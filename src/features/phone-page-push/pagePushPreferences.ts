import { readExtensionStorageRecord, removeExtensionStorageKeys, writeExtensionStorageRecord } from '@/platform/extensionStorage';

export const PHONE_PAGE_PUSH_ENABLED_KEY = 'aira_phone_page_push_enabled_v1';

export const readPhonePagePushEnabledFromLocalStorage = (): boolean => {
  try {
    const raw = localStorage.getItem(PHONE_PAGE_PUSH_ENABLED_KEY);
    if (raw === null) return true;
    return raw !== 'false';
  } catch {
    return true;
  }
};

export const writePhonePagePushEnabled = (enabled: boolean): void => {
  const value = String(enabled);
  try {
    localStorage.setItem(PHONE_PAGE_PUSH_ENABLED_KEY, value);
  } catch {
    // Ignore localStorage failures in extension contexts.
  }
  void writeExtensionStorageRecord({
    [PHONE_PAGE_PUSH_ENABLED_KEY]: value,
  });
};

export const readPhonePagePushEnabledFromExtensionStorage = async (): Promise<boolean> => {
  try {
    const result = await readExtensionStorageRecord([PHONE_PAGE_PUSH_ENABLED_KEY]);
    if (!Object.prototype.hasOwnProperty.call(result, PHONE_PAGE_PUSH_ENABLED_KEY)) {
      return true;
    }
    return String(result[PHONE_PAGE_PUSH_ENABLED_KEY]) !== 'false';
  } catch {
    return true;
  }
};

export const syncPhonePagePushEnabledToExtensionStorage = async (): Promise<void> => {
  const enabled = readPhonePagePushEnabledFromLocalStorage();
  if (enabled === true) {
    await writeExtensionStorageRecord({
      [PHONE_PAGE_PUSH_ENABLED_KEY]: 'true',
    });
    return;
  }
  await removeExtensionStorageKeys([PHONE_PAGE_PUSH_ENABLED_KEY]);
};
