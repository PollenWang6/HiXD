// RuisiCaptchaDialog.ets — 验证码弹窗组件

import { ThemeColors } from '../../utils/ThemeColors';
import { RuisiService } from '../../services/RuisiService';
import { image } from '@kit.ImageKit';

@Component
export struct RuisiCaptchaDialog {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @Prop seccodehash: string;
  @Prop visible: boolean;
  @Link captchaText: string;
  onVerify?: (code: string) => void = undefined;
  onClose?: () => void = undefined;
  @State captchaImage: PixelMap | null = null;
  @State loading: boolean = false;

  async aboutToAppear(): Promise<void> {
    if (this.seccodehash.length > 0) await this.refreshCaptcha();
  }

  async refreshCaptcha(): Promise<void> {
    if (!this.seccodehash) return;
    this.loading = true;
    this.captchaText = '';
    try {
      const data = await RuisiService.getInstance().getRaw(
        `https://rs.xidian.edu.cn/misc.php?mod=seccode&action=update&idhash=${encodeURIComponent(this.seccodehash)}&inajax=1&${Date.now()}`,
        { 'Referer': 'https://rs.xidian.edu.cn/' }
      );
      if (data) {
        const imgSrc = image.createImageSource(data);
        this.captchaImage = await imgSrc.createPixelMap();
      }
    } finally { this.loading = false; }
  }

  build() {
    if (this.visible) {
      Stack() {
        Column() {
          Text('请输入验证码').fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            .margin({ bottom: 16 })

          if (this.loading) {
            LoadingProgress().width(36).height(36).color(this.accentColor).margin({ top: 20, bottom: 20 })
          } else if (this.captchaImage) {
            Image(this.captchaImage).width(120).height(48).borderRadius(6).margin({ bottom: 12 })
              .onClick(() => { this.refreshCaptcha(); })
          }

          TextInput({ text: this.captchaText, placeholder: '验证码' })
            .fontSize(16).fontColor(ThemeColors.textPrimary).backgroundColor(ThemeColors.bgInput)
            .borderRadius(8).height(44).width('80%')
            .onChange((v: string) => { this.captchaText = v; })

          Row() {
            Button('取消').fontSize(14).height(36).margin({ right: 12 })
              .onClick(() => { if (this.onClose) this.onClose(); })
            Button('确定').fontSize(14).height(36)
              .backgroundColor(this.accentColor).fontColor('#FFFFFF')
              .onClick(() => { if (this.onVerify) this.onVerify(this.captchaText); })
          }.margin({ top: 16 })
        }.padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16).alignItems(HorizontalAlign.Center)
      }.width('100%').height('100%').backgroundColor('#80000000').alignContent(Alignment.Center)
    }
  }
}
