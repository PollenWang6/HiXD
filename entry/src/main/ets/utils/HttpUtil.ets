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
          if (!this.cookieStore[entry.domain]) {
            this.cookieStore[entry.domain] = {};
          }
          this.cookieStore[entry.domain][entry.name] = entry.value;
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
        const msg: string = (be && be.message) ? be.message : String(e);
        console.error('[RcpHttp] getArrayBuffer failed code=' + (be ? be.code : '?') + ' msg=' + msg + ' url=' + safeUrl);
        throw new Error('HTTP ' + (be ? be.code : '?') + ': ' + msg);
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
      const msg: string = (be && be.message) ? be.message : String(e);
      console.error('[RcpHttp] request failed code=' + (be ? be.code : '?') + ' msg=' + msg + ' url=' + safeUrl);
      throw new Error('HTTP ' + (be ? be.code : '?') + ': ' + msg);
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

    // body：ArrayBuffer → string
    out.body = this.decodeBody(resp.body);

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

  // ArrayBuffer → UTF-8 string
  private decodeBody(buf: ArrayBuffer | undefined): string {
    if (!buf || buf.byteLength === 0) {
      return '';
    }
    try {
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (e) {
      return '';
    }
  }

  private getDomain(url: string): string {
    const m = url.match(/https?:\/\/([^/]+)/);
    return m ? m[1] : url;
  }

  // 将重定向 Location 解析为绝对 URL（支持绝对地址、协议相对 //host/path、根相对 /path、目录相对 path）
  private resolveRedirect(location: string, baseUrl: string): string {
    if (location.startsWith('//')) {
      const proto: string = baseUrl.startsWith('https') ? 'https:' : 'http:';
      return proto + location;
    }
    if (/^https?:\/\//i.test(location)) {
      return location;
    }
    const m = baseUrl.match(/^https?:\/\/[^/]+/);
    const origin: string = m ? m[0] : baseUrl;
    if (location.startsWith('/')) {
      return origin + location;
    }
    const lastSlash: number = baseUrl.lastIndexOf('/');
    const dir: string = lastSlash >= 0 ? baseUrl.substring(0, lastSlash + 1) : origin + '/';
    return dir + location;
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
    const MAX_REDIRECTS: number = 20;
    let currentUrl: string = url;
    let currentMethod: 'GET' | 'POST' = method === 'GET' ? 'GET' : 'POST';
    let currentBody: string | undefined = body;
    let lastResp: HttpResponse | undefined = undefined;
    const visited: Set<string> = new Set<string>();
    visited.add(currentUrl);

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
