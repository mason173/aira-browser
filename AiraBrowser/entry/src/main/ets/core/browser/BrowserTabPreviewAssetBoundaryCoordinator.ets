import { BrowserTabState } from '../tabs/TabManager';
import {
  BrowserTabPreviewCoordinator,
  BrowserTabPreviewHydrateOptions,
  BrowserTabPreviewState
} from './BrowserTabPreviewCoordinator';
import {
  BrowserTabPreviewAssetState,
  BrowserTabPreviewAssetSummary
} from './BrowserTabBackgroundTypes';
import { BrowserTabsOverviewSnapshotPipelineCoordinator } from './tabsOverview/BrowserTabsOverviewSnapshotPipelineCoordinator';

export interface BrowserTabPreviewAssetHydrateRequest {
  previewCoordinator: BrowserTabPreviewCoordinator;
  tabs: BrowserTabState[];
  suspendedWindowTabsByWindowId: Record<string, BrowserTabState[] | undefined>;
  currentWindowId: string;
  options?: BrowserTabPreviewHydrateOptions;
  notifyChanged: () => void;
}

export interface BrowserTabPreviewAssetHydrateResult {
  changed: boolean;
  assetsByTabId: Record<string, BrowserTabPreviewAssetState>;
  summary: BrowserTabPreviewAssetSummary;
}

export interface BrowserTabPreviewAssetSyncRequest {
  previewCoordinator: BrowserTabPreviewCoordinator;
  snapshotPipelineCoordinator: BrowserTabsOverviewSnapshotPipelineCoordinator;
  tabs: BrowserTabState[];
  suspendedWindowTabsByWindowId: Record<string, BrowserTabState[] | undefined>;
  currentWindowId: string;
  notifyChanged: () => void;
}

export class BrowserTabPreviewAssetBoundaryCoordinator {
  buildPreviewAssetMap(
    tabs: BrowserTabState[],
    previewStates: BrowserTabPreviewState[]
  ): Record<string, BrowserTabPreviewAssetState> {
    const previewStatesByTabId: Record<string, BrowserTabPreviewState | undefined> = {};
    previewStates.forEach((state: BrowserTabPreviewState) => {
      if (state.tabId.trim().length > 0) {
        previewStatesByTabId[state.tabId] = state;
      }
    });
    const assetsByTabId: Record<string, BrowserTabPreviewAssetState> = {};
    tabs.forEach((tab: BrowserTabState) => {
      assetsByTabId[tab.id] = this.buildPreviewAssetState(tab.id, previewStatesByTabId[tab.id]);
    });
    return assetsByTabId;
  }

  buildPreviewAssetSummary(
    tabs: BrowserTabState[],
    assetsByTabId: Record<string, BrowserTabPreviewAssetState>
  ): BrowserTabPreviewAssetSummary {
    let totalTabCount = 0;
    let displayablePreviewCount = 0;
    let persistedImageCount = 0;
    let memoryImageCount = 0;
    const missingPreviewTabIds: string[] = [];
    tabs.forEach((tab: BrowserTabState) => {
      if (tab.isHome) {
        return;
      }
      totalTabCount += 1;
      const asset = assetsByTabId[tab.id];
      if (asset?.hasDisplayablePreview === true) {
        displayablePreviewCount += 1;
      } else {
        missingPreviewTabIds.push(tab.id);
      }
      if (asset?.hasPersistedImage === true) {
        persistedImageCount += 1;
      }
      if (asset?.hasMemoryImage === true) {
        memoryImageCount += 1;
      }
    });
    return {
      totalTabCount: totalTabCount,
      displayablePreviewCount: displayablePreviewCount,
      persistedImageCount: persistedImageCount,
      memoryImageCount: memoryImageCount,
      missingPreviewTabIds: missingPreviewTabIds
    };
  }

  async hydratePersistedPreviewMetadata(
    request: BrowserTabPreviewAssetHydrateRequest
  ): Promise<BrowserTabPreviewAssetHydrateResult> {
    const retainedTabs = this.buildRetainedTabs(
      request.tabs,
      request.suspendedWindowTabsByWindowId,
      request.currentWindowId
    );
    const syncChanged = request.previewCoordinator.syncTabs(retainedTabs);
    const hydrateChanged = await request.previewCoordinator.hydratePersistedPreviews(retainedTabs,
      this.buildHydrateOptions(request.options, request.notifyChanged));
    const changed = syncChanged || hydrateChanged;
    if (changed) {
      request.notifyChanged();
    }
    const previewStates = request.previewCoordinator.listPreviewStates(retainedTabs);
    const assetsByTabId = this.buildPreviewAssetMap(retainedTabs, previewStates);
    return {
      changed: changed,
      assetsByTabId: assetsByTabId,
      summary: this.buildPreviewAssetSummary(request.tabs, assetsByTabId)
    };
  }

  private buildHydrateOptions(
    options: BrowserTabPreviewHydrateOptions | undefined,
    notifyChanged: () => void
  ): BrowserTabPreviewHydrateOptions {
    return {
      batchSize: options?.batchSize,
      batchDelayMs: options?.batchDelayMs,
      notifyBatchChanged: notifyChanged
    };
  }

  syncPreviewAssetsWithTabs(request: BrowserTabPreviewAssetSyncRequest): boolean {
    const retainedTabs = this.buildRetainedTabs(
      request.tabs,
      request.suspendedWindowTabsByWindowId,
      request.currentWindowId
    );
    const previewChanged = request.previewCoordinator.syncTabs(retainedTabs);
    const thumbnailChanged = request.snapshotPipelineCoordinator.clearMissingTabs(retainedTabs);
    const changed = previewChanged || thumbnailChanged;
    if (changed) {
      request.notifyChanged();
    }
    return changed;
  }

  private buildRetainedTabs(
    tabs: BrowserTabState[],
    suspendedWindowTabsByWindowId: Record<string, BrowserTabState[] | undefined>,
    currentWindowId: string
  ): BrowserTabState[] {
    const retainedTabs = tabs.slice();
    const retainedTabIds: Record<string, boolean> = {};
    retainedTabs.forEach((tab: BrowserTabState) => {
      retainedTabIds[tab.id] = true;
    });
    Object.keys(suspendedWindowTabsByWindowId).forEach((windowId: string) => {
      if (windowId === currentWindowId) {
        return;
      }
      const suspendedTabs = suspendedWindowTabsByWindowId[windowId] ?? [];
      suspendedTabs.forEach((tab: BrowserTabState) => {
        if (retainedTabIds[tab.id] === true) {
          return;
        }
        retainedTabs.push(tab);
        retainedTabIds[tab.id] = true;
      });
    });
    return retainedTabs;
  }

  private buildPreviewAssetState(
    tabId: string,
    previewState?: BrowserTabPreviewState
  ): BrowserTabPreviewAssetState {
    const hasPersistedImage = (previewState?.sharedSnapshotImageUri?.trim().length ?? 0) > 0;
    const hasMemoryImage = previewState?.sharedSnapshotPixelMap !== undefined;
    return {
      tabId: tabId,
      hasDisplayablePreview: hasPersistedImage || hasMemoryImage,
      hasPersistedImage: hasPersistedImage,
      hasMemoryImage: hasMemoryImage,
      capturedAt: previewState?.capturedAt ?? 0,
      source: previewState?.captureSource?.trim() ?? previewState?.transitionSource?.captureSource ?? '',
      failureReason: previewState?.failureReason?.trim() ?? ''
    };
  }
}
