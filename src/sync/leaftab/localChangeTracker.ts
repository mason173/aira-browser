import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';

export const LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY = 'leaftab_sync_g2_local_bookmark_changed_at';
const BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY = 'leaftab_sync_g2_apply_suppress_until';
const APPLY_EVENT_SUPPRESS_MS = 20_000;

const readNumber = (key: string) => {
  try {
    const value = Number(globalThis.localStorage?.getItem(key) || 0);
    return Number.isFinite(value) ? value : 0;
  } catch {
    return 0;
  }
};

export const markLeafTabBookmarkSyncApplyStarted = (nowMs = Date.now()) => {
  try {
    globalThis.localStorage?.setItem(
      BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY,
      String(nowMs + APPLY_EVENT_SUPPRESS_MS),
    );
  } catch {}
  void writeExtensionStorageRecord({
    [BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY]: String(nowMs + APPLY_EVENT_SUPPRESS_MS),
  });
};

export const markLeafTabBookmarkSyncApplyFinished = (nowMs = Date.now()) => {
  try {
    globalThis.localStorage?.setItem(
      BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY,
      String(nowMs + APPLY_EVENT_SUPPRESS_MS),
    );
  } catch {}
  void writeExtensionStorageRecord({
    [BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY]: String(nowMs + APPLY_EVENT_SUPPRESS_MS),
  });
};

export const hasPendingLeafTabLocalBookmarkChanges = () => {
  return readNumber(LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY) > 0;
};

export const clearPendingLeafTabLocalBookmarkChanges = () => {
  try {
    globalThis.localStorage?.removeItem(LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY);
  } catch {}
  void removeExtensionStorageKeys([LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY]);
};

export const readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage = async (): Promise<number> => {
  const result = await readExtensionStorageRecord([LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY]);
  const value = Number(result[LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY] || 0);
  return Number.isFinite(value) ? value : 0;
};

export const markLeafTabLocalBookmarkChangedInExtensionStorage = async (nowMs = Date.now()): Promise<void> => {
  const result = await readExtensionStorageRecord([BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY]);
  const suppressUntil = Number(result[BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY] || 0);
  if (Number.isFinite(suppressUntil) && suppressUntil > nowMs) {
    return;
  }
  await writeExtensionStorageRecord({
    [LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY]: String(nowMs),
  });
};

export const clearPendingLeafTabLocalBookmarkChangesInExtensionStorage = async (): Promise<void> => {
  await removeExtensionStorageKeys([LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY]);
};
