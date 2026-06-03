
// EhallService.ets — 西电 Ehall 数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { CacheService } from './CacheService';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';

const TAG = 'EhallService';

export interface EmptyClassroomItem {
  name: string;
  buildingCode: string;
  roomName: string;
  floor: string;
  isUsed: boolean[];
}

export interface BuildingInfo {
  code: string;
  name: string;
}

interface QueryFilter {
  name: string;
  value: string;
  operator: string;
}
interface ZcXqjData { ZC: object; XQJ: object; }
// 显式字段的 API 行类型（不含索引签名，规避 arkts-no-indexed-signatures）
interface ClassTableRow {
  KCM: string; KCH: string; KXH: string; SKXQ: string; SKZC: string;
  KSJC: string; JSJC: string; SKJS: string; JASMC: string;
}

interface ExamRow {
  KCM: string; KSMC: string; KSSJMS: string; KSRQ: string; JASMC: string; ZWH: string;
}

interface ScoreRow {
  XNXQDM: string; XSKCM: string; ZCJ: string; XF: string;
  XGXKLBDM_DISPLAY: string; SFJG: string;
  KCLBDM_DISPLAY: string; CXCKDM_DISPLAY: string; DJCJLXDM: string;
  DJCJLXDM_DISPLAY: string;  // 百分制/五级成绩/二级成绩
  JXBID: string;
}

interface EmptyClassroomRow {
  JXLDM: string; JXLJC: string; JXLMC: string; LC: string; JASMC: string;
  JC1: string; JC2: string; JC3: string; JC4: string; JC5: string;
  JC6: string; JC7: string; JC8: string; JC9: string; JC10: string; JC11: string;
}

interface BuildingRow {
  JXLDM: string; JXLJC: string; JXLMC: string;
}

// ehall 请求头
const EHALL_HEADERS: Record<string, string> = {
  'Referer': 'http://ehall.xidian.edu.cn/new/index_xd.html',
  'Host': 'ehall.xidian.edu.cn',
  'Accept': 'application/json, text/javascript, */*; q=0.01',
  'Accept-Language': 'zh-CN,zh;q=0.9',
  'Accept-Encoding': 'gzip, deflate, br',
  'Connection': 'keep-alive',
  'X-Requested-With': 'XMLHttpRequest',
};

export const EHALL_APP_CLASS_TABLE = '4770397878132218';
export const EHALL_APP_EXAM = '4768687067472349';
export const EHALL_APP_SCORE = '4768574631264620';
export const EHALL_APP_EMPTY_CLASSROOM = '4768402106681759';

const APP_PATH_MAP: Map<string, string> = new Map([
  [EHALL_APP_CLASS_TABLE, '/jwapp/sys/wdkb'],
  [EHALL_APP_EXAM, '/jwapp/sys/studentWdksapApp'],
  [EHALL_APP_SCORE, '/jwapp/sys/cjcx'],
  [EHALL_APP_EMPTY_CLASSROOM, '/jwapp/sys/kxjas'],
]);

export class SemesterUtil {
  // 用户提供的精确学期时间（2025-2026学年第二学期）
  // 第一周：3月2日-8日，第十八周：6月29日-7月5日
  // 学期开始日期：2026年3月2日（周一）
  private static readonly SEMESTER_START_DATE_2025_2026_2 = new Date(2026, 2, 2); // 3月2日

  /**
   * 获取学期开学日期。
   * 参数可以是完整 semCode ("2025-2026-1") 或 (yearPart="2025-2026", termPart="1")
   */
  static getSemesterStartDate(semCodeOrYear: string, termPart?: string): Date {
    let y: number, t: number;
    if (termPart === undefined) {
      // 完整 semCode: "2025-2026-1"
      const p = semCodeOrYear.split('-');
      y = parseInt(p[0]);
      t = parseInt(p[2]);
    } else {
      // (yearPart, termPart) 格式: "2025-2026", "2"
      const p = semCodeOrYear.split('-');
      // 秋季学期使用第一年，春季学期使用第二年
      y = parseInt(termPart === '1' ? p[0] : p[1]);
      t = parseInt(termPart);
    }
    // 对于 2025-2026-2 学期，使用用户提供的精确日期
    let semCode: string;
    if (termPart === undefined) {
      semCode = semCodeOrYear;
    } else {
      const pp = semCodeOrYear.split('-');
      semCode = pp[0] + '-' + pp[1] + '-' + termPart;
    }
    if (semCode === '2025-2026-2') {
      return new Date(SemesterUtil.SEMESTER_START_DATE_2025_2026_2);
    }

    // 旧逻辑：秋季学期9月1日，春季学期3月2日
    const start = t === 1 ? new Date(y, 8, 1) : new Date(y, 2, 2);
    const dow = start.getDay();
    // 找到该日期所在的周一
    const add = dow === 0 ? -6 : dow === 1 ? 0 : 1 - dow;
    start.setDate(start.getDate() + add);
    return start;
  }

  static calcCurrentWeekFromNow(): number {
    const now = new Date();
    const start = SemesterUtil.getSemesterStartDate(SemesterUtil.getCurrentSemesterCode());
    const diff = Math.floor((now.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
    return Math.max(1, Math.min(18, Math.floor(diff / 7) + 1));
  }

  static getCurrentSemesterCode(): string {
    const now = new Date();
    const y = now.getFullYear();
    const m = now.getMonth() + 1;
    if (m >= 9) return y + '-' + (y + 1) + '-1';
    if (m >= 2 && m <= 7) return (y - 1) + '-' + y + '-2';
    return (y - 1) + '-' + y + '-1';
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

  // 缓存 app session URL，避免重复激活
  private appSessionUrl: Record<string, string> = {};

  constructor() {}

  /** 登录后清除过期 session 缓存 */
  clearSessionCache(): void {
    this.appSessionUrl = {};
    console.info(TAG, 'Session cache cleared');
  }

  static getInstance(): EhallService {
    if (!EhallService.inst) EhallService.inst = new EhallService();
    return EhallService.inst;
  }

  private async init(): Promise<void> { await this.cache.init(); }

  /**
   * 检查 ehall 登录状态
   * GET 请求，依赖 HttpUtil 里的 Cookie header
   */
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
          console.info(TAG, 'checkEhallLogin: hasLogin=' + hasLogin);
          return hasLogin;
        }
      }
      // 响应了但无法解析 → 视为未登录
      return false;
    } catch (e) {
      console.warn(TAG, 'checkEhallLogin network error: ' + JSON.stringify(e));
      // 网络异常（超时、DNS失败等）→ 抛出标记错误，让调用方区分
      throw new Error('NETWORK_ERROR');
    }
  }

  /**
   * 尝试自动恢复登录（利用 IDS CAS TGT 续期机制）
   *
   * 原理：CAS 认证流程中，即使用户的 ehall MOD_AUTH_CAS cookie 过期了，
   * IDS 服务器的 TGT（Ticket Granting Ticket）可能仍然有效。
   * 如果 TGT 有效，访问 ehall 的登录 URL 会自动完成 CAS 认证，
   * 服务器会签发新的 MOD_AUTH_CAS cookie。
   *
   * 流程：GET /login?service=https://ehall.xidian.edu.cn/new/index.html
   * → 如果 TGT 有效，IDS 会 302 到 service + ticket=XXX
   * → ehall 用 ticket 换取新 session，返回新的 MOD_AUTH_CAS cookie
   */
  /**
   * 尝试自动恢复登录态
   * 1. 先检查 HttpUtil 里 MOD_AUTH_CAS 是否仍有效
   * 2. 如果过期则通过 CAS TGC 自动续期（无需密码）
   */
  async tryAutoRestoreLogin(): Promise<boolean> {
    try {
      // Step 1: 快速检查
      const verified = await this.checkEhallLogin();
      if (verified) {
        console.info(TAG, 'tryAutoRestoreLogin: already logged in');
        return true;
      }

      // Step 2: 尝试 CAS 自动恢复（TGC 有效则无需密码）
      console.info(TAG, 'tryAutoRestoreLogin: attempting CAS restore...');
      const cas = CasLoginService.getInstance();
      const restored = await cas.tryAutoRestoreLogin();
      if (restored) {
        console.info(TAG, 'tryAutoRestoreLogin: CAS redirect completed, re-verifying...');
        // 重新验证 ehall 登录状态
        const reVerified = await this.checkEhallLogin();
        if (reVerified) {
          console.info(TAG, 'tryAutoRestoreLogin: CAS restore verified, session valid');
          await cas.syncCookiesToWebView();
          return true;
        }
        console.warn(TAG, 'tryAutoRestoreLogin: re-verification FAILED, CAS restore was false positive');
      }

      console.info(TAG, 'tryAutoRestoreLogin: all attempts failed');
      return false;
    } catch (e) {
      console.warn(TAG, 'tryAutoRestoreLogin failed: ' + JSON.stringify(e));
      return false;
    }
  }

  /**
   * 从 ehall API 获取学号（用于自动补全缺失的 ids_account）
   * 从 WebView 抓取学号后存 preference，
   * 这里作为 fallback 尝试从 ehall JSONP 接口提取
   * 优先用 userFavoriteApps.json（复数，已验证可用），
   * fallback 用 getAppUsageMonitor.json
   */
  async fetchStudentId(): Promise<string> {
    // 优先从本地缓存读（学号不会变）
    const cached: string = await PreferenceUtil.getString('ids_account');
    if (cached && cached.length > 0) return cached;

    // 方案1: userFavoriteApps.json (复数，之前 xbrowser 已验证返回200)
    try {
      const resp1 = await this.http.get(
        'https://ehall.xidian.edu.cn/jsonp/userFavoriteApps.json',
        EHALL_HEADERS
      );
      if (resp1.isOk) {
        const jsonStr = resp1.body.replace(/^\s*\/\*\*\/\s*\w*\s*\(/, '').replace(/\)\s*;?\s*$/, '');
        const obj = JSON.parse(jsonStr) as Record<string, object>;
        // 尝试从 user 对象中提取学号
        const user = (obj['user'] || obj) as Record<string, string>;
        const sid = user['code'] || user['userId'] || user['userName'] || user['userCode'] || '';
        if (sid) {
          console.info(TAG, 'fetchStudentId: got from userFavoriteApps');
          await PreferenceUtil.putString('ids_account', sid);
          return sid;
        }
      }
    } catch (e) {
      console.warn(TAG, 'fetchStudentId: userFavoriteApps failed: ' + JSON.stringify(e));
    }

    // 方案2: getuserinfo
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
          console.info(TAG, 'fetchStudentId: got from getuserinfo');
          await PreferenceUtil.putString('ids_account', sid);
          return sid;
        }
      }
    } catch (e) {
      console.warn(TAG, 'fetchStudentId: getuserinfo failed: ' + JSON.stringify(e));
    }

    console.error(TAG, 'fetchStudentId: all methods failed');
    return '';
  }

  /**
   * 激活 app session
   *
   * 流程：GET /appShow?appId=xxx → 302 → 跟随重定向建立 JSESSIONID
   * HarmonyOS NETSTACK 自动跟随重定向，用 %2A 替代 URL 中的 *
   */
  private async activateAppSession(appId: string, force: boolean = false): Promise<void> {
    if (!force && this.appSessionUrl[appId]) {
      console.info(TAG, 'activateAppSession: using cached for ' + appId);
      return;
    }

    const appPath = APP_PATH_MAP.get(appId) || '/jwapp/sys/wdkb';
    this.appSessionUrl[appId] = appPath;

    // 检查当前是否已有 JSESSIONID（如果有了就不需要重新激活，除非 force=true）
    const cookiesBefore = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (!force && cookiesBefore.toLowerCase().includes('jsessionid')) {
      console.info(TAG, 'activateAppSession: already have JSESSIONID, skip for ' + appId);
      return;
    }

    console.info(TAG, 'activateAppSession: establishing session for ' + appId);

    // 方案1：直接调用 /appShow，NETSTACK 会自动跟随重定向
    // 即使最终因为 *default* URL 失败，中间步骤可能已设置了部分 cookie
    try {
      const resp = await this.http.get(
        'https://ehall.xidian.edu.cn/appShow?appId=' + appId,
        EHALL_HEADERS
      );
      console.info(TAG, 'activateAppSession: /appShow resp=' + resp.statusCode);
    } catch (e) {
      console.warn(TAG, 'activateAppSession: /appShow failed (expected): ' + JSON.stringify(e));
    }

    // 检查 /appShow 是否已设置了 JSESSIONID
    const cookiesAfter1 = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    if (cookiesAfter1.toLowerCase().includes('jsessionid')) {
      console.info(TAG, 'activateAppSession: JSESSIONID obtained from /appShow');
      return;
    }

    // 方案2：用 %2A 编码替代 *，手动 GET 应用的默认页面
    try {
      const directUrl = 'https://ehall.xidian.edu.cn' + appPath + '/%2Adefault%2A/index.do';
      console.info(TAG, 'activateAppSession: trying URL-encoded default page: ' + directUrl);
      const resp2 = await this.http.get(directUrl, EHALL_HEADERS);
      console.info(TAG, 'activateAppSession: direct page resp=' + resp2.statusCode);

      // 如果服务器返回了重定向，尝试跟随
      if (resp2.isRedirect && resp2.location) {
        let loc: string = resp2.location;
        // 如果重定向 URL 也是相对路径，补全
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

    // 最终检查 cookie 状态
    const cookiesFinal = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    const hasModAuth = cookiesFinal.toLowerCase().includes('mod_auth_cas');
    const hasJsession = cookiesFinal.toLowerCase().includes('jsessionid');
    console.info(TAG, 'activateAppSession: final cookies hasMOD_AUTH=' + hasModAuth +
      ' hasJSESSIONID=' + hasJsession);
  }

  /**
   * 业务 POST 请求
   * Cookie header 由 HttpUtil 自动从 cookie 池中根据 domain+path 匹配后填入
   * 如果响应是重定向到登录页，清除 appSession 缓存强制下次重新激活
   */
  private async appPost(path: string, body: Record<string, string>): Promise<HttpResponse> {
    const url = 'https://ehall.xidian.edu.cn' + path;
    const cookies = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    const hasCas: boolean = cookies.indexOf('MOD_AUTH_CAS') >= 0;
    const hasJsession: boolean = cookies.toLowerCase().indexOf('jsessionid') >= 0;
    console.info(TAG, `appPost: url=${path} hasMOD_AUTH=${hasCas} hasJSESSIONID=${hasJsession} cookieLen=${cookies.length}`);
    let resp = await this.http.postForm(url, body, EHALL_HEADERS);
    const cookiesAfter = this.http.getCookiesForDomain('ehall.xidian.edu.cn');
    console.info(TAG, 'appPost: resp status=' + resp.statusCode);

    // 检测是否被重定向到登录页（会话过期）
    if (resp.isRedirect && resp.location && resp.location.includes('login')) {
      console.warn(TAG, 'appPost: session expired, redirecting to login');
      // 清除 app session 缓存，强制下次重新激活
      this.appSessionUrl = {};
      // 尝试重新激活并重试
      const appId = this.findAppIdByPath(path);
      if (appId) {
        console.info(TAG, 'appPost: retrying with re-activation for ' + appId);
        await this.activateAppSession(appId, true);  // force=true 强制重新激活
        resp = await this.http.postForm(url, body, EHALL_HEADERS);
        console.info(TAG, 'appPost: retry resp=' + resp.statusCode);
      }
    }

    // 检测响应体是否是 HTML 登录页（非 JSON）
    if (resp.body.trimStart().startsWith('<!') || resp.body.trimStart().startsWith('<html')) {
      console.warn(TAG, 'appPost: received HTML instead of JSON, body[0:200]=' + resp.body.substring(0, 200));
      this.appSessionUrl = {};
      const appId = this.findAppIdByPath(path);
      if (appId) {
        console.info(TAG, 'appPost: retrying with re-activation for ' + appId);
        await this.activateAppSession(appId, true);  // force=true 强制重新激活
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
   * 获取课程表数据
   * forceRefresh=false 时：如果缓存未过期，直接返回缓存；否则请求网络
   * forceRefresh=true 时：跳过缓存，直接网络请求
   */
  async getClassTable(semCode: string, sid: string, forceRefresh: boolean = false): Promise<string> {
    await this.init();
    const key = 'ct_' + semCode;
    return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
      // 尝试激活 session（不阻塞，失败也继续）
      try {
        await this.activateAppSession(EHALL_APP_CLASS_TABLE);
      } catch (e) {
        console.warn(TAG, 'getClassTable: activateAppSession failed, continuing without it: ' + JSON.stringify(e));
      }

      // 构造请求体：XH 可选，有学号就传
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
    }, 7 * 24 * 60 * 60 * 1000, forceRefresh);  // 课表一学期基本不变，缓存7天
  }

  // 仅读取缓存（不触发网络请求），用于快速显示
  async getCachedClassTable(semCode: string, sid: string): Promise<string | null> {
    await this.init();
    const key = 'ct_' + semCode;
    return this.cache.get(key);
  }

  // 读取缓存（忽略过期时间），离线时使用过期缓存
  async getCachedClassTableStale(semCode: string, sid: string): Promise<string | null> {
    await this.init();
    const key = 'ct_' + semCode;
    return this.cache.getStale(key);
  }

  async getExamSchedule(semCode: string): Promise<string> {
    await this.init();
    const key = 'exam_' + semCode;
    return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
      await this.activateAppSession(EHALL_APP_EXAM);
      return (await this.appPost(
        '/jwapp/sys/studentWdksapApp/modules/wdksap/wdksap.do',
        { 'XNXQDM': semCode, '*order': '-KSRQ,-KSSJMS' }
      )).body;
    }, 5 * 60 * 1000);
  }

  async getScores(sid: string): Promise<string> {
    await this.init();
    const key = 'score_' + sid;
    return this.cache.getOrFetch<string>(key, async (): Promise<string> => {
      await this.activateAppSession(EHALL_APP_SCORE);
      const body: Record<string, string> = {
        '*json': '1',
        'querySetting': '[{"name":"SFYX","value":"1","linkOpt":"and","builder":"m_value_equal"}]',
        '*order': '+XNXQDM,KCH,KXH',
        'pageSize': '1000', 'pageNumber': '1',
      };
      return (await this.appPost('/jwapp/sys/cjcx/modules/cjcx/xscjcx.do', body)).body;
    }, 5 * 60 * 1000);
  }

  // 成绩构成详情（平时/期末比例与分数）
  async getScoreDetail(jxbid: string, semesterCode: string): Promise<ComposeDetail[]> {
    await this.init();
    await this.activateAppSession(EHALL_APP_SCORE);
    const sid = PreferenceUtil.getString('ids_account') || '';
    const body: Record<string, string> = {
      'JXBID': jxbid,
      'XH': sid,
      'XNXQDM': semesterCode,
      'CKLY': '1',
    };
    const resp = await this.appPost('/jwapp/sys/cjcx/modules/cjcx/cxkckgcxlrcj.do', body);
    const result: ComposeDetail[] = [];
    try {
      const obj = JSON.parse(resp.body) as Record<string, object>;
      const datas = obj['datas'] as Record<string, object>;
      const sub = datas['cxkckgcxlrcj'] as Record<string, object>;
      const rows = sub['rows'] as Record<string, string>[];
      if (rows.length > 0) {
        const row = rows[0];
        const formula = row['GCXKHLRCJGS']; // 公式如 "平时成绩*0.3 + 期末成绩*0.7 = 总评成绩"
        const detailStr = row['KCGCXKHLRCJ']; // 各项成绩如 "平时成绩:85,期末成绩:72"
        if (formula && detailStr) {
          // 解析分项比例
          const formulaParts = formula.split(/ \+ |\*| = /);
          const detailParts = detailStr.split(',');
          const detailMap = new Map<string, string>();
          for (const dp of detailParts) {
            const kv = dp.split(':');
            if (kv.length === 2) detailMap.set(kv[0], kv[1]);
          }
          let i = 0;
          while (i < formulaParts.length) {
            const name = formulaParts[i].trim();
            if (name === '总评成绩') { i++; continue; }
            const ratio = formulaParts[i + 1] ? `${parseFloat(formulaParts[i + 1]) * 100}%` : '';
            const score = detailMap.get(name) || '未登记';
            result.push({ content: name, ratio: ratio, score: score } as ComposeDetail);
            i += 2;
          }
        }
      }
    } catch (e) {
      console.warn('[EhallService] getScoreDetail parse error: ' + (e as Error).message);
    }
    return result;
  }

  /**
   * 获取空闲教室楼栋列表
   */
  async getEmptyClassroomBuildings(): Promise<BuildingInfo[]> {
    await this.init();
    return this.cache.getOrFetch<BuildingInfo[]>('er_buildings', async (): Promise<BuildingInfo[]> => {
      await this.activateAppSession(EHALL_APP_EMPTY_CLASSROOM);
      const resp = await this.http.get(
        'https://ehall.xidian.edu.cn/jwapp/sys/kxjas/modules/kxjas/jxlcx.do?*order=%2BXXXQDM%2C%2BPX%2C%2BJXLDM',
        EHALL_HEADERS
      );
      console.info(TAG, 'getEmptyClassroomBuildings: resp=' + resp.statusCode);
      const raw: object[] = EhallService.extractRaw(resp.body);
      const out: BuildingInfo[] = [];
      for (const row of raw) {
        const r: BuildingRow = row as BuildingRow;
        const code = r.JXLDM || '';
        if (code !== '') {
          out.push({ code: code, name: r.JXLJC || r.JXLMC || '未知' });
        }
      }
      return out;
    }, 60 * 60 * 1000); // 楼栋列表缓存1小时
  }

  /**
   * 查询空闲教室
   *
   * 流程：
   * 1. POST /rqzhzcjc.do  用日期+学期获取 ZC(周次) 和 XQJ(星期几)
   * 2. POST /cxjsqk.do    用楼栋+ZC+XQJ 查询教室占用情况
   */
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
      await this.activateAppSession(EHALL_APP_EMPTY_CLASSROOM);

      // Step 1: 获取当前日期对应的 ZC（周次）和 XQJ（星期几）
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
            // 显式接口 + 直接属性访问，规避动态 key
            const rqmap: ZcXqjData = rqdata as ZcXqjData;
            const zcRaw = rqmap.ZC;
            const xqjRaw = rqmap.XQJ;
            if (zcRaw !== undefined && zcRaw !== null) { zc = String(zcRaw); }
            if (xqjRaw !== undefined && xqjRaw !== null) { xqj = String(xqjRaw); }
          }
        }
      } catch { /* fallback: 用前端参数 */ }

      console.info(TAG, 'searchEmptyClassrooms: ZC=' + zc + ' XQJ=' + xqj + ' date=' + dateStr);

      // Step 2: 查询教室占用情况
      // querySetting 请求格式
      const querySetting = JSON.stringify([
        { name: 'JXLDM', caption: '教学楼代码', builder: 'equal', linkOpt: 'AND', value: buildingCode },
        { name: 'XNXQDM', value: weekRange + '-' + weekPart, linkOpt: 'AND', builder: 'equal' },
        { name: 'ZC', value: zc, linkOpt: 'AND', builder: 'equal' },
        { name: 'XQJ', value: xqj, linkOpt: 'AND', builder: 'equal' },  // 星期几
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

  /**
   * 将 (学期, 周次, 星期几) 转换为日期字符串 YYYY-MM-DD
   * 用于 rqzhzcjc.do 的 RQ 参数
   */

  /**
   * 按日期查询空闲教室（不依赖周次）
   * @param date 要查询的日期
   */
  async searchEmptyClassroomsByDate(buildingCode: string, date: Date): Promise<string> {
    // 先用 rqzhzcjc.do 把日期转换为周次+星期
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    const dateStr = y + '-' + m + '-' + d;

    // 从 API 获取 ZC/XQJ（需要学年+学期参数）
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

  /**
   * 将 (学期, 周次, 星期几) 转换为日期字符串 YYYY-MM-DD
   * 用于 rqzhzcjc.do 的 RQ 参数
   */
  private calcSemesterDate(semYear: string, semPart: string, week: number, day: number): string {
    const startDate = SemesterUtil.getSemesterStartDate(semYear, semPart);
    const dayMs = 24 * 60 * 60 * 1000;
    // 第week周的第day天（周一=1）
    const target = new Date(startDate.getTime() + (week - 1) * 7 * dayMs + (day - 1) * dayMs);
    const y = target.getFullYear();
    const m = String(target.getMonth() + 1).padStart(2, '0');
    const d = String(target.getDate()).padStart(2, '0');
    return y + '-' + m + '-' + d;
  }

  // 提取 API rows 数组
  // API 响应结构: { "datas": { "xxx": { "rows": [...] } } }
  // 或: { "datas": { "xxx": { "extParams": { "rows": [...] } } } }
  static extractRaw(body: string): object[] {
    try {
      console.info(TAG, 'extractRaw: parsing body length=' + body.length);
      const obj = JSON.parse(body) as Record<string, object>;

      // 方式1: 直接访问 datas.xxx.rows
      const datas = obj['datas'];
      if (datas !== null && typeof datas === 'object') {
        const datasMap = datas as Record<string, object>;
        // 遍历 datas 下的每个 key
        for (const key of Object.keys(datasMap)) {
          const sub = datasMap[key];
          if (sub !== null && typeof sub === 'object') {
            const subMap = sub as Record<string, object>;
            // 直接找 rows
            const rows = subMap['rows'];
            if (Array.isArray(rows)) {
              console.info(TAG, 'extractRaw: found rows via datas.' + key + '.rows, count=' + rows.length);
              return rows as object[];
            }
            // 有些 API 在 extParams.rows 里
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

      // 方式2: 原有的递归遍历（兜底）
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


  // 空教室查询结果
  static extractEmptyClassrooms(body: string): EmptyClassroomItem[] {
    const out: EmptyClassroomItem[] = [];
    const rows = EhallService.extractRaw(body);
    console.info(TAG, 'extractEmptyClassrooms: rows count=' + rows.length);
    for (const row of rows) {
      const r: EmptyClassroomRow = row as EmptyClassroomRow;
      const rawName = r.JASMC || '';
      const roomName = rawName.replace(/[（(].*?[)）]/, '').trim();
      const u1 = r.JC1 || ''; const u2 = r.JC2 || ''; const u3 = r.JC3 || '';
      const u4 = r.JC4 || ''; const u5 = r.JC5 || ''; const u6 = r.JC6 || '';
      const u7 = r.JC7 || ''; const u8 = r.JC8 || ''; const u9 = r.JC9 || '';
      const u10 = r.JC10 || ''; const u11 = r.JC11 || '';

      // 调试：打印第一行数据
      if (out.length === 0) {
        console.info(TAG, 'extractEmptyClassrooms: first row JASMC=' + rawName +
          ' JC1=[' + u1 + '] JC2=[' + u2 + '] JC3=[' + u3 + ']');
      }

      // isUsed[i] = true 表示空闲，false 表示占用
      // JC${index+1} 包含 "1_" 表示占用
      // 所以：不包含 "1_" = 空闲
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

  // ===== sysj 实验系统 OAuth 登录 =====

  // 手动跟随重定向，最多 maxSteps 步
  private async followRedirects(startUrl: string, maxSteps: number = 10): Promise<HttpResponse> {
    let currentUrl = startUrl;
    for (let i = 0; i < maxSteps; i++) {
      const resp = await this.http.getNoRedirect(currentUrl);
      if (!resp.isRedirect || !resp.location) {
        return resp;
      }
      // 处理相对 URL
      let location = resp.location;
      if (location.startsWith('/')) {
        const idx = currentUrl.indexOf('/', 8); // 跳过 https://
        const base = idx > 0 ? currentUrl.substring(0, idx) : currentUrl;
        location = base + location;
      }
      currentUrl = location;
    }
    throw new Error('Too many redirects');
  }

  // 从 URL 中提取查询参数
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

  // 通过 HttpUtil 自行登录 CAS 获取 TGC cookie
  // 流程：GET CAS登录页 → 解析隐藏字段 → POST凭据 → 捕获TGC
  async getCasTgc(): Promise<string> {
    try {
      const serviceUrl = 'https://sysj.xidian.edu.cn/xidian/test';
      const casLoginUrl = 'https://cas.xidian.edu.cn/authserver/login?service=' +
        encodeURIComponent(serviceUrl);
      console.info(TAG, 'getCasTgc: GET ' + casLoginUrl.substring(0, 80));

      // Step 1: GET CAS 登录页
      const loginPageResp = await this.http.get(casLoginUrl);
      const html = loginPageResp.body || '';
      console.info(TAG, 'getCasTgc: login page len=' + html.length);

      // Step 2: 解析隐藏字段 (lt, execution, _eventId)
      const ltMatch = html.match(/name="lt"\s+value="([^"]*)"/);
      const executionMatch = html.match(/name="execution"\s+value="([^"]*)"/);
      const eventIdMatch = html.match(/name="_eventId"\s+value="([^"]*)"/);
      const lt = ltMatch ? ltMatch[1] : '';
      const execution = executionMatch ? executionMatch[1] : '';
      const eventId = eventIdMatch ? eventIdMatch[1] : 'submit';
      console.info(TAG, 'getCasTgc: lt=' + (lt ? 'yes' : 'no') + ' execution=' + (execution ? 'yes' : 'no'));

      if (!lt || !execution) {
        throw new Error('getCasTgc: cannot parse CAS login form');
      }

      // Step 3: POST 凭据到 CAS
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

      console.info(TAG, 'getCasTgc: POST credentials');
      // 用 getNoRedirect 手动跟随，捕获每个 302 的 Set-Cookie
      const casResp = await this.http.postNoRedirect(postUrl, body, {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': casLoginUrl,
      });

      // 检查 CAS 域是否拿到了 TGC
      const casCookies = this.http.getCookiesForDomain('cas.xidian.edu.cn');
      console.info(TAG, 'getCasTgc: cas cookies received');

      const tgcMatch = casCookies.match(/TGC=([^;\s]+)/);
      if (tgcMatch) {
        console.info(TAG, 'getCasTgc: TGC captured, len=' + tgcMatch[1].length);
        return tgcMatch[1];
      }

      // 如果 POST 返回 302，手动跟随重定向链
      let currentUrl = '';
      if (casResp.isRedirect && casResp.location) {
        currentUrl = casResp.location;
        if (currentUrl.startsWith('/')) {
          currentUrl = 'https://cas.xidian.edu.cn' + currentUrl;
        }
      }

      // 跟随重定向链（最多10跳），每跳都可能 Set-Cookie
      let hops = 0;
      while (currentUrl && hops < 10) {
        const redirResp = await this.http.getNoRedirect(currentUrl);
        console.info(TAG, 'getCasTgc: hop[' + hops + '] status=' + redirResp.statusCode +
          ' url=' + currentUrl.substring(0, 80));

        // 每跳后检查 TGC
        const casCk = this.http.getCookiesForDomain('cas.xidian.edu.cn');
        const tgcM = casCk.match(/TGC=([^;\s]+)/);
        if (tgcM) {
          console.info(TAG, 'getCasTgc: TGC found at hop ' + hops + ', len=' + tgcM[1].length);
          return tgcM[1];
        }

        if (redirResp.isRedirect && redirResp.location) {
          currentUrl = redirResp.location;
          if (currentUrl.startsWith('/')) {
            // 从当前URL提取协议+主机
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
      console.info(TAG, 'getCasTgc failed: ' + JSON.stringify(e));
      return '';
    }
  }

  // 使用 TGC cookie 登录 sysj
  async loginToSysjWithTgc(tgc: string): Promise<boolean> {
    console.info(TAG, 'loginToSysjWithTgc: start');
    try {
      // Step 0: 注入 TGC 到 HttpUtil 的 cas.xidian.edu.cn 域
      await this.http.injectCookies('TGC=' + tgc, 'cas.xidian.edu.cn');
      console.info(TAG, 'loginToSysjWithTgc: TGC injected to cas.xidian.edu.cn');

      // Step 1: GET sysj /xidian/test → 302 → uaa/oauth/authorize → 302 → cas
      const resp1 = await this.http.getNoRedirect('https://sysj.xidian.edu.cn/xidian/test');
      console.info(TAG, 'loginToSysjWithTgc: step1 status=' + resp1.statusCode + ' isRedirect=' + resp1.isRedirect);

      if (!resp1.isRedirect || !resp1.location) {
        // 可能已经登录了
        if (resp1.statusCode === 200) {
          console.info(TAG, 'loginToSysjWithTgc: already logged in');
          return true;
        }
        throw new Error('sysj step1: no redirect, status=' + resp1.statusCode);
      }

      // Step 2: 跟随整个重定向链（CAS会用TGC自动认证）
      const state = this.getQueryParam(resp1.location, 'state');
      console.info(TAG, 'loginToSysjWithTgc: step1 redirect, state=' + (state || '(none)'));

      // 跟随重定向链直到回到 sysj 或到达终点
      let currentUrl = resp1.location;
      if (currentUrl.startsWith('/')) {
        currentUrl = 'https://sysj.xidian.edu.cn' + currentUrl;
      }

      const respAfterCas = await this.followRedirects(currentUrl, 12);
      console.info(TAG, 'loginToSysjWithTgc: after CAS chain, status=' + respAfterCas.statusCode +
        ' isRedirect=' + respAfterCas.isRedirect + ' bodyLen=' + (respAfterCas.body || '').length);

      // Step 3: 提取 authorization code
      let code = '';
      const finalBody = respAfterCas.body || '';
      const codeMatch = finalBody.match(/\?code=([^&"\s]+)/);
      if (codeMatch) {
        code = codeMatch[1];
      }
      if (!code && respAfterCas.isRedirect && respAfterCas.location) {
        code = this.getQueryParam(respAfterCas.location, 'code');
      }
      // 尝试从 URL 本身提取
      if (!code) {
        const urlCodeMatch = currentUrl.match(/[?&]code=([^&\s"]+)/);
        if (urlCodeMatch) code = urlCodeMatch[1];
      }

      if (!code && state) {
        // 再尝试: 直接 GET uaa/oauth/authorize
        const authorizeUrl = 'https://sysj.xidian.edu.cn/uaa/oauth/authorize?redirect_uri=https://sysj.xidian.edu.cn/xidian/webapp/callback&state=' +
          state + '&client_id=GvsunLims&response_type=code';
        const respAuth = await this.http.get(authorizeUrl);
        const authBody = respAuth.body || '';
        const authCodeMatch = authBody.match(/\?code=([^&"\s]+)/);
        if (authCodeMatch) code = authCodeMatch[1];
        // 也从callback URL中提取
        if (!code) {
          const callbackMatch = authBody.match(/callback\?code=([^&"\s']+)/);
          if (callbackMatch) code = callbackMatch[1];
        }
      }

      if (!code) {
        throw new Error('loginToSysjWithTgc: failed to extract code, finalUrl=' + currentUrl.substring(0, 200));
      }
      console.info(TAG, 'loginToSysjWithTgc: got code=' + code.substring(0, 10) + '...');

      // Step 4: GET /xidian/webapp/callback?code=xxx → 提取 password
      const callbackUrl = 'https://sysj.xidian.edu.cn/xidian/webapp/callback?code=' + code +
        (state ? '&state=' + state : '');
      const resp4 = await this.http.get(callbackUrl);
      const callbackBody = resp4.body || '';
      console.info(TAG, 'loginToSysjWithTgc: callback status=' + resp4.statusCode + ' bodyLen=' + callbackBody.length);

      const pwdMatch = callbackBody.match(/var\s+password\s*=\s*'([^']*)'/);
      if (!pwdMatch) {
        // 可能已经登录成功，不需要password
        console.warn(TAG, 'loginToSysjWithTgc: no password in callback');
        // 如果callback已经设置了session，直接返回true
        return true;
      }
      const password = pwdMatch[1];

      // Step 5: POST /xidian/webapp/login（需要学号）
      const sid = await PreferenceUtil.getString('ids_account');
      console.info(TAG, 'loginToSysjWithTgc: ids saved');
      if (!sid) {
        throw new Error('loginToSysjWithTgc: no ids_account, need to store it after CAS login');
      }
      const loginResp = await this.http.postRaw(
        'https://sysj.xidian.edu.cn/xidian/webapp/login',
        'username=' + encodeURIComponent(sid) + '&password=' + encodeURIComponent(password),
        'application/x-www-form-urlencoded',
        { 'Content-Type': 'application/x-www-form-urlencoded' }
      );
      console.info(TAG, 'loginToSysjWithTgc: login status=' + loginResp.statusCode);

      if (loginResp.statusCode === 200 && loginResp.body) {
        try {
          const loginResult = JSON.parse(loginResp.body) as Record<string, string | number | boolean | object>;
          if (loginResult['success'] === true || loginResult['code'] === 0) {
            console.info(TAG, 'loginToSysjWithTgc: SUCCESS');
            return true;
          }
          console.error(TAG, 'loginToSysjWithTgc: login failed, status=' + loginResp.statusCode);
          return false;
        } catch (_) {
          return true;
        }
      }
      return false;
    } catch (e) {
      console.error(TAG, 'loginToSysjWithTgc failed: ' + String(e));
      return false;
    }
  }

  // ===== sysj 实验数据获取 =====

  // 解析 sysj 返回的 HTML 表格，提取实验信息
  // HTML 格式：第二个 table，thead 含日期，td[do-labReservation='weekday,classIndex'] 含实验
  private parseSysjHtml(html: string, weekDates: string[]): ExperimentData[] {
    const experiments: ExperimentData[] = [];

    // 提取所有 do-labReservation 属性的 cell
    // 格式: do-labReservation="weekday,classIndex"
    const cellRegex = /do-labReservation=['"](\d+),(\d+)['\"][^>]*>([\s\S]*?)<\/td>/g;
    let match: RegExpExecArray | null = null;

    // 内部提取实验名/教室/教师的辅助函数
    const extractField = (cellHtml: string, marker: string): string => {
      const idx = cellHtml.indexOf(marker);
      if (idx < 0) return '';
      const after = cellHtml.substring(idx + marker.length);
      // 取到下一个 <br> 或 </div> 或 <span
      const endIdx = after.search(/<(?:br|\/div|span)/);
      const raw = endIdx > 0 ? after.substring(0, endIdx).trim() : after.trim();
      // 去掉 HTML 标签
      return raw.replace(/<[^>]+>/g, '').trim();
    };

    // 兼容i18n占位符和中文两种格式(实际HTML已翻译为中文)
    const courseMarker = html.indexOf('???student.timetable.course???') >= 0
      ? '???student.timetable.course???\uff1a'
      : '\u8BFE\u7A0B\uFF1A'; // 课程：
    const labMarker = html.indexOf('???schedule.course.lab???') >= 0
      ? '???schedule.course.lab???\uff1a'
      : '\u5B9E\u9A8C\u5BA4\uFF1A'; // 实验室：
    const teacherMarker = html.indexOf('???student.timetable.teacher???') >= 0
      ? '???student.timetable.teacher???\uff1a'
      : '\u6559\u5E08\uFF1A'; // 教师：

    // 临时存储：按 name+classroom+teacher 去重合并
    const expMap: Record<string, ExperimentData> = {};

    while ((match = cellRegex.exec(html)) !== null) {
      const weekDay = parseInt(match[1]); // 1=周一
      const classIndex = parseInt(match[2]); // 节次
      const cellHtml = match[3];

      const name = extractField(cellHtml, courseMarker);
      const classroom = extractField(cellHtml, labMarker);
      const teacher = extractField(cellHtml, teacherMarker);

      if (!name) continue;

      // 计算时间
      const dateStr = weekDates[weekDay - 1]; // 如 '2026-03-02'
      if (!dateStr) continue;
      const startIdx = (classIndex - 1) * 2;
      const endIdx = startIdx + 1;
      const startTime = startIdx < SYSJ_SECTION_TIMES.length ? SYSJ_SECTION_TIMES[startIdx] : '08:30';
      const endTime = endIdx < SYSJ_SECTION_TIMES.length ? SYSJ_SECTION_TIMES[endIdx] : '09:15';

      const tr = new TimeRange();
      tr.startTime = dateStr + ' ' + startTime;
      tr.endTime = dateStr + ' ' + endTime;

      // 去重 key
      const key = name + '|' + classroom + '|' + teacher;
      if (expMap[key]) {
        // 追加时间段
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

    // 转数组
    const keys = Object.keys(expMap);
    for (const k of keys) {
      experiments.push(expMap[k]);
    }
    return experiments;
  }

  // WebView 已完成 sysj 登录后直接调用（跳过 loginToSysj）
  // 检测 sysj 登录是否有效（轻量：只请求1周，检查响应是否为有效HTML）
  async checkSysjLogin(): Promise<boolean> {
    try {
      const resp = await this.http.postRaw(
        'https://sysj.xidian.edu.cn/xidian/StudentCurrWeekTimetable',
        'weeks=1',
        'application/x-www-form-urlencoded',
        { 'Content-Type': 'application/x-www-form-urlencoded' }
      );
      const body = resp.body || '';
      console.info(TAG, 'checkSysjLogin: bodyLen=' + body.length);
      // 登录失效时返回JSON错误或重定向到登录页，不会包含 <table>
      if (body.indexOf('<table') >= 0) {
        return true;
      }
      return false;
    } catch (e) {
      console.error(TAG, 'checkSysjLogin failed: ' + String(e));
      return false;
    }
  }

  // 供 ExperimentPage WebView 方案使用：解析单周 HTML 响应
  public parseWeekHtml(html: string): ExperimentData[] {
    if (!html || html.length < 100) return [];

    const tableMatch = html.match(/<table[\s\S]*?<\/table>/g);
    if (!tableMatch || tableMatch.length < 2) return [];

    const secondTable = tableMatch[1];

    // 提取表头日期
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

  // 使用TGC登录后，HttpUtil逐周获取实验数据
  // 正确API: POST /xidian/schedule/myScheduleInfo, body: termId=2003&week=N
  // 返回完整HTML页面，需解析列表视图Table 0
  async fetchSysjScheduleWithTgc(tgc: string, onProgress?: (week: number, total: number) => void): Promise<ExperimentData[]> {
    console.info(TAG, 'fetchSysjScheduleWithTgc: start');
    const TOTAL_WEEKS = 25;

    // Step 1: 登录
    const loggedIn = await this.loginToSysjWithTgc(tgc);
    if (!loggedIn) {
      throw new Error('sysj login failed with TGC');
    }
    console.info(TAG, 'fetchSysjScheduleWithTgc: login success, fetching schedule...');

    // Step 2: 逐周POST获取数据
    const expMap: Record<string, ExperimentData> = {};
    const sid = await PreferenceUtil.getString('ids_account');

    for (let week = 1; week <= TOTAL_WEEKS; week++) {
      if (onProgress) {
        onProgress(week, TOTAL_WEEKS);
      }
      try {
        const resp = await this.http.postRaw(
          'https://sysj.xidian.edu.cn/xidian/schedule/myScheduleInfo',
          'termId=2003&week=' + week + '&type=0',
          'application/x-www-form-urlencoded',
          { 'Content-Type': 'application/x-www-form-urlencoded' }
        );
        const html = resp.body || '';

        if (week <= 2) {
          console.info(TAG, 'fetchSysjScheduleWithTgc: week=' + week + ' status=' + resp.statusCode + ' bodyLen=' + html.length);
        }

        if (!html || html.length < 100) continue;

        // 解析列表视图 - Table 0
        const weekExps = this.parseScheduleListHtml(html, week);
        if (weekExps.length > 0) {
          console.info(TAG, 'fetchSysjScheduleWithTgc: week=' + week + ' found=' + weekExps.length);
        }

        // 合并
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
        console.warn(TAG, 'fetchSysjScheduleWithTgc: week=' + week + ' error: ' + String(e));
      }
    }

    const result: ExperimentData[] = [];
    const keys = Object.keys(expMap);
    for (const k of keys) {
      result.push(expMap[k]);
    }
    console.info(TAG, 'fetchSysjScheduleWithTgc: done, total=' + result.length);
    return result;
  }

  // 解析课表页面的列表视图HTML
  // Table 0 列: 序号|课程名称|课程代码|开课院系|上课班级|上课人数|上课时间|上课教师|实验室|实验项目|备注
  // 上课时间格式: "4周|星期6|9-10节"
  parseScheduleListHtml(html: string, weekNum: number): ExperimentData[] {
    const results: ExperimentData[] = [];

    // 找第一个 table（列表视图），不收集所有
    const tableMatch = /<table[^>]*>([\s\S]*?)<\/table>/.exec(html);
    if (!tableMatch) return results;

    const listTable = tableMatch[1];

    // 解析行
    const rowRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/g;
    let rMatch: RegExpExecArray | null = null;
    let rowIndex = 0;
    while ((rMatch = rowRegex.exec(listTable)) !== null) {
      rowIndex++;
      if (rowIndex <= 1) continue; // 跳过表头

      const rowHtml = rMatch[1];
      // 提取所有td
      const tdRegex = /<td[^>]*>([\s\S]*?)<\/td>/g;
      const cells: string[] = [];
      let tdM: RegExpExecArray | null = null;
      while ((tdM = tdRegex.exec(rowHtml)) !== null) {
        // 去掉HTML标签，只留文本
        cells.push(tdM[1].replace(/<[^>]+>/g, '').trim());
      }

      // 列: 0序号 1课程名称 2课程代码 3开课院系 4上课班级 5上课人数 6上课时间 7上课教师 8实验室 9实验项目 10备注
      if (cells.length < 9) continue;

      const name = cells[1];
      if (!name || name.length === 0) continue;

      const timeStr = cells[6];  // "4周|星期6|9-10节"
      const teacher = cells[7];
      const lab = cells[8];
      const project = cells.length > 9 ? cells[9] : '';

      // 解析时间格式 "N周|星期D|S-E节"
      const tr = new TimeRange();
      if (timeStr && timeStr.indexOf('周') >= 0) {
        tr.startTime = timeStr; // 直接存原始格式
      }

      const key = name + '|' + lab + '|' + teacher;
      const exp = new ExperimentData();
      exp.type = ExperimentType.OTHERS;
      exp.name = name;
      exp.classroom = lab;
      exp.teacher = teacher;
      exp.reference = project; // 实验项目存到reference
      exp.timeRanges = tr.startTime ? [tr] : [];
      results.push(exp);
    }

    return results;
  }

  async fetchOtherExperimentsNoLogin(): Promise<ExperimentData[]> {
    console.info(TAG, 'fetchOtherExperimentsNoLogin: start');
    try {
      return await this._fetchOtherExperimentsInner();
    } catch (e) {
      console.error(TAG, 'fetchOtherExperimentsNoLogin failed: ' + String(e));
      return [];
    }
  }

  // 实际请求+解析逻辑（共用）
  private async _fetchOtherExperimentsInner(): Promise<ExperimentData[]> {
    const expMap: Record<string, ExperimentData> = {};

    // 遍历 1-25 周
    for (let week = 1; week <= 25; week++) {
      try {
      const resp = await this.http.postRaw(
        'https://sysj.xidian.edu.cn/xidian/StudentCurrWeekTimetable',
        'weeks=' + week,
        'application/x-www-form-urlencoded',
        { 'Content-Type': 'application/x-www-form-urlencoded' }
      );
      const html = resp.body || '';
      if (week <= 2) {
        console.info(TAG, 'fetchOtherExperiments: week=' + week + ' bodyLen=' + html.length);
      }
      if (!html || html.length < 100) {
        if (week <= 2) console.info(TAG, 'fetchOtherExperiments: week=' + week + ' bodyLen=' + html.length);
        continue;
      }

      // 提取表头日期（第2个 table 的 thead th）
      const weekDates: string[] = [];
      const tableMatch = html.match(/<table[\s\S]*?<\/table>/g);
      if (!tableMatch || tableMatch.length < 2) {
        if (week <= 2) console.info(TAG, 'fetchOtherExperiments: week=' + week + ' tables=' + (tableMatch ? tableMatch.length : 0));
        continue;
      }

      const secondTable = tableMatch[1];
      let thMatch: RegExpExecArray | null = null;
      const thRegex = /<th[^>]*>([\s\S]*?)<\/th>/g;
      let thIndex = 0;
      while ((thMatch = thRegex.exec(secondTable)) !== null) {
        const thContent = thMatch[1];
        const brIdx = thContent.indexOf('<br');
        if (brIdx > 0) {
          const datePart = thContent.substring(brIdx).replace(/<[^>]+>/g, '').trim();
          if (datePart.length >= 8) {
            weekDates.push(datePart);
          }
        }
        thIndex++;
      }

      if (weekDates.length === 0) {
        if (week <= 2) console.info(TAG, 'fetchOtherExperiments: week=' + week + ' weekDates=0');
        continue;
      }

      // 解析实验信息
      const weekExps = this.parseSysjHtml(secondTable, weekDates);
      if (weekExps.length > 0) {
        console.info(TAG, 'fetchOtherExperiments: week=' + week + ' found=' + weekExps.length);
      }

      // 合并到全局
      for (const exp of weekExps) {
        const key = exp.name + '|' + exp.classroom + '|' + exp.teacher;
        if (expMap[key]) {
          for (const tr of exp.timeRanges) {
            expMap[key].timeRanges.push(tr);
          }
        } else {
          expMap[key] = exp;
        }
      }
      } catch (e) {
        console.warn(TAG, 'fetchOtherExperiments: week=' + week + ' error: ' + String(e));
      }
    }

    // 转数组返回
    const result: ExperimentData[] = [];
    const keys = Object.keys(expMap);
    for (const k of keys) {
      result.push(expMap[k]);
    }
    console.info(TAG, 'fetchOtherExperiments: done, total=' + result.length);
    return result;
  }

  // ===== 登录后预加载 =====
  async preloadAllData(): Promise<void> {
    console.info(TAG, 'preloadAllData: start');
    try {
      const semCode: string = SemesterUtil.getCurrentSemesterCode();
      const sid: string = await this.fetchStudentId();
      if (!sid) {
        console.warn(TAG, 'preloadAllData: no student ID');
        return;
      }

      // 课表 + 考试并行预加载，await 考试结果写入 PreferenceUtil
      this.getClassTable(semCode, sid, true).catch((e: Error) => {
        console.warn(TAG, 'preload classTable: ' + String(e));
      });
      this.getExamSchedule(semCode).then((raw: string) => {
        // ClassTablePage 从 PreferenceUtil 读考试数据，CacheService 里的 exam_<sem> 它读不到
        PreferenceUtil.putString('exam_schedule_cache', raw);
        console.info(TAG, 'preload: exam saved to PreferenceUtil, ' + raw.length + ' chars');
      }).catch((e: Error) => {
        console.warn(TAG, 'preload exam: ' + String(e));
      });

      // 其他实验（后台静默调 sysj API，写入 PreferenceUtil 供 ClassTablePage 读取）
      this.preloadOtherExperimentsDirect().catch((e: Error) => {
        console.warn(TAG, 'preload other experiments: ' + String(e));
      });

      console.info(TAG, 'preloadAllData: dispatched');
    } catch (e) {
      console.warn(TAG, 'preloadAllData: ' + String(e));
    }
  }

  // 完整实验数据获取：先试直接API，失败则走 OAuth 流程
  async preloadOtherExperimentsDirect(): Promise<number> {
    const TERM_ID = '2003';
    const SYSJ_BASE = 'https://sysj.xidian.edu.cn';
    const MAX_WEEKS = 25;
    console.info(TAG, 'preloadOtherExperimentsDirect: start');

    try {
      // Step 0: 先试直接 API
      const r0: HttpResponse = await this.http.get(
        SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=1'
      );
      let allItems: Record<string, string>[] = [];

      if (r0.isOk && r0.body.length > 0 && r0.body.charAt(0) === '[') {
        // Session 有效，直接拉取
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
        // Session 过期或无 OAuth → 走完整流程
        console.info(TAG, 'preloadOtherExperimentsDirect: doing full OAuth');
        allItems = await this._fetchExperimentsWithOAuth(TERM_ID, SYSJ_BASE, MAX_WEEKS);
      }

      if (allItems.length > 0) {
        const co: ESObject = { 'ts': Date.now(), 'data': allItems } as ESObject;
        PreferenceUtil.putString('sysj_exp_cache', JSON.stringify(co));
        console.info(TAG, 'preloadOtherExperimentsDirect: saved ' + allItems.length + ' items');
        return allItems.length;
      }
      return 0;
    } catch (e) {
      console.warn(TAG, 'preloadOtherExperimentsDirect: ' + String(e));
      return 0;
    }
  }

  // 完整 OAuth 流程获取实验数据
  private async _fetchExperimentsWithOAuth(
    TERM_ID: string, SYSJ_BASE: string, MAX_WEEKS: number
  ): Promise<Record<string, string>[]> {
    // Step 1: 获取 OAuth state
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
      console.warn(TAG, '_fetchExperimentsWithOAuth: no state');
      return [];
    }
    console.info(TAG, '_fetchExperimentsWithOAuth: state=' + state);

    // Step 2: sysj OAuth → CAS
    const params = 'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
      '&state=' + state + '&client_id=GvsunLims&response_type=code' +
      '&authorize_uri=' + encodeURIComponent(SYSJ_BASE + '/uaa/oauth/authorize');
    await this.http.get(SYSJ_BASE + '/uaa/xidian/login?' + params);

    // Step 3: CAS redirect — 备份 cookie 避免污染
    const idsBackup = this.http.getAllCookies('ids.xidian.edu.cn');
    const ehallBackup = this.http.getAllCookies('ehall.xidian.edu.cn');
    const casUrl = 'https://ids.xidian.edu.cn/authserver/oauth2.0/authorize?' +
      'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/uaa/xidian/callback') +
      '&response_type=code&state=' + state + '&client_id=1387116615722893312';
    const r3 = await this.http.get(casUrl);
    if (r3.body && r3.body.indexOf('password') >= 0 && r3.body.indexOf('username') >= 0 && r3.body.indexOf('<form') >= 0) {
      console.warn(TAG, '_fetchExperimentsWithOAuth: CAS session expired');
      return [];
    }
    this.http.copyCookiesForDomain('ids.xidian.edu.cn', 'sysj.xidian.edu.cn');
    this.http.replaceCookiesForDomain('ids.xidian.edu.cn', idsBackup);
    this.http.replaceCookiesForDomain('ehall.xidian.edu.cn', ehallBackup);

    // Step 4/5: 提取 password
    let pwd = '';
    let pm = r3.body?.match(/var password = '([^']+)'/);
    if (pm) { pwd = pm[1]; }

    if (!pwd) {
      // 方式B: /uaa/oauth/authorize → 拿 code → callback → 拿 password
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
      console.warn(TAG, '_fetchExperimentsWithOAuth: no password extracted');
      return [];
    }

    // Step 6: 登录 sysj
    const account = PreferenceUtil.getString('ids_account');
    const loginBody = 'username=' + encodeURIComponent(account) + '&password=' + encodeURIComponent(pwd);
    await this.http.postRaw(SYSJ_BASE + '/xidian/webapp/login', loginBody, 'application/x-www-form-urlencoded');

    // Step 7: 逐周获取数据
    const allItems: Record<string, string>[] = [];
    for (let w = 1; w <= MAX_WEEKS; w++) {
      try {
        const rw = await this.http.get(
          SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=' + String(w)
        );
        this._parseWeekData(rw.body, w, allItems);
      } catch (_e) { /* continue */ }
    }
    console.info(TAG, '_fetchExperimentsWithOAuth: fetched=' + allItems.length);
    return allItems;
  }

  // 解析 sysj myScheduleInfoAjax 返回的周数据（与 ExperimentPage.parseWeekData 逻辑一致）
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

  async clearCache(): Promise<void> {
    await this.cache.clear();
    this.appSessionUrl = {};
  }
}

// ===== 数据模型 =====

export class ClassItemModel {
  kcm: string = '';
  kch: string = '';
  kxh: string = '';
  skxq: string = '';
  skzc: string = '';
  ksjc: string = '';
  jsjc: string = '';
  skjs: string = '';
  jasmc: string = '';
}

export class ExamItemModel {
  kcm: string = '';
  ksmc: string = '';
  kssjms: string = '';
  ksrq: string = '';
  jasmc: string = '';
  zw: string = '';
}

export class ScoreItemModel {
  xnxqdm: string = '';
  xskcm: string = '';
  zcj: string = '';
  xf: string = '';
  xgxklbdmDisplay: string = ''; // 课程性质（必修/公共任选/非标）
  kclbdmDisplay: string = '';   // 课程类别（专业核心课/大类通识课/通识教育选修课...）
  cxckdmDisplay: string = '';   // 修读类型（初修/重考）
  djcjlxdmDisplay: string = ''; // 等级成绩类型（百分制/五级成绩/二级成绩）
  sfjg: string = '';            // 是否及格
  jxbid: string = '';           // 教学班ID
}

export class ComposeDetail {
  content: string = '';
  ratio: string = '';
  score: string = '';
}

// ===== 实验信息数据模型 =====

export enum ExperimentType {
  PHYSICS = 'physics',
  OTHERS = 'others'
}

export class ExperimentData {
  type: ExperimentType = ExperimentType.OTHERS;
  name: string = '';          // 实验名
  classroom: string = '';     // 教室
  teacher: string = '';       // 教师
  timeRanges: TimeRange[] = []; // 时间段
  reference: string = '';     // 参考书（仅物理实验）
  score: string = '';         // 成绩（仅物理实验，预留）
}

export class TimeRange {
  startTime: string = '';  // ISO格式: 2026-04-27 08:30
  endTime: string = '';    // ISO格式: 2026-04-27 10:05
}

// sysj.xidian.edu.cn 解析用时刻表
const SYSJ_SECTION_TIMES: string[] = [
  '08:30', '09:15',  // 第1节
  '09:20', '10:05',  // 第2节
  '10:25', '11:10',  // 第3节
  '11:15', '12:00',  // 第4节
  '14:00', '14:45',  // 第5节
  '14:50', '15:35',  // 第6节
  '15:55', '16:40',  // 第7节
  '16:45', '17:30',  // 第8节
  '19:00', '19:45',  // 第9节
  '19:55', '20:35',  // 第10节
  '20:40', '21:25',  // 第11节
];

export class DataParser {
  // 全部用直接属性访问 r.KCM，避免任何 m[f] 动态索引
  static parseClassTable(body: string): ClassItemModel[] {
    const raw: object[] = EhallService.extractRaw(body);
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

  static parseExamSchedule(body: string): ExamItemModel[] {
    const raw: object[] = EhallService.extractRaw(body);
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

  static parseScores(body: string): ScoreItemModel[] {
    const raw: object[] = EhallService.extractRaw(body);
    const out: ScoreItemModel[] = [];
    for (const row of raw) {
      const r: ScoreRow = row as ScoreRow;
      const item: ScoreItemModel = new ScoreItemModel();
      item.xnxqdm = String(r.XNXQDM ?? '');
      item.xskcm = String(r.XSKCM ?? '');
      item.zcj = String(r.ZCJ ?? '');
      item.xf = String(r.XF ?? '');
      item.xgxklbdmDisplay = String(r.XGXKLBDM_DISPLAY ?? '');
      item.sfjg = String(r.SFJG ?? '');
      item.kclbdmDisplay = String(r.KCLBDM_DISPLAY ?? '');
      item.cxckdmDisplay = String(r.CXCKDM_DISPLAY ?? '');
      item.djcjlxdmDisplay = String(r.DJCJLXDM_DISPLAY ?? '');
      item.jxbid = String(r.JXBID ?? '');
      out.push(item);
    }
    return out;
  }
}