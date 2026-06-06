// EmptyClassroomPage.ets
// 空闲教室页面：直接按日期查询，自动定位到今天
import { ThemeColors } from '../../utils/ThemeColors';
import { EmptyClassroomItem, BuildingInfo } from '../../services/Models';
import { EmptyClassroomService } from '../../services/EmptyClassroomService';

@Component
export struct EmptyClassroomPage {
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State loadingBuildings: boolean = false;
  @State rooms: EmptyClassroomItem[] = [];
  @State buildings: BuildingInfo[] = [];
  @State selectedBuilding: string = '';
  @State selectedDate: Date = new Date();  // 当前查询日期
  @State errorMsg: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  private ehallsvc: EmptyClassroomService = EmptyClassroomService.getInstance();

  // 日期加减天数
  private addDays(d: Date, n: number): Date {
    return new Date(d.getTime() + n * 24 * 60 * 60 * 1000);
  }

  // 格式化日期 YYYY-MM-DD
  private fmtDate(d: Date): string {
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }

  aboutToAppear(): void {
    // 自动定位到今天
    this.selectedDate = new Date();
    this.loadBuildings();
  }

  async loadBuildings(): Promise<void> {
    this.loadingBuildings = true;
    this.errorMsg = '';
    try {
      this.buildings = await this.ehallsvc.getEmptyClassroomBuildings();
      console.info('EmptyClassroomPage', 'Loaded buildings: ' + this.buildings.length);
      if (this.buildings.length > 0) {
        // 默认选南校区的楼（如果能找到的话）
        const south = this.buildings.find(b => b.name.includes('A') || b.name.includes('B') || b.name.includes('C'));
        this.selectedBuilding = south?.code || this.buildings[0].code;
        this.search();
      } else {
        this.errorMsg = '未获取到楼栋列表';
      }
    } catch (e) {
      this.errorMsg = '加载楼栋失败: ' + (e as Error).message;
    } finally {
      this.loadingBuildings = false;
    }
  }

  async search(): Promise<void> {
    if (!this.selectedBuilding) return;
    this.loading = true;
    this.errorMsg = '';
    try {
      const rawBody: string = await this.ehallsvc.searchEmptyClassroomsByDate(this.selectedBuilding, this.selectedDate);
      console.info('EmptyClassroomPage', 'search response length: ' + rawBody.length);
      this.rooms = EmptyClassroomService.extractEmptyClassrooms(rawBody);
      console.info('EmptyClassroomPage', 'Parsed rooms: ' + this.rooms.length);
    } catch (e) {
      this.errorMsg = '加载失败: ' + (e as Error).message;
      console.error('EmptyClassroomPage', 'search error: ' + JSON.stringify(e));
      this.rooms = [];
    } finally {
      this.loading = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
      // 顶部导航
      // 楼栋选择
      if (this.loadingBuildings) {
        Row() { Text('加载楼栋...').fontSize(13).fontColor(ThemeColors.textSecondary); LoadingProgress().width(16).height(16).margin({ left: 8 }); }
          .width('100%').padding({ left: 16, right: 16, top: 8 })
      } else if (this.buildings.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.buildings, (b: BuildingInfo) => {
              Button(b.name).fontSize(13).height(32).borderRadius(16)
                .fontColor(b.code === this.selectedBuilding ? '#FFFFFF' : ThemeColors.textPrimary)
                .backgroundColor(b.code === this.selectedBuilding ? '#F4511E' : ThemeColors.bgInput)
                .onClick(() => { this.selectedBuilding = b.code; this.search(); })
            }, (b: BuildingInfo) => 'bld_' + b.code)
          }.padding({ left: 16, right: 16 })
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).height(48)
      }

      // 日期选择器
      Row({ space: 8 }) {
        Button('前一天').fontSize(12).height(30).borderRadius(15)
          .fontColor('#F4511E').backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
          .onClick(() => { this.selectedDate = this.addDays(this.selectedDate, -1); this.search(); })

        Text(this.fmtDate(this.selectedDate)).fontSize(17).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          .width(130).textAlign(TextAlign.Center)

        Button('后一天').fontSize(12).height(30).borderRadius(15)
          .fontColor('#F4511E').backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
          .onClick(() => { this.selectedDate = this.addDays(this.selectedDate, 1); this.search(); })

        Button('今天').fontSize(12).height(30).borderRadius(15)
          .fontColor('#F4511E').backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
          .onClick(() => { this.selectedDate = new Date(); this.search(); })
      }.width('100%').padding({ left: 16, right: 16, top: 8 })

      Divider().color('#F0F0F0').margin({ top: 8 })

      // 图例
      Row({ space: 4 }) {
        Text('图例: ').fontSize(10).fontColor(ThemeColors.textSecondary)
        Row({ space: 2 }) {
          Rect().width(12).height(12).fill('#E8F5E9').radius(2)
          Text('空闲').fontSize(10).fontColor('#2E7D32').margin({ left: 2 })
        }
        Row({ space: 2 }) {
          Rect().width(12).height(12).fill('#FFEBEE').radius(2)
          Text('占用').fontSize(10).fontColor('#C62828').margin({ left: 2 })
        }
      }.width('100%').padding({ left: 16, right: 16, top: 6 }).margin({ bottom: 4 })

      // 内容区
      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color('#F4511E')
          Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.errorMsg) {
        Column() {
          Text('⚠️').fontSize(40)
          Text(this.errorMsg).fontSize(14).fontColor('#C62828').margin({ top: 8 })
          Button('重试').margin({ top: 12 }).onClick(() => { this.search(); })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.rooms.length === 0) {
        Column() {
          Text('🏫').fontSize(48)
          Text('暂无数据').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          Text('请选择其他楼栋或日期').fontSize(12).fontColor('#BBBBBB').margin({ top: 4 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.rooms, (room: EmptyClassroomItem) => {
            ListItem() {
              Column() {
                Row() {
                  Column() {
                    Text(room.roomName).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                    Text(room.floor ? '楼层 ' + room.floor : '').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Row({ space: 2 }) {
                    ForEach(room.isUsed, (free: boolean, idx: number) => {
                      Text(free ? '空' : '占').fontSize(9)
                        .fontColor(free ? '#2E7D32' : '#C62828')
                        .backgroundColor(free ? '#E8F5E9' : '#FFEBEE')
                        .borderRadius(3).padding({ left: 3, right: 3, top: 1, bottom: 1 })
                    }, (free: boolean, idx: number) => 'sec_' + String(idx))
                  }
                }.width('100%')
              }.width('100%').padding(14).borderRadius(12).backgroundColor(ThemeColors.bgCard).margin({ bottom: 8 })
            }
          }, (room: EmptyClassroomItem) => 'rm_' + room.roomName + '_' + room.floor)
        }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, top: 8, bottom: 16 })
      }
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgInput)
  }
    .title('空闲教室', { backgroundColor: ThemeColors.bgCard })
    .onReady((ctx: NavDestinationContext) => {})
  }
}
