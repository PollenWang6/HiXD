// ClassTablePage.ets — 支持点击查看所有冲突课程版（已修复重叠课程覆盖问题）
import { ThemeColors } from '../../utils/ThemeColors';
import { EhallService, SemesterUtil, ClassItemModel, ExamItemModel } from '../../services/EhallService';
import { ClassService } from '../../services/ClassService';
import { ExamService } from '../../services/ExamService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { HttpUtil } from '../../utils/HttpUtil';

import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';
import { calendarManager } from '@kit.CalendarKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

// 课程卡片背景色（较鲜艳的色块，配白色文字）
const CLASS_COLORS: string[] = ['#42A5F5', '#AB47BC', '#FF7043', '#66BB6A', '#EC407A', '#26C6DA', '#FFCA28', '#8BC34A', '#7E57C2', '#29B6F6'];
const CLASS_COLORS_DK: string[] = ['#1A3A5C', '#3A1A4C', '#4A2018', '#1A3A1E', '#3A1A2E', '#1A3A4C', '#4A3A18', '#2A3A1A', '#2A1A3A', '#1A3A4C'];
// 实验卡片背景色（橙色系，区分课程）
const EXP_COLORS: string[] = ['#FF8C00', '#E65100', '#F57C00', '#EF6C00', '#FF9800'];
const EXP_COLORS_DK: string[] = ['#4A2818', '#3A1818', '#3A2018', '#3A1A18', '#4A2A18'];
// 考试卡片背景色（红色系，区分课程和实验）
const EXAM_COLORS: string[] = ['#E53935', '#C62828', '#D32F2F', '#F44336', '#EF5350'];
const EXAM_COLORS_DK: string[] = ['#4A1A1A', '#3A1818', '#3A1A1A', '#4A1A1A', '#4A1A18'];
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
  isPhysics: boolean = false;      // 物理实验
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
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State loadProgress: string = '';  // 加载进度文字
  @State syncProgress: string = '';  // 后台同步状态（缓存已显示，服务器同步中）
  @State _todayDay: number = 0;  // 今天星期几
  @State _cellStatusesMap: Map<string, number> = new Map();  // 每节课时间状态 (start_end → -1/0/1)
  @State errorMsg: string = '';
  @State addFormToast: string = '';
  @State currentWeek: number = 1;
  @State maxWeek: number = 25;  // 初始安全上限，实际由数据 SKZC 长度动态扩展
  @State semesterCode: string = '';
  @State classGrid: ClassCell[][][] = []; // 三维数组：[day][startSection] = [课程1, 课程2, ...]
  @State hasCache: boolean = false;
  @State dataHint: string = ''; // 数据同步提示（考试/实验加载状态）
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
  private classSvc = ClassService.getInstance();
  private localFilePath: string = '';
  private readonly EXP_CACHE_KEY: string = 'sysj_exp_cache';
  private lastRenderedRaw: string = '';
  private ROW_HEIGHT: number = 56;
  private swipeStartX: number = 0;
  @State slideOffsetX: number = 0;
  @State slideOpacity: number = 1;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  @StorageLink('preload_status') preloadStatus: string = '';
  @StorageLink('login_state') @Watch('onLoginDetected') loginState: string = '';
  @StorageLink('preload_progress') preloadProgress: string = '';
  private _preloadWasRunning: boolean = false;
  private _loginHandled: boolean = false;
  private _preloadDone: boolean = false;
  private isAnimating: boolean = false;

  onLoginDetected(): void {
    if (this.loginState.length > 0 && !this._loginHandled) {
      this._loginHandled = true;
      if (!this.hasCache) {
        // 无缓存：全屏加载
        this.loadProgress = '登录成功，加载中...';
        this._preloadWasRunning = true;
        this.fetchAndSave();
      } else {
        // 已有缓存：后台同步，显示状态条
        this._preloadWasRunning = true;
        this.syncProgress = '正在同步最新数据...';
        this.fetchAndSave();
      }
    }
  }

  aboutToAppear(): void {
    this.semesterCode = SemesterUtil.getCurrentSemesterCode();
    this.currentWeek = SemesterUtil.calcCurrentWeekFromNow();
    this._preloadWasRunning = (this.preloadStatus === 'loading');
    // 研究生优先用 yjspt API 返回的实际周数
    if (PreferenceUtil.getBool('role')) {
      const yw: number = PreferenceUtil.getNumber('yjspt_current_week', 0);
      if (yw > 0) { this.currentWeek = yw; }
    }
    this.initGrid();
    this.waitAndLoad();
  }

  private async waitAndLoad(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    this.localFilePath = context.filesDir + '/class_table_' + this.semesterCode + '.json';

    // 统一走 fetchAndSave：缓存优先 + 后台刷新 + 考试/实验合并
    this.loading = true;
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
    } catch (e) {
      console.error('ClassTablePage', 'readLocalClassTable FAIL: ' + String(e) + ' path=' + this.localFilePath);
    }
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
    this.loading = true;  // 确保加载动画显示（onLoginDetected 直接调用时 loading 可能为 false）
    const sid: string = PreferenceUtil.getString('ids_account');
    // Step 1: 缓存优先 — 有缓存先显示
    try {
      let cached: string | null = this.readLocalClassTable();
      if (!cached || cached.length < 100) {
        cached = await this.classSvc.getCachedClassTableStale(this.semesterCode, sid);
      }
      if (cached && cached.length >= 100) {
        this.renderClassTable(cached);
        this.lastRenderedRaw = cached;
        this.hasCache = true;
        this.loading = false;  // 有缓存立即显示课表
        this.mergeExperimentDataIntoGrid();
        if (this._preloadWasRunning) {
          this.syncProgress = '正在同步最新数据...';
        }
      } else if (cached && cached.length > 0) {
        // 缓存文件存在但数据太短（可能损坏），尝试用它，至少不白屏
        console.warn('ClassTablePage', 'fetchAndSave step1: cached data too short (' + cached.length + '), using anyway');
        try {
          this.renderClassTable(cached);
          this.lastRenderedRaw = cached;
          this.hasCache = true;
          this.loading = false;
        } catch (e2) {
          console.error('ClassTablePage', 'fetchAndSave step1: render short cache FAIL: ' + String(e2));
        }
      } else {
        console.warn('ClassTablePage', 'fetchAndSave step1: no valid cache found (cachedLen=' + (cached ? cached.length : 'null') + ')');
      }
    } catch (_e) { /* ignore */ }

    // Step 2: 后台拉最新数据（需登录）
    const isLoggedIn = PreferenceUtil.getBool('is_logged_in');
    if (!isLoggedIn) {
      this.loadProgress = '⚠️ 未登录，显示缓存数据';
      setTimeout(() => { this.loadProgress = ''; }, 3000);
      this.loading = false;
      return;
    }

    try {
      let raw: string | null = null;
      raw = await this.classSvc.getCachedClassTable(this.semesterCode, sid);
      if (!raw || raw.length < 100) {
        // 首次登录/预加载时显示同步提示，后续进入不显示
        if (this._preloadWasRunning || !this.hasCache) {
          this.syncProgress = '正在获取课表数据...';
        }
        raw = await this.classSvc.getClassTable(this.semesterCode, sid, true);
      }
      // 只有数据变化或首次加载才重新渲染
      // 防止缓存数据解析出空课表覆盖已有网格
      if (raw && (raw !== this.lastRenderedRaw || !this.hasCache)) {
        const gridBefore: ClassCell[][][] = this.classGrid;
        this.renderClassTable(raw);
        // 如果新数据解析出 0 节课且原先已有课表，还原旧网格
        if (this.isClassGridEmpty() && gridBefore.length > 0) {
          const hadData: boolean = gridBefore.some((day: ClassCell[][]) =>
            day.some((sec: ClassCell[]) => sec.length > 0));
          if (hadData) {
            console.warn('ClassTablePage', 'step2: new data produced empty grid, keeping old cache');
            this.classGrid = gridBefore;
          } else {
            this.lastRenderedRaw = raw;
            this.hasCache = true;
          }
        } else {
          this.lastRenderedRaw = raw;
          this.hasCache = true;
        }
      }
      if (raw) { this.writeLocalClassTable(raw); }
      console.info('ClassTablePage', 'fetchAndSave: step3 exp+exam');

      // Step 3: 同步实验和考试（仅在首登/无缓存时后台同步）
      if (this._preloadWasRunning || !this.hasCache) {
        this.syncProgress = '正在同步实验数据...';
        let expCount = 0;
        try {
          expCount = await this.ehall.preloadOtherExperimentsDirect();
          if (expCount > 0) { this.mergeExperimentDataIntoGrid(); }
        } catch (_e) { /* ignore */ }
        try { await this.mergePhysicsExperiments(); } catch (_e) { /* ignore */ }
        console.info('ClassTablePage', 'syncComplete: exp=' + expCount);

        this.syncProgress = '正在同步考试数据...';
        this.loadExamDataInPlace().then((examCount: number) => {
          console.info('ClassTablePage', 'syncComplete: exam=' + examCount);
          this.syncProgress = '';
          this.loading = false;
        }).catch((e: Error) => {
          console.error('ClassTablePage', 'loadExamDataInPlace error: ' + String(e));
          this.syncProgress = '';
          this.loading = false;
        });
      } else {
        this.loading = false;
        this.syncProgress = '';
      }

      // 首次登录：预加载实验/考试数据可能还未就绪，轮询等待后合并
      if (this._preloadWasRunning && !this._preloadDone) {
        this.schedulePreloadRetry(0);
      }
    } catch (e) {
      console.error('ClassTablePage', 'fetchAndSave step2 FAIL: ' + String(e) + ' hasCache=' + this.hasCache);
      if (this.hasCache && this.lastRenderedRaw && this.lastRenderedRaw.length > 0) {
        // 有缓存，网络失败可以接受
        this.loadProgress = '⚠️ 刷新失败，显示缓存数据';
        setTimeout(() => { this.loadProgress = ''; }, 3000);
      } else {
        this.errorMsg = '加载课程表失败，请检查网络';
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  // 轮询等待预加载完成（最多重试 6 次，每次间隔 3 秒 = 最长 18 秒）
  private schedulePreloadRetry(retryCount: number): void {
    if (retryCount >= 6) {
      console.warn('ClassTablePage', 'schedulePreloadRetry: exhausted retries');
      return;
    }
    setTimeout(() => {
      if (this.preloadStatus === 'done') {
        console.info('ClassTablePage', 'schedulePreloadRetry: preload done, re-merging');
        if (!PreferenceUtil.getBool('role')) { this.mergeExperimentDataIntoGrid(); }
        try { this.mergePhysicsExperiments(); } catch (_e) {}
        this.loadExamDataInPlace();
        this._preloadDone = true;
      } else if (PreferenceUtil.getBool('is_logged_in')) {
        console.info('ClassTablePage', 'schedulePreloadRetry: still loading, retry=' + retryCount);
        this.schedulePreloadRetry(retryCount + 1);
      }
    }, 3000);
  }

  async loadTable(forceRefresh: boolean = false): Promise<void> {
    if (forceRefresh) {
      this.refreshing = true;
      this.errorMsg = '';
      this.syncProgress = '正在获取课表数据...';
      const sid: string = PreferenceUtil.getString('ids_account');
      try {
        const raw: string = await this.classSvc.getClassTable(this.semesterCode, sid, true);
        if (raw !== this.lastRenderedRaw) {
          this.renderClassTable(raw);
          this.lastRenderedRaw = raw;
        }
        this.writeLocalClassTable(raw);
        // 刷新后重新合并实验和考试
        this.syncProgress = '正在同步实验数据...';
        this.mergeExperimentDataIntoGrid();
        try { await this.mergePhysicsExperiments(); } catch (_e) {}
        this.syncProgress = '正在同步考试数据...';
        await this.loadExamDataInPlace();
      } catch (e) {
        this.errorMsg = '刷新失败，请检查网络';
      } finally {
        this.syncProgress = '';
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
    const items: ClassItemModel[] = ClassService.parseClassTable(raw);
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
    // 合并自定义课程
    this.loadCustomCourses(grid);
    this.classGrid = grid;
    this.diagTodayGrid(grid);
    this.computeCellStatuses();
  }

  // 预计算今天每节课的时间状态，供 @Builder 使用（@Builder 内不能调用含 new Date() 的方法）
  private computeCellStatuses(): void {
    this._todayDay = new Date().getDay() === 0 ? 7 : new Date().getDay();
    this._cellStatusesMap = new Map<string, number>();
    const nowMin = new Date().getHours() * 60 + new Date().getMinutes();
    for (let s = 1; s <= SECTION_COUNT; s++) {
      for (let e = s; e <= SECTION_COUNT; e++) {
        const start = this.getSectionStartMinute(s);
        const end = this.getSectionEndMinute(e);
        const key = `${s}_${e}`;
        if (nowMin >= start && nowMin < end) this._cellStatusesMap.set(key, 1);
        else if (nowMin >= end) this._cellStatusesMap.set(key, -1);
        else this._cellStatusesMap.set(key, 0);
      }
    }
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

  // 在当前 classGrid 上合并实验数据
  private mergeExperimentDataIntoGrid(): boolean {
    const cached = PreferenceUtil.getString(this.EXP_CACHE_KEY);
    console.info('ClassTablePage', 'mergeExperimentDataIntoGrid: cacheLen=' + cached.length);
    if (cached.length === 0) return false;
    try {
      const cacheObj: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
      const raw: Object[] = cacheObj['data'] as Object[];
      if (!(raw instanceof Array) || raw.length === 0) return false;
      // 深拷贝当前 grid，先清除实验数据
      const grid: ClassCell[][][] = JSON.parse(JSON.stringify(this.classGrid)) as ClassCell[][][];
      for (let d = 0; d <= DAY_COUNT; d++) {
        for (let s = 0; s <= SECTION_COUNT; s++) {
          grid[d][s] = grid[d][s].filter((c: ClassCell) => !c.isExperiment);
        }
      }
      if (this.mergeExperimentData(grid)) {
        this.classGrid = grid;
        return true;
      }
    } catch (_e) { /* ignore */ }
    return false;
  }

  // 异步加载考试，返回加载数量
  private async loadExamDataInPlace(): Promise<number> {
    const cached: string = PreferenceUtil.getString('exam_schedule_cache');
    console.info('ClassTablePage', 'loadExamDataInPlace: cacheLen=' + cached.length);
    if (cached.length === 0) return 0;
    try {
      const items: ExamItemModel[] = ExamService.parseExamSchedule(cached);
      console.info('ClassTablePage', 'loadExamDataInPlace: parsed=' + items.length);
      if (items.length > 0) {
        this.applyExamItems(items);
        this.classGrid = [...this.classGrid];
        return items.length;
      }
    } catch (e) {
      console.error('ClassTablePage', 'loadExamDataInPlace error: ' + JSON.stringify(e));
    }
    return 0;
  }

  private mergeExperimentData(grid: ClassCell[][][]): boolean {
    const cached = PreferenceUtil.getString(this.EXP_CACHE_KEY);
    if (cached.length === 0) return false;
    try {
      const cacheObj: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
      const raw: Object[] = cacheObj['data'] as Object[];
      if (!(raw instanceof Array) || raw.length === 0) return false;
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
      return false;
    }
    return true;
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
        // 第一层：主页面内容（官方下拉刷新）
        Refresh({ refreshing: $$this.refreshing }) {
          Column() {
          this.buildHeader()
          if (this.showCacheBanner) {
            Row() {
              Text('当前显示的是缓存数据').fontSize(12).fontColor(ThemeColors.warning)
            }.width('100%').height(28).justifyContent(FlexAlign.Center)
            .backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
          }
          Divider().color('#F0F0F0')
          // 后台同步状态条（缓存已显示，正在后台拉取最新数据）
          if (this.syncProgress.length > 0) {
            Row() {
              LoadingProgress().width(14).height(14).color((AppStorage.get('accent_color') as string ?? '#2979FF')).margin({ right: 8 })
              Text(this.syncProgress).fontSize(13).fontColor((AppStorage.get('accent_color') as string ?? '#2979FF'))
            }.width('100%').height(32).justifyContent(FlexAlign.Center)
            .backgroundColor(ThemeColors.isDark ? '#1A2A3A' : '#E3F2FD')
          }
          if (this.loading && !this.hasCache) {
            Column() {
              LoadingProgress().width(40).height(40).color((AppStorage.get('accent_color') as string ?? '#2979FF'))
              Text(this.loadProgress.length > 0 ? this.loadProgress : '正在从学校服务器获取课程表...')
                .fontSize(15).fontColor(ThemeColors.textPrimary).margin({ top: 16 })
              Text('首次加载约需 3~5 秒，请耐心等待').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 8 })
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
        }.onRefreshing(() => { this.loadTable(true); })

        // 第二层：半透明背景遮罩
        if (this.showDetailDialog) {
          Column()
            .width('100%').height('100%')
            .backgroundColor('rgba(0,0,0,0.7)')
            .opacity(this.maskOpacity)
            .onClick(() => { this.hideCellDetail(); })
            .zIndex(1)
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
                        if (cell.isPhysics) {
                          this.DetailRow('🕐 时段', cell.startSection === 7 ? '下午 (15:55-18:10)' : '晚上 (18:30-20:45)')
                        } else if (!cell.isExam) {
                          this.DetailRow('🕐 节次', '第' + cell.startSection + '-' + cell.endSection + '节')
                        }
                        this.DetailRow('📅 周次', cell.weekDesc || '未设置')
          // 自定义课程编辑/删除
          if (cell.isCustom) {
            Row({ space: 12 }) {
              Button('编辑').layoutWeight(1).backgroundColor(ThemeColors.isDark ? '#1A3A5C' : '#E3F2FD').fontColor((AppStorage.get('accent_color') as string ?? '#2979FF'))
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

        // 手动添加课程弹窗（overlay + 暗色背景 + 滚动区域）
        if (this.showAddCourseDialog) {
          Stack() {
            Column()
              .width('100%').height('100%')
              .backgroundColor('rgba(0,0,0,0.5)')
              .onClick(() => { this.showAddCourseDialog = false; this.resetAddCourseForm(); })
            Column() {
              // 标题栏
              Row() {
                Text('添加课程').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                Blank()
                Row() { Text('✕').fontSize(20).fontColor('#999999') }
                  .width(32).height(32).borderRadius(16).backgroundColor(ThemeColors.bgInput)
                  .justifyContent(FlexAlign.Center)
                  .onClick(() => { this.showAddCourseDialog = false; this.resetAddCourseForm(); })
              }.width('100%').margin({ bottom: 16 })
              // 滚动内容
              Scroll() {
                Column({ space: 10 }) {
                  Row() { Text('课程名称').fontSize(14).fontColor(ThemeColors.textSecondary).width(72); TextInput({ placeholder: '必填', text: this.addCourseName }).onChange((v: string) => { this.addCourseName = v; }).layoutWeight(1).fontSize(14) }.width('100%')
                  Row() { Text('教师').fontSize(14).fontColor(ThemeColors.textSecondary).width(72); TextInput({ placeholder: '选填', text: this.addCourseTeacher }).onChange((v: string) => { this.addCourseTeacher = v; }).layoutWeight(1).fontSize(14) }.width('100%')
                  Row() { Text('教室').fontSize(14).fontColor(ThemeColors.textSecondary).width(72); TextInput({ placeholder: '选填', text: this.addCourseClassroom }).onChange((v: string) => { this.addCourseClassroom = v; }).layoutWeight(1).fontSize(14) }.width('100%')
                  Row() { Text('上课周次').fontSize(14).fontColor(ThemeColors.textSecondary).width(72).alignSelf(ItemAlign.Start) }.width('100%')
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach(this.buildWeekOptions(), (week: number) => {
                      Stack() {
                        // 当前周：蓝色圆环 (外圈)
                        if (week === this.currentWeek) {
                          Circle()
                            .width(30).height(30)
                            .fill('#00000000')
                            .stroke((AppStorage.get('accent_color') as string ?? '#2979FF'))
                            .strokeWidth(2)
                        }
                        // 内圈
                        Circle()
                          .width(26).height(26)
                          .fill(this.addCourseWeekList[week - 1] ? (AppStorage.get('accent_color') as string ?? '#2979FF') : ThemeColors.bgInput)
                        Text(String(week))
                          .fontSize(13).fontColor(this.addCourseWeekList[week - 1] ? '#FFFFFF' : ThemeColors.textSecondary)
                      }
                      .margin({ right: 4, bottom: 6 })
                      .onClick(() => {
                        this.addCourseWeekList[week - 1] = !this.addCourseWeekList[week - 1];
                      })
                    })
                  }.width('100%').margin({ top: 4 })
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
              }.width('100%').height(360).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
              Row({ space: 12 }) {
                Button('取消').layoutWeight(1).backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textSecondary)
                  .onClick(() => { this.showAddCourseDialog = false; this.resetAddCourseForm(); })
                Button('添加').layoutWeight(1).backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).fontColor('#FFFFFF')
                  .onClick(() => { this.addCustomCourse(); })
              }.margin({ top: 16 }).width('100%')
            }.width('82%').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(12)
            .shadow({ radius: 24, color: 'rgba(0,0,0,0.25)', offsetY: 10 })
          }.width('100%').height('100%').zIndex(3)
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
              Button('导入').layoutWeight(1).backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).fontColor('#FFFFFF')
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
    .title({ builder: this.customTitle(), height: 56 }, { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
    .onReady(() => {})
    .onBackPressed(() => {
      if (this.showAddCourseDialog) {
        this.showAddCourseDialog = false;
        this.resetAddCourseForm();
        return true;
      }
      if (this.showDetailDialog) {
        this.showDetailDialog = false;
        this.currentConflictCells = [];
        this.cardScale = 0.85;
        return true;
      }
      if (this.showReminderDialog) {
        this.showReminderDialog = false;
        return true;
      }
      return false;
    })
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

      Text(this.getWeekRangeLabel()).fontSize(15).fontColor(ThemeColors.isDark ? '#64B5F6' : (AppStorage.get('accent_color') as string ?? '#2979FF')).fontWeight(FontWeight.Medium)
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
    if (cell.isExam) {
      const arr: string[] = ThemeColors.isDark ? EXAM_COLORS_DK : EXAM_COLORS;
      return arr[cell.colorIndex % arr.length];
    }
    if (cell.isExperiment) {
      const arr: string[] = ThemeColors.isDark ? EXP_COLORS_DK : EXP_COLORS;
      return arr[cell.colorIndex % arr.length];
    }
    const arr: string[] = ThemeColors.isDark ? CLASS_COLORS_DK : CLASS_COLORS;
    return arr[cell.colorIndex % arr.length];
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

  // 节次开始分钟 (如第1节 8:30 → 510)
  private getSectionStartMinute(section: number): number {
    const times: number[][] = [[], [8,30], [9,20], [10,25], [11,15], [14,0], [14,50], [15,55], [16,45], [19,0], [19,55], [20,40]];
    if (section < 1 || section >= times.length) return 0;
    return times[section][0] * 60 + times[section][1];
  }

  // 节次结束分钟
  private getSectionEndMinute(section: number): number {
    const times: number[][] = [[], [9,15], [10,5], [11,10], [12,0], [14,45], [15,35], [16,40], [17,30], [19,45], [20,35], [21,25]];
    if (section < 1 || section >= times.length) return 0;
    return times[section][0] * 60 + times[section][1];
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
            .backgroundColor(idx === new Date().getDay() - 1 ? (ThemeColors.isDark ? '#1A3A6C' : (AppStorage.get('accent_color') as string ?? '#2979FF')) : ThemeColors.bgCard)
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
                  // 今天上课状态标记
                  if (cell.day === this._todayDay && !cell.isExam) {
                    if ((this._cellStatusesMap.get(`${cell.startSection}_${cell.endSection}`) ?? 0) === 1) {
                      Text('进行中').fontSize(7).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                        .backgroundColor('#4CAF50CC').borderRadius(3)
                        .padding({ left: 4, right: 4, top: 1, bottom: 1 }).margin({ top: 2 })
                    } else if ((this._cellStatusesMap.get(`${cell.startSection}_${cell.endSection}`) ?? 0) === -1) {
                      Text('已结束').fontSize(7).fontColor('#FFFFFF88')
                        .margin({ top: 2 })
                    }
                  }
                  // 冲突提示标记
                  if (this.getCurrentWeekConflictCells(day, cell.startSection).length > 1) {
                    Text('⚠️').fontSize(8).fontColor('#FFFFFF').position({ top: 2, right: 2 })
                  }
                }.width('100%').height('100%').padding(4)
                .backgroundColor(this.getCellColor(cell)).borderRadius(6)
                .opacity(cell.day === this._todayDay && !cell.isExam && this._cellStatusesMap.get(`${cell.startSection}_${cell.endSection}`) === -1 ? 0.55 : 1)
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

  // 后台获取物理实验（wlsy.xidian.edu.cn），有密码才尝试，没数据也不报错
  private async mergePhysicsExperiments(): Promise<void> {
    const PHYSICS_CACHE = 'physics_exp_cache';
    const CACHE_TTL = 30 * 60 * 1000; // 30 分钟
    const pwd = PreferenceUtil.getString('physics_pwd');
    if (pwd.length === 0) return; // 无密码，跳过
    try {
      let items: Record<string, string>[] = [];
      let cached = PreferenceUtil.getString(PHYSICS_CACHE);
      if (cached.length > 0) {
        try {
          let co = JSON.parse(cached) as Record<string, Object>;
          if (Date.now() - (co['ts'] as number) < CACHE_TTL) {
            items = co['data'] as Record<string, string>[];
          }
        } catch (_e) { PreferenceUtil.putString(PHYSICS_CACHE, ''); }
      }
      if (items.length === 0) {
        let http = HttpUtil.getInstance();
        let account = PreferenceUtil.getString('ids_account');
        let bd = '__EVENTTARGET=&__EVENTARGUMENT=&__VIEWSTATE=%2FwEPDwUKMTEzNzM0MjM0OWQYAQUeX19Db250cm9sc1JlcXVpcmVQb3N0QmFja0tleV9fFgEFD2xvZ2luMSRidG5Mb2dpbkOuzGVaztce4Ict7jsIJ0F5pUDb%2BsmSbCCrNVSBlPML&__VIEWSTATEGENERATOR=EE008CD9&__EVENTVALIDATION=%2FwEdAAcKecdPGDB%2BfW8Tyghx7AeSpOzeiNZ7aaEg5p6LqSa9cODI2bZwNtRxUKPkisVLf8l8Vv4WhRVIIhZlyYNJO%2BySrDKOhP%2B%2FYMNbVIh74hA2rCYnBBSTsX9SjxiYNNk%2B5kglM%2B6pGIq22Oi5mNu6u6eC2WEBfKAmATKwSpsOL%2FPNcRyi9l8Dnp6JamksyAzjhW4%3D&login1%24StuLoginID='+encodeURIComponent(account)+'&login1%24StuPassword='+encodeURIComponent(pwd)+'&login1%24UserRole=Student&login1%24btnLogin.x=28&login1%24btnLogin.y=14';
        await http.postRaw('http://wlsy.xidian.edu.cn/PhyEws/default.aspx', bd, 'application/x-www-form-urlencoded');
        let r = await http.get('http://wlsy.xidian.edu.cn/PhyEws/student/select.aspx');
        if (r.isOk) {
          items = this.parsePhysicsToItems(r.body);
          let pc: ESObject = {'ts':Date.now(),'data':items} as ESObject;
          PreferenceUtil.putString(PHYSICS_CACHE, JSON.stringify(pc));
        }
      }
      if (items.length > 0) {
        // 深拷贝当前 grid，合并物理实验
        let grid: ClassCell[][][] = JSON.parse(JSON.stringify(this.classGrid)) as ClassCell[][][];
        let merged = 0;
        for (let it of items) {
          let d = parseInt(it['weekday'] as string);
          let s = parseInt(it['startSection'] as string);
          let e = parseInt(it['endSection'] as string);
          if (isNaN(d) || isNaN(s) || isNaN(e) || d < 1 || d > 7) continue;
          let cell = new ClassCell();
          cell.name = (it['experimentName'] || '物理实验').replace('⚛ ', ''); // 弹窗已自动加🧪前缀
          cell.classroom = it['lab'] || '';
          cell.day = d;
          cell.startSection = s;
          cell.endSection = e;
          cell.teacher = it['teacher'] || '';
          cell.isExperiment = true;
          cell.isPhysics = true;
          cell.experimentProject = it['experimentProject'] || '';
          cell.weekDesc = '第' + (it['week'] || '?') + '周';
          cell.colorIndex = 0;
          grid[d][s].push(cell);
          merged++;
        }
        if (merged > 0) {
          this.classGrid = grid;
          console.info('ClassTablePage', 'mergePhysicsExperiments: merged ' + merged);
        }
      }
    } catch (_e) { /* 无物理实验或网络错误，静默 */ }
  }

  // 从物理实验 HTML 解析为简单记录（与 ExperimentPage.parsePhysicsHtml 逻辑一致）
  private parsePhysicsToItems(html: string): Record<string, string>[] {
    let items: Record<string, string>[] = [];
    let trs = html.match(/<tr[^>]*>[\s\S]*?<\/tr>/gi);
    if (!trs) return items;
    for (let tr of trs) {
      let tds: string[] = []; let tm: RegExpExecArray|null; let tr2 = new RegExp(/<td[^>]*>([\s\S]*?)<\/td>/gi);
      while((tm=tr2.exec(tr))!==null) tds.push(tm[1].replace(/<[^>]+>/g,'').replace(/&nbsp;/g,' ').trim());
      if (tds.length < 10 || tds[1].length === 0) continue;
      let dp = (tds[4]||'').split('/'); let isPM = (tds[3]||'').includes('15');
      let it: Record<string, string> = {
        'experimentName': '⚛ ' + tds[1], 'lab': tds[5] || '',
        'teacher': tds[9] || '', 'experimentProject': tds[8] || '',
        'weekday': '0', 'startSection': isPM ? '7' : '9', 'endSection': isPM ? '9' : '11',
        'week': '0', '__week': '0'
      };
      if(dp.length >= 3) {
        let dt = new Date(parseInt(dp[2]), parseInt(dp[0])-1, parseInt(dp[1]));
        it['weekday'] = String(dt.getDay()===0 ? 7 : dt.getDay());
        it['startSection'] = isPM ? '7' : '9'; it['endSection'] = isPM ? '9' : '11';
      }
      items.push(it);
    }
    return items;
  }
}
