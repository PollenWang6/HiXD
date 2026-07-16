import { AccentColors } from '../../utils/AccentColors';
// CalendarExportPage.ets
import { ThemeColors } from '../../utils/ThemeColors';
import { PreferenceUtil } from '../../utils/PreferenceUtil';
import { SemesterUtil } from '../../services/EhallService';
import { calendarManager } from '@kit.CalendarKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'CalendarExportPage';
const DOMAIN: number = 0xFF00;
// [DIAG] 诊断日志开关：排查学校课表重复课导致的日历重复/删不掉问题（排查完可关）
const DIAG: boolean = false;
// [DIAG2] 诊断日志开关：排查①实验编辑为课程后主页预告不刷新 ②导入日历实验数抖动(0/4) 的问题（排查完可关）
const DIAG2: boolean = false;

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
  weekNum: number; // 实验/考试所属周（普通课程为 0，跨多周不填）
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

// 提醒选项预设
const REMINDER_OPTIONS: number[] = [5, 10, 15, 20, 30, 60];

@Component
export struct CalendarExportPage {
  @StorageProp('accent_color') accentColor: string = '#2979FF';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navIndicatorHeight') navIndicatorHeight: number = 0;
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

  @State cCustom: boolean = false;
  @State eCustom: boolean = false;
  @State xCustom: boolean = false;

  @State importing: boolean = false;
  @State resultMsg: string = '';
  @State hasData: boolean = true;
  @State hasChanged: boolean = false;
  @State isBound: boolean = false;  // 是否已导入过日历

  // 统计预览
  @State cCount: number = 0;
  @State eCount: number = 0;
  @State xCount: number = 0;

  private init: Record<string, boolean | string | number> = {};
  private gridCells: SlimCell[][][] = [];
  private forceRebuild: boolean = false;

  aboutToAppear(): void {
    this.loadGrid();
    this.loadConfig();
    this.takeSnapshot();
    this.calcCounts();
    this.isBound = PreferenceUtil.getBool('calendar_bound', false);
  }

  calcCounts(): void {
    let cc = 0, ec = 0, xc = 0;
    for (let d = 1; d <= DC; d++) {
      for (let s = 0; s <= SC; s++) {
        const cells: SlimCell[] = this.gridCells[d]?.[s] ?? [];
        for (const cell of cells) {
          if (cell.isExam) {
            if (cell.examDate.length > 0) xc++;
          } else if (cell.isExperiment) {
            let w = 0;
            for (let i = 0; i < cell.weekList.length; i++) { if (cell.weekList[i]) w++; }
            if (w === 0 && cell.weekNum > 0) w = 1; // 兜底：weekList 空但 weekNum 有效（如服务器单周实验）
            ec += w;
          } else {
            if (s === cell.startSection) {
              let w = 0;
              for (let i = 0; i < cell.weekList.length; i++) { if (cell.weekList[i]) w++; }
              cc += w;
            }
          }
        }
      }
    }
    this.cCount = cc;
    this.eCount = ec;
    this.xCount = xc;
    // [DIAG2] 打印本次导出页读到的计数 + 快照里的实验明细（对照写入日志判断是哪个 source 覆盖）
    if (DIAG2) {
      let expDetail: string = '';
      for (let d = 1; d <= DC; d++) {
        for (let s = 0; s <= SC; s++) {
          const cells: SlimCell[] = this.gridCells[d]?.[s] ?? [];
          for (const cell of cells) {
            if (cell.isExperiment) {
              let wlN: number = 0;
              for (let i = 0; i < cell.weekList.length; i++) { if (cell.weekList[i]) wlN++; }
              if (expDetail.length < 300) {
                expDetail += ('[' + cell.name + ' d=' + d + ' s=' + s + ' wn=' + (cell.weekNum ?? 0) + ' wlN=' + wlN + ']');
              }
            }
          }
        }
      }
      hilog.info(DOMAIN, TAG, '[DIAG2] calcCounts 读快照 hasData=' + this.hasData + ' 课程=' + cc + ' 实验=' + ec + ' 考试=' + xc + ' 实验明细=' + expDetail);
    }
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

  // [DIAG] 扫描课表源数据，检测"同一天同一节次排了多门同名课"的学校侧重复（bug 根源确认）
  diagScanGridDup(): void {
    if (!DIAG) { return; }
    let dupTotal: number = 0;
    let cellTotal: number = 0;
    for (let d = 1; d <= DC; d++) {
      for (let s = 1; s <= SC; s++) {
        const slot: SlimCell[][] | undefined = this.gridCells[d];
        const cells: SlimCell[] = (slot !== undefined && slot[s] !== undefined) ? slot[s] : [];
        const seen: Record<string, number> = {};
        for (let ci = 0; ci < cells.length; ci++) {
          const c: SlimCell = cells[ci];
          if (c.startSection !== s) { continue; }
          cellTotal++;
          const kind: string = c.isExam ? 'X' : (c.isExperiment ? 'E' : 'C');
          // 签名：类型 + 课名 + 起止节 —— 同签名多次即"同格重复课"
          const sig: string = kind + ':' + c.name + '#' + c.startSection + '-' + c.endSection;
          seen[sig] = (seen[sig] === undefined ? 0 : seen[sig]) + 1;
        }
        const sigKeys: string[] = Object.keys(seen);
        for (let i = 0; i < sigKeys.length; i++) {
          if (seen[sigKeys[i]] > 1) {
            dupTotal++;
            hilog.warn(DOMAIN, TAG, '[DIAG] 课表源数据重复 day=' + d + ' section=' + s
              + ' 课程=' + sigKeys[i] + ' 出现' + seen[sigKeys[i]] + '次（学校侧 bug，将导致日历重复/删不掉）');
          }
        }
      }
    }
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
    if (DIAG) {
      hilog.info(DOMAIN, TAG, '[DIAG] ===== doImport 开始 forceRebuild=' + this.forceRebuild
        + ' cEnabled=' + this.cEnabled + ' eEnabled=' + this.eEnabled + ' xEnabled=' + this.xEnabled + ' =====');
      this.diagScanGridDup();
    }
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

      const existMap: Record<string, number[]> = {};
      let evTotalRaw: number = 0;   // [DIAG] 日历事件原始总数
      let evDupCount: number = 0;   // [DIAG] 同 key 多条事件数（含学校重复课副本 / 历史孤儿）
      try {
        const evts: calendarManager.Event[] = await cal.getEvents();
        evTotalRaw = evts.length;
        for (let i = 0; i < evts.length; i++) {
          const ev: calendarManager.Event = evts[i];
          if (ev.id !== undefined && ev.title && ev.startTime) {
            const k: string = ev.title + '|' + String(ev.startTime);
            if (!existMap[k]) { existMap[k] = []; }
            if (DIAG && existMap[k].length > 0) {
              evDupCount++;
              hilog.warn(DOMAIN, TAG, '[DIAG] 日历已存在重复事件 key=' + k
                + ' 已记id数=' + existMap[k].length + ' 新id=' + ev.id
                + '（同 key 多条 → 除首条外均按孤儿/重复副本清理）');
            }
            existMap[k].push(ev.id);
          }
        }
      } catch (_e) {
        // ignore
      }
      if (DIAG) {
        hilog.info(DOMAIN, TAG, '[DIAG] 日历现有事件：原始总数=' + evTotalRaw
          + ' 去重后key数=' + Object.keys(existMap).length + ' 重复(孤儿)数=' + evDupCount);
      }

      const needed: Record<string, boolean> = {};
      const written: Record<string, boolean> = {};  // 本次运行已写入的 key，避免源数据重复课被写多次
      const st: ExportStats = { newCount: 0, delCount: 0, failCount: 0 };
      const rb: boolean = this.forceRebuild;

      if (this.cEnabled) {
        const p: number = this.cNone ? -1 : parseInt(this.cMinutes);
        if (rb || this.courseChg()) {
          await this.impC(mon, cal, existMap, needed, st, p);
        } else {
          await this.synC(mon, cal, existMap, needed, st, p, written);
        }
      }
      if (this.eEnabled) {
        const p: number = this.eNone ? -1 : parseInt(this.eMinutes);
        if (rb || this.expChg()) {
          await this.impE(mon, cal, existMap, needed, st, p, this.eDouble, this.eDbHour, this.eDbMin);
        } else {
          await this.synE(mon, cal, existMap, needed, st, p, this.eDouble, this.eDbHour, this.eDbMin, written);
        }
      }
      if (this.xEnabled) {
        const p: number = this.xNone ? -1 : parseInt(this.xMinutes);
        if (rb || this.examChg()) {
          await this.impX(cal, existMap, needed, st, p, this.xDouble, this.xDbHour, this.xDbMin);
        } else {
          await this.synX(cal, existMap, needed, st, p, this.xDouble, this.xDbHour, this.xDbMin, written);
        }
      }
      this.forceRebuild = false;

      const oldKeys: string[] = Object.keys(existMap);
      if (DIAG) {
        hilog.info(DOMAIN, TAG, '[DIAG] ----- 删除阶段开始 existMap key数=' + oldKeys.length
          + ' needed key数=' + Object.keys(needed).length + ' -----');
      }
      for (let i = 0; i < oldKeys.length; i++) {
        const k: string = oldKeys[i];
        const ids: number[] = existMap[k] || [];
        if (ids.length === 0) { continue; }
        if (needed[k]) {
          // 需要的 key：保留首条，删除其余（含学校重复课副本 + 历史孤儿），避免日历出现重复事件
          for (let j = 1; j < ids.length; j++) {
            try {
              await cal.deleteEvent(ids[j]);
              st.delCount++;
              if (DIAG) { hilog.info(DOMAIN, TAG, '[DIAG] 清理重复副本 key=' + k + ' id=' + ids[j]); }
            } catch (_e) { /* 已删除或不存在，忽略 */ }
          }
        } else {
          for (let j = 0; j < ids.length; j++) {
            try {
              await cal.deleteEvent(ids[j]);
              st.delCount++;
              if (DIAG) { hilog.info(DOMAIN, TAG, '[DIAG] 删除成功 key=' + k + ' id=' + ids[j]); }
            } catch (_e) { /* 忽略 */ }
          }
        }
      }
      if (DIAG) {
        hilog.info(DOMAIN, TAG, '[DIAG] ===== doImport 结束 新增=' + st.newCount
          + ' 删除=' + st.delCount + ' 失败=' + st.failCount
          + '（注意：日历重复孤儿数=' + evDupCount + ' 无法通过本流程删除）=====');
      }

      let msg: string = '';
      if (st.newCount > 0) { msg += '新增 ' + st.newCount + ' 条'; }
      if (st.delCount > 0) { msg += (msg.length > 0 ? '，删除 ' : '删除 ') + st.delCount + ' 条'; }
      if (st.failCount > 0) { msg += (msg.length > 0 ? '，失败 ' : '失败 ') + st.failCount + ' 条'; }
      if (msg.length === 0) { msg = '无变化'; }
      this.resultMsg = msg;
      PreferenceUtil.putBool('calendar_bound', true);
      this.isBound = true;
      this.saveConfig();
      this.takeSnapshot();
    } catch (e) {
      this.resultMsg = '导入失败: ' + String(e);
    }
    this.importing = false;
  }

  // ========== 全量重建 ==========
  async impC(mon: Date, cal: calendarManager.Calendar, existMap: Record<string, number[]>,
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
            if (needed[key]) {
              if (DIAG) {
                hilog.warn(DOMAIN, TAG, '[DIAG] impC 同一key重复写入 key=' + key + ' day=' + d + ' section=' + s
                  + '（源数据重复课 → 跳过，避免日历出现重复事件）');
              }
              continue;
            }
            needed[key] = true;
            const oldIds: number[] = existMap[key] ?? [];
            for (let oi = 0; oi < oldIds.length; oi++) {
              try { await cal.deleteEvent(oldIds[oi]); } catch (_e) { /* ignore */ }
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
            }
          }
        }
      }
    }
  }

  async impE(mon: Date, cal: calendarManager.Calendar, existMap: Record<string, number[]>,
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
          // 收集需导出的周（index 形式，0=第1周）。优先 weekList；若为空但 weekNum 有效，则单周兜底。
          const expWeeks: number[] = [];
          for (let w = 0; w < cell.weekList.length; w++) {
            if (cell.weekList[w]) expWeeks.push(w);
          }
          if (expWeeks.length === 0 && cell.weekNum > 0) expWeeks.push(cell.weekNum);
          for (let wi = 0; wi < expWeeks.length; wi++) {
            const w: number = expWeeks[wi];
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
            if (needed[key]) { continue; }
            needed[key] = true;
            const oldIds: number[] = existMap[key] ?? [];
            for (let oi = 0; oi < oldIds.length; oi++) {
              try { await cal.deleteEvent(oldIds[oi]); } catch (_e) { /* ignore */ }
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
            }
          }
        }
      }
    }
  }

  async impX(cal: calendarManager.Calendar, existMap: Record<string, number[]>,
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
        if (needed[key]) { continue; }
        needed[key] = true;
        const oldIds: number[] = existMap[key] ?? [];
        for (let oi = 0; oi < oldIds.length; oi++) {
          try { await cal.deleteEvent(oldIds[oi]); } catch (_e) { /* ignore */ }
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
        }
      }
    }
  }

  // ========== 增量同步 ==========
  async synC(mon: Date, cal: calendarManager.Calendar, existMap: Record<string, number[]>,
    needed: Record<string, boolean>, st: ExportStats, pre: number,
    written: Record<string, boolean>): Promise<void> {
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
            if (existMap[key] !== undefined && existMap[key].length > 0) { continue; }
            if (written[key]) {
              if (DIAG) {
                hilog.warn(DOMAIN, TAG, '[DIAG] synC 同一key重复命中 key=' + key + ' day=' + d + ' section=' + s
                  + '（源数据重复课 → 跳过，避免重复写入）');
              }
              continue;
            }
            written[key] = true;
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
            }
          }
        }
      }
    }
  }

  async synE(mon: Date, cal: calendarManager.Calendar, existMap: Record<string, number[]>,
    needed: Record<string, boolean>, st: ExportStats, pre: number, dbl: boolean,
    dbH: number, dbM: number, written: Record<string, boolean>): Promise<void> {
    for (let d = 1; d <= DC; d++) {
      for (let s = 1; s <= SC; s++) {
        const slot: SlimCell[][] | undefined = this.gridCells[d];
        const cells: SlimCell[] = (slot !== undefined && slot[s] !== undefined) ? slot[s] : [];
        for (let ci = 0; ci < cells.length; ci++) {
          const cell: SlimCell = cells[ci];
          if (!cell.isExperiment) { continue; }
          if (cell.startSection !== s) { continue; }
          // 收集需导出的周（index 形式，0=第1周）。优先 weekList；若为空但 weekNum 有效，则单周兜底。
          const expWeeks: number[] = [];
          for (let w = 0; w < cell.weekList.length; w++) {
            if (cell.weekList[w]) expWeeks.push(w);
          }
          if (expWeeks.length === 0 && cell.weekNum > 0) expWeeks.push(cell.weekNum);
          for (let wi = 0; wi < expWeeks.length; wi++) {
            const w: number = expWeeks[wi];
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
            if (existMap[key] !== undefined && existMap[key].length > 0) { continue; }
            if (written[key]) { continue; }
            written[key] = true;
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
            }
          }
        }
      }
    }
  }

  async synX(cal: calendarManager.Calendar, existMap: Record<string, number[]>,
    needed: Record<string, boolean>, st: ExportStats, pre: number, dbl: boolean,
    dbH: number, dbM: number, written: Record<string, boolean>): Promise<void> {
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
        if (existMap[key] !== undefined && existMap[key].length > 0) { continue; }
        if (written[key]) { continue; }
        written[key] = true;
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
        }
      }
    }
  }

  // 获取已启用数量
  getEnabledCount(): number {
    return (this.cEnabled ? 1 : 0) + (this.eEnabled ? 1 : 0) + (this.xEnabled ? 1 : 0);
  }

  // 获取已启用类型的日程总条数
  getEnabledTotal(): number {
    let n = 0;
    if (this.cEnabled) n += this.cCount;
    if (this.eEnabled) n += this.eCount;
    if (this.xEnabled) n += this.xCount;
    return n;
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

  // 获取类型颜色
  getTypeColor(t: string): string {
    if (t === 'c') return '#2979FF';
    if (t === 'e') return '#FF9800';
    return '#E91E63';
  }

  // 获取类型图标
  getTypeIcon(t: string): string {
    if (t === 'c') return '📖';
    if (t === 'e') return '🔬';
    return '📋';
  }

  // 获取类型标题
  getTypeTitle(t: string): string {
    if (t === 'c') return '课程';
    if (t === 'e') return '实验';
    return '考试';
  }

  // 获取类型副标题
  getTypeSub(t: string): string {
    if (t === 'c') return '常规课程表';
    if (t === 'e') return '实验课程';
    return '考试安排';
  }

  // 获取条数
  getCount(t: string): number {
    if (t === 'c') return this.cCount;
    if (t === 'e') return this.eCount;
    return this.xCount;
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // ===== 顶部概览卡片 =====
          if (this.hasData) {
            Row() {
              Column() {
                if (this.isBound && !this.hasChanged) {
                  Text('✅ 已同步到系统日历').fontSize(14).fontColor('#FFFFFF')
                  Text(String(this.getEnabledTotal()) + ' 条日程')
                    .fontSize(20).fontWeight(FontWeight.Medium).fontColor('#FFFFFFCC').margin({ top: 4 })
                } else {
                  Text(this.hasChanged ? '保存后同步更改' : '导入到系统日历').fontSize(13).fontColor('#FFFFFFCC')
                  Text(String(this.getEnabledTotal()))
                    .fontSize(36).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').margin({ top: 4 })
                  Text(this.isBound ? '条日程（修改后点保存同步）' : '条日程待导入').fontSize(12).fontColor('#FFFFFF99').margin({ top: 2 })
                }
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)

              // 三类小统计
              Column() {
                Row() {
                  Text('📖 ' + String(this.cCount)).fontSize(13).fontColor(AccentColors.textContrast)
                  Text('  🔬 ' + String(this.eCount)).fontSize(13).fontColor(AccentColors.textContrast)
                  Text('  📋 ' + String(this.xCount)).fontSize(13).fontColor(AccentColors.textContrast)
                }
                // 已启用数量
                Text(this.getEnabledCount() + '/3 已开启')
                  .fontSize(11).fontColor(AccentColors.textContrast).margin({ top: 8 })
              }.alignItems(HorizontalAlign.End)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 20, bottom: 20 })
            .backgroundColor(this.accentColor)
            .borderRadius(16)
            .shadow({ radius: 6, color: this.accentColor + '30', offsetY: 3 })
            .margin({ left: 14, right: 14, top: 12 })
          }

          // ===== 无数据提示 =====
          if (!this.hasData) {
            Column() {
              Text('📭').fontSize(40).margin({ bottom: 12 })
              Text('暂无课表数据').fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
              Text('请先在课表页面加载数据').fontSize(13).fontColor(ThemeColors.textSecondary).margin({ top: 6 })
            }.width('90%').padding(40).borderRadius(12).backgroundColor(ThemeColors.bgCard).margin({ top: 20 })
          }

          // ===== 三类设置卡片 =====
          this.TypeCard('c')
          this.TypeCard('e')
          this.TypeCard('x')

          // ===== 底部操作区 =====
          if (this.hasData) {
            // 主按钮
            Row() {
              if (this.importing) {
                LoadingProgress().width(20).height(20).color('#FFFFFF').margin({ right: 8 })
                Text('导入中...').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
              } else {
                Text(this.hasChanged ? '保存并同步' : '无更改')
                  .fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor(this.hasChanged ? '#FFFFFF' : ThemeColors.textHint)
              }
            }
            .width('100%').height(50)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.hasChanged ? this.accentColor : (ThemeColors.isDark ? '#3A3A3A' : '#E8E8E8'))
            .borderRadius(14)
            .shadow(this.hasChanged ? { radius: 4, color: this.accentColor + '40', offsetY: 2 } : { radius: 0, color: Color.Transparent, offsetY: 0 })
            .margin({ left: 14, right: 14, top: 16 })
            .enabled(this.hasChanged && !this.importing)
            .onClick(() => { this.doImport(); })

            // 次要操作
            Row() {
              Text('🔄 删除所有日程并重新导入')
                .fontSize(13).fontColor('#EF5350')
            }
            .width('100%').height(40)
            .justifyContent(FlexAlign.Center)
            .border({ width: 1, color: '#EF535050' })
            .borderRadius(12)
            .margin({ left: 14, right: 14, top: 10 })
            .enabled(!this.importing)
            .onClick(() => { this.doRefresh(); })
          }

          // ===== 结果提示 =====
          if (this.resultMsg.length > 0) {
            Row() {
              Text(this.resultMsg.indexOf('失败') >= 0 ? '⚠️' : '✅').fontSize(16).margin({ right: 8 })
              Text(this.resultMsg).fontSize(14).fontColor(ThemeColors.textPrimary).layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .borderRadius(14)
            .backgroundColor(this.resultMsg.indexOf('失败') >= 0 ? '#FFEBEE' : (ThemeColors.isDark ? '#1B2E1B' : '#F1F8E9'))
            .border({ width: 1, color: this.resultMsg.indexOf('失败') >= 0 ? '#FFCDD2' : '#C8E6C9' })
            .margin({ left: 14, right: 14, top: 12 })
          }

          // ===== 说明区 =====
          Column() {
            Row() {
              Text('💡').fontSize(16).margin({ right: 6 })
              Text('使用说明').fontSize(14).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
            }.margin({ bottom: 10 })

            Row() {
              Text('1').fontSize(10).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                .width(18).height(18).borderRadius(9).backgroundColor(this.accentColor)
              Text('  开启需要导入的类型（课程/实验/考试）').fontSize(12).fontColor(ThemeColors.textSecondary)
            }.margin({ bottom: 6 })

            Row() {
              Text('2').fontSize(10).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                .width(18).height(18).borderRadius(9).backgroundColor(this.accentColor)
              Text('  设置提醒时间，支持自定义分钟数').fontSize(12).fontColor(ThemeColors.textSecondary)
            }.margin({ bottom: 6 })

            Row() {
              Text('3').fontSize(10).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                .width(18).height(18).borderRadius(9).backgroundColor(this.accentColor)
              Text('  实验和考试支持双重提醒（前一天）').fontSize(12).fontColor(ThemeColors.textSecondary)
            }.margin({ bottom: 6 })

            Row() {
              Text('4').fontSize(10).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                .width(18).height(18).borderRadius(9).backgroundColor(this.accentColor)
              Text('  修改设置后点击保存即可增量同步').fontSize(12).fontColor(ThemeColors.textSecondary)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })
          .borderRadius(14)
          .backgroundColor(ThemeColors.bgCard)
          .shadow({ radius: 2, color: '#00000008', offsetY: 1 })
          .margin({ left: 14, right: 14, top: 12 })

          Blank().height(80 + this.navIndicatorHeight)
        }.width(this.isTablet ? '60%' : '100%').alignSelf(ItemAlign.Center)
      }.width('100%').height('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    }.title({ builder: this.titleBar(), height: 52 + this.statusBarHeight }, { backgroundColor: this.accentColor })
     .backgroundColor(ThemeColors.bgPage).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
     .hideBackButton(true)
  }

  @Builder
  titleBar() {
    Row({ space: 6 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.NORMAL }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([AccentColors.textContrast])
      }.height(40).width(40).onClick(() => { this.pageInfo.pop(); })
      Text('导入系统日历').fontSize(22).fontWeight(FontWeight.Bold).fontColor(AccentColors.textContrast)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.height(52 + this.statusBarHeight).width('100%').padding({ left: 12, right: 12, top: this.statusBarHeight })
  }

  @Builder
  TypeCard(t: string) {
    Column() {
      // 卡片头部：图标 + 标题 + 条数 + Toggle
      Row() {
        // 左侧色块图标
        Stack() {
          Circle().width(40).height(40).fill(this.getTypeColor(t) + '18')
          Text(this.getTypeIcon(t)).fontSize(20)
        }.width(40).height(40)

        Column() {
          Text(this.getTypeTitle(t))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textPrimary)
          Row() {
            Text(this.getTypeSub(t)).fontSize(11).fontColor(ThemeColors.textSecondary)
            Text(' · ').fontSize(11).fontColor(ThemeColors.textHint)
            Text(String(this.getCount(t)) + ' 条').fontSize(11).fontColor(this.getTypeColor(t))
          }.margin({ top: 2 })
        }.layoutWeight(1).margin({ left: 12 })

        Toggle({ type: ToggleType.Switch, isOn: this.getEn(t) })
          .selectedColor(this.accentColor)
          .onChange((v: boolean) => { this.setEn(t, v); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      // 展开内容
      if (this.getEn(t)) {
        // 左侧色条分隔
        Row()
          .width('100%').height(1)
          .backgroundColor(this.getTypeColor(t) + '20')
          .margin({ left: 56, right: 16 })

        this.ReminderSection(t)
      }
    }
    .borderRadius(16).clip(true).backgroundColor(ThemeColors.bgCard)
    .shadow({ radius: 3, color: '#0000000A', offsetY: 1 })
    .margin({ left: 14, right: 14, top: 10 })
  }

  @Builder
  ReminderSection(t: string) {
    Column() {
      // 提醒时间标签
      Text('提前提醒')
        .fontSize(12).fontWeight(FontWeight.Medium).fontColor(ThemeColors.textSecondary)
        .padding({ left: 16, top: 12, bottom: 6 })

      // 提醒选项 — 网格布局，4列
      Grid() {
        ForEach(REMINDER_OPTIONS, (m: number) => {
          GridItem() {
            Text(String(m) + '分')
              .fontSize(13)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: 8, bottom: 8 })
              .borderRadius(10)
              .fontColor(this.getMin(t) === String(m) && !this.getNone(t) && !this.getCustom(t) ? '#FFFFFF' : ThemeColors.textPrimary)
              .fontWeight(this.getMin(t) === String(m) && !this.getNone(t) && !this.getCustom(t) ? FontWeight.Medium : FontWeight.Normal)
              .backgroundColor(this.getMin(t) === String(m) && !this.getNone(t) && !this.getCustom(t) ? this.accentColor : (ThemeColors.isDark ? '#333333' : '#F5F5F5'))
              .onClick(() => { this.setNone(t, false); this.setCustom(t, false); this.setMin(t, String(m)); })
          }
        }, (m: number) => String(m))

        // 自定义
        GridItem() {
          Text('自定义')
            .fontSize(13)
            .width('100%').textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 8 })
            .borderRadius(10)
            .fontColor(this.getCustom(t) && !this.getNone(t) ? '#FFFFFF' : ThemeColors.textPrimary)
            .fontWeight(this.getCustom(t) && !this.getNone(t) ? FontWeight.Medium : FontWeight.Normal)
            .backgroundColor(this.getCustom(t) && !this.getNone(t) ? this.accentColor : (ThemeColors.isDark ? '#333333' : '#F5F5F5'))
            .onClick(() => { this.setNone(t, false); this.setCustom(t, true); })
        }

        // 不提醒
        GridItem() {
          Text('不提醒')
            .fontSize(13)
            .width('100%').textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 8 })
            .borderRadius(10)
            .fontColor(this.getNone(t) ? '#FFFFFF' : '#EF5350')
            .fontWeight(this.getNone(t) ? FontWeight.Medium : FontWeight.Normal)
            .backgroundColor(this.getNone(t) ? '#EF5350' : (ThemeColors.isDark ? '#333333' : '#F5F5F5'))
            .onClick(() => { this.setNone(t, !this.getNone(t)); if (!this.getNone(t)) { this.setCustom(t, false); } })
        }
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(8)
      .columnsGap(8)
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })

      // 自定义输入
      if (this.getCustom(t) && !this.getNone(t)) {
        Row() {
          TextInput({ text: this.getMin(t), placeholder: '输入分钟数' })
            .fontSize(13)
            .type(InputType.Number).maxLength(3)
            .width(80).height(36).borderRadius(10)
            .backgroundColor(ThemeColors.bgPage).border({ width: 1, color: this.accentColor + '40' })
            .onChange((v: string) => { this.setMin(t, v); })
          Text('分钟前提醒').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 8 })
        }.width('100%').padding({ left: 16, right: 16, top: 8 })
      }

      // 双重提醒（仅实验和考试）
      if (t !== 'c') {
        Row()
          .width('100%').height(1)
          .backgroundColor(ThemeColors.isDark ? '#333333' : '#F0F0F0')
          .margin({ left: 16, right: 16, top: 8 })

        Row() {
          Column() {
            Text('双重提醒').fontSize(13).fontColor(ThemeColors.textPrimary)
            Text('前一天额外提醒一次').fontSize(11).fontColor(ThemeColors.textSecondary).margin({ top: 2 })
          }.layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.getDbl(t) })
            .selectedColor(this.accentColor).onChange((v: boolean) => { this.setDbl(t, v); })
        }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })

        if (this.getDbl(t)) {
          Row() {
            Text('前一天').fontSize(12).fontColor(ThemeColors.textSecondary)
            Row() {
              Text(this.getDbTimeStr(t))
                .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.accentColor)
            }
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(10)
            .backgroundColor(this.accentColor + '12')
            .border({ width: 1, color: this.accentColor + '30' })
            .margin({ left: 8 })
            .onClick(() => { this.showTimePicker(t); })
            Text('提醒').fontSize(12).fontColor(ThemeColors.textSecondary).margin({ left: 6 })
          }.width('100%').padding({ left: 16, right: 16, bottom: 14 })
        } else {
          Blank().height(4)
        }
      } else {
        Blank().height(6)
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
