import { webview } from '@kit.ArkWeb';
import { TabCrashReason, TabRestoreReason, isBrowserDataBoundarySessionEphemeralTabLike } from '../../common/models/BrowserModels';
import { BrowserTabRuntimePatch, BrowserTabState } from '../tabs/TabManager';
import { BrowserWebComponentWebStateRestoreResult } from '../web/BrowserWebComponentController';
import { WebRecoveryManager, WebRestoreRecoveryPlan } from '../web/WebRecoveryManager';
import { WebStateSnapshotRecord, WebStateSnapshotStore } from '../web/WebStateSnapshotStore';
import { BrowserFaultClassifier } from './BrowserFaultClassifier';
import { BrowserHostedWebNodeDisposeReason } from './BrowserRuntimeActionReason';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';

export interface BrowserActiveTabRestoreResolution {
  restorePlan: WebRestoreRecoveryPlan;
  patch: BrowserTabRuntimePatch;
}

export interface BrowserSnapshotRestoreFailureResolution {
  recoveryMessage: string;
  patch: BrowserTabRuntimePatch;
}

export interface BrowserNavigationRestoreResolution {
  helperMessage: string;
  patch: BrowserTabRuntimePatch;
}

export interface BrowserNavigationRestoreFailureResolution {
  crashReason: TabCrashReason;
  recoveryMessage: string;
  shouldFallbackToHome: boolean;
  patch: BrowserTabRuntimePatch;
}

export interface BrowserNavigationRestoreFailureApplicationResult {
  tabId: string;
  recoveryMessage: string;
  crashReason: TabCrashReason;
  shouldFallbackToHome: boolean;
  userMessage: string;
  tabPatch: BrowserTabRuntimePatch;
  runtimeEvents: BrowserSnapshotPersistRuntimeEvent[];
  restoreTraceBreadcrumbs: string[];
}

export type BrowserSnapshotPersistStatus = 'saved' | 'skipped' | 'failed' | 'canceled';

export type BrowserSnapshotPersistReason =
  'saved' |
  'no_active_tab' |
  'home_tab' |
  'home_visible' |
  'session_ephemeral' |
  'controller_detached' |
  'controller_missing' |
  'empty_web_state' |
  'save_returned_empty' |
  'serialize_failed' |
  'save_failed' |
  'active_tab_changed';

export interface BrowserSnapshotPersistResolution {
  status: BrowserSnapshotPersistStatus;
  reason: BrowserSnapshotPersistReason;
  tabId: string;
  snapshotReason: string;
  message: string;
  snapshot?: WebStateSnapshotRecord;
  shouldCommitSnapshot: boolean;
  shouldRecordRuntimeEvent: boolean;
  runtimeEventType: string;
  runtimeEventMessage: string;
  restoreTraceBreadcrumb: string;
}

export interface BrowserSnapshotPersistPrecondition {
  shouldAttempt: boolean;
  resolution?: BrowserSnapshotPersistResolution;
}

export interface BrowserSnapshotPersistRuntimeEvent {
  type: string;
  message: string;
}

export interface BrowserSnapshotApplicationResult {
  tabId: string;
  tabPatch?: BrowserTabRuntimePatch;
  runtimeEvents: BrowserSnapshotPersistRuntimeEvent[];
  restoreTraceBreadcrumbs: string[];
  shouldRecordDiagnostic: boolean;
  diagnosticType: string;
  diagnosticMessage: string;
  diagnosticFaultCode: string;
}

export interface BrowserSnapshotPersistApplicationResult extends BrowserSnapshotApplicationResult {
}

export interface BrowserSnapshotRestoreFailureApplicationResult extends BrowserSnapshotApplicationResult {
  recoveryMessage: string;
}

export type BrowserSnapshotDeleteReason =
  'active_tab_changed' |
  'restore_snapshot_invalid' |
  'restore_snapshot_exception' |
  'tab_closed' |
  'home_reset' |
  'stale_cleanup';

export interface BrowserSnapshotDeleteApplicationOptions {
  shouldClearTabSnapshot?: boolean;
  shouldRecordDiagnostic?: boolean;
  shouldRecordRuntimeEvent?: boolean;
  detail?: string;
}

export interface BrowserSnapshotDeleteApplicationResult extends BrowserSnapshotApplicationResult {
  snapshotPath: string;
  reason: BrowserSnapshotDeleteReason;
}

export interface BrowserActiveSnapshotPersistFlowResult {
  results: BrowserSnapshotApplicationResult[];
}

export interface BrowserActiveSnapshotRestoreRequest {
  tabId: string;
  targetUrl: string;
  snapshotPath: string;
  controller?: webview.WebviewController;
}

export interface BrowserActiveSnapshotRestoreHost {
  prepareSnapshotRestoreAttempt: (tabId: string, targetUrl: string) => void;
  restoreWebState: (tabId: string, payload: Uint8Array | undefined) => BrowserWebComponentWebStateRestoreResult;
}

export interface BrowserActiveSnapshotRestoreFlowResult {
  restored: boolean;
  restoredTabPatch?: BrowserTabRuntimePatch;
  invalidationResults: BrowserSnapshotApplicationResult[];
  failureResult?: BrowserSnapshotRestoreFailureApplicationResult;
}

export interface BrowserActiveSnapshotPersistRequest {
  currentActiveTabId: string;
  reason: string;
  tab?: BrowserTabState;
  serializedWebState?: Uint8Array;
  hasController: boolean;
  controllerAttached: boolean;
  showHomePage: boolean;
}

export interface BrowserActiveSnapshotPersistRuntimeState {
  hasController: boolean;
  controllerAttached: boolean;
}

export interface BrowserMountedSnapshotPersistRuntimeState {
  hasController: boolean;
  hasLiveController: boolean;
}

export interface BrowserSnapshotApplicationHost {
  recordRestoreTraceDiagnostic: (type: string, message: string, tabId: string, faultCode: string) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
  appendRestoreTraceBreadcrumb: (tabId: string, breadcrumb: string) => void;
  applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch) => void;
}

export interface BrowserMountedSnapshotPersistFlowResult {
  results: BrowserSnapshotApplicationResult[];
  runtimeEvents: BrowserSnapshotPersistRuntimeEvent[];
  shouldDisposeHostedNode: boolean;
}

export interface BrowserMountedSnapshotPersistRequest {
  tabId: string;
  tab?: BrowserTabState;
  serializedWebState?: Uint8Array;
  hasController: boolean;
  hasLiveController: boolean;
  releaseHostedNodeAfterPersist: boolean;
}

export interface BrowserMountedSnapshotPersistFlowHost extends BrowserSnapshotApplicationHost {
  releaseHostedRuntime: (tabId: string, reason: BrowserHostedWebNodeDisposeReason) => void;
}

export interface BrowserSnapshotPersistenceHost extends BrowserMountedSnapshotPersistFlowHost {
  getActiveTabId: () => string;
  getActiveTab: () => BrowserTabState | undefined;
  resolveTab: (tabId: string) => BrowserTabState | undefined;
  isDownloadSnapshotPersistenceSuppressed: (tabId: string) => boolean;
  isTabNavigationProvisional: (tabId: string) => boolean;
  serializeWebState: (tabId: string) => Uint8Array | undefined;
  isHomeVisible: () => boolean;
}

export class BrowserTabRecoveryCoordinator {
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;

  constructor(runtimeLifecyclePort: BrowserRuntimeLifecyclePort) {
    this.runtimeLifecyclePort = runtimeLifecyclePort;
  }

  buildActiveRestoreResolution(
    recoveryManager: WebRecoveryManager,
    tab: BrowserTabState,
    reason: TabRestoreReason
  ): BrowserActiveTabRestoreResolution {
    const restorePlan = recoveryManager.buildRestorePlan(tab, reason);
    return {
      restorePlan: restorePlan,
      patch: {
        runtimeState: 'restoring',
        lastError: '',
        lastRestoreReason: reason,
        lastCrashReason: ''
      }
    };
  }

  resolveSnapshotRestoreSuccess(recoveryManager: WebRecoveryManager, tabId: string): BrowserTabRuntimePatch {
    recoveryManager.recordSnapshotRestoreSuccess(tabId);
    return {
      runtimeState: 'active',
      lastError: '',
      lastRestoreReason: 'snapshot_restore',
      lastCrashReason: ''
    };
  }

  resolveSnapshotRestoreFailure(
    recoveryManager: WebRecoveryManager,
    tabId: string
  ): BrowserSnapshotRestoreFailureResolution {
    recoveryManager.recordSnapshotRestoreFailure(tabId);
    return {
      recoveryMessage: '',
      patch: {
        lastCrashReason: '',
        webStatePath: '',
        webStateUpdatedAt: 0
      }
    };
  }

  resolveNavigationRestoreStart(
    restorePlan: WebRestoreRecoveryPlan,
    reason: TabRestoreReason
  ): BrowserNavigationRestoreResolution {
    return {
      helperMessage: '正在加载标签页',
      patch: {
        runtimeState: 'loading',
        lastError: '',
        lastRestoreReason: reason,
        lastCrashReason: ''
      }
    };
  }

  resolveNavigationRestoreFailure(
    recoveryManager: WebRecoveryManager,
    tabId: string,
    errorMessage: string
  ): BrowserNavigationRestoreFailureResolution {
    const crashReason: TabCrashReason = 'navigation_failed';
    recoveryManager.recordLoadFailure(tabId, errorMessage);
    return {
      crashReason: crashReason,
      recoveryMessage: recoveryManager.getDegradedReason(tabId),
      shouldFallbackToHome: recoveryManager.shouldFallbackTabToHome(tabId),
      patch: {
        runtimeState: 'crashed',
        lastError: errorMessage,
        lastCrashReason: crashReason
      }
    };
  }

  buildNavigationRestoreFailureApplicationResult(
    recoveryManager: WebRecoveryManager,
    tabId: string,
    errorMessage: string,
    telemetryType: string,
    userMessage: string,
    breadcrumb: string,
    crashReason: TabCrashReason
  ): BrowserNavigationRestoreFailureApplicationResult {
    const resolution = this.resolveNavigationRestoreFailure(recoveryManager, tabId, errorMessage);
    return {
      tabId: tabId,
      recoveryMessage: resolution.recoveryMessage,
      crashReason: crashReason,
      shouldFallbackToHome: resolution.shouldFallbackToHome,
      userMessage: userMessage,
      tabPatch: resolution.patch,
      runtimeEvents: [{
        type: telemetryType,
        message: userMessage
      }],
      restoreTraceBreadcrumbs: [
        breadcrumb,
        `restore_navigation_failed ${userMessage}`
      ]
    };
  }

  async persistSnapshot(
    snapshotStore: WebStateSnapshotStore,
    tab: BrowserTabState | undefined,
    serializedWebState: Uint8Array | undefined,
    hasController: boolean,
    controllerAttached: boolean,
    blockWhenHomeVisible: boolean = false
  ): Promise<WebStateSnapshotRecord | undefined> {
    const resolution = await this.persistSnapshotWithResolution(
      snapshotStore,
      tab,
      serializedWebState,
      hasController,
      controllerAttached,
      blockWhenHomeVisible,
      'snapshot'
    );
    return resolution.snapshot;
  }

  async persistSnapshotWithResolution(
    snapshotStore: WebStateSnapshotStore,
    tab: BrowserTabState | undefined,
    serializedWebState: Uint8Array | undefined,
    hasController: boolean,
    controllerAttached: boolean,
    blockWhenHomeVisible: boolean = false,
    snapshotReason: string = 'snapshot'
  ): Promise<BrowserSnapshotPersistResolution> {
    const precondition = this.resolveSnapshotPersistPrecondition(
      tab,
      controllerAttached,
      hasController,
      blockWhenHomeVisible,
      snapshotReason
    );
    if (!precondition.shouldAttempt && precondition.resolution !== undefined) {
      return precondition.resolution;
    }
    const targetTab = tab as BrowserTabState;
    if (serializedWebState === undefined || serializedWebState === null || serializedWebState.byteLength <= 0) {
      return this.buildSnapshotPersistResolution(
        'skipped',
        'empty_web_state',
        targetTab.id,
        snapshotReason,
        'Web 状态为空，跳过快照保存。',
        false
      );
    }
    try {
      const snapshot = await snapshotStore.saveSnapshot(targetTab.id, serializedWebState);
      if (snapshot === undefined) {
        return this.buildSnapshotPersistResolution(
          'failed',
          'save_returned_empty',
          targetTab.id,
          snapshotReason,
          '快照保存未返回有效结果。',
          true
        );
      }
      return {
        status: 'saved',
        reason: 'saved',
        tabId: targetTab.id,
        snapshotReason: snapshotReason,
        message: `快照已保存 ${snapshot.path}`,
        snapshot: snapshot,
        shouldCommitSnapshot: true,
        shouldRecordRuntimeEvent: false,
        runtimeEventType: '',
        runtimeEventMessage: '',
        restoreTraceBreadcrumb: ''
      };
    } catch (_error) {
      return this.resolveSnapshotPersistFailure(targetTab.id, snapshotReason, 'save_failed');
    }
  }

  resolveSnapshotPersistPrecondition(
    tab: BrowserTabState | undefined,
    controllerAttached: boolean,
    hasController: boolean,
    blockWhenHomeVisible: boolean = false,
    snapshotReason: string = 'snapshot'
  ): BrowserSnapshotPersistPrecondition {
    if (tab === undefined || tab.isHome || blockWhenHomeVisible) {
      const reason: BrowserSnapshotPersistReason = tab === undefined ? 'no_active_tab' :
        (tab.isHome ? 'home_tab' : 'home_visible');
      return {
        shouldAttempt: false,
        resolution: this.buildSnapshotPersistResolution(
          'skipped',
          reason,
          tab?.id ?? '',
          snapshotReason,
          this.resolveSnapshotPersistMessage(reason),
          false
        )
      };
    }
    if (this.isSessionEphemeralTab(tab)) {
      return {
        shouldAttempt: false,
        resolution: this.buildSessionEphemeralSnapshotSkipResolution(tab.id, snapshotReason)
      };
    }
    if (!controllerAttached) {
      return {
        shouldAttempt: false,
        resolution: this.buildSnapshotPersistResolution(
          'skipped',
          'controller_detached',
          tab.id,
          snapshotReason,
          this.resolveSnapshotPersistMessage('controller_detached'),
          false
        )
      };
    }
    if (!hasController) {
      return {
        shouldAttempt: false,
        resolution: this.buildSnapshotPersistResolution(
          'skipped',
          'controller_missing',
          tab.id,
          snapshotReason,
          this.resolveSnapshotPersistMessage('controller_missing'),
          false
        )
      };
    }
    return {
      shouldAttempt: true
    };
  }

  resolveSnapshotPersistCancellation(tabId: string, snapshotReason: string): BrowserSnapshotPersistResolution {
    return this.buildSnapshotPersistResolution(
      'canceled',
      'active_tab_changed',
      tabId,
      snapshotReason,
      '快照保存完成时活动标签页已变化，已取消提交。',
      true
    );
  }

  resolveSnapshotPersistFailure(
    tabId: string,
    snapshotReason: string,
    reason: BrowserSnapshotPersistReason = 'save_failed'
  ): BrowserSnapshotPersistResolution {
    return this.buildSnapshotPersistResolution(
      'failed',
      reason,
      tabId,
      snapshotReason,
      this.resolveSnapshotPersistMessage(reason),
      true
    );
  }

  buildSnapshotPersistApplicationResult(
    resolution: BrowserSnapshotPersistResolution,
    savedEventType: string = 'snapshot_saved_active',
    shouldMarkActiveRuntime: boolean = true
  ): BrowserSnapshotPersistApplicationResult {
    const result: BrowserSnapshotPersistApplicationResult = {
      tabId: resolution.tabId,
      runtimeEvents: [],
      restoreTraceBreadcrumbs: [],
      shouldRecordDiagnostic: true,
      diagnosticType: `snapshot_persist_${resolution.status}`,
      diagnosticMessage: resolution.message,
      diagnosticFaultCode: resolution.status === 'failed' || resolution.status === 'canceled' ? resolution.reason : ''
    };

    if (resolution.shouldCommitSnapshot && resolution.snapshot !== undefined) {
      result.tabPatch = {
        webStatePath: resolution.snapshot.path,
        webStateUpdatedAt: resolution.snapshot.updatedAt,
        runtimeState: shouldMarkActiveRuntime ? 'active' : undefined,
        lastError: shouldMarkActiveRuntime ? '' : undefined,
        lastCrashReason: shouldMarkActiveRuntime ? '' : undefined
      };
      result.runtimeEvents = [{
        type: savedEventType,
        message: `${resolution.snapshotReason} 已保存快照 ${resolution.snapshot.path}`
      }];
      result.restoreTraceBreadcrumbs = [`snapshot_saved ${resolution.snapshotReason}`];
      return result;
    }

    if (resolution.shouldRecordRuntimeEvent && resolution.tabId.length > 0) {
      result.runtimeEvents = [{
        type: resolution.runtimeEventType,
        message: resolution.runtimeEventMessage
      }];
      result.restoreTraceBreadcrumbs = [resolution.restoreTraceBreadcrumb];
    }
    return result;
  }

  buildSnapshotDeleteApplicationResult(
    tabId: string,
    snapshotPath: string,
    reason: BrowserSnapshotDeleteReason,
    options: BrowserSnapshotDeleteApplicationOptions = {}
  ): BrowserSnapshotDeleteApplicationResult {
    const message = this.resolveSnapshotDeleteMessage(reason, snapshotPath, options.detail ?? '');
    const shouldRecordRuntimeEvent = options.shouldRecordRuntimeEvent ?? true;
    const result: BrowserSnapshotDeleteApplicationResult = {
      tabId: tabId,
      snapshotPath: snapshotPath,
      reason: reason,
      runtimeEvents: shouldRecordRuntimeEvent ? [{
        type: 'snapshot_deleted',
        message: message
      }] : [],
      restoreTraceBreadcrumbs: [`snapshot_deleted ${reason}`],
      shouldRecordDiagnostic: options.shouldRecordDiagnostic ?? true,
      diagnosticType: 'snapshot_deleted',
      diagnosticMessage: message,
      diagnosticFaultCode: reason
    };
    if (options.shouldClearTabSnapshot ?? false) {
      result.tabPatch = {
        webStatePath: '',
        webStateUpdatedAt: 0
      };
    }
    return result;
  }

  buildSnapshotRestoreFailureApplicationResult(
    recoveryManager: WebRecoveryManager,
    tabId: string,
    snapshotPath: string,
    telemetryType: string,
    userMessage: string,
    breadcrumb: string
  ): BrowserSnapshotRestoreFailureApplicationResult {
    const resolution = this.resolveSnapshotRestoreFailure(recoveryManager, tabId);
    return {
      tabId: tabId,
      tabPatch: resolution.patch,
      runtimeEvents: [{
        type: telemetryType,
        message: userMessage
      }],
      restoreTraceBreadcrumbs: [
        breadcrumb,
        `snapshot_restore_failed ${snapshotPath}`
      ],
      shouldRecordDiagnostic: false,
      diagnosticType: '',
      diagnosticMessage: '',
      diagnosticFaultCode: '',
      recoveryMessage: resolution.recoveryMessage
    };
  }

  async finalizeActiveSnapshotPersist(
    snapshotStore: WebStateSnapshotStore,
    resolution: BrowserSnapshotPersistResolution,
    currentActiveTabId: string
  ): Promise<BrowserActiveSnapshotPersistFlowResult> {
    const flowResult: BrowserActiveSnapshotPersistFlowResult = {
      results: []
    };
    if (!resolution.shouldCommitSnapshot || resolution.snapshot === undefined) {
      flowResult.results.push(this.buildSnapshotPersistApplicationResult(resolution));
      return flowResult;
    }
    if (resolution.tabId.length <= 0) {
      return flowResult;
    }
    if (currentActiveTabId !== resolution.tabId) {
      await snapshotStore.deleteSnapshot(resolution.snapshot.path);
      flowResult.results.push(this.buildSnapshotDeleteApplicationResult(
        resolution.tabId,
        resolution.snapshot.path,
        'active_tab_changed',
        {
          shouldRecordRuntimeEvent: false,
          detail: `reason=${resolution.snapshotReason}`
        }
      ));
      flowResult.results.push(this.buildSnapshotPersistApplicationResult(
        this.resolveSnapshotPersistCancellation(resolution.tabId, resolution.snapshotReason)
      ));
      return flowResult;
    }
    flowResult.results.push(this.buildSnapshotPersistApplicationResult(resolution));
    return flowResult;
  }

  async persistActiveSnapshotFlow(
    snapshotStore: WebStateSnapshotStore,
    request: BrowserActiveSnapshotPersistRequest
  ): Promise<BrowserActiveSnapshotPersistFlowResult> {
    try {
      if (this.isSessionEphemeralTab(request.tab)) {
        return {
          results: [this.buildSnapshotPersistApplicationResult(this.buildSessionEphemeralSnapshotSkipResolution(
            request.tab?.id ?? request.currentActiveTabId,
            request.reason
          ))]
        };
      }
      const resolution = await this.persistSnapshotWithResolution(
        snapshotStore,
        request.tab,
        request.serializedWebState,
        request.hasController,
        request.controllerAttached,
        request.showHomePage,
        request.reason
      );
      return await this.finalizeActiveSnapshotPersist(
        snapshotStore,
        resolution,
        request.currentActiveTabId
      );
    } catch (_error) {
      const tabId = request.tab?.id ?? request.currentActiveTabId;
      return {
        results: [this.buildSnapshotPersistApplicationResult(
          this.resolveSnapshotPersistFailure(tabId, request.reason, 'save_failed')
        )]
      };
    }
  }

  async runActiveSnapshotPersistFlow(
    snapshotStore: WebStateSnapshotStore,
    request: BrowserActiveSnapshotPersistRequest,
    host: BrowserSnapshotApplicationHost
  ): Promise<void> {
    const result = await this.persistActiveSnapshotFlow(snapshotStore, request);
    this.applyActiveSnapshotPersistFlowResult(result, host, request.currentActiveTabId);
  }

  clearDownloadSnapshotForTab(
    snapshotStore: WebStateSnapshotStore,
    tab: BrowserTabState,
    reason: string,
    host: BrowserSnapshotApplicationHost
  ): void {
    const snapshotPath = tab.webStatePath.trim();
    if (snapshotPath.length <= 0) {
      return;
    }
    host.applyTabRuntimePatch(tab.id, {
      webStatePath: '',
      webStateUpdatedAt: 0
    });
    void snapshotStore.deleteSnapshot(snapshotPath)
      .then(() => {
        host.recordRuntimeEvent(
          'download_snapshot_deleted',
          `tab=${tab.id} reason=${reason} snapshot=${snapshotPath}`,
          tab.id
        );
      })
      .catch(() => {
      });
  }

  private shouldSkipDownloadSnapshotPersistence(
    tabId: string,
    source: string,
    host: BrowserSnapshotPersistenceHost
  ): boolean {
    if (!host.isDownloadSnapshotPersistenceSuppressed(tabId)) {
      return false;
    }
    host.recordRuntimeEvent(
      'download_snapshot_persist_skipped',
      `tab=${tabId} source=${source}`,
      tabId
    );
    return true;
  }

  async runActiveSnapshotPersistFromHost(
    snapshotStore: WebStateSnapshotStore,
    reason: string,
    host: BrowserSnapshotPersistenceHost,
    activeControllerAttached: boolean
  ): Promise<void> {
    const activeTab = host.getActiveTab();
    if (activeTab !== undefined &&
      this.shouldSkipDownloadSnapshotPersistence(activeTab.id, `active_${reason}`, host)) {
      this.clearDownloadSnapshotForTab(snapshotStore, activeTab, `active_${reason}`, host);
      return;
    }
    if (activeTab !== undefined && host.isTabNavigationProvisional(activeTab.id)) {
      this.clearDownloadSnapshotForTab(snapshotStore, activeTab, `active_${reason}_provisional_navigation`, host);
      host.recordRuntimeEvent(
        'provisional_navigation_snapshot_skipped',
        `tab=${activeTab.id} reason=${reason} url=${activeTab.url}`,
        activeTab.id
      );
      return;
    }
    const activeTabId = host.getActiveTabId();
    const runtimeState = this.resolveActiveSnapshotPersistRuntimeState(activeTabId, activeControllerAttached);
    const request: BrowserActiveSnapshotPersistRequest = {
      currentActiveTabId: activeTabId,
      reason: reason,
      tab: activeTab,
      serializedWebState: host.serializeWebState(activeTabId),
      hasController: runtimeState.hasController,
      controllerAttached: runtimeState.controllerAttached,
      showHomePage: host.isHomeVisible()
    };
    await this.runActiveSnapshotPersistFlow(snapshotStore, request, host);
  }

  async persistMountedSnapshotFlow(
    snapshotStore: WebStateSnapshotStore,
    request: BrowserMountedSnapshotPersistRequest
  ): Promise<BrowserMountedSnapshotPersistFlowResult> {
    const snapshotReason = request.releaseHostedNodeAfterPersist ? 'background-release' : 'background';
    if (this.isSessionEphemeralTab(request.tab)) {
      return this.buildMountedSnapshotPersistFlowResult(
        this.buildSessionEphemeralSnapshotSkipResolution(request.tab?.id ?? request.tabId, snapshotReason),
        request.releaseHostedNodeAfterPersist
      );
    }
    try {
      const resolution = await this.persistSnapshotWithResolution(
        snapshotStore,
        request.tab,
        request.serializedWebState,
        request.hasController,
        request.hasLiveController,
        false,
        snapshotReason
      );
      return this.buildMountedSnapshotPersistFlowResult(resolution, request.releaseHostedNodeAfterPersist);
    } catch (_error) {
      return this.buildMountedSnapshotPersistFlowResult(
        this.resolveSnapshotPersistFailure(request.tabId, snapshotReason, 'save_failed'),
        request.releaseHostedNodeAfterPersist
      );
    }
  }

  async runMountedSnapshotPersistFlow(
    snapshotStore: WebStateSnapshotStore,
    request: BrowserMountedSnapshotPersistRequest,
    activeTabId: string,
    host: BrowserMountedSnapshotPersistFlowHost
  ): Promise<void> {
    if (request.tab === undefined || !request.hasController) {
      this.applyMountedSnapshotPersistFlowResult(
        this.buildMountedSnapshotPersistNoopFlowResult(request.releaseHostedNodeAfterPersist),
        host,
        request.tabId,
        activeTabId
      );
      return;
    }
    const result = await this.persistMountedSnapshotFlow(
      snapshotStore,
      request
    );
    this.applyMountedSnapshotPersistFlowResult(result, host, request.tabId, activeTabId);
  }

  runMountedSnapshotPersistFromHost(
    snapshotStore: WebStateSnapshotStore,
    tabId: string,
    releaseHostedNodeAfterPersist: boolean,
    host: BrowserSnapshotPersistenceHost
  ): void {
    const reason = releaseHostedNodeAfterPersist ? 'background_release' : 'background';
    if (this.shouldSkipDownloadSnapshotPersistence(tabId, reason, host)) {
      const tab = host.resolveTab(tabId);
      if (tab !== undefined) {
        this.clearDownloadSnapshotForTab(snapshotStore, tab, reason, host);
      }
      return;
    }
    const runtimeState = this.resolveMountedSnapshotPersistRuntimeState(tabId);
    const request: BrowserMountedSnapshotPersistRequest = {
      tabId: tabId,
      tab: host.resolveTab(tabId),
      serializedWebState: host.serializeWebState(tabId),
      hasController: runtimeState.hasController,
      hasLiveController: runtimeState.hasLiveController,
      releaseHostedNodeAfterPersist: releaseHostedNodeAfterPersist
    };
    void this.runMountedSnapshotPersistFlow(
      snapshotStore,
      request,
      host.getActiveTabId(),
      host
    );
  }

  private resolveActiveSnapshotPersistRuntimeState(
    activeTabId: string,
    activeControllerAttached: boolean
  ): BrowserActiveSnapshotPersistRuntimeState {
    return {
      hasController: this.runtimeLifecyclePort.resolveActiveController() !== undefined,
      controllerAttached: this.runtimeLifecyclePort.hasAttachedController(activeTabId, activeControllerAttached)
    };
  }

  private resolveMountedSnapshotPersistRuntimeState(tabId: string): BrowserMountedSnapshotPersistRuntimeState {
    return {
      hasController: this.runtimeLifecyclePort.hasRuntime(tabId),
      hasLiveController: this.runtimeLifecyclePort.hasLiveRuntimeController(tabId)
    };
  }

  buildMountedSnapshotPersistFlowResult(
    resolution: BrowserSnapshotPersistResolution,
    releaseHostedNodeAfterPersist: boolean
  ): BrowserMountedSnapshotPersistFlowResult {
    const flowResult: BrowserMountedSnapshotPersistFlowResult = {
      results: [this.buildSnapshotPersistApplicationResult(
        resolution,
        'snapshot_saved_background',
        false
      )],
      runtimeEvents: [],
      shouldDisposeHostedNode: releaseHostedNodeAfterPersist
    };
    if (releaseHostedNodeAfterPersist) {
      flowResult.runtimeEvents.push({
        type: 'page_cache_released',
        message: '已释放冷却标签页的 live Web 节点'
      });
    }
    return flowResult;
  }

  buildMountedSnapshotPersistNoopFlowResult(
    releaseHostedNodeAfterPersist: boolean
  ): BrowserMountedSnapshotPersistFlowResult {
    return {
      results: [],
      runtimeEvents: [],
      shouldDisposeHostedNode: releaseHostedNodeAfterPersist
    };
  }

  applyMountedSnapshotPersistFlowResult(
    result: BrowserMountedSnapshotPersistFlowResult,
    host: BrowserMountedSnapshotPersistFlowHost,
    tabId: string,
    activeTabId: string = ''
  ): void {
    result.results.forEach((snapshotResult: BrowserSnapshotApplicationResult) => {
      this.applySnapshotApplicationResult(snapshotResult, host, activeTabId);
    });
    result.runtimeEvents.forEach((runtimeEvent: BrowserSnapshotPersistRuntimeEvent) => {
      host.recordRuntimeEvent(runtimeEvent.type, runtimeEvent.message, tabId);
    });
    if (result.shouldDisposeHostedNode) {
      host.releaseHostedRuntime(tabId, 'runtime_cooling_snapshot_release');
    }
  }

  applyActiveSnapshotPersistFlowResult(
    result: BrowserActiveSnapshotPersistFlowResult,
    host: BrowserSnapshotApplicationHost,
    activeTabId: string
  ): void {
    result.results.forEach((snapshotResult: BrowserSnapshotApplicationResult) => {
      this.applySnapshotApplicationResult(snapshotResult, host, activeTabId);
    });
  }

  applySnapshotApplicationResult(
    result: BrowserSnapshotApplicationResult,
    host: BrowserSnapshotApplicationHost,
    activeTabId: string = ''
  ): void {
    const tabId = result.tabId.length > 0 ? result.tabId : activeTabId;
    if (result.shouldRecordDiagnostic && tabId.length > 0) {
      host.recordRestoreTraceDiagnostic(
        result.diagnosticType,
        result.diagnosticMessage,
        tabId,
        result.diagnosticFaultCode
      );
    }
    result.runtimeEvents.forEach((runtimeEvent: BrowserSnapshotPersistRuntimeEvent) => {
      if (tabId.length > 0) {
        host.recordRuntimeEvent(runtimeEvent.type, runtimeEvent.message, tabId);
      }
    });
    result.restoreTraceBreadcrumbs.forEach((breadcrumb: string) => {
      if (tabId.length > 0) {
        host.appendRestoreTraceBreadcrumb(tabId, breadcrumb);
      }
    });
    if (result.tabPatch === undefined || result.tabId.length <= 0) {
      return;
    }
    host.applyTabRuntimePatch(result.tabId, result.tabPatch);
  }

  async restoreSnapshot(
    snapshotStore: WebStateSnapshotStore,
    host: BrowserActiveSnapshotRestoreHost,
    tabId: string,
    snapshotPath: string
  ): Promise<boolean> {
    if (snapshotPath.trim().length <= 0) {
      return false;
    }
    const snapshotBytes = await snapshotStore.loadSnapshot(snapshotPath);
    if (snapshotBytes === undefined || snapshotBytes.byteLength <= 0) {
      return false;
    }
    return host.restoreWebState(tabId, snapshotBytes).restored;
  }

  async restoreActiveSnapshotFlow(
    snapshotStore: WebStateSnapshotStore,
    recoveryManager: WebRecoveryManager,
    faultClassifier: BrowserFaultClassifier,
    request: BrowserActiveSnapshotRestoreRequest,
    host: BrowserActiveSnapshotRestoreHost
  ): Promise<BrowserActiveSnapshotRestoreFlowResult> {
    try {
      host.prepareSnapshotRestoreAttempt(request.tabId, request.targetUrl);
      if (await this.restoreSnapshot(snapshotStore, host, request.tabId, request.snapshotPath)) {
        return {
          restored: true,
          restoredTabPatch: this.resolveSnapshotRestoreSuccess(recoveryManager, request.tabId),
          invalidationResults: []
        };
      }
      return await this.buildActiveSnapshotRestoreFailureFlowResult(
        snapshotStore,
        recoveryManager,
        faultClassifier,
        request,
        'restore_snapshot_invalid'
      );
    } catch (_error) {
      return await this.buildActiveSnapshotRestoreFailureFlowResult(
        snapshotStore,
        recoveryManager,
        faultClassifier,
        request,
        'restore_snapshot_exception'
      );
    }
  }

  private buildSnapshotPersistResolution(
    status: BrowserSnapshotPersistStatus,
    reason: BrowserSnapshotPersistReason,
    tabId: string,
    snapshotReason: string,
    message: string,
    shouldRecordRuntimeEvent: boolean
  ): BrowserSnapshotPersistResolution {
    return {
      status: status,
      reason: reason,
      tabId: tabId,
      snapshotReason: snapshotReason,
      message: message,
      shouldCommitSnapshot: false,
      shouldRecordRuntimeEvent: shouldRecordRuntimeEvent,
      runtimeEventType: `snapshot_persist_${status}`,
      runtimeEventMessage: `${snapshotReason} ${message}`,
      restoreTraceBreadcrumb: `snapshot_persist_${status} ${reason}`
    };
  }

  private buildSessionEphemeralSnapshotSkipResolution(
    tabId: string,
    snapshotReason: string
  ): BrowserSnapshotPersistResolution {
    return this.buildSnapshotPersistResolution(
      'skipped',
      'session_ephemeral',
      tabId,
      snapshotReason,
      this.resolveSnapshotPersistMessage('session_ephemeral'),
      false
    );
  }

  private isSessionEphemeralTab(tab: BrowserTabState | undefined): boolean {
    if (tab === undefined) {
      return false;
    }
    return isBrowserDataBoundarySessionEphemeralTabLike({
      id: tab.id,
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope
    });
  }

  private resolveSnapshotPersistMessage(reason: BrowserSnapshotPersistReason): string {
    switch (reason) {
      case 'no_active_tab':
        return '没有活动标签页，跳过快照保存。';
      case 'home_tab':
        return '首页标签页不需要保存 Web 快照。';
      case 'home_visible':
        return '首页正在展示，跳过快照保存。';
      case 'session_ephemeral':
        return '仅当前会话标签页不保存 Web 快照。';
      case 'controller_detached':
        return 'Web 控制器未附着，跳过快照保存。';
      case 'controller_missing':
        return 'Web 控制器不存在，跳过快照保存。';
      case 'empty_web_state':
        return 'Web 状态为空，跳过快照保存。';
      case 'save_returned_empty':
        return '快照保存未返回有效结果。';
      case 'serialize_failed':
        return 'Web 状态序列化失败。';
      case 'active_tab_changed':
        return '快照保存完成时活动标签页已变化，已取消提交。';
      case 'save_failed':
      default:
        return '快照保存失败。';
    }
  }

  private resolveSnapshotDeleteMessage(reason: BrowserSnapshotDeleteReason, snapshotPath: string, detail: string): string {
    const suffix = detail.length > 0 ? ` ${detail}` : '';
    switch (reason) {
      case 'active_tab_changed':
        return `活动标签页已变化，删除未提交快照 ${snapshotPath}${suffix}`;
      case 'restore_snapshot_invalid':
        return `快照恢复失败，删除无效快照 ${snapshotPath}${suffix}`;
      case 'restore_snapshot_exception':
        return `快照恢复异常，删除无效快照 ${snapshotPath}${suffix}`;
      case 'tab_closed':
        return `标签页关闭，删除快照 ${snapshotPath}${suffix}`;
      case 'home_reset':
        return `标签页回到首页，删除快照 ${snapshotPath}${suffix}`;
      case 'stale_cleanup':
      default:
        return `清理过期快照 ${snapshotPath}${suffix}`;
    }
  }

  private async buildActiveSnapshotRestoreFailureFlowResult(
    snapshotStore: WebStateSnapshotStore,
    recoveryManager: WebRecoveryManager,
    faultClassifier: BrowserFaultClassifier,
    request: BrowserActiveSnapshotRestoreRequest,
    deleteReason: BrowserSnapshotDeleteReason
  ): Promise<BrowserActiveSnapshotRestoreFlowResult> {
    const invalidationResults: BrowserSnapshotApplicationResult[] = [];
    if (request.snapshotPath.length > 0) {
      try {
        await snapshotStore.deleteSnapshot(request.snapshotPath);
      } catch (_error) {
      }
      invalidationResults.push(this.buildSnapshotDeleteApplicationResult(
        request.tabId,
        request.snapshotPath,
        deleteReason,
        {
          shouldRecordRuntimeEvent: false
        }
      ));
    }
    const fault = faultClassifier.classifySnapshotRestoreFailure(request.snapshotPath);
    return {
      restored: false,
      invalidationResults: invalidationResults,
      failureResult: this.buildSnapshotRestoreFailureApplicationResult(
        recoveryManager,
        request.tabId,
        request.snapshotPath,
        fault.telemetryType,
        fault.userMessage,
        fault.breadcrumb
      )
    };
  }

}
