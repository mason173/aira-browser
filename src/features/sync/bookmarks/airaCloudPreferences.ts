import { AiraAccountBooleanPreferenceModule } from '@/features/desktop-connection/AiraAccountPreferenceModule';
import { AIRA_CLOUD_SYNC_ENABLED_KEY } from '@/features/sync/app/leafTabSyncStorageKeys';

const AIRA_CLOUD_SYNC_ACCOUNT_KEY_PREFIX = 'aira_cloud_bookmark_sync_enabled_v2';
const AIRA_CLOUD_SYNC_LEGACY_OWNER_KEY = 'aira_cloud_bookmark_sync_legacy_owner_v1';

const preference = new AiraAccountBooleanPreferenceModule({
  legacyKey: AIRA_CLOUD_SYNC_ENABLED_KEY,
  scopedKeyPrefix: AIRA_CLOUD_SYNC_ACCOUNT_KEY_PREFIX,
  legacyOwnerKey: AIRA_CLOUD_SYNC_LEGACY_OWNER_KEY,
  defaultValue: false,
});

export const isAiraCloudSyncPreferenceStorageKey = (key: string): boolean => (
  preference.isStorageKey(key)
);

export const readAiraCloudSyncEnabledFromLocalStorage = (uid: string): boolean => preference.readLocal(uid);

export const readAiraCloudSyncEnabledFromExtensionStorage = (uid: string): Promise<boolean> => (
  preference.readExtension(uid)
);

export const writeAiraCloudSyncEnabled = (uid: string, enabled: boolean): void => {
  preference.write(uid, enabled);
};
