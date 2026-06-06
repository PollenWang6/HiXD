// AccentColors.ets — 主题色管理（类似 DailyNic 的 presetColor）
import { PreferenceUtil } from './PreferenceUtil';

// 预设主题色：[颜色, 名称]
export const ACCENT_PRESETS: string[][] = [
  ['#2979FF', '西电蓝'],
  ['#1565C0', '深蓝'],
  ['#00ACC1', '青碧'],
  ['#00897B', '墨绿'],
  ['#43A047', '森林绿'],
  ['#7CB342', '苹果绿'],
  ['#FDD835', '金盏'],
  ['#FFB300', '暖金'],
  ['#FF8F00', '蜜橙'],
  ['#E07A4F', '落日'],
  ['#F4511E', '朱砂'],
  ['#D81B60', '桃红'],
  ['#E91E63', '玫红'],
  ['#8E24AA', '紫罗兰'],
  ['#6B5B9A', '深海回音'],
  ['#5C6BC0', '鸢尾'],
  ['#78909C', '雾灰'],
  ['#795548', '可可色'],
  ['#424242', '墨黑'],
];

const KEY = 'accent_color';
const CUSTOM_KEY = 'accent_custom';

export class AccentColors {
  // 初始化（应用启动时调用一次）
  static init(): void {
    const custom: string = PreferenceUtil.getString(CUSTOM_KEY);
    if (custom.length === 7 && custom.startsWith('#')) {
      AppStorage.setOrCreate('accent_color', custom);
      AppStorage.setOrCreate('accent_index', -1);
      return;
    }
    const saved: number = PreferenceUtil.getNumber(KEY, 0);
    const idx: number = (saved >= 0 && saved < ACCENT_PRESETS.length) ? saved : 0;
    AppStorage.setOrCreate('accent_color', ACCENT_PRESETS[idx][0]);
    AppStorage.setOrCreate('accent_index', idx);
  }

  // 切换颜色
  static select(index: number): void {
    if (index < 0 || index >= ACCENT_PRESETS.length) return;
    PreferenceUtil.putNumber(KEY, index);
    PreferenceUtil.putString(CUSTOM_KEY, '');
    AppStorage.setOrCreate('accent_color', ACCENT_PRESETS[index][0]);
    AppStorage.setOrCreate('accent_index', index);
  }

  // 自定义颜色
  static selectCustom(hex: string): boolean {
    if (!hex.startsWith('#') || hex.length !== 7) return false;
    if (!/^#[0-9A-Fa-f]{6}$/.test(hex)) return false;
    PreferenceUtil.putString(CUSTOM_KEY, hex);
    AppStorage.setOrCreate('accent_color', hex);
    AppStorage.setOrCreate('accent_index', -1);
    return true;
  }

  static get currentColor(): string {
    return (AppStorage.get('accent_color') as string) ?? '#2979FF';
  }

  static get currentName(): string {
    const idx: number = AppStorage.get('accent_index') as number ?? 0;
    if (idx === -1) return '自定义';
    return ACCENT_PRESETS[idx]?.[1] ?? '西电蓝';
  }
}
