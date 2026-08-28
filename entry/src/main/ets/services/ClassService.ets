// ClassService.ets — 课程表数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';
import { ClassItemModel, ClassTableRow, UnscheduledCourse, ClassChange, SerializedClassRow, ClassTableRawWrapper, EHALL_APP_CLASS_TABLE } from './Models';
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
        // （关键修复：原实现只 GET，缺这步导致本科生 dqxnxq.do 返回 401）
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
      }

      const body: Record<string, string> = { 'XNXQDM': semCode };
      if (sid && sid.length > 0) {
        body['XH'] = sid;
      }

      const resp = await this.appPost(
        '/jwapp/sys/wdkb/modules/xskcb/xskcb.do',
        body
      );
      if (!resp.isOk) {
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

  // 研究生未排课列表（yjspt：已选课但尚未排入课表），对齐 Flutter getYjspt 的 notArranged（xswsckbkc.do）
  async getUnscheduledCoursesYjspt(semCode: string, sid: string): Promise<string> {
    const cas = CasLoginService.getInstance();
    const http = HttpUtil.getInstance();
    await cas.navigateToYjspt(
      'https://yjspt.xidian.edu.cn/gsapp/sys/wdkbapp/*default/index.do#/xskcb');
    const body: Record<string, string> = { 'XNXQDM': semCode, 'XH': sid };
    const resp: HttpResponse = await http.post(
      'https://yjspt.xidian.edu.cn/gsapp/sys/wdkbapp/modules/xskcb/xswsckbkc.do',
      body
    );
    return resp.body;
  }

  // 解析研究生未排课列表（rows 仅含 KCMC/KCDM，无时间地点，符合"未排"语义）
  static parseUnscheduledCoursesYjspt(body: string): UnscheduledCourse[] {
    const out: UnscheduledCourse[] = [];
    try {
      const obj: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const datas: Record<string, Object> = obj['datas'] as Record<string, Object>;
      const xswsckbkc: Record<string, Object> = datas['xswsckbkc'] as Record<string, Object>;
      const rows: Object[] = xswsckbkc['rows'] as Object[];
      if (!rows) return out;
      for (const r of rows) {
        const row: Record<string, Object> = r as Record<string, Object>;
        out.push({
          name: String(row['KCMC'] ?? ''),
          code: String(row['KCDM'] ?? ''),
          number: '',
          teacher: ''
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
          newTeacher: String(row['XSKJS'] ?? ''),
          // 合并网格用的原始字段
          rawOrigWeeks: origWeeks,
          rawNewWeeks: newWeeks,
          origDayNum: parseInt(origDayNum) || 0,
          newDayNum: parseInt(newDayNum) || 0,
          origStart: parseInt(String(row['KSJC'] ?? '0')) || 0,
          origEnd: parseInt(String(row['JSJC'] ?? '0')) || 0,
          newStart: parseInt(String(row['XKSJC'] ?? '0')) || 0,
          newEnd: parseInt(String(row['XJSJC'] ?? '0')) || 0
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
   * 研究生(yjspt)开学日：对齐 Flutter traintime_pda 的 getYjspt ——
   * 用 queryRcap.do 取"当前周"，反推第1周周一作为 termStartDay。
   * （cxjcs.do 对研究生不适用，故研究生不走该接口，改用此反推法。）
   * 返回 'yyyy-MM-dd'；取不到返回 null。同时缓存 yjspt_current_week 供课表复用。
   */
  async getYjsptTermStartDay(): Promise<string | null> {
    try {
      const cas = CasLoginService.getInstance();
      const http = HttpUtil.getInstance();
      await cas.navigateToYjspt(
        'https://yjspt.xidian.edu.cn/gsapp/sys/wdkbapp/*default/index.do#/xskcb');
      const now: Date = new Date();
      const dayStr: string = String(now.getFullYear()) +
        String(now.getMonth() + 1).padStart(2, '0') +
        String(now.getDate()).padStart(2, '0');
      const weekBody: Record<string, string> = { 'day': dayStr };
      const weekResp: HttpResponse = await http.post(
        'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/portal/queryRcap.do',
        weekBody);
      const weekData: Record<string, Object> = weekResp.json<Record<string, Object>>();
      let currentWeek: number = 1;
      if (weekData['xnxq'] !== undefined && weekData['xnxq'] !== null) {
        const match: RegExpMatchArray | null = String(weekData['xnxq']).match(/[0-9]+/);
        if (match) { currentWeek = parseInt(match[0]) || 1; }
      }
      PreferenceUtil.putNumber('yjspt_current_week', currentWeek);
      // 对齐 Flutter：weekDay = now.weekday - 1（周一=0）。JS getDay() 周日=0，故用 (getDay()+6)%7。
      const weekDayMon: number = (now.getDay() + 6) % 7;
      const offsetDays: number = (1 - currentWeek) * 7 - weekDayMon;
      const start: Date = new Date(now.getTime() + offsetDays * 86400000);
      const y: string = String(start.getFullYear());
      const m: string = String(start.getMonth() + 1).padStart(2, '0');
      const d: string = String(start.getDate()).padStart(2, '0');
      return y + '-' + m + '-' + d;
    } catch (e) {
      return null;
    }
  }

  /**
   * 从 ehall API 获取学期开学日期
   */
  async getSemesterStartDateFromApi(semCode: string): Promise<string | null> {
    try {
      await this.init();
      await this.activateAppSession(EHALL_APP_CLASS_TABLE);
      const parts: string[] = semCode.split('-');
      const xn: string = parts[0] + '-' + parts[1];
      const xq: string = parts[2];
      const body: Record<string, string> = {'XN': xn, 'XQ': xq};
      const resp: HttpResponse = await this.appPost(
        '/jwapp/sys/wdkb/modules/jshkcb/cxjcs.do', body);
      const data: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      const datas: Record<string, Object> = data['datas'] as Record<string, Object>;
      const cxjcs: Record<string, Object> = datas['cxjcs'] as Record<string, Object>;
      const rows: Object[] = cxjcs['rows'] as Object[];
      if (rows.length > 0) {
        // 优先匹配 XN+XQ 都一致的那一行（cxjcs 可能返回多学期，rows[0] 未必是当前学期）
        for (let i = 0; i < rows.length; i++) {
          const r: Record<string, Object> = rows[i] as Record<string, Object>;
          const rXn: string = String(r['XN'] ?? '');
          const rXq: string = String(r['XQ'] ?? '');
          if (rXn === xn && rXq === xq) {
            const date: string = String(r['XQKSRQ'] ?? '');
          if (date.length >= 10) {
            return date;
          }
          }
        }
        // 回退：取首行
        const r0: Record<string, Object> = rows[0] as Record<string, Object>;
        const date: string = String(r0['XQKSRQ'] ?? '');
        return date;
      }
    } catch (e) {
    }
    return null;
  }

  /**
   * 从 ehall API 获取服务器认定的"当前学年学期"代码（dqxnxq.do）。
   * 对齐 Flutter traintime_pda 的 getSemesterInfoEhall：以学校服务器权威值而非本地日期推导作为"当前学期"。
   * 返回格式 YYYY-YYYY-N（如 2025-2026-1）；失败/未登录/结构异常返回 ''。
   */
  async getRemoteCurrentSemester(): Promise<string> {
    try {
      await this.init();
      await this.activateAppSession(EHALL_APP_CLASS_TABLE);
      const resp: HttpResponse = await this.appPost(
        '/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do', {});
      const data: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      const datas: Record<string, Object> = data['datas'] as Record<string, Object>;
      const dqxnxq: Record<string, Object> = datas['dqxnxq'] as Record<string, Object>;
      const rows: Object[] = dqxnxq['rows'] as Object[];
      if (rows.length > 0) {
        const dm: string = String((rows[0] as Record<string, Object>)['DM'] ?? '');
        const s: string = dm.trim();
        if (/^\d{4}-\d{4}-[123]$/.test(s)) return s;
        const m2: RegExpMatchArray | null = s.match(/^(\d{4})(\d{4})([123])$/);
        if (m2) return m2[1] + '-' + m2[2] + '-' + m2[3];
      }
    } catch (e) {
    }
    return '';
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

  /**
   * 把课程变更（调课/停课/补课）合并进课表原始 JSON，返回合并后的 raw（结构与入参一致，供 parseClassTable 读回）。
   * 对齐 Flutter traintime_pda classtable_session 的 applyChange 逻辑：
   *  - 调课：定位原格（课号+原星期+原起止节），整格改为新时间/教室/周次（缺新值则保留原值）
   *  - 停课：定位原格，把"原周次"对应的那几周位清零（只停那几周）
   *  - 补课：在原课程上新增一节（新时间/教室/周次），无匹配课程则新建
   * 仅作用于本科生（研究生 KCH 为空，无法可靠匹配，调用方已按 role 过滤不传变更）。
   */
  static applyClassChanges(raw: string, changesJson: string): string {
    const items: ClassItemModel[] = ClassService.parseClassTable(raw);
    const changes: ClassChange[] = ClassService.parseClassChanges(changesJson);
    if (changes.length === 0) return raw;
    // 深拷贝，避免污染原始 items
    const merged: ClassItemModel[] = items.map((it: ClassItemModel) => {
      const c: ClassItemModel = new ClassItemModel();
      c.kcm = it.kcm; c.kch = it.kch; c.kxh = it.kxh; c.skxq = it.skxq;
      c.skzc = it.skzc; c.ksjc = it.ksjc; c.jsjc = it.jsjc; c.skjs = it.skjs; c.jasmc = it.jasmc;
      return c;
    });
    for (const ch of changes) {
      if (ch.type === '补课') {
        // 新增一节：克隆匹配课程（或按名称），覆盖新槽位
        const base: ClassItemModel | undefined =
          merged.find((it) => it.kch === ch.courseCode) ||
          merged.find((it) => it.kcm === ch.courseName);
        const c: ClassItemModel = new ClassItemModel();
        if (base) {
          c.kcm = base.kcm; c.kch = base.kch; c.kxh = base.kxh;
          c.skjs = ch.newTeacher || base.skjs;
          c.jasmc = ch.newRoom || base.jasmc;
        } else {
          c.kcm = ch.courseName; c.kch = ch.courseCode; c.kxh = ch.classNumber;
          c.skjs = ch.newTeacher; c.jasmc = ch.newRoom;
        }
        c.skxq = ch.newDayNum > 0 ? String(ch.newDayNum) : String(ch.origDayNum);
        c.ksjc = ch.newStart > 0 ? String(ch.newStart) : String(ch.origStart);
        c.jsjc = ch.newEnd > 0 ? String(ch.newEnd) : String(ch.origEnd);
        c.skzc = ch.rawNewWeeks.length > 0 ? ch.rawNewWeeks : (base ? base.skzc : '');
        merged.push(c);
      } else if (ch.type === '调课') {
        let idx: number = merged.findIndex((it) =>
          it.kch === ch.courseCode &&
          it.skxq === String(ch.origDayNum) &&
          it.ksjc === String(ch.origStart) &&
          it.jsjc === String(ch.origEnd));
        if (idx < 0) idx = merged.findIndex((it) => it.kch === ch.courseCode);
        if (idx >= 0) {
          const it: ClassItemModel = merged[idx];
          if (ch.newDayNum > 0) it.skxq = String(ch.newDayNum);
          if (ch.newStart > 0) it.ksjc = String(ch.newStart);
          if (ch.newEnd > 0) it.jsjc = String(ch.newEnd);
          if (ch.rawNewWeeks.length > 0) it.skzc = ch.rawNewWeeks;
          if (ch.newRoom) it.jasmc = ch.newRoom;
          if (ch.newTeacher) it.skjs = ch.newTeacher;
        }
      } else if (ch.type === '停课') {
        for (const it of merged) {
          if (it.kch === ch.courseCode &&
            it.skxq === String(ch.origDayNum) &&
            it.ksjc === String(ch.origStart) &&
            it.jsjc === String(ch.origEnd)) {
            it.skzc = ClassService.clearWeeks(it.skzc, ch.rawOrigWeeks);
          }
        }
      }
    }
    // 重新序列化为 extractRaw 可读结构（datas.xskcb.rows），用具名接口避免 ArkTS 未类型化字面量报错
    const rows: SerializedClassRow[] = merged.map((it: ClassItemModel): SerializedClassRow => ({
      KCM: it.kcm, KCH: it.kch, KXH: it.kxh, SKXQ: it.skxq,
      SKZC: it.skzc, KSJC: it.ksjc, JSJC: it.jsjc, SKJS: it.skjs, JASMC: it.jasmc
    }));
    const wrapper: ClassTableRawWrapper = { datas: { xskcb: { rows: rows } } };
    return JSON.stringify(wrapper);
  }

  // 把 origWeeks 中为 '1' 的周位在 skzc 中清零（对齐 Flutter：停课只停对应周）
  static clearWeeks(skzc: string, origWeeks: string): string {
    if (!origWeeks || origWeeks.length === 0) return skzc; // 无原周次信息则不误清
    const arr: string[] = skzc.split('');
    for (let i = 0; i < origWeeks.length; i++) {
      if (origWeeks[i] === '1' && i < arr.length) {
        arr[i] = '0';
      }
    }
    return arr.join('');
  }
}
