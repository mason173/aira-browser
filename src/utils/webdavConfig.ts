import type { WebdavConfig } from "@/types/webdav";
import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from "@/platform/extensionStorage";

export const WEBDAV_STORAGE_KEYS = {
  profileName: "webdav_profile_name",
  url: "webdav_url",
  username: "webdav_username",
  password: "webdav_password",
  syncEnabled: "webdav_sync_enabled",
  nextSyncAt: "webdav_next_sync_at",
} as const;

export const WEBDAV_BOOKMARK_SYNC_ROOT_SUFFIX = "aira/v1/bookmarks";

export const isWebdavSyncEnabledFromStorage = () => {
  return (localStorage.getItem(WEBDAV_STORAGE_KEYS.syncEnabled) ?? "false") === "true";
};

export const hasWebdavUrlConfiguredFromStorage = () => {
  return Boolean((localStorage.getItem(WEBDAV_STORAGE_KEYS.url) || "").trim());
};

export type WebdavStorageState = {
  profileName: string;
  url: string;
  username: string;
  password: string;
  syncEnabled: boolean;
};

export const readWebdavStorageStateFromStorage = (defaultProfileName = ""): WebdavStorageState => {
  const profileName = (localStorage.getItem(WEBDAV_STORAGE_KEYS.profileName) || defaultProfileName || "").trim();
  const url = (localStorage.getItem(WEBDAV_STORAGE_KEYS.url) || "").trim();
  const username = (localStorage.getItem(WEBDAV_STORAGE_KEYS.username) || "").trim();
  const password = localStorage.getItem(WEBDAV_STORAGE_KEYS.password) || "";
  const syncEnabled = isWebdavSyncEnabledFromStorage();

  return {
    profileName,
    url,
    username,
    password,
    syncEnabled,
  };
};

export const writeWebdavStorageStateToStorage = async (
  state: WebdavStorageState,
  defaultProfileName = "",
): Promise<void> => {
  const profileName = state.profileName.trim() || defaultProfileName;
  localStorage.setItem(WEBDAV_STORAGE_KEYS.profileName, profileName);
  localStorage.setItem(WEBDAV_STORAGE_KEYS.url, state.url.trim());
  localStorage.setItem(WEBDAV_STORAGE_KEYS.username, state.username.trim());
  localStorage.setItem(WEBDAV_STORAGE_KEYS.password, state.password || "");
  localStorage.setItem(WEBDAV_STORAGE_KEYS.syncEnabled, String(state.syncEnabled));
  await writeExtensionStorageRecord({
    [WEBDAV_STORAGE_KEYS.profileName]: profileName,
    [WEBDAV_STORAGE_KEYS.url]: state.url.trim(),
    [WEBDAV_STORAGE_KEYS.username]: state.username.trim(),
    [WEBDAV_STORAGE_KEYS.password]: state.password || "",
    [WEBDAV_STORAGE_KEYS.syncEnabled]: String(state.syncEnabled),
  });
};

export const syncWebdavStorageStateToExtensionStorage = async (
  defaultProfileName = "",
): Promise<void> => {
  const state = readWebdavStorageStateFromStorage(defaultProfileName);
  await writeExtensionStorageRecord({
    [WEBDAV_STORAGE_KEYS.profileName]: state.profileName.trim() || defaultProfileName,
    [WEBDAV_STORAGE_KEYS.url]: state.url.trim(),
    [WEBDAV_STORAGE_KEYS.username]: state.username.trim(),
    [WEBDAV_STORAGE_KEYS.password]: state.password || "",
    [WEBDAV_STORAGE_KEYS.syncEnabled]: String(state.syncEnabled),
    [WEBDAV_STORAGE_KEYS.nextSyncAt]: localStorage.getItem(WEBDAV_STORAGE_KEYS.nextSyncAt) || "",
  });
};

export const readWebdavStorageStateFromExtensionStorage = async (
  defaultProfileName = "",
): Promise<WebdavStorageState> => {
  const result = await readExtensionStorageRecord(Object.values(WEBDAV_STORAGE_KEYS));
  const profileName = String(result[WEBDAV_STORAGE_KEYS.profileName] || defaultProfileName || "").trim();
  const url = String(result[WEBDAV_STORAGE_KEYS.url] || "").trim();
  const username = String(result[WEBDAV_STORAGE_KEYS.username] || "").trim();
  const password = String(result[WEBDAV_STORAGE_KEYS.password] || "");
  const syncEnabled = String(result[WEBDAV_STORAGE_KEYS.syncEnabled] ?? "false") === "true";

  return {
    profileName,
    url,
    username,
    password,
    syncEnabled,
  };
};

export const readWebdavConfigFromExtensionStorage = async (
  options?: { allowDisabled?: boolean },
): Promise<WebdavConfig | null> => {
  const state = await readWebdavStorageStateFromExtensionStorage();
  const enabled = state.syncEnabled;
  if (!enabled && !options?.allowDisabled) return null;
  if (!state.url) return null;
  return {
    url: state.url,
    username: state.username,
    password: state.password,
  };
};

export const removeWebdavNextSyncAtFromExtensionStorage = async (): Promise<void> => {
  await removeExtensionStorageKeys([WEBDAV_STORAGE_KEYS.nextSyncAt]);
};

export const enableWebdavBookmarkSyncInStorage = async (defaultProfileName = ""): Promise<void> => {
  const current = readWebdavStorageStateFromStorage(defaultProfileName);
  await writeWebdavStorageStateToStorage({
    ...current,
    syncEnabled: true,
  }, defaultProfileName);
};

export const readWebdavConfigFromStorage = (options?: { allowDisabled?: boolean }): WebdavConfig | null => {
  const state = readWebdavStorageStateFromStorage();
  const enabled = state.syncEnabled;
  if (!enabled && !options?.allowDisabled) return null;

  const url = state.url;
  if (!url) return null;

  const username = state.username;
  const password = state.password;
  return {
    url,
    username,
    password,
  };
};
