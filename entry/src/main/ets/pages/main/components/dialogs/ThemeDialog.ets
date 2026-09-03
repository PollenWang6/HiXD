import { ThemeColors } from '../../../../utils/ThemeColors';
import { ConfigurationConstant } from '@kit.AbilityKit';

// 深色模式选择弹窗
@Component
export struct ThemeDialog {
  @Prop visible: boolean = false;
  @Prop dialogOpacity: number = 1;
  @Prop dialogTranslate: number = 0;
  @Prop accentColor: string = '#2979FF';
  @Prop currentPref: number = 0;
  onClose: () => void = () => {};
  onSelect: (mode: number) => void = (mode: number) => {};

  build() {
    Column() {
      Column() {
        Row() {
          Text('深色设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor(ThemeColors.textSecondary) }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
        }.width('100%').margin({ bottom: 16 })
        Button('浅色').width('100%').height(44)
          .backgroundColor(this.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? this.accentColor : ThemeColors.bgInput)
          .fontColor(this.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT ? '#FFFFFF' : ThemeColors.textPrimary)
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.onSelect(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT); })
        Button('深色').width('100%').height(44).margin({ top: 8 })
          .backgroundColor(this.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? this.accentColor : ThemeColors.bgInput)
          .fontColor(this.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? '#FFFFFF' : ThemeColors.textPrimary)
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.onSelect(ConfigurationConstant.ColorMode.COLOR_MODE_DARK); })
        Button('跟随系统').width('100%').height(44).margin({ top: 8 })
          .backgroundColor(this.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET ? this.accentColor : ThemeColors.bgInput)
          .fontColor(this.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET ? '#FFFFFF' : ThemeColors.textPrimary)
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.onSelect(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET); })
      }
      .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.dialogOpacity)
      .translate({ y: this.dialogTranslate })
      .hoverEffect(HoverEffect.Auto).onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.dialogOpacity)
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
    .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
  }
}
