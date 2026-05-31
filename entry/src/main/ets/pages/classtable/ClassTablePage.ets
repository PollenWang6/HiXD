// ClassTablePage.ets — 支持点击查看所有冲突课程版（已修复重叠课程覆盖问题）
import { ThemeColors } from '../../utils/ThemeColors';
import { EhallService, SemesterUtil, DataParser, ClassItemModel, ExamItemModel } from '../../services/EhallService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';

import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';
import { calendarManager } from '@kit.CalendarKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

// 课程卡片背景色（较鲜艳的色块，配白色文字）
const CLASS_COLORS: string[] = ['#42A5F5', '#AB47BC', '#FF7043', '#66BB6A', '#EC407A', '#26C6DA', '#FFCA28', '#8BC34A', '#7E57C2', '#29B6F6'];
// 实验卡片背景色（橙色系，区分课程）
const EXP_COLORS: string[] = ['#FF8C00', '#E65100', '#F57C00', '#EF6C00', '#FF9800'];
// 考试卡片背景色（红色系，区分课程和实验）
const EXAM_COLORS: string[] = ['#E53935', '#C62828', '#D32F2F', '#F44336', '#EF5350'];
const DAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const DAY_COUNT = 7;
const SECTION_COUNT = 11;

// 分隔行：午休(第4-5节间)、放学(第8-9节间)
const BREAK_HEIGHT: number = 22;
const BREAK_LUNCH: number = 1;  // 标识：午休
const BREAK_DINNER: number = 2; // 标识：放学
const BREAK_LABELS: Record<number, string> = { '1': '午休', '2': '放学' };
const BREAK_TIMES: Record<number, string> = { '1': '12:00-14:00', '2': '17:30-19:00' };

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
interface SelectOption {
  value: string;
}

class CustomCourseItem {
  name: string = '';
  teacher: string = '';
  classroom: string = '';
  day: number = 0;
  startSection: number = 0;
  endSection: number = 0;
  weekList: number[] = [];
  colorIndex: number = 0;
}

class ClassCell {
  name: string = '';
  teacher: string = '';
  classroom: string = '';
  day: number = 0;
  startSection: number = 0;
  endSection: number = 0;
  weekList: boolean[] = [];
  weekDesc: string = '';
  kch: string = '';
  kxh: string = '';
  colorIndex: number = 0;
  isExperiment: boolean = false;  // 实验标记
  experimentProject: string = '';  // 实验项目名
  isExam: boolean = false;        // 考试标记
  examDate: string = '';          // 考试日期(yyyy-MM-dd)
  examTimeDesc: string = '';      // 考试时间描述(如"08:30-10:05")
  examSeat: string = '';          // 座位号
  // 考试精确定位（像素级，不按节次对齐）
  examPixelY: number = 0;        // 考试卡片顶部Y偏移
  examPixelH: number = 0;        // 考试卡片高度
  isCustom: boolean = false;
}


@Component
export struct ClassTablePage {
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State addFormToast: string = '';
  @State currentWeek: number = 1;
  @State maxWeek: number = 25;  // 初始安全上限，实际由数据 SKZC 长度动态扩展
  @State semesterCode: string = '';
  @State classGrid: ClassCell[][][] = []; // 三维数组：[day][startSection] = [课程1, 课程2, ...]
  @State hasCache: boolean = false;
  @State refreshing: boolean = false;
  @State showCacheBanner: boolean = false;

  // 弹窗状态改为支持显示多个课程
  @State showDetailDialog: boolean = false;
  @State selectedDay: number = 0;
  @State selectedSection: number = 0;
  @State currentConflictCells: ClassCell[] = [];

  @State cardScale: number = 0.85;
  @State cardOpacity: number = 0;
  @State maskOpacity: number = 0;

  // 手动添加课程弹窗状态
  @State customList: CustomCourseItem[] = [];
  @State showAddCourseDialog: boolean = false;
  @State addCourseName: string = '';
  @State addCourseTeacher: string = '';
  @State addCourseClassroom: string = '';
  @State addCourseWeekList: boolean[] = [];
  @State editingCustomIndex: number = -1;  // -1=add, >=0=edit
  @State addCourseDay: number = 0;
  @State addCourseStartSection: number = 0;
  @State addCourseEndSection: number = 0;

  // 日历提醒选择弹窗
  @State showReminderDialog: boolean = false;
  @State calendarImporting: boolean = false;
  @State calendarImportMsg: string = '';
  @State reminderMinutes: number = 10;
  @State reminderMode: number = 0; // 0=fixed, 1=custom, 2=none
  @State customReminderInput: string = '30';

  private ehall = EhallService.getInstance();
  private localFilePath: string = '';
  private readonly EXP_CACHE_KEY: string = 'sysj_exp_cache';
  private lastRenderedRaw: string = '';
  private ROW_HEIGHT: number = 56;
  private swipeStartX: number = 0;
  @State slideOffsetX: number = 0;
  @State slideOpacity: number = 1;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  private isAnimating: boolean = false;

  aboutToAppear(): void {
    this.semesterCode = SemesterUtil.getCurrentSemesterCode();
    this.currentWeek = SemesterUtil.calcCurrentWeekFromNow();
    this.initGrid();
    this.waitAndLoad();
  }

  private async waitAndLoad(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    this.localFilePath = context.filesDir + '/class_table_' + this.semesterCode + '.json';

    const local = this.readLocalClassTable();
    if (local) {
      this.renderClassTable(local);
      this.loading = false;
      this.hasCache = true;
      return;
    }

    await this.fetchAndSave();

    try {
      const existing: string = PreferenceUtil.getString('ids_account');
      if (!existing) {
        const sid: string = await this.ehall.fetchStudentId();
        if (sid) {
          await PreferenceUtil.putString('ids_account', sid);
        }
      }
    } catch (_) {}

    // 首次登录后 cookie/session 可能还未就绪，课表为空时自动重试
    if (this.isClassGridEmpty() && PreferenceUtil.getBool('is_logged_in')) {
      console.error('ClassTablePage', 'First load empty, auto-retrying in 2s...');
      setTimeout(() => {
        this.loadTable(true);
      }, 2000);
    }
  }

  private isClassGridEmpty(): boolean {
    for (let d = 1; d < this.classGrid.length; d++) {
      if (this.classGrid[d]) {
        for (let s = 1; s < this.classGrid[d].length; s++) {
          if (this.classGrid[d][s] && this.classGrid[d][s].length > 0) {
            return false;
          }
        }
      }
    }
    return true;
  }

  private initGrid(): void {
    const grid: ClassCell[][][] = [];
    for (let d = 0; d <= DAY_COUNT; d++) {
      grid[d] = [];
      for (let s = 0; s <= SECTION_COUNT; s++) {
        grid[d][s] = [];
      }
    }
    this.classGrid = grid;
  }

  private getDateStr(week: number, dayIdx: number): string {
    const startDate: Date = SemesterUtil.getSemesterStartDate(this.semesterCode);
    const dayOfWeek = startDate.getDay();
    const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
    const monday = new Date(startDate);
    monday.setDate(startDate.getDate() + mondayOffset);
    const targetDate = new Date(monday);
    targetDate.setDate(monday.getDate() + (week - 1) * 7 + (dayIdx - 1));
    return (targetDate.getMonth() + 1) + '月' + targetDate.getDate() + '日';
  }

  private getWeekRangeLabel(): string {
    const startDate = this.getDateStr(this.currentWeek, 1);
    const endDate = this.getDateStr(this.currentWeek, 7);
    return '第' + this.currentWeek + '周 · ' + startDate + ' - ' + endDate;
  }

  private readLocalClassTable(): string | null {
    if (!this.localFilePath) return null;
    try {
      const file: fileIo.File = fileIo.openSync(this.localFilePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(this.localFilePath);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const decoder = util.TextDecoder.create('utf-8');
      const result: string = decoder.decodeToString(new Uint8Array(buf));
      if (result.length > 0) return result;
    } catch (_) {}
    return null;
  }

  private writeLocalClassTable(raw: string): void {
    if (!this.localFilePath) return;
    try {
      const encoder = new util.TextEncoder();
      const encoded: Uint8Array = encoder.encodeInto(raw);
      const file: fileIo.File = fileIo.openSync(this.localFilePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, encoded.buffer);
      fileIo.closeSync(file);
    } catch (e) {
      console.warn('ClassTablePage', 'writeLocal failed: ' + JSON.stringify(e));
    }
  }

  private async fetchAndSave(): Promise<void> {
    this.errorMsg = '';
    const sid: string = PreferenceUtil.getString('ids_account');
    try {
      const raw: string = await this.ehall.getClassTable(this.semesterCode, sid, true);
      this.renderClassTable(raw);
      this.lastRenderedRaw = raw;
      this.writeLocalClassTable(raw);
      this.hasCache = true;
    } catch (e) {
      if (!this.hasCache) {
        this.errorMsg = '加载课程表失败，请检查网络';
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  async loadTable(forceRefresh: boolean = false): Promise<void> {
    if (forceRefresh) {
      this.refreshing = true;
      this.errorMsg = '';
      const sid: string = PreferenceUtil.getString('ids_account');
      try {
        const raw: string = await this.ehall.getClassTable(this.semesterCode, sid, true);
        if (raw !== this.lastRenderedRaw) {
          this.renderClassTable(raw);
          this.lastRenderedRaw = raw;
        }
        this.writeLocalClassTable(raw);
      } catch (e) {
        this.errorMsg = '刷新失败，请检查网络';
      } finally {
        this.refreshing = false;
      }
    } else {
      const local = this.readLocalClassTable();
      if (local) {
        this.renderClassTable(local);
        this.loading = false;
        this.hasCache = true;
      } else {
        await this.fetchAndSave();
      }
    }
  }

  private renderClassTable(raw: string): void {
    const items: ClassItemModel[] = DataParser.parseClassTable(raw);
    const nameColorMap = new Map<string, number>();
    let colorIdx = 0;
    const grid: ClassCell[][][] = [];
    for (let d = 0; d <= DAY_COUNT; d++) {
      grid[d] = [];
      for (let s = 0; s <= SECTION_COUNT; s++) {
        grid[d][s] = [];
      }
    }

    for (const item of items) {
      const weekList = this.parseWeekList(item.skzc);
      if (weekList.length > this.maxWeek) this.maxWeek = weekList.length;
      if (!nameColorMap.has(item.kcm)) {
        nameColorMap.set(item.kcm, colorIdx % CLASS_COLORS.length);
        colorIdx++;
      }
      const cell = new ClassCell();
      cell.name = item.kcm;
      cell.teacher = item.skjs;
      cell.classroom = item.jasmc;
      cell.day = parseInt(item.skxq) || 0;
      cell.startSection = parseInt(item.ksjc) || 0;
      cell.endSection = parseInt(item.jsjc) || 0;
      cell.weekList = weekList;
      cell.weekDesc = this.formatWeekDesc(weekList);
      cell.kch = item.kch;
      cell.kxh = item.kxh;
      cell.colorIndex = nameColorMap.get(item.kcm) || 0;

      if (cell.day > 0 && cell.startSection > 0 && cell.endSection >= cell.startSection) {
        grid[cell.day][cell.startSection].push(cell);
      }
    }
    // 合并实验数据到课程表
    this.mergeExperimentData(grid);
    // 合并自定义课程
    this.loadCustomCourses(grid);
    this.classGrid = grid;
    // 诊断：打印今天（当前周）的课程列表，与卡片对比
    this.diagTodayGrid(grid);
    // 异步加载考试数据（不阻塞课程表渲染）
    this.loadExamData();
  }

  private diagTodayGrid(grid: ClassCell[][][]): void {
    const cw: number = this.currentWeek;
    const today: number = 1; // 周一，硬编码用于诊断
    let count: number = 0;
    for (let s: number = 1; s <= SECTION_COUNT; s++) {
      const cells: ClassCell[] = grid[today][s] || [];
      for (let ci: number = 0; ci < cells.length; ci++) {
        const c: ClassCell = cells[ci];
        if (c.weekList.length > cw && c.weekList[cw]) {
          const prefix: string = c.isExperiment ? '🧪' : (c.isCustom ? '✏️' : '📘');
          const tag: string = c.isExperiment ? 'EXP' : (c.isCustom ? 'CUSTOM' : 'API');
          console.error('ClassTablePage', 'TODAY_GRID[' + count + ']: ' + prefix + ' ' + c.name +
            ' sec=' + c.startSection + '-' + c.endSection +
            ' room=' + c.classroom + ' type=' + tag);
          count++;
        }
      }
    }
    console.error('ClassTablePage', 'TODAY_GRID total=' + count + ' weekday=' + today + ' week=' + cw);
  }

  private mergeExperimentData(grid: ClassCell[][][]): void {
    const cached = PreferenceUtil.getString(this.EXP_CACHE_KEY);
    if (cached.length === 0) return;
    try {
      const cacheObj: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
      const raw: Object[] = cacheObj['data'] as Object[];
      if (!(raw instanceof Array) || raw.length === 0) return;
      const items: Record<string, string>[] = raw as Record<string, string>[];
      let expColorIdx: number = 0;
      for (const item of items) {
        const weekNum: number = parseInt(item['week']) || 0;
        const weekday: number = parseInt(item['weekday']) || 0;
        const startSec: number = parseInt(item['startSection']) || 0;
        const endSec: number = parseInt(item['endSection']) || 0;
        if (weekday < 1 || weekday > 7 || startSec < 1 || endSec < startSec) continue;

        // 构建周列表：实验只在该周出现（0-indexed: 第N周对应 weekList[N-1]）
        const weekList: boolean[] = [];
        for (let w = 0; w < 25; w++) weekList.push(w === weekNum - 1);

        const cell = new ClassCell();
        cell.name = item['experimentName'] || '实验';
        cell.teacher = item['teacher'] || '';
        cell.classroom = item['lab'] || '';
        console.error('ClassTablePage', 'mergeExp: name=' + cell.name + ' lab=[' + item['lab'] + '] classroom=[' + cell.classroom + ']');
        cell.day = weekday;
        cell.startSection = startSec;
        cell.endSection = endSec;
        cell.weekList = weekList;
        cell.weekDesc = '第' + weekNum + '周';
        cell.kch = item['courseCode'] || '';
        cell.kxh = item['groupId'] || '';
        cell.isExperiment = true;
        cell.experimentProject = item['experimentProject'] || '';
        cell.colorIndex = expColorIdx % EXP_COLORS.length;
        expColorIdx++;

        if (weekday <= DAY_COUNT && startSec <= SECTION_COUNT) {
          grid[weekday][startSec].push(cell);
        }
      }
    } catch (e) {
      console.warn('ClassTablePage', 'mergeExperimentData error: ' + String(e));
    }
  }

  // 从 _custom.json 加载自定义课程合并到 grid
  private loadCustomCourses(grid: ClassCell[][][]): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const customPath: string = context.filesDir + '/class_table_' + this.semesterCode + '_custom.json';
      console.error('ClassTablePage', 'loadCustomCourses: path=' + customPath + ' semesterCode=' + this.semesterCode);
      console.error('ClassTablePage', 'loadCustomCourses: fileExists=' + fileIo.accessSync(customPath));
      const file = fileIo.openSync(customPath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(customPath);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const decoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(new Uint8Array(buf));
      console.error('ClassTablePage', 'loadCustomCourses: text=' + text.substring(0, 500));
      const items: CustomCourseItem[] = JSON.parse(text) as CustomCourseItem[];

      console.error('ClassTablePage', 'loadCustomCourses: items.length=' + items.length);
      this.customList = items;
        // 先清除 grid 中所有自定义课程，避免累积重复
        for (let cd = 1; cd <= 7; cd++) {
          for (let cs = 1; cs <= 11; cs++) {
            const filtered: ClassCell[] = [];
            for (let ci = 0; ci < grid[cd][cs].length; ci++) {
              if (!grid[cd][cs][ci].isCustom) {
                filtered.push(grid[cd][cs][ci]);
              }
            }
            grid[cd][cs] = filtered;
          }
        }
              for (let idx = 0; idx < items.length; idx++) {
        const item: CustomCourseItem = items[idx];
        const cell = new ClassCell();
        cell.name = item.name;
        cell.teacher = item.teacher;
        cell.classroom = item.classroom;
        cell.day = item.day;
        cell.startSection = item.startSection;
        cell.endSection = item.endSection;
        // 统一为 0-indexed: week W at index W-1（与 parseWeekList 一致）
        const weekList: boolean[] = [];
        for (let w = 0; w < 26; w++) weekList.push(false);
        // 旧数据: 0-indexed in file → no shift. 新数据: 1-indexed in file → shift -1.
        const isOldFormat: boolean = item.weekList.length > 0 && item.weekList.length < 26;
        if (isOldFormat) {
          for (let w = 0; w < item.weekList.length && w < 26; w++) {
            if (item.weekList[w] === 1) weekList[w] = true;
          }
        } else {
          for (let w = 1; w < item.weekList.length && w <= 25; w++) {
            if (item.weekList[w] === 1) weekList[w - 1] = true;
          }
        }
        cell.weekList = weekList;
        console.error('ClassTablePage', 'loadCustomCourses: item=' + cell.name + ' day=' + cell.day + ' sec=' + cell.startSection + '-' + cell.endSection + ' isOld=' + isOldFormat + ' wl[13]=' + weekList[13] + ' wl[12]=' + (weekList.length > 12 ? weekList[12] : '?'));
        cell.weekDesc = this.formatWeekDesc(weekList);
        cell.colorIndex = item.colorIndex;
        cell.isCustom = true;
        cell.isExperiment = false;
        if (cell.day > 0 && cell.startSection > 0 && cell.endSection >= cell.startSection) {
          grid[cell.day][cell.startSection].push(cell);
          console.error('ClassTablePage', 'loadCustomCourses: pushed to grid[' + cell.day + '][' + cell.startSection + ']');
        } else {
          console.error('ClassTablePage', 'loadCustomCourses: SKIP push day=' + cell.day + ' start=' + cell.startSection);
        }
      }
    } catch (e) {
      console.error('ClassTablePage', 'loadCustomCourses error: ' + String(e));
    }
  }

  private async loadExamData(): Promise<void> {
    // 只读缓存（由ExamPage写入），不主动请求API
    const cached: string = PreferenceUtil.getString('exam_schedule_cache');
    console.error('ClassTablePage', 'loadExamData: cached.length=' + cached.length);
    if (cached.length > 0) {
      try {
        const items: ExamItemModel[] = DataParser.parseExamSchedule(cached);
        console.error('ClassTablePage', 'loadExamData: parsed items=' + items.length);
        this.applyExamItems(items);
      } catch (e) {
        console.error('ClassTablePage', 'loadExamData parse error: ' + String(e));
      }
    } else {
      console.error('ClassTablePage', 'loadExamData: no exam cache found');
    }
  }

  private applyExamItems(items: ExamItemModel[]): void {
    console.error('ClassTablePage', 'applyExamItems: count=' + items.length + ' semesterCode=' + this.semesterCode);
    const startDate: Date = SemesterUtil.getSemesterStartDate(this.semesterCode);
    let examColorIdx: number = 0;
    // 先清除旧考试数据
    for (let d = 0; d <= DAY_COUNT; d++) {
      for (let s = 0; s <= SECTION_COUNT; s++) {
        this.classGrid[d][s] = this.classGrid[d][s].filter((c: ClassCell) => !c.isExam);
      }
    }
    for (const item of items) {
      const ksrq: string = item.ksrq;
      const kssjms: string = item.kssjms;
      if (!ksrq || !kssjms) continue;
      const dateParts: string[] = ksrq.split('-');
      const examDate: Date = new Date(
        parseInt(dateParts[0]),
        parseInt(dateParts[1]) - 1,
        parseInt(dateParts[2])
      );
      const diffMs: number = examDate.getTime() - startDate.getTime();
      const diffDays: number = Math.floor(diffMs / (24 * 60 * 60 * 1000));
      if (diffDays < 0) continue;
      const weekNum: number = Math.floor(diffDays / 7) + 1;
      const weekday: number = examDate.getDay() || 7;
      if (weekNum < 1 || weekNum > 25 || weekday < 1 || weekday > 7) continue;
      console.error('ClassTablePage', 'applyExam: ksrq=' + ksrq + ' weekNum=' + weekNum + ' weekday=' + weekday + ' currentWeek=' + this.currentWeek);
      // kssjms format: "2026-04-22 13:00-15:00(星期三)" — extract time portion only
      const spaceIdx: number = kssjms.indexOf(' ');
      const timeWithDay: string = spaceIdx >= 0 ? kssjms.substring(spaceIdx + 1) : kssjms;
      const parenIdx: number = timeWithDay.indexOf('(');
      const timeOnly: string = parenIdx >= 0 ? timeWithDay.substring(0, parenIdx) : timeWithDay;
      const timeParts: string[] = timeOnly.split('-');
      console.error('ClassTablePage', 'applyExam: kssjms=' + kssjms + ' timeOnly=' + timeOnly + ' startPart=' + timeParts[0] + ' endPart=' + timeParts[1]);
      const startY: number = this.timeToY(timeParts[0]);
      const endY: number = this.timeToY(timeParts[1]);
      console.error('ClassTablePage', 'applyExam: startY=' + startY + ' endY=' + endY + ' pixelH=' + (endY - startY));
      const cell = new ClassCell();
      cell.name = item.kcm || item.ksmc || '考试';
      cell.classroom = item.jasmc;
      cell.day = weekday;
      cell.startSection = 0;
      cell.endSection = 0;
      const weekList: boolean[] = [];
      for (let w = 0; w < 25; w++) weekList.push(w === weekNum - 1);
      cell.weekList = weekList;
      cell.weekDesc = '第' + weekNum + '周';
      cell.isExam = true;
      cell.examDate = ksrq.length > 10 ? ksrq.substring(0, 10) : ksrq;
      // 格式化为 "13:00-15:00 星期三"
      const weekDayNames: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
      cell.examTimeDesc = timeOnly + ' ' + weekDayNames[examDate.getDay()];
      cell.examSeat = item.zw;
      cell.examPixelY = startY;
      cell.examPixelH = Math.max(endY - startY, 20);
      cell.colorIndex = examColorIdx % EXAM_COLORS.length;
      examColorIdx++;
      if (weekday <= DAY_COUNT) {
        this.classGrid[weekday][0].push(cell);
      }
    }
  }

  private parseWeekList(skzc: string): boolean[] {
    const result: boolean[] = [];
    if (!skzc) return result;
    for (let i = 0; i < skzc.length; i++) result.push(skzc[i] === '1');
    return result;
  }

  private formatWeekDesc(weekList: boolean[]): string {
    const ranges: string[] = [];
    let i = 0;
    while (i < weekList.length) {
      if (weekList[i]) {
        const start = i + 1;
        let end = start;
        while (i + 1 < weekList.length && weekList[i + 1]) {
          i++;
          end = i + 1;
        }
        if (end === start) {
          ranges.push(`${start}周`);
        } else {
          ranges.push(`${start}-${end}周`);
        }
      }
      i++;
    }
    return ranges.join(', ');
  }

  build() {
    NavDestination() {
      Stack() {
        // 第一层：主页面内容
        Column() {
          this.buildHeader()
          if (this.showCacheBanner) {
            Row() {
              Text('当前显示的是缓存数据').fontSize(12).fontColor(ThemeColors.warning)
            }.width('100%').height(28).justifyContent(FlexAlign.Center)
            .backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
          }
          Divider().color('#F0F0F0')
          if (this.loading && !this.hasCache) {
            Column() {
              LoadingProgress().width(40).height(40).color('#2979FF')
              Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else if (this.errorMsg.length > 0) {
            Column() {
              Text('⚠️').fontSize(40)
              Text(this.errorMsg).fontSize(14).fontColor(ThemeColors.error).margin({ top: 8 })
              Button('重试').margin({ top: 12 }).onClick(() => { this.loadTable(); })
              if (this.errorMsg.includes('登录')) {
                Button('去登录').margin({ top: 8 })
                  .onClick(() => { router.pushUrl({ url: 'pages/login/LoginPage' }); })
              }
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            Column() {
              this.buildClassGrid()
            }.layoutWeight(1)
          }
        }.width('100%').height('100%').backgroundColor(ThemeColors.bgCard)
        .zIndex(0)

        // 第二层：半透明背景遮罩
        if (this.showDetailDialog) {
          Column()
            .width('100%').height('100%')
            .backgroundColor('rgba(0,0,0,0.7)')
            .opacity(this.maskOpacity)
            .onClick(() => { this.hideCellDetail(); })
            .zIndex(1)
        }

        // 刷新遮罩
        if (this.refreshing) {
          Column() {
            LoadingProgress().width(40).height(40).color('#2979FF')
            Text('刷新中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').height('100%')
          .backgroundColor(ThemeColors.isDark ? 'rgba(28,28,30,0.85)' : 'rgba(255,255,255,0.85)')
          .justifyContent(FlexAlign.Center)
          .zIndex(2)
        }

        // 第三层：课程详情弹窗（支持显示多个冲突课程）
        if (this.showDetailDialog) {
          Column() {
            // 顶部色条
            if (this.currentConflictCells.length > 0) {
              Row().width('100%').height(4)
                .backgroundColor(this.getCellColor(this.currentConflictCells[0]))
                .borderRadius({ topLeft: 12, topRight: 12 })
            }

            // 标题
            Text('第' + this.currentWeek + '周 ' + DAY_NAMES[this.selectedDay - 1] + ' 第' + this.selectedSection + '节')
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .margin({ top: 16, bottom: 12 }).width('100%')

            Divider().color('#F0F0F0')

            // 冲突课程列表
            if (this.currentConflictCells.length === 0) {
              Column() {
                Text('暂无课程信息').fontSize(14).fontColor(ThemeColors.textSecondary)
                  .margin({ top: 20, bottom: 20 })
              }.width('100%')
            } else {
              List() {
                ForEach(this.currentConflictCells, (cell: ClassCell, idx: number) => {
                  ListItem() {
                    Column() {
                      // 课程名（带颜色圆点）
                      Row() {
                        Row().width(8).height(8).borderRadius(4)
                          .backgroundColor(this.getCellColor(cell))
                          .margin({ right: 8 })
                        Text(cell.isExam ? '📝 ' + cell.name : (cell.isExperiment ? '🧪 ' + cell.name : cell.name))
                          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                          .layoutWeight(1)
                      }.width('100%')

                      // 详情行
                      Column({ space: 8 }) {
                        if (!cell.isExam) {
                          this.DetailRow('👨‍🏫 教师', cell.teacher)
                        }
                        if (!cell.isExam) {
                          this.DetailRow('📍 教室', cell.classroom)
                        }
                        if (!cell.isExam) {
                          this.DetailRow('🕐 节次', '第' + cell.startSection + '-' + cell.endSection + '节')
                        }
                        this.DetailRow('📅 周次', cell.weekDesc || '未设置')
          // 自定义课程编辑/删除
          if (cell.isCustom) {
            Row({ space: 12 }) {
              Button('编辑').layoutWeight(1).backgroundColor(ThemeColors.isDark ? '#1A3A5C' : '#E3F2FD').fontColor('#2979FF')
                .borderRadius(8)
                .onClick(() => { this.editCustomCourse(cell); })
              Button('删除').layoutWeight(1).backgroundColor(ThemeColors.isDark ? '#3E1A1A' : '#FFEBEE').fontColor('#C62828')
                .borderRadius(8)
                .onClick(() => { this.deleteCustomCourse(cell); })
            }
            .margin({ top: 12 })
          }
                        if (cell.isExam) {
                          this.DetailRow('📅 日期', cell.examDate)
                          this.DetailRow('⏰ 时间', cell.examTimeDesc)
                          this.DetailRow('🏫 考场', cell.classroom)
                          if (cell.examSeat) this.DetailRow('💺 座位号', cell.examSeat)
                        }
                        if (cell.isExperiment && cell.experimentProject) {
                          this.DetailRow('🔬 实验项目', cell.experimentProject)
                        }
                        if (cell.kch) {
                          this.DetailRow('📋 课程号', cell.kch)
                        }
                        if (cell.kxh) {
                          this.DetailRow('🔢 班级', cell.kxh)
                        }
                      }.margin({ top: 10 }).width('100%')
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12 })
                  }
                }, (cell: ClassCell, idx: number) => `conflict_${cell.name}_${idx}_${cell.startSection}`)
              }
              .width('100%')
              .height(Math.min(400, this.currentConflictCells.length * 200))
              .divider({ strokeWidth: 0.5, color: '#F0F0F0' })
            }
          }
          .width('85%')
          .padding({ left: 20, right: 20, bottom: 20 })
          .backgroundColor(ThemeColors.bgInput)
          .borderRadius(12)
          .shadow({ radius: 24, color: 'rgba(0,0,0,0.25)', offsetY: 10 })
          .scale({ x: this.cardScale, y: this.cardScale })
          .opacity(this.cardOpacity)
          .zIndex(2)
        }

        // 手动添加课程弹窗
        if (this.showAddCourseDialog) {
          Column() {
            Text('添加课程').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).margin({ bottom: 16 })
            Column({ space: 10 }) {
              Row() { Text('课程名称').fontSize(14).fontColor(ThemeColors.textSecondary).width(72); TextInput({ placeholder: '必填', text: this.addCourseName }).onChange((v: string) => { this.addCourseName = v; }).layoutWeight(1).fontSize(14) }.width('100%')
              Row() { Text('教师').fontSize(14).fontColor(ThemeColors.textSecondary).width(72); TextInput({ placeholder: '选填', text: this.addCourseTeacher }).onChange((v: string) => { this.addCourseTeacher = v; }).layoutWeight(1).fontSize(14) }.width('100%')
              Row() { Text('教室').fontSize(14).fontColor(ThemeColors.textSecondary).width(72); TextInput({ placeholder: '选填', text: this.addCourseClassroom }).onChange((v: string) => { this.addCourseClassroom = v; }).layoutWeight(1).fontSize(14) }.width('100%')
              Row() { Text('上课周次').fontSize(14).fontColor(ThemeColors.textSecondary).width(72).alignSelf(ItemAlign.Start) }.width('100%')
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.buildWeekOptions(), (week: number) => {
                  Stack() {
                    Circle()
                      .width(36).height(36)
                      .fill(this.addCourseWeekList[week - 1] ? '#2979FF' : '#F0F0F0')
                    Text(String(week))
                      .fontSize(14).fontColor(this.addCourseWeekList[week - 1] ? '#FFFFFF' : ThemeColors.textSecondary)
                  }
                  .margin({ right: 6, bottom: 8 })
                  .onClick(() => {
                    this.addCourseWeekList[week - 1] = !this.addCourseWeekList[week - 1];
                  })
                })
              }.width('100%').margin({ top: 6 })
              Row() { Text('星期').fontSize(14).fontColor(ThemeColors.textSecondary).width(72)
                Select([
                  { value: '请选择星期' },
                  { value: '周一' },
                  { value: '周二' },
                  { value: '周三' },
                  { value: '周四' },
                  { value: '周五' },
                  { value: '周六' },
                  { value: '周日' }
                ])
                  .selected(this.addCourseDay).onSelect((idx: number) => { this.addCourseDay = idx; }).layoutWeight(1)
              }.width('100%')
              Row() { Text('开始节次').fontSize(14).fontColor(ThemeColors.textSecondary).width(72)
                Select(this.buildSectionOptions())
                  .selected(this.addCourseStartSection).onSelect((idx: number) => { this.addCourseStartSection = idx; }).layoutWeight(1)
              }.width('100%')
              Row() { Text('结束节次').fontSize(14).fontColor(ThemeColors.textSecondary).width(72)
                Select(this.buildSectionOptions())
                  .selected(this.addCourseEndSection).onSelect((idx: number) => { this.addCourseEndSection = idx; }).layoutWeight(1)
              }.width('100%')
            }.width('100%')
            Row({ space: 12 }) {
              Button('取消').layoutWeight(1).backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textSecondary)
                .onClick(() => { this.showAddCourseDialog = false; this.resetAddCourseForm(); })
              Button('添加').layoutWeight(1).backgroundColor('#2979FF').fontColor('#FFFFFF')
                .onClick(() => { this.addCustomCourse(); })
            }.margin({ top: 16 }).width('100%')
          }.width('85%').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(12)
          .shadow({ radius: 24, color: 'rgba(0,0,0,0.25)', offsetY: 10 }).zIndex(3)
        }

        // 日历提醒选择弹窗
        if (this.addFormToast.length > 0) {
          Text(this.addFormToast)
            .fontSize(14).fontColor('#FFFFFF')
            .backgroundColor('rgba(0,0,0,0.75)')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .borderRadius(20)
            .position({ x: '50%', y: '85%' }).markAnchor({ x: '50%' })
            .zIndex(5)
        }
        if (this.addFormToast.length > 0) {
          Text(this.addFormToast)
            .fontSize(14).fontColor('#FFFFFF')
            .backgroundColor('rgba(0,0,0,0.75)')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .borderRadius(20)
            .position({ x: '50%', y: '85%' }).markAnchor({ x: '50%' })
            .zIndex(5)
        }
        if (this.showReminderDialog) {
          Column() {
            Text('导入到系统日历').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).margin({ bottom: 16 })
            Text('选择上课前提醒时间：').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ bottom: 12 })
            Column({ space: 8 }) {
              ForEach([5, 10, 15, 20], (min: number) => {
                Row() {
                  Radio({ value: String(min), group: 'reminder' }).checked(this.reminderMode === 0 && this.reminderMinutes === min)
                    .onChange((checked: boolean) => { if (checked) { this.reminderMode = 0; this.reminderMinutes = min; } })
                    .margin({ right: 8 })
                  Text(min + '分钟前').fontSize(14).fontColor(ThemeColors.textPrimary)
                }.width('100%').padding({ left: 4, right: 4 })
              }, (min: number) => String(min))
              // 自定义
              Row() {
                Radio({ value: 'custom', group: 'reminder' }).checked(this.reminderMode === 1)
                  .onChange((checked: boolean) => { if (checked) { this.reminderMode = 1; } })
                  .margin({ right: 8 })
                Text('自定义').fontSize(14).fontColor(ThemeColors.textPrimary).margin({ right: 8 })
                if (this.reminderMode === 1) {
                  TextInput({ placeholder: '分钟', text: this.customReminderInput })
                    .type(InputType.Number).width(60).fontSize(14)
                    .onChange((v: string) => { this.customReminderInput = v; })
                }
              }.width('100%').padding({ left: 4, right: 4 })
              // 不需要提醒
              Row() {
                Radio({ value: 'none', group: 'reminder' }).checked(this.reminderMode === 2)
                  .onChange((checked: boolean) => { if (checked) { this.reminderMode = 2; } })
                  .margin({ right: 8 })
                Text('不需要提醒').fontSize(14).fontColor(ThemeColors.textPrimary)
              }.width('100%').padding({ left: 4, right: 4 })
            }.width('100%')
            Row({ space: 12 }) {
              Button('取消').layoutWeight(1).backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textSecondary)
                .onClick(() => { this.showReminderDialog = false; })
              Button('导入').layoutWeight(1).backgroundColor('#2979FF').fontColor('#FFFFFF')
                .onClick(() => {
                  if (this.reminderMode === 1) {
                    const parsed = parseInt(this.customReminderInput);
                    if (isNaN(parsed) || parsed <= 0) {
                      this.customReminderInput = '30';
                      return;
                    }
                    this.reminderMinutes = parsed;
                  }
                  this.showReminderDialog = false;
                  this.importToCalendar();
                })
            }.margin({ top: 16 }).width('100%')
          }.width('75%').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(12)
          .shadow({ radius: 24, color: 'rgba(0,0,0,0.25)', offsetY: 10 }).zIndex(3)
        }
      }.width('100%').height('100%')
    }
    .hideBackButton(true)
    .title({ builder: this.customTitle(), height: 56 })
    .onReady(() => {})
  }

  @Builder DetailRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(13).fontColor(ThemeColors.textSecondary).width(72)
      Text(value || '未设置').fontSize(13).fontColor(ThemeColors.textPrimary).layoutWeight(1)
    }.width('100%')
  }

  @Builder customTitle() {
    Row() {
      Text('课程表')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)

      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.ic_public_more'))
          .height(22)
          .width(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40)
      .width(40)
      .bindMenu(this.buildClassTableMenu())
    }
    .height(56)
    .width('100%')
    .padding({ left: 12, right: 12 })
  }

  @Builder buildHeader() {
    // 周次选择器（全宽居中）
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.ic_public_arrow_left'))
          .height(20)
          .width(20)
          .fillColor(ThemeColors.textPrimary)
      }
      .height(36)
      .width(36)
      .opacity(this.currentWeek <= 1 ? 0.3 : 1.0)
      .onClick(() => { this.changeWeek(this.currentWeek - 1); })

      Text(this.getWeekRangeLabel()).fontSize(15).fontColor('#2979FF').fontWeight(FontWeight.Medium)
        .margin({ left: 12, right: 12 })

      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.ic_public_arrow_right'))
          .height(20)
          .width(20)
          .fillColor(ThemeColors.textPrimary)
      }
      .height(36)
      .width(36)
      .opacity(this.currentWeek >= this.maxWeek ? 0.3 : 1.0)
      .onClick(() => { this.changeWeek(this.currentWeek + 1); })

      if (this.calendarImportMsg.length > 0) {
        Text(this.calendarImportMsg).fontSize(10).fontColor(ThemeColors.textSecondary).maxLines(1)
      }
    }.width('100%').height(40).justifyContent(FlexAlign.Center).padding({ left: 16, right: 16 })
  }

  @Builder buildClassTableMenu() {
    Menu() {
      MenuItem({ content: '手动添加课程', startIcon: $r('app.media.ic_public_add_norm') })
        .onClick(() => { this.showAddCourseDialog = true; })
      MenuItem({ content: this.calendarImporting ? '导入中...' : '导入系统日历', startIcon: $r('app.media.ic_public_calendar') })
        .onClick(() => { this.showReminderDialog = true; })
      MenuItem({ content: '刷新课表', startIcon: $r('app.media.refresh') })
        .onClick(() => { this.loadTable(true); })
    }
  }

  // 统一颜色获取方法：考试→红色系，实验→橙色系，课程→蓝色系
  private getCellColor(cell: ClassCell): string {
    if (cell.isExam) return EXAM_COLORS[cell.colorIndex % EXAM_COLORS.length];
    if (cell.isExperiment) return EXP_COLORS[cell.colorIndex % EXP_COLORS.length];
    return CLASS_COLORS[cell.colorIndex % CLASS_COLORS.length];
  }

  // 计算某个节次在含分隔行的网格中的 Y 偏移
  private getSectionY(section: number): number {
    let y = 0;
    for (let s = 1; s < section; s++) {
      y += this.ROW_HEIGHT;
      if (s === 4) y += BREAK_HEIGHT;  // 第4节后加午休
      if (s === 8) y += BREAK_HEIGHT;  // 第8节后加放学
    }
    return y;
  }

  // 计算某个节次的像素高度（含跨过的分隔行）
  private getSectionSpanHeight(startSection: number, endSection: number): number {
    let h = (endSection - startSection + 1) * this.ROW_HEIGHT;
    // 如果跨越午休分隔（第4节到第5节之间）
    if (startSection <= 4 && endSection >= 5) h += BREAK_HEIGHT;
    // 如果跨越放学分隔（第8节到第9节之间）
    if (startSection <= 8 && endSection >= 9) h += BREAK_HEIGHT;
    return h;
  }

  // 获取总网格高度（含分隔行）
  private getTotalGridHeight(): number {
    return SECTION_COUNT * this.ROW_HEIGHT + 2 * BREAK_HEIGHT;
  }

  // 考试时间→像素Y坐标映射（按节次级别插值，含课间gap和分隔行）
  // timeStr 格式 "HH:MM" 如 "08:30"
  private timeToY(timeStr: string): number {
    const parts = timeStr.split(':');
    const totalMin = parseInt(parts[0]) * 60 + parseInt(parts[1]);
    const RH = this.ROW_HEIGHT;
    const BH = BREAK_HEIGHT;
    if (totalMin <= 555) return (totalMin - 510) / 45 * RH;                      // sec1 8:30-9:15
    if (totalMin < 560) return RH;                                                // gap→sec2
    if (totalMin <= 605) return RH + (totalMin - 560) / 45 * RH;                 // sec2 9:20-10:05
    if (totalMin < 625) return 2 * RH;                                            // gap→sec3
    if (totalMin <= 670) return 2 * RH + (totalMin - 625) / 45 * RH;             // sec3 10:25-11:10
    if (totalMin < 675) return 3 * RH;                                            // gap→sec4
    if (totalMin <= 720) return 3 * RH + (totalMin - 675) / 45 * RH;             // sec4 11:15-12:00
    if (totalMin <= 840) return 4 * RH + (totalMin - 720) / 120 * BH;            // 午休 12:00-14:00
    if (totalMin <= 885) return 4 * RH + BH + (totalMin - 840) / 45 * RH;       // sec5 14:00-14:45
    if (totalMin < 890) return 5 * RH + BH;                                      // gap→sec6
    if (totalMin <= 935) return 5 * RH + BH + (totalMin - 890) / 45 * RH;       // sec6 14:50-15:35
    if (totalMin < 955) return 6 * RH + BH;                                      // gap→sec7
    if (totalMin <= 1000) return 6 * RH + BH + (totalMin - 955) / 45 * RH;      // sec7 15:55-16:40
    if (totalMin < 1005) return 7 * RH + BH;                                     // gap→sec8
    if (totalMin <= 1050) return 7 * RH + BH + (totalMin - 1005) / 45 * RH;     // sec8 16:45-17:30
    if (totalMin <= 1140) return 8 * RH + BH + (totalMin - 1050) / 90 * BH;     // 放学 17:30-19:00
    if (totalMin <= 1185) return 8 * RH + 2 * BH + (totalMin - 1140) / 45 * RH; // sec9 19:00-19:45
    if (totalMin < 1195) return 9 * RH + 2 * BH;                                 // gap→sec10
    if (totalMin <= 1235) return 9 * RH + 2 * BH + (totalMin - 1195) / 40 * RH; // sec10 19:55-20:35
    if (totalMin < 1240) return 10 * RH + 2 * BH;                                // gap→sec11
    return 10 * RH + 2 * BH + (totalMin - 1240) / 45 * RH;                      // sec11 20:40-21:25
  }

  // 点击事件：传递day和section，获取所有冲突课程
  private showCellDetail(day: number, section: number): void {
    this.selectedDay = day;
    this.selectedSection = section;
    this.currentConflictCells = this.getCurrentWeekConflictCells(day, section);

    if (this.currentConflictCells.length === 0) {
      return;
    }

    this.showDetailDialog = true;
    this.cardScale = 0.85;
    this.cardOpacity = 0;
    this.maskOpacity = 0;
    animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
      this.cardScale = 1;
      this.cardOpacity = 1;
      this.maskOpacity = 0.7;
    });
  }

  private hideCellDetail(): void {
    animateTo({ duration: 180, curve: Curve.EaseIn, onFinish: () => {
      this.showDetailDialog = false;
      this.currentConflictCells = [];
    }}, () => {
      this.cardScale = 0.85;
      this.cardOpacity = 0;
      this.maskOpacity = 0;
    });
  }

  // 新增方法：获取当前周该时间段所有冲突的课程
  private getCurrentWeekConflictCells(day: number, section: number): ClassCell[] {
    const result: ClassCell[] = [];
    if (!this.classGrid[day]) return result;

    // 考试卡片（section=0）
    if (section === 0) {
      const examSlot = this.classGrid[day][0];
      if (examSlot) {
        for (const cell of examSlot) {
          if (cell.isExam && cell.weekList[this.currentWeek - 1]) {
            result.push(cell);
          }
        }
      }
      return result;
    }

    // 遍历所有可能的起始节次，检查是否有课程在当前周覆盖该时间段
    for (let s = 1; s <= section; s++) {
      const cellList = this.classGrid[day][s];
      if (!cellList) continue;

      for (const cell of cellList) {
        // 检查：1. 当前周有课 2. 该课程覆盖了点击的section
        if (cell.weekList[this.currentWeek - 1] &&
          cell.startSection <= section &&
          cell.endSection >= section) {
          result.push(cell);
        }
      }
    }

    // 按跨度从大到小排序（长课在前）
    result.sort((a, b) => {
      const spanA = a.endSection - a.startSection + 1;
      const spanB = b.endSection - b.startSection + 1;
      return spanB - spanA;
    });

    return result;
  }

  private changeWeek(targetWeek: number): void {
    if (targetWeek < 1 || targetWeek > this.maxWeek || targetWeek === this.currentWeek || this.isAnimating) return;
    this.isAnimating = true;
    const dir: number = targetWeek > this.currentWeek ? 1 : -1;
    animateTo({ duration: 120, curve: Curve.EaseIn }, () => {
      this.slideOffsetX = (0 - dir) * 120;
      this.slideOpacity = 0;
    });
    setTimeout(() => {
      this.currentWeek = targetWeek;
      this.slideOffsetX = dir * 120;
      animateTo({ duration: 150, curve: Curve.EaseOut, onFinish: () => {
        this.isAnimating = false;
      }}, () => {
        this.slideOffsetX = 0;
        this.slideOpacity = 1;
      });
    }, 125);
  }

  @Builder buildClassGrid() {
    Scroll() {
      Column() {
        Row() {
          Text('').width(40).height(44)
          ForEach(DAY_NAMES, (name: string, idx: number) => {
            Column() {
              Text(name).fontSize(13)
                .fontColor(idx === new Date().getDay() - 1 ? '#FFFFFF' : ThemeColors.textPrimary)
                .fontWeight(idx === new Date().getDay() - 1 ? FontWeight.Bold : FontWeight.Medium)
              Text(this.getDateStr(this.currentWeek, idx + 1)).fontSize(10)
                .fontColor(idx === new Date().getDay() - 1 ? '#FFFFFF99' : ThemeColors.textSecondary)
            }.layoutWeight(1).height(44)
            .backgroundColor(idx === new Date().getDay() - 1 ? '#2979FF' : ThemeColors.bgCard)
            .borderRadius(8)
            .justifyContent(FlexAlign.Center)
          }, (name: string, idx: number) => `day_${idx}`)
        }.width('100%').padding({ left: 4, right: 4, top: 4, bottom: 2 })
        Divider().color('#EEEEEE').margin({ left: 44 })

        Row() {
          Column() {
            ForEach([1, 2, 3, 4], (section: number) => {
              Column() {
                Text(String(section)).fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Medium)
                Text(SECTION_TIMES[section] || '').fontSize(9).fontColor(ThemeColors.textHint).margin({ top: 1 })
              }.width(40).height(this.ROW_HEIGHT).justifyContent(FlexAlign.Center)
            }, (section: number) => `sec_${section}`)
            Row() { Text('午休').fontSize(8).fontColor(ThemeColors.textHint) }
            .width(40).height(BREAK_HEIGHT).justifyContent(FlexAlign.Center).backgroundColor(ThemeColors.bgInput)
            ForEach([5, 6, 7, 8], (section: number) => {
              Column() {
                Text(String(section)).fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Medium)
                Text(SECTION_TIMES[section] || '').fontSize(9).fontColor(ThemeColors.textHint).margin({ top: 1 })
              }.width(40).height(this.ROW_HEIGHT).justifyContent(FlexAlign.Center)
            }, (section: number) => `sec_${section}`)
            Row() { Text('放学').fontSize(8).fontColor(ThemeColors.textHint) }
            .width(40).height(BREAK_HEIGHT).justifyContent(FlexAlign.Center).backgroundColor(ThemeColors.bgInput)
            ForEach([9, 10, 11], (section: number) => {
              Column() {
                Text(String(section)).fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Medium)
                Text(SECTION_TIMES[section] || '').fontSize(9).fontColor(ThemeColors.textHint).margin({ top: 1 })
              }.width(40).height(this.ROW_HEIGHT).justifyContent(FlexAlign.Center)
            }, (section: number) => `sec_${section}`)
          }.width(40)

          Stack() {
            Column() {
              ForEach([1, 2, 3, 4], (section: number) => {
                Row() {
                  ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                    Column().layoutWeight(1).height(this.ROW_HEIGHT)
                      .border({ width: { right: 0.5, bottom: 0.5 }, color: '#F0F0F0' })
                      .onClick(() => { this.showCellDetail(day, section); })
                  }, (day: number) => `grid_${day}`)
                }.width('100%')
              }, (section: number) => `sec_${section}`)
              Row() { Text('12:00-14:00').fontSize(8).fontColor('#DDDDDD') }
              .width('100%').height(BREAK_HEIGHT).justifyContent(FlexAlign.Center)
              .backgroundColor(ThemeColors.bgInput).border({ width: { top: 0.5, bottom: 0.5 }, color: '#E8E8E8' })
              ForEach([5, 6, 7, 8], (section: number) => {
                Row() {
                  ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                    Column().layoutWeight(1).height(this.ROW_HEIGHT)
                      .border({ width: { right: 0.5, bottom: 0.5 }, color: '#F0F0F0' })
                      .onClick(() => { this.showCellDetail(day, section); })
                  }, (day: number) => `grid_${day}`)
                }.width('100%')
              }, (section: number) => `sec_${section}`)
              Row() { Text('17:30-19:00').fontSize(8).fontColor('#DDDDDD') }
              .width('100%').height(BREAK_HEIGHT).justifyContent(FlexAlign.Center)
              .backgroundColor(ThemeColors.bgInput).border({ width: { top: 0.5, bottom: 0.5 }, color: '#E8E8E8' })
              ForEach([9, 10, 11], (section: number) => {
                Row() {
                  ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                    Column().layoutWeight(1).height(this.ROW_HEIGHT)
                      .border({ width: { right: 0.5, bottom: 0.5 }, color: '#F0F0F0' })
                      .onClick(() => { this.showCellDetail(day, section); })
                  }, (day: number) => `grid_${day}`)
                }.width('100%')
              }, (section: number) => `sec_${section}`)
            }.width('100%')

            ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
              ForEach(this.getCellsForDay(day), (cell: ClassCell) => {
                Column() {
                  Text(cell.name).fontSize(10)
                    .fontColor('#FFFFFF')
                    .fontWeight(FontWeight.Medium).maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(cell.classroom).fontSize(9)
                    .fontColor('#FFFFFFCC')
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 1 })
                  if (cell.teacher) {
                    Text(cell.teacher).fontSize(8)
                      .fontColor('#FFFFFFAA')
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 1 })
                  }
                  // 冲突提示标记
                  if (this.getCurrentWeekConflictCells(day, cell.startSection).length > 1) {
                    Text('⚠️').fontSize(8).fontColor('#FFFFFF').position({ top: 2, right: 2 })
                  }
                }.width('100%').height('100%').padding(4)
                .backgroundColor(this.getCellColor(cell)).borderRadius(6)
                .alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
                .position({
                  x: `${(day - 1) * (100 / 7)}%`,
                  y: cell.isExam ? cell.examPixelY : this.getSectionY(cell.startSection)
                })
                .size({
                  width: `${100 / 7}%`,
                  height: cell.isExam ? cell.examPixelH : this.getSectionSpanHeight(cell.startSection, cell.endSection)
                })
                // 点击事件改为传递day和section
                .onClick(() => {
                  this.showCellDetail(day, cell.startSection);
                })
              }, (cell: ClassCell) => `cell_${day}_${cell.startSection}_${cell.name}_${cell.kch}`)
            }, (day: number) => `day_${day}`)
          }.layoutWeight(1)
        }.width('100%')
      }.width('100%')
      .translate({ x: this.slideOffsetX })
      .opacity(this.slideOpacity)
    }.scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto).layoutWeight(1)
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 30 })
        .onActionStart((event: GestureEvent) => {
          this.swipeStartX = event.fingerList[0].globalX;
        })
        .onActionEnd((event: GestureEvent) => {
          const deltaX = event.fingerList[0].globalX - this.swipeStartX;
          if (deltaX < -30) {
            this.changeWeek(this.currentWeek + 1);
          } else if (deltaX > 30) {
            this.changeWeek(this.currentWeek - 1);
          }
        })
    )
  }

  // 网格显示逻辑：正确处理所有重叠冲突
  // 优先级：考试 > 实验 > 普通课程；同类型下跨度大的优先
  private getCellsForDay(day: number): ClassCell[] {
    const cells: ClassCell[] = [];
    if (!this.classGrid[day]) return cells;

    // 1. 先处理考试卡片（像素级定位，不会和普通课程冲突）
    const examSlot = this.classGrid[day][0];
    if (examSlot && examSlot.length > 0) {
      const examCells = examSlot.filter((c: ClassCell) => c.isExam && c.weekList[this.currentWeek - 1]);
      for (const ec of examCells) {
        cells.push(ec);
      }
    }

    // 2. 收集当天所有在当前周有课的普通课程（排除考试）
    const allCourses: ClassCell[] = [];
    for (let s = 1; s <= SECTION_COUNT; s++) {
      const cellList = this.classGrid[day][s];
      if (!cellList || cellList.length === 0) continue;

      const currentWeekCells = cellList.filter(cell =>
      cell.weekList[this.currentWeek - 1] && cell.startSection === s && !cell.isExam
      );
      allCourses.push(...currentWeekCells);
    }

    if (allCourses.length === 0) return cells;

    // 3. 按优先级排序：实验 > 普通课程；同类型下跨度大的优先
    allCourses.sort((a, b) => {
      // 优先级1：实验课程优先
      if (a.isExperiment && !b.isExperiment) return -1;
      if (!a.isExperiment && b.isExperiment) return 1;

      // 优先级2：跨度大的优先
      const spanA = a.endSection - a.startSection + 1;
      const spanB = b.endSection - b.startSection + 1;
      if (spanA !== spanB) return spanB - spanA;

      // 优先级3：课程号排序（保证稳定性，避免同名课程冲突）
      return a.kch.localeCompare(b.kch);
    });

    // 4. 使用区间调度算法选择不重叠的课程
    const selectedCourses: ClassCell[] = [];
    const occupiedSections: boolean[] = new Array(SECTION_COUNT + 1).fill(false);

    for (const course of allCourses) {
      // 检查该课程的所有节次是否都未被占用
      let canAdd = true;
      for (let s = course.startSection; s <= course.endSection; s++) {
        if (occupiedSections[s]) {
          canAdd = false;
          break;
        }
      }

      if (canAdd) {
        selectedCourses.push(course);
        // 标记这些节次为已占用
        for (let s = course.startSection; s <= course.endSection; s++) {
          occupiedSections[s] = true;
        }
      }
    }

    // 5. 将选中的课程加入最终渲染列表
    cells.push(...selectedCourses);
    return cells;
  }

  // 导入系统日历
  private async importToCalendar(): Promise<void> {
    if (this.calendarImporting) return;
    this.calendarImporting = true;
    this.calendarImportMsg = '';

    try {
      // 1. 申请权限
      const context = getContext(this) as common.UIAbilityContext;
      const atManager = abilityAccessCtrl.createAtManager();
      const permissions: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
      const grantResult = await atManager.requestPermissionsFromUser(context, permissions);
      let allGranted = true;
      const authResults: number[] = grantResult.authResults;
      for (const result of authResults) {
        if (result !== 0) {
          allGranted = false;
          break;
        }
      }
      if (!allGranted) {
        this.calendarImportMsg = '需要日历权限才能导入';
        this.calendarImporting = false;
        return;
      }

      // 2. 获取 CalendarManager
      const calendarMgr = calendarManager.getCalendarManager(context);

      // 3. 获取或创建日历
      let calendar: calendarManager.Calendar = await calendarMgr.getCalendar();
      try {
        const calendars: calendarManager.Calendar[] = await calendarMgr.getAllCalendars();
        let found = false;
        for (const cal of calendars) {
          const acc = cal.getAccount();
          if (acc.name === 'HiXD课程表') {
            calendar = cal;
            found = true;
            break;
          }
        }
        if (!found) {
          const calendarAccount: calendarManager.CalendarAccount = {
            name: 'HiXD课程表',
            type: calendarManager.CalendarType.LOCAL,
            displayName: 'HiXD课程表'
          };
          calendar = await calendarMgr.createCalendar(calendarAccount);
        }
      } catch (e) {
        // fallback to default
      }

      // 4. 启用日历提醒
      try {
        const config: calendarManager.CalendarConfig = {
          enableReminder: true,
          color: '#4A90D9'
        };
        await calendar.setConfig(config);
      } catch (cfgErr) {
        console.warn('ClassTablePage', 'setConfig failed: ' + String(cfgErr));
      }

      // 5. 遍历课程，为每个上课日创建日历事件
      const startDate: Date = SemesterUtil.getSemesterStartDate(this.semesterCode);
      const dayOfWeek = startDate.getDay();
      const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
      const monday = new Date(startDate);
      monday.setDate(startDate.getDate() + mondayOffset);

      let eventCount = 0;

      for (let d = 1; d <= DAY_COUNT; d++) {
        for (let s = 1; s <= SECTION_COUNT; s++) {
          const cells = this.classGrid[d][s];
          for (let ci = 0; ci < cells.length; ci++) {
            const cell = cells[ci];
            if (cell.isExam) continue; // 跳过考试
            if (cell.startSection !== s) continue; // 只在起始节次处理

            // 遍历该课程的所有有课周次
            for (let w = 0; w < cell.weekList.length; w++) {
              if (!cell.weekList[w]) continue;
              const weekNum = w + 1; // 1-based

              // 计算该课的具体日期
              const eventDate = new Date(monday);
              eventDate.setDate(monday.getDate() + (weekNum - 1) * 7 + (d - 1));

              // 获取开始/结束时间
              const startParts = SECTION_TIMES[cell.startSection].split('-');
              const endParts = SECTION_TIMES[cell.endSection].split('-');
              if (startParts.length < 2 || endParts.length < 2) continue;

              const startHour = parseInt(startParts[0].split(':')[0]);
              const startMin = parseInt(startParts[0].split(':')[1]);
              const endHour = parseInt(endParts[1].split(':')[0]);
              const endMin = parseInt(endParts[1].split(':')[1]);

              const startTime = new Date(eventDate.getFullYear(), eventDate.getMonth(), eventDate.getDate(),
                startHour, startMin, 0);
              const endTime = new Date(eventDate.getFullYear(), eventDate.getMonth(), eventDate.getDate(),
                endHour, endMin, 0);

              // 创建日历事件
              const title = (cell.isExperiment ? '🧪 ' : '') + cell.name;
              const desc = (cell.classroom ? '教室: ' + cell.classroom : '') +
                (cell.teacher ? (cell.classroom ? ' | ' : '') + '教师: ' + cell.teacher : '');
              let event: calendarManager.Event;
              if (this.reminderMode === 2) {
                // 不需要提醒
                event = {
                  type: calendarManager.EventType.NORMAL,
                  title: title,
                  startTime: startTime.getTime(),
                  endTime: endTime.getTime(),
                  description: desc
                };
              } else {
                event = {
                  type: calendarManager.EventType.NORMAL,
                  title: title,
                  startTime: startTime.getTime(),
                  endTime: endTime.getTime(),
                  description: desc,
                  reminderTime: [this.reminderMinutes]
                };
              }

              try {
                await calendar.addEvent(event);
                eventCount++;
              } catch (addErr) {
                console.warn('ClassTablePage', 'addEvent failed: ' + String(addErr));
              }
            }
          }
        }
      }

      this.calendarImportMsg = '已导入 ' + eventCount + ' 条课程到系统日历';
    } catch (e) {
      this.calendarImportMsg = '导入失败: ' + String(e);
    }
    this.calendarImporting = false;
  }

  // 手动添加课程到classGrid并保存
  private showAddToast(msg: string): void {
    this.addFormToast = msg;
    setTimeout(() => {
      this.addFormToast = '';
    }, 1500);
  }

  private addCustomCourse(): void {
    if (this.addCourseName.length === 0) {
      this.showAddToast('请输入课程名称');
      return;
    }
    if (this.addCourseStartSection > this.addCourseEndSection) {
      this.showAddToast('开始节次不能大于结束节次');
      return;
    }

    // 解析周次字符串
    const weekList: boolean[] = this.addCourseWeekList;
    const hasAnyWeek: boolean = weekList.some((v: boolean) => v);
    if (!hasAnyWeek) {
      this.showAddToast('请输入有效的上课周次');
      return;
    }

        if (this.addCourseDay === 0) {
          this.showAddToast('请选择星期');
          return;
        }
        if (this.addCourseStartSection === 0) {
          this.showAddToast('请选择开始节次');
          return;
        }
        if (this.addCourseEndSection === 0) {
          this.showAddToast('请选择结束节次');
          return;
        }
    const cell = new ClassCell();
    cell.name = this.addCourseName;
    cell.teacher = this.addCourseTeacher;
    cell.classroom = this.addCourseClassroom;
    cell.day = this.addCourseDay;
    cell.startSection = this.addCourseStartSection;
    cell.endSection = this.addCourseEndSection;
    cell.weekList = weekList;
    cell.weekDesc = this.formatWeekDesc(weekList);
    cell.colorIndex = Math.floor(Math.random() * CLASS_COLORS.length);
    cell.isExperiment = false;
    cell.isCustom = true;

    if (this.editingCustomIndex >= 0) {
      this.customList[this.editingCustomIndex] = this.cellToItem(cell);
    } else {
      this.customList.push(this.cellToItem(cell));
    }
    this.saveCustomList();
    // 保存后重新从文件加载→应用grid，保证和重进页面走同一条路径
    this.loadCustomCourses(this.classGrid);
    this.classGrid = this.classGrid.slice(0, this.classGrid.length);

    this.showAddCourseDialog = false;
    this.resetAddCourseForm();
  }

  // 解析周次字符串（逗号分隔格式，支持 "1-16" 和 "1,3,5"）
  private parseWeekListForAdd(weeks: string): boolean[] {
    // 1-indexed: week w → list[w] = true, 与 parseWeekList 和 getNextClasses 一致
    const list: boolean[] = [];
    for (let i = 0; i < 26; i++) list.push(false);
    if (!weeks || weeks.length === 0) return list;
    const parts: string[] = weeks.split(',');
    for (let pi = 0; pi < parts.length; pi++) {
      const trimmed: string = parts[pi].trim();
      const dashIdx: number = trimmed.indexOf('-');
      if (dashIdx > 0) {
        const start: number = parseInt(trimmed.substring(0, dashIdx)) || 0;
        const end: number = parseInt(trimmed.substring(dashIdx + 1)) || 0;
        for (let w = start; w <= end && w <= 25; w++) {
          if (w > 0) list[w] = true;
        }
      } else {
        const w: number = parseInt(trimmed) || 0;
        if (w > 0 && w <= 25) list[w] = true;
      }
    }
    return list;
  }

  // 保存自定义课程到本地文件

  // 重置添加课程表单
  private resetAddCourseForm(): void {
    this.addCourseName = '';
    this.addCourseTeacher = '';
    this.addCourseClassroom = '';
    this.addCourseWeekList = [];
    this.editingCustomIndex = -1;
    this.addCourseDay = 0;
    this.addCourseStartSection = 0;
    this.addCourseEndSection = 0;
  }

  // 构建节次下拉选项
  private buildSectionOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    opts.push({ value: '请选择' });
    for (let i = 1; i <= 11; i++) {
      opts.push({ value: '第' + i + '节' });
    }
    return opts;
  }

  private buildWeekOptions(): number[] {
    const weeks: number[] = [];
    for (let i = 1; i <= this.maxWeek; i++) {
      weeks.push(i);
    }
    return weeks;
  }

  private cellToItem(cell: ClassCell): CustomCourseItem {
    const item = new CustomCourseItem();
    item.name = cell.name;
    item.teacher = cell.teacher;
    item.classroom = cell.classroom;
    item.day = cell.day;
    item.startSection = cell.startSection;
    item.endSection = cell.endSection;
    // Normalize to 26 elements (1-indexed: index 0 unused, indices 1-25 = weeks 1-25)
    const wl: number[] = [];
    for (let i = 0; i < 26; i++) wl.push(0);
    for (let w = 0; w < cell.weekList.length && w < 25; w++) {
      // addCourseWeekList: 0-indexed (week N at [N-1]); file: 1-indexed (week N at [N])
      wl[w + 1] = cell.weekList[w] ? 1 : 0;
    }
    item.weekList = wl;
    item.colorIndex = cell.colorIndex;
    return item;
  }

  private saveCustomList(): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const customPath: string = context.filesDir + '/class_table_' + this.semesterCode + '_custom.json';
      const encoder = util.TextEncoder.create('utf-8');
      const jsonStr: string = JSON.stringify(this.customList);
      const encoded = encoder.encodeInto(jsonStr);
      const writeFile = fileIo.openSync(customPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(writeFile.fd, encoded.buffer);
      fileIo.closeSync(writeFile);
    } catch (e) {
      console.error('ClassTablePage', 'saveCustomList error' + String(e));
    }
  }

  private deleteCustomCourse(cell: ClassCell): void {
    this.classGrid[cell.day][cell.startSection] = this.classGrid[cell.day][cell.startSection].filter(
      (c: ClassCell) => c !== cell
    );
    this.classGrid = this.classGrid.slice(0, this.classGrid.length);
    const idx: number = this.customList.findIndex((item: CustomCourseItem) =>
      item.name === cell.name && item.day === cell.day &&
      item.startSection === cell.startSection && item.endSection === cell.endSection
    );
    if (idx >= 0) {
      this.customList.splice(idx, 1);
    }
    this.saveCustomList();
    this.showDetailDialog = false;
  }

  private editCustomCourse(cell: ClassCell): void {
    this.addCourseName = cell.name;
    this.addCourseTeacher = cell.teacher;
    this.addCourseClassroom = cell.classroom;
    this.addCourseDay = cell.day;
    this.addCourseStartSection = cell.startSection;
    this.addCourseEndSection = cell.endSection;
    this.addCourseWeekList = cell.weekList.map((v: boolean) => v);
    this.editingCustomIndex = this.customList.findIndex((item: CustomCourseItem) =>
      item.name === cell.name && item.day === cell.day &&
      item.startSection === cell.startSection && item.endSection === cell.endSection
    );
    this.showAddCourseDialog = true;
  }
}
