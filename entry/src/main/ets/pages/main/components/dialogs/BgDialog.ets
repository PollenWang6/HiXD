import { ThemeColors } from '../../../../utils/ThemeColors';

// 自定义课表背景弹窗（受控组件：状态由 MainPage 持有）
@Component
export struct BgDialog {
  @Prop visible: boolean = false;
  @Prop dialogOpacity: number = 1;
  @Prop dialogTranslate: number = 0;
  @Prop isTablet: boolean = false;
  @Prop accentColor: string = '#2979FF';
  @Prop accentTextColor: string = '#FFFFFF';
  @Prop bgShow: boolean = false;
  @Prop bgPath: string = '';
  @Prop bgOpacityVal: number = 60;
  onClose: () => void = () => {};
  onToggle: (value: boolean) => void = (value: boolean) => {};
  onOpacityChange: (value: number) => void = (value: number) => {};
  onSelectImage: () => void = () => {};
  onSave: () => void = () => {};

  build() {
    Column() {
      Column() {
        Text('自定义课表背景').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).margin({ bottom: 16 })
        Row() {
          Text('启用自定义背景').fontSize(15).fontColor(ThemeColors.textPrimary)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.bgShow })
            .selectedColor(this.accentColor)
            .onChange((value: boolean) => { this.onToggle(value); })
        }.width('100%').margin({ bottom: 12 })
        Stack({ alignContent: Alignment.Center }) {
          Image(this.bgPath.length > 0 ? this.bgPath : $r('app.media.background'))
            .width('100%')
            .aspectRatio(this.isTablet ? 4 / 3 : 3 / 4)
            .constraintSize({ maxHeight: 300 })
            .objectFit(ImageFit.Cover)
            .borderRadius(10)
            .opacity(this.bgPath.length > 0 ? (this.bgShow ? this.bgOpacityVal / 100 : 0.15) : 0.06)
            .interpolation(ImageInterpolation.Medium)
          if (this.bgPath.length === 0) {
            Text('📷 点此选择图片').fontSize(14).fontColor(ThemeColors.textHint)
          } else if (!this.bgShow) {
            Text('已关闭').fontSize(13).fontColor('#FFFFFF')
              .backgroundColor('rgba(0,0,0,0.5)').borderRadius(6)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          }
        }
        .width('100%').borderRadius(10)
        .backgroundColor(ThemeColors.bgInput)
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.onSelectImage(); })
        .margin({ bottom: 12 })
        Button('选择图片').fontSize(14)
          .backgroundColor(ThemeColors.isDark ? '#1A3A5C' : '#E3F2FD')
          .fontColor(this.accentColor)
          .borderRadius(8)
          .margin({ bottom: 12 })
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.onSelectImage(); })
        Row() {
          Text('不透明度').fontSize(13).fontColor(ThemeColors.textSecondary)
          Slider({
            value: this.bgOpacityVal,
            min: 30,
            max: 100,
            step: 5
          }).width('60%')
            .trackColor(ThemeColors.bgInput)
            .selectedColor(this.accentColor)
            .onChange((value: number) => { this.onOpacityChange(value); })
          Text(this.bgOpacityVal + '%').fontSize(13)
            .fontColor(ThemeColors.textPrimary).width(36).textAlign(TextAlign.End)
        }.width('100%').margin({ bottom: 16 })
        Row({ space: 10 }) {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary)
            .borderRadius(10)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
          Button('保存').layoutWeight(1).height(40)
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor)
            .borderRadius(10)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onSave(); })
        }.width('100%')
      }
      .width('85%').padding(20).backgroundColor(ThemeColors.bgCard).borderRadius(16)
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
