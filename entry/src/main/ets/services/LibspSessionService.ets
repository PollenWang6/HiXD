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

// 一次 libsp 会话：JWT 本体 + 动态认证头名 + 图书馆分组码
export interface LibspSession {
  jwt: string;
  jwtHeader: string;   // 动态认证头名（如 jwtOpacAuth / jwt / Authorization）
  groupCode: string;   // 图书馆分组码（西电 200755）
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

  // ============ 会话缓存（Preference 持久化） ============

  // 读取持久化的会话；任一关键字段缺失则返回 null
  static getSession(): LibspSession | null {
    const jwt: string = PreferenceUtil.getString(LibspSessionService.KEY_JWT, '');
    const jwtHeader: string = PreferenceUtil.getString(LibspSessionService.KEY_HEADER, '');
    if (jwt.length === 0 || jwtHeader.length === 0) {
      return null;
    }
    const groupCode: string = PreferenceUtil.getString(LibspSessionService.KEY_GROUP, LibspSessionService.GROUP_CODE);
    return { jwt: jwt, jwtHeader: jwtHeader, groupCode: groupCode };
  }

  static hasSession(): boolean {
    return LibspSessionService.getSession() !== null;
  }

  // 持久化会话（通常在 WebView 注入脚本回传 LIBSESSION 时调用）
  static async saveSession(s: LibspSession): Promise<void> {
    await PreferenceUtil.putString(LibspSessionService.KEY_JWT, s.jwt);
    await PreferenceUtil.putString(LibspSessionService.KEY_HEADER, s.jwtHeader);
    await PreferenceUtil.putString(LibspSessionService.KEY_GROUP, s.groupCode || LibspSessionService.GROUP_CODE);
  }

  // 清除会话（鉴权失败 / JWT 失效时）
  static async clearSession(): Promise<void> {
    await PreferenceUtil.putString(LibspSessionService.KEY_JWT, '');
    await PreferenceUtil.putString(LibspSessionService.KEY_HEADER, '');
    await PreferenceUtil.putString(LibspSessionService.KEY_GROUP, '');
  }

  // ============ 请求助手（直连 HTTP，带 JWT 双保险） ============

  // 带 libsp 会话直连接口：注入 jwt cookie + 动态 jwt 头，复刻 SPA 请求范式。
  // 成功返回 HttpResponse（调用方自行解析 body）；失败抛异常。
  static async postJson(apiPath: string, body: object, session: LibspSession): Promise<HttpResponse> {
    const http: HttpUtil = HttpUtil.getInstance();
    // 双保险：动态认证头 + cookie 都带上（复刻 SPA 行为）
    await http.injectCookies(
      'jwt=' + session.jwt + '; jwtHeader=' + session.jwtHeader,
      'findxidian.libsp.cn'
    );
    const headers: Record<string, string> = {
      'Referer': LibspSessionService.BASE + '/',
      'mappingPath': '',
      'groupCode': session.groupCode || LibspSessionService.GROUP_CODE,
      'x-lang': 'CHI',
      'content-language': 'zh_CN'
    };
    // SPA 把 jwt 作为名为 jwtHeader 值的动态头发送
    headers[session.jwtHeader] = session.jwt;
    return await http.postRaw(
      LibspSessionService.BASE + apiPath,
      JSON.stringify(body),
      'application/json',
      headers
    );
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
      "console.log('LIBSESSION:'+JSON.stringify({jwt:jv,jwtHeader:jh,groupCode:gc}));" +
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
