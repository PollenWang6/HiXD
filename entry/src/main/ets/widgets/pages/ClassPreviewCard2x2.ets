
// ClassPreviewCard2x2.ets — 课程预告桌面卡片 2x2
let localStorage2x2 = new LocalStorage();

const COLORS_2X2: string[] = ['#1565C0','#AB47BC','#FF7043','#66BB6A','#EC407A','#26C6DA','#7E57C2','#29B6F6'];

@Entry(localStorage2x2)
@Component
struct ClassPreviewCard2x2 {
  @LocalStorageProp('todayNames')   todayNames: string[]   = [];
  @LocalStorageProp('todayTimes')    todayTimes: string[]    = [];
  @LocalStorageProp('todayRooms')    todayRooms: string[]    = [];
  @LocalStorageProp('todayStarts')   todayStarts: number[]   = [];
  @LocalStorageProp('todayCount')    todayCount: number      = 0;
  @LocalStorageProp('tomorrowNames') tomorrowNames: string[] = [];
  @LocalStorageProp('tomorrowTimes') tomorrowTimes: string[] = [];
  @LocalStorageProp('tomorrowRooms') tomorrowRooms: string[] = [];
  @LocalStorageProp('tomorrowStarts') tomorrowStarts: number[] = [];
  @LocalStorageProp('todayTeachers') todayTeachers: string[] = [];
  @LocalStorageProp('todayTypes') todayTypes: string[] = [];
  @LocalStorageProp('todaySeats') todaySeats: string[] = [];
  @LocalStorageProp('tomorrowTeachers') tomorrowTeachers: string[] = [];
  @LocalStorageProp('tomorrowTypes') tomorrowTypes: string[] = [];
  @LocalStorageProp('tomorrowSeats') tomorrowSeats: string[] = [];
  @LocalStorageProp('tomorrowCount') tomorrowCount: number    = 0;
  @LocalStorageProp('weekNum')       weekNum: number         = 1;
  @LocalStorageProp('weekLabel')     weekLabel: string       = '';
  @LocalStorageProp('dateLabel')     dateLabel: string       = '';
  @LocalStorageProp('lastRefresh')   lastRefresh: string     = '';
  @LocalStorageProp('isEmpty')       isEmpty: boolean        = true;
  @LocalStorageProp('isWeekend')     isWeekend: boolean      = false;
  @LocalStorageProp('showTomorrow')  showTomorrow: boolean   = false;
  @LocalStorageProp('todayExamNames')  todayExamNames: string[]  = [];
  @LocalStorageProp('todayExamTimes')  todayExamTimes: string[]  = [];
  @LocalStorageProp('todayExamRooms')  todayExamRooms: string[]  = [];
  @LocalStorageProp('todayExamCount')  todayExamCount: number    = 0;
  @LocalStorageProp('tomorrowExamNames') tomorrowExamNames: string[] = [];
  @LocalStorageProp('tomorrowExamTimes') tomorrowExamTimes: string[] = [];
  @LocalStorageProp('tomorrowExamRooms') tomorrowExamRooms: string[] = [];
  @LocalStorageProp('tomorrowExamCount') tomorrowExamCount: number   = 0;

  private curNames(): string[] { return this.showTomorrow ? this.tomorrowNames : this.todayNames; }
  private curTimes(): string[] { return this.showTomorrow ? this.tomorrowTimes : this.todayTimes; }
  private curRooms(): string[] { return this.showTomorrow ? this.tomorrowRooms : this.todayRooms; }
  private curTeachers(): string[] { return this.showTomorrow ? this.tomorrowTeachers : this.todayTeachers; }
  private curTypes(): string[] { return this.showTomorrow ? this.tomorrowTypes : this.todayTypes; }
  private curSeats(): string[] { return this.showTomorrow ? this.tomorrowSeats : this.todaySeats; }
  private curCount(): number { return this.showTomorrow ? this.tomorrowCount : this.todayCount; }
  private isExamIdx(idx: number): boolean { return idx < this.curTypes().length && this.curTypes()[idx] === 'exam'; }
  private isExpIdx(idx: number): boolean { return idx < this.curTypes().length && this.curTypes()[idx] === 'exp'; }
  private typeLabel(idx: number): string {
    if (this.isExamIdx(idx)) { return '考试'; }
    if (this.isExpIdx(idx)) { return '实验'; }
    return '课程';
  }
  private typeColor(idx: number): string {
    if (this.isExamIdx(idx)) { return '#BF4D00'; }
    if (this.isExpIdx(idx)) { return '#66BB6A'; }
    return '#1565C0';
  }
  private timeAt(idx: number): string { return idx < this.curTimes().length ? this.curTimes()[idx] : ''; }
  private roomAt(idx: number): string { return idx < this.curRooms().length ? this.curRooms()[idx] : ''; }
  private teacherAt(idx: number): string { return idx < this.curTeachers().length ? this.curTeachers()[idx] : ''; }
  private seatAt(idx: number): string { return idx < this.curSeats().length ? this.curSeats()[idx] : ''; }
  @State refreshSpin: number = 0;
  private colorAt(idx: number): string { return this.typeColor(idx); }

  @Builder
  Row2x2(color: string, name: string, sub1: string, sub2: string, time: string) {
    Column() {
      Row() {
        Line().stroke(color).width(3).height(16).strokeLineCap(LineCapStyle.Round).strokeWidth(3)
        Row() {
          Text(name).fontSize(11).fontWeight(FontWeight.Bold).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '60%' })
          Text(' ' + sub1 + ' ').fontSize(7).fontColor('#FFFFFF')
            .backgroundColor(color)
            .borderRadius(3).height(12).flexShrink(0)
        }.layoutWeight(1).margin({ left: 5 })
        if (time.length > 0) { Text(time).fontSize(9).fontColor('#1565C0').flexShrink(0) }
      }.width('100%').alignItems(VerticalAlign.Center)
      if (sub2.length > 0) {
        Text(sub2)
          .fontSize(8).fontColor('#666666').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%').padding({ left: 8 })
      }
    }.width('100%').padding({ top: 1, bottom: 1 })
  }

  build() {
    Column() {
      Row() {
        Text('课程预告').fontSize(14).fontWeight(FontWeight.Bold)
        Text(' ' + this.curCount()).fontSize(10).fontColor('#FFFFFF').backgroundColor('#1565C0')
          .height(14).borderRadius(7).textAlign(TextAlign.Center).padding({ left: 3, right: 3 })
        Blank()
        // 切换按钮 — 加大触控区域
        Row() {
          Text(this.showTomorrow ? '←' : '→').fontSize(14).fontWeight(FontWeight.Medium)
        }
        .width(24).height(24).borderRadius(12)
        .backgroundColor('rgba(66,165,245,0.12)')
        .justifyContent(FlexAlign.Center)
        .onClick(() => { postCardAction(this, { action: 'message', params: { msgTest: 'toggle' } }); })
        // 刷新按钮 — 加大触控区域 + 旋转动画
        Row() {
          Image($r('app.media.ic_public_refresh'))
            .width(14).height(14)
            .rotate({ angle: this.refreshSpin })
            .animation({ duration: 500, curve: Curve.EaseInOut })
        }
        .width(24).height(24).borderRadius(12)
        .backgroundColor('rgba(66,165,245,0.12)')
        .justifyContent(FlexAlign.Center).margin({ left: 10 })
        .onClick(() => {
          this.refreshSpin += 360;
          postCardAction(this, { action: 'message', params: { msgTest: 'schedule' } });
        })
      }.width('100%').alignItems(VerticalAlign.Center).margin({ bottom: 2 })

      Row() {
        Text(this.weekLabel + (this.dateLabel.length > 0 ? ' · ' + this.dateLabel : '')).fontSize(10).maxLines(1)
        Blank()
        Text(this.showTomorrow ? '明天' : '今天').fontSize(10).fontColor(this.showTomorrow ? '#C2185B' : '#1565C0')
      }.width('100%').margin({ bottom: 4 })

      if (this.isEmpty && !this.showTomorrow) {
        Column() { Text(this.isWeekend ? '周末休息' : '今天没有课').fontSize(15) }
          .width('100%').height(28).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ListItem() {
            Column() {
              ForEach(this.curNames(), (name: string, idx: number) => {
                this.Row2x2(this.colorAt(idx), name,
                  this.typeLabel(idx),
                  this.isExamIdx(idx) ? (this.roomAt(idx) + (this.seatAt(idx).length > 0 ? ' · 座' + this.seatAt(idx) : ''))
                    : (this.teacherAt(idx) + (this.roomAt(idx).length > 0 ? ' · ' + this.roomAt(idx) : '')).replace(/^·\s*/, '').replace(/\s*·$/, ''),
                  this.timeAt(idx))
                if (idx < this.curCount() - 1) { Divider().width('94%') }
              }, (name: string, idx: number): string => name + '2x' + idx)
            }
          }
        }.width('100%').layoutWeight(1)
      }

      if (this.lastRefresh.length > 0) {
        Text(this.lastRefresh).fontSize(7).width('100%').textAlign(TextAlign.Center).margin({ top: 2 })
      }
    }.width('100%').height('100%')
    .padding({ top: 6, left: 8, right: 8, bottom: 4 })
    .backgroundColor(Color.Transparent).borderRadius(16)
    .onClick(() => { postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { router: 'Schedule' } }); })
  }
}
