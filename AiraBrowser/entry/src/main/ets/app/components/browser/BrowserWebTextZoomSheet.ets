import {
  BrowserWebTextZoomAction,
  BrowserWebTextZoomState
} from '../../../core/browser/BrowserWebTextZoomViewModel';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton, BrowserSheetIconButton } from './BrowserModalBottomSheet';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

const WEB_TEXT_ZOOM_CONTROL_HEIGHT: number = 40;
const WEB_TEXT_ZOOM_CONTROL_RADIUS: number = 15;
const WEB_TEXT_ZOOM_DIVIDER_WIDTH: number = 1;

@CustomDialog
export struct BrowserWebTextZoomSheet {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  controller?: CustomDialogController;
  @Link state: BrowserWebTextZoomState;
  onAction: (action: BrowserWebTextZoomAction) => void = (_action: BrowserWebTextZoomAction) => {};

  build() {
    Column({ space: 16 }) {
      Row() {
        Blank()
          .width(56)
          .height(44)

        Text('网页文字大小')
          .layoutWeight(1)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        BrowserSheetActionButton({
          label: '默认',
          fillAvailableWidth: false,
          buttonWidth: 56,
          buttonHeight: 44,
          fontSize: 15,
          actionEnabled: this.state.ratio !== 100,
          onAction: () => {
            this.onAction('reset');
          }
        })
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)

      Row({ space: 0 }) {
        this.buildZoomButton($r('sys.symbol.minus'), '减小网页文字', this.state.canDecrease, () => {
          this.onAction('decrease');
        })

        this.buildDivider()

        Text(this.state.percentLabel)
          .layoutWeight(1)
          .height(WEB_TEXT_ZOOM_CONTROL_HEIGHT)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        this.buildDivider()

        this.buildZoomButton($r('sys.symbol.plus'), '增大网页文字', this.state.canIncrease, () => {
          this.onAction('increase');
        })
      }
      .width('100%')
      .height(WEB_TEXT_ZOOM_CONTROL_HEIGHT)
      .borderRadius(WEB_TEXT_ZOOM_CONTROL_RADIUS)

      Row() {
        BrowserSheetActionButton({
          label: '完成',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }

  @Builder
  private buildZoomButton(icon: Resource, label: string, enabled: boolean, action: () => void) {
    BrowserSheetIconButton({
      icon: icon,
      iconSize: 17,
      buttonSize: WEB_TEXT_ZOOM_CONTROL_HEIGHT,
      actionEnabled: enabled,
      accessibilityLabel: label,
      onAction: () => {
        action();
      }
    })
  }

  @Builder
  private buildDivider() {
    Blank()
      .width(WEB_TEXT_ZOOM_DIVIDER_WIDTH)
      .height(20)
      .backgroundColor(this.storedDividerColor)
  }
}
