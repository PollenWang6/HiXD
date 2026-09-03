// 首页课表预览 & 节次时间 共享定义
// 由 MainPage 与 HomeTab 共用，避免跨文件重复定义。

// 节次时间表（与ClassTablePage一致）
export const SECTION_TIMES: string[][] = [
  ['08:30', '09:15'],  // 第1节
  ['09:20', '10:05'],  // 第2节
  ['10:25', '11:10'],  // 第3节
  ['11:15', '12:00'],  // 第4节
  ['14:00', '14:45'],  // 第5节
  ['14:50', '15:35'],  // 第6节
  ['15:55', '16:40'],  // 第7节
  ['16:45', '17:30'],  // 第8节
  ['19:00', '19:45'],  // 第9节
  ['19:55', '20:35'],  // 第10节
  ['20:40', '21:25'],  // 第11节
];

// 节次→时间 共享表（1-indexed，与 SECTION_TIMES 对齐，两端一致）
// Production: PreviewCell/ClassCell/SlimCell/CustomCourseItem 创生时从此表填充 startTime/endTime
export const SEC_START: string[] = ['', '08:30','09:20','10:25','11:15','14:00','14:50','15:55','16:45','19:00','19:55','20:40'];
export const SEC_END:   string[] = ['', '09:15','10:05','11:10','12:00','14:45','15:35','16:40','17:30','19:45','20:35','21:25'];

// 预览卡片用的轻量数据结构
export class PreviewCell {
  name: string = '';
  classroom: string = '';
  teacher: string = '';
  seat: string = '';
  day: number = 0;        // 1-7 周一~周日
  startSection: number = 0; // 1-11
  endSection: number = 0;   // 1-11
  startTime: string = '';   // 开始钟点 HH:MM（实验/考试优先用此字段，跳过 section→time 转换）
  endTime: string = '';     // 结束钟点 HH:MM
  isExperiment: boolean = false;
  isCustom: boolean = false;
  isExam: boolean = false;
  examTimeDesc: string = '';
  examDate: string = '';        // 考试绝对日期 YYYY-MM-DD（日历同步用）
  experimentProject: string = ''; // 实验项目名（日历同步用）
  weekNum: number = 0;    // 哪一周
  weekList: boolean[] = []; // 普通课程的周次列表
  cellKey: string = '';   // 内容指纹 key，供 ForEach 稳定识别、内容变化时强制重建节点
}
