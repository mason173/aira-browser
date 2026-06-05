import { describe, expect, it } from 'vitest';
import {
  countLeafTabLiveBookmarkEntities,
  normalizeLeafTabLiveBookmarkSnapshot,
} from './snapshot';
import type { LeafTabSyncSnapshot } from './schema';

const buildSnapshot = (): LeafTabSyncSnapshot => ({
  meta: {
    version: 2,
    deviceId: 'device-a',
    generatedAt: '2026-05-24T00:00:00.000Z',
  },
  bookmarkFolders: {
    browser_root_toolbar: {
      id: 'browser_root_toolbar',
      type: 'bookmark-folder',
      parentId: null,
      title: '书签栏',
      createdAt: '2026-05-24T00:00:00.000Z',
      updatedAt: '2026-05-24T00:00:00.000Z',
      updatedBy: 'device-a',
      revision: 1,
    },
  },
  bookmarkItems: {
    bkm_alive_1: {
      id: 'bkm_alive_1',
      type: 'bookmark-item',
      parentId: 'browser_root_toolbar',
      title: 'Alive',
      url: 'https://alive.example.com',
      createdAt: '2026-05-24T00:00:00.000Z',
      updatedAt: '2026-05-24T00:00:00.000Z',
      updatedBy: 'device-a',
      revision: 1,
    },
    bkm_deleted_1: {
      id: 'bkm_deleted_1',
      type: 'bookmark-item',
      parentId: 'browser_root_toolbar',
      title: 'Deleted',
      url: 'https://deleted.example.com',
      createdAt: '2026-05-24T00:00:00.000Z',
      updatedAt: '2026-05-24T00:00:00.000Z',
      updatedBy: 'device-a',
      revision: 1,
    },
  },
  bookmarkOrders: {
    browser_root_toolbar: {
      type: 'bookmark-order',
      parentId: 'browser_root_toolbar',
      ids: ['bkm_alive_1', 'bkm_deleted_1'],
      updatedAt: '2026-05-24T00:00:00.000Z',
      updatedBy: 'device-a',
      revision: 1,
    },
  },
  tombstones: {
    bkm_deleted_1: {
      id: 'bkm_deleted_1',
      type: 'bookmark-item',
      deletedAt: '2026-05-24T01:00:00.000Z',
      deletedBy: 'device-b',
      lastKnownRevision: 1,
    },
  },
});

describe('LeafTab live bookmark snapshot projection', () => {
  it('does not count or apply tombstoned entities as live bookmarks', () => {
    const normalized = normalizeLeafTabLiveBookmarkSnapshot(buildSnapshot());

    expect(Object.keys(normalized.bookmarkItems)).toEqual(['bkm_alive_1']);
    expect(normalized.bookmarkOrders.browser_root_toolbar.ids).toEqual(['bkm_alive_1']);
    expect(countLeafTabLiveBookmarkEntities(buildSnapshot())).toEqual({
      bookmarkFolders: 1,
      bookmarkItems: 1,
      tombstones: 1,
    });
  });

  it('rebuilds browser root orders when remote root folders were tombstoned', () => {
    const snapshot = buildSnapshot();
    delete snapshot.bookmarkFolders.browser_root_toolbar;
    snapshot.bookmarkOrders = {
      __root__: {
        type: 'bookmark-order',
        parentId: null,
        ids: [],
        updatedAt: '2026-05-24T00:00:00.000Z',
        updatedBy: 'device-a',
        revision: 1,
      },
    };
    snapshot.tombstones.browser_root_toolbar = {
      id: 'browser_root_toolbar',
      type: 'bookmark-folder',
      deletedAt: '2026-05-24T01:00:00.000Z',
      deletedBy: 'device-b',
      lastKnownRevision: 1,
    };

    const normalized = normalizeLeafTabLiveBookmarkSnapshot(snapshot);

    expect(normalized.bookmarkOrders.browser_root_toolbar.ids).toEqual(['bkm_alive_1']);
    expect(normalized.bookmarkOrders.__root__.ids).toEqual(['browser_root_toolbar']);
  });
});
