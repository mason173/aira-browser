import {
  BrowserDataScope,
  BrowserTabOpenSource,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  TabCrashReason,
  TabDiscardReason,
  TabLaunchContext,
  TabLaunchSourceType,
  TabRecord,
  TabRestoreReason,
  TabRuntimeState,
  WebSessionRestoreType,
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { BrowserRuntimeStateTransitionTable } from '../browser/BrowserRuntimeStateTransitionTable';
import { browserNativeTabSceneService } from '../browser/BrowserNativeTabSceneService';

export interface BrowserTabState {
  id: string;
  profileId: BrowserProfileId;
  title: string;
  url: string;
  isHome: boolean;
  lastActiveAt: number;
  pendingUrl: string;
  navigationHistory: string[];
  navigationIndex: number;
  runtimeState: TabRuntimeState;
  lastError: string;
  lastRestoreReason: TabRestoreReason | '';
  lastDiscardReason: TabDiscardReason | '';
  lastCrashReason: TabCrashReason | '';
  lastLoadedAt: number;
  webStatePath: string;
  webStateUpdatedAt: number;
  scrollOffsetY: number;
  lastGoodUrl: string;
  lastGoodTitle: string;
  lastRestorableUrl: string;
  lastRestorableTitle: string;
  lastRestoreType: WebSessionRestoreType;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  launchContext: TabLaunchContext;
  openerTabId: string;
  openSource: BrowserTabOpenSource;
  openedByNewWindow: boolean;
  // Desktop tab-strip capabilities. `pinned` is persisted (see TabRecord.isPinned)
  // and pins the tab to the leading edge; `muted`/`audible` are runtime-only web
  // audio facts that drive the tab audio indicator and per-webview mute.
  pinned: boolean;
  muted: boolean;
  audible: boolean;
}

export function isBrowserTabTerminalBackAvailable(tab: BrowserTabState | undefined): boolean {
  return tab !== undefined && !tab.isHome;
}

export interface BrowserTabMutationResult {
  tabs: BrowserTabState[];
  activeTabId: string;
  tabSequence: number;
}

export interface BrowserMissingActiveTerminalBackPlan {
  kind: 'missing_active';
  remainingTabCount: number;
}

export interface BrowserHomeTerminalBackPlan {
  kind: 'home';
  closingTab: BrowserTabState;
}

export interface BrowserParentTerminalBackPlan {
  kind: 'parent';
  closingTab: BrowserTabState;
  targetTabId: string;
}

export type BrowserTerminalBackPlan =
  BrowserMissingActiveTerminalBackPlan |
  BrowserHomeTerminalBackPlan |
  BrowserParentTerminalBackPlan;

export interface BrowserTabRestoreResult extends BrowserTabMutationResult {
  activeTab?: BrowserTabState;
}

export interface BrowserTabRuntimePatch {
  profileId?: BrowserProfileId;
  title?: string;
  url?: string;
  isHome?: boolean;
  lastActiveAt?: number;
  pendingUrl?: string;
  navigationHistory?: string[];
  navigationIndex?: number;
  runtimeState?: TabRuntimeState;
  lastError?: string;
  lastRestoreReason?: TabRestoreReason | '';
  lastDiscardReason?: TabDiscardReason | '';
  lastCrashReason?: TabCrashReason | '';
  lastLoadedAt?: number;
  webStatePath?: string;
  webStateUpdatedAt?: number;
  scrollOffsetY?: number;
  lastGoodUrl?: string;
  lastGoodTitle?: string;
  lastRestorableUrl?: string;
  lastRestorableTitle?: string;
  lastRestoreType?: WebSessionRestoreType;
  privacyMode?: BrowserSessionPrivacyMode;
  dataScope?: BrowserDataScope;
  launchContext?: TabLaunchContext;
  openerTabId?: string;
  openSource?: BrowserTabOpenSource;
  openedByNewWindow?: boolean;
  pinned?: boolean;
  muted?: boolean;
  audible?: boolean;
}

export interface BrowserCreateTabOptions {
  profileId?: BrowserProfileId;
  privacyMode?: BrowserSessionPrivacyMode;
  dataScope?: BrowserDataScope;
  launchContext?: TabLaunchContext;
  openerTabId?: string;
  openSource?: BrowserTabOpenSource;
  openedByNewWindow?: boolean;
  insertAfterTabId?: string;
}

const DEFAULT_WINDOW_ID = 'window-main';
const TAB_ID_SAFE_WINDOW_MAX_LENGTH = 80;

/**
 * Window-Session-facing tab capability surface.
 *
 * The concrete TabManager remains the single policy owner, while Window
 * Session consumers receive this shaped contract instead of the concrete
 * implementation. Keep BrowserTabState/TabRecord as data models here; this
 * interface is the only object capability needed by browser coordinators.
 */
export interface BrowserTabManagerPort {
  setWindowId(windowId: string): void;
  createBootstrapTab(options?: BrowserCreateTabOptions): TabRecord;
  createWindowHomeTab(timestamp?: number, options?: BrowserCreateTabOptions): BrowserTabState;
  createHomeTab(id: string, timestamp?: number, options?: BrowserCreateTabOptions): BrowserTabState;
  createTab(
    tabs: BrowserTabState[],
    tabSequence: number,
    initialUrl?: string,
    initialTitle?: string,
    options?: BrowserCreateTabOptions
  ): BrowserTabMutationResult;
  createBackgroundTab(
    tabs: BrowserTabState[],
    activeTabId: string,
    tabSequence: number,
    initialUrl?: string,
    initialTitle?: string,
    options?: BrowserCreateTabOptions
  ): BrowserTabMutationResult;
  switchToTab(tabs: BrowserTabState[], activeTabId: string, targetTabId: string): BrowserTabMutationResult;
  closeTab(tabs: BrowserTabState[], activeTabId: string, targetTabId: string): BrowserTabMutationResult;
  buildTerminalBackPlan(tabs: BrowserTabState[], activeTabId: string): BrowserTerminalBackPlan;
  closeActiveTabToHome(tabs: BrowserTabState[], activeTabId: string): BrowserTabMutationResult;
  closeTabsToHome(tabs: BrowserTabState[], activeTabId: string, targetTabIds: string[]): BrowserTabMutationResult;
  markActiveTabAsHome(tabs: BrowserTabState[], activeTabId: string): BrowserTabState[];
  updateActiveTab(tabs: BrowserTabState[], activeTabId: string, patch: BrowserTabRuntimePatch): BrowserTabState[];
  updateTab(tabs: BrowserTabState[], targetTabId: string, patch: BrowserTabRuntimePatch): BrowserTabState[];
  recordActiveNavigation(tabs: BrowserTabState[], activeTabId: string, url: string, title?: string): BrowserTabState[];
  recordNavigationForTab(tabs: BrowserTabState[], targetTabId: string, url: string, title?: string): BrowserTabState[];
  restoreTabs(records: TabRecord[], emptyStateOptions?: BrowserCreateTabOptions): BrowserTabRestoreResult;
  serializeTabs(tabs: BrowserTabState[], activeTabId: string): TabRecord[];
  getActiveTab(tabs: BrowserTabState[], activeTabId: string): BrowserTabState | undefined;
  getTab(tabs: BrowserTabState[], tabId: string): BrowserTabState | undefined;
  applyRuntimeStates(tabs: BrowserTabState[], states: Record<string, TabRuntimeState>): BrowserTabState[];
  setTabPinned(tabs: BrowserTabState[], targetTabId: string, pinned: boolean): BrowserTabState[];
}

export class TabManager implements BrowserTabManagerPort {
  private homeUrl: string;
  private windowId: string;
  private runtimeStateTransitionTable: BrowserRuntimeStateTransitionTable = new BrowserRuntimeStateTransitionTable();

  constructor(homeUrl: string = 'aira://home', windowId: string = DEFAULT_WINDOW_ID) {
    this.homeUrl = homeUrl;
    this.windowId = windowId;
  }

  setWindowId(windowId: string): void {
    const normalizedWindowId = windowId.trim();
    if (normalizedWindowId.length === 0) {
      return;
    }
    this.windowId = normalizedWindowId;
  }

  createBootstrapTab(options: BrowserCreateTabOptions = {}): TabRecord {
    const timestamp = Date.now();
    const homeTab = this.createWindowHomeTab(timestamp, options);
    return this.serializeTabs([homeTab], homeTab.id)[0];
  }

  createWindowHomeTab(timestamp: number = Date.now(), options: BrowserCreateTabOptions = {}): BrowserTabState {
    return this.createHomeTab(this.createScopedTabId(timestamp, 1), timestamp, options);
  }

  createHomeTab(
    id: string,
    timestamp: number = Date.now(),
    options: BrowserCreateTabOptions = {}
  ): BrowserTabState {
    const privacyMode = normalizeBrowserSessionPrivacyMode(options.privacyMode);
    const dataScope = normalizeBrowserDataScope(options.dataScope, privacyMode);
    const profileId = normalizeBrowserProfileId(options.profileId);
    return {
      id: id,
      profileId: profileId,
      title: '新标签页',
      url: this.homeUrl,
      isHome: true,
      lastActiveAt: timestamp,
      pendingUrl: '',
      navigationHistory: [],
      navigationIndex: -1,
      runtimeState: 'active',
      lastError: '',
      lastRestoreReason: '',
      lastDiscardReason: '',
      lastCrashReason: '',
      lastLoadedAt: timestamp,
      webStatePath: '',
      webStateUpdatedAt: 0,
      scrollOffsetY: 0,
      lastGoodUrl: '',
      lastGoodTitle: '',
      lastRestorableUrl: '',
      lastRestorableTitle: '',
      lastRestoreType: 'none',
      privacyMode: privacyMode,
      dataScope: dataScope,
      launchContext: this.normalizeLaunchContext(options.launchContext),
      openerTabId: this.normalizeTabId(options.openerTabId),
      openSource: this.normalizeOpenSource(options.openSource),
      openedByNewWindow: options.openedByNewWindow === true,
      pinned: false,
      muted: false,
      audible: false
    };
  }

  createTab(
    tabs: BrowserTabState[],
    tabSequence: number,
    initialUrl: string = this.homeUrl,
    initialTitle: string = '新标签页',
    options: BrowserCreateTabOptions = {}
  ): BrowserTabMutationResult {
    const nextSequence = tabSequence + 1;
    const now = Date.now();
    const tabId = this.createScopedTabId(now, nextSequence);
    const isHomeUrl = initialUrl === this.homeUrl;
    const isNativeTab = browserNativeTabSceneService.isNativeTabUrl(initialUrl);
    const isHome = isHomeUrl || isNativeTab;
    const tabUrl = isHomeUrl ? this.homeUrl : initialUrl;
    const navigationTarget = isHomeUrl ? '' : initialUrl;
    const pendingUrl = isNativeTab ? '' : navigationTarget;
    const profileId = normalizeBrowserProfileId(options.profileId);
    const privacyMode = normalizeBrowserSessionPrivacyMode(options.privacyMode);
    const dataScope = normalizeBrowserDataScope(options.dataScope, privacyMode);
    const tab: BrowserTabState = {
      id: tabId,
      profileId: profileId,
      title: initialTitle,
      url: tabUrl,
      isHome: isHome,
      lastActiveAt: now,
      pendingUrl: pendingUrl,
      navigationHistory: navigationTarget.length > 0 ? [navigationTarget] : [],
      navigationIndex: navigationTarget.length > 0 ? 0 : -1,
      runtimeState: isHome ? 'active' : 'loading',
      lastError: '',
      lastRestoreReason: '',
      lastDiscardReason: '',
      lastCrashReason: '',
      lastLoadedAt: navigationTarget.length > 0 ? 0 : now,
      webStatePath: '',
      webStateUpdatedAt: 0,
      scrollOffsetY: 0,
      lastGoodUrl: isNativeTab ? '' : navigationTarget,
      lastGoodTitle: isNativeTab || navigationTarget.length <= 0 ? '' : initialTitle,
      lastRestorableUrl: isNativeTab ? '' : navigationTarget,
      lastRestorableTitle: isNativeTab || navigationTarget.length <= 0 ? '' : initialTitle,
      lastRestoreType: 'none',
      privacyMode: privacyMode,
      dataScope: dataScope,
      launchContext: this.normalizeLaunchContext(options.launchContext),
      openerTabId: this.normalizeTabId(options.openerTabId),
      openSource: this.normalizeOpenSource(options.openSource),
      openedByNewWindow: options.openedByNewWindow === true,
      pinned: false,
      muted: false,
      audible: false
    };
    return {
      tabs: this.insertCreatedTab(
        this.deactivateCurrentActiveTab(tabs, activeTabIdFromTabs(tabs), now),
        tab,
        options.insertAfterTabId
      ),
      activeTabId: tabId,
      tabSequence: nextSequence
    };
  }

  createBackgroundTab(
    tabs: BrowserTabState[],
    activeTabId: string,
    tabSequence: number,
    initialUrl: string = this.homeUrl,
    initialTitle: string = '新标签页',
    options: BrowserCreateTabOptions = {}
  ): BrowserTabMutationResult {
    const nextSequence = tabSequence + 1;
    const now = Date.now();
    const tabId = this.createScopedTabId(now, nextSequence);
    const isHomeUrl = initialUrl === this.homeUrl;
    const isNativeTab = browserNativeTabSceneService.isNativeTabUrl(initialUrl);
    const isHome = isHomeUrl || isNativeTab;
    const tabUrl = isHomeUrl ? this.homeUrl : initialUrl;
    const navigationTarget = isHomeUrl ? '' : initialUrl;
    const pendingUrl = isNativeTab ? '' : navigationTarget;
    const profileId = normalizeBrowserProfileId(options.profileId);
    const privacyMode = normalizeBrowserSessionPrivacyMode(options.privacyMode);
    const dataScope = normalizeBrowserDataScope(options.dataScope, privacyMode);
    const tab: BrowserTabState = {
      id: tabId,
      profileId: profileId,
      title: initialTitle,
      url: tabUrl,
      isHome: isHome,
      lastActiveAt: now,
      pendingUrl: pendingUrl,
      navigationHistory: navigationTarget.length > 0 ? [navigationTarget] : [],
      navigationIndex: navigationTarget.length > 0 ? 0 : -1,
      runtimeState: isHome ? 'background' : 'suspended',
      lastError: '',
      lastRestoreReason: '',
      lastDiscardReason: '',
      lastCrashReason: '',
      lastLoadedAt: navigationTarget.length > 0 ? 0 : now,
      webStatePath: '',
      webStateUpdatedAt: 0,
      scrollOffsetY: 0,
      lastGoodUrl: isNativeTab ? '' : navigationTarget,
      lastGoodTitle: isNativeTab || navigationTarget.length <= 0 ? '' : initialTitle,
      lastRestorableUrl: isNativeTab ? '' : navigationTarget,
      lastRestorableTitle: isNativeTab || navigationTarget.length <= 0 ? '' : initialTitle,
      lastRestoreType: 'none',
      privacyMode: privacyMode,
      dataScope: dataScope,
      launchContext: this.normalizeLaunchContext(options.launchContext),
      openerTabId: this.normalizeTabId(options.openerTabId),
      openSource: this.normalizeOpenSource(options.openSource),
      openedByNewWindow: options.openedByNewWindow === true,
      pinned: false,
      muted: false,
      audible: false
    };
    return {
      tabs: this.insertCreatedTab(tabs, tab, options.insertAfterTabId),
      activeTabId: activeTabId,
      tabSequence: nextSequence
    };
  }

  private insertCreatedTab(
    tabs: BrowserTabState[],
    tab: BrowserTabState,
    insertAfterTabId: string | undefined
  ): BrowserTabState[] {
    const normalizedInsertAfterTabId = this.normalizeTabId(insertAfterTabId);
    if (normalizedInsertAfterTabId.length <= 0) {
      return tabs.concat([tab]);
    }
    const targetIndex = tabs.findIndex((candidate: BrowserTabState): boolean => {
      return candidate.id === normalizedInsertAfterTabId;
    });
    if (targetIndex < 0) {
      return tabs.concat([tab]);
    }
    return tabs.slice(0, targetIndex + 1).concat([tab]).concat(tabs.slice(targetIndex + 1));
  }

  switchToTab(tabs: BrowserTabState[], activeTabId: string, targetTabId: string): BrowserTabMutationResult {
    const now = Date.now();
    return {
      tabs: tabs.map((tab: BrowserTabState) => {
        if (tab.id === targetTabId) {
          return this.cloneTabState(tab, now, this.resolveForegroundRuntimeState(tab));
        }
        if (tab.id === activeTabId) {
          return this.cloneTabState(tab, now, this.resolveBackgroundRuntimeState(tab));
        }
        return tab;
      }),
      activeTabId: targetTabId,
      tabSequence: this.resolveTabSequence(tabs)
    };
  }

  closeTab(tabs: BrowserTabState[], activeTabId: string, targetTabId: string): BrowserTabMutationResult {
    const remainingTabs = tabs.filter((tab: BrowserTabState) => tab.id !== targetTabId);
    if (remainingTabs.length === 0) {
      return {
        tabs: [],
        activeTabId: '',
        tabSequence: this.resolveTabSequence(remainingTabs)
      };
    }

    let nextActiveTabId = activeTabId;
    if (targetTabId === activeTabId) {
      nextActiveTabId = remainingTabs[remainingTabs.length - 1].id;
    }

    return {
      tabs: remainingTabs.map((tab: BrowserTabState) => {
        if (tab.id !== nextActiveTabId) {
          return tab;
        }
        return this.cloneTabState(tab, Date.now(), this.resolveForegroundRuntimeState(tab));
      }),
      activeTabId: nextActiveTabId,
      tabSequence: this.resolveTabSequence(remainingTabs)
    };
  }

  buildTerminalBackPlan(tabs: BrowserTabState[], activeTabId: string): BrowserTerminalBackPlan {
    const activeTab = tabs.find((tab: BrowserTabState) => tab.id === activeTabId);
    if (activeTab === undefined) {
      return {
        kind: 'missing_active',
        remainingTabCount: tabs.length
      };
    }

    const openerTabId = this.normalizeTabId(activeTab.openerTabId);
    const hasOpenerTab = openerTabId.length > 0 && tabs.some((tab: BrowserTabState) => {
      return tab.id !== activeTabId && tab.id === openerTabId;
    });
    if (hasOpenerTab) {
      return {
        kind: 'parent',
        closingTab: activeTab,
        targetTabId: openerTabId
      };
    }

    return {
      kind: 'home',
      closingTab: activeTab
    };
  }

  closeActiveTabToHome(tabs: BrowserTabState[], activeTabId: string): BrowserTabMutationResult {
    const now = Date.now();
    const remainingTabs = tabs.filter((tab: BrowserTabState) => tab.id !== activeTabId);
    return {
      tabs: remainingTabs.map((tab: BrowserTabState) => {
        if (tab.runtimeState !== 'active' && tab.runtimeState !== 'loading' && tab.runtimeState !== 'restoring') {
          return tab;
        }
        return this.cloneTabState(tab, now, this.resolveBackgroundRuntimeState(tab));
      }),
      activeTabId: '',
      tabSequence: this.resolveTabSequence(remainingTabs)
    };
  }

  closeTabsToHome(tabs: BrowserTabState[], activeTabId: string, targetTabIds: string[]): BrowserTabMutationResult {
    const now = Date.now();
    const remainingTabs = tabs.filter((tab: BrowserTabState) => !targetTabIds.includes(tab.id));
    const nextActiveTabId = targetTabIds.includes(activeTabId) ? '' : activeTabId;
    return {
      tabs: remainingTabs.map((tab: BrowserTabState) => {
        if (tab.runtimeState !== 'active' && tab.runtimeState !== 'loading' && tab.runtimeState !== 'restoring') {
          return tab;
        }
        return this.cloneTabState(tab, now, this.resolveBackgroundRuntimeState(tab));
      }),
      activeTabId: nextActiveTabId,
      tabSequence: this.resolveTabSequence(remainingTabs)
    };
  }

  markActiveTabAsHome(tabs: BrowserTabState[], activeTabId: string): BrowserTabState[] {
    return tabs.filter((tab: BrowserTabState) => tab.id !== activeTabId);
  }

  updateActiveTab(tabs: BrowserTabState[], activeTabId: string, patch: BrowserTabRuntimePatch): BrowserTabState[] {
    return this.updateTab(tabs, activeTabId, patch);
  }

  updateTab(tabs: BrowserTabState[], targetTabId: string, patch: BrowserTabRuntimePatch): BrowserTabState[] {
    return tabs.map((tab: BrowserTabState) => {
      if (tab.id !== targetTabId) {
        return tab;
      }
      const nextHistory = patch.navigationHistory ?? tab.navigationHistory;
      const nextIsHome = patch.isHome ?? tab.isHome;
      const requestedProfileId = normalizeBrowserProfileId(patch.profileId ?? tab.profileId);
      const requestedPrivacyMode = normalizeBrowserSessionPrivacyMode(patch.privacyMode ?? tab.privacyMode);
      const requestedDataScope = normalizeBrowserDataScope(patch.dataScope ?? tab.dataScope, requestedPrivacyMode);
      const boundaryPatchCrossesProfile = this.doesRuntimePatchCrossProfileBoundary(
        tab,
        patch,
        requestedProfileId,
        requestedPrivacyMode,
        requestedDataScope
      );
      const nextProfileId = boundaryPatchCrossesProfile ? tab.profileId : requestedProfileId;
      const nextPrivacyMode = boundaryPatchCrossesProfile ? tab.privacyMode : requestedPrivacyMode;
      const nextDataScope = boundaryPatchCrossesProfile ? tab.dataScope : requestedDataScope;
      return {
        id: tab.id,
        profileId: nextProfileId,
        title: patch.title ?? tab.title,
        url: patch.url ?? tab.url,
        isHome: nextIsHome,
        lastActiveAt: patch.lastActiveAt ?? Date.now(),
        pendingUrl: patch.pendingUrl ?? tab.pendingUrl,
        navigationHistory: nextHistory.slice(),
        navigationIndex: patch.navigationIndex ?? tab.navigationIndex,
        runtimeState: patch.runtimeState ?? tab.runtimeState,
        lastError: patch.lastError ?? tab.lastError,
        lastRestoreReason: patch.lastRestoreReason ?? tab.lastRestoreReason,
        lastDiscardReason: patch.lastDiscardReason ?? tab.lastDiscardReason,
        lastCrashReason: patch.lastCrashReason ?? tab.lastCrashReason,
        lastLoadedAt: patch.lastLoadedAt ?? tab.lastLoadedAt,
        webStatePath: patch.webStatePath ?? tab.webStatePath,
        webStateUpdatedAt: patch.webStateUpdatedAt ?? tab.webStateUpdatedAt,
        scrollOffsetY: patch.scrollOffsetY ?? tab.scrollOffsetY,
        lastGoodUrl: patch.lastGoodUrl ?? tab.lastGoodUrl,
        lastGoodTitle: patch.lastGoodTitle ?? tab.lastGoodTitle,
        lastRestorableUrl: patch.lastRestorableUrl ?? tab.lastRestorableUrl,
        lastRestorableTitle: patch.lastRestorableTitle ?? tab.lastRestorableTitle,
        lastRestoreType: patch.lastRestoreType ?? tab.lastRestoreType,
        privacyMode: nextPrivacyMode,
        dataScope: nextDataScope,
        launchContext: this.normalizeLaunchContext(patch.launchContext ?? tab.launchContext),
        openerTabId: this.normalizeTabId(patch.openerTabId ?? tab.openerTabId),
        openSource: this.normalizeOpenSource(patch.openSource ?? tab.openSource),
        openedByNewWindow: patch.openedByNewWindow ?? tab.openedByNewWindow,
        pinned: patch.pinned ?? tab.pinned,
        muted: patch.muted ?? tab.muted,
        audible: patch.audible ?? tab.audible
      };
    });
  }

  private doesRuntimePatchCrossProfileBoundary(
    tab: BrowserTabState,
    patch: BrowserTabRuntimePatch,
    requestedProfileId: BrowserProfileId,
    requestedPrivacyMode: BrowserSessionPrivacyMode,
    requestedDataScope: BrowserDataScope
  ): boolean {
    const hasBoundaryPatch = patch.profileId !== undefined ||
      patch.privacyMode !== undefined ||
      patch.dataScope !== undefined;
    if (!hasBoundaryPatch) {
      return false;
    }
    return requestedProfileId !== tab.profileId ||
      requestedPrivacyMode !== tab.privacyMode ||
      requestedDataScope !== tab.dataScope;
  }

  recordActiveNavigation(tabs: BrowserTabState[], activeTabId: string, url: string, title?: string): BrowserTabState[] {
    return this.recordNavigationForTab(tabs, activeTabId, url, title);
  }

  recordNavigationForTab(tabs: BrowserTabState[], targetTabId: string, url: string, title?: string): BrowserTabState[] {
    return tabs.map((tab: BrowserTabState) => {
      if (tab.id !== targetTabId) {
        return tab;
      }

      const normalizedUrl = url.trim();
      if (normalizedUrl.length === 0 || normalizedUrl === this.homeUrl) {
        return this.createTabState(
          tab.id,
          tab.profileId,
          title ?? tab.title,
          normalizedUrl.length > 0 ? normalizedUrl : tab.url,
          normalizedUrl === this.homeUrl,
          Date.now(),
          normalizedUrl === this.homeUrl ? '' : tab.pendingUrl,
          tab.navigationHistory,
          tab.navigationIndex,
          normalizedUrl === this.homeUrl ? 'active' : tab.runtimeState,
          '',
          tab.lastRestoreReason,
          tab.lastDiscardReason,
          '',
          normalizedUrl === this.homeUrl ? Date.now() : tab.lastLoadedAt,
          normalizedUrl === this.homeUrl ? '' : tab.webStatePath,
          normalizedUrl === this.homeUrl ? 0 : tab.webStateUpdatedAt,
          normalizedUrl === this.homeUrl ? 0 : tab.scrollOffsetY,
          normalizedUrl === this.homeUrl ? '' : tab.lastGoodUrl,
          normalizedUrl === this.homeUrl ? '' : tab.lastGoodTitle,
          normalizedUrl === this.homeUrl ? '' : tab.lastRestorableUrl,
          normalizedUrl === this.homeUrl ? '' : tab.lastRestorableTitle,
          normalizedUrl === this.homeUrl ? 'none' : tab.lastRestoreType,
          tab.privacyMode,
          tab.dataScope,
          normalizedUrl === this.homeUrl ? this.createEmptyLaunchContext() : tab.launchContext,
          tab.openerTabId,
          tab.openSource,
          tab.openedByNewWindow,
          tab.pinned,
          tab.muted,
          tab.audible
        );
      }

      let nextHistory = tab.navigationHistory.slice();
      let nextIndex = tab.navigationIndex;
      if (nextIndex >= 0 && nextIndex < nextHistory.length &&
        this.normalizeNavigationTarget(nextHistory[nextIndex]) === this.normalizeNavigationTarget(normalizedUrl)) {
        nextHistory[nextIndex] = normalizedUrl;
      } else {
        const retainedHistory = nextIndex >= 0 ? nextHistory.slice(0, nextIndex + 1) : [];
        nextHistory = retainedHistory.concat([normalizedUrl]);
        nextIndex = nextHistory.length - 1;
      }

      const isNativeTab = browserNativeTabSceneService.isNativeTabUrl(normalizedUrl);
      return this.createTabState(
        tab.id,
        tab.profileId,
        title ?? tab.title,
        normalizedUrl,
        isNativeTab,
        Date.now(),
        isNativeTab ? '' : normalizedUrl,
        nextHistory,
        nextIndex,
        'active',
        '',
        tab.lastRestoreReason,
        tab.lastDiscardReason,
        '',
        Date.now(),
        isNativeTab ? '' : tab.webStatePath,
        isNativeTab ? 0 : tab.webStateUpdatedAt,
        isNativeTab ? 0 : tab.scrollOffsetY,
        isNativeTab ? '' : tab.lastGoodUrl,
        isNativeTab ? '' : tab.lastGoodTitle,
        isNativeTab ? '' : tab.lastRestorableUrl,
        isNativeTab ? '' : tab.lastRestorableTitle,
        isNativeTab ? 'none' : tab.lastRestoreType,
        tab.privacyMode,
        tab.dataScope,
        tab.launchContext,
        tab.openerTabId,
        tab.openSource,
        tab.openedByNewWindow,
        tab.pinned,
        tab.muted,
        tab.audible
      );
    });
  }

  restoreTabs(records: TabRecord[], emptyStateOptions: BrowserCreateTabOptions = {}): BrowserTabRestoreResult {
    if (records.length === 0) {
      const homeTab = this.createWindowHomeTab(Date.now(), emptyStateOptions);
      return {
        tabs: [homeTab],
        activeTabId: homeTab.id,
        tabSequence: this.resolveTabSequence([homeTab]),
        activeTab: homeTab
      };
    }

    const uniqueRecords = this.deduplicateTabRecords(records);
    const activeRecord = uniqueRecords.find((record: TabRecord) => record.isActive) ?? uniqueRecords[0];
    const tabs = uniqueRecords.map((record: TabRecord) => {
      const tab = this.fromRecord(record);
      if (record.id === activeRecord.id) {
        return this.cloneTabState(tab, tab.lastActiveAt, this.resolveForegroundRuntimeState(tab));
      }
      if (tab.runtimeState === 'error') {
        return tab;
      }
      return this.cloneTabState(tab, tab.lastActiveAt, this.resolveBackgroundRuntimeState(tab));
    });
    return this.ensureActiveRestoreBoundary({
      tabs: tabs,
      activeTabId: activeRecord.id,
      tabSequence: this.resolveTabSequence(tabs),
      activeTab: tabs.find((tab: BrowserTabState) => tab.id === activeRecord.id)
    }, emptyStateOptions);
  }

  private ensureActiveRestoreBoundary(
    restored: BrowserTabRestoreResult,
    startupBoundaryOptions: BrowserCreateTabOptions
  ): BrowserTabRestoreResult {
    if (startupBoundaryOptions.privacyMode !== 'private') {
      return restored;
    }
    const requiredProfileId = normalizeBrowserProfileId(startupBoundaryOptions.profileId);
    const requiredPrivacyMode = normalizeBrowserSessionPrivacyMode(startupBoundaryOptions.privacyMode);
    const requiredDataScope = normalizeBrowserDataScope(startupBoundaryOptions.dataScope, requiredPrivacyMode);
    if (restored.activeTab?.profileId === requiredProfileId &&
      restored.activeTab.privacyMode === requiredPrivacyMode &&
      restored.activeTab.dataScope === requiredDataScope) {
      return restored;
    }
    const created = this.createTab(
      restored.tabs,
      restored.tabSequence,
      this.homeUrl,
      '新标签页',
      startupBoundaryOptions
    );
    return {
      tabs: created.tabs,
      activeTabId: created.activeTabId,
      tabSequence: created.tabSequence,
      activeTab: created.tabs.find((tab: BrowserTabState) => tab.id === created.activeTabId)
    };
  }

  serializeTabs(tabs: BrowserTabState[], activeTabId: string): TabRecord[] {
    return tabs.map((tab: BrowserTabState, index: number) => {
      const record: TabRecord = {
        id: tab.id,
        profileId: tab.profileId,
        windowId: this.windowId,
        title: tab.title,
        url: tab.url,
        isActive: tab.id === activeTabId,
        isPinned: tab.pinned,
        lastActiveAt: tab.lastActiveAt,
        tabOrder: index,
        isHome: tab.isHome,
        pendingUrl: tab.pendingUrl,
        navigationHistory: tab.navigationHistory.slice(),
        navigationIndex: tab.navigationIndex,
        runtimeState: tab.runtimeState,
        lastError: tab.lastError,
        lastLoadedAt: tab.lastLoadedAt,
        webStatePath: tab.webStatePath,
        webStateUpdatedAt: tab.webStateUpdatedAt,
        scrollOffsetY: tab.scrollOffsetY,
        lastGoodUrl: tab.lastGoodUrl,
        lastGoodTitle: tab.lastGoodTitle,
        lastRestorableUrl: tab.lastRestorableUrl,
        lastRestorableTitle: tab.lastRestorableTitle,
        lastRestoreType: tab.lastRestoreType,
        privacyMode: tab.privacyMode,
        dataScope: tab.dataScope,
        launchSourceType: tab.launchContext.sourceType,
        launchSourceId: tab.launchContext.sourceId,
        launchSourceUrl: tab.launchContext.sourceUrl,
        launchKey: tab.launchContext.key,
        openerTabId: tab.openerTabId,
        openSource: tab.openSource,
        openedByNewWindow: tab.openedByNewWindow
      };
      if (tab.lastRestoreReason.length > 0) {
        record.lastRestoreReason = this.toPersistedRestoreReason(tab.lastRestoreReason);
      }
      if (tab.lastDiscardReason.length > 0) {
        record.lastDiscardReason = this.toPersistedDiscardReason(tab.lastDiscardReason);
      }
      if (tab.lastCrashReason.length > 0) {
        record.lastCrashReason = this.toPersistedCrashReason(tab.lastCrashReason);
      }
      return record;
    });
  }

  getActiveTab(tabs: BrowserTabState[], activeTabId: string): BrowserTabState | undefined {
    return this.getTab(tabs, activeTabId);
  }

  getTab(tabs: BrowserTabState[], tabId: string): BrowserTabState | undefined {
    return tabs.find((tab: BrowserTabState) => tab.id === tabId);
  }

  applyRuntimeStates(tabs: BrowserTabState[], states: Record<string, TabRuntimeState>): BrowserTabState[] {
    return tabs.map((tab: BrowserTabState) => {
      const nextState = states[tab.id];
      if (nextState === undefined || nextState === tab.runtimeState) {
        return tab;
      }
      return this.cloneTabState(tab, tab.lastActiveAt, nextState);
    });
  }

  /**
   * Toggles a tab's pinned flag and re-partitions so pinned tabs keep the
   * leading edge. The stable partition preserves relative order inside each
   * group, so a freshly pinned tab lands at the end of the pinned run and a
   * freshly unpinned tab lands at the head of the unpinned run — matching the
   * desktop-browser convention. No-op when the tab is missing or unchanged.
   */
  setTabPinned(tabs: BrowserTabState[], targetTabId: string, pinned: boolean): BrowserTabState[] {
    const normalizedTargetTabId = this.normalizeTabId(targetTabId);
    if (normalizedTargetTabId.length === 0) {
      return tabs;
    }
    const target = tabs.find((tab: BrowserTabState): boolean => tab.id === normalizedTargetTabId);
    if (target === undefined || target.pinned === pinned) {
      return tabs;
    }
    const updated = this.updateTab(tabs, normalizedTargetTabId, {
      pinned: pinned,
      lastActiveAt: target.lastActiveAt
    });
    return this.partitionPinnedFirst(updated);
  }

  private partitionPinnedFirst(tabs: BrowserTabState[]): BrowserTabState[] {
    const pinnedTabs: BrowserTabState[] = [];
    const unpinnedTabs: BrowserTabState[] = [];
    tabs.forEach((tab: BrowserTabState): void => {
      if (tab.pinned) {
        pinnedTabs.push(tab);
      } else {
        unpinnedTabs.push(tab);
      }
    });
    return pinnedTabs.concat(unpinnedTabs);
  }

  private deduplicateTabRecords(records: TabRecord[]): TabRecord[] {
    const seenIds = new Set<string>();
    const results: TabRecord[] = [];
    records.forEach((record: TabRecord) => {
      if (record.id.length <= 0 || seenIds.has(record.id)) {
        return;
      }
      seenIds.add(record.id);
      results.push(record);
    });
    return results;
  }

  private fromRecord(record: TabRecord): BrowserTabState {
    const isHome = record.isHome === true || record.url === this.homeUrl ||
      browserNativeTabSceneService.isNativeTabUrl(record.url);
    const history = this.normalizeNavigationHistory(
      record.navigationHistory,
      record.url,
      record.url === this.homeUrl
    );
    const navigationIndex = this.normalizeNavigationIndex(record.navigationIndex, history.length);
    const profileId = normalizeBrowserProfileId(record.profileId);
    const privacyMode = normalizeBrowserSessionPrivacyMode(record.privacyMode);
    const dataScope = normalizeBrowserDataScope(record.dataScope, privacyMode);
    return {
      id: record.id,
      profileId: profileId,
      title: record.title.length > 0 ? record.title : (isHome ? '新标签页' : record.url),
      url: record.url.length > 0 ? record.url : this.homeUrl,
      isHome: isHome,
      lastActiveAt: record.lastActiveAt,
      pendingUrl: record.pendingUrl ?? (isHome ? '' : record.url),
      navigationHistory: history,
      navigationIndex: navigationIndex,
      runtimeState: this.normalizeRuntimeState(record.runtimeState, isHome, record.isActive, record.webStatePath ?? ''),
      lastError: record.lastError ?? '',
      lastRestoreReason: record.lastRestoreReason ?? '',
      lastDiscardReason: record.lastDiscardReason ?? '',
      lastCrashReason: record.lastCrashReason ?? '',
      lastLoadedAt: record.lastLoadedAt ?? 0,
      webStatePath: record.webStatePath ?? '',
      webStateUpdatedAt: record.webStateUpdatedAt ?? 0,
      scrollOffsetY: record.scrollOffsetY ?? 0,
      lastGoodUrl: record.lastGoodUrl ?? '',
      lastGoodTitle: record.lastGoodTitle ?? '',
      lastRestorableUrl: record.lastRestorableUrl ?? record.lastGoodUrl ?? '',
      lastRestorableTitle: record.lastRestorableTitle ?? record.lastGoodTitle ?? '',
      lastRestoreType: record.lastRestoreType ?? 'none',
      privacyMode: privacyMode,
      dataScope: dataScope,
      launchContext: this.normalizeLaunchContext({
        sourceType: this.normalizeLaunchSourceType(record.launchSourceType),
        sourceId: record.launchSourceId ?? '',
        sourceUrl: record.launchSourceUrl ?? '',
        key: record.launchKey ?? ''
      }),
      openerTabId: this.normalizeTabId(record.openerTabId),
      openSource: this.normalizeOpenSource(record.openSource),
      openedByNewWindow: record.openedByNewWindow === true,
      pinned: record.isPinned === true,
      muted: false,
      audible: false
    };
  }

  private normalizeNavigationHistory(history: string[] | undefined, url: string, isHome: boolean): string[] {
    if (history !== undefined && history.length > 0) {
      return history.filter((item: string) => item.trim().length > 0).slice();
    }
    if (isHome || url.trim().length === 0 || url === this.homeUrl) {
      return [];
    }
    return [url];
  }

  private normalizeNavigationIndex(index: number | undefined, historyLength: number): number {
    if (historyLength === 0) {
      return -1;
    }
    if (index === undefined || index < 0 || index >= historyLength) {
      return historyLength - 1;
    }
    return index;
  }

  private normalizeNavigationTarget(url: string): string {
    const trimmed = url.trim().toLowerCase();
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  private createEmptyLaunchContext(): TabLaunchContext {
    return {
      sourceType: '',
      sourceId: '',
      sourceUrl: '',
      key: ''
    };
  }

  private normalizeLaunchContext(value: TabLaunchContext | undefined): TabLaunchContext {
    if (value === undefined) {
      return this.createEmptyLaunchContext();
    }
    const sourceType = this.normalizeLaunchSourceType(value.sourceType);
    return {
      sourceType: sourceType,
      sourceId: sourceType.length > 0 ? value.sourceId.trim() : '',
      sourceUrl: sourceType.length > 0 ? value.sourceUrl.trim() : '',
      key: sourceType.length > 0 ? value.key.trim() : ''
    };
  }

  private normalizeLaunchSourceType(value: string | undefined): TabLaunchSourceType {
    if (value === 'home_shortcut' || value === 'desktop_web_entry' || value === 'app_continuation') {
      return value;
    }
    return '';
  }

  private normalizeTabId(value: string | undefined): string {
    return value === undefined ? '' : value.trim();
  }

  private normalizeOpenSource(value: BrowserTabOpenSource | string | undefined): BrowserTabOpenSource {
    if (value === 'user_new_tab' || value === 'web_context_menu' || value === 'window_open' ||
      value === 'restore' || value === 'home' || value === 'external') {
      return value;
    }
    return '';
  }

  private resolveTabSequence(tabs: BrowserTabState[]): number {
    return Math.max(1, tabs.length);
  }

  private cloneTabState(
    tab: BrowserTabState,
    lastActiveAt: number = tab.lastActiveAt,
    runtimeState: TabRuntimeState = tab.runtimeState
  ): BrowserTabState {
    return this.createTabState(
      tab.id,
      tab.profileId,
      tab.title,
      tab.url,
      tab.isHome,
      lastActiveAt,
      tab.pendingUrl,
      tab.navigationHistory,
      tab.navigationIndex,
      runtimeState,
      tab.lastError,
      tab.lastRestoreReason,
      tab.lastDiscardReason,
      tab.lastCrashReason,
      tab.lastLoadedAt,
      tab.webStatePath,
      tab.webStateUpdatedAt,
      tab.scrollOffsetY,
      tab.lastGoodUrl,
      tab.lastGoodTitle,
      tab.lastRestorableUrl,
      tab.lastRestorableTitle,
      tab.lastRestoreType,
      tab.privacyMode,
      tab.dataScope,
      tab.launchContext,
      tab.openerTabId,
      tab.openSource,
      tab.openedByNewWindow,
      tab.pinned,
      tab.muted,
      tab.audible
    );
  }

  private createTabState(
    id: string,
    profileId: BrowserProfileId,
    title: string,
    url: string,
    isHome: boolean,
    lastActiveAt: number,
    pendingUrl: string,
    navigationHistory: string[],
    navigationIndex: number,
    runtimeState: TabRuntimeState,
    lastError: string,
    lastRestoreReason: TabRestoreReason | '',
    lastDiscardReason: TabDiscardReason | '',
    lastCrashReason: TabCrashReason | '',
    lastLoadedAt: number,
    webStatePath: string,
    webStateUpdatedAt: number,
    scrollOffsetY: number = 0,
    lastGoodUrl: string = '',
    lastGoodTitle: string = '',
    lastRestorableUrl: string = '',
    lastRestorableTitle: string = '',
    lastRestoreType: WebSessionRestoreType = 'none',
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope: BrowserDataScope = normalizeBrowserDataScope(undefined, privacyMode),
    launchContext: TabLaunchContext = this.createEmptyLaunchContext(),
    openerTabId: string = '',
    openSource: BrowserTabOpenSource = '',
    openedByNewWindow: boolean = false,
    pinned: boolean = false,
    muted: boolean = false,
    audible: boolean = false
  ): BrowserTabState {
    return {
      id: id,
      profileId: normalizeBrowserProfileId(profileId),
      title: title,
      url: url,
      isHome: isHome,
      lastActiveAt: lastActiveAt,
      pendingUrl: pendingUrl,
      navigationHistory: navigationHistory.slice(),
      navigationIndex: navigationIndex,
      runtimeState: runtimeState,
      lastError: lastError,
      lastRestoreReason: lastRestoreReason,
      lastDiscardReason: lastDiscardReason,
      lastCrashReason: lastCrashReason,
      lastLoadedAt: lastLoadedAt,
      webStatePath: webStatePath,
      webStateUpdatedAt: webStateUpdatedAt,
      scrollOffsetY: scrollOffsetY,
      lastGoodUrl: lastGoodUrl,
      lastGoodTitle: lastGoodTitle,
      lastRestorableUrl: lastRestorableUrl,
      lastRestorableTitle: lastRestorableTitle,
      lastRestoreType: lastRestoreType,
      privacyMode: normalizeBrowserSessionPrivacyMode(privacyMode),
      dataScope: normalizeBrowserDataScope(dataScope, privacyMode),
      launchContext: this.normalizeLaunchContext(launchContext),
      openerTabId: this.normalizeTabId(openerTabId),
      openSource: this.normalizeOpenSource(openSource),
      openedByNewWindow: openedByNewWindow,
      pinned: pinned,
      muted: muted,
      audible: audible
    };
  }

  private deactivateCurrentActiveTab(
    tabs: BrowserTabState[],
    activeTabId: string,
    deactivatedAt: number = Date.now()
  ): BrowserTabState[] {
    return tabs.map((tab: BrowserTabState) => {
      if (tab.id !== activeTabId) {
        return tab;
      }
      return this.cloneTabState(tab, deactivatedAt, this.resolveBackgroundRuntimeState(tab));
    });
  }

  private resolveForegroundRuntimeState(tab: BrowserTabState): TabRuntimeState {
    return this.runtimeStateTransitionTable.resolveForegroundState(tab.runtimeState, tab.isHome);
  }

  private resolveBackgroundRuntimeState(tab: BrowserTabState): TabRuntimeState {
    return this.runtimeStateTransitionTable.resolveBackgroundState(tab.runtimeState, tab.isHome);
  }

  private normalizeRuntimeState(
    runtimeState: TabRuntimeState | undefined,
    isHome: boolean,
    isActive: boolean,
    webStatePath: string = ''
  ): TabRuntimeState {
    return this.runtimeStateTransitionTable.normalizePersistedState({
      runtimeState: runtimeState,
      isHome: isHome,
      isActive: isActive,
      webStatePath: webStatePath
    });
  }

  private toPersistedRestoreReason(reason: TabRestoreReason | ''): TabRestoreReason {
    return reason as TabRestoreReason;
  }

  private toPersistedDiscardReason(reason: TabDiscardReason | ''): TabDiscardReason {
    return reason as TabDiscardReason;
  }

  private toPersistedCrashReason(reason: TabCrashReason | ''): TabCrashReason {
    return reason as TabCrashReason;
  }

  private createScopedTabId(timestamp: number, sequence: number): string {
    const safeWindowId = this.windowId
      .trim()
      .replace(/[^a-zA-Z0-9._-]/g, '_')
      .slice(0, TAB_ID_SAFE_WINDOW_MAX_LENGTH);
    const prefix = safeWindowId.length > 0 ? safeWindowId : DEFAULT_WINDOW_ID;
    return `${prefix}-tab-${Math.max(0, Math.floor(timestamp))}-${Math.max(0, Math.floor(sequence))}`;
  }
}

function activeTabIdFromTabs(tabs: BrowserTabState[]): string {
  const active = tabs.find((tab: BrowserTabState) => tab.runtimeState === 'active' || tab.runtimeState === 'loading' || tab.runtimeState === 'restoring');
  return active?.id ?? '';
}
