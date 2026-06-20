// SchoolnetService.ets — 校园网服务（流量概览 + 在线设备 + ZFW详细账单）
// 对齐 Flutter: traintime_pda/lib/repository/schoolnet_session.dart
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

const TAG = 'SchoolnetService';
const ZFW_BASE = 'https://zfw.xidian.edu.cn';

// ===== 数据模型 =====

export interface ZfwLoginState {
  csrf: string;
  rsaKey: string;
  captchaBase64: string;
}

export interface ZfwUsageData {
  usedFlow: string;     // 已用流量
  remainFlow: string;   // 剩余流量
  settleDate: string;   // 结算日期
  ipList: ZfwIpEntry[]; // 在线设备列表
}

export interface ZfwIpEntry {
  ip: string;
  onlineTime: string;
  usedFlow: string;
}

export interface ZfwDetailEntry {
  startTime: string;
  endTime: string;
  ip: string;
  totalFlow: string;
  duration: string;
  cost: string;
}

export interface ZfwDetailSummary {
  flow: string;
  duration: string;
  cost: string;
}

interface ZfwDetailResult {
  entries: ZfwDetailEntry[];
  totalPages: number;
  summary: ZfwDetailSummary;
}

interface ZfwLoginResult {
  csrf: string;
  rsaKey: string;
}

interface ZfwValidateResult {
  success: boolean;
  message: string;
}

// ===== 服务 =====

export class SchoolnetService {
  private static instance: SchoolnetService;
  private http: HttpUtil = HttpUtil.getInstance();
  private base64Helper: util.Base64Helper = new util.Base64Helper();

  /** 清除 ZFW 域名 cookie（公开接口，供 SchoolNetPage 调用） */
  async clearZfwCookies(): Promise<void> {
    await this.http.clearCookies('zfw.xidian.edu.cn');
  }

  private constructor() {}

  static getInstance(): SchoolnetService {
    if (!SchoolnetService.instance) SchoolnetService.instance = new SchoolnetService();
    return SchoolnetService.instance;
  }

  // ===== 在线状态查询（w.xidian.edu.cn，无需登录） =====

  async getCurrentOnlineInfo(): Promise<Record<string, string | number>> {
    const resp: HttpResponse = await this.http.getWithQuery(
      'https://w.xidian.edu.cn/cgi-bin/rad_user_info',
      { 'callback': 'jsonp', '_': Date.now().toString() }
    );
    let raw: string = resp.body;
    let info: Record<string, string | number> = {};

    if (raw.charCodeAt(0) === 0xFEFF || raw.startsWith('\uFEFF')) {
      raw = raw.substring(1);
    }
    raw = raw.replace(/[\r\n]+$/, '');

    // 尝试 JSONP 解析
    const jsonpRe: RegExp = /^jsonp\d*\((.+)\)$/s;
    const jsonpMatch: RegExpExecArray | null = jsonpRe.exec(raw);
    if (jsonpMatch) {
      try {
        info = JSON.parse(jsonpMatch[1]) as Record<string, string | number>;
      } catch (_e) {
        // fallback to CSV
      }
    }

    // JSONP 失败 → CSV 解析
    if (Object.keys(info).length === 0) {
      const parts: string[] = raw.split(',');
      if (parts.length >= 10) {
        info['user_name'] = parts[0].trim();
        info['start_time'] = parseInt(parts[1].trim()) || 0;
        info['last_acct_time'] = parseInt(parts[2].trim()) || 0;
        info['user_ip'] = parts[8].trim();
        info['sum_flow'] = parseFloat(parts[6].trim()) || 0;
        info['remain_flow'] = parseFloat(parts[7].trim()) || 0;
        info['is_online'] = parts[9]?.trim() === '0' ? 1 : 0;
      }
    }

    // 字段名统一
    if (!info['sum_flow'] && info['sum_bytes']) {
      info['sum_flow'] = parseFloat(String(info['sum_bytes'])) || 0;
    }
    if (!info['remain_flow'] && info['remain_bytes']) {
      info['remain_flow'] = parseFloat(String(info['remain_bytes'])) || 0;
    }
    if (typeof info['sum_flow'] === 'string') {
      info['sum_flow'] = parseFloat(String(info['sum_flow'])) || 0;
    }
    if (typeof info['remain_flow'] === 'string') {
      info['remain_flow'] = parseFloat(String(info['remain_flow'])) || 0;
    }
    if (info['online_ip'] && !info['user_ip']) {
      info['user_ip'] = String(info['online_ip']);
    }
    if (info['add_time'] && !info['add_time_ts']) {
      info['add_time_ts'] = parseInt(String(info['add_time'])) || 0;
    }
    if (info['bytes_in'] && !info['v4_bytes_in']) {
      info['v4_bytes_in'] = parseFloat(String(info['bytes_in'])) || 0;
    }
    if (!info['start_time'] && info['sum_seconds']) {
      info['start_time'] = parseInt(String(info['sum_seconds'])) || 0;
    }
    if (!info['start_time'] && info['acct_start_time']) {
      info['start_time'] = parseInt(String(info['acct_start_time'])) || 0;
    }

    return info;
  }

  // ===== ZFW 登录与数据抓取 =====
  // 对齐 Flutter schoolnet_session.dart 流程：
  // 1. GET /home → 已登录直接解析，302/跳转→未登录
  // 2. GET /login → 提取 csrf + RSA public key
  // 3. GET /site/captcha?refresh=1 → 刷新验证码
  // 4. GET /site/captcha → 获取验证码图片
  // 5. POST /site/validate-user → 验证用户（pre-login）
  // 6. POST / → 完成登录（NETSTACK POST 302 不跟随，需手动 GET /home）
  // 7. GET /home → 解析流量概览
  // 8. GET /log/detail → 解析上网明细

  /**
   * 尝试直接访问 ZFW 首页
   * 对齐 Flutter: _dio.get("/home")，如果 isRedirect 则未登录
   */
  async tryFetchZfwHome(): Promise<ZfwUsageData | null> {
    // 检查 cookie 大小，如果异常大则清除（防止之前 bug 积累的超大 cookie）
    const cookieStr: string = this.http.getCookiesForDomain('zfw.xidian.edu.cn');
    if (cookieStr.length > 2000) {
      console.error(TAG, 'ZFW cookie too large (' + cookieStr.length + '), clearing');
      await this.http.clearCookies('zfw.xidian.edu.cn');
      return null;
    }

    const resp: HttpResponse = await this.http.get(ZFW_BASE + '/home');

    // 被重定向到 /login → 未登录
    if (resp.body.indexOf('LoginForm') >= 0) {
      console.info(TAG, 'ZFW not logged in (login form found)');
      return null;
    }

    // 已登录 → 解析首页
    if (resp.body.indexOf('自服务在线中') >= 0) {
      console.info(TAG, 'ZFW already logged in');
      return this.parseZfwHome(resp.body);
    }

    console.warn(TAG, 'ZFW home unknown state, bodyLen=' + resp.body.length);
    return null;
  }

  /**
   * 获取登录页，提取 CSRF token 和 RSA 公钥
   * 对齐 Flutter: GET /login → 解析 <input> 标签
   */
  async startZfwLogin(): Promise<ZfwLoginResult> {
    // 清除旧 session，开始新的登录流程
    await this.http.clearCookies('zfw.xidian.edu.cn');
    // 调试：打印 clear 后 cookie 状态
    const afterClear: string = this.http.getCookiesForDomain('zfw.xidian.edu.cn');
    console.error(TAG + ' after-clear cookieLen=' + afterClear.length + ' cookies=' + afterClear.substring(0, 200));

    const resp: HttpResponse = await this.http.get(ZFW_BASE + '/login');
    const body: string = resp.body;
    // 调试：打印 set-cookie 响应头
    const scHeader: string = resp.headers['set-cookie'] || resp.headers['Set-Cookie'] || 'NONE';
    console.error(TAG + ' login-page set-cookie=' + scHeader.substring(0, 500));

    // 遍历 <input> 标签提取 csrf 和 RSA public key
    let csrf: string = '';
    let rsaKey: string = '';
    const inputRe: RegExp = /<input[^>]*>/gi;
    let inputMatch: RegExpExecArray | null;
    while ((inputMatch = inputRe.exec(body)) !== null) {
      const inputTag: string = inputMatch[0];
      // CSRF: name 属性含 "csrf"
      if (csrf.length === 0 && inputTag.indexOf('csrf') >= 0) {
        const valRe: RegExp = /value=["']([^"']*)["']/i;
        const valMatch: RegExpExecArray | null = valRe.exec(inputTag);
        if (valMatch) {
          csrf = valMatch[1];
        }
      }
      // RSA public key: id 属性含 "public"
      if (rsaKey.length === 0 && inputTag.indexOf('public') >= 0) {
        const valRe2: RegExp = /value=["']([^"']*)["']/i;
        const valMatch: RegExpExecArray | null = valRe2.exec(inputTag);
        if (valMatch) {
          rsaKey = valMatch[1];
        }
      }
      // 都找到了提前退出
      if (csrf.length > 0 && rsaKey.length > 0) break;
    }

    console.info(TAG, 'ZFW login page: csrf=' + (csrf.length > 0 ? csrf.substring(0, 10) + '...' : 'MISSING') +
      ', key=' + (rsaKey.length > 0 ? rsaKey.substring(0, 20) + '...' : 'MISSING') +
      ', bodyLen=' + body.length);
    // 调试：打印 GET /login 后拿到的 cookie
    const loginCookies: string = this.http.getCookiesForDomain('zfw.xidian.edu.cn');
    console.error(TAG + ' after-login cookies=' + loginCookies.substring(0, 300));

    if (csrf.length === 0 || rsaKey.length === 0) {
      throw new Error('ZFW login page missing csrf or RSA key');
    }

    return { csrf: csrf, rsaKey: rsaKey };
  }

  /**
   * 获取验证码图片（base64 PNG）
   * 对齐 Flutter: refresh → get bytes
   */
  async getZfwCaptcha(): Promise<string> {
    // 先刷新验证码
    await this.http.getWithQuery(
      ZFW_BASE + '/site/captcha',
      { 'refresh': '1', '_': Date.now().toString() }
    );
    // 再获取图片二进制
    const buffer: ArrayBuffer = await this.http.getArrayBuffer(
      ZFW_BASE + '/site/captcha?_=' + Date.now().toString()
    );
    // ArrayBuffer → base64
    const bytes: Uint8Array = new Uint8Array(buffer);
    const encoded: string = this.base64Helper.encodeToStringSync(bytes);
    console.info(TAG, 'ZFW captcha fetched, base64 length=' + encoded.length);
    return 'data:image/png;base64,' + encoded;
  }

  /**
   * 验证用户（pre-login）
   * 对齐 Flutter: POST /site/validate-user
   */
  async validateZfwUser(
    username: string,
    encryptedPwd: string,
    verifyCode: string,
    csrf: string
  ): Promise<ZfwValidateResult> {
    const data: Record<string, string> = {};
    data['LoginForm[username]'] = username;
    data['LoginForm[password]'] = encryptedPwd;
    data['LoginForm[verifyCode]'] = verifyCode;
    const headers: Record<string, string> = {};
    headers['X-CSRF-Token'] = csrf;
    headers['X-Requested-With'] = 'XMLHttpRequest';
    headers['Accept'] = '*/*';

    // 调试：打印 CSRF 和 cookie 状态
    const cookieDebug: string = this.http.getCookiesForDomain('zfw.xidian.edu.cn');
    console.error(TAG + ' validate-user csrf=' + csrf.substring(0, 10) + '... cookieLen=' + cookieDebug.length);
    console.error(TAG + ' validate-user cookies=' + cookieDebug.substring(0, 300));

    const resp: HttpResponse = await this.http.postForm(
      ZFW_BASE + '/site/validate-user', data, headers
    );

    console.error(TAG + ' validate-user resp=' + resp.body.substring(0, 200));
    const parsed: Record<string, string | boolean> = JSON.parse(resp.body) as Record<string, string | boolean>;
    return {
      success: parsed['success'] === true,
      message: String(parsed['message'] || '')
    };
  }

  /**
   * 完成最终登录
   * 对齐 Flutter: POST / → 302 → _getNetworkUsage()
   * NETSTACK POST 302 不跟随，需手动 GET /home
   */
  async completeZfwLogin(
    username: string,
    encryptedPwd: string,
    verifyCode: string,
    csrf: string
  ): Promise<boolean> {
    const data: Record<string, string> = {};
    data['_csrf-8800'] = csrf;
    data['LoginForm[username]'] = username;
    data['LoginForm[password]'] = encryptedPwd;
    data['LoginForm[smsCode]'] = '';
    data['LoginForm[verifyCode]'] = verifyCode;
    const headers: Record<string, string> = {};
    headers['X-CSRF-Token'] = csrf;
    headers['X-Requested-With'] = 'XMLHttpRequest';
    headers['Accept'] = '*/*';

    await this.http.postForm(ZFW_BASE + '/', data, headers);

    // Flutter: POST / 返回 302 后自动跟随到 /home
    // NETSTACK: POST 302 不跟随，body 为空，需手动 GET /home
    const homeResp: HttpResponse = await this.http.get(ZFW_BASE + '/home');
    const ok: boolean = homeResp.body.indexOf('自服务在线中') >= 0;
    console.error(TAG + ' completeLogin homeBodyLen=' + homeResp.body.length + ' ok=' + ok);
    return ok;
  }

  /**
   * 获取 ZFW 使用概览数据（登录后调用）
   * 对齐 Flutter: _getNetworkUsage()
   */
  async getZfwUsage(): Promise<ZfwUsageData> {
    const resp: HttpResponse = await this.http.get(ZFW_BASE + '/home');
    return this.parseZfwHome(resp.body);
  }

  /**
   * 获取上网明细（分页）
   */
  async getZfwDetailLog(startTime: string, endTime: string, page: number = 1): Promise<ZfwDetailResult> {
    const url: string = ZFW_BASE + '/log/detail?page=' + page +
      '&LogSearchForm%5Bstart_time%5D=' + encodeURIComponent(startTime) +
      '&LogSearchForm%5Bend_time%5D=' + encodeURIComponent(endTime);
    const resp: HttpResponse = await this.http.get(url);
    return this.parseZfwDetail(resp.body);
  }

  // ===== HTML 解析 =====

  /**
   * 解析 ZFW 首页 HTML
   * 对齐 Flutter: _getNetworkUsage()
   * Flutter 逻辑：
   *   - 7列 tr → 在线设备 (td[1]=ip, td[3]=usedFlow, td[2]=onlineTime)
   *   - 4列 tr → 产品信息 (td[0]=productName, td[1]=used, td[2]=rest, td[3]=charged)
   *     排除含"联通/移动/电信"的运营商行
   */
  private parseZfwHome(html: string): ZfwUsageData {
    const result: ZfwUsageData = {
      usedFlow: '',
      remainFlow: '',
      settleDate: '',
      ipList: [],
    };

    // 解析所有 <tr>
    const trRegex: RegExp = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let trMatch: RegExpExecArray | null;
    while ((trMatch = trRegex.exec(html)) !== null) {
      const trContent: string = trMatch[1];
      // 提取所有 <td>
      const tdRegex: RegExp = /<td[^>]*>([\s\S]*?)<\/td>/gi;
      const tds: string[] = [];
      let tdMatch: RegExpExecArray | null;
      while ((tdMatch = tdRegex.exec(trContent)) !== null) {
        tds.push(tdMatch[1].replace(/<[^>]*>/g, '').trim());
      }

      if (tds.length === 7) {
        // 在线设备行: td[1]=ip, td[2]=onlineTime, td[3]=usedFlow (对齐Flutter: td[1]=ip, td[3]=used, td[2]=time)
        const ip: string = tds[1];
        const onlineTime: string = tds[2];
        const usedFlow: string = tds[3];
        if (ip.length > 0 && ip !== 'IP地址') {
          result.ipList.push({ ip: ip, onlineTime: onlineTime, usedFlow: usedFlow });
        }
      } else if (tds.length === 4) {
        // 产品信息行: td[0]=productName, td[1]=used, td[2]=rest, td[3]=charged
        // 排除运营商行（对齐 Flutter）
        const productName: string = tds[0];
        const lowerName: string = productName.toLowerCase();
        const isOperator: boolean =
          lowerName.indexOf('联通') >= 0 ||
          lowerName.indexOf('移动') >= 0 ||
          lowerName.indexOf('电信') >= 0;
        if (!isOperator && tds[1].length > 0) {
          result.usedFlow = tds[1];
          result.remainFlow = tds[2];
          result.settleDate = tds[3];
        }
      }
    }

    console.info(TAG, 'Parsed ZFW home: used=' + result.usedFlow +
      ', remain=' + result.remainFlow + ', settle=' + result.settleDate +
      ', ips=' + result.ipList.length);
    return result;
  }

  /**
   * 解析上网明细页 HTML
   */
  private parseZfwDetail(html: string): ZfwDetailResult {
    const entries: ZfwDetailEntry[] = [];
    let totalPages: number = 1;
    const summary: ZfwDetailSummary = { flow: '0', duration: '0', cost: '0' };

    // 解析分页：找到最大页码
    const pageLinkRe: RegExp = /page=(\d+)/g;
    let pageMatch: RegExpExecArray | null;
    while ((pageMatch = pageLinkRe.exec(html)) !== null) {
      const num: number = parseInt(pageMatch[1]) || 0;
      if (num > totalPages) totalPages = num;
    }

    // 解析数据行（6列: 上线时间/下线时间/IP/总流量/时长/消费额）
    const trRegex: RegExp = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let trMatch: RegExpExecArray | null;
    while ((trMatch = trRegex.exec(html)) !== null) {
      const trContent: string = trMatch[1];
      const tdRegex: RegExp = /<td[^>]*>([\s\S]*?)<\/td>/gi;
      const tds: string[] = [];
      let tdMatch: RegExpExecArray | null;
      while ((tdMatch = tdRegex.exec(trContent)) !== null) {
        tds.push(tdMatch[1].replace(/<[^>]*>/g, '').trim());
      }

      if (tds.length === 6) {
        const startTime: string = tds[0];
        // 跳过表头行
        if (startTime === '上线时间' || startTime.length === 0) continue;
        entries.push({
          startTime: startTime,
          endTime: tds[1],
          ip: tds[2],
          totalFlow: tds[3],
          duration: tds[4],
          cost: tds[5],
        });
      } else if (tds.length === 3) {
        // 汇总行
        summary.flow = tds[0];
        summary.duration = tds[1];
        summary.cost = tds[2];
      }
    }

    console.info(TAG, 'Parsed ZFW detail: entries=' + entries.length +
      ', pages=' + totalPages + ', summary flow=' + summary.flow);
    return { entries: entries, totalPages: totalPages, summary: summary };
  }

  // ===== RSA 加密 =====

  /**
   * RSA PKCS#1 v1.5 加密密码
   * ZFW 给的是 PEM 格式 X.509 SPKI（-----BEGIN PUBLIC KEY-----）
   * 去掉 PEM 头 → base64 解码 → X.509 SPKI DER → convertKey
   */
  async encryptPasswordRSA(password: string, rsaKeyPem: string): Promise<string> {
    // 去掉 PEM 头尾和空白
    let b64: string = rsaKeyPem;
    if (b64.indexOf('-----BEGIN') >= 0) {
      b64 = b64.replace(/-----[A-Z ]+-----/g, '');
      b64 = b64.replace(/\r/g, '');
      b64 = b64.replace(/\n/g, '');
      b64 = b64.replace(/\s/g, '');
    }
    console.error(TAG + ' RSA b64 key len=' + b64.length + ' head=' + b64.substring(0, 20));

    // base64 解码得到 X.509 SPKI DER
    const decoded: Uint8Array = this.base64Helper.decodeSync(b64);

    // 直接用 SPKI DER 转换公钥
    const pubKeyBlob: cryptoFramework.DataBlob = { data: decoded };
    const asyKeyGenerator: cryptoFramework.AsyKeyGenerator =
      cryptoFramework.createAsyKeyGenerator('RSA2048|PRIMES_2');
    const keyPair: cryptoFramework.KeyPair = await asyKeyGenerator.convertKey(pubKeyBlob, null);

    // PKCS#1 v1.5 加密
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('RSA2048|PKCS1');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, keyPair.pubKey, null);

    const textEncoder: util.TextEncoder = new util.TextEncoder();
    const plainBytes: Uint8Array = textEncoder.encodeInto(password);
    const input: cryptoFramework.DataBlob = { data: plainBytes };
    const output: cryptoFramework.DataBlob = await cipher.doFinal(input);

    // 加密结果 → base64
    const base64: string = this.base64Helper.encodeToStringSync(output.data);
    console.error(TAG + ' RSA encrypted pwd len=' + base64.length);
    return base64;
  }
}
