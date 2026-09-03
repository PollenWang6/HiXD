import { ThemeColors } from '../../../utils/ThemeColors';
import { PressScale } from '../../../components/PressScale';

// 校园卡首页卡片：余额 + 上笔消费 + 付款码按钮
// 付款码按钮放在 PressScale 外层（Stack 叠加），避免点击付款码时事件冒泡触发卡片 onTap 进校园卡子页
@Component
export struct SchoolCardHomeCard {
  @StorageLink('home_card_balance') snapCardBalance: string = '—';
  @StorageLink('home_card_consume') snapCardConsume: string = '—';
  @StorageLink('home_card_consume_date') snapCardConsumeDate: string = '—';
  @Prop homeLoading: boolean = false;
  onTap: () => void = () => {};
  onPayCode: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 卡片主体（点击进校园卡子页）
      PressScale({ onTap: () => { this.onTap(); } }) {
        Column() {
          Row() {
            Row() {
              Text('💳').fontSize(26)
              Text('校园卡').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                .margin({ left: 8 }).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.layoutWeight(1)
            // 右侧留白给付款码按钮（Stack 叠加）
            Column().width(70)
          }.width('100%')

          Row() {
            Column() {
              Text('余额').fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
              if (this.homeLoading && this.snapCardBalance === '—') {
                LoadingProgress().width(22).height(22).color('#BF4D00').margin({ top: 6 })
              } else {
                Text(this.snapCardBalance === '—' ? '—' : '¥' + this.snapCardBalance)
                  .fontSize(26).fontWeight(FontWeight.Bold).fontColor('#BF4D00')
                  .margin({ top: 4 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width(110).alignItems(HorizontalAlign.Start)

            Column() {
              Row() {
                Text('上笔消费').fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
                Text(this.snapCardConsume)
                  .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                  .margin({ left: 6 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.alignItems(VerticalAlign.Center)

              Text(this.snapCardConsumeDate)
                .fontSize(14).fontColor(ThemeColors.textSecondary)
                .margin({ top: 4 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 38 })
          }.width('100%').margin({ top: 12 })

        }
        .width('100%').padding(14)
        .backgroundColor(ThemeColors.bgCard).borderRadius(12)
        .shadow({ radius: 10, color: '#00000014', offsetY: 3 }).border({ width: 1, color: ThemeColors.border })
        .alignItems(HorizontalAlign.Start)
      }

      // 付款码按钮（叠加在右上角，不在 PressScale 内，避免事件冒泡）
      Button('付款码')
        .height(30).borderRadius(15)
        .backgroundColor('#BF4D00').fontColor('#FFFFFF')
        .fontSize(12).padding({ left: 14, right: 14 })
        .margin({ top: 14, right: 14 })
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.onPayCode(); })
    }
    .width('100%')
  }
}
