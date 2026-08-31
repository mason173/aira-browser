import { DownloadV2TaskEntity } from '../../domain/downloadv2/DownloadV2TaskEntity';

export class DownloadToolbarIndicatorState {
  visible: boolean;
  progressValue: number;
  progressKnown: boolean;
  activeTaskCount: number;

  constructor(
    visible: boolean,
    progressValue: number,
    progressKnown: boolean,
    activeTaskCount: number
  ) {
    this.visible = visible;
    this.progressValue = progressValue;
    this.progressKnown = progressKnown;
    this.activeTaskCount = activeTaskCount;
  }

  accessibilityText(): string {
    if (!this.visible) {
      return '';
    }
    if (!this.progressKnown) {
      return this.activeTaskCount > 1 ? `正在下载 ${this.activeTaskCount} 个任务，进度未知` : '正在下载，进度未知';
    }
    return this.activeTaskCount > 1 ?
      `正在下载 ${this.activeTaskCount} 个任务，${this.progressValue}%` :
      `正在下载，${this.progressValue}%`;
  }
}

export function createHiddenDownloadToolbarIndicatorState(): DownloadToolbarIndicatorState {
  return new DownloadToolbarIndicatorState(false, 0, false, 0);
}

export class DownloadToolbarIndicatorViewModel {
  buildState(tasks: DownloadV2TaskEntity[]): DownloadToolbarIndicatorState {
    const activeTasks = tasks.filter((task: DownloadV2TaskEntity): boolean => task.status === 'running');
    if (activeTasks.length === 0) {
      return createHiddenDownloadToolbarIndicatorState();
    }

    let knownTotalBytes = 0;
    let knownReceivedBytes = 0;
    activeTasks.forEach((task: DownloadV2TaskEntity): void => {
      const totalBytes = this.normalizeByteCount(task.progress.totalBytes);
      if (totalBytes <= 0) {
        return;
      }
      knownTotalBytes += totalBytes;
      knownReceivedBytes += Math.min(totalBytes, this.normalizeByteCount(task.progress.receivedBytes));
    });

    const progressKnown = knownTotalBytes > 0;
    const progressValue = progressKnown ?
      Math.min(99, Math.max(0, Math.floor(knownReceivedBytes * 100 / knownTotalBytes))) : 0;
    return new DownloadToolbarIndicatorState(true, progressValue, progressKnown, activeTasks.length);
  }

  private normalizeByteCount(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return value;
  }
}
