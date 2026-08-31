import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { DownloadV2TaskEntity } from '../../domain/downloadv2/DownloadV2TaskEntity';
import { DownloadV2Status, isDownloadV2TerminalStatus } from '../../domain/downloadv2/DownloadV2Types';

const DOMAIN = 0x0000;
const TAG = 'DownloadV2SystemNotify';
const DOWNLOAD_PROGRESS_NOTIFICATION_ID: number = 240000;
const DOWNLOAD_TERMINAL_NOTIFICATION_ID_BASE: number = 340000;
const DOWNLOAD_TERMINAL_NOTIFICATION_ID_RANGE: number = 100000;
const DOWNLOAD_FAILURE_NOTIFICATION_OFFSET: number = 100000;
const DOWNLOAD_WANT_REQUEST_CODE: number = 240000;
const MIN_PROGRESS_NOTIFICATION_INTERVAL_MS: number = 800;
const MIN_PROGRESS_PERCENT_DELTA: number = 1;
const NOTIFICATION_DISABLED_CODE: number = 1600004;
const NOTIFICATION_NOT_FOUND_CODE: number = 1600007;
const NOTIFICATION_NOT_ALLOWED_CODE: number = 1600020;

interface DownloadV2BackgroundNotificationState {
  context: common.UIAbilityContext;
  notificationId: number;
  continuousTaskId?: number;
  systemProxyActive: boolean;
  progressPublished: boolean;
  lastProgressPercent: number;
  lastProgressAt: number;
}

interface DownloadV2AggregateProgress {
  taskCount: number;
  primaryTask: DownloadV2TaskEntity;
  totalBytes: number;
  receivedBytes: number;
  progressPercent: number;
  progressDeterminate: boolean;
}

export class DownloadV2SystemNotificationService {
  private runningTasksByGuid: Record<string, DownloadV2TaskEntity | undefined> = {};
  private terminalNotificationQueue: DownloadV2TaskEntity[] = [];
  private backgroundState?: DownloadV2BackgroundNotificationState;
  private notificationPermissionRequested: boolean = false;
  private downloadTemplateSupported?: boolean;
  private reconcileRequested: boolean = false;
  private reconcileRunning: boolean = false;

  handleTaskChanged(task: DownloadV2TaskEntity, previousStatus?: DownloadV2Status): void {
    if (task.privacyMode === 'private') {
      this.runningTasksByGuid[task.guid] = undefined;
      this.requestReconcile();
      return;
    }
    this.runningTasksByGuid[task.guid] = task.status === 'running' ? task : undefined;
    if (isDownloadV2TerminalStatus(task.status) && task.status !== previousStatus &&
      (task.status === 'completed' || task.status === 'failed')) {
      this.terminalNotificationQueue.push(task);
    }
    this.requestReconcile();
  }

  handleTaskRemoved(guid: string): void {
    this.runningTasksByGuid[guid.trim()] = undefined;
    this.requestReconcile();
  }

  private requestReconcile(): void {
    this.reconcileRequested = true;
    if (this.reconcileRunning) {
      return;
    }
    this.reconcileRunning = true;
    void this.runReconcileLoop();
  }

  private async runReconcileLoop(): Promise<void> {
    try {
      while (this.reconcileRequested) {
        this.reconcileRequested = false;
        await this.reconcile();
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'background download reconcile failed error=%{public}s', JSON.stringify(error));
    } finally {
      this.reconcileRunning = false;
      if (this.reconcileRequested) {
        this.requestReconcile();
      }
    }
  }

  private async reconcile(): Promise<void> {
    await this.publishQueuedTerminalNotifications();
    const runningTasks = this.listRunningTasks();
    if (runningTasks.length <= 0) {
      await this.stopBackgroundTask();
      return;
    }
    const state = await this.ensureBackgroundTask(runningTasks[0]);
    if (state === undefined) {
      return;
    }
    await this.publishProgressNotification(this.buildAggregateProgress(runningTasks), state);
  }

  private listRunningTasks(): DownloadV2TaskEntity[] {
    return Object.keys(this.runningTasksByGuid)
      .map((guid: string): DownloadV2TaskEntity | undefined => this.runningTasksByGuid[guid])
      .filter((task?: DownloadV2TaskEntity): boolean => task !== undefined) as DownloadV2TaskEntity[];
  }

  private async ensureBackgroundTask(
    representativeTask: DownloadV2TaskEntity
  ): Promise<DownloadV2BackgroundNotificationState | undefined> {
    if (this.backgroundState !== undefined) {
      return this.backgroundState;
    }
    if (!AppRuntimeContext.hasUIAbilityContext()) {
      hilog.warn(DOMAIN, TAG, 'background dataTransfer skipped because UIAbilityContext is unavailable');
      return undefined;
    }
    const context = AppRuntimeContext.getUIAbilityContext();
    await this.requestNotificationPermissionIfNeeded(context);
    const state: DownloadV2BackgroundNotificationState = {
      context: context,
      notificationId: DOWNLOAD_PROGRESS_NOTIFICATION_ID,
      systemProxyActive: false,
      progressPublished: false,
      lastProgressPercent: -1,
      lastProgressAt: 0
    };
    this.backgroundState = state;
    try {
      const result = await backgroundTaskManager.startBackgroundRunning(
        context,
        ['dataTransfer'],
        await this.createOpenDownloadsWantAgent(context)
      );
      state.notificationId = result.notificationId;
      state.continuousTaskId = result.continuousTaskId;
      state.systemProxyActive = true;
      hilog.info(
        DOMAIN,
        TAG,
        'background dataTransfer started guid=%{public}s notificationId=%{public}d taskId=%{public}d',
        representativeTask.guid,
        result.notificationId,
        result.continuousTaskId ?? -1
      );
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'background dataTransfer start failed guid=%{public}s code=%{public}d message=%{public}s',
        representativeTask.guid,
        Number(businessError?.code ?? 0),
        businessError?.message ?? ''
      );
    }
    return state;
  }

  private async stopBackgroundTask(): Promise<void> {
    const state = this.backgroundState;
    if (state === undefined) {
      return;
    }
    if (state.systemProxyActive) {
      try {
        if (state.continuousTaskId !== undefined && state.continuousTaskId >= 0) {
          await backgroundTaskManager.stopBackgroundRunning(state.context, state.continuousTaskId);
        } else {
          await backgroundTaskManager.stopBackgroundRunning(state.context);
        }
      } catch (error) {
        const businessError = error as BusinessError;
        hilog.warn(
          DOMAIN,
          TAG,
          'background dataTransfer stop failed code=%{public}d message=%{public}s',
          Number(businessError?.code ?? 0),
          businessError?.message ?? ''
        );
      }
    } else if (state.progressPublished) {
      try {
        await notificationManager.cancel(state.notificationId);
      } catch (_error) {
      }
    }
    this.backgroundState = undefined;
  }

  private async requestNotificationPermissionIfNeeded(context: common.UIAbilityContext): Promise<void> {
    if (this.notificationPermissionRequested) {
      return;
    }
    this.notificationPermissionRequested = true;
    try {
      if (!await notificationManager.isNotificationEnabled()) {
        await notificationManager.requestEnableNotification(context);
      }
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'notification permission request skipped code=%{public}d message=%{public}s',
        Number(businessError?.code ?? 0),
        businessError?.message ?? ''
      );
    }
  }

  private async publishProgressNotification(
    progress: DownloadV2AggregateProgress,
    state: DownloadV2BackgroundNotificationState
  ): Promise<void> {
    if (!this.canPublishNotification()) {
      return;
    }
    const now = Date.now();
    if (state.progressPublished &&
      Math.abs(progress.progressPercent - state.lastProgressPercent) < MIN_PROGRESS_PERCENT_DELTA &&
      now - state.lastProgressAt < MIN_PROGRESS_NOTIFICATION_INTERVAL_MS) {
      return;
    }
    const request = await this.buildProgressNotificationRequest(progress, state);
    try {
      await notificationManager.publish(request);
      state.progressPublished = true;
      state.lastProgressPercent = progress.progressPercent;
      state.lastProgressAt = now;
    } catch (error) {
      this.logNotificationFailure('publish progress', progress.primaryTask.guid, error as BusinessError);
    }
  }

  private async buildProgressNotificationRequest(
    progress: DownloadV2AggregateProgress,
    state: DownloadV2BackgroundNotificationState
  ): Promise<notificationManager.NotificationRequest> {
    const title = this.buildProgressTitle(progress);
    const fileName = progress.taskCount === 1
      ? this.resolveFileName(progress.primaryTask)
      : `${progress.taskCount} 个下载任务`;
    const additionalText = this.buildProgressAdditionalText(progress);
    const request: notificationManager.NotificationRequest = {
      id: state.notificationId,
      notificationSlotType: state.systemProxyActive
        ? notificationManager.SlotType.LIVE_VIEW
        : notificationManager.SlotType.CONTENT_INFORMATION,
      updateOnly: state.systemProxyActive || state.progressPublished,
      tapDismissed: false,
      isAlertOnce: true,
      wantAgent: await this.createOpenDownloadsWantAgent(state.context),
      content: state.systemProxyActive
        ? {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
          systemLiveView: {
            typeCode: 8,
            title: title,
            text: fileName,
            additionalText: additionalText,
            progress: {
              maxValue: 100,
              currentValue: progress.progressPercent,
              isPercentage: progress.progressDeterminate
            }
          }
        }
        : {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: fileName,
            additionalText: additionalText
          }
        }
    };
    if (await this.isDownloadTemplateSupported()) {
      request.template = {
        name: 'downloadTemplate',
        data: {
          title: '正在下载',
          fileName: fileName,
          progressValue: progress.progressPercent
        }
      };
    }
    return request;
  }

  private async publishQueuedTerminalNotifications(): Promise<void> {
    if (this.terminalNotificationQueue.length <= 0) {
      return;
    }
    const queued = this.terminalNotificationQueue.slice();
    this.terminalNotificationQueue = [];
    for (const task of queued) {
      await this.publishTerminalNotification(task);
    }
  }

  private async publishTerminalNotification(task: DownloadV2TaskEntity): Promise<void> {
    if (!this.canPublishNotification() || !AppRuntimeContext.hasUIAbilityContext()) {
      return;
    }
    const completed = task.status === 'completed';
    const request: notificationManager.NotificationRequest = {
      id: this.buildTerminalNotificationId(task.guid) + (completed ? 0 : DOWNLOAD_FAILURE_NOTIFICATION_OFFSET),
      notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
      wantAgent: await this.createOpenDownloadsWantAgent(AppRuntimeContext.getUIAbilityContext()),
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: completed ? '下载完成' : '下载失败',
          text: this.resolveFileName(task),
          additionalText: '点击查看下载'
        }
      }
    };
    try {
      await notificationManager.publish(request);
    } catch (error) {
      this.logNotificationFailure('publish terminal', task.guid, error as BusinessError);
    }
  }

  private buildAggregateProgress(tasks: DownloadV2TaskEntity[]): DownloadV2AggregateProgress {
    let primaryTask = tasks[0];
    let totalBytes = 0;
    let receivedBytes = 0;
    let progressDeterminate = true;
    tasks.forEach((task: DownloadV2TaskEntity): void => {
      if (task.timing.updatedAt > primaryTask.timing.updatedAt) {
        primaryTask = task;
      }
      if (task.progress.totalBytes <= 0) {
        progressDeterminate = false;
      } else {
        totalBytes += task.progress.totalBytes;
        receivedBytes += Math.min(task.progress.totalBytes, Math.max(0, task.progress.receivedBytes));
      }
    });
    const progressPercent = progressDeterminate && totalBytes > 0
      ? Math.min(100, Math.max(0, Math.floor((receivedBytes * 100) / totalBytes)))
      : 0;
    return {
      taskCount: tasks.length,
      primaryTask: primaryTask,
      totalBytes: totalBytes,
      receivedBytes: receivedBytes,
      progressPercent: progressPercent,
      progressDeterminate: progressDeterminate
    };
  }

  private buildProgressTitle(progress: DownloadV2AggregateProgress): string {
    const subject = progress.taskCount === 1 ? '正在下载' : `正在下载 ${progress.taskCount} 个文件`;
    return progress.progressDeterminate ? `${subject} ${progress.progressPercent}%` : subject;
  }

  private buildProgressAdditionalText(progress: DownloadV2AggregateProgress): string {
    if (!progress.progressDeterminate || progress.totalBytes <= 0) {
      return `${this.formatSize(progress.primaryTask.progress.receivedBytes)} · ${this.formatSpeed(progress.primaryTask)}`;
    }
    return `${this.formatSize(progress.receivedBytes)} / ${this.formatSize(progress.totalBytes)} · ` +
      this.formatSpeed(progress.primaryTask);
  }

  private formatSpeed(task: DownloadV2TaskEntity): string {
    const speed = Math.max(0, task.progress.speedBytesPerSecond);
    return speed > 0 ? `${this.formatSize(speed)}/s` : '准备中';
  }

  private resolveFileName(task: DownloadV2TaskEntity): string {
    const resolved = task.resolvedFileName?.trim() ?? '';
    return resolved.length > 0 ? resolved : task.suggestedFileName;
  }

  private formatSize(size: number): string {
    const normalizedSize = Math.max(0, size);
    if (normalizedSize < 1024) {
      return `${Math.floor(normalizedSize)} B`;
    }
    if (normalizedSize < 1024 * 1024) {
      return `${(normalizedSize / 1024).toFixed(1)} KB`;
    }
    if (normalizedSize < 1024 * 1024 * 1024) {
      return `${(normalizedSize / 1024 / 1024).toFixed(1)} MB`;
    }
    return `${(normalizedSize / 1024 / 1024 / 1024).toFixed(1)} GB`;
  }

  private async isDownloadTemplateSupported(): Promise<boolean> {
    if (this.downloadTemplateSupported !== undefined) {
      return this.downloadTemplateSupported;
    }
    try {
      this.downloadTemplateSupported = await notificationManager.isSupportTemplate('downloadTemplate');
    } catch (_error) {
      this.downloadTemplateSupported = false;
    }
    return this.downloadTemplateSupported;
  }

  private async createOpenDownloadsWantAgent(context: common.UIAbilityContext): Promise<WantAgent> {
    return wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
        parameters: {
          'aira.appShortcut': 'downloads'
        }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: DOWNLOAD_WANT_REQUEST_CODE,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }) as Promise<WantAgent>;
  }

  private buildTerminalNotificationId(guid: string): number {
    let hash = 0;
    for (let index = 0; index < guid.length; index += 1) {
      hash = ((hash * 31) + guid.charCodeAt(index)) >>> 0;
    }
    return DOWNLOAD_TERMINAL_NOTIFICATION_ID_BASE + (hash % DOWNLOAD_TERMINAL_NOTIFICATION_ID_RANGE);
  }

  private canPublishNotification(): boolean {
    try {
      return notificationManager.isNotificationEnabledSync();
    } catch (_error) {
      return false;
    }
  }

  private logNotificationFailure(action: string, guid: string, error: BusinessError): void {
    const code = Number(error?.code ?? 0);
    if (code === NOTIFICATION_DISABLED_CODE || code === NOTIFICATION_NOT_ALLOWED_CODE ||
      code === NOTIFICATION_NOT_FOUND_CODE) {
      return;
    }
    hilog.warn(
      DOMAIN,
      TAG,
      '%{public}s failed guid=%{public}s code=%{public}d message=%{public}s',
      action,
      guid,
      code,
      error?.message ?? ''
    );
  }
}
