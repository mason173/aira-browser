import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserTabPreviewState } from '../BrowserTabPreviewCoordinator';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TabsOverviewThumbnail';

export interface BrowserTabsOverviewThumbnailState {
  tabId: string;
  version: number;
  imageUri: string;
  imageWidth: number;
  imageHeight: number;
  capturedAt: number;
}

export class BrowserTabsOverviewThumbnailStore {
  private thumbnailsByTabId: Record<string, BrowserTabsOverviewThumbnailState | undefined> = {};
  private version: number = 0;

  getVersion(): number {
    return this.version;
  }

  getThumbnail(tabId: string): BrowserTabsOverviewThumbnailState | undefined {
    return this.thumbnailsByTabId[tabId];
  }

  rememberUri(
    tabId: string,
    imageUri: string,
    imageWidth: number,
    imageHeight: number,
    capturedAt: number
  ): number {
    const normalizedTabId = tabId.trim();
    const normalizedImageUri = imageUri.trim();
    if (normalizedTabId.length <= 0 || normalizedImageUri.length <= 0) {
      return this.version;
    }
    const existing = this.thumbnailsByTabId[normalizedTabId];
    const normalizedCapturedAt = Math.max(0, Math.floor(capturedAt));
    // Single-source invariant: an older capture must never overwrite a newer one.
    // Reject strictly-stale writes; equal timestamps are treated as idempotent updates
    // (e.g. the same capture re-published with a refreshed uri).
    if (existing !== undefined &&
      normalizedCapturedAt < existing.capturedAt &&
      existing.imageUri.trim().length > 0) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'thumbnail uri stale rejected tab=%{public}s incomingAt=%{public}d existingAt=%{public}d',
        normalizedTabId, normalizedCapturedAt, existing.capturedAt);
      return this.version;
    }
    if (existing !== undefined &&
      existing.imageUri === normalizedImageUri &&
      existing.capturedAt === normalizedCapturedAt &&
      existing.imageWidth === Math.max(1, Math.floor(imageWidth)) &&
      existing.imageHeight === Math.max(1, Math.floor(imageHeight))) {
      return this.version;
    }
    this.version += 1;
    this.thumbnailsByTabId[normalizedTabId] = {
      tabId: normalizedTabId,
      version: this.version,
      imageUri: normalizedImageUri,
      imageWidth: Math.max(1, Math.floor(imageWidth)),
      imageHeight: Math.max(1, Math.floor(imageHeight)),
      capturedAt: normalizedCapturedAt
    };
    return this.version;
  }

  rememberPreviewState(previewState: BrowserTabPreviewState | undefined): number {
    const imageUri = previewState?.sharedSnapshotImageUri?.trim() ?? '';
    if (previewState === undefined || imageUri.length <= 0) {
      return this.version;
    }
    return this.rememberUri(
      previewState.tabId,
      imageUri,
      previewState.sharedSnapshotImageWidth ?? 1,
      previewState.sharedSnapshotImageHeight ?? 1,
      previewState.transitionCapturedAt ?? previewState.capturedAt
    );
  }

  clearTab(tabId: string): boolean {
    const normalizedTabId = tabId.trim();
    const state = this.thumbnailsByTabId[normalizedTabId];
    if (normalizedTabId.length <= 0 || state === undefined) {
      return false;
    }
    this.thumbnailsByTabId[normalizedTabId] = undefined;
    this.version += 1;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'thumbnail cleared tab=%{public}s version=%{public}d',
      normalizedTabId, this.version);
    return true;
  }

  clearMissingTabs(activeTabIds: string[]): boolean {
    const activeLookup: Record<string, boolean> = {};
    activeTabIds.forEach((tabId: string) => {
      const normalizedTabId = tabId.trim();
      if (normalizedTabId.length > 0) {
        activeLookup[normalizedTabId] = true;
      }
    });
    let changed = false;
    Object.keys(this.thumbnailsByTabId).forEach((tabId: string) => {
      const state = this.thumbnailsByTabId[tabId];
      if (state === undefined || activeLookup[tabId]) {
        return;
      }
      changed = true;
      this.thumbnailsByTabId[tabId] = undefined;
    });
    if (changed) {
      this.version += 1;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'thumbnail missing-tabs cleanup version=%{public}d', this.version);
    }
    return changed;
  }

}

export const sharedBrowserTabsOverviewThumbnailStore: BrowserTabsOverviewThumbnailStore =
  new BrowserTabsOverviewThumbnailStore();
