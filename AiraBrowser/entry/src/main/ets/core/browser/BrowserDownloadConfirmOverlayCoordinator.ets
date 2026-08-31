import {
  DownloadRuntimeService,
  ManualDownloadRequestInput,
  ManualDownloadRequestResult,
  PendingDownloadPromptState
} from '../../services/download/DownloadRuntimeService';
import {
  BrowserDownloadNavigationStateCoordinator,
  BrowserInlineDocumentPromptResolution
} from './BrowserDownloadNavigationStateCoordinator';
import {
  BrowserDownloadPromptLeaseCoordinator,
  BrowserDownloadPromptLeaseReleaseReason
} from './BrowserDownloadPromptLeaseCoordinator';
import { BrowserWebPageLifecycleApplicationCoordinator } from './BrowserWebPageLifecycleApplicationCoordinator';
import { sharedBrowserContinuationCoordinator } from './BrowserContinuationCoordinator';
export interface BrowserDownloadConfirmOverlayFacts {
  activeTabId: string;
}

export interface BrowserDownloadConfirmOverlayAction {
  type: 'confirm' | 'cancel' | 'reset';
  guid?: string;
  fileName?: string;
}

export interface BrowserDownloadConfirmOverlayHost {
  resolveFacts: () => BrowserDownloadConfirmOverlayFacts;
  publishPendingPrompt: (prompt?: PendingDownloadPromptState) => void;
  showToast: (message: string) => void;
}

interface BrowserDownloadConfirmDecisionWaiter {
  guid: string;
  resolve: () => void;
}

export class BrowserDownloadConfirmOverlayCoordinator {
  private readonly downloadService: DownloadRuntimeService;
  private readonly navigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;
  private readonly host: BrowserDownloadConfirmOverlayHost;
  private readonly webPageLifecycleApplicationCoordinator: BrowserWebPageLifecycleApplicationCoordinator;
  private leaseCoordinator: BrowserDownloadPromptLeaseCoordinator = new BrowserDownloadPromptLeaseCoordinator();
  private pendingPrompt?: PendingDownloadPromptState = undefined;
  private pendingPromptTabId: string = '';
  private activeLeaseId: string = '';
  private decisionWaiter?: BrowserDownloadConfirmDecisionWaiter = undefined;

  constructor(
    downloadService: DownloadRuntimeService,
    navigationStateCoordinator: BrowserDownloadNavigationStateCoordinator,
    host: BrowserDownloadConfirmOverlayHost,
    webPageLifecycleApplicationCoordinator: BrowserWebPageLifecycleApplicationCoordinator
  ) {
    this.downloadService = downloadService;
    this.navigationStateCoordinator = navigationStateCoordinator;
    this.host = host;
    this.webPageLifecycleApplicationCoordinator = webPageLifecycleApplicationCoordinator;
  }

  hasActiveLease(): boolean {
    return this.leaseCoordinator.isLeaseActive(this.activeLeaseId);
  }

  present(prompt: PendingDownloadPromptState | undefined): void {
    if (prompt !== undefined && this.decisionWaiter !== undefined && this.decisionWaiter.guid !== prompt.guid) {
      this.completeDecisionWaiter();
    }
    if (prompt === undefined) {
      this.reset(false);
      return;
    }
    const inlineDocumentResolution = this.resolveInlineDocumentPrompt(prompt);
    if (inlineDocumentResolution.shouldIgnore) {
      this.downloadService.abandonPendingDownload(prompt.guid);
      this.reset(false);
      this.navigationStateCoordinator.markVisibleDocumentNavigationCommitted(
        this.host.resolveFacts().activeTabId,
        prompt.url
      );
      return;
    }
    if (this.pendingPrompt?.guid === prompt.guid && this.hasActiveLease()) {
      return;
    }
    const presentation = this.leaseCoordinator.acquire({
      guid: prompt.guid,
      url: prompt.url
    });
    if (!presentation.shouldPresent || presentation.lease === undefined || presentation.prompt === undefined) {
      this.downloadService.abandonPendingDownload(prompt.guid);
      this.reset(false);
      return;
    }
    if (!inlineDocumentResolution.shouldPreserveStableDocument) {
      this.navigationStateCoordinator.markDownloadUrlHandled(prompt.url);
      this.navigationStateCoordinator.resetPromptNavigationState(prompt.url);
    }
    this.activeLeaseId = presentation.lease.id;
    if (!inlineDocumentResolution.shouldPreserveStableDocument) {
      this.webPageLifecycleApplicationCoordinator.pulseDownloadHandoffVisualFeedback(
        this.host.resolveFacts().activeTabId,
        prompt.url
      );
    }
    this.publishPendingPrompt(prompt);
  }

  presentAndWaitForDecision(prompt: PendingDownloadPromptState | undefined): Promise<void> {
    this.completeDecisionWaiter();
    if (prompt === undefined) {
      this.present(undefined);
      return Promise.resolve();
    }
    return new Promise<void>((resolve: () => void) => {
      this.decisionWaiter = {
        guid: prompt.guid,
        resolve: resolve
      };
      this.present(prompt);
      if (this.pendingPrompt?.guid !== prompt.guid) {
        this.completeDecisionWaiter(prompt.guid);
      }
    });
  }

  requestAndPresent(input: ManualDownloadRequestInput): string {
    const normalizedUrl = input.url.trim();
    if (normalizedUrl.length === 0) {
      return '';
    }
    const result: ManualDownloadRequestResult | undefined = this.downloadService.requestManualDownload({
      url: normalizedUrl,
      sourceHost: input.sourceHost,
      suggestedFileName: input.suggestedFileName,
      totalBytes: input.totalBytes,
      userAgent: input.userAgent,
      referer: input.referer,
      mimeType: input.mimeType,
      contentDisposition: input.contentDisposition,
      headers: input.headers
    });
    if (result === undefined) {
      return '';
    }
    this.present(result.prompt);
    return result.guid;
  }

  handleAction(action: BrowserDownloadConfirmOverlayAction): void {
    if (action.type === 'confirm') {
      if (action.guid !== undefined) {
        void this.confirm(action.guid, action.fileName);
      }
      return;
    }
    if (action.type === 'cancel') {
      if (action.guid !== undefined) {
        this.cancel(action.guid);
      }
      return;
    }
    this.reset(false);
  }

  reset(syncPromptFromService: boolean): void {
    this.completeDecisionWaiter();
    const servicePrompt = syncPromptFromService ? this.downloadService.getPendingDownloadPrompt() : undefined;
    const activeLeaseId = this.activeLeaseId;
    if (activeLeaseId.length > 0) {
      this.leaseCoordinator.releaseLease(activeLeaseId, syncPromptFromService ? 'route_transition' : 'dismiss');
    } else if (this.pendingPrompt !== undefined && !syncPromptFromService) {
      this.leaseCoordinator.releaseGuid(this.pendingPrompt.guid, 'dismiss');
    }
    this.activeLeaseId = '';
    const presentation = this.leaseCoordinator.acquire(servicePrompt === undefined ? undefined : {
      guid: servicePrompt.guid,
      url: servicePrompt.url
    });
    const pendingPrompt = presentation.shouldPresent ? servicePrompt : undefined;
    this.publishPendingPrompt(pendingPrompt);
    if (syncPromptFromService && pendingPrompt !== undefined && presentation.lease !== undefined) {
      this.activeLeaseId = presentation.lease.id;
    }
  }

  releaseActiveLease(reason: BrowserDownloadPromptLeaseReleaseReason): void {
    this.completeDecisionWaiter();
    if (this.activeLeaseId.length <= 0) {
      return;
    }
    this.leaseCoordinator.releaseLease(this.activeLeaseId, reason);
    this.activeLeaseId = '';
  }

  clearForPrivateSessionCleanup(): void {
    this.completeDecisionWaiter();
    this.releaseActiveLease('dismiss');
    if (this.pendingPrompt !== undefined) {
      this.leaseCoordinator.releaseGuid(this.pendingPrompt.guid, 'dismiss');
    }
    this.publishPendingPrompt(undefined);
  }

  abandonPendingPromptForDisappear(): void {
    const prompt = this.pendingPrompt ?? this.downloadService.getPendingDownloadPrompt();
    if (prompt === undefined) {
      return;
    }
    this.downloadService.abandonPendingDownload(prompt.guid);
  }

  private async confirm(guid: string, fileName?: string): Promise<void> {
    const host = this.host;
    const prompt = this.pendingPrompt ?? this.downloadService.getPendingDownloadPrompt();
    const effectiveGuid = prompt?.guid ?? guid;
    this.completeDecisionWaiter(effectiveGuid);
    const beginFacts = host.resolveFacts();
    if (prompt !== undefined) {
      this.navigationStateCoordinator.markDownloadNavigationConfirmed(beginFacts.activeTabId, prompt.url, prompt.guid);
      this.leaseCoordinator.releaseGuid(prompt.guid, 'confirm');
    }
    const confirmed = await this.downloadService.confirmPendingDownload(effectiveGuid, fileName);
    if (!confirmed) {
      host.showToast('当前下载暂时不能开始。');
    }
  }

  private cancel(guid: string): void {
    const host = this.host;
    const prompt = this.pendingPrompt ?? this.downloadService.getPendingDownloadPrompt();
    const effectiveGuid = prompt?.guid ?? guid;
    this.completeDecisionWaiter(effectiveGuid);
    const facts = host.resolveFacts();
    if (prompt !== undefined) {
      this.navigationStateCoordinator.markDownloadNavigationCanceled(facts.activeTabId, prompt.url);
      this.leaseCoordinator.releaseGuid(prompt.guid, 'cancel');
    }
    const canceled = this.downloadService.cancelPendingDownload(effectiveGuid);
    if (!canceled) {
      host.showToast('当前下载暂时不能取消。');
    }
  }

  private publishPendingPrompt(prompt?: PendingDownloadPromptState): void {
    const nextTabId = prompt === undefined ? '' : this.host.resolveFacts().activeTabId.trim();
    if (this.pendingPromptTabId.length > 0 && this.pendingPromptTabId !== nextTabId) {
      sharedBrowserContinuationCoordinator.setTransientFlowBlocked(
        this.pendingPromptTabId,
        'download_prompt',
        false
      );
    }
    this.pendingPrompt = prompt;
    this.pendingPromptTabId = nextTabId;
    if (nextTabId.length > 0) {
      sharedBrowserContinuationCoordinator.setTransientFlowBlocked(nextTabId, 'download_prompt', true);
    }
    this.host.publishPendingPrompt(prompt);
  }

  private completeDecisionWaiter(guid: string = ''): void {
    const waiter = this.decisionWaiter;
    if (waiter === undefined || (guid.length > 0 && waiter.guid !== guid)) {
      return;
    }
    this.decisionWaiter = undefined;
    waiter.resolve();
  }

  private resolveInlineDocumentPrompt(prompt: PendingDownloadPromptState): BrowserInlineDocumentPromptResolution {
    const facts = this.host.resolveFacts();
    return this.navigationStateCoordinator.resolveInlineDocumentPrompt(
      prompt.url,
      prompt.mimeType,
      prompt.contentDisposition,
      facts.activeTabId
    );
  }
}
