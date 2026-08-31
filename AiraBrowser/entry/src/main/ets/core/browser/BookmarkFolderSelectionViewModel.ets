import { BookmarkNode } from '../../common/models/BrowserModels';
import { BOOKMARK_TOOLBAR_ROOT_ID } from '../../data/repositories/BookmarkRepositoryCore';
import { BookmarksFeature } from '../../features/bookmarks/BookmarksFeature';
import { BookmarkFolderBookmarkCountsResult } from '../../services/bookmarks/BookmarkTreeQueryService';

const BOOKMARK_FOLDER_SELECTION_BUILD_BATCH_SIZE: number = 200;

function pauseBookmarkFolderSelectionBuild(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => resolve(), 0);
  });
}

export interface BookmarkFolderOptionView {
  id: string;
  title: string;
  subtitle: string;
  parentId: string;
  childFolderCount: number;
  bookmarkCount: number;
  bookmarkCountText: string;
  depth: number;
}

export class BookmarkFolderSelectionViewModel {
  private indexedOptions: BookmarkFolderOptionView[] = [];
  private hasIndexedOptions: boolean = false;
  private folderById: Map<string, BookmarkFolderOptionView> = new Map();
  private childFoldersByParent: Map<string, BookmarkFolderOptionView[]> = new Map();

  buildOptions(bookmarksFeature: BookmarksFeature): BookmarkFolderOptionView[] {
    return this.buildOptionsFromNodes(
      bookmarksFeature.getSnapshot(false).nodes,
      [],
      bookmarksFeature.buildFolderBookmarkCounts()
    );
  }

  async buildOptionsAsync(bookmarksFeature: BookmarksFeature): Promise<BookmarkFolderOptionView[]> {
    return this.buildOptionsFromNodesAsync(
      bookmarksFeature.getSnapshot(false).nodes,
      [],
      await bookmarksFeature.buildFolderBookmarkCountsAsync()
    );
  }

  buildMoveTargetOptions(bookmarksFeature: BookmarksFeature, movingNodeIds: string[]): BookmarkFolderOptionView[] {
    const nodes = bookmarksFeature.getSnapshot(false).nodes;
    const excludedFolderIds = this.buildExcludedMoveFolderIds(nodes, movingNodeIds);
    return this.buildOptionsFromNodes(nodes, excludedFolderIds, bookmarksFeature.buildFolderBookmarkCounts());
  }

  async buildMoveTargetOptionsAsync(
    bookmarksFeature: BookmarksFeature,
    movingNodeIds: string[]
  ): Promise<BookmarkFolderOptionView[]> {
    const nodes = bookmarksFeature.getSnapshot(false).nodes;
    const excludedFolderIds = await this.buildExcludedMoveFolderIdsAsync(nodes, movingNodeIds);
    return this.buildOptionsFromNodesAsync(
      nodes,
      excludedFolderIds,
      await bookmarksFeature.buildFolderBookmarkCountsAsync()
    );
  }

  async buildMoveTargetOptionsFromDataAsync(
    nodes: BookmarkNode[],
    movingNodeIds: string[],
    folderBookmarkCounts: BookmarkFolderBookmarkCountsResult
  ): Promise<BookmarkFolderOptionView[]> {
    const excludedFolderIds = await this.buildExcludedMoveFolderIdsAsync(nodes, movingNodeIds);
    return this.buildOptionsFromNodesAsync(nodes, excludedFolderIds, folderBookmarkCounts);
  }

  private buildOptionsFromNodes(
    nodes: BookmarkNode[],
    excludedFolderIds: string[],
    folderBookmarkCounts: BookmarkFolderBookmarkCountsResult
  ): BookmarkFolderOptionView[] {
    const folderChildrenByParent = this.buildFolderChildrenByParent(nodes, excludedFolderIds);
    const options: BookmarkFolderOptionView[] = [];
    this.appendFolderOptions(options, folderChildrenByParent, folderBookmarkCounts, '', 0);
    return options;
  }

  private async buildOptionsFromNodesAsync(
    nodes: BookmarkNode[],
    excludedFolderIds: string[],
    folderBookmarkCounts: BookmarkFolderBookmarkCountsResult
  ): Promise<BookmarkFolderOptionView[]> {
    const folderChildrenByParent = await this.buildFolderChildrenByParentAsync(nodes, excludedFolderIds);
    const options: BookmarkFolderOptionView[] = [];
    await this.appendFolderOptionsAsync(options, folderChildrenByParent, folderBookmarkCounts, '', 0);
    return options;
  }

  resolveSelectedFolderId(
    currentFolderId: string,
    options: BookmarkFolderOptionView[],
    bookmarksFeature: BookmarksFeature
  ): string {
    this.ensureOptionIndex(options);
    if (this.folderById.has(currentFolderId)) {
      return currentFolderId;
    }
    if (this.folderById.has(BOOKMARK_TOOLBAR_ROOT_ID)) {
      return BOOKMARK_TOOLBAR_ROOT_ID;
    }
    return options.length > 0 ? options[0].id : '';
  }

  listChildFolders(options: BookmarkFolderOptionView[], parentId: string): BookmarkFolderOptionView[] {
    this.ensureOptionIndex(options);
    return (this.childFoldersByParent.get(parentId) ?? []).slice();
  }

  findFolder(options: BookmarkFolderOptionView[], folderId: string): BookmarkFolderOptionView | undefined {
    this.ensureOptionIndex(options);
    return this.folderById.get(folderId);
  }

  resolveParentFolderId(options: BookmarkFolderOptionView[], folderId: string): string {
    const folder = this.findFolder(options, folderId);
    return folder !== undefined ? folder.parentId : '';
  }

  resolveCurrentFolderId(options: BookmarkFolderOptionView[], folderId: string): string {
    if (folderId.length === 0) {
      return '';
    }
    this.ensureOptionIndex(options);
    return this.folderById.has(folderId) ? folderId : '';
  }

  buildFolderPath(options: BookmarkFolderOptionView[], folderId: string): BookmarkFolderOptionView[] {
    this.ensureOptionIndex(options);
    const path: BookmarkFolderOptionView[] = [];
    let currentFolderId = folderId;
    let guard = 0;
    while (currentFolderId.length > 0 && guard < options.length) {
      const folder = this.folderById.get(currentFolderId);
      if (folder === undefined) {
        break;
      }
      path.unshift(folder);
      currentFolderId = folder.parentId;
      guard += 1;
    }
    return path;
  }

  private appendFolderOptions(
    options: BookmarkFolderOptionView[],
    folderChildrenByParent: Map<string, BookmarkNode[]>,
    folderBookmarkCounts: BookmarkFolderBookmarkCountsResult,
    parentId: string,
    depth: number
  ): void {
    const folders = folderChildrenByParent.get(parentId) ?? [];
    folders.forEach((folder: BookmarkNode) => {
      const childFolderCount = (folderChildrenByParent.get(folder.id) ?? []).length;
      const bookmarkCount = folderBookmarkCounts.counts.get(folder.id) ?? 0;
      options.push({
        id: folder.id,
        title: folder.title,
        subtitle: '',
        parentId: parentId,
        childFolderCount: childFolderCount,
        bookmarkCount: bookmarkCount,
        bookmarkCountText: `${bookmarkCount} 个书签`,
        depth: depth
      });
      this.appendFolderOptions(options, folderChildrenByParent, folderBookmarkCounts, folder.id, depth + 1);
    });
  }

  private async appendFolderOptionsAsync(
    options: BookmarkFolderOptionView[],
    folderChildrenByParent: Map<string, BookmarkNode[]>,
    folderBookmarkCounts: BookmarkFolderBookmarkCountsResult,
    parentId: string,
    depth: number
  ): Promise<void> {
    const stack: FolderSelectionBuildStackEntry[] = [{
      parentId: parentId,
      depth: depth,
      nextIndex: 0
    }];
    let appendedCount = 0;
    while (stack.length > 0) {
      const current = stack[stack.length - 1];
      const folders = folderChildrenByParent.get(current.parentId) ?? [];
      if (current.nextIndex >= folders.length) {
        stack.pop();
        continue;
      }
      const folder = folders[current.nextIndex];
      current.nextIndex += 1;
      const childFolderCount = (folderChildrenByParent.get(folder.id) ?? []).length;
      const bookmarkCount = folderBookmarkCounts.counts.get(folder.id) ?? 0;
      options.push({
        id: folder.id,
        title: folder.title,
        subtitle: '',
        parentId: current.parentId,
        childFolderCount: childFolderCount,
        bookmarkCount: bookmarkCount,
        bookmarkCountText: `${bookmarkCount} 个书签`,
        depth: current.depth
      });
      stack.push({
        parentId: folder.id,
        depth: current.depth + 1,
        nextIndex: 0
      });
      appendedCount += 1;
      if (appendedCount % BOOKMARK_FOLDER_SELECTION_BUILD_BATCH_SIZE === 0) {
        await pauseBookmarkFolderSelectionBuild();
      }
    }
  }

  private buildFolderChildrenByParent(nodes: BookmarkNode[], excludedFolderIds: string[]): Map<string, BookmarkNode[]> {
    const folderChildrenByParent = new Map<string, BookmarkNode[]>();
    const excludedLookup = this.buildIdLookup(excludedFolderIds);
    nodes.forEach((node: BookmarkNode) => {
      if (node.type !== 'folder' || excludedLookup.has(node.id)) {
        return;
      }
      const parentKey = node.parentId ?? '';
      const children = folderChildrenByParent.get(parentKey) ?? [];
      children.push(node);
      folderChildrenByParent.set(parentKey, children);
    });
    folderChildrenByParent.forEach((children: BookmarkNode[]) => {
      children.sort((left: BookmarkNode, right: BookmarkNode) => {
        return left.position - right.position;
      });
    });
    return folderChildrenByParent;
  }

  private async buildFolderChildrenByParentAsync(
    nodes: BookmarkNode[],
    excludedFolderIds: string[]
  ): Promise<Map<string, BookmarkNode[]>> {
    const folderChildrenByParent = new Map<string, BookmarkNode[]>();
    const excludedLookup = this.buildIdLookup(excludedFolderIds);
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      if (node.type === 'folder' && !excludedLookup.has(node.id)) {
        const parentKey = node.parentId ?? '';
        const children = folderChildrenByParent.get(parentKey) ?? [];
        children.push(node);
        folderChildrenByParent.set(parentKey, children);
      }
      if ((index + 1) % BOOKMARK_FOLDER_SELECTION_BUILD_BATCH_SIZE === 0) {
        await pauseBookmarkFolderSelectionBuild();
      }
    }
    folderChildrenByParent.forEach((children: BookmarkNode[]) => {
      children.sort((left: BookmarkNode, right: BookmarkNode) => {
        return left.position - right.position;
      });
    });
    return folderChildrenByParent;
  }

  private buildExcludedMoveFolderIds(nodes: BookmarkNode[], movingNodeIds: string[]): string[] {
    const movingLookup = this.buildIdLookup(movingNodeIds);
    const folderChildrenByParent = this.buildFolderChildrenByParent(nodes, []);
    const movingFolderIds: string[] = [];
    nodes.forEach((node: BookmarkNode) => {
      if (node.type === 'folder' && movingLookup.has(node.id)) {
        movingFolderIds.push(node.id);
      }
    });
    const excludedLookup = new Set<string>();
    const excludedIds: string[] = [];
    movingFolderIds.forEach((folderId: string) => {
      this.appendExcludedFolderTree(folderId, folderChildrenByParent, excludedLookup, excludedIds);
    });
    return excludedIds;
  }

  private async buildExcludedMoveFolderIdsAsync(nodes: BookmarkNode[], movingNodeIds: string[]): Promise<string[]> {
    const movingLookup = this.buildIdLookup(movingNodeIds);
    const folderChildrenByParent = await this.buildFolderChildrenByParentAsync(nodes, []);
    const movingFolderIds: string[] = [];
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      if (node.type === 'folder' && movingLookup.has(node.id)) {
        movingFolderIds.push(node.id);
      }
      if ((index + 1) % BOOKMARK_FOLDER_SELECTION_BUILD_BATCH_SIZE === 0) {
        await pauseBookmarkFolderSelectionBuild();
      }
    }
    const excludedLookup = new Set<string>();
    const excludedIds: string[] = [];
    for (let index = 0; index < movingFolderIds.length; index += 1) {
      await this.appendExcludedFolderTreeAsync(movingFolderIds[index], folderChildrenByParent, excludedLookup, excludedIds);
      if ((index + 1) % BOOKMARK_FOLDER_SELECTION_BUILD_BATCH_SIZE === 0) {
        await pauseBookmarkFolderSelectionBuild();
      }
    }
    return excludedIds;
  }

  private appendExcludedFolderTree(
    folderId: string,
    folderChildrenByParent: Map<string, BookmarkNode[]>,
    excludedLookup: Set<string>,
    excludedIds: string[]
  ): void {
    if (excludedLookup.has(folderId)) {
      return;
    }
    excludedLookup.add(folderId);
    excludedIds.push(folderId);
    const children = folderChildrenByParent.get(folderId) ?? [];
    children.forEach((child: BookmarkNode) => {
      this.appendExcludedFolderTree(child.id, folderChildrenByParent, excludedLookup, excludedIds);
    });
  }

  private async appendExcludedFolderTreeAsync(
    folderId: string,
    folderChildrenByParent: Map<string, BookmarkNode[]>,
    excludedLookup: Set<string>,
    excludedIds: string[]
  ): Promise<void> {
    const stack: string[] = [folderId];
    let processedCount = 0;
    while (stack.length > 0) {
      const currentFolderId = stack.pop() ?? '';
      if (currentFolderId.length <= 0 || excludedLookup.has(currentFolderId)) {
        continue;
      }
      excludedLookup.add(currentFolderId);
      excludedIds.push(currentFolderId);
      const children = folderChildrenByParent.get(currentFolderId) ?? [];
      children.forEach((child: BookmarkNode) => {
        stack.push(child.id);
      });
      processedCount += 1;
      if (processedCount % BOOKMARK_FOLDER_SELECTION_BUILD_BATCH_SIZE === 0) {
        await pauseBookmarkFolderSelectionBuild();
      }
    }
  }

  private ensureOptionIndex(options: BookmarkFolderOptionView[]): void {
    if (this.hasIndexedOptions && this.indexedOptions === options) {
      return;
    }

    this.indexedOptions = options;
    this.hasIndexedOptions = true;
    this.folderById = new Map();
    this.childFoldersByParent = new Map();
    options.forEach((option: BookmarkFolderOptionView) => {
      this.folderById.set(option.id, option);
      const children = this.childFoldersByParent.get(option.parentId) ?? [];
      children.push(option);
      this.childFoldersByParent.set(option.parentId, children);
    });
  }

  private buildIdLookup(ids: string[]): Set<string> {
    const lookup = new Set<string>();
    ids.forEach((id: string) => {
      if (id.length > 0) {
        lookup.add(id);
      }
    });
    return lookup;
  }
}

interface FolderSelectionBuildStackEntry {
  parentId: string;
  depth: number;
  nextIndex: number;
}
