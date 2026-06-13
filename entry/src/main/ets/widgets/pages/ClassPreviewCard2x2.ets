
// ClassPreviewCard2x2.ets — 课程预告桌面卡片 2x2
let localStorage2x2 = new LocalStorage();

const COLORS_2X2: string[] = ['#42A5F5','#AB47BC','#FF7043','#66BB6A','#EC407A','#26C6DA','#7E57C2','#29B6F6'];

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
    Column() {
      Row() {
        Column() {
          Line()
            .stroke('#FF9800')
            .width(3).height(20)
            .strokeLineCap(LineCapStyle.Round)
            .strokeWidth(3)
        }
        .width(8).margin({ right: 6 }).justifyContent(FlexAlign.Center)

        Text(name)
          .fontSize(12).fontWeight(FontWeight.Bold)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (time.length > 0) {
          Text(time).fontSize(10).fontColor('#FF9800').flexShrink(0)
        }
      }
      .width('100%')

      if (room.length > 0) {
        Row() {
          Text(room)
            .fontSize(9)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '80%' })
        }
        .width('100%').padding({ left: 14 })
      }
    }
    .width('100%').padding({ top: 3, bottom: 3 })
  }

  @Builder
  CourseRow(name: string, time: string, room: string, colorIdx: number) {
    Column() {
      Row() {
        Column() {
          Line()
            .stroke(COLORS_2X2[colorIdx % COLORS_2X2.length])
            .width(3).height(20)
            .strokeLineCap(LineCapStyle.Round)
            .strokeWidth(3)
        }
        .width(8).margin({ right: 6 }).justifyContent(FlexAlign.Center)

        Text(name)
          .fontSize(12).fontWeight(FontWeight.Bold)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (time.length > 0) {
          Text(time.split('-')[0])
            .fontSize(10).fontColor('#42A5F5').flexShrink(0)
        }
      }
      .width('100%')

      if (room.length > 0) {
        Row() {
          Text(room)
            .fontSize(9)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '80%' })
        }
        .width('100%').padding({ left: 14 })
      }
    }
    .width('100%').padding({ top: 3, bottom: 3 })
  }

  build() {
    Column() {
      Row() {
        Text('\u8BFE\u7A0B\u9884\u544A')
          .fontSize(14).fontWeight(FontWeight.Bold)

        if (this.showTomorrow && this.tomorrowCount > 0) {
          Text(' ' + this.tomorrowCount)
            .fontSize(10).fontColor('#FFFFFF')
            .backgroundColor('#42A5F5')
            .height(14).borderRadius(7)
            .textAlign(TextAlign.Center).padding({ left: 3, right: 3 })
        } else if (this.todayCount > 0) {
          Text(' ' + this.todayCount)
            .fontSize(10).fontColor('#FFFFFF')
            .backgroundColor('#42A5F5')
            .height(14).borderRadius(7)
            .textAlign(TextAlign.Center).padding({ left: 3, right: 3 })
        }

        Blank()

        Text(this.showTomorrow ? '\u2190' : '\u2192')
          .fontSize(14).fontWeight(FontWeight.Medium)
          .margin({ right: 8 })
          .onClick(() => {
            postCardAction(this, { action: 'message', params: { msgTest: 'toggle' } });
          })

        Image($r('app.media.ic_public_refresh'))
          .width(14).height(14)
          .onClick(() => {
            postCardAction(this, { action: 'message', params: { msgTest: 'schedule' } });
          })
      }
      .width('100%').alignItems(VerticalAlign.Center).margin({ bottom: 2 })

      Row() {
        Text(this.weekLabel + (this.dateLabel.length > 0 ? ' · ' + this.dateLabel : ''))
          .fontSize(10).maxLines(1)
        Blank()
        Text(this.showTomorrow ? '\u660E\u5929' : '\u4ECA\u65E5')
          .fontSize(10)
          .fontColor(this.showTomorrow ? '#E91E63' : '#42A5F5')
      }
      .width('100%').margin({ bottom: 4 })

      if (this.isEmpty && !this.showTomorrow) {
        Column() {
          Text(this.isWeekend ? '\u5468\u672B\u4F11\u606F' : '\u4ECA\u5929\u6CA1\u6709\u8BFE')
            .fontSize(15)
        }
        .width('100%').height(28).justifyContent(FlexAlign.Center)
      } else {
        List() {
          if (this.showTomorrow) {
            ForEach(this.tomorrowNames,
              (name: string, index: number) => {
                ListItem() {
                  Column() {
                    this.CourseRow(name,
                      index < this.tomorrowTimes.length ? this.tomorrowTimes[index] : '',
                      index < this.tomorrowRooms.length ? this.tomorrowRooms[index] : '',
                      index
                    )
                    if (index < this.tomorrowNames.length - 1) { Divider().width('94%') }
                  }
                }
              },
              (name: string, index: number): string => name + 't' + index
            )
            if (this.tomorrowExamCount > 0) {
              ListItem() {
                Column() {
                  Divider().width('94%').color('#FFE0B2').margin({ top: 4, bottom: 4 })
                  ForEach(this.tomorrowExamNames,
                    (name: string, index: number) => {
                      Column() {
                        this.ExamRow(name,
                          index < this.tomorrowExamTimes.length ? this.tomorrowExamTimes[index] : '',
                          index < this.tomorrowExamRooms.length ? this.tomorrowExamRooms[index] : ''
                        )
                        if (index < this.tomorrowExamNames.length - 1) { Divider().width('94%') }
                      }
                    },
                    (name: string, index: number): string => name + 'te' + index
                  )
                }
              }
            }
          } else {
            ForEach(this.todayNames,
              (name: string, index: number) => {
                ListItem() {
                  Column() {
                    this.CourseRow(name,
                      index < this.todayTimes.length ? this.todayTimes[index] : '',
                      index < this.todayRooms.length ? this.todayRooms[index] : '',
                      index
                    )
                    if (index < this.todayNames.length - 1) { Divider().width('94%') }
                  }
                }
              },
              (name: string, index: number): string => name + 'd' + index
            )
            if (this.todayExamCount > 0) {
              ListItem() {
                Column() {
                  Divider().width('94%').color('#FFE0B2').margin({ top: 4, bottom: 4 })
                  ForEach(this.todayExamNames,
                    (name: string, index: number) => {
                      Column() {
                        this.ExamRow(name,
                          index < this.todayExamTimes.length ? this.todayExamTimes[index] : '',
                          index < this.todayExamRooms.length ? this.todayExamRooms[index] : ''
                        )
                        if (index < this.todayExamNames.length - 1) { Divider().width('94%') }
                      }
                    },
                    (name: string, index: number): string => name + 'de' + index
                  )
                }
              }
            }
          }
        }
        .width('100%').layoutWeight(1)
      }

      if (this.lastRefresh.length > 0) {
        Text(this.lastRefresh)
          .fontSize(7)
          .width('100%').textAlign(TextAlign.Center).margin({ top: 2 })
      }
    }
    .width('100%').height('100%')
    .padding({ top: 6, left: 8, right: 8, bottom: 4 })
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
