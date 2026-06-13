// SchoolCardPage.ets — 校园卡原生页面
// 余额、付款码、消费记录
// 全部数据通过 WebView 内 JS fetch 获取（避开 Cookie 隔离）
import { webview } from '@kit.ArkWeb';
import { ThemeColors } from '../../utils/ThemeColors';
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
  // WebView OAuth + API 多阶段
  @State wvActive: boolean = false;
  @State wvPhase: number = 0; // 0=idle, 1=OAuth获取openid, 2=查余额, 3=查付款码, 4=查消费记录
  private wvUrl: string = 'https://v8scan.xidian.edu.cn/home/openXDOAuth2Page';
  private wvController: webview.WebviewController = new webview.WebviewController();
  private openid: string = '';

  aboutToAppear(): void {
    this.triggerOAuth();
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
    console.info('SchoolCardPage', 'wvCleanup');
  }

  // Phase 2: 余额查询 JS fetch
  injectFetchBalance(): void {
    const js: string =
      'var x=new XMLHttpRequest();' +
      'x.open("GET","' + this.wvUrl.replace('/home/openXDOAuth2Page','/myaccount/openMyAccount?openid=') + this.openid + '",true);' +
      'x.onload=function(){console.log("SC_BAL:"+x.responseText);};' +
      'x.onerror=function(){console.log("SC_ERR:bal_network");};' +
      'x.send();';
    this.wvController.runJavaScript(js);
  }

  // Phase 3: 付款码
  injectFetchQR(): void {
    // 先取 home page 拿虚拟卡 id，再取二维码
    const homeJs: string =
      'fetch("' + this.wvUrl.replace('/home/openXDOAuth2Page','/home/openHomePage?openid=') + this.openid + '")' +
      '.then(function(r){return r.text();}).then(function(h){' +
      'var m=h.match(/id="(\\d+)"[^>]*>\\s*虚拟卡/);' +
      'if(!m){m=h.match(/"id":"(\\d+)"/);}' +
      'if(!m){m=h.match(/\\/virtualcard\\?[^"]*id=(\\d+)/);}' +
      'if(m){var id=m[1];' +
      '  return fetch("' + this.wvUrl.replace('/home/openXDOAuth2Page','/virtualcard/openVirtualcard?openid=') + this.openid + '&displayflag=1&id="+id);' +
      '}else{console.log("SC_ERR:qr_no_card_id");return Promise.reject();}' +
      '}).then(function(r){return r.text();}).then(function(t){' +
      'var bm=t.match(/src="data:image\\/png;base64,([^"]+)"/);' +
      'if(bm){console.log("SC_QR:"+bm[1]);}' +
      'else{console.log("SC_ERR:qr_no_barcode");}' +
      '}).catch(function(e){console.log("SC_ERR:qr_"+e);});';
    this.wvController.runJavaScript(homeJs);
  }

  // Phase 4: 消费记录
  injectFetchRecords(): void {
    const now = new Date();
    const end = now.toISOString().split('T')[0];
    now.setDate(now.getDate() - 30);
    const begin = now.toISOString().split('T')[0];
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

  // Phase 已完成标记
  private balDone: boolean = false;
  private qrDone: boolean = false;
  private recDone: boolean = false;

  checkAllDone(): void {
    if (this.balDone && this.qrDone && this.recDone) {
      this.wvCleanup();
      this.loading = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 余额卡片
        Row() {
          Text('校园卡余额').fontSize(14).fontColor('#FFFFFFCC')
          Blank()
          this.barcodeBtn()
        }.width('100%').padding({ left: 20, right: 16, top: 20, bottom: 8 })

        Row() {
          Text('¥ ' + this.balance).fontSize(36).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        }.width('100%').padding({ left: 20, right: 20, bottom: 20 })

        // 付款码
        if (this.showBarcode && this.qrBase64) {
          Column() {
            Row() {
              Text('付款码').fontSize(14).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            }.width('100%').padding({ left: 16, right: 16, top: 14 })
            Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 16, right: 16 })
            Row() {
              Image('data:image/png;base64,' + this.qrBase64)
                .width(200).height(200).objectFit(ImageFit.Contain)
            }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 12, bottom: 12 })
          }.borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          .margin({ left: 16, right: 16, top: 0 })
        }

        // 消费记录
        Column() {
          Row() {
            Text('近期消费').fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
            Blank()
            Text(this.records.length + ' 条').fontSize(12).fontColor(ThemeColors.textHint)
          }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 10 })
          Divider().color('#E0E0E0').strokeWidth(0.5).margin({ left: 16, right: 16 })
          if (this.records.length === 0) {
            Text(this.loading ? '加载中...' : '暂无消费记录').fontSize(14).fontColor(ThemeColors.textSecondary)
              .width('100%').textAlign(TextAlign.Center).padding({ top: 20, bottom: 20 })
          } else {
            List() {
              ForEach(this.records.slice(0, 20), (item: PaidRecord, idx: number) => {
                ListItem() {
                  Row() {
                    Column() {
                      Text(item.place || '未知商户').fontSize(14).fontColor(ThemeColors.textPrimary).maxLines(1)
                      Text(item.date).fontSize(11).fontColor(ThemeColors.textHint).margin({ top: 2 })
                    }.layoutWeight(1).margin({ right: 8 })
                    Text('-' + item.money + '元').fontSize(14).fontWeight(FontWeight.Medium)
                      .fontColor(ThemeColors.textPrimary)
                  }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
                }
                if (idx < this.records.length - 1)
                  Divider().color('#F0F0F0').strokeWidth(0.5).margin({ left: 16, right: 16 })
              })
            }.layoutWeight(1).divider({ strokeWidth: 0 })
          }
        }.borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
        .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
        .margin({ left: 16, right: 16, top: 12 }).layoutWeight(1)
      }
      .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)

      // 隐藏 WebView：OAuth + 所有 API 调用都在里面完成
      if (this.wvActive) {
        Web({ src: this.wvUrl, controller: this.wvController })
          .width('300px')
          .height('300px')
          .position({ x: -400, y: 0 })
          .domStorageAccess(true)
          .javaScriptAccess(true)
          .onPageEnd((event) => {
            if (!event || !event.url) return;
            const url: string = event.url;
            console.info('SchoolCardPage', 'wv pageEnd phase=' + this.wvPhase + ' url=' + url.substring(0, 120));
            if (this.wvPhase === 1 && url.indexOf('v8scan.xidian.edu.cn') >= 0 &&
              url.indexOf('openXDOAuth2Page') < 0) {
              // Phase 1 完成：CAS SSO 完成，注入 JS 提取 openid
              const js: string = 'var i=document.getElementById("openid");' +
                'if(i&&i.value){console.log("SC_OPENID:"+i.value);}' +
                'else{console.log("SC_ERR:openid_not_found");}';
              this.wvController.runJavaScript(js);
            }
          })
          .onConsole((event): boolean => {
            if (!event || !event.message) return false;
            const msg: string = event.message.getMessage();

            // Phase 1: openid
            if (msg.indexOf('SC_OPENID:') === 0) {
              this.openid = msg.substring(9).trim().replace(/^:/, '');
              console.info('SchoolCardPage', 'SC_OPENID=' + this.openid);
              // 同时注入到 SchoolCardService（主页卡片复用）
              SchoolCardService.getInstance().setOpenId(this.openid);
              // 进入 Phase 2-4: 并行查余额/付款码/消费
              this.wvPhase = 2;
              this.balDone = false;
              this.qrDone = false;
              this.recDone = false;
              this.injectFetchBalance();
              this.injectFetchQR();
              this.injectFetchRecords();
              return true;
            }

            // Phase 2: 余额
            if (msg.indexOf('SC_BAL:') === 0) {
              const html: string = msg.substring(7);
              console.info('SchoolCardPage', 'SC_BAL len=' + html.length);
              // 从 HTML 解析余额数字
              const liM = html.match(/<li[^>]*>[\s\S]*?(\d+\.\d{2})[\s\S]*?<\/li>/);
              const mMoney = liM ? liM[1] : html.match(/(\d+\.\d{2})/)?.[1] || '';
              this.balance = mMoney || '--';
              this.balDone = true;
              this.checkAllDone();
              return true;
            }

            // Phase 3: 付款码
            if (msg.indexOf('SC_QR:') === 0) {
              this.qrBase64 = msg.substring(6);
              console.info('SchoolCardPage', 'SC_QR len=' + this.qrBase64.length);
              this.showBarcode = true;
              this.qrDone = true;
              this.checkAllDone();
              return true;
            }

            // Phase 4: 消费记录
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
                }
              } catch (e) {
                console.warn('SchoolCardPage', 'SC_RECS parse failed: ' + String(e));
              }
              this.recDone = true;
              this.checkAllDone();
              return true;
            }

            // 各类错误
            if (msg.indexOf('SC_ERR:') === 0) {
              const err: string = msg.substring(7);
              console.warn('SchoolCardPage', 'SC_ERR ' + err);
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

      if (this.error) {
        Text(this.error).fontSize(13).fontColor('#C62828')
          .width('100%').textAlign(TextAlign.Center)
          .position({ x: '50%', y: '45%' }).markAnchor({ x: '50%' })
        Button('重试').fontSize(14)
          .backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(20)
          .padding({ left: 20, right: 20 })
          .position({ x: '50%', y: '55%' }).markAnchor({ x: '50%' })
          .onClick(() => { this.triggerOAuth(); })
        Button('在网页中管理校园卡').fontSize(14).margin({ top: 8 })
          .backgroundColor('#FFFFFF33').fontColor(this.accentColor).borderRadius(20)
          .padding({ left: 20, right: 20 })
          .position({ x: '50%', y: '62%' }).markAnchor({ x: '50%' })
          .onClick(() => {
            this.pageInfo.pop();
            this.pageInfo.pushPath({ name: 'PortalWeb_SchoolCard' });
          })
      }
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder barcodeBtn() {
    Button() {
      Text(this.showBarcode ? '隐藏付款码' : '显示付款码').fontSize(13).fontColor('#FFFFFF')
    }
    .height(32).backgroundColor('#FFFFFF33').borderRadius(16).padding({ left: 12, right: 12 })
    .onClick(() => { this.showBarcode = !this.showBarcode; })
  }
}
