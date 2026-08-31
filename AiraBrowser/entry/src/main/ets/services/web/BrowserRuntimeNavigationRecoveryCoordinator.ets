import { BrowserDownloadNavigationStateCoordinator } from '../../core/browser/BrowserDownloadNavigationStateCoordinator';
import { BrowserTabRuntimePatch, BrowserTabState, BrowserTabManagerPort } from '../../core/tabs/TabManager';
import { WebRecoveryManager } from '../../core/web/WebRecoveryManager';
import {
  BrowserRuntimeNavigationRecoveryService
} from './BrowserRuntimeNavigationRecoveryService';
import { BrowserRuntimeLifecyclePort } from './BrowserRuntimeLifecyclePort';

export interface BrowserRuntimeNavigationRecoveryFacts {
  activeTabId: string;
  tabs: BrowserTabState[];
}

export interface BrowserRuntimeNavigationRecoveryCoordinatorHost {
  readFacts: () => BrowserRuntimeNavigationRecoveryFacts;
}

export interface BrowserRuntimeNavigationRecoveryApplication {
  applyTransientNavigationRetryState: () => void;
  applyMainFrameLoadFailure: (tabId: string, errorMessage: string) => void;
}

export interface BrowserRuntimeNavigationRecoveryCoordinatorDependencies {
  recoveryManager: WebRecoveryManager;
  tabManager: BrowserTabManagerPort;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;
  executeLoadUrl: (tabId: string, targetUrl: string, clearHistory: boolean) => boolean;
  commitRetryTabPatch: (tabId: string, patch: BrowserTabRuntimePatch) => void;
  resolveLifecycleApplication: () => BrowserRuntimeNavigationRecoveryApplication;
}

export class BrowserRuntimeNavigationRecoveryCoordinator {
  private readonly host: BrowserRuntimeNavigationRecoveryCoordinatorHost;
  private readonly dependencies: BrowserRuntimeNavigationRecoveryCoordinatorDependencies;
  private readonly service: BrowserRuntimeNavigationRecoveryService;

  constructor(
    host: BrowserRuntimeNavigationRecoveryCoordinatorHost,
    dependencies: BrowserRuntimeNavigationRecoveryCoordinatorDependencies,
    service: BrowserRuntimeNavigationRecoveryService = new BrowserRuntimeNavigationRecoveryService()
  ) {
    this.host = host;
    this.dependencies = dependencies;
    this.service = service;
  }

  restoreWebViewToRestorableUrl(
    tabId: string,
    skippedUrl: string,
    fallbackUrl: string,
    reason: string
  ): void {
    this.service.restoreWebViewToRestorableUrl({
      tabId: tabId,
      skippedUrl: skippedUrl,
      fallbackUrl: fallbackUrl,
      reason: reason,
      rememberTabNavigation: (targetTabId: string, url: string): void => {
        this.dependencies.runtimeLifecyclePort.rememberCommittedNavigation(targetTabId, url);
      },
      executeLoadUrl: (targetTabId: string, targetUrl: string, clearHistory: boolean): boolean => {
        return this.executeLoadUrl(targetTabId, targetUrl, clearHistory);
      },
      markDownloadNavigationRestored: (targetTabId: string, targetSkippedUrl: string): void => {
        this.dependencies.downloadNavigationStateCoordinator.markDownloadNavigationRestored(
          targetTabId,
          targetSkippedUrl
        );
      },
      sanitizeDownloadRuntimeNavigationState: (
        targetTabId: string,
        targetSkippedUrl: string,
        source: string
      ): void => {
        this.dependencies.downloadNavigationStateCoordinator.sanitizeRuntimeNavigationState(
          targetTabId,
          targetSkippedUrl,
          source
        );
      }
    });
  }

  scheduleTransientRestoreRetry(tabId: string, errorMessage: string): boolean {
    const facts = this.host.readFacts();
    return this.service.scheduleTransientRestoreRetry({
      tabId: tabId,
      activeTabId: facts.activeTabId,
      errorMessage: errorMessage,
      recoveryManager: this.dependencies.recoveryManager,
      resolveTab: (targetTabId: string): BrowserTabState | undefined => {
        return this.dependencies.tabManager.getTab(this.host.readFacts().tabs, targetTabId);
      },
      applyTabRuntimePatch: (targetTabId: string, patch: BrowserTabRuntimePatch): void => {
        this.dependencies.commitRetryTabPatch(targetTabId, patch);
      },
      applyActiveRetryState: (): void => {
        this.dependencies.resolveLifecycleApplication().applyTransientNavigationRetryState();
      },
      executeLoadUrl: (targetTabId: string, targetUrl: string): boolean => {
        return this.executeLoadUrl(targetTabId, targetUrl, false);
      },
      applyMainFrameLoadFailure: (targetTabId: string, targetErrorMessage: string): void => {
        this.dependencies.resolveLifecycleApplication().applyMainFrameLoadFailure(
          targetTabId,
          targetErrorMessage
        );
      }
    });
  }

  private executeLoadUrl(tabId: string, targetUrl: string, clearHistory: boolean): boolean {
    return this.dependencies.executeLoadUrl(tabId, targetUrl, clearHistory);
  }

}
