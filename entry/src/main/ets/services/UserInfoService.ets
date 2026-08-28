// UserInfoService.ets — 用户信息管理（ehall getuserinfo.json + Preference 缓存）
import { HttpUtil, HttpResponse } from '../utils/HttpUtil';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { CasLoginService } from './CasLoginService';
import { AttendanceService } from './AttendanceService';

const TAG: string = 'UserInfoService';

const EHALL_USERINFO_URL: string = 'https://ehall.xidian.edu.cn/jsonp/userFavoriteApps.json';
const EHALL_HEADERS: Record<string, string> = {
  // Referer 必须 https：西电服务端按 Referer scheme 拼重定向 service 前缀
  'Referer': 'https://ehall.xidian.edu.cn/new/index_xd.html',
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
    return info;
  }

  // xgxt 个人信息拉取（CAS SSO → xgxt → getAppConfig → getStuBaseInfo）
  async fetchFromEhall(xh: string): Promise<boolean> {
    try {
      // ──── Step 0: 确保 CAS TGC 有效 ────
      const casRestored: boolean = await CasLoginService.getInstance().tryAutoRestoreLogin();
      if (!casRestored) {
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

      // 不要 copy ids → xgxt：ids 的 route/JSESSIONID/happyVoyage 与 xgxt 不同，会覆盖 xgxt SSO 拿到的正确 session

      const xgxtCookies: string = this.http.getCookiesForDomain('xgxt.xidian.edu.cn');

      // ──── Step 2: getAppConfig 初始化模块 ────
      const xgxtHeaders: Record<string, string> = {
        'Referer': 'https://xgxt.xidian.edu.cn/xsfw/sys/jbxxapp/*default/index.do',
        'Host': 'xgxt.xidian.edu.cn',
      };
      const configUrl: string = 'https://xgxt.xidian.edu.cn/xsfw/sys/swpubapp/indexmenu/getAppConfig.do?appId=4585275700341858&appName=jbxxapp';
      resp = await this.http.postEmpty(configUrl, xgxtHeaders);

      // ──── Step 3: getStuBaseInfo 拉取信息 ────
      const infoUrl: string = 'https://xgxt.xidian.edu.cn/xsfw/sys/jbxxapp/modules/infoStudent/getStuBaseInfo.do';
      // 与隐藏 WebView 注入的 JS fetch 保持一致：xgxt 要求 body 带 requestParamStr（学生编号）。
      // 传空 body 会被 HarmonyOS http 栈以 401 Parameter error 拒绝（POST 的 extraData 空串非法），故必须带真实参数。
      const infoBody: Record<string, string> = {
        'requestParamStr': '{"XSBH":"' + xh + '"}'
      };
      resp = await this.http.postForm(infoUrl, infoBody, xgxtHeaders);

      if (!resp.isOk || !resp.body) {
        return false;
      }

      const obj: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      const returnCode: string = String(obj['returnCode'] ?? '');

      if (returnCode !== '#E000000000000') {
        return false;
      }

      const data: Record<string, Object> = obj['data'] as Record<string, Object>;
      if (!data) {
        return false;
      }

      const dataKeys: string[] = Object.keys(data);

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

      // 拉取超星 UID（await 确保写完 Preference 后再返回）
      await this.fetchChaoxingUid();

      return name.length > 0;
    } catch (e) {
      return false;
    }
  }

  // 超星平台 UID 获取（纯 HTTP，不走 WebView）
  // 流程：CAS SSO → loginToLearning → 优先从 cookie 读 UID（.chaoxing.com 域 Set-Cookie 含 UID=），
  //       兜底 HTTP GET i.chaoxing.com/base → 正则提取 UID
  async fetchChaoxingUid(): Promise<string> {
    const cached: string = PreferenceUtil.getString('cx_uid');
    if (cached.length > 0) {
      return cached;
    }

    try {
      // 确保 CAS session 存活
      const casOk: boolean = await CasLoginService.getInstance().tryAutoRestoreLogin();
      if (!casOk) {
        return '';
      }

      // 通过 xdspoc SSO 登录超星（CAS 白名单内；loginToLearning 已容错最后一跳失败）
      try {
        await AttendanceService.getInstance().loginToLearning();
      } catch (_e) { /* 容忍：cookie 可能已建立 */ }

      // 把子域 cookie 搬运到超星主站域
      const srcDomains: string[] = ['fanya.chaoxing.com', 'xdspoc.fanya.chaoxing.com',
        'fycourse.fanya.chaoxing.com', 'mobilelearn.chaoxing.com'];
      const cxDomains: string[] = ['i.chaoxing.com', 'passport2.chaoxing.com', 'chaoxing.com'];
      for (let si = 0; si < srcDomains.length; si++) {
        for (let di = 0; di < cxDomains.length; di++) {
          this.http.copyCookiesForDomain(srcDomains[si], cxDomains[di]);
        }
      }

      // 优先从 cookie 读 UID（SSO 链 Set-Cookie 已带 UID=.chaoxing.com，比解析 HTML 可靠）
      const uidFromCookie: string = this.uidFromCookies();
      if (uidFromCookie.length > 0) {
        PreferenceUtil.putString('cx_uid', uidFromCookie);
        return uidFromCookie;
      }

      // 兜底：HTTP GET i.chaoxing.com/base（服务端渲染，UID 在初始 HTML 中）
      const resp: HttpResponse = await this.http.get('https://i.chaoxing.com/base');
      const body: string = resp.body || '';

      if (!resp.isOk || body.length < 500) {
        return '';
      }

      // 正则提取 UID：优先 JS 变量，降级头像 URL
      let match: RegExpMatchArray | null = body.match(/var uid\s*=\s*'(\d+)'/);
      if (!match) {
        match = body.match(/photo\.chaoxing\.com\/p\/(\d+)_80/);
      }

      if (!match) {
        return '';
      }

      const uid: string = match[1];
      PreferenceUtil.putString('cx_uid', uid);
      return uid;
    } catch (e) {
      return '';
    }
  }

  // 从超星 cookie 提取 UID（.chaoxing.com 域 Set-Cookie 含 UID=读者ID）
  private uidFromCookies(): string {
    const domains: string[] = ['chaoxing.com', '.chaoxing.com', 'i.chaoxing.com',
      'passport2.chaoxing.com', 'xdspoc.fanya.chaoxing.com', 'fanya.chaoxing.com'];
    for (let i = 0; i < domains.length; i++) {
      const c: string = this.http.getCookiesForDomain(domains[i]);
      if (c.length === 0) {
        continue;
      }
      const m: RegExpMatchArray | null = c.match(/(?:^|;\s*)UID=(\d+)/);
      if (m && m[1] && m[1].length > 0) {
        return m[1];
      }
    }
    return '';
  }
}
