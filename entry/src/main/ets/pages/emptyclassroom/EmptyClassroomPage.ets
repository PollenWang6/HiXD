import { AccentColors } from '../../utils/AccentColors';
// EmptyClassroomPage.ets — 空闲教室搜索
import { ThemeColors } from '../../utils/ThemeColors';
import { EmptyClassroomItem, BuildingInfo } from '../../services/Models';
import { EmptyClassroomService } from '../../services/EmptyClassroomService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';

@Component
export struct EmptyClassroomPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State loadingBuildings: boolean = false;
  @State rooms: EmptyClassroomItem[] = [];
  @State filteredRooms: EmptyClassroomItem[] = [];
  @State searchText: string = '';
  @State buildings: BuildingInfo[] = [];
  @State selectedBuilding: string = '';
  @State selectedDate: Date = new Date();
  @State errorMsg: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  private ehallsvc: EmptyClassroomService = EmptyClassroomService.getInstance();

  private addDays(d: Date, n: number): Date {
    return new Date(d.getTime() + n * 24 * 60 * 60 * 1000);
  }

  private fmtDate(d: Date): string {
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }

  private applyFilter(): void {
    if (this.searchText.length === 0) {
      this.filteredRooms = this.rooms;
      return;
    }
    const s = this.searchText;
    const list: EmptyClassroomItem[] = [];
    for (let i = 0; i < this.rooms.length; i++) {
      const name = this.rooms[i].roomName;
      if (typeof name === 'string' && name.indexOf(s) >= 0) {
        list.push(this.rooms[i]);
      }
    }
    this.filteredRooms = list;
  }

  @Builder buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close')).height(22).fillColor(ThemeColors.textPrimary).draggable(false)
      }.height(40).width(40).onClick(() => { this.pageInfo.pop(); })
      Text(t).fontSize(22).fontWeight(FontWeight.Bold).fontColor(AccentColors.textContrast).layoutWeight(1)
    }.width('100%').height(52 + this.statusBarHeight).padding({ left: 12, right: 16, top: this.statusBarHeight })
  }

  aboutToAppear(): void {
    this.selectedDate = new Date();
    this.loadBuildings();
  }

  async loadBuildings(): Promise<void> {
    this.loadingBuildings = true; this.errorMsg = '';
    try {
      this.buildings = await this.ehallsvc.getEmptyClassroomBuildings();
      if (this.buildings.length > 0) {
        // 恢复上次选择的楼栋
        const lastBld = PreferenceUtil.getString('empty_classroom_last_building');
        if (lastBld.length > 0) {
          const found = this.buildings.find(b => b.code === lastBld);
          if (found) { this.selectedBuilding = found.code; }
        }
        if (!this.selectedBuilding) {
          const south = this.buildings.find(b => b.name.indexOf('A') >= 0 || b.name.indexOf('B') >= 0 || b.name.indexOf('C') >= 0);
          this.selectedBuilding = south?.code || this.buildings[0].code;
        }
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
    this.loading = true; this.errorMsg = '';
    try {
      const rawBody = await this.ehallsvc.searchEmptyClassroomsByDate(this.selectedBuilding, this.selectedDate);
      this.rooms = EmptyClassroomService.extractEmptyClassrooms(rawBody);
      this.applyFilter();
    } catch (e) {
      this.errorMsg = '加载失败: ' + (e as Error).message;
      this.rooms = [];
      this.filteredRooms = [];
    } finally {
      this.loading = false;
    }
  }

  selectBuilding(code: string): void {
    this.selectedBuilding = code;
    PreferenceUtil.putString('empty_classroom_last_building', code);
    this.search();
  }

  build() {
    NavDestination() {
      Column() {
        // 楼栋选择
        if (this.loadingBuildings) {
          Row() {
            Text('加载楼栋...').fontSize(13).fontColor(ThemeColors.textSecondary);
            LoadingProgress().width(16).height(16).color(this.accentColor).margin({ left: 8 });
          }.width('100%').padding({ left: 16, right: 16, top: 8 })
        } else if (this.buildings.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.buildings, (b: BuildingInfo) => {
                Button(b.name).fontSize(15).height(40).borderRadius(20)
                  .fontColor(b.code === this.selectedBuilding ? '#FFFFFF' : ThemeColors.textPrimary)
                  .backgroundColor(b.code === this.selectedBuilding ? '#F4511E' : ThemeColors.bgInput)
                  .onClick(() => { this.selectBuilding(b.code); })
              }, (b: BuildingInfo) => 'bld_' + b.code)
            }.padding({ left: 16, right: 16 })
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).height(48)
        }

        // 日期选择器
        Row({ space: 8 }) {
          Button('前一天').fontSize(14).height(38).borderRadius(19)
            .fontColor('#F4511E').backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
            .onClick(() => { this.selectedDate = this.addDays(this.selectedDate, -1); this.search(); })
          Text(this.fmtDate(this.selectedDate)).fontSize(18).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
            .width(130).textAlign(TextAlign.Center)
          Button('后一天').fontSize(14).height(38).borderRadius(19)
            .fontColor('#F4511E').backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
            .onClick(() => { this.selectedDate = this.addDays(this.selectedDate, 1); this.search(); })
          Button('今天').fontSize(14).height(38).borderRadius(19)
            .fontColor('#F4511E').backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
            .onClick(() => { this.selectedDate = new Date(); this.search(); })
        }.width('100%').padding({ left: 16, right: 16, top: 8 })

        // 搜索框
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索教室名...', text: this.searchText })
            .fontSize(14).layoutWeight(1).height(36).backgroundColor('#00000000')
            .onChange((v: string) => { this.searchText = v; this.applyFilter(); })
            .onSubmit(() => { this.applyFilter(); })
          if (this.searchText.length > 0) {
            Text('✕').fontSize(14).fontColor(ThemeColors.textSecondary)
              .onClick(() => { this.searchText = ''; this.applyFilter(); })
          }
          Button('搜索')
            .fontSize(14).fontColor('#FFFFFF').height(36).borderRadius(8)
            .backgroundColor(this.accentColor)
            .onClick(() => { this.applyFilter(); })
        }.width('100%').padding({ left: 16, right: 16, top: 6, bottom: 4 })
        .backgroundColor(ThemeColors.bgCard).borderRadius(8).margin({ left: 16, right: 16, top: 6 })

        Divider().color('#F0F0F0').margin({ top: 6 })

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
          Blank()
          if (!this.loading && this.filteredRooms.length > 0) {
            Text('共 ' + this.filteredRooms.length + ' 间').fontSize(10).fontColor(ThemeColors.textSecondary)
          }
        }.width('100%').padding({ left: 16, right: 16, top: 6 }).margin({ bottom: 4 })

        // 内容
        if (this.loading) {
          Column() {
            LoadingProgress().width(40).height(40).color(this.accentColor)
            Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.errorMsg) {
          Column() {
            Text('\u26a0\ufe0f').fontSize(40)
            Text(this.errorMsg).fontSize(14).fontColor('#C62828').margin({ top: 8 })
            Button('重试').margin({ top: 12 }).onClick(() => { this.search(); })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.filteredRooms.length === 0 && this.searchText.length > 0) {
          Column() {
            Text('\ud83d\udd0d').fontSize(48)
            Text('未找到匹配的教室').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.filteredRooms.length === 0) {
          Column() {
            Text('\ud83c\udfeb').fontSize(48)
            Text('暂无数据').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            Text('请选择其他楼栋或日期').fontSize(12).fontColor('#BBBBBB').margin({ top: 4 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.filteredRooms, (room: EmptyClassroomItem) => {
              ListItem() {
                Column() {
                  Column() {
                    // 第一行：教室名 + 楼层，允许自动换行，保证名字完整
                    Row() {
                      Text(room.roomName).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      if (room.floor) {
                        Text(room.floor + '层').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ left: 8 })
                      }
                    }.width('100%').alignItems(VerticalAlign.Top)

                    // 第二行：节次状态标签，独立成行，不再被名字挤出
                    Row({ space: 2 }) {
                      ForEach(room.isUsed, (free: boolean, idx: number) => {
                        Text(free ? '空' : '占').fontSize(11)
                          .fontColor(free ? '#2E7D32' : '#C62828')
                          .backgroundColor(free ? '#E8F5E9' : '#FFEBEE')
                          .borderRadius(4).padding({ left: 5, right: 5, top: 2, bottom: 2 })
                      }, (free: boolean, idx: number) => 'sec_' + String(idx))
                    }.width('100%').margin({ top: 8 })
                  }.width('100%')
                }.width('100%').padding(10).borderRadius(12).backgroundColor(ThemeColors.bgCard)
                .shadow({ radius: 2, color: '#00000008', offsetY: 1 }).margin({ bottom: 8 })
              }
            }, (room: EmptyClassroomItem) => 'rm_' + room.roomName + '_' + room.floor)
          }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, top: 8, bottom: 16 })
        }
      }.width('100%').height('100%').backgroundColor(ThemeColors.bgInput)
    }
    .title({ builder: this.buildWhiteTitle('空闲教室'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
  }
}
