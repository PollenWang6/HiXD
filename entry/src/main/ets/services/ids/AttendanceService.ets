// AttendanceService.ets — 超星学习平台考勤数据服务
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { ClassAttendance, ClassAttendanceDetail } from '../../models/ids/AttendanceModels';
import { PreferenceUtil } from '../../utils/PreferenceUtil';

const TAG: string = 'AttendanceService';

// 超星 SSO 登录入口（西电 → 超星）
const LOGIN_URL: string = 'https://xdspoc.fanya.chaoxing.com/sso/xdspoc';
// 课程列表页（HTML）
const COURSE_INFO_URL: string = 'https://fycourse.fanya.chaoxing.com/courselist/study?v=1';
// 考勤数据表（HTML）
const COURSE_DATA_URL: string = 'https://fycourse.fanya.chaoxing.com/courselist/studyCourseDatashow';
// 签到详情（JSON API）
const COURSE_DETAIL_URL: string = 'https://mobilelearn.chaoxing.com/v2/apis/signStat/getActiveList';

// 课程信息类（不用 interface，避免 arkts-no-structural-typing）
class CourseInfo {
  courseId: string = '';
  clazzId: string = '';
  cpi: string = '';
  courseName: string = '';
  className: string = '';
}

// 拼接查询参数到 URL
function buildUrl(base: string, params: Record<string, string>): string {
  const pairs: string[] = [];
  const keys: string[] = Object.keys(params);
  for (let i = 0; i < keys.length; i++) {
    const k: string = keys[i];
    const v: string = params[k];
    pairs.push(encodeURIComponent(k) + '=' + encodeURIComponent(v));
  }
  if (pairs.length > 0) {
    return base + '?' + pairs.join('&');
  }
  return base;
}

export class AttendanceService {
  private static instance: AttendanceService;
  private http: HttpUtil = HttpUtil.getInstance();
  private semesterCode: string = '';
  // SSO 会话建立互斥锁（对齐 MainPage 启动串行化 / SessionGuard.inFlight）：
  // 主页预加载（HomeDataProvider）与考勤页 loadData 可能并发进入 getAttendanceRecords，
  // 各自 ensureLogin→loginToLearning 会共享无锁 cookie 罐互相覆盖（超星会话损坏 →
  // 数据页恒返空壳），必须让登录段串行。
  private ssoLock: Promise<void> | null = null;

  static getInstance(): AttendanceService {
    if (!AttendanceService.instance) {
      AttendanceService.instance = new AttendanceService();
    }
    return AttendanceService.instance;
  }

  // 串行化 SSO 会话建立：并发调用只真正登录一次，其余等待同一结果
  // （对齐 SessionGuard.ensureLoggedIn 的 inFlight 合并锁哲学）
  private async ensureLoginSerialized(): Promise<void> {
    if (this.ssoLock) {
      await this.ssoLock;
      return;
    }
    const p: Promise<void> = this.ensureLogin().catch(() => {});
    this.ssoLock = p;
    try {
      await p;
    } finally {
      if (this.ssoLock === p) {
        this.ssoLock = null;
      }
    }
  }

  // 检查是否已登录超星
  async isLogin(): Promise<boolean> {
    try {
      const checkUrl: string = buildUrl(COURSE_DETAIL_URL, {
        'classId': '123',
        'courseId': '1',
        'page': '1',
        'pageSize': '999',
        'puid': ''
      });
      const resp: HttpResponse = await this.http.get(checkUrl);
      const body: string = resp.body;
      // 登录态判定：未登录响应含"请登录/未登录"类文案。
      // 超星文案会随版本变化（"请登录后再试" / "未登录或已过期" 等），用关键字集合兜底，
      // 避免旧版精确匹配"请登录后再试"在新版下误判为已登录、跳过 SSO 导致半登录态拉课失败。
      if (body.indexOf('请登录') >= 0 || body.indexOf('未登录') >= 0 || body.indexOf('登录后再试') >= 0) {
        console.info('[Att] isLogin: 未登录提示: ' + body.substring(0, 120));
        return false;
      }
      return true;
    } catch (_e) {
      return false;
    }
  }

  // SSO 登录到超星学习平台
  // 参照 Flutter checkAndLogin：直接请求 CAS service URL，利用已有 TGC 自动重定向到超星。
  // 手动逐跳跟随（rcp autoRedirect:false）：最后一跳页面请求失败（如 /portal 偶发
  // "Server returned nothing"）也容忍——cookie 已在此前各跳的 Set-Cookie 中建立，登录态不受影响。
  async loginToLearning(): Promise<void> {
    const casUrl: string = 'https://ids.xidian.edu.cn/authserver/login?service=' +
      encodeURIComponent(LOGIN_URL);
    try {
      let currentUrl: string = casUrl;
      let resp: HttpResponse = await this.http.getNoRedirect(casUrl);
      let guard: number = 0;
      while (resp.isRedirect && resp.location && guard < 10) {
        let location: string = resp.location;
        const baseCk: RegExpMatchArray | null = currentUrl.match(/^(https?:\/\/[^\/]+)/);
        if (baseCk) {
          const base: string = baseCk[1];
          if (!location.startsWith('http://') && !location.startsWith('https://')) {
            location = base + (location.startsWith('/') ? location : '/' + location);
          }
        }
        currentUrl = location;
        try {
          resp = await this.http.getNoRedirect(location);
        } catch (_e) {
          break; // 最后一跳失败容忍：cookie 已建立
        }
        guard++;
      }
    } catch (_e) {
      // 首跳失败不致命，交由调用方判断
    }

    // 跨子域复制 cookie：超星在 xdspoc.fanya.chaoxing.com 设的 cookie 需同步到 fycourse.fanya.chaoxing.com
    const srcDomains: string[] = ['xdspoc.fanya.chaoxing.com', 'ids.xidian.edu.cn', 'fanya.chaoxing.com'];
    const dstDomains: string[] = [
      'fycourse.fanya.chaoxing.com',
      'mobilelearn.chaoxing.com',
      'xdspoc.fanya.chaoxing.com',
      'fanya.chaoxing.com',
      'mh.chaoxing.com'
    ];
    for (let si = 0; si < srcDomains.length; si++) {
      for (let di = 0; di < dstDomains.length; di++) {
        this.http.copyCookiesForDomain(srcDomains[si], dstDomains[di]);
      }
    }
  }

  // 确保登录状态
  async ensureLogin(): Promise<void> {
    if (await this.isLogin()) {
      return;
    }
    await this.loginToLearning();
  }

  // 去掉 HTML 标签辅助
  private stripTags(s: string): string {
    return s.replace(/<[^>]+>/g, '').trim();
  }

  /**
   * 当前学期超星期码（YYYYN，如 20261 = 2026-2027 第一学期）兜底。
   * 真机常态课程页（~80KB 变体，多节点渲染）的 yearList option 全不带 selected，
   * 网页 JS 无 selected 时默认取 value=0（全部课程）；但对考勤页而言用户要的是「只看本学期」，
   * 故解析不到 selected 时回退当前学期码，而不是空串（空串=98 门全学期混排，2026-09-06 实锤）。
   * 优先用 ehall 权威 current_semester 偏好（格式 YYYY-YYYY-N），无则按日期推导。
   */
  private currentChaoxingSemester(): string {
    let year: number = 0;
    let term: number = 0;
    const saved: string = PreferenceUtil.getString('current_semester');
    if (saved.length > 0) {
      const p: string[] = saved.split('-');
      if (p.length >= 3) {
        year = parseInt(p[0]);
        term = parseInt(p[2]);
      }
    }
    if (isNaN(year) || isNaN(term)) {
      const now = new Date();
      const y: number = now.getFullYear();
      const m: number = now.getMonth() + 1;
      if (m >= 9) {
        year = y;
        term = 1;
      } else if (m >= 2) {
        year = y - 1;
        term = 2;
      } else if (m === 1) {
        year = y - 1;
        term = 1;
      } else {
        year = y - 1;
        term = 2; // 8月：上一年春季
      }
    }
    return String(year * 10 + term);
  }

  // ===== 解析课程列表 HTML =====
  private parseCourseInfo(html: string): CourseInfo[] {
    const results: CourseInfo[] = [];
    const seen: Set<string> = new Set();

    // 预处理：剥离 script / style。这两类节点体积大且与解析无关，
    // 若留在 HTML 尾部会被课程块正则（前瞻以 $ 兜底）整段吞入，
    // 使后续正则在超长字符串上空转，曾引发主线程卡死（appfreeze THREAD_BLOCK_6S）
    const cleaned: string = html
      .replace(/<script\b[^>]*>([\s\S]*?)<\/script>/gi, '')
      .replace(/<style\b[^>]*>([\s\S]*?)<\/style>/gi, '');

    // 提取学期：新版 <select id="yearList"> 找 selected option；旧版 li 上的 semesterNum 属性
    // 【2026-09-06 实锤】真机常态课程页（~80KB 多节点变体）yearList 27 个 option 全不带 selected →
    // 原逻辑 semesterCode='' → semesternum 空 → 拉回全部学期 98 门混排（用户最初抱怨的"混学期"）。
    // 修复：无 selected 时回退当前学期码（currentChaoxingSemester），保证考勤只看本学期。
    const yearRe: RegExp = /<select[^>]*id="yearList"[^>]*>([\s\S]{0,20000}?)<\/select>/;
    const yearMatch = cleaned.match(yearRe);
    let diagOptCount: number = 0;       // yearList 内 option 数量（26=全量下拉 / 0=页面变体无下拉）
    let diagSelVal: string = '(none)';  // selected option 的 value
    let diagSemAttr: string = '(none)'; // 旧式 semesterNum 属性值
    if (yearMatch !== null) {
      const optRe: RegExp = /<option\b/g;
      let om: RegExpExecArray | null;
      while ((om = optRe.exec(yearMatch[1])) !== null) {
        diagOptCount++;
      }
      const selRe: RegExp = /<option[^>]*value="([^"]*)"[^>]*selected[^>]*>/;
      const selMatch = yearMatch[1].match(selRe);
      if (selMatch !== null && selMatch[1] !== '0') {
        this.semesterCode = selMatch[1];
        diagSelVal = selMatch[1];
      } else {
        this.semesterCode = this.currentChaoxingSemester();
        diagSelVal = selMatch !== null ? '(0→fallback)' : '(none→fallback)';
      }
    } else {
      // 旧版：semesterNum 属性
      const semM: RegExpMatchArray | null = cleaned.match(/semesterNum="(\d+)"/);
      if (semM !== null) {
        this.semesterCode = semM[1];
        diagSemAttr = semM[1];
      } else {
        // 连旧式 semesterNum 都没有（页面无学期控件）：同样兜底当前学期，避免全学期混排
        this.semesterCode = this.currentChaoxingSemester();
      }
    }
    console.info('[Att] diag: 课程页 len=' + cleaned.length +
      ' myde=' + (cleaned.indexOf('myde_course_item') >= 0) +
      ' yearList=' + (yearMatch !== null) +
      ' optCount=' + diagOptCount +
      ' selected=' + diagSelVal +
      ' semesterNumAttr=' + diagSemAttr +
      ' -> semesterCode=[' + this.semesterCode + ']');

    // 提取每个课程块：新版 div.myde_course_item / 旧版 li.zmy_item
    // 捕获长度设上限，避免前瞻的 $ 兜底把整个 HTML 尾部吞进来
    const blockRe: RegExp = /<(?:div|li)\b[^>]*(?:myde_course_item|zmy_item)[^>]*>([\s\S]{0,4000}?)(?=<(?:div|li)\b[^>]*(?:myde_course_item|zmy_item)|<\/?ul>|$)/g;
    // 推进语句写在 while 条件里，保证循环体内的 continue 也能正常推进（放循环体末尾会被 continue 跳过而死循环）
    let match: RegExpExecArray | null;
    while ((match = blockRe.exec(cleaned)) !== null) {
      const block: string = match[1];
      if (block.length === 0) continue;

      // cname
      const cnameM = block.match(/cname="([^"]*)"/);
      const cname: string = cnameM !== null ? cnameM[1].trim() : '';

      // dt 文本（课程名）
      const dtM = block.match(/<dt[^>]*>([\s\S]{0,2000}?)<\/dt>/);
      let courseName: string = '';
      if (cname.length > 0) {
        courseName = cname;
      } else if (dtM !== null) {
        courseName = this.stripTags(dtM[1]);
      }
      courseName = courseName.replace(/\s*\([^)]*\)\s*$/, '').trim();

      // dd[1] = 班级
      const ddList: string[] = [];
      const ddRe: RegExp = /<dd[^>]*>([\s\S]{0,2000}?)<\/dd>/g;
      let ddM = ddRe.exec(block);
      while (ddM !== null) {
        ddList.push(this.stripTags(ddM[1]));
        ddM = ddRe.exec(block);
      }
      const className: string = ddList.length >= 2 ? ddList[1] : '';

      // href → courseId / clazzId / cpi
      const hrefM = block.match(/<a\s[^>]*href="([^"]*)"[^>]*>/);
      let courseId: string = '';
      let clazzId: string = '';
      let cpi: string = '';
      if (hrefM !== null) {
        const href: string = hrefM[1];
        const cidM2 = href.match(/courseId=(\d+)/);
        const clidM2 = href.match(/clazzId=(\d+)/);
        const cpiM2 = href.match(/cpi=(\d+)/);
        if (cidM2 !== null) courseId = cidM2[1];
        if (clidM2 !== null) clazzId = clidM2[1];
        if (cpiM2 !== null) cpi = cpiM2[1];
      }

      // 兜底：cid
      if (courseId.length === 0) {
        const cidAlt = block.match(/cid="(\d+)"/);
        if (cidAlt !== null) courseId = cidAlt[1];
      }

      if (courseId.length === 0 || clazzId.length === 0) continue;

      const key: string = courseId + '|' + clazzId;
      if (seen.has(key)) continue;
      seen.add(key);

      const info: CourseInfo = new CourseInfo();
      info.courseId = courseId;
      info.clazzId = clazzId;
      info.cpi = cpi;
      info.courseName = courseName;
      info.className = className;
      results.push(info);
    }

    return results;
  }

  // ===== 解析考勤数据表 HTML =====
  private parseAttendanceTable(html: string, courseInfos: CourseInfo[]): ClassAttendance[] {
    const results: ClassAttendance[] = [];

    const tbodyRe: RegExp = /<tbody[^>]*>([\s\S]{0,500000}?)<\/tbody>/;
    const tbodyMatch = html.match(tbodyRe);
    if (tbodyMatch === null) {
      return results;
    }

    // 分割 tr
    const rows: string[] = [];
    const trRe: RegExp = /<tr[^>]*>([\s\S]{0,20000}?)<\/tr>/g;
    let trMatch = trRe.exec(tbodyMatch[1]);
    while (trMatch !== null) {
      rows.push(trMatch[1]);
      trMatch = trRe.exec(tbodyMatch[1]);
    }

    for (let i = 0; i < rows.length; i++) {
      const row: string = rows[i];
      const tdList: string[] = [];
      const tdRe: RegExp = /<td[^>]*>([\s\S]{0,2000}?)<\/td>/g;
      let tdM = tdRe.exec(row);
      while (tdM !== null) {
        tdList.push(this.stripTags(tdM[1]));
        tdM = tdRe.exec(row);
      }

      if (tdList.length < 17) continue;

      const att: ClassAttendance = new ClassAttendance();
      att.courseName = tdList[0];
      att.className = tdList[1];
      att.checkInCount = tdList[2];
      att.personalLeave = tdList[3];
      att.sickLeave = tdList[4];
      att.officialLeave = tdList[5];
      att.absenceCount = tdList[6];
      att.requiredCheckIn = tdList[7];
      att.attendanceRate = tdList[8];
      att.readCount = tdList[9];
      att.unreadCount = tdList[10];
      att.accessCount = tdList[11];
      att.taskProgress = tdList[12];
      att.homeworkProgress = tdList[13];
      att.examProgress = tdList[14];
      att.discussionCount = tdList[15];
      att.materialCount = tdList[16];

      // 匹配课程信息
      let matched: CourseInfo | null = null;
      for (let j = 0; j < courseInfos.length; j++) {
        const info: CourseInfo = courseInfos[j];
        if (info.courseName === att.courseName) {
          // 班级精确匹配优先；匹配不上时退化为课程名匹配（旧版页面班级字段可能对不上）
          if (info.className === att.className) {
            matched = info;
            break;
          }
          if (matched === null) {
            matched = info;
          }
        }
      }
      if (matched !== null) {
        att.courseId = matched.courseId;
        att.clazzId = matched.clazzId;
        att.cpi = matched.cpi;
      }

      results.push(att);
    }

    return results;
  }

  // ===== 主方法：获取考勤数据 =====
  async getAttendanceRecords(): Promise<ClassAttendance[]> {
    try {
      await this.ensureLoginSerialized();

      let courseInfos: CourseInfo[] = await this.fetchCourseInfos();
      if (courseInfos.length === 0) {
        return [];
      }

      let dataUrl: string = buildUrl(COURSE_DATA_URL, {
        'v': '1',
        'semesternum': this.semesterCode
      });
      console.info('[Att] diag: 请求考勤数据 semesternum=[' + this.semesterCode + ']');
      let dataResp: HttpResponse = await this.http.get(dataUrl);
      let cleanedHtml: string = dataResp.body.replace(/[\r\n\t]/g, '');
      let attendances: ClassAttendance[] = this.parseAttendanceTable(cleanedHtml, courseInfos);
      console.info('[Att] diag: 考勤数据页 len=' + cleanedHtml.length +
        ' 解析课程=' + courseInfos.length +
        ' 考勤行数=' + attendances.length);

      // ⚠️ 2026-09-06 二次修复（替代 ac71d63 的"重登+重拉数据页"）：
      // 课程能解析但数据页恒 1031B 空壳（考勤 0 行）的根因不是并发，而是【坏超星会话被服务端无限续用】：
      // 冷启动自动恢复会复用持久化旧会话 cookie（INGRESSCOOKIE 时间戳不变的铁证），该会话下服务端
      // 渲染课程页为"全部学期 95 门、无 selected"，数据页按任何学期查都返回空壳；
      // 手动登录（退登清空 cookie 后）能恢复 = 服务端从零建的新会话才正常。
      // 处置：清空超星域 cookie 逼服务端重建会话 → 整流程重跑（重拉课程页+重解析学期+重拉数据页）。
      if (attendances.length === 0 && courseInfos.length > 0) {
        console.info('[Att] 数据页空壳：清超星会话 cookie 强制重建后整流程重跑');
        await this.clearChaoxingSession();
        await this.ensureLoginSerialized(); // 无 cookie → 服务端从零建全新会话
        courseInfos = await this.fetchCourseInfos();
        if (courseInfos.length > 0) {
          dataUrl = buildUrl(COURSE_DATA_URL, {
            'v': '1',
            'semesternum': this.semesterCode
          });
          dataResp = await this.http.get(dataUrl);
          cleanedHtml = dataResp.body.replace(/[\r\n\t]/g, '');
          attendances = this.parseAttendanceTable(cleanedHtml, courseInfos);
          console.info('[Att] diag: 重建会话后考勤 len=' + cleanedHtml.length +
            ' 解析课程=' + courseInfos.length +
            ' 考勤行数=' + attendances.length);
        }
      }
      return attendances;
    } catch (e) {
      throw new Error('加载考勤数据失败');
    }
  }

  // 拉取课程列表（含 0 门时的重登重试）；学期码解析在 parseCourseInfo 内完成
  private async fetchCourseInfos(): Promise<CourseInfo[]> {
    let courseInfos: CourseInfo[] = [];
    for (let attempt = 0; attempt < 2; attempt++) {
      const infoResp: HttpResponse = await this.http.get(COURSE_INFO_URL);
      courseInfos = this.parseCourseInfo(infoResp.body);
      if (courseInfos.length > 0 || attempt === 1) {
        if (courseInfos.length === 0) {
          // 第二次仍解析不到课程：打印响应特征便于诊断（半登录页/页面版本差异）
          const b: string = infoResp.body;
          console.info('[Att] 解析0门课 len=' + b.length +
            ' myde=' + (b.indexOf('myde_course_item') >= 0) +
            ' zmy=' + (b.indexOf('zmy_item') >= 0) +
            ' courseId=' + (b.indexOf('courseId=') >= 0) +
            ' yearList=' + (b.indexOf('yearList') >= 0) +
            ' dl=' + (b.indexOf('myde_course_dl') >= 0) +
            ' body: ' + b.substring(0, 800));
        }
        break;
      }
      // 解析 0 门课：多半是超星会话半建立（isLogin 误判），强制重登后重试一次
      console.info('[Att] 课程列表解析 0 门课, 重新登录超星后重试');
      await this.loginToLearning();
    }
    return courseInfos;
  }

  // 清空超星相关域 cookie（模拟"退出登录"对超星的效果）：罐里残留旧会话时，
  // 服务端会无限续用（SSO 链走完 jrose/INGRESSCOOKIE 都不变），只有清掉才能逼服务端从零建新会话
  private async clearChaoxingSession(): Promise<void> {
    const domains: string[] = [
      'chaoxing.com',
      '.chaoxing.com',
      'passport2.chaoxing.com',
      'i.chaoxing.com',
      'kb.chaoxing.com',
      'fanya.chaoxing.com',
      'xdspoc.fanya.chaoxing.com',
      'fycourse.fanya.chaoxing.com',
      'mobilelearn.chaoxing.com',
      'mh.chaoxing.com',
      'xdspoc.xidian.edu.cn'
    ];
    for (let i = 0; i < domains.length; i++) {
      await this.http.clearCookies(domains[i]);
    }
  }

  // ===== 获取签到详情 =====
  async getAttendanceDetail(
    courseId: string,
    clazzId: string,
    page: number,
    pageSize: number
  ): Promise<ClassAttendanceDetail[]> {
    try {
      await this.ensureLogin();

      const url: string = buildUrl(COURSE_DETAIL_URL, {
        'classId': clazzId,
        'courseId': courseId,
        'page': String(page),
        'pageSize': String(pageSize),
        'puid': ''
      });
      const resp: HttpResponse = await this.http.get(url);
      const data = JSON.parse(resp.body) as Record<string, Object>;
      const dataObj = data['data'] as Record<string, Object> ?? {};
      const list: Object[] = dataObj['list'] as Object[] ?? [];

      const results: ClassAttendanceDetail[] = [];
      for (let i = 0; i < list.length; i++) {
        results.push(ClassAttendanceDetail.fromJson(list[i] as Record<string, Object>));
      }

      return results;
    } catch (e) {
      throw new Error('加载签到详情失败');
    }
  }
}
