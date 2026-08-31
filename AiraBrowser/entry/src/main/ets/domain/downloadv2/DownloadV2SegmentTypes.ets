export type DownloadV2SegmentStatus =
  'pending' |
  'running' |
  'paused' |
  'completed' |
  'failed';

export interface DownloadV2SegmentRecord {
  guid: string;
  segmentIndex: number;
  startByte: number;
  endByte: number;
  receivedBytes: number;
  partFilePath: string;
  status: DownloadV2SegmentStatus;
  retryCount: number;
  etag?: string;
  lastModified?: string;
  updatedAt: number;
}

export interface DownloadV2SegmentPlanSnapshot {
  version: number;
  guid: string;
  totalBytes: number;
  segmentCount: number;
  partFileBasePath: string;
  etag?: string;
  lastModified?: string;
  acceptRanges?: string;
  createdAt: number;
  updatedAt: number;
  segments: DownloadV2SegmentRecord[];
}

export function cloneDownloadV2SegmentPlanSnapshot(
  snapshot?: DownloadV2SegmentPlanSnapshot
): DownloadV2SegmentPlanSnapshot | undefined {
  if (snapshot === undefined) {
    return undefined;
  }
  const normalized = normalizeDownloadV2SegmentPlanSnapshot(snapshot);
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
    segments: normalized.segments.map((segment: DownloadV2SegmentRecord) => {
      return cloneDownloadV2SegmentRecord(segment);
    })
  };
}

export function normalizeDownloadV2SegmentPlanSnapshot(
  snapshot?: DownloadV2SegmentPlanSnapshot
): DownloadV2SegmentPlanSnapshot | undefined {
  if (snapshot === undefined) {
    return undefined;
  }
  const guid = normalizeRequiredString(snapshot.guid);
  const basePath = normalizeRequiredString(snapshot.partFileBasePath);
  const segments: DownloadV2SegmentRecord[] = [];
  if (Array.isArray(snapshot.segments)) {
    snapshot.segments.forEach((segment: DownloadV2SegmentRecord) => {
      const normalizedSegment = normalizeDownloadV2SegmentRecord(segment, guid);
      if (normalizedSegment !== undefined) {
        segments.push(normalizedSegment);
      }
    });
  }
  if (guid.length <= 0 || basePath.length <= 0 || segments.length <= 0) {
    return undefined;
  }
  const totalBytes = normalizeNonNegativeNumber(snapshot.totalBytes);
  return {
    version: normalizePositiveNumber(snapshot.version, 1),
    guid: guid,
    totalBytes: totalBytes,
    segmentCount: segments.length,
    partFileBasePath: basePath,
    etag: normalizeOptionalString(snapshot.etag),
    lastModified: normalizeOptionalString(snapshot.lastModified),
    acceptRanges: normalizeOptionalString(snapshot.acceptRanges),
    createdAt: normalizeTimestamp(snapshot.createdAt),
    updatedAt: normalizeTimestamp(snapshot.updatedAt),
    segments: segments
  };
}

export function cloneDownloadV2SegmentRecord(record: DownloadV2SegmentRecord): DownloadV2SegmentRecord {
  return {
    guid: record.guid,
    segmentIndex: record.segmentIndex,
    startByte: record.startByte,
    endByte: record.endByte,
    receivedBytes: record.receivedBytes,
    partFilePath: record.partFilePath,
    status: record.status,
    retryCount: record.retryCount,
    etag: record.etag,
    lastModified: record.lastModified,
    updatedAt: record.updatedAt
  };
}

function normalizeDownloadV2SegmentRecord(
  record: DownloadV2SegmentRecord,
  fallbackGuid: string
): DownloadV2SegmentRecord | undefined {
  const guid = normalizeRequiredString(record.guid) || fallbackGuid;
  const partFilePath = normalizeRequiredString(record.partFilePath);
  const startByte = normalizeNonNegativeNumber(record.startByte);
  const endByte = normalizeNonNegativeNumber(record.endByte);
  if (guid.length <= 0 || partFilePath.length <= 0 || endByte < startByte) {
    return undefined;
  }
  const segmentSize = endByte - startByte + 1;
  return {
    guid: guid,
    segmentIndex: normalizeNonNegativeNumber(record.segmentIndex),
    startByte: startByte,
    endByte: endByte,
    receivedBytes: Math.min(normalizeNonNegativeNumber(record.receivedBytes), segmentSize),
    partFilePath: partFilePath,
    status: normalizeSegmentStatus(record.status),
    retryCount: normalizeNonNegativeNumber(record.retryCount),
    etag: normalizeOptionalString(record.etag),
    lastModified: normalizeOptionalString(record.lastModified),
    updatedAt: normalizeTimestamp(record.updatedAt)
  };
}

function normalizeSegmentStatus(value?: string): DownloadV2SegmentStatus {
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

function normalizeRequiredString(value?: string): string {
  return String(value ?? '').trim();
}

function normalizeOptionalString(value?: string): string | undefined {
  const normalized = normalizeRequiredString(value);
  return normalized.length > 0 ? normalized : undefined;
}

function normalizeNonNegativeNumber(value?: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.floor(value);
}

function normalizePositiveNumber(value: number | undefined, fallback: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    return fallback;
  }
  return Math.floor(value);
}

function normalizeTimestamp(value?: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    return Date.now();
  }
  return Math.floor(value);
}
