import { hilog } from '@kit.PerformanceAnalysisKit';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
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
  DownloadV2PauseReason,
  DownloadV2DestinationSnapshot,
  isDownloadV2ActiveStatus,
  isDownloadV2TerminalStatus
} from '../../domain/downloadv2/DownloadV2Types';
import { classifyDownloadV2Failure, DownloadV2FailureReason } from '../../domain/downloadv2/DownloadV2FailureMapper';
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
  DownloadFileResolutionService,
  DownloadPersistResult
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
import { ActivityTracker } from '../activity/ActivityTracker';
import { DownloadTaskBoundary } from '../../domain/download/DownloadTypes';
import { resolveCustomDownloadDirectory } from '../download/DownloadLocationDirectoryService';
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

export interface DownloadV2CompletedFileRenameResult {
  fileName: string;
  tempFilePath?: string;
  finalFileUri?: string;
  finalDisplayPath?: string;
}

export type DownloadV2CompletedFileRenameCommit = 'committed' | 'restored' | 'uncertain';

export interface DownloadV2ManualRequestResult {
  guid: string;
  prompt?: DownloadV2Prompt;
  started: boolean;
}

interface PageDownloadIdentity {
  url: string;
  userAgent: string;
  contentDisposition: string;
  mimeType: string;
  observedAt: number;
}

export class DownloadV2Service {
  private static readonly CONTROL_SYNC_GRACE_MS: number = 2200;
  private static readonly PAGE_DOWNLOAD_IDENTITY_WINDOW_MS: number = 10000;
  private static readonly PAGE_DOWNLOAD_IDENTITY_LIMIT: number = 8;
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
  private systemNotificationService?: DownloadV2SystemNotificationService;
  private callbacks: DownloadV2ServiceCallbacks = {};
  private completionCommitGuids: Record<string, boolean | undefined> = {};
  private completedPersistenceGuids: Record<string, boolean | undefined> = {};
  private expectedStatusByGuid: Record<string, DownloadV2Status | undefined> = {};
  private expectedStatusDeadlineByGuid: Record<string, number | undefined> = {};
  private previousStatusByGuid: Record<string, DownloadV2Status | undefined> = {};
  private completedActivityGuids: Record<string, boolean | undefined> = {};
  private activityTracker?: ActivityTracker;
  private downloadTriggerDiagnosticsService: DownloadTriggerDiagnosticsService;
  private runtimeDiagnosticRecorder?: DownloadRuntimeDiagnosticRecorder;
  private isQueueScheduling: boolean = false;
  private isNetworkPolicyApplying: boolean = false;
  private pendingNetworkPolicyChange: boolean = false;
  private initializationPromise?: Promise<void>;
  private pageDownloadIdentities: PageDownloadIdentity[] = [];

  constructor(
    engine?: DownloadV2Engine,
    requestCapture?: DownloadV2RequestCapture,
    repository?: DownloadV2Repository,
    platformAdapter?: PlatformDownloadAdapter,
    fileResolutionService?: DownloadFileResolutionAdapter,
    downloadPolicyService?: DownloadPolicyService,
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
      void this.applyNetworkPolicyChange('network_changed');
    });
    await this.reconnectPersistedActiveTasks();
  }

  setCellularDownloadsAllowed(allowed: boolean, rescheduleQueuedDownloads: boolean = true): void {
    this.downloadNetworkPolicyService.setCellularDownloadsAllowed(allowed);
    if (rescheduleQueuedDownloads) {
      void this.applyNetworkPolicyChange('cellular_download_policy_changed');
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
      const restoredTask = await this.ensureTaskDestination(reconnectTargets[index]);
      if (restoredTask === undefined) continue;
      const task = restoredTask;
      if (task.persistence.completionState === 'finalizing' ||
        (task.persistence.completionState === 'available' && task.status !== 'completed')) {
        const persistence = this.mergePersistenceSnapshot(task, this.buildPlatformSnapshotFromTask(task));
        persistence.completionState = 'finalizing';
        this.engine.synchronizeTask(task.guid, { status: 'running', persistence: persistence });
        await this.finalizeCompletedTask(task.guid, task.resolvedFileName ?? task.suggestedFileName, true);
        continue;
      }
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
      if (platformTaskId.length > 0 || platformTaskToken.length > 0) {
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
      await this.restorePersistedTaskIntent(task, snapshot);
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
    await this.applyNetworkPolicyChange('startup_restore');
  }

  setCallbacks(callbacks: DownloadV2ServiceCallbacks): void {
    this.callbacks = callbacks;
  }

  consumePlatformEvent(event: PlatformDownloadEvent, boundary: DownloadV2CaptureBoundary): boolean {
    this.downloadTriggerDiagnosticsService.recordPlatformEvent(event);
    if (event.type === 'before_download') {
      this.startInitializationOnDemand();
      const promotedManualPromptCount = this.requestCapture.removeManualPendingRequestsForUrl(event.snapshot.url, boundary);
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
      // Keep the original browser request dormant until confirmation, persistence and admission finish.
      // A legacy adapter without hold support retains its existing pending-request contract.
      const heldSnapshot = this.platformAdapter.holdDownload === undefined
        ? event.snapshot : this.platformAdapter.holdDownload(event.snapshot.guid);
      if (heldSnapshot === undefined) {
        this.platformAdapter.cancelPendingDownload(event.snapshot.guid);
        this.callbacks.onError?.(resolveAppResourceText($r('app.string.download_browser_context_unavailable')));
        return true;
      }
      this.mergeHeldRequestMetadata(heldSnapshot, event.snapshot);
      const captured = this.requestCapture.capturePlatformRequest(heldSnapshot, boundary, requiresConfirmation);
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
    if (this.engine.findTask(event.snapshot.guid) === undefined &&
      this.requestCapture.updatePendingPlatformSnapshot(event.snapshot)) {
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

  /** The caller's batch download button already confirms these requests. Keep unrelated prompts intact. */
  async createConfirmedManualRequest(
    url: string,
    boundary: DownloadV2CaptureBoundary,
    suggestedFileName?: string,
    sourceHost?: string,
    context?: DownloadV2ManualRequestContext
  ): Promise<DownloadV2TaskEntity | undefined> {
    const request = this.requestCapture.createManualRequest(
      url, boundary, suggestedFileName, sourceHost, false, context
    );
    if (request === undefined) {
      return undefined;
    }
    const confirmed = this.requestCapture.confirmRequest(request.guid, false);
    if (confirmed === undefined) {
      return undefined;
    }
    this.downloadTriggerDiagnosticsService.recordCapturedRequest('manual', confirmed, 'captured', 'batch_confirmed');
    return this.createTaskFromCapturedRequest(confirmed, true);
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

  /**
   * Exposes the captured request behind a prompt so callers can resolve facts
   * (such as the save location) against the boundary the request was captured
   * under, instead of whichever boundary happens to be active later.
   */
  getCapturedRequest(guid: string): DownloadV2CapturedRequest | undefined {
    return this.requestCapture.getPendingRequest(guid);
  }

  /**
   * Keeps the user agent from onDownloadStart. A download item created before that callback
   * is updated in place; one already confirmed picks the identity up before the transfer starts.
   */
  rememberPageDownloadIdentity(
    url: string,
    userAgent: string,
    contentDisposition: string,
    mimeType: string
  ): void {
    const normalizedUrl = this.normalizeDownloadIdentityUrl(url);
    const normalizedUserAgent = userAgent.trim();
    if (normalizedUrl.length <= 0 || normalizedUserAgent.length <= 0) {
      return;
    }
    const now = Date.now();
    this.pageDownloadIdentities = this.pageDownloadIdentities.filter((identity: PageDownloadIdentity) =>
      now - identity.observedAt <= DownloadV2Service.PAGE_DOWNLOAD_IDENTITY_WINDOW_MS &&
      identity.url !== normalizedUrl
    );
    this.pageDownloadIdentities.push({
      url: normalizedUrl,
      userAgent: normalizedUserAgent,
      contentDisposition: contentDisposition.trim(),
      mimeType: mimeType.trim(),
      observedAt: now
    });
    if (this.pageDownloadIdentities.length > DownloadV2Service.PAGE_DOWNLOAD_IDENTITY_LIMIT) {
      this.pageDownloadIdentities = this.pageDownloadIdentities.slice(
        this.pageDownloadIdentities.length - DownloadV2Service.PAGE_DOWNLOAD_IDENTITY_LIMIT
      );
    }
    const updatedCount = this.requestCapture.applyPageIdentityToPendingUrl(
      normalizedUrl,
      normalizedUserAgent,
      contentDisposition,
      mimeType
    );
    if (updatedCount > 0) {
      hilog.info(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'apply page download identity urlHost=%{public}s pending=%{public}d',
        this.downloadIdentityHost(normalizedUrl),
        updatedCount
      );
    }
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

  async updateCompletedFileAfterRename(
    guid: string, expectedOldLocation: string, result: DownloadV2CompletedFileRenameResult
  ): Promise<DownloadV2CompletedFileRenameCommit> {
    const task = this.engine.findTask(guid);
    if (task?.status !== 'completed' ||
      (task.persistence.finalFileUri || task.persistence.tempFilePath || '') !== expectedOldLocation ||
      result.fileName.trim().length <= 0) return 'restored';
    const persistence = this.mergePersistenceSnapshot(task, this.buildPlatformSnapshotFromTask(task));
    if (result.tempFilePath !== undefined) {
      persistence.tempFilePath = result.tempFilePath;
      if (task.persistence.partialFilePath === task.persistence.tempFilePath) {
        persistence.partialFilePath = result.tempFilePath;
      }
      if (task.persistence.finalFilePath === task.persistence.tempFilePath) {
        persistence.finalFilePath = result.tempFilePath;
      }
    }
    if (result.finalFileUri !== undefined) persistence.finalFileUri = result.finalFileUri;
    if (result.finalDisplayPath !== undefined) persistence.finalDisplayPath = result.finalDisplayPath;
    if (persistence.destination?.kind === 'file' && result.finalFileUri !== undefined) {
      persistence.destination = { kind: 'file', uri: result.finalFileUri, label: result.finalDisplayPath };
    }
    const newLocation = persistence.finalFileUri || persistence.tempFilePath || '';
    this.engine.synchronizeTask(guid, {
      suggestedFileName: result.fileName, resolvedFileName: result.fileName, persistence: persistence
    });
    try {
      await this.repository.flushPersistence();
      const latest = this.engine.findTask(guid);
      return latest?.status === 'completed' &&
        (latest.persistence.finalFileUri || latest.persistence.tempFilePath || '') === newLocation
        ? 'committed' : 'uncertain';
    } catch (error) {
      const latest = this.engine.findTask(guid);
      if (latest?.status === 'completed' &&
        (latest.persistence.finalFileUri || latest.persistence.tempFilePath || '') === newLocation) {
        this.engine.synchronizeTask(guid, {
          suggestedFileName: task.suggestedFileName, resolvedFileName: task.resolvedFileName,
          persistence: task.persistence
        });
        try {
          await this.repository.flushPersistence();
          return 'restored';
        } catch (_rollbackError) {
          hilog.error(DOWNLOAD_V2_SERVICE_DOMAIN, DOWNLOAD_V2_SERVICE_TAG,
            'rename metadata rollback persistence failed guid=%{public}s', guid);
        }
      }
      return 'uncertain';
    }
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
    const source = await this.fileResolutionService.inspectReadableFile(localPath);
    if (this.engine.findTask(guid)?.status !== 'completed') return false;
    if (source === undefined) {
      this.callbacks.onError?.(resolveAppResourceText($r('app.string.download_file_verification_failed')));
      return false;
    }
    const persisted = await this.persistFinishedDownload(localPath, task.suggestedFileName, {
      windowId: task.windowId,
      profileId: task.profileId,
      privacyMode: task.privacyMode,
      dataScope: task.dataScope,
      sourcePageUrl: task.request.sourcePageUrl
    }, { kind: 'system_downloads' });
    if (this.engine.findTask(guid)?.status !== 'completed') return false;
    if (persisted === undefined || !persisted.isExported || (persisted.finalFileUri?.trim().length ?? 0) <= 0) {
      if (persisted !== undefined) {
        this.persistCompletionLocalDisplayPath(task, persisted.finalDisplayPath);
        await this.repository.flushPersistence();
      }
      return false;
    }
    const finalFileUri = persisted.finalFileUri ?? '';
    const exported = await this.fileResolutionService.inspectReadableFile(finalFileUri);
    if (this.engine.findTask(guid)?.status !== 'completed') return false;
    if (exported === undefined || exported.size !== source.size) {
      this.callbacks.onError?.(resolveAppResourceText($r('app.string.download_file_verification_failed')));
      return false;
    }
    this.engine.synchronizeTask(guid, {
      resolvedFileName: persisted.finalFileName ?? task.resolvedFileName ?? task.suggestedFileName,
      persistence: {
        tempFilePath: task.persistence.tempFilePath,
        finalFileUri: finalFileUri,
        finalDisplayPath: persisted.finalDisplayPath,
        partialFilePath: task.persistence.partialFilePath,
        finalFilePath: task.persistence.finalFilePath,
        writtenBytes: task.persistence.writtenBytes,
        expectedTotalBytes: task.persistence.expectedTotalBytes,
        etag: task.persistence.etag,
        lastModified: task.persistence.lastModified,
        acceptRanges: task.persistence.acceptRanges,
        contentRange: task.persistence.contentRange,
        validatorCapturedAt: task.persistence.validatorCapturedAt,
        downloadDriver: task.persistence.downloadDriver,
        resumeMode: task.persistence.resumeMode,
        needsFullRestart: task.persistence.needsFullRestart,
        restartReason: task.persistence.restartReason,
        destination: persisted.destination ?? task.persistence.destination,
        completionState: task.persistence.completionState,
        segmentPlan: task.persistence.segmentPlan
      }
    });
    await this.repository.flushPersistence();
    if (this.engine.findTask(guid)?.status !== 'completed') return false;
    const cleanupSucceeded = await this.cleanupLocalTempFile(
      localPath,
      task.guid,
      task.suggestedFileName,
      'manual_export'
    );
    if (this.engine.findTask(guid)?.status !== 'completed') return false;
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
          expectedTotalBytes: refreshedTask.persistence.expectedTotalBytes,
          etag: refreshedTask.persistence.etag,
          lastModified: refreshedTask.persistence.lastModified,
          acceptRanges: refreshedTask.persistence.acceptRanges,
          contentRange: refreshedTask.persistence.contentRange,
          validatorCapturedAt: refreshedTask.persistence.validatorCapturedAt,
          downloadDriver: refreshedTask.persistence.downloadDriver,
          resumeMode: refreshedTask.persistence.resumeMode,
          needsFullRestart: refreshedTask.persistence.needsFullRestart,
          restartReason: refreshedTask.persistence.restartReason,
          destination: refreshedTask.persistence.destination,
          completionState: refreshedTask.persistence.completionState,
          segmentPlan: refreshedTask.persistence.segmentPlan
        }
      });
      await this.repository.flushPersistence();
    }
    this.callbacks.onInfo?.(this.buildSavedLocationMessage('saved', persisted.finalFileName ?? task.resolvedFileName ?? task.suggestedFileName, persisted));
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
    if (task === undefined || task.persistence.completionState === 'finalizing' ||
      (task.status !== 'running' && task.status !== 'paused')) {
      return false;
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'pause request guid=%{public}s platformTaskId=%{public}s',
      task.guid,
      task.runtime.platformTaskId ?? ''
    );
    const previousPauseReason = task.runtime.pauseReason ?? 'none';
    this.engine.synchronizeTask(task.guid, { runtime: { pauseReason: 'user' } });
    this.rememberExpectedStatus(task.guid, 'paused');
    if (task.status !== 'paused' && !await this.pauseTransportForTask(task)) {
      const latest = this.engine.findTask(task.guid);
      if (latest?.runtime.pauseReason === 'user') {
        this.engine.synchronizeTask(task.guid, { runtime: { pauseReason: previousPauseReason } });
      }
      this.expectedStatusByGuid[task.guid] = undefined;
      this.expectedStatusDeadlineByGuid[task.guid] = undefined;
      hilog.warn(DOWNLOAD_V2_SERVICE_DOMAIN, DOWNLOAD_V2_SERVICE_TAG, 'pause platform failed guid=%{public}s', task.guid);
      return false;
    }
    const latestTask = this.engine.findTask(task.guid) ?? task;
    const updatedTask = this.engine.dispatch(task.guid, 'pause', {
      progress: {
        speedBytesPerSecond: 0
      },
      runtime: {
        platformTaskId: latestTask.runtime.platformTaskId,
        platformTaskToken: latestTask.runtime.platformTaskToken,
        resumeCapability: latestTask.status === 'paused' ? latestTask.runtime.resumeCapability : 'live_resume',
        pauseReason: 'user'
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
    if (task.status !== 'paused' || (task.failure.code !== 'none' && !task.failure.retriable)) {
      return false;
    }
    const persistence = this.mergePersistenceSnapshot(task, this.buildPlatformSnapshotFromTask(task));
    const liveSnapshot = this.platformAdapter.getActiveDownloadSnapshot(task.guid);
    const canResumeLive = liveSnapshot !== undefined && liveSnapshot.transportHeld !== true &&
      this.isPausedState(liveSnapshot.state) && task.persistence.resumeMode !== 'none';
    persistence.resumeMode = canResumeLive ? 'queued_live_resume' : 'platform_live_resume';
    const queued = this.engine.dispatch(task.guid, 'queue', {
      progress: { speedBytesPerSecond: 0 },
      persistence: persistence,
      runtime: { pauseReason: 'none' },
      failure: buildDownloadV2EmptyFailure()
    });
    if (queued === undefined) {
      return false;
    }
    await this.repository.flushPersistence();
    const started = await this.startPreparedTaskFromRequest(this.buildCapturedRequestFromTask(queued), queued, 'resume');
    await this.repository.flushPersistence();
    return started || this.engine.findTask(guid)?.status === 'queued';
  }

  async retryTask(guid: string): Promise<boolean> {
    const task = this.engine.findTask(guid);
    if (task === undefined || task.status !== 'failed' ||
      !task.failure.retriable ||
      (task.persistence.tempFilePath?.trim().length ?? 0) <= 0) {
      return false;
    }
    if (task.persistence.completionState === 'export_failed') {
      if (this.completedPersistenceGuids[task.guid] === true) return false;
      const persistence = this.mergePersistenceSnapshot(task, this.buildPlatformSnapshotFromTask(task));
      persistence.completionState = 'finalizing';
      this.engine.synchronizeTask(task.guid, {
        status: 'running', persistence: persistence,
        failure: buildDownloadV2EmptyFailure(), runtime: { resumeCapability: 'none', pauseReason: 'none' }
      });
      await this.finalizeCompletedTask(task.guid, task.resolvedFileName ?? task.suggestedFileName);
      return this.engine.findTask(task.guid)?.status === 'completed';
    }
    // Queue before invoking either adapter: a resume may synchronously emit running/finished.
    // Dispatching retry afterwards would overwrite that state and start the same transfer twice.
    const persistence = this.mergePersistenceSnapshot(task, this.buildPlatformSnapshotFromTask(task));
    if (persistence.resumeMode === 'queued_live_resume') persistence.resumeMode = 'platform_live_resume';
    const queuedTask = this.engine.dispatch(task.guid, 'retry', {
      progress: { speedBytesPerSecond: 0 },
      persistence: persistence,
      runtime: { pauseReason: 'none' },
      failure: buildDownloadV2EmptyFailure()
    });
    if (queuedTask === undefined) {
      return false;
    }
    await this.repository.flushPersistence();
    const request = this.buildCapturedRequestFromTask(queuedTask);
    const started = await this.startPreparedTaskFromRequest(request, queuedTask, 'retry');
    await this.repository.flushPersistence();
    return started || this.engine.findTask(guid)?.status === 'queued';
  }

  async chooseTaskLocation(guid: string): Promise<boolean> {
    const task = this.engine.findTask(guid);
    if (task?.status !== 'failed' || !task.failure.retriable ||
      (task.failure.code !== 'permission' && task.persistence.completionState !== 'export_failed')) return false;
    const destination = await this.downloadTargetResolutionService.selectDestination(task.resolvedFileName ?? task.suggestedFileName);
    const current = this.engine.findTask(guid);
    if (destination === undefined || current?.status !== 'failed' || !current.failure.retriable) return false;
    const persistence = this.mergePersistenceSnapshot(current, this.buildPlatformSnapshotFromTask(current));
    persistence.destination = destination;
    if (persistence.completionState === 'export_failed') persistence.finalFileUri = undefined;
    this.engine.synchronizeTask(guid, { persistence: persistence });
    await this.repository.flushPersistence();
    if (this.engine.findTask(guid)?.status !== 'failed') return false;
    return this.retryTask(guid);
  }

  private async ensureTaskDestination(task: DownloadV2TaskEntity): Promise<DownloadV2TaskEntity | undefined> {
    if (task.persistence.destination !== undefined) return task;
    const destination = this.downloadTargetResolutionService.resolveDestinationSnapshot({
      windowId: task.windowId, profileId: task.profileId, privacyMode: task.privacyMode,
      dataScope: task.dataScope, sourcePageUrl: task.request.sourcePageUrl
    });
    const persistence = this.mergePersistenceSnapshot(task, this.buildPlatformSnapshotFromTask(task));
    persistence.destination = destination;
    this.engine.synchronizeTask(task.guid, { persistence: persistence });
    await this.repository.flushPersistence();
    return this.engine.findTask(task.guid);
  }

  async cancelTask(guid: string): Promise<boolean> {
    const task = this.engine.findTask(guid);
    if (task === undefined || task.persistence.completionState === 'finalizing') {
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
        message: resolveAppResourceText($r('app.string.download_canceled_message')),
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
    if (task === undefined || task.status === 'completed' || task.status === 'removed') {
      return false;
    }
    const canceled = task.status === 'canceled' ? true : await this.cancelTask(guid);
    const latestTask = this.engine.findTask(guid);
    // Completion can win while the native cancellation is in flight.
    if (latestTask === undefined || latestTask.status === 'completed' || latestTask.status === 'removed') {
      return false;
    }
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

  private mergeHeldRequestMetadata(held: PlatformDownloadSnapshot, incoming: PlatformDownloadSnapshot): void {
    // Runtime enriches request metadata before capture; hold() supplies only transport truth.
    held.sourceId = incoming.sourceId ?? held.sourceId;
    held.originalUrl = incoming.originalUrl ?? held.originalUrl;
    held.suggestedFileName = incoming.suggestedFileName.length > 0 ? incoming.suggestedFileName : held.suggestedFileName;
    held.method = incoming.method ?? held.method;
    held.mimeType = incoming.mimeType ?? held.mimeType;
    held.userAgent = incoming.userAgent ?? held.userAgent;
    held.referer = incoming.referer ?? held.referer;
    held.contentDisposition = incoming.contentDisposition ?? held.contentDisposition;
    held.headers = incoming.headers ?? held.headers;
    held.hlsSegmentConcurrency = incoming.hlsSegmentConcurrency ?? held.hlsSegmentConcurrency;
    held.privacyMode = incoming.privacyMode ?? held.privacyMode;
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
    this.applyRememberedPageDownloadIdentity(request);
    await this.initialize();
    this.applyRememberedPageDownloadIdentity(request);
    // The selected transport owns every request, including HTTP redirects and cookies.
    // A speculative HTML GET would consume one-use URLs before that transport starts.
    // Manual downloads save the selected resource; HTML/JS navigation belongs to ArkWeb.
    const requestToCreate = request;
    const normalizedConfirmedFileName = confirmedFileName?.trim() ?? '';
    if (normalizedConfirmedFileName.length > 0) {
      if (normalizedConfirmedFileName !== requestToCreate.suggestedFileName) requestToCreate.fileNameLocked = true;
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
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'create task begin guid=%{public}s file=%{public}s url=%{public}s snapshot=%{public}s confirm=%{public}s boundary=%{public}s/%{public}s/%{public}s/%{public}s',
      requestToCreate.guid,
      requestToCreate.suggestedFileName,
      requestToCreate.url,
      requestToCreate.platformSnapshot !== undefined ? 'yes' : 'no',
      requiresConfirmation ? 'true' : 'false',
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
        sourceId: requestToCreate.sourceId,
        nativeReason: requestToCreate.nativeReason,
        fileNameLocked: requestToCreate.fileNameLocked,
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
          message: resolveAppResourceText($r('app.string.download_start_no_directory')),
          retriable: true
        }
      });
      await this.repository.flushPersistence();
      this.callbacks.onError?.(resolveAppResourceText($r('app.string.download_start_no_directory')));
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
    const downloadDriver = this.resolveInitialDownloadDriver(requestToCreate);
    this.downloadTriggerDiagnosticsService.recordDriverSelection(requestToCreate, downloadDriver);
    const preparedTask = this.engine.synchronizeTask(queuedTask.guid, {
      resolvedFileName: targetPlan.fileName,
      persistence: {
        destination: targetPlan.destination,
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
        platformTaskId: sourceSnapshot?.platformTaskId ?? '',
        platformTaskToken: sourceSnapshot?.platformTaskToken,
        resumeCapability: sourceSnapshot === undefined ? 'none' : this.resolveResumeCapability(sourceSnapshot.state),
        pauseReason: 'none'
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
      if (!this.holdQueuedPlatformTask(latestPreparedTask)) {
        await this.repository.flushPersistence();
        return this.engine.findTask(latestPreparedTask.guid);
      }
      this.persistQueuedAdmissionReason(this.engine.findTask(latestPreparedTask.guid) ?? latestPreparedTask, admission.reason);
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
      return this.engine.findTask(latestPreparedTask.guid);
    }
    this.applyRememberedPageDownloadIdentity(requestToCreate);
    await this.startPreparedTaskFromRequest(requestToCreate, latestPreparedTask, 'create_task');
    return this.engine.findTask(queuedTask.guid);
  }

  private resolveInitialDownloadDriver(request: DownloadV2CapturedRequest): DownloadV2Driver {
    const method = request.method.trim().toUpperCase();
    // Non-GET requests (POST "download a copy" flows such as Office on the web) cannot be
    // replayed through libcurl because ArkWeb does not expose the request body, so ArkWeb
    // finishes those itself.
    if (method !== 'GET') {
      return 'arkweb';
    }
    // blob:/data: and other non-http(s) URLs only resolve inside the renderer that produced
    // them, so libcurl cannot fetch them either; ArkWeb writes those itself.
    const normalized = request.url.trim().toLowerCase();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      return 'arkweb';
    }
    // Native transport is an explicit capability for manifest assembly or caller-defined
    // headers. Ordinary manual/MP4/batch downloads use the originating Web controller too.
    // Absence of a live controller is an error, not permission to silently replay with curl.
    if (this.isHlsCapturedRequest(request) ||
      (request.platformSnapshot === undefined && request.nativeReason === 'custom_headers')) return 'libcurl';
    return 'arkweb';
  }

  private isHlsCapturedRequest(request: DownloadV2CapturedRequest): boolean {
    const url = request.url.trim().toLowerCase();
    const mime = request.mimeType?.trim().toLowerCase() ?? '';
    return request.nativeReason === 'hls' || /\.m3u8(?:[?#]|$)/i.test(url) ||
      mime.indexOf('mpegurl') >= 0 || mime.indexOf('hls') >= 0;
  }

  private async startPreparedTaskFromRequest(
    request: DownloadV2CapturedRequest,
    task: DownloadV2TaskEntity,
    reason: string
  ): Promise<boolean> {
    this.persistPageDownloadIdentity(task, request);
    let currentTask = this.engine.findTask(task.guid);
    if (currentTask === undefined) {
      return false;
    }
    const targetPath = currentTask.persistence.tempFilePath?.trim() ?? '';
    const downloadDriver = currentTask.persistence.downloadDriver ?? 'arkweb';
    if (targetPath.length <= 0 || currentTask.status !== 'queued') {
      hilog.warn(
        DOWNLOAD_V2_SERVICE_DOMAIN,
        DOWNLOAD_V2_SERVICE_TAG,
        'start prepared rejected guid=%{public}s reason=%{public}s status=%{public}s path=%{public}s driver=%{public}s',
        currentTask.guid,
        reason,
        currentTask.status,
        targetPath,
        downloadDriver
      );
      return false;
    }
    currentTask = await this.ensureTaskDestination(currentTask);
    if (currentTask === undefined || currentTask.status !== 'queued') return false;
    const destination = currentTask.persistence.destination;
    if (destination === undefined) return false;
    const destinationAllowed = await this.downloadTargetResolutionService.validateDestination(destination);
    currentTask = this.engine.findTask(task.guid);
    if (currentTask === undefined || currentTask.status !== 'queued') return false;
    if (!destinationAllowed) {
      if (!this.holdQueuedPlatformTask(currentTask)) {
        await this.repository.flushPersistence();
        return false;
      }
      const message = resolveAppResourceText($r('app.string.download_failure_permission'));
      this.engine.dispatch(currentTask.guid, 'fail', {
        failure: { code: 'permission', message: message, retriable: true }
      });
      await this.repository.flushPersistence();
      if (this.engine.findTask(task.guid)?.status === 'failed') this.callbacks.onError?.(message);
      return false;
    }
    const admission = this.downloadQueuePolicyService.resolveStartAdmission(
      this.engine.listTasks(),
      currentTask.guid,
      this.downloadNetworkPolicyService.resolveStartAdmission()
    );
    if (!admission.canStartNow) {
      if (!this.holdQueuedPlatformTask(currentTask)) {
        await this.repository.flushPersistence();
        return false;
      }
      this.persistQueuedAdmissionReason(this.engine.findTask(currentTask.guid) ?? currentTask, admission.reason);
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
    // Reserve the queue slot synchronously. A cold native import or ArkWeb callback
    // can yield long enough for a second drain or another task to be admitted.
    if (this.engine.dispatch(currentTask.guid, 'start', { runtime: { pauseReason: 'none' } }) === undefined) {
      return false;
    }
    this.rememberExpectedStatus(currentTask.guid, 'running');
    let startedSnapshot: PlatformDownloadSnapshot | undefined;
    const resumeExisting = currentTask.persistence.resumeMode === 'queued_live_resume';
    if (resumeExisting) {
      const resumed = await this.platformAdapter.resumeDownload(
        currentTask.guid, currentTask.runtime.platformTaskId, currentTask.runtime.platformTaskToken
      );
      if (resumed) {
        startedSnapshot = this.platformAdapter.getActiveDownloadSnapshot(currentTask.guid) ??
          this.buildPlatformSnapshotFromTask(currentTask);
        if (this.isPendingState(startedSnapshot.state)) startedSnapshot.state = 'IN_PROGRESS';
      }
    } else if (downloadDriver !== 'arkweb' && currentTask.timing.failedAt !== undefined &&
      (currentTask.runtime.platformTaskId?.trim().length ?? 0) > 0) {
      const retried = await this.platformAdapter.retryDownload(
        currentTask.guid, targetPath, currentTask.runtime.platformTaskId,
        currentTask.runtime.platformTaskToken, this.resolveTaskHlsSegmentConcurrency(currentTask)
      );
      if (retried) {
        startedSnapshot = this.platformAdapter.getActiveDownloadSnapshot(currentTask.guid) ??
          this.buildPlatformSnapshotFromTask(currentTask);
        startedSnapshot.state = 'IN_PROGRESS';
      }
    }
    if (startedSnapshot === undefined && !resumeExisting) {
      startedSnapshot = await this.startDirectRequest(request, targetPath, currentTask);
    }
    if (startedSnapshot === undefined) {
      const status = this.engine.findTask(currentTask.guid)?.status;
      if (status !== 'running') return false;
      await this.failPreparedTaskStart(currentTask, request, downloadDriver);
      return false;
    }
    const statusAfterStart = this.engine.findTask(currentTask.guid)?.status;
    if (statusAfterStart === undefined || statusAfterStart === 'canceled' || statusAfterStart === 'removed') {
      await this.platformAdapter.cancelDownload(currentTask.guid, startedSnapshot.platformTaskId, startedSnapshot.platformTaskToken);
      return false;
    }
    if (statusAfterStart === 'failed' || statusAfterStart === 'paused') {
      return false;
    }
    if (statusAfterStart === 'completed') return true;
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
    this.markStartedSnapshotAccepted(currentTask.guid, startedSnapshot);
    this.callbacks.onInfo?.(resolveAppResourceText($r('app.string.download_started', request.suggestedFileName)));
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
    const failure: DownloadV2Failure = downloadDriver === 'arkweb' &&
      !this.platformAdapter.hasActiveDownload(task.guid)
      ? this.buildArkWebContextUnavailableFailure(task)
      : {
        code: 'unknown',
        message: resolveAppResourceText($r('app.string.download_start_failed', request.suggestedFileName)),
        retriable: true
      };
    this.engine.dispatch(task.guid, 'fail', { failure: failure });
    await this.repository.flushPersistence();
    this.callbacks.onError?.(failure.message);
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
        speedBytesPerSecond: snapshot.currentSpeed,
        progressFraction: snapshot.progressFraction ?? -1,
        estimatedTotalBytes: snapshot.estimatedTotalBytes ?? 0
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

  private async applyNetworkPolicyChange(reason: string): Promise<void> {
    if (this.isNetworkPolicyApplying) {
      this.pendingNetworkPolicyChange = true;
      return;
    }
    this.isNetworkPolicyApplying = true;
    try {
      do {
        this.pendingNetworkPolicyChange = false;
        const admission = this.downloadNetworkPolicyService.resolveStartAdmission();
        const tasks = this.engine.listTasks();
        for (let index = 0; index < tasks.length; index += 1) {
          const task = this.engine.findTask(tasks[index].guid);
          if (task === undefined || task.persistence.completionState === 'finalizing') continue;
          if (!admission.canStartNow) {
            if (task.status === 'running') {
              await this.pauseTaskForNetworkPolicy(task, this.resolveAdmissionPauseReason(admission.reason));
            } else if (task.status === 'paused' &&
              (task.runtime.pauseReason === 'network' || task.runtime.pauseReason === 'wifi_policy')) {
              this.engine.synchronizeTask(task.guid, {
                runtime: { pauseReason: this.resolveAdmissionPauseReason(admission.reason) }
              });
            } else if (task.status === 'queued') {
              this.persistQueuedAdmissionReason(task, admission.reason);
            }
          } else if (task.status === 'paused' &&
            (task.runtime.pauseReason === 'network' || task.runtime.pauseReason === 'wifi_policy')) {
            await this.resumeTask(task.guid);
          }
        }
        await this.repository.flushPersistence();
        await this.scheduleNextQueuedDownloads(reason);
      } while (this.pendingNetworkPolicyChange);
    } finally {
      this.isNetworkPolicyApplying = false;
    }
  }

  private async pauseTaskForNetworkPolicy(task: DownloadV2TaskEntity, pauseReason: DownloadV2PauseReason): Promise<void> {
    this.engine.synchronizeTask(task.guid, { runtime: { pauseReason: pauseReason } });
    this.rememberExpectedStatus(task.guid, 'paused');
    const paused = await this.pauseTransportForTask(task);
    const latest = this.engine.findTask(task.guid);
    if (latest === undefined || latest.runtime.pauseReason === 'user') return;
    if (!paused) {
      if (latest.status === 'running') {
        this.engine.synchronizeTask(task.guid, { runtime: { pauseReason: 'none' } });
      }
      this.expectedStatusByGuid[task.guid] = undefined;
      this.expectedStatusDeadlineByGuid[task.guid] = undefined;
      return;
    }
    this.engine.dispatch(task.guid, 'pause', {
      progress: { speedBytesPerSecond: 0 },
      runtime: { pauseReason: pauseReason }
    });
  }

  private async pauseTransportForTask(task: DownloadV2TaskEntity): Promise<boolean> {
    const snapshot = this.platformAdapter.getActiveDownloadSnapshot(task.guid);
    if (task.persistence.downloadDriver === 'arkweb' && snapshot !== undefined &&
      this.isPendingState(snapshot.state) && this.platformAdapter.holdDownload !== undefined) {
      const held = this.platformAdapter.holdDownload(task.guid);
      if (held === undefined) return false;
      const persistence = this.mergePersistenceSnapshot(task, held);
      // A held initial request still needs start(targetPath) during manager restoration.
      persistence.resumeMode = 'none';
      this.engine.synchronizeTask(task.guid, {
        persistence: persistence,
        runtime: {
          platformTaskId: held.platformTaskId ?? task.runtime.platformTaskId,
          platformTaskToken: held.platformTaskToken ?? task.runtime.platformTaskToken,
          resumeCapability: 'live_resume'
        }
      });
      return true;
    }
    return this.platformAdapter.pauseDownload(task.guid, task.runtime.platformTaskId, task.runtime.platformTaskToken);
  }

  private resolveAdmissionPauseReason(reason: string): DownloadV2PauseReason {
    if (reason === 'waiting_wifi') return 'wifi_policy';
    if (reason === 'offline_network' || reason === 'network_unknown') return 'network';
    if (reason === 'concurrency_limit') return 'concurrency';
    return 'none';
  }

  private holdQueuedPlatformTask(task: DownloadV2TaskEntity): boolean {
    if (task.persistence.downloadDriver !== 'arkweb' || this.platformAdapter.holdDownload === undefined ||
      !this.platformAdapter.hasActiveDownload(task.guid) || task.persistence.resumeMode === 'queued_live_resume') {
      return true;
    }
    const held = this.platformAdapter.holdDownload(task.guid);
    if (held === undefined) {
      this.platformAdapter.cancelPendingDownload(task.guid);
      const failure = this.buildArkWebContextUnavailableFailure(task);
      this.engine.dispatch(task.guid, 'fail', { failure: failure });
      this.callbacks.onError?.(failure.message);
      return false;
    }
    this.engine.synchronizeTask(task.guid, {
      runtime: {
        platformTaskId: held.platformTaskId ?? task.runtime.platformTaskId,
        platformTaskToken: held.platformTaskToken ?? task.runtime.platformTaskToken,
        resumeCapability: this.resolveResumeCapability(held.state)
      }
    });
    return true;
  }

  private async restorePersistedTaskIntent(task: DownloadV2TaskEntity, snapshot: PlatformDownloadSnapshot): Promise<void> {
    if (this.isCompletedState(snapshot.state)) {
      this.syncTaskFromPlatformEvent({ type: 'finished', snapshot: snapshot }, true);
      return;
    }
    if (task.status === 'running' && this.isRunningState(snapshot.state)) {
      this.syncTaskFromPlatformEvent({ type: 'updated', snapshot: snapshot }, true);
      return;
    }
    const manuallyPaused = task.status === 'paused' &&
      task.runtime.pauseReason !== 'network' && task.runtime.pauseReason !== 'wifi_policy';
    // Deserialization reports an interrupted/paused transport. Preserve application intent instead
    // of turning every restored record into a manual pause or a failure.
    const restoredStatus: DownloadV2Status = task.status === 'running' ? 'queued' : task.status;
    const nextPersistence = this.mergePersistenceSnapshot(task, snapshot);
    if (restoredStatus === 'queued') nextPersistence.resumeMode = 'platform_live_resume';
    this.engine.synchronizeTask(task.guid, {
      status: restoredStatus,
      persistence: nextPersistence,
      progress: { speedBytesPerSecond: 0 },
      runtime: {
        platformTaskId: snapshot.platformTaskId ?? task.runtime.platformTaskId,
        platformTaskToken: snapshot.platformTaskToken ?? task.runtime.platformTaskToken,
        resumeCapability: this.resolveResumeCapability(snapshot.state),
        pauseReason: manuallyPaused ? 'user' : task.runtime.pauseReason ?? 'none'
      }
    });
    if (this.isRunningState(snapshot.state) || this.isPendingState(snapshot.state)) {
      // Reconcile a still-live transport with its saved intent before applying admission.
      const restored = this.engine.findTask(task.guid);
      if (restored === undefined) return;
      if (restored.status === 'queued') {
        this.holdQueuedPlatformTask(restored);
      } else if (restored.status === 'paused') {
        this.rememberExpectedStatus(task.guid, 'paused');
        await this.pauseTransportForTask(restored);
      }
    }
  }

  private async scheduleNextQueuedDownloads(reason: string): Promise<void> {
    if (this.isQueueScheduling) {
      return;
    }
    this.isQueueScheduling = true;
    // One drain must never hand the same task to the adapter twice. A successful start moves the
    // task to `running` and a deferred admission makes the next plan un-startable, so a guid that
    // comes back around is a start that keeps reporting failure without moving the task out of
    // `queued`. Retrying it here is what turned one un-startable download into an unbounded
    // main-thread loop, so stop and leave the task for the user instead.
    const attemptedGuids = new Set<string>();
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
        if (attemptedGuids.has(plan.nextGuid)) {
          hilog.warn(
            DOWNLOAD_V2_SERVICE_DOMAIN,
            DOWNLOAD_V2_SERVICE_TAG,
            'queue schedule stalled guid=%{public}s reason=%{public}s attempted=%{public}d; leaving task queued',
            plan.nextGuid,
            reason,
            attemptedGuids.size
          );
          return;
        }
        const task = this.engine.findTask(plan.nextGuid);
        if (task === undefined || task.status !== 'queued') {
          return;
        }
        attemptedGuids.add(plan.nextGuid);
        const request = this.buildCapturedRequestFromTask(task);
        this.applyRememberedPageDownloadIdentity(request);
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
      this.callbacks.onInfo?.(resolveAppResourceText($r('app.string.download_queued', suggestedFileName)));
      return;
    }
    if (reason === 'waiting_wifi') {
      this.callbacks.onInfo?.(resolveAppResourceText($r('app.string.download_queued_wifi', suggestedFileName)));
      return;
    }
    if (reason === 'offline_network') {
      this.callbacks.onInfo?.(resolveAppResourceText($r('app.string.download_queued_offline', suggestedFileName)));
      return;
    }
    if (reason === 'network_unknown') {
      this.callbacks.onInfo?.(resolveAppResourceText($r('app.string.download_queued_unknown_network', suggestedFileName)));
    }
  }

  private persistQueuedAdmissionReason(
    task: DownloadV2TaskEntity,
    reason: 'concurrency_limit' | 'waiting_wifi' | 'offline_network' | 'network_unknown' | 'not_startable' | 'start_now'
  ): void {
    const restartReason = this.resolveQueuedRestartReason(reason);
    this.engine.synchronizeTask(task.guid, {
      runtime: { pauseReason: this.resolveAdmissionPauseReason(reason) },
      persistence: {
        tempFilePath: task.persistence.tempFilePath,
        finalFileUri: task.persistence.finalFileUri,
        finalDisplayPath: task.persistence.finalDisplayPath,
        partialFilePath: task.persistence.partialFilePath,
        finalFilePath: task.persistence.finalFilePath,
        writtenBytes: task.persistence.writtenBytes,
        expectedTotalBytes: task.persistence.expectedTotalBytes,
        etag: task.persistence.etag,
        lastModified: task.persistence.lastModified,
        acceptRanges: task.persistence.acceptRanges,
        contentRange: task.persistence.contentRange,
        validatorCapturedAt: task.persistence.validatorCapturedAt,
        downloadDriver: task.persistence.downloadDriver,
        resumeMode: task.persistence.resumeMode,
        needsFullRestart: task.persistence.needsFullRestart,
        restartReason: restartReason,
        destination: task.persistence.destination,
        completionState: task.persistence.completionState,
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

  private persistPageDownloadIdentity(
    task: DownloadV2TaskEntity,
    request: DownloadV2CapturedRequest
  ): void {
    const userAgent = request.userAgent?.trim() ?? '';
    const contentDisposition = request.contentDisposition?.trim() ?? '';
    const mimeType = request.mimeType?.trim() ?? '';
    const storedUserAgent = task.request.userAgent?.trim() ?? '';
    const storedDisposition = task.request.contentDisposition?.trim() ?? '';
    const storedMimeType = task.request.mimeType?.trim() ?? '';
    if ((userAgent.length <= 0 || userAgent === storedUserAgent) &&
      (contentDisposition.length <= 0 || contentDisposition === storedDisposition) &&
      (mimeType.length <= 0 || mimeType === storedMimeType)) {
      return;
    }
    this.engine.synchronizeTask(task.guid, {
      request: {
        url: task.request.url,
        originalUrl: task.request.originalUrl,
        sourceId: task.request.sourceId,
        nativeReason: task.request.nativeReason,
        fileNameLocked: task.request.fileNameLocked,
        method: task.request.method,
        sourcePageUrl: task.request.sourcePageUrl,
        sourceHost: task.request.sourceHost,
        userAgent: userAgent.length > 0 ? userAgent : task.request.userAgent,
        referer: task.request.referer,
        mimeType: mimeType.length > 0 ? mimeType : task.request.mimeType,
        contentDisposition: contentDisposition.length > 0 ? contentDisposition : task.request.contentDisposition,
        headers: task.request.headers
      }
    });
  }

  private buildCapturedRequestFromTask(task: DownloadV2TaskEntity): DownloadV2CapturedRequest {
    return {
      guid: task.guid,
      url: task.request.url,
      originalUrl: task.request.originalUrl,
      sourceId: task.request.sourceId,
      nativeReason: task.request.nativeReason,
      fileNameLocked: task.request.fileNameLocked,
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
      sourceId: task.request.sourceId,
      url: task.request.url,
      fileNameLocked: task.request.fileNameLocked,
      originalUrl: task.request.originalUrl,
      suggestedFileName: task.resolvedFileName ?? task.suggestedFileName,
      totalBytes: task.progress.totalBytes,
      progressFraction: task.progress.progressFraction,
      estimatedTotalBytes: task.progress.estimatedTotalBytes,
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
      platformTaskToken: task.runtime.platformTaskToken,
      downloadDriver: task.persistence.downloadDriver,
      privacyMode: task.privacyMode
    };
  }

  private syncTaskFromPlatformEvent(event: PlatformDownloadEvent, silent: boolean = false): boolean {
    const currentTask = this.engine.findTask(event.snapshot.guid);
    if (currentTask === undefined) {
      return false;
    }
    if (currentTask.persistence.completionState !== undefined) {
      return true;
    }
    // HLS conversion owns a separate libcurl transfer; ignore late browser callbacks.
    if (currentTask.persistence.downloadDriver === 'libcurl' && event.snapshot.downloadDriver === 'arkweb') {
      return true;
    }
    if (currentTask.status === 'queued' && event.snapshot.transportHeld === true) {
      this.engine.synchronizeTask(currentTask.guid, {
        runtime: {
          platformTaskId: event.snapshot.platformTaskId ?? currentTask.runtime.platformTaskId,
          platformTaskToken: event.snapshot.platformTaskToken ?? currentTask.runtime.platformTaskToken
        }
      });
      return true;
    }
    if (currentTask.persistence.resumeMode === 'queued_live_resume' &&
      (this.isPausedState(event.snapshot.state) || this.isPausingState(event.snapshot.state))) {
      return true;
    }
    const expectedTotalBytes = currentTask.persistence.expectedTotalBytes ?? 0;
    if (expectedTotalBytes > 0 && this.isCompletedState(event.snapshot.state) &&
      event.snapshot.receivedBytes !== expectedTotalBytes) {
      // A CDN can return a 200 HTML challenge with the original attachment filename.
      // A known expected length still constrains completion after native recovery.
      hilog.warn(DOWNLOAD_V2_SERVICE_DOMAIN, DOWNLOAD_V2_SERVICE_TAG,
        'reject incomplete replacement guid=%{public}s expected=%{public}d received=%{public}d',
        currentTask.guid, expectedTotalBytes, event.snapshot.receivedBytes);
      event = {
        type: 'failed',
        snapshot: {
          guid: event.snapshot.guid,
          url: event.snapshot.url,
          originalUrl: event.snapshot.originalUrl,
          suggestedFileName: event.snapshot.suggestedFileName,
          totalBytes: event.snapshot.totalBytes,
          receivedBytes: event.snapshot.receivedBytes,
          currentSpeed: event.snapshot.currentSpeed,
          mimeType: event.snapshot.mimeType,
          method: event.snapshot.method,
          userAgent: event.snapshot.userAgent,
          referer: event.snapshot.referer,
          contentDisposition: event.snapshot.contentDisposition,
          headers: event.snapshot.headers,
          hlsSegmentConcurrency: event.snapshot.hlsSegmentConcurrency,
          platformTaskId: event.snapshot.platformTaskId,
          platformTaskToken: event.snapshot.platformTaskToken,
          downloadDriver: event.snapshot.downloadDriver,
          privacyMode: event.snapshot.privacyMode,
          state: 'FAILED',
          lastErrorCode: 18,
          errorMessage: resolveAppResourceText($r('app.string.download_response_size_mismatch'))
        }
      };
    }
    if (currentTask.status === 'paused' && currentTask.runtime.pauseReason === 'user' &&
      (this.isRunningState(event.snapshot.state) || this.isPendingState(event.snapshot.state))) {
      void this.pauseTransportForTask(currentTask).catch((error: Error) => {
        hilog.warn(DOWNLOAD_V2_SERVICE_DOMAIN, DOWNLOAD_V2_SERVICE_TAG,
          'retain manual pause failed guid=%{public}s error=%{public}s', currentTask.guid, error.message);
      });
      return true;
    }
    if (this.shouldSuppressStaleControlEcho(currentTask, event.snapshot.state)) {
      return true;
    }
    const nextRequest = this.mergeRequestContext(currentTask.request, event);
    const resolvedEventFileName = this.fileNameService.resolveFileName({
      suggestedFileName: currentTask.request.fileNameLocked !== true && event.snapshot.suggestedFileName.length > 0
        ? event.snapshot.suggestedFileName : currentTask.resolvedFileName ?? currentTask.suggestedFileName,
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
      totalBytes: event.snapshot.downloadDriver === 'libcurl' ? Math.max(0, event.snapshot.totalBytes)
        : event.snapshot.totalBytes > 0 ? event.snapshot.totalBytes : currentTask.progress.totalBytes,
      receivedBytes: event.snapshot.downloadDriver === 'libcurl' ? Math.max(0, event.snapshot.receivedBytes)
        : Math.max(currentTask.progress.receivedBytes, event.snapshot.receivedBytes),
      speedBytesPerSecond: event.snapshot.currentSpeed,
      progressFraction: event.snapshot.progressFraction ?? -1,
      estimatedTotalBytes: event.snapshot.estimatedTotalBytes ?? 0
    };
    const driver = event.snapshot.downloadDriver ?? currentTask.persistence.downloadDriver ?? 'arkweb';
    let nextFailure = this.buildFailureFromPlatformEvent(event, currentTask.failure, driver);
    const classifiedFailure = classifyDownloadV2Failure(driver, event.snapshot.lastErrorCode);
    const networkPause = (event.type === 'failed' || this.isFailureState(event.snapshot.state)) &&
      classifiedFailure.shouldPauseForNetwork;
    let eventName = networkPause ? 'pause' : this.resolveEngineEvent(currentTask.status, event);
    if (networkPause) {
      nextRuntime.pauseReason = currentTask.runtime.pauseReason === 'user' ? 'user' : 'network';
      nextProgress.speedBytesPerSecond = 0;
      if ((nextRuntime.platformTaskToken?.trim().length ?? 0) > 0 ||
        this.platformAdapter.hasActiveDownload(currentTask.guid)) {
        nextRuntime.resumeCapability = 'live_resume';
      } else {
        eventName = 'fail';
        nextFailure = this.buildArkWebContextUnavailableFailure(currentTask);
        nextRuntime.resumeCapability = 'none';
      }
    } else if (eventName === 'start' || eventName === 'resume') {
      nextRuntime.pauseReason = 'none';
    }
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
    if (eventName === 'finish') {
      if (currentTask.status !== 'running' && currentTask.status !== 'paused' && currentTask.status !== 'queued') {
        return false;
      }
      nextPersistence.completionState = 'finalizing';
      nextProgress.speedBytesPerSecond = 0;
      nextRuntime.resumeCapability = 'none';
      const finalizing = this.engine.dispatch(currentTask.guid, 'start', patch);
      if (finalizing === undefined) return false;
      void this.finalizeCompletedTask(finalizing.guid, finalizing.resolvedFileName ?? finalizing.suggestedFileName, silent);
      void this.scheduleNextQueuedDownloads('network_received');
      return true;
    }
    const previousStatus = currentTask.status;
    if (currentTask.status === 'queued' && eventName === 'pause') {
      // A restored transport can pause before its first running callback.
      // The state machine enters running before applying that real pause.
      this.engine.dispatch(currentTask.guid, 'start');
    }
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
    void this.flushSideEffectsForPlatformEvent(updated, event, silent, previousStatus).catch((error: Error) => {
      hilog.error(DOWNLOAD_V2_SERVICE_DOMAIN, DOWNLOAD_V2_SERVICE_TAG,
        'platform side effects failed guid=%{public}s error=%{public}s', updated.guid, error.message);
    });
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
      writtenBytes: currentTask.persistence.completionState !== undefined
        ? currentTask.persistence.writtenBytes ?? receivedBytes : receivedBytes,
      expectedTotalBytes: currentTask.persistence.expectedTotalBytes,
      etag: currentTask.persistence.etag,
      lastModified: currentTask.persistence.lastModified,
      acceptRanges: currentTask.persistence.acceptRanges,
      contentRange: currentTask.persistence.contentRange,
      validatorCapturedAt: currentTask.persistence.validatorCapturedAt,
      downloadDriver: snapshot.downloadDriver ?? currentTask.persistence.downloadDriver ?? 'arkweb',
      resumeMode: currentTask.persistence.resumeMode === 'queued_live_resume' &&
        (this.isRunningState(snapshot.state) || this.isCompletedState(snapshot.state))
        ? 'platform_live_resume' : currentTask.persistence.resumeMode ?? 'platform_live_resume',
      needsFullRestart: currentTask.persistence.needsFullRestart,
      restartReason: currentTask.persistence.restartReason,
      destination: currentTask.persistence.destination,
      completionState: currentTask.persistence.completionState,
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
      progressFraction: snapshot.progressFraction,
      estimatedTotalBytes: snapshot.estimatedTotalBytes,
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
      platformTaskToken: snapshot.platformTaskToken,
      downloadDriver: snapshot.downloadDriver,
      privacyMode: snapshot.privacyMode
    };
  }

  private startDirectRequest(
    request: DownloadV2CapturedRequest,
    targetPath: string,
    task?: DownloadV2TaskEntity
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
      sourceId: request.sourceId,
      fileNameLocked: request.fileNameLocked,
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
      platformTaskId: task?.runtime.platformTaskId ?? request.platformSnapshot?.platformTaskId,
      platformTaskToken: task?.runtime.platformTaskToken ?? request.platformSnapshot?.platformTaskToken,
      downloadDriver: task?.persistence.downloadDriver ?? this.resolveInitialDownloadDriver(request),
      privacyMode: request.boundary.privacyMode
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
    if (!silent && task.status === 'failed' && previousStatus !== 'failed') {
      this.callbacks.onError?.(task.failure.message.length > 0
        ? task.failure.message
        : resolveAppResourceText($r('app.string.download_failed_file', task.suggestedFileName)));
    }
    // The repository coalesces progress writes; only structural transitions need a barrier.
    if (task.status !== previousStatus || isDownloadV2TerminalStatus(task.status)) {
      await this.repository.flushPersistence();
    }
    if (task.status !== previousStatus &&
      (task.status === 'paused' || task.status === 'completed' || task.status === 'failed' || task.status === 'canceled')) {
      void this.scheduleNextQueuedDownloads('platform_terminal');
    }
  }

  private async finalizeCompletedTask(guid: string, suggestedFileName: string, silent: boolean = false): Promise<void> {
    if (this.completedPersistenceGuids[guid] === true) return;
    this.completedPersistenceGuids[guid] = true;
    try {
      await this.repository.flushPersistence();
      let task = this.findFinalizingTask(guid);
      if (task === undefined) return;
      await this.ensureTaskDestination(task);
      task = this.findFinalizingTask(guid);
      if (task === undefined) return;
      const existingUri = task.persistence.finalFileUri?.trim() ?? '';
      if (existingUri.length > 0) {
        const target = await this.fileResolutionService.inspectReadableFile(existingUri);
        task = this.findFinalizingTask(guid);
        if (task === undefined) return;
        if (target === undefined || (task.persistence.writtenBytes !== undefined &&
          target.size !== task.persistence.writtenBytes)) {
          await this.failExportWithRetainedSource(task, true, silent, true);
          return;
        }
        await this.commitAvailableFile(task, target.size, undefined, silent);
        return;
      }
      const localPath = task.persistence.tempFilePath?.trim() ?? '';
      const source = await this.fileResolutionService.inspectReadableFile(localPath);
      task = this.findFinalizingTask(guid);
      if (task === undefined) return;
      if (source === undefined || !this.isFinalizationSourceValid(task, source.size)) {
        await this.failFileFinalization(task, true, silent, false, false);
        return;
      }
      const destination = task.persistence.destination;
      if (destination === undefined) {
        await this.failFileFinalization(task, false, silent);
        return;
      }
      const destinationAllowed = await this.downloadTargetResolutionService.validateDestination(destination);
      task = this.findFinalizingTask(guid);
      if (task === undefined) return;
      if (!destinationAllowed) {
        await this.failExportWithRetainedSource(task, false, silent, false, true);
        return;
      }
      const completionPolicy = this.downloadTargetResolutionService.resolveCompletionTargetPolicy({
        windowId: task.windowId, profileId: task.profileId, privacyMode: task.privacyMode,
        dataScope: task.dataScope, sourcePageUrl: task.request.sourcePageUrl
      }, suggestedFileName, destination);
      if (!completionPolicy.shouldPromptForExport) {
        this.persistCompletionLocalDisplayPath(task, completionPolicy.tempDisplayPath);
        const latest = this.findFinalizingTask(guid);
        if (latest !== undefined) {
          await this.commitAvailableFile(latest, source.size, undefined, silent, completionPolicy.completionMessage);
        }
        return;
      }
      const persisted = await this.persistFinishedDownload(localPath, suggestedFileName, {
        windowId: task.windowId, profileId: task.profileId, privacyMode: task.privacyMode,
        dataScope: task.dataScope, sourcePageUrl: task.request.sourcePageUrl
      }, destination);
      task = this.findFinalizingTask(guid);
      if (task === undefined) return;
      if (persisted?.status === 'user_canceled') {
        const retained = await this.fileResolutionService.inspectReadableFile(localPath);
        task = this.findFinalizingTask(guid);
        if (task === undefined) return;
        if (retained === undefined || retained.size !== source.size) {
          await this.failFileFinalization(task, true, silent, false, false);
          return;
        }
        this.persistCompletionLocalDisplayPath(task, persisted.finalDisplayPath);
        const latest = this.findFinalizingTask(guid);
        if (latest !== undefined) {
          await this.commitAvailableFile(latest, retained.size, persisted, silent,
            resolveAppResourceText($r('app.string.download_export_skipped', suggestedFileName)));
        }
        return;
      }
      if (persisted === undefined || !persisted.isExported || (persisted.finalFileUri?.trim().length ?? 0) <= 0) {
        await this.failExportWithRetainedSource(task, false, silent);
        return;
      }
      const exported = await this.fileResolutionService.inspectReadableFile(persisted.finalFileUri ?? '');
      task = this.findFinalizingTask(guid);
      if (task === undefined) return;
      if (exported === undefined || exported.size !== source.size) {
        await this.failExportWithRetainedSource(task, true, silent);
        return;
      }
      const persistence = this.mergePersistenceSnapshot(task, this.buildPlatformSnapshotFromTask(task));
      persistence.finalFileUri = persisted.finalFileUri;
      if (persisted.destination !== undefined) {
        persistence.destination = persisted.destination;
      } else if (destination.kind === 'prompt') {
        persistence.destination = { kind: 'file', uri: persisted.finalFileUri, label: persisted.finalDisplayPath };
      }
      persistence.finalDisplayPath = persisted.finalDisplayPath;
      persistence.writtenBytes = source.size;
      this.engine.synchronizeTask(guid, {
        persistence: persistence,
        resolvedFileName: persisted.finalFileName ?? task.resolvedFileName ?? suggestedFileName
      });
      const latest = this.findFinalizingTask(guid);
      if (latest !== undefined) await this.commitAvailableFile(latest, source.size, persisted, silent);
    } catch (error) {
      hilog.error(DOWNLOAD_V2_SERVICE_DOMAIN, DOWNLOAD_V2_SERVICE_TAG,
        'file finalization failed guid=%{public}s error=%{public}s', guid, JSON.stringify(error));
      const task = this.engine.findTask(guid);
      if (task !== undefined && (task.persistence.completionState === 'finalizing' ||
        this.completionCommitGuids[guid] === true)) {
        await this.failFileFinalization(task, false, silent);
      }
    } finally {
      this.completedPersistenceGuids[guid] = undefined;
      this.completionCommitGuids[guid] = undefined;
    }
  }

  private findFinalizingTask(guid: string): DownloadV2TaskEntity | undefined {
    const task = this.engine.findTask(guid);
    return task?.status === 'running' && task.persistence.completionState === 'finalizing' ? task : undefined;
  }

  private isFinalizationSourceValid(task: DownloadV2TaskEntity, size: number): boolean {
    if (size === 0 && task.progress.receivedBytes > 0) return false;
    const isHls = task.persistence.downloadDriver === 'libcurl' &&
      this.isHlsCapturedRequest(this.buildCapturedRequestFromTask(task));
    return isHls || task.progress.totalBytes <= 0 || size === task.progress.totalBytes;
  }

  private async failExportWithRetainedSource(
    task: DownloadV2TaskEntity, verificationFailed: boolean, silent: boolean, clearInvalidTarget: boolean = false,
    permissionDenied: boolean = false
  ): Promise<void> {
    const source = await this.fileResolutionService.inspectReadableFile(task.persistence.tempFilePath ?? '');
    let current = this.findFinalizingTask(task.guid);
    if (current === undefined) return;
    const canRetryExport = source !== undefined && this.isFinalizationSourceValid(current, source.size) &&
      ((current.persistence.finalFileUri?.trim().length ?? 0) <= 0 || current.persistence.writtenBytes === undefined ||
        source.size === current.persistence.writtenBytes);
    if (clearInvalidTarget && canRetryExport) {
      const persistence = this.mergePersistenceSnapshot(current, this.buildPlatformSnapshotFromTask(current));
      persistence.finalFileUri = undefined;
      this.engine.synchronizeTask(current.guid, { persistence: persistence });
      current = this.findFinalizingTask(task.guid);
      if (current === undefined) return;
    }
    await this.failFileFinalization(current, verificationFailed || !canRetryExport, silent,
      canRetryExport && permissionDenied, canRetryExport);
  }

  private async failFileFinalization(
    task: DownloadV2TaskEntity, verificationFailed: boolean, silent: boolean, permissionDenied: boolean = false,
    canRetryExport: boolean = true
  ): Promise<void> {
    const current = this.engine.findTask(task.guid);
    if (current === undefined || current.status === 'canceled' || current.status === 'removed') return;
    const persistence = this.mergePersistenceSnapshot(current, this.buildPlatformSnapshotFromTask(current));
    persistence.completionState = 'export_failed';
    const message = permissionDenied ? resolveAppResourceText($r('app.string.download_failure_permission')) : verificationFailed
      ? resolveAppResourceText($r('app.string.download_file_verification_failed'))
      : resolveAppResourceText($r('app.string.download_save_failed_retry'));
    this.engine.synchronizeTask(task.guid, {
      status: 'failed', persistence: persistence, progress: { speedBytesPerSecond: 0 },
      runtime: { resumeCapability: 'none' },
      failure: { code: permissionDenied ? 'permission' : 'file_system', message: message, retriable: canRetryExport },
      clearTimingFields: ['completedAt'], timing: { failedAt: Date.now() }
    });
    try {
      await this.repository.flushPersistence();
    } catch (error) {
      hilog.error(DOWNLOAD_V2_SERVICE_DOMAIN, DOWNLOAD_V2_SERVICE_TAG,
        'save failure persistence failed guid=%{public}s error=%{public}s', task.guid, JSON.stringify(error));
    }
    if (!silent && this.engine.findTask(task.guid)?.status === 'failed') this.callbacks.onError?.(message);
  }

  private async commitAvailableFile(
    task: DownloadV2TaskEntity, size: number, persisted: DownloadPersistResult | undefined, silent: boolean,
    completionMessage?: string
  ): Promise<void> {
    const persistence = this.mergePersistenceSnapshot(task, this.buildPlatformSnapshotFromTask(task));
    persistence.writtenBytes = size;
    // Persist the verified location before making the completed action set visible.
    this.engine.synchronizeTask(task.guid, { persistence: persistence });
    await this.repository.flushPersistence();
    const current = this.findFinalizingTask(task.guid);
    if (current === undefined) return;
    const available = this.mergePersistenceSnapshot(current, this.buildPlatformSnapshotFromTask(current));
    available.completionState = 'available';
    this.completionCommitGuids[task.guid] = true;
    const completed = this.engine.dispatch(task.guid, 'finish', {
      persistence: available, failure: buildDownloadV2EmptyFailure(),
      progress: { totalBytes: size, receivedBytes: size, speedBytesPerSecond: 0 },
      runtime: { resumeCapability: 'none', pauseReason: 'none' }
    });
    if (completed === undefined) return;
    await this.repository.flushPersistence();
    const latest = this.engine.findTask(task.guid);
    if (latest?.status !== 'completed' || latest.persistence.completionState !== 'available') return;
    this.completionCommitGuids[task.guid] = undefined;
    this.notifyTaskChanged(latest);
    this.recordDownloadActivityOnce(task.guid);
    if (!silent) {
      this.callbacks.onInfo?.(completionMessage ?? (persisted?.isExported === true
        ? this.buildSavedLocationMessage('completed', latest.resolvedFileName ?? latest.suggestedFileName, persisted)
        : resolveAppResourceText($r('app.string.download_completed_file', latest.resolvedFileName ?? latest.suggestedFileName))));
    }
    const localPath = latest.persistence.tempFilePath?.trim() ?? '';
    if ((latest.persistence.finalFileUri?.trim().length ?? 0) <= 0 || localPath.length <= 0) return;
    const cleaned = await this.cleanupLocalTempFile(localPath, latest.guid, latest.suggestedFileName, 'completed_export');
    const afterCleanup = this.engine.findTask(task.guid);
    if (!cleaned || afterCleanup?.status !== 'completed' || afterCleanup.persistence.completionState !== 'available') return;
    const cleanedPersistence = this.mergePersistenceSnapshot(afterCleanup, this.buildPlatformSnapshotFromTask(afterCleanup));
    cleanedPersistence.tempFilePath = undefined;
    cleanedPersistence.partialFilePath = undefined;
    this.engine.synchronizeTask(task.guid, { persistence: cleanedPersistence });
    await this.repository.flushPersistence();
  }

  private async persistFinishedDownload(
    localPath: string,
    suggestedFileName: string,
    boundary: DownloadTaskBoundary,
    destination?: DownloadV2DestinationSnapshot
  ): Promise<DownloadPersistResult | undefined> {
    if (destination !== undefined) {
      return this.fileResolutionService.persistToDestination(localPath, suggestedFileName, destination);
    }
    const savePolicy = this.downloadPolicyService.resolveSavePolicy(boundary);
    let customDirectoryBypassed = false;
    if (!savePolicy.isPrivateSession) {
      const customDirectory = resolveCustomDownloadDirectory(savePolicy.settings);
      if (customDirectory !== undefined) {
        const persisted = await this.fileResolutionService.persistToDirectory(
          localPath,
          suggestedFileName,
          customDirectory.uri,
          customDirectory.label
        );
        if (persisted !== undefined && persisted.isExported) {
          return persisted;
        }
        customDirectoryBypassed = true;
      }
    }
    const fallbackPersisted = await this.fileResolutionService.persistToSystemDownloads(localPath, suggestedFileName);
    if (customDirectoryBypassed && fallbackPersisted !== undefined && fallbackPersisted.isExported) {
      fallbackPersisted.customDirectoryBypassed = true;
    }
    return fallbackPersisted;
  }

  private buildSavedLocationMessage(
    kind: 'saved' | 'completed',
    fileName: string,
    persisted: DownloadPersistResult | undefined
  ): string {
    const location = persisted?.destinationLabel !== undefined && persisted.destinationLabel.length > 0
      ? persisted.destinationLabel
      : resolveAppResourceText($r('app.string.download_system_downloads'));
    if (kind === 'completed' && persisted?.customDirectoryBypassed === true) {
      return resolveAppResourceText(
        $r('app.string.download_completed_custom_folder_unavailable', location, fileName)
      );
    }
    return resolveAppResourceText(kind === 'saved'
      ? $r('app.string.download_saved_to_location', location, fileName)
      : $r('app.string.download_completed_saved_to', location, fileName));
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
        expectedTotalBytes: task.persistence.expectedTotalBytes,
        etag: task.persistence.etag,
        lastModified: task.persistence.lastModified,
        acceptRanges: task.persistence.acceptRanges,
        contentRange: task.persistence.contentRange,
        validatorCapturedAt: task.persistence.validatorCapturedAt,
        downloadDriver: task.persistence.downloadDriver,
        resumeMode: task.persistence.resumeMode,
        needsFullRestart: task.persistence.needsFullRestart,
        restartReason: task.persistence.restartReason,
        destination: task.persistence.destination,
        completionState: task.persistence.completionState,
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
        platformTaskId: task.runtime.platformTaskId,
        platformTaskToken: task.runtime.platformTaskToken,
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
        message: resolveAppResourceText($r('app.string.download_canceled_message')),
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
        this.callbacks.onError?.(resolveAppResourceText($r('app.string.download_cleanup_failed', suggestedFileName)));
      }
      return false;
    }
  }

  private shouldReconnectPersistedTask(task: DownloadV2TaskEntity): boolean {
    if (!isDownloadV2ActiveStatus(task.status)) {
      return false;
    }
    return task.persistence.completionState === 'finalizing' || task.persistence.completionState === 'available' ||
      task.persistence.downloadDriver === 'arkweb' ||
      (task.runtime.platformTaskId?.trim().length ?? 0) > 0;
  }

  private markTaskRestoreUnavailable(guid: string): void {
    const currentTask = this.engine.findTask(guid);
    if (currentTask === undefined) {
      return;
    }
    if (currentTask.persistence.downloadDriver === 'libcurl' &&
      (currentTask.status === 'running' || currentTask.status === 'queued' ||
        currentTask.runtime.pauseReason === 'network' || currentTask.runtime.pauseReason === 'wifi_policy') &&
      (currentTask.persistence.tempFilePath?.trim().length ?? 0) > 0) {
      const persistence = this.mergePersistenceSnapshot(currentTask, this.buildPlatformSnapshotFromTask(currentTask));
      persistence.resumeMode = 'platform_live_resume';
      this.engine.synchronizeTask(guid, {
        status: 'queued', persistence: persistence, progress: { speedBytesPerSecond: 0 },
        runtime: { pauseReason: 'none', resumeCapability: 'retry_only' },
        failure: buildDownloadV2EmptyFailure()
      });
      return;
    }
    hilog.info(
      DOWNLOAD_V2_SERVICE_DOMAIN,
      DOWNLOAD_V2_SERVICE_TAG,
      'restore degraded to failed guid=%{public}s',
      guid
    );
    this.engine.synchronizeTask(guid, {
      status: currentTask.status === 'paused' &&
        currentTask.runtime.pauseReason !== 'network' && currentTask.runtime.pauseReason !== 'wifi_policy'
        ? 'paused' : 'failed',
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

  private buildArkWebContextUnavailableFailure(task: DownloadV2TaskEntity): DownloadV2Failure {
    return {
      code: 'context_lost',
      sourceCode: task.failure.sourceCode,
      message: resolveAppResourceText($r('app.string.download_browser_context_unavailable')),
      retriable: false
    };
  }

  private buildTaskLostFailure(task: DownloadV2TaskEntity): DownloadV2Failure {
    if (task.persistence.downloadDriver === 'arkweb') {
      return this.buildArkWebContextUnavailableFailure(task);
    }
    const partialBytes = Math.max(task.progress.receivedBytes, task.persistence.writtenBytes ?? 0);
    return {
      code: 'context_lost',
      sourceCode: task.failure.sourceCode,
      message: partialBytes > 0
        ? resolveAppResourceText($r('app.string.download_paused_progress_kept'))
        : resolveAppResourceText($r('app.string.download_connection_lost')),
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
      sourceId: current.sourceId ?? event.snapshot.sourceId,
      nativeReason: current.nativeReason,
      fileNameLocked: current.fileNameLocked,
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
    currentFailure: DownloadV2Failure,
    driver: DownloadV2Driver = event.snapshot.downloadDriver ?? 'arkweb'
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
        message: resolveAppResourceText($r('app.string.download_canceled_message')),
        retriable: false
      };
    }
    const classification = classifyDownloadV2Failure(driver, event.snapshot.lastErrorCode);
    return {
      code: classification.code,
      sourceCode: event.snapshot.lastErrorCode,
      message: this.resolveFailureMessage(classification.reason, event.snapshot.suggestedFileName),
      retriable: classification.retriable
    };
  }

  private resolveFailureMessage(reason: DownloadV2FailureReason, fileName: string): string {
    switch (reason) {
      case 'network': return resolveAppResourceText($r('app.string.download_failure_network'));
      case 'permission': return resolveAppResourceText($r('app.string.download_failure_permission'));
      case 'storage': return resolveAppResourceText($r('app.string.download_failure_storage'));
      case 'file_system': return resolveAppResourceText($r('app.string.download_failure_file_system'));
      case 'server': return resolveAppResourceText($r('app.string.download_failure_server'));
      case 'certificate': return resolveAppResourceText($r('app.string.download_failure_certificate'));
      case 'unsupported': return resolveAppResourceText($r('app.string.download_failure_unsupported'));
      case 'canceled': return resolveAppResourceText($r('app.string.download_canceled_message'));
      default: return resolveAppResourceText($r('app.string.download_failed_file', fileName));
    }
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

  private applyRememberedPageDownloadIdentity(request: DownloadV2CapturedRequest): void {
    const now = Date.now();
    const normalizedUrl = this.normalizeDownloadIdentityUrl(request.url);
    const matchedIdentity: PageDownloadIdentity = {
      url: '',
      userAgent: '',
      contentDisposition: '',
      mimeType: '',
      observedAt: 0
    };
    this.pageDownloadIdentities = this.pageDownloadIdentities.filter((identity: PageDownloadIdentity) => {
      if (now - identity.observedAt > DownloadV2Service.PAGE_DOWNLOAD_IDENTITY_WINDOW_MS) {
        return false;
      }
      if (identity.url === normalizedUrl) {
        matchedIdentity.url = identity.url;
        matchedIdentity.userAgent = identity.userAgent;
        matchedIdentity.contentDisposition = identity.contentDisposition;
        matchedIdentity.mimeType = identity.mimeType;
        matchedIdentity.observedAt = identity.observedAt;
      }
      return true;
    });
    if (matchedIdentity.userAgent.length <= 0) {
      return;
    }
    const identity = matchedIdentity;
    if ((request.userAgent?.trim().length ?? 0) <= 0) {
      request.userAgent = identity.userAgent;
    }
    if ((request.contentDisposition?.trim().length ?? 0) <= 0 && identity.contentDisposition.length > 0) {
      request.contentDisposition = identity.contentDisposition;
    }
    if ((request.mimeType?.trim().length ?? 0) <= 0 && identity.mimeType.length > 0) {
      request.mimeType = identity.mimeType;
    }
    const snapshot = request.platformSnapshot;
    if (snapshot === undefined) {
      return;
    }
    if ((snapshot.userAgent?.trim().length ?? 0) <= 0) {
      snapshot.userAgent = identity.userAgent;
    }
    if ((snapshot.contentDisposition?.trim().length ?? 0) <= 0 && identity.contentDisposition.length > 0) {
      snapshot.contentDisposition = identity.contentDisposition;
    }
    if ((snapshot.mimeType?.trim().length ?? 0) <= 0 && identity.mimeType.length > 0) {
      snapshot.mimeType = identity.mimeType;
    }
  }

  private normalizeDownloadIdentityUrl(url: string): string {
    const trimmed = url.trim();
    const hashIndex = trimmed.indexOf('#');
    return hashIndex >= 0 ? trimmed.substring(0, hashIndex) : trimmed;
  }

  private downloadIdentityHost(url: string): string {
    const schemeSeparator = url.indexOf('://');
    const start = schemeSeparator >= 0 ? schemeSeparator + 3 : 0;
    const end = url.indexOf('/', start);
    return end >= 0 ? url.substring(start, end) : url.substring(start);
  }

  private isFailureState(state: string): boolean {
    const normalized = state.trim().toUpperCase();
    return normalized.indexOf('FAIL') >= 0 || normalized.indexOf('ERROR') >= 0 || normalized.indexOf('INTERRUPT') >= 0;
  }

  private buildEngineObserver(): DownloadV2EngineObserver {
    return {
      onTaskChanged: (task: DownloadV2TaskEntity) => {
        this.notifyTaskChanged(task);
      },
      onTaskRemoved: (guid: string) => {
        this.previousStatusByGuid[guid] = undefined;
        this.systemNotificationService?.handleTaskRemoved(guid);
        this.callbacks.onTaskRemoved?.(guid);
      }
    };
  }

  private notifyTaskChanged(task: DownloadV2TaskEntity): void {
    if (task.status === 'completed' && this.completionCommitGuids[task.guid] === true) return;
    const previousStatus = this.previousStatusByGuid[task.guid];
    this.previousStatusByGuid[task.guid] = task.status;
    this.systemNotificationService?.handleTaskChanged(task, previousStatus);
    this.callbacks.onTaskChanged?.(task, this.resolveTaskChangeKind(task));
  }

  private resolveTaskChangeKind(task: DownloadV2TaskEntity): DownloadV2TaskChangeKind {
    if (isDownloadV2TerminalStatus(task.status)) {
      return 'terminal';
    }
    if (task.status === 'running' && task.persistence.completionState !== 'finalizing') {
      return 'progress';
    }
    return 'structural';
  }
}
