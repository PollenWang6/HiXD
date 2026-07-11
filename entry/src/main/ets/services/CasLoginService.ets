// CasLoginService.ets — HTTP 原生 CAS 登录服务
// 替代 WebView 登录，消除 WebView ↔ HttpUtil Cookie 隔离问题
import cryptoFramework from '@ohos.security.cryptoFramework';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import web_webview from '@ohos.web.webview';

export interface CasFormFields { lt: string; execution: string; pwdEncryptSalt: string; }
export interface LibraryAuthResult { userId: string; token: string; }

const TAG = 'CasLoginService';

// ===== 接口定义 =====
export interface SliderPuzzle {
  bigImage: string;
  smallImage: string;
  tagWidth: number;
}

export interface TrackPoint {
  a: number; // x 位移
  b: number; // y 位移
  c: number; // 时间差(ms)
}

interface VerifyRequest {
  canvasLength: number;
  moveLength: number;
  tracks: TrackPoint[];
}

export interface LoginProgress {
  step: string;  // 'form' | 'captcha' | 'verify' | 'login' | 'redirect' | 'done' | 'error'
  message: string;
  percent: number; // 0-100
}

// ===== CasLoginService =====
export class CasLoginService {
  private static instance: CasLoginService;
  private http: HttpUtil = HttpUtil.getInstance();
  private readonly IV_STR: string = 'xidianscriptsxdu'; // 16 字节固定 IV
  private readonly AES_CHARS: string = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  // URL 常量
  private readonly SERVICE_URL: string = 'https://ehall.xidian.edu.cn/login?service=https://ehall.xidian.edu.cn/new/index.html';
  private readonly LOGIN_PAGE: string = 'https://ids.xidian.edu.cn/authserver/login';
  private readonly CAPTCHA_URL: string = 'https://ids.xidian.edu.cn/authserver/common/openSliderCaptcha.htl';
  private readonly VERIFY_URL: string = 'https://ids.xidian.edu.cn/authserver/common/verifySliderCaptcha.htl';

  // 滑块参数
  readonly PUZZLE_WIDTH: number = 280;
  readonly PUZZLE_HEIGHT: number = 155;
  readonly PIECE_HEIGHT: number = 155;
  readonly SLIDER_RIGHT_PADDING: number = 40; // JS 右侧留白

  private constructor() {
  }

  static getInstance(): CasLoginService {
    if (!CasLoginService.instance) {
      CasLoginService.instance = new CasLoginService();
    }
    return CasLoginService.instance;
  }

  // ========== Step 1: 获取 CAS 登录表单隐藏字段 ==========
  async getLoginPageForm(onProgress?: (p: LoginProgress) => void): Promise<CasFormFields> {
    if (onProgress) {
      onProgress({ step: 'form', message: '获取登录页面...', percent: 5 });
    }
    const resp: HttpResponse = await this.http.getNoRedirect(
      this.LOGIN_PAGE + '?service=' + encodeURIComponent(this.SERVICE_URL)
    );

    // CAS 可能先 302 重定向（如果 TGC 有效则直接跳 service），也可能返回 200 登录页
    let body: string = resp.body;
    if (resp.isRedirect && resp.location) {
      // TGC 有效已跳转 → 跟进跳转拿到 MOD_AUTH_CAS
      const finalResp: HttpResponse = await this.http.getNoRedirect(resp.location);
      body = finalResp.body;
    }

    if (body.length === 0) {
      throw new Error('CAS 登录页为空，可能是网络问题');
    }

    const fields: CasFormFields = this.parseHiddenFields(body);
    // lt 可为空（XDU CAS 由 JS 动态赋值，静态 HTML 中 value=""）
    if (!fields.execution) {
      // TGC 有效时 CAS 直接 302 到 service（如 ehall），不会返回登录页
      // ehall 首页 ~90KB，CAS 登录页 ~16KB
      if (body.length > 30000) {
        // 跨域 Cookie 修复：getNoRedirect 按原始 URL（ids）域名存了 ehall 重定向响应的
        // MOD_AUTH_CAS，导致 checkEhallLogin() 找不到 → 反复跳转死循环。
        // 复制到正确的 ehall 域名，并备份到 PreferenceUtil。
        this.http.copyCookiesForDomain('ids.xidian.edu.cn', 'ehall.xidian.edu.cn');
        const ehCookies: string = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
        const modMatch: RegExpMatchArray | null = ehCookies.match(/MOD_AUTH_CAS=([^;]+)/);
        if (modMatch && modMatch[1]) {
          await PreferenceUtil.putString('mod_auth_cas', modMatch[1]);
        }
        await this.http.saveCookies();
        return fields;
      }
      throw new Error('登录页缺少必要字段 (execution)');
    }

    if (onProgress) {
      onProgress({ step: 'form', message: '登录页解析完成', percent: 10 });
    }
    return fields;
  }

  // 解析 hidden input 字段（纯字符串操作，无 DOM parser）
  // 注意：HTML 属性顺序不固定，用 [^>]* 跨越中间属性
  private parseHiddenFields(html: string): CasFormFields {
    const fields: CasFormFields = { lt: '', execution: '', pwdEncryptSalt: '' };
    // execution / pwdEncryptSalt 用 input 标签匹配（已确认可用）
    const exMatch: RegExpMatchArray | null =
      html.match(/<input[^>]*name=["']execution["'][^>]*value=["']([^"']*)["'][^>]*\/?>/i);
    const saltMatch: RegExpMatchArray | null =
      html.match(/<input[^>]*id=["']pwdEncryptSalt["'][^>]*value=["']([^"']*)["'][^>]*\/?>/i);
    if (exMatch) {
      fields.execution = exMatch[1];
    }
    if (saltMatch) {
      fields.pwdEncryptSalt = saltMatch[1];
    }
    // lt: 先搜 <input name="lt" value="..." />，搜不到则搜 LT- 前缀值
    let ltInputMatch: RegExpMatchArray | null =
      html.match(/<input[^>]*name=["']lt["'][^>]*value=["']([^"']*)["'][^>]*\/?>/i);
    if (ltInputMatch) {
      fields.lt = ltInputMatch[1];
    } else {
      const ltDirectMatch: RegExpMatchArray | null = html.match(/(LT-\d+-[A-Za-z0-9]+)/);
      if (ltDirectMatch) {
        fields.lt = ltDirectMatch[1];
      }
    }
    return fields;
  }

  // ========== Step 2: 获取滑块验证码图片 ==========
  async getSliderCaptcha(onProgress?: (p: LoginProgress) => void): Promise<SliderPuzzle> {
    if (onProgress) {
      onProgress({ step: 'captcha', message: '获取验证码...', percent: 15 });
    }

    const url: string = this.CAPTCHA_URL + '?_=' + Date.now().toString();
    // 直接用 getNoRedirect 获取 JSON 响应
    const resp: HttpResponse = await this.http.getNoRedirect(url);

    if (resp.statusCode >= 300 && resp.statusCode < 400) {
      // 被重定向（可能session过期），用普通 get 试试
      const resp2: HttpResponse = await this.http.get(url);
      const puzzle: SliderPuzzle = resp2.json<SliderPuzzle>();
      return puzzle;
    }

    const puzzle: SliderPuzzle = resp.json<SliderPuzzle>();
    if (!puzzle.bigImage || !puzzle.smallImage) {
      throw new Error('验证码图片获取失败');
    }

    if (onProgress) {
      onProgress({ step: 'captcha', message: '验证码获取成功', percent: 20 });
    }
    return puzzle;
  }

  // ========== Step 3: 验证滑块轨迹 ==========
  async verifySliderCaptcha(tracks: TrackPoint[], pieceDataBase64: string): Promise<boolean> {
    const moveLength: number = tracks.length > 0 ? tracks[tracks.length - 1].a : 0;
    const payload: VerifyRequest = {
      canvasLength: this.PUZZLE_WIDTH,
      moveLength: moveLength,
      tracks: tracks
    };

    // 加密 payload
    const encrypted: string = await this.encryptCaptchaPayload(payload, pieceDataBase64);
    const body: string = 'sign=' + encodeURIComponent(encrypted);

    const verifyHeaders: Record<string, string> = {
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Origin': 'https://ids.xidian.edu.cn',
      'X-Requested-With': 'XMLHttpRequest'
    };

    const resp: HttpResponse = await this.http.postRaw(this.VERIFY_URL, body, 'application/x-www-form-urlencoded; charset=UTF-8', verifyHeaders);
    const result: Record<string, Object> = resp.json<Record<string, Object>>();
    const errorCode: number = result['errorCode'] as number;
    return errorCode === 1;
  }

  // ========== Step 4: 提交登录 ==========
  async postLogin(
    username: string,
    password: string,
    fields: CasFormFields,
    onProgress?: (p: LoginProgress) => void
  ): Promise<boolean> {
    if (onProgress) {
      onProgress({ step: 'login', message: '正在提交登录...', percent: 60 });
    }

    const encryptedPwd: string = await this.encryptPassword(password, fields.pwdEncryptSalt);
    const formData: Record<string, string> = {
      'username': username,
      'password': encryptedPwd,
      'rememberMe': 'true',
      'cllt': 'userNameLogin',
      'dllt': 'generalLogin',
      '_eventId': 'submit',
      'lt': fields.lt,
      'execution': fields.execution
    };

    const loginUrl: string = this.LOGIN_PAGE + '?service=' + encodeURIComponent(this.SERVICE_URL);

    // 第一次 POST：使用 raw HTTP POST，手动逐跳跟随重定向链
    // 背景：NETSTACK postNoRedirect 的 headersReceive 在 POST 下可能检测不到 302，
    // 导致 NETSTACK 全程用 POST 跟完所有重定向，最后被 ehall 返回 405。
    // 这里用 getNoRedirect 手动逐跳跟随，确保用 GET 跟 302。

    if (onProgress) {
      onProgress({ step: 'redirect', message: '正在提交登录...', percent: 65 });
    }

    // Step 1: POST 登录表单，NETSTACK 跟完全部重定向（cookie 已在 headersReceive 累积）
    const postResult: HttpResponse = await this.httpPostOneShot(loginUrl,
      this.encodeFormData(formData),
      { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' }
    );

    // 先检查 CAS 返回的错误（冻结、密码错等）
    if (postResult.body.indexOf('账号已被锁定') >= 0 || postResult.body.indexOf('账号已冻结') >= 0 ||
        postResult.body.indexOf('密码错误次数过多') >= 0 || postResult.body.indexOf('locked') >= 0 ||
        postResult.body.indexOf('被锁定') >= 0 || postResult.body.indexOf('被冻结') >= 0) {
      throw new Error('账号已被冻结，请稍后再试');
    }
    if (postResult.body.indexOf('用户名或密码') >= 0 || postResult.body.indexOf('showErrorTip') >= 0) {
      const errMatch: RegExpMatchArray | null = postResult.body.match(/id="showErrorTip"[^>]*>([^<]+)/);
      const errMsg: string = errMatch ? errMatch[1] : '用户名或密码有误';
      throw new Error(errMsg);
    }
    if (postResult.statusCode === 401) {
      throw new Error('用户名或密码有误');
    }

    // 检查 ehall cookie 是否有 MOD_AUTH_CAS
    const ehallCookiePost: string = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (ehallCookiePost.indexOf('MOD_AUTH_CAS') < 0) {
      // 如果上面没检测到具体错误，返回登录页面的前500字帮助调试
      throw new Error('登录失败，请检查账号密码');
    }

    if (onProgress) {
      onProgress({ step: 'redirect', message: '登录处理完成', percent: 80 });
    }

    // 最终检查：ehall 是否有 MOD_AUTH_CAS
    const ehallCookies: string = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    const hasModCas: boolean = ehallCookies.indexOf('MOD_AUTH_CAS') >= 0;

    if (hasModCas) {
      // 再发一次请求确认 ehall 登录状态
      // 注意：ehall 可能还需要一次 GET 完成最终的 cookie 设置
      // 这里发一个轻量请求让 ehall 完成握手
      await this.http.get('https://ehall.xidian.edu.cn/jsonp/getAppUsageMonitor.json?type=uv');

      if (onProgress) {
        onProgress({ step: 'done', message: '登录成功', percent: 90 });
      }

      // 持久化 cookie
      await this.http.saveCookies();
      // 提取并单独保存 MOD_AUTH_CAS
      const modMatch: RegExpMatchArray | null = ehallCookies.match(/MOD_AUTH_CAS=([^;]+)/);
      if (modMatch && modMatch[1]) {
        await PreferenceUtil.putString('mod_auth_cas', modMatch[1]);
      }

      // 保存 ids_account
      if (username.length > 0) {
        await PreferenceUtil.putString('ids_account', username);
      }

      return true;
    }

    return false;
  }

  // ========== 完整登录流程 ==========
  async login(
    username: string,
    password: string,
    onTracks: () => Promise<TrackPoint[]>,
    onProgress?: (p: LoginProgress) => void
  ): Promise<boolean> {
    // Step 1: 获取表单
    const fields: CasFormFields = await this.getLoginPageForm(onProgress);

    // Step 2: 获取验证码
    const puzzle: SliderPuzzle = await this.getSliderCaptcha(onProgress);

    // Step 3: 等用户完成滑块 → 获取轨迹
    if (onProgress) {
      onProgress({ step: 'verify', message: '请拖动滑块完成验证', percent: 25 });
    }
    const tracks: TrackPoint[] = await onTracks();

    // Step 4: 验证滑块
    const verified: boolean = await this.verifySliderCaptcha(tracks, puzzle.smallImage);
    if (!verified) {
      throw new Error('验证码校验失败');
    }

    // Step 5: 提交登录
    return await this.postLogin(username, password, fields, onProgress);
  }

  // ========== 自动登录（TGC 优先 → 密码兜底）==========
  // 不依赖持久化标记，直接用 HTTP 检测真实登录状态
  // 返回值：true=已登录，false=需要手动登录
  async checkAndAutoLogin(): Promise<boolean> {
    // Step 1: TGC 自动恢复（已有 cookie，无需密码）
    try {
      const restored: boolean = await this.tryAutoRestoreLogin();
      if (restored) {
        // Log TGC health for diagnostics
        const tgc = this.http.getAllCookies('ids.xidian.edu.cn');
        const hasCASTGC = tgc.toUpperCase().includes('CASTGC') || tgc.toUpperCase().includes('TGC');
        return true;
      }
    } catch (e) {
    }

    // Step 2: 用保存的密码正式登录
    const username: string = PreferenceUtil.getString('ids_account');
    const password: string = PreferenceUtil.getString('login_password');
    if (username.length === 0 || password.length === 0) {
      return false;
    }

    try {
      // 直接走完整登录流程（需要滑块验证码）
      const success: boolean = await this.login(username, password, async (): Promise<TrackPoint[]> => {
        // 自动登录无法弹滑块，返回空轨迹让 login 知道需要手动
        return [];
      });
      if (success) {
        return true;
      }
    } catch (e) {
    }

    return false;
  }

  // ========== 尝试自动恢复登录（无需密码）==========
  // 如果 CAS TGC (Ticket Granting Cookie) 仍有效，
  // 直接访问 login?service= 就会 302 到 ehall 并签发新 MOD_AUTH_CAS
  async tryAutoRestoreLogin(): Promise<boolean> {
    const serviceUrl: string = encodeURIComponent(this.SERVICE_URL);
    const loginWithService: string = this.LOGIN_PAGE + '?service=' + serviceUrl;

    let currentUrl: string = loginWithService;
    let resp: HttpResponse = await this.http.getNoRedirect(loginWithService);
    let loopGuard: number = 0;

    while (resp.isRedirect && resp.location && loopGuard < 10) {
      let location: string = resp.location;
      // Resolve relative redirect URL against current domain
      let urlCk: RegExpMatchArray | null = currentUrl.match(/^(https?:\/\/[^\/]+)/);
      if (urlCk) {
        let base: string = urlCk[1];
        if (!location.startsWith('http://') && !location.startsWith('https://')) {
          location = base + (location.startsWith('/') ? location : '/' + location);
        }
      }
      currentUrl = location;
      resp = await this.http.getNoRedirect(location);
      loopGuard++;
    }

    // 跨域 Cookie 修复：NETSTACK getNoRedirect 按原始 URL 域名存 cookie，
    // TGC 刷新出的 MOD_AUTH_CAS 会被存到 ids.xidian.edu.cn 下，
    // 但 checkEhallLogin() 查的是 ehall.xidian.edu.cn，需要显式复制。
    this.http.copyCookiesForDomain('ids.xidian.edu.cn', 'ehall.xidian.edu.cn');
    await this.http.saveCookies();

    const ehallCookies: string = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    const hasModCas: boolean = ehallCookies.indexOf('MOD_AUTH_CAS') >= 0;

    if (hasModCas) {
      const modMatch: RegExpMatchArray | null = ehallCookies.match(/MOD_AUTH_CAS=([^;]+)/);
      if (modMatch && modMatch[1]) {
        await PreferenceUtil.putString('mod_auth_cas', modMatch[1]);
      }
      await PreferenceUtil.putBool('is_logged_in', true);
      return true;
    }

    return false;
  }

  // 获取图书馆 userId 和 token（参考 Flutter: 先走 CAS 再跟重定向链）
  async getLibraryAuth(): Promise<LibraryAuthResult | null> {
    const libTarget: string = 'https://hyytsgxzs.xidian.edu.cn/api/index/casLoginDo.html?libraryId=5&openId=o2b1a5Fg6r8hKcL0FXopEkfmiQGc&source=xdbb';
    // 先请求 CAS，带上已有 CAS Cookie，已登录则返回 302
    const casUrl: string = 'https://ids.xidian.edu.cn/authserver/login?service=' + encodeURIComponent(libTarget);

    let resp: HttpResponse = await this.http.get(casUrl);
    let loopGuard: number = 0;

    // 跟随 CAS → library 重定向链（全部用 GET）
    while (resp.isRedirect && resp.location && loopGuard < 10) {
      let nextUrl: string = resp.location;
      resp = await this.http.get(nextUrl);
      loopGuard++;
    }

    // 从最终响应中解析 wx.miniProgram.postMessage
    const body: string = resp.body || '';
    // Flutter 用 matchJson.firstMatch 提取，我们匹配整个 postMessage({...}) 块
    const prefix: string = 'wx.miniProgram.postMessage({';
    const idxStart: number = body.indexOf(prefix);
    if (idxStart < 0) {
      return null;
    }
    const jsonStart: number = idxStart + prefix.length - 1;
    // Flutter: replaceFirst(");", ")") — 去掉末尾分号
    const jsonEnd: number = body.indexOf('})', jsonStart);
    if (jsonEnd < 0) {
      return null;
    }
    let jsonStr: string = body.substring(jsonStart, jsonEnd + 1);
    // Flutter 的处理: replaceFirst("data", "\"data\"") — 给 data 加引号
    jsonStr = jsonStr.replace('data:', '"data":');

    try {
      const obj: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>;
      const data: Record<string, Object> = obj['data'] as Record<string, Object>;
      if (!data) {
        return null;
      }
      const userId: string = String(data['id'] ?? '');
      const token: string = String(data['token'] ?? '');
      if (userId && token) {
        const result: LibraryAuthResult = { userId: userId, token: token };
        await PreferenceUtil.putString('library_user_id', userId);
        await PreferenceUtil.putString('library_token', token);
        return result;
      }
    } catch (parseErr) {
    }
    return null;
  }

  // 清除 WebView 指定域名下的所有 cookie（用 max-age=0 使其过期）
  public clearWebViewCookiesForDomain(domain: string): void {
    const urls = ['https://' + domain, 'http://' + domain];
    for (const u of urls) {
      const old: string = web_webview.WebCookieManager.fetchCookieSync(u);
      if (old.length === 0) continue;
      const oldNames: string[] = [];
      for (const kv of old.split('; ')) {
        const eq: number = kv.indexOf('=');
        if (eq > 0) oldNames.push(kv.substring(0, eq).trim());
      }
      for (const name of oldNames) {
        try {
          web_webview.WebCookieManager.setCookie(u, name + '=; Domain=.xidian.edu.cn; Path=/; max-age=0');
        } catch (e) { /* ignore */ }
      }
    }
  }

  // Sync cookies to WebView CookieJar，覆盖所有 *.xidian.edu.cn 子域名
  async syncCookiesToWebView(): Promise<void> {
    const WCM = web_webview.WebCookieManager;
    const domains: string[] = [
      'ids.xidian.edu.cn',
      'ehall.xidian.edu.cn',
      'xxcapp.xidian.edu.cn',  // 移动门户、水电缴费
      'order.xidian.edu.cn',   // 订水系统
      'sysj.xidian.edu.cn',    // 实验系统
      // ignypt / libspace 对多域 cookie 敏感，不在此处同步，由 PortalWebPage 单独处理
    ];
    // 先清除每个目标域的旧 cookie（避免残留脏 cookie 触发 OpenResty 路由异常）
    for (const domain of domains) {
      this.clearWebViewCookiesForDomain(domain);
    }
    // 收集所有子域名的 cookie
    const sourceDomains: string[] = [
      'ids.xidian.edu.cn',
      'ehall.xidian.edu.cn',
      'xxcapp.xidian.edu.cn',
      'order.xidian.edu.cn',
      'ignypt.xidian.edu.cn',
    ];
    const allCookies: string[] = [];
    for (const src of sourceDomains) {
      const cookies = this.http.getAllCookies(src);
      if (cookies.length > 0) {
        for (const kv of cookies.split('; ')) {
          if (kv.trim().length > 0) allCookies.push(kv.trim());
        }
      }
    }
    // 写 cookie 到所有可能用到的子域名
    const tgcCookies = allCookies.filter(c => c.toUpperCase().includes('TGC') || c.toUpperCase().includes('CASTGC'));
    const hasTGC = tgcCookies.length > 0;
    for (const t of tgcCookies) {
    }
    for (const domain of domains) {
      for (const kv of allCookies) {
        try {
          WCM.setCookie('https://' + domain, kv + '; Domain=.xidian.edu.cn; Path=/');
          if (domain.startsWith('libspace')) {
            WCM.setCookie('http://' + domain, kv + '; Domain=.xidian.edu.cn; Path=/');
          }
        } catch (e) {}
      }
    }
  }

  // Sync only CAS CASTGC cookie to WebView CookieJar — write to ONE domain only.
  // Mimics CAS server behavior: when LoginPage WebView logs in, CASTGC is set
  // on ids.xidian.edu.cn with Domain=.xidian.edu.cn. Chromium auto-sends it to
  // all subdomains naturally. Writing to multiple domains with manual setCookie
  // produces cookie header discrepancies that trigger WAF.
  async syncCasCookieOnly(): Promise<void> {
    const WCM = web_webview.WebCookieManager;
    const idsCookies = this.http.getAllCookies("ids.xidian.edu.cn");
    if (idsCookies.length === 0) {
      return;
    }
    // 只提取 CASTGC，滤掉 route/JSESSIONID 等可能干扰目标域 OpenResty 的 cookie
    const castgcOnly: string[] = [];
    for (const kv of idsCookies.split("; ")) {
      const t = kv.trim();
      if (t.length > 0 && t.toUpperCase().startsWith("CASTGC=")) {
        castgcOnly.push(t);
      }
    }
    if (castgcOnly.length === 0) {
      return;
    }
    // Write ONLY CASTGC to ids.xidian.edu.cn
    // Domain=.xidian.edu.cn ensures Chromium auto-forwards to all subdomains.
    for (const kv of castgcOnly) {
      try {
        WCM.setCookie("https://ids.xidian.edu.cn", kv + "; Domain=.xidian.edu.cn; Path=/");
      } catch (e) { /* ignore */ }
    }

  }
  // For ignypt/libspace: pre-walk the OAuth/redirect chain via HttpUtil
  // to get target domain session cookies, then sync only those to WebView.
  // These services DO NOT use CAS, they have their own session mechanism.
  async preWalkAndSyncTarget(entryUrl: string, targetDomain: string): Promise<void> {
    const startMs = Date.now();
    try {
      await this.http.get(entryUrl);
      const elapsedMs = Date.now() - startMs;
      // Extract cookies from target domain only
      const targetCookies = this.http.getAllCookies(targetDomain);
      // Sync to WebView CookieJar
      const WCM = web_webview.WebCookieManager;
      if (targetCookies.length > 0) {
        for (const kv of targetCookies.split("; ")) {
          const t = kv.trim();
          if (t.length > 0) {
            try {
              WCM.setCookie("https://" + targetDomain, t + "; Path=/");
            } catch (e) { /* ignore */ }
          }
        }
      }
    } catch (e) {
    }
  }

  // 西电 CAS → 超星 统一 SSO：用已有 CAS TGC 走 ids.xidian.edu.cn SSO 进超星，
  // 拿到超星会话 cookie 后注入 WebView，实现"WebView 内免登超星"。
  // 参照 AttendanceService.loginToLearning（native 同款西电→超星 SSO）与 preWalkAndSyncTarget 的注入模式。
  // 调用前需保证 CAS TGC 已在 native cookieStore（通常 checkAndAutoLogin 已恢复）。
  async ensureChaoxingSessionForWebView(): Promise<void> {
    // 1) 用 CAS TGC 走西电→超星 SSO，重定向链会把超星会话 cookie 写入 native jar
    const ssoUrl: string = 'https://ids.xidian.edu.cn/authserver/login?service=' +
      encodeURIComponent('https://xdspoc.fanya.chaoxing.com/sso/xdspoc');
    try {
      await this.http.get(ssoUrl);
    } catch (e) { /* 重定向/超时忽略，cookie 已落 jar */ }

    // 2) 跨子域复制，确保各超星子域都有会话
    const srcDomains: string[] = ['xdspoc.fanya.chaoxing.com', 'ids.xidian.edu.cn', 'fanya.chaoxing.com'];
    const dstDomains: string[] = [
      'office.chaoxing.com',
      'fanya.chaoxing.com',
      'xdspoc.fanya.chaoxing.com',
      'mobilelearn.chaoxing.com',
      'mh.chaoxing.com',
      'passport2.chaoxing.com'
    ];
    for (let i = 0; i < srcDomains.length; i++) {
      for (let j = 0; j < dstDomains.length; j++) {
        this.http.copyCookiesForDomain(srcDomains[i], dstDomains[j]);
      }
    }

    // 3) 把 native jar 里的所有超星 cookie 强制注入 WebView
    //    Domain=.chaoxing.com 覆盖全部子域（含 office.chaoxing.com 座位预约）
    const WCM = web_webview.WebCookieManager;
    for (let k = 0; k < dstDomains.length; k++) {
      const c: string = this.http.getCookiesForDomain(dstDomains[k]);
      if (!c || c.length === 0) { continue; }
      const pairs: string[] = c.split(';');
      for (let p = 0; p < pairs.length; p++) {
        const kv: string = pairs[p].trim();
        if (kv.length === 0) { continue; }
        const eq: number = kv.indexOf('=');
        if (eq <= 0) { continue; }
        const name: string = kv.substring(0, eq);
        const val: string = kv.substring(eq + 1);
        try {
          WCM.setCookie('https://office.chaoxing.com', name + '=' + val + '; Domain=.chaoxing.com; Path=/');
        } catch (e) { /* ignore */ }
      }
    }
  }

  // HTTP 层预热：订水 OAuth 走一遍，xxcapp session 入 HTTP cookieStore，再同步到 WebView
  // 调用时机：登录成功后（HTTP 层已有 TGC），不需要 WebView
  async warmUpWebViewSession(): Promise<void> {
    try {
      // Step 1: warm order OAuth (dingshui)
      const t1 = Date.now();
      await this.http.get("https://order.xidian.edu.cn/mobile/thirdoauth/oauth2Xidian/1");
      // Step 2: warm xxcapp OAuth (portal + dianfei)
      const t2 = Date.now();
      try {
        await this.http.get("https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=https://xxcapp.xidian.edu.cn/site/xidianPage/home");
      } catch (e2) {
      }
      // Step 3: warm v8scan OAuth (校园卡) — 通过 xxcapp 的 CAS bridge
      const t3 = Date.now();
      try {
        await this.http.get("https://xxcapp.xidian.edu.cn/a_xidian/api/cas-login/index?redirect=https%3A%2F%2Fxxcapp.xidian.edu.cn%2Fuc%2Fapi%2Foauth%2Findex%3Fredirect%3Dhttps%253A%252F%252Fv8scan.xidian.edu.cn%252Fhome%252FopenHomePage%26appid%3D200200923164459783");
      } catch (e3) {
      }
      await this.http.saveCookies();
      // Diagnostic: log cookie sizes per domain
      const srcs = ["ids.xidian.edu.cn", "ehall.xidian.edu.cn", "xxcapp.xidian.edu.cn", "order.xidian.edu.cn", "ignypt.xidian.edu.cn", "v8scan.xidian.edu.cn"];
      let diag = "";
      for (const d of srcs) {
        const ck = this.http.getAllCookies(d);
        diag += d + ":" + ck.length + " ";
      }
      await this.syncCookiesToWebView();
    } catch (e) {
    }
  }

  // HTTP 走订水 OAuth → 拿 xxcapp session → 注入 WebView CookieJar
  // 只需 xxcapp 这一个 cookie，不全量同步，轻量精准
  async injectXxcappSession(): Promise<void> {
    try {
      await this.http.get('https://order.xidian.edu.cn/mobile/thirdoauth/oauth2Xidian/1');
      await this.http.saveCookies();
      const xxcappCookies: string = this.http.getAllCookies('xxcapp.xidian.edu.cn');
      if (xxcappCookies.length === 0) {
        return;
      }
      const WCM = web_webview.WebCookieManager;
      for (const kv of xxcappCookies.split('; ')) {
        const trimmed: string = kv.trim();
        if (trimmed.length === 0) continue;
        try {
          WCM.setCookie('https://xxcapp.xidian.edu.cn', trimmed + '; Domain=.xidian.edu.cn; Path=/');
        } catch (_e) { /* ignore */ }
      }
    } catch (e) {
    }
  }

  // ========== 研究生 (yjspt) API ==========

  // 走 CAS OAuth 链建立 yjspt session，自动跟随重定向直到拿到最终页面
  async navigateToYjspt(targetUrl: string): Promise<void> {
    try {
      let currentUrl = targetUrl;
      for (let hop = 0; hop < 8; hop++) {
        const resp = await this.http.getNoRedirect(currentUrl);
        if (!resp.isRedirect || !resp.location) {
          // 已到达最终页面
          await this.http.saveCookies();
          return;
        }
        let next = resp.location;
        if (next.startsWith('/')) {
          const idx = currentUrl.indexOf('/', 8);
          const base = idx > 0 ? currentUrl.substring(0, idx) : 'https://yjspt.xidian.edu.cn';
          next = base + next;
        }
        currentUrl = next;
      }
      await this.http.saveCookies();
    } catch (e) {
    }
  }

  // 登录后检测是否为研究生账号（能否访问 yjspt）→ 设置 role 偏好
  async checkWhetherPostgraduate(): Promise<void> {
    try {
      await this.navigateToYjspt(
        'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/portal/index.do');
      const resp: HttpResponse = await this.http.post(
        'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/modules/pubWork/getCanVisitAppList.do',
        new Object()
      );
      if (resp.statusCode === 200 && resp.body.length > 200) {
        const data: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
        if (data['res'] !== null && data['res'] !== undefined) {
          PreferenceUtil.putBool('role', true);
          return;
        }
      }
      PreferenceUtil.putBool('role', false);
    } catch (e) {
      PreferenceUtil.putBool('role', false);
    }
  }

  // ========== 加密工具 ==========

  // AES 加密密码
  private async encryptPassword(password: string, salt: string): Promise<string> {
    // 构建待加密文本
    const prefix: string = 'xidianscriptsxduxidianscriptsxduxidianscriptsxduxidianscriptsxdu';
    const plainText: string = prefix + password;

    // Key: salt 的 UTF-8 字节（取前 16 字节用于 AES-128）
    const textEncoder: util.TextEncoder = new util.TextEncoder();
    const keyBytes: Uint8Array = textEncoder.encodeInto(salt);
    const key16: Uint8Array = new Uint8Array(16);
    for (let i: number = 0; i < 16; i++) {
      key16[i] = i < keyBytes.length ? keyBytes[i] : 0;
    }

    const ivBytes: Uint8Array = textEncoder.encodeInto(this.IV_STR);

    return await this.aesEncryptBase64(textEncoder.encodeInto(plainText), key16, ivBytes);
  }

  // 加密滑块验证 payload
  private async encryptCaptchaPayload(payload: VerifyRequest, pieceBase64: string): Promise<string> {
    // 从图片末尾提取 AES key（最后 16 字节）
    const textEncoder: util.TextEncoder = new util.TextEncoder();
    const pieceBytes: Uint8Array = this.base64ToUint8Array(pieceBase64);
    const keyBytes: Uint8Array = new Uint8Array(16);
    const startIdx: number = pieceBytes.length - 16;
    for (let i: number = 0; i < 16; i++) {
      keyBytes[i] = pieceBytes[startIdx + i];
    }

    // 随机 IV
    const ivStr: string = this.randomString(16);
    const ivBytes: Uint8Array = textEncoder.encodeInto(ivStr);

    // 随机 nonce
    const nonce: string = this.randomString(64);

    const payloadStr: string = JSON.stringify(payload);
    const plainText: string = nonce + payloadStr;

    return await this.aesEncryptBase64(textEncoder.encodeInto(plainText), keyBytes, ivBytes);
  }

  // AES-CBC 加密 → Base64
  private async aesEncryptBase64(data: Uint8Array, key16: Uint8Array, iv16: Uint8Array): Promise<string> {
    const symKeyGenerator: cryptoFramework.SymKeyGenerator =
      cryptoFramework.createSymKeyGenerator('AES128');
    const keyBlob: cryptoFramework.DataBlob = { data: key16 };
    const symKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey(keyBlob);

    const ivBlob: cryptoFramework.DataBlob = { data: iv16 };
    const ivParams: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: ivBlob
    };

    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS5');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivParams);

    const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: data });
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    return base64Helper.encodeToStringSync(output.data);
  }

  // ========== 工具方法 ==========

  // httpPostOneShot: 用 headersReceive 拦截第一个 302，手动返回重定向信息
  // 不依赖固定的 header key 名（如 statusCode），而是遍历所有 key 找 3 位状态码
  private async httpPostOneShot(
    url: string,
    bodyStr: string,
    headers?: Record<string, string>
  ): Promise<HttpResponse> {
    await this.http.loadCookies();
    return new Promise<HttpResponse>((resolve, reject) => {
      const req = http.createHttp();
      const domain: string = this.extractDomain(url);
      const cookieStr: string = this.http.getCookiesForDomain(domain);

      const reqHeaders: Record<string, string> = {};
      if (headers) {
        for (const key of Object.keys(headers)) {
          reqHeaders[key] = headers[key];
        }
      }
      if (!reqHeaders['User-Agent'] && !reqHeaders['user-agent']) {
        reqHeaders['User-Agent'] =
          'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
      }
      if (cookieStr.length > 0) {
        reqHeaders['Cookie'] = cookieStr;
      }

      let allSetCookies: string = '';
      let lastRedirectLoc: string = '';
      const self: CasLoginService = this;

      // 监听 headersReceive — 累积所有重定向的 cookie（不中断请求）
      req.on('headersReceive', (header: Object) => {
        const hdr: Record<string, string | Object> = header as Record<string, string | Object>;
        // 累积 Set-Cookie
        const setCookie: Object = hdr['set-cookie'] || hdr['Set-Cookie'];
        if (setCookie) {
          const sc: string = typeof setCookie === 'string' ? setCookie : String(setCookie);
          allSetCookies += (allSetCookies.length > 0 ? ',' : '') + sc;
        }
        // 记录最后一个 Location（即最终目标 URL）
        const rawLoc: Object = hdr['location'] || hdr['Location'];
        if (rawLoc) {
          lastRedirectLoc = typeof rawLoc === 'string' ? rawLoc : String(rawLoc);
        }
      });

      req.request(
        url,
        {
          method: http.RequestMethod.POST,
          header: reqHeaders,
          extraData: bodyStr,
          expectDataType: http.HttpDataType.STRING,
          readTimeout: 25000,
          connectTimeout: 15000,
        },
        async (err: BusinessError | undefined, data: http.HttpResponse) => {
          if (err !== undefined && err.code !== 0) {
            req.destroy();
            reject(new Error('HTTP ' + err.code + ': ' + err.message));
            return;
          }
          req.destroy();

          // 存累积的所有重定向 cookie（双写 ids + ehall 域名，MOD_AUTH_CAS 无 Domain 属性需显式指定）
          if (allSetCookies.length > 0) {
            self.http.saveResponseCookies(domain, allSetCookies);
            self.http.saveResponseCookies('ehall.xidian.edu.cn', allSetCookies);
            self.http.saveCookies().catch(() => {
            });
          }

          // 也存最终响应的 cookie（405 等无 body 响应 header 可能为空）
          try {
            const h: Record<string, string> = data.header as Record<string, string>;
            const finalSC: string = (h && (h['set-cookie'] || h['Set-Cookie'])) || '';
            if (finalSC.length > 0) {
              self.http.saveResponseCookies(domain, finalSC);
              self.http.saveResponseCookies('ehall.xidian.edu.cn', finalSC);
              self.http.saveCookies().catch(() => {
              });
            }
          } catch (e) {
            // safe: ignore header parse errors
          }

          const resp: HttpResponse = new HttpResponse();
          resp.statusCode = data.responseCode;
          resp.isRedirect = false;
          resp.body = typeof data.result === 'string' ? data.result : '';
          resp.location = lastRedirectLoc.length > 0 ? lastRedirectLoc : '';
          resolve(resp);
        }
      );
    });
  }

  // 从 URL 提取域名
  private extractDomain(url: string): string {
    const m: RegExpMatchArray | null = url.match(/https?:\/\/([^\/:]+)/);
    return m ? m[1] : '';
  }

  // 编码表单数据
  private encodeFormData(data: Record<string, string>): string {
    const parts: string[] = [];
    for (const key of Object.keys(data)) {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(data[key]));
    }
    return parts.join('&');
  }

  // Base64 → Uint8Array
  private base64ToUint8Array(base64: string): Uint8Array {
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    return base64Helper.decodeSync(base64);
  }

  // 随机字符串
  private randomString(length: number): string {
    const chars: string = this.AES_CHARS;
    const result: string[] = [];
    for (let i: number = 0; i < length; i++) {
      const idx: number = Math.floor(Math.random() * chars.length);
      result.push(chars.charAt(idx));
    }
    return result.join('');
  }

  // 获取滑块图片（供 UI 解码显示）
  getPuzzleImages(puzzle: SliderPuzzle): PuzzleImages {
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    return {
      bigPm: base64Helper.decodeSync(puzzle.bigImage),
      smallPm: base64Helper.decodeSync(puzzle.smallImage)
    };
  }
}

// SliderPuzzle 解码结果
export interface PuzzleImages {
  bigPm: Uint8Array;
  smallPm: Uint8Array;
}
