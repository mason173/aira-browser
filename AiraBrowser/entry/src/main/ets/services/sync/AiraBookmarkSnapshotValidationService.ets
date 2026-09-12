import { hilog } from '@kit.PerformanceAnalysisKit';
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

const VALIDATION_LOG_DOMAIN: number = 0x0000;
const VALIDATION_LOG_TAG: string = 'AiraBookmarkSnapshot';

export class AiraBookmarkSnapshotValidationService {
  validate(snapshot: AiraSyncSnapshot, sourceLabel: string): AiraSyncSnapshot {
    if (!this.isValidSnapshot(snapshot)) {
      // Diagnostics only: surface which rule failed and on which record so a
      // failing sync identifies the offending data instead of just "invalid".
      const detail = this.describeInvalidSnapshot(snapshot);
      hilog.error(
        VALIDATION_LOG_DOMAIN,
        VALIDATION_LOG_TAG,
        'snapshot invalid source=%{public}s metaVersion=%{public}d deviceId=%{public}s generatedAt=%{public}s detail=%{public}s',
        sourceLabel,
        snapshot?.meta?.version ?? -1,
        String(snapshot?.meta?.deviceId ?? ''),
        String(snapshot?.meta?.generatedAt ?? ''),
        detail
      );
      throw new Error(`${sourceLabel}书签同步快照格式无效。${detail}`);
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

  private describeInvalidSnapshot(snapshot: AiraSyncSnapshot): string {
    if (snapshot === undefined || snapshot === null || typeof snapshot !== 'object') {
      return '[快照为空或不是对象]';
    }
    const meta = snapshot.meta;
    if (meta === undefined || meta === null || typeof meta !== 'object') {
      return '[meta 缺失]';
    }
    const reasons: string[] = [];
    if (meta.version !== AIRA_SYNC_SCHEMA_VERSION) {
      reasons.push(`meta.version=${meta.version}(期望${AIRA_SYNC_SCHEMA_VERSION})`);
    }
    if (!this.isNonEmptyString(meta.deviceId)) {
      reasons.push('meta.deviceId为空');
    }
    if (!this.isNonEmptyString(meta.generatedAt)) {
      reasons.push('meta.generatedAt为空');
    }
    reasons.push(this.describeDataSet('共享', snapshot));
    if (snapshot.appPrivateBookmarks !== undefined) {
      reasons.push(this.describeDataSet('私有', snapshot.appPrivateBookmarks));
      const sharedIds = this.collectDataSetIdentityIds(snapshot);
      const privateIds = this.collectDataSetIdentityIds(snapshot.appPrivateBookmarks);
      const overlap = Array.from(privateIds.values()).find((id: string): boolean => sharedIds.has(id));
      if (overlap !== undefined) {
        reasons.push(`共享/私有分区ID重叠=${overlap}`);
      }
    }
    const text = reasons.filter((entry: string): boolean => entry.length > 0).join('; ');
    return `[${this.truncateDiagnostic(text)}]`;
  }

  private describeDataSet(
    label: string,
    dataSet: AiraSyncBookmarkDataSet | AiraSyncSnapshot
  ): string {
    if (dataSet === undefined || dataSet === null || typeof dataSet !== 'object') {
      return `${label}分区缺失`;
    }
    const folders = dataSet.bookmarkFolders;
    const items = dataSet.bookmarkItems;
    const orders = dataSet.bookmarkOrders;
    const tombstones = dataSet.tombstones;
    if (!Array.isArray(folders) || !Array.isArray(items) ||
      !Array.isArray(orders) || !Array.isArray(tombstones)) {
      return `${label}分区存在非数组字段`;
    }
    const counts = `${label} 文件夹${folders.length}/书签${items.length}/排序${orders.length}/墓碑${tombstones.length}`;

    for (let index = 0; index < folders.length; index += 1) {
      if (!this.isValidFolder(folders[index])) {
        return `${counts} 非法文件夹[${index}] id=${this.safeId(folders[index].id)}`;
      }
    }
    for (let index = 0; index < items.length; index += 1) {
      if (!this.isValidItem(items[index])) {
        return `${counts} 非法书签[${index}] id=${this.safeId(items[index].id)} url=${this.truncateDiagnostic(String(items[index]?.url ?? ''))}`;
      }
    }
    for (let index = 0; index < orders.length; index += 1) {
      if (!this.isValidOrder(orders[index])) {
        return `${counts} 非法排序[${index}] parentId=${this.safeId(orders[index].parentId)}`;
      }
    }
    for (let index = 0; index < tombstones.length; index += 1) {
      if (!this.isValidTombstone(tombstones[index])) {
        return `${counts} 非法墓碑[${index}] id=${this.safeId(tombstones[index].id)}`;
      }
    }

    const folderKeys = new Set<string>();
    for (let index = 0; index < folders.length; index += 1) {
      const key = folders[index].id;
      if (folderKeys.has(key)) {
        return `${counts} 重复文件夹ID=${key}`;
      }
      folderKeys.add(key);
    }
    const itemKeys = new Set<string>();
    for (let index = 0; index < items.length; index += 1) {
      const key = items[index].id;
      if (itemKeys.has(key)) {
        return `${counts} 重复书签ID=${key}`;
      }
      itemKeys.add(key);
    }
    for (const id of itemKeys.values()) {
      if (folderKeys.has(id)) {
        return `${counts} 书签与文件夹同名ID=${id}`;
      }
    }
    const orderKeys = new Set<string>();
    for (let index = 0; index < orders.length; index += 1) {
      const key = orders[index].parentId ?? '__root__';
      if (orderKeys.has(key)) {
        return `${counts} 重复排序parentId=${key}`;
      }
      orderKeys.add(key);
    }
    const tombstoneKeys = new Set<string>();
    for (let index = 0; index < tombstones.length; index += 1) {
      const entry = tombstones[index];
      const key = `${entry.type}|${entry.id}`;
      if (tombstoneKeys.has(key)) {
        return `${counts} 重复墓碑=${key}`;
      }
      tombstoneKeys.add(key);
      if (folderKeys.has(entry.id) || itemKeys.has(entry.id)) {
        return `${counts} 墓碑与存活实体同ID=${entry.id}`;
      }
    }

    const parentIdByEntityId = new Map<string, string | null>();
    for (let index = 0; index < folders.length; index += 1) {
      const folder = folders[index];
      if (folder.parentId !== null && !folderKeys.has(folder.parentId)) {
        return `${counts} 文件夹父级不存在 id=${folder.id} parentId=${folder.parentId}`;
      }
      parentIdByEntityId.set(folder.id, folder.parentId);
    }
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      if (item.parentId !== null && !folderKeys.has(item.parentId)) {
        return `${counts} 书签父级不存在 id=${item.id} parentId=${item.parentId}`;
      }
      parentIdByEntityId.set(item.id, item.parentId);
    }

    const orderedEntityIds = new Set<string>();
    const orderIdsByParent = new Map<string, string[]>();
    for (let orderIndex = 0; orderIndex < orders.length; orderIndex += 1) {
      const order = orders[orderIndex];
      if (order.parentId !== null && !folderKeys.has(order.parentId)) {
        return `${counts} 排序parentId不是文件夹=${order.parentId}`;
      }
      const orderKey = order.parentId === null ? '__root__' : order.parentId;
      orderIdsByParent.set(orderKey, order.ids);
      for (let idIndex = 0; idIndex < order.ids.length; idIndex += 1) {
        const id = order.ids[idIndex];
        if (!folderKeys.has(id) && !itemKeys.has(id)) {
          return `${counts} 排序引用了不存在的ID=${id}`;
        }
        if (orderedEntityIds.has(id)) {
          return `${counts} 实体出现在多个排序中=${id}`;
        }
        if (parentIdByEntityId.get(id) !== order.parentId) {
          return `${counts} 排序与实体父级不一致 id=${id} orderParent=${order.parentId} entityParent=${parentIdByEntityId.get(id)}`;
        }
        orderedEntityIds.add(id);
      }
    }
    if (orderedEntityIds.size !== folderKeys.size + itemKeys.size) {
      const uncovered = this.describeUncoveredEntities(folders, items, orderedEntityIds, folderKeys);
      return `${counts} 未被排序覆盖的实体数=${folderKeys.size + itemKeys.size - orderedEntityIds.size} ${uncovered}`;
    }

    const reachableEntityIds = new Set<string>();
    const pendingIds = (orderIdsByParent.get('__root__') ?? []).slice();
    for (let index = 0; index < pendingIds.length; index += 1) {
      const id = pendingIds[index];
      if (reachableEntityIds.has(id)) {
        continue;
      }
      reachableEntityIds.add(id);
      if (folderKeys.has(id)) {
        const childIds = orderIdsByParent.get(id) ?? [];
        childIds.forEach((childId: string): void => {
          pendingIds.push(childId);
        });
      }
    }
    if (reachableEntityIds.size !== folderKeys.size + itemKeys.size) {
      return `${counts} 从根不可达的实体数=${folderKeys.size + itemKeys.size - reachableEntityIds.size}`;
    }
    return '';
  }

  private safeId(value: string | null | undefined): string {
    return this.truncateDiagnostic(typeof value === 'string' ? value : '');
  }

  private describeUncoveredEntities(
    folders: AiraSyncBookmarkFolderEntity[],
    items: AiraSyncBookmarkItemEntity[],
    orderedEntityIds: Set<string>,
    folderKeys: Set<string>
  ): string {
    const missingParentCounts = new Map<string, number>();
    let missingParentTotal = 0;
    let parentInSetButUnordered = 0;
    const sampleIds: string[] = [];
    const consider = (id: string, parentId: string | null): void => {
      if (orderedEntityIds.has(id)) {
        return;
      }
      if (parentId !== null && !folderKeys.has(parentId)) {
        missingParentTotal += 1;
        missingParentCounts.set(parentId, (missingParentCounts.get(parentId) ?? 0) + 1);
        if (sampleIds.length < 3) {
          sampleIds.push(`${id}->${parentId}`);
        }
      } else {
        parentInSetButUnordered += 1;
      }
    };
    for (let index = 0; index < folders.length; index += 1) {
      consider(folders[index].id, folders[index].parentId);
    }
    for (let index = 0; index < items.length; index += 1) {
      consider(items[index].id, items[index].parentId);
    }
    const topParents = Array.from(missingParentCounts.entries())
      .sort((left: [string, number], right: [string, number]): number => right[1] - left[1])
      .slice(0, 3)
      .map((entry: [string, number]): string => `${entry[0]}x${entry[1]}`)
      .join(',');
    return `[父级缺失=${missingParentTotal} 父级存在但未排序=${parentInSetButUnordered} 缺失父级Top=${topParents} 样例=${sampleIds.join(' ')}]`;
  }

  private truncateDiagnostic(value: string): string {
    const text = String(value ?? '');
    return text.length > 160 ? `${text.slice(0, 160)}…` : text;
  }
}
