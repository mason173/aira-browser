import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  AIRA_BOOKMARK_HISTORY_VERSION,
  AIRA_BOOKMARK_TOMBSTONE_RETENTION_MS,
  AiraBookmarkHistoryDescriptor,
  AiraSyncBaselineRecord,
  AiraSyncBookmarkDataSet,
  AiraSyncRemoteState,
  AiraSyncSnapshot,
  AiraSyncTombstone
} from '../../common/models/AiraSyncModels';

const PREFERENCES_NAME: string = 'aira_bookmark_tombstone_lifecycle_v1';
const STATE_KEY: string = 'confirmed_history';
const ORIGIN_RETAINED_FROM: string = '1970-01-01T00:00:00.000Z';
const ORIGIN_EPOCH_ID: string = 'bookmark-history-v1-origin';

export interface AiraBookmarkHistoryMergePlan {
  history: AiraBookmarkHistoryDescriptor;
  baselineSnapshot: AiraSyncSnapshot | null;
  localSnapshot: AiraSyncSnapshot;
  remoteSnapshot: AiraSyncSnapshot | null;
  requiresRemoteHistoryWrite: boolean;
}

interface AiraBookmarkHistorySnapshotProjection {
  snapshot: AiraSyncSnapshot;
  retiredTombstoneCount: number;
}

interface AiraBookmarkHistoryDataSetProjection {
  dataSet: AiraSyncBookmarkDataSet;
  retiredTombstoneCount: number;
}

export class AiraBookmarkTombstoneLifecycleService {
  async planMerge(
    baseline: AiraSyncBaselineRecord | undefined,
    localSnapshot: AiraSyncSnapshot,
    remoteState: AiraSyncRemoteState,
    deviceId: string,
    now: number = Date.now()
  ): Promise<AiraBookmarkHistoryMergePlan> {
    const confirmedHistory = await this.readConfirmedHistory();
    let targetHistory = confirmedHistory;
    if (remoteState.history !== null) {
      targetHistory = this.selectNewerHistory(targetHistory, remoteState.history);
    }
    if (baseline !== undefined) {
      targetHistory = this.selectNewerHistory(targetHistory, baseline.history);
    }

    const automaticRetainedFromMs = Math.max(0, now - AIRA_BOOKMARK_TOMBSTONE_RETENTION_MS);
    if (automaticRetainedFromMs > this.parseRetainedFrom(targetHistory) && this.hasTombstoneBefore(
      automaticRetainedFromMs,
      localSnapshot,
      remoteState.snapshot,
      baseline?.snapshot ?? null
    )) {
      targetHistory = this.createAdvancedHistory(automaticRetainedFromMs, deviceId);
    }
    const localProjection = this.projectSnapshot(localSnapshot, targetHistory);
    const remoteProjection = remoteState.snapshot === null
      ? null
      : this.projectSnapshot(remoteState.snapshot, targetHistory);
    const baselineMatches = baseline !== undefined &&
      this.sameHistory(baseline.history, targetHistory) &&
      remoteState.history !== null &&
      this.sameHistory(remoteState.history, targetHistory) &&
      this.sameHistory(confirmedHistory, targetHistory);
    const remoteHistoryMatches = remoteState.snapshot !== null && remoteState.history !== null &&
      this.sameHistory(remoteState.history, targetHistory);
    return {
      history: targetHistory,
      baselineSnapshot: baselineMatches && baseline?.snapshot !== null
        ? this.projectSnapshot(baseline.snapshot, targetHistory).snapshot
        : null,
      localSnapshot: localProjection.snapshot,
      remoteSnapshot: remoteProjection?.snapshot ?? null,
      requiresRemoteHistoryWrite: !remoteHistoryMatches || (remoteProjection?.retiredTombstoneCount ?? 0) > 0
    };
  }

  async readConfirmedHistory(): Promise<AiraBookmarkHistoryDescriptor> {
    const store = await preferences.getPreferences(
      AppRuntimeContext.getApplicationContext(),
      PREFERENCES_NAME
    );
    const payload = String(store.getSync(STATE_KEY, ''));
    if (payload.length > 0) {
      try {
        const candidate = JSON.parse(payload) as AiraBookmarkHistoryDescriptor;
        if (this.isValidHistory(candidate)) {
          return this.validateHistory(candidate);
        }
      } catch (_error) {
      }
    }
    return this.originHistory();
  }

  async confirm(history: AiraBookmarkHistoryDescriptor): Promise<void> {
    const normalized = this.validateHistory(history, '书签墓碑历史纪元');
    const current = await this.readConfirmedHistory();
    const selected = this.selectNewerHistory(current, normalized);
    if (!this.sameHistory(selected, normalized)) {
      throw new Error('书签墓碑历史边界不能回退。');
    }
    if (this.sameHistory(current, normalized)) {
      return;
    }
    const store = await preferences.getPreferences(
      AppRuntimeContext.getApplicationContext(),
      PREFERENCES_NAME
    );
    store.putSync(STATE_KEY, JSON.stringify(normalized));
    await store.flush();
  }

  projectSnapshot(
    snapshot: AiraSyncSnapshot,
    history: AiraBookmarkHistoryDescriptor
  ): AiraBookmarkHistorySnapshotProjection {
    const normalizedHistory = this.validateHistory(history, '书签墓碑历史纪元');
    const retainedFromMs = this.parseRetainedFrom(normalizedHistory);
    const shared = this.projectDataSet(snapshot, retainedFromMs);
    const privateProjection = snapshot.appPrivateBookmarks === undefined
      ? undefined
      : this.projectDataSet(snapshot.appPrivateBookmarks, retainedFromMs);
    const projectedSnapshot: AiraSyncSnapshot = {
      meta: snapshot.meta,
      bookmarkFolders: snapshot.bookmarkFolders,
      bookmarkItems: snapshot.bookmarkItems,
      bookmarkOrders: snapshot.bookmarkOrders,
      tombstones: shared.dataSet.tombstones
    };
    if (privateProjection !== undefined) {
      const privateDataSet: AiraSyncBookmarkDataSet = {
        bookmarkFolders: snapshot.appPrivateBookmarks?.bookmarkFolders ?? [],
        bookmarkItems: snapshot.appPrivateBookmarks?.bookmarkItems ?? [],
        bookmarkOrders: snapshot.appPrivateBookmarks?.bookmarkOrders ?? [],
        tombstones: privateProjection.dataSet.tombstones
      };
      projectedSnapshot.appPrivateBookmarks = privateDataSet;
    }
    const result: AiraBookmarkHistorySnapshotProjection = {
      snapshot: projectedSnapshot,
      retiredTombstoneCount: shared.retiredTombstoneCount +
        (privateProjection?.retiredTombstoneCount ?? 0)
    };
    return result;
  }

  assertSnapshotWithinHistory(
    snapshot: AiraSyncSnapshot,
    history: AiraBookmarkHistoryDescriptor,
    sourceLabel: string
  ): void {
    const normalized = this.validateHistory(history, `${sourceLabel}书签墓碑历史纪元`);
    const retainedFromMs = this.parseRetainedFrom(normalized);
    if (this.dataSetHasTombstoneBefore(snapshot, retainedFromMs) ||
      (snapshot.appPrivateBookmarks !== undefined &&
        this.dataSetHasTombstoneBefore(snapshot.appPrivateBookmarks, retainedFromMs))) {
      throw new Error(`${sourceLabel}书签快照包含已超出保留边界的墓碑。`);
    }
  }

  validateHistory(
    value: AiraBookmarkHistoryDescriptor,
    sourceLabel: string = '书签墓碑历史纪元'
  ): AiraBookmarkHistoryDescriptor {
    if (!this.isValidHistory(value)) {
      throw new Error(`${sourceLabel}无效。`);
    }
    return {
      version: value.version,
      epochId: value.epochId.trim(),
      retainedFrom: new Date(Date.parse(value.retainedFrom)).toISOString()
    };
  }

  sameHistory(left: AiraBookmarkHistoryDescriptor, right: AiraBookmarkHistoryDescriptor): boolean {
    return left.version === right.version && left.epochId.trim() === right.epochId.trim() &&
      Date.parse(left.retainedFrom) === Date.parse(right.retainedFrom);
  }

  private projectDataSet(
    dataSet: AiraSyncBookmarkDataSet | AiraSyncSnapshot,
    retainedFromMs: number
  ): AiraBookmarkHistoryDataSetProjection {
    const retainedTombstones: AiraSyncTombstone[] = [];
    dataSet.tombstones.forEach((tombstone: AiraSyncTombstone): void => {
      const deletedAtMs = Date.parse(tombstone.deletedAt);
      if (Number.isFinite(deletedAtMs) && deletedAtMs >= retainedFromMs) {
        retainedTombstones.push(tombstone);
      }
    });
    const projectedDataSet: AiraSyncBookmarkDataSet = {
      bookmarkFolders: dataSet.bookmarkFolders,
      bookmarkItems: dataSet.bookmarkItems,
      bookmarkOrders: dataSet.bookmarkOrders,
      tombstones: retainedTombstones
    };
    const result: AiraBookmarkHistoryDataSetProjection = {
      dataSet: projectedDataSet,
      retiredTombstoneCount: dataSet.tombstones.length - retainedTombstones.length
    };
    return result;
  }

  private hasTombstoneBefore(
    cutoffMs: number,
    first: AiraSyncSnapshot | null,
    second: AiraSyncSnapshot | null,
    third: AiraSyncSnapshot | null
  ): boolean {
    const snapshots: Array<AiraSyncSnapshot | null> = [first, second, third];
    return snapshots.some((snapshot: AiraSyncSnapshot | null): boolean => {
      if (snapshot === null) {
        return false;
      }
      return this.dataSetHasTombstoneBefore(snapshot, cutoffMs) ||
        (snapshot.appPrivateBookmarks !== undefined &&
          this.dataSetHasTombstoneBefore(snapshot.appPrivateBookmarks, cutoffMs));
    });
  }

  private dataSetHasTombstoneBefore(
    dataSet: AiraSyncBookmarkDataSet | AiraSyncSnapshot,
    cutoffMs: number
  ): boolean {
    return dataSet.tombstones.some((tombstone: AiraSyncTombstone): boolean => {
      const deletedAtMs = Date.parse(tombstone.deletedAt);
      return Number.isFinite(deletedAtMs) && deletedAtMs < cutoffMs;
    });
  }

  selectNewerHistory(
    left: AiraBookmarkHistoryDescriptor,
    right: AiraBookmarkHistoryDescriptor
  ): AiraBookmarkHistoryDescriptor {
    const normalizedLeft = this.validateHistory(left);
    const normalizedRight = this.validateHistory(right, '远端书签墓碑历史纪元');
    const leftRetainedFrom = this.parseRetainedFrom(normalizedLeft);
    const rightRetainedFrom = this.parseRetainedFrom(normalizedRight);
    if (rightRetainedFrom !== leftRetainedFrom) {
      return rightRetainedFrom > leftRetainedFrom ? normalizedRight : normalizedLeft;
    }
    return normalizedRight.epochId.localeCompare(normalizedLeft.epochId) > 0
      ? normalizedRight
      : normalizedLeft;
  }

  private createAdvancedHistory(retainedFromMs: number, deviceId: string): AiraBookmarkHistoryDescriptor {
    const normalizedDeviceId = deviceId.trim().replace(/[^a-zA-Z0-9_-]+/g, '_').slice(0, 48) || 'device';
    const normalizedRetainedFromMs = Math.max(0, Math.floor(retainedFromMs));
    return {
      version: AIRA_BOOKMARK_HISTORY_VERSION,
      epochId: `bookmark-history-v1-${normalizedRetainedFromMs.toString(36)}-${normalizedDeviceId}`,
      retainedFrom: new Date(normalizedRetainedFromMs).toISOString()
    };
  }

  private originHistory(): AiraBookmarkHistoryDescriptor {
    return {
      version: AIRA_BOOKMARK_HISTORY_VERSION,
      epochId: ORIGIN_EPOCH_ID,
      retainedFrom: ORIGIN_RETAINED_FROM
    };
  }

  private isValidHistory(value: AiraBookmarkHistoryDescriptor): boolean {
    return value !== undefined && value !== null && typeof value === 'object' &&
      value.version === AIRA_BOOKMARK_HISTORY_VERSION &&
      typeof value.epochId === 'string' && value.epochId.trim().length > 0 &&
      typeof value.retainedFrom === 'string' && Number.isFinite(Date.parse(value.retainedFrom));
  }

  private parseRetainedFrom(history: AiraBookmarkHistoryDescriptor): number {
    const parsed = Date.parse(history.retainedFrom);
    if (!Number.isFinite(parsed)) {
      throw new Error('书签墓碑保留边界无效。');
    }
    return parsed;
  }
}
