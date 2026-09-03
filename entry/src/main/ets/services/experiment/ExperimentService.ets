// ExperimentService.ets — sysj 实验系统服务（从 EhallService 独立）
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';

const TAG = 'ExperimentService';
const SYSJ_BASE = 'https://sysj.xidian.edu.cn';
const WLSY_BASE = 'http://wlsy.xidian.edu.cn';
const TERM_ID = '2003';
const MAX_WEEKS = 25;

export class ExperimentService {
  private static inst: ExperimentService;
  private http = HttpUtil.getInstance();

  constructor() {}

  static getInstance(): ExperimentService {
    if (!ExperimentService.inst) ExperimentService.inst = new ExperimentService();
    return ExperimentService.inst;
  }

  // ===== 预加载实验数据（供 EhallService.preloadAllData 调用）=====

  async preloadDirect(): Promise<number> {

    try {
      const r0: HttpResponse = await this.http.get(
        SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=1'
      );
      let allItems: Record<string, string>[] = [];

      if (r0.isOk && r0.body.length > 0 && r0.body.charAt(0) === '[') {
        this._parseWeekData(r0.body, 1, allItems);
        for (let w = 2; w <= MAX_WEEKS; w++) {
          try {
            const rw = await this.http.get(
              SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=' + String(w)
            );
            this._parseWeekData(rw.body, w, allItems);
          } catch (_e) { /* continue */ }
        }
      } else {
        allItems = await this._fetchWithOAuth();
      }

      if (allItems.length > 0) {
        const co: ESObject = { 'ts': Date.now(), 'data': allItems } as ESObject;
        PreferenceUtil.putString('sysj_exp_cache', JSON.stringify(co));
        return allItems.length;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  private async _fetchWithOAuth(): Promise<Record<string, string>[]> {
    let state = '';
    const r1 = await this.http.get(SYSJ_BASE + '/xidian/test');
    let om = r1.body?.match(/[?&]state=([a-f0-9\-]{20,50})/i);
    if (om) { state = om[1]; }

    if (!state) {
      for (let a = 0; a < 4; a++) {
        const sr = await this.http.getNoRedirect(SYSJ_BASE + '/xidian/test');
        if (sr.location) {
          let om2 = sr.location.match(/[?&]state=([^&]+)/);
          if (om2) { state = om2[1]; break; }
          let nextUrl = sr.location;
          if (!nextUrl.startsWith('http')) { nextUrl = SYSJ_BASE + (nextUrl.startsWith('/') ? nextUrl : '/' + nextUrl); }
          const sr2 = await this.http.getNoRedirect(nextUrl);
          if (sr2.location) {
            let om3 = sr2.location.match(/[?&]state=([^&]+)/);
            if (om3) { state = om3[1]; break; }
          }
        }
        if (sr.body) {
          let om4 = sr.body.match(/state=([a-f0-9\-]{20,50})/i);
          if (om4) { state = om4[1]; break; }
        }
      }
    }
    if (!state) {
      return [];
    }

    const params = 'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
      '&state=' + state + '&client_id=GvsunLims&response_type=code' +
      '&authorize_uri=' + encodeURIComponent(SYSJ_BASE + '/uaa/oauth/authorize');
    await this.http.get(SYSJ_BASE + '/uaa/xidian/login?' + params);

    const idsBackup = this.http.getAllCookies('ids.xidian.edu.cn');
    const ehallBackup = this.http.getAllCookies('ehall.xidian.edu.cn');
    const casUrl = 'https://ids.xidian.edu.cn/authserver/oauth2.0/authorize?' +
      'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/uaa/xidian/callback') +
      '&response_type=code&state=' + state + '&client_id=1387116615722893312';
    const r3 = await this.http.get(casUrl);
    if (r3.body && r3.body.indexOf('password') >= 0 && r3.body.indexOf('username') >= 0 && r3.body.indexOf('<form') >= 0) {
      return [];
    }
    this.http.copyCookiesForDomain('ids.xidian.edu.cn', 'sysj.xidian.edu.cn');
    this.http.replaceCookiesForDomain('ids.xidian.edu.cn', idsBackup);
    this.http.replaceCookiesForDomain('ehall.xidian.edu.cn', ehallBackup);

    let pwd = '';
    let pm = r3.body?.match(/var password = '([^']+)'/);
    if (pm) { pwd = pm[1]; }

    if (!pwd) {
      const oauthUrl = SYSJ_BASE + '/uaa/oauth/authorize?' +
        'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
        '&state=' + state + '&client_id=GvsunLims&response_type=code';
      const r4 = await this.http.get(oauthUrl);
      let code = '';
      let cm4 = r4.body?.match(/[?&]code=([a-zA-Z0-9]+)/);
      if (!cm4) { cm4 = r4.body?.match(/["']code["']\s*:\s*["']([^"']+)["']/); }
      if (!cm4) { cm4 = r4.body?.match(/window\.location.*?[?&]code=([a-zA-Z0-9]+)/); }
      if (!cm4) { cm4 = r4.body?.match(/url=.*?[?&]code=([a-zA-Z0-9]+)/); }
      if (cm4) { code = cm4[1]; }

      if (code) {
        const r5 = await this.http.get(SYSJ_BASE + '/xidian/webapp/callback?code=' + code + '&state=' + state);
        let pm2 = r5.body?.match(/var password = '([^']+)'/);
        if (pm2) { pwd = pm2[1]; }
        if (!pwd) { pm2 = r3.body?.match(/var password = '([^']+)'/); if (pm2) { pwd = pm2[1]; } }
      }
    }

    if (!pwd) {
      return [];
    }

    const account = PreferenceUtil.getString('ids_account');
    const loginBody = 'username=' + encodeURIComponent(account) + '&password=' + encodeURIComponent(pwd);
    await this.http.postRaw(SYSJ_BASE + '/xidian/webapp/login', loginBody, 'application/x-www-form-urlencoded');

    const allItems: Record<string, string>[] = [];
    for (let w = 1; w <= MAX_WEEKS; w++) {
      try {
        const rw = await this.http.get(
          SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=' + String(w)
        );
        this._parseWeekData(rw.body, w, allItems);
      } catch (_e) { /* continue */ }
    }
    return allItems;
  }

  /**
   * 解析 wlsy 物理实验 select.aspx 的 HTML 表格（统一入口）。
   * ⚠️ ExperimentPage 与 ClassTablePage 曾各自实现解析（parsePhysicsHtml /
   * parsePhysicsToItems），导致残缺版本覆写共享缓存 physics_exp_cache。
   * 本方法是唯一解析器，两个页面必须调用它，禁止另写解析逻辑。
   * 字段语义（td 下标来自 select.aspx 表格）：tds[1]=实验名、tds[3]=节次(含15为下午场)、
   * tds[4]=日期 MM/dd/yyyy、tds[5]=实验室、tds[8]=实验项目、tds[9]=教师。
   * 时间映射与 Flutter 一致：下午场=第7-9节(15:55起)，晚场=第9-11节(19:00起)。
   * @param html select.aspx 页面 HTML
   * @param semesterStartTs 学期开始日期毫秒时间戳；>0 时推算 week，否则 week='0'
   *                        （避免 ExperimentService 反向依赖 EhallService.SemesterUtil）
   */
  static parsePhysicsHtml(html: string, semesterStartTs: number = 0): Record<string, string>[] {
    const items: Record<string, string>[] = [];
    const trs = html.match(/<tr[^>]*>[\s\S]*?<\/tr>/gi);
    if (!trs) return items;
    for (let tr of trs) {
      const tds: string[] = [];
      let tm: RegExpExecArray | null;
      const tr2: RegExp = new RegExp(/<td[^>]*>([\s\S]*?)<\/td>/gi);
      while ((tm = tr2.exec(tr)) !== null) {
        tds.push(tm[1].replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').trim());
      }
      if (tds.length < 10 || tds[1].length === 0) continue;
      const dp = (tds[4] || '').split('/');
      const isPM = (tds[3] || '').includes('15');
      const it: Record<string, string> = {
        'courseCode': '',
        'experimentName': '⚛ ' + tds[1],
        'department': '',
        'lab': tds[5] || '',
        'weekday': '0',
        'startSection': isPM ? '7' : '9',
        'endSection': isPM ? '9' : '11',
        'week': '0',
        'teacher': tds[9] || '',
        'className': '',
        'groupId': '',
        'studentCount': '',
        'experimentProject': tds[8] || ''
      };
      if (dp.length >= 3) {
        const dt = new Date(parseInt(dp[2]), parseInt(dp[0]) - 1, parseInt(dp[1]));
        it['weekday'] = String(dt.getDay() === 0 ? 7 : dt.getDay());
        if (semesterStartTs > 0) {
          it['week'] = String(Math.floor((dt.getTime() - semesterStartTs) / 86400000 / 7) + 1);
        }
      }
      items.push(it);
    }
    return items;
  }

  /**
   * 提取 wlsy 登录失败页 login1_Label1 错误文案（对齐 Flutter LoginFailedException）。
   * ASP.NET Login 控件在账号/密码错误时以 200 重渲染登录页，错误文本放在
   * <span id="login1_Label1"><font color="Red">…</font></span> 中。
   * 剥离 <font color="Red"> / </font> / <br> 后得到纯文本（如"学号或密码错误！"）。
   */
  static extractPhysicsLoginError(html: string): string {
    let text: string = '';
    if (html && html.length > 0) {
      const m: RegExpMatchArray | null = html.match(/id="login1_Label1"[^>]*>([\s\S]*?)<\/span>/i);
      if (m && m.length > 1 && m[1] !== undefined && m[1] !== null) {
        const raw: string = m[1] as string;
        text = raw.replace(/<font[^>]*>/gi, '')
          .replace(/<\/font>/gi, '')
          .replace(/<br\s*\/?>/gi, '。')
          .replace(/<[^>]+>/g, '')
          .replace(/&nbsp;/g, ' ')
          .trim();
      }
    }
    return text.length > 0 ? text : '物理实验系统登录失败（学号或密码错误）';
  }

  /**
   * wlsy 物理实验：登录并抓取 select.aspx 课表页 HTML（ExperimentPage / ClassTablePage 共用，
   * 避免两处各自 postRaw 把失败响应当成功、再各自解析漂移）。
   * ASP.NET PRG 语义（对齐 Flutter dio followRedirects=false）：登录成功 = POST default.aspx
   * 返回 302；失败 = 200 重渲染登录页（含 login1_Label1 错误标签）。
   * 用 postNoRedirect 保留首跳状态码：非 302 直接抛带原始文案的 Error，页面无需再猜原因。
   * @param account 统一认证账号（学号）
   * @param pwd 物理实验独立密码
   * @returns select.aspx 页面 HTML；登录失败抛 Error（消息即 login1_Label1 文案）
   */
  static async physicsFetchScheduleHtml(account: string, pwd: string): Promise<string> {
    const http: HttpUtil = HttpUtil.getInstance();
    const bd: string = '__EVENTTARGET=&__EVENTARGUMENT=&__VIEWSTATE=%2FwEPDwUKMTEzNzM0MjM0OWQYAQUeX19Db250cm9sc1JlcXVpcmVQb3N0QmFja0tleV9fFgEFD2xvZ2luMSRidG5Mb2dpbkOuzGVaztce4Ict7jsIJ0F5pUDb%2BsmSbCCrNVSBlPML&__VIEWSTATEGENERATOR=EE008CD9&__EVENTVALIDATION=%2FwEdAAcKecdPGDB%2BfW8Tyghx7AeSpOzeiNZ7aaEg5p6LqSa9cODI2bZwNtRxUKPkisVLf8l8Vv4WhRVIIhZlyYNJO%2BySrDKOhP%2B%2FYMNbVIh74hA2rCYnBBSTsX9SjxiYNNk%2B5kglM%2B6pGIq22Oi5mNu6u6eC2WEBfKAmATKwSpsOL%2FPNcRyi9l8Dnp6JamksyAzjhW4%3D&login1%24StuLoginID=' + encodeURIComponent(account) + '&login1%24StuPassword=' + encodeURIComponent(pwd) + '&login1%24UserRole=Student&login1%24btnLogin.x=28&login1%24btnLogin.y=14';
    const formHeaders: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    const lr: HttpResponse = await http.postNoRedirect(WLSY_BASE + '/PhyEws/default.aspx', bd, formHeaders);
    const sc: number = lr ? lr.statusCode : 0;
    if (sc < 300 || sc >= 400) {
      // 非 302 = 登录失败（200 重渲染登录页），把服务器原始错误透给用户
      throw new Error(ExperimentService.extractPhysicsLoginError(lr ? lr.body : ''));
    }
    // 登录成功：会话 cookie 已按域（wlsy.xidian.edu.cn）保存，直接抓课表页
    const r: HttpResponse = await http.get(WLSY_BASE + '/PhyEws/student/select.aspx');
    if (!r.isOk) {
      throw new Error('物理实验课表页请求失败（HTTP ' + String(r.statusCode) + '）');
    }
    // 兜底：若 302 种下的会话未生效、select.aspx 仍弹回登录页（body 含错误标签），同样给精准提示
    if (r.body && r.body.indexOf('login1_Label1') >= 0) {
      throw new Error(ExperimentService.extractPhysicsLoginError(r.body));
    }
    return r.body;
  }

  private _parseWeekData(body: string, week: number, out: Record<string, string>[]): void {
    try {
      if (body.length === 0 || body.charAt(0) !== '[') return;
      const raw: Object[] = JSON.parse(body) as Object[];
      for (const d of raw) {
        const row: Object[] = d as Object[];
        if (row.length < 15) continue;
        const item: Record<string, string> = {};
        item['courseCode'] = (row[0] as string) || '';
        item['experimentName'] = (row[1] as string) || '';
        item['department'] = (row[2] as string) || '';
        item['lab'] = (row[11] as string) || '';
        item['weekday'] = (row[4] as string) || '';
        item['startSection'] = (row[5] as string) || '';
        item['endSection'] = (row[6] as string) || '';
        item['week'] = (row[7] as string) || '';
        item['teacher'] = (row[9] as string) || '';
        item['className'] = (row[12] as string) || '';
        item['groupId'] = (row[12] as string) || '';
        item['studentCount'] = (row[13] as string) || '';
        item['experimentProject'] = (row[14] as string) || '';
        item['__week'] = String(week);
        out.push(item);
      }
    } catch (_e) { /* non-critical */ }
  }
}
