// HttpUtil.ets — 带 Cookie 持久化的 HTTP 客户端
import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferenceUtil } from './PreferenceUtil';

const TAG = 'HttpUtil';

export class HttpResponse {
  statusCode: number = 0;
  body: string = '';
  headers: Record<string, string> = {};
  isRedirect: boolean = false;
  location: string | undefined = undefined;

  get isOk(): boolean { return this.statusCode >= 200 && this.statusCode < 300; }

  json<T>(): T { return JSON.parse(this.body) as T; }
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

  private constructor() {}

  static getInstance(): HttpUtil {
    if (!HttpUtil.instance) HttpUtil.instance = new HttpUtil();
    return HttpUtil.instance;
  }

  // ===== Cookie 持久化 =====

  async loadCookies(): Promise<void> {
    if (this.cookiesLoaded) return;
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
        console.info(TAG, `Loaded ${entries.length} cookies`);
      }
    } catch (e) {
      console.warn(TAG, 'Failed to load cookies: ' + JSON.stringify(e));
    }
    this.cookiesLoaded = true;
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
      console.info(TAG, `Saved ${entries.length} cookies`);
    } catch (e) {
      console.error(TAG, 'Failed to save cookies: ' + JSON.stringify(e));
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
    console.info(TAG, `Injected cookies for ${domain}, memory store refreshed`);
  }

  // ===== HTTP 方法 =====

  async get(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    return this.request(url, 'GET', undefined, headers);
  }

  async getWithQuery(url: string, queryParams: Record<string, string>, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    const parts: string[] = [];
    for (const key of Object.keys(queryParams)) {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(queryParams[key]));
    }
    const fullUrl = url + (url.includes('?') ? '&' : '?') + parts.join('&');
    return this.request(fullUrl, 'GET', undefined, headers);
  }

  async post(url: string, data: Object, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    return this.postRaw(url, JSON.stringify(data), 'application/json', headers);
  }

  async postForm(url: string, data: Record<string, string>, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    const parts: string[] = [];
    for (const key of Object.keys(data)) {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(data[key]));
    }
    return this.postRaw(url, parts.join('&'), 'application/x-www-form-urlencoded; charset=UTF-8', headers);
  }

  async postRaw(url: string, bodyStr: string, contentType: string, headers?: Record<string, string>): Promise<HttpResponse> {
    const allHeaders: Record<string, string> = { 'Content-Type': contentType };
    if (headers) {
      for (const key of Object.keys(headers)) {
        allHeaders[key] = headers[key];
      }
    }
    return this.request(url, 'POST', bodyStr, allHeaders);
  }

  // POST 无 body、无 Content-Type（用于 xgxt getAppConfig.do 等仅需 query params 的 API）
  async postEmpty(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    return this.request(url, 'POST', undefined, headers);
  }

  getCookiesForDomain(domain: string): string {
    const domMap = this.cookieStore[domain];
    const parts: string[] = [];
    if (domMap) {
      for (const name of Object.keys(domMap)) {
        parts.push(name + '=' + domMap[name]);
      }
    }
    let result: string = parts.join('; ');
    // 对 ehall 域强制注入 MOD_AUTH_CAS（冗余保护：即使 cookie store 出问题也能正常工作）
    if (domain === 'ehall.xidian.edu.cn' && result.indexOf('MOD_AUTH_CAS') < 0) {
      const modCas: string = PreferenceUtil.getString('mod_auth_cas');
      if (modCas.length > 0) {
        result = result.length > 0 ? result + '; MOD_AUTH_CAS=' + modCas : 'MOD_AUTH_CAS=' + modCas;
        console.info(TAG, 'Injected MOD_AUTH_CAS from PreferenceUtil');
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

  // 深拷贝整个 cookieStore（对象引用，不受后续修改影响）
  cloneCookieStore(): Record<string, Record<string, string>> {
    const clone: Record<string, Record<string, string>> = {};
    for (const domain of Object.keys(this.cookieStore)) {
      clone[domain] = {};
      for (const name of Object.keys(this.cookieStore[domain])) {
        clone[domain][name] = this.cookieStore[domain][name];
      }
    }
    return clone;
  }

  // 从快照中恢复指定域名的 cookie（不受字符串序列化丢数据影响）
  restoreDomainsFromClone(clone: Record<string, Record<string, string>>, domains: string[]): void {
    for (let i: number = 0; i < domains.length; i++) {
      const domain: string = domains[i];
      this.cookieStore[domain] = {};
      if (clone[domain]) {
        for (const name of Object.keys(clone[domain])) {
          this.cookieStore[domain][name] = clone[domain][name];
        }
      }
    }
  }

  // 公开方法，供 CasLoginService 等外部调用者保存 cookie
  saveResponseCookies(domain: string, setCookieHeader: string): void {
    if (!this.cookieStore[domain]) {
      this.cookieStore[domain] = {};
    }
    const cookies = setCookieHeader.split(/,(?=\s*\w+=)/);
    for (const cookie of cookies) {
      const first = cookie.split(';')[0].trim();
      const eq = first.indexOf('=');
      if (eq > 0) {
        const name = first.substring(0, eq).trim();
        const value = first.substring(eq + 1).trim();
        if (name.length > 0) {
          this.cookieStore[domain][name] = value;
        }
      }
    }
  }

  private getDomain(url: string): string {
    const m = url.match(/https?:\/\/([^/]+)/);
    return m ? m[1] : url;
  }

  /**
   * 发送 GET 请求但不自动跟随重定向。
   * HarmonyOS NETSTACK 不支持 followRedirects: false，
   * 此方法通过 on('headersReceive') 拦截 302 响应头，
   * 读取 Location 后立即 destroy 请求，避免自动跟随重定向。
   * 返回的 HttpResponse 中 location 字段包含重定向地址。
   */
  async getNoRedirect(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    return new Promise<HttpResponse>((resolve, reject) => {
      const req = http.createHttp();
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

      const domain = this.getDomain(url);
      const cookieStr = this.getCookiesForDomain(domain);
      if (cookieStr.length > 0) {
        reqHeaders['Cookie'] = cookieStr;
      }

      let resolved = false;
      const resp = new HttpResponse();
      const self = this; // 缓存 this 引用，避免闭包问题

      // 拦截响应头 — 如果是 302，读取 Location 后立即中止请求
      req.on('headersReceive', (header: Object) => {
        const hdr = header as Record<string, string | number | string[]>;
        const statusCode = Number(hdr['statusCode'] || 0);
        if (statusCode >= 300 && statusCode < 400) {
          // 重定向响应 — 读取 Location
          const rawLocation = hdr['location'] || hdr['Location'] || '';
          const location: string = typeof rawLocation === 'string' ? rawLocation : String(rawLocation);
          resp.statusCode = statusCode;
          resp.isRedirect = true;
          resp.location = location;
          resp.headers = {};
          const headerKeys = Object.keys(hdr);
          for (let i = 0; i < headerKeys.length; i++) {
            const key = headerKeys[i];
            const v = hdr[key];
            resp.headers[key] = typeof v === 'string' ? v : String(v);
          }
          // 保存 Set-Cookie
          const sc = hdr['set-cookie'] || hdr['Set-Cookie'];
          if (sc) {
            self.saveResponseCookies(domain, typeof sc === 'string' ? sc : String(sc));
            self.saveCookies().catch(() => {});
          }
          // 中止请求，阻止自动重定向
          resolved = true;
          req.destroy();
          resolve(resp);
        }
      });

      req.request(
        url,
        {
          method: http.RequestMethod.GET,
          header: reqHeaders,
          expectDataType: http.HttpDataType.STRING,
          readTimeout: 20000,
          connectTimeout: 15000,
        },
        async (err: BusinessError | undefined, data: http.HttpResponse) => {
          if (resolved) {
            // 已经在 headersReceive 中 resolve 了，忽略
            return;
          }
          if (err !== undefined && err.code !== 0) {
            reject(new Error('HTTP ' + err.code + ': ' + err.message));
            req.destroy();
            return;
          }
          resp.statusCode = data.responseCode;

          const rawH = data.header as Record<string, string | number | string[]>;
          const respHeaders: Record<string, string> = {};
          for (const key of Object.keys(rawH)) {
            const v = rawH[key];
            respHeaders[key] = typeof v === 'string' ? v : String(v);
          }
          resp.headers = respHeaders;

          const raw = data.result;
          resp.body = typeof raw === 'string' ? raw : '';
          resp.isRedirect = resp.statusCode >= 300 && resp.statusCode < 400;
          resp.location = respHeaders['location'] || respHeaders['Location'];

          const sc = respHeaders['set-cookie'] || respHeaders['Set-Cookie'];
          if (sc) {
            this.saveResponseCookies(domain, sc);
            this.saveCookies().catch(() => {});
          }

          req.destroy();
          resolve(resp);
        }
      );
    });
  }

  /**
   * 发送 POST 请求但不自动跟随重定向。
   * 与 getNoRedirect 相同原理，但支持 POST body。
   */
  async postNoRedirect(url: string, bodyStr: string, headers?: Record<string, string>): Promise<HttpResponse> {
    await this.loadCookies();
    return new Promise<HttpResponse>((resolve, reject) => {
      const req = http.createHttp();
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

      const domain = this.getDomain(url);
      const cookieStr = this.getCookiesForDomain(domain);
      if (cookieStr.length > 0) {
        reqHeaders['Cookie'] = cookieStr;
      }

      let resolved = false;
      const resp = new HttpResponse();
      const self = this;

      req.on('headersReceive', (header: Object) => {
        const hdr = header as Record<string, string | number | string[]>;
        const statusCode = Number(hdr['statusCode'] || 0);
        if (statusCode >= 300 && statusCode < 400) {
          const rawLocation = hdr['location'] || hdr['Location'] || '';
          const location: string = typeof rawLocation === 'string' ? rawLocation : String(rawLocation);
          resp.statusCode = statusCode;
          resp.isRedirect = true;
          resp.location = location;
          resp.headers = {};
          const headerKeys = Object.keys(hdr);
          for (let i = 0; i < headerKeys.length; i++) {
            const key = headerKeys[i];
            const v = hdr[key];
            resp.headers[key] = typeof v === 'string' ? v : String(v);
          }
          const sc = hdr['set-cookie'] || hdr['Set-Cookie'];
          if (sc) {
            self.saveResponseCookies(domain, typeof sc === 'string' ? sc : String(sc));
            self.saveCookies().catch(() => {});
          }
          resolved = true;
          req.destroy();
          resolve(resp);
        }
      });

      req.request(
        url,
        {
          method: http.RequestMethod.POST,
          header: reqHeaders,
          extraData: bodyStr,
          expectDataType: http.HttpDataType.STRING,
          readTimeout: 20000,
          connectTimeout: 15000,
        },
        async (err: BusinessError | undefined, data: http.HttpResponse) => {
          if (resolved) {
            return;
          }
          if (err !== undefined && err.code !== 0) {
            reject(new Error('HTTP ' + err.code + ': ' + err.message));
            req.destroy();
            return;
          }
          resp.statusCode = data.responseCode;

          const rawH = data.header as Record<string, string | number | string[]>;
          const respHeaders: Record<string, string> = {};
          for (const key of Object.keys(rawH)) {
            const v = rawH[key];
            respHeaders[key] = typeof v === 'string' ? v : String(v);
          }
          resp.headers = respHeaders;

          const raw = data.result;
          resp.body = typeof raw === 'string' ? raw : '';
          resp.isRedirect = resp.statusCode >= 300 && resp.statusCode < 400;
          resp.location = respHeaders['location'] || respHeaders['Location'];

          const sc = respHeaders['set-cookie'] || respHeaders['Set-Cookie'];
          if (sc) {
            this.saveResponseCookies(domain, sc);
            this.saveCookies().catch(() => {});
          }

          req.destroy();
          resolve(resp);
        }
      );
    });
  }

  private async request(
    url: string,
    method: string,
    body: string | undefined,
    extraHeaders: Record<string, string> | undefined
  ): Promise<HttpResponse> {
    return new Promise<HttpResponse>((resolve, reject) => {
      const req = http.createHttp();
      const reqHeaders: Record<string, string> = {};

      if (extraHeaders) {
        for (const key of Object.keys(extraHeaders)) {
          reqHeaders[key] = extraHeaders[key];
        }
      }

      if (!reqHeaders['User-Agent'] && !reqHeaders['user-agent']) {
        reqHeaders['User-Agent'] =
          'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
      }

      const domain = this.getDomain(url);
      const cookieStr = this.getCookiesForDomain(domain);
      if (cookieStr.length > 0) {
        reqHeaders['Cookie'] = cookieStr;
      }

      const httpMethod = method === 'GET' ? http.RequestMethod.GET : http.RequestMethod.POST;

      // 捕获中间重定向的 Set-Cookie（不阻止重定向，只存 cookie）
      req.on('headersReceive', (header: Object) => {
        const hdr = header as Record<string, string | number | string[]>;
        const sc = hdr['set-cookie'] || hdr['Set-Cookie'];
        if (sc) {
          const loc = hdr['location'] || hdr['Location'] || '';
          const locStr: string = typeof loc === 'string' ? loc : String(loc);
          const redirectDomain: string = locStr.length > 0 ? this.getDomain(locStr) : this.getDomain(url);
          this.saveResponseCookies(redirectDomain, typeof sc === 'string' ? sc : String(sc));
          this.saveCookies().catch(() => {});
        }
      });

      // body 为 undefined 时不传 extraData（真正的空 POST）；为 '' 时仍需传（form 空串）
      const noBody: boolean = body === undefined;
      if (noBody) {
        req.request(
          url,
          {
            method: httpMethod,
            header: reqHeaders,
            expectDataType: http.HttpDataType.STRING,
            readTimeout: 20000,
            connectTimeout: 15000,
          },
          async (err: BusinessError | undefined, data: http.HttpResponse) => {
            if (err !== undefined && err.code !== 0) {
              reject(new Error('HTTP ' + err.code + ': ' + err.message));
              req.destroy();
              return;
            }
            const resp = new HttpResponse();
            resp.statusCode = data.responseCode;

            const rawH = data.header as Record<string, string | number | string[]>;
            const respHeaders: Record<string, string> = {};
            for (const key of Object.keys(rawH)) {
              const v = rawH[key];
              respHeaders[key] = typeof v === 'string' ? v : String(v);
            }
            resp.headers = respHeaders;

            const raw = data.result;
            resp.body = typeof raw === 'string' ? raw : '';
            resp.isRedirect = resp.statusCode >= 300 && resp.statusCode < 400;
            resp.location = respHeaders['location'] || respHeaders['Location'];

            const sc = respHeaders['set-cookie'] || respHeaders['Set-Cookie'];
            if (sc) {
              this.saveResponseCookies(domain, sc);
              this.saveCookies().catch(() => {});
            }

            req.destroy();
            resolve(resp);
          }
        );
      } else {
        req.request(
          url,
          {
            method: httpMethod,
            header: reqHeaders,
            extraData: body as string,
            expectDataType: http.HttpDataType.STRING,
            readTimeout: 20000,
            connectTimeout: 15000,
          },
          async (err: BusinessError | undefined, data: http.HttpResponse) => {
            if (err !== undefined && err.code !== 0) {
              reject(new Error('HTTP ' + err.code + ': ' + err.message));
              req.destroy();
              return;
            }
            const resp = new HttpResponse();
            resp.statusCode = data.responseCode;

            const rawH = data.header as Record<string, string | number | string[]>;
            const respHeaders: Record<string, string> = {};
            for (const key of Object.keys(rawH)) {
              const v = rawH[key];
              respHeaders[key] = typeof v === 'string' ? v : String(v);
            }
            resp.headers = respHeaders;

            const raw = data.result;
            resp.body = typeof raw === 'string' ? raw : '';
            resp.isRedirect = resp.statusCode >= 300 && resp.statusCode < 400;
            resp.location = respHeaders['location'] || respHeaders['Location'];

            const sc = respHeaders['set-cookie'] || respHeaders['Set-Cookie'];
            if (sc) {
              this.saveResponseCookies(domain, sc);
              this.saveCookies().catch(() => {});
            }

            req.destroy();
            resolve(resp);
          }
        );
      }
    });
  }
}