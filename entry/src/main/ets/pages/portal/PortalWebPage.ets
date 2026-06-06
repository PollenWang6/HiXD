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
  pageInfo: NavPathStack = new NavPathStack();
  @Prop title: string = '';
  @Prop url: string = '';
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

  build() {
    NavDestination() {
      Stack() {
        Column() {

          // WebView 区域
          Stack() {
            Web({ src: this.url, controller: this.webController })
              .onControllerAttached(() => {
                // 只对 CAS 保护域名的页面同步 cookie，避免污染 libspace/sysj 等独立站点
                if (!this.url.includes('libspace') && !this.url.includes('nav.xdruisi') && !this.url.includes('zfw')) {
                  CasLoginService.getInstance().syncCookiesToWebView();
                }
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
              })
              .onPageEnd(() => {
                this.isLoading = false;
                console.info(TAG, 'PageOK: ' + this.url.substring(0, 60));
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
                  console.error(TAG, 'PageFAIL: ' + this.url.substring(0, 60) + ' err=' + event.error.getErrorInfo());
                  this.loadError = '加载失败: ' + event.error.getErrorInfo();
                  this.isLoading = false;
                }
              })

            if (this.isLoading) {
              LoadingProgress()
                .width(36).height(36)
                .color('#00695C')
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
    .title(this.customTitle(), { backgroundColor: ThemeColors.bgCard })
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
