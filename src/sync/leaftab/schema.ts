export const LEAFTAB_SYNC_SCHEMA_VERSION = 2 as const;
export const LEAFTAB_SYNC_DEFAULT_ROOT = 'aira/v1/bookmarks';
export const LEAFTAB_SYNC_BOOKMARK_FOLDER_PACK_SHARDS = 4;
export const LEAFTAB_SYNC_BOOKMARK_ITEM_PACK_SHARDS = 16;
export const LEAFTAB_SYNC_TOMBSTONE_PACK_SHARDS = 8;

export type LeafTabSyncEntityType = 'bookmark-folder' | 'bookmark-item';
export type LeafTabSyncOrderType = 'bookmark-order';

export interface LeafTabSyncSnapshotMeta {
  version: typeof LEAFTAB_SYNC_SCHEMA_VERSION;
  deviceId: string;
  generatedAt: string;
}

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
  packs: LeafTabSyncManifestPackRef[];
}

export interface LeafTabSyncCommitFile {
  id: string;
  version: typeof LEAFTAB_SYNC_SCHEMA_VERSION;
  deviceId: string;
  createdAt: string;
  parentCommitId: string | null;
  manifestPath: string;
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
    summary: {
      bookmarkFolders: Object.keys(params.snapshot.bookmarkFolders).length,
      bookmarkItems: Object.keys(params.snapshot.bookmarkItems).length,
      tombstones: Object.keys(params.snapshot.tombstones).length,
    },
  };
};

export const normalizeLeafTabSyncSnapshot = (
  snapshot: LeafTabSyncSnapshot | null | undefined,
): LeafTabSyncSnapshot | null => {
  if (!snapshot) return null;

  const generatedAt = snapshot.meta?.generatedAt || new Date(0).toISOString();
  const deviceId = snapshot.meta?.deviceId || 'unknown-device';

  return {
    meta: {
      version: LEAFTAB_SYNC_SCHEMA_VERSION,
      deviceId,
      generatedAt,
    },
    bookmarkFolders: snapshot.bookmarkFolders || {},
    bookmarkItems: snapshot.bookmarkItems || {},
    bookmarkOrders: snapshot.bookmarkOrders || {},
    tombstones: snapshot.tombstones || {},
  };
};

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
