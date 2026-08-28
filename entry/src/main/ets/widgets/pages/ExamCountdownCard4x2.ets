// ExamCountdownCard4x2.ets — 考试倒计时桌面卡片 4x2
let localStorageExam4x2 = new LocalStorage();

@Entry(localStorageExam4x2)
@Component
struct ExamCountdownCard4x2 {
  @LocalStorageProp('examCountdownLabel')    label: string = '';
  @LocalStorageProp('examCountdownName')     examName: string = '';
  @LocalStorageProp('examCountdownWeekday')  weekday: string = '';
  @LocalStorageProp('examCountdownTime')     examTime: string = '';
  @LocalStorageProp('examCountdownLocation') location: string = '';
  @LocalStorageProp('examCountdownColor')    countdownColor: string = '#BF4D00';
  @LocalStorageProp('examCountdownIsUrgent') isUrgent: boolean = false;
  @LocalStorageProp('examCountdownIsOngoing') isOngoing: boolean = false;
  @LocalStorageProp('upcoming72hCount')      upcomingCount: number = 0;
  @LocalStorageProp('upcoming72hNames')      upcomingNames: string[] = [];
  @LocalStorageProp('upcoming72hWeekdays')   upcomingWeekdays: string[] = [];
  @LocalStorageProp('upcoming72hTimes')      upcomingTimes: string[] = [];
  @LocalStorageProp('upcoming72hLocations')  upcomingLocations: string[] = [];
  @LocalStorageProp('lastRefresh')           lastRefresh: string = '';
  @State refreshSpin: number = 0;

  @Builder
  UpcomingItem(idx: number) {
    Row() {
      Text(this.upcomingNames[idx])
        .fontSize(9).fontWeight(FontWeight.Medium)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(this.upcomingWeekdays[idx] + ' ' + this.upcomingTimes[idx])
        .fontSize(8).fontColor('#666666')
        .flexShrink(0)
    }.width('100%')
  }

  build() {
    // 核心策略：SpaceBetween — 标题栏置顶、底部区贴底、中间倒计时自然填充
    Column() {
      // ── 标题栏 ──
      Row() {
        Text('考试倒计时')
          .fontSize(12).fontColor('#666666')
        Blank()
        Row() {
          Image($r('app.media.ic_public_refresh'))
            .width(15).height(15)
            .rotate({ angle: this.refreshSpin })
            .animation({ duration: 500, curve: Curve.EaseInOut })
        }
        .width(30).height(30).borderRadius(15)
        .backgroundColor('rgba(255,152,0,0.12)')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.refreshSpin += 360;
          postCardAction(this, { action: 'message', params: { msgTest: 'exam' } });
        })
      }
      .width('100%').alignItems(VerticalAlign.Center)

      // ── 核心倒计时区 ──
      if (this.label.length === 0) {
        Text('🎉 近期无考试')
          .fontSize(18).fontColor('#666666')
      } else {
        Text(this.label)
          .fontSize(this.isOngoing ? 36 : 52)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.countdownColor)

        Row() {
          Text(this.examName)
            .fontSize(13).fontWeight(FontWeight.Bold)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(' ' + this.weekday + ' ' + this.examTime)
            .fontSize(11).fontColor('#666666')
            .flexShrink(0)
          if (this.location.length > 0) {
            Text(' 📍' + this.location)
              .fontSize(9).fontColor('#666666')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(0)
          }
        }
        .width('100%').margin({ top: 6 })
      }

      // ── 底部区 ──
      Column() {
        if (this.label.length > 0) {
          if (this.upcomingCount > 0) {
            Column() {
              Text('未来3天还有 ' + this.upcomingCount + ' 门考试')
                .fontSize(9).fontColor('#BF4D00')
                .width('100%').margin({ bottom: 2 })
              if (this.upcomingCount >= 1) { this.UpcomingItem(0) }
              if (this.upcomingCount >= 2) { this.UpcomingItem(1) }
              if (this.upcomingCount > 2) {
                Text('等...').fontSize(8).fontColor('#666666').width('100%')
              }
            }
            .width('100%')
            .padding({ top: 2, left: 6, right: 6, bottom: 2 })
            .backgroundColor('rgba(0,0,0,0.03)')
            .borderRadius(4)
          } else {
            Text('未来3天没有其他考试')
              .fontSize(9).fontColor('#666666')
          }
        }

        if (this.lastRefresh.length > 0) {
          Text(this.lastRefresh)
            .fontSize(6).fontColor('#666666')
            .margin({ top: 2 })
        }
      }
      .width('100%').alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ top: 4, left: 10, right: 10, bottom: 3 })
    .backgroundColor(Color.Transparent).borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { router: 'Exam' }
      });
    })
  }
}
