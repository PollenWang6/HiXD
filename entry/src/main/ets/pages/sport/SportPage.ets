// SportPage.ets — 体育信息页面（体测成绩 + 课程信息）
// 从 Flutter 版 sport_window.dart / sport_score_window.dart / sport_class_window.dart 移植
import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SportService, SportScore, SportScoreOfYear, SportClassItem, SportItem, SportScoreComponent } from '../../services/SportService';

const WEEKDAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

@Component
export struct SportPage {
  pageInfo: NavPathStack = new NavPathStack();
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  @State currentTab: number = 0;
  @State indicatorBase: number = 0;
  @State indicatorSwipe: number = 0;
  @State barW: number = 360;
  private swiperCtrl: SwiperController = new SwiperController();
  private swiperWidth: number = 360;
  private perTabW: number = 180;

  // 体测成绩
  @State scoreLoading: boolean = false;
  @State scoreErrorMsg: string = '';
  @State sportScore: SportScore | null = null;

  // 课程信息
  @State classLoading: boolean = false;
  @State classErrorMsg: string = '';
  @State classList: SportClassItem[] = [];
  @State expandedTermId: string = ''; // 当前展开成绩构成的学期

  // 密码弹窗
  @State showPwdDialog: boolean = false;
  @State pwdInput: string = '';
  @State pwdOpacity: number = 0;
  @State pwdTranslate: number = 30;
  @State pwdVisible: boolean = false;

  private sport: SportService = SportService.getInstance();

  @Builder
  buildWhiteTitle(t: string) {
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
        .fontColor(Color.White)
        .layoutWeight(1)
    }
    .width('100%')
    .height(52 + this.statusBarHeight)
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
  }

  aboutToAppear(): void {
    if (!SportService.hasPassword()) {
      this.pwdInput = '';
      this.showPwdDialog = true;
      animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
        this.pwdOpacity = 1;
        this.pwdTranslate = 0;
      });
    } else {
      this.loadScore();
    }
  }

  // ===== 数据加载 =====

  async loadScore(): Promise<void> {
    if (!SportService.hasPassword()) {
      this.scoreErrorMsg = '请先设置体育系统密码';
      return;
    }
    this.scoreLoading = true;
    this.scoreErrorMsg = '';
    try {
      this.sportScore = await this.sport.getScore();
    } catch (e) {
      this.scoreErrorMsg = (e as Error).message || '获取成绩失败';
    } finally {
      this.scoreLoading = false;
    }
  }

  async loadClass(): Promise<void> {
    if (!SportService.hasPassword()) {
      this.classErrorMsg = '请先设置体育系统密码';
      return;
    }
    this.classLoading = true;
    this.classErrorMsg = '';
    try {
      this.classList = await this.sport.getClass();
      console.info('SportPage', 'loadClass result: ' + this.classList.length + ' items');
    } catch (e) {
      this.classErrorMsg = (e as Error).message || '获取课程信息失败';
    } finally {
      this.classLoading = false;
    }
  }

  // ===== 辅助方法 =====

  private isQualified(rank: string): boolean {
    return rank.indexOf('不') < 0;
  }

  private unitToShow(evalStr: string): string {
    const idx: number = evalStr.indexOf('.');
    return idx >= 0 ? evalStr.substring(0, idx) : evalStr;
  }

  private scoreRankDisplay(rank: string, listLen: number): string {
    return listLen < 4 ? '未知' : rank;
  }

  private detailFirstLine(detail: string): string {
    const idx: number = detail.indexOf('\\');
    return idx >= 0 ? detail.substring(0, idx) : detail;
  }

  // ===== 体测成绩 Tab =====

  @Builder
  ScoreTab() {
    Column() {
      if (this.scoreLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.accentColor)
          Text('正在加载...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 8 })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.scoreErrorMsg.length > 0) {
        this.ErrorState(this.scoreErrorMsg, () => { this.loadScore(); })
      } else if (this.sportScore) {
        this.ScoreContent()
      } else {
        Column() {
          Text('暂无数据').fontSize(14).fontColor(ThemeColors.textSecondary)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      }
    }.width('100%').height('100%')
  }

  @Builder
  ScoreContent() {
    Scroll() {
      Column({ space: 8 }) {
        // 总成绩卡片
        this.TotalScoreCard()
        // 各学年成绩卡片（倒序）
        if (this.sportScore && this.sportScore.list.length > 0) {
          ForEach(this.sportScore.list.slice().reverse(), (item: SportScoreOfYear) => {
            this.YearScoreCard(item)
          }, (item: SportScoreOfYear, idx: number) => item.year + idx.toString())
        }
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 16 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
  }

  @Builder
  TotalScoreCard() {
    if (this.sportScore) {
      Column() {
        Text('总成绩').fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .padding({ left: 16, top: 14, bottom: 8 })

        // 总分 + 排名
        Row() {
          // 总分
          Column() {
            Text('总分').fontSize(11).fontColor(ThemeColors.textSecondary)
            Text(this.sportScore.total)
              .fontSize(20).fontWeight(FontWeight.Bold)
              .fontColor(this.isQualified(this.sportScore.rank) ? '#2E7D32' : '#C62828')
              .margin({ top: 4 })
          }.layoutWeight(1).alignItems(HorizontalAlign.Center)

          // 排名
          Column() {
            Text('评级').fontSize(11).fontColor(ThemeColors.textSecondary)
            Text(this.scoreRankDisplay(this.sportScore.rank, this.sportScore.list.length))
              .fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor(this.isQualified(this.sportScore.rank) ? '#2E7D32' : '#C62828')
              .margin({ top: 4 })
          }.layoutWeight(1).alignItems(HorizontalAlign.Center)
        }
        .width('100%').padding({ top: 8, bottom: 12 })

        Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 16, right: 16 })

        Text(this.detailFirstLine(this.sportScore.detail))
          .fontSize(12).fontColor(ThemeColors.textSecondary)
          .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
      .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
    }
  }

  @Builder
  YearScoreCard(item: SportScoreOfYear) {
    Column() {
      // 标题行：学年 + 总分
      Row() {
        Text(item.year + ' ' + item.gradeType)
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.totalScore)
          .fontSize(14).fontWeight(FontWeight.Bold)
          .fontColor(this.isQualified(item.rank) ? '#2E7D32' : '#C62828')
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 8 })

      Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 16, right: 16 })

      if (item.details.length > 0) {
        // 表头
        Row() {
          Text('项目').fontSize(12).fontColor(ThemeColors.textSecondary).layoutWeight(1.2)
          Text('数据').fontSize(12).fontColor(ThemeColors.textSecondary).layoutWeight(1.4)
          Text('分数').fontSize(12).fontColor(ThemeColors.textSecondary).layoutWeight(0.8)
          Text('合格').fontSize(12).fontColor(ThemeColors.textSecondary).layoutWeight(0.4).textAlign(TextAlign.End)
        }
        .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })

        // 各项目
        ForEach(item.details, (d: SportItem, idx: number) => {
          Row() {
            Text(d.examName).fontSize(13).fontColor(ThemeColors.textPrimary).layoutWeight(1.2)
            Text(d.actualScore.indexOf('/') >= 0
              ? d.actualScore.split('/')[0] + 'cm/' + d.actualScore.split('/')[1] + 'kg'
              : d.actualScore + this.unitToShow(d.examUnit))
              .fontSize(13).fontColor(ThemeColors.textPrimary).layoutWeight(1.4)
            Text(d.score.toString()).fontSize(13).fontColor(ThemeColors.textPrimary).layoutWeight(0.8)
            Text(d.score >= 60 ? '✓' : '✗')
              .fontSize(14).fontWeight(FontWeight.Bold)
              .fontColor(d.score >= 60 ? '#2E7D32' : '#C62828')
              .layoutWeight(0.4).textAlign(TextAlign.End)
          }
          .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })
        }, (d: SportItem, idx: number) => d.examName + idx.toString())

        // 评级
        Row() {
          Text('评级: ' + item.rank)
            .fontSize(12).fontColor(this.isQualified(item.rank) ? '#2E7D32' : '#C62828')
        }
        .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 12 })
      } else {
        Text(item.moreInfo.length > 0 ? item.moreInfo : '暂无明细数据')
          .fontSize(13).fontColor(ThemeColors.textSecondary)
          .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
    }
    .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
  }

  // ===== 课程信息 Tab =====

  @Builder
  ClassTab() {
    Column() {
      if (this.classLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.accentColor)
          Text('正在加载...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 8 })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.classErrorMsg.length > 0) {
        this.ErrorState(this.classErrorMsg, () => { this.loadClass(); })
      } else if (this.classList.length === 0) {
        Column() {
          Text('🏀').fontSize(48).margin({ bottom: 12 })
          Text('暂无体育课程信息').fontSize(14).fontColor(ThemeColors.textSecondary)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.classList, (item: SportClassItem, idx: number) => {
              this.ClassCard(item)
            }, (item: SportClassItem, idx: number) => item.term + item.name + idx.toString())
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 16 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }
    }.width('100%').height('100%')
  }

  @Builder
  ClassCard(item: SportClassItem) {
    Column() {
      // 标题行
      Row() {
        Text(item.termToShow)
          .fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.score.length > 0 && /\d/.test(item.score)) {
          Text(item.score + '分')
            .fontSize(13).fontColor(Color.White)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.accentColor)
        }
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 8 })

      Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 16, right: 16 })

      // 课程名
      Row() {
        Text('📚').fontSize(14).margin({ right: 8 })
        Text(item.name).fontSize(14).fontColor(ThemeColors.textPrimary).layoutWeight(1)
      }
      .width('100%').padding({ left: 16, right: 16, top: 8 })

      // 时间
      Row() {
        Text('🕐').fontSize(14).margin({ right: 8 })
        Text(item.week > 0 && item.week <= 7
          ? WEEKDAY_NAMES[item.week - 1] + ' 第' + item.start + '-' + item.stop + '节'
          : '时间未解析')
          .fontSize(13).fontColor(ThemeColors.textSecondary)
      }
      .width('100%').padding({ left: 16, right: 16, top: 4 })

      // 教师 + 地点
      Row() {
        Text('👨‍🏫').fontSize(14).margin({ right: 8 })
        Text(item.teacher).fontSize(13).fontColor(ThemeColors.textSecondary).layoutWeight(1)
        Text('📍').fontSize(14).margin({ right: 4 })
        Text(item.place).fontSize(13).fontColor(ThemeColors.textSecondary).layoutWeight(1)
      }
      .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 8 })

      // 成绩构成明细（有分数且有明细数据时显示）
      if (item.scoreComponents.length > 0 && /\d/.test(item.score)) {
        // 分隔线
        Divider().color('#F0F0F0').strokeWidth(0.5).margin({ left: 16, right: 16 })

        // 展开切换按钮
        Row() {
          Text('📊 成绩构成').fontSize(13).fontColor(ThemeColors.textSecondary)
            .layoutWeight(1)
          Text(this.expandedTermId === item.termScoreId ? '收起 ▲' : '展开 ▼')
            .fontSize(12).fontColor(this.accentColor)
        }
        .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })
        .onClick(() => {
          this.expandedTermId = this.expandedTermId === item.termScoreId ? '' : item.termScoreId;
        })

        // 展开内容
        if (this.expandedTermId === item.termScoreId) {
          this.ScoreComponentsContent(item.scoreComponents)
        }
      }
    }
    .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
  }

  @Builder
  ScoreComponentsContent(components: SportScoreComponent[]) {
    Column() {
      // 表头
      Row() {
        Text('项目').fontSize(11).fontColor(ThemeColors.textSecondary).layoutWeight(1.2)
        Text('成绩').fontSize(11).fontColor(ThemeColors.textSecondary).layoutWeight(0.8)
        Text('比例').fontSize(11).fontColor(ThemeColors.textSecondary).layoutWeight(0.6)
        Text('得分').fontSize(11).fontColor(ThemeColors.textSecondary).layoutWeight(0.8).textAlign(TextAlign.End)
      }
      .width('100%').padding({ left: 16, right: 16, top: 6, bottom: 4 })
      .backgroundColor('#FAFAFA')

      // 各项明细（跳过第一行表头数据）
      ForEach(components.slice(1), (c: SportScoreComponent, idx: number) => {
        Row() {
          Text(c.exam).fontSize(12).fontColor(ThemeColors.textPrimary).layoutWeight(1.2)
          Text(c.fenshu).fontSize(12).fontColor(ThemeColors.textPrimary).layoutWeight(0.8)
          Text(parseFloat(c.bili) > 0 ? (parseFloat(c.bili) * 100).toFixed(0) + '%' : '—')
            .fontSize(12).fontColor(ThemeColors.textSecondary).layoutWeight(0.6)
          Text(c.score).fontSize(12).fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary).layoutWeight(0.8).textAlign(TextAlign.End)
        }
        .width('100%').padding({ left: 16, right: 16, top: 3, bottom: 3 })
      }, (c: SportScoreComponent, idx: number) => c.exam + idx.toString())
    }
    .padding({ bottom: 8 })
  }

  // ===== 错误状态 =====

  @Builder
  ErrorState(msg: string, onRetry: () => void) {
    Column() {
      Text('⚠️').fontSize(40).margin({ bottom: 12 })
      Text(msg).fontSize(14).fontColor(ThemeColors.textSecondary)
        .textAlign(TextAlign.Center).margin({ left: 32, right: 32, bottom: 16 })
      Button('重试')
        .fontSize(14).fontColor(Color.White)
        .backgroundColor(this.accentColor)
        .borderRadius(20)
        .padding({ left: 24, right: 24, top: 8, bottom: 8 })
        .onClick(() => { onRetry(); })
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  // ===== 密码弹窗 =====

  @Builder
  PwdDialog() {
    if (this.showPwdDialog) {
      Stack() {
        // 遮罩
        Column()
          .width('100%').height('100%')
          .backgroundColor('#80000000')
          .opacity(this.pwdOpacity)
          .onClick(() => {
            animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
              this.pwdOpacity = 0;
              this.pwdTranslate = 30;
            });
            setTimeout(() => { this.showPwdDialog = false; }, 200);
          })

        // 弹窗内容
        Column() {
          Column() {
            Text('体育系统密码').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
              .margin({ bottom: 16 })

            Text('体育系统使用独立密码（与统一身份认证密码不同），请输入您的体育系统密码。')
              .fontSize(12).fontColor(ThemeColors.textSecondary)
              .margin({ bottom: 16 })

            TextInput({ placeholder: '请输入体育系统密码', text: this.pwdInput })
              .type(this.pwdVisible ? InputType.Normal : InputType.Password)
              .fontSize(15)
              .borderRadius(8)
              .backgroundColor(ThemeColors.bgPage)
              .width('100%')
              .onChange((v: string) => { this.pwdInput = v; })

            Row() {
              Text(this.pwdVisible ? '隐藏密码' : '显示密码')
                .fontSize(13).fontColor(this.accentColor)
                .onClick(() => { this.pwdVisible = !this.pwdVisible; })
            }.width('100%').margin({ top: 8 })

            Row() {
              Blank()
              Button('取消')
                .fontSize(14).fontColor(ThemeColors.textSecondary)
                .backgroundColor(ThemeColors.bgPage)
                .borderRadius(20)
                .padding({ left: 20, right: 20, top: 8, bottom: 8 })
                .margin({ right: 12 })
                .onClick(() => {
                  animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
                    this.pwdOpacity = 0;
                    this.pwdTranslate = 30;
                  });
                  setTimeout(() => { this.showPwdDialog = false; }, 200);
                })
              Button('确定')
                .fontSize(14).fontColor(Color.White)
                .backgroundColor(this.accentColor)
                .borderRadius(20)
                .padding({ left: 20, right: 20, top: 8, bottom: 8 })
                .onClick(async () => {
                  if (this.pwdInput.length === 0) return;
                  await PreferenceUtil.putString('sport_password', this.pwdInput);
                  animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
                    this.pwdOpacity = 0;
                    this.pwdTranslate = 30;
                  });
                  setTimeout(() => {
                    this.showPwdDialog = false;
                    this.loadScore();
                  }, 200);
                })
            }.width('100%').margin({ top: 16 })
          }
          .width('80%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor(ThemeColors.bgCard)
          .translate({ y: this.pwdTranslate })
          .opacity(this.pwdOpacity)
          .onClick(() => {})
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%').height('100%')
      .position({ x: 0, y: 0 })
    }
  }

  // ===== 主构建 =====

  build() {
    NavDestination() {
    Column() {
      // 标题栏
      Column() {
        this.buildWhiteTitle('体育信息')
      }
      .width('100%')
      .backgroundColor(this.accentColor)

      // Tab 栏（单条滑动指示器）
      Stack({ alignContent: Alignment.BottomStart }) {
        Row() {
          Column() {
            Text('体测成绩').fontSize(15)
              .fontColor(this.currentTab === 0 ? this.accentColor : ThemeColors.textSecondary)
              .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
          }
          .layoutWeight(1).height(44).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.currentTab = 0;
            animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
              this.indicatorBase = 0;
              this.indicatorSwipe = 0;
            });
            this.swiperCtrl.changeIndex(0, true);
            if (!this.sportScore && !this.scoreLoading) this.loadScore();
          })

          Column() {
            Text('课程信息').fontSize(15)
              .fontColor(this.currentTab === 1 ? this.accentColor : ThemeColors.textSecondary)
              .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
          }
          .layoutWeight(1).height(44).justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.currentTab = 1;
            animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
              this.indicatorBase = this.perTabW;
              this.indicatorSwipe = 0;
            });
            this.swiperCtrl.changeIndex(1, true);
            if (this.classList.length === 0 && !this.classLoading) this.loadClass();
          })
        }
        .width('100%')
        .onAreaChange((_old: Area, newArea: Area) => {
          this.barW = newArea.width as number;
          this.perTabW = this.barW / 2;
        })

        // 单条滑动指示器
        Row()
          .width(24).height(3)
          .backgroundColor(this.accentColor).borderRadius(1.5)
          .margin({ left: this.indicatorBase + this.indicatorSwipe - 12 + this.barW * 0.25 })
      }
      .width('100%')
      .backgroundColor(ThemeColors.bgCard)
      .border({ width: { bottom: 0.5 }, color: ThemeColors.border })

      // Swiper 内容区
      Swiper(this.swiperCtrl) {
        Column() { this.ScoreTab() }.width('100%')
        Column() { this.ClassTab() }.width('100%')
      }
      .index(this.currentTab)
      .indicator(false)
      .loop(false)
      .onAreaChange((_old: Area, newArea: Area) => {
        this.swiperWidth = newArea.width as number;
      })
      .onGestureSwipe((index: number, event: SwiperAnimationEvent) => {
        const offset: number = event.currentOffset as number;
        const ratio: number = Math.abs(offset) / this.swiperWidth;
        const move: number = ratio >= 1 ? this.perTabW : this.perTabW * ratio;
        this.indicatorSwipe = offset < 0 ? move : -move;
      })
      .onAnimationStart((_index: number, targetIndex: number, _event: SwiperAnimationEvent) => {
        this.currentTab = targetIndex;
        this.indicatorBase = targetIndex === 0 ? 0 : this.perTabW;
        this.indicatorSwipe = 0;
        if (targetIndex === 0) {
          if (!this.sportScore && !this.scoreLoading) this.loadScore();
        } else {
          if (this.classList.length === 0 && !this.classLoading) this.loadClass();
        }
      })
      .layoutWeight(1)

      // 密码弹窗
      Stack() {
        this.PwdDialog()
      }
      .width('100%').height('100%')
      .position({ x: 0, y: 0 })
      .hitTestBehavior(this.showPwdDialog ? HitTestMode.Default : HitTestMode.None)
    }
    .width('100%').height('100%')
    .backgroundColor(ThemeColors.bgPage)
    }
    .hideTitleBar(true)
  }
}
