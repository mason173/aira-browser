import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import {
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  BrowserCreateTabOptions,
  BrowserTabRuntimePatch,
  BrowserTabState,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import {
  BrowserTabTransitionCoordinator,
  BrowserTabTransitionResult
} from './BrowserTabTransitionCoordinator';
import { CreateNewTabRuntimeOptions } from './BrowserShellRuntimeContracts';
import { BrowserPrivateModeLockCoordinator } from '../privacy/BrowserPrivateModeLockCoordinator';
import {
  BrowserPrivateProfileCookieLifecycleHost,
  BrowserPrivateProfileLifecycleCoordinator
} from './BrowserPrivateProfileLifecycleCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserTabSessionPersistenceCoordinator } from './BrowserTabSessionPersistenceCoordinator';
import {
  resolveBrowserNewWindowTestTitle
} from '../../app/debug/BrowserNewWindowTestPage';
import { BrowserTabsOverviewSessionCoordinator } from './BrowserTabsOverviewSessionCoordinator';

export interface BrowserForegroundTabCreationRequest {
  initialUrl: string;
  initialTitle: string;
  options: BrowserCreateTabOptions;
  runtimeOptions: CreateNewTabRuntimeOptions;
  homePresentationMode?: 'tabs_overview' | 'direct';
  prepareCreatedTab?: (tabId: string) => void;
}

export interface BrowserForegroundTabCreationState {
  tabs: BrowserTabState[];
  activeTabId: string;
  tabSequence: number;
  homeUrl: string;
}

export interface BrowserTabCreationStateApplication {
  tabs?: BrowserTabState[];
  activeTabId?: string;
  tabSequence?: number;
  helperMessage?: string;
}

// Time-box for the leave-capture awaited before switching to the home surface:
// long enough for a component snapshot of the visible shell (typically well
// under 200ms, but slower while the page is still rendering), short enough
// that a stuck capture never blocks the "+" action noticeably.

export interface BrowserForegroundTabCreationHost {
  resolveForegroundTabCreationState: () => BrowserForegroundTabCreationState;
  persistActiveTabSnapshot: (reason: string) => void;
  captureCurrentTabPreviewForForegroundCreationAsync: () => Promise<boolean>;
  cancelOutgoingTabPreviewCapture: () => void;
  applyTabCreationState: (application: BrowserTabCreationStateApplication) => void;
}

export type BrowserForegroundTabCreationHostResolver = () => BrowserForegroundTabCreationHost;

export interface BrowserForegroundTabCreationDependencies {
  privateModeLockCoordinator: BrowserPrivateModeLockCoordinator;
  privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator;
  privateProfileCookieLifecycleHost: BrowserPrivateProfileCookieLifecycleHost;
  resolveTabHomeCoordinator: () => BrowserTabHomeCoordinator;
  resolveTabSwitchCoordinator: () => BrowserTabSwitchCoordinator;
  resolveTabSessionPersistenceCoordinator: () => BrowserTabSessionPersistenceCoordinator;
  resolveTabsOverviewSessionCoordinator: () => BrowserTabsOverviewSessionCoordinator;
}

export class BrowserForegroundTabCreationCoordinator {
  private readonly tabManager: BrowserTabManagerPort;
  private readonly resolveHost: BrowserForegroundTabCreationHostResolver;
  private readonly dependencies: BrowserForegroundTabCreationDependencies;
  private transitionCoordinator: BrowserTabTransitionCoordinator = new BrowserTabTransitionCoordinator();

  constructor(
    tabManager: BrowserTabManagerPort,
    resolveHost: BrowserForegroundTabCreationHostResolver,
    dependencies: BrowserForegroundTabCreationDependencies
  ) {
    this.tabManager = tabManager;
    this.resolveHost = resolveHost;
    this.dependencies = dependencies;
  }

  async createNewTab(request: BrowserForegroundTabCreationRequest): Promise<string> {
    const host = this.resolveHost();
    const targetPrivacyMode = normalizeBrowserSessionPrivacyMode(request.options.privacyMode);
    const targetDataScope = normalizeBrowserDataScope(request.options.dataScope, targetPrivacyMode);
    if (!await this.dependencies.privateModeLockCoordinator.ensureUnlocked(
      targetPrivacyMode,
      targetDataScope,
      'enter_private_home'
    )) {
      return '';
    }
    await this.dependencies.privateProfileLifecycleCoordinator.restorePreservedCookiesOnEnterIfNeeded(
      targetPrivacyMode,
      targetDataScope,
      this.dependencies.privateProfileCookieLifecycleHost
    );
    if (request.initialUrl === host.resolveForegroundTabCreationState().homeUrl &&
      request.homePresentationMode !== 'direct') {
      // Capture the outgoing tab's visible surface (page + top chrome) BEFORE
      // create_home_tab swaps the shell to the home surface — afterwards the
      // web page and its chrome are gone and only chrome-less fallbacks exist.
      // Time-boxed so "+" never blocks on a slow capture.
      await this.captureOutgoingTabPreviewBeforeHome(host);
      this.dependencies.resolveTabsOverviewSessionCoordinator().handle({
        type: 'create_home_tab',
        helperMessage: targetPrivacyMode === 'private' ? '已打开隐私标签页' : '已打开新标签页',
        options: request.options,
        keepTabsOverviewMounted: false,
        playHomeReveal: true
      });
      this.dependencies.privateModeLockCoordinator.synchronizeCurrentBoundary();
      return host.resolveForegroundTabCreationState().activeTabId;
    }
    // A context-menu "open in new tab" swaps the visible page immediately.
    // Save the current frame first, or the source card is blank in the tab manager.
    if (request.runtimeOptions.skipCurrentTabPreviewForForegroundOpen !== true) {
      await host.captureCurrentTabPreviewForForegroundCreationAsync();
    }
    const createdTabId = this.createNewTabNow({
      initialUrl: request.initialUrl,
      initialTitle: request.initialTitle,
      options: request.options,
      runtimeOptions: {
        skipCurrentTabPreviewForForegroundOpen: true,
        restoreAsColdStart: request.runtimeOptions.restoreAsColdStart
      },
      homePresentationMode: request.homePresentationMode,
      prepareCreatedTab: request.prepareCreatedTab
    });
    this.dependencies.privateModeLockCoordinator.synchronizeCurrentBoundary();
    return createdTabId;
  }

  private async captureOutgoingTabPreviewBeforeHome(host: BrowserForegroundTabCreationHost): Promise<void> {
    try {
      // Wait until the outgoing page frame is stored. Switching to home first
      // would leave that tab's card blank, and a late capture could store home.
      await host.captureCurrentTabPreviewForForegroundCreationAsync();
    } catch (_error) {
      // Best-effort: never block home creation on a preview-capture failure.
    }
  }

  createNewTabNow(request: BrowserForegroundTabCreationRequest): string {
    const host = this.resolveHost();
    host.persistActiveTabSnapshot('create-new-tab');
    if (request.runtimeOptions.skipCurrentTabPreviewForForegroundOpen !== true) {
      void host.captureCurrentTabPreviewForForegroundCreationAsync();
    }
    const state = host.resolveForegroundTabCreationState();
    const createsHome = request.initialUrl === state.homeUrl;
    if (createsHome) {
      this.dependencies.resolveTabHomeCoordinator().prepareHomeForwardForNewTab();
    }
    const resolvedTitle = request.initialTitle === '新标签页'
      ? resolveBrowserNewWindowTestTitle(request.initialUrl, request.initialTitle)
      : request.initialTitle;
    const transition = this.transitionCoordinator.createTab(
      this.tabManager,
      state.tabs,
      state.tabSequence,
      request.initialUrl,
      resolvedTitle,
      state.homeUrl,
      request.options
    );
    if (createsHome) {
      this.dependencies.resolveTabHomeCoordinator().bindHomeForwardTab(transition.activeTabId, request.options);
    }
    request.prepareCreatedTab?.(transition.activeTabId);
    const coldStartRestorePatch: BrowserTabRuntimePatch | undefined =
      request.runtimeOptions.restoreAsColdStart === true ? {
        lastRestoreReason: 'cold_start',
        lastRestoreType: 'reload',
        webStatePath: '',
        webStateUpdatedAt: 0,
        scrollOffsetY: 0
    } : undefined;
    this.applyForegroundTabCreation(transition, coldStartRestorePatch, host);
    return transition.activeTabId;
  }

  async createNewTabFromWindowMove(
    request: BrowserForegroundTabCreationRequest,
    restoredPatch: BrowserTabRuntimePatch
  ): Promise<string> {
    this.createNewTabNow(request);
    const host = this.resolveHost();
    const state = host.resolveForegroundTabCreationState();
    const targetTabId = state.activeTabId;
    if (targetTabId.length <= 0 || !state.tabs.some((tab: BrowserTabState): boolean => tab.id === targetTabId)) {
      throw new Error('The target window did not create a tab for the move request.');
    }
    host.applyTabCreationState({
      tabs: this.tabManager.updateTab(state.tabs, targetTabId, restoredPatch)
    });
    const tabSwitchCoordinator = this.dependencies.resolveTabSwitchCoordinator();
    tabSwitchCoordinator.synchronizeWebTabsAndPreviewAssets();
    tabSwitchCoordinator.publishActiveTabShellState();
    await this.dependencies.resolveTabSessionPersistenceCoordinator().persistAndWait();
    return targetTabId;
  }

  private applyForegroundTabCreation(
    transition: BrowserTabTransitionResult,
    coldStartRestorePatch: BrowserTabRuntimePatch | undefined,
    host: BrowserForegroundTabCreationHost
  ): void {
    host.applyTabCreationState({ tabs: transition.tabs });
    this.dependencies.resolveTabSwitchCoordinator().synchronizeWebTabsAndPreviewAssets();
    host.applyTabCreationState({
      activeTabId: transition.activeTabId,
      tabSequence: transition.tabSequence
    });
    if (coldStartRestorePatch !== undefined) {
      const state = host.resolveForegroundTabCreationState();
      host.applyTabCreationState({
        tabs: this.tabManager.updateTab(state.tabs, transition.activeTabId, coldStartRestorePatch)
      });
    }
    // Leave the homepage before the overview starts fading. Otherwise the close
    // still treats home as the destination and the opened page appears only after
    // that homepage has already shown through.
    this.dependencies.resolveTabSwitchCoordinator().synchronizeActiveTab();
    this.dependencies.resolveTabsOverviewSessionCoordinator().handle({ type: 'request_close' });
    this.dependencies.resolveTabSessionPersistenceCoordinator().persist();
    host.applyTabCreationState({ helperMessage: transition.helperMessage });
  }
}
