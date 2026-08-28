import { ConfigurationConstant } from '@kit.AbilityKit';

export const THEME_KEY = 'theme_color_mode';

// 提前初始化，确保 @StorageLink('theme_is_dark') 声明时 key 已存在
// try/catch 避免 Form Extension (Widget) 进程里 AppStorage 不可用导致崩溃
try { AppStorage.setOrCreate('theme_is_dark', false); } catch (_e) { /* Form Extension 无 AppStorage */ }

let _isDark: boolean = false;
let _prefMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;

export class ThemeColors {
  static get isDark(): boolean { return _isDark; }
  static get currentPref(): number { return _prefMode; }

  /** 初始化（aboutToAppear） */
  static init(mode: number, ctx: Object): void {
    _prefMode = mode;
    const appCtx: ESObject = (ctx as ESObject)['getApplicationContext']() as ESObject;
    appCtx['setColorMode'](mode);
    if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      const stored: boolean | undefined = AppStorage.get('theme_is_dark') as boolean | undefined;
      _isDark = (stored === true);
    } else {
      _isDark = (mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    }
    try { AppStorage.setOrCreate('theme_is_dark', _isDark); } catch (_e) {}
  }

  /** 切换为手动模式（浅色/深色） */
  static applyManual(mode: number, ctx: Object): void {
    _prefMode = mode;
    const appCtx: ESObject = (ctx as ESObject)['getApplicationContext']() as ESObject;
    appCtx['setColorMode'](mode);
    _isDark = (mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    try { AppStorage.setOrCreate('theme_is_dark', _isDark); } catch (_e) {}
  }

  /** 切换为跟随系统 */
  static applyFollowSystem(ctx: Object): void {
    _prefMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    const appCtx: ESObject = (ctx as ESObject)['getApplicationContext']() as ESObject;
    appCtx['setColorMode'](ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  /** onConfigurationUpdate 回调：已知系统实际模式 */
  static onSystemConfig(dark: boolean): void {
    _isDark = dark;
    try { AppStorage.setOrCreate('theme_is_dark', dark); } catch (_e) {}
  }

  static get bgPage(): string         { return _isDark ? '#0F0F11' : '#F5F5F5'; }
  static get bgCard(): string         { return _isDark ? '#1C1C1E' : '#FFFFFF'; }
  static get bgInput(): string        { return _isDark ? '#2C2C2E' : '#F0F0F0'; }
  static get border(): string         { return _isDark ? '#38383A' : '#E8E8E8'; }
  static get textPrimary(): string    { return _isDark ? '#E5E5E5' : '#1A1A1A'; }
  static get textSecondary(): string  { return _isDark ? '#999999' : '#666666'; }
  static get textHint(): string       { return _isDark ? '#666666' : '#999999'; }
  static get textOnDark(): string     { return '#FFFFFF'; }
  static get textOnDarkSub(): string  { return '#FFFFFF88'; }
  static get accent(): string         { return (AppStorage.get('accent_color') as string) ?? '#2979FF'; }
  static get success(): string        { return _isDark ? '#81C784' : '#2E7D32'; }
  static get error(): string          { return _isDark ? '#EF9A9A' : '#C62828'; }
  static get warning(): string        { return _isDark ? '#FFB74D' : '#BF4D00'; }
  static get tabBar(): string         { return _isDark ? '#2C2C2EDD' : '#FFFFFFFF'; }
  static get overlay(): string        { return _isDark ? '#80000000' : '#40000000'; }
  static get headerGradientStart(): string  { return (AppStorage.get('accent_color') as string) ?? '#1A237E'; }
  static get headerGradientEnd(): string    { return (AppStorage.get('accent_color') as string) ?? '#2979FF'; }

  // 用于文字显示的 accent 色（浅色时自动加深）
  static textForAccent(hex: string): string {
    const r: number = parseInt(hex.substring(1, 3), 16);
    const g: number = parseInt(hex.substring(3, 5), 16);
    const b: number = parseInt(hex.substring(5, 7), 16);
    const lum: number = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return lum > 0.7 ? '#2979FF' : hex;
  }

  // 根据背景色亮度返回合适的前景色（白 or 黑）
  static textOnColor(hex: string): string {
    if (hex.length < 7) return '#FFFFFF';
    const r: number = parseInt(hex.substring(1, 3), 16);
    const g: number = parseInt(hex.substring(3, 5), 16);
    const b: number = parseInt(hex.substring(5, 7), 16);
    const lum: number = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return lum > 0.6 ? '#1A1A1A' : '#FFFFFF';
  }
}
