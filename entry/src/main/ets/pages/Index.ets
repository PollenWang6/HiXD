// Index.ets — 启动门禁页：先征求隐私/协议同意，同意后再进入主页
// 合规要点：同意必须在登录/收集个人信息、联网之前（PIPL + 应用市场审核要求）
import { ThemeColors } from '../utils/ThemeColors';
import { AccentColors } from '../utils/AccentColors';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { router } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';

// 隐私政策版本号：文案有重大变更时 +1，自动重新弹窗征得同意
const PRIVACY_POLICY_VERSION: number = 1;

@Entry
@Component
struct Index {
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  @State showPrivacyDialog: boolean = false;
  @State showPolicyViewer: boolean = false;
  @State policyTitle: string = '';
  @State policyContent: string = '';
  private accentColor: string = '#2979FF';

  aboutToAppear(): void {
    // 主题/强调色提前初始化（主页与登录页都依赖）
    const savedMode: number = PreferenceUtil.getNumber('theme_color_mode',
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    ThemeColors.init(savedMode, getContext(this));
    AccentColors.init();
    this.accentColor = (AppStorage.get('accent_color') as string) ?? '#2979FF';
    this.checkPrivacyAgreement();
  }

  // 是否已同意（含老版本裸 bool 标记迁移，避免老用户被重复弹窗）
  private privacyAgreed(): boolean {
    if (PreferenceUtil.getBool('privacy_agreed', false)
      && PreferenceUtil.getNumber('privacy_agreed_version', 0) === 0) {
      PreferenceUtil.putNumber('privacy_agreed_version', PRIVACY_POLICY_VERSION);
      return true;
    }
    return PreferenceUtil.getNumber('privacy_agreed_version', 0) >= PRIVACY_POLICY_VERSION;
  }

  // 首次启动 / 政策更新 → 弹窗；已同意 → 短暂闪屏后进入主页
  private checkPrivacyAgreement(): void {
    if (this.privacyAgreed()) {
      setTimeout(() => { this.routeToMain(); }, 50);
      return;
    }
    this.showPrivacyDialog = true;
  }

  private agreePrivacy(): void {
    PreferenceUtil.putNumber('privacy_agreed_version', PRIVACY_POLICY_VERSION);
    this.showPrivacyDialog = false;
    this.routeToMain();
  }

  private disagreePrivacy(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.terminateSelf();
    } catch (_) { /* 退出应用 */ }
  }

  private routeToMain(): void {
    router.replaceUrl({ url: 'pages/MainPage' });
  }

  private openPrivacyUrl(type: string): void {
    if (type === 'user') {
      this.policyTitle = '用户协议';
      this.policyContent = '一、服务说明\n1.1 HiXD（以下简称"本软件"）是西安电子科技大学校园助手应用，由独立开发者（以下简称"我们"）开发并提供。本软件非学校官方应用，不代表校方立场。\n\n1.2 本软件通过您主动提供的学号和密码，经由学校统一身份认证系统（CAS）获取您的教务数据，为您提供课表查询、成绩查询、考试安排、空闲教室、水电缴费、空间预约等校园服务。\n\n二、账号与安全\n2.1 您需要使用学号和密码登录 CAS 系统。您的密码采用加密传输，仅存储在您的设备本地，不会上传至任何服务器。\n\n2.2 您应妥善保管账号密码，不得泄露给他人。因自身原因导致的损失由您自行承担。\n\n三、用户义务\n3.1 您承诺不利用本软件进行任何违法违规活动，不干扰学校教务系统的正常运行。\n\n3.2 不得滥用本软件功能（如频繁刷新接口），避免对学校服务器造成压力。\n\n四、免责声明\n4.1 本软件以"现状"方式提供。因学校系统升级或接口变更导致的功能异常，我们将尽力修复但不承担责任。\n\n4.2 因设备故障、网络问题等非我们原因导致的损失，我们不承担责任。\n\n五、协议变更\n5.1 我们有权修改本协议，修改后通过应用更新说明等方式公示。继续使用即视为接受修改后的协议。\n\n六、法律适用\n适用中华人民共和国法律。因本协议产生纠纷协商不成的，由开发者所在地法院管辖。\n\n七、联系方式\npollenwang666@petalmail.com';
    } else {
      this.policyTitle = '隐私政策';
      this.policyContent = '本隐私政策说明本软件在用户信息处理方面的原则。核心特点是：不传输您的任何个人信息至任何服务器。\n\n一、信息收集与使用\n1.1 本软件不含任何追踪器或第三方分析 SDK，不收集使用数据。\n\n1.2 为实现功能，本软件在本地收集和处理以下信息：\n• 登录：收集学号和密码，加密后仅存储在本地设备\n• 课表和考试：获取课表及考试信息，仅保存在本地\n• 个人信息：从学校学工系统获取姓名、学号、专业等，仅存储在本地用于展示\n• 自定义背景：读取您选择的图片文件，仅保存在本地\n\n1.3 所有数据处理均限于本地设备完成，不上传至任何外部服务器。\n\n二、信息存储与安全\n2.1 所有数据仅存储在本地。退出登录或卸载应用后可清除。\n\n2.2 网络通信使用 HTTPS 加密。本地数据受系统沙盒保护。建议为设备设置锁屏密码。\n\n三、权限说明\n• 相机权限：宿舍水机扫码绑定设备\n• 日历权限（可选）：课程和考试提醒，仅读取本软件创建的日程\n• 网络权限：访问学校教务系统\n以上权限均不会收集个人隐私数据。\n\n四、您的权利\n数据仅在本地存储，您可直接通过设备管理数据。可随时退出登录清除所有本地信息。\n\n五、隐私政策变更\n将通过应用更新说明等方式提前公示。\n\n六、联系方式\npollenwang666@petalmail.com';
    }
    this.showPolicyViewer = true;
  }

  build() {
    Stack() {
      // 启动页背景（始终渲染，作为弹窗的底）
      Column() {
        LoadingProgress().width(48).height(48).color(this.accentColor)
        Text('HiXD').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.accentColor).margin({ top: 16 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ThemeColors.bgCard)

      // 隐私协议弹窗（首次启动 / 政策更新）
      if (this.showPrivacyDialog) {
        Column() {
          Column() {
            // 应用图标
            Image($r('app.media.hixd_icon')).width(56).height(56).borderRadius(14)
              .margin({ top: 24 })
            Text('HiXD').fontSize(22).fontWeight(FontWeight.Bold)
              .fontColor(ThemeColors.textPrimary).margin({ top: 8, bottom: 16 })
            Scroll() {
              Text() {
                Span('欢迎使用 HiXD！在使用本应用前，请您仔细阅读并同意')
                  .fontSize(14).fontColor(ThemeColors.textSecondary)
                Span('《用户协议》').fontSize(14)
                  .fontColor(this.accentColor)
                  .onClick(() => { this.openPrivacyUrl('user'); })
                Span('和').fontSize(14).fontColor(ThemeColors.textSecondary)
                Span('《隐私政策》').fontSize(14)
                  .fontColor(this.accentColor)
                  .onClick(() => { this.openPrivacyUrl('privacy'); })
                Span('。').fontSize(14).fontColor(ThemeColors.textSecondary)
                Span('\n\n本应用需要您使用学号和密码登录西安电子科技大学统一身份认证系统，以获取课表、成绩等教务数据。您的账号密码仅用于校内认证，不会上传至任何第三方服务器。')
                  .fontSize(14).fontColor(ThemeColors.textSecondary)
              }.lineHeight(22)
            }.height(160).padding({ left: 4, right: 4 })

            Column({ space: 12 }) {
              Button('不同意').width('80%').height(44).fontSize(15)
                .backgroundColor(Color.Transparent).fontColor(ThemeColors.textSecondary)
                .onClick(() => { this.disagreePrivacy(); })
              Button('同意并继续').width('80%').height(44).fontSize(17)
                .backgroundColor(this.accentColor).fontColor(Color.White)
                .borderRadius(24)
                .onClick(() => { this.agreePrivacy(); })
            }.margin({ top: 16, bottom: 20 })
          }
          .width('85%').padding(20).borderRadius(13).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 16, color: '#00000020' })
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('#4D000000')
        .zIndex(100)
      }

      // 隐私政策/用户协议全文查看
      if (this.showPolicyViewer) {
        Column() {
          Column() {
            Row() {
              Text(this.policyTitle).fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              Blank()
              Text('✕').fontSize(18).fontColor('#999999')
                .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
                .textAlign(TextAlign.Center)
                .onClick(() => { this.showPolicyViewer = false; })
            }.width('100%').margin({ bottom: 16 })
            Scroll() {
              Text(this.policyContent).fontSize(14).fontColor(ThemeColors.textSecondary).lineHeight(24)
            }.layoutWeight(1)
          }
          .width('90%').height('80%').padding(20).borderRadius(13).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 16, color: '#00000020' })
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('#4D000000')
        .zIndex(101)
      }
    }
    .width('100%').height('100%')
  }
}
