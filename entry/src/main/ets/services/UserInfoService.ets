// UserInfoService.ets — 用户信息管理（ehall getuserinfo.json + Preference 缓存）
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { EhallService } from './EhallService';
import { CasLoginService } from './CasLoginService';
import { AttendanceService } from './AttendanceService';

const TAG: string = 'UserInfoService';

const EHALL_USERINFO_URL: string = 'https://ehall.xidian.edu.cn/jsonp/userFavoriteApps.json';
const EHALL_HEADERS: Record<string, string> = {
  'Referer': 'http://ehall.xidian.edu.cn/new/index_xd.html',
  'Host': 'ehall.xidian.edu.cn',
  'Accept': 'application/json, text/javascript, */*; q=0.01',
};

export class UserInfo {
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
    // 动态构造头像URL：从chaoxing UID拼接，80px缩略图可直接访问无需Referer
    if (info.uid.length > 0) {
      info.avatar = 'https://photo.chaoxing.com/p/' + info.uid + '_80';
    } else {
      info.avatar = PreferenceUtil.getString('user_avatar');
    }
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

  // fetchAll 同步版 — fetchFromEhall 成功后直接读缓存，不加 async
  fetchAllSync(): UserInfo {
    const info: UserInfo = new UserInfo();
    info.name = PreferenceUtil.getString('user_name');
    info.uid = PreferenceUtil.getString('cx_uid');
    if (info.uid.length > 0) {
      info.avatar = 'https://photo.chaoxing.com/p/' + info.uid + '_80';
    } else {
      info.avatar = PreferenceUtil.getString('user_avatar');
    }
    info.major = PreferenceUtil.getString('user_major');
    info.college = PreferenceUtil.getString('user_college');
    info.grade = PreferenceUtil.getString('user_grade');
    info.gender = PreferenceUtil.getString('user_gender');
    info.dormitory = PreferenceUtil.getString('user_dormitory');
    info.studentType = PreferenceUtil.getString('user_student_type');
    info.className = PreferenceUtil.getString('user_class');
    return info;
  }

  // xgxt 个人信息拉取（CAS SSO → xgxt → getAppConfig → getStuBaseInfo）
  async fetchFromEhall(xh: string): Promise<boolean> {
    console.info(TAG, 'fetchFromEhall: start, xh=' + xh);
    try {
      // ──── Step 0: 确保 CAS TGC 有效 ────
      const casRestored: boolean = await CasLoginService.getInstance().tryAutoRestoreLogin();
      console.info(TAG, 'fetchFromEhall: tryAutoRestoreLogin=' + String(casRestored));
      if (!casRestored) {
        console.warn(TAG, 'fetchFromEhall: CAS session expired, cannot proceed');
        return false;
      }

      // ──── Step 1: 先 GET xgxt，让它自己触发 CAS 302（service 参数由 xgxt 生成，CAS 才认） ────
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

      // ──── Step 2: getAppConfig 初始化模块 ────
      const xgxtHeaders: Record<string, string> = {
        'Referer': 'https://xgxt.xidian.edu.cn/xsfw/sys/jbxxapp/*default/index.do',
        'Host': 'xgxt.xidian.edu.cn',
      };
      const configUrl: string = 'https://xgxt.xidian.edu.cn/xsfw/sys/swpubapp/indexmenu/getAppConfig.do?appId=4585275700341858&appName=jbxxapp';
      resp = await this.http.postEmpty(configUrl, xgxtHeaders);
      console.info(TAG, 'fetchFromEhall: getAppConfig status=' + String(resp.statusCode) +
        ' body=' + resp.body.substring(0, 200));

      // ──── Step 3: getStuBaseInfo 拉取信息 ────
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

      // 拉取超星 UID（await 确保写完 Preference 后再返回）
      await this.fetchChaoxingUid();

      return name.length > 0;
    } catch (e) {
      console.warn(TAG, 'fetchFromEhall: exception: ' + String(e));
      return false;
    }
  }

  // 超星平台 UID 获取（纯 HTTP，不走 WebView）
  // 流程：CAS SSO → loginToLearning → HTTP GET i.chaoxing.com/base → 正则提取 UID
  async fetchChaoxingUid(): Promise<string> {
    const cached: string = PreferenceUtil.getString('cx_uid');
    if (cached.length > 0) {
      console.info(TAG, 'fetchChaoxingUid: from cache, uid=' + cached);
      return cached;
    }

    console.info(TAG, 'fetchChaoxingUid: no cache, fetching via HTTP...');
    try {
      // 确保 CAS session 存活
      const casOk: boolean = await CasLoginService.getInstance().tryAutoRestoreLogin();
      if (!casOk) {
        console.warn(TAG, 'fetchChaoxingUid: CAS session expired');
        return '';
      }

      // 通过 xdspoc SSO 登录超星（CAS 白名单内）
      await AttendanceService.getInstance().loginToLearning();
      console.info(TAG, 'fetchChaoxingUid: loginToLearning complete');

      // 把子域 cookie 搬运到超星主站域
      const srcDomains: string[] = ['fanya.chaoxing.com', 'xdspoc.fanya.chaoxing.com',
        'fycourse.fanya.chaoxing.com', 'mobilelearn.chaoxing.com'];
      const cxDomains: string[] = ['i.chaoxing.com', 'passport2.chaoxing.com', 'chaoxing.com'];
      for (let si = 0; si < srcDomains.length; si++) {
        for (let di = 0; di < cxDomains.length; di++) {
          this.http.copyCookiesForDomain(srcDomains[si], cxDomains[di]);
        }
      }

      // HTTP GET i.chaoxing.com/base（服务端渲染，UID 在初始 HTML 中）
      const resp: HttpResponse = await this.http.get('https://i.chaoxing.com/base');
      const body: string = resp.body || '';
      console.info(TAG, 'fetchChaoxingUid: base page status=' + String(resp.statusCode) +
        ' len=' + String(body.length));

      if (!resp.isOk || body.length < 500) {
        console.warn(TAG, 'fetchChaoxingUid: base page too short or not OK');
        return '';
      }

      // 正则提取 UID：优先 JS 变量，降级头像 URL
      let match: RegExpMatchArray | null = body.match(/var uid\s*=\s*'(\d+)'/);
      if (!match) {
        match = body.match(/photo\.chaoxing\.com\/p\/(\d+)_80/);
      }

      if (!match) {
        console.warn(TAG, 'fetchChaoxingUid: UID not found in base page HTML');
        return '';
      }

      const uid: string = match[1];
      PreferenceUtil.putString('cx_uid', uid);
      console.info(TAG, 'fetchChaoxingUid: saved uid=' + uid);
      return uid;
    } catch (e) {
      console.warn(TAG, 'fetchChaoxingUid: exception: ' + String(e));
      return '';
    }
  }
}
