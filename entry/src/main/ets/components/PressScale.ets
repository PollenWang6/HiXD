/**
 * PressScale - 通用按下缩放点击反馈组件
 * 用于带阴影/背景色的卡片，hoverEffect 高亮被吃掉时替代
 * 按下缩放到 0.96，松开弹回 1.0，120ms EaseInOut
 * 滑动距离超过 10vp 时不触发 onTap（防止 Scroll 内滑动误触）
 */

@Component
export struct PressScale {
  @State pressed: boolean = false;
  @BuilderParam content: () => void;
  onTap: () => void = () => {};
  private startX: number = 0;
  private startY: number = 0;
  private static readonly TAP_THRESHOLD: number = 10; // vp，超过则视为滑动

  build() {
    Stack() {
      this.content()
    }
    .width('100%')
    .scale({ x: this.pressed ? 0.96 : 1.0, y: this.pressed ? 0.96 : 1.0 })
    .animation({ duration: 120, curve: Curve.EaseInOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
        this.startX = event.touches[0].x;
        this.startY = event.touches[0].y;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
        if (event.type === TouchType.Up) {
          const dx = event.touches[0].x - this.startX;
          const dy = event.touches[0].y - this.startY;
          const distance = Math.sqrt(dx * dx + dy * dy);
          if (distance <= PressScale.TAP_THRESHOLD) {
            this.onTap();
          }
        }
      }
    })
  }
}
