import { ToastUtil } from '../utils/ToastUtil';
﻿// MainPage.ets - 底部Tab栏主页(主页·更多功能·我的)
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { ThemeColors } from '../utils/ThemeColors';
import { AccentColors, ACCENT_PRESETS } from '../utils/AccentColors';
import { ColorWheelPicker } from '../components/ColorWheelPicker';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { EhallService, SemesterUtil, ClassItemModel } from '../services/EhallService';
import { ClassService } from '../services/ClassService';
import { CasLoginService, TrackPoint, SliderPuzzle, PuzzleImages, CasFormFields } from '../services/CasLoginService';
import { CacheService } from '../services/CacheService';
import { HttpUtil } from '../utils/HttpUtil';
import { router } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { ExamPage } from './exam/ExamPage';
import { ClassTablePage } from './classtable/ClassTablePage';
import { ExperimentPage } from './experiment/ExperimentPage';
import { ScorePage } from './score/ScorePage';
import { EmptyClassroomPage } from './emptyclassroom/EmptyClassroomPage';
import { LibraryPage } from './library/LibraryPage';
import { SchoolCardPage } from './schoolcard/SchoolCardPage';
import { SchoolNetPage } from './schoolnet/SchoolNetPage';
import { ElectricityPage } from './electricity/ElectricityPage';
import { PortalWebPage } from './portal/PortalWebPage';
import { FaqPage } from './faq/FaqPage';
import { AboutPage } from './about/AboutPage';
import { CalendarExportPage } from './calendar_export/CalendarExportPage';
import { AttendancePage } from './attendance/AttendancePage';
import { DormWaterPage } from './dormwater/DormWaterPage';
import { SportPage } from './sport/SportPage';
import { UserInfoService } from '../services/UserInfoService';
import { AttendanceService } from '../services/AttendanceService';
import { application, common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo, fileUri, storageStatistics } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import web_webview from '@ohos.web.webview';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { VersionService, VersionInfo } from '../services/VersionService';
import { CalendarSyncService, SlimCell } from '../services/CalendarSyncService';
import networkUtil from '../utils/NetworkUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 每日用电数据模型
interface DailyItem {
  date: string;     // 本次抄读日期 YYYY-MM-DD
  prevDate: string; // 上次抄读日期
  use: string;      // 两次抄读间用电 kWh
}

const TAG: string = 'MainPage';
const DOMAIN: number = 0xFF00;
// [DIAG2] 诊断日志开关：排查①实验编辑为课程后主页预告不刷新 ②导入日历实验数抖动(0/4) 的问题（排查完可关）
const DIAG2: boolean = true;

interface ElecData {
  remain?: string;
  metID?: string;
  date?: string;
  daily?: DailyItem[];
}

// 节次时间表（与ClassTablePage一致）
const SECTION_TIMES: string[][] = [
  ['08:30', '09:15'],  // 第1节
  ['09:20', '10:05'],  // 第2节
  ['10:25', '11:10'],  // 第3节
  ['11:15', '12:00'],  // 第4节
  ['14:00', '14:45'],  // 第5节
  ['14:50', '15:35'],  // 第6节
  ['15:55', '16:40'],  // 第7节
  ['16:45', '17:30'],  // 第8节
  ['19:00', '19:45'],  // 第9节
  ['19:55', '20:35'],  // 第10节
  ['20:40', '21:25'],  // 第11节
];

// 预览卡片用的轻量数据结构
class PreviewCell {
  name: string = '';
  classroom: string = '';
  teacher: string = '';
  seat: string = '';
  day: number = 0;        // 1-7 周一~周日
  startSection: number = 0; // 1-11
  endSection: number = 0;   // 1-11
  isExperiment: boolean = false;
  isCustom: boolean = false;
  isExam: boolean = false;
  examTimeDesc: string = '';
  examDate: string = '';        // 考试绝对日期 YYYY-MM-DD（日历同步用）
  experimentProject: string = ''; // 实验项目名（日历同步用）
  weekNum: number = 0;    // 哪一周
  weekList: boolean[] = []; // 普通课程的周次列表
}

@Entry
@Component
struct MainPage {
  onBackPress(): boolean {
    if (this.showSemesterDialog) { this.closeSemesterDialog(); return true; }
    if (this.showWheelPicker) { this.closeWheelPickerDialog(); return true; }
    if (this.showColorPicker) { this.closeColorPickerDialog(); return true; }
    if (this.showThemeDialog) { this.closeThemeDialog(); return true; }
    if (this.showPhyPwdDialog) { this.closePhyPwdDialog(); return true; }
    if (this.showSchoolnetPwdDialog) { this.closeSchoolnetPwdDialog(); return true; }
    if (this.showSportPwdDialog) { this.closeSportPwdDialog(); return true; }
    if (this.showLogoutDialog) { this.closeLogoutDialog(); return true; }
    if (this.showBgDialog) { this.closeBgDialog(); return true; }
    if (this.showUpdateDialog) { this.showUpdateDialog = false; return true; }
    if (this.showCaptcha) { this.closeCaptcha(); return true; }
    return false;
  }

  // 弹窗动画关闭方法
  closePhyPwdDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.phyOpacity = 0; this.phyTranslate = 30; });
    setTimeout(() => { this.showPhyPwdDialog = false; }, 200);
  }
  closeSchoolnetPwdDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.schoolnetPwdOpacity = 0; this.schoolnetPwdTranslate = 30; });
    setTimeout(() => { this.showSchoolnetPwdDialog = false; }, 200);
  }
  closeSportPwdDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.sportPwdOpacity = 0; this.sportPwdTranslate = 30; });
    setTimeout(() => { this.showSportPwdDialog = false; }, 200);
  }
  closeThemeDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.themeOpacity = 0; this.themeTranslate = 30; });
    setTimeout(() => { this.showThemeDialog = false; }, 200);
  }
  closeColorPickerDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.colorOpacity = 0; this.colorTranslate = 30; });
    setTimeout(() => { this.showColorPicker = false; }, 200);
  }
  closeWheelPickerDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.wheelOpacity = 0; this.wheelTranslate = 30; });
    setTimeout(() => { this.showWheelPicker = false; }, 200);
  }
  closeSemesterDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.semOpacity = 0; this.semTranslate = 30; });
    setTimeout(() => { this.showSemesterDialog = false; }, 200);
  }
  closeLogoutDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.logoutOpacity = 0; this.logoutTranslate = 30; });
    setTimeout(() => { this.showLogoutDialog = false; }, 200);
  }

  // 清理业务缓存：对齐 Flutter 退登删缓存，换账号不残留
  private async clearBusinessCache(): Promise<void> {
    // 1. CacheService 内容缓存（课表/成绩/考试/空教室等）
    try {
      await CacheService.getInstance().init();
      await CacheService.getInstance().clear();
    } catch (_) {}
    // 2. filesDir 下课表原始数据 + 自定义课程文件（通配删除）
    try {
      const dir: string = this.context.filesDir;
      const files: string[] = fileIo.listFileSync(dir);
      for (const f of files) {
        if (f.startsWith('class_table_') && f.endsWith('.json')) {
          try { fileIo.unlinkSync(dir + '/' + f); } catch (_) {}
        }
      }
    } catch (_) {}
    // 3. Preference 中账号关联的业务缓存
    await PreferenceUtil.putString('exam_schedule_cache', '');
    await PreferenceUtil.putString('sysj_exp_cache', '');
    await PreferenceUtil.putString('physics_exp_cache', '');
    await PreferenceUtil.putString('class_grid_snapshot', '');
    await PreferenceUtil.putString('calendar_bound', ''); // 避免换账号串系统日历
    AppStorage.setOrCreate('electricity_cache', '');
  }
  closeBgDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.bgOpacity = 0; this.bgTranslate = 30; });
    setTimeout(() => { this.showBgDialog = false; }, 200);
  }
  // 选择背景图片 → 跳转裁剪页
  selectBgImage(): void {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(photoSelectOptions).then((result: photoAccessHelper.PhotoSelectResult) => {
        if (result.photoUris.length > 0 && result.photoUris[0] !== undefined) {
          const selectedUri = result.photoUris[0];
          const path = new fileUri.FileUri(selectedUri).path;
          // 跳转到裁剪页面
          router.pushUrl({ url: 'pages/ImageCropPage', params: { path: path } });
        }
      }).catch((err: BusinessError) => {
      });
    } catch (error) {
    }
  }
  // 保存背景设置
  async saveBgSettings(): Promise<void> {
    try {
      if (this.bgShow && this.bgOriPath.length > 0) {
        // 裁剪后的图片已在沙箱，直接存路径
        await PreferenceUtil.putString('class_bg_path', this.bgOriPath);
      } else if (this.bgShow && this.bgOriPath.length === 0) {
        // 开了自定义背景但没选图，提示用户
        this.bgToast = '请先选择一张图片';
        setTimeout(() => { this.bgToast = ''; }, 2000);
        return;
      } else if (!this.bgShow) {
        // 关闭自定义背景
        await PreferenceUtil.putString('class_bg_path', '');
      }
      await PreferenceUtil.putBool('class_bg_show', this.bgShow);
      await PreferenceUtil.putNumber('class_bg_opacity', this.bgOpacityVal);
    } catch (_) {}
    this.closeBgDialog();
  }

  private checkPrivacyAgreement(): void {
    if (PreferenceUtil.getBool('privacy_agreed')) return;
    this.showPrivacyDialog = true;
  }

  private agreePrivacy(): void {
    PreferenceUtil.putBool('privacy_agreed', true);
    this.showPrivacyDialog = false;
  }

  private disagreePrivacy(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.terminateSelf();
    } catch (_) { /* 退出应用 */ }
  }

  private openPrivacyUrl(type: string): void {
    if (type === 'user') {
      this.policyTitle = '用户协议';
      this.policyContent = '一、服务说明\n1.1 HiXD（以下简称"本软件"）是西安电子科技大学校园助手应用，由独立开发者（以下简称"我们"）开发并提供。本软件非学校官方应用，不代表校方立场。\n\n1.2 本软件通过您主动提供的学号和密码，经由学校统一身份认证系统（CAS）获取您的教务数据，为您提供课表查询、成绩查询、考试安排、空闲教室、水电缴费、空间预约等校园服务。\n\n二、账号与安全\n2.1 您需要使用学号和密码登录 CAS 系统。您的密码采用加密传输，仅存储在您的设备本地，不会上传至任何服务器。\n\n2.2 您应妥善保管账号密码，不得泄露给他人。因自身原因导致的损失由您自行承担。\n\n三、用户义务\n3.1 您承诺不利用本软件进行任何违法违规活动，不干扰学校教务系统的正常运行。\n\n3.2 不得滥用本软件功能（如频繁刷新接口），避免对学校服务器造成压力。\n\n四、免责声明\n4.1 本软件以"现状"方式提供。因学校系统升级或接口变更导致的功能异常，我们将尽力修复但不承担责任。\n\n4.2 因设备故障、网络问题等非我们原因导致的损失，我们不承担责任。\n\n五、协议变更\n5.1 我们有权修改本协议，修改后通过应用更新说明等方式公示。继续使用即视为接受修改后的协议。\n\n六、法律适用\n适用中华人民共和国法律。因本协议产生纠纷协商不成的，由开发者所在地法院管辖。\n\n七、联系方式\npollenwang666@petalmail.com';
    } else {
      this.policyTitle = '隐私政策';
      this.policyContent = '本隐私政策说明本软件在用户信息处理方面的原则。核心特点是：不传输您的任何个人信息至任何服务器。\n\n一、信息收集与使用\n1.1 本软件不含任何追踪器或第三方分析 SDK，不收集使用数据。\n\n1.2 为实现功能，本软件在本地收集和处理以下信息：\n• 登录：收集学号和密码，加密后仅存储在本地设备\n• 课表和考试：获取课表及考试信息，仅保存在本地\n• 个人信息：从学校学工系统获取姓名、学号、专业等，仅存储在本地用于展示\n• 自定义背景：读取您选择的图片文件，仅保存在本地\n\n1.3 所有数据处理均限于本地设备完成，不上传至任何外部服务器。\n\n二、信息存储与安全\n2.1 所有数据仅存储在本地。退出登录或卸载应用后可清除。\n\n2.2 网络通信使用 HTTPS 加密。本地数据受系统沙盒保护。建议为设备设置锁屏密码。\n\n三、权限说明\n• 相机权限：宿舍水机扫码绑定设备\n• 日历权限（可选）：课程和考试提醒，仅读取本软件创建的日程\n• 网络权限：访问学校教务系统\n以上权限均不会收集个人隐私数据。\n\n四、您的权利\n数据仅在本地存储，您可直接通过设备管理数据。可随时退出登录清除所有本地信息。\n\n五、隐私政策变更\n将通过应用更新说明等方式提前公示。\n\n六、联系方式\npollenwang666@petalmail.com';
    }
    this.showPolicyViewer = true;
  }
  // 恢复默认
  resetBgSettings(): void {
    this.bgShow = false;
    this.bgPath = '';
    this.bgOriPath = '';
    this.bgOpacityVal = 60;
    PreferenceUtil.putString('class_bg_path', '');
    PreferenceUtil.putBool('class_bg_show', false);
    PreferenceUtil.putNumber('class_bg_opacity', 60);
  }

  @State currentIndex: number = 0;
  @State username: string = '';
  @State isLoggedIn: boolean = false;
  @State loginStatus: string = ''; // '' | 'checking' | 'offline' | 'expired' | 'not_logged_in' | 'ok'
  @State userDisplayName: string = '';  // 真实姓名
  @State userAvatarUrl: string = '';    // 头像 URL
  @State userMajor: string = '';        // 专业
  @State userCollege: string = '';      // 学院
  @State userGrade: string = '';        // 年级
  @State userGender: string = '';       // 性别
  @State userRefreshing: boolean = false; // 用户信息刷新中
  @StorageLink('card_balance') cardBalance: string = ''; // 校园卡余额（由 SchoolCardPage WebView 写入 AppStorage）
  @State homeRefreshing: boolean = false;  // 主页下拉刷新
  @State userDormitory: string = '';   // 宿舍
  @State userStudentType: string = ''; // 学生类别
  @State userClassName: string = '';   // 班级
  @State previewCells: PreviewCell[] = [];
  @State previewLoaded: boolean = false;
  @State previewVersion: number = 0;
  @State isTablet: boolean = deviceInfo.deviceType === 'tablet';
  @State selectedMenuIndex: number = 0;
  private menuNames: string[] = ['课程表', '实验信息', '考试安排', '成绩查询', '空教室', '图书馆', '校园卡', '校园网', '水电查询', '我的'];
  @StorageLink('isSplit') isSplit: NavigationMode = NavigationMode.Auto;
  @StorageLink('portalFullscreen') portalFullscreen: boolean = false;
  pageInfo: NavPathStack = new NavPathStack();
  @StorageLink('electricity_cache') elCache: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  @StorageLink('ct_updated') @Watch('onCtUpdated') ctUpdated: string = '';
  private _lastCtUpdated: string = '';
  private _ctPollId: number = 0;
  // 网络回调绑定引用（startListen/stopListen 须用同一引用才能正确解绑）
  private onNetworkChangeHandler: (available: boolean) => void = this.onNetworkChange.bind(this);

  onClassTableUpdated(): void {
    // @Watch on @StorageLink 在 Navigation 隐藏时不触发，改用定时轮询
  }
  @State cacheSize: string = '计算中...';
  @State showPhyPwdDialog: boolean = false;
  @State phyOpacity: number = 0;
  @State phyTranslate: number = 30;
  @State phyPwdInput: string = '';
  @State phyPwdStatus: string = '未设置';
  @State schoolnetPwdStatus: string = '未设置';
  @State sportPwdStatus: string = '未设置';
  @State showSchoolnetPwdDialog: boolean = false;
  @State schoolnetPwdOpacity: number = 0;
  @State schoolnetPwdTranslate: number = 30;
  @State schoolnetPwdInput: string = '';
  @State showSportPwdDialog: boolean = false;
  @State sportPwdOpacity: number = 0;
  @State sportPwdTranslate: number = 30;
  @State sportPwdInput: string = '';
  @State showThemeDialog: boolean = false;
  @State themeOpacity: number = 0;
  @State themeTranslate: number = 30;
  @State showColorPicker: boolean = false;
  @State colorOpacity: number = 0;
  @State colorTranslate: number = 30;
  @State showWheelPicker: boolean = false;
  @State wheelOpacity: number = 0;
  @State wheelTranslate: number = 30;
  @State customHex: string = '';
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('accent_index') accentIdx: number = 0;
  private retryTimer: number = -1;
  private lastForegroundCheck: number = 0;  // 前后台切换防抖

  // ==================== 隐私协议弹窗（首次启动） ====================
  @State showPrivacyDialog: boolean = false;
  @State showPolicyViewer: boolean = false;
  @State policyTitle: string = '';
  @State policyContent: string = '';
  @State showSemesterDialog: boolean = false;
  @State semOpacity: number = 0;
  @State semTranslate: number = 30;
  @State showLogoutDialog: boolean = false;
  @State logoutOpacity: number = 0;
  @State logoutTranslate: number = 30;
  @State pickSemYear: number = 2025;
  @State pickSemPart: number = 2;
  @State pickWeekSwift: number = 0;
  @State semesterToast: string = '';
  // 自定义课表背景
  @State showBgDialog: boolean = false;
  @State bgOpacity: number = 0;
  @State bgTranslate: number = 30;
  @State bgShow: boolean = false;
  @State bgPath: string = '';       // 预览用的 URI
  @State bgOriPath: string = '';    // 原始文件路径
  @State bgOpacityVal: number = 60; // 不透明度，存储为整数（60=60%）
  @StorageProp('currentColorMode') @Watch('onColorModeChange') systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navIndicatorHeight') navIndicatorHeight: number = 0;
  @State currentThemeLabel: string = '当前：浅色模式';
  // ==================== xgxt 隐藏 WebView（个人信息抓取 + 超星头像） ====================
  @State xgxtActive: boolean = false;
  private xgxtPhase: number = 0;  // 0=idle, 1=xgxt学工, 2=超星头像
  private xgxtUrl: string = 'https://xgxt.xidian.edu.cn/xsfw/sys/jbxxapp/*default/index.do';
  private xgxtController: web_webview.WebviewController = new web_webview.WebviewController();
  private xgxtTimeoutId: number = -1;

  // ==================== 版本更新弹窗 ====================
  @State showUpdateDialog: boolean = false;
  @State updateInfo: VersionInfo | null = null;
  @State hasUpdate: boolean = false;
  @State skipVersion: string = '';
  @State updateToast: string = '';
  @State bgToast: string = '';
  updateChecked: boolean = false;
  currentVersion: string = '';

  // ==================== 滑块验证码 overlay（原地弹窗，不跳页） ====================
  @State showCaptcha: boolean = false;
  @State captchaBigPm: PixelMap | null = null;
  @State captchaSmallPm: PixelMap | null = null;
  @State captchaSliderLeft: number = 0;
  @State captchaSubmitting: boolean = false;
  @State captchaErr: string = '';
  private captchaTracks: TrackPoint[] = [];
  private captchaDragStartX: number = 0;
  private captchaLastRecMs: number = 0;
  private captchaLastA: number = -999;
  private captchaLastB: number = -999;
  private captchaActivePtr: number = -1;
  private captchaFormFields: CasFormFields | null = null;
  private captchaSmallBase64: string = '';
  private readonly CAPTCHA_LIMIT: number = 240;
  private readonly CAPTCHA_THUMB: number = 42;

  // ==================== 菜单排序 ====================
  @State homeSortOn: boolean = false;
  @State homeMenuOrder: string[] =
    ['Score', 'Exam', 'Library', 'SchoolNet', 'EmptyClass', 'SchoolCard', 'Attendance', 'Water', 'Experiment', 'Electricity', 'Sport'];
  @State portalSortOn: boolean = false;
  @State portalMenuOrder: string[] =
    ['Dianfei', 'Dingshui', 'Baoxiu', 'Space', 'Portal', 'Ruisi', 'Physics', 'Mail', 'Net', 'SchoolCardWeb'];

  private homeMenuItemClick(name: string): void {
    const names: Record<string, string> = {
      'Score': 'ScorePage', 'Exam': 'ExamPage', 'Library': 'LibraryPage',
      'SchoolNet': 'SchoolNetPage', 'EmptyClass': 'EmptyClassroomPage',
      'SchoolCard': 'SchoolCardPage', 'Attendance': 'AttendancePage',
      'Water': 'DormWaterPage', 'Experiment': 'ExperimentPage',
      'Electricity': 'ElectricityPage', 'Sport': 'SportPage'
    };
    const route = names[name];
    if (route) { this.pageInfo.clear(); this.pageInfo.pushPath({ name: route }); }
  }

  private homeMenuMoveUp(idx: number): void {
    if (idx <= 0) return;
    const arr = [...this.homeMenuOrder];
    const tmp = arr[idx - 1]; arr[idx - 1] = arr[idx]; arr[idx] = tmp;
    this.homeMenuOrder = arr;
    this.saveHomeMenuOrder();
  }

  private homeMenuMoveDown(idx: number): void {
    if (idx >= this.homeMenuOrder.length - 1) return;
    const arr = [...this.homeMenuOrder];
    const tmp = arr[idx + 1]; arr[idx + 1] = arr[idx]; arr[idx] = tmp;
    this.homeMenuOrder = arr;
    this.saveHomeMenuOrder();
  }

  private saveHomeMenuOrder(): void {
    PreferenceUtil.putString('home_menu_order', this.homeMenuOrder.join(','));
  }

  private loadHomeMenuOrder(): void {
    const saved = PreferenceUtil.getString('home_menu_order');
    if (saved.length > 0) {
      const arr = saved.split(',');
      if (arr.length === 11) { this.homeMenuOrder = arr; }
    }
  }

  private portalMenuMoveUp(idx: number): void {
    if (idx <= 0) return;
    const arr = [...this.portalMenuOrder];
    const tmp = arr[idx - 1]; arr[idx - 1] = arr[idx]; arr[idx] = tmp;
    this.portalMenuOrder = arr;
    this.savePortalMenuOrder();
  }

  private portalMenuMoveDown(idx: number): void {
    if (idx >= this.portalMenuOrder.length - 1) return;
    const arr = [...this.portalMenuOrder];
    const tmp = arr[idx + 1]; arr[idx + 1] = arr[idx]; arr[idx] = tmp;
    this.portalMenuOrder = arr;
    this.savePortalMenuOrder();
  }

  private savePortalMenuOrder(): void {
    PreferenceUtil.putString('portal_menu_order', this.portalMenuOrder.join(','));
  }

  private loadPortalMenuOrder(): void {
    const saved = PreferenceUtil.getString('portal_menu_order');
    if (saved.length > 0) {
      const arr = saved.split(',');
      if (arr.length === 9) { this.portalMenuOrder = arr; }
    }
  }

  private tabsController: HdsTabsController = new HdsTabsController();
  private context!: common.UIAbilityContext;
  // 应用级缓存目录（异步初始化）
  private appCacheDir: string = '';
  private appCacheWebDir: string = '';
  // 菜单排序
  @State homeSortMode: boolean = false;
  @State portalSortMode: boolean = false;

  aboutToAppear() {
    this.context = getContext(this) as common.UIAbilityContext;
    this.loadHomeMenuOrder();
    this.loadPortalMenuOrder();
    // 卡片点击跳转
    try {
      this.getUIContext().getHostContext()?.eventHub.on('cardNavigate', (path: string) => {
        if (path === 'Schedule') {
          this.onMenuClick(0); // 0 = 课程表
        }
      });
    } catch (_e) { /* ignore */ }

    // 屏幕宽度检测（响应式布局）
    // 平板：自动选中第一项课表
    if (this.isTablet) {
      this.onMenuClick(0);
    }
    // 基于 ids_account 判断登录状态（无 is_logged_in 标记）
    this.username = PreferenceUtil.getString('ids_account');
    this.isLoggedIn = this.username.length > 0;

    // 主题初始化（LoginPage 也依赖全局主题，提前初始化）
    const savedMode: number = PreferenceUtil.getNumber('theme_color_mode',
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    ThemeColors.init(savedMode, getContext());
    AccentColors.init();
    this.currentThemeLabel = this.buildThemeLabel(savedMode);
    AppStorage.setOrCreate('currentColorMode', savedMode);

    // ===== 门禁：未登录直接进登录页，绝不在 MainPage 触发自动登录/滑块 =====
    if (!this.isLoggedIn) {
      router.replaceUrl({ url: 'pages/login/LoginPage' });
      return;
    }

    // ===== 以下仅已登录态执行 =====
    this.updateCacheSize();
    this.phyPwdStatus = PreferenceUtil.getString('physics_pwd').length > 0 ? '已设置' : '未设置';
    this.schoolnetPwdStatus = PreferenceUtil.getString('schoolnet_password').length > 0 ? '已设置' : '未设置';
    this.sportPwdStatus = PreferenceUtil.getString('sport_password').length > 0 ? '已设置' : '未设置';
    this.loginStatus = 'checking';
    // TGC 优先 → 密码兜底，一步完成
    this.checkLogin();
    this.loadClassPreview();
    // 课表子页（课程表）编辑后返回时，onPageShow/@Watch 不会触发（@Entry 宿主在 NavDestination 之上不重入生命周期），
    // 故用轻量轮询 ct_updated：tryRefreshPreview 仅在 ct_updated 变化时重载预览+快照，无变化则空转（字符串比较）。
    this._lastCtUpdated = AppStorage.get('ct_updated') as string || '';
    this._ctPollId = setInterval(() => { this.tryRefreshPreview(); }, 1000);
    this.initCacheDirs();
    // 后台检查版本更新（不阻塞 UI）
    this.checkVersionUpdate();
    // 获取当前版本号用于 UI 显示
    VersionService.getCurrentVersion().then((v: string) => { this.currentVersion = v; });
    // 首次启动隐私协议检查
    this.checkPrivacyAgreement();
    // 从缓存加载用户信息（登录前也能显示名字和头像）
    this.loadCachedUserInfo();
    // 从 PreferenceUtil 读上次缓存余额（由 SchoolCardPage 写入）
    const cachedBal: string = PreferenceUtil.getString('card_balance_cached', '');
    if (cachedBal.length > 0) {
      AppStorage.setOrCreate('card_balance', cachedBal);
    }
    // 注册网络状态监听：网络恢复时自动触发重登录
    networkUtil.startListen(this.onNetworkChangeHandler);
  }

  /**
   * 网络状态变化回调
   * @param available - 网络是否可用
   */
  private onNetworkChange(available: boolean): void {
    if (available) {
      // 网络恢复 → 如果之前是离线状态，自动触发重登录
      if (this.loginStatus === 'offline' || this.loginStatus === 'expired' || this.loginStatus === 'timeout') {
        this.checkLogin();
      }
    } else {
      // 网络断开 → 更新状态（但不弹窗，避免打扰用户）
      if (this.loginStatus === 'checking' || this.loginStatus === 'online') {
        this.loginStatus = 'offline';
AppStorage.set('loginStatus', 'offline');
        this.isLoggedIn = false;
      }
    }
  }

  // 异步获取应用级缓存目录（WebView 缓存存在这里，不在 HAP 级目录）
  private async initCacheDirs(): Promise<void> {
    try {
      const moduleContext = await application.createModuleContext(this.context, 'entry');
      this.appCacheDir = moduleContext.cacheDir;
      this.appCacheWebDir = moduleContext.cacheDir + '/web';
    } catch (e) {
    }
  }

  // 后台检查版本更新
  private async checkVersionUpdate(showNotNeeded: boolean = false): Promise<void> {
    if (!showNotNeeded && this.updateChecked) return;
    this.updateChecked = true;
    try {
      const info = await VersionService.checkForUpdate();
      if (info) {
        this.updateInfo = info;
        this.hasUpdate = true;
        // 自动检查且已跳过此版本 → 不弹窗；手动检查始终弹窗
        const skipped = PreferenceUtil.getString('skip_version');
        if (showNotNeeded || skipped !== info.version) {
          this.showUpdateDialog = true;
        }
      } else {
        this.hasUpdate = false;
        if (showNotNeeded) {
          this.updateToast = '当前已是最新版本';
          setTimeout(() => { this.updateToast = ''; }, 1500);
        }
      }
    } catch (_) {}
  }

  aboutToDisappear() {
    if (this._ctPollId !== 0) { clearInterval(this._ctPollId); this._ctPollId = 0; }
    this.stopRetryTimer();
    // 解绑监听，避免页面重建时 handler 累积、或销毁后回调触发空引用
    networkUtil.stopListen(this.onNetworkChangeHandler);
    this.getUIContext().getHostContext()?.eventHub.off('cardNavigate');
  }

  // 从后台切回前台时刷新登录状态
  onPageShow(): void {
    const now = Date.now();
    if (now - this.lastForegroundCheck >= 30000) {
      this.lastForegroundCheck = now;
      this.refreshSessionIfNeeded();
    }
    // [FIX] 页面重新可见（含从课表页 NavDestination 返回）时无条件重载预览。
    // 原先仅 tryRefreshPreview（有 ct_updated 变化守卫），编辑后唯一一次重赋发生在主页不可见时，
    // 返回后 onPageShow 因 ct_updated 已相等而不重载 → UI 停留旧帧，须重进 App 才刷新。
    // 这里改为可见即重载，确保 previewCells 在可见态重赋、触发重渲染。
    if (DIAG2) {
      hilog.info(DOMAIN, TAG, '[DIAG2] onPageShow → loadClassPreview(可见重载)');
    }
    this.loadClassPreview();
    // 检查裁剪页面返回的图片
    const croppedPath: string = AppStorage.get<string>('cropped_bg_path') ?? '';
    if (croppedPath.length > 0) {
      this.bgPath = fileUri.getUriFromPath(croppedPath) + '?t=' + Date.now();
      this.bgOriPath = croppedPath;
      this.bgShow = true;
      AppStorage.set<string>('cropped_bg_path', '');
    }
  }

  // 每次 build 时检查课表是否更新（直接读 AppStorage，避免 @StorageLink 在隐藏 Tab 不更新）
  private tryRefreshPreview(): void {
    const current: string = AppStorage.get('ct_updated') as string || '';
    if (current !== this._lastCtUpdated && current.length > 0) {
      if (DIAG2) {
        hilog.info(DOMAIN, TAG, '[DIAG2] tryRefreshPreview 触发重载 ct_updated: ' + this._lastCtUpdated + ' -> ' + current);
      }
      this._lastCtUpdated = current;
      this.loadClassPreview();
    }
  }

  // ct_updated 变化（@StorageLink + @Watch）时触发预览刷新；替代原先 build() 中轮询 _previewDirty 的自循环
  private onCtUpdated(): void {
    this.tryRefreshPreview();
  }

  private async refreshSessionIfNeeded(): Promise<void> {
    if (this.loginStatus !== 'ok') return;
    try {
      const cas = CasLoginService.getInstance();
      const restored = await cas.tryAutoRestoreLogin();
      if (!restored) {
        this.checkLogin();
      }
    } catch (_) { /* TGC check failed, ignore */ }
  }

  // 自动登录检测：TGC → 密码，简单直接
  // 网络失败不跳转不重试，过期不自动弹登录页，由用户手动触发
  async checkLogin() {
    this.stopRetryTimer();
    try {
      const cas = CasLoginService.getInstance();
      const loggedIn: boolean = await cas.checkAndAutoLogin();
      if (loggedIn) {
        const ehall = EhallService.getInstance();
        const reallyLoggedIn: boolean = await ehall.checkEhallLogin();
        if (reallyLoggedIn) {
          this.isLoggedIn = true;
          this.loginStatus = 'ok';
AppStorage.set('loginStatus', 'ok');
          await PreferenceUtil.putBool('is_logged_in', true);
          await cas.syncCookiesToWebView();
          this.loadUserInfo();  // 异步获取名字/头像/专业
          // warmup disabled: pollutes CookieJar with Domain=.xidian.edu.cn cookies, breaking zfw/libspace
          this.startPreload();
          return;
        }
      }
      // checkAndAutoLogin 返回 false → 确认是网络不通还是真的过期
      try {
        await EhallService.getInstance().checkEhallLogin();
        // 网络通但没登录 → 真正过期，有凭证则自动弹出滑块
        const hasCred: boolean = PreferenceUtil.getString('ids_account').length > 0;
        if (hasCred) {
          // 保留 isLoggedIn = true，"我的"页面继续显示菜单，滑块 overlay 在顶层
          this.loginStatus = 'expired';
AppStorage.set('loginStatus', 'expired');
          await this.doRelogin();
          return;
        }
        this.isLoggedIn = false;
        this.loginStatus = 'not_logged_in';
AppStorage.set('loginStatus', 'not_logged_in');
      } catch (_netErr) {
        this.loginStatus = 'offline';
AppStorage.set('loginStatus', 'offline');
        this.isLoggedIn = false;
        this.startRetryTimer();
      }
    } catch (e) {
      // 区分断网和服务器超时
      if (networkUtil.isNetworkAvailable) {
        this.loginStatus = 'timeout';
      } else {
        this.loginStatus = 'offline';
AppStorage.set('loginStatus', 'offline');
      }
      this.isLoggedIn = false;
      this.startRetryTimer();
    }
  }

  // ========== 断网重试 ==========
  private startRetryTimer(): void {
    this.stopRetryTimer();
    this.retryTimer = setInterval(() => {
      if (this.loginStatus === 'offline' || this.loginStatus === 'timeout') { this.checkLogin(); }
    }, 10000) as number;
  }

  private stopRetryTimer(): void {
    if (this.retryTimer !== -1) { clearInterval(this.retryTimer); this.retryTimer = -1; }
  }

  // ==================== 重新登录：TGC 优先 → 滑块兜底（原地弹窗） ====================
  async doRelogin(): Promise<void> {
    this.loginStatus = 'checking';
    try {
      const cas: CasLoginService = CasLoginService.getInstance();
      // Step 1: 先用 TGC 尝试恢复
      const restored: boolean = await cas.tryAutoRestoreLogin();
      if (restored) {
        const ehall: EhallService = EhallService.getInstance();
        const reallyLoggedIn: boolean = await ehall.checkEhallLogin();
        if (reallyLoggedIn) {
          this.isLoggedIn = true;
          this.loginStatus = 'ok';
AppStorage.set('loginStatus', 'ok');
          await PreferenceUtil.putBool('is_logged_in', true);
          await cas.syncCookiesToWebView();
          this.loadUserInfo();
          // warmup disabled
          this.startPreload();
          return;
        }
      }
      // Step 2: TGC 无效 → 获取表单和验证码
      const fields: CasFormFields = await cas.getLoginPageForm();
      if (!fields.execution) {
        // 拉表单时 TGC 又生效了（CAS 302 到 ehall）
        const ehall = EhallService.getInstance();
        const reallyLoggedIn: boolean = await ehall.checkEhallLogin();
        if (reallyLoggedIn) {
          this.isLoggedIn = true;
          this.loginStatus = 'ok';
AppStorage.set('loginStatus', 'ok');
          await PreferenceUtil.putBool('is_logged_in', true);
          await cas.syncCookiesToWebView();
          this.loadUserInfo();
          // warmup disabled
          this.startPreload();
          return;
        }
      }
      this.captchaFormFields = fields;
      const puzzle: SliderPuzzle = await cas.getSliderCaptcha();
      const pieces: PuzzleImages = cas.getPuzzleImages(puzzle);
      this.captchaSmallBase64 = puzzle.smallImage;
      this.captchaBigPm = await this.bytesToPm(pieces.bigPm);
      this.captchaSmallPm = await this.bytesToPm(pieces.smallPm);
      this.captchaSliderLeft = 0;
      this.captchaTracks = [];
      this.captchaErr = '';
      this.showCaptcha = true;
      this.loginStatus = 'expired';
AppStorage.set('loginStatus', 'expired');  // 对应 HiXD 标题下显示「登录已过期」
    } catch (e) {
      this.loginStatus = 'offline';
AppStorage.set('loginStatus', 'offline');
    }
  }

  // Uint8Array → PixelMap
  private async bytesToPm(data: Uint8Array): Promise<PixelMap> {
    const buf: ArrayBuffer = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    const imgSrc: image.ImageSource = image.createImageSource(buf as ArrayBuffer);
    const opts: image.DecodingOptions = { desiredSize: { width: 280, height: 155 } };
    return await imgSrc.createPixelMap(opts);
  }

  // 滑块触摸
  private handleCaptchaTouch(event: TouchEvent): void {
    if (this.captchaSubmitting || !this.showCaptcha) { return; }
    if (event.type === TouchType.Down) {
      const touch: TouchObject = event.touches[0];
      this.captchaActivePtr = touch.id;
      this.captchaDragStartX = touch.x;
      this.captchaLastRecMs = Date.now();
      this.captchaTracks = [{ a: 0, b: 0, c: 0 }];
      this.captchaLastA = 0;
      this.captchaLastB = 0;
      this.captchaErr = '';
    } else if (event.type === TouchType.Move) {
      const found: TouchObject | undefined = event.touches.find((t: TouchObject) => t.id === this.captchaActivePtr);
      if (!found) { return; }
      const dx: number = found.x - this.captchaDragStartX;
      if (dx < 0 || dx > this.CAPTCHA_LIMIT) { return; }
      this.captchaSliderLeft = dx;
      const nowMs: number = Date.now();
      const elapsed: number = nowMs - this.captchaLastRecMs;
      if (elapsed < 20) { return; }
      const a: number = Math.round(dx);
      const b: number = 0;
      const dist: number = (a - this.captchaLastA) * (a - this.captchaLastA)
      if (dist < 4) { return; }
      this.captchaTracks.push({ a: a, b: b, c: elapsed });
      this.captchaLastA = a;
      this.captchaLastB = b;
      this.captchaLastRecMs = nowMs;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.captchaActivePtr = -1;
      if (event.type === TouchType.Up && this.captchaTracks.length > 0) {
        const finalDx: number = this.captchaSliderLeft;
        this.captchaTracks.push({ a: Math.round(finalDx), b: 0, c: Date.now() - this.captchaLastRecMs });
        this.submitCaptcha();
      }
    }
  }

  // 验证码提交验证
  private async submitCaptcha(): Promise<void> {
    if (this.captchaTracks.length === 0 || !this.captchaFormFields) {
      this.captchaErr = '请拖动滑块';
      return;
    }
    this.captchaSubmitting = true;
    this.captchaErr = '';
    try {
      const cas: CasLoginService = CasLoginService.getInstance();
      const verified: boolean = await cas.verifySliderCaptcha(this.captchaTracks, this.captchaSmallBase64);
      if (!verified) {
        this.captchaErr = '验证失败，请重试';
        this.resetCaptchaState();
        return;
      }
      const username: string = PreferenceUtil.getString('ids_account');
      const password: string = PreferenceUtil.getString('login_password');
      const success: boolean = await cas.postLogin(username, password, this.captchaFormFields);
      if (success) {
        EhallService.getInstance().clearSessionCache();
        await cas.syncCookiesToWebView();
        this.showCaptcha = false;
        this.isLoggedIn = true;
        this.loginStatus = 'ok';
AppStorage.set('loginStatus', 'ok');
        this.loadUserInfo();
        // warmup disabled
        this.startPreload();
      } else {
        this.captchaErr = '登录失败，请重试';
        this.resetCaptchaState();
      }
    } catch (e) {
      this.captchaErr = String(e);
      this.resetCaptchaState();
    }
  }

  private resetCaptchaState(): void {
    this.captchaSubmitting = false;
    this.captchaTracks = [];
    this.captchaSliderLeft = 0;
  }

  private closeCaptcha(): void {
    this.showCaptcha = false;
    this.loginStatus = 'expired';
AppStorage.set('loginStatus', 'expired');
  }

  // ====== 滑块验证码 Overlay ======
  @Builder CaptchaOverlay() {
    Stack() {
      Column() {
        // 关闭
        Text('✕')
          .fontSize(20).fontColor('#999999')
          .margin({ bottom: 16 })
          .onClick(() => { this.closeCaptcha(); })

        if (this.captchaSubmitting) {
          LoadingProgress().width(48).height(48).color('#2979FF').margin({ top: 60, bottom: 60 })
          Text('请稍候...').fontSize(14).fontColor('#999999')
          Blank()
        } else {
          // 拼图图片
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.captchaBigPm) {
              Image(this.captchaBigPm).width(280).height(155).objectFit(ImageFit.Fill)
            } else {
              Row().width(280).height(155).backgroundColor('#F5F5F5')
            }
            if (this.captchaSmallPm) {
              Image(this.captchaSmallPm).width(44).height(155).objectFit(ImageFit.Fill)
                .offset({ x: this.captchaSliderLeft, y: 0 })
            }
          }
          .width(280).height(155).borderRadius(4).clip(true).backgroundColor('#F0F0F0')

          // 滑块轨道
          Stack({ alignContent: Alignment.TopStart }) {
            Row().width(280).height(10).backgroundColor('#E0E0E0').borderRadius(5)
            Row().width(Math.min(this.captchaSliderLeft + 4, 280)).height(10)
              .backgroundColor('#4CAF50').borderRadius(5)
            Row() {
              Text('→').fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
            }
            .width(this.CAPTCHA_THUMB).height(this.CAPTCHA_THUMB)
            .borderRadius(21).backgroundColor('#4CAF50')
            .justifyContent(FlexAlign.Center)
            .shadow({ radius: 6, color: '#00000030', offsetY: 2 })
            .offset({ x: this.captchaThumbOff(), y: -16 })
          }
          .width(280).height(this.CAPTCHA_THUMB + 10).margin({ top: 33 })
          .onTouch((event: TouchEvent) => { this.handleCaptchaTouch(event); })

          if (this.captchaErr.length > 0) {
            Text(this.captchaErr).fontSize(13).fontColor('#FF6B6B').margin({ top: 12 })
          }
          Text('请按住滑块拖动到合适位置').fontSize(12).fontColor('#999999').margin({ top: 16 })
        }
      }
      .width(320).padding(20)
      .backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
    .backgroundColor(0xCC000000)
    .alignContent(Alignment.Center)
  }

  private captchaThumbOff(): number {
    return Math.max(0, Math.min(this.captchaSliderLeft - 1, 280 - this.CAPTCHA_THUMB));
  }

  // 登录成功后预加载课表、考试、实验数据
  private startPreload(): void {
    AppStorage.setOrCreate('login_state', String(Date.now()));
    EhallService.getInstance().preloadAllData().then(async () => {
      // 首登/缓存缺失时，把课表从内部 CacheService 落盘到 filesDir/class_table_<学期>.json：
      // 首页预览只读该文件，而 preloadAllData 仅填充 ClassService 内部 CacheService，不会写这个文件，
      // 否则首页课表预览会一直空白，直到用户手动打开课表页（writeLocalClassTable）才生成。
      await this.ensureClassTableFile();
      // 用最新缓存重建预览 + 更新日历快照，并自动增量同步日历（对齐 Flutter 首页刷新触发）
      this.loadClassPreview();
      CalendarSyncService.autoSync(getContext(this) as common.UIAbilityContext);
    }).catch((e: Error) => {
    });
  }

  // 确保 filesDir/class_table_<学期>.json 存在：首页课表预览只读此文件。
  // preloadAllData 已通过 ClassService 内部 CacheService 拉取课表，这里命中缓存写出文件即可，
  // 使首页预览无需用户手动打开课表页就能显示（修复首登后课表不主动加载）。
  private async ensureClassTableFile(): Promise<void> {
    const sid: string = PreferenceUtil.getString('ids_account');
    if (sid.length === 0) return;
    const semCode: string = SemesterUtil.getCurrentSemesterCode();
    const filePath: string = this.context.filesDir + '/class_table_' + semCode + '.json';
    try {
      if (fileIo.accessSync(filePath)) return; // 文件已存在，无需重复拉取
    } catch (_) { /* accessSync 抛异常表示文件不存在，继续 */ }
    try {
      const raw: string = await ClassService.getInstance().getClassTable(semCode, sid);
      if (!raw || raw.length < 100) return;
      const encoder = new util.TextEncoder();
      const encoded: Uint8Array = encoder.encodeInto(raw);
      const file: fileIo.File = fileIo.openSync(filePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, encoded.buffer);
      fileIo.closeSync(file);
    } catch (_) { /* 拉取/写盘失败不影响首页其它模块 */ }
  }

  // 异步加载用户信息（名字/头像/专业），失败用缓存兜底
  private loadUserInfo(): void {
    // 先打印原始 Preference 值，便于诊断
    const rawName: string = PreferenceUtil.getString('user_name');
    const rawAvatar: string = PreferenceUtil.getString('user_avatar');
    const rawMajor: string = PreferenceUtil.getString('user_major');
    const rawCollege: string = PreferenceUtil.getString('user_college');

    UserInfoService.getInstance().fetchAll().then((info) => {
      if (info.name) {
        this.userDisplayName = info.name;
      }
      if (info.avatar) {
        this.downloadAndSetAvatar(info.avatar);
      }
      if (info.major) {
        this.userMajor = info.major;
      }
      if (info.college) {
        this.userCollege = info.college;
      }
      if (info.grade) {
        this.userGrade = info.grade;
      }
      if (info.gender) {
        this.userGender = info.gender;
      }
      if (info.dormitory) {
        this.userDormitory = info.dormitory;
      }
      if (info.studentType) {
        this.userStudentType = info.studentType;
      }
      if (info.className) {
        this.userClassName = info.className;
      }
    }).catch((e: Error) => {
      this.userDisplayName = rawName;
      this.userAvatarUrl = rawAvatar;
      this.userMajor = rawMajor;
      this.userCollege = rawCollege;
    });

    // 首次登录时 LoginPage 已拉取并缓存，这里仅读取；若意外未初始化则自动补一次
    if (!rawName && !PreferenceUtil.getBool('user_info_initialized')) {
      setTimeout(() => { this.refreshUserInfo(); }, 2000);
    }
  }

  // 下载头像到本地缓存（避免 Image 组件跟随 CDN 重定向失败的问题）
  private downloadAndSetAvatar(url: string): void {
    const req: http.HttpRequest = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      header: { 'Referer': 'https://i.chaoxing.com/' }
    }).then((resp: http.HttpResponse): void => {
      if (resp.responseCode === 200 && resp.result) {
        const buf: ArrayBuffer = resp.result as ArrayBuffer;
        const filePath: string = this.context.cacheDir + '/user_avatar.png';
        try {
          const dst: fileIo.File = fileIo.openSync(filePath,
            fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
          fileIo.writeSync(dst.fd, buf);
          fileIo.closeSync(dst);
          this.userAvatarUrl = 'file://' + filePath;
        } catch (e2) {
        }
      } else {
      }
    }).catch((e: Object): void => {
    }).finally((): void => {
      req.destroy();
    });
  }

  private loadCachedUserInfo(): void {
    this.userDisplayName = PreferenceUtil.getString('user_name');
    this.userMajor = PreferenceUtil.getString('user_major');
    this.userCollege = PreferenceUtil.getString('user_college');
    this.userGrade = PreferenceUtil.getString('user_grade');
    this.userGender = PreferenceUtil.getString('user_gender');
  }

  // 后台获取校园卡余额（不阻塞 UI，静默失败）
  // 手动刷新用户信息 — 隐藏 WebView 加载 xgxt jbxxapp SPA → JS fetch API 提取
  private refreshUserInfo(): void {
    if (this.userRefreshing) {
      return;
    }
    this.userRefreshing = true;

    // 清除旧 WebView 状态
    clearTimeout(this.xgxtTimeoutId);
    this.xgxtActive = false;

    // 先同步 CAS cookie 到 WebView，确保 SSO 能自动跳转
    CasLoginService.getInstance().syncCookiesToWebView();

    // 下一帧激活 WebView，触发 CAS SSO → jbxxapp SPA 加载
    this.xgxtPhase = 1;
    setTimeout(() => { this.xgxtActive = true; }, 100);

    // 超时保护
    this.xgxtTimeoutId = setTimeout(() => {
      this.xgxtCleanup();
    }, 25000);
  }

  // xgxt SPA 加载完成后注入 JS 抓取 getStuBaseInfo
  private xgxtInjectFetch(): void {
    const xh: string = this.username || PreferenceUtil.getString('ids_account');
    // 等待 SPA 初始化后再调用 API
    const js: string =
      'setTimeout(function(){' +
      '  var body="requestParamStr="+encodeURIComponent(\'{"XSBH":"' + xh + '"}\');' +
      '  fetch("/xsfw/sys/jbxxapp/modules/infoStudent/getStuBaseInfo.do",{' +
      '    method:"POST",' +
      '    headers:{"Content-Type":"application/x-www-form-urlencoded; charset=UTF-8"},' +
      '    body:body' +
      '  }).then(function(r){return r.text();})' +
      '    .then(function(d){console.log("XGXT_INFO:"+d);})' +
      '    .catch(function(e){console.log("XGXT_ERR:"+e);});' +
      '},4000);';
    this.xgxtController.runJavaScript(js);
  }

  // 处理 JS fetch 返回的 getStuBaseInfo JSON
  private xgxtProcessResult(raw: string): void {
    try {
      const obj: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const returnCode: string = String(obj['returnCode'] ?? '');
      if (returnCode !== '#E000000000000') {
        const desc: string = String(obj['description'] ?? JSON.stringify(raw).substring(0, 120));
        this.xgxtCleanup();
        return;
      }
      const data: Record<string, Object> = obj['data'] as Record<string, Object>;
      if (!data) {
        this.xgxtCleanup();
        return;
      }
      // 提取字段
      const name: string = String(data['XM'] ?? '');
      const gender: string = String(data['XBDM_DISPLAY'] ?? '');
      const college: string = String(data['DWDM_DISPLAY'] ?? '');
      const major: string = String(data['ZYDM_DISPLAY'] ?? '');
      const grade: string = String(data['XZNJ'] ?? '');
      const cls: string = String(data['BJDM_DISPLAY'] ?? '');
      const dorm: string = String(data['ZSDZ'] ?? '');
      const stype: string = String(data['XSLBDM_DISPLAY'] ?? '');

      // 持久化
      Promise.all([
        name ? PreferenceUtil.putString('user_name', name) : Promise.resolve(),
        college ? PreferenceUtil.putString('user_college', college) : Promise.resolve(),
        major ? PreferenceUtil.putString('user_major', major) : Promise.resolve(),
        grade ? PreferenceUtil.putString('user_grade', grade) : Promise.resolve(),
        gender ? PreferenceUtil.putString('user_gender', gender) : Promise.resolve(),
        cls ? PreferenceUtil.putString('user_class', cls) : Promise.resolve(),
        dorm ? PreferenceUtil.putString('user_dormitory', dorm) : Promise.resolve(),
        stype ? PreferenceUtil.putString('user_student_type', stype) : Promise.resolve(),
      ]).catch(() => {});
      if (stype) PreferenceUtil.putString('user_student_type', stype);
      this.loadUserInfo();

      // 学工数据拿到后，进入阶段2：超星头像提取
      const cachedUid: string = PreferenceUtil.getString('cx_uid');
      if (cachedUid.length > 0 && /^\d+$/.test(cachedUid)) {
        this.downloadAndSetAvatar('https://photo.chaoxing.com/p/' + cachedUid + '_80');
        this.xgxtCleanup();
        return;
      }

      // 无缓存 → HTTP 走考勤 SSO 入口建超星 session → WebView 直连 i.chaoxing
      this.xgxtPhase = 2;
      const attSvc: AttendanceService = AttendanceService.getInstance();
      attSvc.loginToLearning().then(() => {
        const http = HttpUtil.getInstance();
        const srcDomains: string[] = ['fanya.chaoxing.com', 'xdspoc.fanya.chaoxing.com',
          'fycourse.fanya.chaoxing.com', 'mobilelearn.chaoxing.com'];
        const cxDomains: string[] = ['i.chaoxing.com', 'passport2.chaoxing.com', 'chaoxing.com'];
        for (let si = 0; si < srcDomains.length; si++) {
          for (let di = 0; di < cxDomains.length; di++) {
            http.copyCookiesForDomain(srcDomains[si], cxDomains[di]);
          }
        }
        CasLoginService.getInstance().syncCookiesToWebView();
        const cxUrl: string = 'https://i.chaoxing.com/base';
        this.xgxtController.loadUrl(cxUrl);
      }).catch((err: Error) => {
        this.xgxtCleanup();
      });
      return;
    } catch (e) {
    }
    this.xgxtCleanup();
  }

  // 阶段2: 注入 JS 提取超星 UID
  private xgxtInjectChaoxing(): void {
    const js: string =
      '(function(){' +
      '  var s=document.body.innerHTML;' +
      '  var m=s.match(/photo\\.chaoxing\\.com\\/p\\/(\\d+)/);' +
      '  if(m){console.log("CX_UID:"+m[1]);}else{console.log("XGXT_ERR:no chaoxing uid");}' +
      '})();';
    this.xgxtController.runJavaScript(js);
  }

  // 处理提取到的超星 UID
  private async xgxtChaoxingResult(uid: string): Promise<void> {
    if (uid.length > 0 && uid !== 'none' && /^\d+$/.test(uid)) {
      await PreferenceUtil.putString('cx_uid', uid);
      this.downloadAndSetAvatar('https://photo.chaoxing.com/p/' + uid + '_80');
    } else {
    }
    this.xgxtCleanup();
  }

  // 清理 xgxt WebView 状态
  private xgxtCleanup(): void {
    clearTimeout(this.xgxtTimeoutId);
    this.xgxtPhase = 0;
    this.xgxtActive = false;
    this.userRefreshing = false;
  }

  // ==================== 缓存管理 ====================
  private formatBytes(bytes: number): string {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  // removeAllCache(true) 清全局磁盘+内存缓存，API 18+ 静态方法，无需 WebView
  // removeAllCache(true) 静态方法，API 18+，不需要 WebView 实例
  // 注意：不能用 setTimeout 包 updateCacheSize()，否则 @State 赋值不触发 UI 刷新
  private clearCache(): void {
    this.cacheSize = '清理中...';
    try {
      web_webview.WebviewController.removeAllCache(true);
    } catch (e) {
    }
    try {
      const moduleContext: common.Context = this.context.createModuleContext('entry');
      const paths: string[] = [moduleContext.cacheDir, moduleContext.cacheDir + '/web', this.context.cacheDir];
      for (let i = 0; i < paths.length; i++) {
        try {
          const entries = fileIo.listFileSync(paths[i]);
          for (let j = 0; j < entries.length; j++) {
            const dp: string = paths[i] + '/' + entries[j];
            if (dp.indexOf('/web/Cookies') >= 0 || dp.indexOf('/web/CookiesD') >= 0) continue;
            try { fileIo.rmdirSync(dp); } catch (_e) { try { fileIo.unlinkSync(dp); } catch (_e2) { /* skip */ } }
          }
        } catch (_e) { /* skip */ }
      }
    } catch (_e) { /* skip */ }
    this.updateCacheSize();
  }

  updateCacheSize(): void {
    storageStatistics.getCurrentBundleStats().then((dataSize: storageStatistics.BundleStats) => {
      this.cacheSize = this.formatBytes(dataSize.cacheSize);
    }).catch((_e: Error) => {
      this.cacheSize = '获取失败';
    });
  }

  // 把预览网格(PreviewCell)转成日历同步用的 SlimCell 网格
  private toSlimGrid(grid: PreviewCell[][][]): SlimCell[][][] {
    const slim: SlimCell[][][] = [];
    for (let d = 0; d <= 7; d++) {
      slim[d] = [];
      for (let s = 0; s <= 11; s++) {
        const cells: PreviewCell[] = grid[d]?.[s] ?? [];
        const slimRow: SlimCell[] = [];
        for (let i = 0; i < cells.length; i++) {
          const c: PreviewCell = cells[i];
          slimRow.push({
            name: c.name,
            teacher: c.teacher ?? '',
            classroom: c.classroom ?? '',
            day: c.day,
            startSection: c.startSection,
            endSection: c.endSection,
            weekList: c.weekList,
            isExam: c.isExam,
            isExperiment: c.isExperiment,
            experimentProject: c.experimentProject ?? '',
            examDate: c.examDate ?? '',
            examTimeDesc: c.examTimeDesc ?? '',
            examSeat: c.seat ?? '',
            weekNum: c.weekNum
          });
        }
        slim[d][s] = slimRow;
      }
    }
    return slim;
  }

  // 加载课表预览数据：读取本地缓存 → 解析classGrid → 提取接下来2节课
  loadClassPreview(): void {
    try {
      const semesterCode: string = SemesterUtil.getCurrentSemesterCode();
      const filePath: string = this.context.filesDir + '/class_table_' + semesterCode + '.json';
      if (!fileIo.accessSync(filePath)) {
        this.previewLoaded = true;
        return;
      }
      const file: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(filePath);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const decoder = util.TextDecoder.create('utf-8');
      const raw: string = decoder.decodeToString(new Uint8Array(buf));
      if (raw.length === 0) {
        this.previewLoaded = true;
        return;
      }
      // 解析classGrid（与ClassTablePage renderClassTable逻辑一致）
      const items: ClassItemModel[] = ClassService.parseClassTable(raw);
      const grid: PreviewCell[][][] = []; // [day][startSection] = PreviewCell[]
      for (let d = 0; d <= 7; d++) {
        grid[d] = [];
        for (let s = 0; s <= 11; s++) {
          grid[d][s] = [];
        }
      }
      for (let i = 0; i < items.length; i++) {
        const item: ClassItemModel = items[i];
        const weekList: boolean[] = this.parseWeekList(item.skzc);
        const day: number = parseInt(item.skxq) || 0;
        const startSec: number = parseInt(item.ksjc) || 0;
        const endSec: number = parseInt(item.jsjc) || 0;
        if (day < 1 || day > 7 || startSec < 1 || endSec < startSec) continue;
        if (day === 1) {
        }
        const cell = new PreviewCell();
        cell.name = item.kcm;
        cell.teacher = item.skjs;
        cell.classroom = item.jasmc;
        cell.day = day;
        cell.startSection = startSec;
        cell.endSection = endSec;
        cell.isExperiment = false;
        cell.weekNum = 0; // 普通课程跨多周
        cell.weekList = weekList;
        grid[day][startSec].push(cell);
      }
      // 合并实验数据
      this.mergeExpPreview(grid);
      // 合并物理实验数据（独立于其他实验）
      this.mergePhysicsPreview(grid);
      // 合并自定义课程
      this.mergeCustomPreview(grid);
      // 合并考试数据
      this.mergeExamPreview(grid);
      // 提取接下来2节课
      this.previewCells = this.getNextClasses(grid);
      // 同步更新日历快照（供 CalendarSyncService.autoSync 读取，实现登录后自动同步）
      CalendarSyncService.saveClassGridSnapshot(this.toSlimGrid(grid), 'MainPage.loadClassPreview');
      this.previewLoaded = true;
      if (DIAG2) {
        let expN = 0, examN = 0, cusN = 0, couN = 0;
        for (const c of this.previewCells) {
          if (c.isExam) examN++; else if (c.isExperiment) expN++; else if (c.isCustom) cusN++; else couN++;
        }
        hilog.info(DOMAIN, TAG, '[DIAG2] loadClassPreview 完成 预览条数=' + this.previewCells.length
          + ' (课程' + couN + ' 实验' + expN + ' 考试' + examN + ' 自定义' + cusN + ')');
      }
    } catch (e) {
      this.previewLoaded = true;
    }
  }

  // 解析周次字符串
  // 二进制格式: "111110111011111" (位置i=1表示第i+1周有课)
  // 逗号格式: "1-5,7-9,11-15"
  private parseWeekList(skzc: string): boolean[] {
    const list: boolean[] = [];
    for (let i = 0; i < 25; i++) list.push(false);
    if (!skzc || skzc.length === 0) return list;
    if (skzc.indexOf(',') >= 0) {
      // 逗号分隔格式
      const parts: string[] = skzc.split(',');
      for (let pi = 0; pi < parts.length; pi++) {
        const trimmed: string = parts[pi].trim();
        const dashIdx: number = trimmed.indexOf('-');
        if (dashIdx > 0) {
          const start: number = parseInt(trimmed.substring(0, dashIdx)) || 0;
          const end: number = parseInt(trimmed.substring(dashIdx + 1)) || 0;
          for (let w = start; w <= end && w < 25; w++) {
            if (w > 0) list[w] = true;
          }
        } else {
          const w: number = parseInt(trimmed) || 0;
          if (w > 0 && w < 25) list[w] = true;
        }
      }
    } else {
      // 二进制字符串格式: 位置i(0-based)的'1'表示第i+1周有课
      for (let i = 0; i < skzc.length && i < 24; i++) {
        if (skzc.charAt(i) === '1') {
          list[i + 1] = true;
        }
      }
    }
    return list;
  }

  // 合并实验缓存到预览grid
  private mergeExpPreview(grid: PreviewCell[][][]): void {
    const cached = PreferenceUtil.getString('sysj_exp_cache');
    if (cached.length === 0) return;
    try {
      const cacheObj: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
      const raw: Object[] = cacheObj['data'] as Object[];
      if (!(raw instanceof Array) || raw.length === 0) return;
      const items: Record<string, string>[] = raw as Record<string, string>[];
      for (let ei = 0; ei < items.length; ei++) {
        const item: Record<string, string> = items[ei];
        const weekday: number = parseInt(item['weekday']) || 0;
        const startSec: number = parseInt(item['startSection']) || 0;
        const endSec: number = parseInt(item['endSection']) || 0;
        if (weekday < 1 || weekday > 7 || startSec < 1) continue;
        const cell = new PreviewCell();
        cell.name = item['experimentName'] || '实验';
        cell.experimentProject = item['experimentProject'] || item['experimentName'] || '实验';
        cell.classroom = item['lab'] || '';
        cell.day = weekday;
        cell.startSection = startSec;
        cell.endSection = endSec > startSec ? endSec : startSec;
        cell.isExperiment = true;
        const expWeek: number = parseInt(item['week']) || 0;
        cell.weekNum = expWeek;
        // 与预览选择器(getNextClasses, 按 weekNum) 和导出计数(calcCounts/impE, 按 weekList) 保持一致：
        // 服务器实验为单周，同时填充 weekNum 与 weekList[week]=true，两路消费都不会漏。
        cell.weekList = [];
        for (let w = 0; w < 26; w++) cell.weekList.push(false);
        if (expWeek >= 1 && expWeek <= 25) cell.weekList[expWeek] = true;
        if (weekday <= 7 && startSec <= 11) {
          grid[weekday][startSec].push(cell);
        }
      }
    } catch (e) {
    }
  }

  // 合并物理实验缓存到预览grid
  private mergePhysicsPreview(grid: PreviewCell[][][]): void {
    const cached = PreferenceUtil.getString('physics_exp_cache');
    if (cached.length === 0) return;
    try {
      const cacheObj: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
      const raw: Object[] = cacheObj['data'] as Object[];
      if (!(raw instanceof Array) || raw.length === 0) return;
      const items: Record<string, string>[] = raw as Record<string, string>[];
      for (let ei = 0; ei < items.length; ei++) {
        const item: Record<string, string> = items[ei];
        const weekday: number = parseInt(item['weekday']) || 0;
        const startSec: number = parseInt(item['startSection']) || 0;
        const endSec: number = parseInt(item['endSection']) || 0;
        if (weekday < 1 || weekday > 7 || startSec < 1) continue;
        const cell = new PreviewCell();
        cell.name = item['experimentName'] || '物理实验';
        cell.experimentProject = item['experimentName'] || '物理实验';
        cell.classroom = item['lab'] || '';
        cell.day = weekday;
        cell.startSection = startSec;
        cell.endSection = endSec > startSec ? endSec : startSec;
        cell.isExperiment = true;
        const phyWeek: number = parseInt(item['week']) || 0;
        cell.weekNum = phyWeek;
        cell.weekList = [];
        for (let w = 0; w < 26; w++) cell.weekList.push(false);
        if (phyWeek >= 1 && phyWeek <= 25) cell.weekList[phyWeek] = true;
        if (weekday <= 7 && startSec <= 11) {
          grid[weekday][startSec].push(cell);
        }
      }
    } catch (e) {
    }
  }

  // 合并自定义课程到预览grid
  private mergeCustomPreview(grid: PreviewCell[][][]): void {
    try {
      const semCode: string = SemesterUtil.getCurrentSemesterCode();
      const customPath: string = this.context.filesDir + '/class_table_' + semCode + '_custom.json';
      if (!fileIo.accessSync(customPath)) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(customPath, fileIo.OpenMode.READ_ONLY);
      const stat: fileIo.Stat = fileIo.statSync(customPath);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(new Uint8Array(buf));
      const items: Object[] = JSON.parse(text) as Object[];
      // [DIAG2] 统计自定义列表里各类型数量（type 0=课程 1=考试 2=实验），确认编辑 exp->course 是否真的落盘为 type=0
      if (DIAG2) {
        let t0: number = 0, t1: number = 0, t2: number = 0;
        for (let i = 0; i < items.length; i++) {
          const it: Record<string, Object> = items[i] as Record<string, Object>;
          const tp: number = (it['type'] as number) || 0;
          if (tp === 1) t1++; else if (tp === 2) t2++; else t0++;
        }
        hilog.info(DOMAIN, TAG, '[DIAG2] mergeCustomPreview 读自定义列表 总数=' + items.length + ' 课程(0)=' + t0 + ' 考试(1)=' + t1 + ' 实验(2)=' + t2);
      }
      for (let i = 0; i < items.length; i++) {
        const item: Record<string, Object> = items[i] as Record<string, Object>;
        const type: number = (item['type'] as number) || 0;
        const day: number = item['day'] as number || 0;
        if (day < 1 || day > 7) continue;

        if (type === 1) {
          // 手动考试：与 mergeExamPreview / ClassTablePage.loadCustomCourses 一致处理
          const examDate: string = (item['examDate'] as string) || '';
          const examTimeStart: string = (item['examTimeStart'] as string) || '';
          const examTimeEnd: string = (item['examTimeEnd'] as string) || '';
          if (examDate.length === 0) continue;
          const exDate = new Date(examDate + 'T00:00:00');
          if (isNaN(exDate.getTime())) continue;
          // 由 examDate 反推学期周次（与 calcCurrentWeekFromNow 同公式，含 week_swift 偏移）
          const semStart = SemesterUtil.getSemesterStartDate(semCode);
          const swift: number = PreferenceUtil.getNumber('week_swift', 0);
          const dayMs: number = 86400000;
          const weekNum: number = Math.max(1,
            Math.floor((exDate.getTime() - semStart.getTime() - swift * 7 * dayMs) / dayMs / 7) + 1);
          const cell = new PreviewCell();
          cell.name = (item['name'] as string) || '考试';
          cell.classroom = (item['classroom'] as string) || '';
          cell.seat = (item['examSeat'] as string) || '';
          cell.day = day;
          cell.startSection = 0;
          cell.endSection = 0;
          cell.isCustom = true;
          cell.isExam = true;
          cell.weekNum = weekNum;
          cell.examDate = examDate;
          cell.examTimeDesc = (examTimeStart && examTimeEnd) ? (examTimeStart + '-' + examTimeEnd) : '';
          cell.weekList = [];
          for (let w = 0; w < 26; w++) cell.weekList.push(false);
          grid[day][0].push(cell);
          continue;
        }

        const startSec: number = item['startSection'] as number || 0;
        const endSec: number = item['endSection'] as number || 0;
        if (startSec < 1) continue;
        const wl: number[] = item['weekList'] as number[] || [];
        // 1-indexed: week w → list[w] = true（与 parseWeekList 和 getNextClasses 一致）
        // 旧数据用 0-indexed（week w → list[w-1]），长度 < 25 时做兼容迁移
        const isOldFormat: boolean = wl.length > 0 && wl.length < 26;
        const weekList: boolean[] = [];
        for (let w = 0; w < 26; w++) weekList.push(false);
        for (let w = 0; w < wl.length && w < 26; w++) {
          if (wl[w] === 1) {
            weekList[isOldFormat ? w + 1 : w] = true;
          }
        }
        const cell = new PreviewCell();
        cell.name = item['name'] as string || '';
        cell.classroom = item['classroom'] as string || '';
        cell.teacher = item['teacher'] as string || '';
        cell.day = day;
        cell.startSection = startSec;
        cell.endSection = endSec > startSec ? endSec : startSec;
        cell.isCustom = true;
        // 自定义 type=2 为实验：与 ClassTablePage.loadCustomCourses 对齐，必须打 isExperiment 标记
        // （否则预览会误判为 isCustom 显示「📌自定」，且日历快照/导出按 isExperiment 计数与导入都会漏掉）
        cell.isExperiment = (type === 2);
        if (type === 2) {
          cell.experimentProject = (item['experimentProject'] as string) || '';
        }
        cell.weekList = weekList;
        // 实验需要 weekNum 兜底：部分消费方（预览选择器 getNextClasses）按 weekNum 匹配；
        // 取 weekList 中首个有课周作代表（多周实验以首周代表，getNextClasses 已改为同时匹配 weekList）。
        // 普通课程 weekNum 保持 0（与 ClassTablePage.loadCustomCourses 一致）。
        if (type === 2) {
          for (let w = 1; w < weekList.length; w++) {
            if (weekList[w]) { cell.weekNum = w; break; }
          }
        }
        if (day <= 7 && startSec <= 11) {
          grid[day][startSec].push(cell);
        }
      }
    } catch (e) {
    }
  }

  // 合并考试数据到预览grid
  // exam_schedule_cache 格式: {"datas":{"wdksap":{"rows":[...]}}}（API 原始响应，键名大写）
  private mergeExamPreview(grid: PreviewCell[][][]): void {
    const cached: string = PreferenceUtil.getString('exam_schedule_cache');
    if (cached.length === 0) return;
    try {
      const root: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
      const datas: Record<string, Object> = root['datas'] as Record<string, Object>;
      if (!datas) return;
      const wdksap: Record<string, Object> = datas['wdksap'] as Record<string, Object>;
      const items: Object[] = wdksap ? wdksap['rows'] as Object[] : [];
      if (!items || items.length === 0) return;
      const startDate: Date = new Date(2026, 2, 2);
      for (let i = 0; i < items.length; i++) {
        const item: Record<string, Object> = items[i] as Record<string, Object>;
        const ksrq: string = item['KSRQ'] as string || '';
        const kssjms: string = item['KSSJMS'] as string || '';
        if (!ksrq || !kssjms) continue;
        const dateParts: string[] = ksrq.split('-');
        const examDate: Date = new Date(parseInt(dateParts[0]), parseInt(dateParts[1]) - 1, parseInt(dateParts[2]));
        const diffDays: number = Math.floor((examDate.getTime() - startDate.getTime()) / 86400000);
        const weekNum: number = Math.floor(diffDays / 7) + 1;
        const weekday: number = examDate.getDay() === 0 ? 7 : examDate.getDay();
        if (weekNum < 1 || weekNum > 25 || weekday < 1 || weekday > 7) continue;
        const spaceIdx: number = kssjms.indexOf(' ');
        const timeWithDay: string = spaceIdx >= 0 ? kssjms.substring(spaceIdx + 1) : kssjms;
        const parenIdx: number = timeWithDay.indexOf('(');
        const timeOnly: string = parenIdx >= 0 ? timeWithDay.substring(0, parenIdx) : timeWithDay;
        const cell = new PreviewCell();
        cell.name = ((item['KCM'] as string) || (item['KSMC'] as string) || '考试');
        cell.classroom = item['JASMC'] as string || '';
        cell.seat = item['ZWH'] as string || '';
        cell.day = weekday;
        cell.startSection = 0;
        cell.endSection = 0;
        cell.isExam = true;
        cell.weekNum = weekNum;
        cell.examTimeDesc = timeOnly;
        cell.examDate = ksrq;
        cell.experimentProject = (item['KCM'] as string) || (item['KSMC'] as string) || '';
        if (weekday <= 7) {
          grid[weekday][0].push(cell);
        }
      }
    } catch (e) {
      PreferenceUtil.putString('exam_schedule_cache', '');
    }
  }

  // 从classGrid中提取接下来2节课（今天+明天）
  private getNextClasses(grid: PreviewCell[][][]): PreviewCell[] {
    const candidates: PreviewCell[] = [];
    const now = new Date();
    let currentWeek: number = SemesterUtil.calcCurrentWeekFromNow();
    const dayOfWeek: number = now.getDay(); // 0=Sun, 1=Mon...
    const todayDay: number = dayOfWeek === 0 ? 7 : dayOfWeek; // 转为1-7（周一=1）

    // 当前时间对应的节次：找到还没结束的节次
    const nowMinutes: number = now.getHours() * 60 + now.getMinutes();
    let currentSection: number = 12; // 默认已过所有课
    for (let s = 1; s <= 11; s++) {
      const endTime: string = SECTION_TIMES[s - 1][1];
      const endMin: number = parseInt(endTime.substring(0, 2)) * 60 + parseInt(endTime.substring(3, 5));
      if (nowMinutes < endMin) {
        currentSection = s;
        break;
      }
    }

    // 计算数据实际最大周（普通课最后有课周 与 考试周 的较大值），避免硬编码上限误杀跨周显示
    let dataMaxWeek = 1;
    for (let d = 1; d <= 7; d++) {
      for (let s = 0; s <= 11; s++) {
        const arr = grid[d]?.[s];
        if (!arr) continue;
        for (const c of arr) {
          if (c.isExam) {
            if (c.weekNum > dataMaxWeek) dataMaxWeek = c.weekNum;
          } else {
            for (let i = 0; i < c.weekList.length; i++) {
              if (c.weekList[i] && i + 1 > dataMaxWeek) dataMaxWeek = i + 1;
            }
            // 实验兜底：weekNum 单独参与最大周计算（防止 weekList 缺漏时跨周显示被截断）
            if (c.isExperiment && c.weekNum > dataMaxWeek) dataMaxWeek = c.weekNum;
          }
        }
      }
    }
    // 学期已结束（超数据最后周）：钳制到最后一合法周，避免预览空白
    if (currentWeek > dataMaxWeek) currentWeek = dataMaxWeek;

    // 搜索范围：今天 + 明天（最多2天）
    for (let offset = 0; offset < 2; offset++) {
      let searchDay: number = todayDay + offset;
      let searchWeek: number = currentWeek;
      if (searchDay > 7) {
        searchDay = 1;
        searchWeek = currentWeek + 1;
      }
      if (searchWeek > dataMaxWeek + 1) continue;  // +1 允许跨周显示明天

      // 考试（存储在 section 0）
      const examCells: PreviewCell[] = grid[searchDay][0];
      for (let ci = 0; ci < examCells.length; ci++) {
        const cell: PreviewCell = examCells[ci];
        if (cell.isExam && cell.weekNum === searchWeek) {
          cell.day = searchDay;
          candidates.push(cell);
        }
      }

      // 遍历该天所有节次
      for (let s = 1; s <= 11; s++) {
        const cells: PreviewCell[] = grid[searchDay][s];
        for (let ci = 0; ci < cells.length; ci++) {
          const cell: PreviewCell = cells[ci];
          // 今天：跳过已全部结束的课程
          if (offset === 0 && cell.endSection < currentSection) continue;
          if (cell.isExperiment || cell.isExam) {
            // 实验/考试按 weekNum 匹配；同时兼容 weekList（多周自定义实验、服务器单周实验均命中）
            if (cell.weekNum === searchWeek ||
                (cell.weekList.length > searchWeek && cell.weekList[searchWeek])) {
              cell.day = searchDay;
              candidates.push(cell);
            }
          } else if (cell.isCustom) {
            const matchWeek = cell.weekList.length > searchWeek && cell.weekList[searchWeek];
            if (matchWeek) {
              cell.day = searchDay;
              candidates.push(cell);
            }
          } else {
            if (cell.weekList.length > searchWeek && cell.weekList[searchWeek]) {
              cell.day = searchDay;
              candidates.push(cell);
            }
          }
        }
      }
    }

    // 按时间排序：先按天，再按开始节次/考试时间
    candidates.sort((a: PreviewCell, b: PreviewCell): number => {
      if (a.day !== b.day) return a.day - b.day;
      // 同一天：比较开始时间
      const aMin: number = a.isExam ? this.examTimeToMinutes(a.examTimeDesc) : this.sectionToMinutes(a.startSection);
      const bMin: number = b.isExam ? this.examTimeToMinutes(b.examTimeDesc) : this.sectionToMinutes(b.startSection);
      return aMin - bMin;
    });

    return candidates.slice(0, 2);
  }

  // 考试时间描述转分钟数（如 "13:00-15:00" → 780）
  private examTimeToMinutes(desc: string): number {
    if (!desc || desc.length < 5) return 9999;
    const m = desc.match(/(\d{1,2}):(\d{2})/);
    if (m) return parseInt(m[1]) * 60 + parseInt(m[2]);
    return 9999;
  }

  // 节次转开始分钟数
  private sectionToMinutes(section: number): number {
    if (section < 1 || section > 11) return 9999;
    const startTime: string = SECTION_TIMES[section - 1][0];
    return parseInt(startTime.substring(0, 2)) * 60 + parseInt(startTime.substring(3, 5));
  }
  private openUrl(url: string) {
    try {
      this.context.openLink(url);
    } catch (e) {
      // openLink 失败时回退
    }
  }

  // 平板侧边栏
  @Builder
  Sidebar() {
    Column() {
      // 侧边栏标题
      Row() {
        Text('HiXD')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2979FF')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16 })

      List() {
        ForEach(this.menuNames, (name: string, i: number) => {
          ListItem() {
            Row() {
              Text(name)
                .fontSize(14)
                .fontColor(this.selectedMenuIndex === i ? '#2979FF' : '#333333')
            }
            .width('100%')
            .padding({ left: 16, top: 12, bottom: 12 })
            .backgroundColor(this.selectedMenuIndex === i ? (ThemeColors.isDark ? "#1A3350" : "#EEF4FF") : "transparent")
            .borderRadius(8)
            .margin({ left: 8, right: 8 })
            .onClick(() => {
              this.selectedMenuIndex = i;
              this.onMenuClick(i);
            })
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width(240)
    .height('100%')
    .backgroundColor(ThemeColors.bgCard)
  }

  // ===== 我的 Tab 行组件 =====
  @Builder themeRow() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(44).height(44).fill('#FF6D0022')
        Text('🌓').fontSize(22)
      }.margin({ right: 16 })
      Column() {
        Text('深色设置').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(this.currentThemeLabel).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor('#CCCCCC')
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => { this.showThemeDialog = true; animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.themeOpacity = 1; this.themeTranslate = 0; }); })
  }

  @Builder colorRow() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(44).height(44).fill(this.accentColor + '22')
        Circle().width(20).height(20).fill(this.accentColor)
      }.margin({ right: 16 })
      Column() {
        Text('主题色').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(this.accentIdx === -1 ? '自定义' : (ACCENT_PRESETS[this.accentIdx]?.[2] ?? '')).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor('#CCCCCC')
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => { this.showColorPicker = true; animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.colorOpacity = 1; this.colorTranslate = 0; }); })
  }

  @Builder bgRow() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(44).height(44).fill('#607D8B22')
        Text('🖼️').fontSize(22)
      }.margin({ right: 16 })
      Column() {
        Text('课表背景').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(this.bgShow ? '已设置图片' : '未自定义').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor('#CCCCCC')
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      // 加载当前设置
      this.bgShow = PreferenceUtil.getBool('class_bg_show', false);
      this.bgOpacityVal = PreferenceUtil.getNumber('class_bg_opacity', 60);
      const savedPath: string = PreferenceUtil.getString('class_bg_path', '');
      if (savedPath.length > 0) {
        try {
          this.bgPath = fileUri.getUriFromPath(savedPath);
          this.bgOriPath = savedPath;
        } catch (_) {
          this.bgPath = '';
          this.bgOriPath = '';
        }
      } else {
        this.bgPath = '';
        this.bgOriPath = '';
      }
      this.showBgDialog = true;
      animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.bgOpacity = 1; this.bgTranslate = 0; });
    })
  }

  @Builder semesterRow() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(44).height(44).fill('#546E7A22')
        Text('📅').fontSize(22)
      }.margin({ right: 16 })
      Column() {
        Text('学期设置').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(SemesterUtil.formatSemester(SemesterUtil.getCurrentSemesterCode())).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor('#CCCCCC')
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      const cur = SemesterUtil.getCurrentSemesterCode();
      const parts = cur.split('-');
      this.pickSemYear = parseInt(parts[0]);
      this.pickSemPart = parseInt(parts[2]) || 2;
      this.pickWeekSwift = PreferenceUtil.getNumber('week_swift', 0);
      this.showSemesterDialog = true;
      animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.semOpacity = 1; this.semTranslate = 0; });
    })
  }

  @Builder logoutRow() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(44).height(44).fill('#FF525222')
        Text('🔓').fontSize(22)
      }.margin({ right: 16 })
      Column() {
        Text('退出登录').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text('清除登录状态').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor('#CCCCCC')
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      this.showLogoutDialog = true;
      animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.logoutOpacity = 1; this.logoutTranslate = 0; });
    })
  }

  @Builder cacheRow() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(44).height(44).fill('#8BC34A22')
        Text('🗑️').fontSize(22)
      }.margin({ right: 16 })
      Column() {
        Text('清除缓存').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text('当前 ' + this.cacheSize).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor('#CCCCCC')
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => { this.clearCache(); })
  }

  // 侧边栏菜单点击路由
  @Builder
  navDestinationBuilder(name: string) {
    if (name === 'ClassTablePage') {
      ClassTablePage({ pageInfo: this.pageInfo })
    } else if (name === 'ExperimentPage') {
      ExperimentPage({ pageInfo: this.pageInfo })
    } else if (name === 'ExamPage') {
      ExamPage({ pageInfo: this.pageInfo })
    } else if (name === 'ScorePage') {
      ScorePage({ pageInfo: this.pageInfo })
    } else if (name === 'EmptyClassroomPage') {
      EmptyClassroomPage({ pageInfo: this.pageInfo })
    } else if (name === 'LibraryPage') {
      LibraryPage({ pageInfo: this.pageInfo })
    } else if (name === 'SchoolCardPage') {
      SchoolCardPage({ pageInfo: this.pageInfo })
    } else if (name === 'PortalWeb_Dingshui') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '订水系统', url: 'https://order.xidian.edu.cn/mobile/thirdoauth/oauth2Xidian/1', isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Baoxiu') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '后勤报修', url: 'https://ids.xidian.edu.cn/authserver/login?service=https%3A%2F%2Fids.xidian.edu.cn%2Fauthserver%2Foauth2.0%2FcallbackAuthorize%3Fclient_id%3D869608421533880320%26redirect_uri%3Dhttp%253A%252F%252Frepair.xidian.edu.cn%252Fappsys%252FxidianCasLogin%252FoauthLogin%26response_type%3Dcode%26state%3Dhome%26client_name%3DCasOAuthClient', isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Space') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '空间预约', url: 'http://libspace.xidian.edu.cn', isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Portal') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '移动门户', url: 'https://xxcapp.xidian.edu.cn/site/xidianPage/home' , useWeChatUA: true , keepWeChatUA: true , isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Ruisi') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '睿思导航', url: 'https://nav.xdruisi.cn/', isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Net') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '校园网登录', url: 'https://zfw.xidian.edu.cn/', isTablet: this.isTablet, useIncognito: true })
    } else if (name === 'PortalWeb_SchoolCard') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '校园卡服务', url: 'https://v8scan.xidian.edu.cn/home/openXDOAuth2Page', isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Mail') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '学生邮箱', url: 'https://edu.icoremail.net/', isTablet: this.isTablet })
    } else if (name === 'SchoolNetPage') {
      SchoolNetPage({ pageInfo: this.pageInfo })
    } else if (name === 'ElectricityPage') {
      ElectricityPage({ pageInfo: this.pageInfo })
    } else if (name === 'FaqPage') {
      FaqPage({ pageInfo: this.pageInfo, isTablet: this.isTablet })
    } else if (name === 'AboutPage') {
      AboutPage({ pageInfo: this.pageInfo, isTablet: this.isTablet })
    } else if (name === 'CalendarExportPage') {
      CalendarExportPage({ pageInfo: this.pageInfo, isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Dianfei') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '水电缴费', url: 'https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=https://ignypt.xidian.edu.cn/revenueH5/login?opcode=MPAY&appid=200260318155520600' , isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Physics') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '物理计算', url: 'https://experiment-helper.wizzstudio.com/#/', isTablet: this.isTablet })
    } else if (name === 'AttendancePage') {
      AttendancePage({ pageInfo: this.pageInfo })
    } else if (name === 'DormWaterPage') {
      DormWaterPage({ pageInfo: this.pageInfo })
    } else if (name === 'SportPage') {
      SportPage({ pageInfo: this.pageInfo })
    }
  }

  onMenuClick(index: number): void {
    // index 9 = 我的 → 清空导航栈，显示 MyTab
    if (index === 9) {
      this.selectedMenuIndex = 9;
      this.pageInfo.clear();
      return;
    }
    const pageNames: string[] = [
      'ClassTablePage',
      'ExperimentPage',
      'ExamPage',
      'ScorePage',
      'EmptyClassroomPage',
      'LibraryPage',
      'SchoolCardPage',
      'SchoolNetPage',
      'ElectricityPage',
    ];
    if (index >= 0 && index < pageNames.length && pageNames[index].length > 0) {
      this.selectedMenuIndex = index;
      this.pageInfo.clear();
      this.pageInfo.pushPath({ name: pageNames[index] });
    }
  }

  // ── 主题弹窗 ──
  onColorModeChange(): void {
    // @StorageProp + @Watch 确保 AppStorage 变化时 @State 自动同步
    this.currentThemeLabel = this.buildThemeLabel(this.systemColorMode);
  }

  selectTheme(mode: number): void {
    this.closeThemeDialog();
    PreferenceUtil.putNumber('theme_color_mode', mode);
    // 直接更新 @State 标签（确保 TabContent 内 Builder 实时刷新）
    this.currentThemeLabel = this.buildThemeLabel(mode);
    AppStorage.setOrCreate('currentColorMode', mode);
    if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      ThemeColors.applyFollowSystem(getContext());
    } else {
      ThemeColors.applyManual(mode, getContext());
    }
    // 切换主题时刷新主题色（深/浅模式不同色值）
    const idx: number = AppStorage.get('accent_index') as number ?? 0;
    const isDark = mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ||
      (mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET && ThemeColors.isDark);
    AppStorage.setOrCreate('accent_color', AccentColors.colorForTheme(isDark, idx));
  }

  // 切换到"我的"Tab时刷新主题标签（非激活Tab被HdsTabs冻结，@State不触发重渲染）
  refreshThemeLabel(): void {
    const savedMode: number = PreferenceUtil.getNumber('theme_color_mode',
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    this.currentThemeLabel = this.buildThemeLabel(savedMode);
  }

  buildThemeLabel(mode: number): string {
    if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) return '当前：跟随系统';
    if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) return '当前：深色模式';
    return '当前：浅色模式';
  }

  getThemeLabel(): string {
    return this.currentThemeLabel;
  }

  // 未登录时由 aboutToAppear 直接 router.replaceUrl 到 LoginPage，
  // 不再保留本地登录引导页（LoginPage 本身已是完整登录界面）

  build() {
    Stack() {
    if (this.isLoggedIn) {
    Navigation(this.pageInfo) {
      if (deviceInfo.distributionOSApiVersion >= 60100) {
        HdsTabs({ controller: this.tabsController }) {
          TabContent() {
            this.HomeTab()
          }.tabBar(this.TabBuilder(0, '🏠', '主页'))
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          TabContent() {
            this.PortalTab()
          }.tabBar(this.TabBuilder(1, '🔧', '更多功能'))
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          TabContent() {
            this.MyTab()
          }.tabBar(this.TabBuilder(2, '👤', '我的'))
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .vertical(false)
        .barPosition(BarPosition.End)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .barOverlap(true)
        .barBackgroundBlurStyle(BlurStyle.Thin)
        .barFloatingStyle({
          barBottomMargin: this.navIndicatorHeight,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        })
        .onAnimationStart((_index: number, targetIndex: number) => {
          this.currentIndex = targetIndex;
          if (targetIndex === 0) { this.loadClassPreview(); }
          else if (targetIndex === 2) { this.updateCacheSize(); this.refreshThemeLabel(); }
        })
        .width('100%')
        .layoutWeight(1)
      } else {
        Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
          TabContent() {
            this.HomeTab()
          }.tabBar(this.TabBuilder(0, '🏠', '主页'))
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          TabContent() {
            this.PortalTab()
          }.tabBar(this.TabBuilder(1, '🔧', '更多功能'))
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          TabContent() {
            this.MyTab()
          }.tabBar(this.TabBuilder(2, '👤', '我的'))
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .scrollable(false)
        .barMode(BarMode.Fixed)
        .barBackgroundColor('#FFFFFF')
        .barOverlap(true)
        .barFloatingStyle({ barBottomMargin: this.navIndicatorHeight })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onChange((index: number) => {
          this.currentIndex = index;
          if (index === 0) { this.loadClassPreview(); }
          else if (index === 2) { this.updateCacheSize(); this.refreshThemeLabel(); this.loadUserInfo(); }
        })
        .width('100%')
        .layoutWeight(1)
      }
    }
    .mode(NavigationMode.Auto)
    .navBarWidth('340vp')
    .navBarWidthRange(['200vp', '50%'])
    .enableDragBar(true)
    .hideTitleBar(true)
    .hideToolBar(true)
    .hideNavBar(this.portalFullscreen)
    .navDestination(this.navDestinationBuilder)
    .onNavigationModeChange((mode: NavigationMode) => {
      this.isSplit = mode;
    })
    // 隐藏 xgxt WebView：加载 jbxxapp SPA 后用 JS 抓取个人信息
    if (this.xgxtActive) {
      Web({ src: this.xgxtUrl, controller: this.xgxtController })
        .width('300px')
        .height('300px')
        .position({ x: -400, y: 0 })
        .onPageEnd((event) => {
          if (event && event.url) {
            if (this.xgxtPhase === 1 && event.url.indexOf('xgxt.xidian.edu.cn') >= 0) {
              this.xgxtInjectFetch();
            } else if (this.xgxtPhase === 2 && event.url.indexOf('i.chaoxing.com') >= 0) {
              this.xgxtInjectChaoxing();
            }
          } else {
          }
        })
        .onConsole((event): boolean => {
          if (event && event.message) {
            const msg: string = event.message.getMessage();
            if (msg.indexOf('XGXT_INFO:') === 0) {
              const raw: string = msg.substring(10);
              this.xgxtProcessResult(raw);
              return true;
            }
            if (msg.indexOf('XGXT_ERR:') === 0) {
              this.xgxtCleanup();
              return true;
            }
            if (msg.indexOf('CX_UID:') === 0) {
              const uid: string = msg.substring(7).trim();
              this.xgxtChaoxingResult(uid);
              return true;
            }
          }
          return false;
        })
        .onErrorReceive(() => {
          this.xgxtCleanup();
        })
        .domStorageAccess(true)
        .javaScriptAccess(true)
    }
    }
    else {
      // 未登录瞬时占位：aboutToAppear 已 replaceUrl 到 LoginPage，这里仅避免黑屏
      Column() { }.width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
    }
    // 滑块验证码 overlay（原地弹窗，不跳页）—— 必须在 Navigation 之后，确保显示在最上层
    if (this.showCaptcha) {
      this.CaptchaOverlay()
    }
    // 物理实验密码弹窗
    if (this.showPhyPwdDialog || this.phyOpacity > 0) {
    Column() {
      Column() {
        Row() {
          Text('物理实验设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor('#999999') }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.closePhyPwdDialog(); })
        }.width('100%').margin({ bottom: 16 })
        TextInput({ placeholder: '输入物理实验密码', text: this.phyPwdInput })
          .type(InputType.Password)
          .width('100%').height(44).fontSize(15)
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .onChange((v: string) => { this.phyPwdInput = v; })
        Row() {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput)
            .onClick(() => { this.closePhyPwdDialog(); })
          Button('保存').layoutWeight(1).height(40).margin({ left: 12 })
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor())
            .onClick(() => {
              if (this.phyPwdInput.length > 0) {
                PreferenceUtil.putString('physics_pwd', this.phyPwdInput).catch(() => {});
                this.phyPwdStatus = '已设置';
                this.closePhyPwdDialog();
              }
            })
        }.width('100%').margin({ top: 16 })
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.phyOpacity)
      .translate({ y: this.phyTranslate })
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.phyOpacity)
    .hitTestBehavior(this.showPhyPwdDialog ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => { this.closePhyPwdDialog(); })
    }
    // 校园网密码弹窗
    if (this.showSchoolnetPwdDialog || this.schoolnetPwdOpacity > 0) {
    Column() {
      Column() {
        Row() {
          Text('校园网密码').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('\u2715').fontSize(18).fontColor('#999999') }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.closeSchoolnetPwdDialog(); })
        }.width('100%').margin({ bottom: 16 })
        Text('用于查询自服务平台(zfw)的详细流量数据').fontSize(12).fontColor(ThemeColors.textSecondary)
          .width('100%').margin({ bottom: 12 })
        TextInput({ placeholder: '输入校园网密码', text: this.schoolnetPwdInput })
          .type(InputType.Password)
          .width('100%').height(44).fontSize(15)
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .onChange((v: string) => { this.schoolnetPwdInput = v; })
        Row() {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput)
            .onClick(() => { this.closeSchoolnetPwdDialog(); })
          Button('保存').layoutWeight(1).height(40).margin({ left: 12 })
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor())
            .onClick(() => {
              if (this.schoolnetPwdInput.length > 0) {
                PreferenceUtil.putString('schoolnet_password', this.schoolnetPwdInput).catch(() => {});
                this.schoolnetPwdStatus = '已设置';
                this.closeSchoolnetPwdDialog();
              }
            })
        }.width('100%').margin({ top: 16 })
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.schoolnetPwdOpacity)
      .translate({ y: this.schoolnetPwdTranslate })
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.schoolnetPwdOpacity)
    .hitTestBehavior(this.showSchoolnetPwdDialog ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => { this.closeSchoolnetPwdDialog(); })
    }
    // 体育密码弹窗
    if (this.showSportPwdDialog || this.sportPwdOpacity > 0) {
    Column() {
      Column() {
        Row() {
          Text('体育系统密码').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('\u2715').fontSize(18).fontColor('#999999') }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.closeSportPwdDialog(); })
        }.width('100%').margin({ bottom: 16 })
        Text('用于登录体育体测系统（tybjxgl），与统一身份认证密码不同').fontSize(12).fontColor(ThemeColors.textSecondary)
          .width('100%').margin({ bottom: 12 })
        TextInput({ placeholder: '输入体育系统密码', text: this.sportPwdInput })
          .type(InputType.Password)
          .width('100%').height(44).fontSize(15)
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .onChange((v: string) => { this.sportPwdInput = v; })
        Row() {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput)
            .onClick(() => { this.closeSportPwdDialog(); })
          Button('保存').layoutWeight(1).height(40).margin({ left: 12 })
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor())
            .onClick(() => {
              if (this.sportPwdInput.length > 0) {
                PreferenceUtil.putString('sport_password', this.sportPwdInput).catch(() => {});
                this.sportPwdStatus = '已设置';
                this.closeSportPwdDialog();
              }
            })
        }.width('100%').margin({ top: 16 })
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.sportPwdOpacity)
      .translate({ y: this.sportPwdTranslate })
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.sportPwdOpacity)
    .hitTestBehavior(this.showSportPwdDialog ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => { this.closeSportPwdDialog(); })
    }
    // 深色模式选择弹窗
    if (this.showThemeDialog || this.themeOpacity > 0) {
    Column() {
      Column() {
        Row() {
          Text('深色设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor('#999999') }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.closeThemeDialog(); })
        }.width('100%').margin({ bottom: 16 })
        Button('浅色').width('100%').height(44)
          .backgroundColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? this.accentColor : ThemeColors.bgInput)
          .fontColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? '#FFFFFF' : ThemeColors.textPrimary)
          .onClick(() => { this.selectTheme(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT); })
        Button('深色').width('100%').height(44).margin({ top: 8 })
          .backgroundColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? this.accentColor : ThemeColors.bgInput)
          .fontColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#FFFFFF' : ThemeColors.textPrimary)
          .onClick(() => { this.selectTheme(ConfigurationConstant.ColorMode.COLOR_MODE_DARK); })
        Button('跟随系统').width('100%').height(44).margin({ top: 8 })
          .backgroundColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET ? this.accentColor : ThemeColors.bgInput)
          .fontColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET ? '#FFFFFF' : ThemeColors.textPrimary)
          .onClick(() => { this.selectTheme(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET); })
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.themeOpacity)
      .translate({ y: this.themeTranslate })
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.themeOpacity)
    .hitTestBehavior(this.showThemeDialog ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => { this.closeThemeDialog(); })
    }
    // 主题色选择弹窗
    if (this.showColorPicker || this.colorOpacity > 0) {
    Column() {
      Column() {
        Row() {
          Text('选择主题色').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor('#999999') }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.closeColorPickerDialog(); })
        }.width('100%').margin({ bottom: 16 })
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(ACCENT_PRESETS, (preset: string[], idx: number) => {
            Column() {
              Stack() {
                Circle().width(40).height(40).fill(ThemeColors.isDark ? preset[1] : preset[0])
                if (idx === this.accentIdx) {
                  Text('✓').fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                }
              }
              Text(preset[2]).fontSize(10).fontColor(ThemeColors.textSecondary).margin({ top: 3 })
            }.margin({ right: 10, bottom: 10 })
            .onClick(() => { AccentColors.select(idx); this.closeColorPickerDialog(); })
          }, (preset: string[], idx: number) => String(idx))
        }.width('100%')
        // 自定义色号输入
        Row() {
          Text('自定义').fontSize(12).fontColor(ThemeColors.textHint)
          Text('#').fontSize(13).fontColor(ThemeColors.textHint).margin({ left: 8, right: 2 })
          TextInput({ placeholder: '色号', text: this.customHex })
            .width(72).height(34).fontSize(13)
            .maxLength(6)
            .placeholderColor(ThemeColors.textHint)
            .backgroundColor(ThemeColors.bgInput).borderRadius(8)
            .onChange((v: string) => { this.customHex = v.replace(/[^0-9A-Fa-f]/g, ''); })
          Row() {
            Circle().width(16).height(16).fill(this.customHex.length === 6 ? ('#' + this.customHex) : '#CCCCCC')
          }.width(32).height(32).borderRadius(8).backgroundColor(ThemeColors.bgInput)
          .justifyContent(FlexAlign.Center).margin({ left: 6, right: 6 })
          Button('应用').height(34).fontSize(12)
            .backgroundColor(this.customHex.length === 6 ? this.accentColor : '#CCCCCC')
            .fontColor('#FFFFFF').borderRadius(8)
            .enabled(this.customHex.length === 6)
            .onClick(() => {
              if (AccentColors.selectCustom('#' + this.customHex)) {
                this.closeColorPickerDialog();
                this.customHex = '';
              }
            })
          Button('调色').height(34).fontSize(12)
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor()).borderRadius(8).margin({ left: 6 })
            .onClick(() => { this.showWheelPicker = true; animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.wheelOpacity = 1; this.wheelTranslate = 0; }); })
        }.width('100%').margin({ top: 8 })
        .padding({ top: 10 }).border({ width: { top: 1 }, color: '#E0E0E0', style: BorderStyle.Dashed })
      }
      .width('85%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.colorOpacity)
      .translate({ y: this.colorTranslate })
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.colorOpacity)
    .hitTestBehavior(this.showColorPicker ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => { this.closeColorPickerDialog(); })
    }
    // 无极取色盘
    if (this.showWheelPicker || this.wheelOpacity > 0) {
    Column() {
      Column() {
        Row() {
          Text('无极取色').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor('#999999') }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.closeWheelPickerDialog(); })
        }.width('100%').margin({ bottom: 12 })
        ColorWheelPicker({
          onCancel: () => {
            this.closeWheelPickerDialog();
            this.closeColorPickerDialog();
          }
        })
      }
      .width('310vp').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.wheelOpacity)
      .translate({ y: this.wheelTranslate })
      .onClick(() => { /* 吞掉事件 */ })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.wheelOpacity)
    .hitTestBehavior(this.showWheelPicker ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => { this.closeWheelPickerDialog(); })
    }
    // 学期设置弹窗
    if (this.showSemesterDialog || this.semOpacity > 0) {
    Column() {
        Column() {
          Row() {
            Text('学期设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            Blank()
            Row() { Text('✕').fontSize(18).fontColor('#999999') }
              .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.closeSemesterDialog(); })
          }.width('100%').margin({ bottom: 14 })
          // 当前学期
          Text(SemesterUtil.formatSemester(SemesterUtil.getCurrentSemesterCode()))
            .fontSize(14).fontColor(ThemeColors.textSecondary).margin({ bottom: 14 }).width('100%')
          // 学年度
          Text('学年度').fontSize(12).fontColor(ThemeColors.textHint).margin({ bottom: 6 })
          Row() {
            Button('‹').fontSize(22).width(40).height(40).fontColor(this.accentColor)
              .backgroundColor(Color.Transparent)
              .onClick(() => { if (this.pickSemYear > 2016) this.pickSemYear--; })
            Text(this.pickSemYear + '-' + (this.pickSemYear + 1)).fontSize(18).fontWeight(FontWeight.Medium)
              .fontColor(ThemeColors.textPrimary).fontFamily('monospace').width(120).textAlign(TextAlign.Center)
            Button('›').fontSize(22).width(40).height(40).fontColor(this.accentColor)
              .backgroundColor(Color.Transparent)
              .onClick(() => { if (this.pickSemYear < new Date().getFullYear() + 1) this.pickSemYear++; })
          }.width('100%').justifyContent(FlexAlign.Center).margin({ bottom: 14 })
          // 学期选择
          Text('学期').fontSize(12).fontColor(ThemeColors.textHint).margin({ bottom: 6 })
          Row() {
            Button('秋季学期').height(40).fontSize(14)
              .backgroundColor(this.pickSemPart === 1 ? this.accentColor : ThemeColors.bgInput)
              .fontColor(this.pickSemPart === 1 ? '#FFFFFF' : ThemeColors.textPrimary)
              .borderRadius(10).layoutWeight(1)
              .onClick(() => { this.pickSemPart = 1; })
            Button('春季学期').height(40).fontSize(14)
              .backgroundColor(this.pickSemPart === 2 ? this.accentColor : ThemeColors.bgInput)
              .fontColor(this.pickSemPart === 2 ? '#FFFFFF' : ThemeColors.textPrimary)
              .borderRadius(10).layoutWeight(1).margin({ left: 10 })
              .onClick(() => { this.pickSemPart = 2; })
          }.width('100%').margin({ bottom: 16 })
          // 开学日期预览
          Text('开学日期：' + this.buildSemesterStartLabel())
            .fontSize(13).fontColor(ThemeColors.textSecondary).margin({ bottom: 6 }).width('100%')
          Text('💡 此日期所在周为「第 1 周」，不是精确到某一天开学').fontSize(11).fontColor(ThemeColors.textHint)
            .margin({ bottom: 14 }).width('100%')
          // 周次偏移
          Text('周次偏移（±几周）').fontSize(12).fontColor(ThemeColors.textHint).margin({ bottom: 6 })
          Row() {
            Button('−').fontSize(22).width(44).height(36).fontColor(this.accentColor)
              .backgroundColor(Color.Transparent)
              .onClick(() => { if (this.pickWeekSwift > -8) this.pickWeekSwift--; })
            Text(this.pickWeekSwift >= 0 ? '+' + this.pickWeekSwift.toString() : this.pickWeekSwift.toString())
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              .fontFamily('monospace').width(56).textAlign(TextAlign.Center)
            Button('+').fontSize(22).width(44).height(36).fontColor(this.accentColor)
              .backgroundColor(Color.Transparent)
              .onClick(() => { if (this.pickWeekSwift < 8) this.pickWeekSwift++; })
          }.width('100%').justifyContent(FlexAlign.Center).margin({ bottom: 16 })
          // 按钮
          Row() {
            Button('恢复默认').height(40).fontSize(14)
              .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary).borderRadius(10)
              .layoutWeight(1)
              .onClick(() => {
                PreferenceUtil.putString('current_semester', '');
                PreferenceUtil.putNumber('week_swift', 0);
                this.pickWeekSwift = 0;
                this.semesterToast = '已恢复默认开学日期设置';
                setTimeout(() => { this.semesterToast = ''; }, 1200);
              })
            Button('保存').height(40).fontSize(14)
              .backgroundColor(this.accentColor).fontColor(this.accentTextColor()).borderRadius(10)
              .layoutWeight(1).margin({ left: 10 })
              .onClick(() => {
                const code = this.pickSemYear + '-' + (this.pickSemYear + 1) + '-' + this.pickSemPart;
                PreferenceUtil.putString('current_semester', code);
                PreferenceUtil.putNumber('week_swift', this.pickWeekSwift);
                this.closeSemesterDialog();
              })
          }.width('100%')
          if (this.semesterToast.length > 0) {
            Text(this.semesterToast).fontSize(13).fontColor('#4CAF50').margin({ top: 12 })
          }
        }
        .width('85%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
        .shadow({ radius: 20, color: '#30000000' })
        .opacity(this.semOpacity)
        .translate({ y: this.semTranslate })
        .onClick(() => {})
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeColors.overlay)
      .opacity(this.semOpacity)
      .hitTestBehavior(this.showSemesterDialog ? HitTestMode.Default : HitTestMode.None)
      .onClick(() => { this.closeSemesterDialog(); })
    }
    // 退出登录确认弹窗
    if (this.showLogoutDialog || this.logoutOpacity > 0) {
    Column() {
      Column() {
        Text('⚠️').fontSize(40).margin({ bottom: 8 })
        Text('确认退出登录？').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).margin({ bottom: 4 })
        Text('退出后需重新输入账号密码登录').fontSize(13)
          .fontColor(ThemeColors.textSecondary).margin({ bottom: 20 })
        Row() {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary)
            .borderRadius(10)
            .onClick(() => { this.closeLogoutDialog(); })
          Button('确认退出').layoutWeight(1).height(40).margin({ left: 12 })
            .backgroundColor('#FF5252').fontColor('#FFFFFF').borderRadius(10)
            .onClick(async () => {
              this.closeLogoutDialog();
              await PreferenceUtil.putString('ids_account', '');
              await PreferenceUtil.putString('login_password', '');
              await PreferenceUtil.putString('user_name', '');
              await PreferenceUtil.putString('user_major', '');
              await PreferenceUtil.putString('user_college', '');
              await PreferenceUtil.putString('user_grade', '');
              await PreferenceUtil.putString('user_gender', '');
              await PreferenceUtil.putString('user_avatar', '');
              await HttpUtil.getInstance().clearCookies();
              // 必须清掉 mod_auth_cas 偏好：getCookiesForDomain 对 ehall 域会把它当
              // cookie 冗余注入，否则退登后重进仍会被 tryAutoRestoreLogin 判定为已登录
              await PreferenceUtil.delete('mod_auth_cas');
              await PreferenceUtil.putBool('is_logged_in', false);
              // 清理业务缓存（对齐 Flutter 退登删缓存，换账号不残留）
              await this.clearBusinessCache();
              // 一并退出独立的宿舍水机(iLife798)与校园网(ZFW)会话，实现"完全退出"
              await PreferenceUtil.putString('dorm_water_token', '');
              await PreferenceUtil.putString('dorm_water_uid', '');
              await PreferenceUtil.putString('dorm_water_eid', '');
              await HttpUtil.getInstance().clearCookies('zfw.xidian.edu.cn');
              this.userDisplayName = '';
              this.username = '';
              this.userMajor = '';
              this.userCollege = '';
              this.userAvatarUrl = '';
              this.isLoggedIn = false;
              this.loginStatus = 'not_logged_in';
AppStorage.set('loginStatus', 'not_logged_in');
              // 退登后直接进入登录页（不再依赖本地引导页占位）
              router.replaceUrl({ url: 'pages/login/LoginPage' });
            })
        }.width('100%')
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.logoutOpacity)
      .translate({ y: this.logoutTranslate })
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.logoutOpacity)
    .hitTestBehavior(this.showLogoutDialog ? HitTestMode.Default : HitTestMode.None)
    .zIndex(100)
    .onClick(() => { this.closeLogoutDialog(); })
    }
    // 自定义课表背景弹窗
    if (this.showBgDialog || this.bgOpacity > 0) {
    Column() {
      Column() {
        // 标题
        Text('自定义课表背景').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).margin({ bottom: 16 })
        // 开关
        Row() {
          Text('启用自定义背景').fontSize(15).fontColor(ThemeColors.textPrimary)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.bgShow })
            .selectedColor(this.accentColor)
            .onChange((value: boolean) => {
              this.bgShow = value;
            })
        }.width('100%').margin({ bottom: 12 })
        // 图片预览
        Stack({ alignContent: Alignment.Center }) {
          Image(this.bgPath.length > 0 ? this.bgPath : $r('app.media.background'))
            .width('100%')
            .aspectRatio(this.isTablet ? 4 / 3 : 3 / 4)
            .constraintSize({ maxHeight: 300 })
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
            .opacity(this.bgPath.length > 0 ? (this.bgShow ? this.bgOpacityVal / 100 : 0.15) : 0.06)
            .interpolation(ImageInterpolation.Medium)
          if (this.bgPath.length === 0) {
            Text('📷 点此选择图片').fontSize(14).fontColor(ThemeColors.textHint)
          } else if (!this.bgShow) {
            Text('已关闭').fontSize(13).fontColor('#FFFFFF')
              .backgroundColor('rgba(0,0,0,0.5)').borderRadius(6)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          }
        }
        .width('100%').borderRadius(10)
        .backgroundColor(ThemeColors.bgInput)
        .onClick(() => { this.selectBgImage(); })
        .margin({ bottom: 12 })
        // 选择图片按钮
        Button('选择图片').fontSize(14)
          .backgroundColor(ThemeColors.isDark ? '#1A3A5C' : '#E3F2FD')
          .fontColor(this.accentColor)
          .borderRadius(8)
          .margin({ bottom: 12 })
          .onClick(() => { this.selectBgImage(); })
        // 不透明度滑动条
        Row() {
          Text('不透明度').fontSize(13).fontColor(ThemeColors.textSecondary)
          Slider({
            value: this.bgOpacityVal,
            min: 30,
            max: 100,
            step: 5
          }).width('60%')
            .trackColor(ThemeColors.bgInput)
            .selectedColor(this.accentColor)
            .onChange((value: number) => { this.bgOpacityVal = value; })
          Text(this.bgOpacityVal + '%').fontSize(13)
            .fontColor(ThemeColors.textPrimary).width(36).textAlign(TextAlign.End)
        }.width('100%').margin({ bottom: 16 })
        // 按钮行
        Row({ space: 10 }) {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary)
            .borderRadius(10)
            .onClick(() => { this.closeBgDialog(); })
          Button('保存').layoutWeight(1).height(40)
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor())
            .borderRadius(10)
            .onClick(() => { this.saveBgSettings(); })
        }.width('100%')
      }
      .width('85%').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.bgOpacity)
      .translate({ y: this.bgTranslate })
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.bgOpacity)
    .hitTestBehavior(this.showBgDialog ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => { this.closeBgDialog(); })
    }
    // 版本更新提示弹窗
    if (this.showUpdateDialog && this.updateInfo) {
    Column() {
      Column() {
        Text('🎉 发现新版本').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).margin({ bottom: 8 })
        Text('最新版本：v' + this.updateInfo.version).fontSize(14).fontColor(ThemeColors.textSecondary).margin({ bottom: 4 })
        // 更新日志
        if (this.updateInfo.changelog && this.updateInfo.changelog.length > 0) {
          Column() {
            Text('更新内容').fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              .width('100%').margin({ bottom: 6 })
            ForEach(this.updateInfo.changelog, (line: string) => {
              Text('• ' + line).fontSize(12).fontColor(ThemeColors.textSecondary).lineHeight(20)
                .width('100%')
            }, (line: string, __: number) => line)
          }
          .width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .margin({ bottom: 16 })
        }
        Row({ space: 10 }) {
          Button('稍后再说').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary)
            .borderRadius(10)
            .onClick(() => {
              this.showUpdateDialog = false;
              if (this.skipVersion.length > 0) PreferenceUtil.putString('skip_version', this.skipVersion);
            })
          Button('立即查看').layoutWeight(1).height(40)
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor())
            .borderRadius(10)
            .onClick(() => {
              this.showUpdateDialog = false;
              if (this.skipVersion.length > 0) PreferenceUtil.putString('skip_version', this.skipVersion);
              if (this.updateInfo) {
                try { this.context.openLink(this.updateInfo.url); } catch (_) {}
              }
            })
        }.width('100%')
        // 以后不再提示
        Row() {
          Checkbox({ name: 'skip_' + (this.updateInfo?.version ?? ''), group: 'update_skip' })
            .selectedColor(this.accentColor)
            .width(16).height(16)
            .onChange((value: boolean) => { this.skipVersion = value ? (this.updateInfo?.version ?? '') : ''; })
          Text('此版本不再提示').fontSize(12).fontColor(ThemeColors.textHint).margin({ left: 6 })
        }.margin({ top: 12 })
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .onClick(() => { this.showUpdateDialog = false; })
    }
    // 底部提示 Toast
    if (this.updateToast.length > 0) {
      Text(this.updateToast)
        .fontSize(14).fontColor('#FFFFFF')
        .backgroundColor('rgba(0,0,0,0.75)')
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(20)
        .position({ x: '50%', y: '90%' }).markAnchor({ x: '50%' })
        .zIndex(10)
    }
    if (this.bgToast.length > 0) {
      Text(this.bgToast)
        .fontSize(14).fontColor('#FFFFFF')
        .backgroundColor('rgba(0,0,0,0.75)')
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(20)
        .position({ x: '50%', y: '90%' }).markAnchor({ x: '50%' })
        .zIndex(10)
    }
    // 隐私协议弹窗（首次启动）
    if (this.showPrivacyDialog) {
      Column() {
        Column() {
          // 应用图标
          Image($r('app.media.hixd_icon')).width(56).height(56).borderRadius(14)
            .margin({ top: 24 })
          Text('HiXD').fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary).margin({ top: 8, bottom: 16 })
          Scroll() {
            Text() {
              Span('欢迎使用 HiXD！在使用本应用前，请您仔细阅读并同意')
                .fontSize(14).fontColor(ThemeColors.textSecondary)
              Span('《用户协议》').fontSize(14)
                .fontColor((AppStorage.get('accent_color') as string ?? '#2979FF'))
                .onClick(() => { this.openPrivacyUrl('user'); })
              Span('和').fontSize(14).fontColor(ThemeColors.textSecondary)
              Span('《隐私政策》').fontSize(14)
                .fontColor((AppStorage.get('accent_color') as string ?? '#2979FF'))
                .onClick(() => { this.openPrivacyUrl('privacy'); })
              Span('。').fontSize(14).fontColor(ThemeColors.textSecondary)
              Span('\n\n本应用需要您使用学号和密码登录西安电子科技大学统一身份认证系统，以获取课表、成绩等教务数据。您的账号密码仅用于校内认证，不会上传至任何第三方服务器。')
                .fontSize(14).fontColor(ThemeColors.textSecondary)
            }.lineHeight(22)
          }.height(160).padding({ left: 4, right: 4 })

          Column({ space: 12 }) {
            Button('不同意').width('80%').height(44).fontSize(15)
              .backgroundColor(Color.Transparent).fontColor(ThemeColors.textSecondary)
              .onClick(() => { this.disagreePrivacy(); })
            Button('同意并继续').width('80%').height(44).fontSize(17)
              .backgroundColor(this.accentColor).fontColor(this.accentTextColor())
              .borderRadius(24)
              .onClick(() => { this.agreePrivacy(); })
          }.margin({ top: 16, bottom: 20 })
        }
        .width('85%').padding(20).borderRadius(13).backgroundColor(ThemeColors.bgCard)
        .shadow({ radius: 16, color: '#00000020' })
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
      .backgroundColor('#4D000000')
      .zIndex(100)
    }
    // 隐私政策/用户协议全文查看
    if (this.showPolicyViewer) {
      Column() {
        Column() {
          Row() {
            Text(this.policyTitle).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            Blank()
            Text('✕').fontSize(18).fontColor('#999999')
              .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
              .textAlign(TextAlign.Center)
              .onClick(() => { this.showPolicyViewer = false; })
          }.width('100%').margin({ bottom: 16 })
          Scroll() {
            Text(this.policyContent).fontSize(14).fontColor(ThemeColors.textSecondary).lineHeight(24)
          }.layoutWeight(1)
        }
        .width('90%').height('80%').padding(20).borderRadius(13).backgroundColor(ThemeColors.bgCard)
        .shadow({ radius: 16, color: '#00000020' })
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
      .backgroundColor('#4D000000')
      .zIndex(101)
    }
    } // closes Stack
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // 根据主题色亮度选择白色或黑色文字
  private accentTextColor(): string {
    const hex = this.accentColor.replace('#', '');
    const r = parseInt(hex.substring(0, 2), 16);
    const g = parseInt(hex.substring(2, 4), 16);
    const b = parseInt(hex.substring(4, 6), 16);
    const lum = (0.299 * r + 0.587 * g + 0.114 * b); // W3C 亮度公式
    return lum > 160 ? '#333333' : '#FFFFFF';
  }

  private accentBgIsLight(): boolean {
    const hex = this.accentColor.replace('#', '');
    const r = parseInt(hex.substring(0, 2), 16);
    const g = parseInt(hex.substring(2, 4), 16);
    const b = parseInt(hex.substring(4, 6), 16);
    const lum = (0.299 * r + 0.587 * g + 0.114 * b);
    return lum > 160;
  }

  // 根据当前选中的学年+学期+周次偏移计算开学日期预览
  private buildSemesterStartLabel(): string {
    const code = this.pickSemYear + '-' + (this.pickSemYear + 1) + '-' + this.pickSemPart;
    const d = SemesterUtil.getSemesterStartDate(code);
    // 加上周次偏移
    d.setDate(d.getDate() + this.pickWeekSwift * 7);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const weekNames = ['日', '一', '二', '三', '四', '五', '六'];
    return y + '/' + m + '/' + day + '（周' + weekNames[d.getDay()] + '）';
  }

  // 课表预览卡片
  @Builder
  ClassPreviewCard() {
    // 强制感知课表数据变化
    if (this.ctUpdated.length > 0) { /* do nothing, trigger re-eval */ }
    if (this.previewLoaded && this.previewCells.length > 0) {
      Column() {
        // 标题行
        Row() {
          Text('📅')
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Text('  课程预告')
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Blank()
          Text('查看课表 >')
            .fontSize(12).fontColor(this.accentColor)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        // 课程列表（时间轴样式）
        ForEach(this.previewCells, (cell: PreviewCell, index: number) => {
          Row() {
            // 左侧时间
            Column() {
              if (cell.isExam) {
                Text('考试')
                  .fontSize(13).fontWeight(FontWeight.Bold).fontColor('#E91E63')
              } else {
                Text(SECTION_TIMES[cell.startSection - 1][0])
                  .fontSize(13).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                Text(SECTION_TIMES[cell.endSection - 1][1])
                  .fontSize(10).fontColor(ThemeColors.textSecondary)
              }
            }
            .width(46).alignItems(HorizontalAlign.End).padding({ right: 4 })

            // 时间轴节点 + 连线
            Column() {
              Circle().width(10).height(10)
                .fill(cell.isExam ? '#E91E63' : (cell.isExperiment ? '#FF9800' : (cell.isCustom ? '#66BB6A' : '#2979FF')))
                .margin({ top: 4 })
              if (index < this.previewCells.length - 1) {
                Column().width(2).layoutWeight(1).backgroundColor('#E0E0E0').margin({ top: 2 })
              }
            }
            .width(16).height('100%').alignItems(HorizontalAlign.Center)

            // 课程信息
            Column() {
              Row() {
                if (cell.isExam) {
                  Text('📝考试')
                    .fontSize(12).fontColor('#E91E63')
                } else if (cell.isExperiment) {
                  Text('🧪实验')
                    .fontSize(12).fontColor(ThemeColors.warning)
                } else if (cell.isCustom) {
                  Text('📌自定')
                    .fontSize(12).fontColor('#66BB6A')
                }
                Text(cell.name)
                  .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .margin({ left: cell.isExam || cell.isExperiment || cell.isCustom ? 6 : 0 })
                Text(cell.day === this.getTodayDay() ? '今天' : '明天')
                  .fontSize(11).fontColor(cell.day === this.getTodayDay() ? this.accentTextColor() : '#FFFFFF')
                  .backgroundColor(cell.day === this.getTodayDay() ? this.accentColor : '#43A047')
                  .borderRadius(10)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              }
              Row() {
                if (cell.isExam && cell.examTimeDesc.length > 0) {
                  Text(cell.examTimeDesc)
                    .fontSize(12).fontColor('#E91E63')
                }
                if (cell.teacher.length > 0) {
                  Text('  ' + cell.teacher)
                    .fontSize(12).fontColor(ThemeColors.textSecondary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                if (cell.classroom.length > 0) {
                  Text('  ' + cell.classroom)
                    .fontSize(12).fontColor(ThemeColors.textSecondary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                if (cell.seat.length > 0) {
                  Text('  ' + cell.seat)
                    .fontSize(12).fontColor('#888888')
                }
              }.margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .padding({ left: 8 })
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
        }, (cell: PreviewCell, index: number) => index.toString())
      }
      .width('100%')
      .backgroundColor(ThemeColors.bgCard)
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 12 })
      .shadow({ radius: 4, color: '#1A000000', offsetX: 0, offsetY: 2 })
      .onClick(() => { this.pageInfo.clear();
        this.pageInfo.pushPath({ name: 'ClassTablePage', onPop: () => {
          // 课表页弹出、主页已可见：同步重载预览（不可用 setTimeout，@State 赋值在定时器中不触发重渲染）
          if (DIAG2) { hilog.info(DOMAIN, TAG, '[DIAG2] ClassTablePage.onPop → loadClassPreview(可见重载)'); }
          this.loadClassPreview();
        } }); })
    } else if (this.previewLoaded && this.previewCells.length === 0) {
      // 没课
      Column() {
        // 标题行
        Row() {
          Text('📅')
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Text('  课程预告')
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Blank()
          Text('查看课表 >')
            .fontSize(12).fontColor(this.accentColor)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        Text('🌸 😴 ✨ 🌙 🐢').fontSize(28).padding({ top: 8, bottom: 4 })
        Text('当前没课，好好休息吧！')
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
          .padding({ bottom: 16 })
      }
      .width('100%')
      .backgroundColor(ThemeColors.bgCard)
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 12 })
      .shadow({ radius: 4, color: '#1A000000', offsetX: 0, offsetY: 2 })
      .onClick(() => { this.pageInfo.clear();
        this.pageInfo.pushPath({ name: 'ClassTablePage', onPop: () => {
          // 课表页弹出、主页已可见：同步重载预览（不可用 setTimeout，@State 赋值在定时器中不触发重渲染）
          if (DIAG2) { hilog.info(DOMAIN, TAG, '[DIAG2] ClassTablePage.onPop → loadClassPreview(可见重载)'); }
          this.loadClassPreview();
        } }); })
    }
  }

  private getTodayDay(): number {
    const dayOfWeek: number = new Date().getDay();
    return dayOfWeek === 0 ? 7 : dayOfWeek;
  }

  // 电费缓存解析（只解析一次，缓存本次渲染周期）
  private _elecParsed: ElecData | null = null;
  private getElecData(): ElecData {
    if (this._elecParsed) return this._elecParsed;
    try {
      this._elecParsed = JSON.parse(this.elCache) as ElecData;
    } catch (_e) {
      this._elecParsed = { remain: '--', date: '', metID: '' };
    }
    return this._elecParsed;
  }
  private getElecRemain(): string { return this.getElecData().remain || '--'; }
  private getElecDate(): string { return this.getElecData().date || ''; }
  private getElecMetID(): string { return this.getElecData().metID || ''; }

  // 主页电费卡片
  @Builder
  ElectricityCard() {
    Column() {
      Row() {
        Text('⚡ 宿舍电费').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        Blank()
        if (this.elCache.length > 0) {
          Text('更新: ' + this.getElecDate()).fontSize(11).fontColor(ThemeColors.textSecondary)
        }
      }.width('100%').padding({ left: 16, right: 16, top: 12 })

      if (this.elCache.length > 0) {
        Row() {
          Text(this.getElecRemain()).fontSize(36).fontWeight(FontWeight.Bold).fontColor('#FF6D00')
          Text(' kWh').fontSize(16).fontColor(ThemeColors.textSecondary).margin({ left: 4 })
        }.padding({ left: 16, right: 16, bottom: 4 })

        Row() {
          Text('电表: ' + this.getElecMetID()).fontSize(11).fontColor(ThemeColors.textSecondary)
          Blank()
          Button('查看详细').fontSize(12).height(28)
            .backgroundColor('#FF6D0020').fontColor('#FF6D00')
            .borderRadius(14).padding({ left: 10, right: 10 })
            .onClick(() => { this.pageInfo.pushPath({ name: 'PortalWeb_Dianfei' }); })
        }.width('100%').padding({ left: 16, right: 16, bottom: 12 })
      } else {
        Row() {
          Text('点击查询宿舍电费\u4F59\u989D').fontSize(13).fontColor(ThemeColors.textSecondary).layoutWeight(1)
          Button('查询').fontSize(12).height(28)
            .backgroundColor('#FF6D00').fontColor('#FFFFFF')
            .borderRadius(14).padding({ left: 10, right: 10 })
            .onClick(() => { this.pageInfo.pushPath({ name: 'ElectricityPage' }); })
        }.width('100%').padding({ left: 16, right: 16, bottom: 12 })
      }
    }
    .backgroundColor(ThemeColors.bgCard).borderRadius(12)
    .margin({ left: 16, right: 16, top: 8, bottom: 4 })
    .shadow({ radius: 8, color: '#00000010', offsetY: 2 })
  }
  // Tab 按钮构建
  @Builder
  TabBuilder(index: number, icon: string, title: string) {
    Column() {
      Text(icon)
        .fontSize(22)
        .fontColor(this.currentIndex === index ? '#2979FF' : '#999999')
      Text(title)
        .fontSize(11)
        .fontColor(this.currentIndex === index ? '#2979FF' : '#999999')
        .margin({ top: 2 })
    }
    .width('100%')
    .height('52vp')
    .justifyContent(FlexAlign.Center)
  }

  // ==================== 主页 Tab ====================
  @Builder
  HomeTab() {
    Column() {
      // 顶部导航栏
      Row() {
        Column() {
          Text('HiXD').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
          if (this.loginStatus === 'ok') {
            Text('已登录').fontSize(11).fontColor(this.accentBgIsLight() ? '#338A3E' : '#80CC80')
          } else if (this.loginStatus === 'expired') {
            Text('登录已过期').fontSize(11).fontColor(this.accentBgIsLight() ? '#C62828' : '#CC8080')
          } else if (this.loginStatus === 'not_logged_in') {
            Text('未登录').fontSize(11).fontColor(this.accentTextColor() + 'CC')
          } else if (this.loginStatus === 'offline') {
            Text('离线模式').fontSize(11).fontColor(this.accentBgIsLight() ? '#BF6A00' : '#FFCC80')
          } else if (this.loginStatus === 'timeout') {
            Text('登录超时').fontSize(11).fontColor(this.accentBgIsLight() ? '#C62828' : '#CC8080')
          } else if (this.loginStatus === 'checking') {
            Text('正在验证...').fontSize(11).fontColor(this.accentTextColor() + 'CC')
          }
        }
        Blank()
        if (this.loginStatus === 'ok') {
          Stack() {
            Circle().width(32).height(32).fill('#FFFFFF33')
            if (this.userAvatarUrl) {
              Image(this.userAvatarUrl).width(32).height(32).borderRadius(16).objectFit(ImageFit.Cover)
            } else {
              Text('🎓').fontSize(18).fontColor('#FFFFFFCC')
            }
          }.width(32).height(32)
          Text(this.userDisplayName || this.username || '已登录').fontSize(13)
            .fontColor(this.accentTextColor() + 'CC').margin({ left: 8 })
        } else {
          Button(this.loginStatus === 'expired' || this.loginStatus === 'timeout' ? '重新登录' : '登录')
            .height(28).fontSize(12).fontColor('#FFFFFF')
            .backgroundColor('#FFFFFF33').borderRadius(14)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              if (this.loginStatus === 'expired' || this.loginStatus === 'offline') {
                this.doRelogin();
              } else {
                router.pushUrl({ url: 'pages/login/LoginPage' });
              }
            })
        }
      }
      .width('100%').height(52 + this.statusBarHeight).padding({ left: 20, right: 16, top: this.statusBarHeight })
      .backgroundColor(this.accentColor)

      // 课表预览卡片
      // 课表预览卡片（ct_updated 变化时由 @Watch('onCtUpdated') 触发刷新）
      this.ClassPreviewCard()

      // 电费查询已移至功能菜单

      // 功能菜单列表(始终显示)
      Column() {
        Refresh({ refreshing:
        $$this.homeRefreshing }) {
          List({ space: 8 }) {
          ForEach(this.homeMenuOrder, (name: string, idx: number) => {
            ListItem() {
              Row() {
                if (this.homeSortOn) {
                  Column({ space: 2 }) {
                    Text('⬆').fontSize(14).onClick(() => { this.homeMenuMoveUp(idx); })
                    Text('⬇').fontSize(14).onClick(() => { this.homeMenuMoveDown(idx); })
                  }.width(28).alignItems(HorizontalAlign.Center).margin({ right: 4 })
                }
                this.HomeMenuItemByName(name)
              }.width('100%')
            }
          }, (name: string) => name)

          // 排序
          ListItem() {
            Row() {
              Blank()
              Text(this.homeSortOn ? '完成' : '⇅ 排序').fontSize(13).fontColor(this.accentColor)
            }.width('100%').padding({ right: 6, top: 4, bottom: 4 })
            .onClick(() => { this.homeSortOn = !this.homeSortOn; })
          }
          ListItem().height(deviceInfo.distributionOSApiVersion >= 60100 ? 60 : 48)
        }
        .padding({ left: 16, right: 16, top: 8 })
        .layoutWeight(1)
        }
        .onRefreshing(() => {
          this.homeRefreshing = true;
          this.checkLogin();
          setTimeout(() => { this.homeRefreshing = false; }, 2000);
        })
      }.width('100%').layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
  }

  // ==================== 更多功能 Tab ====================
  @Builder
  PortalTab() {
    Column() {
      // 顶部
      Row() {
        Text('更多功能').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
      }
      .width('100%').height(52 + this.statusBarHeight).padding({ left: 20, top: this.statusBarHeight })
      .backgroundColor(this.accentColor)
      Divider().color('#F0F0F0')

      List({ space: 8 }) {
        // 功能列表
        ForEach(this.portalMenuOrder, (name: string, idx: number) => {
          ListItem() {
            Row() {
              if (this.portalSortOn) {
                Column({ space: 2 }) {
                  Text('⬆').fontSize(14).onClick(() => { this.portalMenuMoveUp(idx); })
                  Text('⬇').fontSize(14).onClick(() => { this.portalMenuMoveDown(idx); })
                }.width(28).alignItems(HorizontalAlign.Center).margin({ right: 4 })
              }
              this.PortalMenuItemByName(name)
            }.width('100%')
          }
        }, (name: string) => name)

        // 排序
        ListItem() {
          Row() {
            Blank()
            Text(this.portalSortOn ? '完成' : '⇅ 排序').fontSize(13).fontColor(this.accentColor)
          }.width('100%').padding({ right: 6, top: 4, bottom: 4 })
          .onClick(() => { this.portalSortOn = !this.portalSortOn; })
        }
        ListItem().height(deviceInfo.distributionOSApiVersion >= 60100 ? 60 : 48)
      }
      .padding({ left: 16, right: 16, top: 8 })
      .layoutWeight(1)

    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
  }

  // ==================== 我的 Tab ====================
  @Builder
  MyTab() {
    Column() {
      // 顶部
      Row() {
        Text('我的').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
      }
      .width('100%').height(52 + this.statusBarHeight).padding({ left: 20, top: this.statusBarHeight })
      .backgroundColor(this.accentColor)
      Divider().color('#F0F0F0')

      // 用户区域：有缓存数据就显示信息卡片，否则显示登录入口
      if (this.userDisplayName || this.username) {
        // 用户信息卡片 — 顶部主题色横幅 + 内容区
        Column() {
          // 顶部主题色装饰条
          Row()
            .width('100%').height(64)
            .linearGradient({
              direction: GradientDirection.Right,
              colors: [[this.accentColor, 0], [this.accentColor + 'CC', 0.5], [this.accentColor + '66', 1]]
            })

          // 内容区：头像 overlap 装饰条 + 信息
          Row() {
            // 头像 — 大号，带白边
            Stack() {
              Circle().width(72).height(72).fill('#FFFFFF')
              if (this.userAvatarUrl) {
                Image(this.userAvatarUrl).width(66).height(66).borderRadius(33).objectFit(ImageFit.Cover)
              } else {
                Stack() {
                  Circle().width(66).height(66).fill(this.accentColor + '18')
                  Text('🎓').fontSize(32)
                }.width(66).height(66).borderRadius(33)
              }
            }
            .width(72).height(72)
            .offset({ y: -20 })
            .margin({ left: 20 })

            // 右侧信息区
            Column() {
              // 姓名行 + 刷新按钮
              Row() {
                Text(this.userDisplayName || this.username || '已登录')
                  .fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.userGender && this.userGender !== '') {
                  Text(this.userGender === '男' ? '♂' : '♀')
                    .fontSize(18).fontWeight(FontWeight.Bold)
                    .fontColor(this.userGender === '男' ? '#5D9CEC' : '#EC5D8A')
                    .margin({ left: 6 })
                }
                Blank()
                // 刷新按钮
                Row() {
                  if (this.userRefreshing) {
                    LoadingProgress().width(16).height(16).color(this.accentColor)
                  } else {
                    Text('🔄').fontSize(16)
                  }
                }
                .width(32).height(32)
                .justifyContent(FlexAlign.Center)
                .borderRadius(16)
                .backgroundColor(this.accentColor + '10')
                .onClick(() => { this.refreshUserInfo(); })
              }.width('100%')

              // 学院 · 专业
              if (this.userCollege || this.userMajor) {
                Row() {
                  if (this.userCollege) {
                    Text(this.userCollege).fontSize(12).fontColor(ThemeColors.textSecondary).maxLines(1)
                  }
                  if (this.userCollege && this.userMajor) {
                    Text(' · ').fontSize(12).fontColor(ThemeColors.textHint)
                  }
                  if (this.userMajor) {
                    Text(this.userMajor).fontSize(12).fontColor(ThemeColors.textSecondary)
                      .layoutWeight(1).textOverflow({ overflow: TextOverflow.Ellipsis }).maxLines(1)
                  }
                }.margin({ top: 4 })
              }
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            .margin({ left: 14, right: 20, top: 8 })
          }.width('100%')

          // 标签行 — 与信息区左对齐（头像左边距20 + 头像72 + 间距14 = 106vp）
          Row() {
            if (this.userStudentType) {
              Text(this.userStudentType)
                .fontSize(11).fontColor('#FFFFFF')
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.accentColor)
                .borderRadius(10)
            } else {
              Text(PreferenceUtil.getBool('role') ? '研究生' : '本科生')
                .fontSize(11).fontColor('#FFFFFF')
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.accentColor)
                .borderRadius(10)
            }
            if (this.userGrade) {
              Text(this.userGrade + '级')
                .fontSize(11).fontColor(ThemeColors.textSecondary)
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.accentColor + '12')
                .borderRadius(10)
                .margin({ left: 8 })
            }
            if (this.userClassName) {
              Text(this.userClassName + '班')
                .fontSize(11).fontColor(ThemeColors.textSecondary)
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .backgroundColor(this.accentColor + '12')
                .borderRadius(10)
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .padding({ left: 106, right: 20, top: 8, bottom: 16 })
        }
        .width('100%')
        .backgroundColor(ThemeColors.bgCard)
        .borderRadius(16)
        .shadow({ radius: 6, color: '#00000012', offsetY: 2 })
        .margin({ left: 14, right: 14, top: 10 })
        .clip(true)
      } else {
        // 未登录提示
        Button('登录以使用完整功能')
          .width('90%').height(44).fontSize(15).fontColor('#FFFFFF')
          .backgroundColor('#2979FF').borderRadius(22)
          .margin({ top: 24 })
          .onClick(() => { router.pushUrl({ url: 'pages/login/LoginPage' }); })
      }

      // 菜单（始终显示）
      List({ space: 12 }) {
        // ===== 个性化 =====
        ListItem() {
          Column() {
            Text('个性化').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .padding({ left: 16, top: 14, bottom: 10 })
            Divider().color('#E0E0E0').strokeWidth(0.5).margin({ left: 16, right: 16 })
            this.themeRow()
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            this.colorRow()
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            this.bgRow()
          }
          .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
        }

        // ===== 学习 =====
        if (this.isLoggedIn) {
        ListItem() {
          Column() {
            Text('学习').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .padding({ left: 16, top: 14, bottom: 10 })
            Divider().color('#E0E0E0').strokeWidth(0.5).margin({ left: 16, right: 16 })
            this.semesterRow()
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            // 物理实验设置
            Row() {
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(44).height(44).fill('#7B1FA222')
                Text('⚛️').fontSize(22)
              }.margin({ right: 16 })
              Column() {
                Text('物理实验设置').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text(this.phyPwdStatus).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor('#CCCCCC')
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.phyPwdInput = PreferenceUtil.getString('physics_pwd');
              this.showPhyPwdDialog = true;
              animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.phyOpacity = 1; this.phyTranslate = 0; });
            })
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            // 校园网密码设置
            Row() {
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(44).height(44).fill('#00ACC122')
                Text('🌐').fontSize(22)
              }.margin({ right: 16 })
              Column() {
                Text('校园网密码').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text(this.schoolnetPwdStatus).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor('#CCCCCC')
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.schoolnetPwdInput = PreferenceUtil.getString('schoolnet_password');
              this.showSchoolnetPwdDialog = true;
              animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.schoolnetPwdOpacity = 1; this.schoolnetPwdTranslate = 0; });
            })
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            // 体育密码设置
            Row() {
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(44).height(44).fill('#2E7D3222')
                Text('🏀').fontSize(22)
              }.margin({ right: 16 })
              Column() {
                Text('体育系统密码').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text(this.sportPwdStatus).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor('#CCCCCC')
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.sportPwdInput = PreferenceUtil.getString('sport_password');
              this.showSportPwdDialog = true;
              animateTo({ duration: 300, curve: Curve.EaseOut }, () => { this.sportPwdOpacity = 1; this.sportPwdTranslate = 0; });
            })
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            // 导入系统日历
            Row() {
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(44).height(44).fill('#1E88E522')
                Text('📅').fontSize(22)
              }.margin({ right: 16 })
              Column() {
                Text('导入系统日历').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text('课程/实验/考试导入日历').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor('#CCCCCC')
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => { this.pageInfo.clear(); this.pageInfo.pushPath({ name: 'CalendarExportPage' }); })
          }
          .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
        }
        }

        // ===== 其他 =====
        ListItem() {
          Column() {
            Text('其他').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .padding({ left: 16, top: 14, bottom: 10 })
            Divider().color('#E0E0E0').strokeWidth(0.5).margin({ left: 16, right: 16 })
            // 关于软件
            Row() {
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(44).height(44).fill('#2196F322')
                Text('ℹ️').fontSize(22)
              }.margin({ right: 16 })
              Column() {
                Text('关于软件').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text('用户协议 · 隐私政策 · 检查更新').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor('#CCCCCC')
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => { this.pageInfo.clear(); this.pageInfo.pushPath({ name: 'AboutPage' }); })
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            // 常见问题
            Row() {
              Stack({ alignContent: Alignment.Center }) {
                Circle().width(44).height(44).fill('#79554822')
                Text('❓').fontSize(22)
              }.margin({ right: 16 })
              Column() {
                Text('常见问题').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                Text('使用帮助和问题反馈').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor('#CCCCCC')
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => { this.pageInfo.clear(); this.pageInfo.pushPath({ name: 'FaqPage' }); })
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            this.logoutRow()
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 60, right: 16 })
            this.cacheRow()
          }
          .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
        }
        ListItem().height(deviceInfo.distributionOSApiVersion >= 60100 ? 60 : 48)
      }
      .padding({ left: 16, right: 16, top: 8 })
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
  }

  // ==================== 通用菜单项 ====================
  @Builder
  HomeMenuItemByName(name: string) {
    if (name === 'Score') {
      this.MenuItemBuilder('📝', '成绩查询', '查看各科成绩和GPA', '#43A047',
        () => { this.homeMenuItemClick('Score'); })
    } else if (name === 'Exam') {
      this.MenuItemBuilder('📋', '考试安排', '查看考试时间地点', '#FB8C00',
        () => { this.homeMenuItemClick('Exam'); })
    } else if (name === 'Library') {
      this.MenuItemBuilder('📚', '图书馆', '搜索图书和借阅', '#8E24AA',
        () => { this.homeMenuItemClick('Library'); })
    } else if (name === 'SchoolNet') {
      this.MenuItemBuilder('🌐', '校园网', '查看校园网用量', '#00ACC1',
        () => { this.homeMenuItemClick('SchoolNet'); })
    } else if (name === 'EmptyClass') {
      this.MenuItemBuilder('🏫', '空闲教室', '查找空闲自习室', '#F4511E',
        () => { this.homeMenuItemClick('EmptyClass'); })
    } else if (name === 'SchoolCard') {
      this.SchoolCardBuilder()
    } else if (name === 'Attendance') {
      this.MenuItemBuilder('📋', '考勤查询', '查看课程签到和到课率', '#E91E63',
        () => { this.homeMenuItemClick('Attendance'); })
    } else if (name === 'Water') {
      this.MenuItemBuilder('🚰', '宿舍水机', '远程控制宿舍饮水机', '#00ACC1',
        () => { this.homeMenuItemClick('Water'); })
    } else if (name === 'Experiment' && !PreferenceUtil.getBool('role')) {
      this.MenuItemBuilder('🔬', '实验信息', '查看实验课程安排', '#5C6BC0',
        () => { this.homeMenuItemClick('Experiment'); })
    } else if (name === 'Electricity') {
      this.MenuItemBuilder('\u26a1', '水电查询', '查看宿舍水费电费', '#FF6D00',
        () => { this.homeMenuItemClick('Electricity'); })
    } else if (name === 'Sport') {
      this.MenuItemBuilder('🏀', '体育信息', '体测成绩与课程安排', '#2E7D32',
        () => { this.homeMenuItemClick('Sport'); })
    }
  }

  @Builder
  PortalMenuItemByName(name: string) {
    if (name === 'Dianfei') {
      this.MenuItemBuilder('💰', '水电缴费', '线上一键缴纳水电费用', '#E65100',
        () => { this.pageInfo.clear(); this.pageInfo.pushPath({ name: 'PortalWeb_Dianfei' }); })
    } else if (name === 'Dingshui') {
      this.MenuItemBuilder('💧', '订水系统', '再忙也不要忘记喝水呦！', '#0277BD',
        () => { this.pageInfo.pushPath({ name: 'PortalWeb_Dingshui' }); })
    } else if (name === 'Baoxiu') {
      this.MenuItemBuilder('🛠️', '后勤报修', '足不出户提交报修', '#5D4037',
        () => { this.pageInfo.pushPath({ name: 'PortalWeb_Baoxiu' }); })
    } else if (name === 'Space') {
      this.MenuItemBuilder('🏢', '空间预约', '找一个可以集体讨论的地方', '#1565C0',
        () => { this.pageInfo.pushPath({ name: 'PortalWeb_Space' }); })
    } else if (name === 'Portal') {
      this.MenuItemBuilder('📱', '移动门户', '校园服务一网打尽', '#00695C',
        () => { this.pageInfo.pushPath({ name: 'PortalWeb_Portal' }); })
    } else if (name === 'Ruisi') {
      this.MenuItemBuilder('🧭', '睿思导航', '补充其他功能', '#4527A0',
        () => { this.pageInfo.pushPath({ name: 'PortalWeb_Ruisi' }); })
    } else if (name === 'Physics') {
      this.MenuItemBuilder('🔬', '物理计算', '实验数据处理助手', '#00897B',
        () => { this.pageInfo.pushPath({ name: 'PortalWeb_Physics' }); })
    } else if (name === 'Mail') {
      this.MenuItemBuilder('📧', '学生邮箱', '查看icoremail邮件', '#D32F2F',
        () => { this.pageInfo.pushPath({ name: 'PortalWeb_Mail' }); })
    } else if (name === 'Net') {
      this.MenuItemBuilder('🌐', '校园网登录', '登录校园网自助服务平台', '#00ACC1',
        () => { this.pageInfo.pushPath({ name: 'PortalWeb_Net' }); })
    } else if (name === 'SchoolCardWeb') {
      this.MenuItemBuilder('🪪', '校园卡服务', '挂失/解绑/修改密码', '#FF7043',
        () => { this.pageInfo.pushPath({ name: 'PortalWeb_SchoolCard' }); })
    }
  }

  @Builder
  SchoolCardBuilder() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(44).height(44).fill('#FF6D0022')
        Text('💳').fontSize(22)
      }.margin({ right: 16 })
      Column() {
        Text('校园卡').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text('查余额和消费记录').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor('#CCCCCC')
    }
    .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(12).backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
    .onClick(() => { this.homeMenuItemClick('SchoolCard'); })
  }

  @Builder
  MenuItemBuilder(icon: string, title: string, desc: string, color: string, onClick: () => void) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(44).height(44).fill(color + '22')
        Text(icon).fontSize(22)
      }.margin({ right: 16 })
      Column() {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(desc).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor('#CCCCCC')
    }
    .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(12).backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
    .onClick(() => { onClick(); })
  }
}

