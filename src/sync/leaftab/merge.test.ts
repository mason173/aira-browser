import { describe, expect, it } from 'vitest';
import { mergeLeafTabSyncSnapshot } from './merge';
import type { LeafTabSyncSnapshot } from './schema';

const baseSnapshot = (): LeafTabSyncSnapshot => ({
  meta: {
    version: 2,
    deviceId: 'base-device',
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
      updatedBy: 'base-device',
      revision: 1,
    },
  },
  bookmarkItems: {
    bkm_shared_1: {
      id: 'bkm_shared_1',
      type: 'bookmark-item',
      parentId: 'browser_root_toolbar',
      title: 'Shared',
      url: 'https://shared.example.com',
      createdAt: '2026-05-24T00:00:00.000Z',
      updatedAt: '2026-05-24T00:00:00.000Z',
      updatedBy: 'base-device',
      revision: 1,
    },
  },
  bookmarkOrders: {
    browser_root_toolbar: {
      type: 'bookmark-order',
      parentId: 'browser_root_toolbar',
      ids: ['bkm_shared_1'],
      updatedAt: '2026-05-24T00:00:00.000Z',
      updatedBy: 'base-device',
      revision: 1,
    },
  },
  tombstones: {},
});

describe('mergeLeafTabSyncSnapshot', () => {
  it('keeps a deleted bookmark deleted when the other side still has the old entity', () => {
    const base = baseSnapshot();
    const local = baseSnapshot();
    const remote = baseSnapshot();
    delete remote.bookmarkItems.bkm_shared_1;
    remote.bookmarkOrders.browser_root_toolbar.ids = [];
    remote.tombstones.bkm_shared_1 = {
      id: 'bkm_shared_1',
      type: 'bookmark-item',
      deletedAt: '2026-05-24T01:00:00.000Z',
      deletedBy: 'remote-device',
      lastKnownRevision: 1,
    };

    const result = mergeLeafTabSyncSnapshot(base, local, remote, {
      deviceId: 'local-device',
      generatedAt: '2026-05-24T02:00:00.000Z',
    });

    expect(result.snapshot.bookmarkItems.bkm_shared_1).toBeUndefined();
    expect(result.snapshot.tombstones.bkm_shared_1?.type).toBe('bookmark-item');
    expect(result.snapshot.bookmarkOrders.browser_root_toolbar.ids).toEqual([]);
  });
});
