// AccentColors.ets — 主题色管理（类似 DailyNic 的 presetColor）
import { PreferenceUtil } from './PreferenceUtil';

// 预设主题色：[浅色模式颜色, 深色模式颜色, 名称]
export const ACCENT_PRESETS: string[][] = [
  ['#2979FF', '#6699DD', '西电蓝'],
  ['#1565C0', '#5599CC', '深海蓝'],
  ['#00ACC1', '#55B8C4', '青碧'],
  ['#00897B', '#55AA99', '墨绿'],
  ['#2E7D32', '#66BB66', '森林绿'],
  ['#7CB342', '#88CC55', '苹果绿'],
  ['#FDD835', '#DDCC55', '金盏'],
  ['#FFB300', '#E8AA44', '暖金'],
  ['#FF8F00', '#E88844', '蜜橙'],
  ['#E07A4F', '#D88860', '落日'],
  ['#F4511E', '#E06850', '朱砂'],
  ['#D81B60', '#CC4460', '桃红'],
  ['#C2185B', '#DD4470', '玫红'],
  ['#8E24AA', '#9955BB', '紫罗兰'],
  ['#6B5B9A', '#7766A0', '暮紫'],
  ['#5C6BC0', '#6A7ACC', '鸢尾'],
  ['#78909C', '#8899A0', '雾灰'],
  ['#795548', '#886650', '可可色'],
  ['#424242', '#888888', '墨黑'],
  ['#FFFFFF', '#FFFFFF', '雪峰白'],
];

const KEY = 'accent_color';
const CUSTOM_KEY = 'accent_custom';

export class AccentColors {
  // 初始化（应用启动时调用一次）
  static init(): void {
    AccentColors.migrateOrderV2();
    const custom: string = PreferenceUtil.getString(CUSTOM_KEY);
    if (custom.length === 7 && custom.startsWith('#')) {
      AppStorage.setOrCreate('accent_color', custom);
      AppStorage.setOrCreate('accent_index', -1);
      return;
    }
    const saved: number = PreferenceUtil.getNumber(KEY, 0);
    const idx: number = (saved >= 0 && saved < ACCENT_PRESETS.length) ? saved : 0;
    AccentColors.apply(idx);
  }

  /**
   * 一次性顺序迁移：雪峰白由首位(0)移到末位，其余预设 index 整体前移一位。
   * 避免老用户已保存的 accent_color index 因数组重排而错位。
   */
  private static migrateOrderV2(): void {
    const FLAG = 'accent_order_v2';
    if (PreferenceUtil.getBool(FLAG, false)) return;
    // 哨兵值区分「从未保存」与「保存了 0」，避免把全新用户误迁移
    const old: number = PreferenceUtil.getNumber(KEY, -999);
    if (old === -999) {
      // 全新用户：无历史 index，无需迁移，仅打标记
      PreferenceUtil.putBool(FLAG, true);
      return;
    }
    let mapped: number;
    if (old === 0) {
      mapped = ACCENT_PRESETS.length - 1; // 旧雪峰白 → 末尾
    } else if (old > 0) {
      mapped = old - 1;                    // 其余前移一位
    } else {
      mapped = old;                        // -1 自定义，保持
    }
    PreferenceUtil.putNumber(KEY, mapped);
    PreferenceUtil.putBool(FLAG, true);
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

  /**
   * 判断 hex 颜色是否为"亮色"（白字在上面看不清）。
   * 使用简化亮度公式 (0.299R + 0.587G + 0.114B)，阈值 170。
   */
  static isLightColor(hex: string): boolean {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return (0.299 * r + 0.587 * g + 0.114 * b) > 170;
  }

  /** 标题栏文字/图标色：浅底黑字，深底白字 */
  static get textContrast(): Color {
    return AccentColors.isLightColor(AccentColors.currentColor) ? Color.Black : Color.White;
  }

  static get currentName(): string {
    const idx: number = AppStorage.get('accent_index') as number ?? 0;
    if (idx === -1) return '自定义';
    return ACCENT_PRESETS[idx]?.[2] ?? '西电蓝';
  }
}
