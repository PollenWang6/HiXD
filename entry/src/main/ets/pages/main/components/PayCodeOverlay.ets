import { ThemeColors } from '../../../utils/ThemeColors';

// 校园卡付款码弹窗（显隐由外层 if 控制，无需内部 visible 判断）
@Component
export struct PayCodeOverlay {
  @Prop loading: boolean = false;
  @Prop payCodeBase64: string = '';
  @Prop payCodeError: string = '';
  @Prop accentColor: string = '#1976D2';
  onClose: () => void = () => {};
  onRetry: () => void = () => {};

  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('#CC000000')
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
      Column() {
        Row() {
          Text('校园卡付款码').fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Button() {
            Image($r('app.media.close')).width(18).height(18).fillColor(ThemeColors.textSecondary)
          }
          .width(32).height(32).borderRadius(16).backgroundColor('#F0F0F0')
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
        }.width('100%').padding({ left: 16, right: 12, top: 12, bottom: 8 })

        Divider().color('#EEEEEE').strokeWidth(0.5)

        if (this.loading) {
          LoadingProgress().width(28).height(28).color(this.accentColor)
            .margin({ top: 40, bottom: 40 })
        } else if (this.payCodeBase64.length > 0) {
          Image('data:image/png;base64,' + this.payCodeBase64)
            .width(220).height(220).objectFit(ImageFit.Contain)
            .margin({ top: 16, bottom: 8 })
          Text('向收银员出示此码').fontSize(12).fontColor(ThemeColors.textHint)
            .margin({ bottom: 16 })
        } else {
          Column() {
            Text(this.payCodeError || '加载失败').fontSize(13).fontColor(ThemeColors.textHint)
              .width('100%').textAlign(TextAlign.Center)
            Button('重试').fontSize(13).height(32).backgroundColor(this.accentColor)
              .fontColor('#FFFFFF').borderRadius(16).padding({ left: 16, right: 16 })
              .margin({ top: 12 })
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.onRetry(); })
          }.width('100%').padding({ top: 24, bottom: 24 })
        }
      }
      .width(280).padding({ bottom: 12 })
      .backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 8, color: '#00000020', offsetY: 2 })
    }
    .width('100%').height('100%').alignContent(Alignment.Center)
  }
}
