// DeclarationPage.ets — 首启「非官方 / 无关联」强制声明页
// 上架合规要点：华为应用市场审核以「官方误认」驳回（应用功能与校名强关联、缺官方授权证明）。
//   规避手段（参考 DailyNic_HMOS）：在隐私同意之前，先用独立首启页让用户「手打」确认句，
//   显式承认「本应用非官方、与学校无任何关联」，并将该确认持久化，避免用户产生混淆、误认。
// UI：单屏 + 可滚动声明正文（警示色）+ 须原样输入确认句（仿 DailyNic 第 2 屏手打门控）+ 进入按钮；
//   输入与标准句不一致则按钮禁用，已确认过则不再出现。隐私同意仍由 Index 的华为弹窗负责。
import { router } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeColors } from '../utils/ThemeColors';
import { PreferenceUtil } from '../utils/PreferenceUtil';

// 首启声明确认标记（一次确认，永久生效）
const DECLARATION_AGREED_KEY: string = 'declaration_agreed';

// 必须「原样输入」的确认句（仿 DailyNic 句式，去掉引号降低输入难度）
const CONFIRM_SENTENCE: string =
  '我已知晓并承认HiXD由独立开发者自主开发，与西安电子科技大学官方无任何关联';

@Entry
@Component
struct DeclarationPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State typed: string = '';
  @State matched: boolean = false;

  aboutToAppear(): void {
    // 主题已在 Index 提前初始化；此处兜底确保声明页自身用色正确
    const savedMode: number = PreferenceUtil.getNumber('theme_color_mode',
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    ThemeColors.init(savedMode, getContext(this));
  }

  // 实时比对：去掉首尾空白后与标准句完全一致才解锁
  private onInput(value: string): void {
    this.typed = value;
    this.matched = value.trim() === CONFIRM_SENTENCE;
  }

  // 确认后写标记并回到 Index，由 Index 继续隐私同意流程
  private onConfirm(): void {
    if (!this.matched) {
      return;
    }
    PreferenceUtil.putBool(DECLARATION_AGREED_KEY, true);
    router.replaceUrl({ url: 'pages/Index' });
  }

  // 阻断返回：首启声明为强制门禁，必须确认或退出应用
  onBackPress(): boolean {
    return true;
  }

  build() {
    Column() {
      // 顶部品牌区
      Column({ space: 10 }) {
        Image($r('app.media.icon'))
          .width(72)
          .height(72)
          .borderRadius(16)
          .objectFit(ImageFit.Contain)
        Text('HiXD')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
        Text('非官方声明')
          .fontSize(15)
          .fontColor(ThemeColors.textSecondary)
      }
      .width('100%')
      .margin({ top: 32, bottom: 16 })

      // 可滚动声明正文
      Scroll() {
        Column({ space: 14 }) {
          Text('重要提示')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.warning)
            .width('100%')
            .textAlign(TextAlign.Start)

          Text() {
            Span('本应用「HiXD」由独立开发者自主开发，并非西安电子科技大学的官方应用，也未获得学校任何官方授权或认证。')
          }
          .fontSize(15)
          .lineHeight(24)
          .fontColor(ThemeColors.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

          Text() {
            Span('本应用全程未使用任何学校官方标识或表述，未在应用介绍、名称或任何界面中以任何方式宣称、暗示自身为「官方应用」，或与校方存在合作、隶属关系。')
          }
          .fontSize(15)
          .lineHeight(24)
          .fontColor(ThemeColors.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

          Text() {
            Span('应用内所提供的课表、成绩、考试、空教室、校园卡、图书馆、自习座位、睿思论坛等功能，仅是对学校公开网络服务的快捷聚合与查询入口，不代表与学校存在任何官方关联。')
          }
          .fontSize(15)
          .lineHeight(24)
          .fontColor(ThemeColors.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)

          Text() {
            Span('若您对上述内容存在疑问，可随时通过学校官方渠道自行核实。')
          }
          .fontSize(15)
          .lineHeight(24)
          .fontColor(ThemeColors.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Start)
        }
        .padding(16)
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(ThemeColors.bgCard)
      .borderRadius(12)
      .scrollBar(BarState.Off)

      // 手打确认区（固定）
      Column({ space: 10 }) {
        Text('为确认您已知晓上述声明，请在下方完整、准确地输入这句话：')
          .fontSize(13)
          .lineHeight(20)
          .fontColor(ThemeColors.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Start)

        // 标准句（长按可复制，降低输入错误）
        Text(CONFIRM_SENTENCE)
          .fontSize(14)
          .lineHeight(22)
          .fontColor(ThemeColors.accent)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)
          .copyOption(CopyOptions.InApp)
          .padding(10)
          .backgroundColor(ThemeColors.bgInput)
          .borderRadius(8)

        TextArea({ placeholder: '在此输入上方句子' })
          .width('100%')
          .height(64)
          .borderRadius(8)
          .backgroundColor(ThemeColors.bgInput)
          .onChange((value: string) => this.onInput(value))

        // 实时反馈
        Text(this.matched ? '✓ 输入无误，可进入应用' : '输入需与上方句子完全一致')
          .fontSize(12)
          .fontColor(this.matched ? ThemeColors.success : ThemeColors.textHint)
          .width('100%')
          .textAlign(TextAlign.Start)

        Button(this.matched ? '我已知晓，进入应用' : '请先准确输入确认句')
          .width('100%')
          .height(48)
          .borderRadius(24)
          .backgroundColor(this.matched ? ThemeColors.accent : ThemeColors.bgInput)
          .fontColor(this.matched ? ThemeColors.textOnDark : ThemeColors.textHint)
          .enabled(this.matched)
          .onClick(() => this.onConfirm())
      }
      .width('100%')
      .padding({ top: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: this.statusBarHeight })
    .backgroundColor(ThemeColors.bgPage)
    .alignItems(HorizontalAlign.Start)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
