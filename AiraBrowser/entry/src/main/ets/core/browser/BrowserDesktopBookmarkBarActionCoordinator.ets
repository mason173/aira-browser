import {
  BookmarkNode,
  BookmarkStorageScope,
  DesktopBookmarkBarVisibility
} from '../../common/models/BrowserModels';
import {
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID,
  isBookmarkRootNodeId,
  sanitizeBookmarkTitle
} from '../../data/repositories/BookmarkRepositoryCore';
import { BookmarkRepository } from '../../data/repositories/BrowserRepositories';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BookmarkMutationService } from '../../services/bookmarks/BookmarkMutationService';
import { BrowserClipboardCopyTextRequest } from '../../services/share/BrowserClipboardService';
import { DesktopBookmarkClipboardSignal } from '../bookmarks/DesktopBookmarkClipboardSignal';
import { BrowserConfirmationRequest } from './BrowserConfirmationSink';
import { BrowserDesktopBookmarkBarNodeActionKind, BrowserDesktopBookmarkBarRootActionKind } from './BrowserDesktopBookmarkBarViewModel';
import { setDesktopBookmarkBarVisibility } from './DesktopBookmarkBarVisibility';

export interface BrowserDesktopBookmarkBarActivePage {
  title: string;
  url: string;
}

/** One dialog serves "new folder" (empty nodeId) and "rename" (nodeId set). */
export interface BrowserDesktopBookmarkBarFolderNameRequest {
  nodeId: string;
  parentId: string;
  initialTitle: string;
  dialogTitle: string;
  fieldPlaceholder: string;
}

export interface BrowserDesktopBookmarkBarBookmarkEditorRequest {
  parentId: string;
  title: string;
  url: string;
  dialogTitle: string;
}

export interface BrowserDesktopBookmarkBarActionShell {
  /** The page behind the bar, used to prefill "add page". */
  readActivePage: () => BrowserDesktopBookmarkBarActivePage | undefined;
  presentFolderNameDialog: (request: BrowserDesktopBookmarkBarFolderNameRequest) => void;
  presentBookmarkEditor: (request: BrowserDesktopBookmarkBarBookmarkEditorRequest) => void;
  confirmDelete: (request: BrowserConfirmationRequest) => void;
  copyText: (request: BrowserClipboardCopyTextRequest) => void;
  showToast: (message: string) => void;
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
  private clipboard?: BrowserDesktopBookmarkBarClipboardEntry;

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
        this.shell.showToast('书签栏设置保存失败，请稍后重试。');
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
        dialogTitle: '新建文件夹',
        fieldPlaceholder: '文件夹名称'
      });
      return;
    }
    const page = this.shell.readActivePage();
    this.shell.presentBookmarkEditor({
      parentId: rootId,
      title: page?.title ?? '',
      url: page?.url ?? '',
      dialogTitle: `添加到「${this.resolveToolbarRootTitle(scope)}」`
    });
  }

  /** Confirmed by the folder-name dialog. */
  handleFolderNameSubmitted(request: BrowserDesktopBookmarkBarFolderNameRequest, title: string): void {
    const sanitized = title.trim();
    if (sanitized.length === 0) {
      this.shell.showToast('名称不能为空。');
      return;
    }
    void this.applyFolderName(request, sanitized);
  }

  /** Confirmed by the bookmark editor dialog. */
  handleBookmarkSubmitted(request: BrowserDesktopBookmarkBarBookmarkEditorRequest, title: string, url: string): void {
    const sanitizedUrl = url.trim();
    if (sanitizedUrl.length === 0) {
      this.shell.showToast('请输入网址。');
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
        this.shell.showToast(updated === undefined ? '没有找到这个书签。' : '已重命名。');
        return;
      }
      const scope = this.resolveScopeForParentId(request.parentId);
      await this.mutationService.createNode({
        type: 'folder',
        title: title,
        parentId: this.resolveWritableParentId(request.parentId, scope),
        scope: scope
      });
      this.shell.showToast('已新建文件夹。');
    } catch (_error) {
      this.shell.showToast('保存文件夹失败，请稍后重试。');
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
      this.shell.showToast('已添加网页。');
    } catch (_error) {
      this.shell.showToast('添加网页失败，请稍后重试。');
    }
  }

  private requestRename(node: BookmarkNode): void {
    if (isBookmarkRootNodeId(node.id)) {
      return;
    }
    this.shell.presentFolderNameDialog({
      nodeId: node.id,
      parentId: node.parentId ?? '',
      initialTitle: node.title,
      dialogTitle: '重命名',
      fieldPlaceholder: '名称'
    });
  }

  private requestDelete(node: BookmarkNode): void {
    if (isBookmarkRootNodeId(node.id)) {
      return;
    }
    const scope = this.resolveNodeScope(node);
    const containedCount = node.type === 'folder' ? this.collectBookmarkUrls(node.id, scope).length : 0;
    this.shell.confirmDelete({
      title: node.type === 'folder' ? '删除文件夹' : '删除书签',
      message: this.buildDeleteMessage(node, containedCount),
      cancelLabel: '取消',
      confirmLabel: '删除',
      confirmTone: 'alert',
      onConfirm: (): void => {
        void this.applyDelete(node.id);
      }
    });
  }

  private buildDeleteMessage(node: BookmarkNode, containedCount: number): string {
    if (node.type !== 'folder') {
      return `确定删除「${node.title}」吗？此操作无法撤销。`;
    }
    if (containedCount > 0) {
      return `确定删除文件夹「${node.title}」及其中 ${containedCount} 个书签吗？此操作无法撤销。`;
    }
    return `确定删除文件夹「${node.title}」吗？此操作无法撤销。`;
  }

  private async applyDelete(nodeId: string): Promise<void> {
    try {
      const deleted = await this.mutationService.deleteNode(nodeId);
      this.shell.showToast(deleted ? '已删除。' : '没有找到这个书签。');
    } catch (_error) {
      this.shell.showToast('删除失败，请稍后重试。');
    }
  }

  private requestAddFolder(node: BookmarkNode): void {
    const parentId = this.resolveAddParentId(node);
    this.shell.presentFolderNameDialog({
      nodeId: '',
      parentId: parentId,
      initialTitle: '',
      dialogTitle: '新建文件夹',
      fieldPlaceholder: '文件夹名称'
    });
  }

  private requestAddBookmark(node: BookmarkNode): void {
    const parentId = this.resolveAddParentId(node);
    const page = this.shell.readActivePage();
    this.shell.presentBookmarkEditor({
      parentId: parentId,
      title: page?.title ?? '',
      url: page?.url ?? '',
      dialogTitle: `添加到「${this.resolveParentTitle(node, parentId)}」`
    });
  }

  private writeClipboard(node: BookmarkNode, mode: 'copy' | 'cut'): void {
    const scope = this.resolveNodeScope(node);
    const urls = this.collectBookmarkUrls(node.id, scope);
    this.clipboard = { mode: mode, nodeIds: [node.id] };
    DesktopBookmarkClipboardSignal.publish(true);
    if (mode === 'cut') {
      this.shell.showToast('已剪切，可在目标文件夹上右键粘贴。');
      return;
    }
    this.shell.copyText({
      value: urls.join('\n'),
      emptyMessage: node.type === 'folder' ? '这个文件夹里还没有网址。' : '这个书签没有可复制的网址。',
      successMessage: urls.length > 1 ? `已复制 ${urls.length} 个网址。` : '网址已复制。'
    });
  }

  private async applyPaste(node: BookmarkNode): Promise<void> {
    const entry = this.clipboard;
    if (entry === undefined) {
      this.shell.showToast('剪贴板里还没有书签。');
      return;
    }
    const scope = this.resolveNodeScope(node);
    const targetParentId = this.resolvePasteParentId(node, scope);
    for (let index = 0; index < entry.nodeIds.length; index += 1) {
      const sourceId = entry.nodeIds[index];
      if (sourceId === targetParentId || this.isDescendantOf(targetParentId, sourceId)) {
        this.shell.showToast('不能粘贴到它自己的位置。');
        return;
      }
    }
    try {
      await this.options.repository.initialize();
      const pasted = entry.mode === 'cut'
        ? await this.moveClipboardNodes(entry.nodeIds, targetParentId, scope)
        : await this.copyClipboardNodes(entry.nodeIds, targetParentId, scope);
      this.clearClipboard();
      this.shell.showToast(entry.mode === 'cut' ? '已移动。' : `已粘贴 ${pasted} 项。`);
    } catch (_error) {
      this.shell.showToast('粘贴失败，请稍后重试。');
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
      return node.title;
    }
    const parent = this.options.repository.findNodeById(parentId);
    if (parent === undefined || isBookmarkRootNodeId(parent.id)) {
      return '书签栏';
    }
    return parent.title;
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
    const root = this.options.repository.findNodeById(this.resolveToolbarRootId(scope));
    const title = (root?.title ?? '').trim();
    return title.length > 0 ? title : '书签栏';
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
