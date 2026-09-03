import {
  ClientUpdatePolicyState
} from '../../../services/update/ClientUpdatePolicyService';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

export type ClientUpdateRequiredAction = 'open_update' | 'continue_local';

@CustomDialog
struct ClientUpdateRequiredDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Prop state: ClientUpdatePolicyState = {
    required: false,
    policyId: '',
    minimumVersionCode: 0,
    minimumVersionName: '',
    updateUrl: '',
    message: '',
    checkedAt: 0
  };
  onAction: (action: ClientUpdateRequiredAction) => void =
    (_action: ClientUpdateRequiredAction): void => {};

  build() {
    Column({ space: 16 }) {
      Text('需要升级 Aira')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Text(this.state.message)
        .width('100%')
        .fontSize(15)
        .lineHeight(22)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Start)

      if (this.state.minimumVersionName.length > 0 || this.state.minimumVersionCode > 0) {
        Text(this.buildMinimumVersionText())
          .width('100%')
          .fontSize(13)
          .lineHeight(20)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Start)
      }

      Column({ space: 10 }) {
        BrowserSheetActionButton({
          label: '前往升级',
          emphasis: 'primary',
          accentColor: this.storedAccentColor,
          onAction: (): void => this.commit('open_update')
        })

        BrowserSheetActionButton({
          label: '继续使用本地功能',
          textColor: this.storedAccentColor,
          onAction: (): void => this.commit('continue_local')
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }

  private commit(action: ClientUpdateRequiredAction): void {
    this.onAction(action);
    this.controller?.close();
  }

  private buildMinimumVersionText(): string {
    const name = this.state.minimumVersionName.trim();
    const code = this.state.minimumVersionCode > 0 ? ` (${this.state.minimumVersionCode})` : '';
    return `需要版本 ${name}${code}`;
  }
}

@Component
export struct ClientUpdateRequiredOverlay {
  @Prop @Watch('syncState') state: ClientUpdatePolicyState = {
    required: false,
    policyId: '',
    minimumVersionCode: 0,
    minimumVersionName: '',
    updateUrl: '',
    message: '',
    checkedAt: 0
  };
  @State private currentState: ClientUpdatePolicyState = this.state;
  private dialogOpen: boolean = false;
  private decisionCommitted: boolean = false;
  onAction: (action: ClientUpdateRequiredAction) => void =
    (_action: ClientUpdateRequiredAction): void => {};
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: ClientUpdateRequiredDialog({
      state: $currentState,
      onAction: (action: ClientUpdateRequiredAction): void => this.commitAction(action)
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: true
  });

  aboutToAppear(): void {
    this.syncState();
  }

  aboutToDisappear(): void {
    this.closeDialog();
  }

  build() {
    Row()
      .width(0)
      .height(0)
      .hitTestBehavior(HitTestMode.None)
  }

  private syncState(): void {
    this.currentState = this.state;
    if (this.state.required) {
      this.openDialog();
    } else {
      this.closeDialog();
    }
  }

  private openDialog(): void {
    if (this.dialogOpen) {
      return;
    }
    this.decisionCommitted = false;
    this.dialogOpen = true;
    this.dialogController.open();
  }

  private commitAction(action: ClientUpdateRequiredAction): void {
    if (this.decisionCommitted) {
      return;
    }
    this.decisionCommitted = true;
    this.onAction(action);
    this.closeDialog();
  }

  private closeDialog(): void {
    if (!this.dialogOpen) {
      return;
    }
    this.dialogOpen = false;
    try {
      this.dialogController.close();
    } catch (_error) {
    }
  }
}
