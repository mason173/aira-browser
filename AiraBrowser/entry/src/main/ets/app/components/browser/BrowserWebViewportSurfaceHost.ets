import {
  BrowserWebViewportPresentationState
} from '../../../core/browser/BrowserWebViewportCoordinator';

/**
 * Renders the complete Web viewport geometry projected by its coordinator.
 * Parent-relative sizing keeps host and ArkWeb content in the same layout pass.
 */
@Component
export struct BrowserWebViewportSurfaceHost {
  @Prop presentation: BrowserWebViewportPresentationState = {
    hostHeightPx: 1,
    topSafeOverlayHeightPx: 0,
    contentTopPx: 0,
    contentHeightPx: 1,
    fillParentHeight: false
  };
  @Prop backdropSnapshotId: string = '';
  @Prop overlayVisible: boolean = false;
  @Prop surfaceColor: ResourceColor = Color.Transparent;
  @Prop surfaceOpacity: number = 1;
  @Prop surfaceScale: number = 1;
  @Prop blurRadius: number = 0;
  @Prop interactive: boolean = true;

  @BuilderParam topChrome: () => void = this.emptyBuilder;
  @BuilderParam content: () => void = this.emptyBuilder;
  @BuilderParam loadingProgress: () => void = this.emptyBuilder;
  @BuilderParam overlayContent: () => void = this.emptyBuilder;

  build() {
    RelativeContainer() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.presentation.topSafeOverlayHeightPx > 0) {
          this.topChrome()
        }

        Column() {
          this.content()
        }
        .width('100%')
        .height(this.presentation.fillParentHeight ? '100%' : Math.max(1, this.presentation.contentHeightPx))
        .position({
          x: 0,
          y: this.presentation.fillParentHeight ? 0 : this.presentation.contentTopPx
        })
        // Web content geometry must settle in the same layout pass as history
        // navigation. Animating height/top changes moves the scroll viewport
        // while ArkWeb is restoring the target document.
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
    .backgroundColor(this.surfaceColor)
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
