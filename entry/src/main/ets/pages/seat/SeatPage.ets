// SeatPage.ets — 座位预约
// 用 HiXD 现有的 CAS→超星 SSO 桥产出的 passport2 会话，经
// v1.chaoxing.com/mobile/redirectApp?mAppId=20002259（超星一级 App 跳转器，
// 签发超星自有 OAuth code，非微信）进入 seatengine 真实选座界面。
// 实现：WebView 容器 + 把 HttpUtil cookieStore 里的超星 passport2 cookie 注入 WebView CookieJar。
import web_webview from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
import { CasLoginService } from '../../services/auth/CasLoginService';
import { AttendanceService } from '../../services/ids/AttendanceService';
import { HttpUtil } from '../../utils/HttpUtil';

// 座位预约入口（超星一级 App 跳转器，签发超星自有 OAuth code，非微信）
const SEAT_URL: string = 'https://v1.chaoxing.com/mobile/redirectApp?mAppId=20002259';

// 伪装学习通 App 的移动 UA，让 seatengine SPA 走移动端渲染
const MOBILE_UA: string =
  'Mozilla/5.0 (Linux; Android 12; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.5735.196 Mobile Safari/537.36';

// 超星 cookie 需要注入的 WebView 域名（Domain 统一用 .chaoxing.com）
const CX_WEBVIEW_DOMAINS: string[] = [
  'passport2.chaoxing.com',
  'i.chaoxing.com',
  'chaoxing.com',
  'v1.chaoxing.com',
  'office.chaoxing.com',
  'reserve.chaoxing.com',
  'fanya.chaoxing.com',
  'xdspoc.fanya.chaoxing.com',
];

@Component
export struct SeatPage {
  pageInfo: NavPathStack = new NavPathStack();
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @Prop isTablet: boolean = false;

  private webController: web_webview.WebviewController = new web_webview.WebviewController();

  // UI 状态
  @State webUrl: string = '';          // 等 cookie 就绪后才设置，再加载 WebView
  @State isLoading: boolean = true;
  @State errText: string = '';         // 会话准备失败时的错误提示

  aboutToAppear(): void {
    this.startLoginFlow();
  }

  // ===== 登录主流程 =====
  async startLoginFlow(): Promise<void> {
    try {
      // 1. 确保西电 CAS 登录态（TGC）
      await CasLoginService.getInstance().checkAndAutoLogin();

      // 2. CAS→超星 SSO，建立 fanya.chaoxing.com 会话
      await AttendanceService.getInstance().loginToLearning();

      const http: HttpUtil = HttpUtil.getInstance();

      // 3. 把 fanya 子域 cookie 复制到超星主站域（passport2/i/chaoxing）
      const srcDomains: string[] = [
        'fanya.chaoxing.com', 'xdspoc.fanya.chaoxing.com',
        'fycourse.fanya.chaoxing.com', 'mobilelearn.chaoxing.com',
      ];
      const cxDomains: string[] = ['i.chaoxing.com', 'passport2.chaoxing.com', 'chaoxing.com'];
      for (let si = 0; si < srcDomains.length; si++) {
        for (let di = 0; di < cxDomains.length; di++) {
          http.copyCookiesForDomain(srcDomains[si], cxDomains[di]);
        }
      }

      // 4. 额外 GET i.chaoxing.com/base，夯实 passport2 主站会话
      try {
        await http.get('https://i.chaoxing.com/base');
      } catch (e) {
        // 非致命：只要 passport2 cookie 已就绪即可驱动跳转
      }

      // 5. 同步西电 CAS cookie 到 WebView（保持与门户一致，无害）
      await CasLoginService.getInstance().syncCookiesToWebView();

      // 6. 把超星 passport2 cookie 注入 WebView CookieJar
      this.injectChaoxingCookies(http);

      // 7. 触发 WebView 加载座位入口
      this.errText = '';
      this.webUrl = SEAT_URL;
    } catch (e) {
      this.errText = '会话准备失败，请先在本应用登录西电账号与超星学习通';
      this.isLoading = false;
    }
  }

  // 把 HttpUtil cookieStore 里的超星 cookie 注入 WebView（Domain=.chaoxing.com）
  private injectChaoxingCookies(http: HttpUtil): void {
    const WCM = web_webview.WebCookieManager;
    for (let i = 0; i < CX_WEBVIEW_DOMAINS.length; i++) {
      const dom: string = CX_WEBVIEW_DOMAINS[i];
      const ck: string = http.getAllCookies(dom);
      if (ck.length === 0) continue;
      for (const kv of ck.split('; ')) {
        const t: string = kv.trim();
        if (t.length === 0) continue;
        try {
          WCM.setCookie('https://' + dom, t + '; Domain=.chaoxing.com; Path=/');
        } catch (e) { /* ignore */ }
      }
    }
  }

  // ===== UI =====
  @Builder
  titleBar() {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22).fillColor(ThemeColors.textPrimary).draggable(false)
      }
      .height(40).width(40)
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.pageInfo.pop(); })

      Text('座位预约')
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.refresh'))
          .height(20).fillColor(ThemeColors.textPrimary).draggable(false)
      }
      .height(40).width(40)
      .hoverEffect(HoverEffect.Auto).onClick(() => {
        this.webUrl = '';
        this.errText = '';
        this.startLoginFlow();
      })
    }
    .width('100%').height(52 + this.statusBarHeight)
    .padding({ left: 12, right: 12, top: this.statusBarHeight })
    .backgroundColor(this.accentColor)
  }

  build() {
    NavDestination() {
      Column() {
        this.titleBar()

        // 失败提示
        if (this.errText.length > 0) {
          Column() {
            Text(this.errText)
              .fontSize(15).fontColor(ThemeColors.textSecondary)
              .textAlign(TextAlign.Center)
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // WebView 区域（等 cookie 就绪 webUrl 非空后才创建，避免空 src 加载）
          Stack() {
            if (this.webUrl.length > 0) {
              Web({ src: this.webUrl, controller: this.webController })
                .onControllerAttached(() => {
                  this.webController.setCustomUserAgent(MOBILE_UA);
                })
                .onSslErrorEventReceive((event) => {
                  event.handler.handleConfirm();
                })
                .width('100%').height('100%')
                .javaScriptAccess(true)
                .domStorageAccess(true)
                .mixedMode(MixedMode.All)
                .cacheMode(CacheMode.Default)
                .onPageBegin((event) => {
                  this.isLoading = true;
                })
                .onPageEnd((event) => {
                  this.isLoading = false;
                })
                .onOverrideUrlLoading((req) => {
                  const schemeUrl: string = req.getRequestUrl();
                  if (schemeUrl.startsWith('jsbridge://')) {
                    return true;
                  }
                  return false;
                })
                .onErrorReceive((event) => {
                  if (event) {
                    const errCode: number = event.error.getErrorCode();
                    const errUrl: string = event.request ? event.request.getRequestUrl() : '?';
                    if (errCode === -302 || errUrl.startsWith('jsbridge://')) {
                      return;
                    }
                    // 仅主框架错误才提示，子资源（图片等）失败不阻断页面
                    if (event.request && !event.request.isMainFrame()) {
                      return;
                    }
                    this.isLoading = false;
                  }
                })
            }

            // 加载指示器：登录流程中（webUrl 为空）也显示，避免白屏
            if (this.isLoading) {
              LoadingProgress().width(36).height(36).color(this.accentColor)
            }
          }
          .width(this.isTablet ? '60%' : '100%')
          .layoutWeight(1)
          .alignSelf(ItemAlign.Center)
          .backgroundColor(ThemeColors.bgPage)
        }
      }
      .width('100%').height('100%')
      .backgroundColor(ThemeColors.bgPage)
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      let canGoBack = false;
      try {
        canGoBack = this.webController.accessBackward();
      } catch (_e) {
        // WebView 尚未关联组件（页面仍在加载、webUrl 为空），无法判断网页历史
      }
      if (canGoBack) {
        try { this.webController.backward(); } catch (_e) { }
        return true;
      }
      // 已到网页根目录：退出子页面，回到主页（与左上角 ❌ 等价）
      this.pageInfo.pop();
      return true;
    })
  }
}
