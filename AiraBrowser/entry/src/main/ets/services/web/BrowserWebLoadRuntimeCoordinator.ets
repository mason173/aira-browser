import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserWebDataLoadActiveControllerState,
  BrowserOpenResolvedUrlApplicationResult,
  BrowserOpenResolvedUrlExecutionResult,
  BrowserOpenResolvedUrlHost,
  BrowserWebLoadDataPayload,
  BrowserWebLoadCoordinator,
  BrowserWebLoadExecutionHost,
  BrowserWebLoadPlan
} from '../../core/browser/BrowserWebLoadCoordinator';
import {
  BrowserProfileId,
  isBrowserDataBoundarySessionEphemeralTabLike
} from '../../common/models/BrowserModels';
import { BrowserTabRuntimePatch, BrowserTabState, BrowserTabManagerPort } from '../../core/tabs/TabManager';
import { BrowserDownloadNavigationStateCoordinator } from '../../core/browser/BrowserDownloadNavigationStateCoordinator';
import { TabMutationCommitOptions } from '../../core/browser/BrowserShellRuntimeContracts';
import { WebEventRouter } from '../../core/web/WebEventRouter';
import { WebRecoveryManager } from '../../core/web/WebRecoveryManager';
import { WebControllerBootstrapConfig } from '../../core/web/WebControllerBootstrapper';
import {
  buildBrowserNewWindowTestHtml,
  getBrowserNewWindowTestUrl,
  isBrowserNewWindowTestUrl
} from '../../app/debug/BrowserNewWindowTestPage';
import { DocumentViewerService } from '../viewer/DocumentViewerService';
import {
  BrowserRuntimeLifecyclePort,
  BrowserRuntimeMutationPort,
  BrowserRuntimeWebDataLoadRequestAdapter
} from './BrowserRuntimeLifecyclePort';
import { BrowserOfflineFastFailureCoordinator } from './BrowserOfflineFastFailureCoordinator';
import {
  BrowserRuntimeNavigationRecoveryApplication,
  BrowserRuntimeNavigationRecoveryCoordinator,
  BrowserRuntimeNavigationRecoveryCoordinatorDependencies,
  BrowserRuntimeNavigationRecoveryCoordinatorHost,
  BrowserRuntimeNavigationRecoveryFacts
} from './BrowserRuntimeNavigationRecoveryCoordinator';
import {
  BrowserUserAgentNavigationPreparation,
  BrowserUserAgentRuntimeService
} from './BrowserUserAgentRuntimeService';
import { BrowserUserAgentService } from './BrowserUserAgentService';
import { BrowserBrowsingIdentityDecision } from './BrowserBrowsingIdentityDecisionService';
import { BrowserBrowsingIdentityPolicyCoordinator } from '../../core/browser/BrowserBrowsingIdentityPolicyCoordinator';
import { TelegramWebCompatibilityService } from './TelegramWebCompatibilityService';
import { sharedBrowserHttpsFirstNavigationService } from './BrowserHttpsFirstNavigationService';
import { BrowserRootBottomPanelDeferredWorkHandle } from '../../core/browser/BrowserRootBottomPanelSessionCoordinator';

const COLD_ACTIVE_RUNTIME_PRESENTATION_DELAY_MS: number = 16;
const BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN: number = 0x0000;
const BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG: string = 'HomeSearchDiag';

export interface BrowserWebLoadOpenResolvedUrlState {
  targetUrl: string;
  title: string;
  helperMessage: string;
  revealWebSurface: boolean;
}

export interface BrowserWebLoadRuntimeHostBindings {
  readFacts: () => BrowserWebLoadRuntimeFacts;
  applyControllerState: (
    controller: webview.WebviewController | undefined,
    controllerAttached: boolean
  ) => void;
  applyOpenResolvedUrlState: (state: BrowserWebLoadOpenResolvedUrlState) => void;
  invalidateWebSessionTransition: () => void;
  showRuntimeToast: (message: string) => void;
}

export interface BrowserWebLoadRuntimeFacts {
  tabs: BrowserTabState[];
  activeTabId: string;
  currentUrl: string;
  controllerAttached: boolean;
  currentProfileId: BrowserProfileId;
}

interface BrowserWebLoadUserAgentRuntimeContext {
  tabId: string;
  pageUrl: string;
  profileId: BrowserProfileId;
  privateBrowsing: boolean;
  observedOrigins: string[];
}

export interface BrowserWebLoadLifecycleApplication extends BrowserRuntimeNavigationRecoveryApplication {
  primeNavigationVisualFeedback: (
    tabId: string,
    targetUrl: string,
    helperMessage?: string,
    allowHiddenHomeSurface?: boolean
  ) => void;
  cancelNavigationVisualFeedbackIfLoadNotIssued: (tabId: string, targetUrl: string) => void;
}

export interface BrowserWebLoadRuntimeDependencies {
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  runtimeMutationPort: BrowserRuntimeMutationPort;
  visibleUrlService: TelegramWebCompatibilityService;
  webEventRouter: WebEventRouter;
  tabManager: BrowserTabManagerPort;
  downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;
  commitTabs: (tabs: BrowserTabState[], options: TabMutationCommitOptions) => void;
  syncActiveRuntime: () => void;
  syncCustomHomepageVisibility: () => void;
  resolveOfflineFastFailureCoordinator: () => BrowserOfflineFastFailureCoordinator;
  resolveLifecycleApplication: () => BrowserWebLoadLifecycleApplication;
  resolveDocumentViewerService: () => DocumentViewerService;
  resolveRecoveryManager: () => WebRecoveryManager;
  resolveUserAgentService: () => BrowserUserAgentService;
  resolveBrowsingIdentityPolicyCoordinator: () => BrowserBrowsingIdentityPolicyCoordinator;
  resolveUserAgentRuntimeService: () => BrowserUserAgentRuntimeService;
  scheduleOpenResolvedUrlWork?: (work: () => void) => BrowserRootBottomPanelDeferredWorkHandle | undefined;
}

export class BrowserWebLoadRuntimeCoordinator implements BrowserWebLoadExecutionHost {
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly runtimeMutationPort: BrowserRuntimeMutationPort;
  private readonly dependencies: BrowserWebLoadRuntimeDependencies;
  private readonly bindings: BrowserWebLoadRuntimeHostBindings;
  private readonly webLoadCoordinator: BrowserWebLoadCoordinator;
  private readonly dataLoadRequest: BrowserRuntimeWebDataLoadRequestAdapter;
  private runtimeNavigationRecoveryCoordinator?: BrowserRuntimeNavigationRecoveryCoordinator;
  private pendingActiveRuntimeSyncTimer: number = -1;
  private activeRuntimeSyncGeneration: number = 0;
  private pendingOpenResolvedUrlWork?: BrowserRootBottomPanelDeferredWorkHandle = undefined;
  private openResolvedUrlWorkGeneration: number = 0;
  private diagnosticOpenResolvedUrlSequence: number = 0;

  constructor(
    dependencies: BrowserWebLoadRuntimeDependencies,
    bindings: BrowserWebLoadRuntimeHostBindings,
    webLoadCoordinator: BrowserWebLoadCoordinator = new BrowserWebLoadCoordinator()
  ) {
    this.dependencies = dependencies;
    this.runtimeLifecyclePort = dependencies.runtimeLifecyclePort;
    this.runtimeMutationPort = dependencies.runtimeMutationPort;
    this.bindings = bindings;
    this.webLoadCoordinator = webLoadCoordinator;
    this.dataLoadRequest = new BrowserRuntimeWebDataLoadRequestAdapter(
      dependencies.runtimeMutationPort,
      dependencies.runtimeLifecyclePort,
      (tabId: string, targetUrl: string, strict: boolean): void => {
        this.syncEventContext(tabId, targetUrl, strict);
      },
      (state: BrowserWebDataLoadActiveControllerState): void => {
        this.bindings.applyControllerState(state.controller, state.controllerAttached);
      },
      (tabId: string, errorMessage: string): void => {
        this.recordLoadFailure(tabId, errorMessage);
      }
    );
  }

  resolveController(tabId: string): webview.WebviewController | undefined {
    return this.runtimeLifecyclePort.resolveController(tabId);
  }

  resolveRuntimeLoadUrl(targetUrl: string, tabId: string): string {
    return this.dependencies.visibleUrlService.resolveLoadUrl(targetUrl);
  }

  syncEventContext(tabId: string, targetUrl: string, strict: boolean): void {
    const visibleTargetUrl = this.dependencies.visibleUrlService.resolveVisibleUrl(targetUrl);
    sharedBrowserHttpsFirstNavigationService.rearmDeclinedRetry(tabId, visibleTargetUrl);
    sharedBrowserHttpsFirstNavigationService.attachFallbackExecutor(
      tabId,
      (fallbackTabId: string, fallbackUrl: string): boolean =>
        this.loadUrlForTab(fallbackTabId, fallbackUrl, true)
    );
    const navigationId = this.dependencies.webEventRouter.beginNavigation(
      tabId,
      visibleTargetUrl,
      strict,
      true
    );
    sharedBrowserHttpsFirstNavigationService.bindNavigationAttempt(tabId, visibleTargetUrl, navigationId);
  }

  clearControllerHistory(tabId: string): void {
    this.runtimeMutationPort.clearControllerHistory(tabId);
  }

  syncActiveController(tabId: string, controller: webview.WebviewController): void {
    const state = this.runtimeLifecyclePort.resolveWebLoadControllerState(
      tabId,
      controller,
      this.bindings.readFacts().currentUrl
    );
    this.applyUserAgentToControllerForTab(state.tabId, state.controller, state.userAgentPageUrl);
    if (!state.active) {
      return;
    }
    this.bindings.applyControllerState(state.controller, state.controllerAttached);
  }

  resolveDataPayload(targetUrl: string, tabId: string): BrowserWebLoadDataPayload | undefined {
    let payload = this.dependencies.resolveDocumentViewerService().buildLoadingPayload(targetUrl);
    if (payload === undefined && isBrowserNewWindowTestUrl(targetUrl)) {
      const testUrl = getBrowserNewWindowTestUrl();
      payload = {
        data: buildBrowserNewWindowTestHtml(),
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: testUrl,
        historyUrl: testUrl
      };
    }
    if (payload !== undefined) {
      this.scheduleDeferredDataPayloadLoad(tabId, targetUrl);
    }
    return payload;
  }

  recordLoadFailure(_tabId: string, _errorMessage: string): void {
  }

  loadUrlForTab(
    tabId: string,
    targetUrl: string,
    strict: boolean = true,
    clearHistory: boolean = false,
    primeNavigationFeedback: boolean = true
  ): boolean {
    const diagnosticStartedAt = Date.now();
    const runtimeTargetUrl = this.resolveRuntimeLoadUrl(targetUrl, tabId);
    if (this.dependencies.resolveOfflineFastFailureCoordinator().applyIfNeeded(tabId, runtimeTargetUrl)) {
      hilog.info(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] load_url_offline_fast_path tab=%{public}s targetLength=%{public}d elapsedMs=%{public}d',
        tabId,
        runtimeTargetUrl.length,
        Date.now() - diagnosticStartedAt
      );
      return true;
    }
    const loadPlan = this.webLoadCoordinator.buildLoadPlan(
      tabId,
      runtimeTargetUrl,
      strict,
      'shell_load_url',
      clearHistory
    );
    return this.executeLoadPlan(loadPlan, true, primeNavigationFeedback);
  }

  executeOpenResolvedUrl(
    result: BrowserOpenResolvedUrlApplicationResult
  ): BrowserOpenResolvedUrlExecutionResult {
    const diagnosticId = ++this.diagnosticOpenResolvedUrlSequence;
    const diagnosticStartedAt = Date.now();
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] open_begin id=%{public}d tab=%{public}s targetLength=%{public}d',
      diagnosticId,
      result.tabId,
      result.targetUrl.length
    );
    this.cancelPendingOpenResolvedUrlWork();
    const executionHost = this.buildOpenResolvedUrlExecutionHost(result, diagnosticId, diagnosticStartedAt);
    const scheduleWork = this.dependencies.scheduleOpenResolvedUrlWork;
    if (scheduleWork !== undefined) {
      executionHost.prepareOpenResolvedUrlState(result.targetUrl, result.title, result.helperMessage);
      hilog.info(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] open_prepared id=%{public}d elapsedMs=%{public}d',
        diagnosticId,
        Date.now() - diagnosticStartedAt
      );
      const generation = ++this.openResolvedUrlWorkGeneration;
      const deferredWork = scheduleWork((): void => {
        this.pendingOpenResolvedUrlWork = undefined;
        if (generation !== this.openResolvedUrlWorkGeneration || !this.isCurrentDeferredOpen(result)) {
          hilog.warn(
            BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
            BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
            '[DIAG-home-submit-20260828] open_deferred_stale id=%{public}d elapsedMs=%{public}d',
            diagnosticId,
            Date.now() - diagnosticStartedAt
          );
          return;
        }
        hilog.info(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] open_deferred_begin id=%{public}d elapsedMs=%{public}d',
          diagnosticId,
          Date.now() - diagnosticStartedAt
        );
        executionHost.revealOpenResolvedUrlSurface();
        hilog.info(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] open_revealed id=%{public}d elapsedMs=%{public}d',
          diagnosticId,
          Date.now() - diagnosticStartedAt
        );
        const loadResult = this.webLoadCoordinator.executeOpenResolvedUrl(result, executionHost, false);
        hilog.info(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] open_end id=%{public}d status=%{public}s elapsedMs=%{public}d',
          diagnosticId,
          loadResult.status,
          Date.now() - diagnosticStartedAt
        );
        if (loadResult.status === 'failed') {
          this.bindings.showRuntimeToast(loadResult.errorMessage);
        }
      });
      if (deferredWork !== undefined) {
        this.pendingOpenResolvedUrlWork = deferredWork;
        hilog.info(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] open_deferred_queued id=%{public}d elapsedMs=%{public}d',
          diagnosticId,
          Date.now() - diagnosticStartedAt
        );
        return {
          status: 'deferred',
          errorMessage: ''
        };
      }
      executionHost.revealOpenResolvedUrlSurface();
      hilog.info(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] open_revealed id=%{public}d deferred=false elapsedMs=%{public}d',
        diagnosticId,
        Date.now() - diagnosticStartedAt
      );
      const immediateLoadResult = this.webLoadCoordinator.executeOpenResolvedUrl(result, executionHost, false);
      hilog.info(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] open_end id=%{public}d status=%{public}s elapsedMs=%{public}d',
        diagnosticId,
        immediateLoadResult.status,
        Date.now() - diagnosticStartedAt
      );
      return immediateLoadResult;
    }
    executionHost.prepareOpenResolvedUrlState(result.targetUrl, result.title, result.helperMessage);
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] open_prepared id=%{public}d elapsedMs=%{public}d',
      diagnosticId,
      Date.now() - diagnosticStartedAt
    );
    executionHost.revealOpenResolvedUrlSurface();
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] open_revealed id=%{public}d elapsedMs=%{public}d',
      diagnosticId,
      Date.now() - diagnosticStartedAt
    );
    const loadResult = this.webLoadCoordinator.executeOpenResolvedUrl(result, executionHost, false);
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] open_end id=%{public}d status=%{public}s elapsedMs=%{public}d',
      diagnosticId,
      loadResult.status,
      Date.now() - diagnosticStartedAt
    );
    return loadResult;
  }

  private buildOpenResolvedUrlExecutionHost(
    result: BrowserOpenResolvedUrlApplicationResult,
    diagnosticId: number,
    diagnosticStartedAt: number
  ): BrowserOpenResolvedUrlHost {
    const controllerWasAttached = this.bindings.readFacts().controllerAttached;
    return {
      prepareOpenResolvedUrlState: (
        targetUrl: string,
        title: string,
        helperMessage: string
      ): void => {
        this.bindings.applyOpenResolvedUrlState({
          targetUrl: targetUrl,
          title: title,
          helperMessage: helperMessage,
          revealWebSurface: false
        });
        this.bindings.invalidateWebSessionTransition();
        this.dependencies.resolveLifecycleApplication().primeNavigationVisualFeedback(
          result.tabId,
          targetUrl,
          helperMessage,
          true
        );
      },
      revealOpenResolvedUrlSurface: (): void => {
        this.bindings.applyOpenResolvedUrlState({
          targetUrl: result.targetUrl,
          title: result.title,
          helperMessage: result.helperMessage,
          revealWebSurface: true
        });
        this.dependencies.syncCustomHomepageVisibility();
      },
      applyActiveTabPatch: (patch: BrowserTabRuntimePatch): void => {
        this.applyTabPatch(result.tabId, patch, {
          refreshRuntimeTabIds: [result.tabId]
        });
        hilog.info(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] tab_patch_applied id=%{public}d elapsedMs=%{public}d',
          diagnosticId,
          Date.now() - diagnosticStartedAt
        );
      },
      syncActiveRuntimeController: (): void => {
        const syncStartedAt = Date.now();
        if (controllerWasAttached) {
          this.cancelPendingActiveRuntimeSync();
          this.dependencies.syncActiveRuntime();
          hilog.info(
            BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
            BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
            '[DIAG-home-submit-20260828] active_runtime_sync id=%{public}d attached=true elapsedMs=%{public}d stageMs=%{public}d',
            diagnosticId,
            Date.now() - diagnosticStartedAt,
            Date.now() - syncStartedAt
          );
          return;
        }
        this.scheduleActiveRuntimeSync(result.tabId, result.targetUrl);
        hilog.info(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] active_runtime_sync id=%{public}d attached=false scheduled=true elapsedMs=%{public}d stageMs=%{public}d',
          diagnosticId,
          Date.now() - diagnosticStartedAt,
          Date.now() - syncStartedAt
        );
      },
      hasAttachedController: (): boolean => {
        return controllerWasAttached && this.bindings.readFacts().controllerAttached;
      },
      clearControllerAttachment: (): void => {
        this.bindings.applyControllerState(undefined, false);
      },
      executeLoadUrl: (tabId: string, targetUrl: string): boolean => {
        const loadStartedAt = Date.now();
        hilog.info(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] load_url_begin id=%{public}d tab=%{public}s targetLength=%{public}d elapsedMs=%{public}d',
          diagnosticId,
          tabId,
          targetUrl.length,
          Date.now() - diagnosticStartedAt
        );
        const issued = this.loadUrlForTab(tabId, targetUrl, true, false, false);
        hilog.info(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] load_url_end id=%{public}d issued=%{public}s elapsedMs=%{public}d stageMs=%{public}d',
          diagnosticId,
          issued ? 'true' : 'false',
          Date.now() - diagnosticStartedAt,
          Date.now() - loadStartedAt
        );
        return issued;
      }
    };
  }

  private isCurrentDeferredOpen(result: BrowserOpenResolvedUrlApplicationResult): boolean {
    const facts = this.bindings.readFacts();
    return facts.activeTabId === result.tabId && facts.currentUrl.trim() === result.targetUrl.trim();
  }

  private cancelPendingOpenResolvedUrlWork(): void {
    this.openResolvedUrlWorkGeneration += 1;
    this.pendingOpenResolvedUrlWork?.cancel();
    this.pendingOpenResolvedUrlWork = undefined;
  }

  private scheduleActiveRuntimeSync(tabId: string, targetUrl: string): void {
    this.cancelPendingActiveRuntimeSync();
    const generation = this.activeRuntimeSyncGeneration;
    this.pendingActiveRuntimeSyncTimer = setTimeout((): void => {
      this.pendingActiveRuntimeSyncTimer = -1;
      if (generation !== this.activeRuntimeSyncGeneration) {
        return;
      }
      const facts = this.bindings.readFacts();
      const runtime = this.runtimeLifecyclePort.resolveRuntime(tabId);
      if (facts.activeTabId !== tabId || facts.controllerAttached || runtime?.hasLiveController === true ||
        !this.isTabStillTargetingUrl(tabId, targetUrl)) {
        return;
      }
      this.dependencies.syncActiveRuntime();
    }, COLD_ACTIVE_RUNTIME_PRESENTATION_DELAY_MS);
  }

  private cancelPendingActiveRuntimeSync(): void {
    this.activeRuntimeSyncGeneration += 1;
    if (this.pendingActiveRuntimeSyncTimer < 0) {
      return;
    }
    clearTimeout(this.pendingActiveRuntimeSyncTimer);
    this.pendingActiveRuntimeSyncTimer = -1;
  }

  restoreWebViewToRestorableUrl(
    tabId: string,
    skippedUrl: string,
    fallbackUrl: string,
    reason: string
  ): void {
    this.resolveRuntimeNavigationRecoveryCoordinator().restoreWebViewToRestorableUrl(
      tabId,
      skippedUrl,
      fallbackUrl,
      reason
    );
  }

  scheduleTransientRestoreRetry(tabId: string, errorMessage: string): boolean {
    return this.resolveRuntimeNavigationRecoveryCoordinator().scheduleTransientRestoreRetry(tabId, errorMessage);
  }

  buildControllerBootstrapConfig(
    downloadDelegate?: webview.WebDownloadDelegate
  ): WebControllerBootstrapConfig {
    return {
      downloadDelegate: downloadDelegate
    };
  }

  observeUserAgentAtPageBegin(tabId: string, pageUrl: string): void {
    const facts = this.bindings.readFacts();
    const context = this.resolveUserAgentRuntimeContext(tabId, pageUrl, facts.currentProfileId);
    this.resolveUserAgentForContext(context, true);
  }

  prepareWebMainFrameNavigation(tabId: string, targetUrl: string, startsNewTransaction: boolean): boolean {
    const facts = this.bindings.readFacts();
    const context = this.resolveUserAgentRuntimeContext(tabId, targetUrl, facts.currentProfileId);
    const resolution = this.resolveUserAgentForContext(context, false);
    return this.acceptUserAgentPreparation(
      this.dependencies.resolveUserAgentRuntimeService().prepareWebMainFrameNavigation(
        this.runtimeLifecyclePort,
        context.tabId,
        targetUrl,
        resolution,
        startsNewTransaction
      )
    );
  }

  prepareHistoryNavigation(
    tabId: string,
    targetUrl: string,
    targetHistoryIndex: number,
    direction: 'back' | 'forward'
  ): boolean {
    const facts = this.bindings.readFacts();
    const context = this.resolveUserAgentRuntimeContext(tabId, targetUrl, facts.currentProfileId);
    const fallbackResolution = this.resolveUserAgentForContext(context, false);
    return this.acceptUserAgentPreparation(
      this.dependencies.resolveUserAgentRuntimeService().prepareHistoryNavigation(
        this.runtimeLifecyclePort,
        context.tabId,
        targetUrl,
        targetHistoryIndex,
        direction,
        fallbackResolution
      )
    );
  }

  commitUserAgentNavigation(tabId: string, committedUrl: string, isMainFrame: boolean): void {
    if (!isMainFrame) {
      return;
    }
    this.dependencies.resolveUserAgentRuntimeService().commitNavigation(
      tabId,
      this.runtimeLifecyclePort.resolveController(tabId),
      committedUrl
    );
  }

  cancelUserAgentNavigation(tabId: string): void {
    this.dependencies.resolveUserAgentRuntimeService().cancelNavigation(tabId);
  }

  loadWebContextMenuLinkForTab(
    tabId: string,
    targetUrl: string
  ): boolean {
    return this.loadUrlForTab(tabId, targetUrl, true, true);
  }

  buildOpenResolvedUrlApplicationResult(
    tabId: string,
    resolvedUrl: string,
    helperMessage: string,
    title: string
  ): BrowserOpenResolvedUrlApplicationResult {
    return this.webLoadCoordinator.buildOpenResolvedUrlApplicationResult(
      tabId,
      resolvedUrl,
      helperMessage,
      title
    );
  }

  runBackgroundTabPreviewLoad(tabId: string, targetUrl: string): boolean {
    if (!this.prepareUserAgentForNavigation(tabId, targetUrl)) {
      return false;
    }
    const issued = this.webLoadCoordinator.runBackgroundTabPreviewLoad(tabId, targetUrl, this);
    if (!issued) {
      this.cancelUserAgentNavigation(tabId);
    }
    return issued;
  }

  private executeLoadPlan(
    loadPlan: BrowserWebLoadPlan,
    syncEventContext: boolean = true,
    primeNavigationFeedback: boolean = true
  ): boolean {
    const startedAt = Date.now();
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] load_plan_begin tab=%{public}s source=%{public}s targetLength=%{public}d',
      loadPlan.tabId,
      loadPlan.source,
      loadPlan.targetUrl.length
    );
    if (!this.prepareUserAgentForNavigation(loadPlan.tabId, loadPlan.targetUrl)) {
      hilog.warn(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] load_plan_user_agent_failed tab=%{public}s elapsedMs=%{public}d',
        loadPlan.tabId,
        Date.now() - startedAt
      );
      return false;
    }
    if (primeNavigationFeedback) {
      this.dependencies.resolveLifecycleApplication().primeNavigationVisualFeedback(
        loadPlan.tabId,
        loadPlan.targetUrl
      );
    }
    const issued = this.webLoadCoordinator.runLoadPlan(loadPlan, this, syncEventContext);
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] load_plan_end tab=%{public}s source=%{public}s issued=%{public}s elapsedMs=%{public}d',
      loadPlan.tabId,
      loadPlan.source,
      issued ? 'true' : 'false',
      Date.now() - startedAt
    );
    if (!issued) {
      this.cancelUserAgentNavigation(loadPlan.tabId);
      this.dependencies.resolveLifecycleApplication().cancelNavigationVisualFeedbackIfLoadNotIssued(
        loadPlan.tabId,
        loadPlan.targetUrl
      );
    }
    return issued;
  }

  runDataLoad(
    tabId: string,
    targetUrl: string,
    payload: BrowserWebLoadDataPayload,
    syncEventContext: boolean = false
  ): boolean {
    return this.webLoadCoordinator.runDataLoad(
      tabId,
      targetUrl,
      payload,
      this.dataLoadRequest,
      syncEventContext
    );
  }

  private scheduleDeferredDataPayloadLoad(tabId: string, targetUrl: string): void {
    const deferredPayload = this.resolveDeferredDataPayload(targetUrl);
    if (deferredPayload === undefined) {
      return;
    }
    deferredPayload
      .then((payload: BrowserWebLoadDataPayload | undefined): void => {
        if (payload === undefined) {
          return;
        }
        if (!this.isTabStillTargetingUrl(tabId, targetUrl)) {
          return;
        }
        this.runDataLoad(tabId, targetUrl, payload, true);
      })
      .catch((_error: Error): void => {});
  }

  private resolveDeferredDataPayload(targetUrl: string): Promise<BrowserWebLoadDataPayload | undefined> | undefined {
    const documentViewerService = this.dependencies.resolveDocumentViewerService();
    if (!documentViewerService.isDocumentViewerUrl(targetUrl)) {
      return undefined;
    }
    return documentViewerService.buildPayloadFromViewerUrl(targetUrl);
  }

  private resolveRuntimeNavigationRecoveryCoordinator(): BrowserRuntimeNavigationRecoveryCoordinator {
    if (this.runtimeNavigationRecoveryCoordinator !== undefined) {
      return this.runtimeNavigationRecoveryCoordinator;
    }
    const host: BrowserRuntimeNavigationRecoveryCoordinatorHost = {
      readFacts: (): BrowserRuntimeNavigationRecoveryFacts => {
        const facts = this.bindings.readFacts();
        return {
          activeTabId: facts.activeTabId,
          tabs: facts.tabs
        };
      }
    };
    const dependencies: BrowserRuntimeNavigationRecoveryCoordinatorDependencies = {
      recoveryManager: this.dependencies.resolveRecoveryManager(),
      tabManager: this.dependencies.tabManager,
      runtimeLifecyclePort: this.runtimeLifecyclePort,
      downloadNavigationStateCoordinator: this.dependencies.downloadNavigationStateCoordinator,
      executeLoadUrl: (tabId: string, targetUrl: string, clearHistory: boolean): boolean => {
        return this.loadUrlForTab(tabId, targetUrl, true, clearHistory);
      },
      commitRetryTabPatch: (tabId: string, patch: BrowserTabRuntimePatch): void => {
        this.applyTabPatch(tabId, patch, { persistTabs: false });
      },
      resolveLifecycleApplication: this.dependencies.resolveLifecycleApplication
    };
    const coordinator = new BrowserRuntimeNavigationRecoveryCoordinator(host, dependencies);
    this.runtimeNavigationRecoveryCoordinator = coordinator;
    return coordinator;
  }

  private applyTabPatch(
    tabId: string,
    patch: BrowserTabRuntimePatch,
    options: TabMutationCommitOptions
  ): void {
    const nextTabs = this.dependencies.tabManager.updateTab(this.bindings.readFacts().tabs, tabId, patch);
    this.dependencies.commitTabs(nextTabs, {
      syncRuntimeGraph: options.syncRuntimeGraph,
      refreshRuntimeTabIds: options.refreshRuntimeTabIds ?? [tabId],
      persistTabs: options.persistTabs
    });
  }

  private isTabStillTargetingUrl(tabId: string, targetUrl: string): boolean {
    const tab = this.dependencies.tabManager.getTab(this.bindings.readFacts().tabs, tabId);
    if (tab === undefined) {
      return false;
    }
    const activeUrl = tab.pendingUrl.length > 0 ? tab.pendingUrl : tab.url;
    return activeUrl.trim() === targetUrl.trim();
  }

  applyUserAgentToController(controller: webview.WebviewController | undefined, pageUrl: string): boolean {
    return this.applyUserAgentToControllerForTab(this.bindings.readFacts().activeTabId, controller, pageUrl);
  }

  applyUserAgentToControllerForTab(
    tabId: string,
    controller: webview.WebviewController | undefined,
    pageUrl: string
  ): boolean {
    if (controller === undefined) {
      return false;
    }
    const runtimeService = this.dependencies.resolveUserAgentRuntimeService();
    if (runtimeService.isControllerIdentitySynchronized(tabId, controller)) {
      return true;
    }
    const facts = this.bindings.readFacts();
    const context = this.resolveUserAgentRuntimeContext(
      tabId,
      pageUrl,
      facts.currentProfileId
    );
    const resolution = this.resolveUserAgentForContext(context, false);
    return runtimeService.applyToControllerForTab(
      context.tabId,
      controller,
      resolution
    );
  }

  private prepareUserAgentForNavigation(tabId: string, targetUrl: string): boolean {
    const facts = this.bindings.readFacts();
    const context = this.resolveUserAgentRuntimeContext(
      tabId,
      targetUrl,
      facts.currentProfileId
    );
    this.clearUserAgentAffinityForExplicitNavigation(context);
    const resolution = this.resolveUserAgentForContext(context, false);
    return this.acceptUserAgentPreparation(
      this.dependencies.resolveUserAgentRuntimeService().prepareNavigation(
        this.runtimeLifecyclePort,
        context.tabId,
        targetUrl,
        resolution,
        'app_load'
      )
    );
  }

  private acceptUserAgentPreparation(preparation: BrowserUserAgentNavigationPreparation): boolean {
    if (preparation.transitionNoticeRequired) {
      this.bindings.showRuntimeToast(
        '为保留返回与前进历史，当前标签仍使用原网页标识；Web 运行时重建后生效。'
      );
    }
    return preparation.allowed;
  }

  private resolveUserAgentRuntimeContext(
    tabId: string,
    pageUrl: string,
    profileId: BrowserProfileId
  ): BrowserWebLoadUserAgentRuntimeContext {
    const facts = this.bindings.readFacts();
    const normalizedTabId = tabId.trim().length > 0 ? tabId.trim() : facts.activeTabId;
    const tab = this.dependencies.tabManager.getTab(facts.tabs, normalizedTabId);
    const requestedPageUrl = pageUrl.trim();
    const pendingPageUrl = tab?.pendingUrl.trim() ?? '';
    const committedPageUrl = tab?.url.trim() ?? '';
    const activePageUrl = normalizedTabId === facts.activeTabId ? facts.currentUrl.trim() : '';
    let selectedPageUrl = activePageUrl;
    if (committedPageUrl.length > 0) {
      selectedPageUrl = committedPageUrl;
    }
    if (pendingPageUrl.length > 0) {
      selectedPageUrl = pendingPageUrl;
    }
    if (requestedPageUrl.length > 0) {
      selectedPageUrl = requestedPageUrl;
    }
    const context: BrowserWebLoadUserAgentRuntimeContext = {
      tabId: normalizedTabId,
      pageUrl: selectedPageUrl,
      profileId: tab?.profileId ?? profileId,
      privateBrowsing: tab !== undefined && isBrowserDataBoundarySessionEphemeralTabLike({
        id: tab.id,
        profileId: tab.profileId,
        privacyMode: tab.privacyMode,
        dataScope: tab.dataScope
      }),
      observedOrigins: this.uniqueOrigins([
        requestedPageUrl,
        pendingPageUrl,
        committedPageUrl,
        activePageUrl
      ])
    };
    return context;
  }

  private resolveUserAgentForContext(
    context: BrowserWebLoadUserAgentRuntimeContext,
    allowRedirectAffinityExtension: boolean
  ): BrowserBrowsingIdentityDecision {
    const directResolution = this.resolveDirectUserAgent(context);
    return this.dependencies.resolveUserAgentRuntimeService().resolveForContext({
      tabId: context.tabId,
      profileId: context.profileId,
      currentOrigin: this.dependencies.resolveUserAgentService().extractOrigin(context.pageUrl),
      observedOrigins: context.observedOrigins
    }, directResolution, allowRedirectAffinityExtension, (targetOrigin: string): BrowserBrowsingIdentityDecision => {
      return this.dependencies.resolveBrowsingIdentityPolicyCoordinator().resolveWithSystemDefault(
        context.tabId,
        targetOrigin,
        context.profileId,
        context.privateBrowsing
      );
    });
  }

  private resolveDirectUserAgent(context: BrowserWebLoadUserAgentRuntimeContext): BrowserBrowsingIdentityDecision {
    return this.dependencies.resolveBrowsingIdentityPolicyCoordinator().resolveWithSystemDefault(
      context.tabId,
      context.pageUrl,
      context.profileId,
      context.privateBrowsing
    );
  }

  private clearUserAgentAffinityForExplicitNavigation(context: BrowserWebLoadUserAgentRuntimeContext): void {
    const targetOrigin = this.dependencies.resolveUserAgentService().extractOrigin(context.pageUrl);
    this.dependencies.resolveUserAgentRuntimeService().clearAffinityForExplicitNavigation(
      context.tabId,
      targetOrigin
    );
  }

  clearUserAgentRuntimeState(tabId: string): void {
    this.dependencies.resolveBrowsingIdentityPolicyCoordinator().releaseTab(tabId);
    this.dependencies.resolveUserAgentRuntimeService().releaseTab(
      tabId,
      this.runtimeLifecyclePort.resolveController(tabId)
    );
  }

  private uniqueOrigins(urls: string[]): string[] {
    return this.uniqueOriginValues(urls.map((url: string): string => {
      return this.dependencies.resolveUserAgentService().extractOrigin(url);
    }));
  }

  private uniqueOriginValues(origins: string[]): string[] {
    const unique: string[] = [];
    origins.forEach((origin: string): void => {
      const normalized = origin.trim();
      if (normalized.length > 0 && !unique.includes(normalized)) {
        unique.push(normalized);
      }
    });
    return unique;
  }
}
