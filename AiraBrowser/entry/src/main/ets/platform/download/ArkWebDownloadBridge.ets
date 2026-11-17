import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
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
const ARKWEB_TASK_PREFIX = 'arkweb:';
const ARKWEB_TOKEN_PREFIX = 'arkweb-v1:';
const MAX_ARKWEB_TOKEN_BYTES = 1536 * 1024;
const DIRECT_ARKWEB_START_TIMEOUT_MS = 15000;

interface ArkWebDownloadItemApi24 {
  getOriginalUrl?: () => string;
  getReferrerUrl?: () => string;
}

interface ArkWebDirectStart {
  snapshot: PlatformDownloadSnapshot;
  targetPath: string;
  state: 'queued' | 'starting' | 'binding' | 'paused_queued' | 'paused_starting' | 'retired';
  resolve: (snapshot: PlatformDownloadSnapshot | undefined) => void;
  promise?: Promise<PlatformDownloadSnapshot | undefined>;
  timer?: number;
  settled: boolean;
  resumeRequested?: boolean;
}

interface ArkWebDownloadSource {
  start: (url: string) => void;
  queue: ArkWebDirectStart[];
  active?: ArkWebDirectStart;
}

interface ArkWebRetiredStart {
  request: ArkWebDirectStart;
  hold: boolean;
}

export class ArkWebDownloadBridge implements PlatformDownloadAdapter {
  private delegate: PlatformDownloadDelegate = new webview.WebDownloadDelegate();
  private callbacks: PlatformDownloadAdapterCallbacks = {};
  private initialized: boolean = false;
  private itemsByGuid: Record<string, webview.WebDownloadItem | undefined> = {};
  private sourceDelegates: Record<string, PlatformDownloadDelegate | undefined> = {};
  private sourceIdsByGuid: Record<string, string | undefined> = {};
  private downloadSources: Record<string, ArkWebDownloadSource | undefined> = {};
  private closedSourceIds: Record<string, boolean | undefined> = {};
  private directStartsByGuid: Record<string, ArkWebDirectStart | undefined> = {};
  private retiredStartsBySource: Record<string, ArkWebRetiredStart[] | undefined> = {};
  private appGuidsByNativeGuid: Record<string, string | undefined> = {};
  private nativeGuidsByAppGuid: Record<string, string | undefined> = {};
  private requestedSnapshotsByGuid: Record<string, PlatformDownloadSnapshot | undefined> = {};
  private heldSnapshots: Record<string, PlatformDownloadSnapshot | undefined> = {};
  private pendingTargetPaths: Record<string, string | undefined> = {};
  private ignoredCancellationGuids: Record<string, boolean | undefined> = {};
  private retiredItemsByGuid: Record<string, webview.WebDownloadItem[] | undefined> = {};
  private closedGuids: Record<string, boolean | undefined> = {};
  private latestEventSnapshots: Record<string, PlatformDownloadSnapshot | undefined> = {};
  private restoringGuids: Record<string, boolean | undefined> = {};
  private handedOffGuids: Record<string, boolean | undefined> = {};
  private pendingCancelInFlightGuid: string = '';
  private libcurlAdapter: LibcurlDownloadAdapter;
  private base64Helper: util.Base64Helper = new util.Base64Helper();

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

  getDelegateForSource(sourceId: string): PlatformDownloadDelegate {
    this.initialize();
    let delegate = this.sourceDelegates[sourceId];
    if (delegate === undefined) {
      delegate = new webview.WebDownloadDelegate();
      this.configureDelegate(delegate, sourceId);
      this.sourceDelegates[sourceId] = delegate;
    }
    return delegate;
  }

  registerDownloadSource(sourceId: string, start: (url: string) => void): void {
    if (sourceId.trim().length === 0) return;
    this.initialize();
    const existing = this.downloadSources[sourceId];
    if (existing !== undefined) {
      existing.start = start;
      return;
    }
    this.closedSourceIds[sourceId] = undefined;
    this.downloadSources[sourceId] = { start: start, queue: [] };
  }

  unregisterDownloadSource(sourceId: string): void {
    this.closedSourceIds[sourceId] = true;
    this.downloadSources[sourceId] = undefined;
    Object.keys(this.directStartsByGuid).forEach((guid: string): void => {
      const request = this.directStartsByGuid[guid];
      if (request?.snapshot.sourceId === sourceId) {
        this.retireDirectStart(request, false, 'CANCELED');
      }
    });
    const retired = this.retiredStartsBySource[sourceId] ?? [];
    retired.forEach((entry: ArkWebRetiredStart): void => {
      entry.hold = false;
      this.closedGuids[entry.request.snapshot.guid] = true;
      this.directStartsByGuid[entry.request.snapshot.guid] = undefined;
    });
  }

  holdDownload(guid: string): PlatformDownloadSnapshot | undefined {
    const direct = this.directStartsByGuid[guid];
    if (direct !== undefined && direct.state !== 'binding') {
      // Before ArkWeb exposes an item, retain the original request and apply the
      // hold when its callback arrives. Never replace an issued request with a GET.
      this.pauseDirectStart(direct);
      const snapshot = this.snapshotForDirectStart(direct, 'PAUSED');
      snapshot.transportHeld = true;
      return snapshot;
    }
    const held = this.heldSnapshots[guid];
    if (held !== undefined) {
      return held;
    }
    const item = this.itemsByGuid[guid];
    if (item === undefined || this.handedOffGuids[guid] === true) {
      return undefined;
    }
    const snapshot = this.readSnapshot(item);
    if (snapshot.state !== 'PENDING' && snapshot.state !== 'IN_PROGRESS' && snapshot.state !== 'PAUSED') {
      return undefined;
    }
    // PENDING already transfers into ArkWeb's temporary directory. pause() is not valid
    // there. The documented cancel -> manager.resumeDownload sequence stops that traffic
    // while preserving the original task owner instead of replaying its URL. Whether
    // a renderer-only or POST task can resume still depends on its platform context.
    snapshot.state = 'PAUSED';
    snapshot.currentSpeed = 0;
    snapshot.transportHeld = true;
    this.heldSnapshots[guid] = snapshot;
    this.ignoredCancellationGuids[guid] = true;
    try {
      item.cancel();
      return snapshot;
    } catch (_error) {
      this.heldSnapshots[guid] = undefined;
      this.ignoredCancellationGuids[guid] = undefined;
      return undefined;
    }
  }

  setCallbacks(callbacks: PlatformDownloadAdapterCallbacks): void {
    this.callbacks = callbacks;
    this.libcurlAdapter.setCallbacks(callbacks);
  }

  hasActiveDownload(guid: string): boolean {
    if (this.directStartsByGuid[guid] !== undefined) return true;
    if (this.heldSnapshots[guid] !== undefined) {
      return true;
    }
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
    const direct = this.directStartsByGuid[guid];
    if (direct !== undefined) return this.snapshotForDirectStart(direct);
    const held = this.heldSnapshots[guid];
    if (held !== undefined) {
      return held;
    }
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
      if (this.isTerminalState(snapshot.state) && snapshot.state !== 'FAILED') {
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
    Object.keys(this.directStartsByGuid).forEach((guid: string): void => {
      if (this.itemsByGuid[guid] === undefined) {
        const snapshot = this.getActiveDownloadSnapshot(guid);
        if (snapshot !== undefined) snapshots.push(snapshot);
      }
    });
    return snapshots;
  }

  reconnectDownload(
    guid: string,
    platformTaskId: string,
    platformTaskToken?: string
  ): Promise<PlatformDownloadSnapshot | undefined> {
    if (this.isArkWebTask(platformTaskId, platformTaskToken)) {
      const active = this.getActiveDownloadSnapshot(guid);
      if (active !== undefined) {
        return Promise.resolve(active);
      }
      const item = this.deserializeDownload(guid, platformTaskToken, platformTaskId);
      if (item === undefined) {
        return Promise.resolve(undefined);
      }
      const snapshot = this.readSnapshot(item);
      // Reattach the saved task without starting network activity during app initialization.
      // Keep the deserialized object out of the live-item table: only the user's resume action
      // can attach it through WebDownloadManager, rather than calling its paused-item resume().
      snapshot.state = 'PAUSED';
      snapshot.platformTaskToken = platformTaskToken;
      return Promise.resolve(snapshot);
    }
    return this.libcurlAdapter.reconnectDownload(guid, platformTaskId, platformTaskToken);
  }

  async startDirectDownload(
    snapshot: PlatformDownloadSnapshot,
    targetPath: string
  ): Promise<PlatformDownloadSnapshot | undefined> {
    const explicitNative = snapshot.downloadDriver === 'libcurl';
    if (!explicitNative || this.requiresNativeDownload(snapshot)) {
      this.requestedSnapshotsByGuid[snapshot.guid] = snapshot;
      if (this.itemsByGuid[snapshot.guid] !== undefined || this.heldSnapshots[snapshot.guid] !== undefined ||
        this.isArkWebTask(snapshot.platformTaskId, snapshot.platformTaskToken)) {
        return this.startOrRestoreArkWebDownload(snapshot.guid, targetPath, snapshot.platformTaskToken, snapshot.platformTaskId);
      }
      return this.enqueueDirectArkWebStart(snapshot, targetPath);
    }
    const item = this.itemsByGuid[snapshot.guid];
    if (item !== undefined) {
      // Stop the old owner before asynchronous native-module loading or file creation.
      // A failed GET can explicitly switch transports; POST/blob/data keep ArkWeb above.
      this.finalizeLibcurlHandoff(snapshot.guid, item);
    }
    const createdTask = await this.libcurlAdapter.startDirectDownload(snapshot, targetPath);
    if (createdTask === undefined) {
      return undefined;
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
      if (!this.isHlsDownload(snapshot) || this.requiresNativeDownload(snapshot)) {
        return this.startOrRestoreArkWebDownload(guid, targetPath) !== undefined;
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
    if (item !== undefined) {
      const snapshot = this.readSnapshot(item);
      if (!this.isHlsDownload(snapshot) || this.requiresNativeDownload(snapshot)) {
        return Promise.resolve(this.startOrRestoreArkWebDownload(guid, targetPath, platformTaskToken, platformTaskId) !== undefined);
      }
    }
    if (this.isArkWebTask(platformTaskId, platformTaskToken)) {
      return Promise.resolve(this.restoreArkWebDownload(guid, platformTaskToken, targetPath, platformTaskId) !== undefined);
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
    const direct = this.directStartsByGuid[guid];
    if (direct !== undefined && direct.state !== 'binding') {
      this.pauseDirectStart(direct);
      return Promise.resolve(true);
    }
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
    const direct = this.directStartsByGuid[guid];
    if (direct?.state === 'paused_queued') {
      this.directStartsByGuid[guid] = undefined;
      return this.enqueueDirectArkWebStart(direct.snapshot, direct.targetPath)
        .then((snapshot: PlatformDownloadSnapshot | undefined): boolean => snapshot !== undefined);
    }
    if (direct?.state === 'paused_starting') {
      return this.waitForPausedDirectStart(direct)
        .then((snapshot: PlatformDownloadSnapshot | undefined): boolean => snapshot !== undefined);
    }
    if (direct !== undefined) return Promise.resolve(false);
    if (this.heldSnapshots[guid] !== undefined) {
      // Initial admission needs a target path; callers must use startDirectDownload.
      return Promise.resolve(false);
    }
    const item = this.itemsByGuid[guid];
    if (item !== undefined && this.handedOffGuids[guid] !== true) {
      if (this.readState(item) === 'FAILED') {
        return Promise.resolve(this.restoreArkWebDownload(
          guid, this.serializeDownload(item) ?? platformTaskToken, undefined, platformTaskId
        ) !== undefined);
      }
      try {
        item.resume();
        return Promise.resolve(true);
      } catch (_error) {
        return Promise.resolve(this.restoreArkWebDownload(
          guid, this.serializeDownload(item) ?? platformTaskToken, undefined, platformTaskId
        ) !== undefined);
      }
    }
    if (this.isArkWebTask(platformTaskId, platformTaskToken)) {
      return Promise.resolve(this.restoreArkWebDownload(guid, platformTaskToken, undefined, platformTaskId) !== undefined);
    }
    return this.libcurlAdapter.resumeDownload(guid, platformTaskId, platformTaskToken);
  }

  cancelDownload(guid: string, platformTaskId?: string, platformTaskToken?: string): Promise<boolean> {
    const direct = this.directStartsByGuid[guid];
    if (direct !== undefined && direct.state !== 'binding') {
      this.retireDirectStart(direct, false, 'CANCELED');
      return Promise.resolve(true);
    }
    if (this.heldSnapshots[guid] !== undefined) {
      this.clearHeldDownload(guid);
      return Promise.resolve(true);
    }
    this.ignoredCancellationGuids[guid] = undefined;
    const item = this.itemsByGuid[guid];
    if (item !== undefined && this.handedOffGuids[guid] !== true) {
      const pendingPath = this.pendingTargetPaths[guid];
      this.closedGuids[guid] = true;
      this.pendingTargetPaths[guid] = undefined;
      try {
        item.cancel();
        this.itemsByGuid[guid] = undefined;
        this.retiredItemsByGuid[guid] = undefined;
        return Promise.resolve(true);
      } catch (_error) {
        this.closedGuids[guid] = undefined;
        this.pendingTargetPaths[guid] = pendingPath;
        return Promise.resolve(false);
      }
    }
    return this.libcurlAdapter.cancelDownload(guid, platformTaskId, platformTaskToken);
  }

  cancelPendingDownload(guid: string): boolean {
    const direct = this.directStartsByGuid[guid];
    if (direct !== undefined && direct.state !== 'binding') {
      this.retireDirectStart(direct, false, 'CANCELED');
      return true;
    }
    if (this.heldSnapshots[guid] !== undefined) {
      this.clearHeldDownload(guid);
      return true;
    }
    const item = this.itemsByGuid[guid];
    if (item === undefined) {
      return this.libcurlAdapter.cancelPendingDownload(guid);
    }
    this.pendingCancelInFlightGuid = guid;
    this.ignoredCancellationGuids[guid] = true;
    this.closedGuids[guid] = true;
    this.pendingTargetPaths[guid] = undefined;
    try {
      item.cancel();
    } catch (_error) {
      this.closedGuids[guid] = undefined;
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

  private enqueueDirectArkWebStart(
    snapshot: PlatformDownloadSnapshot, targetPath: string
  ): Promise<PlatformDownloadSnapshot | undefined> {
    const sourceId = snapshot.sourceId?.trim() ?? '';
    const source = this.downloadSources[sourceId];
    const url = snapshot.originalUrl?.trim() || snapshot.url.trim();
    if (source === undefined || this.closedSourceIds[sourceId] === true ||
      snapshot.guid.trim().length === 0 || targetPath.trim().length === 0 ||
      snapshot.method?.trim().toUpperCase() !== 'GET' || !this.isHttpUrl(url) ||
      this.closedGuids[snapshot.guid] === true) return Promise.resolve(undefined);
    const existing = this.directStartsByGuid[snapshot.guid];
    if (existing?.state === 'paused_starting') {
      existing.targetPath = targetPath;
      return this.waitForPausedDirectStart(existing);
    }
    if (existing !== undefined && existing.state !== 'paused_queued') {
      return existing.promise ?? Promise.resolve(this.snapshotForDirectStart(existing));
    }
    // The public callback has no request ID. A late callback for this source+URL could not
    // be distinguished from a second request, so never reuse that key while it is retired.
    if ((this.retiredStartsBySource[sourceId] ?? []).some((entry: ArkWebRetiredStart): boolean =>
      this.directStartUrl(entry.request) === url)) return Promise.resolve(undefined);
    const request: ArkWebDirectStart = {
      snapshot: snapshot, targetPath: targetPath, state: 'queued', settled: false,
      resolve: (_snapshot: PlatformDownloadSnapshot | undefined): void => {}
    };
    const promise = new Promise<PlatformDownloadSnapshot | undefined>(
      (resolve: (value: PlatformDownloadSnapshot | undefined) => void): void => {
        request.resolve = resolve;
      });
    request.promise = promise;
    this.directStartsByGuid[snapshot.guid] = request;
    this.sourceIdsByGuid[snapshot.guid] = sourceId;
    source.queue.push(request);
    this.startNextDirectRequest(sourceId);
    return promise;
  }

  private startNextDirectRequest(sourceId: string): void {
    const source = this.downloadSources[sourceId];
    if (source === undefined || source.active !== undefined || this.closedSourceIds[sourceId] === true) return;
    const request = source.queue.shift();
    if (request === undefined) return;
    if (request.state !== 'queued') {
      this.startNextDirectRequest(sourceId);
      return;
    }
    if ((this.retiredStartsBySource[sourceId] ?? []).some((entry: ArkWebRetiredStart): boolean =>
      this.directStartUrl(entry.request) === this.directStartUrl(request))) {
      this.retireDirectStart(request, false, 'FAILED');
      return;
    }
    request.state = 'starting';
    source.active = request;
    request.timer = setTimeout((): void => {
      if (source.active === request && request.state === 'starting') {
        this.retireDirectStart(request, false, 'FAILED');
      }
    }, DIRECT_ARKWEB_START_TIMEOUT_MS);
    try {
      source.start(this.directStartUrl(request));
    } catch (_error) {
      // A throwing controller may already have accepted the request. Keep the exact-match
      // tombstone; do not try another controller or issue a native HTTP request.
      if (request.state === 'starting') this.retireDirectStart(request, false, 'FAILED');
    }
  }

  private directStartUrl(request: ArkWebDirectStart): string {
    return request.snapshot.originalUrl?.trim() || request.snapshot.url.trim();
  }

  private matchesDirectStart(request: ArkWebDirectStart, item: webview.WebDownloadItem): boolean {
    try {
      if (item.getMethod().trim().toUpperCase() !== 'GET') return false;
    } catch (_error) {
      return false;
    }
    const original = this.readOriginalUrl(item);
    const itemUrl = original.length > 0 ? original : this.readUrl(item).trim();
    return itemUrl.length > 0 && itemUrl === this.directStartUrl(request);
  }

  private snapshotForDirectStart(request: ArkWebDirectStart, state?: string): PlatformDownloadSnapshot {
    const snapshot = request.snapshot;
    return {
      guid: snapshot.guid, sourceId: snapshot.sourceId, url: snapshot.url, originalUrl: snapshot.originalUrl,
      suggestedFileName: snapshot.suggestedFileName, fileNameLocked: snapshot.fileNameLocked, totalBytes: snapshot.totalBytes,
      receivedBytes: snapshot.receivedBytes, currentSpeed: 0,
      state: state ?? ((request.state === 'paused_queued' || request.state === 'paused_starting') &&
        request.resumeRequested !== true ? 'PAUSED' : 'PENDING'),
      lastErrorCode: state === 'FAILED' ? 1 : 0, mimeType: snapshot.mimeType, method: snapshot.method,
      userAgent: snapshot.userAgent, referer: snapshot.referer, contentDisposition: snapshot.contentDisposition,
      headers: snapshot.headers, downloadDriver: 'arkweb', privacyMode: snapshot.privacyMode
    };
  }

  private settleDirectStart(request: ArkWebDirectStart, snapshot?: PlatformDownloadSnapshot): void {
    if (request.timer !== undefined) {
      clearTimeout(request.timer);
      request.timer = undefined;
    }
    if (!request.settled) {
      request.settled = true;
      request.resolve(snapshot);
    }
  }

  private detachDirectStart(request: ArkWebDirectStart): void {
    const sourceId = request.snapshot.sourceId ?? '';
    const source = this.downloadSources[sourceId];
    if (source === undefined) return;
    source.queue = source.queue.filter((queued: ArkWebDirectStart): boolean => queued !== request);
    if (source.active === request) source.active = undefined;
  }

  private retireDirectStart(request: ArkWebDirectStart, hold: boolean, state: 'FAILED' | 'CANCELED'): void {
    const sourceId = request.snapshot.sourceId ?? '';
    const guid = request.snapshot.guid;
    const wasIssued = request.state === 'starting' || request.state === 'paused_starting';
    this.detachDirectStart(request);
    if (wasIssued) {
      const retired = this.retiredStartsBySource[sourceId] ?? [];
      const existing = retired.find((entry: ArkWebRetiredStart): boolean => entry.request === request);
      if (existing !== undefined) existing.hold = hold;
      else retired.push({ request: request, hold: hold });
      this.retiredStartsBySource[sourceId] = retired;
    }
    request.state = 'retired';
    this.directStartsByGuid[guid] = undefined;
    this.closedGuids[guid] = true;
    const snapshot = this.snapshotForDirectStart(request, state);
    this.settleDirectStart(request, state === 'FAILED' ? undefined : snapshot);
    this.callbacks.onDownloadEvent?.({ type: state === 'FAILED' ? 'failed' : 'canceled', snapshot: snapshot });
    this.startNextDirectRequest(sourceId);
  }

  private pauseDirectStart(request: ArkWebDirectStart): void {
    if (request.state === 'paused_queued' || request.state === 'paused_starting') {
      if (request.resumeRequested === true) {
        request.resumeRequested = false;
        const paused = this.snapshotForDirectStart(request, 'PAUSED');
        this.settleDirectStart(request, paused);
        this.callbacks.onDownloadEvent?.({ type: 'updated', snapshot: paused });
      }
      return;
    }
    const sourceId = request.snapshot.sourceId ?? '';
    const issued = request.state === 'starting';
    this.detachDirectStart(request);
    request.state = issued ? 'paused_starting' : 'paused_queued';
    if (issued) {
      const retired = this.retiredStartsBySource[sourceId] ?? [];
      retired.push({ request: request, hold: true });
      this.retiredStartsBySource[sourceId] = retired;
    }
    const snapshot = this.snapshotForDirectStart(request, 'PAUSED');
    this.settleDirectStart(request, snapshot);
    this.callbacks.onDownloadEvent?.({ type: 'updated', snapshot: snapshot });
    this.startNextDirectRequest(sourceId);
  }

  private waitForPausedDirectStart(request: ArkWebDirectStart): Promise<PlatformDownloadSnapshot | undefined> {
    if (request.resumeRequested === true && request.promise !== undefined) return request.promise;
    request.resumeRequested = true;
    request.settled = false;
    request.promise = new Promise<PlatformDownloadSnapshot | undefined>(
      (resolve: (snapshot: PlatformDownloadSnapshot | undefined) => void): void => { request.resolve = resolve; });
    request.timer = setTimeout((): void => {
      if (this.directStartsByGuid[request.snapshot.guid] === request && request.resumeRequested === true &&
        request.state === 'paused_starting') this.retireDirectStart(request, false, 'FAILED');
    }, DIRECT_ARKWEB_START_TIMEOUT_MS);
    return request.promise;
  }

  private bindNativeGuid(appGuid: string, nativeGuid: string): boolean {
    if (appGuid.length === 0 || nativeGuid.length === 0) return false;
    const previousApp = this.appGuidsByNativeGuid[nativeGuid];
    const previousNative = this.nativeGuidsByAppGuid[appGuid];
    if ((previousApp !== undefined && previousApp !== appGuid) ||
      (previousNative !== undefined && previousNative !== nativeGuid)) return false;
    this.appGuidsByNativeGuid[nativeGuid] = appGuid;
    this.nativeGuidsByAppGuid[appGuid] = nativeGuid;
    return true;
  }

  private consumeDirectBefore(item: webview.WebDownloadItem, sourceId: string): boolean {
    const nativeGuid = this.readNativeGuid(item);
    if (this.appGuidsByNativeGuid[nativeGuid] !== undefined) return false;
    if (this.closedSourceIds[sourceId] === true) {
      this.closedGuids[nativeGuid] = true;
      try { item.cancel(); } catch (_error) {}
      return true;
    }
    const retired = this.retiredStartsBySource[sourceId] ?? [];
    const retiredIndex = retired.findIndex((entry: ArkWebRetiredStart): boolean => this.matchesDirectStart(entry.request, item));
    if (retiredIndex >= 0) {
      const entry = retired[retiredIndex];
      retired.splice(retiredIndex, 1);
      const guid = entry.request.snapshot.guid;
      if (entry.hold && this.bindNativeGuid(guid, nativeGuid)) {
        if (entry.request.resumeRequested === true) {
          this.bindDirectStartItem(entry.request, item, sourceId);
          return true;
        }
        this.itemsByGuid[guid] = item;
        this.directStartsByGuid[guid] = undefined;
        const held = this.holdDownload(guid);
        if (held !== undefined) this.callbacks.onDownloadEvent?.({ type: 'updated', snapshot: held });
        else {
          this.closedGuids[guid] = true;
          try { item.cancel(); } catch (_error) {}
        }
      } else {
        this.bindNativeGuid(guid, nativeGuid);
        this.closedGuids[this.readGuid(item)] = true;
        try { item.cancel(); } catch (_error) {}
      }
      return true;
    }
    const source = this.downloadSources[sourceId];
    const request = source?.active;
    if (request === undefined || request.state !== 'starting' || !this.matchesDirectStart(request, item)) return false;
    const guid = request.snapshot.guid;
    if (!this.bindNativeGuid(guid, nativeGuid)) {
      this.retireDirectStart(request, false, 'FAILED');
      try { item.cancel(); } catch (_error) {}
      return true;
    }
    this.bindDirectStartItem(request, item, sourceId);
    return true;
  }

  private bindDirectStartItem(request: ArkWebDirectStart, item: webview.WebDownloadItem, sourceId: string): void {
    const guid = request.snapshot.guid;
    request.state = 'binding';
    request.resumeRequested = false;
    this.pendingTargetPaths[guid] = request.targetPath;
    this.itemsByGuid[guid] = item;
    this.restoringGuids[guid] = true;
    this.latestEventSnapshots[guid] = undefined;
    try {
      this.handleDownloadEvent('before_download', item, sourceId);
    } catch (_error) {
      // An observer exception must not leave a controller request waiting forever after
      // ArkWeb accepted it. Return the actual platform state without another HTTP request.
      hilog.warn(DOWNLOAD_BRIDGE_DOMAIN, DOWNLOAD_BRIDGE_TAG, 'direct callback observer failed');
    }
    const snapshot = this.latestEventSnapshots[guid] ?? this.readSnapshot(item);
    this.restoringGuids[guid] = undefined;
    this.latestEventSnapshots[guid] = undefined;
    this.detachDirectStart(request);
    this.directStartsByGuid[guid] = undefined;
    this.settleDirectStart(request, snapshot);
    this.startNextDirectRequest(sourceId);
  }

  private initialize(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    this.configureDelegate(this.delegate);
    webview.WebDownloadManager.setDownloadDelegate(this.delegate);
  }

  private configureDelegate(delegate: PlatformDownloadDelegate, sourceId: string = ''): void {
    delegate.onBeforeDownload((item: webview.WebDownloadItem) => {
      this.handleDownloadEvent('before_download', item, sourceId);
    });

    delegate.onDownloadUpdated((item: webview.WebDownloadItem) => {
      this.handleDownloadEvent('updated', item, sourceId);
    });

    delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      this.handleDownloadEvent('finished', item, sourceId);
    });

    delegate.onDownloadFailed((item: webview.WebDownloadItem) => {
      this.handleDownloadEvent('failed', item, sourceId);
    });
  }

  private handleDownloadEvent(type: PlatformDownloadEventType, item: webview.WebDownloadItem, sourceId: string = ''): void {
    if (type === 'before_download' && this.consumeDirectBefore(item, sourceId)) return;
    const guid = this.readGuid(item);
    if (this.closedGuids[guid] === true) {
      if (type === 'before_download') {
        try { item.cancel(); } catch (_error) {}
      }
      return;
    }
    if (sourceId.length > 0 && this.sourceIdsByGuid[guid] === undefined) {
      this.sourceIdsByGuid[guid] = sourceId;
    }
    if ((this.retiredItemsByGuid[guid]?.indexOf(item) ?? -1) >= 0 || this.heldSnapshots[guid] !== undefined ||
      (this.ignoredCancellationGuids[guid] === true && this.readState(item) === 'CANCELED')) {
      return;
    }
    // A restored provisional download needs its destination in the new before callback.
    // Consume that callback internally so a confirmed task cannot open another prompt.
    const targetPath = this.pendingTargetPaths[guid];
    if (type === 'before_download' && targetPath !== undefined) {
      this.pendingTargetPaths[guid] = undefined;
      this.itemsByGuid[guid] = item;
      try {
        item.start(targetPath);
      } catch (_error) {
        this.ignoredCancellationGuids[guid] = true;
        try { item.cancel(); } catch (_cancelError) {}
        const failed = this.readSnapshot(item);
        failed.state = 'FAILED';
        failed.lastErrorCode = 1;
        if (this.restoringGuids[guid] === true) {
          this.latestEventSnapshots[guid] = failed;
        }
        this.callbacks.onDownloadEvent?.({ type: 'failed', snapshot: failed });
        return;
      }
      type = 'updated';
    }
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
    if (this.isTerminalState(snapshot.state) && snapshot.state !== 'FAILED') {
      this.itemsByGuid[snapshot.guid] = undefined;
      this.closedGuids[guid] = true;
      this.pendingTargetPaths[guid] = undefined;
      this.retiredItemsByGuid[guid] = undefined;
    }
    const event: PlatformDownloadEvent = {
      type: type,
      snapshot: snapshot
    };
    if (this.restoringGuids[guid] === true) {
      this.latestEventSnapshots[guid] = snapshot;
    }
    this.callbacks.onDownloadEvent?.(event);
  }

  private shouldSuppressPendingCancelEvent(type: PlatformDownloadEventType, guid: string, state: string): boolean {
    return this.pendingCancelInFlightGuid === guid &&
      type === 'failed' &&
      state.trim().toUpperCase() === 'CANCELED';
  }

  private readSnapshot(item: webview.WebDownloadItem): PlatformDownloadSnapshot {
    const guid = this.readGuid(item);
    const requested = this.requestedSnapshotsByGuid[guid];
    const url = this.readUrl(item);
    const originalUrl = this.readOriginalUrl(item);
    const referrerUrl = this.readReferrerUrl(item);
    return {
      guid: guid,
      sourceId: this.sourceIdsByGuid[guid],
      url: url,
      originalUrl: originalUrl.length > 0 && originalUrl !== url ? originalUrl : requested?.originalUrl,
      suggestedFileName: requested?.fileNameLocked === true
        ? requested.suggestedFileName.trim() || this.readSuggestedFileName(item) : this.readSuggestedFileName(item),
      fileNameLocked: requested?.fileNameLocked,
      totalBytes: this.readTotalBytes(item),
      receivedBytes: this.readReceivedBytes(item),
      currentSpeed: this.readCurrentSpeed(item),
      state: this.readState(item),
      lastErrorCode: this.readLastErrorCode(item),
      mimeType: this.readMimeType(item),
      method: this.readMethod(item),
      referer: referrerUrl.length > 0 ? referrerUrl : undefined,
      downloadDriver: 'arkweb',
      platformTaskId: `${ARKWEB_TASK_PREFIX}${this.readNativeGuid(item)}`,
      platformTaskToken: this.serializeDownload(item)
    };
  }

  private readGuid(item: webview.WebDownloadItem): string {
    const nativeGuid = this.readNativeGuid(item);
    return this.appGuidsByNativeGuid[nativeGuid] ?? nativeGuid;
  }

  private readNativeGuid(item: webview.WebDownloadItem): string {
    try {
      return item.getGuid();
    } catch (_error) {
      return '';
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
    this.heldSnapshots[guid] = undefined;
    this.pendingTargetPaths[guid] = undefined;
    try {
      item.cancel();
    } catch (_cancelError) {
      // ArkWeb may already have stopped this provisional item after handoff.
    }
    this.itemsByGuid[guid] = undefined;
  }

  private isHlsDownload(snapshot: PlatformDownloadSnapshot): boolean {
    const url = snapshot.url.trim().toLowerCase();
    const mime = snapshot.mimeType?.trim().toLowerCase() ?? '';
    return /\.m3u8?(?:[?#]|$)/i.test(url) || /mpegurl|m3u8/i.test(mime);
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

  private isArkWebTask(platformTaskId?: string, platformTaskToken?: string): boolean {
    return platformTaskId?.startsWith(ARKWEB_TASK_PREFIX) === true ||
      platformTaskToken?.startsWith(ARKWEB_TOKEN_PREFIX) === true;
  }

  private serializeDownload(item: webview.WebDownloadItem): string | undefined {
    try {
      const state = item.getState();
      if (state === webview.WebDownloadState.COMPLETED ||
        state === webview.WebDownloadState.CANCELED) {
        return undefined;
      }
      const bytes = item.serialize();
      return bytes.length > 0 && bytes.length <= MAX_ARKWEB_TOKEN_BYTES
        ? ARKWEB_TOKEN_PREFIX + this.base64Helper.encodeToStringSync(bytes) : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private deserializeDownload(guid: string, token?: string, platformTaskId?: string): webview.WebDownloadItem | undefined {
    if (token?.startsWith(ARKWEB_TOKEN_PREFIX) !== true || token.length > MAX_ARKWEB_TOKEN_BYTES * 2) {
      return undefined;
    }
    try {
      const item = webview.WebDownloadItem.deserialize(
        this.base64Helper.decodeSync(token.substring(ARKWEB_TOKEN_PREFIX.length))
      );
      const expectedNativeGuid = platformTaskId?.startsWith(ARKWEB_TASK_PREFIX)
        ? platformTaskId.substring(ARKWEB_TASK_PREFIX.length) : this.nativeGuidsByAppGuid[guid] ?? guid;
      return item.getGuid() === expectedNativeGuid && this.bindNativeGuid(guid, expectedNativeGuid) ? item : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private restoreArkWebDownload(
    guid: string, token?: string, targetPath?: string, platformTaskId?: string
  ): PlatformDownloadSnapshot | undefined {
    if (this.closedGuids[guid] === true) {
      return undefined;
    }
    const held = this.heldSnapshots[guid];
    const item = this.deserializeDownload(guid, token ?? held?.platformTaskToken, platformTaskId ?? held?.platformTaskId) ??
      (held !== undefined ? this.itemsByGuid[guid] : undefined);
    if (item === undefined) {
      return undefined;
    }
    try {
      this.initialize();
      if (targetPath !== undefined && targetPath.trim().length > 0) {
        this.pendingTargetPaths[guid] = targetPath;
      }
      const previousItem = this.itemsByGuid[guid];
      if (previousItem !== undefined && previousItem !== item) {
        const retiredItems = this.retiredItemsByGuid[guid] ?? [];
        if (retiredItems.indexOf(previousItem) < 0) retiredItems.push(previousItem);
        this.retiredItemsByGuid[guid] = retiredItems;
      }
      this.heldSnapshots[guid] = undefined;
      this.itemsByGuid[guid] = item;
      // Huawei requires deserialize -> WebDownloadManager.resumeDownload for failed tasks.
      // Never replay these URLs through libcurl: their POST body or renderer/session may be unique.
      this.latestEventSnapshots[guid] = undefined;
      this.restoringGuids[guid] = true;
      webview.WebDownloadManager.resumeDownload(item);
      const delivered = this.latestEventSnapshots[guid];
      this.restoringGuids[guid] = undefined;
      this.latestEventSnapshots[guid] = undefined;
      const snapshot = delivered ?? this.readSnapshot(item);
      if (delivered === undefined) {
        snapshot.state = 'IN_PROGRESS';
        snapshot.lastErrorCode = 0;
      }
      snapshot.platformTaskToken = this.serializeDownload(item) ?? token;
      return snapshot;
    } catch (_error) {
      this.restoringGuids[guid] = undefined;
      this.latestEventSnapshots[guid] = undefined;
      this.itemsByGuid[guid] = undefined;
      this.pendingTargetPaths[guid] = undefined;
      if (held !== undefined) {
        this.heldSnapshots[guid] = held;
        this.itemsByGuid[guid] = item;
      }
      return undefined;
    }
  }

  private startOrRestoreArkWebDownload(
    guid: string, targetPath: string, token?: string, platformTaskId?: string
  ): PlatformDownloadSnapshot | undefined {
    if (this.closedGuids[guid] === true) {
      return undefined;
    }
    if (this.heldSnapshots[guid] !== undefined) {
      return this.restoreArkWebDownload(guid, token, targetPath, platformTaskId);
    }
    const item = this.itemsByGuid[guid];
    if (item === undefined) {
      return this.restoreArkWebDownload(guid, token, targetPath, platformTaskId);
    }
    const snapshot = this.readSnapshot(item);
    if (snapshot.state === 'FAILED' || snapshot.state === 'CANCELED') {
      return this.restoreArkWebDownload(guid, snapshot.platformTaskToken ?? token, targetPath, platformTaskId ?? snapshot.platformTaskId);
    }
    if (snapshot.state === 'PAUSED') {
      try {
        item.resume();
        return this.readSnapshot(item);
      } catch (_error) {
        return this.restoreArkWebDownload(guid, snapshot.platformTaskToken ?? token, targetPath, platformTaskId ?? snapshot.platformTaskId);
      }
    }
    return this.startNativeArkWebDownload(guid, targetPath);
  }

  private clearHeldDownload(guid: string): void {
    this.closedGuids[guid] = true;
    this.heldSnapshots[guid] = undefined;
    this.itemsByGuid[guid] = undefined;
    this.pendingTargetPaths[guid] = undefined;
    this.handedOffGuids[guid] = undefined;
    this.retiredItemsByGuid[guid] = undefined;
    // A late cancel callback from the provisional task must stay suppressed.
    this.ignoredCancellationGuids[guid] = true;
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
