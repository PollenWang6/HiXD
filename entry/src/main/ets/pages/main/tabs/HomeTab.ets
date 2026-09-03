import { ThemeColors } from '../../../utils/ThemeColors';
import { PreviewCell, SECTION_TIMES } from '../../../models/common/ClassSchedule';
import { LibspSessionWarmup } from '../../library/LibspSessionWarmup';
import { SchoolCardHomeCard } from '../components/SchoolCardHomeCard';
import { AttendanceHomeCard } from '../components/AttendanceHomeCard';
import { HomeDataCard } from '../components/HomeDataCard';
import { PressScale } from '../../../components/PressScale';

// 主页 Tab：顶部导航（登录态）+ 课表预览 + 常用数据卡 + 更多模块 + 登录进度遮罩
// 首页数据卡状态走 @StorageLink 共享，交互通过回调上抛 MainPage。
@Component
export struct HomeTab {
  // 主题/系统状态（AppStorage 共享）
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('ct_updated') ctUpdated: string = '';
  // 首页数据卡（AppStorage 共享）
  @StorageLink('home_elec_remain') snapElecRemain: string = '—';
  @StorageLink('home_elec_readtime') snapElecReadTime: string = '—';
  @StorageLink('home_lib_borrow') snapLibBorrow: string = '—';
  @StorageLink('home_lib_overdue') snapLibOverdue: string = '—';
  @StorageLink('home_exam_name') snapExamName: string = '—';
  @StorageLink('home_exam_countdown') snapExamCountdown: string = '—';
  @StorageLink('home_exam_date') snapExamDate: string = '—';
  @StorageLink('home_exam_has_upcoming') snapExamHasUpcoming: boolean = false;
  @StorageLink('home_net_used') snapNetUsed: string = '—';
  @StorageLink('home_net_devices') snapNetDevices: string = '—';

  // 父级传入状态
  @Prop loginStatus: string = '';
  @Prop homeLoading: boolean = false;
  // 下拉刷新状态：组件内本地管理（下拉→回调上抛→1.5s 后自动复位）
  @State homeRefreshing: boolean = false;
  @Prop userAvatarUrl: string = '';
  @Prop userDisplayName: string = '';
  @Prop username: string = '';
  @Prop loginProgVisible: boolean = false;
  @Prop loginProgMsg: string = '';
  @Prop loginProgPercent: number = 0;
  @Prop previewLoaded: boolean = false;
  @Prop previewCells: PreviewCell[] = [];
  pageInfo: NavPathStack = new NavPathStack();

  // 回调
  onMenuClick: (name: string) => void = (name: string) => {};
  onRelogin: () => void = () => {};
  onLogin: () => void = () => {};
  onRefresh: () => void = () => {};
  onOpenClassTable: () => void = () => {};
  onOpenPayCode: () => void = () => {};

  // 根据主题色亮度选择白色或黑色文字
  accentTextColor(): string {
    const hex = this.accentColor.replace('#', '');
    const r = parseInt(hex.substring(0, 2), 16);
    const g = parseInt(hex.substring(2, 4), 16);
    const b = parseInt(hex.substring(4, 6), 16);
    const lum = (0.299 * r + 0.587 * g + 0.114 * b); // W3C 亮度公式
    return lum > 160 ? '#333333' : '#FFFFFF';
  }

  accentBgIsLight(): boolean {
    const hex = this.accentColor.replace('#', '');
    const r = parseInt(hex.substring(0, 2), 16);
    const g = parseInt(hex.substring(2, 4), 16);
    const b = parseInt(hex.substring(4, 6), 16);
    const lum = (0.299 * r + 0.587 * g + 0.114 * b);
    return lum > 160;
  }

  getTodayDay(): number {
    const dayOfWeek: number = new Date().getDay();
    return dayOfWeek === 0 ? 7 : dayOfWeek;
  }

  // 考试卡：是否还有未开始的考试
  examHasUpcoming(): boolean {
    return this.snapExamHasUpcoming && this.snapExamName !== '—';
  }
  // 考试卡大标题：未取数→'—'，有未考→科目名，无未考→'暂无'
  examBig(): string {
    if (this.snapExamName === '—') { return '—'; }
    return this.examHasUpcoming() ? this.snapExamName : '暂无';
  }
  // 考试卡副信息：有未考→倒计时·日期；无未考→'X门已结束'
  examSub(): string {
    if (this.snapExamName === '—') { return ''; }
    return this.examHasUpcoming() ? (this.snapExamCountdown + ' · ' + this.snapExamDate) : this.snapExamCountdown;
  }

  @Builder
  ClassPreviewCard() {
    // 强制感知课表数据变化
    if (this.ctUpdated.length > 0) { /* do nothing, trigger re-eval */ }
    PressScale({ onTap: () => { this.onOpenClassTable(); } }) {
    if (this.previewLoaded && this.previewCells.length > 0) {
      Column() {
        Row() {
          Text('📅').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Text('  课程预告').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Blank()
          Text('查看课表 >').fontSize(12).fontColor(this.accentColor)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        ForEach(this.previewCells, (cell: PreviewCell, index: number) => {
          Row() {
            Column() {
              if (cell.isExam) {
                Text('考试').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#C2185B')
              } else {
                Text(SECTION_TIMES[cell.startSection - 1][0])
                  .fontSize(13).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                Text(SECTION_TIMES[cell.endSection - 1][1])
                  .fontSize(10).fontColor(ThemeColors.textSecondary)
              }
            }
            .width(46).alignItems(HorizontalAlign.End).padding({ right: 4 })

            Column() {
              Circle().width(10).height(10)
                .fill(cell.isExam ? '#C2185B' : (cell.isExperiment ? '#2979FF' : (cell.isCustom ? '#66BB6A' : '#2979FF')))
                .margin({ top: 4 })
              if (index < this.previewCells.length - 1) {
                Column().width(2).layoutWeight(1).backgroundColor('#E0E0E0').margin({ top: 2 })
              }
            }
            .width(16).height('100%').alignItems(HorizontalAlign.Center)

            Column() {
              Row() {
                if (cell.isExam) {
                  Text('📝考试').fontSize(12).fontColor('#C2185B')
                } else if (cell.isExperiment) {
                  Text('🧪实验').fontSize(12).fontColor('#2979FF')
                } else if (cell.isCustom) {
                  Text('📌自定').fontSize(12).fontColor('#66BB6A')
                }
                Text(cell.name)
                  .fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .margin({ left: cell.isExam || cell.isExperiment || cell.isCustom ? 6 : 0 })
                Text(cell.day === this.getTodayDay() ? '今天' : '明天')
                  .fontSize(11).fontColor(cell.day === this.getTodayDay() ? this.accentTextColor() : '#FFFFFF')
                  .backgroundColor(cell.day === this.getTodayDay() ? this.accentColor : '#2E7D32')
                  .borderRadius(10)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              }
              Row() {
                if (cell.isExam && cell.examTimeDesc.length > 0) {
                  Text(cell.examTimeDesc).fontSize(12).fontColor('#C2185B')
                }
                if (cell.teacher.length > 0) {
                  Text('  ' + cell.teacher)
                    .fontSize(12).fontColor(ThemeColors.textSecondary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                if (cell.classroom.length > 0) {
                  Text('  ' + cell.classroom)
                    .fontSize(12).fontColor(ThemeColors.textSecondary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                if (cell.seat.length > 0) {
                  Text('  ' + cell.seat)
                    .fontSize(12).fontColor(ThemeColors.textSecondary)
                }
              }.margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .padding({ left: 8 })
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
        }, (cell: PreviewCell) => cell.cellKey)
      }
      .width('100%')
      .backgroundColor(ThemeColors.bgCard)
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 12 })
      .shadow({ radius: 4, color: '#1A000000', offsetX: 0, offsetY: 2 })
      
    } else if (this.previewLoaded && this.previewCells.length === 0) {
      Column() {
        Row() {
          Text('📅').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Text('  课程预告').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Blank()
          Text('查看课表 >').fontSize(12).fontColor(this.accentColor)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        Text('🌸 😴 ✨ 🌙 🐢').fontSize(28).padding({ top: 8, bottom: 4 })
        Text('当前没课，好好休息吧！')
          .fontSize(18).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
          .padding({ bottom: 16 })
      }
      .width('100%')
      .backgroundColor(ThemeColors.bgCard)
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 12 })
      .shadow({ radius: 4, color: '#1A000000', offsetX: 0, offsetY: 2 })
      
        }}
  }

  @Builder
  MoreModuleTile(icon: string, title: string, name: string) {
    PressScale({ onTap: () => { this.onMenuClick(name); } }) {
      Column() {
        Text(icon).fontSize(26)
        Text(title).fontSize(12).fontColor(ThemeColors.textPrimary).margin({ top: 6 })
      }
      .width('100%').padding({ top: 17, bottom: 17 })
      .backgroundColor(ThemeColors.bgCard).borderRadius(14)
      .shadow({ radius: 10, color: '#00000014', offsetY: 3 }).border({ width: 1, color: ThemeColors.border })
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  HomeDataSection() {
    Row() {
      Text('常用').fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      Blank()
      if (this.homeLoading) {
        LoadingProgress().width(18).height(18).color(this.accentColor)
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 8 })

    Grid() {
      GridItem() {
        SchoolCardHomeCard({
          homeLoading: this.homeLoading,
          onTap: () => { this.onMenuClick('SchoolCard'); },
          onPayCode: () => { this.onOpenPayCode(); }
        })
      }.columnStart(0).columnEnd(1)
      GridItem() {
        AttendanceHomeCard({
          homeLoading: this.homeLoading,
          onTap: () => { this.onMenuClick('Attendance'); }
        })
      }.columnStart(0).columnEnd(1)
      GridItem() {
        HomeDataCard({
          icon: '⚡', title: '电费', tag: '余额',
          big: this.snapElecRemain === '—' ? '—' : this.snapElecRemain + ' kWh',
          sub: this.snapElecReadTime === '—' ? '' : ('上次读数 ' + this.snapElecReadTime),
          color: '#BF4D00', loading: this.homeLoading,
          onTap: () => { this.onMenuClick('Electricity'); }
        })
      }
      GridItem() {
        HomeDataCard({
          icon: '📚', title: '图书馆', tag: '在借',
          big: this.snapLibBorrow + ' 本',
          sub: '逾期 ' + this.snapLibOverdue, color: '#8E24AA', loading: this.homeLoading,
          onTap: () => { this.onMenuClick('Library'); }
        })
      }
      GridItem() {
        HomeDataCard({
          icon: '📝', title: '最近考试',
          big: this.examBig(),
          sub: this.examSub(), color: '#BF4D00', loading: this.homeLoading,
          onTap: () => { this.onMenuClick('Exam'); }
        })
      }
      GridItem() {
        HomeDataCard({
          icon: '🌐', title: '校园网',
          big: this.snapNetUsed,
          sub: this.snapNetDevices, color: '#00ACC1', loading: this.homeLoading,
          onTap: () => { this.onMenuClick('SchoolNet'); }
        })
      }
    }
    .columnsTemplate('1fr 1fr').columnsGap(12).rowsGap(12)
    .width('100%').padding({ left: 16, right: 16 })

    Text('更多模块').fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      .width('100%').padding({ left: 16, right: 16, top: 20, bottom: 8 })
    Grid() {
      GridItem() { this.MoreModuleTile('📝', '成绩查询', 'Score') }
      GridItem() { this.MoreModuleTile('🏫', '空闲教室', 'EmptyClass') }
      GridItem() { this.MoreModuleTile('🔬', '实验信息', 'Experiment') }
      GridItem() { this.MoreModuleTile('🪑', '座位预约', 'Seat') }
      GridItem() { this.MoreModuleTile('🚰', '宿舍水机', 'Water') }
      GridItem() { this.MoreModuleTile('🏀', '体育信息', 'Sport') }
    }
    .columnsTemplate('1fr 1fr 1fr').columnsGap(12).rowsGap(12)
    .width('100%').padding({ left: 16, right: 16, bottom: 24 })
  }

  build() {
    Stack() {
      // 图书馆会话后台预热：全屏 Visible 底层 WebView（ArkWeb 对不可见/离屏 WebView 会节流 SSO 自动跳转而卡在 CAS 页，
      // 故不可 Hidden/离屏）。上方紧跟全屏不透明 bgPage 遮罩盖住它（用户不可见），hitTestBehavior None 不拦截首页事件。
      LibspSessionWarmup()
        .width('100%').height('100%')
      Column().width('100%').height('100%').backgroundColor(ThemeColors.bgPage)

      Column() {
        // 顶部导航栏
        Row() {
          Column() {
            Text('HiXD').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.accentTextColor())
            if (this.loginStatus === 'ok') {
              Text('已登录').fontSize(11).fontColor(this.accentTextColor())
            } else if (this.loginStatus === 'expired') {
              Text('登录已过期').fontSize(11).fontColor(this.accentTextColor())
            } else if (this.loginStatus === 'not_logged_in') {
              Text('未登录').fontSize(11).fontColor(this.accentTextColor())
            } else if (this.loginStatus === 'offline') {
              Text('离线模式').fontSize(11).fontColor(this.accentTextColor())
            } else if (this.loginStatus === 'timeout') {
              Text('登录超时').fontSize(11).fontColor(this.accentTextColor())
            } else if (this.loginStatus === 'checking') {
              Text('正在验证...').fontSize(11).fontColor(this.accentTextColor())
            }
          }
          Blank()
          if (this.loginStatus === 'ok') {
            Stack() {
              Circle().width(32).height(32).fill(this.accentBgIsLight() ? '#00000026' : '#FFFFFF33')
              if (this.userAvatarUrl) {
                Image(this.userAvatarUrl).width(32).height(32).borderRadius(16).objectFit(ImageFit.Cover)
              } else {
                Text('🎓').fontSize(18).fontColor(this.accentTextColor())
              }
            }.width(32).height(32)
            Text(this.userDisplayName || this.username || '已登录').fontSize(13)
              .fontColor(this.accentTextColor()).margin({ left: 8 })
          } else if (this.loginStatus === 'checking' || this.loginStatus === '') {
            LoadingProgress()
              .width(22).height(22)
              .color(this.accentTextColor())
              .margin({ right: 6 })
          } else if (this.loginStatus === 'expired' || this.loginStatus === 'timeout' ||
              this.loginStatus === 'offline' || this.loginStatus === 'not_logged_in') {
            Button(this.loginStatus === 'expired' || this.loginStatus === 'timeout' ? '重新登录' : '登录')
              .height(28).fontSize(12)
              .fontColor(ThemeColors.isDark ? '#FFFFFF' : '#333333')
              .backgroundColor(ThemeColors.isDark ? '#333333' : '#FFFFFF')
              .borderRadius(14)
              .padding({ left: 12, right: 12 })
              .hoverEffect(HoverEffect.Auto).onClick(() => {
                if (this.loginStatus === 'expired' || this.loginStatus === 'offline') {
                  this.onRelogin();
                } else {
                  this.onLogin();
                }
              })
          }
        }
        .width('100%').height(52 + this.statusBarHeight).padding({ left: 20, right: 16, top: this.statusBarHeight })
        .backgroundColor(this.accentColor)

        Refresh({ refreshing: $$this.homeRefreshing }) {
          Scroll() {
            Column() {
              this.ClassPreviewCard()
              this.HomeDataSection()
            }
            .width('100%').padding({ bottom: 160 })
          }
          .width('100%').layoutWeight(1).align(Alignment.TopStart).edgeEffect(EdgeEffect.Spring)
        }
        .onRefreshing(() => {
          this.homeRefreshing = true;
          this.onRefresh();
          setTimeout(() => { this.homeRefreshing = false; }, 1500);
        })
      }
      .width('100%').height('100%')

      // 自动重登录进度遮罩（加载登录页 → 滑块验证 → 登录成功）
      if (this.loginProgVisible) {
        Stack() {
          Column() {
            LoadingProgress().width(40).height(40).color(this.accentColor)
            Text(this.loginProgMsg)
              .fontSize(15).fontColor(ThemeColors.textPrimary).margin({ top: 14 })
              .constraintSize({ maxWidth: '80%' }).textAlign(TextAlign.Center)
            Progress({ value: this.loginProgPercent, total: 100, type: ProgressType.Linear })
              .width('70%').height(6).margin({ top: 16 })
              .color(this.accentColor).backgroundColor(ThemeColors.bgInput)
            Text(this.loginProgPercent + '%')
              .fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 8 })
          }
          .padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%').height('100%').backgroundColor(0x66000000)
        .alignContent(Alignment.Center)
      }
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
  }
}
