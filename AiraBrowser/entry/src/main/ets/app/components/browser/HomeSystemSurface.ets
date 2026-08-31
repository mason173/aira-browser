import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState
} from '../../../common/models/WallpaperModels';
import {
  BrowserBackdropEffectState,
  DEFAULT_BROWSER_BACKDROP_EFFECT_STATE
} from '../../../core/browser/BrowserBackdropEffectViewModel';
import {
  BrowserHomeSurfaceContentPresentationState
} from '../../../core/browser/BrowserHomePresentationViewModel';
import { HomeBackdropLayer } from './HomeBackdropLayer';

@Component
export struct HomeSystemSurface {
  @Prop wallpaperState: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @Prop darkModeActive: boolean = false;
  @Prop themeBackgroundColor: ResourceColor | undefined = undefined;
  @Prop privateModeVisible: boolean = false;
  @Prop backdropEffectState: BrowserBackdropEffectState = DEFAULT_BROWSER_BACKDROP_EFFECT_STATE;
  @Prop searchFocused: boolean = false;
  @Prop contentPresentation: BrowserHomeSurfaceContentPresentationState;
  @BuilderParam content: () => void = this.emptyBuilder;
  onDismissSearchFocus: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Top }) {
      HomeBackdropLayer({
        wallpaperState: this.wallpaperState,
        darkModeActive: this.darkModeActive,
        themeBackgroundColor: this.themeBackgroundColor,
        privateModeVisible: this.privateModeVisible,
        contentScale: this.backdropEffectState.contentScale,
        blurRadius: this.backdropEffectState.blurRadius,
        blurEdgeScale: this.backdropEffectState.blurEdgeScale,
        tintColor: this.backdropEffectState.tintColor,
        tintOpacity: this.backdropEffectState.tintOpacity
      })
      this.buildContentLayer()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildContentLayer() {
    Stack({ alignContent: Alignment.Top }) {
      Stack({ alignContent: Alignment.Top }) {
        this.content()
      }
      .width('100%')
      .height('100%')
      .opacity(this.contentPresentation.contentOpacity)
      .translate({ y: this.contentPresentation.contentOffsetY })
      if (this.searchFocused) {
        this.buildSearchFocusDismissLayer()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildSearchFocusDismissLayer() {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .hitTestBehavior(HitTestMode.Default)
      .onClick(() => {
        this.onDismissSearchFocus();
      })
  }

  @Builder
  private emptyBuilder() {
  }
}
