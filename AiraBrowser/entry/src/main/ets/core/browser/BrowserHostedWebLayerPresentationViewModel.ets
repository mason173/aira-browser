import {
  BrowserTabsSharedSnapshotTransitionCoordinator,
  BrowserTabsSharedSnapshotDirection,
  BrowserTabsSharedSnapshotTransitionState
} from './BrowserTabsSharedSnapshotTransitionCoordinator';
import { BrowserTabsOverlayAnimationViewModel } from './BrowserTabsOverlayAnimationViewModel';
import { BrowserHostedWebHiddenSlot } from './BrowserHostedWebOwnershipCoordinator';
import { BrowserTabsOverviewScenePhase } from './tabsOverview/BrowserTabsOverviewSceneDriver';
import {
  BROWSER_TAB_PREVIEW_PIXEL_HEIGHT,
  BROWSER_TAB_PREVIEW_PIXEL_WIDTH
} from './BrowserTabPreviewMetrics';

export interface BrowserHostedWebLayerPresentationInput {
  showPageErrorSurface: boolean;
  holdPageErrorSurfaceDuringReload: boolean;
  showTabsSheet: boolean;
  tabsSharedSnapshotState: BrowserTabsSharedSnapshotTransitionState;
  tabsOverviewScenePhase: BrowserTabsOverviewScenePhase;
  tabsOverviewEntryAnimationActive: boolean;
  tabsOverlayEntryMode: string;
  tabsOverlayWebEntryProgress: number;
  tabsOverlayExiting: boolean;
  tabsOverlayWebLayerOpacity: number;
  tabsOverviewBackdropProgress: number;
}

export interface BrowserHostedWebLayerPresentationState {
  pageErrorSurfaceVisible: boolean;
  hostedWebSurfaceSuspended: boolean;
  hostedWebLayerMounted: boolean;
  hostedWebLayerOpacity: number;
  webSurfaceOpacity: number;
  webSurfaceScale: number;
  webSurfaceBlurRadius: number;
}

export interface BrowserHostedWebSourceSurfaceHandoffPatch {
  webLayerOpacity: number;
  webEntryProgress: number;
}

export interface BrowserHostedWebParkingSlotGeometryInput {
  hostedWebLayerMeasured: boolean;
  hostedWebLayerWidth: number;
  hostedWebLayerHeight: number;
  rootViewportWidth: number;
  rootViewportHeight: number;
  fallbackTopInsetPx: number;
}

export interface BrowserHostedWebParkingSlotGeometry {
  width: number;
  height: number;
}

export class BrowserHostedWebLayerPresentationViewModel {
  private tabsSharedSnapshotTransitionCoordinator: BrowserTabsSharedSnapshotTransitionCoordinator =
    new BrowserTabsSharedSnapshotTransitionCoordinator();
  private tabsOverlayAnimationViewModel: BrowserTabsOverlayAnimationViewModel =
    new BrowserTabsOverlayAnimationViewModel();

  buildState(input: BrowserHostedWebLayerPresentationInput): BrowserHostedWebLayerPresentationState {
    return {
      pageErrorSurfaceVisible: input.showPageErrorSurface || input.holdPageErrorSurfaceDuringReload,
      hostedWebSurfaceSuspended: input.showPageErrorSurface,
      hostedWebLayerMounted: this.shouldMountHostedWebLayer(input),
      hostedWebLayerOpacity: this.resolveHostedWebLayerOpacity(input),
      webSurfaceOpacity: this.resolveWebSurfaceOpacity(input),
      webSurfaceScale: this.tabsOverlayAnimationViewModel.resolveBackdropScale(input.tabsOverviewBackdropProgress),
      webSurfaceBlurRadius: this.tabsOverlayAnimationViewModel
        .resolveBackdropBlurRadius(input.tabsOverviewBackdropProgress)
    };
  }

  resolveHiddenHostedWebNodeParkingSlotGeometry(
    slot: BrowserHostedWebHiddenSlot,
    input: BrowserHostedWebParkingSlotGeometryInput
  ): BrowserHostedWebParkingSlotGeometry {
    if (slot.kind === 'background-hot') {
      return {
        width: BROWSER_TAB_PREVIEW_PIXEL_WIDTH,
        height: BROWSER_TAB_PREVIEW_PIXEL_HEIGHT
      };
    }
    return {
      width: this.resolveBackgroundTabPreviewHostWidth(input),
      height: this.resolveBackgroundTabPreviewHostHeight(input)
    };
  }

  buildSharedSnapshotSourceSurfaceHandoffPatch(
    direction: BrowserTabsSharedSnapshotDirection
  ): BrowserHostedWebSourceSurfaceHandoffPatch {
    if (direction === 'exit') {
      return {
        webLayerOpacity: 0,
        webEntryProgress: 0
      };
    }
    return {
      webLayerOpacity: 0,
      webEntryProgress: 1
    };
  }

  private resolveBackgroundTabPreviewHostWidth(input: BrowserHostedWebParkingSlotGeometryInput): number {
    if (input.hostedWebLayerMeasured && input.hostedWebLayerWidth > 1) {
      return input.hostedWebLayerWidth;
    }
    return Math.max(1, input.rootViewportWidth);
  }

  private resolveBackgroundTabPreviewHostHeight(input: BrowserHostedWebParkingSlotGeometryInput): number {
    if (input.hostedWebLayerMeasured && input.hostedWebLayerHeight > 1) {
      return input.hostedWebLayerHeight;
    }
    return Math.max(
      BROWSER_TAB_PREVIEW_PIXEL_HEIGHT,
      input.rootViewportHeight - input.fallbackTopInsetPx
    );
  }

  private shouldMountHostedWebLayer(_input: BrowserHostedWebLayerPresentationInput): boolean {
    // The root scene decides whether the Web shell is mounted. Once mounted, keep the
    // hosted Web node alive so selection/closing can reveal it without a cold reattach.
    return true;
  }

  private resolveHostedWebLayerOpacity(input: BrowserHostedWebLayerPresentationInput): number {
    if (this.tabsSharedSnapshotTransitionCoordinator.shouldHideWebLayer(input.tabsSharedSnapshotState)) {
      if (this.shouldKeepLiveWebUntilSnapshotEnterHandoff(input)) {
        return input.tabsOverlayWebLayerOpacity;
      }
      return 0;
    }
    return input.tabsOverlayWebLayerOpacity;
  }

  private resolveWebSurfaceOpacity(input: BrowserHostedWebLayerPresentationInput): number {
    if (!input.showTabsSheet || input.tabsOverlayEntryMode !== 'web') {
      return 1;
    }
    if (this.tabsSharedSnapshotTransitionCoordinator.shouldShowOverlay(input.tabsSharedSnapshotState)) {
      if (input.tabsSharedSnapshotState.direction === 'exit') {
        return this.tabsSharedSnapshotTransitionCoordinator.shouldRevealExitSourceSurface(input.tabsSharedSnapshotState)
          ? 1
          : 0;
      }
      if (this.isOpeningWebSnapshotEntry(input)) {
        return this.shouldKeepLiveWebUntilSnapshotEnterHandoff(input)
          ? this.clampProgress(input.tabsOverlayWebLayerOpacity)
          : 0;
      }
    }
    if (input.tabsOverlayExiting) {
      // During a tab-card selection morph the shared snapshot owns the reveal:
      // keep the live Web layer (and its page-colored backdrop) hidden until the
      // selection handoff raises webLayerOpacity at the very end. There is a brief
      // window right after tap where the scene is already exiting but the exit
      // snapshot state is not yet published (so shouldShowOverlay() is still
      // false); without this guard the fallback flashed the real page background
      // out around the still-small snapshot. Other exits (back/close) have no
      // snapshot cover, so they keep revealing the Web immediately.
      if (this.isSelectingTabExit(input)) {
        return this.clampProgress(input.tabsOverlayWebLayerOpacity);
      }
      return 1;
    }
    const webEntryProgress = this.clampProgress(input.tabsOverlayWebEntryProgress);
    if (!this.isOpeningWebSnapshotEntry(input)) {
      return 1 - webEntryProgress;
    }
    return 1;
  }

  private isSelectingTabExit(input: BrowserHostedWebLayerPresentationInput): boolean {
    return input.tabsOverviewScenePhase === 'selectingActiveTab' ||
      input.tabsOverviewScenePhase === 'selectingOtherTab';
  }

  private isOpeningWebSnapshotEntry(input: BrowserHostedWebLayerPresentationInput): boolean {
    if (!input.tabsOverviewEntryAnimationActive) {
      return false;
    }
    return input.tabsOverviewScenePhase === 'openingPreparingSnapshot' ||
      input.tabsOverviewScenePhase === 'openingWaitingForActiveCard' ||
      input.tabsOverviewScenePhase === 'openingMorphingActiveTab';
  }

  private shouldKeepLiveWebUntilSnapshotEnterHandoff(input: BrowserHostedWebLayerPresentationInput): boolean {
    if (!this.isOpeningWebSnapshotEntry(input) || input.tabsSharedSnapshotState.direction !== 'enter') {
      return false;
    }
    return this.clampProgress(input.tabsSharedSnapshotState.progress) <= 0;
  }

  private clampProgress(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(1, value));
  }
}
