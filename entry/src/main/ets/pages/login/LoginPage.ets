// LoginPage.ets — HTTP 原生登录 + 滑块验证码
// 替代 WebView 自动填表方案，消除 Cookie 隔离问题
import { CasLoginService, TrackPoint, SliderPuzzle, PuzzleImages, LoginProgress, CasFormFields } from '../../services/auth/CasLoginService';
import { EhallService } from '../../services/ids/EhallService';
import { UserInfoService } from '../../services/common/UserInfoService';
import { ThemeColors } from '../../utils/ThemeColors';
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SecureStorageUtil, SecureAlias } from '../../utils/SecureStorageUtil';
import { image } from '@kit.ImageKit';

const TAG = 'LoginPage';

@Entry
@Component
struct LoginPage {
  @State username: string = '';
  @State password: string = '';
  @State statusText: string = '';
  @State isSubmitting: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  // 滑块验证码状态
  @State showCaptcha: boolean = false;
  @State jumpToCaptcha: boolean = false;
  @State captchaLoading: boolean = false;
  @State sliderLeftPx: number = 0;

  // 登录流程进度遮罩（加载登录页 → 滑块验证 → 提交登录 → 设备验证 → 登录成功）
  @State loginOverlayVisible: boolean = false;
  @State loginOverlayMsg: string = '';
  @State loginOverlayPercent: number = 0;
  @State captchaError: string = '';
  @State puzzleBigPm: image.PixelMap | null = null;
  @State puzzleSmallPm: image.PixelMap | null = null;

  private cas: CasLoginService = CasLoginService.getInstance();
  private tracks: TrackPoint[] = [];
  private dragStartX: number = 0;
  private lastRecordTime: number = 0;
  private lastTrackA: number = -999;
  private lastTrackB: number = -999;
  private activePointer: number = -1;
  private pieces: PuzzleImages | null = null;
  private readonly RECORD_INTERVAL_MS: number = 20;

  // 二次验证（设备验证）弹窗状态
  @State showReAuth: boolean = false;
  @State reAuthStage: 'send' | 'input' = 'send'; // 'send'=显示获取验证码按钮；'input'=显示输入框
  @State reAuthFactor: number = 3; // 二次验证因子：3=手机短信，4=企业微信（都是收 6 位动态码，默认手机短信，推荐）
  @State reAuthUsername: string = '';
  @State reAuthCode: string = '';
  @State reAuthCountdown: number = 0;
  @State reAuthError: string = '';
  @State reAuthSending: boolean = false;
  @State reAuthSubmitting: boolean = false;
  @State reAuthTrustDevice: boolean = true; // 信任此设备：下次同设备登录免二次验证
  private reAuthResolver: ((ok: boolean) => void) | null = null;
  private reAuthTimer: number = 0;
  private readonly RECORD_DISTANCE_PX: number = 2;
  private readonly THUMB_SIZE: number = 42;
  private readonly dragLimit: number = 240;

  aboutToAppear(): void {
    this.username = PreferenceUtil.getString('ids_account');
    SecureStorageUtil.get(SecureAlias.LOGIN_PASSWORD).then((pwd: string) => { this.password = pwd; });
    // 从已过期入口进入：跳过密码表单，直接走验证码
    try {
      const params = router.getParams() as Record<string, Object>;
      if (params && (params['jumpToCaptcha'] as boolean) === true) {
        this.jumpToCaptcha = true;
        this.statusText = '正在准备验证...';
        setTimeout(() => { this.doLogin(); }, 300);
      }
    } catch (_e) { /* ignore */ }
  }

  // 页面销毁兜底清理 reAuth 倒计时定时器，避免泄漏到后台空转（泄漏②修复）
  aboutToDisappear(): void {
    if (this.reAuthTimer) { clearInterval(this.reAuthTimer); this.reAuthTimer = 0; }
  }

  private formFields: CasFormFields | null = null;
  private captchaSmallBase64: string = '';

  async doLogin(): Promise<void> {
    if (this.username.length === 0) { this.statusText = '请输入学号'; return; }
    if (this.password.length === 0) { this.statusText = '请输入密码'; return; }
    this.statusText = '';
    this.captchaError = '';
    this.isSubmitting = true;
    this.tracks = [];
    this.sliderLeftPx = 0;
    this.formFields = null;
    this.loginOverlayVisible = true;
    this.loginOverlayMsg = '正在加载登录页...';
    this.loginOverlayPercent = 8;

    try {
      const fields: CasFormFields = await this.cas.getLoginPageForm((p: LoginProgress) => {
        this.mapLoginStep(p);
      });

      if (!fields.execution) {
        // 已有有效会话（TGC 恢复等）：确认可登录后才落地账号，避免失败/假账号残留
        this.loginOverlayVisible = false;
        await PreferenceUtil.putString('ids_account', this.username);
        SecureStorageUtil.put(SecureAlias.LOGIN_PASSWORD, this.password).catch(() => {});
        await PreferenceUtil.putBool('is_logged_in', true);
        // 异步抓取 xgxt 用户基本信息
        await this.runXgxtFetch(5000);
        this.statusText = '自动登录成功！';
        setTimeout(() => { router.replaceUrl({ url: 'pages/main/MainPage' }); }, 400);
        return;
      }

      this.formFields = fields;

      // 优先自动过滑块；失败（或异常）再回退手动拖动 UI
      try {
        if (await this.cas.autoSolveSlider()) {
          this.loginOverlayMsg = '正在进行滑块验证...';
          this.loginOverlayPercent = 35;
          const ok: boolean = await this.finishLogin();
          if (ok) {
            return;
          }
        }
      } catch (e) {
        // 登录失败：关闭遮罩，避免一直卡在"正在完成登录跳转"
        this.loginOverlayVisible = false;
        this.isSubmitting = false;
        // 设备验证被用户取消：不要落到手动滑块，回到登录表单让用户重新登录
        const msg: string = String(e);
        if (msg.indexOf('设备验证未完成') >= 0 || msg.indexOf('设备验证') >= 0) {
          this.statusText = '设备验证未完成，请重新登录';
          return;
        }
        this.statusText = msg;
      }

      // 自动滑块失败 → 落到手动拖动滑块 UI
      const puzzle: SliderPuzzle = await this.cas.getSliderCaptcha((p: LoginProgress) => {
        this.mapLoginStep(p);
      });
      this.loginOverlayVisible = false; // 手动滑块 UI 接管
      this.captchaSmallBase64 = puzzle.smallImage;

      const imgs: PuzzleImages = this.cas.getPuzzleImages(puzzle);
      this.pieces = imgs;
      const bigPm: image.PixelMap = await this.bytesToPixelMap(imgs.bigPm);
      const smallPm: image.PixelMap = await this.bytesToPixelMap(imgs.smallPm);
      this.puzzleBigPm = bigPm;
      this.puzzleSmallPm = smallPm;
      this.showCaptcha = true;
      this.statusText = '请拖动滑块完成验证';
      this.isSubmitting = false;
    } catch (e) {
      this.loginOverlayVisible = false;
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
      const verified: boolean = await this.cas.verifySliderCaptcha(this.tracks, this.captchaSmallBase64);
      if (!verified) {
        throw new Error('验证码校验失败');
      }
      this.showCaptcha = false;
      // 滑块关闭后立即恢复登录进度遮罩（对齐 Flutter：遮罩全程存在，避免收尾期空白）
      this.loginOverlayVisible = true;
      this.loginOverlayMsg = '正在登录...';
      this.loginOverlayPercent = 60;
      this.statusText = '正在登录...';
      const ok: boolean = await this.finishLogin();
      if (!ok) {
        this.toForm();
        this.isSubmitting = false;
      }
    } catch (e) {
      const msg: string = String(e);
      // 登录失败：关闭遮罩，避免一直卡在"正在完成登录跳转"
      this.loginOverlayVisible = false;
      this.statusText = msg;
      this.toForm();
      this.isSubmitting = false;
    }
  }

  // 滑块通过后提交登录并完成收尾（自动/手动路径共用）
  private async finishLogin(): Promise<boolean> {
    const fields: CasFormFields | null = this.formFields;
    if (!fields) {
      this.statusText = '登录失败，请重试';
      return false;
    }
    const success: boolean = await this.cas.postLogin(
      this.username,
      this.password,
      fields,
      (p: LoginProgress) => {
        this.mapLoginStep(p);
      },
      (username: string, onProgress?: (p: LoginProgress) => void) => {
        // 设备验证弹窗接管：隐藏登录进度遮罩（弹窗自身负责交互与进度）
        this.loginOverlayVisible = false;
        return this.onReAuthNeeded(username, onProgress);
      }
    );
    if (success) {
      // 关键：保存登录态后立即跳转，非关键操作移到跳转后异步执行，避免网络请求卡住导致一直停在登录页
      await PreferenceUtil.putString('ids_account', this.username);
      SecureStorageUtil.put(SecureAlias.LOGIN_PASSWORD, this.password).catch(() => {});
      EhallService.getInstance().clearSessionCache();
      await PreferenceUtil.putBool('is_logged_in', true);
      this.loginOverlayVisible = true;
      this.loginOverlayMsg = '登录成功';
      this.loginOverlayPercent = 100;
      this.statusText = '登录成功！';
      // 非关键收尾工作：跳转后异步执行，不阻塞登录
      setTimeout(() => {
        this.cas.syncCookiesToWebView().catch(() => {});
        this.cas.checkWhetherPostgraduate().then(() => {
          if (PreferenceUtil.getBool('role')) {
            EhallService.getInstance().getSemesterInfoYjspt().then((sem: string) => {
              PreferenceUtil.putString('yjspt_semester', sem);
            }).catch(() => {});
          }
        }).catch(() => {});
        this.runXgxtFetch(5000).catch(() => {});
      }, 100);
      // 短暂展示「登录成功」后跳转
      setTimeout(() => {
        this.loginOverlayVisible = false;
        router.replaceUrl({ url: 'pages/main/MainPage' });
      }, 500);
    } else {
      this.loginOverlayVisible = false;
      this.statusText = '登录失败，请重试';
    }
    return success;
  }

  // 按阶段映射更友好的中文进度文案（对齐 traintime_pda 分阶段进度）
  private mapLoginStep(p: LoginProgress): void {
    const stepMsg: Record<string, string> = {
      'form': '正在加载登录页...',
      'captcha': '正在进行滑块验证...',
      'verify': '正在进行设备验证...',
      'login': '正在提交登录信息...',
      'redirect': '正在完成登录跳转...',
      'done': '登录成功',
      'error': p.message || '登录遇到问题',
      'device': '正在进行设备验证...'
    };
    this.loginOverlayMsg = stepMsg[p.step] ?? (p.message || '正在登录...');
    this.loginOverlayPercent = p.percent;
  }

  // 首次登录自动拉取个人信息（带超时保护，成功则置标记防止后续误触发）
  private async runXgxtFetch(timeoutMs: number): Promise<void> {
    const controller = UserInfoService.getInstance();
    const fetchPromise = controller.fetchFromEhall(this.username);
    const timeoutPromise = new Promise<boolean>((resolve) => {
      setTimeout(() => resolve(false), timeoutMs);
    });
    const ok: boolean = await Promise.race([fetchPromise, timeoutPromise]);
    if (ok) {
      await PreferenceUtil.putBool('user_info_initialized', true);
    } else {
    }
  }

  toForm(): void {
    this.showCaptcha = false;
    this.captchaLoading = false;
    this.isSubmitting = false;
    if (this.jumpToCaptcha) {
      this.statusText = '正在重新加载验证...';
      setTimeout(() => { this.doLogin(); }, 500);
    }
  }

  resetCaptcha(msg?: string): void {
    this.tracks = [];
    this.sliderLeftPx = 0;
    this.captchaError = msg || '';
    this.isSubmitting = false;
  }

  // 跳转外部链接（隐私政策 / 用户协议在线版，与 AboutPage 同款）
  private openExternal(url: string): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.openLink(url).catch(() => {});
    } catch (_e) {
      // 无法拉起浏览器时忽略
    }
  }

  // 二次验证短信已发送提示：有脱敏手机号则显示「已发送至 138****1234」，对齐 traintime_pda 体验
  private reAuthSentText(): string {
    const phone: string = this.cas.getReAuthPhoneMasked();
    if (phone && phone.length > 0) {
      return '验证码已发送至 ' + phone + '，请输入以完成验证';
    }
    return '验证码已发送至您绑定的手机，请输入以完成验证';
  }

  // 设备验证流程总入口：postLogin 检测到需要 reAuth 时回调。
  // 仅展示弹窗并等待用户驱动（点“获取验证码”→ 点“验证并登录”），resolve(true)=成功，resolve(false)=取消。
  private onReAuthNeeded(username: string, onProgress?: (p: LoginProgress) => void): Promise<boolean> {
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      this.reAuthResolver = resolve;
      this.reAuthUsername = username;
      this.reAuthCode = '';
      this.reAuthError = '';
      this.reAuthStage = 'send';
      this.reAuthCountdown = 0;
      this.reAuthSending = false;
      this.reAuthSubmitting = false;
      this.showReAuth = true;
    });
  }

  private startReAuthCountdown(): void {
    if (this.reAuthTimer) {
      clearInterval(this.reAuthTimer);
      this.reAuthTimer = 0;
    }
    this.reAuthTimer = setInterval(() => {
      if (this.reAuthCountdown > 0) {
        this.reAuthCountdown -= 1;
        if (this.reAuthCountdown === 0) {
          clearInterval(this.reAuthTimer);
          this.reAuthTimer = 0;
        }
      }
    }, 1000) as number;
  }

  // 用户点击“获取验证码”：初始化 reAuth 会话并发送短信
  private async sendReAuthCodeManually(): Promise<void> {
    if (this.reAuthSending || this.reAuthSubmitting) {
      return;
    }
    this.reAuthSending = true;
    this.reAuthError = '';
    try {
      this.cas.setReAuthFactor(this.reAuthFactor);
      await this.cas.startReAuth(this.reAuthUsername);
      this.reAuthStage = 'input';
      this.reAuthCountdown = 120;
      this.startReAuthCountdown();
    } catch (e) {
      this.reAuthError = '获取验证码失败：' + String(e);
    } finally {
      this.reAuthSending = false;
    }
  }

  // 用户点击“验证并登录”：提交验证码并拿登录态
  private async confirmReAuth(): Promise<void> {
    const code: string = this.reAuthCode.trim();
    if (code.length === 0) {
      this.reAuthError = '请输入验证码';
      return;
    }
    if (this.reAuthSubmitting || this.reAuthSending) {
      return;
    }
    this.reAuthSubmitting = true;
    this.reAuthError = '';
    try {
      const ok: boolean = await this.cas.submitReAuth(this.reAuthUsername, code, this.reAuthTrustDevice);
      if (ok) {
        this.showReAuth = false;
        // 弹窗关闭后立即恢复登录进度遮罩（对齐 Flutter：遮罩全程存在，避免收尾期空白）
        this.loginOverlayVisible = true;
        this.loginOverlayMsg = '正在完成登录...';
        this.loginOverlayPercent = 80;
        if (this.reAuthTimer) {
          clearInterval(this.reAuthTimer);
          this.reAuthTimer = 0;
        }
        const resolver = this.reAuthResolver;
        this.reAuthResolver = null;
        if (resolver) {
          resolver(true);
        }
      }
    } catch (e) {
      this.reAuthError = String(e);
    } finally {
      this.reAuthSubmitting = false;
    }
  }

  private cancelReAuth(): void {
    this.showReAuth = false;
    if (this.reAuthTimer) {
      clearInterval(this.reAuthTimer);
      this.reAuthTimer = 0;
    }
    const resolver = this.reAuthResolver;
    this.reAuthResolver = null;
    if (resolver) {
      resolver(false);  // 取消 → postLogin 抛“设备验证未完成”
    }
  }

  private async resendReAuthCode(): Promise<void> {
    if (this.reAuthCountdown > 0) {
      return;
    }
    try {
      await this.cas.sendReAuthCode(this.reAuthUsername);
      this.reAuthCountdown = 120;
      this.startReAuthCountdown();
      this.reAuthError = '';
    } catch (e) {
      this.reAuthError = '重新发送失败，请稍后重试';
    }
  }

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
      const b: number = Math.round(0);
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

  private async bytesToPixelMap(data: Uint8Array): Promise<image.PixelMap> {
    const buffer: ArrayBuffer = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
    const imageSource: image.ImageSource = image.createImageSource(buffer);
    const opts: image.DecodingOptions = { desiredSize: { width: 280, height: 155 } };
    const pm: image.PixelMap = await imageSource.createPixelMap(opts);
    return pm;
  }

  private thumbOffset(): number {
    return Math.max(0, Math.min(this.sliderLeftPx - 1, 280 - this.THUMB_SIZE));
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('登录').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          if (this.isSubmitting && !this.showCaptcha) {
            LoadingProgress().width(24).height(24).color('#2979FF')
          }
        }
        .width('100%').height(56 + this.statusBarHeight).padding({ left: 16, right: 16, top: this.statusBarHeight })
        .backgroundColor(ThemeColors.bgCard)
        .shadow({ radius: 2, color: '#00000010', offsetY: 1 })

        if (this.jumpToCaptcha && !this.showCaptcha) {
          this.buildCaptchaLoading()
        } else {
          this.buildLoginForm()
        }

        Column() {
          Text('请使用统一身份认证账号登录').fontSize(12).fontColor(ThemeColors.textSecondary)
          Text('登录信息仅保存在本设备').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
        }
        // 适配系统导航条：华为要求底部控件抬高避让 >=28vp。
        // Stack 已 expandSafeArea 到底部，此处从屏幕底边起算，48vp 可覆盖常见导航条高度并留足余量。
        .width('100%').padding({ top: 12, bottom: 48 })
        .alignItems(HorizontalAlign.Center).backgroundColor(ThemeColors.bgPage)
      }
      .width('100%').height('100%').backgroundColor(ThemeColors.bgCard)

      // 登录流程进度遮罩（加载登录页 → 滑块验证 → 提交登录 → 设备验证 → 登录成功）
      if (this.loginOverlayVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%').height('100%')
            .backgroundColor(0x66000000)
          Column() {
            LoadingProgress().width(40).height(40).color('#2979FF')
            Text(this.loginOverlayMsg || '请稍候...')
              .fontSize(15).fontColor(ThemeColors.textPrimary).margin({ top: 14 })
              .constraintSize({ maxWidth: '80%' }).textAlign(TextAlign.Center)
            Progress({ value: this.loginOverlayPercent, total: 100, type: ProgressType.Linear })
              .width('70%').height(6).margin({ top: 16 })
              .color('#2979FF').backgroundColor(ThemeColors.bgInput)
            Text(this.loginOverlayPercent + '%')
              .fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 8 })
          }
          .padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%').height('100%')
      }

      if (this.showCaptcha) {
        Stack({ alignContent: Alignment.Center }) {
          // 全屏遮罩层：真正占满屏幕的半透明黑，整数 AARRGGBB 无歧义
          // 0xCC = 80% 不透明度，深色主题下也能明显压暗背景
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(0xCC000000)

          // 滑块验证码卡片（位于遮罩之上）
          Column() {
            Row() {
              Blank()
              Text('✕')
                .fontSize(20).fontColor(ThemeColors.textSecondary)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.toForm(); })
            }.width('100%').margin({ bottom: 16 })

            if (this.isSubmitting) {
              LoadingProgress().width(48).height(48).color('#2979FF').margin({ top: 60, bottom: 60 })
              Text(this.statusText || '请稍候...').fontSize(14).fontColor(ThemeColors.textSecondary)
              Blank()
            } else {
              Stack({ alignContent: Alignment.TopStart }) {
                if (this.puzzleBigPm) {
                  Image(this.puzzleBigPm).width(280).height(155).objectFit(ImageFit.Fill)
                } else {
                  Row().width(280).height(155).backgroundColor('#F5F5F5')
                }
                if (this.puzzleSmallPm) {
                  Image(this.puzzleSmallPm).width(44).height(155).objectFit(ImageFit.Fill)
                    .offset({ x: this.sliderLeftPx, y: 0 })
                }
              }
              .width(280).height(155).borderRadius(4)
              .clip(true).backgroundColor('#F0F0F0')

              Stack({ alignContent: Alignment.TopStart }) {
                Row().width(280).height(10).backgroundColor('#E0E0E0').borderRadius(5)
                Row().width(Math.min(this.sliderLeftPx + 4, 280)).height(10)
                  .backgroundColor('#4CAF50').borderRadius(5)
                Row() {
                  Text('→').fontSize(18).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                }
                .width(this.THUMB_SIZE).height(this.THUMB_SIZE)
                .borderRadius(21).backgroundColor('#4CAF50')
                .justifyContent(FlexAlign.Center)
                .shadow({ radius: 6, color: '#00000030', offsetY: 2 })
                .offset({ x: this.thumbOffset(), y: -16 })
              }
              .width(280).height(this.THUMB_SIZE + 10).margin({ top: 33 })
              .hitTestBehavior(HitTestMode.Default)
              .onTouch((event: TouchEvent) => { this.handleTouch(event); })

              if (this.captchaError.length > 0) {
                Text(this.captchaError).fontSize(13).fontColor('#C62828').margin({ top: 12 })
              }
              Text(this.statusText || '请按住滑块拖动到合适位置').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 16 })
            }
          }
          .width(320).padding(20)
          .backgroundColor(ThemeColors.bgCard).borderRadius(16)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%').height('100%')
      }

      if (this.showReAuth) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(0xCC000000)

          Column() {
            Row() {
              Text('设备验证').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              Blank()
              Text('✕')
                .fontSize(20).fontColor(ThemeColors.textSecondary)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.cancelReAuth(); })
            }.width('100%').margin({ bottom: 4 })

            Text(this.reAuthStage === 'send'
              ? '为保障账号安全，本次登录需要验证此设备'
              : (this.reAuthFactor === 4 ? '验证码已发送至您的企业微信，请输入以完成验证' : this.reAuthSentText()))
              .fontSize(13).fontColor(ThemeColors.textSecondary)
              .width('100%').margin({ bottom: 18 })

            Text('验证方式').fontSize(13).fontColor(ThemeColors.textSecondary)
              .width('100%').margin({ bottom: 8 })
            Row() {
              Button('企业微信')
                .layoutWeight(1).height(40).fontSize(13)
                .fontColor(this.reAuthFactor === 4 ? '#FFFFFF' : ThemeColors.textSecondary)
                .backgroundColor(this.reAuthFactor === 4 ? '#2979FF' : ThemeColors.bgInput)
                .borderRadius(8).enabled(!this.reAuthSending && this.reAuthCountdown === 0)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.reAuthFactor = 4; })
              Button('手机短信（推荐）')
                .layoutWeight(1).height(40).fontSize(13)
                .fontColor(this.reAuthFactor === 3 ? '#FFFFFF' : ThemeColors.textSecondary)
                .backgroundColor(this.reAuthFactor === 3 ? '#2979FF' : ThemeColors.bgInput)
                .borderRadius(8).enabled(!this.reAuthSending && this.reAuthCountdown === 0)
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.reAuthFactor = 3; })
            }.width('100%').margin({ bottom: 18 }).justifyContent(FlexAlign.SpaceBetween)

            Row() {
              Toggle({ type: ToggleType.Checkbox, isOn: this.reAuthTrustDevice })
                .size({ width: 18, height: 18 })
                .onChange((isOn: boolean) => { this.reAuthTrustDevice = isOn; })
              Text('信任此设备（下次登录免验证）')
                .fontSize(13).fontColor(ThemeColors.textSecondary)
                .margin({ left: 8 })
                .hoverEffect(HoverEffect.Auto).onClick(() => { this.reAuthTrustDevice = !this.reAuthTrustDevice; })
            }.width('100%').margin({ bottom: 14 }).alignItems(VerticalAlign.Center)

            Row() {
              TextInput({ placeholder: '请输入 6 位验证码', text: this.reAuthCode })
                .layoutWeight(1).height(48).fontSize(16).type(InputType.Number)
                .backgroundColor(ThemeColors.bgInput).borderRadius(8).padding({ left: 16, right: 16 })
                .onChange((value: string) => { this.reAuthCode = value; })
              Button(this.reAuthCountdown > 0
                ? `${this.reAuthCountdown}s`
                : (this.reAuthSending ? '发送中' : (this.reAuthStage === 'send' ? '获取验证码' : '重新发送')))
                .width(112).height(48).fontSize(14)
                .fontColor(this.reAuthCountdown > 0 ? ThemeColors.textSecondary : '#FFFFFF')
                .backgroundColor(this.reAuthCountdown > 0 ? ThemeColors.bgInput : '#2979FF')
                .borderRadius(8)
                .enabled(this.reAuthCountdown === 0 && !this.reAuthSending)
                .hoverEffect(HoverEffect.Auto).onClick(() => {
                  if (this.reAuthStage === 'send') { this.sendReAuthCodeManually(); }
                  else { this.resendReAuthCode(); }
                })
            }.width('100%').margin({ bottom: 18 })

            Button(this.reAuthSubmitting ? '验证中...' : '验证并登录')
              .width('100%').height(46).fontSize(16).fontColor('#FFFFFF')
              .backgroundColor(this.reAuthSubmitting ? '#90CAF9' : '#2979FF').borderRadius(8)
              .enabled(!this.reAuthSubmitting)
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.confirmReAuth(); })

            if (this.reAuthError.length > 0) {
              Text(this.reAuthError).fontSize(13).fontColor('#C62828').margin({ top: 12 }).width('100%')
            }
          }
          .width(320).padding(20)
          .backgroundColor(ThemeColors.bgCard).borderRadius(16)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%').height('100%')
      }
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder buildLoginForm() {
    Column() {
      Image($r('app.media.icon'))
        .width(96).height(96).borderRadius(20).objectFit(ImageFit.Contain)
        .margin({ bottom: 24 })
        .alignSelf(ItemAlign.Center)
        .shadow({ radius: 12, color: '#0000001A', offsetY: 4 })
      Column() {
        Text('统一身份认证').fontSize(24).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .margin({ bottom: 8 })
        Text('输入学号和密码进行登录').fontSize(14).fontColor(ThemeColors.textSecondary)
          .margin({ bottom: 32 })
      }
      .width('100%').alignItems(HorizontalAlign.Start)

      Row() {
        TextInput({ placeholder: '请输入学号', text: this.username })
          .width('100%').height(48).fontSize(16)
          .type(InputType.Normal)
          .placeholderColor(ThemeColors.textSecondary)
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .padding({ left: 16, right: 16 })
          .id('login_username_input')
          .onChange((value: string) => { this.username = value; })
      }.width('100%')

      Row() {
        TextInput({ placeholder: '请输入密码', text: this.password })
          .width('100%').height(48).fontSize(16)
          .type(InputType.Password)
          .placeholderColor(ThemeColors.textSecondary)
          .backgroundColor(ThemeColors.bgInput).borderRadius(8)
          .padding({ left: 16, right: 16 })
          .cancelButton({ style: CancelButtonStyle.INVISIBLE })
          .id('login_password_input')
          .onChange((value: string) => { this.password = value; })
      }
      .width('100%').margin({ top: 16 })

      Button(this.isSubmitting ? '正在加载...' : '登录')
        .width('100%').height(48).fontSize(16).fontColor('#FFFFFF')
        .backgroundColor(this.isSubmitting ? '#90CAF9' : '#2979FF').borderRadius(8)
        .margin({ top: 32 })
        .enabled(!this.isSubmitting)
        .id('login_submit_button')
        .hoverEffect(HoverEffect.Auto).onClick(() => this.doLogin())

      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(13)
          .fontColor(this.statusText.indexOf('失败') >= 0 || this.statusText.indexOf('错') >= 0 ?
            '#C62828' : '#666666')
          .margin({ top: 16 })
      }

      Text('账号密码仅保存在本设备，不会上传至任何服务器').fontSize(12).fontColor(ThemeColors.textSecondary)
        .margin({ top: 24 })

      // 隐私政策 / 用户协议入口（与首次启动门禁弹窗一致，可随时查阅）
      Row() {
        Text('《用户协议》')
          .fontSize(12).fontColor('#2979FF')
          .hoverEffect(HoverEffect.Auto).onClick(() => this.openExternal('https://hixdapp.cn/user-agreement.html'))
        Text('|')
          .fontSize(12).fontColor(ThemeColors.textSecondary)
          .margin({ left: 12, right: 12 })
        Text('《隐私政策》')
          .fontSize(12).fontColor('#2979FF')
          .hoverEffect(HoverEffect.Auto).onClick(() => this.openExternal('https://hixdapp.cn/privacy.html'))
      }
      .margin({ top: 14 })
    }
    .width('100%').layoutWeight(1)
    .padding({ left: 32, right: 32, top: 48 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(ThemeColors.bgCard)
  }

  @Builder buildCaptchaLoading() {
    Column() {
      LoadingProgress().width(48).height(48).color('#2979FF')
      Text(this.statusText || '正在准备验证...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 16 })
    }
    .width('100%').layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.bgCard)
  }
}
