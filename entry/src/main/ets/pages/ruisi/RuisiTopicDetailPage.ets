// RuisiTopicDetailPage.ets — 帖子详情（楼层、图片、回复）
// 对标 Flutter topic_detail_page.dart: 标题区 + 楼层列表 + 分页 + 回复输入

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import { TopicDetail, Post, RuisiFileAttachment, RuisiConstants, RuisiAttachment, UserParam } from '../../services/RuisiModels';
import { RuisiAttachmentUtil, ruisiInsertAtCaret } from '../../services/RuisiAttachmentUtil';
import { RuisiSmileyService } from '../../services/RuisiSmileyService';
import { RuisiSmileyPanel } from '../../components/RuisiSmileyPanel';
import { ToastUtil } from '../../utils/ToastUtil';
import { HttpUtil } from '../../utils/HttpUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { curves, window, KeyboardAvoidMode } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';

const TAG = 'RuisiTopicDetailPage';

// 帖子内容分段：文本/表情/引用/链接（cleanContent 转换标记）
class ContentSegment {
  type: string = 'text';   // 'text' | 'smile' | 'quote' | 'link' | 'image'
  value: string = '';      // text=文字 / smile=表情资源相对路径 / image=图片URL
  url: string = '';        // 仅 link 类型使用
  aid: number = 0;         // 仅 image 类型使用，作 ForEach 稳定 key
}

// 渲染分组：连续的"非图片"段合并成一个 Text（表情内联在句子中间），
// 图片段单独成块（用块级 Image 组件，保证网络图按比例正常显示，且位置紧跟对应文字）。
class ContentRun {
  isImage: boolean = false;       // true=块级图片；false=文本块（含内联表情/引用/链接）
  imageUrl: string = '';          // 仅 isImage 使用
  segments: ContentSegment[] = []; // 仅文本块使用
  imageIndex: number = -1;        // 仅 isImage 使用：该图在整帖图片列表中的下标（用于全屏左右切换）
}

// 帖子内联图片：ArkUI 的 Image 若不显式给高度会塌成 0 高度导致不显示；
// 故用 width('100%') + 初始高度占位，加载完成后用 onComplete 拿到的真实宽高比
// 反算高度（限幅 120~480），既全宽又不变形，对齐安卓/iOS 富文本按原始比例内联图片。
@Component
struct RuisiPostImageView {
  imageUrl: string = '';
  onPreview: () => void = () => {};
  onLongPress: () => void = () => {};
  @State private imgH: number = 200;

  build() {
    Image(this.imageUrl)
      .width('100%')
      .height(this.imgH)
      .objectFit(ImageFit.Contain)
      .borderRadius(8)
      .onClick(() => { this.onPreview(); })
      .gesture(LongPressGesture().onAction(() => { this.onLongPress(); }))
      .onComplete((res: ImageLoadResult) => {
        const cw = res.componentWidth;
        if (cw > 0 && res.width > 0 && res.height > 0) {
          let nh = cw * res.height / res.width;
          if (nh > 480) nh = 480;
          if (nh < 120) nh = 120;
          this.imgH = nh;
        }
      })
  }
}

@Component
export struct RuisiTopicDetailPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();
  private context = getContext(this) as common.UIAbilityContext;

  private accentTextColor(): Color { return AccentColors.textContrast; }

  private doShare(): void {
    if (!this.detail) return;
    const title = this.detail.title;
    const url = `https://rs.xidian.edu.cn/forum.php?mod=viewthread&tid=${this.tid}`;
    try {
      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: `${title}\n${url}`,
        title: title,
      });
      const controller = new systemShare.ShareController(shareData);
      controller.show(this.context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL,
      });
    } catch (e) {
      ToastUtil.show('分享失败');
    }
  }

  @State tid: number = 0;
  @State detail: TopicDetail | null = null;
  @State loading: boolean = false;
  @State loadingMore: boolean = false;
  @State page: number = 1;
  private scroller: ListScroller = new ListScroller();
  @State replyText: string = '';
  @State replying: boolean = false;
  @State showReplyInput: boolean = false;
  @State replyAttachments: RuisiAttachment[] = [];
  @State replyUploading: boolean = false;
  @State showReplyEmoji: boolean = false;
  // 帖子图片全屏预览：点图进全屏、再点退出；空串表示未预览
  @State previewImageUrl: string = '';
  // 图集：当前帖子所有图片 URL（按正文出现顺序），用于全屏左右切换
  @State previewImages: string[] = [];
  @State previewIndex: number = 0;        // 当前预览的是第几张（0-based）
  // 全屏预览缩放/平移状态
  @State previewScale: number = 1;
  @State previewPinchBase: number = 1;
  @State previewOffsetX: number = 0;
  @State previewOffsetY: number = 0;
  private previewTapTimer: number = -1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  // 长按图片后弹出的「保存到相册」操作表（内含 SaveButton 安全控件）
  @State showSaveSheet: boolean = false;
  @State saveSheetUrl: string = '';
  replyController: TextAreaController = new TextAreaController();
  replySelStart: number = 0;

  // 举报：自管理底部弹层（规避 bindSheet 关闭后无法再次打开的问题），用 @State + if 渲染
  @State showReportSheet: boolean = false;
  @State reportReasons: string[] = [];        // 论坛动态理由（睿思为单个确认项文案）
  @State reportReasonIndex: number = 0;      // 选中的理由下标
  @State reportMessage: string = '';
  @State reportTargetPid: number = 0;   // 举报目标楼层 pid（恒 >0，对应 Discuz 帖子回复 rid）
  @State reportFormhash: string = '';
  @State reportSubmitting: boolean = false;

  // 软键盘避让：键盘弹起时把回复栏整体抬到键盘上方（手动控制，避免系统避让与手动逻辑"跳两次"）
  @State keyboardOffset: number = 0;            // 回复栏底部间距(vp)，等于键盘高度
  private keyboardListener: (height: number) => void = () => {};


  // 悬浮回复按钮：玻璃质感 + 智感握持 + 换手动画（与首页发帖 FAB 三件套一致）
  @State isLeftHand: boolean = false;
  @State fabTranslateX: number = 0;        // 正值靠右，负值滑到左侧
  private fabInitialized: boolean = false;
  private screenWidth: number = 360;       // 屏幕宽度(vp)，onAreaChange 更新

  aboutToAppear(): void {
    this.loadDetail();
    RuisiSmileyService.getInstance().ensureLoaded();
    this.startHoldingHandDetection();
    this.setupKeyboardAvoid();
  }

  aboutToDisappear(): void {
    try {
      motion.off('holdingHandChanged');
    } catch (e) {
      // ignore
    }
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
    } catch (e) {
      // ignore
    }
    try {
      window.getLastWindow(this.getUIContext().getHostContext()).then((win: window.Window) => {
        win.off('keyboardHeightChange', this.keyboardListener);
      }).catch(() => {});
    } catch (e) {
      // ignore
    }
    // 若仍在全屏预览，离开页面时确保恢复系统栏（避免退出 App 后系统栏仍隐藏）
    try {
      this.setImmersive(false);
    } catch (e) {
      // ignore
    }
  }

  // 软键盘避让：关掉系统自动避让(NONE)，改为手动监听键盘高度，给回复栏加等高的底部间距并平滑上移
  private setupKeyboardAvoid(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    } catch (e) {
      // ignore
    }
    try {
      window.getLastWindow(this.getUIContext().getHostContext()).then((win: window.Window) => {
        this.keyboardListener = (height: number) => {
          const offsetVp: number = height > 0 ? this.getUIContext().px2vp(height) : 0;
          animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
            this.keyboardOffset = offsetVp;
          });
        };
        win.on('keyboardHeightChange', this.keyboardListener);
      }).catch(() => {});
    } catch (e) {
      // ignore
    }
  }


  // 智感握持：监听设备感知到的左右手持握，自动切换回复按钮到对应侧
  private startHoldingHandDetection(): void {
    try {
      motion.on('holdingHandChanged', (data: number) => {
        const wasLeft = this.isLeftHand;
        this.isLeftHand = (data === 1 || data === 3);
        if (wasLeft !== this.isLeftHand) {
          this.animateFab();
        }
      });
    } catch (err) {
      const e = err as BusinessError;
      if (e.code === 801) {
        // 设备不支持智感握持，默认右手（右侧）即可
      }
      this.isLeftHand = false;
    }
  }

  private animateFab(): void {
    if (!this.fabInitialized) return;
    // 右手：translateX=0（Stack.BottomEnd 右侧）；左手：滑到左侧
    const targetX = this.isLeftHand ? -(this.screenWidth - 80) : 0;
    animateTo({ duration: 400, curve: curves.springMotion(0.45, 0.85) }, () => {
      this.fabTranslateX = targetX;
    });
  }

  async loadDetail(reset: boolean = true): Promise<void> {
    if (reset) {
      this.page = 1;
      this.loading = true;
    } else {
      if (this.loading || this.loadingMore) return;
      this.loadingMore = true;
    }
    try {
      const api = RuisiApiService.getInstance();
      const d = await api.getTopicDetail(this.tid, this.page);
      if (d) {
        if (reset || !this.detail) {
          this.detail = d;
        } else {
          // 下滑加载：保留首帖/标题，仅把后续页的楼层追加到列表尾部
          const cur = this.detail;
          cur.posts = cur.posts.concat(d.posts);
          cur.totalPages = d.totalPages;
          cur.currentPage = d.currentPage;
        }
        // 楼层号按全局位置连续编号：帖子按页顺序追加，下标即真实绝对楼层（1,2,3…），
        // 规避「每页本地计数重置→9→1→21」。等价于安卓/iOS 从 HTML 取到的服务端绝对楼层。
        const ps = this.detail.posts;
        for (let i = 0; i < ps.length; i++) {
          ps[i].floor = i + 1;
          ps[i].index = i + 1;
        }
      }
    } catch (e) {
      ToastUtil.show('加载失败');
    } finally {
      this.loading = false;
      this.loadingMore = false;
    }
  }

  async doReply(): Promise<void> {
    if (this.replyText.trim().length === 0) { ToastUtil.show('请输入回复内容'); return; }
    if (!this.detail) return;
    this.replying = true;
    try {
      const api = RuisiApiService.getInstance();
      const aids = this.replyAttachments.map((a: RuisiAttachment) => a.aid);
      const result = await api.reply(this.tid, this.detail.fid, this.replyText, aids);
      if (result.success) {
        ToastUtil.show('回复成功');
        this.replyText = '';
        this.replyAttachments = [];
        this.showReplyInput = false;
        this.showReplyEmoji = false;
        this.loadDetail();
      } else {
        ToastUtil.show(result.message);
      }
    } finally { this.replying = false; }
  }

  // 从相册选图并上传，作为回复附件（参照 Flutter 回复亦可带图）
  async pickReplyImage(): Promise<void> {
    if (!this.detail) return;
    if (this.replyAttachments.length >= 9) { ToastUtil.show('最多附加 9 张图片'); return; }
    this.replyUploading = true;
    try {
      const r = await RuisiAttachmentUtil.pickAndUpload(this.detail.fid);
      if (r.success && r.aid.length > 0) {
        const att = new RuisiAttachment();
        att.aid = r.aid;
        att.url = r.url;
        att.name = '图片' + (this.replyAttachments.length + 1);
        this.replyAttachments.push(att);
      } else {
        ToastUtil.show(r.message || '图片上传失败');
      }
    } finally { this.replyUploading = false; }
  }

  removeReplyAttachment(idx: number): void {
    this.replyAttachments.splice(idx, 1);
  }

  // 真正执行存图：必须在 SaveButton 安全控件的 onClick 内调用（点击瞬间系统临时授予 WRITE_IMAGEVIDEO）
  // 普通三方应用不能声明该权限，故用 SaveButton 代替运行时权限申请
  async doSaveImage(url: string): Promise<void> {
    if (url.length === 0) return;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const buf: ArrayBuffer = await HttpUtil.getInstance().getArrayBuffer(url);
      const ext: string = this.imageExtFromUrl(url);

      const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const uri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, ext);
      const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      try {
        // writeSync 只接受 ArrayBuffer | string，必须直接传 ArrayBuffer（不能包成 Uint8Array）
        fileIo.writeSync(file.fd, buf);
      } finally {
        fileIo.closeSync(file);
      }
      ToastUtil.show('已保存到相册');
    } catch (e) {
      ToastUtil.show('保存失败');
    }
  }

  // 长按图片弹出的「保存到相册」操作表内容（SaveButton 安全控件，点击即获临时写相册权限）
  @Builder
  saveSheetBuilder() {
    Column() {
      SaveButton({ text: SaveDescription.SAVE_TO_GALLERY })
        .width(200).height(40)
        .onClick((event: ClickEvent) => {
          this.doSaveImage(this.saveSheetUrl);
          this.showSaveSheet = false;
        })
      Button('取消', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .margin({ top: 12 })
        .onClick(() => { this.showSaveSheet = false; })
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
  }

  // 打开举报面板：按真实协议动态拉取举报表单（rtype/rid/fid/tid）
  async openReport(targetPid: number): Promise<void> {
    if (!this.detail) return;
    this.reportTargetPid = targetPid;
    this.reportReasons = [];
    this.reportReasonIndex = 0;
    this.reportMessage = '';
    this.reportSubmitting = false;
    this.showReportSheet = true;
    try {
      const api = RuisiApiService.getInstance();
      const rtype = 'post';
      const rid = targetPid;
      const form = await api.getReportForm(rtype, rid, this.tid, this.detail.fid);
      this.reportReasons = form.reasons;
      this.reportFormhash = form.formhash;
      if (this.reportReasons.length > 0) this.reportReasonIndex = 0;
    } catch (e) {
      // 不阻塞面板：理由为空时提交仍可带空 report_select
    }
  }

  // 关闭举报面板并重置状态（自管理弹层，确保可重复打开）
  closeReport(): void {
    this.showReportSheet = false;
    this.reportReasons = [];
    this.reportReasonIndex = 0;
    this.reportMessage = '';
    this.reportTargetPid = 0;
    this.reportFormhash = '';
    this.reportSubmitting = false;
  }

  // 提交举报（真实协议）
  async doSubmitReport(): Promise<void> {
    const rtype = 'post';
    const rid = this.reportTargetPid;
    const reason = this.reportReasons.length > 0
      ? this.reportReasons[this.reportReasonIndex]
      : '';
    if (this.reportReasons.length > 0 && (this.reportReasonIndex < 0 || this.reportReasonIndex >= this.reportReasons.length)) {
      ToastUtil.show('请选择举报理由');
      return;
    }
    this.reportSubmitting = true;
    try {
      const detail = this.detail;
      if (!detail) {
        ToastUtil.show('页面数据丢失，请重试');
        return;
      }
      const api = RuisiApiService.getInstance();
      const r = await api.submitReport(
        rtype,
        rid,
        this.tid,
        detail.fid,
        reason,
        this.reportMessage,
        this.reportFormhash
      );
      ToastUtil.show(r.message);
      if (r.success) this.closeReport();
    } finally {
      this.reportSubmitting = false;
    }
  }

  // 举报面板（自管理底部弹层，规避 bindSheet 关闭后无法再次打开的问题）
  @Builder
  reportOverlayBuilder() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 半透明遮罩，点按关闭
      Column()
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => { this.closeReport(); })

      // 底部面板
      Column() {
        // 标题栏 + 关闭
        Row() {
          Text('举报该楼层')
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            .layoutWeight(1)
          Image($r('app.media.close'))
            .width(22).height(22).fillColor(ThemeColors.textSecondary).draggable(false)
            .onClick(() => { this.closeReport(); })
        }
        .width('100%')
        .padding({ left: 16, right: 12, top: 16, bottom: 12 })

        // 内容滚动区
        Scroll() {
          Column() {
            // 论坛确认项 / 理由（睿思为单条确认文案；多理由时可选）
            if (this.reportReasons.length === 1) {
              Row() {
                Text('⚠️').fontSize(14)
                Text(this.reportReasons[0])
                  .fontSize(14).fontColor(ThemeColors.textPrimary)
                  .layoutWeight(1).margin({ left: 6 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor(ThemeColors.bgInput)
              .borderRadius(8)
              .margin({ bottom: 12 })
            } else if (this.reportReasons.length > 1) {
              Column() {
                ForEach(this.reportReasons, (r: string, i: number) => {
                  Row() {
                    Text(r)
                      .fontSize(14).fontColor(ThemeColors.textPrimary)
                      .layoutWeight(1)
                    if (this.reportReasonIndex === i) {
                      Text('✓').fontSize(16).fontColor(this.accentColor)
                    }
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 12, bottom: 12 })
                  .backgroundColor(this.reportReasonIndex === i ? ThemeColors.bgInput : Color.Transparent)
                  .borderRadius(8)
                  .onClick(() => { this.reportReasonIndex = i; })
                }, (r: string) => 'rep_' + r)
              }
              .margin({ bottom: 12 })
            } else {
              Text('提交后由版主核实处理，感谢你的反馈')
                .fontSize(13).fontColor(ThemeColors.textSecondary)
                .margin({ bottom: 12 })
            }

            Text('举报说明（选填）')
              .fontSize(13).fontColor(ThemeColors.textSecondary)
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 6 })
            TextArea({ text: this.reportMessage, placeholder: '请描述具体违规情况' })
              .fontSize(14).fontColor(ThemeColors.textPrimary)
              .backgroundColor(ThemeColors.bgInput)
              .borderRadius(8).height(84)
              .onChange((v: string) => { this.reportMessage = v; })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4 })
        }
        .constraintSize({ maxHeight: '55%' })

        // 按钮行
        Row() {
          Button('取消')
            .layoutWeight(1).height(44).borderRadius(22)
            .backgroundColor(ThemeColors.bgInput)
            .fontColor(ThemeColors.textPrimary)
            .margin({ right: 8 })
            .onClick(() => { this.closeReport(); })
          Button(this.reportSubmitting ? '提交中...' : '提交举报')
            .layoutWeight(1).height(44).borderRadius(22)
            .backgroundColor(this.accentColor)
            .fontColor(this.accentTextColor())
            .enabled(!this.reportSubmitting)
            .onClick(() => { this.doSubmitReport(); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .width('100%')
      .backgroundColor(ThemeColors.bgCard)
      .borderRadius({ topLeft: 16, topRight: 16 })
      .constraintSize({ maxHeight: '88%' })
    }
    .width('100%').height('100%')
    .position({ top: 0, left: 0 })
    .zIndex(300)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  // 从图片 URL 推断相册写入时用的扩展名（jpg/png/gif/bmp/webp/heic）
  private imageExtFromUrl(url: string): string {
    const seg: string = url.split('?')[0];
    const dot: number = seg.lastIndexOf('.');
    if (dot > 0) {
      const e: string = seg.substring(dot + 1).toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic'].includes(e)) {
        return e === 'jpeg' ? 'jpg' : e;
      }
    }
    return 'jpg';
  }

  // 全屏预览：单点退出 / 双击放大（250ms 内第二次点击判定为双击）
  private handlePreviewTap(): void {
    if (this.previewTapTimer !== -1) {
      // 第二次点击在窗口内 → 取消即将执行的关闭，改为切换缩放
      clearTimeout(this.previewTapTimer);
      this.previewTapTimer = -1;
      this.togglePreviewZoom();
      return;
    }
    this.previewTapTimer = setTimeout(() => {
      this.previewTapTimer = -1;
      this.closePreview();
    }, 250);
  }

  // 双击在 1 倍与 2.5 倍之间切换
  private togglePreviewZoom(): void {
    if (this.previewScale > 1.05) {
      this.previewScale = 1;
      this.previewPinchBase = 1;
      this.previewOffsetX = 0;
      this.previewOffsetY = 0;
    } else {
      this.previewScale = 2.5;
      this.previewPinchBase = 2.5;
    }
  }

  // 限制缩放范围 1~3 倍；回到 1 倍时复位平移
  private clampPreviewScale(): void {
    if (this.previewScale > 3) {
      this.previewScale = 3;
      this.previewPinchBase = 3;
    }
    if (this.previewScale < 1) {
      this.previewScale = 1;
      this.previewPinchBase = 1;
      this.previewOffsetX = 0;
      this.previewOffsetY = 0;
    }
  }

  // 进入/退出全屏预览时的系统栏（状态栏、导航栏）沉浸控制
  private setImmersive(hide: boolean): void {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) { return; }
      window.getLastWindow(ctx).then((win: window.Window) => {
        try {
          win.setWindowSystemBarEnable(hide ? [] : ['status', 'navigation']);
        } catch (e) {
          // 设栏失败忽略
        }
      }).catch(() => {});
    } catch (e) {
      // 窗口未就绪或已销毁，忽略
    }
  }

  // 打开全屏预览：传入整帖图片列表与点击位置，复位缩放/平移并隐藏系统栏进入沉浸
  private openPreview(images: string[], index: number): void {
    if (images.length === 0 || index < 0 || index >= images.length) return;
    this.previewImages = images;
    this.previewIndex = index;
    this.previewScale = 1;
    this.previewPinchBase = 1;
    this.previewOffsetX = 0;
    this.previewOffsetY = 0;
    this.previewImageUrl = images[index];
    this.setImmersive(true);
  }

  // 全屏预览左右切换：dir=-1 上一张，+1 下一张；首/尾不越界
  private switchPreview(dir: number): void {
    const ni = this.previewIndex + dir;
    if (ni < 0 || ni >= this.previewImages.length) return;
    this.previewIndex = ni;
    this.previewImageUrl = this.previewImages[ni];
    // 切换时复位缩放/平移，避免把上一张的放大/偏移带到下一张
    this.previewScale = 1;
    this.previewPinchBase = 1;
    this.previewOffsetX = 0;
    this.previewOffsetY = 0;
  }

  // 关闭全屏预览并复位缩放/平移状态，恢复系统栏
  private closePreview(): void {
    if (this.previewTapTimer !== -1) {
      clearTimeout(this.previewTapTimer);
      this.previewTapTimer = -1;
    }
    this.previewImageUrl = '';
    this.previewImages = [];
    this.previewIndex = 0;
    this.previewScale = 1;
    this.previewPinchBase = 1;
    this.previewOffsetX = 0;
    this.previewOffsetY = 0;
    this.setImmersive(false);
  }

  // 对标 Flutter _PostTile: 头像 + 作者/时间/楼层 + 内容 + 回复按钮
  @Builder
  PostTile(post: Post) {
    Column() {
      // 楼层头：头像 + 作者信息 + 楼层号
      Row() {
        if (post.avatar.length > 0) {
          Image(post.avatar)
            .width(36).height(36).borderRadius(18).margin({ right: 8 })
            .alt($r('sys.symbol.person'))
            .objectFit(ImageFit.Cover)
            .onClick(() => {
              if (post.authorId > 0) {
                this.pageInfo.pushPath({ name: 'RuisiUser', param: new UserParam(post.authorId, post.author) });
              }
            })
        } else if (post.authorId > 0) {
          Image(`${RuisiConstants.BASE_URL}/uc2_link/avatar.php?uid=${post.authorId}&size=small`)
            .width(36).height(36).borderRadius(18).margin({ right: 8 })
            .objectFit(ImageFit.Cover)
            .onClick(() => {
              this.pageInfo.pushPath({ name: 'RuisiUser', param: new UserParam(post.authorId, post.author) });
            })
        } else {
          Row() { Text('👤').fontSize(18) }
          .width(36).height(36).borderRadius(18)
          .backgroundColor(ThemeColors.bgInput)
          .justifyContent(FlexAlign.Center)
          .margin({ right: 8 })
        }

        Column() {
          Text(post.author)
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            .maxLines(1)
          if (post.time.length > 0) {
            Text(post.time)
              .fontSize(12).fontColor(ThemeColors.textHint)
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 楼层号
        if (post.floor > 0) {
          Text('#' + post.floor)
            .fontSize(12).fontColor(ThemeColors.textHint)
        }
      }
      .width('100%')

      // 帖子内容（图文混排：文字块用 Text，图片用块级 Image 穿插在正文原位）
      this.PostContent(post.content)

      // 纯文件附件（PDF/文档等）：文件名 + 下载图标，点击进浏览器下载
      // 对标 Flutter _IgnoreJsOpFileCard（topic_detail_page.dart:839，launchUrl 进浏览器）
      if (post.fileAttachments.length > 0) {
        ForEach(post.fileAttachments, (f: RuisiFileAttachment, fi: number) => {
          Row() {
            Image($r('app.media.ic_ruisi_file'))
              .width(22).height(22).fillColor(this.accentColor)
              .draggable(false)
            Text(f.fileName)
              .fontSize(14).fontColor(ThemeColors.textPrimary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1).margin({ left: 10 })
            Image($r('app.media.ic_public_download'))
              .width(20).height(20).fillColor(ThemeColors.textHint)
              .draggable(false)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .margin({ top: 6 })
          .borderRadius(10)
          .backgroundColor(ThemeColors.bgInput)
          .onClick(() => {
            try { this.context.openLink(f.url); } catch (_) {}
          })
        }, (f: RuisiFileAttachment) => 'file_' + f.url + '_' + f.fileName)
      }

      // 回复按钮（对标 Flutter TextButton.icon onReply）
      Row() {
        Blank()
        Row() {
          Text('💬').fontSize(12)
          Text('回复')
            .fontSize(13).fontColor(this.accentColor)
            .margin({ left: 2 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor(ThemeColors.bgInput)
        .onClick(() => {
          // 对标 Flutter：回复某楼时往文本框预填「回复 #楼层 作者」，纯文本约定（submit 仅带 tid）
          this.replyText = '回复 #' + post.floor + ' ' + post.author + '\n';
          this.showReplyInput = true;
        })
        // 举报该楼（对标论坛每楼「使用道具 / 举报」）
        Row() {
          Text('⚠️').fontSize(12)
          Text('举报')
            .fontSize(13).fontColor('#E57373')
            .margin({ left: 2 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor(ThemeColors.bgInput)
        .margin({ left: 8 })
        .onClick(() => { this.openReport(post.pid); })
      }
      .width('100%')
      .margin({ top: 0 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  // 帖子内容渲染：按正文原始顺序穿插文字块与块级图片。
  // 文字块（含内联表情/引用/链接）用 Text+Span/ImageSpan；图片用块级 Image 组件，
  // 网络图 width('100%') 自动按比例算高度，可靠显示，且位置紧跟对应文字（解决"离得远"）。
  @Builder
  PostContent(content: string) {
    Column() {
      ForEach(this.buildRuns(content), (run: ContentRun, ri: number) => {
        if (run.isImage) {
          RuisiPostImageView({
            imageUrl: run.imageUrl,
            // 点开时收集整帖图片列表（按正文出现顺序）并带上当前图下标，用于全屏左右切换
            onPreview: () => {
              const list: string[] = this.buildRuns(content)
                .filter((r: ContentRun) => r.isImage)
                .map((r: ContentRun) => r.imageUrl);
              this.openPreview(list, run.imageIndex);
            },
            onLongPress: () => { this.saveSheetUrl = run.imageUrl; this.showSaveSheet = true; }
          })
            .width('100%')
            .margin({ top: 8, bottom: 8 })
        } else {
          Text() {
            ForEach(run.segments, (seg: ContentSegment) => {
              if (seg.type === 'smile') {
                ImageSpan($rawfile(seg.value))
                  .width(20).height(20)
                  .objectFit(ImageFit.Contain)
              } else if (seg.type === 'quote') {
                Span(`"${seg.value}"`)
                  .fontSize(12).fontColor(ThemeColors.textHint)
              } else if (seg.type === 'link') {
                Span(seg.value)
                  .fontSize(14).fontColor('#4078c0')
                  .decoration({ type: TextDecorationType.Underline })
                  .onClick(() => {
                    try { this.context.openLink(seg.url); } catch (_) {}
                  })
              } else {
                Span(seg.value)
                  .fontSize(14).fontColor(ThemeColors.textPrimary)
              }
            }, (seg: ContentSegment) => `${seg.type}_${seg.value}_${seg.aid}`)
          }
          .width('100%')
          .fontSize(14).lineHeight(19)
          .margin({ top: 6, bottom: 0 })
          .copyOption(CopyOptions.LocalDevice)
        }
      }, (run: ContentRun, ri: number) => `run_${ri}_${run.isImage ? run.imageUrl : run.segments.length}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 把分段按"图片/非图片"分组：连续的非图片段合并成一个文本块（emoji 保持内联），
  // 图片段各自成块。保证图片在文档流里的原始位置，同时块级 Image 可靠显示网络图。
  private buildRuns(content: string): ContentRun[] {
    const segs = this.splitContent(content);
    const runs: ContentRun[] = [];
    let cur: ContentRun | null = null;
    let imgCount: number = 0;
    for (const seg of segs) {
      if (seg.type === 'image') {
        if (cur !== null) {
          runs.push(cur);
          cur = null;
        }
        const r = new ContentRun();
        r.isImage = true;
        r.imageUrl = seg.value;
        r.imageIndex = imgCount++;
        runs.push(r);
      } else {
        if (cur === null) {
          cur = new ContentRun();
          cur.isImage = false;
        }
        cur.segments.push(seg);
      }
    }
    if (cur !== null) {
      runs.push(cur);
    }
    // 丢弃空文本块（避免多余空行）
    return runs.filter((r: ContentRun) => r.isImage || r.segments.length > 0);
  }

  // 将内容按 [[smile:URL]]、[[quote]]...[[/quote]]、[[link:URL]]...[[/link]]、[[img:URL]] 切分
  private splitContent(content: string): ContentSegment[] {
    const segs: ContentSegment[] = [];
    const regex = /\[\[smile:([^\]]+)\]\]|\[\[quote\]\]([\s\S]*?)\[\[\/quote\]\]|\[\[link:([^\]]+)\]\]([\s\S]*?)\[\[\/link\]\]|\[\[img:([^\]]+)\]\]/g;
    let last = 0;
    let imgIdx = 0;
    let m: RegExpExecArray | null;
    while ((m = regex.exec(content)) !== null) {
      if (m.index > last) {
        const v = content.substring(last, m.index).trim();
        if (v.length > 0) {
          const t = new ContentSegment();
          t.type = 'text';
          t.value = v;
          segs.push(t);
        }
      }
      if (m[1]) {
        // 表情占位符
        const s = new ContentSegment();
        s.type = 'smile';
        s.value = m[1].replace(/^https?:\/\/[^\/]+\/static\/image\/smiley\//, 'smiley/');
        segs.push(s);
      } else if (m[2] !== undefined) {
        // 引用块
        const q = new ContentSegment();
        q.type = 'quote';
        q.value = m[2].trim();
        segs.push(q);
      } else if (m[3]) {
        // 链接
        const l = new ContentSegment();
        l.type = 'link';
        l.value = m[4].trim();
        l.url = m[3];
        segs.push(l);
      } else if (m[5]) {
        // 内联图片（保留正文原始位置）
        const img = new ContentSegment();
        img.type = 'image';
        img.value = m[5];
        img.aid = ++imgIdx;
        segs.push(img);
      }
      last = regex.lastIndex;
    }
    if (last < content.length) {
      const v = content.substring(last).trim();
      if (v.length > 0) {
        const t = new ContentSegment();
        t.type = 'text';
        t.value = v;
        segs.push(t);
      }
    }
    return segs;
  }

  // 标题栏（对标 ScorePage/ExamPage 等子页面：自绘圆形返回按钮 + 标题 + 右侧操作）
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

      Text('帖子详细')
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)

      // 收藏按钮
      if (this.detail) {
        Text('☆')
          .fontSize(22).fontColor(this.accentTextColor())
          .margin({ left: 12 })
          .onClick(async () => {
            const api = RuisiApiService.getInstance();
            const r = await api.favorite(this.tid);
            ToastUtil.show(r.message);
          })

        // 分享按钮
        Image($r('app.media.ic_public_share'))
          .width(22).height(22)
          .fillColor(this.accentTextColor())
          .draggable(false)
          .margin({ left: 12 })
          .onClick(() => { this.doShare(); })
      }
    }
    .width('100%').height('100%')
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
    .backgroundColor(this.accentColor)
  }

  build() {
    NavDestination() {
      Column() {
        // 浏览量 / 评论数统计行
        if (this.detail) {
          Row() {
            Text('👁 ' + this.detail.views + ' 浏览')
              .fontSize(12).fontColor(ThemeColors.textSecondary)
            Text('💬 ' + this.detail.replies + ' 评论')
              .fontSize(12).fontColor(ThemeColors.textSecondary)
              .margin({ left: 16 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(ThemeColors.bgCard)
        }

        if (this.loading) {
          Column() { LoadingProgress().width(36).height(36).color(this.accentColor) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.detail) {
          Stack({ alignContent: Alignment.BottomEnd }) {
            Column() {
              // 楼层列表
              List({ space: 0, scroller: this.scroller }) {
                // 标题区（对标 Flutter 第 0 项 Padding with titleLarge）
                ListItem() {
                  Text(this.detail.title)
                    .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
                    .copyOption(CopyOptions.LocalDevice)
                }

                ForEach(this.detail.posts, (post: Post, idx: number) => {
                  ListItem() {
                    this.PostTile(post)
                  }
                  .border({ width: { bottom: 0.5 }, color: ThemeColors.border })
                }, (post: Post) => `post_${post.pid}`)

                // 下滑加载更多 footer（替代原整页翻页）
                if (this.loadingMore) {
                  ListItem() {
                    Row() { LoadingProgress().width(24).height(24).color(this.accentColor) }
                      .width('100%').height(44).justifyContent(FlexAlign.Center)
                  }
                } else if (this.detail && this.page >= this.detail.totalPages && this.detail.posts.length > 0) {
                  ListItem() {
                    Row() { Text('—— 已经到底啦 ——').fontSize(12).fontColor(ThemeColors.textHint) }
                      .width('100%').height(140).justifyContent(FlexAlign.Center)
                  }
                }
              }
              .width('100%').layoutWeight(1)
              .padding({ bottom: 16 })
              .onReachEnd(() => {
                if (this.detail && this.page < this.detail.totalPages && !this.loadingMore && !this.loading) {
                  this.page++;
                  this.loadDetail(false);
                }
              })

              // 回复输入栏（展开时占位在底部，此时悬浮按钮隐藏）
              if (this.showReplyInput) {
                Column() {
                  // 已选图片缩略图
                  if (this.replyAttachments.length > 0) {
                    Row() {
                      ForEach(this.replyAttachments, (att: RuisiAttachment, idx: number) => {
                        Stack({ alignContent: Alignment.TopEnd }) {
                          if (att.url.length > 0) {
                            Image(att.url).width(56).height(56).borderRadius(8).objectFit(ImageFit.Cover)
                          } else {
                            Text(att.name).width(56).height(56).borderRadius(8)
                              .backgroundColor(ThemeColors.bgInput).fontSize(11).textAlign(TextAlign.Center)
                          }
                          Text('✕').fontSize(12).fontColor('#FFFFFF')
                            .backgroundColor('rgba(0,0,0,0.5)').borderRadius(10).width(20).height(20)
                            .textAlign(TextAlign.Center)
                            .onClick(() => { this.removeReplyAttachment(idx); })
                        }.width(56).height(56).margin({ right: 8 })
                      }, (att: RuisiAttachment) => 'reply_att_' + att.aid)
                    }.width('100%').padding({ left: 16, right: 16, top: 8 }).justifyContent(FlexAlign.Start)
                  }

                  TextArea({ text: this.replyText, placeholder: '回复内容...', controller: this.replyController })
                    .fontSize(14).fontColor(ThemeColors.textPrimary).backgroundColor(ThemeColors.bgInput)
                    .borderRadius(8).height(80).margin({ left: 16, right: 16, top: 8 })
                    .onChange((v: string) => { this.replyText = v; })
                    .onTextSelectionChange((start: number, end: number) => { this.replySelStart = start; })

                  // 工具栏：表情 / 图片 / 取消 / 发送（用系统字体字符，避免 SVG+fillColor 在键盘弹起时渲染失效）
                  Row() {
                    // 表情（论坛内置表情面板）
                    Text('😊')
                      .fontSize(22).padding({ left: 16, right: 8 })
                      .onClick(() => {
                        this.showReplyEmoji = !this.showReplyEmoji;
                      })
                    // 图片
                    if (this.replyUploading) {
                      LoadingProgress().width(22).height(22).margin({ left: 16 })
                    } else {
                      Text('🖼️')
                        .fontSize(22).margin({ left: 8 })
                        .onClick(() => { this.pickReplyImage(); })
                    }
                    Blank()
                    // 取消
                    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
                      Text('✕').fontSize(18).fontColor(ThemeColors.textPrimary)
                    }
                    .width(36).height(36).margin({ right: 8 })
                    .backgroundColor(ThemeColors.bgInput)
                    .onClick(() => {
                      this.showReplyInput = false;
                      this.replyText = '';
                      this.replyAttachments = [];
                      this.showReplyEmoji = false;
                    })
                    // 发送
                    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
                      if (this.replying) {
                        LoadingProgress().width(20).height(20).color('#FFFFFF')
                      } else {
                        Text('✈').fontSize(18).fontColor('#FFFFFF')
                      }
                    }
                    .width(36).height(36)
                    .backgroundColor(this.accentColor)
                    .onClick(() => { this.doReply(); })
                    .enabled(!this.replying && !this.replyUploading)
                  }.width('100%').margin({ top: 8, bottom: 12 })

                  // 论坛内置表情面板（公共组件，与发帖页一致）
                  if (this.showReplyEmoji) {
                    RuisiSmileyPanel({
                      onPick: (code: string) => {
                        this.replyText = ruisiInsertAtCaret(this.replyController, this.replyText, this.replySelStart, code);
                      }
                    })
                  }
                }.backgroundColor(ThemeColors.bgCard)
                .padding({ bottom: 8 })
                .margin({ bottom: this.keyboardOffset })
              }
            }
            .width('100%').height('100%')

            // 悬浮回复按钮（玻璃 + 智感握持换手，与首页发帖 FAB 三件套一致）
            if (!this.showReplyInput) {
              Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
                Image($r('app.media.ic_ellipsis_bubble'))
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
              .translate({ x: this.fabTranslateX })
              .onClick(() => { this.showReplyInput = true; })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((oldVal, newVal) => {
            const w = newVal.width as number;
            if (w > 0) this.screenWidth = w;
            if (!this.fabInitialized) {
              this.fabInitialized = true;
              this.fabTranslateX = this.isLeftHand ? -(this.screenWidth - 80) : 0;
            }
          })
        } else {
          Column() {
            Text('加载失败')
              .fontSize(14).fontColor(ThemeColors.textHint)
            Button('重试').fontSize(14).margin({ top: 12 })
              .onClick(() => { this.loadDetail(); })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }

      // 帖子图片全屏预览：点图进、再点退出（叠加在内容之上，定位覆盖整屏）
      if (this.previewImageUrl.length > 0) {
        Stack() {
          // 黑色背景层：点图片以外的区域即退出预览
          Column() { }
            .width('100%').height('100%')
            .backgroundColor('#000000')
            .onClick(() => { this.closePreview(); })

          // 图片本体：双指捏合缩放 + 双击放大/还原 + 单点退出（放大后可拖拽平移）
          Image(this.previewImageUrl)
            .width('100%').height('100%')
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .scale({ x: this.previewScale, y: this.previewScale })
            .translate({ x: this.previewOffsetX, y: this.previewOffsetY })
            .onClick(() => { this.handlePreviewTap(); })
            .gesture(
              GestureGroup(GestureMode.Parallel,
                PinchGesture({ fingers: 2 })
                  .onActionUpdate((e: GestureEvent) => {
                    this.previewScale = this.previewPinchBase * e.scale;
                  })
                  .onActionEnd(() => {
                    this.previewPinchBase = this.previewScale;
                    this.clampPreviewScale();
                  }),
                PanGesture()
                  .onActionStart(() => {
                    this.panStartX = this.previewOffsetX;
                    this.panStartY = this.previewOffsetY;
                  })
                  .onActionUpdate((e: GestureEvent) => {
                    if (this.previewScale > 1) {
                      this.previewOffsetX = this.panStartX + e.offsetX;
                      this.previewOffsetY = this.panStartY + e.offsetY;
                    }
                  })
              )
            )

          // 浮动关闭按钮：标题栏已隐藏，提供明确退出入口（避开顶部状态栏区域）
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
            Image($r('app.media.close'))
              .width(22).height(22)
              .fillColor('#FFFFFF')
              .draggable(false)
          }
          .width(40).height(40)
          .backgroundColor('rgba(0,0,0,0.4)')
          .position({ top: 24, right: 16 })
          .zIndex(101)
          .onClick(() => { this.closePreview(); })

          // 保存到相册：浮在右下角的圆形下载按钮（SaveButton 安全控件，点击即获临时写相册权限；
          // 普通应用只能用系统图标，不能塞自定义 SVG——setIcon 需 CUSTOMIZE_SAVE_BUTTON 权限，拿不到）
          Stack() {
            SaveButton({ icon: SaveIconStyle.FULL_FILLED, buttonType: ButtonType.Circle })
              .width(48).height(48)
              .iconSize(24)
              .backgroundColor('rgba(0,0,0,0.4)')
              .onClick((event: ClickEvent) => { this.doSaveImage(this.previewImageUrl); })
          }
          .position({ bottom: 48, right: 16 })
          .zIndex(101)

          // 图片计数（仅多图时显示）：顶部居中
          if (this.previewImages.length > 1) {
            Row() {
              Text(`${this.previewIndex + 1} / ${this.previewImages.length}`)
                .fontSize(14).fontColor('#FFFFFF')
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .position({ top: 24 })
            .zIndex(101)
          }

          // 左切换（非首图）：垂直居中、左侧。箭头图标对齐课表周切换（ic_public_arrow_left），自动居中
          if (this.previewImages.length > 1 && this.previewIndex > 0) {
            Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
              Image($r('app.media.ic_public_arrow_left'))
                .width(20).height(20)
                .fillColor('#FFFFFF')
                .draggable(false)
            }
            .width(44).height(44)
            .backgroundColor('rgba(0,0,0,0.4)')
            .position({ top: '50%', left: 16 })
            .translate({ y: -22 })
            .zIndex(101)
            .onClick(() => { this.switchPreview(-1); })
          }

          // 右切换（非末图）：垂直居中、右侧。箭头图标对齐课表周切换（ic_public_arrow_right）
          if (this.previewImages.length > 1 && this.previewIndex < this.previewImages.length - 1) {
            Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
              Image($r('app.media.ic_public_arrow_right'))
                .width(20).height(20)
                .fillColor('#FFFFFF')
                .draggable(false)
            }
            .width(44).height(44)
            .backgroundColor('rgba(0,0,0,0.4)')
            .position({ top: '50%', right: 16 })
            .translate({ y: -22 })
            .zIndex(101)
            .onClick(() => { this.switchPreview(1); })
          }
        }
        .width('100%').height('100%')
        .backgroundColor('#000000')
        .position({ top: 0, left: 0 })
        .zIndex(100)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      // 举报浮层（自管理，状态由 showReportSheet 控制，可重复打开/关闭）
      if (this.showReportSheet) {
        this.reportOverlayBuilder()
      }
      }
      .width('100%').height('100%')
      .backgroundColor(ThemeColors.bgPage)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .title({ builder: this.headerBuilder(), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true)
    .hideTitleBar(this.previewImageUrl.length > 0)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.showSaveSheet, this.saveSheetBuilder, { height: 180, showClose: true })
  }
}
