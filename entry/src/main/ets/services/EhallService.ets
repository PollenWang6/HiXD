// EhallService.ets — 西电 Ehall 数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';
import { ClassService } from './ClassService';
import { ExamService } from './ExamService';

import { ExperimentService } from './ExperimentService';
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
        }).catch((_e: Error) => { console.warn("EhallService", "ignored error: " + String(_e.message)); });
      }

      // 顺序预加载：课表 → 考试 → 实验，进度逐步推进
      ClassService.getInstance().getClassTable(semCode, sid, true).then(() => {
        AppStorage.setOrCreate('preload_progress', '考试');
        AppStorage.setOrCreate('ct_updated', String(Date.now()));
        return ExamService.getInstance().getExamSchedule(semCode);
      }).then((raw: string) => {
        if (raw && raw.length > 100) {
          PreferenceUtil.putString('exam_schedule_cache', raw);
          console.info(TAG, 'preload: exam saved, ' + raw.length + ' chars');
        } else {
          console.warn(TAG, 'preload: exam data too short (' + (raw ? raw.length : 0) + '), keeping old cache');
        }
        AppStorage.setOrCreate('preload_progress', '实验');
        return ExperimentService.getInstance().preloadDirect();
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

  // ==================== 研究生 (yjspt) API ====================

  async getSemesterInfoYjspt(): Promise<string> {
    const cas = CasLoginService.getInstance();
    const http = HttpUtil.getInstance();
    // 先走 portal 页面建立完整 session（处理 CAS OAuth 重定向链）
    await cas.navigateToYjspt(
      'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/portal/index.do');
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
