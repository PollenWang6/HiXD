import { ToastUtil } from '../../utils/ToastUtil';
﻿import { AccentColors } from '../../utils/AccentColors';
// ElectricityPage.ets — 电费查询（纯 HTTP + AES，无 WebView）
import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { ElectricityService, ElecFullResult, ElecDailyItem } from '../../services/campus/ElectricityService';
import { SegmentTab } from '../../components/SegmentTab';
import { dayShift } from '../../utils/DateUtil';

const TAG: string = 'ElectricityPage';

interface DailyItem {
  date: string;
  prevDate: string;
  use: string;
  startNum: string;
  endNum: string;
}

interface ElecCache {
  remain: string;
  metID: string;
  nodeID: string;
  date: string;
  daily: DailyItem[];
  error: string;
  waterRemain: string;
  waterMetID: string;
  waterDate: string;
  waterDaily: DailyItem[];
}

interface TimePreset { label: string; days: number }

const TIME_PRESETS: TimePreset[] = [
  { label: '近7天', days: 7 },
  { label: '近30天', days: 30 },
  { label: '近90天', days: 90 }
];

@Component
export struct ElectricityPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();
  @State isLoading: boolean = true;
  @State loadError: string = '';
  // 电费
  @State balance: string = '';
  @State metID: string = '';
  @State readDate: string = '';
  @State dailyItems: DailyItem[] = [];
  @State displayDaily: DailyItem[] = [];
  // 水费
  @State waterBalance: string = '';
  @State waterMetID: string = '';
  @State waterReadDate: string = '';
  @State waterDailyItems: DailyItem[] = [];
  @State waterDisplayDaily: DailyItem[] = [];
  @StorageLink('electricity_cache') @Watch('onCacheChanged') elCache: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  // 查询与Tab
  @State activePreset: number = 30;
  @State customStartStr: string = '';
  @State customEndStr: string = '';
  @State customQuerying: boolean = false;
  @State activeTab: number = 0;

  private isSilent: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.customStartStr = dayShift(30);
    this.customEndStr = dayShift(0);
    const silent: boolean = AppStorage.Get('electricity_silent') as boolean;
    if (silent === true) {
      AppStorage.Set('electricity_silent', false);
      this.isSilent = true;
      return;
    }
    if (this.elCache.length > 0) {
      // 有缓存先秒显，后台再用 HTTP 静默刷新覆盖
      this.onCacheChanged();
      this.loadViaHttp(true);
    } else {
      // 无缓存：纯 HTTP 主路径
      this.loadViaHttp(false);
    }
  }

  // 主取数路径：纯 HTTP 拉全量水电数据（与 Flutter 同款，无需 WebView SSO 拿 code）。
  // silentRefresh=true 时不转圈（用于有缓存时的后台刷新）；false 时显示加载并报错。
  private async loadViaHttp(silentRefresh: boolean): Promise<void> {
    if (!silentRefresh) {
      this.isLoading = true;
      this.loadError = '';
    }
    try {
      const result: ElecFullResult | null = await ElectricityService.fetchFullEnergyInfo();
      if (result && result.remain.length > 0) {
        this.applyResult(result);
        return;
      }
      // HTTP 取数失败（多半未登录 CAS）
      if (!silentRefresh) {
        this.loadError = '查询失败，请检查网络后重试';
      }
    } catch (e) {
      // 兜底：服务异常抛错也不留永久转圈
      if (!silentRefresh) {
        this.loadError = '查询失败，请检查网络后重试';
      }
    } finally {
      if (this.isLoading) {
        this.isLoading = false; // 有缓存的静默刷新失败：保持缓存显示，不报错
      }
    }
  }

  // 将服务返回的全量结果映射到页面状态，并写回缓存（electricity_cache / electricity_cache_v2）。
  private applyResult(r: ElecFullResult): void {
    this.balance = r.remain;
    this.metID = r.metID;
    this.readDate = r.date;
    this.dailyItems = [];
    for (let i: number = 0; i < r.daily.length; i++) {
      const d: ElecDailyItem = r.daily[i];
      this.dailyItems.push({ date: d.date, prevDate: d.prevDate, use: d.use || '0.00', startNum: d.startNum || '', endNum: d.endNum || '' });
    }
    this.displayDaily = this.dailyItems.slice(0, 7);
    this.waterBalance = r.waterRemain;
    this.waterMetID = r.waterMetID;
    this.waterReadDate = r.waterDate;
    this.waterDailyItems = [];
    for (let i: number = 0; i < r.waterDaily.length; i++) {
      const d: ElecDailyItem = r.waterDaily[i];
      this.waterDailyItems.push({ date: d.date, prevDate: d.prevDate, use: d.use || '0.00', startNum: d.startNum || '', endNum: d.endNum || '' });
    }
    this.waterDisplayDaily = this.waterDailyItems.slice(0, 7);
    this.activePreset = 30;
    this.isLoading = false;
    this.loadError = '';
    const cache: ElecCache = {
      remain: r.remain, metID: r.metID, nodeID: r.nodeID, date: r.date,
      daily: this.dailyItems, error: '', waterRemain: r.waterRemain, waterMetID: r.waterMetID, waterDate: r.waterDate, waterDaily: this.waterDailyItems
    };
    AppStorage.setOrCreate('electricity_cache', JSON.stringify(cache));
    PreferenceUtil.putString('electricity_cache_v2', JSON.stringify(cache));
    AppStorage.set('home_data_dirty', String(Date.now()));
    if (this.isSilent) {
      this.isSilent = false;
      this.pageInfo.pop();
    }
  }

  onCacheChanged(): void {
    if (this.elCache.length === 0) return;
    try {
      const obj: object = JSON.parse(this.elCache);
      const data: ElecCache = obj as ElecCache;
      if (data.error && data.error.length > 0) {
        this.loadError = data.error;
        this.isLoading = false;
        return;
      }
      this.balance = data.remain || '--';
      this.metID = data.metID || '';
      this.readDate = data.date || '';
      this.dailyItems = [];
      if (data.daily) {
        for (let i: number = 0; i < data.daily.length; i++) {
          const di: DailyItem = data.daily[i];
          this.dailyItems.push({ date: di.date, prevDate: di.prevDate, use: di.use || '0.00', startNum: di.startNum || '', endNum: di.endNum || '' });
        }
      }
      this.displayDaily = this.dailyItems.slice(0, 7);
      this.waterBalance = data.waterRemain || '';
      this.waterMetID = data.waterMetID || '';
      this.waterReadDate = data.waterDate || '';
      this.waterDailyItems = [];
      if (data.waterDaily) {
        for (let i: number = 0; i < data.waterDaily.length; i++) {
          const di: DailyItem = data.waterDaily[i];
          this.waterDailyItems.push({ date: di.date, prevDate: di.prevDate, use: di.use || '0.00', startNum: di.startNum || '', endNum: di.endNum || '' });
        }
      }
      this.waterDisplayDaily = this.waterDailyItems.slice(0, 7);
      this.isLoading = false;
      if (this.isSilent) {
        this.isSilent = false;
        this.pageInfo.pop();
      }
    } catch (e) {
      this.loadError = '数据解析失败';
      this.isLoading = false;
    }
  }

  aboutToDisappear(): void {
  }

  private async queryStep5(startStr: string, endStr: string): Promise<void> {
    if (this.metID.length === 0) {
      ToastUtil.show('请等待数据加载完成', 2000);
      return;
    }
    this.customQuerying = true;
    try {
      const items: ElecDailyItem[] = await ElectricityService.queryMeterRead(this.metID, startStr, endStr);
      const daily: DailyItem[] = [];
      for (let i: number = 0; i < items.length; i++) {
        const d: ElecDailyItem = items[i];
        daily.push({ date: d.date, prevDate: d.prevDate, use: d.use, startNum: d.startNum, endNum: d.endNum });
      }
      this.dailyItems = daily;
      this.displayDaily = daily.slice(0, 7);
    } catch (e) {
      ToastUtil.show('查询失败', 2000);
    }
    this.customQuerying = false;
  }

  private selectPreset(days: number): void {
    if (days === -1) { this.activePreset = -1; return; }
    this.activePreset = days;
    const startStr: string = dayShift(days);
    const endStr: string = dayShift(0);
    this.queryStep5(startStr, endStr);
  }

  private doCustomQuery(): void {
    if (this.customStartStr.length === 0 || this.customEndStr.length === 0) {
      ToastUtil.show('请选择开始和结束日期', 2000);
      return;
    }
    if (this.customStartStr > this.customEndStr) {
      ToastUtil.show('开始日期不能晚于结束日期', 2000);
      return;
    }
    this.queryStep5(this.customStartStr, this.customEndStr);
  }

  private showStartDatePicker(): void {
    DatePickerDialog.show({
      start: new Date('2022-1-1'),
      end: new Date(),
      selected: this.customStartStr.length > 0 ? new Date(this.customStartStr) : new Date(),
      onAccept: (value: DatePickerResult) => {
        const y: number = value.year as number;
        const m: number = (value.month as number) + 1;
        const d: number = value.day as number;
        this.customStartStr = String(y) + '-' + String(m).padStart(2, '0') + '-' + String(d).padStart(2, '0');
      }
    });
  }

  private showEndDatePicker(): void {
    DatePickerDialog.show({
      start: new Date('2022-1-1'),
      end: new Date(),
      selected: this.customEndStr.length > 0 ? new Date(this.customEndStr) : new Date(),
      onAccept: (value: DatePickerResult) => {
        const y: number = value.year as number;
        const m: number = (value.month as number) + 1;
        const d: number = value.day as number;
        this.customEndStr = String(y) + '-' + String(m).padStart(2, '0') + '-' + String(d).padStart(2, '0');
      }
    });
  }

  private doRefresh(): void {
    this.isLoading = true;
    this.loadError = '';
    this.balance = '';
    this.metID = '';
    this.readDate = '';
    this.dailyItems = [];
    this.activePreset = 30;
    AppStorage.setOrCreate('electricity_cache', '');
    // 主路径是纯 HTTP，失败直接显示错误
    this.loadViaHttp(false);
  }

  private fmtDate(d: string): string {
    if (d.length < 10) return d;
    let m: string = d.substring(5, 7);
    let day: string = d.substring(8, 10);
    if (m.charAt(0) === '0') { m = m.substring(1); }
    if (day.charAt(0) === '0') { day = day.substring(1); }
    return m + '月' + day + '日';
  }

  private totalUsage(): string {
    let sum: number = 0;
    for (let i: number = 0; i < this.dailyItems.length; i++) {
      sum += parseFloat(this.dailyItems[i].use) || 0;
    }
    return sum.toFixed(2);
  }

  @Builder
  buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close')).height(22).fillColor(ThemeColors.textPrimary).draggable(false)
      }
      .height(40).width(40).hoverEffect(HoverEffect.Auto).onClick(() => { this.pageInfo.pop(); })
      Text(t).fontSize(22).fontWeight(FontWeight.Bold).fontColor(AccentColors.textContrast).layoutWeight(1)
    }
    .width('100%').height(52 + this.statusBarHeight).padding({ left: 12, right: 16, top: this.statusBarHeight })
  }

  @Builder
  buildBalanceCard() {
    Column() {
      Row() {
        Text('⚡ 电费余额').fontSize(14).fontColor(Color.White).opacity(0.9)
        Blank()
        Image($r('app.media.ic_public_refresh')).width(22).height(22).fillColor(Color.White).opacity(0.9)
          .hoverEffect(HoverEffect.Auto).onClick(() => { this.doRefresh(); })
      }.width('100%')
      Row({ space: 4 }) {
        Text(this.balance).fontSize(52).fontWeight(FontWeight.Bold).fontColor(Color.White)
        Text('kWh').fontSize(16).fontColor(Color.White).opacity(0.7).margin({ bottom: 6 })
      }.margin({ top: 8 })
      Text('电表 ' + this.metID + '  ·  抄读于 ' + this.readDate)
        .fontSize(12).fontColor(Color.White).opacity(0.6).margin({ top: 6 })
    }
    .width('100%').padding({ left: 20, right: 20, top: 20, bottom: 22 }).borderRadius(16)
    .linearGradient({
      angle: 135,
      colors: this.themeIsDark ? [['#4A2800', 0.0], ['#BF4D00', 1.0]] : [['#FF8F00', 0.0], ['#BF4D00', 1.0]]
    })
    .shadow({ radius: 16, color: '#BF4D0020', offsetY: 6 }).margin({ left: 16, right: 16, top: 16 })
  }

  @Builder
  buildPresetChip(label: string, days: number) {
    Text(label).fontSize(12)
      .fontColor(this.activePreset === days ? this.accentColor : ThemeColors.textSecondary)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 }).borderRadius(10)
      .border({ width: 0.5, color: this.activePreset === days ? this.accentColor : ThemeColors.border })
      .backgroundColor(this.activePreset === days ? (this.accentColor + '18') : Color.Transparent)
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.selectPreset(days); })
  }

  @Builder
  elecContent() {
    Column() {
      Row() {
        Text('用电记录').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        Blank()
        if (this.dailyItems.length > 0) {
          Text(String(this.dailyItems.length) + ' 条').fontSize(12).fontColor(ThemeColors.textHint)
        }
      }.width('100%').padding({ left: 18, right: 18, top: 14, bottom: 6 })

      Row({ space: 8 }) {
        ForEach(TIME_PRESETS, (p: TimePreset) => { this.buildPresetChip(p.label, p.days) }, (p: TimePreset): string => p.label)
        this.buildPresetChip('自定义', -1)
      }.width('100%').padding({ left: 18, right: 18, bottom: 8 })

      Row({ space: 8 }) {
        Text('起').fontSize(13).fontColor(ThemeColors.textHint)
        Row() {
          Text(this.activePreset === -1 ? this.customStartStr : dayShift(this.activePreset))
            .fontSize(13).fontColor(ThemeColors.textPrimary)
        }.padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(6).backgroundColor(ThemeColors.bgPage)
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.activePreset = -1; this.showStartDatePicker(); })

        Text('~').fontSize(13).fontColor(ThemeColors.textHint)
        Text('止').fontSize(13).fontColor(ThemeColors.textHint)
        Row() {
          Text(this.activePreset === -1 ? this.customEndStr : dayShift(0))
            .fontSize(13).fontColor(ThemeColors.textPrimary)
        }.padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(6).backgroundColor(ThemeColors.bgPage)
        .hoverEffect(HoverEffect.Auto).onClick(() => { this.activePreset = -1; this.showEndDatePicker(); })

        if (this.activePreset === -1) {
          Button('查询').fontSize(13).height(32).backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(6)
            .padding({ left: 14, right: 14 }).hoverEffect(HoverEffect.Auto).onClick(() => { this.doCustomQuery(); })
        }
      }.width('100%').padding({ left: 18, right: 18, bottom: 10 })

      if (this.customQuerying) {
        Row() {
          LoadingProgress().width(16).height(16).color(this.accentColor)
          Text('查询中...').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 6 })
        }.width('100%').justifyContent(FlexAlign.Center).padding({ bottom: 6 })
      }

      Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 18, right: 18 })

      if (this.dailyItems.length > 0 && !this.customQuerying) {
        Row() {
          Text('合计 ' + this.totalUsage() + ' kWh').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#BF4D00')
          Text(' · ').fontSize(13).fontColor(ThemeColors.textHint)
          Text(String(this.dailyItems.length) + ' 条').fontSize(13).fontColor(ThemeColors.textSecondary)
        }.width('100%').padding({ left: 18, right: 18, top: 8, bottom: 4 })
      }

      if (this.dailyItems.length === 0 && !this.customQuerying) {
        Text('该时间段暂无用电记录').fontSize(14).fontColor(ThemeColors.textSecondary)
          .width('100%').textAlign(TextAlign.Center).padding({ top: 24, bottom: 24 })
      } else {
        List() {
          ForEach(this.dailyItems, (item: DailyItem, index: number) => {
            ListItem() {
              Row() {
                Column({ space: 3 }) {
                  Text(this.fmtDate(item.prevDate.length > 0 ? item.prevDate : '?') + ' → ' + this.fmtDate(item.date))
                    .fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(1)
                  Text('上次 ' + item.startNum + '  ·  本次 ' + item.endNum)
                    .fontSize(11).fontColor(ThemeColors.textHint)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text(item.use + ' kWh').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#BF4D00')
              }.width('100%').padding({ left: 18, right: 18, top: 11, bottom: 11 })
            }
          }, (item: DailyItem): string => item.date)
        }
        .layoutWeight(1).divider({ strokeWidth: 0.5, color: '#F5F5F5', startMargin: 18, endMargin: 18 })
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .borderRadius(12).backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
    .margin({ left: 16, right: 16, top: 10, bottom: 16 })
    .layoutWeight(1)
  }

  @Builder
  waterContent() {
    Column() {
      Row() {
        Text('水表 ' + this.waterMetID).fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        Blank()
        Text('抄读于 ' + this.waterReadDate).fontSize(12).fontColor(ThemeColors.textSecondary)
      }.width('100%').padding({ left: 18, right: 18, top: 14, bottom: 4 })

      Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 18, right: 18 })

      if (this.waterDailyItems.length > 0) {
        Row() {
          Text('读表时间').fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Bold).width('25%')
          Text('用量').fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Bold).width('20%')
          Text('本次读数').fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Bold).width('27%')
          Text('上次读数').fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Bold).width('28%')
        }.width('100%').padding({ left: 18, right: 18, top: 8, bottom: 8 })

        List() {
          ForEach(this.waterDailyItems, (item: DailyItem, index: number) => {
            ListItem() {
              Row() {
                Text(this.fmtDate(item.date)).fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).width('25%')
                Text(item.use + ' 吨').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#1565C0').width('20%')
                Text('本次:' + item.endNum).fontSize(11).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).width('27%')
                Text('上次:' + item.startNum).fontSize(11).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).width('28%')
              }.width('100%').padding({ top: 8, bottom: 8, left: 18, right: 18 })
            }
          }, (item: DailyItem): string => item.date)
        }
        .layoutWeight(1).divider({ strokeWidth: 0.5, color: '#F5F5F5', startMargin: 18, endMargin: 18 })
        .edgeEffect(EdgeEffect.Spring)
      } else {
        Text('暂无用水记录').fontSize(14).fontColor(ThemeColors.textSecondary)
          .width('100%').textAlign(TextAlign.Center).padding({ top: 28, bottom: 28 })
      }
    }
    .borderRadius(12).backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
    .margin({ left: 16, right: 16, top: 10, bottom: 16 })
    .layoutWeight(1)
  }

  build() {
    NavDestination() {
      Column() {
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(48).height(48).color(this.accentColor)
            Text('正在查询水电...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 16 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }

        if (!this.isLoading && this.loadError.length > 0) {
          Column() {
            Text('😞').fontSize(48)
            Text(this.loadError).fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            Button('重试').fontSize(14).height(36).backgroundColor('#BF4D00').fontColor('#FFFFFF').borderRadius(20)
              .margin({ top: 20 }).padding({ left: 24, right: 24 }).hoverEffect(HoverEffect.Auto).onClick(() => { this.doRefresh(); })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        }

        if (!this.isLoading && this.loadError.length === 0 && this.balance.length > 0) {
          Scroll() {
            Column() {
              this.buildBalanceCard()

              SegmentTab({
                tabs: ['⚡ 电费', '💧 水费'],
                currentIndex: $activeTab,
                accentColor: this.accentColor,
                onTabChange: (_idx: number) => {}
              }) {
                this.elecContent()
                this.waterContent()
              }
            }
          }
          .layoutWeight(1)
          .edgeEffect(EdgeEffect.Spring)
        }

        if (!this.isLoading && this.loadError.length === 0 && this.balance.length === 0) {
          Column() {
            Text('🔌').fontSize(48)
            Text('正在连接缴费系统...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%').height('100%').backgroundColor(ThemeColors.bgInput)
    }
    .title({ builder: this.buildWhiteTitle('水电查询'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => { return false; })
    .backgroundColor(ThemeColors.bgPage)
    .onReady((ctx: NavDestinationContext) => {})
  }
}
