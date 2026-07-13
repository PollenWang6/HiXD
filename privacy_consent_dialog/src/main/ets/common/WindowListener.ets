import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { FinalAvoidAreaVM } from '../viewmodels/FinalAvoidAreaVM';

export class WindowListener {

  public avoidArea: FinalAvoidAreaVM = new FinalAvoidAreaVM();

  private mainWindow: window.Window;

  private onAvoidAreaChange: Callback<window.AvoidAreaOptions> = (options: window.AvoidAreaOptions) => {
    if (options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.avoidArea.setIndicatorAvoidArea(options.area);
    } else if (options.type === window.AvoidAreaType.TYPE_CUTOUT) {
      this.avoidArea.setCutoutAvoidArea(options.area);
    }
  };

  private onWindowSizeChange: Callback<window.Size> = (size: window.Size) => {
    this.avoidArea.setWindowSize(size);
  };

  public start(): void {
    this.loadAvoidAreaInfo([
      window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR,
      window.AvoidAreaType.TYPE_CUTOUT
    ]);
    try {
      const windowRect: window.Rect = this.mainWindow.getWindowProperties().windowRect;
      this.onWindowSizeChange({ width: windowRect.width, height: windowRect.height });
      this.mainWindow.on('avoidAreaChange', this.onAvoidAreaChange);
      this.mainWindow.on('windowSizeChange', this.onWindowSizeChange);
    } catch (error) {
      console.error('[WindowListener] ' +
        `Failed to get window properties, errCode: ${error.code}, errMessage: ${error.message}`);
    }

  }

  public stop(): void {
    this.mainWindow.off('avoidAreaChange', this.onAvoidAreaChange);
    this.mainWindow.off('windowSizeChange', this.onWindowSizeChange);
  }

  private loadAvoidAreaInfo(types: window.AvoidAreaType[]): void {
    for (const type of types) {
      try {
        this.onAvoidAreaChange({
          type: type,
          area: this.mainWindow.getWindowAvoidArea(type)
        });
      } catch (error) {
        console.error('[WindowListener] ' +
          `Failed to get window avoid area, errCode: ${error.code}, errMessage: ${error.message}`);
      }
    }
  }

  constructor(ctx: common.UIAbilityContext) {
    try {
      this.mainWindow = ctx.windowStage.getMainWindowSync();
    } catch (error) {
      console.error('[WindowListener] ' +
        `Failed to get main window sync, errCode: ${error.code}, errMessage: ${error.message}`);
      throw new Error(`Failed to get main window: ${error.message}`);
    }
  }
}