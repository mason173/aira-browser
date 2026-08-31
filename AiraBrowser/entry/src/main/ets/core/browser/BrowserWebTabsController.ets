import { webview } from '@kit.ArkWeb';
import {
  BrowserWebComponentController,
  BrowserWebComponentLinkRequest,
  BrowserWebComponentNavigationEventSource,
  BrowserWebComponentWebUrlDecision,
  BrowserWebComponentWebStateRestoreResult,
  BrowserWebDialogKind,
  BrowserWebHistoryDirection
} from '../web/BrowserWebComponentController';
import { BrowserUnifiedLinkResult } from '../../services/web/BrowserUnifiedLinkLogic';
import {
  BrowserWebNavigationCommandResult,
  BrowserWebPageController,
  BrowserWebPageControllerHost,
  BrowserWebPageStateSnapshot,
  BrowserWindowNewEventConsumptionResult,
  buildEmptyBrowserWindowNewEventConsumptionResult,
  buildUnavailableBrowserWebNavigationCommandResult
} from '../web/BrowserWebPageController';
import {
  BrowserMaterializationOptions,
  BrowserMaterializationPolicy,
  DEFAULT_BROWSER_MATERIALIZATION_POLICY
} from './BrowserMaterializationPolicy';
import { BrowserWebDialogQueueKind } from './BrowserWebDialogQueue';
import { BrowserWindowOpenApplicationCoordinator } from './BrowserWindowOpenApplicationCoordinator';

export interface BrowserWebTabsControllerTabSnapshot {
  id: string;
  url: string;
  pendingUrl: string;
  isHome: boolean;
}

export interface BrowserWebActiveTabChange {
  previousTabId: string;
  activeTabId: string;
  activeUrl: string;
}

export interface BrowserWebTabsControllerDependencies {
  resolveWebController: (tabId: string) => webview.WebviewController | undefined;
  isWebControllerAttached: (tabId: string) => boolean;
  isNormalRuntimeAttached: (tabId: string) => boolean;
  isHostedWebNodeAttached: (tabId: string) => boolean;
  isArkWebControllerAttached: (tabId: string) => boolean;
  resolveWebId: (tabId: string) => number;
  handleJavaScriptDialogBack: (tabId: string, kind: BrowserWebDialogQueueKind) => boolean;
  handleHttpAuthDialogBack: (tabId: string) => boolean;
  handleSslErrorDialogBack: (tabId: string) => boolean;
  handleSpecialNavigationAction: (
    tabId: string,
    url: string,
    source: BrowserWebComponentNavigationEventSource,
    isMainFrame: boolean
  ) => BrowserWebComponentWebUrlDecision;
  canLoadUrlInWebView: (url: string) => boolean;
  handleWebAppScopeOutNavigation: (tabId: string, url: string, isMainFrame: boolean) => boolean;
  resolveMainFrameWebUrlDecision: (
    tabId: string,
    url: string,
    request: WebResourceRequest | undefined,
    source: BrowserWebComponentNavigationEventSource
  ) => BrowserWebComponentWebUrlDecision;
  executeSameWebNavigationRewrite: (tabId: string, url: string, reason: string) => boolean;
  prepareMainFrameWebNavigation: (tabId: string, url: string, startsNewTransaction: boolean) => boolean;
  observeMainFrameWebRequest: (tabId: string, url: string) => void;
  evaluateUnifiedLinkNavigation: (request: BrowserWebComponentLinkRequest) => BrowserUnifiedLinkResult;
  applyUnifiedLinkNavigationResult: (result: BrowserUnifiedLinkResult) => void;
  applyWebPageCommittedUrlRestore: (tabId: string, url: string) => void;
  applyWebHistoryTargetUrlPreview: (
    tabId: string,
    direction: BrowserWebHistoryDirection,
    targetUrl: string
  ) => void;
  beginHistoryReturnQuietWindow: (tabId: string, direction: BrowserWebHistoryDirection) => void;
  prepareHistoryNavigation: (
    tabId: string,
    direction: BrowserWebHistoryDirection,
    targetUrl: string,
    targetHistoryIndex: number
  ) => boolean;
  cancelPreparedNavigation: (tabId: string) => void;
  syncWebNavigationStateSoon: () => void;
  handleWebpageTranslationRefreshOrHistory: (tabId: string, url: string) => void;
  handleActiveTabChanged: (change: BrowserWebActiveTabChange) => void;
}

export interface BrowserWebTabsControllerHost {
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
  applyWebPageNavigationState: (tabId: string, canGoBackward: boolean, canGoForward: boolean) => void;
  applyWebNavigationHelperMessage: (message: string) => void;
  applyWebNavigationErrorMessage: (message: string) => void;
  clearWebNavigationErrorMessage: () => void;
  resolveActiveWebTabId: () => string;
  resolveWebTabSnapshot: (tabId: string) => BrowserWebTabsControllerTabSnapshot | undefined;
  isWebSurfaceVisible: () => boolean;
}

export class BrowserWebTabsController {
  private readonly dependencies: BrowserWebTabsControllerDependencies;
  private readonly host: BrowserWebTabsControllerHost;
  private readonly windowOpenApplicationCoordinator: BrowserWindowOpenApplicationCoordinator;
  private pagesByTabId: Record<string, BrowserWebPageController | undefined> = {};
  private preBuildWindowNewEventConsumptionByTabId:
    Record<string, BrowserWindowNewEventConsumptionResult | undefined> = {};
  private orderedTabIds: string[] = [];
  private activeTabIdState: string = '';
  constructor(
    dependencies: BrowserWebTabsControllerDependencies,
    host: BrowserWebTabsControllerHost,
    windowOpenApplicationCoordinator: BrowserWindowOpenApplicationCoordinator
  ) {
    this.dependencies = dependencies;
    this.host = host;
    this.windowOpenApplicationCoordinator = windowOpenApplicationCoordinator;
  }

  syncTabs(
    tabs: BrowserWebTabsControllerTabSnapshot[],
    activeTabId: string,
    options: BrowserMaterializationOptions = {}
  ): void {
    const host = this.host;
    const pageHost = this.buildPageControllerHost();
    const materializationPolicy = options.materializationPolicy ?? DEFAULT_BROWSER_MATERIALIZATION_POLICY;
    const normalizedActiveTabId = activeTabId.trim();
    const retainedTabIds: Record<string, boolean> = {};
    const nextOrderedTabIds: string[] = [];
    let deferredPageCreationCount = 0;
    let firstDeferredTabId = '';
    tabs.forEach((tab: BrowserWebTabsControllerTabSnapshot) => {
      const normalizedTabId = tab.id.trim();
      if (normalizedTabId.length <= 0 || tab.isHome) {
        return;
      }
      retainedTabIds[normalizedTabId] = true;
      nextOrderedTabIds.push(normalizedTabId);
      const page = this.resolvePageForSnapshot(
        tab,
        this.shouldCreatePageForSnapshot(normalizedTabId, normalizedActiveTabId, materializationPolicy),
        materializationPolicy
      );
      if (page === undefined) {
        deferredPageCreationCount += 1;
        if (firstDeferredTabId.length <= 0) {
          firstDeferredTabId = normalizedTabId;
        }
        return;
      }
      page?.hydrateFromTab(tab.url, tab.pendingUrl);
      page?.syncRuntimeOwnership(pageHost, 'sync_tabs');
    });
    if (deferredPageCreationCount > 0) {
      host.recordRuntimeEvent(
        'web_tabs_page_creation_deferred',
        `policy=${materializationPolicy} deferred=${deferredPageCreationCount}`,
        firstDeferredTabId.length > 0 ? firstDeferredTabId : normalizedActiveTabId
      );
    }

    Object.keys(this.pagesByTabId).forEach((tabId: string) => {
      if (retainedTabIds[tabId] === true) {
        return;
      }
      const page = this.pagesByTabId[tabId];
      page?.onInactive(pageHost);
      this.pagesByTabId[tabId] = undefined;
      this.preBuildWindowNewEventConsumptionByTabId[tabId] = undefined;
      host.recordRuntimeEvent('web_tabs_page_pruned', `tab=${tabId}`, tabId);
    });

    const previousOrder = this.orderedTabIds.join(',');
    this.orderedTabIds = nextOrderedTabIds;
    const nextOrder = this.orderedTabIds.join(',');
    if (previousOrder !== nextOrder) {
      host.recordRuntimeEvent('web_tabs_page_reordered', `order=${nextOrder}`, activeTabId);
    }

    const previousActiveTabId = this.activeTabIdState;
    this.activeTabIdState = normalizedActiveTabId;
    this.orderedTabIds.forEach((tabId: string) => {
      const page = this.pagesByTabId[tabId];
      if (page === undefined) {
        return;
      }
      if (tabId === normalizedActiveTabId) {
        page.onActive(pageHost);
      } else {
        page.onInactive(pageHost);
      }
    });
    if (previousActiveTabId !== normalizedActiveTabId) {
      host.recordRuntimeEvent(
        'web_tabs_active_changed',
        `from=${previousActiveTabId} to=${normalizedActiveTabId}`,
        normalizedActiveTabId
      );
      this.dependencies.handleActiveTabChanged({
        previousTabId: previousActiveTabId,
        activeTabId: normalizedActiveTabId,
        activeUrl: this.resolveActiveTabUrl(normalizedActiveTabId)
      });
    }
  }

  goBackward(): BrowserWebNavigationCommandResult {
    return this.goActivePageBackward();
  }

  goForward(): BrowserWebNavigationCommandResult {
    return this.goActivePageForward();
  }

  goActivePageBackward(): BrowserWebNavigationCommandResult {
    return this.navigateActivePageHistory('back');
  }

  goActivePageForward(): BrowserWebNavigationCommandResult {
    return this.navigateActivePageHistory('forward');
  }

  private navigateActivePageHistory(direction: 'back' | 'forward'): BrowserWebNavigationCommandResult {
    const host = this.host;
    const page = this.resolveActivePage();
    if (page === undefined) {
      const unavailableResult = buildUnavailableBrowserWebNavigationCommandResult('missing_tab');
      host.recordRuntimeEvent(
        'web_tabs_active_history_command',
        `direction=${direction} status=${unavailableResult.status} reason=${unavailableResult.reason}`,
        host.resolveActiveWebTabId()
      );
      return unavailableResult;
    }
    const pageHost = this.buildPageControllerHost();
    const result = direction === 'back' ? page.goBackward(pageHost) : page.goForward(pageHost);
    this.dependencies.handleWebpageTranslationRefreshOrHistory(host.resolveActiveWebTabId(), result.targetUrl);
    host.recordRuntimeEvent(
      'web_tabs_active_history_command',
      `direction=${direction} status=${result.status} reason=${result.reason} target=${result.targetUrl}`,
      host.resolveActiveWebTabId()
    );
    return result;
  }

  stopLoading(tabId: string): BrowserWebNavigationCommandResult {
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      return buildUnavailableBrowserWebNavigationCommandResult('missing_tab');
    }
    return page.stopLoading(this.buildPageControllerHost());
  }

  /**
   * Mutes/unmutes a tab's web runtime via ArkWeb's per-Webview audio control.
   * Silently no-ops when the controller is not yet materialized; the caller
   * keeps the desired mute flag on the tab so it can be re-applied on attach.
   */
  setTabAudioMuted(tabId: string, muted: boolean): void {
    const controller = this.dependencies.resolveWebController(tabId);
    if (controller === undefined) {
      return;
    }
    try {
      controller.setAudioMuted(muted);
    } catch (error) {
      this.host.recordRuntimeEvent('web_audio_mute_failed', `${error}`, tabId);
    }
  }

  refreshActiveNavigationState(): BrowserWebPageStateSnapshot | undefined {
    const page = this.resolveActivePage();
    if (page === undefined) {
      return undefined;
    }
    return page.refreshNavigationState(this.buildPageControllerHost());
  }

  resolveHistoryTargetIntentUrl(tabId: string): string {
    return this.resolvePage(tabId)?.resolveHistoryTargetIntentUrl() ?? '';
  }

  refreshNavigationState(tabId: string): BrowserWebPageStateSnapshot | undefined {
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      return undefined;
    }
    return page.refreshNavigationState(this.buildPageControllerHost());
  }

  onPageBegin(tabId: string, url: string): void {
    const host = this.host;
    host.recordRuntimeEvent('navigation_event_received', `source=page_begin url=${url}`, tabId);
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      host.recordRuntimeEvent('navigation_event_missing_page', `source=page_begin url=${url}`, tabId);
      return;
    }
    page.onPageBegin(url, this.buildPageControllerHost());
  }

  onNavigationEntryCommitted(
    tabId: string,
    url: string,
    isMainFrame: boolean
  ): void {
    const host = this.host;
    host.recordRuntimeEvent(
      'navigation_event_received',
      `source=navigation_entry_committed mainFrame=${isMainFrame} url=${url}`,
      tabId
    );
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      host.recordRuntimeEvent(
        'navigation_event_missing_page',
        `source=navigation_entry_committed mainFrame=${isMainFrame} url=${url}`,
        tabId
      );
      return;
    }
    page.onNavigationEntryCommitted(url, isMainFrame, this.buildPageControllerHost());
  }

  onPageEnd(tabId: string, url: string): void {
    const host = this.host;
    host.recordRuntimeEvent('navigation_event_received', `source=page_end url=${url}`, tabId);
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      host.recordRuntimeEvent('navigation_event_missing_page', `source=page_end url=${url}`, tabId);
      return;
    }
    page.onPageEnd(url, this.buildPageControllerHost());
  }

  onLoadFinished(tabId: string): void {
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      return;
    }
    page.onLoadFinished(this.buildPageControllerHost());
  }

  onProgressChange(tabId: string, progress: number): void {
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      return;
    }
    page.onProgressChange(progress, this.buildPageControllerHost());
  }

  onControllerAttached(tabId: string): BrowserWindowNewEventConsumptionResult {
    const preBuildConsumption = this.preBuildWindowNewEventConsumptionByTabId[tabId];
    this.preBuildWindowNewEventConsumptionByTabId[tabId] = undefined;
    const attachedConsumption = this.consumeStoredWindowNewEventForPage(
      tabId,
      'controller_attached',
      'web_tabs_controller_attached_missing_page'
    );
    return preBuildConsumption?.eventFound === true ? preBuildConsumption : attachedConsumption;
  }

  onBeforeWebBuild(tabId: string): void {
    if (!this.windowOpenApplicationCoordinator.hasStoredEventForPageController(tabId)) {
      return;
    }
    const eventConsumption = this.consumeStoredWindowNewEventForPage(
      tabId,
      'before_hosted_web_build',
      'web_tabs_window_event_missing_page'
    );
    this.preBuildWindowNewEventConsumptionByTabId[tabId] = eventConsumption;
    this.host.recordRuntimeEvent(
      'window_open_pre_build_handoff_completed',
      `completed=${eventConsumption.completed} completion=${eventConsumption.completionKind}`,
      tabId
    );
  }

  private consumeStoredWindowNewEventForPage(
    tabId: string,
    reason: string,
    missingPageEventType: string
  ): BrowserWindowNewEventConsumptionResult {
    const host = this.host;
    const page = this.resolvePage(tabId) ?? this.ensurePageForControllerAttachment(tabId);
    if (page === undefined) {
      host.recordRuntimeEvent(missingPageEventType, `tab=${tabId} reason=${reason}`, tabId);
      return buildEmptyBrowserWindowNewEventConsumptionResult();
    }
    const pageHost = this.buildPageControllerHost();
    page.syncRuntimeOwnership(pageHost, reason);
    return page.consumeStoredWindowNewEvent(pageHost, reason);
  }

  onOverrideUrlLoading(
    tabId: string,
    request: WebResourceRequest
  ): boolean {
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      return false;
    }
    return page.onOverrideUrlLoading(request, this.buildPageControllerHost());
  }

  onLoadIntercept(
    tabId: string,
    event: OnLoadInterceptEvent
  ): boolean {
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      return false;
    }
    return page.onLoadIntercept(event, this.buildPageControllerHost());
  }

  serializeWebState(tabId: string): Uint8Array | undefined {
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      return undefined;
    }
    return page.serializeWebState(this.buildPageControllerHost());
  }

  restoreWebState(
    tabId: string,
    payload: Uint8Array | undefined
  ): BrowserWebComponentWebStateRestoreResult {
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      return {
        restored: false,
        reason: 'missing_controller',
        errorMessage: ''
      };
    }
    return page.restoreWebState(payload, this.buildPageControllerHost());
  }

  setDialogVisible(
    tabId: string,
    kind: BrowserWebDialogKind,
    visible: boolean
  ): void {
    const page = this.resolvePage(tabId);
    if (page === undefined) {
      return;
    }
    page.getComponentController().setDialogVisible(kind, visible);
    page.refreshNavigationState(this.buildPageControllerHost());
  }

  clearTab(tabId: string): void {
    this.pagesByTabId[tabId] = undefined;
    this.preBuildWindowNewEventConsumptionByTabId[tabId] = undefined;
    this.orderedTabIds = this.orderedTabIds.filter((item: string) => item !== tabId);
  }

  pruneTabs(tabIds: string[]): void {
    const retained: Record<string, BrowserWebPageController | undefined> = {};
    const retainedIds: Record<string, boolean> = {};
    tabIds.forEach((tabId: string) => {
      retainedIds[tabId] = true;
      const page = this.pagesByTabId[tabId];
      if (page !== undefined) {
        retained[tabId] = page;
      }
    });
    this.pagesByTabId = retained;
    Object.keys(this.preBuildWindowNewEventConsumptionByTabId).forEach((tabId: string) => {
      if (retainedIds[tabId] !== true) {
        this.preBuildWindowNewEventConsumptionByTabId[tabId] = undefined;
      }
    });
    this.orderedTabIds = this.orderedTabIds.filter((tabId: string) => retainedIds[tabId] === true);
  }

  private buildPageControllerHost(): BrowserWebPageControllerHost {
    const host = this.host;
    return {
      resolveWebController: this.dependencies.resolveWebController,
      isWebControllerAttached: this.dependencies.isWebControllerAttached,
      isNormalRuntimeAttached: this.dependencies.isNormalRuntimeAttached,
      isHostedWebNodeAttached: this.dependencies.isHostedWebNodeAttached,
      isArkWebControllerAttached: this.dependencies.isArkWebControllerAttached,
      resolveWebId: this.dependencies.resolveWebId,
      takeWindowNewEventForPageController: (tabId: string): OnWindowNewEvent | undefined =>
        this.windowOpenApplicationCoordinator.takeStoredEventForPageController(tabId),
      handleWebDialogBack: (tabId: string, kind: BrowserWebDialogKind): boolean =>
        this.handleWebDialogBack(tabId, kind),
      recordRuntimeEvent: host.recordRuntimeEvent,
      handleSpecialNavigationAction: this.dependencies.handleSpecialNavigationAction,
      canLoadUrlInWebView: this.dependencies.canLoadUrlInWebView,
      handleWebAppScopeOutNavigation: this.dependencies.handleWebAppScopeOutNavigation,
      resolveMainFrameWebUrlDecision: this.dependencies.resolveMainFrameWebUrlDecision,
      executeSameWebNavigationRewrite: this.dependencies.executeSameWebNavigationRewrite,
      prepareMainFrameWebNavigation: this.dependencies.prepareMainFrameWebNavigation,
      observeMainFrameWebRequest: this.dependencies.observeMainFrameWebRequest,
      evaluateUnifiedLinkNavigation: this.dependencies.evaluateUnifiedLinkNavigation,
      applyUnifiedLinkNavigationResult: this.dependencies.applyUnifiedLinkNavigationResult,
      applyWebPageNavigationState: host.applyWebPageNavigationState,
      applyWebPageCommittedUrlRestore: this.dependencies.applyWebPageCommittedUrlRestore,
      applyWebHistoryTargetUrlPreview: this.dependencies.applyWebHistoryTargetUrlPreview,
      applyWebNavigationHelperMessage: host.applyWebNavigationHelperMessage,
      applyWebNavigationErrorMessage: host.applyWebNavigationErrorMessage,
      clearWebNavigationErrorMessage: host.clearWebNavigationErrorMessage,
      beginHistoryReturnQuietWindow: this.dependencies.beginHistoryReturnQuietWindow,
      prepareHistoryNavigation: this.dependencies.prepareHistoryNavigation,
      cancelPreparedNavigation: this.dependencies.cancelPreparedNavigation,
      syncWebNavigationStateSoon: this.dependencies.syncWebNavigationStateSoon
    };
  }

  private resolveActivePage(): BrowserWebPageController | undefined {
    return this.resolvePage(this.host.resolveActiveWebTabId());
  }

  private handleWebDialogBack(tabId: string, kind: BrowserWebDialogKind): boolean {
    if (tabId !== this.host.resolveActiveWebTabId()) {
      return false;
    }
    if (kind === 'prompt' || kind === 'confirm' || kind === 'alert') {
      return this.dependencies.handleJavaScriptDialogBack(tabId, kind);
    }
    if (kind === 'http_auth') {
      return this.dependencies.handleHttpAuthDialogBack(tabId);
    }
    return this.dependencies.handleSslErrorDialogBack(tabId);
  }

  private resolveActiveTabUrl(tabId: string): string {
    return this.resolveTabTargetUrl(tabId);
  }

  private resolveTabTargetUrl(tabId: string): string {
    const tab = this.host.resolveWebTabSnapshot(tabId);
    if (tab === undefined) {
      return '';
    }
    const pendingUrl = tab.pendingUrl.trim();
    return pendingUrl.length > 0 ? pendingUrl : tab.url.trim();
  }

  private resolvePage(tabId: string): BrowserWebPageController | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return undefined;
    }
    const tab = this.host.resolveWebTabSnapshot(normalizedTabId);
    if (tab === undefined || tab.isHome) {
      return undefined;
    }
    const page = this.pagesByTabId[normalizedTabId];
    if (page === undefined) {
      return undefined;
    }
    page.setTabId(normalizedTabId);
    page.hydrateFromTab(tab.url, tab.pendingUrl);
    return page;
  }

  private ensurePageForControllerAttachment(tabId: string): BrowserWebPageController | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return undefined;
    }
    const tab = this.host.resolveWebTabSnapshot(normalizedTabId);
    if (tab === undefined || tab.isHome) {
      return undefined;
    }
    const page = this.resolvePageForSnapshot(tab, true, 'active_only');
    if (page === undefined) {
      return undefined;
    }
    page.hydrateFromTab(tab.url, tab.pendingUrl);
    this.host.recordRuntimeEvent(
      'web_tabs_controller_attached_page_reconciled',
      `tab=${normalizedTabId}`,
      normalizedTabId
    );
    return page;
  }

  private resolvePageForSnapshot(
    tab: BrowserWebTabsControllerTabSnapshot,
    allowCreate: boolean = true,
    materializationPolicy: BrowserMaterializationPolicy = DEFAULT_BROWSER_MATERIALIZATION_POLICY
  ): BrowserWebPageController | undefined {
    const normalizedTabId = tab.id.trim();
    if (normalizedTabId.length <= 0 || tab.isHome) {
      return undefined;
    }
    let page = this.pagesByTabId[normalizedTabId];
    if (page === undefined && !allowCreate) {
      return undefined;
    }
    if (page === undefined) {
      page = new BrowserWebPageController(
        normalizedTabId,
        new BrowserWebComponentController(normalizedTabId)
      );
      this.pagesByTabId[normalizedTabId] = page;
      this.host.recordRuntimeEvent(
        'web_tabs_page_created',
        `tab=${normalizedTabId} policy=${materializationPolicy}`,
        normalizedTabId
      );
    }
    page.setTabId(normalizedTabId);
    return page;
  }

  private shouldCreatePageForSnapshot(
    tabId: string,
    activeTabId: string,
    materializationPolicy: BrowserMaterializationPolicy
  ): boolean {
    if (materializationPolicy === 'all') {
      return true;
    }
    if (materializationPolicy === 'active_only') {
      return tabId === activeTabId;
    }
    return false;
  }
}
