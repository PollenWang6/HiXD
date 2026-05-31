// Index.ets — 入口页面：直接进入主页
import { ThemeColors } from '../utils/ThemeColors';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  aboutToAppear() { this.routeToPage(); }

  async routeToPage() {
    await new Promise<void>((resolve) => setTimeout(resolve, 50));
    router.replaceUrl({ url: 'pages/MainPage' });
  }

  build() {
    Column() {
      LoadingProgress().width(48).height(48).color('#2979FF')
      Text('HiXD').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#2979FF').margin({ top: 16 })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(ThemeColors.bgCard)
  }
}
