
// ClassPreviewCard4x2.ets — 课程预告桌面卡片 4x2
let localStorage4x2 = new LocalStorage();

const COLORS_4X2: string[] = ['#1565C0','#AB47BC','#FF7043','#66BB6A','#EC407A','#26C6DA','#7E57C2','#29B6F6'];

@Entry(localStorage4x2)
@Component
struct ClassPreviewCard4x2 {
  @LocalStorageProp('todayNames')   todayNames: string[]   = [];
  @LocalStorageProp('todayTimes')    todayTimes: string[]    = [];
  @LocalStorageProp('todayRooms')    todayRooms: string[]    = [];
  @LocalStorageProp('todayStarts')   todayStarts: number[]   = [];
  @LocalStorageProp('todayCount')    todayCount: number      = 0;
  @LocalStorageProp('tomorrowNames') tomorrowNames: string[] = [];
  @LocalStorageProp('tomorrowTimes') tomorrowTimes: string[] = [];
  @LocalStorageProp('tomorrowRooms') tomorrowRooms: string[] = [];
  @LocalStorageProp('tomorrowStarts') tomorrowStarts: number[] = [];
  @LocalStorageProp('todayTeachers')   todayTeachers: string[]   = [];
  @LocalStorageProp('todayTypes')      todayTypes: string[]      = [];
  @LocalStorageProp('todaySeats')      todaySeats: string[]      = [];
  @LocalStorageProp('tomorrowTeachers') tomorrowTeachers: string[] = [];
  @LocalStorageProp('tomorrowTypes')     tomorrowTypes: string[]     = [];
  @LocalStorageProp('tomorrowSeats')     tomorrowSeats: string[]     = [];
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
  private colorAt(idx: number): string {
    if (this.isExamIdx(idx)) { return '#BF4D00'; }
    if (this.isExpIdx(idx)) { return '#66BB6A'; }
    return COLORS_4X2[idx % COLORS_4X2.length];
  }
  private subText(idx: number): string {
    if (this.isExamIdx(idx)) { return this.roomAt(idx) + (this.seatAt(idx).length > 0 ? ' · 座位' + this.seatAt(idx) : ''); }
    const t: string = this.teacherAt(idx); const r: string = this.roomAt(idx);
    if (t.length > 0 && r.length > 0) { return t + ' · ' + r; }
    return t.length > 0 ? t : r;
  }

  @Builder
  ItemRow(color: string, name: string, tag: string, tagColor: string, sub: string, time: string) {
    Row() {
      Line().stroke(color).width(3).height(18).strokeLineCap(LineCapStyle.Round).strokeWidth(3)
      Row() {
        Text(name).fontSize(13).fontWeight(FontWeight.Bold).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '55%' })
        Text(' ' + tag + ' ').fontSize(8).fontColor('#FFFFFF').backgroundColor(tagColor)
          .borderRadius(3).height(13).flexShrink(0)
      }.layoutWeight(1).margin({ left: 6 })
      if (sub.length > 0) {
        Text(sub).fontSize(10).fontColor('#666666').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 90 }).flexShrink(0).margin({ right: 6 })
      }
      if (time.length > 0) {
        Text(time).fontSize(11).fontWeight(FontWeight.Medium).fontColor('#1565C0').flexShrink(0)
      }
    }.width('100%').padding({ top: 3, bottom: 3 }).alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Text('课程预告').fontSize(15).fontWeight(FontWeight.Bold)
        Text(' ' + this.curCount()).fontSize(10).fontColor('#FFFFFF').backgroundColor('#1565C0')
          .height(16).borderRadius(8).textAlign(TextAlign.Center).padding({ left: 3, right: 3 })
        Blank()
        // 切换按钮 — 加大触控区域
        Row() {
          Text(this.showTomorrow ? '←' : '→').fontSize(15).fontWeight(FontWeight.Medium)
        }
        .width(28).height(28).borderRadius(14)
        .backgroundColor('rgba(66,165,245,0.12)')
        .justifyContent(FlexAlign.Center)
        .onClick(() => { postCardAction(this, { action: 'message', params: { msgTest: 'toggle' } }); })
        // 刷新按钮 — 加大触控区域 + 旋转动画
        Row() {
          Image($r('app.media.ic_public_refresh'))
            .width(16).height(16)
            .rotate({ angle: this.refreshSpin })
            .animation({ duration: 500, curve: Curve.EaseInOut })
        }
        .width(28).height(28).borderRadius(14)
        .backgroundColor('rgba(66,165,245,0.12)')
        .justifyContent(FlexAlign.Center).margin({ left: 10 })
        .onClick(() => {
          this.refreshSpin += 360;
          postCardAction(this, { action: 'message', params: { msgTest: 'schedule' } });
        })
      }.width('100%').alignItems(VerticalAlign.Center).margin({ bottom: 4 })

      Row() {
        Text(this.weekLabel + (this.dateLabel.length > 0 ? ' · ' + this.dateLabel : '')).fontSize(9).maxLines(1)
        Blank()
        Text(this.showTomorrow ? '明天' : '今天').fontSize(9).fontColor(this.showTomorrow ? '#C2185B' : '#1565C0')
      }.width('100%').margin({ bottom: 6 })

      if (this.isEmpty && !this.showTomorrow) {
        Column() { Text(this.isWeekend ? '周末休息' : '今天没有课').fontSize(14) }
          .width('100%').height(40).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ListItem() {
            Column() {
              ForEach(this.curNames(), (name: string, idx: number) => {
                this.ItemRow(this.colorAt(idx), name, this.typeLabel(idx),
                  this.typeColor(idx), this.subText(idx), this.timeAt(idx))
                if (idx < this.curCount() - 1) { Divider().width('94%') }
              }, (name: string, idx: number): string => name + '4x' + idx)
            }
          }
        }.layoutWeight(1).width('100%')
      }

      if (this.lastRefresh.length > 0) {
        Text(this.lastRefresh).fontSize(8).width('100%').textAlign(TextAlign.Center).margin({ top: 4 })
      }
    }.width('100%').height('100%')
    .padding({ top: 10, left: 12, right: 12, bottom: 6 })
    .backgroundColor(Color.Transparent).borderRadius(16)
    .onClick(() => { postCardAction(this, { action: 'router', abilityName: 'EntryAbility', params: { router: 'Schedule' } }); })
  }
}
