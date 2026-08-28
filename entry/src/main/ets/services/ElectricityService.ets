// ElectricityService.ets — 电费纯 HTTP 实时拉取（对齐 Flutter energy_session.dart）
//
// 背景：
//   ElectricityPage 原依赖 WebView 走 SSO 重定向回调拿 ignypt OAuth `code`，无法在首页做后台轻刷。
//   经对照 Flutter(traintime_pda) energy_session.dart：其 getElectricityInfo 是纯 HTTP——
//   checkAndLogin 用 dio 跟随 302 重定向从 location 取 code（全程无 WebView）。
//   本服务用 ArkTS 复刻同款纯 HTTP OAuth 流程：
//     1) 用 HttpUtil 单例（复用已登录的 CAS CASTGC Cookie）跟随 xxcapp→CAS→ignypt 重定向链取 code；
//     2) 对齐 Flutter `_request`：每个 API 请求前都重新 GetSignature（签名一次性，复用会被拒），
//        再用 AES-CBC-128（key/iv=1234567812345678）加密 data，GET 放 query / POST 放 body。
//   前置条件：HttpUtil.cookieStore 中须已有有效的 CAS CASTGC（App 登录或 checkAndAutoLogin 之后）。
//   若 CASTGC 失效（重定向链最终落到 CAS 登录页而非带 code 的 ignypt URL），则抛错由调用方降级显示缓存。

import cryptoFramework from '@ohos.security.cryptoFramework';
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';
import { dayShift } from '../utils/DateUtil';
import { resolveLocation } from '../utils/UrlUtil';

const TAG: string = 'ElectricityService';

// 与 Flutter SSO_ENTRY 完全一致：xxcapp OAuth 入口，redirect 到 ignypt 缴费 H5
const SSO_ENTRY: string =
  'https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=https://ignypt.xidian.edu.cn/revenueH5/login?opcode=MPAY&appid=200260318155520600&state=12312312312312&qrcode=0';

// AES key/iv 与 Flutter(_aesKey/_iv) 及页面三处一致
const AES_KEY: string = '1234567812345678';

// GetSignature 请求头（与 Flutter dio.post 相同）
const IG_HEADERS: Record<string, string> = {
  'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36'
};

export interface ElecFetchResult {
  remain: string;       // 电费余量（kWh）
  metID: string;        // 电表号
  nodeID: string;       // 节点 ID（H5UserIDLogIn 返回）
  date: string;         // 上次读表时间
  waterRemain: string;  // 水费读数
  waterMetID: string;   // 水表号
  waterDate: string;    // 水表读表时间
}

// 单条读表记录
export interface ElecDailyItem {
  date: string;
  prevDate: string;
  use: string;
  startNum: string;
  endNum: string;
}

// 详情页完整结果（在基础余量之上叠加用电/用水明细）
export interface ElecFullResult extends ElecFetchResult {
  daily: ElecDailyItem[];
  waterDaily: ElecDailyItem[];
}

// Step5 读表明细请求体
interface MeterReq { MetID: string; ReadTimeS: string; ReadTimeE: string; ReadNum: string; }

// 各请求体显式接口（规避 arkts-no-untyped-obj-literals）
interface SigBody { data: string; access_token: string; OpCode: string; RequestID: string; }
interface CodeReq { CODE: string; }
interface LoginReq { UserID: string; Pwd: string; IsCehckPwd: number; NodeID: string; }
interface NodeReq { NodeID: string; }
interface ContentBody { content: string; }

// ===== 纯函数工具 =====

function strToU8(s: string): Uint8Array {
  const buf: number[] = [];
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

function extractCode(url: string): string {
  if (!url || url.length === 0) return '';
  const idx: number = url.indexOf('code=');
  if (idx < 0) return '';
  let code: string = url.substring(idx + 5);
  const amp: number = code.indexOf('&');
  return amp >= 0 ? code.substring(0, amp) : code;
}



export class ElectricityService {
  private static http: HttpUtil = HttpUtil.getInstance();

  // AES-CBC-128 + PKCS5，key/iv 均为 AES_KEY；输出标准 Base64（与 Flutter encrypter_plus 兼容）
  private static async aesEncrypt(plaintext: string): Promise<string> {
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

  // 纯 HTTP 跟随重定向链取 ignypt OAuth code（对齐 Flutter checkAndLogin + 重定向跟随）。
  // 前置：HttpUtil.cookieStore 已有有效 CAS CASTGC。
  private static async getIgnyptOAuthCode(): Promise<string> {
    let currentUrl: string = SSO_ENTRY;
    let resp: HttpResponse = await ElectricityService.http.getNoRedirect(currentUrl);
    let loopGuard: number = 0;
    while (loopGuard < 15) {
      if (currentUrl.indexOf('code=') >= 0) {
        return extractCode(currentUrl);
      }
      if (!resp.isRedirect || !resp.location) {
        // 重定向链中断且未拿到 code：多半是 CASTGC 失效，落到 CAS 登录页
        break;
      }
      currentUrl = resolveLocation(currentUrl, resp.location);
      resp = await ElectricityService.http.getNoRedirect(currentUrl);
      loopGuard++;
    }
    // 循环结束后 currentUrl 可能正好是带 code 的最终 URL（该请求返回了 200）
    if (currentUrl.indexOf('code=') >= 0) {
      return extractCode(currentUrl);
    }
    throw new Error('ignypt OAuth code not found (CAS session may be expired)');
  }

  // 每次请求重新 GetSignature（对齐 Flutter _request：sign 在每次请求前获取）。
  // 返回可用的 apiHeaders（timestamp/signature/OpCode/OrgId/RequestID）。
  private static async getSignature(): Promise<Record<string, string>> {
    const sigUrl: string = 'https://ignypt.xidian.edu.cn/baseNew/api/User/GetSignature';
    const emptySigBody: SigBody = { data: '', access_token: '', OpCode: 'MPAY', RequestID: '' };
    const sigResp: HttpResponse = await ElectricityService.http.post(sigUrl, emptySigBody, IG_HEADERS);
    if (!sigResp.isOk) {
      throw new Error('GetSignature failed: ' + sigResp.statusCode);
    }
    const sigJson: Record<string, object> = JSON.parse(sigResp.body) as Record<string, object>;
    const sigData: Record<string, object> | null = sigJson['data'] as Record<string, object> | null;
    if (!sigData) {
      throw new Error('GetSignature data empty: ' + sigResp.body.substring(0, 160));
    }
    const timestamp: string = String(sigData['timestamp']);
    const signature: string = String(sigData['signature']);
    if (timestamp.length === 0 || signature.length === 0) {
      throw new Error('GetSignature invalid ts/signature');
    }
    const apiHeaders: Record<string, string> = {
      'timestamp': timestamp, 'signature': signature, 'OpCode': 'MPAY', 'OrgId': '', 'RequestID': ''
    };
    return apiHeaders;
  }

  // 统一签名请求（对齐 Flutter _request）：每次先 GetSignature → AES 加密 data →
  // GET 时 content 放 query（encodeURIComponent），POST 时 content 放 JSON body。
  private static async signedRequest(url: string, data: object, isGet: boolean): Promise<HttpResponse> {
    const apiHeaders: Record<string, string> = await ElectricityService.getSignature();
    const enc: string = await ElectricityService.aesEncrypt(JSON.stringify(data));
    if (isGet) {
      return await ElectricityService.http.get(url + '?content=' + encodeURIComponent(enc), apiHeaders);
    }
    const body: ContentBody = { content: enc };
    return await ElectricityService.http.post(url, body, apiHeaders);
  }

  // Step0-4：确保 CAS 会话 → 取 OAuth code → 签名请求 → 电/水基础余量。
  // 返回 null 表示未登录/未取到（调用方降级显示缓存或报错）。
  private static async fetchBase(): Promise<ElecFetchResult | null> {
    try {
      // 0) 静默确保 CAS 会话（复用已有 CASTGC，无则尝试已存凭据恢复；不弹 UI）
      let loggedIn: boolean = false;
      try { loggedIn = await CasLoginService.getInstance().checkAndAutoLogin(); } catch (_e) { loggedIn = false; }
      if (!loggedIn) {
        console.error('[ElectricityService] CAS not logged in');
        return null;
      }
      // 1) 纯 HTTP OAuth 取 code
      const code: string = await ElectricityService.getIgnyptOAuthCode();
      if (!code || code.length === 0) {
        console.error('[ElectricityService] code empty');
        return null;
      }

      // Step 2 OauthGetUserInfo(CODE)
      const step2Req: CodeReq = { CODE: code };
      const uInfoResp: HttpResponse = await ElectricityService.signedRequest(
        'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/OauthGetUserInfo', step2Req, true);
      if (!uInfoResp.isOk) {
        throw new Error('OauthGetUserInfo failed: ' + uInfoResp.statusCode);
      }

      // Step 3 H5UserIDLogIn（IsCehckPwd 必须为数字 1，.NET 后端拒绝字符串 '1'）
      const userId: string = PreferenceUtil.getString('ids_account') || PreferenceUtil.getString('login_username') || '';
      const step3Req: LoginReq = { UserID: userId, Pwd: '', IsCehckPwd: 1, NodeID: '' };
      const loginResp: HttpResponse = await ElectricityService.signedRequest(
        'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/H5UserIDLogIn', step3Req, false);
      if (!loginResp.isOk) {
        throw new Error('H5UserIDLogIn failed: ' + loginResp.statusCode);
      }
      const loginJson: Record<string, object> = JSON.parse(loginResp.body) as Record<string, object>;
      const resData: object[] | null = loginJson['ResData'] as object[] | null;
      if (!resData || resData.length === 0) {
        throw new Error('H5UserIDLogIn ResData empty: ' + loginResp.body.substring(0, 160));
      }
      const nodeID: string = String((resData[0] as Record<string, object>)['NodeID']);

      // Step 4 H5QueryMeterList
      const step4Req: NodeReq = { NodeID: nodeID };
      const meterResp: HttpResponse = await ElectricityService.signedRequest(
        'https://ignypt.xidian.edu.cn/estManage/api/wechat/v2/H5QueryMeterList', step4Req, true);
      if (!meterResp.isOk) {
        throw new Error('H5QueryMeterList failed: ' + meterResp.statusCode);
      }
      const meterJson: Record<string, object> = JSON.parse(meterResp.body) as Record<string, object>;
      const md: object | null = meterJson['ResData'] as object | null;
      const rows: object[] | null = md ? ((md as Record<string, object>)['rows'] as object[]) : null;
      if (!rows || rows.length === 0) {
        throw new Error('H5QueryMeterList rows empty: ' + meterResp.body.substring(0, 160));
      }
      let elecRow: Record<string, object> = rows[0] as Record<string, object>;
      let waterRemain: string = '';
      let waterMetID: string = '';
      let waterDate: string = '';
      for (let i: number = 0; i < rows.length; i++) {
        const r: Record<string, object> = rows[i] as Record<string, object>;
        if (String(r['MediumCode']) === '2') {
          elecRow = r;
        } else {
          waterRemain = String(r['UsedNum']);
          waterMetID = String(r['MetID']);
          waterDate = String(r['LastReadDate']);
        }
      }
      const remain: string = String(elecRow['LastNum']);
      const metID: string = String(elecRow['MetID']);
      const date: string = String(elecRow['LastReadDate']);

      const base: ElecFetchResult = {
        remain: remain,
        metID: metID,
        nodeID: nodeID,
        date: date,
        waterRemain: waterRemain,
        waterMetID: waterMetID,
        waterDate: waterDate
      };
      return base;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : JSON.stringify(e);
      console.error('[ElectricityService] fetchBase failed: ' + msg);
      return null;
    }
  }

  // 首页卡片用：仅基础余量（不跑最重的 Step5 读表明细）。
  static async fetchEnergyInfo(): Promise<ElecFetchResult | null> {
    return await ElectricityService.fetchBase();
  }

  // 电费详情页用：完整数据（含近 30 天用电 / 近 365 天用水明细），纯 HTTP 无需 WebView SSO。
  static async fetchFullEnergyInfo(): Promise<ElecFullResult | null> {
    const base: ElecFetchResult | null = await ElectricityService.fetchBase();
    if (!base) return null;
    const daily: ElecDailyItem[] = [];
    let waterDaily: ElecDailyItem[] = [];
    try {
      // 电明细（近 30 天）
      const step5Req: MeterReq = { MetID: base.metID, ReadTimeS: dayShift(30), ReadTimeE: dayShift(0), ReadNum: '' };
      const readResp: HttpResponse = await ElectricityService.signedRequest(
        'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/GetMetRead', step5Req, true);
      if (readResp.isOk) {
        const readJson: Record<string, object> = JSON.parse(readResp.body) as Record<string, object>;
        const rd: object | null = readJson['ResData'] as object | null;
        const rdRows: object[] = (rd ? ((rd as Record<string, object>)['rows'] as object[]) : null) || [];
        for (let i: number = 0; i < rdRows.length; i++) {
          const r0: Record<string, object> = rdRows[i] as Record<string, object>;
          const date: string = String(r0['ReadTime']).substring(0, 10);
          const startNum: string = Number(r0['StartNum']).toFixed(2);
          const endNum: string = Number(r0['EndNum']).toFixed(2);
          const use: string = Number(r0['ReadNum']).toFixed(2);
          let prevDate: string = '';
          if (i + 1 < rdRows.length) {
            const nr: Record<string, object> = rdRows[i + 1] as Record<string, object>;
            prevDate = String(nr['ReadTime']).substring(0, 10);
          }
          daily.push({ date: date, prevDate: prevDate, use: use, startNum: startNum, endNum: endNum });
        }
      }
      // 水明细（近 365 天）
      if (base.waterMetID.length > 0) {
        const wReq: MeterReq = { MetID: base.waterMetID, ReadTimeS: dayShift(365), ReadTimeE: dayShift(0), ReadNum: '' };
        const wResp: HttpResponse = await ElectricityService.signedRequest(
          'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/GetMetRead', wReq, true);
        if (wResp.isOk) {
          const wJson: Record<string, object> = JSON.parse(wResp.body) as Record<string, object>;
          const wrd: object | null = wJson['ResData'] as object | null;
          const wRows: object[] = (wrd ? ((wrd as Record<string, object>)['rows'] as object[]) : null) || [];
          for (let i: number = 0; i < wRows.length; i++) {
            const r0: Record<string, object> = wRows[i] as Record<string, object>;
            const date: string = String(r0['ReadTime']).substring(0, 10);
            const startNum: string = Number(r0['StartNum']).toFixed(2);
            const endNum: string = Number(r0['EndNum']).toFixed(2);
            const use: string = Number(r0['ReadNum']).toFixed(2);
            waterDaily.push({ date: date, prevDate: '', use: use, startNum: startNum, endNum: endNum });
          }
        }
      }
    } catch (e5) {
      console.error('[ElectricityService] Step5 partial fail: ' + (e5 instanceof Error ? e5.message : JSON.stringify(e5)));
    }
    const result: ElecFullResult = {
      remain: base.remain, metID: base.metID, nodeID: base.nodeID, date: base.date,
      waterRemain: base.waterRemain, waterMetID: base.waterMetID, waterDate: base.waterDate,
      daily: daily, waterDaily: waterDaily
    };
    return result;
  }

  // 自定义日期区间读表明细（电或水表），供页面预设/自定义查询。
  // 每次请求重新 GetSignature，不依赖任何缓存的旧签名头。
  static async queryMeterRead(metID: string, startStr: string, endStr: string): Promise<ElecDailyItem[]> {
    const req: MeterReq = { MetID: metID, ReadTimeS: startStr, ReadTimeE: endStr, ReadNum: '' };
    const resp: HttpResponse = await ElectricityService.signedRequest(
      'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/GetMetRead', req, true);
    if (!resp.isOk) {
      throw new Error('GetMetRead failed: ' + resp.statusCode);
    }
    const json: Record<string, object> = JSON.parse(resp.body) as Record<string, object>;
    const rd: object | null = json['ResData'] as object | null;
    const rows: object[] | null = rd ? ((rd as Record<string, object>)['rows'] as object[]) : null;
    const items: ElecDailyItem[] = [];
    if (rows) {
      for (let i: number = 0; i < rows.length; i++) {
        const r0: Record<string, object> = rows[i] as Record<string, object>;
        const date: string = String(r0['ReadTime']).substring(0, 10);
        const startNum: string = Number(r0['StartNum']).toFixed(2);
        const endNum: string = Number(r0['EndNum']).toFixed(2);
        const use: string = Number(r0['ReadNum']).toFixed(2);
        let prevDate: string = '';
        if (i + 1 < rows.length) {
          const nr: Record<string, object> = rows[i + 1] as Record<string, object>;
          prevDate = String(nr['ReadTime']).substring(0, 10);
        }
        items.push({ date: date, prevDate: prevDate, use: use, startNum: startNum, endNum: endNum });
      }
    }
    return items;
  }
}
