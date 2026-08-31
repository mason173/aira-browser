import { webview } from '@kit.ArkWeb';
import { TabRuntimeState } from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import { WebTabRuntimeRecord } from '../web/WebTabRuntime';
import { BrowserHostedWebNodeDisposeReason } from './BrowserRuntimeActionReason';
import { BrowserWebHostAttachState } from './BrowserWebHostCoordinator';
import {
  BrowserBackgroundTabPreviewCoordinator,
  BrowserBackgroundTabPreviewFinishReason,
  BrowserBackgroundTabPreviewRequest
} from './BrowserBackgroundTabPreviewCoordinator';

export interface BrowserBackgroundTabPreviewRuntimeHost {
  resolveTab: (tabId: string) => BrowserTabState | undefined;
  getActiveTabId: () => string;
  getPreviewHostedTabId: () => string;
  hasUsablePreview: (tabId: string) => boolean;
  markBackgroundHot: (
    tabId: string,
    maxCount: number,
    releaseReason: BrowserHostedWebNodeDisposeReason
  ) => void;
  refreshRuntime: (tab: BrowserTabState, tabIdWhenMissing: string) => WebTabRuntimeRecord | undefined;
  markControllerAttached: (tabId: string) => WebTabRuntimeRecord | undefined;
  applyUserAgent: (tabId: string, controller?: webview.WebviewController) => void;
  syncPreview: (tab: BrowserTabState, runtime: WebTabRuntimeRecord) => BrowserWebHostAttachState;
  isHostedControllerAttached: (tabId: string) => boolean;
  capturePreview: (tabId: string) => Promise<boolean>;
  applyBackgroundPreviewRuntimeState: (tabId: string, runtimeState: TabRuntimeState) => void;
  loadUrl: (request: BrowserBackgroundTabPreviewRequest) => boolean;
  releaseBackgroundHot: (tabId: string, releaseReason: BrowserHostedWebNodeDisposeReason) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
}

export interface BrowserBackgroundTabPreviewRuntimeOptions {
  maxBackgroundHotTabCount: number;
  maxAttachAttempts: number;
  attachRetryDelayMs: number;
}

interface BrowserBackgroundTabPreviewRuntimeCapturePlan {
  tabId: string;
  finishReason: BrowserBackgroundTabPreviewFinishReason;
}

interface BrowserBackgroundTabPreviewRuntimeInitialCapturePlan {
  tabId: string;
}

export class BrowserBackgroundTabPreviewRuntimeCoordinator {
  private readonly previewCoordinator: BrowserBackgroundTabPreviewCoordinator;
  private readonly host: BrowserBackgroundTabPreviewRuntimeHost;
  private readonly options: BrowserBackgroundTabPreviewRuntimeOptions;
  private loadIssuedTabIds: string[] = [];
  private initialCaptureTimer: number = -1;
  private captureTimer: number = -1;
  private timeoutTimer: number = -1;

  constructor(
    host: BrowserBackgroundTabPreviewRuntimeHost,
    options: BrowserBackgroundTabPreviewRuntimeOptions,
    previewCoordinator: BrowserBackgroundTabPreviewCoordinator = new BrowserBackgroundTabPreviewCoordinator()
  ) {
    this.previewCoordinator = previewCoordinator;
    this.host = host;
    this.options = options;
  }

  getActiveRequestTabId(): string {
    return this.previewCoordinator.getActiveRequest()?.tabId ?? '';
  }

  shouldTreatProgressAsPageReady(progress: number): boolean {
    return this.previewCoordinator.shouldTreatProgressAsPageReady(progress);
  }

  shouldFinishForActiveTabChange(activeTabId: string): boolean {
    return this.previewCoordinator.shouldFinishForActiveTabChange(activeTabId);
  }

  cancelRequestsOnly(): void {
    this.previewCoordinator.cancelAll();
  }

  removeLoadIssued(tabId: string): void {
    this.loadIssuedTabIds = this.loadIssuedTabIds
      .filter((issuedTabId: string) => issuedTabId !== tabId);
  }

  clearCaptureTimers(): void {
    if (this.initialCaptureTimer >= 0) {
      clearTimeout(this.initialCaptureTimer);
      this.initialCaptureTimer = -1;
    }
    if (this.captureTimer >= 0) {
      clearTimeout(this.captureTimer);
      this.captureTimer = -1;
    }
    if (this.timeoutTimer >= 0) {
      clearTimeout(this.timeoutTimer);
      this.timeoutTimer = -1;
    }
  }

  scheduleCandidate(
    tabId: string,
    source: string
  ): void {
    const host = this.resolveHost();
    const options = this.resolveOptions();
    if (host === undefined || options === undefined) {
      return;
    }
    const tab = host.resolveTab(tabId);
    if (tab === undefined) {
      return;
    }
    const request = this.previewCoordinator.enqueueCandidate({
      tab: tab,
      activeTabId: host.getActiveTabId(),
      hasPreview: host.hasUsablePreview(tabId)
    });
    if (request === undefined || request.tabId !== tabId) {
      return;
    }
    host.recordRuntimeEvent('background_tab_preview_queued', `source=${source} url=${request.url}`, tabId);
    this.startIfNeeded();
  }

  startIfNeeded(): void {
    const host = this.resolveHost();
    const options = this.resolveOptions();
    if (host === undefined || options === undefined) {
      return;
    }
    const request = this.previewCoordinator.getActiveRequest();
    if (request === undefined || request.tabId === host.getPreviewHostedTabId()) {
      return;
    }
    const tab = host.resolveTab(request.tabId);
    if (tab === undefined) {
      this.finishPreview(request.tabId, 'tab_removed');
      return;
    }
    if (tab.id === host.getActiveTabId()) {
      this.finishPreview(request.tabId, 'tab_activated');
      return;
    }
    if (host.hasUsablePreview(request.tabId)) {
      this.finishPreview(request.tabId, 'preview_existing');
      return;
    }
    host.markBackgroundHot(request.tabId, options.maxBackgroundHotTabCount, 'background_preview_release');
    this.scheduleAttach(request.tabId, 0, 0);
  }

  attachIfReady(
    tabId: string,
    attempt: number
  ): void {
    const host = this.resolveHost();
    const options = this.resolveOptions();
    if (host === undefined || options === undefined) {
      return;
    }
    const request = this.previewCoordinator.getActiveRequest();
    if (request === undefined || request.tabId !== tabId) {
      return;
    }
    const tab = host.resolveTab(tabId);
    if (tab === undefined) {
      this.finishPreview(tabId, 'tab_removed');
      return;
    }
    if (tab.id === host.getActiveTabId()) {
      this.finishPreview(tabId, 'tab_activated');
      return;
    }
    const runtime = host.refreshRuntime(tab, tabId);
    if (runtime === undefined) {
      this.finishPreview(tabId, 'attach_failed');
      return;
    }
    const attachState = host.syncPreview(tab, runtime);
    if (!attachState.attached || !attachState.webControllerAttached) {
      host.recordRuntimeEvent('background_tab_preview_attach_pending', request.url, request.tabId);
      if (attempt < options.maxAttachAttempts) {
        this.scheduleAttach(tabId, attempt + 1, options.attachRetryDelayMs);
        return;
      }
      this.finishPreview(tabId, 'attach_failed');
      return;
    }
    this.continueAfterControllerAttached(tabId);
  }

  tryHandleControllerAttached(tabId: string): boolean {
    const host = this.resolveHost();
    if (host === undefined) {
      return false;
    }
    if (tabId === host.getActiveTabId() || tabId !== host.getPreviewHostedTabId()) {
      return false;
    }
    this.handleControllerAttached(tabId, host);
    return true;
  }

  private handleControllerAttached(tabId: string, host: BrowserBackgroundTabPreviewRuntimeHost): void {
    const runtime = host.markControllerAttached(tabId);
    host.applyUserAgent(tabId, runtime?.controller);
    host.recordRuntimeEvent('background_tab_preview_controller_attached', tabId, tabId);
    this.continueAfterControllerAttached(tabId);
  }

  continueAfterControllerAttached(tabId: string): void {
    const host = this.resolveHost();
    if (host === undefined) {
      return;
    }
    const request = this.previewCoordinator.getActiveRequest();
    if (request === undefined || request.tabId !== tabId || host.getPreviewHostedTabId() !== tabId) {
      return;
    }
    const tab = host.resolveTab(tabId);
    if (tab === undefined) {
      this.finishPreview(tabId, 'tab_removed');
      return;
    }
    if (tab.id === host.getActiveTabId()) {
      this.finishPreview(tabId, 'tab_activated');
      return;
    }
    if (this.hasLoadIssued(tabId)) {
      return;
    }
    if (!host.isHostedControllerAttached(tabId)) {
      host.recordRuntimeEvent('background_tab_preview_web_attach_pending', request.url, tabId);
      return;
    }
    this.markLoadIssued(tabId);
    this.applyBackgroundPreviewRuntimeState(request.tabId, 'background-hot', host);
    this.scheduleCaptureTimers(request, host);
    const issued = host.loadUrl(request);
    host.recordRuntimeEvent(
      issued ? 'background_tab_preview_load_issued' : 'background_tab_preview_load_failed',
      request.url,
      request.tabId
    );
    if (!issued) {
      this.finishPreview(request.tabId, 'load_failed');
    }
  }

  schedulePageReadyCapture(
    tabId: string,
    source: string
  ): void {
    const host = this.resolveHost();
    if (host === undefined) {
      return;
    }
    const request = this.previewCoordinator.getActiveRequest();
    if (request === undefined || request.tabId !== tabId || host.getPreviewHostedTabId() !== tabId) {
      return;
    }
    const plan = this.previewCoordinator.buildPageReadyCapturePlan(request);
    if (this.captureTimer >= 0) {
      host.recordRuntimeEvent('background_tab_preview_capture_ready_already_scheduled', source, tabId);
      return;
    }
    host.recordRuntimeEvent('background_tab_preview_capture_ready', source, tabId);
    if (plan.cancelInitialCapture && this.initialCaptureTimer >= 0) {
      clearTimeout(this.initialCaptureTimer);
      this.initialCaptureTimer = -1;
    }
    this.captureTimer = setTimeout(() => {
      this.captureTimer = -1;
      void this.captureIfReady(tabId, 'captured', host);
    }, plan.captureDelayMs);
  }

  private buildCapturePlan(
    tabId: string,
    finishReason: BrowserBackgroundTabPreviewFinishReason
  ): BrowserBackgroundTabPreviewRuntimeCapturePlan | undefined {
    const request = this.previewCoordinator.getActiveRequest();
    if (request === undefined || request.tabId !== tabId) {
      return undefined;
    }
    return {
      tabId: tabId,
      finishReason: finishReason
    };
  }

  private applyCaptureResult(
    plan: BrowserBackgroundTabPreviewRuntimeCapturePlan,
    captured: boolean,
    host: BrowserBackgroundTabPreviewRuntimeHost
  ): void {
    const request = this.previewCoordinator.getActiveRequest();
    if (request === undefined || request.tabId !== plan.tabId) {
      return;
    }
    if (captured || plan.finishReason === 'timeout') {
      this.finishPreview(plan.tabId, captured ? 'captured' : plan.finishReason);
      return;
    }
    host.recordRuntimeEvent('background_tab_preview_capture_deferred', `reason=${plan.finishReason}`, plan.tabId);
  }

  private buildInitialCapturePlan(
    tabId: string,
    host: BrowserBackgroundTabPreviewRuntimeHost
  ): BrowserBackgroundTabPreviewRuntimeInitialCapturePlan | undefined {
    const request = this.previewCoordinator.getActiveRequest();
    if (request === undefined || request.tabId !== tabId || host.getPreviewHostedTabId() !== tabId) {
      return undefined;
    }
    if (this.previewCoordinator.hasInitialCapture(tabId)) {
      return undefined;
    }
    return {
      tabId: tabId
    };
  }

  private applyInitialCaptureResult(
    plan: BrowserBackgroundTabPreviewRuntimeInitialCapturePlan,
    captured: boolean,
    host: BrowserBackgroundTabPreviewRuntimeHost
  ): void {
    const request = this.previewCoordinator.getActiveRequest();
    if (request === undefined || request.tabId !== plan.tabId || host.getPreviewHostedTabId() !== plan.tabId) {
      return;
    }
    if (!captured) {
      host.recordRuntimeEvent('background_tab_preview_initial_capture_deferred', request.url, plan.tabId);
      return;
    }
    this.previewCoordinator.markInitialCapture(plan.tabId);
    host.recordRuntimeEvent('background_tab_preview_initial_captured', request.url, plan.tabId);
  }

  finishPreview(
    tabId: string,
    reason: BrowserBackgroundTabPreviewFinishReason
  ): void {
    const host = this.resolveHost();
    const options = this.resolveOptions();
    if (host === undefined || options === undefined) {
      return;
    }
    if (host.getPreviewHostedTabId() === tabId) {
      this.clearCaptureTimers();
      this.applyBackgroundPreviewRuntimeState(tabId, 'background-hot', host);
    }
    this.removeLoadIssued(tabId);
    this.previewCoordinator.clearInitialCapture(tabId);
    const nextRequest = this.previewCoordinator.complete({
      tabId: tabId,
      reason: reason
    });
    host.recordRuntimeEvent('background_tab_preview_finished', `reason=${reason}`, tabId);
    if (reason === 'attach_failed' || reason === 'load_failed') {
      host.releaseBackgroundHot(tabId, 'background_preview_release');
    }
    if (nextRequest !== undefined && nextRequest.tabId !== tabId) {
      this.scheduleStart(0);
    }
  }

  cancelAll(source: string): void {
    const host = this.resolveHost();
    if (host === undefined) {
      return;
    }
    const request = this.previewCoordinator.getActiveRequest();
    this.clearCaptureTimers();
    const hostedTabId = host.getPreviewHostedTabId();
    if (hostedTabId.length > 0) {
      host.releaseBackgroundHot(hostedTabId, 'background_preview_release');
    }
    this.clearLoadIssued();
    this.previewCoordinator.cancelAll();
    if (request !== undefined) {
      host.recordRuntimeEvent('background_tab_preview_cancelled', source, request.tabId);
    }
  }

  private applyBackgroundPreviewRuntimeState(
    tabId: string,
    runtimeState: TabRuntimeState,
    host: BrowserBackgroundTabPreviewRuntimeHost
  ): void {
    const tab = host.resolveTab(tabId);
    if (tab === undefined || tab.id === host.getActiveTabId() || tab.isHome) {
      return;
    }
    host.applyBackgroundPreviewRuntimeState(tabId, runtimeState);
  }

  private scheduleCaptureTimers(
    request: BrowserBackgroundTabPreviewRequest,
    host: BrowserBackgroundTabPreviewRuntimeHost
  ): void {
    this.clearCaptureTimers();
    this.initialCaptureTimer = setTimeout(() => {
      this.initialCaptureTimer = -1;
      void this.captureInitialIfReady(request.tabId, host);
    }, request.initialCaptureDelayMs);
    this.captureTimer = setTimeout(() => {
      this.captureTimer = -1;
      void this.captureIfReady(request.tabId, 'captured', host);
    }, request.captureDelayMs);
    this.timeoutTimer = setTimeout(() => {
      this.timeoutTimer = -1;
      void this.captureIfReady(request.tabId, 'timeout', host);
    }, request.maxRuntimeMs);
  }

  private async captureIfReady(
    tabId: string,
    finishReason: BrowserBackgroundTabPreviewFinishReason,
    host: BrowserBackgroundTabPreviewRuntimeHost
  ): Promise<void> {
    const plan = this.buildCapturePlan(tabId, finishReason);
    if (plan === undefined) {
      return;
    }
    const captured = await host.capturePreview(plan.tabId);
    this.applyCaptureResult(plan, captured, host);
  }

  private async captureInitialIfReady(
    tabId: string,
    host: BrowserBackgroundTabPreviewRuntimeHost
  ): Promise<void> {
    const plan = this.buildInitialCapturePlan(tabId, host);
    if (plan === undefined) {
      return;
    }
    const captured = await host.capturePreview(plan.tabId);
    this.applyInitialCaptureResult(plan, captured, host);
  }

  private scheduleAttach(
    tabId: string,
    attempt: number,
    delayMs: number
  ): void {
    setTimeout(() => {
      this.attachIfReady(tabId, attempt);
    }, delayMs);
  }

  private scheduleStart(delayMs: number): void {
    setTimeout(() => {
      this.startIfNeeded();
    }, delayMs);
  }

  private resolveHost(): BrowserBackgroundTabPreviewRuntimeHost | undefined {
    return this.host;
  }

  private resolveOptions(): BrowserBackgroundTabPreviewRuntimeOptions | undefined {
    return this.options;
  }

  private hasLoadIssued(tabId: string): boolean {
    return this.loadIssuedTabIds.includes(tabId);
  }

  private markLoadIssued(tabId: string): void {
    if (tabId.trim().length <= 0 || this.loadIssuedTabIds.includes(tabId)) {
      return;
    }
    this.loadIssuedTabIds = this.loadIssuedTabIds.concat([tabId]);
  }

  private clearLoadIssued(): void {
    this.loadIssuedTabIds = [];
  }
}
