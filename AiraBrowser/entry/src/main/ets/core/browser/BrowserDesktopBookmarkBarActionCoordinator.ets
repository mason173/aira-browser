import {
  BookmarkNode,
  BookmarkStorageScope,
  DesktopBookmarkBarVisibility
} from '../../common/models/BrowserModels';
import {
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID,
  isBookmarkRootNodeId,
  resolveBookmarkScope,
  sanitizeBookmarkTitle
} from '../../data/repositories/BookmarkRepositoryCore';
import { BookmarkRepository } from '../../data/repositories/BrowserRepositories';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BookmarkMutationService } from '../../services/bookmarks/BookmarkMutationService';
import { BookmarkTreeQueryService } from '../../services/bookmarks/BookmarkTreeQueryService';
import { BrowserClipboardCopyTextRequest } from '../../services/share/BrowserClipboardService';
import { DesktopBookmarkClipboardSignal } from '../bookmarks/DesktopBookmarkClipboardSignal';
import {
  BookmarkFolderOptionView,
  BookmarkFolderSelectionViewModel
} from './BookmarkFolderSelectionViewModel';
import { BrowserConfirmationRequest } from './BrowserConfirmationSink';
import {
  BrowserDesktopBookmarkBarNodeActionKind,
  BrowserDesktopBookmarkBarReorderAction,
  BrowserDesktopBookmarkBarRootActionKind
} from './BrowserDesktopBookmarkBarViewModel';
import { planDesktopBookmarkBarReorder } from './BrowserDesktopBookmarkBarDragCoordinator';
import { setDesktopBookmarkBarVisibility } from './DesktopBookmarkBarVisibility';
import { resolveAppResourceText } from '../resources/AppResourceText';
import { resolveBookmarkNodeDisplayTitle } from '../resources/HistoryBookmarkDisplayText';

export interface BrowserDesktopBookmarkBarActivePage {
  title: string;
  url: string;
}

/** One dialog serves "new folder" (empty nodeId) and "rename" (nodeId set). */
export interface BrowserDesktopBookmarkBarFolderNameRequest {
  nodeId: string;
  parentId: string;
  initialTitle: string;
  dialogTitle: ResourceStr;
  fieldPlaceholder: ResourceStr;
}

export interface BrowserDesktopBookmarkBarBookmarkEditorRequest {
  parentId: string;
  title: string;
  url: string;
  dialogTitle: ResourceStr;
  /** Empty means "add"; a node id switches the dialog to edit that bookmark, offering the folder picker. */
  nodeId: string;
  /** Storage scope of the edited node, used to build the move-target folder list. */
  scope: BookmarkStorageScope;
  /** Move targets for the folder picker; empty hides the picker, which is the "add" presentation. */
  folderOptions: BookmarkFolderOptionView[];
  initialFolderId: string;
}

export interface BrowserDesktopBookmarkBarActionShell {
  /** The page behind the bar, used to prefill "add page". */
  readActivePage: () => BrowserDesktopBookmarkBarActivePage | undefined;
  presentFolderNameDialog: (request: BrowserDesktopBookmarkBarFolderNameRequest) => void;
  presentBookmarkEditor: (request: BrowserDesktopBookmarkBarBookmarkEditorRequest) => void;
  confirmDelete: (request: BrowserConfirmationRequest) => void;
  copyText: (request: BrowserClipboardCopyTextRequest) => void;
  showToast: (message: ResourceStr) => void;
}

export interface BrowserDesktopBookmarkBarActionCoordinatorOptions {
  repository: BookmarkRepository;
  preferencesRepository: PreferencesRepository;
}

interface BrowserDesktopBookmarkBarClipboardEntry {
  mode: 'copy' | 'cut';
  nodeIds: string[];
}

/**
 * Executes Large-Screen bookmark bar context-menu commands.
 *
 * Ownership: the bar surface only dispatches ids, this coordinator owns bookmark mutations and the
 * in-app cut/copy clipboard, and the page owns dialog presentation through its shell.
 */
export class BrowserDesktopBookmarkBarActionCoordinator {
  private readonly options: BrowserDesktopBookmarkBarActionCoordinatorOptions;
  private readonly mutationService: BookmarkMutationService;
  private readonly shell: BrowserDesktopBookmarkBarActionShell;
  private readonly folderSelectionViewModel: BookmarkFolderSelectionViewModel = new BookmarkFolderSelectionViewModel();
  private clipboard?: BrowserDesktopBookmarkBarClipboardEntry;
  private reorderQueue: Promise<void> = Promise.resolve();

  constructor(
    options: BrowserDesktopBookmarkBarActionCoordinatorOptions,
    shell: BrowserDesktopBookmarkBarActionShell
  ) {
    this.options = options;
    this.mutationService = new BookmarkMutationService(options.repository);
    this.shell = shell;
  }

  async initialize(): Promise<void> {
    await this.options.repository.initialize();
  }

  handleReorder(action: BrowserDesktopBookmarkBarReorderAction): void {
    // Resolve each drop against the latest committed order, even when a user
    // starts the next drag before the previous database write completes.
    this.reorderQueue = this.reorderQueue.then(async (): Promise<void> => {
      await this.initialize();
      const rootId = this.resolveToolbarRootId(action.scope);
      const siblings = this.options.repository.listChildren(rootId, action.scope)
        .filter((node: BookmarkNode): boolean => {
          return node.parentId === rootId && resolveBookmarkScope(node.scope) === action.scope &&
            node.sync.deletedAt === undefined;
        });
      const childIds = planDesktopBookmarkBarReorder(siblings, action.nodeId, action.anchorId, action.placement);
      if (childIds !== undefined) {
        await this.mutationService.reorderChildren({ parentId: rootId, childIds: childIds });
      }
    }).catch((_error: Error): void => {
      this.shell.showToast($r('app.string.bookmark_bar_save_failed'));
    });
  }

  handleNodeAction(kind: BrowserDesktopBookmarkBarNodeActionKind, node: BookmarkNode): void {    if (kind === 'rename_node') {
      this.requestRename(node);
      return;
    }
    if (kind === 'delete_node') {
      this.requestDelete(node);
      return;
    }
    if (kind === 'add_bookmark') {
      this.requestAddBookmark(node);
      return;
    }
    if (kind === 'add_folder') {
      this.requestAddFolder(node);
      return;
    }
    if (kind === 'paste_node') {
      void this.applyPaste(node);
      return;
    }
    this.writeClipboard(node, kind === 'cut_node' ? 'cut' : 'copy');
  }

  handleSetBarVisibility(visibility: DesktopBookmarkBarVisibility): void {
    void setDesktopBookmarkBarVisibility(this.options.preferencesRepository, visibility).then(
      (): void => {},
      (_error: Error): void => {
        this.shell.showToast($r('app.string.bookmark_bar_save_failed'));
      }
    );
  }

  /**
   * Bar-wide "add" commands from the bar's empty area: they write into that scope's toolbar root,
   * which is what the bar itself renders.
   */
  handleBarRootAddAction(kind: BrowserDesktopBookmarkBarRootActionKind, scope: BookmarkStorageScope): void {
    const rootId = this.resolveToolbarRootId(scope);
    if (kind === 'add_folder_to_bar') {
      this.shell.presentFolderNameDialog({
        nodeId: '',
        parentId: rootId,
        initialTitle: '',
        dialogTitle: $r('app.string.bookmark_new_folder'),
        fieldPlaceholder: $r('app.string.bookmark_folder_name')
      });
      return;
    }
    const page = this.shell.readActivePage();
    this.shell.presentBookmarkEditor({
      parentId: rootId,
      title: page?.title ?? '',
      url: page?.url ?? '',
      dialogTitle: $r('app.string.bookmark_bar_add_to_named', this.resolveToolbarRootTitle(scope)),
      nodeId: '',
      scope: scope,
      folderOptions: [],
      initialFolderId: ''
    });
  }

  /** Confirmed by the folder-name dialog. */
  handleFolderNameSubmitted(request: BrowserDesktopBookmarkBarFolderNameRequest, title: string): void {
    const sanitized = title.trim();
    if (sanitized.length === 0) {
      this.shell.showToast($r('app.string.bookmark_bar_name_required'));
      return;
    }
    void this.applyFolderName(request, sanitized);
  }

  /** Confirmed by the bookmark editor dialog; a node id edits, otherwise it adds. */
  handleBookmarkSubmitted(
    request: BrowserDesktopBookmarkBarBookmarkEditorRequest,
    title: string,
    url: string,
    targetFolderId: string
  ): void {
    const sanitizedUrl = url.trim();
    if (sanitizedUrl.length === 0) {
      this.shell.showToast($r('app.string.bookmark_url_required'));
      return;
    }
    if (request.nodeId.length > 0) {
      if (title.trim().length === 0) {
        this.shell.showToast($r('app.string.bookmark_bar_name_required'));
        return;
      }
      void this.applyBookmarkEdit(request, title.trim(), sanitizedUrl, targetFolderId);
      return;
    }
    void this.applyBookmark(request, title, sanitizedUrl);
  }

  private async applyFolderName(
    request: BrowserDesktopBookmarkBarFolderNameRequest,
    title: string
  ): Promise<void> {
    try {
      if (request.nodeId.length > 0) {
        const updated = await this.mutationService.updateNode({ id: request.nodeId, title: title });
        this.shell.showToast(updated === undefined ? $r('app.string.bookmark_bar_missing') : $r('app.string.bookmark_bar_renamed'));
        return;
      }
      const scope = this.resolveScopeForParentId(request.parentId);
      await this.mutationService.createNode({
        type: 'folder',
        title: title,
        parentId: this.resolveWritableParentId(request.parentId, scope),
        scope: scope
      });
      this.shell.showToast($r('app.string.bookmark_bar_folder_created'));
    } catch (_error) {
      this.shell.showToast($r('app.string.bookmark_bar_folder_save_failed'));
    }
  }

  private async applyBookmark(
    request: BrowserDesktopBookmarkBarBookmarkEditorRequest,
    title: string,
    url: string
  ): Promise<void> {
    const scope = this.resolveScopeForParentId(request.parentId);
    try {
      await this.mutationService.createBookmarkIfMissing({
        type: 'bookmark',
        title: sanitizeBookmarkTitle(title, url),
        url: url,
        parentId: this.resolveWritableParentId(request.parentId, scope),
        scope: scope
      });
      this.shell.showToast($r('app.string.bookmark_bar_page_added'));
    } catch (_error) {
      this.shell.showToast($r('app.string.bookmark_bar_page_add_failed'));
    }
  }

  /** The edit path rewrites title and url, then moves the bookmark when the picked folder differs. */
  private async applyBookmarkEdit(
    request: BrowserDesktopBookmarkBarBookmarkEditorRequest,
    title: string,
    url: string,
    targetFolderId: string
  ): Promise<void> {
    try {
      const updated = await this.mutationService.updateNode({
        id: request.nodeId,
        title: title,
        url: url
      });
      if (updated === undefined) {
        this.shell.showToast($r('app.string.bookmark_bar_missing'));
        return;
      }
      await this.moveEditedBookmarkIfNeeded(updated, targetFolderId.trim());
      this.shell.showToast($r('app.string.bookmark_bar_bookmark_updated'));
    } catch (_error) {
      this.shell.showToast($r('app.string.bookmark_bar_bookmark_update_failed'));
    }
  }

  private async moveEditedBookmarkIfNeeded(node: BookmarkNode, targetFolderId: string): Promise<void> {
    if (targetFolderId.length <= 0 || targetFolderId === (node.parentId ?? '').trim()) {
      return;
    }
    const scope = this.resolveNodeScope(node);
    const parentId = this.resolveWritableParentId(targetFolderId, scope);
    if (parentId === (node.parentId ?? '').trim()) {
      return;
    }
    const targetIndex = this.options.repository.listChildren(parentId, scope).length;
    await this.mutationService.moveSubtree({
      nodeId: node.id,
      parentId: parentId,
      targetIndex: targetIndex
    });
  }

  /** Folders rename in place; a bookmark opens the full editor so name, url, and folder change together. */
  private requestRename(node: BookmarkNode): void {
    if (isBookmarkRootNodeId(node.id)) {
      return;
    }
    if (node.type === 'bookmark') {
      const scope = this.resolveNodeScope(node);
      const folderOptions = this.buildEditorFolderOptions(scope, node.id);
      this.shell.presentBookmarkEditor({
        parentId: node.parentId ?? '',
        title: node.title,
        url: node.url ?? '',
        dialogTitle: $r('app.string.bookmark_edit_bookmark'),
        nodeId: node.id,
        scope: scope,
        folderOptions: folderOptions,
        initialFolderId: this.resolveEditorInitialFolderId(node.parentId ?? '', scope, folderOptions)
      });
      return;
    }
    this.shell.presentFolderNameDialog({
      nodeId: node.id,
      parentId: node.parentId ?? '',
      initialTitle: node.title,
      dialogTitle: $r('app.string.bookmark_bar_rename_title'),
      fieldPlaceholder: $r('app.string.ui_name')
    });
  }

  /** The edited bookmark may not move into itself, so it is excluded from the move targets. */
  private buildEditorFolderOptions(scope: BookmarkStorageScope, nodeId: string): BookmarkFolderOptionView[] {
    const nodes = this.options.repository.getSnapshot(false, scope).nodes;
    const folderCounts = new BookmarkTreeQueryService(this.options.repository, scope).buildFolderBookmarkCounts();
    return this.folderSelectionViewModel.buildMoveTargetOptionsFromData(nodes, [nodeId], folderCounts);
  }

  private resolveEditorInitialFolderId(
    parentId: string,
    scope: BookmarkStorageScope,
    options: BookmarkFolderOptionView[]
  ): string {
    const normalized = parentId.trim();
    if (this.containsFolderOption(options, normalized)) {
      return normalized;
    }
    const toolbarRootId = scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
    if (this.containsFolderOption(options, toolbarRootId)) {
      return toolbarRootId;
    }
    return options.length > 0 ? options[0].id : '';
  }

  private containsFolderOption(options: BookmarkFolderOptionView[], folderId: string): boolean {
    return options.some((option: BookmarkFolderOptionView): boolean => option.id === folderId);
  }

  private requestDelete(node: BookmarkNode): void {
    if (isBookmarkRootNodeId(node.id)) {
      return;
    }
    const scope = this.resolveNodeScope(node);
    const containedCount = node.type === 'folder' ? this.collectBookmarkUrls(node.id, scope).length : 0;
    this.shell.confirmDelete({
      title: node.type === 'folder' ? $r('app.string.bookmark_delete_folder') : $r('app.string.bookmark_delete_bookmark'),
      message: this.buildDeleteMessage(node, containedCount),
      cancelLabel: $r('app.string.settings_account_cancel'),
      confirmLabel: $r('app.string.settings_delete'),
      confirmTone: 'alert',
      onConfirm: (): void => {
        void this.applyDelete(node.id);
      }
    });
  }

  private buildDeleteMessage(node: BookmarkNode, containedCount: number): ResourceStr {
    if (node.type !== 'folder') {
      return $r('app.string.bookmark_bar_delete_one', node.title);
    }
    if (containedCount > 0) {
      return $r('app.string.bookmark_bar_delete_folder_count', node.title, containedCount);
    }
    return $r('app.string.bookmark_bar_delete_folder', node.title);
  }

  private async applyDelete(nodeId: string): Promise<void> {
    try {
      const deleted = await this.mutationService.deleteNode(nodeId);
      this.shell.showToast(deleted ? $r('app.string.bookmark_bar_deleted') : $r('app.string.bookmark_bar_missing'));
    } catch (_error) {
      this.shell.showToast($r('app.string.bookmark_bar_delete_failed'));
    }
  }

  private requestAddFolder(node: BookmarkNode): void {
    const parentId = this.resolveAddParentId(node);
    this.shell.presentFolderNameDialog({
      nodeId: '',
      parentId: parentId,
      initialTitle: '',
      dialogTitle: $r('app.string.bookmark_new_folder'),
      fieldPlaceholder: $r('app.string.bookmark_folder_name')
    });
  }

  private requestAddBookmark(node: BookmarkNode): void {
    const parentId = this.resolveAddParentId(node);
    const page = this.shell.readActivePage();
    this.shell.presentBookmarkEditor({
      parentId: parentId,
      title: page?.title ?? '',
      url: page?.url ?? '',
      dialogTitle: $r('app.string.bookmark_bar_add_to_named', this.resolveParentTitle(node, parentId)),
      nodeId: '',
      scope: this.resolveScopeForParentId(parentId),
      folderOptions: [],
      initialFolderId: ''
    });
  }

  private writeClipboard(node: BookmarkNode, mode: 'copy' | 'cut'): void {
    const scope = this.resolveNodeScope(node);
    const urls = this.collectBookmarkUrls(node.id, scope);
    this.clipboard = { mode: mode, nodeIds: [node.id] };
    DesktopBookmarkClipboardSignal.publish(true);
    if (mode === 'cut') {
      this.shell.showToast($r('app.string.bookmark_bar_cut_ready'));
      return;
    }
    this.shell.copyText({
      value: urls.join('\n'),
      emptyMessage: node.type === 'folder' ? $r('app.string.bookmark_bar_folder_no_url') : $r('app.string.bookmark_bar_no_url'),
      successMessage: urls.length > 1 ? $r('app.string.bookmark_bar_copied_many', urls.length) : $r('app.string.bookmark_bar_copied')
    });
  }

  private async applyPaste(node: BookmarkNode): Promise<void> {
    const entry = this.clipboard;
    if (entry === undefined) {
      this.shell.showToast($r('app.string.bookmark_bar_clipboard_empty'));
      return;
    }
    const scope = this.resolveNodeScope(node);
    const targetParentId = this.resolvePasteParentId(node, scope);
    for (let index = 0; index < entry.nodeIds.length; index += 1) {
      const sourceId = entry.nodeIds[index];
      if (sourceId === targetParentId || this.isDescendantOf(targetParentId, sourceId)) {
        this.shell.showToast($r('app.string.bookmark_bar_paste_self'));
        return;
      }
    }
    try {
      await this.options.repository.initialize();
      const pasted = entry.mode === 'cut'
        ? await this.moveClipboardNodes(entry.nodeIds, targetParentId, scope)
        : await this.copyClipboardNodes(entry.nodeIds, targetParentId, scope);
      this.clearClipboard();
      this.shell.showToast(entry.mode === 'cut' ? $r('app.string.bookmark_bar_moved') : $r('app.string.bookmark_bar_pasted', pasted));
    } catch (_error) {
      this.shell.showToast($r('app.string.bookmark_bar_paste_failed'));
    }
  }

  private async moveClipboardNodes(
    nodeIds: string[],
    targetParentId: string,
    scope: BookmarkStorageScope
  ): Promise<number> {
    let moved = 0;
    for (let index = 0; index < nodeIds.length; index += 1) {
      const targetIndex = this.options.repository.listChildren(targetParentId, scope).length;
      const result = await this.mutationService.moveSubtree({
        nodeId: nodeIds[index],
        parentId: targetParentId,
        targetIndex: targetIndex
      });
      if (result !== undefined) {
        moved += 1;
      }
    }
    return moved;
  }

  private async copyClipboardNodes(
    nodeIds: string[],
    targetParentId: string,
    scope: BookmarkStorageScope
  ): Promise<number> {
    let copied = 0;
    for (let index = 0; index < nodeIds.length; index += 1) {
      copied += await this.copySubtree(nodeIds[index], targetParentId, scope);
    }
    return copied;
  }

  private async copySubtree(sourceId: string, targetParentId: string, scope: BookmarkStorageScope): Promise<number> {
    const source = this.options.repository.findNodeById(sourceId);
    if (source === undefined) {
      return 0;
    }
    const created = await this.mutationService.createNode({
      type: source.type,
      title: source.title,
      url: source.url,
      parentId: targetParentId,
      scope: scope
    });
    if (source.type !== 'folder') {
      return 1;
    }
    const children = this.options.repository.listChildren(sourceId, scope);
    let copied = 0;
    for (let index = 0; index < children.length; index += 1) {
      copied += await this.copySubtree(children[index].id, created.id, scope);
    }
    return copied;
  }

  private clearClipboard(): void {
    this.clipboard = undefined;
    DesktopBookmarkClipboardSignal.publish(false);
  }

  /** A folder receives new children; a bookmark adds next to its siblings in the parent folder. */
  private resolveAddParentId(node: BookmarkNode): string {
    if (node.type === 'folder') {
      return node.id;
    }
    return this.resolvePasteParentId(node, this.resolveNodeScope(node));
  }

  private resolvePasteParentId(node: BookmarkNode, scope: BookmarkStorageScope): string {
    if (node.type === 'folder') {
      return node.id;
    }
    const parentId = (node.parentId ?? '').trim();
    return parentId.length > 0 ? parentId : this.resolveToolbarRootId(scope);
  }

  private resolveParentTitle(node: BookmarkNode, parentId: string): string {
    if (node.type === 'folder') {
      return resolveAppResourceText(resolveBookmarkNodeDisplayTitle(node.id, node.title));
    }
    const parent = this.options.repository.findNodeById(parentId);
    if (parent === undefined) {
      return resolveAppResourceText($r('app.string.bookmark_root_toolbar'));
    }
    return resolveAppResourceText(resolveBookmarkNodeDisplayTitle(parent.id, parent.title));
  }

  private resolveWritableParentId(parentId: string, scope: BookmarkStorageScope): string {
    const normalized = parentId.trim();
    if (normalized.length === 0) {
      return this.resolveToolbarRootId(scope);
    }
    const parent = this.options.repository.findNodeById(normalized);
    if (parent !== undefined && parent.type === 'folder') {
      return parent.id;
    }
    return this.resolveToolbarRootId(scope);
  }

  private resolveScopeForParentId(parentId: string): BookmarkStorageScope {
    const parent = this.options.repository.findNodeById(parentId.trim());
    return parent?.scope === 'private' ? 'private' : 'regular';
  }

  private resolveNodeScope(node: BookmarkNode): BookmarkStorageScope {
    return node.scope === 'private' ? 'private' : 'regular';
  }

  private resolveToolbarRootId(scope: BookmarkStorageScope): string {
    return scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
  }

  private resolveToolbarRootTitle(scope: BookmarkStorageScope): string {
    const rootId = this.resolveToolbarRootId(scope);
    const root = this.options.repository.findNodeById(rootId);
    return resolveAppResourceText(resolveBookmarkNodeDisplayTitle(rootId, (root?.title ?? '').trim()));
  }

  private isDescendantOf(candidateId: string, ancestorId: string): boolean {
    let current = this.options.repository.findNodeById(candidateId);
    let guard = 0;
    while (current !== undefined && guard < 64) {
      const parentId = (current.parentId ?? '').trim();
      if (parentId.length === 0) {
        return false;
      }
      if (parentId === ancestorId) {
        return true;
      }
      current = this.options.repository.findNodeById(parentId);
      guard += 1;
    }
    return false;
  }

  /** Every bookmark URL inside a node, in bar order; a bookmark returns its own URL. */
  private collectBookmarkUrls(nodeId: string, scope: BookmarkStorageScope): string[] {
    const node = this.options.repository.findNodeById(nodeId);
    if (node === undefined) {
      return [];
    }
    if (node.type !== 'folder') {
      const url = (node.url ?? '').trim();
      return url.length > 0 ? [url] : [];
    }
    const urls: string[] = [];
    const children = this.options.repository.listChildren(nodeId, scope);
    for (let index = 0; index < children.length; index += 1) {
      const collected = this.collectBookmarkUrls(children[index].id, scope);
      for (let urlIndex = 0; urlIndex < collected.length; urlIndex += 1) {
        urls.push(collected[urlIndex]);
      }
    }
    return urls;
  }
}
