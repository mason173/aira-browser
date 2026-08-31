import {
  BrowserTabState,
  BrowserTabRuntimePatch,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import { TabMutationCommitOptions } from './BrowserShellRuntimeContracts';
import { BrowserPrivateModeLockCoordinator } from '../privacy/BrowserPrivateModeLockCoordinator';
import { BrowserTabTransitionCoordinator } from './BrowserTabTransitionCoordinator';
import { BrowserBackgroundOpenPromptCoordinator } from './BrowserBackgroundOpenPromptCoordinator';
import { BrowserBackgroundTabPreviewRuntimeCoordinator } from './BrowserBackgroundTabPreviewRuntimeCoordinator';
import {
  BrowserActiveTabShellStateApplication,
  BrowserActiveTabShellStateCoordinator,
  BrowserActiveTabShellStateInput
} from '../../services/web/BrowserActiveTabShellStateCoordinator';
import { BrowserActiveRuntimeSyncCoordinator } from './BrowserActiveRuntimeSyncCoordinator';
import { BrowserWebTabsController } from './BrowserWebTabsController';
import { BrowserTabBackgroundSessionSyncCoordinator } from '../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import { BrowserBottomChromeScrollCoordinator } from './BrowserBottomChromeScrollCoordinator';
import { BrowserWebTopImmersionSessionCoordinator } from './BrowserWebTopImmersionSessionCoordinator';
import { BrowserMediaDiscoveryCoordinator } from './media/BrowserMediaDiscoveryCoordinator';
import { BrowserMediaDiscoveryHost } from './media/BrowserMediaDiscoveryModels';
import { BrowserTabSessionPersistenceCoordinator } from './BrowserTabSessionPersistenceCoordinator';
import { BrowserUserAgentActionCoordinator } from './BrowserUserAgentActionCoordinator';
import {
  BrowserMaterializationPolicy,
  DEFAULT_BROWSER_MATERIALIZATION_POLICY
} from './BrowserMaterializationPolicy';
import { BrowserWindowRuntime } from '../../app/runtime/BrowserWindowRuntime';
import { BrowserSearchInvocationRuntime } from '../../app/runtime/BrowserSearchInvocationRuntime';
import { BrowserPageFindCoordinator } from './BrowserPageFindCoordinator';
import { BrowserAddressDisplayCoordinator } from './BrowserAddressDisplayCoordinator';
import { BrowserTabPreviewAssetBoundaryCoordinator } from './BrowserTabPreviewAssetBoundaryCoordinator';
import { BrowserTabPreviewCoordinator } from './BrowserTabPreviewCoordinator';
import { BrowserTabsOverviewSnapshotPipelineCoordinator } from './tabsOverview/BrowserTabsOverviewSnapshotPipelineCoordinator';
import { BrowserRuntimeMutationPort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { ElementInspectionSessionCoordinator } from './ElementInspectionSessionCoordinator';
import { browserNativeTabSceneService } from './BrowserNativeTabSceneService';
import { sharedBrowserContinuationCoordinator } from './BrowserContinuationCoordinator';

type BrowserTabSwitchApplicationMode = 'standard' | 'overview';

export interface BrowserTabSwitchApplicationFacts {
  tabs: BrowserTabState[];
  activeTabId: string;
  tabSequence: number;
  showHomePage: boolean;
  controllerAttached: boolean;
  currentWindowId: string;
  activeDownloadCount: number;
  runtimeDegradedMessage: string;
  fullScreenModeEnabled: boolean;
}

export type BrowserTabSwitchPlatformAction =
  'cancel_bottom_panel_backdrop_focus' |
  'request_close_tabs_overview' |
  'restore_web_bottom_address_panel' |
  'sync_download_boundary' |
  'disable_fullscreen' |
  'sync_bottom_panel_status_bar';

export interface BrowserTabSwitchApplicationSink {
  resolveFacts: () => BrowserTabSwitchApplicationFacts;
  persistActiveTabSnapshot: (reason: string) => void;
  applyTabSelection: (tabs: BrowserTabState[], activeTabId: string) => void;
  applyTabs: (tabs: BrowserTabState[]) => void;
  notifyTabPreviewChanged: () => void;
  applyTabSequence: (tabSequence: number) => void;
  captureOpenerPreviewBeforeBackgroundPromptSwitch: (openerTabId: string, targetTabId: string) => Promise<void>;
  applyShellApplication: (application: BrowserActiveTabShellStateApplication) => void;
  applyHelperMessage: (message: string) => void;
  executePlatformAction: (action: BrowserTabSwitchPlatformAction) => void;
}

interface BrowserTabSwitchDependencies {
  privateModeLockCoordinator: BrowserPrivateModeLockCoordinator;
  activeTabShellStateCoordinator: BrowserActiveTabShellStateCoordinator;
  backgroundOpenPromptCoordinator: BrowserBackgroundOpenPromptCoordinator;
  resolveActiveRuntimeSyncCoordinator: () => BrowserActiveRuntimeSyncCoordinator;
  resolveWebTabsController: () => BrowserWebTabsController;
  resolveBackgroundTabPreviewRuntimeCoordinator: () => BrowserBackgroundTabPreviewRuntimeCoordinator;
  resolveBackgroundSessionSyncCoordinator: () => BrowserTabBackgroundSessionSyncCoordinator;
  resolveBottomChromeScrollCoordinator: () => BrowserBottomChromeScrollCoordinator;
  resolveTopImmersionSessionCoordinator: () => BrowserWebTopImmersionSessionCoordinator;
  resolveMediaDiscoveryCoordinator: () => BrowserMediaDiscoveryCoordinator;
  resolveMediaDiscoveryHost: () => BrowserMediaDiscoveryHost;
  resolveTabSessionPersistenceCoordinator: () => BrowserTabSessionPersistenceCoordinator;
  resolveUserAgentActionCoordinator: () => BrowserUserAgentActionCoordinator;
  resolvePageFindCoordinator: () => BrowserPageFindCoordinator;
  resolveAddressDisplayCoordinator: () => BrowserAddressDisplayCoordinator;
  resolveRuntimeMutationPort: () => BrowserRuntimeMutationPort;
  resolveTabPreviewAssetBoundaryCoordinator: () => BrowserTabPreviewAssetBoundaryCoordinator;
  resolveTabPreviewCoordinator: () => BrowserTabPreviewCoordinator;
  resolveTabsOverviewSnapshotPipelineCoordinator: () => BrowserTabsOverviewSnapshotPipelineCoordinator;
  resolveElementInspectionSessionCoordinator: () => ElementInspectionSessionCoordinator;
  resolveSuspendedWindowTabsByWindowId: () => Record<string, BrowserTabState[] | undefined>;
  resolveRuntimeDegradedReason: (tabId: string) => string;
  sink: BrowserTabSwitchApplicationSink;
}

export class BrowserTabSwitchCoordinator {
  private readonly tabManager: BrowserTabManagerPort;
  private readonly dependencies: BrowserTabSwitchDependencies;
  private readonly transitionCoordinator: BrowserTabTransitionCoordinator = new BrowserTabTransitionCoordinator();

  constructor(tabManager: BrowserTabManagerPort, dependencies: BrowserTabSwitchDependencies) {
    this.tabManager = tabManager;
    this.dependencies = dependencies;
  }

  resolveTabSnapshot(tabId: string): BrowserTabState | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return undefined;
    }
    return this.tabManager.getTab(this.dependencies.sink.resolveFacts().tabs, normalizedTabId);
  }

  resolveTabsSnapshot(): BrowserTabState[] {
    return this.dependencies.sink.resolveFacts().tabs.slice();
  }

  async switchToTab(tabId: string): Promise<void> {
    this.emitPlatform('cancel_bottom_panel_backdrop_focus');
    const facts = this.dependencies.sink.resolveFacts();
    const targetTab = this.findTabById(facts.tabs, tabId);
    if (targetTab !== undefined && !await this.dependencies.privateModeLockCoordinator.ensureUnlocked(
      targetTab.privacyMode,
      targetTab.dataScope,
      'switch_private_tab'
    )) {
      return;
    }
    if (tabId === facts.activeTabId) {
      this.emitPlatform('request_close_tabs_overview');
      this.synchronizeActiveTab();
      return;
    }
    this.applyTabSwitchTransition(tabId, 'standard');
  }

  async openBackgroundPromptTab(tabId: string): Promise<void> {
    const facts = this.dependencies.sink.resolveFacts();
    if (!this.dependencies.backgroundOpenPromptCoordinator.consumeOpenRequest(tabId)) {
      return;
    }
    if (this.findTabById(facts.tabs, tabId) === undefined) {
      return;
    }
    await this.dependencies.sink.captureOpenerPreviewBeforeBackgroundPromptSwitch(facts.activeTabId, tabId);
    await this.switchToTab(tabId);
  }

  applyOverviewSelection(tabId: string): boolean {
    return this.applyTabSwitchTransition(tabId, 'overview');
  }

  restoreActiveWebTabFromHomeOverview(): void {
    const facts = this.dependencies.sink.resolveFacts();
    this.emitPlatform('restore_web_bottom_address_panel');
    this.synchronizeActiveTab();
    this.dependencies.resolveTopImmersionSessionCoordinator().requestVisible(
      'tabs-overview-active-web-selection'
    );
    this.dependencies.resolvePageFindCoordinator().handleActiveTabChanged(facts.activeTabId);
  }

  synchronizeActiveTab(
    materializationPolicy: BrowserMaterializationPolicy = DEFAULT_BROWSER_MATERIALIZATION_POLICY
  ): void {
    this.synchronizeActiveTabInternal(false, materializationPolicy);
  }

  synchronizeAfterTabChange(): void {
    const facts = this.dependencies.sink.resolveFacts();
    const backgroundPreviewCoordinator = this.dependencies.resolveBackgroundTabPreviewRuntimeCoordinator();
    if (backgroundPreviewCoordinator.shouldFinishForActiveTabChange(facts.activeTabId)) {
      backgroundPreviewCoordinator.finishPreview(facts.activeTabId, 'tab_activated');
    }
    this.dependencies.backgroundOpenPromptCoordinator.dismissTab(facts.activeTabId);
    this.synchronizeActiveTabInternal(true, DEFAULT_BROWSER_MATERIALIZATION_POLICY);
  }

  publishActiveTabShellState(): BrowserTabState | undefined {
    const facts = this.dependencies.sink.resolveFacts();
    const application = this.dependencies.activeTabShellStateCoordinator.buildActiveTabApplication(
      this.buildShellStateInput(facts)
    );
    this.applyShellApplication(application);
    return application.activeTab;
  }

  applyTabPatch(
    tabId: string,
    patch: BrowserTabRuntimePatch,
    options: TabMutationCommitOptions = {}
  ): void {
    const facts = this.dependencies.sink.resolveFacts();
    const nextTabs = this.tabManager.updateTab(facts.tabs, tabId, {
      profileId: patch.profileId,
      title: patch.title,
      url: patch.url,
      isHome: patch.isHome,
      lastActiveAt: patch.lastActiveAt,
      pendingUrl: patch.pendingUrl,
      navigationHistory: patch.navigationHistory,
      navigationIndex: patch.navigationIndex,
      runtimeState: patch.runtimeState,
      lastError: patch.lastError,
      lastRestoreReason: patch.lastRestoreReason,
      lastDiscardReason: patch.lastDiscardReason,
      lastCrashReason: patch.lastCrashReason,
      lastLoadedAt: patch.lastLoadedAt,
      webStatePath: patch.webStatePath,
      webStateUpdatedAt: patch.webStateUpdatedAt,
      scrollOffsetY: patch.scrollOffsetY,
      lastGoodUrl: patch.lastGoodUrl,
      lastGoodTitle: patch.lastGoodTitle,
      lastRestorableUrl: patch.lastRestorableUrl,
      lastRestorableTitle: patch.lastRestorableTitle,
      lastRestoreType: patch.lastRestoreType,
      privacyMode: patch.privacyMode,
      dataScope: patch.dataScope,
      launchContext: patch.launchContext,
      openerTabId: patch.openerTabId,
      openSource: patch.openSource,
      openedByNewWindow: patch.openedByNewWindow
    });
    this.commitTabs(nextTabs, {
      syncRuntimeGraph: options.syncRuntimeGraph,
      refreshRuntimeTabIds: options.refreshRuntimeTabIds ?? [tabId],
      persistTabs: options.persistTabs
    });
  }

  /**
   * Pins/unpins a tab and re-partitions so pinned tabs keep the leading edge.
   * The new order is persisted (TabRecord.isPinned + tab_order) so pins survive
   * a session restore.
   */
  setTabPinned(tabId: string, pinned: boolean): void {
    const facts = this.dependencies.sink.resolveFacts();
    const nextTabs = this.tabManager.setTabPinned(facts.tabs, tabId, pinned);
    this.commitTabs(nextTabs, {
      refreshRuntimeTabIds: []
    });
  }

  /**
   * Toggles the runtime mute flag for a tab and silences/unsilences its web
   * runtime. Mute is session-only state, so tab records are not re-persisted.
   */
  setTabMuted(tabId: string, muted: boolean): void {
    const facts = this.dependencies.sink.resolveFacts();
    const currentTab = this.tabManager.getTab(facts.tabs, tabId);
    if (currentTab === undefined) {
      return;
    }
    this.applyTabPatch(tabId, { muted: muted, lastActiveAt: currentTab.lastActiveAt }, {
      persistTabs: false,
      refreshRuntimeTabIds: []
    });
    this.dependencies.resolveWebTabsController().setTabAudioMuted(tabId, muted);
  }

  /**
   * Records the latest web audio playback state for a tab so the tab strip can
   * surface an audio indicator. Session-only state (never persisted); no-op when
   * unchanged to avoid redundant presentation churn on repeated audio events.
   */
  applyTabAudibleState(tabId: string, audible: boolean): void {
    const facts = this.dependencies.sink.resolveFacts();
    const currentTab = this.tabManager.getTab(facts.tabs, tabId);
    if (currentTab === undefined || currentTab.audible === audible) {
      return;
    }
    this.applyTabPatch(tabId, { audible: audible, lastActiveAt: currentTab.lastActiveAt }, {
      persistTabs: false,
      refreshRuntimeTabIds: []
    });
  }

  recordNativeTabNavigation(tabId: string, url: string, title: string): boolean {
    const facts = this.dependencies.sink.resolveFacts();
    const currentTab = this.tabManager.getTab(facts.tabs, tabId);
    const currentScene = currentTab === undefined ? undefined : browserNativeTabSceneService.resolveSceneForTab(
      currentTab.url,
      currentTab.pendingUrl
    );
    const targetScene = browserNativeTabSceneService.resolveScene(url);
    if (currentTab === undefined || currentScene === undefined || targetScene === undefined ||
      currentScene !== targetScene) {
      return false;
    }
    const nextTabs = this.tabManager.recordNavigationForTab(facts.tabs, tabId, url, title);
    this.commitTabs(nextTabs, {
      refreshRuntimeTabIds: []
    });
    if (tabId === facts.activeTabId) {
      this.publishActiveTabShellState();
    }
    return true;
  }

  navigateNativeTabHistory(tabId: string, direction: 'back' | 'forward'): boolean {
    const facts = this.dependencies.sink.resolveFacts();
    const currentTab = this.tabManager.getTab(facts.tabs, tabId);
    if (currentTab === undefined || browserNativeTabSceneService.resolveSceneForTab(
      currentTab.url,
      currentTab.pendingUrl
    ) === undefined) {
      return false;
    }
    const offset = direction === 'back' ? -1 : 1;
    const targetIndex = currentTab.navigationIndex + offset;
    if (targetIndex < 0 || targetIndex >= currentTab.navigationHistory.length) {
      return true;
    }
    const targetUrl = currentTab.navigationHistory[targetIndex];
    const nextTabs = this.tabManager.updateTab(facts.tabs, tabId, {
      title: currentTab.title,
      url: targetUrl,
      isHome: true,
      pendingUrl: '',
      navigationHistory: currentTab.navigationHistory,
      navigationIndex: targetIndex,
      runtimeState: 'active',
      lastError: '',
      webStatePath: '',
      webStateUpdatedAt: 0,
      scrollOffsetY: 0,
      lastGoodUrl: '',
      lastGoodTitle: '',
      lastRestorableUrl: '',
      lastRestorableTitle: '',
      lastRestoreType: 'none'
    });
    this.commitTabs(nextTabs, {
      refreshRuntimeTabIds: []
    });
    this.publishActiveTabShellState();
    return true;
  }

  switchToExistingNativeTab(
    url: string,
    privacyMode: 'regular' | 'private',
    updateExistingRoute: boolean = false
  ): boolean {
    const facts = this.dependencies.sink.resolveFacts();
    const scene = browserNativeTabSceneService.resolveScene(url);
    if (scene === undefined) {
      return false;
    }
    const existing = facts.tabs.find((tab: BrowserTabState): boolean => {
      return tab.privacyMode === privacyMode &&
        browserNativeTabSceneService.resolveSceneForTab(tab.url, tab.pendingUrl) === scene;
    });
    if (existing === undefined) {
      return false;
    }
    const existingRouteUrl = existing.pendingUrl.trim().length > 0 ? existing.pendingUrl : existing.url;
    if (updateExistingRoute && existingRouteUrl.trim() !== url.trim()) {
      this.recordNativeTabNavigation(
        existing.id,
        url,
        browserNativeTabSceneService.resolveCanonicalTitleForTab(url) ?? existing.title
      );
    }
    void this.switchToTab(existing.id);
    return true;
  }

  commitTabs(nextTabs: BrowserTabState[], options: TabMutationCommitOptions = {}): void {
    const facts = this.dependencies.sink.resolveFacts();
    this.dependencies.sink.applyTabs(nextTabs);
    BrowserSearchInvocationRuntime.reconcileActiveContext(facts.currentWindowId, facts.activeTabId);
    this.dependencies.resolveAddressDisplayCoordinator().pruneTabs(
      nextTabs.map((tab: BrowserTabState): string => tab.id)
    );
    this.synchronizeWebTabsAndPreviewAssets();
    BrowserWindowRuntime.updateWindowTabSummary(
      facts.currentWindowId,
      facts.activeTabId,
      nextTabs.map((tab: BrowserTabState): string => tab.id)
    );
    sharedBrowserContinuationCoordinator.publishActiveTab(
      facts.currentWindowId,
      this.tabManager.getActiveTab(nextTabs, facts.activeTabId)
    );
    if (options.syncRuntimeGraph === true) {
      this.dependencies.resolveBackgroundSessionSyncCoordinator().sync();
    } else {
      this.dependencies.resolveRuntimeMutationPort().refresh(options.refreshRuntimeTabIds ?? []);
    }
    if (options.persistTabs !== false) {
      this.dependencies.resolveTabSessionPersistenceCoordinator().persist();
    }
  }

  synchronizeWebTabsAndPreviewAssets(): void {
    const facts = this.dependencies.sink.resolveFacts();
    this.dependencies.resolveWebTabsController().syncTabs(facts.tabs, facts.activeTabId, {
      materializationPolicy: 'existing_only'
    });
    this.dependencies.resolveTabPreviewAssetBoundaryCoordinator().syncPreviewAssetsWithTabs({
      previewCoordinator: this.dependencies.resolveTabPreviewCoordinator(),
      snapshotPipelineCoordinator: this.dependencies.resolveTabsOverviewSnapshotPipelineCoordinator(),
      tabs: facts.tabs,
      suspendedWindowTabsByWindowId: this.dependencies.resolveSuspendedWindowTabsByWindowId(),
      currentWindowId: facts.currentWindowId,
      notifyChanged: (): void => this.dependencies.sink.notifyTabPreviewChanged()
    });
  }

  resumeActiveTabOnPageForeground(): void {
    this.syncWindowTabSummary();
    let facts = this.dependencies.sink.resolveFacts();
    if (facts.showHomePage) {
      this.applyShellApplication(
        this.dependencies.activeTabShellStateCoordinator.buildForegroundHomeApplication(
          this.buildShellStateInput(facts)
        )
      );
      this.scheduleForegroundResumeFollowup(facts.activeTabId, facts.currentWindowId);
      return;
    }
    const application = this.dependencies.activeTabShellStateCoordinator.buildActiveTabApplication(
      this.buildShellStateInput(facts)
    );
    this.applyShellApplication(application);
    if (application.activeTab !== undefined && !application.activeTab.isHome) {
      this.dependencies.resolveActiveRuntimeSyncCoordinator().syncActiveRuntime();
      facts = this.dependencies.sink.resolveFacts();
      if (!facts.controllerAttached) {
        this.dependencies.resolveActiveRuntimeSyncCoordinator().syncActiveRuntimeAfterSwitch();
      }
    }
    this.scheduleForegroundResumeFollowup(application.activeTab?.id ?? facts.activeTabId, facts.currentWindowId);
  }

  private applyTabSwitchTransition(tabId: string, mode: BrowserTabSwitchApplicationMode): boolean {
    const facts = this.dependencies.sink.resolveFacts();
    const previousTabId = facts.activeTabId;
    this.dependencies.sink.persistActiveTabSnapshot('switch-tab');
    const transition = this.transitionCoordinator.switchToTab(
      this.tabManager,
      facts.tabs,
      previousTabId,
      tabId,
      facts.tabSequence
    );
    if (transition === undefined) {
      return false;
    }
    this.dependencies.resolveElementInspectionSessionCoordinator().handleActiveTabChanged(
      previousTabId,
      transition.activeTabId
    );
    this.dependencies.sink.applyTabSelection(transition.tabs, transition.activeTabId);
    if (mode === 'standard') {
      this.dependencies.resolveBottomChromeScrollCoordinator().reset(transition.activeTabId, 0);
      this.dependencies.resolveTopImmersionSessionCoordinator().resetScrollBaseline(transition.activeTabId, 0);
      this.emitPlatform('restore_web_bottom_address_panel');
      this.dependencies.resolveTopImmersionSessionCoordinator().requestVisible('switch-tab');
    }
    this.dependencies.sink.applyTabSequence(transition.tabSequence);
    if (mode === 'standard') {
      this.emitPlatform('request_close_tabs_overview');
    }
    this.synchronizeAfterTabChange();
    this.dependencies.resolvePageFindCoordinator().handleActiveTabChanged(transition.activeTabId);
    this.dependencies.resolveMediaDiscoveryCoordinator().refreshActiveMediaDiscoverySurface(
      this.dependencies.resolveMediaDiscoveryHost()
    );
    this.dependencies.resolveTabSessionPersistenceCoordinator().persist();
    this.dependencies.sink.applyHelperMessage(transition.helperMessage);
    this.dependencies.privateModeLockCoordinator.synchronizeCurrentBoundary();
    return true;
  }

  private synchronizeActiveTabInternal(
    isTabSwitch: boolean,
    materializationPolicy: BrowserMaterializationPolicy
  ): void {
    const facts = this.dependencies.sink.resolveFacts();
    BrowserSearchInvocationRuntime.reconcileActiveContext(facts.currentWindowId, facts.activeTabId);
    this.dependencies.resolveWebTabsController().syncTabs(facts.tabs, facts.activeTabId, {
      materializationPolicy: materializationPolicy
    });
    if (facts.fullScreenModeEnabled) {
      this.emitPlatform('disable_fullscreen');
    }
    this.syncWindowTabSummary();
    this.dependencies.resolveBackgroundSessionSyncCoordinator().sync(
      isTabSwitch ? 'tab_switch' : 'session_sync',
      { materializationPolicy: materializationPolicy }
    );
    this.emitPlatform('sync_download_boundary');
    const activeTab = this.publishActiveTabShellState();
    this.emitPlatform('sync_bottom_panel_status_bar');
    this.dependencies.resolveUserAgentActionCoordinator().synchronize();
    if (activeTab === undefined || activeTab.isHome) {
      return;
    }
    if (isTabSwitch) {
      this.dependencies.resolveActiveRuntimeSyncCoordinator().syncActiveRuntimeAfterSwitch();
      return;
    }
    this.dependencies.resolveActiveRuntimeSyncCoordinator().syncActiveRuntime();
  }

  private scheduleForegroundResumeFollowup(expectedTabId: string, expectedWindowId: string): void {
    setTimeout(() => {
      const facts = this.dependencies.sink.resolveFacts();
      if (facts.currentWindowId !== expectedWindowId || facts.activeTabId !== expectedTabId) {
        return;
      }
      this.emitPlatform('sync_download_boundary');
      this.dependencies.resolveBackgroundSessionSyncCoordinator().handleAppForegroundFollowup(expectedTabId);
    }, 0);
  }

  private buildShellStateInput(facts: BrowserTabSwitchApplicationFacts): BrowserActiveTabShellStateInput {
    const activeTab = this.tabManager.getActiveTab(facts.tabs, facts.activeTabId);
    return {
      activeTab: activeTab,
      activeTabId: facts.activeTabId,
      showHomePage: facts.showHomePage,
      tabCount: facts.tabs.length,
      runtimeDegradedMessage: facts.runtimeDegradedMessage,
      runtimeDegradedReason: activeTab === undefined ? '' : this.dependencies.resolveRuntimeDegradedReason(activeTab.id)
    };
  }

  private applyShellApplication(application: BrowserActiveTabShellStateApplication): void {
    this.dependencies.sink.applyShellApplication(application);
  }

  private syncWindowTabSummary(): void {
    const facts = this.dependencies.sink.resolveFacts();
    BrowserWindowRuntime.updateWindowTabSummary(
      facts.currentWindowId,
      facts.activeTabId,
      facts.tabs.map((tab: BrowserTabState) => tab.id)
    );
    sharedBrowserContinuationCoordinator.publishActiveTab(
      facts.currentWindowId,
      this.tabManager.getActiveTab(facts.tabs, facts.activeTabId)
    );
  }

  private emitPlatform(action: BrowserTabSwitchPlatformAction): void {
    this.dependencies.sink.executePlatformAction(action);
  }

  private findTabById(tabs: BrowserTabState[], tabId: string): BrowserTabState | undefined {
    return tabs.find((tab: BrowserTabState) => tab.id === tabId);
  }
}
