import { TabDiscardReason, TabRestoreReason, TabRuntimeState } from '../../common/models/BrowserModels';
import {
  BrowserHostedWebNodeDisposeAllReason,
  BrowserHostedWebNodeDisposeReason
} from '../../core/browser/BrowserRuntimeActionReason';
import { BrowserSessionCoordinator } from '../../core/browser/BrowserSessionCoordinator';
import {
  BrowserHostedWebOwnershipCoordinator,
  BrowserHostedWebOwnershipSnapshot
} from '../../core/browser/BrowserHostedWebOwnershipCoordinator';
import { BrowserPageFindCoordinator } from '../../core/browser/BrowserPageFindCoordinator';
import {
  BrowserWebHostCoordinator,
  BrowserWebHostSyncResult
} from '../../core/browser/BrowserWebHostCoordinator';
import { BrowserTabRuntimePatch, BrowserTabState } from '../../core/tabs/TabManager';

export type BrowserTabRuntimeLifecycleResultKind =
  'discard_started' |
  'discard_skipped' |
  'restore_started' |
  'restore_skipped';

export interface BrowserTabRuntimeLifecycleResult {
  kind: BrowserTabRuntimeLifecycleResultKind;
  tabId: string;
  message: string;
}

export interface BrowserTabRuntimeRestoreDecision {
  reason: TabRestoreReason;
  stateBefore: TabRuntimeState;
  shouldMarkRestoring: boolean;
  isLiveRuntimePath: boolean;
}

export interface BrowserTabRuntimeDiscardRequest {
  tabId: string;
  reason: TabDiscardReason;
  queuedAt: number;
  activeTabId: string;
  protectedReasonsByTabId: Record<string, string>;
  resolveTab: (tabId: string) => BrowserTabState | undefined;
  persistMountedRuntimeSnapshot: (tabId: string, releaseHostedNodeAfterPersist: boolean) => void;
  applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
}

export interface BrowserTabRuntimeRestoreRequest {
  tabId: string;
  reason: TabRestoreReason;
  resolveTab: (tabId: string) => BrowserTabState | undefined;
  applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch) => void;
  executeRestoreRuntime: (tabId: string, reason: TabRestoreReason) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
}

export interface BrowserHostedRuntimeReleaseResult {
  activeHostedTabId: string;
  activeHostedRenderKey: string;
  ownershipSnapshot?: BrowserHostedWebOwnershipSnapshot;
  released: boolean;
  releasedTabIds: string[];
  activeReleased: boolean;
}

export interface BrowserHostedRuntimeReleaseRequest {
  tabId: string;
  reason: BrowserHostedWebNodeDisposeReason;
  activeTabId: string;
  webHostCoordinator: BrowserWebHostCoordinator;
  sessionCoordinator: BrowserSessionCoordinator;
  ownershipCoordinator: BrowserHostedWebOwnershipCoordinator;
  pageFindCoordinator: BrowserPageFindCoordinator;
}

export interface BrowserHostedRuntimeReleaseInactiveRequest {
  tabs: BrowserTabState[];
  activeTabId: string;
  reason: BrowserHostedWebNodeDisposeReason;
  webHostCoordinator: BrowserWebHostCoordinator;
  sessionCoordinator: BrowserSessionCoordinator;
  ownershipCoordinator: BrowserHostedWebOwnershipCoordinator;
  pageFindCoordinator: BrowserPageFindCoordinator;
}

export interface BrowserHostedRuntimeReleaseAllRequest {
  tabs: BrowserTabState[];
  activeTabId: string;
  reason: BrowserHostedWebNodeDisposeAllReason;
  webHostCoordinator: BrowserWebHostCoordinator;
  sessionCoordinator: BrowserSessionCoordinator;
  ownershipCoordinator: BrowserHostedWebOwnershipCoordinator;
  pageFindCoordinator: BrowserPageFindCoordinator;
}

export interface BrowserParkedHostedRuntimeReleaseRequest {
  tabId: string;
  source: string;
  webHostCoordinator: BrowserWebHostCoordinator;
  sessionCoordinator: BrowserSessionCoordinator;
  ownershipCoordinator: BrowserHostedWebOwnershipCoordinator;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
}

export interface BrowserBackgroundHotRuntimeReleaseRequest {
  tabId: string;
  reason: BrowserHostedWebNodeDisposeReason;
  webHostCoordinator: BrowserWebHostCoordinator;
  sessionCoordinator: BrowserSessionCoordinator;
  ownershipCoordinator: BrowserHostedWebOwnershipCoordinator;
  clearPreviewTimers: () => void;
  clearPreviewLoadIssuedTab: (tabId: string) => void;
  updateBackgroundRuntimeState: (tabId: string, runtimeState: TabRuntimeState) => void;
}

export class BrowserTabRuntimeLifecycleService {
  buildRestoreDecision(tab: BrowserTabState, fallbackReason: TabRestoreReason): BrowserTabRuntimeRestoreDecision {
    const reason = this.resolveRestoreReason(tab, fallbackReason);
    const shouldMarkRestoring = this.shouldMarkRestoring(tab);
    return {
      reason: reason,
      stateBefore: tab.runtimeState,
      shouldMarkRestoring: shouldMarkRestoring,
      isLiveRuntimePath: !shouldMarkRestoring
    };
  }

  resolveRestoreReason(tab: BrowserTabState, fallbackReason: TabRestoreReason): TabRestoreReason {
    if (tab.lastRestoreReason === 'cold_start') {
      return 'cold_start';
    }
    if (tab.runtimeState === 'crashed' || tab.runtimeState === 'error' || tab.lastCrashReason.length > 0) {
      return 'crash_restore';
    }
    if (tab.runtimeState === 'discarded' || tab.lastDiscardReason.length > 0) {
      return 'discard_restore';
    }
    return fallbackReason;
  }

  discardRuntime(request: BrowserTabRuntimeDiscardRequest): BrowserTabRuntimeLifecycleResult {
    const tab = request.resolveTab(request.tabId);
    if (tab === undefined) {
      return this.buildResult('discard_skipped', request.tabId, 'missing_tab');
    }
    if (tab.isHome) {
      request.recordRuntimeEvent('tab_runtime_discard_skipped', 'reason=home_tab', request.tabId);
      return this.buildResult('discard_skipped', request.tabId, 'home_tab');
    }
    if (request.tabId === request.activeTabId) {
      request.recordRuntimeEvent('tab_runtime_discard_skipped', 'reason=active_tab', request.tabId);
      return this.buildResult('discard_skipped', request.tabId, 'active_tab');
    }
    if (request.queuedAt > 0 && tab.lastActiveAt > request.queuedAt) {
      request.recordRuntimeEvent(
        'tab_runtime_discard_skipped',
        `reason=recent_activity_after_queue queuedAt=${request.queuedAt} lastActiveAt=${tab.lastActiveAt}`,
        request.tabId
      );
      return this.buildResult('discard_skipped', request.tabId, 'recent_activity_after_queue');
    }
    if (tab.runtimeState === 'active') {
      request.recordRuntimeEvent('tab_runtime_discard_skipped', 'reason=active_state', request.tabId);
      return this.buildResult('discard_skipped', request.tabId, 'active_state');
    }
    const protectedReason = request.protectedReasonsByTabId[request.tabId] ?? '';
    if (protectedReason.length > 0) {
      request.recordRuntimeEvent(
        'tab_runtime_discard_skipped',
        `reason=protected protectedReason=${protectedReason}`,
        request.tabId
      );
      return this.buildResult('discard_skipped', request.tabId, 'protected');
    }
    if (tab.runtimeState === 'discarded' && tab.lastDiscardReason === request.reason) {
      request.recordRuntimeEvent('tab_runtime_discard_skipped', `reason=already_discarded discard=${request.reason}`,
        request.tabId);
      return this.buildResult('discard_skipped', request.tabId, 'already_discarded');
    }

    request.recordRuntimeEvent('tab_runtime_discard_start', `reason=${request.reason}`, request.tabId);
    request.persistMountedRuntimeSnapshot(request.tabId, true);
    request.applyTabRuntimePatch(request.tabId, {
      runtimeState: 'discarded',
      lastDiscardReason: request.reason,
      lastRestoreReason: '',
      lastError: ''
    });
    request.recordRuntimeEvent('tab_runtime_discard_marked', `reason=${request.reason}`, request.tabId);
    return this.buildResult('discard_started', request.tabId, request.reason);
  }

  restoreRuntime(request: BrowserTabRuntimeRestoreRequest): BrowserTabRuntimeLifecycleResult {
    const tab = request.resolveTab(request.tabId);
    if (tab === undefined) {
      return this.buildResult('restore_skipped', request.tabId, 'missing_tab');
    }
    if (tab.isHome) {
      request.recordRuntimeEvent('tab_runtime_restore_skipped', 'reason=home_tab', request.tabId);
      return this.buildResult('restore_skipped', request.tabId, 'home_tab');
    }
    const decision = this.buildRestoreDecision(tab, request.reason);
    if (decision.shouldMarkRestoring) {
      request.applyTabRuntimePatch(request.tabId, {
        runtimeState: 'restoring',
        lastRestoreReason: decision.reason,
        lastDiscardReason: ''
      });
    } else {
      request.recordRuntimeEvent(
        'tab_runtime_restore_live_path',
        `reason=${decision.reason} state=${decision.stateBefore}`,
        request.tabId
      );
    }
    request.executeRestoreRuntime(request.tabId, decision.reason);
    request.recordRuntimeEvent(
      'tab_runtime_restore_dispatched',
      `reason=${decision.reason} state=${decision.stateBefore} marked=${decision.shouldMarkRestoring ? 'true' : 'false'}`,
      request.tabId
    );
    return this.buildResult('restore_started', request.tabId, decision.reason);
  }

  releaseHostedRuntime(request: BrowserHostedRuntimeReleaseRequest): BrowserHostedRuntimeReleaseResult {
    const tabId = request.tabId.trim();
    if (tabId.length === 0) {
      return this.buildHostedReleaseResult(
        request.webHostCoordinator.dispose(tabId, request.reason),
        request.ownershipCoordinator.getSnapshot(),
        false,
        [],
        false
      );
    }
    const hadController = request.webHostCoordinator.getController(tabId) !== undefined;
    request.ownershipCoordinator.releaseParkedDesktopWebEntry(tabId);
    request.ownershipCoordinator.releaseBackgroundHot(tabId);
    request.pageFindCoordinator.handleControllerDisposed(tabId, request.reason === 'tab_close');
    const hostResult = request.webHostCoordinator.dispose(tabId, request.reason);
    request.sessionCoordinator.markTabControllerDetached(tabId);
    return this.buildHostedReleaseResult(
      hostResult,
      request.ownershipCoordinator.getSnapshot(),
      hadController,
      hadController ? [tabId] : [],
      hadController && tabId === request.activeTabId
    );
  }

  releaseInactiveHostedRuntimes(request: BrowserHostedRuntimeReleaseInactiveRequest): BrowserHostedRuntimeReleaseResult {
    let latestResult = this.buildHostedReleaseResult(
      request.webHostCoordinator.dispose('', request.reason),
      request.ownershipCoordinator.getSnapshot(),
      false,
      [],
      false
    );
    request.tabs
      .filter((tab: BrowserTabState) => !tab.isHome && tab.id !== request.activeTabId)
      .forEach((tab: BrowserTabState) => {
        if (!request.ownershipCoordinator.canHostActive(tab.id)) {
          return;
        }
        latestResult = this.releaseHostedRuntime({
          tabId: tab.id,
          reason: request.reason,
          activeTabId: request.activeTabId,
          webHostCoordinator: request.webHostCoordinator,
          sessionCoordinator: request.sessionCoordinator,
          ownershipCoordinator: request.ownershipCoordinator,
          pageFindCoordinator: request.pageFindCoordinator
        });
      });
    return latestResult;
  }

  releaseAllHostedRuntimes(request: BrowserHostedRuntimeReleaseAllRequest): BrowserHostedRuntimeReleaseResult {
    request.tabs
      .filter((tab: BrowserTabState) => !tab.isHome)
      .forEach((tab: BrowserTabState) => {
        request.pageFindCoordinator.handleControllerDisposed(tab.id, false);
        request.sessionCoordinator.markTabControllerDetached(tab.id);
      });
    const hostResult = request.webHostCoordinator.disposeAll(request.reason);
    request.ownershipCoordinator.clearParkedDesktopWebEntries();
    const ownershipSnapshot = request.ownershipCoordinator.clearBackgroundHotTabs();
    return this.buildHostedReleaseResult(
      hostResult,
      ownershipSnapshot,
      true,
      this.resolveReleasedTabIds(request.tabs),
      this.includesReleasedTabId(request.tabs, request.activeTabId)
    );
  }

  releaseParkedHostedRuntime(request: BrowserParkedHostedRuntimeReleaseRequest): BrowserHostedRuntimeReleaseResult {
    const tabId = request.tabId.trim();
    if (tabId.length === 0 || !request.ownershipCoordinator.isParked(tabId)) {
      return this.buildHostedReleaseResult(
        request.webHostCoordinator.dispose('', 'context_switch'),
        request.ownershipCoordinator.getSnapshot(),
        false,
        [],
        false
      );
    }
    const release = request.ownershipCoordinator.releaseParkedDesktopWebEntry(tabId);
    const hostResult = request.webHostCoordinator.dispose(tabId, 'context_switch');
    request.sessionCoordinator.markTabControllerDetached(tabId);
    request.recordRuntimeEvent('desktop_web_entry_webview_unparked_disposed', request.source, tabId);
    return this.buildHostedReleaseResult(hostResult, release.snapshot, true, [tabId], false);
  }

  releaseBackgroundHotRuntime(request: BrowserBackgroundHotRuntimeReleaseRequest): BrowserHostedRuntimeReleaseResult {
    const tabId = request.tabId.trim();
    const currentPreviewHostedTabId = request.webHostCoordinator.getPreviewHostedTabId();
    if (tabId.length === 0 ||
      (!request.ownershipCoordinator.isBackgroundHot(tabId) && currentPreviewHostedTabId !== tabId)) {
      return this.buildHostedReleaseResult(
        request.webHostCoordinator.dispose('', request.reason),
        request.ownershipCoordinator.getSnapshot(),
        false,
        [],
        false
      );
    }
    request.clearPreviewTimers();
    const hostResult = request.webHostCoordinator.dispose(tabId, request.reason);
    request.clearPreviewLoadIssuedTab(tabId);
    const release = request.ownershipCoordinator.releaseBackgroundHot(tabId);
    request.sessionCoordinator.markTabControllerDetached(tabId);
    request.updateBackgroundRuntimeState(tabId, 'suspended');
    return this.buildHostedReleaseResult(hostResult, release.snapshot, true, [tabId], false);
  }

  private shouldMarkRestoring(tab: BrowserTabState): boolean {
    return tab.runtimeState === 'cold' ||
      tab.runtimeState === 'discarded' ||
      tab.runtimeState === 'suspended' ||
      tab.runtimeState === 'crashed' ||
      tab.runtimeState === 'error' ||
      tab.lastCrashReason.length > 0 ||
      tab.lastDiscardReason.length > 0;
  }

  private buildResult(
    kind: BrowserTabRuntimeLifecycleResultKind,
    tabId: string,
    message: string
  ): BrowserTabRuntimeLifecycleResult {
    return {
      kind: kind,
      tabId: tabId,
      message: message
    };
  }

  private buildHostedReleaseResult(
    hostResult: BrowserWebHostSyncResult,
    ownershipSnapshot: BrowserHostedWebOwnershipSnapshot,
    released: boolean,
    releasedTabIds: string[],
    activeReleased: boolean
  ): BrowserHostedRuntimeReleaseResult {
    return {
      activeHostedTabId: hostResult.activeHostedTabId,
      activeHostedRenderKey: hostResult.activeHostedRenderKey,
      ownershipSnapshot: ownershipSnapshot,
      released: released,
      releasedTabIds: releasedTabIds,
      activeReleased: activeReleased
    };
  }

  private resolveReleasedTabIds(tabs: BrowserTabState[]): string[] {
    return tabs
      .filter((tab: BrowserTabState) => !tab.isHome)
      .map((tab: BrowserTabState) => tab.id);
  }

  private includesReleasedTabId(tabs: BrowserTabState[], tabId: string): boolean {
    return tabs.some((tab: BrowserTabState) => !tab.isHome && tab.id === tabId);
  }
}
