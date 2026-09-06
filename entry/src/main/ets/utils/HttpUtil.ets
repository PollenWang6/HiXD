// HttpUtil.ets — 带 Cookie 持久化的 HTTP 客户端
// Phase 1：HTTP 底层从 @ohos.net.http 切换到 rcp（@kit.RemoteCommunicationKit）
//  - 重定向控制：rcp 的 transfer.autoRedirect=false（官方开关，替代 headersReceive+destroy hack，
//    HTTP/1.1/HTTP/2 下都可靠，Phase 0 真机验证通过）
//  - Cookie：响应 cookie 从 resp.cookies（ResponseCookie[]，结构化且带 domain）按域精确保存，
//    根治此前 data.cookies / set-cookie 头解析的跨域串域污染；cookieStore 与全部对外方法保持不变
import { rcp } from '@kit.RemoteCommunicationKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferenceUtil } from './PreferenceUtil';
import { LoginState } from './LoginState';

const TAG = 'HttpUtil';
const UA_DEFAULT: string =
  'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

export class HttpResponse {
  statusCode: number = 0;
  body: string = '';
  headers: Record<string, string> = {};
  isRedirect: boolean = false;
  location: string | undefined = undefined;

  get isOk(): boolean { return this.statusCode >= 200 && this.statusCode < 300; }

  json<T>(): T {
    return JSON.parse(this.body) as T;
  }
}

interface CookieEntry {
  name: string;
  value: string;
  domain: string;
  path: string;
}

export class HttpUtil {
  private static instance: HttpUtil;
  private cookieStore: Record<string, Record<string, string>> = {};
  private cookiesLoaded: boolean = false;
  // Phase 1：全局单例 rcp Session（长生命周期，连接池复用）
  private rcpSession: rcp.Session | null = null;

  private constructor() {}

  static getInstance(): HttpUtil {
    if (!HttpUtil.instance) HttpUtil.instance = new HttpUtil();
    return HttpUtil.instance;
  }

  /**
   * 把 rcp 网络层 BusinessError 翻译成用户友好文案。
   * 对齐 Flutter login_window.dart 对 DioException 的三档处理：
   *   连不上服务器 / 请求超时 / 具体消息。
   * 原始 code + 消息仍打印到日志便于排查，但抛给上层的是友好串。
   */
  private static friendlyNetError(e: Object): string {
    const be = e as BusinessError;
    const code: string = (be && be.code !== undefined && be.code !== null) ? String(be.code) : '?';
    const raw: string = (be && be.message) ? be.message : String(e);
    const m: string = raw.toLowerCase();
    if (m.includes('resolve') || m.includes('unknown host') || m.includes('dns') || m.includes('getaddrinfo') || m.includes('no address')) {
      return '网络不可用，无法解析服务器地址，请检查网络连接';
    }
    if (m.includes('timed out') || m.includes('timeout') || m.includes('etimeout') || m.includes('超时')) {
      return '连接超时，请检查网络后重试';
    }
    if (m.includes('refused')) {
      return '服务器拒绝连接，可能是服务暂不可用';
    }
    if (m.includes('ssl') || m.includes('tls') || m.includes('certificate') || m.includes('handshake') || m.includes('证书')) {
      return '安全连接失败（证书/加密错误），请稍后重试';
    }
    if (m.includes('reset') || m.includes('abort') || m.includes('closed') || m.includes('broken')) {
      return '网络连接被中断，请检查网络后重试';
    }
    // 兜底：带原始消息，便于排查
    return raw.length > 0 ? ('网络请求失败：' + raw) : ('网络请求失败（错误码 ' + code + '）');
  }

  // ===== Offline 拦截（对齐 Flutter IDSSession.dio）=====
  // 业务请求默认检查登录态：未登录时直接抛异常，不发请求。
  // 登录/SSO 请求用 withNoOfflineCheck() 包裹，绕过拦截。
  private static noOfflineCheckDepth: number = 0;

  /**
   * 临时关闭 offline 拦截，执行登录/SSO 请求。
   * 对齐 Flutter IDSSession.dioNoOfflineCheck。
   * 用法：await HttpUtil.withNoOfflineCheck(async () => { ...登录请求... });
   */
  static async withNoOfflineCheck<T>(fn: () => Promise<T>): Promise<T> {
    HttpUtil.noOfflineCheckDepth++;
    try {
      return await fn();
    } finally {
      HttpUtil.noOfflineCheckDepth--;
    }
  }

  /**
   * 全局 IDS 二次验证处理器（对齐 Flutter activeIDSReAuthHandler）。
   * 由 MainPage 在启动时注册；ehall 业务请求重定向链命中 reAuthLoginView 时由本类的
   * request() 内联触发，返回 true 表示已通过二次验证（会话重建）、原请求可重试。
   */
  static reAuthHandler: ((username: string) => Promise<boolean>) | null = null;

  /**
   * 业务请求未登录时的静默续登处理器（对齐 Flutter IDSSession Dio 拦截器：
   * 业务请求不预先拦死，由请求级 checkAndLogin 续登后重试）。
   * 由 MainPage 注册为 autoHealIfExpired（TGC→保存凭证+自动滑块，无 UI）。
   * request()/postFormNoRedirect 在 ehall 业务域未登录时先调它续登一次，
   * 成功（返回 true，会话已重建）则本次请求照常发出；失败才抛 offline 拦截异常交页面提示。
   * 避免 loginStatus 短暂非 ok（会话过期/自愈进行中）时业务页面一律被拦、
   * 弹"当前未登录校园账号"这种让用户摸不着头脑的硬错误（2026-09-06 真机复现）。
   */
  static sessionRestoreHandler: (() => Promise<boolean>) | null = null;

  /**
   * 检查当前是否允许发业务请求（纯判断，无副作用）。
   * 对齐 Flutter IDSSession.dio：offline 守卫【只作用于 IDS/ehall 业务域】；
   * 睿思/校园网/图书馆/体育/电费等独立模块各自域名的请求不受限（未登录也能用）。
   * 登录/SSO 请求（ids.xidian.edu.cn）走 withNoOfflineCheck 包裹绕过本守卫。
   */
  private isOfflineBlocked(url?: string): boolean {
    if (HttpUtil.noOfflineCheckDepth > 0) return false; // 登录/SSO 请求绕过
    if (LoginState.isLoggedIn()) return false; // 已登录，放行
    // 仅拦截 IDS/ehall 业务域；其余域名直接放行（对齐 Flutter 独立 Dio 客户端）
    if (url) {
      const domain: string = this.getDomain(url);
      if (domain !== 'ehall.xidian.edu.cn') {
        return false;
      }
    }
    return true;
  }

  /**
   * ehall 业务域未登录时的统一处理：先给一次静默续登机会（请求级自愈，对齐 Flutter
   * IDSSession 拦截器），续登成功则放行本次请求；失败才抛拦截异常（页面提示重新登录）。
   */
  private async autoRestoreOrBlock(): Promise<void> {
    const handler = HttpUtil.sessionRestoreHandler;
    if (handler) {
      try {
        const ok: boolean = await HttpUtil.withNoOfflineCheck(() => handler());
        if (ok) {
          return;
        }
      } catch (_e) {
        // 续登内部已按错误类型处理（密码错弹窗/需设备验证等），这里统一走拦截提示
      }
    }
    throw new Error('OFFLINE_MODE: 当前未登录校园账号，业务请求已拦截。请先登录后再使用该功能。');
  }

  /**
   * 判断重定向目标是否为 CAS 二次验证页（对齐 Flutter isIDSReAuthLocation）。
   * 命中 reAuthLoginView.do / reAuthCheck 即视为需要 step-up 验证。
   */
  private isReAuthLocation(loc: string): boolean {
    if (!loc) return false;
    const l: string = loc.toLowerCase();
    return l.includes('reauthloginview') || l.includes('reauthcheck');
  }

  // ===== rcp Session（懒初始化单例）=====

  private getRcpSession(): rcp.Session {
    if (!this.rcpSession) {
      this.rcpSession = rcp.createSession();
    }
    return this.rcpSession;
  }

  // ===== Cookie 持久化（手动管理，逻辑不变）=====

  async loadCookies(): Promise<void> {
    // 只有已成功加载过 cookieStore 中有数据时才跳过
    if (this.cookiesLoaded && Object.keys(this.cookieStore).length > 0) return;
    try {
      const raw: string = PreferenceUtil.getString('http_cookies');
      if (raw.length > 0) {
        const entries: CookieEntry[] = JSON.parse(raw) as CookieEntry[];
        for (const entry of entries) {
          if (!entry || typeof entry.domain !== 'string') {
            continue;
          }
          // 迁移历史脏键：早期把 "host:443" 也当独立域名存过，规整回无端口键，
          // 否则带 :443 跳转读不到无端口会话的 CASTGC（2026-09-06 登录空转根因之一）。
          const entryDomain: string = this.normalizeHost(entry.domain);
          if (!this.cookieStore[entryDomain]) {
            this.cookieStore[entryDomain] = {};
          }
          this.cookieStore[entryDomain][entry.name] = entry.value;
        }
        this.cookiesLoaded = true; // 只有成功加载后才标记
      } else {
        // 没有缓存的 cookies，也算加载完成
        this.cookiesLoaded = true;
      }
    } catch (e) {
      // 加载失败，不设置 cookiesLoaded = true，允许后续重试
    }
  }

  async saveCookies(): Promise<void> {
    try {
      const entries: CookieEntry[] = [];
      for (const domain of Object.keys(this.cookieStore)) {
        for (const name of Object.keys(this.cookieStore[domain])) {
          entries.push({ name, value: this.cookieStore[domain][name], domain, path: '/' });
        }
      }
      await PreferenceUtil.putString('http_cookies', JSON.stringify(entries));
    } catch (e) {
    }
  }

  async clearCookies(domain?: string): Promise<void> {
    if (domain) {
      this.cookieStore[domain] = {};
    } else {
      this.cookieStore = {};
    }
    await this.saveCookies();
  }

  hasCookies(domain: string): boolean {
    domain = this.normalizeHost(domain);
    const domMap = this.cookieStore[domain];
    return domMap !== undefined && Object.keys(domMap).length > 0;
  }

  async injectCookies(cookieString: string, domain: string): Promise<void> {
    if (!this.cookieStore[domain]) {
      this.cookieStore[domain] = {};
    }
    const parts = cookieString.split(';');
    for (const part of parts) {
      const trimmed = part.trim();
      const eqIdx = trimmed.indexOf('=');
      if (eqIdx > 0) {
        const name = trimmed.substring(0, eqIdx).trim();
        const value = trimmed.substring(eqIdx + 1).trim();
        if (name.length > 0 && value.length > 0) {
          this.cookieStore[domain][name] = value;
        }
      }
    }
    await this.saveCookies();
    // 立即 reload，将刚保存的 cookies 重新读入内存
    // 否则 PreferenceUtil.init() 已经设置 cookiesLoaded=true，后续 loadCookies() 不会重新读
    this.cookiesLoaded = false;
    await this.loadCookies();
  }

  // ===== HTTP 方法（对外签名不变）=====

  async get(url: string, headers?: Record<string, string>, skipCookies?: boolean): Promise<HttpResponse> {
    await this.loadCookies();
    return this.request(url, 'GET', undefined, headers, skipCookies);
  }

  async getWithQuery(url: string, queryParams: Record<string, string>, headers?: Record<string, string>, skipCookies?: boolean): Promise<HttpResponse> {
    await this.loadCookies();
    const parts: string[] = [];
    for (const key of Object.keys(queryParams)) {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(queryParams[key]));
    }
    const fullUrl = url + (url.includes('?') ? '&' : '?') + parts.join('&');
    return this.request(fullUrl, 'GET', undefined, headers, skipCookies);
  }

  async post(url: string, data: Object, headers?: Record<string, string>, skipCookies?: boolean): Promise<HttpResponse> {
    await this.loadCookies();
    return this.postRaw(url, JSON.stringify(data), 'application/json', headers, skipCookies);
  }

  async postForm(url: string, data: Record<string, string>, headers?: Record<string, string>, skipCookies?: boolean): Promise<HttpResponse> {
    await this.loadCookies();
    const parts: string[] = [];
    for (const key of Object.keys(data)) {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(data[key]));
    }
    const bodyStr: string = parts.join('&');
    // 空表单不传 body（与旧实现一致：空 body 走不带 body 的 POST）
    if (bodyStr.length === 0) {
      return this.request(url, 'POST', undefined, headers, skipCookies);
    }
    return this.postRaw(url, bodyStr, 'application/x-www-form-urlencoded', headers, skipCookies);
  }

  async postRaw(url: string, bodyStr: string, contentType: string, headers?: Record<string, string>, skipCookies?: boolean): Promise<HttpResponse> {
    const allHeaders: Record<string, string> = { 'Content-Type': contentType };
    if (headers) {
      for (const key of Object.keys(headers)) {
        allHeaders[key] = headers[key];
      }
    }
    return this.request(url, 'POST', bodyStr, allHeaders, skipCookies);
  }

  // POST 无 body、无 Content-Type（用于 xgxt getAppConfig.do 等仅需 query params 的 API）
  async postEmpty(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    return this.request(url, 'POST', undefined, headers);
  }

  // 二进制 GET（用于验证码图片/封面等），返回 ArrayBuffer。
  // 逐跳手动跟随重定向（rcp autoRedirect:false 不自动跟；图床/验证码可能 302），
  // 每跳按当前域名注入 cookie，最终 2xx 返回 ArrayBuffer。
  async getArrayBuffer(url: string, headers?: Record<string, string>): Promise<ArrayBuffer> {
    await this.loadCookies();
    let currentUrl: string = url;
    for (let hop: number = 0; hop < 8; hop++) {
      const session = this.getRcpSession();
      const reqHeaders: rcp.RequestHeaders = {};
      if (headers) {
        for (const key of Object.keys(headers)) {
          reqHeaders[key] = headers[key];
        }
      }
      if (!reqHeaders['user-agent'] && !reqHeaders['User-Agent']) {
        reqHeaders['user-agent'] = UA_DEFAULT;
      }
      const domain = this.getDomain(currentUrl);
      const cookieStr = this.getCookiesForDomain(domain);
      if (cookieStr.length > 0) {
        reqHeaders['cookie'] = cookieStr;
      }
      const safeUrl: string = currentUrl.replace(/([?&]service=)http:\/\//g, '$1https://');
      const request: rcp.Request = new rcp.Request(
        safeUrl,
        'GET',
        reqHeaders,
        undefined,
        undefined,
        undefined,
        {
          transfer: {
            autoRedirect: false,
            timeout: { connectMs: 30000, transferMs: 120000 }
          }
        }
      );
      let resp: rcp.Response;
      try {
        resp = await session.fetch(request);
      } catch (e) {
        const be = e as BusinessError;
        const code: string = (be && be.code !== undefined && be.code !== null) ? String(be.code) : '?';
        const raw: string = (be && be.message) ? be.message : String(e);
        const friendly: string = HttpUtil.friendlyNetError(e);
        console.error('[RcpHttp] getArrayBuffer failed code=' + code + ' msg=' + raw + ' url=' + safeUrl);
        throw new Error(friendly);
      }
      // 响应 cookie 按域保存（与 rcpFetch 一致）
      const cs: rcp.ResponseCookie[] | undefined = resp.cookies;
      if (cs && cs.length > 0) {
        for (let i = 0; i < cs.length; i++) {
          const c = cs[i];
          const cDomain: string = (c.domain && c.domain.length > 0) ? c.domain : domain;
          const cName: string = c.name;
          const cValue: string = c.value !== undefined ? c.value : '';
          if (cName.length > 0 && cValue.length > 0) {
            if (!this.cookieStore[cDomain]) {
              this.cookieStore[cDomain] = {};
            }
            this.cookieStore[cDomain][cName] = cValue;
          }
        }
        this.saveCookies().catch(() => {});
      }
      // 2xx：返回二进制
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.body) {
        return resp.body as ArrayBuffer;
      }
      // 3xx：跟随 Location（相对/协议相对地址由 resolveRedirect 解析）
      if (resp.statusCode >= 300 && resp.statusCode < 400) {
        const locRaw = resp.headers.location;
        if (locRaw !== undefined && locRaw !== null && String(locRaw).length > 0) {
          currentUrl = this.resolveRedirect(String(locRaw), currentUrl);
          continue;
        }
      }
      throw new Error('getArrayBuffer: status=' + resp.statusCode + ' url=' + safeUrl);
    }
    throw new Error('getArrayBuffer: too many redirects url=' + url);
  }

  getCookiesForDomain(domain: string): string {
    // 入口统一规整默认端口，保证与 cookieStore 键一致（见 normalizeHost 注释）
    domain = this.normalizeHost(domain);
    // 收集目标域及其所有父域：同时匹配带点（.xidian.edu.cn）与无点（xidian.edu.cn）两种存法，
    // 避免 rcp ResponseCookie.domain 返回无点域名时父域 cookie 永远匹配不上（会话静默丢失）
    const matchDomains: string[] = [domain];
    const parts: string[] = domain.split('.');
    for (let i = 1; i < parts.length - 1; i++) {
      const suffix: string = parts.slice(i).join('.');
      matchDomains.push(suffix);
      matchDomains.push('.' + suffix);
    }
    const seen: Set<string> = new Set<string>();
    const partsOut: string[] = [];
    for (let i = 0; i < matchDomains.length; i++) {
      const domMap = this.cookieStore[matchDomains[i]];
      if (domMap) {
        for (const name of Object.keys(domMap)) {
          if (!seen.has(name)) {
            seen.add(name);
            partsOut.push(name + '=' + domMap[name]);
          }
        }
      }
    }
    let result: string = partsOut.join('; ');
    // 对 ehall 域强制注入 MOD_AUTH_CAS（冗余保护：即使 cookie store 出问题也能正常工作）
    if (domain === 'ehall.xidian.edu.cn' && result.indexOf('MOD_AUTH_CAS') < 0) {
      const modCas: string = PreferenceUtil.getString('mod_auth_cas');
      if (modCas.length > 0) {
        result = result.length > 0 ? result + '; MOD_AUTH_CAS=' + modCas : 'MOD_AUTH_CAS=' + modCas;
      }
    }
    return result;
  }

  getAllCookies(domain: string): string { return this.getCookiesForDomain(domain); }

  // 复制 cookie：将 fromDomain 的 cookie 复制到 toDomain（用于跨域重定向后 session 纠正）
  copyCookiesForDomain(fromDomain: string, toDomain: string): void {
    if (!this.cookieStore[fromDomain]) { return; }
    if (!this.cookieStore[toDomain]) {
      this.cookieStore[toDomain] = {};
    }
    const src: Record<string, string> = this.cookieStore[fromDomain];
    const dst: Record<string, string> = this.cookieStore[toDomain];
    for (const name of Object.keys(src)) {
      dst[name] = src[name];
    }
  }

  // 从 Cookie header 字符串恢复指定域名的 cookie（先清空再设值）
  replaceCookiesForDomain(domain: string, cookieHeader: string): void {
    this.cookieStore[domain] = {};
    if (cookieHeader.length === 0) { return; }
    const pairs: string[] = cookieHeader.split(';');
    for (let i: number = 0; i < pairs.length; i++) {
      const pair: string = pairs[i].trim();
      const eq: number = pair.indexOf('=');
      if (eq > 0) {
        const name: string = pair.substring(0, eq).trim();
        const value: string = pair.substring(eq + 1).trim();
        if (name.length > 0) {
          this.cookieStore[domain][name] = value;
        }
      }
    }
  }

  // ===== rcp 底层实现 =====

  // 统一 rcp 请求（不自动跟随重定向，返回第一跳响应；cookie 请求前手动拼、响应后按域保存）
  private async rcpFetch(
    url: string,
    method: 'GET' | 'POST',
    bodyStr: string | undefined,
    headers: Record<string, string> | undefined,
    skipCookies: boolean
  ): Promise<HttpResponse> {
    const session = this.getRcpSession();
    const reqHeaders: rcp.RequestHeaders = {};
    if (headers) {
      for (const key of Object.keys(headers)) {
        reqHeaders[key] = headers[key];
      }
    }
    if (!reqHeaders['user-agent'] && !reqHeaders['User-Agent']) {
      reqHeaders['user-agent'] = UA_DEFAULT;
    }
    if (!skipCookies) {
      const domain = this.getDomain(url);
      const cookieStr = this.getCookiesForDomain(domain);
      if (cookieStr.length > 0) {
        reqHeaders['cookie'] = cookieStr;
      }
    }
    // 规整服务端返回的畸形重定向 URL：query 中未编码的明文 service=http://（西电服务端按 http Referer
    // 拼出）会被系统以 Cleartext 拦截，统一提升为 https。
    const safeUrl: string = url.replace(/([?&]service=)http:\/\//g, '$1https://');

    const request: rcp.Request = new rcp.Request(
      safeUrl,
      method,
      reqHeaders,
      bodyStr,
      undefined,
      undefined,
      {
        transfer: {
          autoRedirect: false,
          timeout: { connectMs: 30000, transferMs: 120000 }
        }
      }
    );

    let resp: rcp.Response;
    try {
      resp = await session.fetch(request);
    } catch (e) {
      const be = e as BusinessError;
      const code: string = (be && be.code !== undefined && be.code !== null) ? String(be.code) : '?';
      const raw: string = (be && be.message) ? be.message : String(e);
      const friendly: string = HttpUtil.friendlyNetError(e);
      console.error('[RcpHttp] request failed code=' + code + ' msg=' + raw + ' url=' + safeUrl);
      throw new Error(friendly);
    }

    const out = new HttpResponse();
    out.statusCode = resp.statusCode;

    // headers（ResponseHeaders → Record<string,string>）
    const rawH = resp.headers;
    const rawHMap = rawH as Record<string, string | string[] | undefined>;
    const respHeaders: Record<string, string> = {};
    const hKeys: string[] = Object.keys(rawH);
    for (let i = 0; i < hKeys.length; i++) {
      const k = hKeys[i];
      const v = rawHMap[k];
      respHeaders[k] = typeof v === 'string' ? v : (v === undefined ? '' : JSON.stringify(v));
    }
    out.headers = respHeaders;

    // body：ArrayBuffer → string（按 content-type / 首字节判定编码，兼容 GBK 站点）
    out.body = this.decodeBody(resp.body, respHeaders['content-type'] || respHeaders['Content-Type'] || '');

    out.isRedirect = out.statusCode >= 300 && out.statusCode < 400;
    out.location = typeof rawH.location === 'string' ? rawH.location : (rawH.location ? String(rawH.location) : undefined);

    // 响应 cookie：按 domain（resp.cookies 自带 domain，空则归当前请求域）精确保存——根治串域
    if (!skipCookies) {
      const cs: rcp.ResponseCookie[] | undefined = resp.cookies;
      if (cs && cs.length > 0) {
        const domain = this.getDomain(safeUrl);
        for (let i = 0; i < cs.length; i++) {
          const c = cs[i];
          const cDomain: string = (c.domain && c.domain.length > 0) ? c.domain : domain;
          const cName: string = c.name;
          const cValue: string = c.value !== undefined ? c.value : '';
          if (cName.length > 0 && cValue.length > 0) {
            if (!this.cookieStore[cDomain]) {
              this.cookieStore[cDomain] = {};
            }
            this.cookieStore[cDomain][cName] = cValue;
          }
        }
        this.saveCookies().catch(() => {});
      }
    }

    console.info('[RcpHttp] ' + method + ' ' + out.statusCode + ' ' + safeUrl +
      (out.location ? ' -> ' + out.location : ''));
    // 诊断：请求带的关键 cookie + 响应捕获的 cookie（名称:域:值前16位）
    const cookieHeader: string = typeof reqHeaders['cookie'] === 'string' ? (reqHeaders['cookie'] as string) : '';
    const cookieBrief: string = cookieHeader.length > 0 ? cookieHeader.substring(0, 80) : '(none)';
    let respCookieBrief: string = '(none)';
    const cs2: rcp.ResponseCookie[] | undefined = resp.cookies;
    if (cs2 && cs2.length > 0) {
      const partsBrief: string[] = [];
      for (let i = 0; i < cs2.length; i++) {
        const c = cs2[i];
        partsBrief.push(c.name + '@' + (c.domain || 'url') + '=' + String(c.value ?? '').substring(0, 16));
      }
      respCookieBrief = partsBrief.join(' | ');
    }
    console.info('[RcpHttp]   reqCookie=' + cookieBrief + '  respCookies=' + respCookieBrief);
    return out;
  }

  // ArrayBuffer → string。
  // 编码判定（对齐 Flutter 参考实现的 responseDecoder）：
  // ① 首字节为 '{'(0x7B) 或 '['(0x5B) → JSON，强制 UTF-8；
  // ② 否则 Content-Type 含 'gb'（gbk/gb2312/gb18030）→ GB18030 解码（wlsy 物理实验等 GBK 站点）；
  // ③ 其余 → UTF-8（UTF-8 解码遇非法字节自动替换，不影响正常站点）。
  private decodeBody(buf: ArrayBuffer | undefined, contentType?: string): string {
    if (!buf || buf.byteLength === 0) {
      return '';
    }
    const bytes = new Uint8Array(buf);
    const first: number = bytes[0];
    const isJson: boolean = first === 0x7B || first === 0x5B;
    const ct: string = contentType ? contentType.toLowerCase() : '';
    const isGb: boolean = !isJson && ct.indexOf('gb') >= 0;
    try {
      if (isJson) {
        const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
        return decoder.decodeToString(bytes);
      }
      if (isGb) {
        try {
          const gbDecoder: util.TextDecoder = util.TextDecoder.create('gb18030');
          return gbDecoder.decodeToString(bytes);
        } catch (e) {
          console.warn('[RcpHttp] gb18030 decode failed, fallback to utf-8');
        }
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    } catch (e) {
      return '';
    }
  }

  private getDomain(url: string): string {
    const m = url.match(/https?:\/\/([^/]+)/);
    return m ? this.normalizeHost(m[1]) : url;
  }

  // 将重定向 Location 解析为绝对 URL（支持绝对地址、协议相对 //host/path、根相对 /path、目录相对 path）
  private resolveRedirect(location: string, baseUrl: string): string {
    if (location.startsWith('//')) {
      const proto: string = baseUrl.startsWith('https') ? 'https:' : 'http:';
      return this.normalizeUrlPort(proto + location);
    }
    if (/^https?:\/\//i.test(location)) {
      return this.normalizeUrlPort(location);
    }
    const m = baseUrl.match(/^https?:\/\/[^/]+/);
    const origin: string = m ? this.normalizeUrlPort(m[0]) : baseUrl;
    if (location.startsWith('/')) {
      return origin + location;
    }
    const lastSlash: number = baseUrl.lastIndexOf('/');
    const dir: string = lastSlash >= 0 ? baseUrl.substring(0, lastSlash + 1) : origin + '/';
    return dir + location;
  }

  // 规整 host：剔除默认端口(:443/:80)。
  // CAS/ehall 重定向 Location 常带显式默认端口（实测 ehall 302 → https://ehall.xidian.edu.cn:443/login?...，
  // 再弹回 https://ids.xidian.edu.cn:443/authserver/login?...）。若不剔除，
  // cookieStore 会把 "host:port" 与 "host" 存成两套键：带 :443 的那跳读不到无端口会话刚种下的
  // CASTGC/TGC/JSESSIONID → CAS 视作全新会话 → 一直返回登录页 → 反复拉滑块，
  // 静默续登在 ehall ↔ :443 之间空转，登录态永不 ok，业务请求被 offline 守卫拦下
  //（2026-09-06 真机 HiLog 实证：ST 票据发了一串，登录页 200 一轮接一轮）。
  private normalizeHost(host: string): string {
    if (host.endsWith(':443')) {
      return host.substring(0, host.length - 4);
    }
    if (host.endsWith(':80')) {
      return host.substring(0, host.length - 3);
    }
    return host;
  }

  // 规整 URL：仅剔除与 scheme 匹配的默认端口（https 剥 :443、http 剥 :80），其余原样保留。
  private normalizeUrlPort(url: string): string {
    const m = url.match(/^(https?):\/\/([^/]+)(.*)$/);
    if (!m) {
      return url;
    }
    const isHttps: boolean = m[1] === 'https';
    let host: string = m[2];
    const suffix: string = isHttps ? ':443' : ':80';
    if (host.endsWith(suffix)) {
      host = host.substring(0, host.length - suffix.length);
    }
    return m[1] + '://' + host + m[3];
  }

  /**
   * 发送 GET 请求但不自动跟随重定向。
   * rcp transfer.autoRedirect=false：返回第一跳响应（3xx 时 location 字段含重定向地址）。
   */
  async getNoRedirect(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    return this.rcpFetch(url, 'GET', undefined, headers, false);
  }

  /**
   * 发送 POST 请求但不自动跟随重定向。bodyStr 为 undefined 时（postEmpty 语义）不传 body。
   */
  async postNoRedirect(url: string, bodyStr: string | undefined, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    return this.rcpFetch(url, 'POST', bodyStr, headers, false);
  }

  /**
   * 发送 form-urlencoded POST 但不自动跟随重定向。
   * 对齐 Flutter ehallDio（followRedirects: false）：ehall 业务请求登录失效时
   * 直接返回 302 响应，由上层检测 isRedirect + location.includes('login') 判定会话失效并触发重登，
   * 避免 ehall / CAS 自动跟随死循环（20 跳 too many redirects）。
   */
  async postFormNoRedirect(url: string, data: Record<string, string>, headers?: Record<string, string>): Promise<HttpResponse> {
    if (this.isOfflineBlocked(url)) {
      await this.autoRestoreOrBlock(); // ehall 业务域未登录：先静默续登一次，失败抛拦截异常
    }
    await this.loadCookies();
    const parts: string[] = [];
    for (const key of Object.keys(data)) {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(data[key]));
    }
    const bodyStr: string = parts.join('&');
    const allHeaders: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    if (headers) {
      for (const key of Object.keys(headers)) {
        allHeaders[key] = headers[key];
      }
    }
    return this.rcpFetch(url, 'POST', bodyStr.length > 0 ? bodyStr : undefined, allHeaders, false);
  }

  /**
   * 发送请求（自动跟随重定向，公共底层方法）。
   * 逐跳手动跟随：每一跳经 rcpFetch（autoRedirect:false），按当前 URL 域名拼 cookie；
   * 响应 cookie 由 resp.cookies（带 domain）按域保存；301/302 做浏览器式 POST→GET 降级；
   * visited 集合检测重定向循环（如本科生探测 yjspt 触发 CAS↔yjspt 死循环），快速失败。
   */
  private async request(
    url: string,
    method: string,
    body: string | undefined,
    extraHeaders: Record<string, string> | undefined,
    skipCookies?: boolean
  ): Promise<HttpResponse> {
    if (this.isOfflineBlocked(url)) {
      await this.autoRestoreOrBlock(); // ehall 业务域未登录：先静默续登一次，失败抛拦截异常
    }
    const MAX_REDIRECTS: number = 20;
    let currentUrl: string = url;
    let currentMethod: 'GET' | 'POST' = method === 'GET' ? 'GET' : 'POST';
    let currentBody: string | undefined = body;
    let lastResp: HttpResponse | undefined = undefined;
    const visited: Set<string> = new Set<string>();
    visited.add(currentUrl);
    // 本请求内是否已处理过二次验证（防止重试后再次命中 reAuth 时重复弹窗）
    let reAuthHandledInThisRequest: boolean = false;

    for (let hop: number = 0; hop <= MAX_REDIRECTS; hop++) {
      const resp: HttpResponse = await this.rcpFetch(currentUrl, currentMethod, currentBody, extraHeaders, !!skipCookies);
      lastResp = resp;
      const sc: number = resp.statusCode;

      // 2xx：成功，返回最终结果
      if (sc >= 200 && sc < 300) {
        return resp;
      }

      // 3xx 且有 Location：按当前域名重新注入 cookie 后继续跟随
      if (sc >= 300 && sc < 400 && resp.location !== undefined) {
        const next: string = this.resolveRedirect(resp.location, currentUrl);

        // 内联识别二次验证重定向（对齐 Flutter followIDSRedirects / isIDSReAuthLocation）：
        // ehall 业务请求被 CAS 重定向到 reAuthLoginView 时，触发全局 reAuth 处理器弹短信验证码，
        // 通过后再用原始方法重试原请求。覆盖"信任设备被服务器清除→下次 ehall 请求才被截到验证页"的场景，
        // 避免此前只能靠登录后单独 detectPendingReAuth 探测、中途请求静默 302 到验证页导致 JSON 解析失败。
        const handler = HttpUtil.reAuthHandler;
        if (!reAuthHandledInThisRequest && handler && this.isReAuthLocation(next)) {
          reAuthHandledInThisRequest = true;
          try {
            const username: string = PreferenceUtil.getString('ids_account');
            const ok: boolean = await handler(username);
            if (ok) {
              // 二次验证通过、会话已重建：用原始 method/body 从头重试整个请求
              // （checkOffline 已在入口执行过一次，重试不再触发，不会被离线守卫拦下）
              currentUrl = url;
              currentMethod = method === 'GET' ? 'GET' : 'POST';
              currentBody = body;
              visited.clear();
              visited.add(currentUrl);
              continue;
            }
          } catch (_e) {
            // 二次验证失败/取消：落到下方返回当前响应，由上层（业务 service）按错误兜底
          }
          return resp;
        }

        if (visited.has(next)) {
          // 重定向循环（A→B→A…）：立即返回当前响应，不继续跟随
          console.error('[RcpHttp] redirect loop detected: ' + currentUrl + ' -> ' + next);
          return resp;
        }
        visited.add(next);
        // 浏览器语义：301/302 重定向后方法降级为 GET；307/308 保留原方法（GET 本身不带 body）
        if (sc === 301 || sc === 302) {
          currentMethod = 'GET';
          currentBody = undefined;
        } else if (currentMethod === 'GET') {
          currentBody = undefined;
        }
        currentUrl = next;
        continue;
      }

      // 4xx/5xx，或 3xx 无 Location：原样返回
      return resp;
    }

    // 超过硬上限：返回最后一跳响应并打日志
    console.error('[RcpHttp] too many redirects (capped at ' + MAX_REDIRECTS + '): ' + url);
    if (lastResp) {
      return lastResp;
    }
    throw new Error('HTTP too many redirects: ' + url);
  }
}
