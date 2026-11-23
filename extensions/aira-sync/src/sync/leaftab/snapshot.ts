import type { LeafTabBookmarkTreeDraft } from './bookmarks';
import { normalizeChromeBookmarkUrl } from './chromeBookmarkUrl';
import type {
  LeafTabSyncBookmarkDataSet,
  LeafTabSyncBookmarkFolderEntity,
  LeafTabSyncBookmarkItemEntity,
  LeafTabSyncBookmarkOrder,
  LeafTabSyncSnapshot,
  LeafTabSyncTombstone,
} from './schema';
import {
  cloneLeafTabSyncSnapshotMeta,
  createLeafTabSyncTombstoneKey,
  type LeafTabSyncSnapshotMeta,
} from './schema';

type LeafTabEntityMetadata = {
  createdAt: string;
  updatedAt: string;
  updatedBy: string;
  revision: number;
};

type LeafTabOrderMetadata = {
  updatedAt: string;
  updatedBy: string;
  revision: number;
};

export interface LeafTabSnapshotBuildState {
  snapshotMeta?: LeafTabSyncSnapshotMeta;
  entities?: Record<string, LeafTabEntityMetadata>;
  tombstones?: Record<string, LeafTabSyncTombstone>;
  orders?: {
    bookmarkOrders?: Record<string, LeafTabOrderMetadata>;
  };
  appPrivateBookmarks?: LeafTabSyncBookmarkDataSet;
}

type ResolvedBookmarkFolderEntry = {
  folderId: string;
  parentId: string | null;
  title: string;
};

type ResolvedBookmarkItemEntry = {
  bookmarkId: string;
  parentId: string | null;
  title: string;
  url: string;
};

const ROOT_ORDER_KEY = '__root__';
const BROWSER_ROOT_TOOLBAR_ID = 'browser_root_toolbar';
const BROWSER_ROOT_OTHER_ID = 'browser_root_other';

const BROWSER_ROOT_FOLDERS: Record<string, string> = {
  [BROWSER_ROOT_TOOLBAR_ID]: '书签栏',
  [BROWSER_ROOT_OTHER_ID]: '其他书签',
};

const getEntityMetadata = (
  type: 'bookmark-folder' | 'bookmark-item',
  id: string,
  deviceId: string,
  timestamp: string,
  state?: LeafTabSnapshotBuildState,
): LeafTabEntityMetadata => {
  const fromState = state?.entities?.[createLeafTabSyncTombstoneKey(type, id)];
  if (fromState) return fromState;
  return {
    createdAt: timestamp,
    updatedAt: timestamp,
    updatedBy: deviceId,
    revision: 1,
  };
};

const getOrderMetadata = (
  metadata: LeafTabOrderMetadata | undefined,
  deviceId: string,
  timestamp: string,
): LeafTabOrderMetadata => {
  if (metadata) return metadata;
  return {
    updatedAt: timestamp,
    updatedBy: deviceId,
    revision: 1,
  };
};

const areArraysEqual = (left: string[], right: string[]) => {
  if (left.length !== right.length) return false;
  return left.every((value, index) => value === right[index]);
};

const isSameBookmarkFolderValue = (
  folder: ResolvedBookmarkFolderEntry,
  entity: LeafTabSyncBookmarkFolderEntity | undefined,
) => {
  if (!entity) return false;
  return entity.parentId === folder.parentId && entity.title === folder.title;
};

const isSameBookmarkItemValue = (
  item: ResolvedBookmarkItemEntry,
  entity: LeafTabSyncBookmarkItemEntity | undefined,
) => {
  if (!entity) return false;
  return entity.parentId === item.parentId && entity.title === item.title && entity.url === item.url;
};

const createUpdatedEntityMetadata = (
  current: LeafTabEntityMetadata | undefined,
  deviceId: string,
  timestamp: string,
): LeafTabEntityMetadata => {
  if (!current) {
    return {
      createdAt: timestamp,
      updatedAt: timestamp,
      updatedBy: deviceId,
      revision: 1,
    };
  }
  return {
    createdAt: current.createdAt,
    updatedAt: timestamp,
    updatedBy: deviceId,
    revision: current.revision + 1,
  };
};

const createUpdatedOrderMetadata = (
  current: LeafTabOrderMetadata | undefined,
  deviceId: string,
  timestamp: string,
): LeafTabOrderMetadata => {
  if (!current) {
    return {
      updatedAt: timestamp,
      updatedBy: deviceId,
      revision: 1,
    };
  }
  return {
    updatedAt: timestamp,
    updatedBy: deviceId,
    revision: current.revision + 1,
  };
};

const createTombstone = (
  entity: Pick<
    LeafTabSyncBookmarkFolderEntity | LeafTabSyncBookmarkItemEntity,
    'id' | 'type' | 'revision'
  >,
  deletedBy: string,
  deletedAt: string,
): LeafTabSyncTombstone => ({
  id: entity.id,
  type: entity.type,
  deletedAt,
  deletedBy,
  lastKnownRevision: entity.revision,
});

// Native root folders cannot be created, renamed or removed by the extension.
export const materializeRemoteOverwrite = (
  remote: LeafTabSyncSnapshot,
  local: LeafTabSyncSnapshot,
): LeafTabSyncSnapshot => {
  const rootIds = local.bookmarkOrders[ROOT_ORDER_KEY]?.ids || [];
  const incomingRoots = remote.bookmarkOrders[ROOT_ORDER_KEY]?.ids || [];
  if (incomingRoots.some((id) => !rootIds.includes(id) || !remote.bookmarkFolders[id])) {
    throw new Error('远端书签含有当前浏览器无法写入的根目录，已停止覆盖。');
  }
  const bookmarkFolders = { ...remote.bookmarkFolders };
  const bookmarkOrders = { ...remote.bookmarkOrders };
  const tombstones = { ...remote.tombstones };
  for (const id of rootIds) {
    delete tombstones[createLeafTabSyncTombstoneKey('bookmark-folder', id)];
    const native = local.bookmarkFolders[id];
    if (native) bookmarkFolders[id] = { ...(bookmarkFolders[id] || native), title: native.title };
  }
  const rootOrder = local.bookmarkOrders[ROOT_ORDER_KEY];
  if (rootOrder) bookmarkOrders[ROOT_ORDER_KEY] = { ...(bookmarkOrders[ROOT_ORDER_KEY] || rootOrder), ids: rootIds };
  for (const folder of Object.values(bookmarkFolders)) {
    if (!bookmarkOrders[folder.id]) {
      bookmarkOrders[folder.id] = {
        type: 'bookmark-order', parentId: folder.id, ids: [], updatedAt: folder.updatedAt,
        updatedBy: folder.updatedBy, revision: 1,
      };
    }
  }
  return { ...remote, bookmarkFolders, bookmarkOrders, tombstones };
};

// Browser-owned root names and empty containers can differ from the wire snapshot.
// Reuse the confirmed representation until a local edit actually needs a new container.
export const reconcileNativeBookmarkRoots = (
  captured: LeafTabSyncSnapshot,
  baseline: LeafTabSyncSnapshot,
): LeafTabSyncSnapshot => {
  const physicalOrder = captured.bookmarkOrders[ROOT_ORDER_KEY];
  if (!physicalOrder) return captured;
  const bookmarkFolders = { ...captured.bookmarkFolders };
  const bookmarkOrders = { ...captured.bookmarkOrders };
  const tombstones = { ...captured.tombstones };
  for (const id of physicalOrder.ids) {
    if (id !== 'browser_root_toolbar' && id !== 'browser_root_other') continue;
    const confirmed = baseline.bookmarkFolders[id];
    if (confirmed && bookmarkFolders[id]) {
      bookmarkFolders[id] = confirmed;
    } else if (!confirmed && !bookmarkOrders[id]?.ids.length) {
      delete bookmarkFolders[id];
      const key = createLeafTabSyncTombstoneKey('bookmark-folder', id);
      if (baseline.tombstones[key]) tombstones[key] = baseline.tombstones[key];
    }
  }
  const retainedIds = physicalOrder.ids.filter(id => bookmarkFolders[id]);
  const confirmedOrder = baseline.bookmarkOrders[ROOT_ORDER_KEY];
  if (confirmedOrder && confirmedOrder.ids.length === retainedIds.length &&
      confirmedOrder.ids.every(id => retainedIds.includes(id))) {
    bookmarkOrders[ROOT_ORDER_KEY] = confirmedOrder;
  } else {
    bookmarkOrders[ROOT_ORDER_KEY] = { ...physicalOrder, ids: retainedIds };
  }
  for (const [key, order] of Object.entries(bookmarkOrders)) {
    if (!order.ids.length && !baseline.bookmarkOrders[key] &&
        (key === ROOT_ORDER_KEY || baseline.bookmarkFolders[key] || !bookmarkFolders[key])) {
      delete bookmarkOrders[key];
    }
  }
  return { ...captured, bookmarkFolders, bookmarkOrders, tombstones };
};

// The existing per-record actor carries the explicit overwrite intent to paired
// readers even if an unrelated device publishes another head before they sync.
const COMPUTER_OVERWRITE_ACTOR_PREFIX = 'aira-sync-bookmark-overwrite:';
export const isComputerOverwriteActor = (actor: string | undefined) =>
  Boolean(actor?.startsWith(COMPUTER_OVERWRITE_ACTOR_PREFIX));

// A desktop overwrite owns the shared tree. Keep the App-owned partition from
// the current head and record removals so paired devices can retire their old IDs.
export const buildComputerOverwriteSnapshot = (
  local: LeafTabSyncSnapshot,
  remote: LeafTabSyncSnapshot | null,
  deviceId: string,
): LeafTabSyncSnapshot => {
  if (!remote) return local;
  const now = new Date().toISOString();
  const actor = COMPUTER_OVERWRITE_ACTOR_PREFIX + deviceId;
  const bookmarkFolders = { ...local.bookmarkFolders };
  const bookmarkItems = { ...local.bookmarkItems };
  const bookmarkOrders = { ...local.bookmarkOrders };
  const tombstones = { ...remote.tombstones };
  for (const [key, deletion] of Object.entries(local.tombstones)) {
    const previous = tombstones[key];
    if (!previous || deletion.lastKnownRevision > previous.lastKnownRevision ||
      (deletion.lastKnownRevision === previous.lastKnownRevision && deletion.deletedAt > previous.deletedAt)) {
      tombstones[key] = deletion;
    }
  }

  for (const entity of [...Object.values(remote.bookmarkFolders), ...Object.values(remote.bookmarkItems)]) {
    if (bookmarkFolders[entity.id] || bookmarkItems[entity.id]) continue;
    const key = createLeafTabSyncTombstoneKey(entity.type, entity.id);
    tombstones[key] = {
      ...createTombstone(entity, actor, now),
      lastKnownRevision: Math.max(entity.revision, tombstones[key]?.lastKnownRevision ?? 0),
    };
  }
  for (const entity of [...Object.values(bookmarkFolders), ...Object.values(bookmarkItems)]) {
    const key = createLeafTabSyncTombstoneKey(entity.type, entity.id);
    const formerRevision = remote.tombstones[key]?.lastKnownRevision ?? -1;
    const previous = entity.type === 'bookmark-folder' ? remote.bookmarkFolders[entity.id] : remote.bookmarkItems[entity.id];
    const changed = previous && (previous.parentId !== entity.parentId || previous.title !== entity.title ||
      (entity.type === 'bookmark-item' && previous.type === 'bookmark-item' && previous.url !== entity.url));
    const revision = Math.max(entity.revision, formerRevision + 1, (previous?.revision ?? 0) + (changed ? 1 : 0));
    if (!previous || changed || revision !== entity.revision) {
      const metadata = { revision, updatedAt: now, updatedBy: actor };
      if (entity.type === 'bookmark-folder') bookmarkFolders[entity.id] = { ...entity, ...metadata };
      else bookmarkItems[entity.id] = { ...entity, ...metadata };
    }
    delete tombstones[createLeafTabSyncTombstoneKey('bookmark-folder', entity.id)];
    delete tombstones[createLeafTabSyncTombstoneKey('bookmark-item', entity.id)];
  }
  for (const [key, order] of Object.entries(bookmarkOrders)) {
    const previous = remote.bookmarkOrders[key];
    if (previous && !areArraysEqual(order.ids, previous.ids) && order.revision <= previous.revision) {
      bookmarkOrders[key] = { ...order, ...createUpdatedOrderMetadata(previous, deviceId, now) };
    }
  }
  return { ...local, bookmarkFolders, bookmarkItems, bookmarkOrders, tombstones,
    appPrivateBookmarks: remote.appPrivateBookmarks };
};

// Keep the first occurrence in visible tree order. Two distinct folder entities can
// represent the same named path. Anchor that path at the canonical root identity.
export const deduplicateFirstJoinBookmarks = (
  snapshot: LeafTabSyncSnapshot,
  deviceId: string,
): LeafTabSyncSnapshot => {
  const seen = new Set<string>();
  const duplicates = new Set<string>();
  const visit = (orderKey: string, path: string[]) => {
    for (const id of snapshot.bookmarkOrders[orderKey]?.ids || []) {
      const folder = snapshot.bookmarkFolders[id];
      if (folder) {
        visit(id, [...path, folder.parentId === null ? id : folder.title]);
        continue;
      }
      const item = snapshot.bookmarkItems[id];
      if (!item) continue;
      const key = JSON.stringify([...path, item.title, item.url]);
      if (seen.has(key)) duplicates.add(id);
      else seen.add(key);
    }
  };
  visit(ROOT_ORDER_KEY, []);
  if (duplicates.size === 0) return snapshot;

  const timestamp = new Date().toISOString();
  const bookmarkItems = { ...snapshot.bookmarkItems };
  const bookmarkOrders = { ...snapshot.bookmarkOrders };
  const tombstones = { ...snapshot.tombstones };
  for (const id of duplicates) {
    const deletion = createTombstone(bookmarkItems[id], deviceId, timestamp);
    tombstones[createLeafTabSyncTombstoneKey(deletion)] = deletion;
    delete bookmarkItems[id];
  }
  for (const [key, order] of Object.entries(bookmarkOrders)) {
    const ids = order.ids.filter((id) => !duplicates.has(id));
    if (ids.length !== order.ids.length) {
      bookmarkOrders[key] = { ...order, ...createUpdatedOrderMetadata(order, deviceId, timestamp), ids };
    }
  }
  return { ...snapshot, bookmarkItems, bookmarkOrders, tombstones };
};

const resolveBookmarkTreeInput = (
  bookmarkTree: LeafTabBookmarkTreeDraft | null | undefined,
) => {
  const resolvedBookmarkFolderEntries: ResolvedBookmarkFolderEntry[] = [];
  const resolvedBookmarkItemEntries: ResolvedBookmarkItemEntry[] = [];
  const bookmarkOrderIdsByParent: Record<string, string[]> = {};

  (bookmarkTree?.folders || []).forEach((folder) => {
    resolvedBookmarkFolderEntries.push({
      folderId: folder.entityId,
      parentId: folder.parentId,
      title: folder.title,
    });
  });

  (bookmarkTree?.items || []).forEach((item) => {
    resolvedBookmarkItemEntries.push({
      bookmarkId: item.entityId,
      parentId: item.parentId,
      title: item.title,
      url: item.url,
    });
  });

  Object.entries(bookmarkTree?.orderIdsByParent || {}).forEach(([parentId, ids]) => {
    bookmarkOrderIdsByParent[parentId] = ids.slice();
  });
  if (!bookmarkOrderIdsByParent[ROOT_ORDER_KEY]) {
    bookmarkOrderIdsByParent[ROOT_ORDER_KEY] = [];
  }

  return {
    resolvedBookmarkFolderEntries,
    resolvedBookmarkItemEntries,
    bookmarkOrderIdsByParent,
  };
};

const cloneBookmarkDataSet = (
  value: LeafTabSyncBookmarkDataSet | null | undefined,
): LeafTabSyncBookmarkDataSet | undefined => {
  if (!value) {
    return undefined;
  }
  return {
    bookmarkFolders: { ...(value.bookmarkFolders || {}) },
    bookmarkItems: { ...(value.bookmarkItems || {}) },
    bookmarkOrders: { ...(value.bookmarkOrders || {}) },
    tombstones: { ...(value.tombstones || {}) },
  };
};

export const createLeafTabSyncBuildState = (params: {
  previousSnapshot?: LeafTabSyncSnapshot | null;
  bookmarkTree?: LeafTabBookmarkTreeDraft | null;
  deviceId: string;
  generatedAt?: string;
}): LeafTabSnapshotBuildState => {
  const generatedAt = params.generatedAt || new Date().toISOString();
  const previousSnapshot = params.previousSnapshot || null;
  const state: LeafTabSnapshotBuildState = {
    snapshotMeta: previousSnapshot ? cloneLeafTabSyncSnapshotMeta(previousSnapshot.meta) : undefined,
    entities: {},
    tombstones: {
      ...(previousSnapshot?.tombstones || {}),
    },
    orders: {
      bookmarkOrders: {},
    },
    appPrivateBookmarks: cloneBookmarkDataSet(previousSnapshot?.appPrivateBookmarks),
  };

  const {
    resolvedBookmarkFolderEntries,
    resolvedBookmarkItemEntries,
    bookmarkOrderIdsByParent,
  } = resolveBookmarkTreeInput(params.bookmarkTree);

  resolvedBookmarkFolderEntries.forEach((folder) => {
    const previousEntity = previousSnapshot?.bookmarkFolders[folder.folderId];
    const entityKey = createLeafTabSyncTombstoneKey('bookmark-folder', folder.folderId);
    state.entities![entityKey] = previousEntity && isSameBookmarkFolderValue(folder, previousEntity)
      ? {
          createdAt: previousEntity.createdAt,
          updatedAt: previousEntity.updatedAt,
          updatedBy: previousEntity.updatedBy,
          revision: previousEntity.revision,
        }
      : createUpdatedEntityMetadata(previousEntity, params.deviceId, generatedAt);
    delete state.tombstones![createLeafTabSyncTombstoneKey('bookmark-folder', folder.folderId)];
  });

  resolvedBookmarkItemEntries.forEach((item) => {
    const previousEntity = previousSnapshot?.bookmarkItems[item.bookmarkId];
    const entityKey = createLeafTabSyncTombstoneKey('bookmark-item', item.bookmarkId);
    state.entities![entityKey] = previousEntity && isSameBookmarkItemValue(item, previousEntity)
      ? {
          createdAt: previousEntity.createdAt,
          updatedAt: previousEntity.updatedAt,
          updatedBy: previousEntity.updatedBy,
          revision: previousEntity.revision,
        }
      : createUpdatedEntityMetadata(previousEntity, params.deviceId, generatedAt);
    delete state.tombstones![createLeafTabSyncTombstoneKey('bookmark-item', item.bookmarkId)];
  });

  Object.values(previousSnapshot?.bookmarkFolders || {}).forEach((entity) => {
    if (!state.entities?.[createLeafTabSyncTombstoneKey(entity.type, entity.id)]) {
      const tombstone = createTombstone(entity, params.deviceId, generatedAt);
      state.tombstones![createLeafTabSyncTombstoneKey(tombstone)] = tombstone;
    }
  });

  Object.values(previousSnapshot?.bookmarkItems || {}).forEach((entity) => {
    if (!state.entities?.[createLeafTabSyncTombstoneKey(entity.type, entity.id)]) {
      const tombstone = createTombstone(entity, params.deviceId, generatedAt);
      state.tombstones![createLeafTabSyncTombstoneKey(tombstone)] = tombstone;
    }
  });

  Object.entries(bookmarkOrderIdsByParent).forEach(([orderKey, nextIds]) => {
    const previousOrder = previousSnapshot?.bookmarkOrders[orderKey];
    state.orders!.bookmarkOrders![orderKey] = previousOrder && areArraysEqual(previousOrder.ids, nextIds)
      ? {
          updatedAt: previousOrder.updatedAt,
          updatedBy: previousOrder.updatedBy,
          revision: previousOrder.revision,
        }
      : createUpdatedOrderMetadata(previousOrder, params.deviceId, generatedAt);
  });

  return state;
};

export const buildLeafTabSyncSnapshot = (params: {
  bookmarkTree?: LeafTabBookmarkTreeDraft | null;
  deviceId: string;
  generatedAt?: string;
  state?: LeafTabSnapshotBuildState;
}): LeafTabSyncSnapshot => {
  const generatedAt = params.generatedAt || new Date().toISOString();
  const bookmarkFolders: Record<string, LeafTabSyncBookmarkFolderEntity> = {};
  const bookmarkItems: Record<string, LeafTabSyncBookmarkItemEntity> = {};
  const bookmarkOrders: Record<string, LeafTabSyncBookmarkOrder> = {};
  const {
    resolvedBookmarkFolderEntries,
    resolvedBookmarkItemEntries,
    bookmarkOrderIdsByParent,
  } = resolveBookmarkTreeInput(params.bookmarkTree);
  const tombstones = { ...(params.state?.tombstones || {}) };

  resolvedBookmarkFolderEntries.forEach((folder) => {
    const metadata = getEntityMetadata(
      'bookmark-folder',
      folder.folderId,
      params.deviceId,
      generatedAt,
      params.state,
    );
    bookmarkFolders[folder.folderId] = {
      id: folder.folderId,
      type: 'bookmark-folder',
      parentId: folder.parentId,
      title: folder.title,
      ...metadata,
    };
    delete tombstones[createLeafTabSyncTombstoneKey('bookmark-folder', folder.folderId)];
  });

  resolvedBookmarkItemEntries.forEach((item) => {
    const metadata = getEntityMetadata(
      'bookmark-item',
      item.bookmarkId,
      params.deviceId,
      generatedAt,
      params.state,
    );
    bookmarkItems[item.bookmarkId] = {
      id: item.bookmarkId,
      type: 'bookmark-item',
      parentId: item.parentId,
      title: item.title,
      url: item.url,
      ...metadata,
    };
    delete tombstones[createLeafTabSyncTombstoneKey('bookmark-item', item.bookmarkId)];
  });

  Object.entries(bookmarkOrderIdsByParent).forEach(([orderKey, ids]) => {
    const orderMetadata = getOrderMetadata(
      params.state?.orders?.bookmarkOrders?.[orderKey],
      params.deviceId,
      generatedAt,
    );
    bookmarkOrders[orderKey] = {
      type: 'bookmark-order',
      parentId: orderKey === ROOT_ORDER_KEY ? null : orderKey,
      ids,
      ...orderMetadata,
    };
  });

  return {
    meta: cloneLeafTabSyncSnapshotMeta(params.state?.snapshotMeta, {
      deviceId: params.deviceId,
      generatedAt,
    }),
    bookmarkFolders,
    bookmarkItems,
    bookmarkOrders,
    tombstones,
    appPrivateBookmarks: cloneBookmarkDataSet(params.state?.appPrivateBookmarks),
  };
};

const buildDeletedEntityIdSet = (
  snapshot: LeafTabSyncSnapshot,
  type: 'bookmark-folder' | 'bookmark-item',
) => new Set(
  Object.values(snapshot.tombstones || {})
    .filter((entry) => entry.type === type)
    .map((entry) => entry.id),
);

export const filterLeafTabLiveBookmarkFolders = (
  snapshot: LeafTabSyncSnapshot,
) => {
  const deletedFolderIds = buildDeletedEntityIdSet(snapshot, 'bookmark-folder');
  return Object.fromEntries(
    Object.entries(snapshot.bookmarkFolders || {})
      .filter(([id]) => !deletedFolderIds.has(id)),
  ) as LeafTabSyncSnapshot['bookmarkFolders'];
};

export const filterLeafTabLiveBookmarkItems = (
  snapshot: LeafTabSyncSnapshot,
) => {
  const deletedItemIds = buildDeletedEntityIdSet(snapshot, 'bookmark-item');
  return Object.fromEntries(
    Object.entries(snapshot.bookmarkItems || {})
      .filter(([id]) => !deletedItemIds.has(id)),
  ) as LeafTabSyncSnapshot['bookmarkItems'];
};

export const filterLeafTabLiveBookmarkOrders = (
  snapshot: LeafTabSyncSnapshot,
) => {
  const liveFolders = filterLeafTabLiveBookmarkFolders(snapshot);
  const liveItems = filterLeafTabLiveBookmarkItems(snapshot);
  const liveIds = new Set([
    ...Object.keys(liveFolders),
    ...Object.keys(liveItems),
  ]);

  const orders = Object.fromEntries(
    Object.entries(snapshot.bookmarkOrders || {})
      .filter(([, order]) => order.parentId === null || Boolean(liveFolders[order.parentId]))
      .map(([key, order]) => [
        key,
        {
          ...order,
          ids: order.ids.filter((id) => liveIds.has(id)),
        },
      ]),
  ) as LeafTabSyncSnapshot['bookmarkOrders'];

  Object.keys(BROWSER_ROOT_FOLDERS).forEach((rootId) => {
    const childIds = [
      ...Object.values(liveFolders)
        .filter((folder) => folder.parentId === rootId)
        .map((folder) => folder.id),
      ...Object.values(liveItems)
        .filter((item) => item.parentId === rootId)
        .map((item) => item.id),
    ];
    if (childIds.length === 0) return;

    const existingIds = orders[rootId]?.ids.filter((id) => liveIds.has(id)) || [];
    const mergedIds = [
      ...existingIds,
      ...childIds.filter((id) => !existingIds.includes(id)),
    ];
    orders[rootId] = {
      type: 'bookmark-order',
      parentId: rootId,
      ids: mergedIds,
      updatedAt: orders[rootId]?.updatedAt || snapshot.meta.generatedAt,
      updatedBy: orders[rootId]?.updatedBy || snapshot.meta.deviceId,
      revision: orders[rootId]?.revision || 1,
    };
  });

  const rootIds = Object.keys(BROWSER_ROOT_FOLDERS).filter((rootId) => {
    return Boolean(orders[rootId]?.ids.length)
      || Boolean(liveFolders[rootId])
      || Boolean(liveItems[rootId]);
  });
  if (rootIds.length > 0) {
    const existingRootIds = orders[ROOT_ORDER_KEY]?.ids.filter((id) => rootIds.includes(id)) || [];
    orders[ROOT_ORDER_KEY] = {
      type: 'bookmark-order',
      parentId: null,
      ids: [
        ...existingRootIds,
        ...rootIds.filter((id) => !existingRootIds.includes(id)),
      ],
      updatedAt: orders[ROOT_ORDER_KEY]?.updatedAt || snapshot.meta.generatedAt,
      updatedBy: orders[ROOT_ORDER_KEY]?.updatedBy || snapshot.meta.deviceId,
      revision: orders[ROOT_ORDER_KEY]?.revision || 1,
    };
  }

  return orders;
};

export const normalizeLeafTabLiveBookmarkSnapshot = (
  snapshot: LeafTabSyncSnapshot,
): LeafTabSyncSnapshot => ({
  ...snapshot,
  bookmarkFolders: filterLeafTabLiveBookmarkFolders(snapshot),
  bookmarkItems: filterLeafTabLiveBookmarkItems(snapshot),
  bookmarkOrders: filterLeafTabLiveBookmarkOrders(snapshot),
});

export const countLeafTabLiveBookmarkEntities = (
  snapshot: LeafTabSyncSnapshot | null | undefined,
) => {
  if (!snapshot) {
    return {
      bookmarkFolders: 0,
      bookmarkItems: 0,
      tombstones: 0,
    };
  }
  return {
    bookmarkFolders: Object.keys(filterLeafTabLiveBookmarkFolders(snapshot)).length,
    bookmarkItems: Object.keys(filterLeafTabLiveBookmarkItems(snapshot)).length,
    tombstones: Object.keys(snapshot.tombstones || {}).length,
  };
};

const sortRecord = <T>(record: Record<string, T>): Record<string, T> => {
  return Object.fromEntries(
    Object.entries(record).sort(([left], [right]) => left.localeCompare(right)),
  );
};

export const assertLeafTabBookmarkTreeMatchesSnapshot = (
  bookmarkTree: LeafTabBookmarkTreeDraft,
  expectedSnapshot: LeafTabSyncSnapshot,
): void => {
  const expected = normalizeLeafTabLiveBookmarkSnapshot(expectedSnapshot);
  const actualFolders = Object.fromEntries(bookmarkTree.folders.map((folder) => [folder.entityId, {
    parentId: folder.parentId,
    title: folder.title,
  }]));
  const actualItems = Object.fromEntries(bookmarkTree.items.map((item) => [item.entityId, {
    parentId: item.parentId,
    title: item.title,
    url: normalizeChromeBookmarkUrl(item.url),
  }]));
  const actualOrders = Object.fromEntries(
    Object.entries(bookmarkTree.orderIdsByParent).map(([parentId, ids]) => [parentId, ids.slice()]),
  );
  const expectedFolders = Object.fromEntries(Object.values(expected.bookmarkFolders).map((folder) => [folder.id, {
    parentId: folder.parentId,
    title: folder.title,
  }]));
  const expectedItems = Object.fromEntries(Object.values(expected.bookmarkItems).map((item) => [item.id, {
    parentId: item.parentId,
    title: item.title,
    url: normalizeChromeBookmarkUrl(item.url),
  }]));
  const expectedOrders = Object.fromEntries(
    Object.entries(expected.bookmarkOrders).map(([key, order]) => [key, order.ids.slice()]),
  );

  const actualContent = JSON.stringify({
    folders: sortRecord(actualFolders),
    items: sortRecord(actualItems),
    orders: sortRecord(actualOrders),
  });
  const expectedContent = JSON.stringify({
    folders: sortRecord(expectedFolders),
    items: sortRecord(expectedItems),
    orders: sortRecord(expectedOrders),
  });
  if (actualContent !== expectedContent) {
    throw new Error('本地书签落地校验未通过，已停止提交同步基线。');
  }
};
