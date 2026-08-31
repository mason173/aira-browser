import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  TabLaunchContext,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  BrowserCreateTabOptions,
  BrowserTabState,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import {
  BrowserTabTransitionCoordinator
} from './BrowserTabTransitionCoordinator';
import { CreateNewTabRuntimeOptions } from './BrowserShellRuntimeContracts';
import {
  BrowserNavigationScene,
  BrowserNavigationTransition,
  BrowserNavigationTransitionService
} from './BrowserNavigationTransitionService';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';
import {
  BrowserForegroundTabCreationCoordinator,
  BrowserForegroundTabCreationHost,
  BrowserForegroundTabCreationRequest
} from './BrowserForegroundTabCreationCoordinator';
import { BrowserTabSessionPersistenceCoordinator } from './BrowserTabSessionPersistenceCoordinator';
import { BrowserBackgroundTabPreviewRuntimeCoordinator } from './BrowserBackgroundTabPreviewRuntimeCoordinator';
import { BrowserBackgroundOpenPromptCoordinator } from './BrowserBackgroundOpenPromptCoordinator';
import { BrowserSearchSuggestionCoordinator } from './BrowserSearchSuggestionCoordinator';
import { BrowserRecentActionManager } from '../web/BrowserRecentActionManager';
import { WebRuntimeBridge } from '../web/WebRuntimeBridge';
import {
  BrowserUnifiedLinkNavigationCoordinator,
  BrowserUnifiedLinkNavigationHost
} from './BrowserUnifiedLinkNavigationCoordinator';
import { BrowserOfflineFastFailureCoordinator } from '../../services/web/BrowserOfflineFastFailureCoordinator';
import {
  BrowserWebLoadLifecycleApplication,
  BrowserWebLoadRuntimeCoordinator
} from '../../services/web/BrowserWebLoadRuntimeCoordinator';
import { HomeShortcutWebOpenPlan } from '../../services/shortcuts/HomeShortcutOpenPolicyService';
import { HomeShortcutIconAssociationUpdateCenter } from
  '../../services/shortcuts/HomeShortcutIconAssociationUpdateCenter';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserAddressDisplayCoordinator } from './BrowserAddressDisplayCoordinator';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { resolveBrowserNewWindowTestTitle } from '../../app/debug/BrowserNewWindowTestPage';
import {
  sharedBrowserHttpsFirstNavigationService
} from '../../services/web/BrowserHttpsFirstNavigationService';

export type BrowserAppUrlOpenIntent = 'current_tab' | 'new_tab' | 'background_tab';

export type BrowserAppUrlOpenSource =
  'bookmark' |
  'history' |
  'offline' |
  'home_shortcut' |
  'web_context_menu' |
  'userscript_install' |
  'external_url' |
  'app_ui';

export interface BrowserAppUrlOpenRequest {
  url: string;
  title?: string;
  intent?: BrowserAppUrlOpenIntent;
  source?: BrowserAppUrlOpenSource;
  helperMessage?: string;
  profileId?: BrowserProfileId;
  privacyMode?: BrowserSessionPrivacyMode;
  dataScope?: BrowserDataScope;
  launchContext?: TabLaunchContext;
  createOptions?: BrowserCreateTabOptions;
  openerTabId?: string;
  requestId?: string;
  browserGeneratedHttpFallbackUrl?: string;
}

type BrowserAppUrlOpenAction = 'open_current_tab' | 'open_new_tab' | 'open_background_tab' | 'reject';
type BrowserAppUrlOpenMessageKind = 'helper' | 'error' | 'toast';

interface BrowserAppUrlOpenPlan {
  action: BrowserAppUrlOpenAction;
  url: string;
  title: string;
  intent: BrowserAppUrlOpenIntent;
  source: BrowserAppUrlOpenSource;
  transition: BrowserNavigationTransition;
  scene: BrowserNavigationScene;
  reason: string;
  profileId?: BrowserProfileId;
  privacyMode?: BrowserSessionPrivacyMode;
  dataScope?: BrowserDataScope;
  launchContext?: TabLaunchContext;
  createOptions?: BrowserCreateTabOptions;
  openerTabId: string;
  requestId: string;
  message: string;
  browserGeneratedHttpFallbackUrl: string;
}

interface BrowserAppUrlOpenBoundary {
  profileId?: BrowserProfileId;
  privacyMode?: BrowserSessionPrivacyMode;
  dataScope?: BrowserDataScope;
}

export interface BrowserAppUrlOpenHost extends BrowserForegroundTabCreationHost {
  isHomeSurfaceVisible: () => boolean;
  getOpenErrorMessage: () => string;
  applyAddressInput: (addressInput: string) => void;
  applyMessage: (kind: BrowserAppUrlOpenMessageKind, message: string) => void;
}

interface BrowserAppUrlOpenDependencies {
  tabManager: BrowserTabManagerPort;
  foregroundTabCreationCoordinator: BrowserForegroundTabCreationCoordinator;
  recentActionManager: BrowserRecentActionManager;
  offlineFastFailureCoordinator: BrowserOfflineFastFailureCoordinator;
  webLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator;
  tabSessionPersistenceCoordinator: BrowserTabSessionPersistenceCoordinator;
  backgroundTabPreviewRuntimeCoordinator: BrowserBackgroundTabPreviewRuntimeCoordinator;
  backgroundOpenPromptCoordinator: BrowserBackgroundOpenPromptCoordinator;
  searchSuggestionCoordinator: BrowserSearchSuggestionCoordinator;
  webRuntimeBridge: WebRuntimeBridge;
  unifiedLinkNavigationCoordinator: BrowserUnifiedLinkNavigationCoordinator;
  unifiedLinkNavigationHost: BrowserUnifiedLinkNavigationHost;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  addressDisplayCoordinator: BrowserAddressDisplayCoordinator;
  resolveLifecycleApplication: () => BrowserWebLoadLifecycleApplication;
}

const DEFAULT_APP_URL_OPEN_SOURCE: BrowserAppUrlOpenSource = 'app_ui';
const BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN: number = 0x0000;
const BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG: string = 'HomeSearchDiag';

function stringifyBrowserAppUrlOpenError(error: Error): string {
  if (error.message !== undefined && error.message.length > 0) {
    return error.message;
  }
  try {
    const serialized = JSON.stringify(error);
    return serialized.length > 0 ? serialized : '未知错误';
  } catch (_stringifyError) {
    return '未知错误';
  }
}

export class BrowserAppUrlOpenCoordinator {
  private readonly host: BrowserAppUrlOpenHost;
  private readonly dependencies: BrowserAppUrlOpenDependencies;
  private transitionService: BrowserNavigationTransitionService = new BrowserNavigationTransitionService();
  private transitionCoordinator: BrowserTabTransitionCoordinator = new BrowserTabTransitionCoordinator();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  constructor(host: BrowserAppUrlOpenHost, dependencies: BrowserAppUrlOpenDependencies) {
    this.host = host;
    this.dependencies = dependencies;
  }

  open(request: BrowserAppUrlOpenRequest): void {
    const plan = this.buildPlan(request);
    this.executePlan(plan);
  }

  private executePlan(plan: BrowserAppUrlOpenPlan): void {
    switch (plan.action) {
      case 'open_current_tab':
        this.openCurrentTab(plan);
        return;
      case 'open_new_tab':
        this.openForegroundTab(plan);
        return;
      case 'open_background_tab':
        this.openBackgroundTab(plan);
        return;
      case 'reject':
      default:
        this.host.applyMessage('toast', plan.message);
        return;
    }
  }

  openCurrentAppUi(
    url: string,
    helperMessage: string,
    createOptions: BrowserCreateTabOptions,
    title: string = resolveBrowserNewWindowTestTitle(url, url),
    browserGeneratedHttpFallbackUrl: string = ''
  ): void {
    this.open({
      url: url,
      title: title,
      intent: 'current_tab',
      source: 'app_ui',
      helperMessage: helperMessage,
      profileId: createOptions.profileId,
      privacyMode: createOptions.privacyMode,
      dataScope: createOptions.dataScope,
      createOptions: createOptions,
      openerTabId: createOptions.openerTabId,
      browserGeneratedHttpFallbackUrl: browserGeneratedHttpFallbackUrl
    });
  }

  openHomeShortcut(plan: HomeShortcutWebOpenPlan): void {
    HomeShortcutIconAssociationUpdateCenter.registerLaunch(plan.launchContext);
    this.open({
      url: plan.url,
      title: plan.title,
      intent: plan.intent,
      source: plan.source,
      openerTabId: plan.openerTabId,
      launchContext: plan.launchContext
    });
  }

  openUserScriptRequestedTab(openerTabId: string, url: string, active: boolean): void {
    const targetUrl = url.trim();
    if (targetUrl.length === 0) {
      return;
    }
    const normalizedOpenerTabId = openerTabId.trim();
    const sourceTabId = normalizedOpenerTabId.length > 0
      ? normalizedOpenerTabId
      : this.host.resolveForegroundTabCreationState().activeTabId;
    if (!this.dependencies.webRuntimeBridge.canLoadInWebView(targetUrl)) {
      this.dependencies.unifiedLinkNavigationCoordinator.handleManualLoad(
        sourceTabId,
        targetUrl,
        true,
        true,
        this.dependencies.unifiedLinkNavigationHost
      );
      return;
    }
    this.open({
      url: targetUrl,
      title: targetUrl,
      intent: active ? 'new_tab' : 'background_tab',
      source: 'userscript_install',
      createOptions: this.dependencies.tabScopedEventContextCoordinator.buildCreateOptions(sourceTabId),
      openerTabId: sourceTabId
    });
  }

  private openCurrentTab(plan: BrowserAppUrlOpenPlan): void {
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] app_open_current source=%{public}s intent=%{public}s targetLength=%{public}d',
      plan.source,
      plan.intent,
      plan.url.length
    );
    const resolvedTitle = resolveBrowserNewWindowTestTitle(plan.url, plan.title);
    if (this.shouldCreateForegroundTabForCurrentRequest(plan)) {
      const state = this.host.resolveForegroundTabCreationState();
      const activeTab = state.tabs.find((tab: BrowserTabState): boolean => tab.id === state.activeTabId);
      hilog.info(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] app_open_foreground_create activeTab=%{public}s activeIsHome=%{public}s homeVisible=%{public}s',
        state.activeTabId,
        activeTab?.isHome === true ? 'true' : 'false',
        this.host.isHomeSurfaceVisible() ? 'true' : 'false'
      );
      this.openForegroundTabForMissingActiveTab(plan, resolvedTitle);
      return;
    }
    this.applyLaunchContext(plan);
    const state = this.host.resolveForegroundTabCreationState();
    this.host.applyAddressInput(
      this.dependencies.addressDisplayCoordinator.resolveCommittedDisplay(state.activeTabId, plan.url)
    );
    this.dependencies.recentActionManager.recordOperate(Date.now());
    this.registerBrowserGeneratedHttpsAttempt(state.activeTabId, plan);
    if (this.dependencies.offlineFastFailureCoordinator.applyIfNeeded(state.activeTabId, plan.url)) {
      this.host.applyMessage('error', this.host.getOpenErrorMessage());
      return;
    }
    this.dependencies.searchSuggestionCoordinator.reset();
    const openResult = this.dependencies.webLoadRuntimeCoordinator.buildOpenResolvedUrlApplicationResult(
      state.activeTabId,
      plan.url,
      plan.message,
      resolvedTitle
    );
    const loadResult = this.dependencies.webLoadRuntimeCoordinator.executeOpenResolvedUrl(openResult);
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] app_open_runtime_result status=%{public}s tab=%{public}s',
      loadResult.status,
      state.activeTabId
    );
    if (loadResult.status === 'failed') {
      this.host.applyMessage('error', loadResult.errorMessage);
    }
  }

  private openForegroundTab(plan: BrowserAppUrlOpenPlan): void {
    this.dependencies.recentActionManager.recordOperate(Date.now());
    this.executeForegroundTabCreation(
      plan,
      resolveBrowserNewWindowTestTitle(plan.url, plan.title)
    );
  }

  private openForegroundTabForMissingActiveTab(
    plan: BrowserAppUrlOpenPlan,
    resolvedTitle: string
  ): void {
    const options = this.resolveCreateOptions(plan);
    const request: BrowserForegroundTabCreationRequest = {
      initialUrl: plan.url,
      initialTitle: resolvedTitle,
      options: options,
      runtimeOptions: this.buildForegroundRuntimeOptions()
    };
    if (this.canCreateForegroundTabWithoutAsyncBoundary(options)) {
      const createdTabId = this.dependencies.foregroundTabCreationCoordinator.createNewTabNow(request);
      this.registerBrowserGeneratedHttpsAttempt(createdTabId, plan);
      this.primeExternalForegroundNavigation(createdTabId, plan);
    } else {
      this.executeForegroundTabCreationRequest(plan, request);
    }
    this.host.applyMessage('helper', plan.message);
  }

  private openBackgroundTab(plan: BrowserAppUrlOpenPlan): void {
    this.dependencies.recentActionManager.recordOperate(Date.now());
    this.host.persistActiveTabSnapshot(`app-url-open-${plan.source}-background-tab`);
    const state = this.host.resolveForegroundTabCreationState();
    const transition = this.transitionCoordinator.createBackgroundTab(
      this.dependencies.tabManager,
      state.tabs,
      state.activeTabId,
      state.tabSequence,
      plan.url,
      resolveBrowserNewWindowTestTitle(plan.url, plan.title),
      state.homeUrl,
      this.resolveCreateOptions(plan)
    );
    const createdTab = transition.tabs[transition.tabs.length - 1];
    this.registerBrowserGeneratedHttpsAttempt(createdTab.id, plan);
    this.host.applyTabCreationState({ tabs: transition.tabs });
    this.dependencies.tabSwitchCoordinator.synchronizeWebTabsAndPreviewAssets();
    this.host.applyTabCreationState({
      activeTabId: transition.activeTabId,
      tabSequence: transition.tabSequence,
      helperMessage: transition.helperMessage
    });
    this.dependencies.tabSessionPersistenceCoordinator.persist();
    this.dependencies.backgroundOpenPromptCoordinator.showForTab(createdTab);
    this.dependencies.backgroundTabPreviewRuntimeCoordinator.scheduleCandidate(
      createdTab.id,
      `app_url_open_${plan.source}`
    );
  }

  private executeForegroundTabCreation(
    plan: BrowserAppUrlOpenPlan,
    resolvedTitle: string
  ): void {
    const request: BrowserForegroundTabCreationRequest = {
      initialUrl: plan.url,
      initialTitle: resolvedTitle,
      options: this.resolveCreateOptions(plan),
      runtimeOptions: this.buildForegroundRuntimeOptions()
    };
    this.executeForegroundTabCreationRequest(plan, request);
  }

  private executeForegroundTabCreationRequest(
    plan: BrowserAppUrlOpenPlan,
    request: BrowserForegroundTabCreationRequest
  ): void {
    const startedAt = Date.now();
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] foreground_create_begin targetLength=%{public}d',
      plan.url.length
    );
    void this.dependencies.foregroundTabCreationCoordinator.createNewTab(request)
      .then((createdTabId: string): void => {
        this.registerBrowserGeneratedHttpsAttempt(createdTabId, plan);
        this.primeExternalForegroundNavigation(createdTabId, plan);
        hilog.info(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] foreground_create_end tab=%{public}s elapsedMs=%{public}d',
          createdTabId,
          Date.now() - startedAt
        );
      })
      .catch((error: Error): void => {
        hilog.error(
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
          BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
          '[DIAG-home-submit-20260828] foreground_create_error elapsedMs=%{public}d',
          Date.now() - startedAt
        );
        const errorMessage = stringifyBrowserAppUrlOpenError(error);
        this.host.applyMessage('error', `打开链接失败：${errorMessage}`);
      });
  }

  private primeExternalForegroundNavigation(createdTabId: string, plan: BrowserAppUrlOpenPlan): void {
    if (plan.source !== 'external_url' || createdTabId.length === 0) {
      return;
    }
    this.dependencies.resolveLifecycleApplication().primeNavigationVisualFeedback(
      createdTabId,
      plan.url
    );
  }

  private shouldCreateForegroundTabForCurrentRequest(plan: BrowserAppUrlOpenPlan): boolean {
    const state = this.host.resolveForegroundTabCreationState();
    const activeTab = state.tabs.find((tab: BrowserTabState) => tab.id === state.activeTabId);
    return activeTab === undefined || !this.isActiveTabSameBoundary(plan, activeTab) ||
      this.shouldPromoteHomeSurfaceRequest(plan, activeTab);
  }

  private shouldPromoteHomeSurfaceRequest(
    _plan: BrowserAppUrlOpenPlan,
    activeTab?: BrowserTabState
  ): boolean {
    if (!this.host.isHomeSurfaceVisible()) {
      return false;
    }
    const resolvedActiveTab = activeTab ?? this.resolveActiveTab();
    return resolvedActiveTab === undefined || !resolvedActiveTab.isHome;
  }

  private isActiveTabSameBoundary(plan: BrowserAppUrlOpenPlan, activeTab: BrowserTabState): boolean {
    if (plan.profileId === undefined && plan.privacyMode === undefined && plan.dataScope === undefined) {
      return true;
    }
    const sourceBoundary = this.profileBoundaryService.buildBoundaryInput(
      activeTab.profileId,
      activeTab.privacyMode,
      activeTab.dataScope
    );
    const target = this.profileBoundaryService.buildBoundary({
      profileId: plan.profileId,
      privacyMode: plan.privacyMode,
      dataScope: plan.dataScope
    });
    const targetBoundary = this.profileBoundaryService.buildBoundaryInput(
      target.profileId,
      target.privacyMode,
      target.dataScope
    );
    return this.profileBoundaryService.requireSameProfile(
      sourceBoundary,
      targetBoundary,
      'app_url_open_current_tab'
    ).allowed;
  }

  private resolveActiveTab(): BrowserTabState | undefined {
    const state = this.host.resolveForegroundTabCreationState();
    return state.tabs.find((tab: BrowserTabState) => tab.id === state.activeTabId);
  }

  private applyLaunchContext(plan: BrowserAppUrlOpenPlan): void {
    if (plan.launchContext === undefined) {
      return;
    }
    const state = this.host.resolveForegroundTabCreationState();
    if (state.activeTabId.length === 0) {
      return;
    }
    this.host.applyTabCreationState({
      tabs: this.dependencies.tabManager.updateActiveTab(state.tabs, state.activeTabId, {
        launchContext: plan.launchContext
      })
    });
    this.dependencies.tabSessionPersistenceCoordinator.persist();
  }

  private resolveCreateOptions(plan: BrowserAppUrlOpenPlan): BrowserCreateTabOptions {
    const state = this.host.resolveForegroundTabCreationState();
    const fallbackTabId = state.activeTabId;
    const openerTabId = plan.openerTabId.length > 0 ? plan.openerTabId : fallbackTabId;
    const fallbackOptions = plan.createOptions !== undefined
      ? plan.createOptions
      : this.resolveFallbackCreateOptions(openerTabId);
    const sourceLinkedOptions = this.resolveSourceLinkedCreateOptions(plan, openerTabId, fallbackOptions);
    const launchContext = plan.launchContext ?? fallbackOptions.launchContext;
    if (plan.profileId === undefined && plan.privacyMode === undefined && plan.dataScope === undefined) {
      if (plan.launchContext === undefined) {
        return sourceLinkedOptions;
      }
      return this.copyCreateOptions(sourceLinkedOptions, launchContext);
    }
    const boundary = this.profileBoundaryService.buildBoundary({
      profileId: plan.profileId ?? sourceLinkedOptions.profileId,
      privacyMode: plan.privacyMode ?? sourceLinkedOptions.privacyMode,
      dataScope: plan.dataScope ?? sourceLinkedOptions.dataScope
    });
    return {
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope,
      launchContext: launchContext,
      openerTabId: sourceLinkedOptions.openerTabId,
      openSource: sourceLinkedOptions.openSource,
      openedByNewWindow: sourceLinkedOptions.openedByNewWindow,
      insertAfterTabId: sourceLinkedOptions.insertAfterTabId
    };
  }

  private resolveSourceLinkedCreateOptions(
    plan: BrowserAppUrlOpenPlan,
    openerTabId: string,
    options: BrowserCreateTabOptions
  ): BrowserCreateTabOptions {
    if (plan.source === 'web_context_menu' && openerTabId.length > 0) {
      return {
        profileId: options.profileId,
        privacyMode: options.privacyMode,
        dataScope: options.dataScope,
        launchContext: options.launchContext,
        openerTabId: openerTabId,
        openSource: 'web_context_menu',
        openedByNewWindow: false,
        insertAfterTabId: options.insertAfterTabId
      };
    }
    return options;
  }

  private copyCreateOptions(
    options: BrowserCreateTabOptions,
    launchContext: TabLaunchContext | undefined
  ): BrowserCreateTabOptions {
    return {
      profileId: options.profileId,
      privacyMode: options.privacyMode,
      dataScope: options.dataScope,
      launchContext: launchContext,
      openerTabId: options.openerTabId,
      openSource: options.openSource,
      openedByNewWindow: options.openedByNewWindow,
      insertAfterTabId: options.insertAfterTabId
    };
  }

  private resolveFallbackCreateOptions(openerTabId: string): BrowserCreateTabOptions {
    const openerOptions = this.dependencies.tabScopedEventContextCoordinator.buildCreateOptions(openerTabId);
    if (!this.host.isHomeSurfaceVisible()) {
      return openerOptions;
    }
    const homeOptions = this.dependencies.tabScopedEventContextCoordinator.buildCreateOptions('');
    return {
      profileId: homeOptions.profileId,
      privacyMode: homeOptions.privacyMode,
      dataScope: homeOptions.dataScope,
      launchContext: openerOptions.launchContext,
      openerTabId: openerOptions.openerTabId,
      openSource: openerOptions.openSource,
      openedByNewWindow: openerOptions.openedByNewWindow,
      insertAfterTabId: openerOptions.insertAfterTabId
    };
  }

  private canCreateForegroundTabWithoutAsyncBoundary(options: BrowserCreateTabOptions): boolean {
    const privacyMode = normalizeBrowserSessionPrivacyMode(options.privacyMode);
    return privacyMode === 'regular' &&
      normalizeBrowserDataScope(options.dataScope, privacyMode) === 'profile_persistent';
  }

  private buildForegroundRuntimeOptions(): CreateNewTabRuntimeOptions {
    return {
      skipCurrentTabPreviewForForegroundOpen: true
    };
  }

  private buildPlan(request: BrowserAppUrlOpenRequest): BrowserAppUrlOpenPlan {
    const url = request.url.trim();
    const source = this.normalizeSource(request.source);
    const intent = this.normalizeIntent(request.intent);
    const requestId = this.normalizeRequestId(request.requestId, source);
    const transitionResolution = this.transitionService.resolve(source, intent);
    const boundary = this.normalizeBoundary(request);
    if (url.length === 0) {
      return {
        action: 'reject',
        url: '',
        title: '',
        intent: intent,
        source: source,
        transition: transitionResolution.transition,
        scene: transitionResolution.scene,
        reason: transitionResolution.reason,
        profileId: boundary.profileId,
        privacyMode: boundary.privacyMode,
        dataScope: boundary.dataScope,
        launchContext: request.launchContext,
        createOptions: request.createOptions,
        openerTabId: '',
        requestId: requestId,
        message: '当前没有可打开的链接。',
        browserGeneratedHttpFallbackUrl: ''
      };
    }
    const openerTabId = request.openerTabId?.trim() ?? request.createOptions?.openerTabId?.trim() ?? '';
    return {
      action: this.resolveAction(intent),
      url: url,
      title: this.normalizeTitle(request.title, url),
      intent: intent,
      source: source,
      transition: transitionResolution.transition,
      scene: transitionResolution.scene,
      reason: transitionResolution.reason,
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope,
      launchContext: request.launchContext,
      createOptions: request.createOptions,
      openerTabId: openerTabId,
      requestId: requestId,
      message: this.resolveMessage(intent, request.helperMessage),
      browserGeneratedHttpFallbackUrl: request.browserGeneratedHttpFallbackUrl?.trim() ?? ''
    };
  }

  private registerBrowserGeneratedHttpsAttempt(tabId: string, plan: BrowserAppUrlOpenPlan): void {
    if (tabId.length === 0) {
      return;
    }
    sharedBrowserHttpsFirstNavigationService.prepareProgrammaticNavigation(
      tabId,
      plan.url,
      plan.browserGeneratedHttpFallbackUrl,
      {
        profileId: plan.profileId,
        privacyMode: plan.privacyMode,
        dataScope: plan.dataScope
      },
      (fallbackTabId: string, fallbackUrl: string): boolean =>
        this.dependencies.webLoadRuntimeCoordinator.loadUrlForTab(fallbackTabId, fallbackUrl, true)
    );
  }

  private normalizeIntent(intent: BrowserAppUrlOpenIntent | undefined): BrowserAppUrlOpenIntent {
    if (intent === 'new_tab' || intent === 'background_tab') {
      return intent;
    }
    return 'current_tab';
  }

  private normalizeSource(source: BrowserAppUrlOpenSource | undefined): BrowserAppUrlOpenSource {
    return source ?? DEFAULT_APP_URL_OPEN_SOURCE;
  }

  private normalizeTitle(title: string | undefined, url: string): string {
    const normalizedTitle = title?.trim() ?? '';
    return normalizedTitle.length > 0 ? normalizedTitle : url;
  }

  private normalizeRequestId(requestId: string | undefined, source: BrowserAppUrlOpenSource): string {
    const normalizedRequestId = requestId?.trim() ?? '';
    return normalizedRequestId.length > 0 ? normalizedRequestId : `native-open-${source}-${Date.now()}`;
  }

  private normalizeBoundary(request: BrowserAppUrlOpenRequest): BrowserAppUrlOpenBoundary {
    const hasBoundary = request.profileId !== undefined ||
      request.privacyMode !== undefined ||
      request.dataScope !== undefined;
    if (!hasBoundary) {
      return {};
    }
    const boundary = this.profileBoundaryService.buildBoundary({
      profileId: request.profileId,
      privacyMode: request.privacyMode,
      dataScope: request.dataScope
    });
    return {
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope
    };
  }

  private resolveAction(intent: BrowserAppUrlOpenIntent): BrowserAppUrlOpenAction {
    if (intent === 'new_tab') {
      return 'open_new_tab';
    }
    if (intent === 'background_tab') {
      return 'open_background_tab';
    }
    return 'open_current_tab';
  }

  private resolveMessage(intent: BrowserAppUrlOpenIntent, helperMessage?: string): string {
    const normalizedHelperMessage = helperMessage?.trim() ?? '';
    if (normalizedHelperMessage.length > 0) {
      return normalizedHelperMessage;
    }
    if (intent === 'new_tab') {
      return '已在新标签页中打开链接。';
    }
    if (intent === 'background_tab') {
      return '已在后台打开链接。';
    }
    return '正在打开链接。';
  }
}
