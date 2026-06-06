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
import { PortalWebPage } from './portal/PortalWebPage';
import { SchoolNetPage } from './schoolnet/SchoolNetPage';
import { ElectricityPage } from './electricity/ElectricityPage';
import { FaqPage } from './faq/FaqPage';
import { application, common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import web_webview from '@ohos.web.webview';
import { image } from '@kit.ImageKit';


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
    if (this.showWheelPicker) { this.showWheelPicker = false; return true; }
    if (this.showColorPicker) { this.showColorPicker = false; return true; }
    if (this.showThemeDialog) { this.showThemeDialog = false; return true; }
    if (this.showPhyPwdDialog) { this.showPhyPwdDialog = false; return true; }
    if (this.showCaptcha) { this.closeCaptcha(); return true; }
    return false;
  }

  @State currentIndex: number = 0;
  @State username: string = '';
  @State isLoggedIn: boolean = false;
  @State loginStatus: string = ''; // '' | 'checking' | 'offline' | 'expired' | 'not_logged_in' | 'ok'
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
  @State phyPwdInput: string = '';
  @State phyPwdStatus: string = '未设置';
  @State showThemeDialog: boolean = false;
  @State showColorPicker: boolean = false;
  @State showWheelPicker: boolean = false;
  @State customHex: string = '';
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('accent_index') accentIdx: number = 0;
  private retryTimer: number = -1;
  @StorageProp('currentColorMode') @Watch('onColorModeChange') systemColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @State currentThemeLabel: string = '当前：浅色模式';
  @State warmupActive: boolean = false;
  private warmupUrl: string = 'https://order.xidian.edu.cn/mobile/thirdoauth/oauth2Xidian/1';

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

  private tabsController: HdsTabsController = new HdsTabsController();
  private warmupController: web_webview.WebviewController = new web_webview.WebviewController();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  // 应用级缓存目录（异步初始化，供 computeCacheSizeDirect 同步使用）
  private appCacheDir: string = '';
  private appCacheWebDir: string = '';

  aboutToAppear() {
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

  aboutToDisappear() { this.stopRetryTimer(); }

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
          Text('请按住滑块拖动到最右端').fontSize(12).fontColor('#999999').margin({ top: 16 })
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

  // 同步 Cookie 后跳转 Portal WebView
  private async navPortal(routeName: string): Promise<void> {
    await CasLoginService.getInstance().syncCookiesToWebView();
    await new Promise<void>((r) => setTimeout(r, 300));
    this.pageInfo.pushPath({ name: routeName });
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
    console.error('MainPage', 'computeCacheSizeDirect START');
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
            console.error('MainPage', 'computeCacheSizeDirect stat fail: ' + dp + ' err=' + String(e));
            // skip
          }
        }
      } catch(e) {
        console.error('MainPage', 'computeCacheSizeDirect listFileSync dir fail: ' + dirs[i] + ' err=' + String(e));
      }
    }
    console.error('MainPage', 'computeCacheSizeDirect DONE total=' + total);
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
          console.error('MainPage', 'computeCacheSizeDirect dirSize stat fail: ' + cp + ' err=' + String(e));
          // skip
        }
      }
    } catch (e) {
      console.error('MainPage', 'computeCacheSizeDirect dirSize listFile fail: ' + dirPath + ' err=' + String(e));
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
    } else if (name === 'SchoolNetPage') {
      SchoolNetPage({ pageInfo: this.pageInfo })
    } else if (name === 'ElectricityPage') {
      ElectricityPage({ pageInfo: this.pageInfo })
    } else if (name === 'FaqPage') {
      FaqPage({ pageInfo: this.pageInfo, isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Dianfei') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '水电缴费', url: 'https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=https://ignypt.xidian.edu.cn/revenueH5/login?opcode=MPAY&appid=200260318155520600' , useWeChatUA: true , isTablet: this.isTablet })
    } else if (name === 'PortalWeb_Physics') {
      PortalWebPage({ pageInfo: this.pageInfo, title: '物理计算', url: 'https://experiment-helper.wizzstudio.com/#/', isTablet: this.isTablet })
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
    this.showThemeDialog = false;
    PreferenceUtil.putNumber('theme_color_mode', mode);
    // 直接更新 @State 标签（确保 TabContent 内 Builder 实时刷新）
    this.currentThemeLabel = this.buildThemeLabel(mode);
    AppStorage.setOrCreate('currentColorMode', mode);
    if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      ThemeColors.applyFollowSystem(getContext());
    } else {
      ThemeColors.applyManual(mode, getContext());
    }
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
        .barFloatingStyle({
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
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
          else if (index === 2) { this.computeCacheSizeDirect(); this.refreshThemeLabel(); }
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
    // 物理实验密码弹窗（始终渲染，visibility 控制显示，确保触摸事件正常）
    Column() {
      Column() {
        Row() {
          Text('物理实验设置（test）').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor('#999999') }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.showPhyPwdDialog = false; })
        }.width('100%').margin({ bottom: 16 })
        TextInput({ placeholder: '输入物理实验密码', text: this.phyPwdInput })
          .type(InputType.Password)
          .width('100%').height(44).fontSize(15)
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .onChange((v: string) => { this.phyPwdInput = v; })
        Row() {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput)
            .onClick(() => { this.showPhyPwdDialog = false; })
          Button('保存').layoutWeight(1).height(40).margin({ left: 12 })
            .backgroundColor('#7B1FA2').fontColor('#FFFFFF')
            .onClick(() => {
              if (this.phyPwdInput.length > 0) {
                PreferenceUtil.putString('physics_pwd', this.phyPwdInput);
                this.phyPwdStatus = '已设置';
                this.showPhyPwdDialog = false;
              }
            })
        }.width('100%').margin({ top: 16 })
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(this.showPhyPwdDialog ? '#80000000' : '#00000000')
    .hitTestBehavior(this.showPhyPwdDialog ? HitTestMode.Default : HitTestMode.None)
    .visibility(this.showPhyPwdDialog ? Visibility.Visible : Visibility.None)
    .onClick(() => { this.showPhyPwdDialog = false; })
    // 深色模式选择弹窗
    Column() {
      Column() {
        Row() {
          Text('深色设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor('#999999') }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.showThemeDialog = false; })
        }.width('100%').margin({ bottom: 16 })
        Button('浅色').width('100%').height(44)
          .backgroundColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? '#2979FF' : ThemeColors.bgInput)
          .fontColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? '#FFFFFF' : ThemeColors.textPrimary)
          .onClick(() => { this.selectTheme(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT); })
        Button('深色').width('100%').height(44).margin({ top: 8 })
          .backgroundColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#2979FF' : ThemeColors.bgInput)
          .fontColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#FFFFFF' : ThemeColors.textPrimary)
          .onClick(() => { this.selectTheme(ConfigurationConstant.ColorMode.COLOR_MODE_DARK); })
        Button('跟随系统').width('100%').height(44).margin({ top: 8 })
          .backgroundColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET ? '#2979FF' : ThemeColors.bgInput)
          .fontColor(ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET ? '#FFFFFF' : ThemeColors.textPrimary)
          .onClick(() => { this.selectTheme(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET); })
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .hitTestBehavior(this.showThemeDialog ? HitTestMode.Default : HitTestMode.None)
    .visibility(this.showThemeDialog ? Visibility.Visible : Visibility.None)
    .onClick(() => { this.showThemeDialog = false; })
    // 主题色选择弹窗
    Column() {
      Column() {
        Row() {
          Text('选择主题色').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor('#999999') }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.showColorPicker = false; })
        }.width('100%').margin({ bottom: 16 })
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(ACCENT_PRESETS, (preset: string[], idx: number) => {
            Column() {
              Stack() {
                Circle().width(40).height(40).fill(preset[0])
                if (idx === this.accentIdx) {
                  Text('✓').fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                }
              }
              Text(preset[1]).fontSize(10).fontColor(ThemeColors.textSecondary).margin({ top: 3 })
            }.margin({ right: 10, bottom: 10 })
            .onClick(() => { AccentColors.select(idx); this.showColorPicker = false; })
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
                this.showColorPicker = false;
                this.customHex = '';
              }
            })
          Button('调色').height(34).fontSize(12)
            .backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(8).margin({ left: 6 })
            .onClick(() => { this.showWheelPicker = true; })
        }.width('100%').margin({ top: 8 })
        .padding({ top: 10 }).border({ width: { top: 1 }, color: '#E0E0E0', style: BorderStyle.Dashed })
      }
      .width('85%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .hitTestBehavior(this.showColorPicker ? HitTestMode.Default : HitTestMode.None)
    .visibility(this.showColorPicker ? Visibility.Visible : Visibility.None)
    .onClick(() => { this.showColorPicker = false; })
    // 无极取色盘
    if (this.showWheelPicker) {
      Column() {
        Column() {
          Row() {
            Text('无极取色').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            Blank()
            Row() { Text('✕').fontSize(18).fontColor('#999999') }
              .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.showWheelPicker = false; })
          }.width('100%').margin({ bottom: 12 })
          ColorWheelPicker({
            onApply: () => {
              this.showWheelPicker = false;
              this.showColorPicker = false;
            }
          })
        }
        .width('90%').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(16)
        .shadow({ radius: 20, color: '#30000000' })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeColors.overlay)
      .onClick(() => { this.showWheelPicker = false; })
    }
    } // closes Stack
    .width('100%').height('100%')
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
            .fontSize(12).fontColor('#2979FF')
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
              .fontSize(12).fontColor('#FFFFFF')
              .backgroundColor(cell.day === this.getTodayDay() ? '#2979FF' : '#43A047')
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
          Text('HiXD').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          if (this.loginStatus === 'ok') {
            Text('已登录').fontSize(11).fontColor('#FF80CC80')
          } else if (this.loginStatus === 'expired') {
            Text('登录已过期').fontSize(11).fontColor('#FFCC8080')
          } else if (this.loginStatus === 'not_logged_in') {
            Text('未登录').fontSize(11).fontColor('#FFFFFF88')
          } else if (this.loginStatus === 'offline') {
            Text('离线模式').fontSize(11).fontColor('#FFFFCC80')
          } else if (this.loginStatus === 'checking') {
            Text('正在验证...').fontSize(11).fontColor('#FFFFFF88')
          }
        }
        Blank()
        if (this.loginStatus === 'ok') {
          Stack() {
            Circle().width(32).height(32).fill('#FFFFFF33')
            Text('👤').fontSize(18).fontColor('#FFFFFFCC')
          }.width(32).height(32)
          Text(this.username || '已登录').fontSize(13).fontColor('#FFFFFFCC').margin({ left: 8 })
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
        List({ space: 8 }) {
          ListItem() {
            this.MenuItemBuilder('📝', '成绩查询', '查看各科成绩和GPA', '#43A047',
              () => { this.pageInfo.clear();
                this.pageInfo.pushPath({ name: 'ScorePage' }); })
          }
          ListItem() {
            this.MenuItemBuilder('📋', '考试安排', '查看考试时间地点', '#FB8C00',
              () => {
                this.pageInfo.clear();
                this.pageInfo.pushPath({ name: 'ExamPage' });
              })
          }
          ListItem() {
            this.MenuItemBuilder('📚', '图书馆', '搜索图书和借阅', '#8E24AA',
              () => { this.pageInfo.clear();
                this.pageInfo.pushPath({ name: 'LibraryPage' }); })
          }
          ListItem() {
            this.MenuItemBuilder('🌐', '校园网', '查看校园网用量', '#00ACC1',
              () => { this.pageInfo.clear();
                this.pageInfo.pushPath({ name: 'SchoolNetPage' }); })
          }
          ListItem() {
            this.MenuItemBuilder('🏫', '空闲教室', '查找空闲自习室', '#F4511E',
              () => { this.pageInfo.clear();
                this.pageInfo.pushPath({ name: 'EmptyClassroomPage' }); })
          }
          ListItem() {
            this.MenuItemBuilder('💳', '校园卡', '查余额和消费记录', '#FF6D00',
              () => { this.pageInfo.clear();
                this.pageInfo.pushPath({ name: 'SchoolCardPage' }); })
          }
          if (!PreferenceUtil.getBool('role')) {
          ListItem() {
            this.MenuItemBuilder('🔬', '实验信息', '查看实验课程安排', '#5C6BC0',
              () => { this.pageInfo.clear();
                this.pageInfo.pushPath({ name: 'ExperimentPage' }); })
          }
          }
          ListItem() {
            this.MenuItemBuilder('\u26a1', '水电查询', '查看宿舍水费电费', '#FF6D00',
              () => { this.pageInfo.clear();
                this.pageInfo.pushPath({ name: 'ElectricityPage' }); })
          }
        }
        .padding({ left: 16, right: 16, top: 8 })
        .layoutWeight(1)
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
        Text('更多功能').fontSize(24).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      }
      .width('100%').height(56).padding({ left: 20 })
      .backgroundColor(ThemeColors.bgCard)
      Divider().color('#F0F0F0')

      List({ space: 8 }) {
        // 外部浏览器跳转
        ListItem() {
          this.MenuItemBuilder('💰', '水电缴费', '线上一键缴纳水电费用', '#E65100',
            () => { this.pageInfo.clear();
              this.pageInfo.pushPath({ name: 'PortalWeb_Dianfei' }); })
        }
        ListItem() {
          this.MenuItemBuilder('💧', '订水系统', '再忙也不要忘记喝水呦！', '#0277BD',
            () => { this.pageInfo.pushPath({ name: 'PortalWeb_Dingshui' }); })
        }
        ListItem() {
          this.MenuItemBuilder('🔧', '后勤报修', '足不出户提交报修', '#5D4037',
            () => { this.pageInfo.pushPath({ name: 'PortalWeb_Baoxiu' }); })
        }
        ListItem() {
          this.MenuItemBuilder('🏢', '空间预约', '找一个可以集体讨论的地方', '#1565C0',
            () => { this.pageInfo.pushPath({ name: 'PortalWeb_Space' }); })
        }
        ListItem() {
          this.MenuItemBuilder('📱', '移动门户', '校园服务一网打尽', '#00695C',
            () => { this.pageInfo.pushPath({ name: 'PortalWeb_Portal' }); })
        }
        ListItem() {
          this.MenuItemBuilder('🧭', '睿思导航', '补充其他功能', '#4527A0',
            () => { this.pageInfo.pushPath({ name: 'PortalWeb_Ruisi' }); })
        }
        ListItem() {
          this.MenuItemBuilder('🔬', '物理计算', '实验数据处理助手', '#00897B',
            () => { this.pageInfo.pushPath({ name: 'PortalWeb_Physics' }); })
        }
        ListItem() {
          this.MenuItemBuilder('🌐', '校园网登录', '登录校园网自助服务平台', '#00ACC1',
            () => { this.pageInfo.pushPath({ name: 'PortalWeb_Net' }); })
        }
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
        Text('我的').fontSize(24).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      }
      .width('100%').height(56).padding({ left: 20 })
      .backgroundColor(ThemeColors.bgCard)
      Divider().color('#F0F0F0')

      // 用户区域：已登录显示信息卡片，未登录显示登录入口，下方菜单始终可见
      if (this.isLoggedIn) {
        // 用户信息卡片
        Column() {
          Row() {
            Stack() {
              Circle().width(56).height(56).fill('#2979FF')
              Text('👤').fontSize(30).fontColor('#FFFFFF')
            }.width(56).height(56)
            Column() {
              Text(this.username || '已登录')
                .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              Text('西电校园助手').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
            }.margin({ left: 16 })
          }.width('100%')
        }
        .width('100%').padding(20).backgroundColor(ThemeColors.bgCard)
        .margin({ left: 16, right: 16, top: 16 }).borderRadius(16)
      } else {
        // 未登录提示
        Button('登录以使用完整功能')
          .width('90%').height(44).fontSize(15).fontColor('#FFFFFF')
          .backgroundColor('#2979FF').borderRadius(22)
          .margin({ top: 24 })
          .onClick(() => { router.pushUrl({ url: 'pages/login/LoginPage' }); })
      }

      // 菜单（始终显示）
      List({ space: 8 }) {
            ListItem() {
              this.MenuItemBuilder('🧪', '物理实验设置（test）',
                this.phyPwdStatus,
                '#7B1FA2',
                () => {
                  this.phyPwdInput = PreferenceUtil.getString('physics_pwd');
                  this.showPhyPwdDialog = true;
                })
            }
            ListItem() {
              // 深色设置——内联实现（不用 MenuItemBuilder），desc 直接读 @State 才能实时刷新
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
              .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .borderRadius(12).backgroundColor(ThemeColors.bgCard)
              .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
              .onClick(() => { this.showThemeDialog = true; })
            }
            ListItem() {
              // 主题色选择——内联实现，实时显示当前色
              Row() {
                Stack({ alignContent: Alignment.Center }) {
                  Circle().width(44).height(44).fill(this.accentColor + '22')
                  Circle().width(20).height(20).fill(this.accentColor)
                }.margin({ right: 16 })
                Column() {
                  Text('主题色').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                  Text(AccentColors.currentName).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                }.layoutWeight(1)
                Text('›').fontSize(20).fontColor('#CCCCCC')
              }
              .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .borderRadius(12).backgroundColor(ThemeColors.bgCard)
              .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
              .onClick(() => { this.showColorPicker = true; })
            }
            ListItem() {
              this.MenuItemBuilder('❓', '常见问题', '使用帮助和问题反馈', '#795548',
                () => { this.pageInfo.clear();
                  this.pageInfo.pushPath({ name: 'FaqPage' }); })
            }
            ListItem() {
              this.MenuItemBuilder('🔓', '退出登录', '清除登录状态', '#FF5252',
                async () => {
                  await PreferenceUtil.putString('ids_account', '');
                  await PreferenceUtil.putString('login_password', '');
                  await HttpUtil.getInstance().clearCookies();
                  this.isLoggedIn = false;
                  this.username = '';
                  this.loginStatus = 'not_logged_in';
                })
            }
            ListItem() {
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
              .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .borderRadius(12).backgroundColor(ThemeColors.bgCard)
              .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
              .onClick(() => {
                this.clearCache();
              })
            }
          }
          .padding({ left: 16, right: 16, top: 8 })
          .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
  }

  // ==================== 通用菜单项 ====================
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

