import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  DownloadV2Failure,
  DownloadV2PersistenceSnapshot,
  DownloadV2ProgressSnapshot,
  DownloadV2RequestContext,
  DownloadV2ResumeCapability,
  DownloadV2RuntimeSnapshot,
  DownloadV2Status,
  DownloadV2TaskBoundary,
  DownloadV2TaskTiming,
  buildDownloadV2EmptyFailure
} from './DownloadV2Types';
import { cloneDownloadV2SegmentPlanSnapshot } from './DownloadV2SegmentTypes';

export interface DownloadV2TaskIdentity {
  id: string;
  guid: string;
}

export interface DownloadV2TaskEntity extends DownloadV2TaskIdentity, DownloadV2TaskBoundary {
  request: DownloadV2RequestContext;
  suggestedFileName: string;
  resolvedFileName?: string;
  status: DownloadV2Status;
  progress: DownloadV2ProgressSnapshot;
  persistence: DownloadV2PersistenceSnapshot;
  runtime: DownloadV2RuntimeSnapshot;
  failure: DownloadV2Failure;
  timing: DownloadV2TaskTiming;
}

export interface CreateDownloadV2TaskEntityInput extends DownloadV2TaskBoundary {
  guid: string;
  request: DownloadV2RequestContext;
  suggestedFileName: string;
  resolvedFileName?: string;
  status?: DownloadV2Status;
  progress?: Partial<DownloadV2ProgressSnapshot>;
  persistence?: DownloadV2PersistenceSnapshot;
  runtime?: Partial<DownloadV2RuntimeSnapshot>;
  failure?: DownloadV2Failure;
  timing?: Partial<DownloadV2TaskTiming>;
}

export interface MutableDownloadV2TaskEntityPatch {
  request?: DownloadV2RequestContext;
  suggestedFileName?: string;
  resolvedFileName?: string;
  status?: DownloadV2Status;
  progress?: Partial<DownloadV2ProgressSnapshot>;
  persistence?: DownloadV2PersistenceSnapshot;
  runtime?: Partial<DownloadV2RuntimeSnapshot>;
  failure?: DownloadV2Failure;
  timing?: Partial<DownloadV2TaskTiming>;
  clearFailure?: boolean;
  clearTimingFields?: Array<'confirmedAt' | 'startedAt' | 'completedAt' | 'failedAt' | 'canceledAt' | 'removedAt'>;
  windowId?: string;
}

export function createDownloadV2TaskEntity(input: CreateDownloadV2TaskEntityInput): DownloadV2TaskEntity {
  const now = input.timing?.updatedAt ?? input.timing?.createdAt ?? Date.now();
  return {
    id: buildDownloadV2TaskId(input.guid),
    guid: input.guid,
    windowId: input.windowId,
    profileId: input.profileId,
    privacyMode: input.privacyMode,
    dataScope: input.dataScope,
    request: cloneRequestContext(input.request),
    suggestedFileName: input.suggestedFileName,
    resolvedFileName: input.resolvedFileName,
    status: input.status ?? 'created',
    progress: {
      totalBytes: input.progress?.totalBytes ?? 0,
      receivedBytes: input.progress?.receivedBytes ?? 0,
      speedBytesPerSecond: input.progress?.speedBytesPerSecond ?? 0
    },
    persistence: clonePersistenceSnapshot(input.persistence),
    runtime: {
      platformTaskId: input.runtime?.platformTaskId,
      platformTaskToken: input.runtime?.platformTaskToken,
      resumeCapability: input.runtime?.resumeCapability ?? 'none'
    },
    failure: cloneFailure(input.failure),
    timing: {
      createdAt: input.timing?.createdAt ?? now,
      updatedAt: now,
      confirmedAt: input.timing?.confirmedAt,
      startedAt: input.timing?.startedAt,
      completedAt: input.timing?.completedAt,
      failedAt: input.timing?.failedAt,
      canceledAt: input.timing?.canceledAt,
      removedAt: input.timing?.removedAt
    }
  };
}

export function canContinueDownloadV2TaskFromPersistedData(task: DownloadV2TaskEntity): boolean {
  if (task.status !== 'failed' || task.failure.code !== 'context_lost' ||
    task.runtime.resumeCapability !== 'retry_only') {
    return false;
  }
  const partialBytes = Math.max(task.progress.receivedBytes, task.persistence.writtenBytes ?? 0);
  const tempFilePath = task.persistence.tempFilePath?.trim() ?? '';
  return partialBytes > 0 && tempFilePath.length > 0;
}

export function canContinueDownloadV2Task(task: DownloadV2TaskEntity): boolean {
  return task.runtime.resumeCapability === 'live_resume' || canContinueDownloadV2TaskFromPersistedData(task);
}

export function patchDownloadV2TaskEntity(
  current: DownloadV2TaskEntity,
  patch: MutableDownloadV2TaskEntityPatch
): DownloadV2TaskEntity {
  const clearedTimingFields = new Set<string>(patch.clearTimingFields ?? []);
  return {
    id: current.id,
    guid: current.guid,
    windowId: patch.windowId ?? current.windowId,
    profileId: current.profileId,
    privacyMode: current.privacyMode,
    dataScope: current.dataScope,
    request: patch.request === undefined ? cloneRequestContext(current.request) : cloneRequestContext(patch.request),
    suggestedFileName: patch.suggestedFileName ?? current.suggestedFileName,
    resolvedFileName: patch.resolvedFileName ?? current.resolvedFileName,
    status: patch.status ?? current.status,
    progress: {
      totalBytes: patch.progress?.totalBytes ?? current.progress.totalBytes,
      receivedBytes: patch.progress?.receivedBytes ?? current.progress.receivedBytes,
      speedBytesPerSecond: patch.progress?.speedBytesPerSecond ?? current.progress.speedBytesPerSecond
    },
    persistence: patch.persistence === undefined ? clonePersistenceSnapshot(current.persistence) : clonePersistenceSnapshot(patch.persistence),
    runtime: {
      platformTaskId: patch.runtime?.platformTaskId ?? current.runtime.platformTaskId,
      platformTaskToken: patch.runtime?.platformTaskToken ?? current.runtime.platformTaskToken,
      resumeCapability: patch.runtime?.resumeCapability ?? current.runtime.resumeCapability
    },
    failure: patch.clearFailure === true
      ? buildDownloadV2EmptyFailure()
      : (patch.failure === undefined ? cloneFailure(current.failure) : cloneFailure(patch.failure)),
    timing: {
      createdAt: current.timing.createdAt,
      updatedAt: patch.timing?.updatedAt ?? Date.now(),
      confirmedAt: resolvePatchedTimingValue('confirmedAt', current.timing.confirmedAt, patch, clearedTimingFields),
      startedAt: resolvePatchedTimingValue('startedAt', current.timing.startedAt, patch, clearedTimingFields),
      completedAt: resolvePatchedTimingValue('completedAt', current.timing.completedAt, patch, clearedTimingFields),
      failedAt: resolvePatchedTimingValue('failedAt', current.timing.failedAt, patch, clearedTimingFields),
      canceledAt: resolvePatchedTimingValue('canceledAt', current.timing.canceledAt, patch, clearedTimingFields),
      removedAt: resolvePatchedTimingValue('removedAt', current.timing.removedAt, patch, clearedTimingFields)
    }
  };
}

export function buildDownloadV2TaskId(guid: string): string {
  return `download-v2:${guid}`;
}

export function createDownloadV2BoundarySnapshot(
  profileId: BrowserProfileId,
  privacyMode: BrowserSessionPrivacyMode,
  dataScope: BrowserDataScope,
  windowId: string = ''
): DownloadV2TaskBoundary {
  return {
    windowId: windowId,
    profileId: profileId,
    privacyMode: privacyMode,
    dataScope: dataScope
  };
}

function resolvePatchedTimingValue(
  field: 'confirmedAt' | 'startedAt' | 'completedAt' | 'failedAt' | 'canceledAt' | 'removedAt',
  currentValue: number | undefined,
  patch: MutableDownloadV2TaskEntityPatch,
  clearedFields: Set<string>
): number | undefined {
  if (clearedFields.has(field)) {
    return undefined;
  }
  const timing = patch.timing;
  if (timing === undefined) {
    return currentValue;
  }
  switch (field) {
    case 'confirmedAt':
      return timing.confirmedAt ?? currentValue;
    case 'startedAt':
      return timing.startedAt ?? currentValue;
    case 'completedAt':
      return timing.completedAt ?? currentValue;
    case 'failedAt':
      return timing.failedAt ?? currentValue;
    case 'canceledAt':
      return timing.canceledAt ?? currentValue;
    case 'removedAt':
      return timing.removedAt ?? currentValue;
    default:
      return currentValue;
  }
}

function cloneRequestContext(request: DownloadV2RequestContext): DownloadV2RequestContext {
  const nextHeaders = cloneHeaders(request.headers);
  return {
    url: request.url,
    originalUrl: request.originalUrl,
    method: request.method,
    sourcePageUrl: request.sourcePageUrl,
    sourceHost: request.sourceHost,
    userAgent: request.userAgent,
    referer: request.referer,
    mimeType: request.mimeType,
    contentDisposition: request.contentDisposition,
    headers: nextHeaders
  };
}

function clonePersistenceSnapshot(snapshot?: DownloadV2PersistenceSnapshot): DownloadV2PersistenceSnapshot {
  return {
    tempFilePath: snapshot?.tempFilePath,
    finalFileUri: snapshot?.finalFileUri,
    finalDisplayPath: snapshot?.finalDisplayPath,
    partialFilePath: snapshot?.partialFilePath,
    finalFilePath: snapshot?.finalFilePath,
    writtenBytes: snapshot?.writtenBytes,
    etag: snapshot?.etag,
    lastModified: snapshot?.lastModified,
    acceptRanges: snapshot?.acceptRanges,
    contentRange: snapshot?.contentRange,
    validatorCapturedAt: snapshot?.validatorCapturedAt,
    downloadDriver: snapshot?.downloadDriver,
    resumeMode: snapshot?.resumeMode,
    needsFullRestart: snapshot?.needsFullRestart,
    restartReason: snapshot?.restartReason,
    segmentPlan: cloneDownloadV2SegmentPlanSnapshot(snapshot?.segmentPlan)
  };
}

function cloneFailure(failure?: DownloadV2Failure): DownloadV2Failure {
  if (failure === undefined) {
    return buildDownloadV2EmptyFailure();
  }
  return {
    code: failure.code,
    sourceCode: failure.sourceCode,
    message: failure.message,
    retriable: failure.retriable
  };
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
