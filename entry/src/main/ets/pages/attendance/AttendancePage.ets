// AttendancePage.ets — 考勤查询页面
import { AttendanceService } from '../../services/AttendanceService';
import { ClassAttendance, ClassAttendanceDetail, AttendanceStatus } from '../../services/AttendanceModels';
import { ThemeColors } from '../../utils/ThemeColors';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { SemesterUtil } from '../../services/EhallService';

@Component
export struct AttendancePage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State courses: ClassAttendance[] = [];
  @State showDetail: boolean = false;
  @State detailMaskOpacity: number = 0;
  @State detailSheetOffset: number = 100; // % 从底部偏移
  @State detailCourses: ClassAttendanceDetail[] = [];
  @State detailCourseName: string = '';
  @State detailLoading: boolean = false;

  // 预计算分组
  @State ineligible: ClassAttendance[] = [];
  @State warning: ClassAttendance[] = [];
  @State eligible: ClassAttendance[] = [];
  @State unknown: ClassAttendance[] = [];

  private service: AttendanceService = AttendanceService.getInstance();

  aboutToAppear(): void {
    this.loadData();
  }

  async loadData(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const data: ClassAttendance[] = await this.service.getAttendanceRecords();
      console.info('AttendancePage', 'loaded ' + String(data.length) + ' courses');
      for (let i = 0; i < data.length; i++) {
        const c = data[i];
        console.info('AttendancePage', '  [' + String(i) + '] ' + c.courseName +
          ' rate=' + c.attendanceRate + ' absence=' + c.absenceCount +
          ' required=' + c.requiredCheckIn + ' totalTimes=' + String(c.totalTimes) +
          ' status=' + c.getStatusLabel() + ' id=' + c.courseId + '/' + c.clazzId);
      }
      this.courses = data;
      // 从本地课表计算每门课的总课数（对齐 Flutter numberOfClassComputedSignal）
      this.fillTotalTimes();
      this.updateGroups();
    } catch (e) {
      this.errorMsg = '加载失败，请检查登录状态';
      console.error('AttendancePage loadData error: ' + String(e));
    } finally {
      this.loading = false;
    }
  }

  private updateGroups(): void {
    const ineli: ClassAttendance[] = [];
    const warn: ClassAttendance[] = [];
    const elig: ClassAttendance[] = [];
    const unk: ClassAttendance[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      const course: ClassAttendance = this.courses[i];
      const status: AttendanceStatus = course.getAttendanceStatus();
      switch (status) {
        case AttendanceStatus.INELIGIBLE:
          ineli.push(course); break;
        case AttendanceStatus.WARNING:
          warn.push(course); break;
        case AttendanceStatus.ELIGIBLE:
          elig.push(course); break;
        default:
          unk.push(course); break;
      }
    }
    this.ineligible = ineli;
    this.warning = warn;
    this.eligible = elig;
    this.unknown = unk;
  }

  // 从本地课表 JSON 解析每门课的总课数（周次×2=课时）
  private fillTotalTimes(): void {
    try {
      const semCode: string = SemesterUtil.getCurrentSemesterCode();
      const ctx = getContext(this);
      const filePath: string = ctx.filesDir + '/class_table_' + semCode + '.json';
      if (!fileIo.accessSync(filePath)) {
        console.warn('AttendancePage', 'fillTotalTimes: class table file not found');
        return;
      }
      const file: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const stat: fileIo.Stat = fileIo.statSync(filePath);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const raw: string = decoder.decodeToString(new Uint8Array(buf));

      // 解析 JSON：与 ClassService.extractRaw 一致
      const parsed = JSON.parse(raw) as Record<string, Object>;
      const datas = parsed['datas'] as Record<string, Object>;
      const xskcb = datas['xskcb'] as Record<string, Object>;
      const rows: Object[] = xskcb['rows'] as Object[] ?? [];

      // 按课程名累计课数（每出现一次 = 1 次课 = 2 课时）
      const countMap: Map<string, number> = new Map();
      for (let i = 0; i < rows.length; i++) {
        const row = rows[i] as Record<string, string>;
        const kcm: string = row['KCM'] ?? '';
        const skzc: string = row['SKZC'] ?? '';
        if (kcm.length === 0 || skzc.length === 0) continue;

        // 统计该课程在多少周有课
        let weeks: number = 0;
        for (let w = 0; w < skzc.length; w++) {
          if (skzc.charAt(w) === '1') weeks++;
        }

        if (weeks > 0) {
          const key: string = kcm.trim();
          const prev: number = countMap.get(key) ?? 0;
          countMap.set(key, prev + weeks * 2);
        }
      }

      // 更新 courses 的 totalTimes
      for (let i = 0; i < this.courses.length; i++) {
        const c: ClassAttendance = this.courses[i];
        const tt: number | undefined = countMap.get(c.courseName);
        if (tt !== undefined && tt > 0) {
          c.totalTimes = tt;
        }
      }
    } catch (e) {
      console.warn('AttendancePage', 'fillTotalTimes error: ' + String(e));
    }
  }

  async openDetail(course: ClassAttendance): Promise<void> {
    if (course.courseId.length === 0 || course.clazzId.length === 0) {
      return;
    }
    this.detailCourseName = course.courseName;
    this.showDetail = true;
    this.detailLoading = true;
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.detailMaskOpacity = 1;
      this.detailSheetOffset = 0;
    });
    try {
      const data: ClassAttendanceDetail[] = await this.service.getAttendanceDetail(
        course.courseId, course.clazzId, 1, 20
      );
      this.detailCourses = data;
    } catch (e) {
      console.error('AttendancePage openDetail error: ' + String(e));
    } finally {
      this.detailLoading = false;
    }
  }

  closeDetail(): void {
    animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.detailMaskOpacity = 0;
      this.detailSheetOffset = 100;
    });
    setTimeout(() => {
      this.showDetail = false;
      this.detailCourses = [];
    }, 200);
  }

  private getStatusColorForDetail(userStatus: number): string {
    switch (userStatus) {
      case 1: case 2: return '#4CAF50';
      case 4: case 7: case 8: case 12: return '#FF9800';
      case 5: return '#F44336';
      case 9: case 10: return '#FF9800';
      default: return '#9E9E9E';
    }
  }

  // ===== UI Builders =====
  @Builder
  GroupHeader(title: string, color: string, count: number) {
    Row() {
      Text(title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      Blank()
      Text(String(count) + ' 门').fontSize(12).fontColor(ThemeColors.textHint)
    }
    .width('100%').padding({ left: 16, right: 16, top: 16, bottom: 4 })
  }

  @Builder
  GroupColorBar(color: string) {
    Row()
      .width('100%').height(3).backgroundColor(color).borderRadius(1.5)
      .margin({ left: 16, right: 16, bottom: 8 })
  }

  @Builder
  CourseCard(course: ClassAttendance) {
    Column() {
      Row()
        .width('100%').height(4).backgroundColor(course.getStatusColor())
        .borderRadius({ topLeft: 12, topRight: 12 })
      Row() {
        Text(course.courseName)
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(course.getStatusLabel())
          .fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(course.getStatusColor())
          .backgroundColor(course.getStatusColor() + '18')
          .borderRadius(8).padding({ left: 8, right: 8, top: 3, bottom: 3 })
      }.width('100%').padding({ left: 16, right: 16, top: 12 })
      if (course.className.length > 0) {
        Text(course.className).fontSize(12).fontColor(ThemeColors.textHint)
          .padding({ left: 16, top: 2 })
      }
      Row() {
        this.StatItem('签到', course.checkInCount, '#4CAF50')
        this.StatItem('旷课', course.absenceCount, '#F44336')
        this.StatItem('应签', course.requiredCheckIn, '#2196F3')
        this.StatItem('到课率', course.attendanceRate, course.getStatusColor())
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .justifyContent(FlexAlign.SpaceEvenly)

      // 详细信息（对齐 Flutter）
      this.InfoRow('可缺勤', '还可缺勤 ' + String(course.getRemainAbsence()) +
        ' 次（总课数 ' + String(Math.floor(course.totalTimes / 2)) + '）')
      this.InfoRow('请假', '事假 ' + course.personalLeave +
        '  病假 ' + course.sickLeave + '  公假 ' + course.officialLeave)
      if (course.taskProgress.length > 0 || course.homeworkProgress.length > 0 || course.examProgress.length > 0) {
        this.InfoRow('学习进度', '任务点 ' + course.taskProgress +
          '  作业 ' + course.homeworkProgress + '  考试 ' + course.examProgress)
      }
    }
    .width('100%')
    .borderRadius(12).backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
    .onClick(() => { this.openDetail(course); })
  }

  @Builder
  StatItem(label: string, value: string, color: string) {
    Column() {
      Text(value).fontSize(18).fontWeight(FontWeight.Bold).fontColor(color)
      Text(label).fontSize(11).fontColor(ThemeColors.textHint).margin({ top: 2 })
    }.alignItems(HorizontalAlign.Center)
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
      Text(value).fontSize(12).fontColor(ThemeColors.textHint).margin({ left: 8 })
    }
    .width('100%').padding({ left: 16, right: 16, top: 2, bottom: 4 })
  }

  @Builder
  detailSheetBuilder() {
    Column() {
      Row() {
          Text('签到记录').fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(ThemeColors.textPrimary)
          Blank()
          Row() {
            Text('✕').fontSize(18).fontColor('#999999')
          }
          .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
          .justifyContent(FlexAlign.Center)
          .onClick(() => { this.closeDetail(); })
        }.width('100%').padding({ bottom: 12 })

        Text(this.detailCourseName).fontSize(14).fontColor(ThemeColors.textSecondary)
          .width('100%').margin({ bottom: 16 })

        if (this.detailLoading) {
          LoadingProgress().width(36).height(36).color(this.accentColor).margin({ top: 40, bottom: 40 })
        } else if (this.detailCourses.length === 0) {
          Text('暂无签到记录').fontSize(14).fontColor(ThemeColors.textHint)
            .margin({ top: 32, bottom: 32 })
        } else {
          List({ space: 8 }) {
            ForEach(this.detailCourses, (item: ClassAttendanceDetail, index: number) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(item.getSignTypeLabel())
                      .fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                    Text(item.getSignStatusLabel())
                      .fontSize(12).fontColor(this.getStatusColorForDetail(item.userStatus)).margin({ top: 2 })
                  }.layoutWeight(1)
                  Column() {
                    Text('创建 ' + item.creatorName).fontSize(11).fontColor(ThemeColors.textHint)
                    Text('发起 ' + (item.starttime.length > 0 ? item.starttime.substring(0, 16) : '-'))
                      .fontSize(11).fontColor(ThemeColors.textHint).margin({ top: 1 })
                    if (item.submittime.length > 0) {
                      Text('签到 ' + item.submittime.substring(0, 16))
                        .fontSize(11).fontColor(ThemeColors.textHint).margin({ top: 1 })
                    }
                  }.alignItems(HorizontalAlign.End)
                }
                .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .borderRadius(10).backgroundColor(ThemeColors.bgCard)
              }
            }, (item: ClassAttendanceDetail, index: number) => String(item.activeid) + '_' + String(index))
          }.layoutWeight(1)
        }
    }
    .width('100%').height('100%')
    .padding({ left: 20, right: 20, top: 20 })
    .backgroundColor(ThemeColors.bgPage)
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column() {
          Row() {
            Text('').layoutWeight(1)
            Button('刷新')
              .fontSize(12).height(30)
              .backgroundColor(this.accentColor + '18').fontColor(this.accentColor)
              .borderRadius(15).padding({ left: 12, right: 12 })
              .onClick(() => { this.loadData(); })
          }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })

          if (this.loading) {
            Column() {
              LoadingProgress().width(40).height(40).color(this.accentColor)
              Text('加载中，请耐心等待...').fontSize(13).fontColor(ThemeColors.textHint).margin({ top: 16 })
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else if (this.errorMsg.length > 0) {
            Column() {
              Text(this.errorMsg).fontSize(15).fontColor('#F44336').margin({ bottom: 16 })
              Button('重试')
                .fontSize(14).height(36)
                .backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(18)
                .padding({ left: 24, right: 24 })
                .onClick(() => { this.loadData(); })
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else if (this.courses.length === 0) {
            Column() {
              Text('暂无课程数据').fontSize(15).fontColor(ThemeColors.textHint)
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          } else {
            List({ space: 12 }) {
              if (this.ineligible.length > 0) {
                ListItem() {
                  this.GroupHeader('🚫 取消资格', '#F44336', this.ineligible.length)
                }
                ListItem() { this.GroupColorBar('#F44336') }
                ForEach(this.ineligible, (item: ClassAttendance, index: number) => {
                  ListItem() { this.CourseCard(item) }
                }, (item: ClassAttendance, index: number) => 'i_' + String(index))
              }
              if (this.warning.length > 0) {
                ListItem() {
                  this.GroupHeader('⚠️ 危险', '#FF9800', this.warning.length)
                }
                ListItem() { this.GroupColorBar('#FF9800') }
                ForEach(this.warning, (item: ClassAttendance, index: number) => {
                  ListItem() { this.CourseCard(item) }
                }, (item: ClassAttendance, index: number) => 'w_' + String(index))
              }
              if (this.eligible.length > 0) {
                ListItem() {
                  this.GroupHeader('✅ 正常', '#4CAF50', this.eligible.length)
                }
                ListItem() { this.GroupColorBar('#4CAF50') }
                ForEach(this.eligible, (item: ClassAttendance, index: number) => {
                  ListItem() { this.CourseCard(item) }
                }, (item: ClassAttendance, index: number) => 'e_' + String(index))
              }
              if (this.unknown.length > 0) {
                ListItem() {
                  this.GroupHeader('❓ 未知', '#9E9E9E', this.unknown.length)
                }
                ListItem() { this.GroupColorBar('#9E9E9E') }
                ForEach(this.unknown, (item: ClassAttendance, index: number) => {
                  ListItem() { this.CourseCard(item) }
                }, (item: ClassAttendance, index: number) => 'u_' + String(index))
              }
              ListItem().height(60)
            }
            .padding({ left: 16, right: 16, top: 4 })
            .layoutWeight(1)
          }
        }
        .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)

        if (this.showDetail) {
          // 背景遮罩
          Column()
            .width('100%').height('100%')
            .backgroundColor('#4D000000')
            .opacity(this.detailMaskOpacity)
            .onClick(() => { this.closeDetail(); })
          // 详情卡片
          Column() {
            this.detailSheetBuilder()
          }
          .width('100%').height('70%')
          .position({ x: 0, y: '30%' })
          .translate({ y: this.detailSheetOffset + '%' })
        }
      }
    }
    .title('考勤查询', { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
    .onBackPressed(() => {
      if (this.showDetail) {
        this.closeDetail();
        return true;
      }
      return false;
    })
  }
}
