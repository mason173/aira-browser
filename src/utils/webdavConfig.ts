import type { WebdavConfig } from "@/types/webdav";
import {
  readExtensionStorageRecord,
  writeExtensionStorageRecord,
} from "@/platform/extensionStorage";

export const WEBDAV_STORAGE_KEYS = {
  profileName: "webdav_profile_name",
  url: "webdav_url",
  username: "webdav_username",
  password: "webdav_password",
  syncEnabled: "webdav_bookmark_sync_g2_enabled",
} as const;

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
  await writeExtensionStorageRecord({
    [WEBDAV_STORAGE_KEYS.profileName]: profileName,
    [WEBDAV_STORAGE_KEYS.url]: state.url.trim(),
    [WEBDAV_STORAGE_KEYS.username]: state.username.trim(),
    [WEBDAV_STORAGE_KEYS.password]: state.password || "",
    [WEBDAV_STORAGE_KEYS.syncEnabled]: String(state.syncEnabled),
  });
  localStorage.setItem(WEBDAV_STORAGE_KEYS.profileName, profileName);
  localStorage.setItem(WEBDAV_STORAGE_KEYS.url, state.url.trim());
  localStorage.setItem(WEBDAV_STORAGE_KEYS.username, state.username.trim());
  localStorage.setItem(WEBDAV_STORAGE_KEYS.password, state.password || "");
  localStorage.setItem(WEBDAV_STORAGE_KEYS.syncEnabled, String(state.syncEnabled));
};

export const seedWebdavCredentialsToExtensionStorage = async (
  defaultProfileName = "",
): Promise<void> => {
  const credentialKeys = [
    WEBDAV_STORAGE_KEYS.profileName,
    WEBDAV_STORAGE_KEYS.url,
    WEBDAV_STORAGE_KEYS.username,
    WEBDAV_STORAGE_KEYS.password,
  ];
  const existing = await readExtensionStorageRecord(credentialKeys);
  if (String(existing[WEBDAV_STORAGE_KEYS.url] || "").trim()) {
    return;
  }
  const state = readWebdavStorageStateFromStorage(defaultProfileName);
  if (!state.url.trim()) {
    return;
  }
  await writeExtensionStorageRecord({
    [WEBDAV_STORAGE_KEYS.profileName]: state.profileName.trim() || defaultProfileName,
    [WEBDAV_STORAGE_KEYS.url]: state.url.trim(),
    [WEBDAV_STORAGE_KEYS.username]: state.username.trim(),
    [WEBDAV_STORAGE_KEYS.password]: state.password || "",
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
