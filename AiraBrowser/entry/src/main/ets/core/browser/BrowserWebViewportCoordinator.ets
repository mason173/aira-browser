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
  visualBottomInsetPx?: number;
  fullViewport: boolean;
  largeScreenShellActive: boolean;
  nativeVideoTakeoverActive: boolean;
  scrollHiddenTopBlurHeightPx?: number;
}

export interface BrowserWebViewportVisibleTopChromeInput {
  baseTopInsetPx: number;
  occupiedChromeHeightPx: number;
}

export interface BrowserWebViewportPresentationState {
  hostHeightPx: number;
  reservedBottomInsetPx: number;
  topSafeOverlayHeightPx: number;
  contentTopPx: number;
  contentHeightPx: number;
  fillParentHeight: boolean;
  scrollHiddenTopBlurHeightPx: number;
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
    const availableHeightPx = Math.max(1, Math.ceil(input.hostHeightPx));
    const topInsetPx = input.fullViewport ? 0 : Math.max(0, Math.ceil(input.visualTopInsetPx));
    const fillParentHeight = input.largeScreenShellActive || input.nativeVideoTakeoverActive;
    const bottomInsetPx = input.fullViewport || fillParentHeight ? 0 :
      Math.min(availableHeightPx - 1, Math.max(0, Math.ceil(input.visualBottomInsetPx ?? 0)));
    // Reserve space outside the native viewport. From here on top immersion uses
    // exactly the same geometry as an ordinary screen of this shorter height.
    const hostHeightPx = availableHeightPx - bottomInsetPx;
    const contentHeightPx = input.fullViewport ? hostHeightPx : Math.max(1, hostHeightPx - topInsetPx);
    const scrollHiddenTopBlurHeightPx = input.fullViewport || fillParentHeight || topInsetPx > 0
      ? 0 : Math.min(contentHeightPx, Math.max(0, input.scrollHiddenTopBlurHeightPx ?? 0));
    return {
      hostHeightPx,
      reservedBottomInsetPx: bottomInsetPx,
      topSafeOverlayHeightPx: topInsetPx,
      contentTopPx: topInsetPx,
      contentHeightPx,
      fillParentHeight,
      scrollHiddenTopBlurHeightPx
    };
  }

  static resolvePresentation(input: BrowserWebViewportLayerLayoutInput): BrowserWebViewportPresentationState {
    return BrowserWebViewportCoordinator.resolveLayerLayout(input);
  }

  static resolvePresentationUpdate(
    input: BrowserWebViewportPresentationUpdateInput
  ): BrowserWebViewportPresentationState {
    if (input.current.hostHeightPx === input.next.hostHeightPx &&
      input.current.reservedBottomInsetPx === input.next.reservedBottomInsetPx &&
      input.current.topSafeOverlayHeightPx === input.next.topSafeOverlayHeightPx &&
      input.current.contentTopPx === input.next.contentTopPx &&
      input.current.contentHeightPx === input.next.contentHeightPx &&
      input.current.scrollHiddenTopBlurHeightPx === input.next.scrollHiddenTopBlurHeightPx &&
      input.current.fillParentHeight === input.next.fillParentHeight) {
      return input.current;
    }
    return input.next;
  }

  static resolveTopBlurFractionStops(presentation: BrowserWebViewportPresentationState): FractionStop[] {
    const contentHeightPx = Math.max(1, presentation.contentHeightPx);
    const blurHeightPx = Math.max(0, presentation.scrollHiddenTopBlurHeightPx);
    if (blurHeightPx <= 0) {
      return [[0, 0], [0, 1]];
    }
    // Full blur starts on the first pixel under the safe strip. An offset
    // here leaves a sharp band between the strip and the gradient.
    const fraction = Math.min(1, blurHeightPx / contentHeightPx);
    const stops: FractionStop[] = [[1, 0], [1, fraction * 5 / 14], [0, fraction]];
    if (fraction < 1) {
      stops.push([0, 1]);
    }
    return stops;
  }
}
