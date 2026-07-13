import { ComponentContent, ImmersiveMode, LevelMode, PromptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { PrivacyDocument, DialogType } from './common/CustomTypes';
import { PrivacyConsent } from './components/PrivacyConsent';
import { PrivacyConsentVM } from './viewmodels/PrivacyConsentVM';

export class PrivacyConsentController {

  private uiContext: UIContext;

  private promptAction: PromptAction;

  private model: PrivacyConsentVM = new PrivacyConsentVM();

  private node: ComponentContent<PrivacyConsentVM> | null = null;

  public setDocument(doc: PrivacyDocument): PrivacyConsentController {
    this.model.document = doc;
    return this;
  }

  public setTitle(title: string): PrivacyConsentController {
    this.model.title = title;
    return this;
  }

  public setAppIcon(icon: ResourceStr): PrivacyConsentController {
    this.model.appIcon = icon;
    return this;
  }

  public setAppName(name: string): PrivacyConsentController {
    this.model.appName = name;
    return this;
  }

  public setAppDescription(desc: string): PrivacyConsentController {
    this.model.appDescription = desc;
    return this;
  }

  public onAccept(callback: Callback<void>): PrivacyConsentController {
    this.model.onAccept = callback;
    return this;
  }

  public onReject(callback: Callback<void>): PrivacyConsentController {
    this.model.onReject = callback;
    return this;
  }

  public async openDialog(): Promise<boolean> {
    return this.open(DialogType.NORMAL);
  }

  public async openFullScreenDialog(): Promise<boolean> {
    return this.open(DialogType.FULL_SCREEN);
  }

  public async openSheetDialog(): Promise<boolean> {
    return this.open(DialogType.SHEET);
  }

  private async open(dialogType: DialogType): Promise<boolean> {
    if (this.model.isOpen || this.node) {
      return false;
    }
    try {
      this.model.isOpen = true;
      this.model.dialogType = dialogType;
      this.node = new ComponentContent(this.uiContext, wrapBuilder(buildPrivacyConsentDialog), this.model);
      if (dialogType === DialogType.SHEET) {
        await this.uiContext.openBindSheet(this.node, {
          height: SheetSize.LARGE,
          preferType: SheetType.CENTER,
          showClose: false,
          enableOutsideInteractive: false,
          onWillDismiss: () => {},
          onTypeDidChange: (type: SheetType) => this.model.sheetType = type,
          backgroundColor: $r('sys.color.comp_background_primary')
        });
      } else {
        await this.promptAction.openCustomDialog(this.node, {
          alignment: DialogAlignment.Center,
          isModal: true,
          showInSubWindow: false,
          onWillDismiss: (action: DismissDialogAction) => {
            if (action.reason === DismissReason.PRESS_BACK) {
              this.model.navPathStack.pop();
            }
          },
          autoCancel: false,
          transition: TransitionEffect.IDENTITY,
          levelMode: LevelMode.EMBEDDED,
          immersiveMode: ImmersiveMode.EXTEND,
          keyboardAvoidMode: KeyboardAvoidMode.NONE
        });
      }
      return true;
    } catch {
      this.model.isOpen = false;
      this.node = null;
      return false;
    }
  }

  public close(): void {
    if (this.model.isOpen && this.node) {
      this.model.isOpen = false;
      if (this.model.dialogType === DialogType.SHEET) {
        this.uiContext.closeBindSheet(this.node).catch((err: BusinessError) => {
          console.error('[export class PrivacyConsentController] ' +
            `Failed to close sheet, errCode: ${err.code}, errMessage: ${err.message}`);
        }).finally(() => this.node = null);
      } else {
        this.promptAction.closeCustomDialog(this.node).catch((err: BusinessError) => {
          console.error('[export class PrivacyConsentController] ' +
            `Failed to close dialog, errCode: ${err.code}, errMessage: ${err.message}`);
        }).finally(() => this.node = null);
      }
    }
  }

  constructor(uiContext: UIContext) {
    this.uiContext = uiContext;
    this.promptAction = uiContext.getPromptAction();
    this.model.close = () => this.close();
  }
}

@Builder
function buildPrivacyConsentDialog(model: PrivacyConsentVM): void {
  PrivacyConsent({ model: model })
}
