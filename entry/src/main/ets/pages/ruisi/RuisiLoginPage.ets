// RuisiLoginPage.ets — 睿思论坛登录页
// 对标 Flutter login_page.dart：用户名 + 密码 + 验证码（按需显示）
// 验证码流程：1.获取hash → 2.获取update token → 3.获取图片二进制

import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { RuisiService } from '../../services/RuisiService';
import { RuisiApiService } from '../../services/RuisiApiService';
import { RuisiConstants } from '../../services/RuisiModels';
import { ToastUtil } from '../../utils/ToastUtil';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'RuisiLoginPage';

@Component
export struct RuisiLoginPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageLink('ruisi_logged_in') isLoggedIn: boolean = false;
  pageInfo: NavPathStack = new NavPathStack();

  @State username: string = '';
  @State password: string = '';
  @State captchaText: string = '';
  @State captchaImage: PixelMap | null = null;
  @State captchaHash: string = '';
  @State loginhash: string = '';
  @State formhash: string = '';
  @State needCaptcha: boolean = false;       // 是否需要验证码
  @State captchaLoading: boolean = false;     // 验证码图片加载中
  @State loginLoading: boolean = false;       // 登录请求中
  @State errorMsg: string = '';               // 错误信息

  aboutToAppear(): void {
    // 预加载保存的用户名
    const saved = PreferenceUtil.getString('ruisi_username');
    if (saved.length > 0) this.username = saved;
    // 检查是否需要验证码
    this.checkLoginCaptcha();
  }

  /// 对标 Flutter _checkLoginCaptcha：获取登录页，提取 seccodehash
  async checkLoginCaptcha(): Promise<void> {
    try {
      const api = RuisiApiService.getInstance();
      const info = await api.getLoginPageInfo();
      this.formhash = info.formhash;
      this.loginhash = info.loginhash;
      this.captchaHash = info.seccodehash;

      if (info.seccodehash.length > 0) {
        this.needCaptcha = true;
        await this.loadCaptchaImage();
      } else {
        // 也尝试从 updateseccode JS 中提取
        const hash = await this.fetchCaptchaHashFromHtml();
        if (hash.length > 0) {
          this.captchaHash = hash;
          this.needCaptcha = true;
          await this.loadCaptchaImage();
        } else {
          this.needCaptcha = false;
        }
      }
    } catch (e) {
      hilog.error(0xFF00, TAG, 'checkLoginCaptcha failed: ' + JSON.stringify(e));
      this.errorMsg = '获取登录信息失败';
    }
  }

  /// 从登录页 HTML 中通过 updateseccode('HASH') 提取 seccodehash
  /// 对标 Flutter 方式2: RegExp(r"updateseccode\('(\w+)'")
  async fetchCaptchaHashFromHtml(): Promise<string> {
    try {
      const svc = RuisiService.getInstance();
      const resp = await svc.get(`${RuisiConstants.BASE_URL}/member.php?mod=logging&action=login`);
      if (!resp || !resp.isOk || resp.body.length === 0) return '';
      const html = resp.body;
      // 方式1: <input name="seccodehash" value="HASH" />
      const inputMatch = html.match(/name=["']seccodehash["']\s+value=["'](\w+)["']/i);
      if (inputMatch) return inputMatch[1];
      // 方式2: updateseccode('HASH', ...)
      const jsMatch = html.match(/updateseccode\(['"](\w+)['"]/i);
      if (jsMatch) return jsMatch[1];
      return '';
    } catch {
      return '';
    }
  }

  /// 对标 Flutter fetchCaptchaImage：两步获取验证码图片
  /// 1. GET misc.php?mod=seccode&action=update&idhash={hash} → 解析 update('token')
  /// 2. GET misc.php?mod=seccode&update={token}&idhash={hash} → 图片二进制
  async loadCaptchaImage(): Promise<void> {
    if (!this.captchaHash) return;
    this.captchaLoading = true;
    this.captchaImage = null;
    try {
      const svc = RuisiService.getInstance();
      const hash = this.captchaHash;
      const baseUrl = RuisiConstants.BASE_URL;

      // 步骤1：获取 update token
      // Discuz seccode update 响应格式（inajax=1）：XML 包裹的 HTML，含 update('token')
      // 不加 inajax=1 时可能直接返回图片
      const updateUrl = `${baseUrl}/misc.php?mod=seccode&action=update&idhash=${encodeURIComponent(hash)}&inajax=1&${Date.now()}`;
      const updateResp = await svc.get(updateUrl, { 'Referer': `${baseUrl}/member.php?mod=logging&action=login` });
      let updateToken = '';
      if (updateResp && updateResp.isOk && updateResp.body.length > 0) {
        const body = updateResp.body;
        // 尝试多种正则：update('token'), update("token"), updateseccode('token')
        const m1 = body.match(/update\(['"](\w+)['"]/i);
        if (m1) {
          updateToken = m1[1];
        } else {
          // Discuz 有时返回 <root><![CDATA[<script>updateseccode('hash', '...');</script>]]></root>
          // update token 可能在 misc.php?mod=seccode&update=TOKEN 中
          const m2 = body.match(/mod=seccode&update=([^&"'<]+)/i);
          if (m2) updateToken = m2[1];
        }
      }

      // 步骤2：获取图片二进制
      // 如果 update token 为空，Discuz 也接受直接请求 misc.php?mod=seccode&update=0&idhash=hash
      const safeToken = updateToken || '0';
      const imgUrl = `${baseUrl}/misc.php?mod=seccode&update=${encodeURIComponent(safeToken)}&idhash=${encodeURIComponent(hash)}`;
      const data = await svc.getRaw(imgUrl, { 'Referer': `${baseUrl}/` });
      if (data && data.byteLength > 0) {
        const imgSrc = image.createImageSource(data);
        this.captchaImage = await imgSrc.createPixelMap();
      } else {
        hilog.error(0xFF00, TAG, 'captcha image data empty');
      }
    } catch (e) {
      hilog.error(0xFF00, TAG, 'loadCaptchaImage failed: ' + JSON.stringify(e));
    } finally {
      this.captchaLoading = false;
    }
  }

  /// 刷新验证码（点击图片时）
  async refreshCaptcha(): Promise<void> {
    this.captchaText = '';
    await this.loadCaptchaImage();
  }

  async doLogin(): Promise<void> {
    this.errorMsg = '';
    if (this.username.length === 0) {
      this.errorMsg = '请输入用户名';
      return;
    }
    if (this.password.length === 0) {
      this.errorMsg = '请输入密码';
      return;
    }
    if (this.needCaptcha && this.captchaText.length === 0) {
      this.errorMsg = '请输入验证码';
      return;
    }

    this.loginLoading = true;
    try {
      const api = RuisiApiService.getInstance();
      const result = await api.login(
        this.username,
        this.password,
        this.formhash,
        this.loginhash,
        this.needCaptcha ? this.captchaText : undefined,
        this.needCaptcha ? this.captchaHash : undefined
      );

      if (result.success) {
        ToastUtil.show('登录成功');
        this.isLoggedIn = true;
      } else {
        this.errorMsg = result.message;
        // 验证码错误 → 刷新验证码
        if (this.needCaptcha) {
          this.captchaText = '';
          await this.refreshCaptcha();
        }
      }
    } catch (e) {
      this.errorMsg = '登录失败: ' + String(e);
    } finally {
      this.loginLoading = false;
    }
  }

  build() {
    Column() {
      // 标题栏由 RuisiPage 统一绘制，这里直接从表单区开始
      // 表单区（可滚动，对标 Flutter SingleChildScrollView）
      Scroll() {
        Column() {
          // Logo
          Column() {
            Text('💬')
              .fontSize(48)
              .margin({ bottom: 8 })
          }
          .width('100%')
          .margin({ top: 32, bottom: 24 })

          // 用户名
          TextInput({ text: this.username, placeholder: '用户名' })
            .type(InputType.Normal)
            .fontSize(16)
            .fontColor(ThemeColors.textPrimary)
            .backgroundColor(ThemeColors.bgInput)
            .borderRadius(12)
            .height(50)
            .width('100%')
            .onChange((val: string) => { this.username = val; })

          // 密码
          TextInput({ text: this.password, placeholder: '密码' })
            .type(InputType.Password)
            .fontSize(16)
            .fontColor(ThemeColors.textPrimary)
            .backgroundColor(ThemeColors.bgInput)
            .borderRadius(12)
            .height(50)
            .width('100%')
            .margin({ top: 16 })
            .onChange((val: string) => { this.password = val; })

          // 验证码（仅 needCaptcha 时显示）
          // 对标 Flutter: if (_captchaRequired) Row(TextField + GestureDetector<Image>)
          if (this.needCaptcha) {
            Row() {
              TextInput({ text: this.captchaText, placeholder: '验证码' })
                .type(InputType.Normal)
                .fontSize(16)
                .fontColor(ThemeColors.textPrimary)
                .backgroundColor(ThemeColors.bgInput)
                .borderRadius(12)
                .height(50)
                .layoutWeight(1)
                .onChange((val: string) => { this.captchaText = val; })

              // 验证码图片（可点击刷新）
              Row() {
                if (this.captchaLoading) {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                    .color(this.accentColor)
                } else if (this.captchaImage) {
                  Image(this.captchaImage)
                    .width(100)
                    .height(40)
                    .objectFit(ImageFit.Contain)
                } else {
                  Text('点击刷新')
                    .fontSize(12)
                    .fontColor(ThemeColors.textHint)
                }
              }
              .width(108)
              .height(50)
              .margin({ left: 12 })
              .borderRadius(8)
              .backgroundColor(ThemeColors.bgInput)
              .justifyContent(FlexAlign.Center)
              .onClick(() => { this.refreshCaptcha(); })
            }
            .width('100%')
            .margin({ top: 16 })
          }

          // 错误信息
          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(13)
              .fontColor('#C62828')
              .margin({ top: 12 })
              .width('100%')
          }

          // 登录按钮
          Button(this.loginLoading ? '' : '登录')
            .width('100%')
            .height(50)
            .backgroundColor(this.accentColor)
            .fontColor('#FFFFFF')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .borderRadius(12)
            .margin({ top: 24 })
            .enabled(!this.loginLoading)
            .onClick(() => { this.doLogin(); })

          if (this.loginLoading) {
            LoadingProgress()
              .width(24)
              .height(24)
              .color('#FFFFFF')
              .position({ x: '50%', y: '50%' })
              .markAnchor({ x: '50%', y: '50%' })
          }

          // 重置登录状态按钮
          Text('重置登录状态')
            .fontSize(14)
            .fontColor(ThemeColors.textSecondary)
            .margin({ top: 16 })
            .onClick(() => {
              RuisiService.getInstance().clearCookies().then(() => {
                this.isLoggedIn = false;
                this.needCaptcha = false;
                this.captchaImage = null;
                this.captchaText = '';
                this.errorMsg = '';
                ToastUtil.show('已重置登录状态');
                this.checkLoginCaptcha();
              });
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 40 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgPage)
  }
}
