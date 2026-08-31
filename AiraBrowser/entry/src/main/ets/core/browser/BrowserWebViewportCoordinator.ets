export interface BrowserWebViewportInsets {
  topInsetPx: number;
  bottomInsetPx: number;
}

export interface BrowserWebViewportInput {
  webPageVisible: boolean;
  topSafeInsetVp: number;
  bottomSafeInsetVp: number;
}

export interface BrowserWebViewportTopInsetAlignmentInput {
  safeInsetsChanged: boolean;
  forceAlign: boolean;
  webStatusBarVisible: boolean;
  webPageVisible: boolean;
  tabsSheetVisible: boolean;
  currentTopInsetPx: number;
  targetTopInsetPx: number;
}

export interface BrowserWebViewportTopInsetAlignmentResult {
  shouldAlign: boolean;
  topInsetPx: number;
}

export interface BrowserWebViewportLayerLayoutInput {
  hostHeightPx: number;
  visualTopInsetPx: number;
  fullViewport: boolean;
  largeScreenShellActive: boolean;
  nativeVideoTakeoverActive: boolean;
}

export interface BrowserWebViewportVisibleTopChromeInput {
  baseTopInsetPx: number;
  occupiedChromeHeightPx: number;
}

export interface BrowserWebViewportPresentationState {
  hostHeightPx: number;
  topSafeOverlayHeightPx: number;
  contentTopPx: number;
  contentHeightPx: number;
  fillParentHeight: boolean;
}

export interface BrowserWebViewportPresentationUpdateInput {
  current: BrowserWebViewportPresentationState;
  next: BrowserWebViewportPresentationState;
}

export class BrowserWebViewportCoordinator {
  static resolveVisibleTopChromeInset(input: BrowserWebViewportVisibleTopChromeInput): number {
    return Math.max(0, Math.ceil(input.baseTopInsetPx)) +
      Math.max(0, Math.ceil(input.occupiedChromeHeightPx));
  }

  static resolveInsets(input: BrowserWebViewportInput): BrowserWebViewportInsets {
    if (!input.webPageVisible) {
      return {
        topInsetPx: 0,
        bottomInsetPx: 0
      };
    }
    return {
      topInsetPx: Math.max(0, Math.ceil(input.topSafeInsetVp)),
      bottomInsetPx: Math.max(0, Math.ceil(input.bottomSafeInsetVp))
    };
  }

  static resolveTopInsetAlignment(
    input: BrowserWebViewportTopInsetAlignmentInput
  ): BrowserWebViewportTopInsetAlignmentResult {
    const targetTopInsetPx = Math.max(0, Math.ceil(input.targetTopInsetPx));
    if ((!input.safeInsetsChanged && !input.forceAlign) || !input.webStatusBarVisible || !input.webPageVisible ||
      input.tabsSheetVisible || Math.max(0, Math.ceil(input.currentTopInsetPx)) === targetTopInsetPx) {
      return {
        shouldAlign: false,
        topInsetPx: targetTopInsetPx
      };
    }
    return {
      shouldAlign: true,
      topInsetPx: targetTopInsetPx
    };
  }

  static resolveLayerLayout(input: BrowserWebViewportLayerLayoutInput): BrowserWebViewportPresentationState {
    const hostHeightPx = Math.max(1, Math.ceil(input.hostHeightPx));
    const topInsetPx = input.fullViewport ? 0 : Math.max(0, Math.ceil(input.visualTopInsetPx));
    const contentHeightPx = input.fullViewport ? hostHeightPx : Math.max(1, hostHeightPx - topInsetPx);
    const fillParentHeight = input.largeScreenShellActive || input.nativeVideoTakeoverActive;
    return {
      hostHeightPx,
      topSafeOverlayHeightPx: topInsetPx,
      contentTopPx: topInsetPx,
      contentHeightPx,
      fillParentHeight
    };
  }

  static resolvePresentation(input: BrowserWebViewportLayerLayoutInput): BrowserWebViewportPresentationState {
    return BrowserWebViewportCoordinator.resolveLayerLayout(input);
  }

  static resolvePresentationUpdate(
    input: BrowserWebViewportPresentationUpdateInput
  ): BrowserWebViewportPresentationState {
    if (input.current.hostHeightPx === input.next.hostHeightPx &&
      input.current.topSafeOverlayHeightPx === input.next.topSafeOverlayHeightPx &&
      input.current.contentTopPx === input.next.contentTopPx &&
      input.current.contentHeightPx === input.next.contentHeightPx &&
      input.current.fillParentHeight === input.next.fillParentHeight) {
      return input.current;
    }
    return input.next;
  }
}
