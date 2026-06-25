import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';

const LOCAL_BOOKMARK_CHANGED_AT_KEY = 'leaftab_sync_v1_local_bookmark_changed_at';
const BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY = 'leaftab_sync_v1_apply_suppress_until';
const APPLY_EVENT_SUPPRESS_MS = 20_000;

const readNumber = (key: string) => {
  try {
    const value = Number(globalThis.localStorage?.getItem(key) || 0);
    return Number.isFinite(value) ? value : 0;
  } catch {
    return 0;
  }
};

export const isLeafTabBookmarkSyncApplyEventSuppressed = (nowMs = Date.now()) => {
  return readNumber(BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY) > nowMs;
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

export const markLeafTabLocalBookmarkChanged = (nowMs = Date.now()) => {
  if (isLeafTabBookmarkSyncApplyEventSuppressed(nowMs)) return false;
  try {
    globalThis.localStorage?.setItem(LOCAL_BOOKMARK_CHANGED_AT_KEY, String(nowMs));
  } catch {}
  void writeExtensionStorageRecord({
    [LOCAL_BOOKMARK_CHANGED_AT_KEY]: String(nowMs),
  });
  return true;
};

export const hasPendingLeafTabLocalBookmarkChanges = () => {
  return readNumber(LOCAL_BOOKMARK_CHANGED_AT_KEY) > 0;
};

export const clearPendingLeafTabLocalBookmarkChanges = () => {
  try {
    globalThis.localStorage?.removeItem(LOCAL_BOOKMARK_CHANGED_AT_KEY);
  } catch {}
  void removeExtensionStorageKeys([LOCAL_BOOKMARK_CHANGED_AT_KEY]);
};

export const readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage = async (): Promise<number> => {
  const result = await readExtensionStorageRecord([LOCAL_BOOKMARK_CHANGED_AT_KEY]);
  const value = Number(result[LOCAL_BOOKMARK_CHANGED_AT_KEY] || 0);
  return Number.isFinite(value) ? value : 0;
};

export const markLeafTabLocalBookmarkChangedInExtensionStorage = async (nowMs = Date.now()): Promise<void> => {
  const result = await readExtensionStorageRecord([BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY]);
  const suppressUntil = Number(result[BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY] || 0);
  if (Number.isFinite(suppressUntil) && suppressUntil > nowMs) {
    return;
  }
  await writeExtensionStorageRecord({
    [LOCAL_BOOKMARK_CHANGED_AT_KEY]: String(nowMs),
  });
};

export const clearPendingLeafTabLocalBookmarkChangesInExtensionStorage = async (): Promise<void> => {
  await removeExtensionStorageKeys([LOCAL_BOOKMARK_CHANGED_AT_KEY]);
};
