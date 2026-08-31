import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  bucketRuntimeDiagnosticDuration,
  DownloadRuntimeDiagnosticEvent,
  DownloadRuntimeDiagnosticRecorder
} from '../../common/models/RuntimeDiagnosticModels';
import {
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  createDownloadV2TaskEntity,
  DownloadV2TaskEntity
} from '../../domain/downloadv2/DownloadV2TaskEntity';
import {
  DownloadV2Driver,
  DownloadV2FailureCode,
  DownloadV2Failure,
  DownloadV2PersistenceSnapshot,
  DownloadV2ProgressSnapshot,
  DownloadV2RequestContext,
  DownloadV2ResumeCapability,
  DownloadV2ResumeMode,
  DownloadV2RuntimeSnapshot,
  DownloadV2Status,
  DownloadV2TaskTiming,
  buildDownloadV2EmptyFailure
} from '../../domain/downloadv2/DownloadV2Types';
import {
  DownloadV2SegmentPlanSnapshot,
  DownloadV2SegmentRecord,
  DownloadV2SegmentStatus,
  cloneDownloadV2SegmentPlanSnapshot,
  normalizeDownloadV2SegmentPlanSnapshot
} from '../../domain/downloadv2/DownloadV2SegmentTypes';

const DOWNLOAD_V2_RECORDS_STORE_NAME = 'aira_browser_download_v2_records';
const DOWNLOAD_V2_RECORDS_KEY = 'download_v2_records';
const DOWNLOAD_V2_RECORD_STORE_DOMAIN = 0x0000;
const DOWNLOAD_V2_RECORD_STORE_TAG = 'DownloadV2RecordStore';

interface PersistedDownloadV2Record {
  guid: string;
  windowId?: string;
  profileId?: string;
  privacyMode?: string;
  dataScope?: string;
  request?: PersistedDownloadV2RequestContext;
  suggestedFileName: string;
  resolvedFileName?: string;
  status?: string;
  progress?: PersistedDownloadV2ProgressSnapshot;
  persistence?: PersistedDownloadV2PersistenceSnapshot;
  runtime?: PersistedDownloadV2RuntimeSnapshot;
  failure?: PersistedDownloadV2Failure;
  timing?: PersistedDownloadV2TaskTiming;
}

interface PersistedDownloadV2RequestContext {
  url: string;
  originalUrl?: string;
  method: string;
  sourcePageUrl?: string;
  sourceHost?: string;
  userAgent?: string;
  referer?: string;
  mimeType?: string;
  contentDisposition?: string;
  headers?: Record<string, string>;
}

interface PersistedDownloadV2ProgressSnapshot {
  totalBytes?: number;
  receivedBytes?: number;
  speedBytesPerSecond?: number;
}

interface PersistedDownloadV2PersistenceSnapshot {
  tempFilePath?: string;
  finalFileUri?: string;
  finalDisplayPath?: string;
  partialFilePath?: string;
  finalFilePath?: string;
  writtenBytes?: number;
  etag?: string;
  lastModified?: string;
  acceptRanges?: string;
  contentRange?: string;
  validatorCapturedAt?: number;
  downloadDriver?: string;
  resumeMode?: string;
  needsFullRestart?: boolean;
  restartReason?: string;
  segmentPlan?: PersistedDownloadV2SegmentPlanSnapshot;
}

interface PersistedDownloadV2SegmentPlanSnapshot {
  version?: number;
  guid?: string;
  totalBytes?: number;
  segmentCount?: number;
  partFileBasePath?: string;
  etag?: string;
  lastModified?: string;
  acceptRanges?: string;
  createdAt?: number;
  updatedAt?: number;
  segments?: PersistedDownloadV2SegmentRecord[];
}

interface PersistedDownloadV2SegmentRecord {
  guid?: string;
  segmentIndex?: number;
  startByte?: number;
  endByte?: number;
  receivedBytes?: number;
  partFilePath?: string;
  status?: string;
  retryCount?: number;
  etag?: string;
  lastModified?: string;
  updatedAt?: number;
}

interface PersistedDownloadV2RuntimeSnapshot {
  platformTaskId?: string;
  platformTaskToken?: string;
  resumeCapability?: string;
}

interface PersistedDownloadV2Failure {
  code?: string;
  sourceCode?: number;
  message?: string;
  retriable?: boolean;
}

interface PersistedDownloadV2TaskTiming {
  createdAt?: number;
  updatedAt?: number;
  confirmedAt?: number;
  startedAt?: number;
  completedAt?: number;
  failedAt?: number;
  canceledAt?: number;
  removedAt?: number;
}

interface DownloadV2RecordLogSnapshot {
  guid: string;
  status: string;
  receivedBytes: number;
  totalBytes: number;
  writtenBytes: number;
  platformTaskId: string;
  taskToken: string;
  resumeCapability: string;
  driver: string;
}

interface DownloadV2RecordParseResult {
  records: DownloadV2TaskEntity[];
  activeCount: number;
  terminalCount: number;
  valid: boolean;
}

export interface DownloadV2RecordStore {
  loadRecords(): Promise<DownloadV2TaskEntity[]>;
  saveRecords(records: DownloadV2TaskEntity[]): Promise<void>;
  clearRecords(): Promise<void>;
}

export function normalizeDownloadV2DriverValue(value?: string): DownloadV2Driver | undefined {
  const normalized = String(value ?? '').trim();
  switch (normalized) {
    case 'libcurl':
      return 'libcurl';
    default:
      return undefined;
  }
}

export class ArkDownloadV2RecordStore implements DownloadV2RecordStore {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private diagnosticRecorder?: DownloadRuntimeDiagnosticRecorder;

  constructor(diagnosticRecorder?: DownloadRuntimeDiagnosticRecorder) {
    this.diagnosticRecorder = diagnosticRecorder;
  }

  async loadRecords(): Promise<DownloadV2TaskEntity[]> {
    const store = await this.getStore();
    const readStartEvent: DownloadRuntimeDiagnosticEvent = {
      owner: 'record_store',
      operation: 'record_load',
      state: 'prefs_read_pending',
      result: 'begin'
    };
    await this.diagnosticRecorder?.recordDownloadRuntimeDiagnosticAndWait(readStartEvent);
    const readStartedAt = Date.now();
    const rawValue = store.getSync(DOWNLOAD_V2_RECORDS_KEY, '[]');
    const rawText = String(rawValue);
    const parseStartEvent: DownloadRuntimeDiagnosticEvent = {
      owner: 'record_store',
      operation: 'record_load',
      state: `parse_pending chars=${rawText.length} read=${bucketRuntimeDiagnosticDuration(Date.now() - readStartedAt)}`,
      result: 'progress'
    };
    await this.diagnosticRecorder?.recordDownloadRuntimeDiagnosticAndWait(parseStartEvent);
    const parseStartedAt = Date.now();
    const parseResult = this.parseRecords(rawText);
    const records = parseResult.records;
    const loadResultEvent: DownloadRuntimeDiagnosticEvent = {
      owner: 'record_store',
      operation: 'record_load',
      state: `records=${records.length} active=${parseResult.activeCount} terminal=${parseResult.terminalCount} parse=${bucketRuntimeDiagnosticDuration(Date.now() - parseStartedAt)}`,
      result: parseResult.valid ? 'ok' : 'invalid'
    };
    this.diagnosticRecorder?.recordDownloadRuntimeDiagnostic(loadResultEvent);
    const recordSnapshots = records.map((record: DownloadV2TaskEntity): DownloadV2RecordLogSnapshot => {
      return this.toLogSnapshot(record);
    });
    hilog.info(
      DOWNLOAD_V2_RECORD_STORE_DOMAIN,
      DOWNLOAD_V2_RECORD_STORE_TAG,
      'load count=%{public}d records=%{public}s',
      records.length,
      JSON.stringify(recordSnapshots)
    );
    return records;
  }

  async saveRecords(records: DownloadV2TaskEntity[]): Promise<void> {
    const store = await this.getStore();
    const persistedRecords = records.map((record: DownloadV2TaskEntity) => this.toPersistedRecord(record));
    const recordSnapshots = records.map((record: DownloadV2TaskEntity): DownloadV2RecordLogSnapshot => {
      return this.toLogSnapshot(record);
    });
    hilog.info(
      DOWNLOAD_V2_RECORD_STORE_DOMAIN,
      DOWNLOAD_V2_RECORD_STORE_TAG,
      'save count=%{public}d records=%{public}s',
      records.length,
      JSON.stringify(recordSnapshots)
    );
    store.putSync(DOWNLOAD_V2_RECORDS_KEY, JSON.stringify(persistedRecords));
    store.flushSync();
  }

  async clearRecords(): Promise<void> {
    const store = await this.getStore();
    store.putSync(DOWNLOAD_V2_RECORDS_KEY, '[]');
    store.flushSync();
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        DOWNLOAD_V2_RECORDS_STORE_NAME
      ).then((store: preferences.Preferences) => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }

  private parseRecords(value: string): DownloadV2RecordParseResult {
    try {
      const parsed = JSON.parse(value) as PersistedDownloadV2Record[];
      if (!Array.isArray(parsed)) {
        return { records: [], activeCount: 0, terminalCount: 0, valid: false };
      }
      const records: DownloadV2TaskEntity[] = [];
      let activeCount = 0;
      let terminalCount = 0;
      parsed.forEach((record: PersistedDownloadV2Record) => {
        const normalized = this.toTaskEntity(record);
        if (normalized !== undefined) {
          records.push(normalized);
          if (normalized.status === 'created' || normalized.status === 'queued' ||
            normalized.status === 'running' || normalized.status === 'paused') {
            activeCount += 1;
          } else if (normalized.status === 'completed' || normalized.status === 'failed' ||
            normalized.status === 'canceled' || normalized.status === 'removed') {
            terminalCount += 1;
          }
        }
      });
      return {
        records: records,
        activeCount: activeCount,
        terminalCount: terminalCount,
        valid: true
      };
    } catch (_error) {
      return { records: [], activeCount: 0, terminalCount: 0, valid: false };
    }
  }

  private toTaskEntity(record: PersistedDownloadV2Record): DownloadV2TaskEntity | undefined {
    const guid = String(record.guid ?? '').trim();
    const suggestedFileName = String(record.suggestedFileName ?? '').trim();
    const request = record.request;
    const url = String(request?.url ?? '').trim();
    if (guid.length <= 0 || suggestedFileName.length <= 0 || url.length <= 0) {
      return undefined;
    }
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(record.privacyMode);
    return createDownloadV2TaskEntity({
      guid: guid,
      windowId: record.windowId?.trim() ?? '',
      profileId: normalizeBrowserProfileId(record.profileId),
      privacyMode: normalizedPrivacyMode,
      dataScope: normalizeBrowserDataScope(record.dataScope, normalizedPrivacyMode),
      request: this.toRequestContext(request),
      suggestedFileName: suggestedFileName,
      resolvedFileName: this.normalizeOptionalString(record.resolvedFileName),
      status: this.normalizeStatus(record.status),
      progress: this.toProgressSnapshot(record.progress),
      persistence: this.toPersistenceSnapshot(record.persistence),
      runtime: this.toRuntimeSnapshot(record.runtime),
      failure: this.toFailure(record.failure),
      timing: this.toTiming(record.timing)
    });
  }

  private toPersistedRecord(record: DownloadV2TaskEntity): PersistedDownloadV2Record {
    return {
      guid: record.guid,
      windowId: record.windowId,
      profileId: record.profileId,
      privacyMode: record.privacyMode,
      dataScope: record.dataScope,
      request: {
        url: record.request.url,
        originalUrl: record.request.originalUrl,
        method: record.request.method,
        sourcePageUrl: record.request.sourcePageUrl,
        sourceHost: record.request.sourceHost,
        userAgent: record.request.userAgent,
        referer: record.request.referer,
        mimeType: record.request.mimeType,
        contentDisposition: record.request.contentDisposition,
        headers: cloneHeaders(record.request.headers)
      },
      suggestedFileName: record.suggestedFileName,
      resolvedFileName: record.resolvedFileName,
      status: record.status,
      progress: {
        totalBytes: record.progress.totalBytes,
        receivedBytes: record.progress.receivedBytes,
        speedBytesPerSecond: record.progress.speedBytesPerSecond
      },
      persistence: {
        tempFilePath: record.persistence.tempFilePath,
        finalFileUri: record.persistence.finalFileUri,
        finalDisplayPath: record.persistence.finalDisplayPath,
        partialFilePath: record.persistence.partialFilePath,
        finalFilePath: record.persistence.finalFilePath,
        writtenBytes: record.persistence.writtenBytes,
        etag: record.persistence.etag,
        lastModified: record.persistence.lastModified,
        acceptRanges: record.persistence.acceptRanges,
        contentRange: record.persistence.contentRange,
        validatorCapturedAt: record.persistence.validatorCapturedAt,
        downloadDriver: record.persistence.downloadDriver,
        resumeMode: record.persistence.resumeMode,
        needsFullRestart: record.persistence.needsFullRestart,
        restartReason: record.persistence.restartReason,
        segmentPlan: this.toPersistedSegmentPlan(record.persistence.segmentPlan)
      },
      runtime: {
        platformTaskId: record.runtime.platformTaskId,
        platformTaskToken: record.runtime.platformTaskToken,
        resumeCapability: record.runtime.resumeCapability
      },
      failure: {
        code: record.failure.code,
        sourceCode: record.failure.sourceCode,
        message: record.failure.message,
        retriable: record.failure.retriable
      },
      timing: {
        createdAt: record.timing.createdAt,
        updatedAt: record.timing.updatedAt,
        confirmedAt: record.timing.confirmedAt,
        startedAt: record.timing.startedAt,
        completedAt: record.timing.completedAt,
        failedAt: record.timing.failedAt,
        canceledAt: record.timing.canceledAt,
        removedAt: record.timing.removedAt
      }
    };
  }

  private toRequestContext(request?: PersistedDownloadV2RequestContext): DownloadV2RequestContext {
    return {
      url: String(request?.url ?? '').trim(),
      originalUrl: this.normalizeOptionalString(request?.originalUrl),
      method: String(request?.method ?? 'GET').trim() || 'GET',
      sourcePageUrl: this.normalizeOptionalString(request?.sourcePageUrl),
      sourceHost: this.normalizeOptionalString(request?.sourceHost),
      userAgent: this.normalizeOptionalString(request?.userAgent),
      referer: this.normalizeOptionalString(request?.referer),
      mimeType: this.normalizeOptionalString(request?.mimeType),
      contentDisposition: this.normalizeOptionalString(request?.contentDisposition),
      headers: cloneHeaders(request?.headers)
    };
  }

  private toProgressSnapshot(progress?: PersistedDownloadV2ProgressSnapshot): DownloadV2ProgressSnapshot {
    return {
      totalBytes: this.normalizeNonNegativeNumber(progress?.totalBytes),
      receivedBytes: this.normalizeNonNegativeNumber(progress?.receivedBytes),
      speedBytesPerSecond: this.normalizeNonNegativeNumber(progress?.speedBytesPerSecond)
    };
  }

  private toPersistenceSnapshot(snapshot?: PersistedDownloadV2PersistenceSnapshot): DownloadV2PersistenceSnapshot {
    return {
      tempFilePath: this.normalizeOptionalString(snapshot?.tempFilePath),
      finalFileUri: this.normalizeOptionalString(snapshot?.finalFileUri),
      finalDisplayPath: this.normalizeOptionalString(snapshot?.finalDisplayPath),
      partialFilePath: this.normalizeOptionalString(snapshot?.partialFilePath),
      finalFilePath: this.normalizeOptionalString(snapshot?.finalFilePath),
      writtenBytes: this.normalizeNonNegativeNumber(snapshot?.writtenBytes),
      etag: this.normalizeOptionalString(snapshot?.etag),
      lastModified: this.normalizeOptionalString(snapshot?.lastModified),
      acceptRanges: this.normalizeOptionalString(snapshot?.acceptRanges),
      contentRange: this.normalizeOptionalString(snapshot?.contentRange),
      validatorCapturedAt: this.normalizeNonNegativeNumber(snapshot?.validatorCapturedAt),
      downloadDriver: this.normalizeDownloadDriver(snapshot?.downloadDriver),
      resumeMode: this.normalizeResumeMode(snapshot?.resumeMode),
      needsFullRestart: snapshot?.needsFullRestart === true,
      restartReason: this.normalizeOptionalString(snapshot?.restartReason),
      segmentPlan: this.toSegmentPlanSnapshot(snapshot?.segmentPlan)
    };
  }

  private toPersistedSegmentPlan(
    snapshot?: DownloadV2SegmentPlanSnapshot
  ): PersistedDownloadV2SegmentPlanSnapshot | undefined {
    const normalized = cloneDownloadV2SegmentPlanSnapshot(snapshot);
    if (normalized === undefined) {
      return undefined;
    }
    return {
      version: normalized.version,
      guid: normalized.guid,
      totalBytes: normalized.totalBytes,
      segmentCount: normalized.segmentCount,
      partFileBasePath: normalized.partFileBasePath,
      etag: normalized.etag,
      lastModified: normalized.lastModified,
      acceptRanges: normalized.acceptRanges,
      createdAt: normalized.createdAt,
      updatedAt: normalized.updatedAt,
      segments: normalized.segments.map((segment: DownloadV2SegmentRecord): PersistedDownloadV2SegmentRecord => {
        return {
          guid: segment.guid,
          segmentIndex: segment.segmentIndex,
          startByte: segment.startByte,
          endByte: segment.endByte,
          receivedBytes: segment.receivedBytes,
          partFilePath: segment.partFilePath,
          status: segment.status,
          retryCount: segment.retryCount,
          etag: segment.etag,
          lastModified: segment.lastModified,
          updatedAt: segment.updatedAt
        };
      })
    };
  }

  private toSegmentPlanSnapshot(
    snapshot?: PersistedDownloadV2SegmentPlanSnapshot
  ): DownloadV2SegmentPlanSnapshot | undefined {
    if (snapshot === undefined) {
      return undefined;
    }
    const segments: DownloadV2SegmentRecord[] = Array.isArray(snapshot.segments)
      ? snapshot.segments.map((segment: PersistedDownloadV2SegmentRecord): DownloadV2SegmentRecord => {
        return {
          guid: this.normalizeOptionalString(segment.guid) ?? this.normalizeOptionalString(snapshot.guid) ?? '',
          segmentIndex: this.normalizeNonNegativeNumber(segment.segmentIndex),
          startByte: this.normalizeNonNegativeNumber(segment.startByte),
          endByte: this.normalizeNonNegativeNumber(segment.endByte),
          receivedBytes: this.normalizeNonNegativeNumber(segment.receivedBytes),
          partFilePath: this.normalizeOptionalString(segment.partFilePath) ?? '',
          status: this.normalizeSegmentStatus(segment.status),
          retryCount: this.normalizeNonNegativeNumber(segment.retryCount),
          etag: this.normalizeOptionalString(segment.etag),
          lastModified: this.normalizeOptionalString(segment.lastModified),
          updatedAt: this.normalizeTimestamp(segment.updatedAt)
        };
      })
      : [];
    return normalizeDownloadV2SegmentPlanSnapshot({
      version: this.normalizeNonNegativeNumber(snapshot.version) || 1,
      guid: this.normalizeOptionalString(snapshot.guid) ?? '',
      totalBytes: this.normalizeNonNegativeNumber(snapshot.totalBytes),
      segmentCount: this.normalizeNonNegativeNumber(snapshot.segmentCount),
      partFileBasePath: this.normalizeOptionalString(snapshot.partFileBasePath) ?? '',
      etag: this.normalizeOptionalString(snapshot.etag),
      lastModified: this.normalizeOptionalString(snapshot.lastModified),
      acceptRanges: this.normalizeOptionalString(snapshot.acceptRanges),
      createdAt: this.normalizeTimestamp(snapshot.createdAt),
      updatedAt: this.normalizeTimestamp(snapshot.updatedAt),
      segments: segments
    });
  }

  private toRuntimeSnapshot(snapshot?: PersistedDownloadV2RuntimeSnapshot): DownloadV2RuntimeSnapshot {
    return {
      platformTaskId: this.normalizeOptionalString(snapshot?.platformTaskId),
      platformTaskToken: this.normalizeOptionalString(snapshot?.platformTaskToken),
      resumeCapability: this.normalizeResumeCapability(snapshot?.resumeCapability)
    };
  }

  private toFailure(failure?: PersistedDownloadV2Failure): DownloadV2Failure {
    if (failure === undefined) {
      return buildDownloadV2EmptyFailure();
    }
    return {
      code: this.normalizeFailureCode(failure.code),
      sourceCode: failure.sourceCode,
      message: String(failure.message ?? ''),
      retriable: failure.retriable === true
    };
  }

  private toTiming(timing?: PersistedDownloadV2TaskTiming): DownloadV2TaskTiming {
    const now = this.normalizeTimestamp(timing?.updatedAt ?? timing?.createdAt);
    return {
      createdAt: this.normalizeTimestamp(timing?.createdAt),
      updatedAt: now,
      confirmedAt: this.normalizeOptionalTimestamp(timing?.confirmedAt),
      startedAt: this.normalizeOptionalTimestamp(timing?.startedAt),
      completedAt: this.normalizeOptionalTimestamp(timing?.completedAt),
      failedAt: this.normalizeOptionalTimestamp(timing?.failedAt),
      canceledAt: this.normalizeOptionalTimestamp(timing?.canceledAt),
      removedAt: this.normalizeOptionalTimestamp(timing?.removedAt)
    };
  }

  private normalizeStatus(status?: string): DownloadV2Status {
    switch (String(status ?? '').trim()) {
      case 'created':
      case 'awaiting_confirmation':
      case 'queued':
      case 'running':
      case 'paused':
      case 'completed':
      case 'failed':
      case 'canceled':
      case 'removed':
        return status as DownloadV2Status;
      default:
        return 'created';
    }
  }

  private normalizeFailureCode(code?: string): DownloadV2FailureCode {
    switch (String(code ?? '').trim()) {
      case 'network':
      case 'server':
      case 'file_system':
      case 'permission':
      case 'context_lost':
      case 'unsupported':
      case 'canceled':
      case 'unknown':
        return code as DownloadV2FailureCode;
      default:
        return 'none';
    }
  }

  private normalizeResumeCapability(value?: string): DownloadV2ResumeCapability {
    switch (String(value ?? '').trim()) {
      case 'retry_only':
      case 'live_resume':
        return value as DownloadV2ResumeCapability;
      default:
        return 'none';
    }
  }

  private normalizeDownloadDriver(value?: string): DownloadV2Driver | undefined {
    return normalizeDownloadV2DriverValue(value);
  }

  private normalizeResumeMode(value?: string): DownloadV2ResumeMode | undefined {
    switch (String(value ?? '').trim()) {
      case 'none':
      case 'platform_live_resume':
        return value as DownloadV2ResumeMode;
      default:
        return undefined;
    }
  }

  private normalizeOptionalString(value: string | undefined): string | undefined {
    const normalized = String(value ?? '').trim();
    return normalized.length > 0 ? normalized : undefined;
  }

  private normalizeSegmentStatus(value?: string): DownloadV2SegmentStatus {
    switch (String(value ?? '').trim()) {
      case 'running':
      case 'paused':
      case 'completed':
      case 'failed':
        return value as DownloadV2SegmentStatus;
      default:
        return 'pending';
    }
  }

  private normalizeNonNegativeNumber(value?: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.floor(value);
  }

  private normalizeTimestamp(value?: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
      return Date.now();
    }
    return Math.floor(value);
  }

  private normalizeOptionalTimestamp(value?: number): number | undefined {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
      return undefined;
    }
    return Math.floor(value);
  }

  private toLogSnapshot(record: DownloadV2TaskEntity): DownloadV2RecordLogSnapshot {
    return {
      guid: record.guid,
      status: record.status,
      receivedBytes: record.progress.receivedBytes,
      totalBytes: record.progress.totalBytes,
      writtenBytes: record.persistence.writtenBytes ?? 0,
      platformTaskId: record.runtime.platformTaskId ?? '',
      taskToken: (record.runtime.platformTaskToken?.trim().length ?? 0) > 0 ? 'yes' : 'no',
      resumeCapability: record.runtime.resumeCapability,
      driver: record.persistence.downloadDriver ?? 'libcurl'
    };
  }
}

function cloneHeaders(headers?: Record<string, string>): Record<string, string> | undefined {
  if (headers === undefined) {
    return undefined;
  }
  const nextHeaders: Record<string, string> = {};
  Object.keys(headers).forEach((key: string) => {
    nextHeaders[key] = headers[key];
  });
  return nextHeaders;
}

function cloneDownloadV2TaskEntity(task: DownloadV2TaskEntity): DownloadV2TaskEntity {
  return createDownloadV2TaskEntity({
    guid: task.guid,
    windowId: task.windowId,
    profileId: task.profileId,
    privacyMode: task.privacyMode,
    dataScope: task.dataScope,
    request: {
      url: task.request.url,
      method: task.request.method,
      sourcePageUrl: task.request.sourcePageUrl,
      sourceHost: task.request.sourceHost,
      userAgent: task.request.userAgent,
      referer: task.request.referer,
      mimeType: task.request.mimeType,
      contentDisposition: task.request.contentDisposition,
      headers: cloneHeaders(task.request.headers)
    },
    suggestedFileName: task.suggestedFileName,
    resolvedFileName: task.resolvedFileName,
    status: task.status,
    progress: {
      totalBytes: task.progress.totalBytes,
      receivedBytes: task.progress.receivedBytes,
      speedBytesPerSecond: task.progress.speedBytesPerSecond
    },
    persistence: {
      tempFilePath: task.persistence.tempFilePath,
      finalFileUri: task.persistence.finalFileUri,
      finalDisplayPath: task.persistence.finalDisplayPath,
      partialFilePath: task.persistence.partialFilePath,
      finalFilePath: task.persistence.finalFilePath,
      writtenBytes: task.persistence.writtenBytes,
      etag: task.persistence.etag,
      lastModified: task.persistence.lastModified,
      acceptRanges: task.persistence.acceptRanges,
      contentRange: task.persistence.contentRange,
      validatorCapturedAt: task.persistence.validatorCapturedAt,
      downloadDriver: task.persistence.downloadDriver,
      resumeMode: task.persistence.resumeMode,
      needsFullRestart: task.persistence.needsFullRestart,
      restartReason: task.persistence.restartReason,
      segmentPlan: cloneDownloadV2SegmentPlanSnapshot(task.persistence.segmentPlan)
    },
    runtime: {
      platformTaskId: task.runtime.platformTaskId,
      platformTaskToken: task.runtime.platformTaskToken,
      resumeCapability: task.runtime.resumeCapability
    },
    failure: {
      code: task.failure.code,
      sourceCode: task.failure.sourceCode,
      message: task.failure.message,
      retriable: task.failure.retriable
    },
    timing: {
      createdAt: task.timing.createdAt,
      updatedAt: task.timing.updatedAt,
      confirmedAt: task.timing.confirmedAt,
      startedAt: task.timing.startedAt,
      completedAt: task.timing.completedAt,
      failedAt: task.timing.failedAt,
      canceledAt: task.timing.canceledAt,
      removedAt: task.timing.removedAt
    }
  });
}
