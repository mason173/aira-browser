import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState
} from '../../../common/models/WallpaperModels';
import { resolveHomeWallpaperRenderedMaskOpacity } from '../../../services/wallpaper/HomeWallpaperAnalysisPolicy';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../../core/theme/BrowserThemeStorageKeys';

@Component
export struct HomeWallpaperLayer {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F2F3F5';
  @Prop state: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @Prop darkModeActive: boolean = false;
  @Prop themeBackgroundColor: ResourceColor | undefined = undefined;
  build() {
    Stack() {
      if (this.state.kind === 'image' && this.state.imagePath.length > 0) {
        Image(this.state.imagePath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .backgroundColor(this.resolveThemeBackgroundColor())
      } else {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.resolveThemeBackgroundColor())
      }

      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(this.resolveOverlayOpacity(this.state))
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  private resolveOverlayOpacity(state: HomeWallpaperPresentationState): number {
    if (state.kind === 'default') {
      return 0;
    }
    return resolveHomeWallpaperRenderedMaskOpacity(state.maskOpacity);
  }

  private resolveThemeBackgroundColor(): ResourceColor {
    return this.themeBackgroundColor === undefined ? this.storedPageBackgroundColor : this.themeBackgroundColor;
  }

}
