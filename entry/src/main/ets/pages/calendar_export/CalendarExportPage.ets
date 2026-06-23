// CalendarExportPage.ets
import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SemesterUtil } from '../../services/EhallService';
import { calendarManager } from '@kit.CalendarKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

const TAG: string = 'CalendarExportPage';

interface SlimCell {
  name: string;
  teacher: string;
  classroom: string;
  day: number;
  startSection: number;
  endSection: number;
  weekList: boolean[];
  isExam: boolean;
  isExperiment: boolean;
  experimentProject: string;
  examDate: string;
  examTimeDesc: string;
  examSeat: string;
}
interface ExportStats {
  newCount: number;
  delCount: number;
  failCount: number;
}

const ST: string[] = [
  '', '8:30-9:15', '9:20-10:05', '10:25-11:10', '11:15-12:00',
  '14:00-14:45', '14:50-15:35', '15:55-16:40', '16:45-17:30',
  '19:00-19:45', '19:55-20:35', '20:40-21:25'
];
const DC: number = 7;
const SC: number = 11;

@Component
export struct CalendarExportPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  pageInfo: NavPathStack = new NavPathStack();
  @Prop isTablet: boolean = false;

  @State cEnabled: boolean = false;
  @State cMinutes: string = '10';
  @State cNone: boolean = false;
  @State eEnabled: boolean = false;
  @State eMinutes: string = '10';
  @State eNone: boolean = false;
  @State eDouble: boolean = false;
  @State eDbHour: number = 20;
  @State eDbMin: number = 0;
  @State xEnabled: boolean = false;
  @State xMinutes: string = '30';
  @State xNone: boolean = false;
  @State xDouble: boolean = false;
  @State xDbHour: number = 20;
  @State xDbMin: number = 0;

  // 自定义分钟输入框是否显示
  @State cCustom: boolean = false;
  @State eCustom: boolean = false;
  @State xCustom: boolean = false;

  @State importing: boolean = false;
  @State resultMsg: string = '';
  @State hasData: boolean = true;
  @State hasChanged: boolean = false;

  private init: Record<string, boolean | string | number> = {};
  private gridCells: SlimCell[][][] = [];
  private forceRebuild: boolean = false;

  aboutToAppear(): void {
    this.loadGrid();
    this.loadConfig();
    this.takeSnapshot();
  }

  takeSnapshot(): void {
    this.init['cEnabled'] = this.cEnabled;
    this.init['cMinutes'] = this.cMinutes;
    this.init['cNone'] = this.cNone;
    this.init['eEnabled'] = this.eEnabled;
    this.init['eMinutes'] = this.eMinutes;
    this.init['eNone'] = this.eNone;
    this.init['eDouble'] = this.eDouble;
    this.init['eDbHour'] = this.eDbHour;
    this.init['eDbMin'] = this.eDbMin;
    this.init['xEnabled'] = this.xEnabled;
    this.init['xMinutes'] = this.xMinutes;
    this.init['xNone'] = this.xNone;
    this.init['xDouble'] = this.xDouble;
    this.init['xDbHour'] = this.xDbHour;
    this.init['xDbMin'] = this.xDbMin;
    this.hasChanged = false;
  }

  syncChanged(): void {
    this.hasChanged = !(
      this.cEnabled === this.init['cEnabled'] &&
      this.cMinutes === this.init['cMinutes'] &&
      this.cNone === this.init['cNone'] &&
      this.eEnabled === this.init['eEnabled'] &&
      this.eMinutes === this.init['eMinutes'] &&
      this.eNone === this.init['eNone'] &&
      this.eDouble === this.init['eDouble'] &&
      this.eDbHour === this.init['eDbHour'] &&
      this.eDbMin === this.init['eDbMin'] &&
      this.xEnabled === this.init['xEnabled'] &&
      this.xMinutes === this.init['xMinutes'] &&
      this.xNone === this.init['xNone'] &&
      this.xDouble === this.init['xDouble'] &&
      this.xDbHour === this.init['xDbHour'] &&
      this.xDbMin === this.init['xDbMin']
    );
  }

  courseChg(): boolean {
    return this.cEnabled !== this.init['cEnabled'] ||
      this.cMinutes !== this.init['cMinutes'] ||
      this.cNone !== this.init['cNone'];
  }

  expChg(): boolean {
    return this.eEnabled !== this.init['eEnabled'] ||
      this.eMinutes !== this.init['eMinutes'] ||
      this.eNone !== this.init['eNone'] ||
      this.eDouble !== this.init['eDouble'] ||
      this.eDbHour !== this.init['eDbHour'] ||
      this.eDbMin !== this.init['eDbMin'];
  }

  examChg(): boolean {
    return this.xEnabled !== this.init['xEnabled'] ||
      this.xMinutes !== this.init['xMinutes'] ||
      this.xNone !== this.init['xNone'] ||
      this.xDouble !== this.init['xDouble'] ||
      this.xDbHour !== this.init['xDbHour'] ||
      this.xDbMin !== this.init['xDbMin'];
  }

  loadConfig(): void {
    const raw: string = PreferenceUtil.getString('calendar_export_config', '');
    if (raw.length === 0) {
      return;
    }
    try {
      const c: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      if (c['cEnabled'] !== undefined) { this.cEnabled = c['cEnabled'] as boolean; }
      if (c['cMinutes'] !== undefined) { this.cMinutes = c['cMinutes'] as string; }
      if (c['cNone'] !== undefined) { this.cNone = c['cNone'] as boolean; }
      if (c['eEnabled'] !== undefined) { this.eEnabled = c['eEnabled'] as boolean; }
      if (c['eMinutes'] !== undefined) { this.eMinutes = c['eMinutes'] as string; }
      if (c['eNone'] !== undefined) { this.eNone = c['eNone'] as boolean; }
      if (c['eDouble'] !== undefined) { this.eDouble = c['eDouble'] as boolean; }
      if (c['eDbHour'] !== undefined) { this.eDbHour = c['eDbHour'] as number; }
      if (c['eDbMin'] !== undefined) { this.eDbMin = c['eDbMin'] as number; }
      if (c['xEnabled'] !== undefined) { this.xEnabled = c['xEnabled'] as boolean; }
      if (c['xMinutes'] !== undefined) { this.xMinutes = c['xMinutes'] as string; }
      if (c['xNone'] !== undefined) { this.xNone = c['xNone'] as boolean; }
      if (c['xDouble'] !== undefined) { this.xDouble = c['xDouble'] as boolean; }
      if (c['xDbHour'] !== undefined) { this.xDbHour = c['xDbHour'] as number; }
      if (c['xDbMin'] !== undefined) { this.xDbMin = c['xDbMin'] as number; }
    } catch (_e) {
      // ignore
    }
  }

  saveConfig(): void {
    const c: Record<string, Object> = {};
    c['cEnabled'] = this.cEnabled;
    c['cMinutes'] = this.cMinutes;
    c['cNone'] = this.cNone;
    c['eEnabled'] = this.eEnabled;
    c['eMinutes'] = this.eMinutes;
    c['eNone'] = this.eNone;
    c['eDouble'] = this.eDouble;
    c['eDbHour'] = this.eDbHour;
    c['eDbMin'] = this.eDbMin;
    c['xEnabled'] = this.xEnabled;
    c['xMinutes'] = this.xMinutes;
    c['xNone'] = this.xNone;
    c['xDouble'] = this.xDouble;
    c['xDbHour'] = this.xDbHour;
    c['xDbMin'] = this.xDbMin;
    PreferenceUtil.putString('calendar_export_config', JSON.stringify(c));
  }

  loadGrid(): void {
    const raw: string = PreferenceUtil.getString('class_grid_snapshot', '');
    if (raw.length === 0) {
      this.hasData = false;
      return;
    }
    try {
      const slim: Object[][] = JSON.parse(raw) as Object[][];
      for (let d = 0; d <= DC; d++) {
        this.gridCells[d] = [];
        for (let s = 0; s <= SC; s++) {
          const row: Object[] | undefined = slim[d] as Object[] | undefined;
          if (row !== undefined && row[s] !== undefined) {
            this.gridCells[d][s] = row[s] as SlimCell[];
          } else {
            this.gridCells[d][s] = [];
          }
        }
      }
      this.hasData = true;
    } catch (_e) {
      this.hasData = false;
    }
  }

  cellKey(cell: SlimCell, startMs: number): string {
    if (cell.isExam) {
      return '📝 ' + cell.name + '|' + String(startMs);
    }
    if (cell.isExperiment) {
      return '🧪 ' + cell.name + '|' + String(startMs);
    }
    return cell.name + '|' + String(startMs);
  }

  calcDbMins(startTime: Date, dbH: number, dbM: number): number {
    const db: Date = new Date(startTime);
    db.setDate(db.getDate() - 1);
    db.setHours(dbH, dbM, 0, 0);
    return Math.floor((startTime.getTime() - db.getTime()) / 60000);
  }

  doRefresh(): void {
    this.forceRebuild = true;
    this.doImport();
  }

  async doImport(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    this.resultMsg = '';
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const perms: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
      const grantResult = await atManager.requestPermissionsFromUser(ctx, perms);
      const authResults: number[] = grantResult.authResults;
      let allGranted: boolean = true;
      for (let i = 0; i < authResults.length; i++) {
        if (authResults[i] !== 0) {
          allGranted = false;
          break;
        }
      }
      if (!allGranted) {
        this.resultMsg = '需要日历权限';
        this.importing = false;
        return;
      }

      const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(ctx);
      let cal: calendarManager.Calendar | null = null;
      try {
        const all: calendarManager.Calendar[] = await mgr.getAllCalendars();
        for (let i = 0; i < all.length; i++) {
          if (all[i].getAccount().name === 'HiXD课程表') {
            cal = all[i];
            break;
          }
        }
      } catch (_e) {
        // fallback
      }
      if (cal === null) {
        try {
          const account: calendarManager.CalendarAccount = {
            name: 'HiXD课程表',
            type: calendarManager.CalendarType.LOCAL,
            displayName: 'HiXD课程表'
          };
          cal = await mgr.createCalendar(account);
        } catch (_e) {
          this.resultMsg = '创建日历账户失败';
          this.importing = false;
          return;
        }
      }
      try {
        await cal.setConfig({ enableReminder: true, color: '#4A90D9' });
      } catch (_e) {
        // ignore
      }

      const sem: string = SemesterUtil.getCurrentSemesterCode();
      const sd: Date = SemesterUtil.getSemesterStartDate(sem);
      const sw: number = PreferenceUtil.getNumber('week_swift', 0);
      const mon: Date = new Date(sd);
      mon.setDate(sd.getDate() + (sd.getDay() === 0 ? -6 : 1 - sd.getDay()) + sw * 7);

      const existMap: Record<string, number> = {};
      try {
        const evts: calendarManager.Event[] = await cal.getEvents();
        for (let i = 0; i < evts.length; i++) {
          const ev: calendarManager.Event = evts[i];
          if (ev.id !== undefined && ev.title && ev.startTime) {
            existMap[ev.title + '|' + String(ev.startTime)] = ev.id;
          }
        }
      } catch (_e) {
        // ignore
      }

      const needed: Record<string, boolean> = {};
      const st: ExportStats = { newCount: 0, delCount: 0, failCount: 0 };
      const rb: boolean = this.forceRebuild;

      if (this.cEnabled) {
        const p: number = this.cNone ? -1 : parseInt(this.cMinutes);
        if (rb || this.courseChg()) {
          await this.impC(mon, cal, existMap, needed, st, p);
        } else {
          await this.synC(mon, cal, existMap, needed, st, p);
        }
      }
      if (this.eEnabled) {
        const p: number = this.eNone ? -1 : parseInt(this.eMinutes);
        if (rb || this.expChg()) {
          await this.impE(mon, cal, existMap, needed, st, p, this.eDouble, this.eDbHour, this.eDbMin);
        } else {
          await this.synE(mon, cal, existMap, needed, st, p, this.eDouble, this.eDbHour, this.eDbMin);
        }
      }
      if (this.xEnabled) {
        const p: number = this.xNone ? -1 : parseInt(this.xMinutes);
        if (rb || this.examChg()) {
          await this.impX(cal, existMap, needed, st, p, this.xDouble, this.xDbHour, this.xDbMin);
        } else {
          await this.synX(cal, existMap, needed, st, p, this.xDouble, this.xDbHour, this.xDbMin);
        }
      }
      this.forceRebuild = false;

      const oldKeys: string[] = Object.keys(existMap);
      for (let i = 0; i < oldKeys.length; i++) {
        const k: string = oldKeys[i];
        if (!needed[k]) {
          try {
            await cal.deleteEvent(existMap[k]);
            st.delCount++;
          } catch (e) {
            st.failCount++;
            console.error(TAG, 'del ' + k + ' ' + String(e));
          }
        }
      }

      let msg: string = '';
      if (st.newCount > 0) { msg += '新增 ' + st.newCount + ' 条'; }
      if (st.delCount > 0) { msg += (msg.length > 0 ? '，删除 ' : '删除 ') + st.delCount + ' 条'; }
      if (st.failCount > 0) { msg += (msg.length > 0 ? '，失败 ' : '失败 ') + st.failCount + ' 条'; }
      if (msg.length === 0) { msg = '无变化'; }
      this.resultMsg = msg;
      PreferenceUtil.putBool('calendar_bound', true);
      this.saveConfig();
      this.takeSnapshot();
    } catch (e) {
      this.resultMsg = '导入失败: ' + String(e);
    }
    this.importing = false;
  }

  // ========== 全量重建 ==========
  async impC(mon: Date, cal: calendarManager.Calendar, existMap: Record<string, number>,
    needed: Record<string, boolean>, st: ExportStats, pre: number): Promise<void> {
    for (let d = 1; d <= DC; d++) {
      for (let s = 1; s <= SC; s++) {
        const slot: SlimCell[][] | undefined = this.gridCells[d];
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
            const title: string = cell.name;
            const desc: string = (cell.classroom ? '教室: ' + cell.classroom : '') +
              (cell.teacher ? (cell.classroom ? ' | ' : '') + '教师: ' + cell.teacher : '');
            const key: string = this.cellKey(cell, stT.getTime());
            needed[key] = true;
            const oldId: number | undefined = existMap[key];
            if (oldId !== undefined) {
              try { await cal.deleteEvent(oldId); } catch (_e) { /* ignore */ }
            }
            const ev: calendarManager.Event = {
              type: calendarManager.EventType.NORMAL,
              title: title,
              startTime: stT.getTime(),
              endTime: etT.getTime(),
              description: desc
            };
            if (pre > 0) { ev.reminderTime = [pre]; }
            try {
              await cal.addEvent(ev);
              st.newCount++;
            } catch (e) {
              st.failCount++;
              console.error(TAG, 'impC ' + String(e));
            }
          }
        }
      }
    }
  }

  async impE(mon: Date, cal: calendarManager.Calendar, existMap: Record<string, number>,
    needed: Record<string, boolean>, st: ExportStats, pre: number, dbl: boolean,
    dbH: number, dbM: number): Promise<void> {
    for (let d = 1; d <= DC; d++) {
      for (let s = 1; s <= SC; s++) {
        const slot: SlimCell[][] | undefined = this.gridCells[d];
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
            const title: string = '🧪 ' + cell.name;
            const desc: string = (cell.classroom ? '地点: ' + cell.classroom : '') +
              (cell.experimentProject ? ' 项目: ' + cell.experimentProject : '');
            const key: string = this.cellKey(cell, stT.getTime());
            needed[key] = true;
            const oldId: number | undefined = existMap[key];
            if (oldId !== undefined) {
              try { await cal.deleteEvent(oldId); } catch (_e) { /* ignore */ }
            }
            const ev: calendarManager.Event = {
              type: calendarManager.EventType.NORMAL,
              title: title,
              startTime: stT.getTime(),
              endTime: etT.getTime(),
              description: desc
            };
            const rt: number[] = [];
            if (pre > 0) { rt.push(pre); }
            if (dbl) { rt.push(this.calcDbMins(stT, dbH, dbM)); }
            if (rt.length > 0) { ev.reminderTime = rt; }
            try {
              await cal.addEvent(ev);
              st.newCount++;
            } catch (e) {
              st.failCount++;
              console.error(TAG, 'impE ' + String(e));
            }
          }
        }
      }
    }
  }

  async impX(cal: calendarManager.Calendar, existMap: Record<string, number>,
    needed: Record<string, boolean>, st: ExportStats, pre: number, dbl: boolean,
    dbH: number, dbM: number): Promise<void> {
    for (let d = 1; d <= DC; d++) {
      const slot: SlimCell[][] | undefined = this.gridCells[d];
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
        const title: string = '📝 ' + cell.name;
        const desc: string = (cell.classroom ? '地点: ' + cell.classroom : '') +
          (cell.examSeat ? ' 座位: ' + cell.examSeat : '');
        const key: string = this.cellKey(cell, es.getTime());
        needed[key] = true;
        const oldId: number | undefined = existMap[key];
        if (oldId !== undefined) {
          try { await cal.deleteEvent(oldId); } catch (_e) { /* ignore */ }
        }
        const ev: calendarManager.Event = {
          type: calendarManager.EventType.NORMAL,
          title: title,
          startTime: es.getTime(),
          endTime: ee.getTime(),
          description: desc
        };
        const rt: number[] = [];
        if (pre > 0) { rt.push(pre); }
        if (dbl) { rt.push(this.calcDbMins(es, dbH, dbM)); }
        if (rt.length > 0) { ev.reminderTime = rt; }
        try {
          await cal.addEvent(ev);
          st.newCount++;
        } catch (e) {
          st.failCount++;
          console.error(TAG, 'impX ' + String(e));
        }
      }
    }
  }

  // ========== 增量同步 ==========
  async synC(mon: Date, cal: calendarManager.Calendar, existMap: Record<string, number>,
    needed: Record<string, boolean>, st: ExportStats, pre: number): Promise<void> {
    for (let d = 1; d <= DC; d++) {
      for (let s = 1; s <= SC; s++) {
        const slot: SlimCell[][] | undefined = this.gridCells[d];
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
            const key: string = this.cellKey(cell, stT.getTime());
            needed[key] = true;
            if (existMap[key] !== undefined) { continue; }
            const title: string = cell.name;
            const desc: string = (cell.classroom ? '教室: ' + cell.classroom : '') +
              (cell.teacher ? (cell.classroom ? ' | ' : '') + '教师: ' + cell.teacher : '');
            const ev: calendarManager.Event = {
              type: calendarManager.EventType.NORMAL,
              title: title,
              startTime: stT.getTime(),
              endTime: etT.getTime(),
              description: desc
            };
            if (pre > 0) { ev.reminderTime = [pre]; }
            try {
              await cal.addEvent(ev);
              st.newCount++;
            } catch (e) {
              st.failCount++;
              console.error(TAG, 'synC ' + String(e));
            }
          }
        }
      }
    }
  }

  async synE(mon: Date, cal: calendarManager.Calendar, existMap: Record<string, number>,
    needed: Record<string, boolean>, st: ExportStats, pre: number, dbl: boolean,
    dbH: number, dbM: number): Promise<void> {
    for (let d = 1; d <= DC; d++) {
      for (let s = 1; s <= SC; s++) {
        const slot: SlimCell[][] | undefined = this.gridCells[d];
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
            const key: string = this.cellKey(cell, stT.getTime());
            needed[key] = true;
            if (existMap[key] !== undefined) { continue; }
            const title: string = '🧪 ' + cell.name;
            const desc: string = (cell.classroom ? '地点: ' + cell.classroom : '') +
              (cell.experimentProject ? ' 项目: ' + cell.experimentProject : '');
            const ev: calendarManager.Event = {
              type: calendarManager.EventType.NORMAL,
              title: title,
              startTime: stT.getTime(),
              endTime: etT.getTime(),
              description: desc
            };
            const rt: number[] = [];
            if (pre > 0) { rt.push(pre); }
            if (dbl) { rt.push(this.calcDbMins(stT, dbH, dbM)); }
            if (rt.length > 0) { ev.reminderTime = rt; }
            try {
              await cal.addEvent(ev);
              st.newCount++;
            } catch (e) {
              st.failCount++;
              console.error(TAG, 'synE ' + String(e));
            }
          }
        }
      }
    }
  }

  async synX(cal: calendarManager.Calendar, existMap: Record<string, number>,
    needed: Record<string, boolean>, st: ExportStats, pre: number, dbl: boolean,
    dbH: number, dbM: number): Promise<void> {
    for (let d = 1; d <= DC; d++) {
      const slot: SlimCell[][] | undefined = this.gridCells[d];
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
        const key: string = this.cellKey(cell, es.getTime());
        needed[key] = true;
        if (existMap[key] !== undefined) { continue; }
        const title: string = '📝 ' + cell.name;
        const desc: string = (cell.classroom ? '地点: ' + cell.classroom : '') +
          (cell.examSeat ? ' 座位: ' + cell.examSeat : '');
        const ev: calendarManager.Event = {
          type: calendarManager.EventType.NORMAL,
          title: title,
          startTime: es.getTime(),
          endTime: ee.getTime(),
          description: desc
        };
        const rt: number[] = [];
        if (pre > 0) { rt.push(pre); }
        if (dbl) { rt.push(this.calcDbMins(es, dbH, dbM)); }
        if (rt.length > 0) { ev.reminderTime = rt; }
        try {
          await cal.addEvent(ev);
          st.newCount++;
        } catch (e) {
          st.failCount++;
          console.error(TAG, 'synX ' + String(e));
        }
      }
    }
  }

  // ==================== UI ====================
  showTimePicker(t: string): void {
    const h: number = t === 'e' ? this.eDbHour : this.xDbHour;
    const m: number = t === 'e' ? this.eDbMin : this.xDbMin;
    TimePickerDialog.show({
      selected: new Date(2020, 0, 1, h, m, 0),
      useMilitaryTime: true,
      onAccept: (v: TimePickerResult) => {
        if (v.hour !== undefined && v.minute !== undefined) {
          if (t === 'e') {
            this.eDbHour = v.hour;
            this.eDbMin = v.minute;
          } else {
            this.xDbHour = v.hour;
            this.xDbMin = v.minute;
          }
          this.syncChanged();
        }
      }
    });
  }

  getDbTimeStr(t: string): string {
    const h: number = t === 'e' ? this.eDbHour : this.xDbHour;
    const m: number = t === 'e' ? this.eDbMin : this.xDbMin;
    return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0');
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          if (!this.hasData) {
            Column() {
              Text('📭').fontSize(40).margin({ bottom: 12 })
              Text('暂无课表数据').fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              Text('请先在课表页面加载数据').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 6 })
            }.width('90%').padding(40).borderRadius(12).backgroundColor(ThemeColors.bgCard).margin({ top: 20 })
          }

          this.Card('📖', '课程', '课表中的所有课程', 'c')
          this.Card('🔬', '实验', '所有实验课程和物理实验', 'e')
          this.Card('📋', '考试', '考试日程安排', 'x')

          if (this.hasData) {
            Button(this.importing ? '导入中...' : '保存设置')
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
              .backgroundColor(this.hasChanged ? this.accentColor : '#CCCCCC').borderRadius(12)
              .width('100%').height(48).margin({ left: 16, right: 16, top: 16 })
              .enabled(this.hasChanged && !this.importing).onClick(() => { this.doImport(); })
            Button('删除所有日程并重新导入')
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#EF5350')
              .backgroundColor(Color.Transparent).border({ width: 1, color: '#EF5350' }).borderRadius(12)
              .width('100%').height(40).margin({ left: 16, right: 16, top: 8 })
              .enabled(!this.importing).onClick(() => { this.doRefresh(); })
          }

          if (this.resultMsg.length > 0) {
            Row() {
              Text(this.resultMsg.indexOf('失败') >= 0 ? '⚠️' : '✅').fontSize(14).margin({ right: 6 })
              Text(this.resultMsg).fontSize(13).fontColor(ThemeColors.textPrimary)
            }.width('100%').padding(14).borderRadius(12).backgroundColor(ThemeColors.bgCard)
             .margin({ left: 16, right: 16, top: 12 })
          }

          Column() {
            Text('💡 说明').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              .margin({ bottom: 6 })
            Text('• 分别选择是否导入课程 / 实验 / 考试\n• 独立设置每节课前的提醒时间\n• 实验和考试支持双重提醒（前一天指定时刻）\n• 下方提供全量重建选项')
              .fontSize(12).fontColor(ThemeColors.textSecondary).lineHeight(18)
          }.width('100%').padding(14).borderRadius(12).backgroundColor(ThemeColors.bgCard)
           .shadow({ radius: 2, color: '#00000008', offsetY: 1 }).margin({ left: 16, right: 16, top: 12 })

          Blank().height(100)
        }.width(this.isTablet ? '60%' : '100%').alignSelf(ItemAlign.Center)
      }.width('100%').height('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    }.title(this.titleBar(), { backgroundColor: this.accentColor })
     .backgroundColor(ThemeColors.bgPage).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
     .hideBackButton(true)
  }

  @Builder
  titleBar() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([Color.White])
      }.height(40).width(40).onClick(() => { this.pageInfo.pop(); })
      Text('导入系统日历').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.height(56).width('100%').padding({ left: 12, right: 12 })
  }

  @Builder
  Card(icon: string, title: string, sub: string, t: string) {
    Column() {
      Row() {
        Text(icon).fontSize(20).margin({ right: 10 })
        Column() {
          Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Text(sub).fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
        }.layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.getEn(t) })
          .selectedColor(this.accentColor).onChange((v: boolean) => { this.setEn(t, v); })
      }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      if (this.getEn(t)) {
        Divider().color('#E8E8E8').strokeWidth(0.5).margin({ left: 16, right: 16 })
        this.Capsule(t)
      }
    }.borderRadius(12).clip(true).backgroundColor(ThemeColors.bgCard)
     .shadow({ radius: 2, color: '#00000008', offsetY: 1 }).margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  Capsule(t: string) {
    Column() {
      Flex({ wrap: FlexWrap.Wrap }) {
        Text('提前').fontSize(12).fontColor(ThemeColors.textHint).margin({ right: 6 })
        ForEach([5, 10, 15, 20, 30], (m: number) => {
          Text(String(m) + '分钟').fontSize(12).padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(12)
            .fontColor(this.getMin(t) === String(m) && !this.getNone(t) && !this.getCustom(t) ? '#FFF' : ThemeColors.textPrimary)
            .fontWeight(this.getMin(t) === String(m) && !this.getNone(t) && !this.getCustom(t) ? FontWeight.Medium : FontWeight.Normal)
            .backgroundColor(this.getMin(t) === String(m) && !this.getNone(t) && !this.getCustom(t) ? this.accentColor : ThemeColors.bgPage)
            .margin({ right: 6, bottom: 6 })
            .onClick(() => { this.setNone(t, false); this.setCustom(t, false); this.setMin(t, String(m)); })
        }, (m: number) => String(m))
        Text('自定义').fontSize(12).padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(12)
          .fontColor(this.getCustom(t) && !this.getNone(t) ? '#FFF' : ThemeColors.textPrimary)
          .fontWeight(this.getCustom(t) && !this.getNone(t) ? FontWeight.Medium : FontWeight.Normal)
          .backgroundColor(this.getCustom(t) && !this.getNone(t) ? this.accentColor : ThemeColors.bgPage)
          .margin({ right: 6, bottom: 6 })
          .onClick(() => { this.setNone(t, false); this.setCustom(t, true); })
        Text('不提醒').fontSize(12).padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(12)
          .fontColor(this.getNone(t) ? '#FFF' : ThemeColors.textPrimary)
          .fontWeight(this.getNone(t) ? FontWeight.Medium : FontWeight.Normal)
          .backgroundColor(this.getNone(t) ? '#EF5350' : ThemeColors.bgPage).margin({ right: 6, bottom: 6 })
          .onClick(() => { this.setNone(t, !this.getNone(t)); if (!this.getNone(t)) { this.setCustom(t, false); } })
      }.width('100%').padding({ left: 16, right: 16, top: 8 })

      if (this.getCustom(t) && !this.getNone(t)) {
        Row() {
          TextInput({ text: this.getMin(t), placeholder: '分钟数' }).fontSize(13)
            .type(InputType.Number).maxLength(3).width(64).height(32).borderRadius(8)
            .backgroundColor(ThemeColors.bgPage).border({ width: 1, color: '#E0E0E0' })
            .onChange((v: string) => { this.setMin(t, v); })
          Text('分钟').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 6 })
        }.width('100%').padding({ left: 16, right: 16, bottom: 6 })
      }

      if (t !== 'c') {
        Row() {
          Column() {
            Text('双重提醒').fontSize(13).fontColor(ThemeColors.textPrimary)
            Text('前一天指定时刻提醒').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
          }.layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.getDbl(t) })
            .selectedColor(this.accentColor).onChange((v: boolean) => { this.setDbl(t, v); })
        }.width('100%').padding({ left: 16, right: 16 }).margin({ top: 4, bottom: 8 })
        if (this.getDbl(t)) {
          Row() {
            Text('前一天').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ right: 8 })
            Row() {
              Text(this.getDbTimeStr(t)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.accentColor)
            }.padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(8)
             .backgroundColor(this.accentColor + '12')
             .border({ width: 1, color: this.accentColor + '40' })
             .onClick(() => { this.showTimePicker(t); })
            Text('提醒').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 6 })
          }.width('100%').padding({ left: 16, right: 16, bottom: 12 })
        }
      }
    }
  }

  // ==================== getter/setter ====================
  getEn(t: string): boolean {
    if (t === 'c') { return this.cEnabled; }
    if (t === 'e') { return this.eEnabled; }
    return this.xEnabled;
  }
  setEn(t: string, v: boolean): void {
    if (t === 'c') { this.cEnabled = v; }
    else if (t === 'e') { this.eEnabled = v; }
    else { this.xEnabled = v; }
    this.syncChanged();
  }
  getMin(t: string): string {
    if (t === 'c') { return this.cMinutes; }
    if (t === 'e') { return this.eMinutes; }
    return this.xMinutes;
  }
  setMin(t: string, v: string): void {
    if (t === 'c') { this.cMinutes = v; }
    else if (t === 'e') { this.eMinutes = v; }
    else { this.xMinutes = v; }
    this.syncChanged();
  }
  getNone(t: string): boolean {
    if (t === 'c') { return this.cNone; }
    if (t === 'e') { return this.eNone; }
    return this.xNone;
  }
  setNone(t: string, v: boolean): void {
    if (t === 'c') { this.cNone = v; }
    else if (t === 'e') { this.eNone = v; }
    else { this.xNone = v; }
    this.syncChanged();
  }
  getDbl(t: string): boolean {
    if (t === 'e') { return this.eDouble; }
    return this.xDouble;
  }
  setDbl(t: string, v: boolean): void {
    if (t === 'e') { this.eDouble = v; }
    else { this.xDouble = v; }
    this.syncChanged();
  }
  getCustom(t: string): boolean {
    if (t === 'c') { return this.cCustom; }
    if (t === 'e') { return this.eCustom; }
    return this.xCustom;
  }
  setCustom(t: string, v: boolean): void {
    if (t === 'c') { this.cCustom = v; }
    else if (t === 'e') { this.eCustom = v; }
    else { this.xCustom = v; }
    this.syncChanged();
  }
}
