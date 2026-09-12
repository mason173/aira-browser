import {
  AIRA_SYNC_ROOT_ORDER_KEY,
  AIRA_SYNC_SCHEMA_VERSION,
  AiraBookmarkMergeConflictDetail,
  AiraBookmarkConflictResolution,
  AiraSyncBaseEntity,
  AiraSyncBookmarkDataSet,
  AiraSyncBookmarkFolderEntity,
  AiraSyncBookmarkItemEntity,
  AiraSyncBookmarkOrder,
  AiraSyncSnapshot,
  AiraSyncTombstone
} from '../../common/models/AiraSyncModels';
import { AiraSyncWorkThrottleService } from './AiraSyncWorkThrottleService';

const AIRA_LOCAL_BACKUP_IMPORT_ACTOR: string = 'local-backup-import';
// A backup import is an explicit recovery operation; once its actor is recorded in the baseline,
// later ordinary synchronization resumes normal tombstone propagation.

export interface AiraBookmarkMergeResult {
  snapshot: AiraSyncSnapshot;
  hasConflicts: boolean;
  conflictCount: number;
  localChangeCount: number;
  remoteChangeCount: number;
  localApplyRequired: boolean;
  remoteWriteRequired: boolean;
  conflictDetails: AiraBookmarkMergeConflictDetail[];
  summary: string;
}

export type AiraBookmarkMergeDeletionPolicy =
  | 'propagate'
  | 'preserve-live-on-provider-switch';

export class AiraBookmarkMergeService {
  async mergeCooperatively(
    baseline: AiraSyncSnapshot | null,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot | null,
    throttle: AiraSyncWorkThrottleService,
    deviceId: string = local.meta.deviceId,
    resolution?: AiraBookmarkConflictResolution,
    deletionPolicy: AiraBookmarkMergeDeletionPolicy = 'propagate'
  ): Promise<AiraBookmarkMergeResult> {
    if (remote === null) {
      await throttle.afterStage();
      return {
        snapshot: local,
        hasConflicts: false,
        conflictCount: 0,
        localChangeCount: this.countSnapshotEntities(local),
        remoteChangeCount: 0,
        localApplyRequired: false,
        remoteWriteRequired: true,
        conflictDetails: [],
        summary: '远端为空，使用本地快照作为首次同步结果。'
      };
    }

    if (baseline === null) {
      await throttle.afterStage();
      return this.mergeMissingBaselineSnapshots(local, remote, deviceId);
    }

    const folderMerge = await this.mergeFoldersCooperatively(baseline, local, remote, throttle, resolution);
    const itemMerge = await this.mergeItemsCooperatively(baseline, local, remote, throttle, resolution);
    const tombstoneMerge = await this.mergeTombstonesCooperatively(baseline, local, remote, throttle);
    const deleteEditResolution = this.resolveDeleteEditConflicts(
      baseline,
      local,
      remote,
      resolution,
      deletionPolicy
    );
    const orderMerge = await this.mergeOrdersCooperatively(
      baseline,
      local,
      remote,
      throttle,
      this.buildIgnoredEntityIdSet(deleteEditResolution.ignoredTombstoneKeys)
    );
    const privateMerge = await this.mergePrivateBookmarkDataSetsCooperatively(
      baseline,
      local,
      remote,
      throttle,
      deleteEditResolution.ignoredPrivateTombstoneKeys
    );
    const conflictCount = folderMerge.conflictCount + itemMerge.conflictCount + orderMerge.conflictCount +
      deleteEditResolution.conflictDetails.length;
    const conflictDetails = folderMerge.conflictDetails
      .concat(itemMerge.conflictDetails)
      .concat(orderMerge.conflictDetails)
      .concat(deleteEditResolution.conflictDetails);
    const localChangeCount = folderMerge.localChangeCount + itemMerge.localChangeCount +
      orderMerge.localChangeCount + tombstoneMerge.localChangeCount + privateMerge.localChangeCount;
    const remoteChangeCount = folderMerge.remoteChangeCount + itemMerge.remoteChangeCount +
      orderMerge.remoteChangeCount + tombstoneMerge.remoteChangeCount + privateMerge.remoteChangeCount;
    const generatedAt = new Date().toISOString();
    const resolvedTombstones = tombstoneMerge.values.filter((value: AiraSyncTombstone): boolean => {
      return !deleteEditResolution.ignoredTombstoneKeys.has(`${value.type}|${value.id}`);
    });
    const deletedFolderIds = this.buildDeletedEntityIdSet(resolvedTombstones, 'bookmark-folder');
    const deletedItemIds = this.buildDeletedEntityIdSet(resolvedTombstones, 'bookmark-item');
    const liveFolders = await this.filterLiveFoldersCooperatively(folderMerge.values, deletedFolderIds, throttle);
    const liveItems = await this.filterLiveItemsCooperatively(itemMerge.values, deletedItemIds, throttle);
    const canonicalTombstones = this.filterTombstonesOpposedBySurvivingLiveEntities(
      resolvedTombstones,
      liveFolders,
      liveItems
    );
    const liveEntityIds = await this.collectEntityIdsCooperatively(liveFolders, liveItems, throttle);

    const snapshot: AiraSyncSnapshot = {
      meta: {
        version: AIRA_SYNC_SCHEMA_VERSION,
        deviceId: deviceId,
        generatedAt: generatedAt
      },
      bookmarkFolders: liveFolders,
      bookmarkItems: liveItems,
      bookmarkOrders: await this.filterOrdersByLiveIdsCooperatively(
        orderMerge.values,
        liveFolders,
        liveItems,
        liveEntityIds,
        deviceId,
        generatedAt,
        throttle
      ),
      tombstones: canonicalTombstones,
      appPrivateBookmarks: privateMerge.dataSet
    };

    return {
      snapshot: snapshot,
      hasConflicts: conflictCount > 0,
      conflictCount: conflictCount,
      localChangeCount: localChangeCount,
      remoteChangeCount: remoteChangeCount,
      localApplyRequired: !this.sameLocalMaterializationContent(local, snapshot),
      remoteWriteRequired: !this.sameSnapshotContent(remote, snapshot),
      conflictDetails: conflictDetails,
      summary: conflictCount > 0
        ? `发现 ${conflictCount} 个双向冲突，已阻止自动合并。`
        : `已合并 ${localChangeCount} 个本地变化和 ${remoteChangeCount} 个远端变化。`
    };
  }

  merge(
    baseline: AiraSyncSnapshot | null,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot | null,
    deviceId: string = local.meta.deviceId,
    resolution?: AiraBookmarkConflictResolution,
    deletionPolicy: AiraBookmarkMergeDeletionPolicy = 'propagate'
  ): AiraBookmarkMergeResult {
    if (remote === null) {
      return {
        snapshot: local,
        hasConflicts: false,
        conflictCount: 0,
        localChangeCount: this.countSnapshotEntities(local),
        remoteChangeCount: 0,
        localApplyRequired: false,
        remoteWriteRequired: true,
        conflictDetails: [],
        summary: '远端为空，使用本地快照作为首次同步结果。'
      };
    }

    if (baseline === null) {
      return this.mergeMissingBaselineSnapshots(local, remote, deviceId);
    }

    const folderMerge = this.mergeFolders(baseline, local, remote, resolution);
    const itemMerge = this.mergeItems(baseline, local, remote, resolution);
    const tombstoneMerge = this.mergeTombstones(baseline, local, remote);
    const deleteEditResolution = this.resolveDeleteEditConflicts(
      baseline,
      local,
      remote,
      resolution,
      deletionPolicy
    );
    const orderMerge = this.mergeOrders(
      baseline,
      local,
      remote,
      this.buildIgnoredEntityIdSet(deleteEditResolution.ignoredTombstoneKeys)
    );
    const privateMerge = this.mergePrivateBookmarkDataSets(
      baseline,
      local,
      remote,
      deleteEditResolution.ignoredPrivateTombstoneKeys
    );
    const conflictCount = folderMerge.conflictCount + itemMerge.conflictCount + orderMerge.conflictCount +
      deleteEditResolution.conflictDetails.length;
    const conflictDetails = folderMerge.conflictDetails
      .concat(itemMerge.conflictDetails)
      .concat(orderMerge.conflictDetails)
      .concat(deleteEditResolution.conflictDetails);
    const localChangeCount = folderMerge.localChangeCount + itemMerge.localChangeCount +
      orderMerge.localChangeCount + tombstoneMerge.localChangeCount + privateMerge.localChangeCount;
    const remoteChangeCount = folderMerge.remoteChangeCount + itemMerge.remoteChangeCount +
      orderMerge.remoteChangeCount + tombstoneMerge.remoteChangeCount + privateMerge.remoteChangeCount;
    const generatedAt = new Date().toISOString();
    const resolvedTombstones = tombstoneMerge.values.filter((value: AiraSyncTombstone): boolean => {
      return !deleteEditResolution.ignoredTombstoneKeys.has(`${value.type}|${value.id}`);
    });
    const deletedFolderIds = this.buildDeletedEntityIdSet(resolvedTombstones, 'bookmark-folder');
    const deletedItemIds = this.buildDeletedEntityIdSet(resolvedTombstones, 'bookmark-item');
    const liveFolders = folderMerge.values.filter((folder: AiraSyncBookmarkFolderEntity) => {
      return !deletedFolderIds.has(folder.id);
    });
    const liveItems = itemMerge.values.filter((item: AiraSyncBookmarkItemEntity) => {
      return !deletedItemIds.has(item.id);
    });
    const canonicalTombstones = this.filterTombstonesOpposedBySurvivingLiveEntities(
      resolvedTombstones,
      liveFolders,
      liveItems
    );
    const liveEntityIds = this.collectEntityIds(liveFolders, liveItems);

    const snapshot: AiraSyncSnapshot = {
      meta: {
        version: AIRA_SYNC_SCHEMA_VERSION,
        deviceId: deviceId,
        generatedAt: generatedAt
      },
      bookmarkFolders: liveFolders,
      bookmarkItems: liveItems,
      bookmarkOrders: this.filterOrdersByLiveIds(orderMerge.values, liveFolders, liveItems, liveEntityIds, deviceId, generatedAt),
      tombstones: canonicalTombstones,
      appPrivateBookmarks: privateMerge.dataSet
    };

    return {
      snapshot: snapshot,
      hasConflicts: conflictCount > 0,
      conflictCount: conflictCount,
      localChangeCount: localChangeCount,
      remoteChangeCount: remoteChangeCount,
      localApplyRequired: !this.sameLocalMaterializationContent(local, snapshot),
      remoteWriteRequired: !this.sameSnapshotContent(remote, snapshot),
      conflictDetails: conflictDetails,
      summary: conflictCount > 0
        ? `发现 ${conflictCount} 个双向冲突，已阻止自动合并。`
        : `已合并 ${localChangeCount} 个本地变化和 ${remoteChangeCount} 个远端变化。`
    };
  }

  sameSnapshotContent(left: AiraSyncSnapshot, right: AiraSyncSnapshot): boolean {
    const leftPrivate = this.normalizePrivateBookmarkDataSet(left);
    const rightPrivate = this.normalizePrivateBookmarkDataSet(right);
    return this.sameBookmarkFolders(left.bookmarkFolders, right.bookmarkFolders) &&
      this.sameBookmarkItems(left.bookmarkItems, right.bookmarkItems) &&
      this.sameBookmarkOrders(left.bookmarkOrders, right.bookmarkOrders) &&
      this.sameBookmarkTombstones(left.tombstones, right.tombstones) &&
      this.sameBookmarkFolders(leftPrivate.bookmarkFolders, rightPrivate.bookmarkFolders) &&
      this.sameBookmarkItems(leftPrivate.bookmarkItems, rightPrivate.bookmarkItems) &&
      this.sameBookmarkOrders(leftPrivate.bookmarkOrders, rightPrivate.bookmarkOrders) &&
      this.sameBookmarkTombstones(leftPrivate.tombstones, rightPrivate.tombstones);
  }

  sameVisibleBookmarkContent(left: AiraSyncSnapshot, right: AiraSyncSnapshot): boolean {
    const leftPrivate = this.normalizePrivateBookmarkDataSet(left);
    const rightPrivate = this.normalizePrivateBookmarkDataSet(right);
    return this.sameBookmarkFolders(left.bookmarkFolders, right.bookmarkFolders, false, false) &&
      this.sameBookmarkItems(left.bookmarkItems, right.bookmarkItems, false, false) &&
      this.sameBookmarkOrders(left.bookmarkOrders, right.bookmarkOrders, false) &&
      this.sameBookmarkFolders(leftPrivate.bookmarkFolders, rightPrivate.bookmarkFolders, false, false) &&
      this.sameBookmarkItems(leftPrivate.bookmarkItems, rightPrivate.bookmarkItems, false, false) &&
      this.sameBookmarkOrders(leftPrivate.bookmarkOrders, rightPrivate.bookmarkOrders, false);
  }

  sameLocalMaterializationContent(left: AiraSyncSnapshot, right: AiraSyncSnapshot): boolean {
    const leftPrivate = this.normalizePrivateBookmarkDataSet(left);
    const rightPrivate = this.normalizePrivateBookmarkDataSet(right);
    return this.sameBookmarkFolders(left.bookmarkFolders, right.bookmarkFolders, false, true, false) &&
      this.sameBookmarkItems(left.bookmarkItems, right.bookmarkItems, false, true, false) &&
      this.sameMaterializedBookmarkOrders(left.bookmarkOrders, right.bookmarkOrders) &&
      this.sameBookmarkFolders(
      leftPrivate.bookmarkFolders,
      rightPrivate.bookmarkFolders,
      false,
      true,
      false
    ) && this.sameBookmarkItems(
      leftPrivate.bookmarkItems,
      rightPrivate.bookmarkItems,
      false,
      true,
      false
    ) && this.sameMaterializedBookmarkOrders(leftPrivate.bookmarkOrders, rightPrivate.bookmarkOrders);
  }

  private mergeMissingBaselineSnapshots(
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    deviceId: string
  ): AiraBookmarkMergeResult {
    const localDataSet: AiraSyncBookmarkDataSet = {
      bookmarkFolders: local.bookmarkFolders,
      bookmarkItems: local.bookmarkItems,
      bookmarkOrders: local.bookmarkOrders,
      tombstones: local.tombstones
    };
    const remoteDataSet: AiraSyncBookmarkDataSet = {
      bookmarkFolders: remote.bookmarkFolders,
      bookmarkItems: remote.bookmarkItems,
      bookmarkOrders: remote.bookmarkOrders,
      tombstones: remote.tombstones
    };
    const localPrivateDataSet = this.normalizePrivateBookmarkDataSet(local);
    const remotePrivateDataSet = this.normalizePrivateBookmarkDataSet(remote);
    const missingBaselineGeneratedAt = new Date().toISOString();
    const mergedDataSet = this.mergeMissingBaselineDataSets(
      localDataSet,
      remoteDataSet,
      remote.meta.deviceId || deviceId,
      missingBaselineGeneratedAt
    );
    const snapshot: AiraSyncSnapshot = {
      meta: {
        version: AIRA_SYNC_SCHEMA_VERSION,
        deviceId: deviceId,
        generatedAt: missingBaselineGeneratedAt
      },
      bookmarkFolders: mergedDataSet.bookmarkFolders,
      bookmarkItems: mergedDataSet.bookmarkItems,
      bookmarkOrders: mergedDataSet.bookmarkOrders,
      tombstones: mergedDataSet.tombstones,
      appPrivateBookmarks: this.mergeInitialPrivateBookmarkDataSets(
        local,
        remote,
        remote.meta.deviceId || deviceId,
        missingBaselineGeneratedAt
      )
    };
    return {
      snapshot: snapshot,
      hasConflicts: false,
      conflictCount: 0,
      localChangeCount: this.countInitialDataSetAdditions(remoteDataSet, localDataSet) +
        this.countInitialDataSetAdditions(remotePrivateDataSet, localPrivateDataSet),
      remoteChangeCount: this.countInitialDataSetAdditions(localDataSet, remoteDataSet) +
        this.countInitialDataSetAdditions(localPrivateDataSet, remotePrivateDataSet),
      localApplyRequired: !this.sameLocalMaterializationContent(local, snapshot),
      remoteWriteRequired: !this.sameSnapshotContent(remote, snapshot),
      conflictDetails: [],
      summary: '首次同步已保留本机和云端的全部可见书签；无共享基线的删除记录不会覆盖可见内容。'
    };
  }

  private mergeFolders(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    resolution?: AiraBookmarkConflictResolution
  ): AiraMergeCollectionResult<AiraSyncBookmarkFolderEntity> {
    return this.mergeCollection(
      baseline.bookmarkFolders,
      local.bookmarkFolders,
      remote.bookmarkFolders,
      (value: AiraSyncBookmarkFolderEntity) => value.id,
      (left: AiraSyncBookmarkFolderEntity, right: AiraSyncBookmarkFolderEntity) => {
        return left.title === right.title && left.parentId === right.parentId;
      },
      (value: AiraSyncBookmarkFolderEntity) => {
        return value.title;
      },
      (value: AiraSyncBookmarkFolderEntity) => {
        return `名称：${value.title}，父文件夹：${value.parentId ?? '根目录'}`;
      },
      false,
      resolution
    );
  }

  private mergeItems(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    resolution?: AiraBookmarkConflictResolution
  ): AiraMergeCollectionResult<AiraSyncBookmarkItemEntity> {
    return this.mergeCollection(
      baseline.bookmarkItems,
      local.bookmarkItems,
      remote.bookmarkItems,
      (value: AiraSyncBookmarkItemEntity) => value.id,
      (left: AiraSyncBookmarkItemEntity, right: AiraSyncBookmarkItemEntity) => {
        return left.title === right.title && left.url === right.url && left.parentId === right.parentId;
      },
      (value: AiraSyncBookmarkItemEntity) => {
        return value.title;
      },
      (value: AiraSyncBookmarkItemEntity) => {
        return `标题：${value.title}，网址：${value.url}，父文件夹：${value.parentId ?? '根目录'}`;
      },
      false,
      resolution
    );
  }

  private mergeOrders(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    protectedEntityIds: Set<string> = new Set<string>()
  ): AiraMergeCollectionResult<AiraSyncBookmarkOrder> {
    const validIds = this.collectLiveBookmarkEntityIdSet(local, remote);
    const liveFolderIds = this.collectLiveFolderEntityIdSet(local, remote);
    const keys = this.collectKeys(
      baseline.bookmarkOrders,
      local.bookmarkOrders,
      remote.bookmarkOrders,
      (value: AiraSyncBookmarkOrder) => this.bookmarkOrderKey(value)
    );
    const baselineByKey = this.buildValueMap(baseline.bookmarkOrders, (value: AiraSyncBookmarkOrder) => {
      return this.bookmarkOrderKey(value);
    });
    const localByKey = this.buildValueMap(local.bookmarkOrders, (value: AiraSyncBookmarkOrder) => {
      return this.bookmarkOrderKey(value);
    });
    const remoteByKey = this.buildValueMap(remote.bookmarkOrders, (value: AiraSyncBookmarkOrder) => {
      return this.bookmarkOrderKey(value);
    });
    const values: AiraSyncBookmarkOrder[] = [];
    let localChangeCount = 0;
    let remoteChangeCount = 0;
    keys.forEach((key: string) => {
      const baselineOrder = baselineByKey.get(key);
      const localOrder = localByKey.get(key);
      const remoteOrder = remoteByKey.get(key);
      const localChanged = this.hasChanged(
        baselineOrder,
        localOrder,
        (left: AiraSyncBookmarkOrder, right: AiraSyncBookmarkOrder) => this.sameStringArray(left.ids, right.ids)
      );
      const remoteChanged = this.hasChanged(
        baselineOrder,
        remoteOrder,
        (left: AiraSyncBookmarkOrder, right: AiraSyncBookmarkOrder) => this.sameStringArray(left.ids, right.ids)
      );
      if (localChanged) {
        localChangeCount += 1;
      }
      if (remoteChanged) {
        remoteChangeCount += 1;
      }

      const parentId = key === '__root__' ? null : key;
      const baseIds = baselineOrder ? baselineOrder.ids : [];
      const localIds = localOrder ? localOrder.ids : [];
      const remoteIds = remoteOrder ? remoteOrder.ids : [];
      const sourceOrder = this.selectOrderSource(
        baselineOrder,
        localOrder,
        remoteOrder,
        localChanged,
        remoteChanged
      );
      const primaryIds = sourceOrder === remoteOrder ? remoteIds : localIds;
      const secondaryIds = sourceOrder === remoteOrder ? localIds : remoteIds;
      const mergedIds = this.mergeOrderedIds(
        baseIds,
        primaryIds,
        secondaryIds,
        validIds,
        protectedEntityIds
      );
      if (mergedIds.length === 0 && !this.shouldKeepEmptyOrder(parentId, liveFolderIds)) {
        return;
      }

      values.push({
        type: 'bookmark-order',
        parentId: parentId,
        ids: mergedIds,
        updatedAt: this.resolveLatestIso([
          baselineOrder ? baselineOrder.updatedAt : undefined,
          localOrder ? localOrder.updatedAt : undefined,
          remoteOrder ? remoteOrder.updatedAt : undefined
        ]),
        updatedBy: sourceOrder ? sourceOrder.updatedBy : local.meta.deviceId,
        revision: Math.max(
          baselineOrder ? baselineOrder.revision : 0,
          localOrder ? localOrder.revision : 0,
          remoteOrder ? remoteOrder.revision : 0
        ) + (this.orderMatchesEitherSide(mergedIds, localIds, remoteIds) ? 0 : 1)
      });
    });
    return {
      values: values,
      conflictCount: 0,
      localChangeCount: localChangeCount,
      remoteChangeCount: remoteChangeCount,
      conflictDetails: []
    };
  }

  private mergeTombstones(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot
  ): AiraMergeCollectionResult<AiraSyncTombstone> {
    return this.mergeCollection(
      this.filterBookmarkTombstones(baseline.tombstones),
      this.filterBookmarkTombstones(local.tombstones),
      this.filterBookmarkTombstones(remote.tombstones),
      (value: AiraSyncTombstone) => this.bookmarkTombstoneKey(value),
      (left: AiraSyncTombstone, right: AiraSyncTombstone) => this.sameBookmarkTombstone(left, right),
      (value: AiraSyncTombstone) => {
        return value.id;
      },
      (value: AiraSyncTombstone) => {
        return `删除时间：${value.deletedAt}`;
      },
      true,
      undefined,
      (_baseline, localValue, remoteValue) => this.selectFreshestTombstone(localValue, remoteValue)
    );
  }

  private mergePrivateBookmarkDataSets(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    ignoredTombstoneKeys: Set<string> = new Set<string>()
  ): AiraPrivateBookmarkMergeResult {
    const baselineDataSet = this.normalizePrivateBookmarkDataSet(baseline);
    const localDataSet = this.normalizePrivateBookmarkDataSet(local);
    const remoteDataSet = this.normalizePrivateBookmarkDataSet(remote);
    const folderMerge = this.mergePrivateFolders(baselineDataSet, localDataSet, remoteDataSet);
    const itemMerge = this.mergePrivateItems(baselineDataSet, localDataSet, remoteDataSet);
    const tombstoneMerge = this.mergePrivateTombstones(baselineDataSet, localDataSet, remoteDataSet);
    const resolvedTombstones = tombstoneMerge.values.filter((value: AiraSyncTombstone): boolean => {
      return !ignoredTombstoneKeys.has(`${value.type}|${value.id}`);
    });
    const deletedFolderIds = this.buildDeletedEntityIdSet(resolvedTombstones, 'bookmark-folder');
    const deletedItemIds = this.buildDeletedEntityIdSet(resolvedTombstones, 'bookmark-item');
    const liveFolders = folderMerge.values.filter((folder: AiraSyncBookmarkFolderEntity) => !deletedFolderIds.has(folder.id));
    const liveItems = itemMerge.values.filter((item: AiraSyncBookmarkItemEntity) => !deletedItemIds.has(item.id));
    const canonicalTombstones = this.filterTombstonesOpposedBySurvivingLiveEntities(
      resolvedTombstones,
      liveFolders,
      liveItems
    );
    const liveEntityIds = this.collectEntityIds(liveFolders, liveItems);
    const orderMerge = this.mergePrivateOrders(
      baselineDataSet,
      localDataSet,
      remoteDataSet,
      liveFolders,
      liveEntityIds,
      local.meta.deviceId,
      this.buildIgnoredEntityIdSet(ignoredTombstoneKeys)
    );
    return {
      dataSet: {
        bookmarkFolders: liveFolders,
        bookmarkItems: liveItems,
        bookmarkOrders: orderMerge.values,
        tombstones: canonicalTombstones
      },
      localChangeCount: folderMerge.localChangeCount + itemMerge.localChangeCount +
        tombstoneMerge.localChangeCount + orderMerge.localChangeCount,
      remoteChangeCount: folderMerge.remoteChangeCount + itemMerge.remoteChangeCount +
        tombstoneMerge.remoteChangeCount + orderMerge.remoteChangeCount
    };
  }

  private async mergePrivateBookmarkDataSetsCooperatively(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    throttle: AiraSyncWorkThrottleService,
    ignoredTombstoneKeys: Set<string> = new Set<string>()
  ): Promise<AiraPrivateBookmarkMergeResult> {
    const result = this.mergePrivateBookmarkDataSets(
      baseline,
      local,
      remote,
      ignoredTombstoneKeys
    );
    await throttle.afterStage();
    return result;
  }

  private mergeInitialPrivateBookmarkDataSets(
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    remoteDeviceId: string,
    generatedAt: string
  ): AiraSyncBookmarkDataSet {
    return this.mergeMissingBaselineDataSets(
      this.normalizePrivateBookmarkDataSet(local),
      this.normalizePrivateBookmarkDataSet(remote),
      remoteDeviceId,
      generatedAt
    );
  }

  private mergePrivateFolders(
    baseline: AiraSyncBookmarkDataSet,
    local: AiraSyncBookmarkDataSet,
    remote: AiraSyncBookmarkDataSet
  ): AiraMergeCollectionResult<AiraSyncBookmarkFolderEntity> {
    return this.mergeCollection(
      baseline.bookmarkFolders,
      local.bookmarkFolders,
      remote.bookmarkFolders,
      (value: AiraSyncBookmarkFolderEntity) => value.id,
      (left: AiraSyncBookmarkFolderEntity, right: AiraSyncBookmarkFolderEntity) => {
        return left.title === right.title && left.parentId === right.parentId;
      },
      (value: AiraSyncBookmarkFolderEntity) => value.title,
      (value: AiraSyncBookmarkFolderEntity) => `名称：${value.title}`,
      false,
      undefined,
      (_baseline, localValue, remoteValue) => this.selectFreshestFolder(localValue, remoteValue)
    );
  }

  private mergePrivateItems(
    baseline: AiraSyncBookmarkDataSet,
    local: AiraSyncBookmarkDataSet,
    remote: AiraSyncBookmarkDataSet
  ): AiraMergeCollectionResult<AiraSyncBookmarkItemEntity> {
    return this.mergeCollection(
      baseline.bookmarkItems,
      local.bookmarkItems,
      remote.bookmarkItems,
      (value: AiraSyncBookmarkItemEntity) => value.id,
      (left: AiraSyncBookmarkItemEntity, right: AiraSyncBookmarkItemEntity) => {
        return left.title === right.title && left.url === right.url && left.parentId === right.parentId;
      },
      (value: AiraSyncBookmarkItemEntity) => value.title,
      (value: AiraSyncBookmarkItemEntity) => `标题：${value.title}`,
      false,
      undefined,
      (_baseline, localValue, remoteValue) => this.selectFreshestItem(localValue, remoteValue)
    );
  }

  private mergePrivateTombstones(
    baseline: AiraSyncBookmarkDataSet,
    local: AiraSyncBookmarkDataSet,
    remote: AiraSyncBookmarkDataSet
  ): AiraMergeCollectionResult<AiraSyncTombstone> {
    return this.mergeCollection(
      this.filterBookmarkTombstones(baseline.tombstones),
      this.filterBookmarkTombstones(local.tombstones),
      this.filterBookmarkTombstones(remote.tombstones),
      (value: AiraSyncTombstone) => this.bookmarkTombstoneKey(value),
      (left: AiraSyncTombstone, right: AiraSyncTombstone) => this.sameBookmarkTombstone(left, right),
      (value: AiraSyncTombstone) => value.id,
      (value: AiraSyncTombstone) => `删除时间：${value.deletedAt}`,
      true,
      undefined,
      (_baseline, localValue, remoteValue) => this.selectFreshestTombstone(localValue, remoteValue)
    );
  }

  private mergePrivateOrders(
    baseline: AiraSyncBookmarkDataSet,
    local: AiraSyncBookmarkDataSet,
    remote: AiraSyncBookmarkDataSet,
    liveFolders: AiraSyncBookmarkFolderEntity[],
    liveEntityIds: Set<string>,
    deviceId: string,
    protectedEntityIds: Set<string> = new Set<string>()
  ): AiraMergeCollectionResult<AiraSyncBookmarkOrder> {
    const liveFolderIds = new Set<string>();
    liveFolders.forEach((folder: AiraSyncBookmarkFolderEntity) => liveFolderIds.add(folder.id));
    const keys = this.collectKeys(
      baseline.bookmarkOrders,
      local.bookmarkOrders,
      remote.bookmarkOrders,
      (value: AiraSyncBookmarkOrder) => this.bookmarkOrderKey(value)
    );
    const baselineByKey = this.buildValueMap(baseline.bookmarkOrders, (value: AiraSyncBookmarkOrder) => this.bookmarkOrderKey(value));
    const localByKey = this.buildValueMap(local.bookmarkOrders, (value: AiraSyncBookmarkOrder) => this.bookmarkOrderKey(value));
    const remoteByKey = this.buildValueMap(remote.bookmarkOrders, (value: AiraSyncBookmarkOrder) => this.bookmarkOrderKey(value));
    const result: AiraSyncBookmarkOrder[] = [];
    let localChangeCount = 0;
    let remoteChangeCount = 0;
    keys.forEach((key: string) => {
      const baselineOrder = baselineByKey.get(key);
      const localOrder = localByKey.get(key);
      const remoteOrder = remoteByKey.get(key);
      const localChanged = this.hasChanged(
        baselineOrder,
        localOrder,
        (left: AiraSyncBookmarkOrder, right: AiraSyncBookmarkOrder) => this.sameStringArray(left.ids, right.ids)
      );
      const remoteChanged = this.hasChanged(
        baselineOrder,
        remoteOrder,
        (left: AiraSyncBookmarkOrder, right: AiraSyncBookmarkOrder) => this.sameStringArray(left.ids, right.ids)
      );
      if (localChanged) {
        localChangeCount += 1;
      }
      if (remoteChanged) {
        remoteChangeCount += 1;
      }
      const parentId = key === '__root__' ? null : key;
      const sourceOrder = this.selectFreshestOrder(localOrder, remoteOrder, baselineOrder);
      const primaryIds = sourceOrder === remoteOrder ? remoteOrder?.ids ?? [] : localOrder?.ids ?? [];
      const secondaryIds = sourceOrder === remoteOrder ? localOrder?.ids ?? [] : remoteOrder?.ids ?? [];
      const mergedIds = this.mergeOrderedIds(
        baselineOrder ? baselineOrder.ids : [],
        primaryIds,
        secondaryIds,
        liveEntityIds,
        protectedEntityIds
      );
      if (mergedIds.length === 0 && !this.shouldKeepEmptyOrder(parentId, liveFolderIds)) {
        return;
      }
      result.push({
        type: 'bookmark-order',
        parentId: parentId,
        ids: mergedIds,
        updatedAt: this.resolveLatestIso([
          baselineOrder ? baselineOrder.updatedAt : undefined,
          localOrder ? localOrder.updatedAt : undefined,
          remoteOrder ? remoteOrder.updatedAt : undefined
        ]),
        updatedBy: sourceOrder ? sourceOrder.updatedBy : deviceId,
        revision: Math.max(
          baselineOrder ? baselineOrder.revision : 0,
          localOrder ? localOrder.revision : 0,
          remoteOrder ? remoteOrder.revision : 0
        ) + (this.orderMatchesEitherSide(mergedIds, localOrder?.ids ?? [], remoteOrder?.ids ?? []) ? 0 : 1)
      });
    });
    return {
      values: result,
      conflictCount: 0,
      localChangeCount: localChangeCount,
      remoteChangeCount: remoteChangeCount,
      conflictDetails: []
    };
  }

  private async mergeFoldersCooperatively(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    throttle: AiraSyncWorkThrottleService,
    resolution?: AiraBookmarkConflictResolution
  ): Promise<AiraMergeCollectionResult<AiraSyncBookmarkFolderEntity>> {
    return this.mergeCollectionCooperatively(
      baseline.bookmarkFolders,
      local.bookmarkFolders,
      remote.bookmarkFolders,
      (value: AiraSyncBookmarkFolderEntity) => value.id,
      (left: AiraSyncBookmarkFolderEntity, right: AiraSyncBookmarkFolderEntity) => {
        return left.title === right.title && left.parentId === right.parentId;
      },
      (value: AiraSyncBookmarkFolderEntity) => {
        return value.title;
      },
      (value: AiraSyncBookmarkFolderEntity) => {
        return `名称：${value.title}，父文件夹：${value.parentId ?? '根目录'}`;
      },
      throttle,
      false,
      resolution
    );
  }

  private async mergeItemsCooperatively(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    throttle: AiraSyncWorkThrottleService,
    resolution?: AiraBookmarkConflictResolution
  ): Promise<AiraMergeCollectionResult<AiraSyncBookmarkItemEntity>> {
    return this.mergeCollectionCooperatively(
      baseline.bookmarkItems,
      local.bookmarkItems,
      remote.bookmarkItems,
      (value: AiraSyncBookmarkItemEntity) => value.id,
      (left: AiraSyncBookmarkItemEntity, right: AiraSyncBookmarkItemEntity) => {
        return left.title === right.title && left.url === right.url && left.parentId === right.parentId;
      },
      (value: AiraSyncBookmarkItemEntity) => {
        return value.title;
      },
      (value: AiraSyncBookmarkItemEntity) => {
        return `标题：${value.title}，网址：${value.url}，父文件夹：${value.parentId ?? '根目录'}`;
      },
      throttle,
      false,
      resolution
    );
  }

  private async mergeTombstonesCooperatively(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    throttle: AiraSyncWorkThrottleService
  ): Promise<AiraMergeCollectionResult<AiraSyncTombstone>> {
    return this.mergeCollectionCooperatively(
      this.filterBookmarkTombstones(baseline.tombstones),
      this.filterBookmarkTombstones(local.tombstones),
      this.filterBookmarkTombstones(remote.tombstones),
      (value: AiraSyncTombstone) => this.bookmarkTombstoneKey(value),
      (left: AiraSyncTombstone, right: AiraSyncTombstone) => this.sameBookmarkTombstone(left, right),
      (value: AiraSyncTombstone) => {
        return value.id;
      },
      (value: AiraSyncTombstone) => {
        return `删除时间：${value.deletedAt}`;
      },
      throttle,
      true,
      undefined,
      (_baseline, localValue, remoteValue) => this.selectFreshestTombstone(localValue, remoteValue)
    );
  }

  private async mergeOrdersCooperatively(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    throttle: AiraSyncWorkThrottleService,
    protectedEntityIds: Set<string> = new Set<string>()
  ): Promise<AiraMergeCollectionResult<AiraSyncBookmarkOrder>> {
    const validIds = await this.collectLiveBookmarkEntityIdSetCooperatively(local, remote, throttle);
    const liveFolderIds = await this.collectLiveFolderEntityIdSetCooperatively(local, remote, throttle);
    const keys = await this.collectKeysCooperatively(
      baseline.bookmarkOrders,
      local.bookmarkOrders,
      remote.bookmarkOrders,
      (value: AiraSyncBookmarkOrder) => this.bookmarkOrderKey(value),
      throttle
    );
    const baselineByKey = await this.buildValueMapCooperatively(baseline.bookmarkOrders, (value: AiraSyncBookmarkOrder) => {
      return this.bookmarkOrderKey(value);
    }, throttle);
    const localByKey = await this.buildValueMapCooperatively(local.bookmarkOrders, (value: AiraSyncBookmarkOrder) => {
      return this.bookmarkOrderKey(value);
    }, throttle);
    const remoteByKey = await this.buildValueMapCooperatively(remote.bookmarkOrders, (value: AiraSyncBookmarkOrder) => {
      return this.bookmarkOrderKey(value);
    }, throttle);
    const values: AiraSyncBookmarkOrder[] = [];
    let localChangeCount = 0;
    let remoteChangeCount = 0;
    for (let index = 0; index < keys.length; index += 1) {
      const key = keys[index];
      const baselineOrder = baselineByKey.get(key);
      const localOrder = localByKey.get(key);
      const remoteOrder = remoteByKey.get(key);
      const localChanged = this.hasChanged(
        baselineOrder,
        localOrder,
        (left: AiraSyncBookmarkOrder, right: AiraSyncBookmarkOrder) => this.sameStringArray(left.ids, right.ids)
      );
      const remoteChanged = this.hasChanged(
        baselineOrder,
        remoteOrder,
        (left: AiraSyncBookmarkOrder, right: AiraSyncBookmarkOrder) => this.sameStringArray(left.ids, right.ids)
      );
      if (localChanged) {
        localChangeCount += 1;
      }
      if (remoteChanged) {
        remoteChangeCount += 1;
      }

      const parentId = key === '__root__' ? null : key;
      const baseIds = baselineOrder ? baselineOrder.ids : [];
      const localIds = localOrder ? localOrder.ids : [];
      const remoteIds = remoteOrder ? remoteOrder.ids : [];
      const sourceOrder = this.selectOrderSource(
        baselineOrder,
        localOrder,
        remoteOrder,
        localChanged,
        remoteChanged
      );
      const primaryIds = sourceOrder === remoteOrder ? remoteIds : localIds;
      const secondaryIds = sourceOrder === remoteOrder ? localIds : remoteIds;
      const mergedIds = await this.mergeOrderedIdsCooperatively(
        baseIds,
        primaryIds,
        secondaryIds,
        validIds,
        throttle,
        protectedEntityIds
      );
      if (mergedIds.length === 0 && !this.shouldKeepEmptyOrder(parentId, liveFolderIds)) {
        await throttle.afterBatchItem(index + 1);
        continue;
      }

      values.push({
        type: 'bookmark-order',
        parentId: parentId,
        ids: mergedIds,
        updatedAt: this.resolveLatestIso([
          baselineOrder ? baselineOrder.updatedAt : undefined,
          localOrder ? localOrder.updatedAt : undefined,
          remoteOrder ? remoteOrder.updatedAt : undefined
        ]),
        updatedBy: sourceOrder ? sourceOrder.updatedBy : local.meta.deviceId,
        revision: Math.max(
          baselineOrder ? baselineOrder.revision : 0,
          localOrder ? localOrder.revision : 0,
          remoteOrder ? remoteOrder.revision : 0
        ) + (this.orderMatchesEitherSide(mergedIds, localIds, remoteIds) ? 0 : 1)
      });
      await throttle.afterBatchItem(index + 1);
    }
    return {
      values: values,
      conflictCount: 0,
      localChangeCount: localChangeCount,
      remoteChangeCount: remoteChangeCount,
      conflictDetails: []
    };
  }

  private async mergeCollectionCooperatively<T>(
    baselineValues: T[],
    localValues: T[],
    remoteValues: T[],
    keyOf: (value: T) => string,
    equals: (left: T, right: T) => boolean,
    titleOf: (value: T) => string,
    describe: (value: T) => string,
    throttle: AiraSyncWorkThrottleService,
    unionOnConflict: boolean = false,
    resolution?: AiraBookmarkConflictResolution,
    mergeConcurrent?: (baseline: T | undefined, local: T | undefined, remote: T | undefined) => T | undefined
  ): Promise<AiraMergeCollectionResult<T>> {
    const keys = await this.collectKeysCooperatively(baselineValues, localValues, remoteValues, keyOf, throttle);
    const baselineByKey = await this.buildValueMapCooperatively(baselineValues, keyOf, throttle);
    const localByKey = await this.buildValueMapCooperatively(localValues, keyOf, throttle);
    const remoteByKey = await this.buildValueMapCooperatively(remoteValues, keyOf, throttle);
    const values: T[] = [];
    const conflictDetails: AiraBookmarkMergeConflictDetail[] = [];
    let conflictCount = 0;
    let localChangeCount = 0;
    let remoteChangeCount = 0;
    for (let index = 0; index < keys.length; index += 1) {
      const key = keys[index];
      const baseline = baselineByKey.get(key);
      const local = localByKey.get(key);
      const remote = remoteByKey.get(key);
      const localChanged = this.hasChanged(baseline, local, equals);
      const remoteChanged = this.hasChanged(baseline, remote, equals);
      if (localChanged) {
        localChangeCount += 1;
      }
      if (remoteChanged) {
        remoteChangeCount += 1;
      }
      if (localChanged && remoteChanged && local !== undefined && remote !== undefined && !equals(local, remote)) {
        if (resolution === 'prefer-local') {
          values.push(local);
          await throttle.afterBatchItem(index + 1);
          continue;
        }
        if (resolution === 'prefer-remote') {
          values.push(remote);
          await throttle.afterBatchItem(index + 1);
          continue;
        }
        if (mergeConcurrent !== undefined) {
          const merged = mergeConcurrent(baseline, local, remote);
          if (merged !== undefined) {
            values.push(merged);
            await throttle.afterBatchItem(index + 1);
            continue;
          }
        }
        if (!unionOnConflict) {
          conflictCount += 1;
          conflictDetails.push({
            id: key,
            type: this.resolveConflictType(local),
            title: titleOf(local),
            localValue: describe(local),
            remoteValue: describe(remote)
          });
        }
        values.push(remote);
        await throttle.afterBatchItem(index + 1);
        continue;
      }
      if (remoteChanged && remote !== undefined) {
        values.push(remote);
        await throttle.afterBatchItem(index + 1);
        continue;
      }
      if (localChanged && local !== undefined) {
        values.push(local);
        await throttle.afterBatchItem(index + 1);
        continue;
      }
      if (remote !== undefined) {
        values.push(remote);
        await throttle.afterBatchItem(index + 1);
        continue;
      }
      if (local !== undefined) {
        values.push(local);
      }
      await throttle.afterBatchItem(index + 1);
    }
    return {
      values: values,
      conflictCount: conflictCount,
      localChangeCount: localChangeCount,
      remoteChangeCount: remoteChangeCount,
      conflictDetails: conflictDetails
    };
  }

  private mergeCollection<T>(
    baselineValues: T[],
    localValues: T[],
    remoteValues: T[],
    keyOf: (value: T) => string,
    equals: (left: T, right: T) => boolean,
    titleOf: (value: T) => string,
    describe: (value: T) => string,
    unionOnConflict: boolean = false,
    resolution?: AiraBookmarkConflictResolution,
    mergeConcurrent?: (baseline: T | undefined, local: T | undefined, remote: T | undefined) => T | undefined
  ): AiraMergeCollectionResult<T> {
    const keys = this.collectKeys(baselineValues, localValues, remoteValues, keyOf);
    const baselineByKey = this.buildValueMap(baselineValues, keyOf);
    const localByKey = this.buildValueMap(localValues, keyOf);
    const remoteByKey = this.buildValueMap(remoteValues, keyOf);
    const values: T[] = [];
    const conflictDetails: AiraBookmarkMergeConflictDetail[] = [];
    let conflictCount = 0;
    let localChangeCount = 0;
    let remoteChangeCount = 0;
    keys.forEach((key: string) => {
      const baseline = baselineByKey.get(key);
      const local = localByKey.get(key);
      const remote = remoteByKey.get(key);
      const localChanged = this.hasChanged(baseline, local, equals);
      const remoteChanged = this.hasChanged(baseline, remote, equals);
      if (localChanged) {
        localChangeCount += 1;
      }
      if (remoteChanged) {
        remoteChangeCount += 1;
      }
      if (localChanged && remoteChanged && local !== undefined && remote !== undefined && !equals(local, remote)) {
        if (resolution === 'prefer-local') {
          values.push(local);
          return;
        }
        if (resolution === 'prefer-remote') {
          values.push(remote);
          return;
        }
        if (mergeConcurrent !== undefined) {
          const merged = mergeConcurrent(baseline, local, remote);
          if (merged !== undefined) {
            values.push(merged);
            return;
          }
        }
        if (!unionOnConflict) {
          conflictCount += 1;
          conflictDetails.push({
            id: key,
            type: this.resolveConflictType(local),
            title: titleOf(local),
            localValue: describe(local),
            remoteValue: describe(remote)
          });
        }
        values.push(remote);
        return;
      }
      if (remoteChanged && remote !== undefined) {
        values.push(remote);
        return;
      }
      if (localChanged && local !== undefined) {
        values.push(local);
        return;
      }
      if (remote !== undefined) {
        values.push(remote);
        return;
      }
      if (local !== undefined) {
        values.push(local);
      }
    });
    return {
      values: values,
      conflictCount: conflictCount,
      localChangeCount: localChangeCount,
      remoteChangeCount: remoteChangeCount,
      conflictDetails: conflictDetails
    };
  }

  private collectKeys<T>(baseline: T[], local: T[], remote: T[], keyOf: (value: T) => string): string[] {
    const keys: string[] = [];
    const seen = new Set<string>();
    const visit = (values: T[]): void => {
      values.forEach((value: T) => {
        const key = keyOf(value);
        if (!seen.has(key)) {
          seen.add(key);
          keys.push(key);
        }
      });
    };
    visit(baseline);
    visit(local);
    visit(remote);
    return keys;
  }

  private async collectKeysCooperatively<T>(
    baseline: T[],
    local: T[],
    remote: T[],
    keyOf: (value: T) => string,
    throttle: AiraSyncWorkThrottleService
  ): Promise<string[]> {
    const keys: string[] = [];
    const seen = new Set<string>();
    await this.visitKeysCooperatively(baseline, keyOf, seen, keys, throttle);
    await this.visitKeysCooperatively(local, keyOf, seen, keys, throttle);
    await this.visitKeysCooperatively(remote, keyOf, seen, keys, throttle);
    return keys;
  }

  private async visitKeysCooperatively<T>(
    values: T[],
    keyOf: (value: T) => string,
    seen: Set<string>,
    keys: string[],
    throttle: AiraSyncWorkThrottleService
  ): Promise<void> {
    for (let index = 0; index < values.length; index += 1) {
      const key = keyOf(values[index]);
      if (!seen.has(key)) {
        seen.add(key);
        keys.push(key);
      }
      await throttle.afterBatchItem(index + 1);
    }
  }

  private buildValueMap<T>(values: T[], keyOf: (value: T) => string): Map<string, T> {
    const result = new Map<string, T>();
    values.forEach((value: T) => {
      result.set(keyOf(value), value);
    });
    return result;
  }

  private async buildValueMapCooperatively<T>(
    values: T[],
    keyOf: (value: T) => string,
    throttle: AiraSyncWorkThrottleService
  ): Promise<Map<string, T>> {
    const result = new Map<string, T>();
    for (let index = 0; index < values.length; index += 1) {
      const value = values[index];
      result.set(keyOf(value), value);
      await throttle.afterBatchItem(index + 1);
    }
    return result;
  }

  private mergeInitialTombstones(
    local: AiraSyncTombstone[],
    remote: AiraSyncTombstone[]
  ): AiraSyncTombstone[] {
    const values = new Map<string, AiraSyncTombstone>();
    this.filterBookmarkTombstones(remote).forEach((entry: AiraSyncTombstone) => {
      values.set(this.bookmarkTombstoneKey(entry), entry);
    });
    this.filterBookmarkTombstones(local).forEach((entry: AiraSyncTombstone) => {
      const key = this.bookmarkTombstoneKey(entry);
      const existing = values.get(key);
      const selected = this.selectFreshestTombstone(entry, existing);
      if (selected !== undefined) {
        values.set(key, selected);
      }
    });
    return Array.from(values.values());
  }

  private mergeMissingBaselineDataSets(
    local: AiraSyncBookmarkDataSet,
    remote: AiraSyncBookmarkDataSet,
    remoteDeviceId: string,
    generatedAt: string
  ): AiraSyncBookmarkDataSet {
    const remappedRemote = this.remapInitialRemoteCollisions(local, remote, remoteDeviceId);
    // On a first join, a tombstone may only be suppressed by the remote's own live
    // entities: a snapshot cannot list one id as both live and deleted. A locally-live
    // entity with the same id is the same entity (ids are unique by construction), so
    // ignoring the tombstone there would silently resurrect a bookmark the account had
    // already deleted. Local tombstones are still carried, but they can never delete a
    // remote live entity, because those ids are filtered out first.
    const remoteLiveEntityIds = new Set<string>();
    remappedRemote.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity): void => {
      remoteLiveEntityIds.add(folder.id);
    });
    remappedRemote.bookmarkItems.forEach((item: AiraSyncBookmarkItemEntity): void => {
      remoteLiveEntityIds.add(item.id);
    });
    const tombstoneValues = this.mergeInitialTombstones(local.tombstones, remappedRemote.tombstones)
      .filter((entry: AiraSyncTombstone): boolean => !remoteLiveEntityIds.has(entry.id));
    const deletedFolderIds = this.buildDeletedEntityIdSet(tombstoneValues, 'bookmark-folder');
    const deletedItemIds = this.buildDeletedEntityIdSet(tombstoneValues, 'bookmark-item');
    const survivingLocalFolders = local.bookmarkFolders.filter(
      (folder: AiraSyncBookmarkFolderEntity): boolean => !deletedFolderIds.has(folder.id)
    );
    const survivingLocalItems = local.bookmarkItems.filter(
      (item: AiraSyncBookmarkItemEntity): boolean => !deletedItemIds.has(item.id)
    );
    const survivingRemoteFolders = remappedRemote.bookmarkFolders.filter(
      (folder: AiraSyncBookmarkFolderEntity): boolean => !deletedFolderIds.has(folder.id)
    );
    const survivingRemoteItems = remappedRemote.bookmarkItems.filter(
      (item: AiraSyncBookmarkItemEntity): boolean => !deletedItemIds.has(item.id)
    );
    const bookmarkFolders = this.mergeInitialFolders(survivingLocalFolders, survivingRemoteFolders);
    const bookmarkItems = this.mergeInitialItems(survivingLocalItems, survivingRemoteItems);
    const liveFolderIds = this.toFolderIdSet(bookmarkFolders);
    const liveItemIds = this.toItemIdSet(bookmarkItems);
    const tombstones = tombstoneValues.filter((entry: AiraSyncTombstone): boolean => {
      return !liveFolderIds.has(entry.id) && !liveItemIds.has(entry.id);
    });
    const liveEntityIds = this.collectEntityIds(bookmarkFolders, bookmarkItems);
    return {
      bookmarkFolders: bookmarkFolders,
      bookmarkItems: bookmarkItems,
      bookmarkOrders: this.mergeInitialOrders(
        local.bookmarkOrders,
        remappedRemote.bookmarkOrders,
        bookmarkFolders,
        bookmarkItems,
        liveEntityIds,
        remoteDeviceId,
        generatedAt
      ),
      tombstones: tombstones
    };
  }

  private remapInitialRemoteCollisions(
    local: AiraSyncBookmarkDataSet,
    remote: AiraSyncBookmarkDataSet,
    remoteDeviceId: string
  ): AiraSyncBookmarkDataSet {
    const localFoldersById = this.buildValueMap(local.bookmarkFolders, (value: AiraSyncBookmarkFolderEntity) => value.id);
    const localItemsById = this.buildValueMap(local.bookmarkItems, (value: AiraSyncBookmarkItemEntity) => value.id);
    const remoteFoldersById = this.buildValueMap(remote.bookmarkFolders, (value: AiraSyncBookmarkFolderEntity) => value.id);
    const reservedIds = new Set<string>();
    local.bookmarkFolders.forEach((value: AiraSyncBookmarkFolderEntity) => reservedIds.add(value.id));
    local.bookmarkItems.forEach((value: AiraSyncBookmarkItemEntity) => reservedIds.add(value.id));
    remote.bookmarkFolders.forEach((value: AiraSyncBookmarkFolderEntity) => reservedIds.add(value.id));
    remote.bookmarkItems.forEach((value: AiraSyncBookmarkItemEntity) => reservedIds.add(value.id));

    const entityIdMap = new Map<string, string>();
    const pendingFolders = remote.bookmarkFolders.slice();
    const remappedFolders: AiraSyncBookmarkFolderEntity[] = [];
    while (pendingFolders.length > 0) {
      let progressed = false;
      for (let index = pendingFolders.length - 1; index >= 0; index -= 1) {
        const folder = pendingFolders[index];
        const parentIsPending = folder.parentId !== null && remoteFoldersById.has(folder.parentId) &&
          !entityIdMap.has(folder.parentId) && folder.parentId !== folder.id;
        if (parentIsPending) {
          continue;
        }
        const parentId = folder.parentId === null ? null : (entityIdMap.get(folder.parentId) ?? folder.parentId);
        const localFolder = localFoldersById.get(folder.id);
        const compatible = localFolder !== undefined && localItemsById.get(folder.id) === undefined &&
          localFolder.title === folder.title && localFolder.parentId === parentId;
        const collides = localItemsById.has(folder.id) || (localFolder !== undefined && !compatible);
        const id = collides && !this.isCanonicalBookmarkRootId(folder.id)
          ? this.createInitialCollisionId(
            'folder',
            folder.id,
            parentId,
            folder.title,
            '',
            remoteDeviceId,
            reservedIds
          )
          : folder.id;
        entityIdMap.set(folder.id, id);
        remappedFolders.push({
          id: id,
          type: 'bookmark-folder',
          parentId: parentId,
          title: folder.title,
          createdAt: folder.createdAt,
          updatedAt: folder.updatedAt,
          updatedBy: folder.updatedBy,
          revision: folder.revision
        });
        pendingFolders.splice(index, 1);
        progressed = true;
      }
      if (!progressed) {
        const folder = pendingFolders.pop();
        if (folder === undefined) {
          break;
        }
        const parentId = folder.parentId === null ? null : (entityIdMap.get(folder.parentId) ?? folder.parentId);
        const id = this.createInitialCollisionId(
          'folder',
          folder.id,
          parentId,
          folder.title,
          '',
          remoteDeviceId,
          reservedIds
        );
        entityIdMap.set(folder.id, id);
        remappedFolders.push({
          id: id,
          type: 'bookmark-folder',
          parentId: parentId,
          title: folder.title,
          createdAt: folder.createdAt,
          updatedAt: folder.updatedAt,
          updatedBy: folder.updatedBy,
          revision: folder.revision
        });
      }
    }

    const remappedItems = remote.bookmarkItems.map((item: AiraSyncBookmarkItemEntity): AiraSyncBookmarkItemEntity => {
      const parentId = item.parentId === null ? null : (entityIdMap.get(item.parentId) ?? item.parentId);
      const localItem = localItemsById.get(item.id);
      const compatible = localItem !== undefined && localFoldersById.get(item.id) === undefined &&
        localItem.title === item.title && localItem.url === item.url && localItem.parentId === parentId;
      const collides = localFoldersById.has(item.id) || (localItem !== undefined && !compatible);
      const id = collides
        ? this.createInitialCollisionId(
          'item',
          item.id,
          parentId,
          item.title,
          item.url,
          remoteDeviceId,
          reservedIds
        )
        : item.id;
      entityIdMap.set(item.id, id);
      return {
        id: id,
        type: 'bookmark-item',
        parentId: parentId,
        title: item.title,
        url: item.url,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
        updatedBy: item.updatedBy,
        revision: item.revision
      };
    });

    const remappedOrders = remote.bookmarkOrders.map((order: AiraSyncBookmarkOrder): AiraSyncBookmarkOrder => {
      return {
        type: 'bookmark-order',
        parentId: order.parentId === null ? null : (entityIdMap.get(order.parentId) ?? order.parentId),
        ids: order.ids.map((id: string): string => entityIdMap.get(id) ?? id),
        updatedAt: order.updatedAt,
        updatedBy: order.updatedBy,
        revision: order.revision
      };
    });
    return {
      bookmarkFolders: remappedFolders,
      bookmarkItems: remappedItems,
      bookmarkOrders: remappedOrders,
      tombstones: remote.tombstones.slice()
    };
  }

  private isCanonicalBookmarkRootId(id: string): boolean {
    return id === 'browser_root_toolbar' || id === 'browser_root_other' ||
      id === 'aira_private_root_toolbar' || id === 'aira_private_root_other';
  }

  private createInitialCollisionId(
    type: 'folder' | 'item',
    originalId: string,
    parentId: string | null,
    title: string,
    url: string,
    remoteDeviceId: string,
    reservedIds: Set<string>
  ): string {
    const fingerprint = `${type}|${originalId}|${parentId ?? ''}|${title}|${url}|${remoteDeviceId}`;
    const base = `${type === 'folder' ? 'bkf' : 'bkm'}_initial_${this.hashInitialCollision(fingerprint)}`;
    let candidate = base;
    let suffix = 1;
    while (reservedIds.has(candidate)) {
      candidate = `${base}_${suffix}`;
      suffix += 1;
    }
    reservedIds.add(candidate);
    return candidate;
  }

  private hashInitialCollision(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(36);
  }

  private mergeInitialFolders(
    local: AiraSyncBookmarkFolderEntity[],
    remote: AiraSyncBookmarkFolderEntity[]
  ): AiraSyncBookmarkFolderEntity[] {
    const values = new Map<string, AiraSyncBookmarkFolderEntity>();
    remote.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      values.set(folder.id, folder);
    });
    local.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      values.set(folder.id, folder);
    });
    return Array.from(values.values());
  }

  private mergeInitialItems(
    local: AiraSyncBookmarkItemEntity[],
    remote: AiraSyncBookmarkItemEntity[]
  ): AiraSyncBookmarkItemEntity[] {
    const values = new Map<string, AiraSyncBookmarkItemEntity>();
    remote.forEach((item: AiraSyncBookmarkItemEntity) => {
      values.set(item.id, item);
    });
    local.forEach((item: AiraSyncBookmarkItemEntity) => {
      values.set(item.id, item);
    });
    return Array.from(values.values());
  }

  // First-join identity adoption. Entity IDs are installation-scoped, so a device with
  // no baseline cannot tell that its local entity and the cloud's entity are the same
  // bookmark. The four sync roots are canonical across clients, so a path anchored on
  // the root entity ID identifies the same bookmark everywhere. This returns a rename
  // map local -> remote; it never merges or drops an entity, so a mispairing can only
  // swap two IDs and can never lose a bookmark.
  planIdentityAdoption(local: AiraSyncSnapshot, remote: AiraSyncSnapshot): Map<string, string> {
    const remoteGroups = this.buildContentCorrelationGroups(remote);
    const adoption = new Map<string, string>();
    if (remoteGroups.size === 0) {
      return adoption;
    }
    const localGroups = this.buildContentCorrelationGroups(local);
    localGroups.forEach((localIds: string[], key: string): void => {
      const remoteIds = remoteGroups.get(key);
      if (remoteIds === undefined) {
        return;
      }
      const pairCount = Math.min(localIds.length, remoteIds.length);
      for (let index = 0; index < pairCount; index += 1) {
        if (localIds[index] !== remoteIds[index]) {
          adoption.set(localIds[index], remoteIds[index]);
        }
      }
    });
    return adoption;
  }

  private buildContentCorrelationGroups(snapshot: AiraSyncSnapshot): Map<string, string[]> {
    const parentById = new Map<string, string | null>();
    const titleById = new Map<string, string>();
    const urlById = new Map<string, string>();
    snapshot.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity): void => {
      parentById.set(folder.id, folder.parentId);
      titleById.set(folder.id, folder.title);
    });
    snapshot.bookmarkItems.forEach((item: AiraSyncBookmarkItemEntity): void => {
      parentById.set(item.id, item.parentId);
      titleById.set(item.id, item.title);
      urlById.set(item.id, item.url);
    });

    const orderIndexByParent = new Map<string, Map<string, number>>();
    snapshot.bookmarkOrders.forEach((order: AiraSyncBookmarkOrder): void => {
      if (!Array.isArray(order.ids)) {
        return;
      }
      const parentKey = order.parentId === null ? AIRA_SYNC_ROOT_ORDER_KEY : order.parentId;
      const index = new Map<string, number>();
      for (let position = 0; position < order.ids.length; position += 1) {
        if (!index.has(order.ids[position])) {
          index.set(order.ids[position], position);
        }
      }
      orderIndexByParent.set(parentKey, index);
    });

    const pathKeyById = new Map<string, string>();
    const visiting = new Set<string>();
    const pathKeyOf = (id: string): string => {
      const cached = pathKeyById.get(id);
      if (cached !== undefined) {
        return cached;
      }
      if (visiting.has(id)) {
        return '';
      }
      visiting.add(id);
      const parentId = parentById.get(id) ?? null;
      let key: string;
      if (parentId === null) {
        key = id;
      } else {
        const title = titleById.get(id) ?? '';
        const url = urlById.get(id);
        const parentKey = pathKeyOf(parentId);
        key = url === undefined ? `${parentKey}\u0001${title}` : `${parentKey}\u0001${title}\u0002${url}`;
      }
      visiting.delete(id);
      pathKeyById.set(id, key);
      return key;
    };

    const groups = new Map<string, string[]>();
    snapshot.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity): void => {
      const key = pathKeyOf(folder.id);
      const current = groups.get(key);
      if (current === undefined) {
        groups.set(key, [folder.id]);
      } else {
        current.push(folder.id);
      }
    });
    snapshot.bookmarkItems.forEach((item: AiraSyncBookmarkItemEntity): void => {
      const key = pathKeyOf(item.id);
      const current = groups.get(key);
      if (current === undefined) {
        groups.set(key, [item.id]);
      } else {
        current.push(item.id);
      }
    });

    groups.forEach((ids: string[], key: string): void => {
      ids.sort((left: string, right: string): number => {
        const parentId = parentById.get(left) ?? null;
        const parentKey = parentId === null ? AIRA_SYNC_ROOT_ORDER_KEY : parentId;
        const index = orderIndexByParent.get(parentKey);
        const leftIndex = index === undefined ? -1 : (index.get(left) ?? -1);
        const rightIndex = index === undefined ? -1 : (index.get(right) ?? -1);
        if (leftIndex !== rightIndex) {
          return rightIndex - leftIndex;
        }
        const leftTitle = titleById.get(left) ?? '';
        const rightTitle = titleById.get(right) ?? '';
        if (leftTitle !== rightTitle) {
          return leftTitle.localeCompare(rightTitle);
        }
        return left.localeCompare(right);
      });
      groups.set(key, ids);
    });

    return groups;
  }

  private mergeInitialOrders(
    local: AiraSyncBookmarkOrder[],
    remote: AiraSyncBookmarkOrder[],
    folders: AiraSyncBookmarkFolderEntity[],
    items: AiraSyncBookmarkItemEntity[],
    liveEntityIds: Set<string>,
    deviceId: string,
    generatedAt: string
  ): AiraSyncBookmarkOrder[] {
    const keys = this.collectKeys(
      [],
      local,
      remote,
      (value: AiraSyncBookmarkOrder): string => this.bookmarkOrderKey(value)
    );
    const localByKey = this.buildValueMap(local, (value: AiraSyncBookmarkOrder): string => {
      return this.bookmarkOrderKey(value);
    });
    const remoteByKey = this.buildValueMap(remote, (value: AiraSyncBookmarkOrder): string => {
      return this.bookmarkOrderKey(value);
    });
    const values: AiraSyncBookmarkOrder[] = [];
    keys.forEach((key: string): void => {
      const localOrder = localByKey.get(key);
      const remoteOrder = remoteByKey.get(key);
      const localIds = localOrder?.ids ?? [];
      const remoteIds = remoteOrder?.ids ?? [];
      const sourceOrder = this.selectFreshestOrder(localOrder, remoteOrder, undefined);
      const primaryIds = sourceOrder === remoteOrder ? remoteIds : localIds;
      const secondaryIds = sourceOrder === remoteOrder ? localIds : remoteIds;
      const ids = this.mergeOrderedIds([], primaryIds, secondaryIds, liveEntityIds);
      const matchesLocal = localOrder !== undefined && this.sameStringArray(ids, localIds);
      const matchesRemote = remoteOrder !== undefined && this.sameStringArray(ids, remoteIds);
      const matchingSource = matchesLocal && matchesRemote
        ? sourceOrder
        : (matchesRemote ? remoteOrder : (matchesLocal ? localOrder : undefined));
      if (matchingSource !== undefined) {
        values.push({
          type: 'bookmark-order',
          parentId: key === '__root__' ? null : key,
          ids: ids,
          updatedAt: matchingSource.updatedAt,
          updatedBy: matchingSource.updatedBy,
          revision: matchingSource.revision
        });
        return;
      }
      values.push({
        type: 'bookmark-order',
        parentId: key === '__root__' ? null : key,
        ids: ids,
        updatedAt: this.resolveLatestIso([
          localOrder?.updatedAt,
          remoteOrder?.updatedAt
        ]),
        updatedBy: sourceOrder?.updatedBy ?? '',
        revision: Math.max(localOrder?.revision ?? 0, remoteOrder?.revision ?? 0) +
          (this.orderMatchesEitherSide(ids, localIds, remoteIds) ? 0 : 1)
      });
    });
    return this.filterOrdersByLiveIds(values, folders, items, liveEntityIds, deviceId, generatedAt);
  }

  private countInitialDataSetAdditions(
    baseline: AiraSyncBookmarkDataSet,
    candidate: AiraSyncBookmarkDataSet
  ): number {
    const baselineFolderIds = this.toFolderIdSet(baseline.bookmarkFolders);
    const baselineItemIds = this.toItemIdSet(baseline.bookmarkItems);
    const baselineOrderKeys = new Set<string>();
    baseline.bookmarkOrders.forEach((order: AiraSyncBookmarkOrder) => {
      baselineOrderKeys.add(this.bookmarkOrderKey(order));
    });
    const baselineTombstoneKeys = new Set<string>();
    baseline.tombstones.forEach((entry: AiraSyncTombstone) => {
      baselineTombstoneKeys.add(`${entry.type}|${entry.id}`);
    });
    let count = 0;
    candidate.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      if (!baselineFolderIds.has(folder.id)) {
        count += 1;
      }
    });
    candidate.bookmarkItems.forEach((item: AiraSyncBookmarkItemEntity) => {
      if (!baselineItemIds.has(item.id)) {
        count += 1;
      }
    });
    candidate.bookmarkOrders.forEach((order: AiraSyncBookmarkOrder) => {
      if (!baselineOrderKeys.has(this.bookmarkOrderKey(order))) {
        count += 1;
      }
    });
    candidate.tombstones.forEach((entry: AiraSyncTombstone) => {
      if (!baselineTombstoneKeys.has(`${entry.type}|${entry.id}`)) {
        count += 1;
      }
    });
    return count;
  }

  private toFolderIdSet(values: AiraSyncBookmarkFolderEntity[]): Set<string> {
    const ids = new Set<string>();
    values.forEach((value: AiraSyncBookmarkFolderEntity) => {
      ids.add(value.id);
    });
    return ids;
  }

  private toItemIdSet(values: AiraSyncBookmarkItemEntity[]): Set<string> {
    const ids = new Set<string>();
    values.forEach((value: AiraSyncBookmarkItemEntity) => {
      ids.add(value.id);
    });
    return ids;
  }

  private hasChanged<T>(baseline: T | undefined, current: T | undefined, equals: (left: T, right: T) => boolean): boolean {
    if (baseline === undefined && current === undefined) {
      return false;
    }
    if (baseline === undefined || current === undefined) {
      return true;
    }
    return !equals(baseline, current);
  }

  private sameStringArray(left: string[], right: string[]): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) {
        return false;
      }
    }
    return true;
  }

  private bookmarkOrderKey(value: AiraSyncBookmarkOrder): string {
    return value.parentId === null ? '__root__' : value.parentId;
  }

  private mergeOrderedIds(
    baseIds: string[],
    localIds: string[],
    remoteIds: string[],
    validSet: Set<string>,
    protectedEntityIds: Set<string> = new Set<string>()
  ): string[] {
    const baseSet = this.toStringSet(baseIds);
    const localSet = this.toStringSet(localIds);
    const remoteSet = this.toStringSet(remoteIds);
    const remoteRemoved = new Set<string>();
    const localRemoved = new Set<string>();
    baseIds.forEach((id: string) => {
      if (!remoteSet.has(id)) {
        remoteRemoved.add(id);
      }
      if (!localSet.has(id)) {
        localRemoved.add(id);
      }
    });
    const merged: string[] = [];
    const mergedSet = new Set<string>();
    localIds.forEach((id: string) => {
      if ((!remoteRemoved.has(id) || protectedEntityIds.has(id)) && validSet.has(id) && !mergedSet.has(id)) {
        merged.push(id);
        mergedSet.add(id);
      }
    });
    remoteIds.forEach((id: string) => {
      if (!validSet.has(id) || mergedSet.has(id)) {
        return;
      }
      if ((!baseSet.has(id) && !localRemoved.has(id)) || protectedEntityIds.has(id)) {
        merged.push(id);
        mergedSet.add(id);
      }
    });
    return merged;
  }

  private async mergeOrderedIdsCooperatively(
    baseIds: string[],
    localIds: string[],
    remoteIds: string[],
    validSet: Set<string>,
    throttle: AiraSyncWorkThrottleService,
    protectedEntityIds: Set<string> = new Set<string>()
  ): Promise<string[]> {
    const baseSet = await this.toStringSetCooperatively(baseIds, throttle);
    const localSet = await this.toStringSetCooperatively(localIds, throttle);
    const remoteSet = await this.toStringSetCooperatively(remoteIds, throttle);
    const remoteRemoved = new Set<string>();
    const localRemoved = new Set<string>();
    for (let index = 0; index < baseIds.length; index += 1) {
      const id = baseIds[index];
      if (!remoteSet.has(id)) {
        remoteRemoved.add(id);
      }
      if (!localSet.has(id)) {
        localRemoved.add(id);
      }
      await throttle.afterBatchItem(index + 1);
    }
    const merged: string[] = [];
    const mergedSet = new Set<string>();
    for (let index = 0; index < localIds.length; index += 1) {
      const id = localIds[index];
      if ((!remoteRemoved.has(id) || protectedEntityIds.has(id)) && validSet.has(id) && !mergedSet.has(id)) {
        merged.push(id);
        mergedSet.add(id);
      }
      await throttle.afterBatchItem(index + 1);
    }
    for (let index = 0; index < remoteIds.length; index += 1) {
      const id = remoteIds[index];
      if (validSet.has(id) && !mergedSet.has(id) &&
        ((!baseSet.has(id) && !localRemoved.has(id)) || protectedEntityIds.has(id))) {
        merged.push(id);
        mergedSet.add(id);
      }
      await throttle.afterBatchItem(index + 1);
    }
    return merged;
  }

  private collectLiveBookmarkEntityIdSet(local: AiraSyncSnapshot, remote: AiraSyncSnapshot): Set<string> {
    const ids = new Set<string>();
    local.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      ids.add(folder.id);
    });
    remote.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      ids.add(folder.id);
    });
    local.bookmarkItems.forEach((item: AiraSyncBookmarkItemEntity) => {
      ids.add(item.id);
    });
    remote.bookmarkItems.forEach((item: AiraSyncBookmarkItemEntity) => {
      ids.add(item.id);
    });
    return ids;
  }

  private async collectLiveBookmarkEntityIdSetCooperatively(
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    throttle: AiraSyncWorkThrottleService
  ): Promise<Set<string>> {
    const ids = new Set<string>();
    await this.addFolderIdsCooperatively(local.bookmarkFolders, ids, throttle);
    await this.addFolderIdsCooperatively(remote.bookmarkFolders, ids, throttle);
    await this.addItemIdsCooperatively(local.bookmarkItems, ids, throttle);
    await this.addItemIdsCooperatively(remote.bookmarkItems, ids, throttle);
    return ids;
  }

  private collectLiveFolderEntityIdSet(local: AiraSyncSnapshot, remote: AiraSyncSnapshot): Set<string> {
    const ids = new Set<string>();
    local.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      ids.add(folder.id);
    });
    remote.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      ids.add(folder.id);
    });
    return ids;
  }

  private async collectLiveFolderEntityIdSetCooperatively(
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    throttle: AiraSyncWorkThrottleService
  ): Promise<Set<string>> {
    const ids = new Set<string>();
    await this.addFolderIdsCooperatively(local.bookmarkFolders, ids, throttle);
    await this.addFolderIdsCooperatively(remote.bookmarkFolders, ids, throttle);
    return ids;
  }

  private async addFolderIdsCooperatively(
    folders: AiraSyncBookmarkFolderEntity[],
    ids: Set<string>,
    throttle: AiraSyncWorkThrottleService
  ): Promise<void> {
    for (let index = 0; index < folders.length; index += 1) {
      ids.add(folders[index].id);
      await throttle.afterBatchItem(index + 1);
    }
  }

  private async addItemIdsCooperatively(
    items: AiraSyncBookmarkItemEntity[],
    ids: Set<string>,
    throttle: AiraSyncWorkThrottleService
  ): Promise<void> {
    for (let index = 0; index < items.length; index += 1) {
      ids.add(items[index].id);
      await throttle.afterBatchItem(index + 1);
    }
  }

  private shouldKeepEmptyOrder(parentId: string | null, liveFolderIds: Set<string>): boolean {
    if (parentId === null) {
      return true;
    }
    return liveFolderIds.has(parentId);
  }

  private selectFreshestOrder(
    local: AiraSyncBookmarkOrder | undefined,
    remote: AiraSyncBookmarkOrder | undefined,
    baseline: AiraSyncBookmarkOrder | undefined
  ): AiraSyncBookmarkOrder | undefined {
    if (local === undefined && remote === undefined) {
      return baseline;
    }
    if (local === undefined) {
      return remote;
    }
    if (remote === undefined) {
      return local;
    }
    if (local.revision !== remote.revision) {
      return local.revision > remote.revision ? local : remote;
    }
    const localUpdatedAt = this.toMs(local.updatedAt);
    const remoteUpdatedAt = this.toMs(remote.updatedAt);
    if (localUpdatedAt !== remoteUpdatedAt) {
      return localUpdatedAt > remoteUpdatedAt ? local : remote;
    }
    const updatedByComparison = local.updatedBy.localeCompare(remote.updatedBy);
    if (updatedByComparison !== 0) {
      return updatedByComparison > 0 ? local : remote;
    }
    return JSON.stringify(local.ids).localeCompare(JSON.stringify(remote.ids)) >= 0 ? local : remote;
  }

  private selectOrderSource(
    baseline: AiraSyncBookmarkOrder | undefined,
    local: AiraSyncBookmarkOrder | undefined,
    remote: AiraSyncBookmarkOrder | undefined,
    localChanged: boolean,
    remoteChanged: boolean
  ): AiraSyncBookmarkOrder | undefined {
    if (localChanged && !remoteChanged) {
      return local;
    }
    if (!localChanged && remoteChanged) {
      return remote;
    }
    return this.selectFreshestOrder(local, remote, baseline);
  }

  private resolveDeleteEditConflicts(
    baseline: AiraSyncSnapshot,
    local: AiraSyncSnapshot,
    remote: AiraSyncSnapshot,
    resolution?: AiraBookmarkConflictResolution,
    deletionPolicy: AiraBookmarkMergeDeletionPolicy = 'propagate'
  ): AiraDeleteEditResolution {
    const regularResolution = this.resolveDeleteEditDataSetConflicts(
      {
        bookmarkFolders: baseline.bookmarkFolders,
        bookmarkItems: baseline.bookmarkItems,
        bookmarkOrders: baseline.bookmarkOrders,
        tombstones: baseline.tombstones
      },
      {
        bookmarkFolders: local.bookmarkFolders,
        bookmarkItems: local.bookmarkItems,
        bookmarkOrders: local.bookmarkOrders,
        tombstones: local.tombstones
      },
      {
        bookmarkFolders: remote.bookmarkFolders,
        bookmarkItems: remote.bookmarkItems,
        bookmarkOrders: remote.bookmarkOrders,
        tombstones: remote.tombstones
      },
      resolution,
      deletionPolicy
    );
    const privateResolution = this.resolveDeleteEditDataSetConflicts(
      this.normalizePrivateBookmarkDataSet(baseline),
      this.normalizePrivateBookmarkDataSet(local),
      this.normalizePrivateBookmarkDataSet(remote),
      resolution,
      deletionPolicy
    );
    return {
      conflictDetails: regularResolution.conflictDetails.concat(privateResolution.conflictDetails),
      ignoredTombstoneKeys: regularResolution.ignoredTombstoneKeys,
      ignoredPrivateTombstoneKeys: privateResolution.ignoredTombstoneKeys
    };
  }

  private resolveDeleteEditDataSetConflicts(
    baseline: AiraSyncBookmarkDataSet,
    local: AiraSyncBookmarkDataSet,
    remote: AiraSyncBookmarkDataSet,
    resolution?: AiraBookmarkConflictResolution,
    deletionPolicy: AiraBookmarkMergeDeletionPolicy = 'propagate'
  ): AiraDataSetDeleteEditResolution {
    const conflictDetails: AiraBookmarkMergeConflictDetail[] = [];
    const ignoredTombstoneKeys = new Set<string>();
    const localTombstones = this.buildTombstoneMap(local.tombstones);
    const remoteTombstones = this.buildTombstoneMap(remote.tombstones);
    if (deletionPolicy === 'preserve-live-on-provider-switch') {
      this.ignoreTombstonesOpposedByLiveEntities(
        local.bookmarkFolders,
        remote.bookmarkFolders,
        localTombstones,
        remoteTombstones,
        ignoredTombstoneKeys
      );
      this.ignoreTombstonesOpposedByLiveEntities(
        local.bookmarkItems,
        remote.bookmarkItems,
        localTombstones,
        remoteTombstones,
        ignoredTombstoneKeys
      );
    }
    this.ignoreRemoteTombstonesForRestoredLocalEntities(
      baseline.bookmarkFolders,
      local.bookmarkFolders,
      remote.bookmarkFolders,
      remoteTombstones,
      'bookmark-folder',
      ignoredTombstoneKeys
    );
    this.ignoreRemoteTombstonesForRestoredLocalEntities(
      baseline.bookmarkItems,
      local.bookmarkItems,
      remote.bookmarkItems,
      remoteTombstones,
      'bookmark-item',
      ignoredTombstoneKeys
    );
    this.resolveDeleteEditCollection<AiraSyncBookmarkFolderEntity>(
      baseline.bookmarkFolders,
      local.bookmarkFolders,
      remote.bookmarkFolders,
      localTombstones,
      remoteTombstones,
      'bookmark-folder',
      (left: AiraSyncBookmarkFolderEntity, right: AiraSyncBookmarkFolderEntity): boolean => {
        return left.title === right.title && left.parentId === right.parentId;
      },
      (value: AiraSyncBookmarkFolderEntity): string => value.title,
      (value: AiraSyncBookmarkFolderEntity): string => `名称：${value.title}，父文件夹：${value.parentId ?? '根目录'}`,
      resolution,
      conflictDetails,
      ignoredTombstoneKeys
    );
    this.resolveDeleteEditCollection<AiraSyncBookmarkItemEntity>(
      baseline.bookmarkItems,
      local.bookmarkItems,
      remote.bookmarkItems,
      localTombstones,
      remoteTombstones,
      'bookmark-item',
      (left: AiraSyncBookmarkItemEntity, right: AiraSyncBookmarkItemEntity): boolean => {
        return left.title === right.title && left.url === right.url && left.parentId === right.parentId;
      },
      (value: AiraSyncBookmarkItemEntity): string => value.title,
      (value: AiraSyncBookmarkItemEntity): string => {
        return `标题：${value.title}，网址：${value.url}，父文件夹：${value.parentId ?? '根目录'}`;
      },
      resolution,
      conflictDetails,
      ignoredTombstoneKeys
    );
    return {
      conflictDetails: conflictDetails,
      ignoredTombstoneKeys: ignoredTombstoneKeys
    };
  }

  private ignoreRemoteTombstonesForRestoredLocalEntities<T extends AiraSyncBaseEntity>(
    baselineValues: T[],
    localValues: T[],
    remoteValues: T[],
    remoteTombstones: Map<string, AiraSyncTombstone>,
    entityType: 'bookmark-folder' | 'bookmark-item',
    ignoredTombstoneKeys: Set<string>
  ): void {
    const baselineById = this.buildValueMap(baselineValues, (value: T): string => value.id);
    const remoteIds = new Set<string>();
    remoteValues.forEach((value: T): void => {
      remoteIds.add(value.id);
    });
    localValues.forEach((value: T): void => {
      const baselineValue = baselineById.get(value.id);
      const isLocalBackupRestore = this.isLocalBackupImportActor(value.updatedBy);
      const alreadyRecordedAsRestore = baselineValue !== undefined &&
        baselineValue.updatedBy === value.updatedBy;
      if (isLocalBackupRestore && !alreadyRecordedAsRestore &&
        !remoteIds.has(value.id) &&
        remoteTombstones.has(`${entityType}|${value.id}`)) {
        ignoredTombstoneKeys.add(`${entityType}|${value.id}`);
      }
    });
  }

  private isLocalBackupImportActor(actor: string): boolean {
    return actor === AIRA_LOCAL_BACKUP_IMPORT_ACTOR ||
      actor.startsWith(`${AIRA_LOCAL_BACKUP_IMPORT_ACTOR}-`);
  }

  private resolveDeleteEditCollection<T extends AiraSyncBaseEntity>(
    baselineValues: T[],
    localValues: T[],
    remoteValues: T[],
    localTombstones: Map<string, AiraSyncTombstone>,
    remoteTombstones: Map<string, AiraSyncTombstone>,
    entityType: 'bookmark-folder' | 'bookmark-item',
    equals: (left: T, right: T) => boolean,
    titleOf: (value: T) => string,
    describe: (value: T) => string,
    resolution: AiraBookmarkConflictResolution | undefined,
    conflictDetails: AiraBookmarkMergeConflictDetail[],
    ignoredTombstoneKeys: Set<string>
  ): void {
    const baselineById = this.buildValueMap(baselineValues, (value: T): string => value.id);
    const localById = this.buildValueMap(localValues, (value: T): string => value.id);
    const remoteById = this.buildValueMap(remoteValues, (value: T): string => value.id);
    baselineById.forEach((baseline: T, id: string): void => {
      const tombstoneKey = `${entityType}|${id}`;
      const localTombstone = localTombstones.get(tombstoneKey);
      const remoteTombstone = remoteTombstones.get(tombstoneKey);
      const localValue = localById.get(id);
      const remoteValue = remoteById.get(id);
      if (ignoredTombstoneKeys.has(tombstoneKey)) {
        return;
      }
      if (localTombstone !== undefined && remoteValue !== undefined && !equals(baseline, remoteValue)) {
        if (resolution === 'prefer-remote') {
          ignoredTombstoneKeys.add(tombstoneKey);
          return;
        }
        if (resolution !== 'prefer-local') {
          conflictDetails.push({
            id,
            type: entityType,
            title: titleOf(remoteValue),
            localValue: '本机已删除',
            remoteValue: describe(remoteValue)
          });
        }
        return;
      }
      if (remoteTombstone !== undefined && localValue !== undefined && !equals(baseline, localValue)) {
        if (resolution === 'prefer-local') {
          ignoredTombstoneKeys.add(tombstoneKey);
          return;
        }
        if (resolution !== 'prefer-remote') {
          conflictDetails.push({
            id,
            type: entityType,
            title: titleOf(localValue),
            localValue: describe(localValue),
            remoteValue: '同步源已删除'
          });
        }
      }
    });
  }

  private ignoreTombstonesOpposedByLiveEntities<T extends AiraSyncBaseEntity>(
    localValues: T[],
    remoteValues: T[],
    localTombstones: Map<string, AiraSyncTombstone>,
    remoteTombstones: Map<string, AiraSyncTombstone>,
    ignoredTombstoneKeys: Set<string>
  ): void {
    remoteValues.forEach((value: T): void => {
      this.ignoreTombstonesForLiveEntityId(value.id, localTombstones, ignoredTombstoneKeys);
    });
    localValues.forEach((value: T): void => {
      this.ignoreTombstonesForLiveEntityId(value.id, remoteTombstones, ignoredTombstoneKeys);
    });
  }

  private ignoreTombstonesForLiveEntityId(
    entityId: string,
    tombstones: Map<string, AiraSyncTombstone>,
    ignoredTombstoneKeys: Set<string>
  ): void {
    const folderKey = `bookmark-folder|${entityId}`;
    const itemKey = `bookmark-item|${entityId}`;
    if (tombstones.has(folderKey)) {
      ignoredTombstoneKeys.add(folderKey);
    }
    if (tombstones.has(itemKey)) {
      ignoredTombstoneKeys.add(itemKey);
    }
  }

  private buildIgnoredEntityIdSet(ignoredTombstoneKeys: Set<string>): Set<string> {
    const entityIds = new Set<string>();
    ignoredTombstoneKeys.forEach((key: string): void => {
      const separatorIndex = key.indexOf('|');
      if (separatorIndex >= 0 && separatorIndex < key.length - 1) {
        entityIds.add(key.slice(separatorIndex + 1));
      }
    });
    return entityIds;
  }

  private buildTombstoneMap(values: AiraSyncTombstone[]): Map<string, AiraSyncTombstone> {
    const result = new Map<string, AiraSyncTombstone>();
    values.forEach((value: AiraSyncTombstone): void => {
      result.set(this.bookmarkTombstoneKey(value), value);
    });
    return result;
  }

  private bookmarkTombstoneKey(value: AiraSyncTombstone): string {
    return `${value.type}|${value.id}`;
  }

  private sameBookmarkTombstone(left: AiraSyncTombstone, right: AiraSyncTombstone): boolean {
    return left.id === right.id && left.type === right.type && left.deletedAt === right.deletedAt &&
      left.deletedBy === right.deletedBy && left.lastKnownRevision === right.lastKnownRevision;
  }

  private selectFreshestTombstone(
    left: AiraSyncTombstone | undefined,
    right: AiraSyncTombstone | undefined
  ): AiraSyncTombstone | undefined {
    if (left === undefined) {
      return right;
    }
    if (right === undefined) {
      return left;
    }
    const leftDeletedAt = this.toMs(left.deletedAt);
    const rightDeletedAt = this.toMs(right.deletedAt);
    if (leftDeletedAt !== rightDeletedAt) {
      return leftDeletedAt > rightDeletedAt ? left : right;
    }
    if (left.lastKnownRevision !== right.lastKnownRevision) {
      return left.lastKnownRevision > right.lastKnownRevision ? left : right;
    }
    return left.deletedBy.localeCompare(right.deletedBy) >= 0 ? left : right;
  }

  private selectFreshestFolder(
    local: AiraSyncBookmarkFolderEntity | undefined,
    remote: AiraSyncBookmarkFolderEntity | undefined
  ): AiraSyncBookmarkFolderEntity | undefined {
    if (local === undefined) {
      return remote;
    }
    if (remote === undefined) {
      return local;
    }
    if (local.revision !== remote.revision) {
      return local.revision > remote.revision ? local : remote;
    }
    return this.toMs(local.updatedAt) >= this.toMs(remote.updatedAt) ? local : remote;
  }

  private selectFreshestItem(
    local: AiraSyncBookmarkItemEntity | undefined,
    remote: AiraSyncBookmarkItemEntity | undefined
  ): AiraSyncBookmarkItemEntity | undefined {
    if (local === undefined) {
      return remote;
    }
    if (remote === undefined) {
      return local;
    }
    if (local.revision !== remote.revision) {
      return local.revision > remote.revision ? local : remote;
    }
    return this.toMs(local.updatedAt) >= this.toMs(remote.updatedAt) ? local : remote;
  }

  private resolveLatestIso(values: Array<string | undefined>): string {
    let latest = '';
    values.forEach((value: string | undefined) => {
      if (value !== undefined && (latest.length === 0 || this.toMs(value) >= this.toMs(latest))) {
        latest = value;
      }
    });
    return latest.length > 0 ? latest : new Date().toISOString();
  }

  private orderMatchesEitherSide(mergedIds: string[], localIds: string[], remoteIds: string[]): boolean {
    return this.sameStringArray(mergedIds, localIds) || this.sameStringArray(mergedIds, remoteIds);
  }

  private sameBookmarkFolders(
    left: AiraSyncBookmarkFolderEntity[],
    right: AiraSyncBookmarkFolderEntity[],
    requireCanonicalRevision: boolean = true,
    requireCanonicalMetadata: boolean = true,
    requireCanonicalTimestampText: boolean = true
  ): boolean {
    if (left.length !== right.length) {
      return false;
    }
    const rightById = this.buildValueMap(right, (value: AiraSyncBookmarkFolderEntity) => value.id);
    for (let index = 0; index < left.length; index += 1) {
      const folder = left[index];
      const other = rightById.get(folder.id);
      if (other === undefined || folder.parentId !== other.parentId || folder.title !== other.title ||
        (requireCanonicalMetadata && (!this.sameTimestamp(
          folder.createdAt,
          other.createdAt,
          requireCanonicalTimestampText
        ) || !this.sameTimestamp(folder.updatedAt, other.updatedAt, requireCanonicalTimestampText) ||
          folder.updatedBy !== other.updatedBy)) ||
        (requireCanonicalRevision && folder.revision !== other.revision)) {
        return false;
      }
    }
    return true;
  }

  private sameBookmarkItems(
    left: AiraSyncBookmarkItemEntity[],
    right: AiraSyncBookmarkItemEntity[],
    requireCanonicalRevision: boolean = true,
    requireCanonicalMetadata: boolean = true,
    requireCanonicalTimestampText: boolean = true
  ): boolean {
    if (left.length !== right.length) {
      return false;
    }
    const rightById = this.buildValueMap(right, (value: AiraSyncBookmarkItemEntity) => value.id);
    for (let index = 0; index < left.length; index += 1) {
      const item = left[index];
      const other = rightById.get(item.id);
      if (other === undefined || item.parentId !== other.parentId || item.title !== other.title ||
        item.url !== other.url || (requireCanonicalMetadata && (!this.sameTimestamp(
          item.createdAt,
          other.createdAt,
          requireCanonicalTimestampText
        ) || !this.sameTimestamp(item.updatedAt, other.updatedAt, requireCanonicalTimestampText) ||
          item.updatedBy !== other.updatedBy)) ||
        (requireCanonicalRevision && item.revision !== other.revision)) {
        return false;
      }
    }
    return true;
  }

  private sameBookmarkOrders(
    left: AiraSyncBookmarkOrder[],
    right: AiraSyncBookmarkOrder[],
    requireCanonicalMetadata: boolean = true
  ): boolean {
    if (left.length !== right.length) {
      return false;
    }
    const rightByKey = this.buildValueMap(right, (value: AiraSyncBookmarkOrder) => this.bookmarkOrderKey(value));
    for (let index = 0; index < left.length; index += 1) {
      const order = left[index];
      const other = rightByKey.get(this.bookmarkOrderKey(order));
      if (other === undefined || !this.sameStringArray(order.ids, other.ids) ||
        (requireCanonicalMetadata && (order.updatedAt !== other.updatedAt || order.updatedBy !== other.updatedBy ||
          order.revision !== other.revision))) {
        return false;
      }
    }
    return true;
  }

  private sameMaterializedBookmarkOrders(
    left: AiraSyncBookmarkOrder[],
    right: AiraSyncBookmarkOrder[]
  ): boolean {
    const leftNonEmpty = left.filter((order: AiraSyncBookmarkOrder): boolean => order.ids.length > 0);
    const rightNonEmpty = right.filter((order: AiraSyncBookmarkOrder): boolean => order.ids.length > 0);
    return this.sameBookmarkOrders(leftNonEmpty, rightNonEmpty, false);
  }

  private sameTimestamp(left: string, right: string, requireCanonicalText: boolean): boolean {
    return requireCanonicalText ? left === right : this.toMs(left) === this.toMs(right);
  }

  private sameBookmarkTombstones(left: AiraSyncTombstone[], right: AiraSyncTombstone[]): boolean {
    if (left.length !== right.length) {
      return false;
    }
    const rightByKey = this.buildValueMap(right, (value: AiraSyncTombstone) => this.bookmarkTombstoneKey(value));
    for (let index = 0; index < left.length; index += 1) {
      const tombstone = left[index];
      const other = rightByKey.get(this.bookmarkTombstoneKey(tombstone));
      if (other === undefined || !this.sameBookmarkTombstone(tombstone, other)) {
        return false;
      }
    }
    return true;
  }

  private toStringSet(values: string[]): Set<string> {
    const set = new Set<string>();
    values.forEach((value: string) => set.add(value));
    return set;
  }

  private async toStringSetCooperatively(
    values: string[],
    throttle: AiraSyncWorkThrottleService
  ): Promise<Set<string>> {
    const set = new Set<string>();
    for (let index = 0; index < values.length; index += 1) {
      set.add(values[index]);
      await throttle.afterBatchItem(index + 1);
    }
    return set;
  }

  private toMs(value: string): number {
    const timestamp = Date.parse(value);
    return Number.isFinite(timestamp) ? timestamp : 0;
  }

  private resolveConflictType<T>(value: T): 'bookmark-folder' | 'bookmark-item' | 'bookmark-order' {
    const type = (value as Record<string, string>)['type'];
    if (type === 'bookmark-folder' || type === 'bookmark-item' || type === 'bookmark-order') {
      return type;
    }
    return 'bookmark-item';
  }

  private countSnapshotEntities(snapshot: AiraSyncSnapshot): number {
    let bookmarkTombstoneCount = 0;
    snapshot.tombstones.forEach((entry: AiraSyncTombstone) => {
      if (this.isBookmarkTombstone(entry)) {
        bookmarkTombstoneCount += 1;
      }
    });
    const privateDataSet = this.normalizePrivateBookmarkDataSet(snapshot);
    let privateTombstoneCount = 0;
    privateDataSet.tombstones.forEach((entry: AiraSyncTombstone) => {
      if (this.isBookmarkTombstone(entry)) {
        privateTombstoneCount += 1;
      }
    });
    return snapshot.bookmarkFolders.length + snapshot.bookmarkItems.length + snapshot.bookmarkOrders.length +
      bookmarkTombstoneCount + privateDataSet.bookmarkFolders.length + privateDataSet.bookmarkItems.length +
      privateDataSet.bookmarkOrders.length + privateTombstoneCount;
  }

  private filterBookmarkTombstones(values: AiraSyncTombstone[]): AiraSyncTombstone[] {
    return values.filter((entry: AiraSyncTombstone) => this.isBookmarkTombstone(entry));
  }

  private normalizePrivateBookmarkDataSet(snapshot: AiraSyncSnapshot): AiraSyncBookmarkDataSet {
    const dataSet = snapshot.appPrivateBookmarks;
    if (dataSet === undefined) {
      return {
        bookmarkFolders: [],
        bookmarkItems: [],
        bookmarkOrders: [],
        tombstones: []
      };
    }
    return {
      bookmarkFolders: dataSet.bookmarkFolders ?? [],
      bookmarkItems: dataSet.bookmarkItems ?? [],
      bookmarkOrders: dataSet.bookmarkOrders ?? [],
      tombstones: dataSet.tombstones ?? []
    };
  }

  private isBookmarkTombstone(entry: AiraSyncTombstone): boolean {
    return entry.type === 'bookmark-folder' || entry.type === 'bookmark-item';
  }

  private buildDeletedEntityIdSet(tombstones: AiraSyncTombstone[], type: string): Set<string> {
    const ids = new Set<string>();
    tombstones.forEach((entry: AiraSyncTombstone) => {
      if (entry.type === type) {
        ids.add(entry.id);
      }
    });
    return ids;
  }

  private filterTombstonesOpposedBySurvivingLiveEntities(
    tombstones: AiraSyncTombstone[],
    liveFolders: AiraSyncBookmarkFolderEntity[],
    liveItems: AiraSyncBookmarkItemEntity[]
  ): AiraSyncTombstone[] {
    const liveFolderIds = this.toFolderIdSet(liveFolders);
    const liveItemIds = this.toItemIdSet(liveItems);
    return tombstones.filter((entry: AiraSyncTombstone): boolean => {
      return entry.type === 'bookmark-folder'
        ? !liveItemIds.has(entry.id)
        : !liveFolderIds.has(entry.id);
    });
  }

  private collectEntityIds(
    folders: AiraSyncBookmarkFolderEntity[],
    items: AiraSyncBookmarkItemEntity[]
  ): Set<string> {
    const ids = new Set<string>();
    folders.forEach((folder: AiraSyncBookmarkFolderEntity) => ids.add(folder.id));
    items.forEach((item: AiraSyncBookmarkItemEntity) => ids.add(item.id));
    return ids;
  }

  private async collectEntityIdsCooperatively(
    folders: AiraSyncBookmarkFolderEntity[],
    items: AiraSyncBookmarkItemEntity[],
    throttle: AiraSyncWorkThrottleService
  ): Promise<Set<string>> {
    const ids = new Set<string>();
    await this.addFolderIdsCooperatively(folders, ids, throttle);
    await this.addItemIdsCooperatively(items, ids, throttle);
    return ids;
  }

  private async filterLiveFoldersCooperatively(
    folders: AiraSyncBookmarkFolderEntity[],
    deletedFolderIds: Set<string>,
    throttle: AiraSyncWorkThrottleService
  ): Promise<AiraSyncBookmarkFolderEntity[]> {
    const result: AiraSyncBookmarkFolderEntity[] = [];
    for (let index = 0; index < folders.length; index += 1) {
      const folder = folders[index];
      if (!deletedFolderIds.has(folder.id)) {
        result.push(folder);
      }
      await throttle.afterBatchItem(index + 1);
    }
    return result;
  }

  private async filterLiveItemsCooperatively(
    items: AiraSyncBookmarkItemEntity[],
    deletedItemIds: Set<string>,
    throttle: AiraSyncWorkThrottleService
  ): Promise<AiraSyncBookmarkItemEntity[]> {
    const result: AiraSyncBookmarkItemEntity[] = [];
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      if (!deletedItemIds.has(item.id)) {
        result.push(item);
      }
      await throttle.afterBatchItem(index + 1);
    }
    return result;
  }

  private filterOrdersByLiveIds(
    orders: AiraSyncBookmarkOrder[],
    folders: AiraSyncBookmarkFolderEntity[],
    items: AiraSyncBookmarkItemEntity[],
    liveEntityIds: Set<string>,
    deviceId: string,
    generatedAt: string
  ): AiraSyncBookmarkOrder[] {
    const folderIds = new Set<string>();
    folders.forEach((folder: AiraSyncBookmarkFolderEntity) => folderIds.add(folder.id));
    const result: AiraSyncBookmarkOrder[] = [];
    orders.forEach((order: AiraSyncBookmarkOrder) => {
      if (order.parentId !== null && !folderIds.has(order.parentId)) {
        return;
      }
      const ids: string[] = [];
      order.ids.forEach((id: string) => {
        if (liveEntityIds.has(id)) {
          ids.push(id);
        }
      });
      result.push({
        type: order.type,
        parentId: order.parentId,
        ids: ids,
        updatedAt: order.updatedAt,
        updatedBy: order.updatedBy,
        revision: order.revision
      });
    });
    return this.ensureOrderedCoverage(result, folders, items, deviceId, generatedAt);
  }

  // Every live folder/item must be placed in its parent's order. A merge can
  // introduce live entities that neither side's order lists (for example the same
  // bookmark stored under two installation-scoped IDs), and canonical validation
  // rejects a snapshot with unordered live entities. This retains those
  // otherwise-unplaced entities instead of dropping them.
  private ensureOrderedCoverage(
    orders: AiraSyncBookmarkOrder[],
    folders: AiraSyncBookmarkFolderEntity[],
    items: AiraSyncBookmarkItemEntity[],
    deviceId: string,
    generatedAt: string
  ): AiraSyncBookmarkOrder[] {
    const folderById = new Map<string, AiraSyncBookmarkFolderEntity>();
    folders.forEach((folder: AiraSyncBookmarkFolderEntity) => folderById.set(folder.id, folder));
    const childIdsByParent = new Map<string, string[]>();
    const addChild = (parentId: string | null, id: string): void => {
      const key = parentId === null ? '' : parentId;
      const current = childIdsByParent.get(key);
      if (current !== undefined) {
        current.push(id);
        return;
      }
      childIdsByParent.set(key, [id]);
    };
    folders.forEach((folder: AiraSyncBookmarkFolderEntity) => addChild(folder.parentId, folder.id));
    items.forEach((item: AiraSyncBookmarkItemEntity) => addChild(item.parentId, item.id));

    const orderByKey = new Map<string, AiraSyncBookmarkOrder>();
    orders.forEach((order: AiraSyncBookmarkOrder) => orderByKey.set(order.parentId === null ? '' : order.parentId, order));

    const keys = new Set<string>();
    orderByKey.forEach((_order: AiraSyncBookmarkOrder, key: string) => keys.add(key));
    childIdsByParent.forEach((_ids: string[], key: string) => keys.add(key));

    const placed = new Set<string>();
    const result: AiraSyncBookmarkOrder[] = [];
    keys.forEach((key: string) => {
      const parentId = key === '' ? null : key;
      if (parentId !== null && !folderById.has(parentId)) {
        return;
      }
      const children = childIdsByParent.get(key) ?? [];
      const childSet = new Set<string>();
      children.forEach((id: string) => childSet.add(id));
      const ids: string[] = [];
      const existing = orderByKey.get(key);
      if (existing !== undefined) {
        existing.ids.forEach((id: string) => {
          if (childSet.has(id) && !placed.has(id)) {
            ids.push(id);
            placed.add(id);
          }
        });
      }
      children.forEach((id: string) => {
        if (!placed.has(id)) {
          ids.push(id);
          placed.add(id);
        }
      });
      let updatedAt: string;
      let updatedBy: string;
      let revision: number;
      if (existing !== undefined) {
        updatedAt = existing.updatedAt;
        updatedBy = existing.updatedBy;
        revision = existing.revision;
      } else {
        const synthesized: AiraSynthOrderMeta = this.synthesizeOrderMeta(parentId, folderById, deviceId, generatedAt);
        updatedAt = synthesized.updatedAt;
        updatedBy = synthesized.updatedBy;
        revision = synthesized.revision;
      }
      result.push({
        type: 'bookmark-order',
        parentId: parentId,
        ids: ids,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
        revision: revision
      });
    });
    return result;
  }

  private synthesizeOrderMeta(
    parentId: string | null,
    folderById: Map<string, AiraSyncBookmarkFolderEntity>,
    deviceId: string,
    generatedAt: string
  ): AiraSynthOrderMeta {
    if (parentId !== null) {
      const folder = folderById.get(parentId);
      if (folder !== undefined) {
        return { updatedAt: folder.updatedAt, updatedBy: folder.updatedBy, revision: folder.revision };
      }
    }
    let newest: AiraSyncBookmarkFolderEntity | null = null;
    folderById.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      if (newest === null || folder.updatedAt > newest.updatedAt) {
        newest = folder;
      }
    });
    if (newest !== null) {
      const chosen: AiraSyncBookmarkFolderEntity = newest;
      return { updatedAt: chosen.updatedAt, updatedBy: chosen.updatedBy, revision: chosen.revision };
    }
    return { updatedAt: generatedAt, updatedBy: deviceId, revision: 1 };
  }

  private async filterOrdersByLiveIdsCooperatively(
    orders: AiraSyncBookmarkOrder[],
    folders: AiraSyncBookmarkFolderEntity[],
    items: AiraSyncBookmarkItemEntity[],
    liveEntityIds: Set<string>,
    deviceId: string,
    generatedAt: string,
    throttle: AiraSyncWorkThrottleService
  ): Promise<AiraSyncBookmarkOrder[]> {
    const folderIds = new Set<string>();
    for (let index = 0; index < folders.length; index += 1) {
      folderIds.add(folders[index].id);
      await throttle.afterBatchItem(index + 1);
    }
    const result: AiraSyncBookmarkOrder[] = [];
    for (let orderIndex = 0; orderIndex < orders.length; orderIndex += 1) {
      const order = orders[orderIndex];
      if (order.parentId !== null && !folderIds.has(order.parentId)) {
        await throttle.afterBatchItem(orderIndex + 1);
        continue;
      }
      const ids: string[] = [];
      for (let idIndex = 0; idIndex < order.ids.length; idIndex += 1) {
        const id = order.ids[idIndex];
        if (liveEntityIds.has(id)) {
          ids.push(id);
        }
        await throttle.afterBatchItem(idIndex + 1);
      }
      result.push({
        type: order.type,
        parentId: order.parentId,
        ids: ids,
        updatedAt: order.updatedAt,
        updatedBy: order.updatedBy,
        revision: order.revision
      });
      await throttle.afterBatchItem(orderIndex + 1);
    }
    return this.ensureOrderedCoverage(result, folders, items, deviceId, generatedAt);
  }
}

interface AiraSynthOrderMeta {
  updatedAt: string;
  updatedBy: string;
  revision: number;
}

interface AiraMergeCollectionResult<T> {
  values: T[];
  conflictCount: number;
  localChangeCount: number;
  remoteChangeCount: number;
  conflictDetails: AiraBookmarkMergeConflictDetail[];
}

interface AiraPrivateBookmarkMergeResult {
  dataSet: AiraSyncBookmarkDataSet;
  localChangeCount: number;
  remoteChangeCount: number;
}

interface AiraDeleteEditResolution {
  conflictDetails: AiraBookmarkMergeConflictDetail[];
  ignoredTombstoneKeys: Set<string>;
  ignoredPrivateTombstoneKeys: Set<string>;
}

interface AiraDataSetDeleteEditResolution {
  conflictDetails: AiraBookmarkMergeConflictDetail[];
  ignoredTombstoneKeys: Set<string>;
}
