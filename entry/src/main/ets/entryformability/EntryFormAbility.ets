// EntryFormAbility.ets — 课程预告桌面卡片数据提供者
import { Want, common } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { fileIo } from '@kit.CoreFileKit';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'EntryFormAbility';
const DOMAIN: number = 0xFF00;
let showTomorrowFlag: boolean = false;

// 节次时间表
const SECTION_TIMES: string[] = [
  '',
  '8:30-9:15',
  '9:20-10:05',
  '10:25-11:10',
  '11:15-12:00',
  '14:00-14:45',
  '14:50-15:35',
  '15:55-16:40',
  '16:45-17:30',
  '19:00-19:45',
  '19:55-20:35',
  '20:40-21:25'
];

class FormDataClass {
  // 课程数据：用 string[] 传（formBindingData 不支持对象数组）
  todayNames: string[];
  todayTimes: string[];
  todayRooms: string[];
  todayStarts: number[];
  todayTeachers: string[];
  todayTypes: string[];
  todaySeats: string[];
  todayCount: number;
  tomorrowNames: string[];
  tomorrowTimes: string[];
  tomorrowRooms: string[];
  tomorrowStarts: number[];
  tomorrowTeachers: string[];
  tomorrowTypes: string[];
  tomorrowSeats: string[];
  tomorrowCount: number;
  // 考试数据
  todayExamNames: string[];
  todayExamTimes: string[];
  todayExamRooms: string[];
  todayExamCount: number;
  tomorrowExamNames: string[];
  tomorrowExamTimes: string[];
  tomorrowExamRooms: string[];
  tomorrowExamCount: number;
  // 考试倒计时卡片专用字段
  examCountdownLabel: string;    // "5天8小时" / "进行中" (4×2用)
  examCountdownDays: string;     // "5天" (2×2分两行用)
  examCountdownHours: string;    // "8小时" (2×2分两行用)
  examCountdownName: string;     // 最近一场考试名
  examCountdownWeekday: string;  // "周二"
  examCountdownTime: string;     // "08:30"
  examCountdownLocation: string; // "教三楼301 · 座位12"
  examCountdownColor: string;    // "#FF9800"
  examCountdownIsUrgent: boolean; // ≤3天
  examCountdownIsOngoing: boolean;
  upcoming72hCount: number;      // 未来72h还有几门
  upcoming72hNames: string[];
  upcoming72hWeekdays: string[];
  upcoming72hTimes: string[];
  upcoming72hLocations: string[];
  // 元数据
  weekNum: number;
  weekLabel: string;
  dateLabel: string;
  lastRefresh: string;
  isEmpty: boolean;
  isWeekend: boolean;
  showTomorrow: boolean;

  constructor() {
    this.todayNames = [];
    this.todayTimes = [];
    this.todayRooms = [];
    this.todayStarts = [];
    this.todayTeachers = [];
    this.todayTypes = [];
    this.todaySeats = [];
    this.todayCount = 0;
    this.tomorrowNames = [];
    this.tomorrowTimes = [];
    this.tomorrowRooms = [];
    this.tomorrowStarts = [];
    this.tomorrowTeachers = [];
    this.tomorrowTypes = [];
    this.tomorrowSeats = [];
    this.tomorrowCount = 0;
    this.todayExamNames = [];
    this.todayExamTimes = [];
    this.todayExamRooms = [];
    this.todayExamCount = 0;
    this.tomorrowExamNames = [];
    this.tomorrowExamTimes = [];
    this.tomorrowExamRooms = [];
    this.tomorrowExamCount = 0;
    this.examCountdownLabel = '';
    this.examCountdownDays = '';
    this.examCountdownHours = '';
    this.examCountdownName = '';
    this.examCountdownWeekday = '';
    this.examCountdownTime = '';
    this.examCountdownLocation = '';
    this.examCountdownColor = '#FF9800';
    this.examCountdownIsUrgent = false;
    this.examCountdownIsOngoing = false;
    this.upcoming72hCount = 0;
    this.upcoming72hNames = [];
    this.upcoming72hWeekdays = [];
    this.upcoming72hTimes = [];
    this.upcoming72hLocations = [];
    this.weekNum = 1;
    this.weekLabel = '';
    this.dateLabel = '';
    this.lastRefresh = '';
    this.isEmpty = true;
    this.isWeekend = false;
    this.showTomorrow = false;
  }
}

function getSemesterCode(): string {
  // 必须与 SemesterUtil.getCurrentSemesterCode() 保持一致：优先读 current_semester 偏好
  const saved: string = PreferenceUtil.getString('current_semester');
  if (saved.length > 0) { return saved; }
  const now: Date = new Date();
  const y: number = now.getFullYear();
  const m: number = now.getMonth() + 1;
  if (m >= 9) { return y + '-' + (y + 1) + '-1'; }
  if (m >= 2 && m <= 7) { return (y - 1) + '-' + y + '-2'; }
  return (y - 1) + '-' + y + '-1';
}

function calcCurrentWeek(): number {
  const START: number = new Date(2026, 2, 2).getTime();
  const now: number = Date.now();
  const diff: number = Math.floor((now - START) / (1000 * 60 * 60 * 24));
  // 不再硬编码上限，由实际数据动态确定
  return Math.max(1, Math.floor(diff / 7) + 1);
}

function sortEntries(names: string[], times: string[], rooms: string[], teachers: string[], starts: number[]): void {
  const len: number = names.length;
  if (len <= 1) return;
  const idx: number[] = [];
  for (let i: number = 0; i < len; i++) idx.push(i);
  for (let i: number = 0; i < len - 1; i++) {
    for (let j: number = i + 1; j < len; j++) {
      if (starts[idx[j]] < starts[idx[i]]) {
        const tmp: number = idx[i];
        idx[i] = idx[j];
        idx[j] = tmp;
      }
    }
  }
  const n2: string[] = [];
  const t2: string[] = [];
  const r2: string[] = [];
  const tr2: string[] = [];
  const s2: number[] = [];
  for (let i: number = 0; i < len; i++) {
    n2.push(names[idx[i]]);
    t2.push(times[idx[i]]);
    r2.push(rooms[idx[i]]);
    tr2.push(teachers.length > idx[i] ? teachers[idx[i]] : '');
    s2.push(starts[idx[i]]);
  }
  for (let i: number = 0; i < len; i++) {
    names[i] = n2[i];
    times[i] = t2[i];
    rooms[i] = r2[i];
    teachers[i] = tr2[i];
    starts[i] = s2[i];
  }
}

function parseWeekStr(skzc: string, maxWeeks: number): boolean[] {
  const list: boolean[] = [];
  for (let i: number = 0; i <= maxWeeks; i++) {
    list.push(false);
  }
  if (!skzc || skzc.length === 0) {
    return list;
  }

  // 二进制位图格式：纯0/1字符串，如 "011110111011111"（长度可能不等于 maxWeeks）
  // 检测条件：不含逗号和横杠，且全是0和1
  if (skzc.indexOf(',') < 0 && skzc.indexOf('-') < 0) {
    let isBitmap: boolean = true;
    for (let c: number = 0; c < skzc.length; c++) {
      const ch: string = skzc[c];
      if (ch !== '0' && ch !== '1') {
        isBitmap = false;
        break;
      }
    }
    if (isBitmap) {
      for (let i: number = 0; i < skzc.length && i < maxWeeks; i++) {
        if (skzc[i] === '1') {
          list[i + 1] = true;
        }
      }
      return list;
    }
  }

  // 文本格式：逗号分隔，如 "1-18" / "1,3,5,7,9-16(单)"
  const parts: string[] = skzc.split(',');
  for (let p: number = 0; p < parts.length; p++) {
    const seg: string = parts[p].trim();
    if (seg.length === 0) {
      continue;
    }
    const dash: number = seg.indexOf('-');
    if (dash > 0) {
      const start: number = parseInt(seg.substring(0, dash)) || 0;
      const end: number = parseInt(seg.substring(dash + 1)) || 0;
      for (let w: number = start; w <= end && w <= maxWeeks; w++) {
        list[w] = true;
      }
    } else {
      const w: number = parseInt(seg) || 0;
      if (w > 0 && w <= maxWeeks) {
        list[w] = true;
      }
    }
  }
  return list;
}

function readClassCache(context: common.Context): string | null {
  const code: string = getSemesterCode();
  const path: string = context.filesDir + '/class_table_' + code + '.json';
  try {
    const f: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const stat: fileIo.Stat = fileIo.statSync(path);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(f.fd, buf);
    fileIo.closeSync(f);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const result: string = decoder.decodeToString(new Uint8Array(buf));
    return result;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'readClassCache failed: ' + JSON.stringify(e));
    return null;
  }
}

function mergeCustomCourses(form: FormDataClass, context: common.Context): void {
  const code: string = getSemesterCode();
  const path: string = context.filesDir + '/class_table_' + code + '_custom.json';
  try {
    const f: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const stat: fileIo.Stat = fileIo.statSync(path);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(f.fd, buf);
    fileIo.closeSync(f);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const text: string = decoder.decodeToString(new Uint8Array(buf));
    const items: Object[] = JSON.parse(text) as Object[];

    const now: Date = new Date();
    const localDay: number = (() => {
      const utcDay: number = now.getUTCDay();
      const utcH: number = now.getUTCHours();
      const tzOffsetH: number = -now.getTimezoneOffset() / 60;
      const localH: number = utcH + tzOffsetH;
      let d: number = utcDay;
      if (localH >= 24) d = (d + 1) % 7;
      else if (localH < 0) d = (d + 6) % 7;
      return d === 0 ? 7 : d;
    })();
    const todayDay: number = localDay;
    const tomorrowDay: number = todayDay === 7 ? 1 : todayDay + 1;
    const currentWeek: number = calcCurrentWeek();


    for (let i: number = 0; i < items.length; i++) {
      const item: Record<string, Object> = items[i] as Record<string, Object>;
      const itType: number = (item['type'] as number) || 0;

      // 自定义考试（type=1）：按日期匹配今天/明天，添加到考试列表
      if (itType === 1) {
        const examDate: string = String(item['examDate'] || '');
        if (!examDate) { continue; }
        const now2: Date = new Date();
        const pad2 = (n: number): string => n < 10 ? '0' + n : String(n);
        const todayStr: string = now2.getFullYear() + '-' + pad2(now2.getMonth() + 1) + '-' + pad2(now2.getDate());
        const tm2: Date = new Date(now2.getTime() + 86400000);
        const tomorrowStr: string = tm2.getFullYear() + '-' + pad2(tm2.getMonth() + 1) + '-' + pad2(tm2.getDate());
        if (examDate !== todayStr && examDate !== tomorrowStr) { continue; }
        const eName: string = String(item['name'] || '考试');
        const eTime: string = String(item['examTimeStart'] || '') + (item['examTimeEnd'] ? '-' + String(item['examTimeEnd']) : '');
        const eRoom: string = String(item['classroom'] || '');
        const eSeat: string = String(item['examSeat'] || '');
        if (examDate === todayStr) {
          form.todayNames.push(eName);
          form.todayTimes.push(eTime);
          form.todayRooms.push(eRoom);
          form.todayTeachers.push('');
          form.todayStarts.push(0);
          form.todayTypes.push('exam');
          form.todaySeats.push(eSeat);
        } else {
          form.tomorrowNames.push(eName);
          form.tomorrowTimes.push(eTime);
          form.tomorrowRooms.push(eRoom);
          form.tomorrowTeachers.push('');
          form.tomorrowStarts.push(0);
          form.tomorrowTypes.push('exam');
          form.tomorrowSeats.push(eSeat);
        }
        continue;
      }

      const weekList: number[] = item['weekList'] as number[] || [];
      let weekMatch: boolean = false;
      if (currentWeek > 0 && currentWeek <= weekList.length && weekList[currentWeek] === 1) {
        weekMatch = true;
      }
      const day: number = item['day'] as number || 0;
      const name: string = item['name'] as string || '';
      const startSec: number = item['startSection'] as number || 0;
      const customTeacher: string = item['teacher'] as string || '';
      if (!weekMatch) continue;

      if (day < 1 || day > 7) continue;
      const room: string = item['classroom'] as string || '';
      const endSec: number = item['endSection'] as number || 0;

      let timeStr: string = '';
      if (startSec > 0 && startSec < SECTION_TIMES.length && endSec > 0 && endSec < SECTION_TIMES.length) {
        timeStr = SECTION_TIMES[startSec].split('-')[0] + '~' + SECTION_TIMES[endSec].split('-')[1];
      }

      const typeLabel: string = itType === 2 ? 'exp' : 'custom';

      if (day === todayDay) {
        form.todayNames.push(name);
        form.todayTimes.push(timeStr);
        form.todayRooms.push(room);
        form.todayTeachers.push(customTeacher);
        form.todayStarts.push(startSec);
        form.todayTypes.push(typeLabel);
      } else if (day === tomorrowDay) {
        form.tomorrowNames.push(name);
        form.tomorrowTimes.push(timeStr);
        form.tomorrowRooms.push(room);
        form.tomorrowTeachers.push(customTeacher);
        form.tomorrowStarts.push(startSec);
        form.tomorrowTypes.push(typeLabel);
      }
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'mergeCustomCourses read failed: ' + JSON.stringify(e));
  }
}

function mergeExperimentPreview(form: FormDataClass, currentWeek: number, localDay: number): void {
  const raw: string = PreferenceUtil.getString('sysj_exp_cache');
  if (raw.length === 0) return;
  try {
    const cacheObj: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
    const data: Object[] = cacheObj['data'] as Object[];
    if (!Array.isArray(data) || data.length === 0) return;

    const todayDay: number = localDay;
    const tomorrowDay: number = todayDay === 7 ? 1 : todayDay + 1;

    for (let i: number = 0; i < data.length; i++) {
      const item: Record<string, Object> = data[i] as Record<string, Object>;
      const wk: number = parseInt(String(item['week'] || '0')) || 0;
      if (wk !== currentWeek) continue;

      const day: number = parseInt(String(item['weekday'] || '0')) || 0;
      if (day < 1 || day > 7) continue;

      const name: string = String(item['experimentName'] || '实验');
      const room: string = String(item['lab'] || '');
      const startSec: number = parseInt(String(item['startSection'] || '0')) || 0;
      const endSec: number = parseInt(String(item['endSection'] || '0')) || 0;

      let timeStr: string = '';
      if (startSec > 0 && startSec < SECTION_TIMES.length && endSec > 0 && endSec < SECTION_TIMES.length) {
        timeStr = SECTION_TIMES[startSec].split('-')[0] + '~' + SECTION_TIMES[endSec].split('-')[1];
      }

      if (day === todayDay) {
        form.todayNames.push('🧪 ' + name);
        form.todayTimes.push(timeStr);
        form.todayRooms.push(room);
        form.todayTeachers.push('');
        form.todayStarts.push(startSec);
      } else if (day === tomorrowDay) {
        form.tomorrowNames.push('🧪 ' + name);
        form.tomorrowTimes.push(timeStr);
        form.tomorrowRooms.push(room);
        form.tomorrowTeachers.push('');
        form.tomorrowStarts.push(startSec);
      }
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'mergeExperimentPreview error: ' + JSON.stringify(e));
  }
}

function mergePhysicsPreview(form: FormDataClass, currentWeek: number, localDay: number): void {
  const cached: string = PreferenceUtil.getString('physics_exp_cache');
  if (cached.length === 0) return;
  try {
    const co: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
    const data: Object[] = co['data'] as Object[];
    if (!data || data.length === 0) return;
    for (let i: number = 0; i < data.length; i++) {
      const item: Record<string, Object> = data[i] as Record<string, Object>;
      const wk: number = parseInt(String(item['week'] || '0')) || 0;
      if (wk !== currentWeek) continue;
      const day: number = parseInt(String(item['weekday'] || '0')) || 0;
      if (day < 1 || day > 7 || day !== localDay) continue;
      const name: string = String(item['experimentName'] || '物理实验');
      const room: string = String(item['lab'] || '');
      const startSec: number = parseInt(String(item['startSection'] || '0')) || 0;
      const endSec: number = parseInt(String(item['endSection'] || '0')) || 0;
      let timeStr: string = '';
      if (startSec > 0 && startSec < SECTION_TIMES.length && endSec > 0 && endSec < SECTION_TIMES.length) {
        timeStr = SECTION_TIMES[startSec].split('-')[0] + '~' + SECTION_TIMES[endSec].split('-')[1];
      }
      form.todayNames.push('⚛ ' + name);
      form.todayTimes.push(timeStr);
      form.todayRooms.push(room);
      form.todayTeachers.push('');
      form.todayStarts.push(startSec);
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'mergePhysicsPreview error: ' + JSON.stringify(e));
  }
}


// 从考试时间字符串推算对应节次
function getExamSection(timeStr: string): number {
  const idx: number = timeStr.indexOf('-');
  const startTime: string = idx >= 0 ? timeStr.substring(0, idx) : timeStr;
  const parts: string[] = startTime.split(':');
  if (parts.length < 2) return 11;
  const h: number = parseInt(parts[0]);
  const m: number = parseInt(parts[1]);
  const totalMin: number = h * 60 + m;
  for (let i: number = 1; i < SECTION_TIMES.length; i++) {
    const sep: string[] = SECTION_TIMES[i].split('-');
    const sh: number = parseInt(sep[0].split(':')[0]);
    const sm: number = parseInt(sep[0].split(':')[1]);
    if (totalMin <= sh * 60 + sm) return i;
  }
  return 11;
}
function mergeExamPreview(form: FormDataClass, currentWeek: number, localDay: number, context: common.Context): void {
  try {
    // 从共享文件读取（绕过 Preferences 跨进程隔离）
    let cached: string = PreferenceUtil.readSharedFile('exam_schedule', context.filesDir);
    if (cached.length === 0) {
      cached = PreferenceUtil.getString('exam_schedule_cache');
    }
    if (cached.length === 0) { return; }
    const root: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
    const ds: Record<string, Object> = root['datas'] as Record<string, Object>;
    if (!ds) { return; }
    const wdksap: Record<string, Object> = ds['wdksap'] as Record<string, Object>;
    if (!wdksap) { return; }
    const items: Object[] = wdksap['rows'] as Object[];
    if (!items || items.length === 0) { return; }

    const now: Date = new Date();
    const pad = (n: number): string => n < 10 ? '0' + n : String(n);
    const todayStr: string = now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate());
    const tm: Date = new Date(now.getTime() + 86400000);
    const tomorrowStr: string = tm.getFullYear() + '-' + pad(tm.getMonth() + 1) + '-' + pad(tm.getDate());

    for (let i: number = 0; i < items.length; i++) {
      const item: Record<string, Object> = items[i] as Record<string, Object>;
      const ksrq: string = item['KSRQ'] as string || '';
      const kssjms: string = item['KSSJMS'] as string || '';
      if (!ksrq || !kssjms) continue;

      // KSRQ may include time: "2026-06-15 00:00:00"
      const dateOnly: string = ksrq.length >= 10 ? ksrq.substring(0, 10) : ksrq;
      if (dateOnly !== todayStr && dateOnly !== tomorrowStr) continue;

      // 解析考试时间
      const spaceIdx: number = kssjms.indexOf(' ');
      const timeWithDay: string = spaceIdx >= 0 ? kssjms.substring(spaceIdx + 1) : kssjms;
      const parenIdx: number = timeWithDay.indexOf('(');
      const timeOnly: string = parenIdx >= 0 ? timeWithDay.substring(0, parenIdx) : timeWithDay;

      const name: string = (item['KCM'] as string) || (item['KSMC'] as string) || '考试';
      const room: string = (item['JASMC'] as string) || '';
      const seat: string = (item['ZWH'] as string) || '';
      const examTimeDesc: string = timeOnly;

      if (dateOnly === todayStr) {
        form.todayNames.push(name);
        form.todayTimes.push(examTimeDesc);
        form.todayRooms.push(room);
        form.todayTeachers.push('');
        form.todayStarts.push(getExamSection(timeOnly));
        form.todayTypes.push('exam');
        form.todaySeats.push(seat);
      } else {
        form.tomorrowNames.push(name);
        form.tomorrowTimes.push(examTimeDesc);
        form.tomorrowRooms.push(room);
        form.tomorrowTeachers.push('');
        form.tomorrowStarts.push(getExamSection(timeOnly));
        form.tomorrowTypes.push('exam');
        form.tomorrowSeats.push(seat);
      }
    }

    form.todayExamCount = form.todayTypes.filter((t: string) => t === 'exam').length;
    form.tomorrowExamCount = form.tomorrowTypes.filter((t: string) => t === 'exam').length;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'mergeExamPreview error: ' + JSON.stringify(e));
  }
}

// ── 考试倒计时卡片专用：读取所有考试(学校+自定义)，计算最近一场倒计时和未来72h列表 ──
interface ExamEntryRaw {
  name: string;
  date: string;
  startTime: string;
  endTime: string;
  location: string;
  seat: string;
}

function buildExamCountdownFields(form: FormDataClass, context: common.Context): void {
  try {
    const WEEKDAYS_CN: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    const allExams: ExamEntryRaw[] = [];

    // 1) 学校考试 (exam_schedule cache)
    let cached: string = PreferenceUtil.readSharedFile('exam_schedule', context.filesDir);
    if (cached.length === 0) {
      cached = PreferenceUtil.getString('exam_schedule_cache');
    }
    if (cached.length > 0) {
      const root: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
      const ds: Record<string, Object> = root['datas'] as Record<string, Object>;
      if (ds) {
        const wdksap: Record<string, Object> = ds['wdksap'] as Record<string, Object>;
        if (wdksap) {
          const items: Object[] = wdksap['rows'] as Object[];
          if (items) {
            for (let i: number = 0; i < items.length; i++) {
              const item: Record<string, Object> = items[i] as Record<string, Object>;
              const ksrq: string = String(item['KSRQ'] || '').substring(0, 10);
              const kssjms: string = String(item['KSSJMS'] || '');
              if (!ksrq || !kssjms) { continue; }
              // 解析时间段 "08:30~10:05" / "8:30-10:05"（正则兼容单/双数字小时与任意分隔符）
              const tm: RegExpMatchArray | null = kssjms.match(/(\d{1,2}:\d{2})\s*[~～-]\s*(\d{1,2}:\d{2})/);
              if (!tm) { continue; }
              const startTime: string = tm[1];
              const endTime: string = tm[2];
              allExams.push({
                name: String(item['KCM'] || item['KSMC'] || '考试'),
                date: ksrq, startTime: startTime, endTime: endTime,
                location: String(item['JASMC'] || ''),
                seat: String(item['ZWH'] || '')
              });
            }
          }
        }
      }
    }

    // 2) 自定义考试 (_custom.json)
    try {
      const semCode: string = getSemesterCode();
      const customPath: string = context.filesDir + '/class_table_' + semCode + '_custom.json';
      const cf: fileIo.File = fileIo.openSync(customPath, fileIo.OpenMode.READ_ONLY);
      const cs: fileIo.Stat = fileIo.statSync(customPath);
      const buf: ArrayBuffer = new ArrayBuffer(cs.size);
      fileIo.readSync(cf.fd, buf);
      fileIo.closeSync(cf);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(new Uint8Array(buf));
      const customItems: Object[] = JSON.parse(text) as Object[];
      for (let ci: number = 0; ci < customItems.length; ci++) {
        const citem: Record<string, Object> = customItems[ci] as Record<string, Object>;
        if ((citem['type'] as number) !== 1) { continue; }
        const edate: string = String(citem['examDate'] || '');
        if (!edate) { continue; }
        allExams.push({
          name: String(citem['name'] || ''),
          date: edate,
          startTime: String(citem['examTimeStart'] || ''),
          endTime: String(citem['examTimeEnd'] || ''),
          location: String(citem['classroom'] || ''),
          seat: String(citem['examSeat'] || '')
        });
      }
    } catch (_) {
      // 无自定义课程，忽略
    }

    if (allExams.length === 0) { return; }

    // 按日期+开始时间排序
    allExams.sort((a: ExamEntryRaw, b: ExamEntryRaw): number =>
      (a.date + ' ' + a.startTime).localeCompare(b.date + ' ' + b.startTime));

    const nowTs: number = Date.now();

    // 找最近一场未结束的考试
    let nearest: ExamEntryRaw | null = null;
    for (let i: number = 0; i < allExams.length; i++) {
      const examEndTs: number = new Date(allExams[i].date + 'T' + allExams[i].endTime + ':00').getTime();
      if (examEndTs > nowTs) {
        nearest = allExams[i];
        break;
      }
    }
    if (!nearest) { return; } // 全部已结束

    const examStartTs: number = new Date(nearest.date + 'T' + nearest.startTime + ':00').getTime();
    const examEndTs: number = new Date(nearest.date + 'T' + nearest.endTime + ':00').getTime();

    if (nowTs >= examStartTs && nowTs <= examEndTs) {
      form.examCountdownLabel = '进行中';
      form.examCountdownDays = '进行';
      form.examCountdownHours = '中';
      form.examCountdownIsOngoing = true;
      form.examCountdownIsUrgent = false;
      form.examCountdownColor = '#4CAF50';
    } else {
      const diffMs: number = examStartTs - nowTs;
      const diffHours: number = Math.floor(diffMs / 3600000);
      const diffDays: number = Math.floor(diffHours / 24);
      const remainHours: number = diffHours % 24;
      form.examCountdownLabel = diffDays + '天' + remainHours + '小时';
      form.examCountdownDays = diffDays + '天';
      form.examCountdownHours = remainHours + '小时';
      form.examCountdownIsUrgent = diffHours <= 72;
      form.examCountdownIsOngoing = false;
      form.examCountdownColor = form.examCountdownIsUrgent ? '#FF5252' : '#FF9800';
    }

    form.examCountdownName = nearest.name;
    const examDateObj: Date = new Date(nearest.date + 'T00:00:00');
    form.examCountdownWeekday = WEEKDAYS_CN[examDateObj.getDay()];
    form.examCountdownTime = nearest.startTime;
    if (nearest.location.length > 0) {
      form.examCountdownLocation = nearest.location;
      if (nearest.seat.length > 0) {
        form.examCountdownLocation += ' · 座位' + nearest.seat;
      }
    }

    // 未来72h的其他考试
    const cutoff72h: number = nowTs + 72 * 3600000;
    for (let i: number = 0; i < allExams.length; i++) {
      if (allExams[i] === nearest) { continue; }
      const examStart: number = new Date(allExams[i].date + 'T' + allExams[i].startTime + ':00').getTime();
      if (examStart > nowTs && examStart <= cutoff72h) {
        form.upcoming72hCount++;
        form.upcoming72hNames.push(allExams[i].name);
        const ed: Date = new Date(allExams[i].date + 'T00:00:00');
        form.upcoming72hWeekdays.push(WEEKDAYS_CN[ed.getDay()]);
        form.upcoming72hTimes.push(allExams[i].startTime);
        let loc: string = allExams[i].location || '';
        if (allExams[i].seat.length > 0 && loc.length > 0) { loc += ' · 座位' + allExams[i].seat; }
        form.upcoming72hLocations.push(loc);
      }
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'buildExamCountdownFields error: ' + JSON.stringify(e));
  }
}

function getSemesterStartDate(): Date {
  const now: Date = new Date();
  return new Date(2026, 2, 2);
}

function buildFormData(cache: string | null, showTomorrow: boolean, context: common.Context): FormDataClass {
  const form: FormDataClass = new FormDataClass();
  const currentWeek: number = calcCurrentWeek();
  form.weekNum = currentWeek;
  form.weekLabel = '\u7B2C' + currentWeek + '\u5468';

  const now: Date = new Date();
  const WDAYS: string[] = ['\u65E5', '\u4E00', '\u4E8C', '\u4E09', '\u56DB', '\u4E94', '\u516D'];
  form.dateLabel = (now.getMonth() + 1) + '\u6708' + now.getDate() + '\u65E5 \u5468' + WDAYS[now.getDay()];
  // 修复时区 bug：FormExtensionAbility 中 getDay() 可能返回 UTC 的星期几
  // 手动加上时区偏移，确保拿到本地正确星期几（1=周一 ... 7=周日）
  const localDay: number = (() => {
    const utcDay: number = now.getUTCDay(); // 0=Sun ... 6=Sat
    const utcH: number = now.getUTCHours();
    const tzOffsetH: number = -now.getTimezoneOffset() / 60; // 上海 = +8
    const localH: number = utcH + tzOffsetH;
    let d: number = utcDay;
    if (localH >= 24) d = (d + 1) % 7;
    else if (localH < 0) d = (d + 6) % 7;
    return d === 0 ? 7 : d; // 转成 1=周一 ... 7=周日
  })();

  const hh: string = now.getHours() < 10 ? '0' + now.getHours() : String(now.getHours());
  const mm: string = now.getMinutes() < 10 ? '0' + now.getMinutes() : String(now.getMinutes());
  form.lastRefresh = '更新时间: ' + (now.getMonth() + 1) + '月' + now.getDate() + '日 ' + hh + ':' + mm;

  const dayOfWeek: number = now.getDay();
  form.isWeekend = (localDay === 6 || localDay === 7); // localDay: 6=周六 7=周日
  form.showTomorrow = showTomorrow;

  // ── 加载手动添加课程 ──
  mergeCustomCourses(form, context);

  // ── 加载实验数据 ──
  mergeExperimentPreview(form, currentWeek, localDay);
  mergePhysicsPreview(form, currentWeek, localDay);

  // ── 加载考试数据 ──
  mergeExamPreview(form, currentWeek, localDay, context);
  buildExamCountdownFields(form, context);

  if (!cache || cache.length === 0) {
    form.todayCount = form.todayNames.length;
    form.tomorrowCount = form.tomorrowNames.length;
    form.todayExamCount = form.todayTypes.filter((t: string) => t === 'exam').length;
    form.tomorrowExamCount = form.tomorrowTypes.filter((t: string) => t === 'exam').length;
        form.isEmpty = form.todayNames.length === 0;
    sortEntries(form.todayNames, form.todayTimes, form.todayRooms, form.todayTeachers, form.todayStarts);
    sortEntries(form.tomorrowNames, form.tomorrowTimes, form.tomorrowRooms, form.tomorrowTeachers, form.tomorrowStarts);
    return form;
  }

  try {
    const obj: Record<string, Object> = JSON.parse(cache) as Record<string, Object>;
    const datas: Object = obj['datas'];
    if (!datas || typeof datas !== 'object') {
      return form;
    }
    const datasMap: Record<string, Object> = datas as Record<string, Object>;
    const keys: string[] = Object.keys(datasMap);
    if (keys.length === 0) {
      return form;
    }
    const subObj: Object = datasMap[keys[0]];
    if (!subObj || typeof subObj !== 'object') {
      return form;
    }
    const subMap: Record<string, Object> = subObj as Record<string, Object>;
    const rows: Object[] = subMap['rows'] as Object[];
    if (!Array.isArray(rows)) {
      return form;
    }


    // ── 诊断：打印所有周一（SKXQ=1）课程及其周次过滤结果 ──
    const todayWkDay: number = localDay;
    for (let di: number = 0; di < rows.length; di++) {
      const rd: Record<string, Object> = rows[di] as Record<string, Object>;
      // 打印前3行的所有字段名，确认 SKXQ 字段名
      if (di < 3) {
      }
      const wd: number = parseInt(String(rd['SKXQ'] || rd['skxq'] || '0')) || 0;
      if (wd === todayWkDay) {
        const skzc_raw: string = String(rd['SKZC'] || '');
        const wl: boolean[] = parseWeekStr(skzc_raw, skzc_raw.length);
      }
    }

    let totalRows: number = 0;
    let weekdayFiltered: number = 0;
    let weekFiltered: number = 0;

    for (let i: number = 0; i < rows.length; i++) {
      const r: Record<string, string> = rows[i] as Record<string, string>;
      const name: string = r['KCM'] || '';
      const weekday: number = parseInt(r['SKXQ']) || 0;
      const startSec: number = parseInt(r['KSJC']) || 0;
      const endSec: number = parseInt(r['JSJC']) || 0;
      const classroom: string = r['JASMC'] || '';
      const teacher: string = r['SKJS'] || '';
      const skzc: string = r['SKZC'] || '';

      totalRows++;

      // 采样前3行打印字段值
      if (i < 3) {
      }
      // 诊断：所有今天的行
      const weekList: boolean[] = parseWeekStr(skzc, skzc.length);
      if (weekday === localDay) {
      }

      if (weekday < 1 || weekday > 7 || startSec < 1) {
        weekdayFiltered++;
        continue;
      }

      if (!weekList[currentWeek]) {
        weekFiltered++;
        continue;
      }

      let timeStr: string = '';
      if (startSec > 0 && startSec < SECTION_TIMES.length && endSec > 0 && endSec < SECTION_TIMES.length) {
        timeStr = SECTION_TIMES[startSec].split('-')[0] + '~' + SECTION_TIMES[endSec].split('-')[1];
      }

      const todayWeekday: number = localDay; // localDay 已为 1=周一…7=周日
      const tomorrowWeekday: number = todayWeekday === 7 ? 1 : todayWeekday + 1;

      if (weekday === todayWeekday) {
        form.todayNames.push(name);
        form.todayTimes.push(timeStr);
        form.todayRooms.push(classroom);
        form.todayTeachers.push(teacher);
        form.todayStarts.push(startSec);
      } else if (weekday === tomorrowWeekday) {
        form.tomorrowNames.push(name);
        form.tomorrowTimes.push(timeStr);
        form.tomorrowRooms.push(classroom);
        form.tomorrowTeachers.push(teacher);
        form.tomorrowStarts.push(startSec);
      }
    }

    form.todayCount = form.todayNames.length;
    form.tomorrowCount = form.tomorrowNames.length;

    // 按节次排序 today
    sortEntries(form.todayNames, form.todayTimes, form.todayRooms, form.todayTeachers, form.todayStarts);
    // 按节次排序 tomorrow
    sortEntries(form.tomorrowNames, form.tomorrowTimes, form.tomorrowRooms, form.tomorrowTeachers, form.tomorrowStarts);

    form.todayExamCount = form.todayTypes.filter((t: string) => t === 'exam').length;
    form.tomorrowExamCount = form.tomorrowTypes.filter((t: string) => t === 'exam').length;

        form.isEmpty = form.todayNames.length === 0;

  } catch (e) {
    hilog.error(DOMAIN, TAG, 'parse cache failed: ' + JSON.stringify(e));
  }

  return form;
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want) {
    const formId: string = want.parameters?.['ohos.extra.param.key.form_identity'] as string || '';
    const cache: string | null = readClassCache(this.context);
    const data: FormDataClass = buildFormData(cache, false, this.context);
    if (formId.length > 0) {
      formProvider.setFormNextRefreshTime(formId, 5).catch((_: Error) => {});
    }
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    const cache: string | null = readClassCache(this.context);
    const data: FormDataClass = buildFormData(cache, showTomorrowFlag, this.context);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
      .then(() => {
        formProvider.setFormNextRefreshTime(formId, 5).catch((_: Error) => {});
      })
      .catch((err: Error) => { hilog.error(DOMAIN, TAG, 'updateForm failed: ' + JSON.stringify(err)); });
  }

  onFormEvent(formId: string, message: string): void {
    // 解析卡片交互消息：箭头点击发 { msgTest: 'toggle' }，需翻转 showTomorrowFlag 后重建
    try {
      const parsed: object = JSON.parse(message) as object;
      const rec: Record<string, Object> = parsed as Record<string, Object>;
      let action: string = '';
      if (typeof rec['msgTest'] === 'string') {
        action = rec['msgTest'] as string;
      } else if (rec['params'] !== undefined &&
        typeof (rec['params'] as Record<string, Object>)['msgTest'] === 'string') {
        action = (rec['params'] as Record<string, Object>)['msgTest'] as string;
      }
      if (action === 'toggle') {
        showTomorrowFlag = !showTomorrowFlag;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'onFormEvent parse message failed: ' + (e as Error).message);
    }
    const cache: string | null = readClassCache(this.context);
    const data: FormDataClass = buildFormData(cache, showTomorrowFlag, this.context);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
      .then(() => {
        formProvider.setFormNextRefreshTime(formId, 5).catch((_: Error) => {});
      })
      .catch((err: Error) => { hilog.error(DOMAIN, TAG, 'formEvent update failed: ' + JSON.stringify(err)); });
  }

  onRemoveForm(formId: string): void {
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
