import { ThemeColors } from '../../../utils/ThemeColors';
import { PressScale } from '../../../components/PressScale';

// 首页数据卡（独立组件，@Prop 保证响应）
// 之前用 @Builder + 入参传递，ArkUI 的 @Builder 参数不具响应性：
// 父级（MainPage 的 @StorageLink）重渲染时，@Builder 入参在首构建后被缓存、不再随父重渲染重算，
// 导致卡片一直停在初始 '—'（DBG 直接 Text 却能显示正是此因）。
// 改成 @Component + @Prop 后，父重渲染会把新值自动同步进 @Prop，卡片必更新。
@Component
export struct HomeDataCard {
  @Prop icon: string = '';
  @Prop title: string = '';
  @Prop big: string = '';
  @Prop sub: string = '';
  @Prop color: string = '';
  @Prop loading: boolean = false;
  @Prop wide: boolean = false;   // 全宽卡片：横向布局（图标标题在左，大数字在右）
  @Prop actionLabel: string = '';  // 可选操作按钮文案（如"付款码"），仅全宽卡片展示
  @Prop tag: string = '';          // 可选小标签（如"余额"/"在借"），显示在标题与大数字之间
  onTap: () => void = () => { };
  onAction: () => void = () => { };

  @Builder
  BigContent() {
    if (this.loading && (this.big === '—' || this.big.startsWith('—'))) {
      LoadingProgress().width(22).height(22).color(this.color)
    } else {
      Text(this.big).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontSize(this.wide ? 24 : 22)
    }
  }

  build() {
    PressScale({ onTap: () => { this.onTap(); } }) {
    if (this.wide) {
      // 全宽：左（图标+标题+副信息）｜ 右（大数字）
      Row() {
        Column() {
          Row() {
            Text(this.icon).fontSize(26)
            Text(this.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              .margin({ left: 8 }).layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
          if (this.sub && this.sub.length > 0) {
            Text(this.sub).fontSize(11).fontColor(ThemeColors.textSecondary)
              .margin({ top: 6 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        .margin({ right: 12 })

        Column() {
          this.BigContent()
          if (this.actionLabel && this.actionLabel.length > 0) {
            Button(this.actionLabel)
              .height(30).borderRadius(15)
              .backgroundColor(this.color).fontColor('#FFFFFF')
              .fontSize(12).padding({ left: 14, right: 14 })
              .margin({ top: 8 })
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.onAction(); })
          }
        }.alignItems(HorizontalAlign.End)
      }
      .width('100%').height(88).padding(12)
      .backgroundColor(ThemeColors.bgCard).borderRadius(12)
      .shadow({ radius: 10, color: '#00000014', offsetY: 3 }).border({ width: 1, color: ThemeColors.border })
      .alignItems(VerticalAlign.Center)
      
    } else {
      // 半宽：上（图标+标题）｜ 中（大数字）｜ 底（副信息），固定高度保证等高
      Column() {
        Row() {
          Text(this.icon).fontSize(26)
          Text(this.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
            .margin({ left: 8 }).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%')
        if (this.tag && this.tag.length > 0) {
          Text(this.tag).fontSize(11).fontColor(ThemeColors.textSecondary)
            .margin({ top: 4 })
        }
        Column() { this.BigContent() }
          .margin({ top: 8 }).width('100%')
        Text(this.sub).fontSize(11).fontColor(ThemeColors.textSecondary)
          .margin({ top: 6 }).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%').height(124).padding(12)
      .backgroundColor(ThemeColors.bgCard).borderRadius(12)
      .shadow({ radius: 10, color: '#00000014', offsetY: 3 }).border({ width: 1, color: ThemeColors.border })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Start)
    }
    }
  }
}
