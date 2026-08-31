import { isBrowserDataBoundarySessionEphemeralTabLike } from '../../common/models/BrowserModels';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import { BrowserQuickSearchReloadOwner } from '../search/BrowserQuickSearchSwitchingCoordinator';
import { BrowserTabState } from '../tabs/TabManager';
import { WebStateSnapshotStore } from '../web/WebStateSnapshotStore';
import { WebTabRuntimeRecord } from '../web/WebTabRuntime';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserWebTabsController } from './BrowserWebTabsController';
import { BrowserPageReloadReason } from './BrowserRuntimeActionReason';

export type BrowserUserAgentRuntimeTransitionStatus = 'started' | 'deferred' | 'superseded';

export type BrowserUserAgentRuntimeTransitionReason =
  'none' |
  'invalid_tab' |
  'session_ephemeral' |
  'runtime_missing' |
  'serialize_failed' |
  'snapshot_save_failed' |
  'superseded' |
  'runtime_replace_failed';

export interface BrowserUserAgentRuntimeTransitionResult {
  status: BrowserUserAgentRuntimeTransitionStatus;
  reason: BrowserUserAgentRuntimeTransitionReason;
}

export interface BrowserUserAgentRuntimeTransitionHost {
  resolveActiveTab: () => BrowserTabState | undefined;
  applyActiveRuntimeController: (tab: BrowserTabState, runtime: WebTabRuntimeRecord) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
}

interface BrowserUserAgentRuntimeTransitionDependencies {
  webTabsController: BrowserWebTabsController;
  snapshotStore: WebStateSnapshotStore;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  quickSearchReloadOwner: BrowserQuickSearchReloadOwner;
}

interface BrowserUserAgentSnapshotRestoreReloadMarker {
  generation: number;
  reloadReason: BrowserPageReloadReason;
}

export class BrowserUserAgentRuntimeTransitionCoordinator {
  private readonly dependencies: BrowserUserAgentRuntimeTransitionDependencies;
  private readonly host: BrowserUserAgentRuntimeTransitionHost;
  private generation: number = 0;
  private pendingTabId: string = '';
  private pendingTransition?: Promise<BrowserUserAgentRuntimeTransitionResult>;
  private pendingSnapshotReloadMarkerByTabId:
    Record<string, BrowserUserAgentSnapshotRestoreReloadMarker | undefined> = {};

  constructor(
    dependencies: BrowserUserAgentRuntimeTransitionDependencies,
    host: BrowserUserAgentRuntimeTransitionHost
  ) {
    this.dependencies = dependencies;
    this.host = host;
  }

  transitionToNative(
    tabId: string,
    reloadReason: BrowserPageReloadReason
  ): Promise<BrowserUserAgentRuntimeTransitionResult> {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return Promise.resolve(this.buildResult('deferred', 'invalid_tab'));
    }
    if (this.pendingTabId === normalizedTabId && this.pendingTransition !== undefined) {
      return this.pendingTransition;
    }

    this.generation += 1;
    const transitionGeneration = this.generation;
    const transition = this.runTransition(normalizedTabId, transitionGeneration, reloadReason);
    this.pendingTabId = normalizedTabId;
    this.pendingTransition = transition;
    void transition.then((): void => {
      if (this.generation !== transitionGeneration) {
        return;
      }
      this.pendingTabId = '';
      this.pendingTransition = undefined;
    });
    return transition;
  }

  cancelPending(tabId: string = ''): void {
    const normalizedTabId = tabId.trim();
    const hasMatchingPendingTransition = this.pendingTransition !== undefined &&
      (normalizedTabId.length <= 0 || normalizedTabId === this.pendingTabId);
    const hasMatchingReloadMarker = normalizedTabId.length > 0
      ? this.pendingSnapshotReloadMarkerByTabId[normalizedTabId] !== undefined
      : this.hasPendingSnapshotReloadMarker();
    if (!hasMatchingPendingTransition && !hasMatchingReloadMarker) {
      return;
    }
    if (!hasMatchingPendingTransition) {
      if (normalizedTabId.length > 0) {
        this.pendingSnapshotReloadMarkerByTabId[normalizedTabId] = undefined;
      } else {
        this.pendingSnapshotReloadMarkerByTabId = {};
      }
      return;
    }
    this.generation += 1;
    if (normalizedTabId.length > 0) {
      this.pendingSnapshotReloadMarkerByTabId[normalizedTabId] = undefined;
      if (this.pendingTabId === normalizedTabId) {
        this.pendingTabId = '';
        this.pendingTransition = undefined;
      }
      return;
    }
    this.pendingTabId = '';
    this.pendingTransition = undefined;
    this.pendingSnapshotReloadMarkerByTabId = {};
  }

  cancelUncommittedTransition(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    const hasMatchingReloadMarker = this.pendingSnapshotReloadMarkerByTabId[normalizedTabId] !== undefined;
    if (hasMatchingReloadMarker) {
      return;
    }
    if (this.pendingTransition === undefined || this.pendingTabId !== normalizedTabId) {
      return;
    }
    this.generation += 1;
    this.pendingTabId = '';
    this.pendingTransition = undefined;
  }

  clearSnapshotRestoreReloadMarker(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    this.pendingSnapshotReloadMarkerByTabId[normalizedTabId] = undefined;
  }

  consumeSnapshotRestoreReloadReason(tabId: string): BrowserPageReloadReason | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return undefined;
    }
    const marker = this.pendingSnapshotReloadMarkerByTabId[normalizedTabId];
    if (marker === undefined) {
      return undefined;
    }
    this.pendingSnapshotReloadMarkerByTabId[normalizedTabId] = undefined;
    const activeTab = this.host.resolveActiveTab();
    const controller = this.dependencies.runtimeLifecyclePort.resolveController(normalizedTabId);
    if (this.generation !== marker.generation || activeTab === undefined || activeTab.id !== normalizedTabId ||
      activeTab.isHome || controller === undefined) {
      return undefined;
    }
    this.host.recordRuntimeEvent(
      'user_agent_runtime_transition_reload_handoff',
      'UA 过渡快照已恢复，交由浏览器导航链刷新网页标识',
      normalizedTabId
    );
    return marker.reloadReason;
  }

  private async runTransition(
    tabId: string,
    transitionGeneration: number,
    reloadReason: BrowserPageReloadReason
  ): Promise<BrowserUserAgentRuntimeTransitionResult> {
    const activeTab = this.host.resolveActiveTab();
    if (activeTab === undefined || activeTab.id !== tabId || activeTab.isHome) {
      return this.buildResult('deferred', 'invalid_tab');
    }
    if (isBrowserDataBoundarySessionEphemeralTabLike({
      id: activeTab.id,
      profileId: activeTab.profileId,
      privacyMode: activeTab.privacyMode,
      dataScope: activeTab.dataScope
    })) {
      return this.buildResult('deferred', 'session_ephemeral');
    }
    if (this.dependencies.runtimeLifecyclePort.resolveController(tabId) === undefined) {
      return this.buildResult('deferred', 'runtime_missing');
    }

    let serializedWebState: Uint8Array | undefined;
    try {
      serializedWebState = this.dependencies.webTabsController.serializeWebState(tabId);
    } catch (_error) {
      return this.buildResult('deferred', 'serialize_failed');
    }
    if (serializedWebState === undefined || serializedWebState.byteLength <= 0) {
      return this.buildResult('deferred', 'serialize_failed');
    }

    let releasedOldRuntime = false;
    try {
      const snapshot = await this.dependencies.snapshotStore.saveSnapshot(tabId, serializedWebState);
      if (snapshot === undefined) {
        return this.buildResult('deferred', 'snapshot_save_failed');
      }
      if (!this.isCurrent(transitionGeneration, tabId)) {
        return this.buildResult('superseded', 'superseded');
      }

      this.dependencies.tabSwitchCoordinator.applyTabPatch(tabId, {
        webStatePath: snapshot.path,
        webStateUpdatedAt: snapshot.updatedAt,
        runtimeState: 'restoring',
        lastError: '',
        lastRestoreReason: 'controller_attach',
        lastCrashReason: ''
      });
      const restoringTab = this.host.resolveActiveTab();
      if (restoringTab === undefined || restoringTab.id !== tabId) {
        return this.buildResult('superseded', 'superseded');
      }

      this.dependencies.quickSearchReloadOwner.prepareQuickSearchForReload(tabId);
      this.host.recordRuntimeEvent(
        'user_agent_runtime_transition_snapshot_saved',
        `已保存 UA 运行时过渡快照 ${snapshot.path}`,
        tabId
      );
      this.dependencies.hostedRuntimeSurfacePort.release(tabId, 'user_agent_changed');
      releasedOldRuntime = true;
      const runtime = this.dependencies.runtimeLifecyclePort.replaceControllerForRuntimeRefresh(tabId);
      if (runtime === undefined) {
        this.host.recordRuntimeEvent(
          'user_agent_runtime_transition_replace_failed',
          'UA 运行时过渡未能创建替换 Controller',
          tabId
        );
        return this.buildResult('started', 'runtime_replace_failed');
      }
      this.host.applyActiveRuntimeController(restoringTab, runtime);
      this.pendingSnapshotReloadMarkerByTabId[tabId] = {
        generation: transitionGeneration,
        reloadReason: reloadReason
      };
      this.host.recordRuntimeEvent(
        'user_agent_runtime_transition_started',
        'UA 运行时已替换，等待 Web 访问栈恢复',
        tabId
      );
      return this.buildResult('started', 'none');
    } catch (_error) {
      if (!this.isCurrent(transitionGeneration, tabId)) {
        return this.buildResult('superseded', 'superseded');
      }
      if (releasedOldRuntime) {
        this.pendingSnapshotReloadMarkerByTabId[tabId] = undefined;
        this.host.recordRuntimeEvent(
          'user_agent_runtime_transition_replace_failed',
          'UA 运行时过渡在释放旧 Controller 后异常',
          tabId
        );
        return this.buildResult('started', 'runtime_replace_failed');
      }
      return this.buildResult('deferred', 'snapshot_save_failed');
    }
  }

  private isCurrent(transitionGeneration: number, tabId: string): boolean {
    const activeTab = this.host.resolveActiveTab();
    return this.generation === transitionGeneration && activeTab !== undefined &&
      activeTab.id === tabId && !activeTab.isHome;
  }

  private buildResult(
    status: BrowserUserAgentRuntimeTransitionStatus,
    reason: BrowserUserAgentRuntimeTransitionReason
  ): BrowserUserAgentRuntimeTransitionResult {
    return {
      status: status,
      reason: reason
    };
  }

  private hasPendingSnapshotReloadMarker(): boolean {
    return Object.keys(this.pendingSnapshotReloadMarkerByTabId).some(
      (tabId: string): boolean => this.pendingSnapshotReloadMarkerByTabId[tabId] !== undefined
    );
  }
}
