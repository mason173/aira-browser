import type {
  LeafTabSyncBookmarkFolderEntity,
  LeafTabSyncBookmarkItemEntity,
  LeafTabSyncBookmarkOrder,
  LeafTabSyncEntityType,
  LeafTabSyncSnapshot,
  LeafTabSyncTombstone,
} from './schema';
import {
  cloneLeafTabSyncSnapshotMeta,
  createLeafTabSyncTombstoneKey,
  normalizeLeafTabSyncBookmarkDataSet,
} from './schema';

export type LeafTabSyncMergeSource = 'local' | 'remote' | 'merged' | 'tombstone';
export type LeafTabSyncConflictResolution = 'prefer-local' | 'prefer-remote';

export interface LeafTabSyncMergeConflict {
  id: string;
  type: LeafTabSyncEntityType;
  localRevision: number | null;
  remoteRevision: number | null;
}

export interface LeafTabSyncMergeResult {
  snapshot: LeafTabSyncSnapshot;
  entitySources: Record<string, LeafTabSyncMergeSource>;
  orderSources: Record<string, LeafTabSyncMergeSource>;
  conflicts: LeafTabSyncMergeConflict[];
}

type BookmarkEntity = LeafTabSyncBookmarkFolderEntity | LeafTabSyncBookmarkItemEntity;

const bookmarkFolderFields: Array<keyof LeafTabSyncBookmarkFolderEntity> = [
  'parentId',
  'title',
];

const bookmarkItemFields: Array<keyof LeafTabSyncBookmarkItemEntity> = [
  'parentId',
  'title',
  'url',
];

const cloneEntity = <T>(entity: T): T => {
  return JSON.parse(JSON.stringify(entity)) as T;
};

const cloneTombstone = (tombstone: LeafTabSyncTombstone) => cloneEntity(tombstone);

const isSameByFields = <T extends BookmarkEntity>(
  left: T | null | undefined,
  right: T | null | undefined,
  fields: Array<keyof T>,
) => {
  if (!left || !right) return false;
  return fields.every((field) => left[field] === right[field]);
};

const chooseByRevision = <T extends { revision: number; updatedAt: string }>(
  local: T,
  remote: T,
) => {
  if ((local.revision || 0) > (remote.revision || 0)) return { entity: local, source: 'local' as const };
  if ((remote.revision || 0) > (local.revision || 0)) return { entity: remote, source: 'remote' as const };
  const localTime = Date.parse(local.updatedAt || '');
  const remoteTime = Date.parse(remote.updatedAt || '');
  if (Number.isFinite(localTime) && Number.isFinite(remoteTime) && localTime !== remoteTime) {
    return localTime >= remoteTime
      ? { entity: local, source: 'local' as const }
      : { entity: remote, source: 'remote' as const };
  }
  return { entity: remote, source: 'remote' as const };
};

const resolveTombstone = (
  snapshot: LeafTabSyncSnapshot,
  entity: BookmarkEntity | null | undefined,
) => {
  if (!entity) return null;
  return snapshot.tombstones[createLeafTabSyncTombstoneKey(entity.type, entity.id)] || null;
};

const resolveEntity = <T extends BookmarkEntity>(
  params: {
    id: string;
    type: LeafTabSyncEntityType;
    baseEntity: T | undefined;
    localEntity: T | undefined;
    remoteEntity: T | undefined;
    localTombstone: LeafTabSyncTombstone | null;
    remoteTombstone: LeafTabSyncTombstone | null;
    fields: Array<keyof T>;
    conflictResolution?: LeafTabSyncConflictResolution;
  },
): {
  entity: T | null;
  tombstone: LeafTabSyncTombstone | null;
  source: LeafTabSyncMergeSource;
  conflict: LeafTabSyncMergeConflict | null;
} => {
  const {
    id,
    type,
    baseEntity,
    localEntity,
    remoteEntity,
    localTombstone,
    remoteTombstone,
    fields,
    conflictResolution,
  } = params;

  if (!localEntity && !remoteEntity) {
    const tombstone = localTombstone || remoteTombstone;
    return { entity: null, tombstone: tombstone ? cloneTombstone(tombstone) : null, source: 'tombstone', conflict: null };
  }

  if (localEntity && !remoteEntity) {
    if (remoteTombstone) {
      if (remoteTombstone.lastKnownRevision >= localEntity.revision) {
        return { entity: null, tombstone: cloneTombstone(remoteTombstone), source: 'tombstone', conflict: null };
      }
      const localChanged = !baseEntity || !isSameByFields(baseEntity, localEntity, fields);
      if (localChanged) {
        if (conflictResolution === 'prefer-local') {
          return { entity: cloneEntity(localEntity), tombstone: null, source: 'local', conflict: null };
        }
        if (conflictResolution === 'prefer-remote') {
          return { entity: null, tombstone: cloneTombstone(remoteTombstone), source: 'tombstone', conflict: null };
        }
        return {
          entity: cloneEntity(localEntity),
          tombstone: null,
          source: 'local',
          conflict: {
            id,
            type,
            localRevision: localEntity.revision || null,
            remoteRevision: remoteTombstone.lastKnownRevision || null,
          },
        };
      }
      return { entity: null, tombstone: cloneTombstone(remoteTombstone), source: 'tombstone', conflict: null };
    }
    return { entity: cloneEntity(localEntity), tombstone: null, source: 'local', conflict: null };
  }

  if (!localEntity && remoteEntity) {
    if (localTombstone) {
      if (localTombstone.lastKnownRevision >= remoteEntity.revision) {
        return { entity: null, tombstone: cloneTombstone(localTombstone), source: 'tombstone', conflict: null };
      }
      const remoteChanged = !baseEntity || !isSameByFields(baseEntity, remoteEntity, fields);
      if (remoteChanged) {
        if (conflictResolution === 'prefer-local') {
          return { entity: null, tombstone: cloneTombstone(localTombstone), source: 'tombstone', conflict: null };
        }
        if (conflictResolution === 'prefer-remote') {
          return { entity: cloneEntity(remoteEntity), tombstone: null, source: 'remote', conflict: null };
        }
        return {
          entity: cloneEntity(remoteEntity),
          tombstone: null,
          source: 'remote',
          conflict: {
            id,
            type,
            localRevision: localTombstone.lastKnownRevision || null,
            remoteRevision: remoteEntity.revision || null,
          },
        };
      }
      return { entity: null, tombstone: cloneTombstone(localTombstone), source: 'tombstone', conflict: null };
    }
    return { entity: cloneEntity(remoteEntity), tombstone: null, source: 'remote', conflict: null };
  }

  const safeLocalEntity = localEntity!;
  const safeRemoteEntity = remoteEntity!;

  if (isSameByFields(safeLocalEntity, safeRemoteEntity, fields)) {
    const chosen = chooseByRevision(safeLocalEntity, safeRemoteEntity);
    return { entity: cloneEntity(chosen.entity), tombstone: null, source: chosen.source, conflict: null };
  }

  const localChanged = !baseEntity || !isSameByFields(baseEntity, safeLocalEntity, fields);
  const remoteChanged = !baseEntity || !isSameByFields(baseEntity, safeRemoteEntity, fields);
  if (localChanged && remoteChanged && conflictResolution) {
    const selected = conflictResolution === 'prefer-local' ? safeLocalEntity : safeRemoteEntity;
    return {
      entity: cloneEntity(selected),
      tombstone: null,
      source: conflictResolution === 'prefer-local' ? 'local' : 'remote',
      conflict: null,
    };
  }
  const chosen = chooseByRevision(safeLocalEntity, safeRemoteEntity);

  return {
    entity: cloneEntity(chosen.entity),
    tombstone: null,
    source: chosen.source,
    conflict: localChanged && remoteChanged ? {
      id,
      type,
      localRevision: safeLocalEntity.revision || null,
      remoteRevision: safeRemoteEntity.revision || null,
    } : null,
  };
};

const areArraysEqual = (left: string[], right: string[]) => (
  left.length === right.length && left.every((value, index) => value === right[index])
);

const mergeOrderIds = (
  base: string[],
  local: string[],
  remote: string[],
  availableIds: Set<string>,
) => {
  const result: string[] = [];
  const seen = new Set<string>();
  const add = (id: string) => {
    if (!availableIds.has(id) || seen.has(id)) return;
    seen.add(id);
    result.push(id);
  };

  local.forEach(add);
  remote.forEach(add);
  base.forEach(add);
  Array.from(availableIds).sort().forEach(add);
  return result;
};

const resolveOrderMetadata = (
  base: LeafTabSyncBookmarkOrder | undefined,
  local: LeafTabSyncBookmarkOrder | undefined,
  remote: LeafTabSyncBookmarkOrder | undefined,
  ids: string[],
  source: LeafTabSyncMergeSource,
  deviceId: string,
  generatedAt: string,
) => {
  if (source === 'local' && local) return { updatedAt: local.updatedAt, updatedBy: local.updatedBy, revision: local.revision };
  if (source === 'remote' && remote) return { updatedAt: remote.updatedAt, updatedBy: remote.updatedBy, revision: remote.revision };
  const revision = Math.max(base?.revision || 0, local?.revision || 0, remote?.revision || 0) + (source === 'merged' ? 1 : 0);
  return {
    updatedAt: generatedAt,
    updatedBy: deviceId,
    revision: Math.max(1, revision || (ids.length ? 1 : 0)),
  };
};

const chooseOrderByFreshness = (
  local: LeafTabSyncBookmarkOrder | undefined,
  remote: LeafTabSyncBookmarkOrder | undefined,
) => {
  if (!local) return { order: remote, source: 'remote' as const };
  if (!remote) return { order: local, source: 'local' as const };
  if (local.revision !== remote.revision) {
    return local.revision > remote.revision
      ? { order: local, source: 'local' as const }
      : { order: remote, source: 'remote' as const };
  }
  const localTime = Date.parse(local.updatedAt || '');
  const remoteTime = Date.parse(remote.updatedAt || '');
  if (Number.isFinite(localTime) && Number.isFinite(remoteTime) && localTime !== remoteTime) {
    return localTime > remoteTime
      ? { order: local, source: 'local' as const }
      : { order: remote, source: 'remote' as const };
  }
  const updatedByComparison = local.updatedBy.localeCompare(remote.updatedBy);
  if (updatedByComparison !== 0) {
    return updatedByComparison > 0
      ? { order: local, source: 'local' as const }
      : { order: remote, source: 'remote' as const };
  }
  return JSON.stringify(local.ids).localeCompare(JSON.stringify(remote.ids)) >= 0
    ? { order: local, source: 'local' as const }
    : { order: remote, source: 'remote' as const };
};

const collectChildrenByParent = (snapshot: LeafTabSyncSnapshot) => {
  const map = new Map<string, Set<string>>();
  const add = (parentId: string | null, id: string) => {
    const key = parentId || '__root__';
    const current = map.get(key) || new Set<string>();
    current.add(id);
    map.set(key, current);
  };
  Object.values(snapshot.bookmarkFolders).forEach((folder) => add(folder.parentId, folder.id));
  Object.values(snapshot.bookmarkItems).forEach((item) => add(item.parentId, item.id));
  return map;
};

const INITIAL_SYNC_CANONICAL_ROOT_IDS = new Set([
  'browser_root_toolbar',
  'browser_root_other',
  'aira_private_root_toolbar',
  'aira_private_root_other',
]);

const hashInitialCollision = (value: string) => {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(36);
};

const createInitialCollisionId = (
  type: 'folder' | 'item',
  originalId: string,
  parentId: string | null,
  title: string,
  url: string,
  remoteDeviceId: string,
  reservedIds: Set<string>,
) => {
  const fingerprint = `${type}|${originalId}|${parentId || ''}|${title}|${url}|${remoteDeviceId}`;
  const base = `${type === 'folder' ? 'bkf' : 'bkm'}_initial_${hashInitialCollision(fingerprint)}`;
  let candidate = base;
  let suffix = 1;
  while (reservedIds.has(candidate)) {
    candidate = `${base}_${suffix}`;
    suffix += 1;
  }
  reservedIds.add(candidate);
  return candidate;
};

const remapInitialRemoteCollisions = (
  localSnapshot: LeafTabSyncSnapshot,
  remoteSnapshot: LeafTabSyncSnapshot,
) => {
  const localFolders = localSnapshot.bookmarkFolders;
  const localItems = localSnapshot.bookmarkItems;
  const remoteFolders = remoteSnapshot.bookmarkFolders;
  const reservedIds = new Set([
    ...Object.keys(localFolders),
    ...Object.keys(localItems),
    ...Object.keys(remoteFolders),
    ...Object.keys(remoteSnapshot.bookmarkItems),
  ]);
  const entityIdMap = new Map<string, string>();
  const pendingFolders = Object.values(remoteFolders).map(cloneEntity);
  const remappedFolders: Record<string, LeafTabSyncBookmarkFolderEntity> = {};

  while (pendingFolders.length > 0) {
    let progressed = false;
    for (let index = pendingFolders.length - 1; index >= 0; index -= 1) {
      const folder = pendingFolders[index];
      const parentIsPending = folder.parentId !== null && Boolean(remoteFolders[folder.parentId]) &&
        !entityIdMap.has(folder.parentId) && folder.parentId !== folder.id;
      if (parentIsPending) continue;
      const parentId = folder.parentId === null
        ? null
        : entityIdMap.get(folder.parentId) || folder.parentId;
      const localFolder = localFolders[folder.id];
      const compatible = Boolean(localFolder) && !localItems[folder.id] &&
        localFolder.parentId === parentId && localFolder.title === folder.title;
      const collides = Boolean(localItems[folder.id]) || (Boolean(localFolder) && !compatible);
      const id = collides && !INITIAL_SYNC_CANONICAL_ROOT_IDS.has(folder.id)
        ? createInitialCollisionId(
            'folder',
            folder.id,
            parentId,
            folder.title,
            '',
            remoteSnapshot.meta.deviceId,
            reservedIds,
          )
        : folder.id;
      entityIdMap.set(folder.id, id);
      remappedFolders[id] = { ...folder, id, parentId };
      pendingFolders.splice(index, 1);
      progressed = true;
    }
    if (progressed) continue;
    const folder = pendingFolders.pop();
    if (!folder) break;
    const parentId = folder.parentId === null
      ? null
      : entityIdMap.get(folder.parentId) || folder.parentId;
    const id = createInitialCollisionId(
      'folder',
      folder.id,
      parentId,
      folder.title,
      '',
      remoteSnapshot.meta.deviceId,
      reservedIds,
    );
    entityIdMap.set(folder.id, id);
    remappedFolders[id] = { ...folder, id, parentId };
  }

  const remappedItems: Record<string, LeafTabSyncBookmarkItemEntity> = {};
  Object.values(remoteSnapshot.bookmarkItems).forEach((item) => {
    const parentId = item.parentId === null
      ? null
      : entityIdMap.get(item.parentId) || item.parentId;
    const localItem = localItems[item.id];
    const compatible = Boolean(localItem) && !localFolders[item.id] &&
      localItem.parentId === parentId && localItem.title === item.title && localItem.url === item.url;
    const collides = Boolean(localFolders[item.id]) || (Boolean(localItem) && !compatible);
    const id = collides
      ? createInitialCollisionId(
          'item',
          item.id,
          parentId,
          item.title,
          item.url,
          remoteSnapshot.meta.deviceId,
          reservedIds,
        )
      : item.id;
    entityIdMap.set(item.id, id);
    remappedItems[id] = { ...item, id, parentId };
  });

  const remappedOrders: Record<string, LeafTabSyncBookmarkOrder> = {};
  Object.values(remoteSnapshot.bookmarkOrders).forEach((order) => {
    const parentId = order.parentId === null
      ? null
      : entityIdMap.get(order.parentId) || order.parentId;
    const nextOrder = {
      ...order,
      parentId,
      ids: order.ids.map((id) => entityIdMap.get(id) || id),
    };
    remappedOrders[parentId || '__root__'] = nextOrder;
  });

  return {
    ...remoteSnapshot,
    bookmarkFolders: remappedFolders,
    bookmarkItems: remappedItems,
    bookmarkOrders: remappedOrders,
  };
};

const prepareMissingBaselineSnapshots = (
  localSnapshot: LeafTabSyncSnapshot,
  remoteSnapshot: LeafTabSyncSnapshot,
) => {
  const remappedRemote = remapInitialRemoteCollisions(localSnapshot, remoteSnapshot);
  const liveFolderIds = new Set([
    ...Object.keys(localSnapshot.bookmarkFolders),
    ...Object.keys(remappedRemote.bookmarkFolders),
  ]);
  const liveItemIds = new Set([
    ...Object.keys(localSnapshot.bookmarkItems),
    ...Object.keys(remappedRemote.bookmarkItems),
  ]);
  const tombstones: Record<string, LeafTabSyncTombstone> = {};
  const keepNewestTombstone = (entry: LeafTabSyncTombstone) => {
    const hasLiveEntity = entry.type === 'bookmark-folder'
      ? liveFolderIds.has(entry.id)
      : liveItemIds.has(entry.id);
    if (hasLiveEntity) return;
    const key = createLeafTabSyncTombstoneKey(entry);
    const current = tombstones[key];
    if (!current || entry.lastKnownRevision > current.lastKnownRevision ||
      (entry.lastKnownRevision === current.lastKnownRevision && entry.deletedAt > current.deletedAt)) {
      tombstones[key] = cloneTombstone(entry);
    }
  };
  Object.values(localSnapshot.tombstones).forEach(keepNewestTombstone);
  Object.values(remappedRemote.tombstones).forEach(keepNewestTombstone);
  return {
    local: {
      ...localSnapshot,
      tombstones: {},
    },
    remote: {
      ...remappedRemote,
      tombstones,
    },
  };
};

export const mergeLeafTabSyncSnapshot = (
  baseSnapshot: LeafTabSyncSnapshot,
  localSnapshot: LeafTabSyncSnapshot,
  remoteSnapshot: LeafTabSyncSnapshot,
  options: {
    deviceId: string;
    generatedAt?: string;
    conflictResolution?: LeafTabSyncConflictResolution;
  },
): LeafTabSyncMergeResult => {
  const generatedAt = options.generatedAt || new Date().toISOString();
  const nextBookmarkFolders: Record<string, LeafTabSyncBookmarkFolderEntity> = {};
  const nextBookmarkItems: Record<string, LeafTabSyncBookmarkItemEntity> = {};
  const nextTombstones: Record<string, LeafTabSyncTombstone> = {};
  const entitySources: Record<string, LeafTabSyncMergeSource> = {};
  const conflicts: LeafTabSyncMergeConflict[] = [];

  const folderIds = new Set([
    ...Object.keys(baseSnapshot.bookmarkFolders),
    ...Object.keys(localSnapshot.bookmarkFolders),
    ...Object.keys(remoteSnapshot.bookmarkFolders),
  ]);
  folderIds.forEach((id) => {
    const result = resolveEntity({
      id,
      type: 'bookmark-folder',
      baseEntity: baseSnapshot.bookmarkFolders[id],
      localEntity: localSnapshot.bookmarkFolders[id],
      remoteEntity: remoteSnapshot.bookmarkFolders[id],
      localTombstone: resolveTombstone(localSnapshot, baseSnapshot.bookmarkFolders[id] || remoteSnapshot.bookmarkFolders[id]),
      remoteTombstone: resolveTombstone(remoteSnapshot, baseSnapshot.bookmarkFolders[id] || localSnapshot.bookmarkFolders[id]),
      fields: bookmarkFolderFields,
      conflictResolution: options.conflictResolution,
    });
    entitySources[createLeafTabSyncTombstoneKey('bookmark-folder', id)] = result.source;
    if (result.entity) nextBookmarkFolders[id] = result.entity;
    if (result.tombstone) nextTombstones[createLeafTabSyncTombstoneKey(result.tombstone)] = result.tombstone;
    if (result.conflict) conflicts.push(result.conflict);
  });

  const itemIds = new Set([
    ...Object.keys(baseSnapshot.bookmarkItems),
    ...Object.keys(localSnapshot.bookmarkItems),
    ...Object.keys(remoteSnapshot.bookmarkItems),
  ]);
  itemIds.forEach((id) => {
    const result = resolveEntity({
      id,
      type: 'bookmark-item',
      baseEntity: baseSnapshot.bookmarkItems[id],
      localEntity: localSnapshot.bookmarkItems[id],
      remoteEntity: remoteSnapshot.bookmarkItems[id],
      localTombstone: resolveTombstone(localSnapshot, baseSnapshot.bookmarkItems[id] || remoteSnapshot.bookmarkItems[id]),
      remoteTombstone: resolveTombstone(remoteSnapshot, baseSnapshot.bookmarkItems[id] || localSnapshot.bookmarkItems[id]),
      fields: bookmarkItemFields,
      conflictResolution: options.conflictResolution,
    });
    entitySources[createLeafTabSyncTombstoneKey('bookmark-item', id)] = result.source;
    if (result.entity) nextBookmarkItems[id] = result.entity;
    if (result.tombstone) nextTombstones[createLeafTabSyncTombstoneKey(result.tombstone)] = result.tombstone;
    if (result.conflict) conflicts.push(result.conflict);
  });

  const preserveTombstoneWhenItsTypedEntityIsAbsent = (tombstone: LeafTabSyncTombstone) => {
    const hasLiveTypedEntity = tombstone.type === 'bookmark-folder'
      ? Boolean(nextBookmarkFolders[tombstone.id])
      : Boolean(nextBookmarkItems[tombstone.id]);
    if (!hasLiveTypedEntity) {
      nextTombstones[createLeafTabSyncTombstoneKey(tombstone)] = cloneTombstone(tombstone);
    }
  };
  Object.values(baseSnapshot.tombstones || {}).forEach(preserveTombstoneWhenItsTypedEntityIsAbsent);
  Object.values(localSnapshot.tombstones || {}).forEach(preserveTombstoneWhenItsTypedEntityIsAbsent);
  Object.values(remoteSnapshot.tombstones || {}).forEach(preserveTombstoneWhenItsTypedEntityIsAbsent);
  Object.values(nextTombstones).forEach((tombstone) => {
    if (tombstone.type === 'bookmark-folder') delete nextBookmarkFolders[tombstone.id];
    if (tombstone.type === 'bookmark-item') delete nextBookmarkItems[tombstone.id];
  });

  const mergedMeta = remoteSnapshot.meta;
  const appPrivateBookmarks = normalizeLeafTabSyncBookmarkDataSet(
    remoteSnapshot.appPrivateBookmarks ?? localSnapshot.appPrivateBookmarks ?? baseSnapshot.appPrivateBookmarks,
  );

  const mergedContentSnapshot: LeafTabSyncSnapshot = {
    meta: cloneLeafTabSyncSnapshotMeta(mergedMeta, { deviceId: options.deviceId, generatedAt }),
    bookmarkFolders: nextBookmarkFolders,
    bookmarkItems: nextBookmarkItems,
    bookmarkOrders: {},
    tombstones: nextTombstones,
    appPrivateBookmarks,
  };
  const availableIdsByParent = collectChildrenByParent(mergedContentSnapshot);
  const orderKeys = new Set([
    '__root__',
    ...Object.keys(baseSnapshot.bookmarkOrders),
    ...Object.keys(localSnapshot.bookmarkOrders),
    ...Object.keys(remoteSnapshot.bookmarkOrders),
    ...availableIdsByParent.keys(),
  ]);
  const bookmarkOrders: Record<string, LeafTabSyncBookmarkOrder> = {};
  const orderSources: Record<string, LeafTabSyncMergeSource> = {};

  orderKeys.forEach((orderKey) => {
    const baseOrder = baseSnapshot.bookmarkOrders[orderKey];
    const localOrder = localSnapshot.bookmarkOrders[orderKey];
    const remoteOrder = remoteSnapshot.bookmarkOrders[orderKey];
    const availableIds = availableIdsByParent.get(orderKey) || new Set<string>();
    const baseIds = baseOrder?.ids || [];
    const localIds = localOrder?.ids || [];
    const remoteIds = remoteOrder?.ids || [];
    const localChanged = !areArraysEqual(baseIds, localIds);
    const remoteChanged = !areArraysEqual(baseIds, remoteIds);
    let source: LeafTabSyncMergeSource;
    let ids: string[];

    if (localChanged && !remoteChanged) {
      source = 'local';
      ids = localIds.filter((id) => availableIds.has(id));
    } else if (!localChanged && remoteChanged) {
      source = 'remote';
      ids = remoteIds.filter((id) => availableIds.has(id));
    } else if (areArraysEqual(localIds, remoteIds)) {
      source = localOrder ? 'local' : remoteOrder ? 'remote' : 'merged';
      ids = localIds.filter((id) => availableIds.has(id));
    } else {
      const chosen = chooseOrderByFreshness(localOrder, remoteOrder);
      source = chosen.source;
      const primaryIds = chosen.order?.ids || [];
      const secondaryIds = chosen.source === 'remote' ? localIds : remoteIds;
      ids = mergeOrderIds(baseIds, primaryIds, secondaryIds, availableIds);
    }

    const mergedIds = new Set(ids);
    Array.from(availableIds).sort().forEach((id) => {
      if (mergedIds.has(id)) return;
      mergedIds.add(id);
      ids.push(id);
    });
    const sourceIds = source === 'local' ? localIds : source === 'remote' ? remoteIds : ids;
    if (!areArraysEqual(ids, sourceIds.filter((id) => availableIds.has(id)))) {
      source = 'merged';
    }

    const metadata = resolveOrderMetadata(
      baseOrder,
      localOrder,
      remoteOrder,
      ids,
      source,
      options.deviceId,
      generatedAt,
    );

    bookmarkOrders[orderKey] = {
      type: 'bookmark-order',
      parentId: orderKey === '__root__' ? null : orderKey,
      ids,
      ...metadata,
    };
    orderSources[`bookmark-order:${orderKey}`] = source;
  });

  return {
    snapshot: {
      meta: cloneLeafTabSyncSnapshotMeta(mergedMeta, { deviceId: options.deviceId, generatedAt }),
      bookmarkFolders: nextBookmarkFolders,
      bookmarkItems: nextBookmarkItems,
      bookmarkOrders,
      tombstones: nextTombstones,
      appPrivateBookmarks,
    },
    entitySources,
    orderSources,
    conflicts,
  };
};

export const mergeLeafTabSyncSnapshotWithoutBaseline = (
  localSnapshot: LeafTabSyncSnapshot,
  remoteSnapshot: LeafTabSyncSnapshot,
  options: {
    deviceId: string;
    generatedAt?: string;
  },
): LeafTabSyncMergeResult => {
  const prepared = prepareMissingBaselineSnapshots(localSnapshot, remoteSnapshot);
  const emptyBase: LeafTabSyncSnapshot = {
    meta: cloneLeafTabSyncSnapshotMeta(localSnapshot.meta, {
      deviceId: options.deviceId,
      generatedAt: options.generatedAt || new Date().toISOString(),
    }),
    bookmarkFolders: {},
    bookmarkItems: {},
    bookmarkOrders: {},
    tombstones: {},
  };
  return mergeLeafTabSyncSnapshot(emptyBase, prepared.local, prepared.remote, options);
};
