import { BrowserTabState, TabManager } from '../tabs/TabManager';
import { TabCrashReason, TabRestoreReason, TabRuntimeState } from '../../common/models/BrowserModels';
import {
  WebPageCacheCoordinator,
  WebPageCacheDecisionKind,
  WebPageCacheRestoreType
} from '../web/WebPageCacheCoordinator';
import { WebRuntimeRetentionPlan } from '../web/WebRuntimePoolPolicy';
import { WebTabRuntimeRecord } from '../web/WebTabRuntime';
import { BrowserWindowNewEventConsumptionResult } from '../web/BrowserWebPageController';
import { BrowserSessionCoordinator } from './BrowserSessionCoordinator';
import { BrowserRuntimeStateTransitionTable } from './BrowserRuntimeStateTransitionTable';
import {
  BrowserSystemMemoryPressureLevel,
  BrowserTabAppLifecycleState,
  BrowserTabWindowVisibility
} from './BrowserTabBackgroundTypes';
import {
  BrowserColdTabMaterializeCoordinator,
  BrowserColdTabMaterializePlan
} from './BrowserColdTabMaterializeCoordinator';
import {
  BrowserMaterializationPolicy,
  DEFAULT_BROWSER_MATERIALIZATION_POLICY
} from './BrowserMaterializationPolicy';

export interface BrowserRuntimeSessionSyncResult {
  tabs: BrowserTabState[];
  retentionPlan: WebRuntimeRetentionPlan;
  cooledTabIds: string[];
  deferCooledRuntimeRelease: boolean;
  retentionStateChanged: boolean;
}

export interface BrowserRuntimeSessionSyncOptions {
  protectedReasonsByTabId?: Record<string, string>;
  deferCooledRuntimeRelease?: boolean;
  windowVisibility?: BrowserTabWindowVisibility;
  appLifecycle?: BrowserTabAppLifecycleState;
  systemMemoryPressureLevel?: BrowserSystemMemoryPressureLevel;
  materializationPolicy?: BrowserMaterializationPolicy;
}

export interface BrowserRuntimeSessionSyncHost {
  persistCoolingRuntimeSnapshot: (tabId: string, releaseHostedNodeAfterPersist: boolean) => void;
  applySessionSyncState: (tabs: BrowserTabState[], retentionPlan: WebRuntimeRetentionPlan) => void;
  recordRuntimeEvent: (type: string, message: string, tabId?: string) => void;
  pruneRuntimeTelemetry: (tabIds: string[]) => void;
}

export interface BrowserActiveRuntimeHost {
  detachHostedNode: () => void;
  clearControllerAttachment: () => void;
  attachHostedRuntime: (tab: BrowserTabState, runtime: WebTabRuntimeRecord) => boolean;
  applyRestoreTypeState: (tab: BrowserTabState, restoreType: WebPageCacheRestoreType) => void;
  refreshRuntimeRecords: (tabIds: string[]) => void;
  recordPageCacheDecision: (
    tab: BrowserTabState,
    runtime: WebTabRuntimeRecord,
    resolution: BrowserActiveRuntimeResolution
  ) => void;
  markControllerAttached: (tabId: string) => WebTabRuntimeRecord | undefined;
  applyLiveRuntimePresentation: (tab: BrowserTabState, helperMessage: string) => void;
  restoreActiveSession: (reason: TabRestoreReason) => void;
}

export interface BrowserActiveRuntimeResolution {
  activeTab?: BrowserTabState;
  runtime?: WebTabRuntimeRecord;
  materializePlan: BrowserColdTabMaterializePlan;
  shouldDetachHostedNode: boolean;
  shouldReuseLiveRuntime: boolean;
  shouldRestoreActiveSession: boolean;
  shouldWaitForControllerAttachRestore: boolean;
  restoreType: WebPageCacheRestoreType;
  pageCacheDecisionKind: WebPageCacheDecisionKind;
  pageCacheReasonCode: string;
  pageCacheDiagnosticLine: string;
  helperMessage: string;
}

export interface BrowserActiveRuntimeAttachmentResult {
  attached: boolean;
  shouldRestoreAfterAttachFallback: boolean;
  shouldRestoreSessionAfterAttachRetry: boolean;
  restoreReason: TabRestoreReason;
  diagnosticLine: string;
}

export interface BrowserControllerAttachmentResolution {
  activeTab?: BrowserTabState;
  runtime?: WebTabRuntimeRecord;
  shouldHandleAsActive: boolean;
  shouldRestoreAfterAttach: boolean;
  restoreReason: TabRestoreReason;
  targetUrl: string;
  userVisibleStatus: string;
}

export type BrowserControllerAttachmentWindowOpenConsumption =
  boolean |
  BrowserWindowNewEventConsumptionResult;

export interface BrowserControllerAttachmentOptions {
  windowOpenEventConsumedByPageController?: BrowserControllerAttachmentWindowOpenConsumption;
}

export interface BrowserControllerAttachmentHost {
  hasAttachedController: (tabId: string, runtime?: WebTabRuntimeRecord) => boolean;
  applyAttachFailure: (tabId: string, message: string, crashReason: TabCrashReason) => void;
  bootstrapAttachedController: (tabId: string, runtime?: WebTabRuntimeRecord) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
  appendRestoreTraceBreadcrumb: (tabId: string, breadcrumb: string) => void;
  activateAttachedController: (tabId: string, targetUrl: string, runtime?: WebTabRuntimeRecord) => boolean;
  setRestoreEventContext: (tabId: string, targetUrl: string) => void;
  releaseEventContext: (tabId: string) => void;
  restoreActiveSession: (reason: TabRestoreReason) => void;
  finalizeControllerAttachment: () => void;
}

export class BrowserRuntimeLifecycleCoordinator {
  private pageCacheCoordinator: WebPageCacheCoordinator = new WebPageCacheCoordinator();
  private runtimeStateTransitionTable: BrowserRuntimeStateTransitionTable = new BrowserRuntimeStateTransitionTable();
  private coldTabMaterializeCoordinator: BrowserColdTabMaterializeCoordinator = new BrowserColdTabMaterializeCoordinator();

  syncSession(
    sessionCoordinator: BrowserSessionCoordinator,
    tabManager: TabManager,
    tabs: BrowserTabState[],
    activeTabId: string,
    windowId: string,
    previousRetentionPlan: WebRuntimeRetentionPlan,
    options: BrowserRuntimeSessionSyncOptions = {}
  ): BrowserRuntimeSessionSyncResult {
    const previousRuntimeStates = JSON.stringify(previousRetentionPlan.runtimeStates);
    const previousDiscardReasons = JSON.stringify(previousRetentionPlan.discardReasonsByTabId);
    const previousMountedTabIds = previousRetentionPlan.mountedTabIds.slice();
    const materializationPolicy = options.materializationPolicy ?? DEFAULT_BROWSER_MATERIALIZATION_POLICY;
    const runtimeTabIds = this.syncTabRuntimesForPolicy(
      sessionCoordinator,
      tabs,
      activeTabId,
      windowId,
      materializationPolicy
    );
    sessionCoordinator.getRuntimeRegistry().pruneWindowRuntimes(windowId, runtimeTabIds);
    const activeTab = tabManager.getActiveTab(tabs, activeTabId);
    if (activeTab !== undefined && !activeTab.isHome) {
      sessionCoordinator.activateTab(activeTab, tabs, windowId, {
        materializationPolicy: materializationPolicy
      });
    }

    const retentionPlan = this.alignRetentionPlanWithMaterializedRuntimes(
      sessionCoordinator.buildRuntimeRetentionPlan(tabs, activeTabId, {
        protectedReasonsByTabId: options.protectedReasonsByTabId ?? {},
        windowVisibility: options.windowVisibility,
        appLifecycle: options.appLifecycle,
        systemMemoryPressureLevel: options.systemMemoryPressureLevel
      }),
      tabs,
      activeTabId,
      runtimeTabIds,
      materializationPolicy
    );
    sessionCoordinator.applyRuntimeRetentionPlan(retentionPlan);
    const cooledTabIds = previousMountedTabIds.filter((tabId: string) =>
      !retentionPlan.mountedTabIds.includes(tabId) && tabId !== activeTabId
    );
    const nextTabs = tabManager.applyRuntimeStates(tabs, retentionPlan.runtimeStates);
    return {
      tabs: nextTabs,
      retentionPlan: retentionPlan,
      cooledTabIds: cooledTabIds,
      deferCooledRuntimeRelease: options.deferCooledRuntimeRelease === true,
      retentionStateChanged: this.hasRetentionStateChanged(
        previousRuntimeStates,
        previousDiscardReasons,
        retentionPlan
      )
    };
  }

  private syncTabRuntimesForPolicy(
    sessionCoordinator: BrowserSessionCoordinator,
    tabs: BrowserTabState[],
    activeTabId: string,
    windowId: string,
    materializationPolicy: BrowserMaterializationPolicy
  ): string[] {
    const runtimeTabIds: string[] = [];
    tabs.forEach((tab: BrowserTabState) => {
      if (tab.isHome) {
        return;
      }
      const existingRuntime = sessionCoordinator.getRuntime(tab.id);
      const shouldEnsure = materializationPolicy === 'all' ||
        (materializationPolicy === 'active_only' && tab.id === activeTabId) ||
        existingRuntime !== undefined;
      if (!shouldEnsure) {
        return;
      }
      sessionCoordinator.ensureTabRuntime(tab, windowId);
      runtimeTabIds.push(tab.id);
    });
    return runtimeTabIds;
  }

  private alignRetentionPlanWithMaterializedRuntimes(
    retentionPlan: WebRuntimeRetentionPlan,
    tabs: BrowserTabState[],
    activeTabId: string,
    materializedTabIds: string[],
    materializationPolicy: BrowserMaterializationPolicy
  ): WebRuntimeRetentionPlan {
    if (materializationPolicy === 'all') {
      return retentionPlan;
    }
    const materializedByTabId: Record<string, boolean> = {};
    materializedTabIds.forEach((tabId: string) => {
      materializedByTabId[tabId] = true;
    });
    tabs.forEach((tab: BrowserTabState) => {
      if (tab.isHome || tab.id === activeTabId || materializedByTabId[tab.id] === true) {
        return;
      }
      this.removeTabId(retentionPlan.mountedTabIds, tab.id);
      this.removeTabId(retentionPlan.hotTabIds, tab.id);
      this.removeTabId(retentionPlan.warmTabIds, tab.id);
      this.removeTabId(retentionPlan.forcedDiscardTabIds, tab.id);
      this.syncDeferredWebStateRestoreCandidate(retentionPlan, tab);
      if (!retentionPlan.coldTabIds.includes(tab.id)) {
        retentionPlan.coldTabIds.push(tab.id);
      }
      retentionPlan.runtimeStates[tab.id] = this.resolveDeferredBackgroundRuntimeState(tab);
      retentionPlan.retentionReasonsByTabId[tab.id] =
        `后台标签页仅恢复 metadata，policy=${materializationPolicy}，未创建 live runtime。`;
      retentionPlan.discardReasonsByTabId[tab.id] = '';
      if (retentionPlan.retentionScoresByTabId[tab.id] === undefined) {
        retentionPlan.retentionScoresByTabId[tab.id] = 0;
      }
      if (retentionPlan.restorePrioritiesByTabId[tab.id] === undefined) {
        retentionPlan.restorePrioritiesByTabId[tab.id] = 0;
      }
    });
    this.sortWebStateRestoreCandidates(retentionPlan);
    return retentionPlan;
  }

  private syncDeferredWebStateRestoreCandidate(retentionPlan: WebRuntimeRetentionPlan, tab: BrowserTabState): void {
    if (tab.webStatePath.trim().length <= 0) {
      this.removeTabId(retentionPlan.webStateRestoreCandidateTabIds, tab.id);
      return;
    }
    if (!retentionPlan.webStateRestoreCandidateTabIds.includes(tab.id)) {
      retentionPlan.webStateRestoreCandidateTabIds.push(tab.id);
    }
  }

  private sortWebStateRestoreCandidates(retentionPlan: WebRuntimeRetentionPlan): void {
    retentionPlan.webStateRestoreCandidateTabIds = retentionPlan.webStateRestoreCandidateTabIds.sort(
      (left: string, right: string): number => {
        const priorityDelta = (retentionPlan.restorePrioritiesByTabId[right] ?? 0) -
          (retentionPlan.restorePrioritiesByTabId[left] ?? 0);
        if (priorityDelta !== 0) {
          return priorityDelta;
        }
        return left.localeCompare(right);
      }
    );
  }

  private resolveDeferredBackgroundRuntimeState(tab: BrowserTabState): TabRuntimeState {
    if (tab.runtimeState === 'error' || tab.runtimeState === 'crashed' || tab.runtimeState === 'discarded') {
      return tab.runtimeState;
    }
    return 'suspended';
  }

  private removeTabId(items: string[], tabId: string): void {
    let index = items.indexOf(tabId);
    while (index >= 0) {
      items.splice(index, 1);
      index = items.indexOf(tabId);
    }
  }

  applySessionSyncResult(result: BrowserRuntimeSessionSyncResult, host: BrowserRuntimeSessionSyncHost): void {
    // Keep the active tab on the live controller path; only cooled background tabs are snapshotted and released.
    if (!result.deferCooledRuntimeRelease) {
      result.cooledTabIds.forEach((tabId: string) => {
        host.persistCoolingRuntimeSnapshot(tabId, true);
      });
    }
    host.applySessionSyncState(result.tabs, result.retentionPlan);
    result.cooledTabIds.forEach((tabId: string) => {
      const reason = result.retentionPlan.retentionReasonsByTabId[tabId] ?? 'runtime 已冷却并写入快照';
      host.recordRuntimeEvent('runtime_cooled', reason, tabId);
    });
    result.retentionPlan.forcedDiscardTabIds.forEach((tabId: string) => {
      const reason = result.retentionPlan.retentionReasonsByTabId[tabId] ?? '超过强制 discard 阈值';
      host.recordRuntimeEvent('runtime_force_discard', reason, tabId);
    });
    const discardSummary = this.buildRuntimeDiscardSummary(result.retentionPlan);
    if (discardSummary.length > 0) {
      const discardSummaryTabId = this.resolveFirstDiscardedTabId(result.retentionPlan);
      host.recordRuntimeEvent('policy_runtime_discard_summary', discardSummary, discardSummaryTabId);
    }
    const pressureAssist = result.retentionPlan.pressureAssist;
    const pressureAidedTabId = pressureAssist?.warmTabIds[0] ?? pressureAssist?.mountedTabIds[0] ??
      result.retentionPlan.activeTabId;
    if (pressureAssist !== undefined && (pressureAssist.warmTabIds.length > 0 || pressureAssist.mountedTabIds.length > 0)) {
      host.recordRuntimeEvent('policy_runtime_retention_buffer', pressureAssist.summaryLine, pressureAidedTabId);
    }
    const siteComplexitySummary = result.retentionPlan.siteComplexitySummary;
    if (siteComplexitySummary !== undefined) {
      host.recordRuntimeEvent(
        'policy_runtime_site_complexity',
        siteComplexitySummary.summaryLine,
        siteComplexitySummary.topTabId
      );
    }
    if (result.retentionPlan.webStateRestoreCandidateTabIds.length > 0) {
      host.recordRuntimeEvent(
        'policy_web_state_restore_candidates',
        `mode=on_activation warmPreload=disabled candidates=${result.retentionPlan.webStateRestoreCandidateTabIds.join(' > ')}`,
        result.retentionPlan.webStateRestoreCandidateTabIds[0]
      );
    }
    host.pruneRuntimeTelemetry(result.tabs.map((tab: BrowserTabState) => tab.id));
  }

  private buildRuntimeDiscardSummary(retentionPlan: WebRuntimeRetentionPlan): string {
    const discardedTabIds = Object.keys(retentionPlan.discardReasonsByTabId).filter((tabId: string) => {
      return (retentionPlan.discardReasonsByTabId[tabId] ?? '').length > 0;
    });
    if (discardedTabIds.length === 0) {
      return '';
    }
    let retentionBudgetCount = 0;
    let retentionStaleCount = 0;
    let retentionColdCount = 0;
    discardedTabIds.forEach((tabId: string) => {
      const reason = retentionPlan.discardReasonsByTabId[tabId];
      if (reason === 'retention_budget') {
        retentionBudgetCount += 1;
        return;
      }
      if (reason === 'retention_stale') {
        retentionStaleCount += 1;
        return;
      }
      if (reason === 'retention_cold') {
        retentionColdCount += 1;
      }
    });
    const queuedDiscardCount = discardedTabIds.filter((tabId: string) => {
      return retentionPlan.webStateRestoreCandidateTabIds.includes(tabId);
    }).length;
    return `discardPolicy total=${discardedTabIds.length} budget=${retentionBudgetCount} stale=${retentionStaleCount} ` +
      `cold=${retentionColdCount} queued=${queuedDiscardCount} webStateRestoreCandidates=${retentionPlan.webStateRestoreCandidateTabIds.join(',') || 'none'} ` +
      `tabs=${discardedTabIds.join(',')}`;
  }

  private resolveFirstDiscardedTabId(retentionPlan: WebRuntimeRetentionPlan): string {
    return Object.keys(retentionPlan.discardReasonsByTabId).find((tabId: string) => {
      return (retentionPlan.discardReasonsByTabId[tabId] ?? '').length > 0;
    }) ?? retentionPlan.activeTabId;
  }

  runSessionSync(
    sessionCoordinator: BrowserSessionCoordinator,
    tabManager: TabManager,
    tabs: BrowserTabState[],
    activeTabId: string,
    windowId: string,
    previousRetentionPlan: WebRuntimeRetentionPlan,
    host: BrowserRuntimeSessionSyncHost,
    options: BrowserRuntimeSessionSyncOptions = {}
  ): BrowserRuntimeSessionSyncResult {
    const result = this.syncSession(
      sessionCoordinator,
      tabManager,
      tabs,
      activeTabId,
      windowId,
      previousRetentionPlan,
      options
    );
    this.applySessionSyncResult(result, host);
    return result;
  }

  refreshTabRuntime(
    sessionCoordinator: BrowserSessionCoordinator,
    tab: BrowserTabState | undefined,
    windowId: string,
    tabIdWhenMissing: string = ''
  ): WebTabRuntimeRecord | undefined {
    if (tab === undefined) {
      if (tabIdWhenMissing.length > 0) {
        sessionCoordinator.removeTab(tabIdWhenMissing);
      }
      return undefined;
    }
    if (tab.isHome) {
      sessionCoordinator.removeTab(tab.id);
      return undefined;
    }
    return sessionCoordinator.ensureTabRuntime(tab, windowId).runtime;
  }

  refreshTabRuntimes(
    sessionCoordinator: BrowserSessionCoordinator,
    tabs: BrowserTabState[],
    tabIds: string[],
    windowId: string
  ): void {
    tabIds.forEach((tabId: string) => {
      const tab = tabs.find((candidate: BrowserTabState) => candidate.id === tabId);
      this.refreshTabRuntime(sessionCoordinator, tab, windowId, tabId);
    });
  }

  resolveActiveRuntime(
    sessionCoordinator: BrowserSessionCoordinator,
    tabManager: TabManager,
    tabs: BrowserTabState[],
    activeTabId: string,
    windowId: string,
    showHomePage: boolean
  ): BrowserActiveRuntimeResolution {
    const activeTab = tabManager.getActiveTab(tabs, activeTabId);
    if (showHomePage || activeTab === undefined || activeTab.isHome) {
      return {
        activeTab: activeTab,
        runtime: undefined,
        materializePlan: this.buildNoMaterializePlan(),
        shouldDetachHostedNode: true,
        shouldReuseLiveRuntime: false,
        shouldRestoreActiveSession: false,
        shouldWaitForControllerAttachRestore: false,
        restoreType: 'none',
        pageCacheDecisionKind: 'none',
        pageCacheReasonCode: 'home_or_missing_active_tab',
        pageCacheDiagnosticLine: 'decision=none reason=home_or_missing_active_tab restoreType=none',
        helperMessage: ''
      };
    }

    const runtime = sessionCoordinator.ensureTabRuntime(activeTab, windowId).runtime;
    const activationPlan = this.pageCacheCoordinator.resolveActivation(activeTab, runtime);
    const materializePlan = this.coldTabMaterializeCoordinator.buildMaterializePlan(
      activeTab,
      runtime,
      activationPlan,
      'tab_switch'
    );
    return {
      activeTab: activeTab,
      runtime: runtime,
      materializePlan: materializePlan,
      shouldDetachHostedNode: false,
      shouldReuseLiveRuntime: activationPlan.shouldReuseLiveRuntime,
      shouldRestoreActiveSession: activationPlan.shouldRestoreActiveSession,
      shouldWaitForControllerAttachRestore: !runtime.hasLiveController,
      restoreType: activationPlan.restoreType,
      pageCacheDecisionKind: activationPlan.decisionKind,
      pageCacheReasonCode: activationPlan.reasonCode,
      pageCacheDiagnosticLine: activationPlan.diagnosticLine,
      helperMessage: activationPlan.helperMessage
    };
  }

  applyResolvedActiveRuntime(
    resolution: BrowserActiveRuntimeResolution,
    host: BrowserActiveRuntimeHost
  ): BrowserActiveRuntimeAttachmentResult {
    if (resolution.shouldDetachHostedNode) {
      host.detachHostedNode();
      host.clearControllerAttachment();
      return this.buildActiveRuntimeAttachmentResult(false, false, false, 'tab_switch', 'detached');
    }
    const activeTab = resolution.activeTab;
    const runtime = resolution.runtime;
    if (activeTab === undefined || runtime === undefined) {
      host.detachHostedNode();
      host.clearControllerAttachment();
      return this.buildActiveRuntimeAttachmentResult(false, false, false, 'tab_switch', 'missing_active_runtime');
    }
    const attached = host.attachHostedRuntime(activeTab, runtime);
    if (attached && resolution.shouldWaitForControllerAttachRestore) {
      return this.buildActiveRuntimeAttachmentResult(
        attached,
        true,
        true,
        resolution.materializePlan.shouldMaterialize ? resolution.materializePlan.restoreReason : 'controller_attach',
        `await_controller_attach_callback state=${activeTab.runtimeState} restoreType=${resolution.restoreType} ` +
          resolution.materializePlan.diagnosticLine
      );
    }
    return this.buildActiveRuntimeAttachmentResult(
      attached,
      false,
      this.shouldRestoreSessionAfterAttachRetry(activeTab, resolution),
      resolution.materializePlan.shouldMaterialize ? resolution.materializePlan.restoreReason : 'tab_switch',
      attached ? resolution.materializePlan.diagnosticLine : `attach_pending ${resolution.materializePlan.diagnosticLine}`
    );
  }

  runActiveRuntime(
    sessionCoordinator: BrowserSessionCoordinator,
    tabManager: TabManager,
    tabs: BrowserTabState[],
    activeTabId: string,
    windowId: string,
    showHomePage: boolean,
    host: BrowserActiveRuntimeHost
  ): BrowserActiveRuntimeResolution {
    const resolution = this.resolveActiveRuntime(
      sessionCoordinator,
      tabManager,
      tabs,
      activeTabId,
      windowId,
      showHomePage
    );
    this.applyResolvedActiveRuntime(resolution, host);
    return resolution;
  }

  applyResolvedActiveRuntimeAfterSwitch(
    resolution: BrowserActiveRuntimeResolution,
    host: BrowserActiveRuntimeHost
  ): BrowserActiveRuntimeAttachmentResult {
    const attachment = this.applyResolvedActiveRuntime(resolution, host);
    if (resolution.shouldWaitForControllerAttachRestore) {
      return attachment;
    }
    this.applyActiveRuntimeRestorePlan(
      resolution,
      host,
      resolution.materializePlan.shouldMaterialize ? resolution.materializePlan.restoreReason : 'tab_switch'
    );
    return attachment;
  }

  private applyActiveRuntimeRestorePlan(
    resolution: BrowserActiveRuntimeResolution,
    host: BrowserActiveRuntimeHost,
    restoreReason: TabRestoreReason
  ): void {
    const activeTab = resolution.activeTab;
    const runtime = resolution.runtime;
    if (resolution.shouldDetachHostedNode || activeTab === undefined || runtime === undefined) {
      return;
    }
    host.applyRestoreTypeState(activeTab, resolution.restoreType);
    host.refreshRuntimeRecords([activeTab.id]);
    host.recordPageCacheDecision(activeTab, runtime, resolution);
    if (resolution.shouldReuseLiveRuntime) {
      host.applyLiveRuntimePresentation(activeTab, resolution.helperMessage);
      return;
    }
    if (resolution.shouldRestoreActiveSession) {
      host.restoreActiveSession(restoreReason);
    }
  }

  runActiveRuntimeAfterSwitch(
    sessionCoordinator: BrowserSessionCoordinator,
    tabManager: TabManager,
    tabs: BrowserTabState[],
    activeTabId: string,
    windowId: string,
    showHomePage: boolean,
    host: BrowserActiveRuntimeHost
  ): BrowserActiveRuntimeAttachmentResult {
    const resolution = this.resolveActiveRuntime(
      sessionCoordinator,
      tabManager,
      tabs,
      activeTabId,
      windowId,
      showHomePage
    );
    return this.applyResolvedActiveRuntimeAfterSwitch(resolution, host);
  }

  resolveControllerAttachment(
    sessionCoordinator: BrowserSessionCoordinator,
    tabManager: TabManager,
    tabs: BrowserTabState[],
    activeTabId: string,
    tabId: string,
    showHomePage: boolean,
    options: BrowserControllerAttachmentOptions = {}
  ): BrowserControllerAttachmentResolution {
    const runtimeBeforeAttach = sessionCoordinator.getRuntime(tabId);
    const isWindowOpenHandoff = this.resolveWindowOpenHandoffForControllerAttach(
      sessionCoordinator,
      tabId,
      options.windowOpenEventConsumedByPageController
    );
    const runtime = sessionCoordinator.markTabControllerAttached(tabId);
    const activeTab = tabManager.getActiveTab(tabs, activeTabId);
    const shouldHandleAsActive = !showHomePage &&
      activeTab !== undefined &&
      !activeTab.isHome &&
      activeTab.id === tabId;
    const shouldRestoreAfterAttach = shouldHandleAsActive &&
      !isWindowOpenHandoff &&
      this.shouldRestoreAfterControllerAttach(runtimeBeforeAttach, activeTab);
    const targetUrl = shouldHandleAsActive
      ? (activeTab?.pendingUrl.length ?? 0) > 0
        ? activeTab?.pendingUrl ?? ''
        : activeTab?.url ?? ''
      : '';
    return {
      activeTab: activeTab,
      runtime: runtime,
      shouldHandleAsActive: shouldHandleAsActive,
      shouldRestoreAfterAttach: shouldRestoreAfterAttach,
      restoreReason: shouldRestoreAfterAttach
        ? this.coldTabMaterializeCoordinator.resolveControllerAttachRestoreReason(activeTab, 'controller_attach')
        : 'controller_attach',
      targetUrl: targetUrl,
      userVisibleStatus: shouldHandleAsActive
        ? shouldRestoreAfterAttach
          ? isWindowOpenHandoff
            ? '新窗口 Web 控制器已接管，准备加载目标页面。'
            : 'Web 控制器已附着，准备恢复标签页。'
          : 'Web 控制器已重新挂载，保留当前页面现场。'
        : '后台 Web 控制器已附着。'
    };
  }

  applyResolvedControllerAttachment(
    tabId: string,
    resolution: BrowserControllerAttachmentResolution,
    host: BrowserControllerAttachmentHost
  ): void {
    if (!host.hasAttachedController(tabId, resolution.runtime)) {
      host.applyAttachFailure(tabId, 'Web 控制器附着失败。', 'unknown');
      return;
    }
    host.bootstrapAttachedController(tabId, resolution.runtime);
    host.recordRuntimeEvent('controller_attached', 'web controller 已附着', tabId);
    host.appendRestoreTraceBreadcrumb(tabId, 'controller_attached');
    if (!resolution.shouldHandleAsActive) {
      return;
    }
    const controllerActivated = host.activateAttachedController(tabId, resolution.targetUrl, resolution.runtime);
    if (!controllerActivated) {
      host.applyAttachFailure(tabId, 'Web 控制器激活失败。', 'unknown');
      return;
    }
    if (resolution.shouldRestoreAfterAttach) {
      host.setRestoreEventContext(tabId, resolution.targetUrl);
      host.recordRuntimeEvent('controller_attach_restore_plan', resolution.userVisibleStatus, tabId);
      host.restoreActiveSession(resolution.restoreReason);
    } else {
      host.releaseEventContext(tabId);
      host.recordRuntimeEvent('controller_attach_live_preserved', resolution.userVisibleStatus, tabId);
    }
    host.finalizeControllerAttachment();
  }

  runControllerAttachment(
    sessionCoordinator: BrowserSessionCoordinator,
    tabManager: TabManager,
    tabs: BrowserTabState[],
    activeTabId: string,
    tabId: string,
    showHomePage: boolean,
    host: BrowserControllerAttachmentHost,
    options: BrowserControllerAttachmentOptions = {}
  ): BrowserControllerAttachmentResolution {
    const resolution = this.resolveControllerAttachment(
      sessionCoordinator,
      tabManager,
      tabs,
      activeTabId,
      tabId,
      showHomePage,
      options
    );
    this.applyResolvedControllerAttachment(tabId, resolution, host);
    return resolution;
  }

  private shouldRestoreAfterControllerAttach(
    runtimeBeforeAttach: WebTabRuntimeRecord | undefined,
    activeTab: BrowserTabState | undefined
  ): boolean {
    if (runtimeBeforeAttach === undefined || activeTab === undefined) {
      return true;
    }
    if (!runtimeBeforeAttach.hasLiveController) {
      return true;
    }
    return this.isRestoreRequiredAttachState(runtimeBeforeAttach.state) ||
      this.isRestoreRequiredAttachState(activeTab.runtimeState);
  }

  private resolveWindowOpenHandoffForControllerAttach(
    sessionCoordinator: BrowserSessionCoordinator,
    tabId: string,
    eventConsumption: BrowserControllerAttachmentWindowOpenConsumption | undefined
  ): boolean {
    if (eventConsumption === undefined) {
      return sessionCoordinator.consumeTabWindowOpenHandoffPending(tabId);
    }
    if (typeof eventConsumption === 'boolean') {
      return eventConsumption || sessionCoordinator.consumeTabWindowOpenHandoffPending(tabId);
    }
    const legacyPendingHandoff = sessionCoordinator.consumeTabWindowOpenHandoffPending(tabId);
    if (eventConsumption.eventFound) {
      return eventConsumption.shouldTreatAsWindowOpenHandoff;
    }
    return legacyPendingHandoff;
  }

  private isRestoreRequiredAttachState(state: TabRuntimeState): boolean {
    return this.runtimeStateTransitionTable.shouldRestoreAfterControllerAttach(state);
  }

  private shouldRestoreSessionAfterAttachRetry(
    activeTab: BrowserTabState,
    resolution: BrowserActiveRuntimeResolution
  ): boolean {
    if (resolution.shouldReuseLiveRuntime) {
      return false;
    }
    if (resolution.shouldRestoreActiveSession) {
      return true;
    }
    return this.isRestoreRequiredAttachState(activeTab.runtimeState) &&
      (resolution.restoreType === 'reload' || resolution.restoreType === 'snapshot_restore');
  }

  private buildNoMaterializePlan(): BrowserColdTabMaterializePlan {
    return {
      shouldMaterialize: false,
      reasonCode: 'none',
      restoreReason: 'tab_switch',
      diagnosticLine: 'materialize=0 reason=none restoreReason=tab_switch'
    };
  }

  private buildActiveRuntimeAttachmentResult(
    attached: boolean,
    shouldRestoreAfterAttachFallback: boolean,
    shouldRestoreSessionAfterAttachRetry: boolean,
    restoreReason: TabRestoreReason,
    diagnosticLine: string
  ): BrowserActiveRuntimeAttachmentResult {
    return {
      attached: attached,
      shouldRestoreAfterAttachFallback: shouldRestoreAfterAttachFallback,
      shouldRestoreSessionAfterAttachRetry: shouldRestoreSessionAfterAttachRetry,
      restoreReason: restoreReason,
      diagnosticLine: diagnosticLine
    };
  }

  private hasRetentionStateChanged(
    previousRuntimeStates: string,
    previousDiscardReasons: string,
    nextRetentionPlan: WebRuntimeRetentionPlan
  ): boolean {
    return previousRuntimeStates !== JSON.stringify(nextRetentionPlan.runtimeStates) ||
      previousDiscardReasons !== JSON.stringify(nextRetentionPlan.discardReasonsByTabId);
  }

}
