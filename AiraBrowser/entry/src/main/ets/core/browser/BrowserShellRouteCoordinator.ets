import router from '@ohos.router';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import { resolveAppResourceText } from '../resources/AppResourceText';
import {
  BrowserDataScope,
  HomeSystemShortcutTarget,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  AD_BLOCK_SETTINGS_ROUTE,
  AIRA_PRO_ROUTE,
  APP_PROXY_SETTINGS_ROUTE,
  BOOKMARK_MANAGER_ROUTE,
  BROWSER_TRACKING_PROTECTION_SETTINGS_ROUTE,
  DOWNLOAD_MANAGEMENT_ROUTE,
  HISTORY_MANAGER_ROUTE,
  HUAWEI_ACCOUNT_INFO_ROUTE,
  OFFLINE_PAGES_ROUTE,
  NOVEL_BOOKSHELF_ROUTE,
  SEARCH_SETTINGS_ROUTE,
  SETTINGS_CENTER_ROUTE,
  SETTINGS_CHANGELOG_ROUTE,
  SETTINGS_DETAIL_ROUTE,
  SITE_CONTROLS_MANAGEMENT_ROUTE,
  SITE_CUSTOMIZATION_DETAIL_ROUTE,
  SYNC_SETTINGS_ROUTE,
  USER_SCRIPT_DETAIL_ROUTE,
  USER_SCRIPTS_ROUTE
} from '../../app/router/AppRoutes';
import {
  isSecureCurrentSiteUrl,
  resolveCurrentSiteHost,
  resolveCurrentSiteUrl
} from './AddressDisplayFormatter';
import {
  BrowserBookmarkRouteParams,
  BrowserBookmarkScopeService
} from './BrowserBookmarkScopeService';
import {
  BrowserPrivateBoundaryNavigationService,
  BrowserPrivateBoundaryRouteParams
} from './BrowserPrivateBoundaryNavigationService';
import { BrowserPrivateProfileLifecycleCoordinator } from './BrowserPrivateProfileLifecycleCoordinator';
import { formatOpenUserScriptsPageError } from '../userscripts/UserScriptFeatureCopy';
import { BrowserPrivateModeLockCoordinator } from '../privacy/BrowserPrivateModeLockCoordinator';
import { BrowserBottomPanelActionId } from './BrowserBottomPanelActionCatalog';
import { SiteInteractionLogicService } from '../../services/web/SiteInteractionLogicService';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import {
  BrowserNativeTabOpenRequest,
  BrowserNativeTabScene,
  browserNativeTabSceneService
} from './BrowserNativeTabSceneService';
import { BrowserShellPresentationSurface } from './BrowserShellPresentationCoordinator';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserTabCloseCoordinator } from './BrowserTabCloseCoordinator';
import { sharedBrowserTabletInterfaceModeTransitionOwner } from '../settings/BrowserTabletInterfaceModeTransitionOwner';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

// Temporary Phase-D timing evidence for routed toolbar actions. Remove with the diagnostic.
const BROWSER_ROUTE_ACTION_DIAGNOSTIC_DOMAIN: number = 0x0000;
const BROWSER_ROUTE_ACTION_DIAGNOSTIC_TAG: string = 'RouteActionDiag';
const BROWSER_ROUTE_ACTION_DIAGNOSTIC_PREFIX: string = '[DIAG-route-action-20260914]';

export interface BrowserShellSettingsDetailRouteParams {
  sectionId: string;
  dataScope?: BrowserDataScope | string;
  privacyMode?: string;
  boundarySource?: string;
}

export interface BrowserShellUserScriptDetailRouteParams {
  scriptId: string;
}

export interface BrowserShellSiteControlsRouteParams {
  dataScope?: BrowserDataScope | string;
  privacyMode?: string;
  boundarySource?: string;
  host: string;
  origin: string;
  profileId: BrowserProfileId;
}

export type BrowserShellRouteParams =
  BrowserBookmarkRouteParams |
  BrowserPrivateBoundaryRouteParams |
  BrowserShellSettingsDetailRouteParams |
  BrowserShellUserScriptDetailRouteParams |
  Record<string, never>;

interface BrowserPhoneBookmarkRouteParams extends BrowserBookmarkRouteParams {
  folderId: string;
  query: string;
}

type BrowserShellRouteNavigationParams =
  BrowserShellRouteParams |
  BrowserShellSiteControlsRouteParams |
  BrowserPhoneBookmarkRouteParams;

export interface BrowserShellRouteContext {
  dataScope: BrowserDataScope;
  privacyMode: BrowserSessionPrivacyMode;
  profileId: BrowserProfileId;
  currentUrl: string;
  addressInput: string;
  activeTabId: string;
}

export interface BrowserShellRouteCoordinatorHost {  presentRouteFailure: (errorMessage: string, toastMessage?: string) => void;
  resetTransientOverlayStateForRouteTransition: () => void;
  openTabsOverview: () => void;
  isLargeScreenShellActive: () => boolean;
  openLargeScreenNativeRoute: (request: BrowserNativeTabOpenRequest) => void;
}

interface BrowserPhoneNativeTabRouteRequest {
  url: string;
  params: BrowserShellRouteNavigationParams | undefined;
  failurePrefix: string;
}

interface BrowserShellRouteCoordinatorDependencies {
  privateModeLockCoordinator: BrowserPrivateModeLockCoordinator;
  resolveSiteInteractionLogicService: () => SiteInteractionLogicService;
  resolveTabScopedEventContextCoordinator: () => BrowserTabScopedEventContextCoordinator;
  resolveTabCloseCoordinator: () => BrowserTabCloseCoordinator;
  resolveUIContext: () => UIContext;
}

/**
 * Defers the route commit past the reset UI turn and past the frame that paints the
 * reset, without waiting for an idle frame. `onIdle` only fires when a frame has more
 * than 1ms left before the next VSync, so while the bottom panel is collapsing every
 * frame is busy and the callback is deferred until the animation ends — that is what
 * made a routed toolbar action appear to wait for the toolbar to retract.
 */
class BrowserShellRouteFrameCallback extends FrameCallback {
  private readonly task: () => void;

  constructor(task: () => void) {
    super();
    this.task = task;
  }

  onFrame(_frameTimeInNano: number): void {
    this.task();
  }

  onIdle(_timeLeftInNano: number): void {
  }
}

export class BrowserShellRouteCoordinator {
  private readonly host: BrowserShellRouteCoordinatorHost;
  private readonly dependencies: BrowserShellRouteCoordinatorDependencies;
  private readonly boundaryNavigationService: BrowserPrivateBoundaryNavigationService =
    new BrowserPrivateBoundaryNavigationService();
  private readonly bookmarkScopeService: BrowserBookmarkScopeService = new BrowserBookmarkScopeService();
  private readonly privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator =
    new BrowserPrivateProfileLifecycleCoordinator();
  private routeTransitionRunId: number = 0;
  private phoneNativeTabHandoffKey: string = '';
  // Timing-only state for the routed-toolbar-action diagnostic. Not part of route policy.
  private routeRequestStartedAt: number = 0;
  private routeRequestUrl: string = '';

  constructor(
    host: BrowserShellRouteCoordinatorHost,
    dependencies: BrowserShellRouteCoordinatorDependencies
  ) {
    this.host = host;
    this.dependencies = dependencies;
  }

  dispatchHomeRouteAction(actionId: BrowserBottomPanelActionId): boolean {
    switch (actionId) {
      case 'openBookmarks':
        void this.openBookmarkManagerPage();
        return true;
      case 'history':
        this.openHistoryManagerPage();
        return true;
      case 'downloads':
        this.openDownloadManagementPage();
        return true;
      case 'settings':
        this.openSettingsCenterPage();
        return true;
      case 'savedPages':
        this.openOfflinePagesPage();
        return true;
      case 'scripts':
        this.openUserScriptsPage();
        return true;
      case 'novel':
        this.openNovelBookshelfPage();
        return true;
      default:
        return false;
    }
  }

  openHomeSystemEntry(target: HomeSystemShortcutTarget): boolean {
    switch (target) {
      case 'bookmarks':
        void this.openBookmarkManagerPage();
        return true;
      case 'history':
        this.openHistoryManagerPage();
        return true;
      case 'downloads':
        this.openDownloadManagementPage();
        return true;
      case 'saved_pages':
        this.openOfflinePagesPage();
        return true;
      case 'tabs':
        this.host.openTabsOverview();
        return true;
      case 'user_scripts':
        this.openUserScriptsPage();
        return true;
      case 'ad_block':
        this.openAdBlockSettingsPage();
        return true;
      case 'settings':
        this.openSettingsCenterPage();
        return true;
      default:
        return false;
    }
  }

  async openBookmarkManagerPage(): Promise<void> {
    const context = this.resolveContext();
    const accessPlan = this.privateProfileLifecycleCoordinator.buildPrivateBookmarkAccessPlan(
      context.dataScope,
      context.privacyMode
    );
    if (accessPlan.shouldAuthenticate && !await this.dependencies.privateModeLockCoordinator.ensureUnlocked(
      accessPlan.authPrivacyMode,
      accessPlan.authDataScope,
      accessPlan.authReason
    )) {
      return;
    }
    const routeContext = this.resolveContext();
    if (this.host.isLargeScreenShellActive()) {
      this.host.openLargeScreenNativeRoute({ scene: 'bookmarks' });
      return;
    }
    this.pushRoute(
      BOOKMARK_MANAGER_ROUTE,
      this.bookmarkScopeService.buildRouteParams(routeContext.dataScope, routeContext.privacyMode),
      resolveAppResourceText($r('app.string.offline_bookmarks_open_failed'))
    );
  }

  openHistoryManagerPage(): void {
    if (this.host.isLargeScreenShellActive()) {
      this.host.openLargeScreenNativeRoute({ scene: 'history' });
      return;
    }
    this.pushRoute(
      HISTORY_MANAGER_ROUTE,
      this.buildBoundaryRouteParams(),
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_003'))
    );
  }

  openSyncSettingsPage(): void {
    this.pushRoute(
      SYNC_SETTINGS_ROUTE,
      this.buildBoundaryRouteParams(),
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_004'))
    );
  }

  openTrackingProtectionSettingsPage(): void {
    this.pushRoute(
      BROWSER_TRACKING_PROTECTION_SETTINGS_ROUTE,
      this.buildBoundaryRouteParams(),
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_015'))
    );
  }

  openSearchSettingsPage(): void {
    this.pushRoute(SEARCH_SETTINGS_ROUTE, undefined,
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_007')));
  }

  openAdBlockSettingsPage(): void {
    this.pushRoute(AD_BLOCK_SETTINGS_ROUTE, undefined,
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_011')));
  }

  openUserScriptsPage(): void {
    if (this.host.isLargeScreenShellActive()) {
      this.host.openLargeScreenNativeRoute({ scene: 'user_scripts' });
      return;
    }
    router.pushUrl({
      url: USER_SCRIPTS_ROUTE,
      params: this.buildBoundaryRouteParams()
    }).catch((error: Error) => {
      this.host.presentRouteFailure(formatOpenUserScriptsPageError(error));
    });
  }

  openUserScriptDetailPage(scriptId: string): void {
    this.pushRoute(
      USER_SCRIPT_DETAIL_ROUTE,
      { scriptId: scriptId },
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_012'))
    );
  }

  openSettingsCenterPage(): void {
    if (this.host.isLargeScreenShellActive()) {
      this.host.openLargeScreenNativeRoute({ scene: 'settings' });
      return;
    }
    this.pushRoute(
      SETTINGS_CENTER_ROUTE,
      this.buildBoundaryRouteParams(),
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_013'))
    );
  }

  /**
   * Opens the Huawei account page from the toolbar sheet's account capsule.
   *
   * The capsule only offers this when an account is signed in; the signed-out path opens the login
   * sheet instead, so there is no signed-out state to handle here.
   */
  openHuaweiAccountInfoPage(): void {
    if (this.host.isLargeScreenShellActive()) {
      this.host.openLargeScreenNativeRoute({ scene: 'settings' });
      return;
    }
    this.pushRoute(
      HUAWEI_ACCOUNT_INFO_ROUTE,
      this.buildBoundaryRouteParams(),
      resolveAppResourceText($r('app.string.settings_account_info'))
    );
  }

  openChangelogPage(): void {
    this.pushRoute(
      SETTINGS_CHANGELOG_ROUTE,
      this.buildBoundaryRouteParams(),
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_008'))
    );
  }

  openAiraProPage(): void {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
      return;
    }
    if (this.host.isLargeScreenShellActive()) {
      this.host.openLargeScreenNativeRoute({ scene: 'settings', settingsDestination: 'aira_pro' });
      return;
    }
    this.pushRoute(
      AIRA_PRO_ROUTE,
      this.buildBoundaryRouteParams(),
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_001'))
    );
  }

  openSettingsDetailPage(sectionId: string): void {
    const routeParams = this.buildBoundaryRouteParams();
    const settingsDetailRouteParams: BrowserShellSettingsDetailRouteParams = {
      sectionId: sectionId,
      dataScope: routeParams.dataScope,
      privacyMode: routeParams.privacyMode,
      boundarySource: routeParams.boundarySource
    };
    this.pushRoute(
      SETTINGS_DETAIL_ROUTE,
      settingsDetailRouteParams,
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_014'))
    );
  }

  openSimpleRoute(url: string, failurePrefix: string): void {
    this.pushRoute(
      url,
      this.buildBoundaryRouteParams(),
      failurePrefix
    );
  }

  openCurrentSiteControls(): void {
    const context = this.resolveContext();
    const boundaryRouteParams = this.buildBoundaryRouteParams(context);
    const currentUrl = resolveCurrentSiteUrl(context.currentUrl, context.addressInput);
    const hostName = resolveCurrentSiteHost(context.currentUrl, context.addressInput);
    const origin = this.dependencies.resolveSiteInteractionLogicService().resolveOrigin(currentUrl);
    const routeParams: BrowserShellSiteControlsRouteParams = {
      dataScope: boundaryRouteParams.dataScope,
      privacyMode: boundaryRouteParams.privacyMode,
      boundarySource: boundaryRouteParams.boundarySource,
      host: hostName,
      origin: origin,
      profileId: context.profileId
    };
    this.pushRoute(
      hostName.length > 0 || origin.length > 0 ? SITE_CUSTOMIZATION_DETAIL_ROUTE : SITE_CONTROLS_MANAGEMENT_ROUTE,
      routeParams,
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_010'))
    );
  }

  openOfflinePagesPage(): void {
    if (this.host.isLargeScreenShellActive()) {
      this.host.openLargeScreenNativeRoute({ scene: 'saved_pages' });
      return;
    }
    try {
      router.pushUrl({
        url: OFFLINE_PAGES_ROUTE,
        params: this.buildBoundaryRouteParams()
      }).catch((error: Error) => {
        this.host.presentRouteFailure(
          resolveAppResourceText($r('app.string.offline_route_open_failed_detail'), JSON.stringify(error)),
          resolveAppResourceText($r('app.string.offline_route_open_failed'))
        );
      });
    } catch (error) {
      this.host.presentRouteFailure(
        resolveAppResourceText($r('app.string.offline_route_open_failed_detail'), JSON.stringify(error)),
        resolveAppResourceText($r('app.string.offline_route_open_failed'))
      );
    }
  }

  openNovelBookshelfPage(): void {
    if (this.host.isLargeScreenShellActive()) {
      this.host.resetTransientOverlayStateForRouteTransition();
      this.host.openLargeScreenNativeRoute({ scene: 'bookshelf' });
      return;
    }
    this.pushRoute(
      NOVEL_BOOKSHELF_ROUTE,
      this.buildBoundaryRouteParams(),
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_006'))
    );
  }

  openAppProxySettingsPage(): void {
    if (this.host.isLargeScreenShellActive()) {
      this.host.resetTransientOverlayStateForRouteTransition();
      this.host.openLargeScreenNativeRoute({ scene: 'app_proxy' });
      return;
    }
    this.openSimpleRoute(APP_PROXY_SETTINGS_ROUTE,
      resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_005')));
  }

  openDownloadManagementPage(): void {
    if (this.host.isLargeScreenShellActive()) {
      this.host.resetTransientOverlayStateForRouteTransition();
      this.host.openLargeScreenNativeRoute({ scene: 'downloads' });
      return;
    }
    const context = this.resolveContext();
    const routeParams = this.buildBoundaryRouteParams(context);
    this.host.resetTransientOverlayStateForRouteTransition();
    router.pushUrl({
      url: DOWNLOAD_MANAGEMENT_ROUTE,
      params: routeParams
    }).catch((error: Error) => {
      this.host.presentRouteFailure(resolveAppResourceText($r('app.string.browser_shell_route_failed_detail',
        resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_002')),
        JSON.stringify(error))));
    });
  }

  reconcilePhoneNativeTabHandoff(
    surface: BrowserShellPresentationSurface | undefined,
    tabs: BrowserTabState[],
    activeTabId: string,
    homeVisible: boolean
  ): void {
    if (surface !== 'phone' || homeVisible) {
      this.phoneNativeTabHandoffKey = '';
      return;
    }
    const normalizedActiveTabId = activeTabId.trim();
    const activeTab = tabs.find((tab: BrowserTabState): boolean => tab.id === normalizedActiveTabId);
    if (activeTab === undefined) {
      this.phoneNativeTabHandoffKey = '';
      return;
    }
    const scene = browserNativeTabSceneService.resolveSceneForTab(activeTab.url, activeTab.pendingUrl);
    if (scene === undefined) {
      this.phoneNativeTabHandoffKey = '';
      return;
    }
    if (scene === 'settings' && sharedBrowserTabletInterfaceModeTransitionOwner.consumeCommitted(
      'touch',
      'phone_native_settings_handoff'
    )) {
      this.phoneNativeTabHandoffKey = '';
      void this.dependencies.resolveTabCloseCoordinator().closeCurrentTabForUserReturnHome({
        activeTab: activeTab,
        helperMessage: resolveAppResourceText($r('app.string.browser_shell_008')),
        homeOptions: {
          profileId: activeTab.profileId,
          privacyMode: activeTab.privacyMode,
          dataScope: activeTab.dataScope
        },
        shouldPlayDirectHomeReveal: false,
        cleanupReason: 'manual_interface_mode_return_home'
      });
      return;
    }
    const nativeRouteUrl = activeTab.pendingUrl.trim().length > 0 ? activeTab.pendingUrl : activeTab.url;
    const handoffKey = `${activeTab.id}:${nativeRouteUrl}`;
    if (handoffKey === this.phoneNativeTabHandoffKey) {
      return;
    }
    this.phoneNativeTabHandoffKey = handoffKey;
    const request = this.buildPhoneNativeTabRouteRequest(scene, nativeRouteUrl, activeTab);
    this.pushRoute(request.url, request.params, request.failurePrefix, (): void => {
      void this.dependencies.resolveTabCloseCoordinator().closeTab(activeTab.id);
    }, (): void => {
      if (this.phoneNativeTabHandoffKey === handoffKey) {
        this.phoneNativeTabHandoffKey = '';
      }
    });
  }

  resolveSiteSecurityTitle(currentUrl: string, addressInput: string): string {
    if (isSecureCurrentSiteUrl(currentUrl, addressInput)) {
      return resolveAppResourceText($r('app.string.bottom_panel_secure'));
    }
    return resolveAppResourceText($r('app.string.bottom_panel_unverified'));
  }

  resolveSiteSecurityIcon(currentUrl: string, addressInput: string): Resource {
    if (isSecureCurrentSiteUrl(currentUrl, addressInput)) {
      return $r('sys.symbol.checkmark_shield_fill');
    }
    return $r('sys.symbol.exclamationmark_shield_fill');
  }

  private buildBoundaryRouteParams(
    context: BrowserShellRouteContext = this.resolveContext()
  ): BrowserPrivateBoundaryRouteParams {
    return this.boundaryNavigationService.buildRouteParams(context.dataScope, context.privacyMode);
  }

  private resolveContext(): BrowserShellRouteContext {
    const contextOwner = this.dependencies.resolveTabScopedEventContextCoordinator();
    const current = contextOwner.resolveCurrentContext();
    return {
      dataScope: current.dataScope,
      privacyMode: current.privacyMode,
      profileId: current.profileId,
      currentUrl: current.currentUrl,
      addressInput: current.addressInput,
      activeTabId: current.activeTabId
    };
  }

  private buildPhoneNativeTabRouteRequest(
    scene: BrowserNativeTabScene,
    nativeRouteUrl: string,
    activeTab: BrowserTabState
  ): BrowserPhoneNativeTabRouteRequest {
    const boundaryParams = this.boundaryNavigationService.buildRouteParams(
      activeTab.dataScope,
      activeTab.privacyMode
    );
    switch (scene) {
      case 'bookmarks': {
        const bookmarkParams = this.bookmarkScopeService.buildRouteParams(
          activeTab.dataScope,
          activeTab.privacyMode
        );
        const bookmarkRoute = browserNativeTabSceneService.parseBookmarkRoute(
          nativeRouteUrl,
          bookmarkParams.bookmarkScope
        );
        return {
          url: BOOKMARK_MANAGER_ROUTE,
          params: {
            dataScope: bookmarkParams.dataScope,
            privacyMode: bookmarkParams.privacyMode,
            boundarySource: bookmarkParams.boundarySource,
            bookmarkScope: bookmarkParams.bookmarkScope,
            folderId: bookmarkRoute.folderId,
            query: bookmarkRoute.query
          },
          failurePrefix: resolveAppResourceText($r('app.string.offline_bookmarks_open_failed'))
        };
      }
      case 'history':
        return {
          url: HISTORY_MANAGER_ROUTE,
          params: boundaryParams,
          failurePrefix: resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_003'))
        };
      case 'settings':
        return {
          url: SETTINGS_CENTER_ROUTE,
          params: boundaryParams,
          failurePrefix: resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_013'))
        };
      case 'downloads':
        return {
          url: DOWNLOAD_MANAGEMENT_ROUTE,
          params: boundaryParams,
          failurePrefix: resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_002'))
        };
      case 'user_scripts':
        return {
          url: USER_SCRIPTS_ROUTE,
          params: boundaryParams,
          failurePrefix: resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_009'))
        };
      case 'app_proxy':
        return {
          url: APP_PROXY_SETTINGS_ROUTE,
          params: boundaryParams,
          failurePrefix: resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_005'))
        };
      case 'saved_pages':
        return {
          url: OFFLINE_PAGES_ROUTE,
          params: boundaryParams,
          failurePrefix: resolveAppResourceText($r('app.string.offline_route_open_failed'))
        };
      case 'bookshelf':
        return {
          url: NOVEL_BOOKSHELF_ROUTE,
          params: boundaryParams,
          failurePrefix: resolveAppResourceText($r('app.string.browser_browser_shell_route_coordinator_006'))
        };
      default:
        return {
          url: OFFLINE_PAGES_ROUTE,
          params: boundaryParams,
          failurePrefix: resolveAppResourceText($r('app.string.offline_route_open_failed'))
        };
    }
  }

  private pushRoute(
    url: string,
    params: BrowserShellRouteNavigationParams | undefined,
    failurePrefix: string,
    onCommitted?: () => void,
    onFailed?: () => void
  ): void {
    const runId = ++this.routeTransitionRunId;
    this.routeRequestStartedAt = Date.now();
    this.routeRequestUrl = url;
    this.host.resetTransientOverlayStateForRouteTransition();
    try {
      this.dependencies.resolveUIContext().postFrameCallback(new BrowserShellRouteFrameCallback((): void => {
        if (runId !== this.routeTransitionRunId) {
          onFailed?.();
          return;
        }
        try {
          this.dependencies.resolveUIContext().postFrameCallback(new BrowserShellRouteFrameCallback((): void => {
            this.commitRoute(runId, url, params, failurePrefix, onCommitted, onFailed);
          }));
        } catch (_error) {
          this.commitRoute(runId, url, params, failurePrefix, onCommitted, onFailed);
        }
      }));
    } catch (error) {
      if (runId !== this.routeTransitionRunId) {
        return;
      }
      onFailed?.();
      this.host.presentRouteFailure(resolveAppResourceText(
        $r('app.string.browser_shell_route_failed_detail', failurePrefix, JSON.stringify(error))));
    }
  }

  private commitRoute(
    runId: number,
    url: string,
    params: BrowserShellRouteNavigationParams | undefined,
    failurePrefix: string,
    onCommitted?: () => void,
    onFailed?: () => void
  ): void {
    if (runId !== this.routeTransitionRunId) {
      onFailed?.();
      return;
    }
    hilog.info(
      BROWSER_ROUTE_ACTION_DIAGNOSTIC_DOMAIN,
      BROWSER_ROUTE_ACTION_DIAGNOSTIC_TAG,
      '%{public}s router_push url=%{public}s runId=%{public}d deferredMs=%{public}d',
      BROWSER_ROUTE_ACTION_DIAGNOSTIC_PREFIX,
      url,
      runId,
      Date.now() - this.routeRequestStartedAt
    );
    router.pushUrl({
      url: url,
      params: params
    }).then((): void => {
      hilog.info(
        BROWSER_ROUTE_ACTION_DIAGNOSTIC_DOMAIN,
        BROWSER_ROUTE_ACTION_DIAGNOSTIC_TAG,
        '%{public}s router_committed url=%{public}s runId=%{public}d totalMs=%{public}d',
        BROWSER_ROUTE_ACTION_DIAGNOSTIC_PREFIX,
        this.routeRequestUrl,
        runId,
        Date.now() - this.routeRequestStartedAt
      );
      onCommitted?.();
    }).catch((error: Error) => {
      onFailed?.();
      this.host.presentRouteFailure(resolveAppResourceText(
        $r('app.string.browser_shell_route_failed_detail', failurePrefix, JSON.stringify(error))));
    });
  }
}
