import { webview } from '@kit.ArkWeb';
import { BrowserTabRuntimePatch } from '../tabs/TabManager';

export interface BrowserWebLoadPlan {
  tabId: string;
  targetUrl: string;
  strict: boolean;
  clearHistory: boolean;
  source: string;
}

export interface BrowserWebLoadDataPayload {
  data: string;
  mimeType: string;
  encoding: string;
  baseUrl: string;
  historyUrl: string;
}

export interface BrowserWebLoadContentProvider {
  resolveDataPayload: (targetUrl: string, tabId: string) => BrowserWebLoadDataPayload | undefined;
}

export interface BrowserWebLoadExecutionHost {
  resolveController: (tabId: string) => webview.WebviewController | undefined;
  resolveRuntimeLoadUrl?: (targetUrl: string, tabId: string) => string;
  syncEventContext: (tabId: string, targetUrl: string, strict: boolean) => void;
  clearControllerHistory: (tabId: string) => void;
  syncActiveController: (tabId: string, controller: webview.WebviewController) => void;
  resolveDataPayload: (targetUrl: string, tabId: string) => BrowserWebLoadDataPayload | undefined;
  recordLoadFailure: (tabId: string, errorMessage: string) => void;
}

export interface BrowserWebLoadExecutionResult {
  handled: boolean;
  usedDataPayload: boolean;
  errorMessage: string;
}

export interface BrowserWebDataLoadRuntimeRequest {
  runtimeMutationPort: BrowserWebDataLoadMutationPort;
  runtimeLifecyclePort: BrowserWebDataLoadLifecyclePort;
  syncEventContext(tabId: string, targetUrl: string, strict: boolean): void;
  applyActiveControllerState(state: BrowserWebDataLoadActiveControllerState): void;
  recordLoadFailure(tabId: string, errorMessage: string): void;
}

export interface BrowserWebDataLoadMutationResult {
  handled: boolean;
  errorMessage: string;
}

export class BrowserWebDataLoadMutationResultValue implements BrowserWebDataLoadMutationResult {
  handled: boolean;
  errorMessage: string;

  constructor(handled: boolean, errorMessage: string) {
    this.handled = handled;
    this.errorMessage = errorMessage;
  }
}

export interface BrowserWebDataLoadMutationPort {
  loadData: (
    tabId: string,
    payload: BrowserWebLoadDataPayload,
    beforeLoad?: BrowserWebDataLoadBeforeLoad
  ) => BrowserWebDataLoadMutationResult;
}

export type BrowserWebDataLoadBeforeLoad = (
  controller: webview.WebviewController,
  hasLiveController: boolean
) => void;

export interface BrowserWebDataLoadActiveControllerState {
  controller: webview.WebviewController;
  controllerAttached: boolean;
}

export class BrowserWebDataLoadActiveControllerStateValue implements BrowserWebDataLoadActiveControllerState {
  controller: webview.WebviewController;
  controllerAttached: boolean;

  constructor(controller: webview.WebviewController, controllerAttached: boolean) {
    this.controller = controller;
    this.controllerAttached = controllerAttached;
  }
}

export interface BrowserWebDataLoadLifecyclePort {
  resolveActiveControllerState: (
    tabId: string,
    controller: webview.WebviewController,
    hasLiveController: boolean
  ) => BrowserWebDataLoadActiveControllerState | undefined;
}

export type BrowserWebDataLoadEventContextSync = (tabId: string, targetUrl: string, strict: boolean) => void;
export type BrowserWebDataLoadActiveControllerStateApply =
  (state: BrowserWebDataLoadActiveControllerState) => void;
export type BrowserWebDataLoadFailureRecorder = (tabId: string, errorMessage: string) => void;

export class BrowserWebDataLoadRuntimeRequestAdapter implements BrowserWebDataLoadRuntimeRequest {
  runtimeMutationPort: BrowserWebDataLoadMutationPort;
  runtimeLifecyclePort: BrowserWebDataLoadLifecyclePort;
  private syncEventContextHandler: BrowserWebDataLoadEventContextSync;
  private activeControllerStateApply: BrowserWebDataLoadActiveControllerStateApply;
  private loadFailureRecorder: BrowserWebDataLoadFailureRecorder;

  constructor(
    runtimeMutationPort: BrowserWebDataLoadMutationPort,
    runtimeLifecyclePort: BrowserWebDataLoadLifecyclePort,
    syncEventContextHandler: BrowserWebDataLoadEventContextSync,
    activeControllerStateApply: BrowserWebDataLoadActiveControllerStateApply,
    loadFailureRecorder: BrowserWebDataLoadFailureRecorder
  ) {
    this.runtimeMutationPort = runtimeMutationPort;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.syncEventContextHandler = syncEventContextHandler;
    this.activeControllerStateApply = activeControllerStateApply;
    this.loadFailureRecorder = loadFailureRecorder;
  }

  syncEventContext(tabId: string, targetUrl: string, strict: boolean): void {
    this.syncEventContextHandler(tabId, targetUrl, strict);
  }

  applyActiveControllerState(state: BrowserWebDataLoadActiveControllerState): void {
    this.activeControllerStateApply(state);
  }

  recordLoadFailure(tabId: string, errorMessage: string): void {
    this.loadFailureRecorder(tabId, errorMessage);
  }
}

export type BrowserOpenResolvedUrlExecutionStatus = 'issued' | 'waiting_controller' | 'deferred' | 'failed';

export interface BrowserOpenResolvedUrlApplicationResult {
  tabId: string;
  targetUrl: string;
  helperMessage: string;
  title: string;
  tabPatch: BrowserTabRuntimePatch;
}

export interface BrowserOpenResolvedUrlExecutionResult {
  status: BrowserOpenResolvedUrlExecutionStatus;
  errorMessage: string;
}

export interface BrowserOpenResolvedUrlHost {
  prepareOpenResolvedUrlState: (targetUrl: string, title: string, helperMessage: string) => void;
  revealOpenResolvedUrlSurface: () => void;
  applyActiveTabPatch: (patch: BrowserTabRuntimePatch) => void;
  syncActiveRuntimeController: () => void;
  hasAttachedController: () => boolean;
  clearControllerAttachment: () => void;
  executeLoadUrl: (tabId: string, targetUrl: string) => boolean;
}

export class BrowserWebLoadCoordinator {
  buildLoadPlan(
    tabId: string,
    targetUrl: string,
    strict: boolean,
    source: string,
    clearHistory: boolean = false
  ): BrowserWebLoadPlan {
    return {
      tabId: tabId,
      targetUrl: targetUrl.trim(),
      strict: strict,
      clearHistory: clearHistory,
      source: source
    };
  }

  runBackgroundTabPreviewLoad(
    tabId: string,
    targetUrl: string,
    host: BrowserWebLoadExecutionHost
  ): boolean {
    return this.runLoadPlan(
      this.buildLoadPlan(tabId, targetUrl, true, 'background_tab_preview', false),
      host,
      true
    );
  }

  runLoadPlan(
    plan: BrowserWebLoadPlan,
    host: BrowserWebLoadExecutionHost,
    syncEventContext: boolean = true
  ): boolean {
    const controller = host.resolveController(plan.tabId);
    if (controller === undefined) {
      return false;
    }
    if (syncEventContext) {
      host.syncEventContext(plan.tabId, plan.targetUrl, plan.strict);
    }
    if (plan.clearHistory) {
      host.clearControllerHistory(plan.tabId);
    }
    host.syncActiveController(plan.tabId, controller);
    const resolvedRuntimeTargetUrl = host.resolveRuntimeLoadUrl !== undefined ?
      host.resolveRuntimeLoadUrl(plan.targetUrl, plan.tabId).trim() :
      plan.targetUrl;
    const runtimeTargetUrl = resolvedRuntimeTargetUrl.length > 0 ? resolvedRuntimeTargetUrl : plan.targetUrl;
    const runtimePlan: BrowserWebLoadPlan = runtimeTargetUrl === plan.targetUrl ? plan : {
      tabId: plan.tabId,
      targetUrl: runtimeTargetUrl,
      strict: plan.strict,
      clearHistory: plan.clearHistory,
      source: plan.source
    };
    const result = this.executeLoadPlan(controller, runtimePlan, {
      resolveDataPayload: (targetUrl: string, tabId: string) => {
        return host.resolveDataPayload(targetUrl, tabId);
      }
    });
    if (!result.handled && result.errorMessage.length > 0) {
      host.recordLoadFailure(plan.tabId, result.errorMessage);
    }
    return result.handled;
  }

  runDataLoad(
    tabId: string,
    targetUrl: string,
    payload: BrowserWebLoadDataPayload,
    request: BrowserWebDataLoadRuntimeRequest,
    syncEventContext: boolean = false
  ): boolean {
    const result = request.runtimeMutationPort.loadData(
      tabId,
      payload,
      (controller: webview.WebviewController, hasLiveController: boolean): void => {
        if (syncEventContext) {
          request.syncEventContext(tabId, targetUrl, true);
        }
        const state = request.runtimeLifecyclePort.resolveActiveControllerState(
          tabId,
          controller,
          hasLiveController
        );
        if (state !== undefined) {
          request.applyActiveControllerState(state);
        }
      }
    );
    if (!result.handled && result.errorMessage.length > 0) {
      request.recordLoadFailure(tabId, result.errorMessage);
    }
    return result.handled;
  }

  executeLoadPlan(
    controller: webview.WebviewController | undefined,
    plan: BrowserWebLoadPlan,
    contentProvider?: BrowserWebLoadContentProvider
  ): BrowserWebLoadExecutionResult {
    if (controller === undefined) {
      return {
        handled: false,
        usedDataPayload: false,
        errorMessage: 'web_controller_missing'
      };
    }
    try {
      const dataPayload = contentProvider?.resolveDataPayload(plan.targetUrl, plan.tabId);
      if (dataPayload !== undefined) {
        controller.loadData(
          dataPayload.data,
          dataPayload.mimeType,
          dataPayload.encoding,
          dataPayload.baseUrl,
          dataPayload.historyUrl
        );
        return {
          handled: true,
          usedDataPayload: true,
          errorMessage: ''
        };
      }
      controller.loadUrl(plan.targetUrl);
      return {
        handled: true,
        usedDataPayload: false,
        errorMessage: ''
      };
    } catch (error) {
      return {
        handled: false,
        usedDataPayload: false,
        errorMessage: JSON.stringify(error)
      };
    }
  }

  buildOpenResolvedUrlApplicationResult(
    tabId: string,
    resolvedUrl: string,
    helperMessage: string,
    title: string
  ): BrowserOpenResolvedUrlApplicationResult {
    return {
      tabId: tabId,
      targetUrl: resolvedUrl.trim(),
      helperMessage: helperMessage,
      title: title,
      tabPatch: {
        title: title,
        url: resolvedUrl,
        pendingUrl: resolvedUrl,
        isHome: false,
        runtimeState: 'loading',
        lastError: '',
        lastRestoreReason: '',
        lastCrashReason: '',
        webStatePath: '',
        webStateUpdatedAt: 0,
        scrollOffsetY: 0,
        lastGoodUrl: '',
        lastGoodTitle: '',
        lastRestoreType: 'none'
      }
    };
  }

  executeOpenResolvedUrl(
    result: BrowserOpenResolvedUrlApplicationResult,
    host: BrowserOpenResolvedUrlHost,
    prepareState: boolean = true
  ): BrowserOpenResolvedUrlExecutionResult {
    if (prepareState) {
      host.prepareOpenResolvedUrlState(result.targetUrl, result.title, result.helperMessage);
    }
    host.applyActiveTabPatch(result.tabPatch);
    host.syncActiveRuntimeController();
    if (!host.hasAttachedController()) {
      host.clearControllerAttachment();
      return {
        status: 'waiting_controller',
        errorMessage: ''
      };
    }
    try {
      if (host.executeLoadUrl(result.tabId, result.targetUrl)) {
        return {
          status: 'issued',
          errorMessage: ''
        };
      }
      return {
        status: 'failed',
        errorMessage: `打开页面下发失败：${result.targetUrl}`
      };
    } catch (error) {
      return {
        status: 'failed',
        errorMessage: `打开页面下发异常：${JSON.stringify(error)}`
      };
    }
  }
}
