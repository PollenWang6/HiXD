// LibspSessionService.ets — 西电图书馆新系统(libsp.cn)会话服务（纯 HTTP）
//
// 背景：西电图书馆"借阅历史 / 扫码借书 / 扫码转借"均走 libsp.cn 新系统，
// 鉴权为一枚 JWT（动态头名，默认 jwtOpacAuth / jwt），登录后由服务端跳转下发。
//
// 会话建立（fetchJwtViaHttp，对齐 Flutter library_session.dart 的 initSession）：
//   1) 确保 CAS 登录态（CasLoginService.checkAndAutoLogin，复用 TGC/密码）
//   2) CAS login?service=<超星 init> 拿首个 302 Location（CAS 已登录签 ticket 跳转）
//   3) 逐跳跟随重定向链（≤12 跳）：每跳先尝试从 URL 提取 jwt；
//      遇到 200 HTML（超星 CAS 登录页）→ 正则提取 data/time/enc/displayName/userRole →
//      GET tyrzfw.chaoxing.com/auth/xidian/cas/login 验证 → GET libsp sso/login/xidian/1 拿 302 jwt
//   4) 解析 JWT payload（sub=userId、groupCode），收集 libsp 域 cookie，saveSession
//
// 请求（postJson）：直连 http.createHttp()，鉴权双通道（JWT 动态头 + Cookie）。

import { HttpResponse, HttpUtil } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { CasLoginService } from '../auth/CasLoginService';
import { fmtDateShort } from '../../utils/DateUtil';
import { resolveLocation } from '../../utils/UrlUtil';

// 一次 libsp 会话：JWT 本体 + 动态认证头名 + 图书馆分组码
export interface LibspSession {
  jwt: string;
  jwtHeader: string;   // 动态认证头名（如 jwtOpacAuth / jwt / Authorization）
  groupCode: string;   // 图书馆分组码（西电 200755）
  userId: string;      // 读者ID（scanSubtenancy 需要）
  libCode: string;     // 馆代码（scanSubtenancy 需要）
  allCookies: string;  // findxidian.libsp.cn 全部 cookie 串（含 jwt/SESSION 等），供 postJson Cookie 头
}

// 借阅列表请求体（显式接口，规避 arkts-no-untyped-obj-literals）
interface LoanListReq {
  page: number;
  rows: number;
  searchType: number;
  searchContent: string;
  sortType: number;
  startDate: Object | null;
  endDate: Object | null;
}

// JWT payload 解析结果（显式接口，规避 arkts-no-obj-literals-as-types）
interface JwtPayloadInfo {
  userId: string;
  groupCode: string;
}

// 超星 CAS init（对齐 Flutter _opacLoginTarget）
const CHAOXING_INIT: string =
  'https://tyrzfw.chaoxing.com/auth/xidian/cas/init?isLogout=0&refer=' +
  encodeURIComponent('https://mfindxidian.libsp.cn/find/sso/login/xidian/1');
// CAS 登录入口（service=超星 init，对齐 Flutter checkAndLogin(target)）
const CAS_LOGIN_URL: string =
  'https://ids.xidian.edu.cn/authserver/login?service=' + encodeURIComponent(CHAOXING_INIT);

export class LibspSessionService {
  // 西电 libsp 新系统基址
  static readonly BASE: string = 'https://findxidian.libsp.cn';
  // 西电图书馆分组码
  static readonly GROUP_CODE: string = '200755';
  // 动态认证头名（对齐 Flutter _opacJwtHeader）
  static readonly JWT_HEADER: string = 'jwtOpacAuth';

  private static readonly KEY_JWT: string = 'libsp_jwt';
  private static readonly KEY_HEADER: string = 'libsp_jwt_header';
  private static readonly KEY_GROUP: string = 'libsp_group_code';
  private static readonly KEY_COOKIES: string = 'libsp_cookies';
  private static readonly KEY_USER_ID: string = 'libsp_user_id';
  private static readonly KEY_LIB_CODE: string = 'libsp_lib_code';

  // ============ 会话缓存（Preference 持久化） ============

  // 读取持久化的会话；任一关键字段缺失则返回 null
  static getSession(): LibspSession | null {
    const jwt: string = PreferenceUtil.getString(LibspSessionService.KEY_JWT, '');
    const jwtHeader: string = PreferenceUtil.getString(LibspSessionService.KEY_HEADER, '');
    if (jwt.length === 0 || jwtHeader.length === 0) {
      return null;
    }
    const groupCode: string = PreferenceUtil.getString(LibspSessionService.KEY_GROUP, LibspSessionService.GROUP_CODE);
    const allCookies: string = PreferenceUtil.getString(LibspSessionService.KEY_COOKIES, '');
    const userId: string = PreferenceUtil.getString(LibspSessionService.KEY_USER_ID, '');
    const libCode: string = PreferenceUtil.getString(LibspSessionService.KEY_LIB_CODE, '');
    return { jwt, jwtHeader, groupCode, allCookies, userId, libCode };
  }

  // 持久化会话
  static async saveSession(s: LibspSession): Promise<void> {
    await PreferenceUtil.putString(LibspSessionService.KEY_JWT, s.jwt);
    await PreferenceUtil.putString(LibspSessionService.KEY_HEADER, s.jwtHeader);
    await PreferenceUtil.putString(LibspSessionService.KEY_GROUP, s.groupCode || LibspSessionService.GROUP_CODE);
    if (s.userId && s.userId.length > 0) {
      await PreferenceUtil.putString(LibspSessionService.KEY_USER_ID, s.userId);
    }
    if (s.libCode && s.libCode.length > 0) {
      await PreferenceUtil.putString(LibspSessionService.KEY_LIB_CODE, s.libCode);
    }
    if (s.allCookies && s.allCookies.length > 0) {
      await PreferenceUtil.putString(LibspSessionService.KEY_COOKIES, s.allCookies);
    }
  }

  // 清除会话（鉴权失败 / JWT 失效时）
  static async clearSession(): Promise<void> {
    await PreferenceUtil.putString(LibspSessionService.KEY_JWT, '');
    await PreferenceUtil.putString(LibspSessionService.KEY_HEADER, '');
    await PreferenceUtil.putString(LibspSessionService.KEY_GROUP, '');
  }

  // ============ 纯 HTTP 会话建立（对齐 Flutter initSession / _resolveOpacLogin） ============

  // 纯 HTTP 走完整 CAS→超星→libsp 链拿到 JWT 会话。
  // 成功：saveSession 已执行并返回会话；失败：返回 null（调用方提示错误/降级）。
  static async fetchJwtViaHttp(): Promise<LibspSession | null> {
    const httpUtil: HttpUtil = HttpUtil.getInstance();
    try {
      // Step 1: 确保 CAS 登录态（TGC 恢复或已存凭据登录；不弹 UI）
      let loggedIn: boolean = false;
      try {
        loggedIn = await CasLoginService.getInstance().checkAndAutoLogin();
      } catch (_e) { loggedIn = false; }
      if (!loggedIn) {
        console.error('[Libsp] CAS not logged in');
        return null;
      }

      // Step 2: CAS login?service=CHAOXING_INIT → 首个 302 Location（CAS 已登录签 ticket 跳转）
      let resp: HttpResponse = await httpUtil.getNoRedirect(CAS_LOGIN_URL);
      if (!resp.isRedirect || !resp.location) {
        console.error('[Libsp] CAS login not redirect status=' + resp.statusCode);
        return null;
      }
      let location: string = resolveLocation(CAS_LOGIN_URL, resp.location);

      // Step 3: 逐跳跟随（对齐 Flutter _resolveOpacLogin 循环，≤12 跳）
      for (let hop: number = 0; hop < 12; hop++) {
        // 微信授权跳转 → 失败（对齐 Flutter _throwIfWechatLocation）
        if (LibspSessionService.isWechatLocation(location)) {
          console.error('[Libsp] wechat location: ' + location);
          return null;
        }
        // 从 URL 提取 jwt（query 或 fragment；对齐 Flutter _tryLoadJwtFromLocation）
        const jwt: string = LibspSessionService.extractJwt(location);
        if (jwt.length > 0) {
          const s: LibspSession = LibspSessionService.makeSessionFromJwt(jwt, httpUtil);
          await LibspSessionService.saveSession(s);
          await LibspSessionService.warmUpSession(s, httpUtil);
          return s;
        }
        // GET 当前 location（rcp autoRedirect:false，拿到第一跳响应）
        resp = await httpUtil.getNoRedirect(location);
        const nextLoc: string | undefined = resp.location;
        if (resp.isRedirect && nextLoc !== undefined) {
          location = resolveLocation(location, nextLoc);
          continue;
        }
        // 200 HTML：超星 CAS 登录页 → 提取参数 → 验证 → sso 302 拿 jwt
        const sso: string | null = await LibspSessionService.tryChaoxingCasLogin(resp.body, httpUtil);
        if (sso === null) {
          console.error('[Libsp] no jwt and no chaoxing login (status=' + resp.statusCode + ')');
          return null;
        }
        location = sso;
      }
      console.error('[Libsp] redirect hops exceeded');
      return null;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : JSON.stringify(e);
      console.error('[Libsp] fetchJwtViaHttp failed: ' + msg);
      return null;
    }
  }

  // 超星 CAS 登录页 HTML → 提取 data/time/enc/displayName/userRole → cas/login 验证 → sso 302 拿 jwt。
  // 对齐 Flutter _tryChaoxingCasLogin；返回下一跳 location（带 jwt），无法识别返回 null。
  private static async tryChaoxingCasLogin(html: string, httpUtil: HttpUtil): Promise<string | null> {
    if (!html || html.length === 0) {
      return null;
    }
    const dataM: RegExpMatchArray | null = html.match(/data: "(.*?)",/);
    const timeM: RegExpMatchArray | null = html.match(/time: ([0-9]*),/);
    const encM: RegExpMatchArray | null = html.match(/enc: "(.*?)",/);
    const nameM: RegExpMatchArray | null = html.match(/displayName: "(.*?)",/);
    const roleM: RegExpMatchArray | null = html.match(/userRole: ([0-9]{1}),/);
    if (!dataM || !timeM || !encM || !nameM || !roleM) {
      return null;
    }
    const data: string = dataM[1];
    const time: string = timeM[1];
    const enc: string = encM[1];
    const displayName: string = nameM[1];
    const userRole: string = roleM[1];

    // cas/login 验证（对齐 Flutter：不传 group1/mobilePhone）
    const casLoginUrl: string = 'https://tyrzfw.chaoxing.com/auth/xidian/cas/login?data='
      + encodeURIComponent(data) + '&time=' + encodeURIComponent(time)
      + '&enc=' + encodeURIComponent(enc) + '&displayName=' + encodeURIComponent(displayName)
      + '&userRole=' + encodeURIComponent(userRole);
    const casResp: HttpResponse = await httpUtil.get(casLoginUrl);
    if (!casResp.isOk) {
      console.error('[Libsp] chaoxing cas login http ' + casResp.statusCode);
      return null;
    }
    let statusOk: boolean = false;
    try {
      const j: Record<string, Object> = JSON.parse(casResp.body) as Record<string, Object>;
      statusOk = j['status'] === true;
    } catch (_e) { /* 非 JSON 视为失败 */ }
    if (!statusOk) {
      console.error('[Libsp] chaoxing cas login failed: ' + casResp.body.substring(0, 200));
      return null;
    }

    // sso：302 Location 带 jwt（rcp autoRedirect:false 拿第一跳）
    const ssoUrl: string = 'https://mfindxidian.libsp.cn/find/sso/login/xidian/1?data='
      + encodeURIComponent(data) + '&time=' + encodeURIComponent(time)
      + '&enc=' + encodeURIComponent(enc);
    const ssoResp: HttpResponse = await httpUtil.getNoRedirect(ssoUrl);
    if (ssoResp.isRedirect && ssoResp.location) {
      return resolveLocation(ssoUrl, ssoResp.location);
    }
    console.error('[Libsp] sso not redirect status=' + ssoResp.statusCode);
    return null;
  }

  // 从 URL 提取 jwt（query 的 jwt= 或 fragment 内 ?jwt=；对齐 Flutter _tryLoadJwtFromLocation）
  static extractJwt(location: string): string {
    if (!location || location.length === 0) {
      return '';
    }
    const m: RegExpMatchArray | null = location.match(/[?&#]jwt=([^&#]+)/);
    if (!m) {
      return '';
    }
    try {
      return decodeURIComponent(m[1]);
    } catch (_e) {
      return m[1];
    }
  }

  // 从 jwt 构建会话：解析 payload（userId/groupCode）+ 收集 libsp 域 cookie
  static makeSessionFromJwt(jwt: string, httpUtil: HttpUtil): LibspSession {
    const info: JwtPayloadInfo = LibspSessionService.parseJwtPayload(jwt);
    // libsp 域 cookie（rcp 底层按域存；sso 302 的 Set-Cookie 已含 SESSION 等）
    let cookies: string = httpUtil.getCookiesForDomain('mfindxidian.libsp.cn');
    const jwtCookie: string = 'jwt=' + jwt + '; jwtHeader=' + LibspSessionService.JWT_HEADER;
    if (cookies.length === 0) {
      cookies = jwtCookie;
    } else if (cookies.indexOf('jwt=') < 0) {
      cookies = cookies + '; ' + jwtCookie;
    }
    const s: LibspSession = {
      jwt: jwt,
      jwtHeader: LibspSessionService.JWT_HEADER,
      groupCode: info.groupCode,
      userId: info.userId,
      libCode: '',
      allCookies: cookies
    };
    return s;
  }

  // JWT payload 解析（对齐 Flutter _loadJwtInfo）：sub=userId，groupCode
  static parseJwtPayload(jwt: string): JwtPayloadInfo {
    const parts: string[] = jwt.split('.');
    if (parts.length < 2) {
      const empty: JwtPayloadInfo = { userId: '', groupCode: LibspSessionService.GROUP_CODE };
      return empty;
    }
    try {
      const b64u: string = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const pad: number = (4 - b64u.length % 4) % 4;
      const b64: string = b64u + '===='.substring(0, pad);
      const helper: util.Base64Helper = new util.Base64Helper();
      const u8: Uint8Array = helper.decodeSync(b64);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const jsonStr: string = decoder.decodeToString(u8);
      const payload: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>;
      const userId: string = String(payload['sub'] || '');
      const groupCode: string = String(payload['groupCode'] || '') || LibspSessionService.GROUP_CODE;
      const info: JwtPayloadInfo = { userId: userId, groupCode: groupCode };
      return info;
    } catch (_e) {
      const empty: JwtPayloadInfo = { userId: '', groupCode: LibspSessionService.GROUP_CODE };
      return empty;
    }
  }

  // 对齐 Flutter _warmUpOpacSession：GET /oga/userinfo 预热（失败忽略，不阻塞会话建立）
  private static async warmUpSession(s: LibspSession, httpUtil: HttpUtil): Promise<void> {
    try {
      const headers: Record<string, string> = {
        'Referer': LibspSessionService.BASE + '/',
        'mappingPath': '',
        'groupCode': s.groupCode || LibspSessionService.GROUP_CODE
      };
      headers[s.jwtHeader] = s.jwt;
      const resp: HttpResponse = await httpUtil.get(
        LibspSessionService.BASE + '/oga/userinfo?jwtHeader=' + s.jwtHeader + '&jwt=' + s.jwt,
        headers
      );
      if (!resp.isOk) {
        console.error('[Libsp] warmup http ' + resp.statusCode);
      }
    } catch (e) {
      console.error('[Libsp] warmup error: ' + (e instanceof Error ? e.message : JSON.stringify(e)));
    }
  }

  // 微信授权跳转检查（对齐 Flutter _throwIfWechatLocation）
  static isWechatLocation(location: string): boolean {
    const lower: string = location.toLowerCase();
    return lower.indexOf('open.weixin.qq.com') >= 0
      || lower.indexOf('wx.chaoxing.com') >= 0
      || lower.indexOf('/weixin/') >= 0;
  }

  // ============ 请求助手（直连 HTTP，带 JWT + 完整 Cookie 双鉴权） ============

  // 带 libsp 会话直连接口：原生 http.createHttp()，绕过 HttpUtil cookie 存储。
  // 鉴权双通道：JWT 动态头 + 完整 Cookie（含 jwt/SESSION 等）。
  // 服务端同时校验 cookie，缺 SESSION 会返回 success:true 但 searchResult 空数组。
  // cookie 实时合并：HttpUtil（rcp 底层）按域捕获的新 cookie（如 SESSION 续期）优先，
  // 避免持久化快照 allCookies 发散（会话过期/被覆盖仍发旧 cookie）。
  static async postJson(apiPath: string, body: object, session: LibspSession): Promise<HttpResponse> {
    return new Promise<HttpResponse>((resolve, reject) => {
      const req = http.createHttp();
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Referer': LibspSessionService.BASE + '/',
        'mappingPath': '',
        'groupCode': session.groupCode || LibspSessionService.GROUP_CODE,
        'x-lang': 'CHI',
        'content-language': 'zh_CN'
      };
      // 完整 cookie（含 jwt/SESSION 等）—— 不缺 SESSION，否则服务端返回空数据
      let cookies: string = session.allCookies || '';
      try {
        const live: string = HttpUtil.getInstance().getCookiesForDomain('mfindxidian.libsp.cn');
        if (live.length > 0) {
          // 实时 cookie 逐项覆盖/追加到快照（同名以 live 为准）
          const livePairs: string[] = live.split('; ');
          for (let li = 0; li < livePairs.length; li++) {
            const p: string = livePairs[li];
            const eq: number = p.indexOf('=');
            if (eq <= 0) { continue; }
            const name: string = p.substring(0, eq).trim();
            const parts: string[] = cookies.split('; ').filter((kv: string): boolean => kv.indexOf(name + '=') !== 0);
            parts.push(p);
            cookies = parts.join('; ');
          }
        }
      } catch (_e) { /* 合并失败用快照 */ }
      if (cookies.length > 0) {
        headers['Cookie'] = cookies;
      } else {
        headers['Cookie'] = 'jwt=' + session.jwt;
      }
      // JWT 动态头
      headers[session.jwtHeader] = session.jwt;
      req.request(
        LibspSessionService.BASE + apiPath,
        {
          method: http.RequestMethod.POST,
          header: headers,
          extraData: JSON.stringify(body) as string,
          expectDataType: http.HttpDataType.STRING,
          readTimeout: 120000,
          connectTimeout: 30000,
        },
        (err: BusinessError | undefined, data: http.HttpResponse) => {
          if (err !== undefined && err.code !== 0) {
            req.destroy();
            reject(new Error('HTTP ' + err.code + ': ' + err.message));
            return;
          }
          const resp = new HttpResponse();
          resp.statusCode = data.responseCode;
          const raw = data.result;
          resp.body = typeof raw === 'string' ? raw : '';
          req.destroy();
          resolve(resp);
        }
      );
    });
  }

  // ============ 主页卡片：当前借阅概况（在借数 / 逾期数） ============
  // JWT 会话有效时直连 /find/loanInfo/loanList 拉最新；无会话/失败返回 null（调用方降级显示缓存）。
  static async fetchBorrowSummary(): Promise<LibspBorrowSummary | null> {
    const session: LibspSession | null = LibspSessionService.getSession();
    if (!session) { return null; }
    const body: LoanListReq = {
      page: 1, rows: 999, searchType: 1, searchContent: '', sortType: 0,
      startDate: null, endDate: null
    };
    let resp: HttpResponse;
    try {
      resp = await LibspSessionService.postJson('/find/loanInfo/loanList', body, session);
    } catch (e) {
      return null;
    }
    if (resp.statusCode !== 200) {
      await LibspSessionService.clearSession();
      return null;
    }
    let raw: Record<string, Object>;
    try {
      raw = JSON.parse(resp.body) as Record<string, Object>;
    } catch (e) {
      return null;
    }
    if (raw['success'] !== true) {
      await LibspSessionService.clearSession();
      return null;
    }
    const dataObj: Record<string, Object> = (raw['data'] as Record<string, Object>) || {};
    const rawList: Record<string, string>[] = (dataObj['searchResult'] as Record<string, string>[]) || [];
    const borrow: number = rawList.length;
    let overdue: number = 0;
    const todayStr: string = LibspSessionService.todayKey();
    for (const r of rawList) {
      const nr: string = fmtDateShort(String(r['normReturnDate'] || ''));
      if (nr.length >= 10 && nr < todayStr) { overdue++; }
    }
    return { borrow, overdue };
  }

  private static todayKey(): string {
    const d: Date = new Date();
    const m: string = (d.getMonth() + 1).toString().padStart(2, '0');
    const day: string = d.getDate().toString().padStart(2, '0');
    return d.getFullYear() + '-' + m + '-' + day;
  }
}

// 主页卡片借阅概况
export interface LibspBorrowSummary {
  borrow: number;   // 在借数
  overdue: number;  // 逾期数（应还日期已过的）
}
