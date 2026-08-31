import { BrowserTabsOverlayRect } from './BrowserTabsOverlayViewModel';

export type BrowserTabsSharedSnapshotEntryPhase =
  'idle' |
  'preparingTarget' |
  'targetReady' |
  'animating' |
  'cancelled';

export interface BrowserTabsSharedSnapshotEntryState {
  id: number;
  phase: BrowserTabsSharedSnapshotEntryPhase;
  tabId: string;
  targetRect?: BrowserTabsOverlayRect;
}

export interface BrowserTabsSharedSnapshotTargetReadyInput {
  tabId: string;
  targetRect: BrowserTabsOverlayRect;
}

export class BrowserTabsSharedSnapshotEntryCoordinator {
  private nextEntryId: number = 0;

  buildIdleState(): BrowserTabsSharedSnapshotEntryState {
    return {
      id: 0,
      phase: 'idle',
      tabId: ''
    };
  }

  beginTargetPreparation(tabId: string): BrowserTabsSharedSnapshotEntryState {
    const trimmedTabId = tabId.trim();
    if (trimmedTabId.length <= 0) {
      return this.buildIdleState();
    }
    this.nextEntryId += 1;
    return {
      id: this.nextEntryId,
      phase: 'preparingTarget',
      tabId: trimmedTabId
    };
  }

  beginTargetPreparationAfterCapturedEntry(
    state: BrowserTabsSharedSnapshotEntryState,
    tabId: string
  ): BrowserTabsSharedSnapshotEntryState {
    if (state.phase !== 'idle' && state.phase !== 'cancelled') {
      return state;
    }
    return this.beginTargetPreparation(tabId);
  }

  markTargetReady(
    state: BrowserTabsSharedSnapshotEntryState,
    input: BrowserTabsSharedSnapshotTargetReadyInput
  ): BrowserTabsSharedSnapshotEntryState {
    if (!this.canAcceptTargetReady(state) || state.tabId !== input.tabId ||
      !this.isUsableRect(input.targetRect)) {
      return state;
    }
    return {
      id: state.id,
      phase: state.phase === 'animating' ? 'animating' : 'targetReady',
      tabId: state.tabId,
      targetRect: this.roundRect(input.targetRect)
    };
  }

  markAnimating(state: BrowserTabsSharedSnapshotEntryState): BrowserTabsSharedSnapshotEntryState {
    if (state.phase !== 'preparingTarget' && state.phase !== 'targetReady') {
      return state;
    }
    return {
      id: state.id,
      phase: 'animating',
      tabId: state.tabId,
      targetRect: state.targetRect
    };
  }

  cancel(state: BrowserTabsSharedSnapshotEntryState): BrowserTabsSharedSnapshotEntryState {
    if (state.phase === 'idle') {
      return state;
    }
    return {
      id: state.id,
      phase: 'cancelled',
      tabId: state.tabId,
      targetRect: state.targetRect
    };
  }

  finish(): BrowserTabsSharedSnapshotEntryState {
    return this.buildIdleState();
  }

  shouldAcceptTargetReady(state: BrowserTabsSharedSnapshotEntryState, tabId: string): boolean {
    return this.canAcceptTargetReady(state) && state.tabId === tabId;
  }

  shouldStartSnapshotEnter(state: BrowserTabsSharedSnapshotEntryState): boolean {
    if (state.tabId.length <= 0) {
      return false;
    }
    return state.phase === 'targetReady';
  }

  resolveTargetRect(state: BrowserTabsSharedSnapshotEntryState): BrowserTabsOverlayRect | undefined {
    if (!this.isUsableOptionalRect(state.targetRect)) {
      return undefined;
    }
    return state.targetRect;
  }

  private roundRect(rect: BrowserTabsOverlayRect): BrowserTabsOverlayRect {
    return {
      left: Math.round(rect.left),
      top: Math.round(rect.top),
      width: Math.round(rect.width),
      height: Math.round(rect.height)
    };
  }

  private isUsableOptionalRect(rect?: BrowserTabsOverlayRect): boolean {
    return rect !== undefined && this.isUsableRect(rect);
  }

  private isUsableRect(rect: BrowserTabsOverlayRect): boolean {
    return rect.width > 0 && rect.height > 0;
  }

  private canAcceptTargetReady(state: BrowserTabsSharedSnapshotEntryState): boolean {
    return state.phase === 'preparingTarget' || state.phase === 'animating';
  }
}
