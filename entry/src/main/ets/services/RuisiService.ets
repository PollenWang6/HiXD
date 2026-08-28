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
import { asset } from '@kit.AssetStoreKit';

const TAG = 'RuisiService';
const DOMAIN = 0xFF00;

// 睿思全部请求统一 UA：对齐官方 Flutter 客户端 ruisi_flutter 的 dio 默认 UA。
// 桌面/移动模板由 URL 参数（mobile=2）与 cookie 决定，与 UA 无关——
// 此 UA 不含「Mobile」字样，不会被服务端 UA 探测触发移动判定。
// 沙箱实测（2026-08-13）：用此 UA 登录 + 投票 + 抓帖全部成功，与 Flutter 日志一致。
const RUISI_DESKTOP_UA = 'myRuisiAsyncLiteHttp/1.0';

// Discuz 移动会话标记 cookie（cookiepre + 'mobile'）。会话一旦带它即被判定为移动会话，
// 套用移动组权限（allowvote 受限）→ 投票报「西电托儿所无法进行此操作」。
// 实测（2026-08-13 日志[38693]）：App 会话被某 mobile=2 接口种下此 cookie 后投票必败，
// 而 Flutter 成功会话（全程无 mobile=2、UA=myRuisiAsyncLiteHttp/1.0）无此 cookie。
// 处理：发送/保存/加载时全部剔除（服务端每次请求重新判定 mobile，无此 cookie + 桌面 UA = 桌面会话）。
// Discuz 会话【白名单】：只保留这些核心会话 cookie，其余一律不存不发。
// 实测（2026-08-13 沙箱）：账号登录后投票成功的完整 cookie 集合恰好只有这 12 个；
// App 会话多出的 connect_is_bind/home_diymode/nofavfid/st_p/visitedfid/viewid/
// loginuser/pmnum/mobile/activationauth 等均为服务端种下的辅助/污染 cookie——
// 不发不影响浏览/投票/回复等核心功能（服务端凭 auth+sid 识别用户），
// 但携带其中的污染值（如 activationauth=deleted）会导致会话被静默降级。
// 白名单 = 一次性的根治，杜绝「逐个过滤可疑 cookie」的打补丁循环。
const SESSION_COOKIES: string[] = [
  'Q8qA_2132_auth', 'Q8qA_2132_saltkey', 'Q8qA_2132_sid', 'Q8qA_2132_lip',
  'Q8qA_2132_lastvisit', 'Q8qA_2132_lastact', 'Q8qA_2132_ulastactivity',
  'Q8qA_2132_seccode', 'Q8qA_2132_checkfollow', 'Q8qA_2132_lastcheckfeed',
  'Q8qA_2132_myrepeat_rr', 'UqZBpD3n3iPIDwJU',
];

function isSessionCookie(name: string): boolean {
  return SESSION_COOKIES.indexOf(name) >= 0;
}

// 睿思密码加密存储别名（写入系统 Asset Store，设备级加密，非明文落盘）
const RUISI_PASSWORD_ASSET_ALIAS: Uint8Array = new util.TextEncoder().encodeInto('com.hixd.ruisi.password.v1');

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
  private password: string = '';
  private credentialsLoaded: boolean = false;
  // 退登写锁：clearCookies 执行期间置 true，阻止在途请求回包把旧 cookie 重新落盘
  private cookieWriteBlocked: boolean = false;

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
          // 白名单：只保留 Discuz 会话必需 cookie（实测沙箱成功会话恰为这 12 个）。
          // 其余（mobile/activationauth/loginuser/pmnum/connect_is_bind/home_diymode/
          // nofavfid/st_p/visitedfid/viewid 等）一律不加载——杜绝会话污染导致的
          // 服务端降级（投票报「西电托儿所无法进行此操作」）。
          if (!isSessionCookie(entry.name)) continue;
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
    if (this.cookieWriteBlocked) return; // 退登期间丢弃在途回包的落盘，避免旧 cookie 复活
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
    // 先上写锁：阻止随后到达的退登前在途请求回包调用 saveCookies 把旧 cookie 重新写回磁盘
    this.cookieWriteBlocked = true;
    this.cookieStore = {};
    this.cookiesLoaded = true; // 标记已加载，避免后续 loadCookies 又从磁盘把刚清掉的读回
    this.formhash = '';
    this.password = '';
    this.credentialsLoaded = true; // 内存密码已清，标记已加载避免被 loadCredentials 重新读回
    // 一并清掉用户名/uid，确保 checkAndAutoLogin 的凭证分支正确判定为「无凭证」而非凭残留用户名误重登
    await PreferenceUtil.putString(RuisiConstants.USERNAME_KEY, '');
    await PreferenceUtil.putString(RuisiConstants.UID_KEY, '0');
    await PreferenceUtil.putString(RuisiConstants.COOKIE_KEY, '');
    await PreferenceUtil.putString(RuisiConstants.FORMHASH_KEY, '');
    await PreferenceUtil.putString(RuisiConstants.LOGIN_STATUS_KEY, '');
    // 同步清除加密存储中的密码，避免登出后仍被自动重登
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, RUISI_PASSWORD_ASSET_ALIAS);
      await asset.remove(query);
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'clearCookies asset.remove (no record?): ' + String(e));
    }
    // 收尾解锁：之后的请求可正常落盘（此时 cookieStore 已空，落盘即空）
    this.cookieWriteBlocked = false;
  }

  hasCookies(): boolean {
    return Object.keys(this.cookieStore).length > 0;
  }

  // 清 cookie 与登录态偏好，但【保留用户名/密码（asset）】，并把 credentialsLoaded 复位，
  // 供「重新登录」使用：登录前先清掉可能残留的旧会话（旧 auth/sid/saltkey），
  // 确保本次登录从干净会话开始、建立全新的 auth——避免「新 auth 混入旧 cookie 集合」
  // 或「登录失败但旧 auth 让权威校验误判成功」导致的会话异常（投票报无权限）。
  async clearCookiesKeepCredentials(): Promise<void> {
    this.cookieWriteBlocked = true;
    this.cookieStore = {};
    this.cookiesLoaded = true; // 避免 loadCookies 从磁盘读回旧 cookie
    this.formhash = '';
    this.credentialsLoaded = false; // 允许 loadCredentials 重新从 asset 读回密码
    await PreferenceUtil.putString(RuisiConstants.UID_KEY, '0');
    await PreferenceUtil.putString(RuisiConstants.COOKIE_KEY, '');
    await PreferenceUtil.putString(RuisiConstants.FORMHASH_KEY, '');
    await PreferenceUtil.putString(RuisiConstants.LOGIN_STATUS_KEY, '');
    // 注意：USERNAME_KEY 与 asset 密码保留，供自动重登使用
    this.cookieWriteBlocked = false;
  }

  getCookieString(): string {
    const parts: string[] = [];
    for (const name of Object.keys(this.cookieStore)) {
      // 白名单：只发送核心会话 cookie（其它一律不带，杜绝污染）
      if (!isSessionCookie(name)) continue;
      parts.push(name + '=' + this.cookieStore[name]);
    }
    return parts.join('; ');
  }

  // 仅返回 cookie 名列表（诊断用，避免把 auth 等值打到日志）
  getCookieKeyList(): string[] {
    return Object.keys(this.cookieStore);
  }

  // 诊断：返回指定 cookie 值的脱敏特征（长度:前缀...后缀），用于对比会话差异，
  // 不泄露完整会话令牌。排查「同账号不同设备/客户端投票结果不同」时对比 auth/sid 特征。
  getCookieDigest(name: string): string {
    const v = this.cookieStore[name];
    if (v === undefined || v.length === 0) return '(none)';
    if (v.length <= 10) return v.length + ':' + v;
    return v.length + ':' + v.substring(0, 6) + '...' + v.substring(v.length - 4);
  }

  private saveResponseCookies(setCookieHeader: string): void {
    if (this.cookieWriteBlocked) return; // 退登期间丢弃旧回包的 cookie 写入
    const cookies = setCookieHeader.split(/,(?=\s*[^,;=]+=)/);
    // ArkTS 不支持 delete 操作符，先收集待删除的 cookie 名，循环后统一重建对象
    const toDelete: string[] = [];
    for (const cookie of cookies) {
      const parts = cookie.split(';');
      const first = parts[0].trim();
      const eq = first.indexOf('=');
      if (eq <= 0) continue;
      const name = first.substring(0, eq).trim();
      const value = first.substring(eq + 1).trim();
      if (name.length === 0) continue;
      // ⚠️ 删除/过期标记检测（Discuz dsetcookie 删除格式）：
      //   name=deleted; expires=Thu, 01-Jan-1970 00:00:01 GMT; path=/
      // 实测（2026-08-13）登录响应里 Discuz 以该格式清除 loginuser/activationauth/pmnum，
      // 旧实现只看 value.length>0 把「deleted」当正常值存进 cookieStore，
      // 之后每次请求携带 Q8qA_2132_activationauth=deleted 这类异常值 →
      // 服务端会话判定异常 → 投票报「西电托儿所无法进行此操作」（而 Python cookiejar
      // 正确忽略 deleted → 会话干净 → 投票成功）。必须识别并删除。
      // 以 deleted 开头即可判定（兼容分割误差把 expires 并入值的情况）
      let isDeleted = value.indexOf('deleted') === 0 || value.length === 0;
      for (let i = 1; i < parts.length && !isDeleted; i++) {
        const attr = parts[i].trim().toLowerCase();
        if (attr.indexOf('max-age') === 0) {
          const mv = parseInt(attr.substring(attr.indexOf('=') + 1).trim() || '0', 10);
          if (isNaN(mv) || mv <= 0) isDeleted = true;
        } else if (attr.indexOf('expires') === 0 && (attr.indexOf('1970') >= 0 || attr.indexOf('1971') >= 0)) {
          // Discuz 删除 cookie 的 Expires 固定为 1970 年
          isDeleted = true;
        }
      }
      if (isDeleted) {
        if (toDelete.indexOf(name) < 0) toDelete.push(name);
        continue;
      }
      if (isSessionCookie(name)) {
        this.cookieStore[name] = value;
      }
    }
    // 统一移除被标记删除的 cookie（ArkTS 无 delete，重建对象）
    if (toDelete.length > 0) {
      const kept: Record<string, string> = {};
      for (const k of Object.keys(this.cookieStore)) {
        if (toDelete.indexOf(k) < 0) kept[k] = this.cookieStore[k];
      }
      this.cookieStore = kept;
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

  // 投票专用 POST：严格对齐 Flutter ruisi_flutter 的 submitVote 请求——
  // 1) UA 用 myRuisiAsyncLiteHttp/1.0（Flutter dio 的默认 UA）；
  // 2) 不带 Referer/Origin（dio 默认不发，Flutter 端实测可投）；
  // 3) 跟随 302（对齐 Flutter postFollowRedirect）。
  // body 为已编码表单字符串（支持同名重复 key：pollanswers[]）。
  // ⚠️ 不注入 formhash：实测铁证（2026-08-13 鸿蒙端 Flutter 日志[54973]）成功请求 body
  // 只有 pollanswers[]；带 formhash（尤其与当前会话不匹配时）反被服务端安全拦截。
  async postVote(url: string, bodyStr: string): Promise<RuisiResponse> {
    await this.loadCookies();
    const body = bodyStr;
    const allHeaders: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'myRuisiAsyncLiteHttp/1.0',
    };
    let resp = await this.request(url, 'POST', body, allHeaders);
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
        'User-Agent': RUISI_DESKTOP_UA,
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
        'User-Agent': RUISI_DESKTOP_UA,
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
    return this.password;
  }

  // 密码持久化到系统 Asset Store（设备级加密，非明文落盘），作为 cookie 过期后的自动重登兜底。
  // 重启 App 后内存密码为空，由 loadCredentials() 在 checkAndAutoLogin/relogin 读取前从 Asset 读回内存。
  async setPassword(pwd: string): Promise<void> {
    this.password = pwd;
    await this.savePasswordToAsset(pwd);
  }

  // 从加密 Asset 存储读取密码到内存（幂等）。
  // 冷启动后内存密码为空（密码只存于加密 Asset，非明文落盘），
  // 必须在 checkAndAutoLogin/relogin 读取 getPassword() 前调用，
  // 否则 cookie 过期时仍会走到「必须手输密码」分支。对齐 Flutter 启动时主动恢复凭证。
  async loadCredentials(): Promise<void> {
    if (this.credentialsLoaded) return;
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, RUISI_PASSWORD_ASSET_ALIAS);
      const res = await asset.query(query);
      if (res.length > 0) {
        const secret = res[0].get(asset.Tag.SECRET) as Uint8Array;
        this.password = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(secret));
      }
    } catch (e) {
      // 无记录或查询失败：保持 this.password 为空（用户需手动输入）
      hilog.debug(DOMAIN, TAG, 'loadCredentials no record or failed: ' + String(e));
    }
    this.credentialsLoaded = true;
  }

  // 将密码写入加密 Asset 存储（设备级加密，等同 Flutter 的 secure storage，非明文落盘）。
  // 已存在则更新，避免重复记录。
  async savePasswordToAsset(pwd: string): Promise<void> {
    const secret: Uint8Array = new util.TextEncoder().encodeInto(pwd);
    const attr: asset.AssetMap = new Map();
    attr.set(asset.Tag.ALIAS, RUISI_PASSWORD_ASSET_ALIAS);
    attr.set(asset.Tag.SECRET, secret);
    try {
      await asset.add(attr);
    } catch (_) {
      // 已存在（或首次失败的其他原因）→ 尝试按 alias 更新
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, RUISI_PASSWORD_ASSET_ALIAS);
      const attrsToUpdate: asset.AssetMap = new Map();
      attrsToUpdate.set(asset.Tag.SECRET, secret);
      try {
        await asset.update(query, attrsToUpdate);
      } catch (e2) {
        hilog.error(DOMAIN, TAG, 'savePasswordToAsset update failed: ' + String(e2));
      }
    }
  }
}


