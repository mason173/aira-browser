import {
  BrowserLaunchPayload,
  BrowserWindowRuntime,
  resolveBrowserTabSessionProfileId
} from '../../app/runtime/BrowserWindowRuntime';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserTabBackgroundSessionSyncCoordinator } from '../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import { BrowserCreateTabOptions, BrowserTabState, BrowserTabManagerPort } from '../tabs/TabManager';
import {
  WebAppSessionCoordinator,
  WebAppSessionSnapshot
} from '../webapps/WebAppSessionCoordinator';
import { BrowserRecentlyClosedApplicationCoordinator } from './BrowserRecentlyClosedApplicationCoordinator';
import { BrowserTabPreviewCoordinator } from './BrowserTabPreviewCoordinator';
import { BrowserTabSessionPersistenceCoordinator } from './BrowserTabSessionPersistenceCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserWindowSuspendedContext } from './BrowserWindowContextState';
import {
  BrowserWindowSessionContextStateBinding,
  BrowserWindowSessionContextStateStore,
  resolveBrowserWindowSessionContextStateBinding
} from './BrowserWindowSessionContextState';

export interface BrowserWindowContextFacts {
  storage: LocalStorage | undefined;
  currentWindowId: string;
  homeProfileId: BrowserProfileId;
  homePrivacyMode: BrowserSessionPrivacyMode;
  homeDataScope: BrowserDataScope;
  windowScopeId: string;
  tabs: BrowserTabState[];
  activeTabId: string;
  tabSequence: number;
  showHomePage: boolean;
  isRestoringTabs: boolean;
  isBrowserShellVisible: boolean;
}

export interface BrowserWindowContextShell {
  resolveFacts: () => BrowserWindowContextFacts;
  persistActiveTabSnapshot: () => void;
  applySuspendedWindowPresentation: (reason: string) => void;
  applyWindowPresentation: (
    windowId: string,
    webAppSessionSnapshot: WebAppSessionSnapshot,
    reason: string
  ) => void;
  applyRestoredWindowPresentation: (context: BrowserWindowSuspendedContext, reason: string) => void;
  restoreTabsForCurrentWindow: (reason: string) => void;
  connectSearchInvocationSurface: () => void;
}

export interface BrowserWindowLaunchApplication {
  apply(payload: BrowserLaunchPayload): void;
}

export type BrowserWindowLaunchApplicationResolver = () => BrowserWindowLaunchApplication;

export interface BrowserWindowContextPort {
  connectSessionContextState(binding: BrowserWindowSessionContextStateBinding | undefined): void;
  disconnectSessionContextState(): void;
  resolveCurrentScope(): void;
  hasPendingWebSceneLaunch(): boolean;
  consumePendingLaunch(source: string): boolean;
  consumePendingWebSceneLaunch(source: string): boolean;
  resolveCurrentTabSessionBoundary(): BrowserCreateTabOptions;
  resolveCurrentTabSessionProfileId(): BrowserProfileId;
  schedulePendingLaunchPolling(): void;
  stopPendingLaunchPolling(): void;
  getSuspendedWindowTabsByWindowId(): Record<string, BrowserTabState[] | undefined>;
}

export interface BrowserWindowContextDependencies {
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator;
  tabSessionPersistenceCoordinator: BrowserTabSessionPersistenceCoordinator;
  recentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator;
  tabManager: BrowserTabManagerPort;
  tabPreviewCoordinator: BrowserTabPreviewCoordinator;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  webAppSessionCoordinator: WebAppSessionCoordinator;
}

interface BrowserWindowContextParkableDesktopWebEntryInput {
  currentWindowId: string;
  showHomePage: boolean;
  activeTabId: string;
  activeTab: BrowserTabState | undefined;
  hasHostedController: boolean;
  hasLiveRuntimeController: boolean;
}

const DEFAULT_PENDING_LAUNCH_POLL_DELAY_MS: number = 700;
const DEFAULT_PENDING_LAUNCH_MAX_POLL_ATTEMPTS: number = 8;

/**
 * Owns activation of the current in-app browser window context: scope
 * resolution, live suspend/restore, desktop Web-entry parking, cold-restore
 * delegation, and pending launch arbitration/polling.
 */
export class BrowserWindowContextCoordinator implements BrowserWindowContextPort {
  private readonly dependencies: BrowserWindowContextDependencies;
  private readonly shell: BrowserWindowContextShell;
  private readonly resolveLaunchApplication: BrowserWindowLaunchApplicationResolver;
  private switching: boolean = false;
  private contextStateStore?: BrowserWindowSessionContextStateStore;
  private contextStateConnected: boolean = false;
  private contextStateGeneration: number = 0;
  private pendingLaunchPollTimer: number = -1;
  private pendingLaunchAttemptsRemaining: number = 0;
  private pendingLaunchPollGeneration: number = 0;

  constructor(
    dependencies: BrowserWindowContextDependencies,
    shell: BrowserWindowContextShell,
    resolveLaunchApplication: BrowserWindowLaunchApplicationResolver
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
    this.resolveLaunchApplication = resolveLaunchApplication;
  }

  connectSessionContextState(binding: BrowserWindowSessionContextStateBinding | undefined): void {
    const nextStore = resolveBrowserWindowSessionContextStateBinding(binding);
    if (this.contextStateConnected && this.contextStateStore === nextStore) {
      return;
    }
    this.contextStateConnected = true;
    this.contextStateStore = nextStore;
    this.contextStateGeneration += 1;
    this.stopPendingLaunchPolling();
  }

  disconnectSessionContextState(): void {
    if (!this.contextStateConnected && this.contextStateStore === undefined) {
      return;
    }
    this.contextStateConnected = false;
    this.contextStateStore = undefined;
    this.contextStateGeneration += 1;
    this.stopPendingLaunchPolling();
  }

  resolveCurrentScope(): void {
    if (!this.canUseConnectedSessionContext()) {
      return;
    }
    const facts = this.shell.resolveFacts();
    const nextWindowId = BrowserWindowRuntime.resolveWindowIdFromStorage(facts.storage);
    if (facts.currentWindowId.length > 0 && facts.currentWindowId !== nextWindowId && !facts.isRestoringTabs) {
      this.switchTo(nextWindowId, 'resolve-window-scope');
      return;
    }
    this.applyWindowId(nextWindowId, facts.storage, 'resolve-window-scope');
  }

  switchTo(target: string, reason: string): void {
    if (!this.canUseConnectedSessionContext()) {
      return;
    }
    const facts = this.shell.resolveFacts();
    const normalized = BrowserWindowRuntime.resolveWindowId(target);
    const current = facts.currentWindowId;
    if (current === normalized) {
      return;
    }
    if (this.switching) {
      return;
    }
    this.switching = true;
    try {
      this.flushCurrentTabsForSwitch();
      this.suspendCurrentWindowContext(facts, reason);
      this.applyWindowId(normalized, facts.storage, reason);
      if (this.restoreSuspendedWindowContext(normalized, reason)) {
        this.clearPendingLaunchForRestoredWindow(reason);
      } else {
        this.shell.restoreTabsForCurrentWindow(reason);
      }
    } finally {
      this.switching = false;
    }
  }

  consumePendingLaunch(source: string): boolean {
    if (!this.canUseConnectedSessionContext()) {
      return false;
    }
    const facts = this.shell.resolveFacts();
    const desiredWindowId = BrowserWindowRuntime.resolveWindowIdFromStorage(facts.storage);
    if (desiredWindowId !== facts.currentWindowId && !facts.isRestoringTabs && !this.switching) {
      this.switchTo(desiredWindowId, `pending-launch:${source}`);
      return true;
    }
    const launchPayload = BrowserWindowRuntime.consumePendingLaunch(facts.currentWindowId, facts.storage);
    if (launchPayload === undefined) {
      return false;
    }
    this.resolveLaunchApplication().apply(launchPayload);
    return true;
  }

  hasPendingWebSceneLaunch(): boolean {
    if (!this.canUseConnectedSessionContext()) {
      return false;
    }
    const facts = this.shell.resolveFacts();
    return BrowserWindowRuntime.isWebSceneLaunchPayload(
      BrowserWindowRuntime.peekPendingLaunch(facts.currentWindowId, facts.storage)
    );
  }

  consumePendingWebSceneLaunch(source: string): boolean {
    if (!this.canUseConnectedSessionContext()) {
      return false;
    }
    const facts = this.shell.resolveFacts();
    const launchPayload = BrowserWindowRuntime.peekPendingLaunch(facts.currentWindowId, facts.storage);
    if (!BrowserWindowRuntime.isWebSceneLaunchPayload(launchPayload)) {
      return false;
    }
    return this.consumePendingLaunch(source);
  }

  resolveCurrentTabSessionBoundary(): BrowserCreateTabOptions {
    const facts = this.shell.resolveFacts();
    const activeTab = this.dependencies.tabManager.getActiveTab(facts.tabs, facts.activeTabId);
    const pendingLaunchPayload = BrowserWindowRuntime.peekPendingLaunch(
      facts.currentWindowId,
      facts.storage
    );
    if (pendingLaunchPayload !== undefined && activeTab === undefined && facts.tabs.length === 0) {
      return {
        profileId: pendingLaunchPayload.profileId,
        privacyMode: pendingLaunchPayload.privacyMode,
        dataScope: pendingLaunchPayload.dataScope
      };
    }
    if (facts.showHomePage) {
      return {
        profileId: facts.homeProfileId,
        privacyMode: facts.homePrivacyMode,
        dataScope: facts.homeDataScope
      };
    }
    if (activeTab !== undefined) {
      return {
        profileId: activeTab.profileId,
        privacyMode: activeTab.privacyMode,
        dataScope: activeTab.dataScope
      };
    }
    if (pendingLaunchPayload !== undefined) {
      return {
        profileId: pendingLaunchPayload.profileId,
        privacyMode: pendingLaunchPayload.privacyMode,
        dataScope: pendingLaunchPayload.dataScope
      };
    }
    return {
      profileId: facts.homeProfileId,
      privacyMode: facts.homePrivacyMode,
      dataScope: facts.homeDataScope
    };
  }

  resolveCurrentTabSessionProfileId(): BrowserProfileId {
    return resolveBrowserTabSessionProfileId(this.resolveCurrentTabSessionBoundary().profileId);
  }

  schedulePendingLaunchPolling(): void {
    if (!this.canUseConnectedSessionContext()) {
      return;
    }
    this.stopPendingLaunchPolling();
    this.pendingLaunchAttemptsRemaining = DEFAULT_PENDING_LAUNCH_MAX_POLL_ATTEMPTS;
    this.scheduleNextPendingLaunchPoll();
  }

  stopPendingLaunchPolling(): void {
    if (this.pendingLaunchPollTimer >= 0) {
      clearTimeout(this.pendingLaunchPollTimer);
      this.pendingLaunchPollTimer = -1;
    }
    this.pendingLaunchAttemptsRemaining = 0;
    this.pendingLaunchPollGeneration += 1;
  }

  getSuspendedWindowTabsByWindowId(): Record<string, BrowserTabState[] | undefined> {
    if (!this.canUseConnectedSessionContext()) {
      return {};
    }
    const result: Record<string, BrowserTabState[] | undefined> = {};
    const contexts = this.contextStateStore?.getSuspendedContexts() ?? {};
    Object.keys(contexts).forEach((windowId: string) => {
      const context = contexts[windowId];
      result[windowId] = context === undefined ? undefined : context.tabs.slice();
    });
    return result;
  }

  private flushCurrentTabsForSwitch(): void {
    this.shell.persistActiveTabSnapshot();
    this.dependencies.tabSessionPersistenceCoordinator.persist();
    this.dependencies.recentlyClosedApplicationCoordinator.flushForWindowSwitch();
  }

  private suspendCurrentWindowContext(facts: BrowserWindowContextFacts, reason: string): void {
    this.dependencies.backgroundSessionSyncCoordinator.handleWindowHidden(facts.windowScopeId);
    this.suspendWindowContext(facts.currentWindowId, {
      tabs: facts.tabs,
      activeTabId: facts.activeTabId,
      tabSequence: facts.tabSequence,
      showHomePage: facts.showHomePage
    });
    const activeTab = this.dependencies.tabManager.getActiveTab(facts.tabs, facts.activeTabId);
    this.suspendHostedSurfaceForWindowContext({
      currentWindowId: facts.currentWindowId,
      showHomePage: facts.showHomePage,
      activeTabId: facts.activeTabId,
      activeTab: activeTab,
      hasHostedController: facts.activeTabId.trim().length > 0 &&
        this.dependencies.hostedRuntimeSurfacePort.hasHostedController(facts.activeTabId),
      hasLiveRuntimeController: facts.activeTabId.trim().length > 0 &&
        this.dependencies.runtimeLifecyclePort.hasLiveRuntimeController(facts.activeTabId)
    });
    this.dependencies.recentlyClosedApplicationCoordinator.resetForWindowSwitch();
    this.shell.applySuspendedWindowPresentation(reason);
  }

  private suspendWindowContext(windowId: string, context: BrowserWindowSuspendedContext): void {
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    this.contextStateStore?.setSuspendedContext(normalizedWindowId, context);
  }

  private restoreSuspendedWindowContext(windowId: string, reason: string): boolean {
    const context = this.takeSuspendedWindowContext(
      windowId,
      this.dependencies.runtimeLifecyclePort.hasLiveWindowRuntime(windowId)
    );
    if (context === undefined) {
      return false;
    }
    this.shell.applyRestoredWindowPresentation(context, reason);
    this.dependencies.recentlyClosedApplicationCoordinator.activateWindow(
      this.resolveCurrentTabSessionProfileId()
    );
    this.dependencies.tabSwitchCoordinator.synchronizeActiveTab();
    this.shell.connectSearchInvocationSurface();
    this.consumePendingLaunch(`restore-live-context:${windowId}`);
    this.schedulePendingLaunchPolling();
    return true;
  }

  private takeSuspendedWindowContext(
    windowId: string,
    hasLiveWindowRuntime: boolean
  ): BrowserWindowSuspendedContext | undefined {
    if (!hasLiveWindowRuntime) {
      return undefined;
    }
    const normalizedWindowId = BrowserWindowRuntime.resolveWindowId(windowId);
    return this.contextStateStore?.takeSuspendedContext(normalizedWindowId);
  }

  private applyWindowId(
    windowId: string,
    storage: LocalStorage | undefined,
    reason: string
  ): void {
    if (!this.canUseConnectedSessionContext()) {
      return;
    }
    const contextStateGeneration = this.contextStateGeneration;
    this.shell.applyWindowPresentation(
      windowId,
      this.dependencies.webAppSessionCoordinator.snapshot(windowId),
      `${reason}:cached`
    );
    this.dependencies.tabManager.setWindowId(windowId);
    this.dependencies.tabPreviewCoordinator.setCacheScopeId(windowId);
    BrowserWindowRuntime.markWindowForeground(windowId);
    this.dependencies.backgroundSessionSyncCoordinator.markWindowActive(windowId);
    if (storage !== undefined) {
      BrowserWindowRuntime.registerWindow(windowId, storage);
    }
    void this.dependencies.webAppSessionCoordinator.refreshSettings(windowId).then((snapshot: WebAppSessionSnapshot) => {
      if (!this.canUseConnectedSessionContext(contextStateGeneration)) {
        return;
      }
      if (this.shell.resolveFacts().currentWindowId !== windowId) {
        return;
      }
      this.shell.applyWindowPresentation(
        windowId,
        snapshot,
        `${reason}:settings`
      );
    });
  }

  private resolveParkableDesktopWebEntryTabId(input: BrowserWindowContextParkableDesktopWebEntryInput): string {
    const currentWindowId = BrowserWindowRuntime.resolveWindowId(input.currentWindowId);
    const mainWindowId = BrowserWindowRuntime.resolveWindowId(undefined);
    const activeTabId = input.activeTabId.trim();
    if (currentWindowId === mainWindowId || input.showHomePage || activeTabId.length === 0) {
      return '';
    }
    if (input.activeTab === undefined || !input.hasHostedController || !input.hasLiveRuntimeController) {
      return '';
    }
    return activeTabId;
  }

  private suspendHostedSurfaceForWindowContext(input: BrowserWindowContextParkableDesktopWebEntryInput): void {
    const parkedTabId = this.resolveParkableDesktopWebEntryTabId(input);
    if (parkedTabId.length > 0 &&
      this.dependencies.hostedRuntimeSurfacePort.parkActiveDesktopWebEntry(parkedTabId)) {
      return;
    }
    this.dependencies.hostedRuntimeSurfacePort.detachActive();
  }

  private clearPendingLaunchForRestoredWindow(reason: string): void {
    const facts = this.shell.resolveFacts();
    const launchPayload = BrowserWindowRuntime.consumePendingLaunch(facts.currentWindowId, facts.storage);
    if (launchPayload === undefined) {
      return;
    }
  }

  private scheduleNextPendingLaunchPoll(): void {
    if (!this.canUseConnectedSessionContext()) {
      return;
    }
    const facts = this.shell.resolveFacts();
    if (this.pendingLaunchAttemptsRemaining <= 0 || !facts.isBrowserShellVisible) {
      this.stopPendingLaunchPolling();
      return;
    }
    const generation = ++this.pendingLaunchPollGeneration;
    const contextStateGeneration = this.contextStateGeneration;
    this.pendingLaunchPollTimer = setTimeout(() => {
      if (generation !== this.pendingLaunchPollGeneration ||
        !this.canUseConnectedSessionContext(contextStateGeneration)) {
        return;
      }
      this.pendingLaunchPollTimer = -1;
      this.pendingLaunchAttemptsRemaining -= 1;
      if (this.consumePendingLaunch('poll')) {
        this.pendingLaunchAttemptsRemaining = DEFAULT_PENDING_LAUNCH_MAX_POLL_ATTEMPTS;
      }
      this.scheduleNextPendingLaunchPoll();
    }, DEFAULT_PENDING_LAUNCH_POLL_DELAY_MS);
  }

  private canUseConnectedSessionContext(expectedGeneration?: number): boolean {
    if (!this.contextStateConnected) {
      return false;
    }
    if (expectedGeneration !== undefined && expectedGeneration !== this.contextStateGeneration) {
      return false;
    }
    return this.contextStateStore?.isAvailable() === true;
  }

}
