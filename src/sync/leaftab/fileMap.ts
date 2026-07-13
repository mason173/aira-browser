import type {
  LeafTabSyncBaseline,
  LeafTabSyncBookmarkFolderEntity,
  LeafTabSyncBookmarkItemEntity,
  LeafTabSyncBookmarkOrder,
  LeafTabSyncCommitFile,
  LeafTabSyncHeadFile,
  LeafTabSyncManifestFile,
  LeafTabSyncManifestPackRef,
  LeafTabSyncPackKind,
  LeafTabSyncSnapshot,
  LeafTabSyncTombstone,
} from './schema';
import {
  createLeafTabSyncCommitFile,
  createLeafTabSyncHeadFile,
  toLeafTabSyncWireBookmarkDataSet,
  LEAFTAB_SYNC_APP_PRIVATE_BOOKMARKS_FILE,
  getLeafTabSyncCommitPath,
  getLeafTabSyncHeadPath,
  getLeafTabSyncManifestPath,
  getLeafTabSyncPackPath,
  LEAFTAB_SYNC_BOOKMARK_FOLDER_PACK_SHARDS,
  LEAFTAB_SYNC_BOOKMARK_ITEM_PACK_SHARDS,
  LEAFTAB_SYNC_DEFAULT_ROOT,
  LEAFTAB_SYNC_SCHEMA_VERSION,
  LEAFTAB_SYNC_TOMBSTONE_PACK_SHARDS,
} from './schema';

export type LeafTabSyncFileMap = Record<string, string>;

type LeafTabSyncJsonPayloadMap = Record<string, unknown>;

type LeafTabSyncShardedEntityKind =
  | 'bookmark-folders'
  | 'bookmark-items'
  | 'tombstones';

interface LeafTabSyncEntityPackFile<T, K extends LeafTabSyncShardedEntityKind> {
  version: typeof LEAFTAB_SYNC_SCHEMA_VERSION;
  kind: K;
  shard: string;
  generatedAt: string;
  entities: Record<string, T>;
}

interface LeafTabSyncBookmarkOrderPackFile {
  version: typeof LEAFTAB_SYNC_SCHEMA_VERSION;
  kind: 'bookmark-orders';
  generatedAt: string;
  orders: Record<string, LeafTabSyncBookmarkOrder>;
}

const normalizeRoot = (rootPath = LEAFTAB_SYNC_DEFAULT_ROOT) => {
  return rootPath.replace(/^\/+/, '').replace(/\/+$/, '') || LEAFTAB_SYNC_DEFAULT_ROOT;
};

const stableStringify = (value: unknown) => JSON.stringify(value, null, 2);
const sameContent = (left: unknown, right: unknown) => JSON.stringify(left) === JSON.stringify(right);

const createEmptyCommit = (
  snapshot: LeafTabSyncSnapshot,
  rootPath = LEAFTAB_SYNC_DEFAULT_ROOT,
): LeafTabSyncCommitFile => {
  return createLeafTabSyncCommitFile({
    deviceId: snapshot.meta.deviceId,
    createdAt: snapshot.meta.generatedAt,
    parentCommitId: null,
    snapshot,
    rootPath,
  });
};

const hashStringToShard = (value: string, shardCount: number) => {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return ((hash >>> 0) % shardCount).toString(16).padStart(2, '0');
};

const sortRecord = <T>(value: Record<string, T>) => {
  return Object.fromEntries(
    Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right)),
  ) as Record<string, T>;
};

const createEmptyShardMap = <T>(count: number) => {
  const map: Record<string, Record<string, T>> = {};
  for (let index = 0; index < count; index += 1) {
    map[index.toString(16).padStart(2, '0')] = {};
  }
  return map;
};

const shardEntityRecord = <T>(
  entities: Record<string, T>,
  shardCount: number,
  keyBuilder?: (entityId: string, entity: T) => string,
) => {
  const shards = createEmptyShardMap<T>(shardCount);
  Object.entries(entities).forEach(([entityId, entity]) => {
    const shard = hashStringToShard(keyBuilder ? keyBuilder(entityId, entity) : entityId, shardCount);
    shards[shard][entityId] = entity;
  });
  return shards;
};

const createManifestPackRef = (
  kind: LeafTabSyncPackKind,
  path: string,
  itemCount: number,
  shard: string | null = null,
): LeafTabSyncManifestPackRef => ({
  kind,
  path,
  shard,
  itemCount,
});

const shouldIncludePath = (includePaths: Set<string> | null | undefined, path: string) => {
  return !includePaths || includePaths.has(path);
};

const buildSnapshotPayloadMap = (
  snapshot: LeafTabSyncSnapshot,
  rootPath: string,
  commit: LeafTabSyncCommitFile,
  includePaths?: Set<string> | null,
) => {
  const payloads: LeafTabSyncJsonPayloadMap = {};
  const manifestPacks: LeafTabSyncManifestPackRef[] = [];

  const bookmarkFolderShards = shardEntityRecord(
    snapshot.bookmarkFolders,
    LEAFTAB_SYNC_BOOKMARK_FOLDER_PACK_SHARDS,
  );
  Object.entries(bookmarkFolderShards)
    .sort(([left], [right]) => left.localeCompare(right))
    .forEach(([shard, entities]) => {
      const path = getLeafTabSyncPackPath('bookmark-folders', shard, rootPath);
      if (shouldIncludePath(includePaths, path)) {
        payloads[path] = {
          version: LEAFTAB_SYNC_SCHEMA_VERSION,
          kind: 'bookmark-folders',
          shard,
          generatedAt: snapshot.meta.generatedAt,
          entities: sortRecord(entities),
        } satisfies LeafTabSyncEntityPackFile<LeafTabSyncBookmarkFolderEntity, 'bookmark-folders'>;
      }
      manifestPacks.push(
        createManifestPackRef('bookmark-folders', path, Object.keys(entities).length, shard),
      );
    });

  const bookmarkItemShards = shardEntityRecord(
    snapshot.bookmarkItems,
    LEAFTAB_SYNC_BOOKMARK_ITEM_PACK_SHARDS,
  );
  Object.entries(bookmarkItemShards)
    .sort(([left], [right]) => left.localeCompare(right))
    .forEach(([shard, entities]) => {
      const path = getLeafTabSyncPackPath('bookmark-items', shard, rootPath);
      if (shouldIncludePath(includePaths, path)) {
        payloads[path] = {
          version: LEAFTAB_SYNC_SCHEMA_VERSION,
          kind: 'bookmark-items',
          shard,
          generatedAt: snapshot.meta.generatedAt,
          entities: sortRecord(entities),
        } satisfies LeafTabSyncEntityPackFile<LeafTabSyncBookmarkItemEntity, 'bookmark-items'>;
      }
      manifestPacks.push(
        createManifestPackRef('bookmark-items', path, Object.keys(entities).length, shard),
      );
    });

  const bookmarkOrdersPath = getLeafTabSyncPackPath('bookmark-orders', null, rootPath);
  if (shouldIncludePath(includePaths, bookmarkOrdersPath)) {
    payloads[bookmarkOrdersPath] = {
      version: LEAFTAB_SYNC_SCHEMA_VERSION,
      kind: 'bookmark-orders',
      generatedAt: snapshot.meta.generatedAt,
      orders: sortRecord(snapshot.bookmarkOrders),
    } satisfies LeafTabSyncBookmarkOrderPackFile;
  }
  manifestPacks.push(
    createManifestPackRef('bookmark-orders', bookmarkOrdersPath, Object.keys(snapshot.bookmarkOrders).length),
  );

  const tombstoneEntities = Object.fromEntries(
    Object.values(snapshot.tombstones).map((entry) => [`${entry.type}:${entry.id}`, entry]),
  );
  const tombstoneShards = shardEntityRecord(
    tombstoneEntities,
    LEAFTAB_SYNC_TOMBSTONE_PACK_SHARDS,
  );
  Object.entries(tombstoneShards)
    .sort(([left], [right]) => left.localeCompare(right))
    .forEach(([shard, entities]) => {
      const path = getLeafTabSyncPackPath('tombstones', shard, rootPath);
      if (shouldIncludePath(includePaths, path)) {
        payloads[path] = {
          version: LEAFTAB_SYNC_SCHEMA_VERSION,
          kind: 'tombstones',
          shard,
          generatedAt: snapshot.meta.generatedAt,
          entities: sortRecord(entities),
        } satisfies LeafTabSyncEntityPackFile<LeafTabSyncTombstone, 'tombstones'>;
      }
      manifestPacks.push(
        createManifestPackRef('tombstones', path, Object.keys(entities).length, shard),
      );
    });

  const manifestPath = getLeafTabSyncManifestPath(rootPath);
  if (shouldIncludePath(includePaths, manifestPath)) {
    payloads[manifestPath] = {
      version: LEAFTAB_SYNC_SCHEMA_VERSION,
      commitId: commit.id,
      deviceId: snapshot.meta.deviceId,
      generatedAt: snapshot.meta.generatedAt,
      topologyId: snapshot.meta.topologyId,
      topologyVersion: snapshot.meta.topologyVersion,
      topologyOwnerUid: snapshot.meta.topologyOwnerUid,
      primaryRemoteKind: snapshot.meta.primaryRemoteKind,
      backupRemoteKinds: snapshot.meta.backupRemoteKinds?.slice(),
      packs: manifestPacks,
    } satisfies LeafTabSyncManifestFile;
  }

  const appPrivateBookmarksPath = `${rootPath}/${LEAFTAB_SYNC_APP_PRIVATE_BOOKMARKS_FILE}`;
  if (shouldIncludePath(includePaths, appPrivateBookmarksPath)) {
    payloads[appPrivateBookmarksPath] = toLeafTabSyncWireBookmarkDataSet(snapshot.appPrivateBookmarks) || null;
  }

  return payloads;
};

const collectChangedShardedPaths = <T>(
  previousEntities: Record<string, T>,
  nextEntities: Record<string, T>,
  shardCount: number,
  kind: LeafTabSyncShardedEntityKind,
  rootPath: string,
  identityBuilder?: (entityId: string, entity: T) => string,
) => {
  const changedPaths = new Set<string>();
  const allIds = new Set([
    ...Object.keys(previousEntities || {}),
    ...Object.keys(nextEntities || {}),
  ]);

  allIds.forEach((entityId) => {
    const previousEntity = previousEntities[entityId];
    const nextEntity = nextEntities[entityId];
    if (sameContent(previousEntity, nextEntity)) {
      return;
    }

    if (previousEntity) {
      changedPaths.add(
        getLeafTabSyncPackPath(
          kind,
          hashStringToShard(identityBuilder ? identityBuilder(entityId, previousEntity) : entityId, shardCount),
          rootPath,
        ),
      );
    }

    if (nextEntity) {
      changedPaths.add(
        getLeafTabSyncPackPath(
          kind,
          hashStringToShard(identityBuilder ? identityBuilder(entityId, nextEntity) : entityId, shardCount),
          rootPath,
        ),
      );
    }
  });

  return changedPaths;
};

export const collectLeafTabSyncChangedPayloadPaths = (
  previousSnapshot: LeafTabSyncSnapshot | null | undefined,
  nextSnapshot: LeafTabSyncSnapshot,
  options?: {
    rootPath?: string;
  },
) => {
  const rootPath = normalizeRoot(options?.rootPath);
  if (!previousSnapshot) {
    return null;
  }

  const changedPaths = new Set<string>();

  collectChangedShardedPaths(
    previousSnapshot.bookmarkFolders || {},
    nextSnapshot.bookmarkFolders || {},
    LEAFTAB_SYNC_BOOKMARK_FOLDER_PACK_SHARDS,
    'bookmark-folders',
    rootPath,
  ).forEach((path) => changedPaths.add(path));

  collectChangedShardedPaths(
    previousSnapshot.bookmarkItems || {},
    nextSnapshot.bookmarkItems || {},
    LEAFTAB_SYNC_BOOKMARK_ITEM_PACK_SHARDS,
    'bookmark-items',
    rootPath,
  ).forEach((path) => changedPaths.add(path));

  if (!sameContent(previousSnapshot.bookmarkOrders, nextSnapshot.bookmarkOrders)) {
    changedPaths.add(getLeafTabSyncPackPath('bookmark-orders', null, rootPath));
  }

  const previousTombstones = Object.fromEntries(
    Object.values(previousSnapshot.tombstones || {}).map((entry) => [`${entry.type}:${entry.id}`, entry]),
  );
  const nextTombstones = Object.fromEntries(
    Object.values(nextSnapshot.tombstones || {}).map((entry) => [`${entry.type}:${entry.id}`, entry]),
  );
  collectChangedShardedPaths(
    previousTombstones,
    nextTombstones,
    LEAFTAB_SYNC_TOMBSTONE_PACK_SHARDS,
    'tombstones',
    rootPath,
  ).forEach((path) => changedPaths.add(path));

  if (!sameContent(previousSnapshot.appPrivateBookmarks, nextSnapshot.appPrivateBookmarks)) {
    changedPaths.add(`${rootPath}/${LEAFTAB_SYNC_APP_PRIVATE_BOOKMARKS_FILE}`);
  }

  changedPaths.add(getLeafTabSyncManifestPath(rootPath));
  return changedPaths;
};

export const createLeafTabSyncSerializedSnapshot = (
  snapshot: LeafTabSyncSnapshot,
  options?: {
    rootPath?: string;
    commit?: LeafTabSyncCommitFile | null;
    head?: LeafTabSyncHeadFile | null;
    includePaths?: Iterable<string> | null;
  },
) => {
  const rootPath = normalizeRoot(options?.rootPath);
  const commit = options?.commit || createEmptyCommit(snapshot, rootPath);
  const head = options?.head || createLeafTabSyncHeadFile(commit.id, commit.createdAt);
  const includePaths = options?.includePaths ? new Set(options.includePaths) : null;
  const payloads = buildSnapshotPayloadMap(snapshot, rootPath, commit, includePaths);
  const files: LeafTabSyncFileMap = Object.fromEntries(
    Object.entries(payloads).map(([path, payload]) => [path, stableStringify(payload)]),
  );

  files[getLeafTabSyncCommitPath(commit.id, rootPath)] = stableStringify(commit);
  files[getLeafTabSyncHeadPath(rootPath)] = stableStringify(head);

  return {
    commit,
    head,
    payloads,
    files,
  };
};

export const serializeLeafTabSyncSnapshotToFileMap = (
  snapshot: LeafTabSyncSnapshot,
  options?: {
    rootPath?: string;
    commit?: LeafTabSyncCommitFile | null;
    head?: LeafTabSyncHeadFile | null;
  },
): LeafTabSyncFileMap => {
  return createLeafTabSyncSerializedSnapshot(snapshot, options).files;
};

export const serializeLeafTabSyncSnapshotPayloadFileMap = (
  snapshot: LeafTabSyncSnapshot,
  options?: {
    rootPath?: string;
    commit?: LeafTabSyncCommitFile | null;
  },
): LeafTabSyncFileMap => {
  const serialized = createLeafTabSyncSerializedSnapshot(snapshot, {
    rootPath: options?.rootPath,
    commit: options?.commit,
  });
  return Object.fromEntries(
    Object.entries(serialized.payloads).map(([path, payload]) => [path, stableStringify(payload)]),
  );
};

export const createLeafTabSyncBaselineFromSnapshot = (
  snapshot: LeafTabSyncSnapshot,
  options?: {
    commitId?: string | null;
    rootPath?: string;
  },
): LeafTabSyncBaseline => {
  const rootPath = normalizeRoot(options?.rootPath);
  const commit = createLeafTabSyncCommitFile({
    deviceId: snapshot.meta.deviceId,
    createdAt: snapshot.meta.generatedAt,
    parentCommitId: options?.commitId ?? null,
    snapshot,
    rootPath,
  });
  const head = createLeafTabSyncHeadFile(commit.id, commit.createdAt);
  const files = serializeLeafTabSyncSnapshotToFileMap(snapshot, {
    rootPath,
    commit,
    head,
  });

  return {
    commitId: options?.commitId ?? commit.id,
    files: Object.fromEntries(
      Object.entries(files).map(([path, content]) => [
        path,
        { sha: null, content },
      ]),
    ),
    snapshot,
    savedAt: snapshot.meta.generatedAt,
  };
};
