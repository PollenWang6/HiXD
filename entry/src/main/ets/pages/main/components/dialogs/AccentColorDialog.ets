import { ThemeColors } from '../../../../utils/ThemeColors';
import { AccentColors, ACCENT_PRESETS } from '../../../../utils/AccentColors';

// 主题色选择弹窗（预设色板 + 自定义色号 + 调色盘入口）
@Component
export struct AccentColorDialog {
  @Prop visible: boolean = false;
  @Prop dialogOpacity: number = 1;
  @Prop dialogTranslate: number = 0;
  @Prop accentColor: string = '#2979FF';
  @Prop accentTextColor: string = '#FFFFFF';
  @Prop accentIdx: number = 0;
  onClose: () => void = () => {};
  onOpenWheel: () => void = () => {};
  @State customHex: string = '';

  build() {
    Column() {
      Column() {
        Row() {
          Text('选择主题色').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor(ThemeColors.textSecondary) }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
        }.width('100%').margin({ bottom: 16 })
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(ACCENT_PRESETS, (preset: string[], idx: number) => {
            Column() {
              Stack() {
                Circle().width(40).height(40).fill(ThemeColors.isDark ? preset[1] : preset[0])
                if (idx === this.accentIdx) {
                  Text('✓').fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                }
              }
              Text(preset[2]).fontSize(10).fontColor(ThemeColors.textSecondary).margin({ top: 3 })
            }.margin({ right: 10, bottom: 10 })
            .hoverEffect(HoverEffect.Auto).onClick(() => { AccentColors.select(idx); this.onClose(); })
          }, (preset: string[], idx: number) => String(idx))
        }.width('100%')
        Row() {
          Text('自定义').fontSize(12).fontColor(ThemeColors.textHint)
          Text('#').fontSize(13).fontColor(ThemeColors.textHint).margin({ left: 8, right: 2 })
          TextInput({ placeholder: '色号', text: this.customHex })
            .width(72).height(34).fontSize(13)
            .maxLength(6)
            .placeholderColor(ThemeColors.textHint)
            .backgroundColor(ThemeColors.bgInput).borderRadius(8)
            .onChange((v: string) => { this.customHex = v.replace(/[^0-9A-Fa-f]/g, ''); })
          Row() {
            Circle().width(16).height(16).fill(this.customHex.length === 6 ? ('#' + this.customHex) : '#CCCCCC')
          }.width(32).height(32).borderRadius(8).backgroundColor(ThemeColors.bgInput)
          .justifyContent(FlexAlign.Center).margin({ left: 6, right: 6 })
          Button('应用').height(34).fontSize(12)
            .backgroundColor(this.customHex.length === 6 ? this.accentColor : '#CCCCCC')
            .fontColor('#FFFFFF').borderRadius(8)
            .enabled(this.customHex.length === 6)
            .hoverEffect(HoverEffect.Auto).onClick(() => {
              if (AccentColors.selectCustom('#' + this.customHex)) {
                this.onClose();
                this.customHex = '';
              }
            })
          Button('调色').height(34).fontSize(12)
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor).borderRadius(8).margin({ left: 6 })
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onOpenWheel(); })
        }.width('100%').margin({ top: 8 })
        .padding({ top: 10 }).border({ width: { top: 1 }, color: '#E0E0E0', style: BorderStyle.Dashed })
      }
      .width('85%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
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
