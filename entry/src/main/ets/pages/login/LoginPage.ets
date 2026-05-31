// LoginPage.ets — App内输入账号密码，WebView自动填充
import web from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
import { router } from '@kit.ArkUI';
import { HttpUtil } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';

const TAG = 'LoginPage';

interface PageBeginEvent { url: string; }
interface PageEndEvent { url: string; }
interface ProgressChangeEvent { newProgress: number; }

@Entry
@Component
struct LoginPage {
  @State loadProgress: number = 0;
  @State currentUrl: string = '';
  @State isLoading: boolean = false;
  @State statusText: string = '';
  @State username: string = '';
  @State password: string = '';
  @State showWebView: boolean = false;
  @State autoFilled: boolean = false;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  webController: web.WebviewController = new web.WebviewController();
  private loginHandled: boolean = false;

  private readonly LOGIN_URL: string =
    'https://ehall.xidian.edu.cn/login?service=' +
    encodeURIComponent('https://ehall.xidian.edu.cn/new/index.html');

  aboutToAppear(): void {
    if (PreferenceUtil.getBool('is_logged_in')) {
      this.statusText = '检测到已保存的登录状态，正在验证...';
      setTimeout(() => {
        router.replaceUrl({ url: 'pages/MainPage' });
      }, 500);
      return;
    }
    // 加载已保存的凭据
    this.username = PreferenceUtil.getString('login_username');
    this.password = PreferenceUtil.getString('login_password');
    // 如果是从MainPage过期状态跳转过来且已保存凭据，自动开始登录
    const autoLogin: boolean = PreferenceUtil.getBool('auto_login_next');
    if (autoLogin) {
      PreferenceUtil.putBool('auto_login_next', false); // 清除标志
      if (this.username.length > 0 && this.password.length > 0) {
        setTimeout(() => { this.onAutoFillLogin(); }, 300);
      }
    }
  }

  onAutoFillLogin(): void {
    if (this.username.length === 0) {
      this.statusText = '请输入学号';
      return;
    }
    if (this.password.length === 0) {
      this.statusText = '请输入密码';
      return;
    }
    // 保存凭据到本地
    PreferenceUtil.putString('login_username', this.username);
    PreferenceUtil.putString('login_password', this.password);
    this.statusText = '正在加载登录页面...';
    this.isLoading = true;
    this.showWebView = true;
  }

  tryAutoFill(): void {
    if (this.autoFilled || this.username.length === 0 || this.password.length === 0) {
      return;
    }
    const js: string =
      '(function(){' +
      'var u=document.getElementById("username")||document.querySelector("input[name=\\\"username\\\"]");' +
      'var p=document.getElementById("password")||document.querySelector("input[name=\\\"password\\\"]");' +
      'if(u){u.value="' + this.username + '";u.dispatchEvent(new Event("input",{bubbles:true}));}' +
      'if(p){p.value="' + this.password + '";p.dispatchEvent(new Event("input",{bubbles:true}));}' +
      '})();';
    try {
      this.webController.runJavaScript(js);
      this.autoFilled = true;
      this.statusText = '已自动填充，请完成人机验证';
    } catch (e) {
      console.warn(TAG, 'Auto-fill JS injection failed: ' + JSON.stringify(e));
    }
  }

  async onLoginSuccess(): Promise<void> {
    if (this.loginHandled) {
      return;
    }
    this.loginHandled = true;
    this.statusText = '登录成功！正在保存...';
    // 触发CAS请求以捕获TGC（onInterceptRequest从Cookie请求头提取）
    this.webController.runJavaScript('new Image().src="https://cas.xidian.edu.cn/favicon.ico?"+Date.now()');
    try {
      const idsCookies: string = web.WebCookieManager.getCookie('https://ids.xidian.edu.cn');
      const ehallCookies: string = web.WebCookieManager.getCookie('https://ehall.xidian.edu.cn');
      const casCookies: string = web.WebCookieManager.getCookie('https://cas.xidian.edu.cn');
      console.error(TAG, 'Cookie diag - ids: ' + (idsCookies ? idsCookies.length : 'null') + ', ehall: ' + (ehallCookies ? ehallCookies.length : 'null') + ', cas: ' + (casCookies ? casCookies.length : 'null'));
      if (casCookies && casCookies.length > 0) {
        console.error(TAG, 'CAS cookies: ' + casCookies.substring(0, 200));
      }
      if (idsCookies && idsCookies.length > 0) {
        await HttpUtil.getInstance().injectCookies(idsCookies, 'ids.xidian.edu.cn');
        await web.WebCookieManager.setCookie('https://ids.xidian.edu.cn', idsCookies);
      }
      if (ehallCookies && ehallCookies.length > 0) {
        console.error(TAG, '=== EHALL COOKIES FULL: ' + ehallCookies);
        const modMatch = ehallCookies.match(/MOD_AUTH_CAS=([^;]+)/);
        if (modMatch && modMatch[1]) {
          console.error(TAG, '!!! MOD_AUTH_CAS READABLE: ' + modMatch[1]);
          await PreferenceUtil.putString('mod_auth_cas', modMatch[1]);
        } else {
          console.error(TAG, '!!! MOD_AUTH_CAS NOT FOUND in ehall cookies');
        }
        await HttpUtil.getInstance().injectCookies(ehallCookies, 'ehall.xidian.edu.cn');
        await web.WebCookieManager.setCookie('https://ehall.xidian.edu.cn', ehallCookies);
      }
      // 保存CAS TGC到PreferenceUtil，供实验系统等需要CAS SSO的页面使用
      if (casCookies && casCookies.length > 0) {
        await HttpUtil.getInstance().injectCookies(casCookies, 'cas.xidian.edu.cn');
        const tgcMatch = casCookies.match(/TGC=([^;]+)/);
        if (tgcMatch && tgcMatch[1]) {
          await PreferenceUtil.putString('cas_tgc', tgcMatch[1]);
          console.info(TAG, 'Saved CAS TGC for SSO');
        }
      }
      // 直接把用户输入的学号存入 ids_account（西电统一认证账号就是学号）
      if (this.username.length > 0) {
        await PreferenceUtil.putString('ids_account', this.username);
        console.info(TAG, 'Saved student ID from input: ' + this.username);
      }
    } catch (e) {
      console.error(TAG, 'Cookie extraction failed: ' + JSON.stringify(e));
    }
    await PreferenceUtil.putBool('is_logged_in', true);
    // 登录成功，重置自动登录计数器
    PreferenceUtil.putNumber('auto_login_attempts', 0);
    setTimeout(() => {
      router.replaceUrl({ url: 'pages/MainPage' });
    }, 500);
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('登录').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        Blank()
        if (this.isLoading) {
          LoadingProgress().width(24).height(24).color('#2979FF')
        }
      }
      .width('100%').height(56).padding({ left: 16, right: 16 })
      .backgroundColor(ThemeColors.bgCard)
      .shadow({ radius: 2, color: '#00000010', offsetY: 1 })

      if (!this.showWebView) {
        // ===== 账号密码输入表单 =====
        Column() {
          Column() {
            Text('西电统一身份认证').fontSize(24).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .margin({ bottom: 8 })
            Text('输入学号和密码，自动填写登录页').fontSize(14).fontColor(ThemeColors.textSecondary)
              .margin({ bottom: 32 })
          }
          .width('100%').alignItems(HorizontalAlign.Start)

          // 学号
          TextInput({ placeholder: '请输入学号', text: this.username })
            .width('100%').height(48).fontSize(16)
            .type(InputType.Normal)
            .placeholderColor('#CCCCCC')
            .backgroundColor(ThemeColors.bgInput).borderRadius(8)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => { this.username = value; })

          // 密码
          TextInput({ placeholder: '请输入密码', text: this.password })
            .width('100%').height(48).fontSize(16)
            .type(InputType.Password)
            .placeholderColor('#CCCCCC')
            .backgroundColor(ThemeColors.bgInput).borderRadius(8)
            .padding({ left: 16, right: 16 })
            .margin({ top: 16 })
            .onChange((value: string) => { this.password = value; })

          // 登录按钮
          Button('自动填充并登录')
            .width('100%').height(48).fontSize(16).fontColor('#FFFFFF')
            .backgroundColor('#2979FF').borderRadius(8)
            .margin({ top: 32 })
            .onClick(() => this.onAutoFillLogin())

          // 错误提示
          if (this.statusText.length > 0) {
            Text(this.statusText).fontSize(13).fontColor('#FF6B6B')
              .margin({ top: 16 })
          }

          // 隐私说明
          Text('账号密码仅保存在本设备，不会上传至任何服务器').fontSize(12).fontColor('#BBBBBB')
            .margin({ top: 24 })
        }
        .width('100%').layoutWeight(1)
        .padding({ left: 32, right: 32, top: 48 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(ThemeColors.bgCard)

      } else {
        // ===== WebView 登录页 =====
        Column() {
          // 进度条
          if (this.loadProgress < 100 && this.isLoading) {
            Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
              .width('100%').height(3).color('#2979FF').backgroundColor(ThemeColors.bgInput)
          }

          // 状态文字
          if (this.statusText.length > 0) {
            Text(this.statusText).fontSize(12).fontColor(ThemeColors.textSecondary)
              .width('100%').padding({ left: 16, right: 16, top: 8 })
          }

          Web({ src: this.LOGIN_URL, controller: this.webController })
            .width('100%').layoutWeight(1)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .databaseAccess(true)
            .cacheMode(CacheMode.Default)
            .mixedMode(MixedMode.All)
            .onlineImageAccess(true)
            .fileAccess(true)
            .onInterceptRequest((event) => {
              if (!event || !event.request) {
                return null;
              }
              let url: string = event.request.getRequestUrl();
              if (url.includes('cas.xidian.edu.cn')) {
                let headers = event.request.getRequestHeader();
                for (let i = 0; i < headers.length; i++) {
                  if (headers[i].headerKey.toLowerCase() === 'cookie') {
                    let cookie = headers[i].headerValue;
                    let match = cookie.match(/TGC=([^;]+)/);
                    if (match && match[1]) {
                      console.error(TAG, '!!! TGC CAPTURED from request: ' + match[1]);
                      PreferenceUtil.putString('cas_tgc', match[1]);
                    }
                    break;
                  }
                }
              }
              return null;
            })
            .onPageBegin((event: PageBeginEvent) => {
              if (event) {
                this.currentUrl = event.url;
                this.isLoading = true;
                this.autoFilled = false; // 新页面需要重新填充
                // 在CAS域停留时抓TGC cookie（此时WebView在CAS域，cookie可访问）
                if (event.url.indexOf('cas.xidian.edu.cn') >= 0) {
                  try {
                    const cookies: string = web.WebCookieManager.getCookie('https://cas.xidian.edu.cn');
                    console.error(TAG, 'onPageBegin CAS cookies: ' + (cookies ? cookies.length : 'null') + ' url=' + event.url);
                  } catch (e) {
                    console.warn(TAG, 'CAS cookie capture failed: ' + String(e));
                  }
                }
                if (event.url.includes('ehall.xidian.edu.cn/new/index') ||
                    event.url.includes('ehall.xidian.edu.cn/new/index_xd')) {
                  this.statusText = '检测到登录成功，正在保存...';
                  this.onLoginSuccess();
                }
              }
            })
            .onPageEnd((event: PageEndEvent) => {
              if (event) {
                this.isLoading = false;

                this.loadProgress = 100;
                if (event.url.includes('ehall.xidian.edu.cn') && !event.url.includes('login')) {
                  this.onLoginSuccess();
                } else {
                  // 登录页加载完成，自动填充账号密码
                  this.tryAutoFill();
                }
              }
            })
            .onProgressChange((event: ProgressChangeEvent) => {
              if (event) {
                this.loadProgress = event.newProgress;
              }
            })
        }
        .width('100%').layoutWeight(1)
      }

      // 底部提示
      Column() {
        Text('请使用统一身份认证账号登录').fontSize(12).fontColor(ThemeColors.textSecondary)
        Text('登录成功后 cookies 将自动保存').fontSize(11).fontColor('#BBBBBB').margin({ top: 4 })
      }
      .width('100%').padding({ top: 12, bottom: 20 })
      .alignItems(HorizontalAlign.Center).backgroundColor(ThemeColors.bgPage)
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgCard)
  }
}
