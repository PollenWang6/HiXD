import { AccentColors } from '../../utils/AccentColors';
// ExamPage.ets — 考试安排页面
import { ThemeColors } from '../../utils/ThemeColors';
import { SemesterUtil, ExamItemModel } from '../../services/EhallService';
import { ExamService } from '../../services/ExamService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';


// 卡片背景色 [浅色, 深色] — 深色模式用暗调确保白字可读
const EXAM_CARD_COLORS: string[][] = [
  ['#E3F2FD', '#1A2D40'],
  ['#F3E5F5', '#2D1B30'],
  ['#FFF3E0', '#2D2318'],
  ['#E8F5E9', '#1B2E1C'],
  ['#FCE4EC', '#2D1E23'],
];


@Component
export struct ExamPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State showCacheBanner: boolean = false;
  @State arranged: ExamItemModel[] = [];
  @State notArranged: ExamItemModel[] = [];
  @State selectedSemester: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  @State isRefreshing: boolean = false;

    @Builder buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40).width(40)
      .onClick(() => { this.pageInfo.pop(); })
      Text(t)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(AccentColors.textContrast)
        .layoutWeight(1)
    }
    .width('100%')
    .height(52 + this.statusBarHeight)
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
  }


  aboutToAppear(): void {
    this.selectedSemester = SemesterUtil.getCurrentSemesterCode();
    this.loadExams();
  }

  // 考试状态：-1=已结束，0=未开始，1=进行中，-2=非今天
  private getExamStatus(ksrq: string, kssjms: string): number {
    if (!ksrq || ksrq.length < 10) return -2;
    const examDate: string = ksrq.substring(0, 10);
    const now: Date = new Date();
    const today: string = now.getFullYear() + '-'
      + String(now.getMonth() + 1).padStart(2, '0') + '-'
      + String(now.getDate()).padStart(2, '0');
    if (examDate < today) return -1;
    if (examDate > today) return -2;
    // 今天：按时间段判断
    const timeMatch: RegExpMatchArray | null = (kssjms || '').match(/(\d{1,2}:\d{2})-(\d{1,2}:\d{2})/);
    if (!timeMatch) return -2;
    const startParts: string[] = timeMatch[1].split(':');
    const endParts: string[] = timeMatch[2].split(':');
    const startMin: number = parseInt(startParts[0]) * 60 + parseInt(startParts[1]);
    const endMin: number = parseInt(endParts[0]) * 60 + parseInt(endParts[1]);
    const nowMin: number = now.getHours() * 60 + now.getMinutes();
    if (nowMin >= startMin && nowMin < endMin) return 1;
    if (nowMin >= endMin) return -1;
    return 0;
  }

  // 从日期字符串获取周几
  private getWeekdayFromKsrq(ksrq: string): string {
    if (!ksrq || ksrq.length < 10) return '';
    const weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    const date = new Date(ksrq.substring(0, 10));
    if (isNaN(date.getTime())) return '';
    return weekdays[date.getDay()];
  }

  // 格式化考试时间（去掉日期和星期）
  private formatExamTime(kssjms: string): string {
    const timeRaw: string = kssjms || '';
    const spaceIdx: number = timeRaw.indexOf(' ');
    const afterSpace: string = spaceIdx >= 0 ? timeRaw.substring(spaceIdx + 1) : timeRaw;
    const parenIdx: number = afterSpace.indexOf('(');
    return parenIdx >= 0 ? afterSpace.substring(0, parenIdx).trim() : afterSpace.trim();
  }

  // 拆分 ksmc："2025-2026学年 第二学期 期中考试" → 第一行学年 / 第二行学期+考试
  private getKsmcLine1(ksmc: string): string {
    if (!ksmc || ksmc.length === 0) return ksmc;
    const idx: number = ksmc.indexOf(' ');
    return idx >= 0 ? ksmc.substring(0, idx) : ksmc;
  }
  private getKsmcLine2(ksmc: string): string {
    if (!ksmc || ksmc.length === 0) return '';
    const idx: number = ksmc.indexOf(' ');
    return idx >= 0 ? ksmc.substring(idx + 1) : '';
  }

  async loadExams(): Promise<void> {
    this.loading = true; this.errorMsg = '';
    try {
      const raw: string = await ExamService.getInstance().getExamSchedule(this.selectedSemester);
      const items: ExamItemModel[] = ExamService.parseExamSchedule(raw);
      // 日志：打印完整考试数据，方便排查 ksmc 显示问题
      for (const it of items) {
      }
      this.arranged = items.filter(i => i.ksrq && i.ksrq.length > 0);
      this.notArranged = items.filter(i => !i.ksrq || i.ksrq.length === 0);
      this.showCacheBanner = false;
      if (items.length > 0) {
        PreferenceUtil.putString('exam_schedule_cache', raw);
        await PreferenceUtil.saveSharedFile('exam_schedule', raw);
        AppStorage.set('home_data_dirty', String(Date.now()));
      } else {
      }
    } catch (e) {
      // 用 MainPage 同步到 AppStorage 的 loginStatus 准确判断是否登录过期，
      // 不再依赖脆弱的「未登录」字符串匹配。
      const st: string = AppStorage.get('loginStatus') as string ?? '';
      const expired: boolean = st === 'expired' || (e as Error).message?.includes('未登录');
      // 尝试从缓存加载：缓存命中则清空 errorMsg（否则 build 的 errorMsg 分支优先，
      // 缓存数据永远不渲染，顶部横幅还显示「缓存数据」造成双重误导）
      const cached: string = PreferenceUtil.getString('exam_schedule_cache', '');
      if (cached.length > 0) {
        try {
          const cachedItems: ExamItemModel[] = ExamService.parseExamSchedule(cached);
          if (cachedItems.length > 0) {
            this.arranged = cachedItems.filter(i => i.ksrq && i.ksrq.length > 0);
            this.notArranged = cachedItems.filter(i => !i.ksrq || i.ksrq.length === 0);
            this.showCacheBanner = true;
            this.errorMsg = '';
          } else {
            this.errorMsg = expired ? '登录已过期' : '加载失败';
          }
        } catch (_parseErr) {
          this.errorMsg = expired ? '登录已过期' : '加载失败';
        }
      } else {
        this.errorMsg = expired ? '登录已过期' : '加载失败';
      }
    } finally { this.loading = false; }
  }

  private async doRefresh(): Promise<void> {
    // 强制刷新：绕过 ExamService 5 分钟内存缓存（forceRefresh=true），真正重拉服务器
    this.isRefreshing = true;
    try {
      const raw: string = await ExamService.getInstance().getExamSchedule(this.selectedSemester, true);
      const items: ExamItemModel[] = ExamService.parseExamSchedule(raw);
      this.arranged = items.filter(i => i.ksrq && i.ksrq.length > 0);
      this.notArranged = items.filter(i => !i.ksrq || i.ksrq.length === 0);
      this.showCacheBanner = false;
      if (items.length > 0) {
        PreferenceUtil.putString('exam_schedule_cache', raw);
        await PreferenceUtil.saveSharedFile('exam_schedule', raw);
        AppStorage.set('home_data_dirty', String(Date.now()));
      }
    } catch (e) {
      // 保持现有数据显示，不覆盖
    } finally {
      this.isRefreshing = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
        Blank()
        Text(SemesterUtil.formatSemester(this.selectedSemester)).fontSize(12).fontColor(ThemeColors.textSecondary)
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 }).backgroundColor(ThemeColors.bgCard)
        Divider().color(ThemeColors.border)

        if (this.showCacheBanner) {
          Row() {
            Text('📦 当前显示缓存数据').fontSize(12).fontColor('#BF4D00')
            Text('  刷新').fontSize(12).fontColor(this.accentColor)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .border({ width: 1, color: this.accentColor, radius: 4 })
              .margin({ left: 10 })
              .onClick(() => { this.loadExams(); })
          }.width('100%').height(32).justifyContent(FlexAlign.Center)
          .backgroundColor(this.themeIsDark ? '#3E2723' : '#FFF3E0')
        }

        if (this.loading) {
          Column() { LoadingProgress().width(40).height(40).color(this.accentColor); Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 }); }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorMsg.length > 0) {
          Column() {
            Text('⚠').fontSize(40).fontColor(ThemeColors.textHint)
            Text(this.errorMsg).fontSize(14).fontColor(ThemeColors.error).margin({ top: 8 })
            Button('重试').margin({ top: 12 }).onClick(() => { this.loadExams(); })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.arranged.length === 0 && this.notArranged.length === 0) {
          Column() { Text('🎉').fontSize(48); Text('暂无考试安排').fontSize(16).fontColor(ThemeColors.textSecondary).margin({ top: 12 }); Text('本学期暂未发布考试信息').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 4 }); }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          // 固定刷新行（考勤查询同款）
          Row() {
            Text('').layoutWeight(1)
            if (this.isRefreshing) {
              Row() {
                LoadingProgress().width(14).height(14).color(this.accentColor)
                Text('刷新中').fontSize(12).fontColor(this.accentColor).margin({ left: 6 })
              }.height(30).padding({ left: 12, right: 12 })
            } else {
              Button('刷新')
                .fontSize(12).height(30)
                .backgroundColor(this.accentColor + '18').fontColor(this.accentColor)
                .borderRadius(15).padding({ left: 12, right: 12 })
                .onClick(() => { this.isRefreshing = true; this.doRefresh(); })
            }
          }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })
          List({ space: 12 }) {
            ForEach(this.arranged, (exam: ExamItemModel, idx?: number) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(exam.ksrq ? exam.ksrq.substring(5, 10) + ' ' + this.getWeekdayFromKsrq(exam.ksrq) : '待定').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#BF4D00')
                    Text(this.getKsmcLine1(exam.ksmc)).fontSize(10).fontColor(ThemeColors.textSecondary).margin({ top: 4 }).maxLines(1)
                    Text(this.getKsmcLine2(exam.ksmc)).fontSize(10).fontColor(ThemeColors.textSecondary).margin({ top: 2 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.width(120).alignItems(HorizontalAlign.Center)
                  Column() {
                    Row() {
                      Text(exam.kcm).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      // 考试状态标识
                      if (this.getExamStatus(exam.ksrq, exam.kssjms) === 1) {
                        Text('进行中').fontSize(11).fontColor('#FFFFFF').backgroundColor('#4CAF50').borderRadius(4).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      } else if (this.getExamStatus(exam.ksrq, exam.kssjms) === 0) {
                        Text('未开始').fontSize(11).fontColor('#FFFFFF').backgroundColor('#BF4D00').borderRadius(4).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      } else if (this.getExamStatus(exam.ksrq, exam.kssjms) === -1) {
                        Text('已结束').fontSize(11).fontColor('#FFFFFF').backgroundColor('#9E9E9E').borderRadius(4).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      }
                    }.width('100%')
                    Row() {
                      Text('🕐 ' + (this.formatExamTime(exam.kssjms) || '待定')).fontSize(12).fontColor(ThemeColors.textSecondary)
                    }.margin({ top: 6 }).width('100%')
                    Row({ space: 12 }) {
                      Text('📍 ' + (exam.jasmc || '待定')).fontSize(12).fontColor(ThemeColors.textSecondary)
                      Text('💺 ' + (exam.zw || '--')).fontSize(12).fontColor(ThemeColors.textSecondary)
                    }.margin({ top: 4 }).width('100%')
                  }.layoutWeight(1)
                }.width('100%').padding(16).borderRadius(12).backgroundColor(
                  EXAM_CARD_COLORS[(idx || 0) % EXAM_CARD_COLORS.length][this.themeIsDark ? 1 : 0])
              }
            }, (exam: ExamItemModel, idx?: number) => `exam_${idx}`)
            if (this.notArranged.length > 0) {
              ListItem() {
                Column() {
                  Text('暂无安排考试科目').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).margin({ bottom: 8 })
                  ForEach(this.notArranged, (item: ExamItemModel, idx?: number) => {
                    Row() { Text(item.kcm).fontSize(13).fontColor(ThemeColors.textSecondary).layoutWeight(1); Text('待定').fontSize(12).fontColor(ThemeColors.textSecondary); }
                      .width('100%').padding({ top: 6, bottom: 6 })
                  }, (item: ExamItemModel, idx?: number) => `na_${idx}`)
                }.width('100%').padding(16).borderRadius(12).backgroundColor(ThemeColors.bgInput)
              }
            }
          }.padding({ left: 16, right: 16, top: 12 }).layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeColors.bgPage)
    }
    .title({ builder: this.buildWhiteTitle('考试安排'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
    .onReady((ctx: NavDestinationContext) => {
      // NavDestination 初始化完成
    })
  }
}
