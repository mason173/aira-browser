import {
  BROWSER_LARGE_SCREEN_MODAL_HEADER_ACTION_GAP_VP,
  BROWSER_LARGE_SCREEN_MODAL_HEADER_ACTION_SIZE_VP,
  BROWSER_LARGE_SCREEN_MODAL_HEADER_DIVIDER_WIDTH_VP,
  BROWSER_LARGE_SCREEN_MODAL_HEADER_HEIGHT_VP,
  BROWSER_LARGE_SCREEN_MODAL_HEADER_ICON_SIZE_VP,
  BROWSER_LARGE_SCREEN_MODAL_HEADER_LEFT_PADDING_VP,
  BROWSER_LARGE_SCREEN_MODAL_HEADER_RIGHT_PADDING_VP,
  BROWSER_LARGE_SCREEN_MODAL_HEADER_TITLE_FONT_SIZE_FP
} from '../../../core/browser/BrowserModalPresentationTokens';
import {
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetIconButton } from './BrowserModalBottomSheet';

@Component
export struct BrowserLargeScreenModalHeader {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: string = '';
  @Prop dialogMode: boolean = false;
  @Prop showBackButton: boolean = false;
  @Prop showRefreshButton: boolean = false;
  onBack: () => void = () => {};
  onRefresh: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      Row({ space: BROWSER_LARGE_SCREEN_MODAL_HEADER_ACTION_GAP_VP }) {
        if (this.showBackButton) {
          this.buildActionButton('browser.toolbar.back', '返回', this.onBack)
        } else if (this.dialogMode) {
          Blank()
            .width(BROWSER_LARGE_SCREEN_MODAL_HEADER_ACTION_SIZE_VP)
            .height(BROWSER_LARGE_SCREEN_MODAL_HEADER_ACTION_SIZE_VP)
        }

        Text(this.title)
          .layoutWeight(1)
          .fontSize(this.dialogMode ? 20 : BROWSER_LARGE_SCREEN_MODAL_HEADER_TITLE_FONT_SIZE_FP)
          .fontWeight(this.dialogMode ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(this.dialogMode ? TextAlign.Center : TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.showRefreshButton) {
          this.buildActionButton('browser.toolbar.refresh', '刷新', this.onRefresh)
        }

        this.buildActionButton('browser.tabs.delete', '关闭', this.onClose)
      }
      .width('100%')
      .height(BROWSER_LARGE_SCREEN_MODAL_HEADER_HEIGHT_VP)
      .padding({
        left: BROWSER_LARGE_SCREEN_MODAL_HEADER_LEFT_PADDING_VP,
        right: BROWSER_LARGE_SCREEN_MODAL_HEADER_RIGHT_PADDING_VP
      })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(Color.Transparent)

      Divider()
        .width('100%')
        .strokeWidth(BROWSER_LARGE_SCREEN_MODAL_HEADER_DIVIDER_WIDTH_VP)
        .color(Color.Transparent)
    }
    .width('100%')
  }

  @Builder
  private buildActionButton(
    airaIconId: 'browser.toolbar.back' | 'browser.toolbar.refresh' | 'browser.tabs.delete',
    accessibilityText: string,
    onClick: () => void) {
    BrowserSheetIconButton({
      airaIconId: airaIconId,
      iconSize: BROWSER_LARGE_SCREEN_MODAL_HEADER_ICON_SIZE_VP,
      iconColor: this.dialogMode ? this.storedPrimaryTextColor : this.storedSecondaryTextColor,
      buttonSize: BROWSER_LARGE_SCREEN_MODAL_HEADER_ACTION_SIZE_VP,
      accessibilityLabel: accessibilityText,
      onAction: onClick
    })
  }
}
