/**
 * Phone Shell's primary content composition.
 *
 * This module owns the phone presentation tree only. Session/tab/runtime
 * policy and Hosted Web controller slots stay outside it; callers provide
 * already-shaped state and builder content.
 */
@Component
export struct BrowserPhonePrimarySurface {
  @Prop homeLiveContentMounted: boolean = false;
  @Prop homeBackdropLayerMounted: boolean = false;
  @Prop webLayerMounted: boolean = false;
  @Prop webLayerOpacity: number = 1;

  @BuilderParam homeSurface: () => void = this.emptyBuilder;
  @BuilderParam homeBackdropSurface: () => void = this.emptyBuilder;
  @BuilderParam webSurface: () => void = this.emptyBuilder;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.homeLiveContentMounted) {
        this.homeSurface()
      }

      if (this.homeBackdropLayerMounted) {
        this.homeBackdropSurface()
      }

      if (this.webLayerMounted) {
        Stack() {
          this.webSurface()
        }
        .width('100%')
        .height('100%')
        .opacity(this.resolveWebLayerOpacity())
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private emptyBuilder() {
  }

  private resolveWebLayerOpacity(): number {
    if (!Number.isFinite(this.webLayerOpacity)) {
      return 1;
    }
    return Math.max(0, Math.min(1, this.webLayerOpacity));
  }
}
