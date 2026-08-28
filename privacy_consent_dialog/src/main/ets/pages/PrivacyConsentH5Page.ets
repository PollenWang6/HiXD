import { webview } from '@kit.ArkWeb';
import { RouteName } from '../common/CustomTypes';

@ComponentV2
export struct PrivacyConsentH5Page {

  @Param @Require
  public isSheetPage: boolean;

  @Param @Require
  public href: string;

  private navPathStack: NavPathStack = new NavPathStack();

  private controller: webview.WebviewController = new webview.WebviewController();

  public build(): void {
    NavDestination() {
      Column() {
        this.buildTitleBar()
        Scroll() {
          Column() {
            Web({ src: this.href, controller: this.controller })
              .domStorageAccess(true)
              .onlineImageAccess(true)
              .blockNetwork(false)
              .geolocationAccess(false)
              .fileAccess(false)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => this.navPathStack = ctx.pathStack)
  }

  @Builder
  private buildTitleBar(): void {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_primary')])
          .fontWeight(FontWeight.Normal)
      }
      .width(40)
      .height(40)
      .type(ButtonType.Circle)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .onClick(() => this.navPathStack.pop())
      .margin({ left: 16 })
    }
    .width('100%')
    .padding(this.isSheetPage ? { top: 16, bottom: 8 } : { top: 8, bottom: 8 })
  }
}

@Builder
export function buildPrivacyConsentH5Page(pageName: string, href: string): void {
  PrivacyConsentH5Page({
    isSheetPage: pageName === RouteName.PRIVACY_CONSENT_H5_SHEET,
    href: String(href) ?? ''
  })
}
