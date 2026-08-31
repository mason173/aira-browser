import { webview } from '@kit.ArkWeb';
import {
  BrowserUnifiedLinkResult,
  BrowserUnifiedLinkSource
} from '../../services/web/BrowserUnifiedLinkLogic';

export type BrowserWebHistoryDirection = 'back' | 'forward';

export type BrowserWebComponentNavigationReason =
  'issued' |
  'dialog_back' |
  'missing_controller' |
  'controller_detached' |
  'not_available' |
  'failed';

export type BrowserWebDialogKind = 'prompt' | 'confirm' | 'alert' | 'http_auth' | 'ssl_error';

export interface BrowserWebComponentCapabilities {
  canGoBackward: boolean;
  canGoForward: boolean;
}

export interface BrowserWebHistoryTargetPreview {
  available: boolean;
  currentIndex: number;
  targetIndex: number;
  currentUrl: string;
  targetUrl: string;
}

export interface BrowserWebComponentNavigationResult {
  handled: boolean;
  available: boolean;
  reason: BrowserWebComponentNavigationReason;
  errorMessage: string;
}

export type BrowserWebComponentWebStateRestoreReason =
  'restored' |
  'empty_web_state' |
  'missing_controller' |
  'controller_detached' |
  'failed';

export interface BrowserWebComponentWebStateRestoreResult {
  restored: boolean;
  reason: BrowserWebComponentWebStateRestoreReason;
  errorMessage: string;
}

export type BrowserWebComponentNavigationEventSource =
  'override_url_loading' |
  'load_intercept';

export type BrowserWebComponentWebUrlAction =
  'allow_web' |
  'consume_internal' |
  'consume_extension_action' |
  'consume_security_block' |
  'rewrite_same_web_navigation' |
  'deny' |
  'open_external' |
  'show_info_bar' |
  'show_dialog' |
  'load_fallback_in_web';

export interface BrowserWebComponentWebUrlDecision {
  action: BrowserWebComponentWebUrlAction;
  targetUrl: string;
  reason: string;
}

export interface BrowserWebComponentLinkRequest {
  tabId: string;
  url: string;
  source: BrowserUnifiedLinkSource;
  isMainFrame: boolean;
  isRequestGesture: boolean;
}

export interface BrowserWebComponentNavigationEventRequest {
  source: BrowserWebComponentNavigationEventSource;
  url: string;
  isMainFrame: boolean;
  isRequestGesture: boolean;
  request?: WebResourceRequest;
}

export interface BrowserWebComponentControllerHost {
  resolveWebController: (tabId: string) => webview.WebviewController | undefined;
  isWebControllerAttached: (tabId: string) => boolean;
  handleWebDialogBack: (tabId: string, kind: BrowserWebDialogKind) => boolean;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
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
}

const EMPTY_WEB_STATE_RESTORE_RESULT: BrowserWebComponentWebStateRestoreResult = {
  restored: false,
  reason: 'empty_web_state',
  errorMessage: ''
};

export class BrowserWebComponentController {
  private tabId: string;
  private dialogStack: BrowserWebDialogKind[] = [];
  private restoringWebState: boolean = false;

  constructor(tabId: string) {
    this.tabId = tabId;
  }

  setTabId(tabId: string): void {
    this.tabId = tabId;
  }

  setDialogVisible(kind: BrowserWebDialogKind, visible: boolean): void {
    const retained: BrowserWebDialogKind[] = [];
    this.dialogStack.forEach((item: BrowserWebDialogKind) => {
      if (item !== kind) {
        retained.push(item);
      }
    });
    if (visible) {
      retained.push(kind);
    }
    this.dialogStack = retained;
  }

  clearDialogs(): void {
    this.dialogStack = [];
  }

  hasBackDialog(): boolean {
    return this.dialogStack.length > 0;
  }

  accessBackward(host: BrowserWebComponentControllerHost): boolean {
    if (this.hasBackDialog()) {
      return true;
    }
    return this.accessController(host, 'back');
  }

  accessForward(host: BrowserWebComponentControllerHost): boolean {
    return this.accessController(host, 'forward');
  }

  resolveCapabilities(host: BrowserWebComponentControllerHost): BrowserWebComponentCapabilities {
    return {
      canGoBackward: this.accessBackward(host),
      canGoForward: this.accessForward(host)
    };
  }

  backward(host: BrowserWebComponentControllerHost): BrowserWebComponentNavigationResult {
    const dialogKind = this.peekDialog();
    if (dialogKind !== undefined) {
      const handled = host.handleWebDialogBack(this.tabId, dialogKind);
      if (handled) {
        this.setDialogVisible(dialogKind, false);
      }
      return {
        handled: handled,
        available: true,
        reason: 'dialog_back',
        errorMessage: ''
      };
    }
    return this.navigateController(host, 'back');
  }

  forward(host: BrowserWebComponentControllerHost): BrowserWebComponentNavigationResult {
    return this.navigateController(host, 'forward');
  }

  stop(host: BrowserWebComponentControllerHost): BrowserWebComponentNavigationResult {
    const controller = this.resolveAttachedController(host);
    if (controller === undefined) {
      return this.buildUnavailableResult(host);
    }
    try {
      controller.stop();
      host.recordRuntimeEvent('web_component_stop', 'stop loading', this.tabId);
      return {
        handled: true,
        available: true,
        reason: 'issued',
        errorMessage: ''
      };
    } catch (error) {
      return this.buildFailedResult('停止加载失败', error);
    }
  }

  getBackForwardEntries(host: BrowserWebComponentControllerHost): webview.BackForwardList | undefined {
    const controller = this.resolveAttachedController(host);
    if (controller === undefined) {
      return undefined;
    }
    try {
      return controller.getBackForwardEntries();
    } catch (_error) {
      return undefined;
    }
  }

  serializeWebState(host: BrowserWebComponentControllerHost): Uint8Array | undefined {
    const controller = this.resolveAttachedController(host);
    if (controller === undefined) {
      return undefined;
    }
    try {
      const serialized = controller.serializeWebState() as Uint8Array | undefined;
      if (serialized === undefined || serialized === null || serialized.byteLength <= 0) {
        return undefined;
      }
      return serialized;
    } catch (_error) {
      return undefined;
    }
  }

  restoreWebState(
    payload: Uint8Array | undefined,
    host: BrowserWebComponentControllerHost
  ): BrowserWebComponentWebStateRestoreResult {
    if (payload === undefined || payload.byteLength <= 0) {
      return EMPTY_WEB_STATE_RESTORE_RESULT;
    }
    const controller = this.resolveAttachedController(host);
    if (controller === undefined) {
      return this.buildWebStateUnavailableResult(host);
    }
    this.restoringWebState = true;
    try {
      controller.restoreWebState(payload);
      host.recordRuntimeEvent('web_component_web_state_restored', `bytes=${payload.byteLength}`, this.tabId);
      return {
        restored: true,
        reason: 'restored',
        errorMessage: ''
      };
    } catch (error) {
      return {
        restored: false,
        reason: 'failed',
        errorMessage: `WebState 恢复失败：${JSON.stringify(error)}`
      };
    } finally {
      this.restoringWebState = false;
    }
  }

  resolveHistoryTargetPreview(
    host: BrowserWebComponentControllerHost,
    direction: BrowserWebHistoryDirection
  ): BrowserWebHistoryTargetPreview {
    const emptyPreview: BrowserWebHistoryTargetPreview = {
      available: false,
      currentIndex: -1,
      targetIndex: -1,
      currentUrl: '',
      targetUrl: ''
    };
    const entries = this.getBackForwardEntries(host);
    if (entries === undefined) {
      return emptyPreview;
    }
    try {
      const currentIndex = entries.currentIndex;
      const targetIndex = direction === 'back' ? currentIndex - 1 : currentIndex + 1;
      if (targetIndex < 0 || targetIndex >= entries.size) {
        return emptyPreview;
      }
      const currentItem = currentIndex >= 0 && currentIndex < entries.size
        ? entries.getItemAtIndex(currentIndex)
        : undefined;
      const targetItem = entries.getItemAtIndex(targetIndex);
      return {
        available: true,
        currentIndex: currentIndex,
        targetIndex: targetIndex,
        currentUrl: this.resolveHistoryItemUrl(currentItem),
        targetUrl: this.resolveHistoryItemUrl(targetItem)
      };
    } catch (_error) {
      return emptyPreview;
    }
  }

  onOverrideUrlLoading(request: WebResourceRequest, host: BrowserWebComponentControllerHost): boolean {
    const targetUrl = this.safeReadRequestUrl(request);
    if (targetUrl.length <= 0) {
      return false;
    }
    const navigationRequest: BrowserWebComponentNavigationEventRequest = {
      source: 'override_url_loading',
      url: targetUrl,
      isMainFrame: this.safeReadIsMainFrame(request),
      isRequestGesture: this.safeReadIsRequestGesture(request),
      request: request
    };
    return this.handleNavigationEvent(navigationRequest, host);
  }

  onLoadIntercept(event: OnLoadInterceptEvent, host: BrowserWebComponentControllerHost): boolean {
    const request = event.data;
    const targetUrl = this.safeReadRequestUrl(request);
    if (targetUrl.length <= 0) {
      return false;
    }
    const navigationRequest: BrowserWebComponentNavigationEventRequest = {
      source: 'load_intercept',
      url: targetUrl,
      isMainFrame: this.safeReadIsMainFrame(request),
      isRequestGesture: this.safeReadIsRequestGesture(request),
      request: request
    };
    return this.handleNavigationEvent(navigationRequest, host);
  }

  private peekDialog(): BrowserWebDialogKind | undefined {
    if (this.dialogStack.length <= 0) {
      return undefined;
    }
    return this.dialogStack[this.dialogStack.length - 1];
  }

  private resolveHistoryItemUrl(item: webview.HistoryItem | undefined): string {
    if (item === undefined) {
      return '';
    }
    const historyUrl = item.historyUrl.trim();
    if (historyUrl.length > 0) {
      return historyUrl;
    }
    return item.historyRawUrl.trim();
  }

  private handleNavigationEvent(
    request: BrowserWebComponentNavigationEventRequest,
    host: BrowserWebComponentControllerHost
  ): boolean {
    const specialDecision =
      host.handleSpecialNavigationAction(this.tabId, request.url, request.source, request.isMainFrame);
    if (specialDecision.action !== 'allow_web') {
      return this.consumeNavigationDecision(host, request, specialDecision, 'special');
    }

    if (host.canLoadUrlInWebView(request.url)) {
      if (request.isMainFrame) {
        const decision = host.resolveMainFrameWebUrlDecision(
          this.tabId,
          request.url,
          request.request,
          request.source
        );
        if (decision.action !== 'allow_web') {
          return this.consumeNavigationDecision(host, request, decision, 'main_frame');
        }
        const targetUrl = decision.targetUrl.length > 0 ? decision.targetUrl : request.url;
        if (!this.restoringWebState &&
          !host.prepareMainFrameWebNavigation(this.tabId, targetUrl, request.isRequestGesture)) {
          this.recordNavigationPolicyResult(host, request, 'main_frame_identity_prepare_failed', true);
          return true;
        }
        host.observeMainFrameWebRequest(this.tabId, targetUrl);
        this.recordNavigationPolicyResult(
          host,
          request,
          `main_frame_allow_web_${decision.reason}`,
          false
        );
        return false;
      }
      this.recordNavigationPolicyResult(host, request, 'webview_supported_subframe', false);
      return false;
    }

    if (host.handleWebAppScopeOutNavigation(this.tabId, request.url, request.isMainFrame)) {
      this.recordNavigationPolicyResult(host, request, 'web_app_scope_out', true);
      return true;
    }

    const result = host.evaluateUnifiedLinkNavigation({
      tabId: this.tabId,
      url: request.url,
      source: request.source,
      isMainFrame: request.isMainFrame,
      isRequestGesture: request.isRequestGesture
    });
    host.applyUnifiedLinkNavigationResult(result);
    this.recordNavigationPolicyResult(host, request, `unified_link_${result.action}_${result.reason}`, result.shouldConsumeWebLoad);
    return result.shouldConsumeWebLoad;
  }

  private consumeNavigationDecision(
    host: BrowserWebComponentControllerHost,
    request: BrowserWebComponentNavigationEventRequest,
    decision: BrowserWebComponentWebUrlDecision,
    reasonPrefix: string
  ): boolean {
    let detail = `${reasonPrefix}_${decision.action}_${decision.reason}`;
    if (decision.action === 'rewrite_same_web_navigation') {
      const issued = host.executeSameWebNavigationRewrite(this.tabId, decision.targetUrl, decision.reason);
      detail = `${detail}_issued=${issued}`;
    }
    this.recordNavigationPolicyResult(host, request, detail, true);
    return true;
  }

  private recordNavigationPolicyResult(
    host: BrowserWebComponentControllerHost,
    request: BrowserWebComponentNavigationEventRequest,
    reason: string,
    consumed: boolean
  ): void {
    host.recordRuntimeEvent(
      'web_navigation_policy_result',
      `source=${request.source} mainFrame=${request.isMainFrame} gesture=${request.isRequestGesture} consumed=${consumed} reason=${reason} url=${request.url}`,
      this.tabId
    );
  }

  private safeReadRequestUrl(request: WebResourceRequest): string {
    try {
      return request.getRequestUrl().trim();
    } catch (_error) {
      return '';
    }
  }

  private safeReadIsMainFrame(request: WebResourceRequest): boolean {
    try {
      return request.isMainFrame();
    } catch (_error) {
      return false;
    }
  }

  private safeReadIsRequestGesture(request: WebResourceRequest): boolean {
    try {
      return request.isRequestGesture();
    } catch (_error) {
      return false;
    }
  }

  private accessController(
    host: BrowserWebComponentControllerHost,
    direction: BrowserWebHistoryDirection
  ): boolean {
    const controller = this.resolveAttachedController(host);
    if (controller === undefined) {
      return false;
    }
    try {
      return direction === 'back' ? controller.accessBackward() : controller.accessForward();
    } catch (_error) {
    }
    try {
      return controller.accessStep(direction === 'back' ? -1 : 1);
    } catch (_error) {
      return false;
    }
  }

  private navigateController(
    host: BrowserWebComponentControllerHost,
    direction: BrowserWebHistoryDirection
  ): BrowserWebComponentNavigationResult {
    if (!this.accessController(host, direction)) {
      return {
        handled: false,
        available: false,
        reason: 'not_available',
        errorMessage: ''
      };
    }
    const controller = this.resolveAttachedController(host);
    if (controller === undefined) {
      return this.buildUnavailableResult(host);
    }
    try {
      if (direction === 'back') {
        controller.backward();
      } else {
        controller.forward();
      }
      host.recordRuntimeEvent(
        'web_component_history_navigation',
        direction === 'back' ? 'backward' : 'forward',
        this.tabId
      );
      return {
        handled: true,
        available: true,
        reason: 'issued',
        errorMessage: ''
      };
    } catch (error) {
      return this.buildFailedResult(direction === 'back' ? '后退失败' : '前进失败', error);
    }
  }

  private resolveAttachedController(
    host: BrowserWebComponentControllerHost
  ): webview.WebviewController | undefined {
    if (!host.isWebControllerAttached(this.tabId)) {
      return undefined;
    }
    return host.resolveWebController(this.tabId);
  }

  private buildUnavailableResult(host: BrowserWebComponentControllerHost): BrowserWebComponentNavigationResult {
    if (host.resolveWebController(this.tabId) === undefined) {
      return {
        handled: false,
        available: false,
        reason: 'missing_controller',
        errorMessage: ''
      };
    }
    return {
      handled: false,
      available: false,
      reason: 'controller_detached',
      errorMessage: ''
    };
  }

  private buildWebStateUnavailableResult(
    host: BrowserWebComponentControllerHost
  ): BrowserWebComponentWebStateRestoreResult {
    if (host.resolveWebController(this.tabId) === undefined) {
      return {
        restored: false,
        reason: 'missing_controller',
        errorMessage: ''
      };
    }
    return {
      restored: false,
      reason: 'controller_detached',
      errorMessage: ''
    };
  }

  private buildFailedResult(prefix: string, error: Object): BrowserWebComponentNavigationResult {
    return {
      handled: true,
      available: true,
      reason: 'failed',
      errorMessage: `${prefix}：${JSON.stringify(error)}`
    };
  }
}
