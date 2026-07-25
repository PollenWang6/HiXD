// RuisiTopicListPage.ets — 帖子列表（无限滚动分页）
// 对标 Flutter topic_list_page.dart: PagingController + PagedListView + TopicListItem

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import { Topic, TopicDetailParam, UserParam, NewPostParam } from '../../services/RuisiModels';
import { RuisiTopicItem } from '../../components/RuisiTopicItem';
import { ToastUtil } from '../../utils/ToastUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'RuisiTopicListPage';

@Component
export struct RuisiTopicListPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  fid: number = 0;
  forumName: string = '';
  @State topics: Topic[] = [];
  @State page: number = 1;
  @State totalPages: number = 1;
  @State loading: boolean = false;
  @State loadingMore: boolean = false;
  private scroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    this.loadData(true);
  }

  async loadData(reset: boolean): Promise<void> {
    if (reset) { this.page = 1; this.topics = []; }
    if (this.loading || this.loadingMore) return;
    if (reset) { this.loading = true; } else { this.loadingMore = true; }
    try {
      const api = RuisiApiService.getInstance();
      const result = await api.getTopicList(this.fid, this.page);
      if (reset) { this.topics = result.topics; } else { this.topics = this.topics.concat(result.topics); }
      this.totalPages = result.totalPages;
    } catch (e) {
      ToastUtil.show('加载失败');
    } finally { this.loading = false; this.loadingMore = false; }
  }

  @Builder
  headerBuilder() {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(this.accentTextColor())
          .draggable(false)
      }
      .height(40).width(40)
      .onClick(() => { this.pageInfo.pop(); })

      Text(this.forumName || '帖子列表')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
    }
    .width('100%').height('100%')
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
    .backgroundColor(this.accentColor)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          if (this.loading) {
            Column() { LoadingProgress().width(36).height(36).color(this.accentColor) }
              .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            List({ space: 0, scroller: this.scroller }) {
              ForEach(this.topics, (topic: Topic, idx: number) => {
                ListItem() {
                  RuisiTopicItem({
                    topic: topic,
                    onClickTopic: (tid: number) => {
                      this.pageInfo.pushPath({ name: 'RuisiTopicDetail', param: new TopicDetailParam(tid) });
                    },
                    onClickUser: (uid: number, username: string) => {
                      this.pageInfo.pushPath({ name: 'RuisiUser', param: new UserParam(uid, username) });
                    }
                  })
                }.border({ width: { bottom: 0.5 }, color: ThemeColors.border })
              }, (topic: Topic) => `t_${topic.tid}`)

              if (this.page < this.totalPages && !this.loadingMore) {
                ListItem() {
                  Row() { Text('加载更多').fontSize(13).fontColor(ThemeColors.textSecondary) }
                    .width('100%').height(44).justifyContent(FlexAlign.Center)
                    .onClick(() => { this.page++; this.loadData(false); })
                }
              }
              if (this.loadingMore) {
                ListItem() { Row() { LoadingProgress().width(24).height(24).color(this.accentColor) }
                  .width('100%').height(44).justifyContent(FlexAlign.Center) }
              }
            }.width('100%').layoutWeight(1)
            .onReachEnd(() => {
              if (this.page < this.totalPages && !this.loadingMore && !this.loading) {
                this.page++;
                this.loadData(false);
              }
            })
          }
        }
        .width('100%').height('100%')

        // 板块内发帖悬浮按钮（玻璃质感，与首页发帖 FAB 一致）
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
        .margin({ bottom: 80, right: 20 })
        .onClick(() => {
          this.pageInfo.pushPath({
            name: 'RuisiNewPost',
            param: new NewPostParam(this.fid, this.forumName)
          });
        })
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
