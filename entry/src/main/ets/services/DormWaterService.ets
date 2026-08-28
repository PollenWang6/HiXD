// DormWaterService.ets — 宿舍水机（iLife798 慧生活平台）
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { util } from '@kit.ArkTS';

const TAG = 'DormWaterService';
const API_BASE = 'https://i.ilife798.com';
const USER_AGENT = 'Android_ilife798_2.0.11';
const USER_AGENT_CAPTCHA = 'iLife798/3.1.1 (iPhone; iOS 26.2; Scale/3.00)';

const COMMON_HEADERS: Record<string, string> = {
  'accept': '*/*',
  'accept-encoding': 'gzip, deflate, br',
  'accept-language': 'zh-Hans-US;q=1, el-US;q=0.9, en-US;q=0.8',
  'priority': 'u=3, i',
};

// ===== 模型 =====
export class DormWaterDevice {
  id: string = '';
  name: string = '';
}

export class CaptchaData {
  sessionId: string = '';
  imageBase64: string = '';
}

export class DormWaterLoginResult {
  token: string = '';
  uid: string = '';
  eid: string = '';
}

// ===== 工具：简单 HTTP 请求（不用 HttpUtil，直接用系统 http 模块，可控 Headers）=====
async function httpGet(url: string, headers: Record<string, string>): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const req = http.createHttp();
    req.request(url, { method: http.RequestMethod.GET, header: headers, readTimeout: 15000, connectTimeout: 10000 },
      (err: BusinessError, data: http.HttpResponse) => {
        if (err) { req.destroy(); reject(new Error('HTTP ' + err.code + ': ' + err.message)); return; }
        const body: string = typeof data.result === 'string' ? data.result : '';
        req.destroy();
        resolve(body);
      });
  });
}

async function httpPost(url: string, headers: Record<string, string>, body: string): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const req = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      readTimeout: 15000,
      connectTimeout: 10000
    }, (err: BusinessError, data: http.HttpResponse) => {
      if (err) { req.destroy(); reject(new Error('HTTP ' + err.code + ': ' + err.message)); return; }
      const result: string = typeof data.result === 'string' ? data.result : '';
      req.destroy();
      resolve(result);
    });
  });
}

function authHeaders(): Record<string, string> {
  const h: Record<string, string> = {};
  for (const key of Object.keys(COMMON_HEADERS)) { h[key] = COMMON_HEADERS[key]; }
  h['User-Agent'] = USER_AGENT;
  h['Authorization'] = PreferenceUtil.getString('dorm_water_token');
  return h;
}

export class DormWaterService {
  private static inst: DormWaterService;
  static getInstance(): DormWaterService {
    if (!DormWaterService.inst) DormWaterService.inst = new DormWaterService();
    return DormWaterService.inst;
  }

  private currentSessionId: string = '';

  // ===== 是否已登录 =====
  isLoggedIn(): boolean {
    return PreferenceUtil.getString('dorm_water_token').length > 0;
  }

  // ===== 获取图形验证码 =====
  async getCaptcha(): Promise<CaptchaData> {
    const sessionId: string = this.randStr(16);
    const ts: number = Date.now();
    const url: string = API_BASE + '/api/v1/captcha/?s=' + sessionId + '&r=' + ts;

    const headers: Record<string, string> = {};
    for (const key of Object.keys(COMMON_HEADERS)) { headers[key] = COMMON_HEADERS[key]; }
    headers['User-Agent'] = USER_AGENT_CAPTCHA;

    // 图形验证码是二进制图片，用 request 获取 bytes 然后 base64
    return new Promise<CaptchaData>((resolve, reject) => {
      const req = http.createHttp();
      req.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 10000,
        connectTimeout: 10000
      }, (err: BusinessError, data: http.HttpResponse) => {
        if (err) { req.destroy(); reject(new Error('验证码获取失败: ' + err.message)); return; }
        const buf: ArrayBuffer = data.result as ArrayBuffer;
        const base64: string = this.arrayBufferToBase64(buf);
        req.destroy();
        this.currentSessionId = sessionId;
        resolve({ sessionId: sessionId, imageBase64: base64 } as CaptchaData);
      });
    });
  }

  // ===== 发送短信验证码 =====
  async sendSmsCode(phone: string, imageCode: string): Promise<string> {
    const headers: Record<string, string> = {};
    for (const key of Object.keys(COMMON_HEADERS)) { headers[key] = COMMON_HEADERS[key]; }
    headers['content-type'] = 'application/json';
    headers['User-Agent'] = USER_AGENT;

    const body: string = JSON.stringify({ s: this.currentSessionId, authCode: imageCode, un: phone });
    const resp: string = await httpPost(API_BASE + '/api/v1/acc/login/code', headers, body);
    const obj: Record<string, Object> = JSON.parse(resp) as Record<string, Object>;
    if (Number(obj['code']) !== 0) {
      throw new Error('发送失败: ' + String(obj['msg'] ?? '未知错误'));
    }
    return '短信已发送';
  }

  // ===== 短信验证码登录 =====
  async login(phone: string, smsCode: string): Promise<DormWaterLoginResult> {
    const headers: Record<string, string> = {};
    for (const key of Object.keys(COMMON_HEADERS)) { headers[key] = COMMON_HEADERS[key]; }
    headers['content-type'] = 'application/json';
    headers['User-Agent'] = USER_AGENT;

    const body: string = JSON.stringify({ cid: '', authCode: smsCode, un: phone });
    const resp: string = await httpPost(API_BASE + '/api/v1/acc/login', headers, body);
    const obj: Record<string, Object> = JSON.parse(resp) as Record<string, Object>;
    if (Number(obj['code']) !== 0) {
      throw new Error('登录失败: ' + String(obj['msg'] ?? '未知错误'));
    }
    const data: Record<string, Object> = obj['data'] as Record<string, Object>;
    const al: Record<string, Object> = data['al'] as Record<string, Object>;
    const result: DormWaterLoginResult = {
      token: String(al['token'] ?? ''),
      uid: String(al['uid'] ?? ''),
      eid: String(al['eid'] ?? '')
    };
    PreferenceUtil.putString('dorm_water_token', result.token);
    PreferenceUtil.putString('dorm_water_uid', result.uid);
    PreferenceUtil.putString('dorm_water_eid', result.eid);
    return result;
  }

  // ===== 获取设备列表 =====
  async getDeviceList(): Promise<DormWaterDevice[]> {
    const resp: string = await httpGet(API_BASE + '/api/v1/ui/app/master', authHeaders());
    const obj: Record<string, Object> = JSON.parse(resp) as Record<string, Object>;
    if (Number(obj['code']) !== 0) {
      throw new Error('获取设备失败: ' + String(obj['msg'] ?? '未知错误'));
    }
    const data: Record<string, Object> = obj['data'] as Record<string, Object>;
    if (!data['account']) { throw new Error('登录已过期，请重新登录'); }
    const favos: object[] = (data['favos'] as object[]) ?? [];
    const devices: DormWaterDevice[] = [];
    for (let i = 0; i < favos.length; i++) {
      const f: Record<string, Object> = favos[i] as Record<string, Object>;
      devices.push({ id: String(f['id'] ?? ''), name: String(f['name'] ?? '') });
    }
    return devices;
  }

  // ===== 收藏/取消收藏 =====
  async toggleFavorite(deviceId: string, remove: boolean): Promise<void> {
    const url: string = API_BASE + '/api/v1/dev/favo?did=' + deviceId + '&remove=' + (remove ? 'true' : 'false');
    const resp: string = await httpGet(url, authHeaders());
    const obj: Record<string, Object> = JSON.parse(resp) as Record<string, Object>;
    if (Number(obj['code']) !== 0) {
      throw new Error(String(obj['msg'] ?? '操作失败'));
    }
  }

  // ===== 开始接水 =====
  async startWater(deviceId: string): Promise<void> {
    const url: string = API_BASE + '/api/v1/dev/start?args=&cnt=1&did=' + deviceId + '&pip=21&rcp=0&upgrade=1';
    const resp: string = await httpGet(url, authHeaders());
    const obj: Record<string, Object> = JSON.parse(resp) as Record<string, Object>;
    if (Number(obj['code']) !== 0) {
      throw new Error(String(obj['msg'] ?? '启动失败'));
    }
  }

  // ===== 停止接水 =====
  async endWater(deviceId: string): Promise<void> {
    const url: string = API_BASE + '/api/v1/dev/end?did=' + deviceId;
    const resp: string = await httpGet(url, authHeaders());
    const obj: Record<string, Object> = JSON.parse(resp) as Record<string, Object>;
    if (Number(obj['code']) !== 0) {
      throw new Error(String(obj['msg'] ?? '停止失败'));
    }
  }

  // ===== 查询设备状态 =====
  async checkDeviceStatus(deviceId: string): Promise<number> {
    const url: string = API_BASE + '/api/v1/ui/app/dev/status?did=' + deviceId + '&more=true&promo=false';
    const resp: string = await httpGet(url, authHeaders());
    const obj: Record<string, Object> = JSON.parse(resp) as Record<string, Object>;
    if (Number(obj['code']) !== 0) {
      throw new Error(String(obj['msg'] ?? '状态查询失败'));
    }
    const data: Record<string, Object> = obj['data'] as Record<string, Object>;
    const device: Record<string, Object> = data['device'] as Record<string, Object>;
    const gene: Record<string, Object> = device['gene'] as Record<string, Object>;
    return Number(gene['status'] ?? 0);
  }

  // ===== 登出 =====
  logout(): void {
    PreferenceUtil.putString('dorm_water_token', '');
    PreferenceUtil.putString('dorm_water_uid', '');
    PreferenceUtil.putString('dorm_water_eid', '');
  }

  // ===== 工具 =====
  private randStr(len: number): string {
    const chars: string = '0123456789';
    let result: string = '';
    for (let i = 0; i < len; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    const base64Helper = new util.Base64Helper();
    return base64Helper.encodeToStringSync(bytes);
  }
}
