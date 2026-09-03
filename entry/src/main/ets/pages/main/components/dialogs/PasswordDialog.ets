import { ThemeColors } from '../../../../utils/ThemeColors';
import { PreferenceUtil } from '../../../../utils/PreferenceUtil';
import { SecureStorageUtil } from '../../../../utils/SecureStorageUtil';

// 通用密码设置弹窗（物理实验/校园网/体育系统 三处复用）
@Component
export struct PasswordDialog {
  @Prop visible: boolean = false;
  @Prop dialogOpacity: number = 1;
  @Prop dialogTranslate: number = 0;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop placeholder: string = '';
  @Prop storageKey: string = '';
  @Prop accentColor: string = '#2979FF';
  @Prop accentTextColor: string = '#FFFFFF';
  onClose: () => void = () => {};
  onSaved: () => void = () => {};
  @State input: string = '';
  @State saveError: string = '';

  aboutToAppear(): void {
    SecureStorageUtil.get(this.storageKey).then((pwd: string) => { this.input = pwd; });
  }

  build() {
    Column() {
      Column() {
        Row() {
          Text(this.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor(ThemeColors.textSecondary) }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
        }.width('100%').margin({ bottom: 16 })
        if (this.subtitle.length > 0) {
          Text(this.subtitle).fontSize(12).fontColor(ThemeColors.textSecondary)
            .width('100%').margin({ bottom: 12 })
        }
        TextInput({ placeholder: this.placeholder, text: this.input })
          .type(InputType.Password)
          .width('100%').height(44).fontSize(15)
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .onChange((v: string) => { this.input = v; this.saveError = ''; })
        if (this.saveError.length > 0) {
          Text(this.saveError).fontSize(12).fontColor('#E53935')
            .width('100%').margin({ top: 8 })
        }
        Row() {
          Button('取消').layoutWeight(1).height(40)
            .backgroundColor(ThemeColors.bgInput)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
          Button('保存').layoutWeight(1).height(40).margin({ left: 12 })
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor)
            .hoverEffect(HoverEffect.Auto).onClick(async () => {
              if (this.input.length > 0) {
                try {
                  await SecureStorageUtil.put(this.storageKey, this.input);
                  const verify = await SecureStorageUtil.get(this.storageKey);
                  if (verify.length === 0) {
                    this.saveError = '密码保存失败，请重试';
                    return;
                  }
                } catch (e) {
                  this.saveError = '密码保存失败: ' + String(e);
                  return;
                }
                this.saveError = '';
                this.onSaved();
              }
            })
        }.width('100%').margin({ top: 16 })
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
