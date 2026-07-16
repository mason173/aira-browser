import type {
  LeafTabSyncBookmarkFolderEntity,
  LeafTabSyncBookmarkItemEntity,
  LeafTabSyncBookmarkOrder,
  LeafTabSyncSnapshot,
  LeafTabSyncTombstone,
} from './schema';
import {
  cloneLeafTabSyncSnapshotMeta,
  createLeafTabSyncTombstoneKey,
} from './schema';
import type { LeafTabSyncOperation } from './remoteStore';

const ROOT_ORDER_KEY = '__root__';

const hashString = (value: string) => {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
};

const createOperationId = (kind: string, entityId: string, updatedAt: string, index: number) => {
  return `op_${hashString(`${kind}:${entityId}:${updatedAt}:${index}`)}_${index}`;
};

const orderKey = (parentId: string | null | undefined) => parentId || ROOT_ORDER_KEY;

const tombstoneKey = createLeafTabSyncTombstoneKey;

const sameFolder = (
  left: LeafTabSyncBookmarkFolderEntity,
  right: LeafTabSyncBookmarkFolderEntity,
) => {
  return left.parentId === right.parentId &&
    left.title === right.title &&
    left.createdAt === right.createdAt &&
    left.updatedAt === right.updatedAt &&
    left.updatedBy === right.updatedBy &&
    left.revision === right.revision;
};

const sameItem = (
  left: LeafTabSyncBookmarkItemEntity,
  right: LeafTabSyncBookmarkItemEntity,
) => {
  return left.parentId === right.parentId &&
    left.title === right.title &&
    left.url === right.url &&
    left.createdAt === right.createdAt &&
    left.updatedAt === right.updatedAt &&
    left.updatedBy === right.updatedBy &&
    left.revision === right.revision;
};

const sameOrder = (
  left: LeafTabSyncBookmarkOrder,
  right: LeafTabSyncBookmarkOrder,
) => {
  if (left.parentId !== right.parentId ||
    left.updatedAt !== right.updatedAt ||
    left.updatedBy !== right.updatedBy ||
    left.revision !== right.revision ||
    left.ids.length !== right.ids.length) {
    return false;
  }
  return left.ids.every((id, index) => id === right.ids[index]);
};

const sameTombstone = (
  left: LeafTabSyncTombstone,
  right: LeafTabSyncTombstone,
) => {
  return left.deletedAt === right.deletedAt &&
    left.deletedBy === right.deletedBy &&
    left.lastKnownRevision === right.lastKnownRevision;
};

const removeDeletedEntityFromOrders = (
  orderByKey: Map<string, LeafTabSyncBookmarkOrder>,
  entityId: string,
  updatedAt: string,
  updatedBy: string,
) => {
  orderByKey.forEach((order, key) => {
    if (!order.ids.includes(entityId)) return;
    orderByKey.set(key, {
      type: 'bookmark-order',
      parentId: order.parentId,
      ids: order.ids.filter((id) => id !== entityId),
      updatedAt,
      updatedBy,
      revision: Math.max(1, order.revision + 1),
    });
  });
};

export const buildLeafTabSyncOperations = (
  baseline: LeafTabSyncSnapshot | null,
  local: LeafTabSyncSnapshot,
): LeafTabSyncOperation[] => {
  const operations: LeafTabSyncOperation[] = [];
  const baselineFolders = new Map(Object.entries(baseline?.bookmarkFolders || {}));
  const baselineItems = new Map(Object.entries(baseline?.bookmarkItems || {}));
  const baselineOrders = new Map(Object.entries(baseline?.bookmarkOrders || {}));
  const baselineTombstones = new Map(
    Object.values(baseline?.tombstones || {}).map((tombstone) => [tombstoneKey(tombstone), tombstone]),
  );

  Object.values(local.bookmarkFolders).forEach((folder) => {
    const previous = baselineFolders.get(folder.id);
    if (previous && sameFolder(previous, folder)) return;
    operations.push({
      id: createOperationId('folder', folder.id, folder.updatedAt, operations.length),
      kind: 'upsert_folder',
      entityId: folder.id,
      entityType: 'bookmark-folder',
      parentId: folder.parentId,
      title: folder.title,
      createdAt: folder.createdAt,
      updatedAt: folder.updatedAt,
      updatedBy: folder.updatedBy,
      revision: folder.revision,
    });
  });

  Object.values(local.bookmarkItems).forEach((item) => {
    const previous = baselineItems.get(item.id);
    if (previous && sameItem(previous, item)) return;
    operations.push({
      id: createOperationId('item', item.id, item.updatedAt, operations.length),
      kind: 'upsert_item',
      entityId: item.id,
      entityType: 'bookmark-item',
      parentId: item.parentId,
      title: item.title,
      url: item.url,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      updatedBy: item.updatedBy,
      revision: item.revision,
    });
  });

  Object.values(local.bookmarkOrders).forEach((order) => {
    const key = orderKey(order.parentId);
    const previous = baselineOrders.get(key);
    if (previous && sameOrder(previous, order)) return;
    operations.push({
      id: createOperationId('order', key, order.updatedAt, operations.length),
      kind: 'upsert_order',
      entityId: key,
      parentId: order.parentId,
      ids: order.ids.slice(),
      updatedAt: order.updatedAt,
      updatedBy: order.updatedBy,
      revision: order.revision,
    });
  });

  Object.values(local.tombstones).forEach((tombstone) => {
    const key = tombstoneKey(tombstone);
    const previous = baselineTombstones.get(key);
    if (previous && sameTombstone(previous, tombstone)) return;
    operations.push({
      id: createOperationId('delete', key, tombstone.deletedAt, operations.length),
      kind: 'delete_entity',
      entityId: tombstone.id,
      entityType: tombstone.type,
      updatedAt: tombstone.deletedAt,
      updatedBy: tombstone.deletedBy,
      revision: tombstone.lastKnownRevision,
      lastKnownRevision: tombstone.lastKnownRevision,
    });
  });

  return operations;
};

export const applyLeafTabSyncOperations = (
  baseline: LeafTabSyncSnapshot,
  operations: LeafTabSyncOperation[],
  deviceId: string,
  generatedAt: string,
): LeafTabSyncSnapshot => {
  const folderById = new Map(Object.entries(baseline.bookmarkFolders));
  const itemById = new Map(Object.entries(baseline.bookmarkItems));
  const orderByKey = new Map(Object.entries(baseline.bookmarkOrders));
  const tombstoneByKey = new Map(
    Object.values(baseline.tombstones).map((tombstone) => [tombstoneKey(tombstone), tombstone]),
  );

  operations.forEach((operation) => {
    if (operation.kind === 'upsert_folder') {
      folderById.set(operation.entityId, {
        id: operation.entityId,
        type: 'bookmark-folder',
        parentId: operation.parentId ?? null,
        title: operation.title ?? '新文件夹',
        createdAt: operation.createdAt ?? operation.updatedAt,
        updatedAt: operation.updatedAt,
        updatedBy: operation.updatedBy,
        revision: operation.revision,
      });
      tombstoneByKey.delete(createLeafTabSyncTombstoneKey('bookmark-folder', operation.entityId));
    } else if (operation.kind === 'upsert_item') {
      itemById.set(operation.entityId, {
        id: operation.entityId,
        type: 'bookmark-item',
        parentId: operation.parentId ?? null,
        title: operation.title ?? '新书签',
        url: operation.url ?? 'about:blank',
        createdAt: operation.createdAt ?? operation.updatedAt,
        updatedAt: operation.updatedAt,
        updatedBy: operation.updatedBy,
        revision: operation.revision,
      });
      tombstoneByKey.delete(createLeafTabSyncTombstoneKey('bookmark-item', operation.entityId));
    } else if (operation.kind === 'upsert_order') {
      const parentId = operation.parentId ?? null;
      orderByKey.set(orderKey(parentId), {
        type: 'bookmark-order',
        parentId,
        ids: operation.ids?.slice() ?? [],
        updatedAt: operation.updatedAt,
        updatedBy: operation.updatedBy,
        revision: operation.revision,
      });
    } else if (operation.kind === 'delete_entity') {
      if (operation.entityType === 'bookmark-folder') {
        folderById.delete(operation.entityId);
        orderByKey.delete(operation.entityId);
      } else if (operation.entityType === 'bookmark-item') {
        itemById.delete(operation.entityId);
      } else {
        return;
      }
      removeDeletedEntityFromOrders(orderByKey, operation.entityId, operation.updatedAt, operation.updatedBy);
      const tombstone: LeafTabSyncTombstone = {
        id: operation.entityId,
        type: operation.entityType,
        deletedAt: operation.updatedAt,
        deletedBy: operation.updatedBy,
        lastKnownRevision: operation.lastKnownRevision ?? operation.revision,
      };
      tombstoneByKey.set(tombstoneKey(tombstone), tombstone);
    }
  });

  return {
    meta: cloneLeafTabSyncSnapshotMeta(baseline.meta, {
      deviceId: deviceId || baseline.meta.deviceId,
      generatedAt: generatedAt || new Date().toISOString(),
    }),
    bookmarkFolders: Object.fromEntries(folderById),
    bookmarkItems: Object.fromEntries(itemById),
    bookmarkOrders: Object.fromEntries(orderByKey),
    tombstones: Object.fromEntries(tombstoneByKey),
    appPrivateBookmarks: baseline.appPrivateBookmarks,
  };
};
