import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState
} from '../../../common/models/WallpaperModels';
import { HomeWallpaperLayer } from './HomeWallpaperLayer';
import { PrivateHomeWatermark } from './PrivateHomeWatermark';

@Component
export struct HomeBackdropLayer {
  @Prop wallpaperState: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @Prop darkModeActive: boolean = false;
  @Prop themeBackgroundColor: ResourceColor | undefined = undefined;
  @Prop privateModeVisible: boolean = false;
  @Prop frameWidth: number = 0;
  @Prop frameHeight: number = 0;
  @Prop contentScale: number = 1;
  @Prop blurRadius: number = 0;
  @Prop blurEdgeScale: number = 1;
  @Prop tintColor: ResourceColor = '#000000';
  @Prop tintOpacity: number = 0;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.hasExplicitFrame()) {
        this.buildFixedBackdropLayer()
        if (this.shouldRenderTintOverlay()) {
          this.buildFixedTintOverlay()
        }
      } else {
        this.buildFillBackdropLayer()
        if (this.shouldRenderTintOverlay()) {
          this.buildFillTintOverlay()
        }
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildBackdropContent() {
    HomeWallpaperLayer({
      state: this.wallpaperState,
      darkModeActive: this.darkModeActive,
      themeBackgroundColor: this.themeBackgroundColor
    })
    PrivateHomeWatermark({
      visible: this.privateModeVisible,
      wallpaperState: this.wallpaperState,
      themeBackgroundColor: this.themeBackgroundColor
    })
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildFixedBackdropLayer() {
    Stack({ alignContent: Alignment.Top }) {
      this.buildBackdropContent()
    }
    .width(this.resolveFrameWidth())
    .height(this.resolveFrameHeight())
    .scale({
      x: this.resolveLayerScale(),
      y: this.resolveLayerScale(),
      centerX: '50%',
      centerY: '50%'
    })
    .blur(this.resolveBlurRadius())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildFillBackdropLayer() {
    Stack({ alignContent: Alignment.Top }) {
      this.buildBackdropContent()
    }
    .width('100%')
    .height('100%')
    .scale({
      x: this.resolveLayerScale(),
      y: this.resolveLayerScale(),
      centerX: '50%',
      centerY: '50%'
    })
    .blur(this.resolveBlurRadius())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildFixedTintOverlay() {
    Stack()
      .width(this.resolveFrameWidth())
      .height(this.resolveFrameHeight())
      .backgroundColor(this.tintColor)
      .opacity(this.resolveTintOpacity())
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildFillTintOverlay() {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundColor(this.tintColor)
      .opacity(this.resolveTintOpacity())
      .hitTestBehavior(HitTestMode.None)
  }

  private hasExplicitFrame(): boolean {
    return Number.isFinite(this.frameWidth) && this.frameWidth > 0 &&
      Number.isFinite(this.frameHeight) && this.frameHeight > 0;
  }

  private resolveFrameWidth(): number {
    return Math.max(1, Math.round(this.frameWidth));
  }

  private resolveFrameHeight(): number {
    return Math.max(1, Math.round(this.frameHeight));
  }

  private resolveContentScale(): number {
    if (!Number.isFinite(this.contentScale) || this.contentScale <= 0) {
      return 1;
    }
    return this.contentScale;
  }

  private resolveBlurEdgeScale(): number {
    if (this.resolveBlurRadius() <= 0 || !Number.isFinite(this.blurEdgeScale) || this.blurEdgeScale <= 0) {
      return 1;
    }
    return this.blurEdgeScale;
  }

  private resolveLayerScale(): number {
    return this.resolveContentScale() * this.resolveBlurEdgeScale();
  }

  private resolveBlurRadius(): number {
    if (!Number.isFinite(this.blurRadius) || this.blurRadius <= 0) {
      return 0;
    }
    return this.blurRadius;
  }

  private shouldRenderTintOverlay(): boolean {
    return this.resolveTintOpacity() > 0;
  }

  private resolveTintOpacity(): number {
    if (!Number.isFinite(this.tintOpacity) || this.tintOpacity <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.tintOpacity));
  }
}
