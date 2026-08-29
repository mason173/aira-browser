import { AiraAccountBooleanPreferenceModule } from '@/features/desktop-connection/AiraAccountPreferenceModule';
import { readAiraDesktopConnectionSnapshot } from '@/features/desktop-connection/desktopConnectionRuntime';

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
  const snapshot = await readAiraDesktopConnectionSnapshot();
  return preference.readExtension(snapshot.account?.uid || '');
}

export function writeCrossDeviceTabsEnabled(uid: string, enabled: boolean): void {
  preference.write(uid, enabled);
}
