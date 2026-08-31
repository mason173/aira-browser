export interface HomeSearchOverlayVisualState {
  searchTop: number;
  ambientOffsetY: number;
  ambientOpacity: number;
  suggestionsOffsetY: number;
  suggestionsOpacity: number;
}

export interface HomeSearchOverlayAnchor {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface HomeSearchDismissInput {
  showHomePage: boolean;
  homeSearchFocused: boolean;
  homeSearchOverlayVisible: boolean;
  expandedScrimVisible: boolean;
}

export interface HomeSearchDismissPlan {
  shouldDismissHomeSearch: boolean;
  shouldCollapseBottomPanel: boolean;
}

export interface HomeSearchReleaseInput {
  homeSearchFocused: boolean;
  homeSearchOverlayVisible: boolean;
}

export type HomeSearchReleaseMode = 'none' | 'closing' | 'dismissed';

export interface HomeSearchReleasePlan {
  mode: HomeSearchReleaseMode;
}

export class HomeSearchOverlayViewModel {
  buildVisualState(focused: boolean, anchor?: HomeSearchOverlayAnchor): HomeSearchOverlayVisualState {
    if (focused) {
      return {
        searchTop: 54,
        ambientOffsetY: 42,
        ambientOpacity: 0,
        suggestionsOffsetY: 0,
        suggestionsOpacity: 1
      };
    }
    return {
      searchTop: anchor?.top ?? 210,
      ambientOffsetY: 0,
      ambientOpacity: 1,
      suggestionsOffsetY: 16,
      suggestionsOpacity: 0
    };
  }

  shouldHandleBackPress(showHomePage: boolean, focused: boolean): boolean {
    return showHomePage && focused;
  }

  buildDismissPlan(input: HomeSearchDismissInput): HomeSearchDismissPlan {
    const hasHomeSearchOverlay = input.showHomePage &&
      (input.homeSearchFocused || input.homeSearchOverlayVisible);
    return {
      shouldDismissHomeSearch: hasHomeSearchOverlay && !input.expandedScrimVisible,
      shouldCollapseBottomPanel: input.expandedScrimVisible
    };
  }

  buildReleasePlan(input: HomeSearchReleaseInput): HomeSearchReleasePlan {
    if (input.homeSearchOverlayVisible) {
      return { mode: 'closing' };
    }
    if (input.homeSearchFocused) {
      return { mode: 'dismissed' };
    }
    return { mode: 'none' };
  }

  shouldMountDismissLayer(input: HomeSearchDismissInput): boolean {
    return input.showHomePage && input.homeSearchFocused && input.homeSearchOverlayVisible;
  }

  searchTop(focused: boolean, anchor?: HomeSearchOverlayAnchor): number {
    return this.buildVisualState(focused, anchor).searchTop;
  }

  ambientOffsetY(focused: boolean): number {
    return this.buildVisualState(focused).ambientOffsetY;
  }

  ambientOpacity(focused: boolean): number {
    return this.buildVisualState(focused).ambientOpacity;
  }

  suggestionsOffsetY(focused: boolean): number {
    return this.buildVisualState(focused).suggestionsOffsetY;
  }

  suggestionsOpacity(focused: boolean): number {
    return this.buildVisualState(focused).suggestionsOpacity;
  }

}
