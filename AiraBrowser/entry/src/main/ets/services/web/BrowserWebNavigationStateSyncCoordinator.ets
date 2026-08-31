import { BrowserWebTabsController } from '../../core/browser/BrowserWebTabsController';
import { BrowserWebHistoryDirection } from '../../core/web/BrowserWebComponentController';
import { BrowserWebPageStateSnapshot } from '../../core/web/BrowserWebPageController';
import { WEB_TRANSIENT_LOADING_TITLE } from '../../core/web/WebRuntimeBridge';
import { BrowserTabRuntimePatch, BrowserTabState } from '../../core/tabs/TabManager';
import { normalizeNavigationTarget } from '../../core/browser/AddressDisplayFormatter';

export interface BrowserWebNavigationCommittedUrlRestoreState {
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
  currentTitle: string;
}

export interface BrowserWebNavigationHistoryTargetPreviewState {
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
}

export interface BrowserWebNavigationStateSyncCoordinatorHost {
  resolveWebTabsController: () => BrowserWebTabsController;
  resolveActiveTabId: () => string;
  resolveCurrentUrl: () => string;
  resolveHistoryTargetIntentUrl: (tabId: string) => string;
  findTabById: (tabId: string) => BrowserTabState | undefined;
  shouldDeferNavigationStateForWebScroll: () => boolean;
  resolveWebScrollQuietDelayMs: (baseDelayMs: number) => number;
  applyNavigationState: (canGoBack: boolean, canGoForward: boolean) => void;
  isActiveWebTabVisible: (tabId: string) => boolean;
  resolveCommittedAddressDisplayText: (url: string) => string;
  applyTabPatch: (tabId: string, patch: BrowserTabRuntimePatch, persistTabs: boolean) => void;
  rememberProvisionalNavigation: (tabId: string, url: string) => void;
  applyCommittedUrlRestoreState: (state: BrowserWebNavigationCommittedUrlRestoreState) => void;
  applyHistoryTargetPreviewState: (state: BrowserWebNavigationHistoryTargetPreviewState) => void;
  finishActivePageLoadingProgress: () => void;
}

export class BrowserWebNavigationStateSyncCoordinator {
  private readonly host: BrowserWebNavigationStateSyncCoordinatorHost;
  private readonly scrollDeferredDelayMs: number;
  private readonly soonDelayMs: number;
  private pendingScrollDeferredNavigationStateTimer: number = -1;
  private currentDocumentUrlByTabId: Record<string, string | undefined> = {};
  private receivedTitleByTabId: Record<string, string | undefined> = {};
  private receivedTitleUrlByTabId: Record<string, string | undefined> = {};

  constructor(
    host: BrowserWebNavigationStateSyncCoordinatorHost,
    scrollDeferredDelayMs: number,
    soonDelayMs: number = 120
  ) {
    this.host = host;
    this.scrollDeferredDelayMs = scrollDeferredDelayMs;
    this.soonDelayMs = soonDelayMs;
  }

  sync(fromScrollDeferredUpdate: boolean = false): void {
    if (!fromScrollDeferredUpdate && this.host.shouldDeferNavigationStateForWebScroll()) {
      this.scheduleScrollDeferredSync();
      return;
    }
    this.clearScrollDeferredTimer();
    const snapshot = this.host
      .resolveWebTabsController()
      .refreshActiveNavigationState();
    this.applySnapshot(snapshot);
  }

  syncSoon(): void {
    setTimeout(() => {
      this.sync();
    }, this.soonDelayMs);
  }

  recordCurrentDocumentUrl(tabId: string, url: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedUrl = url.trim();
    if (normalizedTabId.length <= 0 || normalizedUrl.length <= 0) {
      return;
    }
    const receivedTitleUrl = this.receivedTitleUrlByTabId[normalizedTabId]?.trim() ?? '';
    if (receivedTitleUrl.length > 0 && !this.isSameNavigationTarget(receivedTitleUrl, normalizedUrl)) {
      this.receivedTitleByTabId[normalizedTabId] = undefined;
      this.receivedTitleUrlByTabId[normalizedTabId] = undefined;
    }
    this.currentDocumentUrlByTabId[normalizedTabId] = normalizedUrl;
  }

  resolveCurrentDocumentUrlForTitle(tabId: string): string {
    const normalizedTabId = tabId.trim();
    const recordedUrl = this.currentDocumentUrlByTabId[normalizedTabId]?.trim() ?? '';
    if (recordedUrl.length > 0) {
      return recordedUrl;
    }
    const tab = this.host.findTabById(normalizedTabId);
    if (tab !== undefined) {
      const pendingUrl = tab.pendingUrl.trim();
      if (pendingUrl.length > 0) {
        return pendingUrl;
      }
      const url = tab.url.trim();
      if (url.length > 0) {
        return url;
      }
    }
    return normalizedTabId === this.host.resolveActiveTabId() ? this.host.resolveCurrentUrl().trim() : '';
  }

  recordReceivedTitle(tabId: string, titleUrl: string, title: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedTitleUrl = titleUrl.trim();
    if (normalizedTabId.length <= 0 || normalizedTitleUrl.length <= 0) {
      return;
    }
    this.receivedTitleByTabId[normalizedTabId] = title;
    this.receivedTitleUrlByTabId[normalizedTabId] = normalizedTitleUrl;
  }

  resolveTitleForCommittedUrl(tabId: string, committedUrl: string): string {
    const normalizedTabId = tabId.trim();
    const normalizedCommittedUrl = committedUrl.trim();
    const tab = this.host.findTabById(normalizedTabId);
    if (tab === undefined) {
      return normalizedCommittedUrl;
    }
    const receivedTitle = this.receivedTitleByTabId[normalizedTabId]?.trim() ?? '';
    const receivedTitleUrl = this.receivedTitleUrlByTabId[normalizedTabId]?.trim() ?? '';
    if (receivedTitle.length > 0 &&
      receivedTitle !== WEB_TRANSIENT_LOADING_TITLE &&
      this.isSameNavigationTarget(receivedTitleUrl, normalizedCommittedUrl)) {
      return receivedTitle;
    }
    const currentTitle = tab.title.trim();
    const titleUrl = tab.url.trim();
    if (currentTitle.length > 0 &&
      this.isSameNavigationTarget(titleUrl, normalizedCommittedUrl) &&
      currentTitle !== WEB_TRANSIENT_LOADING_TITLE) {
      return currentTitle;
    }
    return normalizedCommittedUrl;
  }

  isTitleUrlCurrentForTab(tabId: string, titleUrl: string): boolean {
    const normalizedTabId = tabId.trim();
    const normalizedTitleUrl = titleUrl.trim();
    const tab = this.host.findTabById(normalizedTabId);
    const historyTargetIntentUrl = this.host.resolveHistoryTargetIntentUrl(normalizedTabId).trim();
    const pendingUrl = tab?.pendingUrl.trim() ?? '';
    const tabUrl = historyTargetIntentUrl.length > 0
      ? historyTargetIntentUrl
      : (pendingUrl.length > 0 ? pendingUrl : (tab?.url.trim() ?? ''));
    if (normalizedTitleUrl.length <= 0 || tabUrl.length <= 0) {
      return true;
    }
    return this.isSameNavigationTarget(normalizedTitleUrl, tabUrl);
  }

  applyCommittedUrlRestore(tabId: string, url: string): void {
    const restoredUrl = url.trim();
    if (restoredUrl.length <= 0) {
      return;
    }
    const title = this.resolveTitleForCommittedUrl(tabId, restoredUrl);
    this.host.applyTabPatch(tabId, {
      title: title,
      url: restoredUrl,
      pendingUrl: restoredUrl,
      isHome: false,
      runtimeState: 'active',
      lastError: ''
    }, true);
    this.host.rememberProvisionalNavigation(tabId, restoredUrl);
    this.recordCurrentDocumentUrl(tabId, restoredUrl);
    if (!this.host.isActiveWebTabVisible(tabId)) {
      return;
    }
    this.host.applyCommittedUrlRestoreState({
      currentUrl: restoredUrl,
      pendingWebUrl: restoredUrl,
      addressInput: this.host.resolveCommittedAddressDisplayText(restoredUrl),
      currentTitle: title
    });
    this.host.finishActivePageLoadingProgress();
  }

  applyHistoryTargetUrlPreview(
    tabId: string,
    direction: BrowserWebHistoryDirection,
    targetUrl: string
  ): void {
    const previewUrl = targetUrl.trim();
    if (previewUrl.length <= 0 || previewUrl === 'about:blank') {
      return;
    }
    if (!this.host.isActiveWebTabVisible(tabId)) {
      return;
    }
    this.host.applyHistoryTargetPreviewState({
      currentUrl: previewUrl,
      pendingWebUrl: previewUrl,
      addressInput: this.host.resolveCommittedAddressDisplayText(previewUrl)
    });
  }

  private scheduleScrollDeferredSync(): void {
    this.clearScrollDeferredTimer();
    this.pendingScrollDeferredNavigationStateTimer = setTimeout(() => {
      this.pendingScrollDeferredNavigationStateTimer = -1;
      if (this.host.shouldDeferNavigationStateForWebScroll()) {
        this.scheduleScrollDeferredSync();
        return;
      }
      this.sync(true);
    }, this.host.resolveWebScrollQuietDelayMs(this.scrollDeferredDelayMs));
  }

  private clearScrollDeferredTimer(): void {
    if (this.pendingScrollDeferredNavigationStateTimer < 0) {
      return;
    }
    clearTimeout(this.pendingScrollDeferredNavigationStateTimer);
    this.pendingScrollDeferredNavigationStateTimer = -1;
  }

  private applySnapshot(snapshot: BrowserWebPageStateSnapshot | undefined): void {
    if (snapshot !== undefined) {
      this.host.applyNavigationState(snapshot.canGoBackward, snapshot.canGoForward);
      return;
    }
    this.host.applyNavigationState(false, false);
  }

  private isSameNavigationTarget(left: string, right: string): boolean {
    const normalizedLeft = normalizeNavigationTarget(left);
    const normalizedRight = normalizeNavigationTarget(right);
    return normalizedLeft.length > 0 && normalizedLeft === normalizedRight;
  }
}
