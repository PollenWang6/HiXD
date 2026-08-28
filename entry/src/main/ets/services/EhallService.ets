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

// ehall 请求头（Referer 必须 https：西电服务端按 Referer scheme 拼 appShow 重定向 service 前缀，
// http Referer 会返回明文 service=http:// 导致激活链 Cleartext/20 跳）
const EHALL_HEADERS: Record<string, string> = {
  'Referer': 'https://ehall.xidian.edu.cn/new/index_xd.html',
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
    // 1) 校历兜底（西电标准开学日，已核对：春季 3/2、秋季 9/1，对齐到所在周周一）。
    //    这是经过用户确认的可靠基准，作为“唯一真相来源”的退路。
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
    const fbBase = t === 1 ? new Date(y, 8, 1) : new Date(y, 2, 2);
    const fbdow = fbBase.getDay();
    const fbadd = fbdow === 0 ? -6 : fbdow === 1 ? 0 : 1 - fbdow;
    fbBase.setDate(fbBase.getDate() + fbadd);
    const fb: Date = fbBase;

    // 2) 真实开学日（preloadAllData 从 ehall API 抓的 XQKSRQ）：对齐 Flutter traintime_pda 用服务端
    //    termStartDay 作为权威值。仅当返回日期的学年与学期码一致、且月份落在合理开学区间
    //    （秋季 7~10 月 / 春季 1~4 月 / 短学期 6~8 月）时才采用，否则回退校历——
    //    这样既信任服务器真实开学日，又能拦掉 cxjcs.do 偶发返回错学期的脏数据。
    const realSd: string = PreferenceUtil.getString('semester_start_date', '');
    if (realSd.length >= 10) {
      const dp: string[] = realSd.substring(0, 10).split('-');
      if (dp.length === 3) {
        const ry: number = parseInt(dp[0]);
        const rm: number = parseInt(dp[1]);
        const rd: number = parseInt(dp[2]);
        const monthOk: boolean =
          (t === 1 && rm >= 7 && rm <= 10) ||
          (t === 2 && rm >= 1 && rm <= 4) ||
          (t === 3 && rm >= 6 && rm <= 8);
        if (!isNaN(ry) && !isNaN(rm) && !isNaN(rd) && monthOk && ry === y && rd >= 1 && rd <= 31) {
          const base = new Date(ry, rm - 1, rd);
          const bdow = base.getDay();
          const badd = bdow === 0 ? -6 : bdow === 1 ? 0 : 1 - bdow;
          base.setDate(base.getDate() + badd);
          return base;
        }
      }
    }
    return fb;
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
    return SemesterUtil.getAutoSemesterCode();
  }

  // 纯按当前日期推导学期码（忽略 current_semester 偏好）。
  // 用于检测"真实时间已跨入的新学期"，与手动锁定的学期对比，决定是否自动前进回自动跟随。
  static getAutoSemesterCode(): string {
    const now = new Date();
    const y = now.getFullYear();
    const m = now.getMonth() + 1;
    if (m >= 9) return y + '-' + (y + 1) + '-1';            // 9-12月：当年秋季学期
    if (m >= 2 && m <= 7) return (y - 1) + '-' + y + '-2';  // 2-7月：当年春季学期
    if (m === 1) return (y - 1) + '-' + y + '-1';           // 1月：刚结束的秋季（寒假前段）
    return (y - 1) + '-' + y + '-2';                        // 8月：刚结束的春季（暑假）
  }

  // 学期码 chronological 比较（格式 YYYY-YYYY-N，N:1=秋 2=春 3=短；按(年,学期)即时间序）。
  // a 早于 b 返回 -1，相等 0，a 晚于 b 返回 1。
  static compareSemester(a: string, b: string): number {
    const pa: string[] = a.split('-');
    const pb: string[] = b.split('-');
    if (pa.length < 3 || pb.length < 3) return a < b ? -1 : (a > b ? 1 : 0);
    const ya: number = parseInt(pa[0]);
    const ta: number = parseInt(pa[2]);
    const yb: number = parseInt(pb[0]);
    const tb: number = parseInt(pb[2]);
    if (ya !== yb) return ya < yb ? -1 : 1;
    if (ta !== tb) return ta < tb ? -1 : 1;
    return 0;
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

  private async activateAppSession(appId: string, _force: boolean = false): Promise<void> {
    const appPath = APP_PATH_MAP.get(appId) || '/jwapp/sys/wdkb';

    // 对齐 Flutter useApp：每次都重新跑 appShow 拿新的 transfer URL（含新签发的 jsessionid），
    // 不复用内存里的 appSessionUrl 黏性跳过——否则一次失败/陈旧会话会永久卡死后续所有该 app 请求。
    // Flutter 在每次业务请求里都重新 useApp，故天然不会卡死。

    // 先确保 CAS 登录态有效（陈旧 jsessionid 不会自动触发重登，须主动刷新 MOD_AUTH_CAS）
    try { await CasLoginService.getInstance().checkAndAutoLogin(); } catch (e) { /* 忽略，继续尝试 */ }

    try {
      // 对齐 Flutter useApp：GET appShow 不跟随重定向，拿 302 Location（transfer URL，含 jsessionid）
      const resp = await this.http.getNoRedirect(
        'https://ehall.xidian.edu.cn/appShow?appId=' + appId,
        EHALL_HEADERS
      );
      let transferUrl: string | undefined = resp.location;
      if (transferUrl && transferUrl.length > 0) {
        if (transferUrl.startsWith('/')) {
          transferUrl = 'https://ehall.xidian.edu.cn' + transferUrl;
        }
        // 对齐 Flutter：去掉 ';jsessionid=...?' → '?'（jsessionid 已由 Set-Cookie 落入 cookie store）
        transferUrl = transferUrl.replace(/;jsessionid=[^?]*\?/, '?');
        // 对齐 Flutter dioEhall.post(get)：POST 到 transfer URL 真正建立该 app 会话
        try {
          await this.http.postEmpty(transferUrl, EHALL_HEADERS);
        } catch (e2) {
          // 302/跳转等非 2xx 视为激活成功（Flutter 同样不校验返回值）
        }
      } else {
        // 兼容兜底：拿不到 Location 时沿用旧 GET *default*/index.do 导航
        try {
          const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
          await this.http.get(directUrl, EHALL_HEADERS);
        } catch (e3) {
        }
      }
    } catch (e) {
      // appShow 异常：再退一步用 GET *default*/index.do 兜底
      try {
        const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
        await this.http.get(directUrl, EHALL_HEADERS);
      } catch (e3) {
      }
    }
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
    // ===== 学期解析（对齐 Flutter SemesterController：以学校服务器 dqxnxq.do 权威值为准）=====
    // 1) 拉取服务器认定的当前学年学期；失败则回退本地日期推导。
    let remoteSem: string = '';
    try {
      remoteSem = await ClassService.getInstance().getRemoteCurrentSemester();
    } catch (_e) { /* ignore，回退本地 */ }
    // 研究生：dqxnxq.do 是本科生接口，返回空；改用登录时缓存的 yjspt_semester（对齐 Flutter fetchRemoteSemester 取 yjspt xnxqdm）
    if (remoteSem.length === 0 && PreferenceUtil.getBool('role')) {
      const yjsptSem: string = PreferenceUtil.getString('yjspt_semester', '').trim();
      // yjspt 返回的 xnxqdm 是 5 位格式 YYYYN（如 20252 = 2025 学年第 2 学期 = 2025-2026 春季），
      // 之前只认 9 位 YYYYYYYYN / 带 dash 格式，匹配不上 20252 → 服务器值被丢弃回退本地（实测证实）。
      const m5: RegExpMatchArray | null = yjsptSem.match(/^(\d{4})(\d)$/);
      if (m5) {
        const yy: number = parseInt(m5[1]);
        const tt: string = m5[2];
        remoteSem = yy + '-' + (yy + 1) + '-' + tt;
      } else if (/^\d{4}-\d{4}-[123]$/.test(yjsptSem)) {
        remoteSem = yjsptSem;
      } else {
        const m9: RegExpMatchArray | null = yjsptSem.match(/^(\d{4})(\d{4})([123])$/);
        if (m9) remoteSem = m9[1] + '-' + m9[2] + '-' + m9[3];
      }
    }
    // 2) 与手动锁定的学期合并：用户若手动预览"当前/未来"学期则保留；否则跟随服务器（或本地兜底）。
    const pinnedSem: string = PreferenceUtil.getString('current_semester', '');
    const refSem: string = remoteSem.length > 0 ? remoteSem : SemesterUtil.getAutoSemesterCode();
    let effSem: string;
    if (pinnedSem.length > 0 && SemesterUtil.compareSemester(pinnedSem, refSem) >= 0) {
      effSem = pinnedSem; // 用户预览当前/未来学期，保留其选择
    } else {
      effSem = refSem;
      // 写入解析结果，供 getCurrentSemesterCode() 各处（日历/卡片/空教室）统一复用
      PreferenceUtil.putString('current_semester', effSem);
    }
    // 3) 跨学期清缓存（仅学期真正变化时才清，日常同学期启动不动）：
    //    日历快照按旧学期周索引生成、考试缓存/通用缓存按旧学期 key，必须作废重算。
    const lastSem: string = PreferenceUtil.getString('last_semester_code', '');
    if (lastSem.length > 0 && lastSem !== effSem) {
      PreferenceUtil.putString('class_grid_snapshot', '');
      AppStorage.setOrCreate('class_grid_snapshot', '');
      PreferenceUtil.putString('exam_schedule_cache', '');
      await PreferenceUtil.saveSharedFile('exam_schedule', '');
      try { await CacheService.getInstance().init(); await CacheService.getInstance().clear(); } catch (_e) { /* ignore */ }
      AppStorage.setOrCreate('ct_updated', String(Date.now()));
    }
    PreferenceUtil.putString('last_semester_code', effSem);
    try {
      const semCode: string = SemesterUtil.getCurrentSemesterCode();
      const sid: string = await this.fetchStudentId();
      if (!sid) {
        PreferenceUtil.putString('preload_status', '');
        return;
      }

      // 开学日期（后台获取，不阻塞）
      if (PreferenceUtil.getBool('role')) {
        // 研究生：用 queryRcap 当前周反推开学日（对齐 Flutter getYjspt）；cxjcs.do 对研究生不适用
        ClassService.getInstance().getYjsptTermStartDay().then((date: string | null) => {
          if (date) { PreferenceUtil.putString('semester_start_date', date); }
        }).catch((_e: Error) => {});
      } else {
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
      }).then(async (raw: string) => {
        if (raw && raw.length > 100) {
          PreferenceUtil.putString('exam_schedule_cache', raw);
          await PreferenceUtil.saveSharedFile('exam_schedule', raw);
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
