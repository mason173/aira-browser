import { AiraAccountBooleanPreferenceModule } from '@/features/desktop-connection/AiraAccountPreferenceModule';
import { readAiraDesktopConnectionSnapshot } from '@/features/desktop-connection/desktopConnectionRuntime';
import { readExtensionStorageRecord } from '@/platform/extensionStorage';
import {
  personalServerAccountScope,
  readPersonalServerConnection,
} from '@/features/personal-server/PersonalServerConnection';
import { LEAFTAB_SELECTED_SYNC_SOURCE_KEY } from '@/features/sync/app/leafTabSyncStorageKeys';

const CROSS_DEVICE_TABS_ENABLED_KEY = 'aira_cross_device_tabs_enabled_v1';
const CROSS_DEVICE_TABS_ACCOUNT_KEY_PREFIX = 'aira_cross_device_tabs_enabled_v2';
const CROSS_DEVICE_TABS_LEGACY_OWNER_KEY = 'aira_cross_device_tabs_legacy_owner_v1';

const preference = new AiraAccountBooleanPreferenceModule({
  legacyKey: CROSS_DEVICE_TABS_ENABLED_KEY,
  scopedKeyPrefix: CROSS_DEVICE_TABS_ACCOUNT_KEY_PREFIX,
  legacyOwnerKey: CROSS_DEVICE_TABS_LEGACY_OWNER_KEY,
  defaultValue: true,
});

export function isCrossDeviceTabsPreferenceStorageKey(key: string): boolean {
  return preference.isStorageKey(key);
}

export function readCrossDeviceTabsEnabledFromLocalStorage(uid: string): boolean {
  return preference.readLocal(uid);
}

export async function readCrossDeviceTabsEnabledFromExtensionStorage(): Promise<boolean> {
  const [sourceRecord, personalServer, snapshot] = await Promise.all([
    readExtensionStorageRecord([LEAFTAB_SELECTED_SYNC_SOURCE_KEY]),
    readPersonalServerConnection(),
    readAiraDesktopConnectionSnapshot(),
  ]);
  const source = String(sourceRecord[LEAFTAB_SELECTED_SYNC_SOURCE_KEY] || '');
  const scope = source === 'personal-server' && personalServer
    ? personalServerAccountScope(personalServer)
    : snapshot.account?.uid || '';
  return preference.readExtension(scope);
}

export function writeCrossDeviceTabsEnabled(uid: string, enabled: boolean): void {
  preference.write(uid, enabled);
}
