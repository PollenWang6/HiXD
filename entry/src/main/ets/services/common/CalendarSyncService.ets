// CalendarSyncService.ets — 课表变更后自动增量同步日历
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SemesterUtil } from '../ids/EhallService';
import { calendarManager } from '@kit.CalendarKit';
import { common } from '@kit.AbilityKit';
import { SEC_START, SEC_END } from '../../models/common/ClassSchedule';
export interface SlimCell {
  name: string; teacher: string; classroom: string; day: number;
  startSection: number; endSection: number; startTime: string; endTime: string;
  weekList: boolean[];
  isExam: boolean; isExperiment: boolean;
  experimentProject: string; examDate: string; examTimeDesc: string; examSeat: string;
  weekNum: number; // 实验/考试所属周（普通课程为 0，跨多周不填）
}

// 统一定时解析：优先 startTime/endTime，存量数据回退 section→SEC_START
function getTimeFromCell(cell: SlimCell, isStart: boolean): string {
  if (isStart && cell.startTime) return cell.startTime;
  if (!isStart && cell.endTime) return cell.endTime;
  const sec = isStart ? cell.startSection : cell.endSection;
  if (sec > 0 && sec < SEC_START.length) return isStart ? SEC_START[sec] : SEC_END[sec];
  return '08:00';
}

// ST replaced by SEC_START/SEC_END import
const DC: number = 7;
const SC: number = 11;

// 事件内容元数据：增量同步比对用（description / reminderTime 与期望一致则跳过，
// 不一致说明教室/教师/座位/提醒等“不改 key”的信息变了 → 删旧重建；CalendarKit 无 update API）
export class EventMeta {
  desc: string = '';
  rem: string = '';
}

export class CalendarSyncService {
  // 串行化 + 尾轮补跑：MainPage 多处（页面可见/轮询/登录预载）都会触发 autoSync，
  // 同一时刻只跑一轮，避免并发双跑导致重复增删；期间又有新触发则在收尾后补跑一轮。
  private static syncBusy: boolean = false;
  private static syncAgain: boolean = false;

  static async autoSync(ctx: common.UIAbilityContext): Promise<void> {
    if (CalendarSyncService.syncBusy) {
      CalendarSyncService.syncAgain = true;
      return;
    }
    CalendarSyncService.syncBusy = true;
    try {
      do {
        CalendarSyncService.syncAgain = false;
        await CalendarSyncService.syncOnce(ctx);
      } while (CalendarSyncService.syncAgain);
    } finally {
      CalendarSyncService.syncBusy = false;
    }
  }

  private static async syncOnce(ctx: common.UIAbilityContext): Promise<void> {
    const bound: boolean = PreferenceUtil.getBool('calendar_bound');
    if (!bound) {
      return;
    }
    const cfg: Record<string, Object> = CalendarSyncService.loadConfig();
    const enabled: boolean = (cfg['cEnabled'] === true || cfg['eEnabled'] === true || cfg['xEnabled'] === true);
    if (!enabled) {
      return;
    }

    const grid: SlimCell[][][] = CalendarSyncService.loadGrid();
    if (grid.length === 0) {
      return;
    }

    // 变更检测（对齐 Flutter snapshot 比对：课表无变化不折腾日历）：
    // 签名 = 课表快照 + 导出配置（含提醒分钟/开关）。任一变化才执行全量日历比对，
    // 否则每次登录/刷新都 getEvents 扫一遍纯属浪费。
    // 注意：config 必须纳入签名——CalendarExportPage 保存设置后不触发任何同步，
    // autoSync 是其唯一生效通道；若只看课表快照，用户改提醒设置会被误跳过。
    const rawGrid: string = PreferenceUtil.getString('class_grid_snapshot', '');
    const cfgRaw: string = PreferenceUtil.getString('calendar_export_config', '');
    const sig: string = rawGrid + '#' + cfgRaw;
    const lastSig: string = PreferenceUtil.getString('calendar_sync_sig', '');
    if (lastSig === sig) {
      return;
    }

    const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(ctx);
    let cal: calendarManager.Calendar | null = null;
    try {
      const all: calendarManager.Calendar[] = await mgr.getAllCalendars();
      for (let i = 0; i < all.length; i++) {
        if (all[i].getAccount().name === 'HiXD课程表') { cal = all[i]; break; }
      }
    } catch (_e) { /* ignore */ }
    if (cal === null) {
      return;
    }

    const existMap: Record<string, number[]> = {};
    const meta: Record<string, EventMeta> = {};
    try {
      const evts: calendarManager.Event[] = await cal.getEvents();
      for (let i = 0; i < evts.length; i++) {
        const ev: calendarManager.Event = evts[i];
        if (ev.id !== undefined && ev.title && ev.startTime) {
          const k: string = ev.title + '|' + String(ev.startTime);
          if (!existMap[k]) {
            existMap[k] = [];
            const em: EventMeta = new EventMeta();
            em.desc = ev.description ?? '';
            em.rem = CalendarSyncService.remKey(ev.reminderTime ?? []);
            meta[k] = em;
          }
          existMap[k].push(ev.id);
        }
      }
    } catch (_e) { return; }

    const sem: string = SemesterUtil.getCurrentSemesterCode();
    const sd: Date = SemesterUtil.getSemesterStartDate(sem);
    const sw: number = PreferenceUtil.getNumber('week_swift', 0);
    const mon: Date = new Date(sd);
    mon.setDate(sd.getDate() + (sd.getDay() === 0 ? -6 : 1 - sd.getDay()) + sw * 7);

    const needed: Record<string, boolean> = {};
    const written: Record<string, boolean> = {};  // 本次运行已写入的 key，避免源数据重复课被写多次
    let added: number = 0;

    if (cfg['cEnabled'] === true) {
      const pre: number = cfg['cNone'] === true ? -1 : parseInt(cfg['cMinutes'] as string);
      added += await CalendarSyncService.syncC(mon, cal, grid, existMap, meta, needed, pre, written);
    }
    if (cfg['eEnabled'] === true) {
      const pre: number = cfg['eNone'] === true ? -1 : parseInt(cfg['eMinutes'] as string);
      const dbl: boolean = cfg['eDouble'] === true;
      const dbH: number = cfg['eDbHour'] as number;
      const dbM: number = cfg['eDbMin'] as number;
      added += await CalendarSyncService.syncE(mon, cal, grid, existMap, meta, needed, pre, dbl, dbH, dbM, written);
    }
    if (cfg['xEnabled'] === true) {
      const pre: number = cfg['xNone'] === true ? -1 : parseInt(cfg['xMinutes'] as string);
      const dbl: boolean = cfg['xDouble'] === true;
      const dbH: number = cfg['xDbHour'] as number;
      const dbM: number = cfg['xDbMin'] as number;
      added += await CalendarSyncService.syncX(cal, grid, existMap, meta, needed, pre, dbl, dbH, dbM, written);
    }

    // 清理过期 / 重复副本 / 历史孤儿
    let deleted: number = 0;
    const oldKeys: string[] = Object.keys(existMap);
    for (let i = 0; i < oldKeys.length; i++) {
      const k: string = oldKeys[i];
      const ids: number[] = existMap[k] || [];
      if (ids.length === 0) { continue; }
      if (needed[k]) {
        // 需要的 key：保留首条，删除其余（含学校重复课副本 + 历史孤儿）
        for (let j = 1; j < ids.length; j++) {
          try {
            await cal.deleteEvent(ids[j]);
            deleted++;
          } catch (_e) { /* 已删/不存在，忽略 */ }
        }
      } else {
        for (let j = 0; j < ids.length; j++) {
          try {
            await cal.deleteEvent(ids[j]);
            deleted++;
          } catch (_e) { /* 忽略 */ }
        }
      }
    }

    // 全量比对完成（无论是否有增删，此刻日历已与快照+配置一致）→ 记录签名，
    // 下次课表/配置无变化时直接跳过。中途异常路径（cal 为 null / getEvents 失败）不会走到这里。
    PreferenceUtil.putString('calendar_sync_sig', sig);
  }

  // 把合并网格写入 class_grid_snapshot（供 autoSync / 桌面卡片读取）
  // 抽自 ClassTablePage，使首页刷新/登录后也能统一更新快照
  static saveClassGridSnapshot(grid: SlimCell[][][], source: string = '?'): void {
    const slim: object[][] = [];
    const semStart: Date = SemesterUtil.getSemesterStartDate(SemesterUtil.getCurrentSemesterCode());
    for (let d = 0; d <= DC; d++) {
      slim[d] = [];
      for (let s = 0; s <= SC; s++) {
        const cells: SlimCell[] = grid[d]?.[s] ?? [];
        const slimRow: object[] = [];
        for (let i = 0; i < cells.length; i++) {
          const c: SlimCell = cells[i];
          const sc: Record<string, Object> = {};
          sc['name'] = c.name;
          sc['teacher'] = c.teacher ?? '';
          sc['classroom'] = c.classroom ?? '';
          sc['day'] = c.day;
          sc['startSection'] = c.startSection;
          sc['endSection'] = c.endSection;
          sc['weekList'] = c.weekList;
          sc['isExam'] = c.isExam;
          sc['isExperiment'] = c.isExperiment;
          sc['experimentProject'] = c.experimentProject ?? '';
          sc['examDate'] = c.examDate ?? '';
          sc['examTimeDesc'] = c.examTimeDesc ?? '';
          sc['examSeat'] = c.examSeat ?? '';
          let weekNum: number = 0;
          if (c.isExam && c.examDate) {
            const exDate = new Date(c.examDate + 'T00:00:00');
            if (!isNaN(exDate.getTime())) {
              weekNum = Math.floor((exDate.getTime() - semStart.getTime()) / 86400000 / 7) + 1;
            }
          } else if (c.isExperiment) {
            // 实验：优先用生产者填好的 weekNum（服务器单周实验 / 自定义实验首周），
            // 否则从 weekList 推导首个有课周，确保快照里的 weekNum 不为 0。
            if ((c.weekNum ?? 0) > 0) {
              weekNum = c.weekNum;
            } else {
              const wl = c.weekList ?? [];
              for (let i = 0; i < wl.length; i++) {
                if (wl[i]) { weekNum = i + 1; break; }
              }
            }
          }
          sc['weekNum'] = weekNum;
          slimRow.push(sc);
        }
        slim[d][s] = slimRow;
      }
    }
    const json: string = JSON.stringify(slim);
    PreferenceUtil.putString('class_grid_snapshot', json);
    // 同时写入 AppStorage，供 MainPage 直接读取（无文件 I/O 延迟）
    AppStorage.setOrCreate('class_grid_snapshot', json);
  }

  static loadConfig(): Record<string, Object> {
    const raw: string = PreferenceUtil.getString('calendar_export_config', '');
    if (raw.length === 0) {
      return {};
    }
    try {
      return JSON.parse(raw) as Record<string, Object>;
    } catch (_e) {
      return {};
    }
  }

  static loadGrid(): SlimCell[][][] {
    const raw: string = PreferenceUtil.getString('class_grid_snapshot', '');
    if (raw.length === 0) {
      return [];
    }
    const grid: SlimCell[][][] = [];
    try {
      const slim: Object[][] = JSON.parse(raw) as Object[][];
      for (let d = 0; d <= DC; d++) {
        grid[d] = [];
        for (let s = 0; s <= SC; s++) {
          const row: Object[] | undefined = slim[d] as Object[] | undefined;
          if (row !== undefined && row[s] !== undefined) {
            grid[d][s] = row[s] as SlimCell[];
          } else {
            grid[d][s] = [];
          }
        }
      }
    } catch (_e) { /* ignore */ }
    return grid;
  }

  // 事件标题：课程/实验/考试加类型前缀，并拼教室（有值才拼）。教室进入标题 → 换教室时 key
  // 自然变化 → 旧 key 不在 needed 被孤儿清理删除，实现“换教室自动更新”；空教室回退纯课名保证 key 稳定。
  static eventTitle(cell: SlimCell): string {
    let t: string = cell.name;
    if (cell.isExperiment) {
      t = '🧪 ' + t;
    } else if (cell.isExam) {
      t = '📝 ' + t;
    }
    const room: string = cell.classroom ?? '';
    if (room.length > 0) { t = t + '@' + room; }
    return t;
  }

  static cellKey(cell: SlimCell, startMs: number): string {
    return CalendarSyncService.eventTitle(cell) + '|' + String(startMs);
  }

  // 描述文本：课程 = 教室/教师；实验 = 地点/教师/项目；考试 = 地点/座位。有值才拼，分隔统一 " | "
  static descC(cell: SlimCell): string {
    const parts: string[] = [];
    if (cell.classroom) { parts.push('教室: ' + cell.classroom); }
    if (cell.teacher) { parts.push('教师: ' + cell.teacher); }
    return parts.join(' | ');
  }

  static descE(cell: SlimCell): string {
    const parts: string[] = [];
    if (cell.classroom) { parts.push('地点: ' + cell.classroom); }
    if (cell.teacher) { parts.push('教师: ' + cell.teacher); }
    if (cell.experimentProject) { parts.push('项目: ' + cell.experimentProject); }
    return parts.join(' | ');
  }

  static descX(cell: SlimCell): string {
    const parts: string[] = [];
    if (cell.classroom) { parts.push('地点: ' + cell.classroom); }
    if (cell.examSeat) { parts.push('座位: ' + cell.examSeat); }
    return parts.join(' | ');
  }

  // 提醒序列化：分钟数组升序 join；无提醒 => ''。与日历读回的 reminderTime 数组比对（顺序无关）
  static remKey(rt: number[]): string {
    if (rt.length === 0) { return ''; }
    const sorted: number[] = rt.slice().sort((a: number, b: number): number => a - b);
    return sorted.join(',');
  }

  static calcDbMins(startTime: Date, dbH: number, dbM: number): number {
    const db: Date = new Date(startTime);
    db.setDate(db.getDate() - 1);
    db.setHours(dbH, dbM, 0, 0);
    return Math.floor((startTime.getTime() - db.getTime()) / 60000);
  }

  static async syncC(mon: Date, cal: calendarManager.Calendar,
    grid: SlimCell[][][], existMap: Record<string, number[]>,
    meta: Record<string, EventMeta>,
    needed: Record<string, boolean>, pre: number,
    written: Record<string, boolean>): Promise<number> {
    let added: number = 0;
    for (let d = 1; d <= DC; d++) {
      for (let s = 1; s <= SC; s++) {
        const slot: SlimCell[][] | undefined = grid[d];
        const cells: SlimCell[] = (slot !== undefined && slot[s] !== undefined) ? slot[s] : [];
        for (let ci = 0; ci < cells.length; ci++) {
          const cell: SlimCell = cells[ci];
          if (cell.isExam || cell.isExperiment) { continue; }
          if (cell.startSection !== s) { continue; }
          for (let w = 0; w < cell.weekList.length; w++) {
            if (!cell.weekList[w]) { continue; }
            const dt: Date = new Date(mon);
            dt.setDate(mon.getDate() + (w - 1) * 7 + (d - 1));
            const sp: string[] = getTimeFromCell(cell, true).split(':');
            const ep: string[] = getTimeFromCell(cell, false).split(':');
            if (sp.length < 2 || ep.length < 2) { continue; }
            const stT: Date = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate(),
              parseInt(sp[0]), parseInt(sp[1]), 0);
            const etT: Date = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate(),
              parseInt(ep[0]), parseInt(ep[1]), 0);
            const title: string = CalendarSyncService.eventTitle(cell);
            const desc: string = CalendarSyncService.descC(cell);
            const key: string = CalendarSyncService.cellKey(cell, stT.getTime());
            needed[key] = true;
            const rt: number[] = [];
            if (pre > 0) { rt.push(pre); }
            const rem: string = CalendarSyncService.remKey(rt);
            const oldIds: number[] = existMap[key] ?? [];
            if (oldIds.length > 0) {
              const em: EventMeta | undefined = meta[key];
              if (em !== undefined && em.desc === desc && em.rem === rem) {
                continue; // 已存在且内容一致 → 跳过（重复源课由收尾去重）
              }
              // key 命中但 desc/提醒已变（教师/教室字段变更）→ CalendarKit 无 update API，删旧重建
              for (let oi = 0; oi < oldIds.length; oi++) {
                try { await cal.deleteEvent(oldIds[oi]); } catch (_e) { /* ignore */ }
              }
            }
            if (written[key]) { continue; }
            written[key] = true;
            const ev: calendarManager.Event = {
              type: calendarManager.EventType.NORMAL,
              title: title,
              startTime: stT.getTime(),
              endTime: etT.getTime(),
              description: desc
            };
            if (rt.length > 0) { ev.reminderTime = rt; }
            try { await cal.addEvent(ev); added++; } catch (_e) { /* ignore */ }
          }
        }
      }
    }
    return added;
  }

  static async syncE(mon: Date, cal: calendarManager.Calendar,
    grid: SlimCell[][][], existMap: Record<string, number[]>,
    meta: Record<string, EventMeta>,
    needed: Record<string, boolean>, pre: number, dbl: boolean,
    dbH: number, dbM: number, written: Record<string, boolean>): Promise<number> {
    let added: number = 0;
    for (let d = 1; d <= DC; d++) {
      for (let s = 1; s <= SC; s++) {
        const slot: SlimCell[][] | undefined = grid[d];
        const cells: SlimCell[] = (slot !== undefined && slot[s] !== undefined) ? slot[s] : [];
        for (let ci = 0; ci < cells.length; ci++) {
          const cell: SlimCell = cells[ci];
          if (!cell.isExperiment) { continue; }
          if (cell.startSection !== s) { continue; }
          // 需导出的周（index 形式，0=第1周）。优先 weekList；weekList 为空但 weekNum 有效时
          // 单周兜底（服务器单周实验 / 自定义实验首周），对齐导出页 impE/synE。
          const expWeeks: number[] = [];
          for (let w = 0; w < cell.weekList.length; w++) {
            if (cell.weekList[w]) { expWeeks.push(w); }
          }
          if (expWeeks.length === 0 && (cell.weekNum ?? 0) > 0) { expWeeks.push(cell.weekNum); }
          for (let wi = 0; wi < expWeeks.length; wi++) {
            const w: number = expWeeks[wi];
            const dt: Date = new Date(mon);
            dt.setDate(mon.getDate() + (w - 1) * 7 + (d - 1));
            const sp: string[] = getTimeFromCell(cell, true).split(':');
            const ep: string[] = getTimeFromCell(cell, false).split(':');
            if (sp.length < 2 || ep.length < 2) { continue; }
            const stT: Date = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate(),
              parseInt(sp[0]), parseInt(sp[1]), 0);
            const etT: Date = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate(),
              parseInt(ep[0]), parseInt(ep[1]), 0);
            const title: string = CalendarSyncService.eventTitle(cell);
            const desc: string = CalendarSyncService.descE(cell);
            const key: string = CalendarSyncService.cellKey(cell, stT.getTime());
            needed[key] = true;
            const rt: number[] = [];
            if (pre > 0) { rt.push(pre); }
            if (dbl) { rt.push(CalendarSyncService.calcDbMins(stT, dbH, dbM)); }
            const rem: string = CalendarSyncService.remKey(rt);
            const oldIds: number[] = existMap[key] ?? [];
            if (oldIds.length > 0) {
              const em: EventMeta | undefined = meta[key];
              if (em !== undefined && em.desc === desc && em.rem === rem) {
                continue; // 已存在且内容一致 → 跳过
              }
              // 内容/提醒已变（教师/项目/双重提醒调整）→ 删旧重建
              for (let oi = 0; oi < oldIds.length; oi++) {
                try { await cal.deleteEvent(oldIds[oi]); } catch (_e) { /* ignore */ }
              }
            }
            if (written[key]) { continue; }
            written[key] = true;
            const ev: calendarManager.Event = {
              type: calendarManager.EventType.NORMAL,
              title: title,
              startTime: stT.getTime(),
              endTime: etT.getTime(),
              description: desc
            };
            if (rt.length > 0) { ev.reminderTime = rt; }
            try { await cal.addEvent(ev); added++; } catch (_e) { /* ignore */ }
          }
        }
      }
    }
    return added;
  }

  static async syncX(cal: calendarManager.Calendar,
    grid: SlimCell[][][], existMap: Record<string, number[]>,
    meta: Record<string, EventMeta>,
    needed: Record<string, boolean>, pre: number, dbl: boolean,
    dbH: number, dbM: number, written: Record<string, boolean>): Promise<number> {
    let added: number = 0;
    for (let d = 1; d <= DC; d++) {
      const slot: SlimCell[][] | undefined = grid[d];
      const cells: SlimCell[] = (slot !== undefined && slot[0] !== undefined) ? slot[0] : [];
      for (let ci = 0; ci < cells.length; ci++) {
        const cell: SlimCell = cells[ci];
        if (!cell.isExam || cell.examDate.length === 0) { continue; }
        const tp: string = cell.examTimeDesc.split(' ')[0];
        if (tp.length === 0 || tp.indexOf('-') < 0) { continue; }
        const tpa: string[] = tp.split('-');
        if (tpa.length < 2) { continue; }
        const sp: string[] = tpa[0].split(':');
        const ep: string[] = tpa[1].split(':');
        if (sp.length < 2 || ep.length < 2) { continue; }
        const dp: string[] = cell.examDate.split('-');
        if (dp.length < 3) { continue; }
        const es: Date = new Date(parseInt(dp[0]), parseInt(dp[1]) - 1, parseInt(dp[2]),
          parseInt(sp[0]), parseInt(sp[1]), 0);
        const ee: Date = new Date(parseInt(dp[0]), parseInt(dp[1]) - 1, parseInt(dp[2]),
          parseInt(ep[0]), parseInt(ep[1]), 0);
        const title: string = CalendarSyncService.eventTitle(cell);
        const desc: string = CalendarSyncService.descX(cell);
        const key: string = CalendarSyncService.cellKey(cell, es.getTime());
        needed[key] = true;
        const rt: number[] = [];
        if (pre > 0) { rt.push(pre); }
        if (dbl) { rt.push(CalendarSyncService.calcDbMins(es, dbH, dbM)); }
        const rem: string = CalendarSyncService.remKey(rt);
        const oldIds: number[] = existMap[key] ?? [];
        if (oldIds.length > 0) {
          const em: EventMeta | undefined = meta[key];
          if (em !== undefined && em.desc === desc && em.rem === rem) {
            continue; // 已存在且内容一致 → 跳过
          }
          // 座位/教室/提醒变化 → 删旧重建
          for (let oi = 0; oi < oldIds.length; oi++) {
            try { await cal.deleteEvent(oldIds[oi]); } catch (_e) { /* ignore */ }
          }
        }
        if (written[key]) { continue; }
        written[key] = true;
        const ev: calendarManager.Event = {
          type: calendarManager.EventType.NORMAL,
          title: title,
          startTime: es.getTime(),
          endTime: ee.getTime(),
          description: desc
        };
        if (rt.length > 0) { ev.reminderTime = rt; }
        try { await cal.addEvent(ev); added++; } catch (_e) { /* ignore */ }
      }
    }
    return added;
  }
}
