import {
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetIconButton } from './BrowserModalBottomSheet';

const PHONE_SETTINGS_SHEET_HEADER_HEIGHT: number = 40;
const PHONE_SETTINGS_SHEET_HEADER_ROW_HEIGHT: number = 56;

@Component
export struct BrowserPhoneSettingsSheetHeader {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop title: string = '';
  @Prop showBackButton: boolean = false;
  @Prop backAccessibilityText: string = '返回';
  /** Row height. The 40vp button stays centered in it, so a taller modal bar does not shift the glyph. */
  @Prop rowHeight: number = PHONE_SETTINGS_SHEET_HEADER_ROW_HEIGHT;
  /**
   * Extra space below the row. Kept off the default 40vp bar: padding inside a fixed height
   * lifts the button and title instead of adding room underneath.
   */
  @Prop bottomPadding: number = 0;
  onBack: () => void = (): void => {};

  build() {
    Row({ space: 8 }) {
      if (this.showBackButton) {
        BrowserSheetIconButton({
          icon: $r('sys.symbol.chevron_left'),
          iconSize: 20,
          buttonSize: PHONE_SETTINGS_SHEET_HEADER_HEIGHT,
          iconColor: this.storedPrimaryTextColor,
          accessibilityLabel: this.backAccessibilityText,
          immersiveMaterialEnabled: true,
          onAction: (): void => {
            this.onBack();
          }
        })
      }

      Text(this.title)
        .layoutWeight(1)
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(this.rowHeight)
    .alignItems(VerticalAlign.Center)
    .padding({
      left: 16,
      right: 56,
      bottom: this.bottomPadding
    })
    .zIndex(1)
  }
}
