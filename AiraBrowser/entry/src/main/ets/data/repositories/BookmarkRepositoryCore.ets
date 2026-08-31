import {
  BookmarkCreateNodeCommand,
  BookmarkMoveSubtreesCommand,
  BookmarkMoveSubtreeCommand,
  BookmarkNode,
  BookmarkReorderChildrenCommand,
  BookmarkRepositorySnapshot,
  BookmarkRootRecord,
  BookmarkStorageScope,
  UpdateBookmarkCommand
} from '../../common/models/BrowserModels';
export const DEFAULT_DEVICE_ID: string = 'aira-phone-local';
export const DEFAULT_ACTOR: string = 'browser-shell-seed';
export const BOOKMARK_TOOLBAR_ROOT_ID: string = 'bookmark-root-toolbar';
export const BOOKMARK_OTHER_ROOT_ID: string = 'bookmark-root-other';
export const PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID: string = 'private-bookmark-root-toolbar';
export const PRIVATE_BOOKMARK_OTHER_ROOT_ID: string = 'private-bookmark-root-other';
const LOCAL_ACTOR = 'aira-bookmark-manager';
let localBookmarkIdSequence: number = 0;

export function buildBookmarkRootRecords(): BookmarkRootRecord[] {
  return [
    {
      role: 'toolbar',
      nodeId: BOOKMARK_TOOLBAR_ROOT_ID,
      title: '书签栏',
      position: 0,
      syncEnabled: true
    },
    {
      role: 'other',
      nodeId: BOOKMARK_OTHER_ROOT_ID,
      title: '其他书签',
      position: 1,
      syncEnabled: true
    }
  ];
}

export function resolveBookmarkScope(scope?: BookmarkStorageScope | string): BookmarkStorageScope {
  return scope === 'private' ? 'private' : 'regular';
}

export function isPrivateBookmarkRootNodeId(id: string): boolean {
  return id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID || id === PRIVATE_BOOKMARK_OTHER_ROOT_ID;
}

export class InMemoryBookmarkRepository {
  private roots: BookmarkRootRecord[] = buildBookmarkRootRecords();
  private nodes: BookmarkNode[] = buildSeedBookmarkNodes();
  private bookmarkChangeGeneration: number = 0;
  private activeNodes: BookmarkNode[] = [];
  private syncNodeById: Map<string, BookmarkNode> = new Map();
  private activeNodeById: Map<string, BookmarkNode> = new Map();
  private childrenByParent: Map<string, BookmarkNode[]> = new Map();
  private bookmarkByScopedNormalizedUrl: Map<string, BookmarkNode> = new Map();
  private suggestionCandidates: BookmarkNode[] = [];

  constructor() {
    this.rebuildIndexes();
  }

  listRoots(): BookmarkRootRecord[] {
    return this.roots.slice().sort((left: BookmarkRootRecord, right: BookmarkRootRecord) => left.position - right.position);
  }

  listNodes(scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    return this.activeNodes.filter((node: BookmarkNode) => this.matchesBookmarkScope(node, scope));
  }

  getChangeGeneration(): number {
    return this.bookmarkChangeGeneration;
  }

  listSuggestionCandidates(limit?: number, scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    const candidates = this.suggestionCandidates.filter((node: BookmarkNode) => this.matchesBookmarkScope(node, scope));
    if (limit !== undefined) {
      return candidates.slice(0, limit);
    }
    return candidates;
  }

  listSearchCandidates(query: string, limit: number, scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    return filterBookmarkSearchCandidates(this.suggestionCandidates.filter((node: BookmarkNode) => {
      return this.matchesBookmarkScope(node, scope);
    }), query, limit);
  }

  listSyncNodes(scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    return this.nodes.filter((node: BookmarkNode) => this.matchesBookmarkScope(node, scope));
  }

  listChildren(parentId?: string, scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    return (this.childrenByParent.get(this.toParentKey(parentId)) ?? [])
      .filter((node: BookmarkNode) => this.matchesBookmarkScope(node, scope));
  }

  findBookmarkByUrl(url: string, scope: BookmarkStorageScope = 'regular'): BookmarkNode | undefined {
    return this.bookmarkByScopedNormalizedUrl.get(buildBookmarkUrlIdentityKey(url, scope));
  }

  findNodeById(id: string, includeDeleted: boolean = false): BookmarkNode | undefined {
    return includeDeleted ? this.syncNodeById.get(id) : this.activeNodeById.get(id);
  }

  listSubtree(rootId: string, includeDeleted: boolean = false, scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    const source = includeDeleted ? this.listSyncNodes(scope) : this.listNodes(scope);
    const subtreeIds = collectBookmarkSubtreeIds(source, rootId);
    return source.filter((node: BookmarkNode) => subtreeIds.indexOf(node.id) >= 0);
  }

  getSnapshot(includeDeleted: boolean = false, scope: BookmarkStorageScope = 'regular'): BookmarkRepositorySnapshot {
    return {
      roots: this.listRoots(),
      nodes: includeDeleted ? this.listSyncNodes(scope) : this.listNodes(scope)
    };
  }

  isInitialized(): boolean {
    return true;
  }

  async initialize(): Promise<void> {
    return Promise.resolve();
  }

  async refresh(): Promise<BookmarkNode[]> {
    return Promise.resolve(this.listNodes());
  }

  async seedIfEmpty(): Promise<void> {
    return Promise.resolve();
  }

  async createNode(command: BookmarkCreateNodeCommand): Promise<BookmarkNode> {
    const now = Date.now();
    const parentId = this.normalizeParentId(command.parentId);
    const node = buildLocalBookmarkNode(
      createLocalBookmarkId(command.type, resolveBookmarkScope(command.scope)),
      command.type,
      sanitizeBookmarkTitle(command.title, command.type === 'folder' ? '新文件夹' : '新书签'),
      parentId,
      this.resolveNextPosition(parentId),
      now,
      command.type === 'bookmark' ? command.url : undefined,
      resolveBookmarkScope(command.scope)
    );
    this.nodes.push(node);
    this.rebuildIndexes();
    return Promise.resolve(node);
  }

  async updateNode(command: UpdateBookmarkCommand): Promise<BookmarkNode | undefined> {
    const node = this.nodes.find((item: BookmarkNode) => item.id === command.id && item.sync.deletedAt === undefined);
    if (node === undefined) {
      return Promise.resolve(undefined);
    }

    const updated = applyLocalBookmarkUpdate(node, command);
    this.nodes = this.nodes.map((item: BookmarkNode) => item.id === updated.id ? updated : item);
    this.rebuildIndexes();
    return Promise.resolve(updated);
  }

  async upsertNode(node: BookmarkNode): Promise<BookmarkNode> {
    const index = this.nodes.findIndex((item: BookmarkNode) => item.id === node.id);
    if (index >= 0) {
      this.nodes[index] = node;
    } else {
      this.nodes.push(node);
    }
    this.rebuildIndexes();
    return Promise.resolve(node);
  }

  async upsertSyncNodes(nodes: BookmarkNode[]): Promise<BookmarkNode[]> {
    const nodeById = new Map<string, BookmarkNode>();
    this.nodes.forEach((node: BookmarkNode) => {
      nodeById.set(node.id, node);
    });
    nodes.forEach((node: BookmarkNode) => {
      nodeById.set(node.id, node);
    });
    this.nodes = Array.from(nodeById.values());
    this.rebuildIndexes();
    return Promise.resolve(nodes);
  }

  async upsertImportedSyncNodes(nodes: BookmarkNode[]): Promise<BookmarkNode[]> {
    return this.upsertSyncNodes(nodes);
  }

  async reorderChildren(command: BookmarkReorderChildrenCommand): Promise<BookmarkNode[]> {
    const siblings = this.listChildren(command.parentId);
    const siblingMap = new Map<string, BookmarkNode>();
    siblings.forEach((node: BookmarkNode) => siblingMap.set(node.id, node));
    const reordered: BookmarkNode[] = [];
    const seen = new Set<string>();
    command.childIds.forEach((id: string) => {
      const node = siblingMap.get(id);
      if (node !== undefined) {
        reordered.push(node);
        seen.add(id);
      }
    });
    siblings.forEach((node: BookmarkNode) => {
      if (!seen.has(node.id)) {
        reordered.push(node);
      }
    });
    const now = Date.now();
    this.nodes = this.nodes.map((node: BookmarkNode) => {
      const nextIndex = reordered.findIndex((item: BookmarkNode) => item.id === node.id);
      return nextIndex >= 0 ? markBookmarkRepositioned(node, nextIndex, now) : node;
    });
    this.rebuildIndexes();
    return Promise.resolve(this.listChildren(command.parentId));
  }

  async moveSubtree(command: BookmarkMoveSubtreeCommand): Promise<BookmarkNode | undefined> {
    const node = this.findNodeById(command.nodeId);
    if (node === undefined) {
      return Promise.resolve(undefined);
    }
    const nextParentId = this.normalizeParentId(command.parentId);
    const siblings = this.listChildren(nextParentId).filter((item: BookmarkNode) => item.id !== node.id);
    const boundedIndex = Math.max(0, Math.min(command.targetIndex, siblings.length));
    const now = Date.now();
    const movedNode = markBookmarkMoved(node, nextParentId, boundedIndex, now);
    this.nodes = this.nodes.map((item: BookmarkNode) => item.id === node.id ? movedNode : item);
    this.rebuildIndexes();
    const reorderedIds = siblings.slice(0, boundedIndex).map((item: BookmarkNode) => item.id)
      .concat([movedNode.id], siblings.slice(boundedIndex).map((item: BookmarkNode) => item.id));
    await this.reorderChildren({
      parentId: nextParentId,
      childIds: reorderedIds
    });
    if (node.parentId !== nextParentId) {
      this.renumberActiveChildren(node.parentId);
    }
    return Promise.resolve(this.findNodeById(command.nodeId));
  }

  async moveSubtrees(command: BookmarkMoveSubtreesCommand): Promise<BookmarkNode[]> {
    const movingNodes = this.resolveMovableNodes(command.nodeIds);
    if (movingNodes.length === 0) {
      return Promise.resolve([]);
    }
    const nextParentId = this.normalizeParentId(command.parentId);
    const movingLookup = buildBookmarkIdLookup(movingNodes.map((node: BookmarkNode) => node.id));
    const targetSiblings = this.listChildren(nextParentId).filter((item: BookmarkNode) => !movingLookup.has(item.id));
    const boundedIndex = Math.max(0, Math.min(command.targetIndex, targetSiblings.length));
    const now = Date.now();
    const movedNodes = movingNodes.map((node: BookmarkNode, index: number) => {
      return markBookmarkMoved(node, nextParentId, boundedIndex + index, now);
    });
    const movedById = new Map<string, BookmarkNode>();
    movedNodes.forEach((node: BookmarkNode) => {
      movedById.set(node.id, node);
    });
    const targetOrdered = targetSiblings.slice(0, boundedIndex)
      .concat(movedNodes, targetSiblings.slice(boundedIndex))
      .map((node: BookmarkNode, index: number) => markBookmarkRepositioned(node, index, now));
    const sourceParentKeys = this.collectSourceParentKeys(movingNodes, nextParentId);
    this.nodes = this.nodes.map((node: BookmarkNode) => {
      return movedById.get(node.id) ?? node;
    });
    this.rebuildIndexes();
    const sourceRepositioned = this.buildRepositionedChildren(sourceParentKeys, now);
    const updateById = new Map<string, BookmarkNode>();
    targetOrdered.concat(sourceRepositioned).forEach((node: BookmarkNode) => {
      updateById.set(node.id, node);
    });
    this.nodes = this.nodes.map((node: BookmarkNode) => updateById.get(node.id) ?? node);
    this.rebuildIndexes();
    const resolvedNodes: BookmarkNode[] = [];
    movedNodes.forEach((node: BookmarkNode) => {
      const resolvedNode = this.findNodeById(node.id);
      if (resolvedNode !== undefined) {
        resolvedNodes.push(resolvedNode);
      }
    });
    return Promise.resolve(resolvedNodes);
  }

  async replaceSnapshot(snapshot: BookmarkRepositorySnapshot): Promise<BookmarkRepositorySnapshot> {
    this.roots = buildBookmarkRootRecords();
    this.nodes = this.nodes.filter((node: BookmarkNode) => !this.matchesBookmarkScope(node, 'regular'))
      .concat(snapshot.nodes);
    this.rebuildIndexes();
    return Promise.resolve(this.getSnapshot(true));
  }

  async purgeDeletedSyncNodes(
    scope: BookmarkStorageScope = 'regular',
    deletedBefore?: number
  ): Promise<number> {
    const beforeCount = this.nodes.length;
    this.nodes = this.nodes.filter((node: BookmarkNode): boolean => {
      return !this.matchesBookmarkScope(node, scope) || node.sync.deletedAt === undefined ||
        (deletedBefore !== undefined && node.sync.deletedAt >= deletedBefore);
    });
    const deletedCount = beforeCount - this.nodes.length;
    if (deletedCount > 0) {
      this.rebuildIndexes();
    }
    return Promise.resolve(deletedCount);
  }

  async deleteNode(id: string): Promise<boolean> {
    const deletingIds = collectBookmarkSubtreeIds(this.nodes, id);
    if (deletingIds.length === 0) {
      return Promise.resolve(false);
    }

    const now = Date.now();
    this.nodes = this.nodes.map((node: BookmarkNode) => {
      if (deletingIds.indexOf(node.id) < 0) {
        return node;
      }
      return markBookmarkDeleted(node, now);
    });
    this.rebuildIndexes();
    this.compactActiveChildren(this.findNodeParentId(id));
    return Promise.resolve(true);
  }

  async deleteNodes(ids: string[]): Promise<number> {
    const deletingIds = collectBookmarkSubtreeIdsForRoots(this.nodes, ids);
    if (deletingIds.length === 0) {
      return Promise.resolve(0);
    }
    const deletingLookup = buildBookmarkIdLookup(deletingIds);
    const affectedParentIds = this.collectAffectedParentIds(ids, deletingLookup);
    const now = Date.now();
    this.nodes = this.nodes.map((node: BookmarkNode) => {
      if (!deletingLookup.has(node.id)) {
        return node;
      }
      return markBookmarkDeleted(node, now);
    });
    this.rebuildIndexes();
    affectedParentIds.forEach((parentId: string) => {
      this.compactActiveChildren(this.fromParentKey(parentId));
    });
    return Promise.resolve(this.countDeletedRootIds(ids, deletingLookup));
  }

  private normalizeParentId(parentId?: string): string | undefined {
    if (parentId === undefined) {
      return undefined;
    }

    const parent = this.findNodeById(parentId);
    if (parent !== undefined && parent.type !== 'folder') {
      return undefined;
    }
    return parent ? parent.id : undefined;
  }

  private resolveNextPosition(parentId?: string): number {
    const siblings = this.listChildren(parentId);
    if (siblings.length === 0) {
      return 0;
    }

    return siblings[siblings.length - 1].position + 1;
  }

  private findNodeParentId(id: string): string | undefined {
    const node = this.nodes.find((item: BookmarkNode) => item.id === id);
    return node ? node.parentId : undefined;
  }

  private resolveMovableNodes(nodeIds: string[]): BookmarkNode[] {
    const movingNodes: BookmarkNode[] = [];
    const movingLookup = new Set<string>();
    nodeIds.forEach((id: string) => {
      const node = this.findNodeById(id);
      if (node !== undefined && !movingLookup.has(node.id)) {
        movingLookup.add(node.id);
        movingNodes.push(node);
      }
    });
    return movingNodes;
  }

  private collectSourceParentKeys(movingNodes: BookmarkNode[], targetParentId?: string): string[] {
    const parentKeys: string[] = [];
    movingNodes.forEach((node: BookmarkNode) => {
      if (node.parentId === targetParentId) {
        return;
      }
      const parentKey = this.toParentKey(node.parentId);
      if (parentKeys.indexOf(parentKey) < 0) {
        parentKeys.push(parentKey);
      }
    });
    return parentKeys;
  }

  private buildRepositionedChildren(parentKeys: string[], now: number): BookmarkNode[] {
    const repositioned: BookmarkNode[] = [];
    parentKeys.forEach((parentKey: string) => {
      const parentId = this.fromParentKey(parentKey);
      this.listChildren(parentId).forEach((node: BookmarkNode, index: number) => {
        if (node.position !== index) {
          repositioned.push(markBookmarkRepositioned(node, index, now));
        }
      });
    });
    return repositioned;
  }

  private collectAffectedParentIds(rootIds: string[], deletingLookup: Set<string>): string[] {
    const parentIds: string[] = [];
    rootIds.forEach((id: string) => {
      if (!deletingLookup.has(id)) {
        return;
      }
      const parentId = this.findNodeParentId(id);
      if (parentId !== undefined && deletingLookup.has(parentId)) {
        return;
      }
      const parentKey = this.toParentKey(parentId);
      if (parentIds.indexOf(parentKey) < 0) {
        parentIds.push(parentKey);
      }
    });
    return parentIds;
  }

  private countDeletedRootIds(rootIds: string[], deletingLookup: Set<string>): number {
    const countedIds: string[] = [];
    rootIds.forEach((id: string) => {
      if (deletingLookup.has(id) && countedIds.indexOf(id) < 0) {
        countedIds.push(id);
      }
    });
    return countedIds.length;
  }

  private renumberActiveChildren(parentId?: string): void {
    const now = Date.now();
    const siblings = this.listChildren(parentId);
    siblings.forEach((node: BookmarkNode, index: number) => {
      this.nodes = this.nodes.map((item: BookmarkNode) => {
        if (item.id === node.id) {
          return markBookmarkRepositioned(item, index, now);
        }
        return item;
      });
    });
    this.rebuildIndexes();
  }

  private compactActiveChildren(parentId?: string): void {
    const siblings = this.listChildren(parentId);
    siblings.forEach((node: BookmarkNode, index: number) => {
      this.nodes = this.nodes.map((item: BookmarkNode) => {
        if (item.id === node.id) {
          return markBookmarkPositionCompacted(item, index);
        }
        return item;
      });
    });
    this.rebuildIndexes();
  }

  private fromParentKey(parentKey: string): string | undefined {
    return parentKey.length > 0 ? parentKey : undefined;
  }

  private rebuildIndexes(): void {
    this.syncNodeById = new Map();
    this.activeNodeById = new Map();
    this.childrenByParent = new Map();
    this.bookmarkByScopedNormalizedUrl = new Map();
    this.suggestionCandidates = [];
    this.activeNodes = [];
    this.nodes.forEach((node: BookmarkNode) => {
      this.syncNodeById.set(node.id, node);
      if (node.sync.deletedAt !== undefined) {
        return;
      }
      this.activeNodes.push(node);
      this.activeNodeById.set(node.id, node);
      const parentKey = this.toParentKey(node.parentId);
      const siblings = this.childrenByParent.get(parentKey) ?? [];
      siblings.push(node);
      this.childrenByParent.set(parentKey, siblings);
      if (node.type === 'bookmark') {
        if (isUserSearchableBookmark(node)) {
          this.suggestionCandidates.push(node);
          const identityKey = buildBookmarkUrlIdentityKey(node.url ?? '', resolveBookmarkScope(node.scope));
          if (!this.bookmarkByScopedNormalizedUrl.has(identityKey)) {
            this.bookmarkByScopedNormalizedUrl.set(identityKey, node);
          }
        }
      }
    });
    this.childrenByParent.forEach((siblings: BookmarkNode[]) => {
      siblings.sort((left: BookmarkNode, right: BookmarkNode) => left.position - right.position);
    });
    this.bookmarkChangeGeneration += 1;
  }

  private toParentKey(parentId?: string): string {
    return parentId ?? '';
  }

  private matchesBookmarkScope(node: BookmarkNode, scope: BookmarkStorageScope): boolean {
    return resolveBookmarkScope(node.scope) === resolveBookmarkScope(scope);
  }
}

export function buildSeedBookmarkNodes(): BookmarkNode[] {
  return [
    createFolderNode(BOOKMARK_TOOLBAR_ROOT_ID, '书签栏', 0),
    createFolderNode(BOOKMARK_OTHER_ROOT_ID, '其他书签', 1),
    createFolderNode(PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID, '隐私书签栏', 2, undefined, 'private'),
    createFolderNode(PRIVATE_BOOKMARK_OTHER_ROOT_ID, '其他隐私书签', 3, undefined, 'private')
  ];
}

export function buildMissingSeedBookmarkNodes(existingNodes: BookmarkNode[]): BookmarkNode[] {
  const seedNodes = buildSeedBookmarkNodes();
  const existingIds = new Set<string>(existingNodes.map((node: BookmarkNode) => node.id));
  let nextToolbarPosition = resolveNextSeedBookmarkPosition(existingNodes, BOOKMARK_TOOLBAR_ROOT_ID);
  return seedNodes
    .filter((node: BookmarkNode) => !existingIds.has(node.id))
    .map((node: BookmarkNode) => {
      if (node.type === 'folder') {
        return node;
      }
      const positioned = createBookmarkNode(
        node.id,
        node.title,
        node.url ?? '',
        BOOKMARK_TOOLBAR_ROOT_ID,
        nextToolbarPosition,
        node.sync.originId,
        node.sync.source === 'chrome_import' ? 'chrome_import' : 'seed',
        resolveBookmarkScope(node.scope)
      );
      nextToolbarPosition += 1;
      return positioned;
    });
}

function resolveNextSeedBookmarkPosition(existingNodes: BookmarkNode[], parentId: string): number {
  const activeChildren = existingNodes.filter((node: BookmarkNode) => {
    return node.sync.deletedAt === undefined && node.parentId === parentId;
  });
  if (activeChildren.length === 0) {
    return 0;
  }
  return Math.max(...activeChildren.map((node: BookmarkNode) => node.position)) + 1;
}

export function buildLocalBookmarkNode(
  id: string,
  type: 'folder' | 'bookmark',
  title: string,
  parentId: string | undefined,
  position: number,
  now: number,
  url?: string,
  scope: BookmarkStorageScope = 'regular'
): BookmarkNode {
  return {
    id: id,
    type: type,
    scope: resolveBookmarkScope(scope),
    parentId: parentId,
    title: title,
    url: type === 'bookmark' ? sanitizeBookmarkUrl(url ?? '') : undefined,
    position: position,
    createdAt: now,
    updatedAt: now,
    sync: {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: now,
      lastModifiedBy: LOCAL_ACTOR,
      deviceId: DEFAULT_DEVICE_ID
    }
  };
}

export function createLocalBookmarkId(kind: 'folder' | 'bookmark', scope: BookmarkStorageScope = 'regular'): string {
  localBookmarkIdSequence = (localBookmarkIdSequence + 1) % 1000000;
  const sequence = localBookmarkIdSequence.toString().padStart(6, '0');
  const prefix = scope === 'private' ? `local-private-${kind}` : `local-${kind}`;
  return `${prefix}-${Date.now()}-${sequence}-${Math.floor(Math.random() * 1000000)}`;
}

export function sanitizeBookmarkTitle(title: string, fallback: string): string {
  const trimmed = title.trim();
  return trimmed.length > 0 ? trimmed : fallback;
}

export function sanitizeBookmarkUrl(url: string): string {
  const trimmed = url.trim();
  if (trimmed.length === 0) {
    return 'about:blank';
  }

  if (trimmed.indexOf('://') >= 0 || trimmed.startsWith('about:')) {
    return trimmed;
  }

  return `https://${trimmed}`;
}

export function buildBookmarkUrlIdentityKey(
  url: string,
  scope: BookmarkStorageScope = 'regular'
): string {
  return `${resolveBookmarkScope(scope)}\n${sanitizeBookmarkUrl(url)}`;
}

export function filterBookmarkSearchCandidates(
  bookmarks: BookmarkNode[],
  query: string,
  limit: number
): BookmarkNode[] {
  const normalizedQuery = normalizeBookmarkSearchText(query);
  const candidates = bookmarks.filter((bookmark: BookmarkNode) => isUserSearchableBookmark(bookmark));
  if (normalizedQuery.length === 0 || limit <= 0) {
    return limit > 0 ? candidates.slice(0, limit) : [];
  }
  const compactQuery = normalizeBookmarkSearchUrl(normalizedQuery);
  const results: BookmarkNode[] = [];
  for (let index = 0; index < candidates.length && results.length < limit; index += 1) {
    const bookmark = candidates[index];
    const title = normalizeBookmarkSearchText(bookmark.title);
    const url = normalizeBookmarkSearchText(bookmark.url ?? '');
    const compactUrl = normalizeBookmarkSearchUrl(url);
    if (title.indexOf(normalizedQuery) >= 0 ||
      url.indexOf(normalizedQuery) >= 0 ||
      (compactQuery.length > 0 && compactUrl.indexOf(compactQuery) >= 0)) {
      results.push(bookmark);
    }
  }
  return results;
}

export function isUserSearchableBookmark(bookmark: BookmarkNode): boolean {
  return bookmark.type === 'bookmark' &&
    (bookmark.url ?? '').trim().length > 0 &&
    bookmark.sync.source !== 'seed';
}

function normalizeBookmarkSearchText(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, ' ');
}

function normalizeBookmarkSearchUrl(value: string): string {
  let normalized = value;
  if (normalized.startsWith('https://')) {
    normalized = normalized.slice('https://'.length);
  } else if (normalized.startsWith('http://')) {
    normalized = normalized.slice('http://'.length);
  }
  if (normalized.startsWith('www.')) {
    normalized = normalized.slice('www.'.length);
  }
  return normalized;
}

export function applyLocalBookmarkUpdate(node: BookmarkNode, command: UpdateBookmarkCommand): BookmarkNode {
  const now = Date.now();
  return {
    id: node.id,
    type: node.type,
    scope: resolveBookmarkScope(node.scope),
    parentId: node.parentId,
    title: sanitizeBookmarkTitle(command.title, node.title),
    url: node.type === 'bookmark' ? sanitizeBookmarkUrl(command.url ?? node.url ?? '') : undefined,
    position: node.position,
    createdAt: node.createdAt,
    updatedAt: now,
    sync: {
      state: 'pending_push',
      source: node.sync.source === 'seed' ? 'local' : node.sync.source,
      lastModifiedAt: now,
      lastModifiedBy: LOCAL_ACTOR,
      deviceId: node.sync.deviceId,
      originId: node.sync.originId,
      deletedAt: node.sync.deletedAt
    }
  };
}

export function markBookmarkDeleted(node: BookmarkNode, now: number): BookmarkNode {
  return {
    id: node.id,
    type: node.type,
    scope: resolveBookmarkScope(node.scope),
    parentId: node.parentId,
    title: node.title,
    url: node.url,
    position: node.position,
    createdAt: node.createdAt,
    updatedAt: now,
    sync: {
      state: 'pending_push',
      source: node.sync.source === 'seed' ? 'local' : node.sync.source,
      lastModifiedAt: now,
      lastModifiedBy: LOCAL_ACTOR,
      deviceId: node.sync.deviceId,
      originId: node.sync.originId,
      deletedAt: now
    }
  };
}

export function markBookmarkMoved(
  node: BookmarkNode,
  parentId: string | undefined,
  position: number,
  now: number
): BookmarkNode {
  return {
    id: node.id,
    type: node.type,
    scope: resolveBookmarkScope(node.scope),
    parentId: parentId,
    title: node.title,
    url: node.url,
    position: position,
    createdAt: node.createdAt,
    updatedAt: now,
    sync: {
      state: 'pending_push',
      source: node.sync.source === 'seed' ? 'local' : node.sync.source,
      lastModifiedAt: now,
      lastModifiedBy: LOCAL_ACTOR,
      deviceId: node.sync.deviceId,
      originId: node.sync.originId,
      deletedAt: node.sync.deletedAt
    }
  };
}

export function markBookmarkRepositioned(node: BookmarkNode, position: number, now: number): BookmarkNode {
  return {
    id: node.id,
    type: node.type,
    scope: resolveBookmarkScope(node.scope),
    parentId: node.parentId,
    title: node.title,
    url: node.url,
    position: position,
    createdAt: node.createdAt,
    updatedAt: now,
    sync: {
      state: 'pending_push',
      source: node.sync.source === 'seed' ? 'local' : node.sync.source,
      lastModifiedAt: now,
      lastModifiedBy: LOCAL_ACTOR,
      deviceId: node.sync.deviceId,
      originId: node.sync.originId,
      deletedAt: node.sync.deletedAt
    }
  };
}

export function markBookmarkPositionCompacted(node: BookmarkNode, position: number): BookmarkNode {
  return {
    id: node.id,
    type: node.type,
    scope: resolveBookmarkScope(node.scope),
    parentId: node.parentId,
    title: node.title,
    url: node.url,
    position: position,
    createdAt: node.createdAt,
    updatedAt: node.updatedAt,
    sync: node.sync
  };
}

export function collectBookmarkSubtreeIds(nodes: BookmarkNode[], rootId: string): string[] {
  const root = nodes.find((node: BookmarkNode) => node.id === rootId && node.sync.deletedAt === undefined);
  if (root === undefined) {
    return [];
  }

  const result: string[] = [rootId];
  collectBookmarkChildIds(nodes, rootId, result);
  return result;
}

export function collectBookmarkSubtreeIdsForRoots(nodes: BookmarkNode[], rootIds: string[]): string[] {
  const childrenByParent = new Map<string, BookmarkNode[]>();
  const activeNodeIds = new Set<string>();
  nodes.forEach((node: BookmarkNode) => {
    if (node.sync.deletedAt !== undefined) {
      return;
    }
    activeNodeIds.add(node.id);
    const children = childrenByParent.get(node.parentId ?? '') ?? [];
    children.push(node);
    childrenByParent.set(node.parentId ?? '', children);
  });

  const result: string[] = [];
  const visited = new Set<string>();
  rootIds.forEach((rootId: string) => {
    collectBookmarkSubtreeIdsFromIndex(rootId, activeNodeIds, childrenByParent, visited, result);
  });
  return result;
}

export function isBookmarkRootNodeId(id: string): boolean {
  return id === BOOKMARK_TOOLBAR_ROOT_ID ||
    id === BOOKMARK_OTHER_ROOT_ID ||
    isPrivateBookmarkRootNodeId(id);
}

function collectBookmarkChildIds(nodes: BookmarkNode[], parentId: string, result: string[]): void {
  nodes
    .filter((node: BookmarkNode) => node.parentId === parentId && node.sync.deletedAt === undefined)
    .forEach((node: BookmarkNode) => {
      result.push(node.id);
      collectBookmarkChildIds(nodes, node.id, result);
    });
}

function collectBookmarkSubtreeIdsFromIndex(
  rootId: string,
  activeNodeIds: Set<string>,
  childrenByParent: Map<string, BookmarkNode[]>,
  visited: Set<string>,
  result: string[]
): void {
  if (!activeNodeIds.has(rootId) || visited.has(rootId)) {
    return;
  }
  visited.add(rootId);
  result.push(rootId);
  const children = childrenByParent.get(rootId) ?? [];
  children.forEach((child: BookmarkNode) => {
    collectBookmarkSubtreeIdsFromIndex(child.id, activeNodeIds, childrenByParent, visited, result);
  });
}

function buildBookmarkIdLookup(ids: string[]): Set<string> {
  const lookup = new Set<string>();
  ids.forEach((id: string) => {
    lookup.add(id);
  });
  return lookup;
}

function createFolderNode(
  id: string,
  title: string,
  position: number,
  parentId?: string,
  scope: BookmarkStorageScope = 'regular',
  originId?: string,
  source: 'seed' | 'chrome_import' = 'seed'
): BookmarkNode {
  const now = resolveSeedTimestamp(position + 1);
  return {
    id: id,
    type: 'folder',
    scope: resolveBookmarkScope(scope),
    parentId: parentId,
    title: title,
    position: position,
    createdAt: now,
    updatedAt: now,
    sync: {
      state: source === 'seed' ? 'local_only' : 'pending_push',
      source: source,
      lastModifiedAt: now,
      lastModifiedBy: DEFAULT_ACTOR,
      deviceId: DEFAULT_DEVICE_ID,
      originId: originId
    }
  };
}

function createBookmarkNode(
  id: string,
  title: string,
  url: string,
  parentId: string,
  position: number,
  originId?: string,
  source: 'seed' | 'chrome_import' = 'seed',
  scope: BookmarkStorageScope = 'regular'
): BookmarkNode {
  const now = resolveSeedTimestamp(position + 10);
  return {
    id: id,
    type: 'bookmark',
    scope: resolveBookmarkScope(scope),
    parentId: parentId,
    title: title,
    url: url,
    position: position,
    createdAt: now,
    updatedAt: now,
    sync: {
      state: source === 'seed' ? 'local_only' : 'pending_push',
      source: source,
      lastModifiedAt: now,
      lastModifiedBy: DEFAULT_ACTOR,
      deviceId: DEFAULT_DEVICE_ID,
      originId: originId
    }
  };
}

function resolveSeedTimestamp(offsetHours: number): number {
  return 1710000000000 + offsetHours * 3600 * 1000;
}
