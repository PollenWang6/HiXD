// AccentColors.ets — 主题色管理（类似 DailyNic 的 presetColor）
import { PreferenceUtil } from './PreferenceUtil';

// 预设主题色：[浅色标题栏, 名称]
export const ACCENT_PRESETS: string[][] = [
  ['#2979FF', '西电蓝'],
  ['#4A90E2', '冰山蓝调'],
  ['#6B5B9A', '深海回音'],
  ['#9B6BB6', '薰衣草田'],
  ['#5F7A8A', '冷石流云'],
  ['#43A047', '森屿青柠'],
  ['#D81B60', '桃启绯英'],
  ['#E07A4F', '落日熔金'],
];

const KEY = 'accent_color';

export class AccentColors {
  // 初始化（应用启动时调用一次）
  static init(): void {
    const saved: number = PreferenceUtil.getNumber(KEY, 0);
    const idx: number = (saved >= 0 && saved < ACCENT_PRESETS.length) ? saved : 0;
    AppStorage.setOrCreate('accent_color', ACCENT_PRESETS[idx][0]);
    AppStorage.setOrCreate('accent_index', idx);
  }

  // 切换颜色
  static select(index: number): void {
    if (index < 0 || index >= ACCENT_PRESETS.length) return;
    PreferenceUtil.putNumber(KEY, index);
    AppStorage.setOrCreate('accent_color', ACCENT_PRESETS[index][0]);
    AppStorage.setOrCreate('accent_index', index);
  }

  static get currentColor(): string {
    const idx: number = AppStorage.get('accent_index') as number ?? 0;
    return ACCENT_PRESETS[idx][0];
  }

  static get currentName(): string {
    const idx: number = AppStorage.get('accent_index') as number ?? 0;
    return ACCENT_PRESETS[idx][1];
  }
}
