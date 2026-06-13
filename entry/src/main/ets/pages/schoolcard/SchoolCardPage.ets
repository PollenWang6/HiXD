// SchoolCardPage.ets — 校园卡原生页面
// 余额、付款码、消费记录
import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { PaidRecord, SchoolCardService } from '../../services/SchoolCardService';

@Component
export struct SchoolCardPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
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
  // WebView
  @State wvActive: boolean = false;
  @State wvPhase: number = 0; // 0=home, 1=OAuth, 2=余额+消费, 3=取QR
  private wvUrl: string = 'https://v8scan.xidian.edu.cn/home/openXDOAuth2Page';
  private wvController: webview.WebviewController = new webview.WebviewController();
  private openid: string = '';

  aboutToAppear(): void {
    const now = new Date();
    const thirtyAgo = new Date(now.getTime() - 30 * 86400000);
    this.endDate = this.fmtDate(now);
    this.beginDate = this.fmtDate(thirtyAgo);
    this.triggerOAuth();
  }

  fmtDate(d: Date): string {
    const y: number = d.getFullYear();
    const mn: number = d.getMonth() + 1;
    const dy: number = d.getDate();
    const m: string = mn < 10 ? '0' + String(mn) : String(mn);
    const day: string = dy < 10 ? '0' + String(dy) : String(dy);
    return y + '-' + m + '-' + day;
  }

  parseDate(s: string): Date {
    const p = s.split('-');
    return new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
  }

  triggerOAuth(): void {
    if (this.wvActive) return;
    console.info('SchoolCardPage', 'triggerOAuth');
    this.wvActive = true;
    this.wvPhase = 1;
    this.loading = true;
    this.error = '';
  }

  wvCleanup(): void {
    this.wvActive = false;
    this.wvPhase = 0;
  }

  // 余额
  injectFetchBalance(): void {
    const js: string =
      'fetch("' + this.wvUrl.replace('/home/openXDOAuth2Page','/myaccount/openMyAccount?openid=') + this.openid + '")' +
      '.then(function(r){return r.text();}).then(function(t){console.log("SC_BAL:"+t.length+"|"+t);})' +
      '.catch(function(e){console.log("SC_BAL_ERR:"+e);});';
    this.wvController.runJavaScript(js);
  }

  // 消费记录
  injectFetchRecords(begin: string, end: string): void {
    const body: string = JSON.stringify({
      beginDate: begin,
      endDate: end,
      tradeType: '-1',
      openid: this.openid,
    });
    const js: string =
      'var x=new XMLHttpRequest();' +
      'x.open("POST","' + this.wvUrl.replace('/home/openXDOAuth2Page','/selftrade/queryCardSelfTradeList?openid=') + this.openid + '",true);' +
      'x.setRequestHeader("Content-Type","application/json; charset=utf-8");' +
      'x.onload=function(){console.log("SC_RECS:"+x.responseText);};' +
      'x.onerror=function(){console.log("SC_ERR:recs_network");};' +
      'x.send(' + JSON.stringify(body) + ');';
    this.wvController.runJavaScript(js);
  }

  // 二维码：按需获取
  fetchQRCode(): void {
    if (this.qrBase64) {
      this.showBarcode = true;
      return;
    }
    if (!this.openid) return;
    this.qrLoading = true;
    this.wvPhase = 3;
    this.wvController.loadUrl('https://v8scan.xidian.edu.cn/virtualcard/openVirtualcard?openid=' +
      this.openid + '&displayflag=1&id=2022082613');
  }

  private balDone: boolean = false;
  private recDone: boolean = false;

  checkInitDone(): void {
    if (this.balDone && this.recDone) {
      this.loading = false;
    }
  }

  onQueryRecords(): void {
    if (!this.wvActive || !this.openid) return;
    this.injectFetchRecords(this.beginDate, this.endDate);
    this.loading = true;
  }

  setDateRange(days: number): void {
    const now = new Date();
    const start = new Date(now.getTime() - days * 86400000);
    this.endDate = this.fmtDate(now);
    this.beginDate = this.fmtDate(start);
    this.onQueryRecords();
  }

  // 日期选择器
  pickDate(kind: number): void { // 0=开始, 1=结束
    const curDate = this.parseDate(kind === 0 ? this.beginDate : this.endDate);
    DatePickerDialog.show({
      start: new Date('2022-01-01'),
      end: new Date(),
      selected: curDate,
      lunar: false,
      onAccept: (value: DatePickerResult) => {
        const picked = this.fmtDate(new Date(value.year, value.month, value.day));
        if (kind === 0) {
          this.beginDate = picked;
        } else {
          this.endDate = picked;
        }
        this.onQueryRecords();
      }
    });
  }

  build() {
    NavDestination() {
      Stack() {
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
                LoadingProgress().width(24).height(24).margin({ top: 24, bottom: 24 })
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
            .borderRadius(14).backgroundColor(ThemeColors.bgCard)
            .shadow({ radius: 4, color: '#0000000A', offsetY: 2 })
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
            }.width('100%').padding({ left: 18, right: 18, bottom: 8 })

            // 日期选择行 — 点击弹出 DatePicker
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
                        .fontColor('#E53935')
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
          .borderRadius(14).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 4, color: '#0000000A', offsetY: 2 })
          .margin({ left: 16, right: 16, top: 10 })
          .layoutWeight(1)
        }
        .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)

        // ========== 隐藏 WebView ==========
        if (this.wvActive) {
          Web({ src: this.wvUrl, controller: this.wvController })
            .width('300px').height('300px')
            .position({ x: -400, y: 0 })
            .domStorageAccess(true).javaScriptAccess(true)
            .onPageEnd((event) => {
              if (!event || !event.url) return;
              const url: string = event.url;
              console.info('SchoolCardPage', 'wv pageEnd phase=' + this.wvPhase +
                ' url=' + url.substring(0, 150));

              if (this.wvPhase === 1 && url.indexOf('v8scan.xidian.edu.cn') >= 0 &&
                url.indexOf('openXDOAuth2Page') < 0) {
                const js: string = 'var i=document.getElementById("openid");' +
                  'if(i&&i.value){console.log("SC_OPENID:"+i.value);}' +
                  'else{console.log("SC_ERR:openid_not_found");}';
                this.wvController.runJavaScript(js);
                return;
              }

              if (this.wvPhase === 3 && url.indexOf('openVirtualcard') >= 0) {
                const qrJs: string =
                  'var imgs=document.querySelectorAll("img");' +
                  'for(var i=0;i<imgs.length;i++){' +
                  'var src=imgs[i].getAttribute("src")||"";' +
                  'if(src.indexOf("data:image/png;base64,")===0){' +
                  'console.log("SC_QR:"+src.substring(22));break;' +
                  '}}' +
                  'if(!imgs.length||!imgs[0]){console.log("SC_QR_SKIP:no_img");}';
                this.wvController.runJavaScript(qrJs);
                return;
              }
            })
            .onConsole((event): boolean => {
              if (!event || !event.message) return false;
              const msg: string = event.message.getMessage();

              if (msg.indexOf('SC_OPENID:') === 0) {
                this.openid = msg.substring(9).trim().replace(/^:/, '');
                console.info('SchoolCardPage', 'SC_OPENID=' + this.openid);
                SchoolCardService.getInstance().setOpenId(this.openid);
                this.wvPhase = 2;
                this.balDone = false;
                this.recDone = false;
                this.injectFetchBalance();
                this.injectFetchRecords(this.beginDate, this.endDate);
                return true;
              }

              if (msg.indexOf('SC_BAL:') === 0) {
                const payload: string = msg.substring(7);
                const pipe: number = payload.indexOf('|');
                const balLen: number = pipe >= 0 ? parseInt(payload.substring(0, pipe)) : payload.length;
                const html: string = pipe >= 0 ? payload.substring(pipe + 1) : payload;
                console.info('SchoolCardPage', 'SC_BAL len=' + balLen);
                if (balLen > 100) {
                  const mMoney = html.match(/(\d+\.\d{2})元/)?.[1] ||
                    html.match(/(\d+\.\d{2})/)?.[1] || '';
                  this.balance = mMoney || '--';
                } else {
                  this.balance = '--';
                }
                AppStorage.setOrCreate('card_balance', this.balance);
                PreferenceUtil.putString('card_balance_cached', this.balance);
                this.balDone = true;
                this.checkInitDone();
                return true;
              }

              if (msg.indexOf('SC_BAL_ERR:') === 0) {
                console.warn('SchoolCardPage', 'SC_BAL_ERR: ' + msg.substring(11));
                this.balance = '--';
                this.balDone = true;
                this.checkInitDone();
                return true;
              }

              if (msg.indexOf('SC_QR:') === 0) {
                this.qrBase64 = msg.substring(6);
                console.info('SchoolCardPage', 'SC_QR len=' + this.qrBase64.length);
                this.showBarcode = true;
                this.qrLoading = false;
                this.wvPhase = 2;
                return true;
              }

              if (msg.indexOf('SC_QR_SKIP:') === 0) {
                console.info('SchoolCardPage', 'QR skip: ' + msg.substring(11));
                this.qrLoading = false;
                this.wvPhase = 2;
                return true;
              }

              if (msg.indexOf('SC_RECS:') === 0) {
                const raw: string = msg.substring(8);
                console.info('SchoolCardPage', 'SC_RECS len=' + raw.length);
                try {
                  const data = JSON.parse(raw) as Record<string, Object>;
                  const resultData = data['resultData'] as Array<Record<string, string>>;
                  if (resultData) {
                    const list: PaidRecord[] = [];
                    for (let i = 0; i < resultData.length; i++) {
                      const item = resultData[i];
                      list.push({
                        place: item['mername'] || '',
                        date: item['txdate'] || '',
                        money: item['txamt'] || '',
                      });
                    }
                    this.records = list;
                    promptAction.showToast({ message: '查询成功，共 ' + String(list.length) + ' 条', duration: 2000 });
                  }
                } catch (e) {
                  console.warn('SchoolCardPage', 'SC_RECS parse failed: ' + String(e));
                }
                this.recDone = true;
                this.checkInitDone();
                return true;
              }

              if (msg.indexOf('SC_ERR:') === 0) {
                console.warn('SchoolCardPage', 'SC_ERR ' + msg.substring(7));
                this.error = '校园卡加载失败';
                this.loading = false;
                this.wvCleanup();
                return true;
              }

              return false;
            })
            .onErrorReceive((event) => {
              console.error('SchoolCardPage', 'wv error: ' + JSON.stringify(event));
              this.error = '校园卡网络错误';
              this.loading = false;
              this.wvCleanup();
            })
        }

        // 错误提示
        if (this.error) {
          Column({ space: 12 }) {
            Text(this.error).fontSize(15).fontColor('#C62828')
            Row({ space: 10 }) {
              Button('重试').fontSize(14)
                .backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(20)
                .padding({ left: 24, right: 24 })
                .onClick(() => { this.triggerOAuth(); })
              Button('网页管理').fontSize(14)
                .backgroundColor('#E0E0E0').fontColor(ThemeColors.textSecondary).borderRadius(20)
                .padding({ left: 24, right: 24 })
                .onClick(() => {
                  this.pageInfo.pop();
                  this.pageInfo.pushPath({ name: 'PortalWeb_SchoolCard' });
                })
            }
          }
          .width('100%').position({ x: '50%', y: '45%' }).markAnchor({ x: '50%', y: '50%' })
        }
      }
    }
    .title('校园卡', { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder dateTag(label: string, days: number) {
    Text(label)
      .fontSize(12)
      .fontColor(this.accentColor)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(10)
      .border({ width: 0.5, color: this.accentColor })
      .onClick(() => { this.setDateRange(days); })
  }
}
