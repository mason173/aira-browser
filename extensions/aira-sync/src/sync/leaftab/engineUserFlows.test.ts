import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import {
  createLeafTabSyncBaseline,
  type LeafTabSyncBaselineStore,
} from './baseline';
import { LeafTabSyncEngine, type BookmarkOverwriteDirection } from './engine';
import { assertLeafTabBookmarkTreeMatchesSnapshot } from './snapshot';
import {
  LEAFTAB_SYNC_TOMBSTONE_RETENTION_MS,
  LeafTabSyncTombstoneLifecycle,
  type LeafTabSyncHistoryStore,
} from './historyLifecycle';
import type {
  LeafTabSyncRemoteState,
  LeafTabSyncRemoteStore,
  LeafTabSyncWriteStateParams,
} from './remoteStore';
import {
  parseCanonicalLeafTabSyncWireSnapshot,
  toLeafTabSyncWireSnapshot,
  LeafTabSyncBaseline,
  LeafTabSyncHistoryDescriptor,
  LeafTabSyncSnapshot,
  LeafTabSyncTombstone,
} from './schema';

const T0 = '2026-08-01T00:00:00.000Z';
const T1 = '2026-08-02T00:00:00.000Z';
const ORIGIN_HISTORY: LeafTabSyncHistoryDescriptor = {
  version: 1,
  epochId: 'bookmark-history-v1-origin',
  retainedFrom: '1970-01-01T00:00:00.000Z',
};

// The expiry fixtures derive from the shared retention window, so changing the retention
// cannot silently leave these tests asserting a frontier that no longer advances.
const EXPIRY_NOW = new Date('2026-08-04T00:00:00.000Z');
const EXPIRED_TOMBSTONE_DELETED_AT = new Date(
  EXPIRY_NOW.getTime() - 30 * 24 * 60 * 60 * 1000,
).toISOString();
const EXPIRY_ADVANCED_RETAINED_FROM = new Date(
  EXPIRY_NOW.getTime() - LEAFTAB_SYNC_TOMBSTONE_RETENTION_MS,
).toISOString();

// Ordinary flow fixtures carry tombstones dated T1 = 2026-08-02. The lifecycle clock must be
// pinned just after them: a real wall clock far in the future would make every fixture tombstone
// look "expired", advance the frontier, and retire the very deletions these flows assert.
const FLOW_CLOCK = '2026-08-02T00:00:01.000Z';

const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

const comparableSnapshot = (snapshot: LeafTabSyncSnapshot) => ({
  bookmarkFolders: snapshot.bookmarkFolders,
  bookmarkItems: snapshot.bookmarkItems,
  bookmarkOrders: snapshot.bookmarkOrders,
  tombstones: snapshot.tombstones,
  appPrivateBookmarks: snapshot.appPrivateBookmarks,
});

const createSnapshot = (
  deviceId: string,
  items: Array<{ id: string; title?: string; revision?: number; updatedAt?: string }> = [],
  tombstones: LeafTabSyncTombstone[] = [],
): LeafTabSyncSnapshot => ({
  meta: {
    version: 2,
    deviceId,
    generatedAt: T1,
  },
  bookmarkFolders: {
    browser_root_toolbar: {
      id: 'browser_root_toolbar',
      type: 'bookmark-folder',
      parentId: null,
      title: '书签栏',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: 'seed',
      revision: 1,
    },
  },
  bookmarkItems: Object.fromEntries(items.map((item) => [item.id, {
    id: item.id,
    type: 'bookmark-item' as const,
    parentId: 'browser_root_toolbar',
    title: item.title || item.id,
    url: `https://example.com/${item.id}`,
    createdAt: T0,
    updatedAt: item.updatedAt || T0,
    updatedBy: deviceId,
    revision: item.revision || 1,
  }])),
  bookmarkOrders: {
    __root__: {
      type: 'bookmark-order',
      parentId: null,
      ids: ['browser_root_toolbar'],
      updatedAt: T0,
      updatedBy: 'seed',
      revision: 1,
    },
    browser_root_toolbar: {
      type: 'bookmark-order',
      parentId: 'browser_root_toolbar',
      ids: items.map((item) => item.id),
      updatedAt: items.length > 0 ? T1 : T0,
      updatedBy: deviceId,
      revision: items.length > 0 ? 2 : 1,
    },
  },
  tombstones: Object.fromEntries(tombstones.map((entry) => [`${entry.type}|${entry.id}`, entry])),
});

const createFolderTreeSnapshot = (
  deviceId: string,
  folderTitle: string,
  childCount = 6,
): LeafTabSyncSnapshot => {
  const snapshot = createSnapshot(deviceId);
  const folderId = 'folder-shared';
  snapshot.bookmarkFolders[folderId] = {
    id: folderId,
    type: 'bookmark-folder',
    parentId: 'browser_root_toolbar',
    title: folderTitle,
    createdAt: T0,
    updatedAt: T0,
    updatedBy: deviceId,
    revision: 1,
  };
  const childIds = Array.from({ length: childCount }, (_, index) => `folder-child-${index}`);
  childIds.forEach((id) => {
    snapshot.bookmarkItems[id] = {
      id,
      type: 'bookmark-item',
      parentId: folderId,
      title: id,
      url: `https://example.com/${id}`,
      createdAt: T0,
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1,
    };
  });
  snapshot.bookmarkOrders.browser_root_toolbar.ids = [folderId];
  snapshot.bookmarkOrders[folderId] = {
    type: 'bookmark-order',
    parentId: folderId,
    ids: childIds,
    updatedAt: T0,
    updatedBy: deviceId,
    revision: 1,
  };
  return snapshot;
};

class MemoryBaselineStore implements LeafTabSyncBaselineStore {
  value: LeafTabSyncBaseline | null;
  saveCount = 0;

  constructor(value: LeafTabSyncBaseline | null = null) {
    this.value = value ? clone(value) : null;
  }

  async load(): Promise<LeafTabSyncBaseline | null> {
    return this.value ? clone(this.value) : null;
  }

  async save(baseline: LeafTabSyncBaseline): Promise<void> {
    this.saveCount += 1;
    this.value = clone(baseline);
  }
}

class MemoryHistoryStore implements LeafTabSyncHistoryStore {
  value: LeafTabSyncHistoryDescriptor | null = null;

  async load(): Promise<LeafTabSyncHistoryDescriptor | null> {
    return this.value ? clone(this.value) : null;
  }

  async save(history: LeafTabSyncHistoryDescriptor): Promise<void> {
    this.value = clone(history);
  }
}

class MemoryRemoteStore implements LeafTabSyncRemoteStore {
  state: LeafTabSyncRemoteState;
  writeCount = 0;

  constructor(state?: LeafTabSyncRemoteState) {
    this.state = state ? clone(state) : { snapshot: null, commitId: null, history: null };
  }

  async readState(): Promise<LeafTabSyncRemoteState> {
    return clone(this.state);
  }

  async writeState(params: LeafTabSyncWriteStateParams) {
    if ((params.parentCommitId || null) !== this.state.commitId) {
      throw new Error('remote compare-and-swap conflict');
    }
    this.writeCount += 1;
    const commitId = `commit-${this.writeCount}`;
    this.state = {
      snapshot: clone(params.snapshot),
      commitId,
      history: clone(params.history),
    };
    return {
      commitId,
      writtenAt: params.createdAt || params.snapshot.meta.generatedAt,
    };
  }
}

class StaleReadBackRemoteStore extends MemoryRemoteStore {
  private staleState: LeafTabSyncRemoteState | null = null;

  override async writeState(params: LeafTabSyncWriteStateParams) {
    this.staleState = clone(this.state);
    return super.writeState(params);
  }

  override async readState(): Promise<LeafTabSyncRemoteState> {
    if (this.writeCount > 0 && this.staleState) {
      return clone(this.staleState);
    }
    return super.readState();
  }
}

class TransientReadFailureRemoteStore extends MemoryRemoteStore {
  readAttempts = 0;

  override async readState(): Promise<LeafTabSyncRemoteState> {
    this.readAttempts += 1;
    if (this.readAttempts === 1) {
      throw new Error('network unavailable');
    }
    return super.readState();
  }
}

class RacingRemoteStore extends MemoryRemoteStore {
  private readonly racedState: LeafTabSyncRemoteState;
  private hasRaced = false;

  constructor(initialState: LeafTabSyncRemoteState, racedState: LeafTabSyncRemoteState) {
    super(initialState);
    this.racedState = clone(racedState);
  }

  override async writeState(params: LeafTabSyncWriteStateParams) {
    if (!this.hasRaced) {
      this.hasRaced = true;
      this.state = clone(this.racedState);
    }
    return super.writeState(params);
  }
}

const createBaseline = (snapshot: LeafTabSyncSnapshot, commitId: string) => (
  createLeafTabSyncBaseline({ snapshot, commitId, history: ORIGIN_HISTORY })
);

const runSync = async (params: {
  local: LeafTabSyncSnapshot;
  remote: MemoryRemoteStore;
  baseline?: LeafTabSyncBaseline | null;
  conflictResolution?: 'prefer-local' | 'prefer-remote';
  overwrite?: BookmarkOverwriteDirection;
  beforeOverwrite?: (direction: BookmarkOverwriteDirection) => Promise<void>;
  applyFailure?: Error;
  verifyFailure?: Error;
}) => {
  let local = clone(params.local);
  const baselineStore = new MemoryBaselineStore(params.baseline || null);
  const historyLifecycle = new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore());
  const engine = new LeafTabSyncEngine({
    deviceId: params.local.meta.deviceId,
    remoteStore: params.remote,
    baselineStore,
    historyLifecycle,
    buildLocalSnapshot: async () => clone(local),
    applyLocalSnapshot: async (snapshot) => {
      if (params.applyFailure) throw params.applyFailure;
      local = clone(snapshot);
    },
    verifyLocalSnapshot: async (snapshot) => {
      if (params.verifyFailure) throw params.verifyFailure;
      expect(comparableSnapshot(local)).toEqual(comparableSnapshot(snapshot));
    },
    createEmptySnapshot: () => createSnapshot(params.local.meta.deviceId),
  });
  const result = await engine.sync({ conflictResolution: params.conflictResolution, overwrite: params.overwrite, beforeOverwrite: params.beforeOverwrite });
  return {
    result,
    local,
    baselineStore,
    historyLifecycle,
  };
};

const remoteWith = (
  snapshot: LeafTabSyncSnapshot,
  commitId = 'commit-seed',
) => new MemoryRemoteStore({ snapshot, commitId, history: ORIGIN_HISTORY });

const expectLiveItemIds = (snapshot: LeafTabSyncSnapshot) => {
  return Object.keys(snapshot.bookmarkItems).sort();
};

beforeEach(() => {
  vi.spyOn(Date, 'now').mockReturnValue(Date.parse(FLOW_CLOCK));
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
});

describe('Airatab realistic bookmark sync flows', () => {
  test('a remote IDN bookmark survives browser serialization, commits its baseline, and converges on retry', async () => {
    const remoteSnapshot = createSnapshot('phone-a', [{ id: 'international' }]);
    remoteSnapshot.bookmarkItems.international.url = 'https://例子.测试';
    const remote = remoteWith(remoteSnapshot);
    let local = createSnapshot('desktop-a');
    const baselineStore = new MemoryBaselineStore();
    let verified = 0;
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore: remote,
      baselineStore,
      historyLifecycle: new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore()),
      buildLocalSnapshot: async () => clone(local),
      applyLocalSnapshot: async (snapshot) => {
        local = clone(snapshot);
        Object.values(local.bookmarkItems).forEach((item) => {
          // Simulate the browser's serialized read-back, independently of the sync normalizer.
          item.url = new URL(item.url).href;
        });
      },
      verifyLocalSnapshot: async (snapshot) => {
        assertLeafTabBookmarkTreeMatchesSnapshot({
          folders: Object.values(local.bookmarkFolders).map((folder) => ({
            entityId: folder.id, localNodeId: folder.id, parentId: folder.parentId, title: folder.title,
          })),
          items: Object.values(local.bookmarkItems).map((item) => ({
            entityId: item.id, localNodeId: item.id, parentId: item.parentId, title: item.title, url: item.url,
          })),
          orderIdsByParent: Object.fromEntries(
            Object.entries(local.bookmarkOrders).map(([key, order]) => [key, order.ids]),
          ),
          nodeIdToEntityId: {},
        }, snapshot);
        verified += 1;
      },
      createEmptySnapshot: () => createSnapshot('desktop-a'),
    });

    await engine.sync();
    expect(verified).toBe(1);
    expect(Object.keys(local.bookmarkItems)).toEqual(['international']);
    expect(local.bookmarkItems.international.url).toBe('https://xn--fsqu00a.xn--0zwm56d/');
    expect(baselineStore.value?.snapshot?.bookmarkItems.international.url)
      .toBe('https://xn--fsqu00a.xn--0zwm56d/');
    expect(baselineStore.value?.commitId).toBe(remote.state.commitId);
    const writeCount = remote.writeCount;
    const baselineSaveCount = baselineStore.saveCount;

    const second = await engine.sync();
    expect(second.kind).toBe('noop');
    expect(remote.writeCount).toBe(writeCount);
    expect(baselineStore.saveCount).toBe(baselineSaveCount);
  });

  test.each(['computer-to-remote', 'remote-to-computer'] as const)(
    'explicit %s replaces the tree despite conflicts, including order and intentional duplicates', async (overwrite) => {
      const base = createSnapshot('base', [{ id: 'shared' }]);
      const desktop = createSnapshot('desktop', [{ id: 'mine' }, { id: 'copy' }, { id: 'shared', title: 'Desktop edit' }]);
      desktop.bookmarkItems.copy = { ...desktop.bookmarkItems.mine, id: 'copy' };
      const cloud = createSnapshot('cloud', [{ id: 'shared', title: 'Cloud edit', revision: 9 }, { id: 'theirs' }]);
      cloud.appPrivateBookmarks = { bookmarkFolders: {}, bookmarkItems: {}, bookmarkOrders: {}, tombstones: {} };
      const remote = remoteWith(cloud);
      const push = overwrite === 'computer-to-remote';
      const winner = push ? desktop : cloud;
      const flow = await runSync({ local: desktop, remote, baseline: createBaseline(base, 'older'), overwrite });
      expect(flow.result.kind).toBe(push ? 'push' : 'pull');
      const confirmed = remote.state.snapshot!;
      expect(expectLiveItemIds(confirmed)).toEqual(expectLiveItemIds(winner));
      expect(confirmed.bookmarkOrders.browser_root_toolbar.ids).toEqual(winner.bookmarkOrders.browser_root_toolbar.ids);
      expect(confirmed.bookmarkItems.shared.title).toBe(winner.bookmarkItems.shared.title);
      expect(confirmed.appPrivateBookmarks).toEqual(cloud.appPrivateBookmarks);
      expect(flow.baselineStore.value?.snapshot).toEqual(confirmed);
      if (push) {
        expect(confirmed.bookmarkItems.shared.revision).toBeGreaterThan(9);
        expect(confirmed.tombstones['bookmark-item|theirs']).toBeDefined();
        const otherDevice = await runSync({ local: cloud, remote, baseline: createBaseline(cloud, 'commit-seed') });
        expect(expectLiveItemIds(otherDevice.local)).toEqual(expectLiveItemIds(desktop));
        expect(otherDevice.local.bookmarkItems.shared.title).toBe('Desktop edit');
      } else {
        expect(remote.writeCount).toBe(0);
        expect(comparableSnapshot(flow.local)).toEqual(comparableSnapshot(cloud));
      }
      const next = await runSync({ local: confirmed, remote, baseline: flow.baselineStore.value });
      expect(next.result.kind).toBe('noop');
    },
  );

  test('a missing remote cannot clear the computer, while a committed empty tree can', async () => {
    const local = createSnapshot('desktop', [{ id: 'mine' }]);
    const overwrite = 'remote-to-computer';
    const missing = new MemoryRemoteStore();
    await expect(runSync({ local, remote: missing, overwrite })).rejects.toThrow('没有书签快照');
    expect(missing.writeCount).toBe(0);
    const empty = await runSync({ local, remote: remoteWith(createSnapshot('cloud')), overwrite });
    expect(expectLiveItemIds(empty.local)).toEqual([]);
    const fresh = new MemoryRemoteStore();
    await runSync({ local, remote: fresh, overwrite: 'computer-to-remote' });
    expect(expectLiveItemIds(fresh.state.snapshot!)).toEqual(['mine']);
  });

  test('a missing browser root cannot be uploaded as an empty bookmark collection', async () => {
    const remote = remoteWith(createSnapshot('cloud', [{ id: 'only-cloud' }]));
    const local = { ...createSnapshot('desktop'), bookmarkFolders: {}, bookmarkOrders: {} };
    await expect(runSync({ local, remote, overwrite: 'computer-to-remote' })).rejects.toThrow('根目录');
    expect(remote.writeCount).toBe(0);
  });

  test('a committed rootless empty snapshot clears the items and keeps native browser roots', async () => {
    const local = createSnapshot('desktop', [{ id: 'mine' }]);
    const empty = { ...createSnapshot('cloud'), bookmarkFolders: {}, bookmarkOrders: {} };
    const remote = remoteWith(empty);
    const flow = await runSync({ local, remote, overwrite: 'remote-to-computer' });
    expect(expectLiveItemIds(flow.local)).toEqual([]);
    expect(flow.local.bookmarkFolders.browser_root_toolbar).toBeDefined();
    expect(flow.local.bookmarkOrders.browser_root_toolbar.ids).toEqual([]);
    const next = await runSync({ local: flow.local, remote, baseline: flow.baselineStore.value });
    expect(next.result.kind).toBe('noop');
    expect(remote.writeCount).toBe(0);
  });

  test('paired readers with identical order and different metadata converge without another write', async () => {
    const first = createSnapshot('first', [{ id: 'shared' }]);
    const second = clone(first);
    for (const order of Object.values(second.bookmarkOrders)) {
      order.updatedBy = 'second';
      order.updatedAt = T1;
    }
    const remote = remoteWith(first);
    const reader = await runSync({ local: second, baseline: createBaseline(second, 'older'), remote });
    expect(remote.writeCount).toBe(0);
    expect(reader.baselineStore.value?.snapshot?.bookmarkOrders).toEqual(first.bookmarkOrders);
    const idle = await runSync({ local: reader.local, baseline: reader.baselineStore.value, remote });
    expect(idle.result.kind).toBe('noop');
    const writer = await runSync({ local: first, baseline: createBaseline(first, 'commit-seed'), remote });
    expect(writer.result.kind).toBe('noop');
    expect(remote.writeCount).toBe(0);
  });

  test('a paired unchanged reader accepts a large remote deletion, while a local mass deletion is guarded', async () => {
    const previous = createSnapshot('old', Array.from({ length: 101 }, (_, i) => ({ id: String(i) })));
    const remote = remoteWith(previous);
    const desktop = createSnapshot('desktop', [{ id: '0' }], Object.values(previous.bookmarkItems).slice(1).map(item => ({
      type: item.type, id: item.id, deletedBy: 'desktop', deletedAt: T1, lastKnownRevision: item.revision,
    })));
    const baseline = createBaseline(previous, 'commit-seed');
    await expect(runSync({ local: desktop, remote, baseline })).rejects.toThrow('100');
    await runSync({ local: desktop, remote, baseline, overwrite: 'computer-to-remote' });
    const reader = await runSync({ local: previous, remote, baseline });
    expect(expectLiveItemIds(reader.local)).toEqual(['0']);
    expect(remote.writeCount).toBe(1);
    const next = await runSync({ local: reader.local, remote, baseline: reader.baselineStore.value });
    expect(next.result.kind).toBe('noop');

    const edited = clone(previous);
    const extra = createSnapshot('reader', [{ id: 'reader-only' }]).bookmarkItems['reader-only'];
    edited.bookmarkItems[extra.id] = extra;
    edited.bookmarkOrders.browser_root_toolbar.ids.push(extra.id);
    const withEdit = await runSync({ local: edited, remote, baseline });
    expect(expectLiveItemIds(withEdit.local)).toEqual(['0', 'reader-only']);
    expect(expectLiveItemIds(remote.state.snapshot!)).toEqual(['0', 'reader-only']);
  });

  test('a paired reader preserves duplicate bookmarks intentionally included in an overwrite', async () => {
    const previous = createSnapshot('old');
    const remote = remoteWith(previous);
    const desktop = createSnapshot('desktop', Array.from({ length: 60 }, (_, i) => ({ id: String(i), title: 'Copy' })));
    for (const item of Object.values(desktop.bookmarkItems)) item.url = 'https://example.org/copy';
    const baseline = createBaseline(previous, 'commit-seed');
    await runSync({ local: desktop, remote, baseline, overwrite: 'computer-to-remote' });
    const reader = await runSync({ local: previous, remote, baseline });
    expect(expectLiveItemIds(reader.local)).toEqual(expectLiveItemIds(desktop));
    expect(remote.writeCount).toBe(1);
  });

  test('a failed read-only confirmation leaves automatic sync running', async () => {
    const snap = createSnapshot('old', [{ id: 'cloud' }]);
    const remote = remoteWith(snap);
    const beforeOverwrite = vi.fn(async () => {});
    vi.spyOn(remote, 'readState').mockResolvedValueOnce(clone(remote.state)).mockRejectedValue(new Error('offline'));
    await expect(runSync({ local: createSnapshot('desktop'), remote, overwrite: 'remote-to-computer',
      beforeOverwrite })).rejects.toThrow();
    expect(beforeOverwrite).not.toHaveBeenCalled();
    expect(remote.writeCount).toBe(0);
  });

  test('a concurrent remote write retries the overwrite against the new head', async () => {
    const original = remoteWith(createSnapshot('cloud')).state;
    const newer = remoteWith(createSnapshot('cloud', [{ id: 'newer' }]), 'concurrent').state;
    const remote = new RacingRemoteStore(original, newer);
    const flow = await runSync({ local: createSnapshot('desktop', [{ id: 'mine' }]), remote,
      overwrite: 'computer-to-remote' });
    expect(expectLiveItemIds(remote.state.snapshot!)).toEqual(['mine']);
    expect(remote.state.snapshot!.tombstones['bookmark-item|newer']).toBeDefined();
    expect(flow.baselineStore.value?.commitId).toBe(remote.state.commitId);
  });

  test('a new user with only local bookmarks publishes the first remote state', async () => {
    const remote = new MemoryRemoteStore();
    const flow = await runSync({
      local: createSnapshot('desktop-a', [{ id: 'local-a' }]),
      remote,
    });

    expect({
      kind: flow.result.kind,
      remoteItems: expectLiveItemIds(remote.state.snapshot!),
      baselineCommitId: flow.baselineStore.value?.commitId,
    }).toEqual({
      kind: 'push',
      remoteItems: ['local-a'],
      baselineCommitId: 'commit-1',
    });
  });

  test('a new user with only remote bookmarks restores them locally', async () => {
    const remote = remoteWith(createSnapshot('phone-a', [{ id: 'remote-a' }]));
    const flow = await runSync({ local: createSnapshot('desktop-a'), remote });

    expect({
      kind: flow.result.kind,
      localItems: expectLiveItemIds(flow.local),
      baselineCommitId: flow.baselineStore.value?.commitId,
    }).toEqual({
      kind: 'pull',
      localItems: ['remote-a'],
      baselineCommitId: 'commit-seed',
    });
  });

  test('first sync with bookmarks on both sides preserves both sets', async () => {
    const remote = remoteWith(createSnapshot('phone-a', [{ id: 'remote-a' }]));
    const flow = await runSync({
      local: createSnapshot('desktop-a', [{ id: 'local-a' }]),
      remote,
    });

    expect({
      kind: flow.result.kind,
      localItems: expectLiveItemIds(flow.local),
      remoteItems: expectLiveItemIds(remote.state.snapshot!),
    }).toEqual({
      kind: 'merge',
      localItems: ['local-a', 'remote-a'],
      remoteItems: ['local-a', 'remote-a'],
    });
  });

  test.each(['remote', 'local', 'both'] as const)(
    'first join collapses exact copies from %s and preserves other folders and titles', async (source) => {
      const seed = createFolderTreeSnapshot('old', 'Group', 1);
      const original = seed.bookmarkItems['folder-child-0'];
      const folder = seed.bookmarkFolders['folder-shared'];
      for (const [folderId, folderTitle] of [['same-path', 'Group'], ['different-path', 'Elsewhere']]) {
        seed.bookmarkFolders[folderId] = { ...folder, id: folderId, title: folderTitle };
        seed.bookmarkOrders.browser_root_toolbar.ids.push(folderId);
        const id = 'item-' + folderId;
        seed.bookmarkItems[id] = { ...original, id, parentId: folderId };
        seed.bookmarkOrders[folderId] = { ...seed.bookmarkOrders[folder.id], parentId: folderId, ids: [id] };
      }
      seed.bookmarkItems.renamed = { ...original, id: 'renamed', title: 'Other title' };
      seed.bookmarkOrders[folder.id].ids.push('renamed');
      const remote = source === 'local' ? new MemoryRemoteStore() : remoteWith(seed);
      const local = source === 'remote' ? createSnapshot('new') : clone(seed);
      const first = await runSync({ local, remote });
      const expected = [original.id, 'item-different-path', 'renamed'].sort();
      expect(expectLiveItemIds(first.local)).toEqual(expected);
      expect(expectLiveItemIds(remote.state.snapshot!)).toEqual(expected);
      expect(first.local.bookmarkOrders['same-path'].ids).toEqual([]);
      expect(first.local.tombstones['bookmark-item|item-same-path']?.lastKnownRevision).toBe(original.revision);
      expect(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(first.local))).toBeTruthy();
      const writes = remote.writeCount;
      const second = await runSync({ local: first.local, remote, baseline: first.baselineStore.value });
      expect(second.result.kind).toBe('noop');
      expect(remote.writeCount).toBe(writes);
    },
  );

  test('retries first-join cleanup after local apply fails without restoring retired copies', async () => {
    const local = createSnapshot('desktop', [{ id: 'first' }, { id: 'copy' }]);
    local.bookmarkItems.copy = { ...local.bookmarkItems.first, id: 'copy' };
    const remote = remoteWith(clone(local));
    await expect(runSync({ local, remote, applyFailure: new Error('interrupted') })).rejects.toThrow();
    const committedId = remote.state.commitId;
    const retry = await runSync({ local, remote });
    expect(expectLiveItemIds(retry.local)).toEqual(['first']);
    expect(retry.local.tombstones['bookmark-item|copy']).toBeDefined();
    expect(retry.baselineStore.value?.commitId).toBe(committedId);
  });

  test('ordinary sync with a baseline keeps a newly added exact copy', async () => {
    const seed = createSnapshot('desktop', [{ id: 'first' }]);
    const local = clone(seed);
    local.bookmarkItems.copy = { ...local.bookmarkItems.first, id: 'copy' };
    local.bookmarkOrders.browser_root_toolbar.ids.push('copy');
    const remote = remoteWith(seed);
    await runSync({ local, remote, baseline: createBaseline(seed, 'commit-seed') });
    expect(expectLiveItemIds(remote.state.snapshot!)).toEqual(['copy', 'first']);
  });

  test('deleting a first-sync preservation folder commits the whole subtree deletion', async () => {
    const remote = remoteWith(createFolderTreeSnapshot('phone-a', 'Phone folder'));
    const first = await runSync({
      local: createFolderTreeSnapshot('desktop-a', 'Desktop folder'),
      remote,
    });
    const preservedFolderId = Object.keys(first.local.bookmarkFolders).find((id) => (
      id !== 'browser_root_toolbar' && id !== 'folder-shared'
    ));
    expect(preservedFolderId).toBeDefined();
    const preservedChildren = Object.values(first.local.bookmarkItems).filter((item) => (
      item.parentId === preservedFolderId
    ));
    expect(preservedChildren).toHaveLength(6);

    const localAfterDelete = clone(first.local);
    const deletedFolder = localAfterDelete.bookmarkFolders[preservedFolderId!];
    delete localAfterDelete.bookmarkFolders[preservedFolderId!];
    delete localAfterDelete.bookmarkOrders[preservedFolderId!];
    localAfterDelete.bookmarkOrders.browser_root_toolbar.ids =
      localAfterDelete.bookmarkOrders.browser_root_toolbar.ids.filter((id) => id !== preservedFolderId);
    localAfterDelete.tombstones[`bookmark-folder|${preservedFolderId}`] = {
      id: preservedFolderId!,
      type: 'bookmark-folder',
      deletedAt: T1,
      deletedBy: 'desktop-a',
      lastKnownRevision: deletedFolder.revision,
    };
    preservedChildren.forEach((item) => {
      delete localAfterDelete.bookmarkItems[item.id];
      localAfterDelete.tombstones[`bookmark-item|${item.id}`] = {
        id: item.id,
        type: 'bookmark-item',
        deletedAt: T1,
        deletedBy: 'desktop-a',
        lastKnownRevision: item.revision,
      };
    });

    const second = await runSync({
      local: localAfterDelete,
      remote,
      baseline: first.baselineStore.value,
    });
    const finalRemote = remote.state.snapshot!;

    expect({
      kind: second.result.kind,
      remoteCommitId: remote.state.commitId,
      localFolders: Object.keys(second.local.bookmarkFolders).length,
      localItems: Object.keys(second.local.bookmarkItems).length,
      remoteFolders: Object.keys(finalRemote.bookmarkFolders).length,
      remoteItems: Object.keys(finalRemote.bookmarkItems).length,
      staleOrder: finalRemote.bookmarkOrders[preservedFolderId!],
      baselineCommitId: second.baselineStore.value?.commitId,
      canonical: Boolean(parseCanonicalLeafTabSyncWireSnapshot(toLeafTabSyncWireSnapshot(finalRemote))),
    }).toEqual({
      kind: 'push',
      remoteCommitId: 'commit-2',
      localFolders: 2,
      localItems: 6,
      remoteFolders: 2,
      remoteItems: 6,
      staleOrder: undefined,
      baselineCommitId: 'commit-2',
      canonical: true,
    });
  });

  test('an established local edit is pushed without replacing the local tree', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'item-a', title: 'Before' }]);
    const local = createSnapshot('desktop-a', [{
      id: 'item-a',
      title: 'After',
      revision: 2,
      updatedAt: T1,
    }]);
    const remote = remoteWith(clone(base));
    const flow = await runSync({ local, remote, baseline: createBaseline(base, 'commit-seed') });

    expect({
      kind: flow.result.kind,
      remoteTitle: remote.state.snapshot?.bookmarkItems['item-a'].title,
      localTitle: flow.local.bookmarkItems['item-a'].title,
    }).toEqual({ kind: 'push', remoteTitle: 'After', localTitle: 'After' });
  });

  test('an established remote edit is pulled and verified locally', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'item-a', title: 'Before' }]);
    const remoteSnapshot = createSnapshot('phone-a', [{
      id: 'item-a',
      title: 'After',
      revision: 2,
      updatedAt: T1,
    }]);
    remoteSnapshot.bookmarkOrders = clone(base.bookmarkOrders);
    const remote = remoteWith(remoteSnapshot);
    const flow = await runSync({
      local: clone(base),
      remote,
      baseline: createBaseline(base, 'commit-seed'),
    });

    expect({
      kind: flow.result.kind,
      localTitle: flow.local.bookmarkItems['item-a'].title,
    }).toEqual({ kind: 'pull', localTitle: 'After' });
  });

  test('a remote folder move updates the parent and both affected child orders locally', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'item-a' }]);
    base.bookmarkFolders.folder_a = {
      id: 'folder_a',
      type: 'bookmark-folder',
      parentId: 'browser_root_toolbar',
      title: 'Folder A',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: 'desktop-a',
      revision: 1,
    };
    base.bookmarkFolders.folder_b = {
      ...base.bookmarkFolders.folder_a,
      id: 'folder_b',
      title: 'Folder B',
    };
    base.bookmarkItems['item-a'].parentId = 'folder_a';
    base.bookmarkOrders.browser_root_toolbar.ids = ['folder_a', 'folder_b'];
    base.bookmarkOrders.folder_a = {
      type: 'bookmark-order',
      parentId: 'folder_a',
      ids: ['item-a'],
      updatedAt: T0,
      updatedBy: 'desktop-a',
      revision: 1,
    };
    base.bookmarkOrders.folder_b = {
      ...base.bookmarkOrders.folder_a,
      parentId: 'folder_b',
      ids: [],
    };
    const remoteSnapshot = clone(base);
    remoteSnapshot.meta.deviceId = 'phone-a';
    remoteSnapshot.bookmarkItems['item-a'] = {
      ...remoteSnapshot.bookmarkItems['item-a'],
      parentId: 'folder_b',
      updatedAt: T1,
      updatedBy: 'phone-a',
      revision: 2,
    };
    remoteSnapshot.bookmarkOrders.folder_a = {
      ...remoteSnapshot.bookmarkOrders.folder_a,
      ids: [],
      updatedAt: T1,
      updatedBy: 'phone-a',
      revision: 2,
    };
    remoteSnapshot.bookmarkOrders.folder_b = {
      ...remoteSnapshot.bookmarkOrders.folder_b,
      ids: ['item-a'],
      updatedAt: T1,
      updatedBy: 'phone-a',
      revision: 2,
    };
    const flow = await runSync({
      local: clone(base),
      remote: remoteWith(remoteSnapshot),
      baseline: createBaseline(base, 'commit-seed'),
    });

    expect({
      parentId: flow.local.bookmarkItems['item-a'].parentId,
      folderAOrder: flow.local.bookmarkOrders.folder_a.ids,
      folderBOrder: flow.local.bookmarkOrders.folder_b.ids,
    }).toEqual({
      parentId: 'folder_b',
      folderAOrder: [],
      folderBOrder: ['item-a'],
    });
  });

  test('an established local deletion publishes its tombstone', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'item-a' }]);
    const tombstone: LeafTabSyncTombstone = {
      id: 'item-a',
      type: 'bookmark-item',
      deletedAt: T1,
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    };
    const local = createSnapshot('desktop-a', [], [tombstone]);
    const remote = remoteWith(clone(base));
    const flow = await runSync({ local, remote, baseline: createBaseline(base, 'commit-seed') });

    expect({
      kind: flow.result.kind,
      remoteItems: expectLiveItemIds(remote.state.snapshot!),
      remoteTombstones: Object.keys(remote.state.snapshot?.tombstones || {}),
    }).toEqual({
      kind: 'push',
      remoteItems: [],
      remoteTombstones: ['bookmark-item|item-a'],
    });
  });

  test('an established remote deletion removes the local bookmark', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'item-a' }]);
    const tombstone: LeafTabSyncTombstone = {
      id: 'item-a',
      type: 'bookmark-item',
      deletedAt: T1,
      deletedBy: 'phone-a',
      lastKnownRevision: 1,
    };
    const remote = remoteWith(createSnapshot('phone-a', [], [tombstone]));
    const flow = await runSync({
      local: clone(base),
      remote,
      baseline: createBaseline(base, 'commit-seed'),
    });

    expect({
      kind: flow.result.kind,
      localItems: expectLiveItemIds(flow.local),
      localTombstones: Object.keys(flow.local.tombstones),
    }).toEqual({
      kind: 'pull',
      localItems: [],
      localTombstones: ['bookmark-item|item-a'],
    });
  });

  test('two desktop users converge after staggered first sync, edit, and deletion operations', async () => {
    const remote = new MemoryRemoteStore();
    const devices = {
      a: {
        local: createSnapshot('desktop-a', [{ id: 'item-a', title: 'A' }]),
        baseline: new MemoryBaselineStore(),
        history: new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore()),
      },
      b: {
        local: createSnapshot('desktop-b', [{ id: 'item-b', title: 'B' }]),
        baseline: new MemoryBaselineStore(),
        history: new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore()),
      },
    };
    const syncDevice = async (key: 'a' | 'b') => {
      const device = devices[key];
      const engine = new LeafTabSyncEngine({
        deviceId: device.local.meta.deviceId,
        remoteStore: remote,
        baselineStore: device.baseline,
        historyLifecycle: device.history,
        buildLocalSnapshot: async () => clone(device.local),
        applyLocalSnapshot: async (snapshot) => { device.local = clone(snapshot); },
        verifyLocalSnapshot: async (snapshot) => {
          expect(comparableSnapshot(device.local)).toEqual(comparableSnapshot(snapshot));
        },
        createEmptySnapshot: () => createSnapshot(device.local.meta.deviceId),
      });
      await engine.sync();
    };

    await syncDevice('a');
    await syncDevice('b');
    await syncDevice('a');

    devices.a.local = createSnapshot('desktop-a', [
      { id: 'item-a', title: 'A edited', revision: 2, updatedAt: T1 },
      { id: 'item-b', title: 'B' },
    ]);
    await syncDevice('a');

    devices.b.local = createSnapshot('desktop-b', [
      { id: 'item-a', title: 'A' },
    ], [{
      id: 'item-b',
      type: 'bookmark-item',
      deletedAt: '2026-08-03T00:00:00.000Z',
      deletedBy: 'desktop-b',
      lastKnownRevision: 1,
    }]);
    await syncDevice('b');
    await syncDevice('a');

    expect({
      desktopA: Object.values(devices.a.local.bookmarkItems).map((item) => item.title),
      desktopB: Object.values(devices.b.local.bookmarkItems).map((item) => item.title),
      remote: Object.values(remote.state.snapshot?.bookmarkItems || {}).map((item) => item.title),
      remoteTombstones: Object.keys(remote.state.snapshot?.tombstones || {}),
    }).toEqual({
      desktopA: ['A edited'],
      desktopB: ['A edited'],
      remote: ['A edited'],
      remoteTombstones: ['bookmark-item|item-b'],
    });
  });

  test('an untouched desktop does not get a conflict when the remote tombstone frontier moved', async () => {
    // Reported symptom: the popup asked to resolve "双向修改冲突" although nothing had been
    // edited on the desktop. Cause: the shared tombstone frontier advanced elsewhere, which
    // excludes this device's baseline for one run; the missing-baseline merge then treated a
    // remote deletion as a delete-vs-edit conflict. A first join has no shared ancestor, so it
    // cannot prove any edit and must treat a surviving tombstone as a deletion (design doc 6.1b).
    const confirmed = createSnapshot('desktop-a', [{ id: 'item-a', title: 'A', revision: 2 }]);
    const remote = new MemoryRemoteStore({
      snapshot: createSnapshot('phone-a', [], [{
        id: 'item-a',
        type: 'bookmark-item',
        deletedAt: T1,
        deletedBy: 'phone-a',
        lastKnownRevision: 1,
      }]),
      commitId: 'commit-seed',
      // The phone advanced the shared frontier; this device's baseline still carries the origin.
      history: {
        version: 1,
        epochId: 'bookmark-history-v1-advanced-phone',
        retainedFrom: '2026-07-26T00:00:00.000Z',
      },
    });
    const flow = await runSync({
      local: confirmed,
      remote,
      baseline: createBaseline(confirmed, 'commit-seed'),
    });

    expect({
      kind: flow.result.kind,
      conflicts: flow.result.mergeResult?.conflicts.length ?? 0,
      localItems: expectLiveItemIds(flow.local),
      localTombstones: Object.keys(flow.local.tombstones),
    }).toEqual({
      // The remote deletion applies silently; the run also carries the advanced frontier,
      // so it is a merge rather than a pure pull. What matters is that no conflict is asked.
      kind: 'merge',
      conflicts: 0,
      localItems: [],
      localTombstones: ['bookmark-item|item-a'],
    });
  });

  test('a resolved conflict does not re-appear on the next run of the same state', async () => {
    // Regression guard for the sticky dialog: once the user picks a side, the very next run
    // against the same state must not re-derive the same conflict.
    const confirmed = createSnapshot('desktop-a', [{ id: 'item-a', title: 'A', revision: 2 }]);
    const remote = new MemoryRemoteStore({
      snapshot: createSnapshot('phone-a', [], [{
        id: 'item-a',
        type: 'bookmark-item',
        deletedAt: T1,
        deletedBy: 'phone-a',
        lastKnownRevision: 1,
      }]),
      commitId: 'commit-seed',
      history: {
        version: 1,
        epochId: 'bookmark-history-v1-advanced-phone',
        retainedFrom: '2026-07-26T00:00:00.000Z',
      },
    });

    const first = await runSync({
      local: confirmed,
      remote,
      baseline: createBaseline(confirmed, 'commit-seed'),
      conflictResolution: 'prefer-local',
    });
    const second = await runSync({
      local: first.local,
      remote,
      baseline: first.baselineStore.value,
      conflictResolution: 'prefer-local',
    });

    expect({
      firstKind: first.result.kind,
      secondKind: second.result.kind,
      secondConflicts: second.result.mergeResult?.conflicts.length ?? 0,
    }).toEqual({ firstKind: 'push', secondKind: 'noop', secondConflicts: 0 });
  });

  test('concurrent incompatible edits stop at a conflict without advancing the baseline', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'item-a', title: 'Before' }]);
    const local = createSnapshot('desktop-a', [{ id: 'item-a', title: 'Desktop', revision: 2, updatedAt: T1 }]);
    const remote = remoteWith(createSnapshot('phone-a', [{
      id: 'item-a',
      title: 'Phone',
      revision: 2,
      updatedAt: T1,
    }]));
    const flow = await runSync({ local, remote, baseline: createBaseline(base, 'commit-seed') });

    expect({
      kind: flow.result.kind,
      remoteTitle: remote.state.snapshot?.bookmarkItems['item-a'].title,
      baselineTitle: flow.baselineStore.value?.snapshot?.bookmarkItems['item-a'].title,
    }).toEqual({ kind: 'conflict', remoteTitle: 'Phone', baselineTitle: 'Before' });
  });

  test('choosing the computer side resolves a concurrent edit and commits it', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'item-a', title: 'Before' }]);
    const local = createSnapshot('desktop-a', [{ id: 'item-a', title: 'Desktop', revision: 2, updatedAt: T1 }]);
    const remote = remoteWith(createSnapshot('phone-a', [{
      id: 'item-a',
      title: 'Phone',
      revision: 2,
      updatedAt: T1,
    }]));
    const flow = await runSync({
      local,
      remote,
      baseline: createBaseline(base, 'commit-seed'),
      conflictResolution: 'prefer-local',
    });

    expect({
      kind: flow.result.kind,
      remoteTitle: remote.state.snapshot?.bookmarkItems['item-a'].title,
      baselineTitle: flow.baselineStore.value?.snapshot?.bookmarkItems['item-a'].title,
    }).toEqual({ kind: 'push', remoteTitle: 'Desktop', baselineTitle: 'Desktop' });
  });

  test('choosing the current sync source resolves an offline delete versus remote edit conflict', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'item-a', title: 'Before' }]);
    const local = createSnapshot('desktop-a', [], [{
      id: 'item-a',
      type: 'bookmark-item',
      deletedAt: T1,
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    }]);
    const remote = remoteWith(createSnapshot('phone-a', [{
      id: 'item-a',
      title: 'Phone edited',
      revision: 2,
      updatedAt: T1,
    }]));

    const conflict = await runSync({
      local,
      remote,
      baseline: createBaseline(base, 'commit-seed'),
    });
    expect({
      kind: conflict.result.kind,
      baselineTitle: conflict.baselineStore.value?.snapshot?.bookmarkItems['item-a'].title,
    }).toEqual({ kind: 'conflict', baselineTitle: 'Before' });

    const resolved = await runSync({
      local,
      remote,
      baseline: createBaseline(base, 'commit-seed'),
      conflictResolution: 'prefer-remote',
    });
    expect({
      kind: resolved.result.kind,
      localTitle: resolved.local.bookmarkItems['item-a'].title,
      tombstones: Object.keys(resolved.local.tombstones),
    }).toEqual({
      kind: 'merge',
      localTitle: 'Phone edited',
      tombstones: [],
    });
  });

  test('repeating an identical sync keeps the remote commit and baseline unchanged', async () => {
    const snapshot = createSnapshot('desktop-a', [{ id: 'item-a' }]);
    const baseline = createBaseline(snapshot, 'commit-seed');
    const remote = remoteWith(clone(snapshot));
    const flow = await runSync({ local: clone(snapshot), remote, baseline });

    expect({
      kind: flow.result.kind,
      remoteCommitId: remote.state.commitId,
      remoteWrites: remote.writeCount,
      baselineWrites: flow.baselineStore.saveCount,
    }).toEqual({
      kind: 'noop',
      remoteCommitId: 'commit-seed',
      remoteWrites: 0,
      baselineWrites: 0,
    });
  });

  test('switching Aira to WebDAV and back preserves the union on both providers', async () => {
    let local = createSnapshot('desktop-a', [{ id: 'aira-a' }]);
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore());
    const airaBaseline = new MemoryBaselineStore();
    const webdavBaseline = new MemoryBaselineStore();
    const aira = new MemoryRemoteStore();
    const webdav = remoteWith(createSnapshot('phone-a', [{ id: 'webdav-b' }]));
    const syncProvider = async (remote: MemoryRemoteStore, baselineStore: MemoryBaselineStore) => {
      const engine = new LeafTabSyncEngine({
        deviceId: 'desktop-a',
        remoteStore: remote,
        baselineStore,
        historyLifecycle,
        buildLocalSnapshot: async () => clone(local),
        applyLocalSnapshot: async (snapshot) => { local = clone(snapshot); },
        verifyLocalSnapshot: async (snapshot) => {
          expect(comparableSnapshot(local)).toEqual(comparableSnapshot(snapshot));
        },
        createEmptySnapshot: () => createSnapshot('desktop-a'),
      });
      return engine.sync();
    };

    await syncProvider(aira, airaBaseline);
    await syncProvider(webdav, webdavBaseline);
    await syncProvider(aira, airaBaseline);

    expect({
      local: expectLiveItemIds(local),
      aira: expectLiveItemIds(aira.state.snapshot!),
      webdav: expectLiveItemIds(webdav.state.snapshot!),
    }).toEqual({
      local: ['aira-a', 'webdav-b'],
      aira: ['aira-a', 'webdav-b'],
      webdav: ['aira-a', 'webdav-b'],
    });
  });

  test('switching back to Aira does not replay its tombstone over a bookmark restored by WebDAV', async () => {
    let local = createSnapshot('desktop-a', [{ id: 'shared-a' }]);
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore());
    const airaBaseline = new MemoryBaselineStore();
    const webdavBaseline = new MemoryBaselineStore();
    const aira = new MemoryRemoteStore();
    const webdav = remoteWith(createSnapshot('phone-a', [{ id: 'shared-a' }]));
    const syncProvider = async (
      remote: MemoryRemoteStore,
      baselineStore: MemoryBaselineStore,
      providerSwitch = false,
    ) => {
      const engine = new LeafTabSyncEngine({
        deviceId: 'desktop-a',
        remoteStore: remote,
        baselineStore,
        historyLifecycle,
        buildLocalSnapshot: async () => clone(local),
        applyLocalSnapshot: async (snapshot) => { local = clone(snapshot); },
        verifyLocalSnapshot: async (snapshot) => {
          expect(comparableSnapshot(local)).toEqual(comparableSnapshot(snapshot));
        },
        createEmptySnapshot: () => createSnapshot('desktop-a'),
      });
      return engine.sync(providerSwitch
        ? { mergeIntent: 'provider-switch' }
        : undefined);
    };

    await syncProvider(aira, airaBaseline);
    local = createSnapshot('desktop-a', [], [{
      id: 'shared-a',
      type: 'bookmark-item',
      deletedAt: T1,
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    }]);
    await syncProvider(aira, airaBaseline);
    await syncProvider(webdav, webdavBaseline, true);
    await syncProvider(aira, airaBaseline, true);

    expect({
      local: expectLiveItemIds(local),
      aira: expectLiveItemIds(aira.state.snapshot!),
      webdav: expectLiveItemIds(webdav.state.snapshot!),
    }).toEqual({
      local: ['shared-a'],
      aira: ['shared-a'],
      webdav: ['shared-a'],
    });

    local = createSnapshot('desktop-a', [], [{
      id: 'shared-a',
      type: 'bookmark-item',
      deletedAt: '2026-08-03T00:00:00.000Z',
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    }]);
    await syncProvider(aira, airaBaseline);

    expect({
      local: expectLiveItemIds(local),
      aira: expectLiveItemIds(aira.state.snapshot!),
      airaTombstones: Object.keys(aira.state.snapshot?.tombstones || {}),
    }).toEqual({
      local: [],
      aira: [],
      airaTombstones: ['bookmark-item|shared-a'],
    });
  });

  test('switching from WebDAV back to Aira preserves an Aira bookmark against the WebDAV deletion', async () => {
    let local = createSnapshot('desktop-a', [{ id: 'shared-a' }]);
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore());
    const airaBaseline = new MemoryBaselineStore();
    const webdavBaseline = new MemoryBaselineStore();
    const aira = new MemoryRemoteStore();
    const webdav = new MemoryRemoteStore();
    const syncProvider = async (
      remote: MemoryRemoteStore,
      baselineStore: MemoryBaselineStore,
      mergeIntent: 'ordinary' | 'provider-switch' = 'ordinary',
    ) => {
      const engine = new LeafTabSyncEngine({
        deviceId: 'desktop-a',
        remoteStore: remote,
        baselineStore,
        historyLifecycle,
        buildLocalSnapshot: async () => clone(local),
        applyLocalSnapshot: async (snapshot) => { local = clone(snapshot); },
        verifyLocalSnapshot: async (snapshot) => {
          expect(comparableSnapshot(local)).toEqual(comparableSnapshot(snapshot));
        },
        createEmptySnapshot: () => createSnapshot('desktop-a'),
      });
      return engine.sync({ mergeIntent });
    };

    await syncProvider(aira, airaBaseline);
    await syncProvider(webdav, webdavBaseline, 'provider-switch');
    local = createSnapshot('desktop-a', [], [{
      id: 'shared-a',
      type: 'bookmark-item',
      deletedAt: T1,
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    }]);
    await syncProvider(webdav, webdavBaseline);
    await syncProvider(aira, airaBaseline, 'provider-switch');

    expect({
      local: expectLiveItemIds(local),
      aira: expectLiveItemIds(aira.state.snapshot!),
      webdav: expectLiveItemIds(webdav.state.snapshot!),
    }).toEqual({
      local: ['shared-a'],
      aira: ['shared-a'],
      webdav: [],
    });
  });

  test('a newer remote history discards the old baseline and preserves incompatible live copies', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'shared', title: 'Desktop copy' }]);
    const remoteSnapshot = createSnapshot('phone-a', [{ id: 'shared', title: 'Phone copy' }]);
    const newerHistory: LeafTabSyncHistoryDescriptor = {
      version: 1,
      epochId: 'bookmark-history-v1-newer',
      retainedFrom: '2026-05-01T00:00:00.000Z',
    };
    const remote = new MemoryRemoteStore({
      snapshot: remoteSnapshot,
      commitId: 'commit-newer-history',
      history: newerHistory,
    });
    const flow = await runSync({
      local: clone(base),
      remote,
      baseline: createBaseline(base, 'commit-old-history'),
    });

    const titles = Object.values(flow.local.bookmarkItems).map((item) => item.title).sort();
    expect({ titles, history: flow.baselineStore.value?.history }).toEqual({
      titles: ['Desktop copy', 'Phone copy'],
      history: newerHistory,
    });
  });

  test('an expired tombstone advances history only after remote confirmation and leaves a clean baseline', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(EXPIRY_NOW);
    const expiredTombstone: LeafTabSyncTombstone = {
      id: 'deleted-a',
      type: 'bookmark-item',
      deletedAt: EXPIRED_TOMBSTONE_DELETED_AT,
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    };
    const snapshot = createSnapshot('desktop-a', [], [expiredTombstone]);
    const remote = remoteWith(clone(snapshot));
    const flow = await runSync({
      local: clone(snapshot),
      remote,
      baseline: createBaseline(snapshot, 'commit-seed'),
    });

    expect({
      retainedFrom: flow.baselineStore.value?.history.retainedFrom,
      baselineTombstones: Object.keys(flow.baselineStore.value?.snapshot?.tombstones || {}),
      remoteTombstones: Object.keys(remote.state.snapshot?.tombstones || {}),
      confirmedHistory: await flow.historyLifecycle.readConfirmedHistory(),
    }).toEqual({
      retainedFrom: EXPIRY_ADVANCED_RETAINED_FROM,
      baselineTombstones: [],
      remoteTombstones: [],
      confirmedHistory: flow.baselineStore.value?.history,
    });
  });

  test('Aira and WebDAV adopt the same retainedFrom after one provider retires an expired tombstone', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(EXPIRY_NOW);
    const expiredTombstone: LeafTabSyncTombstone = {
      id: 'deleted-a',
      type: 'bookmark-item',
      deletedAt: EXPIRED_TOMBSTONE_DELETED_AT,
      deletedBy: 'desktop-a',
      lastKnownRevision: 1,
    };
    let local = createSnapshot('desktop-a', [], [expiredTombstone]);
    const historyLifecycle = new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore());
    const airaBaseline = new MemoryBaselineStore(createBaseline(local, 'commit-aira-seed'));
    const webdavBaseline = new MemoryBaselineStore(createBaseline(local, 'commit-webdav-seed'));
    const aira = remoteWith(clone(local), 'commit-aira-seed');
    const webdav = remoteWith(clone(local), 'commit-webdav-seed');
    const syncProvider = async (
      remote: MemoryRemoteStore,
      baselineStore: MemoryBaselineStore,
      mergeIntent: 'ordinary' | 'provider-switch' = 'ordinary',
    ) => {
      const engine = new LeafTabSyncEngine({
        deviceId: 'desktop-a',
        remoteStore: remote,
        baselineStore,
        historyLifecycle,
        buildLocalSnapshot: async () => clone(local),
        applyLocalSnapshot: async (snapshot) => { local = clone(snapshot); },
        verifyLocalSnapshot: async (snapshot) => {
          expect(comparableSnapshot(local)).toEqual(comparableSnapshot(snapshot));
        },
        createEmptySnapshot: () => createSnapshot('desktop-a'),
      });
      return engine.sync({ mergeIntent });
    };

    await syncProvider(aira, airaBaseline);
    await syncProvider(webdav, webdavBaseline, 'provider-switch');

    const histories = [
      aira.state.history,
      webdav.state.history,
      airaBaseline.value?.history,
      webdavBaseline.value?.history,
      await historyLifecycle.readConfirmedHistory(),
    ];
    expect({
      retainedFromValues: histories.map((history) => history?.retainedFrom),
      epochCount: new Set(histories.map((history) => history?.epochId)).size,
      airaTombstones: Object.keys(aira.state.snapshot?.tombstones || {}),
      webdavTombstones: Object.keys(webdav.state.snapshot?.tombstones || {}),
    }).toEqual({
      retainedFromValues: Array(5).fill(EXPIRY_ADVANCED_RETAINED_FROM),
      epochCount: 1,
      airaTombstones: [],
      webdavTombstones: [],
    });
  });

  test('a stale post-write read-back cannot apply the merge or advance the baseline', async () => {
    const base = createSnapshot('desktop-a');
    const local = createSnapshot('desktop-a', [{ id: 'local-a' }]);
    const remote = new StaleReadBackRemoteStore({
      snapshot: createSnapshot('phone-a', [{ id: 'remote-b' }]),
      commitId: 'commit-seed',
      history: ORIGIN_HISTORY,
    });
    const baselineStore = new MemoryBaselineStore(createBaseline(base, 'commit-seed'));
    let applied = false;
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore: remote,
      baselineStore,
      historyLifecycle: new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore()),
      buildLocalSnapshot: async () => clone(local),
      applyLocalSnapshot: async () => { applied = true; },
      verifyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => createSnapshot('desktop-a'),
    });

    await expect(engine.sync()).rejects.toThrow('未能确认完整的书签提交');
    expect({
      applied,
      baselineItems: expectLiveItemIds(baselineStore.value!.snapshot!),
    }).toEqual({ applied: false, baselineItems: [] });
  });

  test('a transient remote read failure leaves local state and baseline unchanged for retry', async () => {
    const base = createSnapshot('desktop-a', [{ id: 'item-a' }]);
    const remote = new TransientReadFailureRemoteStore({
      snapshot: clone(base),
      commitId: 'commit-seed',
      history: ORIGIN_HISTORY,
    });
    const baselineStore = new MemoryBaselineStore(createBaseline(base, 'commit-seed'));
    let local = clone(base);
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore: remote,
      baselineStore,
      historyLifecycle: new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore()),
      buildLocalSnapshot: async () => clone(local),
      applyLocalSnapshot: async (snapshot) => { local = clone(snapshot); },
      verifyLocalSnapshot: async (snapshot) => {
        expect(comparableSnapshot(local)).toEqual(comparableSnapshot(snapshot));
      },
      createEmptySnapshot: () => createSnapshot('desktop-a'),
    });

    await expect(engine.sync()).rejects.toThrow('network unavailable');
    expect({
      readAttempts: remote.readAttempts,
      localItems: expectLiveItemIds(local),
      baselineCommitId: baselineStore.value?.commitId,
    }).toEqual({
      readAttempts: 1,
      localItems: ['item-a'],
      baselineCommitId: 'commit-seed',
    });

    await expect(engine.sync()).resolves.toMatchObject({ kind: 'noop' });
    expect(remote.readAttempts).toBe(2);
  });

  test('a remote compare-and-swap race leaves the baseline unchanged and converges on retry', async () => {
    const base = createSnapshot('desktop-a');
    const local = createSnapshot('desktop-a', [{ id: 'local-a' }]);
    const remote = new RacingRemoteStore(
      { snapshot: clone(base), commitId: 'commit-seed', history: ORIGIN_HISTORY },
      {
        snapshot: createSnapshot('desktop-b', [{ id: 'remote-b' }]),
        commitId: 'commit-race',
        history: ORIGIN_HISTORY,
      },
    );
    const baselineStore = new MemoryBaselineStore(createBaseline(base, 'commit-seed'));
    let currentLocal = clone(local);
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop-a',
      remoteStore: remote,
      baselineStore,
      historyLifecycle: new LeafTabSyncTombstoneLifecycle(new MemoryHistoryStore()),
      buildLocalSnapshot: async () => clone(currentLocal),
      applyLocalSnapshot: async (snapshot) => { currentLocal = clone(snapshot); },
      verifyLocalSnapshot: async (snapshot) => {
        expect(comparableSnapshot(currentLocal)).toEqual(comparableSnapshot(snapshot));
      },
      createEmptySnapshot: () => createSnapshot('desktop-a'),
    });

    await expect(engine.sync()).rejects.toThrow('compare-and-swap conflict');
    expect({
      baselineCommitId: baselineStore.value?.commitId,
      baselineItems: expectLiveItemIds(baselineStore.value!.snapshot!),
    }).toEqual({ baselineCommitId: 'commit-seed', baselineItems: [] });

    await engine.sync();
    expect({
      local: expectLiveItemIds(currentLocal),
      remote: expectLiveItemIds(remote.state.snapshot!),
      baseline: expectLiveItemIds(baselineStore.value!.snapshot!),
    }).toEqual({
      local: ['local-a', 'remote-b'],
      remote: ['local-a', 'remote-b'],
      baseline: ['local-a', 'remote-b'],
    });
  });

  test('a local apply failure leaves the established baseline unchanged', async () => {
    const base = createSnapshot('desktop-a');
    const remote = remoteWith(createSnapshot('phone-a', [{ id: 'remote-a' }]));
    await expect(runSync({
      local: clone(base),
      remote,
      baseline: createBaseline(base, 'commit-seed'),
      applyFailure: new Error('browser write failed'),
    })).rejects.toThrow('browser write failed');
    expect(remote.state.commitId).toBe('commit-seed');
  });

  test('a post-apply verification failure is not reported as a completed sync', async () => {
    const base = createSnapshot('desktop-a');
    const remote = remoteWith(createSnapshot('phone-a', [{ id: 'remote-a' }]));
    await expect(runSync({
      local: clone(base),
      remote,
      baseline: createBaseline(base, 'commit-seed'),
      verifyFailure: new Error('本地书签落地校验未通过'),
    })).rejects.toThrow('本地书签落地校验未通过');
    expect(remote.state.commitId).toBe('commit-seed');
  });

  test('an incomplete remote triple fails closed before any write', async () => {
    const remote = new MemoryRemoteStore();
    remote.state = {
      snapshot: createSnapshot('phone-a', [{ id: 'remote-a' }]),
      commitId: 'commit-incomplete',
      history: null,
    };

    await expect(runSync({ local: createSnapshot('desktop-a'), remote }))
      .rejects.toThrow('不完整的书签快照');
    expect(remote.writeCount).toBe(0);
  });

  test('App-private bookmarks survive a desktop merge without becoming desktop tree items', async () => {
    const remoteSnapshot = createSnapshot('phone-a', [{ id: 'remote-a' }]);
    remoteSnapshot.appPrivateBookmarks = {
      bookmarkFolders: {},
      bookmarkItems: {
        private_a: {
          id: 'private_a',
          type: 'bookmark-item',
          parentId: null,
          title: 'Private',
          url: 'https://private.example/',
          createdAt: T0,
          updatedAt: T0,
          updatedBy: 'phone-a',
          revision: 1,
        },
      },
      bookmarkOrders: {},
      tombstones: {},
    };
    const remote = remoteWith(remoteSnapshot);
    const flow = await runSync({
      local: createSnapshot('desktop-a', [{ id: 'local-a' }]),
      remote,
    });

    expect({
      regularItems: expectLiveItemIds(flow.result.snapshot),
      privateItems: Object.keys(flow.result.snapshot.appPrivateBookmarks?.bookmarkItems || {}),
    }).toEqual({ regularItems: ['local-a', 'remote-a'], privateItems: ['private_a'] });
  });
});
