// RuisiMyPostsPage.ets — 我的帖子 / 他的帖子（支持下滑加载更多）

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import { Topic, TopicDetailParam, UserParam, TopicListResult } from '../../services/RuisiModels';
import { RuisiTopicItem } from '../../components/RuisiTopicItem';
import { RuisiService } from '../../services/RuisiService';
import { ToastUtil } from '../../utils/ToastUtil';

@Component
export struct RuisiMyPostsPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();
  private scroller: ListScroller = new ListScroller();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  // 查看他人（>0）或自己（=0）的主题/回帖；mode: 'me'=主题 / 'reply'=回帖
  targetUid: number = 0;
  mode: string = 'me';
  @State topics: Topic[] = [];
  @State page: number = 1;
  @State hasMore: boolean = true;
  @State loading: boolean = false;
  @State loadingMore: boolean = false;
  @State pageTitle: string = '我的帖子';

  aboutToAppear(): void {
    const svc = RuisiService.getInstance();
    const uid = this.targetUid > 0 ? this.targetUid : svc.getUid();
    this.pageTitle = this.targetUid > 0
      ? (this.mode === 'reply' ? 'TA的回帖' : 'TA的主题')
      : (this.mode === 'reply' ? '我的回帖' : '我的帖子');
    this.loadThreads(uid, true);
  }

  private currentUid(): number {
    const svc = RuisiService.getInstance();
    return this.targetUid > 0 ? this.targetUid : svc.getUid();
  }

  async loadThreads(uid: number, reset: boolean): Promise<void> {
    if (uid === 0) return;
    if (this.loading || this.loadingMore) return;
    if (reset) { this.page = 1; this.topics = []; this.hasMore = true; this.loading = true; }
    else { this.loadingMore = true; }
    try {
      const api = RuisiApiService.getInstance();
      const view = this.mode === 'reply' ? 'reply' : 'me';
      const type = this.mode === 'reply' ? 'reply' : 'thread';
      const result: TopicListResult = await api.getMyThreads(uid, this.page, view, type);
      if (reset) {
        this.topics = result.topics;
      } else {
        this.topics = this.topics.concat(result.topics);
      }
      // 是否有下一页：优先用解析到的总页数，解析失败（默认1）时按每页返回条数判定
      // （Discuz 默认每页 20 条，返回不足 20 条即末页，空页也视为到底）
      if (result.topics.length === 0) {
        this.hasMore = false;
      } else if (result.totalPages > 1) {
        this.hasMore = this.page < result.totalPages;
      } else {
        this.hasMore = result.topics.length >= 20;
      }
      if (this.hasMore) this.page++;
    } catch (e) {
      ToastUtil.show('加载失败');
    } finally {
      this.loading = false;
      this.loadingMore = false;
    }
  }

  @Builder
  headerBuilder() {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .width(22).height(22)
          .fillColor(this.accentTextColor())
          .draggable(false)
      }
      .width(40).height(40)
      .backgroundColor('rgba(255,255,255,0.18)')
      .onClick(() => { this.pageInfo.pop(); })
      .margin({ right: 12 })

      Text(this.pageTitle)
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
    }.width('100%').height('100%').padding({ left: 12, right: 16, top: this.statusBarHeight }).backgroundColor(this.accentColor)
  }

  build() {
    NavDestination() {
      Column() {
        if (this.loading) {
          Column() { LoadingProgress().width(36).height(36).color(this.accentColor) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.topics.length === 0) {
          Column() {
            Text('📭').fontSize(48).margin({ bottom: 12 })
            Text(this.targetUid > 0
              ? (this.mode === 'reply' ? 'TA还没回复过帖子' : 'TA还没发过主题')
              : (this.mode === 'reply' ? '你还没回复过帖子' : '你还没发过帖子喔'))
              .fontSize(15).fontColor(ThemeColors.textHint)
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 0, scroller: this.scroller }) {
            ForEach(this.topics, (t: Topic, idx: number) => {
              ListItem() {
                RuisiTopicItem({
                  topic: t,
                  onClickTopic: (tid: number) => {
                    this.pageInfo.pushPath({ name: 'RuisiTopicDetail', param: new TopicDetailParam(tid) });
                  },
                  onClickUser: (uid: number, username: string) => {
                    this.pageInfo.pushPath({ name: 'RuisiUser', param: new UserParam(uid, username) });
                  }
                })
              }.border({ width: { bottom: 0.5 }, color: ThemeColors.border })
            }, (t: Topic) => `mypost_${t.tid}`)

            if (this.hasMore && !this.loadingMore) {
              ListItem() {
                Row() { Text('加载更多').fontSize(13).fontColor(ThemeColors.textSecondary) }
                  .width('100%').height(44).justifyContent(FlexAlign.Center)
                  .onClick(() => { this.loadThreads(this.currentUid(), false); })
              }
            }
            if (this.loadingMore) {
              ListItem() {
                Row() { LoadingProgress().width(24).height(24).color(this.accentColor) }
                  .width('100%').height(44).justifyContent(FlexAlign.Center)
              }
            }
            if (!this.hasMore && this.topics.length > 0) {
              ListItem() {
                Row() { Text('—— 已经到底啦 ——').fontSize(12).fontColor(ThemeColors.textHint) }
                  .width('100%').height(44).justifyContent(FlexAlign.Center)
              }
            }
          }
          .width('100%').layoutWeight(1)
          .onReachEnd(() => {
            if (this.hasMore && !this.loadingMore && !this.loading) {
              this.loadThreads(this.currentUid(), false);
            }
          })
        }
      }
      .width('100%').height('100%')
      .backgroundColor(ThemeColors.bgPage)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .title({ builder: this.headerBuilder(), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
