// UrlUtil.ets — URL 相对地址解析
// 统一收敛原散落于 ElectricityService / LibspSessionService 的重复实现（resolveLocation）。

// 把相对重定向地址 loc 解析为绝对地址（基于 from 的域或目录）
export function resolveLocation(from: string, loc: string): string {
  if (loc.startsWith('http://') || loc.startsWith('https://')) {
    return loc;
  }
  const m: RegExpMatchArray | null = from.match(/^(https?:\/\/[^\/]+)/);
  const base: string = m ? m[1] : '';
  if (loc.startsWith('/')) {
    return base + loc;
  }
  const fromNoQuery: string = from.split('?')[0];
  const lastSlash: number = fromNoQuery.lastIndexOf('/');
  const dir: string = fromNoQuery.substring(0, lastSlash + 1);
  return dir + loc;
}
