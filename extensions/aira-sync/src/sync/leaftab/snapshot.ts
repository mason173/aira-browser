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
