import { AccentColors } from '../../utils/AccentColors';
import { menuOptions } from '../../utils/MaterialKit';
// PortalWebPage.ets — 门户通用 WebView 页面
// 通过 title + url 参数复用，避免为每个服务单独建文件
import web_webview from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
import { common } from '@kit.AbilityKit';
import { CasLoginService } from '../../services/CasLoginService';
import { HttpUtil } from '../../utils/HttpUtil';
import { ToastUtil } from '../../utils/ToastUtil';
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
  @State message: string = '';
  @Prop isTablet: boolean = false;
  @Prop useIncognito: boolean = false;  // 隐私模式，cookie 不持久化
  @State uaMode: number = UA_AUTO;  // 当前 UA 模式
  @State needCxLogin: boolean = false;  // 超星需要先登录
  @State canForward: boolean = false;  // 菜单里是否可前进（避免在菜单子树里直接调 controller 崩 17100001）

  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private context!: common.UIAbilityContext;

  aboutToDisappear(): void {
    this.portalFullscreen = false;
  }

  // 把 HttpUtil 单例（与主页校园网同一实例）里已登录的 zfw.xidian.edu.cn 会话
  // 注入 WebView 的 CookieJar，使「更多功能→校园网」打开 w.xidian.edu.cn 后跳转 zfw 时
  // WebView 已是与主页同账号的登录态；并先清除 WebView 残留的脏 cookie（避免带脏会话
  // 访问 /site/sso 被服务端判为失效票据而 404）。
  private syncZfwSessionToWebView(): void {
    CasLoginService.getInstance().clearWebViewCookiesForDomain('zfw.xidian.edu.cn');
    const zfwCookies: string = HttpUtil.getInstance().getCookiesForDomain('zfw.xidian.edu.cn');
    if (zfwCookies.length > 0) {
      for (const kv of zfwCookies.split('; ')) {
        const trimmed: string = kv.trim();
        if (trimmed.length === 0) continue;
        try {
          web_webview.WebCookieManager.setCookie(
            'https://zfw.xidian.edu.cn',
            trimmed + '; Domain=.xidian.edu.cn; Path=/'
          );
        } catch (e) { /* ignore */ }
      }
    }
  }

  // 进入门户页面前刷新 CAS session + 同步 cookie，完成后再加载 WebView
  async aboutToAppear(): Promise<void> {
    try {
      this.context = getContext(this) as common.UIAbilityContext;
      if (this.useWeChatUA) {
        // 移动门户：清除旧脏 cookie + 只同步 CASTGC，避免 route/JSESSIONID/MOD_AUTH_CAS
        // 污染 xxcapp OpenResty 路由 → 子页面显示随机 hash（如 250bb948bd643d8b18f4c0fdd72a059d）
        CasLoginService.getInstance().clearWebViewCookiesForDomain('xxcapp.xidian.edu.cn');
        const t0 = Date.now();
        const loginOk: boolean = await CasLoginService.getInstance().checkAndAutoLogin();
        await CasLoginService.getInstance().syncCasCookieOnly();
      } else if (!this.url.includes('zfw') && !this.url.includes('libspace') && !this.url.includes('ignypt') && !this.url.includes('nav.xdruisi') && !this.url.includes('edu.icoremail.net')) {
        const t0 = Date.now();
        await CasLoginService.getInstance().checkAndAutoLogin();
        if (this.url.includes('order.xidian.edu.cn')) {
          // 订水系统：经 xxcapp OAuth 的 CAS 单点登录页面（已用本机 Edge 实地验证重定向链
          // order/thirdoauth/oauth2Xidian → xxcapp cas-login → ids CAS 登录页）。与 ignypt 同理，
          // 需 xxcapp 已初始化的干净 session：清 order/xxcapp/ignypt 脏 cookie → 预热注入 xxcapp
          // 干净 session（injectXxcappSession，其内会走 order OAuth 触发 xxcapp 登录）→ 补 CASTGC。
          CasLoginService.getInstance().clearWebViewCookiesForDomain('xxcapp.xidian.edu.cn');
          CasLoginService.getInstance().clearWebViewCookiesForDomain('order.xidian.edu.cn');
          CasLoginService.getInstance().clearWebViewCookiesForDomain('ignypt.xidian.edu.cn');
          await CasLoginService.getInstance().injectXxcappSession();
          await CasLoginService.getInstance().syncCasCookieOnly();
        } else {
          await CasLoginService.getInstance().syncCookiesToWebView();
          // 打通主页原生校园网已登录的 zfw 会话到 WebView：
          // 主页 SchoolNetPage 经 SchoolnetService 用 HttpUtil 单例登录 zfw，会话 cookie 只留在
          // HttpUtil，WebView 拿不到；且关隐私模式后 WebView 残留脏 cookie → /site/sso 404。
          // 此处把 HttpUtil 里已登录的 zfw 会话注入 WebView，并先清掉脏 cookie。
          this.syncZfwSessionToWebView();
        }
      } else if (this.url.includes('libspace')) {
        // libspace 对 session cookie 敏感，只同步 CASTGC
        CasLoginService.getInstance().clearWebViewCookiesForDomain('libspace.xidian.edu.cn');
        await CasLoginService.getInstance().checkAndAutoLogin();
        await CasLoginService.getInstance().syncCasCookieOnly();
      } else if (this.url.includes('ignypt')) {
        // ignypt 经 xxcapp OAuth 跨域跳转。根据 FaqPage 历史提示「先进入订水系统完成初始化再进入」
        // 可知 ignypt 链要求 xxcapp 存在一个已初始化的干净 session，而非清掉后让 WebView 重协商
        // （重协商的 xxcapp route 与 ignypt 验证链不一致 → 子页随机 hash/抽风）。
        // 故：清 xxcapp+ignypt 脏 cookie → 预热 xxcapp OAuth 建立干净 session 并注入 WebView
        // （injectXxcappSession）→ 补注入 CASTGC，让 WebView 直接带干净 xxcapp session + CASTGC 走链。
        CasLoginService.getInstance().clearWebViewCookiesForDomain('xxcapp.xidian.edu.cn');
        CasLoginService.getInstance().clearWebViewCookiesForDomain('ignypt.xidian.edu.cn');
        await CasLoginService.getInstance().checkAndAutoLogin();
        await CasLoginService.getInstance().injectXxcappSession();
        await CasLoginService.getInstance().syncCasCookieOnly();
      } else {
      }
    } catch (e) {
      // 任意同步 / cookie 同步异常（如门禁拦截、CAS 服务不可达、WebView cookie 接口异常）
      // 都不应阻断 WebView 加载，否则会卡在永久转圈 / 白屏。降级为直接加载目标 URL，
      // 由页面自身登录流程兜底（门禁页 / 登录页会正常显示，而非白屏）。
      console.error('PortalWebPage cookie 同步失败，降级直接加载: ' + (e as Error)?.message);
    } finally {
      this.isLoading = false;
      this.webUrl = this.url;  // 无论成功失败都触发 WebView 加载，避免白屏/永久转圈
    }
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
              .mixedMode(MixedMode.All)
              .onPageBegin((event) => {
                this.isLoading = true;
                this.loadError = '';
                const pageUrl: string = event ? event.url : this.url;
              })
              .onPageEnd((event) => {
                this.isLoading = false;
                const pageUrl: string = event ? event.url : this.url;
                // 落到 CAS 登录页 = SSO 失败（CASTGC 未注入或已失效）
                if (pageUrl.includes('ids.xidian.edu.cn/authserver/login')) {
                  console.error('[PortalWebPage] SSO 失败：WebView 落到 CAS 登录页，CASTGC 未注入或已失效');
                  // 水电/订水/移动门户等均借用 App 的西电 CAS 登录态，无独立账号。
                  // 落 CAS 页即说明 App 登录态已失效，明确提示用户去重新登录 App，避免对着登录页茫然。
                  ToastUtil.show('西电登录态已失效，请到「我的」重新登录 App 后再访问');
                }
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
                // 同步前进可用性，供右上角菜单读取（菜单子树里不能直接调 controller）
                try {
                  this.canForward = this.webController.accessForward();
                } catch (_e) {
                  this.canForward = false;
                }
              })
              .onOverrideUrlLoading((req) => {
                const schemeUrl: string = req.getRequestUrl();
                // 西电校园网门户 SSO 会把 302 跳到明文 http://zfw.xidian.edu.cn，
                // ArkWeb 顶到明文降级链接会误报 404；统一升级为 https 规避
                if (schemeUrl.startsWith('http://zfw.xidian.edu.cn')) {
                  this.webController.loadUrl(schemeUrl.replace('http://', 'https://'));
                  return true;
                }
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
                  // 校园网门户 SSO 跳 zfw.xidian.edu.cn/site/sso 在 WebView 里会误报 404
                  // （实为明文 http 降级链导致），直接改走可用的 https 登录页（服务端实测 200）
                  if (errCode === 404 && event.request.isMainFrame()
                    && errUrl.includes('zfw.xidian.edu.cn/site/sso')) {
                    // 已登录态直接进主页；未登录服务端会自行 302 到 /login
                    this.webController.loadUrl('https://zfw.xidian.edu.cn/');
                  }
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
                  // 只处理主框架(main frame)错误；子资源(图片/JS/CSS)加载失败
                  // 不应盖住整页（如 repair.xidian.edu.cn 某图片 ERR_CONTENT_LENGTH_MISMATCH）
                  if (event.request && !event.request.isMainFrame()) {
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
    // 系统返回手势 = 网页后退（在门户历史里退一步）；到根则退出子页面回到主页（与左上角 ❌ 等价）
    .onBackPressed(() => {
      let canGoBack = false;
      try {
        canGoBack = this.webController.accessBackward();
      } catch (_e) {
        // WebView 尚未关联组件，忽略
      }
      if (canGoBack) {
        try { this.webController.backward(); } catch (_e) { }
        return true;
      }
      // 已到网页根目录：退出子页面，回到主页
      this.pageInfo.pop();
      return true;
    })


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
        Image($r('app.media.refresh'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40)
      .width(40)
      .onClick(() => { this.webController.refresh(); })

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
      MenuItem({ content: '前进', startIcon: $r('app.media.forth') })
        .enabled(this.canForward)
        .onClick(() => {
          try { this.webController.forward(); } catch (_e) { }
        })
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
    // 在「切换 UA」子菜单的 onClick 里调用，上下文与 Web 组件解耦；
    // 包裹 try/catch 避免 WebviewController 未关联组件时报 17100001 被系统强杀（同类于「前进」菜单项）。
    try {
      this.applyUA();
      this.webController.refresh();
    } catch (_e) {
    }
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
