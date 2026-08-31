import { BrowserPullRefreshPresentation } from '../../../core/browser/BrowserPullRefreshModels';

const PULL_REFRESH_MIN_HEIGHT_VP: number = 48;
const PULL_REFRESH_MAX_EXTRA_HEIGHT_VP: number = 132;
const PULL_REFRESH_INDICATOR_SIZE_VP: number = 24;

@Component
export struct BrowserPullRefreshLoadingArea {
  @Prop presentation: BrowserPullRefreshPresentation;
  @Prop accentColor: ResourceColor = '#0A59F7';
  @Prop surfaceColor: ResourceColor = '#FFFFFF';

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        Blank()
          .height(this.resolveTopPadding())

        Stack() {
          LoadingProgress()
            .width(PULL_REFRESH_INDICATOR_SIZE_VP)
            .height(PULL_REFRESH_INDICATOR_SIZE_VP)
            .color(this.accentColor)
            .freeze(!this.presentation.enableLoading)
        }
        .width(PULL_REFRESH_INDICATOR_SIZE_VP)
        .height(PULL_REFRESH_INDICATOR_SIZE_VP)
        .opacity(this.resolveLoadingOpacity())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height(this.resolveHeight())
    .backgroundColor(this.surfaceColor)
    .visibility(
      this.presentation.visible && this.presentation.offsetY > 0
        ? Visibility.Visible
        : Visibility.Hidden
    )
    .hitTestBehavior(HitTestMode.None)
  }

  private resolveHeight(): number {
    if (!this.presentation.visible || this.presentation.offsetY <= 0) {
      return 0;
    }
    return Math.max(PULL_REFRESH_MIN_HEIGHT_VP, this.resolveTopPadding() + this.resolveOffset());
  }

  private resolveTopPadding(): number {
    if (!Number.isFinite(this.presentation.topPlaceHolderHeight) ||
      this.presentation.topPlaceHolderHeight <= 0) {
      return 0;
    }
    return Math.round(this.presentation.topPlaceHolderHeight);
  }

  private resolveOffset(): number {
    if (!Number.isFinite(this.presentation.offsetY)) {
      return 0;
    }
    return Math.max(0, Math.min(PULL_REFRESH_MAX_EXTRA_HEIGHT_VP, this.presentation.offsetY));
  }

  private resolveLoadingOpacity(): number {
    return Math.max(0.35, Math.min(1, this.resolveOffset() / PULL_REFRESH_MIN_HEIGHT_VP));
  }
}
