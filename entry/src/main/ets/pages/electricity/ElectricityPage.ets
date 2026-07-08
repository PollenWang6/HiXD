import { AccentColors } from '../../utils/AccentColors';
// ElectricityPage.ets — 电费查询（HTTP + cryptoFramework AES，WebView 仅做 SSO 拿 code）
import { ThemeColors } from '../../utils/ThemeColors';
import { webview } from '@kit.ArkWeb';
import web_webview from '@ohos.web.webview';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { HttpUtil } from '../../utils/HttpUtil';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { CasLoginService } from '../../services/CasLoginService';
import { promptAction } from '@kit.ArkUI';
import { SegmentTab } from '../../components/SegmentTab';

const TAG: string = 'ElectricityPage';

const SSO_ENTRY: string =
  'https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=https://ignypt.xidian.edu.cn/revenueH5/login?opcode=MPAY&appid=200260318155520600&state=12312312312312&qrcode=0';

const AES_KEY: string = '1234567812345678';

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

interface CodeReq { CODE: string }
interface LoginReq { UserID: string; Pwd: string; IsCehckPwd: string; NodeID: string }
interface NodeReq { NodeID: string }
interface MeterReq { MetID: string; ReadTimeS: string; ReadTimeE: string; ReadNum: string }
interface PostBody { content: string }
interface SigReq { data: string; access_token: string; OpCode: string; RequestID: string }
interface TimePreset { label: string; days: number }

const TIME_PRESETS: TimePreset[] = [
  { label: '近7天', days: 7 },
  { label: '近30天', days: 30 },
  { label: '近90天', days: 90 }
];

function strToU8(s: string): Uint8Array {
  const buf: Array<number> = [];
  for (let i: number = 0; i < s.length; i++) {
    buf.push(s.charCodeAt(i) & 0xFF);
  }
  return new Uint8Array(buf);
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
  @State webViewSrc: string = '';
  // 查询与Tab
  @State activePreset: number = 30;
  @State customStartStr: string = '';
  @State customEndStr: string = '';
  @State customQuerying: boolean = false;
  @State activeTab: number = 0;

  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private isSilent: boolean = false;
  private http: HttpUtil = HttpUtil.getInstance();
  private ssoDone: boolean = false;
  private cachedApiHeaders: Record<string, string> = {};
  private cachedMetID: string = '';


  async aboutToAppear(): Promise<void> {
    await CasLoginService.getInstance().syncCookiesToWebView();
    this.webViewSrc = SSO_ENTRY;
    this.customStartStr = this.dayShift(30);
    this.customEndStr = this.dayShift(0);
    const silent: boolean = AppStorage.Get('electricity_silent') as boolean;
    if (silent === true) {
      AppStorage.Set('electricity_silent', false);
      this.isSilent = true;
      return;
    }
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

  private dayShift(n: number): string {
    const d: number = Date.now() - n * 86400000;
    const dt: Date = new Date(d);
    const y: string = String(dt.getFullYear());
    const m: string = String(dt.getMonth() + 1).padStart(2, '0');
    const day: string = String(dt.getDate()).padStart(2, '0');
    return y + '-' + m + '-' + day;
  }

  private async fetchData(code: string): Promise<void> {
    if (!this.isSilent) this.isLoading = true;
    this.loadError = '';
    const IG_HEADERS: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36'
    };
    try {
      // Step 1
      const sigUrl = 'https://ignypt.xidian.edu.cn/baseNew/api/User/GetSignature';
      const emptySigBody: SigReq = { data: '', access_token: '', OpCode: 'MPAY', RequestID: '' };
      const sigResp = await this.http.post(sigUrl, emptySigBody, IG_HEADERS);
      if (!sigResp.isOk) throw new Error('GetSignature failed: ' + sigResp.statusCode);
      const sigJson: object = JSON.parse(sigResp.body) as object;
      const sigData: Record<string, object> = (sigJson as Record<string, object>)['data'] as Record<string, object>;
      const timestamp: string = String(sigData['timestamp']);
      const signature: string = String(sigData['signature']);
      const apiHeaders: Record<string, string> = {
        'timestamp': timestamp, 'signature': signature, 'OpCode': 'MPAY', 'OrgId': '', 'RequestID': ''
      };
      this.cachedApiHeaders = {
        'timestamp': timestamp, 'signature': signature, 'OpCode': 'MPAY', 'OrgId': '', 'RequestID': ''
      };
      // Step 2
      const step2Req: CodeReq = { CODE: code };
      const enc2: string = await this.aesEncrypt(JSON.stringify(step2Req));
      const uInfoUrl: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/OauthGetUserInfo?content=' + encodeURIComponent(enc2);
      const uInfoResp = await this.http.get(uInfoUrl, apiHeaders);
      if (!uInfoResp.isOk) throw new Error('OauthGetUserInfo failed');
      // Step 3
      const userId: string = PreferenceUtil.getString('ids_account') || PreferenceUtil.getString('login_username') || '';
      const step3Req: LoginReq = { UserID: userId, Pwd: '', IsCehckPwd: '1', NodeID: '' };
      const enc3: string = await this.aesEncrypt(JSON.stringify(step3Req));
      const loginBody: PostBody = { content: enc3 };
      const loginResp = await this.http.post('https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/H5UserIDLogIn', loginBody, apiHeaders);
      if (!loginResp.isOk) throw new Error('H5UserIDLogIn failed');
      const loginJson: object = JSON.parse(loginResp.body) as object;
      const resData: object[] = (loginJson as Record<string, object[]>)['ResData'] as object[];
      const nodeID: string = String((resData[0] as Record<string, object>)['NodeID']);
      // Step 4
      const step4Req: NodeReq = { NodeID: nodeID };
      const enc4: string = await this.aesEncrypt(JSON.stringify(step4Req));
      const meterUrl: string = 'https://ignypt.xidian.edu.cn/estManage/api/wechat/v2/H5QueryMeterList?content=' + encodeURIComponent(enc4);
      const meterResp = await this.http.get(meterUrl, apiHeaders);
      if (!meterResp.isOk) throw new Error('H5QueryMeterList failed');
      const meterJson: object = JSON.parse(meterResp.body) as object;
      const md: object = (meterJson as Record<string, object>)['ResData'] as object;
      const rows: object[] = (md as Record<string, object[]>)['rows'] as object[];
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
      this.cachedMetID = metID;
      // Step 5
      const daily: DailyItem[] = [];
      let waterDaily: DailyItem[] = [];
      try {
        const step5Req: MeterReq = { MetID: metID, ReadTimeS: this.dayShift(30), ReadTimeE: this.dayShift(0), ReadNum: '' };
        const enc5: string = await this.aesEncrypt(JSON.stringify(step5Req));
        const readUrl: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/GetMetRead?content=' + encodeURIComponent(enc5);
        const readResp = await this.http.get(readUrl, apiHeaders);
        if (readResp.isOk) {
          const readJson: object = JSON.parse(readResp.body) as object;
          const rd: object = (readJson as Record<string, object>)['ResData'] as object;
          const rdRows: object[] = (rd as Record<string, object[]>)['rows'] as object[] || [] as object[];
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
        }
        if (hasWater) {
          const wReq: MeterReq = { MetID: waterMetID, ReadTimeS: this.dayShift(365), ReadTimeE: this.dayShift(0), ReadNum: '' };
          const wEnc: string = await this.aesEncrypt(JSON.stringify(wReq));
          const wUrl: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/GetMetRead?content=' + encodeURIComponent(wEnc);
          const wResp = await this.http.get(wUrl, apiHeaders);
          if (wResp.isOk) {
            const wJson: object = JSON.parse(wResp.body) as object;
            const wrd: object = (wJson as Record<string, object>)['ResData'] as object;
            const wRows: object[] = (wrd as Record<string, object[]>)['rows'] as object[] || [] as object[];
            for (let i: number = 0; i < wRows.length; i++) {
              const r: Record<string, object> = wRows[i] as Record<string, object>;
              const date: string = String(r['ReadTime']).substring(0, 10);
              const startNum: string = Number(r['StartNum']).toFixed(2);
              const endNum: string = Number(r['EndNum']).toFixed(2);
              const use: string = Number(r['ReadNum']).toFixed(2);
              waterDaily.push({ date: date, prevDate: '', use: use, startNum: startNum, endNum: endNum });
            }
          }
        }
      } catch (e5) {
      }
      const cache: ElecCache = { remain: remain, metID: metID, nodeID: nodeID, date: readDate, daily: daily, error: '', waterRemain: waterRemain, waterMetID: waterMetID, waterDate: waterDate, waterDaily: waterDaily };
      AppStorage.setOrCreate('electricity_cache', JSON.stringify(cache));
      PreferenceUtil.putString('electricity_cache_v2', JSON.stringify(cache));
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
      this.activePreset = 30;
      this.isLoading = false;
      if (this.isSilent) {
        this.isSilent = false;
        this.pageInfo.pop();
      }
    } catch (e) {
      const errMsg: string = e instanceof Error ? (e as Error).message : JSON.stringify(e);
      this.loadError = errMsg;
      this.isLoading = false;
      if (this.isSilent) {
        this.isSilent = false;
        this.pageInfo.pop();
      }
    }
  }

  private async queryStep5(startStr: string, endStr: string): Promise<void> {
    if (this.cachedApiHeaders['timestamp'] === undefined || this.cachedMetID.length === 0) {
      promptAction.showToast({ message: '请等待数据加载完成', duration: 2000 });
      return;
    }
    this.customQuerying = true;
    try {
      const req: MeterReq = { MetID: this.cachedMetID, ReadTimeS: startStr, ReadTimeE: endStr, ReadNum: '' };
      const enc: string = await this.aesEncrypt(JSON.stringify(req));
      const url: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/GetMetRead?content=' + encodeURIComponent(enc);
      const resp = await this.http.get(url, this.cachedApiHeaders);
      if (!resp.isOk) {
        promptAction.showToast({ message: '查询失败', duration: 2000 });
        this.customQuerying = false;
        return;
      }
      const json: object = JSON.parse(resp.body) as object;
      const rd: object = (json as Record<string, object>)['ResData'] as object;
      const rows: object[] = (rd as Record<string, object[]>)['rows'] as object[] || [] as object[];
      const items: DailyItem[] = [];
      for (let i: number = 0; i < rows.length; i++) {
        const r: Record<string, object> = rows[i] as Record<string, object>;
        const date: string = String(r['ReadTime']).substring(0, 10);
        const startNum: string = Number(r['StartNum']).toFixed(2);
        const endNum: string = Number(r['EndNum']).toFixed(2);
        const use: string = Number(r['ReadNum']).toFixed(2);
        if (i + 1 < rows.length) {
          const nr: Record<string, object> = rows[i + 1] as Record<string, object>;
          const prevDate: string = String(nr['ReadTime']).substring(0, 10);
          items.push({ date: date, prevDate: prevDate, use: use, startNum: startNum, endNum: endNum });
        }
      }
      this.dailyItems = items;
      this.displayDaily = items.slice(0, 7);
    } catch (e) {
      promptAction.showToast({ message: '查询失败', duration: 2000 });
    }
    this.customQuerying = false;
  }

  private selectPreset(days: number): void {
    if (days === -1) { this.activePreset = -1; return; }
    this.activePreset = days;
    const startStr: string = this.dayShift(days);
    const endStr: string = this.dayShift(0);
    this.queryStep5(startStr, endStr);
  }

  private doCustomQuery(): void {
    if (this.customStartStr.length === 0 || this.customEndStr.length === 0) {
      promptAction.showToast({ message: '请选择开始和结束日期', duration: 2000 });
      return;
    }
    if (this.customStartStr > this.customEndStr) {
      promptAction.showToast({ message: '开始日期不能晚于结束日期', duration: 2000 });
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
    this.ssoDone = false;
    AppStorage.setOrCreate('electricity_cache', '');
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
      .height(40).width(40).onClick(() => { this.pageInfo.pop(); })
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
          .onClick(() => { this.doRefresh(); })
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
      colors: this.themeIsDark ? [['#4A2800', 0.0], ['#E65100', 1.0]] : [['#FF8F00', 0.0], ['#E65100', 1.0]]
    })
    .shadow({ radius: 16, color: '#E6510020', offsetY: 6 }).margin({ left: 16, right: 16, top: 16 })
  }

  @Builder
  buildPresetChip(label: string, days: number) {
    Text(label).fontSize(12)
      .fontColor(this.activePreset === days ? this.accentColor : ThemeColors.textSecondary)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 }).borderRadius(10)
      .border({ width: 0.5, color: this.activePreset === days ? this.accentColor : ThemeColors.border })
      .backgroundColor(this.activePreset === days ? (this.accentColor + '18') : Color.Transparent)
      .onClick(() => { this.selectPreset(days); })
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
          Text(this.activePreset === -1 ? this.customStartStr : this.dayShift(this.activePreset))
            .fontSize(13).fontColor(ThemeColors.textPrimary)
        }.padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(6).backgroundColor(ThemeColors.bgPage)
        .onClick(() => { this.activePreset = -1; this.showStartDatePicker(); })

        Text('~').fontSize(13).fontColor(ThemeColors.textHint)
        Text('止').fontSize(13).fontColor(ThemeColors.textHint)
        Row() {
          Text(this.activePreset === -1 ? this.customEndStr : this.dayShift(0))
            .fontSize(13).fontColor(ThemeColors.textPrimary)
        }.padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(6).backgroundColor(ThemeColors.bgPage)
        .onClick(() => { this.activePreset = -1; this.showEndDatePicker(); })

        if (this.activePreset === -1) {
          Button('查询').fontSize(13).height(32).backgroundColor(this.accentColor).fontColor('#FFFFFF').borderRadius(6)
            .padding({ left: 14, right: 14 }).onClick(() => { this.doCustomQuery(); })
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
          Text('合计 ' + this.totalUsage() + ' kWh').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#FF6D00')
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
                Text(item.use + ' kWh').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#FF6D00')
              }.width('100%').padding({ left: 18, right: 18, top: 11, bottom: 11 })
            }
          }, (item: DailyItem): string => item.date)
        }
        .layoutWeight(1).divider({ strokeWidth: 0.5, color: '#F5F5F5', startMargin: 18, endMargin: 18 })
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
                Text(item.use + ' 吨').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#2196F3').width('20%')
                Text('本次:' + item.endNum).fontSize(11).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).width('27%')
                Text('上次:' + item.startNum).fontSize(11).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary).width('28%')
              }.width('100%').padding({ top: 8, bottom: 8, left: 18, right: 18 })
            }
          }, (item: DailyItem): string => item.date)
        }
        .layoutWeight(1).divider({ strokeWidth: 0.5, color: '#F5F5F5', startMargin: 18, endMargin: 18 })
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
      Stack() {
        Web({ src: this.webViewSrc, controller: this.webController })
          .width('100%').height('100%')
          .javaScriptAccess(true).domStorageAccess(true)
          .onPageEnd((event) => {
            if (event && event.url && !this.ssoDone) {
              const code: string = this.extractCode(event.url);
              if (code.length > 0) {
                this.ssoDone = true;
                this.fetchData(code);
              }
            }
          })
          .onErrorReceive((event) => {
            if (event) {
              this.loadError = '加载失败: ' + event.error.getErrorInfo();
              this.isLoading = false;
            }
          })

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
              Button('重试').fontSize(14).height(36).backgroundColor('#FF6D00').fontColor('#FFFFFF').borderRadius(20)
                .margin({ top: 20 }).padding({ left: 24, right: 24 }).onClick(() => { this.doRefresh(); })
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
      .width('100%').height('100%')
    }
    .title({ builder: this.buildWhiteTitle('水电查询'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed(() => { return false; })
    .backgroundColor(ThemeColors.bgPage)
    .onReady((ctx: NavDestinationContext) => {})
  }
}
