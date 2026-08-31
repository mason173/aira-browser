import { TabRecord } from '../../common/models/BrowserModels';
import {
  ArkBrowserNonRestorableNavigationGuardStore,
  BrowserNonRestorableNavigationGuardRecord,
  BrowserNonRestorableNavigationGuardStore
} from '../../data/browser/BrowserNonRestorableNavigationGuardStore';
import { BrowserTabRuntimePatch, BrowserTabState } from '../tabs/TabManager';
import {
  BrowserDownloadNavigationTransaction,
  BrowserDownloadNavigationTransactionCoordinator
} from './BrowserDownloadNavigationTransactionCoordinator';

export interface BrowserDownloadNavigationStateResetResult {
  shouldReset: boolean;
  patch?: BrowserTabRuntimePatch;
}

export interface BrowserDownloadNavigationRecordSanitizationResult {
  changed: boolean;
  record: TabRecord;
}

export interface BrowserDownloadNavigationRuntimeSanitizationPatch {
  currentUrl: string;
  pendingUrl: string;
  lastKnownUrl: string;
  snapshotPath: string;
  snapshotUpdatedAt: number;
}

export interface BrowserDownloadNavigationRuntimeSanitizationResult {
  shouldPatch: boolean;
  patch?: BrowserDownloadNavigationRuntimeSanitizationPatch;
}

export type BrowserDownloadNavigationReplayPhase = 'page_begin' | 'page_end';

export interface BrowserDownloadNavigationLifecycleHost {
  resolveTab: (tabId: string) => BrowserTabState | undefined;
  resolveActiveTab: () => BrowserTabState | undefined;
  resolveLastKnownUrl: (tabId: string) => string;
  applyTabPatch: (tabId: string, patch: BrowserTabRuntimePatch, persistTabs: boolean) => void;
  clearDownloadSnapshotForTab: (tab: BrowserTabState, reason: string) => void;
  applyActiveTabShellState: () => void;
  patchRuntimeNavigationState: (tabId: string, patch: BrowserDownloadNavigationRuntimeSanitizationPatch) => void;
  restoreWebViewToRestorableUrl: (tabId: string, skippedUrl: string, restoredUrl: string, reason: string) => void;
}

export interface BrowserRestorableNavigationResolution {
  url: string;
  title: string;
  source: string;
}

export interface BrowserVisibleDocumentNavigationPromotionResult {
  promoted: boolean;
  shouldContinue: boolean;
}

export interface BrowserInlineDocumentPromptResolution {
  shouldIgnore: boolean;
  shouldPreserveStableDocument: boolean;
}

export class BrowserDownloadNavigationStateCoordinator {
  private static readonly NON_RESTORABLE_GUARD_TTL_MS = 30 * 60 * 1000;
  private static readonly NON_RESTORABLE_GUARD_MAX_RECORDS = 80;
  private snapshotSuppressedTabs: Record<string, boolean | undefined> = {};
  private transientDownloadUrlsByTabId: Record<string, string | undefined> = {};
  private stableDocumentUrlsByTabId: Record<string, string | undefined> = {};
  private transactionCoordinator: BrowserDownloadNavigationTransactionCoordinator =
    new BrowserDownloadNavigationTransactionCoordinator();
  private guardStore: BrowserNonRestorableNavigationGuardStore;
  private guardRecords: BrowserNonRestorableNavigationGuardRecord[] = [];
  private guardRecordsLoaded: boolean = false;
  private guardRecordsLoadPromise?: Promise<void>;
  private lifecycleHost?: BrowserDownloadNavigationLifecycleHost;

  constructor(
    guardStore: BrowserNonRestorableNavigationGuardStore = new ArkBrowserNonRestorableNavigationGuardStore(),
    lifecycleHost?: BrowserDownloadNavigationLifecycleHost
  ) {
    this.guardStore = guardStore;
    this.lifecycleHost = lifecycleHost;
    void this.ensureGuardRecordsLoaded();
  }

  shouldSuppressNavigationReplay(tabId: string, url: string, phase: BrowserDownloadNavigationReplayPhase): boolean {
    if (!this.shouldSuppressNavigationCommitForTab(tabId, url)) {
      return false;
    }
    const lifecycleHost = this.lifecycleHost;
    if (lifecycleHost !== undefined) {
      const tab = lifecycleHost.resolveTab(tabId);
      const resetResult = this.buildResetPatch(
        tab,
        url,
        lifecycleHost.resolveLastKnownUrl(tabId)
      );
      if (resetResult.shouldReset && resetResult.patch !== undefined) {
        lifecycleHost.applyTabPatch(tabId, resetResult.patch, true);
        const restoredUrl = resetResult.patch.url ??
          resetResult.patch.lastRestorableUrl ??
          resetResult.patch.lastGoodUrl ??
          '';
        if (restoredUrl.length > 0) {
          lifecycleHost.restoreWebViewToRestorableUrl(tabId, url, restoredUrl, `download_navigation_${phase}`);
        }
      }
    }
    return true;
  }

  buildResetPatch(
    tab: BrowserTabState | undefined,
    downloadUrl: string,
    previousStableUrl: string = ''
  ): BrowserDownloadNavigationStateResetResult {
    if (tab === undefined || tab.isHome) {
      return { shouldReset: false };
    }
    const normalizedDownloadUrl = this.normalizeUrl(downloadUrl);
    if (normalizedDownloadUrl.length <= 0) {
      return { shouldReset: false };
    }

    const fallbackUrl = this.resolveFallbackUrl(tab, normalizedDownloadUrl, previousStableUrl);
    if (fallbackUrl.length <= 0) {
      return { shouldReset: false };
    }
    const normalizedTabUrl = this.normalizeUrl(tab.url);
    const normalizedPendingUrl = this.normalizeUrl(tab.pendingUrl);
    const normalizedFallbackUrl = this.normalizeUrl(fallbackUrl);
    if (normalizedFallbackUrl === normalizedTabUrl &&
      normalizedFallbackUrl === normalizedPendingUrl &&
      this.normalizeUrl(tab.lastGoodUrl) === normalizedFallbackUrl) {
      return { shouldReset: false };
    }
    const fallbackTitle = this.resolveFallbackTitle(tab, fallbackUrl);
    this.transactionCoordinator.beginPromptingTransaction({
      tab: tab,
      candidateUrl: downloadUrl,
      fallbackUrl: fallbackUrl,
      fallbackTitle: fallbackTitle
    });
    const filteredHistory = this.filterDownloadUrl(tab.navigationHistory, normalizedDownloadUrl, fallbackUrl);
    const filteredIndex = this.resolveFilteredIndex(filteredHistory, fallbackUrl);
    return {
      shouldReset: true,
      patch: {
        title: fallbackTitle,
        url: fallbackUrl,
        pendingUrl: fallbackUrl,
        navigationHistory: filteredHistory,
        navigationIndex: filteredIndex,
        lastGoodUrl: fallbackUrl,
        lastGoodTitle: fallbackTitle,
        lastRestorableUrl: fallbackUrl,
        lastRestorableTitle: fallbackTitle
      }
    };
  }

  markDownloadUrlHandled(downloadUrl: string): void {
    const normalizedDownloadUrl = this.normalizeUrl(downloadUrl);
    if (normalizedDownloadUrl.length <= 0) {
      return;
    }
    this.rememberNonRestorableNavigation(downloadUrl);
  }

  shouldIgnoreDownloadPromptForInlineDocument(
    url: string,
    mimeType: string = '',
    contentDisposition: string = ''
  ): boolean {
    if (this.isAttachmentDisposition(contentDisposition)) {
      return false;
    }
    const normalizedMimeType = this.normalizeMimeType(mimeType);
    if (normalizedMimeType === 'application/pdf') {
      return true;
    }
    return this.isPdfUrl(url);
  }

  shouldIgnorePromptForInlineDocument(
    url: string,
    mimeType: string = '',
    contentDisposition: string = '',
    visibleTabId: string = ''
  ): boolean {
    return this.resolveInlineDocumentPrompt(
      url,
      mimeType,
      contentDisposition,
      visibleTabId
    ).shouldIgnore;
  }

  resolveInlineDocumentPrompt(
    url: string,
    mimeType: string = '',
    contentDisposition: string = '',
    visibleTabId: string = ''
  ): BrowserInlineDocumentPromptResolution {
    if (!this.shouldIgnoreDownloadPromptForInlineDocument(url, mimeType, contentDisposition)) {
      return {
        shouldIgnore: false,
        shouldPreserveStableDocument: false
      };
    }
    const shouldPreserveStableDocument = this.isStableDocumentVisible(visibleTabId, url);
    return {
      shouldIgnore: !shouldPreserveStableDocument,
      shouldPreserveStableDocument: shouldPreserveStableDocument
    };
  }

  markDocumentNavigationStarted(tabId: string, url: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedUrl = this.normalizeUrl(url);
    if (normalizedTabId.length <= 0 || normalizedUrl.length <= 0) {
      return;
    }
    this.stableDocumentUrlsByTabId[normalizedTabId] = undefined;
  }

  markTabDownloadTransient(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    this.snapshotSuppressedTabs[normalizedTabId] = true;
  }

  markTabDownloadNavigation(tabId: string, downloadUrl: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedDownloadUrl = this.normalizeUrl(downloadUrl);
    if (normalizedTabId.length <= 0 || normalizedDownloadUrl.length <= 0) {
      return;
    }
    this.markTabDownloadTransient(normalizedTabId);
    this.transientDownloadUrlsByTabId[normalizedTabId] = normalizedDownloadUrl;
    this.rememberNonRestorableNavigation(downloadUrl);
    this.transactionCoordinator.markDownloadDetected(normalizedTabId, normalizedDownloadUrl);
  }

  shouldSkipSnapshotPersistence(tabId: string): boolean {
    const normalizedTabId = tabId.trim();
    return this.snapshotSuppressedTabs[normalizedTabId] === true ||
      this.transactionCoordinator.shouldSkipSnapshotPersistence(normalizedTabId);
  }

  shouldSkipTabStatePersistence(tabId: string, url: string, source: string = ''): boolean {
    const normalizedTabId = tabId.trim();
    const normalizedUrl = this.normalizeUrl(url);
    if (normalizedTabId.length <= 0 || normalizedUrl.length <= 0) {
      return false;
    }
    if (this.shouldSuppressNavigationCommitForTab(normalizedTabId, normalizedUrl)) {
      return true;
    }
    const shouldSkip = this.transientDownloadUrlsByTabId[normalizedTabId] === normalizedUrl;
    return shouldSkip;
  }

  shouldBlockRuntimeNavigationCommit(tabId: string, url: string): boolean {
    return this.shouldSkipTabStatePersistence(tabId, url);
  }

  shouldTreatAsNonRestorableNavigation(url: string): boolean {
    return this.shouldSuppressNavigationCommit(url) || this.hasNonRestorableGuard(url);
  }

  markStableNavigationCommitted(tabId: string, url: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0 || this.shouldSuppressNavigationCommitForTab(normalizedTabId, url)) {
      return;
    }
    const normalizedUrl = this.normalizeUrl(url);
    this.stableDocumentUrlsByTabId[normalizedTabId] = normalizedUrl;
    if (this.transientDownloadUrlsByTabId[normalizedTabId] === normalizedUrl) {
      return;
    }
    this.transactionCoordinator.markStableDocumentPromoted(normalizedTabId, url);
    this.snapshotSuppressedTabs[normalizedTabId] = undefined;
    this.transientDownloadUrlsByTabId[normalizedTabId] = undefined;
  }

  markVisibleDocumentNavigationCommitted(tabId: string, url: string): boolean {
    const normalizedTabId = tabId.trim();
    const normalizedUrl = this.normalizeUrl(url);
    if (normalizedTabId.length <= 0 || normalizedUrl.length <= 0) {
      return false;
    }
    const wasSuppressed = this.shouldSuppressNavigationCommitForTab(normalizedTabId, normalizedUrl);
    const wasGuarded = this.hasNonRestorableGuard(normalizedUrl);
    const wasTransient = this.transientDownloadUrlsByTabId[normalizedTabId] === normalizedUrl;
    if (!wasSuppressed && !wasGuarded && !wasTransient) {
      return false;
    }
    this.transactionCoordinator.markCandidateDocumentPromoted(normalizedTabId, normalizedUrl);
    this.snapshotSuppressedTabs[normalizedTabId] = undefined;
    if (wasTransient) {
      this.transientDownloadUrlsByTabId[normalizedTabId] = undefined;
    }
    this.forgetNonRestorableNavigation(normalizedUrl);
    return true;
  }

  resolveVisibleDocumentNavigationPromotion(
    tabId: string,
    url: string
  ): BrowserVisibleDocumentNavigationPromotionResult {
    const promoted = this.markVisibleDocumentNavigationCommitted(tabId, url);
    return {
      promoted: promoted,
      shouldContinue: !this.shouldTreatAsNonRestorableNavigation(url)
    };
  }

  resolveInlineDocumentNavigationPromotion(
    tabId: string,
    url: string,
    mimeType: string = '',
    contentDisposition: string = ''
  ): BrowserVisibleDocumentNavigationPromotionResult {
    if (!this.shouldIgnoreDownloadPromptForInlineDocument(url, mimeType, contentDisposition)) {
      return {
        promoted: false,
        shouldContinue: !this.shouldTreatAsNonRestorableNavigation(url)
      };
    }
    const promoted = this.markVisibleDocumentNavigationCommitted(tabId, url);
    return {
      promoted: promoted,
      shouldContinue: !this.shouldTreatAsNonRestorableNavigation(url)
    };
  }

  markDownloadNavigationRestored(tabId: string, downloadUrl: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedDownloadUrl = this.normalizeUrl(downloadUrl);
    if (normalizedTabId.length <= 0 || normalizedDownloadUrl.length <= 0) {
      return;
    }
    this.transactionCoordinator.markRestored(normalizedTabId, normalizedDownloadUrl);
    this.snapshotSuppressedTabs[normalizedTabId] = undefined;
    if (this.transientDownloadUrlsByTabId[normalizedTabId] === normalizedDownloadUrl) {
      this.transientDownloadUrlsByTabId[normalizedTabId] = undefined;
    }
  }

  markDownloadNavigationCanceled(tabId: string, downloadUrl: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedDownloadUrl = this.normalizeUrl(downloadUrl);
    if (normalizedTabId.length <= 0 || normalizedDownloadUrl.length <= 0) {
      return;
    }
    this.transactionCoordinator.markCanceled(normalizedTabId, normalizedDownloadUrl);
    this.snapshotSuppressedTabs[normalizedTabId] = undefined;
    if (this.transientDownloadUrlsByTabId[normalizedTabId] === normalizedDownloadUrl) {
      this.transientDownloadUrlsByTabId[normalizedTabId] = undefined;
    }
  }

  markDownloadNavigationConfirmed(tabId: string, downloadUrl: string, downloadGuid: string = ''): void {
    const normalizedTabId = tabId.trim();
    const normalizedDownloadUrl = this.normalizeUrl(downloadUrl);
    if (normalizedTabId.length <= 0 || normalizedDownloadUrl.length <= 0) {
      return;
    }
    this.transactionCoordinator.markConfirmed(normalizedTabId, normalizedDownloadUrl, downloadGuid);
  }

  resetPromptNavigationState(promptUrl: string): void {
    const lifecycleHost = this.lifecycleHost;
    if (lifecycleHost === undefined) {
      return;
    }
    const activeTab = lifecycleHost.resolveActiveTab();
    const resetResult = this.buildResetPatch(
      activeTab,
      promptUrl,
      activeTab !== undefined ? lifecycleHost.resolveLastKnownUrl(activeTab.id) : ''
    );
    if (activeTab === undefined) {
      return;
    }
    this.markTabDownloadNavigation(activeTab.id, promptUrl);
    this.sanitizeRuntimeNavigationState(activeTab.id, promptUrl, 'download_prompt');
    lifecycleHost.clearDownloadSnapshotForTab(activeTab, 'download_prompt');
    const resetPatch = this.buildPromptResetPatch(resetResult.patch);
    lifecycleHost.applyTabPatch(activeTab.id, resetPatch, true);
    lifecycleHost.applyActiveTabShellState();
    const restoredUrl = resetPatch.url ?? resetPatch.lastRestorableUrl ?? resetPatch.lastGoodUrl ?? '';
    if (restoredUrl.length > 0) {
      lifecycleHost.restoreWebViewToRestorableUrl(activeTab.id, promptUrl, restoredUrl, 'download_prompt');
    }
  }

  sanitizeRuntimeNavigationState(tabId: string, downloadUrl: string, source: string): void {
    const lifecycleHost = this.lifecycleHost;
    if (lifecycleHost === undefined) {
      return;
    }
    const sanitization = this.buildRuntimeSanitizationPatch(tabId, downloadUrl);
    if (!sanitization.shouldPatch || sanitization.patch === undefined) {
      return;
    }
    lifecycleHost.patchRuntimeNavigationState(tabId, sanitization.patch);
  }

  getActiveTransaction(tabId: string): BrowserDownloadNavigationTransaction | undefined {
    return this.transactionCoordinator.getActiveTransaction(tabId.trim());
  }

  buildRuntimeSanitizationPatch(
    tabId: string,
    downloadUrl: string
  ): BrowserDownloadNavigationRuntimeSanitizationResult {
    const transaction = this.transactionCoordinator.lookupByTabAndUrl(tabId, downloadUrl).transaction ??
      this.transactionCoordinator.getActiveTransaction(tabId);
    if (transaction === undefined || transaction.previousRestorableUrl.trim().length <= 0) {
      return {
        shouldPatch: false
      };
    }
    return {
      shouldPatch: true,
      patch: {
        currentUrl: transaction.previousRestorableUrl,
        pendingUrl: transaction.previousRestorableUrl,
        lastKnownUrl: transaction.previousRestorableUrl,
        snapshotPath: transaction.previousSnapshotPath,
        snapshotUpdatedAt: 0
      }
    };
  }

  shouldSuppressNavigationCommitForTab(tabId: string, url: string): boolean {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return this.shouldSuppressNavigationCommit(url);
    }
    return this.transactionCoordinator.shouldSuppressNavigation(normalizedTabId, url) ||
      this.transientDownloadUrlsByTabId[normalizedTabId] === this.normalizeUrl(url);
  }

  shouldSuppressNavigationCommit(url: string): boolean {
    return this.transactionCoordinator.shouldSuppressUrl(url);
  }

  resolveRestoreTarget(
    lastGoodUrl: string,
    preferredUrl: string,
    fallbackUrl: string
  ): string {
    if (lastGoodUrl.trim().length > 0 && !this.shouldTreatAsNonRestorableNavigation(lastGoodUrl)) {
      return lastGoodUrl.trim();
    }
    if (preferredUrl.trim().length > 0 && !this.shouldTreatAsNonRestorableNavigation(preferredUrl)) {
      return preferredUrl.trim();
    }
    if (fallbackUrl.trim().length > 0 && !this.shouldTreatAsNonRestorableNavigation(fallbackUrl)) {
      return fallbackUrl.trim();
    }
    return '';
  }

  resolveRestorableNavigation(tab: BrowserTabState): BrowserRestorableNavigationResolution {
    const mobileSubdomainUrl = this.resolveMobileSubdomainRestoreAnchor([
      tab.pendingUrl,
      tab.url,
      this.resolveLatestHistoryCandidate(tab.navigationHistory, tab.navigationIndex)
    ]);
    const candidates: BrowserRestorableNavigationResolution[] = [
      {
        url: tab.lastRestorableUrl,
        title: tab.lastRestorableTitle,
        source: 'last_restorable_state'
      },
      {
        url: tab.lastGoodUrl,
        title: tab.lastGoodTitle,
        source: 'last_good_state'
      },
      {
        url: this.resolveLatestHistoryCandidate(tab.navigationHistory, tab.navigationIndex),
        title: tab.title,
        source: 'navigation_history'
      },
      {
        url: tab.pendingUrl,
        title: tab.title,
        source: 'pending_url'
      },
      {
        url: tab.url,
        title: tab.title,
        source: 'tab_url'
      }
    ];
    return this.resolveFirstRestorableCandidate(candidates, mobileSubdomainUrl);
  }

  resolveTabSwitchNavigation(tab: BrowserTabState): BrowserRestorableNavigationResolution {
    const candidates: BrowserRestorableNavigationResolution[] = [
      {
        url: tab.pendingUrl,
        title: tab.title,
        source: 'pending_url'
      },
      {
        url: tab.url,
        title: tab.title,
        source: 'tab_url'
      },
      {
        url: this.resolveLatestHistoryCandidate(tab.navigationHistory, tab.navigationIndex),
        title: tab.title,
        source: 'navigation_history'
      },
      {
        url: tab.lastRestorableUrl,
        title: tab.lastRestorableTitle,
        source: 'last_restorable_state'
      },
      {
        url: tab.lastGoodUrl,
        title: tab.lastGoodTitle,
        source: 'last_good_state'
      }
    ];
    return this.resolveFirstRestorableCandidate(candidates);
  }

  resolveRecordRestorableNavigation(record: TabRecord): BrowserRestorableNavigationResolution {
    const mobileSubdomainUrl = this.resolveMobileSubdomainRestoreAnchor([
      record.pendingUrl ?? '',
      record.url,
      this.resolveLatestHistoryCandidate(record.navigationHistory ?? [], record.navigationIndex ?? -1)
    ]);
    const candidates: BrowserRestorableNavigationResolution[] = [
      {
        url: record.lastRestorableUrl ?? '',
        title: record.lastRestorableTitle ?? '',
        source: 'last_restorable_state'
      },
      {
        url: record.lastGoodUrl ?? '',
        title: record.lastGoodTitle ?? '',
        source: 'last_good_state'
      },
      {
        url: this.resolveLatestHistoryCandidate(record.navigationHistory ?? [], record.navigationIndex ?? -1),
        title: record.title,
        source: 'navigation_history'
      },
      {
        url: record.pendingUrl ?? '',
        title: record.title,
        source: 'pending_url'
      },
      {
        url: record.url,
        title: record.title,
        source: 'tab_url'
      }
    ];
    return this.resolveFirstRestorableCandidate(candidates, mobileSubdomainUrl);
  }

  sanitizePersistedRecord(record: TabRecord): BrowserDownloadNavigationRecordSanitizationResult {
    if (record.isHome === true) {
      return {
        changed: false,
        record: record
      };
    }
    const resolution = this.resolveRecordRestorableNavigation(record);
    const targetUrl = resolution.url;
    if (targetUrl.length <= 0) {
      return {
        changed: false,
        record: record
      };
    }
    const nextHistory = (record.navigationHistory ?? [])
      .filter((item: string) => !this.shouldTreatAsNonRestorableNavigation(item));
    if (nextHistory.length <= 0) {
      nextHistory.push(targetUrl);
    }
    const nextIndex = this.resolveFilteredIndex(nextHistory, targetUrl);
    const nextLastGoodUrl = this.shouldTreatAsNonRestorableNavigation(record.lastGoodUrl ?? '')
      ? targetUrl
      : ((record.lastGoodUrl ?? '').trim().length > 0 ? (record.lastGoodUrl ?? '').trim() : targetUrl);
    const nextRecord: TabRecord = {
      id: record.id,
      windowId: record.windowId,
      profileId: record.profileId,
      title: record.title,
      url: targetUrl,
      isActive: record.isActive,
      isPinned: record.isPinned,
      lastActiveAt: record.lastActiveAt,
      tabOrder: record.tabOrder,
      isHome: record.isHome,
      pendingUrl: targetUrl,
      navigationHistory: nextHistory,
      navigationIndex: nextIndex,
      runtimeState: record.runtimeState,
      lastError: record.lastError,
      lastRestoreReason: record.lastRestoreReason,
      lastDiscardReason: record.lastDiscardReason,
      lastCrashReason: record.lastCrashReason,
      lastLoadedAt: record.lastLoadedAt,
      webStatePath: record.webStatePath,
      webStateUpdatedAt: record.webStateUpdatedAt,
      scrollOffsetY: record.scrollOffsetY,
      lastGoodUrl: nextLastGoodUrl,
      lastGoodTitle: (record.lastGoodTitle ?? '').trim().length > 0 ? record.lastGoodTitle : record.title,
      lastRestorableUrl: this.resolveNextRestorableUrl(record, targetUrl),
      lastRestorableTitle: this.resolveNextRestorableTitle(record, targetUrl),
      lastRestoreType: record.lastRestoreType,
      privacyMode: record.privacyMode,
      dataScope: record.dataScope,
      launchSourceType: record.launchSourceType,
      launchSourceId: record.launchSourceId,
      launchSourceUrl: record.launchSourceUrl,
      launchKey: record.launchKey
    };
    const changed = this.normalizeUrl(record.url) !== this.normalizeUrl(nextRecord.url) ||
      this.normalizeUrl(record.pendingUrl ?? '') !== this.normalizeUrl(nextRecord.pendingUrl ?? '') ||
      this.normalizeUrl(record.lastGoodUrl ?? '') !== this.normalizeUrl(nextRecord.lastGoodUrl ?? '') ||
      this.normalizeUrl(record.lastRestorableUrl ?? '') !== this.normalizeUrl(nextRecord.lastRestorableUrl ?? '') ||
      (record.navigationHistory ?? []).length !== nextRecord.navigationHistory!.length ||
      (record.navigationIndex ?? -1) !== nextRecord.navigationIndex;
    return {
      changed: changed,
      record: nextRecord
    };
  }

  async loadNonRestorableNavigationGuards(): Promise<void> {
    await this.ensureGuardRecordsLoaded();
  }

  private resolveFallbackUrl(
    tab: BrowserTabState,
    normalizedDownloadUrl: string,
    previousStableUrl: string
  ): string {
    const normalizedPreviousStableUrl = this.normalizeUrl(previousStableUrl);
    if (normalizedPreviousStableUrl.length > 0 && normalizedPreviousStableUrl !== normalizedDownloadUrl) {
      return previousStableUrl.trim();
    }
    const lastRestorableUrl = tab.lastRestorableUrl.trim();
    if (this.normalizeUrl(lastRestorableUrl).length > 0 &&
      this.normalizeUrl(lastRestorableUrl) !== normalizedDownloadUrl) {
      return lastRestorableUrl;
    }
    const lastGoodUrl = tab.lastGoodUrl.trim();
    if (this.normalizeUrl(lastGoodUrl).length > 0 && this.normalizeUrl(lastGoodUrl) !== normalizedDownloadUrl) {
      return lastGoodUrl;
    }
    for (let index = tab.navigationHistory.length - 1; index >= 0; index -= 1) {
      const candidate = tab.navigationHistory[index].trim();
      if (candidate.length > 0 && this.normalizeUrl(candidate) !== normalizedDownloadUrl) {
        return candidate;
      }
    }
    if (tab.url.trim().length > 0 && this.normalizeUrl(tab.url) !== normalizedDownloadUrl) {
      return tab.url.trim();
    }
    if (tab.pendingUrl.trim().length > 0 && this.normalizeUrl(tab.pendingUrl) !== normalizedDownloadUrl) {
      return tab.pendingUrl.trim();
    }
    return '';
  }

  private buildPromptResetPatch(sourcePatch: BrowserTabRuntimePatch | undefined): BrowserTabRuntimePatch {
    return {
      profileId: sourcePatch?.profileId,
      title: sourcePatch?.title,
      url: sourcePatch?.url,
      isHome: sourcePatch?.isHome,
      lastActiveAt: sourcePatch?.lastActiveAt,
      pendingUrl: sourcePatch?.pendingUrl,
      navigationHistory: sourcePatch?.navigationHistory,
      navigationIndex: sourcePatch?.navigationIndex,
      runtimeState: sourcePatch?.runtimeState,
      lastError: sourcePatch?.lastError,
      lastRestoreReason: sourcePatch?.lastRestoreReason,
      lastDiscardReason: sourcePatch?.lastDiscardReason,
      lastCrashReason: sourcePatch?.lastCrashReason,
      lastLoadedAt: sourcePatch?.lastLoadedAt,
      webStatePath: '',
      webStateUpdatedAt: 0,
      scrollOffsetY: sourcePatch?.scrollOffsetY,
      lastGoodUrl: sourcePatch?.lastGoodUrl,
      lastGoodTitle: sourcePatch?.lastGoodTitle,
      lastRestorableUrl: sourcePatch?.lastRestorableUrl,
      lastRestorableTitle: sourcePatch?.lastRestorableTitle,
      lastRestoreType: sourcePatch?.lastRestoreType,
      privacyMode: sourcePatch?.privacyMode,
      dataScope: sourcePatch?.dataScope,
      launchContext: sourcePatch?.launchContext
    };
  }

  private rememberNonRestorableNavigation(downloadUrl: string, fallbackUrl: string = ''): void {
    const sourceKey = this.normalizeUrl(downloadUrl);
    if (sourceKey.length <= 0) {
      return;
    }
    const nextRecord: BrowserNonRestorableNavigationGuardRecord = {
      sourceKey: sourceKey,
      decision: 'download_candidate',
      fallbackUrl: fallbackUrl.trim(),
      updatedAt: Date.now()
    };
    this.guardRecords = [nextRecord]
      .concat(this.guardRecords.filter((record: BrowserNonRestorableNavigationGuardRecord) => {
        return record.sourceKey !== sourceKey;
      }));
    this.guardRecords = this.pruneGuardRecords(this.guardRecords);
    void this.persistGuardRecords();
  }

  private forgetNonRestorableNavigation(url: string): void {
    const sourceKey = this.normalizeUrl(url);
    if (sourceKey.length <= 0) {
      return;
    }
    const nextRecords = this.guardRecords.filter((record: BrowserNonRestorableNavigationGuardRecord) => {
      return record.sourceKey !== sourceKey;
    });
    if (nextRecords.length !== this.guardRecords.length) {
      this.guardRecords = nextRecords;
      void this.persistGuardRecords();
    }
    if (this.guardRecordsLoaded) {
      return;
    }
    void this.ensureGuardRecordsLoaded().then(() => {
      const loadedRecords = this.guardRecords.filter((record: BrowserNonRestorableNavigationGuardRecord) => {
        return record.sourceKey !== sourceKey;
      });
      if (loadedRecords.length === this.guardRecords.length) {
        return;
      }
      this.guardRecords = loadedRecords;
      void this.persistGuardRecords();
    });
  }

  private hasNonRestorableGuard(url: string): boolean {
    const sourceKey = this.normalizeUrl(url);
    if (sourceKey.length <= 0) {
      return false;
    }
    if (!this.guardRecordsLoaded) {
      void this.ensureGuardRecordsLoaded();
    }
    this.guardRecords = this.pruneGuardRecords(this.guardRecords);
    return this.guardRecords.some((record: BrowserNonRestorableNavigationGuardRecord) => {
      return record.sourceKey === sourceKey;
    });
  }

  private async ensureGuardRecordsLoaded(): Promise<void> {
    if (this.guardRecordsLoaded) {
      return;
    }
    if (this.guardRecordsLoadPromise === undefined) {
      this.guardRecordsLoadPromise = this.guardStore.loadRecords()
        .then((records: BrowserNonRestorableNavigationGuardRecord[]) => {
          const pendingRecords = this.guardRecords.slice();
          const loadedRecords = this.pruneGuardRecords(records);
          const loadedWithoutPending = loadedRecords.filter((loaded: BrowserNonRestorableNavigationGuardRecord) => {
            return !pendingRecords.some((pending: BrowserNonRestorableNavigationGuardRecord) => {
              return pending.sourceKey === loaded.sourceKey;
            });
          });
          this.guardRecords = this.pruneGuardRecords(pendingRecords.concat(loadedWithoutPending));
          this.guardRecordsLoaded = true;
        })
        .catch(() => {
          this.guardRecords = [];
          this.guardRecordsLoaded = true;
        });
    }
    await this.guardRecordsLoadPromise;
  }

  private async persistGuardRecords(): Promise<void> {
    try {
      await this.ensureGuardRecordsLoaded();
      await this.guardStore.saveRecords(this.guardRecords);
    } catch {
    }
  }

  private pruneGuardRecords(
    records: BrowserNonRestorableNavigationGuardRecord[]
  ): BrowserNonRestorableNavigationGuardRecord[] {
    const deadline = Date.now() - BrowserDownloadNavigationStateCoordinator.NON_RESTORABLE_GUARD_TTL_MS;
    return records
      .filter((record: BrowserNonRestorableNavigationGuardRecord) => {
        return record.sourceKey.trim().length > 0 &&
          record.decision === 'download_candidate' &&
          record.updatedAt >= deadline;
      })
      .sort((left: BrowserNonRestorableNavigationGuardRecord, right: BrowserNonRestorableNavigationGuardRecord) => {
        return right.updatedAt - left.updatedAt;
      })
      .slice(0, BrowserDownloadNavigationStateCoordinator.NON_RESTORABLE_GUARD_MAX_RECORDS);
  }

  private resolveFirstRestorableCandidate(
    candidates: BrowserRestorableNavigationResolution[],
    mobileSubdomainUrl: string = ''
  ): BrowserRestorableNavigationResolution {
    for (const candidate of candidates) {
      const url = candidate.url.trim();
      if (url.length <= 0 || this.isInternalUrl(url) || this.shouldTreatAsNonRestorableNavigation(url)) {
        continue;
      }
      if (this.shouldDeferDesktopSiblingForMobileAnchor(url, mobileSubdomainUrl)) {
        continue;
      }
      return {
        url: url,
        title: candidate.title.trim(),
        source: candidate.source
      };
    }
    return {
      url: '',
      title: '',
      source: ''
    };
  }

  private resolveLatestHistoryCandidate(history: string[], navigationIndex: number): string {
    if (history.length <= 0) {
      return '';
    }
    const startIndex = navigationIndex >= 0 && navigationIndex < history.length ? navigationIndex : history.length - 1;
    for (let index = startIndex; index >= 0; index -= 1) {
      const candidate = history[index].trim();
      if (candidate.length > 0) {
        return candidate;
      }
    }
    for (let index = history.length - 1; index > startIndex; index -= 1) {
      const candidate = history[index].trim();
      if (candidate.length > 0) {
        return candidate;
      }
    }
    return '';
  }

  private resolveMobileSubdomainRestoreAnchor(urls: string[]): string {
    for (const url of urls) {
      const normalizedUrl = url.trim();
      if (normalizedUrl.length > 0 && this.isMobileSubdomainHost(this.extractHost(normalizedUrl))) {
        return normalizedUrl;
      }
    }
    return '';
  }

  private shouldDeferDesktopSiblingForMobileAnchor(candidateUrl: string, mobileSubdomainUrl: string): boolean {
    const mobileHost = this.extractHost(mobileSubdomainUrl);
    if (!this.isMobileSubdomainHost(mobileHost)) {
      return false;
    }
    const candidateHost = this.extractHost(candidateUrl);
    if (candidateHost.length <= 0 || candidateHost === mobileHost) {
      return false;
    }
    const mobileParentHost = this.resolveParentHost(mobileHost);
    if (mobileParentHost.length <= 0) {
      return false;
    }
    return candidateHost === mobileParentHost || candidateHost === `www.${mobileParentHost}`;
  }

  private isMobileSubdomainHost(host: string): boolean {
    const labels = host.trim().toLowerCase().split('.');
    if (labels.length < 3) {
      return false;
    }
    const firstLabel = labels[0];
    return firstLabel === 'm' || firstLabel === 'mobile' || firstLabel === 'touch' ||
      firstLabel === 'wap' || firstLabel === '3g';
  }

  private resolveParentHost(host: string): string {
    const labels = host.trim().toLowerCase().split('.');
    if (labels.length < 3) {
      return '';
    }
    return labels.slice(1).join('.');
  }

  private resolveFallbackTitle(tab: BrowserTabState, fallbackUrl: string): string {
    const lastRestorableUrl = tab.lastRestorableUrl.trim();
    if (lastRestorableUrl.length > 0 && this.normalizeUrl(lastRestorableUrl) === this.normalizeUrl(fallbackUrl)) {
      const lastRestorableTitle = tab.lastRestorableTitle.trim();
      if (lastRestorableTitle.length > 0) {
        return lastRestorableTitle;
      }
    }
    const lastGoodUrl = tab.lastGoodUrl.trim();
    if (lastGoodUrl.length > 0 && this.normalizeUrl(lastGoodUrl) === this.normalizeUrl(fallbackUrl)) {
      const lastGoodTitle = tab.lastGoodTitle.trim();
      if (lastGoodTitle.length > 0) {
        return lastGoodTitle;
      }
    }
    const currentTitle = tab.title.trim();
    return currentTitle.length > 0 ? currentTitle : fallbackUrl;
  }

  private filterDownloadUrl(history: string[], normalizedDownloadUrl: string, fallbackUrl: string): string[] {
    const filtered = history.filter((item: string) => this.normalizeUrl(item) !== normalizedDownloadUrl);
    if (filtered.length <= 0) {
      return [fallbackUrl];
    }
    const normalizedFallbackUrl = this.normalizeUrl(fallbackUrl);
    if (filtered.some((item: string) => this.normalizeUrl(item) === normalizedFallbackUrl)) {
      return filtered;
    }
    return filtered.concat([fallbackUrl]);
  }

  private resolveFilteredIndex(history: string[], fallbackUrl: string): number {
    const normalizedFallbackUrl = this.normalizeUrl(fallbackUrl);
    for (let index = history.length - 1; index >= 0; index -= 1) {
      if (this.normalizeUrl(history[index]) === normalizedFallbackUrl) {
        return index;
      }
    }
    return history.length - 1;
  }

  private resolveNextRestorableUrl(record: TabRecord, targetUrl: string): string {
    const currentRestorableUrl = (record.lastRestorableUrl ?? '').trim();
    if (currentRestorableUrl.length > 0 && !this.shouldTreatAsNonRestorableNavigation(currentRestorableUrl)) {
      return currentRestorableUrl;
    }
    const lastGoodUrl = (record.lastGoodUrl ?? '').trim();
    if (lastGoodUrl.length > 0 && !this.shouldTreatAsNonRestorableNavigation(lastGoodUrl)) {
      return lastGoodUrl;
    }
    return targetUrl;
  }

  private resolveNextRestorableTitle(record: TabRecord, targetUrl: string): string {
    const restorableTitle = (record.lastRestorableTitle ?? '').trim();
    if (restorableTitle.length > 0) {
      return restorableTitle;
    }
    const lastGoodTitle = (record.lastGoodTitle ?? '').trim();
    if (lastGoodTitle.length > 0) {
      return lastGoodTitle;
    }
    const title = record.title.trim();
    return title.length > 0 ? title : targetUrl;
  }

  private isInternalUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('aira://') || normalized.startsWith('about:') || normalized.startsWith('data:');
  }

  private extractHost(url: string): string {
    const trimmedUrl = url.trim();
    if (trimmedUrl.length <= 0) {
      return '';
    }
    const schemeSeparatorIndex = trimmedUrl.indexOf('://');
    if (schemeSeparatorIndex < 0) {
      return '';
    }
    const authorityStart = schemeSeparatorIndex + 3;
    const slashIndex = trimmedUrl.indexOf('/', authorityStart);
    const authority = (slashIndex >= 0 ? trimmedUrl.slice(authorityStart, slashIndex) : trimmedUrl.slice(authorityStart))
      .split('@')
      .pop() ?? '';
    return authority.split(':')[0].trim().toLowerCase();
  }

  private normalizeUrl(url: string): string {
    const trimmed = url.trim().toLowerCase();
    if (trimmed.length <= 0) {
      return '';
    }
    const hashIndex = trimmed.indexOf('#');
    const withoutHash = hashIndex >= 0 ? trimmed.substring(0, hashIndex) : trimmed;
    return withoutHash.endsWith('/') ? withoutHash.substring(0, withoutHash.length - 1) : withoutHash;
  }

  private isPdfUrl(url: string): boolean {
    const normalizedUrl = this.normalizeUrl(url);
    if (normalizedUrl.length <= 0) {
      return false;
    }
    const queryIndex = normalizedUrl.indexOf('?');
    const withoutQuery = queryIndex >= 0 ? normalizedUrl.substring(0, queryIndex) : normalizedUrl;
    return withoutQuery.endsWith('.pdf');
  }

  private isAttachmentDisposition(contentDisposition: string): boolean {
    return contentDisposition.trim().toLowerCase().indexOf('attachment') >= 0;
  }

  private normalizeMimeType(mimeType: string): string {
    const separatorIndex = mimeType.indexOf(';');
    const raw = separatorIndex >= 0 ? mimeType.substring(0, separatorIndex) : mimeType;
    return raw.trim().toLowerCase();
  }

  private isStableDocumentVisible(tabId: string, url: string): boolean {
    const normalizedTabId = tabId.trim();
    const normalizedUrl = this.normalizeUrl(url);
    if (normalizedTabId.length <= 0 || normalizedUrl.length <= 0) {
      return false;
    }
    return this.stableDocumentUrlsByTabId[normalizedTabId] === normalizedUrl;
  }
}
