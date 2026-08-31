import {
  normalizeNavigationTarget,
  resolveCommittedAddressDisplay
} from './AddressDisplayFormatter';

export type BrowserAddressDisplaySubmissionIntent = 'navigate' | 'search';

export interface BrowserAddressDisplaySubmission {
  submittedText: string;
  resolvedUrl: string;
  intent: BrowserAddressDisplaySubmissionIntent;
}

interface BrowserAddressSearchDisplayState {
  query: string;
  targetUrl: string;
}

export class BrowserAddressDisplayCoordinator {
  private pendingSearchState: BrowserAddressSearchDisplayState | undefined = undefined;
  private searchStateByTabId: Map<string, BrowserAddressSearchDisplayState> = new Map();

  recordSubmission(submission: BrowserAddressDisplaySubmission): void {
    const query = submission.submittedText.trim();
    const targetUrl = submission.resolvedUrl.trim();
    if (submission.intent !== 'search' || query.length === 0 || targetUrl.length === 0) {
      this.pendingSearchState = undefined;
      return;
    }
    this.pendingSearchState = {
      query: query,
      targetUrl: targetUrl
    };
  }

  resolveCommittedDisplay(tabId: string, url: string): string {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return url;
    }

    let state = this.searchStateByTabId.get(normalizedTabId);
    const pendingState = this.pendingSearchState;
    if (pendingState !== undefined &&
      normalizeNavigationTarget(url) === normalizeNavigationTarget(pendingState.targetUrl)) {
      state = pendingState;
      this.searchStateByTabId.set(normalizedTabId, pendingState);
      this.pendingSearchState = undefined;
    }
    if (state === undefined) {
      return url;
    }

    const resolved = resolveCommittedAddressDisplay(url, state.query, state.targetUrl);
    if (resolved.pendingDisplayText.length === 0 || resolved.pendingTargetUrl.length === 0) {
      this.searchStateByTabId.delete(normalizedTabId);
    }
    return resolved.displayText;
  }

  resolveEditingText(tabId: string, currentUrl: string, fallbackText: string): string {
    if (currentUrl.trim().length === 0) {
      return fallbackText;
    }
    return this.resolveCommittedDisplay(tabId, currentUrl);
  }

  pruneTabs(tabIds: string[]): void {
    const retainedStateByTabId: Map<string, BrowserAddressSearchDisplayState> = new Map();
    tabIds.forEach((tabId: string): void => {
      const normalizedTabId = tabId.trim();
      const state = this.searchStateByTabId.get(normalizedTabId);
      if (normalizedTabId.length > 0 && state !== undefined) {
        retainedStateByTabId.set(normalizedTabId, state);
      }
    });
    this.searchStateByTabId = retainedStateByTabId;
  }
}
