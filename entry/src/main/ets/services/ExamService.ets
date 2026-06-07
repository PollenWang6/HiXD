// ExamService.ets — 考试安排数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';
import { ExamItemModel, ExamRow, EHALL_APP_CLASS_TABLE, EHALL_APP_EXAM, EHALL_APP_SCORE, EHALL_APP_EMPTY_CLASSROOM } from './Models';

const TAG = 'ExamService';

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

export class ExamService {
  private static inst: ExamService;
  private http = HttpUtil.getInstance();
  private cache = CacheService.getInstance();
  private appSessionUrl: Record<string, string> = {};

  constructor() {}

  static getInstance(): ExamService {
    if (!ExamService.inst) ExamService.inst = new ExamService();
    return ExamService.inst;
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

  async getExamSchedule(semCode: string): Promise<string> {
    if (PreferenceUtil.getBool('role')) {
      const key: string = 'exam_' + semCode;
      return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
        return this.getExamYjspt(semCode);
      }, 5 * 60 * 1000);
    }
    await this.init();
    const key = 'exam_' + semCode;
    return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
      await this.activateAppSession(EHALL_APP_EXAM);
      // 已安排考试
      const arranged = (await this.appPost(
        '/jwapp/sys/studentWdksapApp/modules/wdksap/wdksap.do',
        { 'XNXQDM': semCode, '*order': '-KSRQ,-KSSJMS' }
      )).body;
      // 未安排考试（已选课但考试未排定）
      const notArranged = await this.getNotArrangedExamsEhall(semCode);
      return ExamService.mergeExamResults(arranged, notArranged);
    }, 5 * 60 * 1000);
  }

  // 未安排考试列表（本科生 ehall）
  async getNotArrangedExamsEhall(semCode: string): Promise<string> {
    try {
      const resp = await this.appPost(
        '/jwapp/sys/studentWdksapApp/modules/wdksap/cxyxkwapkwdkc.do',
        { 'XNXQDM': semCode }
      );
      return resp.body;
    } catch (_) {
      return '{"datas":{"cxyxkwapkwdkc":{"rows":[]}}}';
    }
  }

  // 合并已安排和未安排考试
  static mergeExamResults(arranged: string, notArranged: string): string {
    try {
      const arrObj: Record<string, Object> = JSON.parse(arranged) as Record<string, Object>;
      const naObj: Record<string, Object> = JSON.parse(notArranged) as Record<string, Object>;
      // 从 notArranged 中提取课程名，转成考试行格式（无日期/时间）
      const naDatas: Record<string, Object> = naObj['datas'] as Record<string, Object>;
      const naModule: Record<string, Object> = naDatas['cxyxkwapkwdkc'] as Record<string, Object>;
      const naRows: Object[] = (naModule ? naModule['rows'] as Object[] : []) ?? [];
      const naExamRows: Record<string, string>[] = [];
      for (const row of naRows) {
        const r: Record<string, Object> = row as Record<string, Object>;
        naExamRows.push({
          'KCM': String(r['KCM'] ?? ''),
          'KSSJMS': '',
          'KSRQ': '',
          'KSMC': '',
          'JASMC': '',
          'ZWH': ''
        });
      }
      if (naExamRows.length > 0) {
        const arrDatas: Record<string, Object> = arrObj['datas'] as Record<string, Object>;
        const arrMod: Record<string, Object> = arrDatas['wdksap'] as Record<string, Object>;
        const existingRows: Object[] = (arrMod ? arrMod['rows'] as Object[] : []) ?? [];
        const merged: Object[] = [...existingRows, ...naExamRows];
        // 写回
        const wdksObj: Record<string, Object> = arrObj['datas'] as Record<string, Object>;
        (wdksObj['wdksap'] as Record<string, Object>)['rows'] = merged;
      }
      return JSON.stringify(arrObj);
    } catch (_) {
      return arranged;
    }
  }

  // ==================== 研究生 (yjspt) API ====================

  async getExamYjspt(semCode: string): Promise<string> {
    const cas = CasLoginService.getInstance();
    const http = HttpUtil.getInstance();
    await cas.navigateToYjspt(
      'https://yjspt.xidian.edu.cn/gsapp/sys/wdksapp/*default/index.do');
    const sid: string = PreferenceUtil.getString('ids_account');
    const qs: Record<string, string>[] = [];
    const q0: Record<string, string> = {'name':'XNXQDM','caption':'','builder':'equal','linkOpt':'AND','value':semCode};
    const q1: Record<string, string> = {'name':'SFFBKSAP','caption':'','builder':'equal','linkOpt':'AND','value':'1'};
    const q2: Record<string, string> = {'name':'XH','caption':'','builder':'equal','linkOpt':'AND','value':sid};
    const q3: Record<string, string> = {'name':'KSAPWID','caption':'','builder':'notEqual','linkOpt':'AND','value':''};
    qs.push(q0); qs.push(q1); qs.push(q2); qs.push(q3);
    const emptyObj: Object = new Object();
    const examResp: HttpResponse = await http.post(
      'https://yjspt.xidian.edu.cn/gsapp/sys/wdksapp/modules/ksxxck/wdksxxcx.do?querySetting=' +
      encodeURIComponent(JSON.stringify(qs)) +
      '&pageSize=1000&pageNumber=1', emptyObj);
    const data: Record<string, Object> = examResp.json<Record<string, Object>>();
    const datas: Record<string, Object> = data['datas'] as Record<string, Object>;
    const wdks: Record<string, Object> = datas['wdksxxcx'] as Record<string, Object>;
    const rows: Object[] = wdks['rows'] as Object[] || [];
    const wrapped: Record<string, string>[] = [];
    for (const r of rows) {
      const row: Record<string, Object> = r as Record<string, Object>;
      const out: Record<string, string> = {};
      out['KCM'] = String(row['KCMC'] ?? '');
      out['JASMC'] = String(row['JASMC'] ?? '');
      const kssjms: string = String(row['KSSJMS'] ?? '');
      out['KSSJMS'] = kssjms;
      // 从 KSSJMS 提取日期部分作为 KSRQ（格式："2026-04-22 13:00-15:00(星期三)" → "2026-04-22"）
      const spaceIdx: number = kssjms.indexOf(' ');
      out['KSRQ'] = spaceIdx > 0 ? kssjms.substring(0, spaceIdx) : kssjms;
      out['KSMC'] = String(row['KSLXDM_DISPLAY'] ?? '');
      out['SFMR'] = '';
      wrapped.push(out);
    }
    const rowsObj: Record<string, Object> = {'rows': wrapped};
    const wdksObj: Record<string, Object> = {'wdksxxcx': rowsObj};
    return JSON.stringify({'datas': wdksObj});
  }

  static parseExamSchedule(body: string): ExamItemModel[] {
    const raw: object[] = ExamService.extractRaw(body);
    const out: ExamItemModel[] = [];
    for (const row of raw) {
      const r: ExamRow = row as ExamRow;
      const item: ExamItemModel = new ExamItemModel();
      item.kcm = r.KCM || '';
      item.ksmc = r.KSMC || '';
      item.kssjms = r.KSSJMS || '';
      item.ksrq = r.KSRQ || '';
      item.jasmc = r.JASMC || '';
      item.zw = r.ZWH || '';
      out.push(item);
    }
    return out;
  }
}
