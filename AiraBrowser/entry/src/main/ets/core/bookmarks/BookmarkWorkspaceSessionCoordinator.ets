import {
  BookmarkNode,
  BookmarkStorageScope
} from '../../common/models/BrowserModels';
import { isBookmarkRootNodeId } from '../../data/repositories/BookmarkRepositoryCore';
import {
  BookmarkManagementBoundary,
  BookmarkManagementFeature
} from '../../features/bookmarks/BookmarkManagementFeature';
import {
  BookmarkNativeTabRouteState,
  browserNativeTabSceneService
} from '../browser/BrowserNativeTabSceneService';

export interface BookmarkWorkspaceFolderRow {
  id: string;
  title: string;
  depth: number;
  bookmarkCount: number;
  root: boolean;
  hasChildren: boolean;
  expanded: boolean;
}

export type BookmarkWorkspaceSelectionMode = 'replace' | 'toggle' | 'range';

export interface BookmarkWorkspaceSnapshot {
  revision: number;
  scope: BookmarkStorageScope;
  loading: boolean;
  busy: boolean;
  query: string;
  routeUrl: string;
  currentFolderId: string;
  currentFolderTitle: string;
  selectedNodeId: string;
  selectedNodeIds: string[];
  selectionAnchorId: string;
  expandedFolderIds: string[];
  folders: BookmarkWorkspaceFolderRow[];
  rows: BookmarkNode[];
  message: string;
}

export function createEmptyBookmarkWorkspaceSnapshot(): BookmarkWorkspaceSnapshot {
  return {
    revision: 0,
    scope: 'regular',
    loading: true,
    busy: false,
    query: '',
    routeUrl: '',
    currentFolderId: '',
    currentFolderTitle: '书签',
    selectedNodeId: '',
    selectedNodeIds: [],
    selectionAnchorId: '',
    expandedFolderIds: [],
    folders: [],
    rows: [],
    message: ''
  };
}

/** Owns one native bookmark tab's location, tree, search, selection, and mutations. */
export class BookmarkWorkspaceSessionCoordinator {
  private readonly bookmarkManagementFeature: BookmarkManagementFeature;
  private readonly managementBoundary: BookmarkManagementBoundary;
  private snapshotState: BookmarkWorkspaceSnapshot = createEmptyBookmarkWorkspaceSnapshot();
  private expandedFolderIds: Set<string> = new Set<string>();
  private initialized: boolean = false;

  constructor(
    bookmarkManagementFeature: BookmarkManagementFeature,
    managementBoundary: BookmarkManagementBoundary
  ) {
    this.bookmarkManagementFeature = bookmarkManagementFeature;
    this.managementBoundary = managementBoundary;
  }

  getSnapshot(): BookmarkWorkspaceSnapshot {
    return {
      revision: this.snapshotState.revision,
      scope: this.snapshotState.scope,
      loading: this.snapshotState.loading,
      busy: this.snapshotState.busy,
      query: this.snapshotState.query,
      routeUrl: this.snapshotState.routeUrl,
      currentFolderId: this.snapshotState.currentFolderId,
      currentFolderTitle: this.snapshotState.currentFolderTitle,
      selectedNodeId: this.snapshotState.selectedNodeId,
      selectedNodeIds: this.snapshotState.selectedNodeIds.slice(),
      selectionAnchorId: this.snapshotState.selectionAnchorId,
      expandedFolderIds: this.snapshotState.expandedFolderIds.slice(),
      folders: this.snapshotState.folders.slice(),
      rows: this.snapshotState.rows.slice(),
      message: this.snapshotState.message
    };
  }

  async initialize(scope: BookmarkStorageScope, routeUrl: string = ''): Promise<BookmarkWorkspaceSnapshot> {
    this.snapshotState = createEmptyBookmarkWorkspaceSnapshot();
    this.expandedFolderIds.clear();
    this.bookmarkManagementFeature.configure(this.managementBoundary, scope);
    this.snapshotState.scope = scope;
    this.snapshotState.loading = true;
    this.publish();
    try {
      await this.bookmarkManagementFeature.refresh();
      this.initializeExpandedRoots();
      this.applyRouteState(this.parseAuthorizedRoute(routeUrl, scope));
      this.snapshotState.message = '';
      this.rebuildPresentation();
    } catch (error) {
      this.snapshotState.message = `加载书签失败：${this.stringifyError(error as Error)}`;
    }
    this.snapshotState.loading = false;
    this.initialized = true;
    this.publish();
    return this.getSnapshot();
  }

  async activate(scope: BookmarkStorageScope, routeUrl: string = ''): Promise<BookmarkWorkspaceSnapshot> {
    if (!this.initialized || this.snapshotState.scope !== scope) {
      return this.initialize(scope, routeUrl);
    }
    const normalizedRoute = routeUrl.trim();
    if (normalizedRoute.length > 0 && normalizedRoute !== this.snapshotState.routeUrl) {
      this.applyRoute(normalizedRoute);
    }
    return this.refresh();
  }

  async refresh(): Promise<BookmarkWorkspaceSnapshot> {
    if (this.snapshotState.loading || this.snapshotState.busy) {
      return this.getSnapshot();
    }
    this.snapshotState.busy = true;
    this.publish();
    try {
      await this.bookmarkManagementFeature.refresh();
      this.snapshotState.message = '';
      this.rebuildPresentation();
    } catch (error) {
      this.snapshotState.message = `刷新书签失败：${this.stringifyError(error as Error)}`;
    }
    this.snapshotState.busy = false;
    this.publish();
    return this.getSnapshot();
  }

  applyRoute(routeUrl: string): BookmarkWorkspaceSnapshot {
    if (this.snapshotState.loading || routeUrl.trim().length <= 0 ||
      routeUrl === this.snapshotState.routeUrl) {
      return this.getSnapshot();
    }
    this.applyRouteState(this.parseAuthorizedRoute(routeUrl, this.snapshotState.scope));
    this.rebuildPresentation();
    this.publish();
    return this.getSnapshot();
  }

  setQuery(query: string): BookmarkWorkspaceSnapshot {
    this.snapshotState.query = query;
    this.clearSelection();
    this.rebuildRows();
    this.refreshRouteUrl();
    this.publish();
    return this.getSnapshot();
  }

  selectFolder(folderId: string): BookmarkWorkspaceSnapshot {
    const node = this.bookmarkManagementFeature.findNodeById(folderId);
    if (node === undefined || node.type !== 'folder') {
      return this.getSnapshot();
    }
    this.snapshotState.currentFolderId = node.id;
    this.snapshotState.currentFolderTitle = node.title;
    this.snapshotState.query = '';
    this.clearSelection();
    this.expandToFolder(node.id);
    this.rebuildPresentation();
    this.refreshRouteUrl();
    this.publish();
    return this.getSnapshot();
  }

  toggleFolder(folderId: string): BookmarkWorkspaceSnapshot {
    const node = this.bookmarkManagementFeature.findNodeById(folderId);
    if (node === undefined || node.type !== 'folder' || !this.hasChildFolders(node.id)) {
      return this.getSnapshot();
    }
    if (this.expandedFolderIds.has(node.id)) {
      this.expandedFolderIds.delete(node.id);
    } else {
      this.expandedFolderIds.add(node.id);
    }
    this.rebuildFolders();
    this.publish();
    return this.getSnapshot();
  }

  selectNode(nodeId: string, mode: BookmarkWorkspaceSelectionMode = 'replace'): BookmarkWorkspaceSnapshot {
    const rowIndex = this.snapshotState.rows.findIndex((row: BookmarkNode): boolean => row.id === nodeId);
    if (rowIndex < 0) {
      return this.getSnapshot();
    }
    if (mode === 'range') {
      this.selectRange(nodeId);
    } else if (mode === 'toggle') {
      this.toggleNodeSelection(nodeId);
    } else {
      this.snapshotState.selectedNodeIds = [nodeId];
      this.snapshotState.selectedNodeId = nodeId;
      this.snapshotState.selectionAnchorId = nodeId;
    }
    this.publish();
    return this.getSnapshot();
  }

  selectAllRows(): BookmarkWorkspaceSnapshot {
    this.snapshotState.selectedNodeIds = this.snapshotState.rows
      .filter((node: BookmarkNode): boolean => !isBookmarkRootNodeId(node.id))
      .map((node: BookmarkNode): string => node.id);
    this.snapshotState.selectedNodeId = this.snapshotState.selectedNodeIds[0] ?? '';
    this.snapshotState.selectionAnchorId = this.snapshotState.selectedNodeId;
    this.publish();
    return this.getSnapshot();
  }

  clearNodeSelection(): BookmarkWorkspaceSnapshot {
    this.clearSelection();
    this.publish();
    return this.getSnapshot();
  }

  findNode(nodeId: string): BookmarkNode | undefined {
    return this.bookmarkManagementFeature.findNodeById(nodeId);
  }

  authorizeNavigation(): void {
    this.bookmarkManagementFeature.authorizeNavigation();
  }

  buildNextFolderTitle(): string {
    const parentId = this.snapshotState.currentFolderId.length > 0
      ? this.snapshotState.currentFolderId
      : undefined;
    return this.bookmarkManagementFeature.buildNextFolderTitle(parentId);
  }

  async createFolder(title: string): Promise<BookmarkWorkspaceSnapshot> {
    const normalizedTitle = title.trim();
    const parentId = this.snapshotState.currentFolderId;
    if (normalizedTitle.length <= 0 || parentId.length <= 0 || this.snapshotState.busy) {
      return this.getSnapshot();
    }
    return this.runMutation('新建文件夹失败', async (): Promise<void> => {
      const created = await this.bookmarkManagementFeature.createNode({
        type: 'folder',
        title: normalizedTitle,
        parentId: parentId,
        scope: this.snapshotState.scope
      });
      if (created !== undefined) {
        this.expandedFolderIds.add(parentId);
      }
    });
  }

  async updateNode(nodeId: string, title: string, url: string): Promise<BookmarkWorkspaceSnapshot> {
    const node = this.bookmarkManagementFeature.findNodeById(nodeId);
    const normalizedTitle = title.trim();
    const normalizedUrl = url.trim();
    if (node === undefined || isBookmarkRootNodeId(node.id) || normalizedTitle.length <= 0 ||
      (node.type === 'bookmark' && normalizedUrl.length <= 0) || this.snapshotState.busy) {
      return this.getSnapshot();
    }
    return this.runMutation('保存失败', async (): Promise<void> => {
      await this.bookmarkManagementFeature.updateNode({
        id: node.id,
        title: normalizedTitle,
        url: node.type === 'bookmark' ? normalizedUrl : node.url
      });
    });
  }

  async deleteNode(nodeId: string): Promise<BookmarkWorkspaceSnapshot> {
    return this.deleteNodes([nodeId]);
  }

  async deleteSelectedNodes(): Promise<BookmarkWorkspaceSnapshot> {
    return this.deleteNodes(this.snapshotState.selectedNodeIds);
  }

  async deleteNodes(nodeIds: string[]): Promise<BookmarkWorkspaceSnapshot> {
    const deletingIds = this.normalizeMovableNodeIds(nodeIds);
    if (deletingIds.length <= 0 || this.snapshotState.busy) {
      return this.getSnapshot();
    }
    return this.runMutation('删除失败', async (): Promise<void> => {
      await this.bookmarkManagementFeature.deleteNodes(deletingIds);
      deletingIds.forEach((id: string): void => {
        this.expandedFolderIds.delete(id);
      });
      this.clearSelection();
    });
  }

  async moveSelectionToFolder(targetFolderId: string, targetIndex: number = 2147483647): Promise<BookmarkWorkspaceSnapshot> {
    const target = this.bookmarkManagementFeature.findNodeById(targetFolderId);
    const movingIds = this.normalizeMovableNodeIds(this.snapshotState.selectedNodeIds);
    if (target === undefined || target.type !== 'folder' || movingIds.length <= 0 ||
      !this.canMoveNodesToFolder(movingIds, target.id) || this.snapshotState.busy) {
      return this.getSnapshot();
    }
    return this.runMutation('移动失败', async (): Promise<void> => {
      await this.bookmarkManagementFeature.moveSubtrees({
        nodeIds: movingIds,
        parentId: target.id,
        targetIndex: Math.max(0, Math.floor(targetIndex))
      });
      this.expandedFolderIds.add(target.id);
      this.clearSelection();
    });
  }

  canMoveSelectionToFolder(targetFolderId: string): boolean {
    return this.canMoveNodesToFolder(this.normalizeMovableNodeIds(this.snapshotState.selectedNodeIds), targetFolderId);
  }

  private async runMutation(
    failureLabel: string,
    operation: () => Promise<void>
  ): Promise<BookmarkWorkspaceSnapshot> {
    this.snapshotState.busy = true;
    this.publish();
    try {
      await operation();
      this.snapshotState.message = '';
      this.rebuildPresentation();
    } catch (error) {
      this.snapshotState.message = `${failureLabel}：${this.stringifyError(error as Error)}`;
    }
    this.snapshotState.busy = false;
    this.publish();
    return this.getSnapshot();
  }

  private rebuildPresentation(): void {
    const currentFolder = this.bookmarkManagementFeature.findNodeById(this.snapshotState.currentFolderId);
    if (currentFolder === undefined || currentFolder.type !== 'folder') {
      this.snapshotState.currentFolderId = this.bookmarkManagementFeature.getPrimaryFolderId() ?? '';
    }
    const resolvedFolder = this.bookmarkManagementFeature.findNodeById(this.snapshotState.currentFolderId);
    this.snapshotState.currentFolderTitle = resolvedFolder?.title ?? '书签';
    this.expandToFolder(this.snapshotState.currentFolderId);
    this.rebuildFolders();
    this.rebuildRows();
    this.refreshRouteUrl();
  }

  private rebuildRows(): void {
    const query = this.snapshotState.query.trim();
    this.snapshotState.rows = query.length > 0
      ? this.bookmarkManagementFeature.searchBookmarks(query, 500)
      : this.bookmarkManagementFeature.listDisplayChildren(
        this.snapshotState.currentFolderId.length > 0 ? this.snapshotState.currentFolderId : undefined
      );
    const visibleIds = new Set<string>(this.snapshotState.rows.map((node: BookmarkNode): string => node.id));
    this.snapshotState.selectedNodeIds = this.snapshotState.selectedNodeIds.filter((id: string): boolean =>
      visibleIds.has(id));
    this.snapshotState.selectedNodeId = this.snapshotState.selectedNodeIds[0] ?? '';
    if (!visibleIds.has(this.snapshotState.selectionAnchorId)) {
      this.snapshotState.selectionAnchorId = this.snapshotState.selectedNodeId;
    }
  }

  private rebuildFolders(): void {
    const result: BookmarkWorkspaceFolderRow[] = [];
    const visited: Set<string> = new Set<string>();
    const counts = this.bookmarkManagementFeature.buildFolderBookmarkCounts().counts;
    this.appendFolderRows(result, undefined, 0, visited, counts);
    this.snapshotState.folders = result;
    this.snapshotState.expandedFolderIds = Array.from(this.expandedFolderIds.values());
  }

  private appendFolderRows(
    result: BookmarkWorkspaceFolderRow[],
    parentId: string | undefined,
    depth: number,
    visited: Set<string>,
    counts: Map<string, number>
  ): void {
    this.bookmarkManagementFeature.listDisplayChildren(parentId).forEach((node: BookmarkNode): void => {
      if (node.type !== 'folder' || visited.has(node.id)) {
        return;
      }
      visited.add(node.id);
      const hasChildren = this.hasChildFolders(node.id);
      const expanded = this.expandedFolderIds.has(node.id);
      result.push({
        id: node.id,
        title: node.title,
        depth: depth,
        bookmarkCount: counts.get(node.id) ?? 0,
        root: isBookmarkRootNodeId(node.id),
        hasChildren: hasChildren,
        expanded: expanded
      });
      if (expanded && hasChildren) {
        this.appendFolderRows(result, node.id, depth + 1, visited, counts);
      }
    });
  }

  private initializeExpandedRoots(): void {
    this.bookmarkManagementFeature.listDisplayChildren(undefined).forEach((node: BookmarkNode): void => {
      if (node.type === 'folder') {
        this.expandedFolderIds.add(node.id);
      }
    });
  }

  private expandToFolder(folderId: string): void {
    let currentId = folderId;
    const visited: Set<string> = new Set<string>();
    while (currentId.length > 0 && !visited.has(currentId)) {
      visited.add(currentId);
      this.expandedFolderIds.add(currentId);
      const node = this.bookmarkManagementFeature.findNodeById(currentId);
      currentId = node?.parentId ?? '';
    }
  }

  private hasChildFolders(folderId: string): boolean {
    return this.bookmarkManagementFeature.listDisplayChildren(folderId)
      .some((node: BookmarkNode): boolean => node.type === 'folder');
  }

  private toggleNodeSelection(nodeId: string): void {
    const selected = new Set<string>(this.snapshotState.selectedNodeIds);
    if (selected.has(nodeId)) {
      selected.delete(nodeId);
    } else if (!isBookmarkRootNodeId(nodeId)) {
      selected.add(nodeId);
    }
    this.snapshotState.selectedNodeIds = Array.from(selected.values());
    this.snapshotState.selectedNodeId = this.snapshotState.selectedNodeIds[0] ?? '';
    this.snapshotState.selectionAnchorId = nodeId;
  }

  private selectRange(nodeId: string): void {
    const anchorId = this.snapshotState.selectionAnchorId;
    const anchorIndex = this.snapshotState.rows.findIndex((row: BookmarkNode): boolean => row.id === anchorId);
    const targetIndex = this.snapshotState.rows.findIndex((row: BookmarkNode): boolean => row.id === nodeId);
    if (anchorIndex < 0 || targetIndex < 0) {
      this.snapshotState.selectedNodeIds = [nodeId];
      this.snapshotState.selectedNodeId = nodeId;
      this.snapshotState.selectionAnchorId = nodeId;
      return;
    }
    const startIndex = Math.min(anchorIndex, targetIndex);
    const endIndex = Math.max(anchorIndex, targetIndex);
    this.snapshotState.selectedNodeIds = this.snapshotState.rows.slice(startIndex, endIndex + 1)
      .filter((node: BookmarkNode): boolean => !isBookmarkRootNodeId(node.id))
      .map((node: BookmarkNode): string => node.id);
    this.snapshotState.selectedNodeId = nodeId;
  }

  private clearSelection(): void {
    this.snapshotState.selectedNodeId = '';
    this.snapshotState.selectedNodeIds = [];
    this.snapshotState.selectionAnchorId = '';
  }

  private normalizeMovableNodeIds(nodeIds: string[]): string[] {
    const result: string[] = [];
    const seen: Set<string> = new Set<string>();
    nodeIds.forEach((id: string): void => {
      if (id.length <= 0 || isBookmarkRootNodeId(id) || seen.has(id) ||
        this.bookmarkManagementFeature.findNodeById(id) === undefined) {
        return;
      }
      seen.add(id);
      result.push(id);
    });
    return result;
  }

  private canMoveNodesToFolder(nodeIds: string[], targetFolderId: string): boolean {
    if (nodeIds.length <= 0 || targetFolderId.length <= 0 || nodeIds.includes(targetFolderId)) {
      return false;
    }
    const target = this.bookmarkManagementFeature.findNodeById(targetFolderId);
    if (target === undefined || target.type !== 'folder') {
      return false;
    }
    return !nodeIds.some((nodeId: string): boolean => {
      const node = this.bookmarkManagementFeature.findNodeById(nodeId);
      if (node?.type !== 'folder') {
        return false;
      }
      return this.bookmarkManagementFeature.listSubtree(node.id)
        .some((descendant: BookmarkNode): boolean => descendant.id === targetFolderId);
    });
  }

  private parseAuthorizedRoute(routeUrl: string, scope: BookmarkStorageScope): BookmarkNativeTabRouteState {
    const parsed = browserNativeTabSceneService.parseBookmarkRoute(routeUrl, scope);
    return {
      folderId: parsed.folderId,
      query: parsed.query,
      scope: scope
    };
  }

  private applyRouteState(route: BookmarkNativeTabRouteState): void {
    const folder = this.bookmarkManagementFeature.findNodeById(route.folderId);
    this.snapshotState.currentFolderId = folder?.type === 'folder'
      ? folder.id
      : (this.bookmarkManagementFeature.getPrimaryFolderId() ?? '');
    this.snapshotState.query = route.query;
    this.clearSelection();
    this.expandToFolder(this.snapshotState.currentFolderId);
  }

  private refreshRouteUrl(): void {
    this.snapshotState.routeUrl = browserNativeTabSceneService.buildBookmarkRoute({
      folderId: this.snapshotState.currentFolderId,
      query: this.snapshotState.query,
      scope: this.snapshotState.scope
    });
  }

  private publish(): void {
    this.snapshotState.revision += 1;
  }

  private stringifyError(error: Error): string {
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
