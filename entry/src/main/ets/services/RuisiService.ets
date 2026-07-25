// RuisiService.ets — 睿思论坛独立 HTTP 客户端
// 独立 Cookie 存储（持久化到 PreferenceUtil，key: 'ruisi_cookies'）
// 不复用西电 IDS 的 cookie

import { http } from '@kit.NetworkKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { RuisiConstants } from './RuisiModels';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'RuisiService';
const DOMAIN = 0xFF00;

export class RuisiResponse {
  statusCode: number = 0;
  body: string = '';
  headers: Record<string, string> = {};
  isRedirect: boolean = false;
  location: string | undefined = undefined;
  rawBytes?: ArrayBuffer; // 原始响应字节（二进制/expectDataType=ARRAY_BUFFER 时填充），用于诊断

  get isOk(): boolean { return this.statusCode >= 200 && this.statusCode < 300; }
}

interface RuisiCookieEntry {
  name: string;
  value: string;
  path: string;
}

export class RuisiService {
  private static instance: RuisiService;
  private cookieStore: Record<string, string> = {};
  private cookiesLoaded: boolean = false;
  private formhash: string = '';

  private constructor() {}

  static getInstance(): RuisiService {
    if (!RuisiService.instance) RuisiService.instance = new RuisiService();
    return RuisiService.instance;
  }

  // ===== Cookie 持久化 =====

  async loadCookies(): Promise<void> {
    if (this.cookiesLoaded) return;
    try {
      const raw: string = PreferenceUtil.getString(RuisiConstants.COOKIE_KEY);
      if (raw.length > 0) {
        const entries: RuisiCookieEntry[] = JSON.parse(raw) as RuisiCookieEntry[];
        for (const entry of entries) {
          this.cookieStore[entry.name] = entry.value;
        }
        this.cookiesLoaded = true;
      } else {
        this.cookiesLoaded = true;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadCookies failed: ' + JSON.stringify(e));
    }
  }

  async saveCookies(): Promise<void> {
    try {
      const entries: RuisiCookieEntry[] = [];
      for (const name of Object.keys(this.cookieStore)) {
        entries.push({ name, value: this.cookieStore[name], path: '/' });
      }
      await PreferenceUtil.putString(RuisiConstants.COOKIE_KEY, JSON.stringify(entries));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveCookies failed: ' + JSON.stringify(e));
    }
  }

  async clearCookies(): Promise<void> {
    this.cookieStore = {};
    this.cookiesLoaded = false;
    this.formhash = '';
    await PreferenceUtil.putString(RuisiConstants.COOKIE_KEY, '');
    await PreferenceUtil.putString(RuisiConstants.FORMHASH_KEY, '');
    await PreferenceUtil.putString(RuisiConstants.LOGIN_STATUS_KEY, '');
  }

  hasCookies(): boolean {
    return Object.keys(this.cookieStore).length > 0;
  }

  getCookieString(): string {
    const parts: string[] = [];
    for (const name of Object.keys(this.cookieStore)) {
      parts.push(name + '=' + this.cookieStore[name]);
    }
    return parts.join('; ');
  }

  private saveResponseCookies(setCookieHeader: string): void {
    const cookies = setCookieHeader.split(/,(?=\s*[^,;=]+=)/);
    for (const cookie of cookies) {
      const first = cookie.split(';')[0].trim();
      const eq = first.indexOf('=');
      if (eq > 0) {
        const name = first.substring(0, eq).trim();
        const value = first.substring(eq + 1).trim();
        if (name.length > 0 && value.length > 0) {
          this.cookieStore[name] = value;
        }
      }
    }
  }

  // ===== formhash 管理 =====

  getFormhash(): string { return this.formhash; }

  setFormhash(hash: string): void {
    this.formhash = hash;
    PreferenceUtil.putString(RuisiConstants.FORMHASH_KEY, hash);
  }

  async loadFormhash(): Promise<void> {
    this.formhash = PreferenceUtil.getString(RuisiConstants.FORMHASH_KEY);
  }

  // ===== MD5 实现（使用系统 cryptoFramework） =====

  async md5(input: string): Promise<string> {
    const encoder = new util.TextEncoder();
    const dataBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(input) };
    const md5Alg = cryptoFramework.createMd('MD5');
    md5Alg.update(dataBlob);
    const result: cryptoFramework.DataBlob = await md5Alg.digest();
    // 转换为小写 hex 字符串
    let hex = '';
    for (const b of result.data) {
      hex += (b & 0xFF).toString(16).padStart(2, '0');
    }
    return hex;
  }

  // ===== HTTP 方法 =====

  async get(url: string, headers?: Record<string, string>): Promise<RuisiResponse> {
    await this.loadCookies();
    return this.request(url, 'GET', undefined, headers);
  }

  async post(url: string, data: Record<string, string>, headers?: Record<string, string>): Promise<RuisiResponse> {
    await this.loadCookies();
    const parts: string[] = [];
    // 自动注入 formhash
    if (data['formhash'] === undefined && this.formhash.length > 0) {
      data['formhash'] = this.formhash;
    }
    for (const key of Object.keys(data)) {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(data[key]));
    }
    const bodyStr = parts.join('&');
    const allHeaders: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (headers) {
      for (const k of Object.keys(headers)) allHeaders[k] = headers[k];
    }
    return this.request(url, 'POST', bodyStr, allHeaders);
  }

  // 直接发送原始字节（multipart 图片上传），避免二进制经字符串 UTF-8 编码损坏
  async postRaw(url: string, body: string | Uint8Array, headers?: Record<string, string>): Promise<RuisiResponse> {
    await this.loadCookies();
    const allHeaders: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (headers) {
      for (const k of Object.keys(headers)) allHeaders[k] = headers[k];
    }
    // 上传用原始字节接收：服务器对 swfupload 可能返回一整页(GBK/大体积)HTML，
    // expectDataType=STRING 会因解码失败使 data.result 变 undefined → body 空。
    // 改为 ARRAY_BUFFER 自己拿原始字节再解码，避免被 HarmonyOS 吞掉。
    return this.request(url, 'POST', body, allHeaders, true);
  }

  // 使用 rcp（Remote Communication Kit）发送原始字节（图片上传专用）。
  // 关键：原生 http 对 ≥2MB 响应体既不填 data.result 也不触发 dataReceive，会直接丢弃；
  // rcp 完整返回响应体（response.body 为 ArrayBuffer，无 2MB 上限），可稳定读取
  // swfupload 返回的成功串(DISCUZUPLOAD|0|0|aid|...)或 2MB 错误页(用于暴露服务端拒因)。
  async postRawRcp(url: string, body: Uint8Array, headers?: Record<string, string>): Promise<RuisiResponse> {
    await this.loadCookies();
    const resp = new RuisiResponse();
    let session: rcp.Session | undefined;
    try {
      session = rcp.createSession();
      const reqHeaders: rcp.RequestHeaders = {
        'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
      };
      if (headers) {
        for (const k of Object.keys(headers)) reqHeaders[k] = headers[k];
      }
      const cookieStr = this.getCookieString();
      if (cookieStr.length > 0) reqHeaders['Cookie'] = cookieStr;

      const request = new rcp.Request(url, 'POST', reqHeaders, body.buffer);
      const response: rcp.Response = await session.fetch(request);
      resp.statusCode = response.statusCode;
      const rawH = response.headers as Record<string, string | string[]>;
      const respHeaders: Record<string, string> = {};
      let setCookieRaw: string | undefined;
      for (const key of Object.keys(rawH)) {
        const v = rawH[key];
        const val = Array.isArray(v) ? v.join(', ') : String(v);
        respHeaders[key] = val;
        if (key.toLowerCase() === 'set-cookie') setCookieRaw = val;
      }
      resp.headers = respHeaders;
      if (setCookieRaw) {
        this.saveResponseCookies(setCookieRaw);
        this.saveCookies().catch(() => {});
      }
      // 响应体：rcp 完整返回（ArrayBuffer），自行 UTF-8 解码（GBK 页会乱码但 DISCUZUPLOAD/错误关键词仍可读）
      const bodyData = response.body;
      if (typeof bodyData === 'string') {
        resp.body = bodyData;
      } else if (bodyData instanceof ArrayBuffer) {
        resp.rawBytes = bodyData;
        try {
          resp.body = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bodyData));
        } catch (e) {
          resp.body = '';
        }
      } else {
        // 兜底：个别情况下 body 为其它类型，直接用 String 取文本
        try {
          resp.body = String(bodyData);
        } catch (e) {
          resp.body = '';
        }
      }
    } catch (e) {
      resp.statusCode = 0;
      resp.body = '';
    } finally {
      if (session) session.close();
    }
    return resp;
  }

  // POST 不跟随重定向（用于搜索等需要手动处理 302 的场景）
  async postNoRedirect(url: string, bodyStr: string, headers?: Record<string, string>): Promise<RuisiResponse> {
    await this.loadCookies();
    const allHeaders: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (headers) {
      for (const k of Object.keys(headers)) allHeaders[k] = headers[k];
    }
    return this.requestNoRedirect(url, bodyStr, allHeaders);
  }

  // POST 跟随 302 重定向
  async postFollowRedirect(url: string, data: Record<string, string>, headers?: Record<string, string>): Promise<RuisiResponse> {
    await this.loadCookies();
    const parts: string[] = [];
    if (data['formhash'] === undefined && this.formhash.length > 0) {
      data['formhash'] = this.formhash;
    }
    for (const key of Object.keys(data)) {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(data[key]));
    }
    const bodyStr = parts.join('&');
    const allHeaders: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (headers) {
      for (const k of Object.keys(headers)) allHeaders[k] = headers[k];
    }
    let resp = await this.requestNoRedirect(url, bodyStr, allHeaders);
    let redirectCount = 0;
    while (resp.isRedirect && resp.location && redirectCount < 5) {
      redirectCount++;
      let loc = resp.location;
      if (loc.startsWith('http://') || loc.startsWith('https://')) {
        // 绝对 URL
      } else if (loc.startsWith('/')) {
        loc = 'https://' + RuisiConstants.DOMAIN + loc;
      } else {
        loc = 'https://' + RuisiConstants.DOMAIN + '/' + loc;
      }
      resp = await this.request(loc, 'GET', undefined, undefined);
    }
    return resp;
  }

  // 获取验证码图片二进制
  async getRaw(url: string, headers?: Record<string, string>): Promise<ArrayBuffer> {
    await this.loadCookies();
    return new Promise<ArrayBuffer>((resolve, reject) => {
      const req = http.createHttp();
      const reqHeaders: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
      };
      if (headers) {
        for (const k of Object.keys(headers)) reqHeaders[k] = headers[k];
      }
      const cookieStr = this.getCookieString();
      if (cookieStr.length > 0) reqHeaders['Cookie'] = cookieStr;

      req.on('headersReceive', (header: Object) => {
        const hdr = header as Record<string, string | number | string[]>;
        const sc = hdr['set-cookie'] || hdr['Set-Cookie'];
        if (sc) {
          this.saveResponseCookies(typeof sc === 'string' ? sc : String(sc));
          this.saveCookies().catch(() => {});
        }
      });

      req.request(url, {
        method: http.RequestMethod.GET,
        header: reqHeaders,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 30000,
        connectTimeout: 15000,
      }, (err: BusinessError | undefined, data: http.HttpResponse) => {
        if (err !== undefined && err.code !== 0) {
          req.destroy();
          reject(new Error('HTTP ' + err.code + ': ' + err.message));
          return;
        }
        req.destroy();
        if (data.result instanceof ArrayBuffer) {
          resolve(data.result as ArrayBuffer);
        } else {
          reject(new Error('getRaw: unexpected result type'));
        }
      });
    });
  }

  // ===== 底层请求 =====

  private async request(
    url: string,
    method: string,
    body: string | Uint8Array | undefined,
    extraHeaders: Record<string, string> | undefined,
    expectBinary: boolean = false
  ): Promise<RuisiResponse> {
    return new Promise<RuisiResponse>((resolve, reject) => {
      const req = http.createHttp();
      const reqHeaders: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
      };
      if (extraHeaders) {
        for (const k of Object.keys(extraHeaders)) reqHeaders[k] = extraHeaders[k];
      }
      const cookieStr = this.getCookieString();
      if (cookieStr.length > 0) reqHeaders['Cookie'] = cookieStr;

      // 捕获中间重定向的 Set-Cookie
      req.on('headersReceive', (header: Object) => {
        const hdr = header as Record<string, string | number | string[]>;
        const sc = hdr['set-cookie'] || hdr['Set-Cookie'];
        if (sc) {
          this.saveResponseCookies(typeof sc === 'string' ? sc : String(sc));
          this.saveCookies().catch(() => {});
        }
      });

      // 大响应体（如 2MB 上传回包）HarmonyOS 不会填 data.result，需经 dataReceive 流式分片接收
      const chunks: ArrayBuffer[] = [];
      req.on('dataReceive', (data: ArrayBuffer) => {
        if (data && data.byteLength > 0) chunks.push(data);
      });

      const httpMethod = method === 'GET' ? http.RequestMethod.GET : http.RequestMethod.POST;
      const opts: http.HttpRequestOptions = {
        method: httpMethod,
        header: reqHeaders,
        expectDataType: expectBinary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
        readTimeout: 30000,
        connectTimeout: 15000,
      };
      if (body !== undefined) opts.extraData = body;

      req.request(url, opts, (err: BusinessError | undefined, data: http.HttpResponse) => {
        if (err !== undefined && err.code !== 0) {
          hilog.error(DOMAIN, TAG, 'HTTP failed code=' + err.code + ' msg=' + err.message + ' url=' + url);
          req.destroy();
          reject(new Error('HTTP ' + err.code + ': ' + err.message));
          return;
        }
        const resp = new RuisiResponse();
        resp.statusCode = data.responseCode;
        const rawH = data.header as Record<string, string | number | string[]>;
        const respHeaders: Record<string, string> = {};
        for (const key of Object.keys(rawH)) {
          const v = rawH[key];
          respHeaders[key] = typeof v === 'string' ? v : String(v);
        }
        resp.headers = respHeaders;
        // data.result 在大响应体时可能为 undefined，回退用 dataReceive 攒下的分片拼装
        // HttpResponse.result 类型为 string | Object | ArrayBuffer，需放宽标注
        let raw: string | Object | ArrayBuffer | undefined = data.result;
        if (raw === undefined && chunks.length > 0) {
          let total = 0;
          for (const c of chunks) total += c.byteLength;
          const merged = new Uint8Array(total);
          let off = 0;
          for (const c of chunks) {
            const u = new Uint8Array(c);
            merged.set(u, off);
            off += u.byteLength;
          }
          raw = merged.buffer;
        }
        if (typeof raw === 'string') {
          resp.body = raw;
        } else if (raw instanceof ArrayBuffer) {
          // 二进制接收（上传场景）或 STRING 失效时，data.result 为 ArrayBuffer，
          // 自行 UTF-8 解码（GBK 页面会乱码但 ASCII 关键字/DISCUZUPLOAD 仍可读）
          resp.rawBytes = raw;
          try {
            resp.body = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(raw));
          } catch (e) {
            resp.body = '';
          }
        } else {
          resp.body = '';
        }
        resp.isRedirect = resp.statusCode >= 300 && resp.statusCode < 400;
        resp.location = respHeaders['location'] || respHeaders['Location'];
        const sc = respHeaders['set-cookie'] || respHeaders['Set-Cookie'];
        if (sc) {
          this.saveResponseCookies(sc);
          this.saveCookies().catch(() => {});
        }
        req.destroy();
        resolve(resp);
      });
    });
  }

  private requestNoRedirect(
    url: string,
    bodyStr: string,
    headers: Record<string, string>
  ): Promise<RuisiResponse> {
    return new Promise<RuisiResponse>((resolve, reject) => {
      const req = http.createHttp();
      const reqHeaders: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36',
      };
      for (const k of Object.keys(headers)) reqHeaders[k] = headers[k];
      const cookieStr = this.getCookieString();
      if (cookieStr.length > 0) reqHeaders['Cookie'] = cookieStr;

      let resolved = false;
      const resp = new RuisiResponse();
      const self = this;

      req.on('headersReceive', (header: Object) => {
        const hdr = header as Record<string, string | number | string[]>;
        const statusCode = Number(hdr['statusCode'] || 0);
        if (statusCode >= 300 && statusCode < 400) {
          const rawLoc = hdr['location'] || hdr['Location'] || '';
          const location: string = typeof rawLoc === 'string' ? rawLoc : String(rawLoc);
          resp.statusCode = statusCode;
          resp.isRedirect = true;
          resp.location = location;
          resp.headers = {};
          const sc = hdr['set-cookie'] || hdr['Set-Cookie'];
          if (sc) {
            self.saveResponseCookies(typeof sc === 'string' ? sc : String(sc));
            self.saveCookies().catch(() => {});
          }
          resolved = true;
          req.destroy();
          resolve(resp);
        }
      });

      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: reqHeaders,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 30000,
        connectTimeout: 15000,
        extraData: bodyStr,
      };

      req.request(url, opts, (err: BusinessError | undefined, data: http.HttpResponse) => {
        if (resolved) return;
        if (err !== undefined && err.code !== 0) {
          req.destroy();
          reject(new Error('HTTP ' + err.code + ': ' + err.message));
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
        if (typeof raw === 'string') {
          resp.body = raw;
        } else if (raw instanceof ArrayBuffer) {
          // 二进制接收（上传场景）或 STRING 失效时，data.result 为 ArrayBuffer，
          // 自行 UTF-8 解码（GBK 页面会乱码但 ASCII 关键字/DISCUZUPLOAD 仍可读）
          resp.rawBytes = raw;
          try {
            resp.body = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(raw));
          } catch (e) {
            resp.body = '';
          }
        } else {
          resp.body = '';
        }
        resp.isRedirect = resp.statusCode >= 300 && resp.statusCode < 400;
        resp.location = respHeaders['location'] || respHeaders['Location'];
        const sc = respHeaders['set-cookie'] || respHeaders['Set-Cookie'];
        if (sc) {
          this.saveResponseCookies(sc);
          this.saveCookies().catch(() => {});
        }
        req.destroy();
        resolve(resp);
      });
    });
  }

  // ===== 登录态管理 =====

  isLoggedIn(): boolean {
    return this.hasCookies() && PreferenceUtil.getString(RuisiConstants.LOGIN_STATUS_KEY) === 'true';
  }

  async setLoggedIn(loggedIn: boolean): Promise<void> {
    await PreferenceUtil.putString(RuisiConstants.LOGIN_STATUS_KEY, loggedIn ? 'true' : 'false');
  }

  getUid(): number {
    return PreferenceUtil.getNumber(RuisiConstants.UID_KEY, 0);
  }

  async setUid(uid: number): Promise<void> {
    await PreferenceUtil.putNumber(RuisiConstants.UID_KEY, uid);
  }

  getUsername(): string {
    return PreferenceUtil.getString(RuisiConstants.USERNAME_KEY);
  }

  async setUsername(name: string): Promise<void> {
    await PreferenceUtil.putString(RuisiConstants.USERNAME_KEY, name);
  }

  getPassword(): string {
    return PreferenceUtil.getString(RuisiConstants.PASSWORD_KEY);
  }

  async setPassword(pwd: string): Promise<void> {
    await PreferenceUtil.putString(RuisiConstants.PASSWORD_KEY, pwd);
  }
}


