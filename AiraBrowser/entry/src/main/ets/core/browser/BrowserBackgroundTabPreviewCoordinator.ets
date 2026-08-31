import { TabRuntimeState } from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';

const BACKGROUND_PREVIEW_INITIAL_CAPTURE_DELAY_MS: number = 360;
const BACKGROUND_PREVIEW_STABLE_CAPTURE_DELAY_MS: number = 1200;
const BACKGROUND_PREVIEW_PAGE_READY_CAPTURE_DELAY_MS: number = 64;
const BACKGROUND_PREVIEW_CAPTURE_TIMEOUT_MS: number = 5200;

export type BrowserBackgroundTabPreviewFinishReason =
  'captured' |
  'timeout' |
  'cancelled' |
  'tab_removed' |
  'tab_activated' |
  'tab_private' |
  'tab_not_supported' |
  'preview_existing' |
  'attach_failed' |
  'load_failed';

export interface BrowserBackgroundTabPreviewRequest {
  tabId: string;
  url: string;
  createdAt: number;
  initialCaptureDelayMs: number;
  captureDelayMs: number;
  pageReadyCaptureDelayMs: number;
  maxRuntimeMs: number;
}

export interface BrowserBackgroundTabPreviewState {
  activeRequest?: BrowserBackgroundTabPreviewRequest;
  queuedTabIds: string[];
}

export interface BrowserBackgroundTabPreviewPageReadyPlan {
  captureDelayMs: number;
  cancelInitialCapture: boolean;
}

export interface BrowserBackgroundTabPreviewCandidateInput {
  tab: BrowserTabState;
  activeTabId: string;
  hasPreview: boolean;
}

export interface BrowserBackgroundTabPreviewCompletionInput {
  tabId: string;
  reason: BrowserBackgroundTabPreviewFinishReason;
}

export class BrowserBackgroundTabPreviewCoordinator {
  private activeRequest?: BrowserBackgroundTabPreviewRequest;
  private queuedRequests: BrowserBackgroundTabPreviewRequest[] = [];
  private initialCapturedTabIds: string[] = [];

  getState(): BrowserBackgroundTabPreviewState {
    return {
      activeRequest: this.activeRequest,
      queuedTabIds: this.queuedRequests.map((request: BrowserBackgroundTabPreviewRequest) => request.tabId)
    };
  }

  getActiveRequest(): BrowserBackgroundTabPreviewRequest | undefined {
    return this.activeRequest;
  }

  enqueueCandidate(input: BrowserBackgroundTabPreviewCandidateInput): BrowserBackgroundTabPreviewRequest | undefined {
    const reason = this.resolveSkipReason(input);
    if (reason.length > 0) {
      return undefined;
    }
    const existingRequest = this.findRequest(input.tab.id);
    if (existingRequest !== undefined) {
      return existingRequest;
    }
    const request: BrowserBackgroundTabPreviewRequest = {
      tabId: input.tab.id,
      url: input.tab.pendingUrl.length > 0 ? input.tab.pendingUrl : input.tab.url,
      createdAt: Date.now(),
      initialCaptureDelayMs: BACKGROUND_PREVIEW_INITIAL_CAPTURE_DELAY_MS,
      captureDelayMs: BACKGROUND_PREVIEW_STABLE_CAPTURE_DELAY_MS,
      pageReadyCaptureDelayMs: BACKGROUND_PREVIEW_PAGE_READY_CAPTURE_DELAY_MS,
      maxRuntimeMs: BACKGROUND_PREVIEW_CAPTURE_TIMEOUT_MS
    };
    if (this.activeRequest === undefined) {
      this.activeRequest = request;
      return request;
    }
    this.queuedRequests = this.queuedRequests.concat([request]);
    return this.activeRequest;
  }

  complete(input: BrowserBackgroundTabPreviewCompletionInput): BrowserBackgroundTabPreviewRequest | undefined {
    if (this.activeRequest !== undefined && this.activeRequest.tabId === input.tabId) {
      this.activeRequest = undefined;
      const nextRequest = this.queuedRequests[0];
      this.queuedRequests = this.queuedRequests.slice(1);
      this.activeRequest = nextRequest;
      return nextRequest;
    }
    this.queuedRequests = this.queuedRequests.filter((request: BrowserBackgroundTabPreviewRequest) =>
      request.tabId !== input.tabId);
    return this.activeRequest;
  }

  cancel(tabId: string): BrowserBackgroundTabPreviewRequest | undefined {
    return this.complete({
      tabId: tabId,
      reason: 'cancelled'
    });
  }

  cancelAll(): void {
    this.activeRequest = undefined;
    this.queuedRequests = [];
    this.initialCapturedTabIds = [];
  }

  shouldFinishForActiveTabChange(activeTabId: string): boolean {
    return this.activeRequest !== undefined && this.activeRequest.tabId === activeTabId;
  }

  isPreviewRuntimeState(state: TabRuntimeState): boolean {
    return state === 'loading' || state === 'background' || state === 'background-warm';
  }

  shouldTreatProgressAsPageReady(progress: number): boolean {
    return Math.round(progress) >= 100;
  }

  buildPageReadyCapturePlan(request: BrowserBackgroundTabPreviewRequest): BrowserBackgroundTabPreviewPageReadyPlan {
    return {
      captureDelayMs: request.pageReadyCaptureDelayMs,
      cancelInitialCapture: true
    };
  }

  hasInitialCapture(tabId: string): boolean {
    return this.initialCapturedTabIds.includes(tabId);
  }

  markInitialCapture(tabId: string): void {
    if (tabId.trim().length <= 0 || this.initialCapturedTabIds.includes(tabId)) {
      return;
    }
    this.initialCapturedTabIds = this.initialCapturedTabIds.concat([tabId]);
  }

  clearInitialCapture(tabId: string): void {
    this.initialCapturedTabIds = this.initialCapturedTabIds
      .filter((capturedTabId: string) => capturedTabId !== tabId);
  }

  private resolveSkipReason(input: BrowserBackgroundTabPreviewCandidateInput): BrowserBackgroundTabPreviewFinishReason | '' {
    if (input.hasPreview) {
      return 'preview_existing';
    }
    if (input.tab.id === input.activeTabId || input.tab.isHome) {
      return 'tab_activated';
    }
    if (!this.isSupportedHttpUrl(input.tab.pendingUrl.length > 0 ? input.tab.pendingUrl : input.tab.url)) {
      return 'tab_not_supported';
    }
    return '';
  }

  private findRequest(tabId: string): BrowserBackgroundTabPreviewRequest | undefined {
    if (this.activeRequest?.tabId === tabId) {
      return this.activeRequest;
    }
    return this.queuedRequests.find((request: BrowserBackgroundTabPreviewRequest) => request.tabId === tabId);
  }

  private isSupportedHttpUrl(url: string): boolean {
    const normalizedUrl = url.trim().toLowerCase();
    return normalizedUrl.startsWith('http://') || normalizedUrl.startsWith('https://');
  }
}
