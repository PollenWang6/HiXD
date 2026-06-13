// AttendanceService.ets — 超星学习平台考勤数据服务
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { ClassAttendance, ClassAttendanceDetail } from './AttendanceModels';

const TAG: string = 'AttendanceService';

// 超星 SSO 登录入口（西电 → 超星）
const LOGIN_URL: string = 'https://xdspoc.fanya.chaoxing.com/sso/xdspoc';
// 课程列表页（HTML）
const COURSE_INFO_URL: string = 'https://fycourse.fanya.chaoxing.com/courselist/study';
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

  static getInstance(): AttendanceService {
    if (!AttendanceService.instance) {
      AttendanceService.instance = new AttendanceService();
    }
    return AttendanceService.instance;
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
      const data = JSON.parse(resp.body) as Record<string, Object>;
      return data['errorMsg'] as string !== '请登录后再试';
    } catch (_e) {
      return false;
    }
  }

  // SSO 登录到超星学习平台
  // 参照 Flutter checkAndLogin：直接请求 CAS service URL，利用已有 TGC 自动重定向到超星
  async loginToLearning(): Promise<void> {
    const casUrl: string = 'https://ids.xidian.edu.cn/authserver/login?service=' +
      encodeURIComponent(LOGIN_URL);
    console.info(TAG, 'loginToLearning: hitting CAS directly, URL=' + casUrl.substring(0, 100) + '...');
    const resp: HttpResponse = await this.http.get(casUrl);
    console.info(TAG, 'loginToLearning: done, status=' + String(resp.statusCode) +
      ' bodyLen=' + String(resp.body.length));
    const sc: string = resp.headers['set-cookie'] || resp.headers['Set-Cookie'] || '';
    console.info(TAG, 'loginToLearning: set-cookie len=' + String(sc.length));

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
      console.info(TAG, 'ensureLogin: already logged in');
      return;
    }
    console.info(TAG, 'ensureLogin: need login');
    await this.loginToLearning();
  }

  // 去掉 HTML 标签辅助
  private stripTags(s: string): string {
    return s.replace(/<[^>]+>/g, '').trim();
  }

  // ===== 解析课程列表 HTML =====
  private parseCourseInfo(html: string): CourseInfo[] {
    const results: CourseInfo[] = [];
    const seen: Set<string> = new Set();

    // 提取学期
    const yearRe: RegExp = /<select[^>]*id="yearList"[^>]*>([\s\S]*?)<\/select>/;
    const yearMatch= html.match(yearRe);
    if (yearMatch !== null) {
      const optRe: RegExp = /<option[^>]*value="([^"]*)"[^>]*selected[^>]*>/;
      const optMatch = yearMatch[1].match(optRe);
      if (optMatch !== null) {
        this.semesterCode = optMatch[1];
      }
    }
    console.info(TAG, 'parseCourseInfo: semester=' + this.semesterCode);

    // 提取每个 myde_course_item div
    const blockRe: RegExp = /<div\b[^>]*myde_course_item[^>]*>([\s\S]*?)(?=<div\b[^>]*myde_course_item|$)/g;
    let match = blockRe.exec(html);
    while (match !== null) {
      const block: string = match[1];
      if (block.length === 0) continue;

      // cname
      const cnameM = block.match(/cname="([^"]*)"/);
      const cname: string = cnameM !== null ? cnameM[1].trim() : '';

      // dt 文本（课程名）
      const dtM = block.match(/<dt[^>]*>([\s\S]*?)<\/dt>/);
      let courseName: string = '';
      if (cname.length > 0) {
        courseName = cname;
      } else if (dtM !== null) {
        courseName = this.stripTags(dtM[1]);
      }
      courseName = courseName.replace(/\s*\([^)]*\)\s*$/, '').trim();

      // dd[1] = 班级
      const ddList: string[] = [];
      const ddRe: RegExp = /<dd[^>]*>([\s\S]*?)<\/dd>/g;
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
      match = blockRe.exec(html);
    }

    console.info(TAG, 'parseCourseInfo: found ' + String(results.length) + ' courses');    console.info(TAG, 'parseCourseInfo: found ' + String(results.length) + ' courses');
    return results;
  }

  // ===== 解析考勤数据表 HTML =====
  private parseAttendanceTable(html: string, courseInfos: CourseInfo[]): ClassAttendance[] {
    const results: ClassAttendance[] = [];

    const tbodyRe: RegExp = /<tbody[^>]*>([\s\S]*?)<\/tbody>/;
    const tbodyMatch = html.match(tbodyRe);
    if (tbodyMatch === null) {
      console.info(TAG, 'parseAttendanceTable: no tbody found');
      return results;
    }

    // 分割 tr
    const rows: string[] = [];
    const trRe: RegExp = /<tr[^>]*>([\s\S]*?)<\/tr>/g;
    let trMatch = trRe.exec(tbodyMatch[1]);
    while (trMatch !== null) {
      rows.push(trMatch[1]);
      trMatch = trRe.exec(tbodyMatch[1]);
    }

    for (let i = 0; i < rows.length; i++) {
      const row: string = rows[i];
      const tdList: string[] = [];
      const tdRe: RegExp = /<td[^>]*>([\s\S]*?)<\/td>/g;
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
        if (info.courseName === att.courseName && info.className === att.className) {
          matched = info;
          break;
        }
      }
      if (matched !== null) {
        att.courseId = matched.courseId;
        att.clazzId = matched.clazzId;
        att.cpi = matched.cpi;
      }

      results.push(att);
    }

    console.info(TAG, 'parseAttendanceTable: parsed ' + String(results.length) + ' records');
    return results;
  }

  // ===== 主方法：获取考勤数据 =====
  async getAttendanceRecords(): Promise<ClassAttendance[]> {
    try {
      await this.ensureLogin();

      console.info(TAG, 'getAttendanceRecords: fetching course list');
      const infoResp: HttpResponse = await this.http.get(COURSE_INFO_URL);
      console.info(TAG, 'getAttendanceRecords: infoResp status=' + String(infoResp.statusCode) + ' len=' + String(infoResp.body.length));
      console.info(TAG, 'getAttendanceRecords: body[0:300]=' + infoResp.body.substring(0, 300));
      const courseInfos: CourseInfo[] = this.parseCourseInfo(infoResp.body);

      if (courseInfos.length === 0) {
        console.info(TAG, 'getAttendanceRecords: no courses found');
        return [];
      }

      console.info(TAG, 'getAttendanceRecords: fetching data, semester=' + this.semesterCode);
      const dataUrl: string = buildUrl(COURSE_DATA_URL, {
        'v': '1',
        'semesternum': this.semesterCode
      });
      const dataResp: HttpResponse = await this.http.get(dataUrl);
      console.info(TAG, 'getAttendanceRecords: dataResp status=' + String(dataResp.statusCode) + ' len=' + String(dataResp.body.length));
      const cleanedHtml: string = dataResp.body.replace(/[\r\n\t]/g, '');
      const attendances: ClassAttendance[] = this.parseAttendanceTable(cleanedHtml, courseInfos);

      return attendances;
    } catch (e) {
      console.error(TAG, 'getAttendanceRecords error: ' + String(e));
      throw new Error('加载考勤数据失败');
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
      console.error(TAG, 'getAttendanceDetail error: ' + String(e));
      throw new Error('加载签到详情失败');
    }
  }
}
