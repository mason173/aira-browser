import { describe, expect, it } from '@ohos/hypium';
import {
  AiraSyncBookmarkFolderEntity,
  AiraSyncBookmarkDataSet,
  AiraSyncBookmarkItemEntity,
  AiraSyncBookmarkOrder,
  AiraSyncSnapshot,
  AiraSyncTombstone
} from '../main/ets/common/models/AiraSyncModels';
import { AiraBookmarkMergeService } from '../main/ets/services/sync/AiraBookmarkMergeService';
import { AiraBookmarkSnapshotValidationService } from
  '../main/ets/services/sync/AiraBookmarkSnapshotValidationService';
import { AiraSyncWorkThrottleService } from '../main/ets/services/sync/AiraSyncWorkThrottleService';

const T0: string = '2026-08-04T00:00:00.000Z';
const ROOT_ID: string = 'browser_root_toolbar';
const PRIVATE_ROOT_ID: string = 'aira_private_root_toolbar';
const COLLIDING_ID: string = 'cross-type-id';

function createSnapshot(
  deviceId: string,
  includeLiveItem: boolean = false,
  includeFolderTombstone: boolean = false,
  includeItemTombstone: boolean = false,
  appPrivateBookmarks?: AiraSyncBookmarkDataSet,
  liveItemUpdatedBy?: string
): AiraSyncSnapshot {
  const folders: AiraSyncBookmarkFolderEntity[] = [{
    id: ROOT_ID,
    type: 'bookmark-folder',
    parentId: null,
    title: 'Root',
    createdAt: T0,
    updatedAt: T0,
    updatedBy: deviceId,
    revision: 1
  }];
  const items: AiraSyncBookmarkItemEntity[] = includeLiveItem ? [{
    id: COLLIDING_ID,
    type: 'bookmark-item',
    parentId: ROOT_ID,
    title: 'Live item',
    url: 'https://example.com/live',
    createdAt: T0,
    updatedAt: T0,
    updatedBy: liveItemUpdatedBy ?? deviceId,
    revision: 1
  }] : [];
  const orders: AiraSyncBookmarkOrder[] = [{
    type: 'bookmark-order',
    parentId: null,
    ids: [ROOT_ID],
    updatedAt: T0,
    updatedBy: deviceId,
    revision: 1
  }, {
    type: 'bookmark-order',
    parentId: ROOT_ID,
    ids: includeLiveItem ? [COLLIDING_ID] : [],
    updatedAt: T0,
    updatedBy: deviceId,
    revision: includeLiveItem ? 2 : 1
  }];
  const tombstones: AiraSyncTombstone[] = includeFolderTombstone || includeItemTombstone ? [{
    id: COLLIDING_ID,
    type: includeItemTombstone ? 'bookmark-item' : 'bookmark-folder',
    deletedAt: T0,
    deletedBy: deviceId,
    lastKnownRevision: 1
  }] : [];
  return {
    meta: { version: 2, deviceId: deviceId, generatedAt: T0 },
    bookmarkFolders: folders,
    bookmarkItems: items,
    bookmarkOrders: orders,
    tombstones: tombstones,
    appPrivateBookmarks: appPrivateBookmarks
  };
}

function createPrivateDataSet(
  deviceId: string,
  includeLiveItem: boolean = false,
  includeFolderTombstone: boolean = false
): AiraSyncBookmarkDataSet {
  return {
    bookmarkFolders: [{
      id: PRIVATE_ROOT_ID,
      type: 'bookmark-folder',
      parentId: null,
      title: 'Private root',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1
    }],
    bookmarkItems: includeLiveItem ? [{
      id: COLLIDING_ID,
      type: 'bookmark-item',
      parentId: PRIVATE_ROOT_ID,
      title: 'Private live item',
      url: 'https://example.com/private-live',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1
    }] : [],
    bookmarkOrders: [{
      type: 'bookmark-order',
      parentId: null,
      ids: [PRIVATE_ROOT_ID],
      updatedAt: T0,
      updatedBy: deviceId,
      revision: 1
    }, {
      type: 'bookmark-order',
      parentId: PRIVATE_ROOT_ID,
      ids: includeLiveItem ? [COLLIDING_ID] : [],
      updatedAt: T0,
      updatedBy: deviceId,
      revision: includeLiveItem ? 2 : 1
    }],
    tombstones: includeFolderTombstone ? [{
      id: COLLIDING_ID,
      type: 'bookmark-folder',
      deletedAt: T0,
      deletedBy: deviceId,
      lastKnownRevision: 1
    }] : []
  };
}

export default function airaBookmarkMergeServiceTest(): void {
  describe('AiraBookmarkMergeService', () => {
    it('keeps a canonical result when a live entity meets an opposite-type tombstone with the same ID', 0, () => {
      const baseline = createSnapshot('baseline');
      const local = createSnapshot('phone-a', true, false);
      const remote = createSnapshot('desktop-a', false, true);
      const result = new AiraBookmarkMergeService().merge(baseline, local, remote, 'phone-a');

      expect(result.snapshot.bookmarkItems.length).assertEqual(1);
      expect(result.snapshot.tombstones.length).assertEqual(0);
      expect(new AiraBookmarkSnapshotValidationService().validate(result.snapshot, '合并后')).assertEqual(
        result.snapshot
      );
    });

    it('keeps the App-private partition canonical for the same opposite-type collision', 0, () => {
      const baseline = createSnapshot('baseline', false, false, false, createPrivateDataSet('baseline'));
      const local = createSnapshot(
        'phone-a',
        false,
        false,
        false,
        createPrivateDataSet('phone-a', true, false)
      );
      const remote = createSnapshot(
        'desktop-a',
        false,
        false,
        false,
        createPrivateDataSet('desktop-a', false, true)
      );
      const result = new AiraBookmarkMergeService().merge(baseline, local, remote, 'phone-a');
      const privateDataSet = result.snapshot.appPrivateBookmarks as AiraSyncBookmarkDataSet;

      expect(privateDataSet.bookmarkItems.length).assertEqual(1);
      expect(privateDataSet.tombstones.length).assertEqual(0);
      expect(new AiraBookmarkSnapshotValidationService().validate(result.snapshot, '合并后')).assertEqual(
        result.snapshot
      );
    });

    it('keeps the cooperative merge path canonical for an opposite-type collision', 0, async () => {
      const baseline = createSnapshot('baseline');
      const local = createSnapshot('phone-a', true, false);
      const remote = createSnapshot('desktop-a', false, true);
      const result = await new AiraBookmarkMergeService().mergeCooperatively(
        baseline,
        local,
        remote,
        new AiraSyncWorkThrottleService(),
        'phone-a'
      );

      expect(result.snapshot.bookmarkItems.length).assertEqual(1);
      expect(result.snapshot.tombstones.length).assertEqual(0);
      expect(new AiraBookmarkSnapshotValidationService().validate(result.snapshot, '合并后')).assertEqual(
        result.snapshot
      );
    });

    it('preserves a live item and its parent order against a Provider-switch tombstone', 0, () => {
      const baseline = createSnapshot('baseline', true, false);
      const local = createSnapshot('phone-a', true, false);
      const remote = createSnapshot('desktop-a', false, false, true);
      const result = new AiraBookmarkMergeService().merge(
        baseline,
        local,
        remote,
        'phone-a',
        undefined,
        'preserve-live-on-provider-switch'
      );
      const parentOrder = result.snapshot.bookmarkOrders.find((order: AiraSyncBookmarkOrder): boolean => {
        return order.parentId === ROOT_ID;
      });

      expect(result.snapshot.bookmarkItems.length).assertEqual(1);
      expect(result.snapshot.bookmarkItems[0].id).assertEqual(COLLIDING_ID);
      expect(result.snapshot.tombstones.length).assertEqual(0);
      expect(parentOrder?.ids.length).assertEqual(1);
      expect(parentOrder?.ids[0]).assertEqual(COLLIDING_ID);
      expect(new AiraBookmarkSnapshotValidationService().validate(result.snapshot, '合并后')).assertEqual(
        result.snapshot
      );
    });

    it('still propagates an ordinary same-type deletion', 0, () => {
      const baseline = createSnapshot('baseline', true, false);
      const local = createSnapshot('phone-a', true, false);
      const remote = createSnapshot('desktop-a', false, false, true);
      const result = new AiraBookmarkMergeService().merge(baseline, local, remote, 'phone-a');

      expect(result.snapshot.bookmarkItems.length).assertEqual(0);
      expect(result.snapshot.tombstones.length).assertEqual(1);
      expect(result.snapshot.tombstones[0].type).assertEqual('bookmark-item');
      expect(new AiraBookmarkSnapshotValidationService().validate(result.snapshot, '合并后')).assertEqual(
        result.snapshot
      );
    });

    it('preserves a restored local addition when remote carries a tombstone for an ID absent from baseline', 0, () => {
      const baseline = createSnapshot('baseline', false, false);
      const local = createSnapshot('phone-a', true, false, false, undefined, 'local-backup-import');
      const remote = createSnapshot('desktop-a', false, false, true);
      const result = new AiraBookmarkMergeService().merge(baseline, local, remote, 'phone-a');

      expect(result.snapshot.bookmarkItems.length).assertEqual(1);
      expect(result.snapshot.bookmarkItems[0].id).assertEqual(COLLIDING_ID);
      expect(result.snapshot.tombstones.length).assertEqual(0);
      expect(result.remoteWriteRequired).assertTrue();
      expect(new AiraBookmarkSnapshotValidationService().validate(result.snapshot, '合并后')).assertEqual(
        result.snapshot
      );
    });

    it('preserves a restored local entity when its prior baseline version was live', 0, () => {
      const baseline = createSnapshot('baseline', true, false);
      const local = createSnapshot('phone-a', true, false, false, undefined, 'local-backup-import');
      const remote = createSnapshot('desktop-a', false, false, true);
      const result = new AiraBookmarkMergeService().merge(baseline, local, remote, 'phone-a');

      expect(result.snapshot.bookmarkItems.length).assertEqual(1);
      expect(result.snapshot.tombstones.length).assertEqual(0);
      expect(result.remoteWriteRequired).assertTrue();
      expect(new AiraBookmarkSnapshotValidationService().validate(result.snapshot, '合并后')).assertEqual(
        result.snapshot
      );
    });

    it('preserves changed restored content before remote tombstone conflict detection', 0, () => {
      const baseline = createSnapshot('baseline', true, false, false, undefined, 'local-backup-import-1');
      const local = createSnapshot('phone-a', true, false, false, undefined, 'local-backup-import-2');
      local.bookmarkItems[0].title = 'Restored title';
      local.bookmarkItems[0].url = 'https://example.com/restored';
      const remote = createSnapshot('desktop-a', false, false, true);
      const result = new AiraBookmarkMergeService().merge(baseline, local, remote, 'phone-a');

      expect(result.hasConflicts).assertFalse();
      expect(result.snapshot.bookmarkItems.length).assertEqual(1);
      expect(result.snapshot.bookmarkItems[0].title).assertEqual('Restored title');
      expect(result.snapshot.bookmarkItems[0].url).assertEqual('https://example.com/restored');
      expect(result.snapshot.tombstones.length).assertEqual(0);
      expect(result.remoteWriteRequired).assertTrue();
    });

    it('preserves a cooperative restored local addition against a remote tombstone absent from baseline', 0, async () => {
      const baseline = createSnapshot('baseline', false, false);
      const local = createSnapshot('phone-a', true, false, false, undefined, 'local-backup-import');
      const remote = createSnapshot('desktop-a', false, false, true);
      const result = await new AiraBookmarkMergeService().mergeCooperatively(
        baseline,
        local,
        remote,
        new AiraSyncWorkThrottleService(),
        'phone-a'
      );

      expect(result.snapshot.bookmarkItems.length).assertEqual(1);
      expect(result.snapshot.bookmarkItems[0].id).assertEqual(COLLIDING_ID);
      expect(result.snapshot.tombstones.length).assertEqual(0);
      expect(result.remoteWriteRequired).assertTrue();
      expect(new AiraBookmarkSnapshotValidationService().validate(result.snapshot, '合并后')).assertEqual(
        result.snapshot
      );
    });

    it('resumes ordinary tombstone propagation after a restore is recorded in the baseline', 0, () => {
      const baseline = createSnapshot('baseline', true, false, false, undefined, 'local-backup-import-1');
      const local = createSnapshot('phone-a', true, false, false, undefined, 'local-backup-import-1');
      const remote = createSnapshot('desktop-a', false, false, true);
      const result = new AiraBookmarkMergeService().merge(baseline, local, remote, 'phone-a');

      expect(result.snapshot.bookmarkItems.length).assertEqual(0);
      expect(result.snapshot.tombstones.length).assertEqual(1);
      expect(result.snapshot.tombstones[0].type).assertEqual('bookmark-item');
    });

    it('treats a later backup import as a new restore intent', 0, () => {
      const baseline = createSnapshot('baseline', true, false, false, undefined, 'local-backup-import-1');
      const local = createSnapshot('phone-a', true, false, false, undefined, 'local-backup-import-2');
      const remote = createSnapshot('desktop-a', false, false, true);
      const result = new AiraBookmarkMergeService().merge(baseline, local, remote, 'phone-a');

      expect(result.snapshot.bookmarkItems.length).assertEqual(1);
      expect(result.snapshot.bookmarkItems[0].id).assertEqual(COLLIDING_ID);
      expect(result.snapshot.tombstones.length).assertEqual(0);
      expect(result.remoteWriteRequired).assertTrue();
    });

    it('still propagates a remote tombstone for an ordinary new local entity', 0, () => {
      const baseline = createSnapshot('baseline', false, false);
      const local = createSnapshot('phone-a', true, false);
      const remote = createSnapshot('desktop-a', false, false, true);
      const result = new AiraBookmarkMergeService().merge(baseline, local, remote, 'phone-a');

      expect(result.snapshot.bookmarkItems.length).assertEqual(0);
      expect(result.snapshot.tombstones.length).assertEqual(1);
      expect(result.snapshot.tombstones[0].type).assertEqual('bookmark-item');
      expect(new AiraBookmarkSnapshotValidationService().validate(result.snapshot, '合并后')).assertEqual(
        result.snapshot
      );
    });
  });
}
