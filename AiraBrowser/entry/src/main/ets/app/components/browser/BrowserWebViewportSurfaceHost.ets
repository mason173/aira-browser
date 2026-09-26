import {
  BrowserWebViewportCoordinator,
  BrowserWebViewportPresentationState
} from '../../../core/browser/BrowserWebViewportCoordinator';

import { BrowserWebSafeAreaBackground } from './BrowserWebSafeAreaBackground';
import { browserSheetHeaderBlurModifier } from './BrowserModalBottomSheet';

// Same blur strength as the immersive settings, bookmark, and history lists.
const WEB_SCROLL_TOP_BLUR_RADIUS: number = 20;

/**
 * Renders the complete Web viewport geometry projected by its coordinator.
 * Parent-relative sizing keeps host and ArkWeb content in the same layout pass.
 */
@Component
export struct BrowserWebViewportSurfaceHost {
  @Prop presentation: BrowserWebViewportPresentationState = {
    hostHeightPx: 1,
    reservedBottomInsetPx: 0,
    topSafeOverlayHeightPx: 0,
    contentTopPx: 0,
    contentHeightPx: 1,
    fillParentHeight: false,
    scrollHiddenTopBlurHeightPx: 0
  };
  @Prop backdropSnapshotId: string = '';
  @Prop overlayVisible: boolean = false;
  @Prop surfaceColor: ResourceColor = Color.Transparent;
  @Prop safeAreaColor: ResourceColor = Color.White;
  @Prop safeAreaColorTransitionDurationMs: number = 160;
  @Prop surfaceOpacity: number = 1;
  @Prop surfaceScale: number = 1;
  @Prop blurRadius: number = 0;
  @Prop interactive: boolean = true;

  @BuilderParam topChrome: () => void = this.emptyBuilder;
  @BuilderParam content: () => void = this.emptyBuilder;
  @BuilderParam loadingProgress: () => void = this.emptyBuilder;
  @BuilderParam overlayContent: () => void = this.emptyBuilder;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      RelativeContainer() {
        Stack({ alignContent: Alignment.TopStart }) {
          // Keep the clipped chrome mounted at zero height so both ends of a
          // scroll-driven height transition exist in the same render tree.
          this.topChrome()

          Column() {
            Column() {
              this.content()
            }
            .width('100%')
            .height('100%')
            .attributeModifier(browserSheetHeaderBlurModifier(this.presentation.scrollHiddenTopBlurHeightPx > 0 ? WEB_SCROLL_TOP_BLUR_RADIUS : 0, BrowserWebViewportCoordinator.resolveTopBlurFractionStops(this.presentation)))
          }
          .width('100%')
          .height(this.presentation.fillParentHeight ? '100%' : Math.max(1, this.presentation.contentHeightPx))
          .position({
            x: 0,
            y: this.presentation.fillParentHeight ? 0 : this.presentation.contentTopPx
          })
          // Clip after the blur so the kernel cannot paint up into the safe strip.
          // No unconditional geometry animation: history restores still settle in one pass.
          .clip(true)

          this.loadingProgress()
        }
        .id(this.backdropSnapshotId)
        .alignRules({
          top: { anchor: '__container__', align: VerticalAlign.Top },
          bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
          left: { anchor: '__container__', align: HorizontalAlign.Start },
          right: { anchor: '__container__', align: HorizontalAlign.End }
        })
        .width('100%')
        .height('100%')
        .backgroundColor(this.surfaceColor)
        .zIndex(0)

        if (this.overlayVisible) {
          Column() {
            this.overlayContent()
          }
          .width('100%')
          .alignRules({
            top: { anchor: '__container__', align: VerticalAlign.Top },
            left: { anchor: '__container__', align: HorizontalAlign.Start },
            right: { anchor: '__container__', align: HorizontalAlign.End }
          })
          .zIndex(20)
        }
      }
      .width('100%')
      .height(this.presentation.fillParentHeight ? '100%' : Math.max(1, this.presentation.hostHeightPx))
      .clip(this.presentation.reservedBottomInsetPx > 0)
      .backgroundColor(this.surfaceColor)

      if (this.presentation.reservedBottomInsetPx > 0) {
        Column() {
          BrowserWebSafeAreaBackground({
            surfaceColor: this.safeAreaColor,
            colorTransitionDurationMs: this.safeAreaColorTransitionDurationMs
          })
        }
        .width('100%')
        .height(this.presentation.reservedBottomInsetPx)
        .position({ x: 0, y: this.presentation.hostHeightPx })
        .hitTestBehavior(HitTestMode.Block)
      }
    }
    .width('100%')
    .height(this.presentation.fillParentHeight ? '100%' :
      this.presentation.hostHeightPx + this.presentation.reservedBottomInsetPx)
    .opacity(this.surfaceOpacity)
    .scale({
      x: this.surfaceScale,
      y: this.surfaceScale,
      centerX: '50%',
      centerY: '50%'
    })
    .blur(this.blurRadius)
    .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  private emptyBuilder() {
  }
}
