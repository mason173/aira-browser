import {
  BrowserLargeScreenWebZoomAction,
  BrowserLargeScreenWebZoomSnapshot
} from '../../../core/browser/BrowserLargeScreenWebZoomCoordinator';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';
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
        this.buildZoomButton(
          'reader.decreaseFont',
          '缩小网页',
          this.snapshot.canDecrease,
          'decrease'
        )

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

        this.buildZoomButton(
          'reader.increaseFont',
          '放大网页',
          this.snapshot.canIncrease,
          'increase'
        )
      }
      .width('100%')
      .height(LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP)
      .backgroundColor(this.storedControlBackgroundColor)
      .borderRadius(LARGE_SCREEN_WEB_ZOOM_CONTROL_RADIUS_VP)
      .clip(true)

      BrowserSheetActionButton({
        label: '完成',
        emphasis: 'primary',
        fontSize: 15,
        onAction: () => {
          this.onClose();
          this.controller?.close();
        }
      })
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }

  @Builder
  private buildZoomButton(
    iconId: AiraRenderableIconId,
    label: string,
    enabled: boolean,
    action: BrowserLargeScreenWebZoomAction
  ) {
    BrowserSheetIconButton({
      airaIconId: iconId,
      iconSize: 17,
      buttonSize: LARGE_SCREEN_WEB_ZOOM_CONTROL_HEIGHT_VP,
      actionEnabled: enabled,
      accessibilityLabel: label,
      onAction: () => {
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
