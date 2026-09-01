const BOOKMARK_SYNC_EXECUTION_LOCK_NAME = 'aira-g2-bookmark-sync';

export const withBookmarkSyncExecutionLock = async <T>(operation: () => Promise<T>): Promise<T> => {
  const locks = globalThis.navigator?.locks;
  if (!locks) {
    throw new Error('当前浏览器不支持安全的跨窗口书签同步互斥。');
  }
  return locks.request(BOOKMARK_SYNC_EXECUTION_LOCK_NAME, { mode: 'exclusive' }, operation);
};
