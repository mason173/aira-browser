import { image } from '@kit.ImageKit';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SiteIconView } from '../common/SiteIconView';
import { AiraIcon } from '../common/AiraIcon';
import { FLOATING_PROMPT_CARD_ICON_SIZE } from '../common/FloatingPromptCard';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';

const BROWSER_TOP_PROMPT_ICON_FALLBACK_FONT_SIZE: number = 16;
const BROWSER_TOP_PROMPT_ICON_FRAME_BORDER_WIDTH: number = 1;
const BROWSER_TOP_PROMPT_ICON_LIGHT_BORDER_COLOR: string = '#12000000';

@Component
export struct BrowserTopPromptIcon {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @Prop iconUri: string = '';
  @Prop iconPixelMap: image.PixelMap | undefined = undefined;
  @Prop airaIconId: AiraRenderableIconId | undefined = undefined;
  @Prop airaIconColor: ResourceColor = '';
  @Prop airaIconBackgroundColor: ResourceColor = '';
  @Prop fallbackLabel: string = '#';

  build() {
    if (this.airaIconId !== undefined) {
      this.buildAiraIcon()
    } else {
      SiteIconView({
        iconUri: this.iconUri,
        iconPixelMap: this.iconPixelMap,
        fallbackLabel: this.fallbackLabel,
        iconSize: FLOATING_PROMPT_CARD_ICON_SIZE,
        cornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
        frameBorderWidth: BROWSER_TOP_PROMPT_ICON_FRAME_BORDER_WIDTH,
        contentPadding: 0,
        imageContentScale: 1,
        fallbackFontSize: BROWSER_TOP_PROMPT_ICON_FALLBACK_FONT_SIZE,
        containerBackgroundColor: this.storedPressedBackgroundColor,
        frameBorderColor: this.resolveFrameBorderColor(),
        textColor: this.storedAccentColor,
        fit: ImageFit.Cover
      })
    }
  }

  @Builder
  private buildAiraIcon() {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: this.airaIconId,
        iconSize: 20,
        iconColor: this.resolveAiraIconColor()
      })
    }
    .width(FLOATING_PROMPT_CARD_ICON_SIZE)
    .height(FLOATING_PROMPT_CARD_ICON_SIZE)
    .backgroundColor(this.resolveAiraIconBackgroundColor())
    .borderRadius(FLOATING_PROMPT_CARD_ICON_SIZE * this.storedSiteIconCornerRadiusRatio)
    .border({
      width: BROWSER_TOP_PROMPT_ICON_FRAME_BORDER_WIDTH,
      color: this.resolveFrameBorderColor()
    })
  }

  private resolveFrameBorderColor(): ResourceColor {
    const outlineColor = this.storedOutlineColor.trim().toUpperCase();
    if (outlineColor.indexOf('FFFFFF') >= 0) {
      return this.storedOutlineColor;
    }
    return BROWSER_TOP_PROMPT_ICON_LIGHT_BORDER_COLOR;
  }

  private resolveAiraIconColor(): ResourceColor {
    if (`${this.airaIconColor}`.trim().length > 0) {
      return this.airaIconColor;
    }
    return this.storedAccentColor;
  }

  private resolveAiraIconBackgroundColor(): ResourceColor {
    if (`${this.airaIconBackgroundColor}`.trim().length > 0) {
      return this.airaIconBackgroundColor;
    }
    return this.storedPressedBackgroundColor;
  }
}
