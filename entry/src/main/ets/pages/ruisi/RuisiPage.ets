// RuisiPage.ets — 睿思论坛 Tab 入口页
// 登录态判断：已登录 → 渲染 RuisiHomePage（睿思首页），未登录 → RuisiLoginPage
// 子页（含帖子详情）统一走 MainPage 根 Navigation 栈：
//   RuisiHomePage 调用 this.pageInfo.pushPath({ name: 'RuisiTopicDetail', param })
//   → MainPage.navDestinationBuilder 渲染对应子页（全屏子页，系统返回键自动 pop）
//
// 注意：标题栏由本页统一绘制（checking / 已登录 / 未登录 三种状态都显示），
// 子页 RuisiHomePage / RuisiLoginPage 不再各自绘制标题栏，避免切换时标题栏缺失 / 重复。

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiService } from '../../services/RuisiService';
import { RuisiApiService } from '../../services/RuisiApiService';
import { RuisiHomePage } from './RuisiHomePage';
import { RuisiLoginPage } from './RuisiLoginPage';

const TAG = 'RuisiPage';

@Component
export struct RuisiPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageLink('ruisi_logged_in') isLoggedIn: boolean = false;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  // 来自 MainPage 根 Navigation 的导航栈（与全站菜单子页共用）
  pageInfo: NavPathStack = new NavPathStack();
  @State loginChecked: boolean = false;
  @State checking: boolean = true;

  private accentTextColor(): Color { return AccentColors.textContrast; }

  aboutToAppear(): void {
    this.checkLoginStatus();
  }

  async checkLoginStatus(): Promise<void> {
    this.checking = true;
    const svc = RuisiService.getInstance();
    // 冷启动把磁盘 cookie 装回内存。登录态的唯一权威是「磁盘持久化的登录标记 + cookie」，
    // 而不是一次性的网络探针：校园网波动/探针误判绝不应把已登录用户踢回登录页
    // （这正是此前「每次重启都要重登 / 没退出却显示登录页」的根因）。
    await svc.loadCookies();
    this.isLoggedIn = svc.isLoggedIn();
    this.checking = false;
    this.loginChecked = true;
    // 后台静默刷新会话（校验 + 必要时静默续登）。成败都不翻转已显示的登录 UI，
    // 会话确实失效时由实际数据请求（首页/投票等）触发重新登录提示，而不是弹回登录页。
    RuisiApiService.getInstance().refreshSessionInBackground();
  }

  onLoginSuccess(): void {
    this.isLoggedIn = true;
  }

  onLogout(): void {
    this.isLoggedIn = false;
  }

  // 标题栏：三种状态（加载 / 已登录 / 未登录）统一绘制，切 Tab 时不再空白
  @Builder
  TitleBar() {
    Row() {
      Text('睿思论坛')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentTextColor())
    }
    .width('100%')
    .height(52 + this.statusBarHeight)
    .padding({ left: 16, right: 16, top: this.statusBarHeight })
    .backgroundColor(this.accentColor)
  }

  build() {
    Column() {
      // 标题栏始终显示
      this.TitleBar()

      if (this.checking) {
        // 加载中：标题栏 + 内容区 loading（不再整屏空白）
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(this.accentColor)
          Text('正在检查登录状态...')
            .fontSize(14)
            .fontColor(ThemeColors.textSecondary)
            .margin({ top: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeColors.bgPage)
      } else if (this.isLoggedIn) {
        // 睿思首页（其子页走根 Navigation 栈）
        RuisiHomePage({ pageInfo: this.pageInfo })
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(ThemeColors.bgPage)
      } else {
        RuisiLoginPage({ pageInfo: this.pageInfo })
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(ThemeColors.bgPage)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgPage)
  }
}
