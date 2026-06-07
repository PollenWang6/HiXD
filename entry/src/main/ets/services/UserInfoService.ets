// UserInfoService.ets — 用户信息管理（ehall getuserinfo.json + Preference 缓存）
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { EhallService } from './EhallService';

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

  // 从 ehall getuserinfo.json 获取用户信息（复用已有的 CAS → ehall cookie）
  async fetchFromEhall(xh: string): Promise<boolean> {
    console.info(TAG, 'fetchFromEhall: start, xh=' + xh);
    try {
      // 先确保 ehall session 有效
      const ehallOk: boolean = await EhallService.getInstance().checkEhallLogin();
      console.info(TAG, 'fetchFromEhall: checkEhallLogin=' + String(ehallOk));

      // 尝试通过 ehall 代理调用 xgxt API
      const proxyUrl: string = 'https://ehall.xidian.edu.cn/xsfw/sys/jbxxapp/modules/infoStudent/getStuBaseInfo.do';
      const formData: Record<string, string> = {
        'requestParamStr': '{"XSBH":"' + xh + '"}'
      };
      const headers: Record<string, string> = {
        'Referer': 'https://ehall.xidian.edu.cn/xsfw/sys/jbxxapp/*default/index.do',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Host': 'ehall.xidian.edu.cn',
      };
      const resp: HttpResponse = await this.http.postForm(proxyUrl, formData, headers);
      console.info(TAG, 'fetchFromEhall: xgxt-proxy status=' + String(resp.statusCode) +
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
