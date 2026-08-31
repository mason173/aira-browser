import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyCode } from '@kit.InputKit';
import {
  ExternalAppSearchTargetId,
  SearchEngineId,
  SearchSuggestion,
  SitePermissionKind,
  SitePermissionRule
} from '../../common/models/BrowserModels';
import { BrowserSearchInvocationRuntime } from '../../app/runtime/BrowserSearchInvocationRuntime';
import { BrowserActiveTabRuntimeRestoreCoordinator } from '../../services/web/BrowserActiveTabRuntimeRestoreCoordinator';
import { BrowserTabWindowMoveService } from '../../services/browser/BrowserTabWindowMoveService';
import { BrowserBottomAddressPanelActionId } from './BrowserBottomAddressPanelViewModel';
import { BrowserBookmarkFolderSelectionAction } from './BrowserBookmarkActionCoordinator';
import { BrowserSiteControlsUserAction } from './BrowserSiteControlsRuntimeCoordinator';
import { BrowserRootBottomPanelFixedActionApplication } from './BrowserRootBottomPanelActionApplication';
import { BrowserSiteControlsRuntimeCoordinator } from './BrowserSiteControlsRuntimeCoordinator';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { BrowserAddressSubmissionCoordinator } from '../navigation/BrowserAddressSubmissionCoordinator';
import { BrowserForegroundTabCreationCoordinator } from './BrowserForegroundTabCreationCoordinator';
import { BrowserAppUrlOpenCoordinator } from './BrowserAppUrlOpenCoordinator';
import { BrowserDesktopBookmarkBarAction } from './BrowserDesktopBookmarkBarViewModel';
import {
  BrowserLargeScreenSearchInvocationAdapter,
  BrowserLargeScreenSearchInvocationHost
} from './BrowserLargeScreenSearchInvocationAdapter';
import { BrowserSearchSuggestionCoordinator } from './BrowserSearchSuggestionCoordinator';
import { BrowserTabCloseCoordinator } from './BrowserTabCloseCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserRecentlyClosedApplicationCoordinator } from './BrowserRecentlyClosedApplicationCoordinator';
import { BrowserWebHistoryCommandRuntimeCoordinator } from './BrowserWebHistoryCommandRuntimeCoordinator';
import { BrowserWebTabsController } from './BrowserWebTabsController';
import { BrowserWindowSessionContextPort } from './BrowserWindowSessionContextApplication';
import { BrowserTabState } from '../tabs/TabManager';
import { SettingsCenterDestination } from '../settings/SettingsCenterViewModel';
import {
  BrowserLargeScreenWebZoomAction,
  BrowserLargeScreenWebZoomCoordinator,
  BrowserLargeScreenWebZoomSnapshot
} from './BrowserLargeScreenWebZoomCoordinator';
import {
  APP_PROXY_NATIVE_TAB_TITLE,
  APP_PROXY_NATIVE_TAB_URL,
  BrowserNativeTabOpenRequest,
  BrowserNativeTabScene,
  BOOKMARK_NATIVE_TAB_TITLE,
  BOOKMARK_NATIVE_TAB_URL,
  DOWNLOADS_NATIVE_TAB_TITLE,
  DOWNLOADS_NATIVE_TAB_URL,
  HISTORY_NATIVE_TAB_TITLE,
  HISTORY_NATIVE_TAB_URL,
  SAVED_PAGES_NATIVE_TAB_TITLE,
  SAVED_PAGES_NATIVE_TAB_URL,
  SETTINGS_NATIVE_TAB_TITLE,
  SETTINGS_NATIVE_TAB_URL,
  USER_SCRIPTS_NATIVE_TAB_TITLE,
  USER_SCRIPTS_NATIVE_TAB_URL,
  browserNativeTabSceneService
} from './BrowserNativeTabSceneService';

const WEB_ZOOM_DIALOG_AUTO_DISMISS_DELAY_MS: number = 2000;
const WEB_ZOOM_DIAG_DOMAIN: number = 0x0000;
const WEB_ZOOM_DIAG_TAG: string = 'DesktopZoomDiag';
const WEB_ZOOM_DIAG_PREFIX: string = '[DEBUG-desktop-zoom-20260726]';

export type BrowserLargeScreenTabStripIntentKind =
  'select_tab' |
  'close_tab' |
  'new_tab' |
  'open_overflow' |
  'restore_recently_closed' |
  'request_delete_recently_closed' |
  'tab_context_action';

export type BrowserLargeScreenTabContextActionId =
  'new_tab_to_right' |
  'move_to_new_window' |
  'reload' |
  'duplicate' |
  'toggle_pin' |
  'toggle_mute' |
  'close' |
  'close_others' |
  'close_to_right';

export interface BrowserLargeScreenTabStripIntent {
  kind: BrowserLargeScreenTabStripIntentKind;
  tabId: string;
  recordId?: string;
  actionId?: BrowserLargeScreenTabContextActionId;
}

export type BrowserLargeScreenNavigationIntentKind =
  'back' |
  'forward' |
  'reload_or_stop' |
  'set_omnibox_editing' |
  'activate_omnibox' |
  'ack_omnibox_focus_request' |
  'update_omnibox_draft' |
  'submit_omnibox' |
  'dismiss_omnibox' |
  'open_suggestion' |
  'delete_history_suggestion' |
  'select_search_engine' |
  'external_app_search' |
  'open_bookmark_popup' |
  'bookmark_popup_action' |
  'open_site_info' |
  'site_info_action' |
  'open_bookmarks' |
  'open_history' |
  'open_settings' |
  'open_settings_target' |
  'open_downloads' |
  'open_user_scripts' |
  'open_app_proxy' |
  'open_saved_pages' |
  'close_active_tab' |
  'open_bookmark_node' |
  'open_history_visit' |
  'open_saved_page_original' |
  'open_user_script_gallery' |
  'update_bookmark_workspace_route' |
  'update_history_workspace_route' |
  'update_settings_workspace_route' |
  'open_web_zoom_dialog' |
  'web_zoom' |
  'open_browser_action';

export interface BrowserLargeScreenNavigationIntent {
  kind: BrowserLargeScreenNavigationIntentKind;
  text: string;
  omniboxEditing?: boolean;
  suggestion?: SearchSuggestion;
  searchEngineId?: SearchEngineId;
  externalAppSearchTargetId?: ExternalAppSearchTargetId;
  actionId?: BrowserBottomAddressPanelActionId;
  bookmarkAction?: BrowserBookmarkFolderSelectionAction;
  siteControlsAction?: BrowserSiteControlsUserAction;
  permissionKind?: SitePermissionKind;
  permissionRule?: SitePermissionRule;
  url?: string;
  title?: string;
  openInNewTab?: boolean;
  tabId?: string;
  zoomAction?: BrowserLargeScreenWebZoomAction;
  focusRequestVersion?: number;
  settingsDestination?: SettingsCenterDestination;
}

export interface BrowserLargeScreenShellIntentFacts {
  windowId: string;
  activeTabId: string;
  loading: boolean;
  selectedSearchEngine: SearchEngineId;
  largeScreenShellActive: boolean;
}

export interface BrowserLargeScreenShellIntentDependencies {
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  tabCloseCoordinator: BrowserTabCloseCoordinator;
  recentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator;
  foregroundTabCreationCoordinator: BrowserForegroundTabCreationCoordinator;
  appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  windowContextCoordinator: BrowserWindowSessionContextPort;
  webHistoryCommandRuntimeCoordinator: BrowserWebHistoryCommandRuntimeCoordinator;
  activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator;
  webTabsController: BrowserWebTabsController;
  addressSubmissionCoordinator: BrowserAddressSubmissionCoordinator;
  searchSuggestionCoordinator: BrowserSearchSuggestionCoordinator;
  searchInvocationHost: BrowserLargeScreenSearchInvocationHost;
  webZoomCoordinator: BrowserLargeScreenWebZoomCoordinator;
  tabHomeCoordinator: BrowserTabHomeCoordinator;
  resolveRootBottomPanelActionApplication: () => BrowserRootBottomPanelFixedActionApplication;
  siteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator;
  homeUrl: string;
  newTabTitle: string;
  openOverflow: () => void;
  dispatchBrowserAction: (actionId: BrowserBottomAddressPanelActionId) => void;
  requestBrowserBack: () => void;
  presentWebZoom: (snapshot: BrowserLargeScreenWebZoomSnapshot) => void;
  updateWebZoom: (snapshot: BrowserLargeScreenWebZoomSnapshot) => void;
  dismissWebZoom: () => void;
  readFacts: () => BrowserLargeScreenShellIntentFacts;
}

/**
 * Narrative entry point for Large-Screen Shell intents.
 *
 * The Tab Strip and navigation toolbar emit stable UI vocabulary here. This
 * application delegates to the existing Tab, Web navigation, Search
 * Invocation, suggestion, and address-submission owners; it does not mutate
 * browser records or Web runtimes directly.
 */
export class BrowserLargeScreenShellIntentApplication {
  private readonly dependencies: BrowserLargeScreenShellIntentDependencies;
  private readonly searchInvocationAdapter: BrowserLargeScreenSearchInvocationAdapter;
  private readonly tabWindowMoveService: BrowserTabWindowMoveService = new BrowserTabWindowMoveService();
  private movingTabIds: Record<string, boolean> = {};
  private webZoomDialogVisible: boolean = false;
  private webZoomDialogDismissTimer: number = -1;

  constructor(dependencies: BrowserLargeScreenShellIntentDependencies) {
    this.dependencies = dependencies;
    this.searchInvocationAdapter = new BrowserLargeScreenSearchInvocationAdapter(
      dependencies.searchSuggestionCoordinator,
      dependencies.searchInvocationHost
    );
  }

  dispatchBookmarkBarAction(action: BrowserDesktopBookmarkBarAction): void {
    if (action.kind === 'open_bookmarks') {
      this.openNativeRoute({ scene: 'bookmarks' });
      return;
    }
    const url = (action.node.url ?? '').trim();
    if (url.length <= 0) {
      return;
    }
    if (action.target === 'background') {
      this.dependencies.appUrlOpenCoordinator.open({
        url: url,
        title: action.node.title,
        intent: 'background_tab',
        source: 'bookmark',
        createOptions: this.dependencies.windowContextCoordinator.resolveCurrentTabSessionBoundary()
      });
      return;
    }
    this.dispatchNavigation({
      kind: 'open_bookmark_node',
      text: '',
      url: url,
      title: action.node.title,
      openInNewTab: action.target === 'new'
    });
  }

  resolveSearchInvocationAdapter(): BrowserLargeScreenSearchInvocationAdapter {
    return this.searchInvocationAdapter;
  }

  handleWebZoomShortcutKey(event: KeyEvent): boolean {
    if (!this.isControlPressed(event)) {
      return false;
    }
    const action = this.resolveWebZoomShortcutAction(event.keyCode);
    if (action === undefined) {
      return false;
    }
    const facts = this.dependencies.readFacts();
    if (!facts.largeScreenShellActive ||
      !this.dependencies.webZoomCoordinator.snapshot(facts.activeTabId).available) {
      return false;
    }
    // Aira 独占 Ctrl +/-/0：Down 时执行绝对缩放并弹出提示，Down/Up 都消费，
    // 避免 ArkWeb 原生再叠加一次缩放导致弹窗数字与页面真实比例不同步。
    if (event.type === KeyType.Down) {
      const result = this.dependencies.webZoomCoordinator.applyShortcut(facts.activeTabId, action);
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s pre-ime action=%{public}s keyCode=%{public}d keyType=%{public}d tab=%{public}s applied=%{public}s percent=%{public}d label=%{public}s outcome=owned-consume',
        WEB_ZOOM_DIAG_PREFIX,
        action,
        event.keyCode,
        event.type,
        facts.activeTabId,
        result.applied ? 'true' : 'false',
        result.snapshot.percent,
        result.snapshot.shortcutNotificationLabel
      );
    }
    return true;
  }

  handleWebZoomDialogDismissed(): void {
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s dialog dismissed-callback logicalVisibleBefore=%{public}s timerActive=%{public}s',
      WEB_ZOOM_DIAG_PREFIX,
      this.webZoomDialogVisible ? 'true' : 'false',
      this.webZoomDialogDismissTimer >= 0 ? 'true' : 'false'
    );
    this.webZoomDialogVisible = false;
    this.clearWebZoomDialogDismissTimer();
  }

  dispose(): void {
    this.dependencies.webZoomCoordinator.dispose();
    this.dismissWebZoomDialog();
  }

  openNativeRoute(request: BrowserNativeTabOpenRequest): void {
    this.dispatchNavigation({
      kind: request.settingsDestination === undefined
        ? this.resolveNativeSceneIntentKind(request.scene)
        : 'open_settings_target',
      text: '',
      settingsDestination: request.settingsDestination
    });
  }

  private resolveNativeSceneIntentKind(
    scene: BrowserNativeTabScene
  ): 'open_bookmarks' | 'open_history' | 'open_settings' | 'open_downloads' | 'open_user_scripts' |
    'open_app_proxy' | 'open_saved_pages' {
    if (scene === 'history') {
      return 'open_history';
    }
    if (scene === 'settings') {
      return 'open_settings';
    }
    if (scene === 'downloads') {
      return 'open_downloads';
    }
    if (scene === 'user_scripts') {
      return 'open_user_scripts';
    }
    if (scene === 'app_proxy') {
      return 'open_app_proxy';
    }
    if (scene === 'saved_pages') {
      return 'open_saved_pages';
    }
    return 'open_bookmarks';
  }

  dispatchTabStrip(intent: BrowserLargeScreenTabStripIntent): void {
    if (intent.kind === 'select_tab') {
      const tabId = intent.tabId.trim();
      if (tabId.length > 0) {
        void this.dependencies.tabSwitchCoordinator.switchToTab(tabId);
      }
      return;
    }
    if (intent.kind === 'close_tab') {
      const tabId = intent.tabId.trim();
      if (tabId.length > 0) {
        void this.dependencies.tabCloseCoordinator.closeDesktopTab(tabId);
      }
      return;
    }
    if (intent.kind === 'new_tab') {
      void this.dependencies.foregroundTabCreationCoordinator.createNewTab({
        initialUrl: this.dependencies.homeUrl,
        initialTitle: this.dependencies.newTabTitle,
        options: this.dependencies.windowContextCoordinator.resolveCurrentTabSessionBoundary(),
        runtimeOptions: {},
        homePresentationMode: 'direct'
      });
      return;
    }
    if (intent.kind === 'restore_recently_closed') {
      const recordId = intent.recordId?.trim() ?? '';
      if (recordId.length > 0) {
        this.dependencies.tabCloseCoordinator.restoreRecentlyClosedRecord(recordId);
      }
      return;
    }
    if (intent.kind === 'request_delete_recently_closed') {
      const recordId = intent.recordId?.trim() ?? '';
      if (recordId.length > 0) {
        this.dependencies.recentlyClosedApplicationCoordinator.handleUserAction({
          type: 'request_delete_record',
          recordId: recordId
        });
      }
      return;
    }
    if (intent.kind === 'tab_context_action' && intent.actionId !== undefined) {
      void this.dispatchTabContextAction(intent.tabId, intent.actionId);
      return;
    }
    this.dependencies.openOverflow();
  }

  private async dispatchTabContextAction(
    tabId: string,
    actionId: BrowserLargeScreenTabContextActionId
  ): Promise<void> {
    const targetTab = this.dependencies.tabSwitchCoordinator.resolveTabSnapshot(tabId);
    if (targetTab === undefined) {
      return;
    }
    if (actionId === 'new_tab_to_right') {
      await this.createTabBeside(targetTab, this.dependencies.homeUrl, this.dependencies.newTabTitle);
      return;
    }
    if (actionId === 'move_to_new_window') {
      await this.moveTabToNewWindow(targetTab);
      return;
    }
    if (actionId === 'reload') {
      if (targetTab.isHome) {
        return;
      }
      await this.dependencies.tabSwitchCoordinator.switchToTab(targetTab.id);
      this.dependencies.activeTabRuntimeRestoreCoordinator.reloadActive('user_manual_reload');
      return;
    }
    if (actionId === 'duplicate') {
      await this.createTabBeside(targetTab, this.resolveDuplicateUrl(targetTab), targetTab.title);
      return;
    }
    if (actionId === 'toggle_pin') {
      this.dependencies.tabSwitchCoordinator.setTabPinned(targetTab.id, !targetTab.pinned);
      return;
    }
    if (actionId === 'toggle_mute') {
      this.dependencies.tabSwitchCoordinator.setTabMuted(targetTab.id, !targetTab.muted);
      return;
    }
    if (actionId === 'close') {
      await this.dependencies.tabCloseCoordinator.closeDesktopTab(targetTab.id);
      return;
    }
    if (actionId === 'close_others') {
      await this.closeRelatedTabs(targetTab, false);
      return;
    }
    if (actionId === 'close_to_right') {
      await this.closeRelatedTabs(targetTab, true);
    }
  }

  private async moveTabToNewWindow(targetTab: BrowserTabState): Promise<void> {
    if (this.movingTabIds[targetTab.id] === true) {
      return;
    }
    this.movingTabIds[targetTab.id] = true;
    try {
      const acknowledgement = await this.tabWindowMoveService.moveToNewWindow(
        this.dependencies.readFacts().windowId,
        targetTab
      );
      if (!acknowledgement.accepted ||
        this.dependencies.tabSwitchCoordinator.resolveTabSnapshot(targetTab.id) === undefined) {
        return;
      }
      await this.dependencies.tabCloseCoordinator.removeDesktopTabAfterWindowMove(targetTab.id);
    } finally {
      this.movingTabIds[targetTab.id] = false;
    }
  }

  private async createTabBeside(targetTab: BrowserTabState, initialUrl: string, initialTitle: string): Promise<void> {
    await this.dependencies.foregroundTabCreationCoordinator.createNewTab({
      initialUrl: initialUrl,
      initialTitle: initialTitle.trim().length > 0 ? initialTitle : initialUrl,
      options: {
        profileId: targetTab.profileId,
        privacyMode: targetTab.privacyMode,
        dataScope: targetTab.dataScope,
        insertAfterTabId: targetTab.id
      },
      runtimeOptions: {},
      homePresentationMode: 'direct'
    });
  }

  private resolveDuplicateUrl(tab: BrowserTabState): string {
    if (tab.isHome && tab.url === this.dependencies.homeUrl) {
      return this.dependencies.homeUrl;
    }
    const historyUrl = tab.navigationIndex >= 0 ? tab.navigationHistory[tab.navigationIndex] ?? '' : '';
    const candidates = [historyUrl, tab.pendingUrl, tab.url, tab.lastGoodUrl, tab.lastRestorableUrl];
    return candidates.find((candidate: string): boolean => candidate.trim().length > 0)?.trim() ??
      this.dependencies.homeUrl;
  }

  private async closeRelatedTabs(targetTab: BrowserTabState, onlyToRight: boolean): Promise<void> {
    const tabs = this.dependencies.tabSwitchCoordinator.resolveTabsSnapshot();
    const targetIndex = tabs.findIndex((tab: BrowserTabState): boolean => tab.id === targetTab.id);
    if (targetIndex < 0) {
      return;
    }
    const candidateTabs = onlyToRight ? tabs.slice(targetIndex + 1) : tabs;
    const targetTabIds = candidateTabs
      .filter((tab: BrowserTabState): boolean => {
        return tab.id !== targetTab.id &&
          tab.profileId === targetTab.profileId &&
          tab.privacyMode === targetTab.privacyMode &&
          tab.dataScope === targetTab.dataScope;
      })
      .map((tab: BrowserTabState): string => tab.id);
    if (targetTabIds.length <= 0) {
      return;
    }
    await this.dependencies.tabSwitchCoordinator.switchToTab(targetTab.id);
    await this.dependencies.tabCloseCoordinator.closeTabsToHomeAfterReveal(
      targetTabIds,
      onlyToRight ? 'desktop_context_close_right' : 'desktop_context_close_others',
      onlyToRight ? '已关闭右侧标签页。' : '已关闭其他标签页。'
    );
  }

  dispatchNavigation(intent: BrowserLargeScreenNavigationIntent): void {
    const facts = this.dependencies.readFacts();
    if (intent.kind === 'set_omnibox_editing') {
      this.dependencies.siteControlsRuntimeCoordinator.setLargeScreenAddressEditing(intent.omniboxEditing === true);
      return;
    }
    if (intent.kind === 'open_bookmarks') {
      this.openNativeTab(BOOKMARK_NATIVE_TAB_URL, BOOKMARK_NATIVE_TAB_TITLE, facts.windowId);
      return;
    }
    if (intent.kind === 'open_history') {
      this.openNativeTab(HISTORY_NATIVE_TAB_URL, HISTORY_NATIVE_TAB_TITLE, facts.windowId);
      return;
    }
    if (intent.kind === 'open_settings') {
      this.openNativeTab(SETTINGS_NATIVE_TAB_URL, SETTINGS_NATIVE_TAB_TITLE, facts.windowId);
      return;
    }
    if (intent.kind === 'open_settings_target' && intent.settingsDestination !== undefined) {
      this.openNativeTab(
        browserNativeTabSceneService.buildSettingsRoute({ destination: intent.settingsDestination }),
        SETTINGS_NATIVE_TAB_TITLE,
        facts.windowId,
        true
      );
      return;
    }
    if (intent.kind === 'open_downloads') {
      this.openNativeTab(DOWNLOADS_NATIVE_TAB_URL, DOWNLOADS_NATIVE_TAB_TITLE, facts.windowId);
      return;
    }
    if (intent.kind === 'open_user_scripts') {
      this.openNativeTab(USER_SCRIPTS_NATIVE_TAB_URL, USER_SCRIPTS_NATIVE_TAB_TITLE, facts.windowId);
      return;
    }
    if (intent.kind === 'open_app_proxy') {
      this.openNativeTab(APP_PROXY_NATIVE_TAB_URL, APP_PROXY_NATIVE_TAB_TITLE, facts.windowId);
      return;
    }
    if (intent.kind === 'open_saved_pages') {
      this.openNativeTab(SAVED_PAGES_NATIVE_TAB_URL, SAVED_PAGES_NATIVE_TAB_TITLE, facts.windowId);
      return;
    }
    if (intent.kind === 'close_active_tab') {
      if (facts.activeTabId.trim().length > 0) {
        void this.dependencies.tabCloseCoordinator.closeDesktopTab(facts.activeTabId);
      }
      return;
    }
    if (intent.kind === 'open_bookmark_popup') {
      BrowserSearchInvocationRuntime.endCurrent(facts.windowId, 'other_surface_selected');
      this.dependencies.resolveRootBottomPanelActionApplication().openLargeScreenBookmark();
      return;
    }
    if (intent.kind === 'bookmark_popup_action' && intent.bookmarkAction !== undefined) {
      this.dependencies.resolveRootBottomPanelActionApplication().handleLargeScreenBookmarkAction(intent.bookmarkAction);
      return;
    }
    if (intent.kind === 'open_site_info') {
      BrowserSearchInvocationRuntime.endCurrent(facts.windowId, 'other_surface_selected');
      this.dependencies.siteControlsRuntimeCoordinator.open();
      return;
    }
    if (intent.kind === 'site_info_action' && intent.siteControlsAction !== undefined) {
      this.dependencies.siteControlsRuntimeCoordinator.handleUserAction(
        intent.siteControlsAction,
        intent.permissionKind,
        intent.permissionRule
      );
      return;
    }
    if (intent.kind === 'open_browser_action' && intent.actionId !== undefined) {
      BrowserSearchInvocationRuntime.endCurrent(facts.windowId, 'other_surface_selected');
      this.dependencies.dispatchBrowserAction(intent.actionId);
      return;
    }
    if (intent.kind === 'open_web_zoom_dialog') {
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s intent kind=open_web_zoom_dialog tab=%{public}s logicalVisible=%{public}s',
        WEB_ZOOM_DIAG_PREFIX,
        facts.activeTabId,
        this.webZoomDialogVisible ? 'true' : 'false'
      );
      BrowserSearchInvocationRuntime.endCurrent(facts.windowId, 'other_surface_selected');
      this.presentOrUpdateWebZoom(
        this.dependencies.webZoomCoordinator.snapshot(facts.activeTabId)
      );
      return;
    }
    if (intent.kind === 'web_zoom' && intent.zoomAction !== undefined) {
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s intent kind=web_zoom action=%{public}s tab=%{public}s logicalVisible=%{public}s',
        WEB_ZOOM_DIAG_PREFIX,
        intent.zoomAction,
        facts.activeTabId,
        this.webZoomDialogVisible ? 'true' : 'false'
      );
      const result = this.dependencies.webZoomCoordinator.apply(facts.activeTabId, intent.zoomAction);
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s intent result action=%{public}s tab=%{public}s percent=%{public}d changed=%{public}s applied=%{public}s reason=%{public}s',
        WEB_ZOOM_DIAG_PREFIX,
        intent.zoomAction,
        result.snapshot.tabId,
        result.snapshot.percent,
        result.changed ? 'true' : 'false',
        result.applied ? 'true' : 'false',
        result.unavailableReason
      );
      this.presentOrUpdateWebZoom(result.snapshot);
      return;
    }
    if (intent.kind === 'open_bookmark_node' && intent.url !== undefined) {
      const targetUrl = intent.url.trim();
      if (targetUrl.length <= 0) {
        return;
      }
      if (intent.openInNewTab === true) {
        void this.dependencies.foregroundTabCreationCoordinator.createNewTab({
          initialUrl: targetUrl,
          initialTitle: intent.title?.trim().length ? intent.title as string : targetUrl,
          options: this.dependencies.windowContextCoordinator.resolveCurrentTabSessionBoundary(),
          runtimeOptions: {}
        });
        return;
      }
      void this.dependencies.addressSubmissionCoordinator.submitAddress(
        targetUrl,
        facts.selectedSearchEngine,
        'configured',
        900
      );
      return;
    }
    if (intent.kind === 'open_history_visit' && intent.url !== undefined) {
      const targetUrl = intent.url.trim();
      if (targetUrl.length <= 0) {
        return;
      }
      if (intent.openInNewTab === true) {
        void this.dependencies.foregroundTabCreationCoordinator.createNewTab({
          initialUrl: targetUrl,
          initialTitle: intent.title?.trim().length ? intent.title as string : targetUrl,
          options: this.dependencies.windowContextCoordinator.resolveCurrentTabSessionBoundary(),
          runtimeOptions: {}
        });
        return;
      }
      void this.dependencies.addressSubmissionCoordinator.submitAddress(
        targetUrl,
        facts.selectedSearchEngine,
        'configured',
        900
      );
      return;
    }
    if (intent.kind === 'open_saved_page_original' && intent.url !== undefined) {
      const targetUrl = intent.url.trim();
      if (targetUrl.length > 0) {
        void this.dependencies.addressSubmissionCoordinator.submitAddress(
          targetUrl,
          facts.selectedSearchEngine,
          'configured',
          900
        );
      }
      return;
    }
    if (intent.kind === 'open_user_script_gallery' && intent.url !== undefined) {
      const targetUrl = intent.url.trim();
      if (targetUrl.length > 0) {
        void this.dependencies.addressSubmissionCoordinator.submitAddress(
          targetUrl,
          facts.selectedSearchEngine,
          'configured',
          900
        );
      }
      return;
    }
    if (intent.kind === 'update_bookmark_workspace_route' && intent.url !== undefined) {
      const tabId = intent.tabId?.trim() ?? facts.activeTabId;
      const routeUrl = intent.url.trim();
      if (tabId.length > 0 && routeUrl.length > 0) {
        this.dependencies.tabSwitchCoordinator.recordNativeTabNavigation(
          tabId,
          routeUrl,
          BOOKMARK_NATIVE_TAB_TITLE
        );
      }
      return;
    }
    if (intent.kind === 'update_history_workspace_route' && intent.url !== undefined) {
      const tabId = intent.tabId?.trim() ?? facts.activeTabId;
      const routeUrl = intent.url.trim();
      if (tabId.length > 0 && routeUrl.length > 0) {
        this.dependencies.tabSwitchCoordinator.recordNativeTabNavigation(
          tabId,
          routeUrl,
          HISTORY_NATIVE_TAB_TITLE
        );
      }
      return;
    }
    if (intent.kind === 'update_settings_workspace_route' && intent.url !== undefined) {
      const tabId = intent.tabId?.trim() ?? facts.activeTabId;
      const routeUrl = intent.url.trim();
      if (tabId.length > 0 && routeUrl.length > 0) {
        this.dependencies.tabSwitchCoordinator.recordNativeTabNavigation(
          tabId,
          routeUrl,
          SETTINGS_NATIVE_TAB_TITLE
        );
      }
      return;
    }
    if (intent.kind === 'back') {
      if (!this.searchInvocationAdapter.snapshot().editing &&
        this.dependencies.tabSwitchCoordinator.navigateNativeTabHistory(facts.activeTabId, 'back')) {
        return;
      }
      this.dependencies.requestBrowserBack();
      return;
    }
    if (intent.kind === 'forward') {
      if (this.dependencies.tabSwitchCoordinator.navigateNativeTabHistory(facts.activeTabId, 'forward')) {
        return;
      }
      this.dependencies.webHistoryCommandRuntimeCoordinator.handleToolbarNavigateForward();
      return;
    }
    if (intent.kind === 'reload_or_stop') {
      if (facts.loading) {
        this.dependencies.webTabsController.stopLoading(facts.activeTabId);
      } else {
        this.dependencies.activeTabRuntimeRestoreCoordinator.reloadActive('user_manual_reload');
      }
      return;
    }
    if (intent.kind === 'activate_omnibox') {
      BrowserSearchInvocationRuntime.reconcileActiveContext(facts.windowId, facts.activeTabId);
      BrowserSearchInvocationRuntime.triggers(facts.windowId).browserChrome.open();
      return;
    }
    if (intent.kind === 'ack_omnibox_focus_request' && intent.focusRequestVersion !== undefined) {
      this.searchInvocationAdapter.acknowledgeFocusRequest(intent.focusRequestVersion);
      return;
    }
    if (intent.kind === 'update_omnibox_draft') {
      const authorityId = BrowserSearchInvocationRuntime.currentAuthorityId(facts.windowId);
      if (BrowserSearchInvocationRuntime.updateDraft(facts.windowId, authorityId, intent.text)) {
        this.searchInvocationAdapter.updateDraft(authorityId, intent.text);
      }
      return;
    }
    if (intent.kind === 'submit_omnibox') {
      BrowserSearchInvocationRuntime.endCurrent(facts.windowId, 'submitted');
      void this.dependencies.addressSubmissionCoordinator.submitAddress(
        intent.text,
        facts.selectedSearchEngine,
        'configured',
        900
      );
      return;
    }
    if (intent.kind === 'dismiss_omnibox') {
      BrowserSearchInvocationRuntime.endCurrent(facts.windowId, 'explicit_exit');
      return;
    }
    if (intent.kind === 'open_suggestion' && intent.suggestion !== undefined) {
      BrowserSearchInvocationRuntime.endCurrent(facts.windowId, 'submitted');
      this.dependencies.searchSuggestionCoordinator.openSuggestion(intent.suggestion);
      return;
    }
    if (intent.kind === 'delete_history_suggestion' && intent.suggestion !== undefined) {
      void this.dependencies.searchSuggestionCoordinator.deleteHistorySuggestion(intent.suggestion);
      return;
    }
    if (intent.kind === 'select_search_engine' && intent.searchEngineId !== undefined) {
      this.dependencies.tabHomeCoordinator.selectSearchEngine(intent.searchEngineId);
      return;
    }
    if (intent.kind === 'external_app_search' && intent.externalAppSearchTargetId !== undefined) {
      BrowserSearchInvocationRuntime.endCurrent(facts.windowId, 'submitted');
      void this.dependencies.addressSubmissionCoordinator.submitExternalAppSearch(
        intent.externalAppSearchTargetId,
        intent.text,
        facts.selectedSearchEngine
      );
    }
  }

  private presentOrUpdateWebZoom(snapshot: BrowserLargeScreenWebZoomSnapshot): void {
    const presentationMode = this.webZoomDialogVisible ? 'update' : 'present';
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s dialog request mode=%{public}s tab=%{public}s percent=%{public}d available=%{public}s logicalVisibleBefore=%{public}s',
      WEB_ZOOM_DIAG_PREFIX,
      presentationMode,
      snapshot.tabId,
      snapshot.percent,
      snapshot.available ? 'true' : 'false',
      this.webZoomDialogVisible ? 'true' : 'false'
    );
    if (this.webZoomDialogVisible) {
      this.dependencies.updateWebZoom(snapshot);
    } else {
      this.webZoomDialogVisible = true;
      this.dependencies.presentWebZoom(snapshot);
    }
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s dialog request-complete mode=%{public}s logicalVisibleAfter=%{public}s',
      WEB_ZOOM_DIAG_PREFIX,
      presentationMode,
      this.webZoomDialogVisible ? 'true' : 'false'
    );
    this.scheduleWebZoomDialogDismiss();
  }

  private isControlPressed(event: KeyEvent): boolean {
    if (event.getModifierKeyState === undefined) {
      return false;
    }
    try {
      return event.getModifierKeyState(['Ctrl']);
    } catch (_error) {
      return false;
    }
  }

  private resolveWebZoomShortcutAction(keyCode: number): BrowserLargeScreenWebZoomAction | undefined {
    if (keyCode === KeyCode.KEYCODE_EQUALS || keyCode === KeyCode.KEYCODE_PLUS ||
      keyCode === KeyCode.KEYCODE_NUMPAD_ADD) {
      return 'increase';
    }
    if (keyCode === KeyCode.KEYCODE_MINUS || keyCode === KeyCode.KEYCODE_NUMPAD_SUBTRACT) {
      return 'decrease';
    }
    if (keyCode === KeyCode.KEYCODE_0 || keyCode === KeyCode.KEYCODE_NUMPAD_0) {
      return 'reset';
    }
    return undefined;
  }

  private scheduleWebZoomDialogDismiss(): void {
    const replacedTimer = this.webZoomDialogDismissTimer >= 0;
    this.clearWebZoomDialogDismissTimer();
    this.webZoomDialogDismissTimer = setTimeout(() => {
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s dialog timer-fired logicalVisible=%{public}s',
        WEB_ZOOM_DIAG_PREFIX,
        this.webZoomDialogVisible ? 'true' : 'false'
      );
      this.webZoomDialogDismissTimer = -1;
      this.dismissWebZoomDialog();
    }, WEB_ZOOM_DIALOG_AUTO_DISMISS_DELAY_MS);
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s dialog timer-scheduled delayMs=%{public}d replaced=%{public}s timerId=%{public}d',
      WEB_ZOOM_DIAG_PREFIX,
      WEB_ZOOM_DIALOG_AUTO_DISMISS_DELAY_MS,
      replacedTimer ? 'true' : 'false',
      this.webZoomDialogDismissTimer
    );
  }

  private clearWebZoomDialogDismissTimer(): void {
    if (this.webZoomDialogDismissTimer < 0) {
      return;
    }
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s dialog timer-cleared timerId=%{public}d',
      WEB_ZOOM_DIAG_PREFIX,
      this.webZoomDialogDismissTimer
    );
    clearTimeout(this.webZoomDialogDismissTimer);
    this.webZoomDialogDismissTimer = -1;
  }

  private dismissWebZoomDialog(): void {
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s dialog dismiss-request logicalVisible=%{public}s timerActive=%{public}s',
      WEB_ZOOM_DIAG_PREFIX,
      this.webZoomDialogVisible ? 'true' : 'false',
      this.webZoomDialogDismissTimer >= 0 ? 'true' : 'false'
    );
    this.clearWebZoomDialogDismissTimer();
    if (!this.webZoomDialogVisible) {
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s dialog dismiss-skipped reason=already-hidden',
        WEB_ZOOM_DIAG_PREFIX
      );
      return;
    }
    this.webZoomDialogVisible = false;
    this.dependencies.dismissWebZoom();
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s dialog dismiss-dispatched logicalVisibleAfter=false',
      WEB_ZOOM_DIAG_PREFIX
    );
  }

  private openNativeTab(url: string, title: string, windowId: string, updateExistingRoute: boolean = false): void {
    void this.openNativeTabCommitted(url, title, windowId, updateExistingRoute);
  }

  private async openNativeTabCommitted(
    url: string,
    title: string,
    windowId: string,
    updateExistingRoute: boolean = false
  ): Promise<boolean> {
    BrowserSearchInvocationRuntime.endCurrent(windowId, 'other_surface_selected');
    const boundary = this.dependencies.windowContextCoordinator.resolveCurrentTabSessionBoundary();
    if (this.dependencies.tabSwitchCoordinator.switchToExistingNativeTab(
      url,
      boundary.privacyMode ?? 'regular',
      updateExistingRoute
    )) {
      return true;
    }
    try {
      await this.dependencies.foregroundTabCreationCoordinator.createNewTab({
        initialUrl: url,
        initialTitle: title,
        options: boundary,
        runtimeOptions: {},
        homePresentationMode: 'direct'
      });
      return true;
    } catch (_error) {
      return false;
    }
  }
}
