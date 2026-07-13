import { DialogType, PrivacyDocument } from '../common/CustomTypes';

@ObservedV2
export class PrivacyConsentVM {

  @Trace
  public document: PrivacyDocument = [];

  @Trace
  public title: string = '';

  @Trace
  public appIcon: ResourceStr = '';

  @Trace
  public appName: string = '';

  @Trace
  public appDescription: string = '';

  @Trace
  public isOpen: boolean = false;

  @Trace
  public dialogType: DialogType = DialogType.NORMAL;

  @Trace
  public sheetType: SheetType = SheetType.BOTTOM;

  @Trace
  public navPathStack: NavPathStack = new NavPathStack();

  @Trace
  public onAccept: Callback<void> = () => {};

  @Trace
  public onReject: Callback<void> = () => {};

  @Trace
  public close: () => void = () => {};
}
