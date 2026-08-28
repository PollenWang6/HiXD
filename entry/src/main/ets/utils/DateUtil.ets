// DateUtil.ets — 日期格式化工具
// 统一收敛原散落于 EmptyClassroomPage / HomeDataProvider / SchoolCardPage（fmtDate）、
// ElectricityPage / ElectricityService（dayShift）、LibraryPage / LibspSessionService（fmtDateShort）的重复实现。

// Date → "YYYY-MM-DD"
export function fmtDate(d: Date): string {
  const y: number = d.getFullYear();
  const m: string = String(d.getMonth() + 1).padStart(2, '0');
  const day: string = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

// 相对今天偏移 n 天的 "YYYY-MM-DD"（n>0 表示 n 天前）
export function dayShift(n: number): string {
  const d: number = Date.now() - n * 86400000;
  const dt: Date = new Date(d);
  const y: string = String(dt.getFullYear());
  const m: string = String(dt.getMonth() + 1).padStart(2, '0');
  const day: string = String(dt.getDate()).padStart(2, '0');
  return y + '-' + m + '-' + day;
}

// 把 "2024-09-03" / "2024/9/3" 等规范化为 "YYYY-MM-DD"（保留年份）
export function fmtDateShort(raw: string): string {
  const m: RegExpMatchArray | null = raw.match(/^(\d{4})[\/-](\d{1,2})[\/-](\d{1,2})/);
  if (m) {
    const mm: string = m[2].length === 1 ? '0' + m[2] : m[2];
    const dd: string = m[3].length === 1 ? '0' + m[3] : m[3];
    return m[1] + '-' + mm + '-' + dd;
  }
  return raw.substring(0, 10);
}
