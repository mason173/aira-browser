import {
  BrowserWebComponentCapabilities,
  BrowserWebComponentController,
  BrowserWebComponentControllerHost,
  BrowserWebComponentNavigationResult,
  BrowserWebComponentWebStateRestoreResult,
  BrowserWebHistoryDirection
} from './BrowserWebComponentController';

export type BrowserWebNavigationCommandStatus =
  'transient_consumed' |
  'native_issued' |
  'loading_cancelled' |
  'unavailable' |
  'failed';

export type BrowserWebNavigationCommandReason =
  'native_history' |
  'dialog_back' |
  'web_context_menu' |
  'page_find' |
  'web_fullscreen' |
  'loading_not_committed_cancelled' |
  'missing_tab' |
  'missing_controller' |
  'controller_detached' |
  'not_available' |
  'failed';

export interface BrowserWebNavigationCommandResult {
  status: BrowserWebNavigationCommandStatus;
  reason: BrowserWebNavigationCommandReason;
  targetUrl: string;
  errorMessage: string;
}

interface BrowserWebHistoryTargetIntent {
  direction: BrowserWebHistoryDirection;
  targetUrl: string;
  issuedAt: number;
  expiresAt: number;
  webId: number;
  runtimeGeneration: number;
  commandGeneration: number;
}

export interface BrowserWebPageStateSnapshot {
  canGoBackward: boolean;
  canGoForward: boolean;
  isLoading: boolean;
  isNavigationEntryCommitted: boolean;
  lastCommitEntryUrl: string;
  lastKnownUrl: string;
  pendingUrl: string;
}

export type BrowserWindowNewEventCompletionKind =
  'none' |
  'child_controller' |
  'null_controller' |
  'failed';

export interface BrowserWindowNewEventConsumptionResult {
  eventFound: boolean;
  completed: boolean;
  controllerAvailable: boolean;
  completionKind: BrowserWindowNewEventCompletionKind;
  shouldTreatAsWindowOpenHandoff: boolean;
  errorMessage: string;
}

export interface BrowserWebPageRuntimeOwnershipSnapshot {
  controllerObjectResolved: boolean;
  normalRuntimeAttached: boolean;
  hostedWebNodeAttached: boolean;
  arkWebControllerAttached: boolean;
  webIdValid: boolean;
  webId: number;
  activeOrVisible: boolean;
}

export interface BrowserWebPageControllerHost extends BrowserWebComponentControllerHost {
  isNormalRuntimeAttached: (tabId: string) => boolean;
  isHostedWebNodeAttached: (tabId: string) => boolean;
  isArkWebControllerAttached: (tabId: string) => boolean;
  resolveWebId: (tabId: string) => number;
  takeWindowNewEventForPageController: (tabId: string) => OnWindowNewEvent | undefined;
  applyWebPageNavigationState: (tabId: string, canGoBackward: boolean, canGoForward: boolean) => void;
  applyWebPageCommittedUrlRestore: (tabId: string, url: string) => void;
  applyWebHistoryTargetUrlPreview: (tabId: string, direction: BrowserWebHistoryDirection, targetUrl: string) => void;
  applyWebNavigationHelperMessage: (message: string) => void;
  applyWebNavigationErrorMessage: (message: string) => void;
  clearWebNavigationErrorMessage: () => void;
  beginHistoryReturnQuietWindow: (tabId: string, direction: BrowserWebHistoryDirection) => void;
  prepareHistoryNavigation: (
    tabId: string,
    direction: BrowserWebHistoryDirection,
    targetUrl: string,
    targetHistoryIndex: number
  ) => boolean;
  cancelPreparedNavigation: (tabId: string) => void;
  syncWebNavigationStateSoon: () => void;
}

const HISTORY_TARGET_INTENT_TTL_MS: number = 2500;

const EMPTY_COMMAND_RESULT: BrowserWebNavigationCommandResult = {
  status: 'unavailable',
  reason: 'not_available',
  targetUrl: '',
  errorMessage: ''
};

export function buildEmptyBrowserWindowNewEventConsumptionResult(): BrowserWindowNewEventConsumptionResult {
  return {
    eventFound: false,
    completed: false,
    controllerAvailable: false,
    completionKind: 'none',
    shouldTreatAsWindowOpenHandoff: false,
    errorMessage: ''
  };
}

export class BrowserWebPageController {
  private tabId: string;
  private componentController: BrowserWebComponentController;
  private canGoBackwardState: boolean = false;
  private canGoForwardState: boolean = false;
  private isLoadingState: boolean = false;
  private isNavigationEntryCommittedState: boolean = true;
  private lastCommitEntryUrl: string = '';
  private lastKnownUrl: string = '';
  private pendingUrl: string = '';
  private historyTargetIntent: BrowserWebHistoryTargetIntent | undefined = undefined;
  private historyTargetIntentTimerId: number = -1;
  private runtimeGeneration: number = 0;
  private historyCommandGeneration: number = 0;
  private isActiveState: boolean = false;
  private controllerObjectResolvedState: boolean = false;
  private normalRuntimeAttachedState: boolean = false;
  private hostedWebNodeAttachedState: boolean = false;
  private arkWebControllerAttachedState: boolean = false;
  private webIdValidState: boolean = false;
  private webIdState: number = -1;
  private activeOrVisibleState: boolean = false;
  private lastLoggedNavigationState: string = '';

  constructor(tabId: string, componentController: BrowserWebComponentController) {
    this.tabId = tabId;
    this.componentController = componentController;
  }

  setTabId(tabId: string): void {
    if (this.tabId === tabId) {
      return;
    }
    this.tabId = tabId;
    this.resetHistoryTargetIntent();
    this.runtimeGeneration += 1;
    this.componentController.setTabId(tabId);
  }

  hydrateFromTab(url: string, pendingUrl: string = ''): void {
    const normalizedUrl = url.trim();
    const normalizedPendingUrl = pendingUrl.trim();
    if (this.lastKnownUrl.length <= 0 && normalizedUrl.length > 0) {
      this.lastKnownUrl = normalizedUrl;
    }
    if (this.lastCommitEntryUrl.length <= 0 && normalizedUrl.length > 0) {
      this.lastCommitEntryUrl = normalizedUrl;
    }
    if (normalizedPendingUrl.length > 0) {
      this.pendingUrl = normalizedPendingUrl;
    }
  }

  onActive(host: BrowserWebPageControllerHost): void {
    if (this.isActiveState) {
      return;
    }
    this.isActiveState = true;
    host.recordRuntimeEvent('web_page_active', `tab=${this.tabId}`, this.tabId);
    this.syncRuntimeOwnership(host, 'active');
    this.refreshNavigationState(host);
  }

  onInactive(host: BrowserWebPageControllerHost): void {
    if (!this.isActiveState) {
      return;
    }
    this.isActiveState = false;
    this.clearHistoryTargetIntent(host, 'inactive');
    host.recordRuntimeEvent('web_page_inactive', `tab=${this.tabId}`, this.tabId);
    this.syncRuntimeOwnership(host, 'inactive');
  }

  syncRuntimeOwnership(
    host: BrowserWebPageControllerHost,
    source: string = 'sync'
  ): BrowserWebPageRuntimeOwnershipSnapshot {
    const controllerObjectResolved = host.resolveWebController(this.tabId) !== undefined;
    const normalRuntimeAttached = host.isNormalRuntimeAttached(this.tabId);
    const hostedWebNodeAttached = host.isHostedWebNodeAttached(this.tabId);
    const arkWebControllerAttached = host.isArkWebControllerAttached(this.tabId);
    const webId = host.resolveWebId(this.tabId);
    const webIdValid = webId > 0;
    const activeOrVisible = this.isActiveState;
    const attachmentStateChanged =
      this.controllerObjectResolvedState !== controllerObjectResolved ||
      this.normalRuntimeAttachedState !== normalRuntimeAttached ||
      this.hostedWebNodeAttachedState !== hostedWebNodeAttached ||
      this.arkWebControllerAttachedState !== arkWebControllerAttached;
    const activeStateChanged = this.activeOrVisibleState !== activeOrVisible;
    const attachStateChanged = attachmentStateChanged || activeStateChanged;
    const webIdChanged = this.webIdState !== webId || this.webIdValidState !== webIdValid;

    if (attachmentStateChanged || webIdChanged) {
      this.runtimeGeneration += 1;
      this.clearHistoryTargetIntent(host, webIdChanged ? 'web_id_changed' : 'controller_attachment_changed');
    }

    this.controllerObjectResolvedState = controllerObjectResolved;
    this.normalRuntimeAttachedState = normalRuntimeAttached;
    this.hostedWebNodeAttachedState = hostedWebNodeAttached;
    this.arkWebControllerAttachedState = arkWebControllerAttached;
    this.webIdState = webId;
    this.webIdValidState = webIdValid;
    this.activeOrVisibleState = activeOrVisible;

    if (attachStateChanged) {
      host.recordRuntimeEvent(
        'target_controller_attach_state',
        `source=${source} controller=${controllerObjectResolved} runtime=${normalRuntimeAttached} hosted=${hostedWebNodeAttached} ark=${arkWebControllerAttached} active=${activeOrVisible}`,
        this.tabId
      );
    }
    if (webIdChanged) {
      host.recordRuntimeEvent(
        'target_controller_web_id_valid',
        `source=${source} webId=${webId} valid=${webIdValid}`,
        this.tabId
      );
    }
    return this.buildRuntimeOwnershipSnapshot();
  }

  consumeStoredWindowNewEvent(
    host: BrowserWebPageControllerHost,
    reason: string
  ): BrowserWindowNewEventConsumptionResult {
    const event = host.takeWindowNewEventForPageController(this.tabId);
    if (event === undefined) {
      return buildEmptyBrowserWindowNewEventConsumptionResult();
    }
    const controller = host.resolveWebController(this.tabId);
    let completed = false;
    let completionKind: BrowserWindowNewEventCompletionKind = 'failed';
    let failureMessage = '';
    try {
      if (controller !== undefined) {
        event.handler.setWebController(controller);
        completionKind = 'child_controller';
      } else {
        event.handler.setWebController(null);
        completionKind = 'null_controller';
      }
      completed = true;
    } catch (error) {
      failureMessage = JSON.stringify(error);
      try {
        event.handler.setWebController(null);
        completionKind = 'null_controller';
        completed = true;
      } catch (_fallbackError) {
        completionKind = 'failed';
      }
    }
    const result: BrowserWindowNewEventConsumptionResult = {
      eventFound: true,
      completed: completed,
      controllerAvailable: controller !== undefined,
      completionKind: completionKind,
      shouldTreatAsWindowOpenHandoff: completed && completionKind === 'child_controller',
      errorMessage: failureMessage
    };
    host.recordRuntimeEvent(
      'window_open_event_consumed_by_page_controller',
      `targetTab=${this.tabId} reason=${reason} controller=${controller !== undefined} ` +
        `completed=${result.completed} completion=${result.completionKind} handoff=${result.shouldTreatAsWindowOpenHandoff} ` +
        `error=${result.errorMessage}`,
      this.tabId
    );
    this.syncRuntimeOwnership(host, 'window_new_event_consumed');
    return result;
  }

  onPageBegin(url: string, host: BrowserWebPageControllerHost): void {
    this.clearHistoryTargetIntent(host, 'page_begin');
    const normalizedUrl = url.trim();
    this.isLoadingState = true;
    this.isNavigationEntryCommittedState = false;
    this.pendingUrl = normalizedUrl;
    if (normalizedUrl.length > 0) {
      this.lastKnownUrl = normalizedUrl;
    }
    this.refreshNavigationState(host);
  }

  onNavigationEntryCommitted(url: string, isMainFrame: boolean, host: BrowserWebPageControllerHost): void {
    if (!isMainFrame) {
      return;
    }
    this.clearHistoryTargetIntent(host, 'navigation_entry_committed');
    const normalizedUrl = url.trim();
    this.isNavigationEntryCommittedState = true;
    if (normalizedUrl.length > 0) {
      this.lastCommitEntryUrl = normalizedUrl;
      this.lastKnownUrl = normalizedUrl;
      this.pendingUrl = normalizedUrl;
    }
    this.refreshNavigationState(host);
  }

  onPageEnd(url: string, host: BrowserWebPageControllerHost): void {
    const normalizedUrl = url.trim();
    this.isLoadingState = false;
    if (normalizedUrl.length > 0) {
      this.lastKnownUrl = normalizedUrl;
      if (this.lastCommitEntryUrl.length <= 0) {
        this.lastCommitEntryUrl = normalizedUrl;
      }
    }
    this.refreshNavigationState(host);
  }

  onLoadFinished(host: BrowserWebPageControllerHost): void {
    this.isLoadingState = false;
    this.refreshNavigationState(host);
  }

  onProgressChange(progress: number, host: BrowserWebPageControllerHost): void {
    if (progress >= 100) {
      this.isLoadingState = false;
      this.refreshNavigationState(host);
    }
  }

  onOverrideUrlLoading(request: WebResourceRequest, host: BrowserWebPageControllerHost): boolean {
    return this.componentController.onOverrideUrlLoading(request, host);
  }

  onLoadIntercept(event: OnLoadInterceptEvent, host: BrowserWebPageControllerHost): boolean {
    return this.componentController.onLoadIntercept(event, host);
  }

  serializeWebState(host: BrowserWebPageControllerHost): Uint8Array | undefined {
    return this.componentController.serializeWebState(host);
  }

  restoreWebState(
    payload: Uint8Array | undefined,
    host: BrowserWebPageControllerHost
  ): BrowserWebComponentWebStateRestoreResult {
    const result = this.componentController.restoreWebState(payload, host);
    if (result.restored) {
      this.isLoadingState = false;
      this.isNavigationEntryCommittedState = true;
      this.refreshNavigationState(host);
      host.syncWebNavigationStateSoon();
    }
    return result;
  }

  canGoBackward(host: BrowserWebPageControllerHost): boolean {
    this.refreshNavigationState(host);
    return this.canGoBackwardState;
  }

  canGoForward(host: BrowserWebPageControllerHost): boolean {
    this.refreshNavigationState(host);
    return this.canGoForwardState;
  }

  goBackward(host: BrowserWebPageControllerHost): BrowserWebNavigationCommandResult {
    this.refreshNavigationState(host);
    if (!this.canGoBackwardState) {
      return this.buildUnavailableResult('not_available');
    }
    if (this.componentController.hasBackDialog()) {
      return this.navigateCommittedHistory('back', host);
    }
    if (this.shouldCancelUncommittedLoading()) {
      this.componentController.stop(host);
      host.cancelPreparedNavigation(this.tabId);
      this.isLoadingState = false;
      this.isNavigationEntryCommittedState = true;
      const restoreUrl = this.lastCommitEntryUrl;
      host.applyWebPageCommittedUrlRestore(this.tabId, restoreUrl);
      host.applyWebNavigationHelperMessage('已取消当前加载');
      host.recordRuntimeEvent('web_page_back_cancelled_uncommitted_load', restoreUrl, this.tabId);
      this.refreshNavigationState(host);
      host.syncWebNavigationStateSoon();
      return {
        status: 'loading_cancelled',
        reason: 'loading_not_committed_cancelled',
        targetUrl: restoreUrl,
        errorMessage: ''
      };
    }

    return this.navigateCommittedHistory('back', host);
  }

  goForward(host: BrowserWebPageControllerHost): BrowserWebNavigationCommandResult {
    this.refreshNavigationState(host);
    if (!this.canGoForwardState) {
      return this.buildUnavailableResult('not_available');
    }
    return this.navigateCommittedHistory('forward', host);
  }

  stopLoading(host: BrowserWebPageControllerHost): BrowserWebNavigationCommandResult {
    const result = this.componentController.stop(host);
    host.cancelPreparedNavigation(this.tabId);
    if (!result.handled) {
      return this.buildUnavailableResult(this.normalizeUnavailableReason(result.reason));
    }
    if (result.reason === 'failed') {
      return {
        status: 'failed',
        reason: 'failed',
        targetUrl: '',
        errorMessage: result.errorMessage
      };
    }
    this.isLoadingState = false;
    this.refreshNavigationState(host);
    return {
      status: 'native_issued',
      reason: 'native_history',
      targetUrl: '',
      errorMessage: ''
    };
  }

  refreshNavigationState(host: BrowserWebPageControllerHost): BrowserWebPageStateSnapshot {
    const capabilities: BrowserWebComponentCapabilities = this.componentController.resolveCapabilities(host);
    this.canGoBackwardState = capabilities.canGoBackward;
    this.canGoForwardState = capabilities.canGoForward;
    host.applyWebPageNavigationState(this.tabId, this.canGoBackwardState, this.canGoForwardState);
    this.recordNavigationStateIfChanged(host);
    return this.buildSnapshot();
  }

  buildSnapshot(): BrowserWebPageStateSnapshot {
    return {
      canGoBackward: this.canGoBackwardState,
      canGoForward: this.canGoForwardState,
      isLoading: this.isLoadingState,
      isNavigationEntryCommitted: this.isNavigationEntryCommittedState,
      lastCommitEntryUrl: this.lastCommitEntryUrl,
      lastKnownUrl: this.lastKnownUrl,
      pendingUrl: this.pendingUrl
    };
  }

  buildRuntimeOwnershipSnapshot(): BrowserWebPageRuntimeOwnershipSnapshot {
    return {
      controllerObjectResolved: this.controllerObjectResolvedState,
      normalRuntimeAttached: this.normalRuntimeAttachedState,
      hostedWebNodeAttached: this.hostedWebNodeAttachedState,
      arkWebControllerAttached: this.arkWebControllerAttachedState,
      webIdValid: this.webIdValidState,
      webId: this.webIdState,
      activeOrVisible: this.activeOrVisibleState
    };
  }

  getComponentController(): BrowserWebComponentController {
    return this.componentController;
  }

  resolveHistoryTargetIntentUrl(now: number = Date.now()): string {
    const intent = this.historyTargetIntent;
    if (intent === undefined) {
      return '';
    }
    if (
      now >= intent.expiresAt ||
      intent.webId !== this.webIdState ||
      intent.runtimeGeneration !== this.runtimeGeneration
    ) {
      this.resetHistoryTargetIntent();
      return '';
    }
    return intent.targetUrl;
  }

  private navigateCommittedHistory(
    direction: BrowserWebHistoryDirection,
    host: BrowserWebPageControllerHost
  ): BrowserWebNavigationCommandResult {
    host.clearWebNavigationErrorMessage();
    host.applyWebNavigationHelperMessage(direction === 'back' ? '正在后退' : '正在前进');
    const targetPreview = this.componentController.resolveHistoryTargetPreview(host, direction);
    const dialogWillConsumeBack = direction === 'back' && this.componentController.hasBackDialog();
    const historyTargetUrl = !dialogWillConsumeBack && targetPreview.available
      ? targetPreview.targetUrl.trim()
      : '';
    if (historyTargetUrl.length > 0 && !host.prepareHistoryNavigation(
      this.tabId,
      direction,
      historyTargetUrl,
      targetPreview.targetIndex
    )) {
      host.applyWebNavigationErrorMessage('网页标识准备失败，请重试。');
      return {
        status: 'failed',
        reason: 'failed',
        targetUrl: historyTargetUrl,
        errorMessage: '网页标识准备失败'
      };
    }
    if (historyTargetUrl.length > 0) {
      this.beginHistoryTargetIntent(direction, historyTargetUrl, host);
    }
    if (!dialogWillConsumeBack) {
      host.beginHistoryReturnQuietWindow(this.tabId, direction);
    }
    const result: BrowserWebComponentNavigationResult =
      direction === 'back' ? this.componentController.backward(host) : this.componentController.forward(host);
    if (!result.handled) {
      host.cancelPreparedNavigation(this.tabId);
      this.clearHistoryTargetIntent(host, 'command_unavailable');
      this.refreshNavigationState(host);
      return this.buildUnavailableResult(this.normalizeUnavailableReason(result.reason));
    }
    if (result.reason === 'failed') {
      host.cancelPreparedNavigation(this.tabId);
      this.clearHistoryTargetIntent(host, 'command_failed');
      host.applyWebNavigationErrorMessage(result.errorMessage);
      this.refreshNavigationState(host);
      return {
        status: 'failed',
        reason: 'failed',
        targetUrl: '',
        errorMessage: result.errorMessage
      };
    }
    if (historyTargetUrl.length > 0 && this.resolveHistoryTargetIntentUrl() === historyTargetUrl) {
      host.applyWebHistoryTargetUrlPreview(this.tabId, direction, historyTargetUrl);
    }
    this.refreshNavigationState(host);
    host.syncWebNavigationStateSoon();
    return {
      status: result.reason === 'dialog_back' ? 'transient_consumed' : 'native_issued',
      reason: result.reason === 'dialog_back' ? 'dialog_back' : 'native_history',
      targetUrl: historyTargetUrl,
      errorMessage: ''
    };
  }

  private beginHistoryTargetIntent(
    direction: BrowserWebHistoryDirection,
    targetUrl: string,
    host: BrowserWebPageControllerHost
  ): void {
    this.resetHistoryTargetIntent();
    const issuedAt = Date.now();
    this.historyCommandGeneration += 1;
    const intent: BrowserWebHistoryTargetIntent = {
      direction: direction,
      targetUrl: targetUrl,
      issuedAt: issuedAt,
      expiresAt: issuedAt + HISTORY_TARGET_INTENT_TTL_MS,
      webId: this.webIdState,
      runtimeGeneration: this.runtimeGeneration,
      commandGeneration: this.historyCommandGeneration
    };
    this.historyTargetIntent = intent;
    this.historyTargetIntentTimerId = setTimeout(() => {
      const currentIntent = this.historyTargetIntent;
      if (
        currentIntent === undefined ||
        currentIntent.commandGeneration !== intent.commandGeneration ||
        currentIntent.runtimeGeneration !== intent.runtimeGeneration
      ) {
        return;
      }
      this.clearHistoryTargetIntent(host, 'expired');
    }, HISTORY_TARGET_INTENT_TTL_MS);
    host.recordRuntimeEvent(
      'web_history_target_intent_started',
      `direction=${intent.direction} generation=${intent.commandGeneration} runtimeGeneration=${intent.runtimeGeneration} ` +
        `webId=${intent.webId} issuedAt=${intent.issuedAt} expiresAt=${intent.expiresAt} target=${intent.targetUrl}`,
      this.tabId
    );
  }

  private clearHistoryTargetIntent(host: BrowserWebPageControllerHost, reason: string): void {
    const intent = this.historyTargetIntent;
    if (intent === undefined) {
      return;
    }
    host.recordRuntimeEvent(
      'web_history_target_intent_cleared',
      `reason=${reason} direction=${intent.direction} generation=${intent.commandGeneration} ` +
        `runtimeGeneration=${intent.runtimeGeneration} target=${intent.targetUrl}`,
      this.tabId
    );
    this.resetHistoryTargetIntent();
  }

  private resetHistoryTargetIntent(): void {
    if (this.historyTargetIntentTimerId >= 0) {
      clearTimeout(this.historyTargetIntentTimerId);
      this.historyTargetIntentTimerId = -1;
    }
    this.historyTargetIntent = undefined;
  }

  private shouldCancelUncommittedLoading(): boolean {
    return this.isLoadingState &&
      !this.isNavigationEntryCommittedState &&
      this.lastCommitEntryUrl.trim().length > 0;
  }

  private normalizeUnavailableReason(reason: string): BrowserWebNavigationCommandReason {
    if (reason === 'missing_controller') {
      return 'missing_controller';
    }
    if (reason === 'controller_detached') {
      return 'controller_detached';
    }
    return 'not_available';
  }

  private buildUnavailableResult(reason: BrowserWebNavigationCommandReason): BrowserWebNavigationCommandResult {
    return {
      status: 'unavailable',
      reason: reason,
      targetUrl: '',
      errorMessage: ''
    };
  }

  private recordNavigationStateIfChanged(host: BrowserWebPageControllerHost): void {
    const stateKey = `${this.canGoBackwardState}|${this.canGoForwardState}|${this.isLoadingState}|${this.isNavigationEntryCommittedState}|${this.lastCommitEntryUrl}|${this.lastKnownUrl}|${this.pendingUrl}`;
    if (stateKey === this.lastLoggedNavigationState) {
      return;
    }
    this.lastLoggedNavigationState = stateKey;
    host.recordRuntimeEvent(
      this.isActiveState ? 'active_navigation_state_applied' : 'web_page_navigation_state_updated',
      `back=${this.canGoBackwardState} forward=${this.canGoForwardState} loading=${this.isLoadingState} committed=${this.isNavigationEntryCommittedState} lastCommit=${this.lastCommitEntryUrl} lastKnown=${this.lastKnownUrl} pending=${this.pendingUrl}`,
      this.tabId
    );
  }
}

export function buildUnavailableBrowserWebNavigationCommandResult(
  reason: BrowserWebNavigationCommandReason = 'not_available'
): BrowserWebNavigationCommandResult {
  if (reason === 'not_available') {
    return EMPTY_COMMAND_RESULT;
  }
  return {
    status: 'unavailable',
    reason: reason,
    targetUrl: '',
    errorMessage: ''
  };
}
