import { ThemeColors } from '../../../utils/ThemeColors';
import { PressScale } from '../../../components/PressScale';
import { deviceInfo } from '@kit.BasicServicesKit';

// 更多功能Tab
@Component
export struct PortalTab {
  @Prop statusBarHeight: number = 0;
  @Prop accentColor: string = '#1976D2';
  @Prop accentTextColor: string = '#FFFFFF';
  @Prop portalMenuOrder: string[] = [];
  @Prop portalSortOn: boolean = false;
  onMoveUp: (idx: number) => void = () => {};
  onMoveDown: (idx: number) => void = () => {};
  onToggleSort: () => void = () => {};
  onItemClick: (name: string) => void = () => {};

  @Builder
  MenuItemBuilder(icon: string, title: string, desc: string, color: string, onClick: () => void) {
    PressScale({ onTap: () => { onClick(); } }) {
    Row() {
      Text(icon).fontSize(26).margin({ right: 16 })
      Column() {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(desc).fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Text('›').fontSize(20).fontColor(ThemeColors.textSecondary)
    }
    .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(12).backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 10, color: '#00000014', offsetY: 3 }).border({ width: 1, color: ThemeColors.border })
    }
  }

  @Builder
  PortalMenuItemByName(name: string) {
    if (name === 'Dianfei') {
      this.MenuItemBuilder('💰', '水电缴费', '线上一键缴纳水电费用', '#BF4D00',
        () => { this.onItemClick('Dianfei'); })
    } else if (name === 'Dingshui') {
      this.MenuItemBuilder('💧', '订水系统', '再忙也不要忘记喝水呦！', '#0277BD',
        () => { this.onItemClick('Dingshui'); })
    } else if (name === 'Baoxiu') {
      this.MenuItemBuilder('🛠️', '后勤报修', '足不出户提交报修', '#5D4037',
        () => { this.onItemClick('Baoxiu'); })
    } else if (name === 'Space') {
      this.MenuItemBuilder('🏢', '空间预约', '找一个可以集体讨论的地方', '#1565C0',
        () => { this.onItemClick('Space'); })
    } else if (name === 'Portal') {
      this.MenuItemBuilder('📱', '移动门户', '校园服务一网打尽', '#00695C',
        () => { this.onItemClick('Portal'); })
    } else if (name === 'Ruisi') {
      this.MenuItemBuilder('🧭', '睿思导航', '补充其他功能', '#4527A0',
        () => { this.onItemClick('Ruisi'); })
    } else if (name === 'Physics') {
      this.MenuItemBuilder('🔬', '物理计算', '实验数据处理助手', '#00897B',
        () => { this.onItemClick('Physics'); })
    } else if (name === 'Mail') {
      this.MenuItemBuilder('📧', '学生邮箱', '查看icoremail邮件', '#D32F2F',
        () => { this.onItemClick('Mail'); })
    } else if (name === 'Net') {
      this.MenuItemBuilder('🌐', '校园网登录', '校园网状态与自助服务', '#00ACC1',
        () => { this.onItemClick('Net'); })
    } else if (name === 'SchoolCardWeb') {
      this.MenuItemBuilder('🪪', '校园卡服务', '挂失/解绑/修改密码', '#FF7043',
        () => { this.onItemClick('SchoolCardWeb'); })
    }
  }

  build() {
    Column() {
      Row() {
        Text('更多功能').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor)
      }
      .width('100%').height(52 + this.statusBarHeight).padding({ left: 20, top: this.statusBarHeight })
      .backgroundColor(this.accentColor)
      Divider().color('#F0F0F0')

      List({ space: 8 }) {
        ForEach(this.portalMenuOrder, (name: string, idx: number) => {
          ListItem() {
            Row() {
              if (this.portalSortOn) {
                Column({ space: 2 }) {
                  Text('⬆').fontSize(14).hoverEffect(HoverEffect.Auto).onClick(() => { this.onMoveUp(idx); })
                  Text('⬇').fontSize(14).hoverEffect(HoverEffect.Auto).onClick(() => { this.onMoveDown(idx); })
                }.width(28).alignItems(HorizontalAlign.Center).margin({ right: 4 })
              }
              this.PortalMenuItemByName(name)
            }.width('100%')
          }
        }, (name: string) => name)

        ListItem() {
          Row() {
            Blank()
            Text(this.portalSortOn ? '完成' : '⇅ 排序').fontSize(13).fontColor(this.accentColor)
          }.width('100%').padding({ right: 6, top: 4, bottom: 4 })
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.onToggleSort(); })
        }
        ListItem().height(deviceInfo.distributionOSApiVersion >= 60100 ? 120 : 108)
      }
      .padding({ left: 16, right: 16, top: 8 })
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
  }
}
