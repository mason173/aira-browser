import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import { getBookmarksApi } from '@/platform/runtime';
import {
  getDefaultLeafTabBookmarkSyncScope,
  getLeafTabBookmarkScopeStorageKey,
} from './bookmarkScope';
import type { LeafTabSyncSnapshot } from './schema';
import type { LeafTabSyncOperation } from './remoteStore';

type BookmarkTreeNode = chrome.bookmarks.BookmarkTreeNode;

export type LeafTabLocalBookmarkOperationEvent =
  | {
      kind: 'created';
      id: string;
      node: BookmarkTreeNode;
      at: number;
    }
  | {
      kind: 'removed';
      id: string;
      parentId?: string;
      node: BookmarkTreeNode;
      at: number;
    }
  | {
      kind: 'changed';
      id: string;
      at: number;
    }
  | {
      kind: 'moved';
      id: string;
      parentId?: string;
      oldParentId?: string;
      at: number;
    }
  | {
      kind: 'children_reordered';
      id: string;
      at: number;
    }
  | {
      kind: 'import_ended';
      at: number;
    };

type BookmarkMappingState = {
  version: 1;
  nodeIdToEntityId: Record<string, string>;
  savedAt: string;
};

const OUTBOX_STORAGE_KEY = 'leaftab_sync_v1_local_operation_outbox';
const MAPPING_KEY_PREFIX = 'leaftab_sync_bookmark_mapping_v1:';
const ROOT_ORDER_KEY = '__root__';
const MAX_STORED_OUTBOX_EVENTS = 500;
const MAX_DIRECT_OPERATION_EVENTS = 120;

const ROOT_FOLDER_ID_MAP: Record<string, 'toolbar' | 'other' | 'mobile' | 'unknown'> = {
  '1': 'toolbar',
  '2': 'other',
  '3': 'mobile',
  toolbar_____: 'toolbar',
  menu________: 'other',
  mobile______: 'mobile',
  unfiled_____: 'unknown',
};

const getRoleEntityId = (role: 'toolbar' | 'other') => `browser_root_${role}`;

const getMappingStorageKey = () => {
  return `${MAPPING_KEY_PREFIX}${getLeafTabBookmarkScopeStorageKey(getDefaultLeafTabBookmarkSyncScope())}`;
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

const createEntityId = (node: BookmarkTreeNode, parentEntityId: string | null) => {
  const kind = node.url ? 'bkm' : 'bkf';
  return `${kind}_${slugify(node.title || node.url || node.id)}_${shortHash(`${parentEntityId || ROOT_ORDER_KEY}|${node.id}|${node.title || ''}|${node.url || ''}`)}`;
};

const createOperationId = (kind: string, entityId: string, updatedAt: string, index: number) => {
  return `op_${shortHash(`${kind}:${entityId}:${updatedAt}:${index}`)}_${index}`;
};

const toIsoString = (value: number | undefined) => {
  return new Date(Number.isFinite(Number(value)) ? Number(value) : Date.now()).toISOString();
};

const readOutbox = async (): Promise<LeafTabLocalBookmarkOperationEvent[]> => {
  const result = await readExtensionStorageRecord([OUTBOX_STORAGE_KEY]);
  const raw = result[OUTBOX_STORAGE_KEY];
  if (typeof raw !== 'string' || raw.length <= 0) {
    return [];
  }
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((entry) => entry && typeof entry.kind === 'string') : [];
  } catch {
    return [];
  }
};

const writeOutbox = async (events: LeafTabLocalBookmarkOperationEvent[]) => {
  await writeExtensionStorageRecord({
    [OUTBOX_STORAGE_KEY]: JSON.stringify(events.slice(-MAX_STORED_OUTBOX_EVENTS)),
  });
};

const readMapping = async (): Promise<BookmarkMappingState> => {
  const key = getMappingStorageKey();
  const result = await readExtensionStorageRecord([key]);
  const raw = typeof result[key] === 'string' ? result[key] : '';
  if (!raw) {
    return {
      version: 1,
      nodeIdToEntityId: {},
      savedAt: new Date(0).toISOString(),
    };
  }
  try {
    const parsed = JSON.parse(raw) as Partial<BookmarkMappingState>;
    return {
      version: 1,
      nodeIdToEntityId:
        parsed.nodeIdToEntityId && typeof parsed.nodeIdToEntityId === 'object'
          ? Object.fromEntries(
              Object.entries(parsed.nodeIdToEntityId).filter(
                ([nodeId, entityId]) => typeof nodeId === 'string' && typeof entityId === 'string',
              ),
            )
          : {},
      savedAt: typeof parsed.savedAt === 'string' ? parsed.savedAt : new Date(0).toISOString(),
    };
  } catch {
    return {
      version: 1,
      nodeIdToEntityId: {},
      savedAt: new Date(0).toISOString(),
    };
  }
};

const writeMapping = async (mapping: BookmarkMappingState) => {
  const key = getMappingStorageKey();
  await writeExtensionStorageRecord({
    [key]: JSON.stringify({
      version: 1,
      nodeIdToEntityId: mapping.nodeIdToEntityId,
      savedAt: new Date().toISOString(),
    } satisfies BookmarkMappingState),
  });
};

const getBookmarkNode = async (id: string): Promise<BookmarkTreeNode | null> => {
  const api = getBookmarksApi();
  if (!api?.get) return null;
  return new Promise((resolve) => {
    api.get(id, (nodes) => {
      if (globalThis.chrome?.runtime?.lastError) {
        resolve(null);
        return;
      }
      resolve(nodes?.[0] || null);
    });
  });
};

const getBookmarkChildren = async (id: string): Promise<BookmarkTreeNode[] | null> => {
  const api = getBookmarksApi();
  if (!api?.getChildren) return null;
  return new Promise((resolve) => {
    api.getChildren(id, (nodes) => {
      if (globalThis.chrome?.runtime?.lastError) {
        resolve(null);
        return;
      }
      resolve(nodes || []);
    });
  });
};

const resolveRoleEntityId = (localNodeId: string): string | undefined => {
  const role = ROOT_FOLDER_ID_MAP[localNodeId];
  if (role === 'toolbar' || role === 'other') {
    return getRoleEntityId(role);
  }
  return undefined;
};

const resolveMappedEntityId = (localNodeId: string | undefined, mapping: BookmarkMappingState): string | undefined => {
  if (!localNodeId) return undefined;
  return mapping.nodeIdToEntityId[localNodeId] || resolveRoleEntityId(localNodeId);
};

const ensureMappedEntityId = (
  node: BookmarkTreeNode,
  parentEntityId: string | null,
  mapping: BookmarkMappingState,
) => {
  const mapped = resolveMappedEntityId(node.id, mapping);
  if (mapped) return mapped;
  const entityId = createEntityId(node, parentEntityId);
  mapping.nodeIdToEntityId[node.id] = entityId;
  return entityId;
};

const resolveParentEntityId = (localParentId: string | undefined, mapping: BookmarkMappingState): string | null | undefined => {
  if (!localParentId) return null;
  return resolveMappedEntityId(localParentId, mapping);
};

const buildUpsertOperation = (params: {
  node: BookmarkTreeNode;
  entityId: string;
  parentEntityId: string | null;
  baseSnapshot: LeafTabSyncSnapshot;
  deviceId: string;
  updatedAt: string;
  index: number;
}): LeafTabSyncOperation => {
  const previous = params.node.url
    ? params.baseSnapshot.bookmarkItems[params.entityId]
    : params.baseSnapshot.bookmarkFolders[params.entityId];
  const revision = previous ? previous.revision + 1 : 1;
  if (params.node.url) {
    return {
      id: createOperationId('item', params.entityId, params.updatedAt, params.index),
      kind: 'upsert_item',
      entityId: params.entityId,
      entityType: 'bookmark-item',
      parentId: params.parentEntityId,
      title: params.node.title || '',
      url: params.node.url || 'about:blank',
      createdAt: previous?.createdAt || toIsoString(params.node.dateAdded),
      updatedAt: params.updatedAt,
      updatedBy: params.deviceId,
      revision,
    };
  }
  return {
    id: createOperationId('folder', params.entityId, params.updatedAt, params.index),
    kind: 'upsert_folder',
    entityId: params.entityId,
    entityType: 'bookmark-folder',
    parentId: params.parentEntityId,
    title: params.node.title || '',
    createdAt: previous?.createdAt || toIsoString(params.node.dateAdded),
    updatedAt: params.updatedAt,
    updatedBy: params.deviceId,
    revision,
  };
};

const buildDeleteOperation = (params: {
  node: BookmarkTreeNode;
  entityId: string;
  baseSnapshot: LeafTabSyncSnapshot;
  deviceId: string;
  updatedAt: string;
  index: number;
}): LeafTabSyncOperation => {
  const entityType = params.node.url ? 'bookmark-item' : 'bookmark-folder';
  const previous = params.node.url
    ? params.baseSnapshot.bookmarkItems[params.entityId]
    : params.baseSnapshot.bookmarkFolders[params.entityId];
  const revision = previous?.revision || 1;
  return {
    id: createOperationId('delete', params.entityId, params.updatedAt, params.index),
    kind: 'delete_entity',
    entityId: params.entityId,
    entityType,
    updatedAt: params.updatedAt,
    updatedBy: params.deviceId,
    revision,
    lastKnownRevision: revision,
  };
};

const buildOrderOperation = async (params: {
  parentLocalId: string | undefined;
  mapping: BookmarkMappingState;
  baseSnapshot: LeafTabSyncSnapshot;
  deviceId: string;
  updatedAt: string;
  index: number;
}): Promise<LeafTabSyncOperation | undefined | null> => {
  const parentEntityId = resolveParentEntityId(params.parentLocalId, params.mapping);
  if (parentEntityId === undefined) {
    return undefined;
  }
  if (!params.parentLocalId) {
    return undefined;
  }
  const children = await getBookmarkChildren(params.parentLocalId);
  if (!children) {
    return null;
  }
  const ids: string[] = [];
  for (const child of children) {
    const entityId = resolveMappedEntityId(child.id, params.mapping);
    if (!entityId) {
      return null;
    }
    ids.push(entityId);
  }
  const key = parentEntityId || ROOT_ORDER_KEY;
  const previous = params.baseSnapshot.bookmarkOrders[key];
  return {
    id: createOperationId('order', key, params.updatedAt, params.index),
    kind: 'upsert_order',
    entityId: key,
    parentId: parentEntityId,
    ids,
    updatedAt: params.updatedAt,
    updatedBy: params.deviceId,
    revision: previous ? previous.revision + 1 : 1,
  };
};

const collectRemovedNodes = (node: BookmarkTreeNode): BookmarkTreeNode[] => {
  const result: BookmarkTreeNode[] = [node];
  (node.children || []).forEach((child) => {
    result.push(...collectRemovedNodes(child));
  });
  return result;
};

export const appendLeafTabLocalBookmarkOperationEvent = async (
  event: LeafTabLocalBookmarkOperationEvent,
): Promise<void> => {
  const events = await readOutbox();
  events.push(event);
  await writeOutbox(events);
};

export const clearLeafTabLocalBookmarkOperationOutbox = async (): Promise<void> => {
  await removeExtensionStorageKeys([OUTBOX_STORAGE_KEY]);
};

export const hasPendingLeafTabLocalBookmarkOperationOutbox = async (): Promise<boolean> => {
  return (await readOutbox()).length > 0;
};

export const buildLeafTabPendingLocalOperationsFromOutbox = async (params: {
  baseSnapshot: LeafTabSyncSnapshot;
  deviceId: string;
}): Promise<LeafTabSyncOperation[] | null> => {
  const events = await readOutbox();
  if (events.length <= 0) {
    return [];
  }
  if (events.length > MAX_DIRECT_OPERATION_EVENTS || events.some((event) => event.kind === 'import_ended')) {
    return null;
  }
  const mapping = await readMapping();
  const operations: LeafTabSyncOperation[] = [];
  let mappingChanged = false;

  for (const event of events) {
    const updatedAt = toIsoString(event.at);
    if (event.kind === 'created') {
      const parentEntityId = resolveParentEntityId(event.node.parentId, mapping);
      if (parentEntityId === undefined) return null;
      const entityId = ensureMappedEntityId(event.node, parentEntityId, mapping);
      mappingChanged = true;
      operations.push(buildUpsertOperation({
        node: event.node,
        entityId,
        parentEntityId,
        baseSnapshot: params.baseSnapshot,
        deviceId: params.deviceId,
        updatedAt,
        index: operations.length,
      }));
      const order = await buildOrderOperation({
        parentLocalId: event.node.parentId,
        mapping,
        baseSnapshot: params.baseSnapshot,
        deviceId: params.deviceId,
        updatedAt,
        index: operations.length,
      });
      if (order === null) return null;
      if (order) operations.push(order);
      continue;
    }

    if (event.kind === 'changed' || event.kind === 'moved') {
      const node = await getBookmarkNode(event.id);
      if (!node) return null;
      const parentEntityId = resolveParentEntityId(node.parentId, mapping);
      if (parentEntityId === undefined) continue;
      const entityId = resolveMappedEntityId(node.id, mapping);
      if (!entityId) return null;
      operations.push(buildUpsertOperation({
        node,
        entityId,
        parentEntityId,
        baseSnapshot: params.baseSnapshot,
        deviceId: params.deviceId,
        updatedAt,
        index: operations.length,
      }));
      if (event.kind === 'moved') {
        const parentIds = [event.oldParentId, event.parentId || node.parentId];
        for (const parentLocalId of Array.from(new Set(parentIds.filter(Boolean)))) {
          const order = await buildOrderOperation({
            parentLocalId,
            mapping,
            baseSnapshot: params.baseSnapshot,
            deviceId: params.deviceId,
            updatedAt,
            index: operations.length,
          });
          if (order === null) return null;
          if (order) operations.push(order);
        }
      }
      continue;
    }

    if (event.kind === 'removed') {
      const deletedNodes = collectRemovedNodes(event.node).reverse();
      for (const node of deletedNodes) {
        const entityId = resolveMappedEntityId(node.id, mapping);
        if (!entityId) return null;
        operations.push(buildDeleteOperation({
          node,
          entityId,
          baseSnapshot: params.baseSnapshot,
          deviceId: params.deviceId,
          updatedAt,
          index: operations.length,
        }));
        delete mapping.nodeIdToEntityId[node.id];
        mappingChanged = true;
      }
      const order = await buildOrderOperation({
        parentLocalId: event.parentId || event.node.parentId,
        mapping,
        baseSnapshot: params.baseSnapshot,
        deviceId: params.deviceId,
        updatedAt,
        index: operations.length,
      });
      if (order === null) return null;
      if (order) operations.push(order);
      continue;
    }

    if (event.kind === 'children_reordered') {
      const order = await buildOrderOperation({
        parentLocalId: event.id,
        mapping,
        baseSnapshot: params.baseSnapshot,
        deviceId: params.deviceId,
        updatedAt,
        index: operations.length,
      });
      if (order === null) return null;
      if (order) operations.push(order);
    }
  }

  if (mappingChanged) {
    await writeMapping(mapping);
  }
  return operations;
};
