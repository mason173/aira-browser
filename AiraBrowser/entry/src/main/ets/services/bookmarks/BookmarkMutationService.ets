import {
  BookmarkImportBatchRecord,
  BookmarkImportBatchSummary,
  BookmarkCreateNodeCommand,
  BookmarkMoveSubtreesCommand,
  BookmarkMoveSubtreeCommand,
  BookmarkNode,
  BookmarkRootRole,
  BookmarkReorderChildrenCommand,
  BookmarkStorageScope,
  UpdateBookmarkCommand
} from '../../common/models/BrowserModels';
import {
  AiraBookmarkImportApplyResult,
  AiraBookmarkImportPlan
} from '../../common/models/AiraSyncModels';
import { BrowserDatabase } from '../../data/database/BrowserDatabase';
import { BookmarkRepository } from '../../data/repositories/BrowserRepositories';
import {
  buildLocalBookmarkNode,
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  createLocalBookmarkId,
  isBookmarkRootNodeId,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID,
  resolveBookmarkScope,
  sanitizeBookmarkTitle
} from '../../data/repositories/BookmarkRepositoryCore';
const FALLBACK_IMPORT_FOLDER_TITLE = 'Aira 导入';

export interface BookmarkUpdateNodeOperation {
  localCommit: Promise<BookmarkNode | undefined>;
  completion: Promise<BookmarkNode | undefined>;
}

type BookmarkSyncPendingMarker = (changedAt: number) => Promise<void>;

export class BookmarkMutationService {
  private static defaultMarkSyncPending?: BookmarkSyncPendingMarker;
  private repository: BookmarkRepository;
  private database?: BrowserDatabase;
  private markSyncPending?: BookmarkSyncPendingMarker;

  static configureDefaultSyncPendingMarker(marker?: BookmarkSyncPendingMarker): void {
    BookmarkMutationService.defaultMarkSyncPending = marker;
  }

  constructor(repository: BookmarkRepository, database?: BrowserDatabase) {
    this.repository = repository;
    this.database = database ?? this.resolveDatabaseFromRepository(repository);
    this.markSyncPending = BookmarkMutationService.defaultMarkSyncPending;
  }

  async createNode(command: BookmarkCreateNodeCommand): Promise<BookmarkNode> {
    const node = await this.repository.createNode(command);
    await this.markBookmarkSyncPending(node.updatedAt);
    return node;
  }

  async createBookmarkIfMissing(command: BookmarkCreateNodeCommand): Promise<BookmarkNode> {
    const scope = resolveBookmarkScope(command.scope);
    const existing = command.type === 'bookmark' ? this.findBookmarkByUrl(command.url ?? '', scope) : undefined;
    if (existing !== undefined) {
      return existing;
    }
    return this.createNode(command);
  }

  async createBookmarksIfMissing(commands: BookmarkCreateNodeCommand[]): Promise<BookmarkNode[]> {
    await this.repository.initialize();
    const now = Date.now();
    const pendingNodes: BookmarkNode[] = [];
    const knownUrls = new Set<string>();
    this.repository.listNodes('regular').forEach((node: BookmarkNode) => {
      if (node.type !== 'bookmark') {
        return;
      }
      const url = node.url ?? '';
      if (url.length > 0) {
        knownUrls.add(this.normalizeBookmarkUrl(url));
      }
    });
    const nextPositionByParent = new Map<string, number>();

    commands.forEach((command: BookmarkCreateNodeCommand) => {
      if (command.type !== 'bookmark') {
        return;
      }
      const normalizedUrl = this.normalizeBookmarkUrl(command.url ?? '');
      const existing = this.findBookmarkByUrl(normalizedUrl, 'regular');
      if (existing !== undefined) {
        knownUrls.add(normalizedUrl);
        return;
      }
      if (knownUrls.has(normalizedUrl)) {
        return;
      }
      const parentId = this.normalizeParentId(command.parentId);
      const parentKey = parentId ?? '';
      let nextPosition = nextPositionByParent.get(parentKey);
      if (nextPosition === undefined) {
        nextPosition = this.resolveNextPosition(parentId);
      }
      const node = buildLocalBookmarkNode(
        createLocalBookmarkId('bookmark', 'regular'),
        'bookmark',
        sanitizeBookmarkTitle(command.title, '新书签'),
        parentId,
        nextPosition,
        now,
        normalizedUrl,
        'regular'
      );
      nextPositionByParent.set(parentKey, nextPosition + 1);
      pendingNodes.push(node);
      knownUrls.add(normalizedUrl);
    });

    if (pendingNodes.length > 0) {
      await this.repository.upsertSyncNodes(pendingNodes);
      await this.markBookmarkSyncPending(now);
    }
    return pendingNodes;
  }

  async reorderChildren(command: BookmarkReorderChildrenCommand): Promise<BookmarkNode[]> {
    const nodes = await this.repository.reorderChildren(command);
    await this.markBookmarkSyncPending(Date.now());
    return nodes;
  }

  async moveSubtree(command: BookmarkMoveSubtreeCommand): Promise<BookmarkNode | undefined> {
    const moved = await this.repository.moveSubtree(command);
    if (moved !== undefined) {
      await this.markBookmarkSyncPending(moved.updatedAt);
    }
    return moved;
  }

  async moveSubtrees(command: BookmarkMoveSubtreesCommand): Promise<BookmarkNode[]> {
    if (command.nodeIds.some((id: string) => isBookmarkRootNodeId(id))) {
      return Promise.reject(new Error('系统根节点不可移动。'));
    }
    const movedNodes = await this.repository.moveSubtrees(command);
    if (movedNodes.length > 0) {
      await this.markBookmarkSyncPending(Date.now());
    }
    return movedNodes;
  }

  async updateNode(command: UpdateBookmarkCommand): Promise<BookmarkNode | undefined> {
    return this.beginUpdateNode(command).completion;
  }

  beginUpdateNode(command: UpdateBookmarkCommand): BookmarkUpdateNodeOperation {
    const localCommit = this.repository.updateNode(command);
    const completion = localCommit.then(async (updated: BookmarkNode | undefined) => {
      await this.completeUpdateNodeSyncPreparation(updated);
      return updated;
    });
    return {
      localCommit: localCommit,
      completion: completion
    };
  }

  private async completeUpdateNodeSyncPreparation(updated: BookmarkNode | undefined): Promise<void> {
    if (updated !== undefined) {
      await this.markBookmarkSyncPending(updated.updatedAt);
    }
  }

  async deleteNode(id: string): Promise<boolean> {
    if (isBookmarkRootNodeId(id)) {
      return Promise.reject(new Error('系统根节点不可删除。'));
    }
    return (await this.deleteNodes([id])) > 0;
  }

  async deleteNodes(ids: string[]): Promise<number> {
    if (ids.some((id: string) => isBookmarkRootNodeId(id))) {
      throw new Error('系统根节点不可删除。');
    }
    const deletedCount = await this.repository.deleteNodes(ids);
    if (deletedCount > 0) {
      await this.markBookmarkSyncPending(Date.now());
    }
    return deletedCount;
  }

  async deleteBookmarksByUrls(urls: string[]): Promise<number> {
    await this.repository.initialize();
    const deletingIds: string[] = [];
    const seenIds = new Set<string>();
    urls.forEach((url: string) => {
      const bookmark = this.findBookmarkByUrl(url);
      if (bookmark === undefined || seenIds.has(bookmark.id)) {
        return;
      }
      deletingIds.push(bookmark.id);
      seenIds.add(bookmark.id);
    });
    if (deletingIds.length === 0) {
      return 0;
    }
    return this.deleteNodes(deletingIds);
  }

  async moveNodeWithinParent(nodeId: string, direction: 'up' | 'down'): Promise<BookmarkNode | undefined> {
    const node = this.repository.findNodeById(nodeId);
    if (node === undefined || isBookmarkRootNodeId(node.id)) {
      return node;
    }
    const siblings = this.repository.listChildren(node.parentId);
    const currentIndex = siblings.findIndex((item: BookmarkNode) => item.id === node.id);
    if (currentIndex < 0) {
      return node;
    }
    const offset = direction === 'up' ? -1 : 1;
    const targetIndex = currentIndex + offset;
    if (targetIndex < 0 || targetIndex >= siblings.length) {
      return node;
    }
    const reorderedIds = siblings.map((item: BookmarkNode) => item.id);
    const currentId = reorderedIds[currentIndex];
    reorderedIds[currentIndex] = reorderedIds[targetIndex];
    reorderedIds[targetIndex] = currentId;
    await this.repository.reorderChildren({
      parentId: node.parentId,
      childIds: reorderedIds
    });
    await this.markBookmarkSyncPending(Date.now());
    return this.repository.findNodeById(nodeId);
  }

  async moveNodeToRoot(nodeId: string, role: BookmarkRootRole = 'other'): Promise<BookmarkNode | undefined> {
    const node = this.repository.findNodeById(nodeId);
    if (node === undefined || isBookmarkRootNodeId(node.id)) {
      return node;
    }
    const root = this.repository.listRoots().find((item) => item.role === role);
    if (root === undefined) {
      throw new Error('未找到目标根节点。');
    }
    const targetSiblings = this.repository.listChildren(root.nodeId).filter((item: BookmarkNode) => item.id !== nodeId);
    const moved = await this.repository.moveSubtree({
      nodeId: nodeId,
      parentId: root.nodeId,
      targetIndex: targetSiblings.length
    });
    if (moved !== undefined) {
      await this.markBookmarkSyncPending(moved.updatedAt);
    }
    return moved;
  }

  async applyImportPlan(
    plan: AiraBookmarkImportPlan,
    scope: BookmarkStorageScope,
    summary: BookmarkImportBatchSummary = {
      sourceType: 'aira_bundle',
      providerId: 'import_export',
      sourceLabel: 'Aira 导入包'
    }
  ): Promise<AiraBookmarkImportApplyResult> {
    await this.repository.initialize();
    const startedAt = Date.now();
    const batchId = this.createImportBatchId(summary.sourceType, startedAt);
    const localFolderIdByImportId = new Map<string, string>();
    const pendingNodes: BookmarkNode[] = [];
    const nextPositionByParent = new Map<string, number>();
    const knownUrls = new Set<string>();
    this.repository.listNodes(scope).forEach((node: BookmarkNode) => {
      if (node.type === 'bookmark' && node.url !== undefined && node.url.length > 0) {
        knownUrls.add(this.normalizeBookmarkUrl(node.url));
      }
    });
    let importedFolderCount = 0;
    let importedBookmarkCount = 0;
    let skippedNodeCount = 0;
    let duplicateCount = 0;
    let fallbackFolderId = '';
    const now = Date.now();

    for (const node of plan.nodes) {
      const systemRootId = node.type === 'folder' && node.parentId === undefined ?
        this.resolveImportedSystemRootId(node.title, scope) : '';
      if (systemRootId.length > 0) {
        localFolderIdByImportId.set(node.id, systemRootId);
        continue;
      }

      const targetParentId = this.resolveImportParentId(
        node.parentId,
        localFolderIdByImportId,
        () => {
          if (fallbackFolderId.length > 0) {
            return fallbackFolderId;
          }
          const otherRootId = this.resolveImportOtherRootId(scope);
          const folder = this.buildPendingImportNode(
            'folder',
            this.buildUniqueFolderTitle(otherRootId, FALLBACK_IMPORT_FOLDER_TITLE, scope),
            otherRootId,
            undefined,
            now,
            nextPositionByParent,
            scope
          );
          pendingNodes.push(folder);
          fallbackFolderId = folder.id;
          return fallbackFolderId;
        }
      );
      if (fallbackFolderId.length === 0 && node.parentId === undefined &&
        !this.isImportSystemRootId(targetParentId, scope)) {
        fallbackFolderId = targetParentId;
      }

      if (node.type === 'folder') {
        const createdFolder = this.buildPendingImportNode(
          'folder',
          node.title,
          targetParentId,
          undefined,
          now,
          nextPositionByParent,
          scope
        );
        pendingNodes.push(createdFolder);
        localFolderIdByImportId.set(node.id, createdFolder.id);
        importedFolderCount += 1;
      } else if (node.url !== undefined) {
        const normalizedUrl = this.normalizeBookmarkUrl(node.url);
        if (knownUrls.has(normalizedUrl)) {
          duplicateCount += 1;
          continue;
        }
        const createdBookmark = this.buildPendingImportNode(
          'bookmark',
          node.title,
          targetParentId,
          node.url,
          now,
          nextPositionByParent,
          scope
        );
        pendingNodes.push(createdBookmark);
        knownUrls.add(normalizedUrl);
        importedBookmarkCount += 1;
      } else {
        skippedNodeCount += 1;
      }
    }

    if (pendingNodes.length > 0) {
      await this.repository.upsertImportedSyncNodes(pendingNodes);
      await this.markBookmarkSyncPending(now);
    }

    const result: AiraBookmarkImportApplyResult = {
      batchId: batchId,
      importedFolderCount: importedFolderCount,
      importedBookmarkCount: importedBookmarkCount,
      skippedNodeCount: skippedNodeCount,
      duplicateCount: duplicateCount,
      summary: this.buildImportSummary(importedFolderCount, importedBookmarkCount, duplicateCount, skippedNodeCount)
    };
    await this.recordImportBatch({
      batchId: batchId,
      sourceType: summary.sourceType,
      providerId: summary.providerId,
      sourceLabel: summary.sourceLabel,
      sourceRef: summary.sourceRef,
      createdAt: startedAt,
      completedAt: Date.now(),
      importedFolderCount: importedFolderCount,
      importedBookmarkCount: importedBookmarkCount,
      skippedNodeCount: skippedNodeCount,
      duplicateCount: duplicateCount,
      rootNodeId: fallbackFolderId.length > 0 ? fallbackFolderId : undefined
    });
    return result;
  }

  private findBookmarkByUrl(url: string, scope: BookmarkStorageScope = 'regular'): BookmarkNode | undefined {
    return this.repository.findBookmarkByUrl(url, scope);
  }

  private normalizeParentId(parentId?: string): string | undefined {
    if (parentId === undefined || parentId.length === 0) {
      return undefined;
    }
    const parent = this.repository.findNodeById(parentId);
    if (parent !== undefined && parent.type === 'folder') {
      return parent.id;
    }
    return undefined;
  }

  private resolveNextPosition(parentId?: string): number {
    const siblings = this.repository.listChildren(parentId);
    if (siblings.length === 0) {
      return 0;
    }
    return siblings[siblings.length - 1].position + 1;
  }

  private normalizeBookmarkUrl(url: string): string {
    const trimmed = url.trim();
    if (trimmed.length === 0) {
      return 'about:blank';
    }
    if (trimmed.indexOf('://') >= 0 || trimmed.startsWith('about:')) {
      return trimmed;
    }
    return `https://${trimmed}`;
  }

  private resolveImportParentId(
    importParentId: string | undefined,
    localIdByImportId: Map<string, string>,
    resolveFallbackFolderId: () => string
  ): string {
    if (importParentId === undefined) {
      return resolveFallbackFolderId();
    }
    const localParentId = localIdByImportId.get(importParentId) ?? '';
    if (localParentId.length > 0) {
      return localParentId;
    }
    return resolveFallbackFolderId();
  }

  private resolveImportedSystemRootId(title: string, scope: BookmarkStorageScope): string {
    const normalizedTitle = this.normalizeImportedRootTitle(title);
    if (this.matchesImportedRootTitle(normalizedTitle, [
      '书签栏',
      '隐私书签栏',
      '收藏夹栏',
      '收藏栏',
      '个人收藏栏',
      'bookmarksbar',
      'bookmarkbar',
      'bookmarkstoolbar',
      'favoritesbar',
      'favouritesbar'
    ])) {
      return scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
    }
    if (this.matchesImportedRootTitle(normalizedTitle, [
      '其他书签',
      '其他隐私书签',
      '其他收藏',
      '其他收藏夹',
      '未分类书签',
      'otherbookmarks',
      'otherfavorites',
      'unsortedbookmarks'
    ])) {
      return this.resolveImportOtherRootId(scope);
    }
    if (this.matchesImportedRootTitle(normalizedTitle, [
      '移动设备',
      '移动书签',
      '移动收藏',
      'mobilebookmarks',
      'mobilefavorites'
    ])) {
      return this.resolveImportOtherRootId(scope);
    }
    return '';
  }

  private normalizeImportedRootTitle(title: string): string {
    return title.trim().toLowerCase().replace(/\s+/g, '');
  }

  private matchesImportedRootTitle(normalizedTitle: string, aliases: string[]): boolean {
    return aliases.indexOf(normalizedTitle) >= 0;
  }

  private createImportBatchId(sourceType: string, timestamp: number): string {
    return `bookmark-import-${sourceType}-${timestamp}`;
  }

  private buildUniqueFolderTitle(parentId: string, baseTitle: string, scope: BookmarkStorageScope): string {
    const children = this.repository.listChildren(parentId, scope);
    let index = 1;
    let title = baseTitle;
    while (children.find((node: BookmarkNode) => node.type === 'folder' && node.title === title) !== undefined) {
      index += 1;
      title = `${baseTitle} ${index}`;
    }
    return title;
  }

  private buildPendingImportNode(
    type: 'folder' | 'bookmark',
    title: string,
    parentId: string | undefined,
    url: string | undefined,
    now: number,
    nextPositionByParent: Map<string, number>,
    scope: BookmarkStorageScope
  ): BookmarkNode {
    return buildLocalBookmarkNode(
      createLocalBookmarkId(type, scope),
      type,
      title.trim().length > 0 ? title.trim() : (type === 'folder' ? '新文件夹' : '新书签'),
      parentId,
      this.resolveNextImportPosition(parentId, nextPositionByParent, scope),
      now,
      type === 'bookmark' ? url : undefined,
      scope
    );
  }

  private resolveNextImportPosition(
    parentId: string | undefined,
    nextPositionByParent: Map<string, number>,
    scope: BookmarkStorageScope
  ): number {
    const key = parentId ?? '__root__';
    let nextPosition = nextPositionByParent.get(key);
    if (nextPosition === undefined) {
      const children = this.repository.listChildren(parentId, scope);
      nextPosition = children.length === 0 ? 0 : children[children.length - 1].position + 1;
    }
    nextPositionByParent.set(key, nextPosition + 1);
    return nextPosition;
  }

  private resolveImportOtherRootId(scope: BookmarkStorageScope): string {
    return scope === 'private' ? PRIVATE_BOOKMARK_OTHER_ROOT_ID : BOOKMARK_OTHER_ROOT_ID;
  }

  private isImportSystemRootId(id: string, scope: BookmarkStorageScope): boolean {
    const toolbarRootId = scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
    return id === toolbarRootId || id === this.resolveImportOtherRootId(scope);
  }

  private buildImportSummary(
    importedFolderCount: number,
    importedBookmarkCount: number,
    duplicateCount: number,
    skippedNodeCount: number
  ): string {
    const segments: string[] = [
      `新增 ${importedFolderCount} 个文件夹`,
      `新增 ${importedBookmarkCount} 个书签`
    ];
    if (duplicateCount > 0) {
      segments.push(`跳过 ${duplicateCount} 个重复书签`);
    }
    if (skippedNodeCount > 0) {
      segments.push(`跳过 ${skippedNodeCount} 个无效节点`);
    }
    return `导入完成，${segments.join('，')}。`;
  }

  private async recordImportBatch(batch: BookmarkImportBatchRecord): Promise<void> {
    if (this.database === undefined) {
      return;
    }
    await this.database.upsertBookmarkImportBatch(batch);
  }

  private resolveDatabaseFromRepository(repository: BookmarkRepository): BrowserDatabase | undefined {
    if (repository.getDatabase === undefined) {
      return undefined;
    }
    return repository.getDatabase();
  }

  private async markBookmarkSyncPending(changedAt: number): Promise<void> {
    if (this.markSyncPending === undefined) {
      return;
    }
    await this.markSyncPending(changedAt > 0 ? changedAt : Date.now());
  }
}
