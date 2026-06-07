// EhallService.ets — 西电 Ehall 数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';
import { ClassService } from './ClassService';
import { ExamService } from './ExamService';

// 导入共享模型（供 EhallService 内部使用）
import { ClassItemModel, ExamItemModel, ScoreItemModel,
         ComposeDetail, ClassTableRow, ExamRow, ScoreRow,
         EHALL_APP_CLASS_TABLE, EHALL_APP_EXAM, EHALL_APP_SCORE,
         ExperimentType, ExperimentData, TimeRange, SYSJ_SECTION_TIMES } from './Models';

// 重导出共享模型，保持向后兼容（各页面仍可从 EhallService 导入）
export { ClassItemModel, ExamItemModel, ScoreItemModel,
         ComposeDetail, ClassTableRow, ExamRow, ScoreRow,
         EHALL_APP_CLASS_TABLE, EHALL_APP_EXAM, EHALL_APP_SCORE,
         ExperimentType, ExperimentData, TimeRange, SYSJ_SECTION_TIMES };

const TAG = 'EhallService';

interface ZcXqjData { ZC: object; XQJ: object; }

// ehall 请求头
const EHALL_HEADERS: Record<string, string> = {
  'Referer': 'http://ehall.xidian.edu.cn/new/index_xd.html',
  'Host': 'ehall.xidian.edu.cn',
  'Accept': 'application/json, text/javascript, */*; q=0.01',
  'Accept-Language': 'zh-CN,zh;q=0.9',
  'Accept-Encoding': 'gzip, deflate, br',
  'Connection': 'keep-alive',
  'X-Requested-With': 'XMLHttpRequest',
};

const APP_PATH_MAP: Map<string, string> = new Map([
  ['4770397878132218', '/jwapp/sys/wdkb'],
  ['4768687067472349', '/jwapp/sys/studentWdksapApp'],
  ['4768574631264620', '/jwapp/sys/cjcx'],
  ['4768402106681759', '/jwapp/sys/kxjas'],
]);

export class SemesterUtil {
  static getSemesterStartDate(semCodeOrYear: string, termPart?: string): Date {
    let y: number, t: number;
    if (termPart === undefined) {
      const p = semCodeOrYear.split('-');
      t = parseInt(p[2]);
      // 秋季(1)用第一个年，春季(2)用第二个年
      y = t === 1 ? parseInt(p[0]) : parseInt(p[1]);
    } else {
      const p = semCodeOrYear.split('-');
      y = parseInt(termPart === '1' ? p[0] : p[1]);
      t = parseInt(termPart);
    }
    // 秋季 9月1日，春季 3月2日，调整到最近的周一
    const start = t === 1 ? new Date(y, 8, 1) : new Date(y, 2, 2);
    const dow = start.getDay();
    const add = dow === 0 ? -6 : dow === 1 ? 0 : 1 - dow;
    start.setDate(start.getDate() + add);
    return start;
  }

  static calcCurrentWeekFromNow(): number {
    const now = new Date();
    const start = SemesterUtil.getSemesterStartDate(SemesterUtil.getCurrentSemesterCode());
    const swift = PreferenceUtil.getNumber('week_swift', 0);
    const dayMs = 1000 * 60 * 60 * 24;
    const diff = Math.floor((now.getTime() - start.getTime() - swift * 7 * dayMs) / dayMs);
    return Math.max(1, Math.floor(diff / 7) + 1);
  }

  static getCurrentSemesterCode(): string {
    const saved = PreferenceUtil.getString('current_semester');
    if (saved.length > 0) return saved;
    const now = new Date();
    const y = now.getFullYear();
    const m = now.getMonth() + 1;
    if (m >= 9) return y + '-' + (y + 1) + '-1';
    if (m >= 2 && m <= 7) return (y - 1) + '-' + y + '-2';
    return (y - 1) + '-' + y + '-1';
  }

  static formatSemester(code: string): string {
    const parts: string[] = code.split('-');
    if (parts.length !== 3) return code;
    const term: string = parts[2];
    const termName: string = term === '1' ? '秋季学期' : term === '2' ? '春季学期' : '短学期';
    return parts[0] + '-' + parts[1] + ' ' + termName;
  }
}

export class EhallService {
  private static inst: EhallService;
  private http = HttpUtil.getInstance();
  private cache = CacheService.getInstance();
  private appSessionUrl: Record<string, string> = {};

  constructor() {}

  clearSessionCache(): void {
    this.appSessionUrl = {};
    console.info(TAG, 'Session cache cleared');
  }

  static getInstance(): EhallService {
    if (!EhallService.inst) EhallService.inst = new EhallService();
    return EhallService.inst;
  }

  private async init(): Promise<void> { await this.cache.init(); }

  async checkEhallLogin(): Promise<boolean> {
    try {
      const resp = await this.http.get(
        'https://ehall.xidian.edu.cn/jsonp/getAppUsageMonitor.json?type=uv',
        EHALL_HEADERS
      );
      if (resp.isOk) {
        const raw = resp.body;
        const m = raw.match(/"hasLogin"\s*:\s*(true|false)/);
        if (m) {
          const hasLogin = m[1] === 'true';
          console.info(TAG, 'checkEhallLogin: hasLogin=' + hasLogin);
          return hasLogin;
        }
      }
      return false;
    } catch (e) {
      console.warn(TAG, 'checkEhallLogin network error: ' + JSON.stringify(e));
      throw new Error('NETWORK_ERROR');
    }
  }

  async tryAutoRestoreLogin(): Promise<boolean> {
    try {
      const verified = await this.checkEhallLogin();
      if (verified) {
        console.info(TAG, 'tryAutoRestoreLogin: already logged in');
        return true;
      }
      console.info(TAG, 'tryAutoRestoreLogin: attempting CAS restore...');
      const cas = CasLoginService.getInstance();
      const restored = await cas.tryAutoRestoreLogin();
      if (restored) {
        console.info(TAG, 'tryAutoRestoreLogin: CAS redirect completed, re-verifying...');
        const reVerified = await this.checkEhallLogin();
        if (reVerified) {
          console.info(TAG, 'tryAutoRestoreLogin: CAS restore verified, session valid');
          await cas.syncCookiesToWebView();
          return true;
        }
        console.warn(TAG, 'tryAutoRestoreLogin: re-verification FAILED, CAS restore was false positive');
      }
      console.info(TAG, 'tryAutoRestoreLogin: all attempts failed');
      return false;
    } catch (e) {
      console.warn(TAG, 'tryAutoRestoreLogin failed: ' + JSON.stringify(e));
      return false;
    }
  }

  async fetchStudentId(): Promise<string> {
    const cached: string = await PreferenceUtil.getString('ids_account');
    if (cached && cached.length > 0) return cached;

    try {
      const resp1 = await this.http.get(
        'https://ehall.xidian.edu.cn/jsonp/userFavoriteApps.json',
        EHALL_HEADERS
      );
      if (resp1.isOk) {
        const jsonStr = resp1.body.replace(/^\s*\/\*\*\/\s*\w*\s*\(/, '').replace(/\)\s*;?\s*$/, '');
        const obj = JSON.parse(jsonStr) as Record<string, object>;
        const user = (obj['user'] || obj) as Record<string, string>;
        const sid = user['code'] || user['userId'] || user['userName'] || user['userCode'] || '';
        if (sid) {
          console.info(TAG, 'fetchStudentId: got from userFavoriteApps');
          await PreferenceUtil.putString('ids_account', sid);
          return sid;
        }
      }
    } catch (e) {
      console.warn(TAG, 'fetchStudentId: userFavoriteApps failed: ' + JSON.stringify(e));
    }

    try {
      const resp2 = await this.http.get(
        'https://ehall.xidian.edu.cn/jsonp/getuserinfo.json',
        EHALL_HEADERS
      );
      if (resp2.isOk) {
        const jsonStr = resp2.body.replace(/^\s*\/\*\*\/\s*\w*\s*\(/, '').replace(/\)\s*;?\s*$/, '');
        const obj = JSON.parse(jsonStr) as Record<string, object>;
        const user = (obj['user'] || obj) as Record<string, string>;
        const sid = user['code'] || user['userId'] || user['userName'] || user['userCode'] || '';
        if (sid) {
          console.info(TAG, 'fetchStudentId: got from getuserinfo');
          await PreferenceUtil.putString('ids_account', sid);
          return sid;
        }
      }
    } catch (e) {
      console.warn(TAG, 'fetchStudentId: getuserinfo failed: ' + JSON.stringify(e));
    }

    console.error(TAG, 'fetchStudentId: all methods failed');
    return '';
  }

  private async activateAppSession(appId: string, force: boolean = false): Promise<void> {
    if (!force && this.appSessionUrl[appId]) {
      console.info(TAG, 'activateAppSession: using cached for ' + appId);
      return;
    }

    const appPath = APP_PATH_MAP.get(appId) || '/jwapp/sys/wdkb';
    this.appSessionUrl[appId] = appPath;

    const cookiesBefore = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (!force && cookiesBefore.toLowerCase().includes('jsessionid')) {
      console.info(TAG, 'activateAppSession: already have JSESSIONID, skip for ' + appId);
      return;
    }

    console.info(TAG, 'activateAppSession: establishing session for ' + appId);

    try {
      const resp = await this.http.get(
        'https://ehall.xidian.edu.cn/appShow?appId=' + appId,
        EHALL_HEADERS
      );
      console.info(TAG, 'activateAppSession: /appShow resp=' + resp.statusCode);
    } catch (e) {
      console.warn(TAG, 'activateAppSession: /appShow failed (expected): ' + JSON.stringify(e));
    }

    const cookiesAfter1 = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (cookiesAfter1.toLowerCase().includes('jsessionid')) {
      console.info(TAG, 'activateAppSession: JSESSIONID obtained from /appShow');
      return;
    }

    try {
      const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
      console.info(TAG, 'activateAppSession: trying URL-encoded default page: ' + directUrl);
      const resp2 = await this.http.get(directUrl, EHALL_HEADERS);
      console.info(TAG, 'activateAppSession: direct page resp=' + resp2.statusCode);

      if (resp2.isRedirect && resp2.location) {
        let loc: string = resp2.location;
        if (loc.startsWith('/')) {
          loc = 'https://ehall.xidian.edu.cn' + loc;
        }
        console.info(TAG, 'activateAppSession: following redirect to ' + loc);
        try {
          await this.http.get(loc, EHALL_HEADERS);
        } catch (e3) {
          console.warn(TAG, 'activateAppSession: redirect follow failed: ' + JSON.stringify(e3));
        }
      }
    } catch (e2) {
      console.warn(TAG, 'activateAppSession: direct page failed: ' + JSON.stringify(e2));
    }

    const cookiesFinal = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    const hasModAuth = cookiesFinal.toLowerCase().includes('mod_auth_cas');
    const hasJsession = cookiesFinal.toLowerCase().includes('jsessionid');
    console.info(TAG, 'activateAppSession: final cookies hasMOD_AUTH=' + hasModAuth +
      ' hasJSESSIONID=' + hasJsession);
  }

  private async appPost(path: string, body: Record<string, string>): Promise<HttpResponse> {
    const url = 'https://ehall.xidian.edu.cn' + path;
    const cookies = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    const hasCas: boolean = cookies.indexOf('MOD_AUTH_CAS') >= 0;
    const hasJsession: boolean = cookies.toLowerCase().indexOf('jsessionid') >= 0;
    console.info(TAG, `appPost: url=${path} hasMOD_AUTH=${hasCas} hasJSESSIONID=${hasJsession} cookieLen=${cookies.length}`);
    let resp = await this.http.postForm(url, body, EHALL_HEADERS);
    console.info(TAG, 'appPost: resp status=' + resp.statusCode);

    if (resp.isRedirect && resp.location && resp.location.includes('login')) {
      console.warn(TAG, 'appPost: session expired, redirecting to login');
      this.appSessionUrl = {};
      const appId = this.findAppIdByPath(path);
      if (appId) {
        console.info(TAG, 'appPost: retrying with re-activation for ' + appId);
        await this.activateAppSession(appId, true);
        resp = await this.http.postForm(url, body, EHALL_HEADERS);
        console.info(TAG, 'appPost: retry resp=' + resp.statusCode);
      }
    }

    if (resp.body.trimStart().startsWith('<!') || resp.body.trimStart().startsWith('<html')) {
      console.warn(TAG, 'appPost: received HTML instead of JSON, body[0:200]=' + resp.body.substring(0, 200));
      this.appSessionUrl = {};
      const appId = this.findAppIdByPath(path);
      if (appId) {
        console.info(TAG, 'appPost: retrying with re-activation for ' + appId);
        await this.activateAppSession(appId, true);
        resp = await this.http.postForm(url, body, EHALL_HEADERS);
        console.info(TAG, 'appPost: retry resp=' + resp.statusCode);
      }
    }

    return resp;
  }

  private findAppIdByPath(path: string): string {
    if (path.includes('wdkb')) return '4770397878132218';
    if (path.includes('studentWdksapApp') || path.includes('wdksap')) return '4768687067472349';
    if (path.includes('cjcx')) return '4768574631264620';
    if (path.includes('kxjas')) return '4768402106681759';
    return '';
  }

  static extractRaw(body: string): object[] {
    try {
      console.info(TAG, 'extractRaw: parsing body length=' + body.length);
      const obj = JSON.parse(body) as Record<string, object>;

      const datas = obj['datas'];
      if (datas !== null && typeof datas === 'object') {
        const datasMap = datas as Record<string, object>;
        for (const key of Object.keys(datasMap)) {
          const sub = datasMap[key];
          if (sub !== null && typeof sub === 'object') {
            const subMap = sub as Record<string, object>;
            const rows = subMap['rows'];
            if (Array.isArray(rows)) {
              console.info(TAG, 'extractRaw: found rows via datas.' + key + '.rows, count=' + rows.length);
              return rows as object[];
            }
            const extParams = subMap['extParams'];
            if (extParams !== null && typeof extParams === 'object') {
              const extMap = extParams as Record<string, object>;
              const extRows = extMap['rows'];
              if (Array.isArray(extRows)) {
                console.info(TAG, 'extractRaw: found rows via datas.' + key + '.extParams.rows, count=' + extRows.length);
                return extRows as object[];
              }
            }
          }
        }
      }

      for (const second of Object.values(obj)) {
        if (second !== null && typeof second === 'object') {
          const smap: Record<string, object> = second as Record<string, object>;
          for (const third of Object.values(smap)) {
            if (third !== null && typeof third === 'object') {
              const tmap: Record<string, object> = third as Record<string, object>;
              const rows = tmap['rows'];
              if (Array.isArray(rows)) {
                console.info(TAG, 'extractRaw: found rows via recursive, count=' + rows.length);
                return rows as object[];
              }
            }
          }
        }
      }

      console.warn(TAG, 'extractRaw: no rows found in response');
      return [];
    } catch (e) {
      console.error(TAG, 'extractRaw parse error: ' + JSON.stringify(e) + ' body[0:200]=' + body.substring(0, 200));
      return [];
    }
  }

  // ===== sysj 实验系统 OAuth 登录 =====

  private async followRedirects(startUrl: string, maxSteps: number = 10): Promise<HttpResponse> {
    let currentUrl = startUrl;
    for (let i = 0; i < maxSteps; i++) {
      const resp = await this.http.getNoRedirect(currentUrl);
      if (!resp.isRedirect || !resp.location) {
        return resp;
      }
      let location = resp.location;
      if (location.startsWith('/')) {
        const idx = currentUrl.indexOf('/', 8);
        const base = idx > 0 ? currentUrl.substring(0, idx) : currentUrl;
        location = base + location;
      }
      currentUrl = location;
    }
    throw new Error('Too many redirects');
  }

  private getQueryParam(url: string, name: string): string {
    const mark = url.indexOf('?');
    if (mark < 0) return '';
    const query = url.substring(mark + 1);
    const pairs = query.split('&');
    for (const pair of pairs) {
      const eq = pair.indexOf('=');
      if (eq > 0 && pair.substring(0, eq) === name) {
        return decodeURIComponent(pair.substring(eq + 1));
      }
    }
    return '';
  }

  async getCasTgc(): Promise<string> {
    try {
      const serviceUrl = 'https://sysj.xidian.edu.cn/xidian/test';
      const casLoginUrl = 'https://cas.xidian.edu.cn/authserver/login?service=' +
        encodeURIComponent(serviceUrl);
      console.info(TAG, 'getCasTgc: GET ' + casLoginUrl.substring(0, 80));

      const loginPageResp = await this.http.get(casLoginUrl);
      const html = loginPageResp.body || '';
      console.info(TAG, 'getCasTgc: login page len=' + html.length);

      const ltMatch = html.match(/name="lt"\s+value="([^"]*)"/);
      const executionMatch = html.match(/name="execution"\s+value="([^"]*)"/);
      const eventIdMatch = html.match(/name="_eventId"\s+value="([^"]*)"/);
      const lt = ltMatch ? ltMatch[1] : '';
      const execution = executionMatch ? executionMatch[1] : '';
      const eventId = eventIdMatch ? eventIdMatch[1] : 'submit';
      console.info(TAG, 'getCasTgc: lt=' + (lt ? 'yes' : 'no') + ' execution=' + (execution ? 'yes' : 'no'));

      if (!lt || !execution) {
        throw new Error('getCasTgc: cannot parse CAS login form');
      }

      const username = PreferenceUtil.getString('login_username', '');
      const password = PreferenceUtil.getString('login_password', '');
      if (!username || !password) {
        throw new Error('getCasTgc: no stored credentials');
      }

      const postUrl = 'https://cas.xidian.edu.cn/authserver/login';
      const body = 'username=' + encodeURIComponent(username) +
        '&password=' + encodeURIComponent(password) +
        '<=' + encodeURIComponent(lt) +
        '&execution=' + encodeURIComponent(execution) +
        '&_eventId=' + encodeURIComponent(eventId) +
        '&submit=LOGIN';

      console.info(TAG, 'getCasTgc: POST credentials');
      const casResp = await this.http.postNoRedirect(postUrl, body, {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': casLoginUrl,
      });

      const casCookies = this.http.getCookiesForDomain('cas.xidian.edu.cn');
      console.info(TAG, 'getCasTgc: cas cookies received');

      const tgcMatch = casCookies.match(/TGC=([^;\s]+)/);
      if (tgcMatch) {
        console.info(TAG, 'getCasTgc: TGC captured, len=' + tgcMatch[1].length);
        return tgcMatch[1];
      }

      let currentUrl = '';
      if (casResp.isRedirect && casResp.location) {
        currentUrl = casResp.location;
        if (currentUrl.startsWith('/')) {
          currentUrl = 'https://cas.xidian.edu.cn' + currentUrl;
        }
      }

      let hops = 0;
      while (currentUrl && hops < 10) {
        const redirResp = await this.http.getNoRedirect(currentUrl);
        console.info(TAG, 'getCasTgc: hop[' + hops + '] status=' + redirResp.statusCode +
          ' url=' + currentUrl.substring(0, 80));

        const casCk = this.http.getCookiesForDomain('cas.xidian.edu.cn');
        const tgcM = casCk.match(/TGC=([^;\s]+)/);
        if (tgcM) {
          console.info(TAG, 'getCasTgc: TGC found at hop ' + hops + ', len=' + tgcM[1].length);
          return tgcM[1];
        }

        if (redirResp.isRedirect && redirResp.location) {
          currentUrl = redirResp.location;
          if (currentUrl.startsWith('/')) {
            const protoEnd = currentUrl.indexOf('://');
            const afterProto = protoEnd >= 0 ? currentUrl.substring(protoEnd + 3) : currentUrl;
            const slashIdx = afterProto.indexOf('/');
            const host = slashIdx > 0 ? afterProto.substring(0, slashIdx) : afterProto;
            currentUrl = (protoEnd >= 0 ? currentUrl.substring(0, protoEnd + 3) : 'https://') + host + currentUrl;
          }
        } else {
          break;
        }
        hops++;
      }

      throw new Error('getCasTgc: TGC not found after redirect chain');
    } catch (e) {
      console.info(TAG, 'getCasTgc failed: ' + JSON.stringify(e));
      return '';
    }
  }

  async loginToSysjWithTgc(tgc: string): Promise<boolean> {
    console.info(TAG, 'loginToSysjWithTgc: start');
    try {
      await this.http.injectCookies('TGC=' + tgc, 'cas.xidian.edu.cn');
      console.info(TAG, 'loginToSysjWithTgc: TGC injected to cas.xidian.edu.cn');

      const resp1 = await this.http.getNoRedirect('https://sysj.xidian.edu.cn/xidian/test');
      console.info(TAG, 'loginToSysjWithTgc: step1 status=' + resp1.statusCode + ' isRedirect=' + resp1.isRedirect);

      if (!resp1.isRedirect || !resp1.location) {
        if (resp1.statusCode === 200) {
          console.info(TAG, 'loginToSysjWithTgc: already logged in');
          return true;
        }
        throw new Error('sysj step1: no redirect, status=' + resp1.statusCode);
      }

      const state = this.getQueryParam(resp1.location, 'state');
      console.info(TAG, 'loginToSysjWithTgc: step1 redirect, state=' + (state || '(none)'));

      let currentUrl = resp1.location;
      if (currentUrl.startsWith('/')) {
        currentUrl = 'https://sysj.xidian.edu.cn' + currentUrl;
      }

      const respAfterCas = await this.followRedirects(currentUrl, 12);
      console.info(TAG, 'loginToSysjWithTgc: after CAS chain, status=' + respAfterCas.statusCode +
        ' isRedirect=' + respAfterCas.isRedirect + ' bodyLen=' + (respAfterCas.body || '').length);

      let code = '';
      const finalBody = respAfterCas.body || '';
      const codeMatch = finalBody.match(/\?code=([^&"\s]+)/);
      if (codeMatch) {
        code = codeMatch[1];
      }
      if (!code && respAfterCas.isRedirect && respAfterCas.location) {
        code = this.getQueryParam(respAfterCas.location, 'code');
      }
      if (!code) {
        const urlCodeMatch = currentUrl.match(/[?&]code=([^&\s"]+)/);
        if (urlCodeMatch) code = urlCodeMatch[1];
      }

      if (!code && state) {
        const authorizeUrl = 'https://sysj.xidian.edu.cn/uaa/oauth/authorize?redirect_uri=https://sysj.xidian.edu.cn/xidian/webapp/callback&state=' +
          state + '&client_id=GvsunLims&response_type=code';
        const respAuth = await this.http.get(authorizeUrl);
        const authBody = respAuth.body || '';
        const authCodeMatch = authBody.match(/\?code=([^&"\s]+)/);
        if (authCodeMatch) code = authCodeMatch[1];
        if (!code) {
          const callbackMatch = authBody.match(/callback\?code=([^&"\s']+)/);
          if (callbackMatch) code = callbackMatch[1];
        }
      }

      if (!code) {
        throw new Error('loginToSysjWithTgc: failed to extract code, finalUrl=' + currentUrl.substring(0, 200));
      }
      console.info(TAG, 'loginToSysjWithTgc: got code=' + code.substring(0, 10) + '...');

      const callbackUrl = 'https://sysj.xidian.edu.cn/xidian/webapp/callback?code=' + code +
        (state ? '&state=' + state : '');
      const resp4 = await this.http.get(callbackUrl);
      const callbackBody = resp4.body || '';
      console.info(TAG, 'loginToSysjWithTgc: callback status=' + resp4.statusCode + ' bodyLen=' + callbackBody.length);

      const pwdMatch = callbackBody.match(/var\s+password\s*=\s*'([^']*)'/);
      if (!pwdMatch) {
        console.warn(TAG, 'loginToSysjWithTgc: no password in callback');
        return true;
      }
      const password = pwdMatch[1];

      const sid = await PreferenceUtil.getString('ids_account');
      console.info(TAG, 'loginToSysjWithTgc: ids saved');
      if (!sid) {
        throw new Error('loginToSysjWithTgc: no ids_account, need to store it after CAS login');
      }
      const loginResp = await this.http.postRaw(
        'https://sysj.xidian.edu.cn/xidian/webapp/login',
        'username=' + encodeURIComponent(sid) + '&password=' + encodeURIComponent(password),
        'application/x-www-form-urlencoded',
        { 'Content-Type': 'application/x-www-form-urlencoded' }
      );
      console.info(TAG, 'loginToSysjWithTgc: login status=' + loginResp.statusCode);

      if (loginResp.statusCode === 200 && loginResp.body) {
        try {
          const loginResult = JSON.parse(loginResp.body) as Record<string, string | number | boolean | object>;
          if (loginResult['success'] === true || loginResult['code'] === 0) {
            console.info(TAG, 'loginToSysjWithTgc: SUCCESS');
            return true;
          }
          console.error(TAG, 'loginToSysjWithTgc: login failed, status=' + loginResp.statusCode);
          return false;
        } catch (_) {
          return true;
        }
      }
      return false;
    } catch (e) {
      console.error(TAG, 'loginToSysjWithTgc failed: ' + String(e));
      return false;
    }
  }

  // ===== sysj 实验数据获取 =====

  private parseSysjHtml(html: string, weekDates: string[]): ExperimentData[] {
    const experiments: ExperimentData[] = [];

    const cellRegex = /do-labReservation=['"](\d+),(\d+)['\"][^>]*>([\s\S]*?)<\/td>/g;
    let match: RegExpExecArray | null = null;

    const extractField = (cellHtml: string, marker: string): string => {
      const idx = cellHtml.indexOf(marker);
      if (idx < 0) return '';
      const after = cellHtml.substring(idx + marker.length);
      const endIdx = after.search(/<(?:br|\/div|span)/);
      const raw = endIdx > 0 ? after.substring(0, endIdx).trim() : after.trim();
      return raw.replace(/<[^>]+>/g, '').trim();
    };

    const courseMarker = html.indexOf('???student.timetable.course???') >= 0
      ? '???student.timetable.course???\uff1a'
      : '\u8BFE\u7A0B\uFF1A';
    const labMarker = html.indexOf('???schedule.course.lab???') >= 0
      ? '???schedule.course.lab???\uff1a'
      : '\u5B9E\u9A8C\u5BA4\uFF1A';
    const teacherMarker = html.indexOf('???student.timetable.teacher???') >= 0
      ? '???student.timetable.teacher???\uff1a'
      : '\u6559\u5E08\uFF1A';

    const expMap: Record<string, ExperimentData> = {};

    while ((match = cellRegex.exec(html)) !== null) {
      const weekDay = parseInt(match[1]);
      const classIndex = parseInt(match[2]);
      const cellHtml = match[3];

      const name = extractField(cellHtml, courseMarker);
      const classroom = extractField(cellHtml, labMarker);
      const teacher = extractField(cellHtml, teacherMarker);

      if (!name) continue;

      const dateStr = weekDates[weekDay - 1];
      if (!dateStr) continue;
      const startIdx = (classIndex - 1) * 2;
      const endIdx = startIdx + 1;
      const startTime = startIdx < SYSJ_SECTION_TIMES.length ? SYSJ_SECTION_TIMES[startIdx] : '08:30';
      const endTime = endIdx < SYSJ_SECTION_TIMES.length ? SYSJ_SECTION_TIMES[endIdx] : '09:15';

      const tr = new TimeRange();
      tr.startTime = dateStr + ' ' + startTime;
      tr.endTime = dateStr + ' ' + endTime;

      const key = name + '|' + classroom + '|' + teacher;
      if (expMap[key]) {
        expMap[key].timeRanges.push(tr);
      } else {
        const exp = new ExperimentData();
        exp.type = ExperimentType.OTHERS;
        exp.name = name;
        exp.classroom = classroom;
        exp.teacher = teacher;
        exp.timeRanges = [tr];
        expMap[key] = exp;
      }
    }

    const keys = Object.keys(expMap);
    for (const k of keys) {
      experiments.push(expMap[k]);
    }
    return experiments;
  }

  async checkSysjLogin(): Promise<boolean> {
    try {
      const resp = await this.http.postRaw(
        'https://sysj.xidian.edu.cn/xidian/StudentCurrWeekTimetable',
        'weeks=1',
        'application/x-www-form-urlencoded',
        { 'Content-Type': 'application/x-www-form-urlencoded' }
      );
      const body = resp.body || '';
      console.info(TAG, 'checkSysjLogin: bodyLen=' + body.length);
      if (body.indexOf('<table') >= 0) {
        return true;
      }
      return false;
    } catch (e) {
      console.error(TAG, 'checkSysjLogin failed: ' + String(e));
      return false;
    }
  }

  public parseWeekHtml(html: string): ExperimentData[] {
    if (!html || html.length < 100) return [];

    const tableMatch = html.match(/<table[\s\S]*?<\/table>/g);
    if (!tableMatch || tableMatch.length < 2) return [];

    const secondTable = tableMatch[1];

    const weekDates: string[] = [];
    const thRegex = /<th[^>]*>([\s\S]*?)<\/th>/g;
    let thMatch: RegExpExecArray | null = null;
    while ((thMatch = thRegex.exec(secondTable)) !== null) {
      const thContent = thMatch[1];
      const brIdx = thContent.indexOf('<br');
      if (brIdx > 0) {
        const datePart = thContent.substring(brIdx).replace(/<[^>]+>/g, '').trim();
        if (datePart.length >= 8) {
          weekDates.push(datePart);
        }
      }
    }

    if (weekDates.length === 0) return [];

    return this.parseSysjHtml(secondTable, weekDates);
  }

  async fetchSysjScheduleWithTgc(tgc: string, onProgress?: (week: number, total: number) => void): Promise<ExperimentData[]> {
    console.info(TAG, 'fetchSysjScheduleWithTgc: start');
    const TOTAL_WEEKS = 25;

    const loggedIn = await this.loginToSysjWithTgc(tgc);
    if (!loggedIn) {
      throw new Error('sysj login failed with TGC');
    }
    console.info(TAG, 'fetchSysjScheduleWithTgc: login success, fetching schedule...');

    const expMap: Record<string, ExperimentData> = {};
    const sid = await PreferenceUtil.getString('ids_account');

    for (let week = 1; week <= TOTAL_WEEKS; week++) {
      if (onProgress) {
        onProgress(week, TOTAL_WEEKS);
      }
      try {
        const resp = await this.http.postRaw(
          'https://sysj.xidian.edu.cn/xidian/schedule/myScheduleInfo',
          'termId=2003&week=' + week + '&type=0',
          'application/x-www-form-urlencoded',
          { 'Content-Type': 'application/x-www-form-urlencoded' }
        );
        const html = resp.body || '';

        if (week <= 2) {
          console.info(TAG, 'fetchSysjScheduleWithTgc: week=' + week + ' status=' + resp.statusCode + ' bodyLen=' + html.length);
        }

        if (!html || html.length < 100) continue;

        const weekExps = this.parseScheduleListHtml(html, week);
        if (weekExps.length > 0) {
          console.info(TAG, 'fetchSysjScheduleWithTgc: week=' + week + ' found=' + weekExps.length);
        }

        for (const exp of weekExps) {
          const key = exp.name + '|' + exp.classroom + '|' + exp.teacher;
          if (expMap[key]) {
            for (const tr of exp.timeRanges) {
              if (!expMap[key].timeRanges.some(t => t.startTime === tr.startTime)) {
                expMap[key].timeRanges.push(tr);
              }
            }
          } else {
            expMap[key] = exp;
          }
        }
      } catch (e) {
        console.warn(TAG, 'fetchSysjScheduleWithTgc: week=' + week + ' error: ' + String(e));
      }
    }

    const result: ExperimentData[] = [];
    const keys = Object.keys(expMap);
    for (const k of keys) {
      result.push(expMap[k]);
    }
    console.info(TAG, 'fetchSysjScheduleWithTgc: done, total=' + result.length);
    return result;
  }

  parseScheduleListHtml(html: string, weekNum: number): ExperimentData[] {
    const results: ExperimentData[] = [];

    const tableMatch = /<table[^>]*>([\s\S]*?)<\/table>/.exec(html);
    if (!tableMatch) return results;

    const listTable = tableMatch[1];

    const rowRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/g;
    let rMatch: RegExpExecArray | null = null;
    let rowIndex = 0;
    while ((rMatch = rowRegex.exec(listTable)) !== null) {
      rowIndex++;
      if (rowIndex <= 1) continue;

      const rowHtml = rMatch[1];
      const tdRegex = /<td[^>]*>([\s\S]*?)<\/td>/g;
      const cells: string[] = [];
      let tdM: RegExpExecArray | null = null;
      while ((tdM = tdRegex.exec(rowHtml)) !== null) {
        cells.push(tdM[1].replace(/<[^>]+>/g, '').trim());
      }

      if (cells.length < 9) continue;

      const name = cells[1];
      if (!name || name.length === 0) continue;

      const timeStr = cells[6];
      const teacher = cells[7];
      const lab = cells[8];
      const project = cells.length > 9 ? cells[9] : '';

      const tr = new TimeRange();
      if (timeStr && timeStr.indexOf('周') >= 0) {
        tr.startTime = timeStr;
      }

      const key = name + '|' + lab + '|' + teacher;
      const exp = new ExperimentData();
      exp.type = ExperimentType.OTHERS;
      exp.name = name;
      exp.classroom = lab;
      exp.teacher = teacher;
      exp.reference = project;
      exp.timeRanges = tr.startTime ? [tr] : [];
      results.push(exp);
    }

    return results;
  }

  async fetchOtherExperimentsNoLogin(): Promise<ExperimentData[]> {
    console.info(TAG, 'fetchOtherExperimentsNoLogin: start');
    try {
      return await this._fetchOtherExperimentsInner();
    } catch (e) {
      console.error(TAG, 'fetchOtherExperimentsNoLogin failed: ' + String(e));
      return [];
    }
  }

  private async _fetchOtherExperimentsInner(): Promise<ExperimentData[]> {
    const expMap: Record<string, ExperimentData> = {};

    for (let week = 1; week <= 25; week++) {
      try {
        const resp = await this.http.postRaw(
          'https://sysj.xidian.edu.cn/xidian/StudentCurrWeekTimetable',
          'weeks=' + week,
          'application/x-www-form-urlencoded',
          { 'Content-Type': 'application/x-www-form-urlencoded' }
        );
        const html = resp.body || '';
        if (week <= 2) {
          console.info(TAG, 'fetchOtherExperiments: week=' + week + ' bodyLen=' + html.length);
        }
        if (!html || html.length < 100) {
          if (week <= 2) console.info(TAG, 'fetchOtherExperiments: week=' + week + ' bodyLen=' + html.length);
          continue;
        }

        const weekDates: string[] = [];
        const tableMatch = html.match(/<table[\s\S]*?<\/table>/g);
        if (!tableMatch || tableMatch.length < 2) {
          if (week <= 2) console.info(TAG, 'fetchOtherExperiments: week=' + week + ' tables=' + (tableMatch ? tableMatch.length : 0));
          continue;
        }

        const secondTable = tableMatch[1];
        let thMatch: RegExpExecArray | null = null;
        const thRegex = /<th[^>]*>([\s\S]*?)<\/th>/g;
        let thIndex = 0;
        while ((thMatch = thRegex.exec(secondTable)) !== null) {
          const thContent = thMatch[1];
          const brIdx = thContent.indexOf('<br');
          if (brIdx > 0) {
            const datePart = thContent.substring(brIdx).replace(/<[^>]+>/g, '').trim();
            if (datePart.length >= 8) {
              weekDates.push(datePart);
            }
          }
          thIndex++;
        }

        if (weekDates.length === 0) {
          if (week <= 2) console.info(TAG, 'fetchOtherExperiments: week=' + week + ' weekDates=0');
          continue;
        }

        const weekExps = this.parseSysjHtml(secondTable, weekDates);
        if (weekExps.length > 0) {
          console.info(TAG, 'fetchOtherExperiments: week=' + week + ' found=' + weekExps.length);
        }

        for (const exp of weekExps) {
          const key = exp.name + '|' + exp.classroom + '|' + exp.teacher;
          if (expMap[key]) {
            for (const tr of exp.timeRanges) {
              expMap[key].timeRanges.push(tr);
            }
          } else {
            expMap[key] = exp;
          }
        }
      } catch (e) {
        console.warn(TAG, 'fetchOtherExperiments: week=' + week + ' error: ' + String(e));
      }
    }

    const result: ExperimentData[] = [];
    const keys = Object.keys(expMap);
    for (const k of keys) {
      result.push(expMap[k]);
    }
    console.info(TAG, 'fetchOtherExperiments: done, total=' + result.length);
    return result;
  }

  // ===== 登录后预加载 =====
  async preloadAllData(): Promise<void> {
    console.info(TAG, 'preloadAllData: start');
    if (AppStorage.get('preload_status') === 'loading') {
      console.info(TAG, 'preloadAllData: already running, skip');
      return;
    }
    AppStorage.setOrCreate('preload_status', 'loading');
    AppStorage.setOrCreate('preload_progress', '课表');
    try {
      const semCode: string = SemesterUtil.getCurrentSemesterCode();
      const sid: string = await this.fetchStudentId();
      if (!sid) {
        PreferenceUtil.putString('preload_status', '');
        console.warn(TAG, 'preloadAllData: no student ID');
        return;
      }

      // 开学日期（后台获取，不阻塞）
      if (!PreferenceUtil.getBool('role')) {
        ClassService.getInstance().getSemesterStartDateFromApi(semCode).then((date: string | null) => {
          if (date) { PreferenceUtil.putString('semester_start_date', date); }
        }).catch((_e: Error) => {});
      }

      // 顺序预加载：课表 → 考试 → 实验，进度逐步推进
      ClassService.getInstance().getClassTable(semCode, sid, true).then(() => {
        AppStorage.setOrCreate('preload_progress', '考试');
        AppStorage.setOrCreate('ct_updated', String(Date.now()));
        return ExamService.getInstance().getExamSchedule(semCode);
      }).then((raw: string) => {
        PreferenceUtil.putString('exam_schedule_cache', raw);
        AppStorage.setOrCreate('preload_progress', '实验');
        console.info(TAG, 'preload: exam saved, ' + raw.length + ' chars');
        return this.preloadOtherExperimentsDirect();
      }).then(() => {
        AppStorage.setOrCreate('preload_status', 'done');
        console.info(TAG, 'preloadAllData: done');
      }).catch((e: Error) => {
        AppStorage.setOrCreate('preload_status', 'done');
        console.warn(TAG, 'preload: ' + String(e));
      });
    } catch (e) {
      AppStorage.setOrCreate('preload_status', 'done');
      console.warn(TAG, 'preloadAllData: ' + String(e));
    }
  }

  async preloadOtherExperimentsDirect(): Promise<number> {
    const TERM_ID = '2003';
    const SYSJ_BASE = 'https://sysj.xidian.edu.cn';
    const MAX_WEEKS = 25;
    console.info(TAG, 'preloadOtherExperimentsDirect: start');

    try {
      const r0: HttpResponse = await this.http.get(
        SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=1'
      );
      let allItems: Record<string, string>[] = [];

      if (r0.isOk && r0.body.length > 0 && r0.body.charAt(0) === '[') {
        this._parseWeekData(r0.body, 1, allItems);
        for (let w = 2; w <= MAX_WEEKS; w++) {
          try {
            const rw = await this.http.get(
              SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=' + String(w)
            );
            this._parseWeekData(rw.body, w, allItems);
          } catch (_e) { /* continue */ }
        }
      } else {
        console.info(TAG, 'preloadOtherExperimentsDirect: doing full OAuth');
        allItems = await this._fetchExperimentsWithOAuth(TERM_ID, SYSJ_BASE, MAX_WEEKS);
      }

      if (allItems.length > 0) {
        const co: ESObject = { 'ts': Date.now(), 'data': allItems } as ESObject;
        PreferenceUtil.putString('sysj_exp_cache', JSON.stringify(co));
        console.info(TAG, 'preloadOtherExperimentsDirect: saved ' + allItems.length + ' items');
        return allItems.length;
      }
      return 0;
    } catch (e) {
      console.warn(TAG, 'preloadOtherExperimentsDirect: ' + String(e));
      return 0;
    }
  }

  private async _fetchExperimentsWithOAuth(
    TERM_ID: string, SYSJ_BASE: string, MAX_WEEKS: number
  ): Promise<Record<string, string>[]> {
    let state = '';
    const r1 = await this.http.get(SYSJ_BASE + '/xidian/test');
    let om = r1.body?.match(/[?&]state=([a-f0-9\-]{20,50})/i);
    if (om) { state = om[1]; }

    if (!state) {
      for (let a = 0; a < 4; a++) {
        const sr = await this.http.getNoRedirect(SYSJ_BASE + '/xidian/test');
        if (sr.location) {
          let om2 = sr.location.match(/[?&]state=([^&]+)/);
          if (om2) { state = om2[1]; break; }
          let nextUrl = sr.location;
          if (!nextUrl.startsWith('http')) { nextUrl = SYSJ_BASE + (nextUrl.startsWith('/') ? nextUrl : '/' + nextUrl); }
          const sr2 = await this.http.getNoRedirect(nextUrl);
          if (sr2.location) {
            let om3 = sr2.location.match(/[?&]state=([^&]+)/);
            if (om3) { state = om3[1]; break; }
          }
        }
        if (sr.body) {
          let om4 = sr.body.match(/state=([a-f0-9\-]{20,50})/i);
          if (om4) { state = om4[1]; break; }
        }
      }
    }
    if (!state) {
      console.warn(TAG, '_fetchExperimentsWithOAuth: no state');
      return [];
    }
    console.info(TAG, '_fetchExperimentsWithOAuth: state=' + state);

    const params = 'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
      '&state=' + state + '&client_id=GvsunLims&response_type=code' +
      '&authorize_uri=' + encodeURIComponent(SYSJ_BASE + '/uaa/oauth/authorize');
    await this.http.get(SYSJ_BASE + '/uaa/xidian/login?' + params);

    const idsBackup = this.http.getAllCookies('ids.xidian.edu.cn');
    const ehallBackup = this.http.getAllCookies('ehall.xidian.edu.cn');
    const casUrl = 'https://ids.xidian.edu.cn/authserver/oauth2.0/authorize?' +
      'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/uaa/xidian/callback') +
      '&response_type=code&state=' + state + '&client_id=1387116615722893312';
    const r3 = await this.http.get(casUrl);
    if (r3.body && r3.body.indexOf('password') >= 0 && r3.body.indexOf('username') >= 0 && r3.body.indexOf('<form') >= 0) {
      console.warn(TAG, '_fetchExperimentsWithOAuth: CAS session expired');
      return [];
    }
    this.http.copyCookiesForDomain('ids.xidian.edu.cn', 'sysj.xidian.edu.cn');
    this.http.replaceCookiesForDomain('ids.xidian.edu.cn', idsBackup);
    this.http.replaceCookiesForDomain('ehall.xidian.edu.cn', ehallBackup);

    let pwd = '';
    let pm = r3.body?.match(/var password = '([^']+)'/);
    if (pm) { pwd = pm[1]; }

    if (!pwd) {
      const oauthUrl = SYSJ_BASE + '/uaa/oauth/authorize?' +
        'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
        '&state=' + state + '&client_id=GvsunLims&response_type=code';
      const r4 = await this.http.get(oauthUrl);
      let code = '';
      let cm4 = r4.body?.match(/[?&]code=([a-zA-Z0-9]+)/);
      if (!cm4) { cm4 = r4.body?.match(/["']code["']\s*:\s*["']([^"']+)["']/); }
      if (!cm4) { cm4 = r4.body?.match(/window\.location.*?[?&]code=([a-zA-Z0-9]+)/); }
      if (!cm4) { cm4 = r4.body?.match(/url=.*?[?&]code=([a-zA-Z0-9]+)/); }
      if (cm4) { code = cm4[1]; }

      if (code) {
        const r5 = await this.http.get(SYSJ_BASE + '/xidian/webapp/callback?code=' + code + '&state=' + state);
        let pm2 = r5.body?.match(/var password = '([^']+)'/);
        if (pm2) { pwd = pm2[1]; }
        if (!pwd) { pm2 = r3.body?.match(/var password = '([^']+)'/); if (pm2) { pwd = pm2[1]; } }
      }
    }

    if (!pwd) {
      console.warn(TAG, '_fetchExperimentsWithOAuth: no password extracted');
      return [];
    }

    const account = PreferenceUtil.getString('ids_account');
    const loginBody = 'username=' + encodeURIComponent(account) + '&password=' + encodeURIComponent(pwd);
    await this.http.postRaw(SYSJ_BASE + '/xidian/webapp/login', loginBody, 'application/x-www-form-urlencoded');

    const allItems: Record<string, string>[] = [];
    for (let w = 1; w <= MAX_WEEKS; w++) {
      try {
        const rw = await this.http.get(
          SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=' + String(w)
        );
        this._parseWeekData(rw.body, w, allItems);
      } catch (_e) { /* continue */ }
    }
    console.info(TAG, '_fetchExperimentsWithOAuth: fetched=' + allItems.length);
    return allItems;
  }

  private _parseWeekData(body: string, week: number, out: Record<string, string>[]): void {
    try {
      if (body.length === 0 || body.charAt(0) !== '[') return;
      const raw: Object[] = JSON.parse(body) as Object[];
      for (const d of raw) {
        const row: Object[] = d as Object[];
        if (row.length < 15) continue;
        const item: Record<string, string> = {};
        item['courseCode'] = (row[0] as string) || '';
        item['experimentName'] = (row[1] as string) || '';
        item['department'] = (row[2] as string) || '';
        item['lab'] = (row[11] as string) || '';
        item['weekday'] = (row[4] as string) || '';
        item['startSection'] = (row[5] as string) || '';
        item['endSection'] = (row[6] as string) || '';
        item['week'] = (row[7] as string) || '';
        item['teacher'] = (row[9] as string) || '';
        item['className'] = (row[12] as string) || '';
        item['groupId'] = (row[12] as string) || '';
        item['studentCount'] = (row[13] as string) || '';
        item['experimentProject'] = (row[14] as string) || '';
        item['__week'] = String(week);
        out.push(item);
      }
    } catch (_e) { /* non-critical */ }
  }

  // ==================== 研究生 (yjspt) API ====================

  async getSemesterInfoYjspt(): Promise<string> {
    const cas = CasLoginService.getInstance();
    const http = HttpUtil.getInstance();
    await cas.navigateToYjspt('https://yjspt.xidian.edu.cn/');
    const emptyBody: Object = new Object();
    const resp: HttpResponse = await http.post(
      'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do',
      emptyBody
    );
    const data: Record<string, Object> = resp.json<Record<string, Object>>();
    if (data['code'] as string !== '0') {
      throw new Error('getSemesterInfoYjspt failed: ' + String(data['msg']));
    }
    const info: Record<string, Object> = data['data'] as Record<string, Object>;
    return info['xnxqdm'] as string;
  }

  async clearCache(): Promise<void> {
    await this.cache.clear();
    this.appSessionUrl = {};
  }
}
