export interface BrowserSearchBackdropPresentation {
  runId: number;
  progress: number;
  durationMs: number;
  curve: Curve | string | ICurve;
  settleRunId: number;
  surfaceSuppressed: boolean;
}

export type BrowserSearchBackdropPresentationListener =
  (presentation: BrowserSearchBackdropPresentation) => void;
export type BrowserSearchBackdropSettleFinishHandler = (settleRunId: number) => void;

export class BrowserSearchBackdropPresentationChannel {
  private presentation?: BrowserSearchBackdropPresentation = undefined;
  private listener?: BrowserSearchBackdropPresentationListener = undefined;
  private nextRunId: number = 0;
  private readonly finishSettle: BrowserSearchBackdropSettleFinishHandler;

  constructor(finishSettle: BrowserSearchBackdropSettleFinishHandler) {
    this.finishSettle = finishSettle;
  }

  publish(
    progress: number,
    durationMs: number,
    curve: Curve | string | ICurve,
    settleRunId: number = 0
  ): void {
    this.commitPresentation(progress, durationMs, curve, settleRunId, false);
  }

  publishRouteTransitionSuppression(): void {
    this.commitPresentation(0, 0, Curve.Linear, 0, true);
  }

  private commitPresentation(
    progress: number,
    durationMs: number,
    curve: Curve | string | ICurve,
    settleRunId: number,
    surfaceSuppressed: boolean
  ): void {
    const presentation: BrowserSearchBackdropPresentation = {
      runId: ++this.nextRunId,
      progress: this.clampProgress(progress),
      durationMs: Math.max(0, Math.round(durationMs)),
      curve: curve,
      settleRunId: settleRunId,
      surfaceSuppressed: surfaceSuppressed
    };
    this.presentation = presentation;
    if (this.listener !== undefined) {
      this.listener(presentation);
      return;
    }
    this.finishPresentation(presentation.runId);
  }

  current(): BrowserSearchBackdropPresentation | undefined {
    return this.presentation;
  }

  connect(listener: BrowserSearchBackdropPresentationListener): () => boolean {
    this.listener = listener;
    if (this.presentation !== undefined) {
      listener({
        runId: this.presentation.runId,
        progress: this.presentation.progress,
        durationMs: 0,
        curve: this.presentation.curve,
        settleRunId: this.presentation.settleRunId,
        surfaceSuppressed: this.presentation.surfaceSuppressed
      });
    }
    return (): boolean => {
      if (this.listener !== listener) {
        return false;
      }
      this.listener = undefined;
      if (this.presentation !== undefined) {
        this.finishPresentation(this.presentation.runId);
      }
      return true;
    };
  }

  isRunCurrent(runId: number): boolean {
    return this.presentation !== undefined && this.presentation.runId === runId;
  }

  finishPresentation(runId: number): boolean {
    if (!this.isRunCurrent(runId) || this.presentation === undefined || this.presentation.settleRunId <= 0) {
      return false;
    }
    const settleRunId = this.presentation.settleRunId;
    this.presentation.settleRunId = 0;
    this.finishSettle(settleRunId);
    return true;
  }

  private clampProgress(progress: number): number {
    if (!Number.isFinite(progress)) {
      return 0;
    }
    return Math.max(0, Math.min(1, progress));
  }
}
