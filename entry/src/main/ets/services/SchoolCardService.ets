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

  private isOpenIdValid(): boolean {
    if (this.openid.length === 0) return false;
    if (this.openidFetchedAt === 0) return false;
    const now = Date.now();
    return (now - this.openidFetchedAt) < SchoolCardService.OPENID_TTL;
  }

  /**
   * 获取校园卡 openid。
   * 流程：GET /home/openXDOAuth2Page → IDS OAuth2 重定向链 → 最终页面解析隐藏input
   * 利用 ehall 同源 CAS cookie (MOD_AUTH_CAS) 走通重定向链
   */
  async ensureOpenId(forceRefresh: boolean = false): Promise<string> {
    if (!forceRefresh && this.isOpenIdValid()) {
      return this.openid;
    }

    this.openid = '';
    this.openidFetchedAt = 0;

    // 用普通 GET 让 NETSTACK 自动跟随 IDS OAuth2 重定向链
    const startUrl = BASE_URL + '/home/openXDOAuth2Page';
    console.error(TAG, 'ensureOpenId: start GET ' + startUrl);

    const resp = await this.http.get(startUrl);
    const html = resp.body || '';
    console.error(TAG, 'ensureOpenId: status=' + resp.statusCode + ' page len=' + html.length);
    // 调试：打印HTML前1000字符
    console.error(TAG, 'ensureOpenId: HTML preview: ' + html.substring(0, 1000));

    // 解析 <input id="openid" type="hidden" value="xxx">
    const match = html.match(/id="openid"[^>]*type="hidden"[^>]*value="([^"]*)"/) ||
                  html.match(/type="hidden"[^>]*id="openid"[^>]*value="([^"]*)"/) ||
                  html.match(/name="openid"[^>]*type="hidden"[^>]*value="([^"]*)"/);
    if (match && match[1].length > 0) {
      this.openid = match[1];
      this.openidFetchedAt = Date.now();
      console.error(TAG, 'ensureOpenId: got openid, len=' + this.openid.length);
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
      console.error(TAG, 'withOpenIdRetry: first attempt failed, refreshing openid');
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
      console.error(TAG, 'getBalance: GET ' + url.substring(0, 80));

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
      console.error(TAG, 'getBalance: ' + balance);
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

  // ===== 消费记录查询 =====

  /**
   * 查询消费记录。
   * POST /selftrade/queryCardSelfTradeList?openid=xxx
   * Body: { beginDate, endDate, tradeType: "-1", openid }
   * Response: { resultData: [{ mername, txdate, txamt }] }
   */
  async getPaidRecords(beginDate: string, endDate: string): Promise<PaidRecord[]> {
    return this.withOpenIdRetry(async (openid: string) => {
      const url = BASE_URL + '/selftrade/queryCardSelfTradeList?openid=' + openid;
      console.error(TAG, 'getPaidRecords: POST ' + url.substring(0, 80));

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
      console.error(TAG, 'getPaidRecords: got ' + records.length + ' records');
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
        console.error(TAG, 'followRedirects: [' + i + '] final status=' + resp.statusCode);
        return resp;
      }
      // 处理相对 URL
      let location = resp.location;
      if (location.startsWith('/')) {
        const idx = currentUrl.indexOf('/', 8); // 跳过 https://
        const base = idx > 0 ? currentUrl.substring(0, idx) : currentUrl;
        location = base + location;
      }
      console.error(TAG, 'followRedirects: [' + i + '] 302 → ' + location.substring(0, 80));
      currentUrl = location;
    }
    throw new Error('校园卡重定向链过长(>' + maxSteps + '步)');
  }
}
