import { describe, expect, test } from 'vitest';
import {
  LeafTabSyncTombstoneLifecycle,
  type LeafTabSyncHistoryStore,
} from './historyLifecycle';
import type { LeafTabSyncHistoryDescriptor, LeafTabSyncSnapshot } from './schema';

class MemoryHistoryStore implements LeafTabSyncHistoryStore {
  private value: LeafTabSyncHistoryDescriptor | null = null;

  async load(): Promise<LeafTabSyncHistoryDescriptor | null> {
    return this.value;
  }

  async save(history: LeafTabSyncHistoryDescriptor): Promise<void> {
    this.value = history;
  }
}

const createDeletionSnapshot = (): LeafTabSyncSnapshot => ({
  meta: {
    version: 2,
    deviceId: 'desktop-a',
    generatedAt: '2026-08-04T00:00:00.000Z',
  },
  bookmarkFolders: {},
  bookmarkItems: {},
  bookmarkOrders: {},
  tombstones: {
    'bookmark-item|old': {
      id: 'old',
      type: 'bookmark-item',
      deletedAt: '2026-05-05T23:59:59.999Z',
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    },
    'bookmark-item|recent': {
      id: 'recent',
      type: 'bookmark-item',
      deletedAt: '2026-05-06T00:00:00.000Z',
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    },
  },
});

describe('LeafTabSyncTombstoneLifecycle', () => {
  test('advances the 90-day frontier only to retire tombstones older than the cutoff', async () => {
    const lifecycle = new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore());
    const plan = await lifecycle.planMerge(
      null,
      createDeletionSnapshot(),
      { snapshot: null, commitId: null, history: null },
      'desktop-a',
      Date.parse('2026-08-04T00:00:00.000Z'),
    );

    expect({
      retainedFrom: plan.history.retainedFrom,
      retainedTombstoneIds: Object.values(plan.localSnapshot.tombstones).map((entry) => entry.id),
      requiresRemoteHistoryWrite: plan.requiresRemoteHistoryWrite,
    }).toEqual({
      retainedFrom: '2026-05-06T00:00:00.000Z',
      retainedTombstoneIds: ['recent'],
      requiresRemoteHistoryWrite: true,
    });
  });

  test('does not move the frontier when no tombstone needs retirement', async () => {
    const lifecycle = new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore());
    const plan = await lifecycle.planMerge(
      null,
      {
        ...createDeletionSnapshot(),
        tombstones: {},
      },
      { snapshot: null, commitId: null, history: null },
      'desktop-a',
      Date.parse('2030-01-01T00:00:00.000Z'),
    );

    expect(plan.history).toEqual({
      version: 1,
      epochId: 'bookmark-history-v1-origin',
      retainedFrom: '1970-01-01T00:00:00.000Z',
    });
  });

  test('refuses to confirm a frontier older than the locally confirmed history', async () => {
    const store = new MemoryHistoryStore();
    const lifecycle = new LeafTabSyncTombstoneLifecycle(store);
    await lifecycle.confirm({
      version: 1,
      epochId: 'bookmark-history-v1-newer',
      retainedFrom: '2026-05-01T00:00:00.000Z',
    });

    await expect(lifecycle.confirm({
      version: 1,
      epochId: 'bookmark-history-v1-origin',
      retainedFrom: '1970-01-01T00:00:00.000Z',
    })).rejects.toThrow('历史边界不能回退');
    await expect(lifecycle.readConfirmedHistory()).resolves.toEqual({
      version: 1,
      epochId: 'bookmark-history-v1-newer',
      retainedFrom: '2026-05-01T00:00:00.000Z',
    });
  });

  test('retires expired App-private tombstones without exposing private live entities to the shared set', async () => {
    const lifecycle = new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore());
    const snapshot = createDeletionSnapshot();
    snapshot.tombstones = {};
    snapshot.appPrivateBookmarks = {
      bookmarkFolders: {},
      bookmarkItems: {
        private_live: {
          id: 'private_live',
          type: 'bookmark-item',
          parentId: null,
          title: 'Private',
          url: 'https://private.example/',
          createdAt: '2026-08-01T00:00:00.000Z',
          updatedAt: '2026-08-01T00:00:00.000Z',
          updatedBy: 'phone-a',
          revision: 1,
        },
      },
      bookmarkOrders: {},
      tombstones: {
        'bookmark-item|private_old': {
          id: 'private_old',
          type: 'bookmark-item',
          deletedAt: '2026-05-05T23:59:59.999Z',
          deletedBy: 'phone-a',
          lastKnownRevision: 1,
        },
      },
    };
    const plan = await lifecycle.planMerge(
      null,
      snapshot,
      { snapshot: null, commitId: null, history: null },
      'desktop-a',
      Date.parse('2026-08-04T00:00:00.000Z'),
    );

    expect({
      sharedItems: Object.keys(plan.localSnapshot.bookmarkItems),
      privateItems: Object.keys(plan.localSnapshot.appPrivateBookmarks?.bookmarkItems || {}),
      privateTombstones: Object.keys(plan.localSnapshot.appPrivateBookmarks?.tombstones || {}),
    }).toEqual({
      sharedItems: [],
      privateItems: ['private_live'],
      privateTombstones: [],
    });
  });
});
