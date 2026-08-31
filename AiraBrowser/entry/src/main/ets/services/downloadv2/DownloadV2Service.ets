import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DownloadV2Engine,
  DownloadV2EngineObserver
} from '../../core/downloadv2/DownloadV2Engine';
import {
  canContinueDownloadV2TaskFromPersistedData,
  createDownloadV2BoundarySnapshot,
  MutableDownloadV2TaskEntityPatch,
  DownloadV2TaskEntity
} from '../../domain/downloadv2/DownloadV2TaskEntity';
import {
  buildDownloadV2EmptyFailure,
  DownloadV2Failure,
  DownloadV2PersistenceSnapshot,
  DownloadV2ProgressSnapshot,
  DownloadV2RequestContext,
  DownloadV2RuntimeSnapshot,
  DownloadV2Status,
  DownloadV2FailureCode,
  DownloadV2Driver,
  isDownloadV2ActiveStatus,
  isDownloadV2TerminalStatus
} from '../../domain/downloadv2/DownloadV2Types';
import {
  DownloadV2CaptureBoundary,
  DownloadV2CapturedRequest,
  DownloadV2Prompt
} from '../../features/downloadv2/DownloadV2CaptureTypes';
import {
  DownloadV2ManualRequestContext,
  DownloadV2RequestCapture
} from '../../features/downloadv2/DownloadV2RequestCapture';
import { PlatformDownloadEvent } from '../../platform/download/PlatformDownloadAdapter';
import {
  DownloadV2Repository,
  PersistentDownloadV2Repository
} from '../../data/downloadv2/DownloadV2Repository';
import { PlatformDownloadAdapter, PlatformDownloadSnapshot } from '../../platform/download/PlatformDownloadAdapter';
import { ArkWebDownloadBridge } from '../../platform/download/ArkWebDownloadBridge';
import {
  bucketRuntimeDiagnosticDuration,
  DownloadRuntimeDiagnosticEvent,
  DownloadRuntimeDiagnosticRecorder
} from '../../common/models/RuntimeDiagnosticModels';
import {
  DownloadFileResolutionAdapter,
  DownloadFileResolutionService
} from '../download/DownloadFileResolutionService';
import { DownloadFileNameService } from '../download/DownloadFileNameService';
import { DownloadPolicyService } from '../download/DownloadPolicyService';
import {
  DownloadQueuePolicyService,
  DownloadQueueSchedulePlan
} from '../download/DownloadQueuePolicyService';
import {
  DownloadNetworkPolicyService,
  DownloadNetworkSnapshot
} from '../download/DownloadNetworkPolicyService';
import {
  DownloadTargetResolutionService
} from '../download/DownloadTargetResolutionService';
import { DownloadTriggerDiagnosticsService } from '../download/DownloadTriggerDiagnosticsService';
import {
  DownloadHtmlRedirectResolution,
  DownloadHtmlRedirectResolverService
} from './DownloadHtmlRedirectResolverService';
import { ActivityTracker } from '../activity/ActivityTracker';
import { DownloadTaskBoundary } from '../../domain/download/DownloadTypes';
import { DownloadV2SystemNotificationService } from './DownloadV2SystemNotificationService';

const DOWNLOAD_V2_SERVICE_DOMAIN = 0x0000;
const DOWNLOAD_V2_SERVICE_TAG = 'DownloadV2Service';
const MAX_RECONNECT_TARGET_DIAGNOSTICS = 2;

export interface DownloadV2ServiceCallbacks {
  onTaskChanged?: (task: DownloadV2TaskEntity, changeKind?: DownloadV2TaskChangeKind) => void;
  onTaskRemoved?: (guid: string) => void;
  onPromptChanged?: (prompt?: DownloadV2Prompt) => void;
  onInfo?: (message: string) => void;
  onError?: (message: string) => void;
}

export type DownloadV2TaskChangeKind = 'progress' | 'terminal' | 'structural';

export type DownloadV2CompletedFileRemovalStatus =
  'deleted' |
  'missing' |
  'failed' |
  'not_found';

export interface DownloadV2CompletedFileRemovalResult {
  recordRemoved: boolean;
  fileStatus: DownloadV2CompletedFileRemovalStatus;
}

export interface DownloadV2ManualRequestResult {
  guid: string;
  prompt?: DownloadV2Prompt;
  started: boolean;
}

export class DownloadV2Service {
  private static readonly CONTROL_SYNC_GRACE_MS: number = 2200;
  private engine: DownloadV2Engine;
  private requestCapture: DownloadV2RequestCapture;
  private repository: DownloadV2Repository;
  private platformAdapter: PlatformDownloadAdapter;
  private fileResolutionService: DownloadFileResolutionAdapter;
  private fileNameService: DownloadFileNameService;
  private downloadPolicyService: DownloadPolicyService;
  private downloadQueuePolicyService: DownloadQueuePolicyService;
  private downloadNetworkPolicyService: DownloadNetworkPolicyService;
  private downloadTargetResolutionService: DownloadTargetResolutionService;
  private htmlRedirectResolverService: DownloadHtmlRedirectResolverService;
  private systemNotificationService?: DownloadV2SystemNotificationService;
  private callbacks: DownloadV2ServiceCallbacks = {};
  private completedPersistenceGuids: Record<string, boolean | undefined> = {};
  private expectedStatusByGuid: Record<string, DownloadV2Status | undefined> = {};
  private expectedStatusDeadlineByGuid: Record<string, number | undefined> = {};
  private previousStatusByGuid: Record<string, DownloadV2Status | undefined> = {};
  private completedActivityGuids: Record<string, boolean | undefined> = {};
  private activityTracker?: ActivityTracker;
  private downloadTriggerDiagnosticsService: DownloadTriggerDiagnosticsService;
  private runtimeDiagnosticRecorder?: DownloadRuntimeDiagnosticRecorder;
  private isQueueScheduling: boolean = false;
  private initializationPromise?: Promise<void>;

  constructor(
    engine?: DownloadV2Engine,
    requestCapture?: DownloadV2RequestCapture,
    repository?: DownloadV2Repository,
    platformAdapter?: PlatformDownloadAdapter,
    fileResolutionService?: DownloadFileResolutionAdapter,
    downloadPolicyService?: DownloadPolicyService,
    htmlRedirectResolverService?: DownloadHtmlRedirectResolverService,
    fileNameService?: DownloadFileNameService,
    activityTracker?: ActivityTracker,
    downloadTriggerDiagnosticsService?: DownloadTriggerDiagnosticsService,
    downloadTargetResolutionService?: DownloadTargetResolutionService,
    downloadQueuePolicyService?: DownloadQueuePolicyService,
    downloadNetworkPolicyService?: DownloadNetworkPolicyService
  ) {
    this.repository = repository ?? new PersistentDownloadV2Repository();
    this.engine = engine ?? new DownloadV2Engine(this.repository);
    this.requestCapture = requestCapture ?? new DownloadV2RequestCapture();
    this.platformAdapter = platformAdapter ?? new ArkWebDownloadBridge();
    this.fileResolutionService = fileResolutionService ?? new DownloadFileResolutionService();
    this.fileNameService = fileNameService ?? new DownloadFileNameService();
    this.downloadPolicyService = downloadPolicyService ?? new DownloadPolicyService();
    this.htmlRedirectResolverService = htmlRedirectResolverService ?? new DownloadHtmlRedirectResolverService();
    this.activityTracker = activityTracker;
    this.downloadTriggerDiagnosticsService = downloadTriggerDiagnosticsService ?? new DownloadTriggerDiagnosticsService();
    this.downloadTargetResolutionService = downloadTargetResolutionService ??
      new DownloadTargetResolutionService(this.fileResolutionService, this.downloadPolicyService);
    this.downloadQueuePolicyService = downloadQueuePolicyService ?? new DownloadQueuePolicyService();
    this.downloadNetworkPolicyService = downloadNetworkPolicyService ?? new DownloadNetworkPolicyService();
    this.bindRequestCaptureCallbacks();
  }

  initialize(): Promise<void> {
    if (this.initializationPromise !== undefined) {
      return this.initializationPromise;
    }
    this.initializationPromise = this.initializeRuntime()
      .catch((error: Error) => {
        this.initializationPromise = undefined;
        throw error;
      });
    return this.initializationPromise;
  }

  attachRuntimeDiagnosticRecorder(recorder: DownloadRuntimeDiagnosticRecorder): void {
    this.runtimeDiagnosticRecorder = recorder;
  }

  attachSystemNotificationService(service: DownloadV2SystemNotificationService): void {
    this.systemNotificationService = service;
  }

  private async initializeRuntime(): Promise<void> {
    await this.engine.initialize();
    this.engine.setObserver(this.buildEngineObserver());
    this.downloadNetworkPolicyService.startMonitoring((_snapshot: DownloadNetworkSnapshot): void => {
      void this.scheduleNextQueuedDownloads('network_changed');
    });
    await this.reconnectPersistedActiveTasks();
  }

  setCellularDownloadsAllowed(allowed: boolean, rescheduleQueuedDownloads: boolean = true): void {
    this.downloadNetworkPolicyService.setCellularDownloadsAllowed(allowed);
    if (rescheduleQueuedDownloads) {
      void this.scheduleNextQueuedDownloads('cellular_download_policy_changed');
    }
  }

  async reconnectPersistedActiveTasks(): Promise<void> {
    const scanStartEvent: DownloadRuntimeDiagnosticEvent = {
      owner: 'service',
      operation: 'reconnect_scan',
      state: 'task_clone_pending',
      result: 'begin'
    };
    await this.runtimeDiagnosticRecorder?.recordDownloadRuntimeDiagnosticAndWait(scanStartEvent);
    const scanStartedAt = Date.now();
    const allTasks = this.engine.listTasks();
    const reconnectTargets = allTasks
      .filter((task: DownloadV2TaskEntity) => this.shouldReconnectPersistedTask(task));
    const scanResultEvent: DownloadRuntimeDiagnosticEvent = {
      owner: 'service',
      operation: 'reconnect_scan',
      state: `records=${allTasks.length} targets=${reconnectTargets.length} elapsed=${bucketRuntimeDiagnosticDuration(Date.now() - scanStartedAt)}`,
      result: 'ok'
    };
    await this.runtimeDiagnosticRecorder?.recordDownloadRuntimeDiagnosticAndWait(scanResultEvent);
    for (let index = 0; index < reconnectTargets.length; index += 1) {
      const task = reconnectTargets[index];
      const platformTaskId = task.runtime.platformTaskId?.trim() ?? '';
      const platformTaskToken = task.runtime.platformTaskToken?.trim() ?? '';
      const shouldRecordTarget = index < MAX_RECONNECT_TARGET_DIAGNOSTICS;
      const driverClass = task.persistence.downloadDriver ?? 'unknown';
      if (shouldRecordTarget) {
        const targetStartEvent: DownloadRuntimeDiagnosticEvent = {
          owner: 'service',
          operation: 'reconnect_target',
          state: `index=${index + 1}/${reconnectTargets.length} status=${task.status} driver=${driverClass}`,
          result: 'begin'
        };
        await this.runtimeDiagnosticRecorder?.recordDownloadRuntimeDiagnosticAndWait(targetStartEvent);
      }
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'restore inspect guid=%{public}s status=%{public}s platformTaskId=%{public}s taskToken=%{public}s',
        task.guid,
        task.status,
        platformTaskId,
        platformTaskToken.length > 0 ? 'yes' : 'no'
      );
      let snapshot: PlatformDownloadSnapshot | undefined = undefined;
      if (platformTaskId.length > 0) {
        snapshot = await this.platformAdapter.reconnectDownload(task.guid, platformTaskId, platformTaskToken);
      }
      if (snapshot === undefined) {
        if (shouldRecordTarget) {
          const targetUnavailableEvent: DownloadRuntimeDiagnosticEvent = {
            owner: 'service',
            operation: 'reconnect_target',
            state: `index=${index + 1}/${reconnectTargets.length} status=${task.status} driver=${driverClass}`,
            result: platformTaskId.length > 0 ? 'unavailable' : 'no_platform_id'
          };
          this.runtimeDiagnosticRecorder?.recordDownloadRuntimeDiagnostic(targetUnavailableEvent);
        }
        hilog.warn(
          DOWNLOAD_V2_SERVICE_DOMAIN,
          DOWNLOAD_V2_SERVICE_TAG,
          'restore unavailable guid=%{public}s status=%{public}s',
          task.guid,
          task.status
        );
        this.markTaskRestoreUnavailable(task.guid);
        continue;
      }
      this.syncTaskFromPlatformEvent({
        type: 'updated',
        snapshot: snapshot
      }, true);
      if (shouldRecordTarget) {
        const targetRestoredEvent: DownloadRuntimeDiagnosticEvent = {
          owner: 'service',
          operation: 'reconnect_target',
          state: `index=${index + 1}/${reconnectTargets.length} status=${task.status} driver=${driverClass}`,
          result: 'restored'
        };
        this.runtimeDiagnosticRecorder?.recordDownloadRuntimeDiagnostic(targetRestoredEvent);
      }
    }
    await this.repository.flushPersistence();
  }

  setCallbacks(callbacks: DownloadV2ServiceCallbacks): void {
    this.callbacks = callbacks;
  }

  consumePlatformEvent(event: PlatformDownloadEvent, boundary: DownloadV2CaptureBoundary): boolean {
    this.downloadTriggerDiagnosticsService.recordPlatformEvent(event);
    if (event.type === 'before_download') {
      this.startInitializationOnDemand();
      const promotedManualPromptCount = this.requestCapture.removeManualPendingRequestsForUrl(event.snapshot.url);
      if (promotedManualPromptCount > 0) {
        hilog.info(
          DOWNLOAD_V2_SERVICE_DOMAIN,
          DOWNLOAD_V2_SERVICE_TAG,
          'promote platform before_download over manual pending url=%{public}s count=%{public}d',
          event.snapshot.url,
          promotedManualPromptCount
        );
      }
      if (this.shouldIgnoreDuplicatePlatformBeforeDownload(event.snapshot)) {
        hilog.info(
          DOWNLOAD_V2_SERVICE_DOMAIN,
          DOWNLOAD_V2_SERVICE_TAG,
          'ignore duplicate platform before_download guid=%{public}s url=%{public}s',
          event.snapshot.guid,
          event.snapshot.url
        );
        return true;
      }
      const requiresConfirmation = this.shouldRequireConfirmation(boundary);
      const captured = this.requestCapture.capturePlatformRequest(event.snapshot, boundary, requiresConfirmation);
      this.downloadTriggerDiagnosticsService.recordCapturedRequest(
        'arkweb_delegate',
        captured,
        'captured',
        requiresConfirmation ? 'prompt' : 'auto_start'
      );
      if (!requiresConfirmation) {
        void this.startCapturedRequest(captured, false, 'platform_before_download');
      }
      return true;
    }
    return this.syncTaskFromPlatformEvent(event);
  }

  createManualPrompt(
    url: string,
    boundary: DownloadV2CaptureBoundary,
    suggestedFileName?: string,
    sourceHost?: string,
    context?: DownloadV2ManualRequestContext
  ): DownloadV2Prompt | undefined {
    this.startInitializationOnDemand();
    const requiresConfirmation = this.shouldRequireConfirmation(boundary);
    const request = this.requestCapture.createManualRequest(
      url,
      boundary,
      suggestedFileName,
      sourceHost,
      requiresConfirmation,
      context
    );
    if (request === undefined) {
      return undefined;
    }
    this.downloadTriggerDiagnosticsService.recordCapturedRequest(
      'manual',
      request,
      'captured',
      requiresConfirmation ? 'prompt' : 'auto_start'
    );
    if (!requiresConfirmation) {
      void this.startCapturedRequest(request, false, 'manual_request');
      return undefined;
    }
    return this.requestCapture.getPendingPrompt();
  }

  createManualRequest(
    url: string,
    boundary: DownloadV2CaptureBoundary,
    suggestedFileName?: string,
    sourceHost?: string,
    context?: DownloadV2ManualRequestContext
  ): DownloadV2ManualRequestResult | undefined {
    this.startInitializationOnDemand();
    const requiresConfirmation = this.shouldRequireConfirmation(boundary);
    const request = this.requestCapture.createManualRequest(
      url,
      boundary,
      suggestedFileName,
      sourceHost,
      requiresConfirmation,
      context
    );
    if (request === undefined) {
      return undefined;
    }
    this.downloadTriggerDiagnosticsService.recordCapturedRequest(
      'manual',
      request,
      'captured',
      requiresConfirmation ? 'prompt' : 'auto_start'
    );
    if (!requiresConfirmation) {
      void this.startCapturedRequest(request, false, 'manual_request');
      return {
        guid: request.guid,
        started: true
      };
    }
    return {
      guid: request.guid,
      prompt: this.requestCapture.getPendingPrompt(),
      started: false
    };
  }

  getPendingPrompt(): DownloadV2Prompt | undefined {
    return this.requestCapture.getPendingPrompt();
  }

  clearPendingPrompt(guid?: string): void {
    const currentPrompt = this.requestCapture.getPendingPrompt();
    if (guid !== undefined && currentPrompt?.guid !== guid) {
      return;
    }
    const currentRequest = currentPrompt === undefined
      ? undefined
      : this.requestCapture.getPendingRequest(currentPrompt.guid);
    if (currentRequest !== undefined) {
      this.requestCapture.cancelRequest(currentRequest.guid);
      this.cancelPlatformPendingRequest(currentRequest);
    }
  }

  async confirmPendingPrompt(guid: string, fileName?: string): Promise<DownloadV2TaskEntity | undefined> {
    const currentPrompt = this.requestCapture.getPendingPrompt();
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'confirm prompt begin guid=%{public}s currentPrompt=%{public}s existingTask=%{public}s',
      guid,
      currentPrompt?.guid ?? 'none',
      this.engine.findTask(guid)?.status ?? 'none'
    );
    const request = this.requestCapture.confirmRequest(guid);
    if (request === undefined) {
      hilog.warn(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'confirm prompt missing guid=%{public}s',
        guid
      );
      return undefined;
    }
    const task = await this.createTaskFromCapturedRequest(request, true, fileName);
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'confirm prompt result guid=%{public}s status=%{public}s temp=%{public}s',
      guid,
      task?.status ?? 'none',
      task?.persistence.tempFilePath ?? ''
    );
    return task;
  }

  cancelPendingPrompt(guid: string): DownloadV2CapturedRequest | undefined {
    const canceledRequest = this.requestCapture.cancelRequest(guid);
    this.cancelPlatformPendingRequest(canceledRequest);
    return canceledRequest;
  }

  listTasks(boundary?: Partial<DownloadV2CaptureBoundary>): DownloadV2TaskEntity[] {
    return this.engine.listTasks(boundary);
  }

  findTask(guid: string): DownloadV2TaskEntity | undefined {
    return this.engine.findTask(guid);
  }

  async exportCompletedTaskToSystemDownloads(guid: string): Promise<boolean> {
    const task = this.engine.findTask(guid);
    if (task === undefined || task.status !== 'completed') {
      return false;
    }
    if ((task.persistence.finalFileUri?.trim().length ?? 0) > 0) {
      return true;
    }
    const localPath = task.persistence.tempFilePath?.trim() ?? '';
    if (localPath.length <= 0) {
      return false;
    }
    const persisted = await this.fileResolutionService.persistToSystemDownloads(localPath, task.suggestedFileName);
    if (persisted === undefined || !persisted.isExported || (persisted.finalFileUri?.trim().length ?? 0) <= 0) {
      if (persisted !== undefined) {
        this.persistCompletionLocalDisplayPath(task, persisted.finalDisplayPath);
        await this.repository.flushPersistence();
      }
      return false;
    }
    const finalFileUri = persisted.finalFileUri ?? '';
    this.engine.synchronizeTask(guid, {
      persistence: {
        tempFilePath: task.persistence.tempFilePath,
        finalFileUri: finalFileUri,
        finalDisplayPath: persisted.finalDisplayPath,
        partialFilePath: task.persistence.partialFilePath,
        finalFilePath: task.persistence.finalFilePath,
        writtenBytes: task.persistence.writtenBytes,
        etag: task.persistence.etag,
        lastModified: task.persistence.lastModified,
        acceptRanges: task.persistence.acceptRanges,
        contentRange: task.persistence.contentRange,
        validatorCapturedAt: task.persistence.validatorCapturedAt,
        downloadDriver: task.persistence.downloadDriver,
        resumeMode: task.persistence.resumeMode,
        needsFullRestart: task.persistence.needsFullRestart,
        restartReason: task.persistence.restartReason,
        segmentPlan: task.persistence.segmentPlan
      }
    });
    await this.repository.flushPersistence();
    const cleanupSucceeded = await this.cleanupLocalTempFile(
      localPath,
      task.guid,
      task.suggestedFileName,
      'manual_export'
    );
    if (cleanupSucceeded) {
      const refreshedTask = this.engine.findTask(guid) ?? task;
      this.engine.synchronizeTask(guid, {
        persistence: {
          tempFilePath: undefined,
          finalFileUri: finalFileUri,
          finalDisplayPath: persisted.finalDisplayPath,
          partialFilePath: undefined,
          finalFilePath: refreshedTask.persistence.finalFilePath,
          writtenBytes: refreshedTask.persistence.writtenBytes,
          etag: refreshedTask.persistence.etag,
          lastModified: refreshedTask.persistence.lastModified,
          acceptRanges: refreshedTask.persistence.acceptRanges,
          contentRange: refreshedTask.persistence.contentRange,
          validatorCapturedAt: refreshedTask.persistence.validatorCapturedAt,
          downloadDriver: refreshedTask.persistence.downloadDriver,
          resumeMode: refreshedTask.persistence.resumeMode,
          needsFullRestart: refreshedTask.persistence.needsFullRestart,
          restartReason: refreshedTask.persistence.restartReason,
          segmentPlan: refreshedTask.persistence.segmentPlan
        }
      });
      await this.repository.flushPersistence();
    }
    this.callbacks.onInfo?.(`已保存到系统下载目录：${task.suggestedFileName}。`);
    return true;
  }

  syncActiveSnapshots(snapshots: PlatformDownloadSnapshot[]): boolean {
    let changed = false;
    snapshots.forEach((snapshot: PlatformDownloadSnapshot) => {
      const applied = this.syncTaskFromPlatformEvent({
        type: 'updated',
        snapshot: snapshot
      }, true);
      if (applied) {
        changed = true;
      }
    });
    return changed;
  }

  removeTaskRecord(guid: string): boolean {
    return this.engine.removeTaskRecord(guid);
  }

  async deleteCompletedFileAndRemoveTaskRecord(guid: string): Promise<DownloadV2CompletedFileRemovalResult> {
    const task = this.engine.findTask(guid);
    if (task === undefined || task.status !== 'completed') {
      return {
        recordRemoved: false,
        fileStatus: 'not_found'
      };
    }
    let deletedAnyFile = false;
    try {
      const finalFileUri = task.persistence.finalFileUri?.trim() ?? '';
      if (finalFileUri.length > 0) {
        const publicDeleteResult = await this.fileResolutionService.movePublicDocumentToTrash(finalFileUri);
        deletedAnyFile = publicDeleteResult === 'deleted';
      }
      const tempFilePath = task.persistence.tempFilePath?.trim() ?? '';
      if (tempFilePath.length > 0) {
        const localDeleteResult = await this.fileResolutionService.deleteLocalPath(tempFilePath);
        if (localDeleteResult === 'deleted') {
          deletedAnyFile = true;
        }
      }
      const recordRemoved = this.engine.removeTaskRecord(guid);
      if (!recordRemoved) {
        return {
          recordRemoved: false,
          fileStatus: 'not_found'
        };
      }
      await this.repository.flushPersistence();
      return {
        recordRemoved: true,
        fileStatus: deletedAnyFile ? 'deleted' : 'missing'
      };
    } catch (error) {
      hilog.warn(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'delete completed file failed guid=%{public}s file=%{public}s error=%{public}s',
        task.guid,
        task.suggestedFileName,
        JSON.stringify(error)
      );
      return {
        recordRemoved: false,
        fileStatus: 'failed'
      };
    }
  }

  async pauseTask(guid: string): Promise<boolean> {
    const task = this.engine.findTask(guid);
    if (task === undefined) {
      return false;
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'pause request guid=%{public}s platformTaskId=%{public}s',
      task.guid,
      task.runtime.platformTaskId ?? ''
    );
    if (!await this.platformAdapter.pauseDownload(task.guid, task.runtime.platformTaskId, task.runtime.platformTaskToken)) {
      hilog.warn(DOWNLOAD_V2_SERVICE_DOMAIN, DOWNLOAD_V2_SERVICE_TAG, 'pause platform failed guid=%{public}s', task.guid);
      return false;
    }
    const updatedTask = this.engine.dispatch(task.guid, 'pause', {
      progress: {
        speedBytesPerSecond: 0
      },
      runtime: {
        platformTaskId: task.runtime.platformTaskId,
        platformTaskToken: task.runtime.platformTaskToken,
        resumeCapability: 'live_resume'
      }
    });
    this.rememberExpectedStatus(task.guid, 'paused');
    await this.repository.flushPersistence();
    void this.scheduleNextQueuedDownloads('pause');
    return updatedTask !== undefined;
  }

  async resumeTask(guid: string): Promise<boolean> {
    const task = this.engine.findTask(guid);
    if (task === undefined) {
      return false;
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'resume request guid=%{public}s status=%{public}s received=%{public}d total=%{public}d resumeCapability=%{public}s platformTaskId=%{public}s',
      task.guid,
      task.status,
      task.progress.receivedBytes,
      task.progress.totalBytes,
      task.runtime.resumeCapability,
      task.runtime.platformTaskId ?? ''
    );
    if (canContinueDownloadV2TaskFromPersistedData(task)) {
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'resume rebuild persisted task guid=%{public}s received=%{public}d',
        task.guid,
        task.progress.receivedBytes
      );
      return this.retryTask(task.guid);
    }
    const resumed = await this.platformAdapter.resumeDownload(
      task.guid,
      task.runtime.platformTaskId,
      task.runtime.platformTaskToken
    );
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'resume result guid=%{public}s resumed=%{public}s',
      task.guid,
      resumed ? 'true' : 'false'
    );
    if (!resumed) {
      hilog.warn(DOWNLOAD_V2_SERVICE_DOMAIN, DOWNLOAD_V2_SERVICE_TAG, 'resume platform failed guid=%{public}s', task.guid);
      await this.markTaskResumeUnavailable(task);
      return false;
    }
    const updatedTask = this.engine.dispatch(task.guid, 'resume', {
      progress: {
        speedBytesPerSecond: 0
      },
      runtime: {
        platformTaskId: task.runtime.platformTaskId,
        platformTaskToken: task.runtime.platformTaskToken,
        resumeCapability: 'live_resume'
      },
      failure: buildDownloadV2EmptyFailure()
    });
    this.rememberExpectedStatus(task.guid, 'running');
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'resume dispatch guid=%{public}s updated=%{public}s nextStatus=%{public}s nextResumeCapability=%{public}s',
      task.guid,
      updatedTask !== undefined ? 'true' : 'false',
      updatedTask?.status ?? 'none',
      updatedTask?.runtime.resumeCapability ?? 'none'
    );
    await this.repository.flushPersistence();
    return updatedTask !== undefined;
  }

  async retryTask(guid: string): Promise<boolean> {
    const task = this.engine.findTask(guid);
    if (task === undefined) {
      return false;
    }
    const tempFilePath = task.persistence.tempFilePath?.trim() ?? '';
    if (tempFilePath.length <= 0) {
      return false;
    }
    const retried = await this.platformAdapter.retryDownload(
      task.guid,
      tempFilePath,
      task.runtime.platformTaskId,
      task.runtime.platformTaskToken,
      this.resolveTaskHlsSegmentConcurrency(task)
    );
    if (!retried) {
      const restartedSnapshot = await this.restartTaskFromPersistedRequest(task, tempFilePath);
      if (restartedSnapshot === undefined) {
        return false;
      }
      const restartedTask = this.engine.dispatch(task.guid, 'retry', {
        progress: {
          totalBytes: restartedSnapshot.totalBytes > 0 ? restartedSnapshot.totalBytes : task.progress.totalBytes,
          receivedBytes: restartedSnapshot.receivedBytes,
          speedBytesPerSecond: restartedSnapshot.currentSpeed
        },
        runtime: {
          platformTaskId: restartedSnapshot.platformTaskId,
          platformTaskToken: restartedSnapshot.platformTaskToken,
          resumeCapability: this.resolveResumeCapability(restartedSnapshot.state)
        },
        failure: buildDownloadV2EmptyFailure(),
        timing: {
          startedAt: Date.now()
        }
      });
      this.rememberExpectedStatus(task.guid, 'running');
      await this.repository.flushPersistence();
      return restartedTask !== undefined;
    }
    const updatedTask = this.engine.dispatch(task.guid, 'retry', {
      progress: {
        receivedBytes: 0,
        speedBytesPerSecond: 0
      },
      runtime: {
        platformTaskId: task.runtime.platformTaskId,
        platformTaskToken: task.runtime.platformTaskToken,
        resumeCapability: 'live_resume'
      },
      failure: buildDownloadV2EmptyFailure(),
      timing: {
        startedAt: Date.now()
      }
    });
    this.rememberExpectedStatus(task.guid, 'running');
    await this.repository.flushPersistence();
    return updatedTask !== undefined;
  }

  async cancelTask(guid: string): Promise<boolean> {
    const task = this.engine.findTask(guid);
    if (task === undefined) {
      return false;
    }
    if (!await this.platformAdapter.cancelDownload(task.guid, task.runtime.platformTaskId, task.runtime.platformTaskToken)) {
      if (!this.canCancelTaskLocally(task)) {
        return false;
      }
      return this.cancelTaskLocally(task);
    }
    const updatedTask = this.engine.dispatch(task.guid, 'cancel', {
      progress: {
        speedBytesPerSecond: 0
      },
      failure: {
        code: 'canceled',
        sourceCode: task.failure.sourceCode,
        message: '下载已取消。',
        retriable: false
      },
      runtime: {
        platformTaskId: task.runtime.platformTaskId,
        platformTaskToken: task.runtime.platformTaskToken,
        resumeCapability: 'none'
      }
    });
    await this.repository.flushPersistence();
    void this.scheduleNextQueuedDownloads('cancel');
    return updatedTask !== undefined;
  }

  async cancelAndRemoveTask(guid: string): Promise<boolean> {
    const task = this.engine.findTask(guid);
    if (task === undefined) {
      return false;
    }
    const canceled = task.status === 'canceled' ? true : await this.cancelTask(guid);
    const latestTask = this.engine.findTask(guid) ?? task;
    if (!canceled && !this.canRemoveTaskLocally(latestTask)) {
      return false;
    }
    await this.cleanupLocalTempFile(latestTask.persistence.tempFilePath, latestTask.guid, latestTask.suggestedFileName, 'remove');
    const removed = this.engine.removeTaskRecord(guid);
    await this.repository.flushPersistence();
    return removed;
  }

  private shouldRequireConfirmation(boundary: DownloadV2CaptureBoundary): boolean {
    return this.downloadPolicyService.resolveSavePolicy({
      windowId: boundary.windowId,
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope,
      sourcePageUrl: boundary.sourcePageUrl
    }).requiresConfirmation;
  }

  private async startCapturedRequest(
    request: DownloadV2CapturedRequest,
    requiresConfirmation: boolean,
    source: string
  ): Promise<DownloadV2TaskEntity | undefined> {
    const requestToStart = requiresConfirmation
      ? request
      : (this.requestCapture.confirmRequest(request.guid) ?? request);
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'start captured request guid=%{public}s source=%{public}s requiresConfirmation=%{public}s',
      request.guid,
      source,
      requiresConfirmation ? 'true' : 'false'
    );
    this.downloadTriggerDiagnosticsService.recordCapturedRequest(
      source === 'platform_before_download' ? 'arkweb_delegate' : 'manual',
      requestToStart,
      'captured',
      source
    );
    return this.createTaskFromCapturedRequest(requestToStart, requiresConfirmation);
  }

  private shouldIgnoreDuplicatePlatformBeforeDownload(snapshot: PlatformDownloadSnapshot): boolean {
    const guid = snapshot.guid.trim();
    if (guid.length <= 0) {
      return false;
    }
    if (this.requestCapture.getPendingRequest(guid)?.platformSnapshot !== undefined) {
      return true;
    }
    const task = this.engine.findTask(guid);
    return task !== undefined && !isDownloadV2TerminalStatus(task.status);
  }

  private cancelPlatformPendingRequest(request?: DownloadV2CapturedRequest): void {
    if (request?.platformSnapshot === undefined) {
      return;
    }
    this.platformAdapter.cancelPendingDownload(request.guid);
  }

  private bindRequestCaptureCallbacks(): void {
    this.requestCapture.setCallbacks({
      onPromptChanged: (prompt?: DownloadV2Prompt) => {
        this.callbacks.onPromptChanged?.(prompt);
      }
    });
  }

  private startInitializationOnDemand(): void {
    void this.initialize().catch((_error: Error): void => {});
  }

  private async createTaskFromCapturedRequest(
    request: DownloadV2CapturedRequest,
    requiresConfirmation: boolean,
    confirmedFileName?: string
  ): Promise<DownloadV2TaskEntity | undefined> {
    await this.initialize();
    let resolvedRequest: DownloadHtmlRedirectResolution = {
      resolved: false,
      request: request
    };
    if (request.platformSnapshot === undefined) {
      resolvedRequest = await this.htmlRedirectResolverService.resolve(request);
    }
    const requestToCreate = resolvedRequest.request;
    const normalizedConfirmedFileName = confirmedFileName?.trim() ?? '';
    if (normalizedConfirmedFileName.length > 0) {
      const userFileName = this.fileNameService.ensureExtension(
        normalizedConfirmedFileName,
        requestToCreate.mimeType,
        requestToCreate.url
      );
      requestToCreate.suggestedFileName = userFileName;
      if (requestToCreate.platformSnapshot !== undefined) {
        requestToCreate.platformSnapshot.suggestedFileName = userFileName;
      }
    }
    if (!this.downloadPolicyService.canWriteSessionTasks({
      windowId: requestToCreate.boundary.windowId,
      profileId: requestToCreate.boundary.profileId,
      privacyMode: requestToCreate.boundary.privacyMode,
      dataScope: requestToCreate.boundary.dataScope,
      sourcePageUrl: requestToCreate.boundary.sourcePageUrl
    })) {
      return undefined;
    }
    if (resolvedRequest.resolved) {
      this.downloadTriggerDiagnosticsService.recordCapturedRequest(
        'html_redirect',
        requestToCreate,
        'captured',
        'resolved'
      );
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'create task begin guid=%{public}s file=%{public}s url=%{public}s snapshot=%{public}s confirm=%{public}s htmlRedirect=%{public}s boundary=%{public}s/%{public}s/%{public}s/%{public}s',
      requestToCreate.guid,
      requestToCreate.suggestedFileName,
      requestToCreate.url,
      requestToCreate.platformSnapshot !== undefined ? 'yes' : 'no',
      requiresConfirmation ? 'true' : 'false',
      resolvedRequest.resolved ? 'true' : 'false',
      requestToCreate.boundary.windowId,
      requestToCreate.boundary.profileId,
      requestToCreate.boundary.privacyMode,
      requestToCreate.boundary.dataScope
    );
    const createdTask = this.engine.createTask({
      guid: requestToCreate.guid,
      suggestedFileName: requestToCreate.suggestedFileName,
      request: {
        url: requestToCreate.url,
        originalUrl: requestToCreate.originalUrl,
        method: requestToCreate.method,
        sourcePageUrl: requestToCreate.sourcePageUrl,
        sourceHost: requestToCreate.sourceHost,
        userAgent: requestToCreate.userAgent,
        referer: requestToCreate.referer,
        mimeType: requestToCreate.mimeType,
        contentDisposition: requestToCreate.contentDisposition,
        headers: requestToCreate.headers
      },
      boundary: createDownloadV2BoundarySnapshot(
        requestToCreate.boundary.profileId,
        requestToCreate.boundary.privacyMode,
        requestToCreate.boundary.dataScope,
        requestToCreate.boundary.windowId
      ),
      progress: {
        totalBytes: requestToCreate.totalBytes,
        receivedBytes: 0,
        speedBytesPerSecond: 0
      },
      requiresConfirmation: requiresConfirmation
    });
    const queuedTask = requiresConfirmation
      ? (this.engine.dispatch(createdTask.guid, 'confirm') ?? createdTask)
      : createdTask;
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'create task queued guid=%{public}s status=%{public}s',
      queuedTask.guid,
      queuedTask.status
    );
    const targetPlan = await this.downloadTargetResolutionService.resolveTargetPlan(requestToCreate);
    if (targetPlan === undefined) {
      hilog.error(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'create task target resolve failed guid=%{public}s file=%{public}s',
        requestToCreate.guid,
        requestToCreate.suggestedFileName
      );
      this.engine.dispatch(queuedTask.guid, 'fail', {
        failure: {
          code: 'file_system',
          message: '下载启动失败：无法创建本地保存目录。',
          retriable: true
        }
      });
      await this.repository.flushPersistence();
      this.callbacks.onError?.('下载启动失败：无法创建本地保存目录。');
      return this.engine.findTask(queuedTask.guid);
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'create task target resolved guid=%{public}s path=%{public}s display=%{public}s mode=%{public}s export=%{public}s',
      requestToCreate.guid,
      targetPlan.tempFilePath,
      targetPlan.initialDisplayPath,
      targetPlan.storageMode,
      targetPlan.completionExportPolicy
    );
    const sourceSnapshot = requestToCreate.platformSnapshot;
    const downloadDriver = this.resolveInitialDownloadDriver();
    this.downloadTriggerDiagnosticsService.recordDriverSelection(requestToCreate, downloadDriver);
    const preparedTask = this.engine.synchronizeTask(queuedTask.guid, {
      resolvedFileName: targetPlan.fileName,
      persistence: {
        tempFilePath: targetPlan.tempFilePath,
        finalFileUri: queuedTask.persistence.finalFileUri,
        finalDisplayPath: targetPlan.initialDisplayPath,
        partialFilePath: targetPlan.partialFilePath,
        writtenBytes: 0,
        downloadDriver: downloadDriver,
        resumeMode: 'platform_live_resume',
        needsFullRestart: false,
        segmentPlan: undefined
      },
      runtime: {
        platformTaskId: '',
        platformTaskToken: undefined,
        resumeCapability: sourceSnapshot === undefined ? 'none' : this.resolveResumeCapability(sourceSnapshot.state)
      }
    });
    await this.repository.flushPersistence();
    const latestPreparedTask = this.engine.findTask(queuedTask.guid) ?? preparedTask ?? queuedTask;
    const admission = this.downloadQueuePolicyService.resolveStartAdmission(
      this.engine.listTasks(),
      latestPreparedTask.guid,
      this.downloadNetworkPolicyService.resolveStartAdmission()
    );
    if (!admission.canStartNow) {
      this.persistQueuedAdmissionReason(latestPreparedTask, admission.reason);
      await this.repository.flushPersistence();
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'create task queued for scheduler guid=%{public}s reason=%{public}s running=%{public}d queued=%{public}d max=%{public}d network=%{public}s',
        latestPreparedTask.guid,
        admission.reason,
        admission.runningCount,
        admission.queuedCount,
        admission.maxConcurrentDownloads,
        admission.networkMessage ?? ''
      );
      this.notifyQueuedAdmission(requestToCreate.suggestedFileName, admission.reason);
      return latestPreparedTask;
    }
    await this.startPreparedTaskFromRequest(requestToCreate, latestPreparedTask, 'create_task');
    return preparedTask ?? this.engine.findTask(queuedTask.guid);
  }

  private resolveInitialDownloadDriver(): DownloadV2Driver {
    return 'libcurl';
  }

  private async startPreparedTaskFromRequest(
    request: DownloadV2CapturedRequest,
    task: DownloadV2TaskEntity,
    reason: string
  ): Promise<boolean> {
    const targetPath = task.persistence.tempFilePath?.trim() ?? '';
    const downloadDriver = task.persistence.downloadDriver ?? 'libcurl';
    if (targetPath.length <= 0 || task.status !== 'queued') {
      hilog.warn(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'start prepared rejected guid=%{public}s reason=%{public}s status=%{public}s path=%{public}s driver=%{public}s',
        task.guid,
        reason,
        task.status,
        targetPath,
        downloadDriver
      );
      return false;
    }
    const admission = this.downloadQueuePolicyService.resolveStartAdmission(
      this.engine.listTasks(),
      task.guid,
      this.downloadNetworkPolicyService.resolveStartAdmission()
    );
    if (!admission.canStartNow) {
      this.persistQueuedAdmissionReason(task, admission.reason);
      await this.repository.flushPersistence();
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'start prepared deferred guid=%{public}s reason=%{public}s running=%{public}d queued=%{public}d max=%{public}d network=%{public}s',
        task.guid,
        admission.reason,
        admission.runningCount,
        admission.queuedCount,
        admission.maxConcurrentDownloads,
        admission.networkMessage ?? ''
      );
      return false;
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'start prepared begin guid=%{public}s reason=%{public}s path=%{public}s driver=%{public}s',
      request.guid,
      reason,
      targetPath,
      downloadDriver
    );
    const startedSnapshot = await this.startDirectRequest(request, targetPath);
    if (startedSnapshot === undefined) {
      await this.failPreparedTaskStart(task, request, downloadDriver);
      return false;
    }
    this.downloadTriggerDiagnosticsService.recordStartResult(request, true, downloadDriver);
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'start prepared accepted guid=%{public}s state=%{public}s taskId=%{public}s received=%{public}d total=%{public}d reason=%{public}s',
      request.guid,
      startedSnapshot.state,
      startedSnapshot.platformTaskId ?? '',
      startedSnapshot.receivedBytes,
      startedSnapshot.totalBytes,
      reason
    );
    this.syncTaskFromPlatformEvent({
      type: 'updated',
      snapshot: startedSnapshot
    });
    this.markStartedSnapshotAccepted(task.guid, startedSnapshot);
    this.callbacks.onInfo?.(`开始下载 ${request.suggestedFileName}。`);
    return true;
  }

  private async failPreparedTaskStart(
    task: DownloadV2TaskEntity,
    request: DownloadV2CapturedRequest,
    downloadDriver: DownloadV2Driver
  ): Promise<void> {
    this.downloadTriggerDiagnosticsService.recordStartResult(
      request,
      false,
      downloadDriver,
      'adapter_start_failed'
    );
    hilog.error(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'start prepared failed guid=%{public}s path=%{public}s driver=%{public}s',
      request.guid,
      task.persistence.tempFilePath ?? '',
      downloadDriver
    );
    this.engine.dispatch(task.guid, 'fail', {
      failure: {
        code: 'unknown',
        message: `下载启动失败：${request.suggestedFileName}。`,
        retriable: true
      }
    });
    await this.repository.flushPersistence();
    this.callbacks.onError?.(`下载启动失败：${request.suggestedFileName}。`);
    void this.scheduleNextQueuedDownloads('start_failed');
  }

  private markStartedSnapshotAccepted(guid: string, snapshot: PlatformDownloadSnapshot): void {
    const latestTask = this.engine.findTask(guid);
    if (latestTask === undefined || latestTask.status !== 'queued') {
      return;
    }
    const nextPersistence = this.mergePersistenceSnapshot(latestTask, snapshot, {
      totalBytes: snapshot.totalBytes,
      receivedBytes: Math.max(latestTask.progress.receivedBytes, snapshot.receivedBytes),
      speedBytesPerSecond: snapshot.currentSpeed
    });
    nextPersistence.restartReason = undefined;
    nextPersistence.needsFullRestart = false;
    const startedTask = this.engine.dispatch(guid, 'start', {
      progress: {
        totalBytes: snapshot.totalBytes > 0 ? snapshot.totalBytes : latestTask.progress.totalBytes,
        receivedBytes: Math.max(latestTask.progress.receivedBytes, snapshot.receivedBytes),
        speedBytesPerSecond: snapshot.currentSpeed
      },
      persistence: nextPersistence,
      runtime: {
        platformTaskId: snapshot.platformTaskId ?? latestTask.runtime.platformTaskId,
        platformTaskToken: snapshot.platformTaskToken ?? latestTask.runtime.platformTaskToken,
        resumeCapability: this.resolveResumeCapability(snapshot.state)
      },
      failure: buildDownloadV2EmptyFailure(),
      timing: {
        startedAt: Date.now()
      }
    });
    if (startedTask !== undefined) {
      this.rememberExpectedStatus(guid, 'running');
    }
  }

  private async scheduleNextQueuedDownloads(reason: string): Promise<void> {
    if (this.isQueueScheduling) {
      return;
    }
    this.isQueueScheduling = true;
    try {
      while (true) {
        const plan = this.downloadQueuePolicyService.buildSchedulePlan(
          this.engine.listTasks(),
          this.downloadNetworkPolicyService.resolveStartAdmission()
        );
        if (!plan.canStartNow || plan.nextGuid === undefined) {
          this.logQueueScheduleIdle(reason, plan);
          return;
        }
        const task = this.engine.findTask(plan.nextGuid);
        if (task === undefined || task.status !== 'queued') {
          return;
        }
        const request = this.buildCapturedRequestFromTask(task);
        const started = await this.startPreparedTaskFromRequest(request, task, reason);
        if (!started) {
          const afterFailurePlan = this.downloadQueuePolicyService.buildSchedulePlan(
            this.engine.listTasks(),
            this.downloadNetworkPolicyService.resolveStartAdmission()
          );
          if (!afterFailurePlan.canStartNow || afterFailurePlan.nextGuid === undefined) {
            return;
          }
        }
      }
    } finally {
      this.isQueueScheduling = false;
    }
  }

  private logQueueScheduleIdle(reason: string, plan: DownloadQueueSchedulePlan): void {
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'queue schedule idle reason=%{public}s admission=%{public}s running=%{public}d queued=%{public}d max=%{public}d network=%{public}s',
      reason,
      plan.reason,
      plan.runningCount,
      plan.queuedCount,
      plan.maxConcurrentDownloads,
      plan.networkMessage ?? ''
    );
  }

  private notifyQueuedAdmission(
    suggestedFileName: string,
    reason: 'concurrency_limit' | 'waiting_wifi' | 'offline_network' | 'network_unknown' | 'not_startable' | 'start_now'
  ): void {
    if (reason === 'concurrency_limit') {
      this.callbacks.onInfo?.(`已加入下载队列：${suggestedFileName}。`);
      return;
    }
    if (reason === 'waiting_wifi') {
      this.callbacks.onInfo?.(`已加入下载队列，连接 WLAN 后开始下载：${suggestedFileName}。`);
      return;
    }
    if (reason === 'offline_network') {
      this.callbacks.onInfo?.(`网络不可用，已加入下载队列：${suggestedFileName}。`);
      return;
    }
    if (reason === 'network_unknown') {
      this.callbacks.onInfo?.(`无法确认网络类型，已暂缓下载：${suggestedFileName}。`);
    }
  }

  private persistQueuedAdmissionReason(
    task: DownloadV2TaskEntity,
    reason: 'concurrency_limit' | 'waiting_wifi' | 'offline_network' | 'network_unknown' | 'not_startable' | 'start_now'
  ): void {
    const restartReason = this.resolveQueuedRestartReason(reason);
    this.engine.synchronizeTask(task.guid, {
      persistence: {
        tempFilePath: task.persistence.tempFilePath,
        finalFileUri: task.persistence.finalFileUri,
        finalDisplayPath: task.persistence.finalDisplayPath,
        partialFilePath: task.persistence.partialFilePath,
        finalFilePath: task.persistence.finalFilePath,
        writtenBytes: task.persistence.writtenBytes,
        etag: task.persistence.etag,
        lastModified: task.persistence.lastModified,
        acceptRanges: task.persistence.acceptRanges,
        contentRange: task.persistence.contentRange,
        validatorCapturedAt: task.persistence.validatorCapturedAt,
        downloadDriver: task.persistence.downloadDriver,
        resumeMode: task.persistence.resumeMode,
        needsFullRestart: task.persistence.needsFullRestart,
        restartReason: restartReason,
        segmentPlan: task.persistence.segmentPlan
      }
    });
  }

  private resolveQueuedRestartReason(
    reason: 'concurrency_limit' | 'waiting_wifi' | 'offline_network' | 'network_unknown' | 'not_startable' | 'start_now'
  ): string | undefined {
    switch (reason) {
      case 'concurrency_limit':
        return 'queued_concurrency_limit';
      case 'waiting_wifi':
        return 'waiting_wifi';
      case 'offline_network':
        return 'waiting_network';
      case 'network_unknown':
        return 'network_unknown';
      default:
        return undefined;
    }
  }

  private buildCapturedRequestFromTask(task: DownloadV2TaskEntity): DownloadV2CapturedRequest {
    return {
      guid: task.guid,
      url: task.request.url,
      originalUrl: task.request.originalUrl,
      suggestedFileName: task.resolvedFileName ?? task.suggestedFileName,
      sourceHost: task.request.sourceHost ?? '',
      totalBytes: task.progress.totalBytes,
      mimeType: task.request.mimeType,
      method: task.request.method,
      userAgent: task.request.userAgent,
      referer: task.request.referer,
      contentDisposition: task.request.contentDisposition,
      headers: task.request.headers,
      sourcePageUrl: task.request.sourcePageUrl,
      platformSnapshot: undefined,
      boundary: {
        windowId: task.windowId ?? '',
        profileId: task.profileId,
        privacyMode: task.privacyMode,
        dataScope: task.dataScope,
        sourcePageUrl: task.request.sourcePageUrl
      },
      createdAt: task.timing.createdAt
    };
  }

  private buildPlatformSnapshotFromTask(task: DownloadV2TaskEntity): PlatformDownloadSnapshot {
    return {
      guid: task.guid,
      url: task.request.url,
      originalUrl: task.request.originalUrl,
      suggestedFileName: task.resolvedFileName ?? task.suggestedFileName,
      totalBytes: task.progress.totalBytes,
      receivedBytes: task.progress.receivedBytes,
      currentSpeed: task.progress.speedBytesPerSecond,
      state: 'PENDING',
      lastErrorCode: task.failure.sourceCode ?? 0,
      mimeType: task.request.mimeType,
      method: task.request.method,
      userAgent: task.request.userAgent,
      referer: task.request.referer,
      contentDisposition: task.request.contentDisposition,
      headers: task.request.headers,
      hlsSegmentConcurrency: this.resolveTaskHlsSegmentConcurrency(task),
      platformTaskId: task.runtime.platformTaskId,
      platformTaskToken: task.runtime.platformTaskToken
    };
  }

  private syncTaskFromPlatformEvent(event: PlatformDownloadEvent, silent: boolean = false): boolean {
    const currentTask = this.engine.findTask(event.snapshot.guid);
    if (currentTask === undefined) {
      return false;
    }
    if (this.shouldSuppressStaleControlEcho(currentTask, event.snapshot.state)) {
      return true;
    }
    const nextRequest = this.mergeRequestContext(currentTask.request, event);
    const resolvedEventFileName = this.fileNameService.resolveFileName({
      suggestedFileName: event.snapshot.suggestedFileName.length > 0
        ? event.snapshot.suggestedFileName
        : currentTask.resolvedFileName ?? currentTask.suggestedFileName,
      url: event.snapshot.url.length > 0 ? event.snapshot.url : currentTask.request.url,
      mimeType: event.snapshot.mimeType ?? nextRequest.mimeType,
      contentDisposition: event.snapshot.contentDisposition ?? nextRequest.contentDisposition
    });
    const nextRuntime: Partial<DownloadV2RuntimeSnapshot> = {
      platformTaskId: event.snapshot.platformTaskId ?? currentTask.runtime.platformTaskId,
      platformTaskToken: event.snapshot.platformTaskToken ?? currentTask.runtime.platformTaskToken,
      resumeCapability: this.resolveResumeCapability(event.snapshot.state)
    };
    const nextProgress: Partial<DownloadV2ProgressSnapshot> = {
      totalBytes: event.snapshot.totalBytes > 0 ? event.snapshot.totalBytes : currentTask.progress.totalBytes,
      receivedBytes: Math.max(currentTask.progress.receivedBytes, event.snapshot.receivedBytes),
      speedBytesPerSecond: event.snapshot.currentSpeed
    };
    const nextFailure = this.buildFailureFromPlatformEvent(event, currentTask.failure);
    const eventName = this.resolveEngineEvent(currentTask.status, event);
    const isPausing = this.isPausingState(event.snapshot.state);
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'platform sync guid=%{public}s currentStatus=%{public}s platformState=%{public}s eventType=%{public}s mappedEvent=%{public}s received=%{public}d total=%{public}d speed=%{public}d resume=%{public}s taskId=%{public}s',
      currentTask.guid,
      currentTask.status,
      event.snapshot.state,
      event.type,
      eventName ?? (isPausing ? 'noop_pausing' : 'none'),
      event.snapshot.receivedBytes,
      event.snapshot.totalBytes,
      event.snapshot.currentSpeed,
      nextRuntime.resumeCapability ?? currentTask.runtime.resumeCapability,
      nextRuntime.platformTaskId ?? currentTask.runtime.platformTaskId ?? ''
    );
    if (eventName === undefined) {
      return isPausing;
    }
    const nextPersistence = this.mergePersistenceSnapshot(currentTask, event.snapshot, nextProgress);
    if (eventName === 'start' || eventName === 'resume') {
      nextPersistence.restartReason = undefined;
      nextPersistence.needsFullRestart = false;
    }
    const patch: MutableDownloadV2TaskEntityPatch = {
      request: nextRequest,
      resolvedFileName: resolvedEventFileName,
      progress: nextProgress,
      persistence: nextPersistence,
      runtime: nextRuntime,
      failure: nextFailure
    };
    const previousStatus = currentTask.status;
    const updated = this.engine.dispatch(currentTask.guid, eventName, patch);
    if (updated === undefined) {
      return false;
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'platform sync applied guid=%{public}s nextStatus=%{public}s received=%{public}d total=%{public}d speed=%{public}d resume=%{public}s',
      updated.guid,
      updated.status,
      updated.progress.receivedBytes,
      updated.progress.totalBytes,
      updated.progress.speedBytesPerSecond,
      updated.runtime.resumeCapability
    );
    this.clearExpectedStatusIfReached(updated);
    void this.flushSideEffectsForPlatformEvent(updated, event, silent, previousStatus);
    return true;
  }

  private mergePersistenceSnapshot(
    currentTask: DownloadV2TaskEntity,
    snapshot: PlatformDownloadSnapshot,
    progress?: Partial<DownloadV2ProgressSnapshot>
  ): DownloadV2PersistenceSnapshot {
    const receivedBytes = progress?.receivedBytes ?? currentTask.progress.receivedBytes;
    return {
      tempFilePath: currentTask.persistence.tempFilePath,
      finalFileUri: currentTask.persistence.finalFileUri,
      finalDisplayPath: currentTask.persistence.finalDisplayPath,
      partialFilePath: currentTask.persistence.partialFilePath ?? currentTask.persistence.tempFilePath,
      finalFilePath: currentTask.persistence.finalFilePath,
      writtenBytes: receivedBytes,
      etag: currentTask.persistence.etag,
      lastModified: currentTask.persistence.lastModified,
      acceptRanges: currentTask.persistence.acceptRanges,
      contentRange: currentTask.persistence.contentRange,
      validatorCapturedAt: currentTask.persistence.validatorCapturedAt,
      downloadDriver: currentTask.persistence.downloadDriver ?? 'libcurl',
      resumeMode: currentTask.persistence.resumeMode ?? 'platform_live_resume',
      needsFullRestart: currentTask.persistence.needsFullRestart,
      restartReason: currentTask.persistence.restartReason,
      segmentPlan: currentTask.persistence.segmentPlan
    };
  }

  private async startPlatformSnapshotRequest(
    guid: string,
    targetPath: string,
    snapshot: PlatformDownloadSnapshot
  ): Promise<PlatformDownloadSnapshot | undefined> {
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'start snapshot request guid=%{public}s path=%{public}s existingState=%{public}s taskId=%{public}s',
      guid,
      targetPath,
      snapshot.state,
      snapshot.platformTaskId ?? ''
    );
    const started = await this.platformAdapter.startDownload(guid, targetPath);
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'start snapshot platform result guid=%{public}s started=%{public}s',
      guid,
      started ? 'true' : 'false'
    );
    if (!started) {
      return undefined;
    }
    const activeSnapshot = this.platformAdapter.getActiveDownloadSnapshot(guid);
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'start snapshot active lookup guid=%{public}s found=%{public}s',
      guid,
      activeSnapshot !== undefined ? 'true' : 'false'
    );
    return activeSnapshot ?? {
      guid: snapshot.guid,
      url: snapshot.url,
      originalUrl: snapshot.originalUrl,
      suggestedFileName: snapshot.suggestedFileName,
      totalBytes: snapshot.totalBytes,
      receivedBytes: snapshot.receivedBytes,
      currentSpeed: snapshot.currentSpeed,
      state: 'PENDING',
      lastErrorCode: snapshot.lastErrorCode,
      mimeType: snapshot.mimeType,
      method: snapshot.method,
      userAgent: snapshot.userAgent,
      referer: snapshot.referer,
      contentDisposition: snapshot.contentDisposition,
      headers: snapshot.headers,
      platformTaskId: snapshot.platformTaskId,
      platformTaskToken: snapshot.platformTaskToken
    };
  }

  private startDirectRequest(
    request: DownloadV2CapturedRequest,
    targetPath: string
  ): Promise<PlatformDownloadSnapshot | undefined> {
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'start direct request guid=%{public}s path=%{public}s method=%{public}s url=%{public}s',
      request.guid,
      targetPath,
      request.method,
      request.url
    );
    return this.platformAdapter.startDirectDownload({
      guid: request.guid,
      url: request.url,
      originalUrl: request.originalUrl,
      suggestedFileName: request.suggestedFileName,
      totalBytes: request.totalBytes,
      receivedBytes: 0,
      currentSpeed: 0,
      state: 'PENDING',
      lastErrorCode: 0,
      mimeType: request.mimeType,
      method: request.method,
      userAgent: request.userAgent,
      referer: request.referer,
      contentDisposition: request.contentDisposition,
      headers: request.headers,
      hlsSegmentConcurrency: this.resolveHlsSegmentConcurrency(request.boundary),
      platformTaskToken: request.platformSnapshot?.platformTaskToken
    }, targetPath).then((snapshot?: PlatformDownloadSnapshot) => {
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'start direct result guid=%{public}s state=%{public}s taskId=%{public}s received=%{public}d total=%{public}d',
        request.guid,
        snapshot?.state ?? 'none',
        snapshot?.platformTaskId ?? '',
        snapshot?.receivedBytes ?? -1,
        snapshot?.totalBytes ?? -1
      );
      return snapshot;
    });
  }

  private async flushSideEffectsForPlatformEvent(
    task: DownloadV2TaskEntity,
    event: PlatformDownloadEvent,
    silent: boolean = false,
    previousStatus?: DownloadV2Status
  ): Promise<void> {
    const shouldFinalizeCompletion = task.status === 'completed' && previousStatus !== 'completed' &&
      (event.type === 'finished' || this.isCompletedState(event.snapshot.state));
    if (shouldFinalizeCompletion) {
      await this.finalizeCompletedTask(task.guid, task.suggestedFileName, silent);
    } else if (task.status !== 'completed') {
      this.completedPersistenceGuids[task.guid] = undefined;
    }
    if (!silent && task.status === 'failed') {
      this.callbacks.onError?.(task.failure.message.length > 0 ? task.failure.message : `下载失败：${task.suggestedFileName}。`);
    }
    await this.repository.flushPersistence();
    if (task.status === 'completed' || task.status === 'failed' || task.status === 'canceled') {
      void this.scheduleNextQueuedDownloads('platform_terminal');
    }
  }

  private async finalizeCompletedTask(guid: string, suggestedFileName: string, silent: boolean = false): Promise<void> {
    const currentTask = this.engine.findTask(guid);
    if (currentTask === undefined) {
      return;
    }
    if (this.completedPersistenceGuids[guid] === true) {
      this.recordDownloadActivityOnce(guid);
      return;
    }
    if ((currentTask.persistence.finalFileUri?.trim().length ?? 0) > 0) {
      this.completedPersistenceGuids[guid] = true;
      this.recordDownloadActivityOnce(guid);
      if (!silent) {
        this.callbacks.onInfo?.(`下载完成，已保存到系统下载目录：${suggestedFileName}。`);
      }
      return;
    }
    this.completedPersistenceGuids[guid] = true;
    const localPath = currentTask.persistence.tempFilePath?.trim() ?? '';
    if (localPath.length <= 0) {
      this.recordDownloadActivityOnce(guid);
      if (!silent) {
        this.callbacks.onInfo?.(`下载完成：${suggestedFileName}。`);
      }
      return;
    }
    const completionPolicy = this.downloadTargetResolutionService.resolveCompletionTargetPolicy({
      windowId: currentTask.windowId,
      profileId: currentTask.profileId,
      privacyMode: currentTask.privacyMode,
      dataScope: currentTask.dataScope,
      sourcePageUrl: currentTask.request.sourcePageUrl
    }, suggestedFileName);
    if (!completionPolicy.shouldPromptForExport) {
      this.completedPersistenceGuids[guid] = true;
      this.recordDownloadActivityOnce(guid);
      this.persistCompletionLocalDisplayPath(currentTask, completionPolicy.tempDisplayPath);
      await this.repository.flushPersistence();
      if (!silent) {
        this.callbacks.onInfo?.(completionPolicy.completionMessage);
      }
      return;
    }
    const persisted = await this.fileResolutionService.persistToSystemDownloads(localPath, suggestedFileName);
    if (persisted === undefined || !persisted.isExported || (persisted.finalFileUri?.trim().length ?? 0) <= 0) {
      this.completedPersistenceGuids[guid] = true;
      this.recordDownloadActivityOnce(guid);
      const fallbackDisplayPath = persisted?.finalDisplayPath ?? completionPolicy.tempDisplayPath;
      this.persistCompletionLocalDisplayPath(currentTask, fallbackDisplayPath);
      await this.repository.flushPersistence();
      if (!silent) {
        const message = persisted?.status === 'failed'
          ? `下载完成，但自动导出到系统下载目录失败。文件仍保存在 Aira 临时下载目录：${suggestedFileName}。`
          : `下载完成，未导出到系统下载目录。文件仍保存在 Aira 临时下载目录：${suggestedFileName}。`;
        this.callbacks.onInfo?.(message);
      }
      return;
    }
    this.recordDownloadActivityOnce(guid);
    this.engine.synchronizeTask(guid, {
      persistence: {
        tempFilePath: currentTask.persistence.tempFilePath,
        finalFileUri: persisted.finalFileUri,
        finalDisplayPath: persisted.finalDisplayPath,
        partialFilePath: currentTask.persistence.partialFilePath,
        finalFilePath: currentTask.persistence.finalFilePath,
        writtenBytes: currentTask.persistence.writtenBytes,
        etag: currentTask.persistence.etag,
        lastModified: currentTask.persistence.lastModified,
        acceptRanges: currentTask.persistence.acceptRanges,
        contentRange: currentTask.persistence.contentRange,
        validatorCapturedAt: currentTask.persistence.validatorCapturedAt,
        downloadDriver: currentTask.persistence.downloadDriver,
        resumeMode: currentTask.persistence.resumeMode,
        needsFullRestart: currentTask.persistence.needsFullRestart,
        restartReason: currentTask.persistence.restartReason,
        segmentPlan: currentTask.persistence.segmentPlan
      }
    });
    await this.repository.flushPersistence();
    const cleanupSucceeded = await this.cleanupLocalTempFile(
      localPath,
      currentTask.guid,
      currentTask.suggestedFileName,
      'completed_export'
    );
    if (cleanupSucceeded) {
      const refreshedTask = this.engine.findTask(guid) ?? currentTask;
      this.engine.synchronizeTask(guid, {
        persistence: {
          tempFilePath: undefined,
          finalFileUri: persisted.finalFileUri,
          finalDisplayPath: persisted.finalDisplayPath,
          partialFilePath: undefined,
          finalFilePath: refreshedTask.persistence.finalFilePath,
          writtenBytes: refreshedTask.persistence.writtenBytes,
          etag: refreshedTask.persistence.etag,
          lastModified: refreshedTask.persistence.lastModified,
          acceptRanges: refreshedTask.persistence.acceptRanges,
          contentRange: refreshedTask.persistence.contentRange,
          validatorCapturedAt: refreshedTask.persistence.validatorCapturedAt,
          downloadDriver: refreshedTask.persistence.downloadDriver,
          resumeMode: refreshedTask.persistence.resumeMode,
          needsFullRestart: refreshedTask.persistence.needsFullRestart,
          restartReason: refreshedTask.persistence.restartReason,
          segmentPlan: refreshedTask.persistence.segmentPlan
        }
      });
      await this.repository.flushPersistence();
    }
    if (!silent) {
      this.callbacks.onInfo?.(`下载完成，已保存到系统下载目录：${suggestedFileName}。`);
    }
  }

  private persistCompletionLocalDisplayPath(task: DownloadV2TaskEntity, displayPath: string): void {
    this.engine.synchronizeTask(task.guid, {
      persistence: {
        tempFilePath: task.persistence.tempFilePath,
        finalFileUri: task.persistence.finalFileUri,
        finalDisplayPath: displayPath,
        partialFilePath: task.persistence.partialFilePath,
        finalFilePath: task.persistence.finalFilePath,
        writtenBytes: task.persistence.writtenBytes,
        etag: task.persistence.etag,
        lastModified: task.persistence.lastModified,
        acceptRanges: task.persistence.acceptRanges,
        contentRange: task.persistence.contentRange,
        validatorCapturedAt: task.persistence.validatorCapturedAt,
        downloadDriver: task.persistence.downloadDriver,
        resumeMode: task.persistence.resumeMode,
        needsFullRestart: task.persistence.needsFullRestart,
        restartReason: task.persistence.restartReason,
        segmentPlan: task.persistence.segmentPlan
      }
    });
  }

  private async markTaskResumeUnavailable(task: DownloadV2TaskEntity): Promise<void> {
    const fallbackToRetry = !this.platformAdapter.hasActiveDownload(task.guid);
    if (!fallbackToRetry) {
      return;
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'resume degraded to retry guid=%{public}s status=%{public}s platformTaskId=%{public}s',
      task.guid,
      task.status,
      task.runtime.platformTaskId ?? ''
    );
    this.expectedStatusByGuid[task.guid] = undefined;
    this.expectedStatusDeadlineByGuid[task.guid] = undefined;
    this.engine.synchronizeTask(task.guid, {
      status: 'failed',
      progress: {
        speedBytesPerSecond: 0
      },
      runtime: {
        platformTaskId: '',
        platformTaskToken: undefined,
        resumeCapability: 'retry_only'
      },
      failure: this.buildTaskLostFailure(task),
      timing: {
        updatedAt: Date.now(),
        failedAt: Date.now()
      }
    });
    await this.repository.flushPersistence();
  }

  private async restartTaskFromPersistedRequest(
    task: DownloadV2TaskEntity,
    targetPath: string
  ): Promise<PlatformDownloadSnapshot | undefined> {
    return this.platformAdapter.startDirectDownload({
      guid: task.guid,
      url: task.request.url,
      originalUrl: task.request.originalUrl,
      suggestedFileName: task.suggestedFileName,
      totalBytes: task.progress.totalBytes,
      receivedBytes: 0,
      currentSpeed: 0,
      state: 'PENDING',
      lastErrorCode: 0,
      mimeType: task.request.mimeType,
      method: task.request.method,
      userAgent: task.request.userAgent,
      referer: task.request.referer,
      contentDisposition: task.request.contentDisposition,
      headers: task.request.headers,
      hlsSegmentConcurrency: this.resolveTaskHlsSegmentConcurrency(task)
    }, targetPath);
  }

  private resolveTaskHlsSegmentConcurrency(task: DownloadV2TaskEntity): number {
    return this.resolveHlsSegmentConcurrency({
      windowId: task.windowId ?? '',
      profileId: task.profileId,
      privacyMode: task.privacyMode,
      dataScope: task.dataScope,
      sourcePageUrl: task.request.sourcePageUrl
    });
  }

  private resolveHlsSegmentConcurrency(boundary: DownloadV2CaptureBoundary): number {
    const taskBoundary: DownloadTaskBoundary = {
      windowId: boundary.windowId ?? '',
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope,
      sourcePageUrl: boundary.sourcePageUrl
    };
    const settings = this.downloadPolicyService.resolveSavePolicy(taskBoundary).settings;
    return Number(settings.hlsSegmentConcurrency);
  }

  private canCancelTaskLocally(task: DownloadV2TaskEntity): boolean {
    return !this.platformAdapter.hasActiveDownload(task.guid);
  }

  private canRemoveTaskLocally(task: DownloadV2TaskEntity): boolean {
    return !this.platformAdapter.hasActiveDownload(task.guid);
  }

  private async cancelTaskLocally(task: DownloadV2TaskEntity): Promise<boolean> {
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'cancel local fallback guid=%{public}s status=%{public}s platformTaskId=%{public}s',
      task.guid,
      task.status,
      task.runtime.platformTaskId ?? ''
    );
    const updatedTask = this.engine.dispatch(task.guid, 'cancel', {
      progress: {
        speedBytesPerSecond: 0
      },
      failure: {
        code: 'canceled',
        sourceCode: task.failure.sourceCode,
        message: '下载已取消。',
        retriable: false
      },
      runtime: {
        platformTaskId: '',
        platformTaskToken: undefined,
        resumeCapability: 'none'
      }
    });
    if (updatedTask === undefined) {
      return false;
    }
    await this.cleanupLocalTempFile(task.persistence.tempFilePath, task.guid, task.suggestedFileName, 'cancel');
    await this.repository.flushPersistence();
    void this.scheduleNextQueuedDownloads('cancel_local');
    return true;
  }

  private async cleanupLocalTempFile(
    path: string | undefined,
    guid: string,
    suggestedFileName: string,
    reason: 'cancel' | 'retry' | 'remove' | 'completed_export' | 'manual_export'
  ): Promise<boolean> {
    const localPath = path?.trim() ?? '';
    if (localPath.length <= 0) {
      return true;
    }
    try {
      const deleteResult = await this.fileResolutionService.deleteLocalPath(localPath);
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'cleanup temp file guid=%{public}s reason=%{public}s result=%{public}s path=%{public}s',
        guid,
        reason,
        deleteResult,
        localPath
      );
      return true;
    } catch (error) {
      hilog.warn(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'cleanup temp file failed guid=%{public}s reason=%{public}s path=%{public}s error=%{public}s',
        guid,
        reason,
        localPath,
        JSON.stringify(error)
      );
      if (reason !== 'retry' && reason !== 'completed_export' && reason !== 'manual_export') {
        this.callbacks.onError?.(`下载临时文件清理失败：${suggestedFileName}。`);
      }
      return false;
    }
  }

  private shouldReconnectPersistedTask(task: DownloadV2TaskEntity): boolean {
    if (!isDownloadV2ActiveStatus(task.status)) {
      return false;
    }
    return (task.runtime.platformTaskId?.trim().length ?? 0) > 0;
  }

  private markTaskRestoreUnavailable(guid: string): void {
    const currentTask = this.engine.findTask(guid);
    if (currentTask === undefined) {
      return;
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'restore degraded to failed guid=%{public}s',
      guid
    );
    this.engine.synchronizeTask(guid, {
      status: 'failed',
      progress: {
        speedBytesPerSecond: 0
      },
      runtime: {
        platformTaskId: currentTask.runtime.platformTaskId,
        platformTaskToken: currentTask.runtime.platformTaskToken,
        resumeCapability: 'retry_only'
      },
      failure: this.buildTaskLostFailure(currentTask),
      timing: {
        updatedAt: Date.now(),
        failedAt: Date.now()
      }
    });
  }

  private recordDownloadActivityOnce(guid: string): void {
    if (this.completedActivityGuids[guid] === true) {
      return;
    }
    this.completedActivityGuids[guid] = true;
    this.activityTracker?.recordDownloadComplete(Date.now());
  }

  private buildTaskLostFailure(task: DownloadV2TaskEntity): DownloadV2Failure {
    const partialBytes = Math.max(task.progress.receivedBytes, task.persistence.writtenBytes ?? 0);
    return {
      code: 'context_lost',
      sourceCode: task.failure.sourceCode,
      message: partialBytes > 0
        ? '下载已暂停，已有进度已保留。'
        : '下载连接已中断，请重试。',
      retriable: true
    };
  }

  private resolveEngineEvent(
    currentStatus: DownloadV2Status,
    event: PlatformDownloadEvent
  ): 'queue' | 'start' | 'pause' | 'resume' | 'finish' | 'fail' | 'cancel' | undefined {
    if (event.type === 'finished') {
      return 'finish';
    }
    if (event.type === 'canceled') {
      return 'cancel';
    }
    if (event.type === 'failed') {
      if (this.isCanceledState(event.snapshot.state)) {
        return 'cancel';
      }
      return 'fail';
    }
    if (this.isCompletedState(event.snapshot.state)) {
      return 'finish';
    }
    if (this.isCanceledState(event.snapshot.state)) {
      return 'cancel';
    }
    if (this.isFailureState(event.snapshot.state)) {
      return 'fail';
    }
    if (this.isPausedState(event.snapshot.state)) {
      return 'pause';
    }
    if (this.isRunningState(event.snapshot.state)) {
      return currentStatus === 'paused' ? 'resume' : 'start';
    }
    if (this.isPendingState(event.snapshot.state)) {
      return 'queue';
    }
    return undefined;
  }

  private rememberExpectedStatus(guid: string, status: DownloadV2Status): void {
    this.expectedStatusByGuid[guid] = status;
    this.expectedStatusDeadlineByGuid[guid] = Date.now() + DownloadV2Service.CONTROL_SYNC_GRACE_MS;
  }

  private clearExpectedStatusIfReached(task: DownloadV2TaskEntity): void {
    const expectedStatus = this.expectedStatusByGuid[task.guid];
    if (expectedStatus === undefined) {
      return;
    }
    if (task.status === expectedStatus) {
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'expected status reached guid=%{public}s status=%{public}s',
        task.guid,
        task.status
      );
      this.expectedStatusByGuid[task.guid] = undefined;
      this.expectedStatusDeadlineByGuid[task.guid] = undefined;
    }
  }

  private shouldSuppressStaleControlEcho(task: DownloadV2TaskEntity, platformState: string): boolean {
    const expectedStatus = this.expectedStatusByGuid[task.guid];
    if (expectedStatus === undefined) {
      return false;
    }
    const deadline = this.expectedStatusDeadlineByGuid[task.guid] ?? 0;
    if (Date.now() > deadline) {
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'expected status expired guid=%{public}s expected=%{public}s platformState=%{public}s',
        task.guid,
        expectedStatus,
        platformState
      );
      this.expectedStatusByGuid[task.guid] = undefined;
      this.expectedStatusDeadlineByGuid[task.guid] = undefined;
      return false;
    }
    if (expectedStatus === 'running' && (this.isPausedState(platformState) || this.isPendingState(platformState))) {
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'suppress stale echo guid=%{public}s expected=%{public}s current=%{public}s platformState=%{public}s',
        task.guid,
        expectedStatus,
        task.status,
        platformState
      );
      return true;
    }
    if (expectedStatus === 'paused' && (this.isRunningState(platformState) || this.isPendingState(platformState))) {
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'suppress stale echo guid=%{public}s expected=%{public}s current=%{public}s platformState=%{public}s',
        task.guid,
        expectedStatus,
        task.status,
        platformState
      );
      return true;
    }
    return false;
  }

  private mergeRequestContext(
    current: DownloadV2RequestContext,
    event: PlatformDownloadEvent
  ): DownloadV2RequestContext {
    return {
      url: event.snapshot.url.length > 0 ? event.snapshot.url : current.url,
      originalUrl: event.snapshot.originalUrl ?? current.originalUrl,
      method: event.snapshot.method?.trim() ?? current.method,
      sourcePageUrl: current.sourcePageUrl,
      sourceHost: current.sourceHost,
      userAgent: event.snapshot.userAgent ?? current.userAgent,
      referer: event.snapshot.referer ?? current.referer,
      mimeType: event.snapshot.mimeType ?? current.mimeType,
      contentDisposition: event.snapshot.contentDisposition ?? current.contentDisposition,
      headers: event.snapshot.headers ?? current.headers
    };
  }

  private buildFailureFromPlatformEvent(
    event: PlatformDownloadEvent,
    currentFailure: DownloadV2Failure
  ): DownloadV2Failure {
    if (
      event.type !== 'failed' &&
      event.type !== 'canceled' &&
      !this.isFailureState(event.snapshot.state) &&
      !this.isCanceledState(event.snapshot.state)
    ) {
      return currentFailure.code === 'none' ? buildDownloadV2EmptyFailure() : currentFailure;
    }
    if (event.type === 'canceled' || this.isCanceledState(event.snapshot.state)) {
      return {
        code: 'canceled',
        sourceCode: event.snapshot.lastErrorCode,
        message: '下载已取消。',
        retriable: false
      };
    }
    const nativeMessage = event.snapshot.errorMessage?.trim() ?? '';
    return {
      code: 'unknown',
      sourceCode: event.snapshot.lastErrorCode,
      message: nativeMessage.length > 0 ? nativeMessage : `下载失败：${event.snapshot.suggestedFileName}。`,
      retriable: true
    };
  }

  private resolveResumeCapability(state: string): 'none' | 'live_resume' | 'retry_only' {
    if (this.isPausedState(state) || this.isPausingState(state) ||
      this.isRunningState(state) || this.isPendingState(state)) {
      return 'live_resume';
    }
    if (this.isCompletedState(state) || this.isCanceledState(state)) {
      return 'none';
    }
    return 'retry_only';
  }

  private isPendingState(state: string): boolean {
    const normalized = state.trim().toUpperCase();
    return normalized.indexOf('PENDING') >= 0 || normalized.indexOf('QUEUE') >= 0;
  }

  private isRunningState(state: string): boolean {
    const normalized = state.trim().toUpperCase();
    return normalized.indexOf('IN_PROGRESS') >= 0 || normalized.indexOf('RUNNING') >= 0 || normalized.indexOf('PROGRESS') >= 0;
  }

  private isPausedState(state: string): boolean {
    return state.trim().toUpperCase().indexOf('PAUSED') >= 0;
  }

  private isPausingState(state: string): boolean {
    return state.trim().toUpperCase().indexOf('PAUSING') >= 0;
  }

  private isCompletedState(state: string): boolean {
    const normalized = state.trim().toUpperCase();
    return normalized.indexOf('COMPLETE') >= 0 || normalized.indexOf('FINISH') >= 0;
  }

  private isCanceledState(state: string): boolean {
    return state.trim().toUpperCase().indexOf('CANCEL') >= 0;
  }

  private isFailureState(state: string): boolean {
    const normalized = state.trim().toUpperCase();
    return normalized.indexOf('FAIL') >= 0 || normalized.indexOf('ERROR') >= 0 || normalized.indexOf('INTERRUPT') >= 0;
  }

  private buildEngineObserver(): DownloadV2EngineObserver {
    return {
      onTaskChanged: (task: DownloadV2TaskEntity) => {
        const previousStatus = this.previousStatusByGuid[task.guid];
        this.previousStatusByGuid[task.guid] = task.status;
        this.systemNotificationService?.handleTaskChanged(task, previousStatus);
        this.callbacks.onTaskChanged?.(task, this.resolveTaskChangeKind(task));
      },
      onTaskRemoved: (guid: string) => {
        this.previousStatusByGuid[guid] = undefined;
        this.systemNotificationService?.handleTaskRemoved(guid);
        this.callbacks.onTaskRemoved?.(guid);
      }
    };
  }

  private resolveTaskChangeKind(task: DownloadV2TaskEntity): DownloadV2TaskChangeKind {
    if (isDownloadV2TerminalStatus(task.status)) {
      return 'terminal';
    }
    if (task.status === 'running') {
      return 'progress';
    }
    return 'structural';
  }
}
