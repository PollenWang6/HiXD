import { ThemeColors } from '../../../../utils/ThemeColors';
import { ColorWheelPicker } from '../../../../components/ColorWheelPicker';

// 无极取色盘弹窗（包 ColorWheelPicker）
@Component
export struct WheelPickerDialog {
  @Prop visible: boolean = false;
  @Prop dialogOpacity: number = 1;
  @Prop dialogTranslate: number = 0;
  onClose: () => void = () => {};
  onPickerCancel: () => void = () => {};

  build() {
    Column() {
      Column() {
        Row() {
          Text('无极取色').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor(ThemeColors.textSecondary) }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
        }.width('100%').margin({ bottom: 12 })
        ColorWheelPicker({
          onCancel: () => { this.onPickerCancel(); }
        })
      }
      .width('310vp').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.dialogOpacity)
      .translate({ y: this.dialogTranslate })
      .hoverEffect(HoverEffect.Auto).onClick(() => { /* 吞掉事件 */ })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.dialogOpacity)
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
    .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
  }
}
