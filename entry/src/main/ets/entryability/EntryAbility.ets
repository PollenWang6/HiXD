import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { PreferenceUtil } from '../utils/PreferenceUtil';
import { ThemeColors } from '../utils/ThemeColors';
import { CourseReminderService } from '../services/CourseReminderService';

export default class EntryAbility extends UIAbility {
  private routerPath: string = '';

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    await PreferenceUtil.init(this.context);
    CourseReminderService.getInstance().setContext(this.context);
    if (want?.parameters?.router) {
      this.routerPath = want.parameters.router.toString();
    }
    console.info('EntryAbility', 'PreferenceUtil initialized, routerPath=' + this.routerPath);
  }

  onNewWant(want: Want): void {
    if (want?.parameters?.router) {
      this.routerPath = want.parameters.router.toString();
      this.context.eventHub.emit('cardNavigate', this.routerPath);
    }
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const cm = newConfig.colorMode;
    if (cm === undefined) return;
    const isDark: boolean = (cm === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);

    if (ThemeColors.currentPref === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      ThemeColors.onSystemConfig(isDark);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const sysColorMode = this.context.config.colorMode;
    const sysDark = (sysColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    AppStorage.setOrCreate('theme_is_dark', sysDark);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error('EntryAbility', 'Failed to load content: ' + JSON.stringify(err));
        return;
      }
      console.info('EntryAbility', 'Succeeded in loading content');
      if (this.routerPath) {
        this.context.eventHub.emit('cardNavigate', this.routerPath);
      }
    });
  }
}