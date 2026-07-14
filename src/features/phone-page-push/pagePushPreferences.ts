import { readAiraDesktopConnectionSnapshot } from '@/features/desktop-connection/desktopConnectionRuntime';
import { AiraAccountBooleanPreferenceModule } from '@/features/desktop-connection/AiraAccountPreferenceModule';

export const PHONE_PAGE_PUSH_ENABLED_KEY = 'aira_phone_page_push_enabled_v1';
const PHONE_PAGE_PUSH_ACCOUNT_KEY_PREFIX = 'aira_phone_page_push_enabled_v2';
const PHONE_PAGE_PUSH_LEGACY_OWNER_KEY = 'aira_phone_page_push_legacy_owner_v1';

const preference = new AiraAccountBooleanPreferenceModule({
  legacyKey: PHONE_PAGE_PUSH_ENABLED_KEY,
  scopedKeyPrefix: PHONE_PAGE_PUSH_ACCOUNT_KEY_PREFIX,
  legacyOwnerKey: PHONE_PAGE_PUSH_LEGACY_OWNER_KEY,
  defaultValue: true,
});

export const isPhonePagePushPreferenceStorageKey = (key: string): boolean => preference.isStorageKey(key);

export const readPhonePagePushEnabledFromLocalStorage = (uid: string): boolean => {
  return preference.readLocal(uid);
};

export const writePhonePagePushEnabled = (uid: string, enabled: boolean): void => {
  preference.write(uid, enabled);
};

export const readPhonePagePushEnabledFromExtensionStorage = async (): Promise<boolean> => {
  try {
    const snapshot = await readAiraDesktopConnectionSnapshot();
    return preference.readExtension(snapshot.account?.uid || '');
  } catch {
    return true;
  }
};
