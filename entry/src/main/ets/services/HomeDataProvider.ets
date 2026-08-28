// HomeDataProvider.ets — 首页数据聚合层
// 设计：cache-first（进页秒显 AppStorage/Preferences 缓存）+ 进页后台并发轻刷。
// 不重复实现 ElectricityPage 的 AES 多步流 / LibraryPage 的 WebView 注入流，
// 直接读取这些页面已经写好的缓存，零额外请求。

import { PreferenceUtil } from '../utils/PreferenceUtil';
import { ExamService } from './ExamService';
import { SemesterUtil } from './EhallService';
import { AttendanceService } from './AttendanceService';
import { SchoolnetService } from './SchoolnetService';
import { LibspSessionService, LibspBorrowSummary } from './LibspSessionService';
import { SchoolCardService, PaidRecord } from './SchoolCardService';
import { CasLoginService } from './CasLoginService';
import { ElectricityService } from './ElectricityService';
import { ExamItemModel } from './Models';
import { ClassAttendance, AttendanceStatus } from './AttendanceModels';
import { fmtDate } from '../utils/DateUtil';

// 首页快照：所有字段给默认值，渲染层据此判断"无数据/加载中"
export class HomeSnapshot {
  // 校园卡
  cardBalance: string = '—';        // 余额（来自 AppStorage.card_balance）
  cardLastConsume: string = '—';    // 上次消费金额 ¥x
  cardLastConsumeDate: string = '—';// 上次消费日期（已去年份）
  // 电费·水费
  elecRemain: string = '—';         // 电费剩余（单位 kWh，非金额）
  elecReadTime: string = '—';       // 上次读表时间
  waterRemain: string = '—';        // 水费读数
  elecRoom: string = '—';           // 楼栋房间
  // 图书馆
  libBorrow: string = '—';          // 在借数
  libOverdue: string = '—';         // 逾期数
  // 考试
  examName: string = '—';           // 科目名
  examCountdown: string = '—';      // 倒计时 / 已结束门数
  examDate: string = '—';           // 日期
  examHasUpcoming: boolean = false; // 是否还有未开始的考试（false 且已取数 → 显示"暂无"）
  // 考勤（按课程真实聚合，不造假周统计）
  attDanger: number = 0;            // 危险+取消
  attNormal: number = 0;            // 正常
  attUnknown: number = 0;           // 未知
  attHasData: boolean = false;      // 是否拿到过数据
  // 校园网
  netUsed: string = '—';            // 已用流量
  netDevices: string = '—';         // 在线设备数
}

// 回写缓存的形态（与 ElectricityPage 的 ElecCache 字段一致；daily/waterDaily 用数组）
interface ElecCacheV2 {
  remain: string;
  metID: string;
  nodeID: string;
  date: string;
  daily: Object[];
  error: string;
  waterRemain: string;
  waterMetID: string;
  waterDate: string;
  waterDaily: Object[];
}

// 各卡片后台数据的持久缓存形态（对应首页快照字段），用于进页秒显
interface ExamCache { name: string; countdown: string; date: string; hasUpcoming: boolean; }
interface AttCache { danger: number; normal: number; unknown: number; hasData: boolean; }
interface NetCache { used: string; devices: string; }

// 字节 → 可读流量（与 SchoolNetPage.formatFlowNum 对齐）
function fmtFlow(num: number): string {
  if (!num || num <= 0) { return '0 B'; }
  if (num >= 1024 * 1024 * 1024) { return (num / (1024 * 1024 * 1024)).toFixed(2) + ' GB'; }
  if (num >= 1024 * 1024) { return (num / (1024 * 1024)).toFixed(2) + ' MB'; }
  if (num >= 1024) { return (num / 1024).toFixed(2) + ' KB'; }
  return num.toFixed(0) + ' B';
}

// 消费记录日期：去掉年份（首页空间有限），保留 月-日 时:分
// 入参形如 "2026-07-20 14:30:00" / "2026/07/20 14:30" / "2026-07-20" → "07-20 14:30:00" 等
function fmtCardDate(d: string): string {
  if (!d) { return ''; }
  return d.replace(/^\d{4}[-/]/, '');
}

// 逐字段推送：某数据源就绪即写入 AppStorage，使对应卡片立即显示（不必等待其余请求）
function flushCard(snap: HomeSnapshot): void {
  AppStorage.set('home_card_balance', snap.cardBalance);
  AppStorage.set('home_card_consume', snap.cardLastConsume);
  AppStorage.set('home_card_consume_date', snap.cardLastConsumeDate);
}
function flushElec(snap: HomeSnapshot): void {
  AppStorage.set('home_elec_remain', snap.elecRemain);
  AppStorage.set('home_elec_readtime', snap.elecReadTime);
  AppStorage.set('home_water_remain', snap.waterRemain);
  AppStorage.set('home_elec_room', snap.elecRoom);
}
function flushLib(snap: HomeSnapshot): void {
  AppStorage.set('home_lib_borrow', snap.libBorrow);
  AppStorage.set('home_lib_overdue', snap.libOverdue);
}
function flushExam(snap: HomeSnapshot): void {
  AppStorage.set('home_exam_name', snap.examName);
  AppStorage.set('home_exam_countdown', snap.examCountdown);
  AppStorage.set('home_exam_date', snap.examDate);
  AppStorage.set('home_exam_has_upcoming', snap.examHasUpcoming);
}
function flushAtt(snap: HomeSnapshot): void {
  AppStorage.set('home_att_danger', snap.attDanger);
  AppStorage.set('home_att_normal', snap.attNormal);
  AppStorage.set('home_att_unknown', snap.attUnknown);
  AppStorage.set('home_att_hasdata', snap.attHasData);
}
function flushNet(snap: HomeSnapshot): void {
  AppStorage.set('home_net_used', snap.netUsed);
  AppStorage.set('home_net_devices', snap.netDevices);
}

export class HomeDataProvider {
  static async load(): Promise<HomeSnapshot> {
    const snap: HomeSnapshot = new HomeSnapshot();

    // ===== 缓存速显（无需网络） =====
    // 校园卡余额（SchoolCardPage WebView 写入 AppStorage）
    const bal: string = AppStorage.get<string>('card_balance') as string;
    if (bal && bal.length > 0) {
      snap.cardBalance = bal;
    }

    // 电费（ElectricityPage 拉完写 electricity_cache_v2；水费不在首页展示）
    const elecRaw: string = PreferenceUtil.getString('electricity_cache_v2');
    if (elecRaw.length > 0) {
      try {
        const e: Record<string, string> = JSON.parse(elecRaw) as Record<string, string>;
        if (e['remain']) { snap.elecRemain = e['remain']; }      // kWh 余量
        if (e['date']) { snap.elecReadTime = e['date']; }        // 上次读表时间
        if (e['waterRemain']) { snap.waterRemain = e['waterRemain']; }  // 水费读数
        if (e['metID']) { snap.elecRoom = e['metID']; }          // 楼栋房间（电表号）
      } catch (_e) { /* 解析失败忽略 */ }
    }

    // 图书馆（LibraryPage 写 lib_summary = "在借|逾期"）
    const libRaw: string = PreferenceUtil.getString('lib_summary');
    if (libRaw.length > 0) {
      const parts: string[] = libRaw.split('|');
      if (parts.length >= 2) {
        snap.libBorrow = parts[0] || '0';
        snap.libOverdue = parts[1] || '0';
      }
    }
    // 校园卡：AppStorage 即时值优先，退化读 Preferences 持久缓存（WebView 写入）
    const balCached: string = PreferenceUtil.getString('card_balance_cached');
    if ((!bal || bal.length === 0) && balCached.length > 0) {
      snap.cardBalance = balCached;
    }
    const consCached: string = PreferenceUtil.getString('card_consume_cached');
    if (consCached.length > 0) { snap.cardLastConsume = consCached; }
    const consDateCached: string = PreferenceUtil.getString('card_consume_date_cached');
    if (consDateCached.length > 0) { snap.cardLastConsumeDate = consDateCached; }

    // 考试（上次缓存，进页即显，后台静默刷新）
    const examRaw: string = PreferenceUtil.getString('exam_cache');
    if (examRaw.length > 0) {
      try {
        const ex: ExamCache = JSON.parse(examRaw) as ExamCache;
        snap.examName = ex.name || '—';
        snap.examCountdown = ex.countdown || '—';
        snap.examDate = ex.date || '';
        snap.examHasUpcoming = ex.hasUpcoming;
      } catch (_e) { /* ignore */ }
    }

    // 考勤（上次缓存，进页即显，后台静默刷新）
    const attRaw: string = PreferenceUtil.getString('att_cache');
    if (attRaw.length > 0) {
      try {
        const at: AttCache = JSON.parse(attRaw) as AttCache;
        snap.attDanger = at.danger;
        snap.attNormal = at.normal;
        snap.attUnknown = at.unknown;
        snap.attHasData = at.hasData;
      } catch (_e) { /* ignore */ }
    }

    // 校园网（上次缓存，进页即显，后台静默刷新）
    const netRaw: string = PreferenceUtil.getString('net_cache');
    if (netRaw.length > 0) {
      try {
        const nt: NetCache = JSON.parse(netRaw) as NetCache;
        if (nt.used) { snap.netUsed = nt.used; }
        if (nt.devices) { snap.netDevices = nt.devices; }
      } catch (_e) { /* ignore */ }
    }

    // 缓存命中的字段立即推送（秒显，不等网络请求）
    flushCard(snap);
    flushElec(snap);
    flushLib(snap);

    // ===== 并发后台轻刷（失败保持缓存/占位） =====
    const semCode: string = SemesterUtil.getCurrentSemesterCode();
    const end: Date = new Date();
    const begin: Date = new Date();
    begin.setDate(begin.getDate() - 30);
    const beginStr: string = fmtDate(begin);
    const endStr: string = fmtDate(end);

    const tasks: Promise<void>[] = [];

    // 考试：取最早未考；若无未考则统计已结束门数
    tasks.push(
      ExamService.getInstance().getExamSchedule(semCode).then((raw: string) => {
        const list: ExamItemModel[] = ExamService.parseExamSchedule(raw);
        if (!list || list.length === 0) {
          snap.examName = '暂无';
          snap.examCountdown = '0 门已结束';
          snap.examDate = '';
          snap.examHasUpcoming = false;
        } else {
          const today: Date = new Date();
          today.setHours(0, 0, 0, 0);
          const todayTs: number = today.getTime();
          let upcoming: ExamItemModel | null = null;
          let upcomingTs: number = Number.MAX_SAFE_INTEGER;
          let finished: number = 0;
          for (const it of list) {
            if (!it.ksrq) { continue; }
            const t: number = new Date(it.ksrq.replace(/-/g, '/')).getTime();
            if (isNaN(t)) { continue; }
            if (t >= todayTs) {
              if (t < upcomingTs) { upcomingTs = t; upcoming = it; }
            } else {
              finished++;
            }
          }
          if (upcoming) {
            snap.examName = upcoming.kcm || upcoming.ksmc || '考试';
            const days: number = Math.ceil((upcomingTs - todayTs) / 86400000);
            snap.examCountdown = days <= 0 ? '今天' : `还有 ${days} 天`;
            snap.examDate = upcoming.ksrq;
            snap.examHasUpcoming = true;
          } else {
            snap.examName = '暂无';
            snap.examCountdown = `${finished} 门已结束`;
            snap.examDate = '';
            snap.examHasUpcoming = false;
          }
        }
        // 持久化，供下次进页秒显
        const examCache: ExamCache = {
          name: snap.examName, countdown: snap.examCountdown, date: snap.examDate, hasUpcoming: snap.examHasUpcoming
        };
        PreferenceUtil.putString('exam_cache', JSON.stringify(examCache));
        flushExam(snap);
      }).catch((e: Error) => { console.error('[HomeData] exam fail: ' + (e ? e.message : e)); })
    );

    // 考勤：按课程真实聚合危险/正常/未知
    tasks.push(
      AttendanceService.getInstance().getAttendanceRecords().then((list: ClassAttendance[]) => {
        snap.attHasData = !!(list && list.length > 0);
        if (list && list.length > 0) {
          // 统计前先归零，避免叠加进页时已读的 att_cache 缓存值导致数字翻倍
          snap.attDanger = 0;
          snap.attNormal = 0;
          snap.attUnknown = 0;
          for (const c of list) {
            const s: AttendanceStatus = c.getAttendanceStatus();
            if (s === AttendanceStatus.WARNING || s === AttendanceStatus.INELIGIBLE) {
              snap.attDanger++;
            } else if (s === AttendanceStatus.ELIGIBLE) {
              snap.attNormal++;
            } else {
              snap.attUnknown++;
            }
          }
        }
        // 持久化，供下次进页秒显
        const attCache: AttCache = {
          danger: snap.attDanger, normal: snap.attNormal, unknown: snap.attUnknown, hasData: snap.attHasData
        };
        PreferenceUtil.putString('att_cache', JSON.stringify(attCache));
        flushAtt(snap);
      }).catch((e: Error) => { console.error('[HomeData] attendance fail: ' + (e ? e.message : e)); })
    );

    // 校园网用量：走认证系统「当前上网用户」(w.xidian.edu.cn/rad_user_info)，
    // 无需密码，对应 Flutter 的 currentUser；不依赖 ZFW 自服务平台密码。
    tasks.push(
      SchoolnetService.getInstance().getCurrentOnlineInfo().then((info) => {
        const userName: string = String(info['user_name'] || '');
        const sumFlow: number = Number(info['sum_flow'] || 0) || 0;
        const remainFlow: number = Number(info['remain_flow'] || 0) || 0;
        if (userName.length === 0 || sumFlow <= 0) {
          snap.netUsed = '—';
          snap.netDevices = '未连接';
        } else {
          snap.netUsed = fmtFlow(sumFlow);
          snap.netDevices = '剩 ' + fmtFlow(remainFlow);
        }
        // 持久化，供下次进页秒显
        const netCache: NetCache = { used: snap.netUsed, devices: snap.netDevices };
        PreferenceUtil.putString('net_cache', JSON.stringify(netCache));
        flushNet(snap);
      }).catch((e: Error) => { console.error('[HomeData] schoolnet fail: ' + (e ? e.message : e)); })
    );

    // 校园卡：与详情页同款引导（CAS登录 → openid → 余额/消费），主页自己持有数据源（Flutter 风格，不依赖缓存/轮询）
    tasks.push(
      (async () => {
        const loggedIn: boolean = await CasLoginService.getInstance().checkAndAutoLogin();
        await SchoolCardService.getInstance().ensureOpenId();
        const bal: string = await SchoolCardService.getInstance().getBalance();
        if (bal && bal.length > 0) {
          snap.cardBalance = bal;
          AppStorage.set('card_balance', bal);
          PreferenceUtil.putString('card_balance_cached', bal);
          flushCard(snap);
        }
        const recs: PaidRecord[] = await SchoolCardService.getInstance().getPaidRecords(beginStr, endStr);
        if (recs && recs.length > 0) {
          const r: PaidRecord = recs[0];
          snap.cardLastConsume = `¥${r.money}`;
          snap.cardLastConsumeDate = fmtCardDate(r.date);
          PreferenceUtil.putString('card_consume_cached', snap.cardLastConsume);
          PreferenceUtil.putString('card_consume_date_cached', snap.cardLastConsumeDate);
          flushCard(snap);
        }
      })().catch((e: Error) => { console.error('[HomeData] schoolcard fail: ' + (e ? e.message : e)); })
    );

    // 图书馆：JWT 会话有效时直连拉当前借阅概况（覆盖缓存）；无效则降级显示缓存
    tasks.push(
      LibspSessionService.fetchBorrowSummary().then((s: LibspBorrowSummary | null) => {
        if (s) {
          snap.libBorrow = String(s.borrow);
          snap.libOverdue = String(s.overdue);
          PreferenceUtil.putString('lib_summary', s.borrow + '|' + s.overdue);
        }
        flushLib(snap);
      }).catch((e: Error) => {
        console.error('[HomeData] library fail: ' + (e ? e.message : e));
        flushLib(snap);
      })
    );

    // 电费：纯 HTTP 后台实时拉（复用已登录 CAS CASTGC，跟随 xxcapp→CAS→ignypt 重定向取 OAuth code）
    // 成功则写回 electricity_cache_v2 + 推送卡片；失败（如 CASTGC 失效）降级显示缓存。
    // 不 set home_data_dirty，避免轮询重拉循环（同图书馆 task 的处理）。
    tasks.push(
      (async () => {
        const loggedIn: boolean = await CasLoginService.getInstance().checkAndAutoLogin();
        if (!loggedIn) {
          flushElec(snap);
          return;
        }
        const r = await ElectricityService.fetchEnergyInfo();
        if (r) {
          const cache: ElecCacheV2 = {
            remain: r.remain,
            metID: r.metID,
            nodeID: r.nodeID,
            date: r.date,
            daily: [],
            error: '',
            waterRemain: r.waterRemain,
            waterMetID: r.waterMetID,
            waterDate: r.waterDate,
            waterDaily: []
          };
          PreferenceUtil.putString('electricity_cache_v2', JSON.stringify(cache));
          snap.elecRemain = r.remain;
          snap.elecReadTime = r.date;
          snap.waterRemain = r.waterRemain;
          snap.elecRoom = r.metID;
        } else {
        }
        flushElec(snap);
      })().catch((e: Error) => {
        console.error('[HomeData] electricity fail: ' + (e ? e.message : e));
        flushElec(snap);
      })
    );

    await Promise.allSettled(tasks);
    return snap;
  }
}
