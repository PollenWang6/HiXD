// Index.ets — 启动门禁页：先征求隐私/协议同意，同意后再进入主页
// 合规要点：同意必须在登录/收集个人信息、联网之前（PIPL + 应用市场审核要求）
// UI：使用华为官方「通用隐私同意弹窗组件」(privacy_consent_dialog HAR) 的模态底部样式（SHEET / bottom sheet）
//      —— 从屏幕底部升起的半屏卡片：应用图标 + 应用名 + 描述 + 盾牌 + 可滚动协议 + 底部「退出应用 / 同意并继续」
//      该 HAR 已从官方生态市场下载至工程根目录，并去掉唯一外部依赖 @hw-agconnect/util-log（仅日志用）。
import {
  router
} from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { PrivacyConsentController, PrivacyDocument, TextType } from 'privacy_consent_dialog';
import { ThemeColors } from '../utils/ThemeColors';
import { AccentColors } from '../utils/AccentColors';
import { PreferenceUtil } from '../utils/PreferenceUtil';

// 隐私政策版本号：文案有重大变更时 +1，自动重新弹窗征得同意
const PRIVACY_POLICY_VERSION: number = 1;


@Entry
@Component
struct Index {
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  private accentColor: string = '#2979FF';
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
      { text: '《用户协议》', type: TextType.ACTION, onAction: () => this.openExternal('https://pollenwang6.github.io/HiXD/user-agreement.html') },
      { text: '和', type: TextType.PLAIN },
      { text: '《隐私政策》', type: TextType.ACTION, onAction: () => this.openExternal('https://pollenwang6.github.io/HiXD/privacy.html') },
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

  // 跳转外部链接（隐私政策在线版等）
  private openExternal(url: string): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.openLink(url).catch(() => {});
    } catch (_e) {
      // 无法拉起浏览器时忽略
    }
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
