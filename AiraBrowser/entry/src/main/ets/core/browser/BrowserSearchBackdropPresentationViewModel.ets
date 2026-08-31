import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';
import {
  BROWSER_SEARCH_BACKDROP_FULL_PROGRESS_DISTANCE
} from './BrowserBottomPanelMotionTokens';

export interface BrowserSearchBackdropPresentationState {
  scale: number;
}

export interface BrowserSearchBackdropProgressInput {
  panelHeight: number;
  lowHeight: number;
  expandedHeight: number;
  direction?: BrowserSearchBackdropProgressDirection;
}

export interface BrowserSearchBackdropGestureProgressInput {
  startProgress: number;
  offsetY: number;
}

export interface BrowserSearchBackdropDetentStartProgressInput {
  detent: HomeSearchPanelDetent;
  currentProgress: number;
}

export interface BrowserSearchBackdropSettleDurationInput {
  currentProgress: number;
  targetProgress: number;
  maxDurationMs?: number;
  minDurationMs?: number;
}

export interface BrowserSearchBackdropDirectToneInput {
  surfaceEligible: boolean;
  progress: number;
}

export interface BrowserSearchBackdropSettlePlan {
  runId: number;
  targetProgress: number;
  durationMs: number;
}

export type BrowserSearchBackdropProgressDirection = 'opening' | 'closing' | 'idle';

const SEARCH_BACKDROP_EXPANDED_SCALE: number = 0.92;
const SEARCH_BACKDROP_SETTLE_MAX_DURATION_MS: number = 220;
const SEARCH_BACKDROP_SETTLE_MIN_DURATION_MS: number = 72;

export class BrowserSearchBackdropPresentationViewModel {
  private expandedHeight: number = 0;
  private previousPanelHeight: number = -1;
  private gestureStartProgress: number = 0;
  private gestureOffsetActive: boolean = false;
  private gestureSuppressed: boolean = false;
  private settleRunId: number = 0;

  buildState(progress: number): BrowserSearchBackdropPresentationState {
    const safeProgress = this.clampProgress(progress);
    return {
      scale: 1 - (1 - SEARCH_BACKDROP_EXPANDED_SCALE) * safeProgress
    };
  }

  resolveProgress(input: BrowserSearchBackdropProgressInput): number {
    const effectDistance = Math.max(
      1,
      Math.min(
        BROWSER_SEARCH_BACKDROP_FULL_PROGRESS_DISTANCE,
        input.expandedHeight - input.lowHeight
      )
    );
    if (input.direction === 'closing') {
      const clearStartHeight = input.expandedHeight - effectDistance;
      return this.clampProgress((input.panelHeight - clearStartHeight) / effectDistance);
    }
    return this.clampProgress((input.panelHeight - input.lowHeight) / effectDistance);
  }

  resolveProgressDirection(previousPanelHeight: number, panelHeight: number): BrowserSearchBackdropProgressDirection {
    if (!Number.isFinite(previousPanelHeight) || previousPanelHeight < 0) {
      return 'idle';
    }
    if (panelHeight < previousPanelHeight - 0.5) {
      return 'closing';
    }
    if (panelHeight > previousPanelHeight + 0.5) {
      return 'opening';
    }
    return 'idle';
  }

  resolveEffectiveProgress(
    progress: number,
    tabsSheetVisible: boolean,
    bottomPanelHostVisible: boolean = true
  ): number {
    if (tabsSheetVisible || !bottomPanelHostVisible) {
      return 0;
    }
    return this.clampProgress(progress);
  }

  resolveDetentProgress(detent: HomeSearchPanelDetent): number {
    return detent === 'middle' ? 1 : 0;
  }

  shouldUseDirectToneEffect(input: BrowserSearchBackdropDirectToneInput): boolean {
    return input.surfaceEligible && this.clampProgress(input.progress) > 0.01;
  }

  clearExpandedHeight(): void {
    this.expandedHeight = 0;
  }

  beginPanelDrag(
    panelHeight: number,
    targetHeight: number,
    lowHeight: number,
    expansionEnabled: boolean
  ): number | undefined {
    if (!expansionEnabled) {
      return undefined;
    }
    this.expandedHeight = Math.max(panelHeight, lowHeight, targetHeight);
    return this.resolvePanelHeightProgress(panelHeight, targetHeight, lowHeight, expansionEnabled);
  }

  updatePanelDrag(
    panelHeight: number,
    lowHeight: number,
    expansionEnabled: boolean
  ): number | undefined {
    return this.resolvePanelHeightProgress(
      panelHeight,
      this.expandedHeight,
      lowHeight,
      expansionEnabled
    );
  }

  updatePanelVisualHeight(
    panelHeight: number,
    expandedHeight: number,
    lowHeight: number,
    expansionEnabled: boolean
  ): number | undefined {
    return this.resolvePanelHeightProgress(
      panelHeight,
      expandedHeight,
      lowHeight,
      expansionEnabled
    );
  }

  resetInteraction(): number {
    this.settleRunId += 1;
    this.previousPanelHeight = -1;
    this.gestureStartProgress = 0;
    this.gestureOffsetActive = false;
    this.gestureSuppressed = false;
    return 0;
  }

  beginGesture(detent: HomeSearchPanelDetent, currentProgress: number): void {
    this.settleRunId += 1;
    this.gestureSuppressed = false;
    this.gestureStartProgress = this.resolveDetentStartProgress({
      detent: detent,
      currentProgress: currentProgress
    });
  }

  updateGesture(
    suppressSearchBackdrop: boolean,
    offsetY: number,
    expansionEnabled: boolean
  ): number | undefined {
    this.gestureSuppressed = suppressSearchBackdrop;
    if (suppressSearchBackdrop) {
      this.gestureOffsetActive = true;
      this.previousPanelHeight = -1;
      return 0;
    }
    if (!expansionEnabled) {
      return undefined;
    }
    this.settleRunId += 1;
    this.gestureOffsetActive = true;
    this.previousPanelHeight = -1;
    return this.resolveGestureOffsetProgress({
      startProgress: this.gestureStartProgress,
      offsetY: offsetY
    });
  }

  beginFocusTransition(detent: HomeSearchPanelDetent, currentProgress: number): number {
    this.settleRunId += 1;
    const startProgress = this.resolveDetentStartProgress({
      detent: detent,
      currentProgress: currentProgress
    });
    this.gestureStartProgress = startProgress;
    this.gestureOffsetActive = true;
    this.gestureSuppressed = false;
    this.previousPanelHeight = -1;
    return startProgress;
  }

  prepareDetentSettle(
    detent: HomeSearchPanelDetent,
    currentProgress: number
  ): BrowserSearchBackdropSettlePlan {
    if (this.gestureSuppressed) {
      const targetProgress = this.resetInteraction();
      return {
        runId: this.settleRunId,
        targetProgress: targetProgress,
        durationMs: 0
      };
    }
    return this.prepareProgressSettle(
      currentProgress,
      this.resolveDetentProgress(detent)
    );
  }

  prepareProgressSettle(
    currentProgress: number,
    targetProgress: number,
    maxDurationMs?: number
  ): BrowserSearchBackdropSettlePlan {
    const durationMs = this.resolveSettleDurationMs({
      currentProgress: currentProgress,
      targetProgress: targetProgress,
      maxDurationMs: maxDurationMs
    });
    const runId = ++this.settleRunId;
    this.gestureOffsetActive = true;
    this.previousPanelHeight = -1;
    return {
      runId: runId,
      targetProgress: targetProgress,
      durationMs: durationMs
    };
  }

  isSettleRunCurrent(runId: number): boolean {
    return this.settleRunId === runId;
  }

  finishSettle(runId: number): boolean {
    if (!this.isSettleRunCurrent(runId)) {
      return false;
    }
    this.gestureOffsetActive = false;
    this.previousPanelHeight = -1;
    return true;
  }

  resolveDetentStartProgress(input: BrowserSearchBackdropDetentStartProgressInput): number {
    if (input.detent === 'middle') {
      return 1;
    }
    return this.clampProgress(input.currentProgress);
  }

  resolveGestureOffsetProgress(input: BrowserSearchBackdropGestureProgressInput): number {
    if (!Number.isFinite(input.offsetY)) {
      return this.clampProgress(input.startProgress);
    }
    return this.clampProgress(
      input.startProgress - input.offsetY / BROWSER_SEARCH_BACKDROP_FULL_PROGRESS_DISTANCE
    );
  }

  resolveSettleDurationMs(input: BrowserSearchBackdropSettleDurationInput): number {
    const distance = Math.abs(this.clampProgress(input.targetProgress) - this.clampProgress(input.currentProgress));
    if (distance <= 0.001) {
      return 0;
    }
    const maxDurationMs = this.resolveDurationLimit(input.maxDurationMs, SEARCH_BACKDROP_SETTLE_MAX_DURATION_MS);
    const minDurationMs = Math.min(
      maxDurationMs,
      this.resolveDurationLimit(input.minDurationMs, SEARCH_BACKDROP_SETTLE_MIN_DURATION_MS)
    );
    return Math.max(
      minDurationMs,
      Math.round(maxDurationMs * distance)
    );
  }

  private clampProgress(progress: number): number {
    if (!Number.isFinite(progress)) {
      return 0;
    }
    return Math.max(0, Math.min(1, progress));
  }

  private resolveDurationLimit(value: number | undefined, fallback: number): number {
    if (value === undefined || !Number.isFinite(value)) {
      return fallback;
    }
    return Math.max(0, Math.round(value));
  }

  private resolvePanelHeightProgress(
    panelHeight: number,
    targetHeight: number,
    lowHeight: number,
    expansionEnabled: boolean
  ): number | undefined {
    if (!expansionEnabled) {
      return undefined;
    }
    if (this.gestureSuppressed) {
      return 0;
    }
    const targetExpandedHeight = Math.max(targetHeight, this.expandedHeight);
    const expandedHeight = Math.max(panelHeight, lowHeight, targetExpandedHeight);
    if (this.gestureOffsetActive) {
      return undefined;
    }
    const direction = this.resolveProgressDirection(this.previousPanelHeight, panelHeight);
    const progress = this.resolveProgress({
      panelHeight: panelHeight,
      lowHeight: lowHeight,
      expandedHeight: expandedHeight,
      direction: direction
    });
    this.previousPanelHeight = panelHeight;
    return progress;
  }
}
