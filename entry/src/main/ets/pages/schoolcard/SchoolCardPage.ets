// SchoolCardPage.ets — 校园卡页面（WebView 套壳方案）
// 直接加载 v8scan 校园卡系统，复用 WebView CAS 登录态
import web_webview from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
const TAG = 'SchoolCardPage';

const SCHOOL_CARD_URL = 'https://v8scan.xidian.edu.cn/home/openXDOAuth2Page';

@Component
export struct SchoolCardPage {
  pageInfo: NavPathStack = new NavPathStack();
  @State isLoading: boolean = true;
  @State loadError: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  private webController: web_webview.WebviewController = new web_webview.WebviewController();

  build() {
    NavDestination() {
      Column() {
      // 顶部导航栏
      // WebView 区域
      Stack() {
        Web({ src: SCHOOL_CARD_URL, controller: this.webController })
          .width('100%').height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .cacheMode(CacheMode.Default)
          .onPageBegin((event) => {
            this.isLoading = true;
            this.loadError = '';
          })
          .onPageEnd((event) => {
            this.isLoading = false;
          })
          .onErrorReceive((event) => {
            if (event) {
              console.error(TAG, 'WebView error: ' + event.error.getErrorInfo());
              this.loadError = '加载失败: ' + event.error.getErrorInfo();
              this.isLoading = false;
            }
          })

        // 加载中覆盖层
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(48).height(48).color('#FF6D00')
            Text('正在加载校园卡...').fontSize(14).fontColor(ThemeColors.textSecondary)
              .margin({ top: 16 })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .backgroundColor(ThemeColors.bgInput)
        }

        // 错误覆盖层
        if (this.loadError.length > 0) {
          Column() {
            Text('💳').fontSize(48)
            Text(this.loadError).fontSize(14).fontColor(ThemeColors.textSecondary)
              .margin({ top: 12 }).maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Button('重新加载')
              .fontSize(14).fontColor('#FFFFFF').backgroundColor('#FF6D00')
              .borderRadius(20).height(36).margin({ top: 20 })
              .onClick(() => {
                this.loadError = '';
                this.isLoading = true;
                this.webController.loadUrl(SCHOOL_CARD_URL);
              })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .backgroundColor(ThemeColors.bgInput)
          .padding(24)
        }
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%')
    }
    .title('校园卡')
    .onReady((ctx: NavDestinationContext) => {})
  }
}
