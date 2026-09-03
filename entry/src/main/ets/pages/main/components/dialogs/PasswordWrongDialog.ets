import { ThemeColors } from '../../../../utils/ThemeColors';

// 密码错误弹窗（对齐 traintime_pda：密码错误时清除本地密码，提示用户重新登录）
@Component
export struct PasswordWrongDialog {
  @Prop visible: boolean = false;
  @Prop dialogOpacity: number = 1;
  @Prop dialogTranslate: number = 0;
  @Prop errorMsg: string = '';
  onClose: () => void = () => {};
  onRelogin: () => void = () => {};

  build() {
    Column() {
      Column() {
        Text('🔐').fontSize(40).margin({ bottom: 8 })
        Text('密码错误').fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary).margin({ bottom: 4 })
        Text(this.errorMsg.length > 0 ? this.errorMsg : '检测到统一身份认证密码错误，可能是您修改了密码。本地已保存的密码已清除，请重新登录。')
          .fontSize(13).fontColor(ThemeColors.textSecondary).margin({ bottom: 20 })
        Row() {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary)
            .borderRadius(10)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
          Button('重新登录').layoutWeight(1).height(40).margin({ left: 12 })
            .backgroundColor('#1976D2').fontColor('#FFFFFF').borderRadius(10)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onRelogin(); })
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
