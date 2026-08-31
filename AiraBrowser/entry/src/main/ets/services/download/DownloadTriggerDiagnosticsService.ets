import { hilog } from '@kit.PerformanceAnalysisKit';
import { DownloadV2CapturedRequest } from '../../features/downloadv2/DownloadV2CaptureTypes';
import { PlatformDownloadEvent } from '../../platform/download/PlatformDownloadAdapter';
import { DownloadV2Driver } from '../../domain/downloadv2/DownloadV2Types';

const DOWNLOAD_TRIGGER_DIAGNOSTICS_DOMAIN = 0x0000;
const DOWNLOAD_TRIGGER_DIAGNOSTICS_TAG = 'DownloadTriggerDiagnostics';
const DEFAULT_MAX_RECORDS: number = 96;
const DEFAULT_MATCH_WINDOW_MS: number = 1500;

export type DownloadTriggerSource =
  'arkweb_delegate' |
  'on_download_start' |
  'manual' |
  'html_redirect' |
  'resource_sniff' |
  'site_video' |
  'userscript';

export type DownloadTriggerPhase =
  'observed' |
  'captured' |
  'matched_delegate' |
  'driver_selected' |
  'start_succeeded' |
  'start_failed';

export interface DownloadTriggerDiagnosticRecord {
  id: string;
  timestamp: number;
  source: DownloadTriggerSource;
  phase: DownloadTriggerPhase;
  guid?: string;
  url: string;
  tabId?: string;
  fileName?: string;
  platformEventType?: string;
  driver?: DownloadV2Driver;
  reason?: string;
  matched: boolean;
}

export interface DownloadTriggerDiagnosticInput {
  source: DownloadTriggerSource;
  phase: DownloadTriggerPhase;
  guid?: string;
  url: string;
  tabId?: string;
  fileName?: string;
  platformEventType?: string;
  driver?: DownloadV2Driver;
  reason?: string;
  timestamp?: number;
}

export class DownloadTriggerDiagnosticsService {
  private records: DownloadTriggerDiagnosticRecord[] = [];
  private maxRecords: number;
  private matchWindowMs: number;

  constructor(maxRecords: number = DEFAULT_MAX_RECORDS, matchWindowMs: number = DEFAULT_MATCH_WINDOW_MS) {
    this.maxRecords = Math.max(8, maxRecords);
    this.matchWindowMs = Math.max(100, matchWindowMs);
  }

  recordPlatformEvent(event: PlatformDownloadEvent, timestamp: number = Date.now()): DownloadTriggerDiagnosticRecord {
    const record = this.record({
      source: 'arkweb_delegate',
      phase: 'observed',
      guid: event.snapshot.guid,
      url: event.snapshot.url,
      fileName: event.snapshot.suggestedFileName,
      platformEventType: event.type,
      reason: event.snapshot.state,
      timestamp: timestamp
    });
    if (event.type === 'before_download') {
      this.markMatchingOnDownloadStart(event.snapshot.url, timestamp);
    }
    return record;
  }

  recordCapturedRequest(
    source: DownloadTriggerSource,
    request: DownloadV2CapturedRequest,
    phase: DownloadTriggerPhase = 'captured',
    reason: string = '',
    timestamp: number = Date.now()
  ): DownloadTriggerDiagnosticRecord {
    return this.record({
      source: source,
      phase: phase,
      guid: request.guid,
      url: request.url,
      fileName: request.suggestedFileName,
      reason: reason,
      timestamp: timestamp
    });
  }

  recordDriverSelection(
    request: DownloadV2CapturedRequest,
    driver: DownloadV2Driver,
    timestamp: number = Date.now()
  ): DownloadTriggerDiagnosticRecord {
    const source: DownloadTriggerSource = request.platformSnapshot !== undefined ? 'arkweb_delegate' : 'manual';
    return this.record({
      source: source,
      phase: 'driver_selected',
      guid: request.guid,
      url: request.url,
      fileName: request.suggestedFileName,
      driver: driver,
      timestamp: timestamp
    });
  }

  recordStartResult(
    request: DownloadV2CapturedRequest,
    succeeded: boolean,
    driver: DownloadV2Driver,
    reason: string = '',
    timestamp: number = Date.now()
  ): DownloadTriggerDiagnosticRecord {
    const source: DownloadTriggerSource = request.platformSnapshot !== undefined ? 'arkweb_delegate' : 'manual';
    return this.record({
      source: source,
      phase: succeeded ? 'start_succeeded' : 'start_failed',
      guid: request.guid,
      url: request.url,
      fileName: request.suggestedFileName,
      driver: driver,
      reason: reason,
      timestamp: timestamp
    });
  }

  private record(input: DownloadTriggerDiagnosticInput): DownloadTriggerDiagnosticRecord {
    const normalizedUrl = input.url.trim();
    const record: DownloadTriggerDiagnosticRecord = {
      id: this.buildRecordId(input.timestamp ?? Date.now(), this.records.length),
      timestamp: input.timestamp ?? Date.now(),
      source: input.source,
      phase: input.phase,
      guid: this.normalizeOptionalString(input.guid),
      url: normalizedUrl,
      tabId: this.normalizeOptionalString(input.tabId),
      fileName: this.normalizeOptionalString(input.fileName),
      platformEventType: this.normalizeOptionalString(input.platformEventType),
      driver: input.driver,
      reason: this.normalizeOptionalString(input.reason),
      matched: input.source !== 'on_download_start'
    };
    this.records.push(record);
    if (this.records.length > this.maxRecords) {
      this.records = this.records.slice(this.records.length - this.maxRecords);
    }
    hilog.info(
      DOWNLOAD_TRIGGER_DIAGNOSTICS_DOMAIN,
      DOWNLOAD_TRIGGER_DIAGNOSTICS_TAG,
      'record source=%{public}s phase=%{public}s guid=%{public}s url=%{public}s driver=%{public}s reason=%{public}s',
      record.source,
      record.phase,
      record.guid ?? '',
      record.url,
      record.driver ?? '',
      record.reason ?? ''
    );
    return this.cloneRecord(record);
  }

  private markMatchingOnDownloadStart(url: string, timestamp: number): void {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length <= 0) {
      return;
    }
    this.records.forEach((record: DownloadTriggerDiagnosticRecord) => {
      if (record.source !== 'on_download_start' || record.matched) {
        return;
      }
      if (Math.abs(timestamp - record.timestamp) > this.matchWindowMs) {
        return;
      }
      if (!this.urlsMatch(record.url, normalizedUrl)) {
        return;
      }
      record.matched = true;
      record.phase = 'matched_delegate';
    });
  }

  private urlsMatch(left: string, right: string): boolean {
    const normalizedLeft = this.normalizeUrlForMatch(left);
    const normalizedRight = this.normalizeUrlForMatch(right);
    if (normalizedLeft.length <= 0 || normalizedRight.length <= 0) {
      return false;
    }
    return normalizedLeft === normalizedRight;
  }

  private normalizeUrlForMatch(url: string): string {
    const trimmed = url.trim();
    const hashIndex = trimmed.indexOf('#');
    return hashIndex >= 0 ? trimmed.substring(0, hashIndex) : trimmed;
  }

  private cloneRecord(record: DownloadTriggerDiagnosticRecord): DownloadTriggerDiagnosticRecord {
    return {
      id: record.id,
      timestamp: record.timestamp,
      source: record.source,
      phase: record.phase,
      guid: record.guid,
      url: record.url,
      tabId: record.tabId,
      fileName: record.fileName,
      platformEventType: record.platformEventType,
      driver: record.driver,
      reason: record.reason,
      matched: record.matched
    };
  }

  private buildRecordId(timestamp: number, index: number): string {
    return `download-trigger:${timestamp}:${index}`;
  }

  private normalizeOptionalString(value?: string): string | undefined {
    const normalized = String(value ?? '').trim();
    return normalized.length > 0 ? normalized : undefined;
  }
}
