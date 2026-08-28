// RuisiTopicItem.ets — 通用帖子列表项（所有帖子列表共用）
// 左列：用户名(加粗)在头像正上方；右列：标题(置顶/分类标签) → 板块名 + 时间 → 回复/查看标签
// 由 RuisiHomePage 的 TopicItem 抽取为公共组件，首页/板块列表/搜索结果等统一复用。

import { ThemeColors } from '../utils/ThemeColors';
import { RuisiConstants, Topic } from '../services/RuisiModels';

@Component
export struct RuisiTopicItem {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  topic: Topic = new Topic();
  onClickTopic: (tid: number) => void = () => {};
  // 点击头像/用户名进入该用户主页（authorId>0 时生效）
  onClickUser: (uid: number, username: string) => void = () => {};

  @Builder
  InfoTag(text: string) {
    Text(text)
      .fontSize(11)
      .fontColor(ThemeColors.textSecondary)
      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
      .borderRadius(4)
      .backgroundColor(ThemeColors.bgInput)
      .margin({ right: 4, top: 2, bottom: 2 })
  }

  build() {
    Row() {
      // 左侧：用户名在头像正上方（头像 + 名字同在左侧列）
      Column() {
        Text(this.topic.author)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeColors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(64)
          .textAlign(TextAlign.Center)
          .margin({ bottom: 4 })

        if (this.topic.authorId > 0) {
          Image(`${RuisiConstants.BASE_URL}/uc2_link/avatar.php?uid=${this.topic.authorId}&size=small`)
            .width(40).height(40).borderRadius(6)
            .alt($r('sys.symbol.person'))
            .objectFit(ImageFit.Cover)
        } else {
          Row() {
            Text('👤').fontSize(20)
          }
          .width(40).height(40).borderRadius(6)
          .backgroundColor(ThemeColors.bgInput)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width(64)
      .alignItems(HorizontalAlign.Center)
      .margin({ right: 12 })
      .onClick(() => {
        if (this.topic.authorId > 0) {
          this.onClickUser(this.topic.authorId, this.topic.author);
        }
      })

      Column() {
        // 标题行（顶部）
        Row() {
          if (this.topic.isStick) {
            Text('置顶')
              .fontSize(10)
              .fontColor('#FFFFFF')
              .backgroundColor('#C62828')
              .borderRadius(3)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .margin({ right: 6 })
          }
          if (this.topic.categoryName.length > 0) {
            Text(this.topic.categoryName)
              .fontSize(10)
              .fontColor(ThemeColors.textSecondary)
              .backgroundColor(ThemeColors.bgInput)
              .borderRadius(3)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .margin({ right: 6 })
          }
          Text(this.topic.title)
            .fontSize(15)
            .fontColor(ThemeColors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        // 元信息行：板块名（左侧） + 时间（右侧）
        Row() {
          if (this.topic.forumName.length > 0) {
            Text(this.topic.forumName)
              .fontSize(11)
              .fontColor(this.accentColor)
              .backgroundColor(ThemeColors.bgInput)
              .borderRadius(3)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .margin({ right: 6 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          if (this.topic.lastReplyTime.length > 0) {
            Text(this.topic.lastReplyTime)
              .fontSize(11)
              .fontColor(ThemeColors.textHint)
              .layoutWeight(1)
              .textAlign(TextAlign.End)
          } else if (this.topic.postTime.length > 0) {
            Text(this.topic.postTime)
              .fontSize(11)
              .fontColor(ThemeColors.textHint)
              .layoutWeight(1)
              .textAlign(TextAlign.End)
          }
        }
        .width('100%')
        .margin({ top: 6 })

        // 底部信息标签行（回复 / 查看）
        Flex({ wrap: FlexWrap.Wrap }) {
          this.InfoTag(this.topic.replies + '回复')
          this.InfoTag(this.topic.views + '查看')
        }
        .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => { this.onClickTopic(this.topic.tid); })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(ThemeColors.bgCard)
  }
}
