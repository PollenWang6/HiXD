// ExamPage.ets — 考试安排页面
import { ThemeColors } from '../../utils/ThemeColors';
import { EhallService, SemesterUtil, ExamItemModel } from '../../services/EhallService';
import { ExamService } from '../../services/ExamService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { router } from '@kit.ArkUI';


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
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State arranged: ExamItemModel[] = [];
  @State notArranged: ExamItemModel[] = [];
  @State selectedSemester: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  private ehall = EhallService.getInstance();

  aboutToAppear(): void {
    this.selectedSemester = SemesterUtil.getCurrentSemesterCode();
    this.loadExams();
  }

  // 判断考试是否已结束
  private isExamFinished(ksrq: string): boolean {
    if (!ksrq || ksrq.length < 10) return false;
    const examDate: string = ksrq.substring(0, 10);
    const today: string = new Date().toISOString().substring(0, 10);
    return examDate < today;
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
        console.error('ExamPage', 'exam item: kcm=' + it.kcm + ' | ksmc=' + it.ksmc + ' | ksrq=' + it.ksrq + ' | jasmc=' + it.jasmc + ' | zw=' + it.zw);
      }
      this.arranged = items.filter(i => i.ksrq && i.ksrq.length > 0);
      this.notArranged = items.filter(i => !i.ksrq || i.ksrq.length === 0);
      // 缓存原始数据供课表页使用
      PreferenceUtil.putString('exam_schedule_cache', raw);
      console.error('ExamPage', 'Cached exam data, raw.length=' + raw.length);
    } catch (e) {
      this.errorMsg = (e as Error).message?.includes('未登录') ? '登录已过期' : '加载失败';
    } finally { this.loading = false; }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
        Blank()
        Text(SemesterUtil.formatSemester(this.selectedSemester)).fontSize(12).fontColor(ThemeColors.textSecondary)
        }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 }).backgroundColor(ThemeColors.bgCard)
        Divider().color(ThemeColors.border)

        if (this.loading) {
          Column() { LoadingProgress().width(40).height(40).color('#FB8C00'); Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 }); }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.arranged.length === 0 && this.notArranged.length === 0) {
          Column() { Text('🎉').fontSize(48); Text('暂无考试安排').fontSize(16).fontColor(ThemeColors.textSecondary).margin({ top: 12 }); Text('本学期暂未发布考试信息').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 4 }); }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 12 }) {
            ForEach(this.arranged, (exam: ExamItemModel, idx?: number) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(exam.ksrq ? exam.ksrq.substring(5, 10) : '待定').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FB8C00')
                    Text(this.getKsmcLine1(exam.ksmc)).fontSize(10).fontColor(ThemeColors.textSecondary).margin({ top: 4 }).maxLines(1)
                    Text(this.getKsmcLine2(exam.ksmc)).fontSize(10).fontColor(ThemeColors.textSecondary).margin({ top: 2 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }.width(120).alignItems(HorizontalAlign.Center)
                  Column() {
                    Row() {
                      Text(exam.kcm).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      // 已完成标识
                      if (this.isExamFinished(exam.ksrq)) {
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
                  Text('待安排考试').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).margin({ bottom: 8 })
                  ForEach(this.notArranged, (item: ExamItemModel, idx?: number) => {
                    Row() { Text(item.kcm).fontSize(13).fontColor(ThemeColors.textSecondary).layoutWeight(1); Text('待定').fontSize(12).fontColor('#BBBBBB'); }
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
    .title('考试安排')
    .onReady((ctx: NavDestinationContext) => {
      // NavDestination 初始化完成
    })
  }
}
