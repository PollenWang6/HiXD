// ExperimentService.ets — sysj 实验系统服务（从 EhallService 独立）
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { ExperimentType, ExperimentData, TimeRange, SYSJ_SECTION_TIMES } from './Models';

const TAG = 'ExperimentService';
const SYSJ_BASE = 'https://sysj.xidian.edu.cn';
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

  // ===== 工具方法 =====

  private async followRedirects(startUrl: string, maxSteps: number = 10): Promise<HttpResponse> {
    let currentUrl = startUrl;
    for (let i = 0; i < maxSteps; i++) {
      const resp = await this.http.getNoRedirect(currentUrl);
      if (!resp.isRedirect || !resp.location) {
        return resp;
      }
      let location = resp.location;
      if (location.startsWith('/')) {
        const idx = currentUrl.indexOf('/', 8);
        const base = idx > 0 ? currentUrl.substring(0, idx) : currentUrl;
        location = base + location;
      }
      currentUrl = location;
    }
    throw new Error('Too many redirects');
  }

  private getQueryParam(url: string, name: string): string {
    const mark = url.indexOf('?');
    if (mark < 0) return '';
    const query = url.substring(mark + 1);
    const pairs = query.split('&');
    for (const pair of pairs) {
      const eq = pair.indexOf('=');
      if (eq > 0 && pair.substring(0, eq) === name) {
        return decodeURIComponent(pair.substring(eq + 1));
      }
    }
    return '';
  }

  // ===== CAS TGC 获取 =====

  async getCasTgc(): Promise<string> {
    try {
      const serviceUrl = SYSJ_BASE + '/xidian/test';
      const casLoginUrl = 'https://cas.xidian.edu.cn/authserver/login?service=' +
        encodeURIComponent(serviceUrl);

      const loginPageResp = await this.http.get(casLoginUrl);
      const html = loginPageResp.body || '';

      const ltMatch = html.match(/name="lt"\s+value="([^"]*)"/);
      const executionMatch = html.match(/name="execution"\s+value="([^"]*)"/);
      const eventIdMatch = html.match(/name="_eventId"\s+value="([^"]*)"/);
      const lt = ltMatch ? ltMatch[1] : '';
      const execution = executionMatch ? executionMatch[1] : '';
      const eventId = eventIdMatch ? eventIdMatch[1] : 'submit';

      if (!lt || !execution) {
        throw new Error('getCasTgc: cannot parse CAS login form');
      }

      const username = PreferenceUtil.getString('login_username', '');
      const password = PreferenceUtil.getString('login_password', '');
      if (!username || !password) {
        throw new Error('getCasTgc: no stored credentials');
      }

      const postUrl = 'https://cas.xidian.edu.cn/authserver/login';
      const body = 'username=' + encodeURIComponent(username) +
        '&password=' + encodeURIComponent(password) +
        '<=' + encodeURIComponent(lt) +
        '&execution=' + encodeURIComponent(execution) +
        '&_eventId=' + encodeURIComponent(eventId) +
        '&submit=LOGIN';

      const casResp = await this.http.postNoRedirect(postUrl, body, {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': casLoginUrl,
      });

      const casCookies = this.http.getCookiesForDomain('cas.xidian.edu.cn');

      const tgcMatch = casCookies.match(/TGC=([^;\s]+)/);
      if (tgcMatch) {
        return tgcMatch[1];
      }

      let currentUrl = '';
      if (casResp.isRedirect && casResp.location) {
        currentUrl = casResp.location;
        if (currentUrl.startsWith('/')) {
          currentUrl = 'https://cas.xidian.edu.cn' + currentUrl;
        }
      }

      let hops = 0;
      while (currentUrl && hops < 10) {
        const redirResp = await this.http.getNoRedirect(currentUrl);

        const casCk = this.http.getCookiesForDomain('cas.xidian.edu.cn');
        const tgcM = casCk.match(/TGC=([^;\s]+)/);
        if (tgcM) {
          return tgcM[1];
        }

        if (redirResp.isRedirect && redirResp.location) {
          currentUrl = redirResp.location;
          if (currentUrl.startsWith('/')) {
            const protoEnd = currentUrl.indexOf('://');
            const afterProto = protoEnd >= 0 ? currentUrl.substring(protoEnd + 3) : currentUrl;
            const slashIdx = afterProto.indexOf('/');
            const host = slashIdx > 0 ? afterProto.substring(0, slashIdx) : afterProto;
            currentUrl = (protoEnd >= 0 ? currentUrl.substring(0, protoEnd + 3) : 'https://') + host + currentUrl;
          }
        } else {
          break;
        }
        hops++;
      }

      throw new Error('getCasTgc: TGC not found after redirect chain');
    } catch (e) {
      return '';
    }
  }

  // ===== sysj 登录 =====

  async loginToSysjWithTgc(tgc: string): Promise<boolean> {
    try {
      await this.http.injectCookies('TGC=' + tgc, 'cas.xidian.edu.cn');

      const resp1 = await this.http.getNoRedirect(SYSJ_BASE + '/xidian/test');

      if (!resp1.isRedirect || !resp1.location) {
        if (resp1.statusCode === 200) {
          return true;
        }
        throw new Error('sysj step1: no redirect, status=' + resp1.statusCode);
      }

      const state = this.getQueryParam(resp1.location, 'state');

      let currentUrl = resp1.location;
      if (currentUrl.startsWith('/')) {
        currentUrl = SYSJ_BASE + currentUrl;
      }

      const respAfterCas = await this.followRedirects(currentUrl, 12);

      let code = '';
      const finalBody = respAfterCas.body || '';
      const codeMatch = finalBody.match(/\?code=([^&"\s]+)/);
      if (codeMatch) {
        code = codeMatch[1];
      }
      if (!code && respAfterCas.isRedirect && respAfterCas.location) {
        code = this.getQueryParam(respAfterCas.location, 'code');
      }
      if (!code) {
        const urlCodeMatch = currentUrl.match(/[?&]code=([^&\s"]+)/);
        if (urlCodeMatch) code = urlCodeMatch[1];
      }

      if (!code && state) {
        const authorizeUrl = SYSJ_BASE + '/uaa/oauth/authorize?redirect_uri=' +
          encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
          '&state=' + state + '&client_id=GvsunLims&response_type=code';
        const respAuth = await this.http.get(authorizeUrl);
        const authBody = respAuth.body || '';
        const authCodeMatch = authBody.match(/\?code=([^&"\s]+)/);
        if (authCodeMatch) code = authCodeMatch[1];
        if (!code) {
          const callbackMatch = authBody.match(/callback\?code=([^&"\s']+)/);
          if (callbackMatch) code = callbackMatch[1];
        }
      }

      if (!code) {
        throw new Error('loginToSysjWithTgc: failed to extract code, finalUrl=' + currentUrl.substring(0, 200));
      }

      const callbackUrl = SYSJ_BASE + '/xidian/webapp/callback?code=' + code +
        (state ? '&state=' + state : '');
      const resp4 = await this.http.get(callbackUrl);
      const callbackBody = resp4.body || '';

      const pwdMatch = callbackBody.match(/var\s+password\s*=\s*'([^']*)'/);
      if (!pwdMatch) {
        return true;
      }
      const password = pwdMatch[1];

      const sid = await PreferenceUtil.getString('ids_account');
      if (!sid) {
        throw new Error('loginToSysjWithTgc: no ids_account, need to store it after CAS login');
      }
      const loginResp = await this.http.postRaw(
        SYSJ_BASE + '/xidian/webapp/login',
        'username=' + encodeURIComponent(sid) + '&password=' + encodeURIComponent(password),
        'application/x-www-form-urlencoded',
        { 'Content-Type': 'application/x-www-form-urlencoded' }
      );

      if (loginResp.statusCode === 200 && loginResp.body) {
        try {
          const loginResult = JSON.parse(loginResp.body) as Record<string, string | number | boolean | object>;
          if (loginResult['success'] === true || loginResult['code'] === 0) {
            return true;
          }
          return false;
        } catch (_) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // ===== HTML 解析 =====

  private parseSysjHtml(html: string, weekDates: string[]): ExperimentData[] {
    const experiments: ExperimentData[] = [];

    const cellRegex = /do-labReservation=['"](\d+),(\d+)['\"][^>]*>([\s\S]*?)<\/td>/g;
    let match: RegExpExecArray | null = null;

    const extractField = (cellHtml: string, marker: string): string => {
      const idx = cellHtml.indexOf(marker);
      if (idx < 0) return '';
      const after = cellHtml.substring(idx + marker.length);
      const endIdx = after.search(/<(?:br|\/div|span)/);
      const raw = endIdx > 0 ? after.substring(0, endIdx).trim() : after.trim();
      return raw.replace(/<[^>]+>/g, '').trim();
    };

    const courseMarker = html.indexOf('???student.timetable.course???') >= 0
      ? '???student.timetable.course???\uff1a'
      : '\u8BFE\u7A0B\uFF1A';
    const labMarker = html.indexOf('???schedule.course.lab???') >= 0
      ? '???schedule.course.lab???\uff1a'
      : '\u5B9E\u9A8C\u5BA4\uFF1A';
    const teacherMarker = html.indexOf('???student.timetable.teacher???') >= 0
      ? '???student.timetable.teacher???\uff1a'
      : '\u6559\u5E08\uFF1A';

    const expMap: Record<string, ExperimentData> = {};

    while ((match = cellRegex.exec(html)) !== null) {
      const weekDay = parseInt(match[1]);
      const classIndex = parseInt(match[2]);
      const cellHtml = match[3];

      const name = extractField(cellHtml, courseMarker);
      const classroom = extractField(cellHtml, labMarker);
      const teacher = extractField(cellHtml, teacherMarker);

      if (!name) continue;

      const dateStr = weekDates[weekDay - 1];
      if (!dateStr) continue;
      const startIdx = (classIndex - 1) * 2;
      const endIdx = startIdx + 1;
      const startTime = startIdx < SYSJ_SECTION_TIMES.length ? SYSJ_SECTION_TIMES[startIdx] : '08:30';
      const endTime = endIdx < SYSJ_SECTION_TIMES.length ? SYSJ_SECTION_TIMES[endIdx] : '09:15';

      const tr = new TimeRange();
      tr.startTime = dateStr + ' ' + startTime;
      tr.endTime = dateStr + ' ' + endTime;

      const key = name + '|' + classroom + '|' + teacher;
      if (expMap[key]) {
        expMap[key].timeRanges.push(tr);
      } else {
        const exp = new ExperimentData();
        exp.type = ExperimentType.OTHERS;
        exp.name = name;
        exp.classroom = classroom;
        exp.teacher = teacher;
        exp.timeRanges = [tr];
        expMap[key] = exp;
      }
    }

    const keys = Object.keys(expMap);
    for (const k of keys) {
      experiments.push(expMap[k]);
    }
    return experiments;
  }

  parseWeekHtml(html: string): ExperimentData[] {
    if (!html || html.length < 100) return [];

    const tableMatch = html.match(/<table[\s\S]*?<\/table>/g);
    if (!tableMatch || tableMatch.length < 2) return [];

    const secondTable = tableMatch[1];

    const weekDates: string[] = [];
    const thRegex = /<th[^>]*>([\s\S]*?)<\/th>/g;
    let thMatch: RegExpExecArray | null = null;
    while ((thMatch = thRegex.exec(secondTable)) !== null) {
      const thContent = thMatch[1];
      const brIdx = thContent.indexOf('<br');
      if (brIdx > 0) {
        const datePart = thContent.substring(brIdx).replace(/<[^>]+>/g, '').trim();
        if (datePart.length >= 8) {
          weekDates.push(datePart);
        }
      }
    }

    if (weekDates.length === 0) return [];

    return this.parseSysjHtml(secondTable, weekDates);
  }

  // ===== 按周拉取实验数据（需已登录） =====

  async fetchSysjScheduleWithTgc(tgc: string, onProgress?: (week: number, total: number) => void): Promise<ExperimentData[]> {

    const loggedIn = await this.loginToSysjWithTgc(tgc);
    if (!loggedIn) {
      throw new Error('sysj login failed with TGC');
    }

    const expMap: Record<string, ExperimentData> = {};

    for (let week = 1; week <= MAX_WEEKS; week++) {
      if (onProgress) {
        onProgress(week, MAX_WEEKS);
      }
      try {
        const resp = await this.http.postRaw(
          SYSJ_BASE + '/xidian/schedule/myScheduleInfo',
          'termId=' + TERM_ID + '&week=' + week + '&type=0',
          'application/x-www-form-urlencoded',
          { 'Content-Type': 'application/x-www-form-urlencoded' }
        );
        const html = resp.body || '';

        if (week <= 2) {
        }

        if (!html || html.length < 100) continue;

        const weekExps = this.parseScheduleListHtml(html, week);
        if (weekExps.length > 0) {
        }

        for (const exp of weekExps) {
          const key = exp.name + '|' + exp.classroom + '|' + exp.teacher;
          if (expMap[key]) {
            for (const tr of exp.timeRanges) {
              if (!expMap[key].timeRanges.some(t => t.startTime === tr.startTime)) {
                expMap[key].timeRanges.push(tr);
              }
            }
          } else {
            expMap[key] = exp;
          }
        }
      } catch (e) {
      }
    }

    const result: ExperimentData[] = [];
    const keys = Object.keys(expMap);
    for (const k of keys) {
      result.push(expMap[k]);
    }
    return result;
  }

  parseScheduleListHtml(html: string, weekNum: number): ExperimentData[] {
    const results: ExperimentData[] = [];

    const tableMatch = /<table[^>]*>([\s\S]*?)<\/table>/.exec(html);
    if (!tableMatch) return results;

    const listTable = tableMatch[1];

    const rowRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/g;
    let rMatch: RegExpExecArray | null = null;
    let rowIndex = 0;
    while ((rMatch = rowRegex.exec(listTable)) !== null) {
      rowIndex++;
      if (rowIndex <= 1) continue;

      const rowHtml = rMatch[1];
      const tdRegex = /<td[^>]*>([\s\S]*?)<\/td>/g;
      const cells: string[] = [];
      let tdM: RegExpExecArray | null = null;
      while ((tdM = tdRegex.exec(rowHtml)) !== null) {
        cells.push(tdM[1].replace(/<[^>]+>/g, '').trim());
      }

      if (cells.length < 9) continue;

      const name = cells[1];
      if (!name || name.length === 0) continue;

      const timeStr = cells[6];
      const teacher = cells[7];
      const lab = cells[8];
      const project = cells.length > 9 ? cells[9] : '';

      const tr = new TimeRange();
      if (timeStr && timeStr.indexOf('周') >= 0) {
        tr.startTime = timeStr;
      }

      const key = name + '|' + lab + '|' + teacher;
      const exp = new ExperimentData();
      exp.type = ExperimentType.OTHERS;
      exp.name = name;
      exp.classroom = lab;
      exp.teacher = teacher;
      exp.reference = project;
      exp.timeRanges = tr.startTime ? [tr] : [];
      results.push(exp);
    }

    return results;
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
