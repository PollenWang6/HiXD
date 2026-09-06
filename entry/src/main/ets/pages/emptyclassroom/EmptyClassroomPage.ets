import { AccentColors } from '../../utils/AccentColors';
// EmptyClassroomPage.ets — 空闲教室搜索
import { ThemeColors } from '../../utils/ThemeColors';
import { EmptyClassroomItem, BuildingInfo } from '../../models/common/Models';
import { EmptyClassroomService } from '../../services/campus/EmptyClassroomService';
import { EhallSessionExpiredError } from '../../services/ids/EhallConstants';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { fmtDate } from '../../utils/DateUtil';
import { LoginState } from '../../utils/LoginState';

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
  @State showCacheBanner: boolean = false; // 当前显示的是缓存数据（网络失败回退）
  @State screenWidth: number = 360; // 内容区宽度（vp），onAreaChange 更新，宽屏多列展示教室卡片

  private ehallsvc: EmptyClassroomService = EmptyClassroomService.getInstance();

  private addDays(d: Date, n: number): Date {
    return new Date(d.getTime() + n * 24 * 60 * 60 * 1000);
  }

  // 教室卡片列数：宽屏多列、窄屏单列（对齐成绩页 AlignedGridView：列宽 ~380vp 自适应）
  private getColumns(): number {
    if (this.screenWidth <= 0) return 1;
    return Math.max(1, Math.floor(this.screenWidth / 380));
  }

  // 错误文案：会话失效给「可行动」提示（告诉用户去重新登录），其余走「动作失败：原因」。
  // 此前 EhallConstants 抛的是 'EHALL_SESSION_EXPIRED' 内部码，会原样显示成
  // 「加载楼栋失败: EHALL_SESSION_EXPIRED」，用户看不懂也不知道该怎么办。
  private errText(action: string, e: Object): string {
    if (e instanceof EhallSessionExpiredError) {
      return '登录状态已失效，请返回首页重新登录后再试';
    }
    return action + '：' + (e as Error).message;
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
      }.height(40).width(40).hoverEffect(HoverEffect.Auto).onClick(() => { this.pageInfo.pop(); })
      Text(t).fontSize(22).fontWeight(FontWeight.Bold).fontColor(AccentColors.textContrast).layoutWeight(1)
    }.width('100%').height(52 + this.statusBarHeight).padding({ left: 12, right: 16, top: this.statusBarHeight })
  }

  aboutToAppear(): void {
    this.selectedDate = new Date();
    if (!LoginState.isLoggedIn() && !LoginState.isOffline()) {
      // 未登录且非离线：提示后仍允许加载（离线时可能有缓存）
      // 不阻断，因为空教室是轻量查询，登录失败时 loadBuildings 会报错
    }
    this.loadBuildings();
  }

  onPageShow(): void {
    if (this.buildings.length === 0) {
      this.loadBuildings(true);
    }
  }

  async loadBuildings(forceRefresh: boolean = false): Promise<void> {
    this.loadingBuildings = true; this.errorMsg = '';
    try {
      this.buildings = await this.ehallsvc.getEmptyClassroomBuildings(forceRefresh);
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
      this.errorMsg = this.errText('加载楼栋失败', e);
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
      PreferenceUtil.putString('empty_classroom_last_result', rawBody); // 缓存最后成功结果，失败可回退
      this.showCacheBanner = false;
      this.applyFilter();
    } catch (e) {
      // 失败回退：保留上次成功的数据，避免空白（对齐 Flutter "保留上次缓存" 的稳定性支柱）
      let fallbackShown: boolean = false;
      if (this.rooms.length === 0) {
        const cached = PreferenceUtil.getString('empty_classroom_last_result');
        if (cached.length > 0) {
          this.rooms = EmptyClassroomService.extractEmptyClassrooms(cached);
          fallbackShown = this.rooms.length > 0;
        }
      }
      this.applyFilter();
      // 缓存命中：不设 errorMsg（否则 build 的错误分支会覆盖列表，缓存永远不渲染）
      if (fallbackShown || this.rooms.length > 0) {
        this.errorMsg = '';
        this.showCacheBanner = true; // 显示缓存数据提示
      } else {
        this.errorMsg = this.errText('加载失败', e);
      }
    } finally {
      this.loading = false;
    }
  }

  // 重试：楼栋未就绪时先重新加载楼栋（避免 selectedBuilding 为空时 search() 直接 return 无法自愈）
  private retry(): void {
    this.errorMsg = '';
    if (!this.selectedBuilding && this.buildings.length === 0) {
      this.loadBuildings(true);
      return;
    }
    this.search();
  }

  selectBuilding(code: string): void {
    this.selectedBuilding = code;
    PreferenceUtil.putString('empty_classroom_last_building', code);
    this.search();
  }

  // ===== 节次格 4/4/3 分组（对齐 Flutter empty_classroom_search_window）=====
  // isUsed 恒为 11 项（JC1~JC11，true=空闲），按 1~4 / 5~8 / 9~11 三组排列，
  // 每组间留空隙，格内直接写节次号 → 一眼看出是哪节课、是空闲还是占用。
  // 底色沿用页面图例语义：绿=空闲、红=占用。
  // ⚠️ @Builder 内 ForEach 回调只允许 UI 组件语法，下标/取色判断一律内联进表达式。
  @Builder
  sectionGroup(isUsed: boolean[], base: number, rels: number[]) {
    Row({ space: 3 }) {
      ForEach(rels, (rel: number) => {
        Text(String(base + rel + 1))
          .fontSize(11).width(22).height(22).textAlign(TextAlign.Center)
          .fontColor(base + rel < isUsed.length && isUsed[base + rel] ? '#2E7D32' : '#C62828')
          .backgroundColor(base + rel < isUsed.length && isUsed[base + rel] ? '#E8F5E9' : '#FFEBEE')
          .borderRadius(6)
      }, (rel: number) => 'cell_' + String(base + rel))
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 缓存数据提示条（网络失败回退到上次成功结果时显示）
        if (this.showCacheBanner) {
          Row() {
            Text('📦 当前显示缓存数据').fontSize(12).fontColor(ThemeColors.warning)
            Text('  刷新').fontSize(12).fontColor('#F4511E')
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .border({ width: 1, color: '#F4511E', radius: 4 })
              .margin({ left: 10 })
              .hoverEffect(HoverEffect.Auto).onClick(() => {
                this.showCacheBanner = false;
                this.loadBuildings(true);
              })
          }.width('100%').height(32).justifyContent(FlexAlign.Center)
          .backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
        }
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
                  .hoverEffect(HoverEffect.Auto).onClick(() => { this.selectBuilding(b.code); })
              }, (b: BuildingInfo) => 'bld_' + b.code)
            }.padding({ left: 16, right: 16 })
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).height(48)
        }

        // 日期选择器
        Row({ space: 8 }) {
          Button('前一天').fontSize(14).height(38).borderRadius(19)
            .fontColor('#F4511E').backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.selectedDate = this.addDays(this.selectedDate, -1); this.search(); })
          Text(fmtDate(this.selectedDate)).fontSize(18).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
            .width(130).textAlign(TextAlign.Center)
          Button('后一天').fontSize(14).height(38).borderRadius(19)
            .fontColor('#F4511E').backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.selectedDate = this.addDays(this.selectedDate, 1); this.search(); })
          Button('今天').fontSize(14).height(38).borderRadius(19)
            .fontColor('#F4511E').backgroundColor(ThemeColors.isDark ? '#3E2723' : '#FFF3E0')
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.selectedDate = new Date(); this.search(); })
        }.width('100%').padding({ left: 16, right: 16, top: 8 })

        // 搜索框
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索教室名...', text: this.searchText })
            .fontSize(14).layoutWeight(1).height(36).backgroundColor('#00000000')
            .onChange((v: string) => { this.searchText = v; this.applyFilter(); })
            .onSubmit(() => { this.applyFilter(); })
          if (this.searchText.length > 0) {
            Text('✕').fontSize(14).fontColor(ThemeColors.textSecondary)
              .hoverEffect(HoverEffect.Auto).onClick(() => { this.searchText = ''; this.applyFilter(); })
          }
          Button('搜索')
            .fontSize(14).fontColor('#FFFFFF').height(36).borderRadius(8)
            .backgroundColor(this.accentColor)
            .hoverEffect(HoverEffect.Auto).onClick(() => { this.applyFilter(); })
        }.width('100%').padding({ left: 16, right: 16, top: 6, bottom: 4 })
        .backgroundColor(ThemeColors.bgCard).borderRadius(8).margin({ left: 16, right: 16, top: 6 })

        Divider().color('#F0F0F0').margin({ top: 6 })

        // 图例（格子=节次号，底色=状态；对齐 Flutter 4/4/3 分段一眼识别课次）
        Row({ space: 6 }) {
          Text('图例: ').fontSize(10).fontColor(ThemeColors.textSecondary)
          Row({ space: 2 }) {
            Text('1').fontSize(10).width(16).height(16).textAlign(TextAlign.Center).borderRadius(4)
              .fontColor('#2E7D32').backgroundColor('#E8F5E9')
            Text('空闲').fontSize(10).fontColor('#2E7D32').margin({ left: 2 })
          }
          Row({ space: 2 }) {
            Text('1').fontSize(10).width(16).height(16).textAlign(TextAlign.Center).borderRadius(4)
              .fontColor('#C62828').backgroundColor('#FFEBEE')
            Text('占用').fontSize(10).fontColor('#C62828').margin({ left: 2 })
          }
          Text('数字=节次').fontSize(10).fontColor(ThemeColors.textSecondary)
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
            Button('重试').margin({ top: 12 }).hoverEffect(HoverEffect.Auto).onClick(() => { this.retry(); })
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
            Text('请选择其他楼栋或日期').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.filteredRooms, (room: EmptyClassroomItem) => {
              GridItem() {
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

                    // 第二行：节次状态 4/4/3 分组（1~4 / 5~8 / 9~11 节），格内带节次号，
                    // 一眼看出是哪节课；组间留空隙模拟 Flutter 的三段视觉分隔
                    Row() {
                      this.sectionGroup(room.isUsed, 0, [0, 1, 2, 3])
                      Blank().width(10)
                      this.sectionGroup(room.isUsed, 4, [0, 1, 2, 3])
                      Blank().width(10)
                      this.sectionGroup(room.isUsed, 8, [0, 1, 2])
                    }.width('100%').margin({ top: 8 })
                  }.width('100%')
                }.width('100%').padding(10).borderRadius(12).backgroundColor(ThemeColors.bgCard)
                .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
                // ⚠️ 不能设 height('100%')：Grid 会把它撑满整行可滚动高度，卡片被拉成大方块。
                // GridItem 同行自动等高由网格布局保证，无需子组件显式撑满。
              }
            }, (room: EmptyClassroomItem) => 'rm_' + room.roomName + '_' + room.floor)
          }
          .columnsTemplate('1fr '.repeat(this.getColumns()).trim())
          .columnsGap(8).rowsGap(8)
          .width('100%').layoutWeight(1)
          .edgeEffect(EdgeEffect.Spring)
          // 边缘回弹：滑到列表顶/底部时橡皮筋回弹（对齐主页/成绩页等既有滚动容器风格）
          .edgeEffect(EdgeEffect.Spring)
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
          .onAreaChange((o: Area, n: Area) => {
            const w = n.width as number;
            if (w > 0 && Math.abs(w - this.screenWidth) > 1) {
              this.screenWidth = w;
            }
          })
        }
      }.width('100%').height('100%').backgroundColor(ThemeColors.bgInput)
    }
    .title({ builder: this.buildWhiteTitle('空闲教室'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
  }
}
