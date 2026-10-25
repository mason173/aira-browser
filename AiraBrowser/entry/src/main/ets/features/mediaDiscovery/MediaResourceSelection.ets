import { MediaResourceAction, MediaResourceListItem } from './MediaResourceProjectionModels';

export type MediaResourceSurfaceTab = 'video' | 'other';
export type MediaResourceBatchAction = 'download' | 'copy';

export function belongsToMediaResourceTab(candidate: MediaResourceListItem, tab: MediaResourceSurfaceTab): boolean {
  if (candidate.family === 'segment') {
    return false;
  }
  const videoFamily = candidate.family === 'video' ||
    (candidate.family === 'manifest' && candidate.acquisition?.primaryTrack.role !== 'audio');
  const actionableVideo = candidate.actions.indexOf('download') >= 0 ||
    candidate.actions.indexOf('parse_manifest') >= 0;
  const exceptionalVideo = candidate.status === 'protected' || candidate.status === 'expired' ||
    candidate.status === 'unsupported' || candidate.status === 'failed';
  return tab === 'video' ? videoFamily && (actionableVideo || exceptionalVideo) :
    !videoFamily || (!actionableVideo && !exceptionalVideo);
}

export function isSelectableMediaResource(candidate: MediaResourceListItem): boolean {
  return belongsToMediaResourceTab(candidate, 'other') &&
    (candidate.actions.indexOf('download') >= 0 || candidate.actions.indexOf('copy') >= 0);
}

export function reconcileMediaResourceSelection(ids: string[], candidates: MediaResourceListItem[]): string[] {
  return ids.filter((id: string, index: number) => ids.indexOf(id) === index &&
    candidates.some((candidate: MediaResourceListItem) => candidate.id === id && isSelectableMediaResource(candidate)));
}

export function selectedMediaResourcesForAction(
  ids: string[], candidates: MediaResourceListItem[], action: MediaResourceAction
): MediaResourceListItem[] {
  const selectedIds = reconcileMediaResourceSelection(ids, candidates);
  return candidates.filter((candidate: MediaResourceListItem) =>
    selectedIds.indexOf(candidate.id) >= 0 && candidate.actions.indexOf(action) >= 0);
}
