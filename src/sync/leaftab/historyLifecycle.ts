import {
  LEAFTAB_SYNC_HISTORY_VERSION,
  type LeafTabSyncBaseline,
  type LeafTabSyncBookmarkDataSet,
  type LeafTabSyncHistoryDescriptor,
  type LeafTabSyncSnapshot,
  type LeafTabSyncTombstone,
} from './schema';
import type { LeafTabSyncRemoteState } from './remoteStore';

export const LEAFTAB_SYNC_TOMBSTONE_RETENTION_MS = 90 * 24 * 60 * 60 * 1000;

const ORIGIN_RETAINED_FROM = '1970-01-01T00:00:00.000Z';
const ORIGIN_EPOCH_ID = 'bookmark-history-v1-origin';

export interface LeafTabSyncHistoryStore {
  load(): Promise<LeafTabSyncHistoryDescriptor | null>;
  save(history: LeafTabSyncHistoryDescriptor): Promise<void>;
}

export interface LeafTabSyncHistoryMergePlan {
  history: LeafTabSyncHistoryDescriptor;
  baselineSnapshot: LeafTabSyncSnapshot | null;
  localSnapshot: LeafTabSyncSnapshot;
  remoteSnapshot: LeafTabSyncSnapshot | null;
  requiresRemoteHistoryWrite: boolean;
}

interface SnapshotProjection {
  snapshot: LeafTabSyncSnapshot;
  retiredTombstoneCount: number;
}

interface DataSetProjection {
  dataSet: LeafTabSyncBookmarkDataSet;
  retiredTombstoneCount: number;
}

export class LeafTabSyncExtensionStorageHistoryStore implements LeafTabSyncHistoryStore {
  private readonly key: string;

  constructor(key: string) {
    this.key = key;
  }

  private getStorageArea() {
    const storageArea = globalThis.chrome?.storage?.local;
    if (!storageArea?.get || !storageArea?.set) {
      throw new Error('chrome.storage.local is required for bookmark sync history storage');
    }
    return storageArea;
  }

  async load(): Promise<LeafTabSyncHistoryDescriptor | null> {
    const storageArea = this.getStorageArea();
    const result = await storageArea.get(this.key);
    const value = result?.[this.key];
    return value && typeof value === 'object'
      ? value as LeafTabSyncHistoryDescriptor
      : null;
  }

  async save(history: LeafTabSyncHistoryDescriptor): Promise<void> {
    const storageArea = this.getStorageArea();
    await storageArea.set({ [this.key]: history });
  }
}

export class LeafTabSyncTombstoneLifecycle {
  private readonly store: LeafTabSyncHistoryStore | null;

  constructor(store?: LeafTabSyncHistoryStore) {
    this.store = store || null;
  }

  async planMerge(
    baseline: LeafTabSyncBaseline | null,
    localSnapshot: LeafTabSyncSnapshot,
    remoteState: LeafTabSyncRemoteState,
    deviceId: string,
    now = Date.now(),
  ): Promise<LeafTabSyncHistoryMergePlan> {
    const confirmedHistory = await this.readConfirmedHistory();
    let targetHistory = confirmedHistory;
    if (remoteState.history) {
      targetHistory = this.selectNewerHistory(targetHistory, remoteState.history);
    }
    if (baseline?.history) {
      targetHistory = this.selectNewerHistory(targetHistory, baseline.history);
    }

    const automaticRetainedFrom = Math.max(0, now - LEAFTAB_SYNC_TOMBSTONE_RETENTION_MS);
    if (automaticRetainedFrom > this.parseRetainedFrom(targetHistory)
      && this.hasTombstoneBefore(
        automaticRetainedFrom,
        localSnapshot,
        remoteState.snapshot,
        baseline?.snapshot || null,
      )) {
      targetHistory = this.createAdvancedHistory(automaticRetainedFrom, deviceId);
    }

    const localProjection = this.projectSnapshot(localSnapshot, targetHistory);
    const remoteProjection = remoteState.snapshot
      ? this.projectSnapshot(remoteState.snapshot, targetHistory)
      : null;
    const baselineMatches = Boolean(
      baseline?.snapshot
      && baseline.history
      && this.sameHistory(baseline.history, targetHistory)
      && remoteState.history
      && this.sameHistory(remoteState.history, targetHistory)
      && this.sameHistory(confirmedHistory, targetHistory),
    );
    const remoteHistoryMatches = Boolean(
      remoteState.snapshot
      && remoteState.history
      && this.sameHistory(remoteState.history, targetHistory),
    );

    return {
      history: targetHistory,
      baselineSnapshot: baselineMatches && baseline?.snapshot
        ? this.projectSnapshot(baseline.snapshot, targetHistory).snapshot
        : null,
      localSnapshot: localProjection.snapshot,
      remoteSnapshot: remoteProjection?.snapshot || null,
      requiresRemoteHistoryWrite: !remoteHistoryMatches
        || (remoteProjection?.retiredTombstoneCount || 0) > 0,
    };
  }

  async readConfirmedHistory(): Promise<LeafTabSyncHistoryDescriptor> {
    if (!this.store) {
      throw new Error('书签墓碑历史存储未配置。');
    }
    const stored = await this.store.load();
    return stored ? this.validateHistory(stored) : this.originHistory();
  }

  async confirm(history: LeafTabSyncHistoryDescriptor): Promise<void> {
    if (!this.store) {
      throw new Error('书签墓碑历史存储未配置。');
    }
    const normalized = this.validateHistory(history);
    const current = await this.readConfirmedHistory();
    const selected = this.selectNewerHistory(current, normalized);
    if (!this.sameHistory(selected, normalized)) {
      throw new Error('书签墓碑历史边界不能回退。');
    }
    if (!this.sameHistory(current, normalized)) {
      await this.store.save(normalized);
    }
  }

  projectSnapshot(
    snapshot: LeafTabSyncSnapshot,
    history: LeafTabSyncHistoryDescriptor,
  ): SnapshotProjection {
    const retainedFrom = this.parseRetainedFrom(this.validateHistory(history));
    const shared = this.projectDataSet(snapshot, retainedFrom);
    const privateProjection = snapshot.appPrivateBookmarks
      ? this.projectDataSet(snapshot.appPrivateBookmarks, retainedFrom)
      : null;
    return {
      snapshot: {
        meta: snapshot.meta,
        bookmarkFolders: snapshot.bookmarkFolders,
        bookmarkItems: snapshot.bookmarkItems,
        bookmarkOrders: snapshot.bookmarkOrders,
        tombstones: shared.dataSet.tombstones,
        ...(privateProjection ? {
          appPrivateBookmarks: {
            bookmarkFolders: snapshot.appPrivateBookmarks?.bookmarkFolders || {},
            bookmarkItems: snapshot.appPrivateBookmarks?.bookmarkItems || {},
            bookmarkOrders: snapshot.appPrivateBookmarks?.bookmarkOrders || {},
            tombstones: privateProjection.dataSet.tombstones,
          },
        } : {}),
      },
      retiredTombstoneCount: shared.retiredTombstoneCount
        + (privateProjection?.retiredTombstoneCount || 0),
    };
  }

  assertSnapshotWithinHistory(
    snapshot: LeafTabSyncSnapshot,
    history: LeafTabSyncHistoryDescriptor,
    sourceLabel: string,
  ): void {
    const retainedFrom = this.parseRetainedFrom(this.validateHistory(history));
    if (this.dataSetHasTombstoneBefore(snapshot, retainedFrom)
      || (snapshot.appPrivateBookmarks
        && this.dataSetHasTombstoneBefore(snapshot.appPrivateBookmarks, retainedFrom))) {
      throw new Error(`${sourceLabel}书签快照包含已超出保留边界的墓碑。`);
    }
  }

  validateHistory(value: unknown): LeafTabSyncHistoryDescriptor {
    if (!value || typeof value !== 'object') {
      throw new Error('书签墓碑历史纪元无效。');
    }
    const candidate = value as Partial<LeafTabSyncHistoryDescriptor>;
    const retainedFrom = Date.parse(String(candidate.retainedFrom || ''));
    if (candidate.version !== LEAFTAB_SYNC_HISTORY_VERSION
      || typeof candidate.epochId !== 'string'
      || !candidate.epochId.trim()
      || !Number.isFinite(retainedFrom)) {
      throw new Error('书签墓碑历史纪元无效。');
    }
    return {
      version: LEAFTAB_SYNC_HISTORY_VERSION,
      epochId: candidate.epochId.trim(),
      retainedFrom: new Date(retainedFrom).toISOString(),
    };
  }

  sameHistory(
    left: LeafTabSyncHistoryDescriptor,
    right: LeafTabSyncHistoryDescriptor,
  ): boolean {
    return left.version === right.version
      && left.epochId.trim() === right.epochId.trim()
      && Date.parse(left.retainedFrom) === Date.parse(right.retainedFrom);
  }

  selectNewerHistory(
    left: LeafTabSyncHistoryDescriptor,
    right: LeafTabSyncHistoryDescriptor,
  ): LeafTabSyncHistoryDescriptor {
    const normalizedLeft = this.validateHistory(left);
    const normalizedRight = this.validateHistory(right);
    const leftRetainedFrom = this.parseRetainedFrom(normalizedLeft);
    const rightRetainedFrom = this.parseRetainedFrom(normalizedRight);
    if (leftRetainedFrom !== rightRetainedFrom) {
      return rightRetainedFrom > leftRetainedFrom ? normalizedRight : normalizedLeft;
    }
    return normalizedRight.epochId.localeCompare(normalizedLeft.epochId) > 0
      ? normalizedRight
      : normalizedLeft;
  }

  private projectDataSet(
    dataSet: LeafTabSyncBookmarkDataSet | LeafTabSyncSnapshot,
    retainedFrom: number,
  ): DataSetProjection {
    const tombstones = Object.fromEntries(
      Object.entries(dataSet.tombstones).filter(([, tombstone]) => {
        const deletedAt = Date.parse(tombstone.deletedAt);
        return Number.isFinite(deletedAt) && deletedAt >= retainedFrom;
      }),
    );
    return {
      dataSet: {
        bookmarkFolders: dataSet.bookmarkFolders,
        bookmarkItems: dataSet.bookmarkItems,
        bookmarkOrders: dataSet.bookmarkOrders,
        tombstones,
      },
      retiredTombstoneCount: Object.keys(dataSet.tombstones).length - Object.keys(tombstones).length,
    };
  }

  private hasTombstoneBefore(
    cutoff: number,
    ...snapshots: Array<LeafTabSyncSnapshot | null>
  ): boolean {
    return snapshots.some((snapshot) => Boolean(
      snapshot
      && (this.dataSetHasTombstoneBefore(snapshot, cutoff)
        || (snapshot.appPrivateBookmarks
          && this.dataSetHasTombstoneBefore(snapshot.appPrivateBookmarks, cutoff))),
    ));
  }

  private dataSetHasTombstoneBefore(
    dataSet: { tombstones: Record<string, LeafTabSyncTombstone> },
    cutoff: number,
  ): boolean {
    return Object.values(dataSet.tombstones).some((tombstone) => {
      const deletedAt = Date.parse(tombstone.deletedAt);
      return Number.isFinite(deletedAt) && deletedAt < cutoff;
    });
  }

  private createAdvancedHistory(retainedFrom: number, deviceId: string): LeafTabSyncHistoryDescriptor {
    const normalizedDeviceId = deviceId.trim().replace(/[^a-zA-Z0-9_-]+/g, '_').slice(0, 48) || 'device';
    const normalizedRetainedFrom = Math.max(0, Math.floor(retainedFrom));
    return {
      version: LEAFTAB_SYNC_HISTORY_VERSION,
      epochId: `bookmark-history-v1-${normalizedRetainedFrom.toString(36)}-${normalizedDeviceId}`,
      retainedFrom: new Date(normalizedRetainedFrom).toISOString(),
    };
  }

  private originHistory(): LeafTabSyncHistoryDescriptor {
    return {
      version: LEAFTAB_SYNC_HISTORY_VERSION,
      epochId: ORIGIN_EPOCH_ID,
      retainedFrom: ORIGIN_RETAINED_FROM,
    };
  }

  private parseRetainedFrom(history: LeafTabSyncHistoryDescriptor): number {
    const retainedFrom = Date.parse(history.retainedFrom);
    if (!Number.isFinite(retainedFrom)) {
      throw new Error('书签墓碑保留边界无效。');
    }
    return retainedFrom;
  }
}
