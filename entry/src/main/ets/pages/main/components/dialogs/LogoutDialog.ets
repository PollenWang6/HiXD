import { ThemeColors } from '../../../../utils/ThemeColors';

// 退出登录确认弹窗
@Component
export struct LogoutDialog {
  @Prop visible: boolean = false;
  @Prop dialogOpacity: number = 1;
  @Prop dialogTranslate: number = 0;
  onClose: () => void = () => {};
  onConfirm: () => void = () => {};

  build() {
    Column() {
      Column() {
        Text('⚠️').fontSize(40).margin({ bottom: 8 })
        Text('确认退出登录？').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).margin({ bottom: 4 })
        Text('退出后需重新输入账号密码登录').fontSize(13)
          .fontColor(ThemeColors.textSecondary).margin({ bottom: 20 })
        Row() {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary)
            .borderRadius(10)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
          Button('确认退出').layoutWeight(1).height(40).margin({ left: 12 })
            .backgroundColor('#C62828').fontColor('#FFFFFF').borderRadius(10)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onConfirm(); })
        }.width('100%')
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
    .zIndex(100)
    .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
  }
}
