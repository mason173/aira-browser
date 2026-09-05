import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_BOTTOM_NEUTRAL_ICON_DISABLED_OPACITY,
  BROWSER_BOTTOM_NEUTRAL_ICON_ENABLED_OPACITY,
  resolveBrowserBottomNeutralContainerColor,
  resolveBrowserBottomNeutralPrimaryColor,
  resolveBrowserBottomNeutralSecondaryColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import {
  BROWSER_BOTTOM_QUICK_ACTION_BUTTON_SIZE,
  BROWSER_BOTTOM_QUICK_ACTION_LABEL_LINE_HEIGHT,
  BROWSER_BOTTOM_QUICK_ACTION_VERTICAL_GAP
} from '../../../core/browser/BrowserBottomAddressPanelMetrics';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
const HOME_SEARCH_QUICK_ACTION_CARD_IMAGE_ICON_SIZE: number = 26;
const HOME_SEARCH_QUICK_ACTION_CARD_LABEL_SIZE: number = 11;
const HOME_SEARCH_QUICK_ACTION_CARD_BORDER_WIDTH: number = 1;
const HOME_SEARCH_QUICK_ACTION_CARD_PRESSED_SCALE: number = 0.94;
const HOME_SEARCH_QUICK_ACTION_CARD_PRESS_DURATION_MS: number = 90;
const HOME_SEARCH_QUICK_ACTION_CARD_RELEASE_DURATION_MS: number = 260;
const HOME_SEARCH_QUICK_ACTION_LABEL_COLOR_TRANSITION_MS: number = 160;

@Component
export struct HomeSearchQuickActionCard {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop imageIcon: Resource | undefined = undefined;
  @Prop airaIconId: AiraRenderableIconId | undefined = undefined;
  @Prop label: string = '';
  @Prop cardEnabled: boolean = true;
  @Prop cardImageFillColor: ResourceColor | undefined = undefined;
  @Prop cardLabelColor: ResourceColor | undefined = undefined;
  @Prop cardBackgroundColor: ResourceColor | undefined = undefined;
  @Prop cardDisabledOpacity: number = 0.42;
  @Prop cardBorderWidth: number = HOME_SEARCH_QUICK_ACTION_CARD_BORDER_WIDTH;
  @Prop cardCornerRadius: number = 0;
  @Prop imageRenderVersion: number = 0;
  @Prop buttonSize: number = BROWSER_BOTTOM_QUICK_ACTION_BUTTON_SIZE;
  @State private pressed: boolean = false;
  action: () => void = () => {};

  build() {
    Button() {
      Column({ space: BROWSER_BOTTOM_QUICK_ACTION_VERTICAL_GAP }) {
        this.buildQuickActionButtonSurface()

        Text(this.label)
          .width('100%')
          .fontSize(HOME_SEARCH_QUICK_ACTION_CARD_LABEL_SIZE)
          .lineHeight(BROWSER_BOTTOM_QUICK_ACTION_LABEL_LINE_HEIGHT)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.resolveLabelColor())
          .animation({
            duration: HOME_SEARCH_QUICK_ACTION_LABEL_COLOR_TRANSITION_MS,
            curve: Curve.EaseOut
          })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(false)
    .opacity(1)
    .scale({
      x: this.resolvePressedScale(),
      y: this.resolvePressedScale()
    })
    .animation({
      duration: this.pressed ? HOME_SEARCH_QUICK_ACTION_CARD_PRESS_DURATION_MS :
      HOME_SEARCH_QUICK_ACTION_CARD_RELEASE_DURATION_MS,
      curve: this.pressed ? Curve.EaseOut : 'interpolatingSpring(0, 1, 360, 24)'
    })
    .onTouch((event: TouchEvent) => {
      this.updatePressedState(event.type);
    })
    .onClick(() => {
      this.action();
    })
  }

  @Builder
  private buildQuickActionButtonSurface() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildQuickActionButtonIcon()
    }
    .width(this.resolveButtonSize())
    .height(this.resolveButtonSize())
    .backgroundColor(this.resolveBackgroundColor())
    .borderWidth(this.cardBorderWidth)
    .borderColor(this.storedDividerColor)
    .borderRadius(this.resolveButtonRadius())
  }

  @Builder
  private buildQuickActionButtonIcon() {
    if (this.airaIconId !== undefined) {
      AiraIcon({
        airaIconId: this.airaIconId,
        iconSize: HOME_SEARCH_QUICK_ACTION_CARD_IMAGE_ICON_SIZE,
        iconColor: this.resolveOperationalIconColor()
      })
        .opacity(this.resolveIconOpacity())
    } else if (this.imageIcon !== undefined) {
      ForEach([this.resolveImageRenderKey()], (_renderKey: string) => {
        this.buildImageIcon()
      }, (renderKey: string) => renderKey)
    }
  }

  @Builder
  private buildImageIcon() {
    if (this.cardImageFillColor !== undefined) {
      Image(this.imageIcon as Resource)
        .width(HOME_SEARCH_QUICK_ACTION_CARD_IMAGE_ICON_SIZE)
        .height(HOME_SEARCH_QUICK_ACTION_CARD_IMAGE_ICON_SIZE)
        .objectFit(ImageFit.Contain)
        .draggable(false)
        .fillColor(this.cardImageFillColor)
        .opacity(this.resolveIconOpacity())
    } else {
      Image(this.imageIcon as Resource)
        .width(HOME_SEARCH_QUICK_ACTION_CARD_IMAGE_ICON_SIZE)
        .height(HOME_SEARCH_QUICK_ACTION_CARD_IMAGE_ICON_SIZE)
        .objectFit(ImageFit.Contain)
        .draggable(false)
        .opacity(this.resolveIconOpacity())
    }
  }

  private updatePressedState(type: TouchType): void {
    if (!this.cardEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolvePressedScale(): number {
    return this.pressed ? HOME_SEARCH_QUICK_ACTION_CARD_PRESSED_SCALE : 1;
  }

  private resolveIconOpacity(): number {
    return this.cardEnabled ? BROWSER_BOTTOM_NEUTRAL_ICON_ENABLED_OPACITY :
    BROWSER_BOTTOM_NEUTRAL_ICON_DISABLED_OPACITY;
  }

  private resolveLabelColor(): ResourceColor {
    return this.cardLabelColor === undefined ? resolveBrowserBottomNeutralSecondaryColor(this.storedResolvedThemeMode) :
      this.cardLabelColor;
  }

  private resolveOperationalIconColor(): ResourceColor {
    return this.cardImageFillColor === undefined ?
      resolveBrowserBottomNeutralPrimaryColor(this.storedResolvedThemeMode) : this.cardImageFillColor;
  }

  private resolveBackgroundColor(): ResourceColor {
    if (this.cardBackgroundColor !== undefined) {
      return this.cardBackgroundColor;
    }
    return resolveBrowserBottomNeutralContainerColor(this.storedResolvedThemeMode);
  }

  private resolveButtonSize(): number {
    return Math.max(1, Math.min(BROWSER_BOTTOM_QUICK_ACTION_BUTTON_SIZE, this.buttonSize));
  }

  private resolveButtonRadius(): number {
    const maximumRadius = this.resolveButtonSize() / 2;
    return this.cardCornerRadius > 0 ? Math.min(this.cardCornerRadius, maximumRadius) : maximumRadius;
  }

  private resolveImageRenderKey(): string {
    return `${this.imageRenderVersion}:${this.label}:${this.cardImageFillColor ?? 'default'}`;
  }
}
