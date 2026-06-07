// PortalWebPage.ets — 门户通用 WebView 页面
// 通过 title + url 参数复用，避免为每个服务单独建文件
import web_webview from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
import { common } from '@kit.AbilityKit';
import { CasLoginService } from '../../services/CasLoginService';
const TAG = 'PortalWebPage';

// 需要拉起外部 App 的自定义 scheme（微信支付、支付宝等）
const EXTERNAL_SCHEMES: string[] = ['weixin://', 'alipays://', 'wechat://'];

// 伪装微信浏览器 UA，绕过移动门户的微信限制
const WE_CHAT_UA: string = 'Mozilla/5.0 (Linux; Android 12; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.88 Mobile Safari/537.36 MicroMessenger/8.0.50';

@Component
export struct PortalWebPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @Prop title: string = '';
  @Prop url: string = '';
  @State webUrl: string = '';  // 等 cookie 就绪后才设置，再加载 WebView
  @Prop useWeChatUA: boolean = false;
  @Prop keepWeChatUA: boolean = false;  // 移动门户：不清理 UA，页面内跳转保持一致
  @State isLoading: boolean = true;
  @State loadError: string = '';
  @StorageLink('portalFullscreen') portalFullscreen: boolean = false;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  @State message: string = '';
  @Prop isTablet: boolean = false;

  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToDisappear(): void {
    this.portalFullscreen = false;
  }

  // 进入门户页面前刷新 CAS session + 同步 cookie，完成后再加载 WebView
  async aboutToAppear(): Promise<void> {
    console.info(TAG, 'aboutToAppear: url=' + this.url.substring(0, 80));
    if (!this.url.includes('zfw') && !this.url.includes('libspace') && !this.url.includes('nav.xdruisi') && !this.url.includes('edu.icoremail.net')) {
      const t0 = Date.now();
      const loginOk: boolean = await CasLoginService.getInstance().checkAndAutoLogin();
      console.info(TAG, 'checkAndAutoLogin: result=' + loginOk + ' cost=' + (Date.now() - t0) + 'ms');
      // 等待 cookie 同步完成（内部先续 TGC 再写 WebView）
      await CasLoginService.getInstance().syncCookiesToWebView();
      console.info(TAG, 'syncCookies done, ready to load WebView');
    } else {
      console.info(TAG, 'syncCookies skip (non-CAS domain)');
    }
    this.webUrl = this.url;  // cookie 就绪，触发 WebView 加载
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {

          // WebView 区域（等 cookie 就绪 webUrl 非空后才创建，避免空 src 加载）
          Stack() {
            if (this.webUrl.length > 0) {
            Web({ src: this.webUrl, controller: this.webController, incognitoMode: this.url.includes('zfw') })
              .onControllerAttached(() => {
                console.info(TAG, 'onControllerAttached: webUrl loaded');
                if (this.useWeChatUA) {
                  this.webController.setCustomUserAgent(WE_CHAT_UA);
                }
              })
              .onSslErrorEventReceive((event) => {
                // 允许证书过期的 HTTPS 站点加载（如 experiment-helper.wizzstudio.com）
                event.handler.handleConfirm();
              })
              .width('100%').height('100%')
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .cacheMode(CacheMode.Default)
              .onPageBegin(() => {
                this.isLoading = true;
                this.loadError = '';
                console.info(TAG, 'onPageBegin: url=' + this.url.substring(0, 80));
              })
              .onPageEnd(() => {
                this.isLoading = false;
                console.info(TAG, 'onPageEnd OK: ' + this.url.substring(0, 80));
                if (this.useWeChatUA && !this.keepWeChatUA) {
                  this.webController.setCustomUserAgent('');
                }
              })
              .onOverrideUrlLoading((req) => {
                const schemeUrl: string = req.getRequestUrl();
                for (let i = 0; i < EXTERNAL_SCHEMES.length; i++) {
                  if (schemeUrl.startsWith(EXTERNAL_SCHEMES[i])) {
                    try {
                      this.context.openLink(schemeUrl);
                    } catch {
                      // scheme 无法拉起，忽略
                    }
                    return true;
                  }
                }
                return false;
              })
              .onErrorReceive((event) => {
                if (event) {
                  const errInfo: string = event.error.getErrorInfo();
                  const errCode: number = event.error.getErrorCode();
                  console.error(TAG, 'onErrorReceive: code=' + errCode + ' info=' + errInfo + ' url=' + this.url.substring(0, 80));
                  this.loadError = '加载失败: ' + errInfo;
                  this.isLoading = false;
                }
              })

            } // closes if(webUrl.length > 0)

            if (this.isLoading) {
              LoadingProgress()
                .width(36).height(36)
                .color(this.accentColor)
            }

            if (this.loadError) {
              Column() {
                Text('⚠️').fontSize(40)
                Text(this.loadError).fontSize(14).fontColor('#C62828').margin({ top: 8 })
                Button('重试').margin({ top: 12 })
                  .onClick(() => {
                    this.loadError = '';
                    this.webController.refresh();
                  })
              }.width('100%').height('100%')
              .justifyContent(FlexAlign.Center).backgroundColor(ThemeColors.bgInput)
            }

            if (this.message) {
              Text(this.message).fontSize(14).fontColor('#FFFFFF')
                .padding(12).backgroundColor('#666666')
                .borderRadius(8).position({ bottom: 48 })
            }
          }
          .width('100%')
          .layoutWeight(1)

          
        }.width('100%').height('100%').backgroundColor(ThemeColors.bgInput)


      }
      .width('100%')
      .height('100%')
    }
    .title(this.customTitle(), { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
    .hideBackButton(true)


  }

  @Builder customTitle() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40)
      .width(40)
      .onClick(() => { this.pageInfo.pop(); })

      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.back'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40)
      .width(40)
      .onClick(() => { this.webController.backward(); })

      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.forth'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40)
      .width(40)
      .onClick(() => { this.webController.forward(); })

      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.more_opinion'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40)
      .width(40)
      .bindMenu(this.WebviewMenu())
    }
    .padding({ left: 12, right: 12 })
    .height(56)
    .width('100%')
  }

  @Builder WebviewMenu() {
    Menu() {
      MenuItem({ content: '刷新', startIcon: $r('app.media.refresh') })
        .onClick(() => { this.webController.refresh(); })
      MenuItem({ content: '全屏展示', startIcon: $r('app.media.ic_public_enlarge') })
        .enabled(this.isTablet && !this.portalFullscreen)
        .onClick(() => { this.portalFullscreen = true; })
      MenuItem({ content: '退出全屏', startIcon: $r('app.media.ic_public_reduce') })
        .enabled(this.isTablet && this.portalFullscreen)
        .onClick(() => { this.portalFullscreen = false; })
      MenuItem({ content: '在浏览器打开', startIcon: $r('app.media.ic_public_worldclock') })
        .onClick(() => {
          this.context.openLink(this.url);
        })

      MenuItem({ content: '清除 Cookies', startIcon: $r('app.media.ic_public_delete') })
        .onClick(() => {
          try {
            web_webview.WebCookieManager.clearAllCookiesSync();
            this.message = '已清除 Cookies，重新打开需登录';
            setTimeout(() => { this.message = ''; }, 2000);
          } catch (e) {
            console.error('PortalWebPage', 'clearCookie error: ' + String(e));
          }
        })
    }
  }
}
