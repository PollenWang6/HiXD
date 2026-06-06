// SchoolNetPage.ets — 校园网页面
import { ThemeColors } from '../../utils/ThemeColors';
import { SchoolnetService } from '../../services/SchoolnetService';

@Component
export struct SchoolNetPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @State loading: boolean = false;
  @State errorMsg: string = '';
  @State isOnline: boolean = false;
  // 流量概览
  @State username: string = '';
  @State usedFlow: string = '';
  @State remainFlow: string = '';
  @State productName: string = '在校学生20G/月';
  // 在线设备信息
  @State deviceIp: string = '';
  @State sessionFlow: string = '';    // V4入流量
  @State onlineTime: string = '';     // 上线时间
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  private schoolnet = SchoolnetService.getInstance();

  aboutToAppear(): void { this.loadData(); }

  async loadData(): Promise<void> {
    this.loading = true; this.errorMsg = '';
    try {
      const info = await this.schoolnet.getCurrentOnlineInfo();
      this.isOnline = true;
      this.username = String(info['user_name'] || '');
      this.usedFlow = this.formatFlow(String(info['sum_flow'] || 0));
      this.remainFlow = this.formatFlow(String(info['remain_flow'] || 0));
      this.deviceIp = String(info['user_ip'] || '');
      // V4入流量
      this.sessionFlow = this.formatFlow(String(info['v4_bytes_in'] || info['bytes_in'] || 0));
      // 上线时间：从 add_time_ts 时间戳转为 YYYY-MM-DD HH:mm:ss
      const addTimeTs = parseInt(String(info['add_time_ts'] || info['add_time'] || 0)) || 0;
      if (addTimeTs > 0) {
        this.onlineTime = this.formatTimestamp(addTimeTs);
      }
    } catch {
      this.isOnline = false; this.errorMsg = '无法获取校园网信息（请确认已连接校园网）';
    } finally { this.loading = false; }
  }

  private formatFlow(flow: string): string {
    const num = parseFloat(flow) || 0;
    if (num >= 1024 * 1024 * 1024) return (num / (1024 * 1024 * 1024)).toFixed(3) + 'G';
    if (num >= 1024 * 1024) return (num / (1024 * 1024)).toFixed(2) + ' MB';
    if (num >= 1024) return (num / 1024).toFixed(2) + ' KB';
    return num.toFixed(2) + ' B';
  }

  // Unix 时间戳（秒）转为 "YYYY-MM-DD HH:mm:ss" (UTC+8)
  private formatTimestamp(ts: number): string {
    // js 原生 Date 在 ArkTS 中可用
    const d = new Date(ts * 1000);
    // UTC+8 = UTC + 8h = 480min
    const offsetMs = 8 * 60 * 60 * 1000;
    const local = new Date(d.getTime() + offsetMs + d.getTimezoneOffset() * 60 * 1000);
    const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
    return local.getUTCFullYear() + '-' + pad(local.getUTCMonth() + 1) + '-' + pad(local.getUTCDate())
      + ' ' + pad(local.getUTCHours()) + ':' + pad(local.getUTCMinutes()) + ':' + pad(local.getUTCSeconds());
  }

  build() {
    NavDestination() {
      Column() {
      // 导航栏
      Row() {
        Blank()
        Circle().width(10).height(10).fill(this.isOnline ? '#4CAF50' : '#FF5252').margin({ right: 6 })
        Text(this.isOnline ? '在线' : '离线').fontSize(12).fontColor(this.isOnline ? '#4CAF50' : '#FF5252')
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 }).backgroundColor(ThemeColors.bgCard)
      Divider().color('#F0F0F0')

      if (this.loading) {
        Column() {
          LoadingProgress().width(40).height(40).color('#00ACC1')
          Text('加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.isOnline) {
        Column() {
          // === 流量概览 ===
          Text('流量概览').fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            .width('100%').margin({ bottom: 12 })
          Row() {
            Text('账号').fontSize(12).fontColor(ThemeColors.textSecondary).width('25%')
            Text('已用流量').fontSize(12).fontColor(ThemeColors.textSecondary).width('25%')
            Text('剩余流量').fontSize(12).fontColor(ThemeColors.textSecondary).width('25%')
            Text('套餐').fontSize(12).fontColor(ThemeColors.textSecondary).width('25%')
          }.width('100%')
          Row() {
            Text(this.username).fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              .width('25%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.usedFlow).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#00ACC1').width('25%')
            Text(this.remainFlow).fontSize(13).fontWeight(FontWeight.Bold).fontColor(ThemeColors.success).width('25%')
            Text(this.productName).fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.warning)
              .width('25%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%').margin({ top: 4 })

          Divider().color('#F0F0F0').margin({ top: 16, bottom: 16 })

          // === 在线设备（对齐 zfw 网页的"在线信息"区域）===
          Text('在线设备').fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            .width('100%').margin({ bottom: 12 })
          Row() {
            Text('IP地址').fontSize(12).fontColor(ThemeColors.textSecondary).width('33%')
            Text('使用流量').fontSize(12).fontColor(ThemeColors.textSecondary).width('34%')
            Text('上线时间').fontSize(12).fontColor(ThemeColors.textSecondary).width('33%')
          }.width('100%')
          Row() {
            Text(this.deviceIp).fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('33%')
            Text(this.sessionFlow).fontSize(12).fontWeight(FontWeight.Bold).fontColor('#00ACC1').width('34%')
            Text(this.onlineTime).fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).width('33%')
          }.width('100%').margin({ top: 4 })

          Divider().color('#F0F0F0').margin({ top: 16, bottom: 8 })

          // 底部提示
          Text('流量数据来自校园网认证系统，仅供参考').fontSize(11).fontColor('#BBBBBB')
            .width('100%').textAlign(TextAlign.Center)
        }.width('100%').padding(20).borderRadius(16).backgroundColor(ThemeColors.bgCard)
          .margin({ left: 16, right: 16, top: 16 }).shadow({ radius: 4, color: '#00000008', offsetY: 2 })
      } else {
        Column() {
          Text('\u{1f310}').fontSize(48)
          Text('未连接校园网').fontSize(16).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          Text('请确认已连接到校园WiFi或有线网络').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 4 })
          Button('重试').margin({ top: 16 }).onClick(() => { this.loadData(); })
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }.width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
  }
    .title('校园网', { backgroundColor: this.accentColor })
    .backgroundColor(ThemeColors.bgPage)
    .onReady((ctx: NavDestinationContext) => {})
  }
}
