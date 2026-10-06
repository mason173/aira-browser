import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  PlatformDownloadAdapter,
  PlatformDownloadAdapterCallbacks,
  PlatformDownloadDelegate,
  PlatformDownloadEvent,
  PlatformDownloadEventType,
  PlatformDownloadSnapshot
} from './PlatformDownloadAdapter';
import { DownloadNativeProxyResolver, LibcurlDownloadAdapter } from './LibcurlDownloadAdapter';
import { DownloadRuntimeDiagnosticRecorder } from '../../common/models/RuntimeDiagnosticModels';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';

const DOWNLOAD_BRIDGE_DOMAIN = 0x0000;
const DOWNLOAD_BRIDGE_TAG = 'DownloadBridge';

interface ArkWebDownloadItemApi24 {
  getOriginalUrl?: () => string;
  getReferrerUrl?: () => string;
}

export class ArkWebDownloadBridge implements PlatformDownloadAdapter {
  private delegate: PlatformDownloadDelegate = new webview.WebDownloadDelegate();
  private callbacks: PlatformDownloadAdapterCallbacks = {};
  private initialized: boolean = false;
  private itemsByGuid: Record<string, webview.WebDownloadItem | undefined> = {};
  private handedOffGuids: Record<string, boolean | undefined> = {};
  private pendingCancelInFlightGuid: string = '';
  private libcurlAdapter: LibcurlDownloadAdapter;

  constructor(
    diagnosticRecorder?: DownloadRuntimeDiagnosticRecorder,
    proxyResolver?: DownloadNativeProxyResolver
  ) {
    this.libcurlAdapter = new LibcurlDownloadAdapter(proxyResolver);
  }

  getDelegate(): PlatformDownloadDelegate {
    this.initialize();
    return this.delegate;
  }

  setCallbacks(callbacks: PlatformDownloadAdapterCallbacks): void {
    this.callbacks = callbacks;
    this.libcurlAdapter.setCallbacks(callbacks);
  }

  hasActiveDownload(guid: string): boolean {
    if (this.libcurlAdapter.hasActiveDownload(guid)) {
      return true;
    }
    if (this.handedOffGuids[guid] === true) {
      return false;
    }
    const item = this.itemsByGuid[guid];
    if (item === undefined) {
      return false;
    }
    const snapshot = this.readSnapshot(item);
    if (!this.isLiveState(snapshot.state)) {
      hilog.info(
        DOWNLOAD_BRIDGE_DOMAIN,
        DOWNLOAD_BRIDGE_TAG,
        'drop stale active guid=%{public}s state=%{public}s received=%{public}d total=%{public}d',
        snapshot.guid,
        snapshot.state,
        snapshot.receivedBytes,
        snapshot.totalBytes
      );
      return false;
    }
    return true;
  }

  getActiveDownloadSnapshot(guid: string): PlatformDownloadSnapshot | undefined {
    const requestSnapshot = this.libcurlAdapter.getActiveDownloadSnapshot(guid);
    if (requestSnapshot !== undefined) {
      return requestSnapshot;
    }
    if (this.handedOffGuids[guid] === true) {
      return undefined;
    }
    const item = this.itemsByGuid[guid];
    if (item === undefined) {
      return undefined;
    }
    const snapshot = this.readSnapshot(item);
    if (!this.isLiveState(snapshot.state)) {
      hilog.info(
        DOWNLOAD_BRIDGE_DOMAIN,
        DOWNLOAD_BRIDGE_TAG,
        'skip inactive snapshot guid=%{public}s state=%{public}s received=%{public}d total=%{public}d',
        snapshot.guid,
        snapshot.state,
        snapshot.receivedBytes,
        snapshot.totalBytes
      );
      if (this.isTerminalState(snapshot.state)) {
        this.itemsByGuid[guid] = undefined;
      }
      return undefined;
    }
    return snapshot;
  }

  getActiveDownloadSnapshots(): PlatformDownloadSnapshot[] {
    const snapshots: PlatformDownloadSnapshot[] = this.libcurlAdapter.getActiveDownloadSnapshots();
    const guids = Object.keys(this.itemsByGuid);
    guids.forEach((guid: string) => {
      if (this.handedOffGuids[guid] === true) {
        return;
      }
      const snapshot = this.getActiveDownloadSnapshot(guid);
      if (snapshot !== undefined) {
        snapshots.push(snapshot);
      }
    });
    return snapshots;
  }

  reconnectDownload(
    guid: string,
    platformTaskId: string,
    platformTaskToken?: string
  ): Promise<PlatformDownloadSnapshot | undefined> {
    return this.libcurlAdapter.reconnectDownload(guid, platformTaskId, platformTaskToken);
  }

  async startDirectDownload(
    snapshot: PlatformDownloadSnapshot,
    targetPath: string
  ): Promise<PlatformDownloadSnapshot | undefined> {
    if (this.requiresNativeDownload(snapshot)) {
      return this.startNativeArkWebDownload(snapshot.guid, targetPath);
    }
    const createdTask = await this.libcurlAdapter.startDirectDownload(snapshot, targetPath);
    if (createdTask === undefined) {
      return undefined;
    }
    const item = this.itemsByGuid[snapshot.guid];
    if (item !== undefined) {
      this.finalizeLibcurlHandoff(snapshot.guid, item);
    }
    return createdTask;
  }

  async startDownload(guid: string, targetPath: string): Promise<boolean> {
    const item = this.itemsByGuid[guid];
    if (item === undefined || targetPath.length === 0) {
      return false;
    }
    try {
      const snapshot = this.readSnapshot(item);
      if (this.requiresNativeDownload(snapshot)) {
        return this.startNativeArkWebDownload(guid, targetPath) !== undefined;
      }
      const createdTask = await this.libcurlAdapter.startDirectDownload(snapshot, targetPath);
      if (createdTask === undefined) {
        return false;
      }
      this.finalizeLibcurlHandoff(guid, item);
      return true;
    } catch (nativeError) {
      hilog.warn(
        DOWNLOAD_BRIDGE_DOMAIN,
        DOWNLOAD_BRIDGE_TAG,
        'libcurl start failed guid=%{public}s error=%{public}s',
        guid,
        JSON.stringify(nativeError)
      );
      return false;
    }
  }

  retryDownload(
    guid: string,
    targetPath: string,
    platformTaskId?: string,
    platformTaskToken?: string,
    hlsSegmentConcurrency?: number
  ): Promise<boolean> {
    const item = this.itemsByGuid[guid];
    if (item !== undefined && this.requiresNativeDownload(this.readSnapshot(item))) {
      return Promise.resolve(this.startNativeArkWebDownload(guid, targetPath) !== undefined);
    }
    return this.libcurlAdapter.retryDownload(
      guid,
      targetPath,
      platformTaskId,
      platformTaskToken,
      hlsSegmentConcurrency
    );
  }

  pauseDownload(guid: string, platformTaskId?: string, platformTaskToken?: string): Promise<boolean> {
    const item = this.itemsByGuid[guid];
    if (item !== undefined && this.handedOffGuids[guid] !== true) {
      try {
        item.pause();
        return Promise.resolve(true);
      } catch (_error) {
      }
    }
    return this.libcurlAdapter.pauseDownload(guid, platformTaskId, platformTaskToken);
  }

  resumeDownload(guid: string, platformTaskId?: string, platformTaskToken?: string): Promise<boolean> {
    const item = this.itemsByGuid[guid];
    if (item !== undefined && this.handedOffGuids[guid] !== true) {
      try {
        item.resume();
        return Promise.resolve(true);
      } catch (_error) {
        try {
          webview.WebDownloadManager.resumeDownload(item);
          return Promise.resolve(true);
        } catch (_resumeError) {
        }
      }
    }
    return this.libcurlAdapter.resumeDownload(guid, platformTaskId, platformTaskToken);
  }

  cancelDownload(guid: string, platformTaskId?: string, platformTaskToken?: string): Promise<boolean> {
    const item = this.itemsByGuid[guid];
    if (item !== undefined && this.handedOffGuids[guid] !== true) {
      try {
        item.cancel();
        return Promise.resolve(true);
      } catch (_error) {
      }
    }
    return this.libcurlAdapter.cancelDownload(guid, platformTaskId, platformTaskToken);
  }

  cancelPendingDownload(guid: string): boolean {
    const item = this.itemsByGuid[guid];
    if (item === undefined) {
      return false;
    }
    this.pendingCancelInFlightGuid = guid;
    try {
      item.cancel();
    } catch (_error) {
      return false;
    } finally {
      if (this.pendingCancelInFlightGuid === guid) {
        this.pendingCancelInFlightGuid = '';
      }
    }
    this.itemsByGuid[guid] = undefined;
    this.handedOffGuids[guid] = undefined;
    return true;
  }

  private initialize(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    webview.WebDownloadManager.setDownloadDelegate(this.delegate);

    this.delegate.onBeforeDownload((item: webview.WebDownloadItem) => {
      this.handleDownloadEvent('before_download', item);
    });

    this.delegate.onDownloadUpdated((item: webview.WebDownloadItem) => {
      this.handleDownloadEvent('updated', item);
    });

    this.delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      this.handleDownloadEvent('finished', item);
    });

    this.delegate.onDownloadFailed((item: webview.WebDownloadItem) => {
      this.handleDownloadEvent('failed', item);
    });
  }

  private handleDownloadEvent(type: PlatformDownloadEventType, item: webview.WebDownloadItem): void {
    const snapshot = this.readSnapshot(item);
    if (this.shouldSuppressPendingCancelEvent(type, snapshot.guid, snapshot.state)) {
      hilog.info(
        DOWNLOAD_BRIDGE_DOMAIN,
        DOWNLOAD_BRIDGE_TAG,
        'ignore expected pending cancel event=%{public}s guid=%{public}s state=%{public}s',
        type,
        snapshot.guid,
        snapshot.state
      );
      this.itemsByGuid[snapshot.guid] = undefined;
      return;
    }
    if (this.handedOffGuids[snapshot.guid] === true && type !== 'before_download') {
      hilog.info(
        DOWNLOAD_BRIDGE_DOMAIN,
        DOWNLOAD_BRIDGE_TAG,
        'ignore web event after handoff event=%{public}s guid=%{public}s state=%{public}s',
        type,
        snapshot.guid,
        snapshot.state
      );
      this.itemsByGuid[snapshot.guid] = undefined;
      return;
    }
    hilog.info(
      DOWNLOAD_BRIDGE_DOMAIN,
      DOWNLOAD_BRIDGE_TAG,
      'event=%{public}s guid=%{public}s state=%{public}s received=%{public}d total=%{public}d speed=%{public}d',
      type,
      snapshot.guid,
      snapshot.state,
      snapshot.receivedBytes,
      snapshot.totalBytes,
      snapshot.currentSpeed
    );
    this.itemsByGuid[snapshot.guid] = item;
    if (this.isTerminalState(snapshot.state)) {
      this.itemsByGuid[snapshot.guid] = undefined;
    }
    const event: PlatformDownloadEvent = {
      type: type,
      snapshot: snapshot
    };
    this.callbacks.onDownloadEvent?.(event);
  }

  private shouldSuppressPendingCancelEvent(type: PlatformDownloadEventType, guid: string, state: string): boolean {
    return this.pendingCancelInFlightGuid === guid &&
      type === 'failed' &&
      state.trim().toUpperCase() === 'CANCELED';
  }

  private readSnapshot(item: webview.WebDownloadItem): PlatformDownloadSnapshot {
    const url = this.readUrl(item);
    const originalUrl = this.readOriginalUrl(item);
    const referrerUrl = this.readReferrerUrl(item);
    return {
      guid: this.readGuid(item),
      url: url,
      originalUrl: originalUrl.length > 0 && originalUrl !== url ? originalUrl : undefined,
      suggestedFileName: this.readSuggestedFileName(item),
      totalBytes: this.readTotalBytes(item),
      receivedBytes: this.readReceivedBytes(item),
      currentSpeed: this.readCurrentSpeed(item),
      state: this.readState(item),
      lastErrorCode: this.readLastErrorCode(item),
      mimeType: this.readMimeType(item),
      method: this.readMethod(item),
      referer: referrerUrl.length > 0 ? referrerUrl : undefined
    };
  }

  private readGuid(item: webview.WebDownloadItem): string {
    try {
      return item.getGuid();
    } catch (_error) {
      return `download-${Date.now()}`;
    }
  }

  private readUrl(item: webview.WebDownloadItem): string {
    try {
      return item.getUrl();
    } catch (_error) {
      return '';
    }
  }

  private readOriginalUrl(item: webview.WebDownloadItem): string {
    try {
      const api24Item = item as ArkWebDownloadItemApi24;
      return api24Item.getOriginalUrl?.().trim() ?? '';
    } catch (_error) {
      return '';
    }
  }

  private readReferrerUrl(item: webview.WebDownloadItem): string {
    try {
      const api24Item = item as ArkWebDownloadItemApi24;
      return api24Item.getReferrerUrl?.().trim() ?? '';
    } catch (_error) {
      return '';
    }
  }

  private readSuggestedFileName(item: webview.WebDownloadItem): string {
    try {
      const name = item.getSuggestedFileName();
      return name.length > 0 ? name : resolveAppResourceText($r('app.string.download_status_unnamed'));
    } catch (_error) {
      return resolveAppResourceText($r('app.string.download_status_unnamed'));
    }
  }

  private readMethod(item: webview.WebDownloadItem): string {
    try {
      return item.getMethod();
    } catch (_error) {
      return 'GET';
    }
  }

  private readMimeType(item: webview.WebDownloadItem): string {
    try {
      return item.getMimeType();
    } catch (_error) {
      return '';
    }
  }

  private readTotalBytes(item: webview.WebDownloadItem): number {
    try {
      return item.getTotalBytes();
    } catch (_error) {
      return 0;
    }
  }

  private readReceivedBytes(item: webview.WebDownloadItem): number {
    try {
      return item.getReceivedBytes();
    } catch (_error) {
      return 0;
    }
  }

  private readCurrentSpeed(item: webview.WebDownloadItem): number {
    try {
      return item.getCurrentSpeed();
    } catch (_error) {
      return 0;
    }
  }

  private readState(item: webview.WebDownloadItem): string {
    try {
      const state = item.getState();
      if (state === webview.WebDownloadState.IN_PROGRESS) {
        return 'IN_PROGRESS';
      }
      if (state === webview.WebDownloadState.COMPLETED) {
        return 'COMPLETED';
      }
      if (state === webview.WebDownloadState.CANCELED) {
        return 'CANCELED';
      }
      if (state === webview.WebDownloadState.INTERRUPTED) {
        return 'FAILED';
      }
      if (state === webview.WebDownloadState.PENDING) {
        return 'PENDING';
      }
      if (state === webview.WebDownloadState.PAUSED) {
        return 'PAUSED';
      }
      return 'UNKNOWN';
    } catch (_error) {
      return 'PENDING';
    }
  }

  private readLastErrorCode(item: webview.WebDownloadItem): number {
    try {
      return item.getLastErrorCode();
    } catch (_error) {
      return 0;
    }
  }

  private dropInactiveItem(guid: string, state: string): void {
    hilog.info(
      DOWNLOAD_BRIDGE_DOMAIN,
      DOWNLOAD_BRIDGE_TAG,
      'drop inactive item guid=%{public}s state=%{public}s',
      guid,
      state
    );
    this.itemsByGuid[guid] = undefined;
    if (this.isTerminalState(state)) {
      this.handedOffGuids[guid] = undefined;
    }
  }

  private isTerminalState(state: string): boolean {
    const normalizedState = state.trim().toUpperCase();
    return normalizedState.indexOf('COMPLETE') >= 0 ||
      normalizedState.indexOf('FINISH') >= 0 ||
      normalizedState.indexOf('FAIL') >= 0 ||
      normalizedState.indexOf('ERROR') >= 0 ||
      normalizedState.indexOf('CANCEL') >= 0;
  }

  private isLiveState(state: string): boolean {
    const normalizedState = state.trim().toUpperCase();
    return normalizedState === 'PENDING' ||
      normalizedState === 'PAUSED' ||
      normalizedState === 'IN_PROGRESS';
  }

  private finalizeLibcurlHandoff(guid: string, item: webview.WebDownloadItem): void {
    this.handedOffGuids[guid] = true;
    try {
      item.cancel();
    } catch (_cancelError) {
      // ArkWeb may already have stopped this provisional item after handoff.
    }
    this.itemsByGuid[guid] = undefined;
  }

  private requiresNativeDownload(snapshot: PlatformDownloadSnapshot): boolean {
    const method = snapshot.method?.trim().toUpperCase() ?? 'GET';
    if (method !== 'GET') {
      return true;
    }
    // Blob and data URLs resolve only inside the renderer that produced them (a generated file
    // saved through URL.createObjectURL or a data: href with a download attribute), so libcurl
    // can never fetch them and its http/https-only transfer rejects them outright. ArkWeb already
    // owns the download item and can write those bytes itself, so route every non-http(s) download
    // to the native path.
    return !this.isHttpUrl(snapshot.url);
  }

  private isHttpUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private startNativeArkWebDownload(guid: string, targetPath: string): PlatformDownloadSnapshot | undefined {
    const normalizedGuid = guid.trim();
    if (normalizedGuid.length <= 0 || targetPath.trim().length <= 0) {
      return undefined;
    }
    const item = this.itemsByGuid[normalizedGuid];
    if (item === undefined) {
      hilog.warn(
        DOWNLOAD_BRIDGE_DOMAIN,
        DOWNLOAD_BRIDGE_TAG,
        'native start missing item guid=%{public}s',
        normalizedGuid
      );
      return undefined;
    }
    try {
      // Non-GET requests (for example Office-on-the-web "download a copy") cannot be
      // replayed through libcurl because ArkWeb does not expose the request body, so let
      // ArkWeb finish the download it already owns. Keeping the item tracked lets the
      // existing delegate callbacks drive progress and completion.
      item.start(targetPath);
    } catch (error) {
      hilog.warn(
        DOWNLOAD_BRIDGE_DOMAIN,
        DOWNLOAD_BRIDGE_TAG,
        'native start failed guid=%{public}s error=%{public}s',
        normalizedGuid,
        JSON.stringify(error)
      );
      return undefined;
    }
    const snapshot = this.readSnapshot(item);
    hilog.info(
      DOWNLOAD_BRIDGE_DOMAIN,
      DOWNLOAD_BRIDGE_TAG,
      'native start guid=%{public}s method=%{public}s state=%{public}s path=%{public}s',
      normalizedGuid,
      snapshot.method ?? '',
      snapshot.state,
      targetPath
    );
    return snapshot;
  }

}
