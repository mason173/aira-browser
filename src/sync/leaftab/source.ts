export type LeafTabSyncRemoteKind = 'aira-cloud' | 'webdav';

export const parseLeafTabSyncRemoteKind = (value: unknown): LeafTabSyncRemoteKind | null => {
  if (value === 'aira-cloud' || value === 'webdav') {
    return value;
  }
  return null;
};

const isEnabledStorageValue = (value: unknown) => value === true || String(value ?? 'false') === 'true';

export const resolveLeafTabSelectedSyncSource = (values: {
  selectedSource: unknown;
  airaCloudEnabled: unknown;
  webdavEnabled: unknown;
}): { source: LeafTabSyncRemoteKind | null; needsMigration: boolean } => {
  const selectedSource = parseLeafTabSyncRemoteKind(values.selectedSource);
  if (selectedSource) {
    return { source: selectedSource, needsMigration: false };
  }
  const legacySource = isEnabledStorageValue(values.airaCloudEnabled)
    ? 'aira-cloud'
    : (isEnabledStorageValue(values.webdavEnabled) ? 'webdav' : null);
  return {
    source: legacySource,
    needsMigration: Boolean(legacySource),
  };
};

export type LeafTabPendingBookmarkConflict = {
  provider: LeafTabSyncRemoteKind;
  detectedAt: string;
  remoteCommitId: string;
  summary: string;
};
