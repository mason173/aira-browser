import { BrowserExperimentSettings } from '../../common/models/BrowserModels';
import router from '@ohos.router';
import {
  CUSTOM_HOMEPAGE_RETURN_HOME_SOURCE,
  CUSTOM_HOMEPAGE_RETURN_HOME_VALUE
} from '../customhome/CustomHomepagePreviewViewModel';
import { resolveCurrentSiteUrl } from './AddressDisplayFormatter';
import {
  sharedBrowserGestureOnboardingPromptCoordinator,
  sharedBrowserProxyRuntimeRefreshCoordinator,
  sharedPreferencesRepository,
  sharedSyncExperienceCoordinator
} from '../../app/bootstrap/BrowserAppRuntime';
import {
  BrowserSearchInvocationRuntime,
  BrowserSearchInvocationSurfaceConnection
} from '../../app/runtime/BrowserSearchInvocationRuntime';
import { BrowserWindowRuntime } from '../../app/runtime/BrowserWindowRuntime';
import { BrowserWebLayerGeometryStore } from '../../data/browser/BrowserWebLayerGeometryStore';
import { BrowserWebLayerGeometrySnapshot } from './BrowserWebLayerGeometryCache';
import { isBrowserThemePresentationScope } from '../theme/BrowserThemePreferenceScopes';
import { DownloadRuntimeService, PendingDownloadPromptState } from '../../services/download/DownloadRuntimeService';
import { DownloadV2TaskEntity } from '../../domain/downloadv2/DownloadV2TaskEntity';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import {
  BrowserRuntimeLifecyclePort,
  BrowserRuntimeMutationPort
} from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserTabBackgroundSessionSyncCoordinator } from '../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import { BrowserOfflineFastFailureCoordinator } from '../../services/web/BrowserOfflineFastFailureCoordinator';
import { CustomHomepageRuntimeCoordinator } from '../customhome/CustomHomepageRuntimeCoordinator';
import { BrowserPrivateModeLockCoordinator } from '../privacy/BrowserPrivateModeLockCoordinator';
import { BrowserPrivateTabCoordinator } from './BrowserPrivateTabCoordinator';
import { HomeShortcutStateCoordinator } from '../shortcuts/HomeShortcutStateCoordinator';
import { WebpageTranslationCoordinator } from '../translation/WebpageTranslationCoordinator';
import { UserScriptRuntimeCoordinator } from '../userscripts/UserScriptRuntimeCoordinator';
import { OfflinePageSaveCoordinator } from '../offline/OfflinePageSaveCoordinator';
import { BrowserTabManagerPort, BrowserTabState } from '../tabs/TabManager';
import { BrowserDownloadConfirmOverlayCoordinator } from './BrowserDownloadConfirmOverlayCoordinator';
import { BrowserDownloadNavigationStateCoordinator } from './BrowserDownloadNavigationStateCoordinator';
import { BrowserAppUrlOpenCoordinator } from './BrowserAppUrlOpenCoordinator';
import { BrowserFaultClassifier } from './BrowserFaultClassifier';
import { BrowserFullscreenSessionCoordinator } from './BrowserFullscreenSessionCoordinator';
import { BrowserHomePresentationSessionCoordinator } from './BrowserHomePresentationSessionCoordinator';
import { BrowserNativeNavigationConsumeCoordinator } from '../navigation/BrowserNativeNavigationConsumeCoordinator';
import {
  BrowserProxyAuthRefreshCoordinator,
  BrowserProxyRuntimeRefreshHost
} from './BrowserProxyAuthRefreshCoordinator';
import { BrowserRuntimeRefreshStateSink } from './BrowserRuntimeRefreshStateSink';
import { BrowserAdBlockCoordinator } from './BrowserAdBlockCoordinator';
import { BrowserPullRefreshCoordinator } from './BrowserPullRefreshCoordinator';
import { BrowserRecentlyClosedApplicationCoordinator } from './BrowserRecentlyClosedApplicationCoordinator';
import { ArticleReadingSessionOperations } from './ReaderModeCoordinator';
import { BrowserSiteControlsRuntimeCoordinator } from './BrowserSiteControlsRuntimeCoordinator';
import { BrowserSmartGripCoordinator, BrowserSmartGripState } from './BrowserSmartGripCoordinator';
import { BrowserTabCloseCoordinator } from './BrowserTabCloseCoordinator';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { BrowserTabPreviewCoordinator } from './BrowserTabPreviewCoordinator';
import { BrowserTabSessionPersistenceCoordinator } from './BrowserTabSessionPersistenceCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import { BrowserTabsOverviewSessionCoordinator } from './BrowserTabsOverviewSessionCoordinator';
import { BrowserWebPageLifecycleApplicationCoordinator } from './BrowserWebPageLifecycleApplicationCoordinator';
import { BrowserWebScrollInteractionCoordinator } from './BrowserWebScrollInteractionCoordinator';
import { BrowserWebTopImmersionSessionCoordinator } from './BrowserWebTopImmersionSessionCoordinator';
import { BrowserWindowAvoidAreaCoordinator } from './BrowserWindowAvoidAreaCoordinator';
import { BrowserWindowContextPort } from './BrowserWindowContextCoordinator';
import { BrowserMediaDiscoveryRuntimeContextFactory } from './media/BrowserMediaDiscoveryRuntimeContextFactory';
import { ManualElementHideRuntimeCoordinator } from '../adblock/ManualElementHideRuntimeCoordinator';
import { BrowserGestureOnboardingTopPromptState } from './BrowserGestureOnboardingPromptCoordinator';
import { ElementInspectionSessionCoordinator } from './ElementInspectionSessionCoordinator';
import { BrowserTransientSurfaceId } from './BrowserTransientSurfaceCoordinator';
import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';
import { BrowserRootBottomPanelSessionCoordinator } from './BrowserRootBottomPanelSessionCoordinator';

export interface BrowserShellLifecycleFacts {
  tabs: BrowserTabState[];
  activeTabId: string;
  currentWindowId: string;
  windowScopeId: string;
  currentUrl: string;
  addressInput: string;
  showHomePage: boolean;
  isRestoringTabs: boolean;
  hasHandledInitialPageShow: boolean;
  rootBottomPanelDetent: HomeSearchPanelDetent;
}

export interface BrowserShellLifecycleAppearanceState {
  globalImmersionEnabled: boolean;
  alwaysTopImmersionEnabled: boolean;
}

export interface BrowserShellLifecycleShell {
  readFacts: () => BrowserShellLifecycleFacts;
  setBrowserShellVisible: (visible: boolean) => void;
  setStartupHomeSurfacePending: (pending: boolean) => void;
  setInitialPageShowHandled: (handled: boolean) => void;
  refreshRootBottomPanelLayoutState: () => void;
  applyDownloadInfo: (message: string) => void;
  applyDownloadError: (userMessage: string, sourceMessage: string) => void;
  syncDownloadBoundary: () => void;
  applyInitialWebPresentation: () => void;
  syncWindowSafeInsets: () => void;
  applyAppearanceState: (state: BrowserShellLifecycleAppearanceState) => void;
  applyExperimentSettings: (settings: BrowserExperimentSettings) => void;
  incrementThemeModeActionVersion: () => void;
  incrementToolbarLayoutVersion: () => void;
  syncBottomPanelStatusBarStyle: () => void;
  applySmartGripState: (state: BrowserSmartGripState) => void;
  bindReaderModeSession: () => void;
  applyRestoredWebLayerGeometry: (snapshot?: BrowserWebLayerGeometrySnapshot) => void;
  setColdStartDeferredSurfaceContentMounted: (mounted: boolean) => void;
  restoreSavedTabs: () => void;
  captureLifecycleExitPreview: () => void;
  releaseAllKeyboardAvoidModes: () => void;
  restoreBottomPanelStatusBarStyle: () => void;
  resetTransientOverlays: (
    syncPromptFromService: boolean,
    preservedCustomBottomSurfaceIds?: BrowserTransientSurfaceId[]
  ) => void;
  persistActiveTabSnapshot: (reason: string) => void;
  dismissWebContextMenu: () => void;
  cancelDeferredTabsOverviewOpen: () => void;
  scheduleWebSafeInsetSettleSync: (source: string) => void;
  applyGestureOnboardingPromptState: (state: BrowserGestureOnboardingTopPromptState) => void;
  connectSearchInvocationSurface: () => void;
}

export interface BrowserShellLifecycleDependencies {
  windowContextCoordinator: BrowserWindowContextPort;
  searchInvocationSurfaceConnection: BrowserSearchInvocationSurfaceConnection;
  runtimeMutationPort: BrowserRuntimeMutationPort;
  downloadService: DownloadRuntimeService;
  downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;
  appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  downloadConfirmOverlayCoordinator: BrowserDownloadConfirmOverlayCoordinator;
  faultClassifier: BrowserFaultClassifier;
  backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator;
  tabHomeCoordinator: BrowserTabHomeCoordinator;
  customHomepageRuntimeCoordinator: CustomHomepageRuntimeCoordinator;
  homePresentationSessionCoordinator: BrowserHomePresentationSessionCoordinator;
  offlineFastFailureCoordinator: BrowserOfflineFastFailureCoordinator;
  readerModeCoordinator: ArticleReadingSessionOperations;
  homeShortcutStateCoordinator: HomeShortcutStateCoordinator;
  recentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator;
  tabCloseCoordinator: BrowserTabCloseCoordinator;
  tabSessionPersistenceCoordinator: BrowserTabSessionPersistenceCoordinator;
  tabPreviewCoordinator: BrowserTabPreviewCoordinator;
  webPageLifecycleApplicationCoordinator: BrowserWebPageLifecycleApplicationCoordinator;
  pullRefreshCoordinator: BrowserPullRefreshCoordinator;
  windowAvoidAreaCoordinator: BrowserWindowAvoidAreaCoordinator;
  manualElementHideRuntimeCoordinator: ManualElementHideRuntimeCoordinator;
  elementInspectionSessionCoordinator: ElementInspectionSessionCoordinator;
  webpageTranslationCoordinator: WebpageTranslationCoordinator;
  webScrollInteractionCoordinator: BrowserWebScrollInteractionCoordinator;
  offlinePageSaveCoordinator: OfflinePageSaveCoordinator;
  fullscreenSessionCoordinator: BrowserFullscreenSessionCoordinator;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  adBlockCoordinator: BrowserAdBlockCoordinator;
  tabsOverviewSessionCoordinator: BrowserTabsOverviewSessionCoordinator;
  privateTabCoordinator: BrowserPrivateTabCoordinator;
  privateModeLockCoordinator: BrowserPrivateModeLockCoordinator;
  siteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator;
  nativeNavigationConsumeCoordinator: BrowserNativeNavigationConsumeCoordinator;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  webTopImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator;
  userScriptRuntimeCoordinator: UserScriptRuntimeCoordinator;
  tabManager: BrowserTabManagerPort;
  proxyAuthRefreshCoordinator: BrowserProxyAuthRefreshCoordinator;
  proxyRuntimeRefreshHost: BrowserProxyRuntimeRefreshHost;
  runtimeRefreshStateSink: BrowserRuntimeRefreshStateSink;
  mediaDiscoveryRuntimeContextFactory: BrowserMediaDiscoveryRuntimeContextFactory;
  smartGripCoordinator: BrowserSmartGripCoordinator;
  webLayerGeometryStore: BrowserWebLayerGeometryStore;
  runtimeCoolingTickMs: number;
  rootBottomPanelSessionCoordinator: BrowserRootBottomPanelSessionCoordinator;
}

export class BrowserShellLifecycleCoordinator {
  private readonly dependencies: BrowserShellLifecycleDependencies;
  private readonly shell: BrowserShellLifecycleShell;
  private themePreferencesListenerKey: string = '';
  private proxyRuntimeRefreshListenerKey: string = '';
  private adBlockRuntimeRefreshListenerKey: string = '';
  private handledReturnHomeRouteToken: string = '';
  private alwaysUsePrivateModeEnabled: boolean = false;
  private startupSurfaceRestoreStarted: boolean = false;
  private postFirstFrameWorkCompleted: boolean = false;

  constructor(dependencies: BrowserShellLifecycleDependencies, shell: BrowserShellLifecycleShell) {
    this.dependencies = dependencies;
    this.shell = shell;
  }

  handleAppear(): void {
    this.startupSurfaceRestoreStarted = false;
    this.postFirstFrameWorkCompleted = false;
    this.shell.setStartupHomeSurfacePending(false);
    this.shell.setColdStartDeferredSurfaceContentMounted(false);
    this.shell.setBrowserShellVisible(true);
    this.shell.refreshRootBottomPanelLayoutState();
    this.shell.setInitialPageShowHandled(false);
    this.dependencies.windowContextCoordinator.resolveCurrentScope();
    this.dependencies.searchInvocationSurfaceConnection.disconnect();
    this.dependencies.runtimeMutationPort.setNavigationCommitGuard(
      (tabId: string, url: string): boolean =>
        this.dependencies.downloadNavigationStateCoordinator.shouldBlockRuntimeNavigationCommit(tabId, url)
    );
    this.bindDownloadCallbacks();
    this.shell.syncDownloadBoundary();
    this.shell.applyInitialWebPresentation();
    this.applyRuntimeRetentionSettings(false);
    this.shell.syncWindowSafeInsets();
    this.refreshAppearanceState();
    this.refreshExperimentState();
    this.dependencies.tabHomeCoordinator.refreshWallpaperPresentation();
    this.dependencies.tabHomeCoordinator.refreshAppearance();
    this.dependencies.customHomepageRuntimeCoordinator.start(true);
    this.dependencies.homePresentationSessionCoordinator.initializeStartupEntrance();
    this.bindThemePreferencesUpdates();
    this.bindSmartGripUpdates();
    this.dependencies.backgroundSessionSyncCoordinator.startCoolingTimer(this.dependencies.runtimeCoolingTickMs);
    this.dependencies.offlineFastFailureCoordinator.startMonitoring();
    this.dependencies.tabHomeCoordinator.loadSearchEngineSelection();
    this.shell.bindReaderModeSession();
    this.dependencies.readerModeCoordinator.loadPreferences();
    if (this.dependencies.windowContextCoordinator.hasPendingWebSceneLaunch()) {
      this.beginStartupSurfaceRestore();
    }
  }

  handlePostFirstFrame(): void {
    this.beginStartupSurfaceRestore();
    if (this.postFirstFrameWorkCompleted) {
      return;
    }
    this.postFirstFrameWorkCompleted = true;
    this.consumeRouteLaunchUrl();
    this.consumeReturnHomeRouteRequest();
    this.bindProxyRuntimeRefreshUpdates();
    this.bindAdBlockRuntimeRefreshUpdates();
    this.consumePendingAdBlockRuntimeRefresh();
    this.dependencies.elementInspectionSessionCoordinator.handleShellAppear();
    if (this.shell.readFacts().showHomePage) {
      this.dependencies.homeShortcutStateCoordinator.refresh();
      this.dependencies.recentlyClosedApplicationCoordinator.activateWindow(
        this.dependencies.windowContextCoordinator.resolveCurrentTabSessionProfileId()
      );
    }
  }

  private beginStartupSurfaceRestore(): void {
    if (this.startupSurfaceRestoreStarted) {
      return;
    }
    this.startupSurfaceRestoreStarted = true;
    const facts = this.shell.readFacts();
    const shouldHoldHomeSurface = facts.showHomePage &&
      sharedPreferencesRepository.getPreferences().general.startupRestorePolicy === 'open_home' &&
      !this.dependencies.windowContextCoordinator.hasPendingWebSceneLaunch();
    this.shell.setStartupHomeSurfacePending(shouldHoldHomeSurface);
    this.shell.setColdStartDeferredSurfaceContentMounted(true);
    this.restoreCachedWebLayerGeometry();
    this.shell.restoreSavedTabs();
  }

  handleDisappear(): void {
    this.shell.captureLifecycleExitPreview();
    this.shell.setBrowserShellVisible(false);
    this.shell.setStartupHomeSurfacePending(false);
    this.dependencies.searchInvocationSurfaceConnection.disconnect();
    this.dependencies.customHomepageRuntimeCoordinator.syncVisibility();
    this.shell.releaseAllKeyboardAvoidModes();
    this.shell.restoreBottomPanelStatusBarStyle();
    this.dependencies.webTopImmersionSessionCoordinator.releaseVisible('page-disappear');
    this.dependencies.downloadConfirmOverlayCoordinator.abandonPendingPromptForDisappear();
    this.shell.resetTransientOverlays(false, this.resolveLifecyclePreservedCustomBottomSurfaceIds());
    this.shell.persistActiveTabSnapshot('page-disappear');
    if (!this.dependencies.tabCloseCoordinator.flushScheduledTabSessionPersist()) {
      this.dependencies.tabSessionPersistenceCoordinator.persist();
    }
    this.dependencies.backgroundSessionSyncCoordinator.handleAppBackground(this.shell.readFacts().windowScopeId);
    this.dependencies.tabPreviewCoordinator.cancelScheduledCapture();
    this.dependencies.backgroundSessionSyncCoordinator.stopCoolingTimer();
    this.dependencies.offlineFastFailureCoordinator.stopMonitoring();
    this.dependencies.webPageLifecycleApplicationCoordinator.cancelLoadingProgressTimers();
    this.dependencies.pullRefreshCoordinator.handleShellDisappear();
    this.dependencies.windowAvoidAreaCoordinator.cancelSafeInsetSettleSync();
    this.shell.dismissWebContextMenu();
    this.shell.cancelDeferredTabsOverviewOpen();
    this.dependencies.manualElementHideRuntimeCoordinator.handlePageDisappear();
    this.dependencies.elementInspectionSessionCoordinator.handleShellDisappear();
    this.dependencies.webpageTranslationCoordinator.handleShellDisappear();
    this.dependencies.webScrollInteractionCoordinator.handleShellDisappear();
    this.dependencies.offlinePageSaveCoordinator.handleShellDisappear();
    this.dependencies.windowContextCoordinator.stopPendingLaunchPolling();
    this.dependencies.fullscreenSessionCoordinator.cancelOrientationReapply();
    this.dependencies.windowAvoidAreaCoordinator.cancelFullscreenInsetRestore();
    this.shell.applyGestureOnboardingPromptState(sharedBrowserGestureOnboardingPromptCoordinator.dispose());
    this.dependencies.hostedRuntimeSurfacePort.releaseForPageDisappear();
    this.unbindProxyRuntimeRefreshUpdates();
    this.unbindAdBlockRuntimeRefreshUpdates();
    this.unbindThemePreferencesUpdates();
    this.dependencies.customHomepageRuntimeCoordinator.stop();
    this.unbindSmartGripUpdates();
    this.dependencies.rootBottomPanelSessionCoordinator.cancelBackdropFocusTransition();
    this.dependencies.tabsOverviewSessionCoordinator.resetBackdropPresentation();
    this.dependencies.readerModeCoordinator.shutdownSpeechSession();
  }

  handlePageShow(): void {
    this.shell.setBrowserShellVisible(true);
    this.dependencies.readerModeCoordinator.resetSpeechAfterLifecycleResume();
    this.dependencies.windowContextCoordinator.resolveCurrentScope();
    const facts = this.shell.readFacts();
    BrowserSearchInvocationRuntime.notifyForeground(facts.currentWindowId);
    BrowserWindowRuntime.markWindowForeground(facts.currentWindowId);
    this.dependencies.backgroundSessionSyncCoordinator.markAppForeground(facts.windowScopeId);
    if (!facts.hasHandledInitialPageShow) {
      this.dependencies.rootBottomPanelSessionCoordinator.restoreSearchBackdropPresentation(
        facts.rootBottomPanelDetent
      );
      this.shell.setInitialPageShowHandled(true);
      this.dependencies.homePresentationSessionCoordinator.playPendingStartupEntrance();
      this.shell.connectSearchInvocationSurface();
      this.dependencies.privateModeLockCoordinator.handleForegroundResume();
      this.dependencies.tabHomeCoordinator.schedulePromptEvaluations();
      return;
    }
    this.shell.resetTransientOverlays(true, this.resolveLifecyclePreservedCustomBottomSurfaceIds());
    this.dependencies.rootBottomPanelSessionCoordinator.restoreSearchBackdropPresentation(
      facts.rootBottomPanelDetent
    );
    this.dependencies.backgroundSessionSyncCoordinator.startCoolingTimer(this.dependencies.runtimeCoolingTickMs);
    this.applyRuntimeRetentionSettings(true);
    this.shell.syncWindowSafeInsets();
    this.shell.scheduleWebSafeInsetSettleSync('page-show');
    this.refreshAppearanceState();
    this.refreshExperimentState();
    this.dependencies.webTopImmersionSessionCoordinator.syncPolicy('page-show');
    this.bindProxyRuntimeRefreshUpdates();
    this.consumePendingProxyRuntimeRefresh();
    this.bindAdBlockRuntimeRefreshUpdates();
    this.consumePendingAdBlockRuntimeRefresh();
    this.dependencies.tabHomeCoordinator.loadSearchEngineSelection();
    this.dependencies.siteControlsRuntimeCoordinator.configureCurrentPageAdBlock();
    this.dependencies.offlineFastFailureCoordinator.startMonitoring();
    this.dependencies.siteControlsRuntimeCoordinator.refreshTrackingProtectionStatus();
    this.bindThemePreferencesUpdates();
    this.dependencies.tabHomeCoordinator.refreshAppearance();
    this.dependencies.customHomepageRuntimeCoordinator.start(false);
    this.bindSmartGripUpdates();
    this.dependencies.hostedRuntimeSurfacePort.updateCurrentActiveConfigFromHost();
    if (facts.showHomePage) {
      this.dependencies.tabHomeCoordinator.refreshWallpaperPresentation();
    }
    this.dependencies.nativeNavigationConsumeCoordinator.consume();
    this.dependencies.privateModeLockCoordinator.handleForegroundResume();
    this.dependencies.tabSwitchCoordinator.resumeActiveTabOnPageForeground();
    this.dependencies.elementInspectionSessionCoordinator.handleShellAppear();
    this.shell.connectSearchInvocationSurface();
    this.dependencies.windowContextCoordinator.consumePendingLaunch('page-show');
    this.consumeRouteLaunchUrl();
    this.consumeReturnHomeRouteRequest();
    sharedSyncExperienceCoordinator.notifyBookmarkSurfaceForeground();
    if (this.shell.readFacts().showHomePage) {
      this.dependencies.homeShortcutStateCoordinator.refresh();
      this.dependencies.recentlyClosedApplicationCoordinator.activateWindow(
        this.dependencies.windowContextCoordinator.resolveCurrentTabSessionProfileId()
      );
      this.dependencies.tabHomeCoordinator.schedulePromptEvaluations();
    }
  }

  refreshExperimentSettings(): void {
    this.refreshExperimentState();
  }

  private applyRuntimeRetentionSettings(syncRuntimeGraph: boolean): void {
    this.dependencies.runtimeMutationPort.updateRetentionSettings(
      sharedPreferencesRepository.getPreferences().retention
    );
    if (syncRuntimeGraph && !this.shell.readFacts().isRestoringTabs) {
      this.dependencies.backgroundSessionSyncCoordinator.sync();
    }
  }

  private resolveLifecyclePreservedCustomBottomSurfaceIds(): BrowserTransientSurfaceId[] {
    if (this.dependencies.elementInspectionSessionCoordinator.shouldPreserveSurfaceForShellLifecycle()) {
      return ['element_inspection'];
    }
    return [];
  }

  private consumeRouteLaunchUrl(): void {
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    const targetUrl = String(params?.url ?? '').trim();
    if (targetUrl.length === 0) {
      return;
    }
    const facts = this.shell.readFacts();
    if (resolveCurrentSiteUrl(facts.currentUrl, facts.addressInput) === targetUrl) {
      return;
    }
    this.dependencies.appUrlOpenCoordinator.openCurrentAppUi(
      targetUrl,
      '正在打开脚本市场',
      this.dependencies.tabScopedEventContextCoordinator.resolveCurrentBoundary()
    );
  }

  private consumeReturnHomeRouteRequest(): void {
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    if (params?.returnHome !== CUSTOM_HOMEPAGE_RETURN_HOME_VALUE ||
      params?.boundarySource !== CUSTOM_HOMEPAGE_RETURN_HOME_SOURCE) {
      return;
    }
    const token = String(params.returnHomeToken ?? '').trim();
    if (token.length <= 0 || token === this.handledReturnHomeRouteToken) {
      return;
    }
    this.handledReturnHomeRouteToken = token;
    this.dependencies.customHomepageRuntimeCoordinator.refresh(true, true);
    void this.dependencies.tabHomeCoordinator.goHome().then((): void => {
      this.dependencies.customHomepageRuntimeCoordinator.refresh(true, true);
    });
  }

  private bindDownloadCallbacks(): void {
    this.dependencies.downloadService.setCallbacks({
      onPendingDownloadPromptChange: (prompt?: PendingDownloadPromptState): void => {
        this.dependencies.downloadConfirmOverlayCoordinator.present(prompt);
      },
      onTaskListChange: (tasks: DownloadV2TaskEntity[]): void => {
        this.dependencies.backgroundSessionSyncCoordinator.handleDownloadActivitySnapshot();
        this.dependencies.userScriptRuntimeCoordinator.handleNativeDownloadTaskSnapshots(tasks);
      },
      resolveCurrentPageUrl: (): string => this.shell.readFacts().currentUrl,
      onInfo: (message: string): void => this.shell.applyDownloadInfo(message),
      onError: (message: string): void => {
        const fault = this.dependencies.faultClassifier.classifyDownloadError(message);
        this.shell.applyDownloadError(fault.userMessage, message);
      }
    });
  }

  private bindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length > 0) {
      return;
    }
    const currentPreferences = sharedPreferencesRepository.getPreferences();
    this.dependencies.proxyAuthRefreshCoordinator.remember(currentPreferences.experiments);
    this.reconcileAlwaysPrivateModePreference(currentPreferences.general.alwaysUsePrivateMode === true);
    this.themePreferencesListenerKey = sharedPreferencesRepository.subscribe((preferences, scope): void => {
      if (scope === 'general') {
        this.reconcileAlwaysPrivateModePreference(preferences.general.alwaysUsePrivateMode === true);
      }
      if (isBrowserThemePresentationScope(scope)) {
        if (scope === 'theme_mode') {
          this.dependencies.tabHomeCoordinator.clearOptimisticThemeModeOverride();
          this.shell.incrementThemeModeActionVersion();
        }
        if (scope === 'appearance') {
          this.refreshAppearanceState();
        }
        this.dependencies.tabHomeCoordinator.refreshAppearance();
        this.shell.syncBottomPanelStatusBarStyle();
        this.dependencies.customHomepageRuntimeCoordinator.syncBridge('theme');
        this.dependencies.hostedRuntimeSurfacePort.updateCurrentActiveConfigFromHost();
        if (scope === 'appearance') {
          this.dependencies.webTopImmersionSessionCoordinator.syncPolicy('appearance');
        }
        return;
      }
      if (scope === 'experiments') {
        this.refreshExperimentState();
        this.consumePendingProxyRuntimeRefresh();
        const facts = this.shell.readFacts();
        this.dependencies.proxyAuthRefreshCoordinator.handleSettingsRefresh({
          settings: sharedPreferencesRepository.getPreferences().experiments,
          activeTab: this.dependencies.tabManager.getActiveTab(facts.tabs, facts.activeTabId),
          showHomePage: facts.showHomePage
        }, this.dependencies.proxyRuntimeRefreshHost);
        return;
      }
      if (scope === 'toolbar_layout') {
        this.shell.incrementToolbarLayoutVersion();
      }
    });
  }

  private reconcileAlwaysPrivateModePreference(enabled: boolean): void {
    const wasEnabled = this.alwaysUsePrivateModeEnabled;
    this.alwaysUsePrivateModeEnabled = enabled;
    if (!wasEnabled || enabled ||
      !this.dependencies.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate()) {
      return;
    }
    const regularBoundary = this.dependencies.privateTabCoordinator.buildRegularTabCreateOptions();
    this.dependencies.tabHomeCoordinator.showHomeSurface(
      '已退出始终保持隐私模式',
      regularBoundary,
      false,
      false
    );
    this.dependencies.privateModeLockCoordinator.synchronizeCurrentBoundary();
  }

  private bindProxyRuntimeRefreshUpdates(): void {
    if (this.proxyRuntimeRefreshListenerKey.length > 0) {
      return;
    }
    this.proxyRuntimeRefreshListenerKey = sharedBrowserProxyRuntimeRefreshCoordinator.subscribe((): void => {
      this.consumePendingProxyRuntimeRefresh();
    });
  }

  private unbindProxyRuntimeRefreshUpdates(): void {
    if (this.proxyRuntimeRefreshListenerKey.length <= 0) {
      return;
    }
    sharedBrowserProxyRuntimeRefreshCoordinator.unsubscribe(this.proxyRuntimeRefreshListenerKey);
    this.proxyRuntimeRefreshListenerKey = '';
  }

  private unbindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length <= 0) {
      return;
    }
    sharedPreferencesRepository.unsubscribe(this.themePreferencesListenerKey);
    this.themePreferencesListenerKey = '';
  }

  private consumePendingProxyRuntimeRefresh(): void {
    if (!sharedBrowserProxyRuntimeRefreshCoordinator.consumePendingRefresh()) {
      return;
    }
    const facts = this.shell.readFacts();
    this.dependencies.proxyAuthRefreshCoordinator.handlePendingRuntimeRefresh({
      settings: sharedPreferencesRepository.getPreferences().experiments,
      activeTab: this.dependencies.tabManager.getActiveTab(facts.tabs, facts.activeTabId),
      showHomePage: facts.showHomePage
    }, this.dependencies.proxyRuntimeRefreshHost);
  }

  private bindAdBlockRuntimeRefreshUpdates(): void {
    if (this.adBlockRuntimeRefreshListenerKey.length > 0) {
      return;
    }
    this.adBlockRuntimeRefreshListenerKey =
      this.dependencies.adBlockCoordinator.subscribeRuntimeRefresh((): void => {
        this.consumePendingAdBlockRuntimeRefresh();
      });
  }

  private unbindAdBlockRuntimeRefreshUpdates(): void {
    if (this.adBlockRuntimeRefreshListenerKey.length <= 0) {
      return;
    }
    this.dependencies.adBlockCoordinator.unsubscribeRuntimeRefresh(this.adBlockRuntimeRefreshListenerKey);
    this.adBlockRuntimeRefreshListenerKey = '';
  }

  private consumePendingAdBlockRuntimeRefresh(): void {
    if (!this.dependencies.adBlockCoordinator.consumePendingRuntimeRefresh()) {
      return;
    }
    this.dependencies.hostedRuntimeSurfacePort.releaseAll('adblock_settings_changed');
    const facts = this.shell.readFacts();
    const activeTab = this.dependencies.tabManager.getActiveTab(facts.tabs, facts.activeTabId);
    if (activeTab === undefined || activeTab.isHome || facts.showHomePage) {
      return;
    }
    const runtime = this.dependencies.runtimeLifecyclePort.replaceControllerForRuntimeRefresh(activeTab.id);
    if (runtime !== undefined) {
      this.dependencies.runtimeRefreshStateSink.applyReplacementRuntimeState(runtime);
      this.dependencies.hostedRuntimeSurfacePort.syncActiveFromHost(activeTab, runtime);
    }
  }

  private refreshAppearanceState(): void {
    const appearance = sharedPreferencesRepository.getPreferences().appearance;
    this.dependencies.webScrollInteractionCoordinator.applyBottomToolbarScrollBehavior(
      appearance.bottomToolbarScrollBehavior,
      this.shell.readFacts().activeTabId
    );
    this.shell.applyAppearanceState({
      globalImmersionEnabled: appearance.globalImmersionEnabled,
      alwaysTopImmersionEnabled: appearance.alwaysTopImmersionEnabled
    });
  }

  private refreshExperimentState(): void {
    const settings = sharedPreferencesRepository.getPreferences().experiments;
    this.shell.applyExperimentSettings(settings);
    this.dependencies.mediaDiscoveryRuntimeContextFactory.invalidate();
    this.dependencies.smartGripCoordinator.applyExperimentSettings(settings);
    this.dependencies.pullRefreshCoordinator.syncEnabled();
    this.dependencies.hostedRuntimeSurfacePort.updateCurrentActiveConfigFromHost();
  }

  private bindSmartGripUpdates(): void {
    this.dependencies.smartGripCoordinator.bind((state: BrowserSmartGripState): void => {
      this.shell.applySmartGripState(state);
      this.dependencies.customHomepageRuntimeCoordinator.updateSmartGripState(state);
    });
    this.dependencies.smartGripCoordinator.applyExperimentSettings(
      sharedPreferencesRepository.getPreferences().experiments
    );
  }

  private unbindSmartGripUpdates(): void {
    this.dependencies.smartGripCoordinator.unbind();
    this.shell.applySmartGripState(this.dependencies.smartGripCoordinator.createState());
  }

  private restoreCachedWebLayerGeometry(): void {
    void this.dependencies.webLayerGeometryStore.readSnapshot()
      .then((snapshot?: BrowserWebLayerGeometrySnapshot): void => {
        this.shell.applyRestoredWebLayerGeometry(snapshot);
      })
      .catch((_error: Error): void => {
        this.shell.applyRestoredWebLayerGeometry(undefined);
      });
  }
}
