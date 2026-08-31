import {
  SearchEngineId,
  SearchEngineRecord,
  TabRestoreReason
} from '../../common/models/BrowserModels';
import { BrowserFaultClassifier } from '../../core/browser/BrowserFaultClassifier';
import {
  BrowserRestoreCoordinator,
  BrowserRestoreTrace
} from '../../core/browser/BrowserRestoreCoordinator';
import {
  BrowserWebEventCommitCoordinator,
  BrowserWebSnapshotRestoreSuccessCommit
} from '../../core/browser/BrowserWebEventCommitCoordinator';
import { BrowserPageReloadReason } from '../../core/browser/BrowserRuntimeActionReason';
import {
  BrowserActiveSnapshotRestoreFlowResult,
  BrowserActiveSnapshotRestoreHost,
  BrowserNavigationRestoreFailureApplicationResult,
  BrowserSnapshotApplicationHost,
  BrowserTabRecoveryCoordinator
} from '../../core/browser/BrowserTabRecoveryCoordinator';
import { BrowserTabRuntimePatch, BrowserTabState, BrowserTabManagerPort } from '../../core/tabs/TabManager';
import { NavigationController } from '../../core/navigation/NavigationController';
import { BrowserWebComponentWebStateRestoreResult } from '../../core/web/BrowserWebComponentController';
import { WebRecoveryManager, WebRestoreRecoveryPlan } from '../../core/web/WebRecoveryManager';
import { WebSessionStateStore } from '../../core/web/WebSessionStateStore';
import { WebStateSnapshotStore } from '../../core/web/WebStateSnapshotStore';
import {
  BrowserRuntimeLifecyclePort,
  BrowserRuntimeMutationPort
} from './BrowserRuntimeLifecyclePort';
import { BrowserWebLoadRuntimeCoordinator } from './BrowserWebLoadRuntimeCoordinator';
import { BrowserHostedRuntimeSurfacePort } from './BrowserHostedRuntimeSurfacePort';
import { TelegramWebCompatibilityService } from './TelegramWebCompatibilityService';
import { BrowserTabSwitchCoordinator } from '../../core/browser/BrowserTabSwitchCoordinator';
import { BrowserShellStateCoordinator } from '../../core/browser/BrowserShellStateCoordinator';
import { BrowserWebLoadFailureSurfaceCoordinator } from '../../core/browser/BrowserWebLoadFailureSurfaceCoordinator';
import {
  BrowserWebActiveSurfaceCoordinator,
  WEB_ACTIVE_SURFACE_SCROLL_SOURCE_NAVIGATION_RESTORE
} from '../../core/browser/BrowserWebActiveSurfaceCoordinator';
import { BrowserWebTabsController } from '../../core/browser/BrowserWebTabsController';
import { BrowserTabHomeCoordinator } from '../../core/browser/BrowserTabHomeCoordinator';
import { browserNativeTabSceneService } from '../../core/browser/BrowserNativeTabSceneService';
import { WebpageTranslationCoordinator } from '../../core/translation/WebpageTranslationCoordinator';
import { WebEventRouter } from '../../core/web/WebEventRouter';

export interface BrowserActiveTabRuntimeRestoreFacts {
  activeTabId: string;
  controllerAttached: boolean;
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
  selectedSearchEngine: SearchEngineId;
  availableSearchEngines: SearchEngineRecord[];
  tabs: BrowserTabState[];
  showTabsSheet: boolean;
  showHomePage: boolean;
  holdPageErrorSurfaceDuringReload: boolean;
}

export interface BrowserActiveTabRuntimeRestoreStateApplication {
  restoreTraceTabId?: string;
  restoreTrace?: BrowserRestoreTrace;
  helperMessage?: string;
  errorMessage?: string;
  runtimeDegradedMessage?: string;
  isLoading?: boolean;
  pageErrorSurfaceVisible?: boolean;
  holdPageErrorSurfaceDuringReload?: boolean;
  currentUrl?: string;
  pendingWebUrl?: string;
  invalidateTransition?: boolean;
}

export interface BrowserActiveTabRuntimeRestoreHost {
  resolveFacts: () => BrowserActiveTabRuntimeRestoreFacts;
  applyState: (application: BrowserActiveTabRuntimeRestoreStateApplication) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
  appendRestoreTraceBreadcrumb: (tabId: string, breadcrumb: string) => void;
  beginTransition: () => number;
  isTransitionCurrent: (token: number, tabId: string) => boolean;
}

interface BrowserActiveTabRuntimeRestoreDependencies {
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  restoreCoordinator: BrowserRestoreCoordinator;
  recoveryManager: WebRecoveryManager;
  sessionStateStore: WebSessionStateStore;
  snapshotStore: WebStateSnapshotStore;
  snapshotRecoveryCoordinator: BrowserTabRecoveryCoordinator;
  faultClassifier: BrowserFaultClassifier;
  webEventCommitCoordinator: BrowserWebEventCommitCoordinator;
  webLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator;
  tabManager: BrowserTabManagerPort;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  shellStateCoordinator: BrowserShellStateCoordinator;
  runtimeMutationPort: BrowserRuntimeMutationPort;
  loadFailureSurfaceCoordinator: BrowserWebLoadFailureSurfaceCoordinator;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  webpageTranslationCoordinator: WebpageTranslationCoordinator;
  webEventRouter: WebEventRouter;
  visibleUrlService: TelegramWebCompatibilityService;
  activeSurfaceCoordinator: BrowserWebActiveSurfaceCoordinator;
  snapshotApplicationHost: BrowserSnapshotApplicationHost;
  resolveWebTabsController: () => BrowserWebTabsController;
  resolveTabHomeCoordinator: () => BrowserTabHomeCoordinator;
  primeNavigationVisualFeedback: (tabId: string, targetUrl: string, helperMessage?: string) => void;
  clearUserAgentTransitionSnapshotReloadMarker: (tabId: string) => void;
  consumeUserAgentTransitionSnapshotReloadReason: (tabId: string) => BrowserPageReloadReason | undefined;
}

export class BrowserActiveTabRuntimeRestoreCoordinator {
  private readonly dependencies: BrowserActiveTabRuntimeRestoreDependencies;
  private readonly host: BrowserActiveTabRuntimeRestoreHost;
  private readonly navigationController: NavigationController = new NavigationController();

  constructor(
    dependencies: BrowserActiveTabRuntimeRestoreDependencies,
    host: BrowserActiveTabRuntimeRestoreHost
  ) {
    this.dependencies = dependencies;
    this.host = host;
  }

  restoreActive(reason: TabRestoreReason): void {
    const activeTabId = this.host.resolveFacts().activeTabId;
    this.restore(activeTabId, reason);
  }

  restore(tabId: string, reason: TabRestoreReason): void {
    this.dependencies.runtimeLifecyclePort.restoreRuntime(
      tabId,
      reason,
      (restoringTabId: string, restoreReason: TabRestoreReason): void => {
        void this.runActiveRestoreFlow(restoringTabId, restoreReason);
      }
    );
  }

  reloadActive(reason: BrowserPageReloadReason, holdErrorPageDuringReload: boolean = true): void {
    const activeFacts = this.host.resolveFacts();
    const activeTab = this.resolveTab(activeFacts, activeFacts.activeTabId);
    const targetUrl = this.resolveActiveReloadTargetUrl(activeFacts);
    if (targetUrl.length === 0 || activeTab === undefined || activeTab.isHome ||
      browserNativeTabSceneService.isNativeTabUrl(targetUrl)) {
      return;
    }
    const shouldHoldErrorPage = holdErrorPageDuringReload &&
      (this.dependencies.loadFailureSurfaceCoordinator.shouldShowNativeSurface(activeFacts.activeTabId) ||
        activeFacts.holdPageErrorSurfaceDuringReload);
    if (shouldHoldErrorPage && activeTab.id === activeFacts.activeTabId &&
      !activeFacts.showTabsSheet && !activeFacts.showHomePage) {
      this.host.applyState({
        holdPageErrorSurfaceDuringReload: true
      });
    }
    this.dependencies.loadFailureSurfaceCoordinator.clear(activeFacts.activeTabId);
    this.host.applyState({
      pageErrorSurfaceVisible: false
    });
    this.dependencies.hostedRuntimeSurfacePort.ensureActiveWebSurfaceForNavigation(activeTab);
    const resolution = this.dependencies.restoreCoordinator.buildManualReloadResolution(activeTab, targetUrl, reason);
    this.host.applyState({
      restoreTraceTabId: activeTab.id,
      restoreTrace: resolution.trace,
      errorMessage: '',
      helperMessage: resolution.restorePlan.helperMessage,
      currentUrl: resolution.restorePlan.targetUrl,
      pendingWebUrl: resolution.restorePlan.targetUrl,
      invalidateTransition: true
    });
    this.dependencies.primeNavigationVisualFeedback(
      activeFacts.activeTabId,
      resolution.restorePlan.targetUrl,
      resolution.restorePlan.helperMessage
    );
    this.host.recordRuntimeEvent(
      'manual_reload_start',
      `trace=${resolution.trace.id} reason=${resolution.trace.source} type=${resolution.trace.restoreType} ` +
        `target=${resolution.restorePlan.targetUrl}`,
      activeTab.id
    );
    this.dependencies.webpageTranslationCoordinator.handleRefreshOrBackForwardForRuntimeTab(
      activeTab.id,
      activeFacts.activeTabId,
      resolution.restorePlan.targetUrl
    );
    this.dependencies.tabSwitchCoordinator.applyTabPatch(activeTab.id, resolution.patch);
    const executionError = this.issueLoadUrl(
      activeTab.id,
      resolution.restorePlan.targetUrl,
      '刷新下发失败',
      '刷新下发异常'
    );
    if (activeFacts.controllerAttached && executionError.length > 0) {
      this.host.applyState({
        errorMessage: executionError
      });
    }
  }

  private async runActiveRestoreFlow(
    tabId: string,
    reason: TabRestoreReason
  ): Promise<void> {
    const facts = this.host.resolveFacts();
    const activeTab = this.resolveTab(facts, tabId);
    if (tabId !== facts.activeTabId || !facts.controllerAttached || activeTab === undefined || activeTab.isHome) {
      this.dependencies.clearUserAgentTransitionSnapshotReloadMarker(tabId);
      return;
    }
    const restoreStart = this.dependencies.restoreCoordinator.buildRestoreStartResolution(
      this.dependencies.recoveryManager,
      this.dependencies.sessionStateStore,
      activeTab,
      reason
    );
    this.host.applyState({
      restoreTraceTabId: activeTab.id,
      restoreTrace: restoreStart.trace
    });
    this.host.recordRuntimeEvent(
      'restore_start',
      `trace=${restoreStart.trace.id} type=${restoreStart.trace.restoreType} ` +
        `source=${restoreStart.trace.source} target=${restoreStart.restorePlan.targetUrl}`,
      activeTab.id
    );
    this.dependencies.tabSwitchCoordinator.applyTabPatch(activeTab.id, restoreStart.patch, {
      persistTabs: false
    });
    this.dependencies.activeSurfaceCoordinator.applyVisualState(
      this.dependencies.shellStateCoordinator.buildRestoreTransitionState(activeTab, restoreStart.restorePlan)
    );

    const transitionToken = this.host.beginTransition();
    const snapshotResult = await this.restoreSnapshotIfRequested(
      activeTab.id,
      restoreStart.restorePlan
    );
    if (snapshotResult !== undefined) {
      if (!this.host.isTransitionCurrent(transitionToken, activeTab.id)) {
        this.dependencies.clearUserAgentTransitionSnapshotReloadMarker(activeTab.id);
        return;
      }
      if (snapshotResult.restored && snapshotResult.restoredTabPatch !== undefined) {
        this.applySnapshotRestoreSuccess(
          activeTab.id,
          snapshotResult.restoredTabPatch,
          this.dependencies.webEventCommitCoordinator.buildSnapshotRestoreSuccessCommit(
            restoreStart.restorePlan.snapshotPath
          )
        );
        const userAgentReloadReason = this.dependencies.consumeUserAgentTransitionSnapshotReloadReason(activeTab.id);
        if (userAgentReloadReason !== undefined) {
          this.reloadActive(userAgentReloadReason);
        }
        return;
      }
      this.dependencies.clearUserAgentTransitionSnapshotReloadMarker(activeTab.id);
      this.applySnapshotRestoreFailure(facts.activeTabId, snapshotResult);
    }
    this.dependencies.clearUserAgentTransitionSnapshotReloadMarker(activeTab.id);
    if (!this.host.isTransitionCurrent(transitionToken, activeTab.id)) {
      return;
    }
    await this.runNavigationRestore(activeTab.id, restoreStart.restorePlan, reason);
  }

  private async restoreSnapshotIfRequested(
    tabId: string,
    restorePlan: WebRestoreRecoveryPlan
  ): Promise<BrowserActiveSnapshotRestoreFlowResult | undefined> {
    if (!restorePlan.attemptSnapshotRestore || restorePlan.snapshotPath.length === 0) {
      return undefined;
    }
    const snapshotHost: BrowserActiveSnapshotRestoreHost = {
      prepareSnapshotRestoreAttempt: (restoringTabId: string, targetUrl: string): void => {
        this.dependencies.webEventRouter.beginNavigation(
          restoringTabId,
          this.dependencies.visibleUrlService.resolveVisibleUrl(targetUrl),
          true
        );
        this.dependencies.runtimeLifecyclePort.clearControllerHistory(restoringTabId);
      },
      restoreWebState: (
        restoringTabId: string,
        payload: Uint8Array | undefined
      ): BrowserWebComponentWebStateRestoreResult => {
        return this.dependencies.resolveWebTabsController().restoreWebState(restoringTabId, payload);
      }
    };
    return this.dependencies.snapshotRecoveryCoordinator.restoreActiveSnapshotFlow(
      this.dependencies.snapshotStore,
      this.dependencies.recoveryManager,
      this.dependencies.faultClassifier,
      {
        tabId: tabId,
        targetUrl: restorePlan.targetUrl,
        snapshotPath: restorePlan.snapshotPath,
        controller: this.dependencies.runtimeLifecyclePort.resolveActiveController()
      },
      snapshotHost
    );
  }

  private async runNavigationRestore(
    tabId: string,
    restorePlan: WebRestoreRecoveryPlan,
    reason: TabRestoreReason
  ): Promise<void> {
    if (restorePlan.targetUrl.length === 0) {
      this.host.applyState({
        helperMessage: '标签页没有可恢复地址，已回到首页'
      });
      await this.dependencies.resolveTabHomeCoordinator().goHome();
      return;
    }
    const resolution = this.dependencies.restoreCoordinator.buildActiveTabNavigationRestoreResolution(
      restorePlan,
      reason
    );
    this.dependencies.tabSwitchCoordinator.applyTabPatch(tabId, resolution.tabPatch, {
      persistTabs: false
    });
    this.host.recordRuntimeEvent(resolution.runtimeEventType, resolution.runtimeEventMessage, tabId);
    this.host.appendRestoreTraceBreadcrumb(tabId, resolution.restoreTraceBreadcrumb);
    this.applyNavigationLoadingState(resolution.helperMessage);
    const executionError = this.issueLoadUrl(
      tabId,
      resolution.targetUrl,
      '恢复导航下发失败',
      '恢复导航下发异常'
    );
    if (executionError.length === 0) {
      return;
    }
    const fault = this.dependencies.faultClassifier.classifyNavigationRestoreFailure(executionError);
    const failureResult = this.dependencies.snapshotRecoveryCoordinator.buildNavigationRestoreFailureApplicationResult(
      this.dependencies.recoveryManager,
      tabId,
      executionError,
      fault.telemetryType,
      fault.userMessage,
      fault.breadcrumb,
      fault.crashReason ?? 'navigation_failed'
    );
    this.applyNavigationRestoreFailure(executionError, failureResult);
  }

  private applyNavigationLoadingState(helperMessage: string): void {
    this.host.applyState({
      isLoading: true,
      helperMessage: helperMessage
    });
    const facts = this.host.resolveFacts();
    this.dependencies.primeNavigationVisualFeedback(
      facts.activeTabId,
      facts.pendingWebUrl.length > 0 ? facts.pendingWebUrl : facts.currentUrl
    );
  }

  private applySnapshotRestoreFailure(
    tabId: string,
    result: BrowserActiveSnapshotRestoreFlowResult
  ): void {
    result.invalidationResults.forEach((snapshotResult) => {
      this.dependencies.snapshotRecoveryCoordinator.applySnapshotApplicationResult(
        snapshotResult,
        this.dependencies.snapshotApplicationHost,
        tabId
      );
    });
    if (result.failureResult === undefined) {
      return;
    }
    this.host.applyState({
      runtimeDegradedMessage: result.failureResult.recoveryMessage
    });
    this.dependencies.snapshotRecoveryCoordinator.applySnapshotApplicationResult(
      result.failureResult,
      this.dependencies.snapshotApplicationHost,
      tabId
    );
  }

  private applySnapshotRestoreSuccess(
    tabId: string,
    tabPatch: BrowserTabRuntimePatch,
    commit: BrowserWebSnapshotRestoreSuccessCommit
  ): void {
    this.dependencies.tabSwitchCoordinator.applyTabPatch(tabId, tabPatch);
    this.host.recordRuntimeEvent(commit.runtimeEvent.type, commit.runtimeEvent.message, tabId);
    this.host.appendRestoreTraceBreadcrumb(tabId, commit.restoreTraceBreadcrumb);
    this.dependencies.activeSurfaceCoordinator.applySnapshotRestorePresentation(
      {
        plan: commit.activeSurfacePlan
      },
      {
        tabId: tabId,
        scrollSource: 'snapshot_restore'
      }
    );
  }

  private applyNavigationRestoreFailure(
    errorMessage: string,
    failureResult: BrowserNavigationRestoreFailureApplicationResult
  ): void {
    this.host.applyState({
      errorMessage: errorMessage.length > 0 ? errorMessage : failureResult.userMessage,
      runtimeDegradedMessage: failureResult.recoveryMessage
    });
    this.dependencies.runtimeMutationPort.markTabCrashed(
      failureResult.tabId,
      failureResult.recoveryMessage,
      failureResult.crashReason
    );
    failureResult.runtimeEvents.forEach((runtimeEvent) => {
      this.host.recordRuntimeEvent(runtimeEvent.type, runtimeEvent.message, failureResult.tabId);
    });
    failureResult.restoreTraceBreadcrumbs.forEach((breadcrumb: string) => {
      this.host.appendRestoreTraceBreadcrumb(failureResult.tabId, breadcrumb);
    });
    this.dependencies.tabSwitchCoordinator.applyTabPatch(failureResult.tabId, failureResult.tabPatch);
    this.dependencies.activeSurfaceCoordinator.applyLoadFailurePresentation(
      {
        plan: {
          shouldApplyVisualState: true,
          shouldRefreshPermissions: false,
          certificateAction: 'none',
          shouldRefreshTracking: false,
          shouldSyncNavigationState: false,
          shouldPersistActiveSnapshot: false,
          snapshotReason: ''
        }
      },
      failureResult.userMessage,
      failureResult.recoveryMessage,
      {
        tabId: failureResult.tabId,
        scrollSource: WEB_ACTIVE_SURFACE_SCROLL_SOURCE_NAVIGATION_RESTORE
      }
    );
    if (!failureResult.shouldFallbackToHome) {
      return;
    }
    const facts = this.host.resolveFacts();
    const activeTab = this.resolveTab(facts, facts.activeTabId);
    if (activeTab === undefined) {
      return;
    }
    void this.dependencies.resolveTabHomeCoordinator().degradeBrokenActiveTab({
      tabId: activeTab.id,
      snapshotPath: activeTab.webStatePath,
      degradedReason: this.dependencies.recoveryManager.getDegradedReason(activeTab.id)
    });
  }

  private resolveTab(
    facts: BrowserActiveTabRuntimeRestoreFacts,
    tabId: string
  ): BrowserTabState | undefined {
    return this.dependencies.tabManager.getTab(facts.tabs, tabId);
  }

  private resolveActiveReloadTargetUrl(facts: BrowserActiveTabRuntimeRestoreFacts): string {
    const currentUrl = facts.currentUrl.trim();
    if (currentUrl.length > 0) {
      return currentUrl;
    }
    return this.navigationController.resolveAddressInput(
      facts.addressInput,
      facts.selectedSearchEngine,
      facts.availableSearchEngines
    ).trim();
  }

  private issueLoadUrl(
    tabId: string,
    targetUrl: string,
    failurePrefix: string,
    exceptionPrefix: string
  ): string {
    try {
      if (this.dependencies.webLoadRuntimeCoordinator.loadUrlForTab(tabId, targetUrl, true)) {
        return '';
      }
      return `${failurePrefix}：${targetUrl}`;
    } catch (error) {
      return `${exceptionPrefix}：${JSON.stringify(error)}`;
    }
  }
}
