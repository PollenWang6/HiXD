// AttendanceModels.ets — 超星学习平台考勤数据模型

// 考勤状态
export enum AttendanceStatus {
  UNKNOWN,
  ELIGIBLE,    // 正常（到课率 >= 90%）
  WARNING,     // 危险
  INELIGIBLE   // 取消（旷课 > 总课时/4）
}

// 课程考勤总览
export class ClassAttendance {
  // 课程信息
  courseName: string = '';
  className: string = '';

  // 考勤数据
  checkInCount: string = '';      // 签到次数
  personalLeave: string = '';     // 事假
  sickLeave: string = '';         // 病假
  officialLeave: string = '';     // 公假
  absenceCount: string = '';      // 旷课次数
  requiredCheckIn: string = '';   // 应签次数
  attendanceRate: string = '';    // 到课率

  // 学习进度
  readCount: string = '';
  unreadCount: string = '';
  accessCount: string = '';
  taskProgress: string = '';
  homeworkProgress: string = '';
  examProgress: string = '';
  discussionCount: string = '';
  materialCount: string = '';

  // 课程标识
  courseId: string = '';
  clazzId: string = '';
  cpi: string = '';

  // 用户设置的该课程总课时（用于判定考勤状态）
  totalTimes: number = 0;

  // 获取考勤状态
  getAttendanceStatus(): AttendanceStatus {
    const total: number = this.totalTimes > 0 ? this.totalTimes : (parseInt(this.requiredCheckIn) || 0) * 2;
    const timeToError: number = Math.floor(total / 4);
    const absenceNum: number = parseInt(this.absenceCount) || 0;
    const absenceHours: number = absenceNum * 2; // 每次缺勤 = 2 课时
    const remainHours: number = timeToError - absenceHours;
    const rateStr: string = this.attendanceRate.replace(' %', '').replace('%', '');
    const rate: number = parseFloat(rateStr);

    if (isNaN(rate)) {
      return AttendanceStatus.UNKNOWN;
    }
    // 可缺勤次数 < 0 → 已超上限 → 取消
    if (remainHours < 0) {
      return AttendanceStatus.INELIGIBLE;
    }
    // 到课率 < 75% → 危险（黄）
    if (rate < 75) {
      return AttendanceStatus.WARNING;
    }
    return AttendanceStatus.ELIGIBLE;
  }

  getStatusLabel(): string {
    switch (this.getAttendanceStatus()) {
      case AttendanceStatus.ELIGIBLE: return '正常';
      case AttendanceStatus.WARNING: return '危险';
      case AttendanceStatus.INELIGIBLE: return '取消';
      default: return '未知';
    }
  }

  getStatusColor(): string {
    switch (this.getAttendanceStatus()) {
      case AttendanceStatus.ELIGIBLE: return '#4CAF50';
      case AttendanceStatus.WARNING: return '#F9A825';
      case AttendanceStatus.INELIGIBLE: return '#F44336';
      default: return '#9E9E9E';
    }
  }

  // 还可缺课次数
  getRemainAbsence(): number {
    const total: number = this.totalTimes > 0 ? this.totalTimes : (parseInt(this.requiredCheckIn) || 0) * 2;
    const timeToError: number = Math.floor(total / 4);
    const absenceNum: number = parseInt(this.absenceCount) || 0;
    const absenceHours: number = absenceNum * 2;
    const remainHours: number = timeToError - absenceHours;
    return Math.floor(remainHours / 2); // 换算回缺勤次数
  }
}

// 单次签到详情
export class ClassAttendanceDetail {
  submittime: string = '';
  createxxuid: string = '';
  userStatus: number = 0;
  creatorName: string = '';
  activeid: number = 0;
  starttime: string = '';
  attendid: number = 0;
  activeType: number = 0;
  name: string = '';
  otherId: number = 0;
  updatetime: number = 0;
  createUid: string = '';
  status: number = 0;

  static fromJson(json: Record<string, Object>): ClassAttendanceDetail {
    const d: ClassAttendanceDetail = new ClassAttendanceDetail();
    d.submittime = json['submittime'] as string ?? '';
    d.createxxuid = json['createxxuid'] as string ?? '';
    d.userStatus = json['userStatus'] as number ?? 0;
    d.creatorName = json['creatorName'] as string ?? '';
    d.activeid = json['activeid'] as number ?? 0;
    d.starttime = json['starttime'] as string ?? '';
    d.attendid = json['attendid'] as number ?? 0;
    d.activeType = json['activeType'] as number ?? 0;
    d.name = json['name'] as string ?? '';
    d.otherId = json['other_id'] as number ?? 0;
    d.updatetime = json['updatetime'] as number ?? 0;
    d.createUid = json['createUid'] as string ?? '';
    d.status = json['status'] as number ?? 0;
    return d;
  }

  getSignStatusLabel(): string {
    switch (this.userStatus) {
      case 1: return '已签';
      case 2: return '教师代签';
      case 4: return '事假';
      case 5: return '旷课';
      case 7: return '病假';
      case 8: return '事假';
      case 9: return '迟到';
      case 10: return '早退';
      case 11: return '签到过期';
      case 12: return '公假';
      default: return '未参与';
    }
  }

  getSignTypeLabel(): string {
    if (this.name && this.name.length > 0) {
      return this.name;
    }
    switch (this.otherId) {
      case 2: return '二维码';
      case 3: return '手势';
      case 4: return '位置';
      default: return '默认';
    }
  }
}
