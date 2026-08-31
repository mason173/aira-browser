import {
  BrowserBottomPanelResponsiveState,
  BrowserBottomPanelResponsiveViewModel
} from './BrowserBottomPanelResponsiveViewModel';
import {
  BrowserViewportStabilityPolicy,
  BrowserViewportState
} from './BrowserViewportStabilityPolicy';
import {
  AppWindowResponsiveLayoutService
} from '../../services/layout/AppWindowResponsiveLayoutService';

export interface BrowserRootBottomPanelLayoutInput {
  viewportWidth: number;
  viewportHeight: number;
  displayViewportWidth: number;
  displayViewportHeight: number;
  homeAddressFocused: boolean;
  webAddressFocused: boolean;
}

export interface BrowserRootBottomPanelLayoutState {
  viewport: BrowserViewportState;
  responsiveState: BrowserBottomPanelResponsiveState;
  homeHostHeight: number;
  webHostHeight: number;
  tabsHostHeight: number;
  homePanelHeight: number;
  webPanelHeight: number;
  layoutRenderKey: string;
}

export class BrowserRootBottomPanelLayoutModel {
  private stableHomeViewport: BrowserViewportState = { width: 0, height: 0 };
  private stableWebViewport: BrowserViewportState = { width: 0, height: 0 };
  private responsiveViewModel: BrowserBottomPanelResponsiveViewModel;
  private viewportStabilityPolicy: BrowserViewportStabilityPolicy;
  private appWindowResponsiveLayoutService: AppWindowResponsiveLayoutService;

  constructor(
    responsiveViewModel: BrowserBottomPanelResponsiveViewModel = new BrowserBottomPanelResponsiveViewModel(),
    viewportStabilityPolicy: BrowserViewportStabilityPolicy = new BrowserViewportStabilityPolicy(),
    appWindowResponsiveLayoutService: AppWindowResponsiveLayoutService = new AppWindowResponsiveLayoutService()
  ) {
    this.responsiveViewModel = responsiveViewModel;
    this.viewportStabilityPolicy = viewportStabilityPolicy;
    this.appWindowResponsiveLayoutService = appWindowResponsiveLayoutService;
  }

  private updateStableViewports(input: BrowserRootBottomPanelLayoutInput, viewport: BrowserViewportState): void {
    this.stableHomeViewport = this.resolveStableViewportState(
      viewport.width,
      viewport.height,
      this.stableHomeViewport,
      input.homeAddressFocused
    );
    this.stableWebViewport = this.resolveStableViewportState(
      viewport.width,
      viewport.height,
      this.stableWebViewport,
      input.webAddressFocused
    );
  }

  buildState(input: BrowserRootBottomPanelLayoutInput): BrowserRootBottomPanelLayoutState {
    const viewport = this.resolveResponsiveViewport(input);
    this.updateStableViewports(input, viewport);
    const stableHomeViewport = this.resolveInitializedStableViewport(this.stableHomeViewport, viewport);
    const stableWebViewport = this.resolveInitializedStableViewport(this.stableWebViewport, viewport);
    const responsiveState = this.responsiveViewModel.buildState({
      viewportWidth: viewport.width,
      viewportHeight: viewport.height
    });
    const homeHostHeight = this.resolveKeyboardAwareHostHeight(
      viewport,
      stableHomeViewport,
      input.homeAddressFocused
    );
    const webHostHeight = this.resolveKeyboardAwareHostHeight(
      viewport,
      stableWebViewport,
      input.webAddressFocused
    );
    return {
      viewport,
      responsiveState,
      homeHostHeight,
      webHostHeight,
      tabsHostHeight: viewport.height,
      homePanelHeight: this.responsiveViewModel.resolveBrowserPanelHeight({
        viewportHeight: homeHostHeight,
        addressFocused: input.homeAddressFocused,
        state: responsiveState
      }),
      webPanelHeight: this.responsiveViewModel.resolveWebPanelHeight({
        viewportHeight: webHostHeight,
        addressFocused: input.webAddressFocused,
        state: responsiveState
      }),
      layoutRenderKey: this.responsiveViewModel.buildLayoutRenderKey(responsiveState)
    };
  }

  private resolveStableViewportState(
    nextWidth: number,
    nextHeight: number,
    currentStableViewport: BrowserViewportState,
    keepStableOnShrink: boolean
  ): BrowserViewportState {
    return this.viewportStabilityPolicy.resolve({
      nextWidth,
      nextHeight,
      currentViewport: currentStableViewport,
      keepStableOnShrink
    });
  }

  private resolveKeyboardAwareHostHeight(
    viewport: BrowserViewportState,
    stableViewport: BrowserViewportState,
    addressFocused: boolean
  ): number {
    if (addressFocused || this.viewportStabilityPolicy.hasOrientationChanged(viewport, stableViewport)) {
      return viewport.height;
    }
    return Math.max(viewport.height, stableViewport.height);
  }

  private resolveInitializedStableViewport(
    stableViewport: BrowserViewportState,
    fallbackViewport: BrowserViewportState
  ): BrowserViewportState {
    if (stableViewport.width <= 0 || stableViewport.height <= 0) {
      return fallbackViewport;
    }
    return stableViewport;
  }

  private resolveResponsiveViewport(input: BrowserRootBottomPanelLayoutInput): BrowserViewportState {
    return this.appWindowResponsiveLayoutService.resolveViewport({
      viewportWidth: input.viewportWidth,
      viewportHeight: input.viewportHeight,
      displayViewportWidth: input.displayViewportWidth,
      displayViewportHeight: input.displayViewportHeight
    });
  }

}
