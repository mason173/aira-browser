import {
  BrowserPageShareAction,
  BrowserPageShareSnapshot
} from '../../../core/browser/BrowserPageShareCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { CENTERED_DIALOG_SYSTEM_SCROLL_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

const SHARE_QR_SIZE_VP: number = 196;
const SHARE_ACTION_CORNER_RADIUS_VP: number = 12;

@CustomDialog
export struct BrowserPageShareDialog {
  controller?: CustomDialogController;
  @Link snapshot: BrowserPageShareSnapshot;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private accent: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private divider: string = '#E2E7EE';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private primary: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private secondary: string = '#5F6875';
  onAction: (action: BrowserPageShareAction) => void = (_action: BrowserPageShareAction): void => {};

  build() {
    Scroll() {
      Column() {
        Row() {
          Text($r('app.string.bottom_panel_action_share'))
            .layoutWeight(1)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primary)
            .maxLines(2)
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([this.secondary])
          }
          .width(44)
          .height(44)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText($r('app.string.ui_close'))
          .onClick(() => this.onAction('close'))
        }
        .width('100%')

        Text(this.snapshot.title)
          .width('100%')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: 4 })

        Text(this.snapshot.url)
          .width('100%')
          .fontSize(12)
          .fontColor(this.secondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: 2, bottom: 8 })

        Stack({ alignContent: Alignment.Center }) {
          if (this.snapshot.qrSource.length > 0) {
            Image(this.snapshot.qrSource)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .interpolation(ImageInterpolation.None)
              .accessibilityText($r('app.string.web_page_share_scan_qr'))
          } else if (this.snapshot.qrLoading) {
            LoadingProgress().width(28).height(28).color(this.accent)
          } else {
            Text($r('app.string.web_page_share_qr_unavailable'))
              .fontSize(13)
              .fontColor(this.secondary)
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: SHARE_QR_SIZE_VP })
        .height(SHARE_QR_SIZE_VP)

        if (this.snapshot.qrSource.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
            Text($r('app.string.web_page_share_scan_qr'))
              .fontSize(12)
              .fontColor(this.secondary)
              .margin({ right: 8 })
            Button($r('app.string.web_page_share_save_qr'), { type: ButtonType.Normal })
              .height(44)
              .padding({ left: 6, right: 6 })
              .fontSize(12)
              .fontColor(this.accent)
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .borderRadius(SHARE_ACTION_CORNER_RADIUS_VP)
              .clip(true)
              .enabled(!this.snapshot.savingQr)
              .onClick(() => this.onAction('save_qr'))
          }
          .width('100%')
        }

        Divider().color(this.divider).margin({ top: 4 })
        Row() {
          this.buildAction($r('app.string.ui_copy_link'), $r('sys.symbol.link'), 'copy')
          this.buildAction($r('app.string.web_page_share_system'), $r('sys.symbol.arrow_up'), 'system_share')
        }
        .width('100%')
      }
      .width('100%')
      .padding({ top: 10, left: 18, right: 18, bottom: 8 })
    }
    .scrollBar(BarState.Auto)
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SCROLL_SURFACE_MODIFIER)
  }

  @Builder
  private buildAction(label: Resource, glyph: Resource, action: BrowserPageShareAction) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 5 }) {
        SymbolGlyph(glyph).fontSize(15).fontColor([this.primary])
        Text(label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primary)
          .textAlign(TextAlign.Center)
      }
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 44 })
    .padding({ top: 8, bottom: 8, left: 4, right: 4 })
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .borderRadius(SHARE_ACTION_CORNER_RADIUS_VP)
    .clip(true)
    .onClick(() => this.onAction(action))
  }
}
