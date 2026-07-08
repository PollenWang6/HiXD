// SportService.ets — 体育体测数据服务
// 从 Flutter 版 xidian_sport_session.dart 移植
// 数据源: http://tybjxgl.xidian.edu.cn/app/
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { HttpUtil } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';

const TAG = 'SportService';
const BASE_URL = 'http://tybjxgl.xidian.edu.cn/app/';

// 体育系统 RSA 公钥 (PEM X.509 SPKI, 2048-bit)
const SPORT_RSA_KEY =
  '-----BEGIN PUBLIC KEY-----\n' +
  'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAq4l\n' +
  'aolA7zAk7jzsqDb3Oa5pS/uCPlZfASK8Soh/NzEmry77QDZ\n' +
  '2koyr96M5Wx+A9cxwewQMHzi8RoOfb3UcQO4UDQlMUImLuz\n' +
  'Unfbk3TTppijSLH+PU88XQxcgYm2JTa546c7JdZSI6dBeXO\n' +
  'JH20quuxWyzgLk9jAlt3ytYygPQ7C6o6ZSmjcMgE3xgLaHG\n' +
  'vixEVpOjL/pdVLzXhrMqWVAnB/snMjpCqesDVTDe5c6OOmj\n' +
  '2q5J8n+tzIXtnvrkxQSDaUp8DWF8meMwyTErmYklMXzKic2\n' +
  'rjdYZpHh4x98Fg0Q28sp6i2ZoWiGrJDKW29mntVQQiDNhKD\n' +
  'awb4B45zUwIDAQAB\n' +
  '-----END PUBLIC KEY-----';

const APP_ID = '3685bc028aaf4e64ad6b5d2349d24ba8';
const APP_SECRET = 'e8167ef026cbc5e456ab837d9d6d9254';

// ===== 数据模型 =====

export interface SportItem {
  examName: string;
  examUnit: string;
  actualScore: string;
  score: number;
  rank: string;
}

export interface SportScoreOfYear {
  year: string;
  totalScore: string;
  rank: string;
  gradeType: string;
  moreInfo: string;
  details: SportItem[];
}

export interface SportScore {
  total: string;
  rank: string;
  detail: string;
  list: SportScoreOfYear[];
}

// 成绩构成明细项
export interface SportScoreComponent {
  exam: string;       // 项目名
  fenshu: string;     // 成绩
  duizhaofen: string; // 对照分
  bili: string;       // 比例
  score: string;      // 得分
}

export interface SportClassItem {
  termToShow: string;
  term: string;
  name: string;
  teacher: string;
  week: number;     // 1=周一 ... 7=周日
  start: number;    // 开始节次
  stop: number;     // 结束节次
  place: string;
  score: string;
  type: string;
  termScoreId: string; // 学期成绩ID，用于查询成绩构成
  scoreComponents: SportScoreComponent[]; // 成绩构成明细
}

export class SportService {
  private static instance: SportService;
  private http: HttpUtil = HttpUtil.getInstance();
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  private textEncoder: util.TextEncoder = new util.TextEncoder();
  private userId: string = '';
  private token: string = '';

  private constructor() {}

  static getInstance(): SportService {
    if (!SportService.instance) SportService.instance = new SportService();
    return SportService.instance;
  }

  // ===== 登录 =====

  private async encryptPasswordRSA(password: string): Promise<string> {
    // 去掉 PEM 头尾
    let b64: string = SPORT_RSA_KEY
      .replace(/-----[A-Z ]+-----/g, '')
      .replace(/\r/g, '')
      .replace(/\n/g, '')
      .replace(/\s/g, '');

    const decoded: Uint8Array = this.base64Helper.decodeSync(b64);
    const pubKeyBlob: cryptoFramework.DataBlob = { data: decoded };
    const asyKeyGenerator: cryptoFramework.AsyKeyGenerator =
      cryptoFramework.createAsyKeyGenerator('RSA2048|PRIMES_2');
    const keyPair: cryptoFramework.KeyPair = await asyKeyGenerator.convertKey(pubKeyBlob, null);

    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('RSA2048|PKCS1');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, keyPair.pubKey, null);

    const plainBytes: Uint8Array = this.textEncoder.encodeInto(password);
    const input: cryptoFramework.DataBlob = { data: plainBytes };
    const output: cryptoFramework.DataBlob = await cipher.doFinal(input);

    return this.base64Helper.encodeToStringSync(output.data);
  }

  private md5Hex(input: string): string {
    // 同步 MD5 — cryptoFramework Md 是异步的，但 HarmonyOS 提供同步接口
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    const bytes: Uint8Array = this.textEncoder.encodeInto(input);
    md.updateSync({ data: bytes });
    const digest: cryptoFramework.DataBlob = md.digestSync();
    // 转十六进制
    let hex: string = '';
    for (let i = 0; i < digest.data.length; i++) {
      const b: number = digest.data[i];
      hex += (b < 16 ? '0' : '') + b.toString(16);
    }
    return hex;
  }

  /**
   * 计算签名: 对 params 按 key 排序拼接 → MD5
   * 格式: key1=val1&key2=val2&...  (不含前导 &)
   */
  private getSign(params: Record<string, string>): string {
    const keys: string[] = Object.keys(params).sort();
    let toCalc: string = '';
    for (const k of keys) {
      toCalc += (toCalc.length > 0 ? '&' : '') + k + '=' + params[k];
    }
    return this.md5Hex(toCalc);
  }

  /**
   * 构建请求头: channel/version/type + token + timestamp + sign
   */
  private getHeaders(body: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {
      'channel': 'H5',
      'version': '99999',
      'type': '0',
    };
    if (this.token.length > 0) {
      headers['token'] = this.token;
    }
    const timestamp: string = Date.now().toString();
    headers['timestamp'] = timestamp;

    // 签名: body params + timestamp + appId + appSecret
    const signParams: Record<string, string> = {};
    for (const k of Object.keys(body)) {
      signParams[k] = body[k];
    }
    signParams['timestamp'] = timestamp;
    signParams['appId'] = APP_ID;
    signParams['appSecret'] = APP_SECRET;
    headers['sign'] = this.getSign(signParams);

    return headers;
  }

  /**
   * 发送 POST 请求 (form-urlencoded)
   */
  private async require(subWebsite: string, body: Record<string, string>): Promise<Record<string, Object>> {
    const url: string = BASE_URL + subWebsite;
    const headers: Record<string, string> = this.getHeaders(body);
    const resp = await this.http.postForm(url, body, headers);
    if (!resp.isOk) {
      throw new Error('Sport API error: ' + resp.statusCode + ' ' + resp.body.substring(0, 200));
    }
    const parsed: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
    return parsed;
  }

  /**
   * 检查响应是否认证失败
   */
  private isAuthFailure(response: Record<string, Object>): boolean {
    const returnCode: string = String(response['returnCode'] ?? '');
    if (returnCode === '401' || returnCode === '402') return true;
    const returnMsg: string = String(response['returnMsg'] ?? response['msg'] ?? '');
    const keywords: string[] = ['未登录', '登录失效', '自动登录失效', 'token失效', '重新登录'];
    for (const kw of keywords) {
      if (returnMsg.indexOf(kw) >= 0) return true;
    }
    return false;
  }

  /**
   * 带认证的请求 (失败自动重试一次)
   */
  private async authenticatedRequire(subWebsite: string, body: Record<string, string>): Promise<Record<string, Object>> {
    const resp: Record<string, Object> = await this.require(subWebsite, body);
    if (this.isAuthFailure(resp)) {
      // 重新登录后重试
      this.userId = '';
      this.token = '';
      await this.login(true);
      const resp2: Record<string, Object> = await this.require(subWebsite, body);
      if (this.isAuthFailure(resp2)) {
        throw new Error('Sport auth failed after retry');
      }
      return resp2;
    }
    return resp;
  }

  /**
   * 登录体育系统
   */
  async login(force: boolean = false): Promise<void> {
    if (!force && this.userId.length > 0 && this.token.length > 0) return;

    const idsAccount: string = PreferenceUtil.getString('ids_account');
    const sportPwd: string = PreferenceUtil.getString('sport_password');
    if (idsAccount.length === 0 || sportPwd.length === 0) {
      throw new Error('缺少体育系统密码，请先在设置中填写');
    }

    const encryptedPwd: string = await this.encryptPasswordRSA(sportPwd);

    const body: Record<string, string> = {
      'uname': idsAccount,
      'pwd': encryptedPwd,
      'openid': '',
    };

    const resp: Record<string, Object> = await this.require('h5/login', body);
    const returnCode: string = String(resp['returnCode'] ?? '');
    if (returnCode !== '200') {
      const returnMsg: string = String(resp['returnMsg'] ?? '登录失败');
      // 检查是否密码错误
      const pwdKeywords: string[] = ['用户名', '账号', '密码'];
      for (const kw of pwdKeywords) {
        if (returnMsg.indexOf(kw) >= 0) {
          throw new Error('体育系统密码错误: ' + returnMsg);
        }
      }
      throw new Error('体育系统登录失败: ' + returnMsg);
    }

    const data: Record<string, Object> = resp['data'] as Record<string, Object>;
    this.userId = String(data['id'] ?? '');
    this.token = String(data['token'] ?? '');
  }

  // ===== 数据获取 =====

  /**
   * 获取体测成绩
   * 返回总分、排名、各学年明细
   */
  async getScore(): Promise<SportScore> {
    if (this.userId.length === 0 || this.token.length === 0) {
      await this.login();
    }

    const result: SportScore = {
      total: '0.0',
      rank: '',
      detail: '',
      list: [],
    };

    const body: Record<string, string> = { 'userId': this.userId };
    const resp: Record<string, Object> = await this.authenticatedRequire('measure/getStuTotalScore', body);

    const dataArray: Object[] = resp['data'] as Object[];
    if (!dataArray) return result;

    for (const item of dataArray) {
      const i: Record<string, Object> = item as Record<string, Object>;
      if (i['graduationStatus'] !== undefined && i['graduationStatus'] !== null) {
        // 毕业总成绩行
        result.total = String(i['totalScore'] ?? '0.0');
        result.detail = String(i['gradeType'] ?? '');
        result.rank = String(i['rank'] ?? '');
      } else {
        // 学年成绩
        const yearItem: SportScoreOfYear = {
          year: String(i['year'] ?? ''),
          totalScore: String(i['totalScore'] ?? ''),
          rank: String(i['rank'] ?? ''),
          gradeType: String(i['gradeType'] ?? ''),
          moreInfo: '',
          details: [],
        };

        // 获取该学年详细项目
        const meaScoreId: string = String(i['meaScoreId'] ?? '');
        if (meaScoreId.length > 0) {
          try {
            const detailBody: Record<string, string> = { 'meaScoreId': meaScoreId };
            const detailResp: Record<string, Object> = await this.authenticatedRequire('measure/getStuScoreDetail', detailBody);
            const detailCode: string = String(detailResp['returnCode'] ?? '');
            if (detailCode !== '200') {
              yearItem.moreInfo = String(detailResp['returnMsg'] ?? '查询失败');
            } else {
              const details: Object[] = detailResp['data'] as Object[];
              if (details) {
                for (const d of details) {
                  const dr: Record<string, Object> = d as Record<string, Object>;
                  yearItem.details.push({
                    examName: String(dr['examName'] ?? ''),
                    examUnit: String(dr['examunit'] ?? ''),
                    actualScore: String(dr['actualScore'] ?? '0'),
                    score: Number(dr['score'] ?? 0),
                    rank: String(dr['rank'] ?? '不及格'),
                  });
                }
              }
            }
          } catch (e) {
            yearItem.moreInfo = '详情获取失败';
          }
        }

        result.list.push(yearItem);
      }
    }

    return result;
  }

  /**
   * 获取学期成绩构成明细
   * API: POST /app/stuTermScore/isLookScoreFX
   */
  async getScoreDetail(stuTermScoreId: string): Promise<SportScoreComponent[]> {
    const result: SportScoreComponent[] = [];
    if (stuTermScoreId.length === 0) return result;

    const body: Record<string, string> = {
      'stuTermScoreid': stuTermScoreId,
    };
    const resp: Record<string, Object> = await this.authenticatedRequire('stuTermScore/isLookScoreFX', body);

    const dataArray: Object[] = resp['data'] as Object[];
    if (!dataArray) return result;

    for (const item of dataArray) {
      const i: Record<string, Object> = item as Record<string, Object>;
      result.push({
        exam: String(i['exam'] ?? ''),
        fenshu: String(i['fenshu'] ?? ''),
        duizhaofen: String(i['duizhaofen'] ?? ''),
        bili: String(i['bili'] ?? ''),
        score: String(i['score'] ?? ''),
      });
    }
    return result;
  }

  /**
   * 获取体育课程信息（含成绩构成）
   */
  async getClass(): Promise<SportClassItem[]> {
    if (this.userId.length === 0 || this.token.length === 0) {
      await this.login();
    }

    const result: SportClassItem[] = [];

    const body: Record<string, string> = {
      'uid': this.userId,
      'pageIndex': '1',
      'pageSize': '100',
    };
    const resp: Record<string, Object> = await this.authenticatedRequire('stuTermScore/uidSelect', body);

    const dataArray: Object[] = resp['data'] as Object[];
    if (!dataArray) return result;

    for (const item of dataArray) {
      try {
        const i: Record<string, Object> = item as Record<string, Object>;
        const latestId: string = String(i['id'] ?? '');

        const classBody: Record<string, string> = {
          'stuid': this.userId,
          'stuTermScoreid': latestId,
        };
        const classResp: Record<string, Object> = await this.authenticatedRequire('stuTeacherCurriculum/selstuTeacherCurriculum', classBody);
        const classDataArray: Object[] = classResp['data'] as Object[];
        if (!classDataArray || classDataArray.length === 0) continue;

        const classData: Record<string, Object> = classDataArray[0] as Record<string, Object>;
        const termName: string = String(classData['teacherCurriculumSysTermName'] ?? '');
        const timeStr: string = String(classData['teacherCurriculumTeachingSchoolTimeName'] ?? '');

        // 解析学期名: "2024-2025第一学期" → term="2024-2025-1"
        const termMatch: string[] | null = /^(\d{4})-(\d{4})(.*?)(\d{1})$/.exec(termName);
        const term: string = termMatch ? `${termMatch[1]}-${termMatch[2]}-${termMatch[4]}` : termName;

        // 解析时间: "星期三35" → week=3, start=3, stop=5
        const timeMatch: string[] | null = /^星期(.{1})(\d{1})(\d{1})$/.exec(timeStr);
        let week: number = 0;
        let start: number = 0;
        let stop: number = 0;
        if (timeMatch) {
          const weekMap: Record<string, number> = {
            '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7,
          };
          week = weekMap[timeMatch[1]] ?? 0;
          start = parseInt(timeMatch[2], 10);
          stop = parseInt(timeMatch[3], 10);
        }

        result.push({
          termToShow: termName,
          term: term,
          name: String(classData['teacherCurriculumTeachingCurriculumName'] ?? ''),
          teacher: String(classData['teacherCurriculumSysUserName'] ?? ''),
          week: week,
          start: start,
          stop: stop,
          place: String(classData['teacherCurriculumTeachingAddressName'] ?? ''),
          score: String(i['score'] ?? ''),
          type: String(i['type'] ?? ''),
          termScoreId: latestId,
          scoreComponents: [],
        });

        // 尝试获取成绩构成明细
        if (latestId.length > 0 && /\d/.test(String(i['score'] ?? ''))) {
          try {
            const components: SportScoreComponent[] = await this.getScoreDetail(latestId);
            result[result.length - 1].scoreComponents = components;
          } catch (e) {
          }
        }
      } catch (e) {
        continue;
      }
    }

    return result;
  }

  /**
   * 检查是否已设置体育密码
   */
  static hasPassword(): boolean {
    return PreferenceUtil.getString('sport_password').length > 0;
  }
}
