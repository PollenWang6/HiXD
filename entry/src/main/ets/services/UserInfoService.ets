// UserInfoService.ets — 用户信息管理（ehall getuserinfo.json + Preference 缓存）
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { EhallService } from './EhallService';
import { CasLoginService } from './CasLoginService';

const TAG: string = 'UserInfoService';

const EHALL_USERINFO_URL: string = 'https://ehall.xidian.edu.cn/jsonp/userFavoriteApps.json';
const EHALL_HEADERS: Record<string, string> = {
  'Referer': 'http://ehall.xidian.edu.cn/new/index_xd.html',
  'Host': 'ehall.xidian.edu.cn',
  'Accept': 'application/json, text/javascript, */*; q=0.01',
};

class UserInfo {
  name: string = '';
  uid: string = '';
  avatar: string = '';
  major: string = '';
  college: string = '';
  grade: string = '';
  gender: string = '';
  dormitory: string = '';
  studentType: string = '';
  className: string = '';
}

export class UserInfoService {
  private static instance: UserInfoService;
  private http: HttpUtil = HttpUtil.getInstance();

  static getInstance(): UserInfoService {
    if (!UserInfoService.instance) {
      UserInfoService.instance = new UserInfoService();
    }
    return UserInfoService.instance;
  }

  // 从 Preference 读取已缓存的信息
  async fetchAll(): Promise<UserInfo> {
    const info: UserInfo = new UserInfo();
    info.name = PreferenceUtil.getString('user_name');
    info.uid = PreferenceUtil.getString('cx_uid');
    info.avatar = PreferenceUtil.getString('user_avatar');
    info.major = PreferenceUtil.getString('user_major');
    info.college = PreferenceUtil.getString('user_college');
    info.grade = PreferenceUtil.getString('user_grade');
    info.gender = PreferenceUtil.getString('user_gender');
    info.dormitory = PreferenceUtil.getString('user_dormitory');
    info.studentType = PreferenceUtil.getString('user_student_type');
    info.className = PreferenceUtil.getString('user_class');
    console.info(TAG, 'fetchAll: name=' + info.name + ' college=' + info.college +
      ' major=' + info.major + ' grade=' + info.grade);
    return info;
  }

  // xgxt 个人信息拉取（CAS SSO → xgxt → getAppConfig → getStuBaseInfo）
  async fetchFromEhall(xh: string): Promise<boolean> {
    console.info(TAG, 'fetchFromEhall: start, xh=' + xh);
    try {
      // ─── Step 0: 确保 CAS TGC 有效（checkEhallLogin 只看 MOD_AUTH_CAS，不验证 TGC） ───
      const casRestored: boolean = await CasLoginService.getInstance().tryAutoRestoreLogin();
      console.info(TAG, 'fetchFromEhall: tryAutoRestoreLogin=' + String(casRestored));
      if (!casRestored) {
        console.warn(TAG, 'fetchFromEhall: CAS session expired, cannot proceed');
        return false;
      }

      // ─── Step 1: 先 GET xgxt，让它自己触发 CAS 302（service 参数由 xgxt 生成，CAS 才认） ───
      const xgxtIndex: string = 'https://xgxt.xidian.edu.cn/xsfw/sys/jbxxapp/*default/index.do';
      let currentUrl: string = xgxtIndex;
      let resp: HttpResponse = await this.http.getNoRedirect(xgxtIndex);
      let loop: number = 0;
      while (resp.isRedirect && resp.location && loop < 10) {
        let location: string = resp.location;
        const baseCk: RegExpMatchArray | null = currentUrl.match(/^(https?:\/\/[^\/]+)/);
        if (baseCk) {
          const base: string = baseCk[1];
          if (!location.startsWith('http://') && !location.startsWith('https://')) {
            location = base + (location.startsWith('/') ? location : '/' + location);
          }
        }
        currentUrl = location;
        resp = await this.http.getNoRedirect(location);
        loop++;
      }
      console.info(TAG, 'fetchFromEhall: SSO done, final status=' + String(resp.statusCode) +
        ' url=' + currentUrl.substring(0, 80));

      // 不要 copy ids → xgxt：ids 的 route/JSESSIONID/happyVoyage 与 xgxt 不同，会覆盖 xgxt SSO 拿到的正确 session
      const xgxtCookies: string = this.http.getCookiesForDomain('xgxt.xidian.edu.cn');
      console.info(TAG, 'fetchFromEhall: xgxt cookies=' + xgxtCookies.substring(0, 200));

      // ─── Step 2: getAppConfig 初始化模块（初始化 session，可能设置必要 cookie） ───
      const xgxtHeaders: Record<string, string> = {
        'Referer': 'https://xgxt.xidian.edu.cn/xsfw/sys/jbxxapp/*default/index.do',
        'Host': 'xgxt.xidian.edu.cn',
      };
      const configUrl: string = 'https://xgxt.xidian.edu.cn/xsfw/sys/swpubapp/indexmenu/getAppConfig.do?appId=4585275700341858&appName=jbxxapp';
      resp = await this.http.postEmpty(configUrl, xgxtHeaders);
      console.info(TAG, 'fetchFromEhall: getAppConfig status=' + String(resp.statusCode) +
        ' body=' + resp.body.substring(0, 200));

      // ─── Step 3: getStuBaseInfo 拉取信息 ───
      const infoUrl: string = 'https://xgxt.xidian.edu.cn/xsfw/sys/jbxxapp/modules/infoStudent/getStuBaseInfo.do';
      const infoBody: Record<string, string> = {
        'requestParamStr': '{"XSBH":"' + xh + '"}'
      };
      resp = await this.http.postForm(infoUrl, infoBody, xgxtHeaders);
      console.info(TAG, 'fetchFromEhall: getStuBaseInfo status=' + String(resp.statusCode) +
        ' body=' + resp.body.substring(0, 300));

      if (!resp.isOk || !resp.body) {
        console.warn(TAG, 'fetchFromEhall: request failed');
        return false;
      }

      // xgxt API 返回纯 JSON: {"returnCode":"...","data":{...}}
      const obj: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      const returnCode: string = String(obj['returnCode'] ?? '');
      console.info(TAG, 'fetchFromEhall: returnCode=' + returnCode);

      if (returnCode !== '#E000000000000') {
        console.warn(TAG, 'fetchFromEhall: API error');
        return false;
      }

      const data: Record<string, Object> = obj['data'] as Record<string, Object>;
      if (!data) {
        console.warn(TAG, 'fetchFromEhall: no data field');
        return false;
      }

      // 打印全部字段便于诊断
      const dataKeys: string[] = Object.keys(data);
      console.info(TAG, 'fetchFromEhall: data keys=' + dataKeys.join(',') +
        ' count=' + String(dataKeys.length));

      const name: string = String(data['XM'] ?? '');
      const college: string = String(data['DWDM_DISPLAY'] ?? '');
      const major: string = String(data['ZYDM_DISPLAY'] ?? '');
      const grade: string = String(data['XZNJ'] ?? '');
      const gender: string = String(data['XBDM_DISPLAY'] ?? '');
      const dormitory: string = String(data['ZSDZ'] ?? '');
      const studentType: string = String(data['XSLBDM_DISPLAY'] ?? '');
      const className: string = String(data['BJDM_DISPLAY'] ?? '');

      if (name) PreferenceUtil.putString('user_name', name);
      if (college) PreferenceUtil.putString('user_college', college);
      if (major) PreferenceUtil.putString('user_major', major);
      if (grade) PreferenceUtil.putString('user_grade', grade);
      if (gender) PreferenceUtil.putString('user_gender', gender);
      if (dormitory) PreferenceUtil.putString('user_dormitory', dormitory);
      if (studentType) PreferenceUtil.putString('user_student_type', studentType);
      if (className) PreferenceUtil.putString('user_class', className);

      console.info(TAG, 'fetchFromEhall: OK name=' + name + ' college=' + college +
        ' major=' + major + ' grade=' + grade + ' gender=' + gender);
      return name.length > 0;
    } catch (e) {
      console.warn(TAG, 'fetchFromEhall: exception: ' + String(e));
      return false;
    }
  }
}
