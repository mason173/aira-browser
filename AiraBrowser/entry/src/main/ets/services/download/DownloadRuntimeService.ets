import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  DownloadQueryService,
  DownloadStatusCounts
} from '../../core/download/DownloadQueryService';
import {
  DownloadQueryGroup,
  DownloadTaskBoundary,
  matchesDownloadTaskBoundary
} from '../../domain/download/DownloadTypes';
import {
  PlatformDownloadDelegate,
  PlatformDownloadAdapter,
  PlatformDownloadEvent
} from '../../platform/download/PlatformDownloadAdapter';
import { ArkWebDownloadBridge } from '../../platform/download/ArkWebDownloadBridge';
import {
  DownloadFileResolutionAdapter,
  DownloadFileResolutionService
} from './DownloadFileResolutionService';
import { DownloadFollowupExecutionResult, DownloadFollowupService, DownloadFollowupTask } from './DownloadFollowupService';
import { DownloadPolicyService, DownloadSavePolicy, DownloadSessionCleanupPolicy } from './DownloadPolicyService';
import {
  DownloadV2CompletedFileRemovalResult,
  DownloadV2Service,
  DownloadV2TaskChangeKind
} from '../downloadv2/DownloadV2Service';
import { DownloadV2Prompt } from '../../features/downloadv2/DownloadV2CaptureTypes';
import {
  canContinueDownloadV2TaskFromPersistedData,
  DownloadV2TaskEntity
} from '../../domain/downloadv2/DownloadV2TaskEntity';
import {
  DownloadV2Action,
  DownloadV2ManagementAction,
  getDownloadV2ActionPermissionSet
} from '../../domain/downloadv2/DownloadV2Types';

const DOWNLOAD_RUNTIME_SERVICE_DOMAIN = 0x0000;
const DOWNLOAD_RUNTIME_SERVICE_TAG = 'DownloadRuntimeService';

interface DownloadV2FollowupTaskSnapshot {
  suggestedFileName: string;
  mimeType?: string;
  tempLocalPath?: string;
  finalFileUri?: string;
}

export interface PendingDownloadPromptState {
  guid: string;
  fileName: string;
  sourceHost: string;
  url: string;
  totalBytes: number;
  mimeType?: string;
  contentDisposition?: string;
  riskLevel: 'unknown' | 'safe' | 'warning' | 'danger' | 'blocked';
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel: string;
}

export interface ManualDownloadRequestInput {
  url: string;
  sourceHost?: string;
  suggestedFileName?: string;
  totalBytes?: number;
  userAgent?: string;
  referer?: string;
  mimeType?: string;
  contentDisposition?: string;
  headers?: Record<string, string>;
}

export interface ManualDownloadRequestResult {
  guid: string;
  prompt?: PendingDownloadPromptState;
  started: boolean;
}

export interface DownloadRuntimeServiceCallbacks {
  onTaskListChange?: (tasks: DownloadV2TaskEntity[]) => void;
  onInfo?: (message: string) => void;
  onError?: (message: string) => void;
  onPendingDownloadPromptChange?: (prompt?: PendingDownloadPromptState) => void;
  resolveCurrentPageUrl?: () => string;
  onPlatformDownloadEvent?: (event: PlatformDownloadEvent, boundary: DownloadTaskBoundary) => void;
}

interface DownloadRuntimeServiceCallbackListener {
  key: string;
  callbacks: DownloadRuntimeServiceCallbacks;
}
export type DownloadTaskFollowupAction = 'open_file' | 'open_location';

export class DownloadRuntimeService {
  private downloadBridge: PlatformDownloadAdapter;
  private downloadV2Service: DownloadV2Service;
  private isSyncingActiveDownloads: boolean = false;
  private queryService: DownloadQueryService = new DownloadQueryService();
  private fileResolutionService: DownloadFileResolutionAdapter;
  private downloadFollowupService: DownloadFollowupService;
  private downloadPolicyService: DownloadPolicyService;
  private initialized: boolean = false;
  private repositoryInitializationPromise?: Promise<void>;
  private callbacks: DownloadRuntimeServiceCallbacks = {};
  private callbackListeners: DownloadRuntimeServiceCallbackListener[] = [];
  private nextCallbackListenerId: number = 0;
  private taskListProgressBroadcastPauseOwners: string[] = [];
  private hasSuppressedTaskListProgressChange: boolean = false;
  private activeBoundary: DownloadTaskBoundary = {
    windowId: '',
    profileId: DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: 'regular',
    dataScope: 'profile_persistent'
  };

  constructor(
    downloadBridge: PlatformDownloadAdapter = new ArkWebDownloadBridge(),
    downloadPolicyService: DownloadPolicyService = new DownloadPolicyService(),
    downloadV2Service?: DownloadV2Service,
    fileResolutionService: DownloadFileResolutionAdapter = new DownloadFileResolutionService()
  ) {
    this.downloadBridge = downloadBridge;
    this.fileResolutionService = fileResolutionService;
    this.downloadFollowupService = new DownloadFollowupService(this.fileResolutionService);
    this.downloadPolicyService = downloadPolicyService;
    this.downloadV2Service = downloadV2Service ?? new DownloadV2Service(
      undefined,
      undefined,
      undefined,
      this.downloadBridge,
      this.fileResolutionService,
      downloadPolicyService
    );
    this.attachDownloadV2Service(this.downloadV2Service);
  }

  attachDownloadV2Service(downloadV2Service?: DownloadV2Service): void {
    if (downloadV2Service !== undefined) {
      this.downloadV2Service = downloadV2Service;
    }
    this.downloadV2Service.setCallbacks({
      onTaskChanged: (_task: DownloadV2TaskEntity, changeKind?: DownloadV2TaskChangeKind) => {
        this.emitTaskListChange(changeKind === 'progress' ? 'progress' : 'important');
      },
      onTaskRemoved: () => {
        this.emitTaskListChange('important');
      },
      onPromptChanged: () => {
        this.emitPendingDownloadPromptChange(this.getPendingDownloadPrompt());
      },
      onInfo: (message: string) => {
        this.emitInfo(message);
      },
      onError: (message: string) => {
        this.emitError(message);
      }
    });
    this.emitTaskListChange('important');
    this.emitPendingDownloadPromptChange(this.getPendingDownloadPrompt());
  }

  async initializeRepository(): Promise<void> {
    if (this.repositoryInitializationPromise !== undefined) {
      return this.repositoryInitializationPromise;
    }
    this.initialize();
    const initializationPromise = this.downloadV2Service.initialize()
      .then(() => {
        this.emitTaskListChange('important');
        this.emitPendingDownloadPromptChange(this.getPendingDownloadPrompt());
      })
      .catch((error: Error) => {
        this.repositoryInitializationPromise = undefined;
        throw error;
      });
    this.repositoryInitializationPromise = initializationPromise;
    return initializationPromise;
  }

  setCallbacks(callbacks: DownloadRuntimeServiceCallbacks): void {
    this.callbacks = callbacks;
    this.emitTaskListChange();
    this.emitPendingDownloadPromptChange(this.getPendingDownloadPrompt());
  }

  addCallbacksListener(callbacks: DownloadRuntimeServiceCallbacks): string {
    const key = `download-service-listener-${this.nextCallbackListenerId}`;
    this.nextCallbackListenerId += 1;
    this.callbackListeners = this.callbackListeners
      .filter((listener: DownloadRuntimeServiceCallbackListener) => listener.key !== key);
    this.callbackListeners.push({
      key: key,
      callbacks: callbacks
    });
    this.emitCallbacksToListener(callbacks);
    return key;
  }

  removeCallbacksListener(key: string): void {
    this.callbackListeners = this.callbackListeners
      .filter((listener: DownloadRuntimeServiceCallbackListener) => listener.key !== key);
  }

  getDelegate(): PlatformDownloadDelegate {
    this.initialize();
    return this.downloadBridge.getDelegate();
  }

  listAllowedActionsForTask(task: DownloadV2TaskEntity): DownloadV2ManagementAction[] {
    return this.resolveAllowedActionsForV2Task(task);
  }

  setActiveBoundary(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope?: BrowserDataScope,
    windowId: string = '',
    sourcePageUrl: string = ''
  ): void {
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(privacyMode);
    this.activeBoundary = {
      windowId: windowId,
      profileId: normalizeBrowserProfileId(profileId),
      privacyMode: normalizedPrivacyMode,
      dataScope: normalizeBrowserDataScope(dataScope, normalizedPrivacyMode),
      sourcePageUrl: sourcePageUrl.trim()
    };
  }

  listTasks(boundary?: DownloadTaskBoundary): DownloadV2TaskEntity[] {
    this.syncActiveDownloads();
    return this.listTasksSnapshot(boundary);
  }

  listTasksSnapshot(boundary?: DownloadTaskBoundary): DownloadV2TaskEntity[] {
    const normalizedBoundary = boundary === undefined ? undefined : this.normalizeBoundary(boundary);
    if (normalizedBoundary !== undefined && !this.downloadPolicyService.canReadSessionTasks(normalizedBoundary)) {
      return [];
    }
    const tasks = this.queryService.listTasks({
      tasks: this.downloadV2Service.listTasks(),
      boundary: normalizedBoundary,
      group: 'all'
    });
    return tasks;
  }

  listStableTasksSnapshot(boundary?: DownloadTaskBoundary, group: DownloadQueryGroup = 'all'): DownloadV2TaskEntity[] {
    const normalizedBoundary = boundary === undefined ? undefined : this.normalizeBoundary(boundary);
    if (normalizedBoundary !== undefined && !this.downloadPolicyService.canReadSessionTasks(normalizedBoundary)) {
      return [];
    }
    const tasks = this.queryService.listRecentTasks({
      tasks: this.downloadV2Service.listTasks(),
      boundary: normalizedBoundary,
      group: group
    });
    return tasks;
  }

  getStatusCountsSnapshot(boundary?: DownloadTaskBoundary): DownloadStatusCounts {
    const normalizedBoundary = boundary === undefined ? undefined : this.normalizeBoundary(boundary);
    if (normalizedBoundary !== undefined && !this.downloadPolicyService.canReadSessionTasks(normalizedBoundary)) {
      return this.queryService.countByStatus([], normalizedBoundary);
    }
    return this.queryService.countByStatus(this.downloadV2Service.listTasks(), normalizedBoundary);
  }

  hasRealtimeActivity(boundary?: DownloadTaskBoundary): boolean {
    const counts = this.getStatusCountsSnapshot(boundary);
    return counts.active > 0 || counts.pending > 0;
  }

  setTaskListProgressBroadcastPaused(owner: string, paused: boolean): void {
    const normalizedOwner = owner.trim();
    if (normalizedOwner.length === 0) {
      return;
    }
    const hasOwner = this.taskListProgressBroadcastPauseOwners.indexOf(normalizedOwner) >= 0;
    if (paused) {
      if (!hasOwner) {
        this.taskListProgressBroadcastPauseOwners = this.taskListProgressBroadcastPauseOwners.concat([normalizedOwner]);
      }
      return;
    }
    if (hasOwner) {
      this.taskListProgressBroadcastPauseOwners = this.taskListProgressBroadcastPauseOwners
        .filter((candidate: string) => candidate !== normalizedOwner);
    }
    if (!this.isTaskListProgressBroadcastPaused() && this.hasSuppressedTaskListProgressChange) {
      this.hasSuppressedTaskListProgressChange = false;
      this.emitTaskListChange('important');
    }
  }

  refreshActiveDownloads(notifyChange: boolean = true): boolean {
    return this.syncActiveDownloads(notifyChange);
  }

  openFileForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'open_file')) {
      return Promise.resolve(false);
    }
    const v2Task = this.resolveV2FollowupTask(guid, boundary, 'open_file');
    if (v2Task !== undefined) {
      return this.downloadFollowupService.openFile(v2Task)
        .then((result: DownloadFollowupExecutionResult) => {
          this.emitFollowupResult(result.success, result.userMessage);
          return result.success;
        });
    }
    return Promise.resolve(false);
  }

  openLocationForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'open_location')) {
      return Promise.resolve(false);
    }
    const v2Task = this.resolveV2FollowupTask(guid, boundary, 'open_location');
    if (v2Task !== undefined) {
      return this.downloadFollowupService.openLocation(v2Task)
        .then((result: DownloadFollowupExecutionResult) => {
          this.emitFollowupResult(result.success, result.userMessage);
          return result.success;
        });
    }
    return Promise.resolve(false);
  }

  saveTaskToSystemDownloadsForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.downloadPolicyService.canExportFile(boundary, true)) {
      return Promise.resolve(false);
    }
    if (!this.canExecuteTaskAction(guid, boundary, 'save_to_system')) {
      return Promise.resolve(false);
    }
    return this.downloadV2Service.exportCompletedTaskToSystemDownloads(guid);
  }

  openFile(index: number): Promise<boolean> {
    return this.executeTaskFollowupByVisibleIndex(index, 'open_file');
  }

  openLocation(index: number): Promise<boolean> {
    return this.executeTaskFollowupByVisibleIndex(index, 'open_location');
  }

  pauseTaskForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'pause')) {
      return Promise.resolve(false);
    }
    return this.downloadV2Service.pauseTask(guid);
  }

  resumeTaskForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'resume')) {
      return Promise.resolve(false);
    }
    return this.downloadV2Service.resumeTask(guid);
  }

  retryTaskForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'retry')) {
      return Promise.resolve(false);
    }
    return this.downloadV2Service.retryTask(guid);
  }

  cancelTaskForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'cancel')) {
      return Promise.resolve(false);
    }
    return this.downloadV2Service.cancelTask(guid);
  }

  cancelAndRemoveTaskForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'cancel')) {
      return Promise.resolve(false);
    }
    return this.downloadV2Service.cancelAndRemoveTask(guid);
  }

  pauseTask(index: number): Promise<boolean> {
    return this.executeTaskControlByVisibleIndex(index, 'pause');
  }

  resumeTask(index: number): Promise<boolean> {
    return this.executeTaskControlByVisibleIndex(index, 'resume');
  }

  retryTask(index: number): Promise<boolean> {
    return this.executeTaskControlByVisibleIndexAsync(index, 'retry');
  }

  cancelTask(index: number): Promise<boolean> {
    return this.executeTaskControlByVisibleIndex(index, 'cancel');
  }

  clearPrivateDownloadSessionForWindow(
    windowId: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: BrowserSessionPrivacyMode = 'private',
    dataScope: BrowserDataScope = 'session_ephemeral'
  ): number {
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(privacyMode);
    const boundary: DownloadTaskBoundary = {
      windowId: windowId,
      profileId: normalizeBrowserProfileId(profileId),
      privacyMode: normalizedPrivacyMode,
      dataScope: normalizeBrowserDataScope(dataScope, normalizedPrivacyMode)
    };
    if (!this.downloadPolicyService.canCleanupSession(boundary)) {
      return 0;
    }
    const cleanupPolicy = this.downloadPolicyService.resolveSessionCleanupPolicy(boundary);
    if (!cleanupPolicy.isPrivateSession) {
      return 0;
    }
    if (cleanupPolicy.shouldDeleteSessionTempFilesOnWindowClose) {
      this.cleanupSessionEphemeralTempFilesForWindow(windowId);
    }
    if (!cleanupPolicy.shouldClearSessionRecordsOnWindowClose) {
      return 0;
    }
    const removedCount = this.removeV2TasksForBoundary({
      windowId: boundary.windowId,
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope
    });
    if (removedCount > 0) {
      this.emitTaskListChange();
    }
    return removedCount;
  }

  removeTaskRecordForBoundary(guid: string, boundary: DownloadTaskBoundary): boolean {
    const normalizedBoundary = this.normalizeBoundary(boundary);
    if (!this.downloadPolicyService.canWriteSessionTasks(normalizedBoundary)) {
      return false;
    }
    const downloadV2Task = this.downloadV2Service.findTask(guid);
    if (downloadV2Task !== undefined) {
      if (!this.matchesTaskBoundary(downloadV2Task, normalizedBoundary)) {
        return false;
      }
      const removed = this.downloadV2Service.removeTaskRecord(guid) === true;
      if (removed) {
        this.emitTaskListChange();
      }
      return removed;
    }
    return false;
  }

  async deleteCompletedFileAndRemoveRecordForBoundary(
    guid: string,
    boundary: DownloadTaskBoundary
  ): Promise<DownloadV2CompletedFileRemovalResult> {
    const normalizedBoundary = this.normalizeBoundary(boundary);
    if (!this.downloadPolicyService.canWriteSessionTasks(normalizedBoundary)) {
      return {
        recordRemoved: false,
        fileStatus: 'not_found'
      };
    }
    const downloadV2Task = this.downloadV2Service.findTask(guid);
    if (downloadV2Task === undefined || downloadV2Task.status !== 'completed' ||
      !this.matchesTaskBoundary(downloadV2Task, normalizedBoundary)) {
      return {
        recordRemoved: false,
        fileStatus: 'not_found'
      };
    }
    const result = await this.downloadV2Service.deleteCompletedFileAndRemoveTaskRecord(guid);
    if (result.recordRemoved) {
      this.emitTaskListChange();
    }
    return result;
  }

  removeTaskRecord(index: number): boolean {
    const tasks = this.listTasks(this.activeBoundary);
    const visibleIndex = tasks.length - 1 - index;
    const task = visibleIndex >= 0 ? tasks[visibleIndex] : undefined;
    if (task === undefined) {
      return false;
    }
    return this.removeTaskRecordForBoundary(task.guid, this.activeBoundary);
  }

  getPendingDownloadPrompt(): PendingDownloadPromptState | undefined {
    const v2Prompt = this.downloadV2Service.getPendingPrompt();
    if (v2Prompt !== undefined) {
      return {
        guid: v2Prompt.guid,
        fileName: v2Prompt.fileName,
        sourceHost: v2Prompt.sourceHost,
        url: v2Prompt.url,
        totalBytes: v2Prompt.totalBytes,
        mimeType: v2Prompt.mimeType,
        contentDisposition: v2Prompt.contentDisposition,
        riskLevel: 'warning',
        title: v2Prompt.title,
        message: v2Prompt.message,
        confirmLabel: v2Prompt.confirmLabel,
        cancelLabel: v2Prompt.cancelLabel
      };
    }
    return undefined;
  }

  confirmPendingDownload(guid: string, fileName?: string): Promise<boolean> {
    const prompt = this.downloadV2Service.getPendingPrompt();
    hilog.info(
      DOWNLOAD_RUNTIME_SERVICE_DOMAIN,
      DOWNLOAD_RUNTIME_SERVICE_TAG,
      'confirm pending via v2 guid=%{public}s prompt=%{public}s',
      guid,
      prompt?.guid ?? 'none'
    );
    return this.downloadV2Service.confirmPendingPrompt(guid, fileName)
      .then((task?: DownloadV2TaskEntity) => {
        const confirmed = task !== undefined &&
          task.status !== 'failed' &&
          task.status !== 'canceled' &&
          task.status !== 'removed';
        hilog.info(
          DOWNLOAD_RUNTIME_SERVICE_DOMAIN,
          DOWNLOAD_RUNTIME_SERVICE_TAG,
          'confirm pending result guid=%{public}s confirmed=%{public}s taskStatus=%{public}s temp=%{public}s final=%{public}s',
          guid,
          confirmed ? 'true' : 'false',
          task?.status ?? 'none',
          task?.persistence.tempFilePath ?? '',
          task?.persistence.finalDisplayPath ?? ''
        );
        return confirmed;
      })
      .catch((_error: Error) => {
        this.emitError('下载组件初始化失败，请稍后重试。');
        return false;
      });
  }

  cancelPendingDownload(guid: string): boolean {
    const canceledV2Request = this.downloadV2Service.cancelPendingPrompt(guid);
    if (canceledV2Request !== undefined) {
      const fileName = canceledV2Request.suggestedFileName?.trim() ?? '';
      this.emitInfo(`已取消下载：${fileName.length > 0 ? fileName : '未命名下载'}。`);
      return true;
    }
    return false;
  }

  abandonPendingDownload(guid: string): boolean {
    const currentPrompt = this.downloadV2Service.getPendingPrompt();
    if (currentPrompt?.guid !== guid) {
      return false;
    }
    this.downloadV2Service.clearPendingPrompt(guid);
    return true;
  }

  requestManualDownloadPrompt(input: ManualDownloadRequestInput): PendingDownloadPromptState | undefined {
    if (!this.downloadPolicyService.canWriteSessionTasks(this.activeBoundary)) {
      return undefined;
    }
    const prompt = this.downloadV2Service.createManualPrompt(
      input.url,
      {
        windowId: this.activeBoundary.windowId ?? '',
        profileId: this.activeBoundary.profileId,
        privacyMode: this.activeBoundary.privacyMode,
        dataScope: this.activeBoundary.dataScope,
        sourcePageUrl: this.activeBoundary.sourcePageUrl
      },
      input.suggestedFileName,
      input.sourceHost,
      {
        userAgent: input.userAgent,
        referer: input.referer,
        mimeType: input.mimeType,
        contentDisposition: input.contentDisposition,
        totalBytes: input.totalBytes,
        headers: input.headers
      }
    );
    if (prompt === undefined) {
      return undefined;
    }
    return {
      guid: prompt.guid,
      fileName: prompt.fileName,
      sourceHost: prompt.sourceHost,
      url: prompt.url,
      totalBytes: prompt.totalBytes,
      mimeType: prompt.mimeType,
      contentDisposition: prompt.contentDisposition,
      riskLevel: 'warning',
      title: prompt.title,
      message: prompt.message,
      confirmLabel: prompt.confirmLabel,
      cancelLabel: prompt.cancelLabel
    };
  }

  requestManualDownload(input: ManualDownloadRequestInput): ManualDownloadRequestResult | undefined {
    if (!this.downloadPolicyService.canWriteSessionTasks(this.activeBoundary)) {
      return undefined;
    }
    const result = this.downloadV2Service.createManualRequest(
      input.url,
      {
        windowId: this.activeBoundary.windowId ?? '',
        profileId: this.activeBoundary.profileId,
        privacyMode: this.activeBoundary.privacyMode,
        dataScope: this.activeBoundary.dataScope,
        sourcePageUrl: this.activeBoundary.sourcePageUrl
      },
      input.suggestedFileName,
      input.sourceHost,
      {
        userAgent: input.userAgent,
        referer: input.referer,
        mimeType: input.mimeType,
        contentDisposition: input.contentDisposition,
        totalBytes: input.totalBytes,
        headers: input.headers
      }
    );
    if (result === undefined) {
      return undefined;
    }
    return {
      guid: result.guid,
      prompt: this.toPendingDownloadPromptFromV2(result.prompt),
      started: result.started
    };
  }

  private toPendingDownloadPromptFromV2(prompt?: DownloadV2Prompt): PendingDownloadPromptState | undefined {
    if (prompt === undefined) {
      return undefined;
    }
    return {
      guid: prompt.guid,
      fileName: prompt.fileName,
      sourceHost: prompt.sourceHost,
      url: prompt.url,
      totalBytes: prompt.totalBytes,
      mimeType: prompt.mimeType,
      contentDisposition: prompt.contentDisposition,
      riskLevel: 'warning',
      title: prompt.title,
      message: prompt.message,
      confirmLabel: prompt.confirmLabel,
      cancelLabel: prompt.cancelLabel
    };
  }

  private initialize(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    this.downloadBridge.setCallbacks({
      onDownloadEvent: (event: PlatformDownloadEvent) => {
        if (event.type === 'before_download') {
          this.refreshActiveBoundarySourcePageUrl();
        }
        this.callbacks.onPlatformDownloadEvent?.(event, this.normalizeBoundary(this.activeBoundary));
        this.callbackListeners.forEach((listener: DownloadRuntimeServiceCallbackListener) => {
          listener.callbacks.onPlatformDownloadEvent?.(event, this.normalizeBoundary(this.activeBoundary));
        });
        const handled = this.downloadV2Service.consumePlatformEvent(event, {
          windowId: this.activeBoundary.windowId ?? '',
          profileId: this.activeBoundary.profileId,
          privacyMode: this.activeBoundary.privacyMode,
          dataScope: this.activeBoundary.dataScope,
          sourcePageUrl: this.activeBoundary.sourcePageUrl
        }) === true;
        if (!handled) {
          this.emitError(`下载处理失败：${event.snapshot.suggestedFileName}。`);
        }
      }
    });
    this.downloadBridge.getDelegate();
  }

  private syncActiveDownloads(notifyChange: boolean = false): boolean {
    if (this.isSyncingActiveDownloads) {
      hilog.info(
        DOWNLOAD_RUNTIME_SERVICE_DOMAIN,
        DOWNLOAD_RUNTIME_SERVICE_TAG,
        'skip nested sync active downloads notify=%{public}s',
        notifyChange ? 'true' : 'false'
      );
      return false;
    }
    this.initialize();
    this.isSyncingActiveDownloads = true;
    try {
      const changed = this.downloadV2Service.syncActiveSnapshots(this.downloadBridge.getActiveDownloadSnapshots()) === true;
      if (changed && notifyChange) {
        this.emitTaskListChange();
      }
      return changed;
    } finally {
      this.isSyncingActiveDownloads = false;
    }
  }

  private emitTaskListChange(changeKind: 'progress' | 'important' = 'important'): void {
    if (changeKind === 'progress' && this.isTaskListProgressBroadcastPaused()) {
      this.hasSuppressedTaskListProgressChange = true;
      return;
    }
    const hasPrimaryCallback = this.callbacks.onTaskListChange !== undefined;
    const hasListenerCallback = this.callbackListeners.some((listener: DownloadRuntimeServiceCallbackListener) => {
      return listener.callbacks.onTaskListChange !== undefined;
    });
    if (!hasPrimaryCallback && !hasListenerCallback) {
      return;
    }
    const tasks = this.listTasksSnapshot(this.activeBoundary);
    this.callbacks.onTaskListChange?.(tasks);
    this.callbackListeners.forEach((listener: DownloadRuntimeServiceCallbackListener) => {
      listener.callbacks.onTaskListChange?.(tasks);
    });
  }

  private isTaskListProgressBroadcastPaused(): boolean {
    return this.taskListProgressBroadcastPauseOwners.length > 0;
  }

  private emitInfo(message: string): void {
    this.callbacks.onInfo?.(message);
    this.callbackListeners.forEach((listener: DownloadRuntimeServiceCallbackListener) => {
      listener.callbacks.onInfo?.(message);
    });
  }

  private emitError(message: string): void {
    this.callbacks.onError?.(message);
    this.callbackListeners.forEach((listener: DownloadRuntimeServiceCallbackListener) => {
      listener.callbacks.onError?.(message);
    });
  }

  private emitPendingDownloadPromptChange(prompt?: PendingDownloadPromptState): void {
    this.callbacks.onPendingDownloadPromptChange?.(prompt);
    this.callbackListeners.forEach((listener: DownloadRuntimeServiceCallbackListener) => {
      listener.callbacks.onPendingDownloadPromptChange?.(prompt);
    });
  }

  private emitCallbacksToListener(callbacks: DownloadRuntimeServiceCallbacks): void {
    callbacks.onTaskListChange?.(this.listTasksSnapshot(this.activeBoundary));
    callbacks.onPendingDownloadPromptChange?.(this.getPendingDownloadPrompt());
  }

  private normalizeBoundary(boundary: DownloadTaskBoundary): DownloadTaskBoundary {
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    return {
      windowId: boundary.windowId?.trim() ?? '',
      profileId: normalizeBrowserProfileId(boundary.profileId),
      privacyMode: normalizedPrivacyMode,
      dataScope: normalizeBrowserDataScope(boundary.dataScope, normalizedPrivacyMode),
      sourcePageUrl: boundary.sourcePageUrl?.trim() ?? ''
    };
  }

  private refreshActiveBoundarySourcePageUrl(): void {
    const resolvedUrl = this.callbacks.resolveCurrentPageUrl?.().trim() ?? '';
    if (resolvedUrl.length <= 0 || resolvedUrl === (this.activeBoundary.sourcePageUrl ?? '')) {
      return;
    }
    this.activeBoundary = {
      windowId: this.activeBoundary.windowId,
      profileId: this.activeBoundary.profileId,
      privacyMode: this.activeBoundary.privacyMode,
      dataScope: this.activeBoundary.dataScope,
      sourcePageUrl: resolvedUrl
    };
  }

  private isTaskInsideBoundary(task: DownloadV2TaskEntity, boundary: DownloadTaskBoundary): boolean {
    return matchesDownloadTaskBoundary(
      {
        windowId: task.windowId,
        profileId: task.profileId,
        privacyMode: task.privacyMode,
        dataScope: task.dataScope
      },
      {
        windowId: boundary.windowId,
        profileId: boundary.profileId,
        privacyMode: boundary.privacyMode,
        dataScope: boundary.dataScope
      }
    );
  }

  private executeTaskControlByVisibleIndex(index: number, action: 'pause' | 'resume' | 'cancel'): Promise<boolean> {
    const tasks = this.listTasks(this.activeBoundary);
    const visibleIndex = tasks.length - 1 - index;
    const task = visibleIndex >= 0 ? tasks[visibleIndex] : undefined;
    if (task === undefined) {
      return Promise.resolve(false);
    }
    if (action === 'pause') {
      return this.pauseTaskForBoundary(task.guid, this.activeBoundary);
    }
    if (action === 'resume') {
      return this.resumeTaskForBoundary(task.guid, this.activeBoundary);
    }
    return this.cancelTaskForBoundary(task.guid, this.activeBoundary);
  }

  private executeTaskControlByVisibleIndexAsync(index: number, action: 'retry'): Promise<boolean> {
    const tasks = this.listTasks(this.activeBoundary);
    const visibleIndex = tasks.length - 1 - index;
    const task = visibleIndex >= 0 ? tasks[visibleIndex] : undefined;
    if (task === undefined) {
      return Promise.resolve(false);
    }
    return this.retryTaskForBoundary(task.guid, this.activeBoundary);
  }

  private executeTaskFollowupByVisibleIndex(index: number, action: 'open_file' | 'open_location'): Promise<boolean> {
    const tasks = this.listTasks(this.activeBoundary);
    const visibleIndex = tasks.length - 1 - index;
    const task = visibleIndex >= 0 ? tasks[visibleIndex] : undefined;
    if (task === undefined) {
      return Promise.resolve(false);
    }
    if (action === 'open_file') {
      return this.openFileForBoundary(task.guid, this.activeBoundary);
    }
    return this.openLocationForBoundary(task.guid, this.activeBoundary);
  }

  private cleanupSessionEphemeralTempFilesForWindow(windowId: string): void {
    const tasks = this.downloadV2Service.listTasks().filter((task: DownloadV2TaskEntity) => {
      return (task.windowId?.trim() ?? '') === windowId.trim() && task.dataScope === 'session_ephemeral';
    });
    tasks.forEach((task: DownloadV2TaskEntity) => {
      const tempLocalPath = task.persistence.tempFilePath?.trim() ?? '';
      if (tempLocalPath.length <= 0) {
        return;
      }
      this.fileResolutionService.deleteLocalPath(tempLocalPath).catch(() => {
        this.emitError(`私密下载临时文件清理失败：${task.suggestedFileName}。`);
      });
    });
  }

  private removeV2TasksForBoundary(boundary: DownloadTaskBoundary): number {
    const normalizedBoundary = this.normalizeBoundary(boundary);
    let removedCount = 0;
    this.downloadV2Service.listTasks().forEach((task: DownloadV2TaskEntity) => {
      if (!this.matchesTaskBoundary(task, normalizedBoundary)) {
        return;
      }
      if (this.downloadV2Service.removeTaskRecord(task.guid)) {
        removedCount += 1;
      }
    });
    return removedCount;
  }

  private resolveV2FollowupTask(
    guid: string,
    boundary: DownloadTaskBoundary,
    action: DownloadTaskFollowupAction
  ): DownloadFollowupTask | undefined {
    const v2Task = this.downloadV2Service.findTask(guid);
    if (v2Task === undefined) {
      return undefined;
    }
    const normalizedBoundary = this.normalizeBoundary(boundary);
    if (!this.allowsTaskFollowupAction(v2Task, action) || !this.isTaskInsideBoundary(v2Task, normalizedBoundary)) {
      return undefined;
    }
    return this.toFollowupTaskEntityFromV2({
      suggestedFileName: v2Task.suggestedFileName,
      mimeType: v2Task.request.mimeType,
      tempLocalPath: v2Task.persistence.tempFilePath,
      finalFileUri: v2Task.persistence.finalFileUri
    });
  }

  private toFollowupTaskEntityFromV2(task: DownloadV2FollowupTaskSnapshot): DownloadFollowupTask {
    return {
      suggestedFileName: task.suggestedFileName,
      mimeType: task.mimeType,
      tempLocalPath: task.tempLocalPath,
      finalFileUri: task.finalFileUri
    };
  }

  private emitFollowupResult(success: boolean, message?: string): void {
    const normalizedMessage = message?.trim() ?? '';
    if (normalizedMessage.length <= 0) {
      return;
    }
    if (success) {
      this.emitInfo(normalizedMessage);
      return;
    }
    this.emitError(normalizedMessage);
  }

  private allowsTaskFollowupAction(task: DownloadV2TaskEntity, action: DownloadTaskFollowupAction): boolean {
    return this.resolveAllowedActionsForV2Task(task).indexOf(action) >= 0;
  }

  private canExecuteTaskAction(
    guid: string,
    boundary: DownloadTaskBoundary,
    action: DownloadV2ManagementAction
  ): boolean {
    if (!this.downloadPolicyService.canReadSessionTasks(boundary)) {
      return false;
    }
    const task = this.getTaskByGuid(guid);
    if (task === undefined) {
      return false;
    }
    if (!this.isTaskInsideBoundary(task, this.normalizeBoundary(boundary))) {
      return false;
    }
    if (this.isTaskMutationAction(action) && !this.downloadPolicyService.canWriteSessionTasks(boundary)) {
      return false;
    }
    return this.resolveAllowedActionsForV2Task(task).indexOf(action) >= 0;
  }

  private isTaskMutationAction(action: DownloadV2ManagementAction): boolean {
    return action === 'pause' ||
      action === 'resume' ||
      action === 'retry' ||
      action === 'cancel' ||
      action === 'remove_record';
  }

  private getTaskByGuid(guid: string): DownloadV2TaskEntity | undefined {
    const normalizedGuid = guid.trim();
    if (normalizedGuid.length <= 0) {
      return undefined;
    }
    return this.downloadV2Service.findTask(normalizedGuid);
  }

  private resolveAllowedActionsForV2Task(task: DownloadV2TaskEntity): DownloadV2ManagementAction[] {
    let supportedActions: DownloadV2ManagementAction[] = [];
    getDownloadV2ActionPermissionSet(task.status).allowedActions.forEach((action: DownloadV2Action) => {
      if (action !== 'confirm' && action !== 'start') {
        supportedActions.push(action);
      }
    });
    if (task.status !== 'completed' && task.status !== 'failed' &&
      task.status !== 'canceled' && task.status !== 'removed') {
      supportedActions = supportedActions.filter((action: DownloadV2ManagementAction) => action !== 'remove_record');
    }
    const retryOnly = task.runtime.resumeCapability === 'retry_only';
    const canContinuePersisted = canContinueDownloadV2TaskFromPersistedData(task);
    const canResumeLive = task.runtime.resumeCapability === 'live_resume';
    if (task.status === 'failed' && canContinuePersisted) {
      supportedActions = supportedActions.filter((action: DownloadV2ManagementAction) => action !== 'retry');
      if (supportedActions.indexOf('resume') < 0) {
        supportedActions.unshift('resume');
      }
    } else if (task.status === 'failed' && retryOnly) {
      supportedActions = supportedActions.filter((action: DownloadV2ManagementAction) => action !== 'resume');
      if (supportedActions.indexOf('retry') < 0) {
        supportedActions.unshift('retry');
      }
    } else if (task.status === 'failed' && canResumeLive) {
      supportedActions = supportedActions.filter((action: DownloadV2ManagementAction) => action !== 'retry');
      if (supportedActions.indexOf('resume') < 0) {
        supportedActions.unshift('resume');
      }
    }
    if (task.status === 'completed' && !this.canSaveV2TaskToSystemDownloads(task)) {
      supportedActions = supportedActions.filter((action: DownloadV2ManagementAction) => action !== 'save_to_system');
    }
    return supportedActions;
  }

  private canSaveV2TaskToSystemDownloads(task: DownloadV2TaskEntity): boolean {
    if (task.status !== 'completed') {
      return false;
    }
    if ((task.persistence.finalFileUri?.trim().length ?? 0) > 0) {
      return false;
    }
    if ((task.persistence.tempFilePath?.trim().length ?? 0) <= 0) {
      return false;
    }
    const savePolicy = this.downloadPolicyService.resolveSavePolicy({
      windowId: task.windowId,
      profileId: task.profileId,
      privacyMode: task.privacyMode,
      dataScope: task.dataScope,
      sourcePageUrl: task.request.sourcePageUrl
    });
    return savePolicy.reason !== 'private_session_temp_only';
  }

  private matchesTaskBoundary(task: DownloadV2TaskEntity, boundary: DownloadTaskBoundary): boolean {
    return matchesDownloadTaskBoundary(
      {
        windowId: task.windowId,
        profileId: task.profileId,
        privacyMode: task.privacyMode,
        dataScope: task.dataScope
      },
      {
        windowId: boundary.windowId,
        profileId: boundary.profileId,
        privacyMode: boundary.privacyMode,
        dataScope: boundary.dataScope
      }
    );
  }
}
