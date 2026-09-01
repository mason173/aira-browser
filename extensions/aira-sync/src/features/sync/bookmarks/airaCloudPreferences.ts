import {
  readExtensionStorageRecord,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';

const AIRA_CLOUD_SYNC_ACCOUNT_KEY_PREFIX = 'aira_cloud_bookmark_sync_g2_enabled';

const createAiraCloudSyncPreferenceKey = (uid: string): string => (
  `${AIRA_CLOUD_SYNC_ACCOUNT_KEY_PREFIX}:${encodeURIComponent(uid.trim())}`
);

export const isAiraCloudSyncPreferenceStorageKey = (key: string): boolean => (
  key.startsWith(`${AIRA_CLOUD_SYNC_ACCOUNT_KEY_PREFIX}:`)
);

export const readAiraCloudSyncEnabledFromLocalStorage = (uid: string): boolean => {
  const normalizedUid = uid.trim();
  if (!normalizedUid) return false;
  try {
    return localStorage.getItem(createAiraCloudSyncPreferenceKey(normalizedUid)) === 'true';
  } catch {
    return false;
  }
};

export const readAiraCloudSyncEnabledFromExtensionStorage = async (uid: string): Promise<boolean> => {
  const normalizedUid = uid.trim();
  if (!normalizedUid) return false;
  const storageKey = createAiraCloudSyncPreferenceKey(normalizedUid);
  const record = await readExtensionStorageRecord([storageKey]);
  return String(record[storageKey] || '') === 'true';
};

export const writeAiraCloudSyncEnabled = async (uid: string, enabled: boolean): Promise<void> => {
  const normalizedUid = uid.trim();
  if (!normalizedUid) return;
  const storageKey = createAiraCloudSyncPreferenceKey(normalizedUid);
  await writeExtensionStorageRecord({
    [storageKey]: String(enabled),
  });
  try {
    localStorage.setItem(storageKey, String(enabled));
  } catch {
    // Popup localStorage is only a UI cache; extension storage is authoritative.
  }
};
