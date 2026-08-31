import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserTabPreviewState } from '../BrowserTabPreviewCoordinator';
import { BrowserTabState } from '../../tabs/TabManager';
import {
  BrowserTabsOverviewThumbnailStore,
  sharedBrowserTabsOverviewThumbnailStore
} from './BrowserTabsOverviewThumbnailStore';

export class BrowserTabsOverviewThumbnailCoordinator {
  private thumbnailStore: BrowserTabsOverviewThumbnailStore = sharedBrowserTabsOverviewThumbnailStore;

  buildGalleryPreviewStates(
    mergedStates: BrowserTabPreviewState[],
    tabs: BrowserTabState[]
  ): BrowserTabPreviewState[] {
    const previewByTabId: Record<string, BrowserTabPreviewState | undefined> = {};
    mergedStates.forEach((previewState: BrowserTabPreviewState) => {
      if (previewState.tabId.trim().length > 0) {
        previewByTabId[previewState.tabId] = previewState;
      }
    });
    tabs.forEach((tab: BrowserTabState) => {
      const existing = previewByTabId[tab.id];
      // previewEntries/session is the single authoritative source. The thumbnail store
      // is used ONLY as a cold fallback when that source carries no image, matching
      // mergeThumbnailAssetIntoTransitionPreviewState so the card and the transition
      // never diverge. (The store is mirrored to previewEntries via
      // reconcileFromPreviewStates, so this fallback is normally the same capture.)
      const existingHasImage = existing !== undefined &&
        ((existing.sharedSnapshotImageUri?.trim().length ?? 0) > 0 ||
          existing.sharedSnapshotPixelMap !== undefined);
      if (existingHasImage) {
        return;
      }
      const thumbnail = this.thumbnailStore.getThumbnail(tab.id);
      if (thumbnail === undefined || thumbnail.imageUri.trim().length <= 0) {
        return;
      }
      hilog.info(0x0000, 'ThumbDiag',
        '[THUMB-DIAG] thumb-store-fallback tab=%{public}s size=%{public}s age=%{public}s',
        tab.id,
        `${thumbnail.imageWidth}x${thumbnail.imageHeight}`,
        `${Math.round((Date.now() - thumbnail.capturedAt) / 1000)}s`);
      previewByTabId[tab.id] = {
        tabId: tab.id,
        sharedSnapshotImageUri: thumbnail.imageUri,
        sharedSnapshotImageWidth: thumbnail.imageWidth,
        sharedSnapshotImageHeight: thumbnail.imageHeight,
        transitionReady: existing?.transitionSource !== undefined,
        transitionCapturedAt: thumbnail.capturedAt,
        transitionSource: existing?.transitionSource,
        lockedForTransition: existing?.lockedForTransition,
        capturedAt: thumbnail.capturedAt,
        failureReason: '',
        captureSource: existing?.captureSource
      };
    });
    const nextStates: BrowserTabPreviewState[] = [];
    tabs.forEach((tab: BrowserTabState) => {
      const previewState = previewByTabId[tab.id];
      if (previewState !== undefined) {
        nextStates.push(previewState);
      }
    });
    return nextStates;
  }

  mergeThumbnailAssetIntoTransitionPreviewState(
    tabId: string,
    previewState: BrowserTabPreviewState | undefined
  ): BrowserTabPreviewState | undefined {
    // If the state already carries a live shared snapshot image, keep it as-is.
    // A stale thumbnail uri must not outrank a fresh PixelMap from the current
    // overview entry capture.
    if (previewState !== undefined &&
      ((previewState.sharedSnapshotImageUri?.trim().length ?? 0) > 0 ||
        previewState.sharedSnapshotPixelMap !== undefined)) {
      return previewState;
    }
    const thumbnail = this.thumbnailStore.getThumbnail(tabId);
    const thumbnailUri = thumbnail?.imageUri.trim() ?? '';
    if (thumbnailUri.length <= 0 || previewState?.transitionSource === undefined) {
      return previewState;
    }
    // Attach the gallery card's thumbnail uri as the transition image. Keep any
    // existing pixel map as a secondary fallback, but the uri is what renders so a
    // late/blank session capture can never blank out the morph.
    return {
      tabId: previewState?.tabId ?? tabId,
      sharedSnapshotImageUri: thumbnailUri,
      sharedSnapshotImageWidth: Math.max(1, Math.floor(thumbnail?.imageWidth ??
        previewState?.sharedSnapshotImageWidth ?? 1)),
      sharedSnapshotImageHeight: Math.max(1, Math.floor(thumbnail?.imageHeight ??
        previewState?.sharedSnapshotImageHeight ?? 1)),
      sharedSnapshotPixelMap: previewState?.sharedSnapshotPixelMap,
      transitionReady: true,
      transitionCapturedAt: previewState?.transitionCapturedAt ?? thumbnail?.capturedAt,
      transitionSource: previewState?.transitionSource,
      lockedForTransition: previewState?.lockedForTransition,
      favicon: previewState?.favicon,
      faviconRevision: previewState?.faviconRevision,
      capturedAt: previewState?.capturedAt ?? thumbnail?.capturedAt ?? 0,
      failureReason: previewState?.failureReason ?? '',
      captureSource: previewState?.captureSource
    };
  }

  rememberPersistedPreviewState(previewState: BrowserTabPreviewState | undefined): boolean {
    const previousVersion = this.thumbnailStore.getVersion();
    this.thumbnailStore.rememberPreviewState(previewState);
    return this.thumbnailStore.getVersion() !== previousVersion;
  }

  // Mirrors the freshest persisted preview of each tab into the thumbnail store so the
  // gallery card's snapshotThumbnail asset stays in lockstep with previewEntries (the
  // single source). Stale writes are dropped by the store's capturedAt guard, so this is
  // safe to call on every render.
  reconcileFromPreviewStates(previewStates: BrowserTabPreviewState[]): void {
    previewStates.forEach((previewState: BrowserTabPreviewState) => {
      this.thumbnailStore.rememberPreviewState(previewState);
    });
  }

  clearMissingTabs(retainedTabs: BrowserTabState[]): boolean {
    return this.thumbnailStore.clearMissingTabs(retainedTabs.map((tab: BrowserTabState) => tab.id));
  }

  clearTab(tabId: string): boolean {
    return this.thumbnailStore.clearTab(tabId);
  }
}
