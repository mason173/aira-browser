import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { PlatformDownloadSnapshot } from '../../platform/download/PlatformDownloadAdapter';

export interface DownloadV2CaptureBoundary {
  windowId: string;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  sourcePageUrl?: string;
}

export interface DownloadV2CapturedRequest {
  guid: string;
  url: string;
  originalUrl?: string;
  suggestedFileName: string;
  sourceHost: string;
  totalBytes: number;
  mimeType?: string;
  method: string;
  userAgent?: string;
  referer?: string;
  contentDisposition?: string;
  headers?: Record<string, string>;
  sourcePageUrl?: string;
  boundary: DownloadV2CaptureBoundary;
  platformSnapshot?: PlatformDownloadSnapshot;
  createdAt: number;
}

export interface DownloadV2Prompt {
  guid: string;
  fileName: string;
  sourceHost: string;
  url: string;
  totalBytes: number;
  mimeType?: string;
  contentDisposition?: string;
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel: string;
}
