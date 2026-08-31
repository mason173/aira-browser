import { webview } from '@kit.ArkWeb';
import { certificateManager } from '@kit.DeviceCertificateKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  PlatformDownloadAdapterCallbacks,
  PlatformDownloadDelegate,
  PlatformDownloadEventType,
  PlatformDownloadSnapshot
} from './PlatformDownloadAdapter';

interface AiraDownloadSnapshot {
  state: 'created' | 'running' | 'pausing' | 'paused' | 'completed' | 'failed' | 'canceled';
  receivedBytes: number;
  totalBytes: number;
  speedBytesPerSecond: number;
  errorCode: number;
  errorMessage: string;
  diagnosticMessage: string;
  failurePhase: string;
  fileExtension: string;
}

interface AiraDownloadNativeModule {
  createTask(
    url: string,
    targetPath: string,
    headers: string[],
    hls: boolean,
    caPath: string,
    hlsSegmentConcurrency: number
  ): number;
  startTask(handle: number): boolean;
  pauseTask(handle: number): boolean;
  resumeTask(handle: number): boolean;
  cancelTask(handle: number): boolean;
  releaseTask(handle: number): void;
  cleanupHlsArtifacts(targetPath: string): void;
  getSnapshot(handle: number): AiraDownloadSnapshot;
  backendVersion(): string;
  hlsPolicySummary(): string;
}

interface AiraDownloadNativeModuleNamespace {
  default: AiraDownloadNativeModule;
}

interface LibcurlTaskBinding {
  guid: string;
  handle: number;
  targetPath: string;
  hls: boolean;
  snapshot: PlatformDownloadSnapshot;
  lastState: string;
  lastReceivedBytes: number;
  terminalEventSent: boolean;
  nativeReleased: boolean;
}

const LIBCURL_DOWNLOAD_DOMAIN = 0x0000;
const LIBCURL_DOWNLOAD_TAG = 'LibcurlDownload';
const LIBCURL_POLL_INTERVAL_MS = 250;
const LIBCURL_DIAGNOSTIC_PREFIX = '[DEBUG-DLSSL-827]';
const DEFAULT_HLS_SEGMENT_CONCURRENCY = 8;

export class LibcurlDownloadAdapter {
  private callbacks: PlatformDownloadAdapterCallbacks = {};
  private nativeModule?: AiraDownloadNativeModule;
  private nativeModuleTask?: Promise<AiraDownloadNativeModule>;
  private bindingsByGuid: Record<string, LibcurlTaskBinding | undefined> = {};
  private pollTimer?: number;

  getDelegate(): PlatformDownloadDelegate {
    throw new Error('LibcurlDownloadAdapter does not provide a Web download delegate.');
  }

  setCallbacks(callbacks: PlatformDownloadAdapterCallbacks): void {
    this.callbacks = callbacks;
  }

  hasActiveDownload(guid: string): boolean {
    const binding = this.bindingsByGuid[guid.trim()];
    return binding !== undefined && this.isLiveState(binding.snapshot.state);
  }

  getActiveDownloadSnapshot(guid: string): PlatformDownloadSnapshot | undefined {
    const binding = this.bindingsByGuid[guid.trim()];
    return binding?.snapshot;
  }

  getActiveDownloadSnapshots(): PlatformDownloadSnapshot[] {
    return Object.keys(this.bindingsByGuid)
      .map((guid: string) => this.bindingsByGuid[guid]?.snapshot)
      .filter((snapshot?: PlatformDownloadSnapshot) => snapshot !== undefined && this.isLiveState(snapshot.state)) as
      PlatformDownloadSnapshot[];
  }

  async reconnectDownload(
    guid: string,
    platformTaskId: string,
    _platformTaskToken?: string
  ): Promise<PlatformDownloadSnapshot | undefined> {
    const handle = Number(platformTaskId.trim());
    if (!Number.isFinite(handle) || handle <= 0) {
      return undefined;
    }
    const binding = this.bindingsByGuid[guid.trim()];
    if (binding === undefined || binding.handle !== handle) {
      return undefined;
    }
    if (binding.nativeReleased) {
      return binding.snapshot;
    }
    this.pollBinding(binding);
    return binding.snapshot;
  }

  async startDownload(_guid: string, _targetPath: string): Promise<boolean> {
    return false;
  }

  async startDirectDownload(
    snapshot: PlatformDownloadSnapshot,
    targetPath: string
  ): Promise<PlatformDownloadSnapshot | undefined> {
    const guid = snapshot.guid.trim();
    const url = snapshot.url.trim();
    const normalizedTargetPath = targetPath.trim();
    if (guid.length <= 0 || url.length <= 0 || normalizedTargetPath.length <= 0) {
      return undefined;
    }
    const method = snapshot.method?.trim().toUpperCase() ?? 'GET';
    if (method !== 'GET') {
      hilog.warn(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
        'unsupported method guid=%{public}s method=%{public}s', guid, method);
      return undefined;
    }
    const nativeModule = await this.loadNativeModule();
    const headers = this.buildHeaders(snapshot);
    const hls = this.isHlsSnapshot(snapshot);
    const hlsSegmentConcurrency = this.normalizeHlsSegmentConcurrency(snapshot.hlsSegmentConcurrency);
    const hlsRetryPolicy = nativeModule.hlsPolicySummary();
    const caPath = this.resolveSystemCaPath();
    hilog.info(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
      '%{public}s start guid=%{public}s hls=%{public}s hlsConcurrency=%{public}d hlsRetry=%{public}s caPath=%{public}s headerNames=%{public}s',
      LIBCURL_DIAGNOSTIC_PREFIX, guid, String(hls), hlsSegmentConcurrency,
      hlsRetryPolicy, caPath.length > 0 ? caPath : 'empty',
      this.summarizeHeaderNames(headers));
    let handle = 0;
    try {
      handle = nativeModule.createTask(
        url,
        normalizedTargetPath,
        headers,
        hls,
        caPath,
        hlsSegmentConcurrency
      );
      if (!nativeModule.startTask(handle)) {
        hilog.warn(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
          '%{public}s native start rejected guid=%{public}s handle=%{public}d',
          LIBCURL_DIAGNOSTIC_PREFIX, guid, handle);
        nativeModule.releaseTask(handle);
        return undefined;
      }
    } catch (error) {
      hilog.warn(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
        '%{public}s native start failed guid=%{public}s error=%{public}s',
        LIBCURL_DIAGNOSTIC_PREFIX, guid, JSON.stringify(error));
      if (handle > 0) {
        try {
          nativeModule.releaseTask(handle);
        } catch (_releaseError) {
        }
      }
      return undefined;
    }
    const token = `libcurl:${guid}`;
    const startedSnapshot: PlatformDownloadSnapshot = {
      guid: guid,
      url: url,
      originalUrl: snapshot.originalUrl,
      suggestedFileName: snapshot.suggestedFileName,
      totalBytes: snapshot.totalBytes,
      receivedBytes: snapshot.receivedBytes,
      currentSpeed: snapshot.currentSpeed,
      state: 'RUNNING',
      lastErrorCode: 0,
      errorMessage: undefined,
      mimeType: snapshot.mimeType,
      method: method,
      userAgent: snapshot.userAgent,
      referer: snapshot.referer,
      contentDisposition: snapshot.contentDisposition,
      headers: snapshot.headers,
      hlsSegmentConcurrency: hlsSegmentConcurrency,
      platformTaskId: String(handle),
      platformTaskToken: token
    };
    this.bindingsByGuid[guid] = {
      guid: guid,
      handle: handle,
      targetPath: normalizedTargetPath,
      hls: hls,
      snapshot: startedSnapshot,
      lastState: 'RUNNING',
      lastReceivedBytes: startedSnapshot.receivedBytes,
      terminalEventSent: false,
      nativeReleased: false
    };
    this.ensurePoller();
    this.callbacks.onDownloadEvent?.({
      type: 'updated',
      snapshot: startedSnapshot
    });
    return startedSnapshot;
  }

  async retryDownload(
    guid: string,
    targetPath: string,
    _platformTaskId?: string,
    _platformTaskToken?: string,
    hlsSegmentConcurrency?: number
  ): Promise<boolean> {
    const binding = this.bindingsByGuid[guid.trim()];
    if (binding === undefined) {
      return false;
    }
    const previous = binding.snapshot;
    this.releaseNativeTask(binding);
    this.bindingsByGuid[guid.trim()] = undefined;
    const restarted = await this.startDirectDownload({
      guid: previous.guid,
      url: previous.url,
      originalUrl: previous.originalUrl,
      suggestedFileName: previous.suggestedFileName,
      totalBytes: previous.totalBytes,
      receivedBytes: 0,
      currentSpeed: 0,
      state: 'PENDING',
      lastErrorCode: 0,
      errorMessage: undefined,
      mimeType: previous.mimeType,
      method: previous.method,
      userAgent: previous.userAgent,
      referer: previous.referer,
      contentDisposition: previous.contentDisposition,
      headers: previous.headers,
      hlsSegmentConcurrency: hlsSegmentConcurrency ?? previous.hlsSegmentConcurrency
    }, targetPath);
    return restarted !== undefined;
  }

  private normalizeHlsSegmentConcurrency(value: number | undefined): number {
    if (value === 4 || value === 8 || value === 16) {
      return value;
    }
    return DEFAULT_HLS_SEGMENT_CONCURRENCY;
  }

  async pauseDownload(guid: string, _platformTaskId?: string, _platformTaskToken?: string): Promise<boolean> {
    const binding = this.bindingsByGuid[guid.trim()];
    if (binding === undefined || binding.nativeReleased || this.nativeModule === undefined) {
      return false;
    }
    try {
      const accepted = this.nativeModule.pauseTask(binding.handle);
      this.logControl('pause', binding, accepted, '');
      return accepted;
    } catch (error) {
      this.logControl('pause', binding, false, JSON.stringify(error));
      return false;
    }
  }

  async resumeDownload(guid: string, _platformTaskId?: string, _platformTaskToken?: string): Promise<boolean> {
    const binding = this.bindingsByGuid[guid.trim()];
    if (binding === undefined || binding.nativeReleased || this.nativeModule === undefined) {
      return false;
    }
    try {
      const accepted = this.nativeModule.resumeTask(binding.handle);
      this.logControl('resume', binding, accepted, '');
      return accepted;
    } catch (error) {
      this.logControl('resume', binding, false, JSON.stringify(error));
      return false;
    }
  }

  async cancelDownload(guid: string, _platformTaskId?: string, _platformTaskToken?: string): Promise<boolean> {
    const binding = this.bindingsByGuid[guid.trim()];
    if (binding === undefined || this.nativeModule === undefined) {
      return false;
    }
    if (binding.nativeReleased) {
      if (binding.snapshot.state.trim().toUpperCase() !== 'FAILED') {
        return false;
      }
      this.cleanupBindingArtifacts(binding);
      if (this.bindingsByGuid[binding.guid] === binding) {
        this.bindingsByGuid[binding.guid] = undefined;
      }
      return true;
    }
    try {
      const canceled = this.nativeModule.cancelTask(binding.handle);
      this.logControl('cancel', binding, canceled, '');
      if (canceled && binding.snapshot.state.trim().toUpperCase() === 'FAILED') {
        this.releaseNativeTask(binding);
        if (this.bindingsByGuid[binding.guid] === binding) {
          this.bindingsByGuid[binding.guid] = undefined;
        }
      }
      return canceled;
    } catch (error) {
      this.logControl('cancel', binding, false, JSON.stringify(error));
      return false;
    }
  }

  cancelPendingDownload(guid: string): boolean {
    const binding = this.bindingsByGuid[guid.trim()];
    if (binding === undefined || binding.nativeReleased || this.nativeModule === undefined) {
      return false;
    }
    try {
      const accepted = this.nativeModule.cancelTask(binding.handle);
      this.logControl('cancel_pending', binding, accepted, '');
      return accepted;
    } catch (error) {
      this.logControl('cancel_pending', binding, false, JSON.stringify(error));
      return false;
    }
  }

  private async loadNativeModule(): Promise<AiraDownloadNativeModule> {
    if (this.nativeModule !== undefined) {
      return this.nativeModule;
    }
    if (this.nativeModuleTask === undefined) {
      this.nativeModuleTask = import('libaira_download.so')
        .then((module: AiraDownloadNativeModuleNamespace): AiraDownloadNativeModule => {
          this.nativeModule = module.default;
          hilog.info(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
            '%{public}s loaded backend=%{public}s',
            LIBCURL_DIAGNOSTIC_PREFIX, this.nativeModule.backendVersion());
          return module.default;
        })
        .catch((error: Error): AiraDownloadNativeModule => {
          this.nativeModuleTask = undefined;
          hilog.error(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
            '%{public}s load native module failed error=%{public}s',
            LIBCURL_DIAGNOSTIC_PREFIX, JSON.stringify(error));
          throw error;
        });
    }
    return this.nativeModuleTask;
  }

  private buildHeaders(snapshot: PlatformDownloadSnapshot): string[] {
    const headers: Record<string, string> = {};
    const sourceHeaders = snapshot.headers;
    if (sourceHeaders !== undefined) {
      Object.keys(sourceHeaders).forEach((key: string) => {
        const normalizedKey = key.trim();
        const normalizedValue = sourceHeaders[key].trim();
        if (normalizedKey.length > 0 && normalizedValue.length > 0 &&
            normalizedKey.indexOf('\r') < 0 && normalizedKey.indexOf('\n') < 0 &&
            normalizedValue.indexOf('\r') < 0 && normalizedValue.indexOf('\n') < 0 &&
            this.isForwardableHeader(normalizedKey)) {
          headers[normalizedKey] = normalizedValue;
        }
      });
    }
    const hasHeader = (name: string): boolean => {
      return Object.keys(headers).some((key: string) => key.toLowerCase() === name.toLowerCase());
    };
    const userAgent = snapshot.userAgent?.trim() ?? '';
    if (userAgent.length > 0 && !hasHeader('User-Agent')) {
      headers['User-Agent'] = userAgent;
    }
    const referer = snapshot.referer?.trim() ?? '';
    if (referer.length > 0 && !hasHeader('Referer')) {
      headers['Referer'] = referer;
    }
    if (!hasHeader('Cookie')) {
      try {
        const cookie = webview.WebCookieManager.fetchCookieSync(snapshot.url, false).trim();
        if (cookie.length > 0) {
          headers['Cookie'] = cookie;
        }
      } catch (_error) {
      }
    }
    return Object.keys(headers).map((key: string) => `${key}: ${headers[key]}`);
  }

  private isForwardableHeader(name: string): boolean {
    switch (name.trim().toLowerCase()) {
      case 'accept-encoding':
      case 'connection':
      case 'content-length':
      case 'host':
      case 'proxy-connection':
      case 'range':
      case 'te':
      case 'trailer':
      case 'transfer-encoding':
      case 'upgrade':
        return false;
      default:
        return true;
    }
  }

  private isHlsSnapshot(snapshot: PlatformDownloadSnapshot): boolean {
    const url = snapshot.url.trim().toLowerCase();
    const mime = snapshot.mimeType?.trim().toLowerCase() ?? '';
    return url.indexOf('.m3u8') >= 0 || mime.indexOf('mpegurl') >= 0 || mime.indexOf('hls') >= 0;
  }

  private resolveSystemCaPath(): string {
    try {
      return certificateManager.getCertificateStorePath({
        certType: certificateManager.CertType.CA_CERT_SYSTEM
      }).trim();
    } catch (error) {
      hilog.warn(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
        'system CA path unavailable error=%{public}s', JSON.stringify(error));
      return '';
    }
  }

  private summarizeHeaderNames(headers: string[]): string {
    const names: string[] = [];
    headers.forEach((header: string): void => {
      const separator = header.indexOf(':');
      const name = (separator >= 0 ? header.substring(0, separator) : header).trim().toLowerCase();
      if (name.length > 0 && names.indexOf(name) < 0) {
        names.push(name);
      }
    });
    return names.join(',');
  }

  private replaceMediaExtension(fileName: string, extension: string): string {
    const normalizedExtension = extension.trim().toLowerCase();
    if (normalizedExtension !== '.ts' && normalizedExtension !== '.mp4') {
      return fileName;
    }
    const normalizedName = fileName.trim();
    const slashIndex = Math.max(normalizedName.lastIndexOf('/'), normalizedName.lastIndexOf('\\'));
    const dotIndex = normalizedName.lastIndexOf('.');
    if (dotIndex > slashIndex) {
      return `${normalizedName.substring(0, dotIndex)}${normalizedExtension}`;
    }
    return `${normalizedName}${normalizedExtension}`;
  }

  private ensurePoller(): void {
    if (this.pollTimer !== undefined) {
      return;
    }
    this.pollTimer = setInterval((): void => {
      this.pollAll();
    }, LIBCURL_POLL_INTERVAL_MS);
  }

  private pollAll(): void {
    let hasLiveTask = false;
    Object.keys(this.bindingsByGuid).forEach((guid: string) => {
      const binding = this.bindingsByGuid[guid];
      if (binding === undefined) {
        return;
      }
      this.pollBinding(binding);
      if (this.isLiveState(binding.snapshot.state)) {
        hasLiveTask = true;
      }
    });
    if (!hasLiveTask && this.pollTimer !== undefined) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  private pollBinding(binding: LibcurlTaskBinding): void {
    if (binding.nativeReleased || this.nativeModule === undefined) {
      return;
    }
    let nativeSnapshot: AiraDownloadSnapshot;
    try {
      nativeSnapshot = this.nativeModule.getSnapshot(binding.handle);
    } catch (error) {
      hilog.warn(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
        '%{public}s snapshot failed guid=%{public}s handle=%{public}d error=%{public}s',
        LIBCURL_DIAGNOSTIC_PREFIX, binding.guid, binding.handle, JSON.stringify(error));
      return;
    }
    const state = this.mapState(nativeSnapshot.state);
    const suggestedFileName = this.replaceMediaExtension(
      binding.snapshot.suggestedFileName,
      nativeSnapshot.fileExtension
    );
    const reportedTotalBytes = nativeSnapshot.totalBytes > 0 ?
      nativeSnapshot.totalBytes : binding.snapshot.totalBytes;
    binding.snapshot = {
      guid: binding.snapshot.guid,
      url: binding.snapshot.url,
      originalUrl: binding.snapshot.originalUrl,
      suggestedFileName: suggestedFileName,
      mimeType: binding.snapshot.mimeType,
      method: binding.snapshot.method,
      userAgent: binding.snapshot.userAgent,
      referer: binding.snapshot.referer,
      contentDisposition: binding.snapshot.contentDisposition,
      headers: binding.snapshot.headers,
      platformTaskId: binding.snapshot.platformTaskId,
      platformTaskToken: binding.snapshot.platformTaskToken,
      state: state,
      receivedBytes: nativeSnapshot.receivedBytes,
      totalBytes: reportedTotalBytes,
      currentSpeed: nativeSnapshot.speedBytesPerSecond,
      lastErrorCode: state === 'FAILED' ? nativeSnapshot.errorCode : 0,
      errorMessage: nativeSnapshot.errorMessage.trim().length > 0 ? nativeSnapshot.errorMessage : undefined
    };
    const changed = state !== binding.lastState || nativeSnapshot.receivedBytes !== binding.lastReceivedBytes;
    binding.lastState = state;
    binding.lastReceivedBytes = nativeSnapshot.receivedBytes;
    if (!changed) {
      return;
    }
    hilog.info(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
      '%{public}s state guid=%{public}s handle=%{public}d state=%{public}s received=%{public}d total=%{public}d speed=%{public}d phase=%{public}s code=%{public}d',
      LIBCURL_DIAGNOSTIC_PREFIX, binding.guid, binding.handle, state,
      nativeSnapshot.receivedBytes, nativeSnapshot.totalBytes, nativeSnapshot.speedBytesPerSecond,
      nativeSnapshot.failurePhase, nativeSnapshot.errorCode);
    if (state === 'FAILED') {
      hilog.error(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
        '%{public}s failure guid=%{public}s handle=%{public}d phase=%{public}s code=%{public}d message=%{public}s diagnostic=%{public}s',
        LIBCURL_DIAGNOSTIC_PREFIX, binding.guid, binding.handle, nativeSnapshot.failurePhase,
        nativeSnapshot.errorCode, nativeSnapshot.errorMessage, nativeSnapshot.diagnosticMessage);
    }
    if (state === 'COMPLETED' && !binding.terminalEventSent) {
      binding.terminalEventSent = true;
      this.emit('finished', binding.snapshot);
    } else if (state === 'CANCELED' && !binding.terminalEventSent) {
      binding.terminalEventSent = true;
      this.emit('canceled', binding.snapshot);
    } else if (state === 'FAILED' && !binding.terminalEventSent) {
      binding.terminalEventSent = true;
      this.emit('failed', binding.snapshot);
    } else {
      this.emit('updated', binding.snapshot);
    }
    if (this.isTerminalState(state)) {
      this.releaseNativeTask(binding);
      if ((state === 'COMPLETED' || state === 'CANCELED') &&
          this.bindingsByGuid[binding.guid] === binding) {
        this.bindingsByGuid[binding.guid] = undefined;
      }
    }
  }

  private releaseNativeTask(binding: LibcurlTaskBinding): void {
    if (binding.nativeReleased || this.nativeModule === undefined) {
      return;
    }
    try {
      this.nativeModule.releaseTask(binding.handle);
      binding.nativeReleased = true;
    } catch (_error) {
    }
  }

  private logControl(action: string, binding: LibcurlTaskBinding, accepted: boolean, error: string): void {
    hilog.info(LIBCURL_DOWNLOAD_DOMAIN, LIBCURL_DOWNLOAD_TAG,
      '%{public}s control action=%{public}s guid=%{public}s handle=%{public}d accepted=%{public}s state=%{public}s error=%{public}s',
      LIBCURL_DIAGNOSTIC_PREFIX, action, binding.guid, binding.handle, String(accepted),
      binding.snapshot.state, error);
  }

  private cleanupBindingArtifacts(binding: LibcurlTaskBinding): void {
    if (!binding.hls || this.nativeModule === undefined) {
      return;
    }
    try {
      this.nativeModule.cleanupHlsArtifacts(binding.targetPath);
    } catch (_error) {
    }
  }

  private emit(type: PlatformDownloadEventType, snapshot: PlatformDownloadSnapshot): void {
    this.callbacks.onDownloadEvent?.({
      type: type,
      snapshot: snapshot
    });
  }

  private mapState(state: string): string {
    switch (state.trim().toLowerCase()) {
      case 'created': return 'PENDING';
      case 'running': return 'RUNNING';
      case 'pausing': return 'PAUSING';
      case 'paused': return 'PAUSED';
      case 'completed': return 'COMPLETED';
      case 'failed': return 'FAILED';
      case 'canceled': return 'CANCELED';
      default: return 'UNKNOWN';
    }
  }

  private isLiveState(state: string): boolean {
    const normalized = state.trim().toUpperCase();
    return normalized === 'PENDING' || normalized === 'RUNNING' || normalized === 'PAUSING' || normalized === 'PAUSED';
  }

  private isTerminalState(state: string): boolean {
    const normalized = state.trim().toUpperCase();
    return normalized === 'COMPLETED' || normalized === 'FAILED' || normalized === 'CANCELED';
  }

}
