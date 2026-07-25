// RuisiSmileyPanel.ets — 论坛内置表情面板（公共组件）
// 发帖页 / 回帖页共用，统一格子尺寸、间距与点击反馈，并内置预加载。
// 对标 Flutter/iOS/Android：别人把表情清单+图片打包进本地资源（离线秒开）；
// 我们走论坛接口（联网），本组件在挂载即预拉清单，并给出加载中/失败占位。

import { ThemeColors } from '../utils/ThemeColors';
import { RuisiSmileyService } from '../services/RuisiSmileyService';
import { Smiley, SmileyCategory } from '../services/RuisiModels';

@Component
export struct RuisiSmileyPanel {
  /** 选中表情短码（{:分类_编号:}）回调，由父页面负责插入对应输入框 */
  onPick: (code: string) => void = () => {};
  /** 选中分类 tab 的高亮色（从 AppStorage 读取，与页面 accent 一致） */
  @StorageProp('accent_color') accentColor: ResourceColor = '#3370FF';

  @State private cats: SmileyCategory[] = [];
  @State private currentCat: string = '';
  @State private loading: boolean = false;
  @State private failed: boolean = false;

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const svc = RuisiSmileyService.getInstance();
    if (!svc.isLoaded()) {
      this.loading = true;
      this.failed = false;
      try {
        await svc.ensureLoaded();
      } catch (e) {
        // ensureLoaded 内部已吞异常，这里仅兜底
      }
      this.loading = false;
      if (!svc.isLoaded()) this.failed = true;
    }
    this.cats = svc.getCategoryList();
    if (this.cats.length > 0 && this.currentCat.length === 0) {
      this.currentCat = this.cats[0].key;
    }
  }

  build() {
    Column() {
      // 分类 tab（横向，无滚动条）
      Scroll() {
        Row() {
          ForEach(this.cats, (item: SmileyCategory) => {
            Text(item.name)
              .fontSize(13).padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(item.key === this.currentCat ? this.accentColor : ThemeColors.bgInput)
              .fontColor(item.key === this.currentCat ? '#FFFFFF' : ThemeColors.textPrimary)
              .margin({ right: 8 })
              .onClick(() => { this.currentCat = item.key; })
          }, (item: SmileyCategory) => `smcat_${item.key}`)
        }.padding({ left: 12, right: 12 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ top: 8 })

      // 内容区
      if (this.loading) {
        Row() {
          LoadingProgress().width(22).height(22)
          Text('表情加载中…').fontSize(12).fontColor(ThemeColors.textHint).margin({ left: 8 })
        }.width('100%').height(200).justifyContent(FlexAlign.Center)
      } else if (this.failed) {
        Text('表情加载失败，请稍后重试')
          .fontSize(12).fontColor(ThemeColors.textHint)
          .width('100%').height(200).textAlign(TextAlign.Center)
      } else {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(RuisiSmileyService.getInstance().getSmilies(this.currentCat), (s: Smiley) => {
              // 外框 48×48 作为点击命中区，内图 40×40 居中，间距 8，避免误触相邻表情
              Stack() {
                Image($rawfile(s.url))
                  .width(40).height(40).objectFit(ImageFit.Contain).borderRadius(4)
              }
              .width(48).height(48)
              .alignContent(Alignment.Center)
              .borderRadius(6)
              .backgroundColor(ThemeColors.bgInput)
              .onClick(() => { this.onPick(s.code); })
              .margin({ right: 8, bottom: 8 })
            }, (s: Smiley) => `smiley_${s.code}`)
          }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
        .scrollable(ScrollDirection.Vertical)
        .width('100%')
        .height(200)
      }
    }
    .width('100%')
    .backgroundColor(ThemeColors.bgCard)
    .border({ width: { top: 0.5 }, color: ThemeColors.border })
  }
}
