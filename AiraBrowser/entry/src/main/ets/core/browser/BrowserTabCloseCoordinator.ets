import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID
} from '../../common/models/BrowserModels';
import {
  BrowserCreateTabOptions,
  BrowserParentTerminalBackPlan,
  BrowserTabMutationResult,
  BrowserTabState,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import {
  BrowserRestoreRecentlyClosedTabResult
} from './BrowserRecentlyClosedTabsService';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';
import { BrowserPrivateSessionCleanupCoordinator } from './BrowserPrivateSessionCleanupCoordinator';
import { SiteClearOnCloseCoordinator, SiteClearOnCloseCoordinatorHost } from './SiteClearOnCloseCoordinator';
import {
  BrowserTabTransitionCoordinator,
  BrowserTabTransitionResult
} from './BrowserTabTransitionCoordinator';
import { DocumentViewerService } from '../../services/viewer/DocumentViewerService';
import {
  BrowserRecentlyClosedApplicationCoordinator,
  BrowserRecentlyClosedRecordOutcome
} from './BrowserRecentlyClosedApplicationCoordinator';
import { BrowserTabSessionPersistenceCoordinator } from './BrowserTabSessionPersistenceCoordinator';
import { BrowserWebPageLifecycleApplicationCoordinator } from './BrowserWebPageLifecycleApplicationCoordinator';
import { BrowserBackgroundOpenPromptCoordinator } from './BrowserBackgroundOpenPromptCoordinator';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserPageFindCoordinator } from './BrowserPageFindCoordinator';
import { BrowserPrivateModeLockCoordinator } from '../privacy/BrowserPrivateModeLockCoordinator';
import { BrowserTabPreviewCoordinator } from './BrowserTabPreviewCoordinator';
import {
  BrowserTabsOverviewSnapshotPipelineCoordinator
} from './tabsOverview/BrowserTabsOverviewSnapshotPipelineCoordinator';
import { BrowserApplicationTerminationService } from '../../services/browser/BrowserApplicationTerminationService';

export type BrowserClosedTabsHelperMessageMode = 'provided' | 'closed_count';

export interface BrowserCloseTabsToHomeResult {
  closedCount: number;
  helperMessage: string;
}

export interface BrowserRecentlyClosedRestoreOutcome {
  restored: boolean;
  restoredCount: number;
  activeTabId: string;
  summaryLine: string;
}

export interface BrowserCloseCurrentTabToHomeRequest {
  activeTab: BrowserTabState;
  helperMessage: string;
  homeOptions: BrowserCreateTabOptions;
  shouldPlayDirectHomeReveal: boolean;
  cleanupReason: string;
}

interface BrowserCloseTabCleanupPlan {
  tabId: string;
  profileId: BrowserProfileId;
  wasActive: boolean;
  closingTabFound: boolean;
  isLastTab: boolean;
  snapshotPath: string;
  shouldDeleteSnapshot: boolean;
  shouldCleanupSessionPermissions: boolean;
}

type BrowserCloseTabExecutionMode = 'visual_first' | 'cleanup_first';
export type BrowserCloseTabHomeRevealMotion = 'scale' | 'steady';
type BrowserCloseTabDeferredPostCleanup = () => void;

export interface BrowserCloseTabAnimationPlan {
  durationMs: number;
  curve: string;
  apply: () => void;
}

interface BrowserCloseTabExecutionPlan {
  mode: BrowserCloseTabExecutionMode;
  reason: string;
  shouldPersistImmediately: boolean;
  persistDelayMs: number;
}

type BrowserPostCloseTabSurfaceKind = 'tabs' | 'home' | 'terminate_application';
type BrowserLastTabCloseBehavior = 'return_home' | 'terminate_application';

interface BrowserPostCloseTabSurfacePlan {
  kind: BrowserPostCloseTabSurfaceKind;
  homeOptions: BrowserCreateTabOptions;
  helperMessage: string;
}

interface BrowserCloseTabFlowRequest {
  tabId: string;
  closingTab?: BrowserTabState;
  transition: BrowserTabTransitionResult;
  postCloseSurfacePlan: BrowserPostCloseTabSurfacePlan;
}

export interface BrowserTabCloseCoordinatorDependencies {
  resolveApplicationHost: () => BrowserCloseTabApplicationHost;
  resolveWebPageLifecycleCoordinator: () => BrowserWebPageLifecycleApplicationCoordinator;
  resolveTabSessionPersistenceCoordinator: () => BrowserTabSessionPersistenceCoordinator;
  resolveTabHomeCoordinator: () => BrowserTabHomeCoordinator;
  revealHomeSurfaceFromTabsOverview: (
    helperMessage: string,
    homeOptions: BrowserCreateTabOptions,
    homeRevealMotion: BrowserCloseTabHomeRevealMotion
  ) => Promise<void>;
  playDirectHomeReveal: () => void;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  pageFindCoordinator: BrowserPageFindCoordinator;
  privateModeLockCoordinator: BrowserPrivateModeLockCoordinator;
  tabPreviewCoordinator: BrowserTabPreviewCoordinator;
  tabsOverviewSnapshotPipelineCoordinator: BrowserTabsOverviewSnapshotPipelineCoordinator;
  backgroundOpenPromptCoordinator: BrowserBackgroundOpenPromptCoordinator;
  recentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator;
  privateSessionCleanupCoordinator: BrowserPrivateSessionCleanupCoordinator;
  documentViewerService: DocumentViewerService;
  siteClearOnCloseCoordinator: SiteClearOnCloseCoordinator;
  resolveSiteClearOnCloseHost: () => SiteClearOnCloseCoordinatorHost;
}

export interface BrowserTabCloseApplicationState {
  tabs: BrowserTabState[];
  activeTabId: string;
  tabSequence: number;
  dataScope: BrowserDataScope;
  privacyMode: BrowserSessionPrivacyMode;
  tabsOverviewVisible: boolean;
}

export interface BrowserCloseTabApplicationHost {
  readState: () => BrowserTabCloseApplicationState;
  persistActiveTabSnapshot: (reason: string) => void;
  applyRestoredTabState: (
    tabs: BrowserTabState[],
    activeTabId: string
  ) => void;
  requestCloseTabsOverview: () => void;
  showToast: (message: string) => void;
  restoreHomeBottomPanelForDirectHomeNavigation: (detent: 'peek' | 'low') => void;
  executeTabListAnimation: (plan: BrowserCloseTabAnimationPlan) => void;
  applyTabList: (tabs: BrowserTabState[]) => void;
  applyActiveTabState: (activeTabId: string, tabSequence: number) => void;
  notifyTabPreviewChanged: () => void;
  setHelperMessage: (message: string) => void;
}

export class BrowserTabCloseCoordinator {
  private readonly tabManager: BrowserTabManagerPort;
  private readonly dependencies: BrowserTabCloseCoordinatorDependencies;
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private transitionCoordinator: BrowserTabTransitionCoordinator = new BrowserTabTransitionCoordinator();
  private applicationTerminationService: BrowserApplicationTerminationService =
    new BrowserApplicationTerminationService();
  private deferredPersistTimer: number = -1;

  constructor(
    tabManager: BrowserTabManagerPort,
    dependencies: BrowserTabCloseCoordinatorDependencies
  ) {
    this.tabManager = tabManager;
    this.dependencies = dependencies;
  }

  async closeTab(tabId: string): Promise<void> {
    await this.closeTabWithLastTabBehavior(tabId, 'return_home');
  }

  async closeDesktopTab(tabId: string): Promise<void> {
    await this.closeTabWithLastTabBehavior(tabId, 'terminate_application');
  }

  async removeDesktopTabAfterWindowMove(tabId: string): Promise<boolean> {
    const host = this.resolveApplicationHost();
    const state = host.readState();
    const movedTab = this.findTabById(state.tabs, tabId);
    if (movedTab === undefined) {
      return false;
    }
    const transition = this.transitionCoordinator.closeTab(
      this.tabManager,
      state.tabs,
      state.activeTabId,
      tabId,
      state.tabSequence
    );
    const postMoveSurfacePlan = this.buildPostCloseTabSurfacePlan(
      transition.tabs,
      movedTab,
      'terminate_application'
    );
    const cleanupPlan = this.buildCloseTabCleanupPlan(state.tabs, state.activeTabId, tabId);
    this.dependencies.resolveWebPageLifecycleCoordinator().prepareTabForTerminalClose(tabId);
    await this.runCloseTabCleanup(cleanupPlan);
    this.applyCloseTabTransition(transition, host);
    await this.removeClosedTabPreviewBeforeActivation(tabId, host);
    this.dependencies.backgroundOpenPromptCoordinator.dismissTab(tabId);
    this.refreshPostCloseBoundaryState(host.readState().activeTabId);
    host.setHelperMessage('已将标签页移至新窗口。');
    if (postMoveSurfacePlan.kind === 'terminate_application') {
      await this.persistTabsAndWait();
      try {
        await this.applicationTerminationService.terminateCurrentApplication();
      } catch (_error) {
        this.dependencies.resolveTabHomeCoordinator().showHomeSurface(
          '已将标签页移至新窗口。',
          postMoveSurfacePlan.homeOptions
        );
      }
      return true;
    }
    this.dependencies.tabSwitchCoordinator.synchronizeActiveTab();
    this.persistTabs();
    return true;
  }

  private async closeTabWithLastTabBehavior(
    tabId: string,
    lastTabBehavior: BrowserLastTabCloseBehavior
  ): Promise<void> {
    const host = this.resolveApplicationHost();
    const state = host.readState();
    const tabs = state.tabs;
    const activeTabId = state.activeTabId;
    const closingTab = this.findTabById(tabs, tabId);
    const transition = this.transitionCoordinator.closeTab(
      this.tabManager,
      tabs,
      activeTabId,
      tabId,
      state.tabSequence
    );
    const postCloseSurfacePlan = this.buildPostCloseTabSurfacePlan(
      transition.tabs,
      closingTab,
      lastTabBehavior
    );
    await this.executeCloseTabFlow({
      tabId: tabId,
      closingTab: closingTab,
      transition: transition,
      postCloseSurfacePlan: postCloseSurfacePlan
    }, host);
  }

  async closeActiveTabBackToLastTabOrHome(reason: string): Promise<void> {
    await this.closeActiveTabBackToParentOrHome(reason);
  }

  async closeCurrentTabForUserReturnHome(request: BrowserCloseCurrentTabToHomeRequest): Promise<void> {
    const host = this.resolveApplicationHost();
    const state = host.readState();
    const tabs = state.tabs;
    const activeTabId = state.activeTabId;
    const activeTab = request.activeTab;
    if (activeTab.id !== activeTabId) {
      return;
    }
    const tabId = activeTab.id;
    const cleanupPlan = this.buildCloseTabCleanupPlan(tabs, activeTabId, tabId);
    this.dependencies.resolveWebPageLifecycleCoordinator().prepareTabForTerminalClose(tabId);
    this.recordRecentlyClosedTabForAction(tabId);
    this.applyCloseTabsToHomeMutation(this.tabManager.closeActiveTabToHome(tabs, activeTabId), host);
    this.removeClosedTabPreview(tabId, host);
    this.dependencies.backgroundOpenPromptCoordinator.dismissTab(tabId);
    this.dependencies.resolveTabHomeCoordinator().showHomeSurface(
      request.helperMessage,
      request.homeOptions,
      false,
      false
    );
    host.restoreHomeBottomPanelForDirectHomeNavigation(request.shouldPlayDirectHomeReveal ? 'peek' : 'low');
    this.refreshPostCloseBoundaryState(host.readState().activeTabId);
    host.setHelperMessage(request.helperMessage);
    if (request.shouldPlayDirectHomeReveal) {
      this.dependencies.playDirectHomeReveal();
    }
    this.scheduleDeferredCloseTabCleanup(cleanupPlan, request.cleanupReason, () => {
      this.runSessionEphemeralCleanupIfNeeded(cleanupPlan);
      this.clearSiteDataForTabOnCloseIfNeeded(activeTab);
    });
  }

  async cleanupPrivateTabsForExit(
    tabs: BrowserTabState[],
    activeTabId: string,
    privateTabs: BrowserTabState[]
  ): Promise<void> {
    const host = this.resolveApplicationHost();
    for (let index = 0; index < privateTabs.length; index += 1) {
      const tab = privateTabs[index];
      await this.runCloseTabCleanup(this.buildCloseTabCleanupPlan(tabs, activeTabId, tab.id));
      this.dependencies.backgroundOpenPromptCoordinator.dismissTab(tab.id);
    }
    await this.dependencies.privateSessionCleanupCoordinator.runExplicitPrivateModeExitCleanup(
      privateTabs[0]?.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      privateTabs.map((tab: BrowserTabState): string => tab.id)
    );
  }

  private async closeActiveTabBackToParentOrHome(
    _reason: string
  ): Promise<void> {
    const host = this.resolveApplicationHost();
    const state = host.readState();
    const tabs = state.tabs;
    const activeTabId = state.activeTabId;
    const plan = this.tabManager.buildTerminalBackPlan(tabs, activeTabId);
    if (plan.kind === 'missing_active') {
      const helperMessage = '已回到主页';
      this.dependencies.resolveTabHomeCoordinator().showHomeSurface(
        helperMessage,
        this.buildHomeOptionsFromClosedTab(undefined)
      );
      host.setHelperMessage(helperMessage);
      return;
    }
    if (plan.kind === 'home') {
      await this.closeActiveTabAndReturnHome(host, plan.closingTab);
      return;
    }
    await this.closeActiveTabAndReturnToParent(host, plan);
  }

  async closeTabsToHomeAfterReveal(
    targetTabIds: string[],
    _action: string,
    helperMessage: string,
    helperMessageMode: BrowserClosedTabsHelperMessageMode = 'provided'
  ): Promise<BrowserCloseTabsToHomeResult> {
    const host = this.resolveApplicationHost();
    const state = host.readState();
    const tabs = state.tabs;
    const activeTabId = state.activeTabId;
    const tabIds = this.resolveExistingUniqueTabIds(targetTabIds, tabs);
    if (tabIds.length <= 0) {
      return {
        closedCount: 0,
        helperMessage: helperMessageMode === 'closed_count' ? '已关闭 0 个标签页。' : helperMessage
      };
    }
    const cleanupPlans: BrowserCloseTabCleanupPlan[] = [];
    const closingTabs: (BrowserTabState | undefined)[] = [];
    let simulatedTabs = tabs.slice();
    let simulatedActiveTabId = activeTabId;
    for (let index = 0; index < tabIds.length; index += 1) {
      const tabId = tabIds[index];
      const closingTab = tabs.find((tab: BrowserTabState) => tab.id === tabId);
      closingTabs.push(closingTab);
      const cleanupPlan = this.buildCloseTabCleanupPlan(simulatedTabs, simulatedActiveTabId, tabId);
      cleanupPlans.push(cleanupPlan);
      this.dependencies.resolveWebPageLifecycleCoordinator().prepareTabForTerminalClose(tabId);
      this.recordRecentlyClosedTabForAction(tabId);
      this.dependencies.backgroundOpenPromptCoordinator.dismissTab(tabId);
      const simulatedMutation = this.tabManager.closeTabsToHome(simulatedTabs, simulatedActiveTabId, [tabId]);
      simulatedTabs = simulatedMutation.tabs;
      simulatedActiveTabId = simulatedMutation.activeTabId;
    }
    this.applyCloseTabsToHomeMutation(this.tabManager.closeTabsToHome(tabs, activeTabId, tabIds), host);
    for (let index = 0; index < tabIds.length; index += 1) {
      const tabId = tabIds[index];
      const cleanupPlan = cleanupPlans[index];
      await this.runCloseTabCleanup(cleanupPlan);
      this.removeClosedTabPreview(tabId, host);
      this.runSessionEphemeralCleanupIfNeeded(cleanupPlan);
      this.clearSiteDataForTabOnCloseIfNeeded(closingTabs[index]);
    }
    const resolvedHelperMessage = helperMessageMode === 'closed_count' ?
      `已关闭 ${tabIds.length} 个标签页。` : helperMessage;
    this.finalizeClosedTabs(resolvedHelperMessage, host);
    return {
      closedCount: tabIds.length,
      helperMessage: resolvedHelperMessage
    };
  }

  private finalizeClosedTabs(helperMessage: string, host: BrowserCloseTabApplicationHost): void {
    this.refreshPostCloseBoundaryState(host.readState().activeTabId);
    this.persistTabs();
    host.setHelperMessage(helperMessage);
  }

  private buildCloseTabCleanupPlan(
    tabs: BrowserTabState[],
    activeTabId: string,
    tabId: string
  ): BrowserCloseTabCleanupPlan {
    const closingTab = tabs.find((item: BrowserTabState) => item.id === tabId);
    const sessionEphemeralTabCount = tabs
      .filter((item: BrowserTabState) => this.isSessionEphemeralTab(item))
      .length;
    const snapshotPath = closingTab?.webStatePath ?? '';
    const wasActive = tabId === activeTabId;
    const isLastTab = closingTab !== undefined && tabs.length <= 1;
    return {
      tabId: tabId,
      profileId: closingTab?.profileId ?? 'profile-main',
      wasActive: wasActive,
      closingTabFound: closingTab !== undefined,
      isLastTab: isLastTab,
      snapshotPath: snapshotPath,
      shouldDeleteSnapshot: snapshotPath.length > 0,
      shouldCleanupSessionPermissions: this.isSessionEphemeralTab(closingTab) && sessionEphemeralTabCount <= 1
    };
  }

  private buildPostCloseTabSurfacePlan(
    tabsAfterClose: BrowserTabState[],
    closedTab: BrowserTabState | undefined,
    lastTabBehavior: BrowserLastTabCloseBehavior = 'return_home'
  ): BrowserPostCloseTabSurfacePlan {
    if (tabsAfterClose.length > 0) {
      return {
        kind: 'tabs',
        homeOptions: this.buildHomeOptionsFromClosedTab(closedTab),
        helperMessage: '已关闭标签页。'
      };
    }
    const homeOptions = this.buildHomeOptionsFromClosedTab(closedTab);
    const privateHome = this.isHomeOptionsSessionEphemeral(homeOptions);
    if (closedTab !== undefined && lastTabBehavior === 'terminate_application') {
      return {
        kind: 'terminate_application',
        homeOptions: homeOptions,
        helperMessage: privateHome ? '已进入隐私模式' : '已回到主页'
      };
    }
    return {
      kind: 'home',
      homeOptions: homeOptions,
      helperMessage: privateHome ? '已进入隐私模式' : '已回到主页'
    };
  }

  private async closeActiveTabAndReturnHome(
    host: BrowserCloseTabApplicationHost,
    activeTab: BrowserTabState
  ): Promise<void> {
    const state = host.readState();
    const tabs = state.tabs;
    const activeTabId = state.activeTabId;
    if (activeTab.id !== activeTabId) {
      return;
    }
    const mutation = this.tabManager.closeActiveTabToHome(tabs, activeTabId);
    const transition: BrowserTabTransitionResult = {
      tabs: mutation.tabs,
      activeTabId: mutation.activeTabId,
      tabSequence: Math.max(state.tabSequence, mutation.tabSequence),
      helperMessage: '已关闭网页并回到主页。'
    };
    const postCloseSurfacePlan = this.buildBackToHomeSurfacePlan(activeTab);
    await this.executeCloseTabFlow({
      tabId: activeTab.id,
      closingTab: activeTab,
      transition: transition,
      postCloseSurfacePlan: postCloseSurfacePlan
    }, host);
  }

  private async closeActiveTabAndReturnToParent(
    host: BrowserCloseTabApplicationHost,
    plan: BrowserParentTerminalBackPlan
  ): Promise<void> {
    const state = host.readState();
    const tabs = state.tabs;
    const activeTabId = state.activeTabId;
    const activeTab = plan.closingTab;
    const cleanupPlan = this.buildCloseTabCleanupPlan(tabs, activeTabId, activeTab.id);
    this.dependencies.resolveWebPageLifecycleCoordinator().prepareTabForTerminalClose(activeTab.id);
    this.recordRecentlyClosedTabForAction(activeTab.id);
    const transition = this.transitionCoordinator.closeTabAndActivate(
      this.tabManager,
      tabs,
      activeTabId,
      activeTab.id,
      plan.targetTabId,
      state.tabSequence,
      '已返回原标签页。'
    );
    this.applyCloseTabTransition(transition, host);
    this.dependencies.tabSwitchCoordinator.synchronizeActiveTab();
    this.dependencies.backgroundOpenPromptCoordinator.dismissTab(activeTab.id);
    this.refreshPostCloseBoundaryState(transition.activeTabId);
    this.persistTabs();
    host.setHelperMessage(transition.helperMessage);
    this.scheduleDeferredCloseTabCleanup(cleanupPlan, 'source_linked_parent_return', () => {
      this.runSessionEphemeralCleanupIfNeeded(cleanupPlan);
      this.clearSiteDataForTabOnCloseIfNeeded(activeTab);
    });
  }

  private async executeCloseTabFlow(
    request: BrowserCloseTabFlowRequest,
    host: BrowserCloseTabApplicationHost
  ): Promise<void> {
    this.dependencies.resolveWebPageLifecycleCoordinator().prepareTabForTerminalClose(request.tabId);
    const state = host.readState();
    const tabs = state.tabs;
    const activeTabId = state.activeTabId;
    this.recordRecentlyClosedTabForAction(request.tabId);
    const cleanupPlan = this.buildCloseTabCleanupPlan(
      tabs,
      activeTabId,
      request.tabId
    );
    const executionPlan = this.buildCloseTabExecutionPlan(cleanupPlan, request.postCloseSurfacePlan);
    if (request.postCloseSurfacePlan.kind === 'terminate_application') {
      await this.runCloseTabCleanup(cleanupPlan);
      this.applyCloseTabTransition(request.transition, host);
      await this.removeClosedTabPreviewBeforeActivation(request.tabId, host);
      this.dependencies.backgroundOpenPromptCoordinator.dismissTab(request.tabId);
      this.refreshPostCloseBoundaryState(host.readState().activeTabId);
      await this.runSessionEphemeralCleanupAndWaitIfNeeded(cleanupPlan);
      this.clearSiteDataForTabOnCloseIfNeeded(request.closingTab);
      host.setHelperMessage(request.transition.helperMessage);
      await this.applyPostCloseTabSurfacePlan(
        request.postCloseSurfacePlan,
        executionPlan,
        host
      );
      return;
    }
    if (executionPlan.mode === 'visual_first') {
      this.applyCloseTabTransition(request.transition, host);
      this.dependencies.tabSwitchCoordinator.synchronizeWebTabsAndPreviewAssets();
    } else {
      await this.runCloseTabCleanup(cleanupPlan);
      this.applyCloseTabTransition(request.transition, host);
      this.removeClosedTabPreview(request.tabId, host);
    }
    this.dependencies.backgroundOpenPromptCoordinator.dismissTab(request.tabId);
    await this.applyPostCloseTabSurfacePlan(
      request.postCloseSurfacePlan,
      executionPlan,
      host
    );
    this.refreshPostCloseBoundaryState(host.readState().activeTabId);
    if (executionPlan.mode === 'visual_first') {
      this.scheduleDeferredCloseTabCleanup(
        cleanupPlan,
        executionPlan.reason,
        () => {
          this.runSessionEphemeralCleanupIfNeeded(cleanupPlan);
          this.clearSiteDataForTabOnCloseIfNeeded(request.closingTab);
        }
      );
    } else {
      this.runSessionEphemeralCleanupIfNeeded(cleanupPlan);
      this.clearSiteDataForTabOnCloseIfNeeded(request.closingTab);
    }
    host.setHelperMessage(
      request.postCloseSurfacePlan.kind === 'home'
        ? request.postCloseSurfacePlan.helperMessage
        : request.transition.helperMessage
    );
  }

  private buildBackToHomeSurfacePlan(
    tab: BrowserTabState
  ): BrowserPostCloseTabSurfacePlan {
    const homeOptions = this.buildHomeOptionsFromClosedTab(tab);
    const privateHome = this.isHomeOptionsSessionEphemeral(homeOptions);
    return {
      kind: 'home',
      homeOptions: homeOptions,
      helperMessage: privateHome ? '已进入隐私模式' : '已关闭网页并回到主页。'
    };
  }

  private buildHomeOptionsFromClosedTab(tab: BrowserTabState | undefined): BrowserCreateTabOptions {
    if (tab === undefined) {
      return {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
    }
    return {
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope
    };
  }

  private isSessionEphemeralTab(tab: BrowserTabState | undefined): boolean {
    if (tab === undefined) {
      return false;
    }
    return this.profileBoundaryService.isSessionEphemeral(
      this.profileBoundaryService.buildBoundaryInput(tab.profileId, tab.privacyMode, tab.dataScope)
    );
  }

  private resolveExistingUniqueTabIds(targetTabIds: string[], tabs: BrowserTabState[]): string[] {
    const tabIds: string[] = [];
    for (let index = 0; index < targetTabIds.length; index += 1) {
      const tabId = targetTabIds[index];
      if (tabId.trim().length <= 0 || !tabs.some((tab: BrowserTabState) => tab.id === tabId) ||
        tabIds.includes(tabId)) {
        continue;
      }
      tabIds.push(tabId);
    }
    return tabIds;
  }

  private isHomeOptionsSessionEphemeral(options: BrowserCreateTabOptions): boolean {
    return this.profileBoundaryService.isSessionEphemeral(
      this.profileBoundaryService.buildBoundaryInput(
        options.profileId ?? 'profile-main',
        options.privacyMode ?? 'regular',
        options.dataScope ?? 'profile_persistent'
      )
    );
  }

  private applyCloseTabTransition(
    transition: BrowserTabTransitionResult,
    host: BrowserCloseTabApplicationHost
  ): void {
    host.applyActiveTabState(transition.activeTabId, transition.tabSequence);
    this.executeTabListAnimation(host, (): void => {
      host.applyTabList(transition.tabs);
    });
  }

  private executeTabListAnimation(
    host: BrowserCloseTabApplicationHost,
    apply: () => void
  ): void {
    host.executeTabListAnimation({
      durationMs: 360,
      curve: 'interpolatingSpring(0, 1, 260, 28)',
      apply: apply
    });
  }

  private applyCloseTabsToHomeMutation(
    mutation: BrowserTabMutationResult,
    host: BrowserCloseTabApplicationHost
  ): void {
    host.applyActiveTabState(mutation.activeTabId, mutation.tabSequence);
    this.dependencies.tabSwitchCoordinator.commitTabs(mutation.tabs, {
      persistTabs: false,
      refreshRuntimeTabIds: []
    });
  }

  private removeClosedTabPreview(
    tabId: string,
    host: BrowserCloseTabApplicationHost
  ): void {
    this.clearClosedTabThumbnail(tabId, host);
    void this.dependencies.tabPreviewCoordinator.removeTab(tabId)
      .then((changed: boolean) => {
        if (changed) {
          host.notifyTabPreviewChanged();
        }
      });
    this.dependencies.tabSwitchCoordinator.synchronizeWebTabsAndPreviewAssets();
  }

  private async removeClosedTabPreviewBeforeActivation(
    tabId: string,
    host: BrowserCloseTabApplicationHost
  ): Promise<void> {
    this.clearClosedTabThumbnail(tabId, host);
    if (await this.dependencies.tabPreviewCoordinator.removeTab(tabId)) {
      host.notifyTabPreviewChanged();
    }
    this.dependencies.tabSwitchCoordinator.synchronizeWebTabsAndPreviewAssets();
  }

  private clearClosedTabThumbnail(tabId: string, host: BrowserCloseTabApplicationHost): void {
    if (this.dependencies.tabsOverviewSnapshotPipelineCoordinator.clearTabThumbnail(tabId)) {
      host.notifyTabPreviewChanged();
    }
  }

  private refreshPostCloseBoundaryState(activeTabId: string): void {
    this.dependencies.pageFindCoordinator.handleActiveTabChanged(activeTabId);
    this.dependencies.privateModeLockCoordinator.synchronizeCurrentBoundary();
  }

  private async runCloseTabCleanup(plan: BrowserCloseTabCleanupPlan): Promise<void> {
    await this.dependencies.resolveWebPageLifecycleCoordinator().cleanupClosedTabRuntime({
      tabId: plan.tabId,
      snapshotPath: plan.snapshotPath,
      shouldDeleteSnapshot: plan.shouldDeleteSnapshot,
      wasActive: plan.wasActive
    });
  }

  private scheduleDeferredCloseTabCleanup(
    plan: BrowserCloseTabCleanupPlan,
    reason: string,
    postCleanup: BrowserCloseTabDeferredPostCleanup | undefined = undefined
  ): void {
    const host = this.resolveApplicationHost();
    setTimeout(() => {
      this.runCloseTabCleanup(plan)
        .then(() => {
          this.runDeferredPostCleanup(postCleanup);
          this.removeClosedTabPreview(plan.tabId, host);
        })
        .catch((_error: Error) => {
          this.runDeferredPostCleanup(postCleanup);
        });
    }, 0);
  }

  private runSessionEphemeralCleanup(profileId: BrowserProfileId, tabId: string): void {
    void this.dependencies.privateSessionCleanupCoordinator.runLastPrivateTabClosedCleanup(profileId, tabId);
  }

  private runSessionEphemeralCleanupIfNeeded(plan: BrowserCloseTabCleanupPlan): void {
    if (!plan.closingTabFound || !plan.shouldCleanupSessionPermissions) {
      return;
    }
    this.runSessionEphemeralCleanup(plan.profileId, plan.tabId);
  }

  private async runSessionEphemeralCleanupAndWaitIfNeeded(
    plan: BrowserCloseTabCleanupPlan
  ): Promise<void> {
    if (!plan.closingTabFound || !plan.shouldCleanupSessionPermissions) {
      return;
    }
    try {
      await this.dependencies.privateSessionCleanupCoordinator.runLastPrivateTabClosedCleanup(
        plan.profileId,
        plan.tabId
      );
    } catch (_error) {
    }
  }

  private scheduleTabSessionPersist(plan: BrowserCloseTabExecutionPlan): void {
    if (plan.shouldPersistImmediately) {
      if (!this.flushScheduledTabSessionPersist()) {
        this.persistTabs();
      }
      return;
    }
    const delayMs = Math.max(0, Math.floor(plan.persistDelayMs));
    if (this.deferredPersistTimer >= 0) {
      clearTimeout(this.deferredPersistTimer);
      this.deferredPersistTimer = -1;
    }
    this.deferredPersistTimer = setTimeout(() => {
      this.deferredPersistTimer = -1;
      this.persistTabs();
    }, delayMs);
  }

  flushScheduledTabSessionPersist(): boolean {
    if (this.deferredPersistTimer < 0) {
      return false;
    }
    clearTimeout(this.deferredPersistTimer);
    this.deferredPersistTimer = -1;
    this.persistTabs();
    return true;
  }

  private recordRecentlyClosedTabForAction(tabId: string): BrowserRecentlyClosedRecordOutcome {
    const state = this.resolveApplicationHost().readState();
    const recentlyClosedOwner = this.dependencies.recentlyClosedApplicationCoordinator;
    const tab = this.findTabById(state.tabs, tabId);
    const skipReason = this.resolveRecentlyClosedSkipReason(tab);
    if (skipReason.length > 0) {
      return this.buildRecentlyClosedSkippedResult(skipReason);
    }
    return recentlyClosedOwner.recordClosedTab(tab);
  }

  restoreRecentlyClosedRecord(recordId: string): BrowserRecentlyClosedRestoreOutcome {
    const host = this.resolveApplicationHost();
    const state = host.readState();
    if (!this.allowRecentlyClosedRestore(state, host)) {
      return this.buildBlockedRestoreOutcome(state.activeTabId);
    }
    const result = this.dependencies.recentlyClosedApplicationCoordinator.prepareRestoreByRecordId(
      state.tabs,
      state.activeTabId,
      recordId
    );
    if (!result.restored) {
      host.showToast('这个标签页已经无法恢复。');
      return this.buildSingleRestoreOutcome(result);
    }
    this.applySingleRestoreResult(result, host);
    return this.buildSingleRestoreOutcome(result);
  }

  restoreLatestRecentlyClosedShortcut(): BrowserRecentlyClosedRestoreOutcome {
    const host = this.resolveApplicationHost();
    const state = host.readState();
    if (!this.allowRecentlyClosedRestore(state, host)) {
      return this.buildBlockedRestoreOutcome(state.activeTabId);
    }
    const result = this.dependencies.recentlyClosedApplicationCoordinator.prepareRestoreLatest(
      state.tabs,
      state.activeTabId
    );
    if (!result.restored) {
      host.setHelperMessage('没有最近关闭的标签页。');
      host.showToast('没有最近关闭的标签页。');
      return this.buildSingleRestoreOutcome(result);
    }
    this.applySingleRestoreResult(result, host);
    host.showToast('已恢复最近关闭的标签页。');
    return this.buildSingleRestoreOutcome(result);
  }

  private buildCloseTabExecutionPlan(
    cleanupPlan: BrowserCloseTabCleanupPlan,
    postCloseSurfacePlan: BrowserPostCloseTabSurfacePlan | undefined = undefined
  ): BrowserCloseTabExecutionPlan {
    if (!cleanupPlan.closingTabFound) {
      return {
        mode: 'cleanup_first',
        reason: 'tab_missing',
        shouldPersistImmediately: true,
        persistDelayMs: 0
      };
    }
    if (postCloseSurfacePlan?.kind === 'terminate_application') {
      return {
        mode: 'cleanup_first',
        reason: 'terminate_application_last_tab',
        shouldPersistImmediately: true,
        persistDelayMs: 0
      };
    }
    if (postCloseSurfacePlan?.kind === 'home') {
      return {
        mode: 'visual_first',
        reason: cleanupPlan.isLastTab ? 'home_surface_last_tab' : 'home_surface',
        shouldPersistImmediately: false,
        persistDelayMs: 300
      };
    }
    if (cleanupPlan.wasActive) {
      return {
        mode: 'cleanup_first',
        reason: 'active_tab',
        shouldPersistImmediately: true,
        persistDelayMs: 0
      };
    }
    if (cleanupPlan.isLastTab) {
      return {
        mode: 'cleanup_first',
        reason: 'last_tab',
        shouldPersistImmediately: true,
        persistDelayMs: 0
      };
    }
    if (cleanupPlan.shouldCleanupSessionPermissions) {
      return {
        mode: 'cleanup_first',
        reason: 'session_cleanup',
        shouldPersistImmediately: true,
        persistDelayMs: 0
      };
    }
    return {
      mode: 'visual_first',
      reason: 'background_tab',
      shouldPersistImmediately: false,
      persistDelayMs: 300
    };
  }

  private async applyPostCloseTabSurfacePlan(
    plan: BrowserPostCloseTabSurfacePlan,
    executionPlan: BrowserCloseTabExecutionPlan,
    host: BrowserCloseTabApplicationHost
  ): Promise<void> {
    if (plan.kind === 'terminate_application') {
      await this.persistTabsAndWait();
      try {
        await this.applicationTerminationService.terminateCurrentApplication();
        return;
      } catch (_error) {
        if (host.readState().tabsOverviewVisible) {
          await this.dependencies.revealHomeSurfaceFromTabsOverview(
            plan.helperMessage,
            plan.homeOptions,
            'steady'
          );
          return;
        }
        this.dependencies.resolveTabHomeCoordinator().showHomeSurface(plan.helperMessage, plan.homeOptions);
        return;
      }
    }
    this.scheduleTabSessionPersist(executionPlan);
    if (plan.kind !== 'home') {
      this.dependencies.tabSwitchCoordinator.synchronizeActiveTab();
      return;
    }
    if (host.readState().tabsOverviewVisible) {
      await this.dependencies.revealHomeSurfaceFromTabsOverview(plan.helperMessage, plan.homeOptions, 'steady');
      return;
    }
    this.dependencies.resolveTabHomeCoordinator().showHomeSurface(plan.helperMessage, plan.homeOptions);
  }

  private runDeferredPostCleanup(postCleanup: BrowserCloseTabDeferredPostCleanup | undefined): void {
    if (postCleanup === undefined) {
      return;
    }
    try {
      postCleanup();
    } catch (_error) {
    }
  }

  private resolveApplicationHost(): BrowserCloseTabApplicationHost {
    return this.dependencies.resolveApplicationHost();
  }

  private persistTabs(): void {
    this.dependencies.resolveTabSessionPersistenceCoordinator().persist();
  }

  private async persistTabsAndWait(): Promise<void> {
    if (this.deferredPersistTimer >= 0) {
      clearTimeout(this.deferredPersistTimer);
      this.deferredPersistTimer = -1;
    }
    try {
      await this.dependencies.resolveTabSessionPersistenceCoordinator().persistAndWait();
    } catch (_error) {
    }
  }

  private clearSiteDataForTabOnCloseIfNeeded(tab: BrowserTabState | undefined): void {
    this.dependencies.siteClearOnCloseCoordinator.handleExplicitSiteExit(
      tab,
      this.dependencies.resolveSiteClearOnCloseHost()
    );
  }

  private applySingleRestoreResult(
    result: BrowserRestoreRecentlyClosedTabResult,
    host: BrowserCloseTabApplicationHost
  ): void {
    host.persistActiveTabSnapshot('restore-recently-closed');
    host.applyRestoredTabState(result.tabs, result.activeTabId);
    this.dependencies.tabSwitchCoordinator.synchronizeWebTabsAndPreviewAssets();
    this.dependencies.recentlyClosedApplicationCoordinator.acceptRestoredRecords(result.remainingRecords);
    host.requestCloseTabsOverview();
    this.dependencies.tabSwitchCoordinator.synchronizeAfterTabChange();
    this.persistTabs();
    host.setHelperMessage('已恢复最近关闭的标签页。');
  }

  private buildSingleRestoreOutcome(
    result: BrowserRestoreRecentlyClosedTabResult
  ): BrowserRecentlyClosedRestoreOutcome {
    return {
      restored: result.restored,
      restoredCount: result.restored ? 1 : 0,
      activeTabId: result.activeTabId,
      summaryLine: result.summaryLine
    };
  }

  private allowRecentlyClosedRestore(
    state: BrowserTabCloseApplicationState,
    host: BrowserCloseTabApplicationHost
  ): boolean {
    const decision = this.dependencies.recentlyClosedApplicationCoordinator.buildRestoreBoundaryDecision(
      state.dataScope,
      state.privacyMode
    );
    if (!decision.allowed) {
      host.showToast(decision.helperText);
    }
    return decision.allowed;
  }

  private buildBlockedRestoreOutcome(activeTabId: string): BrowserRecentlyClosedRestoreOutcome {
    return {
      restored: false,
      restoredCount: 0,
      activeTabId: activeTabId,
      summaryLine: 'recentlyClosedRestore restored=0 reason=private_boundary'
    };
  }

  private findTabById(tabs: BrowserTabState[], tabId: string): BrowserTabState | undefined {
    return tabs.find((item: BrowserTabState) => item.id === tabId);
  }

  private resolveRecentlyClosedSkipReason(tab: BrowserTabState | undefined): string {
    if (this.isDocumentViewerBrowserTab(tab, this.dependencies.documentViewerService)) {
      return 'document_viewer';
    }
    if (this.dependencies.siteClearOnCloseCoordinator.shouldSkipRecentlyClosed(tab)) {
      return 'site_clear_on_close';
    }
    return '';
  }

  private buildRecentlyClosedSkippedResult(
    reason: string
  ): BrowserRecentlyClosedRecordOutcome {
    return {
      recorded: false,
      reason: reason,
      summaryLine: `recentlyClosedRecord recorded=0 reason=${reason}`
    };
  }

  private isDocumentViewerBrowserTab(
    tab: BrowserTabState | undefined,
    documentViewerService: DocumentViewerService
  ): boolean {
    if (tab === undefined) {
      return false;
    }
    const candidates: string[] = [
      tab.pendingUrl,
      tab.url,
      tab.lastGoodUrl,
      tab.lastRestorableUrl
    ];
    tab.navigationHistory.forEach((url: string) => {
      candidates.push(url);
    });
    for (let index = 0; index < candidates.length; index += 1) {
      const url = candidates[index].trim();
      if (url.length > 0 && documentViewerService.resolveChromePolicy(url).active) {
        return true;
      }
    }
    return false;
  }
}
