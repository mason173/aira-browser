import { OfflinePageSaveCoordinator } from '../offline/OfflinePageSaveCoordinator';
import { BrowserActiveTabRuntimeRestoreCoordinator } from '../../services/web/BrowserActiveTabRuntimeRestoreCoordinator';
import { BrowserRecentActionManager } from '../web/BrowserRecentActionManager';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserShellRouteCoordinator } from './BrowserShellRouteCoordinator';
import { BrowserTabCloseCoordinator } from './BrowserTabCloseCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserTabsOverviewSessionCoordinator } from './BrowserTabsOverviewSessionCoordinator';
import { BrowserWebHistoryCommandRuntimeCoordinator } from './BrowserWebHistoryCommandRuntimeCoordinator';
import { BrowserWebTabsController } from './BrowserWebTabsController';
import { BrowserPageFindCoordinator } from './BrowserPageFindCoordinator';
import { BrowserForegroundTabCreationCoordinator } from './BrowserForegroundTabCreationCoordinator';
import { BrowserFullscreenSessionCoordinator } from './BrowserFullscreenSessionCoordinator';
import { BrowserWindowContextPort } from './BrowserWindowContextCoordinator';
import { BrowserWindowRuntime } from '../../app/runtime/BrowserWindowRuntime';

export type BrowserKeyboardShortcutAction =
  'focusAddressBar' |
  'openNewTab' |
  'openHistory' |
  'openDownloads' |
  'toggleTabsOverview' |
  'openPageFind' |
  'toggleFullScreen' |
  'navigateBack' |
  'navigateForward' |
  'reloadPage' |
  'closeActiveTab' |
  'restoreRecentlyClosedTab' |
  'switchToNextTab' |
  'switchToPreviousTab' |
  'saveOfflinePage' |
  'bookmarkCurrentPage' |
  'escape';

export interface BrowserKeyboardShortcutFacts {
  showHomePage: boolean;
  showTabsSheet: boolean;
  fullScreenModeEnabled: boolean;
  webBottomAddressFocused: boolean;
  homeSearchFocused: boolean;
  activeTabId: string;
  tabs: BrowserTabState[];
  recentlyClosedCount: number;
  controllerAttached: boolean;
  loading: boolean;
}

export interface BrowserKeyboardShortcutShell {
  readFacts: () => BrowserKeyboardShortcutFacts;
  showMessage: (message: string) => void;
  focusAddressBar: () => void;
  setTabsOverviewVisible: (visible: boolean) => void;
  releaseAddressFocus: (homePage: boolean) => void;
  bookmarkCurrentPage: () => void;
}

export interface BrowserKeyboardShortcutDependencies {
  routeCoordinator: BrowserShellRouteCoordinator;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  tabCloseCoordinator: BrowserTabCloseCoordinator;
  activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator;
  tabsOverviewSessionCoordinator: BrowserTabsOverviewSessionCoordinator;
  webHistoryCommandRuntimeCoordinator: BrowserWebHistoryCommandRuntimeCoordinator;
  webTabsController: BrowserWebTabsController;
  offlinePageSaveCoordinator: OfflinePageSaveCoordinator;
  recentActionManager: BrowserRecentActionManager;
  pageFindCoordinator: BrowserPageFindCoordinator;
  foregroundTabCreationCoordinator: BrowserForegroundTabCreationCoordinator;
  windowContextCoordinator: BrowserWindowContextPort;
  fullscreenSessionCoordinator: BrowserFullscreenSessionCoordinator;
  homeUrl: string;
  newTabTitle: string;
}

export class BrowserKeyboardShortcutCoordinator {
  private readonly dependencies: BrowserKeyboardShortcutDependencies;
  private readonly shell: BrowserKeyboardShortcutShell;

  constructor(
    dependencies: BrowserKeyboardShortcutDependencies,
    shell: BrowserKeyboardShortcutShell
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
  }

  handleShortcut(action: BrowserKeyboardShortcutAction): void {
    this.dependencies.recentActionManager.recordOperate();
    const facts = this.shell.readFacts();
    switch (action) {
      case 'focusAddressBar':
        this.shell.focusAddressBar();
        this.shell.showMessage('已聚焦地址栏。');
        return;
      case 'openNewTab':
        this.openNewTab();
        this.shell.showMessage('已打开新标签页。');
        return;
      case 'openHistory':
        this.dependencies.routeCoordinator.openHistoryManagerPage();
        this.shell.showMessage('已打开历史记录。');
        return;
      case 'openDownloads':
        this.dependencies.routeCoordinator.openDownloadManagementPage();
        this.shell.showMessage('已打开下载管理。');
        return;
      case 'toggleTabsOverview':
        this.shell.setTabsOverviewVisible(!facts.showTabsSheet);
        this.shell.showMessage(facts.showTabsSheet ? '已关闭标签页列表。' : '已打开标签页列表。');
        return;
      case 'openPageFind':
        if (this.isWebSurfaceUnavailable(facts) || !facts.controllerAttached || !this.canOpenPageFind(facts)) {
          this.shell.showMessage('当前页面暂不可查找。');
          return;
        }
        this.dependencies.pageFindCoordinator.open(facts.activeTabId);
        return;
      case 'toggleFullScreen':
        if (!facts.fullScreenModeEnabled && this.isWebSurfaceUnavailable(facts)) {
          this.shell.showMessage('打开网页后可进入全屏模式。');
          return;
        }
        if (facts.fullScreenModeEnabled) {
          void this.dependencies.fullscreenSessionCoordinator.disableFullscreen(true);
          return;
        }
        this.dependencies.fullscreenSessionCoordinator.toggleManualFullscreen();
        return;
      case 'navigateBack':
        if (facts.showTabsSheet || facts.fullScreenModeEnabled ||
          this.dependencies.pageFindCoordinator.isVisibleForTab(facts.activeTabId)) {
          this.handleEscapeShortcut(facts);
          return;
        }
        if (facts.showHomePage) {
          this.shell.showMessage('已经在首页。');
          return;
        }
        this.dependencies.webHistoryCommandRuntimeCoordinator.handleShortcutNavigateBack();
        return;
      case 'navigateForward':
        if (this.isWebSurfaceUnavailable(facts)) {
          this.shell.showMessage('没有可前进的页面。');
          return;
        }
        this.dependencies.webHistoryCommandRuntimeCoordinator.handleShortcutNavigateForward('已前进。');
        return;
      case 'reloadPage':
        if (this.isWebSurfaceUnavailable(facts)) {
          this.shell.showMessage('当前没有可刷新的网页。');
          return;
        }
        this.dependencies.activeTabRuntimeRestoreCoordinator.reloadActive('user_manual_reload');
        this.shell.showMessage('已刷新页面。');
        return;
      case 'closeActiveTab':
        if (facts.showTabsSheet) {
          return;
        }
        void this.closeActiveTab(facts.activeTabId, facts.tabs, '已关闭当前标签页。');
        return;
      case 'restoreRecentlyClosedTab':
        if (facts.recentlyClosedCount <= 0) {
          this.shell.showMessage('没有最近关闭的标签页。');
          return;
        }
        this.dependencies.tabCloseCoordinator.restoreLatestRecentlyClosedShortcut();
        return;
      case 'switchToNextTab':
      case 'switchToPreviousTab':
        if (facts.tabs.length <= 1) {
          this.shell.showMessage('没有其他可切换的标签页。');
          return;
        }
        void this.switchActiveTabByOffset(
          facts.tabs,
          facts.activeTabId,
          action === 'switchToNextTab' ? 1 : -1,
          action === 'switchToNextTab' ? '已切到下一个标签页。' : '已切到上一个标签页。'
        );
        return;
      case 'saveOfflinePage':
        if (this.isWebSurfaceUnavailable(facts)) {
          this.shell.showMessage('当前页面无法保存离线。');
          return;
        }
        this.dependencies.offlinePageSaveCoordinator.startActiveSave();
        return;
      case 'bookmarkCurrentPage':
        if (this.isWebSurfaceUnavailable(facts)) {
          this.shell.showMessage('当前页面无法收藏。');
          return;
        }
        this.shell.bookmarkCurrentPage();
        return;
      case 'escape':
        this.handleEscapeShortcut(facts);
        return;
      default:
        return;
    }
  }

  handleNumberedShortcut(digit: number): void {
    this.dependencies.recentActionManager.recordOperate();
    const facts = this.shell.readFacts();
    if (facts.showTabsSheet) {
      this.dependencies.tabsOverviewSessionCoordinator.handle({
        type: 'keyboard',
        command: { type: 'number_shortcut', digit: digit }
      });
      return;
    }
    if (facts.tabs.length <= 0) {
      this.shell.showMessage('当前没有可切换的标签页。');
      return;
    }
    const targetTabId = this.dependencies.tabsOverviewSessionCoordinator.handle({
      type: 'keyboard',
      command: {
        type: 'resolve_numbered_tab',
        tabs: facts.tabs,
        digit: digit
      }
    })?.tabId ?? '';
    if (targetTabId.length <= 0) {
      this.shell.showMessage('没有对应的标签页。');
      return;
    }
    void this.switchToNumberedTab(targetTabId, digit);
  }

  releaseAddressFocus(): void {
    const facts = this.shell.readFacts();
    this.shell.releaseAddressFocus(facts.showHomePage);
  }

  private async switchToNumberedTab(tabId: string, digit: number): Promise<void> {
    await this.dependencies.tabSwitchCoordinator.switchToTab(tabId);
    const label = digit === 9 ? '最后一个标签页' : `第 ${digit} 个标签页`;
    this.shell.showMessage(`已切到${label}。`);
  }

  private async switchActiveTabByOffset(
    tabs: BrowserTabState[],
    activeTabId: string,
    offset: number,
    message: string
  ): Promise<void> {
    const targetTabId = this.resolveAdjacentTabId(tabs, activeTabId, offset);
    if (targetTabId.length <= 0) {
      this.shell.showMessage('没有其他可切换的标签页。');
      return;
    }
    await this.dependencies.tabSwitchCoordinator.switchToTab(targetTabId);
    this.shell.showMessage(message);
  }

  private async closeActiveTab(
    activeTabId: string,
    tabs: BrowserTabState[],
    message: string
  ): Promise<void> {
    if (activeTabId.length <= 0 || this.findTabById(tabs, activeTabId) === undefined) {
      this.shell.showMessage('当前没有可关闭的标签页。');
      return;
    }
    const closesApplication = tabs.length <= 1 &&
      BrowserWindowRuntime.resolveActiveShellPresentationSurface() === 'large_screen';
    if (closesApplication) {
      await this.dependencies.tabCloseCoordinator.closeDesktopTab(activeTabId);
    } else {
      await this.dependencies.tabCloseCoordinator.closeTab(activeTabId);
    }
    if (!closesApplication) {
      this.shell.showMessage(message);
    }
  }

  private handleEscapeShortcut(facts: BrowserKeyboardShortcutFacts): void {
    if (this.dependencies.pageFindCoordinator.isVisibleForTab(facts.activeTabId)) {
      this.dependencies.pageFindCoordinator.close(facts.activeTabId);
      this.shell.showMessage('已关闭页内查找。');
      return;
    }
    if (facts.fullScreenModeEnabled) {
      void this.dependencies.fullscreenSessionCoordinator.disableFullscreen(true);
      return;
    }
    if (facts.showTabsSheet) {
      this.shell.setTabsOverviewVisible(false);
      this.shell.showMessage('已关闭标签页列表。');
      return;
    }
    if (facts.webBottomAddressFocused || facts.homeSearchFocused) {
      this.releaseAddressFocus();
      this.shell.showMessage('已退出地址栏。');
      return;
    }
    if (facts.loading) {
      this.dependencies.webTabsController.stopLoading(facts.activeTabId);
      this.shell.showMessage('已停止加载。');
    }
  }

  private resolveAdjacentTabId(tabs: BrowserTabState[], activeTabId: string, offset: number): string {
    if (tabs.length <= 1) {
      return '';
    }
    const activeIndex = tabs.findIndex((tab: BrowserTabState) => tab.id === activeTabId);
    const baseIndex = activeIndex >= 0 ? activeIndex : 0;
    const targetIndex = (baseIndex + offset + tabs.length) % tabs.length;
    return tabs[targetIndex].id;
  }

  private findTabById(tabs: BrowserTabState[], tabId: string): BrowserTabState | undefined {
    return tabs.find((tab: BrowserTabState) => tab.id === tabId);
  }

  private isWebSurfaceUnavailable(facts: BrowserKeyboardShortcutFacts): boolean {
    return facts.showHomePage || facts.showTabsSheet;
  }

  private openNewTab(): void {
    void this.dependencies.foregroundTabCreationCoordinator.createNewTab({
      initialUrl: this.dependencies.homeUrl,
      initialTitle: this.dependencies.newTabTitle,
      options: this.dependencies.windowContextCoordinator.resolveCurrentTabSessionBoundary(),
      runtimeOptions: {}
    });
  }

  private canOpenPageFind(facts: BrowserKeyboardShortcutFacts): boolean {
    const activeTab = facts.tabs.find((tab: BrowserTabState): boolean => tab.id === facts.activeTabId);
    return this.dependencies.pageFindCoordinator.canOpen({
      tab: activeTab,
      webPageVisible: !facts.showHomePage
    });
  }
}
