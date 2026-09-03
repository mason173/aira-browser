import { PendingDownloadPromptState } from '../../../services/download/DownloadRuntimeService';
import { BrowserDownloadConfirmOverlayAction } from '../../../core/browser/BrowserDownloadConfirmOverlayCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from './BrowserModalBottomSheet';
import {
  CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER,
  createCenteredDialogMaterial
} from '../common/CenteredDialogSurface';

const DOWNLOAD_FILE_NAME_MAX_LENGTH: number = 180;

@CustomDialog
struct BrowserDownloadConfirmDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link prompt: PendingDownloadPromptState | undefined;
  @Link fileNameDraft: string;
  onAction: (action: BrowserDownloadConfirmOverlayAction) => void =
    (_action: BrowserDownloadConfirmOverlayAction): void => {};

  build() {
    Column({ space: 16 }) {
      if (this.prompt !== undefined) {
        this.buildContent(this.prompt!)
      }
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildContent(prompt: PendingDownloadPromptState) {
    Text(prompt.title)
      .width('100%')
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.storedPrimaryTextColor)
      .textAlign(TextAlign.Center)

    Column({ space: 7 }) {
      Text('文件名')
        .width('100%')
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)

      TextInput({ text: this.fileNameDraft, placeholder: '文件名' })
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .caretColor(this.storedAccentColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .maxLength(DOWNLOAD_FILE_NAME_MAX_LENGTH)
        .onChange((value: string) => {
          this.fileNameDraft = value;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)

    Row({ space: 14 }) {
      if (prompt.totalBytes > 0) {
        Text(`大小 ${this.formatBytes(prompt.totalBytes)}`)
          .fontSize(13)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
      }

      Blank()

      Text(this.resolveSourceText(prompt))
        .constraintSize({ maxWidth: 190 })
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)

    Row({ space: 10 }) {
      BrowserSheetActionButton({
        label: prompt.cancelLabel,
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.onAction({ type: 'cancel', guid: prompt.guid });
        }
      })

      BrowserSheetActionButton({
        label: prompt.confirmLabel,
        emphasis: 'primary',
        actionEnabled: this.fileNameDraft.trim().length > 0,
        accentColor: this.storedAccentColor,
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.onAction({
            type: 'confirm',
            guid: prompt.guid,
            fileName: this.fileNameDraft
          });
        }
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  private resolveSourceText(prompt: PendingDownloadPromptState): string {
    const sourceHost = prompt.sourceHost.trim();
    if (sourceHost.length > 0) {
      return sourceHost;
    }
    const sourceUrl = prompt.url.trim();
    return sourceUrl.length > 0 ? sourceUrl : '未知来源';
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(bytes < 1024 * 100 ? 1 : 0)} KB`;
    }
    if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(bytes < 1024 * 1024 * 100 ? 1 : 0)} MB`;
    }
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  }
}

@Component
export struct BrowserDownloadConfirmOverlay {
  @Prop @Watch('syncVisibility') visible: boolean = false;
  @Prop @Watch('syncPrompt') prompt: PendingDownloadPromptState | undefined = undefined;
  @State private currentPrompt: PendingDownloadPromptState | undefined = undefined;
  @State private fileNameDraft: string = '';
  onAction: (action: BrowserDownloadConfirmOverlayAction) => void =
    (_action: BrowserDownloadConfirmOverlayAction): void => {};
  private dialogOpen: boolean = false;
  private decisionCommitted: boolean = false;
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: BrowserDownloadConfirmDialog({
      prompt: $currentPrompt,
      fileNameDraft: $fileNameDraft,
      onAction: (action: BrowserDownloadConfirmOverlayAction): void => {
        this.commitAction(action);
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    onWillDismiss: (dismissDialogAction: DismissDialogAction): void => {
      this.handleInteractiveDismiss();
      dismissDialogAction.dismiss();
    }
  });

  aboutToAppear(): void {
    this.syncPrompt();
    this.syncVisibility();
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

  private syncPrompt(): void {
    const nextPrompt = this.prompt;
    if (nextPrompt === undefined) {
      this.currentPrompt = undefined;
      this.fileNameDraft = '';
      this.closeDialog();
      return;
    }
    if (this.currentPrompt?.guid !== nextPrompt.guid) {
      this.fileNameDraft = nextPrompt.fileName;
    }
    this.currentPrompt = nextPrompt;
    this.syncVisibility();
  }

  private syncVisibility(): void {
    if (this.visible && this.currentPrompt !== undefined) {
      this.openDialog();
      return;
    }
    this.closeDialog();
  }

  private openDialog(): void {
    if (this.dialogOpen) {
      return;
    }
    this.decisionCommitted = false;
    this.dialogOpen = true;
    this.dialogController.open();
  }

  private commitAction(action: BrowserDownloadConfirmOverlayAction): void {
    if (this.decisionCommitted) {
      return;
    }
    this.decisionCommitted = true;
    this.onAction(action);
    if (this.visible && this.currentPrompt !== undefined && this.currentPrompt.guid !== action.guid) {
      this.decisionCommitted = false;
      return;
    }
    this.closeDialog();
  }

  private handleInteractiveDismiss(): void {
    if (this.decisionCommitted) {
      return;
    }
    this.decisionCommitted = true;
    this.dialogOpen = false;
    if (this.currentPrompt !== undefined) {
      this.onAction({ type: 'cancel', guid: this.currentPrompt.guid });
      return;
    }
    this.onAction({ type: 'reset' });
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
