import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';
import {
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT
} from './BrowserBottomAddressPanelMetrics';
import {
  BrowserSearchBackdropPresentationViewModel,
  BrowserSearchBackdropSettleDurationInput
} from './BrowserSearchBackdropPresentationViewModel';

export interface BrowserBottomBackdropProgressInput {
  panelHeight: number;
  expandedHeight: number;
  previousPanelHeight: number;
}

export type BrowserBottomBackdropSettleInput = BrowserSearchBackdropSettleDurationInput;

export class BrowserBottomBackdropViewModel {
  private searchBackdropViewModel: BrowserSearchBackdropPresentationViewModel =
    new BrowserSearchBackdropPresentationViewModel();

  resolveProgress(input: BrowserBottomBackdropProgressInput): number {
    return this.searchBackdropViewModel.resolveProgress({
      panelHeight: input.panelHeight,
      lowHeight: BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT,
      expandedHeight: Math.max(input.panelHeight, input.expandedHeight),
      direction: this.searchBackdropViewModel.resolveProgressDirection(input.previousPanelHeight, input.panelHeight)
    });
  }

  resolveDetentProgress(detent: HomeSearchPanelDetent): number {
    return this.searchBackdropViewModel.resolveDetentProgress(detent);
  }

  resolveSettleDurationMs(input: BrowserBottomBackdropSettleInput): number {
    return this.searchBackdropViewModel.resolveSettleDurationMs({
      currentProgress: input.currentProgress,
      targetProgress: input.targetProgress,
      maxDurationMs: input.maxDurationMs,
      minDurationMs: input.minDurationMs
    });
  }

  resolveContentScale(progress: number): number {
    return this.searchBackdropViewModel.buildState(progress).scale;
  }

  resolveEffectiveProgress(progress: number): number {
    if (!Number.isFinite(progress)) {
      return 0;
    }
    return Math.max(0, Math.min(1, progress));
  }
}
