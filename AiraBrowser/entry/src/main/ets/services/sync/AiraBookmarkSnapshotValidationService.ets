import {
  AIRA_SYNC_SCHEMA_VERSION,
  AiraSyncBaseEntity,
  AiraSyncBookmarkDataSet,
  AiraSyncBookmarkFolderEntity,
  AiraSyncBookmarkItemEntity,
  AiraSyncBookmarkOrder,
  AiraSyncSnapshot,
  AiraSyncTombstone
} from '../../common/models/AiraSyncModels';

export class AiraBookmarkSnapshotValidationService {
  validate(snapshot: AiraSyncSnapshot, sourceLabel: string): AiraSyncSnapshot {
    if (!this.isValidSnapshot(snapshot)) {
      throw new Error(`${sourceLabel}书签同步快照格式无效。`);
    }
    return snapshot;
  }

  private isValidSnapshot(snapshot: AiraSyncSnapshot): boolean {
    if (snapshot === undefined || snapshot === null || typeof snapshot !== 'object' ||
      snapshot.meta === undefined || snapshot.meta === null ||
      snapshot.meta.version !== AIRA_SYNC_SCHEMA_VERSION ||
      !this.isNonEmptyString(snapshot.meta.deviceId) ||
      !this.isNonEmptyString(snapshot.meta.generatedAt) ||
      !this.isValidDataSet(snapshot)) {
      return false;
    }
    if (snapshot.appPrivateBookmarks === undefined) {
      return true;
    }
    return this.isValidDataSet(snapshot.appPrivateBookmarks) &&
      !this.hasPartitionIdentityOverlap(snapshot, snapshot.appPrivateBookmarks);
  }

  private isValidDataSet(dataSet: AiraSyncBookmarkDataSet | AiraSyncSnapshot): boolean {
    if (!Array.isArray(dataSet.bookmarkFolders) ||
      !Array.isArray(dataSet.bookmarkItems) ||
      !Array.isArray(dataSet.bookmarkOrders) ||
      !Array.isArray(dataSet.tombstones) ||
      !this.hasValidUniqueValues<AiraSyncBookmarkFolderEntity>(
        dataSet.bookmarkFolders,
        (value: AiraSyncBookmarkFolderEntity) => this.isValidFolder(value),
        (value: AiraSyncBookmarkFolderEntity) => value.id
      ) ||
      !this.hasValidUniqueValues<AiraSyncBookmarkItemEntity>(
        dataSet.bookmarkItems,
        (value: AiraSyncBookmarkItemEntity) => this.isValidItem(value),
        (value: AiraSyncBookmarkItemEntity) => value.id
      ) ||
      !this.hasValidUniqueValues<AiraSyncBookmarkOrder>(
        dataSet.bookmarkOrders,
        (value: AiraSyncBookmarkOrder) => this.isValidOrder(value),
        (value: AiraSyncBookmarkOrder) => value.parentId ?? '__root__'
      ) ||
      !this.hasValidUniqueValues<AiraSyncTombstone>(
        dataSet.tombstones,
        (value: AiraSyncTombstone) => this.isValidTombstone(value),
        (value: AiraSyncTombstone) => `${value.type}|${value.id}`
      )) {
      return false;
    }
    const folderIds = new Set<string>();
    dataSet.bookmarkFolders.forEach((value: AiraSyncBookmarkFolderEntity): void => {
      folderIds.add(value.id);
    });
    const itemIds = new Set<string>();
    dataSet.bookmarkItems.forEach((value: AiraSyncBookmarkItemEntity): void => {
      itemIds.add(value.id);
    });
    if (Array.from(itemIds.values()).some((id: string): boolean => folderIds.has(id))) {
      return false;
    }
    if (dataSet.tombstones.some((value: AiraSyncTombstone): boolean => {
      return folderIds.has(value.id) || itemIds.has(value.id);
    })) {
      return false;
    }
    return this.hasValidBookmarkTree(dataSet, folderIds, itemIds);
  }

  private hasValidBookmarkTree(
    dataSet: AiraSyncBookmarkDataSet | AiraSyncSnapshot,
    folderIds: Set<string>,
    itemIds: Set<string>
  ): boolean {
    const parentIdByEntityId = new Map<string, string | null>();
    for (let index = 0; index < dataSet.bookmarkFolders.length; index += 1) {
      const folder = dataSet.bookmarkFolders[index];
      if (folder.parentId !== null && !folderIds.has(folder.parentId)) {
        return false;
      }
      parentIdByEntityId.set(folder.id, folder.parentId);
    }
    for (let index = 0; index < dataSet.bookmarkItems.length; index += 1) {
      const item = dataSet.bookmarkItems[index];
      if (item.parentId !== null && !folderIds.has(item.parentId)) {
        return false;
      }
      parentIdByEntityId.set(item.id, item.parentId);
    }

    const orderedEntityIds = new Set<string>();
    const orderIdsByParent = new Map<string, string[]>();
    for (let orderIndex = 0; orderIndex < dataSet.bookmarkOrders.length; orderIndex += 1) {
      const order = dataSet.bookmarkOrders[orderIndex];
      if (order.parentId !== null && !folderIds.has(order.parentId)) {
        return false;
      }
      const orderKey = order.parentId === null ? '__root__' : order.parentId;
      orderIdsByParent.set(orderKey, order.ids);
      for (let idIndex = 0; idIndex < order.ids.length; idIndex += 1) {
        const id = order.ids[idIndex];
        if ((!folderIds.has(id) && !itemIds.has(id)) || orderedEntityIds.has(id) ||
          parentIdByEntityId.get(id) !== order.parentId) {
          return false;
        }
        orderedEntityIds.add(id);
      }
    }
    if (orderedEntityIds.size !== folderIds.size + itemIds.size) {
      return false;
    }

    const reachableEntityIds = new Set<string>();
    const pendingIds = (orderIdsByParent.get('__root__') ?? []).slice();
    for (let index = 0; index < pendingIds.length; index += 1) {
      const id = pendingIds[index];
      if (reachableEntityIds.has(id)) {
        continue;
      }
      reachableEntityIds.add(id);
      if (folderIds.has(id)) {
        const childIds = orderIdsByParent.get(id) ?? [];
        childIds.forEach((childId: string): void => {
          pendingIds.push(childId);
        });
      }
    }
    return reachableEntityIds.size === folderIds.size + itemIds.size;
  }

  private hasPartitionIdentityOverlap(
    shared: AiraSyncBookmarkDataSet | AiraSyncSnapshot,
    appPrivate: AiraSyncBookmarkDataSet
  ): boolean {
    const sharedIds = this.collectDataSetIdentityIds(shared);
    const privateIds = this.collectDataSetIdentityIds(appPrivate);
    return Array.from(privateIds.values()).some((id: string): boolean => sharedIds.has(id));
  }

  private collectDataSetIdentityIds(dataSet: AiraSyncBookmarkDataSet | AiraSyncSnapshot): Set<string> {
    const ids = new Set<string>();
    dataSet.bookmarkFolders.forEach((value: AiraSyncBookmarkFolderEntity): void => {
      ids.add(value.id);
    });
    dataSet.bookmarkItems.forEach((value: AiraSyncBookmarkItemEntity): void => {
      ids.add(value.id);
    });
    dataSet.tombstones.forEach((value: AiraSyncTombstone): void => {
      ids.add(value.id);
    });
    return ids;
  }

  private hasValidUniqueValues<T extends Object>(
    values: T[],
    isValid: (value: T) => boolean,
    keyOf: (value: T) => string
  ): boolean {
    const keys = new Set<string>();
    for (let index = 0; index < values.length; index += 1) {
      const value = values[index];
      const key = keyOf(value);
      if (!isValid(value) || keys.has(key)) {
        return false;
      }
      keys.add(key);
    }
    return true;
  }

  private isValidFolder(value: AiraSyncBookmarkFolderEntity): boolean {
    return value !== undefined && value !== null && typeof value === 'object' &&
      value.type === 'bookmark-folder' &&
      this.isValidBaseEntity(value) &&
      this.isValidParentId(value.parentId) &&
      typeof value.title === 'string';
  }

  private isValidItem(value: AiraSyncBookmarkItemEntity): boolean {
    return value !== undefined && value !== null && typeof value === 'object' &&
      value.type === 'bookmark-item' &&
      this.isValidBaseEntity(value) &&
      this.isValidParentId(value.parentId) &&
      typeof value.title === 'string' &&
      typeof value.url === 'string';
  }

  private isValidBaseEntity(value: AiraSyncBaseEntity): boolean {
    return this.isNonEmptyString(value.id) &&
      this.isNonEmptyString(value.createdAt) &&
      this.isNonEmptyString(value.updatedAt) &&
      this.isNonEmptyString(value.updatedBy) &&
      this.isNonNegativeInteger(value.revision);
  }

  private isValidOrder(value: AiraSyncBookmarkOrder): boolean {
    if (value === undefined || value === null || typeof value !== 'object' ||
      value.type !== 'bookmark-order' || !this.isValidParentId(value.parentId) ||
      !Array.isArray(value.ids) || !this.isNonEmptyString(value.updatedAt) ||
      !this.isNonEmptyString(value.updatedBy) || !this.isNonNegativeInteger(value.revision)) {
      return false;
    }
    const ids = new Set<string>();
    for (let index = 0; index < value.ids.length; index += 1) {
      const id = value.ids[index];
      if (!this.isNonEmptyString(id) || ids.has(id)) {
        return false;
      }
      ids.add(id);
    }
    return true;
  }

  private isValidTombstone(value: AiraSyncTombstone): boolean {
    return value !== undefined && value !== null && typeof value === 'object' &&
      this.isNonEmptyString(value.id) &&
      (value.type === 'bookmark-folder' || value.type === 'bookmark-item') &&
      this.isValidTimestamp(value.deletedAt) &&
      this.isNonEmptyString(value.deletedBy) &&
      this.isNonNegativeInteger(value.lastKnownRevision);
  }

  private isValidTimestamp(value: string): boolean {
    return this.isNonEmptyString(value) && Number.isFinite(Date.parse(value));
  }

  private isValidParentId(value: string | null): boolean {
    return value === null || this.isNonEmptyString(value);
  }

  private isNonEmptyString(value: string | undefined): boolean {
    return typeof value === 'string' && value.trim().length > 0;
  }

  private isNonNegativeInteger(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 && Math.floor(value) === value;
  }
}
