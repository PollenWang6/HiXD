import { ToastUtil } from '../../utils/ToastUtil';
﻿import { AccentColors } from '../../utils/AccentColors';
// AboutPage.ets — 关于软件
import { ThemeColors } from '../../utils/ThemeColors';
import { VersionService } from '../../services/VersionService';
import { VersionInfo } from '../../services/VersionService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { common } from '@kit.AbilityKit';
import { openAppGalleryDetail } from '../../utils/AppGalleryUtil';

@Component
export struct AboutPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  pageInfo: NavPathStack = new NavPathStack();
  @Prop isTablet: boolean = false;
  @State currentVersion: string = '';
  @State hasUpdate: boolean = false;
  @State checkingUpdate: boolean = false;
  @State showUpdateDialog: boolean = false;
  @State updateInfo: VersionInfo | null = null;
  @State skipVersion: string = '';
  private context = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    VersionService.getCurrentVersion().then((v: string) => { this.currentVersion = v; });
    VersionService.checkForUpdate().then((info: VersionInfo | null) => {
      if (info) this.hasUpdate = true;
    }).catch(() => {});
  }

  private async doCheckUpdate(): Promise<void> {
    if (this.checkingUpdate) return;
    this.checkingUpdate = true;
    try {
      const info = await VersionService.checkForUpdate();
      if (info) {
        this.hasUpdate = true;
        this.updateInfo = info;
        this.showUpdateDialog = true;
      } else {
        ToastUtil.show('当前已是最新版本');
      }
    } catch (_) {
      ToastUtil.show('检查失败，请检查网络');
    }
    this.checkingUpdate = false;
  }

  // 跳转在线版隐私政策（单一来源，与 AGC 提交网址一致）
  private openPrivacyPolicy(): void {
    try {
      this.context.openLink('https://pollenwang6.github.io/HiXD/privacy.html').catch(() => {});
    } catch (_e) {
      // 无法拉起浏览器时忽略
    }
  }

  // 跳转在线版用户协议（单一来源）
  private openUserAgreement(): void {
    try {
      this.context.openLink('https://pollenwang6.github.io/HiXD/user-agreement.html').catch(() => {});
    } catch (_e) {
      // 无法拉起浏览器时忽略
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // 应用信息
          Row() {
            Image($r('app.media.hixd_icon')).width(48).height(48).borderRadius(12)
            Column() {
              Text('HiXD').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              Text('v' + (this.currentVersion || '?.?')).fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
            }.margin({ left: 12 }).alignItems(HorizontalAlign.Start)
            Blank()
            Button(this.checkingUpdate ? '检查中...' : (this.hasUpdate ? '新版本可用' : '检查更新'))
              .height(34).fontSize(13)
              .backgroundColor(this.hasUpdate ? '#E65100' : this.accentColor)
              .fontColor('#FFFFFF').borderRadius(17)
              .padding({ left: 14, right: 14 })
              .onClick(() => { this.doCheckUpdate(); })
          }.width('100%').padding({ left: 20, right: 20, top: 20, bottom: 16 })

          // 用户协议（跳转在线版，单一来源）
          Column() {
            Row() {
              Column() {
                Text('用户协议').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                Text('点击查看完整用户协议').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor('#CCCCCC')
            }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
          }.borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          .margin({ left: 16, right: 16, top: 12 })
          .onClick(() => this.openUserAgreement())

          // 隐私政策（跳转在线版，单一来源）
          Column() {
            Row() {
              Column() {
                Text('隐私政策').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                Text('点击查看完整隐私政策').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
              }.layoutWeight(1)
              Text('›').fontSize(20).fontColor('#CCCCCC')
            }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
          }.borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          .margin({ left: 16, right: 16, top: 12 })
          .onClick(() => this.openPrivacyPolicy())
        }
        .padding({ bottom: 30 })
      }
      .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)

      // 版本更新弹窗
      if (this.showUpdateDialog && this.updateInfo) {
        Column() {
          Column() {
            Text('🎉 发现新版本').fontSize(18).fontWeight(FontWeight.Bold)
              .fontColor(ThemeColors.textPrimary).margin({ bottom: 8 })
            Text('最新版本：v' + this.updateInfo.version).fontSize(14)
              .fontColor(ThemeColors.textSecondary).margin({ bottom: 4 })
            if (this.updateInfo.changelog && this.updateInfo.changelog.length > 0) {
              Column() {
                Text('更新内容').fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                  .width('100%').margin({ bottom: 6 })
                ForEach(this.updateInfo.changelog, (line: string) => {
                  Text('• ' + line).fontSize(12).fontColor(ThemeColors.textSecondary).lineHeight(20)
                    .width('100%')
                }, (line: string) => line)
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
                .onClick(() => {
                  this.showUpdateDialog = false;
                  if (this.skipVersion.length > 0) PreferenceUtil.putString('skip_version', this.skipVersion);
                })
              Button('前往应用市场').layoutWeight(1).height(40)
                .backgroundColor(this.accentColor).fontColor('#FFFFFF')
                .borderRadius(10)
                .onClick(() => {
                  this.showUpdateDialog = false;
                  if (this.skipVersion.length > 0) PreferenceUtil.putString('skip_version', this.skipVersion);
                  openAppGalleryDetail(this.context);
                })
            }.width('100%')
            Row() {
              Checkbox({ name: 'skip_' + (this.updateInfo?.version ?? ''), group: 'about_update_skip' })
                .selectedColor(this.accentColor)
                .width(16).height(16)
                .onChange((value: boolean) => { this.skipVersion = value ? (this.updateInfo?.version ?? '') : ''; })
              Text('此版本不再提示').fontSize(12).fontColor(ThemeColors.textHint).margin({ left: 6 })
            }.margin({ top: 12 })
          }
          .width('80%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
          .shadow({ radius: 20, color: '#30000000' })
          .onClick(() => {})
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor(ThemeColors.overlay)
        .onClick(() => { this.showUpdateDialog = false; })
      }
    }
    .width('100%').height('100%')
    .title({ builder: this.customTitle(), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .backgroundColor(ThemeColors.bgPage)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .hideBackButton(true)
  }

  @Builder customTitle() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([AccentColors.textContrast])
      }.height(40).width(40).onClick(() => { this.pageInfo.pop(); })
      Text('关于软件').fontSize(22).fontWeight(FontWeight.Bold).fontColor(AccentColors.textContrast).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.height(52 + this.statusBarHeight).width('100%').padding({ left: 12, right: 12, top: this.statusBarHeight })
  }
}
