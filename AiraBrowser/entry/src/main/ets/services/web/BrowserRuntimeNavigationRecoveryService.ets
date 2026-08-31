import { BrowserTabRuntimePatch, BrowserTabState } from '../../core/tabs/TabManager';
import { WebRecoveryManager } from '../../core/web/WebRecoveryManager';
import { normalizeNavigationTarget } from '../../core/browser/AddressDisplayFormatter';

export interface BrowserRestorableNavigationRecoveryRequest {
  tabId: string;
  skippedUrl: string;
  fallbackUrl: string;
  reason: string;
  rememberTabNavigation: (tabId: string, url: string) => void;
  executeLoadUrl: (tabId: string, targetUrl: string, clearHistory: boolean) => boolean;
  markDownloadNavigationRestored: (tabId: string, skippedUrl: string) => void;
  sanitizeDownloadRuntimeNavigationState: (tabId: string, skippedUrl: string, reason: string) => void;
}

export interface BrowserTransientRestoreRetryRequest {
  tabId: string;
  activeTabId: string;
  errorMessage: string;
  recoveryManager: WebRecoveryManager;
  resolveTab: (tabId: string) => BrowserTabState | undefined;
  applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch) => void;
  applyActiveRetryState: () => void;
  executeLoadUrl: (tabId: string, targetUrl: string) => boolean;
  applyMainFrameLoadFailure: (tabId: string, errorMessage: string) => void;
}

export class BrowserRuntimeNavigationRecoveryService {
  restoreWebViewToRestorableUrl(request: BrowserRestorableNavigationRecoveryRequest): void {
    const normalizedFallbackUrl = normalizeNavigationTarget(request.fallbackUrl);
    if (normalizedFallbackUrl.length <= 0 ||
      normalizeNavigationTarget(request.skippedUrl) === normalizedFallbackUrl) {
      return;
    }
    request.rememberTabNavigation(request.tabId, request.fallbackUrl);
    const dispatched = request.executeLoadUrl(request.tabId, request.fallbackUrl, true);
    if (dispatched) {
      request.markDownloadNavigationRestored(request.tabId, request.skippedUrl);
      request.sanitizeDownloadRuntimeNavigationState(request.tabId, request.skippedUrl, request.reason);
    }
  }

  scheduleTransientRestoreRetry(request: BrowserTransientRestoreRetryRequest): boolean {
    const tab = request.resolveTab(request.tabId);
    if (!request.recoveryManager.shouldAutoRetryTransientRestoreLoadFailure(tab, request.errorMessage)) {
      return false;
    }
    if (tab === undefined) {
      return false;
    }
    request.recoveryManager.recordTransientRestoreRetry(request.tabId);
    const targetUrl = request.recoveryManager.resolveTransientRetryTargetUrl(tab);
    if (targetUrl.length <= 0) {
      return false;
    }
    request.applyTabRuntimePatch(request.tabId, {
      runtimeState: 'loading',
      lastError: ''
    });
    if (request.tabId === request.activeTabId) {
      request.applyActiveRetryState();
    }
    setTimeout(() => {
      const retryTab = request.resolveTab(request.tabId);
      if (retryTab === undefined || retryTab.isHome) {
        return;
      }
      const retryTargetUrl = request.recoveryManager.resolveTransientRetryTargetUrl(retryTab);
      if (retryTargetUrl.length <= 0) {
        return;
      }
      if (request.executeLoadUrl(request.tabId, retryTargetUrl)) {
        return;
      }
      request.applyMainFrameLoadFailure(request.tabId, request.errorMessage);
    }, 180);
    return true;
  }

}
