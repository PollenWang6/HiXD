// CasLoginService.ets — HTTP 原生 CAS 登录服务
// 替代 WebView 登录，消除 WebView ↔ HttpUtil Cookie 隔离问题
import cryptoFramework from '@ohos.security.cryptoFramework';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SecureStorageUtil, SecureAlias } from '../../utils/SecureStorageUtil';
import web_webview from '@ohos.web.webview';
import { image } from '@kit.ImageKit';

export interface CasFormFields { lt: string; execution: string; pwdEncryptSalt: string; }

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

// 解码后的图像：灰度亮度数组 + 原 RGBA（用于 alpha 包围盒）
export interface DecodedImage {
  lum: Float32Array;
  width: number;
  height: number;
  rgba: Uint8Array;
}

interface VerifyRequest {
  canvasLength: number;
  moveLength: number;
  tracks: TrackPoint[];
}

export interface LoginProgress {
  step: string;  // 'form' | 'captcha' | 'verify' | 'login' | 'redirect' | 'done' | 'error' | 'device'
  message: string;
  percent: number; // 0-100
}

// 二次验证（设备验证）需求信号：POST login 后被 CAS 要求走设备验证流程。
// 必须 extends Error，否则触发 arkts-limited-throw（ArkTS 严格模式仅允许抛 Error 子类型）。
export class NeedReAuthError extends Error {
  constructor() {
    super('NEED_REAUTH');
    this.name = 'NeedReAuthError';
  }
}

// ===== 登录失败细分异常（对齐 traintime_pda）=====
export class PasswordWrongException extends Error {
  constructor(msg: string = '用户名或密码有误') {
    super(msg);
    this.name = 'PasswordWrongException';
  }
}

export class AccountLockedException extends Error {
  constructor(msg: string = '账号已被冻结，请稍后再试') {
    super(msg);
    this.name = 'AccountLockedException';
  }
}

export class LoginPageException extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = 'LoginPageException';
  }
}

export class CaptchaException extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = 'CaptchaException';
  }
}

export class ReAuthCancelledException extends Error {
  constructor(msg: string = '设备验证已取消') {
    super(msg);
    this.name = 'ReAuthCancelledException';
  }
}

export class ReAuthExpiredException extends Error {
  constructor(msg: string = '设备验证已失效，请重新登录') {
    super(msg);
    this.name = 'ReAuthExpiredException';
  }
}

export class LoginFailedException extends Error {
  constructor(msg: string = '登录失败，请检查账号密码') {
    super(msg);
    this.name = 'LoginFailedException';
  }
}

// ===== CasLoginService =====
export class CasLoginService {
  private static instance: CasLoginService;
  private http: HttpUtil = HttpUtil.getInstance();
  private readonly IV_STR: string = 'xidianscriptsxdu'; // 16 字节固定 IV
  private readonly AES_CHARS: string = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';
  // POST login 被要求二次验证时 302 重定向到的真实 reAuth 中间页 URL。
  // 形如 reAuthLoginView.do?isMultifactor=true&service=<urlencoded service>
  // 直接裸 GET 常量 REAUTH_VIEW（无 isMultifactor）会被 CAS 返回 500。
  private reAuthViewUrl: string = '';
  // 【关键】CAS 的二次验证上下文是按 service 维度绑定的。
  // 我们 POST 的是 login?service=<ehall>，所以 302 出来的 reAuth 中间页也带 service=<ehall>；
  // 后续 changeReAuthType.do / reAuthSubmit.do 必须回传【同一个】 service，
  // 否则 CAS 只会把"空 service"那份 reAuth 标记为已完成 —— 表现就是：
  // reAuthSubmit 返回"认证成功"、裸 GET /authserver/login 能拿到 CASTGC，
  // 但 GET login?service=<ehall> 依旧原样返回二次验证页（body 长度与中间页完全一致）。
  private reAuthService: string = '';
  // 二次验证因子：3=手机短信，4=企业微信（两者都是收 6 位动态码，都无需离开 App）
  private reAuthFactor: number = 3;
  // 二次验证目标脱敏手机号（服务端 changeReAuthType.do / getDynamicCodeByReauth.do 返回，已脱敏如 138****1234）。
  // 仅用于 UI 展示「验证码已发送至 xxx」，不持久化、不另存明文手机号。
  private reAuthPhoneMasked: string = '';

  // 设备指纹（bfp）：CAS 的「信任此设备 / skipTmpReAuth」是按浏览器指纹(bfp)服务端绑定账号的。
  // 浏览器登录勾选"信任此浏览器"后，该指纹即被服务端登记为受信任，以后同指纹登录免二次验证。
  // App 原生无法运行 CAS 网页的 JS 指纹算法，故改为【按设备】在本地生成并持久化一个稳定指纹：
  // 登录前通过 bfp/info 上报该指纹把会话锚定到此指纹；用户在二次验证页勾选"信任此设备"后，
  // 该指纹被服务端登记为受信任，后续同设备登录即可免二次验证。
  // 指纹是每台设备各自独立的随机值，不再全局硬编码（杜绝多账号共用同一指纹带来的异地告警/风控风险）。
  private static readonly BFP_KEY: string = 'device_bfp';

  // URL 常量
  private readonly SERVICE_URL: string = 'https://ehall.xidian.edu.cn/login?service=https://ehall.xidian.edu.cn/new/index.html';
  private readonly LOGIN_PAGE: string = 'https://ids.xidian.edu.cn/authserver/login';
  private readonly CAPTCHA_URL: string = 'https://ids.xidian.edu.cn/authserver/common/openSliderCaptcha.htl';
  private readonly VERIFY_URL: string = 'https://ids.xidian.edu.cn/authserver/common/verifySliderCaptcha.htl';

  // 二次验证（设备验证）相关接口
  private readonly REAUTH_CHANGE_TYPE: string = 'https://ids.xidian.edu.cn/authserver/reAuthCheck/changeReAuthType.do';
  private readonly REAUTH_SEND_CODE: string = 'https://ids.xidian.edu.cn/authserver/dynamicCode/getDynamicCodeByReauth.do';
  private readonly REAUTH_SUBMIT: string = 'https://ids.xidian.edu.cn/authserver/reAuthCheck/reAuthSubmit.do';
  private readonly REAUTH_VIEW: string = 'https://ids.xidian.edu.cn/authserver/reAuthCheck/reAuthLoginView.do';
  private readonly BFP_URL: string = 'https://ids.xidian.edu.cn/authserver/bfp/info';

  // 滑块参数
  readonly PUZZLE_WIDTH: number = 280;
  readonly PUZZLE_HEIGHT: number = 155;
  readonly PIECE_HEIGHT: number = 155;
  readonly SLIDER_RIGHT_PADDING: number = 40; // JS 右侧留白
  // sigmoid 轨迹归一化常量（复刻 Flutter _genTracksNorm）
  private readonly GEN_TRACKS_NORM: number = 1.0 / (1.0 + Math.exp(-7.0 * (1.0 - 0.42)));

  private constructor() {
  }

  static getInstance(): CasLoginService {
    if (!CasLoginService.instance) {
      CasLoginService.instance = new CasLoginService();
    }
    return CasLoginService.instance;
  }

  // ========== Step 1: 获取 CAS 登录表单隐藏字段 ==========
  // 拉取一次 CAS 登录页 body（处理 TGC 有效时直接 302 到 service 的情况）
  private async fetchLoginBody(): Promise<string> {
    const r: HttpResponse = await this.http.getNoRedirect(
      this.LOGIN_PAGE + '?service=' + encodeURIComponent(this.SERVICE_URL)
    );
    let b: string = r.body;
    if (r.isRedirect && r.location) {
      const finalResp: HttpResponse = await this.http.getNoRedirect(r.location);
      b = finalResp.body;
    }
    return b;
  }

  async getLoginPageForm(onProgress?: (p: LoginProgress) => void): Promise<CasFormFields> {
    if (onProgress) {
      onProgress({ step: 'form', message: '获取登录页面...', percent: 5 });
    }

    let body: string = await this.fetchLoginBody();

    if (body.length === 0) {
      throw new LoginPageException('CAS 登录页为空，可能是网络问题');
    }

    let fields: CasFormFields = this.parseHiddenFields(body);
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

      // 拿不到 execution 且不是 ehall 首页：CAS 可能把会话推进到了“二次验证中间态”
      // （例如此前获取过短信验证码但未完成校验，服务端记住了这个 session 状态），
      // 直接返回 reAuth 中间页而不是带 execution 的登录页，导致滑块永远出不来。
      // 清掉 ids 域会话 cookie 后重试一次，让 CAS 重新下发干净的登录页。
      const looksReAuth: boolean = body.toLowerCase().includes('reauth') ||
        body.includes('二次认证') || body.includes('设备验证') || body.includes('动态码');
      if (looksReAuth || body.length < 3000) {
        await this.http.clearCookies('ids.xidian.edu.cn');
        body = await this.fetchLoginBody();
        fields = this.parseHiddenFields(body);
        if (fields.execution) {
          return fields;
        }
      }

      // 重试仍失败 → 抛出明确错误，避免滑块永久卡死无提示
      const snippet: string = body.length > 0 ? body.slice(0, 160).replace(/\s+/g, ' ') : '(空响应)';
      throw new LoginPageException('登录页异常，验证码无法显示。若此前获取过短信验证码，请退出应用重进，或清除登录缓存后重试。诊断：' + snippet);
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
      throw new CaptchaException('验证码图片获取失败');
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

  // ========== Step 3.5: 自动滑块求解（复刻 Flutter slider_captcha_client.dart）==========
  // 自动过滑块：拉图 → NCC 算缺口 → 邻域微调 → 拟人轨迹 → verify。
  // 成功返回 true；全失败返回 false（调用方应 fallback 到手动拖动 UI）。
  // 注：本方法只负责「滑块验证」这一步，后续仍需 postLogin 提交账号密码表单。
  //
  // ⚠️ 2026-09-06 失败收敛策略重写（真机日志 F1[18146] 实锤）：
  //   旧实现每张图一口气试 15 个邻域点（含 ±0.5/±1.5 亚像素），40 秒内对同一会话
  //   连发 56 次 verify 全败、登录卡 5% 死循环。CAS 滑块验证上下文在一次 verify
  //   失败后即被服务端作废并对会话打风控标记——同图/同会话后续 verify 全是必败
  //   请求，试得越多死得越快（重开 App 新会话 3 次即过，证明非数据损坏）。
  //   对齐 Flutter solve()：每轮【换新图】、每图只试少量整数邻域、失败立即换图重来。
  //   ① 邻域收敛为整数 ±0..3（NCC 亚像素误差由整数吸收，0.5 步长无意义且徒增请求）；
  //   ② 连续 8 次被拒 = 会话已被风控 → 立即 false 交还手动拖动（真人一次即可过）；
  //   ③ 总 verify 保险丝 28 次，防极端死循环。
  async autoSolveSlider(maxRounds: number = 6, onProgress?: (p: LoginProgress) => void): Promise<boolean> {
    // 整数邻域（Flutter 用 [1,-1,2,-2,3,-3,4]，此处加 0 覆盖直落，最多 7 点/图）
    const deltas: number[] = [0, 1, -1, 2, -2, 3, -3];
    const MAX_TOTAL_VERIFY: number = 28;  // 全局保险丝：28 次仍不过 → 判定失败交还手动
    const MAX_CONSECUTIVE_FAIL: number = 8; // 连续被拒 8 次 → 会话已被风控，快速交还手动
    let totalVerify: number = 0;
    let consecutiveFail: number = 0;
    for (let round: number = 0; round < maxRounds; round++) {
      if (onProgress) {
        onProgress({ step: 'captcha', message: '正在进行滑块验证...', percent: Math.min(20 + round * 5, 50) });
      }
      if (totalVerify >= MAX_TOTAL_VERIFY) {
        return false;
      }
      let puzzle: SliderPuzzle;
      try {
        puzzle = await this.getSliderCaptcha();
      } catch (_e) {
        // 拉图失败（网络抖动/频率风控）→ 稍等换下一张，不中断整轮
        await this.delay(500);
        continue;
      }
      const offset: number | null = await this.solveOffset(puzzle.bigImage, puzzle.smallImage);
      if (offset === null) {
        await this.delay(300);
        continue;
      }
      const baseMove: number = offset * this.PUZZLE_WIDTH; // 保留浮点精度，整数邻域吸收取整误差
      let solved: boolean = false;
      for (const delta of deltas) {
        const move: number = baseMove + delta;
        if (move < 1 || move > this.PUZZLE_WIDTH - 1) {
          continue;
        }
        // ⚠️ 真人节奏：每次 verify 前睡眠 400~900ms（对齐 Flutter solve() 的
        // sleep(tracks.last.c-100) 思路）。高频连发会被 CAS 风控判为非人类。
        await this.delay(400 + Math.floor(Math.random() * 500));
        const tracks: TrackPoint[] = this.generateTracks(move);
        totalVerify++;
        try {
          if (await this.verifySliderCaptcha(tracks, puzzle.smallImage)) {
            solved = true;
            break;
          }
          consecutiveFail++;
          if (consecutiveFail >= MAX_CONSECUTIVE_FAIL) {
            // 连续 8 次被 CAS 拒（F1[18146] 实证：56 连败卡 5%）→ 本会话已被风控，
            // 继续自动尝试纯属浪费，立即交还手动拖动（真人拖一次即可过）。
            return false;
          }
        } catch (_e) {
          // 单次 verify 网络异常：不累计连败（非服务端拒绝），继续下一邻域
        }
      }
      if (solved) {
        return true;
      }
      // 本轮未过：换图也需人类节奏，过快换图同样触发频率风控
      await this.delay(1000 + Math.floor(Math.random() * 600));
    }
    return false;
  }

  // 解码 base64 图像 → 灰度亮度数组 + 原 RGBA（用于 alpha 包围盒）
  private async decodeImage(b64: string): Promise<DecodedImage | null> {
    let raw: string = b64;
    const commaIdx: number = b64.indexOf(',');
    if (commaIdx >= 0 && b64.substring(0, commaIdx).indexOf('base64') >= 0) {
      raw = b64.substring(commaIdx + 1);
    }
    let bytes: Uint8Array;
    try {
      bytes = this.base64ToUint8Array(raw);
    } catch (e) {
      return null;
    }
    const buf: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    let src: image.ImageSource;
    try {
      src = image.createImageSource(buf);
    } catch (e) {
      return null;
    }
    let pm: image.PixelMap;
    try {
      pm = await src.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.BGRA_8888 });
    } catch (e) {
      return null;
    }
    const info: image.ImageInfo = await pm.getImageInfo();
    const w: number = info.size.width;
    const h: number = info.size.height;
    if (w <= 0 || h <= 0) {
      return null;
    }
    const out: ArrayBuffer = new ArrayBuffer(w * h * 4);
    try {
      await pm.readPixelsToBuffer(out);
    } catch (e) {
      return null;
    }
    const rgba: Uint8Array = new Uint8Array(out);
    const lum: Float32Array = new Float32Array(w * h);
    for (let i: number = 0; i < w * h; i++) {
      const r: number = rgba[i * 4 + 2];
      const g: number = rgba[i * 4 + 1];
      const b: number = rgba[i * 4 + 0];
      lum[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }
    return { lum: lum, width: w, height: h, rgba: rgba };
  }

  // NCC 模板匹配求缺口归一化偏移（逐字节复刻 Flutter solveOffset，border=24 内缩）
  private async solveOffset(bigB64: string, smallB64: string): Promise<number | null> {
    const big: DecodedImage | null = await this.decodeImage(bigB64);
    if (!big) {
      return null;
    }
    const piece: DecodedImage | null = await this.decodeImage(smallB64);
    if (!piece) {
      return null;
    }
    const wBig: number = big.width;
    const hBig: number = big.height;
    const wPiece: number = piece.width;
    const hPiece: number = piece.height;

    // 1) piece 中 alpha>=250 像素包围盒（拼图实体）
    let xL: number = wPiece, yT: number = hPiece, xR: number = 0, yB: number = 0;
    for (let y: number = 0; y < hPiece; y++) {
      for (let x: number = 0; x < wPiece; x++) {
        const a: number = piece.rgba[(y * wPiece + x) * 4 + 3];
        if (a >= 250) {
          if (x < xL) xL = x;
          if (y < yT) yT = y;
          if (x > xR) xR = x;
          if (y > yB) yB = y;
        }
      }
    }
    if (xR < xL || yB < yT) {
      return null;
    }
    const border: number = 8;
    xL = xL + border; yT = yT + border;
    xR = xR - border; yB = yB - border;
    // clamp 到合法范围（防止 border 过大导致负窗口）
    xL = Math.max(0, xL); yT = Math.max(0, yT);
    xR = Math.min(wPiece - 1, xR); yB = Math.min(hPiece - 1, yB);
    const windowWidth: number = xR - xL + 1;
    const windowHeight: number = yB - yT + 1;
    if (windowWidth <= 0 || windowHeight <= 0) {
      return null;
    }

    const bigWidth: number = wBig - wPiece + windowWidth;
    if (bigWidth <= windowWidth) {
      return null;
    }

    // 2) template = piece 窗口内零均值亮度
    const tArea: number = windowWidth * windowHeight;
    let templateSum: number = 0;
    for (let y: number = yT; y < yT + windowHeight; y++) {
      for (let x: number = xL; x < xL + windowWidth; x++) {
        templateSum += piece.lum[y * wPiece + x];
      }
    }
    const templateMean: number = templateSum / tArea;
    const template: Float32Array = new Float32Array(tArea);
    let ti: number = 0;
    for (let y: number = yT; y < yT + windowHeight; y++) {
      for (let x: number = xL; x < xL + windowWidth; x++) {
        template[ti++] = piece.lum[y * wPiece + x] - templateMean;
      }
    }

    // 3) 大图列和（窗口高度内每列亮度累加），用于滑动窗口 O(1) 增量
    const columnSums: Float32Array = new Float32Array(bigWidth);
    for (let x: number = 0; x < bigWidth; x++) {
      let s: number = 0;
      const col: number = x + xL;
      for (let y: number = yT; y < yT + windowHeight; y++) {
        s += big.lum[y * wBig + col];
      }
      columnSums[x] = s;
    }

    let windowSum: number = 0;
    for (let x: number = 0; x < windowWidth; x++) {
      windowSum += columnSums[x];
    }
    const area: number = tArea;

    const nccAt: (startX: number, wSum: number) => number = (startX: number, wSum: number): number => {
      const meanW: number = wSum / area;
      let sumWt: number = 0;
      let sumWw: number = 0.000001;
      let it: number = 0;
      for (let y: number = yT; y < yT + windowHeight; y++) {
        const rowBase: number = y * wBig + startX;
        for (let x: number = 0; x < windowWidth; x++) {
          const wv: number = big.lum[rowBase + x] - meanW;
          sumWt += wv * template[it++];
          sumWw += wv * wv;
        }
      }
      return sumWt / sumWw;
    };

    let nccMax: number = nccAt(0 + xL, windowSum / area);
    let xMax: number = 0;
    for (let x: number = 1; x < bigWidth - windowWidth; x++) {
      windowSum += columnSums[x + windowWidth - 1] - columnSums[x - 1];
      const ncc: number = nccAt(x + xL, windowSum / area);
      if (ncc > nccMax) {
        nccMax = ncc;
        xMax = x;
      }
    }
    return xMax / wBig;
  }

  // 拟人拖拽轨迹：水平位移走 sigmoid 缓动，时间戳单调递增且为人类拖拽节奏（核心风控点）
  private generateTracks(offs: number): TrackPoint[] {
    const target: number = Math.max(1, Math.round(offs));
    const tracks: TrackPoint[] = [{ a: 0, b: 0, c: 0 }];
    const n: number = Math.floor(Math.random() * 5) + 12; // 12~16 个采样点
    let b: number = 0;
    // 总拖拽时长随机落在人类区间 900~1600ms，逐点单调递增 + 小抖动
    const totalMs: number = 900 + Math.floor(Math.random() * 700);
    let elapsed: number = 0;
    for (let i: number = 0; i < n; i++) {
      const z: number =
        (1.0 / (1.0 + Math.exp(-7.0 * ((i / n) - 0.42)))) / this.GEN_TRACKS_NORM;
      // 期望位置（sigmoid 缓动），夹在 [上一点+1, 目标-1] 内保证单调前进
      let nextA: number = Math.round(target * z);
      nextA = Math.min(target - 1, Math.max(tracks[tracks.length - 1].a + 1, nextA));
      const r: number = Math.random();
      if (r < 0.65) {
        b = b - 1;
      } else if (r < 0.80) {
        b = b + 1;
      }
      b = Math.max(-10, Math.min(10, b));
      // 时间戳：按进度均分总时长 + ±12ms 抖动，保证单调递增且间隔人类化
      elapsed = Math.round((i + 1) / (n + 1) * totalMs) + (Math.floor(Math.random() * 25) - 12);
      elapsed = Math.max(tracks[tracks.length - 1].c + 8, elapsed); // 至少间隔 8ms
      tracks.push({ a: nextA, b: b, c: elapsed });
    }
    // 终点：精确落在目标像素，时间戳 = 总时长（收尾停顿）
    tracks.push({ a: target, b: b, c: totalMs });
    return tracks;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  // ========== Step 4: 提交登录 ==========
  // 复刻浏览器信任态：向 CAS 上报「受信任浏览器」指纹，使后续登录免二次验证。
  // 取本设备持久化的浏览器指纹；首次运行时用安全随机数生成 32 位十六进制指纹并存储。
  private getDeviceBfp(): string {
    let bfp: string = PreferenceUtil.getString(CasLoginService.BFP_KEY);
    if (!/^[0-9A-Fa-f]{32}$/.test(bfp)) {
      bfp = util.generateRandomUUID().replace(/-/g, '').toUpperCase();
      PreferenceUtil.putString(CasLoginService.BFP_KEY, bfp);
    }
    return bfp;
  }

  // 登录前上报本设备指纹，复刻浏览器"信任"态：
  // 实测（Python 实证脚本）：不发的会话 POST login 必被截到 reAuthLoginView；
  // 发后（同一 HttpUtil 共享会话）POST login 直接 302 到 ehall 签 MOD_AUTH_CAS，全程零二次验证。
  private async sendBfp(): Promise<void> {
    const bfp: string = this.getDeviceBfp();
    if (bfp.length === 0) {
      return;
    }
    const url: string = this.BFP_URL + '?bfp=' + bfp + '&_=' + Date.now();
    try {
      await this.http.getNoRedirect(url, {
        'Referer': this.LOGIN_PAGE,
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json, text/javascript, */*; q=0.01'
      });
    } catch (e) {
    }
  }

  async postLogin(
    username: string,
    password: string,
    fields: CasFormFields,
    onProgress?: (p: LoginProgress) => void,
    onReAuthNeeded?: (username: string, onProgress?: (p: LoginProgress) => void) => Promise<boolean>,
    skipReAuth?: boolean
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
    // HAR 实测 [42]：浏览器 POST 登录表单时带 Origin + Referer，CAS 在二次验证场景下
    // 依赖它们关联 login 上下文，这里一并对齐。

    // 🔑 一次性登录：登录前先发 bfp/info 复刻浏览器信任态（同一 HttpUtil 会话，让 CAS 把本会话锚定到受信任指纹）
    await this.sendBfp();

    const postResult: HttpResponse = await this.httpPostOneShot(loginUrl,
      this.encodeFormData(formData),
      {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Origin': 'https://ids.xidian.edu.cn',
        'Referer': this.LOGIN_PAGE
      }
    );

    // 先检查 CAS 返回的错误（冻结、密码错等）
    // ⚠️ 2026-09-06 对齐 Flutter _parsePasswordWrongMsg：错误分类以 #showErrorTip 的
    // 【实际文本】为准。此前用"body 含 showErrorTip 元素"当密码错信号，但该空容器
    // 常驻登录页模板，导致账号冻结/风险提示页（body 必然带此元素）被误报成
    // "用户名或密码有误"，用户分不清到底是密码错还是账号被冻结。
    const errTip: string = this.extractErrorTip(postResult.body);
    const lowBody: string = postResult.body.toLowerCase();
    if (lowBody.indexOf('账号已被锁定') >= 0 || lowBody.indexOf('账号已冻结') >= 0 ||
        lowBody.indexOf('密码错误次数过多') >= 0 || lowBody.indexOf('locked') >= 0 ||
        lowBody.indexOf('被锁定') >= 0 || lowBody.indexOf('被冻结') >= 0 ||
        errTip.indexOf('锁') >= 0 || errTip.indexOf('冻结') >= 0 || errTip.indexOf('次数过多') >= 0) {
      throw new AccountLockedException('账号已被冻结，请稍后再试');
    }
    // 凭证错误 / 其他失败：透传 CAS 真实文案（对齐 Flutter），避免吞掉具体原因
    if (postResult.statusCode === 401 || errTip.length > 0) {
      let reason: string = errTip.length > 0 ? errTip : '用户名或密码有误';
      if (reason.indexOf('用户名') >= 0 || reason.indexOf('密码') >= 0) {
        reason = '用户名或密码有误';
      }
      throw new PasswordWrongException(reason);
    }

    // 检查 ehall cookie 是否有 MOD_AUTH_CAS
    const ehallCookiePost: string = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (ehallCookiePost.indexOf('MOD_AUTH_CAS') < 0) {
      // 被 CAS 要求走二次验证（设备验证）：触发 reAuth 流程
      if (this.isReAuthRequired(postResult)) {
        if (skipReAuth) {
          // 重新提交登录后仍被截到二次验证 → 说明设备信任未真正生效，直接失败让用户重试
          throw new ReAuthExpiredException('设备验证已提交，但登录态仍未建立，请重试登录');
        }
        if (!onReAuthNeeded) {
          throw new NeedReAuthError();
        }
        // 捕获 POST login 302 重定向到的真实 reAuth 中间页 URL，供 startReAuth 建立 reAuth 会话态。
        // 直接 GET 常量 REAUTH_VIEW（缺 isMultifactor）会被 CAS 返回 500。
        this.reAuthViewUrl = postResult.location || '';
        // 从中间页 URL 上原样摘出 service（保持 URL 编码形式，后续原样回传给 CAS）
        this.reAuthService = this.extractServiceParam(this.reAuthViewUrl);
        const ok: boolean = await onReAuthNeeded(username, onProgress);
        if (!ok) {
          throw new ReAuthCancelledException('设备验证未完成，登录已取消');
        }
        // 设备已信任，重新提交登录以拿到最终登录态（MOD_AUTH_CAS）
        return await this.completeLoginAfterReAuth(username, onProgress);
      } else {
        // POST 登录链可能被 NETSTACK 以 POST 跟随 302 一路打到 ehall，触发 405（日志实证 18:08:14），
        // 但 CASTGC 已在前面某跳写入 cookie 罐。补一次干净的 GET 恢复，让 CAS 用 TGC 签发 ST→MOD_AUTH_CAS，
        // 可消除“第一次点击报‘请检查账号密码’、第二次才进（无滑块）”的现象。
        let restored: boolean = await this.tryAutoRestoreLogin();
        if (!restored) {
          restored = await this.tryAutoRestoreLogin(); // 偶发时序重试一次（不清除 cookie，TGC 不丢）
        }
        if (!restored) {
          // 如果上面没检测到具体错误，返回登录页面的前500字帮助调试
          throw new LoginFailedException('登录失败，请检查账号密码');
        }
        // restored=true → 继续走下方成功收尾（hasModCas 现已为 true）
      }
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
      // 这里发一个轻量请求让 ehall 完成握手，并读返回体校验 hasLogin。
      // 对齐 Flutter loginEhall：统一认证成功但 ehall 侧会话未建立时明确抛错，
      // 而不是仅凭本地 MOD_AUTH_CAS 存在就判定登录成功（否则用户进业务页才发现没进去）。
      // ⚠️ 2026-09-06 修复：本确认请求是 ehall 业务域，postLogin 自身处于登录流程中
      //（loginStatus 尚未置 ok），必须与 sendBfp/POST login 一样绕过 offline 守卫。
      // 此前 LoginPage 手动登录路径在此被 sessionRestoreHandler 拦截（MainPage 已被
      // replace 销毁、handler=null）→ postLogin 抛"当前未登录校园账号"→ 协议层
      // 明明登录成功（ST+ehall 200）但 UI 一直停在登录页（真机日志：getAppUsageMonitor 0 次）。
      const confirmResp: HttpResponse = await HttpUtil.withNoOfflineCheck(async (): Promise<HttpResponse> => {
        return await this.http.get(
          'https://ehall.xidian.edu.cn/jsonp/getAppUsageMonitor.json?type=uv');
      });
      const confirmMatch: RegExpMatchArray | null =
        confirmResp.body.match(/"hasLogin"\s*:\s*(true|false)/);
      if (!confirmMatch || confirmMatch[1] !== 'true') {
        throw new LoginFailedException('统一认证成功，但一站式大厅登录状态校验失败');
      }

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
      // 保险：持久化登录密码，确保后续自动重登录/滑块路径能拿到有效密码，
      // 避免本地密码丢失后提交空密码触发“密码错误”死循环
      if (password && password.length > 0) {
        SecureStorageUtil.put(SecureAlias.LOGIN_PASSWORD, password).catch(() => {});
      }

      return true;
    }

    return false;
  }

  // ========== 二次验证（设备验证）相关 ==========
  // 解析 CAS 错误页 #showErrorTip 的文本内容（对齐 Flutter _parsePasswordWrongMsg）。
  // ⚠️ 该元素是常驻空容器（无错误时也存在于登录页模板），必须取其【实际文本】，
  // 绝不能拿"页面含 showErrorTip 元素"当失败信号——否则账号冻结/风险提示等
  // 非密码错误会被误报成"用户名或密码有误"（2026-09-06 对照 Flutter 定位）。
  private extractErrorTip(body: string): string {
    const m: RegExpMatchArray | null = body.match(/id="showErrorTip"[^>]*>\s*([^<]{1,300}?)\s*</);
    if (!m) {
      return '';
    }
    return m[1].trim();
  }
  // 二次验证判定（对齐 Flutter isIDSReAuthLocation）：
  // ⚠️ 只认 CAS 302 跳转目标路径 === /authserver/reAuthCheck/reAuthLoginView.do。
  // 严禁扫响应 body 关键词：账号锁定页/登录失败页/普通登录页模板的 JS 里常驻
  // 'reauth'/'二次认证'/'动态码'/'多因子' 等字样（含隐藏表单与静态资源引用），
  // 扫 body 会把普通登录失败（如账号被锁）误判成“需要二次验证”→ 强跑短信流程，
  // 但 CAS 根本不处于 reAuth 态 → 永远收不到验证码（2026-09-06 线上实证）。
  private isReAuthLocation(loc: string): boolean {
    if (!loc) return false;
    const idx: number = loc.indexOf('/authserver/');
    if (idx < 0) return false;
    return loc.substring(idx).startsWith('/authserver/reauthcheck/reauthloginview.do');
  }

  // 判断 CAS 是否因二次认证拦截了登录（仅依据 POST 后 302 目标，见 isReAuthLocation 注释）
  private isReAuthRequired(postResult: HttpResponse): boolean {
    return this.isReAuthLocation((postResult.location || '').toLowerCase());
  }

  // 登录“成功”后复查：设备验证是否仍以 step-up 形式 pending（信任设备被删场景）。
  // 对齐 Flutter followIDSRedirects / resolveIDSReAuthIfNeeded：每次关键请求后都复查是否跳到 reAuthLoginView。
  // 某些情况下 CAS 在登录 POST 这步不拦截（直接签发 MOD_AUTH_CAS），把设备验证推迟到真正访问
  // 受保护资源时才跳 reAuthLoginView；此探查在登录后立即再走一遍“访问受保护资源”的流程，
  // 把它提前揪出来，避免“过了滑块就判成功、却没弹验证码”的 bug。
  async detectPendingReAuth(): Promise<boolean> {
    try {
      const serviceUrl: string = encodeURIComponent(this.SERVICE_URL);
      const loginWithService: string = this.LOGIN_PAGE + '?service=' + serviceUrl;
      let resp: HttpResponse = await this.http.getNoRedirect(loginWithService, this.pageHeaders(this.LOGIN_PAGE));
      let currentUrl: string = loginWithService;
      let loopGuard: number = 0;
      while (resp.isRedirect && resp.location && loopGuard < 10) {
        let location: string = resp.location;
        const m: RegExpMatchArray | null = currentUrl.match(/^(https?:\/\/[^\/]+)/);
        if (m) {
          const base: string = m[1];
          if (!location.startsWith('http://') && !location.startsWith('https://')) {
            location = base + (location.startsWith('/') ? location : '/' + location);
          }
        }
        // 逐跳复查（对齐 Flutter resolveIDSReAuthIfNeeded）：任一跳 302 指向 reAuth 中间页即命中
        if (this.isReAuthLocation(location.toLowerCase())) {
          return true;
        }
        currentUrl = location;
        resp = await this.http.getNoRedirect(location, this.pageHeaders(this.LOGIN_PAGE));
        loopGuard++;
      }
      // 循环退出（非 302 终止）后复查最后一跳
      return this.isReAuthLocation((resp.location || '').toLowerCase());
    } catch (e) {
      // 网络异常时保守返回 false（不误触发验证码弹窗，交给现有过期/重试逻辑兜底）
      return false;
    }
  }

  // 二次验证请求头（CAS 校验 X-Requested-With）
  // 【关键】Referer 必须是 reAuth 中间页 URL：HAR 实测浏览器的
  // changeReAuthType / getDynamicCodeByReauth / reAuthSubmit 三个请求
  // 全都带 Referer: .../reAuthCheck/reAuthLoginView.do?isMultifactor=true。
  // CAS 靠它把本次 reAuth 关联到对应的 login 上下文；缺了它虽然会返回
  // "认证成功"，但通过标记落不到当前 session，导致之后 GET login 仍被打回验证页。
  private reAuthHeaders(): Record<string, string> {
    const ref: string = this.reAuthViewUrl.length > 0 ? this.reAuthViewUrl : this.REAUTH_VIEW;
    return {
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Origin': 'https://ids.xidian.edu.cn',
      'Referer': ref,
      'X-Requested-With': 'XMLHttpRequest'
    };
  }

  // 浏览器访问 CAS 页面时的通用 HTML 请求头（含 Referer）
  private pageHeaders(referer: string): Record<string, string> {
    return {
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Referer': referer
    };
  }

  // 从 reAuth 中间页 URL 上原样摘出 service 参数（保持 URL 编码形式）
  private extractServiceParam(url: string): string {
    const m: RegExpMatchArray | null = url.match(/[?&]service=([^&]*)/);
    return m && m[1] ? m[1] : '';
  }

  // 当前因子对应的动态码类型名（实测 HAR：短信=reAuthDynamicCodeType，企业微信=reAuthWChatDynamicCodeType）
  private authCodeTypeName(): string {
    return this.reAuthFactor === 4 ? 'reAuthWChatDynamicCodeType' : 'reAuthDynamicCodeType';
  }

  // 当前因子的收码渠道文案
  reAuthChannelText(): string {
    return this.reAuthFactor === 4 ? '企业微信' : '手机短信';
  }

  // 二次验证目标脱敏手机号（UI 展示用），无则返回空串
  getReAuthPhoneMasked(): string {
    return this.reAuthPhoneMasked;
  }

  // 切换二次验证因子（3=短信，4=企业微信），由 UI 在发码前调用
  setReAuthFactor(factor: number): void {
    this.reAuthFactor = factor === 4 ? 4 : 3;
  }

  // 向已登录账号发送二次验证动态码（短信 / 企业微信）
  async sendReAuthCode(username: string, onProgress?: (p: LoginProgress) => void): Promise<void> {
    if (onProgress) {
      onProgress({ step: 'device', message: '正在发送验证码...', percent: 72 });
    }
    const body: string = 'userName=' + encodeURIComponent(username) +
      '&authCodeTypeName=' + this.authCodeTypeName();
    const resp: HttpResponse = await this.http.postRaw(
      this.REAUTH_SEND_CODE,
      body,
      'application/x-www-form-urlencoded; charset=UTF-8',
      this.reAuthHeaders()
    );
    // 兜底解析脱敏手机号（getDynamicCodeByReauth.do 返回 mobile，如 138****1234）
    // 企业微信因子不发 changeReAuthType，这里可补到号码；短信因子优先取 changeReAuthType 的 reAuthUserNameInput
    try {
      const sendJson: Record<string, Object> = resp.json<Record<string, Object>>();
      const mob: string = sendJson['mobile'] as string;
      if (mob && mob.length > 0 && this.reAuthPhoneMasked.length === 0) {
        this.reAuthPhoneMasked = mob;
      }
    } catch (_e) {
      // 解析失败不影响发码流程
    }
    if (onProgress) {
      onProgress({ step: 'device', message: '验证码已发送，请查收' + this.reAuthChannelText(), percent: 73 });
    }
  }

  // 步骤1：初始化并开始二次验证（供 UI 在用户点击“获取验证码”时调用）
  // 关键：真实浏览器流程是 POST login → 302 reAuthLoginView → 先 GET 该中间页建立 reAuth 会话态
  // → 再 changeReAuthType → 发码 → 提交。之前直接 changeReAuthType 很可能因会话态不完整被 CAS 静默拒绝，
  // 导致 reAuthSubmit 之后登录态建不起来（tryAutoRestoreLogin 仍跟到 reAuth 中间页）。这里补上 GET 中间页。
  async startReAuth(username: string, onProgress?: (p: LoginProgress) => void): Promise<void> {
    if (onProgress) {
      onProgress({ step: 'device', message: '正在初始化设备验证...', percent: 70 });
    }
    // 1) 加载二次验证中间页，建立/补全 reAuth 会话态
    //    必须用 POST login 实际重定向到的真实 reAuthLoginView URL（带会话 token），
    //    直接裸 GET 常量 REAUTH_VIEW 会被 CAS 返回 500（缺少会话上下文）。
    let viewUrl: string = this.reAuthViewUrl;
    if (!viewUrl || viewUrl.length === 0) {
      viewUrl = this.REAUTH_VIEW;
    }
    try {
      // HAR 实测 [43]：浏览器 GET 中间页时 Referer 是 https://ids.xidian.edu.cn/authserver/login
      const viewResp: HttpResponse = await this.http.getNoRedirect(viewUrl, this.pageHeaders(this.LOGIN_PAGE));
    } catch (e) {
    }
    if (onProgress) {
      onProgress({ step: 'device', message: '正在选择验证方式...', percent: 71 });
    }
    // 2) 选择认证方式。
    //    短信(3)：浏览器裸登门户时 changeReAuthType 的 service 为空（落地点是门户非 ehall）；我们 App 入口带 service=ehall，
    //    企业微信(4)：实测 HAR 里浏览器【根本不发】 changeReAuthType.do，直接发码；
    //                多发这一发会把服务端因子状态改回去，所以这里必须跳过。
    if (this.reAuthFactor !== 4) {
      const chResp: HttpResponse = await this.http.postRaw(
        this.REAUTH_CHANGE_TYPE,
        'isMultifactor=true&reAuthType=3&service=' + this.reAuthService,
        'application/x-www-form-urlencoded; charset=UTF-8',
        this.reAuthHeaders()
      );
      // 解析脱敏手机号（changeReAuthType.do 返回 data.reAuthUserNameInput，如 138****1234）
      try {
        const chJson: Record<string, Object> = chResp.json<Record<string, Object>>();
        const chData: Object = chJson['data'];
        if (chData && typeof chData === 'object') {
          const input: string = (chData as Record<string, Object>)['reAuthUserNameInput'] as string;
          if (input && input.length > 0) {
            this.reAuthPhoneMasked = input;
          }
        }
      } catch (_e) {
        // 解析失败不影响发码流程
      }
    }
    // 3) 发送动态码（短信 / 企业微信）
    await this.sendReAuthCode(username, onProgress);
  }

  // 步骤2：提交二次验证（供 UI 在用户点击“验证并登录”时调用）
  // 返回 true 表示登录态（MOD_AUTH_CAS）已建立
  async submitReAuth(username: string, code: string, trustDevice: boolean = false, onProgress?: (p: LoginProgress) => void): Promise<boolean> {
    if (!code || code.trim().length === 0) {
      throw new CaptchaException('请输入验证码');
    }
    if (onProgress) {
      onProgress({ step: 'device', message: '正在验证验证码...', percent: 78 });
    }
    // 【关键】reAuthSubmit / changeReAuthType 的 service 必须与初始登录一致（= 满 service=ehall）。
    // 我们 App 是 POST login?service=<ehall> 触发的，reAuth 上下文就是 ehall；落地也是重新 POST login?service=ehall。
    // 对齐 Flutter：其 login() 用 target=ehall（满 service）。HAR 实证（ehall.xidian.edu.cn.har #94）正常登录
    // 也是 POST login?service=ehall。浏览器"裸登门户"那份空 service 是错误参照（落地点是门户非 ehall，不签 MOD_AUTH_CAS）。
    // skipTmpReAuth=true 表示"信任此设备"：服务端把当前设备指纹(device_bfp)登记为受信任，
    // 之后同设备登录（sendBfp 上传同一指纹）即可免二次验证（持久信任）。
    // skipTmpReAuth=false 仅本次登录通过，不做持久信任。两者都能让随后的完成 GET 签 ST、本次登录完成。
    const submitBody: string =
      'service=' + this.reAuthService +
      '&reAuthType=' + this.reAuthFactor +
      '&isMultifactor=true&password=&dynamicCode=' +
      encodeURIComponent(code.trim()) +
      '&uuid=&answer1=&answer2=&otpCode=&skipTmpReAuth=' + (trustDevice ? 'true' : 'false');
    // 🔑 对齐 traintime（IDSReAuthClient.prepare() 在 reAuthSubmit 之前无条件调 _registerBrowserFingerprint）：
    // 指纹必须在「reAuth 会话内、提交信任绑定(skipTmpReAuth)之前」注册，CAS 才会把当前会话锚定到本设备指纹，
    // 使 skipTmpReAuth=true 真正把本设备登记为受信任。此前 sendBfp 只放在 postLogin 开头（reAuth 尚未发生），
    // 导致提交信任时 CAS 看不到本会话指纹 → 信任不生效 → 每次登录仍触发二次验证 → 死循环。
    // 注册指纹本身不会触发信任（信任仅由 skipTmpReAuth 决定），故无条件注册，与 traintime 一致。
    await this.sendBfp();
    const submitResp: HttpResponse = await this.http.postRaw(
      this.REAUTH_SUBMIT,
      submitBody,
      'application/x-www-form-urlencoded; charset=UTF-8',
      this.reAuthHeaders()
    );
    if (submitResp.statusCode < 200 || submitResp.statusCode >= 300) {
      throw new ReAuthExpiredException('设备验证提交失败（HTTP ' + submitResp.statusCode + '），请检查验证码后重试');
    }
    // 服务端对"验证码错误/失败"也返回 HTTP 200，必须解析 body 区分，不能只看状态码！
    // 否则会把"验证码错误"误判为成功，继续走落地重试（实测 [38256]：reAuthSubmit 返回
    // {"msg":"验证码错误","code":"reAuth_failed"}，旧代码照常 return true → 卡死在重试）。
    const submitBodyStr: string = submitResp.body || '';
    const submitOk: boolean = submitBodyStr.indexOf('reAuth_success') >= 0 ||
      submitBodyStr.indexOf('认证成功') >= 0;
    if (!submitOk) {
      let failMsg: string = '设备验证失败，请重试';
      const rm: RegExpMatchArray | null = submitBodyStr.match(/"returnMessage"\s*:\s*"([^"]+)"/);
      if (rm && rm[1]) {
        failMsg = rm[1];
      } else if (submitBodyStr.indexOf('验证码错误') >= 0) {
        failMsg = '验证码错误，请重新输入';
      } else if (submitBodyStr.indexOf('code_time') >= 0 || submitBodyStr.indexOf('重复发送') >= 0) {
        failMsg = '验证码发送过于频繁，请稍后再试';
      }
      throw new ReAuthExpiredException(failMsg);
    }
    // 提交成功（服务端已返回"认证成功"，当前会话已被标记为已通过二次验证）。
    // 真正的登录态（MOD_AUTH_CAS）由 postLogin 的 completeLoginAfterReAuth 落地 + 签 MOD_AUTH_CAS 来建立，这里仅返回成功。
    return true;
  }

  // reAuth 完成后，当前会话已被标记为已通过二次验证（reAuthSubmit 已提交 skipTmpReAuth）。
  // 若用户勾选了"信任此设备"，该设备指纹已被服务端登记为受信任，后续同设备登录免二次验证。
  // 因 httpPostOneShot 已统一走 HttpUtil 共享会话（手动逐跳跟随），reAuth 阶段与登录是同一 CAS 会话，
  // 直接 tryAutoRestoreLogin()（GET login?service=ehall 跟 302 到 ehall 签 MOD_AUTH_CAS）即【本次登录完成】，
  // 不需要用户再点第二次，也不再需要"裸 GET 落地"（实测无效，会话级验证标记靠共享会话自然落到签发环节）。
  async completeLoginAfterReAuth(
    username: string,
    onProgress?: (p: LoginProgress) => void
  ): Promise<boolean> {
    if (onProgress) {
      onProgress({ step: 'redirect', message: '正在完成登录...', percent: 85 });
    }
    // 设备已信任（reAuthSubmit 已提交 skipTmpReAuth）。POST login 与后续 reAuth 已统一走
    // HttpUtil 共享会话，直接 GET login?service=ehall 跟 302 即可签 MOD_AUTH_CAS（一次性登录完成）。
    let ok: boolean = await this.tryAutoRestoreLogin();
    if (!ok) {
      // 偶发时序：重试一次（不清除 cookie，信任不丢）
      ok = await this.tryAutoRestoreLogin();
    }
    if (ok) {
      if (username.length > 0) {
        await PreferenceUtil.putString('ids_account', username);
      }
      return true;
    }
    // 信任态仍未转成登录态（落地未生效）。保留 cookie 不清除（信任不丢），如实告知，不再虚假承诺"第二次不用验证"。
    throw new ReAuthExpiredException('设备验证已通过，但登录态建立失败，请稍后重试（仍失败可重启 App 再登录一次）。');
  }

  // 持久化登录态（MOD_AUTH_CAS + ids_account + is_logged_in）
  private async persistLogin(username: string, ehCookies: string): Promise<boolean> {
    await this.http.get('https://ehall.xidian.edu.cn/jsonp/getAppUsageMonitor.json?type=uv');
    await this.http.saveCookies();
    const modMatch: RegExpMatchArray | null = ehCookies.match(/MOD_AUTH_CAS=([^;]+)/);
    if (modMatch && modMatch[1]) {
      await PreferenceUtil.putString('mod_auth_cas', modMatch[1]);
    }
    if (username.length > 0) {
      await PreferenceUtil.putString('ids_account', username);
    }
    await PreferenceUtil.putBool('is_logged_in', true);
    return true;
  }

  // ========== 完整登录流程 ==========
  async login(
    username: string,
    password: string,
    onTracks: () => Promise<TrackPoint[]>,
    onProgress?: (p: LoginProgress) => void,
    onReAuthNeeded?: (username: string, onProgress?: (p: LoginProgress) => void) => Promise<boolean>
  ): Promise<boolean> {
    // 登录/SSO 请求绕过 offline 拦截（对齐 Flutter dioNoOfflineCheck）
    return await HttpUtil.withNoOfflineCheck(async (): Promise<boolean> => {
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
      throw new CaptchaException('验证码校验失败');
    }

    // Step 5: 提交登录（含二次验证分支）
    return await this.postLogin(username, password, fields, onProgress, onReAuthNeeded);
    });
  }

  // 鉴权类异常判定（供各业务服务的 activateAppSession/checkAndAutoLogin 调用方使用）：
  // 这类异常=必须用户介入重新登录/设备验证，服务层不得吞掉，须原样上抛给页面走重登流程；
  // 其余（网络抖动等）可按需降级继续尝试。
  static isAuthError(e: Object): boolean {
    return e instanceof NeedReAuthError
      || e instanceof CaptchaException
      || e instanceof ReAuthCancelledException
      || e instanceof ReAuthExpiredException;
  }

  // ========== 自动登录（TGC 优先 → 密码兜底）==========
  // 不依赖持久化标记，直接用 HTTP 检测真实登录状态
  // 返回值：true=已登录，false=需要手动登录
  async checkAndAutoLogin(): Promise<boolean> {
    // 静默续登请求绕过 offline 拦截（对齐 Flutter dioNoOfflineCheck）
    return await HttpUtil.withNoOfflineCheck(async (): Promise<boolean> => {
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
    const password: string = await SecureStorageUtil.get(SecureAlias.LOGIN_PASSWORD);
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
      // NeedReAuthError：遇到二次验证（信任设备被删/上限），必须抛给上层弹 reAuth 弹窗
      // CaptchaException：需要滑块验证，静默续登无法完成，必须抛给上层走手动登录
      // 这两个异常不能在此吞掉——吞掉会导致"登录失效但无任何提示"，用户只能干等
      if (e instanceof NeedReAuthError) {
        throw new NeedReAuthError();
      }
      if (e instanceof CaptchaException) {
        throw new CaptchaException('需要滑块验证');
      }
      // 其他异常（网络超时等）吞掉，返回 false 由上层决定是否重试
    }

    return false;
    });
  }

  // ========== 尝试自动恢复登录（无需密码）==========
  // 如果 CAS TGC (Ticket Granting Cookie) 仍有效，
  // 直接访问 login?service= 就会 302 到 ehall 并签发新 MOD_AUTH_CAS
  // referer：reAuth 收尾场景传 reAuth 中间页 URL（对齐 HAR），普通自动恢复登录不传
  async tryAutoRestoreLogin(referer?: string): Promise<boolean> {
    // TGC 自动恢复登录请求绕过 offline 拦截（对齐 Flutter dioNoOfflineCheck）
    return await HttpUtil.withNoOfflineCheck(async (): Promise<boolean> => {
    const serviceUrl: string = encodeURIComponent(this.SERVICE_URL);
    const loginWithService: string = this.LOGIN_PAGE + '?service=' + serviceUrl;

    const hopHeaders: Record<string, string> | undefined =
      (referer !== undefined && referer.length > 0) ? this.pageHeaders(referer) : undefined;

    let currentUrl: string = loginWithService;
    let resp: HttpResponse = await this.http.getNoRedirect(loginWithService, hopHeaders);
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
      resp = await this.http.getNoRedirect(location, hopHeaders);
      loopGuard++;
    }

    // 跨域 Cookie 修复：NETSTACK getNoRedirect 按原始 URL 域名存 cookie，
    // TGC 刷新出的 MOD_AUTH_CAS 会被存到 ids.xidian.edu.cn 下，
    // 但 checkEhallLogin() 查的是 ehall.xidian.edu.cn，需要显式复制。
    this.http.copyCookiesForDomain('ids.xidian.edu.cn', 'ehall.xidian.edu.cn');
    await this.http.saveCookies();

    const ehallCookies: string = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    const hasModCas: boolean = ehallCookies.indexOf('MOD_AUTH_CAS') >= 0;

    const stillReAuth: boolean = (resp.body || '').toLowerCase().indexOf('reauth') >= 0;

    if (hasModCas) {
      const modMatch: RegExpMatchArray | null = ehallCookies.match(/MOD_AUTH_CAS=([^;]+)/);
      if (modMatch && modMatch[1]) {
        await PreferenceUtil.putString('mod_auth_cas', modMatch[1]);
      }
      await PreferenceUtil.putBool('is_logged_in', true);
      return true;
    }

    return false;
    });
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
    for (const domain of domains) {
      for (const kv of allCookies) {
        try {
          WCM.setCookie('https://' + domain, kv + '; Domain=.xidian.edu.cn; Path=/');
          if (domain.startsWith('libspace')) {
            WCM.setCookie('http://' + domain, kv + '; Domain=.xidian.edu.cn; Path=/');
          }
        } catch (e) {
          // 单个域 setCookie 失败不中断其余域，但留日志便于排查 WebView 同步问题
          console.warn('[CasLogin] WebView setCookie failed for ' + domain + ': ' + String(e));
        }
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
    // 第一跳：POST 登录表单。postNoRedirect 在收到 3xx 时立即返回并保存 Set-Cookie 到 ids 域名，
    // 不依赖 NETSTACK 自动跟随（其自动跟随 302 时不携带/不更新共享 cookieStore，会断会话）。
    let resp: HttpResponse = await this.http.postNoRedirect(url, bodyStr, headers);
    let currentUrl: string = url;
    let guard: number = 0;
    let lastRedirectLoc: string = resp.isRedirect ? (resp.location || '') : '';
    // 手动用 GET 逐跳跟随 302（同源），每一跳都走 HttpUtil 共享 cookieStore，
    // 保证整条链（POST login → 302 reAuthLoginView → 200）使用同一个 CAS 会话，
    // 否则 reAuth 阶段会拿到与登录不同的会话，使“设备已验证”标记落不到签发环节（反复要验证码）。
    while (resp.isRedirect && resp.location && guard < 10) {
      let location: string = resp.location;
      const m: RegExpMatchArray | null = currentUrl.match(/^(https?:\/\/[^\/]+)/);
      if (m) {
        const base: string = m[1];
        if (!location.startsWith('http://') && !location.startsWith('https://')) {
          location = base + (location.startsWith('/') ? location : '/' + location);
        }
      }
      currentUrl = location;
      lastRedirectLoc = location;
      resp = await this.http.getNoRedirect(location, this.pageHeaders(url));
      guard++;
    }
    // 保留最后一个 302 的 location（reAuthLoginView），供上层提取 reAuthViewUrl；
    // 最终响应（200 reAuth 页 / ehall 首页）的 body 保留用于错误检测。
    if (lastRedirectLoc.length > 0) {
      resp.location = lastRedirectLoc;
      resp.isRedirect = true;
    }
    return resp;
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

  // 简单的延时等待（毫秒）
  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }
}

// SliderPuzzle 解码结果
export interface PuzzleImages {
  bigPm: Uint8Array;
  smallPm: Uint8Array;
}
