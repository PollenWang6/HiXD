// RuisiChatPage.ets — 私信对话详情
// 对齐 Android ChatActivity / iOS ChatViewController：左右气泡 + 发送框

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import { ChatMessage, PmParam, RuisiConstants } from '../../services/RuisiModels';
import { RuisiService } from '../../services/RuisiService';
import { ToastUtil } from '../../utils/ToastUtil';

@Component
export struct RuisiChatPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  tuid: number = 0;
  username: string = '';
  @State messages: ChatMessage[] = [];
  @State loading: boolean = false;
  @State sending: boolean = false;
  @State inputText: string = '';
  private replyUrl: string = '';
  private myAvatar: string = '';
  private listScroller: ListScroller = new ListScroller();

  aboutToAppear(): void {
    const svc = RuisiService.getInstance();
    const myUid = svc.getUid();
    if (myUid > 0) {
      this.myAvatar = `${RuisiConstants.BASE_URL}/uc2_link/avatar.php?uid=${myUid}&size=small`;
    }
    this.loadMessages();
  }

  async loadMessages(): Promise<void> {
    if (this.tuid === 0) return;
    this.loading = true;
    try {
      const api = RuisiApiService.getInstance();
      const res = await api.getChatDetail(this.tuid);
      this.messages = res.messages;
      this.replyUrl = res.replyUrl;
      if (this.messages.length > 0) {
        this.listScroller.scrollToIndex(this.messages.length - 1, false);
      }
    } catch (e) {
      ToastUtil.show('加载失败');
    } finally {
      this.loading = false;
    }
  }

  async onSend(): Promise<void> {
    const text = this.inputText.trim();
    if (text.length === 0) {
      ToastUtil.show('你还没写内容呢');
      return;
    }
    if (this.sending) return;
    this.sending = true;
    try {
      const api = RuisiApiService.getInstance();
      const r = await api.sendPm(this.tuid, text, this.replyUrl);
      if (r.success) {
        const m = new ChatMessage();
        m.isMe = true;
        m.content = text;
        m.time = '刚刚';
        m.avatar = this.myAvatar;
        this.messages.push(m);
        this.inputText = '';
        this.listScroller.scrollToIndex(this.messages.length - 1, false);
      } else {
        ToastUtil.show(r.message || '发送失败');
      }
    } catch (e) {
      ToastUtil.show('发送失败');
    } finally {
      this.sending = false;
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

      Text(this.username)
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
        .maxLines(1).layoutWeight(1)
    }.width('100%').height('100%').padding({ left: 12, right: 16, top: this.statusBarHeight }).backgroundColor(this.accentColor)
  }

  @Builder
  MessageRow(m: ChatMessage) {
    Row() {
      if (!m.isMe) {
        if (m.avatar.length > 0) {
          Image(m.avatar).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover)
            .margin({ right: 8 })
        } else {
          Text('👤').fontSize(18)
            .margin({ right: 8 })
        }
      }
      Text(m.content)
        .fontSize(15)
        .fontColor(m.isMe ? '#FFFFFF' : ThemeColors.textPrimary)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(m.isMe ? this.accentColor : ThemeColors.bgCard)
        .borderRadius(12)
        .constraintSize({ maxWidth: '72%' })
        .textAlign(TextAlign.Start)

      if (m.isMe) {
        if (this.myAvatar.length > 0) {
          Image(this.myAvatar).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover)
            .margin({ left: 8 })
        } else {
          Text('👤').fontSize(18)
            .margin({ left: 8 })
        }
      }
    }
    .width('100%')
    .justifyContent(m.isMe ? FlexAlign.End : FlexAlign.Start)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  build() {
    NavDestination() {
      Column() {
        if (this.loading && this.messages.length === 0) {
          Column() { LoadingProgress().width(36).height(36).color(this.accentColor) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.messages.length === 0) {
          Column() {
            Text('💬').fontSize(48).margin({ bottom: 12 })
            Text('还没有消息，发一条吧')
              .fontSize(15).fontColor(ThemeColors.textHint)
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          List({ scroller: this.listScroller, space: 0 }) {
            ForEach(this.messages, (m: ChatMessage, idx: number) => {
              ListItem() { this.MessageRow(m) }
            }, (m: ChatMessage) => 'chat_' + (m.isMe ? 1 : 0) + '_' + m.time + '_' + m.content)
          }
          .width('100%').layoutWeight(1)
          .backgroundColor(ThemeColors.bgPage)
        }

        // 发送栏
        Row() {
          TextInput({ placeholder: '发送私信', text: this.inputText })
            .backgroundColor(ThemeColors.bgInput)
            .borderRadius(20)
            .height(40)
            .layoutWeight(1)
            .onChange((v: string) => { this.inputText = v; })
          Button('发送')
            .height(40)
            .borderRadius(20)
            .backgroundColor(this.accentColor)
            .fontColor(this.accentTextColor())
            .enabled(!this.sending)
            .margin({ left: 8 })
            .onClick(() => { this.onSend(); })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(ThemeColors.bgPage)
        .border({ width: { top: 0.5 }, color: ThemeColors.border })
      }
      .width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .title({ builder: this.headerBuilder(), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
