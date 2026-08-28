import { ToastUtil } from '../../utils/ToastUtil';
﻿import { AccentColors } from '../../utils/AccentColors';
// SchoolCardPage.ets — 校园卡原生页面（纯 HTTP，对标 Flutter）
// 余额、付款码、消费记录
import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { PaidRecord, SchoolCardService } from '../../services/SchoolCardService';
import { CasLoginService } from '../../services/CasLoginService';
import { fmtDate } from '../../utils/DateUtil';

@Component
export struct SchoolCardPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();
  @State balance: string = '...';
  @State records: PaidRecord[] = [];
  @State loading: boolean = true;
  @State error: string = '';
  @State showBarcode: boolean = false;
  @State qrBase64: string = '';
  @State qrLoading: boolean = false;
  // 日期筛选
  @State beginDate: string = '';
  @State endDate: string = '';
  @State activePreset: number = 30; // -1=自定义
  // Service
  private cardSvc: SchoolCardService = SchoolCardService.getInstance();

    @Builder buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40).width(40)
      .onClick(() => { this.pageInfo.pop(); })
      Text(t)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(AccentColors.textContrast)
        .layoutWeight(1)
    }
    .width('100%')
    .height(52 + this.statusBarHeight)
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
  }

  aboutToAppear(): void {
    const now = new Date();
    this.endDate = fmtDate(now);
    this.beginDate = fmtDate(new Date(now.getTime() - 30 * 86400000));
    this.initData();
  }

  async initData(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      // Step 0: 确保 CAS TGC 有效（触发自动恢复/密码登录）
      const loggedIn = await CasLoginService.getInstance().checkAndAutoLogin();
      if (!loggedIn) {
        this.error = '请先登录校园账号';
        this.loading = false;
        return;
      }

      // Step 1: OAuth 获取 openid（5min 内缓存）
      const oid = await this.cardSvc.ensureOpenId();

      // Step 2: 并行获取余额 + 消费记录
      const results = await Promise.all([
        this.cardSvc.getBalance(),
        this.cardSvc.getPaidRecords(this.beginDate, this.endDate),
      ]);
      this.balance = results[0] as string;
      AppStorage.setOrCreate('card_balance', this.balance);
      PreferenceUtil.putString('card_balance_cached', this.balance);
      AppStorage.set('home_data_dirty', String(Date.now()));
      this.records = results[1] as PaidRecord[];
      this.loading = false;
    } catch (e) {
      // 尝试仅余额
      try {
        const bal = await this.cardSvc.getBalance();
        this.balance = bal;
        AppStorage.setOrCreate('card_balance', bal);
        PreferenceUtil.putString('card_balance_cached', bal);
        AppStorage.set('home_data_dirty', String(Date.now()));
        this.loading = false;
      } catch (_e2) {
        this.error = '校园卡加载失败';
        this.loading = false;
      }
    }
  }

  parseDate(s: string): Date {
    const p = s.split('-');
    return new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
  }

  // 二维码：按需获取
  async fetchQRCode(): Promise<void> {
    if (this.qrBase64) {
      this.showBarcode = true;
      return;
    }
    this.qrLoading = true;
    try {
      this.qrBase64 = await this.cardSvc.getQRCodeBase64();
      this.showBarcode = true;
    } catch (e) {
    } finally {
      this.qrLoading = false;
    }
  }

  async onQueryRecords(): Promise<void> {
    try {
      this.loading = true;
      this.error = '';
      this.records = await this.cardSvc.getPaidRecords(this.beginDate, this.endDate);
      ToastUtil.show('查询成功，共 ' + String(this.records.length) + ' 条', 2000);
    } catch (e) {
      ToastUtil.show('查询失败', 2000);
    } finally {
      this.loading = false;
    }
  }

  setDateRange(days: number): void {
    this.activePreset = days;
    if (days === -1) return; // 自定义模式，等用户选日期后手动查询
    const now = new Date();
    this.endDate = fmtDate(now);
    this.beginDate = fmtDate(new Date(now.getTime() - days * 86400000));
    this.onQueryRecords();
  }

  // 日期选择器
  pickDate(kind: number): void { // 0=开始, 1=结束
    this.activePreset = -1;
    const curDate = this.parseDate(kind === 0 ? this.beginDate : this.endDate);
    DatePickerDialog.show({
      start: new Date('2022-01-01'),
      end: new Date(),
      selected: curDate,
      lunar: false,
      onAccept: (value: DatePickerResult) => {
        const picked = fmtDate(new Date(value.year, value.month, value.day));
        if (kind === 0) {
          this.beginDate = picked;
        } else {
          this.endDate = picked;
        }
        this.onQueryRecords();
      }
    });
  }

  totalAmount(): string {
    let sum = 0;
    for (const r of this.records) sum += parseFloat(r.money) || 0;
    return Math.abs(sum).toFixed(2);
  }

  build() {
    NavDestination() {
      Column() {
        // ========== 余额卡片 ==========
        Column() {
          Row() {
            Text('校园卡余额').fontSize(14).fontColor('#FFFFFFB3')
            Blank()
            Button() {
              Text(this.showBarcode ? '隐藏付款码' : '显示付款码')
                .fontSize(13).fontColor('#FFFFFF')
            }
            .height(32).borderRadius(16)
            .border({ width: 1, color: '#FFFFFF80' })
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              if (this.showBarcode) {
                this.showBarcode = false;
              } else {
                this.showBarcode = true;
                this.fetchQRCode();
              }
            })
          }.width('100%').padding({ left: 20, right: 16, top: 16, bottom: 0 })

          Row() {
            Text('¥ ' + this.balance)
              .fontSize(42).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 18 })
        }
        .width('100%')
        .borderRadius(16)
        .linearGradient({
          angle: 135,
          colors: [['#4A90D9', 0], ['#2979FF', 0.5], ['#1565C0', 1]]
        })
        .margin({ left: 16, right: 16, top: 8 })

        // ========== 付款码 ==========
        if (this.showBarcode) {
          Column() {
            Row() {
              Text('付款码').fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            }.width('100%').padding({ left: 18, right: 18, top: 14 })

            if (this.qrLoading) {
              LoadingProgress().width(24).height(24).color(ThemeColors.accent).margin({ top: 24, bottom: 24 })
            } else if (this.qrBase64) {
              Divider().color('#EEEEEE').strokeWidth(0.5).margin({ left: 18, right: 18 })
              Row() {
                Image('data:image/png;base64,' + this.qrBase64)
                  .width(220).height(220).objectFit(ImageFit.Contain)
              }.width('100%').justifyContent(FlexAlign.Center)
              .padding({ top: 8, bottom: 14 })
            } else {
              Text('二维码加载失败').fontSize(13).fontColor(ThemeColors.textHint)
                .width('100%').textAlign(TextAlign.Center).padding({ top: 20, bottom: 20 })
            }
          }
          .borderRadius(12).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          .margin({ left: 16, right: 16, top: 10 })
        }

        // ========== 消费记录 ==========
        Column() {
          Row() {
            Text('消费记录').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            Blank()
            Text(this.records.length + ' 条').fontSize(12).fontColor(ThemeColors.textHint)
          }.width('100%').padding({ left: 18, right: 18, top: 14, bottom: 6 })

          // 快捷日期
          Row({ space: 8 }) {
            this.dateTag('近7天', 7)
            this.dateTag('近30天', 30)
            this.dateTag('近90天', 90)
            this.dateTag('自定义', -1)
          }.width('100%').padding({ left: 18, right: 18, bottom: 8 })

          // 日期选择行
          Row({ space: 8 }) {
            Text('起').fontSize(13).fontColor(ThemeColors.textHint)
            Row() {
              Text(this.beginDate).fontSize(13).fontColor(ThemeColors.textPrimary)
            }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6).backgroundColor(ThemeColors.bgPage)
            .onClick(() => { this.pickDate(0); })

            Text('~').fontSize(13).fontColor(ThemeColors.textHint)

            Text('止').fontSize(13).fontColor(ThemeColors.textHint)
            Row() {
              Text(this.endDate).fontSize(13).fontColor(ThemeColors.textPrimary)
            }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(6).backgroundColor(ThemeColors.bgPage)
            .onClick(() => { this.pickDate(1); })

            Blank()
            Button('查询').fontSize(13).height(32)
              .backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(6)
              .padding({ left: 14, right: 14 })
              .onClick(() => { this.onQueryRecords(); })
          }.width('100%').padding({ left: 18, right: 18, bottom: 10 })

          Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 18, right: 18 })

          if (this.records.length > 0 && !this.loading) {
            Row() {
              Text('合计 ¥' + this.totalAmount()).fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor('#C2410C')
              Text(' · ').fontSize(13).fontColor(ThemeColors.textHint)
              Text(this.records.length + ' 笔').fontSize(13).fontColor(ThemeColors.textSecondary)
            }.width('100%').padding({ left: 18, right: 18, top: 8, bottom: 4 })
          }

          if (this.records.length === 0) {
            Text(this.loading ? '加载中...' : '暂无消费记录')
              .fontSize(14).fontColor(ThemeColors.textSecondary)
              .width('100%').textAlign(TextAlign.Center).padding({ top: 28, bottom: 28 })
          } else {
            List() {
              ForEach(this.records, (item: PaidRecord, idx: number) => {
                ListItem() {
                  Row() {
                    Column({ space: 3 }) {
                      Text(item.place || '未知商户')
                        .fontSize(14).fontColor(ThemeColors.textPrimary)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(item.date)
                        .fontSize(11).fontColor(ThemeColors.textHint)
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ right: 10 })

                    Text(item.money)
                      .fontSize(15).fontWeight(FontWeight.Medium)
                      .fontColor('#C62828')
                  }
                  .width('100%')
                  .padding({ left: 18, right: 18, top: 11, bottom: 11 })
                }
              }, (item: PaidRecord, idx: number) => idx.toString())
            }
            .layoutWeight(1)
            .divider({ strokeWidth: 0.5, color: '#F5F5F5', startMargin: 18, endMargin: 18 })
          }
        }
        .borderRadius(12).backgroundColor(ThemeColors.bgCard)
        .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
        .margin({ left: 16, right: 16, top: 10 })
        .layoutWeight(1)

        // ========== 错误提示 ==========
        if (this.error) {
          Column({ space: 12 }) {
            Text(this.error).fontSize(15).fontColor('#C62828')
            Button('重试').fontSize(14)
              .backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(20)
              .padding({ left: 24, right: 24 })
              .onClick(() => { this.initData(); })
          }.width('100%').position({ x: '50%', y: '45%' }).markAnchor({ x: '50%', y: '50%' })
        }
      }
      .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
    }
    .title({ builder: this.buildWhiteTitle('校园卡'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder dateTag(label: string, days: number) {
    Text(label)
      .fontSize(12)
      .fontColor(this.activePreset === days ? this.accentColor : ThemeColors.textSecondary)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(10)
      .border({ width: 0.5, color: this.activePreset === days ? this.accentColor : ThemeColors.border })
      .backgroundColor(this.activePreset === days ? (this.accentColor + '18') : Color.Transparent)
      .onClick(() => { this.setDateRange(days); })
  }
}
