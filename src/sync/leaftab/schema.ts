export const LEAFTAB_SYNC_SCHEMA_VERSION = 2 as const;
export const LEAFTAB_SYNC_DEFAULT_ROOT = 'aira/g2/bookmarks';

export type LeafTabSyncEntityType = 'bookmark-folder' | 'bookmark-item';

export type LeafTabSyncSnapshotMeta = {
  version: typeof LEAFTAB_SYNC_SCHEMA_VERSION;
  deviceId: string;
  generatedAt: string;
};

export interface LeafTabSyncBaseEntity {
  id: string;
  type: LeafTabSyncEntityType;
  createdAt: string;
  updatedAt: string;
  updatedBy: string;
  revision: number;
}

export interface LeafTabSyncBookmarkFolderEntity extends LeafTabSyncBaseEntity {
  type: 'bookmark-folder';
  parentId: string | null;
  title: string;
}

export interface LeafTabSyncBookmarkItemEntity extends LeafTabSyncBaseEntity {
  type: 'bookmark-item';
  parentId: string | null;
  title: string;
  url: string;
}

export interface LeafTabSyncBookmarkOrder {
  type: 'bookmark-order';
  parentId: string | null;
  ids: string[];
  updatedAt: string;
  updatedBy: string;
  revision: number;
}

export interface LeafTabSyncTombstone {
  id: string;
  type: LeafTabSyncEntityType;
  deletedAt: string;
  deletedBy: string;
  lastKnownRevision: number;
}

export interface LeafTabSyncBookmarkDataSet {
  bookmarkFolders: Record<string, LeafTabSyncBookmarkFolderEntity>;
  bookmarkItems: Record<string, LeafTabSyncBookmarkItemEntity>;
  bookmarkOrders: Record<string, LeafTabSyncBookmarkOrder>;
  tombstones: Record<string, LeafTabSyncTombstone>;
}

export interface LeafTabSyncSnapshot {
  meta: LeafTabSyncSnapshotMeta;
  bookmarkFolders: Record<string, LeafTabSyncBookmarkFolderEntity>;
  bookmarkItems: Record<string, LeafTabSyncBookmarkItemEntity>;
  bookmarkOrders: Record<string, LeafTabSyncBookmarkOrder>;
  tombstones: Record<string, LeafTabSyncTombstone>;
  appPrivateBookmarks?: LeafTabSyncBookmarkDataSet;
}

export interface LeafTabSyncWireBookmarkDataSet {
  bookmarkFolders: LeafTabSyncBookmarkFolderEntity[];
  bookmarkItems: LeafTabSyncBookmarkItemEntity[];
  bookmarkOrders: LeafTabSyncBookmarkOrder[];
  tombstones: LeafTabSyncTombstone[];
}

export interface LeafTabSyncWireSnapshot {
  meta: LeafTabSyncSnapshotMeta;
  bookmarkFolders: LeafTabSyncBookmarkFolderEntity[];
  bookmarkItems: LeafTabSyncBookmarkItemEntity[];
  bookmarkOrders: LeafTabSyncBookmarkOrder[];
  tombstones: LeafTabSyncTombstone[];
  appPrivateBookmarks?: LeafTabSyncWireBookmarkDataSet;
}

export interface LeafTabSyncBaseline {
  commitId: string | null;
  snapshot?: LeafTabSyncSnapshot;
  savedAt: string;
}

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
};

const collectionValues = (value: unknown): unknown[] => {
  if (Array.isArray(value)) return value;
  if (isRecord(value)) return Object.values(value);
  return [];
};

const isNonEmptyString = (value: unknown): value is string => {
  return typeof value === 'string' && value.trim().length > 0;
};

const isNullableParentId = (value: unknown): value is string | null => {
  return value === null || isNonEmptyString(value);
};

const isNonNegativeInteger = (value: unknown): value is number => {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && Math.floor(value) === value;
};

const hasUniqueKeys = <T>(values: T[], keyOf: (value: T) => string): boolean => {
  const keys = new Set<string>();
  for (const value of values) {
    const key = keyOf(value);
    if (keys.has(key)) return false;
    keys.add(key);
  }
  return true;
};

const isLeafTabSyncSnapshotMeta = (value: unknown): value is LeafTabSyncSnapshotMeta => {
  if (!isRecord(value)) return false;
  return value.version === LEAFTAB_SYNC_SCHEMA_VERSION
    && isNonEmptyString(value.deviceId)
    && isNonEmptyString(value.generatedAt);
};

export const createLeafTabSyncOrderKey = (parentId: string | null | undefined) => parentId || '__root__';

export const createLeafTabSyncTombstoneKey = (
  tombstoneOrType: LeafTabSyncTombstone | LeafTabSyncEntityType,
  id?: string,
) => {
  const type = typeof tombstoneOrType === 'string' ? tombstoneOrType : tombstoneOrType.type;
  const entityId = typeof tombstoneOrType === 'string' ? String(id || '') : tombstoneOrType.id;
  return `${type}|${entityId}`;
};

export const cloneLeafTabSyncSnapshotMeta = (
  value: unknown,
  overrides?: Partial<Pick<LeafTabSyncSnapshotMeta, 'deviceId' | 'generatedAt'>>,
): LeafTabSyncSnapshotMeta => {
  const source = isRecord(value) ? value : {};
  const deviceId = String(overrides?.deviceId || source.deviceId || 'unknown-device');
  const generatedAt = String(overrides?.generatedAt || source.generatedAt || new Date(0).toISOString());
  return {
    version: LEAFTAB_SYNC_SCHEMA_VERSION,
    deviceId,
    generatedAt,
  };
};

export const createLeafTabSyncCommitId = (
  deviceId: string,
  createdAt = new Date().toISOString(),
) => {
  const safeTimestamp = createdAt.replace(/[:.]/g, '-');
  const compactDeviceId = (deviceId || 'device').replace(/[^a-zA-Z0-9_-]/g, '_');
  return `cmt_${safeTimestamp}_${compactDeviceId}`;
};

export const normalizeLeafTabSyncSnapshot = (
  snapshot: unknown,
): LeafTabSyncSnapshot | null => {
  if (!isRecord(snapshot)) return null;

  return {
    meta: cloneLeafTabSyncSnapshotMeta(snapshot.meta),
    bookmarkFolders: Object.fromEntries(
      collectionValues(snapshot.bookmarkFolders)
        .filter(isLeafTabSyncBookmarkFolderEntity)
        .map((entry) => [entry.id, entry]),
    ),
    bookmarkItems: Object.fromEntries(
      collectionValues(snapshot.bookmarkItems)
        .filter(isLeafTabSyncBookmarkItemEntity)
        .map((entry) => [entry.id, entry]),
    ),
    bookmarkOrders: Object.fromEntries(
      collectionValues(snapshot.bookmarkOrders)
        .filter(isLeafTabSyncBookmarkOrder)
        .map((entry) => [createLeafTabSyncOrderKey(entry.parentId), entry]),
    ),
    tombstones: Object.fromEntries(
      collectionValues(snapshot.tombstones)
        .filter(isLeafTabSyncTombstone)
        .map((entry) => [createLeafTabSyncTombstoneKey(entry), entry]),
    ),
    appPrivateBookmarks: normalizeLeafTabSyncBookmarkDataSet(snapshot.appPrivateBookmarks),
  };
};

export const normalizeLeafTabSyncBookmarkDataSet = (
  value: unknown,
): LeafTabSyncBookmarkDataSet | undefined => {
  if (!isRecord(value)) return undefined;
  return {
    bookmarkFolders: Object.fromEntries(
      collectionValues(value.bookmarkFolders)
        .filter(isLeafTabSyncBookmarkFolderEntity)
        .map((entry) => [entry.id, entry]),
    ),
    bookmarkItems: Object.fromEntries(
      collectionValues(value.bookmarkItems)
        .filter(isLeafTabSyncBookmarkItemEntity)
        .map((entry) => [entry.id, entry]),
    ),
    bookmarkOrders: Object.fromEntries(
      collectionValues(value.bookmarkOrders)
        .filter(isLeafTabSyncBookmarkOrder)
        .map((entry) => [createLeafTabSyncOrderKey(entry.parentId), entry]),
    ),
    tombstones: Object.fromEntries(
      collectionValues(value.tombstones)
        .filter(isLeafTabSyncTombstone)
        .map((entry) => [createLeafTabSyncTombstoneKey(entry), entry]),
    ),
  };
};

export const toLeafTabSyncWireBookmarkDataSet = (
  value: LeafTabSyncBookmarkDataSet | null | undefined,
): LeafTabSyncWireBookmarkDataSet | undefined => {
  if (!value) return undefined;
  return {
    bookmarkFolders: Object.values(value.bookmarkFolders),
    bookmarkItems: Object.values(value.bookmarkItems),
    bookmarkOrders: Object.values(value.bookmarkOrders),
    tombstones: Object.values(value.tombstones),
  };
};

export const toLeafTabSyncWireSnapshot = (snapshot: LeafTabSyncSnapshot): LeafTabSyncWireSnapshot => ({
  meta: cloneLeafTabSyncSnapshotMeta(snapshot.meta),
  bookmarkFolders: Object.values(snapshot.bookmarkFolders),
  bookmarkItems: Object.values(snapshot.bookmarkItems),
  bookmarkOrders: Object.values(snapshot.bookmarkOrders),
  tombstones: Object.values(snapshot.tombstones),
  appPrivateBookmarks: toLeafTabSyncWireBookmarkDataSet(snapshot.appPrivateBookmarks),
});

export const isLeafTabSyncBookmarkFolderEntity = (
  value: unknown,
): value is LeafTabSyncBookmarkFolderEntity => {
  if (!isRecord(value)) return false;
  return value.type === 'bookmark-folder'
    && isNonEmptyString(value.id)
    && isNonEmptyString(value.createdAt)
    && isNonEmptyString(value.updatedAt)
    && isNonEmptyString(value.updatedBy)
    && isNonNegativeInteger(value.revision)
    && isNullableParentId(value.parentId)
    && typeof value.title === 'string';
};

export const isLeafTabSyncBookmarkItemEntity = (
  value: unknown,
): value is LeafTabSyncBookmarkItemEntity => {
  if (!isRecord(value)) return false;
  return value.type === 'bookmark-item'
    && isNonEmptyString(value.id)
    && isNonEmptyString(value.createdAt)
    && isNonEmptyString(value.updatedAt)
    && isNonEmptyString(value.updatedBy)
    && isNonNegativeInteger(value.revision)
    && isNullableParentId(value.parentId)
    && typeof value.title === 'string'
    && typeof value.url === 'string';
};

export const isLeafTabSyncBookmarkOrder = (
  value: unknown,
): value is LeafTabSyncBookmarkOrder => {
  if (!isRecord(value) || !Array.isArray(value.ids)) return false;
  const ids = value.ids;
  return value.type === 'bookmark-order'
    && isNullableParentId(value.parentId)
    && ids.every(isNonEmptyString)
    && hasUniqueKeys(ids, (id) => id)
    && isNonEmptyString(value.updatedAt)
    && isNonEmptyString(value.updatedBy)
    && isNonNegativeInteger(value.revision);
};

export const isLeafTabSyncTombstone = (
  value: unknown,
): value is LeafTabSyncTombstone => {
  if (!isRecord(value)) return false;
  return isNonEmptyString(value.id)
    && (value.type === 'bookmark-folder' || value.type === 'bookmark-item')
    && isNonEmptyString(value.deletedAt)
    && isNonEmptyString(value.deletedBy)
    && isNonNegativeInteger(value.lastKnownRevision);
};

const isCanonicalLeafTabSyncWireDataSet = (
  value: unknown,
): value is LeafTabSyncWireBookmarkDataSet => {
  if (!isRecord(value)
    || !Array.isArray(value.bookmarkFolders)
    || !Array.isArray(value.bookmarkItems)
    || !Array.isArray(value.bookmarkOrders)
    || !Array.isArray(value.tombstones)) {
    return false;
  }
  const folders = value.bookmarkFolders;
  const items = value.bookmarkItems;
  const orders = value.bookmarkOrders;
  const tombstones = value.tombstones;
  if (!folders.every(isLeafTabSyncBookmarkFolderEntity)
    || !items.every(isLeafTabSyncBookmarkItemEntity)
    || !orders.every(isLeafTabSyncBookmarkOrder)
    || !tombstones.every(isLeafTabSyncTombstone)) {
    return false;
  }
  const folderIds = new Set(folders.map((entry) => entry.id));
  return !items.some((entry) => folderIds.has(entry.id))
    && hasUniqueKeys(folders, (entry) => entry.id)
    && hasUniqueKeys(items, (entry) => entry.id)
    && hasUniqueKeys(orders, (entry) => createLeafTabSyncOrderKey(entry.parentId))
    && hasUniqueKeys(tombstones, (entry) => createLeafTabSyncTombstoneKey(entry));
};

export const parseCanonicalLeafTabSyncWireSnapshot = (
  value: unknown,
): LeafTabSyncSnapshot | null => {
  if (!isRecord(value)
    || !isLeafTabSyncSnapshotMeta(value.meta)
    || !isCanonicalLeafTabSyncWireDataSet(value)) {
    return null;
  }
  if (value.appPrivateBookmarks !== undefined
    && !isCanonicalLeafTabSyncWireDataSet(value.appPrivateBookmarks)) {
    return null;
  }
  return normalizeLeafTabSyncSnapshot(value);
};
