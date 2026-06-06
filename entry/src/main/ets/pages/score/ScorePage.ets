// ScorePage.ets — 成绩查询（含成绩构成详情，增强层次感版）
import { EhallService, SemesterUtil, ScoreItemModel, ComposeDetail } from '../../services/EhallService';
import { ScoreService } from '../../services/ScoreService';
import { ThemeColors } from '../../utils/ThemeColors';

@Component
export struct ScorePage {
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State selectedSemester: string = '';
  @State semesterCodes: string[] = [];
  @State currentScores: ScoreItemModel[] = [];

  // 成绩构成详情弹窗状态
  @State selectedCell: ScoreItemModel | null = null;
  @State cardScale: number = 0.85;
  @State cardOpacity: number = 0;
  @State maskOpacity: number = 0; // 新增：单独控制背景遮罩透明度
  @State detailLoading: boolean = false;
  @State currentDetail: ComposeDetail[] = [];
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  private ehall = EhallService.getInstance();
  private allScores: ScoreItemModel[] = [];
  private detailCache: Map<string, ComposeDetail[]> = new Map();

  aboutToAppear(): void {
    this.waitAndLoad();
  }

  private async waitAndLoad(): Promise<void> {
    let waited = 0;
    while (waited < 2000) {
      await new Promise<void>((r) => { setTimeout(r, 300); });
      waited += 300;
    }
    console.info('[ScorePage] waitAndLoad done');
    this.loadScores();
  }

  async loadScores(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const raw: string = await ScoreService.getInstance().getScores('');
      const items: ScoreItemModel[] = ScoreService.parseScores(raw);
      console.info('[ScorePage] parsed ' + items.length + ' items');

      this.allScores = items;

      const semSet: string[] = [];
      const seen = new Set<string>();
      for (let i = 0; i < items.length; i++) {
        const item: ScoreItemModel = items[i];
        const sem: string = item.xnxqdm;
        if (!seen.has(sem)) {
          seen.add(sem);
          semSet.push(sem);
        }
      }
      semSet.sort((a, b) => b.localeCompare(a));
      this.semesterCodes = semSet;

      if (semSet.length > 0) {
        this.selectedSemester = semSet[0];
        this.currentScores = this.allScores.filter((it: ScoreItemModel) => it.xnxqdm === semSet[0]);
      }
    } catch (e) {
      const msg = (e as Error).message || '';
      this.errorMsg = msg.includes('未登录') ? '登录已过期，请重新登录' : '加载成绩失败';
    } finally {
      this.loading = false;
    }
  }

  private scoreToGPA(score: string, scoreType: string): string {
    if (scoreType === '五级成绩') {
      const num = parseFloat(score);
      if (!isNaN(num)) {
        if (num >= 90) return '4.0';
        if (num >= 80) return '3.8';
        if (num >= 70) return '3.2';
        if (num >= 60) return '2.4';
        return '0';
      }
      if (score === '优秀') return '4.0';
      if (score === '良好') return '3.8';
      if (score === '中等') return '3.2';
      if (score === '及格') return '2.4';
      return '0';
    }
    if (scoreType === '二级成绩') {
      const num = parseFloat(score);
      if (!isNaN(num)) {
        return num >= 60 ? '3.2' : '0';
      }
      if (score === '通过') return '3.2';
      return '0';
    }
    const num = parseFloat(score);
    if (isNaN(num)) return '0';
    if (num >= 95) return '4.0';
    if (num >= 90) return '3.9';
    if (num >= 84) return '3.8';
    if (num >= 80) return '3.6';
    if (num >= 76) return '3.4';
    if (num >= 73) return '3.2';
    if (num >= 70) return '3.0';
    if (num >= 67) return '2.7';
    if (num >= 64) return '2.4';
    if (num >= 62) return '2.2';
    if (num >= 60) return '2.0';
    return '0';
  }

  private getScoreDisplay(item: ScoreItemModel): string {
    const scoreType = item.djcjlxdmDisplay;
    const zcj = String(item.zcj);
    if (!zcj || zcj === '') return '暂无';

    if (scoreType === '五级成绩') {
      const num = parseFloat(zcj);
      if (!isNaN(num)) {
        if (num >= 90) return '优秀';
        if (num >= 80) return '良好';
        if (num >= 70) return '中等';
        if (num >= 60) return '及格';
        return '不及格';
      }
      return zcj;
    }
    if (scoreType === '二级成绩') {
      const num = parseFloat(zcj);
      if (!isNaN(num)) {
        return num >= 60 ? '通过' : '不通过';
      }
      return zcj;
    }
    return zcj;
  }

  private getScoreColor(score: string): string {
    const s = String(score);
    const num: number = parseFloat(s);
    if (isNaN(num)) {
      if (s === '优秀') return '#43A047';
      if (s === '良好') return '#1976D2';
      if (s === '中等') return '#FFB300';
      if (s === '通过') return '#43A047';
      if (s === '不通过' || s === '不及格') return '#FF5252';
      return '#999999';
    }
    if (num >= 90) return '#43A047';
    if (num >= 80) return '#1976D2';
    if (num >= 70) return '#FFB300';
    if (num >= 60) return '#FF7043';
    return '#FF5252';
  }

  private getTagLabel(item: ScoreItemModel): string {
    if (item.xgxklbdmDisplay) {
      const parts: string[] = item.xgxklbdmDisplay.split('/');
      return parts[parts.length - 1];
    }
    if (item.kclbdmDisplay) {
      return item.kclbdmDisplay;
    }
    return '';
  }

  private getTagColor(label: string): string {
    if (label.includes('必修') || label.includes('核心') || label.includes('专业')) return '#E3F2FD';
    if (label.includes('选修') || label.includes('任选') || label.includes('通识教育')) return '#FFF3E0';
    if (label.includes('非标') || label.includes('实践') || label.includes('集中')) return '#F3E5F5';
    if (label.includes('限选')) return '#E8F5E9';
    if (label.includes('通识') || label.includes('公共')) return '#E0F7FA';
    if (label.includes('拓展')) return '#FBE9E7';
    return '#F5F5F5';
  }

  private getTagTextColor(label: string): string {
    if (label.includes('必修') || label.includes('核心') || label.includes('专业')) return '#1565C0';
    if (label.includes('选修') || label.includes('任选') || label.includes('通识教育')) return '#E65100';
    if (label.includes('非标') || label.includes('实践') || label.includes('集中')) return '#7B1FA2';
    if (label.includes('限选')) return '#2E7D32';
    if (label.includes('通识') || label.includes('公共')) return '#00838F';
    if (label.includes('拓展')) return '#BF360C';
    return '#757575';
  }

  private async showScoreDetail(item: ScoreItemModel): Promise<void> {
    if (!item.jxbid) {
      AlertDialog.show({ message: '该课程暂无成绩构成信息' });
      return;
    }

    const cacheKey = item.jxbid + '_' + item.xnxqdm;
    if (this.detailCache.has(cacheKey)) {
      this.currentDetail = this.detailCache.get(cacheKey)!;
      this.selectedCell = item;
      this.animateShowCard();
      return;
    }

    this.selectedCell = item;
    this.detailLoading = true;
    this.currentDetail = [];
    this.animateShowCard();

    try {
      const details = await ScoreService.getInstance().getScoreDetail(item.jxbid, item.xnxqdm);
      this.currentDetail = details;
      this.detailCache.set(cacheKey, details);
    } catch (e) {
      AlertDialog.show({ message: '获取成绩构成失败' });
    } finally {
      this.detailLoading = false;
    }
  }

  // 优化：背景遮罩和弹窗同步动画，增强层次感
  private animateShowCard(): void {
    this.cardScale = 0.85;
    this.cardOpacity = 0;
    this.maskOpacity = 0;
    animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
      this.cardScale = 1;
      this.cardOpacity = 1;
      this.maskOpacity = 0.7; // 背景变暗到70%透明度，凸显弹窗
    });
  }

  private hideScoreDetail(): void {
    animateTo({ duration: 180, curve: Curve.EaseIn, onFinish: () => {
      this.selectedCell = null;
    }}, () => {
      this.cardScale = 0.85;
      this.cardOpacity = 0;
      this.maskOpacity = 0; // 背景恢复透明
    });
  }

  build() {
    NavDestination() {
      Stack() {
        // 第一层：主页面内容（最底层）
        Column() {

          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.semesterCodes, (code: string) => {
                Button(SemesterUtil.formatSemester(code))
                  .fontSize(12)
                  .fontColor(code === this.selectedSemester ? '#FFFFFF' : '#333333')
                  .backgroundColor(code === this.selectedSemester ? '#4CAF50' : '#F0F0F0')
                  .borderRadius(16)
                  .height(32)
                  .onClick(() => {
                    this.selectedSemester = code;
                    this.currentScores = this.allScores.filter((it: ScoreItemModel) => it.xnxqdm === code);
                  })
              }, (code: string) => 'sem_' + code)
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .height(44)
          .backgroundColor(ThemeColors.bgCard)

          Divider().color('#F0F0F0')

          if (this.loading) {
            Column() {
              LoadingProgress().width(40).height(40).color('#4CAF50')
              Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else if (this.errorMsg.length > 0) {
            Column() {
              Text('⚠️').fontSize(40)
              Text(this.errorMsg).fontSize(14).fontColor(ThemeColors.error).margin({ top: 8 })
              Button('重试').margin({ top: 12 }).onClick(() => { this.loadScores(); })
            }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            List() {
              ForEach(this.currentScores, (item: ScoreItemModel, idx?: number) => {
                ListItem() {
                  Row() {
                    Column() {
                      Text(item.xskcm)
                        .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row({ space: 6 }) {
                        if (this.getTagLabel(item)) {
                          Text(this.getTagLabel(item))
                            .fontSize(10)
                            .fontColor(this.getTagTextColor(this.getTagLabel(item)))
                            .backgroundColor(this.getTagColor(this.getTagLabel(item)))
                            .borderRadius(4)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        }
                        if (item.cxckdmDisplay && item.cxckdmDisplay !== '初修') {
                          Text(item.cxckdmDisplay)
                            .fontSize(10).fontColor(ThemeColors.error)
                            .backgroundColor(ThemeColors.isDark ? '#3E1A1A' : '#FFEBEE').borderRadius(4)
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        }
                        if (item.xf) {
                          Text(item.xf + '学分')
                            .fontSize(11).fontColor(ThemeColors.textSecondary)
                        }
                      }.margin({ top: 6 })
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                    Column() {
                      Text(this.getScoreDisplay(item))
                        .fontSize(22).fontWeight(FontWeight.Bold)
                        .fontColor(this.getScoreColor(item.zcj))
                      if (item.zcj) {
                        Text('绩点 ' + this.scoreToGPA(item.zcj, item.djcjlxdmDisplay))
                          .fontSize(10).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                      }
                    }.alignItems(HorizontalAlign.End)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                  .alignItems(VerticalAlign.Center)
                  .onClick(() => {
                    this.showScoreDetail(item);
                  })
                }
              }, (item: ScoreItemModel, idx?: number) => `score_${item.xnxqdm}_${item.xskcm}_${idx}`)
            }
            .divider({ strokeWidth: 0.5, color: '#F5F5F5' })
            .layoutWeight(1)
          }
        }
        .width('100%').height('100%').backgroundColor(ThemeColors.bgCard)
        .zIndex(0) // 明确层级：主页面在最底层

        // 第二层：半透明背景遮罩（中间层）
        if (this.selectedCell !== null) {
          Column()
            .width('100%').height('100%')
            .backgroundColor('rgba(0,0,0,0.7)') // 加深背景透明度，增强层次感
            .opacity(this.maskOpacity)
            .onClick(() => { this.hideScoreDetail(); })
            .zIndex(1) // 遮罩在主页面之上
        }

        // 第三层：成绩构成详情弹窗（最顶层）
        if (this.selectedCell !== null) {
          Column() {
            // 顶部色条（用成绩颜色）
            Row().width('100%').height(4)
              .backgroundColor(this.getScoreColor(this.selectedCell.zcj))
              .borderRadius({ topLeft: 12, topRight: 12 })

            // 课程名
            Text(this.selectedCell.xskcm)
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .margin({ top: 16, bottom: 12 }).width('100%')

            Divider().color('#F0F0F0')

            // 成绩+绩点概览
            Row() {
              Column() {
                Text('成绩').fontSize(12).fontColor(ThemeColors.textSecondary)
                Text(this.getScoreDisplay(this.selectedCell))
                  .fontSize(24).fontWeight(FontWeight.Bold)
                  .fontColor(this.getScoreColor(this.selectedCell.zcj))
                  .margin({ top: 4 })
              }.alignItems(HorizontalAlign.Start)

              Blank()

              Column() {
                Text('绩点').fontSize(12).fontColor(ThemeColors.textSecondary)
                Text(this.scoreToGPA(this.selectedCell.zcj, this.selectedCell.djcjlxdmDisplay))
                  .fontSize(24).fontWeight(FontWeight.Bold)
                  .fontColor('#1976D2')
                  .margin({ top: 4 })
              }.alignItems(HorizontalAlign.End)
            }
            .width('100%')
            .padding({ top: 12, bottom: 12 })

            Divider().color('#F0F0F0')

            // 成绩构成详情列表
            if (this.detailLoading) {
              Column() {
                LoadingProgress().width(32).height(32).color('#4CAF50')
                  .margin({ top: 20, bottom: 20 })
              }.width('100%')
            } else if (this.currentDetail.length === 0) {
              Column() {
                Text('暂无成绩构成信息')
                  .fontSize(14).fontColor(ThemeColors.textSecondary)
                  .margin({ top: 20, bottom: 20 })
              }.width('100%')
            } else {
              Column({ space: 10 }) {
                ForEach(this.currentDetail, (detail: ComposeDetail) => {
                  Row() {
                    Text(detail.content)
                      .fontSize(14).fontColor(ThemeColors.textPrimary)
                      .layoutWeight(1)
                    Text(detail.ratio)
                      .fontSize(14).fontColor(ThemeColors.textSecondary)
                      .margin({ right: 16 })
                    Text(detail.score)
                      .fontSize(14).fontWeight(FontWeight.Medium)
                      .fontColor(this.getScoreColor(detail.score))
                      .width(60).textAlign(TextAlign.End)
                  }
                  .width('100%')
                }, (detail: ComposeDetail) => detail.content)
              }
              .width('100%')
              .margin({ top: 12 })
            }
          }
          .width('75%')
          .padding({ left: 20, right: 20, bottom: 20 })
          .backgroundColor(ThemeColors.bgInput)
          .borderRadius(12)
          .shadow({
            radius: 24,
            color: 'rgba(0,0,0,0.25)', // 增强阴影，让弹窗更突出
            offsetY: 10
          })
          .scale({ x: this.cardScale, y: this.cardScale })
          .opacity(this.cardOpacity)
          .zIndex(2) // 弹窗在最顶层
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('成绩查询')
    .onReady((ctx: NavDestinationContext) => {})
    .onBackPressed(() => {
      if (this.selectedCell !== null) {
        this.selectedCell = null;
        this.cardScale = 0.85;
        return true;
      }
      return false;
    })
  }}