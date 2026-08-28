// SchoolCardService.ets — 校园卡（一卡通）数据服务
// 数据源: v8scan.xidian.edu.cn，认证走 IDS OAuth2（同ehall CAS）
import { HttpUtil } from '../utils/HttpUtil';

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
   * 手动跟随 OAuth2 重定向链（同 Flutter 做法），确保每步携带对应域名的 Cookie
   */
  async ensureOpenId(forceRefresh: boolean = false): Promise<string> {
    if (!forceRefresh && this.isOpenIdValid()) {
      return this.openid;
    }

    this.openid = '';
    this.openidFetchedAt = 0;

    // v8scan OAuth 链: v8scan → xxcapp/uc/api/oauth → xxcapp/uc/wap/login
    //   → xxcapp/a_xidian/cas-login → ids CAS（验证 TGC）→ 原路返回
    // appid/state 是 xxcapp 的独立查询参数，不能编码进 redirect 值
    const redirect1 = encodeURIComponent('https://v8scan.xidian.edu.cn/home/openHomePage');
    const ucOauth = 'https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=' + redirect1 + '&appid=200200923164459783&state=STATE';
    const redirect2 = encodeURIComponent(ucOauth);
    const ucWapLogin = 'https://xxcapp.xidian.edu.cn/uc/wap/login?redirect=' + redirect2;
    const redirect3 = encodeURIComponent(ucWapLogin);
    const casCallback = 'https://xxcapp.xidian.edu.cn/a_xidian/api/cas-login/index?redirect=' + redirect3 + '&from=wap';
    const serviceParam = encodeURIComponent(casCallback);
    const casUrl = 'https://ids.xidian.edu.cn/authserver/login?service=' + serviceParam;

    const resp = await this.http.get(casUrl);
    const html = resp.body || '';

    // 解析 openid
    const match = html.match(/id="openid"[^>]*type="hidden"[^>]*value="([^"]*)"/) ||
                  html.match(/type="hidden"[^>]*id="openid"[^>]*value="([^"]*)"/) ||
                  html.match(/name="openid"[^>]*type="hidden"[^>]*value="([^"]*)"/);
    if (match && match[1].length > 0) {
      this.openid = match[1];
      this.openidFetchedAt = Date.now();
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
      // WebView 注入的 openid 还在有效期内，直接重试同一 openid，
      // 不要回退到 HTTP ensureOpenId（会触发 NETSTACK 跨域 cookie 死胡同）
      if (this.isOpenIdValid()) {
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
      return balance;
    });
  }

  private parseBalanceFromHtml(html: string): string {
    // 策略1：优先找包含「余额」关键字的 li，取其金额（避免命中日期/交易金额等其他数字）
    const liRegex = /<li[^>]*>([\s\S]*?)<\/li>/g;
    let liMatch: RegExpExecArray | null = null;
    let firstMoney: string = '';
    while ((liMatch = liRegex.exec(html)) !== null) {
      const liContent = liMatch[1];
      const moneyMatch = liContent.match(/(\d+\.\d{2})/);
      if (moneyMatch) {
        if (firstMoney.length === 0) {
          firstMoney = moneyMatch[1];
        }
        // 含「余额」关键字的 li 优先返回
        if (liContent.indexOf('余额') >= 0 || liContent.toLowerCase().indexOf('balance') >= 0) {
          return moneyMatch[1];
        }
      }
    }
    // 策略2：无「余额」li 时，返回第一个含金额的 li（比全文匹配更可靠）
    if (firstMoney.length > 0) {
      return firstMoney;
    }
    // 策略3：全文兜底
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
      return records;
    });
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
      return base64;
    });
  }
}
