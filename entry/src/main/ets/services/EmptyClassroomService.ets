// EmptyClassroomService.ets — 空闲教室数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { EmptyClassroomItem, BuildingInfo, BuildingRow, EmptyClassroomRow,
         EHALL_APP_EMPTY_CLASSROOM } from './Models';
import { EHALL_HEADERS, findAppIdByPath, extractRaw } from './EhallConstants';
import { SemesterUtil } from './EhallService';

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

  private async activateAppSession(appId: string): Promise<void> {
    if (this.appSessionUrl[appId]) {
      console.info(TAG, 'activateAppSession: using cached for ' + appId);
      return;
    }

    const appPath = '/jwapp/sys/kxjas';
    this.appSessionUrl[appId] = appPath;

    const cookiesBefore = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (cookiesBefore.toLowerCase().includes('jsessionid')) {
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
      const appId = findAppIdByPath(path);
      if (appId) {
        console.info(TAG, 'appPost: retrying with re-activation for ' + appId);
        await this.activateAppSession(appId);
        resp = await this.http.postForm(url, body, EHALL_HEADERS);
        console.info(TAG, 'appPost: retry resp=' + resp.statusCode);
      }
    }

    if (resp.body.trimStart().startsWith('<!') || resp.body.trimStart().startsWith('<html')) {
      console.warn(TAG, 'appPost: received HTML instead of JSON, body[0:200]=' + resp.body.substring(0, 200));
      this.appSessionUrl = {};
      const appId = findAppIdByPath(path);
      if (appId) {
        console.info(TAG, 'appPost: retrying with re-activation for ' + appId);
        await this.activateAppSession(appId);
        resp = await this.http.postForm(url, body, EHALL_HEADERS);
        console.info(TAG, 'appPost: retry resp=' + resp.statusCode);
      }
    }

    return resp;
  }

  async getEmptyClassroomBuildings(): Promise<BuildingInfo[]> {
    await this.init();
    return this.cache.getOrFetch<BuildingInfo[]>('er_buildings', async (): Promise<BuildingInfo[]> => {
      await this.activateAppSession('4768402106681759');
      const resp = await this.http.get(
        'https://ehall.xidian.edu.cn/jwapp/sys/kxjas/modules/kxjas/jxlcx.do?*order=%2BXXXQDM%2C%2BPX%2C%2BJXLDM',
        EHALL_HEADERS
      );
      console.info(TAG, 'getEmptyClassroomBuildings: resp=' + resp.statusCode);
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
    }, 60 * 60 * 1000);
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

      console.info(TAG, 'searchEmptyClassrooms: ZC=' + zc + ' XQJ=' + xqj + ' date=' + dateStr);

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
    const resp1 = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/rqzhzcjc.do', {
      'RQ': dateStr,
      'XN': semParts[0] + '-' + semParts[1],
      'XQ': semParts[2],
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

    console.info(TAG, `searchEmptyClassroomsByDate: ${dateStr} ZC=${zc} XQJ=${xqj}`);

    const querySetting = JSON.stringify([
      { name: 'JXLDM', caption: '教学楼代码', builder: 'equal', linkOpt: 'AND', value: buildingCode },
      { name: 'ZC', value: zc, linkOpt: 'AND', builder: 'equal' },
      { name: 'XQJ', value: xqj, linkOpt: 'AND', builder: 'equal' },
    ]);
    const resp = await this.appPost('/jwapp/sys/kxjas/modules/kxjas/cxjsqk.do', {
      'XNXQDM': semCode,
      'ZC': zc,
      'XQ': xqj,
      'querySetting': querySetting,
      '*order': '+LC,+JASMC',
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
    console.info(TAG, 'extractEmptyClassrooms: rows count=' + rows.length);
    for (const row of rows) {
      const r: EmptyClassroomRow = row as EmptyClassroomRow;
      const rawName = r.JASMC || '';
      const roomName = rawName.replace(/[（(].*?[)）]/, '').trim();
      const u1 = r.JC1 || ''; const u2 = r.JC2 || ''; const u3 = r.JC3 || '';
      const u4 = r.JC4 || ''; const u5 = r.JC5 || ''; const u6 = r.JC6 || '';
      const u7 = r.JC7 || ''; const u8 = r.JC8 || ''; const u9 = r.JC9 || '';
      const u10 = r.JC10 || ''; const u11 = r.JC11 || '';

      if (out.length === 0) {
        console.info(TAG, 'extractEmptyClassrooms: first row JASMC=' + rawName +
          ' JC1=[' + u1 + '] JC2=[' + u2 + '] JC3=[' + u3 + ']');
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
