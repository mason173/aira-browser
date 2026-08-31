import {
  BookmarkNode,
  HomeSystemShortcutTarget,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import {
  sharedBookmarkRepository,
  sharedShortcutRepository
} from '../../app/bootstrap/BrowserAppRuntime';
import { BookmarksFeature } from '../../features/bookmarks/BookmarksFeature';
import {
  BookmarkFolderNavigationController,
  BookmarkFolderLocation
} from '../../features/bookmarks/BookmarkFolderNavigationController';
import {
  getHomeSystemShortcutDefinitions,
  HomeSystemShortcutDefinition
} from '../../services/shortcuts/HomeSystemShortcutCatalog';
import {
  HomeShortcutToggleService,
  HomeShortcutToggleTarget
} from '../../services/shortcuts/HomeShortcutToggleService';

export type HomeShortcutSelectionTab = 'system' | 'bookmarks';
export interface HomeShortcutSelectionAction {
  type: 'select_tab' | 'back_folder' | 'enter_folder' | 'toggle_system' | 'toggle_bookmark';
  tab?: HomeShortcutSelectionTab;
  folderId?: string;
  target?: HomeSystemShortcutTarget;
  bookmarkId?: string;
}

export interface HomeShortcutSystemSelectionRow {
  target: HomeSystemShortcutTarget;
  title: string;
  busyKey: string;
  added: boolean;
}

export interface HomeShortcutBookmarkSelectionRow {
  id: string;
  kind: 'folder' | 'bookmark';
  title: string;
  url: string;
  folderBookmarkCount: number;
  busyKey: string;
  added: boolean;
}

export interface HomeShortcutSelectionState {
  sessionId: number;
  scenarioId: string;
  activeTab: HomeShortcutSelectionTab;
  currentFolderId: string;
  currentFolderTitle: string;
  systemRows: HomeShortcutSystemSelectionRow[];
  bookmarkRows: HomeShortcutBookmarkSelectionRow[];
  busyKeys: string[];
  bookmarksLoading: boolean;
}

interface HomeShortcutSelectionBackPlan {
  state: HomeShortcutSelectionState;
  shouldClose: boolean;
}

export interface HomeShortcutSelectionShell {
  publishSnapshot: (state: HomeShortcutSelectionState) => void;
  canOpen: () => boolean;
  openSheet: () => void;
  closeSheet: () => void;
  refreshHomeShortcuts: () => void;
  showMessage: (message: string) => void;
}

const HOME_SHORTCUT_SELECTION_ROOT_TITLE: string = '书签';

export class HomeShortcutSelectionCoordinator {
  private readonly shell: HomeShortcutSelectionShell;
  private readonly bookmarksFeature: BookmarksFeature = new BookmarksFeature(sharedBookmarkRepository, 'regular');
  private readonly navigationController: BookmarkFolderNavigationController =
    new BookmarkFolderNavigationController();
  private readonly toggleService: HomeShortcutToggleService = new HomeShortcutToggleService(sharedShortcutRepository);
  private folderBookmarkCounts: Map<string, number> = new Map();
  private sessionId: number = 0;
  private state: HomeShortcutSelectionState;

  constructor(shell: HomeShortcutSelectionShell) {
    this.shell = shell;
    this.state = this.createInitialState();
  }

  getSnapshot(): HomeShortcutSelectionState {
    return this.cloneState(this.state);
  }

  private createInitialState(): HomeShortcutSelectionState {
    return {
      sessionId: 0,
      scenarioId: 'aira_default_scenario',
      activeTab: 'system',
      currentFolderId: '',
      currentFolderTitle: HOME_SHORTCUT_SELECTION_ROOT_TITLE,
      systemRows: [],
      bookmarkRows: [],
      busyKeys: [],
      bookmarksLoading: false
    };
  }

  openSession(
    shortcuts: ShortcutRecord[],
    scenarioId: string
  ): void {
    if (!this.shell.canOpen()) {
      return;
    }
    const state = this.beginSession(shortcuts, scenarioId);
    this.applyState(state);
    this.shell.openSheet();
    this.refreshSession(state);
  }

  handleAction(action: HomeShortcutSelectionAction): void {
    if (action.type === 'select_tab') {
      this.selectTab(action.tab ?? 'system');
      return;
    }
    if (action.type === 'back_folder') {
      this.handleSystemBack();
      return;
    }
    if (action.type === 'enter_folder') {
      this.openFolder(action.folderId ?? '');
      return;
    }
    if (action.type === 'toggle_system') {
      if (action.target !== undefined) {
        this.toggleSystemShortcut(action.target);
      }
      return;
    }
    this.toggleBookmarkShortcut(action.bookmarkId ?? '');
  }

  private selectTab(tab: HomeShortcutSelectionTab): void {
    this.applyState(this.switchTab(this.state, tab));
  }

  private openFolder(folderId: string): void {
    this.applyState(this.enterFolder(this.state, folderId));
  }

  handleSystemBack(): void {
    const plan = this.buildBackPlan(this.state);
    if (plan.shouldClose) {
      this.shell.closeSheet();
      return;
    }
    this.applyState(plan.state);
  }

  private beginSession(shortcuts: ShortcutRecord[], scenarioId: string): HomeShortcutSelectionState {
    this.sessionId += 1;
    this.navigationController.reset();
    this.folderBookmarkCounts = new Map();
    const state = this.createInitialState();
    state.sessionId = this.sessionId;
    state.scenarioId = this.resolveScenarioId(scenarioId);
    state.systemRows = this.buildSystemRows(shortcuts, state.scenarioId);
    state.bookmarksLoading = true;
    return state;
  }

  private refreshSession(state: HomeShortcutSelectionState): void {
    const expectedSessionId = state.sessionId;
    void this.refreshSessionData(expectedSessionId);
  }

  resetSession(): void {
    this.sessionId += 1;
    this.navigationController.reset();
    this.folderBookmarkCounts = new Map();
    this.applyState(this.createInitialState());
  }

  private switchTab(state: HomeShortcutSelectionState, tab: HomeShortcutSelectionTab): HomeShortcutSelectionState {
    const next = this.cloneState(state);
    next.activeTab = tab;
    return next;
  }

  private enterFolder(state: HomeShortcutSelectionState, folderId: string): HomeShortcutSelectionState {
    const folder = this.bookmarksFeature.findNodeById(folderId);
    if (folder === undefined || folder.type !== 'folder') {
      return state;
    }
    const location = this.navigationController.enterFolder(folder);
    return this.buildFolderState(state, location);
  }

  private buildBackPlan(state: HomeShortcutSelectionState): HomeShortcutSelectionBackPlan {
    if (state.activeTab !== 'bookmarks' || !this.navigationController.canNavigateBack()) {
      return {
        state: state,
        shouldClose: true
      };
    }
    const location = this.navigationController.navigateBack();
    return {
      state: this.buildFolderState(state, location),
      shouldClose: false
    };
  }

  private toggleSystemShortcut(target: HomeSystemShortcutTarget): void {
    const state = this.state;
    const definition = getHomeSystemShortcutDefinitions().find((item: HomeSystemShortcutDefinition) => {
      return item.target === target;
    });
    if (definition === undefined) {
      this.shell.showMessage('这个系统入口暂不可添加到主页。');
      return;
    }
    const toggleTarget: HomeShortcutToggleTarget = {
      title: definition.title,
      url: definition.url,
      kind: 'system',
      scenarioId: state.scenarioId
    };
    this.runToggle(state, this.buildSystemBusyKey(target), toggleTarget);
  }

  private toggleBookmarkShortcut(bookmarkId: string): void {
    const state = this.state;
    const bookmark = this.bookmarksFeature.findNodeById(bookmarkId);
    const url = (bookmark?.url ?? '').trim();
    if (bookmark === undefined || bookmark.type !== 'bookmark' || url.length <= 0) {
      this.shell.showMessage('这个书签没有可添加到主页的网址。');
      return;
    }
    const toggleTarget: HomeShortcutToggleTarget = {
      title: bookmark.title,
      url: url,
      kind: 'web',
      scenarioId: state.scenarioId
    };
    this.runToggle(state, this.buildBookmarkBusyKey(bookmarkId, url), toggleTarget);
  }

  private buildSystemBusyKey(target: HomeSystemShortcutTarget): string {
    return `system:${target}`;
  }

  private buildBookmarkBusyKey(bookmarkId: string, url: string): string {
    const normalizedUrlKey = this.toggleService.normalizeUrlKey(url);
    return normalizedUrlKey.length > 0 ? `bookmark-url:${normalizedUrlKey}` : `bookmark:${bookmarkId}`;
  }

  private async refreshSessionData(expectedSessionId: number): Promise<void> {
    try {
      await this.bookmarksFeature.refresh();
      const folderBookmarkCounts = await this.bookmarksFeature.buildFolderBookmarkCountsAsync();
      const shortcuts = await this.toggleService.refresh();
      const current = this.state;
      if (!this.isSessionCurrent(expectedSessionId, current)) {
        return;
      }
      this.folderBookmarkCounts = folderBookmarkCounts.counts;
      const next = this.cloneState(current);
      next.systemRows = this.buildSystemRows(shortcuts, current.scenarioId);
      next.bookmarkRows = this.buildBookmarkRows(current.currentFolderId, shortcuts, current.scenarioId);
      next.bookmarksLoading = false;
      this.applyState(next);
    } catch (error) {
      const current = this.state;
      if (!this.isSessionCurrent(expectedSessionId, current)) {
        return;
      }
      const next = this.cloneState(current);
      next.bookmarksLoading = false;
      this.applyState(next);
      this.shell.showMessage(`加载添加列表失败：${this.describeError(error)}`);
    }
  }

  private runToggle(
    state: HomeShortcutSelectionState,
    busyKey: string,
    target: HomeShortcutToggleTarget
  ): void {
    if (state.busyKeys.indexOf(busyKey) >= 0) {
      return;
    }
    const busyState = this.cloneState(state);
    busyState.busyKeys = busyState.busyKeys.concat([busyKey]);
    this.applyState(busyState);
    void this.toggleService.toggle(target)
      .then((result): void => {
        this.shell.refreshHomeShortcuts();
        this.showSystemToggleSuccess(target, result.added, result.removed);
        const current = this.state;
        if (!this.isSessionCurrent(state.sessionId, current)) {
          return;
        }
        const next = this.cloneState(current);
        next.busyKeys = next.busyKeys.filter((key: string) => key !== busyKey);
        next.systemRows = this.buildSystemRows(result.shortcuts, current.scenarioId);
        next.bookmarkRows = this.buildBookmarkRows(current.currentFolderId, result.shortcuts, current.scenarioId);
        this.applyState(next);
      })
      .catch((error: Error): void => {
        const current = this.state;
        if (!this.isSessionCurrent(state.sessionId, current)) {
          return;
        }
        const next = this.cloneState(current);
        next.busyKeys = next.busyKeys.filter((key: string) => key !== busyKey);
        this.applyState(next);
        this.shell.showMessage(`更新首页快捷方式失败：${this.describeError(error)}`);
      });
  }

  private showSystemToggleSuccess(
    target: HomeShortcutToggleTarget,
    added: boolean,
    removed: boolean
  ): void {
    if (target.kind !== 'system') {
      return;
    }
    const title = target.title.trim().length > 0 ? target.title.trim() : '系统入口';
    if (added) {
      this.shell.showMessage(`已将“${title}”添加至首页。`);
      return;
    }
    if (removed) {
      this.shell.showMessage(`已从首页移除“${title}”。`);
    }
  }

  private applyState(state: HomeShortcutSelectionState): void {
    this.state = this.cloneState(state);
    this.shell.publishSnapshot(this.getSnapshot());
  }

  private buildSystemRows(shortcuts: ShortcutRecord[], scenarioId: string): HomeShortcutSystemSelectionRow[] {
    return getHomeSystemShortcutDefinitions().map((definition: HomeSystemShortcutDefinition) => {
      const target: HomeShortcutToggleTarget = {
        title: definition.title,
        url: definition.url,
        kind: 'system',
        scenarioId: scenarioId
      };
      const row: HomeShortcutSystemSelectionRow = {
        target: definition.target,
        title: definition.title,
        busyKey: this.buildSystemBusyKey(definition.target),
        added: this.toggleService.isTargetAddedToScenario(target, shortcuts, scenarioId)
      };
      return row;
    });
  }

  private buildBookmarkRows(
    folderId: string,
    shortcuts: ShortcutRecord[],
    scenarioId: string
  ): HomeShortcutBookmarkSelectionRow[] {
    const parentId = folderId.length > 0 ? folderId : undefined;
    return this.bookmarksFeature.listDisplayChildren(parentId).map((node: BookmarkNode) => {
      const url = (node.url ?? '').trim();
      const row: HomeShortcutBookmarkSelectionRow = {
        id: node.id,
        kind: node.type,
        title: node.title,
        url: url,
        folderBookmarkCount: node.type === 'folder' ? this.folderBookmarkCounts.get(node.id) ?? 0 : -1,
        busyKey: this.buildBookmarkBusyKey(node.id, url),
        added: node.type === 'bookmark' && url.length > 0 &&
          this.toggleService.isUrlAddedToScenario(url, shortcuts, scenarioId)
      };
      return row;
    });
  }

  private buildFolderState(
    state: HomeShortcutSelectionState,
    location: BookmarkFolderLocation
  ): HomeShortcutSelectionState {
    const next = this.cloneState(state);
    next.currentFolderId = location.folderId;
    next.currentFolderTitle = location.folderId.length > 0 ? location.folderTitle : HOME_SHORTCUT_SELECTION_ROOT_TITLE;
    next.bookmarkRows = this.buildBookmarkRows(location.folderId, this.toggleServiceSnapshot(), state.scenarioId);
    return next;
  }

  private toggleServiceSnapshot(): ShortcutRecord[] {
    return sharedShortcutRepository.listAll();
  }

  private cloneState(state: HomeShortcutSelectionState): HomeShortcutSelectionState {
    return {
      sessionId: state.sessionId,
      scenarioId: state.scenarioId,
      activeTab: state.activeTab,
      currentFolderId: state.currentFolderId,
      currentFolderTitle: state.currentFolderTitle,
      systemRows: state.systemRows.slice(),
      bookmarkRows: state.bookmarkRows.slice(),
      busyKeys: state.busyKeys.slice(),
      bookmarksLoading: state.bookmarksLoading
    };
  }

  private resolveScenarioId(scenarioId: string): string {
    const normalized = scenarioId.trim();
    return normalized.length > 0 ? normalized : 'aira_default_scenario';
  }

  private isSessionCurrent(expectedSessionId: number, state: HomeShortcutSelectionState): boolean {
    return expectedSessionId === this.sessionId && expectedSessionId === state.sessionId;
  }

  private describeError(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
