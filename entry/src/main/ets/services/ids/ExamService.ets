// ExamService.ets — 考试安排数据服务
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { CacheService } from '../common/CacheService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { CasLoginService } from '../auth/CasLoginService';
import { ExamItemModel, ExamRow, EHALL_APP_EXAM } from '../../models/common/Models';
import { EHALL_HEADERS, APP_PATH_MAP, extractRaw, sharedAppPost, AppPostContext,
         assertExtParamsOk, EhallDataError } from './EhallConstants';

const TAG = 'ExamService';

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
  private async activateAppSession(appId: string, _force: boolean = false): Promise<void> {
    const appPath = APP_PATH_MAP.get(appId) || '/jwapp/sys/wdkb';

    // 对齐 Flutter useApp：每次都重新跑 appShow 拿新的 transfer URL（含新签发的 jsessionid），
    // 不复用内存里的 appSessionUrl 黏性跳过——否则一次失败/陈旧会话会永久卡死后续所有该 app 请求。
    // Flutter 在每次业务请求里都重新 useApp，故天然不会卡死。

    // 先确保 CAS 登录态有效（陈旧 jsessionid 不会自动触发重登，须主动刷新 MOD_AUTH_CAS）
    try {
      await CasLoginService.getInstance().checkAndAutoLogin();
    } catch (e) {
      // 鉴权类异常（需重新登录/设备验证）必须原样上抛（与 EmptyClassroomService 同款修复）；
      // 网络抖动等非鉴权错误不阻断，继续尝试激活（TGC 可能仍有效）。
      const err: Error = e as Error;
      if (CasLoginService.isAuthError(err)) {
        throw err;
      }
      console.warn('[' + TAG + '] checkAndAutoLogin 失败，继续尝试激活: ' + String(err));
    }

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
        try {
          const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
          await this.http.get(directUrl, EHALL_HEADERS);
        } catch (e3) {
        }
      }
    } catch (e) {
      try {
        const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
        await this.http.get(directUrl, EHALL_HEADERS);
      } catch (e3) {
      }
    }

    // 对齐 Flutter useApp：不在此校验 jsessionid、也不抛异常（Flutter 从不校验 useApp 返回值，
    // 由后续业务请求自然暴露失败）。去掉原先的 throw，避免"服务暂不可用"与黏性缓存叠加成永久失败。
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

  static extractRaw(body: string): object[] { return extractRaw(body, TAG); }

  async getExamSchedule(semCode: string, forceRefresh: boolean = false): Promise<string> {
    if (PreferenceUtil.getBool('role')) {
      const key: string = 'exam_' + semCode;
      return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
        return this.getExamYjspt(semCode);
      }, 5 * 60 * 1000, forceRefresh);
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
    }, 5 * 60 * 1000, forceRefresh);
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
    // 同 ScoreService：取 rows 前先校验 extParams.code（Flutter exam_session 直接取 datas.wdksxxcx.rows，
    // 但响应异常时 rows 会缺失，此处补校验 + 空值防护，避免 TypeError 冒到页面上）。
    assertExtParamsOk(examResp.body);
    const datas: Record<string, Object> = data['datas'] as Record<string, Object>;
    const wdksRaw: Object | undefined = datas ? datas['wdksxxcx'] : undefined;
    if (!wdksRaw) {
      throw new EhallDataError('考试接口返回格式异常（缺少 wdksxxcx）');
    }
    const wdks: Record<string, Object> = wdksRaw as Record<string, Object>;
    const rowsRaw: Object | undefined = wdks['rows'];
    const rows: Object[] = (rowsRaw ? rowsRaw : []) as Object[];
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
