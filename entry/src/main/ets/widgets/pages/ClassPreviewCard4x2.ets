
// ClassPreviewCard4x2.ets — 课程预告桌面卡片 4x2
let localStorage4x2 = new LocalStorage();

const COLORS_4X2: string[] = ['#42A5F5','#AB47BC','#FF7043','#66BB6A','#EC407A','#26C6DA','#7E57C2','#29B6F6'];

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
  @LocalStorageProp('tomorrowTeachers') tomorrowTeachers: string[] = [];
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

  @Builder
  ExamRow(name: string, time: string, room: string) {
    Row() {
      Column() {
        Line()
          .stroke('#FF9800')
          .width(3).height(20)
          .strokeLineCap(LineCapStyle.Round)
          .strokeWidth(3)
      }
      .width(8).margin({ right: 6 })

      Column() {
        Row() {
          Text(name)
            .fontSize(14).fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        if (time.length > 0) {
          Text('🕐 ' + time)
            .fontSize(10).fontColor('#FF9800')
        }
        if (room.length > 0) {
          Text('📍 ' + room)
            .fontSize(10)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
    }
    .width('100%').padding({ top: 4, bottom: 4 })
  }

  @Builder
  CourseRow(name: string, time: string, room: string, teacher: string, colorIdx: number) {
    Row() {
      Column() {
        Line()
          .stroke(COLORS_4X2[colorIdx % COLORS_4X2.length])
          .width(3).height(20)
          .strokeLineCap(LineCapStyle.Round)
          .strokeWidth(3)
      }
      .width(8).margin({ right: 6 })

      Column() {
        Row() {
          Text(name)
            .fontSize(14).fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '65%' })
          Text(' ' + this.getTypeLabel(name) + ' ')
            .fontSize(9).fontColor('#FFFFFF')
            .backgroundColor(this.getTypeColor(name))
            .borderRadius(4)
            .height(12)
            .flexShrink(0)
          Blank()
        }
        .width('100%')
      }
      .layoutWeight(3)
      .alignItems(HorizontalAlign.Start)

      Column() {
        if (teacher.length > 0) {
          Text(teacher)
            .fontSize(10)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 70 })
        }
        if (room.length > 0) {
          Text(room)
            .fontSize(10)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 70 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 6, right: 6 })

      Column() {
        if (time.length > 0) {
          Text(time.split('-')[0])
            .fontSize(12).fontWeight(FontWeight.Medium).fontColor('#42A5F5')
        }
        if (time.length > 0 && time.includes('-')) {
          Text(time.split('-')[1])
            .fontSize(12).fontWeight(FontWeight.Medium).fontColor('#42A5F5')
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%').padding({ top: 4, bottom: 4 }).alignItems(VerticalAlign.Center)
  }

  getTypeLabel(name: string): string {
    if (name.includes('\u{1F9EA}')) return '\u{5B9E}\u{9A8C}';
    return '\u{8BFE}\u{7A0B}';
  }
  getTypeColor(name: string): string {
    if (name.includes('\u{1F9EA}')) return '#9C27B0';
    return '#42A5F5';
  }

  build() {
    Column() {
      Row() {
        Text('\u8BFE\u7A0B\u9884\u544A')
          .fontSize(15).fontWeight(FontWeight.Bold)

        if (this.showTomorrow && this.tomorrowCount > 0) {
          Text(' ' + this.tomorrowCount)
            .fontSize(10).fontColor('#FFFFFF')
            .backgroundColor('#42A5F5')
            .height(16).borderRadius(8)
            .textAlign(TextAlign.Center)
            .padding({ left: 3, right: 3 })
        } else if (this.todayCount > 0) {
          Text(' ' + this.todayCount)
            .fontSize(10).fontColor('#FFFFFF')
            .backgroundColor('#42A5F5')
            .height(16).borderRadius(8)
            .textAlign(TextAlign.Center)
            .padding({ left: 3, right: 3 })
        }

        Blank()

        Text(this.showTomorrow ? '\u2190' : '\u2192')
          .fontSize(16).fontWeight(FontWeight.Medium)
          .margin({ right: 8 })
          .onClick(() => {
            postCardAction(this, { action: 'message', params: { msgTest: 'toggle' } });
          })

        Image($r('app.media.ic_public_refresh'))
          .width(16).height(16)
          .onClick(() => {
            postCardAction(this, { action: 'message', params: { msgTest: 'schedule' } });
          })
      }
      .width('100%').alignItems(VerticalAlign.Center).margin({ bottom: 4 })

      Row() {
        Text(this.weekLabel + (this.dateLabel.length > 0 ? ' · ' + this.dateLabel : ''))
          .fontSize(9).maxLines(1)
        Blank()
        Text(this.showTomorrow ? '\u660E\u5929' : '\u4ECA\u65E5')
          .fontSize(9)
          .fontColor(this.showTomorrow ? '#E91E63' : '#42A5F5')
      }
      .width('100%').margin({ bottom: 6 })

      if (this.isEmpty && !this.showTomorrow) {
        Column() {
          Text(this.isWeekend ? '\u5468\u672B\u4F11\u606F' : '\u4ECA\u5929\u6CA1\u6709\u8BFE')
            .fontSize(14)
        }
        .width('100%').height(40).justifyContent(FlexAlign.Center)
      } else {
        if (this.showTomorrow) {
          List() {
            ListItem() {
              Column() {
                ForEach(this.tomorrowNames,
                  (name: string, index: number) => {
                    this.CourseRow(name,
                      index < this.tomorrowTimes.length ? this.tomorrowTimes[index] : '',
                      index < this.tomorrowRooms.length ? this.tomorrowRooms[index] : '',
                      index < this.tomorrowTeachers.length ? this.tomorrowTeachers[index] : '',
                      index
                    )
                    if (index < this.tomorrowNames.length - 1) { Divider().width('94%') }
                  },
                  (name: string, index: number): string => name + 't' + index
                )
                if (this.tomorrowExamCount > 0) {
                  Divider().width('94%').color('#FFE0B2').margin({ top: 4, bottom: 4 })
                  ForEach(this.tomorrowExamNames,
                    (name: string, index: number) => {
                      this.ExamRow(name,
                        index < this.tomorrowExamTimes.length ? this.tomorrowExamTimes[index] : '',
                        index < this.tomorrowExamRooms.length ? this.tomorrowExamRooms[index] : ''
                      )
                      if (index < this.tomorrowExamNames.length - 1) { Divider().width('94%') }
                    },
                    (name: string, index: number): string => name + 'te' + index
                  )
                }
              }
            }
          }
          .layoutWeight(1).width('100%')
        } else {
          List() {
            ListItem() {
              Column() {
                ForEach(this.todayNames,
                  (name: string, index: number) => {
                    this.CourseRow(name,
                      index < this.todayTimes.length ? this.todayTimes[index] : '',
                      index < this.todayRooms.length ? this.todayRooms[index] : '',
                      index < this.todayTeachers.length ? this.todayTeachers[index] : '',
                      index
                    )
                    if (index < this.todayNames.length - 1) { Divider().width('94%') }
                  },
                  (name: string, index: number): string => name + 'd' + index
                )
                if (this.todayExamCount > 0) {
                  Divider().width('94%').color('#FFE0B2').margin({ top: 4, bottom: 4 })
                  ForEach(this.todayExamNames,
                    (name: string, index: number) => {
                      this.ExamRow(name,
                        index < this.todayExamTimes.length ? this.todayExamTimes[index] : '',
                        index < this.todayExamRooms.length ? this.todayExamRooms[index] : ''
                      )
                      if (index < this.todayExamNames.length - 1) { Divider().width('94%') }
                    },
                    (name: string, index: number): string => name + 'de' + index
                  )
                }
              }
            }
          }
          .layoutWeight(1).width('100%')
        }
      }

      if (this.lastRefresh.length > 0) {
        Text(this.lastRefresh)
          .fontSize(8)
          .width('100%').textAlign(TextAlign.Center)
          .margin({ top: 4 })
      }
    }
    .width('100%').height('100%')
    .padding({ top: 10, left: 12, right: 12, bottom: 6 })
    .backgroundColor(Color.Transparent)
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { router: 'Schedule' }
      });
    })
  }
}
