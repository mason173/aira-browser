import { BrowserBottomToolbarScrollBehavior } from '../../common/models/BrowserModels';
import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';

export interface BrowserBottomChromeScrollConfig {
  applyPresentationDeltaPx: number;
  restorePresentationDeltaPx: number;
  transitionCooldownMs: number;
  homeDirectionNoisePx?: number;
  manualPeekRevealDeltaPx?: number;
}

export type BrowserBottomChromeScrollPresentation = 'resting' | 'compact' | 'hidden';

export interface BrowserBottomChromePresentationScrollInput {
  surfaceId: string;
  scrollOffsetY: number;
  surfaceVisible: boolean;
  addressFocused: boolean;
  currentDetent: HomeSearchPanelDetent;
  currentPresentation: BrowserBottomChromeScrollPresentation;
  presentationChangeAllowed: boolean;
  showTabsSheet: boolean;
  scrollBehavior: BrowserBottomToolbarScrollBehavior;
}

export interface BrowserBottomChromePresentationScrollDecision {
  presentation: BrowserBottomChromeScrollPresentation;
  changed: boolean;
  reason: string;
}

export interface BrowserBottomChromeHomeScrollDecision {
  detent: HomeSearchPanelDetent;
  presentation: BrowserBottomChromeScrollPresentation;
  changed: boolean;
  shouldClearAddressFocus: boolean;
  shouldClearAddressDraft: boolean;
  shouldSyncStatusBarStyle: boolean;
  reason: string;
}

export interface BrowserBottomChromeWebScrollInput {
  tabId: string;
  scrollOffsetY: number;
  webPageVisible: boolean;
  addressFocused: boolean;
  currentDetent: HomeSearchPanelDetent;
  currentPresentation: BrowserBottomChromeScrollPresentation;
  presentationChangeAllowed: boolean;
  showTabsSheet: boolean;
  scrollBehavior: BrowserBottomToolbarScrollBehavior;
  webAppImmersiveMode: boolean;
  fullScreenModeEnabled: boolean;
}

export interface BrowserBottomChromeWebScrollDecision {
  detent: HomeSearchPanelDetent;
  presentation: BrowserBottomChromeScrollPresentation;
  changed: boolean;
  shouldClearAddressFocus: boolean;
  shouldClearAddressDraft: boolean;
  shouldSyncStatusBarStyle: boolean;
  reason: string;
}

interface BrowserBottomChromeScrollState {
  tabId: string;
  lastScrollOffsetY: number;
  downwardDelta: number;
  upwardDelta: number;
  lastTransitionAt: number;
}

const DEFAULT_SCROLL_CONFIG: BrowserBottomChromeScrollConfig = {
  applyPresentationDeltaPx: 28,
  restorePresentationDeltaPx: 24,
  transitionCooldownMs: 180,
  homeDirectionNoisePx: 2,
  manualPeekRevealDeltaPx: 12
};

export class BrowserBottomChromeScrollCoordinator {
  private state: BrowserBottomChromeScrollState = {
    tabId: '',
    lastScrollOffsetY: 0,
    downwardDelta: 0,
    upwardDelta: 0,
    lastTransitionAt: 0
  };
  private config: BrowserBottomChromeScrollConfig;

  constructor(config: BrowserBottomChromeScrollConfig = DEFAULT_SCROLL_CONFIG) {
    this.config = config;
  }

  handlePresentationScroll(
    input: BrowserBottomChromePresentationScrollInput,
    now: number = Date.now()
  ): BrowserBottomChromePresentationScrollDecision {
    return this.handlePresentationScrollWithNoise(input, now, 0);
  }

  handleHomeScroll(
    input: BrowserBottomChromePresentationScrollInput,
    now: number = Date.now()
  ): BrowserBottomChromeHomeScrollDecision {
    const normalizedY = Math.max(0, Math.floor(input.scrollOffsetY));
    if (this.shouldDisableHomeScroll(input)) {
      this.rememberBaseline(input.surfaceId, normalizedY);
      return this.buildHomeScrollDecision(
        input,
        input.currentDetent,
        'resting',
        input.currentPresentation !== 'resting',
        input.currentPresentation !== 'resting' ? 'home_scroll_disabled_restore' : 'none'
      );
    }
    if (this.state.tabId !== input.surfaceId) {
      this.rememberBaseline(input.surfaceId, normalizedY);
      return this.buildHomeScrollDecision(
        input,
        input.currentDetent,
        input.currentPresentation,
        false,
        'none'
      );
    }
    if (input.currentDetent === 'peek') {
      return this.handleManualPeekHomeScroll(input, normalizedY, now);
    }
    const presentationDecision = this.handlePresentationScrollWithNoise(
      input,
      now,
      this.resolveHomeDirectionNoisePx()
    );
    return this.buildHomeScrollDecision(
      input,
      input.currentDetent,
      presentationDecision.presentation,
      presentationDecision.changed,
      presentationDecision.reason
    );
  }

  private handlePresentationScrollWithNoise(
    input: BrowserBottomChromePresentationScrollInput,
    now: number,
    directionNoisePx: number
  ): BrowserBottomChromePresentationScrollDecision {
    const normalizedY = Math.max(0, Math.floor(input.scrollOffsetY));
    if (this.shouldDisablePresentationScroll(input)) {
      this.rememberBaseline(input.surfaceId, normalizedY);
      return {
        presentation: 'resting',
        changed: input.currentPresentation !== 'resting',
        reason: input.currentPresentation !== 'resting' ? 'scroll_presentation_disabled_restore' : 'none'
      };
    }
    if (this.state.tabId !== input.surfaceId) {
      this.rememberBaseline(input.surfaceId, normalizedY);
      return this.buildUnchangedPresentationDecision(input);
    }
    if (!input.presentationChangeAllowed) {
      this.rememberBaseline(input.surfaceId, normalizedY);
      return this.buildUnchangedPresentationDecision(input);
    }
    this.recordScrollDelta(normalizedY, directionNoisePx);
    if (this.isTransitionCoolingDown(now)) {
      return this.buildUnchangedPresentationDecision(input);
    }
    const scrolledPresentation = this.resolveScrolledPresentation(input.scrollBehavior);
    if (input.currentPresentation !== scrolledPresentation && normalizedY > 0 &&
      this.state.downwardDelta >= this.config.applyPresentationDeltaPx) {
      this.state.downwardDelta = 0;
      this.state.lastTransitionAt = Math.max(0, Math.floor(now));
      return {
        presentation: scrolledPresentation,
        changed: true,
        reason: scrolledPresentation === 'hidden' ? 'scroll_hide' : 'scroll_compact'
      };
    }
    if (input.currentPresentation !== 'resting' &&
      this.state.upwardDelta >= this.config.restorePresentationDeltaPx) {
      this.state.upwardDelta = 0;
      this.state.lastTransitionAt = Math.max(0, Math.floor(now));
      return {
        presentation: 'resting',
        changed: true,
        reason: 'scroll_reveal'
      };
    }
    return this.buildUnchangedPresentationDecision(input);
  }

  private handleManualPeekHomeScroll(
    input: BrowserBottomChromePresentationScrollInput,
    normalizedY: number,
    now: number
  ): BrowserBottomChromeHomeScrollDecision {
    this.recordScrollDelta(normalizedY, this.resolveHomeDirectionNoisePx());
    const revealDeltaPx = this.resolveManualPeekRevealDeltaPx();
    if (this.state.downwardDelta < revealDeltaPx && this.state.upwardDelta < revealDeltaPx) {
      return this.buildHomeScrollDecision(
        input,
        'peek',
        'resting',
        input.currentPresentation !== 'resting',
        'none'
      );
    }
    this.state.downwardDelta = 0;
    this.state.upwardDelta = 0;
    this.state.lastTransitionAt = Math.max(0, Math.floor(now));
    return this.buildHomeScrollDecision(input, 'low', 'resting', true, 'home_manual_peek_scroll_restore');
  }

  private buildHomeScrollDecision(
    input: BrowserBottomChromePresentationScrollInput,
    detent: HomeSearchPanelDetent,
    presentation: BrowserBottomChromeScrollPresentation,
    changed: boolean,
    reason: string
  ): BrowserBottomChromeHomeScrollDecision {
    const resolvedChanged = changed || input.currentDetent !== detent ||
      input.currentPresentation !== presentation;
    return {
      detent: detent,
      presentation: presentation,
      changed: resolvedChanged,
      shouldClearAddressFocus: false,
      shouldClearAddressDraft: false,
      shouldSyncStatusBarStyle: input.currentDetent !== detent,
      reason: reason
    };
  }

  handleWebScrollMove(
    input: BrowserBottomChromeWebScrollInput,
    now: number = Date.now()
  ): BrowserBottomChromeWebScrollDecision {
    if (input.webAppImmersiveMode) {
      return this.buildForcedWebDetentDecision(input, true, true, 'webapp_immersive_forced_peek');
    }
    if (input.fullScreenModeEnabled) {
      return this.buildForcedWebDetentDecision(input, false, false, 'fullscreen_forced_peek');
    }
    if (input.currentDetent === 'peek') {
      const decision = this.recordManualPeekWebScrollMove(input);
      return {
        detent: decision.detent,
        presentation: decision.presentation,
        changed: decision.changed,
        shouldClearAddressFocus: decision.shouldClearAddressFocus,
        shouldClearAddressDraft: decision.shouldClearAddressDraft,
        shouldSyncStatusBarStyle: decision.shouldSyncStatusBarStyle,
        reason: decision.reason
      };
    }
    const decision = this.handleScrollPresentationMove(input, now);
    return {
      detent: decision.detent,
      presentation: decision.presentation,
      changed: decision.changed,
      shouldClearAddressFocus: decision.shouldClearAddressFocus,
      shouldClearAddressDraft: decision.shouldClearAddressDraft,
      shouldSyncStatusBarStyle: decision.shouldSyncStatusBarStyle,
      reason: decision.reason
    };
  }

  handleWebScrollSettle(
    input: BrowserBottomChromeWebScrollInput,
    now: number = Date.now()
  ): BrowserBottomChromeWebScrollDecision {
    if (input.webAppImmersiveMode) {
      return this.buildForcedWebDetentDecision(input, true, true, 'webapp_immersive_forced_peek');
    }
    if (input.fullScreenModeEnabled) {
      return this.buildForcedWebDetentDecision(input, false, false, 'fullscreen_forced_peek');
    }
    if (input.currentDetent === 'peek') {
      const decision = this.handleManualPeekWebScrollSettle(input, now);
      return {
        detent: decision.detent,
        presentation: decision.presentation,
        changed: decision.changed,
        shouldClearAddressFocus: decision.shouldClearAddressFocus,
        shouldClearAddressDraft: decision.shouldClearAddressDraft,
        shouldSyncStatusBarStyle: decision.shouldSyncStatusBarStyle,
        reason: decision.reason
      };
    }
    return this.buildUnchangedWebDecision(input);
  }

  reset(tabId: string = '', scrollOffsetY: number = 0): void {
    this.rememberBaseline(tabId, scrollOffsetY);
  }

  private isTransitionCoolingDown(now: number): boolean {
    const cooldownMs = Math.max(0, Math.floor(this.config.transitionCooldownMs));
    if (cooldownMs <= 0 || this.state.lastTransitionAt <= 0) {
      return false;
    }
    return Math.max(0, Math.floor(now)) - this.state.lastTransitionAt < cooldownMs;
  }

  private handleScrollPresentationMove(
    input: BrowserBottomChromeWebScrollInput,
    now: number
  ): BrowserBottomChromeWebScrollDecision {
    const presentationDecision = this.handlePresentationScroll(this.buildPresentationScrollInput(input), now);
    return {
      detent: input.currentDetent,
      presentation: presentationDecision.presentation,
      changed: presentationDecision.changed,
      shouldClearAddressFocus: false,
      shouldClearAddressDraft: false,
      shouldSyncStatusBarStyle: false,
      reason: presentationDecision.reason
    };
  }

  private recordManualPeekWebScrollMove(
    input: BrowserBottomChromeWebScrollInput
  ): BrowserBottomChromeWebScrollDecision {
    const normalizedY = Math.max(0, Math.floor(input.scrollOffsetY));
    if (!input.webPageVisible || input.showTabsSheet || input.addressFocused) {
      this.rememberBaseline(input.tabId, normalizedY);
      return this.buildManualPeekDecision(
        input,
        false,
        input.currentPresentation !== 'resting' ? 'manual_peek_disabled_restore' : 'none'
      );
    }
    if (this.state.tabId !== input.tabId) {
      this.rememberBaseline(input.tabId, normalizedY);
      return this.buildUnchangedWebDecision(input);
    }
    this.recordScrollDelta(normalizedY);
    return this.buildUnchangedWebDecision(input);
  }

  private handleManualPeekWebScrollSettle(
    input: BrowserBottomChromeWebScrollInput,
    now: number
  ): BrowserBottomChromeWebScrollDecision {
    const normalizedY = Math.max(0, Math.floor(input.scrollOffsetY));
    if (!input.webPageVisible || input.showTabsSheet || input.addressFocused) {
      this.rememberBaseline(input.tabId, normalizedY);
      return this.buildManualPeekDecision(
        input,
        false,
        input.currentPresentation !== 'resting' ? 'manual_peek_disabled_restore' : 'none'
      );
    }
    if (this.state.tabId !== input.tabId) {
      this.rememberBaseline(input.tabId, normalizedY);
      return this.buildUnchangedWebDecision(input);
    }
    if (this.state.downwardDelta <= 0 && this.state.upwardDelta <= 0) {
      return this.buildUnchangedWebDecision(input);
    }
    this.state.downwardDelta = 0;
    this.state.upwardDelta = 0;
    this.state.lastTransitionAt = Math.max(0, Math.floor(now));
    return this.buildManualPeekDecision(input, true, 'manual_peek_scroll_settle_restore');
  }

  private buildManualPeekDecision(
    input: BrowserBottomChromeWebScrollInput,
    restoreToLow: boolean,
    reason: string
  ): BrowserBottomChromeWebScrollDecision {
    const nextDetent: HomeSearchPanelDetent = restoreToLow ? 'low' : input.currentDetent;
    const changed = input.currentDetent !== nextDetent || input.currentPresentation !== 'resting';
    return {
      detent: nextDetent,
      presentation: 'resting',
      changed,
      shouldClearAddressFocus: false,
      shouldClearAddressDraft: false,
      shouldSyncStatusBarStyle: changed,
      reason
    };
  }

  private buildForcedWebDetentDecision(
    input: BrowserBottomChromeWebScrollInput,
    shouldClearAddressFocus: boolean,
    shouldClearAddressDraft: boolean,
    reason: string
  ): BrowserBottomChromeWebScrollDecision {
    const changed = input.currentDetent !== 'peek' ||
      input.currentPresentation !== 'resting' ||
      (shouldClearAddressFocus && input.addressFocused) ||
      shouldClearAddressDraft;
    return {
      detent: 'peek',
      presentation: 'resting',
      changed,
      shouldClearAddressFocus,
      shouldClearAddressDraft,
      shouldSyncStatusBarStyle: changed,
      reason
    };
  }

  private buildUnchangedWebDecision(input: BrowserBottomChromeWebScrollInput): BrowserBottomChromeWebScrollDecision {
    return {
      detent: input.currentDetent,
      presentation: input.currentPresentation,
      changed: false,
      shouldClearAddressFocus: false,
      shouldClearAddressDraft: false,
      shouldSyncStatusBarStyle: false,
      reason: 'none'
    };
  }

  private shouldDisablePresentationScroll(input: BrowserBottomChromePresentationScrollInput): boolean {
    return input.scrollBehavior === 'fixed' ||
      !input.surfaceVisible ||
      input.showTabsSheet ||
      input.addressFocused ||
      input.currentDetent !== 'low';
  }

  private shouldDisableHomeScroll(input: BrowserBottomChromePresentationScrollInput): boolean {
    return input.scrollBehavior === 'fixed' ||
      !input.presentationChangeAllowed ||
      !input.surfaceVisible ||
      input.showTabsSheet ||
      input.addressFocused ||
      (input.currentDetent !== 'low' && input.currentDetent !== 'peek');
  }

  private buildPresentationScrollInput(
    input: BrowserBottomChromeWebScrollInput
  ): BrowserBottomChromePresentationScrollInput {
    return {
      surfaceId: input.tabId,
      scrollOffsetY: input.scrollOffsetY,
      surfaceVisible: input.webPageVisible,
      addressFocused: input.addressFocused,
      currentDetent: input.currentDetent,
      currentPresentation: input.currentPresentation,
      presentationChangeAllowed: input.presentationChangeAllowed,
      showTabsSheet: input.showTabsSheet,
      scrollBehavior: input.scrollBehavior
    };
  }

  private buildUnchangedPresentationDecision(
    input: BrowserBottomChromePresentationScrollInput
  ): BrowserBottomChromePresentationScrollDecision {
    return {
      presentation: input.currentPresentation,
      changed: false,
      reason: 'none'
    };
  }

  private resolveScrolledPresentation(
    behavior: BrowserBottomToolbarScrollBehavior
  ): BrowserBottomChromeScrollPresentation {
    if (behavior === 'hidden') {
      return 'hidden';
    }
    return behavior === 'compact' ? 'compact' : 'resting';
  }

  private recordScrollDelta(normalizedY: number, directionNoisePx: number = 0): void {
    const delta = normalizedY - this.state.lastScrollOffsetY;
    const resolvedDirectionNoisePx = Math.max(0, Math.floor(directionNoisePx));
    if (delta > 0) {
      if (delta <= resolvedDirectionNoisePx && this.state.upwardDelta > 0) {
        return;
      }
      this.state.lastScrollOffsetY = normalizedY;
      this.state.downwardDelta += delta;
      this.state.upwardDelta = 0;
    } else if (delta < 0) {
      const upwardDelta = Math.abs(delta);
      if (upwardDelta <= resolvedDirectionNoisePx && this.state.downwardDelta > 0) {
        return;
      }
      this.state.lastScrollOffsetY = normalizedY;
      this.state.upwardDelta += upwardDelta;
      this.state.downwardDelta = 0;
    }
  }

  private resolveHomeDirectionNoisePx(): number {
    return Math.max(0, Math.floor(this.config.homeDirectionNoisePx ?? 2));
  }

  private resolveManualPeekRevealDeltaPx(): number {
    return Math.max(1, Math.floor(this.config.manualPeekRevealDeltaPx ?? 12));
  }

  private rememberBaseline(tabId: string, scrollOffsetY: number): void {
    this.state = {
      tabId: tabId,
      lastScrollOffsetY: Math.max(0, Math.floor(scrollOffsetY)),
      downwardDelta: 0,
      upwardDelta: 0,
      lastTransitionAt: 0
    };
  }
}
