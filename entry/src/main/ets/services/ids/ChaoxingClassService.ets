// ChaoxingClassService.ets — 超星（学习通）课表服务
//
// 背景：西电本科生课表已从 ehall 教务（/jwapp/sys/wdkb/modules/xskcb/xskcb.do）迁移到
// 超星课表 kb.chaoxing.com。ehall 旧接口仍返回 200，但 datas 是空壳（新学期没有任何课程行），
// 校内官方 App 也已改为内嵌 kb.chaoxing.com 的 H5。因此本科生课表改由本服务提供；
// 研究生课表仍走 yjspt（ClassService 内按 role 分流）。
//
// 打通登录（不弹独立学习通账号）：
//   复用 App 内考勤/头像/座位现成的「西电 CAS → 超星 SSO」桥
//   （AttendanceService.loginToLearning：ids.xidian.edu.cn CAS service =
//    xdspoc.fanya.chaoxing.com/sso/xdspoc，CAS 白名单内）。SSO 成功后超星会在
//   .chaoxing.com 域种下 UID/vc3/uf 等会话 cookie —— 与 kb.chaoxing.com 同一账号体系，
//   因此把会话 cookie 搬运并固化到父域后，课表接口即可直接使用，无需用户再输学习通密码。
//   ⚠️ 关键一步：SSO 会话默认落在 SPOC 组织 fid=146332（该组织 kb 无课表，lessonArray
//   恒空，但接口仍返回 200+JSON，早先误判为"打通成功"）；本科生课表挂在超星主校
//   fid=16820。必须在拉课表前 GET i.chaoxing.com/base?fid=16820 把当前学校切到主校
//   （switchToMainFid），否则整学期拉回来都是 0 条。官方「学在西电」App 同样以
//   fid=16820 会话访问 kb（其日志 cookie：fid=16820 / sso_schooltime 多组织）。
//
// 接口（已实测通过）：
//   1) GET  https://passport2.chaoxing.com/login?newversion=true      拿初始 cookie
//   2) POST https://passport2.chaoxing.com/fanyalogin                 提交 AES 加密凭据
//      form: fid=-1 & uname=<base64(AES-CBC)> & password=<base64(AES-CBC)> & t=true
//            & forbidotherlogin=0 & validate=
//      AES-128-CBC / PKCS5，key 与 iv 均为 u2oh6Vu^HWe4_AES
//      成功响应：{"url":"http://i.mooc.chaoxing.com","status":true}
//   3) GET  https://kb.chaoxing.com/pc/curriculum/getMyLessons?week=N 取第 N 周课表
//      Referer 需带 https://kb.chaoxing.com/res/pc/curriculum/schedule.html
//      data.curriculum：maxWeek / schoolYear / semester / firstWeekDate / lessonTimeConfigArray
//      data.lessonArray[]：name / teacherName / location / dayOfWeek(1-7) / beginNumber /
//                          length / courseId / classId / courseNo
//   （fanyalogin 仅作备用：若学校 SSO 账号与课表账号不一致时才需手动登录）
//
// 输出：与 ehall 同构的 JSON —— datas.xskcb.rows[]（KCM/KCH/KXH/SKXQ/SKZC/KSJC/JSJC/SKJS/JASMC）。
// 这样 ClassService.parseClassTable、ClassTablePage.renderClassTable、实验/考试合并、
// 日历导出等既有链路全部不需要改动。

import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SecureStorageUtil, SecureAlias } from '../../utils/SecureStorageUtil';
import { SerializedClassRow, ClassTableRawWrapper } from '../../models/common/Models';
import { CasLoginService } from '../auth/CasLoginService';
import { AttendanceService } from './AttendanceService';
import cryptoFramework from '@ohos.security.cryptoFramework';

const CX_TAG: string = 'ChaoxingClassService';

const CX_LOGIN_PAGE: string = 'https://passport2.chaoxing.com/login?newversion=true';
const CX_LOGIN_API: string = 'https://passport2.chaoxing.com/fanyalogin';
const CX_KB_API: string = 'https://kb.chaoxing.com/pc/curriculum/getMyLessons';
const CX_AES_KEY: string = 'u2oh6Vu^HWe4_AES';
const CX_REFERER: string = 'https://kb.chaoxing.com/res/pc/curriculum/schedule.html';

// 超星"一账号多学校"：西电 CAS→xdspoc SSO 建立的会话默认落在 SPOC 组织 fid=146332，
// 该组织在 kb.chaoxing.com 没有课表（lessonArray 恒空）；本科生课表挂在超星主校 fid=16820。
// GET i.chaoxing.com/base?fid=16820 会把当前学校切到主校（服务端 Set-Cookie: fid=16820），
// kb 接口随即返回真实课表 —— 2026-09-06 实测：切校前第1周 0 条，切校后 11 条，周1-6 共 16 门/69 行。
const CX_MAIN_FID: string = '16820';
const CX_SWITCH_URL: string = 'https://i.chaoxing.com/base?fid=' + CX_MAIN_FID;

// 课表网格最大节次（与 ClassTablePage 的 SECTION_COUNT 一致），超星最多 12 小节需截断
const CX_MAX_SECTION: number = 11;

// 周次请求并发数：超星按周出数据，整学期需 maxWeek 次请求，5 路并发平衡耗时与服务端压力
const CX_CONCURRENCY: number = 5;

const CX_UA: string =
  'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

// 未取到 maxWeek 时的兜底周数
const CX_FALLBACK_MAX_WEEK: number = 20;

// ===== 偏好键 =====
const PREF_CX_LOGGED_IN: string = 'cx_logged_in';
const PREF_CX_ACCOUNT: string = 'cx_account';
const PREF_CX_LOGIN_TIME: string = 'cx_login_time';
const PREF_CX_MAX_WEEK: string = 'cx_max_week';

// 抛给上层的会话缺失错误标识（上层据此提示登录而非"网络错误"）
const CX_ERR_NEED_LOGIN: string = 'CX_NEED_LOGIN';

function cxHeaders(referer: string): Record<string, string> {
  const h: Record<string, string> = {
    'User-Agent': CX_UA,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9'
  };
  if (referer.length > 0) {
    h['Referer'] = referer;
  }
  return h;
}

function cxStrToU8(s: string): Uint8Array {
  const buf: number[] = [];
  for (let i: number = 0; i < s.length; i++) {
    buf.push(s.charCodeAt(i) & 0xFF);
  }
  return new Uint8Array(buf);
}

function cxBase64Encode(u8: Uint8Array): string {
  const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result: string = '';
  for (let i: number = 0; i < u8.length; i += 3) {
    const b0: number = u8[i];
    const b1: number = i + 1 < u8.length ? u8[i + 1] : 0;
    const b2: number = i + 2 < u8.length ? u8[i + 2] : 0;
    result += chars.charAt((b0 >> 2) & 0x3F);
    result += chars.charAt(((b0 << 4) | (b1 >> 4)) & 0x3F);
    result += i + 1 < u8.length ? chars.charAt(((b1 << 2) | (b2 >> 6)) & 0x3F) : '=';
    result += i + 2 < u8.length ? chars.charAt(b2 & 0x3F) : '=';
  }
  return result;
}

// AES-128-CBC + PKCS5，key 与 iv 相同（与超星 H5 前端 encryptByAES 一致）
async function cxAesEncrypt(plaintext: string): Promise<string> {
  const keyData: cryptoFramework.DataBlob = { data: cxStrToU8(CX_AES_KEY) };
  const iv: cryptoFramework.DataBlob = { data: cxStrToU8(CX_AES_KEY) };
  const gen = cryptoFramework.createSymKeyGenerator('AES128');
  const symKey: cryptoFramework.SymKey = await gen.convertKey(keyData);
  const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS5');
  const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: iv } as cryptoFramework.IvParamsSpec;
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
  const input: cryptoFramework.DataBlob = { data: cxStrToU8(plaintext) };
  const output: cryptoFramework.DataBlob = await cipher.doFinal(input);
  return cxBase64Encode(output.data);
}

function cxStr(obj: Record<string, Object>, key: string): string {
  const v: Object | undefined = obj[key];
  if (v === undefined || v === null) {
    return '';
  }
  return String(v);
}

function cxNum(obj: Record<string, Object>, key: string): number {
  const v: Object | undefined = obj[key];
  if (v === undefined || v === null) {
    return 0;
  }
  const n: number = Number(v);
  return isNaN(n) ? 0 : n;
}

// 单门课的一个"时间槽"（同一门课每周固定落在同一格）
export class CxLesson {
  name: string = '';
  teacherName: string = '';
  location: string = '';
  dayOfWeek: number = 0;      // 1-7
  beginNumber: number = 0;    // 起始小节
  length: number = 1;         // 连上几小节
  courseId: string = '';
  classId: string = '';
  courseNo: string = '';
}

class CxSlot {
  lesson: CxLesson = new CxLesson();
  weeks: boolean[] = [];
}

class CxCurriculum {
  maxWeek: number = 0;
  schoolYear: number = 0;
  semester: number = 0;
  firstWeekDate: number = 0;  // 毫秒时间戳
}

export class ChaoxingClassService {
  private static inst: ChaoxingClassService;
  private http: HttpUtil = HttpUtil.getInstance();

  static getInstance(): ChaoxingClassService {
    if (!ChaoxingClassService.inst) {
      ChaoxingClassService.inst = new ChaoxingClassService();
    }
    return ChaoxingClassService.inst;
  }

  // ===== 登录态 =====

  /** 是否已打标"超星会话就绪"（SSO 打通或手动登录成功后置位） */
  static isLoggedIn(): boolean {
    return PreferenceUtil.getBool(PREF_CX_LOGGED_IN, false);
  }

  /** 主站域是否存在有效会话 cookie（UID 等），跨启动也能判断 */
  static hasKbSession(): boolean {
    const http: HttpUtil = HttpUtil.getInstance();
    const domains: string[] = ['chaoxing.com', '.chaoxing.com', 'i.chaoxing.com',
      'passport2.chaoxing.com', 'kb.chaoxing.com', 'fanya.chaoxing.com',
      'xdspoc.fanya.chaoxing.com'];
    for (let i: number = 0; i < domains.length; i++) {
      const c: string = http.getCookiesForDomain(domains[i]);
      if (c.length > 0 && c.indexOf('UID=') >= 0) {
        return true;
      }
    }
    return false;
  }

  static getAccount(): string {
    return PreferenceUtil.getString(PREF_CX_ACCOUNT, '');
  }

  static getMaxWeek(): number {
    return PreferenceUtil.getNumber(PREF_CX_MAX_WEEK, 0);
  }

  static async logout(): Promise<void> {
    await PreferenceUtil.putBool(PREF_CX_LOGGED_IN, false);
    await PreferenceUtil.delete(PREF_CX_LOGIN_TIME);
    await SecureStorageUtil.remove(SecureAlias.CHAOXING_PASSWORD);
    HttpUtil.getInstance().clearCookies('chaoxing.com');
    HttpUtil.getInstance().clearCookies('.chaoxing.com');
    HttpUtil.getInstance().clearCookies('passport2.chaoxing.com');
    HttpUtil.getInstance().clearCookies('kb.chaoxing.com');
    HttpUtil.getInstance().clearCookies('i.chaoxing.com');
  }

  /**
   * 确保超星会话处于"主校 fid=16820"上下文（幂等，可重复调用）。
   * 西电 CAS→xdspoc SSO 建立的会话默认落在 SPOC 组织 fid=146332，该组织在
   * kb.chaoxing.com 没有课表数据；本科生课表挂在超星主校 16820。
   * i.chaoxing.com/base?fid=16820 会让服务端把当前会话切到主校。
   * ⚠️ 不在此处改写共享 cookie 存储：fid 若被写进 chaoxing.com/.chaoxing.com 父域，
   * 考勤(fycourse.fanya)/移动端等 SPOC 子域请求经父域匹配也会读到 16820，造成串扰。
   * kb 请求自身所需的 fid=16820 由 fetchWeek 的请求头显式携带（见 fetchWeek）。
   * 失败仅告警不阻断（保持旧行为，由上层空数据兜底）。
   */
  private async switchToMainFid(): Promise<void> {
    try {
      const resp: HttpResponse = await this.http.get(CX_SWITCH_URL, cxHeaders('https://i.chaoxing.com'));
      if (!resp.isOk) {
        console.warn('[' + CX_TAG + '] 切校 fid=' + CX_MAIN_FID + ' 响应异常 http=' + resp.statusCode);
        return;
      }
      console.info('[' + CX_TAG + '] 已切换超星主校 fid=' + CX_MAIN_FID);
    } catch (e) {
      console.warn('[' + CX_TAG + '] 切校 fid=' + CX_MAIN_FID + ' 失败: ' + String(e));
    }
  }

  // ===== 学校账号打通（西电 CAS → 超星 SSO）=====
  // 复用 App 内考勤/头像/座位现成的打通链：西电 CAS（TGC）→ ids.xidian.edu.cn
  // authserver/login?service=xdspoc.fanya.chaoxing.com/sso/xdspoc（CAS 白名单）→ 302 回
  // 超星 SSO → 种下 .chaoxing.com 会话 cookie。再把会话搬运/固化到父域，kb.chaoxing.com
  // 即与考勤/头像同一会话，无需单独的学习通账号。
  // 成功与否以「直接探测 kb 课表接口」为准，而不是只认 cookie 名（SSO 会话 cookie
  // 组合可能随超星版本变化，UID 未必必然出现）。
  // 返回：0=会话就绪，1=未登录西电（无法 SSO），2=打通失败（网络/会话异常/账号不匹配）
  async ensureSessionViaCas(force: boolean = false): Promise<number> {
    if (!force && ChaoxingClassService.hasKbSession()) {
      return 0;
    }
    // 1) 西电 CAS 登录态（无 TGC 时静默尝试恢复；失败则要求用户先登录西电账号）
    const casOk: boolean = await CasLoginService.getInstance().tryAutoRestoreLogin();
    if (!casOk) {
      return 1;
    }
    // 2) 复用考勤 SSO 打通入口（内部已容错最后一跳失败）
    try {
      await AttendanceService.getInstance().loginToLearning();
    } catch (_e) { /* 容错：cookie 可能已建立 */ }
    // 3) 把超星各子域会话 cookie 搬运到主站域（含课表域）
    const srcDomains: string[] = ['fanya.chaoxing.com', 'xdspoc.fanya.chaoxing.com',
      'fycourse.fanya.chaoxing.com', 'mobilelearn.chaoxing.com', 'ids.xidian.edu.cn'];
    const dstDomains: string[] = ['chaoxing.com', '.chaoxing.com', 'i.chaoxing.com',
      'passport2.chaoxing.com', 'kb.chaoxing.com'];
    for (let si: number = 0; si < srcDomains.length; si++) {
      for (let di: number = 0; di < dstDomains.length; di++) {
        this.http.copyCookiesForDomain(srcDomains[si], dstDomains[di]);
      }
    }
    // 4) 固化到 chaoxing.com 父域并落盘（copyCookiesForDomain 只改内存，重启后会丢）
    const merged: string[] = [];
    const mergeDomains: string[] = ['passport2.chaoxing.com', 'i.chaoxing.com', 'kb.chaoxing.com',
      'fanya.chaoxing.com', 'mobilelearn.chaoxing.com', 'xdspoc.fanya.chaoxing.com',
      'fycourse.fanya.chaoxing.com', 'chaoxing.com', '.chaoxing.com'];
    for (let mi: number = 0; mi < mergeDomains.length; mi++) {
      const c: string = this.http.getAllCookies(mergeDomains[mi]);
      if (c.length > 0) {
        merged.push(c);
      }
    }
    try {
      await this.http.injectCookies(merged.join('; '), 'chaoxing.com');
    } catch (e) {
      console.warn('[' + CX_TAG + '] 固化超星 cookie 失败: ' + String(e));
    }
    // 4.5) SSO 会话默认落在 SPOC 组织 fid=146332（kb 无课表），先切到主校 fid=16820
    await this.switchToMainFid();
    // 5) 直接探测 kb 课表：week=1 能返回 JSON 才算打通成功
    const probe: Record<string, Object> | null = await this.fetchWeek(1);
    if (probe !== null) {
      await PreferenceUtil.putBool(PREF_CX_LOGGED_IN, true);
      return 0;
    }
    return 2;
  }

  /**
   * 登录学习通。返回空串表示成功，否则返回可直接展示给用户的错误文案。
   */
  async login(uname: string, pwd: string): Promise<string> {
    if (uname.length === 0 || pwd.length === 0) {
      return '请输入学习通账号和密码';
    }
    try {
      // 1) 打开登录页，拿 JSESSIONID / route 初始 cookie
      await this.http.get(CX_LOGIN_PAGE, cxHeaders(''));
      // 2) 提交加密后的凭据
      const form: Record<string, string> = {
        'fid': '-1',
        'uname': await cxAesEncrypt(uname),
        'password': await cxAesEncrypt(pwd),
        't': 'true',
        'forbidotherlogin': '0',
        'validate': ''
      };
      const resp: HttpResponse = await this.http.postForm(CX_LOGIN_API, form, cxHeaders(CX_LOGIN_PAGE));
      const body: string = resp.body;
      const brace: number = body.indexOf('{');
      if (brace < 0) {
        return '登录失败：服务器返回异常';
      }
      const obj: Record<string, Object> = JSON.parse(body.substring(brace)) as Record<string, Object>;
      const rawStatus: Object | undefined = obj['status'];
      const ok: boolean = rawStatus === true || String(rawStatus) === 'true' || String(rawStatus) === '1';
      if (!ok) {
        let msg: string = cxStr(obj, 'msg2');
        if (msg.length === 0) {
          msg = cxStr(obj, 'mes');
        }
        if (msg.length === 0) {
          msg = cxStr(obj, 'msg');
        }
        return msg.length > 0 ? msg : '登录失败：账号或密码错误';
      }
      // 3) 把 passport2 子域的会话 cookie 提升到 chaoxing.com 父域并落盘，
      //    否则 kb.chaoxing.com 取不到 UID/vc3 等凭证（父域匹配才命中）
      const cookieStr: string = this.http.getAllCookies('passport2.chaoxing.com');
      await this.http.injectCookies(cookieStr, 'chaoxing.com');
      await PreferenceUtil.putBool(PREF_CX_LOGGED_IN, true);
      await PreferenceUtil.putString(PREF_CX_ACCOUNT, uname);
      await PreferenceUtil.putNumber(PREF_CX_LOGIN_TIME, Date.now());
      await SecureStorageUtil.put(SecureAlias.CHAOXING_PASSWORD, pwd);
      return '';
    } catch (e) {
      console.warn('[' + CX_TAG + '] login failed: ' + String(e));
      return '登录失败：' + String(e);
    }
  }

  // ===== 拉课表 =====

  /** 取某一周的原始数据；未登录/失败返回 null */
  private async fetchWeek(week: number): Promise<Record<string, Object> | null> {
    try {
      const h: Record<string, string> = cxHeaders(CX_REFERER);
      // kb 按当前 fid cookie 决定返回哪个学校的课表：SSO 会话默认 fid=146332（SPOC 组织，
      // lessonArray 恒空但接口 200）。这里在请求头显式覆盖为超星主校 fid=16820 —— 用
      // skipCookies 跳过共享存储自动注入，手动拼 Cookie，避免把 fid=16820 写进父域存储
      // 污染考勤(fycourse)等 SPOC 子域会话（它们经父域匹配会读到错误 fid）。
      const jar: string = this.http.getCookiesForDomain('kb.chaoxing.com');
      const kept: string[] = [];
      const parts: string[] = jar.split(';');
      for (let pi: number = 0; pi < parts.length; pi++) {
        const t: string = parts[pi].trim();
        if (t.length > 0 && !t.startsWith('fid=')) {
          kept.push(t);
        }
      }
      let cookie: string = kept.join('; ');
      if (cookie.length > 0) {
        cookie += '; ';
      }
      cookie += 'fid=' + CX_MAIN_FID;
      h['cookie'] = cookie;
      const resp: HttpResponse = await this.http.get(CX_KB_API + '?week=' + week, h, true);
      if (!resp.isOk) {
        return null;
      }
      const body: string = resp.body.trimStart();
      // 未登录时超星会回落到 HTML 登录页，此时不能当成"空课表"
      if (!body.startsWith('{')) {
        return null;
      }
      const obj: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
      const data: Object | undefined = obj['data'];
      if (data === undefined || data === null || typeof data !== 'object') {
        return null;
      }
      return data as Record<string, Object>;
    } catch (e) {
      console.warn('[' + CX_TAG + '] fetchWeek ' + week + ' failed: ' + String(e));
      return null;
    }
  }

  private parseCurriculum(data: Record<string, Object>): CxCurriculum {
    const c: CxCurriculum = new CxCurriculum();
    const curObj: Object | undefined = data['curriculum'];
    if (curObj === undefined || curObj === null || typeof curObj !== 'object') {
      return c;
    }
    const m: Record<string, Object> = curObj as Record<string, Object>;
    c.maxWeek = cxNum(m, 'maxWeek');
    c.schoolYear = cxNum(m, 'schoolYear');
    c.semester = cxNum(m, 'semester');
    c.firstWeekDate = cxNum(m, 'firstWeekDate');
    return c;
  }

  private parseLessons(data: Record<string, Object>): CxLesson[] {
    const out: CxLesson[] = [];
    const arrObj: Object | undefined = data['lessonArray'];
    if (arrObj === undefined || arrObj === null || !Array.isArray(arrObj)) {
      return out;
    }
    const arr: Object[] = arrObj as Object[];
    for (const it of arr) {
      if (it === null || typeof it !== 'object') {
        continue;
      }
      const m: Record<string, Object> = it as Record<string, Object>;
      const l: CxLesson = new CxLesson();
      l.name = cxStr(m, 'name');
      l.teacherName = cxStr(m, 'teacherName');
      l.location = cxStr(m, 'location');
      l.dayOfWeek = cxNum(m, 'dayOfWeek');
      l.beginNumber = cxNum(m, 'beginNumber');
      l.length = cxNum(m, 'length');
      l.courseId = cxStr(m, 'courseId');
      l.classId = cxStr(m, 'classId');
      l.courseNo = cxStr(m, 'courseNo');
      if (l.length <= 0) {
        l.length = 1;
      }
      out.push(l);
    }
    return out;
  }

  private saveTermStart(cur: CxCurriculum): void {
    if (cur.maxWeek > 0) {
      PreferenceUtil.putNumber(PREF_CX_MAX_WEEK, cur.maxWeek);
    }
    if (cur.firstWeekDate <= 0) {
      return;
    }
    const d: Date = new Date(cur.firstWeekDate);
    const y: number = d.getFullYear();
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const mm: string = m < 10 ? '0' + m : String(m);
    const dd: string = day < 10 ? '0' + day : String(day);
    // 供 SemesterUtil.getSemesterStartDate 使用（内部会校验学年/月份合理性）
    PreferenceUtil.putString('semester_start_date', y + '-' + mm + '-' + dd);
  }

  /** 拉取整学期课表，返回与 ehall 同构的 raw JSON */
  async fetchClassTableRaw(): Promise<string> {
    // 会话预检：无有效超星会话时先走西电账号打通（SSO），全程无感，不弹学习通登录
    if (!ChaoxingClassService.hasKbSession()) {
      const r: number = await this.ensureSessionViaCas();
      if (r !== 0) {
        throw new Error(CX_ERR_NEED_LOGIN);
      }
    }
    // 会话预检后统一切到主校 fid=16820：考勤/头像等其他模块刷新 SSO 会话可能把 fid
    // 重置回 146332（SPOC 组织无课表），故每次拉课表前都幂等切校，确保 kb 读到主校数据。
    await this.switchToMainFid();
    let first: Record<string, Object> | null = await this.fetchWeek(1);
    if (first === null) {
      // 会话可能已失效：强制重新打通一次并重试（force 跳过"有陈旧 cookie 就早退"，
      // 否则上一步刚建/遗留的失效 cookie 会让 ensureSessionViaCas 直接返回 0 而不重打）
      await this.ensureSessionViaCas(true);
      await this.switchToMainFid();
      first = await this.fetchWeek(1);
    }
    if (first === null) {
      throw new Error(CX_ERR_NEED_LOGIN);
    }
    const cur: CxCurriculum = this.parseCurriculum(first);
    const maxWeek: number = cur.maxWeek > 0 ? cur.maxWeek : CX_FALLBACK_MAX_WEEK;
    this.saveTermStart(cur);

    const weekMap: Map<number, CxLesson[]> = new Map();
    weekMap.set(1, this.parseLessons(first));
    for (let start: number = 2; start <= maxWeek; start += CX_CONCURRENCY) {
      const end: number = Math.min(start + CX_CONCURRENCY - 1, maxWeek);
      const tasks: Promise<void>[] = [];
      for (let k: number = start; k <= end; k++) {
        const wk: number = k;
        const p: Promise<void> = this.fetchWeek(wk).then((d: Record<string, Object> | null) => {
          if (d !== null) {
            weekMap.set(wk, this.parseLessons(d));
          }
        });
        tasks.push(p);
      }
      await Promise.all(tasks);
    }

    // 按"时间槽"聚合，把出现的周次压成 SKZC 位串
    const slots: Map<string, CxSlot> = new Map();
    const keys: string[] = [];
    for (let w: number = 1; w <= maxWeek; w++) {
      const arr: CxLesson[] | undefined = weekMap.get(w);
      if (arr === undefined) {
        continue;
      }
      for (const l of arr) {
        const key: string =
          l.courseId + '_' + l.classId + '_' + l.dayOfWeek + '_' + l.beginNumber + '_' + l.length;
        let slot: CxSlot | undefined = slots.get(key);
        if (slot === undefined) {
          slot = new CxSlot();
          slot.lesson = l;
          for (let i: number = 0; i < maxWeek; i++) {
            slot.weeks.push(false);
          }
          slots.set(key, slot);
          keys.push(key);
        }
        if (w - 1 < slot.weeks.length) {
          slot.weeks[w - 1] = true;
        }
      }
    }

    const rows: SerializedClassRow[] = [];
    for (const key of keys) {
      const slot: CxSlot | undefined = slots.get(key);
      if (slot === undefined) {
        continue;
      }
      const l: CxLesson = slot.lesson;
      if (l.dayOfWeek < 1 || l.dayOfWeek > 7 || l.beginNumber < 1) {
        continue;
      }
      let skzc: string = '';
      for (let i: number = 0; i < slot.weeks.length; i++) {
        skzc += slot.weeks[i] ? '1' : '0';
      }
      // 超星最多 12 小节，HiXD 网格只有 11 节，超出部分截断
      let endSec: number = l.beginNumber + l.length - 1;
      if (endSec > CX_MAX_SECTION) {
        endSec = CX_MAX_SECTION;
      }
      if (endSec < l.beginNumber) {
        endSec = l.beginNumber;
      }
      const row: SerializedClassRow = {
        KCM: l.name,
        KCH: l.courseNo,
        KXH: l.classId,
        SKXQ: String(l.dayOfWeek),
        SKZC: skzc,
        KSJC: String(l.beginNumber),
        JSJC: String(endSec),
        SKJS: l.teacherName,
        JASMC: l.location
      };
      rows.push(row);
    }

    const wrapper: ClassTableRawWrapper = { datas: { xskcb: { rows: rows } } };
    console.info('[' + CX_TAG + '] 课表聚合完成：' + rows.length + ' 条 / ' + maxWeek + ' 周');
    return JSON.stringify(wrapper);
  }

  /** 用已保存的凭据静默重登（凭据存在 SecureStorage） */
  async reloginIfPossible(): Promise<string> {
    const account: string = ChaoxingClassService.getAccount();
    if (account.length === 0) {
      return '';
    }
    const pwd: string = await SecureStorageUtil.get(SecureAlias.CHAOXING_PASSWORD);
    if (pwd.length === 0) {
      return '';
    }
    return this.login(account, pwd);
  }
}
