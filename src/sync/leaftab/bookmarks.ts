import { getBookmarksApi } from '@/platform/runtime';
import { readExtensionStorageRecord, writeExtensionStorageRecord } from '@/platform/extensionStorage';
import { ensureExtensionPermission } from '@/utils/extensionPermissions';
import {
  formatLeafTabBookmarkSyncScopeLabel as formatBookmarkSyncScopeLabel,
  getDefaultLeafTabBookmarkSyncScope as getDefaultBookmarkSyncScope,
  getLeafTabBookmarkScopeStorageKey,
  normalizeLeafTabBookmarkSyncScope,
  type LeafTabBookmarkSyncScope,
  type LeafTabBookmarkSyncScopeRole,
} from './bookmarkScope';

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
  pending?: Promise<LeafTabBookmarkTreeDraft>;
}

type BookmarkApi = typeof chrome.bookmarks;
type BookmarkTreeNode = chrome.bookmarks.BookmarkTreeNode;
type BookmarkCreateArg = chrome.bookmarks.CreateDetails;
type BookmarkUpdateArg = chrome.bookmarks.UpdateChanges;
type BookmarkMoveArg = chrome.bookmarks.MoveDestination;

const ROOT_FOLDER_ID_MAP: Record<string, LeafTabBookmarkSyncScopeRole | 'unknown'> = {
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
  role: LeafTabBookmarkSyncScopeRole | 'unknown';
}> = [
  { pattern: /toolbar|bookmarks bar|bookmarks toolbar|favorites bar|书签栏|收藏夹栏|lesezeichen-symbolleiste/i, role: 'toolbar' },
  { pattern: /bookmarks menu|menu|other|其他书签|其他收藏夹|weitere|sonstige/i, role: 'other' },
  { pattern: /mobile|mobil/i, role: 'mobile' },
];

const ROOT_ORDER_KEY = '__root__';
const MAPPING_KEY_PREFIX = 'leaftab_sync_g2_bookmark_mapping:';
const BOOKMARK_DRAFT_CACHE_TTL_MS = 5 * 60 * 1000;
const bookmarkDraftCache = new Map<string, LeafTabBookmarkDraftCacheEntry>();
let bookmarkDraftCacheListenersBound = false;
const SYNC_ROOT_ROLES: LeafTabBookmarkSyncScopeRole[] = ['toolbar', 'other'];

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

const getOrderKey = (parentId: string | null) => parentId || ROOT_ORDER_KEY;
const getRoleEntityId = (role: LeafTabBookmarkSyncScopeRole) => `browser_root_${role}`;

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

const getScopeRoleLabel = (role: LeafTabBookmarkSyncScopeRole) => {
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
): LeafTabBookmarkSyncScopeRole | 'unknown' => {
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

const invalidateLeafTabBookmarkDraftCache = (scope?: LeafTabBookmarkSyncScope | null) => {
  if (!scope) {
    bookmarkDraftCache.clear();
    return;
  }
  bookmarkDraftCache.delete(getLeafTabBookmarkScopeStorageKey(scope));
};

const ensureLeafTabBookmarkDraftCacheListeners = () => {
  if (bookmarkDraftCacheListenersBound) return;
  const api = getBookmarksApi();
  if (!api) return;

  const invalidate = () => invalidateLeafTabBookmarkDraftCache();
  api.onCreated?.addListener?.(invalidate);
  api.onRemoved?.addListener?.(invalidate);
  api.onChanged?.addListener?.(invalidate);
  api.onMoved?.addListener?.(invalidate);
  api.onChildrenReordered?.addListener?.(invalidate);
  api.onImportEnded?.addListener?.(invalidate);
  bookmarkDraftCacheListenersBound = true;
};

const readCachedLeafTabBookmarkTreeDraft = (scope: LeafTabBookmarkSyncScope) => {
  const entry = bookmarkDraftCache.get(getLeafTabBookmarkScopeStorageKey(scope));
  if (!entry?.draft) return null;
  if (Date.now() - entry.savedAt > BOOKMARK_DRAFT_CACHE_TTL_MS) {
    bookmarkDraftCache.delete(getLeafTabBookmarkScopeStorageKey(scope));
    return null;
  }
  return cloneBookmarkTreeDraft(entry.draft);
};

const writeCachedLeafTabBookmarkTreeDraft = (
  scope: LeafTabBookmarkSyncScope,
  draft: LeafTabBookmarkTreeDraft,
) => {
  bookmarkDraftCache.set(getLeafTabBookmarkScopeStorageKey(scope), {
    draft: cloneBookmarkTreeDraft(draft),
    savedAt: Date.now(),
  });
};

const readBookmarkMappingFromLocalStorage = (scope: LeafTabBookmarkSyncScope): LeafTabBookmarkMappingState => {
  try {
    const raw = globalThis.localStorage?.getItem(`${MAPPING_KEY_PREFIX}${getLeafTabBookmarkScopeStorageKey(scope)}`);
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

const readBookmarkMapping = async (scope: LeafTabBookmarkSyncScope): Promise<LeafTabBookmarkMappingState> => {
  const storageKey = `${MAPPING_KEY_PREFIX}${getLeafTabBookmarkScopeStorageKey(scope)}`;
  try {
    const result = await readExtensionStorageRecord([storageKey]);
    const raw = typeof result[storageKey] === 'string' ? result[storageKey] : '';
    if (!raw) {
      const legacy = readBookmarkMappingFromLocalStorage(scope);
      if (Object.keys(legacy.nodeIdToEntityId).length > 0) {
        await writeExtensionStorageRecord({
          [storageKey]: JSON.stringify(legacy),
        });
      }
      return legacy;
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
    return readBookmarkMappingFromLocalStorage(scope);
  }
};

const writeBookmarkMapping = async (
  scope: LeafTabBookmarkSyncScope,
  nodeIdToEntityId: Record<string, string>,
) => {
  const storageKey = `${MAPPING_KEY_PREFIX}${getLeafTabBookmarkScopeStorageKey(scope)}`;
  const nextValue = JSON.stringify({
    version: 1,
    nodeIdToEntityId,
    savedAt: new Date().toISOString(),
  } satisfies LeafTabBookmarkMappingState);
  try {
    globalThis.localStorage?.setItem(storageKey, nextValue);
  } catch {}
  await writeExtensionStorageRecord({
    [storageKey]: nextValue,
  });
};

const createFolderEntityId = (parentId: string | null, title: string, occurrence: number) => {
  return `bkf_${slugify(title || 'folder')}_${shortHash(`${parentId || ROOT_ORDER_KEY}|${title}|${occurrence}`)}`;
};

const createItemEntityId = (
  parentId: string | null,
  title: string,
  url: string,
  occurrence: number,
) => {
  return `bkm_${slugify(title || url || 'item')}_${shortHash(`${parentId || ROOT_ORDER_KEY}|${title}|${url}|${occurrence}`)}`;
};

const resolveSyncRoleRoots = async () => {
  const tree = await getBookmarkTree();
  const topLevelFolders = tree[0]?.children || [];
  const roleRoots = new Map<LeafTabBookmarkSyncScopeRole, BookmarkTreeNode>();
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
) => {
  const folderCounts = new Map<string, number>();
  const itemCounts = new Map<string, number>();
  const orderedIds: string[] = [];

  for (const child of parentNode.children || []) {
    if (child.url) {
      const key = `${child.title || ''}|${child.url || ''}`;
      const occurrence = (itemCounts.get(key) || 0) + 1;
      itemCounts.set(key, occurrence);
      const entityId =
        mapping.nodeIdToEntityId[child.id] ||
        createItemEntityId(parentEntityId, child.title || '', child.url || '', occurrence);
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
    const entityId =
      mapping.nodeIdToEntityId[child.id] ||
      createFolderEntityId(parentEntityId, child.title || '', occurrence);

    draft.folders.push({
      entityId,
      localNodeId: child.id,
      parentId: parentEntityId,
      title: child.title || '',
    });
    draft.nodeIdToEntityId[child.id] = entityId;
    orderedIds.push(entityId);
    walkBookmarkChildren(child, entityId, mapping, draft);
  }

  draft.orderIdsByParent[getOrderKey(parentEntityId)] = orderedIds;
};

export const getDefaultLeafTabBookmarkSyncScope = (): LeafTabBookmarkSyncScope => {
  return getDefaultBookmarkSyncScope();
};

export const readLeafTabBookmarkSyncScope = (): LeafTabBookmarkSyncScope => {
  return getDefaultBookmarkSyncScope();
};

export const formatLeafTabBookmarkSyncScopeLabel = (
  scope: LeafTabBookmarkSyncScope | null | undefined,
) => {
  return formatBookmarkSyncScopeLabel(scope);
};

export const captureLeafTabBookmarkTreeDraft = async (options?: {
  scope?: LeafTabBookmarkSyncScope | null;
  requestPermission?: boolean;
  throwOnPermissionDenied?: boolean;
}): Promise<LeafTabBookmarkTreeDraft> => {
  const scope = normalizeLeafTabBookmarkSyncScope(options?.scope);
  ensureLeafTabBookmarkDraftCacheListeners();
  const granted = await ensureExtensionPermission('bookmarks', {
    requestIfNeeded: options?.requestPermission === true,
  });

  if (!granted) {
    if (options?.throwOnPermissionDenied) {
      throw new LeafTabBookmarkPermissionDeniedError();
    }
    return createEmptyBookmarkTreeDraft();
  }

  const cached = readCachedLeafTabBookmarkTreeDraft(scope);
  if (cached) {
    return cached;
  }

  const cacheKey = getLeafTabBookmarkScopeStorageKey(scope);
  const pending = bookmarkDraftCache.get(cacheKey)?.pending;
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
    const mapping = await readBookmarkMapping(scope);
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
      walkBookmarkChildren(roleRoot, entityId, mapping, draft);
    }

    draft.orderIdsByParent[ROOT_ORDER_KEY] = rootIds;
    await writeBookmarkMapping(scope, draft.nodeIdToEntityId);
    writeCachedLeafTabBookmarkTreeDraft(scope, draft);
    return draft;
  })();

  bookmarkDraftCache.set(cacheKey, {
    ...bookmarkDraftCache.get(cacheKey),
    savedAt: 0,
    pending: nextPending,
  });

  try {
    return cloneBookmarkTreeDraft(await nextPending);
  } finally {
    const current = bookmarkDraftCache.get(cacheKey);
    if (current?.pending === nextPending) {
      if (current.draft) {
        bookmarkDraftCache.set(cacheKey, {
          draft: current.draft,
          savedAt: current.savedAt,
        });
      } else {
        bookmarkDraftCache.delete(cacheKey);
      }
    }
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
    }).catch(() => currentNode as unknown as BookmarkTreeNode);
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

export const replaceLeafTabBookmarkTree = async (params: {
  scope?: LeafTabBookmarkSyncScope | null;
  folderLookup: Record<string, { title: string; parentId: string | null }>;
  itemLookup: Record<string, { title: string; parentId: string | null; url: string }>;
  orderIdsByParent: Record<string, string[]>;
  tombstoneIds?: string[];
  requestPermission?: boolean;
}) => {
  const scope = normalizeLeafTabBookmarkSyncScope(params.scope);
  invalidateLeafTabBookmarkDraftCache(scope);
  const granted = await ensureExtensionPermission('bookmarks', {
    requestIfNeeded: params.requestPermission !== false,
  });
  if (!granted) {
    if (params.requestPermission === false) return false;
    throw new Error('书签权限未授予，无法写入本地书签');
  }

  const roleRoots = await resolveSyncRoleRoots();
  const currentDraft = await captureLeafTabBookmarkTreeDraft({
    scope,
    requestPermission: false,
    throwOnPermissionDenied: true,
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

  const staleSyncedNodes = [
    ...currentDraft.items.map((item) => ({
      entityId: item.entityId,
      localNodeId: item.localNodeId,
      type: 'bookmark' as const,
    })),
    ...currentDraft.folders
      .filter((folder) => !ROOT_ENTITY_IDS.has(folder.entityId))
      .sort((left, right) => right.parentId?.localeCompare(left.parentId || '') || 0)
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
    await deleteBookmarkNode(existing).catch(() => {});
    delete nodeIdToEntityId[existing.id];
  }

  await writeBookmarkMapping(scope, nodeIdToEntityId);
  invalidateLeafTabBookmarkDraftCache(scope);
  return true;
};
