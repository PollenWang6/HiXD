// CourseReminderService.ets — 上课前通知服务
// 基于 @ohos.reminderAgentManager 后台代理提醒
// 参考 Flutter Traintime PDA 的 CourseReminderService 实现

import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CacheService } from './CacheService';
import { SemesterUtil } from './EhallService';

const TAG = 'CourseReminderService';

// 课程节次时间表 — 与 Flutter timeList 保持一致
export const TIME_LIST: string[] = [
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

// 节次时间表 — 与 SYSJ_SECTION_TIMES 一致（含结束时间，用于实验）
export const SECTION_TIMES: string[] = [
  '08:30', '09:15', '09:20', '10:05', '10:25', '11:10', '11:15', '12:00',
  '14:00', '14:45', '14:50', '15:35', '15:55', '16:40', '16:45', '17:30',
  '19:00', '19:45', '19:55', '20:35', '20:40', '21:25',
];

export class ClassTime {
  hour: number = 0;
  minute: number = 0;
}

// ==================== 配置 ====================

export interface CourseReminderConfig {
  courseEnabled: boolean;
  courseMinutesBefore: number;

  experimentEnabled: boolean;
  experimentMinutesBefore: number;
  experimentDoubleReminder: boolean;
  experimentDayBeforeHour: number;
  experimentDayBeforeMinute: number;

  examEnabled: boolean;
  examMinutesBefore: number;
  examDoubleReminder: boolean;
  examDayBeforeHour: number;
  examDayBeforeMinute: number;
}

// 保存的提醒元数据
export interface CourseReminderInfo {
  reminderId: number;
  courseKey: string;       // 唯一键（课程/实验/考试各有不同的 key 规则）
  courseName: string;
  teacher: string;
  location: string;
  weekDay: number;
  startClass: number;
  notifyHour: number;
  notifyMinute: number;
}

// 从缓存获取的扁平化条目
export interface FlatCourse {
  courseName: string;
  teacher: string;
  location: string;
  weekDay: number;
  startClass: number;
  endClass: number;
  courseKey: string;
  skzc: string;
  isExperiment: boolean;
}

// 用于增量对比的待发布条目
interface PendingReminder {
  key: string;
  name: string;
  teacher: string;
  location: string;
  notifyHour: number;
  notifyMinute: number;
  weekDay: number;
  startClass: number;
  type: 'course' | 'experiment' | 'exam';
  // course
  courseObj?: FlatCourse;
  weekIndex?: number;  // 0=全周重复
  // experiment
  specificDate?: Date;
  // exam
  // (uses specificDate)
}

export class CourseReminderService {
  private static instance: CourseReminderService;
  private cache: CacheService = CacheService.getInstance();
  private context: common.UIAbilityContext | null = null;

  static readonly MINUTES_OPTIONS: number[] = [5, 10, 15, 20, 30, 60];
  static readonly HOUR_OPTIONS: number[] = [1, 2, 3, 6, 12, 24];
  static readonly DEF_MINUTES_BEFORE: number = 5;

  // Preferences keys
  static readonly PREF_COURSE_ENABLED = 'cr_course_enabled';
  static readonly PREF_COURSE_MINUTES = 'cr_course_minutes';
  static readonly PREF_EXP_ENABLED = 'cr_exp_enabled';
  static readonly PREF_EXP_MINUTES = 'cr_exp_minutes';
  static readonly PREF_EXP_DOUBLE = 'cr_exp_double';
  static readonly PREF_EXP_DB_HOUR = 'cr_exp_db_hour';
  static readonly PREF_EXP_DB_MIN = 'cr_exp_db_min';
  static readonly PREF_EXAM_ENABLED = 'cr_exam_enabled';
  static readonly PREF_EXAM_MINUTES = 'cr_exam_minutes';
  static readonly PREF_EXAM_DOUBLE = 'cr_exam_double';
  static readonly PREF_EXAM_DB_HOUR = 'cr_exam_db_hour';
  static readonly PREF_EXAM_DB_MIN = 'cr_exam_db_min';
  static readonly PREF_REMINDER_IDS = 'course_reminder_ids';

  private constructor() {}

  static getInstance(): CourseReminderService {
    if (!CourseReminderService.instance) {
      CourseReminderService.instance = new CourseReminderService();
    }
    return CourseReminderService.instance;
  }

  setContext(ctx: common.UIAbilityContext): void {
    this.context = ctx;
  }

  // ==================== 配置读写 ====================

  getConfig(): CourseReminderConfig {
    return {
      courseEnabled: PreferenceUtil.getBool(CourseReminderService.PREF_COURSE_ENABLED, false),
      courseMinutesBefore: PreferenceUtil.getNumber(CourseReminderService.PREF_COURSE_MINUTES, 5),

      experimentEnabled: PreferenceUtil.getBool(CourseReminderService.PREF_EXP_ENABLED, false),
      experimentMinutesBefore: PreferenceUtil.getNumber(CourseReminderService.PREF_EXP_MINUTES, 5),
      experimentDoubleReminder: PreferenceUtil.getBool(CourseReminderService.PREF_EXP_DOUBLE, false),
      experimentDayBeforeHour: PreferenceUtil.getNumber(CourseReminderService.PREF_EXP_DB_HOUR, 20),
      experimentDayBeforeMinute: PreferenceUtil.getNumber(CourseReminderService.PREF_EXP_DB_MIN, 0),

      examEnabled: PreferenceUtil.getBool(CourseReminderService.PREF_EXAM_ENABLED, false),
      examMinutesBefore: PreferenceUtil.getNumber(CourseReminderService.PREF_EXAM_MINUTES, 30),
      examDoubleReminder: PreferenceUtil.getBool(CourseReminderService.PREF_EXAM_DOUBLE, false),
      examDayBeforeHour: PreferenceUtil.getNumber(CourseReminderService.PREF_EXAM_DB_HOUR, 20),
      examDayBeforeMinute: PreferenceUtil.getNumber(CourseReminderService.PREF_EXAM_DB_MIN, 0),
    };
  }

  isAnyEnabled(): boolean {
    const c = this.getConfig();
    return c.courseEnabled || c.experimentEnabled || c.examEnabled;
  }

  async setCourseEnabled(value: boolean): Promise<void> {
    await PreferenceUtil.putBool(CourseReminderService.PREF_COURSE_ENABLED, value);
  }

  async setCourseMinutesBefore(value: number): Promise<void> {
    await PreferenceUtil.putNumber(CourseReminderService.PREF_COURSE_MINUTES, value);
  }

  async setExperimentEnabled(value: boolean): Promise<void> {
    await PreferenceUtil.putBool(CourseReminderService.PREF_EXP_ENABLED, value);
  }

  async setExperimentMinutesBefore(value: number): Promise<void> {
    await PreferenceUtil.putNumber(CourseReminderService.PREF_EXP_MINUTES, value);
  }

  async setExperimentDouble(value: boolean): Promise<void> {
    await PreferenceUtil.putBool(CourseReminderService.PREF_EXP_DOUBLE, value);
  }

  async setExperimentDayBeforeTime(hour: number, minute: number): Promise<void> {
    await PreferenceUtil.putNumber(CourseReminderService.PREF_EXP_DB_HOUR, hour);
    await PreferenceUtil.putNumber(CourseReminderService.PREF_EXP_DB_MIN, minute);
  }

  async setExamEnabled(value: boolean): Promise<void> {
    await PreferenceUtil.putBool(CourseReminderService.PREF_EXAM_ENABLED, value);
  }

  async setExamMinutesBefore(value: number): Promise<void> {
    await PreferenceUtil.putNumber(CourseReminderService.PREF_EXAM_MINUTES, value);
  }

  async setExamDouble(value: boolean): Promise<void> {
    await PreferenceUtil.putBool(CourseReminderService.PREF_EXAM_DOUBLE, value);
  }

  async setExamDayBeforeTime(hour: number, minute: number): Promise<void> {
    await PreferenceUtil.putNumber(CourseReminderService.PREF_EXAM_DB_HOUR, hour);
    await PreferenceUtil.putNumber(CourseReminderService.PREF_EXAM_DB_MIN, minute);
  }

  // ==================== 权限管理 ====================

  async checkNotificationPermission(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (_err) {
      return false;
    }
  }

  async requestPermissions(): Promise<boolean> {
    try {
      const isEnabled = await notificationManager.isNotificationEnabled();
      if (isEnabled) return true;
      if (!this.context) {
        console.error(TAG, 'Context not set');
        return false;
      }
      await notificationManager.requestEnableNotification(this.context);
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      console.error(TAG, `Permission failed: ${(err as BusinessError).message}`);
      return false;
    }
  }

  // ==================== 数据获取 ====================

  async getCoursesFromCache(): Promise<FlatCourse[]> {
    const courses: FlatCourse[] = [];
    const semCode: string = PreferenceUtil.getString('current_semester', '');
    if (!semCode) return courses;
    try {
      await this.cache.init();
      const cached: string | null = await this.cache.get(`ct_${semCode}`);
      if (!cached) return courses;
      const rawList: Record<string, string>[] = JSON.parse(cached) as Record<string, string>[];
      const seen: Set<string> = new Set();
      for (const raw of rawList) {
        const skxq: string = raw['SKXQ'] || '';
        const ksjc: string = raw['KSJC'] || '';
        const jsjc: string = raw['JSJC'] || '';
        const kcm: string = raw['KCM'] || '';
        const kch: string = raw['KCH'] || '';
        const kxh: string = raw['KXH'] || '';
        const skzc: string = raw['SKZC'] || '';
        if (!skxq || !ksjc || !kcm) continue;
        const weekDay: number = parseInt(skxq);
        const startClass: number = parseInt(ksjc);
        if (isNaN(weekDay) || isNaN(startClass) || weekDay < 1 || weekDay > 7) continue;
        if (skzc.indexOf('1') < 0) continue;
        const courseKey: string = `c_${kch}_${kxh}_${weekDay}_${startClass}`;
        if (seen.has(courseKey)) continue;
        seen.add(courseKey);
        courses.push({
          courseName: kcm,
          teacher: raw['SKJS'] || '未知教师',
          location: raw['JASMC'] || '未知教室',
          weekDay: weekDay,
          startClass: startClass,
          endClass: jsjc ? parseInt(jsjc) : startClass,
          courseKey: courseKey,
          skzc: skzc,
          isExperiment: false,
        });
      }
      console.info(TAG, `Loaded ${courses.length} courses from cache`);
    } catch (e) {
      console.error(TAG, `Failed to load courses: ${JSON.stringify(e)}`);
    }
    return courses;
  }

  async getExperimentsFromCache(): Promise<ExpReminderData[]> {
    const items: ExpReminderData[] = [];
    const semCode: string = PreferenceUtil.getString('current_semester', '');
    if (!semCode) return items;
    try {
      const cached: string = PreferenceUtil.getString('sysj_exp_cache', '');
      if (!cached) return items;
      const co: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
      const data: Object[] = co['data'] as Object[] || [];
      const semesterStart: Date = SemesterUtil.getSemesterStartDate(semCode);
      for (const raw of data) {
        const item: Record<string, string> = raw as Record<string, string>;
        const name: string = item['experimentName'] || '';
        const weekday: string = item['weekday'] || '';
        const week: string = item['week'] || '';
        const startSec: string = item['startSection'] || '';
        const lab: string = item['lab'] || '';
        const teacher: string = item['teacher'] || '';
        if (!name || !weekday || !startSec || !week) continue;
        const wd: number = parseInt(weekday);
        const wk: number = parseInt(week);
        const sec: number = parseInt(startSec);
        if (isNaN(wd) || isNaN(wk) || isNaN(sec)) continue;
        // 计算日期
        const daysOffset: number = (wk - 1) * 7 + (wd - 1);
        const expDate: Date = new Date(semesterStart.getTime() + daysOffset * 24 * 60 * 60 * 1000);
        // 计算时间
        const timeIdx: number = (sec - 1) * 2;
        const timeStr: string = timeIdx >= 0 && timeIdx < SECTION_TIMES.length ? SECTION_TIMES[timeIdx] : '08:00';
        const tp: string[] = timeStr.split(':');
        expDate.setHours(parseInt(tp[0]), parseInt(tp[1]), 0, 0);
        items.push({
          name: name,
          teacher: teacher,
          location: lab,
          date: expDate,
          weekday: wd,
          startClass: sec,
          key: `exp_${name}_${wk}_${wd}_${sec}`.replace(/\s/g, '_'),
        });
      }
    } catch (e) {
      console.error(TAG, `Failed to load experiments: ${JSON.stringify(e)}`);
    }
    return items;
  }

  async getExamsFromCache(): Promise<ExpReminderData[]> {
    const items: ExpReminderData[] = [];
    try {
      const cached: string = PreferenceUtil.getString('exam_schedule_cache', '');
      if (!cached) return items;
      const root: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
      const datas: Record<string, Object> = root['datas'] as Record<string, Object> || {};
      const wdksap: Record<string, Object> = datas['wdksap'] as Record<string, Object> || {};
      const rows: Object[] = wdksap['rows'] as Object[] || [];
      for (const raw of rows) {
        const item: Record<string, string> = raw as Record<string, string>;
        const kcm: string = item['KCM'] || '';
        const ksrq: string = (item['KSRQ'] || '').substring(0, 10);
        const kssjms: string = item['KSSJMS'] || '';
        const jasmc: string = item['JASMC'] || '';
        if (!kcm || !ksrq) continue;
        // 解析日期
        const dateParts: string[] = ksrq.split('-');
        if (dateParts.length !== 3) continue;
        const examDate: Date = new Date(parseInt(dateParts[0]), parseInt(dateParts[1]) - 1, parseInt(dateParts[2]), 8, 0, 0);
        // 尝试从 KSSJMS 解析具体时间
        const spaceIdx: number = kssjms.indexOf(' ');
        if (spaceIdx >= 0) {
          const parenIdx: number = kssjms.indexOf('(');
          const timeStr: string = (parenIdx >= 0 ? kssjms.substring(spaceIdx + 1, parenIdx) : kssjms.substring(spaceIdx + 1)).trim();
          const dashIdx: number = timeStr.indexOf('-');
          if (dashIdx >= 0) {
            const startTime: string = timeStr.substring(0, dashIdx);
            const tp: string[] = startTime.split(':');
            if (tp.length >= 2) {
              examDate.setHours(parseInt(tp[0]), parseInt(tp[1]), 0, 0);
            }
          }
        }
        items.push({
          name: kcm,
          teacher: '',
          location: jasmc,
          date: examDate,
          weekday: examDate.getDay() === 0 ? 7 : examDate.getDay(),
          startClass: 0,
          key: `exam_${kcm}_${ksrq}`.replace(/\s/g, '_'),
        });
      }
    } catch (e) {
      console.error(TAG, `Failed to load exams: ${JSON.stringify(e)}`);
    }
    return items;
  }

  // ==================== 时间计算 ====================

  getClassStartTime(startClass: number): ClassTime | null {
    if (startClass < 1 || startClass > TIME_LIST.length / 2) return null;
    const timeStr: string = TIME_LIST[(startClass - 1) * 2];
    const parts: string[] = timeStr.split(':');
    const result: ClassTime = new ClassTime();
    result.hour = parseInt(parts[0]);
    result.minute = parseInt(parts[1]);
    return result;
  }

  getNotifyTime(startHour: number, startMinute: number, minutesBefore: number): ClassTime {
    const totalMinutes: number = startHour * 60 + startMinute - minutesBefore;
    const h: number = ((totalMinutes % (24 * 60)) + 24 * 60) % (24 * 60);
    const result: ClassTime = new ClassTime();
    result.hour = Math.floor(h / 60);
    result.minute = h % 60;
    return result;
  }

  parseWeekBitmap(skzc: string): number[] {
    const weeks: number[] = [];
    for (let i: number = 0; i < skzc.length; i++) {
      if (skzc.charAt(i) === '1') weeks.push(i + 1);
    }
    return weeks;
  }

  isFullWeek(skzc: string, firstWeek: number, lastWeek: number): boolean {
    if (firstWeek < 1 || lastWeek > skzc.length) return false;
    for (let i: number = firstWeek; i <= lastWeek; i++) {
      if (skzc.charAt(i - 1) !== '1') return false;
    }
    return true;
  }

  calcDateForWeek(weekIndex: number, weekday: number, notifyHour: number, notifyMinute: number): Date | null {
    const semCode: string = PreferenceUtil.getString('current_semester', '');
    if (!semCode) return null;
    const start: Date = SemesterUtil.getSemesterStartDate(semCode);
    const daysOffset: number = (weekIndex - 1) * 7 + (weekday - 1);
    const date: Date = new Date(start.getTime() + daysOffset * 24 * 60 * 60 * 1000);
    date.setHours(notifyHour, notifyMinute, 0, 0);
    return date;
  }

  private calcFirstTriggerDate(weekDay: number, notifyHour: number, notifyMinute: number): Date {
    const now: Date = new Date();
    const currentDay: number = now.getDay() === 0 ? 7 : now.getDay();
    let diffDays: number = ((weekDay - currentDay) + 7) % 7;
    if (diffDays === 0) {
      const currentMinutes: number = now.getHours() * 60 + now.getMinutes();
      const targetMinutes: number = notifyHour * 60 + notifyMinute;
      if (targetMinutes <= currentMinutes) diffDays = 7;
    }
    const triggerDate: Date = new Date(now.getTime() + diffDays * 24 * 60 * 60 * 1000);
    triggerDate.setHours(notifyHour, notifyMinute, 0, 0);
    return triggerDate;
  }

  // ==================== 提醒发布 ====================

  private async publishCalendarReminder(
    title: string, content: string, dateTime: Date, ringDuration: number = 5,
    daysOfWeek?: number[], endDateTime?: Date,
  ): Promise<number | null> {
    try {
      const now: Date = new Date();
      if (dateTime.getTime() <= now.getTime()) return null;
      const request: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: {
          year: dateTime.getFullYear(), month: dateTime.getMonth() + 1, day: dateTime.getDate(),
          hour: dateTime.getHours(), minute: dateTime.getMinutes(), second: 0,
        },
        title: title,
        content: content,
        slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        actionButton: [{ title: '知道了', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }],
        ringDuration: ringDuration,
      };
      if (daysOfWeek && daysOfWeek.length > 0) {
        request.daysOfWeek = daysOfWeek;
      }
      if (endDateTime) {
        request.endDateTime = {
          year: endDateTime.getFullYear(), month: endDateTime.getMonth() + 1, day: endDateTime.getDate(),
          hour: 23, minute: 59,
        };
      }
      const reminderId: number = await reminderAgentManager.publishReminder(request);
      console.info(TAG, `Published: "${title}" at ${dateTime.toISOString()} id=${reminderId}`);
      return reminderId;
    } catch (err) {
      const error = err as BusinessError;
      console.error(TAG, `Publish failed: ${error.code} - ${error.message}`);
      return null;
    }
  }

  private buildCourseContent(name: string, teacher: string, location: string, minutesBefore: number): string {
    let content: string = `将在 ${minutesBefore} 分钟后开始\n科目: ${name}`;
    if (teacher) content += `\n教师: ${teacher}`;
    if (location) content += `\n地点: ${location}`;
    return content;
  }

  // ==================== 调度（增量对比） ====================

  async scheduleAllReminders(forceRebuild: boolean = true): Promise<number> {
    const config = this.getConfig();
    if (!this.isAnyEnabled()) {
      console.info(TAG, 'Nothing enabled, cancelling all');
      await this.cancelAllReminders();
      return 0;
    }

    console.info(TAG, `Scheduling (forceRebuild=${forceRebuild})`);

    const saved: string = PreferenceUtil.getString(CourseReminderService.PREF_REMINDER_IDS, '[]');
    const oldInfos: CourseReminderInfo[] = JSON.parse(saved) as CourseReminderInfo[];
    const oldMap: Map<string, CourseReminderInfo> = new Map();
    for (const info of oldInfos) oldMap.set(info.courseKey, info);

    // 收集待发布条目
    const pending: PendingReminder[] = [];
    const newInfos: CourseReminderInfo[] = [];

    // ---- 课程 ----
    if (config.courseEnabled) {
      const courses: FlatCourse[] = await this.getCoursesFromCache();
      const semCode: string = PreferenceUtil.getString('current_semester', '');
      const semesterStart: Date = SemesterUtil.getSemesterStartDate(semCode);
      for (const course of courses) {
        const activeWeeks: number[] = this.parseWeekBitmap(course.skzc);
        if (activeWeeks.length === 0) continue;
        const ct = this.getClassStartTime(course.startClass);
        if (!ct) continue;
        const nt = this.getNotifyTime(ct.hour, ct.minute, config.courseMinutesBefore);
        const firstWeek: number = activeWeeks[0];
        const lastWeek: number = activeWeeks[activeWeeks.length - 1];
        if (this.isFullWeek(course.skzc, firstWeek, lastWeek)) {
          pending.push({
            key: course.courseKey, name: course.courseName, teacher: course.teacher,
            location: course.location, notifyHour: nt.hour, notifyMinute: nt.minute,
            weekDay: course.weekDay, startClass: course.startClass,
            type: 'course', courseObj: course, weekIndex: 0,
          });
        } else {
          for (const wi of activeWeeks) {
            pending.push({
              key: `${course.courseKey}_w${wi}`, name: course.courseName, teacher: course.teacher,
              location: course.location, notifyHour: nt.hour, notifyMinute: nt.minute,
              weekDay: course.weekDay, startClass: course.startClass,
              type: 'course', courseObj: course, weekIndex: wi,
            });
          }
        }
      }
    }

    // ---- 实验 ----
    if (config.experimentEnabled) {
      const experiments: ExpReminderData[] = await this.getExperimentsFromCache();
      for (const exp of experiments) {
        const nt = this.getNotifyTime(exp.date.getHours(), exp.date.getMinutes(), config.experimentMinutesBefore);
        const triggerDate: Date = new Date(exp.date);
        triggerDate.setHours(nt.hour, nt.minute, 0, 0);
        pending.push({
          key: `exp_today_${exp.key}`, name: exp.name, teacher: exp.teacher,
          location: exp.location, notifyHour: nt.hour, notifyMinute: nt.minute,
          weekDay: exp.weekday, startClass: exp.startClass,
          type: 'experiment', specificDate: new Date(triggerDate),
        });
        // 双重提醒：前一天
        if (config.experimentDoubleReminder) {
          const dayBefore: Date = new Date(exp.date.getTime() - 24 * 60 * 60 * 1000);
          dayBefore.setHours(config.experimentDayBeforeHour, config.experimentDayBeforeMinute, 0, 0);
          pending.push({
            key: `exp_daybefore_${exp.key}`, name: exp.name, teacher: exp.teacher,
            location: exp.location,
            notifyHour: config.experimentDayBeforeHour, notifyMinute: config.experimentDayBeforeMinute,
            weekDay: exp.weekday, startClass: exp.startClass,
            type: 'experiment', specificDate: new Date(dayBefore),
          });
        }
      }
    }

    // ---- 考试 ----
    if (config.examEnabled) {
      const exams: ExpReminderData[] = await this.getExamsFromCache();
      for (const exam of exams) {
        const nt = this.getNotifyTime(exam.date.getHours(), exam.date.getMinutes(), config.examMinutesBefore);
        const triggerDate: Date = new Date(exam.date);
        triggerDate.setHours(nt.hour, nt.minute, 0, 0);
        pending.push({
          key: `exam_today_${exam.key}`, name: exam.name, teacher: exam.teacher,
          location: exam.location, notifyHour: nt.hour, notifyMinute: nt.minute,
          weekDay: exam.weekday, startClass: exam.startClass,
          type: 'exam', specificDate: new Date(triggerDate),
        });
        if (config.examDoubleReminder) {
          const dayBefore: Date = new Date(exam.date.getTime() - 24 * 60 * 60 * 1000);
          dayBefore.setHours(config.examDayBeforeHour, config.examDayBeforeMinute, 0, 0);
          pending.push({
            key: `exam_daybefore_${exam.key}`, name: exam.name, teacher: exam.teacher,
            location: exam.location,
            notifyHour: config.examDayBeforeHour, notifyMinute: config.examDayBeforeMinute,
            weekDay: exam.weekday, startClass: exam.startClass,
            type: 'exam', specificDate: new Date(dayBefore),
          });
        }
      }
    }

    // ---- 增量对比 ----
    let createdCount: number = 0;
    let keptCount: number = 0;
    let removedCount: number = 0;
    const semCode: string = PreferenceUtil.getString('current_semester', '');
    const semesterStart: Date = SemesterUtil.getSemesterStartDate(semCode);

    // 取消多余的
    for (const info of oldInfos) {
      let found: boolean = false;
      for (const p of pending) {
        if (p.key === info.courseKey) { found = true; break; }
      }
      if (forceRebuild || !found) {
        try {
          await reminderAgentManager.cancelReminder(info.reminderId);
          removedCount++;
        } catch (err) {
          if ((err as BusinessError).code !== 1700003) {
            console.warn(TAG, `Cancel failed for ${info.reminderId}`);
          }
        }
      }
    }

    // 发布新的 / 保留已有的
    for (const p of pending) {
      if (!forceRebuild && oldMap.has(p.key)) {
        newInfos.push(oldMap.get(p.key)!);
        keptCount++;
        continue;
      }

      let reminderId: number | null = null;

      if (p.type === 'course') {
        if (p.weekIndex === 0 && p.courseObj) {
          // 全周重复
          const weeks: number[] = this.parseWeekBitmap(p.courseObj.skzc);
          const lastW: number = weeks[weeks.length - 1];
          const lastDayOffset: number = (lastW - 1) * 7 + (p.courseObj.weekDay - 1);
          const endDate: Date = new Date(semesterStart.getTime() + lastDayOffset * 24 * 60 * 60 * 1000);
          endDate.setHours(23, 59, 0, 0);
          const dateTime: Date = this.calcFirstTriggerDate(p.weekDay, p.notifyHour, p.notifyMinute);
          reminderId = await this.publishCalendarReminder(
            `课程提醒`, this.buildCourseContent(p.name, p.teacher, p.location, config.courseMinutesBefore),
            dateTime, 5, [p.weekDay], endDate,
          );
        } else {
          // 一次性
          const date: Date | null = this.calcDateForWeek(p.weekIndex!, p.weekDay, p.notifyHour, p.notifyMinute);
          if (date) {
            reminderId = await this.publishCalendarReminder(
              `课程提醒`, this.buildCourseContent(p.name, p.teacher, p.location, config.courseMinutesBefore),
              date, 5,
            );
          }
        }
      } else if (p.type === 'experiment') {
        const label: string = p.key.indexOf('daybefore') >= 0 ? '明天有实验' : '实验提醒';
        const mins: number = p.key.indexOf('daybefore') >= 0 ? 0 : config.experimentMinutesBefore;
        if (p.specificDate) {
          reminderId = await this.publishCalendarReminder(
            label, this.buildCourseContent(p.name, p.teacher, p.location, mins),
            p.specificDate, 5,
          );
        }
      } else if (p.type === 'exam') {
        const label: string = p.key.indexOf('daybefore') >= 0 ? '明天有考试' : '考试提醒';
        const mins: number = p.key.indexOf('daybefore') >= 0 ? 0 : config.examMinutesBefore;
        if (p.specificDate) {
          reminderId = await this.publishCalendarReminder(
            label, this.buildCourseContent(p.name, p.teacher, p.location, mins),
            p.specificDate, 5,
          );
        }
      }

      if (reminderId !== null) {
        newInfos.push({
          reminderId: reminderId, courseKey: p.key, courseName: p.name,
          teacher: p.teacher, location: p.location, weekDay: p.weekDay,
          startClass: p.startClass, notifyHour: p.notifyHour, notifyMinute: p.notifyMinute,
        });
        createdCount++;
      }
    }

    await PreferenceUtil.putString(CourseReminderService.PREF_REMINDER_IDS, JSON.stringify(newInfos));
    console.info(TAG, `Schedule done: +${createdCount} created, ${keptCount} kept, -${removedCount} removed`);
    return newInfos.length;
  }

  async cancelAllReminders(): Promise<void> {
    try {
      const saved: string = PreferenceUtil.getString(CourseReminderService.PREF_REMINDER_IDS, '[]');
      const infos: CourseReminderInfo[] = JSON.parse(saved) as CourseReminderInfo[];
      let count: number = 0;
      for (const info of infos) {
        try { await reminderAgentManager.cancelReminder(info.reminderId); count++; }
        catch (err) { if ((err as BusinessError).code !== 1700003) console.warn(TAG, `Cancel fail ${info.reminderId}`); }
      }
      try { await reminderAgentManager.cancelAllReminders(); } catch (_e) { /* ignore */ }
      await PreferenceUtil.putString(CourseReminderService.PREF_REMINDER_IDS, '[]');
      console.info(TAG, `Cancelled ${count} reminders`);
    } catch (e) {
      console.error(TAG, `Cancel all failed: ${JSON.stringify(e)}`);
    }
  }

  async getActiveReminderCount(): Promise<number> {
    try { const r = await reminderAgentManager.getValidReminders(); return r.length; }
    catch (_err) { return 0; }
  }
}

// 实验/考试提醒数据
export interface ExpReminderData {
  name: string;
  teacher: string;
  location: string;
  date: Date;
  weekday: number;
  startClass: number;
  key: string;
}
