import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserTopImmersionScrollCoordinator } from './BrowserTopImmersionScrollCoordinator';
import { BrowserWindowWebTopGeometryInsets } from './BrowserWindowAvoidAreaCoordinator';

const TOP_IMMERSION_LOG_DOMAIN: number = 0x0000;
// Keep the established device-log filter channel stable after moving ownership out of BrowserShellPage.
const TOP_IMMERSION_DEVICE_LOG_TAG: string = 'BrowserShellPage';
const TOP_IMMERSION_SCROLL_TRANSITION_MS: number = 180;
const COVERED_PAGE_STATUS_BAR_HOLD_MS: number = 450;
const TOP_IMMERSION_BLUR_HEIGHT_SCALE: number = 1.5;

type BrowserWebTopImmersionForcedReason =
  'none' |
  'always' |
  'fullscreen' |
  'webapp' |
  'assistant';

export interface BrowserWebTopImmersionFacts {
  activeTabId: string;
  browserShellVisible: boolean;
  webPageVisible: boolean;
  homePageVisible: boolean;
  tabsSheetVisible: boolean;
  scrollTopImmersionEnabled: boolean;
  alwaysTopImmersionEnabled: boolean;
  fullScreenModeEnabled: boolean;
  webAppTopSafeAreaHidden: boolean;
  assistantVideoTakeoverActive: boolean;
  scrollOffsetY: number;
  addressFocused: boolean;
  bottomPanelInteractive: boolean;
  bottomToolbarPinnedBySafeArea?: boolean;
  statusBarVisible: boolean;
}

interface BrowserWebTopImmersionVisibilityRequest {
  respectForcedImmersion?: boolean;
  activeSurfaceReady?: boolean;
  resetScrollBaseline?: boolean;
  animate?: boolean;
}

export interface BrowserWebTopImmersionSessionHost {
  resolveVisibleTopInsetPx: () => number;
  applyPresentation: (visible: boolean, targetTopInsetPx: number, source: string,
    animationDurationMs: number) => void;
  applyWindowVisibility: (
    visible: boolean,
    source: string,
    shouldApply: () => boolean
  ) => Promise<boolean>;
  scheduleSafeInsetSettle: (source: string) => void;
}

export interface BrowserWebTopImmersionSessionDependencies {
  resolveFacts: () => BrowserWebTopImmersionFacts;
  host: BrowserWebTopImmersionSessionHost;
}

interface BrowserWebTopImmersionPendingHide {
  tabId: string;
  runtimeGeneration: number;
  source: string;
}

interface BrowserWebTopImmersionVisibilityOverride {
  ownerId: string;
  visible: boolean;
}

export class BrowserWebTopImmersionSessionCoordinator {
  private readonly dependencies: BrowserWebTopImmersionSessionDependencies;
  private readonly scrollCoordinator: BrowserTopImmersionScrollCoordinator;
  private activeTabId: string = '';
  private activeRuntimeGeneration: number = 0;
  private attachedRuntimeGeneration: number = -1;
  private activeWebSurfaceReady: boolean = false;
  private pendingHide: BrowserWebTopImmersionPendingHide | undefined = undefined;
  private visibilityOverride?: BrowserWebTopImmersionVisibilityOverride = undefined;
  private desiredVisible: boolean = true;
  private appliedVisible: boolean = true;
  private appliedVisibilityInitialized: boolean = false;
  private visibilityRequestGeneration: number = 0;
  private pendingWindowOperationCount: number = 0;
  private coveredPagePendingRestore: boolean = false;
  private coveredStatusBarHoldUntilMs: number = 0;
  private coveredStatusBarHoldTimer: number = -1;
  private visibilityTask: Promise<void> = Promise.resolve();

  constructor(
    dependencies: BrowserWebTopImmersionSessionDependencies,
    scrollCoordinator: BrowserTopImmersionScrollCoordinator = new BrowserTopImmersionScrollCoordinator()
  ) {
    this.dependencies = dependencies;
    this.scrollCoordinator = scrollCoordinator;
  }

  resolveWebTopSystemInsetVp(geometryInsets: BrowserWindowWebTopGeometryInsets): number {
    const facts = this.dependencies.resolveFacts();
    if (facts.alwaysTopImmersionEnabled) {
      return 0;
    }
    const systemTopInsetVp = Math.max(0, Math.ceil(geometryInsets.systemTopInsetVp));
    const cutoutTopInsetVp = Math.max(0, Math.ceil(geometryInsets.cutoutTopInsetVp));
    if (facts.statusBarVisible) {
      return cutoutTopInsetVp;
    }
    return Math.max(systemTopInsetVp, cutoutTopInsetVp);
  }

  resolveScrollHiddenTopBlurHeightVp(
    geometryInsets: BrowserWindowWebTopGeometryInsets,
    contentGapVp: number
  ): number {
    const facts = this.dependencies.resolveFacts();
    const forcedReason = this.resolveForcedReason(facts);
    const immersionCollapsed = !facts.statusBarVisible &&
      (facts.scrollTopImmersionEnabled || facts.alwaysTopImmersionEnabled);
    if (!this.isEligibleWebSurface(facts) || !immersionCollapsed ||
      forcedReason === 'fullscreen' || forcedReason === 'webapp' || forcedReason === 'assistant' ||
      this.visibilityOverride !== undefined) {
      return 0;
    }
    // Extend the blur to 1.5 times the visible strip, excluding any quick-search
    // row. Cutout geometry survives the status bar becoming hidden.
    const safeStripHeightVp = Math.max(0, Math.ceil(geometryInsets.cutoutTopInsetVp + contentGapVp));
    return safeStripHeightVp * TOP_IMMERSION_BLUR_HEIGHT_SCALE;
  }

  syncPolicy(source: string): void {
    const facts = this.dependencies.resolveFacts();
    const host = this.dependencies.host;
    this.syncActiveSurface(facts);
    const forcedReason = this.resolveForcedReason(facts);
    if (forcedReason !== 'none') {
      this.requestVisibility(false, facts, source, host, {
        respectForcedImmersion: true,
        activeSurfaceReady: forcedReason === 'assistant',
        resetScrollBaseline: true
      });
      return;
    }
    if (!this.isEligibleWebSurface(facts) || !facts.scrollTopImmersionEnabled) {
      this.requestVisibility(true, facts, source, host, {
        respectForcedImmersion: true,
        resetScrollBaseline: true
      });
    }
  }

  handleBeforeWebBuild(tabId: string): void {
    const facts = this.dependencies.resolveFacts();
    this.syncActiveSurface(facts);
    if (tabId.length <= 0 || tabId !== facts.activeTabId) {
      return;
    }
    this.activeRuntimeGeneration += 1;
    this.attachedRuntimeGeneration = -1;
    this.activeWebSurfaceReady = false;
    this.syncPolicy('before-web-build');
  }

  handleControllerAttached(tabId: string): void {
    const facts = this.dependencies.resolveFacts();
    this.syncActiveSurface(facts);
    if (tabId.length <= 0 || tabId !== facts.activeTabId) {
      return;
    }
    if (this.activeRuntimeGeneration <= 0) {
      this.activeRuntimeGeneration = 1;
    }
    this.attachedRuntimeGeneration = this.activeRuntimeGeneration;
    this.activeWebSurfaceReady = false;
    this.syncPolicy('controller-attached');
  }

  handlePageVisible(tabId: string): void {
    const facts = this.dependencies.resolveFacts();
    this.syncActiveSurface(facts);
    if (tabId.length <= 0 || tabId !== facts.activeTabId || !this.isEligibleWebSurface(facts) ||
      this.activeRuntimeGeneration <= 0 ||
      this.attachedRuntimeGeneration !== this.activeRuntimeGeneration) {
      return;
    }
    this.activeWebSurfaceReady = true;
    const source = this.resolvePendingHideSource(tabId);
    this.syncPolicy(source);
  }

  handleScroll(tabId: string, scrollOffsetY: number, bottomChromeRestoredByScroll: boolean = false): void {
    const facts = this.dependencies.resolveFacts();
    const host = this.dependencies.host;
    this.syncActiveSurface(facts);
    if (!facts.browserShellVisible) {
      return;
    }
    const forcedReason = this.resolveForcedReason(facts);
    if (forcedReason !== 'none') {
      const scrollProvesForcedSurfaceReady = forcedReason === 'fullscreen' || forcedReason === 'assistant';
      if (scrollProvesForcedSurfaceReady && tabId === facts.activeTabId && this.isEligibleWebSurface(facts)) {
        this.activeWebSurfaceReady = true;
      }
      this.requestVisibility(false, facts, 'web-scroll-forced', host, {
        respectForcedImmersion: true,
        activeSurfaceReady: scrollProvesForcedSurfaceReady,
        resetScrollBaseline: true
      });
      return;
    }
    if (tabId === facts.activeTabId && this.isEligibleWebSurface(facts)) {
      this.activeWebSurfaceReady = true;
    }
    const decision = this.scrollCoordinator.handleScroll({
      tabId: tabId,
      scrollOffsetY: scrollOffsetY,
      webPageVisible: facts.webPageVisible,
      addressFocused: facts.addressFocused,
      bottomPanelInteractive: facts.bottomPanelInteractive && facts.bottomToolbarPinnedBySafeArea !== true,
      bottomChromeRestoredByScroll: bottomChromeRestoredByScroll,
      showTabsSheet: facts.tabsSheetVisible,
      scrollImmersionEnabled: facts.scrollTopImmersionEnabled,
      currentStatusBarVisible: facts.statusBarVisible
    });
    if (!decision.changed) {
      return;
    }
    this.requestVisibility(decision.statusBarVisible, facts, 'web-scroll', host, {
      respectForcedImmersion: true,
      activeSurfaceReady: true,
      // Bottom chrome applies first and is already interactive when an upward
      // scroll restores it. Preserve that scroll intent instead of treating the
      // fresh interactive fact as a manual panel reveal. Focus/sheets still snap.
      animate: this.isEligibleWebSurface(facts) && facts.scrollTopImmersionEnabled &&
        !facts.addressFocused && (!facts.bottomPanelInteractive ||
          facts.bottomToolbarPinnedBySafeArea === true || bottomChromeRestoredByScroll)
    });
  }

  resetScrollBaseline(tabId: string, scrollOffsetY: number): void {
    this.scrollCoordinator.reset(tabId, scrollOffsetY);
  }

  reassertVisibleWindow(
    source: string
  ): Promise<void> {
    const host = this.dependencies.host;
    const facts = this.dependencies.resolveFacts();
    if (!this.desiredVisible || !facts.statusBarVisible) {
      return Promise.resolve();
    }
    this.pendingHide = undefined;
    const requestGeneration = ++this.visibilityRequestGeneration;
    this.enqueueWindowVisibility(true, source, host, requestGeneration, true);
    return this.visibilityTask;
  }

  requestVisible(source: string): void {
    const facts = this.dependencies.resolveFacts();
    this.requestVisibility(true, facts, source, this.dependencies.host, {
      resetScrollBaseline: true
    });
  }

  releaseVisible(source: string): void {
    const facts = this.dependencies.resolveFacts();
    this.requestVisibility(true, facts, source, this.dependencies.host, {
      respectForcedImmersion: false,
      resetScrollBaseline: true
    });
  }

  /**
   * Another page is covering the browser. Show the status bar for that page, but
   * leave the web viewport where it is. Resizing it during the transition stutters
   * the animation.
   */
  releaseCoveredPage(source: string): void {
    const facts = this.dependencies.resolveFacts();
    this.scrollCoordinator.reset(facts.activeTabId, facts.scrollOffsetY);
    this.pendingHide = undefined;
    this.desiredVisible = true;
    this.coveredPagePendingRestore = true;
    const requestGeneration = ++this.visibilityRequestGeneration;
    this.enqueueWindowVisibility(true, source, this.dependencies.host, requestGeneration, true, true);
  }

  /**
   * The browser page is back, but the page that covered it is still leaving.
   * Keep the status bar up until that transition ends, then match the web page again.
   */
  holdCoveredStatusBarForPageReturn(): void {
    if (!this.coveredPagePendingRestore) {
      return;
    }
    this.coveredPagePendingRestore = false;
    this.clearCoveredStatusBarHold();
    this.coveredStatusBarHoldUntilMs = Date.now() + COVERED_PAGE_STATUS_BAR_HOLD_MS;
    this.coveredStatusBarHoldTimer = setTimeout((): void => {
      this.coveredStatusBarHoldTimer = -1;
      this.coveredStatusBarHoldUntilMs = 0;
      const facts = this.dependencies.resolveFacts();
      if (!facts.browserShellVisible) {
        return;
      }
      this.restoreCoveredPage('page-show');
      this.syncPolicy('page-show');
    }, COVERED_PAGE_STATUS_BAR_HOLD_MS);
  }

  cancelCoveredStatusBarHold(): void {
    this.clearCoveredStatusBarHold();
  }

  private clearCoveredStatusBarHold(): void {
    if (this.coveredStatusBarHoldTimer >= 0) {
      clearTimeout(this.coveredStatusBarHoldTimer);
      this.coveredStatusBarHoldTimer = -1;
    }
    this.coveredStatusBarHoldUntilMs = 0;
  }

  private isCoveredStatusBarHeld(): boolean {
    return Date.now() < this.coveredStatusBarHoldUntilMs;
  }

  /**
   * The browser is visible again. Put the status bar back in line with the web
   * page, still without resizing it. The following policy sync applies the real mode.
   */
  restoreCoveredPage(source: string): void {
    const facts = this.dependencies.resolveFacts();
    if (this.desiredVisible === facts.statusBarVisible) {
      return;
    }
    this.desiredVisible = facts.statusBarVisible;
    this.pendingHide = undefined;
    const requestGeneration = ++this.visibilityRequestGeneration;
    this.enqueueWindowVisibility(
      facts.statusBarVisible, source, this.dependencies.host, requestGeneration, true, true
    );
  }

  requestVisibilityIntent(
    visible: boolean,
    source: string
  ): void {
    const facts = this.dependencies.resolveFacts();
    this.requestVisibility(visible, facts, source, this.dependencies.host, {
      respectForcedImmersion: true
    });
  }

  setVisibilityOverride(ownerId: string, visible: boolean, source: string): void {
    const normalizedOwnerId: string = ownerId.trim();
    if (normalizedOwnerId.length <= 0) {
      return;
    }
    this.visibilityOverride = {
      ownerId: normalizedOwnerId,
      visible: visible
    };
    const facts = this.dependencies.resolveFacts();
    this.requestVisibility(visible, facts, source, this.dependencies.host, {
      respectForcedImmersion: true
    });
  }

  releaseVisibilityOverride(ownerId: string, source: string): void {
    const visibilityOverride = this.visibilityOverride;
    if (visibilityOverride === undefined || visibilityOverride.ownerId !== ownerId.trim()) {
      return;
    }
    this.visibilityOverride = undefined;
    this.syncPolicy(source);
  }

  requestFullscreenHidden(): void {
    const facts = this.dependencies.resolveFacts();
    this.requestVisibility(false, facts, 'fullscreen-mode', this.dependencies.host, {
      respectForcedImmersion: true,
      activeSurfaceReady: true
    });
  }

  refreshVisibleInset(source: string): void {
    const facts = this.dependencies.resolveFacts();
    this.syncActiveSurface(facts);
    if (!this.desiredVisible || !facts.statusBarVisible || this.resolveForcedReason(facts) !== 'none') {
      return;
    }
    const targetTopInsetPx = Math.max(0, Math.ceil(this.dependencies.host.resolveVisibleTopInsetPx()));
    this.dependencies.host.applyPresentation(true, targetTopInsetPx, source, 0);
  }

  private requestVisibility(
    requestedVisible: boolean,
    facts: BrowserWebTopImmersionFacts,
    source: string,
    host: BrowserWebTopImmersionSessionHost,
    options: BrowserWebTopImmersionVisibilityRequest = {}
  ): void {
    this.syncActiveSurface(facts);
    if (options.resetScrollBaseline === true) {
      this.scrollCoordinator.reset(facts.activeTabId, facts.scrollOffsetY);
    }
    if (options.activeSurfaceReady === true && facts.activeTabId === this.activeTabId) {
      this.activeWebSurfaceReady = true;
    }
    const respectForcedImmersion = options.respectForcedImmersion !== false;
    const forcedReason = respectForcedImmersion ? this.resolveForcedReason(facts) : 'none';
    const overrideVisible = this.visibilityOverride?.visible;
    const nextVisible = forcedReason !== 'none'
      ? false
      : (overrideVisible !== undefined ? overrideVisible : requestedVisible);
    this.desiredVisible = nextVisible;
    const requestGeneration = ++this.visibilityRequestGeneration;
    if (!nextVisible && !this.canApplyHidden(facts, forcedReason)) {
      this.pendingHide = {
        tabId: this.activeTabId,
        runtimeGeneration: this.activeRuntimeGeneration,
        source: source
      };
      return;
    }
    this.pendingHide = undefined;
    const animationDurationMs = options.animate === true && forcedReason === 'none' &&
      overrideVisible === undefined ? TOP_IMMERSION_SCROLL_TRANSITION_MS : 0;
    this.applyDesiredVisibility(nextVisible, source, host, requestGeneration, animationDurationMs);
  }

  private resolveForcedReason(facts: BrowserWebTopImmersionFacts): BrowserWebTopImmersionForcedReason {
    if (facts.assistantVideoTakeoverActive) {
      return 'assistant';
    }
    if (!this.isEligibleWebSurface(facts)) {
      return 'none';
    }
    if (facts.fullScreenModeEnabled) {
      return 'fullscreen';
    }
    if (facts.webAppTopSafeAreaHidden) {
      return 'webapp';
    }
    if (facts.alwaysTopImmersionEnabled) {
      return 'always';
    }
    return 'none';
  }

  private isEligibleWebSurface(facts: BrowserWebTopImmersionFacts): boolean {
    return facts.browserShellVisible &&
      facts.webPageVisible &&
      !facts.homePageVisible &&
      !facts.tabsSheetVisible &&
      facts.activeTabId.length > 0;
  }

  private canApplyHidden(
    facts: BrowserWebTopImmersionFacts,
    forcedReason: BrowserWebTopImmersionForcedReason
  ): boolean {
    if (forcedReason === 'assistant') {
      return true;
    }
    return this.isEligibleWebSurface(facts) && this.activeWebSurfaceReady;
  }

  private syncActiveSurface(facts: BrowserWebTopImmersionFacts): void {
    const nextActiveTabId = facts.activeTabId.trim();
    if (nextActiveTabId !== this.activeTabId) {
      this.activeTabId = nextActiveTabId;
      this.activeRuntimeGeneration = 0;
      this.attachedRuntimeGeneration = -1;
      this.activeWebSurfaceReady = false;
      this.pendingHide = undefined;
    }
    if (facts.homePageVisible || nextActiveTabId.length <= 0) {
      this.activeWebSurfaceReady = false;
      this.pendingHide = undefined;
    }
  }

  private resolvePendingHideSource(tabId: string): string {
    const pendingHide = this.pendingHide;
    if (pendingHide === undefined || pendingHide.tabId !== tabId ||
      pendingHide.runtimeGeneration !== this.activeRuntimeGeneration) {
      return 'page-visible';
    }
    return pendingHide.source;
  }

  private applyDesiredVisibility(
    visible: boolean,
    source: string,
    host: BrowserWebTopImmersionSessionHost,
    requestGeneration: number,
    animationDurationMs: number
  ): void {
    const facts = this.dependencies.resolveFacts();
    if (facts.statusBarVisible !== visible) {
      const targetTopInsetPx = visible ? Math.max(0, Math.ceil(host.resolveVisibleTopInsetPx())) : 0;
      host.applyPresentation(visible, targetTopInsetPx, source, animationDurationMs);
    }
    this.enqueueWindowVisibility(visible, source, host, requestGeneration, false);
  }

  private enqueueWindowVisibility(
    visible: boolean,
    source: string,
    host: BrowserWebTopImmersionSessionHost,
    requestGeneration: number,
    forceApply: boolean,
    skipSafeInsetSettle: boolean = false
  ): void {
    if (!forceApply && this.pendingWindowOperationCount <= 0 &&
      this.appliedVisibilityInitialized && this.appliedVisible === visible) {
      return;
    }
    this.pendingWindowOperationCount += 1;
    this.visibilityTask = this.visibilityTask
      .catch((_error: Error) => {
      })
      .then(() => {
        if (requestGeneration !== this.visibilityRequestGeneration || this.desiredVisible !== visible) {
          return;
        }
        if (!visible && this.isCoveredStatusBarHeld()) {
          return;
        }
        return host.applyWindowVisibility(visible, source, (): boolean => {
          return requestGeneration === this.visibilityRequestGeneration && this.desiredVisible === visible;
        })
          .then((applied: boolean) => {
            if (!applied) {
              return;
            }
            this.appliedVisible = visible;
            this.appliedVisibilityInitialized = true;
            if (!skipSafeInsetSettle &&
              requestGeneration === this.visibilityRequestGeneration && this.desiredVisible === visible) {
              host.scheduleSafeInsetSettle(source);
            }
          });
      })
      .catch((error: Error) => {
        if (requestGeneration !== this.visibilityRequestGeneration) {
          return;
        }
        this.appliedVisibilityInitialized = false;
        const fallbackVisible = !visible && this.desiredVisible === visible;
        if (fallbackVisible) {
          this.desiredVisible = true;
          this.pendingHide = {
            tabId: this.activeTabId,
            runtimeGeneration: this.activeRuntimeGeneration,
            source: source
          };
        }
        if (fallbackVisible) {
          host.applyPresentation(
            true,
            host.resolveVisibleTopInsetPx(),
            `${source}-fallback`,
            0
          );
        }
        hilog.warn(
          TOP_IMMERSION_LOG_DOMAIN,
          TOP_IMMERSION_DEVICE_LOG_TAG,
          'Failed to set status bar visible=%{public}s on %{public}s: %{public}s',
          visible ? 'true' : 'false',
          source,
          error.message
        );
      })
      .then(() => {
        this.pendingWindowOperationCount = Math.max(0, this.pendingWindowOperationCount - 1);
      });
  }

}
