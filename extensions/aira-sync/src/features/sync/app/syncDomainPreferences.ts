import {
  readExtensionStorageRecord,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import {
  BOOKMARK_SYNC_DOMAIN_ENABLED_KEY,
  HISTORY_SYNC_DOMAIN_ENABLED_KEY,
} from './leafTabSyncStorageKeys';

// The domain switches pause remote sync on this device without deleting data.
// History still captures local visits/removals for the browser's history override;
// its existing outbox waits until sync is enabled again. An unset key means enabled.
const readDomainEnabled = async (storageKey: string): Promise<boolean> => {
  const record = await readExtensionStorageRecord([storageKey]);
  const value = record[storageKey];
  if (value === undefined || value === null) {
    return true;
  }
  return String(value) === 'true';
};

const writeDomainEnabled = async (storageKey: string, enabled: boolean): Promise<void> => {
  await writeExtensionStorageRecord({
    [storageKey]: String(enabled),
  });
};

export const readBookmarkSyncDomainEnabled = (): Promise<boolean> =>
  readDomainEnabled(BOOKMARK_SYNC_DOMAIN_ENABLED_KEY);

export const writeBookmarkSyncDomainEnabled = (enabled: boolean): Promise<void> =>
  writeDomainEnabled(BOOKMARK_SYNC_DOMAIN_ENABLED_KEY, enabled);

export const readHistorySyncDomainEnabled = (): Promise<boolean> =>
  readDomainEnabled(HISTORY_SYNC_DOMAIN_ENABLED_KEY);

export const writeHistorySyncDomainEnabled = (enabled: boolean): Promise<void> =>
  writeDomainEnabled(HISTORY_SYNC_DOMAIN_ENABLED_KEY, enabled);
