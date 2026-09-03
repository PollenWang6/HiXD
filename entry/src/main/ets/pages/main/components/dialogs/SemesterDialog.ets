import { ThemeColors } from '../../../../utils/ThemeColors';
import { PreferenceUtil } from '../../../../utils/PreferenceUtil';
import { SemesterUtil } from '../../../../services/ids/EhallService';

// 学期设置弹窗（学年度 + 秋季/春季 + 周次偏移）
@Component
export struct SemesterDialog {
  @Prop visible: boolean = false;
  @Prop dialogOpacity: number = 1;
  @Prop dialogTranslate: number = 0;
  @Prop accentColor: string = '#2979FF';
  @Prop accentTextColor: string = '#FFFFFF';
  onClose: () => void = () => {};
  onSaved: () => void = () => {};
  @State pickSemYear: number = new Date().getFullYear();
  @State pickSemPart: number = 2;
  @State pickWeekSwift: number = 0;
  @State semesterToast: string = '';

  aboutToAppear(): void {
    const cur = SemesterUtil.getCurrentSemesterCode();
    const parts = cur.split('-');
    this.pickSemYear = parseInt(parts[0]);
    this.pickSemPart = parseInt(parts[2]) || 2;
    this.pickWeekSwift = PreferenceUtil.getNumber('week_swift', 0);
  }

  buildSemesterStartLabel(): string {
    const code = this.pickSemYear + '-' + (this.pickSemYear + 1) + '-' + this.pickSemPart;
    const d = SemesterUtil.getSemesterStartDate(code);
    d.setDate(d.getDate() + this.pickWeekSwift * 7);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const weekNames = ['日', '一', '二', '三', '四', '五', '六'];
    return y + '/' + m + '/' + day + '（周' + weekNames[d.getDay()] + '）';
  }

  build() {
    Column() {
      Column() {
        Row() {
          Text('学期设置').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
          Blank()
          Row() { Text('✕').fontSize(18).fontColor(ThemeColors.textSecondary) }
            .width(28).height(28).borderRadius(14).backgroundColor(ThemeColors.bgInput)
            .justifyContent(FlexAlign.Center)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
        }.width('100%').margin({ bottom: 14 })
        Text(SemesterUtil.formatSemester(SemesterUtil.getCurrentSemesterCode()))
          .fontSize(14).fontColor(ThemeColors.textSecondary).margin({ bottom: 14 }).width('100%')
        Text('学年度').fontSize(12).fontColor(ThemeColors.textHint).margin({ bottom: 6 })
        Row() {
          Button('‹').fontSize(22).width(40).height(40).fontColor(this.accentColor)
            .backgroundColor(Color.Transparent)
            .hoverEffect(HoverEffect.Auto).onClick(() => { if (this.pickSemYear > 2016) this.pickSemYear--; })
          Text(this.pickSemYear + '-' + (this.pickSemYear + 1)).fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textPrimary).fontFamily('monospace').width(120).textAlign(TextAlign.Center)
          Button('›').fontSize(22).width(40).height(40).fontColor(this.accentColor)
            .backgroundColor(Color.Transparent)
            .hoverEffect(HoverEffect.Auto).onClick(() => { if (this.pickSemYear < new Date().getFullYear() + 1) this.pickSemYear++; })
        }.width('100%').justifyContent(FlexAlign.Center).margin({ bottom: 14 })
        Text('学期').fontSize(12).fontColor(ThemeColors.textHint).margin({ bottom: 6 })
        Row() {
          Button('秋季学期').height(40).fontSize(14)
            .backgroundColor(this.pickSemPart === 1 ? this.accentColor : ThemeColors.bgInput)
            .fontColor(this.pickSemPart === 1 ? '#FFFFFF' : ThemeColors.textPrimary)
            .borderRadius(10).layoutWeight(1)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.pickSemPart = 1; })
          Button('春季学期').height(40).fontSize(14)
            .backgroundColor(this.pickSemPart === 2 ? this.accentColor : ThemeColors.bgInput)
            .fontColor(this.pickSemPart === 2 ? '#FFFFFF' : ThemeColors.textPrimary)
            .borderRadius(10).layoutWeight(1).margin({ left: 10 })
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.pickSemPart = 2; })
        }.width('100%').margin({ bottom: 16 })
        Text('开学日期：' + this.buildSemesterStartLabel())
          .fontSize(13).fontColor(ThemeColors.textSecondary).margin({ bottom: 6 }).width('100%')
        Text('💡 此日期所在周为「第 1 周」，不是精确到某一天开学').fontSize(11).fontColor(ThemeColors.textHint)
          .margin({ bottom: 14 }).width('100%')
        Text('周次偏移（±几周）').fontSize(12).fontColor(ThemeColors.textHint).margin({ bottom: 6 })
        Row() {
          Button('−').fontSize(22).width(44).height(36).fontColor(this.accentColor)
            .backgroundColor(Color.Transparent)
            .hoverEffect(HoverEffect.Auto).onClick(() => { if (this.pickWeekSwift > -8) this.pickWeekSwift--; })
          Text(this.pickWeekSwift >= 0 ? '+' + this.pickWeekSwift.toString() : this.pickWeekSwift.toString())
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
            .fontFamily('monospace').width(56).textAlign(TextAlign.Center)
          Button('+').fontSize(22).width(44).height(36).fontColor(this.accentColor)
            .backgroundColor(Color.Transparent)
            .hoverEffect(HoverEffect.Auto).onClick(() => { if (this.pickWeekSwift < 8) this.pickWeekSwift++; })
        }.width('100%').justifyContent(FlexAlign.Center).margin({ bottom: 16 })
        Row() {
          Button('恢复默认').height(40).fontSize(14)
            .backgroundColor(ThemeColors.bgInput).fontColor(ThemeColors.textPrimary).borderRadius(10)
            .layoutWeight(1)
            .hoverEffect(HoverEffect.Auto).onClick(() => {
              PreferenceUtil.putString('current_semester', '');
              PreferenceUtil.putNumber('week_swift', 0);
              this.pickWeekSwift = 0;
              this.semesterToast = '已恢复默认开学日期设置';
              setTimeout(() => { this.semesterToast = ''; }, 1200);
            })
          Button('保存').height(40).fontSize(14)
            .backgroundColor(this.accentColor).fontColor(this.accentTextColor).borderRadius(10)
            .layoutWeight(1).margin({ left: 10 })
            .hoverEffect(HoverEffect.Auto).onClick(() => {
              const code = this.pickSemYear + '-' + (this.pickSemYear + 1) + '-' + this.pickSemPart;
              PreferenceUtil.putString('current_semester', code);
              PreferenceUtil.putNumber('week_swift', this.pickWeekSwift);
              this.onSaved();
            })
        }.width('100%')
        if (this.semesterToast.length > 0) {
          Text(this.semesterToast).fontSize(13).fontColor('#4CAF50').margin({ top: 12 })
        }
      }
      .width('85%').padding(24).backgroundColor(ThemeColors.bgCard).borderRadius(16)
      .shadow({ radius: 20, color: '#30000000' })
      .opacity(this.dialogOpacity)
      .translate({ y: this.dialogTranslate })
      .hoverEffect(HoverEffect.Auto).onClick(() => {})
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    .backgroundColor(ThemeColors.overlay)
    .opacity(this.dialogOpacity)
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.None)
    .hoverEffect(HoverEffect.Auto).onClick(() => { this.onClose(); })
  }
}
