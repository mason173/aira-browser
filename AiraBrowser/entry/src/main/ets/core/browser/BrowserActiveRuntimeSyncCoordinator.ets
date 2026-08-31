import { TabRestoreReason } from '../../common/models/BrowserModels';
import {
  BrowserActiveRuntimeAttachmentResult,
  BrowserActiveRuntimeHost,
  BrowserActiveRuntimeResolution
} from './BrowserRuntimeLifecycleCoordinator';
import { BrowserTabState } from '../tabs/TabManager';
import {
  BrowserRuntimeLifecyclePort,
  BrowserRuntimeMutationPort
} from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import {
  BrowserControllerAttachmentRuntimeCoordinator
} from '../../services/web/BrowserControllerAttachmentRuntimeCoordinator';
import { BrowserWebActiveSurfaceCoordinator } from './BrowserWebActiveSurfaceCoordinator';
import { WebRecoveryManager } from '../web/WebRecoveryManager';
import { WebEventRouter } from '../web/WebEventRouter';
import { TelegramWebCompatibilityService } from '../../services/web/TelegramWebCompatibilityService';
import { WebPageCacheRestoreType } from '../web/WebPageCacheCoordinator';
import { WebTabRuntimeRecord } from '../web/WebTabRuntime';
import {
  BrowserActiveTabRuntimeRestoreCoordinator
} from '../../services/web/BrowserActiveTabRuntimeRestoreCoordinator';

type BrowserPassiveRestorePendingReason = TabRestoreReason | undefined;

export interface BrowserActiveRuntimeSyncFacts {
  activeTabId: string;
  tabs: BrowserTabState[];
  showHomePage: boolean;
  controllerAttached: boolean;
}

export interface BrowserActiveRuntimeSyncSink {
  resolveFacts: () => BrowserActiveRuntimeSyncFacts;
  attachHostedRuntime: (tab: BrowserTabState, runtime: WebTabRuntimeRecord) => boolean;
  beginTransition: () => number;
  isTransitionCurrent: (token: number, tabId: string) => boolean;
  applyControllerAttached: (attached: boolean) => void;
  applyRestoreType: (tab: BrowserTabState, restoreType: WebPageCacheRestoreType) => void;
}

interface BrowserActiveRuntimeSyncDependencies {
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  runtimeMutationPort: BrowserRuntimeMutationPort;
  controllerAttachmentRuntimeCoordinator: BrowserControllerAttachmentRuntimeCoordinator;
  activeSurfaceCoordinator: BrowserWebActiveSurfaceCoordinator;
  webRecoveryManager: WebRecoveryManager;
  webEventRouter: WebEventRouter;
  visibleUrlService: TelegramWebCompatibilityService;
  activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator;
  sink: BrowserActiveRuntimeSyncSink;
}

interface BrowserActiveRuntimeAttachmentRetryRequest {
  tabId: string;
  reason: TabRestoreReason;
  shouldRestoreSessionAfterAttach: boolean;
  transitionToken: number;
}

interface BrowserActiveRuntimeAttachmentRetryRun {
  request: BrowserActiveRuntimeAttachmentRetryRequest;
  attemptIndex: number;
}

export class BrowserActiveRuntimeSyncCoordinator {
  private readonly controllerAttachRestoreFallbackDelayMs: number;
  private readonly dependencies: BrowserActiveRuntimeSyncDependencies;
  private readonly retryDelaysMs: number[];
  private readonly activeRuntimeHost: BrowserActiveRuntimeHost;

  constructor(
    controllerAttachRestoreFallbackDelayMs: number,
    dependencies: BrowserActiveRuntimeSyncDependencies,
    retryDelaysMs: number[] = [80, 180, 360]
  ) {
    this.controllerAttachRestoreFallbackDelayMs = controllerAttachRestoreFallbackDelayMs;
    this.dependencies = dependencies;
    this.retryDelaysMs = retryDelaysMs;
    this.activeRuntimeHost = this.buildActiveRuntimeHost();
  }

  syncActiveRuntime(): void {
    this.dependencies.runtimeLifecyclePort.restoreActiveRuntime(
      'tab_switch',
      (_tabId: string, _restoreReason: TabRestoreReason): void => {
        this.dependencies.runtimeLifecyclePort.runActiveRuntime(this.activeRuntimeHost);
      }
    );
    this.schedulePassiveRestoreRetryIfNeeded();
  }

  syncActiveRuntimeAfterSwitch(): void {
    this.dependencies.runtimeLifecyclePort.restoreActiveRuntime(
      'tab_switch',
      (_tabId: string, _restoreReason: TabRestoreReason): void => {
        const attachment = this.dependencies.runtimeLifecyclePort.runActiveRuntimeAfterSwitch(this.activeRuntimeHost);
        this.handleSwitchAttachment(attachment);
      }
    );
  }

  private handleSwitchAttachment(attachment: BrowserActiveRuntimeAttachmentResult): void {
    if (attachment.attached && attachment.shouldRestoreAfterAttachFallback) {
      this.scheduleControllerAttachRestoreFallback(attachment);
    }
    if (!attachment.attached || !this.dependencies.sink.resolveFacts().controllerAttached) {
      this.scheduleAttachRetry(
        attachment.restoreReason,
        attachment.shouldRestoreSessionAfterAttachRetry
      );
    }
  }

  private buildActiveRuntimeHost(): BrowserActiveRuntimeHost {
    return {
      detachHostedNode: (): void => {
        this.dependencies.hostedRuntimeSurfacePort.detachActive();
      },
      clearControllerAttachment: (): void => {
        this.emitControllerAttached(false);
      },
      attachHostedRuntime: (tab: BrowserTabState, runtime: WebTabRuntimeRecord): boolean => {
        return this.dependencies.sink.attachHostedRuntime(tab, runtime);
      },
      applyRestoreTypeState: (tab: BrowserTabState, restoreType: WebPageCacheRestoreType): void => {
        this.dependencies.sink.applyRestoreType(tab, restoreType);
      },
      refreshRuntimeRecords: (tabIds: string[]): void => {
        this.dependencies.runtimeMutationPort.refresh(tabIds);
      },
      recordPageCacheDecision: (
        _tab: BrowserTabState,
        _runtime: WebTabRuntimeRecord,
        _resolution: BrowserActiveRuntimeResolution
      ): void => {},
      markControllerAttached: (tabId: string): WebTabRuntimeRecord | undefined => {
        const state = this.dependencies.controllerAttachmentRuntimeCoordinator.markControllerAttachedWithState(
          tabId,
          this.dependencies.sink.resolveFacts().controllerAttached
        );
        this.emitControllerAttached(state.controllerAttached);
        return state.runtime;
      },
      applyLiveRuntimePresentation: (tab: BrowserTabState, helperMessage: string): void => {
        this.dependencies.activeSurfaceCoordinator.applyLiveRuntimePresentation(
          tab,
          helperMessage,
          this.dependencies.webRecoveryManager.getDegradedReason(tab.id),
          {
            tabId: tab.id,
            scrollSource: 'controller_attach'
          }
        );
      },
      restoreActiveSession: (reason: TabRestoreReason): void => {
        this.dependencies.activeTabRuntimeRestoreCoordinator.restoreActive(reason);
      }
    };
  }

  private scheduleControllerAttachRestoreFallback(attachment: BrowserActiveRuntimeAttachmentResult): void {
    const tabId = this.dependencies.sink.resolveFacts().activeTabId;
    setTimeout(() => {
      const facts = this.dependencies.sink.resolveFacts();
      if (tabId !== facts.activeTabId || facts.showHomePage) {
        return;
      }
      const activeTab = this.resolveActiveTab(facts);
      if (activeTab === undefined || activeTab.isHome) {
        return;
      }
      const attached = this.dependencies.controllerAttachmentRuntimeCoordinator.resolveLiveRuntimeControllerState(
        tabId,
        facts.controllerAttached
      );
      this.emitControllerAttached(attached);
      if (!attached) {
        return;
      }
      const targetUrl = activeTab.pendingUrl.length > 0 ? activeTab.pendingUrl : activeTab.url;
      this.dependencies.webEventRouter.beginNavigation(
        tabId,
        this.dependencies.visibleUrlService.resolveVisibleUrl(targetUrl),
        true
      );
      this.dependencies.activeTabRuntimeRestoreCoordinator.restore(tabId, attachment.restoreReason);
    }, this.controllerAttachRestoreFallbackDelayMs);
  }

  private schedulePassiveRestoreRetryIfNeeded(): void {
    const facts = this.dependencies.sink.resolveFacts();
    const activeTab = this.resolveActiveTab(facts);
    if (activeTab === undefined || activeTab.isHome || facts.showHomePage) {
      return;
    }
    const restoreReason = this.resolvePassiveRestorePendingReason(activeTab);
    if (restoreReason === undefined) {
      return;
    }
    this.scheduleAttachRetry(restoreReason, true);
  }

  private scheduleAttachRetry(
    reason: TabRestoreReason,
    shouldRestoreSessionAfterAttach: boolean
  ): void {
    const facts = this.dependencies.sink.resolveFacts();
    const request: BrowserActiveRuntimeAttachmentRetryRequest = {
      tabId: facts.activeTabId,
      reason: reason,
      shouldRestoreSessionAfterAttach: shouldRestoreSessionAfterAttach,
      transitionToken: this.dependencies.sink.beginTransition()
    };
    this.scheduleRetryRun({
      request: request,
      attemptIndex: 0
    });
  }

  private scheduleRetryRun(run: BrowserActiveRuntimeAttachmentRetryRun): void {
    setTimeout(() => {
      this.runRetryAttempt(run);
    }, this.resolveRetryDelayMs(run.attemptIndex));
  }

  private runRetryAttempt(run: BrowserActiveRuntimeAttachmentRetryRun): void {
    const request = run.request;
    if (!this.dependencies.sink.isTransitionCurrent(request.transitionToken, request.tabId)) {
      return;
    }
    const facts = this.dependencies.sink.resolveFacts();
    const activeTab = this.resolveActiveTab(facts);
    if (activeTab === undefined || activeTab.isHome) {
      return;
    }
    const attached = this.dependencies.hostedRuntimeSurfacePort.syncActiveFromHost(activeTab) ||
      this.dependencies.hostedRuntimeSurfacePort.isHostedControllerAttached(request.tabId);
    this.emitControllerAttached(attached);
    if (!attached) {
      this.scheduleNextRetryAttempt(run);
      return;
    }
    if (request.shouldRestoreSessionAfterAttach) {
      this.dependencies.activeTabRuntimeRestoreCoordinator.restoreActive(request.reason);
    }
  }

  private scheduleNextRetryAttempt(run: BrowserActiveRuntimeAttachmentRetryRun): void {
    const nextAttemptIndex = run.attemptIndex + 1;
    if (nextAttemptIndex >= this.retryDelaysMs.length) {
      return;
    }
    this.scheduleRetryRun({
      request: run.request,
      attemptIndex: nextAttemptIndex
    });
  }

  private resolveActiveTab(facts: BrowserActiveRuntimeSyncFacts): BrowserTabState | undefined {
    for (let index = 0; index < facts.tabs.length; index += 1) {
      if (facts.tabs[index].id === facts.activeTabId) {
        return facts.tabs[index];
      }
    }
    return undefined;
  }

  private resolvePassiveRestorePendingReason(tab: BrowserTabState): BrowserPassiveRestorePendingReason {
    if (tab.runtimeState === 'loading') {
      return this.resolveLoadingRestoreReason(tab.lastRestoreReason);
    }
    if (tab.runtimeState === 'restoring') {
      return this.resolveStoredRestoreReason(tab.lastRestoreReason, 'tab_switch');
    }
    if (tab.runtimeState === 'crashed' || tab.runtimeState === 'error') {
      return 'crash_restore';
    }
    if (tab.runtimeState === 'cold' || tab.runtimeState === 'discarded') {
      return 'discard_restore';
    }
    if (tab.runtimeState === 'suspended') {
      return this.resolveStoredRestoreReason(tab.lastRestoreReason, 'tab_switch');
    }
    return undefined;
  }

  private resolveLoadingRestoreReason(reason: TabRestoreReason | ''): BrowserPassiveRestorePendingReason {
    switch (reason) {
      case 'cold_start':
      case 'discard_restore':
      case 'crash_restore':
      case 'snapshot_restore':
      case 'snapshot_fallback_reload':
      case 'external_launch':
      case 'controller_attach':
        return reason;
      default:
        return undefined;
    }
  }

  private resolveStoredRestoreReason(
    reason: TabRestoreReason | '',
    fallback: TabRestoreReason
  ): TabRestoreReason {
    switch (reason) {
      case 'cold_start':
      case 'controller_attach':
      case 'tab_switch':
      case 'discard_restore':
      case 'crash_restore':
      case 'snapshot_restore':
      case 'snapshot_fallback_reload':
      case 'external_launch':
        return reason;
      default:
        return fallback;
    }
  }

  private resolveRetryDelayMs(attemptIndex: number): number {
    return this.retryDelaysMs[attemptIndex] ?? 0;
  }

  private emitControllerAttached(attached: boolean): void {
    this.dependencies.sink.applyControllerAttached(attached);
  }

}
