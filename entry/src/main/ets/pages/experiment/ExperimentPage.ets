// ExperimentPage.ets - 实验信息页面（HTTP 数据获取）
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { ThemeColors } from '../../utils/ThemeColors';
import { ExperimentData, ExperimentType, TimeRange } from '../../services/Models';
import { ExperimentService } from '../../services/ExperimentService';
import { SemesterUtil, EhallService } from '../../services/EhallService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import router from '@ohos.router';

const TAG = 'ExperimentPage';
const WEEKDAY_NAMES: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const CACHE_KEY = 'sysj_exp_cache';
const PHYSICS_CACHE_KEY = 'physics_exp_cache';
const CACHE_TTL = 4 * 60 * 60 * 1000;
const TERM_ID = '2003';
const SYSJ_BASE = 'https://sysj.xidian.edu.cn';
const MAX_WEEKS = 25;

enum PageState { IDLE, LOADING, SUCCESS, ERROR }

interface SysjScheduleItem {
  courseCode: string; experimentName: string; department: string; lab: string;
  weekday: string; startSection: string; endSection: string; week: string;
  unknown8: string; teacher: string; unknown10: string; className: string;
  groupId: string; studentCount: string; experimentProject: string; __week: number;
}

interface ExpCard {
  date: string; weekdayName: string; weekNum: number; sectionName: string;
  isCompleted: boolean; experimentName: string; lab: string; teacher: string;
  experimentProject: string; className: string;
}

function formatDate(d: Date): string { let m=String(d.getMonth()+1).padStart(2,'0'); let day=String(d.getDate()).padStart(2,'0'); return d.getFullYear()+'-'+m+'-'+day; }
function getWeekdayName(w: number): string { let i=w-1; return (i>=0&&i<7)?WEEKDAY_NAMES[i]:''; }

@Component
export struct ExperimentPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @State pageState: PageState = PageState.IDLE;
  @State statusText: string = '';
  @State errorMsg: string = '';
  @State showCacheBanner: boolean = false;
  @State cards: ExpCard[] = [];
  @State fetchProgress: string = '';
  @State private isRefreshing: boolean = false;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.pageState = PageState.LOADING;
    this.statusText = '正在加载实验信息...';
    let cached = PreferenceUtil.getString(CACHE_KEY);
    let hasOther = false;
    if (cached.length > 0) {
      try {
        let co = JSON.parse(cached) as Record<string, Object>;
        if (Date.now() - (co['ts'] as number) < CACHE_TTL) {
          let raw = co['data'];
          if (raw instanceof Array && raw.length > 0) {
            this.buildCards(raw as SysjScheduleItem[]);
            hasOther = true;
            this.showCacheBanner = true;  // 显示缓存标记
          }
        }
      } catch (e) { PreferenceUtil.putString(CACHE_KEY, ''); }
    }
    if (!hasOther) {
      await this.doHttpSSOAndFetch();
    } else {
      // 有缓存，后台刷新 + 加载物理实验
      this.doHttpSSOAndFetch();
      await this.fetchPhysicsExperiment();
    }
    if (this.cards.length === 0) this.onError('暂无实验信息');
    else this.pageState = PageState.SUCCESS;
  }

  // ===== HTTP OAuth + 数据获取 =====
  async doHttpSSOAndFetch(): Promise<void> {
    if (!PreferenceUtil.getBool('is_logged_in')) { this.onError('请先登录统一认证'); return; }
    let account = PreferenceUtil.getString('ids_account');
    if (account.length === 0) { this.onError('缺少账号信息'); return; }

    this.pageState = PageState.LOADING;
    this.statusText = '正在登录实验系统...';
    this.fetchProgress = '';
    let http = HttpUtil.getInstance();

    try {
      // === Step 0: 先试直接调 API —— 如果已有 session 直接取数据 ===
      let r0: HttpResponse = await http.get(SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=1');
      if (r0.isOk && r0.body.length > 0 && r0.body.charAt(0) === '[') {
        console.info(TAG, 'already logged in, skip OAuth');
        // 直接进入数据获取循环
        let allItems: SysjScheduleItem[] = [];
        this.parseWeekData(r0.body, 1, allItems);
        for (let w: number = 2; w <= MAX_WEEKS; w++) {
          try {
            let rw: HttpResponse = await http.get(SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=' + String(w));
            this.parseWeekData(rw.body, w, allItems);
          } catch (e) { /* continue */ }
          this.fetchProgress = '(' + String(w) + '/' + String(MAX_WEEKS) + ')';
        }
        console.info(TAG, 'fetched=' + String(allItems.length));
        if (allItems.length > 0) {
          let co: ESObject = { 'ts': Date.now(), 'data': allItems } as ESObject;
          PreferenceUtil.putString(CACHE_KEY, JSON.stringify(co));
        }
        this.buildCards(allItems);
        this.showCacheBanner = false;
        if (allItems.length > 0) { this.pageState = PageState.SUCCESS; return; }
        else { this.onError('暂无实验信息'); return; }
      }
      console.info(TAG, 'need OAuth, API returned HTML or empty');

      // === Step 1: 从 sysj OAuth 重定向链提取真实 state ===
      let state: string = '';
      let r1: HttpResponse = await http.get(SYSJ_BASE + '/xidian/test');
      let b1: string = r1.body || '';
      console.info(TAG, 'step1 body len=' + b1.length);
      let om: RegExpMatchArray | null = b1.match(/[?&]state=([a-f0-9\-]{20,50})/i);
      if (om) { state = om[1]; console.info(TAG, 'state from body='+state); }

      // 如果 body 没有，试用 getNoRedirect 拦截重定向
      if (state.length === 0) {
        for (let a: number = 0; a < 4; a++) {
          let sr: HttpResponse = await http.getNoRedirect(SYSJ_BASE + '/xidian/test');
          console.info(TAG, 'step1-gnr'+a+': isRedirect='+sr.isRedirect+' status='+sr.statusCode+' loc='+(sr.location||'none').substring(0,120));
          if (sr.location && sr.location.length > 0) {
            let om2: RegExpMatchArray | null = sr.location.match(/[?&]state=([^&]+)/);
            if (om2) { state = om2[1]; break; }
            // 跟随这个重定向继续找
            let nextUrl: string = sr.location;
            if (!nextUrl.startsWith('http')) { nextUrl = SYSJ_BASE + (nextUrl.startsWith('/')?nextUrl:'/'+nextUrl); }
            let sr2: HttpResponse = await http.getNoRedirect(nextUrl);
            console.info(TAG, 'step1-gnr'+a+'-follow: loc='+(sr2.location||'none').substring(0,120));
            if (sr2.location) {
              let om3: RegExpMatchArray | null = sr2.location.match(/[?&]state=([^&]+)/);
              if (om3) { state = om3[1]; break; }
            }
          }
          if (sr.body && sr.body.length > 0) {
            let om4: RegExpMatchArray | null = sr.body.match(/state=([a-f0-9\-]{20,50})/i);
            if (om4) { state = om4[1]; break; }
          }
        }
      }
      if (state.length === 0) { this.onError('无法获取 OAuth 认证参数'); return; }
      console.info(TAG, 'state=' + state);

      // === Step 2: sysj OAuth → CAS OAuth authorize ===
      let params = 'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
        '&state=' + state + '&client_id=GvsunLims&response_type=code' +
        '&authorize_uri=' + encodeURIComponent(SYSJ_BASE + '/uaa/oauth/authorize');
      let r2 = await http.get(SYSJ_BASE + '/uaa/xidian/login?' + params);
      let b2 = r2.body || '';
      console.info(TAG, 'login page got, len=' + b2.length);

      // Step 3: CAS — http.get() 会把重定向链中 sysj 的 cookie 错存到 ids 域名
      // 先备份 ids/ehall cookie，CAS 完成后恢复，避免污染 portal 页面
      let idsBackup: string = http.getAllCookies('ids.xidian.edu.cn');
      let ehallBackup: string = http.getAllCookies('ehall.xidian.edu.cn');
      let casUrl = 'https://ids.xidian.edu.cn/authserver/oauth2.0/authorize?' +
        'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/uaa/xidian/callback') +
        '&response_type=code&state=' + state + '&client_id=1387116615722893312';
      let r3 = await http.get(casUrl);
      let b3 = r3.body || '';
      // 如果 body 里有 CAS 登录表单，说明 TGC 过期
      if (b3.indexOf('password') >= 0 && b3.indexOf('username') >= 0 && b3.indexOf('<form') >= 0) {
        this.onError('CAS 登录已过期，请先重新登录统一认证');
        return;
      }
      console.info(TAG, 'CAS done, body=' + b3.length);
      // CAS 重定向到 sysj 后，Set-Cookie 被 HttpUtil 按原始 URL 存到了 ids 域名
      // sysj OAuth 需要这些 cookie 在 sysj.xidian.edu.cn 下，复制一份
      http.copyCookiesForDomain('ids.xidian.edu.cn', 'sysj.xidian.edu.cn');
      // 恢复 ids/ehall 备份，撤销 CAS 步骤对 portal 页面的 cookie 污染
      http.replaceCookiesForDomain('ids.xidian.edu.cn', idsBackup);
      http.replaceCookiesForDomain('ehall.xidian.edu.cn', ehallBackup);

      // Step 4+5: 提取 code 和 password
      let code: string = '';
      let pwd: string = '';

      // 方式A：Step 3 CAS 响应 body 可能已走完整个 OAuth 链（如含 var password，直接提取）
      let cmA: RegExpMatchArray | null = b3.match(/var password = '([^']+)'/);
      if (cmA) {
        pwd = cmA[1];
        console.info(TAG, 'got pwd from CAS step, len=' + String(pwd.length));
      }

      // 方式B：调 /uaa/oauth/authorize 拿 code
      if (pwd.length === 0) {
        let oauthUrl: string = SYSJ_BASE + '/uaa/oauth/authorize?' +
          'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
          '&state=' + state + '&client_id=GvsunLims&response_type=code';
        let r4: HttpResponse = await http.get(oauthUrl);
        let b4: string = r4.body || '';
        console.info(TAG, 'step4 body len=' + String(b4.length) + ' head=' + b4.substring(0, 300));

        // 把 body 写入 PreferenceUtil 以便调试
        let debugStr: string = b4.replace(/\n/g, ' ').replace(/\r/g, '').replace(/\s+/g, ' ');
        // 找含 'code' 的行
        let codeIdx: number = debugStr.indexOf('code=');
        if (codeIdx >= 0) { console.info(TAG, 'codeSnippet=' + debugStr.substring(Math.max(0, codeIdx-60), codeIdx+100)); }
        let cbIdx: number = debugStr.indexOf('/webapp/callback');
        if (cbIdx >= 0) { console.info(TAG, 'cbSnippet=' + debugStr.substring(Math.max(0, cbIdx-60), cbIdx+100)); }

        // 多种 regex 试 code
        let cm4: RegExpMatchArray | null = b4.match(/[?&]code=([a-zA-Z0-9]+)/);
        if (!cm4) { cm4 = b4.match(/["']code["']\s*:\s*["']([^"']+)["']/); }
        if (!cm4) { cm4 = b4.match(/window\.location.*?[?&]code=([a-zA-Z0-9]+)/); }
        if (!cm4) { cm4 = b4.match(/url=.*?[?&]code=([a-zA-Z0-9]+)/); }
        if (cm4) { code = cm4[1]; console.info(TAG, 'code=' + code); }

        // 方式C：用 code 去 callback 拿 password
        if (code.length > 0) {
          let r5: HttpResponse = await http.get(SYSJ_BASE + '/xidian/webapp/callback?code=' + code + '&state=' + state);
          let b5: string = r5.body || '';
          console.info(TAG, 'step5 body len=' + String(b5.length) + ' head=' + b5.substring(0, 200));
          let pm: RegExpMatchArray | null = b5.match(/var password = '([^']+)'/);
          if (pm) { pwd = pm[1]; }
          // fallback: CAS response
          if (pwd.length === 0) {
            pm = b3.match(/var password = '([^']+)'/);
            if (pm) { pwd = pm[1]; }
          }
        }
      }

      if (pwd.length === 0) {
        console.info(TAG, 'failed: b3=' + b3.substring(0, 500));
        this.onError('无法获取实验系统登录密码');
        return;
      }
      console.info(TAG, 'pwd len=' + String(pwd.length));

      // Step 6: POST sysj login
      let loginBody = 'username=' + encodeURIComponent(account) + '&password=' + encodeURIComponent(pwd);
      let r6 = await http.postRaw(SYSJ_BASE + '/xidian/webapp/login', loginBody, 'application/x-www-form-urlencoded');
      console.info(TAG, 'sysj login result: status=' + r6.statusCode);

      // Step 7: 逐周获取数据
      let allItems: SysjScheduleItem[] = [];
      for (let w = 1; w <= MAX_WEEKS; w++) {
        try {
          let r7 = await http.get(SYSJ_BASE + '/xidian/schedule/myScheduleInfoAjax?termId=' + TERM_ID + '&week=' + String(w));
          if (r7.isOk && r7.body.length > 0 && r7.body.charAt(0) === '[') {
            let raw = JSON.parse(r7.body) as Object[];
            for (let i = 0; i < raw.length; i++) {
              let d = raw[i] as Object[];
              if (d.length < 15) continue;
              let item: SysjScheduleItem = {
                courseCode: (d[0] as string) || '', experimentName: (d[1] as string) || '',
                department: (d[2] as string) || '', lab: (d[11] as string) || '',
                weekday: (d[4] as string) || '', startSection: (d[5] as string) || '',
                endSection: (d[6] as string) || '', week: (d[7] as string) || '',
                unknown8: (d[8] as string) || '', teacher: (d[9] as string) || '',
                unknown10: (d[10] as string) || '', className: (d[12] as string) || '',
                groupId: (d[12] as string) || '', studentCount: (d[13] as string) || '',
                experimentProject: (d[14] as string) || '', __week: w
              } as SysjScheduleItem;
              allItems.push(item);
            }
          }
        } catch (e) {
          console.warn(TAG, 'week ' + w + ' err: ' + String(e));
        }
        this.fetchProgress = '(' + w + '/' + MAX_WEEKS + ')';
      }
      console.info(TAG, 'fetched=' + allItems.length);

      if (allItems.length > 0) {
        let co: ESObject = { 'ts': Date.now(), 'data': allItems } as ESObject;
        PreferenceUtil.putString(CACHE_KEY, JSON.stringify(co));
      }
      this.buildCards(allItems);
      await this.fetchPhysicsExperiment();
      if (this.cards.length === 0) {
        this.onError('暂无实验信息');
      }
    } catch (e) {
      console.error(TAG, 'error: ' + String(e));
      this.onError('实验系统登录失败: ' + String(e));
    }
  }

  parseWeekData(body: string, week: number, out: SysjScheduleItem[]): void {
    try {
      if (body.length === 0 || body.charAt(0) !== '[') { return; }
      let raw: Object[] = JSON.parse(body) as Object[];
      for (let i: number = 0; i < raw.length; i++) {
        let d: Object[] = raw[i] as Object[];
        if (d.length < 15) { continue; }
        let item: SysjScheduleItem = {
          courseCode: (d[0] as string) || '', experimentName: (d[1] as string) || '',
          department: (d[2] as string) || '', lab: (d[11] as string) || '',
          weekday: (d[4] as string) || '', startSection: (d[5] as string) || '',
          endSection: (d[6] as string) || '', week: (d[7] as string) || '',
          unknown8: (d[8] as string) || '', teacher: (d[9] as string) || '',
          unknown10: (d[10] as string) || '', className: (d[12] as string) || '',
          groupId: (d[12] as string) || '', studentCount: (d[13] as string) || '',
          experimentProject: (d[14] as string) || '', __week: week
        } as SysjScheduleItem;
        out.push(item);
      }
    } catch (e) { /* non-critical */ }
  }

  buildCards(items: SysjScheduleItem[]): void {
    let cmap: Map<string, ExpCard> = new Map();
    let ss = SemesterUtil.getSemesterStartDate(SemesterUtil.getCurrentSemesterCode());
    let today = formatDate(new Date());
    let dm = 86400000;
    for (let it of items) {
      let en = it.experimentName || '\u672a\u77e5\u5b9e\u9a8c';
      let lab = it.lab || '';
      let wd = parseInt(it.weekday) || 1;
      let ss2 = parseInt(it.startSection) || 1;
      let es = parseInt(it.endSection) || 1;
      let wn = parseInt(it.week) || 1;
      if (wn <= 0 || wn > 20) continue;
      let t = ss.getTime() + (wn - 1) * 7 * dm + (wd - 1) * dm;
      let date = formatDate(new Date(t));
      let sn = '\u7b2c' + ss2 + '-' + es + '\u8282';
      let key = date + '_' + ss2;
      let card = cmap.get(key);
      if (!card) {
        card = {
          date: date, weekdayName: getWeekdayName(wd), weekNum: wn,
          sectionName: sn, isCompleted: date < today, experimentName: en,
          lab: lab, teacher: it.teacher || '', experimentProject: it.experimentProject || '',
          className: it.className || ''
        } as ExpCard;
        cmap.set(key, card);
      }
      if (it.experimentProject && card.experimentProject.indexOf(it.experimentProject) < 0)
        card.experimentProject += ' | ' + it.experimentProject;
    }
    let sk: string[] = []; cmap.forEach((_v: ExpCard, k: string) => { sk.push(k); }); sk.sort();
    let up: ExpCard[] = []; let cm: ExpCard[] = [];
    for (let k of sk) { let c = cmap.get(k); if (c) { if(c.isCompleted)cm.push(c); else up.push(c); } }
    this.cards = up.concat(cm);
  }

  async fetchPhysicsExperiment(): Promise<void> {
    let pwd = PreferenceUtil.getString('physics_pwd');
    if (pwd.length === 0) { if(this.cards.length===0)this.onError('\u6682\u65e0\u5b9e\u9a8c\u4fe1\u606f'); else this.pageState=PageState.SUCCESS; return; }
    try {
      let pi: SysjScheduleItem[] = [];
      let cached = PreferenceUtil.getString(PHYSICS_CACHE_KEY);
      if (cached.length > 0) {
        let c = JSON.parse(cached) as Record<string, Object>;
        if (Date.now()-(c['ts'] as number)<CACHE_TTL && ((c['data'] as Object[])).length>0) pi = c['data'] as SysjScheduleItem[];
      }
      if (pi.length === 0) {
        let http = HttpUtil.getInstance();
        let bd = '__EVENTTARGET=&__EVENTARGUMENT=&__VIEWSTATE=%2FwEPDwUKMTEzNzM0MjM0OWQYAQUeX19Db250cm9sc1JlcXVpcmVQb3N0QmFja0tleV9fFgEFD2xvZ2luMSRidG5Mb2dpbkOuzGVaztce4Ict7jsIJ0F5pUDb%2BsmSbCCrNVSBlPML&__VIEWSTATEGENERATOR=EE008CD9&__EVENTVALIDATION=%2FwEdAAcKecdPGDB%2BfW8Tyghx7AeSpOzeiNZ7aaEg5p6LqSa9cODI2bZwNtRxUKPkisVLf8l8Vv4WhRVIIhZlyYNJO%2BySrDKOhP%2B%2FYMNbVIh74hA2rCYnBBSTsX9SjxiYNNk%2B5kglM%2B6pGIq22Oi5mNu6u6eC2WEBfKAmATKwSpsOL%2FPNcRyi9l8Dnp6JamksyAzjhW4%3D&login1%24StuLoginID='+encodeURIComponent(PreferenceUtil.getString('ids_account'))+'&login1%24StuPassword='+encodeURIComponent(pwd)+'&login1%24UserRole=Student&login1%24btnLogin.x=28&login1%24btnLogin.y=14';
        await http.postRaw('http://wlsy.xidian.edu.cn/PhyEws/default.aspx', bd, 'application/x-www-form-urlencoded');
        let r = await http.get('http://wlsy.xidian.edu.cn/PhyEws/student/select.aspx');
        if (r.isOk) {
          pi = this.parsePhysicsHtml(r.body);
          let pc: ESObject = {'ts':Date.now(),'data':pi} as ESObject;
          PreferenceUtil.putString(PHYSICS_CACHE_KEY, JSON.stringify(pc));
        }
      }
      if (pi.length > 0) this.buildCards(pi);
    } catch (e) { console.warn(TAG, 'physics err: '+String(e)); }
    if(this.cards.length===0)this.onError('\u6682\u65e0\u5b9e\u9a8c\u4fe1\u606f'); else this.pageState=PageState.SUCCESS;
  }

  parsePhysicsHtml(html: string): SysjScheduleItem[] {
    let items: SysjScheduleItem[] = [];
    let trs = html.match(/<tr[^>]*>[\s\S]*?<\/tr>/gi);
    if (!trs) return items;
    for (let tr of trs) {
      let tds: string[] = []; let tm: RegExpExecArray|null; let tr2 = new RegExp(/<td[^>]*>([\s\S]*?)<\/td>/gi);
      while((tm=tr2.exec(tr))!==null) tds.push(tm[1].replace(/<[^>]+>/g,'').replace(/&nbsp;/g,' ').trim());
      if (tds.length<10||tds[1].length===0) continue;
      let dp = (tds[4]||'').split('/'); let isPM = (tds[3]||'').includes('15');
      let it: SysjScheduleItem = {
        courseCode:'', experimentName:'\u269b '+tds[1], department:'',
        lab:tds[5]||'', weekday:'0', startSection:isPM?'7':'9', endSection:isPM?'9':'11',
        week:'0', unknown8:'', teacher:tds[9]||'', unknown10:'', className:'',
        groupId:'', studentCount:'', experimentProject:tds[8]||'', __week:0
      } as SysjScheduleItem;
      if(dp.length>=3){
        let dt = new Date(parseInt(dp[2]),parseInt(dp[0])-1,parseInt(dp[1]));
        it.weekday=String(dt.getDay()===0?7:dt.getDay());
        let ss2=SemesterUtil.getSemesterStartDate(SemesterUtil.getCurrentSemesterCode());
        it.week=String(Math.floor((dt.getTime()-ss2.getTime())/86400000/7)+1);
        it.startSection=isPM?'7':'9'; it.endSection=isPM?'9':'11';
      }
      items.push(it);
    }
    return items;
  }

  onError(msg: string) { this.errorMsg=msg; this.pageState=PageState.ERROR; }

  build() {
    NavDestination() {
      Column() {
        if (this.pageState===PageState.LOADING) {
          Column() {
            LoadingProgress().width(40).height(40).color((AppStorage.get('accent_color') as string ?? '#2979FF'))
            Text(this.statusText).fontSize(14).fontColor(ThemeColors.textSecondary).margin({top:12})
            if(this.fetchProgress.length>0) Text(this.fetchProgress).fontSize(12).fontColor(ThemeColors.textSecondary).margin({top:8})
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else if (this.pageState===PageState.ERROR) {
          Column() {
            Text('\ud83d\udccb').fontSize(48)
            Text(this.errorMsg).fontSize(15).fontColor(ThemeColors.textSecondary).margin({top:12})
            Row() {
              Button('\u91cd\u8bd5').fontSize(14).fontColor('#FFFFFF').backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).borderRadius(20).height(36).margin({top:20,right:12}).onClick(()=>{this.doHttpSSOAndFetch();})
              Button('\u91cd\u65b0\u767b\u5f55').fontSize(14).fontColor('#FFFFFF').backgroundColor('#E53935').borderRadius(20).height(36).margin({top:20}).onClick(()=>{PreferenceUtil.putBool('is_logged_in',false);PreferenceUtil.putString('mod_auth_cas','');router.pushUrl({url:'pages/login/LoginPage'});})
            }
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).padding(24)
        } else if (this.pageState===PageState.IDLE) {
          Column() {
            Text('\ud83e\uddea').fontSize(48)
            Text('\u5b9e\u9a8c\u7cfb\u7edf\u9700\u8981\u5355\u72ec\u767b\u5f55').fontSize(15).fontColor(ThemeColors.textSecondary).margin({top:12})
            Text('\u5c06\u81ea\u52a8\u901a\u8fc7\u7edf\u4e00\u8ba4\u8bc1\u767b\u5f55').fontSize(13).fontColor(ThemeColors.textSecondary).margin({top:6})
            Button('\u8fdb\u5165\u5b9e\u9a8c\u7cfb\u7edf').fontSize(14).fontColor('#FFFFFF').backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).borderRadius(20).height(40).margin({top:20}).onClick(()=>{this.doHttpSSOAndFetch();})
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).padding(24)
        } else if (this.pageState===PageState.SUCCESS) {
          if (this.showCacheBanner) {
            Row() {
              Text('📦 当前显示缓存数据').fontSize(12).fontColor('#E65100')
              Text('  刷新').fontSize(12).fontColor(this.accentColor)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .border({ width: 1, color: this.accentColor, radius: 4 })
                .margin({ left: 10 })
                .onClick(() => { this.doHttpSSOAndFetch(); })
            }.width('100%').height(32).justifyContent(FlexAlign.Center)
            .backgroundColor(this.themeIsDark ? '#3E2723' : '#FFF3E0')
          }
          if(this.cards.length===0) {
            Column() {
              Text('\ud83e\uddea').fontSize(48)
              Text('\u6682\u65e0\u5b9e\u9a8c\u4fe1\u606f').fontSize(15).fontColor(ThemeColors.textSecondary).margin({top:12})
              Button('\u5237\u65b0').fontSize(14).fontColor('#FFFFFF').backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).borderRadius(20).height(36).margin({top:20}).onClick(()=>{PreferenceUtil.putString(CACHE_KEY,'');this.doHttpSSOAndFetch();})
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).padding(24)
          } else {
            Refresh({refreshing:$$this.isRefreshing}) {
              Scroll() {
                Column() {
                  ForEach(this.cards, (card:ExpCard)=>{this.ExpCardBuilder(card)},(card:ExpCard)=>card.date+'_'+card.sectionName)
                }.width('100%').padding({left:16,right:16,top:8,bottom:16})
              }.width('100%').layoutWeight(1)
            }.onRefreshing(()=>{PreferenceUtil.putString(CACHE_KEY,'');this.isRefreshing=false;this.doHttpSSOAndFetch();})
          }
        }
      }.width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
    }.title('\u5b9e\u9a8c\u4fe1\u606f', { backgroundColor: this.accentColor })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .backgroundColor(ThemeColors.bgPage)
  }

  @Builder
  ExpCardBuilder(card: ExpCard) {
    Column() {
      Row() {
        if(card.isCompleted) Text('\u2705').fontSize(16).margin({right:6})
        Text(card.experimentName).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).layoutWeight(1).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis})
      }.width('100%').margin({bottom:6})
      Row() { Text('\ud83d\udcc5').fontSize(13).margin({right:4}); Text(card.date+' '+card.weekdayName+' \u7b2c'+card.weekNum+'\u5468').fontSize(13).fontColor(ThemeColors.textSecondary) }.width('100%').margin({bottom:4})
      Row() { Text('\ud83d\udd50').fontSize(13).margin({right:4}); Text(card.sectionName).fontSize(13).fontColor(ThemeColors.textSecondary) }.width('100%').margin({bottom:4})
      if(card.lab.length>0) { Row() { Text('\ud83d\udccd').fontSize(13).margin({right:4}); Text(card.lab).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis}) }.width('100%').margin({top:2}) }
      if(card.teacher.length>0) { Row() { Text('\ud83d\udc68\u200d\ud83c\udfeb').fontSize(13).margin({right:4}); Text(card.teacher).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis}) }.width('100%').margin({top:2}) }
      if(card.experimentProject.length>0) { Row() { Text('\ud83d\udcdd').fontSize(13).margin({right:4}); Text(card.experimentProject).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(2).textOverflow({overflow:TextOverflow.Ellipsis}).layoutWeight(1) }.width('100%').margin({top:2}) }
      if(card.className.length>0) { Row() { Text('\ud83d\udc65').fontSize(13).margin({right:4}); Text(card.className).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis}) }.width('100%').margin({top:2}) }
    }.width('100%').padding(14).borderRadius(12).backgroundColor(ThemeColors.bgCard).margin({top:8}).alignItems(HorizontalAlign.Start).border({width:{bottom:1,right:1,top:1,left:1},color:'#E0E0E0',radius:12})
  }
}
