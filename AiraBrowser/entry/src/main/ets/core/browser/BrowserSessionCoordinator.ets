import { BrowserTabState } from '../tabs/TabManager';
import {
  BrowserRetentionSettings,
  TabCrashReason
} from '../../common/models/BrowserModels';
import { webview } from '@kit.ArkWeb';
import {
  ActivateTabRuntimeResult,
  EnsureTabRuntimeResult,
  TabRuntimeRegistry
} from '../tabs/TabRuntimeRegistry';
import { WebRuntimePoolPolicy, WebRuntimeRetentionPlan } from '../web/WebRuntimePoolPolicy';
import {
  WebTabRuntimeControllerFactory,
  WebTabRuntimePatch,
  WebTabRuntimeRecord
} from '../web/WebTabRuntime';
import { BrowserMemoryPressureCoordinator, BrowserMemoryPressureOptions } from './BrowserMemoryPressureCoordinator';
import {
  BrowserMaterializationOptions,
  DEFAULT_BROWSER_MATERIALIZATION_POLICY
} from './BrowserMaterializationPolicy';

export interface ActivateBrowserTabPlan {
  activeRuntime: WebTabRuntimeRecord;
  backgroundRuntimeIds: string[];
}

export type BrowserRuntimeNavigationCommitGuard = (tabId: string, url: string, phase: 'stable' | 'provisional') => boolean;

export interface BrowserRuntimeSessionOperations {
  setRuntimeNavigationCommitGuard(guard?: BrowserRuntimeNavigationCommitGuard): void;
  updateRetentionSettings(settings: BrowserRetentionSettings): void;
  ensureTabRuntime(tab: BrowserTabState, windowId: string): EnsureTabRuntimeResult | undefined;
  activateTab(
    tab: BrowserTabState,
    tabs: BrowserTabState[],
    windowId: string,
    options?: BrowserMaterializationOptions
  ): ActivateBrowserTabPlan | undefined;
  buildRuntimeRetentionPlan(
    tabs: BrowserTabState[],
    activeTabId: string,
    options?: BrowserMemoryPressureOptions
  ): WebRuntimeRetentionPlan | undefined;
  applyRuntimeRetentionPlan(plan: WebRuntimeRetentionPlan): void;
  removeTab(tabId: string): WebTabRuntimeRecord | undefined;
  getRuntime(tabId: string): WebTabRuntimeRecord | undefined;
  markTabControllerAttached(tabId: string): WebTabRuntimeRecord | undefined;
  markTabWindowOpenHandoffPending(tabId: string): WebTabRuntimeRecord | undefined;
  consumeTabWindowOpenHandoffPending(tabId: string): boolean;
  replaceTabControllerForProxyRefresh(
    tabId: string,
    controller: webview.WebviewController
  ): WebTabRuntimeRecord | undefined;
  markTabControllerDetached(tabId: string): WebTabRuntimeRecord | undefined;
  markTabCrashed(
    tabId: string,
    degradedReason?: string,
    crashReason?: TabCrashReason
  ): WebTabRuntimeRecord | undefined;
  rememberTabNavigation(tabId: string, url: string): WebTabRuntimeRecord | undefined;
  rememberProvisionalTabNavigation(tabId: string, url: string): WebTabRuntimeRecord | undefined;
  patchRuntime(tabId: string, patch: WebTabRuntimePatch): WebTabRuntimeRecord | undefined;
  pruneWindowRuntimes(windowId: string, allowedTabIds: string[]): void;
  listWindowRuntimes(windowId: string): WebTabRuntimeRecord[];
  hasLiveWindowRuntime(windowId: string): boolean;
}

export class BrowserSessionCoordinator implements BrowserRuntimeSessionOperations {
  private runtimeRegistry: TabRuntimeRegistry;
  private runtimePoolPolicy: WebRuntimePoolPolicy = new WebRuntimePoolPolicy();
  private memoryPressureCoordinator: BrowserMemoryPressureCoordinator = new BrowserMemoryPressureCoordinator();
  private runtimeNavigationCommitGuard?: BrowserRuntimeNavigationCommitGuard;

  constructor(createController?: WebTabRuntimeControllerFactory) {
    this.runtimeRegistry = new TabRuntimeRegistry(createController);
  }

  setRuntimeNavigationCommitGuard(guard?: BrowserRuntimeNavigationCommitGuard): void {
    this.runtimeNavigationCommitGuard = guard;
  }

  updateRetentionSettings(settings: BrowserRetentionSettings): void {
    this.runtimePoolPolicy.updateConfig({
      maxHotBackgroundTabs: settings.maxHotBackgroundTabs,
      maxWarmBackgroundTabs: settings.maxWarmBackgroundTabs
    });
    this.memoryPressureCoordinator.updateConfig({
      staleAfterMs: settings.staleAfterMs,
      unstableTabGraceMs: 3 * 60 * 1000,
      hotBackgroundMaxAgeMs: settings.hotBackgroundMaxAgeMs,
      warmBackgroundMaxAgeMs: settings.warmBackgroundMaxAgeMs,
      loadingTabGraceMs: 45 * 1000,
      maxMountedRuntimeTabs: settings.maxMountedRuntimeTabs
    });
  }

  ensureTabRuntime(tab: BrowserTabState, windowId: string): EnsureTabRuntimeResult {
    return this.runtimeRegistry.ensureRuntime({
      tabId: tab.id,
      windowId: windowId,
      initialUrl: tab.url,
      initialTitle: tab.title,
      state: tab.runtimeState,
      lastActiveAt: tab.lastActiveAt,
      pendingUrl: tab.pendingUrl,
      snapshotPath: tab.webStatePath,
      snapshotUpdatedAt: tab.webStateUpdatedAt,
      lastRestoreReason: tab.lastRestoreReason,
      lastDiscardReason: tab.lastDiscardReason,
      lastCrashReason: tab.lastCrashReason
    });
  }

  activateTab(
    tab: BrowserTabState,
    tabs: BrowserTabState[],
    windowId: string,
    options: BrowserMaterializationOptions = {}
  ): ActivateBrowserTabPlan | undefined {
    const materializationPolicy = options.materializationPolicy ?? DEFAULT_BROWSER_MATERIALIZATION_POLICY;
    if (materializationPolicy !== 'existing_only' || this.runtimeRegistry.getRuntime(tab.id) !== undefined) {
      this.ensureTabRuntime(tab, windowId);
    }
    tabs.forEach((item: BrowserTabState) => {
      if (item.id !== tab.id && !item.isHome) {
        if (materializationPolicy === 'all' || this.runtimeRegistry.getRuntime(item.id) !== undefined) {
          this.ensureTabRuntime(item, windowId);
        }
      }
    });
    const activation = this.runtimeRegistry.activateRuntime(tab.id, Date.now());
    if (activation === undefined) {
      return undefined;
    }
    const plan: ActivateBrowserTabPlan = {
      activeRuntime: activation.activeRuntime,
      backgroundRuntimeIds: activation.backgroundRuntimeIds
    };
    return plan;
  }

  buildRuntimeRetentionPlan(
    tabs: BrowserTabState[],
    activeTabId: string,
    options: BrowserMemoryPressureOptions = {}
  ): WebRuntimeRetentionPlan {
    return this.memoryPressureCoordinator.buildRetentionPlan(this.runtimePoolPolicy, tabs, activeTabId, Date.now(), options);
  }

  applyRuntimeRetentionPlan(plan: WebRuntimeRetentionPlan): void {
    Object.keys(plan.runtimeStates).forEach((tabId: string) => {
      const nextState = plan.runtimeStates[tabId];
      const mounted = plan.mountedTabIds.includes(tabId);
      this.runtimeRegistry.patchRuntime(tabId, {
        state: nextState,
        hasLiveController: mounted ? undefined : false
      });
    });
  }

  removeTab(tabId: string): WebTabRuntimeRecord | undefined {
    return this.runtimeRegistry.removeRuntime(tabId);
  }

  getRuntime(tabId: string): WebTabRuntimeRecord | undefined {
    return this.runtimeRegistry.getRuntime(tabId);
  }

  markTabControllerAttached(tabId: string): WebTabRuntimeRecord | undefined {
    return this.runtimeRegistry.markControllerAttached(tabId);
  }

  markTabWindowOpenHandoffPending(tabId: string): WebTabRuntimeRecord | undefined {
    return this.runtimeRegistry.markWindowOpenHandoffPending(tabId);
  }

  consumeTabWindowOpenHandoffPending(tabId: string): boolean {
    return this.runtimeRegistry.consumeWindowOpenHandoffPending(tabId);
  }

  replaceTabControllerForProxyRefresh(
    tabId: string,
    controller: webview.WebviewController
  ): WebTabRuntimeRecord | undefined {
    return this.runtimeRegistry.replaceControllerForProxyRefresh(tabId, controller);
  }

  markTabControllerDetached(tabId: string): WebTabRuntimeRecord | undefined {
    return this.runtimeRegistry.detachController(tabId, true);
  }

  markTabCrashed(
    tabId: string,
    degradedReason: string = '',
    crashReason: TabCrashReason = 'unknown'
  ): WebTabRuntimeRecord | undefined {
    return this.runtimeRegistry.markRuntimeCrashed(tabId, degradedReason, crashReason);
  }

  rememberTabNavigation(tabId: string, url: string): WebTabRuntimeRecord | undefined {
    if (this.shouldBlockRuntimeNavigationCommit(tabId, url, 'stable')) {
      return this.runtimeRegistry.getRuntime(tabId);
    }
    return this.runtimeRegistry.rememberLastKnownUrl(tabId, url);
  }

  rememberProvisionalTabNavigation(tabId: string, url: string): WebTabRuntimeRecord | undefined {
    if (this.shouldBlockRuntimeNavigationCommit(tabId, url, 'provisional')) {
      return this.runtimeRegistry.getRuntime(tabId);
    }
    return this.runtimeRegistry.rememberProvisionalUrl(tabId, url);
  }

  patchRuntime(tabId: string, patch: WebTabRuntimePatch): WebTabRuntimeRecord | undefined {
    return this.runtimeRegistry.patchRuntime(tabId, patch);
  }

  pruneWindowRuntimes(windowId: string, allowedTabIds: string[]): void {
    this.runtimeRegistry.pruneWindowRuntimes(windowId, allowedTabIds);
  }

  listWindowRuntimes(windowId: string): WebTabRuntimeRecord[] {
    return this.runtimeRegistry.listWindowRuntimes(windowId);
  }

  getRuntimeRegistry(): TabRuntimeRegistry {
    return this.runtimeRegistry;
  }

  hasLiveWindowRuntime(windowId: string): boolean {
    return this.runtimeRegistry.listWindowRuntimes(windowId)
      .some((runtime: WebTabRuntimeRecord) => runtime.hasLiveController);
  }

  private shouldBlockRuntimeNavigationCommit(
    tabId: string,
    url: string,
    phase: 'stable' | 'provisional'
  ): boolean {
    return this.runtimeNavigationCommitGuard?.(tabId, url, phase) === true;
  }
}

/**
 * A fixed Browser Window Session connection. It exposes named runtime
 * operations only and never re-resolves mutable window or LocalStorage
 * identity. Callers check isConnected() before invoking a runtime operation.
 */
export class BrowserRuntimeSessionPort implements BrowserRuntimeSessionOperations {
  private readonly operations?: BrowserRuntimeSessionOperations;
  private readonly isSessionAvailable: () => boolean;

  constructor(
    operations?: BrowserRuntimeSessionOperations,
    isSessionAvailable: () => boolean = (): boolean => false
  ) {
    this.operations = operations;
    this.isSessionAvailable = isSessionAvailable;
  }

  isConnected(): boolean {
    return this.isSessionAvailable() && this.operations !== undefined;
  }

  private resolveOperations(): BrowserRuntimeSessionOperations | undefined {
    return this.isConnected() ? this.operations : undefined;
  }

  setRuntimeNavigationCommitGuard(guard?: BrowserRuntimeNavigationCommitGuard): void {
    this.resolveOperations()?.setRuntimeNavigationCommitGuard(guard);
  }

  updateRetentionSettings(settings: BrowserRetentionSettings): void {
    this.resolveOperations()?.updateRetentionSettings(settings);
  }

  ensureTabRuntime(tab: BrowserTabState, windowId: string): EnsureTabRuntimeResult | undefined {
    return this.resolveOperations()?.ensureTabRuntime(tab, windowId);
  }

  activateTab(
    tab: BrowserTabState,
    tabs: BrowserTabState[],
    windowId: string,
    options: BrowserMaterializationOptions = {}
  ): ActivateBrowserTabPlan | undefined {
    return this.resolveOperations()?.activateTab(tab, tabs, windowId, options);
  }

  buildRuntimeRetentionPlan(
    tabs: BrowserTabState[],
    activeTabId: string,
    options: BrowserMemoryPressureOptions = {}
  ): WebRuntimeRetentionPlan | undefined {
    return this.resolveOperations()?.buildRuntimeRetentionPlan(tabs, activeTabId, options);
  }

  applyRuntimeRetentionPlan(plan: WebRuntimeRetentionPlan): void {
    this.resolveOperations()?.applyRuntimeRetentionPlan(plan);
  }

  removeTab(tabId: string): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.removeTab(tabId);
  }

  getRuntime(tabId: string): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.getRuntime(tabId);
  }

  markTabControllerAttached(tabId: string): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.markTabControllerAttached(tabId);
  }

  markTabWindowOpenHandoffPending(tabId: string): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.markTabWindowOpenHandoffPending(tabId);
  }

  consumeTabWindowOpenHandoffPending(tabId: string): boolean {
    return this.resolveOperations()?.consumeTabWindowOpenHandoffPending(tabId) ?? false;
  }

  replaceTabControllerForProxyRefresh(
    tabId: string,
    controller: webview.WebviewController
  ): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.replaceTabControllerForProxyRefresh(tabId, controller);
  }

  markTabControllerDetached(tabId: string): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.markTabControllerDetached(tabId);
  }

  markTabCrashed(
    tabId: string,
    degradedReason: string = '',
    crashReason: TabCrashReason = 'unknown'
  ): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.markTabCrashed(tabId, degradedReason, crashReason);
  }

  rememberTabNavigation(tabId: string, url: string): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.rememberTabNavigation(tabId, url);
  }

  rememberProvisionalTabNavigation(tabId: string, url: string): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.rememberProvisionalTabNavigation(tabId, url);
  }

  patchRuntime(tabId: string, patch: WebTabRuntimePatch): WebTabRuntimeRecord | undefined {
    return this.resolveOperations()?.patchRuntime(tabId, patch);
  }

  pruneWindowRuntimes(windowId: string, allowedTabIds: string[]): void {
    this.resolveOperations()?.pruneWindowRuntimes(windowId, allowedTabIds);
  }

  listWindowRuntimes(windowId: string): WebTabRuntimeRecord[] {
    return this.resolveOperations()?.listWindowRuntimes(windowId) ?? [];
  }

  hasLiveWindowRuntime(windowId: string): boolean {
    return this.resolveOperations()?.hasLiveWindowRuntime(windowId) ?? false;
  }
}
