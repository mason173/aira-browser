import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want,
  wantConstant
} from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  initializeBrowserAppLaunchReadiness,
  initializeBrowserAppRuntime,
  refreshBrowserThemeForSystemConfigurationChange,
  restoreArkWebAppProxyAfterForeground,
  sharedAppCrashDiagnosticsService,
  sharedActivityForegroundSessionCoordinator,
  sharedDownloadRuntimeService,
  sharedBrowserRuntimeMaintenanceCoordinator,
  sharedBrowserFingerprintPrivacyPolicyService,
  sharedBrowserUserAgentHostPolicyService,
  sharedBrowserUserAgentSettingsRepository,
  sharedBrowserTabletInterfaceModeRepository,
  sharedCustomHomepageRepository,
  sharedPreferencesRepository,
  sharedSitePolicyService,
  sharedSyncExperienceCoordinator,
  sharedStartupWelcomeIntroRepository,
  sharedTabSessionRepository,
  sharedUserScriptInstallSessionCoordinator
} from '../bootstrap/BrowserAppRuntime';
import { AppRuntimeContext } from '../runtime/AppRuntimeContext';
import { BROWSER_SHELL_ROUTE, STARTUP_WELCOME_INTRO_ROUTE } from '../router/AppRoutes';
import { BrowserTabSessionRuntime } from '../runtime/BrowserTabSessionRuntime';
import {
  BrowserWindowAvoidAreaCoordinator,
} from '../../core/browser/BrowserWindowAvoidAreaCoordinator';
import { BrowserSystemFontScaleCoordinator } from '../../core/browser/BrowserSystemFontScaleCoordinator';
import {
  BrowserWindowDisplayViewportCoordinator
} from '../../core/browser/BrowserWindowDisplayViewportCoordinator';
import { BrowserShellAdapterCatalog } from '../../core/browser/BrowserShellAdapterCatalog';
import { BrowserWindowPresentationProfileInputService } from '../../services/browser/BrowserWindowPresentationProfileInputService';
import {
  sharedBrowserLargeScreenWindowChromeService
} from '../../services/browser/BrowserLargeScreenWindowChromeService';
import { sharedWebAppSessionCoordinator } from '../../core/webapps/WebAppSessionCoordinator';
import {
  BROWSER_SEARCH_DESKTOP_CARD_SOURCE,
  BrowserLaunchPayload,
  BrowserWindowRuntime,
  buildBrowserLaunchPayload,
  resolveBrowserLaunchPayloadFromWant,
  resolveBrowserLaunchWindowId
} from '../runtime/BrowserWindowRuntime';
import { BrowserSearchInvocationRuntime } from '../runtime/BrowserSearchInvocationRuntime';
import { WebBackForwardCacheCoordinator } from '../../core/web/WebBackForwardCacheCoordinator';
import { DesktopWebEntryMissionIdentityService } from '../../core/webapps/DesktopWebEntryMissionIdentityService';
import { BrowserPrivateModeForegroundSignal } from '../../core/privacy/BrowserPrivateModeForegroundSignal';
import { BrowserTabPreviewLifecycleSignal } from '../../core/browser/BrowserTabPreviewLifecycleSignal';
import {
  BrowserSystemMemoryPressureSignal
} from '../../core/browser/BrowserSystemMemoryPressureSignal';
import {
  DEFAULT_BROWSER_LARGE_SCREEN_WINDOW_FACTS_POLICY,
  BrowserLargeScreenWindowFactsInput
} from '../../core/browser/BrowserLargeScreenWindowFactsViewModel';
import { BrowserShellPresentationRefreshSignal } from '../../core/browser/BrowserShellPresentationRefreshSignal';
import { BrowserSystemMemoryPressureLevel } from '../../core/browser/BrowserTabBackgroundTypes';
import { SiteDataControlService } from '../../services/web/SiteDataControlService';
import { BROWSER_STATUS_BAR_DARK_CONTENT_COLOR } from '../../services/browser/BrowserStatusBarStyleService';
import { normalizeAiraSearchCardWant } from '../../features/desktopcard/AiraSearchCardLaunchAdapter';
import { AiraIconFontRuntime } from '../../core/resources/AiraIconFontRuntime';
import {
  HuaweiSpaceBookmarkUpgradePromptPresenter
} from '../components/sync/HuaweiSpaceBookmarkUpgradePromptPresenter';
import { AppShortcutNavigationCoordinator } from '../router/AppShortcutNavigationCoordinator';
import {
  CustomHomepageExternalImportLaunchHost,
  CustomHomepageSettingsCoordinator
} from '../../core/customhome/CustomHomepageSettingsCoordinator';
import {
  UserScriptExternalImportCoordinator,
  UserScriptExternalImportLaunchHost
} from '../../core/userscripts/UserScriptExternalImportCoordinator';
import {
  BrowserExternalShareIngressCoordinator,
  BrowserExternalShareIngressHost,
  BrowserExternalShareIngressRequest
} from '../../core/browser/BrowserExternalShareIngressCoordinator';
import {
  BrowserArkWebTimerTransition,
  sharedBrowserArkWebProcessLifecycleCoordinator
} from '../../core/browser/BrowserArkWebProcessLifecycleCoordinator';
import {
  BROWSER_CONTINUATION_WANT_KEY,
  BrowserContinuationEligibilityConnection,
  BrowserContinuationPayload,
  sharedBrowserContinuationCoordinator
} from '../../core/browser/BrowserContinuationCoordinator';

const DOMAIN = 0x0000;
const TAG = 'AiraBrowser';
const LIGHT_SYSTEM_NAVIGATION_BAR_COLOR: string = '#FFF0F2F4';
const DARK_SYSTEM_NAVIGATION_BAR_COLOR: string = '#FF0B0D10';

export default class EntryAbility extends UIAbility {
  private pageStorage: LocalStorage = new LocalStorage();
  private currentWindowId: string = 'window-main';
  private browserWindowSessionId: string = '';
  private windowStageLifecycleGeneration: number = 0;
  private pendingMissionLaunchPayload?: BrowserLaunchPayload;
  private pendingMissionWindowId: string = '';
  private runtimeInitializationPromise: Promise<void> = Promise.resolve();
  private launchReadinessPromise: Promise<void> = Promise.resolve();
  private initialExternalShareIngressReadiness: Promise<void> = Promise.resolve();
  private runtimeInitializationStarted: boolean = false;
  private permissionSessionAcquired: boolean = false;
  private contentReady: boolean = false;
  private appInForeground: boolean = false;
  private contentReadyWaiters: Array<() => void> = [];
  private continuationEligibilityConnection?: BrowserContinuationEligibilityConnection;
  private continuationMissionState?: AbilityConstant.ContinueState;
  private desiredContinuationMissionState: AbilityConstant.ContinueState = AbilityConstant.ContinueState.INACTIVE;
  private continuationMissionStateQueue: Promise<void> = Promise.resolve();
  private browserWindowAvoidAreaCoordinator: BrowserWindowAvoidAreaCoordinator =
    new BrowserWindowAvoidAreaCoordinator();
  private webBackForwardCacheCoordinator: WebBackForwardCacheCoordinator =
    new WebBackForwardCacheCoordinator();
  private browserSystemFontScaleCoordinator: BrowserSystemFontScaleCoordinator =
    new BrowserSystemFontScaleCoordinator();
  private browserWindowDisplayViewportCoordinator: BrowserWindowDisplayViewportCoordinator =
    new BrowserWindowDisplayViewportCoordinator();
  private browserShellAdapterCatalog: BrowserShellAdapterCatalog = new BrowserShellAdapterCatalog();
  private browserWindowPresentationProfileInputService: BrowserWindowPresentationProfileInputService =
    new BrowserWindowPresentationProfileInputService();
  private browserWindowPresentationProfileRevision: number = 0;
  private browserLargeScreenWindowFactsRequestRevision: number = 0;
  private browserPointerAvailable: boolean = false;
  private browserPresentationMainWindow?: window.Window;
  private initialBrowserPresentationFactsReady: Promise<void> = Promise.resolve();
  private tabletInterfaceModeListenerKey: string = '';
  private desktopWebEntryMissionIdentityService: DesktopWebEntryMissionIdentityService =
    new DesktopWebEntryMissionIdentityService();
  private siteDataControlService: SiteDataControlService =
    new SiteDataControlService(sharedPreferencesRepository);
  private huaweiSpaceBookmarkUpgradePromptPresenter: HuaweiSpaceBookmarkUpgradePromptPresenter =
    new HuaweiSpaceBookmarkUpgradePromptPresenter(sharedSyncExperienceCoordinator);
  private appShortcutNavigationCoordinator: AppShortcutNavigationCoordinator =
    new AppShortcutNavigationCoordinator();
  private customHomepageSettingsCoordinator: CustomHomepageSettingsCoordinator =
    new CustomHomepageSettingsCoordinator(sharedCustomHomepageRepository);
  private userScriptExternalImportCoordinator: UserScriptExternalImportCoordinator =
    new UserScriptExternalImportCoordinator(sharedUserScriptInstallSessionCoordinator);
  private browserExternalShareIngressCoordinator: BrowserExternalShareIngressCoordinator =
    new BrowserExternalShareIngressCoordinator();
  private customHomepageExternalImportLaunchHost: CustomHomepageExternalImportLaunchHost = {
    waitForContentReady: (): Promise<void> => this.waitForContentReady(),
    openSettings: async (source: string): Promise<boolean> => {
      const navigationResult = await this.appShortcutNavigationCoordinator.openShortcut(
        'custom_homepage_settings',
        {
          dataScope: 'profile_persistent',
          privacyMode: 'regular',
          boundarySource: `external_homepage_import:${source}`
        }
      );
      if (!navigationResult.handled) {
        hilog.warn(
          DOMAIN,
          TAG,
          'Failed to route external homepage import: %{public}s',
          navigationResult.errorMessage
        );
      }
      return navigationResult.handled;
    }
  };
  private userScriptExternalImportLaunchHost: UserScriptExternalImportLaunchHost = {
    waitForContentReady: (): Promise<void> => this.waitForContentReady(),
    openUserScripts: async (source: string): Promise<boolean> => {
      const navigationResult = await this.appShortcutNavigationCoordinator.openShortcut(
        'user_scripts',
        {
          dataScope: 'profile_persistent',
          privacyMode: 'regular',
          boundarySource: `external_user_script_import:${source}`
        }
      );
      if (!navigationResult.handled) {
        hilog.warn(
          DOMAIN,
          TAG,
          'Failed to route external user script import: %{public}s',
          navigationResult.errorMessage
        );
      }
      return navigationResult.handled;
    }
  };
  private browserExternalShareIngressHost: BrowserExternalShareIngressHost = {
    openBrowserUrl: (url: string, source: string): void => this.stageSharedBrowserUrl(url, source),
    forwardSharedFile: (want: Want, source: string): void => {
      this.handleCustomHomepageExternalImportWant(want, source);
    }
  };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppRuntimeContext.setUIAbilityContext(this.context);
    sharedSitePolicyService.acquirePermissionSession();
    this.permissionSessionAcquired = true;
    sharedAppCrashDiagnosticsService.initialize(this.context, launchParam);
    this.browserSystemFontScaleCoordinator.syncInitial(this.context.config);
    this.bindTabletInterfaceModeUpdates();
    try {
      const bfcacheResult = this.webBackForwardCacheCoordinator.enableGlobalFeature();
      if (!bfcacheResult.enabled) {
        hilog.warn(DOMAIN, TAG, 'ArkWeb BFCache prepare failed before engine init: %{public}s', bfcacheResult.message);
      }
      webview.WebviewController.initializeWebEngine();
      sharedSitePolicyService.clearArkWebGeolocationPermissions(false);
      sharedSitePolicyService.clearArkWebGeolocationPermissions(true);
      const cookiePolicy = this.siteDataControlService.applyBrowserCompatibleCookiePolicy();
      hilog.info(
        DOMAIN,
        TAG,
        'ArkWeb default cookie policy applied before preferences: cookie=%{public}s thirdParty=%{public}s',
        String(cookiePolicy.acceptCookies),
        String(cookiePolicy.acceptThirdPartyCookies)
      );
      webview.WebviewController.enableWholeWebPageDrawing();
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to set color mode: %{public}s', JSON.stringify(error));
    }

    this.launchReadinessPromise = initializeBrowserAppLaunchReadiness(this.context)
      .then(() => {
        const trackingProtection = sharedBrowserFingerprintPrivacyPolicyService.applyRuntime(
          sharedPreferencesRepository.getPreferences()
        );
        hilog.info(
          DOMAIN,
          TAG,
          'ArkWeb tracking protection applied before first Web: mode=%{public}s runtimeApplied=%{public}s',
          trackingProtection.mode,
          String(trackingProtection.runtimeApplied)
        );
          if (this.browserPresentationMainWindow !== undefined) {
            this.reconcileBrowserWindowPresentationProfile(
              this.browserPresentationMainWindow,
              'launch-readiness',
              true
            );
          }
      })
      .catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Failed to prepare browser launch readiness: %{public}s', JSON.stringify(error));
      });

    const continuationLaunchHandled = this.stageIncomingContinuation(want, launchParam, 'onCreate');
    const normalizedWant = normalizeAiraSearchCardWant(want);
    if (!continuationLaunchHandled && !this.handleUserScriptExternalImportWant(normalizedWant, 'onCreate') &&
      !this.handleBrowserExternalShareWant(normalizedWant, 'onCreate') &&
      !this.handleCustomHomepageExternalImportWant(normalizedWant, 'onCreate')) {
      const launchPayload = resolveBrowserLaunchPayloadFromWant(normalizedWant, 'onCreate');
      if (launchPayload !== undefined) {
        const targetWindowId = resolveBrowserLaunchWindowId(launchPayload);
        BrowserWindowRuntime.stageLaunchPayloadAt(launchPayload, targetWindowId);
        BrowserWindowRuntime.applyWindowIdToStorage(this.pageStorage, targetWindowId);
        this.triggerSearchInvocationIfNeeded(launchPayload, targetWindowId);
        this.desktopWebEntryMissionIdentityService.apply(this.context, launchPayload, targetWindowId, 'onCreate');
        this.stagePendingMissionIdentity(launchPayload, targetWindowId);
      }
    }

    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    this.restoreWindowStageForContinuation(launchParam);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.prepareWindowStage(windowStage, 'create');
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    this.prepareWindowStage(windowStage, 'restore');
  }

  private prepareWindowStage(windowStage: window.WindowStage, source: 'create' | 'restore'): void {
    const windowStageGeneration = ++this.windowStageLifecycleGeneration;
    hilog.info(DOMAIN, TAG, 'Ability window stage %{public}s', source);
    sharedAppCrashDiagnosticsService.recordLifecycle(
      this.context,
      source === 'restore' ? 'window_stage_restore' : 'window_stage_create'
    );
    this.configureMainWindow(windowStage)
      .then((mainWindow: window.Window) => {
        if (windowStageGeneration !== this.windowStageLifecycleGeneration) {
          return;
        }
        this.browserPresentationMainWindow = mainWindow;
        this.browserWindowDisplayViewportCoordinator.bind(mainWindow, (boundWindow: window.Window): void => {
          if (windowStageGeneration !== this.windowStageLifecycleGeneration) {
            return;
          }
          this.reconcileBrowserWindowPresentationProfile(boundWindow, 'window-fact-change', false);
          const presentationFactsReady = this.reconcileBrowserLargeScreenWindowFacts(
            boundWindow,
            windowStageGeneration,
            'window-fact-change'
          );
          if (!this.contentReady) {
            this.initialBrowserPresentationFactsReady = presentationFactsReady;
          }
        });
        this.browserWindowAvoidAreaCoordinator.syncStorage(mainWindow, this.pageStorage);
        this.browserWindowAvoidAreaCoordinator.bind(mainWindow, this.pageStorage);
        const windowId = BrowserWindowRuntime.resolveWindowIdFromStorage(this.pageStorage);
        this.currentWindowId = windowId;
        this.browserWindowSessionId = windowId;
        sharedBrowserLargeScreenWindowChromeService.registerWindow(windowId, mainWindow, (): void => {
          this.browserWindowDisplayViewportCoordinator.scheduleSync();
        });
        this.browserWindowPresentationProfileRevision = 0;
        BrowserWindowRuntime.acquireSession({
          windowId: this.browserWindowSessionId,
          articleReadingPreferencesRepository: sharedPreferencesRepository
        });
        BrowserWindowRuntime.bindSessionToStorage(this.pageStorage, this.browserWindowSessionId);
        BrowserWindowRuntime.reconcileSessionLifetime(this.browserWindowSessionId, true);
        BrowserWindowRuntime.connectShellPresentation(
          this.pageStorage,
          this.browserShellAdapterCatalog.snapshot()
        );
        this.reconcileBrowserWindowPresentationProfile(mainWindow, 'window-stage-create', true);
        this.initialBrowserPresentationFactsReady = this.reconcileBrowserLargeScreenWindowFacts(
          mainWindow,
          windowStageGeneration,
          `window-stage-${source}`
        );
        BrowserWindowRuntime.registerWindow(windowId, this.pageStorage, this.context);
        BrowserWindowRuntime.markWindowForeground(windowId);
        this.connectContinuationEligibility(windowId);
        this.applyPendingMissionIdentityAfterWindowStageCreate(windowId);
        return this.waitForInitialRouteReadiness()
          .then((initialRoute: string) => {
            if (windowStageGeneration !== this.windowStageLifecycleGeneration) {
              return;
            }
            AiraIconFontRuntime.registerBeforeContentLoad();
            windowStage.loadContent(initialRoute, this.pageStorage, (err) => {
              if (windowStageGeneration !== this.windowStageLifecycleGeneration) {
                return;
              }
              if (err.code) {
                hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
                return;
              }
              if (initialRoute === BROWSER_SHELL_ROUTE) {
                this.applyPendingMissionIdentityAfterContentLoad(windowId);
                sharedSyncExperienceCoordinator.notifyAppContentReady();
              }
              this.markContentReady();
              void this.huaweiSpaceBookmarkUpgradePromptPresenter.presentIfNeeded()
                .catch((error: Error): void => {
                  hilog.warn(
                    DOMAIN,
                    TAG,
                    'Huawei Space Bookmark upgrade prompt skipped: %{public}s',
                    JSON.stringify(error)
                  );
                });
              this.startBrowserRuntimeInitialization('initial-content-loaded');
              sharedAppCrashDiagnosticsService.recordLifecycle(this.context, 'initial_content_loaded', initialRoute);
              hilog.info(DOMAIN, TAG, 'Initial content loaded: %{public}s', initialRoute);
            });
          });
      })
      .catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to prepare window stage: %{public}s', JSON.stringify(error));
      });
  }

  onWindowStageDestroy(): void {
    this.windowStageLifecycleGeneration += 1;
    this.browserLargeScreenWindowFactsRequestRevision += 1;
    this.browserWindowDisplayViewportCoordinator.unbind();
    this.browserPresentationMainWindow = undefined;
    this.browserPointerAvailable = false;
    this.initialBrowserPresentationFactsReady = Promise.resolve();
    this.browserWindowPresentationProfileRevision = 0;
    this.currentWindowId = BrowserWindowRuntime.resolveWindowIdFromStorage(this.pageStorage);
    this.disconnectContinuationEligibility();
    sharedBrowserContinuationCoordinator.clearWindow(this.currentWindowId);
    sharedAppCrashDiagnosticsService.recordLifecycle(this.context, 'window_stage_destroy', this.currentWindowId);
    this.flushLastKnownTabSession('window-stage-destroy');
    sharedDownloadRuntimeService.clearPrivateDownloadSessionForWindow(this.currentWindowId);
    BrowserWindowRuntime.markWindowBackground(this.currentWindowId);
    BrowserWindowRuntime.reconcileSessionLifetime(this.browserWindowSessionId, false);
    BrowserSearchInvocationRuntime.notifyBackground(this.currentWindowId);
    sharedBrowserLargeScreenWindowChromeService.unregisterWindow(this.currentWindowId);
    BrowserWindowRuntime.unregisterWindow(this.currentWindowId);
    BrowserWindowRuntime.releaseSession(this.browserWindowSessionId);
    BrowserWindowRuntime.clearSessionFromStorage(this.pageStorage);
    this.browserWindowSessionId = '';
    BrowserSearchInvocationRuntime.clearWindow(this.currentWindowId);
    if (!BrowserWindowRuntime.hasForegroundWindows()) {
      this.pauseArkWebTimersForProcessBackground();
      sharedSyncExperienceCoordinator.notifyAppBackground();
    }
    sharedWebAppSessionCoordinator.clear(this.currentWindowId);
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy for %{public}s', this.currentWindowId);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    sharedAppCrashDiagnosticsService.recordLifecycle(this.context, 'ability_on_new_want');
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.stageIncomingContinuation(want, launchParam, 'onNewWant');
      this.restoreWindowStageForContinuation(launchParam);
      return;
    }
    const normalizedWant = normalizeAiraSearchCardWant(want);
    if (this.handleUserScriptExternalImportWant(normalizedWant, 'onNewWant') ||
      this.handleBrowserExternalShareWant(normalizedWant, 'onNewWant') ||
      this.handleCustomHomepageExternalImportWant(normalizedWant, 'onNewWant')) {
      return;
    }
    const launchPayload = resolveBrowserLaunchPayloadFromWant(normalizedWant, 'onNewWant');
    let targetWindowId: string;
    if (launchPayload !== undefined &&
      (launchPayload.shortcut !== undefined || launchPayload.tabMoveWindowInstanceId.length > 0)) {
      targetWindowId = resolveBrowserLaunchWindowId(launchPayload);
      BrowserWindowRuntime.stageLaunchPayloadAt(launchPayload, targetWindowId);
      this.desktopWebEntryMissionIdentityService.apply(this.context, launchPayload, targetWindowId, 'onNewWant');
      this.stagePendingMissionIdentity(launchPayload, targetWindowId);
    } else if (launchPayload !== undefined) {
      // External deep link without shortcut metadata: open in the normal browser.
      targetWindowId = 'window-main';
      BrowserWindowRuntime.stageLaunchPayloadAt(launchPayload, targetWindowId);
    } else {
      // Plain launcher click while app is alive: always return to the normal
      // browser context so a previously-active desktop web entry session
      // does not bleed into a regular Aira launch.
      targetWindowId = 'window-main';
    }
    if (launchPayload !== undefined) {
      this.triggerSearchInvocationIfNeeded(launchPayload, targetWindowId);
    }
    BrowserWindowRuntime.applyWindowIdToStorage(this.pageStorage, targetWindowId);
    const previousWindowId = this.currentWindowId;
    this.currentWindowId = targetWindowId;
    if (this.browserPresentationMainWindow !== undefined) {
      sharedBrowserLargeScreenWindowChromeService.rebindWindow(
        previousWindowId,
        targetWindowId,
        this.browserPresentationMainWindow
      );
    }
    if (launchPayload !== undefined) {
      BrowserWindowRuntime.consumePendingLaunchThroughWindowOwner(targetWindowId, 'ability-on-new-want');
    }
  }

  onForeground(): void {
    this.appInForeground = true;
    const windowId = BrowserWindowRuntime.resolveWindowIdFromStorage(this.pageStorage);
    BrowserWindowRuntime.markWindowForeground(windowId);
    const arkWebTimerTransition = sharedBrowserArkWebProcessLifecycleCoordinator.resumeForProcessForeground();
    this.recordArkWebTimerTransition(arkWebTimerTransition);
    BrowserWindowRuntime.reconcileSessionLifetime(this.browserWindowSessionId, true);
    BrowserSearchInvocationRuntime.notifyForeground(windowId);
    sharedAppCrashDiagnosticsService.notifyForeground(this.context);
    BrowserPrivateModeForegroundSignal.markForeground();
    sharedActivityForegroundSessionCoordinator.markForeground();
    sharedSyncExperienceCoordinator.notifyAppForeground();
    sharedBrowserRuntimeMaintenanceCoordinator.notifyForeground();
    refreshBrowserThemeForSystemConfigurationChange();
    restoreArkWebAppProxyAfterForeground();
    this.browserWindowDisplayViewportCoordinator.scheduleSync();
    this.refreshContinuationMissionState(windowId);
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onConfigurationUpdate(config: Configuration): void {
    const fontScaleChanged = this.browserSystemFontScaleCoordinator.handleConfigurationUpdate(config);
    this.browserWindowDisplayViewportCoordinator.scheduleSync();
    refreshBrowserThemeForSystemConfigurationChange(config.colorMode);
    hilog.info(DOMAIN, TAG, 'Ability onConfigurationUpdate fontScaleChanged=%{public}s', String(fontScaleChanged));
  }

  onBackground(): void {
    this.appInForeground = false;
    this.currentWindowId = BrowserWindowRuntime.resolveWindowIdFromStorage(this.pageStorage);
    this.applyContinuationMissionState(false);
    BrowserWindowRuntime.markWindowBackground(this.currentWindowId);
    BrowserWindowRuntime.reconcileSessionLifetime(this.browserWindowSessionId, false);
    BrowserSearchInvocationRuntime.notifyBackground(this.currentWindowId);
    sharedAppCrashDiagnosticsService.recordLifecycle(this.context, 'ability_background', this.currentWindowId);
    BrowserPrivateModeForegroundSignal.markBackground();
    sharedActivityForegroundSessionCoordinator.markBackground();
    if (!BrowserWindowRuntime.hasForegroundWindows()) {
      this.pauseArkWebTimersForProcessBackground();
      sharedSyncExperienceCoordinator.notifyAppBackground();
    }
    sharedBrowserRuntimeMaintenanceCoordinator.notifyBackground();
    BrowserTabPreviewLifecycleSignal.requestCapture();
    this.flushLastKnownTabSession('ability-background');
    this.flushPreferences('ability-background');
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }

  private pauseArkWebTimersForProcessBackground(): void {
    const transition = sharedBrowserArkWebProcessLifecycleCoordinator.pauseForProcessBackground();
    this.recordArkWebTimerTransition(transition);
  }

  private recordArkWebTimerTransition(transition: BrowserArkWebTimerTransition): void {
    if (transition === 'unchanged') {
      return;
    }
    const state = transition === 'paused' || transition === 'pause_failed' ? 'background' : 'foreground';
    const result = transition === 'paused' || transition === 'resumed' ? 'ok' : 'failed';
    sharedAppCrashDiagnosticsService.recordDiagnostic(
      this.context,
      'arkweb',
      'process_lifecycle',
      'javascript_timers',
      state,
      result
    );
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    const pressureLevel = this.resolveSystemMemoryPressureLevel(level);
    const revision = BrowserSystemMemoryPressureSignal.record(
      pressureLevel,
      'ability_on_memory_level',
      Number(level)
    );
    sharedAppCrashDiagnosticsService.recordLifecycle(
      this.context,
      'ability_memory_level',
      `pressure=${pressureLevel} raw=${Number(level)} revision=${revision}`
    );
    hilog.warn(
      DOMAIN,
      TAG,
      'Ability onMemoryLevel pressure=%{public}s raw=%{public}d revision=%{public}d',
      pressureLevel,
      Number(level),
      revision
    );
  }

  onDestroy(): void {
    this.disconnectContinuationEligibility();
    this.resolveContentReadyWaiters();
    this.browserExternalShareIngressCoordinator.destroy();
    this.userScriptExternalImportCoordinator.destroyExternalImportIngress();
    this.customHomepageSettingsCoordinator.destroyExternalImportIngress();
    this.unbindTabletInterfaceModeUpdates();
    sharedAppCrashDiagnosticsService.recordLifecycle(this.context, 'ability_destroy');
    BrowserTabPreviewLifecycleSignal.requestCapture();
    this.flushPreferences('ability-destroy');
    if (this.permissionSessionAcquired) {
      sharedSitePolicyService.releasePermissionSession();
      this.permissionSessionAcquired = false;
    }
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    const windowId = BrowserWindowRuntime.resolveWindowIdFromStorage(this.pageStorage);
    const payload = sharedBrowserContinuationCoordinator.buildOutgoingPayload(windowId);
    if (payload === undefined) {
      return AbilityConstant.OnContinueResult.REJECT;
    }
    wantParam[BROWSER_CONTINUATION_WANT_KEY] = sharedBrowserContinuationCoordinator.serializePayload(payload);
    wantParam[wantConstant.Params.SUPPORT_CONTINUE_PAGE_STACK_KEY] = false;
    wantParam[wantConstant.Params.SUPPORT_CONTINUE_SOURCE_EXIT_KEY] = false;
    return AbilityConstant.OnContinueResult.AGREE;
  }

  private stageIncomingContinuation(
    want: Want,
    launchParam: AbilityConstant.LaunchParam,
    source: string
  ): boolean {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return false;
    }
    const parameters = want.parameters as Record<string, Object> | undefined;
    const continuation: BrowserContinuationPayload | undefined =
      sharedBrowserContinuationCoordinator.parseIncomingPayload(parameters);
    if (continuation === undefined) {
      hilog.warn(DOMAIN, TAG, 'Continuation payload rejected at %{public}s', source);
      return false;
    }
    const targetWindowId = 'window-main';
    const launchPayload = buildBrowserLaunchPayload({
      uri: continuation.url,
      source: 'app_continuation',
      profileId: 'profile-main',
      privacyMode: 'regular',
      dataScope: 'profile_persistent',
      continuation: continuation
    });
    BrowserWindowRuntime.stageLaunchPayloadAt(launchPayload, targetWindowId);
    BrowserWindowRuntime.applyWindowIdToStorage(this.pageStorage, targetWindowId);
    this.currentWindowId = targetWindowId;
    return true;
  }

  private restoreWindowStageForContinuation(launchParam: AbilityConstant.LaunchParam): void {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return;
    }
    try {
      this.context.restoreWindowStage(this.pageStorage);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to restore continuation WindowStage: %{public}s', JSON.stringify(error));
    }
  }

  private connectContinuationEligibility(windowId: string): void {
    this.disconnectContinuationEligibility();
    this.continuationEligibilityConnection = sharedBrowserContinuationCoordinator.connectEligibility(
      windowId,
      (eligible: boolean): void => this.applyContinuationMissionState(eligible && this.appInForeground)
    );
  }

  private disconnectContinuationEligibility(): void {
    this.continuationEligibilityConnection?.disconnect();
    this.continuationEligibilityConnection = undefined;
  }

  private refreshContinuationMissionState(windowId: string): void {
    this.applyContinuationMissionState(
      this.appInForeground && sharedBrowserContinuationCoordinator.isWindowEligible(windowId)
    );
  }

  private applyContinuationMissionState(eligible: boolean): void {
    this.desiredContinuationMissionState = eligible
      ? AbilityConstant.ContinueState.ACTIVE
      : AbilityConstant.ContinueState.INACTIVE;
    this.continuationMissionStateQueue = this.continuationMissionStateQueue
      .then(async (): Promise<void> => {
        const targetState = this.desiredContinuationMissionState;
        if (this.continuationMissionState === targetState) {
          return;
        }
        await this.context.setMissionContinueState(targetState);
        this.continuationMissionState = targetState;
      })
      .catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'Failed to update continuation eligibility: %{public}s', JSON.stringify(error));
      });
  }

  private handleCustomHomepageExternalImportWant(want: Want, source: string): boolean {
    return this.customHomepageSettingsCoordinator.handleExternalImportWant(
      want,
      source,
      this.customHomepageExternalImportLaunchHost
    );
  }

  private handleUserScriptExternalImportWant(want: Want, source: string): boolean {
    return this.userScriptExternalImportCoordinator.handleExternalImportWant(
      want,
      source,
      this.userScriptExternalImportLaunchHost
    );
  }

  private handleBrowserExternalShareWant(want: Want, source: string): boolean {
    const request: BrowserExternalShareIngressRequest = this.browserExternalShareIngressCoordinator.handle(
      want,
      source,
      this.browserExternalShareIngressHost
    );
    if (source === 'onCreate' && request.handled) {
      this.initialExternalShareIngressReadiness = request.completion;
    }
    return request.handled;
  }

  private stageSharedBrowserUrl(url: string, source: string): void {
    const targetWindowId = 'window-main';
    const launchPayload = buildBrowserLaunchPayload({
      uri: url,
      action: 'ohos.want.action.sendData',
      type: 'general.hyperlink',
      source: `system_share:${source}`
    });
    BrowserWindowRuntime.stageLaunchPayloadAt(launchPayload, targetWindowId);
    BrowserWindowRuntime.applyWindowIdToStorage(this.pageStorage, targetWindowId);
    this.currentWindowId = targetWindowId;
    BrowserWindowRuntime.consumePendingLaunchThroughWindowOwner(targetWindowId, `system-share:${source}`);
  }

  private waitForContentReady(): Promise<void> {
    if (this.contentReady) {
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void): void => {
      this.contentReadyWaiters.push(resolve);
    });
  }

  private markContentReady(): void {
    if (this.contentReady) {
      return;
    }
    this.contentReady = true;
    this.resolveContentReadyWaiters();
  }

  private resolveContentReadyWaiters(): void {
    const waiters = this.contentReadyWaiters.slice();
    this.contentReadyWaiters = [];
    waiters.forEach((resolve: () => void): void => {
      resolve();
    });
  }

  private triggerSearchInvocationIfNeeded(payload: BrowserLaunchPayload, windowId: string): void {
    if (payload.appShortcut !== 'search') {
      return;
    }
    const triggers = BrowserSearchInvocationRuntime.triggers(windowId);
    if (payload.source === BROWSER_SEARCH_DESKTOP_CARD_SOURCE) {
      triggers.desktopCard.open();
      return;
    }
    triggers.appShortcut.open();
  }

  private resolveSystemMemoryPressureLevel(level: AbilityConstant.MemoryLevel): BrowserSystemMemoryPressureLevel {
    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) {
      return 'critical';
    }
    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) {
      return 'low';
    }
    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE) {
      return 'moderate';
    }
    return 'normal';
  }

  private flushLastKnownTabSession(source: string): void {
    const snapshot = BrowserTabSessionRuntime.getSnapshot(this.currentWindowId);
    if (snapshot === undefined) {
      hilog.info(DOMAIN, TAG, 'Skip tab session flush on %{public}s: no snapshot.', source);
      return;
    }
    sharedTabSessionRepository.replaceTabs(snapshot.records, snapshot.windowId, snapshot.profileId)
      .then(() => {
        hilog.info(
          DOMAIN,
          TAG,
          'Flushed %{public}d tab session records on %{public}s for %{public}s.',
          snapshot.records.length,
          source,
          snapshot.windowId
        );
      })
      .catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to flush tab session on %{public}s: %{public}s', source, JSON.stringify(error));
      });
  }

  private flushPreferences(source: string): void {
    sharedPreferencesRepository.flush()
      .catch((error: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to flush preferences on %{public}s: %{public}s', source, JSON.stringify(error));
      });
  }

  private waitForInitialRouteReadiness(): Promise<string> {
    return this.launchReadinessPromise
      .then(() => this.initialExternalShareIngressReadiness)
      .then(() => this.waitForInitialBrowserPresentationFacts())
      .then(() => {
        const presentationInput = this.browserPresentationMainWindow === undefined
          ? undefined
          : this.browserWindowPresentationProfileInputService.resolve(this.browserPresentationMainWindow);
        BrowserWindowRuntime.prepareInitialShellPresentation(this.pageStorage, presentationInput);
        return sharedStartupWelcomeIntroRepository.hasCompletedCurrentVersion()
          ? BROWSER_SHELL_ROUTE
          : STARTUP_WELCOME_INTRO_ROUTE;
      });
  }

  private waitForInitialBrowserPresentationFacts(): Promise<void> {
    const pendingFacts = this.initialBrowserPresentationFactsReady;
    return pendingFacts.then((): Promise<void> => {
      if (pendingFacts !== this.initialBrowserPresentationFactsReady) {
        return this.waitForInitialBrowserPresentationFacts();
      }
      return Promise.resolve();
    });
  }

  private startBrowserRuntimeInitialization(source: string): void {
    if (this.runtimeInitializationStarted) {
      return;
    }
    this.runtimeInitializationStarted = true;
    this.runtimeInitializationPromise = initializeBrowserAppRuntime(this.context)
      .then(() => {
        hilog.info(DOMAIN, TAG, 'Browser runtime bootstrap completed after %{public}s.', source);
      })
      .catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Failed to bootstrap browser runtime after %{public}s: %{public}s', source, JSON.stringify(error));
      });
  }

  private configureMainWindow(windowStage: window.WindowStage): Promise<window.Window> {
    return windowStage.getMainWindow()
      .then((mainWindow: window.Window) => {
        return mainWindow.setWindowLayoutFullScreen(true)
          .then(() => {
            return mainWindow.setWindowSystemBarProperties({
              statusBarColor: '#00000000',
              statusBarContentColor: BROWSER_STATUS_BAR_DARK_CONTENT_COLOR,
              isStatusBarLightIcon: false,
              navigationBarColor: LIGHT_SYSTEM_NAVIGATION_BAR_COLOR
            });
          })
          .then(() => {
            hilog.info(DOMAIN, TAG, 'Main window immersive layout configured.');
            return mainWindow;
          });
      });
  }

  private bindTabletInterfaceModeUpdates(): void {
    if (this.tabletInterfaceModeListenerKey.length > 0) {
      return;
    }
    this.tabletInterfaceModeListenerKey = sharedBrowserTabletInterfaceModeRepository.subscribe((): void => {
      if (this.browserPresentationMainWindow !== undefined) {
        this.reconcileBrowserWindowPresentationProfile(
          this.browserPresentationMainWindow,
          'tablet-interface-mode-change'
        );
      }
    });
  }

  private unbindTabletInterfaceModeUpdates(): void {
    if (this.tabletInterfaceModeListenerKey.length <= 0) {
      return;
    }
    sharedBrowserTabletInterfaceModeRepository.unsubscribe(this.tabletInterfaceModeListenerKey);
    this.tabletInterfaceModeListenerKey = '';
  }

  private reconcileBrowserWindowPresentationProfile(
    mainWindow: window.Window,
    source: string,
    reconcileApplicationIdentity: boolean = false
  ): void {
    if (this.browserWindowSessionId.trim().length <= 0) {
      return;
    }
    this.browserWindowPresentationProfileRevision += 1;
    const input = this.browserWindowPresentationProfileInputService.resolve(mainWindow);
    input.pointerAvailable = this.browserPointerAvailable;
    input.tabletInterfaceMode = sharedBrowserTabletInterfaceModeRepository.getMode();
    input.foldState = this.browserWindowDisplayViewportCoordinator.getFoldPresentationState();
    const reconciliation = BrowserWindowRuntime.reconcileSessionPresentation(
      this.browserWindowSessionId,
      input,
      this.browserShellAdapterCatalog.resolveAvailability(),
      this.browserWindowPresentationProfileRevision
    );
    if (reconciliation === undefined) {
      return;
    }
    const profile = reconciliation.profile;
    if (reconcileApplicationIdentity || reconciliation.presentationChanged) {
      const userAgentPolicy = sharedBrowserUserAgentHostPolicyService.reconcileApplicationUserAgentForPresentation(
        sharedBrowserUserAgentSettingsRepository.getSettings(),
        profile.shellFamily
      );
      if (userAgentPolicy.applied) {
        hilog.info(
          DOMAIN,
          TAG,
          'Browser application User-Agent reconciled source=%{public}s shell=%{public}s',
          source,
          profile.shellFamily
        );
      } else {
        hilog.warn(DOMAIN, TAG, '%{public}s', userAgentPolicy.message);
      }
    }
    if (reconciliation.presentationChanged) {
      BrowserShellPresentationRefreshSignal.publish();
    }
    hilog.info(
      DOMAIN,
      TAG,
      'Browser Shell Family profile source=%{public}s family=%{public}s device=%{public}s widthVp=%{public}d heightVp=%{public}d reason=%{public}s revision=%{public}d',
      source,
      profile.shellFamily,
      profile.detectedFormFactor,
      profile.windowWidthVp,
      profile.windowHeightVp,
      profile.decisionReason,
      profile.revision
    );
  }

  private reconcileBrowserLargeScreenWindowFacts(
    mainWindow: window.Window,
    windowStageGeneration: number,
    source: string
  ): Promise<void> {
    const sessionId = this.browserWindowSessionId;
    if (sessionId.trim().length <= 0) {
      return Promise.resolve();
    }
    const requestRevision = ++this.browserLargeScreenWindowFactsRequestRevision;
    const avoidAreaInsets = this.browserWindowAvoidAreaCoordinator.syncStorage(mainWindow, this.pageStorage);
    return this.browserWindowPresentationProfileInputService.resolveLargeScreenFacts(
      mainWindow,
      avoidAreaInsets,
      sharedBrowserLargeScreenWindowChromeService.isIntegrated(sessionId)
    )
      .then((facts: BrowserLargeScreenWindowFactsInput): void => {
        if (windowStageGeneration !== this.windowStageLifecycleGeneration ||
          sessionId !== this.browserWindowSessionId ||
          requestRevision !== this.browserLargeScreenWindowFactsRequestRevision) {
          return;
        }
        this.browserPointerAvailable = facts.pointerAvailable;
        this.reconcileBrowserWindowPresentationProfile(mainWindow, `${source}:input-facts`);
        const presentationResult = BrowserWindowRuntime.reconcileLargeScreenWindowFacts(
          sessionId,
          facts,
          DEFAULT_BROWSER_LARGE_SCREEN_WINDOW_FACTS_POLICY
        );
        if (presentationResult.changed) {
          BrowserShellPresentationRefreshSignal.publish();
        }
        hilog.info(
          DOMAIN,
          TAG,
          'Large-Screen window facts source=%{public}s mode=%{public}s widthVp=%{public}d heightVp=%{public}d pointer=%{public}s keyboard=%{public}s drag=%{public}s',
          source,
          facts.windowMode,
          facts.availableWidthVp,
          facts.availableHeightVp,
          String(facts.pointerAvailable),
          String(facts.physicalKeyboardAvailable),
          String(facts.dragSupported)
        );
      })
      .catch((error: Error): void => {
        if (windowStageGeneration !== this.windowStageLifecycleGeneration ||
          sessionId !== this.browserWindowSessionId ||
          requestRevision !== this.browserLargeScreenWindowFactsRequestRevision) {
          return;
        }
        hilog.warn(
          DOMAIN,
          TAG,
          'Large-Screen window facts unavailable source=%{public}s error=%{public}s',
          source,
          JSON.stringify(error)
        );
      });
  }

  private stagePendingMissionIdentity(launchPayload: BrowserLaunchPayload, windowId: string): void {
    if (launchPayload.shortcut === undefined || windowId === 'window-main') {
      return;
    }
    this.pendingMissionLaunchPayload = launchPayload;
    this.pendingMissionWindowId = windowId;
  }

  private applyPendingMissionIdentityAfterWindowStageCreate(windowId: string): void {
    if (this.pendingMissionLaunchPayload === undefined || this.pendingMissionWindowId !== windowId) {
      return;
    }
    this.desktopWebEntryMissionIdentityService.apply(this.context, this.pendingMissionLaunchPayload, windowId, 'windowStageCreate');
  }

  private applyPendingMissionIdentityAfterContentLoad(windowId: string): void {
    if (this.pendingMissionLaunchPayload === undefined || this.pendingMissionWindowId !== windowId) {
      return;
    }
    this.desktopWebEntryMissionIdentityService.apply(this.context, this.pendingMissionLaunchPayload, windowId, 'contentLoaded');
    this.pendingMissionLaunchPayload = undefined;
    this.pendingMissionWindowId = '';
  }

}
