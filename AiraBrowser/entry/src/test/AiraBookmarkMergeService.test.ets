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
  appPrivateBookmarks?: AiraSyncBookmarkDataSet
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
    updatedBy: deviceId,
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
  });
}
