import {
  BrowserWebLoadingProgressBarPresentationState,
  DEFAULT_BROWSER_WEB_LOADING_PROGRESS_BAR_PRESENTATION_STATE
} from '../../../core/browser/BrowserWebLoadingProgressBarPresentationViewModel';

@Component
export struct BrowserWebLoadingProgressBar {
  @Prop presentation: BrowserWebLoadingProgressBarPresentationState =
    DEFAULT_BROWSER_WEB_LOADING_PROGRESS_BAR_PRESENTATION_STATE;
  @Prop accentColor: ResourceColor = '#0A59F7';

  build() {
    Progress({
      value: this.resolveProgress(),
      total: 100,
      type: ProgressType.Linear
    })
      .value(this.resolveProgress())
      .width('100%')
      .height(this.resolveLineHeight())
      .color(this.accentColor)
      .style({
        strokeWidth: '2vp',
        strokeRadius: 0
      })
      .hitTestBehavior(HitTestMode.None)
  }

  private resolveProgress(): number {
    if (!Number.isFinite(this.presentation.progress)) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round(this.presentation.progress)));
  }

  private resolveLineHeight(): number {
    if (!Number.isFinite(this.presentation.lineHeightVp) || this.presentation.lineHeightVp <= 0) {
      return 2;
    }
    return Math.max(1, Math.round(this.presentation.lineHeightVp));
  }
}
