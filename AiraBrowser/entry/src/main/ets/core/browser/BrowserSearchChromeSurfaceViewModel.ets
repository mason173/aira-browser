import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';

export type BrowserSearchChromeContentMode = 'home' | 'web' | 'custom';
export type BrowserSearchChromeFloatingLayoutMode = 'stack' | 'input';

export interface BrowserSearchChromeSurfaceInput {
  contentMode: BrowserSearchChromeContentMode;
  panelDetent: HomeSearchPanelDetent;
  addressEditing: boolean;
  addressFocused: boolean;
  panelDragHeight: number;
  lowPanelDragHeight: number;
  dragRevealThreshold: number;
  expandedDragRevealSuppressed: boolean;
  actionPanelContentReady: boolean;
  quickActionsOnly: boolean;
  quickActionsAvailable: boolean;
  suggestionsVisible: boolean;
  suggestionCount: number;
}

export interface BrowserSearchChromeSurfaceState {
  inputPresentationActive: boolean;
  expandedPresentationActive: boolean;
  actionPanelAvailable: boolean;
  actionPanelMounted: boolean;
  actionPanelContentMounted: boolean;
  suggestionsPanelMounted: boolean;
  floatingStackEnabled: boolean;
  floatingLayoutMode: BrowserSearchChromeFloatingLayoutMode;
  lightweightCollapsedMotion: boolean;
}

export class BrowserSearchChromeSurfaceViewModel {
  buildState(input: BrowserSearchChromeSurfaceInput): BrowserSearchChromeSurfaceState {
    const inputPresentationActive = this.isInputPresentationActive(input);
    const expandedPresentationActive = this.isExpandedPresentationActive(input);
    const actionPanelAvailable = this.isActionPanelAvailable(input, inputPresentationActive);
    const suggestionsPanelMounted = this.shouldMountSuggestionsPanel(input);
    const actionPanelMounted = actionPanelAvailable &&
      (expandedPresentationActive || input.actionPanelContentReady);
    const actionPanelContentMounted = actionPanelMounted && input.actionPanelContentReady;
    const floatingStackEnabled = this.shouldEnableFloatingStack(
      input,
      inputPresentationActive,
      actionPanelAvailable,
      suggestionsPanelMounted
    );
    return {
      inputPresentationActive,
      expandedPresentationActive,
      actionPanelAvailable,
      actionPanelMounted,
      actionPanelContentMounted,
      suggestionsPanelMounted,
      floatingStackEnabled,
      floatingLayoutMode: inputPresentationActive ? 'input' : 'stack',
      lightweightCollapsedMotion: floatingStackEnabled &&
        !inputPresentationActive &&
        !expandedPresentationActive &&
        !suggestionsPanelMounted
    };
  }

  private isInputPresentationActive(input: BrowserSearchChromeSurfaceInput): boolean {
    return input.addressEditing ||
      input.addressFocused;
  }

  private isExpandedPresentationActive(input: BrowserSearchChromeSurfaceInput): boolean {
    if (input.panelDetent === 'middle') {
      return true;
    }
    if (input.expandedDragRevealSuppressed) {
      return false;
    }
    const revealHeight = Math.max(0, input.lowPanelDragHeight) + Math.max(0, input.dragRevealThreshold);
    return input.panelDragHeight > revealHeight;
  }

  private isActionPanelAvailable(
    input: BrowserSearchChromeSurfaceInput,
    inputPresentationActive: boolean
  ): boolean {
    return this.canUseFloatingActionPanel(input) &&
      !inputPresentationActive &&
      input.quickActionsAvailable;
  }

  private shouldMountSuggestionsPanel(input: BrowserSearchChromeSurfaceInput): boolean {
    if (!input.suggestionsVisible || input.suggestionCount <= 0) {
      return false;
    }
    if (input.contentMode !== 'home' && input.contentMode !== 'web') {
      return false;
    }
    return input.panelDetent === 'middle' && input.addressEditing;
  }

  private shouldEnableFloatingStack(
    input: BrowserSearchChromeSurfaceInput,
    inputPresentationActive: boolean,
    actionPanelAvailable: boolean,
    suggestionsPanelMounted: boolean
  ): boolean {
    if (!this.canUseFloatingActionPanel(input)) {
      return false;
    }
    return inputPresentationActive || actionPanelAvailable || suggestionsPanelMounted;
  }

  private canUseFloatingActionPanel(input: BrowserSearchChromeSurfaceInput): boolean {
    return input.contentMode === 'web' || input.contentMode === 'home' || input.quickActionsOnly;
  }
}
