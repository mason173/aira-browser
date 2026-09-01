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
});
