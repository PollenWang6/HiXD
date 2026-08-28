// ExamCountdownCard2x2.ets — 考试倒计时桌面卡片 2x2
let localStorageExam = new LocalStorage();

@Entry(localStorageExam)
@Component
struct ExamCountdownCard2x2 {
  @LocalStorageProp('examCountdownDays')     countdownDays: string = '';
  @LocalStorageProp('examCountdownHours')    countdownHours: string = '';
  @LocalStorageProp('examCountdownName')     examName: string = '';
  @LocalStorageProp('examCountdownWeekday')  weekday: string = '';
  @LocalStorageProp('examCountdownTime')     examTime: string = '';
  @LocalStorageProp('examCountdownColor')    countdownColor: string = '#BF4D00';
  @LocalStorageProp('examCountdownIsUrgent') isUrgent: boolean = false;
  @LocalStorageProp('examCountdownIsOngoing') isOngoing: boolean = false;
  @LocalStorageProp('upcoming72hCount')      upcomingCount: number = 0;
  @LocalStorageProp('lastRefresh')           lastRefresh: string = '';
  @State refreshSpin: number = 0;

  build() {
    // SpaceBetween：标题栏贴顶、底部文字贴底、倒计时居中
    Column() {
      // ── 标题栏 ──
      Row() {
        Text('考试倒计时')
          .fontSize(10).fontColor('#666666')
        Blank()
        Row() {
          Image($r('app.media.ic_public_refresh'))
            .width(13).height(13)
            .rotate({ angle: this.refreshSpin })
            .animation({ duration: 500, curve: Curve.EaseInOut })
        }
        .width(26).height(26).borderRadius(13)
        .backgroundColor('rgba(255,152,0,0.12)')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.refreshSpin += 360;
          postCardAction(this, { action: 'message', params: { msgTest: 'exam' } });
        })
      }
      .width('100%').alignItems(VerticalAlign.Center)

      // ── 倒计时核心 ──
      if (this.countdownDays.length === 0) {
        Text('🎉 近期无考试')
          .fontSize(14).fontColor('#666666')
      } else {
        Column() {
          Text(this.countdownDays)
            .fontSize(34).fontWeight(FontWeight.Bold)
            .fontColor(this.countdownColor)
          Text(this.countdownHours)
            .fontSize(34).fontWeight(FontWeight.Bold)
            .fontColor(this.countdownColor)
          Text(this.examName)
            .fontSize(11).fontWeight(FontWeight.Bold)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
          Text(this.weekday + ' ' + this.examTime)
            .fontSize(9).fontColor('#666666')
            .margin({ top: 1 })
        }.width('100%').alignItems(HorizontalAlign.Center)
      }

      // ── 底部 ──
      Column() {
        if (this.countdownDays.length > 0) {
          Text(this.upcomingCount > 0
            ? '未来3天还有 ' + this.upcomingCount + ' 门'
            : '未来3天没有其他考试')
            .fontSize(8)
            .fontColor(this.upcomingCount > 0 ? '#BF4D00' : '#BBBBBB')
        }
        if (this.lastRefresh.length > 0) {
          Text(this.lastRefresh)
            .fontSize(6).fontColor('#666666')
            .margin({ top: 1 })
        }
      }.width('100%').alignItems(HorizontalAlign.Center)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ top: 3, left: 8, right: 8, bottom: 2 })
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
