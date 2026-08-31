import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';

const SETTINGS_NOTICE_DISMISS_ANIMATION_MS = 240;
const SETTINGS_NOTICE_CARD_PADDING = 16;
const SETTINGS_NOTICE_CARD_EXPANDED_HEIGHT = 92;
const SETTINGS_NOTICE_DISMISS_SCALE = 0.84;
const SETTINGS_NOTICE_DISMISS_TRANSLATE_Y = -8;
const SETTINGS_NOTICE_DEFAULT_SIBLING_SPACE = 16;
const SETTINGS_NOTICE_UNMOUNT_ANIMATION_MS = 80;

@Component
export struct SettingsNoticeCard {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop icon: Resource = $r('sys.symbol.info_circle_fill');
  @Prop title: ResourceStr = '';
  @Prop message: ResourceStr = '';
  @Prop actionText: string = '';
  @Prop dismissible: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop siblingSpace: number = SETTINGS_NOTICE_DEFAULT_SIBLING_SPACE;
  @State private closing: boolean = false;
  onClosed: () => void = () => {};
  onAction: () => void = () => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          AiraIcon({
            airaIconId: 'settings.notice.userShield',
            iconSize: 25,
            iconColor: this.storedPrimaryTextColor
          })
        }
        .width(26)
        .height(26)
        .margin({ top: 1 })
        .flexShrink(0)

        Column({ space: 3 }) {
          Text(this.title)
            .width('100%')
            .fontSize(15)
            .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.actionText.length > 0) {
            Text() {
              Span(this.message)
                .fontColor(this.storedSecondaryTextColor)
              Span(` ${this.actionText}`)
                .fontColor(this.storedAccentColor)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .fontSize(12)
            .lineHeight(17)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              if (!this.closing) {
                this.onAction();
              }
            })
          } else {
            Text(this.message)
              .width('100%')
              .fontSize(12)
              .lineHeight(17)
              .fontColor(this.storedSecondaryTextColor)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.dismissible) {
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(18)
              .fontColor([this.storedSecondaryTextColor])
          }
          .width(30)
          .height(30)
          .type(ButtonType.Circle)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .enabled(!this.closing)
          .flexShrink(0)
          .onClick(() => {
            this.close();
          })
        }
      }
      .width('100%')
      .height(SETTINGS_NOTICE_CARD_EXPANDED_HEIGHT)
      .padding(SETTINGS_NOTICE_CARD_PADDING)
      .opacity(this.closing ? 0 : 1)
      .scale({
        x: this.closing ? SETTINGS_NOTICE_DISMISS_SCALE : 1,
        y: this.closing ? SETTINGS_NOTICE_DISMISS_SCALE : 1
      })
      .translate({ y: this.closing ? SETTINGS_NOTICE_DISMISS_TRANSLATE_Y : 0 })
      .alignItems(VerticalAlign.Top)
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .borderRadius(this.desktopPresentation ? 8 : 22)
      .clip(true)
    }
    .width('100%')
    .height(this.closing ? 0 : SETTINGS_NOTICE_CARD_EXPANDED_HEIGHT)
    .margin({ bottom: this.closing ? -this.siblingSpace : 0 })
    .clip(true)
    .animation({
      duration: SETTINGS_NOTICE_DISMISS_ANIMATION_MS,
      curve: Curve.EaseInOut
    })
  }

  private close(): void {
    if (this.closing) {
      return;
    }
    animateTo({
      duration: SETTINGS_NOTICE_DISMISS_ANIMATION_MS,
      curve: Curve.EaseInOut,
      onFinish: () => {
        animateTo({
          duration: SETTINGS_NOTICE_UNMOUNT_ANIMATION_MS,
          curve: Curve.EaseOut
        }, () => {
          this.onClosed();
        });
      }
    }, () => {
      this.closing = true;
    });
  }
}
