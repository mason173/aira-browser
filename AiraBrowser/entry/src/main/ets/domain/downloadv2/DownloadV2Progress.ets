import { DownloadV2ProgressSnapshot, DownloadV2Status } from './DownloadV2Types';

/** Negative means unknown. HLS resource progress is independent of its size estimate. */
export function resolveDownloadProgressFraction(progress: DownloadV2ProgressSnapshot): number {
  const fraction = progress.progressFraction ?? -1;
  if (Number.isFinite(fraction) && fraction >= 0) {
    return Math.min(1, fraction);
  }
  if (Number.isFinite(progress.totalBytes) && progress.totalBytes > 0 &&
    Number.isFinite(progress.receivedBytes)) {
    return Math.max(0, Math.min(1, progress.receivedBytes / progress.totalBytes));
  }
  return -1;
}

export function resolveDownloadProgressPercent(progress: DownloadV2ProgressSnapshot, status: DownloadV2Status): number {
  return status === 'completed' ? 100 : Math.max(0, Math.min(99,
    Math.floor(resolveDownloadProgressFraction(progress) * 100)));
}

export function resolveDownloadDisplayTotal(progress: DownloadV2ProgressSnapshot): number {
  if (Number.isFinite(progress.totalBytes) && progress.totalBytes > 0) return progress.totalBytes;
  const estimate = progress.estimatedTotalBytes ?? 0;
  return Number.isFinite(estimate) && estimate > 0 ? Math.max(estimate, progress.receivedBytes) : 0;
}

export function isDownloadTotalEstimated(progress: DownloadV2ProgressSnapshot): boolean {
  return progress.totalBytes <= 0 && resolveDownloadDisplayTotal(progress) > 0;
}
