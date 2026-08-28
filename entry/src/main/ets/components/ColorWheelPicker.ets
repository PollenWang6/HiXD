// ColorWheelPicker.ets — Canvas 无极取色盘（官方文档方案）
import { ThemeColors } from '../utils/ThemeColors';
import { AccentColors } from '../utils/AccentColors';

const SZ = 280;

function hsvToRgb(h: number, s: number, v: number): number[] {
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
  }
  return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)];
}

function hsvToHex(h: number, s: number, v: number): string {
  const c = hsvToRgb(h, s, v);
  return '#' + c.map((x: number) => Math.max(0, Math.min(255, x)).toString(16).toUpperCase().padStart(2, '0')).join('');
}

function rgbToHsv(r: number, g: number, b: number): number[] {
  const nr = r / 255, ng = g / 255, nb = b / 255;
  const max = Math.max(nr, ng, nb), min = Math.min(nr, ng, nb), delta = max - min;
  let h = 0;
  if (delta !== 0) {
    if (max === nr) h = ((ng - nb) / delta + (ng < nb ? 6 : 0)) * 60;
    else if (max === ng) h = ((nb - nr) / delta + 2) * 60;
    else h = ((nr - ng) / delta + 4) * 60;
  }
  return [h % 360, max === 0 ? 0 : delta / max, max];
}

@Component
export struct ColorWheelPicker {
  onCancel?: () => void;
  @State hue: number = 215;
  @State sat: number = 0.84;
  @State val: number = 1;
  @State hex: string = '#2979FF';
  @State rr: number = 41;
  @State gg: number = 121;
  @State bb: number = 255;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  aboutToAppear(): void {
    this.drawSwatch();
  }

  private drawSwatch(): void {
    const base = hsvToHex(this.hue, 1, 1);
    // 底色（当前色相纯色）
    this.ctx.fillStyle = base;
    this.ctx.fillRect(0, 0, SZ, SZ);
    // 白色渐变（左→右，控制饱和度）
    const hGrad = this.ctx.createLinearGradient(0, 0, SZ, 0);
    hGrad.addColorStop(0, 'rgb(255,255,255)');
    hGrad.addColorStop(1, 'rgba(255,255,255,0)');
    this.ctx.fillStyle = hGrad;
    this.ctx.fillRect(0, 0, SZ, SZ);
    // 黑色渐变（上→下，控制明度）
    const vGrad = this.ctx.createLinearGradient(0, 0, 0, SZ);
    vGrad.addColorStop(0, 'rgba(0,0,0,0)');
    vGrad.addColorStop(1, 'rgb(0,0,0)');
    this.ctx.fillStyle = vGrad;
    this.ctx.fillRect(0, 0, SZ, SZ);
  }

  private updateColor(x: number, y: number): void {
    if (x < 0 || x > SZ || y < 0 || y > SZ) return;
    this.sat = x / SZ;
    this.val = 1 - y / SZ;
    const c = hsvToRgb(this.hue, this.sat, this.val);
    this.rr = c[0]; this.gg = c[1]; this.bb = c[2];
    this.hex = hsvToHex(this.hue, this.sat, this.val);
  }

  build() {
    Column() {
      // 取色盘 Canvas
      Stack() {
        Canvas(this.ctx)
          .width(`${SZ}vp`).height(`${SZ}vp`).borderRadius(12)
          .onReady(() => { this.drawSwatch(); })
          .onTouch((e: TouchEvent) => {
            if ((e.type === TouchType.Down || e.type === TouchType.Move) && e.touches.length > 0) {
              this.updateColor(e.touches[0].x, e.touches[0].y);
            }
          })
          .hitTestBehavior(HitTestMode.Default)
        // 光标
        Circle().width(12).height(12).fill(Color.White).border({ width: 2, color: '#333333' })
          .position({ x: this.sat * SZ - 6, y: (1 - this.val) * SZ - 6 })
      }.width(`${SZ}vp`).height(`${SZ}vp`)

      // 色相滑条
      Row() {
        Text('色相').fontSize(12).fontColor(ThemeColors.textSecondary).width(36)
        Slider({ value: this.hue, min: 0, max: 360, step: 1 })
          .layoutWeight(1).blockColor(this.hex).trackColor('#F0F0F0').selectedColor(this.hex)
          .onChange((v: number) => {
            this.hue = v;
            this.drawSwatch();
            const c = hsvToRgb(this.hue, this.sat, this.val);
            this.rr = c[0]; this.gg = c[1]; this.bb = c[2];
            this.hex = hsvToHex(this.hue, this.sat, this.val);
          })
        Text(`${Math.round(this.hue)}°`).fontSize(12).fontColor(ThemeColors.textSecondary).width(36).textAlign(TextAlign.End)
      }.width(`${SZ}vp`).margin({ top: 12 })
      .hitTestBehavior(HitTestMode.Default)

      // 预览
      Row() {
        Column() {}
          .width(40).height(40).backgroundColor(this.hex).borderRadius(6)
          .border({ width: 1.5, color: '#DDD' })
        Column() {
          Text(this.hex).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary).fontFamily('monospace')
          Text(`R:${this.rr} G:${this.gg} B:${this.bb}`)
            .fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
        }.margin({ left: 10 }).alignItems(HorizontalAlign.Start)
        Blank()
      }.width(`${SZ}vp`).margin({ top: 10 })

      // 确认 / 取消
      Row() {
        Button('取消').height(40).fontSize(15)
          .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary).borderRadius(10)
          .layoutWeight(1)
          .onClick(() => { if (this.onCancel) this.onCancel(); })
        Button('确认').height(40).fontSize(15)
          .backgroundColor(this.hex).fontColor('#FFFFFF').borderRadius(10)
          .layoutWeight(1).margin({ left: 10 })
          .onClick(() => {
            AccentColors.selectCustom(this.hex);
            if (this.onCancel) this.onCancel();
          })
      }.width(`${SZ}vp`).margin({ top: 10 })
    }
    .width(`${SZ}vp`).alignItems(HorizontalAlign.Center)
  }
}
