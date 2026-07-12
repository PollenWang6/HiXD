// SegmentTab.ets — 通用分段 Tab + Swiper 组件
// 胶囊背景 springMotion 滑动 + 文字颜色插值 + 手势跟随 + Swiper 联动
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
  @BuilderParam content: () => void = this.defaultContent;

  // 胶囊位置（动画目标值）
  @State capsuleX: number = 0;
  // 手势滑动偏移
  @State capsuleSwipe: number = 0;
  // 文字进度（0 = tab0, 1 = tab1）
  @State textProgress: number = 0;
  @State textSwipeProgress: number = 0;
  // 容器宽度
  @State barW: number = 360;
  private perTabW: number = 180;
  private swiperCtrl: SwiperController = new SwiperController();
  private swiperWidth: number = 360;

  @Builder defaultContent() {
    Column().width('100%')
  }

  aboutToAppear(): void {
    // 初始化胶囊位置
    this.textProgress = this.currentIndex;
  }

  build() {
    Column() {
      // Tab 栏
      Stack({ alignContent: Alignment.TopStart }) {
        // 胶囊背景（垂直居中：top=6, height=32, 总44）
        // 位置直接用 Stack 坐标，x = 当前页偏移 + 滑动偏移 + 每页宽 10%
        Row()
          .width(this.perTabW * 0.8)
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.accentColor + '20')
          .position({
            x: this.capsuleX + this.capsuleSwipe + this.perTabW * 0.1,
            y: 6
          })

        // 文字（上层）。宽度显式绑定到 Stack 实测宽度，
        // 保证文字均分与胶囊/指示器使用同一坐标系，任意父级容器下都对齐。
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
              if (this.currentIndex === idx) return;
              this.swiperCtrl.changeIndex(idx, true);
            })
          }, (tab: string, idx: number) => `seg_${idx}_${tab}`)
        }
        .width(this.barW)

        // 底部指示器（贴底：top=41 = 44-3），居中于每页
        Row()
          .width(24)
          .height(3)
          .borderRadius(1.5)
          .backgroundColor(this.accentColor)
          .position({
            x: this.capsuleX + this.capsuleSwipe + this.perTabW * 0.5 - 12,
            y: 41
          })
      }
      .width('100%')
      .height(44)
      .border({ width: { bottom: 0.5 }, color: ThemeColors.border })
      // 关键：宽度以 Stack 自身为准（胶囊/指示器的坐标父级），
      // 不再依赖文字 Row 的 onAreaChange，避免不同父容器下两套坐标错位。
      .onAreaChange((_old: Area, newArea: Area) => {
        const w: number = newArea.width as number;
        if (w > 0) {
          this.barW = w;
          this.perTabW = w / this.tabs.length;
          this.capsuleX = this.currentIndex * this.perTabW;
        }
      })

      // Swiper 内容区
      Swiper(this.swiperCtrl) {
        this.content()
      }
      .index(this.currentIndex)
      .indicator(false)
      .loop(false)
      .onAreaChange((_old: Area, newArea: Area) => {
        this.swiperWidth = newArea.width as number;
      })
      .onGestureSwipe((_index: number, event: SwiperAnimationEvent) => {
        const offset: number = event.currentOffset as number;
        if (this.swiperWidth <= 0 || this.perTabW <= 0) return;
        const ratio: number = Math.abs(offset) / this.swiperWidth;
        const move: number = ratio >= 1 ? this.perTabW : this.perTabW * ratio;
        this.capsuleSwipe = offset < 0 ? move : -move;
        this.textSwipeProgress = offset < 0 ? ratio : -ratio;
      })
      .onAnimationStart((_index: number, targetIndex: number, _event: SwiperAnimationEvent) => {
        animateTo({ duration: 350, curve: curves.springMotion(0.38, 0.85) }, () => {
          this.capsuleX = targetIndex * this.perTabW;
          this.capsuleSwipe = 0;
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
    if (idx === 0) {
      return Math.max(0, 1 - progress);
    } else {
      return Math.max(0, Math.min(1, progress));
    }
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
