// ImageCropPage.ets - 图片裁剪页面（全屏）
// 裁剪框固定屏幕中心，图片可双指缩放、单指拖动
// Stack.clip(true) 防止图片溢出到顶栏/底栏
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { router } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

@Entry
@Component
struct ImageCropPage {
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State isReady: boolean = false;

  // 图片原始尺寸 (px)
  private imgW: number = 0;
  private imgH: number = 0;

  // 图片基础显示尺寸 (vp)
  @State baseW: number = 0;
  @State baseH: number = 0;

  // 图片缩放和拖动状态
  @State imgScale: number = 1;
  @State imgTranslateX: number = 0;
  @State imgTranslateY: number = 0;

  // 手势临时状态
  private pinchStartScale: number = 1;
  private panStartTransX: number = 0;
  private panStartTransY: number = 0;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private minScale: number = 1;

  // Stack 实际尺寸（onAreaChange 获取）
  @State stackW: number = 0;
  @State stackH: number = 0;

  // 裁剪框
  @State cropX: number = 0;
  @State cropY: number = 0;
  @State cropW: number = 0;
  @State cropH: number = 0;

  private srcPath: string = '';
  private isTablet: boolean = deviceInfo.deviceType === 'tablet';
  private cropRatio: number = deviceInfo.deviceType === 'tablet' ? 4 / 3 : 3 / 4;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navIndicatorHeight') navIndicatorHeight: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string>;
    if (params && params.path) {
      this.srcPath = params.path;
      this.loadImage();
    }
  }

  async loadImage(): Promise<void> {
    try {
      const src = image.createImageSource(this.srcPath);
      const pm = await src.createPixelMap({ editable: true, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      const info = await pm.getImageInfo();
      this.pixelMap = pm;
      this.imgW = info.size.width;
      this.imgH = info.size.height;
      this.isReady = true;
      // stackW/stackH 由 onAreaChange 设置，如果已有尺寸则立即布局
      if (this.stackW > 0 && this.stackH > 0) {
        this.initLayout();
      }
    } catch (e) {
    }
  }

  initLayout(): void {
    if (this.stackW <= 0 || this.stackH <= 0 || this.imgW <= 0) return;

    // 裁剪框：Stack 中心，按设备比例
    this.cropW = this.stackW * 0.9;
    this.cropH = this.cropW / this.cropRatio;
    if (this.cropH > this.stackH * 0.9) {
      this.cropH = this.stackH * 0.9;
      this.cropW = this.cropH * this.cropRatio;
    }
    this.cropX = (this.stackW - this.cropW) / 2;
    this.cropY = (this.stackH - this.cropH) / 2;

    // 图片基础尺寸：Contain 适配 Stack
    const containScale: number = Math.min(this.stackW / this.imgW, this.stackH / this.imgH);
    this.baseW = this.imgW * containScale;
    this.baseH = this.imgH * containScale;

    // 最小缩放 = 覆盖裁剪框；初始缩放再多 10% 余量
    const coverScaleW: number = this.cropW / this.baseW;
    const coverScaleH: number = this.cropH / this.baseH;
    this.minScale = Math.max(coverScaleW, coverScaleH);
    this.imgScale = this.minScale * 1.1;
    this.imgTranslateX = 0;
    this.imgTranslateY = 0;

  }

  clampTranslate(tx: number, ty: number): void {
    const dispW: number = this.baseW * this.imgScale;
    const dispH: number = this.baseH * this.imgScale;
    const imgLeft: number = (this.stackW - dispW) / 2 + tx;
    const imgTop: number = (this.stackH - dispH) / 2 + ty;
    const minLeft: number = this.cropX + this.cropW - dispW;
    const maxLeft: number = this.cropX;
    const minTop: number = this.cropY + this.cropH - dispH;
    const maxTop: number = this.cropY;
    const clampedLeft: number = Math.max(minLeft, Math.min(imgLeft, maxLeft));
    const clampedTop: number = Math.max(minTop, Math.min(imgTop, maxTop));
    this.imgTranslateX = clampedLeft - (this.stackW - dispW) / 2;
    this.imgTranslateY = clampedTop - (this.stackH - dispH) / 2;
  }

  async confirmCrop(): Promise<void> {
    if (!this.pixelMap) { router.back(); return; }
    try {
      const dispW: number = this.baseW * this.imgScale;
      const dispH: number = this.baseH * this.imgScale;
      const imgLeft: number = (this.stackW - dispW) / 2 + this.imgTranslateX;
      const imgTop: number = (this.stackH - dispH) / 2 + this.imgTranslateY;
      const pxPerVp: number = this.imgW / dispW;
      const cropPxX: number = Math.round((this.cropX - imgLeft) * pxPerVp);
      const cropPxY: number = Math.round((this.cropY - imgTop) * pxPerVp);
      const cropPxW: number = Math.round(this.cropW * pxPerVp);
      const cropPxH: number = Math.round(this.cropH * pxPerVp);

      const safeX: number = Math.max(0, Math.min(cropPxX, this.imgW - cropPxW));
      const safeY: number = Math.max(0, Math.min(cropPxY, this.imgH - cropPxH));
      const safeW: number = Math.min(cropPxW, this.imgW - safeX);
      const safeH: number = Math.min(cropPxH, this.imgH - safeY);


      await this.pixelMap.crop({ x: safeX, y: safeY, size: { width: safeW, height: safeH } });

      const packer = image.createImagePacker();
      const buffer = await packer.packing(this.pixelMap, { format: 'image/jpeg', quality: 90 });
      packer.release();
      const destPath = getContext(this).filesDir + '/class_bg_image.jpg';
      const fd = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(fd.fd, buffer);
      fileIo.closeSync(fd);

      this.pixelMap.release();
      this.pixelMap = undefined;

      AppStorage.setOrCreate('cropped_bg_path', destPath);
      router.back();
    } catch (e) {
      router.back();
    }
  }

  cancel(): void {
    if (this.pixelMap) {
      this.pixelMap.release();
      this.pixelMap = undefined;
    }
    router.back();
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text('取消').fontSize(16).fontColor('#FFFFFF')
          .onClick(() => { this.cancel(); })
        Blank()
        Text('裁剪图片').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        Blank()
        Text('完成').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(this.isReady ? '#FF6B00' : '#666666')
          .onClick(() => { if (this.isReady) { this.confirmCrop(); } })
      }
      .width('100%').height(56 + this.statusBarHeight)
      .padding({ left: 20, right: 20, top: this.statusBarHeight })
      .backgroundColor('#1A1A1C')

      // 裁剪区域
      Stack() {
        if (this.pixelMap && this.isReady && this.stackW > 0) {
          // 图片
          Image(this.pixelMap)
            .width(this.baseW).height(this.baseH)
            .objectFit(ImageFit.Fill)
            .scale({ x: this.imgScale, y: this.imgScale })
            .translate({ x: this.imgTranslateX, y: this.imgTranslateY })

          // 遮罩：上
          Column()
            .width('100%').height(this.cropY)
            .position({ x: 0, y: 0 })
            .backgroundColor('#99000000')
            .hitTestBehavior(HitTestMode.None)
          // 遮罩：下
          Column()
            .width('100%')
            .height(Math.max(0, this.stackH - this.cropY - this.cropH))
            .position({ x: 0, y: this.cropY + this.cropH })
            .backgroundColor('#99000000')
            .hitTestBehavior(HitTestMode.None)
          // 遮罩：左
          Column()
            .width(this.cropX).height(this.cropH)
            .position({ x: 0, y: this.cropY })
            .backgroundColor('#99000000')
            .hitTestBehavior(HitTestMode.None)
          // 遮罩：右
          Column()
            .width(Math.max(0, this.stackW - this.cropX - this.cropW))
            .height(this.cropH)
            .position({ x: this.cropX + this.cropW, y: this.cropY })
            .backgroundColor('#99000000')
            .hitTestBehavior(HitTestMode.None)

          // 裁剪框白色边框
          Column()
            .width(this.cropW).height(this.cropH)
            .position({ x: this.cropX, y: this.cropY })
            .border({ width: 2, color: '#FFFFFF' })
            .hitTestBehavior(HitTestMode.None)

          // 触摸层
          Column()
            .width(this.cropW).height(this.cropH)
            .position({ x: this.cropX, y: this.cropY })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.touchStartX = e.touches[0].x;
                this.touchStartY = e.touches[0].y;
                this.panStartTransX = this.imgTranslateX;
                this.panStartTransY = this.imgTranslateY;
              } else if (e.type === TouchType.Move) {
                const dx: number = e.touches[0].x - this.touchStartX;
                const dy: number = e.touches[0].y - this.touchStartY;
                this.clampTranslate(this.panStartTransX + dx, this.panStartTransY + dy);
              }
            })
            .gesture(
              PinchGesture({ fingers: 2, distance: 5 })
                .onActionStart(() => {
                  this.pinchStartScale = this.imgScale;
                })
                .onActionUpdate((event: GestureEvent) => {
                  const newScale: number = Math.max(this.minScale, Math.min(this.pinchStartScale * event.scale, 10));
                  this.imgScale = newScale;
                  this.clampTranslate(this.imgTranslateX, this.imgTranslateY);
                })
            )
        }
      }
      .width('100%').layoutWeight(1)
      .backgroundColor('#000000')
      .clip(true)
      .onAreaChange((_old: Area, newArea: Area) => {
        const w: number = parseFloat(newArea.width.toString());
        const h: number = parseFloat(newArea.height.toString());
        if (w > 0 && h > 0 && (w !== this.stackW || h !== this.stackH)) {
          this.stackW = w;
          this.stackH = h;
          if (this.isReady) {
            this.initLayout();
          }
        }
      })

      // 底部提示
      Text('双指缩放 · 单指拖动 · 比例已按' + (this.isTablet ? '平板' : '手机') + '课表优化')
        .fontSize(12).fontColor('#999999')
        .height(44 + this.navIndicatorHeight).width('100%').textAlign(TextAlign.Center)
        .padding({ bottom: this.navIndicatorHeight })
        .backgroundColor('#1A1A1C')
    }
    .width('100%').height('100%')
    .backgroundColor('#000000')
  }
}
