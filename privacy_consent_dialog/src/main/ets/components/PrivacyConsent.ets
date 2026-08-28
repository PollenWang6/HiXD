import { common } from '@kit.AbilityKit';

import { PrivacyConsentVM } from '../viewmodels/PrivacyConsentVM';
import { PrivacyText, TextType, WidthBreakpoint, DialogType, RouteName } from '../common/CustomTypes';
import { WindowListener } from '../common/WindowListener';

@ComponentV2
export struct PrivacyConsent {

  @Param @Require
  public model: PrivacyConsentVM;

  @Local
  private breakpoint: WidthBreakpoint = WidthBreakpoint.XS;

  @Computed
  private get dialogWidth(): string {
    if (this.model.dialogType === DialogType.NORMAL) {
      if (this.breakpoint === WidthBreakpoint.XS || this.breakpoint === WidthBreakpoint.SM) {
        return 'calc(100% - 32vp)';
      } else {
        return '400vp';
      }
    } else {
      return '100%';
    }
  }

  @Computed
  private get dialogPadding(): Padding {
    if (this.model.dialogType === DialogType.SHEET && this.model.sheetType === SheetType.BOTTOM) {
      return { bottom: `${this.listener.avoidArea.bottom}px` };
    } else {
      return {};
    }
  }

  private abilityContext: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  private listener: WindowListener = new WindowListener(this.abilityContext);

  public aboutToAppear(): void {
    this.listener.start();
  }

  public aboutToDisappear(): void {
    this.listener.stop();
  }

  public build(): void {
    Navigation(this.model.navPathStack) {
      Column() {
        Column() {
          GridRow({
            columns: 12,
            breakpoints: { value: [ '320vp', '600vp', '840vp' ] }
          }) {
            if (this.model.dialogType === DialogType.FULL_SCREEN) {
              GridCol({
                span: { xs: 12, sm: 12, md: 10, lg: 8 },
                offset: { xs: 0, sm: 0, md: 1, lg: 2 }
              }) {
                this.buildContent()
              }
            } else {
              GridCol({ span: 12 }) {
                if (this.model.dialogType === DialogType.NORMAL) {
                  this.buildSimpleContent()
                } else {
                  this.buildContent()
                }
              }
            }
          }
          .onBreakpointChange((breakpoints: string) => {
            if (breakpoints === WidthBreakpoint.XS) {
              this.breakpoint = WidthBreakpoint.XS;
            } else if (breakpoints === WidthBreakpoint.SM) {
              this.breakpoint = WidthBreakpoint.SM;
            } else if (breakpoints === WidthBreakpoint.MD) {
              this.breakpoint = WidthBreakpoint.MD;
            } else {
              this.breakpoint = WidthBreakpoint.LG;
            }
          })
        }
        .width(this.dialogWidth)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .borderRadius(this.model.dialogType === DialogType.NORMAL ? 32 : 0)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding(this.dialogPadding)
    }
    /*
     * 模态页面类型需要在最外层主动指定 '100%'
     */
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .hideBackButton(true)
    .mode(NavigationMode.Stack)
  }

  @Builder
  private buildSimpleContent(): void {
    Column() {
      Text(this.model.title)
        .width('100%')
        .height(56)
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .fontColor($r('sys.color.font_primary'))
        .fontSize($r('sys.float.Title_S'))
        .fontWeight(FontWeight.Bold)
        .padding({ left: 24, right: 24 })
      Scroll() {
        Column() {
          this.buildDocument()
        }
      }
      .constraintSize({ maxHeight: 'calc(80% - 56vp - 56vp)' })
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
      .scrollBar(BarState.Off)
      this.buildButtons()
    }
  }

  @Builder
  private buildContent(): void {
    Column() {
      Scroll() {
        Column() {
          Column() {
            Image(this.model.appIcon)
              .width(72)
              .height(72)
              .borderRadius(16)
              .margin({ top: 36, bottom: 24 })
              .objectFit(ImageFit.Cover)
              .draggable(false)
            Text(this.model.appName)
              .width('100%')
              .textAlign(TextAlign.Center)
              .fontColor($r('sys.color.font_primary'))
              .fontSize($r('sys.float.Title_L'))
              .fontWeight(FontWeight.Medium)
              .margin({ bottom: 8 })
            Text(this.model.appDescription)
              .width('100%')
              .textAlign(TextAlign.Center)
              .fontColor($r('sys.color.font_secondary'))
              .fontSize($r('sys.float.Body_M'))
              .fontWeight(FontWeight.Regular)
              .margin({ bottom: 24 })
          }
          .justifyContent(FlexAlign.Center)
          .constraintSize({ minHeight: '60%' })
          Column() {
            Image($r('app.media.ic_security_shield'))
              .height(24)
              .objectFit(ImageFit.Contain)
              .draggable(false)
              .margin({ bottom: 16 })
            this.buildDocument()
          }
        }
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: this.model.dialogType === DialogType.SHEET })
      .scrollBar(BarState.Off)
      this.buildButtons()
    }
  }

  @Builder
  private buildDocument(): void {
    Text() {
      ForEach(this.model.document, (text: PrivacyText) => {
        Span(text.text)
          .fontSize(text.fontSize ? text.fontSize : $r('sys.float.Caption_M'))
          .fontColor(text.color ? text.color :
            (text.type === TextType.PLAIN ? $r('sys.color.font_secondary') : $r('sys.color.multi_color_01'))
          )
          .fontWeight(text.fontWeight ? text.fontWeight : FontWeight.Regular)
          .onClick(() => {
            if (text.type === TextType.LINK) {
              if (this.model.dialogType === DialogType.SHEET) {
                this.model.navPathStack.pushPathByName(RouteName.PRIVACY_CONSENT_H5_SHEET, text.href);
              } else {
                this.model.navPathStack.pushPathByName(RouteName.PRIVACY_CONSENT_H5, text.href);
              }
            } else if (text.type === TextType.ACTION) {
              text.onAction && text.onAction();
            }
          })
      }, (text: PrivacyText, index: number) => index + '_' + JSON.stringify(text))
    }
    .width('100%')
    .textAlign(TextAlign.Start)
    .margin(this.model.dialogType === DialogType.NORMAL ? { bottom: 8 } : {})
    .padding(this.model.dialogType === DialogType.NORMAL ? { left: 24, right: 24 } : { left: 16, right: 16 })
  }

  @Builder
  private buildButtons(): void {
    Row({ space: 12 }) {
      Button('退出应用')
        .type(ButtonType.ROUNDED_RECTANGLE)
        .fontColor($r('sys.color.font_emphasize'))
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .layoutWeight(1)
        .onClick(() => this.model.onReject())
      Button('同意并继续')
        .type(ButtonType.ROUNDED_RECTANGLE)
        .layoutWeight(1)
        .onClick(() => this.model.onAccept())
    }
    .padding(16)
  }
}
