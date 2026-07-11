import { AccentColors } from '../../utils/AccentColors';
import { menuOptions } from '../../utils/MaterialKit';
// PortalWebPage.ets — 门户通用 WebView 页面
// 通过 title + url 参数复用，避免为每个服务单独建文件
import web_webview from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
import { common } from '@kit.AbilityKit';
import { CasLoginService } from '../../services/CasLoginService';
import { HttpUtil } from '../../utils/HttpUtil';
const TAG = 'PortalWebPage';

// 需要拉起外部 App 的自定义 scheme（微信支付、支付宝等）
const EXTERNAL_SCHEMES: string[] = ['weixin://', 'alipays://', 'wechat://'];

// 伪装微信浏览器 UA，绕过移动门户的微信限制
const WE_CHAT_UA: string = 'Mozilla/5.0 (Linux; Android 12; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.88 Mobile Safari/537.36 MicroMessenger/8.0.50';
// 手动切换 UA 标识（参考妮可之记 DailyNic）
const DESKTOP_UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36';
const MOBILE_UA: string = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.5735.196 Mobile Safari/537.36';
const TABLET_UA: string = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.5735.196 Safari/537.36';

const UA_AUTO: number = 0;   // 跟随系统（原生 UA）
const UA_MOBILE: number = 1;
const UA_TABLET: number = 2;
const UA_DESKTOP: number = 3;

@Component
export struct PortalWebPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
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
  @Prop useIncognito: boolean = false;  // 隐私模式，cookie 不持久化
  @State uaMode: number = UA_AUTO;  // 当前 UA 模式
  @State needCxLogin: boolean = false;  // 超星需要先登录

  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private context!: common.UIAbilityContext;

  aboutToDisappear(): void {
    this.portalFullscreen = false;
  }

  // 进入门户页面前刷新 CAS session + 同步 cookie，完成后再加载 WebView
  async aboutToAppear(): Promise<void> {
    this.context = getContext(this) as common.UIAbilityContext;
    if (this.url.includes('seatengine') || this.url.includes('office.chaoxing.com')) {
      // 超星座位预约：入口是西电移动门户 OAuth 代理（xxcapp/uc/api/oauth/index?redirect=…），
      // 代理需要 CAS cookie（已同步到 WebView）来识别用户、现场签发 code/uid 票据并 302 到座位页。
      // 同步注入超星会话确保座位页加载时已有超星登录态（免登）。
      const cxOk: boolean = await CasLoginService.getInstance().checkAndAutoLogin();
      if (cxOk) {
        await CasLoginService.getInstance().syncCasCookieOnly();       // CAS 给 xxcapp 代理
        await CasLoginService.getInstance().ensureChaoxingSessionForWebView(); // 超星给座位页
      }
      // webUrl = this.url（即 OAuth 代理 URL）；代理会 302 跳转，WebView 自动跟踪到座位页
    } else if (this.useWeChatUA) {
      // 移动门户：清除旧脏 cookie + 只同步 CASTGC，避免 route/JSESSIONID/MOD_AUTH_CAS
      // 污染 xxcapp OpenResty 路由 → 子页面显示随机 hash（如 250bb948bd643d8b18f4c0fdd72a059d）
      CasLoginService.getInstance().clearWebViewCookiesForDomain('xxcapp.xidian.edu.cn');
      const t0 = Date.now();
      const loginOk: boolean = await CasLoginService.getInstance().checkAndAutoLogin();
      await CasLoginService.getInstance().syncCasCookieOnly();
    } else if (!this.url.includes('zfw') && !this.url.includes('libspace') && !this.url.includes('ignypt') && !this.url.includes('nav.xdruisi') && !this.url.includes('edu.icoremail.net')) {
      const t0 = Date.now();
      const loginOk: boolean = await CasLoginService.getInstance().checkAndAutoLogin();
      await CasLoginService.getInstance().syncCookiesToWebView();
    } else if (this.url.includes('libspace') || this.url.includes('ignypt')) {
      // libspace/ignypt 对 session cookie 敏感，只同步 CASTGC
      CasLoginService.getInstance().clearWebViewCookiesForDomain(
        this.url.includes('libspace') ? 'libspace.xidian.edu.cn' : 'ignypt.xidian.edu.cn'
      );
      await CasLoginService.getInstance().checkAndAutoLogin();
      await CasLoginService.getInstance().syncCasCookieOnly();
    } else {
    }
    // ===== 诊断：看 WebView CookieJar 里 xxcapp 实际有什么 =====
    const wcmDiag = web_webview.WebCookieManager;
    for (const d of ['xxcapp.xidian.edu.cn', 'ids.xidian.edu.cn']) {
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
            Web({ src: this.webUrl, controller: this.webController, incognitoMode: this.useIncognito })
              .onControllerAttached(() => {
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
              .onPageBegin((event) => {
                this.isLoading = true;
                this.loadError = '';
                const pageUrl: string = event ? event.url : this.url;
              })
              .onPageEnd((event) => {
                this.isLoading = false;
                const pageUrl: string = event ? event.url : this.url;
                // 超星登录成功后跳转到目标 URL
                if (this.needCxLogin && !pageUrl.includes('passport2.chaoxing.com/login') && !pageUrl.includes('passport2.chaoxing.com/wlogin')) {
                  this.needCxLogin = false;
                  this.webUrl = this.url;
                  return;
                }
                // 诊断：加载后看 xxcapp cookie 变了没
                if (this.useWeChatUA && !this.keepWeChatUA) {
                  this.webController.setCustomUserAgent('');
                } else if (!this.useWeChatUA) {
                  this.applyUA();  // 页面跳转后重新应用手动选择的 UA
                }
              })
              .onOverrideUrlLoading((req) => {
                const schemeUrl: string = req.getRequestUrl();
                // 拦截超星 jsbridge:// 协议，避免 ERR_UNKNOWN_URL_SCHEME
                if (schemeUrl.startsWith('jsbridge://')) {
                  return true;
                }
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
              .onHttpErrorReceive((event) => {
                if (event) {
                  const errUrl: string = event.request.getRequestUrl();
                  const errCode: number = event.response.getResponseCode();
                }
              })
              .onErrorReceive((event) => {
                if (event) {
                  const errInfo: string = event.error.getErrorInfo();
                  const errCode: number = event.error.getErrorCode();
                  const errUrl: string = event.request ? event.request.getRequestUrl() : '?';
                  // 忽略 jsbridge:// 等自定义协议的 ERR_UNKNOWN_URL_SCHEME 错误
                  if (errCode === -302 || errUrl.startsWith('jsbridge://')) {
                    return;
                  }
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
    .title({ builder: this.customTitle(), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
        .fontColor(AccentColors.textContrast)
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
      .bindMenu(this.WebviewMenu(), menuOptions())
    }
    .padding({ left: 12, right: 12, top: this.statusBarHeight })
    .height(52 + this.statusBarHeight)
    .width('100%')
  }

  @Builder WebviewMenu() {
    Menu() {
      MenuItem({ content: '刷新', startIcon: $r('app.media.refresh') })
        .onClick(() => { this.webController.refresh(); })
      MenuItem({ content: '切换 UA', builder: this.changeUAMenu(),
        startIcon: $r('app.media.ic_public_rotate_switch'), endIcon: $r('app.media.ic_public_arrow_right') })
        .enabled(!this.useWeChatUA)
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
          }
        })
    }
  }

  @Builder changeUAMenu() {
    Menu() {
      MenuItem({ content: '跟随系统', startIcon: $r('app.media.ic_controlcenter_auto_rotate_filled'), endIcon: (this.uaMode === UA_AUTO ? $r('app.media.checkmark') : undefined) })
        .onClick(() => { this.setUA(UA_AUTO); })
      MenuItem({ content: '手机版', startIcon: $r('app.media.ic_public_devices_phone'), endIcon: (this.uaMode === UA_MOBILE ? $r('app.media.checkmark') : undefined) })
        .onClick(() => { this.setUA(UA_MOBILE); })
      MenuItem({ content: '平板版', startIcon: $r('app.media.ic_device_pad'), endIcon: (this.uaMode === UA_TABLET ? $r('app.media.checkmark') : undefined) })
        .onClick(() => { this.setUA(UA_TABLET); })
      MenuItem({ content: '电脑版', startIcon: $r('app.media.ic_device_matebook'), endIcon: (this.uaMode === UA_DESKTOP ? $r('app.media.checkmark') : undefined) })
        .onClick(() => { this.setUA(UA_DESKTOP); })
    }
  }

  uaIcon(): Resource {
    if (this.uaMode === UA_AUTO) {
      return $r('app.media.ic_controlcenter_auto_rotate_filled');
    } else if (this.uaMode === UA_MOBILE) {
      return $r('app.media.ic_public_devices_phone');
    } else if (this.uaMode === UA_TABLET) {
      return $r('app.media.ic_device_pad');
    } else {
      return $r('app.media.ic_device_matebook');
    }
  }

  setUA(mode: number): void {
    this.uaMode = mode;
    this.applyUA();
    this.webController.refresh();
  }

  applyUA(): void {
    if (this.uaMode === UA_AUTO) {
      this.webController.setCustomUserAgent('');
    } else if (this.uaMode === UA_MOBILE) {
      this.webController.setCustomUserAgent(MOBILE_UA);
    } else if (this.uaMode === UA_TABLET) {
      this.webController.setCustomUserAgent(TABLET_UA);
    } else {
      this.webController.setCustomUserAgent(DESKTOP_UA);
    }
  }
}
