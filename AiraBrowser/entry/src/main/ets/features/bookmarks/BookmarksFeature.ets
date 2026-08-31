import { AiraBookmarkOverview } from '../../common/models/AiraSyncModels';
import {
  BookmarkNode,
  BookmarkRepositorySnapshot,
  BookmarkStorageScope,
  BookmarkStats,
  BookmarkTreeRow
} from '../../common/models/BrowserModels';
import { BookmarkRepository } from '../../data/repositories/BrowserRepositories';
import {
  BookmarkFolderBookmarkCountsResult,
  BookmarkTreeQueryService
} from '../../services/bookmarks/BookmarkTreeQueryService';

export class BookmarksFeature {
  private repository: BookmarkRepository;
  private treeQueryService: BookmarkTreeQueryService;
  private scope: BookmarkStorageScope;

  constructor(repository: BookmarkRepository, scope: BookmarkStorageScope = 'regular') {
    this.repository = repository;
    this.scope = scope;
    this.treeQueryService = new BookmarkTreeQueryService(repository, scope);
  }

  setScope(scope: BookmarkStorageScope): void {
    this.scope = scope;
    this.treeQueryService.setScope(scope);
  }

  getCount(): number {
    return this.getStats().bookmarkCount;
  }

  getStats(): BookmarkStats {
    const nodes = this.repository.listNodes(this.scope);
    let bookmarkCount: number = 0;
    let folderCount: number = 0;

    nodes.forEach((node) => {
      if (node.type === 'bookmark') {
        bookmarkCount += 1;
      } else {
        folderCount += 1;
      }
    });

    return {
      totalNodes: nodes.length,
      bookmarkCount: bookmarkCount,
      folderCount: folderCount
    };
  }

  listTreeRows(): BookmarkTreeRow[] {
    const rows: BookmarkTreeRow[] = [];
    this.appendChildren(rows, undefined, 0);
    return rows;
  }

  refresh(): Promise<BookmarkNode[]> {
    return this.treeQueryService.refresh();
  }

  listDisplayChildren(parentId?: string): BookmarkNode[] {
    return this.treeQueryService.listDisplayChildren(parentId);
  }

  searchBookmarks(query: string, limit: number): BookmarkNode[] {
    return this.repository.listSearchCandidates(query, limit, this.scope);
  }

  listPreviewChildren(parentId?: string, limit: number = 50): Promise<BookmarkNode[]> {
    return this.treeQueryService.listPreviewChildren(parentId, limit);
  }

  getPrimaryFolderId(): string | undefined {
    return this.treeQueryService.findPrimaryFolderId();
  }

  findBookmarkByUrl(url: string): BookmarkNode | undefined {
    return this.repository.findBookmarkByUrl(url, this.scope);
  }

  hasBookmarkForUrl(url: string): boolean {
    return this.findBookmarkByUrl(url) !== undefined;
  }

  findNodeById(id: string, includeDeleted: boolean = false): BookmarkNode | undefined {
    return this.treeQueryService.findNodeById(id, includeDeleted);
  }

  listSubtree(rootId: string, includeDeleted: boolean = false): BookmarkNode[] {
    return this.repository.listSubtree(rootId, includeDeleted, this.scope);
  }

  getSnapshot(includeDeleted: boolean = false): BookmarkRepositorySnapshot {
    return this.repository.getSnapshot(includeDeleted, this.scope);
  }

  countBookmarksInFolder(folderId: string): number {
    return this.treeQueryService.countBookmarksInFolder(folderId);
  }

  buildFolderBookmarkCounts(): BookmarkFolderBookmarkCountsResult {
    return this.treeQueryService.buildFolderBookmarkCounts();
  }

  buildFolderBookmarkCountsAsync(): Promise<BookmarkFolderBookmarkCountsResult> {
    return this.treeQueryService.buildFolderBookmarkCountsAsync();
  }

  buildLocalBookmarkOverview(): AiraBookmarkOverview {
    return this.treeQueryService.buildLocalBookmarkOverview();
  }

  buildNextFolderTitle(parentId?: string, baseTitle?: string): string {
    return this.treeQueryService.buildNextFolderTitle(parentId, baseTitle);
  }

  private appendChildren(rows: BookmarkTreeRow[], parentId: string | undefined, depth: number): void {
    const children = this.listDisplayChildren(parentId);
    children.forEach((node: BookmarkNode, index: number) => {
      rows.push({
        id: node.id,
        title: node.title,
        subtitle: this.resolveSubtitle(node),
        type: node.type,
        depth: depth,
        canMoveUp: index > 0,
        canMoveDown: index < children.length - 1
      });

      if (node.type === 'folder') {
        this.appendChildren(rows, node.id, depth + 1);
      }
    });
  }

  private resolveSubtitle(node: BookmarkNode): string {
    if (node.type === 'folder') {
      const children = this.listDisplayChildren(node.id);
      return `${children.length} 个子项`;
    }

    return node.url ?? '';
  }

}
