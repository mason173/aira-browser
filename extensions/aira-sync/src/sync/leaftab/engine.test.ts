import { describe, expect, test } from 'vitest';
import type { LeafTabSyncBaselineStore } from './baseline';
import { LeafTabSyncEngine } from './engine';
import {
  LeafTabSyncTombstoneLifecycle,
  type LeafTabSyncHistoryStore,
} from './historyLifecycle';
import type { LeafTabSyncRemoteStore, LeafTabSyncWriteStateParams } from './remoteStore';
import type {
  LeafTabSyncBaseline,
  LeafTabSyncHistoryDescriptor,
  LeafTabSyncSnapshot,
} from './schema';

const EMPTY_TIMESTAMP = '1970-01-01T00:00:00.000Z';
const ORIGIN_HISTORY: LeafTabSyncHistoryDescriptor = {
  version: 1,
  epochId: 'bookmark-history-v1-origin',
  retainedFrom: EMPTY_TIMESTAMP,
};

const createEmptySnapshot = (deviceId: string): LeafTabSyncSnapshot => ({
  meta: {
    version: 2,
    deviceId,
    generatedAt: EMPTY_TIMESTAMP,
  },
  bookmarkFolders: {},
  bookmarkItems: {},
  bookmarkOrders: {},
  tombstones: {},
});

class MemoryBaselineStore implements LeafTabSyncBaselineStore {
  private value: LeafTabSyncBaseline | null = null;

  async load(): Promise<LeafTabSyncBaseline | null> {
    return this.value;
  }

  async save(baseline: LeafTabSyncBaseline): Promise<void> {
    this.value = baseline;
  }
}

class MemoryHistoryStore implements LeafTabSyncHistoryStore {
  private value: LeafTabSyncHistoryDescriptor | null = null;

  async load(): Promise<LeafTabSyncHistoryDescriptor | null> {
    return this.value;
  }

  async save(history: LeafTabSyncHistoryDescriptor): Promise<void> {
    this.value = history;
  }
}

describe('LeafTabSyncEngine', () => {
  test('first upload stays uncommitted when the complete remote read-back is missing', async () => {
    const localSnapshot = createEmptySnapshot('desktop-a');
    const baselineStore = new MemoryBaselineStore();
    const historyStore = new MemoryHistoryStore();
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(historyStore);
    const remoteStore: LeafTabSyncRemoteStore = {
      async readState() {
        return { snapshot: null, commitId: null, history: null };
      },
      async writeState() {
        return {
          commitId: 'commit-first-upload',
          writtenAt: '2026-08-04T00:00:00.000Z',
        };
      },
    };
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore,
      baselineStore,
      historyLifecycle,
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: async () => undefined,
      verifyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => createEmptySnapshot('desktop-a'),
    });

    await expect(engine.sync()).rejects.toThrow('未能确认完整的书签提交');
    await expect(baselineStore.load()).resolves.toBeNull();
  });

  test('first sync commits the same origin history to remote, baseline, and local frontier', async () => {
    const localSnapshot = createEmptySnapshot('desktop-a');
    const baselineStore = new MemoryBaselineStore();
    const historyStore = new MemoryHistoryStore();
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(historyStore);
    let readCount = 0;
    let writtenHistory: LeafTabSyncHistoryDescriptor | undefined;
    const remoteStore: LeafTabSyncRemoteStore = {
      async readState() {
        readCount += 1;
        return readCount === 1
          ? { snapshot: null, commitId: null, history: null }
          : { snapshot: localSnapshot, commitId: 'commit-first-upload', history: ORIGIN_HISTORY };
      },
      async writeState(params: LeafTabSyncWriteStateParams) {
        writtenHistory = params.history;
        return {
          commitId: 'commit-first-upload',
          writtenAt: '2026-08-04T00:00:00.000Z',
        };
      },
    };
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore,
      baselineStore,
      historyLifecycle,
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: async () => undefined,
      verifyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => createEmptySnapshot('desktop-a'),
    });

    await engine.sync();
    const baseline = await baselineStore.load();

    expect({
      writtenHistory,
      baselineHistory: baseline?.history,
      confirmedHistory: await historyLifecycle.readConfirmedHistory(),
    }).toEqual({
      writtenHistory: ORIGIN_HISTORY,
      baselineHistory: ORIGIN_HISTORY,
      confirmedHistory: ORIGIN_HISTORY,
    });
  });

  test('confirms a remote write when the read-back keeps the same commit but drops extra entity fields', async () => {
    const localSnapshot = createEmptySnapshot('desktop-a');
    (localSnapshot.bookmarkFolders as Record<string, unknown>).folder = {
      id: 'folder',
      type: 'bookmark-folder',
      parentId: null,
      title: '书签栏',
      createdAt: EMPTY_TIMESTAMP,
      updatedAt: EMPTY_TIMESTAMP,
      updatedBy: 'desktop-a',
      revision: 1,
      extraField: 'chrome-only',
    };
    localSnapshot.bookmarkOrders = {
      __root__: {
        type: 'bookmark-order',
        parentId: null,
        ids: ['folder'],
        updatedAt: EMPTY_TIMESTAMP,
        updatedBy: 'desktop-a',
        revision: 1,
      },
    };
    const readBackSnapshot = createEmptySnapshot('desktop-a');
    readBackSnapshot.bookmarkFolders = {
      folder: {
        id: 'folder',
        type: 'bookmark-folder',
        parentId: null,
        title: '书签栏',
        createdAt: EMPTY_TIMESTAMP,
        updatedAt: EMPTY_TIMESTAMP,
        updatedBy: 'desktop-a',
        revision: 1,
      },
    };
    readBackSnapshot.bookmarkOrders = localSnapshot.bookmarkOrders;
    const baselineStore = new MemoryBaselineStore();
    const historyStore = new MemoryHistoryStore();
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(historyStore);
    let readCount = 0;
    const remoteStore: LeafTabSyncRemoteStore = {
      async readState() {
        readCount += 1;
        return readCount === 1
          ? { snapshot: null, commitId: null, history: null }
          : { snapshot: readBackSnapshot, commitId: 'commit-canonicalized', history: ORIGIN_HISTORY };
      },
      async writeState() {
        return {
          commitId: 'commit-canonicalized',
          writtenAt: '2026-09-07T08:00:00.000Z',
        };
      },
    };
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore,
      baselineStore,
      historyLifecycle,
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: async () => undefined,
      verifyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => createEmptySnapshot('desktop-a'),
    });

    const result = await engine.sync();
    const baseline = await baselineStore.load();

    expect({
      kind: result.kind,
      commitId: result.remoteCommitId,
      baselineCommitId: baseline?.commitId || null,
      baselineHasExtraField: Boolean(
        (baseline?.snapshot?.bookmarkFolders.folder as { extraField?: string } | undefined)?.extraField,
      ),
    }).toEqual({
      kind: 'push',
      commitId: 'commit-canonicalized',
      baselineCommitId: 'commit-canonicalized',
      baselineHasExtraField: false,
    });
  });

  test('rewrites Chrome-invalid bookmark urls into the committed snapshot instead of dropping them', async () => {
    const localSnapshot = createEmptySnapshot('desktop-a');
    localSnapshot.bookmarkFolders = {
      browser_root_toolbar: {
        id: 'browser_root_toolbar',
        type: 'bookmark-folder',
        parentId: null,
        title: '书签栏',
        createdAt: EMPTY_TIMESTAMP,
        updatedAt: EMPTY_TIMESTAMP,
        updatedBy: 'desktop-a',
        revision: 1,
      },
    };
    localSnapshot.bookmarkItems = {
      spaced: {
        id: 'spaced',
        type: 'bookmark-item',
        parentId: 'browser_root_toolbar',
        title: 'Spaced',
        url: 'https://example.com/foo bar',
        createdAt: EMPTY_TIMESTAMP,
        updatedAt: EMPTY_TIMESTAMP,
        updatedBy: 'desktop-a',
        revision: 1,
      },
      bookmarklet: {
        id: 'bookmarklet',
        type: 'bookmark-item',
        parentId: 'browser_root_toolbar',
        title: 'Bookmarklet',
        url: 'javascript:alert(1)',
        createdAt: EMPTY_TIMESTAMP,
        updatedAt: EMPTY_TIMESTAMP,
        updatedBy: 'desktop-a',
        revision: 1,
      },
    };
    localSnapshot.bookmarkOrders = {
      __root__: {
        type: 'bookmark-order',
        parentId: null,
        ids: ['browser_root_toolbar'],
        updatedAt: EMPTY_TIMESTAMP,
        updatedBy: 'desktop-a',
        revision: 1,
      },
      browser_root_toolbar: {
        type: 'bookmark-order',
        parentId: 'browser_root_toolbar',
        ids: ['spaced', 'bookmarklet'],
        updatedAt: EMPTY_TIMESTAMP,
        updatedBy: 'desktop-a',
        revision: 1,
      },
    };
    const baselineStore = new MemoryBaselineStore();
    const historyStore = new MemoryHistoryStore();
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(historyStore);
    let writtenSnapshot: LeafTabSyncSnapshot | undefined;
    let stored: { snapshot: LeafTabSyncSnapshot; commitId: string } | null = null;
    const remoteStore: LeafTabSyncRemoteStore = {
      async readState() {
        return stored
          ? { snapshot: stored.snapshot, commitId: stored.commitId, history: ORIGIN_HISTORY }
          : { snapshot: null, commitId: null, history: null };
      },
      async writeState(params) {
        writtenSnapshot = params.snapshot as LeafTabSyncSnapshot;
        stored = { snapshot: params.snapshot, commitId: 'commit-cleaned' };
        return { commitId: 'commit-cleaned', writtenAt: EMPTY_TIMESTAMP };
      },
    };
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore,
      baselineStore,
      historyLifecycle,
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: async () => undefined,
      verifyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => createEmptySnapshot('desktop-a'),
    });

    await engine.sync();
    expect({
      spaced: writtenSnapshot!.bookmarkItems.spaced.url,
      bookmarklet: writtenSnapshot!.bookmarkItems.bookmarklet.url,
    }).toEqual({
      spaced: 'https://example.com/foo%20bar',
      bookmarklet: 'javascript:alert(1)',
    });
  });

  test('does not apply App-private bookmarks to desktop when regular bookmark content already matches', async () => {
    const localSnapshot = createEmptySnapshot('desktop-a');
    const remoteSnapshot = createEmptySnapshot('phone-a');
    remoteSnapshot.appPrivateBookmarks = {
      bookmarkFolders: {
        aira_private_root_toolbar: {
          id: 'aira_private_root_toolbar',
          type: 'bookmark-folder',
          parentId: null,
          title: '私密书签栏',
          createdAt: EMPTY_TIMESTAMP,
          updatedAt: EMPTY_TIMESTAMP,
          updatedBy: 'phone-a',
          revision: 1,
        },
      },
      bookmarkItems: {},
      bookmarkOrders: {
        __root__: {
          type: 'bookmark-order',
          parentId: null,
          ids: ['aira_private_root_toolbar'],
          updatedAt: EMPTY_TIMESTAMP,
          updatedBy: 'phone-a',
          revision: 1,
        },
      },
      tombstones: {},
    };
    const baselineStore = new MemoryBaselineStore();
    const historyStore = new MemoryHistoryStore();
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(historyStore);
    let applied = 0;
    const remoteStore: LeafTabSyncRemoteStore = {
      async readState() {
        return { snapshot: remoteSnapshot, commitId: 'commit-cloud', history: ORIGIN_HISTORY };
      },
      async writeState() {
        throw new Error('matching regular bookmarks must not rewrite Aira cloud');
      },
    };
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore,
      baselineStore,
      historyLifecycle,
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: async () => { applied += 1; },
      verifyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => createEmptySnapshot('desktop-a'),
    });

    const result = await engine.sync();
    const baseline = await baselineStore.load();
    expect({
      kind: result.kind,
      applied,
      baselineCommitId: baseline?.commitId || null,
      keptPrivateFolders: Object.keys(baseline?.snapshot?.appPrivateBookmarks?.bookmarkFolders || {}),
    }).toEqual({
      kind: 'noop',
      applied: 0,
      baselineCommitId: 'commit-cloud',
      keptPrivateFolders: ['aira_private_root_toolbar'],
    });
  });

  test('confirms a remote write when the read-back only reorders equivalent bookmark collections', async () => {
    const folderRoot = {
      id: 'root',
      type: 'bookmark-folder' as const,
      parentId: null,
      title: 'Root',
      createdAt: '2026-09-07T08:00:00.000Z',
      updatedAt: '2026-09-07T08:00:00.000Z',
      updatedBy: 'desktop-a',
      revision: 1,
    };
    const folderA = {
      id: 'folder-a',
      type: 'bookmark-folder' as const,
      parentId: 'root',
      title: 'A',
      createdAt: '2026-09-07T08:00:00.000Z',
      updatedAt: '2026-09-07T08:00:00.000Z',
      updatedBy: 'desktop-a',
      revision: 1,
    };
    const itemA = {
      id: 'item-a',
      type: 'bookmark-item' as const,
      parentId: 'folder-a',
      title: 'Item',
      url: 'https://example.com/item',
      createdAt: '2026-09-07T08:00:00.000Z',
      updatedAt: '2026-09-07T08:00:00.000Z',
      updatedBy: 'desktop-a',
      revision: 1,
    };
    const writtenSnapshot: LeafTabSyncSnapshot = {
      meta: {
        version: 2,
        deviceId: 'desktop-a',
        generatedAt: '2026-09-07T08:00:00.000Z',
      },
      bookmarkFolders: {
        root: folderRoot,
        'folder-a': folderA,
      },
      bookmarkItems: {
        'item-a': itemA,
      },
      bookmarkOrders: {
        __root__: {
          type: 'bookmark-order',
          parentId: null,
          ids: ['root'],
          updatedAt: '2026-09-07T08:00:00.000Z',
          updatedBy: 'desktop-a',
          revision: 1,
        },
        root: {
          type: 'bookmark-order',
          parentId: 'root',
          ids: ['folder-a'],
          updatedAt: '2026-09-07T08:00:00.000Z',
          updatedBy: 'desktop-a',
          revision: 1,
        },
        'folder-a': {
          type: 'bookmark-order',
          parentId: 'folder-a',
          ids: ['item-a'],
          updatedAt: '2026-09-07T08:00:00.000Z',
          updatedBy: 'desktop-a',
          revision: 1,
        },
      },
      tombstones: {
        'bookmark-item|gone': {
          id: 'gone',
          type: 'bookmark-item',
          deletedAt: '2026-09-07T07:00:00.000Z',
          deletedBy: 'desktop-a',
          lastKnownRevision: 1,
        },
      },
    };
    const reorderedSnapshot: LeafTabSyncSnapshot = {
      ...writtenSnapshot,
      bookmarkFolders: {
        'folder-a': folderA,
        root: folderRoot,
      },
      bookmarkOrders: {
        'folder-a': writtenSnapshot.bookmarkOrders['folder-a'],
        root: writtenSnapshot.bookmarkOrders.root,
        __root__: writtenSnapshot.bookmarkOrders.__root__,
      },
    };
    const baselineStore = new MemoryBaselineStore();
    const historyStore = new MemoryHistoryStore();
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(historyStore);
    let readCount = 0;
    const remoteStore: LeafTabSyncRemoteStore = {
      async readState() {
        readCount += 1;
        return readCount === 1
          ? { snapshot: null, commitId: null, history: null }
          : { snapshot: reorderedSnapshot, commitId: 'commit-reordered', history: ORIGIN_HISTORY };
      },
      async writeState() {
        return {
          commitId: 'commit-reordered',
          writtenAt: '2026-09-07T08:00:00.000Z',
        };
      },
    };
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore,
      baselineStore,
      historyLifecycle,
      buildLocalSnapshot: async () => writtenSnapshot,
      applyLocalSnapshot: async () => undefined,
      verifyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => createEmptySnapshot('desktop-a'),
    });

    const result = await engine.sync();
    const baseline = await baselineStore.load();

    expect(result.kind).toBe('push');
    expect(baseline?.commitId).toBe('commit-reordered');
  });

  test('retries a transient remote read-back mismatch before failing confirmation', async () => {
    const localSnapshot = createEmptySnapshot('desktop-a');
    const baselineStore = new MemoryBaselineStore();
    const historyStore = new MemoryHistoryStore();
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(historyStore);
    let readCount = 0;
    let committed = false;
    const remoteStore: LeafTabSyncRemoteStore = {
      async readState() {
        readCount += 1;
        return readCount < 3 || !committed
          ? { snapshot: null, commitId: null, history: null }
          : { snapshot: localSnapshot, commitId: 'commit-first-upload', history: ORIGIN_HISTORY };
      },
      async writeState() {
        committed = true;
        return {
          commitId: 'commit-first-upload',
          writtenAt: '2026-08-04T00:00:00.000Z',
        };
      },
    };
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore,
      baselineStore,
      historyLifecycle,
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: async () => undefined,
      verifyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => createEmptySnapshot('desktop-a'),
    });

    await engine.sync();
    expect(readCount).toBe(3);
    await expect(baselineStore.load()).resolves.not.toBeNull();
  });

  test('treats equivalent snapshots with different object key order as the same commit', async () => {
    const localSnapshot = createEmptySnapshot('desktop-a');
    localSnapshot.bookmarkFolders = {
      folder: {
        id: 'folder',
        type: 'bookmark-folder',
        parentId: null,
        title: '书签栏',
        createdAt: EMPTY_TIMESTAMP,
        updatedAt: EMPTY_TIMESTAMP,
        updatedBy: 'desktop-a',
        revision: 1,
      },
    };
    const remoteSnapshot = {
      ...localSnapshot,
      bookmarkFolders: {
        folder: {
          revision: 1,
          updatedBy: 'desktop-a',
          updatedAt: EMPTY_TIMESTAMP,
          createdAt: EMPTY_TIMESTAMP,
          title: '书签栏',
          parentId: null,
          type: 'bookmark-folder' as const,
          id: 'folder',
        },
      },
    };
    const baselineStore = new MemoryBaselineStore();
    const historyStore = new MemoryHistoryStore();
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(historyStore);
    const remoteStore: LeafTabSyncRemoteStore = {
      async readState() {
        return { snapshot: remoteSnapshot, commitId: 'commit-equivalent', history: ORIGIN_HISTORY };
      },
      async writeState() {
        throw new Error('equivalent snapshots must not be rewritten');
      },
    };
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore,
      baselineStore,
      historyLifecycle,
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: async () => undefined,
      verifyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => createEmptySnapshot('desktop-a'),
    });

    await expect(engine.sync()).resolves.toMatchObject({ kind: 'noop' });
  });
});
