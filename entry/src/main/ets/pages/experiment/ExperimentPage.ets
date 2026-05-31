// ExperimentPage.ets - 实验信息页面（WebView 登录 + JS 注入获取数据）
import web_webview from '@ohos.web.webview';
import { ThemeColors } from '../../utils/ThemeColors';
import { ExperimentData, ExperimentType, TimeRange, SemesterUtil } from '../../services/EhallService';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { HttpUtil, HttpResponse } from '../../utils/HttpUtil';

const TAG = 'ExperimentPage';

const WEEKDAY_NAMES: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

const CACHE_KEY = 'sysj_exp_cache';
const PHYSICS_CACHE_KEY = 'physics_exp_cache';
const CACHE_TTL = 4 * 60 * 60 * 1000;

enum PageState {
  IDLE,
  LOADING,
  SUCCESS,
  ERROR,
  WEBVIEW_LOGIN
}

// 二维数组的一个子数组: [课程代码, 课程名称, 开课院系, 实验室, 星期几, 开始节次, 结束节次, 周次, _, 上课教师, _, 上课班级, 分组标识, 上课人数, 实验项目]
// JS注入后额外附加 __week 字段
interface SysjScheduleItem {
  courseCode: string;
  experimentName: string;
  department: string;
  lab: string;
  weekday: string;
  startSection: string;
  endSection: string;
  week: string;
  unknown8: string;
  teacher: string;
  unknown10: string;
  className: string;
  groupId: string;
  studentCount: string;
  experimentProject: string;
  __week: number;
  sectionName?: string;
}

interface ExpCard {
  date: string;
  weekdayName: string;
  weekNum: number;
  sectionName: string;
  isCompleted: boolean;
  experimentName: string;
  lab: string;
  teacher: string;
  experimentProject: string;
  className: string;
}

function formatDate(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return y + '-' + m + '-' + day;
}

function getWeekdayName(weekday: number): string {
  // weekday 1=周一(0), 2=周二(1), ..., 7=周日(6)
  const idx = weekday - 1;
  if (idx >= 0 && idx < WEEKDAY_NAMES.length) {
    return WEEKDAY_NAMES[idx];
  }
  return '';
}


@Component
export struct ExperimentPage {
  pageInfo: NavPathStack = new NavPathStack();
  @State pageState: PageState = PageState.IDLE;
  @State statusText: string = '';
  @State errorMsg: string = '';
  @State cards: ExpCard[] = [];
  @State fetchProgress: string = '';

  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private autoFilled: boolean = false;
  private submitHandled: boolean = false;
  private dataReceived: boolean = false;
  private allWeekData: SysjScheduleItem[] = [];
  private weeksDone: number = 0;
  @State private isRefreshing: boolean = false;
  @StorageLink('theme_is_dark') themeIsDark: boolean = false;

  async aboutToAppear(): Promise<void> {
    // 尝试读取缓存（方案B：启用缓存，首次弹窗后后续走缓存不弹）
    const cached = PreferenceUtil.getString(CACHE_KEY);
    if (cached.length > 0) {
      try {
        const cacheObj: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
        const ts: number = cacheObj['ts'] as number;
        if (Date.now() - ts < CACHE_TTL) {
          const raw: Object = cacheObj['data'];
          if (raw instanceof Array && raw.length > 0) {
            const items: SysjScheduleItem[] = raw as SysjScheduleItem[];
            this.buildCards(items);
            this.pageState = PageState.SUCCESS;
            console.info(TAG, 'Loaded from cache, ' + items.length + ' items');
            return;
          }
        }
      } catch (e) {
        console.warn(TAG, 'Cache parse error, clearing');
        PreferenceUtil.putString(CACHE_KEY, '');
      }
    }
    // 无有效缓存，走 WebView SSO
    this.pageState = PageState.IDLE;
    this.startLogin();
  }

  startLogin(): void {
    const isLoggedIn: boolean = PreferenceUtil.getBool('is_logged_in');
    if (!isLoggedIn) {
      this.errorMsg = '请先登录统一认证';
      this.pageState = PageState.ERROR;
      return;
    }
    this.pageState = PageState.WEBVIEW_LOGIN;
    this.statusText = '正在验证登录状态...';
    this.fetchProgress = '';
    this.autoFilled = false;
    this.submitHandled = false;
    this.dataReceived = false;
    this.allWeekData = [];
    this.weeksDone = 0;
  }

  injectDataFetcher(): void {
    if (this.dataReceived) return; // already fetched, don't re-inject
    this.statusText = '正在获取实验数据...';
    this.allWeekData = [];
    this.weeksDone = 0;

    // JS: 逐周抓取 myScheduleInfoAjax API，返回二维数组
    // termId=2003 是实验系统学期 ID，下学期需手动更新
    // & 符号在 ArkTS 字符串中用 \x26 转义
    const js = '(async function(){' +
      'for(var w=1;w<=25;w++){' +
      'try{' +
      'var resp=await fetch("/xidian/schedule/myScheduleInfoAjax?termId=2003\\x26week="+w);' +
      'if(!resp.ok){console.error("__EXP_WEEK__"+w+"|[]");continue;}' +
      'var data=await resp.json();' +
      'if(data.length>0){console.error("__EXP_RAW__"+w+"|"+JSON.stringify(data[0]));}for(var i=0;i<data.length;i++){var d=data[i];data[i]={courseCode:d[0]||"",experimentName:d[1]||"",department:d[2]||"",lab:d[11]||"",weekday:d[4]||"",startSection:d[5]||"",endSection:d[6]||"",week:d[7]||"",unknown8:d[8]||"",teacher:d[9]||"",unknown10:d[10]||"",className:d[12]||"",groupId:d[12]||"",studentCount:d[13]||"",experimentProject:d[14]||"",__week:w};}' +
      'console.error("__EXP_WEEK__"+w+"|"+JSON.stringify(data));' +
      '}catch(e){' +
      'console.error("__EXP_WEEK__"+w+"|[]");' +
      '}' +
      '}' +
      'console.error("__EXP_DONE__");' +
      '})();';
    try {
      this.webController.runJavaScript(js);
    } catch (e) {
      console.error(TAG, 'Inject data fetcher failed: ' + String(e));
      this.onError('注入数据获取脚本失败');
    }
  }

  onPageEnd(url: string): void {
    console.info(TAG, 'onPageEnd: ' + url);

    // Fallback: CAS login page detected (fetch approach failed, direct navigation)
    const isCasLoginPage = (url.indexOf('cas.xidian.edu.cn') >= 0 && url.indexOf('/login') >= 0) ||
      (url.indexOf('ids.xidian.edu.cn') >= 0 && url.indexOf('/login') >= 0);
    if (isCasLoginPage) {
      this.autoFilled = false;
      this.submitHandled = false;
      const username = PreferenceUtil.getString('login_username');
      const password = PreferenceUtil.getString('login_password');
      if (username.length > 0 && password.length > 0) {
        // Auto-fill + auto-submit with type=password→text trick
        const js = '(function(){' +
          'var u=document.getElementById("username")||document.querySelector(\'input[name="username"]\');' +
          'var p=document.getElementById("password")||document.querySelector(\'input[name="password"]\');' +
          'if(p&&p.type==="password"){p.type="text";p.style.color="transparent";p.style.caretColor="transparent";}' +
          'if(u){u.value="' + username + '";u.dispatchEvent(new Event("input",{bubbles:true}));}' +
          'if(p){p.value="' + password + '";p.dispatchEvent(new Event("input",{bubbles:true}));}' +
          'var btn=document.getElementById("loginBtn")||document.querySelector("button[type=submit]");' +
          'if(btn){setTimeout(function(){btn.click();},300);}' +
          '})();';
        try {
          this.webController.runJavaScript(js);
          this.autoFilled = true;
          this.submitHandled = true;
          this.statusText = '自动登录中...';
        } catch (e) {
          console.warn(TAG, 'CAS auto-fill failed: ' + String(e));
        }
      }
      return;
    }
    // 登录成功回到 sysj 主站（排除sysj的OAuth中间页面和登录页）
    if (url.indexOf('sysj.xidian.edu.cn') >= 0 &&
      url.indexOf('/uaa/') < 0 &&
      url.indexOf('/webapp/login') < 0 &&
      url.indexOf('/webapp/callback') < 0) {
      if (this.dataReceived) return;
      setTimeout(() => { this.injectDataFetcher(); }, 1000);
    }
  }

  handleConsole(event: OnConsoleEvent): boolean {
    const msg: string = event?.message?.getMessage()?.toString() || '';

    // Login status updates from local HTML
    if (msg.startsWith('__LOGIN_STATUS__')) {
      this.statusText = msg.substring('__LOGIN_STATUS__'.length);
      return true;
    }
    if (msg.startsWith('__LOGIN_FAIL__')) {
      console.error(TAG, 'Login failed: ' + msg);
      return true;
    }

    if (!msg.startsWith('__EXP_')) return false;

    if (msg.startsWith('__EXP_WEEK__')) {
      if (this.dataReceived) return true;
      const pipeIdx = msg.indexOf('|');
      if (pipeIdx < 0) return true;
      const jsonStr = msg.substring(pipeIdx + 1);
      try {
        const items = JSON.parse(jsonStr) as SysjScheduleItem[];
        if (items.length > 0) {
          this.allWeekData = this.allWeekData.concat(items);
        }
      } catch (e) {
        console.warn(TAG, 'Parse week data error: ' + String(e));
      }
      this.weeksDone++;
      this.statusText = '正在获取实验数据...';
      this.fetchProgress = '(' + this.weeksDone + '/20)';
      return true;
    }

    if (msg.startsWith('__EXP_DONE__')) {
      if (this.dataReceived) return true;
      this.dataReceived = true;
      console.info(TAG, 'All weeks fetched, total items=' + this.allWeekData.length);
      this.onAllDataFetched();
      return true;
    }

    return false;
  }

  onAllDataFetched(): void {
    const cacheObj: ESObject = {
      'ts': Date.now(),
      'data': this.allWeekData
    } as ESObject;
    PreferenceUtil.putString(CACHE_KEY, JSON.stringify(cacheObj));

    this.buildCards(this.allWeekData);
    // 同时拉取物理实验数据（后台 HTTP，不阻塞 UI）
    this.fetchPhysicsExperiment();
  }

  buildCards(items: SysjScheduleItem[]): void {
    console.info(TAG, 'buildCards called with items=' + items.length);
    for (let i = 0; i < Math.min(items.length, 2); i++) {
      const it = items[i];
      console.info(TAG, 'item[' + i + ']: name=' + it.experimentName + ' weekday=' + it.weekday + ' week=' + it.week + ' start=' + it.startSection);
    }
    const cardMap: Map<string, ExpCard> = new Map();
    const semesterStart = SemesterUtil.getSemesterStartDate(SemesterUtil.getCurrentSemesterCode());
    const today = formatDate(new Date());
    const dayMs = 24 * 60 * 60 * 1000;

    for (const item of items) {
      // 从二维数组子数组中按索引取值
      const experimentName: string = item.experimentName || '未知实验';   // [1] 课程名称
      const lab: string = item.lab || '';                    // [3] 实验室
      const weekday: number = parseInt(item.weekday) || 1;      // [4] 星期几 (1=周一..7=周日)
      const startSection: number = parseInt(item.startSection) || 1;  // [5] 开始节次
      const endSection: number = parseInt(item.endSection) || 1;    // [6] 结束节次
      const weekNum: number = parseInt(item.week) || 1;          // 周次(由JS注入)
      const teacher: string = item.teacher || '';                // [9] 上课教师
      const className: string = item.className || '';             // [11] 上课班级
      const experimentProject: string = item.experimentProject || '';     // [14] 实验项目

      if (weekNum <= 0 || weekNum > 20) continue;

      // 日期计算: 学期起始 + (week-1)*7 + (weekday-1)
      // weekday 1=周一 偏移0, 2=周二 偏移1, ..., 7=周日 偏移6
      const weekdayOffset = weekday - 1;
      const dateMs = semesterStart.getTime() + (weekNum - 1) * 7 * dayMs + weekdayOffset * dayMs;
      const date = formatDate(new Date(dateMs));

      // 节次名称
      const sectionName = '第' + startSection + '-' + endSection + '节';
      const weekdayName = getWeekdayName(weekday);

      // 分组 key = 日期 + _ + 开始节次，不合并不同天的实验
      const key = date + '_' + startSection;
      let card = cardMap.get(key);
      if (!card) {
        card = {
          date: date,
          weekdayName: weekdayName,
          weekNum: weekNum,
          sectionName: sectionName,
          isCompleted: date < today,
          experimentName: experimentName,
          lab: lab,
          teacher: teacher,
          experimentProject: experimentProject,
          className: className
        };
        cardMap.set(key, card);
      }

      // 同一 key 下如果有多条，追加实验项目
      if (experimentProject.length > 0 && card.experimentProject.indexOf(experimentProject) < 0) {
        card.experimentProject = card.experimentProject + ' | ' + experimentProject;
      }
    }

    const sortedKeys = Array.from(cardMap.keys()).sort();
    const upcoming: ExpCard[] = [];
    const completed: ExpCard[] = [];
    for (const k of sortedKeys) {
      const card = cardMap.get(k);
      if (card !== undefined) {
        if (card.isCompleted) {
          completed.push(card);
        } else {
          upcoming.push(card);
        }
      }
    }
    this.cards = upcoming.concat(completed);
    console.info(TAG, 'cards built: total=' + this.cards.length);
  }

  async fetchPhysicsExperiment(): Promise<void> {
    const pwd = PreferenceUtil.getString('physics_pwd');
    if (pwd.length === 0) {
      // 没设密码，只更新状态
      if (this.allWeekData.length === 0) { this.onError('暂无实验信息'); }
      else { this.pageState = PageState.SUCCESS; }
      return;
    }
    try {
      // 尝试读物理实验缓存
      const cached = PreferenceUtil.getString(PHYSICS_CACHE_KEY);
      let physicsItems: SysjScheduleItem[] = [];
      if (cached.length > 0) {
        const c: Record<string, Object> = JSON.parse(cached) as Record<string, Object>;
        if (Date.now() - (c['ts'] as number) < CACHE_TTL && (c['data'] as Object[]).length > 0) {
          physicsItems = c['data'] as SysjScheduleItem[];
          console.info(TAG, 'Physics loaded from cache, ' + physicsItems.length + ' items');
        }
      }
      // 无缓存则 HTTP 获取
      if (physicsItems.length === 0) {
        const http = HttpUtil.getInstance();
        const body = '__EVENTTARGET=&__EVENTARGUMENT=&' +
          '__VIEWSTATE=%2FwEPDwUKMTEzNzM0MjM0OWQYAQUeX19Db250cm9sc1JlcXVpcmVQb3N0QmFja0tleV9fFgEFD2xvZ2luMSRidG5Mb2dpbkOuzGVaztce4Ict7jsIJ0F5pUDb%2BsmSbCCrNVSBlPML&' +
          '__VIEWSTATEGENERATOR=EE008CD9&' +
          '__EVENTVALIDATION=%2FwEdAAcKecdPGDB%2BfW8Tyghx7AeSpOzeiNZ7aaEg5p6LqSa9cODI2bZwNtRxUKPkisVLf8l8Vv4WhRVIIhZlyYNJO%2BySrDKOhP%2B%2FYMNbVIh74hA2rCYnBBSTsX9SjxiYNNk%2B5kglM%2B6pGIq22Oi5mNu6u6eC2WEBfKAmATKwSpsOL%2FPNcRyi9l8Dnp6JamksyAzjhW4%3D&' +
          'login1%24StuLoginID=' + encodeURIComponent(PreferenceUtil.getString('ids_account')) +
          '&login1%24StuPassword=' + encodeURIComponent(pwd) +
          '&login1%24UserRole=Student&login1%24btnLogin.x=28&login1%24btnLogin.y=14';
        const loginResp = await http.postRaw('http://wlsy.xidian.edu.cn/PhyEws/default.aspx',
          body, 'application/x-www-form-urlencoded');
        if (loginResp.statusCode === 302 || loginResp.isOk) {
          // 登录成功，获取列表
          const resp = await http.get('http://wlsy.xidian.edu.cn/PhyEws/student/select.aspx');
          if (resp.isOk) {
            physicsItems = this.parsePhysicsHtml(resp.body);
            const pcache: ESObject = { 'ts': Date.now(), 'data': physicsItems } as ESObject;
            PreferenceUtil.putString(PHYSICS_CACHE_KEY, JSON.stringify(pcache));
            console.info(TAG, 'Physics fetched: ' + physicsItems.length + ' items');
          }
        }
      }
      // 合并物理实验卡片
      if (physicsItems.length > 0) {
        this.buildCards(physicsItems);
      }
    } catch (e) {
      console.warn(TAG, 'Physics fetch error: ' + String(e));
    }
    // 最终状态
    if (this.allWeekData.length === 0 && this.cards.length === 0) {
      this.onError('暂无实验信息');
    } else if (this.pageState !== PageState.SUCCESS) {
      this.pageState = PageState.SUCCESS;
    }
  }

  parsePhysicsHtml(html: string): SysjScheduleItem[] {
    const items: SysjScheduleItem[] = [];
    const trRegex = /<tr[^>]*>[\s\S]*?<\/tr>/gi;
    const tdRegex = /<td[^>]*>[\s\S]*?<\/td>/gi;
    const trs = html.match(trRegex);
    if (!trs) return items;
    for (const tr of trs) {
      const tds: string[] = [];
      let m: RegExpExecArray | null;
      while ((m = tdRegex.exec(tr)) !== null) {
        tds.push(m[1].replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').trim());
      }
      if (tds.length < 10 || tds[1].length === 0) continue;
      // td[1]=名称, td[3]=时间(如"第8-9节"或含"15"的时间), td[4]=日期(如"4/26/2026"), td[5]=教室
      // 转换为 ExpCard 兼容格式
      const dateStr = tds[4] || '';
      const dateParts = dateStr.split('/');
      const timeStr = tds[3] || '';
      const isAfternoon = timeStr.includes('15');
      const sectionName = isAfternoon ? '15:55-18:10' : '18:30-20:45';
      const item: SysjScheduleItem = {
        courseCode: '',
        experimentName: '⚛ ' + tds[1],
        department: '',
        lab: tds[5] || '',
        weekday: '0', // 从日期推算
        startSection: isAfternoon ? '7' : '9',
        endSection: isAfternoon ? '9' : '11',
        week: '0',
        unknown8: '',
        teacher: tds[9] || '',
        unknown10: '',
        className: '',
        groupId: '',
        studentCount: '',
        experimentProject: tds[8] || '',
        __week: 0
      } as SysjScheduleItem;
      // 从日期推算星期几
      if (dateParts.length >= 3) {
        const m = parseInt(dateParts[0]);
        const d = parseInt(dateParts[1]);
        const y = parseInt(dateParts[2]);
        const dt = new Date(y, m - 1, d);
        item.weekday = String(dt.getDay() === 0 ? 7 : dt.getDay());
        // 计算周次
        const semesterStart = SemesterUtil.getSemesterStartDate(SemesterUtil.getCurrentSemesterCode());
        const diffDays = Math.floor((dt.getTime() - semesterStart.getTime()) / 86400000);
        item.week = String(Math.floor(diffDays / 7) + 1);
        // 设置节次
        const hour = isAfternoon ? 15 : 18;
        const section = hour <= 15 ? 7 : 9;
        item.startSection = String(section);
        item.endSection = String(section + 2);
        item.sectionName = sectionName;
      }
      items.push(item);
    }
    return items;
  }

  onError(msg: string): void {
    this.errorMsg = msg;
    this.pageState = PageState.ERROR;
  }

  build() {
    NavDestination() {
      Column() {
      // 顶部导航栏
      if (this.pageState === PageState.WEBVIEW_LOGIN) {
        Stack() {
          // 隐藏 WebView 做 CAS SSO + 数据获取
          Web({ src: 'https://sysj.xidian.edu.cn/xidian/test', controller: this.webController })
            .width(1).height(1)
            .javaScriptAccess(true)
            .fileAccess(true)
            .domStorageAccess(true)
            .cacheMode(CacheMode.Default)
            .password(false)

            .onPageEnd((event) => {
              if (event) { this.onPageEnd(event.url); }
            })
            .onConsole((event: OnConsoleEvent) => {
              return this.handleConsole(event);
            })

          // 转圈加载动画覆盖层，盖住WebView
          Column() {
            LoadingProgress().width(48).height(48).color('#2979FF')
            Text(this.statusText || '正在登录实验系统...').fontSize(14).fontColor(ThemeColors.textSecondary)
              .margin({ top: 16 })
            if (this.fetchProgress.length > 0) {
              Text(this.fetchProgress).fontSize(12).fontColor(ThemeColors.textSecondary)
                .margin({ top: 8 })
            }
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .backgroundColor(ThemeColors.bgPage)
          .zIndex(1)
        }
        .width('100%').layoutWeight(1)

      } else if (this.pageState === PageState.LOADING) {
        Column() {
          LoadingProgress().width(40).height(40).color('#2979FF')
          Text(this.statusText || '加载中...').fontSize(14).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)

      } else if (this.pageState === PageState.ERROR) {
        Column() {
          Text('\ud83d\udccb').fontSize(48)
          Text(this.errorMsg).fontSize(15).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          Button('重新登录')
            .fontSize(14).fontColor('#FFFFFF').backgroundColor('#2979FF')
            .borderRadius(20).height(36).margin({ top: 20 })
            .onClick(() => { this.startLogin(); })
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .padding(24)

      } else if (this.pageState === PageState.IDLE) {
        Column() {
          Text('\ud83e\uddea').fontSize(48)
          Text('实验系统需要单独登录').fontSize(15).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
          Text('将使用统一认证账号自动填充').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 6 })
          Button('登录实验系统')
            .fontSize(14).fontColor('#FFFFFF').backgroundColor('#2979FF')
            .borderRadius(20).height(40).margin({ top: 20 })
            .onClick(() => { this.startLogin(); })
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .padding(24)

      } else if (this.pageState === PageState.SUCCESS) {
        if (this.cards.length === 0) {
          Column() {
            Text('\ud83e\uddea').fontSize(48)
            Text('暂无实验信息').fontSize(15).fontColor(ThemeColors.textSecondary).margin({ top: 12 })
            Button('重新登录')
              .fontSize(14).fontColor('#FFFFFF').backgroundColor('#2979FF')
              .borderRadius(20).height(36).margin({ top: 20 })
              .onClick(() => { this.startLogin(); })
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .padding(24)
        } else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            Scroll() {
              Column() {
                ForEach(this.cards, (card: ExpCard) => {
                  this.ExpCardBuilder(card)
                }, (card: ExpCard) => card.date + '_' + card.sectionName)
              }
              .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 16 })
          }
          .width('100%').layoutWeight(1)
          }
          .onRefreshing(() => {
            // 下拉刷新：清缓存，重新走 WebView SSO
            PreferenceUtil.putString(CACHE_KEY, '');
            this.isRefreshing = false;
            this.startLogin();
          })
        }
      }
    }
    .width('100%').height('100%').backgroundColor(ThemeColors.bgPage)
  }
    .title('实验信息')

  }
  @Builder
  ExpCardBuilder(card: ExpCard) {
    Column() {
      // 实验名称
      Row() {
        if (card.isCompleted) {
          Text('\u2705').fontSize(16).margin({ right: 6 })
        }
        Text(card.experimentName).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(ThemeColors.textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .margin({ bottom: 6 })

      // 日期 + 星期 + 周次
      Row() {
        Text('\ud83d\udcc5').fontSize(13).margin({ right: 4 })
        Text(card.date + ' ' + card.weekdayName + ' 第' + card.weekNum + '周')
          .fontSize(13).fontColor(ThemeColors.textSecondary)
      }
      .width('100%')
      .margin({ bottom: 4 })

      // 节次
      Row() {
        Text('\ud83d\udd50').fontSize(13).margin({ right: 4 })
        Text(card.sectionName)
          .fontSize(13).fontColor(ThemeColors.textSecondary)
      }
      .width('100%')
      .margin({ bottom: 4 })

      // 实验室
      if (card.lab.length > 0) {
        Row() {
          Text('\ud83d\udccd').fontSize(13).margin({ right: 4 })
          Text(card.lab).fontSize(13).fontColor(ThemeColors.textSecondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%').margin({ top: 2 })
      }

      // 教师
      if (card.teacher.length > 0) {
        Row() {
          Text('\ud83d\udc68\u200d\ud83c\udfeb').fontSize(13).margin({ right: 4 })
          Text(card.teacher).fontSize(13).fontColor(ThemeColors.textSecondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%').margin({ top: 2 })
      }

      // 实验项目
      if (card.experimentProject.length > 0) {
        Row() {
          Text('\ud83d\udcdd').fontSize(13).margin({ right: 4 })
          Text(card.experimentProject).fontSize(13).fontColor(ThemeColors.textSecondary)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%').margin({ top: 2 })
      }

      // 班级
      if (card.className.length > 0) {
        Row() {
          Text('\ud83d\udc65').fontSize(13).margin({ right: 4 })
          Text(card.className).fontSize(13).fontColor(ThemeColors.textSecondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%').margin({ top: 2 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor(ThemeColors.bgCard)

    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
    .border({ width: { bottom: 1, right: 1, top: 1, left: 1 }, color: '#E0E0E0', radius: 12 })

  }
}