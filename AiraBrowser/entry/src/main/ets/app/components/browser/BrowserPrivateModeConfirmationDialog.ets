import {
  BrowserPrivateModeConfirmationState
} from '../../../core/browser/BrowserPrivateTabCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from './BrowserModalBottomSheet';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct BrowserPrivateModeConfirmationDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link confirmation: BrowserPrivateModeConfirmationState;
  @Link clearPrivateData: boolean;
  cancel: () => void = () => {};
  confirm: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text(this.confirmation.title)
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.confirmation.message)
          .width('100%')
          .fontSize(14)
          .lineHeight(20)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Start)
      }
      .width('100%')

      if (this.confirmation.showClearPrivateDataOption) {
        this.buildClearPrivateDataRow()
      }

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: this.confirmation.cancelLabel,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.cancel();
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: this.confirmation.confirmLabel,
          emphasis: 'primary',
          accentColor: this.storedAccentColor,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm();
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }

  @Builder
  private buildClearPrivateDataRow() {
    Row({ space: 10 }) {
      Checkbox()
        .select(this.clearPrivateData)
        .selectedColor(this.storedAccentColor)
        .width(20)
        .height(20)
        .hitTestBehavior(HitTestMode.None)

      Text(this.confirmation.clearPrivateDataLabel)
        .layoutWeight(1)
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(16)
    .onClick(() => {
      this.clearPrivateData = !this.clearPrivateData;
    })
  }
}
