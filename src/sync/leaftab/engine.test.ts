import { describe, expect, it, vi } from 'vitest';
import type { LeafTabSyncBaselineStore } from './baseline';
import { LeafTabSyncEngine } from './engine';
import { LEAFTAB_SYNC_SCHEMA_VERSION, type LeafTabSyncBaseline } from './schema';
import type { LeafTabSyncRemoteState, LeafTabSyncRemoteStore } from './remoteStore';
import type { LeafTabSyncSnapshot } from './schema';

const snapshot = (id: string): LeafTabSyncSnapshot => ({
  meta: {
    version: LEAFTAB_SYNC_SCHEMA_VERSION,
    deviceId: id,
    generatedAt: `2026-06-05T00:00:00.000Z`,
  },
  bookmarkFolders: {
    browser_root_toolbar: {
      id: 'browser_root_toolbar',
      type: 'bookmark-folder',
      parentId: null,
      title: '书签栏',
      createdAt: '2026-06-05T00:00:00.000Z',
      updatedAt: '2026-06-05T00:00:00.000Z',
      updatedBy: id,
      revision: 1,
    },
  },
  bookmarkItems: {
    [`bkm_${id}`]: {
      id: `bkm_${id}`,
      type: 'bookmark-item',
      parentId: 'browser_root_toolbar',
      title: id,
      url: `https://${id}.example.com`,
      createdAt: '2026-06-05T00:00:00.000Z',
      updatedAt: '2026-06-05T00:00:00.000Z',
      updatedBy: id,
      revision: 1,
    },
  },
  bookmarkOrders: {
    __root__: {
      type: 'bookmark-order',
      parentId: null,
      ids: ['browser_root_toolbar'],
      updatedAt: '2026-06-05T00:00:00.000Z',
      updatedBy: id,
      revision: 1,
    },
    browser_root_toolbar: {
      type: 'bookmark-order',
      parentId: 'browser_root_toolbar',
      ids: [`bkm_${id}`],
      updatedAt: '2026-06-05T00:00:00.000Z',
      updatedBy: id,
      revision: 1,
    },
  },
  tombstones: {},
});

const createBaselineStore = (): LeafTabSyncBaselineStore => {
  let value: LeafTabSyncBaseline | null = null;
  return {
    load: vi.fn(async () => value),
    save: vi.fn(async (next: LeafTabSyncBaseline) => {
      value = next;
    }),
    clear: vi.fn(async () => {
      value = null;
    }),
  };
};

const createRemoteStore = (state: LeafTabSyncRemoteState): LeafTabSyncRemoteStore => ({
  acquireLock: vi.fn(async () => ({})),
  releaseLock: vi.fn(async () => {}),
  readState: vi.fn(async () => state),
  writeState: vi.fn(async ({ snapshot: nextSnapshot }) => ({
    head: {
      version: LEAFTAB_SYNC_SCHEMA_VERSION,
      commitId: 'commit-written',
      updatedAt: nextSnapshot.meta.generatedAt,
    },
    commit: {
      id: 'commit-written',
      version: LEAFTAB_SYNC_SCHEMA_VERSION,
      deviceId: nextSnapshot.meta.deviceId,
      createdAt: nextSnapshot.meta.generatedAt,
      parentCommitId: null,
      manifestPath: 'aira/v1/bookmarks/manifest.json',
      summary: {
        bookmarkFolders: Object.keys(nextSnapshot.bookmarkFolders).length,
        bookmarkItems: Object.keys(nextSnapshot.bookmarkItems).length,
        tombstones: Object.keys(nextSnapshot.tombstones).length,
      },
    },
  })),
});

describe('LeafTabSyncEngine first sync behavior', () => {
  it('prefers the remote snapshot when no baseline exists', async () => {
    const localSnapshot = snapshot('local');
    const remoteSnapshot = snapshot('remote');
    const baselineStore = createBaselineStore();
    const remoteStore = createRemoteStore({
      head: null,
      commit: {
        id: 'commit-remote',
        version: LEAFTAB_SYNC_SCHEMA_VERSION,
        deviceId: 'remote',
        createdAt: remoteSnapshot.meta.generatedAt,
        parentCommitId: null,
        manifestPath: 'aira/v1/bookmarks/manifest.json',
        summary: {
          bookmarkFolders: 1,
          bookmarkItems: 1,
          tombstones: 0,
        },
      },
      snapshot: remoteSnapshot,
    });
    const applyLocalSnapshot = vi.fn(async () => {});
    const engine = new LeafTabSyncEngine({
      deviceId: 'local',
      remoteStore,
      baselineStore,
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot,
      createEmptySnapshot: () => snapshot('empty'),
      rootPath: 'aira/v1/bookmarks',
    });

    const result = await engine.sync('auto');

    expect(result.kind).toBe('pull');
    expect(result.snapshot.bookmarkItems.bkm_remote).toBeDefined();
    expect(applyLocalSnapshot).toHaveBeenCalledWith(remoteSnapshot);
    expect(remoteStore.writeState).not.toHaveBeenCalled();
  });

  it('pushes local only when no baseline and remote is empty', async () => {
    const localSnapshot = snapshot('local');
    const baselineStore = createBaselineStore();
    const remoteStore = createRemoteStore({
      head: null,
      commit: null,
      snapshot: null,
    });
    const engine = new LeafTabSyncEngine({
      deviceId: 'local',
      remoteStore,
      baselineStore,
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: vi.fn(async () => {}),
      createEmptySnapshot: () => snapshot('empty'),
      rootPath: 'aira/v1/bookmarks',
    });

    const result = await engine.sync('auto');

    expect(result.kind).toBe('push');
    expect(remoteStore.writeState).toHaveBeenCalledWith(expect.objectContaining({
      snapshot: localSnapshot,
      parentCommitId: null,
    }));
  });
});
