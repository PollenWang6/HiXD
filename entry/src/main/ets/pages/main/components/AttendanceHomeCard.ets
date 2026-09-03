import { ThemeColors } from '../../../utils/ThemeColors';
import { PressScale } from '../../../components/PressScale';

// 考勤首页卡片：左图标+标题，右三色统计（危险/正常/未知）
@Component
export struct AttendanceHomeCard {
  @StorageLink('home_att_hasdata') snapAttHasData: boolean = false;
  @StorageLink('home_att_danger') snapAttDanger: number = 0;
  @StorageLink('home_att_normal') snapAttNormal: number = 0;
  @StorageLink('home_att_unknown') snapAttUnknown: number = 0;
  @Prop homeLoading: boolean = false;
  onTap: () => void = () => {};

  @Builder
  AttStat(value: string, label: string, color: string) {
    Column() {
      Text(value).fontSize(22).fontWeight(FontWeight.Bold).fontColor(color)
      Text(label).fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
    }.alignItems(HorizontalAlign.Center).margin({ left: 10, right: 10 })
  }

  build() {
    PressScale({ onTap: () => { this.onTap(); } }) {
    Row() {
      Row() {
        Text('✅').fontSize(26)
        Column() {
          Text('考勤').fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Text(this.snapAttHasData ? '按课程聚合' : '暂无数据').fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor(ThemeColors.textSecondary).margin({ top: 2 })
        }.alignItems(HorizontalAlign.Start).margin({ left: 8 }).layoutWeight(1)
      }.layoutWeight(1).margin({ right: 12 })

      if (this.snapAttHasData) {
        Row() {
          this.AttStat(String(this.snapAttDanger), '危险', '#C62828')
          this.AttStat(String(this.snapAttNormal), '正常', '#2E7D32')
          this.AttStat(String(this.snapAttUnknown), '未知', '#9E9E9E')
        }.alignItems(VerticalAlign.Center)
      } else if (this.homeLoading) {
        LoadingProgress().width(22).height(22).color('#C2185B')
      } else {
        Text('—').fontSize(22).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
      }
    }
    .width('100%').height(88).padding(12)
    .backgroundColor(ThemeColors.bgCard).borderRadius(12)
    .shadow({ radius: 10, color: '#00000014', offsetY: 3 }).border({ width: 1, color: ThemeColors.border })
    .alignItems(VerticalAlign.Center)
    }
  }
}
