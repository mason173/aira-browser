import { webview } from '@kit.ArkWeb';

export type BrowserSslDecisionCacheClearStatus = 'applied' | 'deferred';

export interface BrowserSslDecisionCacheController {
  clearSslCache(): void;
}

export class ArkWebSslDecisionCacheController implements BrowserSslDecisionCacheController {
  private readonly controller: webview.WebviewController;

  constructor(controller: webview.WebviewController) {
    this.controller = controller;
  }

  clearSslCache(): void {
    this.controller.clearSslCache();
  }
}

export class BrowserSslDecisionCacheRuntime {
  private latestAttachedController?: BrowserSslDecisionCacheController;
  private clearPending: boolean = false;

  requestClear(): BrowserSslDecisionCacheClearStatus {
    this.clearPending = true;
    return this.applyPendingClear();
  }

  handleControllerAttached(controller: BrowserSslDecisionCacheController): BrowserSslDecisionCacheClearStatus {
    this.latestAttachedController = controller;
    return this.applyPendingClear();
  }

  isClearPending(): boolean {
    return this.clearPending;
  }

  private applyPendingClear(): BrowserSslDecisionCacheClearStatus {
    if (!this.clearPending) {
      return 'applied';
    }
    const controller = this.latestAttachedController;
    if (controller === undefined) {
      return 'deferred';
    }
    try {
      controller.clearSslCache();
      this.clearPending = false;
      return 'applied';
    } catch (_error) {
      return 'deferred';
    }
  }
}

export const sharedBrowserSslDecisionCacheRuntime: BrowserSslDecisionCacheRuntime =
  new BrowserSslDecisionCacheRuntime();
