import { ThemeColors } from '../utils/ThemeColors';

// 周次选择 chip —— 独立组件，点击只重渲染自身，解决原内联 ForEach 全量重绘卡顿
@Component
export struct WeekChip {
  @Prop week: number = 1;
  @Prop selected: boolean = false;
  @Prop current: number = 1;
  @Prop accent: string = '#2979FF';
  onToggle?: () => void;

  build() {
    Column() {
      Text(String(this.week))
        .fontSize(13)
        .fontColor(this.selected ? '#FFFFFF' : ThemeColors.textSecondary)
        .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
    }
    .justifyContent(FlexAlign.Center)
    .width(36).height(36)
    .borderRadius(18)
    .border({
      width: (this.current === this.week && !this.selected) ? 2 : 0,
      color: this.accent,
      style: BorderStyle.Solid
    })
    .backgroundColor(this.selected ? this.accent : ThemeColors.bgInput)
    .onClick(() => { if (this.onToggle) { this.onToggle(); } })
  }
}
