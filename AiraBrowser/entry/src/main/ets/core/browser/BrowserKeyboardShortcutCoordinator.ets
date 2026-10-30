import { resolveAppResourceText } from '../resources/AppResourceText';
import { common } from '@kit.AbilityKit';
import { OfflinePageSaveCoordinator } from '../offline/OfflinePageSaveCoordinator';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BrowserActiveTabRuntimeRestoreCoordinator } from '../../services/web/BrowserActiveTabRuntimeRestoreCoordinator';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserWebPrintService } from '../../services/web/BrowserWebPrintService';
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
import { ElementInspectionSessionCoordinator } from './ElementInspectionSessionCoordinator';
import { BrowserRootBottomPanelShellActionExecutor } from './BrowserRootBottomPanelShellActionExecutor';
import { toggleDesktopBookmarkBarVisibility } from './DesktopBookmarkBarVisibility';

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
  'openBookmarks' |
  'openSettings' |
  'toggleBookmarkBar' |
  'togglePrivateMode' |
  'printPage' |
  'inspectElement' |
  'escape';

export interface BrowserKeyboardShortcutFacts {
  showHomePage: boolean;
  showTabsSheet: boolean;
  fullScreenModeEnabled: boolean;
  webBottomAddressFocused: boolean;
  homeSearchFocused: boolean;
  searchInvocationVisible: boolean;
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
  preferencesRepository: PreferencesRepository;
  elementInspectionSessionCoordinator: ElementInspectionSessionCoordinator;
  bottomPanelShellActionExecutor: BrowserRootBottomPanelShellActionExecutor;
  webPrintService: BrowserWebPrintService;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  resolveAbilityContext: () => common.UIAbilityContext;
  homeUrl: string;
  newTabTitle: string;
}

export class BrowserKeyboardShortcutCoordinator {
  private readonly dependencies: BrowserKeyboardShortcutDependencies;
  private readonly shell: BrowserKeyboardShortcutShell;
  private suppressFollowingEscapeShortcut: boolean = false;

  constructor(
    dependencies: BrowserKeyboardShortcutDependencies,
    shell: BrowserKeyboardShortcutShell
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
  }

  consumeFullscreenEscapeFromPreIme(): void {
    this.handleShortcut('escape');
    this.suppressFollowingEscapeShortcut = true;
    setTimeout((): void => {
      this.suppressFollowingEscapeShortcut = false;
    }, 0);
  }

  handleShortcut(action: BrowserKeyboardShortcutAction): void {
    if (action === 'escape' && this.suppressFollowingEscapeShortcut) {
      this.suppressFollowingEscapeShortcut = false;
      return;
    }
    this.dependencies.recentActionManager.recordOperate();
    const facts = this.shell.readFacts();
    switch (action) {
      case 'focusAddressBar':
        this.shell.focusAddressBar();
        this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_016')));
        return;
      case 'openNewTab':
        this.openNewTab();
        this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_011')));
        return;
      case 'openHistory':
        this.dependencies.routeCoordinator.openHistoryManagerPage();
        this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_010')));
        return;
      case 'openDownloads':
        this.dependencies.routeCoordinator.openDownloadManagementPage();
        this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_008')));
        return;
      case 'toggleTabsOverview':
        this.shell.setTabsOverviewVisible(!facts.showTabsSheet);
        this.shell.showMessage(facts.showTabsSheet ? resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_004')) : resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_012')));
        return;
      case 'openPageFind':
        if (this.isWebSurfaceUnavailable(facts) || !facts.controllerAttached || !this.canOpenPageFind(facts)) {
          this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_024')));
          return;
        }
        this.dependencies.pageFindCoordinator.open(facts.activeTabId);
        return;
      case 'toggleFullScreen':
        if (!facts.fullScreenModeEnabled && this.isWebSurfaceUnavailable(facts)) {
          this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_026')));
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
          this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_015')));
          return;
        }
        this.dependencies.webHistoryCommandRuntimeCoordinator.handleShortcutNavigateBack();
        return;
      case 'navigateForward':
        if (facts.showTabsSheet) {
          this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_028')));
          return;
        }
        this.dependencies.webHistoryCommandRuntimeCoordinator.handleShortcutNavigateForward(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_007')));
        return;
      case 'reloadPage':
        if (this.isWebSurfaceUnavailable(facts)) {
          this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_021')));
          return;
        }
        this.dependencies.activeTabRuntimeRestoreCoordinator.reloadActive('user_manual_reload');
        this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_006')));
        return;
      case 'closeActiveTab':
        if (facts.showTabsSheet) {
          return;
        }
        void this.closeActiveTab(facts.activeTabId, facts.tabs, resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_003')));
        return;
      case 'restoreRecentlyClosedTab':
        if (facts.recentlyClosedCount <= 0) {
          this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_030')));
          return;
        }
        this.dependencies.tabCloseCoordinator.restoreLatestRecentlyClosedShortcut();
        return;
      case 'switchToNextTab':
      case 'switchToPreviousTab':
        if (facts.tabs.length <= 1) {
          this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_027')));
          return;
        }
        void this.switchActiveTabByOffset(
          facts.tabs,
          facts.activeTabId,
          action === 'switchToNextTab' ? 1 : -1,
          action === 'switchToNextTab' ? resolveAppResourceText($r('app.string.keyboard_shortcut_switched_next')) : resolveAppResourceText($r('app.string.keyboard_shortcut_switched_previous'))
        );
        return;
      case 'saveOfflinePage':
        if (this.isWebSurfaceUnavailable(facts)) {
          this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_022')));
          return;
        }
        this.dependencies.offlinePageSaveCoordinator.startActiveSave();
        return;
      case 'bookmarkCurrentPage':
        if (this.isWebSurfaceUnavailable(facts)) {
          this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_023')));
          return;
        }
        this.shell.bookmarkCurrentPage();
        return;
      case 'openBookmarks':
        void this.dependencies.routeCoordinator.openBookmarkManagerPage();
        this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_009')));
        return;
      case 'openSettings':
        this.dependencies.routeCoordinator.openSettingsCenterPage();
        this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_013')));
        return;
      case 'toggleBookmarkBar':
        void this.toggleBookmarkBar();
        return;
      case 'togglePrivateMode':
        this.dependencies.bottomPanelShellActionExecutor.apply('toggle_private_mode');
        return;
      case 'printPage':
        void this.printCurrentPage(facts);
        return;
      case 'inspectElement':
        this.dependencies.elementInspectionSessionCoordinator.startFromToolbar();
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
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_020')));
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
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_029')));
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
    const message = digit === 9
      ? resolveAppResourceText($r('app.string.keyboard_shortcut_switched_last'))
      : resolveAppResourceText($r('app.string.keyboard_shortcut_switched_numbered', digit));
    this.shell.showMessage(message);
  }

  private async switchActiveTabByOffset(
    tabs: BrowserTabState[],
    activeTabId: string,
    offset: number,
    message: string
  ): Promise<void> {
    const targetTabId = this.resolveAdjacentTabId(tabs, activeTabId, offset);
    if (targetTabId.length <= 0) {
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_027')));
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
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_019')));
      return;
    }
    if (BrowserWindowRuntime.resolveActiveShellPresentationSurface() === 'large_screen') {
      await this.dependencies.tabCloseCoordinator.closeDesktopTab(activeTabId);
    } else {
      await this.dependencies.tabCloseCoordinator.closeTab(activeTabId);
    }
    this.shell.showMessage(message);
  }

  private handleEscapeShortcut(facts: BrowserKeyboardShortcutFacts): void {
    if (this.dependencies.pageFindCoordinator.isVisibleForTab(facts.activeTabId)) {
      this.dependencies.pageFindCoordinator.close(facts.activeTabId);
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_005')));
      return;
    }
    if (facts.fullScreenModeEnabled) {
      void this.dependencies.fullscreenSessionCoordinator.disableFullscreen(true);
      return;
    }
    if (facts.showTabsSheet) {
      this.shell.setTabsOverviewVisible(false);
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_004')));
      return;
    }
    if (facts.webBottomAddressFocused || facts.homeSearchFocused || facts.searchInvocationVisible) {
      this.releaseAddressFocus();
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_017')));
      return;
    }
    if (facts.loading) {
      this.dependencies.webTabsController.stopLoading(facts.activeTabId);
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_002')));
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

  private async toggleBookmarkBar(): Promise<void> {
    try {
      const visible = await toggleDesktopBookmarkBarVisibility(this.dependencies.preferencesRepository);
      this.shell.showMessage(visible ? resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_014')) : resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_018')));
    } catch (_error) {
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_001')));
    }
  }

  private async printCurrentPage(facts: BrowserKeyboardShortcutFacts): Promise<void> {
    const canPrint = this.dependencies.webPrintService.canPrintCurrentPage({
      runtimeLifecyclePort: this.dependencies.runtimeLifecyclePort,
      showHomePage: facts.showHomePage,
      showTabsSheet: facts.showTabsSheet,
      webPageVisible: !facts.showHomePage && !facts.showTabsSheet && facts.controllerAttached
    });
    if (!canPrint) {
      this.shell.showMessage(resolveAppResourceText($r('app.string.browser_browser_keyboard_shortcut_coordinator_025')));
      return;
    }
    const activeTab = this.findTabById(facts.tabs, facts.activeTabId);
    const result = await this.dependencies.webPrintService.printCurrentPageFromLifecyclePort({
      runtimeLifecyclePort: this.dependencies.runtimeLifecyclePort,
      context: this.dependencies.resolveAbilityContext(),
      title: activeTab === undefined ? '' : activeTab.title,
      printBackground: true,
      onStatusMessage: (message: string): void => {
        this.shell.showMessage(message);
      }
    });
    this.shell.showMessage(result.message);
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
