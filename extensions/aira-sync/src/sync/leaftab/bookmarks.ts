import { getBookmarksApi } from '@/platform/runtime';
import {
  getExtensionStorageArea,
  readExtensionStorageRecord,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import { ensureExtensionPermission } from '@/utils/extensionPermissions';
import { LEAFTAB_BOOKMARK_MAPPING_KEY } from '@/features/sync/app/leafTabSyncStorageKeys';
import type { LeafTabSyncSnapshot } from './schema';

export interface LeafTabBookmarkFolderDraft {
  entityId: string;
  localNodeId: string;
  parentId: string | null;
  title: string;
}

export interface LeafTabBookmarkItemDraft {
  entityId: string;
  localNodeId: string;
  parentId: string | null;
  title: string;
  url: string;
}

export interface LeafTabBookmarkTreeDraft {
  folders: LeafTabBookmarkFolderDraft[];
  items: LeafTabBookmarkItemDraft[];
  orderIdsByParent: Record<string, string[]>;
  nodeIdToEntityId: Record<string, string>;
}

export class LeafTabBookmarkPermissionDeniedError extends Error {
  constructor(message = '未授予书签权限，已停止同步以保护现有书签数据') {
    super(message);
    this.name = 'LeafTabBookmarkPermissionDeniedError';
  }
}

interface LeafTabBookmarkMappingState {
  version: 1;
  nodeIdToEntityId: Record<string, string>;
  savedAt: string;
}

interface LeafTabBookmarkDraftCacheEntry {
  draft?: LeafTabBookmarkTreeDraft;
  savedAt: number;
  cacheKey: string;
  pending?: Promise<LeafTabBookmarkTreeDraft>;
}

type BookmarkApi = typeof chrome.bookmarks;
type BookmarkTreeNode = chrome.bookmarks.BookmarkTreeNode;
type BookmarkCreateArg = chrome.bookmarks.CreateDetails;
type BookmarkUpdateArg = chrome.bookmarks.UpdateChanges;
type BookmarkMoveArg = chrome.bookmarks.MoveDestination;
type LeafTabBookmarkRootRole = 'toolbar' | 'other' | 'mobile';

const ROOT_FOLDER_ID_MAP: Record<string, LeafTabBookmarkRootRole | 'unknown'> = {
  '1': 'toolbar',
  '2': 'other',
  '3': 'mobile',
  toolbar_____: 'toolbar',
  menu________: 'other',
  mobile______: 'mobile',
  unfiled_____: 'unknown',
};

const ROOT_FOLDER_TITLE_PATTERNS: Array<{
  pattern: RegExp;
  role: LeafTabBookmarkRootRole | 'unknown';
}> = [
  { pattern: /toolbar|bookmarks bar|bookmarks toolbar|favorites bar|书签栏|收藏夹栏|lesezeichen-symbolleiste/i, role: 'toolbar' },
  { pattern: /bookmarks menu|menu|other|其他书签|其他收藏夹|weitere|sonstige/i, role: 'other' },
  { pattern: /mobile|mobil/i, role: 'mobile' },
];

const ROOT_ORDER_KEY = '__root__';
const BOOKMARK_DRAFT_CACHE_TTL_MS = 5 * 60 * 1000;
let bookmarkDraftCache: LeafTabBookmarkDraftCacheEntry | null = null;
let bookmarkDraftCacheListenersBound = false;
let bookmarkDraftCacheApi: BookmarkApi | null = null;
let bookmarkDraftCaptureTail: Promise<void> = Promise.resolve();
const SYNC_ROOT_ROLES: LeafTabBookmarkRootRole[] = ['toolbar', 'other'];

const getOrderKey = (parentId: string | null) => parentId || ROOT_ORDER_KEY;
const getRoleEntityId = (role: LeafTabBookmarkRootRole) => `browser_root_${role}`;

const createEmptyBookmarkTreeDraft = (): LeafTabBookmarkTreeDraft => ({
  folders: [],
  items: [],
  orderIdsByParent: {
    [ROOT_ORDER_KEY]: [],
  },
  nodeIdToEntityId: {},
});

const cloneBookmarkTreeDraft = (draft: LeafTabBookmarkTreeDraft): LeafTabBookmarkTreeDraft => ({
  folders: draft.folders.map((folder) => ({ ...folder })),
  items: draft.items.map((item) => ({ ...item })),
  orderIdsByParent: Object.fromEntries(
    Object.entries(draft.orderIdsByParent).map(([key, ids]) => [key, ids.slice()]),
  ),
  nodeIdToEntityId: { ...draft.nodeIdToEntityId },
});

const getScopeRoleLabel = (role: LeafTabBookmarkRootRole) => {
  if (role === 'toolbar') return '书签栏';
  if (role === 'mobile') return '移动书签';
  return '其他书签';
};

const hasBookmarkRuntimeError = () => {
  return Boolean(globalThis.chrome?.runtime?.lastError);
};

const callBookmarksApi = <T>(
  executor: (api: BookmarkApi, resolve: (value: T) => void, reject: (error: Error) => void) => void,
): Promise<T> => {
  const api = getBookmarksApi();
  if (!api) {
    return Promise.reject(new Error('当前环境不支持书签 API'));
  }

  return new Promise<T>((resolve, reject) => {
    executor(
      api,
      (value) => {
        if (hasBookmarkRuntimeError()) {
          reject(new Error(globalThis.chrome?.runtime?.lastError?.message || '书签 API 调用失败'));
          return;
        }
        resolve(value);
      },
      reject,
    );
  });
};

const getBookmarkTree = () => {
  return callBookmarksApi<BookmarkTreeNode[]>((api, resolve) => {
    api.getTree((nodes) => resolve(nodes || []));
  });
};

const createBookmarkNode = (details: BookmarkCreateArg) => {
  return callBookmarksApi<BookmarkTreeNode>((api, resolve) => {
    api.create(details, (node) => resolve(node));
  });
};

const updateBookmarkNode = (id: string, changes: BookmarkUpdateArg) => {
  return callBookmarksApi<BookmarkTreeNode>((api, resolve) => {
    api.update(id, changes, (node) => resolve(node));
  });
};

const moveBookmarkNode = (id: string, destination: BookmarkMoveArg) => {
  return callBookmarksApi<BookmarkTreeNode>((api, resolve) => {
    api.move(id, destination, (node) => resolve(node));
  });
};

const removeBookmarkTree = (id: string) => {
  return callBookmarksApi<void>((api, resolve) => {
    api.removeTree(id, () => resolve());
  });
};

const removeBookmarkNode = (id: string) => {
  return callBookmarksApi<void>((api, resolve) => {
    api.remove(id, () => resolve());
  });
};

const detectRootFolderRole = (
  node: BookmarkTreeNode,
): LeafTabBookmarkRootRole | 'unknown' => {
  if (node.id && ROOT_FOLDER_ID_MAP[node.id]) {
    const mapped = ROOT_FOLDER_ID_MAP[node.id];
    return mapped === 'unknown' ? 'unknown' : mapped;
  }

  const title = node.title || '';
  for (const entry of ROOT_FOLDER_TITLE_PATTERNS) {
    if (entry.pattern.test(title)) return entry.role;
  }

  return 'unknown';
};

const invalidateLeafTabBookmarkDraftCache = () => {
  bookmarkDraftCache = null;
};

const ensureLeafTabBookmarkDraftCacheListeners = () => {
  const api = getBookmarksApi();
  if (!api) return;
  if (bookmarkDraftCacheApi !== api) {
    bookmarkDraftCache = null;
    bookmarkDraftCacheListenersBound = false;
    bookmarkDraftCacheApi = api;
  }
  if (bookmarkDraftCacheListenersBound) return;

  const invalidate = () => invalidateLeafTabBookmarkDraftCache();
  api.onCreated?.addListener?.(invalidate);
  api.onRemoved?.addListener?.(invalidate);
  api.onChanged?.addListener?.(invalidate);
  api.onMoved?.addListener?.(invalidate);
  api.onChildrenReordered?.addListener?.(invalidate);
  api.onImportEnded?.addListener?.(invalidate);
  bookmarkDraftCacheListenersBound = true;
};

const createBookmarkDraftCacheKey = (options?: {
  previousSnapshot?: LeafTabSyncSnapshot | null;
  deviceId?: string;
}) => {
  const previousSnapshot = options?.previousSnapshot;
  const baselineKey = previousSnapshot == null
    ? 'no-baseline'
    : `baseline:${JSON.stringify({
        generatedAt: previousSnapshot.meta?.generatedAt || '',
        folders: Object.values(previousSnapshot.bookmarkFolders || {})
          .map((folder) => ({ id: folder.id, parentId: folder.parentId, title: folder.title }))
          .sort((left, right) => left.id.localeCompare(right.id)),
        items: Object.values(previousSnapshot.bookmarkItems || {})
          .map((item) => ({
            id: item.id,
            parentId: item.parentId,
            title: item.title,
            url: item.url,
          }))
          .sort((left, right) => left.id.localeCompare(right.id)),
      })}`;
  return `${options?.deviceId || 'unknown-device'}|${baselineKey}`;
};

const readCachedLeafTabBookmarkTreeDraft = (cacheKey: string) => {
  const entry = bookmarkDraftCache;
  if (!entry?.draft) return null;
  if (entry.cacheKey !== cacheKey) return null;
  if (Date.now() - entry.savedAt > BOOKMARK_DRAFT_CACHE_TTL_MS) {
    bookmarkDraftCache = null;
    return null;
  }
  return cloneBookmarkTreeDraft(entry.draft);
};

const writeCachedLeafTabBookmarkTreeDraft = (
  draft: LeafTabBookmarkTreeDraft,
  cacheKey: string,
) => {
  bookmarkDraftCache = {
    draft: cloneBookmarkTreeDraft(draft),
    savedAt: Date.now(),
    cacheKey,
  };
};

const readBookmarkMappingFromLocalStorage = (): LeafTabBookmarkMappingState => {
  try {
    const raw = globalThis.localStorage?.getItem(LEAFTAB_BOOKMARK_MAPPING_KEY);
    if (!raw) {
      return {
        version: 1,
        nodeIdToEntityId: {},
        savedAt: new Date(0).toISOString(),
      };
    }
    const parsed = JSON.parse(raw) as Partial<LeafTabBookmarkMappingState>;
    return {
      version: 1,
      nodeIdToEntityId:
        parsed?.nodeIdToEntityId && typeof parsed.nodeIdToEntityId === 'object'
          ? Object.fromEntries(
              Object.entries(parsed.nodeIdToEntityId).filter(
                ([nodeId, entityId]) => typeof nodeId === 'string' && typeof entityId === 'string',
              ),
            )
          : {},
      savedAt: typeof parsed?.savedAt === 'string' ? parsed.savedAt : new Date(0).toISOString(),
    };
  } catch {
    return {
      version: 1,
      nodeIdToEntityId: {},
      savedAt: new Date(0).toISOString(),
    };
  }
};

const readBookmarkMapping = async (): Promise<LeafTabBookmarkMappingState> => {
  const storageKey = LEAFTAB_BOOKMARK_MAPPING_KEY;
  if (!getExtensionStorageArea()) {
    return readBookmarkMappingFromLocalStorage();
  }
  const result = await readExtensionStorageRecord([storageKey]);
  const raw = typeof result[storageKey] === 'string' ? result[storageKey] : '';
  if (!raw) {
    return {
      version: 1,
      nodeIdToEntityId: {},
      savedAt: new Date(0).toISOString(),
    };
  }
  const parsed = JSON.parse(raw) as Partial<LeafTabBookmarkMappingState>;
  return {
    version: 1,
    nodeIdToEntityId:
      parsed?.nodeIdToEntityId && typeof parsed.nodeIdToEntityId === 'object'
        ? Object.fromEntries(
            Object.entries(parsed.nodeIdToEntityId).filter(
              ([nodeId, entityId]) => typeof nodeId === 'string' && typeof entityId === 'string',
            ),
          )
        : {},
    savedAt: typeof parsed?.savedAt === 'string' ? parsed.savedAt : new Date(0).toISOString(),
  };
};

const writeBookmarkMapping = async (
  nodeIdToEntityId: Record<string, string>,
) => {
  const storageKey = LEAFTAB_BOOKMARK_MAPPING_KEY;
  const nextValue = JSON.stringify({
    version: 1,
    nodeIdToEntityId,
    savedAt: new Date().toISOString(),
  } satisfies LeafTabBookmarkMappingState);
  if (!getExtensionStorageArea()) {
    globalThis.localStorage?.setItem(storageKey, nextValue);
    return;
  }
  await writeExtensionStorageRecord({
    [storageKey]: nextValue,
  });
  try {
    globalThis.localStorage?.removeItem(storageKey);
  } catch {}
};

const createStableLocalEntityId = (
  type: 'folder' | 'item',
  deviceId: string,
  localNodeId: string,
) => {
  // Browser node IDs survive moves but are only unique within one installation.
  return `${type === 'folder' ? 'bkf' : 'bkm'}_local_` +
    `${encodeURIComponent(deviceId)}_${encodeURIComponent(localNodeId)}`;
};

const shortHash = (value: string) => {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(36);
};

const slugify = (value: string) => {
  return (value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 32) || 'bookmark';
};

const createLegacyEntityId = (
  type: 'folder' | 'item',
  parentId: string | null,
  title: string,
  url: string,
  occurrence: number,
) => {
  const parentKey = parentId || ROOT_ORDER_KEY;
  const key = type === 'folder'
    ? `${parentKey}|${title}|${occurrence}`
    : `${parentKey}|${title}|${url}|${occurrence}`;
  const label = type === 'folder' ? title || 'folder' : title || url || 'item';
  return `${type === 'folder' ? 'bkf' : 'bkm'}_${slugify(label)}_${shortHash(key)}`;
};

const resolveLegacyEntityId = (params: {
  type: 'folder' | 'item';
  parentId: string | null;
  title: string;
  url?: string;
  occurrence: number;
  previousSnapshot?: LeafTabSyncSnapshot | null;
  usedEntityIds: Set<string>;
}) => {
  // Compatibility-only probe for snapshots produced by the pre-0.2.14 fallback.
  // New nodes still use the installation-scoped stable ID below.
  const entityId = createLegacyEntityId(
    params.type,
    params.parentId,
    params.title,
    params.url || '',
    params.occurrence,
  );
  if (params.usedEntityIds.has(entityId)) return undefined;
  const entity = params.type === 'folder'
    ? params.previousSnapshot?.bookmarkFolders?.[entityId]
    : params.previousSnapshot?.bookmarkItems?.[entityId];
  if (!entity || entity.title !== params.title || entity.parentId !== params.parentId) {
    return undefined;
  }
  if (params.type === 'item' && (!('url' in entity) || entity.url !== (params.url || ''))) {
    return undefined;
  }
  return entityId;
};

const resolveUnusedPreviousEntityId = (params: {
  type: 'folder' | 'item';
  parentId: string | null;
  title: string;
  url?: string;
  previousSnapshot?: LeafTabSyncSnapshot | null;
  usedEntityIds: Set<string>;
}) => {
  const candidates = params.type === 'folder'
    ? Object.values(params.previousSnapshot?.bookmarkFolders || {})
      .filter((folder) => (
        folder.parentId === params.parentId
        && folder.title === params.title
        && !params.usedEntityIds.has(folder.id)
      ))
    : Object.values(params.previousSnapshot?.bookmarkItems || {})
      .filter((item) => (
        item.parentId === params.parentId
        && item.title === params.title
        && item.url === (params.url || '')
        && !params.usedEntityIds.has(item.id)
      ));
  return candidates.length === 1 ? candidates[0].id : undefined;
};

const resolveUniquePreviousEntityId = (params: {
  type: 'folder' | 'item';
  title: string;
  url?: string;
  previousSnapshot?: LeafTabSyncSnapshot | null;
  usedEntityIds: Set<string>;
}) => {
  const candidates = params.type === 'folder'
    ? Object.values(params.previousSnapshot?.bookmarkFolders || {})
      .filter((folder) => folder.title === params.title)
      .map((folder) => folder.id)
    : Object.values(params.previousSnapshot?.bookmarkItems || {})
      .filter((item) => item.title === params.title && item.url === (params.url || ''))
      .map((item) => item.id);
  if (candidates.length !== 1 || params.usedEntityIds.has(candidates[0])) {
    return undefined;
  }
  return candidates[0];
};

const resolveMappedEntityId = (params: {
  type: 'folder' | 'item';
  mapping: LeafTabBookmarkMappingState;
  localNodeId: string;
  usedEntityIds: Set<string>;
  previousSnapshot?: LeafTabSyncSnapshot | null;
}) => {
  const mappedEntityId = params.mapping.nodeIdToEntityId[params.localNodeId];
  const isStableLocalId = params.type === 'folder'
    ? mappedEntityId?.startsWith('bkf_local_')
    : mappedEntityId?.startsWith('bkm_local_');
  const existsInBaseline = params.type === 'folder'
    ? Boolean(params.previousSnapshot?.bookmarkFolders?.[mappedEntityId || ''])
    : Boolean(params.previousSnapshot?.bookmarkItems?.[mappedEntityId || '']);
  // A local fallback ID produced before the remote baseline was available is
  // provisional until it is present in that baseline. Let migration recover
  // the pre-0.2.14 ID instead of allowing the provisional ID to duplicate it.
  if (isStableLocalId && params.previousSnapshot && !existsInBaseline) return undefined;
  return mappedEntityId && !params.usedEntityIds.has(mappedEntityId)
    ? mappedEntityId
    : undefined;
};

const resolveSyncRoleRoots = async () => {
  const tree = await getBookmarkTree();
  const topLevelFolders = tree[0]?.children || [];
  const roleRoots = new Map<LeafTabBookmarkRootRole, BookmarkTreeNode>();
  const unmatchedRoots: BookmarkTreeNode[] = [];

  for (const node of topLevelFolders) {
    const role = detectRootFolderRole(node);
    if (role === 'toolbar' || role === 'other' || role === 'mobile') {
      if (!roleRoots.has(role)) {
        roleRoots.set(role, node);
      }
      continue;
    }
    unmatchedRoots.push(node);
  }

  for (const role of SYNC_ROOT_ROLES) {
    if (roleRoots.has(role)) continue;
    const fallbackRoot = unmatchedRoots.shift();
    if (!fallbackRoot) break;
    roleRoots.set(role, fallbackRoot);
  }

  return roleRoots;
};

const walkBookmarkChildren = (
  parentNode: BookmarkTreeNode,
  parentEntityId: string | null,
  mapping: LeafTabBookmarkMappingState,
  draft: LeafTabBookmarkTreeDraft,
  previousSnapshot: LeafTabSyncSnapshot | null | undefined,
  usedEntityIds: Set<string>,
  deviceId: string,
) => {
  const folderCounts = new Map<string, number>();
  const itemCounts = new Map<string, number>();
  const orderedIds: string[] = [];

  for (const child of parentNode.children || []) {
    if (child.url) {
      const key = `${child.title || ''}|${child.url || ''}`;
      const occurrence = (itemCounts.get(key) || 0) + 1;
      itemCounts.set(key, occurrence);
      const mappedEntityId = resolveMappedEntityId({
        type: 'item',
        mapping,
        localNodeId: child.id,
        usedEntityIds,
        previousSnapshot,
      });
      const entityId = mappedEntityId
        || resolveLegacyEntityId({
          type: 'item',
          parentId: parentEntityId,
          title: child.title || '',
          url: child.url || '',
          occurrence,
          previousSnapshot,
          usedEntityIds,
        })
        || resolveUnusedPreviousEntityId({
          type: 'item',
          parentId: parentEntityId,
          title: child.title || '',
          url: child.url || '',
          previousSnapshot,
          usedEntityIds,
        })
        || resolveUniquePreviousEntityId({
          type: 'item',
          title: child.title || '',
          url: child.url || '',
          previousSnapshot,
          usedEntityIds,
        })
        || createStableLocalEntityId('item', deviceId, child.id);
      usedEntityIds.add(entityId);
      draft.items.push({
        entityId,
        localNodeId: child.id,
        parentId: parentEntityId,
        title: child.title || '',
        url: child.url || '',
      });
      draft.nodeIdToEntityId[child.id] = entityId;
      orderedIds.push(entityId);
      continue;
    }

    const key = child.title || '';
    const occurrence = (folderCounts.get(key) || 0) + 1;
    folderCounts.set(key, occurrence);
    const mappedEntityId = resolveMappedEntityId({
      type: 'folder',
      mapping,
      localNodeId: child.id,
      usedEntityIds,
      previousSnapshot,
    });
    const entityId = mappedEntityId
      || resolveLegacyEntityId({
        type: 'folder',
        parentId: parentEntityId,
        title: child.title || '',
        occurrence,
        previousSnapshot,
        usedEntityIds,
      })
      || resolveUnusedPreviousEntityId({
        type: 'folder',
        parentId: parentEntityId,
        title: child.title || '',
        previousSnapshot,
        usedEntityIds,
      })
      || resolveUniquePreviousEntityId({
        type: 'folder',
        title: child.title || '',
        previousSnapshot,
        usedEntityIds,
      })
      || createStableLocalEntityId('folder', deviceId, child.id);
    usedEntityIds.add(entityId);

    draft.folders.push({
      entityId,
      localNodeId: child.id,
      parentId: parentEntityId,
      title: child.title || '',
    });
    draft.nodeIdToEntityId[child.id] = entityId;
    orderedIds.push(entityId);
    walkBookmarkChildren(child, entityId, mapping, draft, previousSnapshot, usedEntityIds, deviceId);
  }

  draft.orderIdsByParent[getOrderKey(parentEntityId)] = orderedIds;
};

export const captureLeafTabBookmarkTreeDraft = async (options?: {
  requestPermission?: boolean;
  throwOnPermissionDenied?: boolean;
  previousSnapshot?: LeafTabSyncSnapshot | null;
  deviceId: string;
}): Promise<LeafTabBookmarkTreeDraft> => {
  ensureLeafTabBookmarkDraftCacheListeners();
  const cacheKey = createBookmarkDraftCacheKey(options);
  const granted = await ensureExtensionPermission('bookmarks', {
    requestIfNeeded: options?.requestPermission === true,
  });

  if (!granted) {
    if (options?.throwOnPermissionDenied) {
      throw new LeafTabBookmarkPermissionDeniedError();
    }
    return createEmptyBookmarkTreeDraft();
  }

  const previousCapture = bookmarkDraftCaptureTail;
  let releaseCapture: (() => void) | undefined;
  bookmarkDraftCaptureTail = new Promise<void>((resolve) => {
    releaseCapture = resolve;
  });

  await previousCapture;
  try {
    const cached = readCachedLeafTabBookmarkTreeDraft(cacheKey);
    if (cached) {
      return cached;
    }

    const pending = bookmarkDraftCache?.cacheKey === cacheKey
      ? bookmarkDraftCache.pending
      : undefined;
    if (pending) {
      return cloneBookmarkTreeDraft(await pending);
    }

    const nextPending = (async () => {
      const roleRoots = await resolveSyncRoleRoots();

      const draft: LeafTabBookmarkTreeDraft = {
        folders: [],
        items: [],
        orderIdsByParent: {},
        nodeIdToEntityId: {},
      };
      const mapping = await readBookmarkMapping();
      // Mapping entries for nodes no longer in the browser tree are historical data,
      // not reservations. Only IDs assigned during this capture may block a match.
      const usedEntityIds = new Set<string>();
      const rootIds: string[] = [];

      for (const role of SYNC_ROOT_ROLES) {
        const roleRoot = roleRoots.get(role);
        if (!roleRoot) continue;
        const entityId = getRoleEntityId(role);
        draft.folders.push({
          entityId,
          localNodeId: roleRoot.id,
          parentId: null,
          title: getScopeRoleLabel(role),
        });
        draft.nodeIdToEntityId[roleRoot.id] = entityId;
        rootIds.push(entityId);
        usedEntityIds.add(entityId);
        walkBookmarkChildren(
          roleRoot,
          entityId,
          mapping,
          draft,
          options?.previousSnapshot,
          usedEntityIds,
          options?.deviceId || 'unknown-device',
        );
      }

      draft.orderIdsByParent[ROOT_ORDER_KEY] = rootIds;
      await writeBookmarkMapping(draft.nodeIdToEntityId);
      writeCachedLeafTabBookmarkTreeDraft(draft, cacheKey);
      return draft;
    })();

    bookmarkDraftCache = {
      ...bookmarkDraftCache,
      savedAt: 0,
      cacheKey,
      pending: nextPending,
    };

    try {
      return cloneBookmarkTreeDraft(await nextPending);
    } finally {
      const current = bookmarkDraftCache;
      if (current?.pending === nextPending) {
        if (current.draft) {
          bookmarkDraftCache = {
            draft: current.draft,
            savedAt: current.savedAt,
            cacheKey: current.cacheKey,
          };
        } else {
          bookmarkDraftCache = null;
        }
      }
    }
  } finally {
    releaseCapture?.();
  }
};

type LeafTabApplyBookmarkNode = {
  id: string;
  parentId: string | null;
  title: string;
  url?: string;
  type: 'folder' | 'bookmark';
};

const ROOT_ENTITY_IDS = new Set(SYNC_ROOT_ROLES.map((role) => getRoleEntityId(role)));

const buildEntityNodeLookup = (draft: LeafTabBookmarkTreeDraft) => {
  const lookup = new Map<string, LeafTabApplyBookmarkNode>();
  draft.folders.forEach((folder) => {
    lookup.set(folder.entityId, {
      id: folder.localNodeId,
      parentId: folder.parentId,
      title: folder.title,
      type: 'folder',
    });
  });
  draft.items.forEach((item) => {
    lookup.set(item.entityId, {
      id: item.localNodeId,
      parentId: item.parentId,
      title: item.title,
      url: item.url,
      type: 'bookmark',
    });
  });
  return lookup;
};

const appendMissingOrderedIds = (
  ids: string[],
  childIds: string[],
) => {
  const nextIds = ids.slice();
  const seen = new Set(nextIds);
  const append = (id: string) => {
    if (seen.has(id)) return;
    seen.add(id);
    nextIds.push(id);
  };

  childIds.forEach(append);
  return nextIds;
};

const buildChildIdsByParent = (
  folderLookup: Record<string, { title: string; parentId: string | null }>,
  itemLookup: Record<string, { title: string; parentId: string | null; url: string }>,
) => {
  const childIdsByParent = new Map<string, string[]>();
  const add = (parentId: string | null, id: string) => {
    const key = parentId || ROOT_ORDER_KEY;
    const current = childIdsByParent.get(key);
    if (current) {
      current.push(id);
      return;
    }
    childIdsByParent.set(key, [id]);
  };

  Object.entries(folderLookup).forEach(([id, folder]) => add(folder.parentId, id));
  Object.entries(itemLookup).forEach(([id, item]) => add(item.parentId, id));
  return childIdsByParent;
};

const resolveDesiredChildren = (
  parentEntityId: string,
  orderIdsByParent: Record<string, string[]>,
  childIdsByParent: Map<string, string[]>,
) => {
  return appendMissingOrderedIds(
    orderIdsByParent[parentEntityId] || [],
    childIdsByParent.get(parentEntityId) || [],
  );
};

const ensureBookmarkNode = async (params: {
  entityId: string;
  parentNodeId: string;
  index: number;
  currentNode: LeafTabApplyBookmarkNode | undefined;
  desiredNode: LeafTabApplyBookmarkNode;
}) => {
  const { currentNode, desiredNode, parentNodeId, index } = params;
  if (!currentNode) {
    const created = await createBookmarkNode({
      parentId: parentNodeId,
      index,
      title: desiredNode.title,
      ...(desiredNode.type === 'bookmark' ? { url: desiredNode.url || '' } : {}),
    });
    return {
      ...desiredNode,
      id: created.id,
    };
  }

  let nextNode = currentNode;
  if (currentNode.parentId !== desiredNode.parentId) {
    const moved = await moveBookmarkNode(currentNode.id, {
      parentId: parentNodeId,
      index,
    });
    nextNode = {
      ...nextNode,
      id: moved.id,
      parentId: desiredNode.parentId,
    };
  } else {
    await moveBookmarkNode(currentNode.id, {
      parentId: parentNodeId,
      index,
    });
  }

  if (desiredNode.type === 'folder') {
    if (nextNode.title !== desiredNode.title) {
      const updated = await updateBookmarkNode(nextNode.id, { title: desiredNode.title });
      nextNode = {
        ...nextNode,
        title: updated.title || desiredNode.title,
      };
    }
    return nextNode;
  }

  if (nextNode.title !== desiredNode.title || (nextNode.url || '') !== (desiredNode.url || '')) {
    const updated = await updateBookmarkNode(nextNode.id, {
      title: desiredNode.title,
      url: desiredNode.url || '',
    });
    nextNode = {
      ...nextNode,
      title: updated.title || desiredNode.title,
      url: updated.url || desiredNode.url || '',
    };
  }
  return nextNode;
};

const deleteBookmarkNode = async (node: LeafTabApplyBookmarkNode) => {
  if (node.type === 'folder') {
    await removeBookmarkTree(node.id);
    return;
  }
  await removeBookmarkNode(node.id);
};

const shouldDeleteStaleSyncedNode = (
  entityId: string,
  folderLookup: Record<string, { title: string; parentId: string | null }>,
  itemLookup: Record<string, { title: string; parentId: string | null; url: string }>,
) => {
  if (ROOT_ENTITY_IDS.has(entityId)) return false;
  if (folderLookup[entityId] || itemLookup[entityId]) return false;
  return true;
};

const resolveFolderDepth = (
  folder: LeafTabBookmarkFolderDraft,
  foldersByEntityId: Map<string, LeafTabBookmarkFolderDraft>,
): number => {
  let depth = 0;
  let parentId = folder.parentId;
  const visited = new Set<string>();
  while (parentId && !ROOT_ENTITY_IDS.has(parentId) && !visited.has(parentId)) {
    visited.add(parentId);
    const parent = foldersByEntityId.get(parentId);
    if (!parent) break;
    depth += 1;
    parentId = parent.parentId;
  }
  return depth;
};

export const replaceLeafTabBookmarkTree = async (params: {
  folderLookup: Record<string, { title: string; parentId: string | null }>;
  itemLookup: Record<string, { title: string; parentId: string | null; url: string }>;
  orderIdsByParent: Record<string, string[]>;
  tombstoneIds?: string[];
  requestPermission?: boolean;
  deviceId: string;
}) => {
  invalidateLeafTabBookmarkDraftCache();
  const granted = await ensureExtensionPermission('bookmarks', {
    requestIfNeeded: params.requestPermission !== false,
  });
  if (!granted) {
    if (params.requestPermission === false) return false;
    throw new Error('书签权限未授予，无法写入本地书签');
  }

  const roleRoots = await resolveSyncRoleRoots();
  const currentDraft = await captureLeafTabBookmarkTreeDraft({
    requestPermission: false,
    throwOnPermissionDenied: true,
    deviceId: params.deviceId,
  });
  const entityNodeLookup = buildEntityNodeLookup(currentDraft);
  const nodeIdToEntityId: Record<string, string> = { ...currentDraft.nodeIdToEntityId };
  const childIdsByParent = buildChildIdsByParent(params.folderLookup, params.itemLookup);

  const applyChildren = async (parentEntityId: string, parentNodeId: string) => {
    const childIds = resolveDesiredChildren(
      parentEntityId,
      params.orderIdsByParent,
      childIdsByParent,
    );

    for (let index = 0; index < childIds.length; index += 1) {
      const entityId = childIds[index];
      const folder = params.folderLookup[entityId];
      const item = params.itemLookup[entityId];
      const currentNode = entityNodeLookup.get(entityId);
      const desiredNode: LeafTabApplyBookmarkNode | null = folder
        ? {
            id: currentNode?.id || entityId,
            parentId: parentEntityId,
            title: folder.title,
            type: 'folder',
          }
        : item
          ? {
              id: currentNode?.id || entityId,
              parentId: parentEntityId,
              title: item.title,
              url: item.url,
              type: 'bookmark',
            }
          : null;
      if (!desiredNode) continue;

      const appliedNode = await ensureBookmarkNode({
        entityId,
        parentNodeId,
        index,
        currentNode,
        desiredNode,
      });
      entityNodeLookup.set(entityId, appliedNode);
      nodeIdToEntityId[appliedNode.id] = entityId;
      if (folder) {
        await applyChildren(entityId, appliedNode.id);
      }
    }
  };

  for (const role of SYNC_ROOT_ROLES) {
    const scopeRoot = roleRoots.get(role);
    if (!scopeRoot) continue;
    const roleEntityId = getRoleEntityId(role);
    nodeIdToEntityId[scopeRoot.id] = roleEntityId;
    await applyChildren(roleEntityId, scopeRoot.id);
  }

  const foldersByEntityId = new Map<string, LeafTabBookmarkFolderDraft>(
    currentDraft.folders.map((folder) => [folder.entityId, folder]),
  );
  const staleSyncedNodes = [
    ...currentDraft.items.map((item) => ({
      entityId: item.entityId,
      localNodeId: item.localNodeId,
      type: 'bookmark' as const,
    })),
    ...currentDraft.folders
      .filter((folder) => !ROOT_ENTITY_IDS.has(folder.entityId))
      .map((folder) => ({
        folder,
        depth: resolveFolderDepth(folder, foldersByEntityId),
      }))
      .sort((left, right) => {
        return right.depth - left.depth
          || left.folder.entityId.localeCompare(right.folder.entityId);
      })
      .map(({ folder }) => folder)
      .map((folder) => ({
        entityId: folder.entityId,
        localNodeId: folder.localNodeId,
        type: 'folder' as const,
      })),
  ];

  for (const node of staleSyncedNodes) {
    if (!shouldDeleteStaleSyncedNode(node.entityId, params.folderLookup, params.itemLookup)) continue;
    const existing = entityNodeLookup.get(node.entityId);
    if (!existing) continue;
    await deleteBookmarkNode(existing);
    delete nodeIdToEntityId[existing.id];
  }

  await writeBookmarkMapping(nodeIdToEntityId);
  invalidateLeafTabBookmarkDraftCache();
  return true;
};
