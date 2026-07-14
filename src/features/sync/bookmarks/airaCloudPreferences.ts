import { AiraAccountBooleanPreferenceModule } from '@/features/desktop-connection/AiraAccountPreferenceModule';
import { AIRA_CLOUD_SYNC_ENABLED_KEY } from '@/features/sync/app/leafTabSyncStorageKeys';
import type { LeafTabSyncRemoteKind } from '@/features/sync/app/LeafTabSyncContracts';
import { writeExtensionStorageRecord } from '@/platform/extensionStorage';
import { parseLeafTabSyncRemoteKind } from '@/sync/leaftab/source';

const AIRA_CLOUD_SYNC_ACCOUNT_KEY_PREFIX = 'aira_cloud_bookmark_sync_enabled_v2';
const AIRA_CLOUD_SYNC_LEGACY_OWNER_KEY = 'aira_cloud_bookmark_sync_legacy_owner_v1';
export const AIRA_CLOUD_SELECTED_ACCOUNT_KEY = 'aira_cloud_selected_account_uid_v1';
const AIRA_ACCOUNT_SELECTED_SYNC_SOURCE_KEY_PREFIX = 'leaftab_primary_sync_remote_kind_v2';

const preference = new AiraAccountBooleanPreferenceModule({
  legacyKey: AIRA_CLOUD_SYNC_ENABLED_KEY,
  scopedKeyPrefix: AIRA_CLOUD_SYNC_ACCOUNT_KEY_PREFIX,
  legacyOwnerKey: AIRA_CLOUD_SYNC_LEGACY_OWNER_KEY,
  defaultValue: false,
});

export const createAiraAccountSelectedSyncSourceKey = (uid: string): string => (
  `${AIRA_ACCOUNT_SELECTED_SYNC_SOURCE_KEY_PREFIX}:${encodeURIComponent(uid.trim())}`
);

export const isAiraCloudSyncPreferenceStorageKey = (key: string): boolean => (
  key === AIRA_CLOUD_SELECTED_ACCOUNT_KEY
  || key.startsWith(`${AIRA_ACCOUNT_SELECTED_SYNC_SOURCE_KEY_PREFIX}:`)
  || preference.isStorageKey(key)
);

export const readAiraCloudSyncEnabledFromLocalStorage = (uid: string): boolean => preference.readLocal(uid);

export const readAiraCloudSyncEnabledFromExtensionStorage = (uid: string): Promise<boolean> => (
  preference.readExtension(uid)
);

export const writeAiraCloudSyncEnabled = (uid: string, enabled: boolean): void => {
  preference.write(uid, enabled);
};

export const resolveAiraCloudSelectedSourceForAccount = (params: {
  selectedSource: LeafTabSyncRemoteKind | null;
  uid: string;
  selectedAccountUid: unknown;
  enabledForAccount: boolean;
}): LeafTabSyncRemoteKind | null => {
  if (params.selectedSource !== 'aira-cloud') {
    return params.selectedSource;
  }
  const uid = params.uid.trim();
  const selectedAccountUid = String(params.selectedAccountUid || '').trim();
  if (!uid) {
    return null;
  }
  if (params.enabledForAccount || !selectedAccountUid || selectedAccountUid === uid) {
    return 'aira-cloud';
  }
  return null;
};

export const readAiraCloudSelectedSourceFromLocalStorage = (
  selectedSource: LeafTabSyncRemoteKind | null,
  uid: string,
  enabledForAccount: boolean,
): LeafTabSyncRemoteKind | null => {
  let selectedAccountUid = '';
  try {
    const scopedSource = uid
      ? parseLeafTabSyncRemoteKind(localStorage.getItem(createAiraAccountSelectedSyncSourceKey(uid)))
      : null;
    if (scopedSource) {
      return scopedSource;
    }
    selectedAccountUid = String(localStorage.getItem(AIRA_CLOUD_SELECTED_ACCOUNT_KEY) || '').trim();
  } catch {
    // Extension service workers do not expose localStorage.
  }
  const resolvedSource = resolveAiraCloudSelectedSourceForAccount({
    selectedSource,
    uid,
    selectedAccountUid,
    enabledForAccount,
  });
  if (resolvedSource && uid) {
    const normalizedUid = uid.trim();
    try {
      localStorage.setItem(createAiraAccountSelectedSyncSourceKey(normalizedUid), resolvedSource);
      if (resolvedSource === 'aira-cloud' && !selectedAccountUid) {
        localStorage.setItem(AIRA_CLOUD_SELECTED_ACCOUNT_KEY, normalizedUid);
      }
    } catch {
      // Extension service workers do not expose localStorage.
    }
    const migration: Record<string, unknown> = {
      [createAiraAccountSelectedSyncSourceKey(normalizedUid)]: resolvedSource,
    };
    if (resolvedSource === 'aira-cloud' && !selectedAccountUid) {
      migration[AIRA_CLOUD_SELECTED_ACCOUNT_KEY] = normalizedUid;
    }
    void writeExtensionStorageRecord(migration).catch(() => undefined);
  }
  return resolvedSource;
};

export const persistAiraAccountSelectedSyncSource = async (
  source: LeafTabSyncRemoteKind,
  uid: string,
): Promise<void> => {
  const normalizedUid = uid.trim();
  if (!normalizedUid) return;
  const values: Record<string, unknown> = {
    [createAiraAccountSelectedSyncSourceKey(normalizedUid)]: source,
  };
  try {
    localStorage.setItem(createAiraAccountSelectedSyncSourceKey(normalizedUid), source);
    if (source === 'aira-cloud') {
      localStorage.setItem(AIRA_CLOUD_SELECTED_ACCOUNT_KEY, normalizedUid);
    }
  } catch {
    // Extension service workers do not expose localStorage.
  }
  if (source === 'aira-cloud') {
    values[AIRA_CLOUD_SELECTED_ACCOUNT_KEY] = normalizedUid;
  }
  await writeExtensionStorageRecord(values);
};
