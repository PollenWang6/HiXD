import { ThemeColors } from '../../../../utils/ThemeColors';
import { VersionInfo } from '../../../../services/common/VersionService';

// 版本更新提示弹窗
@Component
export struct UpdateDialog {
  @Prop visible: boolean = false;
  @Prop info: VersionInfo | null = null;
  @Prop accentColor: string = '#2979FF';
  @Prop accentTextColor: string = '#FFFFFF';
  onClose: () => void = () => {};
  onLater: (skipVersion: string) => void = (skipVersion: string) => {};
  onUpdate: (skipVersion: string) => void = (skipVersion: string) => {};
  @State skipVersion: string = '';

  build() {
    if (this.visible && this.info) {
      Column() {
        Column() {
          Text('🎉 发现新版本').fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary).margin({ bottom: 8 })
          Text('最新版本：v' + this.info.version).fontSize(14).fontColor(ThemeColors.textSecondary).margin({ bottom: 4 })
          if (this.info.changelog && this.info.changelog.length > 0) {
            Column() {
              Text('更新内容').fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                .width('100%').margin({ bottom: 6 })
              ForEach(this.info.changelog, (line: string) => {
                Text('• ' + line).fontSize(12).fontColor(ThemeColors.textSecondary).lineHeight(20)
                  .width('100%')
              }, (line: string, __: number) => line)
            }
            .width('100%').alignItems(HorizontalAlign.Start)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(ThemeColors.bgInput).borderRadius(8)
            .margin({ bottom: 16 })
          }
          Row({ space: 10 }) {
            Button('稍后再说').layoutWeight(1).height(40)
              .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary)
              .borderRadius(10)
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.onLater(this.skipVersion); })
            Button('前往应用市场').layoutWeight(1).height(40)
              .backgroundColor(this.accentColor).fontColor(this.accentTextColor)
              .borderRadius(10)
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.onUpdate(this.skipVersion); })
          }.width('100%')
          Row() {
            Checkbox({ name: 'skip_' + (this.info?.version ?? ''), group: 'update_skip' })
              .selectedColor(this.accentColor)
              .width(16).height(16)
              .onChange((value: boolean) => { this.skipVersion = value ? (this.info?.version ?? '') : ''; })
            Text('此版本不再提示').fontSize(12).fontColor(ThemeColors.textHint).margin({ left: 6 })
          }.margin({ top: 12 })
        }
        .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
        .shadow({ radius: 20, color: '#30000000' })
        .hoverEffect(HoverEffect.Auto).onClick(() => {})
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor(ThemeColors.overlay)
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
    }
  }
}
