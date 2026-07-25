// RuisiSearchPage.ets — 搜索
// 对标 Flutter search_page.dart: PagingController + PagedListView

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import { SearchResult, Topic, RuisiConstants, TopicDetailParam, UserParam } from '../../services/RuisiModels';
import { RuisiTopicItem } from '../../components/RuisiTopicItem';
import { ToastUtil } from '../../utils/ToastUtil';

@Component
export struct RuisiSearchPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  @State keyword: string = '';
  @State results: SearchResult[] = [];
  @State searching: boolean = false;
  @State hasSearched: boolean = false;
  @State page: number = 1;
  @State hasMore: boolean = false;
  private scroller: ListScroller = new ListScroller();

  async doSearch(reset: boolean = true): Promise<void> {
    if (this.keyword.trim().length === 0) { ToastUtil.show('请输入关键词'); return; }
    if (reset) {
      this.page = 1;
      this.results = [];
    }
    this.searching = true;
    this.hasSearched = true;
    try {
      const api = RuisiApiService.getInstance();
      const newResults = await api.search(this.keyword.trim(), this.page);
      if (reset) {
        this.results = newResults;
      } else {
        this.results = this.results.concat(newResults);
      }
      this.hasMore = newResults.length > 0;
    } catch (e) {
      ToastUtil.show('搜索失败');
    } finally { this.searching = false; }
  }

  // 把搜索结果映射成通用 Topic，复用 RuisiTopicItem 列表项组件
  private toTopic(r: SearchResult): Topic {
    const t = new Topic();
    t.tid = r.tid;
    t.title = r.title;
    t.author = r.author;
    t.authorId = r.authorId;
    t.replies = r.replies;
    t.views = r.views;
    t.postTime = r.postTime;
    t.forumName = r.forumName;
    t.excerpt = r.excerpt;
    return t;
  }

  @Builder
  headerBuilder() {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close')).width(22).height(22).fillColor(this.accentTextColor()).draggable(false)
      }.width(40).height(40).backgroundColor('rgba(255,255,255,0.18)').onClick(() => { this.pageInfo.pop() }).margin({ right: 12 })
      Text('搜索').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
    }.width('100%').height('100%').padding({ left: 12, right: 16, top: this.statusBarHeight }).backgroundColor(this.accentColor)
  }

  build() {
    NavDestination() {
      Column() {
        // 搜索框（对标 Flutter TextField with autofocus）
        Row() {
          TextInput({ text: this.keyword, placeholder: '搜索帖子...' })
            .fontSize(15).fontColor(ThemeColors.textPrimary).backgroundColor(ThemeColors.bgInput)
            .borderRadius(20).height(40).layoutWeight(1)
            .onChange((v: string) => { this.keyword = v; })
            .onSubmit(() => { this.doSearch(true); })
          Button('搜索').fontSize(14).height(40).margin({ left: 8 })
            .backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(20)
            .onClick(() => { this.doSearch(true); })
        }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 }).backgroundColor(ThemeColors.bgCard)

        if (this.searching && this.results.length === 0) {
          Column() { LoadingProgress().width(36).height(36).color(this.accentColor) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.hasSearched && this.results.length === 0) {
          Column() { Text('未找到相关帖子').fontSize(14).fontColor(ThemeColors.textHint) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0, scroller: this.scroller }) {
            ForEach(this.results, (r: SearchResult, idx: number) => {
              ListItem() {
                RuisiTopicItem({
                  topic: this.toTopic(r),
                  onClickTopic: (tid: number) => {
                    this.pageInfo.pushPath({ name: 'RuisiTopicDetail', param: new TopicDetailParam(tid) });
                  },
                  onClickUser: (uid: number, username: string) => {
                    this.pageInfo.pushPath({ name: 'RuisiUser', param: new UserParam(uid, username) });
                  }
                })
              }.border({ width: { bottom: 0.5 }, color: ThemeColors.border })
            }, (r: SearchResult) => `srch_${r.tid}`)

            // 加载更多
            if (this.hasMore && !this.searching) {
              ListItem() {
                Row() { Text('加载更多').fontSize(13).fontColor(ThemeColors.textSecondary) }
                  .width('100%').height(44).justifyContent(FlexAlign.Center)
                  .onClick(() => { this.page++; this.doSearch(false); })
              }
            }
            if (this.searching && this.results.length > 0) {
              ListItem() {
                Row() { LoadingProgress().width(24).height(24).color(this.accentColor) }
                  .width('100%').height(44).justifyContent(FlexAlign.Center)
              }
            }
          }.width('100%').layoutWeight(1)
          .onReachEnd(() => {
            if (this.hasMore && !this.searching) {
              this.page++;
              this.doSearch(false);
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
