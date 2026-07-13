export const LEAFTAB_SYNC_SCHEMA_VERSION = 2 as const;
export const LEAFTAB_SYNC_DEFAULT_ROOT = 'aira/v1/bookmarks';
export const LEAFTAB_SYNC_APP_PRIVATE_BOOKMARKS_FILE = 'app-private-bookmarks.json';
export const LEAFTAB_SYNC_BOOKMARK_FOLDER_PACK_SHARDS = 4;
export const LEAFTAB_SYNC_BOOKMARK_ITEM_PACK_SHARDS = 16;
export const LEAFTAB_SYNC_TOMBSTONE_PACK_SHARDS = 8;

export type LeafTabSyncEntityType = 'bookmark-folder' | 'bookmark-item';
export type LeafTabSyncOrderType = 'bookmark-order';

export interface LeafTabSyncTopologyMetadata {
  topologyId?: string;
  topologyVersion?: number;
  topologyOwnerUid?: string;
  primaryRemoteKind?: string;
  backupRemoteKinds?: string[];
}

export type LeafTabSyncSnapshotMeta = LeafTabSyncTopologyMetadata & {
  version: typeof LEAFTAB_SYNC_SCHEMA_VERSION;
  deviceId: string;
  generatedAt: string;
} & Record<string, unknown>;

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

export type LeafTabSyncEntity =
  | LeafTabSyncBookmarkFolderEntity
  | LeafTabSyncBookmarkItemEntity;

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

export interface LeafTabSyncHeadFile {
  version: typeof LEAFTAB_SYNC_SCHEMA_VERSION;
  commitId: string;
  updatedAt: string;
}

export type LeafTabSyncPackKind =
  | 'bookmark-folders'
  | 'bookmark-items'
  | 'bookmark-orders'
  | 'tombstones';

export interface LeafTabSyncManifestPackRef {
  kind: LeafTabSyncPackKind;
  path: string;
  shard: string | null;
  itemCount: number;
}

export interface LeafTabSyncManifestFile {
  version: typeof LEAFTAB_SYNC_SCHEMA_VERSION;
  commitId: string;
  deviceId: string;
  generatedAt: string;
  topologyId?: string;
  topologyVersion?: number;
  topologyOwnerUid?: string;
  primaryRemoteKind?: string;
  backupRemoteKinds?: string[];
  packs: LeafTabSyncManifestPackRef[];
}

export interface LeafTabSyncCommitFile {
  id: string;
  version: typeof LEAFTAB_SYNC_SCHEMA_VERSION;
  deviceId: string;
  createdAt: string;
  parentCommitId: string | null;
  manifestPath: string;
  operationsPath?: string;
  summary: {
    bookmarkFolders: number;
    bookmarkItems: number;
    tombstones: number;
  };
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

export interface LeafTabSyncBaselineFileEntry {
  sha: string | null;
  content: string;
}

export interface LeafTabSyncBaseline {
  commitId: string | null;
  files: Record<string, LeafTabSyncBaselineFileEntry>;
  snapshot?: LeafTabSyncSnapshot;
  savedAt: string;
}

const normalizeRoot = (rootPath = LEAFTAB_SYNC_DEFAULT_ROOT) => {
  return rootPath.replace(/^\/+/, '').replace(/\/+$/, '') || LEAFTAB_SYNC_DEFAULT_ROOT;
};

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
};

const collectionValues = (value: unknown): unknown[] => {
  if (Array.isArray(value)) return value;
  if (isRecord(value)) return Object.values(value);
  return [];
};

const normalizeOptionalString = (value: unknown): string | undefined => {
  const normalized = typeof value === 'string' ? value.trim() : '';
  return normalized || undefined;
};

const normalizeOptionalPositiveInteger = (value: unknown): number | undefined => {
  const normalized = Math.floor(Number(value));
  return Number.isFinite(normalized) && normalized > 0 ? normalized : undefined;
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
  const backupRemoteKinds = Array.isArray(source.backupRemoteKinds)
    ? source.backupRemoteKinds.map((entry) => String(entry || '').trim()).filter(Boolean)
    : undefined;
  return {
    ...source,
    version: LEAFTAB_SYNC_SCHEMA_VERSION,
    deviceId,
    generatedAt,
    topologyId: normalizeOptionalString(source.topologyId),
    topologyVersion: normalizeOptionalPositiveInteger(source.topologyVersion),
    topologyOwnerUid: normalizeOptionalString(source.topologyOwnerUid),
    primaryRemoteKind: normalizeOptionalString(source.primaryRemoteKind),
    backupRemoteKinds,
  } as LeafTabSyncSnapshotMeta;
};

export const createLeafTabSyncDeviceId = () => {
  try {
    return crypto.randomUUID();
  } catch {
    return `dev_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  }
};

export const createLeafTabSyncCommitId = (
  deviceId: string,
  createdAt = new Date().toISOString(),
) => {
  const safeTimestamp = createdAt.replace(/[:.]/g, '-');
  const compactDeviceId = (deviceId || 'device').replace(/[^a-zA-Z0-9_-]/g, '_');
  return `cmt_${safeTimestamp}_${compactDeviceId}`;
};

export const getLeafTabSyncHeadPath = (rootPath = LEAFTAB_SYNC_DEFAULT_ROOT) => {
  return `${normalizeRoot(rootPath)}/head.json`;
};

export const getLeafTabSyncLockPath = (rootPath = LEAFTAB_SYNC_DEFAULT_ROOT) => {
  return `${normalizeRoot(rootPath)}/sync.lock.json`;
};

export const getLeafTabSyncCommitPath = (
  commitId: string,
  rootPath = LEAFTAB_SYNC_DEFAULT_ROOT,
) => {
  return `${normalizeRoot(rootPath)}/commits/${commitId}.json`;
};

export const getLeafTabSyncManifestPath = (rootPath = LEAFTAB_SYNC_DEFAULT_ROOT) => {
  return `${normalizeRoot(rootPath)}/manifest.json`;
};

export const getLeafTabSyncPackPath = (
  kind: LeafTabSyncPackKind,
  shard: string | null = null,
  rootPath = LEAFTAB_SYNC_DEFAULT_ROOT,
) => {
  const shardSuffix = shard ? `-${shard}` : '';
  return `${normalizeRoot(rootPath)}/packs/${kind}${shardSuffix}.pack.json`;
};

export const createLeafTabSyncHeadFile = (
  commitId: string,
  updatedAt = new Date().toISOString(),
): LeafTabSyncHeadFile => ({
  version: LEAFTAB_SYNC_SCHEMA_VERSION,
  commitId,
  updatedAt,
});

export const createLeafTabSyncCommitFile = (params: {
  deviceId: string;
  createdAt?: string;
  parentCommitId?: string | null;
  snapshot: LeafTabSyncSnapshot;
  rootPath?: string;
  operationsPath?: string;
}): LeafTabSyncCommitFile => {
  const createdAt = params.createdAt || new Date().toISOString();
  const id = createLeafTabSyncCommitId(params.deviceId, createdAt);
  return {
    id,
    version: LEAFTAB_SYNC_SCHEMA_VERSION,
    deviceId: params.deviceId,
    createdAt,
    parentCommitId: params.parentCommitId ?? null,
    manifestPath: getLeafTabSyncManifestPath(params.rootPath || LEAFTAB_SYNC_DEFAULT_ROOT),
    ...(params.operationsPath ? { operationsPath: params.operationsPath } : {}),
    summary: {
      bookmarkFolders: Object.keys(params.snapshot.bookmarkFolders).length,
      bookmarkItems: Object.keys(params.snapshot.bookmarkItems).length,
      tombstones: Object.keys(params.snapshot.tombstones).length,
    },
  };
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
  return Boolean(
    value &&
      typeof value === 'object' &&
      (value as { type?: unknown }).type === 'bookmark-folder' &&
      typeof (value as { id?: unknown }).id === 'string',
  );
};

export const isLeafTabSyncBookmarkItemEntity = (
  value: unknown,
): value is LeafTabSyncBookmarkItemEntity => {
  return Boolean(
    value &&
      typeof value === 'object' &&
      (value as { type?: unknown }).type === 'bookmark-item' &&
      typeof (value as { id?: unknown }).id === 'string',
  );
};

export const isLeafTabSyncBookmarkOrder = (
  value: unknown,
): value is LeafTabSyncBookmarkOrder => {
  return Boolean(
    value &&
      typeof value === 'object' &&
      (value as { type?: unknown }).type === 'bookmark-order' &&
      Array.isArray((value as { ids?: unknown }).ids),
  );
};

export const isLeafTabSyncTombstone = (
  value: unknown,
): value is LeafTabSyncTombstone => {
  return Boolean(
    value &&
      typeof value === 'object' &&
      typeof (value as { id?: unknown }).id === 'string' &&
      (
        (value as { type?: unknown }).type === 'bookmark-folder' ||
        (value as { type?: unknown }).type === 'bookmark-item'
      ) &&
      typeof (value as { deletedAt?: unknown }).deletedAt === 'string',
  );
};
