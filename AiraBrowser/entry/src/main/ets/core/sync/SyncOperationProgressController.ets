import {
  SYNC_OPERATION_PROGRESS_TIMING,
  SyncOperationProgressTipsState,
  SyncOperationProgressViewModel
} from './SyncOperationProgressViewModel';

export interface SyncOperationProgressUiState {
  title: string;
  subtitle: string;
  progress: number;
  inProgress: boolean;
  details: string;
  detailOpacity: number;
}

export class SyncOperationProgressController {
  private applyProgressState: (state: SyncOperationProgressUiState) => void;
  private isProgressDialogOpen: () => boolean;
  private openProgressDialog: () => void;
  private closeProgressDialog: () => void;
  private showResultDialog: (title: string, subtitle: string) => void;
  private progressViewModel: SyncOperationProgressViewModel = new SyncOperationProgressViewModel();
  private tipTimer: number = -1;
  private visualTimer: number = -1;
  private completionTimer: number = -1;
  private finishTimer: number = -1;
  private startTime: number = 0;
  private targetProgress: number = SYNC_OPERATION_PROGRESS_TIMING.inProgressTarget;
  private tipsState: SyncOperationProgressTipsState = { tips: [], index: 0, activeTip: '' };
  private state: SyncOperationProgressUiState = {
    title: '',
    subtitle: '',
    progress: 0,
    inProgress: false,
    details: '',
    detailOpacity: 1
  };

  constructor(
    applyProgressState: (state: SyncOperationProgressUiState) => void,
    isProgressDialogOpen: () => boolean,
    openProgressDialog: () => void,
    closeProgressDialog: () => void,
    showResultDialog: (title: string, subtitle: string) => void
  ) {
    this.applyProgressState = applyProgressState;
    this.isProgressDialogOpen = isProgressDialogOpen;
    this.openProgressDialog = openProgressDialog;
    this.closeProgressDialog = closeProgressDialog;
    this.showResultDialog = showResultDialog;
  }

  begin(title: string, subtitle: string): void {
    this.stopTimers();
    this.targetProgress = SYNC_OPERATION_PROGRESS_TIMING.inProgressTarget;
    this.startTime = Date.now();
    this.applyState({
      title: title,
      subtitle: subtitle,
      progress: 0,
      inProgress: true,
      details: subtitle,
      detailOpacity: 1
    });
    this.beginTips(title, subtitle);
    this.startVisualTimer();
    this.openProgressDialog();
  }

  update(title: string, subtitle: string, progress: number): void {
    if (!this.isProgressDialogOpen()) {
      return;
    }
    this.targetProgress = Math.max(this.targetProgress, progress);
    this.tipsState = this.progressViewModel.appendTip(this.tipsState, subtitle);
    this.applyState({
      title: title,
      subtitle: subtitle,
      progress: this.state.progress,
      inProgress: this.state.inProgress,
      details: this.state.details,
      detailOpacity: this.state.detailOpacity
    });
    this.showTip(subtitle);
  }

  finish(title: string, subtitle: string, onComplete?: () => void, showResultDialog: boolean = true): void {
    if (!this.isProgressDialogOpen()) {
      if (showResultDialog) {
        this.showResultDialog(title, subtitle);
      }
      if (onComplete !== undefined) {
        onComplete();
      }
      return;
    }
    this.stopActiveTimers();
    const finishingTip = this.resolveFinishingTip(this.state.title);
    this.applyState({
      title: this.state.title,
      subtitle: finishingTip,
      progress: this.state.progress,
      inProgress: this.state.inProgress,
      details: this.state.details,
      detailOpacity: this.state.detailOpacity
    });
    this.showTip(finishingTip);
    this.completionTimer = setInterval(() => {
      const nextProgress = Math.min(100, this.state.progress + 4);
      this.applyState({
        title: this.state.title,
        subtitle: this.state.subtitle,
        progress: nextProgress,
        inProgress: this.state.inProgress,
        details: this.state.details,
        detailOpacity: this.state.detailOpacity
      });
      if (nextProgress < 100) {
        return;
      }
      if (this.completionTimer >= 0) {
        clearInterval(this.completionTimer);
        this.completionTimer = -1;
      }
      this.applyState({
        title: title,
        subtitle: subtitle,
        progress: this.state.progress,
        inProgress: false,
        details: this.state.details,
        detailOpacity: this.state.detailOpacity
      });
      this.showTip(subtitle);
      this.finishTimer = setTimeout(() => {
        this.complete();
        if (showResultDialog) {
          this.showResultDialog(title, subtitle);
        }
        if (onComplete !== undefined) {
          onComplete();
        }
      }, SYNC_OPERATION_PROGRESS_TIMING.successVisibleMs);
    }, SYNC_OPERATION_PROGRESS_TIMING.finishIntervalMs);
  }

  complete(): void {
    this.applyState({
      title: this.state.title,
      subtitle: this.state.subtitle,
      progress: this.state.progress,
      inProgress: false,
      details: this.state.details,
      detailOpacity: this.state.detailOpacity
    });
    this.stopTimers();
    this.closeProgressDialog();
  }

  dispose(): void {
    this.stopTimers();
    this.closeProgressDialog();
  }

  private beginTips(title: string, firstTip: string): void {
    this.tipsState = this.progressViewModel.buildInitialTips(title, firstTip);
    this.showTip(this.tipsState.activeTip);
    this.tipTimer = setInterval(() => {
      this.advanceTip();
    }, SYNC_OPERATION_PROGRESS_TIMING.tipIntervalMs);
  }

  private advanceTip(): void {
    if (!this.state.inProgress || this.tipsState.tips.length === 0) {
      return;
    }
    this.tipsState = this.progressViewModel.advanceTip(this.tipsState);
    this.showTip(this.tipsState.activeTip);
  }

  private showTip(tip: string): void {
    this.applyState({
      title: this.state.title,
      subtitle: this.state.subtitle,
      progress: this.state.progress,
      inProgress: this.state.inProgress,
      details: this.state.details,
      detailOpacity: 0.22
    });
    setTimeout(() => {
      this.applyState({
        title: this.state.title,
        subtitle: this.state.subtitle,
        progress: this.state.progress,
        inProgress: this.state.inProgress,
        details: tip,
        detailOpacity: 1
      });
    }, 80);
  }

  private startVisualTimer(): void {
    this.visualTimer = setInterval(() => {
      if (!this.state.inProgress) {
        return;
      }
      const nextProgress = this.progressViewModel.resolveVisualProgress(
        this.state.progress,
        this.targetProgress,
        Date.now() - this.startTime
      );
      this.applyState({
        title: this.state.title,
        subtitle: this.state.subtitle,
        progress: nextProgress,
        inProgress: this.state.inProgress,
        details: this.state.details,
        detailOpacity: this.state.detailOpacity
      });
    }, SYNC_OPERATION_PROGRESS_TIMING.visualIntervalMs);
  }

  private stopActiveTimers(): void {
    if (this.tipTimer >= 0) {
      clearInterval(this.tipTimer);
      this.tipTimer = -1;
    }
    if (this.visualTimer >= 0) {
      clearInterval(this.visualTimer);
      this.visualTimer = -1;
    }
  }

  private stopTimers(): void {
    this.stopActiveTimers();
    if (this.completionTimer >= 0) {
      clearInterval(this.completionTimer);
      this.completionTimer = -1;
    }
    if (this.finishTimer >= 0) {
      clearTimeout(this.finishTimer);
      this.finishTimer = -1;
    }
  }

  private applyState(state: SyncOperationProgressUiState): void {
    this.state = state;
    this.applyProgressState(state);
  }

  private resolveFinishingTip(title: string): string {
    if (title.indexOf('导入') >= 0) {
      return '正在完成导入';
    }
    if (title.indexOf('导出') >= 0) {
      return '正在完成导出';
    }
    if (title.indexOf('同步') >= 0) {
      return '正在完成同步';
    }
    return '正在完成处理';
  }
}
