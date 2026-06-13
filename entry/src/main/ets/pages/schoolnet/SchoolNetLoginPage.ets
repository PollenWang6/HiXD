// SchoolNetLoginPage.ets — 校园网 WebView 登录
import web from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
import { HttpUtil } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';

const TAG = 'SchoolNetLogin';

interface PageBeginEvent { url: string; }
interface PageEndEvent { url: string; }
interface ProgressChangeEvent { newProgress: number; }

@Component
export struct SchoolNetLoginPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @State loadProgress: number = 0;
  @State isLoading: boolean = true;
  @State statusText: string = '正在加载登录页面...';
  @State loginHandled: boolean = false;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  webController: web.WebviewController = new web.WebviewController();

  private readonly LOGIN_URL: string = 'https://zfw.xidian.edu.cn/';
  private readonly SUCCESS_PATTERN: RegExp = /srun_portal|index\.html|\/user\/|selfservice/;

  aboutToAppear(): void {
    if (HttpUtil.getInstance().hasCookies('zfw.xidian.edu.cn')) {
      this.statusText = '已保存登录状态，如需重新登录请在下方操作';
    }
  }

  async onLoginSuccess(): Promise<void> {
    if (this.loginHandled) return;
    this.loginHandled = true;
    this.statusText = '登录成功！正在保存...';
    try {
      const zfwCookies: string = await web.WebCookieManager.getCookie('https://zfw.xidian.edu.cn');
      if (zfwCookies && zfwCookies.length > 0) {
        await HttpUtil.getInstance().injectCookies(zfwCookies, 'zfw.xidian.edu.cn');
        await web.WebCookieManager.setCookie('https://zfw.xidian.edu.cn', zfwCookies);
        console.info(TAG, 'Cookies captured for zfw.xidian.edu.cn, length=' + zfwCookies.length);
      }
      await PreferenceUtil.putBool('schoolnet_logged_in', true);
    } catch (e) {
      console.error(TAG, 'Cookie extraction failed: ' + JSON.stringify(e));
    }
    setTimeout(() => { this.pageInfo.pop(); }, 800);
  }

  build() {
    NavDestination() {
      Column() {
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
      }
      .width('100%').height('100%').backgroundColor(ThemeColors.bgCard)
    }
    .title('校园网登录', { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
    .onBackPressed(() => { this.pageInfo.pop(); return true; })
  }
}
