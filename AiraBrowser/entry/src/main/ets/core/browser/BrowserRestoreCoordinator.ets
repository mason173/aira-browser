import {
  TabRecord,
  TabRestoreReason,
  TabRuntimeState,
  WebSessionRestoreType
} from '../../common/models/BrowserModels';
import { BrowserTabRuntimePatch, BrowserTabState } from '../tabs/TabManager';
import { WebRecoveryManager, WebRestoreRecoveryPlan } from '../web/WebRecoveryManager';
import { WebSessionStateStore } from '../web/WebSessionStateStore';
import { BrowserDownloadNavigationStateCoordinator } from './BrowserDownloadNavigationStateCoordinator';
import { BrowserPageReloadReason } from './BrowserRuntimeActionReason';

export interface BrowserRestoreTrace {
  id: string;
  startedAt: number;
  tabId: string;
  reason: TabRestoreReason;
  restoreType: WebSessionRestoreType;
  targetUrl: string;
  snapshotPath: string;
  scrollOffsetY: number;
  source: string;
  breadcrumbs: string[];
}

interface BrowserRestoreStartResolution {
  restorePlan: WebRestoreRecoveryPlan;
  patch: BrowserTabRuntimePatch;
  trace: BrowserRestoreTrace;
}

export interface BrowserColdRestoreResolution {
  records: TabRecord[];
  skippedCount: number;
  traces: BrowserRestoreTrace[];
}

interface BrowserActiveTabNavigationRestoreResolution {
  targetUrl: string;
  tabPatch: BrowserTabRuntimePatch;
  runtimeEventType: string;
  runtimeEventMessage: string;
  restoreTraceBreadcrumb: string;
  helperMessage: string;
}

export class BrowserRestoreCoordinator {
  private downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;

  constructor(downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator) {
    this.downloadNavigationStateCoordinator = downloadNavigationStateCoordinator;
  }

  buildRestoreStartResolution(
    recoveryManager: WebRecoveryManager,
    sessionStateStore: WebSessionStateStore,
    tab: BrowserTabState,
    reason: TabRestoreReason
  ): BrowserRestoreStartResolution {
    const effectiveReason = this.resolveEffectiveRestoreReason(tab, reason);
    const basePlan = recoveryManager.buildRestorePlan(tab, effectiveReason);
    const restoreType = this.resolveRestoreType(basePlan);
    const targetUrl = this.resolveRestoreTargetUrl(tab, basePlan, effectiveReason);
    const restorePlan = this.copyRestorePlan(basePlan, targetUrl);
    const trace = this.createTrace(tab, effectiveReason, restoreType, restorePlan);
    const restoreTypePatch = sessionStateStore.buildRestoreTypePatch(restoreType, tab);
    return {
      restorePlan: restorePlan,
      patch: {
        runtimeState: 'restoring',
        lastError: '',
        lastRestoreReason: effectiveReason,
        lastCrashReason: '',
        lastRestoreType: restoreTypePatch.lastRestoreType,
        lastGoodUrl: restoreTypePatch.lastGoodUrl,
        lastGoodTitle: restoreTypePatch.lastGoodTitle,
        lastRestorableUrl: restoreTypePatch.lastRestorableUrl,
        lastRestorableTitle: restoreTypePatch.lastRestorableTitle
      },
      trace: trace
    };
  }

  buildManualReloadResolution(
    tab: BrowserTabState,
    targetUrl: string,
    reloadReason: BrowserPageReloadReason = 'user_manual_reload'
  ): BrowserRestoreStartResolution {
    const normalizedTargetUrl = this.normalizeTargetUrl(targetUrl);
    const restorePlan: WebRestoreRecoveryPlan = {
      tabId: tab.id,
      reason: 'manual_reload',
      targetUrl: normalizedTargetUrl,
      snapshotPath: '',
      attemptSnapshotRestore: false,
      helperMessage: '正在刷新页面',
    };
    const trace = this.createTrace(tab, 'manual_reload', 'reload', restorePlan, reloadReason);
    return {
      restorePlan: restorePlan,
      patch: {
        pendingUrl: normalizedTargetUrl,
        url: normalizedTargetUrl,
        isHome: false,
        runtimeState: 'loading',
        lastError: '',
        lastRestoreReason: 'manual_reload',
        lastCrashReason: '',
        webStatePath: '',
        webStateUpdatedAt: 0,
        scrollOffsetY: 0,
        lastRestoreType: 'reload'
      },
      trace: trace
    };
  }

  buildColdRestoreResolution(recoveryManager: WebRecoveryManager, records: TabRecord[]): BrowserColdRestoreResolution {
    const sanitized = recoveryManager.sanitizeColdRestoreRecords(records);
    const restoredRecords = sanitized.records.map((record: TabRecord) => this.buildColdRestoreRecord(record));
    return {
      records: restoredRecords,
      skippedCount: sanitized.skippedCount,
      traces: restoredRecords
        .filter((record: TabRecord) => record.isHome !== true)
        .map((record: TabRecord) => this.createColdRestoreTrace(record))
    };
  }

  buildActiveTabNavigationRestoreResolution(
    restorePlan: WebRestoreRecoveryPlan,
    reason: TabRestoreReason
  ): BrowserActiveTabNavigationRestoreResolution {
    return {
      targetUrl: restorePlan.targetUrl,
      tabPatch: this.resolveNavigationRestorePatch(restorePlan, reason),
      runtimeEventType: 'restore_navigation',
      runtimeEventMessage: `通过导航恢复 ${restorePlan.targetUrl}`,
      restoreTraceBreadcrumb: `restore_navigation ${restorePlan.targetUrl}`,
      helperMessage: '正在加载标签页'
    };
  }

  private resolveNavigationRestorePatch(
    restorePlan: WebRestoreRecoveryPlan,
    reason: TabRestoreReason
  ): BrowserTabRuntimePatch {
    return {
      runtimeState: 'loading',
      lastError: '',
      lastRestoreReason: reason,
      lastCrashReason: '',
      lastRestoreType: 'reload'
    };
  }

  private resolveEffectiveRestoreReason(tab: BrowserTabState, reason: TabRestoreReason): TabRestoreReason {
    if (reason === 'tab_switch' || reason === 'controller_attach') {
      if (tab.runtimeState === 'crashed' || tab.runtimeState === 'error' || tab.lastCrashReason.length > 0) {
        return 'crash_restore';
      }
      if (tab.runtimeState === 'cold' || tab.runtimeState === 'discarded' || tab.runtimeState === 'suspended' ||
        tab.lastDiscardReason.length > 0) {
        return 'discard_restore';
      }
    }
    return reason;
  }

  private resolveRestoreType(restorePlan: WebRestoreRecoveryPlan): WebSessionRestoreType {
    if (restorePlan.attemptSnapshotRestore && restorePlan.snapshotPath.length > 0) {
      return 'snapshot_restore';
    }
    return 'reload';
  }

  private resolveRestoreTargetUrl(
    tab: BrowserTabState,
    restorePlan: WebRestoreRecoveryPlan,
    reason: TabRestoreReason
  ): string {
    const resolution = this.shouldPreferTabSwitchNavigation(reason)
      ? this.downloadNavigationStateCoordinator.resolveTabSwitchNavigation(tab)
      : this.downloadNavigationStateCoordinator.resolveRestorableNavigation(tab);
    if (resolution.url.length > 0) {
      return resolution.url;
    }
    return this.downloadNavigationStateCoordinator.resolveRestoreTarget(
      '',
      restorePlan.targetUrl.length > 0 ? restorePlan.targetUrl : tab.pendingUrl,
      tab.url
    );
  }

  private shouldPreferTabSwitchNavigation(reason: TabRestoreReason): boolean {
    return reason === 'tab_switch' || reason === 'controller_attach';
  }

  private buildColdRestoreRecord(record: TabRecord): TabRecord {
    const sanitizedRecord = this.downloadNavigationStateCoordinator.sanitizePersistedRecord(record).record;
    const isHome = sanitizedRecord.isHome === true;
    const restoreType: WebSessionRestoreType = isHome ? 'none' : 'reload';
    const targetUrl = this.resolveRecordTargetUrl(sanitizedRecord);
    const normalizedTargetUrl = targetUrl.length > 0 ? targetUrl : sanitizedRecord.url;
    const nextRecord: TabRecord = {
      id: sanitizedRecord.id,
      windowId: sanitizedRecord.windowId,
      profileId: sanitizedRecord.profileId,
      title: sanitizedRecord.title,
      url: isHome ? sanitizedRecord.url : normalizedTargetUrl,
      isActive: sanitizedRecord.isActive,
      isPinned: sanitizedRecord.isPinned,
      lastActiveAt: sanitizedRecord.lastActiveAt
    };
    nextRecord.isHome = sanitizedRecord.isHome;
    nextRecord.pendingUrl = isHome ? '' : normalizedTargetUrl;
    nextRecord.navigationHistory = sanitizedRecord.navigationHistory === undefined
      ? undefined
      : sanitizedRecord.navigationHistory.slice();
    nextRecord.navigationIndex = sanitizedRecord.navigationIndex;
    nextRecord.runtimeState = this.resolveColdRestoreRuntimeState(sanitizedRecord, isHome);
    nextRecord.lastError = '';
    nextRecord.lastRestoreReason = isHome ? sanitizedRecord.lastRestoreReason : 'cold_start';
    nextRecord.lastDiscardReason = sanitizedRecord.lastDiscardReason;
    nextRecord.lastLoadedAt = sanitizedRecord.lastLoadedAt;
    nextRecord.webStatePath = '';
    nextRecord.webStateUpdatedAt = 0;
    nextRecord.scrollOffsetY = 0;
    nextRecord.lastGoodUrl = sanitizedRecord.lastGoodUrl;
    nextRecord.lastGoodTitle = sanitizedRecord.lastGoodTitle;
    nextRecord.lastRestorableUrl = sanitizedRecord.lastRestorableUrl;
    nextRecord.lastRestorableTitle = sanitizedRecord.lastRestorableTitle;
    nextRecord.lastRestoreType = isHome ? 'none' : restoreType;
    nextRecord.lastCrashReason = sanitizedRecord.lastCrashReason;
    nextRecord.privacyMode = sanitizedRecord.privacyMode;
    nextRecord.dataScope = sanitizedRecord.dataScope;
    nextRecord.launchSourceType = sanitizedRecord.launchSourceType;
    nextRecord.launchSourceId = sanitizedRecord.launchSourceId;
    nextRecord.launchSourceUrl = sanitizedRecord.launchSourceUrl;
    nextRecord.launchKey = sanitizedRecord.launchKey;
    return nextRecord;
  }

  private resolveColdRestoreRuntimeState(
    record: TabRecord,
    isHome: boolean
  ): TabRuntimeState | undefined {
    if (isHome) {
      return record.isActive ? 'active' : 'background';
    }
    if (record.isActive) {
      return 'loading';
    }
    return 'suspended';
  }

  private resolveRecordTargetUrl(record: TabRecord): string {
    return this.normalizeTargetUrl(
      this.downloadNavigationStateCoordinator.resolveRecordRestorableNavigation(record).url
    );
  }

  private createTrace(
    tab: BrowserTabState,
    reason: TabRestoreReason,
    restoreType: WebSessionRestoreType,
    restorePlan: WebRestoreRecoveryPlan,
    forcedSource: string = ''
  ): BrowserRestoreTrace {
    const source = forcedSource.length > 0
      ? forcedSource
      : (tab.lastRestorableUrl.length > 0 ? 'last_restorable_state' :
        (tab.lastGoodUrl.length > 0 ? 'last_good_state' : 'tab_url'));
    return {
      id: `${tab.id}-${Date.now()}`,
      startedAt: Date.now(),
      tabId: tab.id,
      reason: reason,
      restoreType: restoreType,
      targetUrl: restorePlan.targetUrl,
      snapshotPath: restorePlan.snapshotPath,
      scrollOffsetY: tab.scrollOffsetY,
      source: source,
      breadcrumbs: [`restore_start reason=${reason} type=${restoreType} target=${restorePlan.targetUrl}`]
    };
  }

  private createColdRestoreTrace(record: TabRecord): BrowserRestoreTrace {
    const restoreType: WebSessionRestoreType = record.isHome === true ? 'none' : 'reload';
    const targetUrl = this.resolveRecordTargetUrl(record);
    const resolution = this.downloadNavigationStateCoordinator.resolveRecordRestorableNavigation(record);
    return {
      id: `${record.id}-${Date.now()}`,
      startedAt: Date.now(),
      tabId: record.id,
      reason: 'cold_start',
      restoreType: restoreType,
      targetUrl: targetUrl,
      snapshotPath: '',
      scrollOffsetY: record.scrollOffsetY ?? 0,
      source: resolution.source.length > 0 ? resolution.source : 'tab_record',
      breadcrumbs: [`cold_restore type=${restoreType} target=${targetUrl}`]
    };
  }

  private copyRestorePlan(restorePlan: WebRestoreRecoveryPlan, targetUrl: string): WebRestoreRecoveryPlan {
    return {
      tabId: restorePlan.tabId,
      reason: restorePlan.reason,
      targetUrl: targetUrl,
      snapshotPath: restorePlan.snapshotPath,
      attemptSnapshotRestore: restorePlan.attemptSnapshotRestore,
      helperMessage: restorePlan.helperMessage
    };
  }

  private normalizeTargetUrl(url: string): string {
    return url.trim();
  }

}
