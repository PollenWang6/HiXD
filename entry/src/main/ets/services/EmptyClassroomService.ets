// EmptyClassroomService.ets — 空闲教室数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { EmptyClassroomItem, BuildingInfo, BuildingRow, EmptyClassroomRow,
         EHALL_APP_EMPTY_CLASSROOM } from './Models';
import { EHALL_HEADERS, extractRaw, sharedAppPost, AppPostContext } from './EhallConstants';
import { SemesterUtil } from './EhallService';
import { CasLoginService } from './CasLoginService';

const TAG = 'EmptyClassroomService';

interface ZcXqjData { ZC: object; XQJ: object; }

export class EmptyClassroomService {
  private static inst: EmptyClassroomService;
  private http = HttpUtil.getInstance();
  private cache = CacheService.getInstance();
  private appSessionUrl: Record<string, string> = {};

  constructor() {}

  static getInstance(): EmptyClassroomService {
    if (!EmptyClassroomService.inst) EmptyClassroomService.inst = new EmptyClassroomService();
    return EmptyClassroomService.inst;
  }

  private async init(): Promise<void> { await this.cache.init(); }

  static extractRaw(body: string): object[] { return extractRaw(body, TAG); }

  private async activateAppSession(appId: string, _force: boolean = false): Promise<void> {
    const appPath = '/jwapp/sys/kxjas';

    // 已激活且非强制：直接复用，省一次网络
    if (!_force && this.appSessionUrl[appId]) {
      return;
    }
    const cookiesBefore = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    // 非强制且已有 jsessionid：认为可用，跳过（陈旧 jsessionid 仅在强制/失败时才会被下方刷新）
    if (!_force && cookiesBefore.toLowerCase().includes('jsessionid')) {
      this.appSessionUrl[appId] = appPath;
      return;
    }

    // 需要（重新）建立会话：先确保 CAS 登录态有效（根因修复——陈旧 jsessionid 不会自动触发重登，
    // 必须由此处主动刷新 MOD_AUTH_CAS，否则后续 appShow 重定向无法签发新的 jsessionid）
    try { await CasLoginService.getInstance().checkAndAutoLogin(); } catch (e) { /* 忽略，继续尝试 */ }

    try {
      const resp = await this.http.get(
        'https://ehall.xidian.edu.cn/appShow?appId=' + appId,
        EHALL_HEADERS
      );
    } catch (e) {
    }

    const cookiesAfter1 = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (cookiesAfter1.toLowerCase().includes('jsessionid')) {
      this.appSessionUrl[appId] = appPath;
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
    const hasJsession = cookiesFinal.toLowerCase().includes('jsessionid');
    if (hasJsession) {
      this.appSessionUrl[appId] = appPath;
    } else {
      throw new Error('空教室服务暂不可用，请先完成登录后重试');
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

  async getEmptyClassroomBuildings(forceRefresh?: boolean): Promise<BuildingInfo[]> {
    await this.init();
    return this.cache.getOrFetch<BuildingInfo[]>('er_buildings', async (): Promise<BuildingInfo[]> => {
      const resp = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/jxlcx.do', {
        '*order': '+XXXQDM,+PX,+JXLDM',
      });
      const raw: object[] = EmptyClassroomService.extractRaw(resp.body);
      const out: BuildingInfo[] = [];
      for (const row of raw) {
        const r: BuildingRow = row as BuildingRow;
        const code = r.JXLDM || '';
        if (code !== '') {
          out.push({ code: code, name: r.JXLJC || r.JXLMC || '未知' });
        }
      }
      return out;
    }, 60 * 60 * 1000, forceRefresh);
  }

  async searchEmptyClassrooms(
    buildingCode: string,
    weekRange: string,
    weekPart: string,
    week: number,
    day: number
  ): Promise<string> {
    await this.init();
    const key = 'er_' + buildingCode + '_' + weekRange + '_' + weekPart + '_' + week + '_' + day;
    return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
      await this.activateAppSession('4768402106681759');

      const dateStr = this.calcSemesterDate(weekRange, weekPart, week, day);
      const resp1 = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/rqzhzcjc.do', {
        'RQ': dateStr,
        'XN': weekRange,
        'XQ': weekPart,
      });
      let zc = String(week);
      let xqj = String(day);
      try {
        const obj = JSON.parse(resp1.body) as Record<string, object>;
        const datas = obj['datas'];
        if (datas !== undefined && datas !== null) {
          const dmap = datas as Record<string, object>;
          const rqdata = dmap['rqzhzcjc'];
          if (rqdata !== undefined && rqdata !== null) {
            const rqmap: ZcXqjData = rqdata as ZcXqjData;
            const zcRaw = rqmap.ZC;
            const xqjRaw = rqmap.XQJ;
            if (zcRaw !== undefined && zcRaw !== null) { zc = String(zcRaw); }
            if (xqjRaw !== undefined && xqjRaw !== null) { xqj = String(xqjRaw); }
          }
        }
      } catch { /* fallback */ }


      const querySetting = JSON.stringify([
        { name: 'JXLDM', caption: '教学楼代码', builder: 'equal', linkOpt: 'AND', value: buildingCode },
        { name: 'XNXQDM', value: weekRange + '-' + weekPart, linkOpt: 'AND', builder: 'equal' },
        { name: 'ZC', value: zc, linkOpt: 'AND', builder: 'equal' },
        { name: 'XQJ', value: xqj, linkOpt: 'AND', builder: 'equal' },
      ]);
      const resp2 = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/cxjsqk.do', {
        'XNXQDM': weekRange + '-' + weekPart,
        'ZC': zc,
        'XQ': xqj,
        'querySetting': querySetting,
        '*order': '+LC,+JASMC',
        'pageSize': '999',
        'pageNumber': '1',
      });
      return resp2.body;
    }, 10 * 60 * 1000);
  }

  async searchEmptyClassroomsByDate(buildingCode: string, date: Date): Promise<string> {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    const dateStr = y + '-' + m + '-' + d;

    const semCode = SemesterUtil.getCurrentSemesterCode();
    const semParts = semCode.split('-');
    const xn = semParts[0] + '-' + semParts[1];
    const xq = semParts[2];
    const xnxqdm = xn + '-' + xq;

    // 1) 用日期换周次 / 星期
    const resp1 = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/rqzhzcjc.do', {
      'RQ': dateStr,
      'XN': xn,
      'XQ': xq,
    });
    let zc = '';
    let xqj = '';
    try {
      const obj = JSON.parse(resp1.body) as Record<string, object>;
      const datas = obj['datas'] as Record<string, object> | undefined;
      if (datas) {
        const rqdata = datas['rqzhzcjc'] as Record<string, object> | undefined;
        if (rqdata) {
          zc = String(rqdata['ZC'] ?? '');
          xqj = String(rqdata['XQJ'] ?? '');
        }
      }
    } catch { /* fallback */ }

    // 2) 查询空闲教室（必须带上 querySetting 等参数，否则服务端收不到过滤条件）
    const querySetting = JSON.stringify([
      { name: 'JXLDM', caption: '教学楼代码', builder: 'equal', linkOpt: 'AND', value: buildingCode },
      { name: 'XNXQDM', value: xnxqdm, linkOpt: 'AND', builder: 'equal' },
      { name: 'ZC', value: zc, linkOpt: 'AND', builder: 'equal' },
      { name: 'XQJ', value: xqj, linkOpt: 'AND', builder: 'equal' },
    ]);
    const resp = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/cxjsqk.do', {
      'XNXQDM': xnxqdm,
      'ZC': zc,
      'XQ': xqj,
      'querySetting': querySetting,
      '*order': '+LC,+JASMC',
      'pageSize': '999',
      'pageNumber': '1',
    });
    return resp.body;
  }

  private calcSemesterDate(semYear: string, semPart: string, week: number, day: number): string {
    const swift: number = PreferenceUtil.getNumber('week_swift', 0);
    const startDate = SemesterUtil.getSemesterStartDate(semYear, semPart);
    const dayMs = 24 * 60 * 60 * 1000;
    const target = new Date(startDate.getTime() + (week - 1 - swift) * 7 * dayMs + (day - 1) * dayMs);
    const y = target.getFullYear();
    const m = String(target.getMonth() + 1).padStart(2, '0');
    const d = String(target.getDate()).padStart(2, '0');
    return y + '-' + m + '-' + d;
  }

  static extractEmptyClassrooms(body: string): EmptyClassroomItem[] {
    const out: EmptyClassroomItem[] = [];
    const rows = EmptyClassroomService.extractRaw(body);
    for (const row of rows) {
      const r: EmptyClassroomRow = row as EmptyClassroomRow;
      const rawName = r.JASMC || '';
      const roomName = rawName.replace(/[（(].*?[)）]/, '').trim();
      const u1 = r.JC1 || ''; const u2 = r.JC2 || ''; const u3 = r.JC3 || '';
      const u4 = r.JC4 || ''; const u5 = r.JC5 || ''; const u6 = r.JC6 || '';
      const u7 = r.JC7 || ''; const u8 = r.JC8 || ''; const u9 = r.JC9 || '';
      const u10 = r.JC10 || ''; const u11 = r.JC11 || '';

      if (out.length === 0) {
      }

      const isUsed: boolean[] = [
        !u1.includes('1_'), !u2.includes('1_'), !u3.includes('1_'),
        !u4.includes('1_'), !u5.includes('1_'), !u6.includes('1_'),
        !u7.includes('1_'), !u8.includes('1_'), !u9.includes('1_'),
        !u10.includes('1_'), !u11.includes('1_')
      ];
      out.push({
        name: roomName,
        buildingCode: r.JXLDM || '',
        roomName: rawName,
        floor: r.LC || '',
        isUsed: isUsed,
      });
    }
    return out;
  }
}
