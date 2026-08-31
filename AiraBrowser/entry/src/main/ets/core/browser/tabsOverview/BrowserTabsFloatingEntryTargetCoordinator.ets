import { BrowserTabsOverlayRect } from '../BrowserTabsOverlayViewModel';

export interface BrowserTabsFloatingEntryTargetPreparationState {
  version: number;
  targetTabId: string;
  scrollIssuedTabId: string;
  preparedTabId: string;
  minimumRectGeneration: number;
  previewRectByTabId: Record<string, BrowserTabsOverlayRect | undefined>;
  previewRectGenerationByTabId: Record<string, number>;
  previewRectGeneration: number;
}

export interface BrowserTabsFloatingEntryTargetMeasuredRectInput {
  state: BrowserTabsFloatingEntryTargetPreparationState;
  tabId: string;
  rect: BrowserTabsOverlayRect | undefined;
  rectGeneration: number;
}

export interface BrowserTabsFloatingEntryTargetResolvedRectResult {
  state: BrowserTabsFloatingEntryTargetPreparationState;
  ready: boolean;
}

export interface BrowserTabsFloatingEntryTargetRecordedRectResult {
  state: BrowserTabsFloatingEntryTargetPreparationState;
  rect: BrowserTabsOverlayRect;
  measuredResult: BrowserTabsFloatingEntryTargetResolvedRectResult;
  shouldDefer: boolean;
  shouldScheduleReady: boolean;
}

export type BrowserTabsFloatingEntryTargetReadyAction = 'ignore' | 'publish' | 'retry';

export interface BrowserTabsFloatingEntryTargetReadyAttemptInput {
  state: BrowserTabsFloatingEntryTargetPreparationState;
  tabId: string;
  version: number;
  targetTabId: string;
  predictedRect?: BrowserTabsOverlayRect;
  attempt: number;
  maxAttempts: number;
}

export interface BrowserTabsFloatingEntryTargetReadyAttemptResult {
  state: BrowserTabsFloatingEntryTargetPreparationState;
  action: BrowserTabsFloatingEntryTargetReadyAction;
  rect?: BrowserTabsOverlayRect;
  nextAttempt: number;
}

export interface BrowserTabsFloatingEntryTargetRectInput {
  tabIds: string[];
  tabId: string;
  slotCount: number;
  viewportLeft: number;
  viewportTop: number;
  viewportHeight: number;
  horizontalPadding: number;
  topPadding: number;
  bottomPadding: number;
  columnCount: number;
  cardWidth: number;
  previewHeight: number;
  previewTopInset: number;
  itemHeight: number;
  gridGap: number;
}

export class BrowserTabsFloatingEntryTargetCoordinator {
  buildIdleState(version: number = 0): BrowserTabsFloatingEntryTargetPreparationState {
    return {
      version: version,
      targetTabId: '',
      scrollIssuedTabId: '',
      preparedTabId: '',
      minimumRectGeneration: 0,
      previewRectByTabId: {},
      previewRectGenerationByTabId: {},
      previewRectGeneration: 0
    };
  }

  cancel(state: BrowserTabsFloatingEntryTargetPreparationState): BrowserTabsFloatingEntryTargetPreparationState {
    return this.buildIdleState(state.version + 1);
  }

  beginPreparation(
    state: BrowserTabsFloatingEntryTargetPreparationState,
    tabId: string
  ): BrowserTabsFloatingEntryTargetPreparationState {
    const targetTabId = tabId.trim();
    if (targetTabId.length <= 0) {
      return this.cancel(state);
    }
    if (state.targetTabId === targetTabId && state.preparedTabId !== targetTabId) {
      return state;
    }
    return {
      version: state.version + 1,
      targetTabId: targetTabId,
      scrollIssuedTabId: '',
      preparedTabId: '',
      minimumRectGeneration: 0,
      previewRectByTabId: state.previewRectByTabId,
      previewRectGenerationByTabId: state.previewRectGenerationByTabId,
      previewRectGeneration: state.previewRectGeneration
    };
  }

  markScrollIssued(
    state: BrowserTabsFloatingEntryTargetPreparationState,
    tabId: string,
    currentRectGeneration: number
  ): BrowserTabsFloatingEntryTargetPreparationState {
    const targetTabId = tabId.trim();
    if (targetTabId.length <= 0 || state.targetTabId !== targetTabId) {
      return state;
    }
    return {
      version: state.version,
      targetTabId: state.targetTabId,
      scrollIssuedTabId: targetTabId,
      preparedTabId: '',
      minimumRectGeneration: Math.max(0, Math.floor(currentRectGeneration)) + 1,
      previewRectByTabId: state.previewRectByTabId,
      previewRectGenerationByTabId: state.previewRectGenerationByTabId,
      previewRectGeneration: state.previewRectGeneration
    };
  }

  clearPreviewRectCache(
    state: BrowserTabsFloatingEntryTargetPreparationState
  ): BrowserTabsFloatingEntryTargetPreparationState {
    return {
      version: state.version,
      targetTabId: state.targetTabId,
      scrollIssuedTabId: state.scrollIssuedTabId,
      preparedTabId: state.preparedTabId,
      minimumRectGeneration: state.minimumRectGeneration,
      previewRectByTabId: {},
      previewRectGenerationByTabId: {},
      previewRectGeneration: 0
    };
  }

  discardPreviewRect(
    state: BrowserTabsFloatingEntryTargetPreparationState,
    tabId: string
  ): BrowserTabsFloatingEntryTargetPreparationState {
    const targetTabId = tabId.trim();
    if (targetTabId.length <= 0) {
      return state;
    }
    state.previewRectByTabId[targetTabId] = undefined;
    state.previewRectGenerationByTabId[targetTabId] = 0;
    return state;
  }

  resolveCurrentRectGeneration(state: BrowserTabsFloatingEntryTargetPreparationState): number {
    return Math.max(0, Math.floor(state.previewRectGeneration));
  }

  recordPreviewRect(
    state: BrowserTabsFloatingEntryTargetPreparationState,
    tabId: string,
    rect: BrowserTabsOverlayRect
  ): BrowserTabsFloatingEntryTargetRecordedRectResult {
    state.previewRectGeneration += 1;
    state.previewRectByTabId[tabId] = rect;
    state.previewRectGenerationByTabId[tabId] = state.previewRectGeneration;
    const measuredResult = this.resolveMeasuredRect({
      state: state,
      tabId: tabId,
      rect: rect,
      rectGeneration: state.previewRectGeneration
    });
    const shouldDefer = this.shouldDeferPreviewRect(state, tabId);
    return {
      state: state,
      rect: rect,
      measuredResult: measuredResult,
      shouldDefer: shouldDefer,
      shouldScheduleReady: shouldDefer && this.hasScrollIssued(state, tabId)
    };
  }

  resolveReadyAttempt(input: BrowserTabsFloatingEntryTargetReadyAttemptInput):
    BrowserTabsFloatingEntryTargetReadyAttemptResult {
    if (input.version !== input.state.version ||
      input.tabId !== input.targetTabId ||
      input.state.preparedTabId === input.tabId ||
      !this.isCurrentPendingTarget(input.state, input.tabId)) {
      return {
        state: input.state,
        action: 'ignore',
        nextAttempt: input.attempt
      };
    }
    const rect = input.state.previewRectByTabId[input.tabId];
    const measuredResult = this.resolveMeasuredRect({
      state: input.state,
      tabId: input.tabId,
      rect: rect,
      rectGeneration: input.state.previewRectGenerationByTabId[input.tabId] ?? 0
    });
    if (measuredResult.ready && rect !== undefined && this.isUsableRect(rect)) {
      return {
        state: measuredResult.state,
        action: 'publish',
        rect: rect,
        nextAttempt: input.attempt
      };
    }
    const predictedRect = input.predictedRect;
    const predictedResult = this.resolvePredictedRect(input.state, input.tabId, predictedRect);
    if (predictedResult.ready && predictedRect !== undefined && this.isUsableRect(predictedRect)) {
      return {
        state: predictedResult.state,
        action: 'publish',
        rect: predictedRect,
        nextAttempt: input.attempt
      };
    }
    if (input.attempt < input.maxAttempts) {
      return {
        state: input.state,
        action: 'retry',
        nextAttempt: input.attempt + 1
      };
    }
    return {
      state: input.state,
      action: 'ignore',
      nextAttempt: input.attempt
    };
  }

  shouldDeferPreviewRect(state: BrowserTabsFloatingEntryTargetPreparationState, tabId: string): boolean {
    const targetTabId = tabId.trim();
    return targetTabId.length > 0 &&
      state.targetTabId === targetTabId &&
      state.preparedTabId !== targetTabId;
  }

  hasScrollIssued(state: BrowserTabsFloatingEntryTargetPreparationState, tabId: string): boolean {
    const targetTabId = tabId.trim();
    return targetTabId.length > 0 &&
      state.targetTabId === targetTabId &&
      state.scrollIssuedTabId === targetTabId;
  }

  resolveMeasuredRect(input: BrowserTabsFloatingEntryTargetMeasuredRectInput):
    BrowserTabsFloatingEntryTargetResolvedRectResult {
    if (!this.isCurrentPendingTarget(input.state, input.tabId) ||
      input.state.scrollIssuedTabId !== input.tabId ||
      input.rectGeneration < input.state.minimumRectGeneration ||
      !this.isUsableRect(input.rect)) {
      return {
        state: input.state,
        ready: false
      };
    }
    return {
      state: this.markPrepared(input.state, input.tabId),
      ready: true
    };
  }

  resolvePredictedRect(
    state: BrowserTabsFloatingEntryTargetPreparationState,
    tabId: string,
    rect: BrowserTabsOverlayRect | undefined
  ): BrowserTabsFloatingEntryTargetResolvedRectResult {
    if (!this.isCurrentPendingTarget(state, tabId) ||
      state.scrollIssuedTabId !== tabId ||
      !this.isUsableRect(rect)) {
      return {
        state: state,
        ready: false
      };
    }
    return {
      state: this.markPrepared(state, tabId),
      ready: true
    };
  }

  resolvePredictedCenteredPreviewRect(input: BrowserTabsFloatingEntryTargetRectInput):
    BrowserTabsOverlayRect | undefined {
    const index = input.tabIds.indexOf(input.tabId);
    if (index < 0) {
      return undefined;
    }
    const columnCount = Math.max(1, Math.floor(input.columnCount));
    const column = index % columnCount;
    const row = Math.floor(index / columnCount);
    const slotCount = Math.max(input.tabIds.length, Math.floor(input.slotCount));
    const rowCount = Math.max(1, Math.ceil(slotCount / columnCount));
    const gridGap = Math.max(0, input.gridGap);
    const itemHeight = Math.max(1, input.itemHeight);
    const rowStride = itemHeight + gridGap;
    const topPadding = Math.max(0, input.topPadding);
    const bottomPadding = Math.max(0, input.bottomPadding);
    const contentHeight = Math.max(1, topPadding) +
      (rowCount * itemHeight) +
      (Math.max(0, rowCount - 1) * gridGap) +
      bottomPadding;
    const viewportHeight = Math.max(1, input.viewportHeight);
    const availableHeight = Math.max(1, viewportHeight - topPadding - bottomPadding);
    const itemTopInContent = topPadding + (row * rowStride);
    const centeredOffset = itemTopInContent - topPadding -
      Math.max(0, (availableHeight - itemHeight) / 2);
    const maxOffset = Math.max(0, contentHeight - viewportHeight);
    const scrollOffset = Math.max(0, Math.min(maxOffset, centeredOffset));
    return {
      left: input.viewportLeft + Math.max(0, input.horizontalPadding) +
        (column * (Math.max(1, input.cardWidth) + gridGap)),
      top: input.viewportTop + itemTopInContent + Math.max(0, input.previewTopInset) - scrollOffset,
      width: Math.max(1, input.cardWidth),
      height: Math.max(1, input.previewHeight)
    };
  }

  private isCurrentPendingTarget(state: BrowserTabsFloatingEntryTargetPreparationState, tabId: string): boolean {
    const targetTabId = tabId.trim();
    return targetTabId.length > 0 &&
      state.targetTabId === targetTabId &&
      state.preparedTabId !== targetTabId;
  }

  private markPrepared(
    state: BrowserTabsFloatingEntryTargetPreparationState,
    tabId: string
  ): BrowserTabsFloatingEntryTargetPreparationState {
    return {
      version: state.version,
      targetTabId: state.targetTabId,
      scrollIssuedTabId: state.scrollIssuedTabId,
      preparedTabId: tabId,
      minimumRectGeneration: state.minimumRectGeneration,
      previewRectByTabId: state.previewRectByTabId,
      previewRectGenerationByTabId: state.previewRectGenerationByTabId,
      previewRectGeneration: state.previewRectGeneration
    };
  }

  private isUsableRect(rect: BrowserTabsOverlayRect | undefined): boolean {
    return rect !== undefined && rect.width > 0 && rect.height > 0;
  }
}
