import { DownloadV2ManagementAction, DownloadV2Status } from '../../domain/downloadv2/DownloadV2Types';
import { resolveAppResourceText } from '../resources/AppResourceText';

export interface DownloadSelectionCandidate {
  guid: string;
  status: DownloadV2Status;
}

export function downloadSelectionEmptyToast(): string {
  return resolveAppResourceText($r('app.string.download_selection_empty'));
}

export function buildDownloadSelectionTitle(selectedCount: number): string {
  return resolveAppResourceText($r('app.string.download_selection_title', selectedCount));
}

export function canSelectDownloadTask(status: DownloadV2Status): boolean {
  return status !== 'canceled' && status !== 'removed';
}

export type DownloadBatchAction = 'pause' | 'resume' | 'cancel';

/** Resolve each command against current capabilities, including retry-only downloads. */
export function resolveDownloadBatchTaskAction(
  action: DownloadBatchAction,
  status: DownloadV2Status,
  allowedActions: DownloadV2ManagementAction[]
): DownloadV2ManagementAction | undefined {
  if (!canSelectDownloadTask(status) || status === 'completed') {
    return undefined;
  }
  if (allowedActions.indexOf(action) >= 0) {
    return action;
  }
  if (action === 'resume' && allowedActions.indexOf('retry') >= 0) {
    return 'retry';
  }
  return undefined;
}

export function collectSelectableDownloadGuids(candidates: DownloadSelectionCandidate[]): string[] {
  const guids: string[] = [];
  candidates.forEach((candidate: DownloadSelectionCandidate) => {
    if (canSelectDownloadTask(candidate.status)) {
      guids.push(candidate.guid);
    }
  });
  return guids;
}

export function pruneDownloadSelection(selectedGuids: string[], selectableGuids: string[]): string[] {
  return selectedGuids.filter((guid: string) => selectableGuids.indexOf(guid) >= 0);
}
