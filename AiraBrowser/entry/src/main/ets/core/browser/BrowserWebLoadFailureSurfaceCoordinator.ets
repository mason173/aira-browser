interface BrowserWebLoadFailureSurfaceRecord {
  errorMessage: string;
  targetUrl: string;
  updatedAt: number;
  webDocumentLoading: boolean;
  webDocumentCommitted: boolean;
  webDocumentFailed: boolean;
}

export class BrowserWebLoadFailureSurfaceCoordinator {
  private recordsByTabId: Record<string, BrowserWebLoadFailureSurfaceRecord | undefined> = {};

  markFailure(tabId: string, errorMessage: string, targetUrl: string = '', now: number = Date.now()): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    this.recordsByTabId[normalizedTabId] = {
      errorMessage: errorMessage.trim(),
      targetUrl: targetUrl.trim(),
      updatedAt: now,
      webDocumentLoading: false,
      webDocumentCommitted: false,
      webDocumentFailed: false
    };
  }

  markWebDocumentLoading(tabId: string, now: number = Date.now()): void {
    const record = this.resolveRecord(tabId);
    if (record === undefined) {
      return;
    }
    record.webDocumentLoading = true;
    record.webDocumentCommitted = false;
    record.webDocumentFailed = false;
    record.updatedAt = now;
  }

  markWebDocumentCommitted(tabId: string, now: number = Date.now()): void {
    const record = this.resolveRecord(tabId);
    if (record === undefined) {
      return;
    }
    record.webDocumentLoading = false;
    record.webDocumentCommitted = true;
    record.webDocumentFailed = false;
    record.updatedAt = now;
  }

  markWebDocumentFailed(tabId: string, now: number = Date.now()): void {
    const record = this.resolveRecord(tabId);
    if (record === undefined) {
      return;
    }
    record.webDocumentLoading = false;
    record.webDocumentFailed = true;
    record.updatedAt = now;
  }

  clear(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    this.recordsByTabId[normalizedTabId] = undefined;
  }

  shouldShow(tabId: string): boolean {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return false;
    }
    return this.recordsByTabId[normalizedTabId] !== undefined;
  }

  shouldShowNativeSurface(tabId: string): boolean {
    const record = this.resolveRecord(tabId);
    if (record === undefined) {
      return false;
    }
    return !record.webDocumentLoading && !record.webDocumentCommitted;
  }

  isWebDocumentLoading(tabId: string): boolean {
    return this.resolveRecord(tabId)?.webDocumentLoading === true;
  }

  isWebDocumentCommitted(tabId: string): boolean {
    return this.resolveRecord(tabId)?.webDocumentCommitted === true;
  }

  resolveTargetUrl(tabId: string): string {
    return this.resolveRecord(tabId)?.targetUrl ?? '';
  }

  shouldIgnoreRepeatedMainFrameError(tabId: string, targetUrl: string): boolean {
    const record = this.resolveRecord(tabId);
    if (record === undefined || record.webDocumentFailed) {
      return false;
    }
    if (!record.webDocumentLoading && !record.webDocumentCommitted) {
      return false;
    }
    const normalizedTargetUrl = targetUrl.trim();
    if (normalizedTargetUrl.length <= 0 || record.targetUrl.length <= 0) {
      return true;
    }
    return normalizedTargetUrl === record.targetUrl;
  }

  resolveErrorMessage(tabId: string, fallbackMessage: string): string {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return fallbackMessage;
    }
    const record = this.recordsByTabId[normalizedTabId];
    if (record === undefined || record.errorMessage.length <= 0) {
      return fallbackMessage;
    }
    return record.errorMessage;
  }

  prune(allowedTabIds: string[]): void {
    const allowed: Record<string, boolean> = {};
    allowedTabIds.forEach((tabId: string) => {
      const normalized = tabId.trim();
      if (normalized.length > 0) {
        allowed[normalized] = true;
      }
    });
    Object.keys(this.recordsByTabId).forEach((tabId: string) => {
      if (!allowed[tabId]) {
        this.recordsByTabId[tabId] = undefined;
      }
    });
  }

  private resolveRecord(tabId: string): BrowserWebLoadFailureSurfaceRecord | undefined {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return undefined;
    }
    return this.recordsByTabId[normalizedTabId];
  }
}
