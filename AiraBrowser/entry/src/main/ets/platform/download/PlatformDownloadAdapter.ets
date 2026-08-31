import { webview } from '@kit.ArkWeb';

export type PlatformDownloadDelegate = webview.WebDownloadDelegate;

export type PlatformDownloadEventType =
  'before_download' |
  'updated' |
  'finished' |
  'failed' |
  'canceled';

export interface PlatformDownloadSnapshot {
  guid: string;
  url: string;
  originalUrl?: string;
  suggestedFileName: string;
  totalBytes: number;
  receivedBytes: number;
  currentSpeed: number;
  state: string;
  lastErrorCode: number;
  errorMessage?: string;
  mimeType?: string;
  method?: string;
  userAgent?: string;
  referer?: string;
  contentDisposition?: string;
  headers?: Record<string, string>;
  hlsSegmentConcurrency?: number;
  platformTaskId?: string;
  platformTaskToken?: string;
}

export interface PlatformDownloadEvent {
  type: PlatformDownloadEventType;
  snapshot: PlatformDownloadSnapshot;
}

export interface PlatformDownloadAdapterCallbacks {
  onDownloadEvent?: (event: PlatformDownloadEvent) => void;
}

export interface PlatformDownloadAdapter {
  getDelegate(): PlatformDownloadDelegate;
  setCallbacks(callbacks: PlatformDownloadAdapterCallbacks): void;
  hasActiveDownload(guid: string): boolean;
  getActiveDownloadSnapshot(guid: string): PlatformDownloadSnapshot | undefined;
  getActiveDownloadSnapshots(): PlatformDownloadSnapshot[];
  reconnectDownload(guid: string, platformTaskId: string, platformTaskToken?: string): Promise<PlatformDownloadSnapshot | undefined>;
  startDirectDownload(snapshot: PlatformDownloadSnapshot, targetPath: string): Promise<PlatformDownloadSnapshot | undefined>;
  startDownload(guid: string, targetPath: string): Promise<boolean>;
  retryDownload(
    guid: string,
    targetPath: string,
    platformTaskId?: string,
    platformTaskToken?: string,
    hlsSegmentConcurrency?: number
  ): Promise<boolean>;
  pauseDownload(guid: string, platformTaskId?: string, platformTaskToken?: string): Promise<boolean>;
  resumeDownload(guid: string, platformTaskId?: string, platformTaskToken?: string): Promise<boolean>;
  cancelDownload(guid: string, platformTaskId?: string, platformTaskToken?: string): Promise<boolean>;
  cancelPendingDownload(guid: string): boolean;
}
