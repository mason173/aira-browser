import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserActiveRuntimeAttachmentResult,
  BrowserActiveRuntimeHost,
  BrowserControllerAttachmentHost,
  BrowserControllerAttachmentOptions,
  BrowserRuntimeLifecycleCoordinator,
  BrowserRuntimeSessionSyncHost
} from '../../core/browser/BrowserRuntimeLifecycleCoordinator';
import {
  ActivateBrowserTabPlan,
  BrowserRuntimeNavigationCommitGuard,
  BrowserRuntimeSessionOperations,
  BrowserRuntimeSessionPort,
  BrowserSessionCoordinator
} from '../../core/browser/BrowserSessionCoordinator';
import {
  BrowserWindowSessionBackgroundBinding,
  BrowserWindowSessionBackgroundOperations,
  BrowserWindowSessionRuntimeBinding,
  resolveBrowserWindowSessionBackgroundBinding,
  resolveBrowserWindowSessionRuntimeBinding,
  resolveBrowserWindowSessionRuntimeLifecycleBinding
} from '../../core/browser/BrowserWindowSessionApplication';
import {
  normalizeNavigationTarget,
  resolveCurrentSiteUrl
} from '../../core/browser/AddressDisplayFormatter';
import {
  BrowserWebDataLoadActiveControllerState,
  BrowserWebDataLoadActiveControllerStateApply,
  BrowserWebDataLoadActiveControllerStateValue,
  BrowserWebDataLoadBeforeLoad,
  BrowserWebDataLoadEventContextSync,
  BrowserWebDataLoadFailureRecorder,
  BrowserWebDataLoadLifecyclePort,
  BrowserWebDataLoadMutationPort,
  BrowserWebDataLoadMutationResult,
  BrowserWebDataLoadMutationResultValue,
  BrowserWebDataLoadRuntimeRequestAdapter,
  BrowserWebLoadDataPayload
} from '../../core/browser/BrowserWebLoadCoordinator';
import {
  BrowserDataScope,
  BrowserRetentionSettings,
  BrowserSessionPrivacyMode,
  TabRuntimeState,
  TabCrashReason,
  TabRestoreReason,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { BrowserTabManagerPort, BrowserTabRuntimePatch, BrowserTabState, TabManager } from '../../core/tabs/TabManager';
import { EnsureTabRuntimeResult, TabRuntimeRegistry } from '../../core/tabs/TabRuntimeRegistry';
import {
  BrowserTabBackgroundSessionSyncRequest,
  BrowserTabBackgroundSessionSyncResult
} from '../../core/browser/BrowserTabBackgroundManagerCoordinator';
import {
  BrowserTabBackgroundTrigger,
  BrowserTabDiscardTask,
  BrowserTabPageBehaviorState,
  BrowserTabPreviewAssetState,
  BrowserSystemMemoryPressureSnapshot,
  BrowserTabWindowState
} from '../../core/browser/BrowserTabBackgroundTypes';
import {
  BrowserMaterializationOptions,
  BrowserMaterializationPolicy
} from '../../core/browser/BrowserMaterializationPolicy';
import { BrowserMemoryPressureOptions } from '../../core/browser/BrowserMemoryPressureCoordinator';
import { WebRuntimeRetentionPlan } from '../../core/web/WebRuntimePoolPolicy';
import {
  BrowserHostedWebNodeDisposeAllReason,
  BrowserHostedWebNodeDisposeReason
} from '../../core/browser/BrowserRuntimeActionReason';
import { BrowserHostedWebOwnershipCoordinator } from '../../core/browser/BrowserHostedWebOwnershipCoordinator';
import { BrowserPageFindCoordinator } from '../../core/browser/BrowserPageFindCoordinator';
import { BrowserWebHostCoordinator } from '../../core/browser/BrowserWebHostCoordinator';
import {
  BrowserHostedRuntimeReleaseResult,
  BrowserTabRuntimeLifecycleResult,
  BrowserTabRuntimeLifecycleService
} from './BrowserTabRuntimeLifecycleService';
import {
  WebTabRuntimePatch,
  WebTabRuntimeRecord
} from '../../core/web/WebTabRuntime';

const BROWSER_RUNTIME_PORT_LOG_DOMAIN: number = 0x0000;
const BROWSER_RUNTIME_PORT_LOG_TAG: string = 'AiraRuntimePort';

export interface BrowserRuntimeLifecyclePortHost {
  getTabs: () => BrowserTabState[];
  getWindowScopeId: () => string;
  getActiveTabId: () => string;
  isHomeVisible: () => boolean;
  applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
}

export interface BrowserRuntimeLifecyclePortDependencies {
  persistMountedRuntimeSnapshot: (tabId: string, releaseHostedNodeAfterPersist: boolean) => void;
  hostedRuntimeReleaseSink?: BrowserHostedRuntimeReleaseSink;
}

export interface BrowserHostedRuntimeReleaseSink {
  releaseControllerBindings(tabIds: string[]): void;
}

export interface BrowserRuntimeControllerResolver {
  resolveController(tabId: string): webview.WebviewController | undefined;
}

export interface BrowserRuntimeDataLoadResult {
  handled: boolean;
  hasLiveController: boolean;
  errorMessage: string;
}

export interface BrowserRuntimeControllerAttachedState {
  runtime?: WebTabRuntimeRecord;
  controllerAttached: boolean;
}

export interface BrowserRuntimeWebLoadControllerState {
  tabId: string;
  controller: webview.WebviewController;
  controllerAttached: boolean;
  userAgentPageUrl: string;
  active: boolean;
}

export interface BrowserRuntimeActiveControllerState {
  tabId: string;
  controller: webview.WebviewController;
  controllerAttached: boolean;
}

export interface BrowserRuntimeActiveTabDataScope {
  tabId: string;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface BrowserRuntimeNavigationMemoryPatch {
  currentUrl?: string;
  pendingUrl?: string;
  lastKnownUrl?: string;
  snapshotPath?: string;
  snapshotUpdatedAt?: number;
}

export interface BrowserAcceptedSpaRouteSignal {
  tabId: string;
  url: string;
  kind: string;
  timestamp: number;
}

export interface BrowserRuntimeBackgroundSessionSyncRequest {
  tabs: BrowserTabState[];
  activeTabId: string;
  windowId: string;
  previousRetentionPlan: WebRuntimeRetentionPlan;
  host: BrowserRuntimeSessionSyncHost;
  trigger?: BrowserTabBackgroundTrigger;
  windowState?: BrowserTabWindowState;
  activeDownloadCount: number;
  explicitProtectionReasonsByTabId: Record<string, string>;
  pageBehaviorByTabId?: Record<string, BrowserTabPageBehaviorState>;
  previewAssetsByTabId?: Record<string, BrowserTabPreviewAssetState>;
  systemMemoryPressure?: BrowserSystemMemoryPressureSnapshot;
  materializationPolicy?: BrowserMaterializationPolicy;
  resolveDiscardQueueTab?: (tabId: string) => BrowserTabState | undefined;
  executeDiscardTask?: (task: BrowserTabDiscardTask) => void;
  recordDiscardQueueRuntimeEvent?: (type: string, message: string, tabId: string) => void;
}

export interface BrowserRuntimeHostedReleaseBaseRequest {
  lifecycleService: BrowserTabRuntimeLifecycleService;
  webHostCoordinator: BrowserWebHostCoordinator;
  ownershipCoordinator: BrowserHostedWebOwnershipCoordinator;
  pageFindCoordinator: BrowserPageFindCoordinator;
}

export interface BrowserRuntimeHostedReleaseRequest extends BrowserRuntimeHostedReleaseBaseRequest {
  tabId: string;
  reason: BrowserHostedWebNodeDisposeReason;
}

export interface BrowserRuntimeHostedReleaseInactiveRequest extends BrowserRuntimeHostedReleaseBaseRequest {
  reason: BrowserHostedWebNodeDisposeReason;
}

export interface BrowserRuntimeHostedReleaseAllRequest extends BrowserRuntimeHostedReleaseBaseRequest {
  reason: BrowserHostedWebNodeDisposeAllReason;
}

export interface BrowserRuntimeParkedHostedReleaseRequest {
  lifecycleService: BrowserTabRuntimeLifecycleService;
  tabId: string;
  source: string;
  webHostCoordinator: BrowserWebHostCoordinator;
  ownershipCoordinator: BrowserHostedWebOwnershipCoordinator;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
}

export interface BrowserRuntimeBackgroundHotReleaseRequest {
  lifecycleService: BrowserTabRuntimeLifecycleService;
  tabId: string;
  reason: BrowserHostedWebNodeDisposeReason;
  webHostCoordinator: BrowserWebHostCoordinator;
  ownershipCoordinator: BrowserHostedWebOwnershipCoordinator;
  clearPreviewTimers: () => void;
  clearPreviewLoadIssuedTab: (tabId: string) => void;
  updateBackgroundRuntimeState: (tabId: string, runtimeState: TabRuntimeState) => void;
}

type BrowserRuntimeDataLoadBeforeLoad = (
  controller: webview.WebviewController,
  hasLiveController: boolean
) => void;
export type BrowserRuntimeRestoreExecutor = (tabId: string, reason: TabRestoreReason) => void;

interface BrowserRuntimeRestoreDispatch {
  tabId: string;
  fallbackReason: TabRestoreReason;
  executeRestoreRuntime: BrowserRuntimeRestoreExecutor;
}

class BrowserRuntimeSessionRegistryAdapter extends TabRuntimeRegistry {
  private readonly operations: BrowserRuntimeSessionOperations;

  constructor(operations: BrowserRuntimeSessionOperations) {
    super();
    this.operations = operations;
  }

  pruneWindowRuntimes(windowId: string, allowedTabIds: string[]): void {
    this.operations.pruneWindowRuntimes(windowId, allowedTabIds);
  }

  listWindowRuntimes(windowId: string): WebTabRuntimeRecord[] {
    return this.operations.listWindowRuntimes(windowId);
  }
}

/**
 * Internal bridge for the existing protected lifecycle coordinator. The
 * Session-facing API remains BrowserRuntimeSessionOperations; this adapter is
 * created only inside the runtime Port and is never returned to a page.
 */
class BrowserRuntimeSessionCoordinatorAdapter extends BrowserSessionCoordinator {
  private readonly operations: BrowserRuntimeSessionOperations;
  private readonly registryAdapter: BrowserRuntimeSessionRegistryAdapter;

  constructor(operations: BrowserRuntimeSessionOperations) {
    super();
    this.operations = operations;
    this.registryAdapter = new BrowserRuntimeSessionRegistryAdapter(operations);
  }

  setRuntimeNavigationCommitGuard(guard?: BrowserRuntimeNavigationCommitGuard): void {
    this.operations.setRuntimeNavigationCommitGuard(guard);
  }

  updateRetentionSettings(settings: BrowserRetentionSettings): void {
    this.operations.updateRetentionSettings(settings);
  }

  ensureTabRuntime(tab: BrowserTabState, windowId: string): EnsureTabRuntimeResult {
    const result = this.operations.ensureTabRuntime(tab, windowId);
    if (result === undefined) {
      throw new Error('Connected runtime adapter lost its Session before ensureTabRuntime completed.');
    }
    return result;
  }

  activateTab(
    tab: BrowserTabState,
    tabs: BrowserTabState[],
    windowId: string,
    options: BrowserMaterializationOptions = {}
  ): ActivateBrowserTabPlan | undefined {
    return this.operations.activateTab(tab, tabs, windowId, options);
  }

  buildRuntimeRetentionPlan(
    tabs: BrowserTabState[],
    activeTabId: string,
    options: BrowserMemoryPressureOptions = {}
  ): WebRuntimeRetentionPlan {
    const result = this.operations.buildRuntimeRetentionPlan(tabs, activeTabId, options);
    if (result === undefined) {
      throw new Error('Connected runtime adapter lost its Session before retention planning completed.');
    }
    return result;
  }

  applyRuntimeRetentionPlan(plan: WebRuntimeRetentionPlan): void {
    this.operations.applyRuntimeRetentionPlan(plan);
  }

  removeTab(tabId: string): WebTabRuntimeRecord | undefined {
    return this.operations.removeTab(tabId);
  }

  getRuntime(tabId: string): WebTabRuntimeRecord | undefined {
    return this.operations.getRuntime(tabId);
  }

  markTabControllerAttached(tabId: string): WebTabRuntimeRecord | undefined {
    return this.operations.markTabControllerAttached(tabId);
  }

  markTabWindowOpenHandoffPending(tabId: string): WebTabRuntimeRecord | undefined {
    return this.operations.markTabWindowOpenHandoffPending(tabId);
  }

  consumeTabWindowOpenHandoffPending(tabId: string): boolean {
    return this.operations.consumeTabWindowOpenHandoffPending(tabId);
  }

  replaceTabControllerForProxyRefresh(
    tabId: string,
    controller: webview.WebviewController
  ): WebTabRuntimeRecord | undefined {
    return this.operations.replaceTabControllerForProxyRefresh(tabId, controller);
  }

  markTabControllerDetached(tabId: string): WebTabRuntimeRecord | undefined {
    return this.operations.markTabControllerDetached(tabId);
  }

  markTabCrashed(
    tabId: string,
    degradedReason: string = '',
    crashReason: TabCrashReason = 'unknown'
  ): WebTabRuntimeRecord | undefined {
    return this.operations.markTabCrashed(tabId, degradedReason, crashReason);
  }

  rememberTabNavigation(tabId: string, url: string): WebTabRuntimeRecord | undefined {
    return this.operations.rememberTabNavigation(tabId, url);
  }

  rememberProvisionalTabNavigation(tabId: string, url: string): WebTabRuntimeRecord | undefined {
    return this.operations.rememberProvisionalTabNavigation(tabId, url);
  }

  patchRuntime(tabId: string, patch: WebTabRuntimePatch): WebTabRuntimeRecord | undefined {
    return this.operations.patchRuntime(tabId, patch);
  }

  pruneWindowRuntimes(windowId: string, allowedTabIds: string[]): void {
    this.operations.pruneWindowRuntimes(windowId, allowedTabIds);
  }

  listWindowRuntimes(windowId: string): WebTabRuntimeRecord[] {
    return this.operations.listWindowRuntimes(windowId);
  }

  getRuntimeRegistry(): TabRuntimeRegistry {
    return this.registryAdapter;
  }

  hasLiveWindowRuntime(windowId: string): boolean {
    return this.operations.hasLiveWindowRuntime(windowId);
  }
}

export class BrowserRuntimeLifecyclePort implements BrowserRuntimeControllerResolver {
  private runtimeLifecycleCoordinator?: BrowserRuntimeLifecycleCoordinator;
  private readonly runtimeLifecycleService: BrowserTabRuntimeLifecycleService;
  private runtimeSession: BrowserRuntimeSessionPort = new BrowserRuntimeSessionPort();
  private backgroundOperations?: BrowserWindowSessionBackgroundOperations;
  private runtimeCoordinator: BrowserSessionCoordinator = new BrowserRuntimeSessionCoordinatorAdapter(
    this.runtimeSession
  );
  private readonly tabManager: BrowserTabManagerPort;
  private readonly host: BrowserRuntimeLifecyclePortHost;
  private readonly createController: () => webview.WebviewController;
  private readonly dependencies: BrowserRuntimeLifecyclePortDependencies;
  private restoreDispatching: boolean = false;
  private restoreQueueDraining: boolean = false;
  private pendingRestoreDispatches: BrowserRuntimeRestoreDispatch[] = [];
  private acceptedSpaRouteSignalListener?: (signal: BrowserAcceptedSpaRouteSignal) => void;

  constructor(
    tabManager: BrowserTabManagerPort,
    host: BrowserRuntimeLifecyclePortHost,
    createController: () => webview.WebviewController,
    dependencies: BrowserRuntimeLifecyclePortDependencies,
    runtimeLifecycleService: BrowserTabRuntimeLifecycleService = new BrowserTabRuntimeLifecycleService()
  ) {
    this.runtimeLifecycleService = runtimeLifecycleService;
    this.tabManager = tabManager;
    this.host = host;
    this.createController = createController;
    this.dependencies = dependencies;
  }

  connectRuntimeSession(
    binding: BrowserWindowSessionRuntimeBinding | undefined,
    backgroundBinding?: BrowserWindowSessionBackgroundBinding
  ): void {
    this.pendingRestoreDispatches = [];
    this.restoreDispatching = false;
    this.restoreQueueDraining = false;
    this.runtimeSession = resolveBrowserWindowSessionRuntimeBinding(binding) ?? new BrowserRuntimeSessionPort();
    this.runtimeLifecycleCoordinator = resolveBrowserWindowSessionRuntimeLifecycleBinding(binding);
    this.runtimeCoordinator = new BrowserRuntimeSessionCoordinatorAdapter(this.runtimeSession);
    this.backgroundOperations = resolveBrowserWindowSessionBackgroundBinding(backgroundBinding);
  }

  isRuntimeSessionConnected(): boolean {
    return this.runtimeSession.isConnected() && this.runtimeLifecycleCoordinator !== undefined;
  }

  setAcceptedSpaRouteSignalListener(
    listener: (signal: BrowserAcceptedSpaRouteSignal) => void
  ): void {
    this.acceptedSpaRouteSignalListener = listener;
  }

  publishAcceptedSpaRouteSignal(signal: BrowserAcceptedSpaRouteSignal): void {
    try {
      this.acceptedSpaRouteSignalListener?.(signal);
    } catch (_error) {
      hilog.warn(BROWSER_RUNTIME_PORT_LOG_DOMAIN, BROWSER_RUNTIME_PORT_LOG_TAG,
        'Accepted SPA route listener failed kind=%{public}s.', signal.kind.substring(0, 32));
    }
  }

  refresh(tabIds: string[]): void {
    const runtimeLifecycleCoordinator = this.runtimeLifecycleCoordinator;
    if (!this.isRuntimeSessionConnected() || runtimeLifecycleCoordinator === undefined || tabIds.length === 0) {
      return;
    }
    runtimeLifecycleCoordinator.refreshTabRuntimes(
      this.runtimeCoordinator,
      this.host.getTabs(),
      tabIds,
      this.host.getWindowScopeId()
    );
  }

  refreshTab(tab: BrowserTabState, tabIdWhenMissing: string): WebTabRuntimeRecord | undefined {
    const runtimeLifecycleCoordinator = this.runtimeLifecycleCoordinator;
    if (!this.isRuntimeSessionConnected() || runtimeLifecycleCoordinator === undefined) {
      return undefined;
    }
    return runtimeLifecycleCoordinator.refreshTabRuntime(
      this.runtimeCoordinator,
      tab,
      this.host.getWindowScopeId(),
      tabIdWhenMissing
    );
  }

  runActiveRuntime(activeRuntimeHost: BrowserActiveRuntimeHost): void {
    const runtimeLifecycleCoordinator = this.runtimeLifecycleCoordinator;
    if (!this.isRuntimeSessionConnected() || runtimeLifecycleCoordinator === undefined) {
      return;
    }
    runtimeLifecycleCoordinator.runActiveRuntime(
      this.runtimeCoordinator,
      this.tabManager as TabManager,
      this.host.getTabs(),
      this.host.getActiveTabId(),
      this.host.getWindowScopeId(),
      this.host.isHomeVisible(),
      activeRuntimeHost
    );
  }

  runActiveRuntimeAfterSwitch(
    activeRuntimeHost: BrowserActiveRuntimeHost
  ): BrowserActiveRuntimeAttachmentResult {
    const runtimeLifecycleCoordinator = this.runtimeLifecycleCoordinator;
    if (!this.isRuntimeSessionConnected() || runtimeLifecycleCoordinator === undefined) {
      return this.buildDisconnectedActiveRuntimeAttachmentResult();
    }
    return runtimeLifecycleCoordinator.runActiveRuntimeAfterSwitch(
      this.runtimeCoordinator,
      this.tabManager as TabManager,
      this.host.getTabs(),
      this.host.getActiveTabId(),
      this.host.getWindowScopeId(),
      this.host.isHomeVisible(),
      activeRuntimeHost
    );
  }

  replaceControllerForProxyRefresh(tabId: string): WebTabRuntimeRecord | undefined {
    if (!this.isRuntimeSessionConnected()) {
      return undefined;
    }
    return this.runtimeSession.replaceTabControllerForProxyRefresh(tabId, this.createController());
  }

  replaceControllerForRuntimeRefresh(tabId: string): WebTabRuntimeRecord | undefined {
    if (!this.isRuntimeSessionConnected()) {
      return undefined;
    }
    return this.runtimeSession.replaceTabControllerForProxyRefresh(tabId, this.createController());
  }

  resolveRuntime(tabId: string): WebTabRuntimeRecord | undefined {
    if (!this.isRuntimeSessionConnected()) {
      return undefined;
    }
    return this.runtimeSession.getRuntime(tabId);
  }

  resolveController(tabId: string, runtime?: WebTabRuntimeRecord): webview.WebviewController | undefined {
    return runtime?.controller ?? this.resolveRuntime(tabId)?.controller;
  }

  resolveActiveController(): webview.WebviewController | undefined {
    return this.resolveController(this.host.getActiveTabId());
  }

  isActiveWebTab(tabId: string): boolean {
    const normalizedTabId = tabId.trim();
    return normalizedTabId.length > 0 && normalizedTabId === this.host.getActiveTabId() &&
      !this.host.isHomeVisible();
  }

  resolveActiveTabDataScope(): BrowserRuntimeActiveTabDataScope | undefined {
    const activeTabId: string = this.host.getActiveTabId().trim();
    if (activeTabId.length === 0 || this.host.isHomeVisible()) {
      return undefined;
    }
    const tab = this.host.getTabs().find((candidate: BrowserTabState): boolean => candidate.id === activeTabId);
    if (tab === undefined) {
      return undefined;
    }
    const privacyMode: BrowserSessionPrivacyMode = normalizeBrowserSessionPrivacyMode(tab.privacyMode);
    return {
      tabId: activeTabId,
      privacyMode: privacyMode,
      dataScope: normalizeBrowserDataScope(tab.dataScope, privacyMode)
    };
  }

  resolvePageUrl(tabId: string): string {
    const tab = this.host.getTabs().find((candidate: BrowserTabState): boolean => candidate.id === tabId);
    if (tab !== undefined) {
      return resolveCurrentSiteUrl(tab.url, tab.pendingUrl);
    }
    return resolveCurrentSiteUrl(this.resolveRuntimeLastKnownUrl(tabId), this.resolveRuntimePendingUrl(tabId));
  }

  resolveWebId(tabId: string): number {
    const controller = this.resolveController(tabId);
    if (controller === undefined) {
      return -1;
    }
    try {
      return controller.getWebId();
    } catch (_error) {
      return -1;
    }
  }

  clearControllerHistory(tabId: string): boolean {
    const controller = this.resolveController(tabId);
    if (controller === undefined) {
      return false;
    }
    try {
      controller.clearHistory();
      return true;
    } catch (_error) {
      return false;
    }
  }

  loadData(
    tabId: string,
    payload: BrowserWebLoadDataPayload,
    beforeLoad?: BrowserRuntimeDataLoadBeforeLoad
  ): BrowserRuntimeDataLoadResult {
    const runtime = this.resolveRuntime(tabId);
    const controller = runtime?.controller;
    if (controller === undefined) {
      return {
        handled: false,
        hasLiveController: false,
        errorMessage: ''
      };
    }
    const hasLiveController = runtime?.hasLiveController === true;
    if (beforeLoad !== undefined) {
      beforeLoad(controller, hasLiveController);
    }
    try {
      controller.loadData(payload.data, payload.mimeType, payload.encoding, payload.baseUrl, payload.historyUrl);
      return {
        handled: true,
        hasLiveController: hasLiveController,
        errorMessage: ''
      };
    } catch (error) {
      return {
        handled: false,
        hasLiveController: hasLiveController,
        errorMessage: JSON.stringify(error)
      };
    }
  }

  hasRuntime(tabId: string): boolean {
    return this.resolveRuntime(tabId) !== undefined;
  }

  hasLiveRuntimeController(tabId: string): boolean {
    return this.resolveRuntime(tabId)?.hasLiveController === true;
  }

  resolveWebLoadControllerState(
    tabId: string,
    controller: webview.WebviewController,
    activePageUrlFallback: string
  ): BrowserRuntimeWebLoadControllerState {
    const active = tabId === this.host.getActiveTabId();
    const tab = this.host.getTabs().find((candidate: BrowserTabState) => candidate.id === tabId);
    if (!active) {
      this.markControllerAttached(tabId);
    }
    const controllerAttached = this.hasLiveRuntimeController(tabId);
    const pendingUrl = tab?.pendingUrl ?? '';
    const userAgentPageUrl = pendingUrl.trim().length > 0
      ? pendingUrl
      : (active ? activePageUrlFallback : '');
    return {
      tabId: tabId,
      controller: controller,
      controllerAttached: controllerAttached,
      userAgentPageUrl: userAgentPageUrl,
      active: active
    };
  }

  resolveActiveControllerState(
    tabId: string,
    controller: webview.WebviewController,
    controllerAttached: boolean
  ): BrowserRuntimeActiveControllerState | undefined {
    if (tabId !== this.host.getActiveTabId()) {
      return undefined;
    }
    return {
      tabId: tabId,
      controller: controller,
      controllerAttached: controllerAttached
    };
  }

  resolveLiveRuntimeControllerState(tabId: string, fallback: boolean): boolean {
    return this.resolveRuntime(tabId)?.hasLiveController ?? fallback;
  }

  hasAttachedController(tabId: string, activeControllerAttached: boolean): boolean {
    if (this.hasLiveRuntimeController(tabId)) {
      return true;
    }
    return tabId === this.host.getActiveTabId() &&
      activeControllerAttached &&
      this.resolveActiveController() !== undefined;
  }

  runJavaScriptOnLiveRuntime(
    tabId: string,
    script: string,
    missingReason: string = 'runtime_controller_not_live'
  ): Promise<string> {
    const runtime = this.resolveRuntime(tabId);
    if (runtime === undefined || !runtime.hasLiveController) {
      return Promise.reject(new Error(missingReason));
    }
    return runtime.controller.runJavaScript(script);
  }

  terminateRenderProcess(tabId: string): boolean {
    const targetTabId = tabId.trim().length > 0 ? tabId : this.host.getActiveTabId();
    const controller = this.resolveController(targetTabId);
    if (controller === undefined) {
      return false;
    }
    try {
      controller.terminateRenderProcess();
      return true;
    } catch (_error) {
      return false;
    }
  }

  setNavigationCommitGuard(guard?: BrowserRuntimeNavigationCommitGuard): void {
    if (!this.isRuntimeSessionConnected()) {
      return;
    }
    this.runtimeSession.setRuntimeNavigationCommitGuard(guard);
  }

  removeClosedTabRuntime(tabId: string, reason: string): WebTabRuntimeRecord | undefined {
    const normalizedTabId = tabId.trim();
    if (!this.isRuntimeSessionConnected() || normalizedTabId.length <= 0) {
      return undefined;
    }
    const removed = this.runtimeSession.removeTab(normalizedTabId);
    this.host.recordRuntimeEvent(
      'tab_runtime_removed_for_close',
      `reason=${reason} removed=${removed !== undefined ? 'true' : 'false'}`,
      normalizedTabId
    );
    return removed;
  }

  consumeWindowOpenHandoff(tabId: string): boolean {
    if (!this.isRuntimeSessionConnected()) {
      return false;
    }
    return this.runtimeSession.consumeTabWindowOpenHandoffPending(tabId);
  }

  markControllerAttached(tabId: string): WebTabRuntimeRecord | undefined {
    if (!this.isRuntimeSessionConnected()) {
      return undefined;
    }
    return this.runtimeSession.markTabControllerAttached(tabId);
  }

  markControllerAttachedWithState(
    tabId: string,
    currentControllerAttached: boolean
  ): BrowserRuntimeControllerAttachedState {
    const runtime = this.markControllerAttached(tabId);
    if (tabId !== this.host.getActiveTabId()) {
      return {
        runtime: runtime,
        controllerAttached: currentControllerAttached
      };
    }
    return {
      runtime: runtime,
      controllerAttached: runtime?.hasLiveController ?? currentControllerAttached
    };
  }

  markTabCrashed(
    tabId: string,
    degradedReason: string = '',
    crashReason: TabCrashReason = 'unknown'
  ): WebTabRuntimeRecord | undefined {
    if (!this.isRuntimeSessionConnected()) {
      return undefined;
    }
    return this.runtimeSession.markTabCrashed(tabId, degradedReason, crashReason);
  }

  updateRetentionSettings(settings: BrowserRetentionSettings): void {
    if (!this.isRuntimeSessionConnected()) {
      return;
    }
    this.runtimeSession.updateRetentionSettings(settings);
  }

  patchRuntimeState(tabId: string, runtimeState: TabRuntimeState, hasLiveController: boolean): void {
    if (!this.isRuntimeSessionConnected()) {
      return;
    }
    this.runtimeSession.patchRuntime(tabId, {
      state: runtimeState,
      hasLiveController: hasLiveController
    });
  }

  rememberCommittedNavigation(tabId: string, url: string): void {
    if (!this.isRuntimeSessionConnected()) {
      return;
    }
    this.runtimeSession.rememberTabNavigation(tabId, url);
  }

  rememberProvisionalNavigation(tabId: string, url: string): void {
    if (!this.isRuntimeSessionConnected()) {
      return;
    }
    this.runtimeSession.rememberProvisionalTabNavigation(tabId, url);
  }

  resolveRuntimeLastKnownUrl(tabId: string): string {
    return this.resolveRuntime(tabId)?.lastKnownUrl ?? '';
  }

  resolveRuntimePendingUrl(tabId: string): string {
    return this.resolveRuntime(tabId)?.pendingUrl ?? '';
  }

  patchRuntimeNavigationMemory(tabId: string, patch: BrowserRuntimeNavigationMemoryPatch): void {
    if (!this.isRuntimeSessionConnected()) {
      return;
    }
    const runtimePatch: WebTabRuntimePatch = {
      currentUrl: patch.currentUrl,
      pendingUrl: patch.pendingUrl,
      lastKnownUrl: patch.lastKnownUrl,
      snapshotPath: patch.snapshotPath,
      snapshotUpdatedAt: patch.snapshotUpdatedAt
    };
    this.runtimeSession.patchRuntime(tabId, runtimePatch);
  }

  patchRuntimeNavigationState(tabId: string, url: string): void {
    this.patchRuntimeNavigationMemory(tabId, {
      currentUrl: url,
      pendingUrl: url,
      lastKnownUrl: url
    });
  }

  persistMountedRuntimeSnapshot(tabId: string, releaseHostedNodeAfterPersist: boolean): void {
    this.dependencies.persistMountedRuntimeSnapshot(tabId, releaseHostedNodeAfterPersist);
  }

  isNavigationProvisional(tabId: string, tabUrl: string): boolean {
    const pendingUrl = normalizeNavigationTarget(this.resolveRuntimePendingUrl(tabId));
    if (pendingUrl.length <= 0) {
      return false;
    }
    return pendingUrl !== normalizeNavigationTarget(tabUrl);
  }

  isTabNavigationProvisional(tabId: string): boolean {
    const tab = this.host.getTabs().find((candidate: BrowserTabState): boolean => candidate.id === tabId);
    if (tab === undefined) {
      return false;
    }
    return this.isNavigationProvisional(tabId, tab.url);
  }

  restoreActiveRuntime(
    fallbackReason: TabRestoreReason,
    executeRestoreRuntime: BrowserRuntimeRestoreExecutor
  ): void {
    if (!this.isRuntimeSessionConnected()) {
      return;
    }
    this.restoreRuntime(this.host.getActiveTabId(), fallbackReason, executeRestoreRuntime);
  }

  restoreRuntime(
    tabId: string,
    fallbackReason: TabRestoreReason,
    executeRestoreRuntime: BrowserRuntimeRestoreExecutor
  ): void {
    if (!this.isRuntimeSessionConnected()) {
      return;
    }
    if (this.restoreDispatching) {
      this.pendingRestoreDispatches.push({
        tabId: tabId,
        fallbackReason: fallbackReason,
        executeRestoreRuntime: executeRestoreRuntime
      });
      this.host.recordRuntimeEvent('tab_runtime_restore_reentrant_queued', `reason=${fallbackReason}`, tabId);
      return;
    }
    this.dispatchRestoreRuntime(tabId, fallbackReason, executeRestoreRuntime);
    this.drainPendingRestoreDispatches();
  }

  private dispatchRestoreRuntime(
    tabId: string,
    fallbackReason: TabRestoreReason,
    executeRestoreRuntime: BrowserRuntimeRestoreExecutor
  ): void {
    this.restoreDispatching = true;
    try {
      this.runtimeLifecycleService.restoreRuntime({
        tabId: tabId,
        reason: fallbackReason,
        resolveTab: (targetTabId: string): BrowserTabState | undefined => {
          return this.host.getTabs().find((candidate: BrowserTabState): boolean => candidate.id === targetTabId);
        },
        applyTabRuntimePatch: (targetTabId: string, patch: BrowserTabRuntimePatch): void => {
          this.host.applyTabRuntimePatch(targetTabId, patch);
        },
        executeRestoreRuntime: (targetTabId: string, restoreReason: TabRestoreReason): void => {
          executeRestoreRuntime(targetTabId, restoreReason);
        },
        recordRuntimeEvent: (type: string, message: string, targetTabId: string): void => {
          this.host.recordRuntimeEvent(type, message, targetTabId);
        }
      });
    } finally {
      this.restoreDispatching = false;
    }
  }

  private drainPendingRestoreDispatches(): void {
    if (this.restoreQueueDraining) {
      return;
    }
    this.restoreQueueDraining = true;
    try {
      while (!this.restoreDispatching && this.pendingRestoreDispatches.length > 0) {
        const nextDispatch = this.pendingRestoreDispatches.shift();
        if (nextDispatch === undefined) {
          return;
        }
        this.dispatchRestoreRuntime(
          nextDispatch.tabId,
          nextDispatch.fallbackReason,
          nextDispatch.executeRestoreRuntime
        );
      }
    } finally {
      this.restoreQueueDraining = false;
    }
  }

  discardRuntime(
    task: BrowserTabDiscardTask,
    protectedReasonsByTabId: Record<string, string>
  ): BrowserTabRuntimeLifecycleResult {
    if (!this.isRuntimeSessionConnected()) {
      return {
        kind: 'discard_skipped',
        tabId: task.tabId,
        message: 'runtime_session_disconnected'
      };
    }
    return this.runtimeLifecycleService.discardRuntime({
      tabId: task.tabId,
      reason: task.reason,
      queuedAt: task.queuedAt,
      activeTabId: this.host.getActiveTabId(),
      protectedReasonsByTabId: protectedReasonsByTabId,
      resolveTab: (targetTabId: string): BrowserTabState | undefined => {
        return this.host.getTabs().find((candidate: BrowserTabState): boolean => candidate.id === targetTabId);
      },
      persistMountedRuntimeSnapshot: (targetTabId: string, releaseHostedNodeAfterPersist: boolean): void => {
        this.persistMountedRuntimeSnapshot(targetTabId, releaseHostedNodeAfterPersist);
      },
      applyTabRuntimePatch: (targetTabId: string, patch: BrowserTabRuntimePatch): void => {
        this.host.applyTabRuntimePatch(targetTabId, patch);
      },
      recordRuntimeEvent: (type: string, message: string, targetTabId: string): void => {
        this.host.recordRuntimeEvent(type, message, targetTabId);
      }
    });
  }

  hasLiveWindowRuntime(windowId: string): boolean {
    if (!this.isRuntimeSessionConnected()) {
      return false;
    }
    return this.runtimeSession.hasLiveWindowRuntime(windowId);
  }

  handleAttached(
    tabId: string,
    controllerAttachmentHost: BrowserControllerAttachmentHost,
    options: BrowserControllerAttachmentOptions = {}
  ): void {
    const runtimeLifecycleCoordinator = this.runtimeLifecycleCoordinator;
    if (!this.isRuntimeSessionConnected() || runtimeLifecycleCoordinator === undefined) {
      return;
    }
    runtimeLifecycleCoordinator.runControllerAttachment(
      this.runtimeCoordinator,
      this.tabManager as TabManager,
      this.host.getTabs(),
      this.host.getActiveTabId(),
      tabId,
      this.host.isHomeVisible(),
      controllerAttachmentHost,
      options
    );
  }

  runBackgroundSessionSync(
    request: BrowserRuntimeBackgroundSessionSyncRequest
  ): BrowserTabBackgroundSessionSyncResult | undefined {
    const runtimeLifecycleCoordinator = this.runtimeLifecycleCoordinator;
    if (!this.isRuntimeSessionConnected() || runtimeLifecycleCoordinator === undefined ||
      this.backgroundOperations === undefined) {
      return undefined;
    }
    const managerRequest: BrowserTabBackgroundSessionSyncRequest = {
      sessionCoordinator: this.runtimeCoordinator,
      runtimeLifecycleCoordinator: runtimeLifecycleCoordinator,
      tabManager: this.tabManager,
      tabs: request.tabs,
      activeTabId: request.activeTabId,
      windowId: request.windowId,
      previousRetentionPlan: request.previousRetentionPlan,
      host: request.host,
      trigger: request.trigger,
      windowState: request.windowState,
      activeDownloadCount: request.activeDownloadCount,
      explicitProtectionReasonsByTabId: request.explicitProtectionReasonsByTabId,
      pageBehaviorByTabId: request.pageBehaviorByTabId,
      previewAssetsByTabId: request.previewAssetsByTabId,
      systemMemoryPressure: request.systemMemoryPressure,
      materializationPolicy: request.materializationPolicy,
      resolveDiscardQueueTab: request.resolveDiscardQueueTab,
      executeDiscardTask: request.executeDiscardTask,
      recordDiscardQueueRuntimeEvent: request.recordDiscardQueueRuntimeEvent
    };
    return this.backgroundOperations.runSessionSync(managerRequest);
  }

  markBackgroundAppForeground(windowId: string): void {
    this.backgroundOperations?.markAppForeground(windowId);
  }

  markBackgroundAppBackground(windowId: string): void {
    this.backgroundOperations?.markAppBackground(windowId);
  }

  markBackgroundWindowActive(windowId: string): void {
    this.backgroundOperations?.markWindowActive(windowId);
  }

  markBackgroundWindowHidden(windowId: string): void {
    this.backgroundOperations?.markWindowHidden(windowId);
  }

  buildBackgroundWindowState(windowId: string): BrowserTabWindowState | undefined {
    return this.backgroundOperations?.buildWindowState(windowId);
  }

  releaseHostedRuntime(request: BrowserRuntimeHostedReleaseRequest): BrowserHostedRuntimeReleaseResult {
    if (!this.isRuntimeSessionConnected()) {
      return this.buildDisconnectedHostedReleaseResult(request.webHostCoordinator, request.ownershipCoordinator);
    }
    return this.finalizeHostedRuntimeRelease(request.lifecycleService.releaseHostedRuntime({
      tabId: request.tabId,
      reason: request.reason,
      activeTabId: this.host.getActiveTabId(),
      webHostCoordinator: request.webHostCoordinator,
      sessionCoordinator: this.runtimeCoordinator,
      ownershipCoordinator: request.ownershipCoordinator,
      pageFindCoordinator: request.pageFindCoordinator
    }));
  }

  releaseInactiveHostedRuntimes(
    request: BrowserRuntimeHostedReleaseInactiveRequest
  ): BrowserHostedRuntimeReleaseResult {
    if (!this.isRuntimeSessionConnected()) {
      return this.buildDisconnectedHostedReleaseResult(request.webHostCoordinator, request.ownershipCoordinator);
    }
    return this.finalizeHostedRuntimeRelease(request.lifecycleService.releaseInactiveHostedRuntimes({
      tabs: this.host.getTabs(),
      activeTabId: this.host.getActiveTabId(),
      reason: request.reason,
      webHostCoordinator: request.webHostCoordinator,
      sessionCoordinator: this.runtimeCoordinator,
      ownershipCoordinator: request.ownershipCoordinator,
      pageFindCoordinator: request.pageFindCoordinator
    }));
  }

  releaseAllHostedRuntimes(request: BrowserRuntimeHostedReleaseAllRequest): BrowserHostedRuntimeReleaseResult {
    if (!this.isRuntimeSessionConnected()) {
      return this.buildDisconnectedHostedReleaseResult(request.webHostCoordinator, request.ownershipCoordinator);
    }
    return this.finalizeHostedRuntimeRelease(request.lifecycleService.releaseAllHostedRuntimes({
      tabs: this.host.getTabs(),
      activeTabId: this.host.getActiveTabId(),
      reason: request.reason,
      webHostCoordinator: request.webHostCoordinator,
      sessionCoordinator: this.runtimeCoordinator,
      ownershipCoordinator: request.ownershipCoordinator,
      pageFindCoordinator: request.pageFindCoordinator
    }));
  }

  releaseParkedHostedRuntime(request: BrowserRuntimeParkedHostedReleaseRequest): BrowserHostedRuntimeReleaseResult {
    if (!this.isRuntimeSessionConnected()) {
      return this.buildDisconnectedHostedReleaseResult(request.webHostCoordinator, request.ownershipCoordinator);
    }
    return this.finalizeHostedRuntimeRelease(request.lifecycleService.releaseParkedHostedRuntime({
      tabId: request.tabId,
      source: request.source,
      webHostCoordinator: request.webHostCoordinator,
      sessionCoordinator: this.runtimeCoordinator,
      ownershipCoordinator: request.ownershipCoordinator,
      recordRuntimeEvent: request.recordRuntimeEvent
    }));
  }

  releaseBackgroundHotRuntime(
    request: BrowserRuntimeBackgroundHotReleaseRequest
  ): BrowserHostedRuntimeReleaseResult {
    if (!this.isRuntimeSessionConnected()) {
      return this.buildDisconnectedHostedReleaseResult(request.webHostCoordinator, request.ownershipCoordinator);
    }
    return this.finalizeHostedRuntimeRelease(request.lifecycleService.releaseBackgroundHotRuntime({
      tabId: request.tabId,
      reason: request.reason,
      webHostCoordinator: request.webHostCoordinator,
      sessionCoordinator: this.runtimeCoordinator,
      ownershipCoordinator: request.ownershipCoordinator,
      clearPreviewTimers: request.clearPreviewTimers,
      clearPreviewLoadIssuedTab: request.clearPreviewLoadIssuedTab,
      updateBackgroundRuntimeState: request.updateBackgroundRuntimeState
    }));
  }

  private finalizeHostedRuntimeRelease(
    result: BrowserHostedRuntimeReleaseResult
  ): BrowserHostedRuntimeReleaseResult {
    if (result.releasedTabIds.length > 0) {
      this.dependencies.hostedRuntimeReleaseSink?.releaseControllerBindings(result.releasedTabIds);
    }
    return result;
  }

  private buildDisconnectedActiveRuntimeAttachmentResult(): BrowserActiveRuntimeAttachmentResult {
    return {
      attached: false,
      shouldRestoreAfterAttachFallback: false,
      shouldRestoreSessionAfterAttachRetry: false,
      restoreReason: 'tab_switch',
      diagnosticLine: 'runtime_session_disconnected'
    };
  }

  private buildDisconnectedHostedReleaseResult(
    webHostCoordinator: BrowserWebHostCoordinator,
    ownershipCoordinator: BrowserHostedWebOwnershipCoordinator
  ): BrowserHostedRuntimeReleaseResult {
    return {
      activeHostedTabId: webHostCoordinator.getActiveHostedTabId(),
      activeHostedRenderKey: webHostCoordinator.getActiveHostedRenderKey(),
      ownershipSnapshot: ownershipCoordinator.getSnapshot(),
      released: false,
      releasedTabIds: [],
      activeReleased: false
    };
  }
}

export class BrowserRuntimeMutationPort {
  private readonly lifecyclePort: BrowserRuntimeLifecyclePort;

  constructor(lifecyclePort: BrowserRuntimeLifecyclePort) {
    this.lifecyclePort = lifecyclePort;
  }

  markTabCrashed(
    tabId: string,
    degradedReason: string = '',
    crashReason: TabCrashReason = 'unknown'
  ): WebTabRuntimeRecord | undefined {
    return this.lifecyclePort.markTabCrashed(tabId, degradedReason, crashReason);
  }

  refresh(tabIds: string[]): void {
    this.lifecyclePort.refresh(tabIds);
  }

  refreshTab(tab: BrowserTabState, tabIdWhenMissing: string): WebTabRuntimeRecord | undefined {
    return this.lifecyclePort.refreshTab(tab, tabIdWhenMissing);
  }

  clearControllerHistory(tabId: string): boolean {
    return this.lifecyclePort.clearControllerHistory(tabId);
  }

  terminateRenderProcess(tabId: string): boolean {
    return this.lifecyclePort.terminateRenderProcess(tabId);
  }

  loadData(
    tabId: string,
    payload: BrowserWebLoadDataPayload,
    beforeLoad?: BrowserRuntimeDataLoadBeforeLoad
  ): BrowserRuntimeDataLoadResult {
    return this.lifecyclePort.loadData(tabId, payload, beforeLoad);
  }

  updateRetentionSettings(settings: BrowserRetentionSettings): void {
    this.lifecyclePort.updateRetentionSettings(settings);
  }

  setNavigationCommitGuard(guard?: BrowserRuntimeNavigationCommitGuard): void {
    this.lifecyclePort.setNavigationCommitGuard(guard);
  }
}

export class BrowserRuntimeWebDataLoadMutationPortAdapter implements BrowserWebDataLoadMutationPort {
  private readonly runtimeMutationPort: BrowserRuntimeMutationPort;

  constructor(runtimeMutationPort: BrowserRuntimeMutationPort) {
    this.runtimeMutationPort = runtimeMutationPort;
  }

  loadData(
    tabId: string,
    payload: BrowserWebLoadDataPayload,
    beforeLoad?: BrowserWebDataLoadBeforeLoad
  ): BrowserWebDataLoadMutationResult {
    const result = this.runtimeMutationPort.loadData(
      tabId,
      payload,
      beforeLoad === undefined ? undefined :
        (controller: webview.WebviewController, hasLiveController: boolean): void => {
          beforeLoad(controller, hasLiveController);
        }
    );
    return new BrowserWebDataLoadMutationResultValue(result.handled, result.errorMessage);
  }
}

export class BrowserRuntimeWebDataLoadLifecyclePortAdapter implements BrowserWebDataLoadLifecyclePort {
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;

  constructor(runtimeLifecyclePort: BrowserRuntimeLifecyclePort) {
    this.runtimeLifecyclePort = runtimeLifecyclePort;
  }

  resolveActiveControllerState(
    tabId: string,
    controller: webview.WebviewController,
    hasLiveController: boolean
  ): BrowserWebDataLoadActiveControllerState | undefined {
    const state = this.runtimeLifecyclePort.resolveActiveControllerState(tabId, controller, hasLiveController);
    if (state === undefined) {
      return undefined;
    }
    return new BrowserWebDataLoadActiveControllerStateValue(state.controller, state.controllerAttached);
  }
}

export class BrowserRuntimeWebDataLoadRequestAdapter extends BrowserWebDataLoadRuntimeRequestAdapter {
  constructor(
    runtimeMutationPort: BrowserRuntimeMutationPort,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    syncEventContextHandler: BrowserWebDataLoadEventContextSync,
    activeControllerStateApply: BrowserWebDataLoadActiveControllerStateApply,
    loadFailureRecorder: BrowserWebDataLoadFailureRecorder
  ) {
    super(
      new BrowserRuntimeWebDataLoadMutationPortAdapter(runtimeMutationPort),
      new BrowserRuntimeWebDataLoadLifecyclePortAdapter(runtimeLifecyclePort),
      syncEventContextHandler,
      activeControllerStateApply,
      loadFailureRecorder
    );
  }
}
