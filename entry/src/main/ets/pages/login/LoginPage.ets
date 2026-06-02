// LoginPage.ets — HTTP 原生登录 + 滑块验证码
// 替代 WebView 自动填表方案，消除 Cookie 隔离问题
import { CasLoginService, TrackPoint, SliderPuzzle, PuzzleImages, LoginProgress, CasFormFields } from '../../services/CasLoginService';
import { EhallService } from '../../services/EhallService';
import { ThemeColors } from '../../utils/ThemeColors';
import { router } from '@kit.ArkUI';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { image } from '@kit.ImageKit';

const TAG = 'LoginPage';

@Entry
@Component
struct LoginPage {
  // ===== 表单状态 =====
  @State username: string = '';
  @State password: string = '';
  @State passwordVisible: boolean = false;
  @State statusText: string = '';
  @State isSubmitting: boolean = false;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  // ===== 滑块状态 =====
  @State showCaptcha: boolean = false;
  @State captchaLoading: boolean = false;
  @State sliderLeftPx: number = 0;
  @State captchaError: string = '';
  @State puzzleBigPm: PixelMap | null = null;
  @State puzzleSmallPm: PixelMap | null = null;

  // ===== 内部变量 =====
  private cas: CasLoginService = CasLoginService.getInstance();
  private tracks: TrackPoint[] = [];
  private dragStartX: number = 0;
  private lastRecordTime: number = 0;
  private lastTrackA: number = -999;
  private lastTrackB: number = -999;
  private activePointer: number = -1;
  private pieces: PuzzleImages | null = null;
  private readonly RECORD_INTERVAL_MS: number = 20;
  private readonly RECORD_DISTANCE_PX: number = 2;
  private readonly THUMB_SIZE: number = 42;
  private readonly dragLimit: number = 240; // PUZZLE_WIDTH - SLIDER_RIGHT_PADDING = 280-40

  aboutToAppear(): void {
    if (PreferenceUtil.getBool('is_logged_in')) {
      this.statusText = '检测到已保存的登录状态，正在验证...';
      setTimeout(() => { router.replaceUrl({ url: 'pages/MainPage' }); }, 500);
      return;
    }
    this.username = PreferenceUtil.getString('login_username');
    this.password = PreferenceUtil.getString('login_password');
    const autoLogin: boolean = PreferenceUtil.getBool('auto_login_next');
    if (autoLogin) {
      PreferenceUtil.putBool('auto_login_next', false);
      if (this.username.length > 0 && this.password.length > 0) {
        setTimeout(() => { this.doLogin(); }, 300);
      }
    }
  }

  // ===== 登录流程 =====
  private formFields: CasFormFields | null = null;
  private captchaSmallBase64: string = '';

  async doLogin(): Promise<void> {
    if (this.username.length === 0) { this.statusText = '请输入学号'; return; }
    if (this.password.length === 0) { this.statusText = '请输入密码'; return; }
    PreferenceUtil.putString('login_username', this.username);
    PreferenceUtil.putString('login_password', this.password);
    this.statusText = '';
    this.captchaError = '';
    this.isSubmitting = true;
    this.tracks = [];
    this.sliderLeftPx = 0;
    this.formFields = null;

    try {
      // Step 1-2: 获取登录表单 + 验证码图片
      const fields: CasFormFields = await this.cas.getLoginPageForm((p: LoginProgress) => {
        this.statusText = p.message;
      });

      // TGC 有效 → CAS 直接 302 到 ehall，没有登录表单
      if (!fields.execution) {
        await PreferenceUtil.putBool('is_logged_in', true);
        PreferenceUtil.putNumber('auto_login_attempts', 0);
        this.statusText = '自动登录成功！';
        setTimeout(() => { router.replaceUrl({ url: 'pages/MainPage' }); }, 400);
        return;
      }

      this.formFields = fields;

      const puzzle: SliderPuzzle = await this.cas.getSliderCaptcha((p: LoginProgress) => {
        this.statusText = p.message;
      });
      this.captchaSmallBase64 = puzzle.smallImage;

      // 解码图片
      const imgs: PuzzleImages = this.cas.getPuzzleImages(puzzle);
      this.pieces = imgs;
      const bigPm: PixelMap = await this.bytesToPixelMap(imgs.bigPm);
      const smallPm: PixelMap = await this.bytesToPixelMap(imgs.smallPm);
      this.puzzleBigPm = bigPm;
      this.puzzleSmallPm = smallPm;
      this.showCaptcha = true;
      this.statusText = '请拖动滑块完成验证';
      this.isSubmitting = false;
    } catch (e) {
      this.statusText = '加载失败：' + String(e);
      this.isSubmitting = false;
    }
  }

  async doSubmit(): Promise<void> {
    if (this.tracks.length === 0) {
      this.captchaError = '请拖动滑块';
      return;
    }
    if (!this.formFields) {
      this.captchaError = '表单数据丢失，请重试';
      return;
    }

    this.isSubmitting = true;
    this.captchaError = '';
    this.statusText = '正在验证...';

    try {
      // Step 3: 验证滑块轨迹（不再重新拉表单和验证码）
      const verified: boolean = await this.cas.verifySliderCaptcha(this.tracks, this.captchaSmallBase64);
      if (!verified) {
        throw new Error('验证码校验失败');
      }

      // Step 4: POST 登录
      this.statusText = '正在登录...';
      const success: boolean = await this.cas.postLogin(
        this.username,
        this.password,
        this.formFields,
        (p: LoginProgress) => { this.statusText = p.message; }
      );

      if (success) {
        await PreferenceUtil.putBool('is_logged_in', true);
        PreferenceUtil.putNumber('auto_login_attempts', 0);
        EhallService.getInstance().clearSessionCache();
        await this.cas.syncCookiesToWebView();
        this.statusText = '登录成功！';
        setTimeout(() => { router.replaceUrl({ url: 'pages/MainPage' }); }, 400);
      } else {
        this.statusText = '登录失败，请重试';
        this.toForm();
      }
    } catch (e) {
      const msg: string = String(e);
      this.statusText = msg;
      this.toForm();  // 不管什么错误都回到表单，不再重试
      this.isSubmitting = false;
    }
  }

  toForm(): void {
    this.showCaptcha = false;
    this.captchaLoading = false;
    this.isSubmitting = false;
  }

  resetCaptcha(msg?: string): void {
    this.tracks = [];
    this.sliderLeftPx = 0;
    this.captchaError = msg || '';
    this.isSubmitting = false;
  }

  // ========== 滑块触摸处理 ==========
  private handleTouch(event: TouchEvent): void {
    if (this.isSubmitting) { return; }

    if (event.type === TouchType.Down) {
      const touch: TouchObject = event.touches[0];
      this.activePointer = touch.id;
      this.dragStartX = touch.x;
      this.lastRecordTime = Date.now();
      this.tracks = [{ a: 0, b: 0, c: 0 }];
      this.lastTrackA = 0;
      this.lastTrackB = 0;
      this.captchaError = '';
    } else if (event.type === TouchType.Move) {
      const touch: TouchObject | undefined = event.touches.find((t: TouchObject) => t.id === this.activePointer);
      if (!touch) { return; }
      const dx: number = touch.x - this.dragStartX;
      if (dx < 0 || dx > this.dragLimit) { return; }
      this.sliderLeftPx = dx;
      const now: number = Date.now();
      const elapsed: number = now - this.lastRecordTime;
      if (elapsed < this.RECORD_INTERVAL_MS) { return; }
      const a: number = Math.round(dx);
      const b: number = Math.round(0); // y抖动忽略（简单化）
      const dist: number = (a - this.lastTrackA) * (a - this.lastTrackA) + (b - this.lastTrackB) * (b - this.lastTrackB);
      if (dist < this.RECORD_DISTANCE_PX * this.RECORD_DISTANCE_PX) { return; }
      this.tracks.push({ a: a, b: b, c: elapsed });
      this.lastTrackA = a;
      this.lastTrackB = b;
      this.lastRecordTime = now;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.activePointer = -1;
      if (event.type === TouchType.Up && this.tracks.length > 0) {
        const finalDx: number = this.sliderLeftPx;
        this.tracks.push({ a: Math.round(finalDx), b: 0, c: Date.now() - this.lastRecordTime });
        this.doSubmit();
      }
    }
  }

  // ========== 工具方法 ==========
  private async bytesToPixelMap(data: Uint8Array): Promise<PixelMap> {
    const buffer: ArrayBuffer = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    const imageSource: image.ImageSource = image.createImageSource(buffer as ArrayBuffer);
    const opts: image.DecodingOptions = { desiredSize: { width: 280, height: 155 } };
    const pm: image.PixelMap = await imageSource.createPixelMap(opts);
    return pm;
  }

  private thumbOffset(): number {
    return Math.max(0, Math.min(this.sliderLeftPx - 1, 280 - this.THUMB_SIZE));
  }

  // ========== UI ==========
  build() {
    Column() {
      // 标题栏
      Row() {
        Text('登录').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        Blank()
        if (this.isSubmitting && !this.showCaptcha) {
          LoadingProgress().width(24).height(24).color('#2979FF')
        }
      }
      .width('100%').height(56).padding({ left: 16, right: 16 })
      .backgroundColor(ThemeColors.bgCard)
      .shadow({ radius: 2, color: '#00000010', offsetY: 1 })

      if (!this.showCaptcha) {
        // ===== 账号密码表单 =====
        this.buildLoginForm()
      } else {
        // ===== 滑块验证码 =====
        this.buildCaptcha()
      }

      // 底部提示
      Column() {
        Text('请使用统一身份认证账号登录').fontSize(12).fontColor(ThemeColors.textSecondary)
        Text('登录信息仅保存在本设备').fontSize(11).fontColor('#BBBBBB').margin({ top: 4 })
      }
      .width('100%').padding({ top: 12, bottom: 20 })
      .alignItems(HorizontalAlign.Center).backgroundColor(ThemeColors.bgPage)
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgCard)
  }

  @Builder buildLoginForm() {
    Column() {
      Column() {
        Text('西电统一身份认证').fontSize(24).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .margin({ bottom: 8 })
        Text('输入学号和密码进行登录').fontSize(14).fontColor(ThemeColors.textSecondary)
          .margin({ bottom: 32 })
      }
      .width('100%').alignItems(HorizontalAlign.Start)

      // 学号
      Row() {
        TextInput({ placeholder: '请输入学号', text: this.username })
          .width('100%').height(48).fontSize(16)
          .type(InputType.Normal)
          .placeholderColor('#CCCCCC')
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => { this.username = value; })
      }.width('100%')

      // 密码
      Row() {
        TextInput({ placeholder: '请输入密码', text: this.password })
          .width('100%').height(48).fontSize(16)
          .type(InputType.Password)
          .placeholderColor('#CCCCCC')
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .padding({ left: 16, right: 16 })
          .cancelButton({ style: CancelButtonStyle.INVISIBLE })
          .onChange((value: string) => { this.password = value; })
      }
      .width('100%').margin({ top: 16 })

      // 登录按钮
      Button(this.isSubmitting ? '正在加载...' : '登录')
        .width('100%').height(48).fontSize(16).fontColor('#FFFFFF')
        .backgroundColor(this.isSubmitting ? '#90CAF9' : '#2979FF').borderRadius(8)
        .margin({ top: 32 })
        .enabled(!this.isSubmitting)
        .onClick(() => this.doLogin())

      // 状态/错误提示
      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(13)
          .fontColor(this.statusText.indexOf('失败') >= 0 || this.statusText.indexOf('误') >= 0 ?
            '#FF6B6B' : '#666666')
          .margin({ top: 16 })
      }

      // 隐私说明
      Text('账号密码仅保存在本设备，不会上传至任何服务器').fontSize(12).fontColor('#BBBBBB')
        .margin({ top: 24 })
    }
    .width('100%').layoutWeight(1)
    .padding({ left: 32, right: 32, top: 48 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(ThemeColors.bgCard)
  }

  @Builder buildCaptcha() {
    Column() {
      if (this.isSubmitting) {
        LoadingProgress().width(48).height(48).color('#2979FF').margin({ top: 60, bottom: 60 })
        Text(this.statusText || '请稍候...').fontSize(14).fontColor(ThemeColors.textSecondary)
        Blank()
      } else {
        // 验证码图片区域
        Stack({ alignContent: Alignment.TopStart }) {
          // 背景大图
          if (this.puzzleBigPm) {
            Image(this.puzzleBigPm).width(280).height(155).objectFit(ImageFit.Fill)
          } else {
            Row().width(280).height(155).backgroundColor('#F5F5F5')
          }
          // 滑块小片
          if (this.puzzleSmallPm) {
            Image(this.puzzleSmallPm).width(44).height(155).objectFit(ImageFit.Fill)
              .offset({ x: this.sliderLeftPx, y: 0 })
          }
        }
        .width(280).height(155).borderRadius(4)
        .clip(true)
        .backgroundColor('#F0F0F0')

        // 滑块拖动区域
        Stack({ alignContent: Alignment.TopStart }) {
          // 滑轨背景
          Row().width(280).height(10).backgroundColor('#E0E0E0').borderRadius(5)

          // 已滑过区域
          Row().width(Math.min(this.sliderLeftPx + 4, 280)).height(10)
            .backgroundColor('#4CAF50').borderRadius(5)

          // 拖动圆钮
          Row() {
            // 箭头图标
            Text('→').fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
          }
          .width(this.THUMB_SIZE).height(this.THUMB_SIZE)
          .borderRadius(21)
          .backgroundColor('#4CAF50')
          .justifyContent(FlexAlign.Center)
          .shadow({ radius: 6, color: '#00000030', offsetY: 2 })
          .offset({ x: this.thumbOffset(), y: -16 }) // 圆钮在滑轨上方
        }
        .width(280).height(this.THUMB_SIZE + 10)
        .margin({ top: 33 })
        .hitTestBehavior(HitTestMode.Default)
        .onTouch((event: TouchEvent) => { this.handleTouch(event); })

        // 错误提示
        if (this.captchaError.length > 0) {
          Text(this.captchaError).fontSize(13).fontColor('#FF6B6B').margin({ top: 12 })
        }

        // 状态文字
        Text(this.statusText || '请按住滑块拖动到最右端').fontSize(12).fontColor('#999999').margin({ top: 16 })

        // 返回按钮
        Button('返回修改账号')
          .fontSize(13).fontColor('#2979FF').backgroundColor(Color.Transparent)
          .margin({ top: 8 })
          .onClick(() => { this.toForm(); })
      }

      Blank()
    }
    .width('100%').layoutWeight(1)
    .padding({ top: 32 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.bgCard)
  }
}