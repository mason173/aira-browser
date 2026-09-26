import {
  BrowserBottomToolbarScrollBehavior,
  BrowserExperimentSettings
} from '../../common/models/BrowserModels';
import { WebScrollSmoothModeService } from '../../services/web/WebScrollSmoothModeService';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserWebLocalScrollSignalService } from '../../services/web/BrowserWebLocalScrollSignalService';
import { sharedBrowserContinuationCoordinator } from './BrowserContinuationCoordinator';
import { BrowserRecentActionManager } from '../web/BrowserRecentActionManager';
import {
  BrowserBottomChromeScrollCoordinator,
  BrowserBottomChromeScrollPresentation,
  BrowserBottomChromeWebScrollDecision,
  BrowserBottomChromeWebScrollInput
} from './BrowserBottomChromeScrollCoordinator';
import {
  BrowserScrollDeferredTaskKind,
  BrowserScrollPerformanceCoordinator,
  BrowserScrollPerformanceState
} from './BrowserScrollPerformanceCoordinator';
import { BrowserWebTopImmersionSessionCoordinator } from './BrowserWebTopImmersionSessionCoordinator';
import { BrowserWebViewportPresentationState } from './BrowserWebViewportCoordinator';
import { AiraScrollOscProbe } from '../../common/debug/AiraScrollOscProbe';
import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';

export type BrowserWebScrollTouchPhase = 'down' | 'move' | 'up' | 'cancel';
export type BrowserWebScrollInteractionKind = 'user' | 'programmatic';

export interface BrowserWebScrollInteractionConfig {
  recentTouchGraceMs: number;
  programmaticScrollSuppressMs: number;
  fallbackUserDeltaPx: number;
  interactionQuietMs: number;
  moveQuietRefreshMs: number;
  idleSettleDelayMs: number;
}

export interface BrowserWebScrollInteractionDecision {
  kind: BrowserWebScrollInteractionKind;
  touchActive: boolean;
  presentationChangeAllowed: boolean;
  reason: string;
}

export interface BrowserWebScrollInteractionShellFacts {
  activeTabId: string;
  bottomToolbarPinnedBySafeArea?: boolean;
  webPageVisible: boolean;
  addressFocused: boolean;
  currentDetent: HomeSearchPanelDetent;
  currentPresentation: BrowserBottomChromeScrollPresentation;
  tabsSheetVisible: boolean;
  webAppImmersiveMode: boolean;
  fullScreenModeEnabled: boolean;
  smoothModeRuntimeEnabled: boolean;
  experimentSettings: BrowserExperimentSettings;
}

export interface BrowserWebScrollInteractionShell {
  resolveFacts: () => BrowserWebScrollInteractionShellFacts;
  applyBottomChromeDecision: (decision: BrowserBottomChromeWebScrollDecision) => void;
}

export interface BrowserWebScrollInteractionDependencies {
  bottomChromeScrollCoordinator: BrowserBottomChromeScrollCoordinator;
  topImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator;
  recentActionManager: BrowserRecentActionManager;
  scrollPerformanceCoordinator: BrowserScrollPerformanceCoordinator;
  smoothModeService: WebScrollSmoothModeService;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
}

const DEFAULT_WEB_SCROLL_INTERACTION_CONFIG: BrowserWebScrollInteractionConfig = {
  recentTouchGraceMs: 700,
  programmaticScrollSuppressMs: 1200,
  fallbackUserDeltaPx: 2,
  interactionQuietMs: 2200,
  moveQuietRefreshMs: 240,
  idleSettleDelayMs: 80
};

const CONTINUATION_SCROLL_CHECKPOINT_DELAY_MS: number = 300;
// Covers the immediate ArkWeb reflow after the native top inset changes, without
// suppressing a whole gesture or treating every reverse scroll as layout feedback.
const VIEWPORT_SCROLL_CORRECTION_WINDOW_MS: number = 650;

export class BrowserWebScrollInteractionCoordinator {
  private readonly dependencies: BrowserWebScrollInteractionDependencies;
  private readonly shell: BrowserWebScrollInteractionShell;
  private readonly config: BrowserWebScrollInteractionConfig;
  private touchActive: boolean = false;
  private touchMoveObserved: boolean = false;
  private recentTouchUntilAt: number = 0;
  private recentScrollGestureUntilAt: number = 0;
  private programmaticScrollSuppressedUntilAt: number = 0;
  private lastScrollY: number = 0;
  private splitAddressBarScrollNotePending: boolean = false;
  private splitAddressBarScrollNoteTrack: boolean = false;
  private viewportCorrectionTabId: string = '';
  private viewportCorrectionRemainingPx: number = 0;
  private viewportCorrectionUntilAt: number = 0;
  private lastBottomChromeScrollY: number = 0;
  private bottomChromeScrollSourceId: string = '';
  private scrollPerformanceState: BrowserScrollPerformanceState;
  private settleTimer: number = -1;
  private pendingSettleTabId: string = '';
  private continuationScrollCheckpointTimer: number = -1;
  private pendingContinuationScrollTabId: string = '';
  private pendingContinuationScrollY: number = 0;
  private scrollBehavior: BrowserBottomToolbarScrollBehavior = 'compact';
  private readonly localScrollSignalService: BrowserWebLocalScrollSignalService =
    new BrowserWebLocalScrollSignalService();

  constructor(
    dependencies: BrowserWebScrollInteractionDependencies,
    shell: BrowserWebScrollInteractionShell,
    config: BrowserWebScrollInteractionConfig = DEFAULT_WEB_SCROLL_INTERACTION_CONFIG
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
    this.config = config;
    this.scrollPerformanceState = dependencies.scrollPerformanceCoordinator.createState();
  }

  handleScroll(tabId: string, scrollOffsetY: number): void {
    const facts = this.shell.resolveFacts();
    if (!this.shouldHandleActiveWebTab(tabId, facts)) {
      return;
    }
    const scrollY = this.normalizeScrollY(scrollOffsetY);
    const probePreviousY = this.lastScrollY;
    this.scheduleContinuationScrollCheckpoint(tabId, scrollY);
    this.adoptBottomChromeScrollSource(`global:${tabId}`, tabId, scrollY);
    const viewportCorrection = this.consumeViewportScrollCorrection(tabId, scrollY - this.lastScrollY);
    const interaction = this.resolveScrollInteraction(this.lastScrollY, scrollY);
    this.lastScrollY = scrollY;
    this.lastBottomChromeScrollY = scrollY;
    if (viewportCorrection) {
      this.dependencies.bottomChromeScrollCoordinator.reset(tabId, scrollY);
      this.dependencies.topImmersionSessionCoordinator.resetScrollBaseline(tabId, scrollY);
      this.queueSplitAddressBarScrollNote(false);
      return;
    }
    if (interaction.kind !== 'user') {
      AiraScrollOscProbe.markSignal(
        `global:${tabId}`, scrollY, scrollY - probePreviousY, 'skip_' + interaction.reason, interaction.reason
      );
      this.dependencies.bottomChromeScrollCoordinator.reset(tabId, scrollY);
      this.dependencies.topImmersionSessionCoordinator.resetScrollBaseline(tabId, scrollY);
      this.queueSplitAddressBarScrollNote(false);
      if (interaction.reason === 'programmatic_suppressed') {
        this.restoreBottomChromeScrollPresentation(facts, 'programmatic_scroll_restore');
      }
      return;
    }
    const decision = this.dependencies.bottomChromeScrollCoordinator.handleWebScrollMove(
      this.buildBottomChromeInput(facts, tabId, scrollY, interaction.presentationChangeAllowed)
    );
    AiraScrollOscProbe.markSignal(
      `global:${tabId}`, scrollY, scrollY - probePreviousY, decision.reason, interaction.reason
    );
    this.queueSplitAddressBarScrollNote(true);
    this.shell.applyBottomChromeDecision(decision);
    this.dependencies.topImmersionSessionCoordinator.handleScroll(
      tabId,
      scrollY,
      decision.changed && decision.reason === 'scroll_reveal'
    );
    this.activatePerformanceForMove();
    this.applySmoothModeForScroll(facts, tabId);
  }

  handleViewportChanged(
    tabId: string,
    previous: BrowserWebViewportPresentationState,
    next: BrowserWebViewportPresentationState
  ): void {
    const facts = this.shell.resolveFacts();
    if (tabId === facts.activeTabId && facts.bottomToolbarPinnedBySafeArea === true) {
      this.shell.applyBottomChromeDecision(this.dependencies.bottomChromeScrollCoordinator.handleWebScrollMove(
        this.buildBottomChromeInput(facts, tabId, this.lastBottomChromeScrollY, false)
      ));
    }
    // Top immersion resizes ordinary pages too. Layout feedback must not be
    // classified as a new gesture just because bottom avoidance is disabled.
    if (previous.fillParentHeight || next.fillParentHeight ||
      previous.hostHeightPx !== next.hostHeightPx) {
      this.clearViewportScrollCorrection();
      return;
    }
    const heightDelta = next.contentHeightPx - previous.contentHeightPx;
    if (heightDelta === 0) return;
    this.viewportCorrectionTabId = tabId;
    // A taller viewport can clamp scrollY backwards at the document end. A
    // shrinking viewport can move it forwards through scroll anchoring.
    this.viewportCorrectionRemainingPx = -heightDelta;
    this.viewportCorrectionUntilAt = Date.now() + VIEWPORT_SCROLL_CORRECTION_WINDOW_MS;
  }

  private consumeViewportScrollCorrection(tabId: string, delta: number): boolean {
    if (tabId !== this.viewportCorrectionTabId || Date.now() > this.viewportCorrectionUntilAt) {
      this.clearViewportScrollCorrection();
      return false;
    }
    const remaining = this.viewportCorrectionRemainingPx;
    if (delta === 0 || remaining === 0) return false;
    if (delta * remaining <= 0 || Math.abs(delta) > Math.abs(remaining) + 1) {
      // Different direction / beyond the geometry delta is genuine movement.
      this.clearViewportScrollCorrection();
      return false;
    }
    this.viewportCorrectionRemainingPx = Math.abs(delta) >= Math.abs(remaining) ? 0 : remaining - delta;
    return true;
  }

  private clearViewportScrollCorrection(): void {
    this.viewportCorrectionTabId = '';
    this.viewportCorrectionRemainingPx = 0;
    this.viewportCorrectionUntilAt = 0;
  }

  handleControllerAttached(tabId: string): void {
    const controller = this.dependencies.runtimeLifecyclePort.resolveController(tabId);
    if (controller === undefined) {
      return;
    }
    try {
      this.localScrollSignalService.registerBridge(controller, (payloadJson: string): void => {
        this.handleLocalScrollSignal(tabId, payloadJson);
      });
    } catch (_error) {
    }
    void sharedBrowserContinuationCoordinator.applyPendingScrollAfterRuntimeReady(
      tabId,
      this.dependencies.runtimeLifecyclePort.resolvePageUrl(tabId),
      this.dependencies.runtimeLifecyclePort
    );
  }

  handleLocalScrollSignal(tabId: string, payloadJson: string): void {
    const signal = this.localScrollSignalService.parseSignal(payloadJson);
    if (signal === undefined) {
      return;
    }
    const facts = this.shell.resolveFacts();
    if (!this.shouldHandleActiveWebTab(tabId, facts)) {
      return;
    }
    const scrollY = this.normalizeScrollY(signal.scrollTop);
    const sourceId = `local:${tabId}:${signal.sourceId}`;
    if (this.bottomChromeScrollSourceId !== sourceId) {
      const previousScrollY = this.normalizeScrollY(signal.scrollTop - signal.deltaY);
      this.adoptBottomChromeScrollSource(sourceId, tabId, previousScrollY);
    }
    this.lastBottomChromeScrollY = scrollY;
    const interaction = this.resolveScrollDeltaInteraction(signal.deltaY);
    if (interaction.kind !== 'user') {
      AiraScrollOscProbe.markSignal(
        sourceId, scrollY, signal.deltaY, 'skip_' + interaction.reason, interaction.reason
      );
      this.dependencies.bottomChromeScrollCoordinator.reset(tabId, scrollY);
      if (interaction.reason === 'programmatic_suppressed') {
        this.restoreBottomChromeScrollPresentation(facts, 'programmatic_local_scroll_restore');
      }
      return;
    }
    const decision = this.dependencies.bottomChromeScrollCoordinator.handleWebScrollMove(
      this.buildBottomChromeInput(facts, tabId, scrollY, interaction.presentationChangeAllowed)
    );
    AiraScrollOscProbe.markSignal(sourceId, scrollY, signal.deltaY, decision.reason, interaction.reason);
    this.shell.applyBottomChromeDecision(decision);
    this.activatePerformanceForMove();
    this.applySmoothModeForScroll(facts, tabId);
  }

  handleTouchEvent(tabId: string, type: TouchType): void {
    const phase = this.resolveTouchPhase(type);
    if (phase !== undefined) {
      this.handleTouch(tabId, phase);
    }
  }

  handleTouch(tabId: string, phase: BrowserWebScrollTouchPhase): void {
    const facts = this.shell.resolveFacts();
    if (!this.shouldHandleActiveWebTab(tabId, facts)) {
      return;
    }
    if (phase === 'down') {
      this.clearViewportScrollCorrection();
      this.dependencies.recentActionManager.recordClick(Date.now());
      this.cancelPendingSettle();
      this.dependencies.bottomChromeScrollCoordinator.reset(tabId, this.lastBottomChromeScrollY);
      this.recordTouchPhase(phase, Date.now());
      return;
    }
    if (phase === 'move') {
      this.recordTouchPhase(phase, Date.now());
      this.activatePerformanceForMove();
      return;
    }
    if (this.recordTouchPhase(phase, Date.now())) {
      this.activatePerformance();
      this.scheduleIdleSettle(tabId);
    }
  }

  resetForNavigation(tabId: string, scrollOffsetY: number = 0): void {
    this.clearViewportScrollCorrection();
    const scrollY = this.normalizeScrollY(scrollOffsetY);
    sharedBrowserContinuationCoordinator.updateActiveTabScroll(tabId, scrollY);
    this.cancelPendingSettle();
    this.lastScrollY = scrollY;
    this.lastBottomChromeScrollY = scrollY;
    this.bottomChromeScrollSourceId = `global:${tabId}`;
    this.suppressProgrammaticScroll();
    this.dependencies.bottomChromeScrollCoordinator.reset(tabId, scrollY);
    this.dependencies.topImmersionSessionCoordinator.resetScrollBaseline(tabId, scrollY);
    this.restoreBottomChromeScrollPresentation(this.shell.resolveFacts(), 'navigation_restore');
  }

  applyBottomToolbarScrollBehavior(
    behavior: BrowserBottomToolbarScrollBehavior,
    tabId: string
  ): void {
    if (this.scrollBehavior === behavior) {
      return;
    }
    this.scrollBehavior = behavior;
    this.cancelPendingSettle();
    this.dependencies.bottomChromeScrollCoordinator.reset(tabId, this.lastBottomChromeScrollY);
    this.dependencies.topImmersionSessionCoordinator.resetScrollBaseline(tabId, this.lastScrollY);
    this.restoreBottomChromeScrollPresentation(this.shell.resolveFacts(), 'scroll_behavior_changed_restore');
  }

  handleShellDisappear(): void {
    this.clearViewportScrollCorrection();
    const facts = this.shell.resolveFacts();
    this.flushContinuationScrollCheckpoint();
    this.cancelPendingSettle();
    this.touchActive = false;
    this.touchMoveObserved = false;
    this.recentTouchUntilAt = 0;
    this.recentScrollGestureUntilAt = 0;
    this.suppressProgrammaticScroll();
    this.dependencies.bottomChromeScrollCoordinator.reset(facts.activeTabId, this.lastBottomChromeScrollY);
    this.dependencies.topImmersionSessionCoordinator.resetScrollBaseline(facts.activeTabId, this.lastScrollY);
    this.restoreBottomChromeScrollPresentation(facts, 'shell_disappear_restore');
  }

  private restoreBottomChromeScrollPresentation(
    facts: BrowserWebScrollInteractionShellFacts,
    reason: string
  ): void {
    if (facts.currentPresentation === 'resting') {
      return;
    }
    this.shell.applyBottomChromeDecision({
      detent: facts.currentDetent,
      presentation: 'resting',
      changed: true,
      shouldClearAddressFocus: false,
      shouldClearAddressDraft: false,
      shouldSyncStatusBarStyle: false,
      reason: reason
    });
  }

  cancelPendingSettle(): void {
    if (this.settleTimer >= 0) {
      clearTimeout(this.settleTimer);
      this.settleTimer = -1;
    }
    this.pendingSettleTabId = '';
  }

  suppressProgrammaticScroll(now: number = Date.now()): void {
    const normalizedNow = Math.max(0, Math.floor(now));
    this.programmaticScrollSuppressedUntilAt = Math.max(
      this.programmaticScrollSuppressedUntilAt,
      normalizedNow + this.config.programmaticScrollSuppressMs
    );
  }

  beginHistoryReturnQuietWindow(now: number = Date.now()): void {
    this.cancelPendingSettle();
    this.suppressProgrammaticScroll(now);
  }

  takeSplitAddressBarScrollNote(): boolean {
    if (!this.splitAddressBarScrollNotePending) {
      return false;
    }
    this.splitAddressBarScrollNotePending = false;
    return true;
  }

  wasSplitAddressBarScrollTracked(): boolean {
    return this.splitAddressBarScrollNoteTrack;
  }

  private queueSplitAddressBarScrollNote(track: boolean): void {
    this.splitAddressBarScrollNotePending = true;
    this.splitAddressBarScrollNoteTrack = track;
  }

  getLastScrollY(): number {
    return this.lastScrollY;
  }

  getQuietDelayMs(baseDelayMs: number): number {
    return this.dependencies.scrollPerformanceCoordinator.getQuietDelayMs(
      this.scrollPerformanceState,
      baseDelayMs
    );
  }

  shouldDeferTask(kind: BrowserScrollDeferredTaskKind): boolean {
    return this.dependencies.scrollPerformanceCoordinator.shouldDeferTask(this.scrollPerformanceState, kind);
  }

  private shouldHandleActiveWebTab(tabId: string, facts: BrowserWebScrollInteractionShellFacts): boolean {
    return tabId === facts.activeTabId && facts.webPageVisible;
  }

  private buildBottomChromeInput(
    facts: BrowserWebScrollInteractionShellFacts,
    tabId: string,
    scrollOffsetY: number,
    presentationChangeAllowed: boolean
  ): BrowserBottomChromeWebScrollInput {
    return {
      tabId: tabId,
      bottomToolbarPinnedBySafeArea: facts.bottomToolbarPinnedBySafeArea,
      scrollOffsetY: this.normalizeScrollY(scrollOffsetY),
      webPageVisible: facts.webPageVisible,
      addressFocused: facts.addressFocused,
      currentDetent: facts.currentDetent,
      currentPresentation: facts.currentPresentation,
      presentationChangeAllowed: presentationChangeAllowed,
      showTabsSheet: facts.tabsSheetVisible,
      scrollBehavior: this.scrollBehavior,
      webAppImmersiveMode: facts.webAppImmersiveMode,
      fullScreenModeEnabled: facts.fullScreenModeEnabled
    };
  }

  private settleBottomChrome(tabId: string): void {
    const facts = this.shell.resolveFacts();
    if (!this.shouldHandleActiveWebTab(tabId, facts)) {
      return;
    }
    this.flushContinuationScrollCheckpoint();
    const decision = this.dependencies.bottomChromeScrollCoordinator.handleWebScrollSettle(
      this.buildBottomChromeInput(
        facts,
        tabId,
        this.lastBottomChromeScrollY,
        this.isPresentationChangeAllowed()
      )
    );
    this.shell.applyBottomChromeDecision(decision);
  }

  private scheduleIdleSettle(tabId: string): void {
    this.cancelPendingSettle();
    this.pendingSettleTabId = tabId;
    this.settleTimer = setTimeout(() => {
      this.settleTimer = -1;
      if (this.pendingSettleTabId !== tabId) {
        return;
      }
      this.pendingSettleTabId = '';
      this.settleBottomChrome(tabId);
    }, Math.max(0, Math.floor(this.config.idleSettleDelayMs)));
  }

  private scheduleContinuationScrollCheckpoint(tabId: string, scrollY: number): void {
    const normalizedScrollY = this.normalizeScrollY(scrollY);
    // Re-arming for an unchanged checkpoint cannot change the value that gets flushed, so keep the
    // timer already in flight. This avoids clearTimeout/setTimeout churn on every scroll event of
    // content-heavy pages, which repeat identical offsets while the gesture is held.
    if (this.continuationScrollCheckpointTimer >= 0 &&
      this.pendingContinuationScrollTabId === tabId &&
      this.pendingContinuationScrollY === normalizedScrollY) {
      return;
    }
    this.pendingContinuationScrollTabId = tabId;
    this.pendingContinuationScrollY = normalizedScrollY;
    if (this.continuationScrollCheckpointTimer >= 0) {
      clearTimeout(this.continuationScrollCheckpointTimer);
    }
    this.continuationScrollCheckpointTimer = setTimeout(() => {
      this.continuationScrollCheckpointTimer = -1;
      this.flushContinuationScrollCheckpoint();
    }, CONTINUATION_SCROLL_CHECKPOINT_DELAY_MS);
  }

  private flushContinuationScrollCheckpoint(): void {
    if (this.continuationScrollCheckpointTimer >= 0) {
      clearTimeout(this.continuationScrollCheckpointTimer);
      this.continuationScrollCheckpointTimer = -1;
    }
    const tabId = this.pendingContinuationScrollTabId;
    if (tabId.length > 0) {
      sharedBrowserContinuationCoordinator.updateActiveTabScroll(tabId, this.pendingContinuationScrollY);
    }
    this.pendingContinuationScrollTabId = '';
    this.pendingContinuationScrollY = 0;
  }

  private applySmoothModeForScroll(facts: BrowserWebScrollInteractionShellFacts, tabId: string): void {
    if (!facts.smoothModeRuntimeEnabled) {
      return;
    }
    this.dependencies.smoothModeService.handleScrollMoveFromLifecyclePort(
      this.dependencies.runtimeLifecyclePort,
      tabId,
      facts.experimentSettings
    );
  }

  private activatePerformance(now: number = Date.now()): void {
    this.scrollPerformanceState = this.dependencies.scrollPerformanceCoordinator.activate(
      this.scrollPerformanceState,
      this.config.interactionQuietMs,
      now
    );
  }

  private activatePerformanceForMove(): void {
    this.scrollPerformanceState = this.dependencies.scrollPerformanceCoordinator.activateForMove(
      this.scrollPerformanceState,
      this.config.interactionQuietMs,
      this.config.moveQuietRefreshMs
    );
  }

  private recordTouchPhase(phase: BrowserWebScrollTouchPhase, now: number): boolean {
    const normalizedNow = Math.max(0, Math.floor(now));
    if (phase === 'down') {
      this.touchActive = false;
      this.touchMoveObserved = false;
      this.recentTouchUntilAt = normalizedNow + this.config.recentTouchGraceMs;
      this.recentScrollGestureUntilAt = 0;
      this.programmaticScrollSuppressedUntilAt = 0;
      return false;
    }
    if (phase === 'move') {
      this.touchActive = true;
      this.touchMoveObserved = true;
      this.recentTouchUntilAt = normalizedNow + this.config.recentTouchGraceMs;
      this.recentScrollGestureUntilAt = normalizedNow + this.config.recentTouchGraceMs;
      this.programmaticScrollSuppressedUntilAt = 0;
      return false;
    }
    const shouldSettle = this.touchActive;
    this.touchActive = false;
    if (this.touchMoveObserved) {
      const settleGraceMs = Math.floor(this.config.recentTouchGraceMs / 2);
      this.recentTouchUntilAt = normalizedNow + settleGraceMs;
      this.recentScrollGestureUntilAt = normalizedNow + settleGraceMs;
    } else {
      this.recentTouchUntilAt = 0;
      this.recentScrollGestureUntilAt = 0;
    }
    this.touchMoveObserved = false;
    return shouldSettle;
  }

  private resolveScrollInteraction(
    previousScrollY: number,
    nextScrollY: number,
    now: number = Date.now()
  ): BrowserWebScrollInteractionDecision {
    const delta = Math.abs(this.normalizeScrollY(nextScrollY) - this.normalizeScrollY(previousScrollY));
    return this.resolveScrollInteractionFromDelta(delta, now);
  }

  private resolveScrollDeltaInteraction(
    deltaY: number,
    now: number = Date.now()
  ): BrowserWebScrollInteractionDecision {
    return this.resolveScrollInteractionFromDelta(Math.abs(deltaY), now);
  }

  private resolveScrollInteractionFromDelta(
    delta: number,
    now: number
  ): BrowserWebScrollInteractionDecision {
    const normalizedNow = Math.max(0, Math.floor(now));
    if (this.touchActive) {
      return this.buildDecision('user', true, 'touch_active');
    }
    if (normalizedNow <= this.programmaticScrollSuppressedUntilAt) {
      return this.buildDecision('programmatic', false, 'programmatic_suppressed');
    }
    if (normalizedNow <= this.recentScrollGestureUntilAt) {
      return this.buildDecision('user', true, 'recent_scroll_gesture');
    }
    if (normalizedNow <= this.recentTouchUntilAt) {
      return this.buildDecision('user', false, 'recent_touch');
    }
    if (delta >= this.config.fallbackUserDeltaPx) {
      return this.buildDecision('user', false, 'scroll_delta_fallback');
    }
    return this.buildDecision('programmatic', false, 'no_user_signal');
  }

  private isPresentationChangeAllowed(now: number = Date.now()): boolean {
    const normalizedNow = Math.max(0, Math.floor(now));
    if (normalizedNow <= this.programmaticScrollSuppressedUntilAt) {
      return false;
    }
    return this.touchActive || normalizedNow <= this.recentScrollGestureUntilAt;
  }

  private normalizeScrollY(scrollY: number): number {
    return Math.max(0, Math.round(scrollY));
  }

  private adoptBottomChromeScrollSource(sourceId: string, tabId: string, scrollY: number): void {
    if (this.bottomChromeScrollSourceId === sourceId) {
      return;
    }
    this.bottomChromeScrollSourceId = sourceId;
    this.lastBottomChromeScrollY = this.normalizeScrollY(scrollY);
    AiraScrollOscProbe.markSource(sourceId, this.lastBottomChromeScrollY);
    this.dependencies.bottomChromeScrollCoordinator.reset(tabId, this.lastBottomChromeScrollY);
  }

  private resolveTouchPhase(type: TouchType): BrowserWebScrollTouchPhase | undefined {
    if (type === TouchType.Down) {
      return 'down';
    }
    if (type === TouchType.Move) {
      return 'move';
    }
    if (type === TouchType.Up) {
      return 'up';
    }
    if (type === TouchType.Cancel) {
      return 'cancel';
    }
    return undefined;
  }

  private buildDecision(
    kind: BrowserWebScrollInteractionKind,
    presentationChangeAllowed: boolean,
    reason: string
  ): BrowserWebScrollInteractionDecision {
    return {
      kind: kind,
      touchActive: this.touchActive,
      presentationChangeAllowed: presentationChangeAllowed,
      reason: reason
    };
  }
}
