export type BrowserLargeScreenSidePanelState = 'closed' | 'open' | 'pinned';
export type BrowserLargeScreenSidePanelPosition = 'left' | 'right';
export type BrowserLargeScreenSidePanelAction =
  'open' |
  'close' |
  'toggle_pin' |
  'switch_position';

export interface BrowserLargeScreenSidePanelFacts {
  requestedState: BrowserLargeScreenSidePanelState;
  position: BrowserLargeScreenSidePanelPosition;
  contentAvailable: boolean;
  widthVp: number;
  minimumMainStageWidthVp: number;
}

export interface BrowserLargeScreenSidePanelPresentation {
  state: BrowserLargeScreenSidePanelState;
  position: BrowserLargeScreenSidePanelPosition;
  visible: boolean;
  widthVp: number;
}

export interface BrowserLargeScreenSidePanelResolution {
  presentation: BrowserLargeScreenSidePanelPresentation;
  mainStageWidthVp: number;
}

export interface BrowserLargeScreenSidePanelTransition {
  state: BrowserLargeScreenSidePanelState;
  position: BrowserLargeScreenSidePanelPosition;
}

/**
 * Owns Side Panel presentation state and fit policy without owning panel
 * content or its domain actions.
 */
export class BrowserLargeScreenSidePanelViewModel {
  resolve(facts: BrowserLargeScreenSidePanelFacts, availableWidthVp: number): BrowserLargeScreenSidePanelResolution {
    const panelWidthVp = this.normalizeNonNegativeDimension(facts.widthVp);
    const minimumMainStageWidthVp = this.normalizeNonNegativeDimension(facts.minimumMainStageWidthVp);
    const normalizedAvailableWidthVp = this.normalizeNonNegativeDimension(availableWidthVp);
    const contentAvailable = facts.contentAvailable === true;
    const canFit = contentAvailable && panelWidthVp > 0 &&
      normalizedAvailableWidthVp >= panelWidthVp + minimumMainStageWidthVp;
    const requestedState = facts.requestedState === 'pinned' || facts.requestedState === 'open'
      ? facts.requestedState
      : 'closed';
    const state: BrowserLargeScreenSidePanelState = canFit ? requestedState : 'closed';
    const visible = state !== 'closed';
    return {
      presentation: {
        state: state,
        position: facts.position === 'left' ? 'left' : 'right',
        visible: visible,
        widthVp: visible ? panelWidthVp : 0
      },
      mainStageWidthVp: Math.max(0, normalizedAvailableWidthVp - (visible ? panelWidthVp : 0))
    };
  }

  transition(
    state: BrowserLargeScreenSidePanelState,
    position: BrowserLargeScreenSidePanelPosition,
    action: BrowserLargeScreenSidePanelAction
  ): BrowserLargeScreenSidePanelTransition {
    if (action === 'open') {
      return { state: 'open', position: position };
    }
    if (action === 'close') {
      return { state: 'closed', position: position };
    }
    if (action === 'toggle_pin') {
      return {
        state: state === 'pinned' ? 'open' : 'pinned',
        position: position
      };
    }
    return {
      state: state,
      position: position === 'left' ? 'right' : 'left'
    };
  }

  private normalizeNonNegativeDimension(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.max(0, Math.round(value));
  }
}
