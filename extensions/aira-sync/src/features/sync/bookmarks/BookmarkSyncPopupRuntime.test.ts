import { afterEach, expect, test, vi } from 'vitest';
import { BookmarkSyncPopupRuntime } from './BookmarkSyncPopupRuntime';
import { BookmarkSyncModule } from './BookmarkSyncModule';
import { pauseAutoSyncDuringBookmarkOverwrite, readPausedBookmarkOverwrite } from './localApplyVerificationBreaker';
import { WEBDAV_STORAGE_KEYS } from '@/utils/webdavConfig';
import {
  LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';

vi.mock('@/features/desktop-connection/desktopConnectionProfile', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/features/desktop-connection/desktopConnectionProfile')>()),
  readAiraDesktopConnectionProfileWithinExecutionLock: async () => null,
}));

function setup() {
  const storage: Record<string, unknown> = {
    [WEBDAV_STORAGE_KEYS.url]: 'https://example.test/bookmarks',
    [WEBDAV_STORAGE_KEYS.username]: 'first',
  };
  vi.stubGlobal('chrome', { storage: { local: {
    get: async () => ({ ...storage }),
    set: async (values: Record<string, unknown>) => Object.assign(storage, values),
    remove: async (keys: string[]) => keys.forEach(key => delete storage[key]),
  } } });
  vi.stubGlobal('navigator', { locks: { request: (_key: string, _options: unknown, operation: () => unknown) => operation() } });
  vi.stubGlobal('window', new EventTarget());
  vi.stubGlobal('localStorage', { getItem: () => null, setItem: () => {}, removeItem: () => {} });
  return { storage, popup: new BookmarkSyncPopupRuntime({ deviceId: 'desktop', rootPath: 'sync' }) };
}

afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

test('a confirmation is invalid after the WebDAV account or selected provider changes', async () => {
  const { storage, popup } = setup();
  const target = await popup.prepareOverwrite('webdav');
  const sync = vi.spyOn(BookmarkSyncModule.prototype, 'sync');
  storage[WEBDAV_STORAGE_KEYS.username] = 'another';
  expect((await popup.overwrite(target, 'computer-to-remote', {})).type).toBe('blocked');
  storage[WEBDAV_STORAGE_KEYS.username] = 'first';
  storage[LEAFTAB_SELECTED_SYNC_SOURCE_KEY] = 'personal-server';
  expect((await popup.overwrite(target, 'remote-to-computer', {})).type).toBe('blocked');
  expect(sync).not.toHaveBeenCalled();
});

test('overwrite can finish a first selection with a pending conflict and clears it only on success', async () => {
  const { storage, popup } = setup();
  const target = await popup.prepareOverwrite('webdav');
  storage[LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY] = {
    provider: 'webdav', sourceIdentity: target.sourceIdentity, detectedAt: 'now', remoteCommitId: 'prior', summary: 'conflict',
  };
  const sync = vi.spyOn(BookmarkSyncModule.prototype, 'sync').mockRejectedValueOnce(new Error('offline'));
  expect((await popup.overwrite(target, 'remote-to-computer', {})).type).toBe('failed');
  expect(storage[LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY]).toBeDefined();
  expect(storage[LEAFTAB_SELECTED_SYNC_SOURCE_KEY]).toBeUndefined();
  sync.mockResolvedValueOnce({
    kind: 'pull', remoteCommitId: 'prior', snapshotSummary: { bookmarkItems: 0, bookmarkFolders: 0, tombstones: 0 },
    snapshot: { meta: { version: 2, deviceId: 'desktop', generatedAt: 'now' },
      bookmarkFolders: {}, bookmarkItems: {}, bookmarkOrders: {}, tombstones: {} },
  });
  expect((await popup.overwrite(target, 'remote-to-computer', {})).type).toBe('completed');
  expect(sync).toHaveBeenLastCalledWith(expect.objectContaining({ overwrite: 'remote-to-computer' }));
  expect(storage[LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY]).toBeUndefined();
  expect(storage[LEAFTAB_SELECTED_SYNC_SOURCE_KEY]).toBe('webdav');
});

test('manual sync after interruption retries the chosen direction only for its original account', async () => {
  const { storage, popup } = setup();
  storage[WEBDAV_STORAGE_KEYS.syncEnabled] = true;
  storage[LEAFTAB_SELECTED_SYNC_SOURCE_KEY] = 'webdav';
  const target = await popup.prepareOverwrite('webdav');
  await pauseAutoSyncDuringBookmarkOverwrite({ sourceIdentity: target.sourceIdentity, direction: 'remote-to-computer' });
  const sync = vi.spyOn(BookmarkSyncModule.prototype, 'sync');
  expect((await popup.selectSource('webdav')).type).toBe('blocked');
  storage[WEBDAV_STORAGE_KEYS.username] = 'second';
  expect((await popup.syncNow('webdav')).type).toBe('blocked');
  expect(sync).not.toHaveBeenCalled();
  storage[WEBDAV_STORAGE_KEYS.username] = 'first';
  sync.mockRejectedValueOnce(new Error('offline'));
  expect((await popup.syncNow('webdav')).type).toBe('failed');
  expect(sync).toHaveBeenLastCalledWith(expect.objectContaining({ overwrite: 'remote-to-computer' }));
  expect(await readPausedBookmarkOverwrite()).toEqual({ sourceIdentity: target.sourceIdentity, direction: 'remote-to-computer' });
});
