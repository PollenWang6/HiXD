// Models.ets — 共享数据模型和常量（避免循环导入）
// 导出 ehall app ID 常量
export const EHALL_APP_CLASS_TABLE = '4770397878132218';
export const EHALL_APP_EXAM = '4768687067472349';
export const EHALL_APP_SCORE = '4768574631264620';
export const EHALL_APP_EMPTY_CLASSROOM = '4768402106681759';

// ===== 导出的顶层接口 =====
export interface EmptyClassroomItem {
  name: string;
  buildingCode: string;
  roomName: string;
  floor: string;
  isUsed: boolean[];
}

export interface BuildingInfo {
  code: string;
  name: string;
}

// ===== 数据行接口 =====
export interface ClassTableRow {
  KCM: string; KCH: string; KXH: string; SKXQ: string; SKZC: string;
  KSJC: string; JSJC: string; SKJS: string; JASMC: string;
}

export interface ExamRow {
  KCM: string; KSMC: string; KSSJMS: string; KSRQ: string; JASMC: string; ZWH: string;
}

export interface ScoreRow {
  XNXQDM: string; XSKCM: string; ZCJ: string; XF: string;
  XGXKLBDM_DISPLAY: string; SFJG: string;
  KCLBDM_DISPLAY: string; CXCKDM_DISPLAY: string; DJCJLXDM: string;
  DJCJLXDM_DISPLAY: string;
  JXBID: string;
}

export interface EmptyClassroomRow {
  JXLDM: string; JXLJC: string; JXLMC: string; LC: string; JASMC: string;
  JC1: string; JC2: string; JC3: string; JC4: string; JC5: string;
  JC6: string; JC7: string; JC8: string; JC9: string; JC10: string; JC11: string;
}

export interface BuildingRow {
  JXLDM: string; JXLJC: string; JXLMC: string;
}

// ===== 数据模型类 =====
export class ClassItemModel {
  kcm: string = '';
  kch: string = '';
  kxh: string = '';
  skxq: string = '';
  skzc: string = '';
  ksjc: string = '';
  jsjc: string = '';
  skjs: string = '';
  jasmc: string = '';
}

export class ExamItemModel {
  kcm: string = '';
  ksmc: string = '';
  kssjms: string = '';
  ksrq: string = '';
  jasmc: string = '';
  zw: string = '';
}

// 未排课课程（本科生：已选课但尚未安排时间地点）
export class UnscheduledCourse {
  name: string = '';
  code: string = '';
  number: string = '';
  teacher: string = '';
}

// 课表合并后重新序列化的具名接口（ArkTS 严格模式禁止 Record<> 与内联对象类型，必须用具名接口）
export interface SerializedClassRow {
  KCM: string;
  KCH: string;
  KXH: string;
  SKXQ: string;
  SKZC: string;
  KSJC: string;
  JSJC: string;
  SKJS: string;
  JASMC: string;
}
export interface SerializedXskcb {
  rows: SerializedClassRow[];
}
export interface SerializedDatas {
  xskcb: SerializedXskcb;
}
export interface ClassTableRawWrapper {
  datas: SerializedDatas;
}

// 课程变更（调课/停课/补课）
export class ClassChange {
  type: string = '';   // "调课" | "停课" | "补课"
  courseName: string = '';
  courseCode: string = '';
  classNumber: string = '';
  originalWeeks: string = '';    // 原周次描述
  originalDay: string = '';      // 原星期
  originalSection: string = '';  // 原节次
  originalRoom: string = '';     // 原教室
  originalTeacher: string = '';  // 原教师
  newWeeks: string = '';         // 新周次描述
  newDay: string = '';           // 新星期
  newSection: string = '';       // 新节次
  newRoom: string = '';          // 新教室
  newTeacher: string = '';       // 新教师
  // 合并课表网格用的"原始数值/二进制"字段（弹窗用上面格式化字段，合并用下面）
  rawOrigWeeks: string = '';    // 原周次二进制字符串 SKZC
  rawNewWeeks: string = '';     // 新周次二进制字符串 XSKZC
  origDayNum: number = 0;       // 原星期数字（1=周一）
  newDayNum: number = 0;        // 新星期数字
  origStart: number = 0;        // 原起始节次
  origEnd: number = 0;          // 原结束节次
  newStart: number = 0;         // 新起始节次
  newEnd: number = 0;           // 新结束节次
}

export class ScoreItemModel {
  xnxqdm: string = '';
  xskcm: string = '';
  zcj: string = '';
  xf: string = '';
  xgxklbdmDisplay: string = '';
  kclbdmDisplay: string = '';
  cxckdmDisplay: string = '';
  djcjlxdmDisplay: string = '';
  sfjg: string = '';
  jxbid: string = '';
}

export class ComposeDetail {
  content: string = '';
  ratio: string = '';
  score: string = '';
}

// ===== 实验信息数据模型 =====
export enum ExperimentType {
  PHYSICS = 'physics',
  OTHERS = 'others'
}

export class ExperimentData {
  type: ExperimentType = ExperimentType.OTHERS;
  name: string = '';
  classroom: string = '';
  teacher: string = '';
  timeRanges: TimeRange[] = [];
  reference: string = '';
  score: string = '';
}

export class TimeRange {
  startTime: string = '';
  endTime: string = '';
}

// sysj.xidian.edu.cn 解析用时刻表
export const SYSJ_SECTION_TIMES: string[] = [
  '08:30', '09:15',
  '09:20', '10:05',
  '10:25', '11:10',
  '11:15', '12:00',
  '14:00', '14:45',
  '14:50', '15:35',
  '15:55', '16:40',
  '16:45', '17:30',
  '19:00', '19:45',
  '19:55', '20:35',
  '20:40', '21:25',
];
