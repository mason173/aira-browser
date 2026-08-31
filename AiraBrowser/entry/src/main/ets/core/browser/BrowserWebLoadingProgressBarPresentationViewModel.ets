import { BrowserLoadingProgressState } from './BrowserLoadingProgressCoordinator';

export interface BrowserWebLoadingProgressBarPresentationInput {
  loadingProgressState: BrowserLoadingProgressState;
  showHomePage: boolean;
  showTabsSheet: boolean;
}

export interface BrowserWebLoadingProgressBarPresentationState {
  visible: boolean;
  progress: number;
  lineHeightVp: number;
}

export const DEFAULT_BROWSER_WEB_LOADING_PROGRESS_BAR_PRESENTATION_STATE:
  BrowserWebLoadingProgressBarPresentationState = {
    visible: false,
    progress: 0,
    lineHeightVp: 2
  };

const WEB_LOADING_PROGRESS_BAR_HEIGHT_VP: number = 2;

export class BrowserWebLoadingProgressBarPresentationViewModel {
  buildState(input: BrowserWebLoadingProgressBarPresentationInput): BrowserWebLoadingProgressBarPresentationState {
    const progress = this.resolveProgress(input.loadingProgressState);
    const visible = !input.showHomePage &&
      !input.showTabsSheet &&
      input.loadingProgressState.isLoading &&
      progress > 0 &&
      progress <= 100;
    if (!visible) {
      return DEFAULT_BROWSER_WEB_LOADING_PROGRESS_BAR_PRESENTATION_STATE;
    }
    return {
      visible: true,
      progress: progress,
      lineHeightVp: WEB_LOADING_PROGRESS_BAR_HEIGHT_VP
    };
  }

  private resolveProgress(state: BrowserLoadingProgressState): number {
    const rawProgress = state.displayProgress > 0 ? state.displayProgress : state.realProgress;
    if (!Number.isFinite(rawProgress) || rawProgress <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round(rawProgress)));
  }
}
