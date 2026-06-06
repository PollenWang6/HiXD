// ElectricityPage.ets — 电费查询（HTTP + cryptoFramework AES，WebView 仅做 SSO 拿 code）
import { ThemeColors } from '../../utils/ThemeColors';
import { webview } from '@kit.ArkWeb';
import web_webview from '@ohos.web.webview';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { HttpUtil } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { CasLoginService } from '../../services/CasLoginService';

const TAG: string = 'ElectricityPage';

// xxcapp OAuth SSO 入口（WebView 自动跟随重定向，利用 CookieJar 中 TGC 完成 CAS 登录）
const SSO_ENTRY: string =
  'https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=https://ignypt.xidian.edu.cn/revenueH5/login?opcode=MPAY&appid=200260318155520600&state=12312312312312&qrcode=0';

const AES_KEY: string = '1234567812345678'; // AES-CBC key=IV

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
  // 水费字段（可选，部分宿舍可能没有水表）
  waterRemain: string;
  waterMetID: string;
  waterDate: string;
  waterDaily: DailyItem[];
}

interface CodeReq { CODE: string }
interface LoginReq { UserID: string; Pwd: string; IsCehckPwd: string; NodeID: string }
interface NodeReq { NodeID: string }
interface MeterReq { MetID: string; ReadTimeS: string; ReadTimeE: string; ReadNum: string }
interface PostBody { content: string }
interface SigReq { data: string; access_token: string; OpCode: string; RequestID: string }

function strToU8(s: string): Uint8Array {
  const buf: Array<number> = [];
  for (let i: number = 0; i < s.length; i++) {
    buf.push(s.charCodeAt(i) & 0xFF);
  }
  return new Uint8Array(buf);
}

function u8ToStr(u: Uint8Array): string {
  const buf: Array<number> = [];
  for (let i: number = 0; i < u.length; i++) {
    buf.push(u[i]);
  }
  let result: string = '';
  for (let i: number = 0; i < buf.length; i++) {
    result += String.fromCharCode(buf[i]);
  }
  return result;
}

function base64Encode(u8: Uint8Array): string {
  const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result: string = '';
  for (let i: number = 0; i < u8.length; i += 3) {
    const b0: number = u8[i];
    const b1: number = i + 1 < u8.length ? u8[i + 1] : 0;
    const b2: number = i + 2 < u8.length ? u8[i + 2] : 0;
    result += chars.charAt((b0 >> 2) & 0x3F);
    result += chars.charAt(((b0 << 4) | (b1 >> 4)) & 0x3F);
    result += i + 1 < u8.length ? chars.charAt(((b1 << 2) | (b2 >> 6)) & 0x3F) : '=';
    result += i + 2 < u8.length ? chars.charAt(b2 & 0x3F) : '=';
  }
  return result;
}

@Component
export struct ElectricityPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @State isLoading: boolean = true;
  @State loadError: string = '';
  // 电费
  @State balance: string = '';
  @State metID: string = '';
  @State readDate: string = '';
  @State dailyItems: DailyItem[] = [];
  @State displayDaily: DailyItem[] = [];
  @State showMore: boolean = false;
  // 水费
  @State waterBalance: string = '';
  @State waterMetID: string = '';
  @State waterReadDate: string = '';
  @State waterDailyItems: DailyItem[] = [];
  @State waterDisplayDaily: DailyItem[] = [];
  @State showMoreWater: boolean = false;
  @StorageLink('electricity_cache') @Watch('onCacheChanged') elCache: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;
  @State webViewSrc: string = '';

  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private isSilent: boolean = false;
  private http: HttpUtil = HttpUtil.getInstance();
  private ssoDone: boolean = false;

  async aboutToAppear(): Promise<void> {
    // 先同步 HTTP cookie 到 WebView，再加载 SSO 页面（避免 cookie 未就绪的竞态）
    await CasLoginService.getInstance().syncCookiesToWebView();
    this.webViewSrc = SSO_ENTRY;

    // 静默模式：自动刷新后 pop
    const silent: boolean = AppStorage.Get('electricity_silent') as boolean;
    if (silent === true) {
      AppStorage.Set('electricity_silent', false);
      this.isSilent = true;
      return;
    }

    // 非静默模式：有缓存立即展示
    if (this.elCache.length > 0) {
      this.onCacheChanged();
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
      // 水费缓存恢复
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
    try { web_webview.WebviewController.removeAllCache(false); } catch (_e) { /* ignore */ }
  }

  private extractCode(url: string): string {
    if (url.length === 0) return '';
    const idx: number = url.indexOf('code=');
    if (idx < 0) return '';
    const code: string = url.substring(idx + 5);
    const amp: number = code.indexOf('&');
    return amp >= 0 ? code.substring(0, amp) : code;
  }

  // AES-CBC 加密（cryptoFramework）
  private async aesEncrypt(plaintext: string): Promise<string> {
    const keyData: cryptoFramework.DataBlob = { data: strToU8(AES_KEY) };
    const iv: cryptoFramework.DataBlob = { data: strToU8(AES_KEY) };

    const gen = cryptoFramework.createSymKeyGenerator('AES128');
    const symKey: cryptoFramework.SymKey = await gen.convertKey(keyData);

    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS5');
    const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: iv } as cryptoFramework.IvParamsSpec;
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);

    const input: cryptoFramework.DataBlob = { data: strToU8(plaintext) };
    const output: cryptoFramework.DataBlob = await cipher.doFinal(input);

    return base64Encode(output.data);
  }

  // 日期往前推 n 天
  private dayShift(n: number): string {
    const d: number = Date.now() - n * 86400000;
    const dt: Date = new Date(d);
    const y: string = String(dt.getFullYear());
    const m: string = String(dt.getMonth() + 1).padStart(2, '0');
    const day: string = String(dt.getDate()).padStart(2, '0');
    return y + '-' + m + '-' + day;
  }

  // ===== ignypt HTTP API 链（Step 1-5） =====
  private async fetchData(code: string): Promise<void> {
    if (!this.isSilent) this.isLoading = true;
    this.loadError = '';
    const IG_HEADERS: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36'
    };

    try {
      // ── Step 1: GetSignature ──
      const sigUrl = 'https://ignypt.xidian.edu.cn/baseNew/api/User/GetSignature';
      const emptySigBody: SigReq = { data: '', access_token: '', OpCode: 'MPAY', RequestID: '' };
      const sigResp = await this.http.post(sigUrl, emptySigBody, IG_HEADERS);
      if (!sigResp.isOk) throw new Error('GetSignature failed: ' + sigResp.statusCode);
      const sigJson: object = JSON.parse(sigResp.body) as object;
      const sigData: Record<string, object> = (sigJson as Record<string, object>)['data'] as Record<string, object>;
      const timestamp: string = String(sigData['timestamp']);
      const signature: string = String(sigData['signature']);
      const apiHeaders: Record<string, string> = {
        'timestamp': timestamp,
        'signature': signature,
        'OpCode': 'MPAY',
        'OrgId': '',
        'RequestID': ''
      };
      console.error(TAG, 'Step1 OK, timestamp=' + timestamp);

      // ── Step 2: OauthGetUserInfo ──
      const step2Req: CodeReq = { CODE: code };
      const enc2: string = await this.aesEncrypt(JSON.stringify(step2Req));
      const uInfoUrl: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/OauthGetUserInfo?content=' + encodeURIComponent(enc2);
      const uInfoResp = await this.http.get(uInfoUrl, apiHeaders);
      if (!uInfoResp.isOk) throw new Error('OauthGetUserInfo failed: ' + uInfoResp.statusCode);
      console.error(TAG, 'Step2 OK');

      // ── Step 3: H5UserIDLogIn ──
      const userId: string = PreferenceUtil.getString('ids_account') || PreferenceUtil.getString('login_username') || '';
      const step3Req: LoginReq = { UserID: userId, Pwd: '', IsCehckPwd: '1', NodeID: '' };
      const enc3: string = await this.aesEncrypt(JSON.stringify(step3Req));
      const loginBody: PostBody = { content: enc3 };
      const loginResp = await this.http.post('https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/H5UserIDLogIn',
        loginBody, apiHeaders);
      if (!loginResp.isOk) throw new Error('H5UserIDLogIn failed: ' + loginResp.statusCode);
      const loginJson: object = JSON.parse(loginResp.body) as object;
      const resData: object[] = (loginJson as Record<string, object[]>)['ResData'] as object[];
      const nodeID: string = String((resData[0] as Record<string, object>)['NodeID']);
      console.error(TAG, 'Step3 OK, NodeID=' + nodeID);

      // ── Step 4: H5QueryMeterList ──
      const step4Req: NodeReq = { NodeID: nodeID };
      const enc4: string = await this.aesEncrypt(JSON.stringify(step4Req));
      const meterUrl: string = 'https://ignypt.xidian.edu.cn/estManage/api/wechat/v2/H5QueryMeterList?content=' + encodeURIComponent(enc4);
      const meterResp = await this.http.get(meterUrl, apiHeaders);
      if (!meterResp.isOk) throw new Error('H5QueryMeterList failed: ' + meterResp.statusCode);
      const meterJson: object = JSON.parse(meterResp.body) as object;
      const md: object = (meterJson as Record<string, object>)['ResData'] as object;
      const rows: object[] = (md as Record<string, object[]>)['rows'] as object[];
      // ━━━ DEBUG: 打印 Step4 全量原始数据 ━━━
      console.error('========== STEP4 RAW RESPONSE ==========');
      console.error(meterResp.body);
      console.error('========== STEP4 ROWS FIELDS ==========');
      for (let di: number = 0; di < rows.length; di++) {
        const dr: Record<string, object> = rows[di] as Record<string, object>;
        const keys: string[] = Object.keys(dr);
        let dump: string = '--- Row[' + di + '] all fields ---';
        for (let ki: number = 0; ki < keys.length; ki++) {
          const k: string = String(keys[ki]);
          dump += '\n  ' + k + ' = ' + JSON.stringify(dr[k]);
        }
        console.error(dump);
      }
      // Find electric meter (MediumCode=2) and water meter (other)
      let elecRow: Record<string, object> = rows[0] as Record<string, object>;
      let hasWater: boolean = false;
      let waterRemain: string = '';
      let waterMetID: string = '';
      let waterDate: string = '';
      for (let i: number = 0; i < rows.length; i++) {
        const r: Record<string, object> = rows[i] as Record<string, object>;
        if (String(r['MediumCode']) === '2') {
          elecRow = r;
        } else {
          hasWater = true;
          waterRemain = String(r['UsedNum']);
          waterMetID = String(r['MetID']);
          waterDate = String(r['LastReadDate']);
        }
      }
      const remain: string = String(elecRow['LastNum']);
      const metID: string = String(elecRow['MetID']);
      const readDate: string = String(elecRow['LastReadDate']);
      console.error(TAG, 'Step4 OK, remain=' + remain + ', metID=' + metID + ', hasWater=' + String(hasWater));

      // ── Step 5: GetMetRead (30天) ──
      const daily: DailyItem[] = [];
      let waterDaily: DailyItem[] = [];
      try {
        const step5Req: MeterReq = { MetID: metID, ReadTimeS: this.dayShift(30), ReadTimeE: this.dayShift(0), ReadNum: '' };
        const enc5: string = await this.aesEncrypt(JSON.stringify(step5Req));
        const readUrl: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/GetMetRead?content=' + encodeURIComponent(enc5);
        const readResp = await this.http.get(readUrl, apiHeaders);
        if (readResp.isOk) {
          // ━━━ DEBUG: 打印 Step5 电费全量原始数据 ━━━
          console.error('========== STEP5 (ELEC) RAW RESPONSE ==========');
          console.error(readResp.body);
          const readJson: object = JSON.parse(readResp.body) as object;
          const rd: object = (readJson as Record<string, object>)['ResData'] as object;
          const rdRows: object[] = (rd as Record<string, object[]>)['rows'] as object[] || [] as object[];
          // 打印第一条记录的所有字段
          if (rdRows.length > 0) {
            const firstRow: Record<string, object> = rdRows[0] as Record<string, object>;
            const keys: string[] = Object.keys(firstRow);
            let dump: string = '--- Elec Row[0] all fields ---';
            for (let ki: number = 0; ki < keys.length; ki++) {
              const k: string = String(keys[ki]);
              dump += '\n  ' + k + ' = ' + JSON.stringify(firstRow[k]);
            }
            console.error(dump);
          }
          for (let i: number = 0; i < rdRows.length; i++) {
            const r: Record<string, object> = rdRows[i] as Record<string, object>;
            const date: string = String(r['ReadTime']).substring(0, 10);
            const startNum: string = Number(r['StartNum']).toFixed(2);
            const endNum: string = Number(r['EndNum']).toFixed(2);
            const use: string = Number(r['ReadNum']).toFixed(2);
            if (i + 1 < rdRows.length) {
              const nr: Record<string, object> = rdRows[i + 1] as Record<string, object>;
              const prevDate: string = String(nr['ReadTime']).substring(0, 10);
              daily.push({ date: date, prevDate: prevDate, use: use, startNum: startNum, endNum: endNum });
            }
          }
          console.error(TAG, 'Step5 OK, daily records=' + daily.length);
        }
        // Water meter readings
        if (hasWater) {
          const wReq: MeterReq = { MetID: waterMetID, ReadTimeS: this.dayShift(365), ReadTimeE: this.dayShift(0), ReadNum: '' };
          const wEnc: string = await this.aesEncrypt(JSON.stringify(wReq));
          const wUrl: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/GetMetRead?content=' + encodeURIComponent(wEnc);
          const wResp = await this.http.get(wUrl, apiHeaders);
          if (wResp.isOk) {
            // ━━━ DEBUG: 打印 Step5 水费全量原始数据 ━━━
            console.error('========== STEP5 (WATER) RAW RESPONSE ==========');
            console.error(wResp.body);
            const wJson: object = JSON.parse(wResp.body) as object;
            const wrd: object = (wJson as Record<string, object>)['ResData'] as object;
            const wRows: object[] = (wrd as Record<string, object[]>)['rows'] as object[] || [] as object[];
            // 打印第一条记录的所有字段
            if (wRows.length > 0) {
              const firstRow: Record<string, object> = wRows[0] as Record<string, object>;
              const keys: string[] = Object.keys(firstRow);
              let dump: string = '--- Water Row[0] all fields ---';
              for (let ki: number = 0; ki < keys.length; ki++) {
                const k: string = String(keys[ki]);
                dump += '\n  ' + k + ' = ' + JSON.stringify(firstRow[k]);
              }
              console.error(dump);
            }
            for (let i: number = 0; i < wRows.length; i++) {
              const r: Record<string, object> = wRows[i] as Record<string, object>;
              const date: string = String(r['ReadTime']).substring(0, 10);
              const startNum: string = Number(r['StartNum']).toFixed(2);
              const endNum: string = Number(r['EndNum']).toFixed(2);
              const use: string = Number(r['ReadNum']).toFixed(2);
              waterDaily.push({ date: date, prevDate: '', use: use, startNum: startNum, endNum: endNum });
            }
            console.error(TAG, 'Step5 water OK, daily records=' + waterDaily.length);
          }
        }
      } catch (e5) {
        console.warn(TAG, 'Step5 failed (non-critical): ' + JSON.stringify(e5));
      }

      // ── 写入缓存 ──
      const cache: ElecCache = { remain: remain, metID: metID, nodeID: nodeID, date: readDate, daily: daily, error: '', waterRemain: waterRemain, waterMetID: waterMetID, waterDate: waterDate, waterDaily: waterDaily };
      AppStorage.SetOrCreate('electricity_cache', JSON.stringify(cache));

      // 直接更新本组件状态（@Watch 可能不触发）
      this.balance = remain;
      this.metID = metID;
      this.readDate = readDate;
      this.dailyItems = daily;
      this.displayDaily = daily.slice(0, 7);
      this.waterBalance = waterRemain;
      this.waterMetID = waterMetID;
      this.waterReadDate = waterDate;
      this.waterDailyItems = waterDaily;
      this.waterDisplayDaily = waterDaily.slice(0, 7);
      
      this.isLoading = false;

      if (this.isSilent) {
        this.isSilent = false;
        this.pageInfo.pop();
      }
    } catch (e) {
      const errMsg: string = e instanceof Error ? (e as Error).message : JSON.stringify(e);
      console.error(TAG, 'fetchData failed: ' + errMsg);
      this.loadError = errMsg;
      this.isLoading = false;
      if (this.isSilent) {
        this.isSilent = false;
        this.pageInfo.pop();
      }
    }
  }

  private doRefresh(): void {
    this.isLoading = true;
    this.loadError = '';
    this.balance = '';
    this.metID = '';
    this.readDate = '';
    this.dailyItems = [];
    this.ssoDone = false;
    AppStorage.SetOrCreate('electricity_cache', '');
    // WebView SSO 入口已通过 src 加载，这里只需确保重新加载
    this.webController.loadUrl(SSO_ENTRY);
  }

  private fmtDate(d: string): string {
    if (d.length < 10) return d;
    let m: string = d.substring(5, 7);
    let day: string = d.substring(8, 10);
    if (m.charAt(0) === '0') { m = m.substring(1); }
    if (day.charAt(0) === '0') { day = day.substring(1); }
    return m + '月' + day + '日';
  }

  @Builder
  fullReadingsBuilder(): void {
    Column() {
      Row() {
        Text('全部抄读记录').fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        Blank()
        Image($r('app.media.ic_public_close'))
          .width(24).height(24)
          .fillColor(ThemeColors.textSecondary)
          .onClick(() => { this.showMore = false; })
      }
      .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 10 })

      Scroll() {
        Column() {
          ForEach(this.dailyItems, (item: DailyItem, index: number) => {
            Column() {
              // 第一行：读表时间 + 用量
              Row() {
                Text(this.fmtDate(item.date)).fontSize(13).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
                Blank()
                Text(item.use + ' kWh').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              }.width('100%')
              // 第二行：上次读数 / 本次读数
              Row() {
                Text('上次: ' + item.startNum).fontSize(11).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
                Blank()
                Text('本次: ' + item.endNum).fontSize(11).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
              }.width('100%').margin({ top: 2 })
            }
            .width('100%').padding({ top: 10, bottom: 10 })
            if (index < this.dailyItems.length - 1) {
              Divider().color('#F5F5F5')
            }
          }, (item: DailyItem): string => item.date)
        }
        .width('100%').padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgCard)
  }

  build() {
    NavDestination() {
      Stack() {
        // 隐藏 WebView（全尺寸，被 UI 层覆盖，仅做 SSO 拿 code）
        Web({ src: this.webViewSrc, controller: this.webController })
          .width('100%').height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageEnd((event) => {
            if (event && event.url && !this.ssoDone) {
              const code: string = this.extractCode(event.url);
              if (code.length > 0) {
                this.ssoDone = true;
                console.error(TAG, 'SSO code obtained: ' + code.substring(0, 10) + '...');
                this.fetchData(code);
              }
            }
          })
          .onErrorReceive((event) => {
            if (event) {
              console.error(TAG, 'WebView error: ' + event.error.getErrorInfo());
              this.loadError = '加载失败: ' + event.error.getErrorInfo();
              this.isLoading = false;
            }
          })

        // 原生 UI 层
        Column() {
          // Loading
          if (this.isLoading) {
            Column() {
              LoadingProgress().width(48).height(48).color(this.accentColor)
              Text('正在查询水电...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 16 })
            }
            .width('100%').layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          }

          // Error
          if (!this.isLoading && this.loadError.length > 0) {
            Column() {
              Text('😞').fontSize(48)
              Text(this.loadError).fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
              Button('重试').fontSize(14).height(36)
                .backgroundColor('#FF6D00').fontColor('#FFFFFF').borderRadius(20)
                .margin({ top: 20 }).padding({ left: 24, right: 24 })
                .onClick(() => { this.doRefresh(); })
            }
            .width('100%').layoutWeight(1)
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          }

          // Data
          if (!this.isLoading && this.loadError.length === 0 && this.balance.length > 0) {
            Scroll() {
              Column() {
                // 余额卡片
                Column() {
                  Row() {
                    Text('⚡ 电费余额').fontSize(14).fontColor(ThemeColors.textSecondary)
                    Blank()
                    Image($r('app.media.ic_public_refresh'))
                      .width(20).height(20)
                      .fillColor('#FF6D00')
                      .onClick(() => { this.doRefresh(); })
                  }.width('100%')
                  Row() {
                    Text(this.balance).fontSize(48).fontWeight(FontWeight.Bold).fontColor('#FF6D00')
                    Text(' kWh').fontSize(18).fontColor(ThemeColors.textSecondary).margin({ left: 4 })
                  }.margin({ top: 8 })
                  Text('电表 ' + this.metID + '  ·  抄读于 ' + this.readDate)
                    .fontSize(12).fontColor('#AAAAAA').margin({ top: 8 })
                }
                .width('100%').padding(20)
                .backgroundColor(ThemeColors.bgCard).borderRadius(16)
                .margin({ left: 16, right: 16, top: 16 })
                .shadow({ radius: 12, color: '#00000008', offsetY: 4 })


                // 每日用电卡片
                Column() {
                  Row() {
                    Text('📊 用电记录').fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                    Blank()
                    Button('查看更多').fontSize(12).fontColor('#FF6D00')
                      .type(ButtonType.Normal).backgroundColor(Color.Transparent).borderRadius(0).padding(0)
                      .onClick(() => { this.showMore = true; })
                  }.width('100%').margin({ bottom: 4 })

                  Divider().color('#F0F0F0').margin({ bottom: 8 })

                  if (this.displayDaily.length > 0) {
                    ForEach(this.displayDaily, (item: DailyItem, index: number) => {
                      Row() {
                        Text(this.fmtDate(item.prevDate.length > 0 ? item.prevDate : '?') + ' → ' + this.fmtDate(item.date)).fontSize(13).fontColor(ThemeColors.textSecondary)
                        Blank()
                        Text(item.use).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
                        Text(' kWh').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 2 })
                      }
                      .width('100%').padding({ top: 10, bottom: 10 })
                      if (index < this.displayDaily.length - 1) {
                        Divider().color('#F5F5F5')
                      }
                    }, (item: DailyItem): string => item.date)
                  } else {
                    Text('暂无用电记录').fontSize(13).fontColor(ThemeColors.textSecondary)
                      .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
                  }
                }
                .width('100%').padding(16)
                .backgroundColor(ThemeColors.bgCard).borderRadius(16)
                .margin({ left: 16, right: 16, top: 12, bottom: 16 })
                .shadow({ radius: 12, color: '#00000008', offsetY: 4 })

                // 水费记录卡片（数据少，全量显示，不折叠）
                if (this.waterMetID.length > 0) {
                  Column() {
                    Text('💧 用水记录').fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
                    Divider().color('#F0F0F0').margin({ top: 8, bottom: 8 })

                    if (this.waterDailyItems.length > 0) {
                      // 表头
                      Row() {
                        Text('读表时间').fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Bold).width('25%')
                        Text('用量').fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Bold).width('20%')
                        Text('本次读数').fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Bold).width('27%')
                        Text('上次读数').fontSize(12).fontColor(ThemeColors.textSecondary).fontWeight(FontWeight.Bold).width('28%')
                      }.width('100%').padding({ bottom: 8 })
                      Divider().color('#F0F0F0')
                      // 数据行
                      ForEach(this.waterDailyItems, (item: DailyItem, index: number) => {
                        Row() {
                          // 四列：读表时间 / 用量 / 本次读数 / 上次读数
                          Text(this.fmtDate(item.date)).fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).width('25%')
                          Text(item.use + ' 吨').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#2196F3').width('20%')
                          Text('本次:' + item.endNum).fontSize(11).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).width('27%')
                          Text('上次:' + item.startNum).fontSize(11).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).width('28%')
                        }
                        .width('100%').padding({ top: 8, bottom: 8 })
                        if (index < this.waterDailyItems.length - 1) {
                          Divider().color('#F5F5F5')
                        }
                      }, (item: DailyItem): string => item.date)
                    } else {
                      Text('暂无用水记录').fontSize(13).fontColor(ThemeColors.textSecondary)
                        .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
                    }
                  }
                  .width('100%').padding(16)
                  .backgroundColor(ThemeColors.bgCard).borderRadius(16)
                  .margin({ left: 16, right: 16, top: 12, bottom: 16 })
                  .shadow({ radius: 12, color: '#00000008', offsetY: 4 })
                }
              }
            }
            .layoutWeight(1)
          }

          // 初始空状态
          if (!this.isLoading && this.loadError.length === 0 && this.balance.length === 0) {
            Column() {
              Text('🔌').fontSize(48)
              Text('正在连接缴费系统...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            }
            .width('100%').layoutWeight(1)
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%').height('100%')
        .backgroundColor(ThemeColors.bgInput)

        // 查看更多弹窗
        if (this.showMore) {
          Stack() {
            Column()
              .width('100%').height('100%')
              .backgroundColor('rgba(0,0,0,0.5)')
              .onClick(() => { this.showMore = false; })
              .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn }))

            Flex({ justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
              Column() {
                Row().width('100%').height(4)
                  .backgroundColor('#FF6D00')
                  .borderRadius({ topLeft: 16, topRight: 16 })

                this.fullReadingsBuilder()
              }
              .width('88%')
              .height('70%')
              .backgroundColor(ThemeColors.bgCard)
              .borderRadius(16)
              .shadow({ radius: 24, color: 'rgba(0,0,0,0.25)', offsetY: 10 })
              .zIndex(2)
              .transition(TransitionEffect.scale({ x: 0.9, y: 0.9 })
                .combine(TransitionEffect.OPACITY)
                .animation({ duration: 300, curve: Curve.EaseOut }))
            }
            .width('100%').height('100%')
          }
          .width('100%').height('100%')
        }
      }
      .width('100%').height('100%')
    }
    .title('水电查询', { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      if (this.showMore) { this.showMore = false; return true; }
      if (this.showMoreWater) { this.showMoreWater = false; return true; }
      return false;
    })
    .backgroundColor(ThemeColors.bgPage)
    .onReady((ctx: NavDestinationContext) => {})
  }
}
