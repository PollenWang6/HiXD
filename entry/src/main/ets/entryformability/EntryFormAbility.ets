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
  todayCount: number;
  tomorrowNames: string[];
  tomorrowTimes: string[];
  tomorrowRooms: string[];
  tomorrowStarts: number[];
  tomorrowTeachers: string[];
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
    this.todayCount = 0;
    this.tomorrowNames = [];
    this.tomorrowTimes = [];
    this.tomorrowRooms = [];
    this.tomorrowStarts = [];
    this.tomorrowTeachers = [];
    this.tomorrowCount = 0;
    this.todayExamNames = [];
    this.todayExamTimes = [];
    this.todayExamRooms = [];
    this.todayExamCount = 0;
    this.tomorrowExamNames = [];
    this.tomorrowExamTimes = [];
    this.tomorrowExamRooms = [];
    this.tomorrowExamCount = 0;
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
  return Math.max(1, Math.min(25, Math.floor(diff / 7) + 1));
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
  hilog.info(DOMAIN, TAG, 'readClassCache path=' + path);
  try {
    const f: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const stat: fileIo.Stat = fileIo.statSync(path);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(f.fd, buf);
    fileIo.closeSync(f);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const result: string = decoder.decodeToString(new Uint8Array(buf));
    hilog.info(DOMAIN, TAG, 'readClassCache success, length=' + result.length);
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

    hilog.info(DOMAIN, TAG, 'mergeCustomCourses: file=' + path + ' code=' + code + ' items=' + items.length + ' currentWeek=' + currentWeek + ' todayDay=' + todayDay);

    for (let i: number = 0; i < items.length; i++) {
      const item: Record<string, Object> = items[i] as Record<string, Object>;
      const weekList: number[] = item['weekList'] as number[] || [];
      let weekMatch: boolean = false;
      if (currentWeek > 0 && currentWeek <= weekList.length && weekList[currentWeek] === 1) {
        weekMatch = true;
      }
      const day: number = item['day'] as number || 0;
      const name: string = item['name'] as string || '';
      const startSec: number = item['startSection'] as number || 0;
      const customTeacher: string = item['teacher'] as string || '';
      hilog.info(DOMAIN, TAG, 'MC[' + i + ']: name=' + name + ' day=' + day + ' start=' + startSec + ' weekList[' + (currentWeek - 1) + ']=' + (weekList[currentWeek - 1] || 0) + ' weekMatch=' + weekMatch);
      if (!weekMatch) continue;

      if (day < 1 || day > 7) continue;
      const room: string = item['classroom'] as string || '';
      const endSec: number = item['endSection'] as number || 0;

      let timeStr: string = '';
      if (startSec > 0 && startSec < SECTION_TIMES.length && endSec > 0 && endSec < SECTION_TIMES.length) {
        timeStr = SECTION_TIMES[startSec].split('-')[0] + '~' + SECTION_TIMES[endSec].split('-')[1];
      }

      if (day === todayDay) {
        form.todayNames.push(name);
        form.todayTimes.push(timeStr);
        form.todayRooms.push(room);
        form.todayTeachers.push(customTeacher);
        form.todayStarts.push(startSec);
      } else if (day === tomorrowDay) {
        form.tomorrowNames.push(name);
        form.tomorrowTimes.push(timeStr);
        form.tomorrowRooms.push(room);
        form.tomorrowTeachers.push(customTeacher);
        form.tomorrowStarts.push(startSec);
      }
    }
    hilog.info(DOMAIN, TAG, 'mergeCustomCourses done: today=' + form.todayNames.length + ' tomorrow=' + form.tomorrowNames.length);
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
    hilog.info(DOMAIN, TAG, 'mergeExperimentPreview: items=' + data.length + ' currentWeek=' + currentWeek);

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
    hilog.info(DOMAIN, TAG, 'mergeExperimentPreview done: today=' + form.todayNames.length + ' tomorrow=' + form.tomorrowNames.length);
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

function mergeExamPreview(form: FormDataClass, currentWeek: number, localDay: number): void {
  try {
    const cached: string = PreferenceUtil.getString('exam_schedule_cache');
    if (cached.length === 0) { return; }
    const items: Object[] = JSON.parse(cached) as Object[];
    const todayDay: number = localDay;
    const tomorrowDay: number = todayDay === 7 ? 1 : todayDay + 1;

    hilog.info(DOMAIN, TAG, 'mergeExamPreview: items=' + items.length + ' currentWeek=' + currentWeek);

    for (let i: number = 0; i < items.length; i++) {
      const item: Record<string, Object> = items[i] as Record<string, Object>;
      const ksrq: string = item['ksrq'] as string || '';
      const kssjms: string = item['kssjms'] as string || '';
      if (!ksrq || !kssjms) continue;

      // 计算考试周次
      const dateParts: string[] = ksrq.split('-');
      const examDate: Date = new Date(parseInt(dateParts[0]), parseInt(dateParts[1]) - 1, parseInt(dateParts[2]));
      const startDate: Date = getSemesterStartDate();
      const diffDays: number = Math.floor((examDate.getTime() - startDate.getTime()) / 86400000);
      const weekNum: number = Math.floor(diffDays / 7) + 1;
      const weekday: number = examDate.getDay() === 0 ? 7 : examDate.getDay();

      if (weekNum !== currentWeek) continue;

      // 解析考试时间
      const spaceIdx: number = kssjms.indexOf(' ');
      const timeWithDay: string = spaceIdx >= 0 ? kssjms.substring(spaceIdx + 1) : kssjms;
      const parenIdx: number = timeWithDay.indexOf('(');
      const timeOnly: string = parenIdx >= 0 ? timeWithDay.substring(0, parenIdx) : timeWithDay;
      const timeParts: string[] = timeOnly.split('-');
      const timeStr: string = timeParts.length >= 2 ? timeParts[0].trim() + '-' + timeParts[1].trim() : timeOnly;

      const name: string = (item['kcm'] as string) || (item['ksmc'] as string) || '考试';
      const room: string = (item['jasmc'] as string) || '';
      const weekDayNames: string[] = ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
      const examTimeDesc: string = timeOnly + ' ' + weekDayNames[examDate.getDay() || 7];

      hilog.info(DOMAIN, TAG, 'Exam[' + i + ']: name=' + name + ' weekday=' + weekday + ' time=' + timeStr);

      if (weekday === todayDay) {
        form.todayExamNames.push('📝 ' + name);
        form.todayExamTimes.push(examTimeDesc);
        form.todayExamRooms.push(room);
      } else if (weekday === tomorrowDay) {
        form.tomorrowExamNames.push('📝 ' + name);
        form.tomorrowExamTimes.push(examTimeDesc);
        form.tomorrowExamRooms.push(room);
      }
    }

    form.todayExamCount = form.todayExamNames.length;
    form.tomorrowExamCount = form.tomorrowExamNames.length;
    hilog.info(DOMAIN, TAG, 'mergeExamPreview done: today=' + form.todayExamCount + ' tomorrow=' + form.tomorrowExamCount);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'mergeExamPreview error: ' + JSON.stringify(e));
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
  hilog.info(DOMAIN, TAG, 'buildFormData: now.getDay=' + now.getDay() + ' localDay=' + localDay);

  const hh: string = now.getHours() < 10 ? '0' + now.getHours() : String(now.getHours());
  const mm: string = now.getMinutes() < 10 ? '0' + now.getMinutes() : String(now.getMinutes());
  form.lastRefresh = '更新时间: ' + (now.getMonth() + 1) + '月' + now.getDate() + '日 ' + hh + ':' + mm;

  const dayOfWeek: number = now.getDay();
  form.isWeekend = (localDay === 6 || localDay === 7); // localDay: 6=周六 7=周日
  form.showTomorrow = showTomorrow;
  hilog.info(DOMAIN, TAG, 'buildFormData: rawDayOfWeek=' + dayOfWeek + ' localDay=' + localDay + ' cacheLen=' + (cache ? cache.length : 0));

  // ── 加载手动添加课程 ──
  mergeCustomCourses(form, context);

  // ── 加载实验数据 ──
  mergeExperimentPreview(form, currentWeek, localDay);
  mergePhysicsPreview(form, currentWeek, localDay);

  // ── 加载考试数据 ──
  mergeExamPreview(form, currentWeek, localDay);

  if (!cache || cache.length === 0) {
    form.todayCount = form.todayNames.length;
    form.tomorrowCount = form.tomorrowNames.length;
    form.todayExamCount = form.todayExamNames.length;
    form.tomorrowExamCount = form.tomorrowExamNames.length;
    form.isEmpty = form.todayNames.length === 0 && form.todayExamNames.length === 0;
    sortEntries(form.todayNames, form.todayTimes, form.todayRooms, form.todayTeachers, form.todayStarts);
    sortEntries(form.tomorrowNames, form.tomorrowTimes, form.tomorrowRooms, form.tomorrowTeachers, form.tomorrowStarts);
    hilog.info(DOMAIN, TAG, 'buildFormData done (no cache): today=' + form.todayCount + ' tomorrow=' + form.tomorrowCount +
      ' examToday=' + form.todayExamCount + ' examTomorrow=' + form.tomorrowExamCount);
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

    hilog.info(DOMAIN, TAG, 'buildFormData: rows.length=' + rows.length + ' currentWeek=' + currentWeek);

    // ── 诊断：打印所有周一（SKXQ=1）课程及其周次过滤结果 ──
    const todayWkDay: number = localDay;
    for (let di: number = 0; di < rows.length; di++) {
      const rd: Record<string, Object> = rows[di] as Record<string, Object>;
      // 打印前3行的所有字段名，确认 SKXQ 字段名
      if (di < 3) {
        hilog.info(DOMAIN, TAG, 'MONDAY_FIELDS[' + di + '] keys=' + Object.keys(rd).join(','));
      }
      const wd: number = parseInt(String(rd['SKXQ'] || rd['skxq'] || '0')) || 0;
      if (wd === todayWkDay) {
        const skzc_raw: string = String(rd['SKZC'] || '');
        const wl: boolean[] = parseWeekStr(skzc_raw, 25);
        hilog.info(DOMAIN, TAG, 'MONDAY diag[' + di + ']: KCM=' + String(rd['KCM'] || '') +
          ' SKZC=' + skzc_raw + ' SKZC_len=' + skzc_raw.length +
          ' weekList[' + currentWeek + ']=' + wl[currentWeek]);
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
        hilog.info(DOMAIN, TAG, 'row[' + i + '] SKXQ=' + weekday + ' SKZC=' + skzc + ' KCM=' + name);
      }
      // 诊断：所有今天的行
      const weekList: boolean[] = parseWeekStr(skzc, 25);
      if (weekday === localDay) {
        hilog.info(DOMAIN, TAG, 'MAIN_LOOP_TODAY[' + i + '] KCM=' + name + ' SKZC=' + skzc + ' weekList[13]=' + weekList[currentWeek]);
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

    form.todayExamCount = form.todayExamNames.length;
    form.tomorrowExamCount = form.tomorrowExamNames.length;

    form.isEmpty = form.todayNames.length === 0 && form.todayExamNames.length === 0;
    hilog.info(DOMAIN, TAG, 'buildFormData done: today=' + form.todayCount + ' tomorrow=' + form.tomorrowCount +
      ' rows=' + totalRows + ' weekdaySkip=' + weekdayFiltered + ' weekSkip=' + weekFiltered);

  } catch (e) {
    hilog.error(DOMAIN, TAG, 'parse cache failed: ' + JSON.stringify(e));
  }

  return form;
}

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want) {
    hilog.info(DOMAIN, TAG, 'onAddForm');
    const cache: string | null = readClassCache(this.context);
    return formBindingData.createFormBindingData(buildFormData(cache, false, this.context));
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm formId=' + formId);
    const cache: string | null = readClassCache(this.context);
    const data: FormDataClass = buildFormData(cache, showTomorrowFlag, this.context);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
      .then(() => { hilog.info(DOMAIN, TAG, 'updateForm success'); })
      .catch((err: Error) => { hilog.error(DOMAIN, TAG, 'updateForm failed: ' + JSON.stringify(err)); });
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent formId=' + formId + ' msg=' + message);
    let msgObj: Record<string, string> | null = null;
    try {
      msgObj = JSON.parse(message) as Record<string, string>;
    } catch (_) {
      // not JSON
    }
    if (msgObj && msgObj['msgTest'] === 'toggle') {
      showTomorrowFlag = !showTomorrowFlag;
      hilog.info(DOMAIN, TAG, 'toggle showTomorrow=' + showTomorrowFlag);
    }
    const cache: string | null = readClassCache(this.context);
    const data: FormDataClass = buildFormData(cache, showTomorrowFlag, this.context);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
      .then(() => { hilog.info(DOMAIN, TAG, 'formEvent update success'); })
      .catch((err: Error) => { hilog.error(DOMAIN, TAG, 'formEvent update failed: ' + JSON.stringify(err)); });
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm formId=' + formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
