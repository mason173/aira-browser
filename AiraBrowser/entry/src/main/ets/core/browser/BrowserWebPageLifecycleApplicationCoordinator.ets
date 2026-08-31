import {
  BrowserHistoryApiBridgePolicy,
  BrowserHistoryApiChangeEvent
} from '../web/BrowserHistoryApiBridge';
import {
  WebEventRouter,
  WebMainFrameEventKind,
  WebPageEventRoute,
  WebPageEventRouteInput
} from '../web/WebEventRouter';
import { WebPagePresentation, WebRuntimeBridge } from '../web/WebRuntimeBridge';
import { WebRecoveryManager } from '../web/WebRecoveryManager';
import { BrowserTabRuntimePatch, BrowserTabState, BrowserTabManagerPort } from '../tabs/TabManager';
import { resolveCurrentSiteUrl } from './AddressDisplayFormatter';
import { BrowserAddressDisplayCoordinator } from './BrowserAddressDisplayCoordinator';
import { BrowserShellStateCoordinator } from './BrowserShellStateCoordinator';
import { BrowserExperimentSettings, TabCrashReason } from '../../common/models/BrowserModels';
import { BrowserDownloadNavigationStateCoordinator } from './BrowserDownloadNavigationStateCoordinator';
import {
  BrowserErrorDocumentCommittedUrlResolution,
  BrowserErrorDocumentLoadCoordinator,
  BrowserErrorDocumentLoadRequest,
  BrowserErrorDocumentLoadShell
} from '../../services/web/BrowserErrorDocumentLoadCoordinator';
import {
  BrowserRuntimeNavigationRecoveryApplication
} from '../../services/web/BrowserRuntimeNavigationRecoveryCoordinator';
import {
  BrowserOfflineFastFailureApplication,
  BrowserOfflineFastFailureCoordinator
} from '../../services/web/BrowserOfflineFastFailureCoordinator';
import { BrowserWebNavigationStateSyncCoordinator } from '../../services/web/BrowserWebNavigationStateSyncCoordinator';
import { BrowserWebLoadRuntimeCoordinator } from '../../services/web/BrowserWebLoadRuntimeCoordinator';
import { BrowserActiveTabRuntimeRestoreCoordinator } from '../../services/web/BrowserActiveTabRuntimeRestoreCoordinator';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserRuntimeMutationPort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import { BrowserControllerAttachmentRuntimeCoordinator } from '../../services/web/BrowserControllerAttachmentRuntimeCoordinator';
import { TelegramWebCompatibilityService } from '../../services/web/TelegramWebCompatibilityService';
import {
  sharedBrowserHttpsFirstNavigationService
} from '../../services/web/BrowserHttpsFirstNavigationService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserWebCapabilityPromptApplicationCoordinator } from './BrowserWebCapabilityPromptApplicationCoordinator';
import {
  BrowserWebEventCommitCoordinator,
  BrowserWebFollowupEventHost,
  BrowserWebLoadFailureHost,
  BrowserWebNavigationHistoryMetadataHost,
  BrowserWebActiveSurfacePlan,
  BrowserWebPageCommitHost
} from './BrowserWebEventCommitCoordinator';
import {
  BrowserWebPageFeatureEffectsCoordinator,
  BrowserWebPageFeatureEffectsDependencies
} from './BrowserWebPageFeatureEffectsCoordinator';
import {
  BrowserWebPagePresentationEventCoordinator
} from './BrowserWebPagePresentationEventCoordinator';
import {
  BrowserWebActiveSurfaceCoordinator,
  BrowserWebActiveSurfaceScrollSource
} from './BrowserWebActiveSurfaceCoordinator';
import { BrowserWebLoadFailureSurfaceCoordinator } from './BrowserWebLoadFailureSurfaceCoordinator';
import { BrowserWebActiveTabChange, BrowserWebTabsController } from './BrowserWebTabsController';
import { BrowserPageFindCoordinator } from './BrowserPageFindCoordinator';
import {
  BrowserMediaDiscoveryCoordinator
} from './media/BrowserMediaDiscoveryCoordinator';
import { BrowserMediaDiscoveryHost } from './media/BrowserMediaDiscoveryModels';
import { BrowserBackgroundTabPreviewRuntimeCoordinator } from './BrowserBackgroundTabPreviewRuntimeCoordinator';
import { BrowserFaultClassifier } from './BrowserFaultClassifier';
import { BrowserHistoryVisitPersistenceCoordinator } from './BrowserHistoryVisitPersistenceCoordinator';
import { BrowserFaviconApplyHost } from './BrowserFaviconCoordinator';
import {
  BrowserPrivateProfileCookieLifecycleHost,
  BrowserPrivateProfileLifecycleCoordinator
} from './BrowserPrivateProfileLifecycleCoordinator';
import { WebpageTranslationCoordinator } from '../translation/WebpageTranslationCoordinator';
import { WebSessionStateStore } from '../web/WebSessionStateStore';
import {
  BrowserLoadingProgressCoordinator,
  BrowserLoadingProgressHost,
  BrowserLoadingProgressState
} from './BrowserLoadingProgressCoordinator';
import { WebScrollSmoothModeService } from '../../services/web/WebScrollSmoothModeService';
import { WebAppCurrentUrlService } from '../../services/webapps/WebAppCurrentUrlService';
import { WebAppSessionCoordinator } from '../webapps/WebAppSessionCoordinator';
import { OfflinePageSaveCoordinator } from '../offline/OfflinePageSaveCoordinator';
import {
  BrowserBackgroundOpenPromptCoordinator
} from './BrowserBackgroundOpenPromptCoordinator';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { BrowserChromeRuntimeState } from './BrowserChromeRuntimeCoordinator';
import { BrowserBottomChromeScrollCoordinator } from './BrowserBottomChromeScrollCoordinator';
import { BrowserPageChromeThemeSamplingCoordinator } from './BrowserPageChromeThemeSamplingCoordinator';
import { BrowserWebTopImmersionSessionCoordinator } from './BrowserWebTopImmersionSessionCoordinator';
import { BrowserWebScrollInteractionCoordinator } from './BrowserWebScrollInteractionCoordinator';
import { BrowserUnifiedLinkApplicationCoordinator } from './BrowserUnifiedLinkApplicationCoordinator';
import { BrowserArkWebMediaTakeoverCoordinator } from './media/BrowserArkWebMediaTakeoverCoordinator';
import {
  BrowserMediaRuntimeObservationApplicationCoordinator
} from './media/BrowserMediaRuntimeObservationApplicationCoordinator';
import { BrowserTabBackgroundSessionSyncCoordinator } from '../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import { BrowserTabSessionPersistenceCoordinator } from './BrowserTabSessionPersistenceCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import {
  BrowserSnapshotApplicationHost,
  BrowserTabRecoveryCoordinator
} from './BrowserTabRecoveryCoordinator';
import { WebStateSnapshotStore } from '../web/WebStateSnapshotStore';
import { BrowserPullRefreshCoordinator } from './BrowserPullRefreshCoordinator';
import { BrowserAddressSubmissionCoordinator } from '../navigation/BrowserAddressSubmissionCoordinator';
import { BrowserAppUrlOpenCoordinator } from './BrowserAppUrlOpenCoordinator';
import { BrowserRecentActionManager } from '../web/BrowserRecentActionManager';
import { SearchEngineRepository } from '../../data/search/SearchEngineRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { WebLoadErrorPresentation } from '../../services/web/WebLoadErrorPresentationService';
import {
  BrowserWebPageLifecycleActiveDocumentState,
  BrowserWebPageLifecycleApplicationHost,
  BrowserWebPageLifecycleErrorSurfaceState,
  BrowserWebPageLifecycleShellFacts
} from './BrowserWebPageLifecycleModels';
import { ElementInspectionSessionCoordinator } from './ElementInspectionSessionCoordinator';
import { BrowserQuickSearchSwitchingCoordinator } from '../search/BrowserQuickSearchSwitchingCoordinator';
import { webview } from '@kit.ArkWeb';
import { BrowserUrlThreatProtectionCoordinator } from './BrowserUrlThreatProtectionCoordinator';
import { sharedBrowserContinuationCoordinator } from './BrowserContinuationCoordinator';

const BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN: number = 0x0000;
const BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG: string = 'HomeSearchDiag';

export interface BrowserClosedTabRuntimeCleanupRequest {
  tabId: string;
  snapshotPath: string;
  shouldDeleteSnapshot: boolean;
  wasActive: boolean;
}

export type BrowserWebLoadErrorSurfaceAction = 'reload' | 'open_network_settings';

export interface BrowserWebPageLifecycleDependencies {
  visibleUrlService: TelegramWebCompatibilityService;
  webEventRouter: WebEventRouter;
  webRuntimeBridge: WebRuntimeBridge;
  commitCoordinator: BrowserWebEventCommitCoordinator;
  recoveryManager: WebRecoveryManager;
  downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;
  errorDocumentLoadShell: BrowserErrorDocumentLoadShell;
  loadFailureSurfaceCoordinator: BrowserWebLoadFailureSurfaceCoordinator;
  offlineFastFailureCoordinator: BrowserOfflineFastFailureCoordinator;
  webLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator;
  activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator;
  addressSubmissionCoordinator: BrowserAddressSubmissionCoordinator;
  appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  recentActionManager: BrowserRecentActionManager;
  searchEngineRepository: SearchEngineRepository;
  preferencesRepository: PreferencesRepository;
  quickSearchSwitchingCoordinator: BrowserQuickSearchSwitchingCoordinator;
  webTabsController: BrowserWebTabsController;
  webpageTranslationCoordinator: WebpageTranslationCoordinator;
  pageFindCoordinator: BrowserPageFindCoordinator;
  elementInspectionSessionCoordinator: ElementInspectionSessionCoordinator;
  navigationStateSyncCoordinator: BrowserWebNavigationStateSyncCoordinator;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  webScrollSmoothModeService: WebScrollSmoothModeService;
  sessionStateStore: WebSessionStateStore;
  historyApiBridgePolicy: BrowserHistoryApiBridgePolicy;
  mediaDiscoveryCoordinator: BrowserMediaDiscoveryCoordinator;
  mediaDiscoveryHost: BrowserMediaDiscoveryHost;
  backgroundTabPreviewRuntimeCoordinator: BrowserBackgroundTabPreviewRuntimeCoordinator;
  backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator;
  arkWebMediaTakeoverCoordinator: BrowserArkWebMediaTakeoverCoordinator;
  mediaRuntimeObservationCoordinator: BrowserMediaRuntimeObservationApplicationCoordinator;
  pullRefreshCoordinator: BrowserPullRefreshCoordinator;
  backgroundOpenPromptCoordinator: BrowserBackgroundOpenPromptCoordinator;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  faultClassifier: BrowserFaultClassifier;
  runtimeMutationPort: BrowserRuntimeMutationPort;
  controllerAttachmentRuntimeCoordinator: BrowserControllerAttachmentRuntimeCoordinator;
  activeSurfaceCoordinator: BrowserWebActiveSurfaceCoordinator;
  historyVisitPersistenceCoordinator: BrowserHistoryVisitPersistenceCoordinator;
  tabManager: BrowserTabManagerPort;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  faviconHost: BrowserFaviconApplyHost;
  privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator;
  privateProfileCookieLifecycleHost: BrowserPrivateProfileCookieLifecycleHost;
  featureEffectsDependencies: BrowserWebPageFeatureEffectsDependencies;
  webAppSessionCoordinator: WebAppSessionCoordinator;
  webAppCurrentUrlService: WebAppCurrentUrlService;
  offlinePageSaveCoordinator: OfflinePageSaveCoordinator;
  tabHomeCoordinator: BrowserTabHomeCoordinator;
  addressDisplayCoordinator: BrowserAddressDisplayCoordinator;
  shellStateCoordinator: BrowserShellStateCoordinator;
  topImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator;
  resolveWebScrollInteractionCoordinator: () => BrowserWebScrollInteractionCoordinator;
  resolveBottomChromeScrollCoordinator: () => BrowserBottomChromeScrollCoordinator;
  unifiedLinkApplicationCoordinator: BrowserUnifiedLinkApplicationCoordinator;
  tabSessionPersistenceCoordinator: BrowserTabSessionPersistenceCoordinator;
  webStateSnapshotStore: WebStateSnapshotStore;
  tabRecoveryCoordinator: BrowserTabRecoveryCoordinator;
  snapshotApplicationHost: BrowserSnapshotApplicationHost;
  pageChromeThemeSamplingCoordinator: BrowserPageChromeThemeSamplingCoordinator;
  httpsFirstPromptCoordinator: BrowserWebCapabilityPromptApplicationCoordinator;
  urlThreatProtectionCoordinator: BrowserUrlThreatProtectionCoordinator;
  loadingProgressTerminalHoldMs: number;
  metadataVisualUpdateDelayMs: number;
  pageEventFallbackUrl: string;
  host: BrowserWebPageLifecycleApplicationHost;
}

export class BrowserWebPageLifecycleApplicationCoordinator implements
  BrowserOfflineFastFailureApplication,
  BrowserRuntimeNavigationRecoveryApplication {
  private readonly dependencies: BrowserWebPageLifecycleDependencies;
  private readonly pageCommitHost: BrowserWebPageCommitHost;
  private readonly loadFailureHost: BrowserWebLoadFailureHost;
  private readonly followupHost: BrowserWebFollowupEventHost;
  private readonly navigationHistoryMetadataHost: BrowserWebNavigationHistoryMetadataHost;
  private readonly featureEffectsCoordinator: BrowserWebPageFeatureEffectsCoordinator;
  private readonly loadingProgressCoordinator: BrowserLoadingProgressCoordinator;
  private readonly loadingProgressHost: BrowserLoadingProgressHost;
  private readonly pagePresentationEventCoordinator: BrowserWebPagePresentationEventCoordinator;
  private readonly errorDocumentLoadCoordinator: BrowserErrorDocumentLoadCoordinator;
  private loadingProgressState: BrowserLoadingProgressState;
  private lastAppliedPageProgress: number = 0;
  private activePageLoadCompleted: boolean = false;

  constructor(dependencies: BrowserWebPageLifecycleDependencies) {
    this.dependencies = dependencies;
    this.pageCommitHost = this.buildPageCommitHost();
    this.loadFailureHost = this.buildLoadFailureHost();
    this.followupHost = this.buildFollowupEventHost();
    this.navigationHistoryMetadataHost = this.buildNavigationHistoryMetadataHost();
    this.featureEffectsCoordinator = new BrowserWebPageFeatureEffectsCoordinator(
      dependencies.featureEffectsDependencies
    );
    this.loadingProgressCoordinator = new BrowserLoadingProgressCoordinator({
      terminalHoldMs: dependencies.loadingProgressTerminalHoldMs
    });
    this.loadingProgressState = this.loadingProgressCoordinator.createState();
    this.loadingProgressHost = this.buildLoadingProgressHost();
    this.errorDocumentLoadCoordinator = new BrowserErrorDocumentLoadCoordinator({
      loadFailureSurfaceCoordinator: dependencies.loadFailureSurfaceCoordinator,
      hostedRuntimeSurfacePort: dependencies.hostedRuntimeSurfacePort,
      webLoadRuntimeCoordinator: dependencies.webLoadRuntimeCoordinator,
      runtimeLifecyclePort: dependencies.runtimeLifecyclePort,
      activeTabRuntimeRestoreCoordinator: dependencies.activeTabRuntimeRestoreCoordinator,
      addressSubmissionCoordinator: dependencies.addressSubmissionCoordinator,
      recentActionManager: dependencies.recentActionManager,
      searchEngineRepository: dependencies.searchEngineRepository,
      addressDisplayCoordinator: dependencies.addressDisplayCoordinator,
      visibleUrlService: dependencies.visibleUrlService,
      tabManager: dependencies.tabManager,
      tabSwitchCoordinator: dependencies.tabSwitchCoordinator,
      navigationStateSyncCoordinator: dependencies.navigationStateSyncCoordinator,
      topImmersionSessionCoordinator: dependencies.topImmersionSessionCoordinator,
      lifecycleHost: dependencies.host,
      completeActivePageLoadingProgress: (): void => this.finishActivePageLoadingProgress()
    }, dependencies.errorDocumentLoadShell);
    this.pagePresentationEventCoordinator = new BrowserWebPagePresentationEventCoordinator({
      tabManager: dependencies.tabManager,
      webEventRouter: dependencies.webEventRouter,
      commitCoordinator: dependencies.commitCoordinator,
      followupHost: this.followupHost,
      faviconHost: dependencies.faviconHost,
      webLoadRuntimeCoordinator: dependencies.webLoadRuntimeCoordinator,
      navigationStateSyncCoordinator: dependencies.navigationStateSyncCoordinator,
      backgroundTabPreviewRuntimeCoordinator: dependencies.backgroundTabPreviewRuntimeCoordinator,
      backgroundOpenPromptCoordinator: dependencies.backgroundOpenPromptCoordinator,
      privateProfileLifecycleCoordinator: dependencies.privateProfileLifecycleCoordinator,
      privateProfileCookieLifecycleHost: dependencies.privateProfileCookieLifecycleHost,
      isActivePageLoadCompleted: (): boolean => this.activePageLoadCompleted,
      getLastAppliedPageProgress: (): number => this.lastAppliedPageProgress,
      metadataVisualUpdateDelayMs: dependencies.metadataVisualUpdateDelayMs
    });
  }

  private resolveShellFacts(): BrowserWebPageLifecycleShellFacts {
    return this.dependencies.host.resolveShellFacts();
  }

  private findTabById(tabId: string): BrowserTabState | undefined {
    return this.dependencies.tabManager.getTab(this.resolveShellFacts().tabs, tabId);
  }

  private shouldHandleActiveWebTab(tabId: string): boolean {
    const facts = this.resolveShellFacts();
    return tabId === facts.activeTabId && facts.webPageVisible;
  }

  private applyTabPatch(tabId: string, patch: BrowserTabRuntimePatch, persistTabs: boolean): void {
    this.dependencies.tabSwitchCoordinator.applyTabPatch(tabId, patch, {
      persistTabs: persistTabs
    });
  }

  private resolvePageUrlForTab(tabId: string): string {
    const facts = this.resolveShellFacts();
    const tab = this.dependencies.tabManager.getTab(facts.tabs, tabId);
    if (tab === undefined) {
      return resolveCurrentSiteUrl(facts.currentUrl, facts.addressInput);
    }
    return resolveCurrentSiteUrl(tab.url, tab.pendingUrl);
  }

  private resolveCommittedAddressDisplayText(url: string): string {
    const facts = this.resolveShellFacts();
    return this.dependencies.addressDisplayCoordinator.resolveCommittedDisplay(
      facts.activeTabId,
      this.dependencies.visibleUrlService.resolveVisibleUrl(url)
    );
  }

  private publishActiveDocumentState(
    patch: Partial<BrowserWebPageLifecycleActiveDocumentState>
  ): void {
    const facts = this.resolveShellFacts();
    this.dependencies.host.applyActiveDocumentState({
      currentUrl: patch.currentUrl ?? facts.currentUrl,
      pendingWebUrl: patch.pendingWebUrl ?? facts.pendingWebUrl,
      addressInput: patch.addressInput ?? facts.addressInput,
      currentTitle: patch.currentTitle ?? facts.currentTitle
    });
  }

  private publishErrorSurfaceState(
    patch: Partial<BrowserWebPageLifecycleErrorSurfaceState>
  ): void {
    const facts = this.resolveShellFacts();
    this.dependencies.host.applyErrorSurfaceState({
      visible: patch.visible ?? facts.pageErrorSurfaceVisible,
      reloadHold: patch.reloadHold ?? facts.pageErrorSurfaceReloadHold,
      retryTabId: patch.retryTabId ?? facts.activeErrorDocumentRetryTabId
    });
  }

  private reconcileExternalNavigationPrompt(committedUrl: string = ''): void {
    const facts = this.resolveShellFacts();
    const currentPageUrl = committedUrl.trim().length > 0
      ? committedUrl
      : this.resolvePageUrlForTab(facts.activeTabId);
    this.dependencies.unifiedLinkApplicationCoordinator.reconcileExternalNavigationPromptForPageContext(
      this.dependencies.unifiedLinkApplicationCoordinator.buildExternalNavigationPromptPageContext({
        activeTabId: facts.activeTabId,
        currentPageUrl: currentPageUrl,
        webPageVisible: facts.webPageVisible,
        tabsOverviewVisible: facts.tabsSheetVisible
      })
    );
  }

  private resetActiveNavigationChrome(tabId: string, clearVisualCollapse: boolean): void {
    const webScrollInteractionCoordinator = this.dependencies.resolveWebScrollInteractionCoordinator();
    webScrollInteractionCoordinator.suppressProgrammaticScroll();
    this.dependencies.resolveBottomChromeScrollCoordinator().reset(
      tabId,
      webScrollInteractionCoordinator.getLastScrollY()
    );
    if (clearVisualCollapse) {
      this.dependencies.host.clearRootBottomChromeScrollVisualCollapse();
    }
  }

  private handleNavigationEntryCommittedShellEffects(
    tabId: string,
    url: string,
    isMainFrame: boolean
  ): void {
    if (!isMainFrame || tabId !== this.resolveShellFacts().activeTabId) {
      return;
    }
    this.resetActiveNavigationChrome(tabId, false);
    this.reconcileExternalNavigationPrompt(url);
  }

  async cleanupClosedTabRuntime(request: BrowserClosedTabRuntimeCleanupRequest): Promise<void> {
    const host = this.dependencies.host;
    this.featureEffectsCoordinator.blockClosedTabUserScriptDocument(request.tabId);
    sharedBrowserContinuationCoordinator.clearTab(request.tabId);
    this.dependencies.urlThreatProtectionCoordinator.clearTab(request.tabId);
    sharedBrowserHttpsFirstNavigationService.clearTab(request.tabId);
    this.dependencies.httpsFirstPromptCoordinator.clearHttpsFirstFallbackForTab(request.tabId);
    this.dependencies.webLoadRuntimeCoordinator.clearUserAgentRuntimeState(request.tabId);
    this.dependencies.elementInspectionSessionCoordinator.handleOriginRuntimeRemoved(request.tabId);
    if (request.shouldDeleteSnapshot) {
      await this.dependencies.webStateSnapshotStore.deleteSnapshot(request.snapshotPath);
      this.dependencies.tabRecoveryCoordinator.applySnapshotApplicationResult(
        this.dependencies.tabRecoveryCoordinator.buildSnapshotDeleteApplicationResult(
          request.tabId,
          request.snapshotPath,
          'tab_closed',
          {
            shouldRecordRuntimeEvent: false
          }
        ),
        this.dependencies.snapshotApplicationHost,
        this.resolveShellFacts().activeTabId
      );
    }
    this.dependencies.recoveryManager.clearTab(request.tabId);
    this.dependencies.mediaRuntimeObservationCoordinator.clearTab(request.tabId);
    this.dependencies.mediaDiscoveryCoordinator.clearTab(request.tabId);
    const webLiveWasActive = this.dependencies.arkWebMediaTakeoverCoordinator.clearTab(request.tabId);
    if (webLiveWasActive) {
      host.exitVideoAssistantFullscreen();
    }
    host.invalidateVideoAssistantPresentation();
    this.dependencies.backgroundSessionSyncCoordinator.release(request.tabId);
    this.dependencies.webpageTranslationCoordinator.handleTabDestroyedForRuntimeTab(
      request.tabId,
      this.resolveShellFacts().activeTabId,
      request.wasActive
    );
    this.dependencies.hostedRuntimeSurfacePort.release(request.tabId, 'tab_close');
    this.dependencies.runtimeLifecyclePort.removeClosedTabRuntime(request.tabId, 'tab_close');
  }

  prepareTabForTerminalClose(tabId: string): void {
    this.featureEffectsCoordinator.blockClosedTabUserScriptDocument(tabId);
    this.dependencies.webTabsController.stopLoading(tabId);
    this.dependencies.offlineFastFailureCoordinator.cancelForTab(tabId);
  }

  loadErrorDocument(request: BrowserErrorDocumentLoadRequest): boolean {
    return this.errorDocumentLoadCoordinator.load(request);
  }

  applyOfflineFastFailure(
    tabId: string,
    targetUrl: string,
    errorMessage: string,
    fallbackTab: BrowserTabState
  ): void {
    const activeWebTabBeforePatch = this.shouldHandleActiveWebTab(tabId);
    if (activeWebTabBeforePatch) {
      this.dependencies.host.applyActiveDocumentState({
        currentUrl: targetUrl,
        pendingWebUrl: targetUrl,
        addressInput: this.resolveCommittedAddressDisplayText(targetUrl),
        currentTitle: targetUrl
      });
      this.applyLoadingProgressError();
    }
    this.dependencies.tabSwitchCoordinator.applyTabPatch(tabId, {
      title: targetUrl,
      url: targetUrl,
      pendingUrl: targetUrl,
      isHome: false,
      runtimeState: 'error',
      lastError: errorMessage,
      lastRestoreReason: '',
      lastCrashReason: '',
      webStatePath: '',
      webStateUpdatedAt: 0
    }, {
      refreshRuntimeTabIds: [tabId]
    });
    this.dependencies.loadFailureSurfaceCoordinator.markFailure(tabId, errorMessage, targetUrl);
    if (!this.shouldHandleActiveWebTab(tabId)) {
      return;
    }
    this.setActivePageLoadCompleted(true);
    const failedTab = this.findTabById(tabId) ?? fallbackTab;
    this.dependencies.activeSurfaceCoordinator.applyVisualState(
      this.dependencies.shellStateCoordinator.buildPageErrorState(failedTab, errorMessage, '')
    );
    this.dependencies.webTabsController.stopLoading(tabId);
    this.loadErrorDocument({
      tabId: tabId,
      targetUrl: targetUrl,
      errorMessage: errorMessage
    });
  }

  applyTransientNavigationRetryState(): void {
    this.dependencies.host.applyRuntimeState({ errorMessage: '' });
    this.dependencies.host.applyRuntimeState({ runtimeDegradedMessage: '' });
    this.dependencies.host.applyRuntimeState({
      helperMessage: '检测到网络协议抖动，正在重新尝试恢复页面'
    });
    this.dependencies.host.applyRuntimeState({ loading: true });
    this.beginActivePageLoadingProgress();
  }

  handleErrorDocumentActionUrl(tabId: string, targetUrl: string): boolean {
    return this.errorDocumentLoadCoordinator.handleActionUrl(tabId, targetUrl);
  }

  handleActiveLoadErrorSurfaceAction(action: BrowserWebLoadErrorSurfaceAction): void {
    if (action === 'open_network_settings') {
      this.dependencies.host.openSystemNetworkSettings();
      return;
    }
    this.retryActivePageAfterLoadError();
  }

  private retryActivePageAfterLoadError(): void {
    this.errorDocumentLoadCoordinator.retryActivePageAfterLoadError();
  }

  buildActiveLoadErrorPresentation(): WebLoadErrorPresentation {
    return this.errorDocumentLoadCoordinator.buildActivePresentation();
  }

  resolveErrorDocumentCommittedUrl(
    tabId: string,
    candidateUrl: string,
    source: string
  ): BrowserErrorDocumentCommittedUrlResolution {
    return this.errorDocumentLoadCoordinator.resolveCommittedUrl(tabId, candidateUrl, source);
  }

  handleProgressChange(tabId: string, progress: number): void {
    this.dependencies.webTabsController.onProgressChange(tabId, progress);
    this.pagePresentationEventCoordinator.handleProgressChange(
      tabId,
      progress,
      this.dependencies.host
    );
  }

  handleTitleReceive(tabId: string, title: string): void {
    this.pagePresentationEventCoordinator.handleTitleReceive(
      tabId,
      title,
      this.dependencies.host
    );
  }

  handleFaviconReceived(tabId: string, event: OnFaviconReceivedEvent): void {
    this.pagePresentationEventCoordinator.handleFaviconReceived(
      tabId,
      event,
      this.dependencies.host
    );
  }

  createLoadingProgressState(): BrowserLoadingProgressState {
    return this.loadingProgressState;
  }

  handleActiveTabChanged(change: BrowserWebActiveTabChange): void {
    this.dependencies.webpageTranslationCoordinator.handleActiveTabChangedFromShell(
      change.previousTabId,
      change.activeTabId,
      change.activeUrl
    );
    this.reconcileExternalNavigationPrompt();
    this.dependencies.httpsFirstPromptCoordinator.handleActiveTabChanged(change.activeTabId);
    this.dependencies.urlThreatProtectionCoordinator.handleActiveTabChanged(change.activeTabId);
  }

  handleWebSurfaceVisibilityChanged(tabId: string, visible: boolean): void {
    this.dependencies.httpsFirstPromptCoordinator.handleWebSurfaceVisibilityChanged(tabId, visible);
  }

  restoreLoadingProgressState(progress: number, isLoading: boolean): void {
    this.lastAppliedPageProgress = progress;
    this.activePageLoadCompleted = !isLoading && progress >= 100;
    this.loadingProgressCoordinator.createStateFromProgressAndSchedule(
      progress,
      isLoading,
      this.loadingProgressHost
    );
  }

  beginActivePageLoadingProgress(): void {
    this.activePageLoadCompleted = false;
    this.lastAppliedPageProgress = 0;
    this.loadingProgressCoordinator.beginLoadAndSchedule(true, this.loadingProgressHost);
  }

  resetActivePageLoadingProgress(): void {
    this.activePageLoadCompleted = false;
    this.lastAppliedPageProgress = 0;
    this.loadingProgressCoordinator.resetForNonWebSurfaceAndSchedule(this.loadingProgressHost);
  }

  finishActivePageLoadingProgress(): void {
    if (this.activePageLoadCompleted && !this.loadingProgressState.isLoading) {
      return;
    }
    this.activePageLoadCompleted = true;
    this.lastAppliedPageProgress = 100;
    this.loadingProgressCoordinator.finishLoadAndSchedule(this.loadingProgressHost);
  }

  applyLoadingProgressError(): void {
    this.activePageLoadCompleted = true;
    this.lastAppliedPageProgress = 100;
    this.loadingProgressCoordinator.applyErrorAndSchedule(this.loadingProgressHost);
  }

  setActivePageLoadCompleted(completed: boolean): void {
    this.activePageLoadCompleted = completed;
  }

  shouldShowLoadingProgressVisualState(state: BrowserLoadingProgressState): boolean {
    return this.loadingProgressCoordinator.shouldShowVisualState(state);
  }

  cancelLoadingProgressTimers(): void {
    this.loadingProgressCoordinator.cancelTimers();
  }

  primeNavigationVisualFeedback(
    tabId: string,
    targetUrl: string,
    helperMessage: string = '',
    allowHiddenHomeSurface: boolean = false
  ): void {
    const host = this.dependencies.host;
    const facts = this.resolveShellFacts();
    const resolvedTargetUrl = targetUrl.trim();
    const activeTab = this.findTabById(tabId);
    const hiddenHomeSurfaceAllowed = allowHiddenHomeSurface && activeTab?.isHome === true;
    const activeTabMatchesRequest = tabId === facts.activeTabId;
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] progress_prime tab=%{public}s activeMatch=%{public}s webVisible=%{public}s hiddenHomeAllowed=%{public}s tabsSheet=%{public}s targetLength=%{public}d',
      tabId,
      activeTabMatchesRequest ? 'true' : 'false',
      facts.webPageVisible ? 'true' : 'false',
      hiddenHomeSurfaceAllowed ? 'true' : 'false',
      facts.tabsSheetVisible ? 'true' : 'false',
      resolvedTargetUrl.length
    );
    if (resolvedTargetUrl.length <= 0 || facts.tabsSheetVisible ||
      (!activeTabMatchesRequest && !hiddenHomeSurfaceAllowed)) {
      return;
    }
    if (!facts.webPageVisible && !hiddenHomeSurfaceAllowed) {
      return;
    }
    if (helperMessage.length > 0) {
      host.applyRuntimeState({ helperMessage: helperMessage });
    }
    this.activePageLoadCompleted = false;
    this.lastAppliedPageProgress = 0;
    this.loadingProgressCoordinator.beginNavigationIntentAndSchedule(this.loadingProgressHost);
  }

  pulseDownloadHandoffVisualFeedback(tabId: string, targetUrl: string): void {
    const facts = this.resolveShellFacts();
    if (tabId !== facts.activeTabId || targetUrl.trim().length <= 0 || facts.tabsSheetVisible || !facts.webPageVisible) {
      return;
    }
    this.activePageLoadCompleted = false;
    this.lastAppliedPageProgress = 0;
    this.loadingProgressCoordinator.pulseDownloadHandoffAndSchedule(this.loadingProgressHost);
  }

  cancelNavigationVisualFeedbackIfLoadNotIssued(tabId: string, targetUrl: string): void {
    const facts = this.resolveShellFacts();
    const resolvedTargetUrl = targetUrl.trim();
    this.dependencies.quickSearchSwitchingCoordinator.handleNavigationCancelled(tabId);
    if (tabId !== facts.activeTabId || resolvedTargetUrl.length <= 0) {
      return;
    }
    if (facts.pendingWebUrl === resolvedTargetUrl || facts.currentUrl === resolvedTargetUrl) {
      this.resetActivePageLoadingProgress();
    }
  }

  degradeBrokenActiveTabToHome(): void {
    const facts = this.resolveShellFacts();
    const activeTab = this.findTabById(facts.activeTabId);
    if (activeTab === undefined) {
      return;
    }
    void this.dependencies.tabHomeCoordinator.degradeBrokenActiveTab({
      tabId: activeTab.id,
      snapshotPath: activeTab.webStatePath,
      degradedReason: this.dependencies.recoveryManager.getDegradedReason(activeTab.id)
    });
  }

  refreshWebSmoothModeRuntime(tabId: string): void {
    this.dependencies.webScrollSmoothModeService.handlePageReadyFromLifecyclePort(
      this.dependencies.runtimeLifecyclePort,
      tabId,
      this.resolveShellFacts().webScrollExperimentSettings
    );
  }

  clearDeferredPageMetadata(tabId: string): void {
    this.pagePresentationEventCoordinator.clearDeferredPageMetadata(tabId);
  }

  flushDeferredPageMetadata(tabId: string): void {
    this.pagePresentationEventCoordinator.flushDeferredPageMetadata(
      tabId,
      this.dependencies.host
    );
  }

  handlePageBegin(tabId: string, event: OnPageBeginEvent): void {
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] page_begin tab=%{public}s urlLength=%{public}d',
      tabId,
      event.url.length
    );
    const host = this.dependencies.host;
    const webLiveWasActive = this.dependencies.arkWebMediaTakeoverCoordinator.beginNavigation(tabId);
    if (webLiveWasActive) {
      host.exitVideoAssistantFullscreen();
    }
    host.invalidateVideoAssistantPresentation();
    this.dependencies.backgroundSessionSyncCoordinator.clearRuntimePageBehavior(tabId, 'page_begin');
    this.handlePullRefreshPageBegin(tabId);
    const visibleEventUrl = this.dependencies.visibleUrlService.resolveVisibleUrl(event.url);
    const errorDocumentUrl = this.errorDocumentLoadCoordinator.resolveLoadFailureTargetUrl(tabId);
    if (this.dependencies.loadFailureSurfaceCoordinator.shouldIgnoreRepeatedMainFrameError(tabId, errorDocumentUrl)) {
      this.dependencies.offlineFastFailureCoordinator.cancelForTab(tabId);
      if (this.shouldHandleActiveWebTab(tabId)) {
        this.setActivePageLoadCompleted(true);
      }
      return;
    }
    if (this.shouldIgnoreStaleMainFrameWebEvent(tabId, visibleEventUrl, 'page_begin')) {
      return;
    }
    this.dependencies.urlThreatProtectionCoordinator.observePageBegin(tabId, visibleEventUrl);
    this.featureEffectsCoordinator.prepareForPageBegin(
      tabId,
      this.dependencies.host
    );
    this.dependencies.httpsFirstPromptCoordinator.handleNavigationStarted(tabId);
    this.dependencies.quickSearchSwitchingCoordinator.handlePageBegin(
      tabId,
      visibleEventUrl,
      this.dependencies.webTabsController.resolveHistoryTargetIntentUrl(tabId)
    );
    this.dependencies.elementInspectionSessionCoordinator.handlePageBegin(tabId);
    this.dependencies.webTabsController.onPageBegin(tabId, visibleEventUrl);
    if (tabId === this.resolveShellFacts().activeTabId) {
      this.reconcileExternalNavigationPrompt(visibleEventUrl);
    }
    this.dependencies.webpageTranslationCoordinator.handlePageBeginForRuntimeTab(
      tabId,
      this.resolveShellFacts().activeTabId,
      visibleEventUrl
    );
    this.dependencies.mediaRuntimeObservationCoordinator.beginDocument(tabId);
    if (this.shouldHandleActiveWebTab(tabId)) {
      if (this.dependencies.loadFailureSurfaceCoordinator.isWebDocumentLoading(tabId)) {
        this.applyLoadingProgressError();
      } else {
        this.beginActivePageLoadingProgress();
      }
      this.resetActiveNavigationChrome(tabId, true);
      this.featureEffectsCoordinator.applyActivePageBeginChromeEffects(this.dependencies.host);
    }
    this.dependencies.pageFindCoordinator.handlePageBegin(tabId);
    this.pagePresentationEventCoordinator.clearDeferredPageMetadata(tabId);
    this.dependencies.offlineFastFailureCoordinator.scheduleForLoadingTab(tabId, visibleEventUrl);
    this.dependencies.pageChromeThemeSamplingCoordinator.clearTab(tabId);
    const route = this.buildWebPageEventRoute(tabId, visibleEventUrl, false);
    const resolvedEventUrl = route.resolvedUrl;
    const downloadNavigationStateCoordinator = this.dependencies.downloadNavigationStateCoordinator;
    downloadNavigationStateCoordinator.markDocumentNavigationStarted(tabId, resolvedEventUrl);
    if (downloadNavigationStateCoordinator.shouldSuppressNavigationReplay(tabId, resolvedEventUrl, 'page_begin')) {
      return;
    }
    this.dependencies.navigationStateSyncCoordinator.recordCurrentDocumentUrl(tabId, resolvedEventUrl);
    const presentation = this.dependencies.webRuntimeBridge.resolvePageBegin({
      url: resolvedEventUrl
    } as OnPageBeginEvent, this.resolveCommittedAddressDisplayText(resolvedEventUrl));
    const commit = this.dependencies.commitCoordinator.buildPageBeginCommit({
      route: route,
      presentation: presentation
    });
    this.dependencies.commitCoordinator.applyPageBeginCommit(
      tabId,
      resolvedEventUrl,
      presentation,
      commit,
      this.pageCommitHost
    );
    if (this.shouldHandleActiveWebTab(tabId)) {
      this.dependencies.webLoadRuntimeCoordinator.observeUserAgentAtPageBegin(tabId, resolvedEventUrl);
    }
    this.featureEffectsCoordinator.applyManualElementHideRulesForPage(tabId, resolvedEventUrl);
  }

  handlePageEnd(tabId: string, event: OnPageEndEvent): void {
    const startedAt = Date.now();
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] page_end_begin tab=%{public}s urlLength=%{public}d',
      tabId,
      event.url.length
    );
    sharedBrowserHttpsFirstNavigationService.finishNavigation(tabId, event.url);
    try {
      this.handlePageEndTransaction(tabId, event);
    } finally {
      this.handlePullRefreshPageFinished(tabId);
      hilog.info(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] page_end_done tab=%{public}s elapsedMs=%{public}d',
        tabId,
        Date.now() - startedAt
      );
    }
  }

  private handlePageEndTransaction(tabId: string, event: OnPageEndEvent): void {
    const visibleEventUrl = this.dependencies.visibleUrlService.resolveVisibleUrl(event.url);
    this.dependencies.offlineFastFailureCoordinator.cancelForTab(tabId);
    if (this.dependencies.loadFailureSurfaceCoordinator.isWebDocumentLoading(tabId)) {
      this.errorDocumentLoadCoordinator.markCommitted(
        tabId,
        this.errorDocumentLoadCoordinator.resolveLoadFailureTargetUrl(tabId),
        'page_end'
      );
      return;
    }
    const errorDocumentUrl = this.errorDocumentLoadCoordinator.resolveLoadFailureTargetUrl(tabId);
    if (this.dependencies.loadFailureSurfaceCoordinator.shouldIgnoreRepeatedMainFrameError(tabId, errorDocumentUrl)) {
      if (this.shouldHandleActiveWebTab(tabId)) {
        this.setActivePageLoadCompleted(true);
      }
      return;
    }
    if (this.shouldIgnoreStaleMainFrameWebEvent(tabId, visibleEventUrl, 'page_end')) {
      return;
    }
    this.dependencies.webTabsController.onPageEnd(tabId, visibleEventUrl);
    this.dependencies.quickSearchSwitchingCoordinator.handlePageEnd(tabId, visibleEventUrl);
    this.dependencies.webpageTranslationCoordinator.handlePageEndForRuntimeTab(
      tabId,
      this.resolveShellFacts().activeTabId,
      visibleEventUrl
    );
    const route = this.buildWebPageEventRoute(tabId, visibleEventUrl, true);
    const resolvedEventUrl = route.resolvedUrl;
    const downloadNavigationStateCoordinator = this.dependencies.downloadNavigationStateCoordinator;
    if (downloadNavigationStateCoordinator.shouldIgnorePromptForInlineDocument(resolvedEventUrl)) {
      downloadNavigationStateCoordinator.resolveInlineDocumentNavigationPromotion(tabId, resolvedEventUrl);
    }
    if (downloadNavigationStateCoordinator.shouldSuppressNavigationReplay(tabId, resolvedEventUrl, 'page_end')) {
      return;
    }
    downloadNavigationStateCoordinator.markStableNavigationCommitted(tabId, resolvedEventUrl);
    this.dependencies.navigationStateSyncCoordinator.recordCurrentDocumentUrl(tabId, resolvedEventUrl);
    const isRestorableNavigationCandidate =
      !downloadNavigationStateCoordinator.shouldTreatAsNonRestorableNavigation(resolvedEventUrl);
    const presentation = this.dependencies.webRuntimeBridge.resolvePageEnd(
      {
        url: resolvedEventUrl
      } as OnPageEndEvent,
      this.resolveCommittedAddressDisplayText(resolvedEventUrl),
      this.dependencies.navigationStateSyncCoordinator.resolveTitleForCommittedUrl(tabId, resolvedEventUrl)
    );
    this.dependencies.runtimeLifecyclePort.rememberProvisionalNavigation(tabId, resolvedEventUrl);
    const sessionPatch = this.dependencies.sessionStateStore.buildLoadSuccessPatch(
      resolvedEventUrl,
      presentation.currentTitle
    );
    const commit = this.dependencies.commitCoordinator.buildPageEndCommit({
      route: route,
      presentation: presentation,
      sessionPatch: sessionPatch,
      isRestorableNavigation: isRestorableNavigationCandidate,
      shouldPromoteRestorableState: isRestorableNavigationCandidate
    });
    this.dependencies.recoveryManager.recordLoadSuccess(tabId);
    this.dependencies.commitCoordinator.applyPageEndCommit(
      tabId,
      resolvedEventUrl,
      presentation,
      commit,
      this.pageCommitHost
    );
    if (this.shouldHandleActiveWebTab(tabId)) {
      this.finishActivePageLoadingProgress();
      this.featureEffectsCoordinator.applyActivePageEndChromeEffects(
        tabId,
        this.dependencies.host
      );
    }
    void this.dependencies.webAppCurrentUrlService.recordInstalledWebAppUrl({
      activeContext: this.dependencies.webAppSessionCoordinator.getActive(this.resolveShellFacts().currentWindowId),
      tab: this.findTabById(tabId),
      url: resolvedEventUrl
    });
    this.featureEffectsCoordinator.applyPageEndEffects(
      tabId,
      resolvedEventUrl,
      presentation.currentTitle,
      this.dependencies.host
    );
    this.dependencies.backgroundOpenPromptCoordinator.updateTab(tabId, {
      title: presentation.currentTitle,
      url: resolvedEventUrl,
      progress: 100,
      isLoading: false
    });
  }

  handleLoadFinished(tabId: string): void {
    const startedAt = Date.now();
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] load_finished_begin tab=%{public}s',
      tabId
    );
    try {
      this.handleLoadFinishedTransaction(tabId);
    } finally {
      this.handlePullRefreshPageFinished(tabId);
      hilog.info(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] load_finished_done tab=%{public}s elapsedMs=%{public}d',
        tabId,
        Date.now() - startedAt
      );
    }
  }

  private handleLoadFinishedTransaction(tabId: string): void {
    this.dependencies.webTabsController.onLoadFinished(tabId);
    this.dependencies.offlineFastFailureCoordinator.cancelForTab(tabId);
    if (this.dependencies.loadFailureSurfaceCoordinator.isWebDocumentLoading(tabId)) {
      this.errorDocumentLoadCoordinator.markCommitted(
        tabId,
        this.errorDocumentLoadCoordinator.resolveLoadFailureTargetUrl(tabId),
        'load_finished'
      );
      return;
    }
    const errorDocumentUrl = this.errorDocumentLoadCoordinator.resolveLoadFailureTargetUrl(tabId);
    if (this.dependencies.loadFailureSurfaceCoordinator.shouldIgnoreRepeatedMainFrameError(tabId, errorDocumentUrl)) {
      if (tabId === this.resolveShellFacts().activeTabId) {
        this.finishActivePageLoadingProgress();
      }
      return;
    }
    const shouldHandleActiveTab = this.resolveFollowupRouteShouldHandleActiveTab(tabId);
    const commit = this.dependencies.commitCoordinator.buildLoadFinishedCommit(shouldHandleActiveTab);
    this.dependencies.commitCoordinator.applyLoadFinishedCommit(
      tabId,
      commit,
      this.followupHost
    );
    this.dependencies.pageFindCoordinator.handleLoadFinished(tabId);
    this.refreshWebSmoothModeRuntime(tabId);
    const loadFinishedUrl = this.dependencies.visibleUrlService.resolveVisibleUrl(this.resolvePageUrlForTab(tabId));
    void sharedBrowserContinuationCoordinator.applyPendingScrollAfterLoad(
      tabId,
      loadFinishedUrl,
      this.dependencies.runtimeLifecyclePort
    );
    this.featureEffectsCoordinator.applyLoadFinishedEffects(
      tabId,
      loadFinishedUrl,
      this.dependencies.host
    );
    if (tabId === this.resolveShellFacts().activeTabId) {
      this.finishActivePageLoadingProgress();
      this.featureEffectsCoordinator.applyActiveLoadFinishedChromeEffects(
        tabId,
        this.dependencies.host
      );
    }
    if (this.dependencies.offlinePageSaveCoordinator.consumePendingLinkSave(tabId)) {
      this.dependencies.offlinePageSaveCoordinator.startPendingLinkSave(tabId);
    }
    this.dependencies.backgroundOpenPromptCoordinator.updateTab(tabId, {
      progress: 100,
      isLoading: false
    });
    this.dependencies.backgroundTabPreviewRuntimeCoordinator.schedulePageReadyCapture(tabId, 'load_finished');
    this.dependencies.quickSearchSwitchingCoordinator.handleLoadFinished(tabId);
  }

  handleNavigationEntryCommitted(tabId: string, details: LoadCommittedDetails): void {
    const rawCommittedUrl = details.url.trim();
    const committedUrl = this.dependencies.visibleUrlService.resolveVisibleUrl(rawCommittedUrl);
    const downloadNavigationStateCoordinator = this.dependencies.downloadNavigationStateCoordinator;
    if (details.isMainFrame &&
      this.shouldIgnoreStaleMainFrameWebEvent(tabId, committedUrl, 'navigation_entry_committed')) {
      return;
    }
    if (details.isMainFrame &&
      this.errorDocumentLoadCoordinator.shouldIgnoreCommittedUrl(
        tabId,
        committedUrl,
        'navigation_entry_committed'
      )) {
      this.dependencies.webLoadRuntimeCoordinator.commitUserAgentNavigation(tabId, committedUrl, true);
      return;
    }
    if (details.isMainFrame &&
      downloadNavigationStateCoordinator.shouldSkipTabStatePersistence(
        tabId,
        committedUrl,
        'navigation_entry_committed'
      )) {
      downloadNavigationStateCoordinator.sanitizeRuntimeNavigationState(
        tabId,
        committedUrl,
        'navigation_entry_committed'
      );
      this.dependencies.webLoadRuntimeCoordinator.commitUserAgentNavigation(tabId, committedUrl, true);
      return;
    }
    this.dependencies.webLoadRuntimeCoordinator.commitUserAgentNavigation(
      tabId,
      committedUrl,
      details.isMainFrame
    );
    this.handleNavigationEntryCommittedShellEffects(tabId, committedUrl, details.isMainFrame);
    this.dependencies.webTabsController.onNavigationEntryCommitted(
      tabId,
      committedUrl,
      details.isMainFrame
    );
    this.dependencies.quickSearchSwitchingCoordinator.handleNavigationCommitted(
      tabId,
      committedUrl,
      {
        navigationType: details.navigationType,
        isMainFrame: details.isMainFrame,
        isSameDocument: details.isSameDocument,
        didReplaceEntry: details.didReplaceEntry
      }
    );
    if (details.isMainFrame) {
      this.dependencies.pageChromeThemeSamplingCoordinator.clearTab(tabId);
    }
    const shouldHandleActiveTab = this.resolveFollowupRouteShouldHandleActiveTab(tabId);
    const commit = this.dependencies.commitCoordinator.buildNavigationEntryCommittedCommit(
      shouldHandleActiveTab,
      details.isMainFrame
    );
    this.dependencies.commitCoordinator.applyNavigationEntryCommittedCommit(
      tabId,
      committedUrl,
      details.isMainFrame,
      shouldHandleActiveTab,
      commit,
      this.followupHost
    );
  }

  handleErrorReceive(tabId: string, event: OnErrorReceiveEvent): void {
    if (event.request.isMainFrame()) {
      const speculativePurpose = this.resolveSpeculativeRequestPurpose(event.request);
      if (speculativePurpose.length > 0) {
        return;
      }
      const failedUrl = this.dependencies.visibleUrlService.resolveVisibleUrl(event.request.getRequestUrl());
      const navigationDecision = this.dependencies.webEventRouter.resolveMainFrameEventDecision(
        tabId,
        failedUrl,
        'error_receive',
        {
          activeSurfaceVisible: this.shouldHandleActiveWebTab(tabId),
          foregroundUrlCandidates: [failedUrl]
        }
      );
      if (!navigationDecision.accepted) {
        this.handlePullRefreshPageFailed(tabId);
        return;
      }
      const httpsFirstDecision = sharedBrowserHttpsFirstNavigationService.resolveResourceFailureDecision(tabId, {
        requestUrl: event.request.getRequestUrl(),
        isMainFrame: true,
        errorCode: this.safeReadWebResourceErrorCode(event.error),
        navigationId: navigationDecision.navigationId
      });
      if (httpsFirstDecision.action === 'require_http_confirmation') {
        if (httpsFirstDecision.delivery === 'apply') {
          this.dependencies.httpsFirstPromptCoordinator.handleHttpsFirstFallbackDecision(tabId, httpsFirstDecision);
        }
      }
      if (httpsFirstDecision.action === 'automatic_http_fallback') {
        if (httpsFirstDecision.delivery === 'suppress_duplicate') {
          this.handlePullRefreshPageFailed(tabId);
          return;
        }
        const preparedFallback = sharedBrowserHttpsFirstNavigationService.prepareFallback(
          tabId,
          httpsFirstDecision.attemptId
        );
        if (preparedFallback !== undefined &&
          sharedBrowserHttpsFirstNavigationService.executePreparedFallback(preparedFallback)) {
          this.handlePullRefreshPageFailed(tabId);
          return;
        }
      }
    }
    try {
      this.handleErrorReceiveTransaction(tabId, event);
    } finally {
      this.handlePullRefreshPageFailed(tabId);
    }
  }

  private safeReadWebResourceErrorCode(error: WebResourceError): number {
    try {
      return error.getErrorCode();
    } catch (_error) {
      return 0;
    }
  }

  private handleErrorReceiveTransaction(tabId: string, event: OnErrorReceiveEvent): void {
    if (!event.request.isMainFrame()) {
      return;
    }
    const failedUrl = this.dependencies.visibleUrlService.resolveVisibleUrl(event.request.getRequestUrl());
    this.dependencies.webLoadRuntimeCoordinator.cancelUserAgentNavigation(tabId);
    this.dependencies.quickSearchSwitchingCoordinator.handleMainFrameFailure(tabId, failedUrl);
    const shouldHandleActiveWebTab = this.shouldHandleActiveWebTab(tabId);
    const errorMessage = `加载失败：${event.error.getErrorInfo()}`;
    const failureTargetUrl = this.errorDocumentLoadCoordinator.resolveLoadFailureTargetUrl(tabId);
    this.dependencies.backgroundOpenPromptCoordinator.updateTab(tabId, {
      progress: 100,
      isLoading: false
    });
    if (this.dependencies.loadFailureSurfaceCoordinator.shouldIgnoreRepeatedMainFrameError(tabId, failureTargetUrl)) {
      if (shouldHandleActiveWebTab) {
        this.setActivePageLoadCompleted(true);
      }
      return;
    }
    if (this.dependencies.loadFailureSurfaceCoordinator.isWebDocumentLoading(tabId)) {
      this.dependencies.loadFailureSurfaceCoordinator.markWebDocumentFailed(tabId);
      if (shouldHandleActiveWebTab) {
        this.publishErrorSurfaceState({ visible: true });
        this.dependencies.hostedRuntimeSurfacePort.detachActive();
      }
      return;
    }
    if (shouldHandleActiveWebTab) {
      this.setActivePageLoadCompleted(true);
      this.publishErrorSurfaceState({ retryTabId: '', reloadHold: false });
    }
    if (this.dependencies.webLoadRuntimeCoordinator.scheduleTransientRestoreRetry(tabId, errorMessage)) {
      return;
    }
    if (this.errorDocumentLoadCoordinator.tryAutomaticSearchFallback(tabId, failedUrl)) {
      return;
    }
    this.dependencies.loadFailureSurfaceCoordinator.markFailure(tabId, errorMessage, failureTargetUrl);
    if (shouldHandleActiveWebTab) {
      this.applyLoadingProgressError();
    }
    this.errorDocumentLoadCoordinator.load({
      tabId: tabId,
      targetUrl: failureTargetUrl,
      errorMessage: errorMessage
    });
    this.applyMainFrameLoadFailure(tabId, errorMessage);
    if (shouldHandleActiveWebTab && this.resolveShellFacts().hostedWebSurfaceSuspended) {
      this.dependencies.hostedRuntimeSurfacePort.detachActive();
    }
  }

  private resolveSpeculativeRequestPurpose(request: WebResourceRequest): string {
    const secPurpose = this.safeReadRequestHeader(request, 'sec-purpose');
    if (this.containsSpeculativePurposeToken(secPurpose)) {
      return secPurpose;
    }
    const purpose = this.safeReadRequestHeader(request, 'purpose');
    if (this.containsSpeculativePurposeToken(purpose)) {
      return purpose;
    }
    return '';
  }

  private containsSpeculativePurposeToken(value: string): boolean {
    const tokens = value.toLowerCase().split(/[;,]/);
    for (let index = 0; index < tokens.length; index += 1) {
      const token = tokens[index].trim();
      if (token === 'prefetch' || token === 'prerender') {
        return true;
      }
    }
    return false;
  }

  private safeReadRequestHeader(request: WebResourceRequest, name: string): string {
    try {
      const headers = request.getRequestHeader();
      const target = name.trim().toLowerCase();
      for (let index = 0; index < headers.length; index += 1) {
        const headerName = headers[index].headerKey ?? '';
        if (headerName.trim().toLowerCase() !== target) {
          continue;
        }
        return headers[index].headerValue?.trim() ?? '';
      }
    } catch (_error) {
    }
    return '';
  }

  applyMainFrameLoadFailure(tabId: string, errorMessage: string): void {
    const sideEffect = this.dependencies.commitCoordinator.commitMainFrameLoadFailure(
      {
        tabId: tabId,
        errorMessage: errorMessage,
        tab: this.findTabById(tabId),
        shouldHandleActiveTab: this.shouldHandleActiveWebTab(tabId),
        recoveryManager: this.dependencies.recoveryManager,
        faultClassifier: this.dependencies.faultClassifier
      }
    );
    this.dependencies.commitCoordinator.applyMainFrameLoadFailure(
      tabId,
      sideEffect,
      this.loadFailureHost
    );
  }

  private handlePullRefreshPageBegin(tabId: string): void {
    this.dependencies.pullRefreshCoordinator.handlePageBegin(tabId);
  }

  private handlePullRefreshPageFinished(tabId: string): void {
    this.dependencies.pullRefreshCoordinator.completePageRefresh(tabId);
  }

  private handlePullRefreshPageFailed(tabId: string): void {
    this.dependencies.pullRefreshCoordinator.completePageRefresh(tabId);
  }

  private buildWebPageEventRoute(tabId: string, eventUrl: string, isPageEnd: boolean): WebPageEventRoute {
    const facts = this.resolveShellFacts();
    const visibleEventUrl = this.dependencies.visibleUrlService.resolveVisibleUrl(eventUrl);
    const input: WebPageEventRouteInput = {
      tabId: tabId,
      activeTabId: facts.activeTabId,
      activeSurfaceVisible: facts.webPageVisible,
      tab: this.findTabById(tabId),
      eventUrl: visibleEventUrl,
      fallbackUrl: this.dependencies.pageEventFallbackUrl
    };
    if (isPageEnd) {
      return this.dependencies.webEventRouter.resolvePageEndRoute(input);
    }
    return this.dependencies.webEventRouter.resolvePageBeginRoute(input);
  }

  private shouldIgnoreStaleMainFrameWebEvent(
    tabId: string,
    eventUrl: string,
    eventName: WebMainFrameEventKind
  ): boolean {
    const facts = this.resolveShellFacts();
    const tab = this.findTabById(tabId);
    const visibleEventUrl = this.dependencies.visibleUrlService.resolveVisibleUrl(eventUrl);
    const foregroundUrlCandidates = [
      this.dependencies.webTabsController.resolveHistoryTargetIntentUrl(facts.activeTabId),
      facts.pendingWebUrl,
      facts.currentUrl,
      this.resolveActiveRuntimeUrlCandidate()
    ];
    foregroundUrlCandidates.push(tab?.pendingUrl ?? '');
    const decision = this.dependencies.webEventRouter.resolveMainFrameEventDecision(tabId, visibleEventUrl, eventName, {
      activeSurfaceVisible: this.shouldHandleActiveWebTab(tabId),
      foregroundUrlCandidates: foregroundUrlCandidates
    });
    if (decision.accepted) {
      return false;
    }
    return true;
  }

  private resolveActiveRuntimeUrlCandidate(): string {
    const controller: webview.WebviewController | undefined =
      this.dependencies.runtimeLifecyclePort.resolveActiveController();
    if (controller === undefined) {
      return '';
    }
    try {
      return this.dependencies.visibleUrlService.resolveVisibleUrl(controller.getUrl());
    } catch (_error) {
      return '';
    }
  }

  private resolveFollowupRouteShouldHandleActiveTab(tabId: string): boolean {
    const facts = this.resolveShellFacts();
    return this.dependencies.webEventRouter.resolveFollowupRoute(
      tabId,
      facts.activeTabId,
      facts.webPageVisible
    ).shouldHandleActiveTab;
  }

  handleHistoryApiUrlChange(tabId: string, payloadJson: string): void {
    const previousUrl = this.resolvePageUrlForTab(tabId);
    const decision = this.dependencies.historyApiBridgePolicy.resolveChange(payloadJson, previousUrl);
    if (!decision.accepted || decision.event === undefined) {
      return;
    }
    this.applyHistoryApiUrlChange(tabId, decision.event);
  }

  private applyHistoryApiUrlChange(
    tabId: string,
    event: BrowserHistoryApiChangeEvent
  ): void {
    const tab = this.findTabById(tabId);
    if (tab === undefined || tab.isHome) {
      return;
    }
    const url = this.dependencies.visibleUrlService.resolveVisibleUrl(event.newUrl);
    const normalizedEvent: BrowserHistoryApiChangeEvent = {
      kind: event.kind,
      oldUrl: this.dependencies.visibleUrlService.resolveVisibleUrl(event.oldUrl),
      newUrl: url,
      timestamp: event.timestamp
    };
    if (this.errorDocumentLoadCoordinator.shouldIgnoreCommittedUrl(
      tabId,
      url,
      'history_api_url_change'
    )) {
      return;
    }
    if (this.dependencies.downloadNavigationStateCoordinator
      .shouldSkipTabStatePersistence(tabId, url, 'history_api_url_change')) {
      return;
    }
    this.applyTabPatch(tabId, {
      url: url,
      pendingUrl: url,
      isHome: false,
      runtimeState: 'active'
    }, false);
    this.dependencies.runtimeLifecyclePort.patchRuntimeNavigationState(tabId, url);
    this.dependencies.commitCoordinator.recordNavigationMetadata(
      this.dependencies.tabManager,
      tabId,
      url,
      tab.title,
      this.navigationHistoryMetadataHost
    );
    this.dependencies.runtimeLifecyclePort.rememberProvisionalNavigation(tabId, url);
    if (this.shouldHandleActiveWebTab(tabId)) {
      this.publishActiveDocumentState({
        currentUrl: url,
        pendingWebUrl: url,
        addressInput: this.resolveCommittedAddressDisplayText(url)
      });
      this.dependencies.navigationStateSyncCoordinator.syncSoon();
    }
    this.featureEffectsCoordinator.applyHistoryUrlRuntimeEffects(
      tabId,
      url,
      this.dependencies.host
    );
    if (event.kind !== 'init') {
      this.dependencies.mediaRuntimeObservationCoordinator.advanceRoute(
        tabId,
        url,
        tab.title,
        event.kind + ':' + event.timestamp.toString(),
        event.timestamp
      );
      this.dependencies.runtimeLifecyclePort.publishAcceptedSpaRouteSignal({
        tabId: tabId,
        url: url,
        kind: event.kind,
        timestamp: event.timestamp
      });
    }
    if (tabId === this.resolveShellFacts().activeTabId) {
      this.reconcileExternalNavigationPrompt(url);
    }
    this.dependencies.webpageTranslationCoordinator.handleSpaRouteChangedForRuntimeTab(
      tabId,
      this.resolveShellFacts().activeTabId,
      url
    );
    this.dependencies.mediaDiscoveryCoordinator.scheduleSpaRouteProbeIfNeeded(
      tabId,
      url,
      tab.title,
      this.dependencies.mediaDiscoveryHost
    );
    if (event.kind !== 'init') {
      this.dependencies.quickSearchSwitchingCoordinator.handleHistoryApiUrlChange(tabId, normalizedEvent);
    }
  }

  private buildPageCommitHost(): BrowserWebPageCommitHost {
    return {
      rememberTabNavigation: (tabId: string, url: string): void => {
        this.dependencies.runtimeLifecyclePort.rememberCommittedNavigation(tabId, url);
      },
      rememberProvisionalTabNavigation: (tabId: string, url: string): void => {
        this.dependencies.runtimeLifecyclePort.rememberProvisionalNavigation(tabId, url);
      },
      applyTabPatch: (tabId: string, patch: BrowserTabRuntimePatch): void => {
        this.applyTabPatch(tabId, patch, true);
      },
      syncEventContext: (tabId: string, resolvedUrl: string): void => {
        this.dependencies.webEventRouter.beginNavigation(
          tabId,
          this.dependencies.visibleUrlService.resolveVisibleUrl(resolvedUrl),
          false
        );
      },
      updateControllerAttachedFromRuntime: (tabId: string): void => {
        this.dependencies.host.applyControllerAttachedState(
          this.dependencies.controllerAttachmentRuntimeCoordinator.resolveLiveRuntimeControllerState(
            tabId,
            this.resolveShellFacts().controllerAttached
          )
        );
      },
      applyPagePresentation: (
        tabId: string,
        plan: BrowserWebActiveSurfacePlan,
        presentation: WebPagePresentation,
        scrollSource: BrowserWebActiveSurfaceScrollSource
      ): void => {
        this.dependencies.activeSurfaceCoordinator.applyPagePresentation(
          { plan: plan },
          presentation,
          {
            tabId: tabId,
            scrollSource: scrollSource
          }
        );
      },
      recordHistoryVisit: (tabId: string, url: string, title: string): void => {
        this.dependencies.historyVisitPersistenceCoordinator.record(tabId, url, title);
      },
      recordTabNavigationMetadata: (tabId: string, url: string, title: string): void => {
        this.dependencies.commitCoordinator.recordNavigationMetadata(
          this.dependencies.tabManager,
          tabId,
          url,
          title,
          this.navigationHistoryMetadataHost
        );
      },
      shouldSkipTabStatePersistence: (tabId: string, url: string): boolean => {
        return this.dependencies.downloadNavigationStateCoordinator.shouldSkipTabStatePersistence(
          tabId,
          url,
          'web_commit_host'
        );
      },
      syncNavigationState: (): void => {
        this.dependencies.navigationStateSyncCoordinator.sync();
      },
      syncNavigationStateSoon: (): void => {
        this.dependencies.navigationStateSyncCoordinator.syncSoon();
      },
      releaseEventContext: (tabId: string): void => {
        this.dependencies.webEventRouter.releaseNavigation(tabId);
      }
    };
  }

  private buildLoadFailureHost(): BrowserWebLoadFailureHost {
    return {
      markTabCrashed: (tabId: string, degradedReason: string, crashReason: TabCrashReason): void => {
        this.dependencies.runtimeMutationPort.markTabCrashed(tabId, degradedReason, crashReason);
      },
      applyTabPatch: (tabId: string, patch: BrowserTabRuntimePatch): void => {
        this.applyTabPatch(tabId, patch, true);
      },
      applyLoadFailurePresentation: (
        tabId: string,
        plan: BrowserWebActiveSurfacePlan,
        userMessage: string,
        degradedReason: string
      ): void => {
        this.dependencies.activeSurfaceCoordinator.applyLoadFailurePresentation(
          { plan: plan },
          userMessage,
          degradedReason,
          {
            tabId: tabId,
            scrollSource: 'navigation_restore'
          }
        );
      },
      degradeBrokenActiveTabToHome: (): void => {
        this.degradeBrokenActiveTabToHome();
      }
    };
  }

  private buildFollowupEventHost(): BrowserWebFollowupEventHost {
    return {
      syncNavigationState: (): void => {
        this.dependencies.navigationStateSyncCoordinator.sync();
      },
      syncNavigationStateSoon: (): void => {
        this.dependencies.navigationStateSyncCoordinator.syncSoon();
      },
      setPageProgress: (pageProgress: number): void => {
        this.applyPageProgress(pageProgress);
      },
      rememberTabNavigation: (tabId: string, url: string): void => {
        this.dependencies.runtimeLifecyclePort.rememberCommittedNavigation(tabId, url);
      },
      rememberProvisionalTabNavigation: (tabId: string, url: string): void => {
        this.dependencies.runtimeLifecyclePort.rememberProvisionalNavigation(tabId, url);
      },
      applyNavigationCommittedPatch: (tabId: string, url: string): void => {
        this.applyNavigationCommittedPatch(tabId, url);
      },
      updateActiveCommittedUrl: (url: string): void => {
        this.updateActiveCommittedUrl(url);
      },
      shouldSkipTabStatePersistence: (tabId: string, url: string): boolean => {
        return this.dependencies.downloadNavigationStateCoordinator.shouldSkipTabStatePersistence(
          tabId,
          url,
          'web_commit_host'
        );
      },
      applyTabTitle: (tabId: string, title: string): void => {
        this.applyTabTitle(tabId, title);
      },
      updateActiveTitle: (title: string): void => {
        this.publishActiveDocumentState({ currentTitle: title });
      }
    };
  }

  private applyNavigationCommittedPatch(tabId: string, url: string): void {
    if (this.dependencies.downloadNavigationStateCoordinator.shouldSkipTabStatePersistence(
      tabId,
      url,
      'navigation_entry_patch'
    )) {
      return;
    }
    const committedUrl = url.trim();
    if (committedUrl.length <= 0) {
      return;
    }
    this.dependencies.navigationStateSyncCoordinator.recordCurrentDocumentUrl(tabId, committedUrl);
    const nextTitle = this.dependencies.navigationStateSyncCoordinator.resolveTitleForCommittedUrl(
      tabId,
      committedUrl
    );
    this.applyTabPatch(tabId, {
      title: nextTitle,
      url: committedUrl,
      pendingUrl: committedUrl,
      isHome: false,
      runtimeState: 'loading',
      lastError: ''
    }, false);
    if (!this.shouldHandleActiveWebTab(tabId)) {
      return;
    }
    this.publishActiveDocumentState({
      currentUrl: committedUrl,
      pendingWebUrl: committedUrl,
      addressInput: this.resolveCommittedAddressDisplayText(committedUrl),
      currentTitle: nextTitle
    });
  }

  private updateActiveCommittedUrl(url: string): void {
    const activeTabId = this.resolveShellFacts().activeTabId;
    if (this.errorDocumentLoadCoordinator.shouldIgnoreCommittedUrl(
      activeTabId,
      url,
      'active_committed_url'
    )) {
      return;
    }
    if (this.dependencies.downloadNavigationStateCoordinator.shouldBlockRuntimeNavigationCommit(activeTabId, url)) {
      return;
    }
    this.publishActiveDocumentState({
      currentUrl: url,
      addressInput: this.resolveCommittedAddressDisplayText(url)
    });
  }

  private applyTabTitle(tabId: string, title: string): void {
    if (this.dependencies.runtimeLifecyclePort.isTabNavigationProvisional(tabId)) {
      return;
    }
    this.applyTabPatch(tabId, {
      title: title,
      isHome: false
    }, true);
  }

  private applyPageProgress(pageProgress: number): void {
    const clampedProgress = Math.max(0, Math.min(100, Math.round(pageProgress)));
    if (clampedProgress >= 100) {
      this.activePageLoadCompleted = true;
    }
    this.lastAppliedPageProgress = clampedProgress;
    const loadingProgressState = this.loadingProgressCoordinator.applyRealProgressAndSchedule(
      clampedProgress,
      this.loadingProgressHost
    );
    if (loadingProgressState.visualState === 'complete') {
      this.activePageLoadCompleted = true;
    }
  }

  private buildLoadingProgressHost(): BrowserLoadingProgressHost {
    return {
      getLoadingProgressState: (): BrowserLoadingProgressState => {
        return this.loadingProgressState;
      },
      applyLoadingProgressState: (state: BrowserLoadingProgressState): void => {
        this.loadingProgressState = state;
        this.dependencies.host.applyLoadingProgressState(state);
      }
    };
  }

  private buildNavigationHistoryMetadataHost(): BrowserWebNavigationHistoryMetadataHost {
    return {
      resolveTabs: (): BrowserTabState[] => this.resolveShellFacts().tabs,
      resolveActiveTabId: (): string => this.resolveShellFacts().activeTabId,
      applyTabs: (tabs: BrowserTabState[]): void => {
        this.dependencies.host.applyTabs(tabs);
      },
      shouldSkipDownloadTabStatePersistence: (tabId: string, url: string, source: string): boolean => {
        return this.dependencies.downloadNavigationStateCoordinator.shouldSkipTabStatePersistence(tabId, url, source);
      },
      refreshRuntimeTab: (tabId: string): void => {
        this.dependencies.runtimeMutationPort.refresh([tabId]);
      },
      syncNavigationState: (): void => {
        this.dependencies.navigationStateSyncCoordinator.sync();
      },
      persistTabs: (): void => {
        this.dependencies.tabSessionPersistenceCoordinator.persist();
      }
    };
  }
}
