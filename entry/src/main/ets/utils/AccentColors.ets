// AccentColors.ets — 主题色管理（类似 DailyNic 的 presetColor）
import { PreferenceUtil } from './PreferenceUtil';

// 预设主题色：[浅色模式颜色, 深色模式颜色, 名称]
export const ACCENT_PRESETS: string[][] = [
  ['#000000', '#FFFFFF', '雪峰白'],
  ['#5588CC', '#6699DD', '西电蓝'],
  ['#3A6DAA', '#5599CC', '深海蓝'],
  ['#3A9CAA', '#55B8C4', '青碧'],
  ['#3A8880', '#55AA99', '墨绿'],
  ['#5A9E5A', '#66BB66', '森林绿'],
  ['#7CA84E', '#88CC55', '苹果绿'],
  ['#CCB040', '#DDCC55', '金盏'],
  ['#D4982E', '#E8AA44', '暖金'],
  ['#D0782E', '#E88844', '蜜橙'],
  ['#C8704A', '#D88860', '落日'],
  ['#D0583A', '#E06850', '朱砂'],
  ['#B83850', '#CC4460', '桃红'],
  ['#C8385E', '#DD4470', '玫红'],
  ['#8038A0', '#9955BB', '紫罗兰'],
  ['#685A90', '#7766A0', '暮紫'],
  ['#5A6AB8', '#6A7ACC', '鸢尾'],
  ['#6A8088', '#8899A0', '雾灰'],
  ['#785A44', '#886650', '可可色'],
  ['#585858', '#888888', '墨黑'],
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
    const saved: number = PreferenceUtil.getNumber(KEY, 1);
    const idx: number = (saved >= 0 && saved < ACCENT_PRESETS.length) ? saved : 0;
    AccentColors.apply(idx);
  }

  // 根据当前主题模式获取颜色
  static colorForTheme(isDark: boolean, idx: number): string {
    if (idx === -1) return AppStorage.get('accent_color') as string ?? '#5588CC';
    if (idx < 0 || idx >= ACCENT_PRESETS.length) idx = 0;
    return isDark ? ACCENT_PRESETS[idx][1] : ACCENT_PRESETS[idx][0];
  }

  private static apply(index: number): void {
    const isDark = AppStorage.get('theme_is_dark') as boolean ?? false;
    const color = AccentColors.colorForTheme(isDark, index);
    AppStorage.setOrCreate('accent_color', color);
    AppStorage.setOrCreate('accent_index', index);
  }

  // 切换颜色
  static select(index: number): void {
    if (index < 0 || index >= ACCENT_PRESETS.length) return;
    PreferenceUtil.putNumber(KEY, index);
    PreferenceUtil.putString(CUSTOM_KEY, '');
    AccentColors.apply(index);
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
    return ACCENT_PRESETS[idx]?.[2] ?? '西电蓝';
  }
}
