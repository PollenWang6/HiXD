import { AccentColors } from '../../utils/AccentColors';
import { menuOptions } from '../../utils/MaterialKit';
// ClassTablePage.ets — 支持点击查看所有冲突课程版（已修复重叠课程覆盖问题）
import { ThemeColors } from '../../utils/ThemeColors';
import { EhallService, SemesterUtil, ClassItemModel, ExamItemModel } from '../../services/ids/EhallService';
import { ExperimentService } from '../../services/experiment/ExperimentService';
import { ClassService } from '../../services/ids/ClassService';
import { ChaoxingClassService } from '../../services/ids/ChaoxingClassService';
import { UnscheduledCourse, ClassChange } from '../../models/common/Models';
import { ExamService } from '../../services/ids/ExamService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SecureStorageUtil, SecureAlias } from '../../utils/SecureStorageUtil';
import { WeekChip } from '../../components/WeekChip';
import { SEC_START, SEC_END } from '../../models/common/ClassSchedule';

import { fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';
import { calendarManager } from '@kit.CalendarKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { SegmentButton, SegmentButtonOptions } from '@ohos.arkui.advanced.SegmentButton';

const CT_TAG: string = 'ClassTablePage';
const CT_DOMAIN: number = 0xFF00;

// 课程卡片背景色（降低饱和度，白色文字）
const CLASS_COLORS: string[] = ['#559BD6', '#AA68B8', '#E87F5A', '#6EAE6E', '#D86687', '#3EA8BC', '#D6B23E', '#82AD5A', '#8E6EBB', '#3EA6D6'];
const CLASS_COLORS_DK: string[] = ['#1A3A5C', '#3A1A4C', '#4A2018', '#1A3A1E', '#3A1A2E', '#1A3A4C', '#4A3A18', '#2A3A1A', '#2A1A3A', '#1A3A4C'];
// 实验卡片背景色（橙色系）
const EXP_COLORS: string[] = ['#E8903E', '#CC5C20', '#DC7C30', '#D86828', '#E89838'];
const EXP_COLORS_DK: string[] = ['#4A2818', '#3A1818', '#3A2018', '#3A1A18', '#4A2A18'];
// 考试卡片背景色（红色系）
const EXAM_COLORS: string[] = ['#D65048', '#BA3838', '#C44240', '#E05250', '#DC6058'];
const EXAM_COLORS_DK: string[] = ['#4A1A1A', '#3A1818', '#3A1A1A', '#4A1A1A', '#4A1A18'];
// 课程卡片描边色（比背景亮一档，参考 Flutter Traintime 的 shade300 描边，让方块更有“卡片感”）
const CLASS_COLORS_BD: string[] = ['#7FB8E6', '#C89AD2', '#F2A385', '#94C994', '#E892AB', '#6FC6D6', '#E6CD72', '#A6C684', '#B296D6', '#6FC2E6'];
const EXAM_COLORS_BD: string[] = ['#E47C76', '#D06A6A', '#D8706E', '#EA7E7C', '#E6847E'];
const DAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const DAY_COUNT = 7;
const SECTION_COUNT = 11;
// 课表格子水平间隙（百分比，相对周宽）—— 参考 Flutter Traintime：方块间留细缝，更紧凑精致
const CELL_GAP: number = 1;
// 课表格子垂直间隙（px）
const CELL_GAP_V: number = 3;

// 分隔行：午休(第4-5节间)、放学(第8-9节间)
const BREAK_HEIGHT: number = 32;
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
  id: string = '';           // 唯一标识（用于精确增删）
  name: string = '';
  teacher: string = '';
  classroom: string = '';
  day: number = 0;
  startSection: number = 0;
  endSection: number = 0;
  startTime: string = '';    // 开始钟点 HH:MM
  endTime: string = '';      // 结束钟点 HH:MM
  weekList: number[] = [];
  colorIndex: number = 0;
  type: number = 0;          // 0=课程, 1=考试, 2=实验
  examDate: string = '';     // 考试日期 yyyy-MM-dd
  examTimeStart: string = '';// 开始时间 HH:MM
  examTimeEnd: string = '';  // 结束时间 HH:MM
  examSeat: string = '';     // 座位号
}

class ClassCell {
  name: string = '';
  teacher: string = '';
  classroom: string = '';
  day: number = 0;
  startSection: number = 0;
  endSection: number = 0;
  startTime: string = '';    // 开始钟点 HH:MM（实验优先用此字段）
  endTime: string = '';      // 结束钟点 HH:MM
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
  examColumnSpan: number = 1;    // 同一天多个重叠考试时分列数（>=2时等分宽度）
  examColumnIndex: number = 0;   // 当前考试在分列中的序号（0起始）
  isCustom: boolean = false;
  customId: string = '';     // 关联 CustomCourseItem.id
}


@Component
export struct ClassTablePage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
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
  @State refreshing: boolean = false;
  @State showCacheBanner: boolean = false;
  @State emptySchedule: boolean = false; // 服务器确认本学期为空课表（新学期课程未发布），显示友好提示而非误导为 bug
  // 定时器统一管理：所有 setTimeout 走 later() 记录 id，aboutToDisappear 统一清理，避免页面销毁后回调写状态
  private timerIds: number[] = [];

  private later(fn: () => void, ms: number): void {
    const id: number = setTimeout(() => {
      const idx: number = this.timerIds.indexOf(id);
      if (idx >= 0) { this.timerIds.splice(idx, 1); }
      fn();
    }, ms) as number;
    this.timerIds.push(id);
  }

  aboutToDisappear(): void {
    for (let i = 0; i < this.timerIds.length; i++) {
      clearTimeout(this.timerIds[i]);
    }
    this.timerIds = [];
  }
  @State termEnded: boolean = false;  // 当前周已超过数据最后周（学期已结束），显示提示
  // 课表单元格缓存（仅 currentWeek 变化时更新，避免拖拽时每帧重算）
  // 渲染缓存：key=`${week}_${day}` → 该天要显示的 cell 列表
  // buildCellCache() 写入，build() 里的 ForEach 读取，实现增量更新
  @State _renderCache: Map<string, ClassCell[]> = new Map();
  @State _gridVersion: number = 0;  // 每次数据变更递增，用于 ForEach key

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
  @State addCourseType: number = 0;     // 0=课程, 1=考试, 2=实验
  @State addCourseName: string = '';
  @State addCourseTeacher: string = '';
  @State addCourseClassroom: string = '';
  @State addCourseWeekList: boolean[] = [];
  @State editingCustomIndex: number = -1;  // -1=add, >=0=edit
  @State savedDetailDay: number = -1;   // 编辑前保存的详情位置
  @State savedDetailSection: number = -1;
  @State addCourseDay: number = 0;
  @State addCourseStartSection: number = 0;
  @State addCourseEndSection: number = 0;
  @State addCourseStartTime: string = '';   // 选择的时间 HH:MM
  @State addCourseEndTime: string = '';
  // 考试专用
  @State addExamDate: string = '';       // yyyy-MM-dd
  @State addExamTimeStart: string = '';  // HH:MM
  @State addExamTimeEnd: string = '';    // HH:MM
  @State addExamSeat: string = '';
  // 高级分段控件（API26 重设计：替代手写 Row 分段）
  @State addCourseSegOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [
      { text: '📘 课程' },
      { text: '📝 考试' },
      { text: '🧪 实验' }
    ],
    selectedBackgroundColor: (AppStorage.get('accent_color') as string ?? '#2979FF'),
    selectedFontColor: '#FFFFFF'
  });
  @State addCourseSegSel: number[] = [0];
  @State weekIndexList: number[] = [];

  // 操作反馈 toast
  @State actionToast: string = '';
  @State actionToastTimer: number = 0;

  // 自定义课表背景图片
  @State classBgShow: boolean = false;
  @State classBgPath: string = '';
  @State classBgOpacity: number = 0.06;

  // 日历提醒选择弹窗
  @State showReminderDialog: boolean = false;
  @State calendarImporting: boolean = false;
  @State calendarImportMsg: string = '';
  @State reminderMinutes: number = 10;
  @State reminderMode: number = 0; // 0=fixed, 1=custom, 2=none
  @State customReminderInput: string = '30';

  // 未安排课程弹窗
  @State showUnscheduledDialog: boolean = false;
  @State unscheduledOpacity: number = 0;
  @State unscheduledTranslate: number = 30;
  @State unscheduledList: UnscheduledCourse[] = [];
  @State unscheduledLoading: boolean = false;
  @State unscheduledMsg: string = '';

  // 课程变更弹窗
  @State showClassChangesDialog: boolean = false;
  @State classChangesOpacity: number = 0;
  @State classChangesTranslate: number = 30;
  @State classChangesList: ClassChange[] = [];
  @State classChangesLoading: boolean = false;
  @State classChangesMsg: string = '';

  private ehall = EhallService.getInstance();
  private classSvc = ClassService.getInstance();
  private localFilePath: string = '';
  private readonly EXP_CACHE_KEY: string = 'sysj_exp_cache';
  private lastRenderedRaw: string = '';
  private ROW_HEIGHT: number = 58;
  private swiperController: SwiperController = new SwiperController(); // GPU 级滑动
  @State _weekList: number[] = [1]; // Swiper 数据源，maxWeek 变化时更新
  @StorageLink('preload_status') preloadStatus: string = '';
  @StorageLink('login_state') @Watch('onLoginDetected') loginState: string = '';
  private _preloadWasRunning: boolean = false;
  private _loginHandled: boolean = false;
  private _preloadDone: boolean = false;
  private _fetching: boolean = false;  // 防止并发 fetchAndSave
  private retryCount: number = 0;     // 课表加载重试次数
  private readonly MAX_RETRY: number = 3;

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
    this.loading = true;  // 先标记加载中，避免 initGrid() 空网格闪屏
    this.semesterCode = SemesterUtil.getCurrentSemesterCode();
    this.currentWeek = SemesterUtil.calcCurrentWeekFromNow();
    this._preloadWasRunning = (this.preloadStatus === 'loading');
    // 研究生优先用 yjspt API 返回的实际周数
    if (PreferenceUtil.getBool('role')) {
      const yw: number = PreferenceUtil.getNumber('yjspt_current_week', 0);
      if (yw > 0) { this.currentWeek = yw; }
    }
    this.buildCellCache();
    // 自定义课表背景
    this.classBgShow = PreferenceUtil.getBool('class_bg_show', false);
    if (this.classBgShow) {
      const rawPath: string = PreferenceUtil.getString('class_bg_path', '');
      // 检查图片文件是否存在
      try {
        if (rawPath.length > 0 && fileIo.accessSync(rawPath)) {
          this.classBgPath = fileUri.getUriFromPath(rawPath);
        } else {
          this.classBgShow = false;
        }
      } catch (_) {
        this.classBgShow = false;
      }
      const op: number = PreferenceUtil.getNumber('class_bg_opacity', 60);
      this.classBgOpacity = op / 100;
    }
    this.initGrid();
    this.waitAndLoad();
  }

  private async waitAndLoad(): Promise<void> {
    this.retryCount = 0; // 每次页面出现时重置重试计数器
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
    } catch (e) {
      // 学号补全失败不阻断课表加载，但留日志（sid 为空会导致部分请求参数缺失）
      console.warn('[ClassTablePage] fetchStudentId fill failed: ' + String(e));
    }

    // 首次登录后 cookie/session 可能还未就绪，课表为空时自动重试
    // （服务器已确认空课表 emptySchedule 时不再白重试——新学期课程未发布是正常现象）
    if (this.isClassGridEmpty() && !this.emptySchedule && this.isClassTableLoggedIn() && this.retryCount < this.MAX_RETRY) {
      this.retryCount++;
      this.later(() => {
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

  private countClassGridCourses(): number {
    let count: number = 0;
    for (let d = 1; d < this.classGrid.length; d++) {
      if (this.classGrid[d]) {
        for (let s = 1; s < this.classGrid[d].length; s++) {
          if (this.classGrid[d][s]) {
            count += this.classGrid[d][s].length;
          }
        }
      }
    }
    return count;
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
    const swift: number = PreferenceUtil.getNumber('week_swift', 0);
    const dayOfWeek = startDate.getDay();
    const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
    const monday = new Date(startDate);
    monday.setDate(startDate.getDate() + mondayOffset + swift * 7);
    const targetDate = new Date(monday);
    targetDate.setDate(monday.getDate() + (week - 1) * 7 + (dayIdx - 1));
    return (targetDate.getMonth() + 1) + '月' + targetDate.getDate() + '日';
  }

  private getWeekRangeLabel(): string {
    const startDate = this.getDateStr(this.currentWeek, 1);
    const endDate = this.getDateStr(this.currentWeek, 7);
    return '第' + this.currentWeek + '周 · ' + startDate + ' - ' + endDate;
  }

  private async readLocalClassTable(): Promise<string | null> {
    if (!this.localFilePath) return null;
    try {
      const file: fileIo.File = await fileIo.open(this.localFilePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(this.localFilePath);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buf);
      await fileIo.close(file);
      const decoder = util.TextDecoder.create('utf-8');
      const result: string = decoder.decodeToString(new Uint8Array(buf));
      if (result.length > 0) return result;
    } catch (e) {
      console.warn('[ClassTablePage] readLocalClassTable failed: ' + String(e));
    }
    return null;
  }

  private async writeLocalClassTable(raw: string): Promise<void> {
    if (!this.localFilePath) return;
    try {
      const encoder = new util.TextEncoder();
      const encoded: Uint8Array = encoder.encodeInto(raw);
      const file: fileIo.File = await fileIo.open(this.localFilePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      await fileIo.write(file.fd, encoded.buffer);
      await fileIo.close(file);
    } catch (e) {
      // 课表本地缓存写失败：下次启动无缓存可显示（会走网络），不影响当前内存态，留日志便于排查
      console.warn('[ClassTablePage] writeLocalClassTable failed: ' + String(e));
    }
  }

  // 课表数据源是否已就绪：本科生走超星（会话可由西电账号 SSO 打通），研究生走 yjspt（CAS）
  private isClassTableLoggedIn(): boolean {
    if (PreferenceUtil.getBool('role')) {
      return PreferenceUtil.getBool('is_logged_in');
    }
    // 有超星会话，或 CAS 在登录态（服务层会用 SSO 静默打通超星）都算就绪
    return ChaoxingClassService.hasKbSession() || PreferenceUtil.getBool('is_logged_in');
  }

  private async fetchAndSave(): Promise<void> {
    if (this._fetching) {
      return;
    }
    this._fetching = true;
    this.errorMsg = '';
    this.loading = true;  // 确保加载动画显示（onLoginDetected 直接调用时 loading 可能为 false）
    const sid: string = PreferenceUtil.getString('ids_account');
    // Step 1: 缓存优先 — 有缓存先显示
    try {
      let cached: string | null = await this.readLocalClassTable();
      if (!cached || cached.length < 100) {
        cached = await this.classSvc.getCachedClassTableStale(this.semesterCode, sid);
      }
      if (cached && cached.length >= 100) {
        // 预检查：缓存数据是否包含有效课程
        const cachedItems: ClassItemModel[] = ClassService.parseClassTable(cached);
        if (cachedItems.length === 0 && this.hasCache) {
        } else {
          await this.renderClassTable(cached);
          this.lastRenderedRaw = cached;
          this.hasCache = true;
          this.loading = false;  // 有缓存立即显示课表
          this.mergeExperimentDataIntoGrid();
          this.buildCellCache();
          this.saveClassGridSnapshot();
          this.loadExamDataInPlace(); // 也加载缓存的考试（内部会再次 saveSnapshot）
          if (this._preloadWasRunning) {
            this.syncProgress = '正在同步最新数据...';
          }
        }
      } else if (cached && cached.length > 0) {
        // 缓存文件存在但数据太短（可能损坏），尝试用它，至少不白屏
        try {
          await this.renderClassTable(cached);
          this.lastRenderedRaw = cached;
          this.hasCache = true;
          this.loading = false;
        } catch (e2) {
          console.warn('[ClassTablePage] render damaged cache failed: ' + String(e2));
        }
      } else {
      }
    } catch (_e) { /* ignore */ }

    // Step 2: 后台拉最新数据（需登录）
    // 本科生课表数据源已迁至超星：无超星会话时会由服务层用西电账号 SSO 静默打通，
    // 因此只要西电 CAS 在线就放行；只有 CAS 也不在线时才在此拦截（避免空跑网络）。
    const isLoggedIn: boolean = this.isClassTableLoggedIn();
    if (!isLoggedIn) {
      if (!PreferenceUtil.getBool('role') && !this.hasCache) {
        // 无缓存可显示：给出明确指引，而不是停在空白网格
        this.errorMsg = '无法读取课表：请先登录西电账号（我的 → 登录），课表将自动同步';
      } else {
        this.loadProgress = '⚠️ 未登录，显示缓存数据';
        this.later(() => { this.loadProgress = ''; }, 3000);
      }
      this.loading = false;
      // 原实现在此处直接 return 会漏掉 finally 里的 _fetching 复位，
      // 导致后续任何刷新都被 _fetching 挡住（课表永远停在缓存）
      this._fetching = false;
      return;
    }

    try {
      let raw: string | null = null;
      raw = await this.classSvc.getCachedClassTable(this.semesterCode, sid);
      // 如果缓存与已渲染数据不同（preload 先拿到了一份更短的脏缓存），跳过缓存直拉服务器
      if (raw && this.hasCache && this.lastRenderedRaw.length > 0 && raw !== this.lastRenderedRaw) {
        raw = await this.classSvc.getClassTable(this.semesterCode, sid, true);
      } else if (!raw || raw.length < 100) {
        // 首次登录/预加载时显示同步提示，后续进入不显示
        if (this._preloadWasRunning || !this.hasCache) {
          this.syncProgress = '正在获取课表数据...';
        }
        raw = await this.classSvc.getClassTable(this.semesterCode, sid, true);
      }
      // 只有数据变化或首次加载才重新渲染
      // 防止缓存数据解析出空课表覆盖已有网格
      if (raw && (raw !== this.lastRenderedRaw || !this.hasCache)) {
        // 先尝试验证新数据有效性
        const items: ClassItemModel[] = ClassService.parseClassTable(raw);
        const oldCount: number = this.countClassGridCourses();
        // 新数据 0 课程，或课程数不足旧数据的 30%（可能是网络波动返回不完整数据）
        if (items.length === 0 || (this.hasCache && oldCount > 0 && items.length < oldCount * 0.3)) {
          if (this.hasCache && oldCount > 0) {
            // 已有课缓存 + 新数据空/不足 → 保留缓存，显示「缓存数据」横幅（网络波动兜底）
            this.showCacheBanner = true;
            this.emptySchedule = false;
          } else {
            // 无缓存（首次进入/新学期）：服务器确认本学期就是空课表 →
            // 显示友好空状态提示，不再误导为「缓存数据」或「加载失败」
            this.emptySchedule = true;
            this.showCacheBanner = false;
            // 空课表也要初始化渲染缓存 + Swiper 周数数据源（maxWeek 取标准周数），
            // 否则 _weekList 停在初始 [1]、Swiper 只有一页，滑动切周无反应
            this.buildCellCache();
          }
        } else {
          this.showCacheBanner = false;
          this.emptySchedule = false;
          await this.renderMergedClassTable(raw);
          this.lastRenderedRaw = raw;
          this.hasCache = true;
          await this.writeLocalClassTable(raw);
        }
      }

      // Step 3: 同步实验和考试
      // [FIX] 无论首登还是后台刷新，重渲染课表后都必须重新合并实验/考试。
      // 否则后台刷新用纯课程重建 classGrid 会覆盖掉已合并的实验，导致实验"一闪即消失"。
      this.syncProgress = '正在同步实验数据...';
      let expCount = 0;
      try {
        if (this._preloadWasRunning || !this.hasCache) {
          expCount = await ExperimentService.getInstance().preloadDirect();
        }
        if (expCount > 0 || this.hasCache) {
          this.mergeExperimentDataIntoGrid();
          this.buildCellCache();
        }
      } catch (_e) { /* ignore */ }
      try { await this.mergePhysicsExperiments(); } catch (_e) { /* ignore */ }

      this.syncProgress = '正在同步考试数据...';
      this.loadExamDataInPlace().then((examCount: number) => {
        this.syncProgress = '';
        this.loading = false;
      }).catch((e: Error) => {
        this.syncProgress = '';
        this.loading = false;
      });

      // 首次登录：预加载实验/考试数据可能还未就绪，轮询等待后合并
      if (this._preloadWasRunning && !this._preloadDone) {
        this.schedulePreloadRetry(0);
      }
    } catch (e) {
      if (this.hasCache && this.lastRenderedRaw && this.lastRenderedRaw.length > 0) {
        // 有缓存，网络失败可以接受
        this.showCacheBanner = true;
        this.loadProgress = '';
      } else {
        // 超星会话缺失（西电未登录/SSO 打通失败）与纯网络错误分开提示
        const errMsg: string = String(e);
        this.errorMsg = errMsg.indexOf('CX_NEED_LOGIN') >= 0
          ? '无法读取课表：西电账号未登录或会话已过期，请重新登录'
          : '加载课程表失败，请检查网络';
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
      this._fetching = false;
    }
  }

  // 轮询等待预加载完成（最多重试 6 次，每次间隔 3 秒 = 最长 18 秒）
  private schedulePreloadRetry(retryCount: number): void {
    if (retryCount >= 6) {
      return;
    }
    this.later(() => {
      if (this.preloadStatus === 'done') {
        if (!PreferenceUtil.getBool('role')) { this.mergeExperimentDataIntoGrid(); this.buildCellCache(); }
        try { this.mergePhysicsExperiments(); } catch (e) {
          console.warn('[ClassTablePage] mergePhysicsExperiments failed: ' + String(e));
        }
        this.loadExamDataInPlace();
        this._preloadDone = true;
      } else if (PreferenceUtil.getBool('is_logged_in')) {
        this.schedulePreloadRetry(retryCount + 1);
      }
    }, 3000);
  }

  async loadTable(forceRefresh: boolean = false): Promise<void> {
    if (forceRefresh) {
      if (this.refreshing) { return; }
      this.refreshing = true;
      // 不提前重置 errorMsg/syncProgress：连续状态变化会导致 Refresh 组件重新布局子控件、课表暂时空白
      const sid: string = PreferenceUtil.getString('ids_account');
      try {
        const raw: string = await this.classSvc.getClassTable(this.semesterCode, sid, true);
        if (raw !== this.lastRenderedRaw) {
          const items: ClassItemModel[] = ClassService.parseClassTable(raw);
          if (items.length === 0) {
            if (this.hasCache) {
              this.errorMsg = '刷新失败：服务器返回空数据，保留当前课表';
              this.showCacheBanner = true;
            } else {
              // 无缓存 + 刷新仍空：服务器确认本学期空课表
              this.emptySchedule = true;
              this.showCacheBanner = false;
              // 同步初始化缓存与周数数据源，保证空课表也能滑动切周
              this.buildCellCache();
            }
          } else {
            this.showCacheBanner = false;
            this.emptySchedule = false;
            await this.renderMergedClassTable(raw);
            await this.writeLocalClassTable(raw);
          }
          this.lastRenderedRaw = raw;
        }
        // 刷新后重新合并实验和考试
        this.syncProgress = '正在同步实验数据...';
        this.mergeExperimentDataIntoGrid();
        this.buildCellCache();
        try { await this.mergePhysicsExperiments(); } catch (e) {
          console.warn('[ClassTablePage] mergePhysicsExperiments failed: ' + String(e));
        }
        this.syncProgress = '正在同步考试数据...';
        await this.loadExamDataInPlace();
        this.syncProgress = '';
        AppStorage.setOrCreate('ct_updated', String(Date.now()));
      } catch (e) {
        const errMsg: string = String(e);
        this.errorMsg = errMsg.indexOf('CX_NEED_LOGIN') >= 0
          ? '刷新失败：西电账号未登录或会话已过期，请重新登录'
          : '刷新失败，请检查网络';
        if (this.hasCache) { this.showCacheBanner = true; }
      } finally {
        this.syncProgress = '';
        this.refreshing = false;
      }
    } else {
      const local = await this.readLocalClassTable();
      if (local) {
        await this.renderMergedClassTable(local);
        this.loading = false;
        this.hasCache = true;
      } else {
        await this.fetchAndSave();
      }
    }
  }

  private async renderClassTable(raw: string): Promise<void> {
    const items: ClassItemModel[] = ClassService.parseClassTable(raw);
    const nameColorMap = new Map<string, number>();
    let colorIdx = 0;
    const grid: ClassCell[][][] = [];
    for (let d = 0; d <= DAY_COUNT; d++) {
      grid[d] = [];
      for (let s = 0; s <= SECTION_COUNT; s++) {
        grid[d][s] = [];
      }
      if (this.classGrid[d] && this.classGrid[d][0]) {
        grid[d][0] = this.classGrid[d][0].filter((c: ClassCell) => c.isExam);
      }
    }

    for (const item of items) {
      const weekList = this.parseWeekList(item.skzc);
      // 注：maxWeek 不再在此处单独维护，改由 recalcMaxWeek() 在 buildCellCache 时统一计算（含考试周），避免学期末 currentWeek 超界导致整周空白
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
    await this.loadCustomCourses(grid);
    this.classGrid = grid;
    this.updateWeekList();
    this.buildCellCache();
    this.computeCellStatuses();
    this.saveClassGridSnapshot();
  }

  // [FIX] 不再由课表页写入 class_grid_snapshot。
  // 该快照现由 MainPage.loadClassPreview 作为【唯一权威写入者】：它合并学校课表/实验/自定义，
  // 周次 weekNum 正确。课表页此前是“第二写入者”，且在异步缓存未就绪时会写出 实验=0 或 wn=0 的
  // 残缺快照，最后写入者覆盖 → 导入日历页实验数在 0/4 间抖动（日志实锤：ClassTablePage 写出
  // 实验=0 后立刻被导出页读到）。课表页编辑后已通过 ct_updated 通知 MainPage 轮询重写快照，
  // 无需本页再写。保留 7 处调用点不动，仅此处不再落盘，避免误覆盖。
  private saveClassGridSnapshot(): void {
  }

  /**
   * 渲染课表前先合并"课程变更"（调课/停课/补课）进网格，对齐 Flutter 让课表本体反映真实安排。
   * 仅在本科生路径合并（研究生 KCH 为空，无法可靠匹配变更，跳过）。
   * 变更获取失败时回退原始 raw，保证课表至少正常显示。
   */
  private async renderMergedClassTable(raw: string): Promise<void> {
    let merged: string = raw;
    if (!PreferenceUtil.getBool('role')) {
      try {
        const changesJson: string = await this.classSvc.getClassChangesEhall(this.semesterCode);
        merged = ClassService.applyClassChanges(raw, changesJson);
      } catch (_e) {
        merged = raw;
      }
    }
    await this.renderClassTable(merged);
  }


  // 获取真实日历周次（不受用户滑动切换影响）
  private getRealCurrentWeek(): number {
    return SemesterUtil.calcCurrentWeekFromNow();
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

  // 获取考试卡片的时间状态：-1=已结束, 0=未开始, 1=进行中
  private getExamStatus(cell: ClassCell): number {
    if (!cell.isExam || !cell.examDate) return 0;
    // examDate: "2026-04-22"  examTimeDesc: "13:00-15:00 星期三"
    const dateStr: string = cell.examDate;
    const timePart: string = cell.examTimeDesc.split(' ')[0] || '';  // "13:00-15:00"
    if (!timePart.includes('-')) return 0;
    const parts: string[] = timePart.split('-');
    if (parts.length < 2) return 0;
    const startTime: string = parts[0];
    const endTime: string = parts[1];
    const startParts: string[] = startTime.split(':');
    const endParts: string[] = endTime.split(':');
    if (startParts.length < 2 || endParts.length < 2) return 0;
    const startMin: number = parseInt(startParts[0]) * 60 + parseInt(startParts[1]);
    const endMin: number = parseInt(endParts[0]) * 60 + parseInt(endParts[1]);
    // 比较日期
    const now: Date = new Date();
    const examDay: Date = new Date(dateStr + 'T00:00:00');
    const todayStart: Date = new Date(now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0') + '-' + String(now.getDate()).padStart(2, '0') + 'T00:00:00');
    if (examDay.getTime() > todayStart.getTime()) return 0;  // 未来
    if (examDay.getTime() < todayStart.getTime()) return -1; // 过去
    // 同一天：比较时间
    const nowMin: number = now.getHours() * 60 + now.getMinutes();
    if (nowMin >= startMin && nowMin < endMin) return 1;  // 进行中
    if (nowMin >= endMin) return -1;  // 已结束
    return 0;  // 未开始
  }

  // 在当前 classGrid 上合并实验数据
  private mergeExperimentDataIntoGrid(): boolean {
    const cached = PreferenceUtil.getString(this.EXP_CACHE_KEY);
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
        this.saveClassGridSnapshot();
        return true;
      }
    } catch (_e) { /* ignore */ }
    return false;
  }

  // 异步加载考试，返回加载数量
  private async loadExamDataInPlace(): Promise<number> {
    const cached: string = PreferenceUtil.getString('exam_schedule_cache');
    let count: number = 0;
    if (cached.length > 0) {
      try {
        const items: ExamItemModel[] = ExamService.parseExamSchedule(cached);
        if (items.length > 0) {
          this.applyExamItems(items);
          count = items.length;
        }
      } catch (e) {
        // 考试缓存解析失败：本次不显示考试行，下次刷新会重拉
        console.warn('[ClassTablePage] loadExamDataInPlace parse failed: ' + String(e));
      }
    }
    // applyExamItems 会清除所有考试（含自定义），事后补回
    await this.loadCustomCourses(this.classGrid);
    this.buildCellCache();
    this.saveClassGridSnapshot();
    // [FIX] 不再在此直调 autoSync：本页 saveClassGridSnapshot 已为空实现（快照唯一权威写入者 =
    // MainPage.loadClassPreview），此处直调会基于旧快照空跑/误判，属旧快照竞态源头。
    // 课表数据变化已由 ct_updated 通知 MainPage 轮询 → loadClassPreview → 尾部顺序 autoSync。
    return count;
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
        cell.day = weekday;
        cell.startSection = startSec;
        cell.endSection = endSec;
        cell.startTime = startSec > 0 && startSec <= 11 ? SEC_START[startSec] : '';
        cell.endTime = endSec > 0 && endSec <= 11 ? SEC_END[endSec] : '';
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
      return false;
    }
    return true;
  }

  // 从 _custom.json 加载自定义课程合并到 grid
  private async loadCustomCourses(grid: ClassCell[][][]): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const customPath: string = context.filesDir + '/class_table_' + this.semesterCode + '_custom.json';
      const file = await fileIo.open(customPath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(customPath);
      const buf = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buf);
      await fileIo.close(file);
      const decoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(new Uint8Array(buf));
      const items: CustomCourseItem[] = JSON.parse(text) as CustomCourseItem[];

      this.customList = items;
      // 先清除 grid 中所有自定义课程，避免累积重复
      for (let cd = 1; cd <= 7; cd++) {
        for (let cs = 0; cs <= 11; cs++) {
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
        cell.customId = item.id || `${item.day}_${item.startSection}_${item.name}_${idx}`;
        cell.teacher = item.teacher;
        cell.classroom = item.classroom;
        cell.day = item.day;
        cell.startSection = item.startSection;
        cell.endSection = item.endSection;
        cell.startTime = item.startTime || '';
        cell.endTime = item.endTime || '';
        // 旧数据兼容：有 section 无 time 时用 SEC_START/SEC_END 填充
        if (!cell.startTime && cell.startSection > 0 && cell.startSection <= 11) cell.startTime = SEC_START[cell.startSection];
        if (!cell.endTime && cell.endSection > 0 && cell.endSection <= 11) cell.endTime = SEC_END[cell.endSection];
        cell.isCustom = true;
        // 新字段 type
        const itType: number = item.type || 0;
        cell.isExam = (itType === 1);
        cell.isExperiment = (itType === 2);
        cell.examDate = item.examDate || '';
        cell.examTimeDesc = (item.examTimeStart || '') + (item.examTimeStart && item.examTimeEnd ? '-' + item.examTimeEnd : '');
        cell.examSeat = item.examSeat || '';

        const weekList: boolean[] = [];
        for (let w = 0; w < 26; w++) weekList.push(false);
        if (itType === 1) {
          // 考试：根据 examDate 计算属于哪一周
          cell.weekList = weekList;
          cell.weekDesc = item.examDate || '';
          // 从 examDate 反推学期周次，设置 weekList 以便按周过滤渲染
          if (item.examDate) {
            const exDate = new Date(item.examDate + 'T00:00:00');
            if (!isNaN(exDate.getTime())) {
              const semStart = SemesterUtil.getSemesterStartDate(this.semesterCode);
              const swift: number = PreferenceUtil.getNumber('week_swift', 0);
              const dayMs: number = 86400000;
              const weekNum: number = Math.max(1,
                Math.floor((exDate.getTime() - semStart.getTime() - swift * 7 * dayMs) / dayMs / 7) + 1);
              if (weekNum >= 1 && weekNum <= 26) {
                weekList[weekNum - 1] = true;
                cell.weekDesc = '第' + weekNum + '周';
              }
            }
          }
          // 用 timeToY 计算像素坐标
          if (item.examTimeStart && item.examTimeEnd) {
            const startY: number = this.timeToY(item.examTimeStart);
            const endY: number = this.timeToY(item.examTimeEnd);
            cell.examPixelY = startY;
            cell.examPixelH = Math.max(endY - startY, 20);
            // 找到对应的节次
            for (let s = 1; s <= 11; s++) {
              const secStartY: number = this.getSectionY(s);
              if (secStartY <= startY && startY < secStartY + this.ROW_HEIGHT) {
                cell.startSection = s;
                break;
              }
            }
            for (let s = cell.startSection; s <= 11; s++) {
              const secEndY: number = this.getSectionY(s) + this.ROW_HEIGHT;
              if (endY <= secEndY) {
                cell.endSection = s;
                break;
              }
            }
            if (cell.endSection === 0) cell.endSection = cell.startSection;
          }
          cell.colorIndex = item.colorIndex;
        } else {
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
          cell.weekDesc = this.formatWeekDesc(weekList);
          cell.colorIndex = item.colorIndex;
        }

        if (cell.day > 0) {
          if (cell.isExam) {
            // 考试存放在 section 0，渲染代码从 classGrid[day][0] 取
            grid[cell.day][0].push(cell);
          } else if (cell.startSection > 0 && cell.endSection >= cell.startSection) {
            grid[cell.day][cell.startSection].push(cell);
          }
        }
      }
    } catch (e) {
      // 自定义课程解析失败：该部分课程不显示，其余不受影响
      console.warn('[ClassTablePage] loadCustomCourses failed: ' + String(e));
    }
  }

  private applyExamItems(items: ExamItemModel[]): void {
    const startDate: Date = SemesterUtil.getSemesterStartDate(this.semesterCode);
    let examColorIdx: number = 0;
    // 浅拷贝 grid 避免逐格 filter 触发多次渲染
    const grid: ClassCell[][][] = [];
    for (let d = 0; d <= DAY_COUNT; d++) {
      grid[d] = [];
      for (let s = 0; s <= SECTION_COUNT; s++) {
        grid[d][s] = this.classGrid[d][s].filter((c: ClassCell) => !c.isExam);
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
      const swift: number = PreferenceUtil.getNumber('week_swift', 0);
      const weekNum: number = Math.floor(diffDays / 7) + 1 - swift;
      const weekday: number = examDate.getDay() || 7;
      if (weekNum < 1 || weekNum > 25 || weekday < 1 || weekday > 7) continue;
      // kssjms format: "2026-04-22 13:00-15:00(星期三)" — extract time portion only
      const spaceIdx: number = kssjms.indexOf(' ');
      const timeWithDay: string = spaceIdx >= 0 ? kssjms.substring(spaceIdx + 1) : kssjms;
      const parenIdx: number = timeWithDay.indexOf('(');
      const timeOnly: string = parenIdx >= 0 ? timeWithDay.substring(0, parenIdx) : timeWithDay;
      const timeParts: string[] = timeOnly.split('-');
      const startY: number = this.timeToY(timeParts[0]);
      const endY: number = this.timeToY(timeParts[1]);
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
        grid[weekday][0].push(cell);
      }
    }
    this.classGrid = grid; // 原子替换，避免逐格 filter 闪烁
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
              Text('📦 当前显示缓存数据').fontSize(12).fontColor(ThemeColors.warning)
              Text('  刷新').fontSize(12).fontColor(this.accentColor)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .border({ width: 1, color: this.accentColor, radius: 4 })
                .margin({ left: 10 })
                .hoverEffect(HoverEffect.Auto).onClick(() => {
                  this.showCacheBanner = false;
                  this.loadTable(true);
                })
            }.width('100%').height(32).justifyContent(FlexAlign.Center)
            .backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
          }
          // 空课表状态改为网格中央空态层呈现（见下方 buildClassGrid 处），此处不再占 32px 横幅
          if (this.termEnded) {
            Row() {
              Text('📅 当前学期已结束，显示最后一周边课表').fontSize(12).fontColor(ThemeColors.textSecondary)
            }.width('100%').height(32).justifyContent(FlexAlign.Center)
            .backgroundColor(ThemeColors.isDark ? '#263238' : '#ECEFF1')
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
              Text(this.loadProgress.length > 0 ? this.loadProgress : '正在获取课程表...')
                .fontSize(15).fontColor(ThemeColors.textPrimary).margin({ top: 16 })
              Text('首次加载约需 3~5 秒，请耐心等待').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 8 })
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else if (this.errorMsg.length > 0) {
            Column() {
              Text('⚠️').fontSize(40)
              Text(this.errorMsg).fontSize(14).fontColor(ThemeColors.error).margin({ top: 8 })
              Button('重试').margin({ top: 12 }).hoverEffect(HoverEffect.Auto).onClick(() => { this.loadTable(); })
              if (this.errorMsg.includes('登录')) {
                Button('去登录').margin({ top: 8 })
                  .hoverEffect(HoverEffect.Auto).onClick(() => { router.pushUrl({ url: 'pages/login/LoginPage' }); })
              }
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            Stack() {
              // 背景图放在 Scroll 外层，不随课表滚动
              if (this.classBgShow && this.classBgPath.length > 0) {
                Image(this.classBgPath)
                  .width('100%').height('100%')
                  .objectFit(ImageFit.Cover)
                  .opacity(ThemeColors.isDark ? this.classBgOpacity * 0.5 : this.classBgOpacity)
                  .interpolation(ImageInterpolation.Medium)
                  .hitTestBehavior(HitTestMode.None)
              }
              Column() {
                this.buildClassGrid()
              }.layoutWeight(1)
              // 空课表（服务器确认本学期未发布课程）：网格中央空态层。
              // 与「加载失败」区分：失败走上方 errorMsg 整页 + 重试，这里是"成功但没课"。
              // 参考 Flutter 空课表设计：空态渲染在网格内部，周次导航/Swiper 照常可用。
              // HitTestMode.None 让触摸穿透到下层 Swiper，滑动切周不受影响。
              if (this.emptySchedule && this.isClassGridEmpty()) {
                Column() {
                  Text('📭').fontSize(42)
                  Text(this.semesterCode.length > 0
                    ? SemesterUtil.formatSemester(this.semesterCode) + ' 暂无课程安排'
                    : '本学期暂无课程安排')
                    .fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor(ThemeColors.textPrimary).margin({ top: 12 })
                  Text('学校还没发布课程，发布后下拉刷新即可显示').fontSize(12)
                    .fontColor(ThemeColors.textSecondary).margin({ top: 8 })
                  Text('左右滑动或点击上方箭头可浏览各周').fontSize(12)
                    .fontColor(ThemeColors.textHint).margin({ top: 4 })
                }.width('100%').height('100%').justifyContent(FlexAlign.Center)
                .hitTestBehavior(HitTestMode.None)
              }
            }.layoutWeight(1)
            .onAreaChange((_old: Area, newArea: Area) => {
              const w: number = parseFloat(newArea.width.toString());
              const h: number = parseFloat(newArea.height.toString());
            })
          }
        }.width('100%').height('100%').backgroundColor(Color.Transparent)
        .zIndex(0)

        // 第二层：半透明背景遮罩
        if (this.showDetailDialog) {
          Column()
            .width('100%').height('100%')
            .backgroundColor('rgba(0,0,0,0.7)')
            .opacity(this.maskOpacity)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.hideCellDetail(); })
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
            Text(this.currentConflictCells.length > 0 ?
              (this.currentConflictCells[0].isExam ? '📝 ' : '') + this.currentConflictCells[0].name : '')
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .margin({ top: 16, bottom: 12 }).width('100%').maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

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
                        if (!cell.isExperiment) {
                          this.DetailRow('📆 周次', cell.weekDesc || '未设置')
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
                        // 自定义课程编辑/删除（放在详情最底部）
                        if (cell.isCustom) {
                          Row({ space: 12 }) {
                            Button() {
                              Row({ space: 4 }) {
                                Text('✏️').fontSize(16)
                                Text('编辑').fontSize(13).fontColor((AppStorage.get('accent_color') as string ?? '#2979FF'))
                              }
                            }.layoutWeight(1).height(40).backgroundColor(ThemeColors.isDark ? '#1A3A5C' : '#E3F2FD')
                              .borderRadius(8)
                              .hoverEffect(HoverEffect.Auto).onClick(() => { this.editCustomCourse(cell); })
                            Button() {
                              Row({ space: 4 }) {
                                Text('🗑️').fontSize(16)
                                Text('删除').fontSize(13).fontColor('#C62828')
                              }
                            }.layoutWeight(1).height(40).backgroundColor(ThemeColors.isDark ? '#3E1A1A' : '#FFEBEE')
                              .borderRadius(8)
                              .hoverEffect(HoverEffect.Auto).onClick(() => { this.deleteCustomCourse(cell); })
                          }
                          .margin({ top: 8 })
                        }
                      }.margin({ top: 10 }).width('100%')
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12 })
                  }
                }, (cell: ClassCell, idx: number) => `conflict_${cell.customId}_${idx}_${cell.startSection}`)
              }
              .width('100%')
              .constraintSize({ maxHeight: 360 })
              .divider({ strokeWidth: 0.5, color: '#F0F0F0' })
              .edgeEffect(EdgeEffect.Spring)
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

        // 手动添加日程弹窗（课程/考试/实验三合一，API26 重设计）
        if (this.showAddCourseDialog) {
          Stack() {
            Column()
              .width('100%').height('100%')
              .backgroundColor('rgba(0,0,0,0.5)')
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.cancelAddCourse(); })
            Column() {
              // 标题栏
              Row() {
                Text(this.editingCustomIndex >= 0 ? '编辑日程' : '添加日程')
                  .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                Blank()
                Row() {
                  Text('✕').fontSize(18).fontColor(ThemeColors.textSecondary)
                }
                .width(32).height(32).borderRadius(16).backgroundColor(ThemeColors.bgInput)
                .justifyContent(FlexAlign.Center)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.cancelAddCourse(); })
              }.width('100%').margin({ bottom: 14 })

              // 类型选择器 — 高级分段控件（流畅动画、主题一致）
              SegmentButton({
                options: this.addCourseSegOptions,
                selectedIndexes: this.addCourseSegSel,
                onItemClicked: (idx: number) => {
                  this.addCourseType = idx;
                  if (idx === 1 || idx === 2) this.initExamDefaults();
                }
              })
              .width('100%')
              .margin({ bottom: 14 })

              // 表单内容（统一滚动容器，避免考试表单溢出截断）
              Scroll() {
                Column({ space: 14 }) {
                  if (this.addCourseType === 1) {
                    this.examForm()
                  } else {
                    this.courseForm()
                  }
                }.width('100%')
              }.width('100%').constraintSize({ maxHeight: 460 }).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)

              Row({ space: 12 }) {
                Button('取消').layoutWeight(1).backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textSecondary)
                  .hoverEffect(HoverEffect.Auto).onClick(() => { this.cancelAddCourse(); })
                Button(this.editingCustomIndex >= 0 ? '保存' : '添加').layoutWeight(1)
                  .backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).fontColor('#FFFFFF')
                  .hoverEffect(HoverEffect.Auto).onClick(() => { this.addCustomCourse(); })
              }.margin({ top: 12 }).width('100%')

              // 表单校验提示
              if (this.addFormToast.length > 0) {
                Text(this.addFormToast)
                  .fontSize(12).fontColor('#C62828')
                  .width('100%').textAlign(TextAlign.Center)
                  .margin({ top: 8 })
              }
            }
            .width('92%').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(16)
            .shadow({ radius: 24, color: 'rgba(0,0,0,0.25)', offsetY: 10 })
          }.width('100%').height('100%').zIndex(3)
        }

        // 操作反馈 toast
        if (this.actionToast.length > 0) {
          Text(this.actionToast)
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
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.showReminderDialog = false; })
              Button('导入').layoutWeight(1).backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).fontColor('#FFFFFF')
                .hoverEffect(HoverEffect.Auto).onClick(() => {
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
        // 未安排课程弹窗
        if (this.showUnscheduledDialog || this.unscheduledOpacity > 0) {
        Column() {
          Column() {
            Row() {
              Text('未安排课程').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              Blank()
              Row() { Text('✕').fontSize(18).fontColor(ThemeColors.textSecondary) }
                .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
                .justifyContent(FlexAlign.Center)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.closeUnscheduledDialog(); })
            }.width('100%').margin({ bottom: 14 })
            if (this.unscheduledLoading) {
              Column() {
                LoadingProgress().width(32).height(32).color(this.accentColor)
                Text('加载中...').fontSize(14).fontColor(ThemeColors.textHint).margin({ top: 10 })
              }.padding({ top: 20, bottom: 20 })
            } else if (this.unscheduledMsg.length > 0) {
              Text(this.unscheduledMsg).fontSize(14).fontColor(ThemeColors.textHint)
                .padding({ top: 10, bottom: 10 })
            } else {
              List({ space: 8 }) {
                ForEach(this.unscheduledList, (item: UnscheduledCourse) => {
                  ListItem() {
                    Row() {
                      Column() {
                        Text(item.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        Row() {
                          if (item.number) { Text(item.number + '班').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ right: 12 }) }
                          if (item.teacher) { Text(item.teacher).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ right: 12 }) }
                          if (item.code) { Text(item.code).fontSize(11).fontColor(ThemeColors.textHint) }
                        }.margin({ top: 4 })
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    }
                    .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .backgroundColor(ThemeColors.bgInput).borderRadius(8)
                  }
                })
              }.height(320).scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)
            }
            Button('确定').width('100%').height(40).margin({ top: 14 })
              .backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(10)
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.closeUnscheduledDialog(); })
          }
          .width('85%').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(16)
          .shadow({ radius: 20, color: '#30000000' })
          .opacity(this.unscheduledOpacity)
          .translate({ y: this.unscheduledTranslate })
          .hoverEffect(HoverEffect.Auto).onClick(() => {})
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor(ThemeColors.overlay)
        .opacity(this.unscheduledOpacity)
        .hitTestBehavior(this.showUnscheduledDialog ? HitTestMode.Default : HitTestMode.None)
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.closeUnscheduledDialog(); })
        }
        // 课程变更弹窗
        if (this.showClassChangesDialog || this.classChangesOpacity > 0) {
        Column() {
          Column() {
            Row() {
              Text('课程变更').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              Blank()
              Row() { Text('✕').fontSize(18).fontColor(ThemeColors.textSecondary) }
                .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
                .justifyContent(FlexAlign.Center)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.closeClassChangesDialog(); })
            }.width('100%').margin({ bottom: 14 })
            if (this.classChangesLoading) {
              Column() {
                LoadingProgress().width(32).height(32).color(this.accentColor)
                Text('加载中...').fontSize(14).fontColor(ThemeColors.textHint).margin({ top: 10 })
              }.padding({ top: 20, bottom: 20 })
            } else if (this.classChangesMsg.length > 0) {
              Text(this.classChangesMsg).fontSize(14).fontColor(ThemeColors.textHint)
                .padding({ top: 10, bottom: 10 })
            } else {
              List({ space: 8 }) {
                ForEach(this.classChangesList, (item: ClassChange) => {
                  ListItem() {
                    Column() {
                      Row() {
                        Text(item.type).fontSize(11).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                          .backgroundColor(item.type === '调课' ? '#BF4D00' : (item.type === '停课' ? '#C62828' : '#4CAF50'))
                          .borderRadius(4)
                          .margin({ right: 10 })
                        Text(item.courseName).fontSize(15).fontWeight(FontWeight.Medium)
                          .fontColor(ThemeColors.textPrimary).layoutWeight(1).maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }.width('100%')
                      if (item.originalWeeks || item.originalDay) {
                        Row() {
                          Text('原:').fontSize(11).fontColor(ThemeColors.textHint).width(20)
                          Text(item.originalWeeks + ' ' + item.originalDay + ' ' + item.originalSection).fontSize(12).fontColor(ThemeColors.textSecondary)
                          if (item.originalRoom) Text(' ' + item.originalRoom).fontSize(12).fontColor(ThemeColors.textHint)
                        }.margin({ top: 4 })
                      }
                      if (item.type !== '停课' && (item.newWeeks || item.newDay)) {
                        Row() {
                          Text('新:').fontSize(11).fontColor(ThemeColors.textHint).width(20)
                          Text(item.newWeeks + ' ' + item.newDay + ' ' + item.newSection).fontSize(12).fontColor('#1976D2')
                          if (item.newRoom) Text(' ' + item.newRoom).fontSize(12).fontColor('#1976D2')
                        }.margin({ top: 2 })
                      }
                      if (item.type === '调课' && item.newTeacher) {
                        Text(item.originalTeacher + ' → ' + item.newTeacher).fontSize(11).fontColor(ThemeColors.textHint).margin({ top: 2 })
                      }
                    }
                    .width('100%').alignItems(HorizontalAlign.Start)
                    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .backgroundColor(ThemeColors.bgInput).borderRadius(8)
                  }
                })
              }.height(380).scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)
            }
            Button('确定').width('100%').height(40).margin({ top: 14 })
              .backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(10)
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.closeClassChangesDialog(); })
          }
          .width('85%').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(16)
          .shadow({ radius: 20, color: '#30000000' })
          .opacity(this.classChangesOpacity)
          .translate({ y: this.classChangesTranslate })
          .hoverEffect(HoverEffect.Auto).onClick(() => {})
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor(ThemeColors.overlay)
        .opacity(this.classChangesOpacity)
        .hitTestBehavior(this.showClassChangesDialog ? HitTestMode.Default : HitTestMode.None)
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.closeClassChangesDialog(); })
        }
      }.width('100%').height('100%')
    }
    .hideBackButton(true)
    .title({ builder: this.customTitle(), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
    .onReady(() => {})
    .onShown(() => {
      // 从实验/考试页面返回时，重新合并缓存数据到课表
      if (!this.loading) {
        this.mergeExperimentDataIntoGrid();
        this.loadExamDataInPlace();
        this.mergePhysicsExperiments();
      }
    })
    .onHidden(() => {
      // 页面隐藏（用户返回主页）时，通知主页刷新课表预览
      const flag: string = String(Date.now()) + '_nav_back';
      AppStorage.setOrCreate('ct_updated', flag);
    })
    .onBackPressed(() => {
      if (this.showAddCourseDialog) {
        this.showAddCourseDialog = false;
        this.resetAddCourseForm();
        return true;
      }
      if (this.showDetailDialog) {
        this.hideCellDetail();
        return true;
      }
      if (this.showReminderDialog) {
        this.showReminderDialog = false;
        return true;
      }
      if (this.showUnscheduledDialog) {
        this.closeUnscheduledDialog();
        return true;
      }
      if (this.showClassChangesDialog) {
        this.closeClassChangesDialog();
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

  // ===== 添加弹窗：课程/实验表单 =====
  @Builder courseForm() {
    Row() {
      Text('名称').fontSize(14).fontColor(ThemeColors.textSecondary).width(64)
      TextInput({ placeholder: '必填', text: this.addCourseName })
        .onChange((v: string) => { this.addCourseName = v; })
        .layoutWeight(1).backgroundColor(ThemeColors.bgInput).borderRadius(8)
    }.width('100%')
    Row() {
      Text('教师').fontSize(14).fontColor(ThemeColors.textSecondary).width(64)
      TextInput({ placeholder: '选填', text: this.addCourseTeacher })
        .onChange((v: string) => { this.addCourseTeacher = v; })
        .layoutWeight(1).backgroundColor(ThemeColors.bgInput).borderRadius(8)
    }.width('100%')
    Row() {
      Text('教室').fontSize(14).fontColor(ThemeColors.textSecondary).width(64)
      TextInput({ placeholder: '选填', text: this.addCourseClassroom })
        .onChange((v: string) => { this.addCourseClassroom = v; })
        .layoutWeight(1).backgroundColor(ThemeColors.bgInput).borderRadius(8)
    }.width('100%')

    // 周次
    Row() {
      Text('周次').fontSize(14).fontColor(ThemeColors.textSecondary)
      Blank()
      Row({ space: 14 }) {
        Text('全选').fontSize(12)
          .fontColor((AppStorage.get('accent_color') as string ?? '#2979FF'))
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.setAllWeeks(true); })
        Text('清空').fontSize(12).fontColor(ThemeColors.textSecondary)
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.setAllWeeks(false); })
      }
    }.width('100%').margin({ top: 2, bottom: 6 })
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignContent: FlexAlign.Start }) {
      ForEach(this.weekIndexList, (w: number) => {
        WeekChip({
          week: w,
          selected: this.addCourseWeekList[w - 1],
          current: this.currentWeek,
          accent: (AppStorage.get('accent_color') as string ?? '#2979FF'),
          onToggle: () => { this.addCourseWeekList[w - 1] = !this.addCourseWeekList[w - 1]; }
        })
          .margin({ right: 6, bottom: 6 })
      }, (w: number) => String(w))
    }.width('100%')

    Row() {
      Text('星期').fontSize(14).fontColor(ThemeColors.textSecondary).width(64)
      Select([
        { value: '请选择星期' }, { value: '周一' }, { value: '周二' }, { value: '周三' },
        { value: '周四' }, { value: '周五' }, { value: '周六' }, { value: '周日' }
      ])
        .value(this.getDayValue())
        .selected(this.addCourseDay)
        .onSelect((idx: number) => { this.addCourseDay = idx; })
        .layoutWeight(1).backgroundColor(ThemeColors.bgInput).borderRadius(8)
    }.width('100%')

    if (this.addCourseType === 0) {
      // 课程：选节次
      Row() {
        Text('开始').fontSize(14).fontColor(ThemeColors.textSecondary).width(64)
        Select(this.buildSectionOptions())
          .value(this.getSectionValue(this.addCourseStartSection))
          .selected(this.addCourseStartSection)
          .onSelect((idx: number) => { this.addCourseStartSection = idx; })
          .layoutWeight(1).backgroundColor(ThemeColors.bgInput).borderRadius(8)
      }.width('100%')
      Row() {
        Text('结束').fontSize(14).fontColor(ThemeColors.textSecondary).width(64)
        Select(this.buildSectionOptions())
          .value(this.getSectionValue(this.addCourseEndSection))
          .selected(this.addCourseEndSection)
          .onSelect((idx: number) => { this.addCourseEndSection = idx; })
          .layoutWeight(1).backgroundColor(ThemeColors.bgInput).borderRadius(8)
      }.width('100%')
    } else {
      // 实验：选时间
      Column() {
        Text('时间').fontSize(14).fontColor(ThemeColors.textSecondary).width('100%').margin({ bottom: 4 })
        Row({ space: 10 }) {
          TimePicker({
            selected: this.addCourseStartTime.length > 0 ? this.parseTime(this.addCourseStartTime) : new Date(2026, 0, 1, 8, 30)
          })
            .onChange((v: TimePickerResult) => {
              this.addCourseStartTime = String(v.hour || 8).padStart(2, '0') + ':' + String(v.minute || 0).padStart(2, '0');
            })
            .layoutWeight(1)
          Text('—').fontSize(16).fontColor(ThemeColors.textSecondary)
          TimePicker({
            selected: this.addCourseEndTime.length > 0 ? this.parseTime(this.addCourseEndTime) : new Date(2026, 0, 1, 9, 15)
          })
            .onChange((v: TimePickerResult) => {
              this.addCourseEndTime = String(v.hour || 9).padStart(2, '0') + ':' + String(v.minute || 0).padStart(2, '0');
            })
            .layoutWeight(1)
        }.width('100%').height(56)
      }.width('100%')
    }
  }

  // ===== 添加弹窗：考试表单 =====
  @Builder examForm() {
    Row() {
      Text('名称').fontSize(14).fontColor(ThemeColors.textSecondary).width(64)
      TextInput({ placeholder: '考试名称（必填）', text: this.addCourseName })
        .onChange((v: string) => { this.addCourseName = v; })
        .layoutWeight(1).backgroundColor(ThemeColors.bgInput).borderRadius(8)
    }.width('100%')
    Column() {
      Text('日期').fontSize(14).fontColor(ThemeColors.textSecondary).width('100%').margin({ bottom: 4 })
      DatePicker({
        start: (() => { const n = new Date(); return new Date(n.getFullYear() - 1, n.getMonth(), 1); })(),
        end: (() => { const n = new Date(); return new Date(n.getFullYear() + 1, 11, 31); })(),
        selected: this.addExamDate.length > 0 ? new Date(this.addExamDate) : new Date()
      })
        .onChange((v: DatePickerResult) => {
          const y = v.year || 2026;
          const m = (v.month != null ? v.month : 0) + 1;
          const d = v.day || 1;
          this.addExamDate = String(y) + '-' + String(m).padStart(2, '0') + '-' + String(d).padStart(2, '0');
          this.addCourseDay = new Date(y, (v.month != null ? v.month : 0), d).getDay() || 7;
        })
        .width('100%')
    }.width('100%')
    Column() {
      Text('时间').fontSize(14).fontColor(ThemeColors.textSecondary).width('100%').margin({ bottom: 4 })
      Row({ space: 10 }) {
        TimePicker({
          selected: this.addExamTimeStart.length > 0 ? this.parseTime(this.addExamTimeStart) : new Date(2026, 0, 1, 8, 30)
        })
          .onChange((v: TimePickerResult) => {
            this.addExamTimeStart = String(v.hour || 8).padStart(2, '0') + ':' + String(v.minute || 0).padStart(2, '0');
          })
          .layoutWeight(1)
        Text('—').fontSize(16).fontColor(ThemeColors.textSecondary)
        TimePicker({
          selected: this.addExamTimeEnd.length > 0 ? this.parseTime(this.addExamTimeEnd) : new Date(2026, 0, 1, 10, 30)
        })
          .onChange((v: TimePickerResult) => {
            this.addExamTimeEnd = String(v.hour || 10).padStart(2, '0') + ':' + String(v.minute || 0).padStart(2, '0');
          })
          .layoutWeight(1)
      }.width('100%').height(56)
    }.width('100%')
    Row() {
      Text('考场').fontSize(14).fontColor(ThemeColors.textSecondary).width(64)
      TextInput({ placeholder: '考场/教室（选填）', text: this.addCourseClassroom })
        .onChange((v: string) => { this.addCourseClassroom = v; })
        .layoutWeight(1).backgroundColor(ThemeColors.bgInput).borderRadius(8)
    }.width('100%')
    Row() {
      Text('座位').fontSize(14).fontColor(ThemeColors.textSecondary).width(64)
      TextInput({ placeholder: '座位号（选填）', text: this.addExamSeat })
        .onChange((v: string) => { this.addExamSeat = v; })
        .layoutWeight(1).backgroundColor(ThemeColors.bgInput).borderRadius(8)
    }.width('100%')
  }

  @Builder customTitle() {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(Color.White)
          .draggable(false)
      }
      .height(40).width(40)
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.pageInfo.pop(); })

      Text('课程表')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(AccentColors.textContrast)
        .layoutWeight(1)
        .margin({ left: 4 })

      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.ic_public_more'))
          .height(22)
          .width(22)
          .fillColor(Color.White)
          .draggable(false)
      }
      .height(40)
      .width(40)
      .bindMenu(this.buildClassTableMenu(), menuOptions())
    }
    .height(52 + this.statusBarHeight)
    .width('100%')
    .padding({ left: 12, right: 12, top: this.statusBarHeight })
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
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.changeWeek(this.currentWeek - 1); })

      Text(this.getWeekRangeLabel()).fontSize(15)
        .fontColor(ThemeColors.isDark ? '#64B5F6' :
          ThemeColors.textForAccent(AppStorage.get('accent_color') as string ?? '#2979FF'))
        .fontWeight(FontWeight.Medium)
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
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.changeWeek(this.currentWeek + 1); })

      if (this.calendarImportMsg.length > 0) {
        Text(this.calendarImportMsg).fontSize(10).fontColor(ThemeColors.textSecondary).maxLines(1)
      }
    }.width('100%').height(40).justifyContent(FlexAlign.Center).padding({ left: 16, right: 16 })
      .backgroundColor(ThemeColors.isDark ? '#1A1A1C' : '#F8F9FA')
      .borderRadius(8)
  }

  @Builder buildClassTableMenu() {
    Menu() {
      MenuItem({ content: '手动添加日程', startIcon: $r('app.media.ic_public_add_norm') })
        .hoverEffect(HoverEffect.Auto).onClick(() => {
          this.savedDetailDay = -1;
          this.savedDetailSection = -1;
          this.refreshWeekIndex();
          this.showAddCourseDialog = true;
        })
      MenuItem({ content: '课程变更', startIcon: $r('app.media.ic_public_rotate') })
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.loadClassChanges(); })
      MenuItem({ content: '未安排课程', startIcon: $r('app.media.ic_public_albums') })
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.loadUnscheduledCourses(); })
      MenuItem({ content: '刷新课表', startIcon: $r('app.media.refresh') })
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.loadTable(true); })
    }
  }

  // 统一颜色获取方法：考试→红色系，实验/课程→蓝色系（实验与课程配色一致）
  private getCellColor(cell: ClassCell): string {
    if (cell.isExam) {
      const arr: string[] = ThemeColors.isDark ? EXAM_COLORS_DK : EXAM_COLORS;
      return arr[cell.colorIndex % arr.length];
    }
    // 实验与普通课程使用同一套蓝色系配色
    const arr: string[] = ThemeColors.isDark ? CLASS_COLORS_DK : CLASS_COLORS;
    return arr[cell.colorIndex % arr.length];
  }

  // 卡片描边色：取比背景亮一档的同色系（参考 Flutter Traintime），让方块边缘有“卡片感”
  private getCellBorderColor(cell: ClassCell): string {
    if (cell.isExam) {
      return EXAM_COLORS_BD[cell.colorIndex % EXAM_COLORS_BD.length];
    }
    return CLASS_COLORS_BD[cell.colorIndex % CLASS_COLORS_BD.length];
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
  private showActionToast(msg: string): void {
    this.actionToast = msg;
    this.actionToastTimer++;
    const tid: number = this.actionToastTimer;
    this.later(() => {
      if (this.actionToastTimer === tid) { this.actionToast = ''; }
    }, 2000);
  }

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
  private getCurrentWeekConflictCells(day: number, section: number, week?: number): ClassCell[] {
    const result: ClassCell[] = [];
    if (!this.classGrid[day]) return result;
    const w: number = week !== undefined ? week : this.currentWeek;

    // 考试卡片（section=0）
    if (section === 0) {
      const examSlot = this.classGrid[day][0];
      if (examSlot) {
        for (const cell of examSlot) {
          if (cell.isExam && cell.weekList[w - 1]) {
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
        if (cell.weekList[w - 1] &&
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
    if (targetWeek < 1 || targetWeek > this.maxWeek || targetWeek === this.currentWeek) return;
    this.swiperController.changeIndex(targetWeek - 1, true);
  }

  // Swiper 数据源更新
  private updateWeekList(): void {
    const arr: number[] = [];
    for (let w = 1; w <= this.maxWeek; w++) arr.push(w);
    this._weekList = arr;
  }

  private recalcMaxWeek(): void {
    // 重新计算真实最大周：所有课程（普通/实验/考试/自定义）weekList 中最后为 true 的周次（0-indexed → 周次 = index+1）
    let realMax = 0;
    for (let d = 1; d <= DAY_COUNT; d++) {
      for (let s = 0; s <= SECTION_COUNT; s++) {
        const arr = this.classGrid[d]?.[s];
        if (!arr) continue;
        for (const c of arr) {
          for (let i = 0; i < c.weekList.length; i++) {
            if (c.weekList[i] && i + 1 > realMax) realMax = i + 1;
          }
        }
      }
    }
    // 对齐学期标准周数（西电秋/春季 20 周），即使数据 SKZC 缺失末周也显示标准周数，与 Flutter 一致
    const std = SemesterUtil.getStandardWeekCount(this.semesterCode);
    if (realMax > 0) this.maxWeek = Math.max(realMax, std);
    else this.maxWeek = Math.max(this.maxWeek, std);
  }

  private buildCellCache(): void {
    // 重新计算真实最大周（含考试），避免学期末 currentWeek 超过数据最后周
    this.recalcMaxWeek();
    // recalcMaxWeek() 可能抬高 maxWeek（例如考试周晚于课程末周），
    // 必须同步刷新 Swiper 的页数数据源，否则 _weekList 偏短、后面的周次滑不过去
    this.updateWeekList();
    // 学期已结束（currentWeek 超过数据最后周）：钳制到最后一合法周，避免整周空白
    if (this.currentWeek > this.maxWeek) {
      this.currentWeek = this.maxWeek;
      this.termEnded = true;
    }
    if (this.currentWeek < 1) this.currentWeek = 1;
    // 全周次渲染缓存（1..maxWeek）。
    // 原实现只缓存当前周±1，于是每次切周都要重建缓存并 _gridVersion++；
    // 而 cell 的 ForEach key 含 _gridVersion —— key 全部失效 → 整张课表销毁重建 →
    // 滑动切换时主线程被打满，Swiper 的跟手动画被掐断（表现为"能切但直接跳变、不跟手"）。
    // 改为全周预建后，切周只需改 currentWeek，缓存与 key 都不变，滑动期零重建。
    const newCache: Map<string, ClassCell[]> = new Map();
    for (let w = 1; w <= this.maxWeek; w++) {
      for (let d = 1; d <= DAY_COUNT; d++) {
        const cells: ClassCell[] = this.getCellsForDay(d, w);
        // 只存非空格，减少 Map 体积（渲染侧已用 ?? [] 兜底）
        if (cells.length > 0) {
          newCache.set(`${w}_${d}`, cells);
        }
      }
    }
    this._renderCache = newCache;
    // 仅在数据真正变更时递增；切周不再触发，保证 cell 组件可复用
    this._gridVersion++;
  }

  @Builder buildClassGrid() {
    Column() {
      // ===== 固定表头行（不随课表滚动）=====
      Row() {
        // 左上角空白格
        Column() {}
        .width(28).height(44)
        .backgroundColor(ThemeColors.bgCard)

        // 周几表头（跟随 currentWeek 显示日期）
        Row() {
          ForEach(DAY_NAMES, (name: string, di: number) => {
            Column() {
              Text(name).fontSize(13)
                .fontColor(ThemeColors.textPrimary)
                .fontWeight(di === this._todayDay - 1 && this.currentWeek === this.getRealCurrentWeek() ? FontWeight.Bold : FontWeight.Medium)
              Text(this.getDateStr(this.currentWeek, di + 1)).fontSize(10)
                .fontColor(ThemeColors.textSecondary)
              // 今天指示线
              if (di === this._todayDay - 1 && this.currentWeek === this.getRealCurrentWeek()) {
                Row().width(20).height(3).borderRadius(2)
                  .backgroundColor(AppStorage.get('accent_color') as string ?? '#2979FF')
                  .margin({ top: 2 })
              }
            }.layoutWeight(1).height(44)
            .justifyContent(FlexAlign.Center)
          }, (name: string, di: number) => `hdr_${di}`)
        }.layoutWeight(1).height(44)
        .backgroundColor(ThemeColors.bgCard)
      }.width('100%')

      // ===== 可滚动区域（时间列 + 网格）=====
    Scroll() {
      Column() {
        Row() {
          // Left: time labels
          Column() {
            ForEach([1, 2, 3, 4], (section: number) => {
              Column() {
                Text(String(section)).fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Medium)
                Text(SECTION_TIMES[section].split('-')[0] || '').fontSize(9).fontColor(ThemeColors.textHint).margin({ top: 1 })
                Text(SECTION_TIMES[section].split('-')[1] || '').fontSize(9).fontColor(ThemeColors.textHint).margin({ top: 1 })
              }.width(28).height(this.ROW_HEIGHT).justifyContent(FlexAlign.Center)
            }, (section: number) => `sec_${section}`)
            Row() { Text('午休').fontSize(9).fontColor(ThemeColors.textHint) }
            .width(28).height(BREAK_HEIGHT).justifyContent(FlexAlign.Center)
            ForEach([5, 6, 7, 8], (section: number) => {
              Column() {
                Text(String(section)).fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Medium)
                Text(SECTION_TIMES[section].split('-')[0] || '').fontSize(9).fontColor(ThemeColors.textHint).margin({ top: 1 })
                Text(SECTION_TIMES[section].split('-')[1] || '').fontSize(9).fontColor(ThemeColors.textHint).margin({ top: 1 })
              }.width(28).height(this.ROW_HEIGHT).justifyContent(FlexAlign.Center)
            }, (section: number) => `sec_${section}`)
            Row() { Text('放学').fontSize(9).fontColor(ThemeColors.textHint) }
            .width(28).height(BREAK_HEIGHT).justifyContent(FlexAlign.Center)
            ForEach([9, 10, 11], (section: number) => {
              Column() {
                Text(String(section)).fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Medium)
                Text(SECTION_TIMES[section].split('-')[0] || '').fontSize(9).fontColor(ThemeColors.textHint).margin({ top: 1 })
                Text(SECTION_TIMES[section].split('-')[1] || '').fontSize(9).fontColor(ThemeColors.textHint).margin({ top: 1 })
              }.width(28).height(this.ROW_HEIGHT).justifyContent(FlexAlign.Center)
            }, (section: number) => `sec_${section}`)
            Row().width(28).height(24)
          }.width(28)
          .backgroundColor(ThemeColors.bgCard)

          // Right: Swiper (GPU-native horizontal scroll, one page per week)
          Swiper(this.swiperController) {
            ForEach(this._weekList, (week: number, idx: number) => {
              Column() {
                // Grid content for this week
                Stack() {

                  Column() {
                    ForEach([1, 2, 3, 4], (section: number) => {
                      Row() {
                        ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                          Column().layoutWeight(1).height(this.ROW_HEIGHT)
                            .hoverEffect(HoverEffect.Auto).onClick(() => { this.showCellDetail(day, section); })
                        }, (day: number) => `grid_${day}`)
                      }.width('100%')
                    }, (section: number) => `sec_${section}`)
                    Row() {
                      ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                        Column().layoutWeight(1).height(BREAK_HEIGHT)
                      }, (day: number) => `brk1_${day}`)
                    }.width('100%')
                    ForEach([5, 6, 7, 8], (section: number) => {
                      Row() {
                        ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                          Column().layoutWeight(1).height(this.ROW_HEIGHT)
                            .hoverEffect(HoverEffect.Auto).onClick(() => { this.showCellDetail(day, section); })
                        }, (day: number) => `grid_${day}`)
                      }.width('100%')
                    }, (section: number) => `sec_${section}`)
                    Row() {
                      ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                        Column().layoutWeight(1).height(BREAK_HEIGHT)
                      }, (day: number) => `brk2_${day}`)
                    }.width('100%')
                    ForEach([9, 10, 11], (section: number) => {
                      Row() {
                        ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                          Column().layoutWeight(1).height(this.ROW_HEIGHT)
                            .hoverEffect(HoverEffect.Auto).onClick(() => { this.showCellDetail(day, section); })
                        }, (day: number) => `grid_${day}`)
                      }.width('100%')
                    }, (section: number) => `sec_${section}`)
                    Row().width('100%').height(24)
                  }.width('100%')

                  // Cells for this week (read from render cache, not real-time computation)
                  ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
                    ForEach(this._renderCache.get(`${week}_${day}`) ?? [], (cell: ClassCell) => {
                      Column() {
                        Text(cell.name).fontSize(12)
                          .fontColor('#FFFFFF')
                          .fontWeight(FontWeight.Medium).maxLines(4)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        // 教室+老师合并显示（普通课）；考试格：考场另起一行显示座位号，与普通课同构
                        if (cell.isExam && (cell.classroom || cell.examSeat)) {
                          Text((cell.classroom ? cell.classroom : '') + (cell.examSeat ? '\n' + cell.examSeat : ''))
                            .fontSize(9)
                            .fontColor('#FFFFFFCC')
                            .margin({ top: 2 })
                        } else if (cell.classroom || cell.teacher) {
                          Text((cell.classroom ? cell.classroom : '') + (cell.classroom && cell.teacher ? '\n' : '') + (cell.teacher ? cell.teacher : ''))
                            .fontSize(9)
                            .fontColor('#FFFFFFCC')
                            .margin({ top: 2 })
                        }
                        if (cell.day === this._todayDay &&
                            week === this.getRealCurrentWeek() &&
                            cell.weekList.length > (week - 1) && cell.weekList[week - 1]) {
                          if (cell.isExam) {
                            if (this.getExamStatus(cell) === 1) {
                              Text('进行中').fontSize(7).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                                .backgroundColor('#4CAF50CC').borderRadius(3)
                                .padding({ left: 4, right: 4, top: 1, bottom: 1 }).margin({ top: 2 })
                            } else if (this.getExamStatus(cell) === -1) {
                              Text('已结束').fontSize(7).fontColor('#FFFFFF88').margin({ top: 2 })
                            }
                          } else {
                            if ((this._cellStatusesMap.get(`${cell.startSection}_${cell.endSection}`) ?? 0) === 1) {
                              Text('进行中').fontSize(7).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                                .backgroundColor('#4CAF50CC').borderRadius(3)
                                .padding({ left: 4, right: 4, top: 1, bottom: 1 }).margin({ top: 2 })
                            } else if ((this._cellStatusesMap.get(`${cell.startSection}_${cell.endSection}`) ?? 0) === -1) {
                              Text('已结束').fontSize(7).fontColor('#FFFFFF88').margin({ top: 2 })
                            }
                          }
                        }
                        if (!cell.isExam && this.getCurrentWeekConflictCells(day, cell.startSection, week).length > 1) {
                          Text('⚠️').fontSize(8).fontColor('#FFFFFF').position({ top: 2, right: 2 })
                        }
                      }.width('100%').height('100%').padding({ left: 4, right: 4, top: 4, bottom: 4 })
                      .backgroundColor(this.getCellColor(cell)).borderRadius(8)
                      .opacity(cell.day === this._todayDay &&
                            week === this.getRealCurrentWeek() &&
                        cell.weekList.length > (week - 1) && cell.weekList[week - 1] &&
                          (cell.isExam ? this.getExamStatus(cell) === -1 :
                          this._cellStatusesMap.get(`${cell.startSection}_${cell.endSection}`) === -1) ? 0.6 : 1)
                      .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start)
                      .position({
                        x: `${(day - 1) * (100 / 7) + (cell.isExam && cell.examColumnSpan > 1 ? cell.examColumnIndex * (100 / 7 / cell.examColumnSpan) : 0) + CELL_GAP / 2}%`,
                        y: cell.isExam ? cell.examPixelY : this.getSectionY(cell.startSection) + CELL_GAP_V
                      })
                      .size({
                        width: `${cell.isExam && cell.examColumnSpan > 1 ? (100 / 7 / cell.examColumnSpan - CELL_GAP) : (100 / 7 - CELL_GAP)}%`,
                        height: cell.isExam ? cell.examPixelH : this.getSectionSpanHeight(cell.startSection, cell.endSection) - CELL_GAP_V
                      })
                      .border({
                        width: 2,
                        color: (cell.day === this._todayDay && week === this.getRealCurrentWeek() &&
                          cell.weekList.length > (week - 1) && cell.weekList[week - 1] &&
                          (cell.isExam ? this.getExamStatus(cell) === 1 :
                            (this._cellStatusesMap.get(`${cell.startSection}_${cell.endSection}`) ?? 0) === 1))
                          ? (AppStorage.get('accent_color') as string ?? '#2979FF')
                          : this.getCellBorderColor(cell)
                      })
                      .hoverEffect(HoverEffect.Auto).onClick(() => {
                        if (cell.isExam) {
                          this.currentConflictCells = [cell];
                          this.showDetailDialog = true;
                          this.cardScale = 0.85; this.cardOpacity = 0; this.maskOpacity = 0;
                          animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
                            this.cardScale = 1; this.cardOpacity = 1; this.maskOpacity = 0.7;
                          });
                        } else {
                          this.showCellDetail(day, cell.startSection);
                        }
                      })
                    }, (cell: ClassCell) => `cell_${week}_${day}_${cell.startSection}_${cell.kch}_${cell.customId}_${this._gridVersion}`)
                  }, (day: number) => `day_${day}`)
                }.width('100%')
              }.width('100%')
            }, (week: number) => `week_${week}`)
          }
          .index(this.currentWeek - 1)
          .cachedCount(1)
          .indicator(false)
          .loop(false)
          // 与主页/睿思等页的 SegmentTab 对齐：边缘弹性回弹，手感一致
          .effectMode(EdgeEffect.Spring)
          .onChange((index: number) => {
            // 只切换周次，不重建缓存：渲染缓存已在数据加载时按全周预建，
            // 此处若再调 buildCellCache() 会令 _gridVersion 变化 → 整表销毁重建 → 滑动掉帧
            this.currentWeek = index + 1;
          })
          .layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      }.width('100%')
    }.scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto).layoutWeight(1)
    // 课表主体纵向滚动：滑到顶部/底部橡皮筋回弹
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor(this.classBgShow && this.classBgPath.length > 0 ? Color.Transparent : (ThemeColors.isDark ? '#0F0F11' : '#F3F3F3'))
    }
  }

  // 网格显示逻辑：正确处理所有重叠冲突
  // 优先级：考试 > 实验 > 普通课程；同类型下跨度大的优先
  private getCellsForDay(day: number, week?: number): ClassCell[] {
    const w: number = week !== undefined ? week : this.currentWeek;
    const cells: ClassCell[] = [];
    if (!this.classGrid[day]) return cells;

    // 1. 先处理考试卡片（像素级定位，不会和普通课程冲突）
    const examSlot = this.classGrid[day][0];
    if (examSlot && examSlot.length > 0) {
      const allExams: ClassCell[] = examSlot.filter((c: ClassCell) => c.isExam);
      const examCells = allExams.filter((c: ClassCell) => c.weekList[w - 1]);
      // 检测同一天多个考试是否时间重叠，重叠时分列显示
      if (examCells.length > 1) {
        examCells.sort((a, b) => a.examPixelY - b.examPixelY);
        const cols: ClassCell[][] = [];
        for (const ec of examCells) {
          let placed: boolean = false;
          for (let ci = 0; ci < cols.length; ci++) {
            const lastInCol: ClassCell = cols[ci][cols[ci].length - 1];
            if (ec.examPixelY >= (lastInCol.examPixelY + lastInCol.examPixelH)) {
              cols[ci].push(ec);
              placed = true;
              break;
            }
          }
          if (!placed) {
            cols.push([ec]);
          }
        }
        const span: number = cols.length;
        for (let ci = 0; ci < cols.length; ci++) {
          for (const ec of cols[ci]) {
            ec.examColumnSpan = span;
            ec.examColumnIndex = ci;
          }
        }
      }
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
      cell.weekList[w - 1] && cell.startSection === s && !cell.isExam
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

  // 计算当前课表数据的快照签名（课表+实验+考试）
  private computeCalendarSnapshot(): string {
    const classCount: number = this.countClassGridCourses();
    const rawLen: number = this.lastRenderedRaw ? this.lastRenderedRaw.length : 0;
    let expCount: number = 0;
    let examCount: number = 0;
    for (let d = 1; d <= DAY_COUNT; d++) {
      for (let s = 0; s <= SECTION_COUNT; s++) {
        const cells = this.classGrid[d][s];
        if (!cells) continue;
        for (let ci = 0; ci < cells.length; ci++) {
          if (cells[ci].isExperiment) expCount++;
          if (cells[ci].isExam) examCount++;
        }
      }
    }
    return this.semesterCode + '|' + String(classCount) + '|' + String(rawLen) + '|' + String(expCount) + '|' + String(examCount);
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
      let failCount: number = 0;
      try {
        const config: calendarManager.CalendarConfig = {
          enableReminder: true,
          color: '#4A90D9'
        };
        await calendar.setConfig(config);
      } catch (cfgErr) {
        failCount++;
        console.warn('[ClassTablePage] calendar setConfig failed: ' + String(cfgErr));
      }

      const startDate: Date = SemesterUtil.getSemesterStartDate(this.semesterCode);
      const swift: number = PreferenceUtil.getNumber('week_swift', 0);
      const dayOfWeek = startDate.getDay();
      const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
      const monday = new Date(startDate);
      monday.setDate(startDate.getDate() + mondayOffset + swift * 7);

      // 5. 获取日历中已有事件 → 签名映射（标题|startTime）
      const existingMap: Record<string, number> = {};
      try {
        const existingEvents: calendarManager.Event[] = await calendar.getEvents();
        for (let ei = 0; ei < existingEvents.length; ei++) {
          const evt: calendarManager.Event = existingEvents[ei];
          if (evt.id !== undefined && evt.title && evt.startTime) {
            const sig: string = evt.title + '|' + String(evt.startTime);
            existingMap[sig] = evt.id;
          }
        }
      } catch (getErr) {
        failCount++;
        console.warn('[ClassTablePage] calendar getEvents failed: ' + String(getErr));
      }

      // 6. 遍历课程，增量导入：跳过已有的，只添加新的
      const neededSigs: Record<string, boolean> = {};
      let newCount: number = 0;
      let skipCount: number = 0;

      for (let d = 1; d <= DAY_COUNT; d++) {
        for (let s = 1; s <= SECTION_COUNT; s++) {
          const cells = this.classGrid[d][s];
          for (let ci = 0; ci < cells.length; ci++) {
            const cell = cells[ci];
            if (cell.isExam) continue;
            if (cell.startSection !== s) continue;

            for (let w = 0; w < cell.weekList.length; w++) {
              if (!cell.weekList[w]) continue;
              const weekNum = w + 1;

              const eventDate = new Date(monday);
              eventDate.setDate(monday.getDate() + (weekNum - 1) * 7 + (d - 1));

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

              const title = (cell.isExperiment ? '🧪 ' : '') + cell.name;
              const desc = (cell.classroom ? '教室: ' + cell.classroom : '') +
                (cell.teacher ? (cell.classroom ? ' | ' : '') + '教师: ' + cell.teacher : '');

              // 签名 = 标题|开始毫秒数，唯一标识一条日程
              const sig: string = title + '|' + String(startTime.getTime());
              neededSigs[sig] = true;

              if (existingMap[sig] !== undefined) {
                skipCount++;
                continue; // 已存在，跳过
              }

              let event: calendarManager.Event;
              if (this.reminderMode === 2) {
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
                newCount++;
              } catch (addErr) {
                failCount++;
                console.warn('[ClassTablePage] calendar addEvent(course) failed: ' + String(addErr));
              }
            }
          }
        }
      }

      // 6b. 遍历考试卡片（存储在 classGrid[day][0]）
      for (let d = 1; d <= DAY_COUNT; d++) {
        const examSlot = this.classGrid[d][0];
        if (!examSlot || examSlot.length === 0) continue;
        for (let ci = 0; ci < examSlot.length; ci++) {
          const cell = examSlot[ci];
          if (!cell.isExam) continue;
          // examDate: "2026-04-22"
          if (!cell.examDate) continue;
          // 解析考试时间：examTimeDesc = "13:00-15:00 星期三"
          const timePart: string = (cell.examTimeDesc.split(' ')[0]) || '';
          if (!timePart.includes('-')) continue;
          const tParts: string[] = timePart.split('-');
          if (tParts.length < 2) continue;
          const sp: string[] = tParts[0].split(':');
          const ep: string[] = tParts[1].split(':');
          if (sp.length < 2 || ep.length < 2) continue;
          const dateParts: string[] = cell.examDate.split('-');
          if (dateParts.length < 3) continue;
          const examStart: Date = new Date(parseInt(dateParts[0]), parseInt(dateParts[1]) - 1,
            parseInt(dateParts[2]), parseInt(sp[0]), parseInt(sp[1]), 0);
          const examEnd: Date = new Date(parseInt(dateParts[0]), parseInt(dateParts[1]) - 1,
            parseInt(dateParts[2]), parseInt(ep[0]), parseInt(ep[1]), 0);
          const title: string = '📝 ' + cell.name;
          const desc: string = (cell.classroom ? '地点: ' + cell.classroom : '') +
            (cell.examSeat ? ' 座位: ' + cell.examSeat : '');
          const sig: string = title + '|' + String(examStart.getTime());
          neededSigs[sig] = true;
          if (existingMap[sig] !== undefined) {
            skipCount++;
            continue;
          }
          let event: calendarManager.Event;
          if (this.reminderMode === 2) {
            event = {
              type: calendarManager.EventType.NORMAL,
              title: title,
              startTime: examStart.getTime(),
              endTime: examEnd.getTime(),
              description: desc
            };
          } else {
            event = {
              type: calendarManager.EventType.NORMAL,
              title: title,
              startTime: examStart.getTime(),
              endTime: examEnd.getTime(),
              description: desc,
              reminderTime: [this.reminderMinutes]
            };
          }
          try {
            await calendar.addEvent(event);
            newCount++;
          } catch (addErr) {
            failCount++;
            console.warn('[ClassTablePage] calendar addEvent(exam) failed: ' + String(addErr));
          }
        }
      }

      // 7. 删除日历中不再需要的课程事件（课程被删除或时间变更）
      let delCount: number = 0;
      const existingSigs: string[] = Object.keys(existingMap);
      for (let si = 0; si < existingSigs.length; si++) {
        const sig: string = existingSigs[si];
        if (!neededSigs[sig]) {
          try {
            await calendar.deleteEvent(existingMap[sig]);
            delCount++;
          } catch (delErr) {
            failCount++;
            console.warn('[ClassTablePage] calendar deleteEvent failed: ' + String(delErr));
          }
        }
      }

      let msg: string = '';
      if (newCount > 0) msg += '新增 ' + newCount + ' 条';
      if (delCount > 0) msg += (msg.length > 0 ? '，删除 ' : '删除 ') + delCount + ' 条';
      if (skipCount > 0) msg += (msg.length > 0 ? '，跳过 ' : '跳过 ') + skipCount + ' 条';
      if (failCount > 0) msg += (msg.length > 0 ? '，' : '') + failCount + ' 条失败（权限受限或日历限制）';
      if (msg.length === 0) msg = '课程无变化';
      this.calendarImportMsg = msg;
      // 标记已绑定日历，保存当前 snapshot
      PreferenceUtil.putBool('calendar_bound', true);
      PreferenceUtil.putString('calendar_snapshot', this.computeCalendarSnapshot());
    } catch (e) {
      this.calendarImportMsg = '导入失败: ' + String(e);
    }
    this.calendarImporting = false;
  }

  // 手动添加课程到classGrid并保存
  private showAddToast(msg: string): void {
    this.addFormToast = msg;
    this.later(() => {
      this.addFormToast = '';
    }, 1500);
  }

  // 加载未安排课程
  async loadUnscheduledCourses(): Promise<void> {
    this.unscheduledList = [];
    this.unscheduledMsg = '';
    this.unscheduledLoading = true;
    this.showUnscheduledDialog = true;
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.unscheduledOpacity = 1; this.unscheduledTranslate = 0; });
    try {
      const sid: string = PreferenceUtil.getString('ids_account');
      // 研究生走 yjspt 的 xswsckbkc.do（对齐 Flutter），本科生走 ehall 的 cxxsllsywpk.do
      if (PreferenceUtil.getBool('role')) {
        const raw: string = await this.classSvc.getUnscheduledCoursesYjspt(this.semesterCode, sid);
        this.unscheduledList = ClassService.parseUnscheduledCoursesYjspt(raw);
      } else {
        const raw: string = await this.classSvc.getUnscheduledCoursesEhall(this.semesterCode, sid);
        this.unscheduledList = ClassService.parseUnscheduledCourses(raw);
      }
      if (this.unscheduledList.length === 0) {
        this.unscheduledMsg = '暂无非排期课程';
      }
    } catch (_) {
      this.unscheduledMsg = '加载失败，请重试';
    }
    this.unscheduledLoading = false;
  }

  closeUnscheduledDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.unscheduledOpacity = 0; this.unscheduledTranslate = 30; });
    this.later(() => { this.showUnscheduledDialog = false; }, 200);
  }

  // 加载课程变更
  async loadClassChanges(): Promise<void> {
    this.classChangesList = [];
    this.classChangesMsg = '';
    this.classChangesLoading = true;
    this.showClassChangesDialog = true;
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.classChangesOpacity = 1; this.classChangesTranslate = 0; });
    try {
      const raw: string = await this.classSvc.getClassChangesEhall(this.semesterCode);
      this.classChangesList = ClassService.parseClassChanges(raw);
      if (this.classChangesList.length === 0) {
        this.classChangesMsg = '暂无课程变更信息';
      }
    } catch (_) {
      this.classChangesMsg = '加载失败，请重试';
    }
    this.classChangesLoading = false;
  }

  closeClassChangesDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.classChangesOpacity = 0; this.classChangesTranslate = 30; });
    this.later(() => { this.showClassChangesDialog = false; }, 200);
  }

  private async addCustomCourse(): Promise<void> {
    if (this.addCourseName.length === 0) {
      this.showAddToast(this.addCourseType === 1 ? '请输入考试名称' : '请输入名称');
      return;
    }

    if (this.addCourseType === 1) {
      // 考试验证
      if (this.addExamDate.length === 0) {
        this.showAddToast('请选择考试日期');
        return;
      }
      if (this.addExamTimeStart.length === 0 || this.addExamTimeEnd.length === 0) {
        this.showAddToast('请选择考试时间');
        return;
      }
      if (this.addExamTimeStart >= this.addExamTimeEnd) {
        this.showAddToast('开始时间不能晚于或等于结束时间');
        return;
      }
    } else if (this.addCourseType === 0) {
      // 课程验证（节次）
      if (this.addCourseStartSection > this.addCourseEndSection) {
        this.showAddToast('开始节次不能大于结束节次');
        return;
      }
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
    } else {
      // 实验验证（时间 HH:MM）
      const startT: string = this.addCourseStartTime.trim();
      const endT: string = this.addCourseEndTime.trim();
      const timeRe = /^(\d{1,2}):(\d{2})$/;
      if (!timeRe.test(startT) || !timeRe.test(endT)) {
        this.showAddToast('请输入正确的时间格式，如 08:30');
        return;
      }
      if (startT >= endT) {
        this.showAddToast('开始时间不能晚于或等于结束时间');
        return;
      }
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
    }

    const cell = new ClassCell();
    cell.name = this.addCourseName;
    cell.classroom = this.addCourseClassroom;
    cell.isCustom = true;

    if (this.addCourseType === 1) {
      // 考试
      cell.isExam = true;
      cell.isExperiment = false;
      cell.teacher = '';
      cell.day = this.addCourseDay; // DatePicker onChange 已自动计算
      cell.examDate = this.addExamDate;
      cell.examTimeDesc = this.addExamTimeStart + '-' + this.addExamTimeEnd;
      cell.examSeat = this.addExamSeat;
      // 考试映射到像素坐标（不在节次网格里，用 timeToY 定位）
      const startY: number = this.timeToY(this.addExamTimeStart);
      const endY: number = this.timeToY(this.addExamTimeEnd);
      cell.examPixelY = startY;
      cell.examPixelH = Math.max(endY - startY, 20);
      cell.startSection = 0;
      cell.endSection = 0;
      cell.weekList = [];
      // 用节次级别的 Y 来复用渲染逻辑：把考试放进 startSection 对应位置
      for (let s = 1; s <= 11; s++) {
        const secStartY: number = this.getSectionY(s);
        if (secStartY <= startY && startY < secStartY + this.ROW_HEIGHT) {
          cell.startSection = s;
          break;
        }
      }
      for (let s = cell.startSection; s <= 11; s++) {
        const secEndY: number = this.getSectionY(s) + this.ROW_HEIGHT;
        if (endY <= secEndY) {
          cell.endSection = s;
          break;
        }
      }
      if (cell.endSection === 0) cell.endSection = cell.startSection;
      cell.weekDesc = this.addExamDate;
      cell.colorIndex = Math.floor(Math.random() * (ThemeColors.isDark ? EXAM_COLORS_DK : EXAM_COLORS).length);
    } else if (this.addCourseType === 0) {
      // 课程：节次 → 时间
      cell.isExam = false;
      cell.isExperiment = false;
      cell.teacher = this.addCourseTeacher;
      cell.day = this.addCourseDay;
      cell.startSection = this.addCourseStartSection;
      cell.endSection = this.addCourseEndSection;
      cell.startTime = this.addCourseStartSection > 0 && this.addCourseStartSection <= 11 ? SEC_START[this.addCourseStartSection] : '';
      cell.endTime = this.addCourseEndSection > 0 && this.addCourseEndSection <= 11 ? SEC_END[this.addCourseEndSection] : '';
      cell.weekList = this.addCourseWeekList;
      cell.weekDesc = this.formatWeekDesc(this.addCourseWeekList);
      cell.examDate = '';
      cell.examTimeDesc = '';
      cell.examSeat = '';
      cell.examPixelY = 0;
      cell.examPixelH = 0;
      cell.colorIndex = Math.floor(Math.random() * CLASS_COLORS.length);
    } else {
      // 实验：时间 → 节次
      cell.isExam = false;
      cell.isExperiment = true;
      cell.teacher = this.addCourseTeacher;
      cell.day = this.addCourseDay;
      cell.startTime = this.addCourseStartTime;
      cell.endTime = this.addCourseEndTime;
      cell.startSection = this.timeToSec(this.addCourseStartTime);
      cell.endSection = this.timeToSec(this.addCourseEndTime, true);
      cell.weekList = this.addCourseWeekList;
      cell.weekDesc = this.formatWeekDesc(this.addCourseWeekList);
      cell.examDate = '';
      cell.examTimeDesc = '';
      cell.examSeat = '';
      cell.examPixelY = 0;
      cell.examPixelH = 0;
      cell.colorIndex = Math.floor(Math.random() * CLASS_COLORS.length);
      if (cell.startSection === 0) cell.startSection = 1;
      if (cell.endSection < cell.startSection) cell.endSection = cell.startSection;
    }

    // 生成唯一 ID（编辑时保留原 ID）
    const customId: string = (this.editingCustomIndex >= 0 && this.customList[this.editingCustomIndex] && this.customList[this.editingCustomIndex].id.length > 0)
      ? this.customList[this.editingCustomIndex].id
      : `${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    cell.customId = customId;

    if (this.editingCustomIndex >= 0) {
      this.customList[this.editingCustomIndex] = this.cellToItem(cell);
    } else {
      this.customList.push(this.cellToItem(cell));
    }
    await this.saveCustomList();
    await this.loadCustomCourses(this.classGrid);
    this.buildCellCache();
    this.saveClassGridSnapshot();

    const wasEditing: boolean = this.editingCustomIndex >= 0;
    this.showAddCourseDialog = false;
    this.resetAddCourseForm();
    this.showActionToast(wasEditing ? '✅ 已保存' : '✅ 已添加');
  }

  /** 解析 "HH:MM" 字符串为 Date */
  private parseTime(timeStr: string): Date {
    const parts = timeStr.split(':');
    const h = parseInt(parts[0]) || 8;
    const m = parseInt(parts[1]) || 30;
    return new Date(2026, 0, 1, h, m, 0);
  }

  // 保存自定义课程到本地文件

  /** 打开添加弹窗前预填默认值（DatePicker/TimePicker onChange 不触发初始值） */
  private initExamDefaults(): void {
    if (this.addCourseType === 1) {
      // 考试
      const now = new Date();
      if (this.addExamDate.length === 0) {
        const y = now.getFullYear();
        const m = now.getMonth() + 1;
        const d = now.getDate();
        this.addExamDate = String(y) + '-' + String(m).padStart(2, '0') + '-' + String(d).padStart(2, '0');
        this.addCourseDay = now.getDay() || 7;
      }
      if (this.addExamTimeStart.length === 0) this.addExamTimeStart = '08:30';
      if (this.addExamTimeEnd.length === 0) this.addExamTimeEnd = '10:30';
    } else if (this.addCourseType === 2) {
      // 实验：预填开始/结束时间
      if (this.addCourseStartTime.length === 0) this.addCourseStartTime = '08:30';
      if (this.addCourseEndTime.length === 0) this.addCourseEndTime = '09:15';
    }
  }

  // 重置添加课程表单
  private resetAddCourseForm(): void {
    this.addCourseType = 0;
    this.addCourseName = '';
    this.addCourseTeacher = '';
    this.addCourseClassroom = '';
    this.addCourseWeekList = [];
    this.editingCustomIndex = -1;
    this.addCourseDay = 0;
    this.addCourseStartSection = 0;
    this.addCourseEndSection = 0;
    this.addCourseStartTime = '';
    this.addCourseEndTime = '';
    this.addExamDate = '';
    this.addExamTimeStart = '';
    this.addExamTimeEnd = '';
    this.addExamSeat = '';
    this.addCourseSegSel = [0];
    this.refreshWeekIndex();
  }

  // 依据当前 maxWeek 刷新周次选择器的下标列表（稳定引用，避免 ForEach 每次重建）
  private refreshWeekIndex(): void {
    const arr: number[] = [];
    for (let i = 1; i <= this.maxWeek; i++) arr.push(i);
    this.weekIndexList = arr;
  }

  // 周次一键全选 / 清空
  private setAllWeeks(flag: boolean): void {
    const arr: boolean[] = [];
    for (let i = 0; i < this.maxWeek; i++) arr.push(flag);
    this.addCourseWeekList = arr;
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

  // 时间字符串→节次索引（1-11），找不到返回 1
  private timeToSec(time: string, isEnd: boolean = false): number {
    if (!time) return isEnd ? 11 : 1;
    const m = time.match(/^(\d{1,2}):(\d{2})$/);
    if (!m) return isEnd ? 11 : 1;
    const mins = parseInt(m[1]) * 60 + parseInt(m[2]);
    // 遍历 SEC_START/SEC_END 找匹配区间
    for (let s = 1; s <= 11; s++) {
      const sParts = SEC_START[s].split(':');
      const eParts = SEC_END[s].split(':');
      const sMins = parseInt(sParts[0]) * 60 + parseInt(sParts[1]);
      const eMins = parseInt(eParts[0]) * 60 + parseInt(eParts[1]);
      if (isEnd) {
        if (mins >= sMins && mins <= eMins + 5) return s;  // +5 容差
      } else {
        if (mins >= sMins - 5 && mins <= eMins) return s;
      }
    }
    return isEnd ? 11 : 1;
  }

  private getDayValue(): string {
    const v: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return this.addCourseDay > 0 && this.addCourseDay < v.length ? v[this.addCourseDay] : '请选择星期';
  }

  private getSectionValue(idx: number): string {
    return idx > 0 && idx <= 11 ? '第' + idx + '节' : '请选择';
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
    item.id = cell.customId;
    item.name = cell.name;
    item.teacher = cell.teacher;
    item.classroom = cell.classroom;
    item.day = cell.day;
    item.startSection = cell.startSection;
    item.endSection = cell.endSection;
    item.startTime = cell.startTime || '';
    item.endTime = cell.endTime || '';
    // Normalize to 26 elements (1-indexed: index 0 unused, indices 1-25 = weeks 1-25)
    const wl: number[] = [];
    for (let i = 0; i < 26; i++) wl.push(0);
    for (let w = 0; w < cell.weekList.length && w < 25; w++) {
      wl[w + 1] = cell.weekList[w] ? 1 : 0;
    }
    item.weekList = wl;
    item.colorIndex = cell.colorIndex;
    item.type = cell.isExam ? 1 : (cell.isExperiment ? 2 : 0);
    item.examDate = cell.examDate || '';
    item.examTimeStart = cell.examTimeDesc.length > 0 ? cell.examTimeDesc.split('-')[0] : '';
    item.examTimeEnd = cell.examTimeDesc.length > 0 && cell.examTimeDesc.indexOf('-') >= 0 ? cell.examTimeDesc.split('-')[1] : '';
    item.examSeat = cell.examSeat || '';
    return item;
  }

  private async saveCustomList(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const customPath: string = context.filesDir + '/class_table_' + this.semesterCode + '_custom.json';
      const encoder = util.TextEncoder.create('utf-8');
      const jsonStr: string = JSON.stringify(this.customList);
      const encoded = encoder.encodeInto(jsonStr);
      const writeFile = await fileIo.open(customPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      await fileIo.write(writeFile.fd, encoded.buffer);
      await fileIo.close(writeFile);
    } catch (e) {
      // 自定义课表落盘失败：重启后自定义课程丢失，必须留日志
      console.warn('[ClassTablePage] saveCustomList failed: ' + String(e));
    }
    AppStorage.setOrCreate('ct_updated', String(Date.now()) + '_' + String(Math.floor(Math.random() * 10000)));
  }

  private async deleteCustomCourse(cell: ClassCell): Promise<void> {
    // 按 customId 精确删除（不依赖引用比较）
    const targetId: string = cell.customId;
    if (targetId.length === 0) {
      return;
    }
    // 从 classGrid 中按 ID 移除
    for (let cd = 0; cd <= DAY_COUNT; cd++) {
      if (!this.classGrid[cd]) continue;
      for (let cs = 0; cs <= SECTION_COUNT; cs++) {
        if (!this.classGrid[cd][cs]) continue;
        this.classGrid[cd][cs] = this.classGrid[cd][cs].filter(
          (c: ClassCell) => c.customId !== targetId
        );
      }
    }
    // 从 customList 中按 ID 移除
    const idx: number = this.customList.findIndex((item: CustomCourseItem) => item.id === targetId);
    if (idx >= 0) {
      this.customList.splice(idx, 1);
    }
    await this.saveCustomList();
    this.buildCellCache();
    this.saveClassGridSnapshot();
    this.hideCellDetail();
    this.showActionToast('🗑️ 已删除');
  }

  private editCustomCourse(cell: ClassCell): void {
    this.addCourseType = cell.isExam ? 1 : (cell.isExperiment ? 2 : 0);
    this.addCourseSegSel = [this.addCourseType];
    this.addCourseName = cell.name;
    this.addCourseTeacher = cell.teacher;
    this.addCourseClassroom = cell.classroom;
    this.addCourseDay = cell.day;
    this.addCourseStartSection = cell.startSection;
    this.addCourseEndSection = cell.endSection;
    this.addCourseStartTime = cell.startTime || (cell.startSection > 0 && cell.startSection <= 11 ? SEC_START[cell.startSection] : '');
    this.addCourseEndTime = cell.endTime || (cell.endSection > 0 && cell.endSection <= 11 ? SEC_END[cell.endSection] : '');
    this.addCourseWeekList = cell.weekList.map((v: boolean) => v);
    this.addExamDate = cell.examDate || '';
    if (cell.examTimeDesc && cell.examTimeDesc.indexOf('-') >= 0) {
      const pts = cell.examTimeDesc.split('-');
      this.addExamTimeStart = pts[0];
      this.addExamTimeEnd = pts[1];
    } else {
      this.addExamTimeStart = '';
      this.addExamTimeEnd = '';
    }
    this.addExamSeat = cell.examSeat || '';
    this.editingCustomIndex = this.customList.findIndex((item: CustomCourseItem) =>
      item.id === cell.customId
    );
    this.refreshWeekIndex();
    this.savedDetailDay = this.selectedDay;
    this.savedDetailSection = this.selectedSection;
    // 关闭详情弹窗，再打开编辑弹窗
    this.hideCellDetail();
    this.later(() => { this.showAddCourseDialog = true; }, 200);
  }

  private cancelAddCourse(): void {
    const wasEditing: boolean = this.editingCustomIndex >= 0;
    this.showAddCourseDialog = false;
    this.resetAddCourseForm();
    // 编辑模式取消：回到详情弹窗
    if (wasEditing && this.savedDetailDay >= 0 && this.savedDetailSection >= 0) {
      this.later(() => { this.showCellDetail(this.savedDetailDay, this.savedDetailSection); }, 200);
    }
  }

  // 后台获取物理实验（wlsy.xidian.edu.cn），有密码才尝试，没数据也不报错
  private async mergePhysicsExperiments(): Promise<void> {
    const PHYSICS_CACHE = 'physics_exp_cache';
    const CACHE_TTL = 30 * 60 * 1000; // 30 分钟
    const pwd = await SecureStorageUtil.get(SecureAlias.PHYSICS_PWD);
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
        let account = PreferenceUtil.getString('ids_account');
        // 共享登录+取页（ExperimentService，勿在本页另写登录/解析：残缺解析曾覆写共享缓存，
        // 污染 ExperimentPage/MainPage 预览/桌面卡片对 physics_exp_cache 的读取；
        // 登录失败抛带 login1_Label1 原始文案的 Error，后台场景由外层 catch 静默兜底）
        const html = await ExperimentService.physicsFetchScheduleHtml(account, pwd);
        const startTs: number = SemesterUtil.getSemesterStartDate(this.semesterCode).getTime();
        let parsed = ExperimentService.parsePhysicsHtml(html, startTs);
        if (parsed.length > 0) {
          let pc: ESObject = {'ts':Date.now(),'data':parsed} as ESObject;
          PreferenceUtil.putString(PHYSICS_CACHE, JSON.stringify(pc));
        }
        items = parsed;
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
          // 实验只在对应周出现（与 mergeExperimentData 的 sysj 实验同规则；weekList 为空会整学期不渲染）
          const phyWeek: number = parseInt(it['week'] as string) || 0;
          const weekList: boolean[] = [];
          for (let w = 0; w < 25; w++) weekList.push(phyWeek >= 1 && phyWeek <= 25 && w === phyWeek - 1);
          let cell = new ClassCell();
          cell.name = (it['experimentName'] || '物理实验').replace('⚛ ', ''); // 弹窗已自动加🧪前缀
          cell.classroom = it['lab'] || '';
          cell.day = d;
          cell.startSection = s;
          cell.endSection = e;
          cell.startTime = s > 0 && s <= 11 ? SEC_START[s] : '';
          cell.endTime = e > 0 && e <= 11 ? SEC_END[e] : '';
          cell.teacher = it['teacher'] || '';
          cell.isExperiment = true;
          cell.isPhysics = true;
          cell.experimentProject = it['experimentProject'] || '';
          cell.weekList = weekList;
          cell.weekDesc = phyWeek > 0 ? ('第' + phyWeek + '周') : '';
          cell.colorIndex = 0;
          grid[d][s].push(cell);
          merged++;
        }
        if (merged > 0) {
          this.classGrid = grid;
          this.saveClassGridSnapshot();
        }
      }
    } catch (_e) { /* 无物理实验或网络错误，静默 */ }
  }
}
