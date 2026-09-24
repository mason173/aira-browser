import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserLargeScreenModalHeader } from '../browser/BrowserLargeScreenModalHeader';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import {
  CENTERED_DIALOG_HORIZONTAL_PADDING_VP,
  CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER
} from '../common/CenteredDialogSurface';

const SOURCE_EDIT_TEXT_INSET_VP: number = 16;

@CustomDialog
export struct UserScriptSourceEditDialog {
  controller?: CustomDialogController;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Link source: string;
  onSourceChange: (source: string) => void = (_source: string): void => {};
  onSave: () => void = (): void => {};
  onClose: () => void = (): void => {};

  build() {
    Column({ space: 0 }) {
      BrowserLargeScreenModalHeader({
        title: '编辑或粘贴源码',
        dialogMode: true,
        onClose: (): void => {
          this.onClose();
        }
      })

      Column() {
        Column() {
          TextArea({ text: this.source, placeholder: '// ==UserScript==\n// @name ...' })
            .width('100%')
            .layoutWeight(1)
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor(this.storedPrimaryTextColor)
            .placeholderColor(this.storedSecondaryTextColor)
            .caretColor(this.storedAccentColor)
            .backgroundColor(Color.Transparent)
            .borderRadius(0)
            .padding(0)
            .onChange((value: string) => {
              this.source = value;
              this.onSourceChange(value);
            })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          left: SOURCE_EDIT_TEXT_INSET_VP,
          right: SOURCE_EDIT_TEXT_INSET_VP,
          top: SOURCE_EDIT_TEXT_INSET_VP,
          bottom: SOURCE_EDIT_TEXT_INSET_VP
        })
        .backgroundColor(this.storedControlBackgroundColor)
        .borderRadius(12)
        .clip(true)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: CENTERED_DIALOG_HORIZONTAL_PADDING_VP,
        right: CENTERED_DIALOG_HORIZONTAL_PADDING_VP,
        top: 4,
        bottom: 8
      })

      Row() {
        BrowserSheetActionButton({
          label: '完成',
          emphasis: 'primary',
          accentColor: this.storedAccentColor,
          fillAvailableWidth: false,
          buttonWidth: 120,
          buttonHeight: 40,
          fontSize: 14,
          onAction: (): void => {
            this.onSave();
          }
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 20 })
      .justifyContent(FlexAlign.End)
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER)
    .keyboardShortcut(FunctionKey.ESC, [], (): void => {
      this.onClose();
    })
  }
}
