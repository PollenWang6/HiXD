// ColorWheelPicker.ets — HSV 取色盘（DrawModifier + Canvas）
import { drawing } from '@kit.ArkGraphics2D';
import { ThemeColors } from '../utils/ThemeColors';
import { AccentColors } from '../utils/AccentColors';

// ========== HSV 颜色工具 ==========
function hsvToRgb(h: number, s: number, v: number): { r: number, g: number, b: number } {
  let r = 0, g = 0, b = 0;
  const i = Math.floor(h / 60);
  const f = h / 60 - i;
  const p = v * (1 - s);
  const q = v * (1 - f * s);
  const t = v * (1 - (1 - f) * s);
  switch (i % 6) {
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    case 5: r = v; g = p; b = q; break;
    default: break;
  }
  return { r: Math.round(r * 255), g: Math.round(g * 255), b: Math.round(b * 255) };
}

function rgbToHex(r: number, g: number, b: number): string {
  const hx = (v: number) => Math.max(0, Math.min(255, v)).toString(16).toUpperCase().padStart(2, '0');
  return '#' + hx(r) + hx(g) + hx(b);
}

function rgbToHsv(r: number, g: number, b: number): { h: number, s: number, v: number } {
  const nr = r / 255, ng = g / 255, nb = b / 255;
  const max = Math.max(nr, ng, nb), min = Math.min(nr, ng, nb), delta = max - min;
  let h = 0;
  if (delta !== 0) {
    if (max === nr) h = ((ng - nb) / delta + (ng < nb ? 6 : 0)) * 60;
    else if (max === ng) h = ((nb - nr) / delta + 2) * 60;
    else h = ((nr - ng) / delta + 4) * 60;
  }
  return { h: h % 360, s: max === 0 ? 0 : delta / max, v: max };
}

// ========== Canvas 绘制器 ==========
class ColorWheelModifier extends DrawModifier {
  public hue: number = 0;
  public sat: number = 1;
  public val: number = 1;
  private uiCtx: UIContext;
  constructor(uiCtx: UIContext) { super(); this.uiCtx = uiCtx; }

  drawContent(context: DrawContext): void {
    const cw = context.size.width;
    const ch = context.size.height;
    const svW = this.uiCtx.vp2px(200);
    const barW = this.uiCtx.vp2px(24);
    const gap = this.uiCtx.vp2px(16);
    const sx = (cw - svW - gap - barW) / 2;
    const sy = (ch - svW) / 2;
    const bx = sx + svW + gap;
    const by = sy;

    // 1. SV 方块底色
    const bc = hsvToRgb(this.hue, 1, 1);
    const brush = new drawing.Brush();
    brush.setColor({ alpha: 255, red: bc.r, green: bc.g, blue: bc.b });
    context.canvas.attachBrush(brush);
    context.canvas.drawRect({ left: sx, top: sy, right: sx + svW, bottom: sy + svW });
    // 白渐变（左→右, 控制饱和度）
    for (let x = 0; x < svW; x += 3) {
      const a = 255 - Math.round((x / svW) * 255);
      const wb = new drawing.Brush();
      wb.setColor({ alpha: a < 0 ? 0 : a, red: 255, green: 255, blue: 255 });
      context.canvas.attachBrush(wb);
      context.canvas.drawRect({ left: sx + x, top: sy, right: sx + x + 3, bottom: sy + svW });
    }
    // 黑渐变（上→下, 控制明度）
    for (let y = 0; y < svW; y += 3) {
      const a = 180 - Math.round((y / svW) * 180);
      const bb = new drawing.Brush();
      bb.setColor({ alpha: a < 0 ? 0 : a, red: 0, green: 0, blue: 0 });
      context.canvas.attachBrush(bb);
      context.canvas.drawRect({ left: sx, top: sy + y, right: sx + svW, bottom: sy + y + 3 });
    }
    context.canvas.detachBrush();

    // 2. 色相条（从上到下 0°→360°）
    for (let y = 0; y < svW; y++) {
      const color = hsvToRgb((y / svW) * 360, 1, 1);
      const hb = new drawing.Brush();
      hb.setColor({ alpha: 255, red: color.r, green: color.g, blue: color.b });
      context.canvas.attachBrush(hb);
      context.canvas.drawRect({ left: bx, top: by + y, right: bx + barW, bottom: by + y + 1 });
    }
    context.canvas.detachBrush();

    // 3. SV 光标
    const scx = sx + Math.round(this.sat * svW);
    const scy = sy + Math.round((1 - this.val) * svW);
    const p1 = new drawing.Pen();
    p1.setColor({ alpha: 255, red: 255, green: 255, blue: 255 });
    p1.setStrokeWidth(this.uiCtx.vp2px(3));
    context.canvas.attachPen(p1);
    context.canvas.drawCircle(scx, scy, this.uiCtx.vp2px(6));
    const p2 = new drawing.Pen();
    p2.setColor({ alpha: 255, red: 0, green: 0, blue: 0 });
    p2.setStrokeWidth(this.uiCtx.vp2px(1));
    context.canvas.attachPen(p2);
    context.canvas.drawCircle(scx, scy, this.uiCtx.vp2px(6));
    context.canvas.detachPen();

    // 4. 色相条指示线
    const hy = by + Math.round((this.hue / 360) * svW);
    const ip = new drawing.Pen();
    ip.setColor({ alpha: 255, red: 255, green: 255, blue: 255 });
    ip.setStrokeWidth(this.uiCtx.vp2px(3));
    context.canvas.attachPen(ip);
    context.canvas.drawLine(bx - this.uiCtx.vp2px(4), hy, bx + barW + this.uiCtx.vp2px(4), hy);
    context.canvas.detachPen();
  }
}

// ========== 组件 ==========
@Component
export struct ColorWheelPicker {
  @Prop onColorChange?: (hex: string) => void;
  @Prop onApply?: () => void;
  @State previewHex: string = '#2979FF';
  @State previewR: number = 41;
  @State previewG: number = 121;
  @State previewB: number = 255;

  private modifier: ColorWheelModifier = new ColorWheelModifier(this.getUIContext());
  private canvasW: number = 300;
  private canvasH: number = 250;

  aboutToAppear(): void {
    const hsv = rgbToHsv(this.previewR, this.previewG, this.previewB);
    this.modifier.hue = hsv.h;
    this.modifier.sat = hsv.s;
    this.modifier.val = hsv.v;
  }

  private handleTouch(x: number, y: number, w: number, h: number): void {
    // Canvas 内元素布局: svW=200, barW=24, gap=16, 总宽=240
    // 触摸坐标需要映射到这个坐标系
    const total = 240;
    const svW = 200;
    const barW = 24;
    const gap = 16;
    const scaleX = total / w;
    const pixX = x * scaleX;
    const pixY = y * (200 / h);

    if (pixX >= 0 && pixX <= svW && pixY >= 0 && pixY <= 200) {
      // SV 方块: X=饱和度(左→右), Y=明度(上→下, 0→1 在上面)
      this.modifier.sat = Math.max(0, Math.min(1, pixX / svW));
      this.modifier.val = Math.max(0, Math.min(1, 1 - pixY / 200));
    } else if (pixX >= svW + gap && pixX <= svW + gap + barW && pixY >= 0 && pixY <= 200) {
      // 色相条: Y=色相(上→下, 0°→360°)
      this.modifier.hue = Math.max(0, Math.min(360, (pixY / 200) * 360));
    }
    this.modifier.invalidate();
    const c = hsvToRgb(this.modifier.hue, this.modifier.sat, this.modifier.val);
    this.previewR = c.r;
    this.previewG = c.g;
    this.previewB = c.b;
    this.previewHex = rgbToHex(c.r, c.g, c.b);
  }

  build() {
    Column() {
      // Canvas 区域（固定宽高比）
      Stack() {
      }
      .width('100%').aspectRatio(240 / 200)
      .onAreaChange((_old: Area, newArea: Area) => {
        this.canvasW = newArea.width as number;
        this.canvasH = newArea.height as number;
      })
      .drawModifier(this.modifier)
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
          .onActionStart((e: GestureEvent) => {
            this.handleTouch(e.offsetX as number, e.offsetY as number, this.canvasW, this.canvasH);
          })
          .onActionUpdate((e: GestureEvent) => {
            this.handleTouch(e.offsetX as number, e.offsetY as number, this.canvasW, this.canvasH);
          })
          .onActionEnd(() => {
            if (this.onColorChange) this.onColorChange(this.previewHex);
          })
      )

      // 预览 + Hex
      Row() {
        Column() {}
          .width(44).height(44).backgroundColor(this.previewHex).borderRadius(8)
          .border({ width: 2, color: '#E0E0E0' })
        Column() {
          Text(this.previewHex).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary).fontFamily('monospace')
          Text(`R:${this.previewR} G:${this.previewG} B:${this.previewB}`)
            .fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 3 })
        }.margin({ left: 12 }).alignItems(HorizontalAlign.Start)
        Blank()
      }.width('100%').margin({ top: 10 })

      // 应用按钮
      Button('使用此颜色').width('100%').height(44).fontSize(15)
        .backgroundColor(this.previewHex).fontColor('#FFFFFF').borderRadius(10)
        .margin({ top: 12 })
        .onClick(() => {
          const hex = this.previewHex;
          AccentColors.selectCustom(hex);
          if (this.onApply) this.onApply();
          if (this.onColorChange) this.onColorChange(hex);
        })
    }
    .width('100%')
  }
}
