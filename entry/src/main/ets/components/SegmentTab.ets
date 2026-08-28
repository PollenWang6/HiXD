// SegmentTab.ets — 通用分段 Tab + Swiper 组件
// 胶囊背景 springMotion 滑动 + 文字颜色插值 + 手势跟随 + Swiper 联动
//
// 设计要点（修复平板首帧错位）：
//   - 胶囊/指示器宽度直接设为单页百分比 `100/len%`，用 translate 百分比平移。
//     translate 的百分比是「相对自身宽」，故进度 progress(第几页的小数) 直接驱动，
//     **不依赖任何测量宽度**，手机/平板首帧即正确，无需 onAreaChange 修正。
//   - 仅 Swiper.onAreaChange 保留 swiperWidth，且仅用于手势滑动比例换算，
//     静止定位完全不依赖它，不存在首帧错位问题。
//
// 用法：
//   SegmentTab({
//     tabs: ['电费', '水费'],
//     currentIndex: $activeTab,
//     accentColor: this.accentColor,
//     onTabChange: (idx: number) => { if (idx === 1) this.loadWater(); }
//   }) {
//     // Tab0 内容
//     this.elecContent()
//     // Tab1 内容
//     this.waterContent()
//   }

import { curves } from '@kit.ArkUI';
import { ThemeColors } from '../utils/ThemeColors';

@Component
export struct SegmentTab {
  @Prop tabs: string[] = [];
  @Link currentIndex: number;
  @Prop accentColor: string = '#2979FF';
  onTabChange?: (index: number) => void = undefined;
  // 再次点击「已激活」的 tab 时触发（用于论坛：回到顶部并刷新）
  onReTap?: (index: number) => void = undefined;
  @BuilderParam content: () => void = this.defaultContent;

  // 胶囊/指示器进度（单位：页）。0 = 第0页，1 = 第1页，可带小数做滑动跟随。
  @State capsuleProgress: number = 0;
  // 文字颜色插值进度（0 = tab0, 1 = tab1，可带小数）
  @State textProgress: number = 0;
  @State textSwipeProgress: number = 0;
  // 仅用于手势滑动比例换算（不影响静止定位）
  private swiperWidth: number = 0;
  private swiperCtrl: SwiperController = new SwiperController();

  @Builder defaultContent() {
    Column().width('100%')
  }

  aboutToAppear(): void {
    // 首帧即按当前页定位，无需等测量 —— 这是修复平板错位的关键
    this.capsuleProgress = this.currentIndex;
    this.textProgress = this.currentIndex;
  }

  build() {
    Column() {
      // Tab 栏
      Stack({ alignContent: Alignment.TopStart }) {
        // 滑动胶囊：外层宽度 = 单页宽(百分比)，translate 百分比(相对自身宽=单页宽)
        // 平移 progress*100% 即把胶囊移到第 progress 页；内层 80% 宽做视觉内缩。
        Row() {
          Row()
            .width('80%')
            .height(32)
            .borderRadius(16)
            .backgroundColor(this.accentColor + '20')
        }
        .width(`${100 / this.tabs.length}%`)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .translate({ x: `${this.capsuleProgress * 100}%` })

        // 文字（上层）。每页 layoutWeight(1) 均分，宽度 100% 父级，
        // 与胶囊/指示器共用同一百分比坐标系，任意父容器下都对齐。
        Row() {
          ForEach(this.tabs, (tab: string, idx: number) => {
            Column() {
              Text(tab)
                .fontSize(15)
                .fontColor(this.lerpColor(
                  ThemeColors.textSecondary,
                  this.accentColor,
                  this.getTextActive(idx)
                ))
                .fontWeight(this.getTextActive(idx) > 0.5 ? FontWeight.Bold : FontWeight.Normal)
            }
            .layoutWeight(1)
            .height(44)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              if (this.currentIndex === idx) {
                if (this.onReTap) { this.onReTap(idx); }
                return;
              }
              this.swiperCtrl.changeIndex(idx, true);
            })
          }, (tab: string, idx: number) => `seg_${idx}_${tab}`)
        }
        .width('100%')

        // 底部指示器（贴底：top=41 = 44-3）。
        // 外层宽度=单页宽并 translate 平移(相对自身宽=单页宽)，内层固定 24px 小横条居中
        // → 任意屏幕下都是「小条居中于当前页」，不再随屏宽变长。
        Row() {
          Row()
            .width(42)
            .height(3)
            .borderRadius(1.5)
            .backgroundColor(this.accentColor)
        }
        .width(`${100 / this.tabs.length}%`)
        .height(3)
        .justifyContent(FlexAlign.Center)
        .position({ y: 41 })
        .translate({ x: `${this.capsuleProgress * 100}%` })
      }
      .width('100%')
      .height(44)
      .border({ width: { bottom: 0.5 }, color: ThemeColors.border })

      // Swiper 内容区
      Swiper(this.swiperCtrl) {
        this.content()
      }
      .index(this.currentIndex)
      .indicator(false)
      .loop(false)
      .effectMode(EdgeEffect.Spring)
      .onAreaChange((_old: Area, newArea: Area) => {
        this.swiperWidth = newArea.width as number;
      })
      .onGestureSwipe((_index: number, event: SwiperAnimationEvent) => {
        const offset: number = event.currentOffset as number;
        if (this.swiperWidth <= 0) return;
        // 偏移 / 页宽 = 0..1 的「页分数」，直接累加到胶囊进度上做跟随
        const ratio: number = Math.abs(offset) / this.swiperWidth;
        this.capsuleProgress = this.currentIndex + (offset < 0 ? ratio : -ratio);
        this.textSwipeProgress = offset < 0 ? ratio : -ratio;
      })
      .onAnimationStart((_index: number, targetIndex: number, _event: SwiperAnimationEvent) => {
        animateTo({ duration: 350, curve: curves.springMotion(0.38, 0.85) }, () => {
          this.capsuleProgress = targetIndex;
          this.textProgress = targetIndex;
          this.textSwipeProgress = 0;
        });
        this.currentIndex = targetIndex;
        if (this.onTabChange) {
          this.onTabChange(targetIndex);
        }
      })
      .layoutWeight(1)
    }
    .width('100%').layoutWeight(1)
  }

  getTextActive(idx: number): number {
    const progress: number = this.textProgress + this.textSwipeProgress;
    // 通用写法：与当前进度的「距离」决定激活度，任意 tab 数都成立
    // （原 2-tab 公式在 3+ tab 时 progress>1 会让非首 tab 全亮）。
    // 滑动时 progress 为小数，相邻两 tab 平滑过渡；静止时 progress=currentIndex，仅当前 tab 为 1。
    return Math.max(0, 1 - Math.abs(idx - progress));
  }

  lerpColor(c1: string, c2: string, t: number): string {
    if (t <= 0) return c1;
    if (t >= 1) return c2;
    const r1: number = parseInt(c1.substring(1, 3), 16);
    const g1: number = parseInt(c1.substring(3, 5), 16);
    const b1: number = parseInt(c1.substring(5, 7), 16);
    const r2: number = parseInt(c2.substring(1, 3), 16);
    const g2: number = parseInt(c2.substring(3, 5), 16);
    const b2: number = parseInt(c2.substring(5, 7), 16);
    const r: number = Math.round(r1 + (r2 - r1) * t);
    const g: number = Math.round(g1 + (g2 - g1) * t);
    const b: number = Math.round(b1 + (b2 - b1) * t);
    const rh: string = r.toString(16).padStart(2, '0');
    const gh: string = g.toString(16).padStart(2, '0');
    const bh: string = b.toString(16).padStart(2, '0');
    return `#${rh}${gh}${bh}`;
  }
}
