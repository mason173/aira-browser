import { BrowserTabState } from '../../core/tabs/TabManager';
import { WebRuntimeRetentionPlan } from '../../core/web/WebRuntimePoolPolicy';
import { BrowserRuntimeSessionSyncHost } from '../../core/browser/BrowserRuntimeLifecycleCoordinator';
import { BrowserRuntimeTransactionSignalService } from '../../core/browser/BrowserRuntimeTransactionSignalService';
import {
  BrowserTabBackgroundTrigger,
  BrowserTabDiscardTask,
  BrowserTabPageBehaviorPatch,
  BrowserTabPageBehaviorPrioritySummary,
  BrowserTabPageBehaviorState
} from '../../core/browser/BrowserTabBackgroundTypes';
import { BrowserTabPreviewAssetBoundaryCoordinator } from '../../core/browser/BrowserTabPreviewAssetBoundaryCoordinator';
import { BrowserSystemMemoryPressureSignal } from '../../core/browser/BrowserSystemMemoryPressureSignal';
import { BrowserTabPreviewState } from '../../core/browser/BrowserTabPreviewCoordinator';
import { BrowserBackgroundTabPreviewRuntimeCoordinator } from '../../core/browser/BrowserBackgroundTabPreviewRuntimeCoordinator';
import { BrowserHostedWebHiddenSlot } from '../../core/browser/BrowserHostedWebOwnershipCoordinator';
import { BrowserHostedRuntimeSurfacePort } from './BrowserHostedRuntimeSurfacePort';
import { BrowserRuntimeLifecyclePort } from './BrowserRuntimeLifecyclePort';
import {
  BrowserMaterializationOptions,
  DEFAULT_BROWSER_MATERIALIZATION_POLICY
} from '../../core/browser/BrowserMaterializationPolicy';
import {
  BrowserWindowSessionLifetimeListener,
  sharedBrowserWindowSessionLifetimeSignal
} from '../../core/browser/BrowserWindowSessionLifetimeSignal';

const DOWNLOAD_BEHAVIOR_RECHECK_DELAY_MS: number = 2500;

interface RawPageBehaviorSignalPayload {
  isScreenCapture?: boolean;
  isMediaPlaying?: boolean;
  isUserEditing?: boolean;
  source?: string;
}

export interface BrowserTabBackgroundSessionSyncCoordinatorHost {
  isRestoringTabs: () => boolean;
  getTabs: () => BrowserTabState[];
  getActiveTabId: () => string;
  getWindowId: () => string;
  getPreviousRetentionPlan: () => WebRuntimeRetentionPlan;
  applySessionSyncState: (tabs: BrowserTabState[], retentionPlan: WebRuntimeRetentionPlan) => void;
  recordRuntimeEvent: (type: string, message: string, tabId?: string) => void;
}

export interface BrowserTabBackgroundSessionSyncCoordinatorDependencies {
  persistTabs: () => void;
  getActiveDownloadCountSnapshot: () => number;
  getPreviewStates: () => BrowserTabPreviewState[];
  pruneRuntimeTelemetry: (tabIds: string[]) => void;
}

export class BrowserTabBackgroundSessionSyncCoordinator {
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly previewAssetBoundaryCoordinator: BrowserTabPreviewAssetBoundaryCoordinator;
  private readonly backgroundPreviewRuntimeCoordinator: BrowserBackgroundTabPreviewRuntimeCoordinator;
  private readonly hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  private readonly runtimeTransactionSignalService: BrowserRuntimeTransactionSignalService =
    new BrowserRuntimeTransactionSignalService();
  private readonly dependencies: BrowserTabBackgroundSessionSyncCoordinatorDependencies;
  private readonly host: BrowserTabBackgroundSessionSyncCoordinatorHost;
  private protectionReasonsByTabId: Record<string, string> = {};
  private pageBehaviorByTabId: Record<string, BrowserTabPageBehaviorState> = {};
  private coolingTimer: number = -1;
  private coolingIntervalMs: number = -1;
  private sessionForeground: boolean = false;
  private lifetimeWindowId: string = '';
  private readonly sessionLifetimeListener: BrowserWindowSessionLifetimeListener = (foreground: boolean): void => {
    this.handleSessionLifetimeChanged(foreground);
  };
  private downloadBehaviorRecheckTimer: number = -1;

  constructor(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    previewAssetBoundaryCoordinator: BrowserTabPreviewAssetBoundaryCoordinator,
    backgroundPreviewRuntimeCoordinator: BrowserBackgroundTabPreviewRuntimeCoordinator,
    hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort,
    dependencies: BrowserTabBackgroundSessionSyncCoordinatorDependencies,
    host: BrowserTabBackgroundSessionSyncCoordinatorHost
  ) {
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.previewAssetBoundaryCoordinator = previewAssetBoundaryCoordinator;
    this.backgroundPreviewRuntimeCoordinator = backgroundPreviewRuntimeCoordinator;
    this.hostedRuntimeSurfacePort = hostedRuntimeSurfacePort;
    this.dependencies = dependencies;
    this.host = host;
  }

  protect(tabId: string, reason: string): void {
    if (tabId.length === 0 || reason.length === 0) {
      return;
    }
    if ((this.protectionReasonsByTabId[tabId] ?? '') === reason) {
      return;
    }
    this.protectionReasonsByTabId[tabId] = reason;
    this.syncProtectionSignalChange(tabId, 'protect', reason);
  }

  release(tabId: string): void {
    if (tabId.length === 0) {
      return;
    }
    const previousReason = this.protectionReasonsByTabId[tabId] ?? '';
    if (previousReason.length <= 0) {
      return;
    }
    const nextReasons: Record<string, string> = {};
    Object.keys(this.protectionReasonsByTabId).forEach((key: string) => {
      if (key !== tabId) {
        nextReasons[key] = this.protectionReasonsByTabId[key];
      }
    });
    this.protectionReasonsByTabId = nextReasons;
    this.syncProtectionSignalChange(tabId, 'release', previousReason);
  }

  sync(
    trigger: BrowserTabBackgroundTrigger = 'session_sync',
    options: BrowserMaterializationOptions = {}
  ): boolean {
    const tabs = this.host.getTabs();
    const windowId = this.host.getWindowId();
    const runtimeSessionSyncHost = this.buildRuntimeSessionSyncHost();
    const materializationPolicy = options.materializationPolicy ??
      (this.host.isRestoringTabs() ? 'active_only' : DEFAULT_BROWSER_MATERIALIZATION_POLICY);
    const result = this.runtimeLifecyclePort.runBackgroundSessionSync({
      tabs: tabs,
      activeTabId: this.host.getActiveTabId(),
      windowId: windowId,
      windowState: this.runtimeLifecyclePort.buildBackgroundWindowState(windowId),
      previousRetentionPlan: this.host.getPreviousRetentionPlan(),
      host: runtimeSessionSyncHost,
      trigger: trigger,
      activeDownloadCount: this.dependencies.getActiveDownloadCountSnapshot(),
      explicitProtectionReasonsByTabId: this.buildProtectionReasons(),
      pageBehaviorByTabId: this.buildPageBehaviorMap(tabs),
      previewAssetsByTabId: this.previewAssetBoundaryCoordinator.buildPreviewAssetMap(
        tabs,
        this.dependencies.getPreviewStates()
      ),
      systemMemoryPressure: BrowserSystemMemoryPressureSignal.getSnapshot(),
      materializationPolicy: materializationPolicy,
      resolveDiscardQueueTab: (tabId: string): BrowserTabState | undefined => {
        return this.host.getTabs().find((candidate: BrowserTabState): boolean => candidate.id === tabId);
      },
      executeDiscardTask: (task: BrowserTabDiscardTask): void => {
        this.runtimeLifecyclePort.discardRuntime(task, this.buildProtectionReasons(true));
      },
      recordDiscardQueueRuntimeEvent: (type: string, message: string, tabId: string): void => {
        runtimeSessionSyncHost.recordRuntimeEvent(type, message, tabId);
      }
    });
    if (result === undefined) {
      return false;
    }
    return result.lifecycleResult.retentionStateChanged;
  }

  handlePageBehaviorSignal(tabId: string, payloadJson: string): void {
    const patch = this.parsePageBehaviorSignal(payloadJson);
    if (patch === undefined) {
      return;
    }
    this.applyPageBehaviorPatch(tabId, patch, 'web_probe');
  }

  clearRuntimePageBehavior(tabId: string, source: string = 'navigation'): void {
    this.applyPageBehaviorPatch(tabId, {
      isScreenCapture: false,
      isMediaPlaying: false,
      isUserEditing: false,
      source: source
    }, source);
  }

  markNativeMediaPlayback(tabId: string, isPlaying: boolean, source: string): void {
    this.applyPageBehaviorPatch(tabId, {
      isMediaPlaying: isPlaying,
      source: source
    }, source);
  }

  markDownloadStarted(tabId: string): void {
    this.applyPageBehaviorPatch(tabId, {
      isDownloading: true,
      source: 'download_start'
    }, 'download_start');
    this.scheduleDownloadBehaviorRecheck();
  }

  handleDownloadActivitySnapshot(): void {
    if (this.dependencies.getActiveDownloadCountSnapshot() > 0) {
      return;
    }
    this.clearDownloadPageBehavior('download_idle');
  }

  private buildProtectionReasons(includePageBehavior: boolean = false): Record<string, string> {
    const reasons: Record<string, string> = {};
    Object.keys(this.protectionReasonsByTabId).forEach((tabId: string) => {
      const reason = this.protectionReasonsByTabId[tabId] ?? '';
      if (reason.length > 0) {
        reasons[tabId] = reason;
      }
    });
    this.appendWindowOpenOpenerProtectionReasons(reasons, this.host.getTabs());
    const activePreviewTabId = this.backgroundPreviewRuntimeCoordinator.getActiveRequestTabId();
    if (activePreviewTabId.length > 0) {
      reasons[activePreviewTabId] = '后台标签页正在生成预览图';
    }
    this.hostedRuntimeSurfacePort.getHiddenSlots().forEach((slot: BrowserHostedWebHiddenSlot) => {
      if ((reasons[slot.tabId] ?? '').length > 0) {
        return;
      }
      reasons[slot.tabId] = this.resolveHiddenSlotReason(slot);
    });
    if (includePageBehavior) {
      const pageBehaviorByTabId = this.buildPageBehaviorMap(this.host.getTabs());
      Object.keys(pageBehaviorByTabId).forEach((tabId: string) => {
        if ((reasons[tabId] ?? '').length > 0) {
          return;
        }
        const reason = this.resolvePageBehaviorProtectionReason(pageBehaviorByTabId[tabId]);
        if (reason.length > 0) {
          reasons[tabId] = reason;
        }
      });
    }
    return reasons;
  }

  private appendWindowOpenOpenerProtectionReasons(
    reasons: Record<string, string>,
    tabs: BrowserTabState[]
  ): void {
    const existingTabIds: Record<string, boolean> = {};
    tabs.forEach((tab: BrowserTabState): void => {
      existingTabIds[tab.id] = true;
    });
    tabs.forEach((tab: BrowserTabState): void => {
      const openerTabId = tab.openerTabId.trim();
      if (!tab.openedByNewWindow || openerTabId.length <= 0 || existingTabIds[openerTabId] !== true) {
        return;
      }
      if ((reasons[openerTabId] ?? '').length > 0) {
        return;
      }
      reasons[openerTabId] = `新窗口 child=${tab.id} 仍存在，保留 opener live runtime。`;
    });
  }

  private buildPageBehaviorMap(tabs: BrowserTabState[]): Record<string, BrowserTabPageBehaviorState> {
    const activeTabIds: Record<string, boolean> = {};
    tabs.forEach((tab: BrowserTabState) => {
      activeTabIds[tab.id] = true;
    });
    const result: Record<string, BrowserTabPageBehaviorState> = {};
    const retained: Record<string, BrowserTabPageBehaviorState> = {};
    Object.keys(this.pageBehaviorByTabId).forEach((tabId: string) => {
      if (activeTabIds[tabId] !== true) {
        return;
      }
      const state = this.pageBehaviorByTabId[tabId];
      if (!this.hasAnyPageBehavior(state)) {
        return;
      }
      retained[tabId] = state;
      result[tabId] = state;
    });
    this.pageBehaviorByTabId = retained;
    return result;
  }

  private parsePageBehaviorSignal(payloadJson: string): BrowserTabPageBehaviorPatch | undefined {
    try {
      const payload = JSON.parse(payloadJson) as RawPageBehaviorSignalPayload;
      return {
        isScreenCapture: payload.isScreenCapture === true,
        isMediaPlaying: payload.isMediaPlaying === true,
        isUserEditing: payload.isUserEditing === true,
        source: payload.source ?? 'web_probe'
      };
    } catch (_error) {
      return undefined;
    }
  }

  private applyPageBehaviorPatch(
    tabId: string,
    patch: BrowserTabPageBehaviorPatch,
    fallbackSource: string
  ): boolean {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return false;
    }
    const current = this.pageBehaviorByTabId[normalizedTabId] ?? this.buildEmptyPageBehaviorState(fallbackSource);
    const source = (patch.source ?? fallbackSource).trim();
    const next: BrowserTabPageBehaviorState = {
      isScreenCapture: patch.isScreenCapture ?? current.isScreenCapture,
      isMediaPlaying: patch.isMediaPlaying ?? current.isMediaPlaying,
      isUserEditing: patch.isUserEditing ?? current.isUserEditing,
      isDownloading: patch.isDownloading ?? current.isDownloading,
      updatedAt: Date.now(),
      source: source.length > 0 ? source : fallbackSource
    };
    if (this.isSamePageBehaviorState(current, next)) {
      return false;
    }
    if (this.hasAnyPageBehavior(next)) {
      this.pageBehaviorByTabId[normalizedTabId] = next;
    } else {
      this.removePageBehavior(normalizedTabId);
    }
    this.syncPageBehaviorSignalChange(normalizedTabId, next.source, this.hasAnyPageBehavior(next) ? next : undefined);
    return true;
  }

  private clearDownloadPageBehavior(source: string): void {
    const tabIds = Object.keys(this.pageBehaviorByTabId);
    tabIds.forEach((tabId: string) => {
      const state = this.pageBehaviorByTabId[tabId];
      if (!state.isDownloading) {
        return;
      }
      this.applyPageBehaviorPatch(tabId, {
        isDownloading: false,
        source: source
      }, source);
    });
  }

  private scheduleDownloadBehaviorRecheck(): void {
    if (this.downloadBehaviorRecheckTimer >= 0) {
      clearTimeout(this.downloadBehaviorRecheckTimer);
    }
    this.downloadBehaviorRecheckTimer = setTimeout(() => {
      this.downloadBehaviorRecheckTimer = -1;
      this.handleDownloadActivitySnapshot();
    }, DOWNLOAD_BEHAVIOR_RECHECK_DELAY_MS);
  }

  private buildEmptyPageBehaviorState(source: string): BrowserTabPageBehaviorState {
    return {
      isScreenCapture: false,
      isMediaPlaying: false,
      isUserEditing: false,
      isDownloading: false,
      updatedAt: 0,
      source: source
    };
  }

  private isSamePageBehaviorState(
    left: BrowserTabPageBehaviorState,
    right: BrowserTabPageBehaviorState
  ): boolean {
    return left.isScreenCapture === right.isScreenCapture &&
      left.isMediaPlaying === right.isMediaPlaying &&
      left.isUserEditing === right.isUserEditing &&
      left.isDownloading === right.isDownloading;
  }

  private removePageBehavior(tabId: string): void {
    const next: Record<string, BrowserTabPageBehaviorState> = {};
    Object.keys(this.pageBehaviorByTabId).forEach((key: string) => {
      if (key !== tabId) {
        next[key] = this.pageBehaviorByTabId[key];
      }
    });
    this.pageBehaviorByTabId = next;
  }

  private hasAnyPageBehavior(state: BrowserTabPageBehaviorState): boolean {
    return state.isScreenCapture || state.isMediaPlaying || state.isUserEditing || state.isDownloading;
  }

  private syncPageBehaviorSignalChange(
    tabId: string,
    source: string,
    state?: BrowserTabPageBehaviorState
  ): void {
    const retentionStateChanged = this.sync('page_signal_changed');
    if (retentionStateChanged) {
      this.dependencies.persistTabs();
    }
    const prioritySummary: BrowserTabPageBehaviorPrioritySummary | undefined =
      this.runtimeTransactionSignalService.resolvePageBehaviorPrioritySummary(state);
    this.host.recordRuntimeEvent(
      'tab_page_behavior_signal_changed',
      `changed=${retentionStateChanged ? 'true' : 'false'} source=${source} ` +
        `screenCapture=${state?.isScreenCapture === true ? 'true' : 'false'} ` +
        `media=${state?.isMediaPlaying === true ? 'true' : 'false'} ` +
        `editing=${state?.isUserEditing === true ? 'true' : 'false'} ` +
        `download=${state?.isDownloading === true ? 'true' : 'false'} ` +
        `behaviorScore=${prioritySummary?.totalPriority ?? 0} ` +
        `behaviorSignals=${this.runtimeTransactionSignalService.formatPageBehaviorSignalList(prioritySummary)}`,
      tabId
    );
  }

  private resolvePageBehaviorProtectionReason(state: BrowserTabPageBehaviorState | undefined): string {
    return this.runtimeTransactionSignalService.formatPageBehaviorProtectionReason(state);
  }

  private syncProtectionSignalChange(tabId: string, action: 'protect' | 'release', reason: string): void {
    const retentionStateChanged = this.sync('page_signal_changed');
    if (retentionStateChanged) {
      this.dependencies.persistTabs();
    }
    this.host.recordRuntimeEvent(
      'tab_background_protection_signal_changed',
      `action=${action} changed=${retentionStateChanged ? 'true' : 'false'} reason=${reason}`,
      tabId
    );
  }

  private resolveHiddenSlotReason(slot: BrowserHostedWebHiddenSlot): string {
    if (slot.kind === 'background-hot') {
      return '后台打开标签页已热加载，等待用户切入。';
    }
    return '桌面网页入口已停放保活，等待用户切回。';
  }

  private buildRuntimeSessionSyncHost(): BrowserRuntimeSessionSyncHost {
    return {
      persistCoolingRuntimeSnapshot: (
        tabId: string,
        releaseHostedNodeAfterPersist: boolean
      ): void => {
        this.runtimeLifecyclePort.persistMountedRuntimeSnapshot(tabId, releaseHostedNodeAfterPersist);
      },
      applySessionSyncState: (tabs: BrowserTabState[], retentionPlan: WebRuntimeRetentionPlan): void => {
        this.host.applySessionSyncState(tabs, retentionPlan);
      },
      recordRuntimeEvent: (type: string, message: string, tabId?: string): void => {
        this.host.recordRuntimeEvent(type, message, tabId);
      },
      pruneRuntimeTelemetry: (tabIds: string[]): void => {
        this.dependencies.pruneRuntimeTelemetry(tabIds);
      }
    };
  }

  markAppForeground(windowId: string): void {
    this.runtimeLifecyclePort.markBackgroundAppForeground(windowId);
  }

  markWindowActive(windowId: string): void {
    this.runtimeLifecyclePort.markBackgroundWindowActive(windowId);
  }

  markAppBackgroundAndSync(windowId: string): boolean {
    this.runtimeLifecyclePort.markBackgroundAppBackground(windowId);
    return this.sync('app_background');
  }

  handleAppBackground(windowId: string): void {
    if (this.markAppBackgroundAndSync(windowId)) {
      this.dependencies.persistTabs();
    }
  }

  markWindowHiddenAndSync(windowId: string): boolean {
    this.runtimeLifecyclePort.markBackgroundWindowHidden(windowId);
    return this.sync('window_hidden');
  }

  handleWindowHidden(windowId: string): void {
    if (this.markWindowHiddenAndSync(windowId)) {
      this.dependencies.persistTabs();
    }
  }

  syncAppForeground(): boolean {
    return this.sync('app_foreground');
  }

  handleAppForegroundFollowup(tabId: string): boolean {
    const retentionStateChanged = this.syncAppForeground();
    if (!retentionStateChanged) {
      return false;
    }
    this.dependencies.persistTabs();
    this.host.recordRuntimeEvent(
      'page_foreground_retention_sync',
      `页面前台恢复后已刷新 runtime retention 计划 downloads=${this.dependencies.getActiveDownloadCountSnapshot()}`,
      tabId
    );
    return true;
  }

  startCoolingTimer(intervalMs: number): void {
    this.bindSessionLifetime();
    const normalizedIntervalMs = Math.max(1, Math.floor(intervalMs));
    if (this.coolingIntervalMs === normalizedIntervalMs && this.coolingTimer >= 0) {
      return;
    }
    this.coolingIntervalMs = normalizedIntervalMs;
    this.suspendCoolingTimer();
    this.resumeCoolingTimer();
  }

  stopCoolingTimer(): void {
    this.coolingIntervalMs = -1;
    this.suspendCoolingTimer();
    this.unbindSessionLifetime();
  }

  handleSessionLifetimeChanged(foreground: boolean): void {
    this.sessionForeground = foreground;
    if (!foreground) {
      this.suspendCoolingTimer();
      this.handleAppBackground(this.host.getWindowId());
      return;
    }
    this.markAppForeground(this.host.getWindowId());
    this.resumeCoolingTimer();
  }

  private resumeCoolingTimer(): void {
    if (!this.sessionForeground || this.coolingIntervalMs <= 0 || this.coolingTimer >= 0) {
      return;
    }
    this.coolingTimer = setInterval(() => {
      this.handleCoolingTick();
    }, this.coolingIntervalMs);
  }

  private suspendCoolingTimer(): void {
    if (this.coolingTimer < 0) {
      return;
    }
    clearInterval(this.coolingTimer);
    this.coolingTimer = -1;
  }

  private bindSessionLifetime(): void {
    const windowId = this.host.getWindowId().trim();
    if (windowId.length === 0 || windowId === this.lifetimeWindowId) {
      return;
    }
    this.unbindSessionLifetime();
    this.lifetimeWindowId = windowId;
    sharedBrowserWindowSessionLifetimeSignal.subscribe(windowId, this.sessionLifetimeListener);
  }

  private unbindSessionLifetime(): void {
    if (this.lifetimeWindowId.length > 0) {
      sharedBrowserWindowSessionLifetimeSignal.unsubscribe(
        this.lifetimeWindowId,
        this.sessionLifetimeListener
      );
    }
    this.lifetimeWindowId = '';
    this.sessionForeground = false;
  }

  handleCoolingTick(): void {
    if (!this.sessionForeground || this.host.isRestoringTabs()) {
      return;
    }
    const retentionStateChanged = this.sync('cooling_tick');
    if (!retentionStateChanged) {
      return;
    }
    this.dependencies.persistTabs();
    this.host.recordRuntimeEvent(
      'runtime_cooling_tick',
      '后台标签页降温时钟已刷新 runtime retention 计划'
    );
  }

  handleSystemMemoryPressureRevision(revision: number): void {
    if (revision <= 0) {
      return;
    }
    const snapshot = BrowserSystemMemoryPressureSignal.getSnapshot();
    this.host.recordRuntimeEvent(
      'system_memory_pressure',
      `level=${snapshot.level} raw=${snapshot.rawLevel} source=${snapshot.source} revision=${snapshot.revision}`,
      this.host.getActiveTabId()
    );
    if (this.sync('memory_pressure')) {
      this.dependencies.persistTabs();
    }
  }
}
