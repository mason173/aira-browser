import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';

export const LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY = 'leaftab_sync_g2_local_bookmark_changed_at';
const BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY = 'leaftab_sync_g2_apply_suppress_until';
const APPLY_EVENT_SUPPRESS_MS = 20_000;
let pendingLocalBookmarkChangeTail: Promise<void> = Promise.resolve();

const runPendingLocalBookmarkChangeOperation = <T>(operation: () => Promise<T>): Promise<T> => {
  const result = pendingLocalBookmarkChangeTail.then(operation);
  pendingLocalBookmarkChangeTail = result.then(
    () => undefined,
    () => undefined,
  );
  return result;
};

export const markLeafTabBookmarkSyncApplyStarted = async (nowMs = Date.now()): Promise<void> => {
  await writeExtensionStorageRecord({
    [BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY]: String(nowMs + APPLY_EVENT_SUPPRESS_MS),
  });
};

export const markLeafTabBookmarkSyncApplyFinished = async (nowMs = Date.now()): Promise<void> => {
  await writeExtensionStorageRecord({
    [BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY]: String(nowMs + APPLY_EVENT_SUPPRESS_MS),
  });
};

export const readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage = async (): Promise<number> => {
  return runPendingLocalBookmarkChangeOperation(async () => {
    const result = await readExtensionStorageRecord([LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY]);
    const value = Number(result[LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY] || 0);
    return Number.isFinite(value) ? value : 0;
  });
};

export const markLeafTabLocalBookmarkChangedInExtensionStorage = async (nowMs = Date.now()): Promise<boolean> => {
  return runPendingLocalBookmarkChangeOperation(async () => {
    const result = await readExtensionStorageRecord([
      BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY,
      LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY,
    ]);
    const suppressUntil = Number(result[BOOKMARK_SYNC_APPLY_SUPPRESS_UNTIL_KEY] || 0);
    if (Number.isFinite(suppressUntil) && suppressUntil > nowMs) {
      return false;
    }
    const currentChangedAt = Number(result[LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY] || 0);
    const normalizedCurrentChangedAt = Number.isFinite(currentChangedAt) ? currentChangedAt : 0;
    const nextChangedAt = nowMs > normalizedCurrentChangedAt
      ? nowMs
      : normalizedCurrentChangedAt + 1;
    await writeExtensionStorageRecord({
      [LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY]: String(nextChangedAt),
    });
    return true;
  });
};

export const clearPendingLeafTabLocalBookmarkChangesInExtensionStorage = async (
  expectedChangedAt: number,
): Promise<void> => {
  await runPendingLocalBookmarkChangeOperation(async () => {
    if (expectedChangedAt <= 0) {
      return;
    }
    const result = await readExtensionStorageRecord([LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY]);
    const currentChangedAt = Number(result[LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY] || 0);
    if (!Number.isFinite(currentChangedAt) || currentChangedAt !== expectedChangedAt) {
      return;
    }
    await removeExtensionStorageKeys([LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY]);
  });
};
