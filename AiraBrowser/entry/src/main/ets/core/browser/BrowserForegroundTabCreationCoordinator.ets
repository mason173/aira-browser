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
const FOREGROUND_HOME_TAB_PREVIEW_CAPTURE_TIMEOUT_MS: number = 600;

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
    const createdTabId = this.createNewTabNow(request);
    this.dependencies.privateModeLockCoordinator.synchronizeCurrentBoundary();
    return createdTabId;
  }

  private async captureOutgoingTabPreviewBeforeHome(host: BrowserForegroundTabCreationHost): Promise<void> {
    try {
      let timedOut = false;
      await Promise.race([
        host.captureCurrentTabPreviewForForegroundCreationAsync(),
        new Promise<boolean>((resolve: (value: boolean) => void) => {
          setTimeout(() => {
            timedOut = true;
            resolve(false);
          }, FOREGROUND_HOME_TAB_PREVIEW_CAPTURE_TIMEOUT_MS);
        })
      ]);
      if (timedOut) {
        // The shell is about to swap to the home surface. A snapshot that is
        // still running must not store whatever it ends up seeing (it could
        // capture HOME and attribute it to the outgoing web tab).
        host.cancelOutgoingTabPreviewCapture();
      }
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
    this.dependencies.resolveTabsOverviewSessionCoordinator().handle({ type: 'request_close' });
    if (coldStartRestorePatch !== undefined) {
      const state = host.resolveForegroundTabCreationState();
      host.applyTabCreationState({
        tabs: this.tabManager.updateTab(state.tabs, transition.activeTabId, coldStartRestorePatch)
      });
    }
    this.dependencies.resolveTabSwitchCoordinator().synchronizeActiveTab();
    this.dependencies.resolveTabSessionPersistenceCoordinator().persist();
    host.applyTabCreationState({ helperMessage: transition.helperMessage });
  }
}
