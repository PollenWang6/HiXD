// ClassService.ets — 课程表数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';
import { ClassItemModel, ClassTableRow, UnscheduledCourse, ClassChange, EHALL_APP_CLASS_TABLE, EHALL_APP_EXAM, EHALL_APP_SCORE, EHALL_APP_EMPTY_CLASSROOM } from './Models';

const TAG = 'ClassService';

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
  [EHALL_APP_CLASS_TABLE, '/jwapp/sys/wdkb'],
  [EHALL_APP_EXAM, '/jwapp/sys/studentWdksapApp'],
  [EHALL_APP_SCORE, '/jwapp/sys/cjcx'],
  [EHALL_APP_EMPTY_CLASSROOM, '/jwapp/sys/kxjas'],
]);

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

  /**
   * 业务 POST 请求
   */
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

  /**
   * 根据 API 路径反查 appId
   */
  private findAppIdByPath(path: string): string {
    if (path.includes('wdkb')) return EHALL_APP_CLASS_TABLE;
    if (path.includes('studentWdksapApp') || path.includes('wdksap')) return EHALL_APP_EXAM;
    if (path.includes('cjcx')) return EHALL_APP_SCORE;
    if (path.includes('kxjas')) return EHALL_APP_EMPTY_CLASSROOM;
    return '';
  }

  /**
   * 提取 API rows 数组
   */
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
      } catch (_) {}
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
    } catch (_) {}
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
      } catch (_) {}
      const resp = await this.appPost(
        '/jwapp/sys/wdkb/modules/xskcb/xsdkkc.do',
        { 'XNXQDM': semCode, '*order': '-SQSJ' }
      );
      return resp.body;
    }, 30 * 60 * 1000);  // 30 分钟缓存
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
        const origDayNum: string = String(row['TKXQ'] ?? '');
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
          originalWeeks: origWeeks,
          originalDay: '周' + (dayMap[origDayNum] || origDayNum),
          originalSection: String(row['TKKSJC'] ?? '') + '-' + String(row['TKJSJC'] ?? ''),
          originalRoom: String(row['JASMC'] ?? ''),
          originalTeacher: String(row['TKJS'] ?? ''),
          newWeeks: newWeeks,
          newDay: '周' + (dayMap[newDayNum] || newDayNum),
          newSection: String(row['XSKKSJC'] ?? '') + '-' + String(row['XSKJSJC'] ?? ''),
          newRoom: String(row['XJASMC'] ?? ''),
          newTeacher: String(row['XJSXM'] ?? '')
        });
      }
    } catch (_) {}
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
