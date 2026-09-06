import { AccentColors } from '../../utils/AccentColors';
// ExperimentPage.ets - 实验信息页面（HTTP 数据获取）
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';
import { ThemeColors } from '../../utils/ThemeColors';
import { SemesterUtil } from '../../services/ids/EhallService';
import { ExperimentService } from '../../services/experiment/ExperimentService';
import { PhysicsScoreService, PhysicsScoreResult } from '../../services/experiment/PhysicsScoreService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SecureStorageUtil, SecureAlias } from '../../utils/SecureStorageUtil';

const TAG = 'ExperimentPage';
const WEEKDAY_NAMES: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const CACHE_KEY = 'sysj_exp_cache';
const PHYSICS_CACHE_KEY = 'physics_exp_cache';
const CACHE_TTL = 4 * 60 * 60 * 1000;
const TERM_ID = '2003';
const SYSJ_BASE = 'https://sysj.xidian.edu.cn';
const MAX_WEEKS = 25;
// 成绩识别 8 分钟内存记忆（模块级：跨页面实例生效，避免反复进出实验页重复起 wgyreport 会话）
let gLastScoreFetchTs: number = 0;

// 节次钟点表（下标即节次 1..11，与 ClassTablePage 一致）——把「第x-y节」换算成绝对钟点，
// 用于时间线三分类（进行中/未完成/已完成），对齐 Flutter 按 timeRange 判定的语义
const SECT_TIMES: string[] = [
  '', '8:30-9:15', '9:20-10:05', '10:25-11:10', '11:15-12:00',
  '14:00-14:45', '14:50-15:35', '15:55-16:40', '16:45-17:30',
  '19:00-19:45', '19:55-20:35', '20:40-21:25'
];

function sectStart(s: number): string {
  if (s >= 1 && s < SECT_TIMES.length) {
    const p: string[] = SECT_TIMES[s].split('-');
    return p.length > 0 ? p[0] : '';
  }
  return '';
}

function sectEnd(s: number): string {
  if (s >= 1 && s < SECT_TIMES.length) {
    const p: string[] = SECT_TIMES[s].split('-');
    return p.length > 1 ? p[1] : '';
  }
  return '';
}

enum PageState { IDLE, LOADING, SUCCESS, ERROR }

interface SysjScheduleItem {
  courseCode: string; experimentName: string; department: string; lab: string;
  weekday: string; startSection: string; endSection: string; week: string;
  unknown8: string; teacher: string; unknown10: string; className: string;
  groupId: string; studentCount: string; experimentProject: string; __week: number;
  isPhysics?: boolean;  // true=wlsy 物理实验（真实场次钟点），缺省=sysj 其他实验（节次换算）
}

interface ExpCard {
  date: string; weekdayName: string; weekNum: number; sectionName: string;
  startSection: number;       // 分组排序/去重键用
  startTime: string;          // 开始钟点 HH:mm（物理=真实场次；其他=节次表换算）
  endTime: string;            // 结束钟点 HH:mm
  isPhysics: boolean;         // 物理实验卡（时间行显示绝对场次窗口）
  experimentName: string; lab: string; teacher: string;
  experimentProject: string; className: string;
}

function formatDate(d: Date): string { let m=String(d.getMonth()+1).padStart(2,'0'); let day=String(d.getDate()).padStart(2,'0'); return d.getFullYear()+'-'+m+'-'+day; }
function getWeekdayName(w: number): string { let i=w-1; return (i>=0&&i<7)?WEEKDAY_NAMES[i]:''; }

@Component
export struct ExperimentPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  pageInfo: NavPathStack = new NavPathStack();
  @State pageState: PageState = PageState.IDLE;
  @State statusText: string = '';
  @State errorMsg: string = '';
  @State showCacheBanner: boolean = false;
  @State cards: ExpCard[] = [];
  @State doingCards: ExpCard[] = [];      // 正在进行实验（当前时刻处于场次窗口内）
  @State upcomingCards: ExpCard[] = [];   // 未完成实验（场次开始时间在未来）
  @State doneCards: ExpCard[] = [];       // 已完成实验（场次已结束）
  @State fetchProgress: string = '';
  @State private isRefreshing: boolean = false;
  // 物理实验成绩角标（wgyreport 识别）：规整实验名 → 识别结果；空 Map=未识别/识别失败
  @State physicsScores: Record<string, PhysicsScoreResult> = {};
  // 成绩详情半屏（对齐 Flutter 点击成绩 chip 弹图片+预测分）
  @State showScoreSheet: boolean = false;
  @State sheetExpName: string = '';
  @State sheetScoreLabel: string = '';
  @State sheetScoreFound: boolean = false;
  @State sheetScoreUrl: string = '';
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

    @Builder buildWhiteTitle(t: string) {
    Row() {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        Image($r('app.media.close'))
          .height(22)
          .fillColor(ThemeColors.textPrimary)
          .draggable(false)
      }
      .height(40).width(40)
      .hoverEffect(HoverEffect.Auto).onClick(() => { this.pageInfo.pop(); })
      Text(t)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(AccentColors.textContrast)
        .layoutWeight(1)
    }
    .width('100%')
    .height(52 + this.statusBarHeight)
    .padding({ left: 12, right: 16, top: this.statusBarHeight })
  }

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
    // 物理实验内部已设置更具体的错误（无密码引导/登录失败原因）时不覆盖
    if (this.cards.length === 0 && !this.isErrorState()) this.onError('暂无实验信息');
    else if (!this.isErrorState()) this.pageState = PageState.SUCCESS;
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
        if (allItems.length > 0) {
          let co: ESObject = { 'ts': Date.now(), 'data': allItems } as ESObject;
          PreferenceUtil.putString(CACHE_KEY, JSON.stringify(co));
        }
        this.buildCards(allItems);
        this.showCacheBanner = false;
        // 已登录会话下也顺带刷新物理实验（此前直接 return 会跳过物理实验加载）
        await this.fetchPhysicsExperiment();
        if (!this.isErrorState()) {
          if (this.cards.length === 0) this.onError('暂无实验信息');
          else this.pageState = PageState.SUCCESS;
        }
        return;
      }

      // === Step 1: 从 sysj OAuth 重定向链提取真实 state ===
      let state: string = '';
      let r1: HttpResponse = await http.get(SYSJ_BASE + '/xidian/test');
      let b1: string = r1.body || '';
      let om: RegExpMatchArray | null = b1.match(/[?&]state=([a-f0-9\-]{20,50})/i);
      if (om) { state = om[1];}

      // 如果 body 没有，试用 getNoRedirect 拦截重定向
      if (state.length === 0) {
        for (let a: number = 0; a < 4; a++) {
          let sr: HttpResponse = await http.getNoRedirect(SYSJ_BASE + '/xidian/test');
          if (sr.location && sr.location.length > 0) {
            let om2: RegExpMatchArray | null = sr.location.match(/[?&]state=([^&]+)/);
            if (om2) { state = om2[1]; break; }
            // 跟随这个重定向继续找
            let nextUrl: string = sr.location;
            if (!nextUrl.startsWith('http')) { nextUrl = SYSJ_BASE + (nextUrl.startsWith('/')?nextUrl:'/'+nextUrl); }
            let sr2: HttpResponse = await http.getNoRedirect(nextUrl);
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

      // === Step 2: sysj OAuth → CAS OAuth authorize ===
      let params = 'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
        '&state=' + state + '&client_id=GvsunLims&response_type=code' +
        '&authorize_uri=' + encodeURIComponent(SYSJ_BASE + '/uaa/oauth/authorize');
      let r2 = await http.get(SYSJ_BASE + '/uaa/xidian/login?' + params);
      let b2 = r2.body || '';

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
      }

      // 方式B：调 /uaa/oauth/authorize 拿 code
      if (pwd.length === 0) {
        let oauthUrl: string = SYSJ_BASE + '/uaa/oauth/authorize?' +
          'redirect_uri=' + encodeURIComponent(SYSJ_BASE + '/xidian/webapp/callback') +
          '&state=' + state + '&client_id=GvsunLims&response_type=code';
        let r4: HttpResponse = await http.get(oauthUrl);
        let b4: string = r4.body || '';

        // 多种 regex 试 code
        let cm4: RegExpMatchArray | null = b4.match(/[?&]code=([a-zA-Z0-9]+)/);
        if (!cm4) { cm4 = b4.match(/["']code["']\s*:\s*["']([^"']+)["']/); }
        if (!cm4) { cm4 = b4.match(/window\.location.*?[?&]code=([a-zA-Z0-9]+)/); }
        if (!cm4) { cm4 = b4.match(/url=.*?[?&]code=([a-zA-Z0-9]+)/); }
        if (cm4) { code = cm4[1]; }

        // 方式C：用 code 去 callback 拿 password
        if (code.length > 0) {
          let r5: HttpResponse = await http.get(SYSJ_BASE + '/xidian/webapp/callback?code=' + code + '&state=' + state);
          let b5: string = r5.body || '';
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
        this.onError('无法获取实验系统登录密码');
        return;
      }

      // Step 6: POST sysj login
      let loginBody = 'username=' + encodeURIComponent(account) + '&password=' + encodeURIComponent(pwd);
      let r6 = await http.postRaw(SYSJ_BASE + '/xidian/webapp/login', loginBody, 'application/x-www-form-urlencoded');

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
        }
        this.fetchProgress = '(' + w + '/' + MAX_WEEKS + ')';
      }

      if (allItems.length > 0) {
        let co: ESObject = { 'ts': Date.now(), 'data': allItems } as ESObject;
        PreferenceUtil.putString(CACHE_KEY, JSON.stringify(co));
      }
      this.buildCards(allItems);
      await this.fetchPhysicsExperiment();
      // 物理实验已给出更具体的错误（无密码引导/登录失败原因）时不覆盖
      if (this.cards.length === 0 && !this.isErrorState()) {
        this.onError('暂无实验信息');
      }
    } catch (e) {
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

  // 统一卡片构建：sysj(其他实验) 与 wlsy(物理实验) 分多次喂入——
  // 先并入已有卡片再叠加本次数据，避免后一次调用覆盖前一次；最后按绝对钟点做时间线三分类。
  buildCards(items: SysjScheduleItem[]): void {
    let cmap: Map<string, ExpCard> = new Map();
    for (let old of this.cards) {
      cmap.set(old.date + '_' + String(old.startSection), old);
    }
    let ss = SemesterUtil.getSemesterStartDate(SemesterUtil.getCurrentSemesterCode());
    let today = formatDate(new Date());
    let dm = 86400000;
    for (let it of items) {
      let en = it.experimentName || '\u672a\u77e5\u5b9e\u9a8c';
      let lab = it.lab || '';
      let wd = parseInt(it.weekday) || 1;
      let ss2 = parseInt(it.startSection) || 1;
      let es = parseInt(it.endSection) || ss2;
      let wn = parseInt(it.week) || 1;
      if (wn <= 0 || wn > 20) continue;
      let t = ss.getTime() + (wn - 1) * 7 * dm + (wd - 1) * dm;
      let date = formatDate(new Date(t));
      let sn = '\u7b2c' + ss2 + '-' + es + '\u8282';
      // 物理实验（解析器统一带 ⚛ 前缀或显式标记）：按真实场次窗口；其他实验按节次表换算钟点
      let isPhysics = it.isPhysics === true || en.indexOf('\u269b') === 0;
      let startTime = '';
      let endTime = '';
      if (isPhysics) {
        startTime = ss2 === 7 ? '15:55' : '18:30';
        endTime = ss2 === 7 ? '18:10' : '20:45';
      } else {
        startTime = sectStart(ss2);
        endTime = sectEnd(es);
      }
      let key = date + '_' + ss2;
      let card = cmap.get(key);
      if (!card) {
        card = {
          date: date, weekdayName: getWeekdayName(wd), weekNum: wn,
          sectionName: sn, startSection: ss2, startTime: startTime, endTime: endTime,
          isPhysics: isPhysics, experimentName: en, lab: lab, teacher: it.teacher || '',
          experimentProject: it.experimentProject || '', className: it.className || ''
        } as ExpCard;
        cmap.set(key, card);
      }
      if (it.experimentProject && card.experimentProject.indexOf(it.experimentProject) < 0)
        card.experimentProject += ' | ' + it.experimentProject;
    }
    let sk: string[] = [];
    cmap.forEach((_v: ExpCard, k: string) => { sk.push(k); });
    sk.sort();
    let merged: ExpCard[] = [];
    for (let k of sk) { let c = cmap.get(k); if (c) merged.push(c); }

    // 时间线三分类（对齐 Flutter TimelineWidget：进行中→未完成→已完成），组内按日期+节次升序
    let now = Date.now();
    let doing: ExpCard[] = [];
    let up: ExpCard[] = [];
    let dn: ExpCard[] = [];
    for (let c of merged) {
      if (c.startTime.length === 0) {
        // 节次越界无法换算钟点：仅按日期粗分（今天及以后视为未完成）
        if (c.date < today) dn.push(c);
        else up.push(c);
        continue;
      }
      let d0 = c.date.split('-');
      let sh = parseInt(c.startTime.split(':')[0]);
      let sm = parseInt(c.startTime.split(':')[1]);
      let eh = parseInt(c.endTime.split(':')[0]);
      let em = parseInt(c.endTime.split(':')[1]);
      let sTs = new Date(parseInt(d0[0]), parseInt(d0[1]) - 1, parseInt(d0[2]), sh, sm).getTime();
      let eTs = new Date(parseInt(d0[0]), parseInt(d0[1]) - 1, parseInt(d0[2]), eh, em).getTime();
      if (eTs <= now) dn.push(c);
      else if (sTs <= now) doing.push(c);
      else up.push(c);
    }
    this.doingCards = doing;
    this.upcomingCards = up;
    this.doneCards = dn;
    this.cards = merged;
  }

  async fetchPhysicsExperiment(): Promise<void> {
    let pwd = await SecureStorageUtil.get(SecureAlias.PHYSICS_PWD);
    // P1-b：未设置物理实验密码时给明确引导（此前显示"暂无实验信息"误导用户）
    if (pwd.length === 0) {
      if (this.cards.length === 0) {
        this.errorMsg = '未设置物理实验密码：物理实验（wlsy）需独立密码，请到「我的」页 → 物理实验设置 中填写后刷新';
        this.pageState = PageState.ERROR;
      } else {
        this.pageState = PageState.SUCCESS;
      }
      return;
    }
    let failMsg = '';
    try {
      let pi: SysjScheduleItem[] = [];
      let cached = PreferenceUtil.getString(PHYSICS_CACHE_KEY);
      if (cached.length > 0) {
        let c = JSON.parse(cached) as Record<string, Object>;
        if (Date.now()-(c['ts'] as number)<CACHE_TTL && ((c['data'] as Object[])).length>0) pi = c['data'] as SysjScheduleItem[];
      }
      if (pi.length === 0) {
        // 共享登录+取页：登录失败会抛带 login1_Label1 原始文案的 Error（如"学号或密码错误"），
        // 不再把失败响应当成功解析出空列表、误报"暂无实验信息"
        const html = await ExperimentService.physicsFetchScheduleHtml(
          PreferenceUtil.getString('ids_account'), pwd);
        const startTs = SemesterUtil.getSemesterStartDate(SemesterUtil.getCurrentSemesterCode()).getTime();
        pi = this.toSysjItems(ExperimentService.parsePhysicsHtml(html, startTs));
        let pc: ESObject = {'ts':Date.now(),'data':pi} as ESObject;
        PreferenceUtil.putString(PHYSICS_CACHE_KEY, JSON.stringify(pc));
      }
      if (pi.length > 0) this.buildCards(pi);
      // 成绩角标：wgyreport 独立会话识别，不 await 阻塞排课；失败静默=无角标（对齐 Flutter getData）
      this.refreshPhysicsScores(pwd);
    } catch (e) {
      // 失败原因（密码错误/网络异常）直接透出，不再一律显示"暂无实验信息"误导用户
      failMsg = e instanceof Error ? e.message : String(e);
      console.warn('[ExperimentPage] fetchPhysicsExperiment failed: ' + failMsg);
    }
    if (this.cards.length === 0) {
      this.onError(failMsg.length > 0 ? ('实验信息获取失败：' + failMsg) : '暂无实验信息');
    } else {
      // 已有卡片（sysj 实验）但物理实验失败：顶部横幅提示，不全页报错
      if (failMsg.length > 0) {
        this.errorMsg = '实验信息获取失败：' + failMsg;
        this.showCacheBanner = true;
      }
      this.pageState = PageState.SUCCESS;
    }
  }

  // ===== 物理实验成绩角标（移植 Flutter image_recognition + physics_experiment_session）=====

  // 成绩识别入口：逐图下载→左上角 50×20 像素 FNV-1a 哈希→查 12 项哈希表→按实验名回填。
  // 内部 8 分钟记忆，避免同一页面反复进出时重复起 wgyreport 会话；识别失败静默清空角标。
  private async refreshPhysicsScores(pwd: string): Promise<void> {
    const account: string = PreferenceUtil.getString('ids_account');
    if (account.length === 0 || pwd.length === 0) return;
    if (Date.now() - gLastScoreFetchTs < 8 * 60 * 1000) return; // 命中内存记忆
    gLastScoreFetchTs = Date.now();
    try {
      const raw: Record<string, PhysicsScoreResult> =
        await PhysicsScoreService.getInstance().recognizeAllScores(account, pwd);
      const res: Record<string, PhysicsScoreResult> = {};
      const keys: string[] = Object.keys(raw);
      for (let i = 0; i < keys.length; i++) {
        res[PhysicsScoreService.normalizeName(keys[i])] = raw[keys[i]];
      }
      this.physicsScores = res;
      console.info('[ExperimentPage] physics scores recognized: ' + String(Object.keys(res).length));
    } catch (e) {
      // 识别失败静默（对齐 Flutter getData 的 try/catch：跳过识别不阻塞排课）
      console.warn('[ExperimentPage] refreshPhysicsScores failed: ' + String(e));
      this.physicsScores = {};
    }
  }

  // 物理卡 → 该实验名对应识别结果；无角标（非物理/未识别/未命中名单）返回 undefined
  private scoreOf(card: ExpCard): PhysicsScoreResult | undefined {
    if (!card.isPhysics) return undefined;
    const key: string = PhysicsScoreService.normalizeName(card.experimentName);
    if (key.length === 0) return undefined;
    const r = this.physicsScores[key];
    return r ? r : undefined;
  }

  private scoreChipVisible(card: ExpCard): boolean {
    return this.scoreOf(card) !== undefined;
  }

  private scoreChipText(card: ExpCard): string {
    const sr = this.scoreOf(card);
    if (!sr) return '';
    if (!sr.found) return '查看成绩';
    // 提交状态图（无数字分）直接显示状态；数字分带"成绩 "前缀
    if (sr.label === '已上传' || sr.label === '未上传') return sr.label;
    return '成绩 ' + sr.label;
  }

  private openScoreSheet(card: ExpCard): void {
    const sr = this.scoreOf(card);
    if (!sr) return;
    this.sheetExpName = card.experimentName;
    this.sheetScoreLabel = sr.label;
    this.sheetScoreFound = sr.found;
    this.sheetScoreUrl = sr.rawUrl;
    this.showScoreSheet = true;
  }

  // Record<string,string>（共享解析器产物）→ SysjScheduleItem（本页卡片消费模型）
  private toSysjItems(src: Record<string, string>[]): SysjScheduleItem[] {
    const out: SysjScheduleItem[] = [];
    for (let i = 0; i < src.length; i++) {
      const s = src[i];
      out.push({
        courseCode: s['courseCode'] || '', experimentName: s['experimentName'] || '',
        department: s['department'] || '', lab: s['lab'] || '',
        weekday: s['weekday'] || '', startSection: s['startSection'] || '',
        endSection: s['endSection'] || '', week: s['week'] || '',
        unknown8: '', teacher: s['teacher'] || '', unknown10: '',
        className: s['className'] || '', groupId: s['groupId'] || '',
        studentCount: s['studentCount'] || '', experimentProject: s['experimentProject'] || '',
        __week: 0, isPhysics: true
      } as SysjScheduleItem);
    }
    return out;
  }

  onError(msg: string) {
    // 有缓存数据时只显示横幅，不切换全页错误（对齐 Flutter）
    if (this.cards.length > 0) {
      this.errorMsg = msg;
      this.showCacheBanner = true;
      this.pageState = PageState.SUCCESS;
    } else {
      this.errorMsg = msg;
      this.pageState = PageState.ERROR;
    }
  }

  // 读取当前是否已处于错误态（用方法调用打断 ArkTS 对 this.pageState 的控制流收窄，
  // 避免"先赋 LOADING、后比 ERROR 无重叠"的 10505001 误报）
  private isErrorState(): boolean {
    return this.pageState === PageState.ERROR;
  }

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
              Button('\u91cd\u8bd5').fontSize(14).fontColor('#FFFFFF').backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).borderRadius(20).height(36).margin({top:20}).hoverEffect(HoverEffect.Auto).onClick(()=>{this.doHttpSSOAndFetch();})
            }
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).padding(24)
        } else if (this.pageState===PageState.IDLE) {
          Column() {
            Text('\ud83e\uddea').fontSize(48)
            Text('\u5b9e\u9a8c\u7cfb\u7edf\u9700\u8981\u5355\u72ec\u767b\u5f55').fontSize(15).fontColor(ThemeColors.textSecondary).margin({top:12})
            Text('\u5c06\u81ea\u52a8\u901a\u8fc7\u7edf\u4e00\u8ba4\u8bc1\u767b\u5f55').fontSize(13).fontColor(ThemeColors.textSecondary).margin({top:6})
            Button('\u8fdb\u5165\u5b9e\u9a8c\u7cfb\u7edf').fontSize(14).fontColor('#FFFFFF').backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).borderRadius(20).height(40).margin({top:20}).hoverEffect(HoverEffect.Auto).onClick(()=>{this.doHttpSSOAndFetch();})
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).padding(24)
        } else if (this.pageState===PageState.SUCCESS) {
          // 固定刷新行（考勤查询同款）
          Row() {
            Text('').layoutWeight(1)
            Button('刷新')
              .fontSize(12).height(30)
              .backgroundColor(this.accentColor + '18').fontColor(this.accentColor)
              .borderRadius(15).padding({ left: 12, right: 12 })
              .hoverEffect(HoverEffect.Auto).onClick(() => { PreferenceUtil.putString(CACHE_KEY, ''); this.doHttpSSOAndFetch(); })
          }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })
          if (this.showCacheBanner) {
            Row() {
              Text(this.errorMsg.length > 0 ? '⚠ ' + this.errorMsg : '📦 当前显示缓存数据').fontSize(12).fontColor('#BF4D00')
                .layoutWeight(1).maxLines(2)
              if (this.errorMsg.length > 0) {
                Button('重试').fontSize(12).height(26).backgroundColor(this.accentColor).fontColor('#FFFFFF')
                  .borderRadius(4).padding({ left: 8, right: 8 }).hoverEffect(HoverEffect.Auto).onClick(() => { this.doHttpSSOAndFetch(); })
              } else {
                Text('  刷新').fontSize(12).fontColor(this.accentColor)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .border({ width: 1, color: this.accentColor, radius: 4 })
                  .margin({ left: 10 })
                  .hoverEffect(HoverEffect.Auto).onClick(() => { this.doHttpSSOAndFetch(); })
              }
            }.width('100%').padding({ left: 16, right: 8, top: 6, bottom: 6 })
            .backgroundColor(this.themeIsDark ? '#3E2723' : '#FFF3E0')
          }
          if(this.cards.length===0) {
            Column() {
              Text('\ud83e\uddea').fontSize(48)
              Text('\u6682\u65e0\u5b9e\u9a8c\u4fe1\u606f').fontSize(15).fontColor(ThemeColors.textSecondary).margin({top:12})
              Button('\u5237\u65b0').fontSize(14).fontColor('#FFFFFF').backgroundColor((AppStorage.get('accent_color') as string ?? '#2979FF')).borderRadius(20).height(36).margin({top:20}).hoverEffect(HoverEffect.Auto).onClick(()=>{PreferenceUtil.putString(CACHE_KEY,'');this.doHttpSSOAndFetch();})
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).padding(24)
          } else {
            Scroll() {
              Column() {
                // 时间线三分类（对齐 Flutter：进行中→未完成→已完成）；进行中为空时整段隐藏
                if (this.doingCards.length > 0) {
                  this.ExpSection('正在进行实验', this.accentColor, '', this.doingCards)
                }
                this.ExpSection('未完成实验', '#BF4D00', '所有实验全部完成', this.upcomingCards)
                this.ExpSection('已完成实验', '#2E7D32', '目前没有已经完成的实验', this.doneCards)
              }.width('100%').padding({left:16,right:16,top:8,bottom:16}).alignItems(HorizontalAlign.Start)
            }.width('100%').layoutWeight(1)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
      }.width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
    }    .title({ builder: this.buildWhiteTitle('\u5b9e\u9a8c\u4fe1\u606f'), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
    .hideBackButton(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showScoreSheet, this.ScoreSheetBuilder, { height: 360, showClose: true, dragBar: true })
    
    .backgroundColor(ThemeColors.bgPage)
  }

  // 时间行文案：物理实验=真实场次绝对钟点（对齐 Flutter 卡片 HH:mm~HH:mm）；其他实验保留「第x-y节」
  private cardTimeText(card: ExpCard): string {
    if (card.isPhysics) {
      return (card.startSection === 7 ? '下午 15:55-18:10' : '晚上 18:30-20:45');
    }
    return card.sectionName;
  }

  // 时间线小节：圆点标题 + 卡片列表；列表为空时展示占位文案（对齐 Flutter 空段提示）
  @Builder
  ExpSection(title: string, dotColor: string, emptyHint: string, list: ExpCard[]) {
    Column() {
      Row() {
        Row(){}.width(8).height(8).borderRadius(4).backgroundColor(dotColor).margin({ right: 6 })
        Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary)
        Text('').layoutWeight(1)
        Text('共 ' + String(list.length) + ' 项').fontSize(11).fontColor(ThemeColors.textSecondary)
      }.width('100%').margin({ top: 16, bottom: 2 })
      if (list.length === 0) {
        Row() {
          Text(emptyHint).fontSize(13).fontColor(ThemeColors.textSecondary)
        }.width('100%').justifyContent(FlexAlign.Center).padding(14).margin({ top: 8 })
        .borderRadius(12).backgroundColor(ThemeColors.bgCard)
        .border({ width: { bottom: 1, right: 1, top: 1, left: 1 }, color: '#E0E0E0', radius: 12 })
      } else {
        ForEach(list, (card: ExpCard) => { this.ExpCardBuilder(card) },
          (card: ExpCard) => card.date + '_' + String(card.startSection))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  ExpCardBuilder(card: ExpCard) {
    Column() {
      Row() {
        Text(card.experimentName).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary).layoutWeight(1).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis})
        if (this.scoreChipVisible(card)) {
          Text(this.scoreChipText(card))
            .fontSize(12).fontColor(this.accentColor).fontWeight(FontWeight.Medium)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .backgroundColor(this.accentColor + '1A')
            .borderRadius(12)
            .margin({ left: 8 })
            .hoverEffect(HoverEffect.Auto)
            .onClick(() => { this.openScoreSheet(card); })
        }
      }.width('100%').margin({bottom:6})
      Row() { Text('\ud83d\udcc5').fontSize(13).margin({right:4}); Text(card.date+' '+card.weekdayName+' \u7b2c'+card.weekNum+'\u5468').fontSize(13).fontColor(ThemeColors.textSecondary) }.width('100%').margin({bottom:4})
      Row() { Text('\ud83d\udd50').fontSize(13).margin({right:4}); Text(this.cardTimeText(card)).fontSize(13).fontColor(ThemeColors.textSecondary) }.width('100%').margin({bottom:4})
      if(card.lab.length>0) { Row() { Text('\ud83d\udccd').fontSize(13).margin({right:4}); Text(card.lab).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis}) }.width('100%').margin({top:2}) }
      if(card.teacher.length>0) { Row() { Text('\ud83d\udc68\u200d\ud83c\udfeb').fontSize(13).margin({right:4}); Text(card.teacher).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis}) }.width('100%').margin({top:2}) }
      if(card.experimentProject.length>0) { Row() { Text('\ud83d\udcdd').fontSize(13).margin({right:4}); Text(card.experimentProject).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(2).textOverflow({overflow:TextOverflow.Ellipsis}).layoutWeight(1) }.width('100%').margin({top:2}) }
      if(card.className.length>0) { Row() { Text('\ud83d\udc65').fontSize(13).margin({right:4}); Text(card.className).fontSize(13).fontColor(ThemeColors.textSecondary).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis}) }.width('100%').margin({top:2}) }
    }.width('100%').padding(14).borderRadius(12).backgroundColor(ThemeColors.bgCard).margin({top:8}).alignItems(HorizontalAlign.Start).border({width:{bottom:1,right:1,top:1,left:1},color:'#E0E0E0',radius:12})
  }

  // 成绩详情半屏：原图 + 预测分数（对齐 Flutter ExperimentInfoCard 弹窗）
  @Builder
  ScoreSheetBuilder() {
    Column() {
      Text(this.sheetExpName).fontSize(17).fontWeight(FontWeight.Bold).fontColor(ThemeColors.textPrimary).maxLines(2).textOverflow({overflow:TextOverflow.Ellipsis})
        .width('100%').margin({ top: 4, bottom: 10 })
      if (this.sheetScoreFound) {
        Row() {
          Text('\u6210\u7ee9').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ right: 8 })
          Text(this.sheetScoreLabel).fontSize(30).fontWeight(FontWeight.Bold).fontColor(this.accentColor)
        }.width('100%').margin({ bottom: 10 })
      } else {
        Text('\u672a\u80fd\u81ea\u52a8\u8bc6\u522b\u5206\u6570\uff0c\u4ee5\u4e0b\u4e3a\u6210\u7ee9\u539f\u56fe').fontSize(14).fontColor(ThemeColors.textSecondary)
          .width('100%').margin({ bottom: 10 })
      }
      // 成绩原图（教务系统返回，等比 contain 预览）
      if (this.sheetScoreUrl.length > 0) {
        Image(this.sheetScoreUrl)
          .width('100%').height(150)
          .objectFit(ImageFit.Contain)
          .backgroundColor('#FFFFFF')
          .borderRadius(10)
          .margin({ bottom: 10 })
      }
      Text('\u63d0\u793a\uff1a\u56fe\u7247\u4e3a\u6210\u7ee9\u7cfb\u7edf\u539f\u59cb\u56fe\uff0c\u5206\u6570\u7531\u50cf\u7d20\u54c8\u5e0c\u8bc6\u522b\uff0c\u4ec5\u4f9b\u53c2\u8003')
        .fontSize(12).fontColor(ThemeColors.textSecondary).width('100%')
    }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
  }
}
