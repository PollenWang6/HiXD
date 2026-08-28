import { AccentColors } from '../../utils/AccentColors';
// MobilePortalPage.ets — 移动门户（应用内 WebView，复用 CAS 登录态）
import web_webview from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
const TAG = 'MobilePortalPage';

const PORTAL_URL = 'https://xxcapp.xidian.edu.cn/site/xidianPage/home';

@Component
export struct MobilePortalPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @State isLoading: boolean = true;
  @State loadError: string = '';

  @Builder buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40).width(40)
      .onClick(() => { this.pageInfo.pop(); })
      Text(t)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AccentColors.textContrast)
        .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 16 })
  }

  private webController: web_webview.WebviewController = new web_webview.WebviewController();

  build() {
    NavDestination() {
      Column() {
      // WebView 区域
      Stack() {
        Web({ src: PORTAL_URL, controller: this.webController })
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
          })
          .onErrorReceive((event) => {
            if (event) {
              this.loadError = '加载失败: ' + event.error.getErrorInfo();
              this.isLoading = false;
            }
          })

        // 加载中动画
        if (this.isLoading) {
          LoadingProgress()
            .width(36).height(36)
            .color(this.accentColor)
        }

        // 加载错误提示
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
      }
      .width('100%')
      .layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgInput)
    .title({ builder: this.buildWhiteTitle('移动门户'), height: 56 }, { backgroundColor: this.accentColor })
    .hideBackButton(true)
  }
}
}
