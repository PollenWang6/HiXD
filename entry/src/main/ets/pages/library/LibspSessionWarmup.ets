// 图书馆会话后台静默预热组件（纯 HTTP）。
//
// 问题背景：首页「图书馆」卡片（在借/逾期）依赖 LibspSessionService 缓存的 JWT 会话取数，
// 而该会话只有进入图书馆页、其纯 HTTP 流程（fetchJwtViaHttp）跑完 CAS→超星→libsp 链拿到
// JWT 并 saveSession 后才存在。于是首页首次/会话失效时取不到，进了图书馆页出来后才显示。
//
// 本组件在 CAS 登录成功后，于后台静默执行 fetchJwtViaHttp 建立 libsp 会话（纯 HTTP，
// 无 WebView），随后直接刷新首页卡片（并 bump home_data_dirty 兜底）。
// 组件常驻挂载、build 为空（纯逻辑组件，不渲染任何 UI）。

import { LibspSessionService, LibspBorrowSummary } from '../../services/LibspSessionService';

@Component
export struct LibspSessionWarmup {
  @StorageLink('loginStatus') @Watch('onLoginStatus') loginStatus: string = '';
  private warmed: boolean = false;

  aboutToAppear(): void {
    // 冷启动若已处于登录态，立即预热
    if (this.loginStatus === 'ok') {
      this.startWarmup();
    }
  }

  // loginStatus 变化：变为 ok 时预热；离开 ok（登出/过期）时重置，允许下次重新预热
  private onLoginStatus(): void {
    if (this.loginStatus === 'ok') {
      this.startWarmup();
    } else {
      this.warmed = false;
    }
  }

  private async startWarmup(): Promise<void> {
    if (this.warmed) {
      return;
    }
    this.warmed = true;
    // 纯 HTTP 建立 libsp 会话（内部已确保 CAS 登录态）
    const s = await LibspSessionService.fetchJwtViaHttp();
    if (!s) {
      return; // 失败不重置 warmed，避免反复重试；待登录态变化后再试
    }
    // 会话已 saveSession；直接取概况更新首页卡片，并 bump home_data_dirty 触发既有刷新路径兜底
    LibspSessionService.fetchBorrowSummary()
      .then((summary: LibspBorrowSummary | null) => {
        if (summary) {
          AppStorage.set('home_lib_borrow', String(summary.borrow));
          AppStorage.set('home_lib_overdue', String(summary.overdue));
        }
        AppStorage.set('home_data_dirty', String(Date.now()));
      })
      .catch(() => {
        AppStorage.set('home_data_dirty', String(Date.now()));
      });
  }

  build() {
    // 纯逻辑组件：不渲染任何 UI
    Column().width(0).height(0)
  }
}
