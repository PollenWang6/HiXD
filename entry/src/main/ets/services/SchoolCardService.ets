// SchoolCardService.ets — 校园卡（一卡通）数据服务
// 数据源: v8scan.xidian.edu.cn，认证走 IDS OAuth2（同ehall CAS）
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';

const TAG = 'SchoolCardService';
const BASE_URL = 'https://v8scan.xidian.edu.cn';

// 消费记录
export interface PaidRecord {
  place: string;   // 商户名
  date: string;    // 日期
  money: string;   // 金额
}

export class SchoolCardService {
  private static instance: SchoolCardService;
  private http: HttpUtil = HttpUtil.getInstance();

  // openid 缓存（5分钟有效）
  private openid: string = '';
  private openidFetchedAt: number = 0;
  private static readonly OPENID_TTL = 5 * 60 * 1000; // 5分钟(ms)

  private constructor() {}

  static getInstance(): SchoolCardService {
    if (!SchoolCardService.instance) {
      SchoolCardService.instance = new SchoolCardService();
    }
    return SchoolCardService.instance;
  }

  // ===== openid 管理 =====

  /** 由外部（WebView OAuth）注入 openid，绕开 NETSTACK 跨域重定向限制 */
  setOpenId(oid: string): void {
    this.openid = oid;
    this.openidFetchedAt = Date.now();
    console.info(TAG, 'setOpenId: injected from WebView, len=' + oid.length);
  }

  private isOpenIdValid(): boolean {
    if (this.openid.length === 0) return false;
    if (this.openidFetchedAt === 0) return false;
    const now = Date.now();
    return (now - this.openidFetchedAt) < SchoolCardService.OPENID_TTL;
  }

  /**
   * 获取校园卡 openid。
   * 手动跟随 OAuth2 重定向链（同 Flutter 做法），确保每步携带对应域名的 Cookie
   */
  async ensureOpenId(forceRefresh: boolean = false): Promise<string> {
    if (!forceRefresh && this.isOpenIdValid()) {
      return this.openid;
    }

    this.openid = '';
    this.openidFetchedAt = 0;

    // NETSTACK 自动跟随重定向时只带原始域名的 cookie。
    // v8scan→ids CAS→v8scan 链中需 ids 的 CASTGC，提前拷贝过去。
    this.http.copyCookiesForDomain('ids.xidian.edu.cn', 'v8scan.xidian.edu.cn');
    this.http.copyCookiesForDomain('.ehall.xidian.edu.cn', 'v8scan.xidian.edu.cn');

    const startUrl = BASE_URL + '/home/openXDOAuth2Page';
    console.info(TAG, 'ensureOpenId: start ' + startUrl);

    const finalResp = await this.followRedirects(startUrl, 8);
    const html = finalResp.body || '';
    console.info(TAG, 'ensureOpenId: status=' + finalResp.statusCode + ' page len=' + html.length);
    console.info(TAG, 'ensureOpenId: HTML preview: ' + html.substring(0, 500));

    // 解析 openid
    const match = html.match(/id="openid"[^>]*type="hidden"[^>]*value="([^"]*)"/) ||
                  html.match(/type="hidden"[^>]*id="openid"[^>]*value="([^"]*)"/) ||
                  html.match(/name="openid"[^>]*type="hidden"[^>]*value="([^"]*)"/);
    if (match && match[1].length > 0) {
      this.openid = match[1];
      this.openidFetchedAt = Date.now();
      console.info(TAG, 'ensureOpenId: got openid, len=' + this.openid.length);
      return this.openid;
    }

    throw new Error('校园卡 openid 获取失败');
  }

  /**
   * 带 openid 重试的执行器
   */
  private async withOpenIdRetry<T>(action: (openid: string) => Promise<T>): Promise<T> {
    const oid = await this.ensureOpenId();
    try {
      return await action(oid);
    } catch (e) {
      console.warn(TAG, 'withOpenIdRetry: first attempt failed: ' + String(e));
      // WebView 注入的 openid 还在有效期内，直接重试同一 openid，
      // 不要回退到 HTTP ensureOpenId（会触发 NETSTACK 跨域 cookie 死胡同）
      if (this.isOpenIdValid()) {
        console.info(TAG, 'withOpenIdRetry: retry with same WebView openid');
        return await action(this.openid);
      }
      const oid2 = await this.ensureOpenId(true);
      return await action(oid2);
    }
  }

  // ===== 余额查询 =====

  /**
   * 查询校园卡余额。
   * GET /myaccount/openMyAccount?openid=xxx → 解析HTML提取余额
   */
  async getBalance(): Promise<string> {
    return this.withOpenIdRetry(async (openid: string) => {
      const url = BASE_URL + '/myaccount/openMyAccount?openid=' + openid;
      console.info(TAG, 'getBalance: GET ' + url.substring(0, 80));

      const resp = await this.http.get(url);
      if (!resp.isOk) {
        throw new Error('余额查询HTTP错误: ' + resp.statusCode);
      }

      const html = resp.body || '';
      // 从 HTML 中解析 <li> 标签内的余额数字
      const balance = this.parseBalanceFromHtml(html);
      if (balance.length === 0) {
        throw new Error('余额解析失败');
      }
      console.info(TAG, 'getBalance: ' + balance);
      return balance;
    });
  }

  private parseBalanceFromHtml(html: string): string {
    // 策略1：找 <li> 中包含 "余额" 或金额格式的文本
    // 尝试正则匹配常见格式
    const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/g;
    let liMatch: RegExpExecArray | null = null;
    while ((liMatch = liRegex.exec(html)) !== null) {
      const liContent = liMatch[1];
      // 查找金额格式: 数字.数字
      const moneyMatch = liContent.match(/(\d+\.\d{2})/);
      if (moneyMatch) {
        return moneyMatch[1];
      }
    }

    // 策略2：直接全文匹配金额
    const moneyMatch = html.match(/(\d+\.\d{2})/);
    return moneyMatch ? moneyMatch[1] : '';
  }

  // ===== 余额查询 =====

  /**
   * 查询消费记录。
   * POST /selftrade/queryCardSelfTradeList?openid=xxx
   * Body: { beginDate, endDate, tradeType: "-1", openid }
   * Response: { resultData: [{ mername, txdate, txamt }] }
   */
  async getPaidRecords(beginDate: string, endDate: string): Promise<PaidRecord[]> {
    return this.withOpenIdRetry(async (openid: string) => {
      const url = BASE_URL + '/selftrade/queryCardSelfTradeList?openid=' + openid;
      console.info(TAG, 'getPaidRecords: POST ' + url.substring(0, 80));

      const body = JSON.stringify({
        beginDate: beginDate,
        endDate: endDate,
        tradeType: '-1',
        openid: openid,
      });

      const resp = await this.http.postRaw(url, body, 'application/json; charset=utf-8');
      if (!resp.isOk) {
        throw new Error('消费记录HTTP错误: ' + resp.statusCode);
      }

      const data = resp.json<object>();
      const resultData = (data as Record<string, Object>)['resultData'];
      if (!resultData) {
        throw new Error('消费记录解析失败: 无resultData');
      }

      const items = resultData as Array<Record<string, string>>;
      const records: PaidRecord[] = [];
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        records.push({
          place: item['mername'] || '',
          date: item['txdate'] || '',
          money: item['txamt'] || '',
        });
      }
      console.info(TAG, 'getPaidRecords: got ' + records.length + ' records');
      return records;
    });
  }

  // ===== 重定向跟随 =====

  /**
   * 手动跟随 HTTP 重定向链（getNoRedirect + headersReceive 捕获 Set-Cookie）
   * 与 EhallService.followRedirects 同理
   */
  private async followRedirects(startUrl: string, maxSteps: number = 10): Promise<HttpResponse> {
    let currentUrl = startUrl;
    for (let i = 0; i < maxSteps; i++) {
      const resp = await this.http.getNoRedirect(currentUrl);
      if (!resp.isRedirect || !resp.location) {
        console.info(TAG, 'followRedirects: [' + i + '] final status=' + resp.statusCode);
        return resp;
      }
      // 处理相对 URL
      let location = resp.location;
      if (location.startsWith('/')) {
        const idx = currentUrl.indexOf('/', 8); // 跳过 https://
        const base = idx > 0 ? currentUrl.substring(0, idx) : currentUrl;
        location = base + location;
      }
      console.info(TAG, 'followRedirects: [' + i + '] 302 → ' + location.substring(0, 80));
      currentUrl = location;
    }
    throw new Error('校园卡重定向链过长(>' + maxSteps + '步)');
  }

  // ===== 付款码 =====

  /**
   * 获取付款二维码（base64 PNG）。
   * 参照 Flutter getQRCode() 实现
   */
  async getQRCodeBase64(): Promise<string> {
    return this.withOpenIdRetry(async (openid: string) => {
      const homeUrl = BASE_URL + '/home/openHomePage?openid=' + openid;
      const homeResp = await this.http.get(homeUrl);
      const homeHtml = homeResp.body || '';
      const aMatch = homeHtml.match(/\/virtualcard\/openVirtualcard[^"]*id=([^"&]+)/);
      const cardId = aMatch ? aMatch[1] : '';
      if (!cardId) throw new Error('虚拟卡 id 未找到');

      const qrUrl = BASE_URL + '/virtualcard/openVirtualcard?openid=' + openid +
        '&displayflag=1&id=' + cardId;
      const qrResp = await this.http.get(qrUrl);
      const qrHtml = qrResp.body || '';
      const imgMatch = qrHtml.match(/id="qrcode"[^>]*src="(data:image\/png;base64,[^"]+)"/);
      if (!imgMatch) throw new Error('付款码图片未找到');
      let base64 = imgMatch[1];
      base64 = base64.replace('data:image/png;base64,', '').replace(/\n/g, '');
      console.info(TAG, 'getQRCodeBase64: got base64 len=' + base64.length);
      return base64;
    });
  }
}
