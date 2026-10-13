import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  PlatformDownloadEvent,
  PlatformDownloadSnapshot
} from '../../platform/download/PlatformDownloadAdapter';
import { DownloadFileNameService } from '../../services/download/DownloadFileNameService';
import {
  DownloadV2CaptureBoundary,
  DownloadV2CapturedRequest,
  DownloadV2Prompt
} from './DownloadV2CaptureTypes';
import { inferDownloadSourceHost } from './DownloadV2UrlUtils';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';

const DOWNLOAD_V2_CAPTURE_DOMAIN = 0x0000;
const DOWNLOAD_V2_CAPTURE_TAG = 'DownloadV2Capture';

export interface DownloadV2RequestCaptureCallbacks {
  onPromptChanged?: (prompt?: DownloadV2Prompt) => void;
}

export interface DownloadV2ManualRequestContext {
  userAgent?: string;
  referer?: string;
  mimeType?: string;
  contentDisposition?: string;
  totalBytes?: number;
  headers?: Record<string, string>;
}

export class DownloadV2RequestCapture {
  private callbacks: DownloadV2RequestCaptureCallbacks = {};
  private pendingRequests: Record<string, DownloadV2CapturedRequest | undefined> = {};
  private fileNameService: DownloadFileNameService = new DownloadFileNameService();

  setCallbacks(callbacks: DownloadV2RequestCaptureCallbacks): void {
    this.callbacks = callbacks;
  }

  capturePlatformRequest(
    snapshot: PlatformDownloadSnapshot,
    boundary: DownloadV2CaptureBoundary,
    notifyPrompt: boolean = true
  ): DownloadV2CapturedRequest {
    const request = this.createRequestFromSnapshot(snapshot, boundary);
    this.storePendingRequest(request);
    if (notifyPrompt) {
      this.callbacks.onPromptChanged?.(this.getPendingPrompt());
    }
    hilog.info(
      DOWNLOAD_V2_CAPTURE_DOMAIN,
      DOWNLOAD_V2_CAPTURE_TAG,
      'capture platform guid=%{public}s url=%{public}s file=%{public}s',
      request.guid,
      request.url,
      request.suggestedFileName
    );
    return request;
  }

  consumePlatformEvent(event: PlatformDownloadEvent, boundary: DownloadV2CaptureBoundary): DownloadV2CapturedRequest | undefined {
    if (event.type !== 'before_download') {
      return undefined;
    }
    return this.capturePlatformRequest(event.snapshot, boundary);
  }

  createManualRequest(
    url: string,
    boundary: DownloadV2CaptureBoundary,
    suggestedFileName?: string,
    sourceHost?: string,
    notifyPrompt: boolean = true,
    context?: DownloadV2ManualRequestContext
  ): DownloadV2CapturedRequest | undefined {
    const trimmedUrl = url.trim();
    if (trimmedUrl.length <= 0) {
      return undefined;
    }
    const request: DownloadV2CapturedRequest = {
      guid: `download-v2-prompt-${Date.now()}`,
      url: trimmedUrl,
      suggestedFileName: this.fileNameService.resolveFileName({
        suggestedFileName: suggestedFileName,
        url: trimmedUrl,
        mimeType: context?.mimeType,
        contentDisposition: context?.contentDisposition
      }),
      sourceHost: sourceHost?.trim() ?? inferDownloadSourceHost(trimmedUrl) ??
        resolveAppResourceText($r('app.string.offline_unknown_source')),
      totalBytes: context?.totalBytes !== undefined && context.totalBytes > 0 ? Math.floor(context.totalBytes) : 0,
      mimeType: context?.mimeType,
      method: 'GET',
      userAgent: context?.userAgent,
      referer: context?.referer,
      contentDisposition: context?.contentDisposition,
      headers: this.cloneHeaders(context?.headers),
      boundary: boundary,
      createdAt: Date.now()
    };
    this.storePendingRequest(request);
    if (notifyPrompt) {
      this.callbacks.onPromptChanged?.(this.getPendingPrompt());
    }
    hilog.info(
      DOWNLOAD_V2_CAPTURE_DOMAIN,
      DOWNLOAD_V2_CAPTURE_TAG,
      'capture manual guid=%{public}s url=%{public}s file=%{public}s',
      request.guid,
      request.url,
      request.suggestedFileName
    );
    return request;
  }

  getPendingPrompt(): DownloadV2Prompt | undefined {
    const request = this.getFirstPendingRequest();
    return request === undefined ? undefined : this.buildPrompt(request);
  }

  replacePendingRequest(request?: DownloadV2CapturedRequest): DownloadV2Prompt | undefined {
    this.pendingRequests = {};
    if (request !== undefined) {
      this.pendingRequests[request.guid] = this.cloneRequest(request);
    }
    const prompt = this.getPendingPrompt();
    this.callbacks.onPromptChanged?.(prompt);
    hilog.info(
      DOWNLOAD_V2_CAPTURE_DOMAIN,
      DOWNLOAD_V2_CAPTURE_TAG,
      'replace pending prompt=%{public}s count=%{public}d',
      prompt?.guid ?? 'none',
      this.getPendingRequestCount()
    );
    return prompt;
  }

  getPendingRequest(guid: string): DownloadV2CapturedRequest | undefined {
    const request = this.pendingRequests[guid];
    return request === undefined ? undefined : this.cloneRequest(request);
  }

  /**
   * Fills the page identity that only onDownloadStart carries. The download item itself
   * has no user agent, and a pending request is still mutable until the user confirms it.
   */
  applyPageIdentityToPendingUrl(
    url: string,
    userAgent: string,
    contentDisposition: string,
    mimeType: string
  ): number {
    const normalizedUrl = this.normalizeUrlForMatch(url);
    const normalizedUserAgent = userAgent.trim();
    if (normalizedUrl.length <= 0 || normalizedUserAgent.length <= 0) {
      return 0;
    }
    let updatedCount = 0;
    const keys = Object.keys(this.pendingRequests);
    for (let index = 0; index < keys.length; index += 1) {
      const request = this.pendingRequests[keys[index]];
      if (request === undefined || this.normalizeUrlForMatch(request.url) !== normalizedUrl) {
        continue;
      }
      this.fillMissingPageIdentity(request, normalizedUserAgent, contentDisposition, mimeType);
      updatedCount += 1;
    }
    return updatedCount;
  }

  hasPendingRequestForUrl(url: string): boolean {
    return this.hasPendingRequestForUrlMatching(url, false);
  }

  hasPendingPlatformRequestForUrl(url: string): boolean {
    return this.hasPendingRequestForUrlMatching(url, true);
  }

  removeManualPendingRequestsForUrl(url: string): number {
    const normalizedUrl = this.normalizeUrlForMatch(url);
    if (normalizedUrl.length <= 0) {
      return 0;
    }
    let removedCount = 0;
    const keys = Object.keys(this.pendingRequests);
    for (let index = 0; index < keys.length; index += 1) {
      const request = this.pendingRequests[keys[index]];
      if (request === undefined || request.platformSnapshot !== undefined ||
        this.normalizeUrlForMatch(request.url) !== normalizedUrl) {
        continue;
      }
      this.pendingRequests[keys[index]] = undefined;
      removedCount += 1;
    }
    if (removedCount > 0) {
      hilog.info(
        DOWNLOAD_V2_CAPTURE_DOMAIN,
        DOWNLOAD_V2_CAPTURE_TAG,
        'remove manual pending url=%{public}s count=%{public}d',
        normalizedUrl,
        removedCount
      );
    }
    return removedCount;
  }

  confirmRequest(guid: string): DownloadV2CapturedRequest | undefined {
    const request = this.pendingRequests[guid];
    if (request === undefined) {
      hilog.warn(
        DOWNLOAD_V2_CAPTURE_DOMAIN,
        DOWNLOAD_V2_CAPTURE_TAG,
        'confirm request missing guid=%{public}s count=%{public}d first=%{public}s',
        guid,
        this.getPendingRequestCount(),
        this.getFirstPendingRequest()?.guid ?? 'none'
      );
      return undefined;
    }
    this.pendingRequests[guid] = undefined;
    this.callbacks.onPromptChanged?.(this.getPendingPrompt());
    hilog.info(
      DOWNLOAD_V2_CAPTURE_DOMAIN,
      DOWNLOAD_V2_CAPTURE_TAG,
      'confirm request guid=%{public}s count=%{public}d next=%{public}s',
      guid,
      this.getPendingRequestCount(),
      this.getFirstPendingRequest()?.guid ?? 'none'
    );
    return this.cloneRequest(request);
  }

  cancelRequest(guid: string): DownloadV2CapturedRequest | undefined {
    const request = this.pendingRequests[guid];
    if (request === undefined) {
      hilog.warn(
        DOWNLOAD_V2_CAPTURE_DOMAIN,
        DOWNLOAD_V2_CAPTURE_TAG,
        'cancel request missing guid=%{public}s count=%{public}d first=%{public}s',
        guid,
        this.getPendingRequestCount(),
        this.getFirstPendingRequest()?.guid ?? 'none'
      );
      return undefined;
    }
    this.pendingRequests[guid] = undefined;
    this.callbacks.onPromptChanged?.(this.getPendingPrompt());
    hilog.info(
      DOWNLOAD_V2_CAPTURE_DOMAIN,
      DOWNLOAD_V2_CAPTURE_TAG,
      'cancel request guid=%{public}s count=%{public}d next=%{public}s',
      guid,
      this.getPendingRequestCount(),
      this.getFirstPendingRequest()?.guid ?? 'none'
    );
    return this.cloneRequest(request);
  }

  private getFirstPendingRequest(): DownloadV2CapturedRequest | undefined {
    const guid = Object.keys(this.pendingRequests).find((key: string) => this.pendingRequests[key] !== undefined);
    if (guid === undefined) {
      return undefined;
    }
    return this.pendingRequests[guid];
  }

  private storePendingRequest(request: DownloadV2CapturedRequest): void {
    this.pendingRequests[request.guid] = request;
  }

  private getPendingRequestCount(): number {
    return Object.keys(this.pendingRequests)
      .filter((key: string) => this.pendingRequests[key] !== undefined)
      .length;
  }

  private createRequestFromSnapshot(
    snapshot: PlatformDownloadSnapshot,
    boundary: DownloadV2CaptureBoundary
  ): DownloadV2CapturedRequest {
    const nextHeaders = this.cloneHeaders(snapshot.headers);
    return {
      guid: snapshot.guid,
      url: snapshot.url,
      originalUrl: snapshot.originalUrl,
      suggestedFileName: this.fileNameService.resolveFileName({
        suggestedFileName: snapshot.suggestedFileName,
        url: snapshot.url,
        mimeType: snapshot.mimeType,
        contentDisposition: snapshot.contentDisposition
      }),
      sourceHost: inferDownloadSourceHost(snapshot.url) ??
        resolveAppResourceText($r('app.string.offline_unknown_source')),
      totalBytes: snapshot.totalBytes,
      mimeType: snapshot.mimeType,
      method: snapshot.method?.trim() ?? 'GET',
      userAgent: snapshot.userAgent,
      referer: snapshot.referer,
      contentDisposition: snapshot.contentDisposition,
      headers: nextHeaders,
      sourcePageUrl: boundary.sourcePageUrl,
      boundary: boundary,
      platformSnapshot: snapshot,
      createdAt: Date.now()
    };
  }

  private buildPrompt(request: DownloadV2CapturedRequest): DownloadV2Prompt {
    return {
      guid: request.guid,
      fileName: request.suggestedFileName,
      sourceHost: request.sourceHost,
      url: request.url,
      totalBytes: request.totalBytes,
      mimeType: request.mimeType,
      contentDisposition: request.contentDisposition,
      title: resolveAppResourceText($r('app.string.download_prompt_title')),
      message: resolveAppResourceText($r('app.string.download_prompt_message')),
      confirmLabel: resolveAppResourceText($r('app.string.media_resource_action_download')),
      cancelLabel: resolveAppResourceText($r('app.string.settings_account_cancel'))
    };
  }

  private cloneRequest(request: DownloadV2CapturedRequest): DownloadV2CapturedRequest {
    const nextHeaders = this.cloneHeaders(request.headers);
    let nextPlatformSnapshot: PlatformDownloadSnapshot | undefined = undefined;
    if (request.platformSnapshot !== undefined) {
      nextPlatformSnapshot = {
        guid: request.platformSnapshot.guid,
        url: request.platformSnapshot.url,
        originalUrl: request.platformSnapshot.originalUrl,
        suggestedFileName: request.platformSnapshot.suggestedFileName,
        totalBytes: request.platformSnapshot.totalBytes,
        receivedBytes: request.platformSnapshot.receivedBytes,
        currentSpeed: request.platformSnapshot.currentSpeed,
        state: request.platformSnapshot.state,
        lastErrorCode: request.platformSnapshot.lastErrorCode,
        mimeType: request.platformSnapshot.mimeType,
        method: request.platformSnapshot.method,
        userAgent: request.platformSnapshot.userAgent,
        referer: request.platformSnapshot.referer,
        contentDisposition: request.platformSnapshot.contentDisposition,
        headers: this.cloneHeaders(request.platformSnapshot.headers),
        platformTaskId: request.platformSnapshot.platformTaskId,
        platformTaskToken: request.platformSnapshot.platformTaskToken
      };
    }
    return {
      guid: request.guid,
      url: request.url,
      originalUrl: request.originalUrl,
      suggestedFileName: request.suggestedFileName,
      sourceHost: request.sourceHost,
      totalBytes: request.totalBytes,
      mimeType: request.mimeType,
      method: request.method,
      userAgent: request.userAgent,
      referer: request.referer,
      contentDisposition: request.contentDisposition,
      headers: nextHeaders,
      sourcePageUrl: request.sourcePageUrl,
      boundary: {
        windowId: request.boundary.windowId,
        profileId: request.boundary.profileId,
        privacyMode: request.boundary.privacyMode,
        dataScope: request.boundary.dataScope
      },
      platformSnapshot: nextPlatformSnapshot,
      createdAt: request.createdAt
    };
  }

  private cloneHeaders(headers?: Record<string, string>): Record<string, string> | undefined {
    if (headers === undefined) {
      return undefined;
    }
    const nextHeaders: Record<string, string> = {};
    Object.keys(headers).forEach((key: string) => {
      nextHeaders[key] = headers[key];
    });
    return nextHeaders;
  }

  private fillMissingPageIdentity(
    request: DownloadV2CapturedRequest,
    userAgent: string,
    contentDisposition: string,
    mimeType: string
  ): void {
    if ((request.userAgent?.trim().length ?? 0) <= 0) {
      request.userAgent = userAgent;
    }
    const normalizedDisposition = contentDisposition.trim();
    if ((request.contentDisposition?.trim().length ?? 0) <= 0 && normalizedDisposition.length > 0) {
      request.contentDisposition = normalizedDisposition;
    }
    const normalizedMimeType = mimeType.trim();
    if ((request.mimeType?.trim().length ?? 0) <= 0 && normalizedMimeType.length > 0) {
      request.mimeType = normalizedMimeType;
    }
    const snapshot = request.platformSnapshot;
    if (snapshot === undefined) {
      return;
    }
    if ((snapshot.userAgent?.trim().length ?? 0) <= 0) {
      snapshot.userAgent = userAgent;
    }
    if ((snapshot.contentDisposition?.trim().length ?? 0) <= 0 && normalizedDisposition.length > 0) {
      snapshot.contentDisposition = normalizedDisposition;
    }
    if ((snapshot.mimeType?.trim().length ?? 0) <= 0 && normalizedMimeType.length > 0) {
      snapshot.mimeType = normalizedMimeType;
    }
  }

  private normalizeUrlForMatch(url: string): string {
    const trimmed = url.trim();
    const hashIndex = trimmed.indexOf('#');
    return hashIndex >= 0 ? trimmed.substring(0, hashIndex) : trimmed;
  }

  private hasPendingRequestForUrlMatching(url: string, platformOnly: boolean): boolean {
    const normalizedUrl = this.normalizeUrlForMatch(url);
    if (normalizedUrl.length <= 0) {
      return false;
    }
    const keys = Object.keys(this.pendingRequests);
    for (let index = 0; index < keys.length; index += 1) {
      const request = this.pendingRequests[keys[index]];
      if (request === undefined || this.normalizeUrlForMatch(request.url) !== normalizedUrl) {
        continue;
      }
      if (!platformOnly || request.platformSnapshot !== undefined) {
        return true;
      }
    }
    return false;
  }
}
