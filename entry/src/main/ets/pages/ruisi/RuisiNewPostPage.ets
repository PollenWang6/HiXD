// RuisiNewPostPage.ets — 发帖
// 对标 Flutter new_post_page.dart：板块选择 + 主题分类 + 标题 + 内容 + 表情 + 图片附件

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import {
  PostPageMeta, RuisiAttachment, Forum, ForumGroup, ForumTypeOption
} from '../../services/RuisiModels';
import { RuisiAttachmentUtil, ruisiInsertAtCaret } from '../../services/RuisiAttachmentUtil';
import { RuisiSmileyService } from '../../services/RuisiSmileyService';
import { RuisiSmileyPanel } from '../../components/RuisiSmileyPanel';
import { ToastUtil } from '../../utils/ToastUtil';

@Component
export struct RuisiNewPostPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  // 从板块内进入发帖时，由外部传入预选中的板块（fid / 名称）
  initFid: number = 0;
  initForumName: string = '';

  @State fid: number = 0;
  @State forumName: string = '请选择板块';
  @State forums: ForumGroup[] = [];
  @State flatForums: Forum[] = [];
  @State meta: PostPageMeta | null = null;
  @State subject: string = '';
  @State content: string = '';
  @State selectedTypeId: number = 0;
  @State typeName: string = '无';
  @State attachments: RuisiAttachment[] = [];
  @State uploading: boolean = false;
  @State posting: boolean = false;
  @State showEmoji: boolean = false;
  contentController: TextAreaController = new TextAreaController();
  contentSelStart: number = 0;

  aboutToAppear(): void {
    this.loadForums().then(() => {
      // 从板块内进入：预选中对应板块并自动加载主题分类
      if (this.initFid > 0) {
        const idx = this.flatForums.findIndex((f: Forum) => f.fid === this.initFid);
        if (idx >= 0) {
          this.onForumSelected(idx);
        } else {
          // 板块列表未收录该板块（兜底），直接按 fid 加载
          this.fid = this.initFid;
          this.forumName = this.initForumName || '板块';
          this.loadMeta(this.initFid);
        }
      }
    });
    RuisiSmileyService.getInstance().ensureLoaded();
  }

  async loadForums(): Promise<void> {
    try {
      const api = RuisiApiService.getInstance();
      const groups = await api.getForumList();
      this.forums = groups;
      const flat: Forum[] = [];
      for (const g of groups) {
        for (const f of g.forums) flat.push(f);
      }
      this.flatForums = flat;
    } catch (e) {}
  }

  async onForumSelected(idx: number): Promise<void> {
    if (idx < 0 || idx >= this.flatForums.length) return;
    const f = this.flatForums[idx];
    this.fid = f.fid;
    this.forumName = f.name;
    await this.loadMeta(f.fid);
  }

  async loadMeta(fid: number): Promise<void> {
    try {
      const api = RuisiApiService.getInstance();
      this.meta = await api.getNewPostPageMeta(fid);
      if (this.meta && this.meta.typeOptions.length > 0) {
        this.selectedTypeId = this.meta.typeOptions[0].id;
        this.typeName = this.meta.typeOptions[0].name;
      } else {
        this.selectedTypeId = 0;
        this.typeName = '无';
      }
    } catch (e) {}
  }

  // 板块下拉选项（无占位项，未选时下拉框留空）
  private getBoardSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (const f of this.flatForums) opts.push({ value: f.name });
    return opts;
  }

  private getBoardSelectedIndex(): number {
    if (this.fid === 0) return -1;
    const idx = this.flatForums.findIndex((f: Forum) => f.fid === this.fid);
    return idx >= 0 ? idx : -1;
  }

  private onBoardSelect(idx: number): void {
    if (idx < 0 || idx >= this.flatForums.length) return;
    this.onForumSelected(idx);
  }

  // 主题分类下拉选项（不保留占位项，默认选中第一项）
  private getTypeSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    if (this.meta) {
      for (const o of this.meta.typeOptions) opts.push({ value: o.name });
    }
    return opts;
  }

  private getTypeSelectedIndex(): number {
    if (!this.meta || this.meta.typeOptions.length === 0) return 0;
    const idx = this.meta.typeOptions.findIndex((o: ForumTypeOption) => o.id === this.selectedTypeId);
    return idx >= 0 ? idx : 0;
  }

  private onTypeSelect(idx: number): void {
    if (idx < 0 || !this.meta || idx >= this.meta.typeOptions.length) return;
    const o = this.meta.typeOptions[idx];
    this.selectedTypeId = o.id;
    this.typeName = o.name;
  }

  async pickImage(): Promise<void> {
    if (this.fid === 0) { ToastUtil.show('请先选择板块'); return; }
    if (this.attachments.length >= 9) { ToastUtil.show('最多附加 9 张图片'); return; }
    this.uploading = true;
    try {
      const r = await RuisiAttachmentUtil.pickAndUpload(this.fid);
      if (r.success && r.aid.length > 0) {
        const att = new RuisiAttachment();
        att.aid = r.aid;
        att.url = r.url;
        att.name = '图片' + (this.attachments.length + 1);
        this.attachments.push(att);
      } else {
        ToastUtil.show(r.message || '图片上传失败');
      }
    } finally { this.uploading = false; }
  }

  removeAttachment(idx: number): void {
    this.attachments.splice(idx, 1);
  }

  async doPost(): Promise<void> {
    if (this.fid === 0) { ToastUtil.show('请选择板块'); return; }
    if (this.subject.trim().length === 0) { ToastUtil.show('请输入标题'); return; }
    if (this.content.trim().length === 0) { ToastUtil.show('请输入内容'); return; }
    this.posting = true;
    try {
      const api = RuisiApiService.getInstance();
      const aids = this.attachments.map((a: RuisiAttachment) => a.aid);
      const result = await api.newThread(
        this.fid,
        this.subject.trim(),
        this.content.trim(),
        this.selectedTypeId > 0 ? this.selectedTypeId : undefined,
        undefined,
        aids
      );
      if (result.success) {
        ToastUtil.show('发帖成功');
        this.pageInfo.pop();
      } else {
        ToastUtil.show(result.message);
      }
    } finally { this.posting = false; }
  }

  @Builder
  headerBuilder() {
    Row() {
      // 圆形返回键（与其他子页面一致）
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(this.accentTextColor())
          .draggable(false)
      }
      .height(40).width(40)
      .onClick(() => { this.pageInfo.pop(); })

      Text('发帖')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)

      // 发布按钮：胶囊样式 + 纸飞机图标，明显区别于标题文字（反色高对比）
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.NORMAL }) {
        Row() {
          if (this.posting) {
            LoadingProgress().width(18).height(18).color(this.isDark ? this.accentTextColor() : this.accentColor)
          } else {
            Image($r('app.media.paperplane_right_fill'))
              .width(18).height(18)
              .fillColor(this.isDark ? this.accentTextColor() : this.accentColor)
              .draggable(false)
            Text('发布')
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.isDark ? this.accentTextColor() : this.accentColor)
              .margin({ left: 4 })
          }
        }
        .padding({ left: 12, right: 12 })
      }
      .height(36)
      .backgroundColor(this.isDark ? 'rgba(255,255,255,0.18)' : this.accentTextColor())
      .borderRadius(18)
      .enabled(!this.posting)
      .onClick(() => { this.doPost(); })
    }
    .width('100%').height('100%')
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
      .backgroundColor(this.accentColor)
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(13).fontColor(ThemeColors.textSecondary)
      .margin({ left: 2, bottom: 8 })
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            // 板块内发帖：板块已确定，仅展示「发布到」提示
            if (this.initFid > 0) {
              this.fieldLabel('发布到')
              Row() {
                Text(this.forumName)
                  .fontSize(15).fontColor(ThemeColors.textPrimary).fontWeight(FontWeight.Medium)
                  .layoutWeight(1).textAlign(TextAlign.Start)
              }
              .width('100%').height(48).padding({ left: 14, right: 14 })
              .backgroundColor(ThemeColors.bgInput).borderRadius(10)
              .border({ width: 1, color: ThemeColors.border })
              .margin({ bottom: 16 })
            } else {
              // 通用发帖：板块下拉（带边框 Outline 风格，左对齐顶格）
              this.fieldLabel('板块')
              Select(this.getBoardSelectOptions())
                .value(this.fid > 0 ? this.forumName : '')
                .selected(this.getBoardSelectedIndex())
                .onSelect((idx: number) => { this.onBoardSelect(idx); })
                .width('100%').height(48)
                .backgroundColor(ThemeColors.bgInput)
                .border({ width: 1, color: ThemeColors.border }).borderRadius(10)
                .margin({ bottom: 16 })
            }

            // 主题分类（部分板块有）
            if (this.meta && this.meta.typeOptions.length > 0) {
              this.fieldLabel('主题分类')
              Select(this.getTypeSelectOptions())
                .value(this.typeName)
                .selected(this.getTypeSelectedIndex())
                .onSelect((idx: number) => { this.onTypeSelect(idx); })
                .width('100%').height(48)
                .backgroundColor(ThemeColors.bgInput)
                .border({ width: 1, color: ThemeColors.border }).borderRadius(10)
                .margin({ bottom: 16 })
            }

            // 标题
            this.fieldLabel('标题')
            TextInput({ text: this.subject, placeholder: '请输入标题' })
              .width('100%').height(48)
              .fontSize(15).fontColor(ThemeColors.textPrimary).textAlign(TextAlign.Start)
              .backgroundColor(ThemeColors.bgInput)
              .border({ width: 1, color: ThemeColors.border }).borderRadius(10)
              .padding({ left: 14, right: 14 })
              .margin({ bottom: 16 })
              .onChange((v: string) => { this.subject = v; })

            // 内容
            this.fieldLabel('内容')
            TextArea({ text: this.content, placeholder: '说点什么...', controller: this.contentController })
              .width('100%').height(220)
              .fontSize(14).fontColor(ThemeColors.textPrimary).textAlign(TextAlign.Start)
              .backgroundColor(ThemeColors.bgInput)
              .border({ width: 1, color: ThemeColors.border }).borderRadius(10)
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .margin({ bottom: 16 })
              .onChange((v: string) => { this.content = v; })
              .onTextSelectionChange((start: number, end: number) => { this.contentSelStart = start; })

            // 已选图片缩略图
            if (this.attachments.length > 0) {
              Row() {
                ForEach(this.attachments, (att: RuisiAttachment, idx: number) => {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    if (att.url.length > 0) {
                      Image(att.url).width(72).height(72).borderRadius(10).objectFit(ImageFit.Cover)
                    } else {
                      Text(att.name).width(72).height(72).borderRadius(10)
                        .backgroundColor(ThemeColors.bgInput).fontSize(11).textAlign(TextAlign.Center)
                    }
                    Text('✕').fontSize(12).fontColor('#FFFFFF')
                      .backgroundColor('rgba(0,0,0,0.5)').borderRadius(10).width(20).height(20)
                      .textAlign(TextAlign.Center)
                      .onClick(() => { this.removeAttachment(idx); })
                  }.width(72).height(72).margin({ right: 8 })
                }, (att: RuisiAttachment) => 'post_att_' + att.aid)
              }.width('100%').margin({ bottom: 16 }).justifyContent(FlexAlign.Start)
            }

            // 工具栏：表情 / 图片（带圆角背景的按钮，左对齐）
            Row() {
              Row({ space: 6 }) {
                Text('😊').fontSize(18)
              }
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor(ThemeColors.bgInput).borderRadius(20)
              .onClick(() => { this.showEmoji = !this.showEmoji; })

              Row({ space: 6 }) {
                if (this.uploading) {
                  LoadingProgress().width(18).height(18)
                } else {
                  Text('🖼️').fontSize(18)
                }
              }
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor(ThemeColors.bgInput).borderRadius(20)
              .margin({ left: 10 })
              .onClick(() => { this.pickImage(); })

              Blank()
              Text(this.attachments.length + '/9').fontSize(12).fontColor(ThemeColors.textHint)
            }.width('100%').margin({ bottom: 8 })

            // 论坛内置表情面板（公共组件，与回帖页一致）
            if (this.showEmoji) {
              RuisiSmileyPanel({
                onPick: (code: string) => {
                  this.content = ruisiInsertAtCaret(this.contentController, this.content, this.contentSelStart, code);
                }
              })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(16)
        }
        .layoutWeight(1)
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
