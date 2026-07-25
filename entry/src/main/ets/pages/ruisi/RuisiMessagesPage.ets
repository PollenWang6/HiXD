// RuisiMessagesPage.ets — 消息中心
// 对齐 Android FrageMessage / iOS MessageViewController：回复 / 私信 / @我 三个 tab

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import {
  ReplyNotification, AtNotification, TopicDetailParam, PmConversation, PmParam
} from '../../services/RuisiModels';
import { SegmentTab } from '../../components/SegmentTab';
import { ToastUtil } from '../../utils/ToastUtil';
import { RuisiService } from '../../services/RuisiService';

@Component
export struct RuisiMessagesPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  @State currentTab: number = 0;
  @State loading: boolean = false;
  @State replies: ReplyNotification[] = [];
  @State pmList: PmConversation[] = [];
  @State atNotifs: AtNotification[] = [];

  aboutToAppear(): void { this.loadData(); }

  async loadData(): Promise<void> {
    this.loading = true;
    try {
      const api = RuisiApiService.getInstance();
      if (this.currentTab === 0) {
        this.replies = await api.getReplyNotifications(1);
      } else if (this.currentTab === 1) {
        this.pmList = await api.getPmList(1);
      } else {
        this.atNotifs = await api.getAtNotifications(1);
      }
    } catch (e) { ToastUtil.show('加载失败'); }
    finally { this.loading = false; }
  }

  onTabChange(idx: number): void { this.currentTab = idx; this.loadData(); }

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

      Text('消息')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
        .maxLines(1).layoutWeight(1)
    }.width('100%').height('100%').padding({ left: 12, right: 16, top: this.statusBarHeight }).backgroundColor(this.accentColor)
  }

  build() {
    NavDestination() {
      Column() {
        SegmentTab({ tabs: ['回复', '私信', '@我'], currentIndex: $currentTab, accentColor: this.accentColor,
          onTabChange: (i: number) => this.onTabChange(i) }) {
          // 三个 tab 内容并列全量渲染，保证 Swiper 恒有 3 页（否则滑动/点击都无法切换）
          this.ReplyList()
          this.PmList()
          this.AtList()
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

  // 回复我的
  @Builder
  ReplyList() {
    if (this.loading && this.currentTab === 0) {
      Column() { LoadingProgress().width(36).height(36).color(this.accentColor) }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.replies.length === 0) {
      this.EmptyView('还没有人回复你')
    } else {
      List({ space: 0 }) {
        ForEach(this.replies, (n: ReplyNotification, idx: number) => {
          ListItem() {
            Column() {
              Text(n.title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).maxLines(1)
              Row() {
                Text(n.author).fontSize(12).fontColor(ThemeColors.textSecondary)
                Text('·').fontSize(12).fontColor(ThemeColors.textHint).margin({ left: 4, right: 4 })
                Text(n.time).fontSize(12).fontColor(ThemeColors.textHint)
              }.margin({ top: 4 })
              if (n.content.length > 0) {
                Text(n.content).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(2).margin({ top: 4 })
              }
            }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => { this.pageInfo.pushPath({ name: 'RuisiTopicDetail', param: new TopicDetailParam(n.tid) }); })
          }.border({ width: { bottom: 0.5 }, color: ThemeColors.border })
        }, (n: ReplyNotification) => 'rep_' + n.id)
      }.width('100%').layoutWeight(1)
    }
  }

  // 私信
  @Builder
  PmList() {
    if (this.loading && this.currentTab === 1) {
      Column() { LoadingProgress().width(36).height(36).color(this.accentColor) }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.pmList.length === 0) {
      this.EmptyView('还没有私信')
    } else {
      List({ space: 0 }) {
        ForEach(this.pmList, (c: PmConversation, idx: number) => {
          ListItem() {
            Row() {
              Stack() {
                if (c.avatar.length > 0) {
                  Image(c.avatar).width(42).height(42).borderRadius(21).objectFit(ImageFit.Cover)
                } else {
                  Text('👤').fontSize(22)
                }
                if (c.unread) {
                  Circle().width(10).height(10).fill('#FF4D4F')
                    .position({ top: 0, right: 0 })
                }
              }.width(42).height(42).margin({ right: 12 })

              Column() {
                Row() {
                  Text(c.username).fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).layoutWeight(1).maxLines(1)
                  Text(c.time).fontSize(12).fontColor(ThemeColors.textHint)
                }
                Text(c.lastMessage).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(1).margin({ top: 4 })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.pageInfo.pushPath({ name: 'RuisiChat', param: new PmParam(c.tuid, c.username) });
            })
          }.border({ width: { bottom: 0.5 }, color: ThemeColors.border })
        }, (c: PmConversation, idx: number) => `pm_${c.tuid}`)
      }.width('100%').layoutWeight(1)
    }
  }

  // @我
  @Builder
  AtList() {
    if (this.loading && this.currentTab === 2) {
      Column() { LoadingProgress().width(36).height(36).color(this.accentColor) }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.atNotifs.length === 0) {
      this.EmptyView('还没有人 @ 你')
    } else {
      List({ space: 0 }) {
        ForEach(this.atNotifs, (n: AtNotification, idx: number) => {
          ListItem() {
            Column() {
              Text(n.title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).maxLines(1)
              Row() {
                Text(n.author).fontSize(12).fontColor(ThemeColors.textSecondary)
                Text('·').fontSize(12).fontColor(ThemeColors.textHint).margin({ left: 4, right: 4 })
                Text(n.time).fontSize(12).fontColor(ThemeColors.textHint)
              }.margin({ top: 4 })
            }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => { this.pageInfo.pushPath({ name: 'RuisiTopicDetail', param: new TopicDetailParam(n.tid) }); })
          }.border({ width: { bottom: 0.5 }, color: ThemeColors.border })
        }, (n: AtNotification) => 'at_' + n.id)
      }.width('100%').layoutWeight(1)
    }
  }

  @Builder
  EmptyView(text: string) {
    Column() {
      Text('💬').fontSize(48).margin({ bottom: 12 })
      Text(text).fontSize(15).fontColor(ThemeColors.textHint)
    }
    .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
}
