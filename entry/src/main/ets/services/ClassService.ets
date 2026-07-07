// ClassService.ets — 课程表数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';
import { ClassItemModel, ClassTableRow, UnscheduledCourse, ClassChange, EHALL_APP_CLASS_TABLE } from './Models';
import { EHALL_HEADERS, APP_PATH_MAP, extractRaw, sharedAppPost, AppPostContext } from './EhallConstants';

const TAG = 'ClassService';

export class ClassService {
  private static inst: ClassService;
  private http = HttpUtil.getInstance();
  private cache = CacheService.getInstance();
  private appSessionUrl: Record<string, string> = {};

  constructor() {}

  static getInstance(): ClassService {
    if (!ClassService.inst) ClassService.inst = new ClassService();
    return ClassService.inst;
  }

  private async init(): Promise<void> { await this.cache.init(); }

  /**
   * 激活 app session
   */
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

  /** POST上下文（供 sharedAppPost 委托） */
  private readonly _appCtx: AppPostContext = new AppPostContext(
    this.http,
    (appId: string, force: boolean = false) => this.activateAppSession(appId, force),
    this.appSessionUrl,
    TAG
  );

  /** 业务 POST 请求 → sharedAppPost */
  private async appPost(path: string, body: Record<string, string>): Promise<HttpResponse> {
    return sharedAppPost(this._appCtx, path, body);
  }

  static extractRaw(body: string): object[] { return extractRaw(body, TAG); }

  /**
   * 获取课程表数据
   */
  async getClassTable(semCode: string, sid: string, forceRefresh: boolean = false): Promise<string> {
    if (PreferenceUtil.getBool('role')) {
      const key: string = 'ct_' + semCode;
      return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
        return this.getClassTableYjspt(semCode, sid);
      }, 7 * 24 * 60 * 60 * 1000, forceRefresh);
    }
    await this.init();
    const key = 'ct_' + semCode;
    return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
      try {
        await this.activateAppSession(EHALL_APP_CLASS_TABLE);
      } catch (e) {
        console.warn(TAG, 'getClassTable: activateAppSession failed, continuing without it: ' + JSON.stringify(e));
      }

      const body: Record<string, string> = { 'XNXQDM': semCode };
      if (sid && sid.length > 0) {
        body['XH'] = sid;
      }

      const resp = await this.appPost(
        '/jwapp/sys/wdkb/modules/xskcb/xskcb.do',
        body
      );
      console.info(TAG, 'getClassTable: status=' + resp.statusCode +
        ' bodyLen=' + resp.body.length);
      if (!resp.isOk) {
        console.warn(TAG, 'getClassTable: unexpected response, bodyLen=' + resp.body.length);
      }
      // 防止 HTML 错误页被缓存 — appPost 重试后仍返回 HTML 时直接抛异常
      const trimmed = resp.body.trimStart();
      if (trimmed.startsWith('<!') || trimmed.startsWith('<html') || trimmed.startsWith('<HTML')) {
        throw new Error('getClassTable: received HTML instead of JSON (session expired?)');
      }
      return resp.body;
    }, 7 * 24 * 60 * 60 * 1000, forceRefresh);
  }

  // 未排课列表（本科生 ehall：已选课但尚未排入课表）
  async getUnscheduledCoursesEhall(semCode: string, sid: string): Promise<string> {
    await this.init();
    const key = 'unscheduled_' + semCode;
    return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
      try {
        await this.activateAppSession(EHALL_APP_CLASS_TABLE);
      } catch (_) { console.warn("ClassService", "ignored error"); }
      const resp = await this.appPost(
        '/jwapp/sys/wdkb/modules/xskcb/cxxsllsywpk.do',
        { 'XNXQDM': semCode, 'XH': sid }
      );
      return resp.body;
    }, 7 * 24 * 60 * 60 * 1000);
  }

  // 解析未排课列表
  static parseUnscheduledCourses(body: string): UnscheduledCourse[] {
    const out: UnscheduledCourse[] = [];
    try {
      const obj: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const datas: Record<string, Object> = obj['datas'] as Record<string, Object>;
      const cxxsllsywpk: Record<string, Object> = datas['cxxsllsywpk'] as Record<string, Object>;
      const rows: Object[] = cxxsllsywpk['rows'] as Object[];
      if (!rows) return out;
      for (const r of rows) {
        const row: Record<string, Object> = r as Record<string, Object>;
        out.push({
          name: String(row['KCM'] ?? ''),
          code: String(row['KCH'] ?? ''),
          number: String(row['KXH'] ?? ''),
          teacher: String(row['SKJS'] ?? '')
        });
      }
    } catch (_) { console.warn("ClassService", "ignored error"); }
    return out;
  }

  async getCachedClassTable(semCode: string, sid: string): Promise<string | null> {
    await this.init();
    const key = 'ct_' + semCode;
    return this.cache.get(key);
  }

  async getCachedClassTableStale(semCode: string, sid: string): Promise<string | null> {
    await this.init();
    const key = 'ct_' + semCode;
    return this.cache.getStale(key);
  }

  // 课程变更列表（本科生 ehall：调课/停课/补课）
  async getClassChangesEhall(semCode: string): Promise<string> {
    await this.init();
    const key = 'changes_' + semCode;
    return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
      try {
        await this.activateAppSession(EHALL_APP_CLASS_TABLE);
      } catch (_) { console.warn("ClassService", "ignored error"); }
      const resp = await this.appPost(
        '/jwapp/sys/wdkb/modules/xskcb/xsdkkc.do',
        { 'XNXQDM': semCode, '*order': '-SQSJ' }
      );
      return resp.body;
    }, 30 * 60 * 1000);  // 30 分钟缓存
  }

  // 格式化周次字符串 "000000001000" → "第16周" 或 "第14-18周"
  static formatWeekRange(skzc: string): string {
    if (!skzc || skzc.length === 0) return '';
    const weeks: number[] = [];
    for (let i = 0; i < skzc.length; i++) {
      if (skzc[i] === '1') weeks.push(i + 1);
    }
    if (weeks.length === 0) return '';
    if (weeks.length === 1) return '第' + weeks[0] + '周';
    // 合并连续周次
    const ranges: string[] = [];
    let start: number = weeks[0];
    let prev: number = weeks[0];
    for (let i = 1; i < weeks.length; i++) {
      if (weeks[i] === prev + 1) { prev = weeks[i]; continue; }
      ranges.push(start === prev ? '第' + start + '周' : '第' + start + '-' + prev + '周');
      start = weeks[i];
      prev = weeks[i];
    }
    ranges.push(start === prev ? '第' + start + '周' : '第' + start + '-' + prev + '周');
    return ranges.join(', ');
  }

  // 解析课程变更列表
  static parseClassChanges(body: string): ClassChange[] {
    const out: ClassChange[] = [];
    try {
      const obj: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const datas: Record<string, Object> = obj['datas'] as Record<string, Object>;
      const xsdkkc: Record<string, Object> = datas['xsdkkc'] as Record<string, Object>;
      const rows: Object[] = xsdkkc['rows'] as Object[];
      if (!rows) return out;
      for (const r of rows) {
        const row: Record<string, Object> = r as Record<string, Object>;
        const tklxdm: string = String(row['TKLXDM'] ?? '');
        let typeStr = '调课';
        if (tklxdm === '02') typeStr = '停课';
        else if (tklxdm === '03') typeStr = '补课';
        // 周次字符串转描述
        const origDayNum: string = String(row['SKXQ'] ?? '');
        const newDayNum: string = String(row['XSKXQ'] ?? '');
        const dayMap: Record<string, string> = { '1': '一', '2': '二', '3': '三', '4': '四', '5': '五', '6': '六', '7': '日' };
        // 周次字符串转描述
        const origWeeks: string = String(row['SKZC'] ?? '');
        const newWeeks: string = String(row['XSKZC'] ?? '');
        out.push({
          type: typeStr,
          courseName: String(row['KCM'] ?? ''),
          courseCode: String(row['KCH'] ?? ''),
          classNumber: String(row['KXH'] ?? ''),
          originalWeeks: ClassService.formatWeekRange(origWeeks),
          originalDay: '周' + (dayMap[origDayNum] || origDayNum),
          originalSection: String(row['KSJC'] ?? '') + '-' + String(row['JSJC'] ?? ''),
          originalRoom: String(row['JASMC'] ?? ''),
          originalTeacher: String(row['YSKJS'] ?? ''),
          newWeeks: ClassService.formatWeekRange(newWeeks),
          newDay: '周' + (dayMap[newDayNum] || newDayNum),
          newSection: String(row['XKSJC'] ?? '') + '-' + String(row['XJSJC'] ?? ''),
          newRoom: String(row['XJASMC'] ?? ''),
          newTeacher: String(row['XSKJS'] ?? '')
        });
      }
    } catch (_) { console.warn("ClassService", "ignored error"); }
    return out;
  }

  // ==================== 研究生 (yjspt) API ====================

  async getClassTableYjspt(semCode: string, sid: string): Promise<string> {
    const cas = CasLoginService.getInstance();
    const http = HttpUtil.getInstance();
    await cas.navigateToYjspt(
      'https://yjspt.xidian.edu.cn/gsapp/sys/wdkbapp/*default/index.do#/xskcb');
    const now: Date = new Date();
    const dayStr: string = String(now.getFullYear()) +
      String(now.getMonth() + 1).padStart(2, '0') +
      String(now.getDate()).padStart(2, '0');
    const weekBody: Record<string, string> = {'day': dayStr};
    const weekResp: HttpResponse = await http.post(
      'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/portal/queryRcap.do', weekBody);
    const weekData: Record<string, Object> = weekResp.json<Record<string, Object>>();
    let currentWeek: number = 1;
    if (weekData['xnxq'] !== undefined && weekData['xnxq'] !== null) {
      const match: RegExpMatchArray | null = String(weekData['xnxq']).match(/[0-9]+/);
      if (match) { currentWeek = parseInt(match[0]) || 1; }
    }
    const classBody: Record<string, string> = {'XNXQDM': semCode};
    const classResp: HttpResponse = await http.post(
      'https://yjspt.xidian.edu.cn/gsapp/sys/wdkbapp/modules/xskcb/xspkjgcx.do', classBody);
    const classData: Record<string, Object> = classResp.json<Record<string, Object>>();
    if (classData['code'] as string !== '0') {
      console.warn(TAG, 'getClassTableYjspt: ' + JSON.stringify(classData));
      return '';
    }
    const datas: Record<string, Object> = classData['datas'] as Record<string, Object>;
    const xspk: Record<string, Object> = datas['xspkjgcx'] as Record<string, Object>;
    const rows: Object[] = xspk['rows'] as Object[];
    const wrapped: Record<string, string>[] = [];
    for (const r of rows) {
      const row: Record<string, Object> = r as Record<string, Object>;
      const out: Record<string, string> = {};
      out['KCM'] = String(row['KCMC'] ?? '');
      out['JASMC'] = String(row['JASMC'] ?? '');
      out['SKJS'] = String(row['JSXM'] ?? '');
      out['SKXQ'] = String(row['XQ'] ?? '1');
      out['KSJC'] = String(row['KSJCDM'] ?? '1');
      out['JSJC'] = String(row['JSJCDM'] ?? '1');
      out['SKZC'] = String(row['ZCBH'] ?? '');
      out['KXH'] = String(row['KCDM'] ?? '');
      out['KCH'] = '';
      wrapped.push(out);
    }
    const rowsObj: Record<string, Object> = {'rows': wrapped};
    const xskcbObj: Record<string, Object> = {'xskcb': rowsObj};
    const result: Record<string, Object> = {'datas': xskcbObj};
    PreferenceUtil.putNumber('yjspt_current_week', currentWeek);
    return JSON.stringify(result);
  }

  /**
   * 从 ehall API 获取学期开学日期
   */
  async getSemesterStartDateFromApi(semCode: string): Promise<string | null> {
    try {
      await this.init();
      await this.activateAppSession(EHALL_APP_CLASS_TABLE);
      const parts: string[] = semCode.split('-');
      const body: Record<string, string> = {'XN': parts[0] + '-' + parts[1], 'XQ': parts[2]};
      const resp: HttpResponse = await this.appPost(
        '/jwapp/sys/wdkb/modules/jshkcb/cxjcs.do', body);
      const data: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      const datas: Record<string, Object> = data['datas'] as Record<string, Object>;
      const cxjcs: Record<string, Object> = datas['cxjcs'] as Record<string, Object>;
      const rows: Object[] = cxjcs['rows'] as Object[];
      if (rows.length > 0) {
        const r0: Record<string, Object> = rows[0] as Record<string, Object>;
        const date: string = String(r0['XQKSRQ'] ?? '');
        console.info(TAG, 'getSemesterStartDateFromApi: ' + date);
        return date;
      }
    } catch (e) {
      console.warn(TAG, 'getSemesterStartDateFromApi failed: ' + String(e));
    }
    return null;
  }

  static parseClassTable(body: string): ClassItemModel[] {
    const raw: object[] = ClassService.extractRaw(body);
    const out: ClassItemModel[] = [];
    for (const row of raw) {
      const r: ClassTableRow = row as ClassTableRow;
      const item: ClassItemModel = new ClassItemModel();
      item.kcm = r.KCM || '';
      item.kch = r.KCH || '';
      item.kxh = r.KXH || '';
      item.skxq = r.SKXQ || '';
      item.skzc = r.SKZC || '';
      item.ksjc = r.KSJC || '';
      item.jsjc = r.JSJC || '';
      item.skjs = r.SKJS || '';
      item.jasmc = r.JASMC || '';
      out.push(item);
    }
    return out;
  }
}
