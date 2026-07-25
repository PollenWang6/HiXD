// RuisiUserPage.ets — 个人主页
// 头像卡片(主题/帖子/积分/金币) + 内容入口(我的帖子/我的收藏/每日签到) + 设置入口
// 关于/退出登录统一收进设置页，避免主页与设置页互相包含造成回环

import { ThemeColors } from '../../utils/ThemeColors';
import { AccentColors } from '../../utils/AccentColors';
import { RuisiApiService } from '../../services/RuisiApiService';
import { UserInfo, SignResult, RuisiConstants, UserThreadsParam, PmParam, FriendResult } from '../../services/RuisiModels';
import { RuisiService } from '../../services/RuisiService';
import { ToastUtil } from '../../utils/ToastUtil';
import { RuisUtils } from '../../utils/RuisUtils';

@Component
export struct RuisiUserPage {
  @StorageLink('theme_is_dark') isDark: boolean = false;
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('ruisi_logged_in') isLoggedIn: boolean = false;
  pageInfo: NavPathStack = new NavPathStack();

  private accentTextColor(): Color { return AccentColors.textContrast; }

  @State uid: number = 0;
  @State username: string = '';
  @State userInfo: UserInfo | null = null;
  // 等级昵称（由积分换算，对齐安卓/苹果：西电托儿所 → 西电博士后）
  @State userLevel: string = '';
  @State loading: boolean = false;
  @State signLoading: boolean = false;
  // 签到天数（常驻显示在「每日签到」行，进页面 + 点击签到后刷新）
  @State signMonthDays: number = 0;
  @State signTotalDays: number = 0;
  // 是否查看自己（他人主页时隐藏个人专属入口）
  @State isSelf: boolean = false;
  // 外部传入的目标用户（>0 表示查看他人；=0 表示查看当前登录用户自己）
  targetUid: number = 0;
  targetUsername: string = '';
  // 添加好友弹窗控制器
  private addFriendDialogController!: CustomDialogController;

  aboutToAppear(): void {
    const svc = RuisiService.getInstance();
    if (this.targetUid > 0) {
      this.uid = this.targetUid;
      this.username = this.targetUsername || ('uid:' + this.targetUid);
    } else {
      this.uid = svc.getUid();
      this.username = svc.getUsername() || '未知用户';
    }
    this.isSelf = (this.uid > 0 && this.uid === svc.getUid());
    this.buildAddFriendDialog();
    this.loadInfo().catch(() => { ToastUtil.show('加载失败，请重试'); });
  }

  async loadInfo(): Promise<void> {
    if (this.uid === 0) return;
    this.loading = true;
    try {
      const api = RuisiApiService.getInstance();
      // 顺序拉取：用户基本信息 + 金币（金币是独立货币，单独接口）
      const info = await api.getUserInfo(this.uid);
      if (info) {
        this.userInfo = info;
        this.userLevel = RuisUtils.getLevel(info.credits);
      }
      // 进页面即刷新签到天数（常驻显示在「每日签到」行）
      const stats = await api.getSignStats();
      this.signMonthDays = stats.monthDays;
      this.signTotalDays = stats.totalDays;
    } finally { this.loading = false; }
  }

  async doSign(): Promise<void> {
    if (this.signLoading) return;
    this.signLoading = true;
    try {
      const api = RuisiApiService.getInstance();
      // 1) 立刻签到并弹「动作结果」提示（不等待天数，避免变慢）
      const result: SignResult = await api.sign('kx');
      ToastUtil.show(result.message);
      if (result.success) {
        // 签到可能奖励金币，刷新一下
        this.userInfo!.coins = await api.getCoins();
      }
      // 2) 刷新签到天数（常驻显示在「每日签到」行，与动作提示分离）
      const stats = await api.getSignStats();
      this.signMonthDays = stats.monthDays;
      this.signTotalDays = stats.totalDays;
    } finally { this.signLoading = false; }
  }

  // 构建「添加好友」弹窗（在 aboutToAppear 中调用，确保 accent/用户名是最新的）
  private buildAddFriendDialog(): void {
    this.addFriendDialogController = new CustomDialogController({
      builder: AddFriendDialog({
        uid: this.uid,
        username: this.userInfo?.username || this.username,
        accentColor: this.accentColor,
        onConfirm: (note: string) => { this.doAddFriend(note); },
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
    });
  }

  // 打开添加好友弹窗
  openAddFriend(): void {
    if (!this.isLoggedIn) {
      ToastUtil.show('你还没有登录，无法添加好友');
      return;
    }
    if (this.uid === 0) return;
    this.buildAddFriendDialog();
    this.addFriendDialogController.open();
  }

  // 提交添加好友请求
  async doAddFriend(note: string): Promise<void> {
    if (this.uid === 0) return;
    const api = RuisiApiService.getInstance();
    const r = await api.addFriend(this.uid, note);
    ToastUtil.show(r.message);
  }

  @Builder
  MenuRow(icon: string, title: string, onClick: () => void) {
    Row() {
      Text(icon).fontSize(18).margin({ right: 12 })
      Text(title).fontSize(15).fontColor(ThemeColors.textPrimary).layoutWeight(1)
      Text('›').fontSize(18).fontColor(ThemeColors.textHint)
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .backgroundColor(ThemeColors.bgCard)
    .onClick(() => onClick())
  }

  @Builder
  StatItem(num: number | string, label: string) {
    Column() {
      Text(String(num))
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      Text(label)
        .fontSize(12).fontColor(ThemeColors.textHint).margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
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

      Text('个人主页')
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
        Scroll() {
          Column() {
            // 头像卡片
            Column() {
              if (this.uid > 0) {
                Image(`${RuisiConstants.BASE_URL}/uc2_link/avatar.php?uid=${this.uid}&size=middle`)
                  .width(64).height(64).borderRadius(12)
                  .alt($r('sys.symbol.person'))
                  .objectFit(ImageFit.Cover)
              } else {
                Row() { Text('👤').fontSize(32) }
                .width(64).height(64).borderRadius(12)
                .backgroundColor(ThemeColors.bgInput)
                .justifyContent(FlexAlign.Center)
              }
              Text(this.userInfo?.username || this.username)
                .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                .margin({ top: 8 })
              Text('uid: ' + this.uid)
                .fontSize(13).fontColor(ThemeColors.textSecondary)
                .margin({ top: 4 })

              // 统计行：等级 / 旧积分 / 积分 / 金币（四列等宽）
              if (this.userInfo) {
                Row() {
                  this.StatItem(this.userLevel, '等级')
                  this.StatItem(this.userInfo.oldCredits, '旧积分')
                  this.StatItem(this.userInfo.credits, '积分')
                  this.StatItem(this.userInfo.coins, '金币')
                }
                .margin({ top: 20 })

                if (this.userInfo.joinDate.length > 0) {
                  Text('注册: ' + this.userInfo.joinDate)
                    .fontSize(12).fontColor(ThemeColors.textHint).margin({ top: 12 })
                }
                if (this.userInfo.signature.length > 0) {
                  Text(this.userInfo.signature)
                    .fontSize(12).fontColor(ThemeColors.textHint).margin({ top: 4, left: 16, right: 16 })
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(ThemeColors.bgCard)
            .borderRadius(0)

            // 间距
            Row().height(8).backgroundColor(ThemeColors.bgPage)

            // 内容入口（查看任何人都有：他的帖子，无数量、仅入口，对齐安卓 UserDetailActivity）
            this.MenuRow('📖', this.isSelf ? '我的帖子' : '他的帖子', () => {
              this.pageInfo.pushPath({ name: 'RuisiUserThreads', param: new UserThreadsParam(this.uid, 'me') });
            })
            // 发私信（仅查看他人时显示，对齐安卓/iOS 个人主页 → 私信入口）
            if (!this.isSelf) {
              Row().height(0.5).backgroundColor(ThemeColors.border).margin({ left: 16 })
              this.MenuRow('💬', '发私信', () => {
                this.pageInfo.pushPath({ name: 'RuisiChat', param: new PmParam(this.uid, this.userInfo?.username || this.username) });
              })
              Row().height(0.5).backgroundColor(ThemeColors.border).margin({ left: 16 })
              this.MenuRow('👥', '添加好友', () => {
                this.openAddFriend();
              })
            }

            Row().height(8).backgroundColor(ThemeColors.bgPage)

            if (this.isSelf) {
            // 个人专属入口（仅自己可见）
            this.MenuRow('🔖', '我的收藏', () => {
              this.pageInfo.pushPath({ name: 'RuisiFavorites' });
            })
            Row().height(0.5).backgroundColor(ThemeColors.border).margin({ left: 16 })

            // 签到（天数常驻显示在标题下方）
            Row() {
              Text('✅').fontSize(18).margin({ right: 12 })
              Column() {
                Text('每日签到').fontSize(15).fontColor(ThemeColors.textPrimary)
                if (this.signMonthDays > 0 || this.signTotalDays > 0) {
                  Text(`本月已签${this.signMonthDays}天 · 累计已签${this.signTotalDays}天`)
                    .fontSize(12).fontColor(ThemeColors.textHint).margin({ top: 2 })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (this.signLoading) {
                LoadingProgress().width(20).height(20).color(this.accentColor)
              } else {
                Text('›').fontSize(18).fontColor(ThemeColors.textHint)
              }
            }
            .width('100%').height(56).padding({ left: 16, right: 16 })
            .backgroundColor(ThemeColors.bgCard)
            .onClick(() => { this.doSign(); })

            Row().height(8).backgroundColor(ThemeColors.bgPage)

            // 设置（关于 / 退出登录统一收进设置页，避免主页与设置页互相包含）
            this.MenuRow('⚙️', '设置', () => {
              this.pageInfo.pushPath({ name: 'RuisiSettings' });
            })
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
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

// 添加好友弹窗（对齐安卓 AddFriendDialog：留言输入 + 发送/取消）
@CustomDialog
struct AddFriendDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: AddFriendDialog() });
  uid: number = 0;
  username: string = '';
  accentColor: string = '#2979FF';
  onConfirm: (note: string) => void = () => {};
  @State note: string = '';

  build() {
    Column() {
      Text('添加好友')
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        .margin({ top: 20, bottom: 6 })
      Text(this.username)
        .fontSize(14).fontColor(ThemeColors.textHint)
        .margin({ bottom: 14 })
      TextInput({ placeholder: '说点什么（最多10字）', text: this.note })
        .maxLength(10)
        .onChange((v: string) => { this.note = v; })
        .width('100%')
        .padding({ left: 20, right: 20 })
      Row() {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor(ThemeColors.bgInput)
          .fontColor(ThemeColors.textPrimary)
          .onClick(() => { this.controller.close(); })
        Button('发送')
          .layoutWeight(1)
          .margin({ left: 12 })
          .backgroundColor(this.accentColor)
          .fontColor(AccentColors.textContrast)
          .onClick(() => {
            if (this.note.length > 10) {
              ToastUtil.show('字数太多了,最多10个');
              return;
            }
            this.onConfirm(this.note);
            this.controller.close();
          })
      }
      .width('100%')
      .margin({ top: 16, bottom: 20 })
      .padding({ left: 20, right: 20 })
    }
    .width('86%')
    .backgroundColor(ThemeColors.bgCard)
    .borderRadius(16)
    .padding({ top: 4, bottom: 4 })
  }
}
