// RuisiHomePage.ets — 睿思论坛首页
// 对标 Flutter home_page.dart：7 Tab + 顶栏操作按钮
// Tab 顺序：最新帖子、最新回复、水区、摄影、二手交易、就业、失物招领

import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { RuisiApiService } from '../../services/RuisiApiService';
import { RuisiService } from '../../services/RuisiService';
import { Topic, RuisiConstants, TopicDetailParam, UserParam } from '../../services/RuisiModels';
import { ToastUtil } from '../../utils/ToastUtil';
import { SegmentTab } from '../../components/SegmentTab';
import { RuisiTopicItem } from '../../components/RuisiTopicItem';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { curves } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'RuisiHomePage';

@Component
export struct RuisiHomePage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageLink('ruisi_logged_in') isLoggedIn: boolean = false;
  pageInfo: NavPathStack = new NavPathStack();

  @State currentTab: number = 0;
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State topics: Topic[] = [];
  @State page: number = 1;
  @State hasMore: boolean = true;
  @State avatarUrl: string = '';

  // 发帖悬浮按钮：玻璃质感 + 智感握持 + 换手动画（对标 ScorePage GPA 计算器 FAB）
  @State isLeftHand: boolean = false;
  @State fabTranslateX: number = 0;        // 正值靠右，负值滑到左侧
  private fabInitialized: boolean = false;
  private screenWidth: number = 360;       // 屏幕宽度(vp)，onAreaChange 更新

  // 对标 Flutter: Tab 顺序 = 最新帖子/最新回复/水区/摄影/二手交易/就业/失物招领
  private tabs: string[] = ['最新', '回复', '水区', '摄影', '交易', '就业', '失物'];
  private fidMap: number[] = [
    0, // 最新帖子（guide）
    0, // 最新回复（guide）
    RuisiConstants.FORUM_WATER,   // 72
    RuisiConstants.FORUM_PHOTO,   // 561
    RuisiConstants.FORUM_TRADE,   // 110
    RuisiConstants.FORUM_JOB,     // 553
    RuisiConstants.FORUM_LOST,    // 142
  ];

  aboutToAppear(): void {
    this.loadData(true);
    this.loadAvatarUrl();
    this.startHoldingHandDetection();
  }

  aboutToDisappear(): void {
    try {
      motion.off('holdingHandChanged');
    } catch (e) {
      // ignore
    }
  }

  // 智感握持：监听设备感知到的左右手持握，自动切换发帖按钮到对应侧
  private startHoldingHandDetection(): void {
    try {
      motion.on('holdingHandChanged', (data: number) => {
        const wasLeft = this.isLeftHand;
        this.isLeftHand = (data === 1 || data === 3);
        if (wasLeft !== this.isLeftHand) {
          this.animateFab();
        }
      });
    } catch (err) {
      const e = err as BusinessError;
      if (e.code === 801) {
        // 设备不支持智感握持，默认右手（右侧）即可
      }
      this.isLeftHand = false;
    }
  }

  private animateFab(): void {
    if (!this.fabInitialized) return;
    // 右手：translateX=0（Stack.BottomEnd 右侧）；左手：滑到左侧
    const targetX = this.isLeftHand ? -(this.screenWidth - 80) : 0;
    animateTo({ duration: 400, curve: curves.springMotion(0.45, 0.85) }, () => {
      this.fabTranslateX = targetX;
    });
  }

  loadAvatarUrl(): void {
    const uid = RuisiService.getInstance().getUid();
    if (uid > 0) {
      this.avatarUrl = `${RuisiConstants.BASE_URL}/uc2_link/avatar.php?uid=${uid}&size=small`;
    }
  }

  async loadData(reset: boolean = false): Promise<void> {
    if (this.loading) return;
    if (reset) {
      this.page = 1;
      this.topics = [];
      this.hasMore = true;
    }
    if (!this.hasMore) return;

    this.loading = true;
    try {
      const api = RuisiApiService.getInstance();
      const tabIdx = this.currentTab;
      let newTopics: Topic[] = [];

      if (tabIdx === 0) {
        newTopics = await api.getNewThreads(this.page);
      } else if (tabIdx === 1) {
        newTopics = await api.getNewReplies(this.page);
      } else {
        const fid = this.fidMap[tabIdx];
        const result = await api.getTopicList(fid, this.page);
        newTopics = result.topics;
      }

      if (reset) {
        this.topics = newTopics;
      } else {
        this.topics = this.topics.concat(newTopics);
      }
      this.hasMore = newTopics.length > 0;
    } catch (e) {
      hilog.error(0xFF00, TAG, 'loadData failed: ' + JSON.stringify(e));
      ToastUtil.show('加载失败');
    } finally {
      this.loading = false;
    }
  }

  onTabChange(idx: number): void {
    this.currentTab = idx;
    this.loadData(true);
  }

  onLoadMore(): void {
    if (this.loading || !this.hasMore) return;
    this.page++;
    this.loadData(false);
  }

  // 下拉刷新 / 点击已激活 tab：回到顶部并重新加载首屏
  async doRefresh(): Promise<void> {
    this.refreshing = true;
    await this.loadData(true);
    this.refreshing = false;
  }

  private scroller: ListScroller = new ListScroller();

  onTopicClick(tid: number): void {
    this.pageInfo.pushPath({ name: 'RuisiTopicDetail', param: new TopicDetailParam(tid) });
  }

  // 每个 tab 页复用的帖子列表（内容绑定 this.topics，由 currentTab 决定当前显示数据）
  @Builder
  TabListContent() {
    Refresh({ refreshing: $$this.refreshing }) {
      List({ space: 0, scroller: this.scroller }) {
      ForEach(this.topics, (topic: Topic, idx: number) => {
        ListItem() {
          RuisiTopicItem({
            topic: topic,
            onClickTopic: (tid: number) => { this.onTopicClick(tid); },
            onClickUser: (uid: number, username: string) => {
              this.pageInfo.pushPath({ name: 'RuisiUser', param: new UserParam(uid, username) });
            }
          })
        }
        .border({ width: { bottom: 0.5 }, color: ThemeColors.border })
      }, (topic: Topic) => 'topic_' + topic.tid)

      if (this.hasMore && !this.loading) {
        ListItem() {
          Row() {
            Text('点击加载更多')
              .fontSize(13)
              .fontColor(ThemeColors.textSecondary)
          }
          .width('100%')
          .height(44)
          .justifyContent(FlexAlign.Center)
          .onClick(() => { this.onLoadMore(); })
        }
      }

      if (this.loading) {
        ListItem() {
          Row() {
            LoadingProgress().width(24).height(24).color(this.accentColor)
          }
          .width('100%')
          .height(44)
          .justifyContent(FlexAlign.Center)
        }
      }

      if (!this.loading && this.topics.length === 0) {
        ListItem() {
          Column() {
            Text('暂无帖子')
              .fontSize(14)
              .fontColor(ThemeColors.textHint)
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
        }
      }
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: ThemeColors.border, startMargin: 16, endMargin: 16 })
      .onReachEnd(() => {
        if (this.hasMore && !this.loading) {
          this.onLoadMore();
        }
      })
    }
    .width('100%')
    .height('100%')
    .onRefreshing(() => { this.doRefresh(); })
  }

  // 酷安风格搜索操作行：头像 + 搜索框 + 板块按钮
  @Builder
  SearchHeaderRow() {
    Row() {
      // 个人头像：点击进入个人主页（退出登录已收进 RuisiUserPage）
      Row() {
        if (this.avatarUrl.length > 0) {
          Image(this.avatarUrl)
            .width(38).height(38).borderRadius(19)
            .objectFit(ImageFit.Cover)
        } else {
          Text('👤').fontSize(20)
        }
      }
      .width(42).height(42)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.pageInfo.pushPath({ name: 'RuisiUser' });
      })

      // 长条搜索框
      Row() {
        Text('🔍').fontSize(16).fontColor(ThemeColors.textHint)
        Text('搜索帖子、用户...')
          .fontSize(14).fontColor(ThemeColors.textHint)
          .layoutWeight(1)
          .margin({ left: 8 })
      }
      .height(40)
      .layoutWeight(1)
      .padding({ left: 12, right: 12 })
      .backgroundColor(ThemeColors.bgInput)
      .borderRadius(20)
      .margin({ left: 12, right: 12 })
      .onClick(() => {
        this.pageInfo.pushPath({ name: 'RuisiSearch' });
      })

      // 消息按钮（Emoji 入口，位于搜索框与板块之间；点击进入消息中心）
      Text('💬')
        .fontSize(20)
        .height(40)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeColors.bgInput)
        .borderRadius(20)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.pageInfo.pushPath({ name: 'RuisiMessages' });
        })

      // 板块按钮（Emoji 入口，去掉文字）
      Text('📋')
        .fontSize(20)
        .height(40)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeColors.bgInput)
        .borderRadius(20)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.pageInfo.pushPath({ name: 'RuisiForumList' });
        })
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .backgroundColor(ThemeColors.bgPage)
  }

  build() {
    Column() {
      // 标题栏由 RuisiPage 统一绘制，这里只放搜索操作行（头像 | 搜索框 | 板块）
      this.SearchHeaderRow()

      // Tab 内容 + 悬浮发帖按钮
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          SegmentTab({
            tabs: this.tabs,
            currentIndex: $currentTab,
            accentColor: this.accentColor,
            onTabChange: (idx: number) => this.onTabChange(idx),
            onReTap: (idx: number) => {
              this.scroller.scrollToIndex(0, true);
              this.doRefresh();
            }
          }) {
            ForEach(this.tabs, (tab: string, idx: number) => {
              this.TabListContent()
            }, (tab: string) => 'ruisi_tabpage_' + tab)
          }
        }
        .width('100%').height('100%')

        // 悬浮发帖按钮（玻璃质感 + 智感握持换手，对标 ScorePage 的 GPA 计算器 FAB）
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
          Image($r('app.media.ic_screenshot_penshape'))
            .width(26).height(26)
            .fillColor(this.isDark ? '#FFFFFF' : '#1A1A1A')
        }
        .width(56).height(56)
        .borderRadius(999)
        .backdropBlur(18)
        .backgroundColor(this.isDark ? 'rgba(40,40,45,0.35)' : 'rgba(255,255,255,0.15)')
        .border({ width: 1, color: 'rgba(255,255,255,0.30)' })
        .shadow({ radius: 10, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 4 })
        .margin({ bottom: 110, right: 20 })
        .translate({ x: this.fabTranslateX })
        .onClick(() => {
          this.pageInfo.pushPath({ name: 'RuisiNewPost' });
        })
      }
      .width('100%')
      .layoutWeight(1)
      .onAreaChange((oldVal, newVal) => {
        const w = newVal.width as number;
        if (w > 0) this.screenWidth = w;
        if (!this.fabInitialized) {
          this.fabInitialized = true;
          // 默认右手模式在右侧，translateX=0；左手模式滑到左侧
          this.fabTranslateX = this.isLeftHand ? -(this.screenWidth - 80) : 0;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeColors.bgPage)
  }
}
