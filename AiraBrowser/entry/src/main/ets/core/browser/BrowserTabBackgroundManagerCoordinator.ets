import { TabDiscardReason, TabRestoreReason, TabRuntimeState } from '../../common/models/BrowserModels';
import { BrowserTabState, BrowserTabManagerPort, TabManager } from '../tabs/TabManager';
import { WebRuntimeRetentionPlan } from '../web/WebRuntimePoolPolicy';
import {
  BrowserRuntimeLifecycleCoordinator,
  BrowserRuntimeSessionSyncHost,
  BrowserRuntimeSessionSyncResult
} from './BrowserRuntimeLifecycleCoordinator';
import {
  BrowserRuntimeProtectionPlanInput,
  BrowserRuntimeProtectionSummary,
  BrowserRuntimeTransactionSignalService
} from './BrowserRuntimeTransactionSignalService';
import { BrowserSessionCoordinator } from './BrowserSessionCoordinator';
import {
  BrowserTabBackgroundQueueCoordinator
} from './BrowserTabBackgroundQueueCoordinator';
import {
  BROWSER_TAB_BACKGROUND_POLICY_VERSION,
  BrowserTabBackgroundDiscardGateSummary,
  BrowserTabDiscardQueueSummary,
  BrowserTabDiscardReasonCountSummary,
  BrowserTabBackgroundManagerInput,
  BrowserTabBackgroundPlan,
  BrowserTabBackgroundTrigger,
  BrowserTabDiscardTask,
  BrowserTabPageBehaviorPrioritySummary,
  BrowserTabPageBehaviorState,
  BrowserTabPageBehaviorSummary,
  BrowserTabPreviewAssetState,
  BrowserTabPreviewAssetSummary,
  BrowserTabRuntimeStateCountSummary,
  BrowserTabWebStateRestoreCandidate,
  BrowserSystemMemoryPressureLevel,
  BrowserSystemMemoryPressureSnapshot,
  BrowserTabWindowState
} from './BrowserTabBackgroundTypes';
import { BrowserSystemMemoryPressureSignal } from './BrowserSystemMemoryPressureSignal';
import {
  BrowserMaterializationPolicy,
  DEFAULT_BROWSER_MATERIALIZATION_POLICY
} from './BrowserMaterializationPolicy';

const SYSTEM_MEMORY_PRESSURE_TTL_MS: number = 2 * 60 * 1000;
const PREVIEW_MISSING_DISCARD_PRIORITY_PENALTY: number = 250;

export interface BrowserTabBackgroundSessionSyncRequest {
  sessionCoordinator: BrowserSessionCoordinator;
  runtimeLifecycleCoordinator: BrowserRuntimeLifecycleCoordinator;
  tabManager: BrowserTabManagerPort;
  tabs: BrowserTabState[];
  activeTabId: string;
  windowId: string;
  previousRetentionPlan: WebRuntimeRetentionPlan;
  host: BrowserRuntimeSessionSyncHost;
  trigger?: BrowserTabBackgroundTrigger;
  windowState?: BrowserTabWindowState;
  activeDownloadCount: number;
  explicitProtectionReasonsByTabId: Record<string, string>;
  pageBehaviorByTabId?: Record<string, BrowserTabPageBehaviorState>;
  previewAssetsByTabId?: Record<string, BrowserTabPreviewAssetState>;
  systemMemoryPressure?: BrowserSystemMemoryPressureSnapshot;
  materializationPolicy?: BrowserMaterializationPolicy;
  resolveDiscardQueueTab?: (tabId: string) => BrowserTabState | undefined;
  executeDiscardTask?: (task: BrowserTabDiscardTask) => void;
  recordDiscardQueueRuntimeEvent?: (type: string, message: string, tabId: string) => void;
}

export interface BrowserTabBackgroundSessionSyncResult {
  lifecycleResult: BrowserRuntimeSessionSyncResult;
  plan: BrowserTabBackgroundPlan;
  protectionSummary: BrowserRuntimeProtectionSummary;
  input: BrowserTabBackgroundManagerInput;
}

export class BrowserTabBackgroundManagerCoordinator {
  private runtimeTransactionSignalService: BrowserRuntimeTransactionSignalService =
    new BrowserRuntimeTransactionSignalService();
  private discardQueueCoordinator: BrowserTabBackgroundQueueCoordinator = new BrowserTabBackgroundQueueCoordinator();

  runSessionSync(request: BrowserTabBackgroundSessionSyncRequest): BrowserTabBackgroundSessionSyncResult {
    const trigger = request.trigger ?? 'session_sync';
    const windowState = request.windowState ?? this.buildDefaultWindowState(request.windowId);
    const now = Date.now();
    const systemMemoryPressure = this.resolveEffectiveSystemMemoryPressure(
      request.systemMemoryPressure ?? BrowserSystemMemoryPressureSignal.buildInitialSnapshot(),
      now
    );
    const previewAssetsByTabId = request.previewAssetsByTabId ?? {};
    const explicitProtectionReasonsByTabId = this.mergeProtectionReasons(
      request.explicitProtectionReasonsByTabId,
      this.buildDiscardGateProtectionReasons(request.tabs, request.activeTabId)
    );
    const protectionInput: BrowserRuntimeProtectionPlanInput = {
      tabs: request.tabs,
      activeTabId: request.activeTabId,
      activeDownloadCount: request.activeDownloadCount,
      explicitReasonsByTabId: explicitProtectionReasonsByTabId,
      pageBehaviorByTabId: request.pageBehaviorByTabId ?? {}
    };
    const protectedReasonsByTabId = this.runtimeTransactionSignalService.buildProtectionReasons(protectionInput);
    const protectionSummary = this.runtimeTransactionSignalService.buildProtectionSummary(protectionInput);
    if (protectionSummary.total > 0) {
      request.host.recordRuntimeEvent(
        'policy_runtime_protection_summary',
        protectionSummary.summaryLine,
        protectionSummary.tabIds[0]
      );
    }
    const materializationPolicy = request.materializationPolicy ?? DEFAULT_BROWSER_MATERIALIZATION_POLICY;

    const lifecycleResult = request.runtimeLifecycleCoordinator.runSessionSync(
      request.sessionCoordinator,
      request.tabManager as TabManager,
      request.tabs,
      request.activeTabId,
      request.windowId,
      request.previousRetentionPlan,
      request.host,
      {
        protectedReasonsByTabId: protectedReasonsByTabId,
        deferCooledRuntimeRelease: this.hasDiscardQueueExecutor(request),
        windowVisibility: windowState.visibility,
        appLifecycle: windowState.appLifecycle,
        systemMemoryPressureLevel: systemMemoryPressure.level,
        materializationPolicy: materializationPolicy
      }
    );
    const input: BrowserTabBackgroundManagerInput = {
      windowId: request.windowId,
      activeTabId: request.activeTabId,
      tabs: request.tabs,
      runtimes: request.sessionCoordinator.listWindowRuntimes(request.windowId),
      trigger: trigger,
      windowState: windowState,
      activeDownloadCount: request.activeDownloadCount,
      explicitProtectionReasonsByTabId: explicitProtectionReasonsByTabId,
      pageBehaviorByTabId: request.pageBehaviorByTabId ?? {},
      protectedReasonsByTabId: protectedReasonsByTabId,
      previewAssetsByTabId: previewAssetsByTabId,
      systemMemoryPressure: systemMemoryPressure,
      now: now
    };
    const plan = this.buildPlanFromRetentionPlan(
      lifecycleResult.retentionPlan,
      protectedReasonsByTabId,
      input
    );
    this.recordProtectionContractViolations(request, plan, protectionSummary, protectedReasonsByTabId);
    request.host.recordRuntimeEvent(
      'tab_background_plan',
      this.buildPlanSummary(trigger, windowState, plan, materializationPolicy),
      plan.activeTabId
    );
    if (this.hasDiscardQueueExecutor(request) &&
      request.executeDiscardTask !== undefined &&
      request.recordDiscardQueueRuntimeEvent !== undefined) {
      this.discardQueueCoordinator.syncDiscardQueue({
        tasks: plan.discardQueue,
        tabs: lifecycleResult.tabs,
        activeTabId: request.activeTabId,
        protectedReasonsByTabId: protectedReasonsByTabId,
        executableTabIds: lifecycleResult.cooledTabIds,
        resolveTab: request.resolveDiscardQueueTab,
        executeDiscardTask: request.executeDiscardTask,
        recordRuntimeEvent: request.recordDiscardQueueRuntimeEvent,
        maxPendingTasks: this.resolveDiscardQueueMaxPendingTasks(plan.systemMemoryPressureLevel)
      });
    }
    return {
      lifecycleResult: lifecycleResult,
      plan: plan,
      protectionSummary: protectionSummary,
      input: input
    };
  }

  private buildDefaultWindowState(windowId: string): BrowserTabWindowState {
    return {
      windowId: windowId,
      visibility: 'active',
      isCurrentWindow: true,
      appLifecycle: 'foreground'
    };
  }

  private hasDiscardQueueExecutor(request: BrowserTabBackgroundSessionSyncRequest): boolean {
    return request.executeDiscardTask !== undefined && request.recordDiscardQueueRuntimeEvent !== undefined;
  }

  private mergeProtectionReasons(
    primaryReasonsByTabId: Record<string, string>,
    fallbackReasonsByTabId: Record<string, string>
  ): Record<string, string> {
    const merged: Record<string, string> = {};
    Object.keys(primaryReasonsByTabId).forEach((tabId: string) => {
      const reason = primaryReasonsByTabId[tabId] ?? '';
      if (reason.length > 0) {
        merged[tabId] = reason;
      }
    });
    Object.keys(fallbackReasonsByTabId).forEach((tabId: string) => {
      if ((merged[tabId] ?? '').length > 0) {
        return;
      }
      const reason = fallbackReasonsByTabId[tabId] ?? '';
      if (reason.length > 0) {
        merged[tabId] = reason;
      }
    });
    return merged;
  }

  private buildDiscardGateProtectionReasons(
    tabs: BrowserTabState[],
    activeTabId: string
  ): Record<string, string> {
    const reasons: Record<string, string> = {};
    tabs.forEach((tab: BrowserTabState) => {
      if (!this.shouldProtectFromDiscardForMissingRestoreTarget(tab, activeTabId)) {
        return;
      }
      reasons[tab.id] = '后台回收保护：缺少 WebState 且没有可靠 reload target。 gate=no_web_state';
    });
    return reasons;
  }

  private shouldProtectFromDiscardForMissingRestoreTarget(tab: BrowserTabState, activeTabId: string): boolean {
    if (tab.isHome || tab.id === activeTabId || tab.webStatePath.trim().length > 0) {
      return false;
    }
    if (tab.runtimeState === 'cold' || tab.runtimeState === 'discarded' || tab.runtimeState === 'suspended') {
      return false;
    }
    return !this.hasReliableReloadTarget(tab);
  }

  private hasReliableReloadTarget(tab: BrowserTabState): boolean {
    if (this.isReliableReloadTargetUrl(tab.lastRestorableUrl)) {
      return true;
    }
    if (this.isReliableReloadTargetUrl(tab.lastGoodUrl)) {
      return true;
    }
    if (this.isReliableReloadTargetUrl(tab.pendingUrl)) {
      return true;
    }
    if (this.isReliableReloadTargetUrl(tab.url)) {
      return true;
    }
    return tab.navigationHistory.some((url: string): boolean => this.isReliableReloadTargetUrl(url));
  }

  private isReliableReloadTargetUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') ||
      normalized.startsWith('https://') ||
      normalized.startsWith('file://');
  }

  private resolveEffectiveSystemMemoryPressure(
    snapshot: BrowserSystemMemoryPressureSnapshot,
    now: number
  ): BrowserSystemMemoryPressureSnapshot {
    if (snapshot.updatedAt <= 0 || snapshot.level === 'normal') {
      return snapshot;
    }
    if (now - snapshot.updatedAt <= SYSTEM_MEMORY_PRESSURE_TTL_MS) {
      return snapshot;
    }
    return {
      level: 'normal',
      revision: snapshot.revision,
      updatedAt: snapshot.updatedAt,
      source: `${snapshot.source}:expired`,
      rawLevel: snapshot.rawLevel
    };
  }

  private buildPlanFromRetentionPlan(
    retentionPlan: WebRuntimeRetentionPlan,
    protectedReasonsByTabId: Record<string, string>,
    input: BrowserTabBackgroundManagerInput
  ): BrowserTabBackgroundPlan {
    const protectedTabIds = Object.keys(protectedReasonsByTabId);
    const discardQueue = this.buildDiscardQueue(retentionPlan, input);
    const webStateRestoreCandidates = this.buildWebStateRestoreCandidates(retentionPlan, input);
    return {
      activeTabId: retentionPlan.activeTabId,
      protectedTabIds: protectedTabIds,
      liveTabIds: retentionPlan.mountedTabIds.slice(),
      hotTabIds: retentionPlan.hotTabIds.slice(),
      warmTabIds: retentionPlan.warmTabIds.slice(),
      suspendedTabIds: retentionPlan.coldTabIds.slice(),
      discardQueue: discardQueue,
      webStateRestoreCandidates: webStateRestoreCandidates,
      runtimeStatePatchByTabId: retentionPlan.runtimeStates,
      reasonsByTabId: retentionPlan.retentionReasonsByTabId,
      pageBehaviorSummary: this.buildPageBehaviorSummary(input.pageBehaviorByTabId),
      previewAssetSummary: this.buildPreviewAssetSummary(input),
      discardGateSummary: this.buildDiscardGateSummary(protectedReasonsByTabId, discardQueue, input),
      systemMemoryPressureLevel: input.systemMemoryPressure.level
    };
  }

  private recordProtectionContractViolations(
    request: BrowserTabBackgroundSessionSyncRequest,
    plan: BrowserTabBackgroundPlan,
    protectionSummary: BrowserRuntimeProtectionSummary,
    protectedReasonsByTabId: Record<string, string>
  ): void {
    Object.keys(protectedReasonsByTabId).forEach((tabId: string) => {
      const protectedReason = protectedReasonsByTabId[tabId] ?? '';
      const discardTask = plan.discardQueue.find((task: BrowserTabDiscardTask): boolean => task.tabId === tabId);
      if (discardTask !== undefined) {
        this.recordProtectionContractViolation(
          request,
          tabId,
          `reason=protected_discard_queued discardReason=${discardTask.reason} priority=${discardTask.priority} ` +
            `protectedReason=${protectedReason}`
        );
      }
      const runtimeState = plan.runtimeStatePatchByTabId[tabId];
      if (this.isProtectedRuntimeTerminalState(runtimeState)) {
        this.recordProtectionContractViolation(
          request,
          tabId,
          `reason=protected_runtime_terminal_state runtimeState=${runtimeState} protectedReason=${protectedReason}`
        );
      }
    });
    plan.pageBehaviorSummary.protectedTabIds.forEach((tabId: string) => {
      if ((protectedReasonsByTabId[tabId] ?? '').length > 0) {
        return;
      }
      this.recordProtectionContractViolation(
        request,
        tabId,
        `reason=page_behavior_missing_runtime_protection behaviorSignals=${plan.pageBehaviorSummary.maxBehaviorSignals}`
      );
    });
    protectionSummary.tabIds.forEach((tabId: string) => {
      if ((protectedReasonsByTabId[tabId] ?? '').length > 0) {
        return;
      }
      this.recordProtectionContractViolation(
        request,
        tabId,
        'reason=protection_summary_missing_runtime_reason'
      );
    });
  }

  private isProtectedRuntimeTerminalState(state: TabRuntimeState | undefined): boolean {
    return state === 'cold' || state === 'discarded' || state === 'suspended';
  }

  private recordProtectionContractViolation(
    request: BrowserTabBackgroundSessionSyncRequest,
    tabId: string,
    detail: string
  ): void {
    request.host.recordRuntimeEvent(
      'policy_background_contract_violation',
      `policyVersion=${BROWSER_TAB_BACKGROUND_POLICY_VERSION} ${detail}`,
      tabId
    );
  }

  private buildDiscardQueue(
    retentionPlan: WebRuntimeRetentionPlan,
    input: BrowserTabBackgroundManagerInput
  ): BrowserTabDiscardTask[] {
    const tasks: BrowserTabDiscardTask[] = [];
    Object.keys(retentionPlan.discardReasonsByTabId).forEach((tabId: string) => {
      const reason = retentionPlan.discardReasonsByTabId[tabId] ?? '';
      if (reason.length === 0) {
        return;
      }
      tasks.push({
        tabId: tabId,
        reason: reason as TabDiscardReason,
        priority: this.resolveDiscardTaskPriority(tabId, retentionPlan.retentionScoresByTabId[tabId] ?? 0, input),
        queuedAt: input.now
      });
    });
    return tasks.sort((left: BrowserTabDiscardTask, right: BrowserTabDiscardTask) => {
      if (left.priority !== right.priority) {
        return left.priority - right.priority;
      }
      return left.tabId.localeCompare(right.tabId);
    });
  }

  private resolveDiscardTaskPriority(
    tabId: string,
    basePriority: number,
    input: BrowserTabBackgroundManagerInput
  ): number {
    if (!this.shouldDeferDiscardForMissingPreview(tabId, input)) {
      return basePriority;
    }
    return basePriority + PREVIEW_MISSING_DISCARD_PRIORITY_PENALTY;
  }

  private shouldDeferDiscardForMissingPreview(
    tabId: string,
    input: BrowserTabBackgroundManagerInput
  ): boolean {
    if (input.systemMemoryPressure.level === 'critical') {
      return false;
    }
    const asset = input.previewAssetsByTabId[tabId];
    return asset?.hasDisplayablePreview !== true;
  }

  private buildDiscardGateSummary(
    protectedReasonsByTabId: Record<string, string>,
    discardQueue: BrowserTabDiscardTask[],
    input: BrowserTabBackgroundManagerInput
  ): BrowserTabBackgroundDiscardGateSummary {
    const protectedTabIds: string[] = [];
    let protectedNoWebStateCount = 0;
    Object.keys(protectedReasonsByTabId).forEach((tabId: string) => {
      const reason = protectedReasonsByTabId[tabId] ?? '';
      if (reason.indexOf('gate=no_web_state') >= 0) {
        protectedTabIds.push(tabId);
        protectedNoWebStateCount += 1;
      }
    });
    const previewDeferredTabIds = discardQueue
      .filter((task: BrowserTabDiscardTask): boolean => this.shouldDeferDiscardForMissingPreview(task.tabId, input))
      .map((task: BrowserTabDiscardTask): string => task.tabId);
    return {
      protectedTabIds: protectedTabIds,
      protectedNoWebStateCount: protectedNoWebStateCount,
      previewDeferredTabIds: previewDeferredTabIds
    };
  }

  private buildWebStateRestoreCandidates(
    retentionPlan: WebRuntimeRetentionPlan,
    input: BrowserTabBackgroundManagerInput
  ): BrowserTabWebStateRestoreCandidate[] {
    const tabById: Record<string, BrowserTabState | undefined> = {};
    input.tabs.forEach((tab: BrowserTabState) => {
      tabById[tab.id] = tab;
    });
    return retentionPlan.webStateRestoreCandidateTabIds
      .filter((tabId: string): boolean => {
        const tab = tabById[tabId];
        return tab !== undefined && !tab.isHome && tab.webStatePath.trim().length > 0;
      })
      .map((tabId: string): BrowserTabWebStateRestoreCandidate => {
        return {
          tabId: tabId,
          reason: 'discard_restore' as TabRestoreReason,
          priority: retentionPlan.restorePrioritiesByTabId[tabId] ?? 0,
          queuedAt: input.now
        };
      });
  }

  private buildPlanSummary(
    trigger: BrowserTabBackgroundTrigger,
    windowState: BrowserTabWindowState,
    plan: BrowserTabBackgroundPlan,
    materializationPolicy: BrowserMaterializationPolicy
  ): string {
    const previewSummary = plan.previewAssetSummary;
    const runtimeStateCounts = this.buildRuntimeStateCountSummary(plan);
    const queueSummary = this.buildDiscardQueueSummary(plan.discardQueue);
    const discardGateSummary = plan.discardGateSummary;
    return `trigger=${trigger} window=${windowState.windowId} visibility=${windowState.visibility} ` +
      `app=${windowState.appLifecycle} current=${windowState.isCurrentWindow ? 'true' : 'false'} ` +
      `memoryPressure=${plan.systemMemoryPressureLevel} policy=${materializationPolicy} ` +
      `policyVersion=${BROWSER_TAB_BACKGROUND_POLICY_VERSION} ` +
      `active=${plan.activeTabId} live=${plan.liveTabIds.length} hot=${plan.hotTabIds.length} ` +
      `warm=${plan.warmTabIds.length} suspended=${plan.suspendedTabIds.length} protected=${plan.protectedTabIds.length} ` +
      `stateCounts=${this.formatRuntimeStateCounts(runtimeStateCounts)} ` +
      `behaviorScreenCapture=${plan.pageBehaviorSummary.screenCaptureTabIds.length} ` +
      `behaviorMedia=${plan.pageBehaviorSummary.mediaPlayingTabIds.length} ` +
      `behaviorEditing=${plan.pageBehaviorSummary.userEditingTabIds.length} ` +
      `behaviorDownload=${plan.pageBehaviorSummary.downloadingTabIds.length} ` +
      `behaviorProtected=${plan.pageBehaviorSummary.protectedTabIds.length} ` +
      `behaviorScoreMax=${plan.pageBehaviorSummary.maxBehaviorScore} ` +
      `behaviorSignals=${plan.pageBehaviorSummary.maxBehaviorSignals} ` +
      `preview=${previewSummary.displayablePreviewCount}/${previewSummary.totalTabCount} ` +
      `persistedPreview=${previewSummary.persistedImageCount} memoryPreview=${previewSummary.memoryImageCount} ` +
      `previewMissing=${previewSummary.missingPreviewTabIds.length} ` +
      `previewMissingTabs=${this.formatTabIdList(previewSummary.missingPreviewTabIds)} ` +
      `queueCount=${queueSummary.totalCount} ` +
      `queueLimit=${this.resolveDiscardQueueMaxPendingTasks(plan.systemMemoryPressureLevel)} ` +
      `discardReasonCounts=${this.formatDiscardReasonCounts(queueSummary.reasonCounts)} ` +
      `discardGateProtected=${discardGateSummary.protectedTabIds.length} ` +
      `noWebStateProtected=${discardGateSummary.protectedNoWebStateCount} ` +
      `previewDeferred=${discardGateSummary.previewDeferredTabIds.length} ` +
      `previewDeferredTabs=${this.formatTabIdList(discardGateSummary.previewDeferredTabIds)} ` +
      `webStateCandidateCount=${plan.webStateRestoreCandidates.length} ` +
      `webStateCandidateMode=on_activation warmPreload=disabled ` +
      `discardQueue=${plan.discardQueue.map((task: BrowserTabDiscardTask): string => task.tabId).join(',') || 'none'} ` +
      `webStateRestoreCandidates=${plan.webStateRestoreCandidates.map((task: BrowserTabWebStateRestoreCandidate): string => task.tabId).join(',') || 'none'}`;
  }

  private resolveDiscardQueueMaxPendingTasks(level: BrowserSystemMemoryPressureLevel): number {
    switch (level) {
      case 'critical':
        return 16;
      case 'low':
        return 8;
      case 'moderate':
        return 6;
      case 'normal':
      default:
        return 4;
    }
  }

  private buildPageBehaviorSummary(
    pageBehaviorByTabId: Record<string, BrowserTabPageBehaviorState>
  ): BrowserTabPageBehaviorSummary {
    const screenCaptureTabIds: string[] = [];
    const mediaPlayingTabIds: string[] = [];
    const userEditingTabIds: string[] = [];
    const downloadingTabIds: string[] = [];
    const protectedTabIds: string[] = [];
    let maxBehaviorScore = 0;
    let maxBehaviorSignals = 'none';
    Object.keys(pageBehaviorByTabId).forEach((tabId: string) => {
      const state = pageBehaviorByTabId[tabId];
      if (state.isScreenCapture) {
        screenCaptureTabIds.push(tabId);
      }
      if (state.isMediaPlaying) {
        mediaPlayingTabIds.push(tabId);
      }
      if (state.isUserEditing) {
        userEditingTabIds.push(tabId);
      }
      if (state.isDownloading) {
        downloadingTabIds.push(tabId);
      }
      const prioritySummary: BrowserTabPageBehaviorPrioritySummary | undefined =
        this.runtimeTransactionSignalService.resolvePageBehaviorPrioritySummary(state);
      if (prioritySummary === undefined) {
        return;
      }
      protectedTabIds.push(tabId);
      if (prioritySummary.totalPriority > maxBehaviorScore) {
        maxBehaviorScore = prioritySummary.totalPriority;
        maxBehaviorSignals = this.runtimeTransactionSignalService.formatPageBehaviorSignalList(prioritySummary);
      }
    });
    return {
      screenCaptureTabIds: screenCaptureTabIds,
      mediaPlayingTabIds: mediaPlayingTabIds,
      userEditingTabIds: userEditingTabIds,
      downloadingTabIds: downloadingTabIds,
      protectedTabIds: protectedTabIds,
      maxBehaviorScore: maxBehaviorScore,
      maxBehaviorSignals: maxBehaviorSignals
    };
  }

  private buildRuntimeStateCountSummary(plan: BrowserTabBackgroundPlan): BrowserTabRuntimeStateCountSummary {
    const summary: BrowserTabRuntimeStateCountSummary = {
      active: 0,
      background: 0,
      backgroundHot: 0,
      backgroundWarm: 0,
      suspended: 0,
      cold: 0,
      discarded: 0,
      loading: 0,
      error: 0,
      restoring: 0,
      crashed: 0
    };
    Object.keys(plan.runtimeStatePatchByTabId).forEach((tabId: string) => {
      this.incrementRuntimeStateCount(summary, plan.runtimeStatePatchByTabId[tabId]);
    });
    return summary;
  }

  private incrementRuntimeStateCount(summary: BrowserTabRuntimeStateCountSummary, state: TabRuntimeState): void {
    switch (state) {
      case 'active':
        summary.active += 1;
        return;
      case 'background':
        summary.background += 1;
        return;
      case 'background-hot':
        summary.backgroundHot += 1;
        return;
      case 'background-warm':
        summary.backgroundWarm += 1;
        return;
      case 'suspended':
        summary.suspended += 1;
        return;
      case 'cold':
        summary.cold += 1;
        return;
      case 'discarded':
        summary.discarded += 1;
        return;
      case 'loading':
        summary.loading += 1;
        return;
      case 'error':
        summary.error += 1;
        return;
      case 'restoring':
        summary.restoring += 1;
        return;
      case 'crashed':
        summary.crashed += 1;
        return;
      default:
        return;
    }
  }

  private buildDiscardQueueSummary(discardQueue: BrowserTabDiscardTask[]): BrowserTabDiscardQueueSummary {
    const reasonCounts: BrowserTabDiscardReasonCountSummary = {
      retentionCold: 0,
      retentionBudget: 0,
      retentionStale: 0,
      manualHome: 0,
      controllerDetached: 0
    };
    discardQueue.forEach((task: BrowserTabDiscardTask) => {
      this.incrementDiscardReasonCount(reasonCounts, task.reason);
    });
    return {
      totalCount: discardQueue.length,
      reasonCounts: reasonCounts
    };
  }

  private incrementDiscardReasonCount(summary: BrowserTabDiscardReasonCountSummary, reason: TabDiscardReason): void {
    switch (reason) {
      case 'retention_cold':
        summary.retentionCold += 1;
        return;
      case 'retention_budget':
        summary.retentionBudget += 1;
        return;
      case 'retention_stale':
        summary.retentionStale += 1;
        return;
      case 'manual_home':
        summary.manualHome += 1;
        return;
      case 'controller_detached':
        summary.controllerDetached += 1;
        return;
      default:
        return;
    }
  }

  private formatRuntimeStateCounts(summary: BrowserTabRuntimeStateCountSummary): string {
    return `active:${summary.active},background:${summary.background},background-hot:${summary.backgroundHot},` +
      `background-warm:${summary.backgroundWarm},suspended:${summary.suspended},cold:${summary.cold},` +
      `discarded:${summary.discarded},loading:${summary.loading},error:${summary.error},` +
      `restoring:${summary.restoring},crashed:${summary.crashed}`;
  }

  private formatDiscardReasonCounts(summary: BrowserTabDiscardReasonCountSummary): string {
    return `retention_cold:${summary.retentionCold},retention_budget:${summary.retentionBudget},` +
      `retention_stale:${summary.retentionStale},manual_home:${summary.manualHome},` +
      `controller_detached:${summary.controllerDetached}`;
  }

  private formatTabIdList(tabIds: string[]): string {
    if (tabIds.length === 0) {
      return 'none';
    }
    return tabIds.join(',');
  }

  private buildPreviewAssetSummary(input: BrowserTabBackgroundManagerInput): BrowserTabPreviewAssetSummary {
    let totalTabCount = 0;
    let displayablePreviewCount = 0;
    let persistedImageCount = 0;
    let memoryImageCount = 0;
    const missingPreviewTabIds: string[] = [];
    input.tabs.forEach((tab: BrowserTabState) => {
      if (tab.isHome) {
        return;
      }
      totalTabCount += 1;
      const asset = input.previewAssetsByTabId[tab.id];
      if (asset?.hasDisplayablePreview === true) {
        displayablePreviewCount += 1;
      } else {
        missingPreviewTabIds.push(tab.id);
      }
      if (asset?.hasPersistedImage === true) {
        persistedImageCount += 1;
      }
      if (asset?.hasMemoryImage === true) {
        memoryImageCount += 1;
      }
    });
    return {
      totalTabCount: totalTabCount,
      displayablePreviewCount: displayablePreviewCount,
      persistedImageCount: persistedImageCount,
      memoryImageCount: memoryImageCount,
      missingPreviewTabIds: missingPreviewTabIds
    };
  }
}
