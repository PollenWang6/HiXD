// MainPage.ets - 底部Tab栏主页(主页·更多功能·我的)
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { ThemeColors } from '../utils/ThemeColors';
import { AccentColors, ACCENT_PRESETS } from '../utils/AccentColors';
import { ColorWheelPicker } from '../components/ColorWheelPicker';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { EhallService, SemesterUtil, ClassItemModel } from '../services/EhallService';
import { ClassService } from '../services/ClassService';
import { CasLoginService, TrackPoint, SliderPuzzle, PuzzleImages, CasFormFields } from '../services/CasLoginService';
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
import { AttendancePage } from './attendance/AttendancePage';
import { AttendanceService } from '../services/AttendanceService';
import { SchoolCardService } from '../services/SchoolCardService';
import { DormWaterPage } from './dormwater/DormWaterPage';
import { UserInfoService } from '../services/UserInfoService';
import { application, common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import web_webview from '@ohos.web.webview';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { VersionService, VersionInfo } from '../services/VersionService';


// 每日用电数据模型
interface DailyItem {
  date: string;     // 本次抄读日期 YYYY-MM-DD
  prevDate: string; // 上次抄读日期
  use: string;      // 两次抄读间用电 kWh
}


const TAG: string = 'MainPage';

interface ElecData {
  remain?: string;
  metID?: string;
  date?: string;
  daily?: DailyItem[];
}

// 节次时间表（与ClassTablePage一致）
const SECTION_TIMES: string[][] = [
  ['08:30', '09:15'],  // 第1节
  ['09:25', '10:10'],  // 第2节
  ['10:30', '11:15'],  // 第3节
  ['11:25', '12:00'],  // 第4节
  ['14:00', '14:45'],  // 第5节
  ['14:55', '15:40'],  // 第6节
  ['16:00', '16:45'],  // 第7节
  ['16:55', '17:30'],  // 第8节
  ['19:00', '19:45'],  // 第9节
  ['19:55', '20:40'],  // 第10节
  ['20:50', '21:25'],  // 第11节
];

// 预览卡片用的轻量数据结构
class PreviewCell {
  name: string = '';
  classroom: string = '';
  day: number = 0;        // 1-7 周一~周日
  startSection: number = 0; // 1-11
  endSection: number = 0;   // 1-11
  isExperiment: boolean = false;
  isCustom: boolean = false;
  isExam: boolean = false;
  examTimeDesc: string = '';
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
  closeBgDialog(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => { this.bgOpacity = 0; this.bgTranslate = 30; });
    setTimeout(() => { this.showBgDialog = false; }, 200);
  }
  // 选择背景图片
  selectBgImage(): void {
    try {
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(photoSelectOptions).then((result: photoAccessHelper.PhotoSelectResult) => {
        if (result.photoUris.length > 0 && result.photoUris[0] !== undefined) {
          this.bgPath = result.photoUris[0];
          // 提取真实路径，保存时用于复制文件
          this.bgOriPath = new fileUri.FileUri(this.bgPath).path;
          if (!this.bgShow) {
            this.bgShow = true;
          }
        }
      }).catch((err: BusinessError) => {
        console.error(TAG, 'PhotoViewPicker failed: ' + JSON.stringify(err));
      });
    } catch (error) {
      console.error(TAG, 'PhotoViewPicker failed: ' + JSON.stringify(error));
    }
  }
  // 保存背景设置
  async saveBgSettings(): Promise<void> {
    try {
      if (this.bgShow && this.bgOriPath.length > 0) {
        // 新选择了图片：复制到应用沙箱
        const destPath: string = this.context.filesDir + '/class_bg_image';
        try { await fileIo.copyFile(this.bgOriPath, destPath); } catch (_) { console.warn("MainPage", "copy bg file failed"); }
        await PreferenceUtil.putString('class_bg_path', destPath);
      } else if (!this.bgShow) {
        // 关闭自定义背景
        await PreferenceUtil.putString('class_bg_path', '');
      }
      // 如果 bgShow 为 true 但未新选图片，保留已有路径不变
      await PreferenceUtil.putBool('class_bg_show', this.bgShow);
      await PreferenceUtil.putNumber('class_bg_opacity', this.bgOpacityVal);
    } catch (_) { console.warn("MainPage", "ignored error"); }
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
  @State cardBalance: string = ''; // 校园卡余额显示（空字符串=未加载, '...'=加载中, '--'=失败）
  @State homeRefreshing: boolean = false;  // 主页下拉刷新
  @State userDormitory: string = '';   // 宿舍
  @State userStudentType: string = ''; // 学生类别
  @State userClassName: string = '';   // 班级
  @State previewCells: PreviewCell[] = [];
  @State previewLoaded: boolean = false;
  @State isTablet: boolean = deviceInfo.deviceType === 'tablet';
  @State selectedMenuIndex: number = 0;
  private menuNames: string[] = ['课程表', '实验信息', '考试安排', '成绩查询', '空教室', '图书馆', '校园卡', '校园网', '水电查询', '我的'];
  @StorageLink('isSplit') isSplit: NavigationMode = NavigationMode.Auto;
  @StorageLink('portalFullscreen') portalFullscreen: boolean = false;
  pageInfo: NavPathStack = new NavPathStack();
  @StorageLink('electricity_cache') elCache: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  @StorageLink('ct_updated') @Watch('onClassTableUpdated') ctUpdated: string = '';

  onClassTableUpdated(): void {
    if (this.ctUpdated.length > 0) { this.loadClassPreview(); }
  }
  @State cacheSize: string = '计算中...';
  @State showPhyPwdDialog: boolean = false;
  @State phyOpacity: number = 0;
  @State phyTranslate: number = 30;
  @State phyPwdInput: string = '';
  @State phyPwdStatus: string = '未设置';
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
  @State currentThemeLabel: string = '当前：浅色模式';
  @State warmupActive: boolean = false;
  private warmupUrl: string = 'https://order.xidian.edu.cn/mobile/thirdoauth/oauth2Xidian/1';

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
    ['Score', 'Exam', 'Library', 'SchoolNet', 'EmptyClass', 'SchoolCard', 'Attendance', 'Water', 'Experiment', 'Electricity'];
  @State portalSortOn: boolean = false;
  @State portalMenuOrder: string[] =
    ['Dianfei', 'Dingshui', 'Baoxiu', 'Space', 'Portal', 'Ruisi', 'Physics', 'Mail', 'Net', 'SchoolCardWeb'];

  private homeMenuItemClick(name: string): void {
    const names: Record<string, string> = {
      'Score': 'ScorePage', 'Exam': 'ExamPage', 'Library': 'LibraryPage',
      'SchoolNet': 'SchoolNetPage', 'EmptyClass': 'EmptyClassroomPage',
      'SchoolCard': 'SchoolCardPage', 'Attendance': 'AttendancePage',
      'Water': 'DormWaterPage', 'Experiment': 'ExperimentPage',
      'Electricity': 'ElectricityPage'
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
      if (arr.length === 10) { this.homeMenuOrder = arr; }
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
  private warmupController: web_webview.WebviewController = new web_webview.WebviewController();
  private context!: common.UIAbilityContext;
  // 应用级缓存目录（异步初始化，供 computeCacheSizeDirect 同步使用）
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
    console.info('MainPage', 'isTablet=' + this.isTablet + ' deviceType=' + deviceInfo.deviceType);
    // 平板：自动选中第一项课表
    if (this.isTablet) {
      this.onMenuClick(0);
    }
    // 立即显示界面，后台检查登录
    this.username = PreferenceUtil.getString('ids_account');
    this.computeCacheSizeDirect();
    // 基于 ids_account 判断登录状态（无 is_logged_in 标记）
    this.isLoggedIn = this.username.length > 0;
    this.phyPwdStatus = PreferenceUtil.getString('physics_pwd').length > 0 ? '已设置' : '未设置';
    const savedMode: number = PreferenceUtil.getNumber('theme_color_mode',
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    ThemeColors.init(savedMode, getContext());
    AccentColors.init();
    // 同步初始标签
    this.currentThemeLabel = this.buildThemeLabel(savedMode);
    AppStorage.setOrCreate('currentColorMode', savedMode);
    this.loginStatus = 'checking';
    // TGC 优先 → 密码兜底，一步完成
    this.checkLogin();
    this.loadClassPreview();
    this.initCacheDirs();
    // 后台检查版本更新（不阻塞 UI）
    this.checkVersionUpdate();
    // 获取当前版本号用于 UI 显示
    VersionService.getCurrentVersion().then((v: string) => { this.currentVersion = v; });
    // 首次启动隐私协议检查
    this.checkPrivacyAgreement();
    // 从缓存加载用户信息（登录前也能显示名字和头像）
    this.loadCachedUserInfo();
    // 后台获取校园卡余额（不阻塞 UI）
    setTimeout(() => { this.fetchCardBalance(); }, 3000);
  }

  // 异步获取应用级缓存目录（WebView 缓存存在这里，不在 HAP 级目录）
  private async initCacheDirs(): Promise<void> {
    try {
      const moduleContext = await application.createModuleContext(this.context, 'entry');
      this.appCacheDir = moduleContext.cacheDir;
      this.appCacheWebDir = moduleContext.cacheDir + '/web';
    } catch (e) {
      console.error('MainPage', 'initCacheDirs error: ' + String(e));
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
    } catch (_) { console.warn("MainPage", "ignored error"); }
  }

  aboutToDisappear() { this.stopRetryTimer(); }

  // 从后台切回前台时刷新登录状态
  onPageShow(): void {
    const now = Date.now();
    if (now - this.lastForegroundCheck < 30000) return; // 30s 防抖
    this.lastForegroundCheck = now;
    this.refreshSessionIfNeeded();
  }

  private async refreshSessionIfNeeded(): Promise<void> {
    if (this.loginStatus !== 'ok') return;
    try {
      const cas = CasLoginService.getInstance();
      const restored = await cas.tryAutoRestoreLogin();
      if (!restored) {
        console.info('MainPage', 'TGC expired after background, checking...');
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
          await this.doRelogin();
          return;
        }
        this.isLoggedIn = false;
        this.loginStatus = 'not_logged_in';
      } catch (_netErr) {
        this.loginStatus = 'offline';
        this.isLoggedIn = false;
        this.startRetryTimer();
      }
    } catch (e) {
      this.loginStatus = 'offline';
      this.isLoggedIn = false;
      this.startRetryTimer();
    }
  }

  // ========== 断网重试 ==========
  private startRetryTimer(): void {
    this.stopRetryTimer();
    this.retryTimer = setInterval(() => {
      if (this.loginStatus === 'offline') { this.checkLogin(); }
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
      this.loginStatus = 'expired';  // 对应 HiXD 标题下显示「登录已过期」
    } catch (e) {
      this.loginStatus = 'offline';
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
        + (b - this.captchaLastB) * (b - this.captchaLastB);
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
    .backgroundColor('#00000080')
    .alignContent(Alignment.Center)
  }

  private captchaThumbOff(): number {
    return Math.max(0, Math.min(this.captchaSliderLeft - 1, 280 - this.CAPTCHA_THUMB));
  }

  // 登录成功后预加载课表、考试、实验数据
  private startPreload(): void {
    AppStorage.setOrCreate('login_state', String(Date.now()));
    EhallService.getInstance().preloadAllData().catch((e: Error) => {
      console.warn('MainPage', 'preload failed: ' + String(e));
    });
  }

  // 异步加载用户信息（名字/头像/专业），失败用缓存兜底
  private loadUserInfo(): void {
    // 先打印原始 Preference 值，便于诊断
    const rawName: string = PreferenceUtil.getString('user_name');
    const rawAvatar: string = PreferenceUtil.getString('user_avatar');
    const rawMajor: string = PreferenceUtil.getString('user_major');
    const rawCollege: string = PreferenceUtil.getString('user_college');
    console.info(TAG, 'loadUserInfo: raw prefs name=' + rawName +
      ' college=' + rawCollege + ' major=' + rawMajor +
      ' avatarLen=' + String(rawAvatar.length));

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
      console.info(TAG, 'loadUserInfo: OK name=' + this.userDisplayName +
        ' college=' + this.userCollege + ' major=' + this.userMajor +
        ' grade=' + this.userGrade + ' gender=' + this.userGender +
        ' dormitory=' + this.userDormitory + ' studentType=' + this.userStudentType +
        ' className=' + this.userClassName);
    }).catch((e: Error) => {
      console.warn(TAG, 'loadUserInfo failed: ' + String(e));
      // 用缓存兜底
      this.userDisplayName = rawName;
      this.userAvatarUrl = rawAvatar;
      this.userMajor = rawMajor;
      this.userCollege = rawCollege;
    });
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
          console.info(TAG, 'downloadAndSetAvatar: OK path=' + filePath);
        } catch (e2) {
          console.warn(TAG, 'downloadAndSetAvatar: write failed: ' + String(e2));
        }
      } else {
        console.warn(TAG, 'downloadAndSetAvatar: bad response code=' + resp.responseCode + ' url=' + url);
      }
    }).catch((e: Object): void => {
      console.warn(TAG, 'downloadAndSetAvatar: download failed: ' + String(e) + ' url=' + url);
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
  private fetchCardBalance(): void {
    if (this.cardBalance.length > 0) return; // 已获取过
    this.cardBalance = '...';
    const svc = SchoolCardService.getInstance();
    svc.ensureOpenId().then(() => {
      svc.getBalance().then((bal: string) => {
        this.cardBalance = bal;
        console.info(TAG, 'fetchCardBalance: OK ' + bal);
      }).catch((e: Object) => {
        console.warn(TAG, 'fetchCardBalance: balance failed ' + String(e));
        this.cardBalance = '--';
      });
    }).catch((e: Object) => {
      console.warn(TAG, 'fetchCardBalance: openid failed ' + String(e));
      this.cardBalance = '--';
    });
  }

  // 手动刷新用户信息 — 隐藏 WebView 加载 xgxt jbxxapp SPA → JS fetch API 提取
  private refreshUserInfo(): void {
    if (this.userRefreshing) {
      console.info(TAG, 'refreshUserInfo: already refreshing, skip');
      return;
    }
    this.userRefreshing = true;
    console.info(TAG, 'refreshUserInfo: START (WebView → xgxt)');

    // 清除旧 WebView 状态
    clearTimeout(this.xgxtTimeoutId);
    this.xgxtActive = false;

    // 下一帧激活 WebView，触发 CAS SSO → jbxxapp SPA 加载
    this.xgxtPhase = 1;
    setTimeout(() => { this.xgxtActive = true; }, 100);

    // 超时保护
    this.xgxtTimeoutId = setTimeout(() => {
      console.warn(TAG, 'xgxt fetch TIMEOUT');
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
      '    .catch(function(e){console.log("XGXT_ERR:"+e.message);});' +
      '},4000);';
    this.xgxtController.runJavaScript(js);
    console.info(TAG, 'xgxtInjectFetch: JS injected, waiting for SPA init...');
  }

  // 处理 JS fetch 返回的 getStuBaseInfo JSON
  private xgxtProcessResult(raw: string): void {
    try {
      console.info(TAG, 'xgxtProcessResult: raw[0:500]=' + raw.substring(0, 500));
      const obj: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const returnCode: string = String(obj['returnCode'] ?? '');
      if (returnCode !== '#E000000000000') {
        const desc: string = String(obj['description'] ?? JSON.stringify(raw).substring(0, 120));
        console.warn(TAG, 'xgxt API failed: ' + desc);
        this.xgxtCleanup();
        return;
      }
      const data: Record<string, Object> = obj['data'] as Record<string, Object>;
      if (!data) {
        console.warn(TAG, 'xgxt result: no data field');
        this.xgxtCleanup();
        return;
      }
      // 提取字段（与实际 API 返回一致）
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

      console.info(TAG, 'xgxt result: OK name=' + name + ' college=' + college +
        ' major=' + major + ' grade=' + grade + ' gender=' + gender +
        ' dorm=' + dorm + ' stype=' + stype + ' cls=' + cls);
      this.loadUserInfo();

      // 学工数据拿到后，进入阶段2：超星头像提取
      // 读缓存：若已有有效 UID（纯数字）则跳过 WebView
      const cachedUid: string = PreferenceUtil.getString('cx_uid');
      if (cachedUid.length > 0 && /^\d+$/.test(cachedUid)) {
        this.downloadAndSetAvatar('https://photo.chaoxing.com/p/' + cachedUid + '_80');
        console.info(TAG, 'xgxt result: using cached uid=' + cachedUid);
        this.xgxtCleanup();
        return;
      }

      // 无缓存 → HTTP 走考勤 SSO 入口建超星 session → WebView 直连 i.chaoxing
      // 关键：走 xdspoc.fanya.chaoxing.com（CAS 白名单内），不走 i.chaoxing.com（外域被拦截）
      this.xgxtPhase = 2;
      const attSvc: AttendanceService = AttendanceService.getInstance();
      console.info(TAG, 'xgxt result: logging into chaoxing via xdspoc SSO...');
      attSvc.loginToLearning().then(() => {
        // 把 fanya/xdspoc 子域的 cookie 复制到超星主站域（i.chaoxing / passport2）
        const http = HttpUtil.getInstance();
        const srcDomains: string[] = ['fanya.chaoxing.com', 'xdspoc.fanya.chaoxing.com',
          'fycourse.fanya.chaoxing.com', 'mobilelearn.chaoxing.com'];
        const cxDomains: string[] = ['i.chaoxing.com', 'passport2.chaoxing.com', 'chaoxing.com'];
        for (let si = 0; si < srcDomains.length; si++) {
          for (let di = 0; di < cxDomains.length; di++) {
            http.copyCookiesForDomain(srcDomains[si], cxDomains[di]);
          }
        }
        // 同步所有 cookie 到 WebView（现在包含 i.chaoxing / passport2）
        CasLoginService.getInstance().syncCookiesToWebView();
        const cxUrl: string = 'https://i.chaoxing.com/base';
        console.info(TAG, 'xgxt result: chaoxing session ready, nav=' + cxUrl);
        this.xgxtController.loadUrl(cxUrl);
      }).catch((err: Error) => {
        console.error(TAG, 'xgxt result: loginToLearning failed: ' + err.message);
        this.xgxtCleanup();
      });
      return;
    } catch (e) {
      console.error(TAG, 'xgxt parse error: ' + JSON.stringify(e));
    }
    this.xgxtCleanup();
  }

  // 阶段2: 注入 JS 提取超星 UID
  private xgxtInjectChaoxing(): void {
    const js: string =
      '(function(){' +
      '  var s=document.body.innerHTML;' +
      '  var m=s.match(/photo\\.chaoxing\\.com\\/p\\/(\\d+)/);' +
      '  if(m){console.log("CX_UID:"+m[1]);}else{console.log("CX_UID:none");}' +
      '})();';
    this.xgxtController.runJavaScript(js);
    console.info(TAG, 'xgxtInjectChaoxing: JS injected');
  }

  // 处理提取到的超星 UID
  private async xgxtChaoxingResult(uid: string): Promise<void> {
    if (uid.length > 0 && uid !== 'none' && /^\d+$/.test(uid)) {
      await PreferenceUtil.putString('cx_uid', uid);
      this.downloadAndSetAvatar('https://photo.chaoxing.com/p/' + uid + '_80');
      console.info(TAG, 'xgxtChaoxingResult: saved uid=' + uid);
    } else {
      console.warn(TAG, 'xgxtChaoxingResult: no valid uid found, raw=' + uid);
    }
    this.xgxtCleanup();
  }

  // 清理 xgxt WebView 状态
  private xgxtCleanup(): void {
    clearTimeout(this.xgxtTimeoutId);
    this.xgxtPhase = 0;
    this.xgxtActive = false;
    this.userRefreshing = false;
    console.info(TAG, 'xgxtCleanup: done');
  }

  // ==================== 缓存管理 ====================
  private formatBytes(bytes: number): string {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  // removeAllCache(true) 清全局磁盘+内存缓存，API 18+ 静态方法，无需 WebView
  // removeAllCache(true) 静态方法，API 18+，不需要 WebView 实例
  // 注意：不能用 setTimeout 包 computeCacheSizeDirect()，否则 @State 赋值不触发 UI 刷新
  private clearCache(): void {
    this.cacheSize = '清理中...';
    try {
      web_webview.WebviewController.removeAllCache(true);
    } catch (e) {
      console.error('MainPage', 'clearCache error: ' + String(e));
    }
    this.computeCacheSizeDirect();
  }

  // 手动遍历 cache 目录算大小（绕过 getCurrentBundleStats 缓存）
  // 同步计算缓存大小（绕过 getCurrentBundleStats 缓存）
  // 注意：不用 async/await，否则 @State 赋值可能不触发 UI 刷新
  computeCacheSizeDirect(): void {
    console.info('MainPage', 'computeCacheSizeDirect START');
    let total: number = 0;
    // 应用级（WebView 缓存）+ HAP 级
    const dirs: string[] = [];
    if (this.appCacheDir.length > 0) { dirs.push(this.appCacheDir); }
    if (this.appCacheWebDir.length > 0) { dirs.push(this.appCacheWebDir); }
    dirs.push(this.context.cacheDir);
    for (let i = 0; i < dirs.length; i++) {
      try {
        const entries = fileIo.listFileSync(dirs[i]);
        for (let j = 0; j < entries.length; j++) {
          let dp = dirs[i] + '/' + entries[j];
          try {
            let st = fileIo.statSync(dp);
            if (st.isDirectory()) {
              total += this.dirSize(dp);
            } else {
              total += st.size;
            }
          } catch(e) {
            console.info('MainPage', 'computeCacheSizeDirect stat fail: ' + dp + ' err=' + String(e));
            // skip
          }
        }
      } catch(e) {
        console.info('MainPage', 'computeCacheSizeDirect listFileSync dir fail: ' + dirs[i] + ' err=' + String(e));
      }
    }
    console.info('MainPage', 'computeCacheSizeDirect DONE total=' + total);
    this.cacheSize = this.formatBytes(total);
  }

  // 递归计算目录大小
  private dirSize(dirPath: string): number {
    let size: number = 0;
    try {
      const children = fileIo.listFileSync(dirPath);
      for (let k = 0; k < children.length; k++) {
        let cp = dirPath + '/' + children[k];
        try {
          let st = fileIo.statSync(cp);
          if (st.isDirectory()) {
            size += this.dirSize(cp);
          } else {
            size += st.size;
          }
        } catch (e) {
          console.info('MainPage', 'computeCacheSizeDirect dirSize stat fail: ' + cp + ' err=' + String(e));
          // skip
        }
      }
    } catch (e) {
      console.info('MainPage', 'computeCacheSizeDirect dirSize listFile fail: ' + dirPath + ' err=' + String(e));
      // skip
    }
    return size;
  }

  // 加载课表预览数据：读取本地缓存 → 解析classGrid → 提取接下来2节课
  loadClassPreview(): void {
    console.error('Preview', 'loadClassPreview called');
    try {
      const semesterCode: string = SemesterUtil.getCurrentSemesterCode();
      const filePath: string = this.context.filesDir + '/class_table_' + semesterCode + '.json';
      if (!fileIo.accessSync(filePath)) {
        this.previewLoaded = true;
        return;
      }
      console.error('Preview', 'loadClassPreview filePath=' + filePath);
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
          console.error('Preview', 'item: ' + item.kcm + ' skzc=[' + item.skzc + '] weekList11=' + weekList[11]);
        }
        const cell = new PreviewCell();
        cell.name = item.kcm;
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
      console.error('Preview', 'previewCells count=' + this.previewCells.length);
      this.previewLoaded = true;
    } catch (e) {
      console.error('MainPage', 'loadClassPreview error: ' + String(e));
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
        cell.classroom = item['lab'] || '';
        cell.day = weekday;
        cell.startSection = startSec;
        cell.endSection = endSec > startSec ? endSec : startSec;
        cell.isExperiment = true;
        cell.weekNum = parseInt(item['week']) || 0;
        if (weekday <= 7 && startSec <= 11) {
          grid[weekday][startSec].push(cell);
        }
      }
    } catch (e) {
      console.error('MainPage', 'mergeExpPreview error: ' + String(e));
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
        cell.classroom = item['lab'] || '';
        cell.day = weekday;
        cell.startSection = startSec;
        cell.endSection = endSec > startSec ? endSec : startSec;
        cell.isExperiment = true;
        cell.weekNum = parseInt(item['week']) || 0;
        if (weekday <= 7 && startSec <= 11) {
          grid[weekday][startSec].push(cell);
        }
      }
    } catch (e) {
      console.error('MainPage', 'mergePhysicsPreview error: ' + String(e));
    }
  }

  // 合并自定义课程到预览grid
  private mergeCustomPreview(grid: PreviewCell[][][]): void {
    try {
      const semCode: string = SemesterUtil.getCurrentSemesterCode();
      const customPath: string = this.context.filesDir + '/class_table_' + semCode + '_custom.json';
      console.error('Preview', 'mergeCustom searchPath=' + customPath);
      if (!fileIo.accessSync(customPath)) {
        console.error('Preview', 'mergeCustom file not found');
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
      console.error('Preview', 'mergeCustom items.length=' + items.length);
      for (let i = 0; i < items.length; i++) {
        const item: Record<string, Object> = items[i] as Record<string, Object>;
        const day: number = item['day'] as number || 0;
        const startSec: number = item['startSection'] as number || 0;
        const endSec: number = item['endSection'] as number || 0;
        if (day < 1 || day > 7 || startSec < 1) continue;
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
        cell.day = day;
        cell.startSection = startSec;
        cell.endSection = endSec > startSec ? endSec : startSec;
        cell.isCustom = true;
        cell.weekList = weekList;
        console.error('Preview', 'mergeCustom item: name=' + cell.name + ' day=' + day + ' sec=' + startSec + '-' + cell.endSection + ' wlLen=' + wl.length + ' wl[13]=' + (wl.length > 13 ? wl[13] : '?'));
        if (day <= 7 && startSec <= 11) {
          grid[day][startSec].push(cell);
        }
      }
    } catch (e) {
      console.error('MainPage', 'mergeCustomPreview error: ' + String(e));
    }
  }

  // 合并考试数据到预览grid
  private mergeExamPreview(grid: PreviewCell[][][]): void {
    const cached: string = PreferenceUtil.getString('exam_schedule_cache');
    if (cached.length === 0) return;
    try {
      const items: Object[] = JSON.parse(cached) as Object[];
      const startDate: Date = new Date(2026, 2, 2);
      for (let i = 0; i < items.length; i++) {
        const item: Record<string, Object> = items[i] as Record<string, Object>;
        const ksrq: string = item['ksrq'] as string || '';
        const kssjms: string = item['kssjms'] as string || '';
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
        const weekDayNames: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
        const cell = new PreviewCell();
        cell.name = '📝 ' + ((item['kcm'] as string) || (item['ksmc'] as string) || '考试');
        cell.classroom = item['jasmc'] as string || '';
        cell.day = weekday;
        cell.startSection = 0;
        cell.endSection = 0;
        cell.isExam = true;
        cell.weekNum = weekNum;
        cell.examTimeDesc = timeOnly + ' ' + weekDayNames[examDate.getDay()];
        if (weekday <= 7) {
          grid[weekday][0].push(cell);
        }
      }
    } catch (e) {
      console.error('MainPage', 'mergeExamPreview error: ' + String(e));
      PreferenceUtil.putString('exam_schedule_cache', '');
    }
  }

  // 从classGrid中提取接下来2节课（今天+明天）
  private getNextClasses(grid: PreviewCell[][][]): PreviewCell[] {
    const result: PreviewCell[] = [];
    const now = new Date();
    const currentWeek: number = SemesterUtil.calcCurrentWeekFromNow();
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

    console.error('Preview', 'week=' + currentWeek + ' todayDay=' + todayDay + ' currentSection=' + currentSection);

    // 搜索范围：今天 + 明天（最多2天）
    for (let offset = 0; offset < 2 && result.length < 2; offset++) {
      let searchDay: number = todayDay + offset;
      let searchWeek: number = currentWeek;
      if (searchDay > 7) {
        searchDay = 1;
        searchWeek = currentWeek + 1;
      }
      if (searchWeek > 18) continue;

      console.error('Preview', 'offset=' + offset + ' searchDay=' + searchDay + ' searchWeek=' + searchWeek);

      // 先检查考试（存储在 section 0）
      const examCells: PreviewCell[] = grid[searchDay][0];
      for (let ci = 0; ci < examCells.length; ci++) {
        const cell: PreviewCell = examCells[ci];
        if (cell.isExam && cell.weekNum === searchWeek) {
          result.push(cell);
          if (result.length >= 2) break;
        }
      }

      // 遍历该天所有节次
      for (let s = 1; s <= 11 && result.length < 2; s++) {
        const cells: PreviewCell[] = grid[searchDay][s];
        for (let ci = 0; ci < cells.length; ci++) {
          const cell: PreviewCell = cells[ci];
          // 今天：跳过已全部结束的课程（endSection < currentSection）
          if (offset === 0 && cell.endSection < currentSection) continue;
          // 实验课程：weekNum匹配当前周
          if (cell.isExperiment || cell.isExam) {
            if (cell.weekNum === searchWeek) {
              result.push(cell);
              if (result.length >= 2) break;
            }
          } else if (cell.isCustom) {
            // 自定义课程：检查weekList
            const matchWeek = cell.weekList.length > searchWeek && cell.weekList[searchWeek];
            console.error('Preview', 'getNext custom: name=' + cell.name + ' s=' + s + ' endSec=' + cell.endSection + ' curSec=' + currentSection + ' searchWeek=' + searchWeek + ' wlLen=' + cell.weekList.length + ' matchWeek=' + matchWeek + ' offset=' + offset + ' resultLen=' + result.length);
            if (matchWeek) {
              result.push(cell);
              if (result.length >= 2) break;
            }
          } else {
            // 普通课程：检查weekList是否包含搜索周
            if (cell.weekList.length > searchWeek && cell.weekList[searchWeek]) {
              result.push(cell);
            } else {
              console.error('Preview', 'skip: ' + cell.name + ' day=' + cell.day + ' s=' + s + ' weekLen=' + cell.weekList.length + ' searchWeek=' + searchWeek);
            }
            if (result.length >= 2) break;
          }
        }
      }
    }
    return result;
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
        } catch (_) {
          this.bgPath = '';
        }
      } else {
        this.bgPath = '';
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
      PortalWebPage({ pageInfo: this.pageInfo, title: '校园网登录', url: 'https://zfw.xidian.edu.cn/', isTablet: this.isTablet })
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
    } else if (name === 'PortalWeb_Dianfei') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '水电缴费', url: 'https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=https://ignypt.xidian.edu.cn/revenueH5/login?opcode=MPAY&appid=200260318155520600' , isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Physics') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '物理计算', url: 'https://experiment-helper.wizzstudio.com/#/', isTablet: this.isTablet })
    } else if (name === 'AttendancePage') {
      AttendancePage({ pageInfo: this.pageInfo })
    } else if (name === 'DormWaterPage') {
      DormWaterPage({ pageInfo: this.pageInfo })
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

  build() {
    Stack() {
    // 隐形 WebView：冷启动时走一遍 CAS OAuth 链刷新 session cookie
    if (this.warmupActive) {
      Web({ src: this.warmupUrl, controller: this.warmupController })
        .width('100%')
        .height('100%')
        .onPageEnd((event) => {
          if (event && event.url && event.url.indexOf('order.xidian.edu.cn') >= 0) {
            console.error(TAG, 'warmup done: ' + event.url);
            setTimeout(() => { this.warmupActive = false; }, 2000);
          }
        })
        .onErrorReceive(() => {
          console.error(TAG, 'warmup error, disabling');
          setTimeout(() => { this.warmupActive = false; }, 5000);
        })
        .domStorageAccess(true)
    }
    // 隐藏 xgxt WebView：加载 jbxxapp SPA 后用 JS 抓取个人信息
    if (this.xgxtActive) {
      Web({ src: this.xgxtUrl, controller: this.xgxtController })
        .width('300px')
        .height('300px')
        .position({ x: -400, y: 0 })
        .onPageEnd((event) => {
          if (event && event.url) {
            console.info(TAG, 'xgxt pageEnd: url=' + event.url.substring(0, 120));
            if (this.xgxtPhase === 1 && event.url.indexOf('xgxt.xidian.edu.cn') >= 0) {
              console.info(TAG, 'xgxt pageEnd: xgxt page loaded, injecting JS...');
              this.xgxtInjectFetch();
            } else if (this.xgxtPhase === 2 && event.url.indexOf('i.chaoxing.com') >= 0) {
              console.info(TAG, 'xgxt pageEnd: chaoxing page loaded, extracting uid...');
              this.xgxtInjectChaoxing();
            }
          } else {
            console.info(TAG, 'xgxt pageEnd: no url in event');
          }
        })
        .onConsole((event): boolean => {
          if (event && event.message) {
            const msg: string = event.message.getMessage();
            if (msg.indexOf('XGXT_INFO:') === 0) {
              const raw: string = msg.substring(10);
              console.info(TAG, 'xgxt console: XGXT_INFO len=' + String(raw.length));
              this.xgxtProcessResult(raw);
              return true;
            }
            if (msg.indexOf('XGXT_ERR:') === 0) {
              console.warn(TAG, 'xgxt console: XGXT_ERR ' + msg.substring(10));
              this.xgxtCleanup();
              return true;
            }
            if (msg.indexOf('CX_UID:') === 0) {
              const uid: string = msg.substring(7).trim();
              console.info(TAG, 'xgxt console: CX_UID=' + uid);
              this.xgxtChaoxingResult(uid);
              return true;
            }
          }
          return false;
        })
        .onErrorReceive(() => {
          console.error(TAG, 'xgxt WebView error');
          this.xgxtCleanup();
        })
        .domStorageAccess(true)
        .javaScriptAccess(true)
    }
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
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        })
        .onAnimationStart((_index: number, targetIndex: number) => {
          this.currentIndex = targetIndex;
          if (targetIndex === 0) { this.loadClassPreview(); }
          else if (targetIndex === 2) { this.computeCacheSizeDirect(); this.refreshThemeLabel(); }
        })
        .width('100%')
        .layoutWeight(1)
      } else {
        Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
          TabContent() {
            this.HomeTab()
          }.tabBar(this.TabBuilder(0, '🏠', '主页'))

          TabContent() {
            this.PortalTab()
          }.tabBar(this.TabBuilder(1, '🔧', '更多功能'))

          TabContent() {
            this.MyTab()
          }.tabBar(this.TabBuilder(2, '👤', '我的'))
        }
        .scrollable(false)
        .barMode(BarMode.Fixed)
        .barBackgroundColor('#FFFFFF')
        .onChange((index: number) => {
          this.currentIndex = index;
          if (index === 0) { this.loadClassPreview(); }
          else if (index === 2) { this.computeCacheSizeDirect(); this.refreshThemeLabel(); this.loadUserInfo(); }
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
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.phyOpacity)
    .hitTestBehavior(this.showPhyPwdDialog ? HitTestMode.Default : HitTestMode.None)
    .onClick(() => { this.closePhyPwdDialog(); })
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
              this.userDisplayName = '';
              this.username = '';
              this.userMajor = '';
              this.userCollege = '';
              this.userAvatarUrl = '';
              this.isLoggedIn = false;
              this.loginStatus = 'not_logged_in';
            })
        }.width('100%')
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.logoutOpacity)
      .translate({ y: this.logoutTranslate })
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
            .aspectRatio(4 / 3)
            .constraintSize({ maxHeight: 300 })
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
            .opacity(this.bgPath.length > 0 ? this.bgOpacityVal / 100 : 0.06)
            .interpolation(ImageInterpolation.Medium)
          if (this.bgPath.length === 0) {
            Text('📷 点此选择图片').fontSize(14).fontColor(ThemeColors.textHint)
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
        Text('最新版本：v' + this.updateInfo.version).fontSize(14).fontColor(ThemeColors.textSecondary).margin({ bottom: 16 })
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
                try { this.context.openLink(this.updateInfo.url); } catch (_) { console.warn("MainPage", "openLink failed"); }
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

        // 课程列表
        ForEach(this.previewCells, (cell: PreviewCell, index: number) => {
          Row() {
            // 左侧色条
            Column()
              .width(4).height('100%').borderRadius(2)
              .backgroundColor(cell.isExam ? '#E91E63' : (cell.isExperiment ? '#FF9800' : (cell.isCustom ? '#66BB6A' : '#2979FF')))

            // 课程信息
            Column() {
              Row() {
                Text(cell.name)
                  .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              Row() {
                if (cell.isExam) {
                  Text('📝考试')
                    .fontSize(11).fontColor('#E91E63')
                } else if (cell.isExperiment) {
                  Text('  实验')
                    .fontSize(11).fontColor(ThemeColors.warning)
                } else if (cell.isCustom) {
                  Text('  自定')
                    .fontSize(11).fontColor('#66BB6A')
                }
                if (cell.isExam && cell.examTimeDesc.length > 0) {
                  Text(cell.examTimeDesc)
                    .fontSize(12).fontColor('#E91E63')
                } else if (!cell.isExam) {
                  Text(SECTION_TIMES[cell.startSection - 1][0] + '-' + SECTION_TIMES[cell.endSection - 1][1])
                    .fontSize(12).fontColor(ThemeColors.textSecondary)
                }
                if (cell.classroom.length > 0) {
                  Text('  ' + cell.classroom)
                    .fontSize(12).fontColor(ThemeColors.textSecondary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
              }.margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .padding({ left: 12 })

            // 日期标签
            Text(cell.day === this.getTodayDay() ? '今天' : '明天')
              .fontSize(12).fontColor(cell.day === this.getTodayDay() ? this.accentTextColor() : '#FFFFFF')
              .backgroundColor(cell.day === this.getTodayDay() ? this.accentColor : '#43A047')
              .borderRadius(10)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          }
          .width('100%')
          .height(56)
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
        this.pageInfo.pushPath({ name: 'ClassTablePage' }); })
    } else if (this.previewLoaded && this.previewCells.length === 0) {
      // 没课
      Column() {
        Text('🌸 😴 ✨ 🌙 🐢').fontSize(28).padding({ top: 16, bottom: 4 })
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
        this.pageInfo.pushPath({ name: 'ClassTablePage' }); })
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
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 6, bottom: 8, left: 12, right: 12 })
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
          Button(this.loginStatus === 'expired' ? '重新登录' : '登录')
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
      .width('100%').height(60).padding({ left: 20, right: 16, top: 8 })
      .backgroundColor(this.accentColor)

      // 课表预览卡片
      this.ClassPreviewCard()

      // 电费查询已移至功能菜单

      // 功能菜单列表(始终显示)
      Column() {
        Refresh({ refreshing: $$this.homeRefreshing }) {
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
      .width('100%').height(56).padding({ left: 20 })
      .backgroundColor(this.accentColor)
      Divider().color('#F0F0F0')

      List({ space: 8 }) {
        // 提示卡片
        ListItem() {
          Row() {
            Text('💡').fontSize(16)
            Text('部分功能需从「订水系统」预热登录后使用')
              .fontSize(12).fontColor(ThemeColors.textSecondary)
              .margin({ left: 6 }).layoutWeight(1)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(ThemeColors.isDark ? '#1A2A3A' : '#FFF8E1')
          .borderRadius(8)
        }
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
      .width('100%').height(56).padding({ left: 20 })
      .backgroundColor(this.accentColor)
      Divider().color('#F0F0F0')

      // 用户区域：有缓存数据就显示信息卡片，否则显示登录入口
      if (this.userDisplayName || this.username) {
        // 用户信息卡片
        Column() {
          Row() {
            // 头像
            Stack() {
              Circle().width(56).height(56).fill(this.accentColor + '18')
              if (this.userAvatarUrl) {
                Image(this.userAvatarUrl).width(56).height(56).borderRadius(28).objectFit(ImageFit.Cover)
              } else {
                Text('🎓').fontSize(28)
              }
            }.width(56).height(56)
            .border({ width: 2.5, color: this.accentColor + '40', radius: 28 })

            Column() {
              // 姓名行
              Row() {
                Text(this.userDisplayName || this.username || '已登录')
                  .fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                // 性别符号
                if (this.userGender && this.userGender !== '') {
                  Text(this.userGender === '男' ? '♂' : '♀')
                    .fontSize(20).fontWeight(FontWeight.Bold)
                    .fontColor(this.userGender === '男' ? '#5D9CEC' : '#EC5D8A')
                    .margin({ left: 8 })
                }
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
                }.margin({ top: 6 })
              }

              // 标签行
              Row() {
                Text(PreferenceUtil.getBool('role') ? '研究生' : '本科生')
                  .fontSize(11).fontColor(this.accentColor)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor(this.accentColor + '14')
                  .borderRadius(4)
                if (this.userGrade) {
                  Text(this.userGrade + '级').fontSize(11).fontColor(ThemeColors.textSecondary)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(this.accentColor + '0A')
                    .borderRadius(4).margin({ left: 6 })
                }
                if (this.userClassName) {
                  Text(this.userClassName + '班').fontSize(11).fontColor(ThemeColors.textSecondary)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(this.accentColor + '0A')
                    .borderRadius(4).margin({ left: 6 })
                }
              }.margin({ top: 8 })
            }.margin({ left: 16 }).layoutWeight(1).alignItems(HorizontalAlign.Start)

            // 刷新按钮
            Row() {
              if (this.userRefreshing) {
                LoadingProgress().width(22).height(22).color(this.accentColor)
              } else {
                Text('🔄').fontSize(20)
              }
            }.width(40).height(40)
             .justifyContent(FlexAlign.Center)
             .borderRadius(20)
             .backgroundColor(this.accentColor + '10')
             .onClick(() => { this.refreshUserInfo(); })
          }.width('100%')
        }
        .width('100%').padding({ left: 18, right: 18, top: 20, bottom: 20 })
        .backgroundColor(ThemeColors.bgCard)
        .borderRadius(14).shadow({ radius: 4, color: '#0000000C', offsetY: 2 })
        .margin({ left: 16, right: 16, top: 12 })
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
      this.MenuItemBuilder('🔧', '后勤报修', '足不出户提交报修', '#5D4037',
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
        if (this.cardBalance.length > 0) {
          if (this.cardBalance === '...') {
            Text('正在查询余额...').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
          } else if (this.cardBalance === '--') {
            Text('余额获取失败').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
          } else {
            Text('¥ ' + this.cardBalance).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FF6D00').margin({ top: 2 })
          }
        } else {
          Text('查余额和消费记录').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
        }
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

