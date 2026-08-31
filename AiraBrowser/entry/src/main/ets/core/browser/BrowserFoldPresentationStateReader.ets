import { display } from '@kit.ArkUI';
import { BrowserFoldPresentationState } from '../../common/models/BrowserDevicePresentationModels';

export interface BrowserFoldPresentationFacts {
  capabilityConfirmed: boolean;
  state: BrowserFoldPresentationState;
}

/**
 * Single platform adapter for fold capability and the last stable fold state.
 * The capability and status APIs are independent on HarmonyOS devices and
 * emulators, so callers must not make a second capability decision.
 */
export class BrowserFoldPresentationStateReader {
  read(): BrowserFoldPresentationFacts {
    let capabilityConfirmed = false;
    let state: BrowserFoldPresentationState = 'unknown';

    try {
      capabilityConfirmed = display.isFoldable() === true;
    } catch (_error) {
    }

    try {
      const foldDisplayMode = display.getFoldDisplayMode();
      if (foldDisplayMode !== display.FoldDisplayMode.FOLD_DISPLAY_MODE_UNKNOWN) {
        capabilityConfirmed = true;
      }
    } catch (_error) {
    }

    try {
      const stableState = this.resolveStableState(display.getFoldStatus());
      if (stableState !== undefined) {
        capabilityConfirmed = true;
        state = stableState;
      }
    } catch (_error) {
    }

    return {
      capabilityConfirmed: capabilityConfirmed,
      state: state
    };
  }

  resolveStableState(status: display.FoldStatus): BrowserFoldPresentationState | undefined {
    if (status === display.FoldStatus.FOLD_STATUS_EXPANDED ||
      status === display.FoldStatus.FOLD_STATUS_EXPANDED_WITH_SECOND_EXPANDED) {
      return 'expanded';
    }
    if (status === display.FoldStatus.FOLD_STATUS_FOLDED) {
      return 'folded';
    }
    return undefined;
  }
}
