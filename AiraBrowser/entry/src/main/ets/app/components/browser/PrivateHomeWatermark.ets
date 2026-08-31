import { AiraIcon } from '../common/AiraIcon';
import {
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState
} from '../../../common/models/WallpaperModels';
import {
  BrowserForegroundPresentationViewModel,
  BrowserForegroundPresentation
} from '../../../core/browser/BrowserForegroundPresentationViewModel';
import { HOME_WALLPAPER_APPEARANCE_TRANSITION_MS } from '../../../core/wallpaper/HomeWallpaperPresentationTokens';

const PRIVATE_HOME_WATERMARK_ICON_SIZE: number = 168;
const PRIVATE_HOME_WATERMARK_OPACITY: number = 0.14;
const PRIVATE_HOME_WATERMARK_TEXT_OPACITY: number = 0.42;
const PRIVATE_HOME_WATERMARK_TEXT_GAP: number = 12;
const PRIVATE_HOME_WATERMARK_LABEL: string = '当前处于隐私模式';

@Component
export struct PrivateHomeWatermark {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F2F3F5';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop visible: boolean = false;
  @Prop label: string = PRIVATE_HOME_WATERMARK_LABEL;
  @Prop watermarkOpacity: number = PRIVATE_HOME_WATERMARK_OPACITY;
  @Prop textOpacity: number = PRIVATE_HOME_WATERMARK_TEXT_OPACITY;
  @Prop wallpaperState: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @Prop themeBackgroundColor: ResourceColor | undefined = undefined;
  private foregroundPresentationViewModel: BrowserForegroundPresentationViewModel =
    new BrowserForegroundPresentationViewModel();

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Center }) {
        Column({ space: PRIVATE_HOME_WATERMARK_TEXT_GAP }) {
          AiraIcon({
            airaIconId: 'browser.toolbar.privacyMode',
            iconSize: PRIVATE_HOME_WATERMARK_ICON_SIZE,
            iconColor: this.resolveTextColor()
          })
            .opacity(this.resolveWatermarkOpacity())
            .hitTestBehavior(HitTestMode.None)

          Text(this.label)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.resolveTextColor())
            .textShadow(this.resolveTextShadow())
            .animation({ duration: HOME_WALLPAPER_APPEARANCE_TRANSITION_MS, curve: Curve.EaseInOut })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .opacity(this.resolveTextOpacity())
            .hitTestBehavior(HitTestMode.None)
        }
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
  }

  private resolveTextColor(): ResourceColor {
    return this.resolveTextColorState().secondaryTextColor;
  }

  private resolveTextShadow(): Array<ShadowOptions> {
    return this.resolveTextColorState().textShadow;
  }

  private resolveTextColorState(): BrowserForegroundPresentation {
    return this.foregroundPresentationViewModel.resolveHomePresentation({
      foregroundBackdropSource: 'system_home',
      wallpaperState: this.wallpaperState,
      themeBackgroundColor: this.themeBackgroundColor === undefined ? this.storedPageBackgroundColor : this.themeBackgroundColor,
      themedPrimaryTextColor: this.storedSecondaryTextColor,
      themedSecondaryTextColor: this.storedSecondaryTextColor
    });
  }

  private resolveWatermarkOpacity(): number {
    return Math.max(0, Math.min(1, this.watermarkOpacity));
  }

  private resolveTextOpacity(): number {
    return Math.max(0, Math.min(1, this.textOpacity));
  }
}
