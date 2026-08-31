import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsTextField } from '../settings/SettingsRows';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct SiteControlsManualOriginDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link addressDraft: string;
  @Link errorText: string;
  confirm: () => boolean = (): boolean => true;

  build() {
    Column({ space: 16 }) {
      Text('添加站点')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      SettingsTextField({
        text: this.addressDraft,
        placeholder: 'http://192.168.1.10:8080',
        helperText: '输入域名、IP 或完整地址。非默认端口会作为独立站点。',
        errorText: this.errorText,
        inputType: InputType.URL,
        maxLength: 2048,
        controlBackgroundColor: this.storedControlBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        onChange: (value: string): void => {
          this.addressDraft = value;
          this.errorText = '';
        }
      })

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: (): void => {
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: '继续',
          emphasis: 'primary',
          accentColor: this.storedAccentColor,
          buttonHeight: 44,
          fontSize: 15,
          onAction: (): void => {
            if (this.confirm()) {
              this.controller?.close();
            }
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }
}
