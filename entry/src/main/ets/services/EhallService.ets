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

import { findAppIdByPath as _findAppByPath, sharedAppPost, AppPostContext } from './EhallConstants';

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

  // 学期标准总周数（西电标准：秋季/春季 20 周含考试周；短学期约 6 周）
  // 用于课表周选择器上限，与 Flutter traintime_pda 保持一致（即使数据 SKZC 缺失末周也显示标准周数）
  static getStandardWeekCount(semCode: string): number {
    const parts: string[] = semCode.split('-');
    const t: number = parts.length >= 3 ? parseInt(parts[2]) : 1;
    if (t === 2) return 20;   // 春季学期 20 周
    if (t === 3) return 6;    // 短学期（小学期）约 6 周
    return 20;                // 秋季学期 20 周
  }

  static formatSemester(code: string): string {
    const parts: string[] = code.split('-');
    if (parts.length !== 3) return code;
    const term: string = parts[2];
    const termName: string = term === '1' ? '秋季学期' : term === '2' ? '春季学期' : '短学期';
    return parts[0] + '-' + parts[1] + ' ' + termName;
  }

  // 根据当前学期代码计算下学期代码
  // e.g. '2025-2026-2' → '2026-2027-1'  or  '2025-2026-1' → '2025-2026-2'
  static getNextSemesterCode(current: string): string {
    const parts: string[] = current.split('-');
    if (parts.length !== 3) return current;
    const y1: number = parseInt(parts[0]);
    const y2: number = parseInt(parts[1]);
    const term: number = parseInt(parts[2]);
    if (term === 1) {
      return y1 + '-' + y2 + '-2';
    } else {
      return y2 + '-' + (y2 + 1) + '-1';
    }
  }

  // 判断当前日期是否在学期有效范围内（学期开始日 ~ 学期开始日 + maxWeeks*7天）
  static isDateInSemester(code: string, maxWeeks: number): boolean {
    const now: Date = new Date();
    const start: Date = SemesterUtil.getSemesterStartDate(code);
    if (now < start) return false;
    const diffDays: number = Math.floor((now.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
    return diffDays < maxWeeks * 7;
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
          return hasLogin;
        }
      }
      return false;
    } catch (e) {
      throw new Error('NETWORK_ERROR');
    }
  }

  async tryAutoRestoreLogin(): Promise<boolean> {
    try {
      const verified = await this.checkEhallLogin();
      if (verified) {
        return true;
      }
      const cas = CasLoginService.getInstance();
      const restored = await cas.tryAutoRestoreLogin();
      if (restored) {
        const reVerified = await this.checkEhallLogin();
        if (reVerified) {
          await cas.syncCookiesToWebView();
          return true;
        }
      }
      return false;
    } catch (e) {
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
          await PreferenceUtil.putString('ids_account', sid);
          return sid;
        }
      }
    } catch (e) {
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
          await PreferenceUtil.putString('ids_account', sid);
          return sid;
        }
      }
    } catch (e) {
    }

    return '';
  }

  private async activateAppSession(appId: string, force: boolean = false): Promise<void> {
    if (!force && this.appSessionUrl[appId]) {
      return;
    }

    const appPath = APP_PATH_MAP.get(appId) || '/jwapp/sys/wdkb';
    this.appSessionUrl[appId] = appPath;

    const cookiesBefore = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (!force && cookiesBefore.toLowerCase().includes('jsessionid')) {
      return;
    }


    try {
      const resp = await this.http.get(
        'https://ehall.xidian.edu.cn/appShow?appId=' + appId,
        EHALL_HEADERS
      );
    } catch (e) {
    }

    const cookiesAfter1 = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (cookiesAfter1.toLowerCase().includes('jsessionid')) {
      return;
    }

    try {
      const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
      const resp2 = await this.http.get(directUrl, EHALL_HEADERS);

      if (resp2.isRedirect && resp2.location) {
        let loc: string = resp2.location;
        if (loc.startsWith('/')) {
          loc = 'https://ehall.xidian.edu.cn' + loc;
        }
        try {
          await this.http.get(loc, EHALL_HEADERS);
        } catch (e3) {
        }
      }
    } catch (e2) {
    }

    const cookiesFinal = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    const hasModAuth = cookiesFinal.toLowerCase().includes('mod_auth_cas');
    const hasJsession = cookiesFinal.toLowerCase().includes('jsessionid');
  }

  private readonly _appCtx: AppPostContext = new AppPostContext(
    this.http,
    (appId: string, force: boolean = false) => this.activateAppSession(appId, force),
    this.appSessionUrl,
    TAG
  );

  private async appPost(path: string, body: Record<string, string>): Promise<HttpResponse> {
    return sharedAppPost(this._appCtx, path, body);
  }

  // 别名（EhallService 保持实例方法签名兼容）
  private findAppIdByPath(path: string): string { return _findAppByPath(path); }

  static extractRaw(body: string): object[] {
    try {
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
              return rows as object[];
            }
            const extParams = subMap['extParams'];
            if (extParams !== null && typeof extParams === 'object') {
              const extMap = extParams as Record<string, object>;
              const extRows = extMap['rows'];
              if (Array.isArray(extRows)) {
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
                return rows as object[];
              }
            }
          }
        }
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  // ===== 登录后预加载 =====
  async preloadAllData(): Promise<void> {
    if (AppStorage.get('preload_status') === 'loading') {
      return;
    }
    AppStorage.setOrCreate('preload_status', 'loading');
    AppStorage.setOrCreate('preload_progress', '课表');
    try {
      const semCode: string = SemesterUtil.getCurrentSemesterCode();
      const sid: string = await this.fetchStudentId();
      if (!sid) {
        PreferenceUtil.putString('preload_status', '');
        return;
      }

      // 开学日期（后台获取，不阻塞）
      if (!PreferenceUtil.getBool('role')) {
        ClassService.getInstance().getSemesterStartDateFromApi(semCode).then((date: string | null) => {
          if (date) { PreferenceUtil.putString('semester_start_date', date); }
        }).catch((_e: Error) => {});
      }

      // 顺序预加载：课表 → 考试 → 实验，进度逐步推进
      // 注意：必须 await 整条链，否则 preloadAllData 会在数据拉完前就 resolve，
      // 导致调用方（如首页自动同步日历）读到旧缓存
      await ClassService.getInstance().getClassTable(semCode, sid, true).then(() => {
        AppStorage.setOrCreate('preload_progress', '考试');
        AppStorage.setOrCreate('ct_updated', String(Date.now()));
        return ExamService.getInstance().getExamSchedule(semCode);
      }).then((raw: string) => {
        if (raw && raw.length > 100) {
          PreferenceUtil.putString('exam_schedule_cache', raw);
          PreferenceUtil.saveSharedFile('exam_schedule', raw);
        } else {
        }
        AppStorage.setOrCreate('preload_progress', '实验');
        return ExperimentService.getInstance().preloadDirect();
      }).then(() => {
        AppStorage.setOrCreate('preload_status', 'done');
      }).catch((e: Error) => {
        AppStorage.setOrCreate('preload_status', 'done');
      });
    } catch (e) {
      AppStorage.setOrCreate('preload_status', 'done');
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
