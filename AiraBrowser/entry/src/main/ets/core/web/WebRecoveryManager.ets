import { TabRecord, TabRestoreReason } from '../../common/models/BrowserModels';
import { BrowserDownloadNavigationStateCoordinator } from '../browser/BrowserDownloadNavigationStateCoordinator';
import { BrowserTabState } from '../tabs/TabManager';

export interface WebRestoreRecoveryPlan {
  tabId: string;
  reason: TabRestoreReason;
  targetUrl: string;
  snapshotPath: string;
  attemptSnapshotRestore: boolean;
  helperMessage: string;
}

export interface WebColdRestoreResult {
  records: TabRecord[];
  skippedCount: number;
}

const SNAPSHOT_FAILURE_DEGRADE_THRESHOLD = 1;
const LOAD_FAILURE_HOME_THRESHOLD = 2;
const TRANSIENT_RESTORE_RETRY_LIMIT = 1;

export class WebRecoveryManager {
  private snapshotFailureCounts: Record<string, number> = {};
  private loadFailureCounts: Record<string, number> = {};
  private degradedReasons: Record<string, string> = {};
  private transientRestoreRetryCounts: Record<string, number> = {};
  private downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;

  constructor(downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator) {
    this.downloadNavigationStateCoordinator = downloadNavigationStateCoordinator;
  }

  sanitizeColdRestoreRecords(records: TabRecord[]): WebColdRestoreResult {
    const restoredRecords = records.filter((record: TabRecord) => this.canRestoreRecord(record));
    return {
      records: restoredRecords,
      skippedCount: records.length - restoredRecords.length
    };
  }

  buildRestorePlan(tab: BrowserTabState, reason: TabRestoreReason): WebRestoreRecoveryPlan {
    const snapshotFailureCount = this.snapshotFailureCounts[tab.id] ?? 0;
    const targetUrl = this.resolveTargetUrl(tab);
    const attemptSnapshotRestore = this.shouldAttemptSnapshotRestore(tab, reason, snapshotFailureCount);
    return {
      tabId: tab.id,
      reason: reason,
      targetUrl: targetUrl,
      snapshotPath: attemptSnapshotRestore ? tab.webStatePath : '',
      attemptSnapshotRestore: attemptSnapshotRestore,
      helperMessage: this.resolveHelperMessage(reason, attemptSnapshotRestore)
    };
  }

  recordSnapshotRestoreSuccess(tabId: string): void {
    this.snapshotFailureCounts[tabId] = 0;
    if ((this.loadFailureCounts[tabId] ?? 0) <= 0) {
      this.degradedReasons = this.removeKey(this.degradedReasons, tabId);
    }
  }

  recordSnapshotRestoreFailure(tabId: string): void {
    this.snapshotFailureCounts[tabId] = 0;
    if ((this.loadFailureCounts[tabId] ?? 0) <= 0) {
      this.degradedReasons = this.removeKey(this.degradedReasons, tabId);
    }
  }

  recordLoadSuccess(tabId: string): void {
    this.loadFailureCounts[tabId] = 0;
    this.transientRestoreRetryCounts[tabId] = 0;
    if ((this.snapshotFailureCounts[tabId] ?? 0) <= 0) {
      this.degradedReasons = this.removeKey(this.degradedReasons, tabId);
    }
  }

  recordLoadFailure(tabId: string, errorMessage: string): void {
    this.loadFailureCounts[tabId] = (this.loadFailureCounts[tabId] ?? 0) + 1;
    this.degradedReasons[tabId] = errorMessage.length > 0
      ? `页面恢复异常：${errorMessage}`
      : '页面恢复异常，等待重新加载。';
  }

  prepareUserRetry(tabId: string): void {
    if (tabId.length <= 0) {
      return;
    }
    this.loadFailureCounts[tabId] = 0;
    this.transientRestoreRetryCounts[tabId] = 0;
    this.degradedReasons[tabId] = '正在按用户操作重新加载页面。';
  }

  shouldAutoRetryTransientRestoreLoadFailure(tab: BrowserTabState | undefined, errorMessage: string): boolean {
    if (tab === undefined || tab.isHome) {
      return false;
    }
    if (!this.isTransientHttp2ProtocolError(errorMessage)) {
      return false;
    }
    if (!this.isRestoreRetryEligible(tab)) {
      return false;
    }
    return (this.transientRestoreRetryCounts[tab.id] ?? 0) < TRANSIENT_RESTORE_RETRY_LIMIT;
  }

  recordTransientRestoreRetry(tabId: string): number {
    const nextCount = (this.transientRestoreRetryCounts[tabId] ?? 0) + 1;
    this.transientRestoreRetryCounts[tabId] = nextCount;
    return nextCount;
  }

  resolveTransientRetryTargetUrl(tab: BrowserTabState): string {
    return this.resolveTargetUrl(tab);
  }

  shouldFallbackTabToHome(tabId: string): boolean {
    return (this.loadFailureCounts[tabId] ?? 0) >= LOAD_FAILURE_HOME_THRESHOLD;
  }

  shouldTreatLoadFailureAsRestoreFailure(tab: BrowserTabState | undefined): boolean {
    if (tab === undefined || tab.isHome) {
      return false;
    }
    return this.isRestoreRetryEligible(tab);
  }

  getDegradedReason(tabId: string): string {
    return this.degradedReasons[tabId] ?? '';
  }

  clearTab(tabId: string): void {
    this.snapshotFailureCounts = this.removeKey(this.snapshotFailureCounts, tabId);
    this.loadFailureCounts = this.removeKey(this.loadFailureCounts, tabId);
    this.degradedReasons = this.removeKey(this.degradedReasons, tabId);
    this.transientRestoreRetryCounts = this.removeKey(this.transientRestoreRetryCounts, tabId);
  }

  pruneTabs(tabIds: string[]): void {
    const allowed = new Set(tabIds);
    this.snapshotFailureCounts = this.filterRecord(this.snapshotFailureCounts, allowed);
    this.loadFailureCounts = this.filterRecord(this.loadFailureCounts, allowed);
    this.degradedReasons = this.filterRecord(this.degradedReasons, allowed);
    this.transientRestoreRetryCounts = this.filterRecord(this.transientRestoreRetryCounts, allowed);
  }

  private canRestoreRecord(record: TabRecord): boolean {
    if (record.isHome === true) {
      return true;
    }
    return this.resolveRecordTargetUrl(record).length > 0;
  }

  private resolveTargetUrl(tab: BrowserTabState): string {
    return this.normalizeTargetUrl(this.downloadNavigationStateCoordinator.resolveRestorableNavigation(tab).url);
  }

  private resolveRecordTargetUrl(record: TabRecord): string {
    return this.normalizeTargetUrl(
      this.downloadNavigationStateCoordinator.resolveRecordRestorableNavigation(record).url
    );
  }

  private normalizeTargetUrl(url: string): string {
    return url.trim();
  }

  private resolveHelperMessage(reason: TabRestoreReason, attemptSnapshotRestore: boolean): string {
    if (attemptSnapshotRestore) {
      return reason === 'controller_attach' ? '正在恢复标签页内容' : '正在切换标签页内容';
    }
    return '正在重新加载标签页';
  }

  private shouldAttemptSnapshotRestore(
    tab: BrowserTabState,
    reason: TabRestoreReason,
    snapshotFailureCount: number
  ): boolean {
    if (tab.webStatePath.length <= 0 || snapshotFailureCount >= SNAPSHOT_FAILURE_DEGRADE_THRESHOLD + 1) {
      return false;
    }
    if (reason !== 'tab_switch') {
      return true;
    }
    return tab.runtimeState === 'background-warm' ||
      tab.runtimeState === 'cold' ||
      tab.runtimeState === 'discarded' ||
      tab.runtimeState === 'crashed' ||
      tab.runtimeState === 'restoring' ||
      tab.runtimeState === 'suspended';
  }

  private isTransientHttp2ProtocolError(errorMessage: string): boolean {
    const normalized = errorMessage.trim().toUpperCase();
    return normalized.indexOf('ERR_HTTP2_PROTOCOL_ERROR') >= 0;
  }

  private isRestoreRetryEligible(tab: BrowserTabState): boolean {
    if (tab.runtimeState === 'restoring') {
      return true;
    }
    switch (tab.lastRestoreReason) {
      case 'cold_start':
      case 'controller_attach':
      case 'tab_switch':
      case 'discard_restore':
      case 'crash_restore':
      case 'snapshot_restore':
        return true;
      default:
        return false;
    }
  }

  private filterRecord<T>(source: Record<string, T>, allowed: Set<string>): Record<string, T> {
    const result: Record<string, T> = {};
    Object.keys(source).forEach((key: string) => {
      if (allowed.has(key)) {
        result[key] = source[key];
      }
    });
    return result;
  }

  private removeKey<T>(source: Record<string, T>, removedKey: string): Record<string, T> {
    const result: Record<string, T> = {};
    Object.keys(source).forEach((key: string) => {
      if (key !== removedKey) {
        result[key] = source[key];
      }
    });
    return result;
  }
}
