import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';

@Component
export struct SyncContentSwitchCard {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string =
    DEFAULT_THEME_PALETTE.light.settingsIconForeground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop title: string = '';
  @Prop status: string = '';
  @Prop checked: boolean = false;
  @Prop isEnabled: boolean = true;
  @Prop icon: Resource = $r('sys.symbol.gearshape_fill');
  @Prop imageIcon: Resource | undefined = undefined;
  @Prop airaIconId: AiraRenderableIconId | undefined = undefined;
  @Prop iconBackgroundColor: ResourceColor = '';
  @Prop infoText: string = '';
  @Prop desktopPresentation: boolean = false;
  @State private infoPopupVisible: boolean = false;
  onChange?: (checked: boolean) => void;

  build() {
    Column() {
      Row() {
        this.buildIcon()

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.checked })
          .enabled(this.isEnabled)
          .selectedColor(this.storedAccentColor)
          .onChange((value: boolean) => {
            if (this.isEnabled && value !== this.checked) {
              this.onChange?.(value);
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Blank()

      Row({ space: 4 }) {
        Text(this.title)
          .layoutWeight(1)
          .fontSize(this.desktopPresentation ? 15 : 16)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.isEnabled ? this.storedPrimaryTextColor : this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.infoText.trim().length > 0) {
          this.buildInfoButton()
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.status)
        .width('100%')
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 3 })
    }
    .width('100%')
    .height(this.desktopPresentation ? 100 : 118)
    .padding(this.desktopPresentation ? 12 : 14)
    .borderRadius(this.desktopPresentation ? 8 : 18)
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .opacity(this.isEnabled ? 1 : 0.58)
  }

  @Builder
  private buildIcon() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(36)
        .height(36)
        .fill(this.iconBackgroundColor)

      if (this.airaIconId !== undefined) {
        AiraIcon({
          airaIconId: this.airaIconId,
          iconSize: 20,
          iconColor: this.storedSettingsIconForegroundColor
        })
      } else if (this.imageIcon !== undefined) {
        Image(this.imageIcon as Resource)
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      } else {
        SymbolGlyph(this.icon)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.storedSettingsIconForegroundColor])
      }
    }
    .width(36)
    .height(36)
  }

  @Builder
  private buildInfoButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(17)
        .fontColor([this.storedSecondaryTextColor])
    }
    .width(28)
    .height(28)
    .type(ButtonType.Circle)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(true)
    .accessibilityText(`查看${this.title}同步说明`)
    .onClick(() => {
      this.infoPopupVisible = !this.infoPopupVisible;
    })
    .bindPopup(this.infoPopupVisible, {
      message: this.infoText,
      placement: Placement.Top,
      enableArrow: true,
      autoCancel: true,
      mask: false,
      targetSpace: 8,
      popupColor: this.storedSurfaceBackgroundColor,
      messageOptions: {
        textColor: this.storedSecondaryTextColor,
        font: {
          size: 13,
          weight: FontWeight.Regular
        }
      },
      radius: 14,
      width: 246,
      onStateChange: (event: PopupStateChangeParam) => {
        if (!event.isVisible) {
          this.infoPopupVisible = false;
        }
      }
    })
  }
}
