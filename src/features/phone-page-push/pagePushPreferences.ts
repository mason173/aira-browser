import { readAiraDesktopConnectionSnapshot } from '@/features/desktop-connection/desktopConnectionRuntime';
import { AiraAccountBooleanPreferenceModule } from '@/features/desktop-connection/AiraAccountPreferenceModule';

export const PHONE_PAGE_PUSH_ENABLED_KEY = 'aira_phone_page_push_enabled_v1';
const PHONE_PAGE_PUSH_ACCOUNT_KEY_PREFIX = 'aira_phone_page_push_enabled_v2';
const PHONE_PAGE_PUSH_LEGACY_OWNER_KEY = 'aira_phone_page_push_legacy_owner_v1';
const LEGACY_DESKTOP_LOGIN_PROFILE_KEY = 'aira_desktop_login_profile_v1';

const preference = new AiraAccountBooleanPreferenceModule({
  legacyKey: PHONE_PAGE_PUSH_ENABLED_KEY,
  scopedKeyPrefix: PHONE_PAGE_PUSH_ACCOUNT_KEY_PREFIX,
  legacyOwnerKey: PHONE_PAGE_PUSH_LEGACY_OWNER_KEY,
  defaultValue: true,
});

export const createPhonePagePushPreferenceKey = (uid: string): string => (
  preference.createKey(uid)
);

export const isPhonePagePushPreferenceStorageKey = (key: string): boolean => preference.isStorageKey(key);

export const readPhonePagePushEnabledFromLocalStorage = (): boolean => {
  return preference.readLocal(readCurrentPopupUid());
};

export const writePhonePagePushEnabled = (enabled: boolean): void => {
  preference.write(readCurrentPopupUid(), enabled);
};

export const readPhonePagePushEnabledFromExtensionStorage = async (): Promise<boolean> => {
  try {
    const snapshot = await readAiraDesktopConnectionSnapshot();
    return preference.readExtension(snapshot.account?.uid || '');
  } catch {
    return true;
  }
};

const readCurrentPopupUid = (): string => {
  try {
    const raw = localStorage.getItem(LEGACY_DESKTOP_LOGIN_PROFILE_KEY);
    if (!raw) return '';
    const profile = JSON.parse(raw) as { uid?: string };
    return String(profile.uid || '').trim();
  } catch {
    return '';
  }
};
