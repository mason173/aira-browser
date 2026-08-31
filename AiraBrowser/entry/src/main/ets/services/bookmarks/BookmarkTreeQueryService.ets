import {
  BookmarkNode,
  BookmarkStorageScope
} from '../../common/models/BrowserModels';
import {
  AiraBookmarkOverview
} from '../../common/models/AiraSyncModels';
import { BookmarkRepository } from '../../data/repositories/BrowserRepositories';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../../data/repositories/BookmarkRepositoryCore';

const DEFAULT_NEW_FOLDER_TITLE = '新建文件夹';
const BOOKMARK_FOLDER_COUNT_BATCH_SIZE: number = 200;
const LOCAL_BOOKMARK_OVERVIEW_ROOT_IDS: string[] = [
  BOOKMARK_TOOLBAR_ROOT_ID,
  BOOKMARK_OTHER_ROOT_ID
];

function pauseBookmarkTreeQueryWork(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => resolve(), 0);
  });
}

export interface BookmarkFolderBookmarkCountsResult {
  ready: boolean;
  counts: Map<string, number>;
}

export class BookmarkTreeQueryService {
  private repository: BookmarkRepository;
  private scope: BookmarkStorageScope;

  constructor(repository: BookmarkRepository, scope: BookmarkStorageScope = 'regular') {
    this.repository = repository;
    this.scope = scope;
  }

  setScope(scope: BookmarkStorageScope): void {
    this.scope = scope;
  }

  async refresh(): Promise<BookmarkNode[]> {
    const wasInitialized = this.repository.isInitialized();
    await this.repository.initialize();
    if (wasInitialized) {
      await this.repository.refresh();
    }
    return this.repository.listNodes(this.scope);
  }

  async listPreviewChildren(parentId?: string, limit: number = 50): Promise<BookmarkNode[]> {
    if (this.repository.listPreviewChildren !== undefined) {
      return this.repository.listPreviewChildren(parentId, limit, this.scope);
    }
    await this.repository.initialize();
    return this.listDisplayChildren(parentId).slice(0, Math.max(1, Math.floor(limit)));
  }

  listDisplayChildren(parentId?: string): BookmarkNode[] {
    const children = this.repository.listChildren(parentId, this.scope);
    const folders = children.filter((node: BookmarkNode) => node.type === 'folder');
    const bookmarks = children.filter((node: BookmarkNode) => node.type === 'bookmark');
    return folders.concat(bookmarks);
  }

  findPrimaryFolderId(): string | undefined {
    const primaryRootId = this.scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
    const toolbar = this.repository.listNodes(this.scope).find((node: BookmarkNode) => node.id === primaryRootId);
    if (toolbar !== undefined) {
      return toolbar.id;
    }

    const firstFolder = this.repository.listNodes(this.scope).find((node: BookmarkNode) => node.type === 'folder');
    return firstFolder ? firstFolder.id : undefined;
  }

  findNodeById(id: string, includeDeleted: boolean = false): BookmarkNode | undefined {
    return this.repository.findNodeById(id, includeDeleted);
  }

  countBookmarksInFolder(folderId: string): number {
    let count = 0;
    this.repository.listChildren(folderId, this.scope).forEach((node: BookmarkNode) => {
      if (node.type === 'bookmark') {
        count += 1;
      } else {
        count += this.countBookmarksInFolder(node.id);
      }
    });
    return count;
  }

  buildFolderBookmarkCounts(): BookmarkFolderBookmarkCountsResult {
    const directCounts: Map<string, number> = new Map();
    const countsByFolderId: Map<string, number> = new Map();
    const childFolderIdsByParentId: Map<string, string[]> = new Map();
    const folderIds: string[] = [];
    this.repository.listNodes(this.scope).forEach((node: BookmarkNode) => {
      const parentId = node.parentId ?? '';
      if (node.type === 'bookmark') {
        directCounts.set(parentId, (directCounts.get(parentId) ?? 0) + 1);
        return;
      }
      folderIds.push(node.id);
      const childFolderIds = childFolderIdsByParentId.get(parentId) ?? [];
      childFolderIds.push(node.id);
      childFolderIdsByParentId.set(parentId, childFolderIds);
      if (!directCounts.has(node.id)) {
        directCounts.set(node.id, 0);
      }
    });
    folderIds.forEach((folderId: string) => {
      this.resolveFolderBookmarkCount(folderId, directCounts, countsByFolderId, childFolderIdsByParentId, new Set<string>());
    });
    return {
      ready: this.repository.isInitialized(),
      counts: countsByFolderId
    };
  }

  async buildFolderBookmarkCountsAsync(): Promise<BookmarkFolderBookmarkCountsResult> {
    const directCounts: Map<string, number> = new Map();
    const countsByFolderId: Map<string, number> = new Map();
    const childFolderIdsByParentId: Map<string, string[]> = new Map();
    const parentIdByFolderId: Map<string, string> = new Map();
    const folderIds: string[] = [];
    const nodes = this.repository.listNodes(this.scope);

    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const parentId = node.parentId ?? '';
      if (node.type === 'bookmark') {
        directCounts.set(parentId, (directCounts.get(parentId) ?? 0) + 1);
      } else {
        folderIds.push(node.id);
        parentIdByFolderId.set(node.id, parentId);
        const childFolderIds = childFolderIdsByParentId.get(parentId) ?? [];
        childFolderIds.push(node.id);
        childFolderIdsByParentId.set(parentId, childFolderIds);
        if (!directCounts.has(node.id)) {
          directCounts.set(node.id, 0);
        }
      }
      if ((index + 1) % BOOKMARK_FOLDER_COUNT_BATCH_SIZE === 0) {
        await pauseBookmarkTreeQueryWork();
      }
    }

    const unresolvedChildCounts: Map<string, number> = new Map();
    const accumulatedCounts: Map<string, number> = new Map();
    const readyFolderIds: string[] = [];
    folderIds.forEach((folderId: string) => {
      const childCount = (childFolderIdsByParentId.get(folderId) ?? []).length;
      unresolvedChildCounts.set(folderId, childCount);
      accumulatedCounts.set(folderId, directCounts.get(folderId) ?? 0);
      if (childCount <= 0) {
        readyFolderIds.push(folderId);
      }
    });

    let processedCount = 0;
    while (readyFolderIds.length > 0) {
      const folderId = readyFolderIds.pop() ?? '';
      if (folderId.length <= 0 || countsByFolderId.has(folderId)) {
        continue;
      }
      const count = accumulatedCounts.get(folderId) ?? directCounts.get(folderId) ?? 0;
      countsByFolderId.set(folderId, count);
      const parentId = parentIdByFolderId.get(folderId) ?? '';
      if (parentId.length > 0 && unresolvedChildCounts.has(parentId)) {
        accumulatedCounts.set(parentId, (accumulatedCounts.get(parentId) ?? 0) + count);
        const remaining = Math.max(0, (unresolvedChildCounts.get(parentId) ?? 0) - 1);
        unresolvedChildCounts.set(parentId, remaining);
        if (remaining <= 0) {
          readyFolderIds.push(parentId);
        }
      }
      processedCount += 1;
      if (processedCount % BOOKMARK_FOLDER_COUNT_BATCH_SIZE === 0) {
        await pauseBookmarkTreeQueryWork();
      }
    }

    folderIds.forEach((folderId: string) => {
      if (!countsByFolderId.has(folderId)) {
        countsByFolderId.set(folderId, accumulatedCounts.get(folderId) ?? directCounts.get(folderId) ?? 0);
      }
    });

    return {
      ready: this.repository.isInitialized(),
      counts: countsByFolderId
    };
  }

  buildLocalBookmarkOverview(): AiraBookmarkOverview {
    const nodes = this.repository.listSyncNodes(this.scope);
    const includedIds = this.buildIncludedLocalOverviewNodeIds(nodes);
    const activeNodes = this.filterReachableActiveNodes(nodes).filter((node: BookmarkNode) => includedIds.has(node.id));
    let folderCount = 0;
    let itemCount = 0;
    activeNodes.forEach((node: BookmarkNode) => {
      if (node.type === 'folder') {
        folderCount += 1;
      } else {
        itemCount += 1;
      }
    });
    return {
      bookmarkFolderCount: folderCount,
      bookmarkItemCount: itemCount
    };
  }

  buildNextFolderTitle(parentId?: string, baseTitle: string = DEFAULT_NEW_FOLDER_TITLE): string {
    const children = this.listDisplayChildren(parentId);
    let index = 1;
    let title = baseTitle;
    while (children.find((node: BookmarkNode) => node.type === 'folder' && node.title === title) !== undefined) {
      index += 1;
      title = `${baseTitle} ${index}`;
    }
    return title;
  }

  private resolveFolderBookmarkCount(
    folderId: string,
    directCounts: Map<string, number>,
    countsByFolderId: Map<string, number>,
    childFolderIdsByParentId: Map<string, string[]>,
    visiting: Set<string>
  ): number {
    const cached = countsByFolderId.get(folderId);
    if (cached !== undefined) {
      return cached;
    }
    if (visiting.has(folderId)) {
      return directCounts.get(folderId) ?? 0;
    }
    visiting.add(folderId);
    let count = directCounts.get(folderId) ?? 0;
    const childFolderIds = childFolderIdsByParentId.get(folderId) ?? [];
    childFolderIds.forEach((childFolderId: string) => {
      count += this.resolveFolderBookmarkCount(
        childFolderId,
        directCounts,
        countsByFolderId,
        childFolderIdsByParentId,
        visiting
      );
    });
    visiting.delete(folderId);
    countsByFolderId.set(folderId, count);
    return count;
  }

  private buildIncludedLocalOverviewNodeIds(nodes: BookmarkNode[]): Set<string> {
    const includedIds = new Set<string>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    nodes.forEach((node: BookmarkNode) => {
      const parentKey = node.parentId ?? '';
      const children = childrenByParent.get(parentKey) ?? [];
      children.push(node);
      childrenByParent.set(parentKey, children);
    });
    LOCAL_BOOKMARK_OVERVIEW_ROOT_IDS.forEach((rootId: string) => {
      this.collectLocalOverviewNodeIds(rootId, childrenByParent, includedIds);
    });
    return includedIds;
  }

  private collectLocalOverviewNodeIds(
    nodeId: string,
    childrenByParent: Map<string, BookmarkNode[]>,
    includedIds: Set<string>
  ): void {
    if (includedIds.has(nodeId)) {
      return;
    }
    includedIds.add(nodeId);
    const children = childrenByParent.get(nodeId) ?? [];
    children.forEach((child: BookmarkNode) => {
      this.collectLocalOverviewNodeIds(child.id, childrenByParent, includedIds);
    });
  }

  private filterReachableActiveNodes(nodes: BookmarkNode[]): BookmarkNode[] {
    const nodesById = new Map<string, BookmarkNode>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    nodes.forEach((node: BookmarkNode) => {
      if (node.sync.deletedAt !== undefined) {
        return;
      }
      nodesById.set(node.id, node);
      const parentKey = node.parentId ?? '';
      const children = childrenByParent.get(parentKey) ?? [];
      children.push(node);
      childrenByParent.set(parentKey, children);
    });

    const reachableIds = new Set<string>();
    const roots = childrenByParent.get('') ?? [];
    roots.forEach((node: BookmarkNode) => {
      this.collectReachableActiveNodeIds(node.id, childrenByParent, reachableIds);
    });
    return nodes.filter((node: BookmarkNode) => {
      return node.sync.deletedAt === undefined && reachableIds.has(node.id) &&
        (node.parentId === undefined || nodesById.has(node.parentId));
    });
  }

  private collectReachableActiveNodeIds(
    nodeId: string,
    childrenByParent: Map<string, BookmarkNode[]>,
    reachableIds: Set<string>
  ): void {
    if (reachableIds.has(nodeId)) {
      return;
    }
    reachableIds.add(nodeId);
    const children = childrenByParent.get(nodeId) ?? [];
    children.forEach((child: BookmarkNode) => {
      this.collectReachableActiveNodeIds(child.id, childrenByParent, reachableIds);
    });
  }
}
