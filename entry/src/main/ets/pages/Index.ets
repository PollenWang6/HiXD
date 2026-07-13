// Index.ets — 启动门禁页：先征求隐私/协议同意，同意后再进入主页
// 合规要点：同意必须在登录/收集个人信息、联网之前（PIPL + 应用市场审核要求）
// UI：使用华为官方「通用隐私同意弹窗组件」(privacy_consent_dialog HAR) 的模态底部样式（SHEET / bottom sheet）
//      —— 从屏幕底部升起的半屏卡片：应用图标 + 应用名 + 描述 + 盾牌 + 可滚动协议 + 底部「退出应用 / 同意并继续」
//      该 HAR 已从官方生态市场下载至工程根目录，并去掉唯一外部依赖 @hw-agconnect/util-log（仅日志用）。
import {
  router,
  ComponentContent,
  PromptAction,
  LevelMode,
  ImmersiveMode
} from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { PrivacyConsentController, PrivacyDocument, TextType } from 'privacy_consent_dialog';
import { ThemeColors } from '../utils/ThemeColors';
import { AccentColors } from '../utils/AccentColors';
import { PreferenceUtil } from '../utils/PreferenceUtil';

// 隐私政策版本号：文案有重大变更时 +1，自动重新弹窗征得同意
const PRIVACY_POLICY_VERSION: number = 1;

// ---- 本地协议正文（复用原手写版文案，仍本地维护） ----
const USER_AGREEMENT_TEXT: string =
  '一、服务说明\n' +
  '1.1 HiXD（以下简称"本软件"）是西安电子科技大学校园助手应用，由独立开发者（以下简称"我们"）开发并提供。本软件非学校官方应用，不代表校方立场。\n\n' +
  '1.2 本软件通过您主动提供的学号和密码，经由学校统一身份认证系统（CAS）获取您的教务数据，为您提供课表查询、成绩查询、考试安排、空闲教室、水电缴费、空间预约等校园服务。\n\n' +
  '二、账号与安全\n' +
  '2.1 您需要使用学号和密码登录 CAS 系统。您的密码采用加密传输，仅存储在您的设备本地，不会上传至任何服务器。\n\n' +
  '2.2 您应妥善保管账号密码，不得泄露给他人。因自身原因导致的损失由您自行承担。\n\n' +
  '三、用户义务\n' +
  '3.1 您承诺不利用本软件进行任何违法违规活动，不干扰学校教务系统的正常运行。\n\n' +
  '3.2 不得滥用本软件功能（如频繁刷新接口），避免对学校服务器造成压力。\n\n' +
  '四、免责声明\n' +
  '4.1 本软件以"现状"方式提供。因学校系统升级或接口变更导致的功能异常，我们将尽力修复但不承担责任。\n\n' +
  '4.2 因设备故障、网络问题等非我们原因导致的损失，我们不承担责任。\n\n' +
  '五、协议变更\n' +
  '5.1 我们有权修改本协议，修改后通过应用更新说明等方式公示。继续使用即视为接受修改后的协议。\n\n' +
  '六、法律适用\n' +
  '适用中华人民共和国法律。因本协议产生纠纷协商不成的，由开发者所在地法院管辖。\n\n' +
  '七、联系方式\n' +
  'pollenwang666@petalmail.com';

const PRIVACY_POLICY_TEXT: string =
  '本隐私政策说明本软件在用户信息处理方面的原则。核心特点是：不传输您的任何个人信息至任何服务器。\n\n' +
  '一、信息收集与使用\n' +
  '1.1 本软件不含任何追踪器或第三方分析 SDK，不收集使用数据。\n\n' +
  '1.2 为实现功能，本软件在本地收集和处理以下信息：\n' +
  '• 登录：收集学号和密码，加密后仅存储在本地设备\n' +
  '• 课表和考试：获取课表及考试信息，仅保存在本地\n' +
  '• 个人信息：从学校学工系统获取姓名、学号、专业等，仅存储在本地用于展示\n' +
  '• 自定义背景：读取您选择的图片文件，仅保存在本地\n\n' +
  '1.3 所有数据处理均限于本地设备完成，不上传至任何外部服务器。\n\n' +
  '二、信息存储与安全\n' +
  '2.1 所有数据仅存储在本地。退出登录或卸载应用后可清除。\n\n' +
  '2.2 网络通信使用 HTTPS 加密。本地数据受系统沙盒保护。建议为设备设置锁屏密码。\n\n' +
  '三、权限说明\n' +
  '• 相机权限：宿舍水机扫码绑定设备\n' +
  '• 日历权限（可选）：课程和考试提醒，仅读取本软件创建的日程\n' +
  '• 网络权限：访问学校教务系统\n' +
  '以上权限均不会收集个人隐私数据。\n\n' +
  '四、您的权利\n' +
  '数据仅在本地存储，您可直接通过设备管理数据。可随时退出登录清除所有本地信息。\n\n' +
  '五、隐私政策变更\n' +
  '将通过应用更新说明等方式提前公示。\n\n' +
  '六、联系方式\n' +
  'pollenwang666@petalmail.com';

// 协议查看器视图模型（供嵌套自定义弹窗复用本地协议文本）
@ObservedV2
class PolicyVM {
  @Trace title: string = '';
  @Trace content: string = '';
}

// 持有当前协议弹窗节点，供「✕」关闭按钮调用
class PolicyDialogHolder {
  static node: ComponentContent<PolicyVM> | null = null;
  static promptAction: PromptAction | null = null;

  static close(): void {
    const node: ComponentContent<PolicyVM> | null = PolicyDialogHolder.node;
    const pa: PromptAction | null = PolicyDialogHolder.promptAction;
    if (!node || !pa) {
      return;
    }
    try {
      pa.closeCustomDialog(node);
    } catch (e) {
      console.error('[PolicyDialogHolder] close failed', e);
    }
    PolicyDialogHolder.node = null;
    PolicyDialogHolder.promptAction = null;
  }
}

@Builder
function buildPolicyDialog(vm: PolicyVM): void {
  Column() {
    Column() {
      Row() {
        Text(vm.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
        Blank()
        Text('✕')
          .fontSize(18)
          .fontColor('#999999')
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor(ThemeColors.bgInput)
          .textAlign(TextAlign.Center)
          .onClick(() => { PolicyDialogHolder.close(); })
      }
      .width('100%')
      .margin({ bottom: 16 })

      Scroll() {
        Text(vm.content)
          .fontSize(14)
          .fontColor(ThemeColors.textSecondary)
          .lineHeight(24)
      }
      .layoutWeight(1)
    }
    .width('90%')
    .height('80%')
    .padding(20)
    .borderRadius(13)
    .backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 16, color: '#00000020' })
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .backgroundColor('#4D000000')
}

@Entry
@Component
struct Index {
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  private accentColor: string = '#2979FF';
  private uiContext: UIContext = this.getUIContext();
  private promptAction: PromptAction = this.uiContext.getPromptAction();
  private controller: PrivacyConsentController = new PrivacyConsentController(this.getUIContext());

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
    this.showConsent();
  }

  // 拉起官方全屏隐私同意弹窗
  private showConsent(): void {
    const doc: PrivacyDocument = [
      { text: '欢迎使用 HiXD！在使用本应用前，请您仔细阅读并同意', type: TextType.PLAIN },
      { text: '《用户协议》', type: TextType.ACTION, onAction: () => this.openPolicy('user') },
      { text: '和', type: TextType.PLAIN },
      { text: '《隐私政策》', type: TextType.ACTION, onAction: () => this.openPolicy('privacy') },
      {
        text: '。\n\n本应用需要您使用学号和密码登录西安电子科技大学统一身份认证系统，' +
          '以获取课表、成绩等教务数据。您的账号密码仅用于校内认证，不会上传至任何第三方服务器。',
        type: TextType.PLAIN
      }
    ];
    this.controller
      .setAppIcon($r('app.media.hixd_icon'))
      .setAppName('HiXD')
      .setAppDescription('西安电子科技大学校园助手')
      .setTitle('用户协议与隐私政策')
      .setDocument(doc)
      .onAccept(() => {
        PreferenceUtil.putNumber('privacy_agreed_version', PRIVACY_POLICY_VERSION);
        this.controller.close();
        this.routeToMain();
      })
      .onReject(() => {
        try {
          const ctx = getContext(this) as common.UIAbilityContext;
          ctx.terminateSelf();
        } catch (_) { /* 退出应用 */ }
      });
    this.controller.openSheetDialog();
  }

  // 复用本地协议文本，以置顶自定义弹窗展示（稳定盖在同意弹窗之上）
  private openPolicy(type: string): void {
    const vm: PolicyVM = new PolicyVM();
    vm.title = type === 'user' ? '用户协议' : '隐私政策';
    vm.content = type === 'user' ? USER_AGREEMENT_TEXT : PRIVACY_POLICY_TEXT;
    const node: ComponentContent<PolicyVM> =
      new ComponentContent<PolicyVM>(this.uiContext, wrapBuilder(buildPolicyDialog), vm);
    PolicyDialogHolder.node = node;
    PolicyDialogHolder.promptAction = this.promptAction;
    this.promptAction.openCustomDialog(node, {
      alignment: DialogAlignment.Center,
      isModal: true,
      autoCancel: true,
      showInSubWindow: false,
      levelMode: LevelMode.EMBEDDED,
      immersiveMode: ImmersiveMode.EXTEND,
      keyboardAvoidMode: KeyboardAvoidMode.NONE
    }).catch((e: BusinessError) => {
      console.error('[Index] openPolicy failed', e);
      PolicyDialogHolder.node = null;
    });
  }

  private routeToMain(): void {
    router.replaceUrl({ url: 'pages/MainPage' });
  }

  build() {
    // 启动页背景（始终渲染，作为弹窗的底）
    Column() {
      LoadingProgress().width(48).height(48).color(this.accentColor)
      Text('HiXD').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.accentColor).margin({ top: 16 })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(ThemeColors.bgCard)
  }
}
