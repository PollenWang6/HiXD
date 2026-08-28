// RuisiFavoritesPage.ets — 我的收藏
// 每行显示：标题 + 收藏时间 + 删除按钮（确认弹窗），对齐安卓长按删除

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import { Topic, TopicDetailParam } from '../../services/RuisiModels';
import { ToastUtil } from '../../utils/ToastUtil';
import { promptAction } from '@kit.ArkUI';

@Component
export struct RuisiFavoritesPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  @State topics: Topic[] = [];
  @State loading: boolean = false;

  aboutToAppear(): void { this.loadFavorites().catch(() => { ToastUtil.show('加载失败，请重试'); }); }

  async loadFavorites(): Promise<void> {
    this.loading = true;
    try {
      const api = RuisiApiService.getInstance();
      this.topics = await api.getMyFavorites(1);
    } finally { this.loading = false; }
  }

  private async doDelete(t: Topic, idx: number): Promise<void> {
    const api = RuisiApiService.getInstance();
    const r = await api.unfavoriteByFavId(t.favId);
    ToastUtil.show(r.message);
    if (r.success) {
      this.topics.splice(idx, 1);
    }
  }

  private confirmDelete(t: Topic, idx: number): void {
    const title = t.title.length > 30 ? t.title.substring(0, 30) + '...' : t.title;
    promptAction.showDialog({
      title: '取消收藏',
      message: `确定要取消收藏\n"${title}"吗？`,
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '确定删除', color: '#C62828' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.doDelete(t, idx);
      }
    }).catch(() => {});
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

      Text('我的收藏')
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
            ForEach(this.topics, (t: Topic, idx: number) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(t.title)
                      .fontSize(15).fontColor(ThemeColors.textPrimary)
                      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    if (t.postTime.length > 0) {
                      Text(t.postTime)
                        .fontSize(11).fontColor(ThemeColors.textHint)
                        .margin({ top: 4 })
                    }
                  }.layoutWeight(1).margin({ right: 12 })

                  // 删除按钮
                  Button({ type: ButtonType.Normal }) {
                    Image($r('app.media.ic_trash'))
                      .width(18).height(18)
                      .fillColor('#C62828')
                      .draggable(false)
                  }
                  .width(36).height(36)
                  .backgroundColor(ThemeColors.bgInput)
                  .borderRadius(8)
                  .onClick(() => { this.confirmDelete(t, idx); })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .backgroundColor(ThemeColors.bgCard)
                .onClick(() => {
                  this.pageInfo.pushPath({ name: 'RuisiTopicDetail', param: new TopicDetailParam(t.tid) });
                })
              }.border({ width: { bottom: 0.5 }, color: ThemeColors.border })
            }, (t: Topic) => `fav_${t.favId}`)
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
