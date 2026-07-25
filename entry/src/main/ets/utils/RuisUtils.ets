// RuisUtils.ets — 睿思论坛工具函数
// 等级（昵称）由「积分」按阈值表换算，对齐安卓 RuisUtils.getLevel / getNextLevel。
// 西电睿思的趣味等级：积分越高段位越高（托儿所 → 博士后）。

export class RuisUtils {
  // 根据积分返回等级昵称（对齐安卓 RuisUtils.getLevel）
  static getLevel(a: number): string {
    if (a >= 0 && a < 100) {
      return '西电托儿所';
    } else if (a < 200) {
      return '西电幼儿园';
    } else if (a < 500) {
      return '西电附小';
    } else if (a < 1000) {
      return '西电附中';
    } else if (a < 2000) {
      return '西电大一';
    } else if (a < 2500) {
      return '西电大二';
    } else if (a < 3000) {
      return '西电大三';
    } else if (a < 3500) {
      return '西电大四';
    } else if (a < 6000) {
      return '西电研一';
    } else if (a < 10000) {
      return '西电研二';
    } else if (a < 14000) {
      return '西电研三';
    } else if (a < 20000) {
      return '西电博一';
    } else if (a < 25000) {
      return '西电博二';
    } else if (a < 30000) {
      return '西电博三';
    } else if (a < 35000) {
      return '西电博四';
    } else if (a < 40000) {
      return '西电博五';
    } else if (a >= 40000 && a < 100000) {
      return '西电博士后';
    } else {
      return '新手上路';
    }
  }

  // 下一等级所需积分（对齐安卓 RuisUtils.getNextLevel）
  static getNextLevel(a: number): number {
    if (a >= 0 && a < 100) {
      return 100;
    } else if (a < 200) {
      return 200;
    } else if (a < 500) {
      return 500;
    } else if (a < 1000) {
      return 1000;
    } else if (a < 2000) {
      return 2000;
    } else if (a < 2500) {
      return 2500;
    } else if (a < 3000) {
      return 3000;
    } else if (a < 3500) {
      return 3500;
    } else if (a < 6000) {
      return 6000;
    } else if (a < 10000) {
      return 10000;
    } else if (a < 14000) {
      return 14000;
    } else if (a < 20000) {
      return 20000;
    } else if (a < 25000) {
      return 25000;
    } else if (a < 30000) {
      return 30000;
    } else if (a < 35000) {
      return 35000;
    } else if (a < 40000) {
      return 40000;
    } else if (a >= 40000) {
      return 60000;
    } else {
      return 100;
    }
  }
}
