// AboutPage.ets — 关于软件
import { ThemeColors } from '../../utils/ThemeColors';
import { VersionService } from '../../services/VersionService';
import { VersionInfo } from '../../services/VersionService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

@Component
export struct AboutPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
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
        const skipped = PreferenceUtil.getString('skip_version');
        if (skipped !== info.version) {
          this.showUpdateDialog = true;
        } else {
          promptAction.showToast({ message: '当前已是最新版本' });
        }
      } else {
        promptAction.showToast({ message: '当前已是最新版本' });
      }
    } catch (_) {
      promptAction.showToast({ message: '检查失败，请检查网络' });
    }
    this.checkingUpdate = false;
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

          // 用户协议
          Column() {
            Text('用户协议').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .padding({ left: 16, top: 14, bottom: 10 })
            Divider().color('#E0E0E0').strokeWidth(0.5).margin({ left: 16, right: 16 })
            Text('一、服务说明\n1.1 HiXD（以下简称"本软件"）是西安电子科技大学校园助手应用，由独立开发者（以下简称"我们"）开发并提供。本软件非学校官方应用，不代表校方立场。\n\n1.2 本软件通过您主动提供的学号和密码，经由学校统一身份认证系统（CAS）获取您的教务数据，为您提供课表查询、成绩查询、考试安排、空闲教室、水电缴费、空间预约等校园服务。\n\n二、账号与安全\n2.1 您需要使用学号和密码登录西安电子科技大学 CAS 系统。您的密码采用加密传输，仅存储在您的设备本地，不会上传至我们或任何第三方服务器。\n\n2.2 您应妥善保管账号密码，不得泄露给他人。因您自身原因（设备丢失、账号泄露等）导致的损失，由您自行承担。\n\n三、用户义务\n3.1 您承诺提供的学号和密码信息真实有效，不利用本软件进行任何违法违规活动，不通过任何方式干扰学校教务系统的正常运行。\n\n3.2 您不得滥用本软件功能（如频繁刷新接口、恶意提交数据），避免对学校服务器造成压力。\n\n四、免责声明\n4.1 本软件以"现状"和"可用"方式提供。因学校系统升级、接口变更或网络波动导致的功能异常，我们将尽力修复但不承担任何责任。\n\n4.2 因以下情况导致您遭受损失的，我们不承担责任：(1)您违反本协议约定或相关法律法规使用本软件；(2)设备故障、网络问题等非因我们原因导致的问题；(3)不可抗力等超出我们控制范围的因素。\n\n4.3 本软件为非官方第三方应用，开发者不承担超出合理范围的赔偿责任。\n\n五、协议变更\n5.1 我们有权根据法律法规或运营需要修改本协议，修改后通过应用更新说明等方式公示。继续使用即视为接受修改后的协议。若不同意修改后的协议，应立即停止使用本软件。\n\n六、法律适用与争议解决\n6.1 本协议的成立、生效、履行、解释及纠纷解决，均适用中华人民共和国法律。\n\n6.2 若因本协议产生纠纷，应首先友好协商解决；协商不成的，任何一方有权向开发者所在地有管辖权的人民法院提起诉讼。\n\n七、联系方式\n如有问题或建议，请联系：\npollenwang666@petalmail.com')
              .fontSize(13).fontColor(ThemeColors.textSecondary).lineHeight(22)
              .padding({ left: 16, right: 16, top: 8, bottom: 14 })
          }.borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          .margin({ left: 16, right: 16, top: 8 })

          // 隐私政策
          Column() {
            Text('隐私政策').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .padding({ left: 16, top: 14, bottom: 10 })
            Divider().color('#E0E0E0').strokeWidth(0.5).margin({ left: 16, right: 16 })
            Text('本隐私政策旨在向您说明本软件在用户信息处理方面的原则、方式及范围。本软件的核心特点是：不传输您的任何个人信息或使用数据至我们的服务器或任何第三方服务器，请您放心使用。\n\n一、信息收集与使用\n1.1 本软件在运行过程中，我们不收集任何使用情况数据或分析数据，不含任何追踪器或第三方分析 SDK。\n\n1.2 为实现以下功能，本软件将在本地收集和处理相关信息：\n• 当您使用"登录"功能时，本软件会收集您输入的学号与密码，将其加密后仅存储在您的本地设备中，不会上传至任何服务器。\n• 当您使用"自动获取课表和考试信息"功能时，本软件会获取您的课表与考试相关信息，仅保存在您的本地设备中。\n• 当您使用"个人信息展示"功能时，本软件从学校学工系统获取您的姓名、学号、专业、学院、年级、性别等信息，仅存储在本地用于界面展示。\n• 当您使用"自定义课表背景"功能时，本软件将读取并保存您通过系统图片选择器选择的图片文件，仅保存在您的本地设备中，不会上传至任何服务器。\n\n1.3 所有功能涉及的数据处理（访问、存储、计算）均严格限于您的本地设备内部完成。我们不将任何本地存储的信息传输至外部服务器、网络或第三方。\n\n二、信息存储与安全\n2.1 本软件的所有数据均保存在您的本地设备上。退出登录或卸载应用后，所有本地数据将被清除。\n\n2.2 所有网络通信使用 HTTPS 加密传输。本地数据存储在应用沙盒内，受到系统级安全保护。我们建议您为设备设置锁屏密码以加强本机安全。\n\n三、权限说明\n本软件申请以下权限，均不会收集个人隐私数据：\n• 相机权限：用于宿舍水机扫码绑定设备，仅在使用扫码功能时调用\n• 日历权限（可选）：用于写入课程和考试提醒，仅读取由本软件创建的日程\n• 网络权限：用于访问学校教务系统\n\n四、您的权利\n4.1 因所有数据仅在本地存储，您可直接通过设备管理数据，无需通过我们行使查询、更正、删除等权利。\n\n4.2 您可随时在"我的"页面退出登录，清除所有本地账号信息和缓存数据。\n\n4.3 若对本软件隐私保护有疑问，可通过下方联系方式与我们联系。\n\n五、隐私政策变更\n5.1 若因法律法规变化或功能调整需要变更本隐私政策，将通过应用更新说明等方式提前公示。涉及信息收集方式的变更将在您明确同意后才生效。\n\n六、联系方式\n如有隐私相关问题，请联系：\npollenwang666@petalmail.com')
              .fontSize(13).fontColor(ThemeColors.textSecondary).lineHeight(22)
              .padding({ left: 16, right: 16, top: 8, bottom: 14 })
          }.borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          .margin({ left: 16, right: 16, top: 12 })
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
              Button('立即查看').layoutWeight(1).height(40)
                .backgroundColor(this.accentColor).fontColor('#FFFFFF')
                .borderRadius(10)
                .onClick(() => {
                  this.showUpdateDialog = false;
                  if (this.skipVersion.length > 0) PreferenceUtil.putString('skip_version', this.skipVersion);
                  if (this.updateInfo) {
                    try { this.context.openLink(this.updateInfo.url); } catch (_) {
                      console.warn("AboutPage", "openLink failed");
                    }
                  }
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
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor(ThemeColors.overlay)
        .onClick(() => { this.showUpdateDialog = false; })
      }
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
