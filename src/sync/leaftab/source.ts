export type LeafTabSyncRemoteKind = 'aira-cloud' | 'webdav';

export const parseLeafTabSyncRemoteKind = (value: unknown): LeafTabSyncRemoteKind | null => {
  if (value === 'aira-cloud' || value === 'webdav') {
    return value;
  }
  return null;
};

export const resolveLeafTabSelectedSyncSource = (values: {
  selectedSource: unknown;
  legacySelectedSource?: unknown;
}): { source: LeafTabSyncRemoteKind | null; needsMigration: boolean } => {
  const selectedSource = parseLeafTabSyncRemoteKind(values.selectedSource);
  if (selectedSource) {
    return { source: selectedSource, needsMigration: false };
  }
  const legacySource = parseLeafTabSyncRemoteKind(values.legacySelectedSource);
  return {
    source: legacySource,
    needsMigration: Boolean(legacySource),
  };
};

export const canRunLeafTabSelectedAutoSync = (values: {
  selectedSource: unknown;
  cloudUid: unknown;
  cloudDeviceCredential: unknown;
  cloudEntitled?: unknown;
  webdavUrl: unknown;
  airaCloudEnabled?: unknown;
  webdavEnabled?: unknown;
}): boolean => {
  const selectedSource = parseLeafTabSyncRemoteKind(values.selectedSource);
  if (selectedSource === 'aira-cloud') {
    return values.airaCloudEnabled === true
      && String(values.cloudUid || '').trim().length > 0
      && String(values.cloudDeviceCredential || '').trim().length > 0;
  }
  if (selectedSource === 'webdav') {
    return values.webdavEnabled === true
      && String(values.webdavUrl || '').trim().length > 0;
  }
  return false;
};

export type LeafTabPendingBookmarkConflict = {
  provider: LeafTabSyncRemoteKind;
  detectedAt: string;
  remoteCommitId: string;
  summary: string;
};
