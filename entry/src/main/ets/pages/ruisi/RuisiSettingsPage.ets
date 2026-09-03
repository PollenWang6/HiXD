// RuisiSettingsPage.ets — 设置

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiService } from '../../services/ruisi/RuisiService';
import { ToastUtil } from '../../utils/ToastUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'RuisiSettings';

@Component
export struct RuisiSettingsPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('ruisi_logged_in') isLoggedIn: boolean = false;
  pageInfo: NavPathStack = new NavPathStack();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  async clearCache(): Promise<void> {
    try {
      await RuisiService.getInstance().clearCookies();
      ToastUtil.show('已清除缓存');
    } catch (e) { ToastUtil.show('清除失败'); }
  }

  @Builder
  headerBuilder() {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .width(22).height(22)
          .fillColor(this.accentTextColor())
          .draggable(false)
      }
      .width(40).height(40)
      .backgroundColor('rgba(255,255,255,0.18)')
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.pageInfo.pop(); })
      .margin({ right: 12 })

      Text('设置')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
    }.width('100%').height('100%').padding({ left: 12, right: 16, top: this.statusBarHeight }).backgroundColor(this.accentColor)
  }

  build() {
    NavDestination() {
      Column() {
      // 设置项
      Column() {
        // 清除缓存
        Row() {
          Text('清除缓存').fontSize(15).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          Text('>').fontSize(16).fontColor(ThemeColors.textHint)
        }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 }).backgroundColor(ThemeColors.bgCard)
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.clearCache(); })

        Row().height(0.5).width('100%').backgroundColor(ThemeColors.border)

        // 关于
        Row() {
          Text('关于').fontSize(15).fontColor(ThemeColors.textPrimary).layoutWeight(1)
          Text('>').fontSize(16).fontColor(ThemeColors.textHint)
        }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 }).backgroundColor(ThemeColors.bgCard)
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.pageInfo.pushPath({ name: 'RuisiAbout' }); })

        Row().height(0.5).width('100%').backgroundColor(ThemeColors.border)

        // 退出登录
        Row() {
          Text('退出登录').fontSize(15).fontColor('#C62828').layoutWeight(1)
        }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 }).backgroundColor(ThemeColors.bgCard)
        .hoverEffect(HoverEffect.Auto).onClick(async () => {
          // 先翻 UI 态：即使 clearCookies 异常也立刻回到登录页，杜绝卡在已登录界面
          this.isLoggedIn = false;
          try {
            await RuisiService.getInstance().clearCookies();
          } catch (e) {
            hilog.error(0xFF00, TAG, 'clearCookies on logout failed: ' + JSON.stringify(e));
          }
          hilog.info(0xFF00, TAG, 'logout done, isLoggedIn()=' + RuisiService.getInstance().isLoggedIn());
          this.pageInfo.pop();
        })
      }.margin({ top: 8 })
    }
    .width('100%').height('100%')
    .backgroundColor(ThemeColors.bgPage)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  .title({ builder: this.headerBuilder(), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
  .hideBackButton(true)
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
