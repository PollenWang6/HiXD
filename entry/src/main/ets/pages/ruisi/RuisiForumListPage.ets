// RuisiForumListPage.ets — 板块列表

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import { ForumGroup, Forum, TopicListParam } from '../../services/RuisiModels';
import { ToastUtil } from '../../utils/ToastUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'RuisiForumListPage';

@Component
export struct RuisiForumListPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  @State groups: ForumGroup[] = [];
  @State loading: boolean = false;

  aboutToAppear(): void { this.loadForums(); }

  async loadForums(): Promise<void> {
    this.loading = true;
    try {
      const api = RuisiApiService.getInstance();
      this.groups = await api.getForumList();
    } catch (e) {
      hilog.error(0xFF00, TAG, 'loadForums: ' + JSON.stringify(e));
      ToastUtil.show('加载板块失败');
    } finally { this.loading = false; }
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

      Text('板块列表')
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
        } else {
          List({ space: 0 }) {
            ForEach(this.groups, (group: ForumGroup, gi: number) => {
              ListItem() {
                Column() {
                  Text(group.title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textSecondary)
                    .margin({ top: 12, bottom: 6, left: 16 })
                  ForEach(group.forums, (forum: Forum, fi: number) => {
                    Row() {
                      Column() {
                        Text(forum.name).fontSize(15).fontColor(ThemeColors.textPrimary)
                        if (forum.description.length > 0) {
                          Text(forum.description).fontSize(12).fontColor(ThemeColors.textHint).maxLines(1)
                        }
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      if (forum.threads > 0) {
                        Text(forum.threads + '帖').fontSize(12).fontColor(ThemeColors.textHint)
                      }
                    }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
                    .onClick(() => {
                      this.pageInfo.pushPath({ name: 'RuisiTopicList', param: new TopicListParam(forum.fid, forum.name) });
                    })
                  }, (forum: Forum) => `forum_${forum.fid}`)
                }.width('100%')
              }
            }, (group: ForumGroup) => 'group_' + group.title)
          }.width('100%').layoutWeight(1)
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
