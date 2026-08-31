import { BrowserTabsOverlayAnimationViewModel } from '../BrowserTabsOverlayAnimationViewModel';
import { BrowserTabsOverlayRect } from '../BrowserTabsOverlayViewModel';

export type BrowserTabsOverviewScenePhase =
  'closed' |
  'openingHomeCards' |
  'openingPreparingSnapshot' |
  'openingWaitingForActiveCard' |
  'openingMorphingActiveTab' |
  'settled' |
  'selectingActiveTab' |
  'selectingOtherTab' |
  'closing';
export type BrowserTabsOverviewEntryMode = 'home' | 'web';

export interface BrowserTabsOverviewSceneState {
  phase: BrowserTabsOverviewScenePhase;
  backgroundMode: 'home';
  openedFromHome: boolean;
  activeTabIdAtOpen: string;
  morphCoveredTabId: string;
}

export interface BrowserTabsOverviewSceneTargetResult {
  state: BrowserTabsOverviewSceneState;
  shouldStartMorph: boolean;
}

export interface BrowserTabsOverviewSceneRenderInput {
  sceneState: BrowserTabsOverviewSceneState;
  showHomePage: boolean;
  showTabsSheet: boolean;
  keepHomeResident: boolean;
  sharedSnapshotOverlayVisible?: boolean;
}

export interface BrowserTabsOverviewSceneRenderState {
  homeLayerMounted: boolean;
  homeLiveContentMounted: boolean;
  homeBackdropLayerMounted: boolean;
  homeLayerInteractive: boolean;
  webLayerMounted: boolean;
  webLayerInteractive: boolean;
  cardsLayerMounted: boolean;
  cardsLayerOpacity: number;
  cardsLayerInteractive: boolean;
  rootBottomPanelHostRetained: boolean;
}

export interface BrowserTabsOverviewCapturedEntryInput {
  tabId: string;
  showTabsSheet: boolean;
  tabsOverlayExiting: boolean;
  hasEntryPixelMap: boolean;
}

export type BrowserTabsOverviewHeaderMode = 'home' | 'address';

export interface BrowserTabsOverviewSceneOverlayPatch {
  entryMode: BrowserTabsOverviewEntryMode;
  webEntryProgress: number;
  homeExitProgress: number;
  overlayOpacity: number;
  webLayerOpacity: number;
  backdropProgress: number;
}

export interface BrowserTabsOverviewSceneEntryRunPlan {
  kind: 'homeCards' | 'webSnapshot';
  sceneState: BrowserTabsOverviewSceneState;
  headerMode: BrowserTabsOverviewHeaderMode;
  overlayPatch: BrowserTabsOverviewSceneOverlayPatch;
  shouldFinishSharedSnapshotEntry: boolean;
  shouldClearSharedSnapshotIfHidden: boolean;
  exiting: boolean;
  entryAnimationActive: boolean;
  homeExitProgress: number;
  shouldShowTabsSheet: boolean;
  shouldResetHomeReveal: boolean;
  shouldHideBackgroundOpenPrompt: boolean;
  shouldCreateSharedSnapshotRunId: boolean;
  shouldResetEntrySnapshotFrame: boolean;
  shouldPrepareActiveCardTarget: boolean;
  statusBarReason: string;
  fallbackSettleDelayMs: number;
}

export interface BrowserTabsOverviewSceneClosePlan {
  sceneState: BrowserTabsOverviewSceneState;
  headerMode: BrowserTabsOverviewHeaderMode;
  exiting: boolean;
  entryAnimationActive: boolean;
}

export interface BrowserTabsOverviewSceneResetPatch {
  sceneState: BrowserTabsOverviewSceneState;
  exiting: boolean;
  homeSurfaceCloseInFlight: boolean;
  entryAnimationActive: boolean;
  webLayerOpacity: number;
  webEntryProgress: number;
  homeExitProgress: number;
  overlayOpacity: number;
  backdropProgress: number;
}

export class BrowserTabsOverviewSceneDriver {
  private animationViewModel: BrowserTabsOverlayAnimationViewModel = new BrowserTabsOverlayAnimationViewModel();

  buildClosedSceneState(): BrowserTabsOverviewSceneState {
    return {
      phase: 'closed',
      backgroundMode: 'home',
      openedFromHome: false,
      activeTabIdAtOpen: '',
      morphCoveredTabId: ''
    };
  }

  buildRenderState(input: BrowserTabsOverviewSceneRenderInput): BrowserTabsOverviewSceneRenderState {
    const currentSceneState = input.sceneState;
    const tabsSceneVisible = input.showTabsSheet && currentSceneState.phase !== 'closed';
    const homeLayerMounted = input.showHomePage ||
      input.keepHomeResident ||
      tabsSceneVisible;
    return {
      homeLayerMounted: homeLayerMounted,
      homeLiveContentMounted: input.showHomePage || input.keepHomeResident,
      homeBackdropLayerMounted: homeLayerMounted && !input.showHomePage,
      homeLayerInteractive: input.showHomePage && !tabsSceneVisible,
      webLayerMounted: this.shouldMountWebLayer(currentSceneState, input, tabsSceneVisible),
      webLayerInteractive: !input.showHomePage && !tabsSceneVisible,
      cardsLayerMounted: input.showTabsSheet,
      cardsLayerOpacity: this.resolveCardsLayerOpacity(currentSceneState),
      cardsLayerInteractive: currentSceneState.phase === 'settled',
      rootBottomPanelHostRetained: this.shouldRetainRootBottomPanelHost(
        currentSceneState,
        input,
        tabsSceneVisible
      )
    };
  }

  resolveGalleryCoveredTabId(currentSceneState: BrowserTabsOverviewSceneState): string {
    if (currentSceneState.phase === 'openingPreparingSnapshot' ||
      currentSceneState.phase === 'openingWaitingForActiveCard' ||
      currentSceneState.phase === 'openingMorphingActiveTab' ||
      currentSceneState.phase === 'selectingActiveTab' ||
      currentSceneState.phase === 'selectingOtherTab') {
      return currentSceneState.morphCoveredTabId;
    }
    return '';
  }

  resolveSelectionDisplacementTabId(
    currentSceneState: BrowserTabsOverviewSceneState,
    selectionMorphAnimating: boolean
  ): string {
    if (selectionMorphAnimating &&
      (currentSceneState.phase === 'selectingActiveTab' || currentSceneState.phase === 'selectingOtherTab')) {
      return currentSceneState.morphCoveredTabId;
    }
    return '';
  }

  resolveEntryDisplacementTabId(currentSceneState: BrowserTabsOverviewSceneState): string {
    if (currentSceneState.openedFromHome) {
      return '';
    }
    if (currentSceneState.phase === 'openingPreparingSnapshot' ||
      currentSceneState.phase === 'openingWaitingForActiveCard' ||
      currentSceneState.phase === 'openingMorphingActiveTab') {
      return currentSceneState.morphCoveredTabId;
    }
    return '';
  }

  shouldSettleEntryDisplacement(currentSceneState: BrowserTabsOverviewSceneState): boolean {
    return !currentSceneState.openedFromHome && currentSceneState.phase === 'openingMorphingActiveTab';
  }

  shouldRunSideCardEntryAnimation(currentSceneState: BrowserTabsOverviewSceneState): boolean {
    return currentSceneState.openedFromHome;
  }

  shouldProcessCapturedEntry(
    currentSceneState: BrowserTabsOverviewSceneState,
    input: BrowserTabsOverviewCapturedEntryInput
  ): boolean {
    const tabId = input.tabId.trim();
    return currentSceneState.phase !== 'closed' &&
      tabId.length > 0 &&
      tabId === currentSceneState.activeTabIdAtOpen &&
      input.showTabsSheet &&
      !input.tabsOverlayExiting &&
      input.hasEntryPixelMap;
  }

  buildEntrySnapshotReadyState(
    currentSceneState: BrowserTabsOverviewSceneState,
    tabId: string
  ): BrowserTabsOverviewSceneState {
    if (tabId !== currentSceneState.activeTabIdAtOpen ||
      currentSceneState.phase !== 'openingPreparingSnapshot') {
      return currentSceneState;
    }
    return this.withPhase(currentSceneState, 'openingWaitingForActiveCard');
  }

  buildEntryRunPlan(openedFromHome: boolean, activeTabId: string, backdropStartProgress: number):
    BrowserTabsOverviewSceneEntryRunPlan {
    return {
      kind: openedFromHome ? 'homeCards' : 'webSnapshot',
      sceneState: this.beginOpening(openedFromHome, activeTabId),
      headerMode: openedFromHome ? 'home' : 'address',
      overlayPatch: this.buildEntryOverlayPatch(backdropStartProgress),
      shouldFinishSharedSnapshotEntry: true,
      shouldClearSharedSnapshotIfHidden: true,
      exiting: false,
      entryAnimationActive: true,
      homeExitProgress: 0,
      shouldShowTabsSheet: true,
      shouldResetHomeReveal: true,
      shouldHideBackgroundOpenPrompt: true,
      shouldCreateSharedSnapshotRunId: !openedFromHome,
      shouldResetEntrySnapshotFrame: !openedFromHome,
      shouldPrepareActiveCardTarget: !openedFromHome,
      statusBarReason: openedFromHome ? 'tabs-overview-entry' : 'tabs-overview-direct-entry',
      fallbackSettleDelayMs: openedFromHome ?
        this.animationViewModel.getEntryStartDelayMs() + this.animationViewModel.getHomeRevealDurationMs() + 360 :
        this.animationViewModel.getSharedSnapshotEnterDurationMs() + 420
    };
  }

  buildClosePlan(
    currentSceneState: BrowserTabsOverviewSceneState,
    showHomePage: boolean,
    targetHeaderMode: BrowserTabsOverviewHeaderMode | undefined
  ): BrowserTabsOverviewSceneClosePlan {
    return {
      sceneState: currentSceneState.phase === 'closed' ? currentSceneState :
        this.withPhase(currentSceneState, 'closing'),
      headerMode: targetHeaderMode ?? (showHomePage ? 'home' : 'address'),
      exiting: true,
      entryAnimationActive: false
    };
  }

  buildClosedResetPatch(overlayOpacity: number = 1): BrowserTabsOverviewSceneResetPatch {
    return this.buildResetPatch(overlayOpacity, 0);
  }

  buildInterruptedReentryResetPatch(backdropStartProgress: number): BrowserTabsOverviewSceneResetPatch {
    return this.buildResetPatch(1, Math.max(0, Math.min(1, backdropStartProgress)));
  }

  private buildResetPatch(overlayOpacity: number, backdropProgress: number): BrowserTabsOverviewSceneResetPatch {
    return {
      sceneState: this.buildClosedSceneState(),
      exiting: false,
      homeSurfaceCloseInFlight: false,
      entryAnimationActive: false,
      webLayerOpacity: 1,
      webEntryProgress: 1,
      homeExitProgress: 0,
      overlayOpacity: overlayOpacity,
      backdropProgress: backdropProgress
    };
  }

  buildSelectionPanelExitState(
    currentSceneState: BrowserTabsOverviewSceneState,
    tabId: string,
    selectedTabIsHome: boolean
  ): BrowserTabsOverviewSceneClosePlan {
    const selectedTabId = tabId.trim();
    const selectingActive = selectedTabId.length > 0 && selectedTabId === currentSceneState.activeTabIdAtOpen;
    return {
      sceneState: currentSceneState.phase === 'closed' ? currentSceneState : {
        phase: selectingActive ? 'selectingActiveTab' : 'selectingOtherTab',
        backgroundMode: currentSceneState.backgroundMode,
        openedFromHome: currentSceneState.openedFromHome,
        activeTabIdAtOpen: currentSceneState.activeTabIdAtOpen,
        morphCoveredTabId: selectedTabId
      },
      headerMode: selectedTabIsHome ? 'home' : 'address',
      exiting: true,
      entryAnimationActive: false
    };
  }

  buildActiveCardRectReadyState(
    currentSceneState: BrowserTabsOverviewSceneState,
    tabId: string,
    targetRect: BrowserTabsOverlayRect | undefined
  ): BrowserTabsOverviewSceneTargetResult {
    if (currentSceneState.phase !== 'openingWaitingForActiveCard' ||
      tabId !== currentSceneState.activeTabIdAtOpen ||
      !this.isUsableRect(targetRect)) {
      return {
        state: currentSceneState,
        shouldStartMorph: false
      };
    }
    return {
      state: this.withPhase(currentSceneState, 'openingMorphingActiveTab'),
      shouldStartMorph: true
    };
  }

  buildSettledState(currentSceneState: BrowserTabsOverviewSceneState): BrowserTabsOverviewSceneState {
    if (currentSceneState.phase === 'closed') {
      return currentSceneState;
    }
    return {
      phase: 'settled',
      backgroundMode: currentSceneState.backgroundMode,
      openedFromHome: currentSceneState.openedFromHome,
      activeTabIdAtOpen: currentSceneState.activeTabIdAtOpen,
      morphCoveredTabId: ''
    };
  }

  shouldSettleOpeningFallback(currentSceneState: BrowserTabsOverviewSceneState, tabId: string): boolean {
    if (tabId !== currentSceneState.activeTabIdAtOpen) {
      return false;
    }
    return currentSceneState.phase === 'openingHomeCards' ||
      currentSceneState.phase === 'openingPreparingSnapshot' ||
      currentSceneState.phase === 'openingWaitingForActiveCard';
  }

  private beginOpening(openedFromHome: boolean, activeTabIdValue: string): BrowserTabsOverviewSceneState {
    const activeTabId = activeTabIdValue.trim();
    if (!openedFromHome && activeTabId.length <= 0) {
      return this.buildClosedSceneState();
    }
    return {
      phase: openedFromHome ? 'openingHomeCards' : 'openingPreparingSnapshot',
      backgroundMode: 'home',
      openedFromHome: openedFromHome,
      activeTabIdAtOpen: activeTabId,
      morphCoveredTabId: openedFromHome ? '' : activeTabId
    };
  }

  private withPhase(
    state: BrowserTabsOverviewSceneState,
    phase: BrowserTabsOverviewScenePhase
  ): BrowserTabsOverviewSceneState {
    return {
      phase: phase,
      backgroundMode: state.backgroundMode,
      openedFromHome: state.openedFromHome,
      activeTabIdAtOpen: state.activeTabIdAtOpen,
      morphCoveredTabId: state.morphCoveredTabId
    };
  }

  private shouldRetainRootBottomPanelHost(
    state: BrowserTabsOverviewSceneState,
    input: BrowserTabsOverviewSceneRenderInput,
    tabsSceneVisible: boolean
  ): boolean {
    if (!tabsSceneVisible || input.showHomePage || input.sharedSnapshotOverlayVisible === true) {
      return false;
    }
    return state.phase === 'openingPreparingSnapshot' || state.phase === 'openingWaitingForActiveCard';
  }

  private resolveCardsLayerOpacity(state: BrowserTabsOverviewSceneState): number {
    if (state.openedFromHome) {
      return 1;
    }
    if (state.phase === 'openingPreparingSnapshot' || state.phase === 'openingWaitingForActiveCard') {
      return 0;
    }
    return 1;
  }

  private shouldMountWebLayer(
    state: BrowserTabsOverviewSceneState,
    input: BrowserTabsOverviewSceneRenderInput,
    tabsSceneVisible: boolean
  ): boolean {
    if (!tabsSceneVisible) {
      return !input.showHomePage;
    }
    if (state.phase === 'openingPreparingSnapshot' ||
      state.phase === 'openingWaitingForActiveCard' ||
      state.phase === 'openingMorphingActiveTab') {
      return !state.openedFromHome;
    }
    if (state.phase === 'selectingActiveTab' ||
      state.phase === 'selectingOtherTab' ||
      state.phase === 'closing') {
      return !input.showHomePage;
    }
    return false;
  }

  private isUsableRect(rect: BrowserTabsOverlayRect | undefined): boolean {
    return rect !== undefined && rect.width > 0 && rect.height > 0;
  }

  private buildEntryOverlayPatch(backdropStartProgress: number): BrowserTabsOverviewSceneOverlayPatch {
    const directState = this.animationViewModel.buildDirectWebEntryState();
    return {
      entryMode: 'web',
      webEntryProgress: directState.webEntryProgress,
      homeExitProgress: directState.homeExitProgress,
      overlayOpacity: directState.overlayOpacity,
      webLayerOpacity: directState.webLayerOpacity,
      backdropProgress: Math.max(0, Math.min(1, backdropStartProgress))
    };
  }
}
