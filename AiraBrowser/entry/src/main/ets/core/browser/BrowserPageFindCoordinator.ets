import { webview } from '@kit.ArkWeb';
import { BrowserTabState } from '../tabs/TabManager';

type BrowserPageFindStatus =
  'empty' |
  'counting' |
  'navigating' |
  'matched' |
  'no_match' |
  'controller_unavailable';

interface BrowserPageFindTabState {
  tabId: string;
  query: string;
  activeMatchOrdinal: number;
  numberOfMatches: number;
  isDoneCounting: boolean;
  isSearchStable: boolean;
  isNavigating: boolean;
  status: BrowserPageFindStatus;
  openedAt: number;
  updatedAt: number;
  searchToken: number;
  navigateToken: number;
}

export interface BrowserPageFindBarState {
  visible: boolean;
  query: string;
  progressText: string;
  statusText: string;
  canSearchPrevious: boolean;
  canSearchNext: boolean;
  inputFocused: boolean;
}

export interface BrowserPageFindBarAction {
  type: 'query_change' | 'previous' | 'next' | 'close';
  query?: string;
}

export function createBrowserPageFindClosedBarState(): BrowserPageFindBarState {
  return {
    visible: false,
    query: '',
    progressText: '',
    statusText: '',
    canSearchPrevious: false,
    canSearchNext: false,
    inputFocused: false
  };
}

export interface BrowserPageFindOpenAvailabilityInput {
  tab?: BrowserTabState;
  webPageVisible: boolean;
}

export interface BrowserPageFindMoveResult {
  diagnosticText: string;
}

export interface BrowserPageFindController {
  searchAllAsync(searchString: string): void;
  searchNext(forward: boolean): void;
  clearMatches(): void;
  requestFocus?(): void;
}

export interface BrowserPageFindControllerHost {
  resolveController: (tabId: string) => BrowserPageFindController | webview.WebviewController | undefined;
  isControllerAttached: (tabId: string) => boolean;
  publishBarState: (tabId: string, state: BrowserPageFindBarState) => void;
  showStatusMessage?: (message: string) => void;
}

interface BrowserPageFindStatePatch {
  query?: string;
  activeMatchOrdinal?: number;
  numberOfMatches?: number;
  isDoneCounting?: boolean;
  isSearchStable?: boolean;
  isNavigating?: boolean;
  status?: BrowserPageFindStatus;
  updatedAt?: number;
  searchToken?: number;
  navigateToken?: number;
}

export class BrowserPageFindCoordinator {
  private readonly navigateUnlockDelayMs: number = 320;
  private readonly host: BrowserPageFindControllerHost;
  private statesByTabId: Record<string, BrowserPageFindTabState | undefined> = {};
  private pendingClearTabIds: string[] = [];
  private navigateUnlockTimersByTabId: Record<string, number | undefined> = {};

  constructor(host: BrowserPageFindControllerHost) {
    this.host = host;
  }

  canOpen(input: BrowserPageFindOpenAvailabilityInput): boolean {
    const tab = input.tab;
    if (tab === undefined || tab.isHome || !input.webPageVisible) {
      return false;
    }
    return this.host.resolveController(tab.id) !== undefined;
  }

  isVisibleForTab(tabId: string): boolean {
    return this.statesByTabId[tabId] !== undefined;
  }

  open(tabId: string): void {
    const now = Date.now();
    const existing = this.statesByTabId[tabId];
    this.statesByTabId[tabId] = existing !== undefined
      ? this.copyState(existing, existing.status, now)
      : this.createState(tabId, '', 'empty', now);
    this.reapplySearchIfNeeded(tabId);
    this.publishBarState(tabId);
  }

  close(tabId: string): void {
    this.clearNavigateUnlockTimer(tabId);
    this.clearMatches(tabId);
    this.statesByTabId[tabId] = undefined;
    this.publishBarState(tabId);
  }

  updateQuery(tabId: string, query: string): void {
    this.statesByTabId[tabId] = this.updateQueryState(tabId, query);
    this.publishBarState(tabId);
  }

  handleBarAction(tabId: string, action: BrowserPageFindBarAction): void {
    if (action.type === 'query_change') {
      this.updateQuery(tabId, action.query ?? '');
      return;
    }
    if (action.type === 'close') {
      this.close(tabId);
      return;
    }
    const result = this.move(tabId, action.type === 'next');
    if (result.diagnosticText.length > 0) {
      this.host.showStatusMessage?.(result.diagnosticText);
    }
  }

  move(tabId: string, forward: boolean): BrowserPageFindMoveResult {
    const state = this.statesByTabId[tabId];
    if (state === undefined ||
      state.numberOfMatches <= 0 ||
      state.query.trim().length === 0 ||
      !state.isSearchStable) {
      return {
        diagnosticText: '查找结果还在稳定中'
      };
    }
    if (state.isNavigating || state.status === 'navigating') {
      return {
        diagnosticText: ''
      };
    }
    if (!this.canUseController(tabId)) {
      this.statesByTabId[tabId] = this.copyState(state, 'controller_unavailable', Date.now());
      this.publishBarState(tabId);
      return {
        diagnosticText: 'Web 控制器暂不可用'
      };
    }
    try {
      const controller = this.host.resolveController(tabId);
      controller?.requestFocus?.();
      // Keep result navigation on ArkWeb's native find pipeline. Previous JS scroll correction made dynamic pages jump
      // unpredictably, and activeMatchOrdinal is only a logical index, not a visual scroll-completion guarantee.
      controller?.searchNext(forward);
    } catch (_error) {
      this.statesByTabId[tabId] = this.copyState(state, 'controller_unavailable', Date.now());
      this.publishBarState(tabId);
      return {
        diagnosticText: '调用 ArkWeb 查找跳转失败'
      };
    }
    const nextState = this.copyStateWithNavigation(state, Date.now());
    this.statesByTabId[tabId] = nextState;
    this.publishBarState(tabId);
    this.scheduleNavigateUnlock(tabId, nextState.navigateToken);
    return {
      diagnosticText: ''
    };
  }

  handleSearchResult(tabId: string, event: OnSearchResultReceiveEvent): void {
    const state = this.statesByTabId[tabId];
    if (state === undefined) {
      return;
    }
    const numberOfMatches = Math.max(0, event.numberOfMatches);
    const isNavigatingResult = state.status === 'navigating' || state.isNavigating;
    const isSearchStable = event.isDoneCounting || isNavigatingResult;
    const status: BrowserPageFindStatus = numberOfMatches > 0
      ? (isNavigatingResult ? 'navigating' : (isSearchStable ? 'matched' : 'counting'))
      : (event.isDoneCounting ? 'no_match' : 'counting');
    this.statesByTabId[tabId] = this.copyStateWithPatch(state, {
      activeMatchOrdinal: Math.max(0, event.activeMatchOrdinal),
      numberOfMatches: numberOfMatches,
      isDoneCounting: event.isDoneCounting,
      isSearchStable: isSearchStable,
      isNavigating: isNavigatingResult,
      status: status,
      updatedAt: Date.now()
    });
    this.publishBarState(tabId);
  }

  handleControllerAttached(tabId: string): void {
    this.flushPendingClear(tabId);
    this.reapplySearchIfNeeded(tabId);
    this.publishBarState(tabId);
  }

  handlePageBegin(tabId: string): void {
    const state = this.statesByTabId[tabId];
    this.clearNavigateUnlockTimer(tabId);
    this.clearMatches(tabId);
    if (state !== undefined && state.query.trim().length > 0) {
      this.statesByTabId[tabId] = this.copyStateWithPatch(state, {
        activeMatchOrdinal: 0,
        numberOfMatches: 0,
        isDoneCounting: false,
        isSearchStable: false,
        isNavigating: false,
        status: 'counting',
        updatedAt: Date.now(),
        searchToken: state.searchToken + 1
      });
    }
    this.publishBarState(tabId);
  }

  handleLoadFinished(tabId: string): void {
    this.reapplySearchIfNeeded(tabId);
    this.publishBarState(tabId);
  }

  handleControllerDisposed(tabId: string, removeState: boolean): void {
    this.clearMatches(tabId);
    if (removeState) {
      this.clearNavigateUnlockTimer(tabId);
      this.statesByTabId[tabId] = undefined;
      this.removePendingClear(tabId);
      this.publishBarState(tabId);
      return;
    }
    const state = this.statesByTabId[tabId];
    if (state !== undefined) {
      this.statesByTabId[tabId] = this.copyStateWithPatch(state, {
        isNavigating: false,
        status: 'controller_unavailable',
        updatedAt: Date.now()
      });
    }
    this.publishBarState(tabId);
  }

  handleActiveTabChanged(tabId: string): void {
    this.publishBarState(tabId);
  }

  clearPrivateTabs(privateTabIds: string[]): void {
    privateTabIds.forEach((tabId: string) => {
      this.close(tabId);
    });
  }

  private updateQueryState(tabId: string, query: string): BrowserPageFindTabState {
    const trimmedQuery = query.trim();
    const now = Date.now();
    if (trimmedQuery.length === 0) {
      this.clearNavigateUnlockTimer(tabId);
      this.clearMatches(tabId);
      return this.createState(tabId, '', 'empty', now);
    }
    if (!this.canUseController(tabId)) {
      this.clearNavigateUnlockTimer(tabId);
      return this.createState(tabId, query, 'controller_unavailable', now);
    }
    const existing = this.statesByTabId[tabId];
    if (existing !== undefined &&
      existing.query === query &&
      existing.isSearchStable &&
      existing.status !== 'controller_unavailable') {
      return existing;
    }
    this.clearNavigateUnlockTimer(tabId);
    const countingState = this.createState(tabId, query, 'counting', now, (existing?.searchToken ?? 0) + 1);
    this.statesByTabId[tabId] = countingState;
    try {
      this.host.resolveController(tabId)?.searchAllAsync(query);
    } catch (_error) {
      return this.createState(tabId, query, 'controller_unavailable', now);
    }
    return countingState;
  }

  private reapplySearchIfNeeded(tabId: string): void {
    const state = this.statesByTabId[tabId];
    if (state === undefined || state.query.trim().length === 0) {
      return;
    }
    this.statesByTabId[tabId] = this.updateQueryState(tabId, state.query);
  }

  private publishBarState(tabId: string): void {
    this.host.publishBarState(tabId, this.buildBarState(this.statesByTabId[tabId]));
  }

  private buildBarState(state: BrowserPageFindTabState | undefined): BrowserPageFindBarState {
    if (state === undefined) {
      return createBrowserPageFindClosedBarState();
    }
    const canMove = this.canMoveBetweenMatches(state);
    return {
      visible: true,
      query: state.query,
      progressText: this.buildProgressText(state),
      statusText: this.buildStatusText(state),
      canSearchPrevious: canMove,
      canSearchNext: canMove,
      inputFocused: state.status === 'empty' && state.query.length === 0
    };
  }

  private buildProgressText(state: BrowserPageFindTabState): string {
    if (state.query.trim().length === 0 || state.status === 'controller_unavailable') {
      return '';
    }
    if (!state.isDoneCounting && state.numberOfMatches <= 0) {
      return '统计中';
    }
    if (state.numberOfMatches <= 0) {
      return '0 / 0';
    }
    const current = Math.max(1, Math.min(state.numberOfMatches, state.activeMatchOrdinal + 1));
    return `${current} / ${state.numberOfMatches}`;
  }

  private buildStatusText(state: BrowserPageFindTabState): string {
    if (state.status === 'controller_unavailable') {
      return '页面暂不可查找';
    }
    if (state.query.trim().length === 0 || state.status === 'empty') {
      return '';
    }
    if (state.status === 'no_match') {
      return '无结果';
    }
    if (state.status === 'counting') {
      return '统计中';
    }
    if (state.status === 'navigating') {
      return '定位中';
    }
    return '';
  }

  private canMoveBetweenMatches(state: BrowserPageFindTabState): boolean {
    return state.status === 'matched' &&
      state.isSearchStable &&
      !state.isNavigating &&
      state.query.trim().length > 0 &&
      state.numberOfMatches > 0;
  }

  private clearMatches(tabId: string): void {
    if (!this.canUseController(tabId)) {
      this.addPendingClear(tabId);
      return;
    }
    try {
      this.host.resolveController(tabId)?.clearMatches();
      this.removePendingClear(tabId);
    } catch (_error) {
      this.addPendingClear(tabId);
    }
  }

  private flushPendingClear(tabId: string): void {
    if (this.pendingClearTabIds.indexOf(tabId) < 0) {
      return;
    }
    this.clearMatches(tabId);
  }

  private canUseController(tabId: string): boolean {
    return this.host.isControllerAttached(tabId) && this.host.resolveController(tabId) !== undefined;
  }

  private createState(
    tabId: string,
    query: string,
    status: BrowserPageFindStatus,
    now: number,
    searchToken: number = 0
  ): BrowserPageFindTabState {
    return {
      tabId: tabId,
      query: query,
      activeMatchOrdinal: 0,
      numberOfMatches: 0,
      isDoneCounting: status === 'empty',
      isSearchStable: status === 'empty',
      isNavigating: false,
      status: status,
      openedAt: now,
      updatedAt: now,
      searchToken: searchToken,
      navigateToken: 0
    };
  }

  private copyState(
    state: BrowserPageFindTabState,
    status: BrowserPageFindStatus,
    updatedAt: number
  ): BrowserPageFindTabState {
    return this.copyStateWithPatch(state, {
      isSearchStable: status === 'matched' || status === 'empty' || status === 'no_match' ?
        true : state.isSearchStable,
      isNavigating: status === 'navigating',
      status: status,
      updatedAt: updatedAt
    });
  }

  private copyStateWithNavigation(
    state: BrowserPageFindTabState,
    updatedAt: number
  ): BrowserPageFindTabState {
    return this.copyStateWithPatch(state, {
      isSearchStable: true,
      isNavigating: true,
      status: 'navigating',
      updatedAt: updatedAt,
      navigateToken: state.navigateToken + 1
    });
  }

  private scheduleNavigateUnlock(tabId: string, navigateToken: number): void {
    this.clearNavigateUnlockTimer(tabId);
    this.navigateUnlockTimersByTabId[tabId] = setTimeout(() => {
      this.navigateUnlockTimersByTabId[tabId] = undefined;
      const state = this.statesByTabId[tabId];
      if (state === undefined || state.navigateToken !== navigateToken || !state.isNavigating) {
        return;
      }
      this.statesByTabId[tabId] = this.copyStateWithPatch(state, {
        isSearchStable: true,
        isNavigating: false,
        status: state.numberOfMatches > 0 ? 'matched' : 'no_match',
        updatedAt: Date.now()
      });
      this.publishBarState(tabId);
    }, this.navigateUnlockDelayMs);
  }

  private copyStateWithPatch(
    state: BrowserPageFindTabState,
    patch: BrowserPageFindStatePatch
  ): BrowserPageFindTabState {
    return {
      tabId: state.tabId,
      query: patch.query !== undefined ? patch.query : state.query,
      activeMatchOrdinal: patch.activeMatchOrdinal !== undefined ? patch.activeMatchOrdinal : state.activeMatchOrdinal,
      numberOfMatches: patch.numberOfMatches !== undefined ? patch.numberOfMatches : state.numberOfMatches,
      isDoneCounting: patch.isDoneCounting !== undefined ? patch.isDoneCounting : state.isDoneCounting,
      isSearchStable: patch.isSearchStable !== undefined ? patch.isSearchStable : state.isSearchStable,
      isNavigating: patch.isNavigating !== undefined ? patch.isNavigating : state.isNavigating,
      status: patch.status !== undefined ? patch.status : state.status,
      openedAt: state.openedAt,
      updatedAt: patch.updatedAt !== undefined ? patch.updatedAt : state.updatedAt,
      searchToken: patch.searchToken !== undefined ? patch.searchToken : state.searchToken,
      navigateToken: patch.navigateToken !== undefined ? patch.navigateToken : state.navigateToken
    };
  }

  private clearNavigateUnlockTimer(tabId: string): void {
    const timer = this.navigateUnlockTimersByTabId[tabId];
    if (timer !== undefined) {
      clearTimeout(timer);
      this.navigateUnlockTimersByTabId[tabId] = undefined;
    }
  }

  private addPendingClear(tabId: string): void {
    if (tabId.length === 0 || this.pendingClearTabIds.indexOf(tabId) >= 0) {
      return;
    }
    this.pendingClearTabIds = this.pendingClearTabIds.concat([tabId]);
  }

  private removePendingClear(tabId: string): void {
    this.pendingClearTabIds = this.pendingClearTabIds.filter((item: string) => item !== tabId);
  }
}
