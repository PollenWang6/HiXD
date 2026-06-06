// SchoolNetLoginPage.ets — 校园网 WebView 登录（对齐 eHall LoginPage Cookie 抓取模式）
import web from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
import { router } from '@kit.ArkUI';
import { HttpUtil } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';

const TAG = 'SchoolNetLogin';

interface PageBeginEvent { url: string; }
interface PageEndEvent { url: string; }
interface ProgressChangeEvent { newProgress: number; }

@Entry
@Component
struct SchoolNetLoginPage {
  @State loadProgress: number = 0;
  @State isLoading: boolean = true;
  @State statusText: string = '正在加载登录页面...';
  @State loginHandled: boolean = false;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  webController: web.WebviewController = new web.WebviewController();

  private readonly LOGIN_URL: string = 'https://zfw.xidian.edu.cn/';
  // 登录成功后 URL 特征：不再包含登录页面的路径，通常是首页或用户中心
  private readonly SUCCESS_PATTERN: RegExp = /srun_portal|index\.html|\/user\/|selfservice/;

  aboutToAppear(): void {
    // 始终显示登录页面，不自动返回（用户可能需要重新登录）
    if (HttpUtil.getInstance().hasCookies('zfw.xidian.edu.cn')) {
      this.statusText = '已保存登录状态，如需重新登录请在下方操作';
    }
  }

  /**
   * 登录成功后：抓取 Cookie → 注入 HttpUtil → 保存状态
   * 与 eHall LoginPage.onLoginSuccess() 完全对齐
   */
  async onLoginSuccess(): Promise<void> {
    if (this.loginHandled) return;
    this.loginHandled = true;
    this.statusText = '登录成功！正在保存...';
    try {
      // 1. 从 WebView 提取 Cookie（包含 HttpOnly 的 session cookie）
      const zfwCookies: string = await web.WebCookieManager.getCookie('https://zfw.xidian.edu.cn');
      if (zfwCookies && zfwCookies.length > 0) {
        await HttpUtil.getInstance().injectCookies(zfwCookies, 'zfw.xidian.edu.cn');
        await web.WebCookieManager.setCookie('https://zfw.xidian.edu.cn', zfwCookies);
        console.info(TAG, 'Cookies captured for zfw.xidian.edu.cn, length=' + zfwCookies.length);
      }
      // 2. 保存校园网登录状态
      await PreferenceUtil.putBool('schoolnet_logged_in', true);
    } catch (e) {
      console.error(TAG, 'Cookie extraction failed: ' + JSON.stringify(e));
    }
    setTimeout(() => { router.back(); }, 800);
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('‹').fontSize(26).fontColor(ThemeColors.textPrimary).width(40).textAlign(TextAlign.Center)
          .onClick(() => { router.back(); })
        Text('校园网登录').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('刷新').fontSize(14).fontColor((AppStorage.get('accent_color') as string ?? '#2979FF')).width(40).textAlign(TextAlign.End)
          .onClick(() => {
            this.isLoading = true;
            this.webController.refresh();
          })
      }.width('100%').height(56).padding({ left: 8, right: 16 }).backgroundColor(ThemeColors.bgCard)
      Divider().color('#F0F0F0')

      // 进度条
      if (this.loadProgress < 100 && this.isLoading) {
        Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
          .width('100%').height(3).color('#00ACC1').backgroundColor('#E0E0E0')
      }

      // 状态文字
      if (this.statusText.length > 0) {
        Text(this.statusText).fontSize(12).fontColor(ThemeColors.textSecondary)
          .width('100%').padding({ left: 16, right: 16, top: 8 })
      }

      // WebView
      Web({ src: this.LOGIN_URL, controller: this.webController })
        .width('100%').layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .cacheMode(CacheMode.Default)
        .mixedMode(MixedMode.All)
        .onlineImageAccess(true)
        .onPageBegin((event: PageBeginEvent) => {
          if (event) {
            this.isLoading = true;
            // 检测登录成功（URL 跳转到首页/用户中心）
            if (this.SUCCESS_PATTERN.test(event.url) && !event.url.includes('login')) {
              this.onLoginSuccess();
            }
          }
        })
        .onPageEnd((event: PageEndEvent) => {
          if (event) {
            this.isLoading = false;
            this.loadProgress = 100;
          }
        })
        .onProgressChange((event: ProgressChangeEvent) => {
          if (event) { this.loadProgress = event.newProgress; }
        })
        .onErrorReceive((event) => {
          this.isLoading = false;
          console.warn(TAG, 'Web error: ' + event.error.getErrorInfo());
        })

      // 底部提示
      Column() {
        Text('请使用校园网账号密码登录（非统一身份认证）').fontSize(12).fontColor(ThemeColors.textSecondary)
        Text('登录成功后 Cookie 将自动保存').fontSize(11).fontColor('#BBBBBB').margin({ top: 4 })
      }
      .width('100%').padding({ top: 12, bottom: 20 }).alignItems(HorizontalAlign.Center)
      .backgroundColor('#FAFAFA')
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgCard)
  }
}
