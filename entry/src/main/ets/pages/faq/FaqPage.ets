// FaqPage.ets — 常见问题
import { ThemeColors } from '../../utils/ThemeColors';

@Component
export struct FaqPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  @Prop isTablet: boolean = false;

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            // 标题
            Text('写在前面').fontSize(24).fontWeight(FontWeight.Bold)
              .fontColor(ThemeColors.textPrimary).width('100%')
              .padding({ top: 20, bottom: 8, left: 20, right: 20 })

            // 介绍
            this.TextBlock('作者非相关专业人士，代码几乎全为 AI 完成，能力有限，bug 可能较多请见谅。\n对于使用 HarmonyOS 且不想使用卓易通的用户或许是个不错的选择 🤔。')
            Divider().color(ThemeColors.isDark ? '#38383A' : '#F0F0F0').margin({ top: 16, bottom: 16 })

            // 常见问题
            Text('可能遇到的问题').fontSize(20).fontWeight(FontWeight.Bold)
              .fontColor(ThemeColors.textPrimary).width('100%')
              .padding({ left: 20, right: 20, bottom: 12 })

            this.QaCard(
              'P & S',
              '概率性"移动门户"和"水电缴费"无法打开怎么办',
              '可以先进入"订水系统"完成初始化再进入这两个界面。'
            )
            this.QaCard(
              'P & S',
              '概率性无法拉起微信支付怎么办',
              '使用右上角菜单中的"在浏览器打开"。'
            )
            this.QaCard(
              'P & S',
              '登录状态掉了没有弹出滑块验证',
              '"主页"右上角点击登录重新进入登录界面。'
            )
            this.QaCard(
              'P & S',
              '显示已登录但无法获取数据',
              '"我的"界面退出登录后重新登录，仍不行则卸载重装。'
            )
            this.QaCard(
              'P & S',
              '实验信息怎么刷新',
              '页面内下拉刷新即可（同时刷新其他实验和物理实验）。'
            )

            // 下载
            this.SectionText('软件下载')
            this.TextBlock('安装包可在以下地址获取：\nhttps://sydxky.cn/detail.php?id=453')

            // 反馈
            this.SectionText('问题反馈')
            this.TextBlock('出现其他问题可通过 1727881630@qq.com 反馈，\n也不确定是否可以解决 😭')

          }.width(this.isTablet ? '60%' : '100%').padding({ bottom: 32 })
          .alignSelf(ItemAlign.Center)
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor(ThemeColors.bgInput)
    }
    .title(this.customTitle(), { backgroundColor: this.accentColor })
    .backgroundColor(ThemeColors.bgPage)
    .hideBackButton(true)
  }

  @Builder customTitle() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close')).height(22)
          .fillColor(ThemeColors.textPrimary).draggable(false)
      }.height(40).width(40).onClick(() => { this.pageInfo.pop(); })
      Text('常见问题').fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.height(56).width('100%').padding({ left: 12, right: 12 })
  }

  @Builder SectionText(text: string) {
    Text(text).fontSize(18).fontWeight(FontWeight.Bold)
      .fontColor(ThemeColors.textPrimary).width('100%')
      .padding({ top: 20, bottom: 8, left: 20, right: 20 })
  }

  @Builder TextBlock(text: string) {
    Text(text).fontSize(15).fontColor(ThemeColors.textSecondary)
      .width('100%').padding({ left: 20, right: 20 })
      .lineHeight(24).copyOption(CopyOptions.LocalDevice)
  }

  @Builder QaCard(question: string, answer: string, solution: string) {
    Column() {
      Text(question).fontSize(15).fontWeight(FontWeight.Bold)
        .fontColor('#FF6D00').width('100%').padding({ bottom: 6 })
        .copyOption(CopyOptions.LocalDevice)
      Text(answer).fontSize(14).fontColor(ThemeColors.textPrimary)
        .width('100%').padding({ bottom: 4 }).copyOption(CopyOptions.LocalDevice)
      Text('💡 ' + solution).fontSize(13).fontColor(ThemeColors.textSecondary)
        .width('100%').lineHeight(22).copyOption(CopyOptions.LocalDevice)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 14 })
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(12)
    .margin({ left: 20, right: 20, bottom: 12 })
  }
}
