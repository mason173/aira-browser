import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { BrowserTabPreviewState } from './BrowserTabPreviewCoordinator';
import { BrowserTabPreviewTransitionSource } from '../../services/web/BrowserTabPreviewTypes';

export interface BrowserTabsOverviewEntrySnapshotSessionState {
  tabId: string;
  pixelMap?: image.PixelMap;
  width: number;
  height: number;
  capturedAt: number;
  transitionSource?: BrowserTabPreviewTransitionSource;
}

export interface BrowserTabsOverviewEntrySnapshotBeginInput {
  tabId: string;
  pixelMap: image.PixelMap;
  width: number;
  height: number;
  transitionSource: BrowserTabPreviewTransitionSource;
}

export interface BrowserTabsOverviewEntrySnapshotReleaseResult {
  state: BrowserTabsOverviewEntrySnapshotSessionState;
  pixelMapToRelease?: image.PixelMap;
}

export class BrowserTabsOverviewEntrySnapshotSessionCoordinator {
  buildIdleState(): BrowserTabsOverviewEntrySnapshotSessionState {
    return {
      tabId: '',
      width: 0,
      height: 0,
      capturedAt: 0
    };
  }

  beginSession(
    state: BrowserTabsOverviewEntrySnapshotSessionState,
    input: BrowserTabsOverviewEntrySnapshotBeginInput
  ): BrowserTabsOverviewEntrySnapshotReleaseResult {
    const released = this.releaseSession(state);
    return {
      state: {
        tabId: input.tabId,
        pixelMap: input.pixelMap,
        width: Math.max(1, Math.floor(input.width)),
        height: Math.max(1, Math.floor(input.height)),
        capturedAt: Date.now(),
        transitionSource: input.transitionSource
      },
      pixelMapToRelease: released.pixelMapToRelease
    };
  }

  buildPreviewState(
    state: BrowserTabsOverviewEntrySnapshotSessionState,
    persistedState: BrowserTabPreviewState | undefined,
    capturedAt: number
  ): BrowserTabPreviewState | undefined {
    if (state.tabId.length <= 0 || state.pixelMap === undefined) {
      return persistedState;
    }
    hilog.info(0x0000, 'ThumbDiag',
      '[THUMB-DIAG] entry-snapshot tab=%{public}s size=%{public}s source=%{public}s',
      state.tabId,
      `${state.width}x${state.height}`,
      state.transitionSource?.captureSource ?? 'none');
    const freshImageUri = this.resolveFreshPersistedImageUri(state, persistedState);
    return {
      tabId: state.tabId,
      sharedSnapshotImageUri: freshImageUri,
      sharedSnapshotImageWidth: Math.max(1, state.width || persistedState?.sharedSnapshotImageWidth || 1),
      sharedSnapshotImageHeight: Math.max(1, state.height || persistedState?.sharedSnapshotImageHeight || 1),
      sharedSnapshotPixelMap: state.pixelMap,
      transitionReady: true,
      transitionCapturedAt: state.capturedAt > 0 ? state.capturedAt : capturedAt,
      transitionSource: state.transitionSource,
      lockedForTransition: true,
      favicon: persistedState?.favicon,
      faviconRevision: persistedState?.faviconRevision,
      capturedAt: state.capturedAt > 0 ? state.capturedAt : capturedAt,
      failureReason: '',
      captureSource: state.transitionSource?.captureSource ?? 'none'
    };
  }

  private resolveFreshPersistedImageUri(
    state: BrowserTabsOverviewEntrySnapshotSessionState,
    persistedState: BrowserTabPreviewState | undefined
  ): string {
    const persistedImageUri = persistedState?.sharedSnapshotImageUri?.trim() ?? '';
    if (persistedImageUri.length <= 0) {
      return '';
    }
    const persistedCapturedAt = Math.max(0, Math.floor(
      persistedState?.transitionCapturedAt ?? persistedState?.capturedAt ?? 0
    ));
    const sessionCapturedAt = Math.max(0, Math.floor(state.capturedAt));
    return persistedCapturedAt >= sessionCapturedAt ? persistedImageUri : '';
  }

  mergePreviewStatesWithEntrySession(
    state: BrowserTabsOverviewEntrySnapshotSessionState,
    persistedStates: BrowserTabPreviewState[],
    capturedAt: number
  ): BrowserTabPreviewState[] {
    if (state.tabId.length <= 0 || state.pixelMap === undefined) {
      return persistedStates;
    }
    let replaced = false;
    const nextStates = persistedStates.map((item: BrowserTabPreviewState) => {
      if (item.tabId !== state.tabId) {
        return item;
      }
      replaced = true;
      return this.buildPreviewState(state, item, capturedAt) as BrowserTabPreviewState;
    });
    if (!replaced) {
      const entryState = this.buildPreviewState(state, undefined, capturedAt);
      if (entryState !== undefined) {
        nextStates.push(entryState);
      }
    }
    return nextStates;
  }

  releaseSession(
    state: BrowserTabsOverviewEntrySnapshotSessionState,
    tabId?: string
  ): BrowserTabsOverviewEntrySnapshotReleaseResult {
    if (tabId !== undefined && state.tabId !== tabId) {
      return { state: state };
    }
    const pixelMap = state.pixelMap;
    return {
      state: {
        tabId: '',
        width: 0,
        height: 0,
        capturedAt: 0
      },
      pixelMapToRelease: pixelMap
    };
  }

}
