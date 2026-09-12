import { describe, expect, it } from '@ohos/hypium';
import {
  HistorySyncVisit,
  HuaweiSpaceHistorySyncState
} from '../main/ets/common/models/HistorySyncModels';
import {
  AiraSyncBookmarkItemEntity,
  AiraSyncSnapshot
} from '../main/ets/common/models/AiraSyncModels';
import { AiraBookmarkMergeService } from '../main/ets/services/sync/AiraBookmarkMergeService';
import { AiraBookmarkIdentityNoOpService } from '../main/ets/services/sync/AiraBookmarkIdentityNoOpService';
import { AiraHistoryTaskpoolTransferCodec } from '../main/ets/services/sync/AiraHistoryTaskpoolTransferCodec';
import { HistorySyncMergeService } from '../main/ets/services/sync/HistorySyncMergeService';
import {
  hasHuaweiHistoryLocalWork,
  resolveHuaweiHistoryRemoteReadPlan
} from '../main/ets/services/sync/HuaweiSpaceHistorySyncRunner';
import { PersonalizationSyncCollectionMergeService } from
  '../main/ets/services/sync/PersonalizationSyncCollectionMergeService';
import { HuaweiSpaceHistoryRow, HuaweiSpaceHistorySnapshotCodec } from
  '../main/ets/data/sync/HuaweiSpaceHistorySnapshotCodec';

const NOW: number = Date.now();
const ROOT_ID: string = 'browser_root_toolbar';
const ITEM_ID: string = 'closed-loop-item';

function historyVisit(nativeId: string, url: string, visitedAt: number): HistorySyncVisit {
  const clientId = 'phone-a';
  return {
    visitId: `h1:${clientId}:${nativeId}`,
    clientId: clientId,
    nativeVisitId: nativeId,
    url: url,
    title: nativeId,
    visitedAt: visitedAt,
    transition: 'link',
    referrer: '',
    deviceName: 'phone-a',
    source: 'local'
  };
}

function historyState(
  visits: HistorySyncVisit[],
  tombstones: { visitId: string, deletedAt: number }[] = []
): HuaweiSpaceHistorySyncState {
  return {
    visits: visits,
    tombstones: tombstones,
    deleteRanges: [],
    clearBefore: 0,
    retentionFrontier: {
      cutoffAt: 0,
      boundaryVisitedAt: 0,
      boundaryVisitId: '',
      updatedAt: 0
    }
  };
}

function bookmarkSnapshot(deviceId: string, includeItem: boolean, includeTombstone: boolean): AiraSyncSnapshot {
  const items: AiraSyncBookmarkItemEntity[] = includeItem ? [{
    id: ITEM_ID,
    type: 'bookmark-item',
    parentId: ROOT_ID,
    title: 'Closed loop',
    url: 'https://example.com/loop',
    createdAt: '2026-08-04T00:00:00.000Z',
    updatedAt: '2026-08-04T00:00:00.000Z',
    updatedBy: deviceId,
    revision: 1
  }] : [];
  return {
    meta: { version: 2, deviceId: deviceId, generatedAt: '2026-08-04T00:00:00.000Z' },
    bookmarkFolders: [{
      id: ROOT_ID,
      type: 'bookmark-folder',
      parentId: null,
      title: 'Root',
      createdAt: '2026-08-04T00:00:00.000Z',
      updatedAt: '2026-08-04T00:00:00.000Z',
      updatedBy: deviceId,
      revision: 1
    }],
    bookmarkItems: items,
    bookmarkOrders: [{
      type: 'bookmark-order',
      parentId: null,
      ids: [ROOT_ID],
      updatedAt: '2026-08-04T00:00:00.000Z',
      updatedBy: deviceId,
      revision: 1
    }, {
      type: 'bookmark-order',
      parentId: ROOT_ID,
      ids: includeItem ? [ITEM_ID] : [],
      updatedAt: '2026-08-04T00:00:00.000Z',
      updatedBy: deviceId,
      revision: includeItem ? 2 : 1
    }],
    tombstones: includeTombstone ? [{
      id: ITEM_ID,
      type: 'bookmark-item',
      deletedAt: '2026-08-04T00:00:00.000Z',
      deletedBy: deviceId,
      lastKnownRevision: 1
    }] : []
  };
}

export default function airaSyncClosedLoopTest(): void {
  describe('Aira sync closed loop', () => {
    const historyMerge = new HistorySyncMergeService();
    const bookmarkMerge = new AiraBookmarkMergeService();
    const bookmarkNoOp = new AiraBookmarkIdentityNoOpService();
    const personalizationMerge = new PersonalizationSyncCollectionMergeService();

    it('dirties only the visit and tombstone buckets for one History delete', 0, () => {
      const codec = new HuaweiSpaceHistorySnapshotCodec('uid-a', 'phone-a');
      const local = historyState(
        [historyVisit('keep-1', 'https://example.com/keep', NOW - 2000)],
        [{ visitId: 'h1:phone-a:del-1', deletedAt: NOW }]
      );
      const dirty = codec.collectDirtyBucketIndexes(local, NOW - 1000, [], false);
      expect(dirty === undefined).assertFalse();
      const bucketCount = dirty === undefined ? 0 : dirty.length;
      expect(bucketCount > 0).assertTrue();
      expect(bucketCount <= 2).assertTrue();
    });

    it('plans History skip, replica, and cloud without confusing stale tombstones', 0, () => {
      expect(hasHuaweiHistoryLocalWork(0, false, true, false)).assertFalse();
      expect(hasHuaweiHistoryLocalWork(0, false, true, true)).assertTrue();
      expect(resolveHuaweiHistoryRemoteReadPlan(false, true, 'abc', false)).assertEqual('skip');
      expect(resolveHuaweiHistoryRemoteReadPlan(false, false, 'new', true)).assertEqual('skip');
      expect(resolveHuaweiHistoryRemoteReadPlan(true, true, 'abc', true)).assertEqual('replica');
      expect(resolveHuaweiHistoryRemoteReadPlan(true, false, 'new', true)).assertEqual('replica');
      expect(resolveHuaweiHistoryRemoteReadPlan(true, false, 'new', false)).assertEqual('cloud');
      expect(resolveHuaweiHistoryRemoteReadPlan(false, false, 'new', false)).assertEqual('cloud');
    });

    it('keeps other-device History visits while uploading a local add', 0, () => {
      const remoteVisit = historyVisit('remote-1', 'https://example.com/other-device', NOW - 1000);
      const localVisit = historyVisit('local-1', 'https://example.com/this-device', NOW);
      const remote = historyState([remoteVisit]);
      const local = historyState([localVisit]);
      const merged = historyMerge.mergeKeepingPreferredVisits(remote, local, NOW);
      expect(merged.visits.length).assertEqual(2);
      expect(historyMerge.sameState(merged, remote)).assertFalse();
      expect(historyMerge.sameState(merged, local)).assertFalse();
    });

    it('uploads a local History deletion without dropping a live remote visit', 0, () => {
      const keep = historyVisit('keep-1', 'https://example.com/keep', NOW - 2000);
      const removed = historyVisit('del-1', 'https://example.com/delete', NOW - 1000);
      const remote = historyState([keep, removed]);
      const local = historyState([keep], [{ visitId: removed.visitId, deletedAt: NOW }]);
      const merged = historyMerge.mergeKeepingPreferredVisits(remote, local, NOW);
      expect(merged.visits.length).assertEqual(1);
      expect(merged.visits[0].visitId).assertEqual(keep.visitId);
      expect(merged.tombstones.length).assertEqual(1);
    });

    it('partitions compact History chunks deterministically and round-trips them', 0, () => {
      const codec = new HuaweiSpaceHistorySnapshotCodec('uid-a', 'phone-a');
      const visits: HistorySyncVisit[] = [];
      const longTitle = 't'.repeat(600);
      for (let index = 0; index < 400; index += 1) {
        const visit = historyVisit(`bulk-${index}`, `https://example.com/bulk/${index}`, NOW - index);
        visit.title = `${longTitle}-${index}`;
        visits.push(visit);
      }
      const state = historyState(visits);
      const mirror = codec.decodeRows([]);
      const first = codec.buildProjection(state, mirror);
      const second = codec.buildProjection(state, mirror);
      const chunkRows = first.rowsToUpsert.filter((row: HuaweiSpaceHistoryRow): boolean => {
        return row.recordKind === 'snapshot_chunk';
      });
      const secondChunkRows = second.rowsToUpsert.filter((row: HuaweiSpaceHistoryRow): boolean => {
        return row.recordKind === 'snapshot_chunk';
      });
      expect(chunkRows.length > 0).assertTrue();
      expect(chunkRows.length).assertEqual(secondChunkRows.length);
      for (let index = 0; index < chunkRows.length; index += 1) {
        expect(chunkRows[index].rowId).assertEqual(secondChunkRows[index].rowId);
        expect(chunkRows[index].data).assertEqual(secondChunkRows[index].data);
      }
      const decoded = codec.decodeRows(first.rowsToUpsert);
      expect(decoded.selectedHeads.length).assertEqual(1);
      expect(decoded.state.visits.length).assertEqual(visits.length);
    });

    it('reuses unchanged dirty buckets when the lite projection is built', 0, () => {
      const codec = new HuaweiSpaceHistorySnapshotCodec('uid-a', 'phone-a');
      const visits: HistorySyncVisit[] = [];
      for (let index = 0; index < 200; index += 1) {
        visits.push(historyVisit(`lite-${index}`, `https://example.com/lite/${index}`, NOW - index * 1000));
      }
      const state = historyState(visits);
      const initial = codec.buildProjection(state, codec.decodeRows([]));
      const initialChunks = initial.rowsToUpsert.filter((row: HuaweiSpaceHistoryRow): boolean => {
        return row.recordKind === 'snapshot_chunk';
      });
      expect(initialChunks.length > 0).assertTrue();

      const decoded = codec.decodeRows(initial.rowsToUpsert);
      const allBuckets: number[] = [];
      for (let index = 0; index < 64; index += 1) {
        allBuckets.push(index);
      }
      const unchangedLite = codec.buildProjectionReusingHead(state, initial.rowsToUpsert, allBuckets);
      const unchangedChunks = unchangedLite.rowsToUpsert.filter((row: HuaweiSpaceHistoryRow): boolean => {
        return row.recordKind === 'snapshot_chunk';
      });
      expect(unchangedChunks.length).assertEqual(0);
      expect(unchangedLite.rowIdsToDeleteBeforePublish.length).assertEqual(0);

      const deleted = visits[0];
      const nextState = historyState(
        visits.slice(1),
        [{ visitId: deleted.visitId, deletedAt: NOW + 1000 }]
      );
      const dirty = codec.collectDirtyBucketIndexes(nextState, NOW + 500, [], false);
      expect(dirty === undefined).assertFalse();
      const dirtyBuckets = dirty === undefined ? [] : dirty;
      expect(dirtyBuckets.length > 0).assertTrue();
      const lite = codec.buildProjectionReusingHead(nextState, initial.rowsToUpsert, dirtyBuckets);
      const liteChunks = lite.rowsToUpsert.filter((row: HuaweiSpaceHistoryRow): boolean => {
        return row.recordKind === 'snapshot_chunk';
      });
      expect(liteChunks.length > 0).assertTrue();
      expect(liteChunks.length < initialChunks.length).assertTrue();
      const deletedRowIds = new Set<string>(lite.rowIdsToDeleteBeforePublish);
      const mergedRows = initial.rowsToUpsert
        .filter((row: HuaweiSpaceHistoryRow): boolean => !deletedRowIds.has(row.rowId))
        .concat(lite.rowsToUpsert);
      const liteDecoded = codec.decodeRows(mergedRows);
      expect(liteDecoded.selectedHeads.length).assertEqual(1);
      expect(liteDecoded.state.visits.length).assertEqual(visits.length - 1);
      expect(liteDecoded.state.tombstones.length).assertEqual(1);
      expect(decoded.selectedHeads.length).assertEqual(1);
    });

    it('detects an incomplete compact replica when a Head references missing Buckets', 0, () => {
      const codec = new HuaweiSpaceHistorySnapshotCodec('uid-a', 'phone-a');
      const visits: HistorySyncVisit[] = [];
      for (let index = 0; index < 120; index += 1) {
        visits.push(historyVisit(`repair-${index}`, `https://example.com/repair/${index}`, NOW - index));
      }
      const projection = codec.buildProjection(historyState(visits), codec.decodeRows([]));
      const headRow = projection.rowsToUpsert.find((row: HuaweiSpaceHistoryRow): boolean => {
        return row.recordKind === 'snapshot_head';
      });
      const bucketRows = projection.rowsToUpsert.filter((row: HuaweiSpaceHistoryRow): boolean => {
        return row.recordKind === 'snapshot_bucket';
      });
      const chunkRows = projection.rowsToUpsert.filter((row: HuaweiSpaceHistoryRow): boolean => {
        return row.recordKind === 'snapshot_chunk';
      });
      expect(headRow === undefined).assertFalse();
      expect(codec.needsBlockCloudSync(projection.rowsToUpsert)).assertFalse();
      const headOnly = headRow === undefined ? [] : [headRow];
      expect(codec.needsBlockCloudSync(headOnly)).assertTrue();
      expect(codec.needsBlockCloudSync(headOnly.concat(chunkRows))).assertTrue();
      const missingOneBucket = headOnly
        .concat(bucketRows.slice(0, bucketRows.length - 1))
        .concat(chunkRows);
      expect(codec.needsBlockCloudSync(missingOneBucket)).assertTrue();
      expect(codec.needsBlockCloudSync([])).assertFalse();
    });

    it('round-trips History state and rows through the TaskPool codec', 0, () => {
      const state = historyState([historyVisit('codec-1', 'https://example.com/codec', NOW)]);
      const decodedState = AiraHistoryTaskpoolTransferCodec.decodeState(
        AiraHistoryTaskpoolTransferCodec.encodeState(state)
      );
      expect(historyMerge.sameState(decodedState, state)).assertTrue();
      const rows: HuaweiSpaceHistoryRow[] = [{
        rowId: 'row-1',
        recordKind: 'snapshot_head',
        logicalId: 'head-1',
        data: '{"stateChecksum":"abc"}',
        updatedAt: NOW
      }];
      const decodedRows = AiraHistoryTaskpoolTransferCodec.decodeRows(
        AiraHistoryTaskpoolTransferCodec.encodeRows(rows)
      );
      expect(decodedRows.length).assertEqual(1);
      expect(decodedRows[0].rowId).assertEqual('row-1');
    });

    it('reuses Bookmark baseline when Head matches a pending local delete', 0, () => {
      const probe = {
        remoteKind: 'huawei_space',
        intent: 'merge',
        conservativeMerge: false,
        pendingBookmarkSyncAt: 42,
        baselineCommitId: 'cmt-1',
        baselineFolderCount: 3,
        baselineItemCount: 12,
        hasBaselineSnapshot: true,
        baselineHasExpiredTombstone: false
      };
      expect(bookmarkNoOp.isEligible(probe)).assertFalse();
      expect(bookmarkNoOp.matchesConfirmedHead(probe, {
        commitId: 'cmt-1',
        updatedAt: 1,
        bookmarkFolders: 3,
        bookmarkItems: 11,
        hasBookmarkSummary: true
      })).assertTrue();
    });

    it('no-ops unchanged Huawei Bookmark Heads even when summary counts drift', 0, () => {
      const probe = {
        remoteKind: 'huawei_space',
        intent: 'merge',
        conservativeMerge: false,
        pendingBookmarkSyncAt: 0,
        baselineCommitId: 'cmt-1',
        baselineFolderCount: 3,
        baselineItemCount: 12,
        hasBaselineSnapshot: true,
        baselineHasExpiredTombstone: false
      };
      expect(bookmarkNoOp.isEligible(probe)).assertTrue();
      expect(bookmarkNoOp.matchesConfirmedHead(probe, {
        commitId: 'cmt-1',
        updatedAt: 1,
        bookmarkFolders: 9,
        bookmarkItems: 1,
        hasBookmarkSummary: true
      })).assertTrue();
      expect(bookmarkNoOp.matchesConfirmedHead(probe, {
        commitId: 'cmt-other',
        updatedAt: 1,
        bookmarkFolders: 9,
        bookmarkItems: 1,
        hasBookmarkSummary: true
      })).assertFalse();
    });

    it('merges Bookmark add, other-device add, and local delete', 0, () => {
      const baseline = bookmarkSnapshot('baseline', false, false);
      const localAdd = bookmarkSnapshot('phone-a', true, false);
      const emptyRemote = bookmarkSnapshot('desktop-a', false, false);
      const added = bookmarkMerge.merge(baseline, localAdd, emptyRemote, 'phone-a');
      expect(added.snapshot.bookmarkItems.length).assertEqual(1);
      expect(added.remoteWriteRequired).assertTrue();

      const remoteAdd = bookmarkSnapshot('desktop-a', true, false);
      const localEmpty = bookmarkSnapshot('phone-a', false, false);
      const pulled = bookmarkMerge.merge(baseline, localEmpty, remoteAdd, 'phone-a');
      expect(pulled.snapshot.bookmarkItems.length).assertEqual(1);
      expect(pulled.localApplyRequired).assertTrue();

      const localLive = bookmarkSnapshot('phone-a', true, false);
      const remoteDeleted = bookmarkSnapshot('desktop-a', false, true);
      const deleted = bookmarkMerge.merge(
        bookmarkSnapshot('baseline', true, false),
        localLive,
        remoteDeleted,
        'phone-a'
      );
      expect(deleted.snapshot.bookmarkItems.length).assertEqual(0);
      expect(deleted.snapshot.tombstones.length).assertEqual(1);
    });

    it('merges Personalization collection add, remote add, and tombstones', 0, () => {
      const localOnly = personalizationMerge.merge(
        [{ id: 'local', updatedAt: 20 }],
        [],
        [],
        [],
        (item: { id: string, updatedAt: number }): string => item.id,
        (item: { id: string, updatedAt: number }): number => item.updatedAt
      );
      expect(localOnly.items.length).assertEqual(1);
      expect(localOnly.items[0].id).assertEqual('local');

      const remoteOnly = personalizationMerge.merge(
        [],
        [{ id: 'remote', updatedAt: 20 }],
        [],
        [],
        (item: { id: string, updatedAt: number }): string => item.id,
        (item: { id: string, updatedAt: number }): number => item.updatedAt
      );
      expect(remoteOnly.items.length).assertEqual(1);
      expect(remoteOnly.items[0].id).assertEqual('remote');

      const deleted = personalizationMerge.merge(
        [{ id: 'gone', updatedAt: 10 }],
        [{ id: 'gone', updatedAt: 10 }],
        [{ id: 'gone', deletedAt: 30 }],
        [],
        (item: { id: string, updatedAt: number }): string => item.id,
        (item: { id: string, updatedAt: number }): number => item.updatedAt
      );
      expect(deleted.items.length).assertEqual(0);
      expect(deleted.tombstones.length).assertEqual(1);
    });
  });
}
