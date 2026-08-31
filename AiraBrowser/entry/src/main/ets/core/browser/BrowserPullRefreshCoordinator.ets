import {
  BrowserPullRefreshAction,
  BrowserPullRefreshContext,
  BrowserPullRefreshInputProfile,
  BrowserPullRefreshPresentation,
  BrowserPullRefreshShellFamily,
  BrowserPullRefreshState
} from './BrowserPullRefreshModels';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserActiveTabRuntimeRestoreCoordinator } from '../../services/web/BrowserActiveTabRuntimeRestoreCoordinator';
import { resolveCurrentSiteUrl } from './AddressDisplayFormatter';

const MIN_PULL_OFFSET_Y: number = 0;
const MAX_TRACKED_PULL_OFFSET_Y: number = 180;
const REFRESH_COMPLETION_TIMEOUT_MS: number = 12000;

interface BrowserPullRefreshDecision {
  state: BrowserPullRefreshState;
  shouldReload: boolean;
}

export interface BrowserPullRefreshShell {
  readSurfaceFacts: (activeTab?: BrowserTabState) => BrowserPullRefreshSurfaceFacts;
  publishState: (state: BrowserPullRefreshState) => void;
  prepareRootChromeForReload: () => void;
}

export interface BrowserPullRefreshSurfaceFacts {
  enabled: boolean;
  activeTab?: BrowserTabState;
  fallbackActiveTabId: string;
  fallbackPageUrl: string;
  showHomePage: boolean;
  showTabsSheet: boolean;
  webPageVisible: boolean;
  pageErrorSurfaceVisible: boolean;
  shellFamily: BrowserPullRefreshShellFamily;
  inputProfile: BrowserPullRefreshInputProfile;
}

export class BrowserPullRefreshCoordinator {
  private readonly activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator;
  private readonly shell: BrowserPullRefreshShell;
  private state: BrowserPullRefreshState;
  private refreshCompletionTimeoutTimer: number = -1;

  constructor(
    activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator,
    shell: BrowserPullRefreshShell
  ) {
    this.activeTabRuntimeRestoreCoordinator = activeTabRuntimeRestoreCoordinator;
    this.shell = shell;
    this.state = this.createResetState('', 0);
  }

  getSnapshot(): BrowserPullRefreshState {
    return this.state;
  }

  syncEnabled(): void {
    if (this.readContext().enabled) {
      return;
    }
    this.clearRefreshCompletionTimeout();
    this.publishState(this.createResetState('', this.state.generation + 1));
  }

  handleOffset(offsetY: number): void {
    const context = this.readContext();
    if (!this.isEligible(context)) {
      this.resetForSurfaceChange(context.activeTabId);
      return;
    }
    this.publishState(this.buildOffsetState(offsetY, this.state));
  }

  handleStatus(status: RefreshStatus): void {
    const action = this.mapRefreshStatus(status);
    if (action === BrowserPullRefreshAction.UNKNOWN) {
      return;
    }
    this.applyAction(action);
  }

  requestRefresh(): void {
    this.applyAction(BrowserPullRefreshAction.PULL_REFRESH);
  }

  handlePageBegin(tabId: string): void {
    if (tabId !== this.state.activeTabId || !this.state.refreshInFlight) {
      return;
    }
    this.publishState({
      action: BrowserPullRefreshAction.PULL_REFRESH,
      offsetY: Math.max(this.state.offsetY, 48),
      loadingVisible: true,
      enableLoading: true,
      refreshInFlight: true,
      activeTabId: this.state.activeTabId,
      generation: this.state.generation
    });
    this.scheduleRefreshCompletionTimeout(tabId, this.state.generation);
  }

  completePageRefresh(tabId: string): void {
    if (tabId !== this.state.activeTabId) {
      return;
    }
    this.clearRefreshCompletionTimeout();
    this.publishState(this.createResetState(tabId, this.state.generation + 1));
  }

  buildPresentation(
    observedState: BrowserPullRefreshState,
    topPlaceHolderHeight: number
  ): BrowserPullRefreshPresentation {
    const context = this.readContext();
    const enabled = this.isEligible(context) && observedState.activeTabId === context.activeTabId;
    if (!enabled || !observedState.loadingVisible || observedState.offsetY <= 0) {
      return {
        visible: false,
        offsetY: 0,
        topPlaceHolderHeight: 0,
        enableLoading: false
      };
    }
    return {
      visible: true,
      offsetY: observedState.offsetY,
      topPlaceHolderHeight: Math.max(0, topPlaceHolderHeight),
      enableLoading: observedState.enableLoading
    };
  }

  isEnabledForActiveSurface(activeTab?: BrowserTabState): boolean {
    return this.isEligible(this.readContext(activeTab));
  }

  handleShellDisappear(): void {
    this.clearRefreshCompletionTimeout();
  }

  private applyAction(action: BrowserPullRefreshAction): void {
    const context = this.readContext();
    const decision = this.buildActionDecision(action, context, this.state);
    this.publishState(decision.state);
    if (!decision.state.refreshInFlight) {
      this.clearRefreshCompletionTimeout();
    }
    if (!decision.shouldReload || context.activeTabId.length === 0) {
      return;
    }
    this.shell.prepareRootChromeForReload();
    this.scheduleRefreshCompletionTimeout(context.activeTabId, decision.state.generation);
    this.activeTabRuntimeRestoreCoordinator.reloadActive('user_manual_reload');
  }

  private buildActionDecision(
    action: BrowserPullRefreshAction,
    context: BrowserPullRefreshContext,
    state: BrowserPullRefreshState
  ): BrowserPullRefreshDecision {
    if (!this.isEligible(context)) {
      return {
        state: this.createResetState(context.activeTabId, state.generation + 1),
        shouldReload: false
      };
    }

    if (state.activeTabId.length > 0 && state.activeTabId !== context.activeTabId) {
      state = this.createResetState(context.activeTabId, state.generation + 1);
    }

    if (action === BrowserPullRefreshAction.PULL_REFRESH) {
      if (state.refreshInFlight) {
        return {
          state: this.copyForAction(action, state, true, true, context.activeTabId),
          shouldReload: false
        };
      }
      return {
        state: this.copyForAction(action, state, true, true, context.activeTabId, true),
        shouldReload: true
      };
    }

    if (action === BrowserPullRefreshAction.PULL_RESET) {
      return {
        state: this.createResetState(context.activeTabId, state.generation + 1),
        shouldReload: false
      };
    }

    if (action === BrowserPullRefreshAction.PULL_CANCEL) {
      return {
        state: this.copyForAction(action, state, false, false, context.activeTabId),
        shouldReload: false
      };
    }

    const enableLoading = state.refreshInFlight;
    return {
      state: this.copyForAction(action, state, true, enableLoading, context.activeTabId),
      shouldReload: false
    };
  }

  private resetForSurfaceChange(activeTabId: string): void {
    this.clearRefreshCompletionTimeout();
    this.publishState(this.createResetState(activeTabId, this.state.generation + 1));
  }

  private scheduleRefreshCompletionTimeout(tabId: string, generation: number): void {
    this.clearRefreshCompletionTimeout();
    if (tabId.length === 0) {
      return;
    }
    this.refreshCompletionTimeoutTimer = setTimeout(() => {
      this.refreshCompletionTimeoutTimer = -1;
      this.handleRefreshTimeout(tabId, generation);
    }, REFRESH_COMPLETION_TIMEOUT_MS);
  }

  private clearRefreshCompletionTimeout(): void {
    if (this.refreshCompletionTimeoutTimer < 0) {
      return;
    }
    clearTimeout(this.refreshCompletionTimeoutTimer);
    this.refreshCompletionTimeoutTimer = -1;
  }

  private handleRefreshTimeout(tabId: string, generation: number): void {
    if (!this.state.refreshInFlight || tabId !== this.state.activeTabId || generation !== this.state.generation) {
      return;
    }
    this.publishState(this.createResetState(tabId, this.state.generation + 1));
  }

  private publishState(state: BrowserPullRefreshState): void {
    this.state = state;
    this.shell.publishState(state);
  }

  private isEligible(context: BrowserPullRefreshContext): boolean {
    if (!context.enabled || context.activeTabId.length === 0) {
      return false;
    }
    if (context.shellFamily === 'large_screen' && context.inputProfile !== 'touch') {
      return false;
    }
    if (context.showHomePage || context.showTabsSheet || !context.webPageVisible || context.pageErrorSurfaceVisible) {
      return false;
    }
    return this.isHttpUrl(context.pageUrl);
  }

  private readContext(activeTab?: BrowserTabState): BrowserPullRefreshContext {
    const facts = this.shell.readSurfaceFacts(activeTab);
    const resolvedTab = activeTab ?? facts.activeTab;
    return {
      enabled: facts.enabled,
      activeTabId: resolvedTab?.id ?? facts.fallbackActiveTabId,
      pageUrl: resolvedTab === undefined
        ? facts.fallbackPageUrl
        : resolveCurrentSiteUrl(resolvedTab.url, resolvedTab.pendingUrl),
      showHomePage: facts.showHomePage || resolvedTab?.isHome === true,
      showTabsSheet: facts.showTabsSheet,
      webPageVisible: facts.webPageVisible,
      pageErrorSurfaceVisible: facts.pageErrorSurfaceVisible,
      shellFamily: facts.shellFamily,
      inputProfile: facts.inputProfile
    };
  }

  private isHttpUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private createResetState(activeTabId: string, generation: number): BrowserPullRefreshState {
    return {
      action: BrowserPullRefreshAction.PULL_RESET,
      offsetY: 0,
      loadingVisible: false,
      enableLoading: false,
      refreshInFlight: false,
      activeTabId: activeTabId,
      generation: generation
    };
  }

  private buildOffsetState(offsetY: number, state: BrowserPullRefreshState): BrowserPullRefreshState {
    const nextOffsetY = this.normalizeOffset(offsetY);
    if (state.action === BrowserPullRefreshAction.PULL_RESET && nextOffsetY <= 0) {
      return state;
    }
    return {
      action: nextOffsetY > 0 && state.action === BrowserPullRefreshAction.PULL_RESET
        ? BrowserPullRefreshAction.PULL_START
        : state.action,
      offsetY: nextOffsetY,
      loadingVisible: nextOffsetY > 0 || state.refreshInFlight,
      enableLoading: state.enableLoading,
      refreshInFlight: state.refreshInFlight,
      activeTabId: state.activeTabId,
      generation: state.generation
    };
  }

  private copyForAction(
    action: BrowserPullRefreshAction,
    state: BrowserPullRefreshState,
    loadingVisible: boolean,
    enableLoading: boolean,
    activeTabId: string,
    refreshInFlight: boolean = state.refreshInFlight
  ): BrowserPullRefreshState {
    return {
      action: action,
      offsetY: Math.max(state.offsetY, action === BrowserPullRefreshAction.PULL_REFRESH ? 48 : state.offsetY),
      loadingVisible: loadingVisible,
      enableLoading: enableLoading,
      refreshInFlight: refreshInFlight,
      activeTabId: activeTabId,
      generation: state.generation
    };
  }

  private normalizeOffset(offsetY: number): number {
    if (!Number.isFinite(offsetY)) {
      return MIN_PULL_OFFSET_Y;
    }
    return Math.max(MIN_PULL_OFFSET_Y, Math.min(MAX_TRACKED_PULL_OFFSET_Y, offsetY));
  }

  private mapRefreshStatus(status: RefreshStatus): BrowserPullRefreshAction {
    if (status === RefreshStatus.Drag) {
      return BrowserPullRefreshAction.PULL_START;
    }
    if (status === RefreshStatus.OverDrag) {
      return BrowserPullRefreshAction.PULL_RELEASE;
    }
    if (status === RefreshStatus.Refresh) {
      return BrowserPullRefreshAction.PULL_REFRESH;
    }
    if (status === RefreshStatus.Done) {
      return BrowserPullRefreshAction.PULL_CANCEL;
    }
    if (status === RefreshStatus.Inactive) {
      return BrowserPullRefreshAction.PULL_RESET;
    }
    return BrowserPullRefreshAction.UNKNOWN;
  }
}
