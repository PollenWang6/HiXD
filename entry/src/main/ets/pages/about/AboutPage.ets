import { ToastUtil } from '../../utils/ToastUtil';
import { AccentColors } from '../../utils/AccentColors';
// AboutPage.ets — 关于软件
import { ThemeColors } from '../../utils/ThemeColors';
import { VersionService } from '../../services/VersionService';
import { VersionInfo } from '../../services/VersionService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { common, Want } from '@kit.AbilityKit';
import { openAppGalleryDetail } from '../../utils/AppGalleryUtil';

class FeatureItem {
  title: string = '';
  desc: string = '';
  constructor(title: string, desc: string) {
    this.title = title;
    this.desc = desc;
  }
}

@Component
export struct AboutPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();
  @Prop isTablet: boolean = false;
  @State currentVersion: string = '';
  @State hasUpdate: boolean = false;
  @State checkingUpdate: boolean = false;
  @State showUpdateDialog: boolean = false;
  @State updateInfo: VersionInfo | null = null;
  @State skipVersion: string = '';
  private context = getContext(this) as common.UIAbilityContext;

  // 功能一览（静态展示，不跳转）
  private readonly features: Array<FeatureItem> = [
    new FeatureItem('课表查询', '每日课程、教室与周次一目了然'),
    new FeatureItem('空教室', '一键查找空闲自习室'),
    new FeatureItem('图书馆', '馆藏检索、借阅与续借'),
    new FeatureItem('成绩 GPA', '学期成绩与绩点统计'),
    new FeatureItem('考勤预警', '到课率与缺勤风险提醒'),
    new FeatureItem('校园卡', '余额与消费明细查询'),
    new FeatureItem('睿思论坛', '校园社区与学习资源'),
    new FeatureItem('自习座位', '超星选座一键预约')
  ];

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

  // 通用外链跳转
  private openUrl(url: string): void {
    try {
      this.context.openLink(url).catch(() => {});
    } catch (_e) {
      // 无法拉起浏览器时忽略
    }
  }

  private openPrivacyPolicy(): void {
    this.openUrl('https://hixdapp.cn/privacy.html');
  }

  private openUserAgreement(): void {
    this.openUrl('https://hixdapp.cn/user-agreement.html');
  }

  private openGitHub(): void {
    this.openUrl('https://github.com/PollenWang6/HiXD');
  }

  private openFeedback(): void {
    const recipient: string = 'pollenwang666@petalmail.com';
    const subject: string = 'HiXD 问题反馈';
    const body: string = '请描述您遇到的问题或建议：\n（如方便请附上机型 / 系统版本 / App 版本）';
    const uri: string = 'mailto:' + recipient +
      '?subject=' + encodeURIComponent(subject) +
      '&body=' + encodeURIComponent(body);
    const want: Want = {
      action: 'ohos.want.action.sendToData',
      uri: uri
    };
    try {
      this.context.startAbility(want).then(() => {
        // 已拉起邮件应用
      }).catch(() => {
        ToastUtil.show('未找到邮件应用，请联系：' + recipient);
      });
    } catch (_e) {
      ToastUtil.show('未找到邮件应用，请联系：' + recipient);
    }
  }

  private openBeian(): void {
    this.openUrl('https://hixdapp.cn');
  }

  @Builder
  rowItem(title: string, sub: string, onClick: () => void) {
    Row() {
      Column() {
        Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        Text(sub).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
    }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => onClick())
  }

  build() {
    NavDestination() {
      Stack() {
      Scroll() {
        Column() {
          // ===== 品牌 Hero 区（accent 实色背景，左对齐）=====
          Row() {
            Image($r('app.media.icon')).width(64).height(64).borderRadius(16)
              .backgroundColor('#FFFFFF')
            Column() {
              Row() {
                Text('HiXD').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                Text('非官方')
                  .fontSize(9).fontColor('#FFFFFF')
                  .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                  .backgroundColor('rgba(0,0,0,0.30)')
                  .borderRadius(6)
                  .margin({ left: 6, top: 2 })
              }.alignItems(VerticalAlign.Top)
              Text('第三方校园信息查询工具').fontSize(12).fontColor('#FFFFFF')
                .opacity(0.8).margin({ top: 4 })
              Row() {
                Text('v' + (this.currentVersion || '?.?.?')).fontSize(11).fontColor('#FFFFFF')
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor('#FFFFFF').opacity(0.22).borderRadius(10)
              }.margin({ top: 8 })
            }.margin({ left: 14 }).alignItems(HorizontalAlign.Start).layoutWeight(1)

            Button(this.checkingUpdate ? '检查中' : (this.hasUpdate ? '有更新' : '检查更新'))
              .height(36).fontSize(13).fontColor(this.accentColor)
              .backgroundColor('#FFFFFF').borderRadius(18)
              .padding({ left: 16, right: 16 })
              .onClick(() => { this.doCheckUpdate(); })
          }
          .width('100%').padding({ left: 20, right: 20, top: 20, bottom: 20 })
          .backgroundColor(this.accentColor)

          // ===== 功能一览 =====
          Text('功能一览').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.accentColor)
            .margin({ left: 16, top: 20, bottom: 10 })
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Stretch }) {
            ForEach(this.features, (f: FeatureItem) => {
              Column() {
                Text(f.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                Text(f.desc).fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width(this.isTablet ? '23.5%' : '48%')
              .padding(14).backgroundColor(ThemeColors.bgCard)
              .borderRadius(12).shadow({ radius: 2, color: '#00000008', offsetY: 1 })
              .alignItems(HorizontalAlign.Start)
              .margin({ bottom: 10 })
            }, (f: FeatureItem) => f.title)
            // 收尾卡片：暗示还有更多功能未一一列出
            Column() {
              Text('更多功能').fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.accentColor)
              Text('持续上新，敬请期待…').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
            }
            .width(this.isTablet ? '23.5%' : '48%')
            .padding(14).backgroundColor(ThemeColors.bgCard)
            .borderRadius(12)
            .border({ width: 1, color: this.accentColor, style: BorderStyle.Dashed })
            .alignItems(HorizontalAlign.Start)
            .margin({ bottom: 10 })
          }.width('100%').padding({ left: 16, right: 16 })

          // ===== 关于与设置 =====
          Text('关于与设置').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.accentColor)
            .margin({ left: 16, top: 20, bottom: 10 })

          Column() {
            this.rowItem('开源仓库', 'GitHub 开源仓库', () => { this.openGitHub(); })
            Divider().strokeWidth(1).color(ThemeColors.border).margin({ left: 16, right: 16 })
            this.rowItem('问题反馈', '邮件联系开发者', () => { this.openFeedback(); })
            Divider().strokeWidth(1).color(ThemeColors.border).margin({ left: 16, right: 16 })
            this.rowItem('用户协议', '点击查看完整用户协议', () => { this.openUserAgreement(); })
            Divider().strokeWidth(1).color(ThemeColors.border).margin({ left: 16, right: 16 })
            this.rowItem('隐私政策', '点击查看完整隐私政策', () => { this.openPrivacyPolicy(); })
          }.borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          .margin({ left: 16, right: 16, top: 4 })

          // ===== 底部信息 =====
          Column() {
            Text('© 2026 HiXD. 保留所有权利.').fontSize(12).fontColor(ThemeColors.textHint)
            Text('桂ICP备2026015291号').fontSize(12).fontColor(this.accentColor)
              .margin({ top: 6 }).onClick(() => { this.openBeian(); })
            Text('hixdapp.cn').fontSize(12).fontColor(ThemeColors.textHint).margin({ top: 2 })
            Text('本应用为独立开发者提供的第三方校园工具，与西安电子科技大学无任何隶属、合作或授权关系，并非学校官方出品或授权应用。')
              .fontSize(11).fontColor(ThemeColors.textHint).margin({ top: 8 })
          }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, top: 20, bottom: 30 })
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 20 })
      }
      .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
      .align(Alignment.TopStart)

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
