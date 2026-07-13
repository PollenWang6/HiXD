// CalendarSyncService.ets — 课表变更后自动增量同步日历
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { SemesterUtil } from './EhallService';
import { calendarManager } from '@kit.CalendarKit';
import { common } from '@kit.AbilityKit';
export interface SlimCell {
  name: string; teacher: string; classroom: string; day: number;
  startSection: number; endSection: number; weekList: boolean[];
  isExam: boolean; isExperiment: boolean;
  experimentProject: string; examDate: string; examTimeDesc: string; examSeat: string;
  weekNum: number; // 实验/考试所属周（普通课程为 0，跨多周不填）
}

const ST: string[] = ['', '8:30-9:15', '9:20-10:05', '10:25-11:10', '11:15-12:00',
  '14:00-14:45', '14:50-15:35', '15:55-16:40', '16:45-17:30', '19:00-19:45', '19:55-20:35', '20:40-21:25'];
const DC: number = 7;
const SC: number = 11;

export class CalendarSyncService {
  static async autoSync(ctx: common.UIAbilityContext): Promise<void> {
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
    try {
      const evts: calendarManager.Event[] = await cal.getEvents();
      for (let i = 0; i < evts.length; i++) {
        const ev: calendarManager.Event = evts[i];
        if (ev.id !== undefined && ev.title && ev.startTime) {
          const k: string = ev.title + '|' + String(ev.startTime);
          if (!existMap[k]) { existMap[k] = []; }
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
      added += await CalendarSyncService.syncC(mon, cal, grid, existMap, needed, pre, written);
    }
    if (cfg['eEnabled'] === true) {
      const pre: number = cfg['eNone'] === true ? -1 : parseInt(cfg['eMinutes'] as string);
      const dbl: boolean = cfg['eDouble'] === true;
      const dbH: number = cfg['eDbHour'] as number;
      const dbM: number = cfg['eDbMin'] as number;
      added += await CalendarSyncService.syncE(mon, cal, grid, existMap, needed, pre, dbl, dbH, dbM, written);
    }
    if (cfg['xEnabled'] === true) {
      const pre: number = cfg['xNone'] === true ? -1 : parseInt(cfg['xMinutes'] as string);
      const dbl: boolean = cfg['xDouble'] === true;
      const dbH: number = cfg['xDbHour'] as number;
      const dbM: number = cfg['xDbMin'] as number;
      added += await CalendarSyncService.syncX(cal, grid, existMap, needed, pre, dbl, dbH, dbM, written);
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

    if (added > 0 || deleted > 0) {
    }
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

  static cellKey(cell: SlimCell, startMs: number): string {
    if (cell.isExam) { return '📝 ' + cell.name + '|' + String(startMs); }
    if (cell.isExperiment) { return '🧪 ' + cell.name + '|' + String(startMs); }
    return cell.name + '|' + String(startMs);
  }

  static calcDbMins(startTime: Date, dbH: number, dbM: number): number {
    const db: Date = new Date(startTime);
    db.setDate(db.getDate() - 1);
    db.setHours(dbH, dbM, 0, 0);
    return Math.floor((startTime.getTime() - db.getTime()) / 60000);
  }

  static async syncC(mon: Date, cal: calendarManager.Calendar,
    grid: SlimCell[][][], existMap: Record<string, number[]>,
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
            dt.setDate(mon.getDate() + w * 7 + (d - 1));
            const sp: string[] = ST[cell.startSection].split('-');
            const ep: string[] = ST[cell.endSection].split('-');
            if (sp.length < 2 || ep.length < 2) { continue; }
            const stT: Date = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate(),
              parseInt(sp[0].split(':')[0]), parseInt(sp[0].split(':')[1]), 0);
            const etT: Date = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate(),
              parseInt(ep[1].split(':')[0]), parseInt(ep[1].split(':')[1]), 0);
            const key: string = CalendarSyncService.cellKey(cell, stT.getTime());
            needed[key] = true;
            if (existMap[key] !== undefined && existMap[key].length > 0) { continue; }
            if (written[key]) { continue; }
            written[key] = true;
            const ev: calendarManager.Event = {
              type: calendarManager.EventType.NORMAL,
              title: cell.name,
              startTime: stT.getTime(),
              endTime: etT.getTime(),
              description: (cell.classroom ? '教室: ' + cell.classroom : '') +
                (cell.teacher ? (cell.classroom ? ' | ' : '') + '教师: ' + cell.teacher : '')
            };
            if (pre > 0) { ev.reminderTime = [pre]; }
            try { await cal.addEvent(ev); added++; } catch (_e) { /* ignore */ }
          }
        }
      }
    }
    return added;
  }

  static async syncE(mon: Date, cal: calendarManager.Calendar,
    grid: SlimCell[][][], existMap: Record<string, number[]>,
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
          for (let w = 0; w < cell.weekList.length; w++) {
            if (!cell.weekList[w]) { continue; }
            const dt: Date = new Date(mon);
            dt.setDate(mon.getDate() + w * 7 + (d - 1));
            const sp: string[] = ST[cell.startSection].split('-');
            const ep: string[] = ST[cell.endSection].split('-');
            if (sp.length < 2 || ep.length < 2) { continue; }
            const stT: Date = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate(),
              parseInt(sp[0].split(':')[0]), parseInt(sp[0].split(':')[1]), 0);
            const etT: Date = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate(),
              parseInt(ep[1].split(':')[0]), parseInt(ep[1].split(':')[1]), 0);
            const key: string = CalendarSyncService.cellKey(cell, stT.getTime());
            needed[key] = true;
            if (existMap[key] !== undefined && existMap[key].length > 0) { continue; }
            if (written[key]) { continue; }
            written[key] = true;
            const ev: calendarManager.Event = {
              type: calendarManager.EventType.NORMAL,
              title: '🧪 ' + cell.name,
              startTime: stT.getTime(),
              endTime: etT.getTime(),
              description: (cell.classroom ? '地点: ' + cell.classroom : '') +
                (cell.experimentProject ? ' 项目: ' + cell.experimentProject : '')
            };
            const rt: number[] = [];
            if (pre > 0) { rt.push(pre); }
            if (dbl) { rt.push(CalendarSyncService.calcDbMins(stT, dbH, dbM)); }
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
        const key: string = CalendarSyncService.cellKey(cell, es.getTime());
        needed[key] = true;
        if (existMap[key] !== undefined && existMap[key].length > 0) { continue; }
        if (written[key]) { continue; }
        written[key] = true;
        const ev: calendarManager.Event = {
          type: calendarManager.EventType.NORMAL,
          title: '📝 ' + cell.name,
          startTime: es.getTime(),
          endTime: ee.getTime(),
          description: (cell.classroom ? '地点: ' + cell.classroom : '') +
            (cell.examSeat ? ' 座位: ' + cell.examSeat : '')
        };
        const rt: number[] = [];
        if (pre > 0) { rt.push(pre); }
        if (dbl) { rt.push(CalendarSyncService.calcDbMins(es, dbH, dbM)); }
        if (rt.length > 0) { ev.reminderTime = rt; }
        try { await cal.addEvent(ev); added++; } catch (_e) { /* ignore */ }
      }
    }
    return added;
  }
}
