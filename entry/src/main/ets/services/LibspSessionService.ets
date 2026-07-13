// LibspSessionService.ets — 西电图书馆新系统(libsp.cn)会话服务
//
// 背景：西电图书馆"借阅历史 / 扫码借书 / 扫码转借"均走 libsp.cn 新系统，
// 鉴权为一枚 JWT（动态头名，默认 jwtOpacAuth / jwt），登录后由前端写入
// sessionStorage('jwt') / ('jwtHeader') 与 window.groupCode。
//
// 本服务把"如何拿到这枚 JWT"与"如何带 JWT 调接口"从 LibraryPage 抽出来，
// 供「我的借阅」与未来的「扫码借书 / 转借」两个功能共用：
//   - 登录态持久化到 Preference，避免 LibraryPage 每次重登
//   - WebView 注入取数脚本与控制台消息解析集中于此，避免重复实现
//
// 登录范式（已由 LibraryPage 跑通）：CAS SSO 种子(syncCasCookieOnly) →
// WebView 加载 findxidian.libsp.cn 自动登录 → SPA 把 JWT 写入 sessionStorage
// → 注入脚本读出 JWT 并经 console.log('LIBSESSION:...') 回传。

import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 一次 libsp 会话：JWT 本体 + 动态认证头名 + 图书馆分组码
export interface LibspSession {
  jwt: string;
  jwtHeader: string;   // 动态认证头名（如 jwtOpacAuth / jwt / Authorization）
  groupCode: string;   // 图书馆分组码（西电 200755）
  userId: string;      // 读者ID（scanSubtenancy 需要）
  libCode: string;     // 馆代码（scanSubtenancy 需要）
  allCookies: string;  // findxidian.libsp.cn 全部 cookie 串（含 jwt/SESSION 等），供 postJson Cookie 头
}

// WebView 注入脚本回传的控制台消息分类
export interface LibspConsoleResult {
  kind: 'session' | 'result' | 'notready' | 'error' | 'unknown';
  marker?: string;    // 成功结果时的标记名（如 LIBHIST）
  payload?: string;   // 附带文本（JSON 字符串 / 错误信息）
}

export class LibspSessionService {
  // 西电 libsp 新系统基址
  static readonly BASE: string = 'https://findxidian.libsp.cn';
  // 西电图书馆分组码
  static readonly GROUP_CODE: string = '200755';

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

  static hasSession(): boolean {
    return LibspSessionService.getSession() !== null;
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

  // ============ 纯 HTTP 登录（CAS CASTGC → findxidian SSO → JWT） ============

  // 确保有效会话存在。先从 Preference 缓存取；未命中则走 CAS SSO 链获取全新 JWT。
  // 调用方无需关心 WebView — 全链路纯 HTTP。
  static async ensureSession(): Promise<LibspSession | null> {
    // 1. 先检查缓存
    const cached: LibspSession | null = LibspSessionService.getSession();
    if (cached) {
      return cached;
    }

    const http: HttpUtil = HttpUtil.getInstance();
    const SSO_PATH: string = '/find/sso/login/xidian/0';
    const OPC: string = encodeURIComponent('?opacRoute=/personalCenter');
    const serviceUrl: string = LibspSessionService.BASE + SSO_PATH + OPC;

    // 2. 直连 CAS：用已有 CASTGC 换 findxidian SSO ticket
    //    CAS 验证 CASTGC → 302 到 findxidian（带 ticket）→ findxidian 返回 Set-Cookie jwt
    //    HttpUtil.request() 自动跟随 302 并在 headersReceive 中存 Set-Cookie
    const casUrl: string = 'https://ids.xidian.edu.cn/authserver/login?service=' + encodeURIComponent(serviceUrl);

    try {
      // CAS → findxidian 全链：
      // 1. ids.xidian.edu.cn/authserver/login?service=findxidian/SSO-path
      // 2. CASTGC 有效 → CAS 302 到 service URL（带 ticket）
      // 3. findxidian → tyrzfw.chaoxing.com（OpenResty 路由，HTTP 302）
      // 4. tyrzfw 验 ticket → 302 回 findxidian → Set-Cookie: jwt/jwtHeader/SESSION
      // HttpUtil.get() 自动跟随 302，沿途 headersReceive 收集 Set-Cookie
      const resp: HttpResponse = await http.get(casUrl);

      // 诊断日志：最终落哪个 URL
      console.info('[HiXD-Libsp] ensureSession final status=' + resp.statusCode +
        ' url=' + (resp.headers['X-Final-Url'] || casUrl));

      // 3. 从 cookieStore 提取 JWT 和全部 cookie
      const cookies: string = http.getAllCookies('findxidian.libsp.cn');
      if (cookies.length === 0) {
        console.error('[HiXD-Libsp] ensureSession: no cookies on findxidian.libsp.cn after CAS chain');
        return null;
      }

      // 全 cookie 串需在内存中保留，供 postJson Cookie 头发送
      const COOKIES: string = cookies;

      // 解析 cookie 字符串
      const map: Record<string, string> = {};
      for (const kv of cookies.split('; ')) {
        const eq: number = kv.indexOf('=');
        if (eq > 0) {
          map[kv.substring(0, eq).trim()] = kv.substring(eq + 1).trim();
        }
      }

      const jwt: string = map['jwt'] || '';
      const jwtHeader: string = map['jwtHeader'] || '';
      const hasSession: boolean = (map['SESSION'] || '').length > 0;

      if (!jwt || !jwtHeader) {
        console.error('[HiXD-Libsp] ensureSession: jwt or jwtHeader missing from cookies. ' +
          'keys=' + Object.keys(map).join(','));
        return null;
      }

      // 部分cookie可能来自WebView / browser（已登录）或仅来自HTTP CAS链（仅jwt+header，无SESSION）。
      // 仅当已有SESSION时缓存；没有SESSION时直接返回null → LibraryPage走WebView部署以确保全cookie写入。
      if (!hasSession) {
        console.info('[HiXD-Libsp] ensureSession: no SESSION cookie from HTTP CAS chain; skipping cache, will use WebView');
        return null;
      }

      const session: LibspSession = {
        jwt: jwt,
        jwtHeader: jwtHeader,
        groupCode: LibspSessionService.GROUP_CODE,
        userId: '',
        libCode: '',
        allCookies: COOKIES
      };
      await LibspSessionService.saveSession(session);
      console.info('[HiXD-Libsp] ensureSession SUCCESS jwt.len=' + jwt.length + ' header=' + jwtHeader + ' hasSession=true');
      return session;
    } catch (e) {
      console.error('[HiXD-Libsp] ensureSession ERROR: ' + e);
      return null;
    }
  }

  // ============ 请求助手（直连 HTTP，带 JWT 双保险） ============

  // 带 libsp 会话直连接口：原生 http.createHttp()，绕过 HttpUtil cookie 存储。
  // 鉴权双通道：JWT 动态头 + 完整 Cookie（含 jwt/SESSION 等）。
  // 服务端同时校验 cookie，缺 SESSION 会返回 success:true 但 searchResult 空数组。
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
      if (session.allCookies && session.allCookies.length > 0) {
        headers['Cookie'] = session.allCookies;
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

  // ============ WebView 注入脚本 ============

  // 生成 WebView 内注入的取数脚本：
  //   1. 从 sessionStorage/cookie 读取 JWT + 动态头名 + groupCode
  //   2. 经 console.log('LIBSESSION:<json>') 回传会话（供持久化）
  //   3. 同源 fetch(targetApi)，成功 JSON 经 console.log('<marker>:<json>') 回传
  //      ，非 JSON / 未就绪经 console.log('LIBNOTREADY')，异常经 console.log('LIBERR:<msg>')
  //
  // 注意：body 以 JSON 字符串形式内联（单引号包裹），fetch 直接发送该字符串；
  //       api / marker 以 JSON 字符串字面量形式内联。
  static buildInjectJs(targetApi: string, bodyObj: object, successMarker: string): string {
    const apiLit: string = JSON.stringify(targetApi);                       // 形如 '"/find/..."'
    const bodyLit: string = "'" + JSON.stringify(bodyObj).replace(/'/g, "\\'") + "'";  // 形如 '{"page":1}'
    const markerLit: string = JSON.stringify(successMarker);                // 形如 '"LIBHIST"'
    return "(function(){" +
      "try{" +
      "function gci(k){try{var m=document.cookie.match(new RegExp('(?:^|; )'+k+'=([^;]*)'));return m?decodeURIComponent(m[1]):''}catch(e){return ''}}" +
      "var jv=sessionStorage.getItem('jwt')||gci('jwt')||'';" +
      "if(!jv){console.log('LIBNOTREADY');return;}" +
      "var jh=sessionStorage.getItem('jwtHeader')||gci('jwtHeader')||'';" +
      "var gc=(window.groupCode||'')+'';" +
      "var ji=sessionStorage.getItem('userInfo');" +
      "var uid='',lbc='';" +
      "try{if(ji){var ui=JSON.parse(ji);uid=ui.userId||ui.id||'';lbc=ui.libCode||'';}}" +
      "catch(e){}" +
      "console.log('LIBSESSION:'+JSON.stringify({jwt:jv,jwtHeader:jh,groupCode:gc,allCookies:document.cookie||'',userId:uid,libCode:lbc}));" +
      "var api=" + apiLit + ";" +
      "var body=" + bodyLit + ";" +
      "var h={'Content-Type':'application/json','mappingPath':'','groupCode':gc,'x-lang':'CHI','content-language':'zh_CN'};" +
      "if(jh&&jv)h[jh]=jv;" +
      "fetch(api,{method:'POST',headers:h,body:body,credentials:'include'})" +
      ".then(function(r){return r.text();}).then(function(t){" +
      "if(t&&t.trim().charAt(0)==='{'){console.log(" + markerLit + "+':'+t);}" +
      "else{console.log('LIBNOTREADY');}" +
      "})" +
      ".catch(function(e){console.log('LIBERR:'+e);});" +
      "}catch(e){console.log('LIBERR:'+e);}" +
      "})()";
  }

  // ============ 控制台消息解析 ============

  // 解析注入脚本经 console.log 回传的消息。
  static parseConsole(msg: string): LibspConsoleResult {
    if (msg.indexOf('LIBSESSION:') === 0) {
      return { kind: 'session', payload: msg.substring('LIBSESSION:'.length) };
    }
    if (msg.indexOf('LIBNOTREADY') === 0) {
      return { kind: 'notready' };
    }
    if (msg.indexOf('LIBERR:') === 0) {
      return { kind: 'error', payload: msg.substring('LIBERR:'.length) };
    }
    // 成功结果：'<MARKER>:<json>'（MARKER 以 LIB 开头，如 LIBHIST）
    const idx: number = msg.indexOf(':');
    if (idx > 0) {
      const marker: string = msg.substring(0, idx);
      if (marker.indexOf('LIB') === 0) {
        return { kind: 'result', marker: marker, payload: msg.substring(idx + 1) };
      }
    }
    return { kind: 'unknown' };
  }
}
