// CourseReminderPage.ets — 上课前通知设置页面
import { ThemeColors } from '../../utils/ThemeColors';
import {
  CourseReminderService,
  CourseReminderConfig,
  CourseReminderInfo
} from '../../services/CourseReminderService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { promptAction } from '@kit.ArkUI';

@Component
export struct CourseReminderPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  @Prop isTablet: boolean = false;

  @State hasPermission: boolean = false;
  @State saving: boolean = false;
  @State showList: boolean = false;

  // 课程
  @State cEnabled: boolean = false;
  @State cMinutes: string = '5';
  // 实验
  @State eEnabled: boolean = false;
  @State eMinutes: string = '5';
  @State eDouble: boolean = false;
  @State eDbHour: number = 20;
  @State eDbMin: number = 0;
  // 考试
  @State xEnabled: boolean = false;
  @State xMinutes: string = '30';
  @State xDouble: boolean = false;
  @State xDbHour: number = 20;
  @State xDbMin: number = 0;

  @State reminderInfos: CourseReminderInfo[] = [];

  private svc: CourseReminderService = CourseReminderService.getInstance();

  aboutToAppear(): void {
    this.reload();
    this.refreshPerm();
  }

  reload(): void {
    const c: CourseReminderConfig = this.svc.getConfig();
    this.cEnabled = c.courseEnabled;
    this.cMinutes = String(c.courseMinutesBefore);
    this.eEnabled = c.experimentEnabled;
    this.eMinutes = String(c.experimentMinutesBefore);
    this.eDouble = c.experimentDoubleReminder;
    this.eDbHour = c.experimentDayBeforeHour;
    this.eDbMin = c.experimentDayBeforeMinute;
    this.xEnabled = c.examEnabled;
    this.xMinutes = String(c.examMinutesBefore);
    this.xDouble = c.examDoubleReminder;
    this.xDbHour = c.examDayBeforeHour;
    this.xDbMin = c.examDayBeforeMinute;
    const s: string = PreferenceUtil.getString(CourseReminderService.PREF_REMINDER_IDS, '[]');
    try { this.reminderInfos = JSON.parse(s) as CourseReminderInfo[]; }
    catch (_e) { this.reminderInfos = []; }
  }

  async refreshPerm(): Promise<void> {
    this.hasPermission = await this.svc.checkNotificationPermission();
  }

  async saveSettings(): Promise<void> {
    const MAX_MINUTES: number = 120;
    if (this.cEnabled) {
      const cm: number = parseInt(this.cMinutes);
      if (isNaN(cm) || cm < 1) { promptAction.showToast({ message: '课程提前时间无效', duration: 2000 }); return; }
      if (cm > MAX_MINUTES) { promptAction.showToast({ message: `课程提前最长${MAX_MINUTES}分钟`, duration: 2000 }); return; }
    }
    if (this.eEnabled) {
      const em: number = parseInt(this.eMinutes);
      if (isNaN(em) || em < 1) { promptAction.showToast({ message: '实验提前时间无效', duration: 2000 }); return; }
      if (em > MAX_MINUTES) { promptAction.showToast({ message: `实验提前最长${MAX_MINUTES}分钟`, duration: 2000 }); return; }
    }
    if (this.xEnabled) {
      const xm: number = parseInt(this.xMinutes);
      if (isNaN(xm) || xm < 1) { promptAction.showToast({ message: '考试提前时间无效', duration: 2000 }); return; }
      if (xm > MAX_MINUTES) { promptAction.showToast({ message: `考试提前最长${MAX_MINUTES}分钟`, duration: 2000 }); return; }
    }
    if (this.cEnabled || this.eEnabled || this.xEnabled) {
      if (!this.hasPermission) {
        this.hasPermission = await this.svc.requestPermissions();
        if (!this.hasPermission) {
          promptAction.showToast({ message: '需要通知权限', duration: 2000 });
          return;
        }
      }
    }
    this.saving = true;
    try {
      await this.svc.setCourseEnabled(this.cEnabled);
      const cm: number = parseInt(this.cMinutes);
      if (!isNaN(cm)) await this.svc.setCourseMinutesBefore(cm);
      await this.svc.setExperimentEnabled(this.eEnabled);
      const em: number = parseInt(this.eMinutes);
      if (!isNaN(em)) await this.svc.setExperimentMinutesBefore(em);
      await this.svc.setExperimentDouble(this.eDouble);
      await this.svc.setExperimentDayBeforeTime(this.eDbHour, this.eDbMin);
      await this.svc.setExamEnabled(this.xEnabled);
      const xm: number = parseInt(this.xMinutes);
      if (!isNaN(xm)) await this.svc.setExamMinutesBefore(xm);
      await this.svc.setExamDouble(this.xDouble);
      await this.svc.setExamDayBeforeTime(this.xDbHour, this.xDbMin);
      if (this.svc.isAnyEnabled()) {
        await this.svc.scheduleAllReminders(true);
        promptAction.showToast({ message: '设置已保存', duration: 1200 });
      } else {
        await this.svc.cancelAllReminders();
        promptAction.showToast({ message: '提醒已全部关闭', duration: 1200 });
      }
    } catch (_e) {
      promptAction.showToast({ message: '保存失败', duration: 2000 });
    }
    this.saving = false;
    this.reload();
    await this.refreshPerm();
  }

  async requestPermission(): Promise<void> {
    this.hasPermission = await this.svc.requestPermissions();
    promptAction.showToast({ message: this.hasPermission ? '通知权限已开启' : '请到系统设置开启', duration: 2000 });
  }

  showTimePicker(target: 'e' | 'x'): void {
    const hour: number = target === 'e' ? this.eDbHour : this.xDbHour;
    const min: number = target === 'e' ? this.eDbMin : this.xDbMin;
    const d: Date = new Date(2020, 0, 1, hour, min, 0);
    TimePickerDialog.show({
      selected: d,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        if (value.hour !== undefined && value.minute !== undefined) {
          if (target === 'e') { this.eDbHour = value.hour; this.eDbMin = value.minute; }
          else { this.xDbHour = value.hour; this.xDbMin = value.minute; }
        }
      },
    });
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // 权限警告
          if (!this.hasPermission) {
            Row() {
              Text('⚠️ 通知权限未开启').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#E65100').layoutWeight(1)
              Button('去开启').fontSize(12).fontColor('#FFF').backgroundColor('#E65100').borderRadius(14)
                .height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.requestPermission(); })
            }.width('100%').padding(12).backgroundColor('#FFF3E0').borderRadius(10)
             .border({ width: 1, color: '#FFE0B2' }).margin({ left: 16, right: 16, top: 8 })
          }

          // ===== 课程通知 =====
          Column() {
            this.SectionRow('📖', '课程通知', '上课前定时提醒', this.cEnabled,
              (v: boolean) => { this.cEnabled = v; })
            if (this.cEnabled) {
              Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 16, right: 16 })
              Column() {
                this.CapsuleBar(this.cMinutes,
                  (v: string) => { this.cMinutes = v; })
                Row() {
                  Text('自定义').fontSize(12).fontColor(ThemeColors.textHint).margin({ right: 8 })
                  TextInput({ text: this.cMinutes, placeholder: '分钟数' })
                    .fontSize(13).type(InputType.Number).maxLength(3)
                    .width(64).height(32).borderRadius(8).backgroundColor(ThemeColors.bgPage)
                    .border({ width: 1, color: '#E0E0E0' })
                    .onChange((v: string) => { this.cMinutes = v; })
                  Text('分钟').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 6 })
                }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 12 })
              }
            }
          }
          .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 }).margin({ left: 16, right: 16, top: 12 })

          // ===== 实验通知 =====
          Column() {
            this.SectionRow('🔬', '实验通知', '实验课前准备提醒', this.eEnabled,
              (v: boolean) => { this.eEnabled = v; })
            if (this.eEnabled) {
              Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 16, right: 16 })
              Column() {
                this.CapsuleBar(this.eMinutes,
                  (v: string) => { this.eMinutes = v; })
                Row() {
                  Text('自定义').fontSize(12).fontColor(ThemeColors.textHint).margin({ right: 8 })
                  TextInput({ text: this.eMinutes, placeholder: '分钟数' })
                    .fontSize(13).type(InputType.Number).maxLength(3)
                    .width(64).height(32).borderRadius(8).backgroundColor(ThemeColors.bgPage)
                    .border({ width: 1, color: '#E0E0E0' })
                    .onChange((v: string) => { this.eMinutes = v; })
                  Text('分钟').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 6 })
                }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 8 })
                Row() {
                  Column() {
                    Text('双重提醒').fontSize(13).fontColor(ThemeColors.textPrimary)
                    Text('实验前一天也通知一次').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                  }.layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.eDouble }).selectedColor(this.accentColor)
                    .onChange((v: boolean) => { this.eDouble = v; })
                }.width('100%').padding({ left: 16, right: 16 }).margin({ top: 4 })
                if (this.eDouble) {
                  Row() {
                    Text('前一天').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ right: 8 })
                    Row() {
                      Text(`${String(this.eDbHour).padStart(2, '0')}:${String(this.eDbMin).padStart(2, '0')}`)
                        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.accentColor)
                    }.padding({ left: 10, right: 10, top: 5, bottom: 5 })
                     .borderRadius(8).backgroundColor(this.accentColor + '12')
                     .border({ width: 1, color: this.accentColor + '40' })
                     .onClick(() => { this.showTimePicker('e'); })
                    Text('提醒').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 6 })
                  }.width('100%').padding({ left: 16, right: 16, bottom: 12 }).margin({ top: 4 })
                }
              }
            }
          }
          .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 }).margin({ left: 16, right: 16, top: 12 })

          // ===== 考试通知 =====
          Column() {
            this.SectionRow('📋', '考试通知', '考试日程和提醒', this.xEnabled,
              (v: boolean) => { this.xEnabled = v; })
            if (this.xEnabled) {
              Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 16, right: 16 })
              Column() {
                this.CapsuleBar(this.xMinutes,
                  (v: string) => { this.xMinutes = v; })
                Row() {
                  Text('自定义').fontSize(12).fontColor(ThemeColors.textHint).margin({ right: 8 })
                  TextInput({ text: this.xMinutes, placeholder: '分钟数' })
                    .fontSize(13).type(InputType.Number).maxLength(3)
                    .width(64).height(32).borderRadius(8).backgroundColor(ThemeColors.bgPage)
                    .border({ width: 1, color: '#E0E0E0' })
                    .onChange((v: string) => { this.xMinutes = v; })
                  Text('分钟').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 6 })
                }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 8 })
                Row() {
                  Column() {
                    Text('双重提醒').fontSize(13).fontColor(ThemeColors.textPrimary)
                    Text('考试前一天也通知一次').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                  }.layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.xDouble }).selectedColor(this.accentColor)
                    .onChange((v: boolean) => { this.xDouble = v; })
                }.width('100%').padding({ left: 16, right: 16 }).margin({ top: 4 })
                if (this.xDouble) {
                  Row() {
                    Text('前一天').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ right: 8 })
                    Row() {
                      Text(`${String(this.xDbHour).padStart(2, '0')}:${String(this.xDbMin).padStart(2, '0')}`)
                        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.accentColor)
                    }.padding({ left: 10, right: 10, top: 5, bottom: 5 })
                     .borderRadius(8).backgroundColor(this.accentColor + '12')
                     .border({ width: 1, color: this.accentColor + '40' })
                     .onClick(() => { this.showTimePicker('x'); })
                    Text('提醒').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 6 })
                  }.width('100%').padding({ left: 16, right: 16, bottom: 12 }).margin({ top: 4 })
                }
              }
            }
          }
          .borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 }).margin({ left: 16, right: 16, top: 12 })

          // ===== 保存按钮 =====
          Button(this.saving ? '保存中...' : '保存设置')
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            .backgroundColor(this.accentColor).borderRadius(12)
            .width('100%').height(48)
            .margin({ left: 16, right: 16, top: 16 })
            .enabled(!this.saving)
            .onClick(() => { this.saveSettings(); })

          // ===== 提醒列表 =====
          if (this.reminderInfos.length > 0) {
            Column() {
              Row() {
                Text(`已安排 ${this.reminderInfos.length} 个提醒`).fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor(ThemeColors.textPrimary)
                Blank()
                Text(this.showList ? '收起 ▲' : '展开 ▼').fontSize(12).fontColor(this.accentColor)
                  .onClick(() => { this.showList = !this.showList; })
              }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: this.showList ? 6 : 14 })
              if (this.showList) {
                Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 16, right: 16 })
                ForEach(this.reminderInfos, (info: CourseReminderInfo) => {
                  Row() {
                    Text(info.courseKey.startsWith('c_') ? '📖' :
                      info.courseKey.startsWith('exp_') ? '🔬' : '📋')
                      .fontSize(12).margin({ right: 8 })
                    Text(info.courseName).fontSize(13).fontWeight(FontWeight.Medium)
                      .fontColor(ThemeColors.textPrimary).layoutWeight(1)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${String(info.notifyHour).padStart(2, '0')}:${String(info.notifyMinute).padStart(2, '0')}`)
                      .fontSize(11).fontColor(ThemeColors.textSecondary)
                  }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
                })
              }
            }.borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
             .shadow({ radius: 2, color: '#00000008', offsetY: 1 }).margin({ left: 16, right: 16, top: 12 })
          }

          // 说明
          Column() {
            Text('💡 说明').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).margin({ bottom: 6 })
            Text('• 修改设置后点击"保存设置"生效\n• 系统后台代理提醒，应用关闭后仍有效\n• 课表变更时自动增量更新通知')
              .fontSize(12).fontColor(ThemeColors.textSecondary).lineHeight(18)
          }.width('100%').padding(14).borderRadius(12).backgroundColor(ThemeColors.bgCard)
           .shadow({ radius: 2, color: '#00000008', offsetY: 1 }).margin({ left: 16, right: 16, top: 12 })

          Blank().height(100)
        }
        .width(this.isTablet ? '60%' : '100%').alignSelf(ItemAlign.Center)
      }
      .width('100%').height('100%').layoutWeight(1)
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    }
    .title(this.customTitle(), { backgroundColor: this.accentColor })
    .backgroundColor(ThemeColors.bgPage)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .hideBackButton(true)
  }

  @Builder customTitle() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([Color.White])
      }.height(40).width(40).onClick(() => { this.pageInfo.pop(); })
      Text('上课提醒').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.height(56).width('100%').padding({ left: 12, right: 12 })
  }

  // ==================== 小组件 ====================

  @Builder
  SectionRow(icon: string, title: string, sub: string, on: boolean, onToggle: (v: boolean) => void) {
    Row() {
      Text(icon).fontSize(20).margin({ right: 10 })
      Column() {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
        Text(sub).fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
      }.layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: on }).selectedColor(this.accentColor).onChange(onToggle)
    }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  @Builder
  CapsuleBar(selected: string, onSelect: (v: string) => void) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(CourseReminderService.MINUTES_OPTIONS, (opt: number) => {
        Text(`${opt}分钟`).fontSize(12)
          .fontColor(String(opt) === selected ? '#FFF' : ThemeColors.textPrimary)
          .fontWeight(String(opt) === selected ? FontWeight.Medium : FontWeight.Normal)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(12)
          .backgroundColor(String(opt) === selected ? this.accentColor : ThemeColors.bgPage)
          .margin({ right: 6, bottom: 6 })
          .onClick(() => { onSelect(String(opt)); })
      })
    }.width('100%').padding({ left: 16, right: 16, top: 10 })
  }
}
