import {
  BrowserLargeScreenWebZoomAction,
  BrowserLargeScreenWebZoomSnapshot
} from '../../../core/browser/BrowserLargeScreenWebZoomCoordinator';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';
import { BrowserSheetActionButton, BrowserSheetIconButton } from './BrowserModalBottomSheet';

const LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP: number = 40;
const LARGE_SCREEN_WEB_ZOOM_CONTROL_RADIUS_VP: number = 15;
const LARGE_SCREEN_WEB_ZOOM_DIVIDER_WIDTH_VP: number = 1;

@CustomDialog
export struct BrowserLargeScreenWebZoomDialog {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link snapshot: BrowserLargeScreenWebZoomSnapshot;
  onAction: (action: BrowserLargeScreenWebZoomAction) => void =
    (_action: BrowserLargeScreenWebZoomAction): void => {};
  onClose: () => void = (): void => {};

  build() {
    Column({ space: 16 }) {
      Row() {
        Blank()
          .width(64)
          .height(44)

        Text('网页缩放')
          .layoutWeight(1)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        BrowserSheetActionButton({
          label: '默认',
          fillAvailableWidth: false,
          buttonWidth: 64,
          actionEnabled: this.snapshot.available && (!this.snapshot.percentKnown || this.snapshot.percent !== 100),
          fontSize: 15,
          onAction: () => {
            this.onAction('reset');
          }
        })
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)

      Row({ space: 0 }) {
        Stack() {
          if (this.snapshot.canDecrease) {
            this.buildZoomButton('browser.toolbar.zoomOut', '缩小网页', 'decrease', true)
          } else {
            this.buildZoomButton('browser.toolbar.zoomOut', '缩小网页', 'decrease', false)
          }
        }
        .width(LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP)
        .height(LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP)
        .opacity(this.snapshot.canDecrease ? 1 : 0.38)
        .enabled(this.snapshot.canDecrease)

        this.buildDivider()

        Text(this.snapshot.percentLabel)
          .layoutWeight(1)
          .height(LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        this.buildDivider()

        Stack() {
          if (this.snapshot.canIncrease) {
            this.buildZoomButton('browser.toolbar.zoomIn', '放大网页', 'increase', true)
          } else {
            this.buildZoomButton('browser.toolbar.zoomIn', '放大网页', 'increase', false)
          }
        }
        .width(LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP)
        .height(LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP)
        .opacity(this.snapshot.canIncrease ? 1 : 0.38)
        .enabled(this.snapshot.canIncrease)
      }
      .width('100%')
      .height(LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP)
      .backgroundColor(this.storedControlBackgroundColor)
      .borderRadius(LARGE_SCREEN_WEB_ZOOM_CONTROL_RADIUS_VP)
      .clip(true)

      BrowserSheetActionButton({
        stacked: true,
        label: '完成',
        emphasis: 'primary',
        fontSize: 15,
        onAction: () => {
          this.onClose();
          this.controller?.close();
        }
      })
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  @Builder
  private buildZoomButton(
    iconId: AiraRenderableIconId,
    label: string,
    action: BrowserLargeScreenWebZoomAction,
    enabled: boolean
  ) {
    BrowserSheetIconButton({
      airaIconId: iconId,
      iconSize: 17,
      iconColor: enabled ? this.storedPrimaryTextColor : this.storedSecondaryTextColor,
      buttonSize: LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP,
      actionEnabled: enabled,
      accessibilityLabel: label,
      onAction: () => {
        if (action === 'decrease' && !this.snapshot.canDecrease) {
          return;
        }
        if (action === 'increase' && !this.snapshot.canIncrease) {
          return;
        }
        this.onAction(action);
      }
    })
  }

  @Builder
  private buildDivider() {
    Blank()
      .width(LARGE_SCREEN_WEB_ZOOM_DIVIDER_WIDTH_VP)
      .height(20)
      .backgroundColor(this.storedDividerColor)
  }
}
