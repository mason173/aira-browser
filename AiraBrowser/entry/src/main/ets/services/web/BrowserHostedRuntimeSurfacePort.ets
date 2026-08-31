import { UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import {
  BrowserPreviewWebHostSyncResult,
  BrowserWebHostAttachState,
  BrowserWebHostConfigUpdateInput,
  BrowserWebHostCoordinator,
  BrowserWebHostSyncInput,
  BrowserWebHostSyncResult
} from '../../core/browser/BrowserWebHostCoordinator';
import {
  BrowserHostedWebForegroundAttachFinishInput,
  BrowserHostedWebHiddenSlot,
  BrowserHostedWebOwnershipCoordinator,
  BrowserHostedWebOwnershipSnapshot
} from '../../core/browser/BrowserHostedWebOwnershipCoordinator';
import { BrowserTabState } from '../../core/tabs/TabManager';
import {
  HostedWebNodeCallbacks,
  HostedWebNodeController,
  HostedWebVideoControllerBridge
} from '../../core/web/HostedWebNode';
import { WebAppearancePolicy } from '../../core/web/WebAppearancePolicy';
import { WebTabRuntimeRecord } from '../../core/web/WebTabRuntime';
import {
  BrowserHostedWebNodeDisposeAllReason,
  BrowserHostedWebNodeDisposeReason
} from '../../core/browser/BrowserRuntimeActionReason';
import { BrowserRuntimeLifecyclePort } from './BrowserRuntimeLifecyclePort';
import {
  BrowserHostedRuntimeReleaseResult,
  BrowserTabRuntimeLifecycleService
} from './BrowserTabRuntimeLifecycleService';
import { BrowserPageFindCoordinator } from '../../core/browser/BrowserPageFindCoordinator';
import { BrowserBackgroundTabPreviewRuntimeCoordinator } from '../../core/browser/BrowserBackgroundTabPreviewRuntimeCoordinator';
import { TabRuntimeState } from '../../common/models/BrowserModels';

export interface BrowserHostedRuntimeActiveSurfaceConfig {
  uiContext: UIContext;
  appearancePolicy?: WebAppearancePolicy;
  documentStartScripts?: ScriptItem[];
  forceEnableWebZoom?: boolean;
  textZoomRatio?: number;
  pullRefreshNestedScrollEnabled?: boolean;
  webVideoControllerBridge?: HostedWebVideoControllerBridge;
  callbacks: HostedWebNodeCallbacks;
}

export interface BrowserHostedRuntimePreviewSurfaceConfig {
  uiContext: UIContext;
  appearancePolicy?: WebAppearancePolicy;
  userScriptNativeBridge?: Object;
  forceEnableWebZoom?: boolean;
  textZoomRatio?: number;
  callbacks: HostedWebNodeCallbacks;
}

export interface BrowserHostedRuntimeSurfacePortHost {
  applyActiveHostedSurfaceState: (tabId: string, renderKey: string) => void;
  applyControllerAttachedState: (attached: boolean) => void;
  applyHostedHiddenSlots: (hiddenSlots: BrowserHostedWebHiddenSlot[]) => void;
  getActiveTabId: () => string;
  resolveActiveTab: () => BrowserTabState | undefined;
  getCurrentWindowId: () => string;
  createUserScriptNativeBridge: (tabId: string, controller: webview.WebviewController) => Object;
  shouldSuspendActiveWebSurface: () => boolean;
  isHomeVisible: () => boolean;
  isTabsVisible: () => boolean;
  handleActiveRuntimeDetached: () => void;
  handleWebpageTranslationActiveSurfaceDetached: (tabId: string) => void;
  applyBackgroundRuntimeTabState: (tabId: string, runtimeState: TabRuntimeState) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
  attachForegroundHostedRuntime: () => void;
  buildActiveSurfaceConfig: (activeTab?: BrowserTabState) => BrowserHostedRuntimeActiveSurfaceConfig;
  buildPreviewSurfaceConfig: (
    tab: BrowserTabState,
    runtime: WebTabRuntimeRecord
  ) => BrowserHostedRuntimePreviewSurfaceConfig;
}

export interface BrowserHostedRuntimeActiveSurfacePrepareResult {
  handled: boolean;
  attached: boolean;
}

const MAX_PARKED_DESKTOP_WEB_ENTRY_COUNT: number = 1;

export class BrowserHostedRuntimeSurfacePort {
  private readonly webHostCoordinator: BrowserWebHostCoordinator;
  private readonly ownershipCoordinator: BrowserHostedWebOwnershipCoordinator;
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly lifecycleService: BrowserTabRuntimeLifecycleService;
  private readonly pageFindCoordinator: BrowserPageFindCoordinator;
  private readonly backgroundPreviewRuntimeCoordinator: BrowserBackgroundTabPreviewRuntimeCoordinator;
  private readonly host: BrowserHostedRuntimeSurfacePortHost;
  private retainedWindowOpenOpenerByTargetTabId: Record<string, string | undefined> = {};

  constructor(
    webHostCoordinator: BrowserWebHostCoordinator,
    ownershipCoordinator: BrowserHostedWebOwnershipCoordinator,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    lifecycleService: BrowserTabRuntimeLifecycleService,
    pageFindCoordinator: BrowserPageFindCoordinator,
    backgroundPreviewRuntimeCoordinator: BrowserBackgroundTabPreviewRuntimeCoordinator,
    host: BrowserHostedRuntimeSurfacePortHost
  ) {
    this.webHostCoordinator = webHostCoordinator;
    this.ownershipCoordinator = ownershipCoordinator;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.lifecycleService = lifecycleService;
    this.pageFindCoordinator = pageFindCoordinator;
    this.backgroundPreviewRuntimeCoordinator = backgroundPreviewRuntimeCoordinator;
    this.host = host;
  }

  detachActive(): void {
    const detachedTabId = this.webHostCoordinator.getActiveHostedTabId();
    const result = this.webHostCoordinator.detachActive();
    if (detachedTabId.length > 0) {
      this.host.handleWebpageTranslationActiveSurfaceDetached(detachedTabId);
    }
    this.applyActiveSurfaceResult(result);
  }

  promotePreviewToActive(tabId: string): void {
    this.webHostCoordinator.promotePreviewToActive(tabId);
  }

  detachHostedController(tabId: string): void {
    this.webHostCoordinator.getController(tabId)?.detachWeb();
  }

  getHostedController(tabId: string): HostedWebNodeController | undefined {
    return this.webHostCoordinator.getController(tabId);
  }

  getHostedNodeGeneration(tabId: string): number {
    return this.webHostCoordinator.getHostedNodeGeneration(tabId);
  }

  hasHostedController(tabId: string): boolean {
    return this.getHostedController(tabId) !== undefined;
  }

  isHostedNodeAttached(tabId: string): boolean {
    return this.getHostedController(tabId)?.isAttached() === true;
  }

  isHostedControllerAttached(tabId: string): boolean {
    return this.getHostedController(tabId)?.isWebControllerAttached() === true;
  }

  canHostActive(tabId: string): boolean {
    return this.ownershipCoordinator.canHostActive(tabId);
  }

  isBackgroundHot(tabId: string): boolean {
    return this.ownershipCoordinator.isBackgroundHot(tabId);
  }

  getPreviewHostedTabId(): string {
    return this.webHostCoordinator.getPreviewHostedTabId();
  }

  getHiddenSlots(): BrowserHostedWebHiddenSlot[] {
    return this.ownershipCoordinator.getSnapshot().hiddenSlots.concat([]);
  }

  retainWindowOpenOpener(tabId: string, targetTabId: string): boolean {
    const normalizedTabId = tabId.trim();
    const normalizedTargetTabId = targetTabId.trim();
    if (normalizedTabId.length === 0 || this.webHostCoordinator.getController(normalizedTabId) === undefined) {
      return false;
    }
    if (this.webHostCoordinator.getActiveHostedTabId() === normalizedTabId) {
      this.applyActiveSurfaceResult(this.webHostCoordinator.parkActive());
    }
    if (normalizedTargetTabId.length > 0) {
      this.retainedWindowOpenOpenerByTargetTabId[normalizedTargetTabId] = normalizedTabId;
    }
    const backgroundHotCount = this.ownershipCoordinator.getSnapshot().backgroundHotTabIds.length + 1;
    this.markBackgroundHot(normalizedTabId, backgroundHotCount, 'context_switch');
    this.host.recordRuntimeEvent(
      'window_open_opener_retained',
      `targetTab=${normalizedTargetTabId} ownership=background_hot`,
      normalizedTabId
    );
    return true;
  }

  markBackgroundHot(
    tabId: string,
    maxCount: number,
    overflowReleaseReason: BrowserHostedWebNodeDisposeReason
  ): void {
    const markResult = this.ownershipCoordinator.markBackgroundHot(tabId, maxCount);
    markResult.overflowTabIds.forEach((overflowTabId: string) => {
      this.releaseBackgroundHot(overflowTabId, overflowReleaseReason);
    });
    this.applyOwnershipSnapshot(this.ownershipCoordinator.getSnapshot());
  }

  releaseInactive(reason: BrowserHostedWebNodeDisposeReason): void {
    this.applyReleaseResult(
      this.runtimeLifecyclePort.releaseInactiveHostedRuntimes({
        lifecycleService: this.lifecycleService,
        reason: reason,
        webHostCoordinator: this.webHostCoordinator,
        ownershipCoordinator: this.ownershipCoordinator,
        pageFindCoordinator: this.pageFindCoordinator
      })
    );
  }

  release(tabId: string, reason: BrowserHostedWebNodeDisposeReason): void {
    const normalizedTabId = tabId.trim();
    const retainedOpenerTabId = this.consumeRetainedWindowOpenOpenerForTarget(normalizedTabId);
    this.applyReleaseResult(
      this.runtimeLifecyclePort.releaseHostedRuntime({
        lifecycleService: this.lifecycleService,
        tabId: tabId,
        reason: reason,
        webHostCoordinator: this.webHostCoordinator,
        ownershipCoordinator: this.ownershipCoordinator,
        pageFindCoordinator: this.pageFindCoordinator
      })
    );
    if (retainedOpenerTabId.length > 0) {
      this.releaseRetainedWindowOpenOpener(retainedOpenerTabId, normalizedTabId, reason);
    }
  }

  releaseAll(reason: BrowserHostedWebNodeDisposeAllReason): void {
    this.retainedWindowOpenOpenerByTargetTabId = {};
    this.applyReleaseResult(
      this.runtimeLifecyclePort.releaseAllHostedRuntimes({
        lifecycleService: this.lifecycleService,
        reason: reason,
        webHostCoordinator: this.webHostCoordinator,
        ownershipCoordinator: this.ownershipCoordinator,
        pageFindCoordinator: this.pageFindCoordinator
      })
    );
  }

  releaseParked(tabId: string, source: string): void {
    this.applyReleaseResult(
      this.runtimeLifecyclePort.releaseParkedHostedRuntime({
        lifecycleService: this.lifecycleService,
        tabId: tabId,
        source: source,
        webHostCoordinator: this.webHostCoordinator,
        ownershipCoordinator: this.ownershipCoordinator,
        recordRuntimeEvent: (type: string, message: string, targetTabId: string): void => {
          this.host.recordRuntimeEvent(type, message, targetTabId);
        }
      })
    );
  }

  releaseBackgroundHot(tabId: string, reason: BrowserHostedWebNodeDisposeReason): void {
    this.applyReleaseResult(
      this.runtimeLifecyclePort.releaseBackgroundHotRuntime({
        lifecycleService: this.lifecycleService,
        tabId: tabId,
        reason: reason,
        webHostCoordinator: this.webHostCoordinator,
        ownershipCoordinator: this.ownershipCoordinator,
        clearPreviewTimers: (): void => {
          this.backgroundPreviewRuntimeCoordinator.clearCaptureTimers();
        },
        clearPreviewLoadIssuedTab: (targetTabId: string): void => {
          this.backgroundPreviewRuntimeCoordinator.removeLoadIssued(targetTabId);
        },
        updateBackgroundRuntimeState: (targetTabId: string, runtimeState: TabRuntimeState): void => {
          this.applyBackgroundRuntimeState(targetTabId, runtimeState);
        }
      })
    );
  }

  applyBackgroundRuntimeState(tabId: string, runtimeState: TabRuntimeState): void {
    if (tabId.length === 0) {
      return;
    }
    this.host.applyBackgroundRuntimeTabState(tabId, runtimeState);
    this.runtimeLifecyclePort.patchRuntimeState(tabId, runtimeState, this.resolveLiveControllerState(runtimeState));
  }

  releaseBackgroundHotTabs(reason: BrowserHostedWebNodeDisposeReason): void {
    this.ownershipCoordinator.getSnapshot().backgroundHotTabIds.forEach((tabId: string) => {
      this.releaseBackgroundHot(tabId, reason);
    });
    this.backgroundPreviewRuntimeCoordinator.cancelRequestsOnly();
  }

  releaseForPageDisappear(): void {
    this.releaseBackgroundHotTabs('page_disappear');
    this.releaseInactive('page_disappear');
  }

  parkActiveDesktopWebEntry(tabId: string): boolean {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0 || this.webHostCoordinator.getController(normalizedTabId) === undefined) {
      return false;
    }
    const currentWindowId = this.host.getCurrentWindowId();
    this.applyActiveSurfaceResult(this.webHostCoordinator.parkActive());
    this.markParkedDesktopWebEntry(
      normalizedTabId,
      MAX_PARKED_DESKTOP_WEB_ENTRY_COUNT,
      'parked_desktop_entry_overflow'
    );
    this.host.recordRuntimeEvent('desktop_web_entry_webview_parked', `window=${currentWindowId}`, normalizedTabId);
    return true;
  }

  syncActive(input: BrowserWebHostSyncInput): boolean {
    const previousActiveHostedTabId = this.webHostCoordinator.getActiveHostedTabId();
    const activeTab = input.activeTab;
    if (activeTab !== undefined) {
      const runtime = input.runtime ?? this.runtimeLifecyclePort.resolveRuntime(activeTab.id);
      input.runtime = runtime;
      if (runtime !== undefined && input.userScriptNativeBridge === undefined) {
        input.userScriptNativeBridge = this.host.createUserScriptNativeBridge(activeTab.id, runtime.controller);
      }
    }
    input.showHomePage = this.host.isHomeVisible();
    input.suspendActiveWebSurface = this.host.shouldSuspendActiveWebSurface();
    const result = this.webHostCoordinator.syncActive(input);
    if (previousActiveHostedTabId.length > 0 && previousActiveHostedTabId !== result.activeHostedTabId) {
      this.host.handleWebpageTranslationActiveSurfaceDetached(previousActiveHostedTabId);
    }
    this.applyActiveSurfaceResult(result);
    return result.attached && result.controller?.isWebControllerAttached() === true;
  }

  syncActiveFromHost(activeTab?: BrowserTabState, runtime?: WebTabRuntimeRecord): boolean {
    const surfacePrepareResult = this.prepareActiveSurfaceForSync(activeTab);
    if (surfacePrepareResult.handled) {
      return surfacePrepareResult.attached;
    }
    const config = this.host.buildActiveSurfaceConfig(activeTab);
    return this.syncActive({
      uiContext: config.uiContext,
      activeTab: activeTab,
      runtime: runtime,
      appearancePolicy: config.appearancePolicy,
      documentStartScripts: config.documentStartScripts,
      forceEnableWebZoom: config.forceEnableWebZoom,
      textZoomRatio: config.textZoomRatio,
      pullRefreshNestedScrollEnabled: config.pullRefreshNestedScrollEnabled,
      webVideoControllerBridge: config.webVideoControllerBridge,
      callbacks: config.callbacks
    });
  }

  syncCurrentActiveFromHost(runtime?: WebTabRuntimeRecord): boolean {
    return this.syncActiveFromHost(this.host.resolveActiveTab(), runtime);
  }

  ensureActiveWebSurfaceForNavigation(activeTab: BrowserTabState): void {
    if (this.host.isHomeVisible() || activeTab.isHome) {
      return;
    }
    this.host.applyControllerAttachedState(this.syncActiveFromHost(activeTab));
  }

  syncPreview(input: BrowserWebHostSyncInput): BrowserPreviewWebHostSyncResult {
    input.showHomePage = false;
    input.suspendActiveWebSurface = false;
    return this.webHostCoordinator.syncPreview(input);
  }

  syncPreviewFromHost(tab: BrowserTabState, runtime: WebTabRuntimeRecord): BrowserPreviewWebHostSyncResult {
    const config = this.host.buildPreviewSurfaceConfig(tab, runtime);
    return this.syncPreview({
      uiContext: config.uiContext,
      activeTab: tab,
      runtime: runtime,
      appearancePolicy: config.appearancePolicy,
      userScriptNativeBridge: config.userScriptNativeBridge,
      forceEnableWebZoom: config.forceEnableWebZoom,
      textZoomRatio: config.textZoomRatio,
      callbacks: config.callbacks
    });
  }

  syncPreviewAttachStateFromHost(tab: BrowserTabState, runtime: WebTabRuntimeRecord): BrowserWebHostAttachState {
    const result = this.syncPreviewFromHost(tab, runtime);
    return this.buildAttachState(result);
  }

  updateActiveConfig(input: BrowserWebHostConfigUpdateInput): boolean {
    const activeTab = input.activeTab;
    if (activeTab !== undefined) {
      const controller = input.controller ?? this.runtimeLifecyclePort.resolveController(activeTab.id);
      input.controller = controller;
      if (controller !== undefined && input.userScriptNativeBridge === undefined) {
        input.userScriptNativeBridge = this.host.createUserScriptNativeBridge(activeTab.id, controller);
      }
    }
    input.showHomePage = this.host.isHomeVisible();
    return this.webHostCoordinator.updateExisting(input);
  }

  updateActiveConfigFromHost(activeTab?: BrowserTabState): boolean {
    const config = this.host.buildActiveSurfaceConfig(activeTab);
    return this.updateActiveConfig({
      uiContext: config.uiContext,
      activeTab: activeTab,
      appearancePolicy: config.appearancePolicy,
      documentStartScripts: config.documentStartScripts,
      forceEnableWebZoom: config.forceEnableWebZoom,
      textZoomRatio: config.textZoomRatio,
      pullRefreshNestedScrollEnabled: config.pullRefreshNestedScrollEnabled,
      callbacks: config.callbacks
    });
  }

  updateCurrentActiveConfigFromHost(): boolean {
    return this.updateActiveConfigFromHost(this.host.resolveActiveTab());
  }

  hasActiveHostedSurface(): boolean {
    return this.webHostCoordinator.getActiveHostedTabId().length > 0;
  }

  prepareActiveSurfaceForSync(activeTab?: BrowserTabState): BrowserHostedRuntimeActiveSurfacePrepareResult {
    if (activeTab === undefined) {
      return this.buildPrepareResult(false, false);
    }
    const tabId = activeTab.id;
    const currentWindowId = this.host.getCurrentWindowId();
    if (this.ownershipCoordinator.isParked(tabId)) {
      this.releaseParkedDesktopWebEntryOwnership(tabId);
      this.prepareForegroundAttach(
        tabId,
        currentWindowId,
        'desktop_web_entry_webview_unparking',
        'desktop_web_entry_webview_unpark_skipped',
        'desktop_web_entry_webview_unparked_foreground'
      );
      return this.buildPrepareResult(true, false);
    }
    if (this.ownershipCoordinator.isPendingForegroundAttach(tabId)) {
      return this.buildPrepareResult(true, false);
    }
    if (this.ownershipCoordinator.isBackgroundHot(tabId)) {
      this.releaseBackgroundHotOwnership(tabId);
      this.host.recordRuntimeEvent(
        'background_hot_webview_reusing_fixed_slot',
        `window=${currentWindowId}`,
        tabId
      );
      return this.buildPrepareResult(false, this.isHostedControllerAttached(tabId));
    }
    return this.buildPrepareResult(false, false);
  }

  private prepareForegroundAttach(
    tabId: string,
    currentWindowId: string,
    pendingEvent: string,
    skippedEvent: string,
    finishedEvent: string
  ): void {
    if (!this.beginForegroundAttachOwnership(tabId)) {
      return;
    }
    this.detachHostedController(tabId);
    this.host.recordRuntimeEvent(pendingEvent, `window=${currentWindowId}`, tabId);
    setTimeout(() => {
      this.finishForegroundAttach(tabId, currentWindowId, skippedEvent, finishedEvent);
    }, 0);
  }

  private finishForegroundAttach(
    tabId: string,
    currentWindowId: string,
    skippedEvent: string,
    finishedEvent: string
  ): void {
    const input: BrowserHostedWebForegroundAttachFinishInput = {
      tabId: tabId,
      activeTabId: this.host.getActiveTabId(),
      showHomePage: this.host.isHomeVisible(),
      showTabsSheet: this.host.isTabsVisible()
    };
    const shouldAttachForeground = this.finishForegroundAttachOwnership(input);
    if (!shouldAttachForeground) {
      this.host.recordRuntimeEvent(
        skippedEvent,
        `active=${input.activeTabId} showHome=${input.showHomePage} showTabs=${input.showTabsSheet}`,
        tabId
      );
      return;
    }
    this.host.attachForegroundHostedRuntime();
    this.host.recordRuntimeEvent(finishedEvent, `window=${currentWindowId}`, tabId);
  }

  private buildPrepareResult(handled: boolean, attached: boolean): BrowserHostedRuntimeActiveSurfacePrepareResult {
    return {
      handled: handled,
      attached: attached
    };
  }

  private applyActiveSurfaceResult(result: BrowserWebHostSyncResult): void {
    this.host.applyActiveHostedSurfaceState(result.activeHostedTabId, result.activeHostedRenderKey);
  }

  private applyOwnershipSnapshot(snapshot: BrowserHostedWebOwnershipSnapshot): void {
    this.host.applyHostedHiddenSlots(snapshot.hiddenSlots);
  }

  private releaseBackgroundHotOwnership(tabId: string): void {
    const releaseResult = this.ownershipCoordinator.releaseBackgroundHot(tabId);
    this.applyOwnershipSnapshot(releaseResult.snapshot);
  }

  private markParkedDesktopWebEntry(tabId: string, maxCount: number, overflowReleaseSource: string): void {
    const markResult = this.ownershipCoordinator.markParkedDesktopWebEntry(tabId, maxCount);
    markResult.overflowTabIds.forEach((overflowTabId: string) => {
      this.releaseParked(overflowTabId, overflowReleaseSource);
    });
    this.applyOwnershipSnapshot(this.ownershipCoordinator.getSnapshot());
  }

  private releaseParkedDesktopWebEntryOwnership(tabId: string): void {
    this.applyOwnershipSnapshot(
      this.ownershipCoordinator.releaseParkedDesktopWebEntry(tabId).snapshot
    );
  }

  private consumeRetainedWindowOpenOpenerForTarget(targetTabId: string): string {
    const normalizedTargetTabId = targetTabId.trim();
    if (normalizedTargetTabId.length === 0) {
      return '';
    }
    const openerTabId = this.retainedWindowOpenOpenerByTargetTabId[normalizedTargetTabId] ?? '';
    this.retainedWindowOpenOpenerByTargetTabId[normalizedTargetTabId] = undefined;
    return openerTabId.trim();
  }

  private releaseRetainedWindowOpenOpener(
    openerTabId: string,
    targetTabId: string,
    reason: BrowserHostedWebNodeDisposeReason
  ): void {
    const releaseResult = this.ownershipCoordinator.releaseBackgroundHot(openerTabId);
    this.applyOwnershipSnapshot(releaseResult.snapshot);
    if (releaseResult.released) {
      this.host.recordRuntimeEvent(
        'window_open_opener_released',
        `targetTab=${targetTabId} reason=${reason}`,
        openerTabId
      );
    }
  }

  private beginForegroundAttachOwnership(tabId: string): boolean {
    const startResult = this.ownershipCoordinator.beginForegroundAttach(tabId);
    this.applyOwnershipSnapshot(startResult.snapshot);
    return startResult.shouldScheduleFinish;
  }

  private finishForegroundAttachOwnership(input: BrowserHostedWebForegroundAttachFinishInput): boolean {
    const finishResult = this.ownershipCoordinator.finishForegroundAttach(input);
    this.applyOwnershipSnapshot(finishResult.snapshot);
    return finishResult.shouldAttachForeground;
  }

  private applyReleaseResult(result: BrowserHostedRuntimeReleaseResult): void {
    if (result.activeReleased) {
      this.host.handleActiveRuntimeDetached();
    }
    this.host.applyActiveHostedSurfaceState(result.activeHostedTabId, result.activeHostedRenderKey);
    if (result.ownershipSnapshot !== undefined) {
      this.applyOwnershipSnapshot(result.ownershipSnapshot);
    }
    if (result.activeHostedTabId.length === 0 && !this.hasActiveHostedSurface()) {
      this.host.applyControllerAttachedState(false);
    }
  }

  private resolveLiveControllerState(runtimeState: TabRuntimeState): boolean {
    return runtimeState !== 'suspended';
  }

  private buildAttachState(result: BrowserPreviewWebHostSyncResult): BrowserWebHostAttachState {
    return {
      attached: result.attached,
      webControllerAttached: result.controller?.isWebControllerAttached() === true
    };
  }
}
