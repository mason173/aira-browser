import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
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
import { DownloadFileActionService, DownloadFileAvailability } from './DownloadFileActionService';
import { DownloadPolicyService, DownloadSavePolicy, DownloadSessionCleanupPolicy } from './DownloadPolicyService';
import { resolveCustomDownloadDirectory } from './DownloadLocationDirectoryService';
import {
  DownloadV2CompletedFileRemovalResult,
  DownloadV2Service,
  DownloadV2TaskChangeKind
} from '../downloadv2/DownloadV2Service';
import { DownloadV2Prompt } from '../../features/downloadv2/DownloadV2CaptureTypes';
import { DownloadV2ManualRequestContext } from '../../features/downloadv2/DownloadV2RequestCapture';
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

interface PendingPromptLocationState {
  /** The path (or "chosen at save time" text) shown on the location row. */
  path: string;
  /** False for private sessions, which never honour the custom folder. */
  canChange: boolean;
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
  /**
   * Where the finished file will land, resolved from live settings at prompt
   * time (never cached) so changing the folder from the prompt is reflected
   * immediately. Shown verbatim on the prompt's location row.
   */
  locationPath: string;
  /** Whether the prompt may offer a folder change action at all. */
  canChangeLocation: boolean;
  /**
   * True when this prompt came from an ArkWeb WebDownloadItem (the site handed the browser a
   * download, usually via Content-Disposition: attachment). Such a request must never be
   * reclassified as an inline document: ArkWeb's WebDownloadItem exposes no Content-Disposition,
   * so the delegate-derived mimeType alone (e.g. application/pdf) would otherwise be mistaken for
   * a document to render inline and the download would be silently dropped.
   */
  isPlatformDownload: boolean;
  /** An explicit URL/link/resource download has no ArkWeb item until after confirmation. */
  isUserInitiatedDownload?: boolean;
}

export interface ManualDownloadRequestInput {
  url: string;
  sourceTabId?: string;
  headersSource?: 'page' | 'explicit';
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

export interface ManualDownloadBatchResult {
  queued: number;
  failed: number;
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

interface WebDownloadStartContext {
  sourceId: string;
  url: string;
  userAgent: string;
  contentDisposition: string;
  mimeType: string;
  contentLength: number;
  observedAt: number;
}

interface PageDownloadSource {
  sourceId: string;
  boundary: DownloadTaskBoundary;
  controller?: webview.WebviewController;
}

interface ResolvedManualDownloadRequest {
  boundary: DownloadTaskBoundary;
  context: DownloadV2ManualRequestContext;
}

interface DownloadFileAvailabilitySnapshot {
  location: string;
  availability: DownloadFileAvailability;
}

const WEB_DOWNLOAD_START_MATCH_WINDOW_MS: number = 10000;
const WEB_DOWNLOAD_START_CONTEXT_LIMIT: number = 8;
export type DownloadTaskFollowupAction = 'open_file' | 'open_location' | 'share_file';

export class DownloadRuntimeService {
  private downloadBridge: PlatformDownloadAdapter;
  private downloadV2Service: DownloadV2Service;
  private isSyncingActiveDownloads: boolean = false;
  private queryService: DownloadQueryService = new DownloadQueryService();
  private fileResolutionService: DownloadFileResolutionAdapter;
  private downloadFollowupService: DownloadFollowupService;
  private fileActionService: DownloadFileActionService;
  private fileActionGuids: Set<string> = new Set<string>();
  private fileAvailabilityByGuid: Map<string, DownloadFileAvailabilitySnapshot> =
    new Map<string, DownloadFileAvailabilitySnapshot>();
  private downloadPolicyService: DownloadPolicyService;
  private recentWebDownloadStarts: WebDownloadStartContext[] = [];
  private pageDownloadSources: Map<string, PageDownloadSource> = new Map<string, PageDownloadSource>();
  private downloadSourceBoundaries: Map<string, DownloadTaskBoundary> = new Map<string, DownloadTaskBoundary>();
  private downloadGuidBoundaries: Map<string, DownloadTaskBoundary> = new Map<string, DownloadTaskBoundary>();
  private nextDownloadSourceId: number = 1;
  private readonly downloadSourceSessionId: string = util.generateRandomUUID();
  private initialized: boolean = false;
  private repositoryInitializationPromise?: Promise<void>;
  private repositoryHydrated: boolean = false;
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
    this.fileActionService = new DownloadFileActionService(this.fileResolutionService);
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
      onTaskRemoved: (guid: string) => {
        this.downloadGuidBoundaries.delete(guid);
        this.fileAvailabilityByGuid.delete(guid);
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
        this.repositoryHydrated = true;
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

  registerPageDownloadSource(
    tabId: string,
    controller: webview.WebviewController | undefined,
    boundary: DownloadTaskBoundary
  ): void {
    if (tabId.trim().length === 0) {
      return;
    }
    this.initialize();
    const normalizedBoundary = this.normalizeBoundary(boundary);
    const previous = this.pageDownloadSources.get(tabId);
    if (previous !== undefined && previous.controller === controller &&
      previous.boundary.windowId === normalizedBoundary.windowId &&
      previous.boundary.profileId === normalizedBoundary.profileId &&
      previous.boundary.privacyMode === normalizedBoundary.privacyMode &&
      previous.boundary.dataScope === normalizedBoundary.dataScope &&
      previous.boundary.sourcePageUrl === normalizedBoundary.sourcePageUrl) {
      return;
    }
    if (previous !== undefined) this.downloadBridge.unregisterDownloadSource?.(previous.sourceId);
    // A replaced controller keeps its old source identity for late callbacks.
    const sourceId = `${this.downloadSourceSessionId}:${tabId}:download:${this.nextDownloadSourceId}`;
    this.nextDownloadSourceId += 1;
    const source: PageDownloadSource = { sourceId: sourceId, boundary: normalizedBoundary };
    this.pageDownloadSources.set(tabId, source);
    this.downloadSourceBoundaries.set(sourceId, normalizedBoundary);
    if (controller === undefined || this.downloadBridge.getDelegateForSource === undefined) {
      return;
    }
    try {
      controller.setDownloadDelegate(this.downloadBridge.getDelegateForSource(sourceId));
      this.downloadBridge.registerDownloadSource?.(sourceId, (url: string): void => controller.startDownload(url));
      source.controller = controller;
    } catch (_error) {
      this.downloadBridge.unregisterDownloadSource?.(sourceId);
    }
  }

  retainPageDownloadSources(windowId: string, tabIds: string[]): void {
    this.pageDownloadSources.forEach((source: PageDownloadSource, tabId: string) => {
      if (source.boundary.windowId === windowId && tabIds.indexOf(tabId) < 0) {
        this.downloadBridge.unregisterDownloadSource?.(source.sourceId);
        this.pageDownloadSources.delete(tabId);
      }
    });
  }

  requestPageDownload(tabId: string, input: ManualDownloadRequestInput): ManualDownloadRequestResult | undefined {
    // The manual confirmation creates the stable task GUID; only admitted tasks start ArkWeb.
    return this.requestManualDownload(input, tabId);
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

  async openFileForBoundary(
    guid: string, boundary: DownloadTaskBoundary, onFailure?: (message: string) => void
  ): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'open_file')) {
      return Promise.resolve(false);
    }
    const v2Task = this.resolveV2FollowupTask(guid, boundary, 'open_file');
    if (v2Task !== undefined) {
      const entity = this.getTaskByGuid(guid);
      if (entity !== undefined) await this.fileActionService.inspectTask(entity);
      return this.downloadFollowupService.openFile(v2Task)
        .then((result: DownloadFollowupExecutionResult) => {
          this.emitScopedFileActionResult(result.success, result.userMessage, onFailure);
          return result.success;
        });
    }
    return Promise.resolve(false);
  }

  openLocationForBoundary(
    guid: string, boundary: DownloadTaskBoundary, onFailure?: (message: string) => void
  ): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'open_location')) {
      return Promise.resolve(false);
    }
    const v2Task = this.resolveV2FollowupTask(guid, boundary, 'open_location');
    if (v2Task !== undefined) {
      return this.downloadFollowupService.openLocation(v2Task)
        .then((result: DownloadFollowupExecutionResult) => {
          this.emitScopedFileActionResult(result.success, result.userMessage, onFailure);
          return result.success;
        });
    }
    return Promise.resolve(false);
  }

  async shareFileForBoundary(
    guid: string, boundary: DownloadTaskBoundary, onFailure?: (message: string) => void
  ): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'share_file')) return Promise.resolve(false);
    const task = this.resolveV2FollowupTask(guid, boundary, 'share_file');
    if (task === undefined) return Promise.resolve(false);
    const entity = this.getTaskByGuid(guid);
    if (entity !== undefined) await this.fileActionService.inspectTask(entity);
    return this.downloadFollowupService.shareFile(task).then((result: DownloadFollowupExecutionResult): boolean => {
      this.emitScopedFileActionResult(result.success, result.userMessage, onFailure);
      return result.success;
    });
  }

  async inspectTaskFileForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<DownloadFileAvailability> {
    const task = this.getTaskByGuid(guid);
    if (task === undefined || task.status !== 'completed' ||
      !this.downloadPolicyService.canReadSessionTasks(boundary) ||
      !this.isTaskInsideBoundary(task, this.normalizeBoundary(boundary))) return 'unavailable';
    const location = task.persistence.finalFileUri?.trim() || task.persistence.tempFilePath?.trim() || '';
    const availability = await this.fileActionService.inspectTask(task);
    const latest = this.getTaskByGuid(guid);
    const latestLocation = latest?.persistence.finalFileUri?.trim() || latest?.persistence.tempFilePath?.trim() || '';
    if (latest !== undefined && latestLocation === location) {
      const previous = this.fileAvailabilityByGuid.get(guid);
      this.fileAvailabilityByGuid.set(guid, { location: location, availability: availability });
      if (previous?.location !== location || previous?.availability !== availability) this.emitTaskListChange('important');
    }
    return availability;
  }

  async renameTaskForBoundary(
    guid: string, newBaseName: string, boundary: DownloadTaskBoundary, onFailure?: (message: string) => void
  ): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'rename')) return false;
    const task = this.getTaskByGuid(guid);
    if (task === undefined) return false;
    this.fileActionGuids.add(guid);
    this.emitTaskListChange('important');
    try {
      const prepared = await this.fileActionService.prepareRename(task, newBaseName);
      const plan = prepared.plan;
      if (plan === undefined) {
        this.emitScopedFileActionResult(false, resolveAppResourceText(prepared.failure === 'unsupported'
          ? $r('app.string.download_rename_unsupported') : $r('app.string.download_rename_failed')), onFailure);
        return false;
      }
      try {
        const committed = await this.downloadV2Service.updateCompletedFileAfterRename(guid, plan.sourceLocation, {
          fileName: plan.fileName, tempFilePath: plan.tempFilePath,
          finalFileUri: plan.finalFileUri, finalDisplayPath: plan.finalDisplayPath
        });
        if (committed !== 'committed') {
          // A failed durable rollback can leave the on-disk record at either location.
          // Keep both possible targets until persistence is trustworthy again.
          const rolledBack = committed === 'restored' && await this.fileActionService.rollbackRename(plan);
          this.emitScopedFileActionResult(false, resolveAppResourceText(rolledBack
            ? $r('app.string.download_rename_failed') : $r('app.string.download_rename_cleanup_failed')), onFailure);
          return false;
        }
        if (!await this.fileActionService.finishRename(plan)) {
          // The directory copy is durable, but the old file could not be removed. Restore
          // metadata first; never delete the new file while the task still points to it.
          // A provider may recycle the source before reporting an error. In that case the
          // verified new file is the only known copy and must keep its task metadata.
          const restored = await this.fileActionService.canRestoreOriginal(plan)
            ? await this.downloadV2Service.updateCompletedFileAfterRename(guid, plan.targetLocation, {
            fileName: task.resolvedFileName?.trim() || task.suggestedFileName,
            tempFilePath: task.persistence.tempFilePath, finalFileUri: task.persistence.finalFileUri,
            finalDisplayPath: task.persistence.finalDisplayPath
            }) : 'uncertain';
          const rolledBack = restored === 'committed' && await this.fileActionService.rollbackRename(plan);
          this.emitScopedFileActionResult(false, resolveAppResourceText(rolledBack
            ? $r('app.string.download_rename_failed') : $r('app.string.download_rename_cleanup_failed')), onFailure);
          return false;
        }
        this.emitInfo(resolveAppResourceText($r('app.string.download_rename_succeeded')));
        return true;
      } finally {
        this.fileActionService.releaseRename(plan);
      }
    } catch (_error) {
      this.emitScopedFileActionResult(false, resolveAppResourceText($r('app.string.download_rename_cleanup_failed')), onFailure);
      return false;
    } finally {
      this.fileActionGuids.delete(guid);
      this.emitTaskListChange('important');
    }
  }

  canRedownloadMissingTaskForBoundary(guid: string, boundary: DownloadTaskBoundary): boolean {
    const task = this.getTaskByGuid(guid);
    return task !== undefined && !this.fileActionGuids.has(guid) &&
      this.downloadPolicyService.canReadSessionTasks(boundary) &&
      this.downloadPolicyService.canWriteSessionTasks(boundary) &&
      this.isTaskInsideBoundary(task, this.normalizeBoundary(boundary)) && this.fileActionService.canRedownload(task);
  }

  /** Called only after the missing-file confirmation, never from an open failure or timer. */
  async redownloadMissingTaskForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.canRedownloadMissingTaskForBoundary(guid, boundary)) return false;
    this.fileActionGuids.add(guid);
    this.emitTaskListChange('important');
    try {
      if (await this.inspectTaskFileForBoundary(guid, boundary) !== 'missing') return false;
      const task = this.getTaskByGuid(guid);
      if (task === undefined || !this.downloadPolicyService.canReadSessionTasks(boundary) ||
        !this.downloadPolicyService.canWriteSessionTasks(boundary) ||
        !this.isTaskInsideBoundary(task, this.normalizeBoundary(boundary)) ||
        !this.fileActionService.canRedownload(task)) return false;
      const url = task.request.originalUrl?.trim() || task.request.url;
      let sourceTabId = '';
      this.pageDownloadSources.forEach((source: PageDownloadSource, tabId: string): void => {
        if (source.controller !== undefined && source.boundary.profileId === task.profileId &&
          source.boundary.privacyMode === task.privacyMode && source.boundary.dataScope === task.dataScope &&
          source.boundary.windowId === boundary.windowId &&
          source.boundary.sourcePageUrl === task.request.sourcePageUrl) sourceTabId = tabId;
      });
      const resolved = this.resolveManualDownloadRequest({
        url: url, sourceTabId: sourceTabId.length > 0 ? sourceTabId : undefined,
        suggestedFileName: task.resolvedFileName || task.suggestedFileName,
        userAgent: task.request.userAgent, referer: task.request.referer, mimeType: task.request.mimeType,
        headers: task.request.headers, headersSource: task.request.nativeReason === 'custom_headers' ? 'explicit' : 'page'
      }, { windowId: boundary.windowId, profileId: task.profileId, privacyMode: task.privacyMode,
        dataScope: task.dataScope, sourcePageUrl: task.request.sourcePageUrl });
      if (resolved === undefined) return false;
      // A new, user-confirmed request gets a new identity. Never reuse the completed GUID/token.
      const created = await this.downloadV2Service.createConfirmedManualRequest(url, {
        windowId: boundary.windowId ?? '', profileId: task.profileId, privacyMode: task.privacyMode,
        dataScope: task.dataScope, sourcePageUrl: task.request.sourcePageUrl
      }, task.resolvedFileName || task.suggestedFileName, task.request.sourceHost, resolved.context);
      return created !== undefined && created.status !== 'failed' && created.status !== 'canceled';
    } catch (_error) {
      return false;
    } finally {
      this.fileActionGuids.delete(guid);
      this.emitTaskListChange('important');
    }
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

  chooseTaskLocationForBoundary(guid: string, boundary: DownloadTaskBoundary): Promise<boolean> {
    if (!this.canExecuteTaskAction(guid, boundary, 'choose_location')) {
      return Promise.resolve(false);
    }
    return this.downloadV2Service.chooseTaskLocation(guid);
  }

  hasDownloadDestinationReference(uri: string): boolean {
    const normalizedUri = uri.trim();
    if (normalizedUri.length > 0 && !this.repositoryHydrated) return true;
    return normalizedUri.length > 0 && this.downloadV2Service.listTasks().some((task: DownloadV2TaskEntity): boolean =>
      task.status !== 'canceled' && task.status !== 'removed' && task.persistence.destination?.uri === normalizedUri);
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
    this.pageDownloadSources.forEach((source: PageDownloadSource, tabId: string) => {
      if (this.matchesSourceBoundary(source.boundary, boundary)) {
        this.downloadBridge.unregisterDownloadSource?.(source.sourceId);
        this.pageDownloadSources.delete(tabId);
      }
    });
    this.downloadSourceBoundaries.forEach((sourceBoundary: DownloadTaskBoundary, sourceId: string) => {
      if (this.matchesSourceBoundary(sourceBoundary, boundary)) {
        this.downloadSourceBoundaries.delete(sourceId);
      }
    });
    this.downloadGuidBoundaries.forEach((taskBoundary: DownloadTaskBoundary, guid: string) => {
      if (this.matchesSourceBoundary(taskBoundary, boundary)) {
        this.downloadGuidBoundaries.delete(guid);
      }
    });
    this.recentWebDownloadStarts = this.recentWebDownloadStarts.filter((context: WebDownloadStartContext) =>
      this.downloadSourceBoundaries.has(context.sourceId));
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
      const location = this.resolvePendingPromptLocation(v2Prompt);
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
        cancelLabel: v2Prompt.cancelLabel,
        locationPath: location.path,
        canChangeLocation: location.canChange,
        isPlatformDownload: this.isPlatformDownloadPrompt(v2Prompt.guid),
        isUserInitiatedDownload: this.isUserInitiatedDownloadPrompt(v2Prompt.guid)
      };
    }
    return undefined;
  }

  private isPlatformDownloadPrompt(guid: string): boolean {
    return this.downloadV2Service.getCapturedRequest(guid)?.platformSnapshot !== undefined;
  }

  private isUserInitiatedDownloadPrompt(guid: string): boolean {
    const request = this.downloadV2Service.getCapturedRequest(guid);
    return request !== undefined && request.platformSnapshot === undefined;
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
        this.emitError(resolveAppResourceText($r('app.string.download_init_failed')));
        return false;
      });
  }

  /**
   * Remembers the Web component's onDownloadStart until the matching download item arrives.
   * ArkWeb's download item does not carry the user agent the page used, so a later libcurl
   * transfer would otherwise identify itself as the download core and be rejected with HTTP 403.
   */
  recordWebDownloadStart(
    tabId: string,
    url: string,
    userAgent: string,
    contentDisposition: string,
    mimeType: string,
    contentLength: number
  ): void {
    const normalizedUrl = this.normalizeDownloadMatchUrl(url);
    const normalizedUserAgent = userAgent.trim();
    const sourceId = this.pageDownloadSources.get(tabId)?.sourceId ?? '';
    if (normalizedUrl.length <= 0 || sourceId.length <= 0) {
      return;
    }
    const now = Date.now();
    this.recentWebDownloadStarts = this.recentWebDownloadStarts.filter((context: WebDownloadStartContext) =>
      now - context.observedAt <= WEB_DOWNLOAD_START_MATCH_WINDOW_MS &&
      (context.url !== normalizedUrl || context.sourceId !== sourceId)
    );
    this.recentWebDownloadStarts.push({
      sourceId: sourceId,
      url: normalizedUrl,
      userAgent: normalizedUserAgent,
      contentDisposition: contentDisposition.trim(),
      mimeType: mimeType.trim(),
      contentLength: Number.isFinite(contentLength) && contentLength > 0 ? contentLength : 0,
      observedAt: now
    });
    if (this.recentWebDownloadStarts.length > WEB_DOWNLOAD_START_CONTEXT_LIMIT) {
      this.recentWebDownloadStarts = this.recentWebDownloadStarts.slice(
        this.recentWebDownloadStarts.length - WEB_DOWNLOAD_START_CONTEXT_LIMIT
      );
    }
  }

  cancelPendingDownload(guid: string): boolean {
    const canceledV2Request = this.downloadV2Service.cancelPendingPrompt(guid);
    if (canceledV2Request !== undefined) {
      this.downloadGuidBoundaries.delete(guid);
      const fileName = canceledV2Request.suggestedFileName?.trim() ?? '';
      const displayName = fileName.length > 0
        ? fileName
        : resolveAppResourceText($r('app.string.download_status_unnamed'));
      this.emitInfo(resolveAppResourceText($r('app.string.download_canceled_named', displayName)));
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
    this.downloadGuidBoundaries.delete(guid);
    return true;
  }

  requestManualDownloadPrompt(input: ManualDownloadRequestInput, sourceTabId: string = ''): PendingDownloadPromptState | undefined {
    const resolved = this.resolveManualDownloadRequest(input, this.activeBoundary, sourceTabId);
    if (resolved === undefined) return undefined;
    const prompt = this.downloadV2Service.createManualPrompt(input.url, {
      windowId: resolved.boundary.windowId ?? '',
      profileId: resolved.boundary.profileId,
      privacyMode: resolved.boundary.privacyMode,
      dataScope: resolved.boundary.dataScope,
      sourcePageUrl: resolved.boundary.sourcePageUrl
    }, input.suggestedFileName, input.sourceHost, resolved.context);
    return prompt === undefined ? undefined : this.withPromptLocation(prompt);
  }

  async requestConfirmedManualDownloads(inputs: ManualDownloadRequestInput[]): Promise<ManualDownloadBatchResult> {
    // Freeze every source and its request context before the first asynchronous task creation.
    const boundary = this.normalizeBoundary(this.activeBoundary);
    const requests: (ResolvedManualDownloadRequest | undefined)[] = inputs.map((input: ManualDownloadRequestInput) =>
      this.resolveManualDownloadRequest(input, boundary));
    const result: ManualDownloadBatchResult = { queued: 0, failed: 0 };
    for (let index = 0; index < inputs.length; index++) {
      const input = inputs[index];
      const resolved = requests[index];
      if (resolved === undefined || !this.downloadPolicyService.canWriteSessionTasks(resolved.boundary)) {
        result.failed += 1;
        continue;
      }
      try {
        const task = await this.downloadV2Service.createConfirmedManualRequest(input.url, {
          windowId: resolved.boundary.windowId ?? '',
          profileId: resolved.boundary.profileId,
          privacyMode: resolved.boundary.privacyMode,
          dataScope: resolved.boundary.dataScope,
          sourcePageUrl: resolved.boundary.sourcePageUrl
        }, input.suggestedFileName, input.sourceHost, resolved.context);
        if (task !== undefined && task.status !== 'failed' && task.status !== 'canceled' && task.status !== 'removed') {
          result.queued += 1;
        } else {
          result.failed += 1;
        }
      } catch (_error) {
        result.failed += 1;
      }
    }
    return result;
  }

  requestManualDownload(input: ManualDownloadRequestInput, sourceTabId: string = ''): ManualDownloadRequestResult | undefined {
    const resolved = this.resolveManualDownloadRequest(input, this.activeBoundary, sourceTabId);
    if (resolved === undefined) return undefined;
    const result = this.downloadV2Service.createManualRequest(input.url, {
      windowId: resolved.boundary.windowId ?? '',
      profileId: resolved.boundary.profileId,
      privacyMode: resolved.boundary.privacyMode,
      dataScope: resolved.boundary.dataScope,
      sourcePageUrl: resolved.boundary.sourcePageUrl
    }, input.suggestedFileName, input.sourceHost, resolved.context);
    if (result === undefined) return undefined;
    return {
      guid: result.guid,
      prompt: this.toPendingDownloadPromptFromV2(result.prompt),
      started: result.started
    };
  }

  private resolveManualDownloadRequest(
    input: ManualDownloadRequestInput,
    initiatingBoundary: DownloadTaskBoundary,
    sourceTabId: string = ''
  ): ResolvedManualDownloadRequest | undefined {
    const frozenBoundary = this.normalizeBoundary(initiatingBoundary);
    const explicitTabId = sourceTabId.trim() || input.sourceTabId?.trim() || '';
    let source: PageDownloadSource | undefined = undefined;
    if (explicitTabId.length > 0) {
      source = this.pageDownloadSources.get(explicitTabId);
      if (source === undefined) return this.rejectUnavailableDownloadSource();
    } else {
      // A global active boundary is only a lookup key, never permission to borrow another tab.
      const candidates: PageDownloadSource[] = [];
      this.pageDownloadSources.forEach((candidate: PageDownloadSource): void => {
        if (candidate.controller !== undefined && this.matchesSourceBoundary(candidate.boundary, frozenBoundary) &&
          (candidate.boundary.windowId ?? '') === (frozenBoundary.windowId ?? '') &&
          candidate.boundary.sourcePageUrl === frozenBoundary.sourcePageUrl) candidates.push(candidate);
      });
      if (candidates.length === 1) source = candidates[0];
    }
    const boundary = this.normalizeBoundary(source?.boundary ?? frozenBoundary);
    if (!this.downloadPolicyService.canWriteSessionTasks(boundary)) return undefined;
    const nativeReason = this.resolveManualNativeReason(input, boundary.sourcePageUrl ?? '');
    if (nativeReason === undefined && source?.controller === undefined) return this.rejectUnavailableDownloadSource();
    const headers: Record<string, string> = {};
    if (input.headers !== undefined) {
      Object.keys(input.headers).forEach((name: string): void => { headers[name] = input.headers?.[name] ?? ''; });
    }
    return {
      boundary: boundary,
      context: {
        sourceId: source?.sourceId,
        nativeReason: nativeReason,
        userAgent: input.userAgent ?? this.resolveSourceUserAgent(source),
        referer: input.referer ?? boundary.sourcePageUrl,
        mimeType: input.mimeType,
        contentDisposition: input.contentDisposition,
        totalBytes: input.totalBytes,
        headers: input.headers === undefined ? undefined : headers
      }
    };
  }

  private rejectUnavailableDownloadSource(): undefined {
    this.emitError(resolveAppResourceText($r('app.string.download_browser_context_unavailable')));
    return undefined;
  }

  private resolveSourceUserAgent(source?: PageDownloadSource): string | undefined {
    if (source?.controller === undefined) return undefined;
    try {
      const custom = source.controller.getCustomUserAgent().trim();
      return custom.length > 0 ? custom : source.controller.getUserAgent().trim();
    } catch (_error) {
      return undefined;
    }
  }

  private resolveManualNativeReason(
    input: ManualDownloadRequestInput,
    pageUrl: string
  ): 'hls' | 'custom_headers' | undefined {
    if (/\.m3u8?(?:[?#]|$)/i.test(input.url) || /\.m3u8?$/i.test(input.suggestedFileName ?? '') ||
      /mpegurl|m3u8/i.test(input.mimeType ?? '')) return 'hls';
    const headers = input.headers;
    if (headers === undefined) return undefined;
    const names = Object.keys(headers).filter((name: string): boolean =>
      name.trim().length > 0 && (headers[name]?.trim().length ?? 0) > 0);
    if (names.length === 0) return undefined;
    if (input.headersSource !== 'page') return 'custom_headers';
    const pageHeaders = ['cookie', 'user-agent', 'referer', 'origin', 'accept', 'accept-language',
      'accept-encoding', 'connection', 'host', 'content-length', 'sec-fetch-dest', 'sec-fetch-mode',
      'sec-fetch-site', 'sec-fetch-user', 'sec-ch-ua', 'sec-ch-ua-mobile', 'sec-ch-ua-platform',
      'upgrade-insecure-requests'];
    for (let index = 0; index < names.length; index++) {
      const name = names[index].trim().toLowerCase();
      if (pageHeaders.indexOf(name) < 0) return 'custom_headers';
      if (name === 'origin' && (this.resolveHttpOrigin(pageUrl).length === 0 ||
        this.resolveHttpOrigin(headers[names[index]]) !== this.resolveHttpOrigin(pageUrl))) {
        return 'custom_headers';
      }
    }
    return undefined;
  }

  private resolveHttpOrigin(value: string): string {
    const match = /^https?:\/\/[^/?#]+/i.exec(value.trim());
    return match === null ? '' : match[0].toLowerCase();
  }

  private toPendingDownloadPromptFromV2(prompt?: DownloadV2Prompt): PendingDownloadPromptState | undefined {
    if (prompt === undefined) {
      return undefined;
    }
    return this.withPromptLocation(prompt);
  }

  /**
   * Fills in the save-location fields for a prompt.
   *
   * The location is read from live settings on every call rather than baked
   * into the captured request, because the user can change the folder from the
   * prompt itself and a cached path would go stale immediately.
   */
  private withPromptLocation(prompt: DownloadV2Prompt): PendingDownloadPromptState {
    const location = this.resolvePendingPromptLocation(prompt);
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
      cancelLabel: prompt.cancelLabel,
      locationPath: location.path,
      canChangeLocation: location.canChange,
      isPlatformDownload: this.isPlatformDownloadPrompt(prompt.guid),
      isUserInitiatedDownload: this.isUserInitiatedDownloadPrompt(prompt.guid)
    };
  }

  /**
   * A private session saves through the system save dialog and deliberately
   * ignores the custom folder, so the prompt must say "choose each time"
   * instead of naming a location that will not be used. Changing the folder
   * from a private-session prompt is therefore not offered.
   */
  private resolvePendingPromptLocation(prompt: DownloadV2Prompt): PendingPromptLocationState {
    const boundary = this.resolvePromptBoundary(prompt);
    let savePolicy: DownloadSavePolicy;
    try {
      savePolicy = this.downloadPolicyService.resolveSavePolicy(boundary);
    } catch (_error) {
      return {
        path: resolveAppResourceText($r('app.string.settings_web_download_system_location')),
        canChange: false
      };
    }
    if (savePolicy.isPrivateSession) {
      return {
        path: resolveAppResourceText($r('app.string.download_choose_each_time')),
        canChange: false
      };
    }
    const customDirectory = resolveCustomDownloadDirectory(savePolicy.settings);
    if (customDirectory !== undefined) {
      return {
        path: customDirectory.label,
        canChange: true
      };
    }
    return {
      path: resolveAppResourceText($r('app.string.settings_web_download_system_location')),
      canChange: true
    };
  }

  /**
   * The captured request carries the boundary it was captured under, which is
   * what the location has to be resolved against. The active boundary can have
   * moved on (tab switch, window change) by the time the prompt is rendered.
   */
  private resolvePromptBoundary(prompt: DownloadV2Prompt): DownloadTaskBoundary {
    const request = this.downloadV2Service.getCapturedRequest(prompt.guid);
    if (request === undefined) {
      return this.activeBoundary;
    }
    return {
      windowId: request.boundary.windowId ?? '',
      profileId: request.boundary.profileId,
      privacyMode: request.boundary.privacyMode,
      dataScope: request.boundary.dataScope,
      sourcePageUrl: request.boundary.sourcePageUrl
    };
  }

  private initialize(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    this.downloadBridge.setCallbacks({
      onDownloadEvent: (event: PlatformDownloadEvent) => {
        const boundary = this.resolvePlatformEventBoundary(event);
        if (boundary === undefined) {
          if (event.type === 'before_download') {
            this.downloadBridge.cancelPendingDownload(event.snapshot.guid);
          }
          return;
        }
        if (event.type === 'before_download') {
          this.downloadGuidBoundaries.set(event.snapshot.guid, boundary);
          this.applyRecentWebDownloadStart(event);
        }
        this.callbacks.onPlatformDownloadEvent?.(event, boundary);
        this.callbackListeners.forEach((listener: DownloadRuntimeServiceCallbackListener) => {
          listener.callbacks.onPlatformDownloadEvent?.(event, boundary);
        });
        // Unknown and superseded progress events are normal during recovery. The service emits
        // actionable failures itself; an unhandled callback must not create a generic error toast.
        this.downloadV2Service.consumePlatformEvent(event, {
          windowId: boundary.windowId ?? '',
          profileId: boundary.profileId,
          privacyMode: boundary.privacyMode,
          dataScope: boundary.dataScope,
          sourcePageUrl: boundary.sourcePageUrl
        });
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

  private matchesSourceBoundary(source: DownloadTaskBoundary, expected: DownloadTaskBoundary): boolean {
    return matchesDownloadTaskBoundary({
      windowId: source.windowId,
      profileId: source.profileId,
      privacyMode: source.privacyMode,
      dataScope: source.dataScope
    }, {
      windowId: expected.windowId,
      profileId: expected.profileId,
      privacyMode: expected.privacyMode,
      dataScope: expected.dataScope
    });
  }

  private applyRecentWebDownloadStart(event: PlatformDownloadEvent): void {
    const normalizedUrl = this.normalizeDownloadMatchUrl(event.snapshot.url);
    const sourceId = event.snapshot.sourceId ?? '';
    if (normalizedUrl.length <= 0 || sourceId.length <= 0) {
      return;
    }
    const now = Date.now();
    const matchedContext: WebDownloadStartContext = {
      sourceId: '',
      url: '',
      userAgent: '',
      contentDisposition: '',
      mimeType: '',
      contentLength: 0,
      observedAt: 0
    };
    this.recentWebDownloadStarts = this.recentWebDownloadStarts.filter((context: WebDownloadStartContext) => {
      if (now - context.observedAt > WEB_DOWNLOAD_START_MATCH_WINDOW_MS) {
        return false;
      }
      if (context.url === normalizedUrl && context.sourceId === sourceId) {
        matchedContext.sourceId = context.sourceId;
        matchedContext.url = context.url;
        matchedContext.userAgent = context.userAgent;
        matchedContext.contentDisposition = context.contentDisposition;
        matchedContext.mimeType = context.mimeType;
        matchedContext.contentLength = context.contentLength;
        matchedContext.observedAt = context.observedAt;
        return false;
      }
      return true;
    });
    if (matchedContext.sourceId.length <= 0) {
      return;
    }
    const context = matchedContext;
    if ((event.snapshot.userAgent?.trim().length ?? 0) <= 0) {
      event.snapshot.userAgent = context.userAgent;
    }
    if ((event.snapshot.contentDisposition?.trim().length ?? 0) <= 0 && context.contentDisposition.length > 0) {
      event.snapshot.contentDisposition = context.contentDisposition;
    }
    if ((event.snapshot.mimeType?.trim().length ?? 0) <= 0 && context.mimeType.length > 0) {
      event.snapshot.mimeType = context.mimeType;
    }
    hilog.info(
      DOWNLOAD_RUNTIME_SERVICE_DOMAIN,
      DOWNLOAD_RUNTIME_SERVICE_TAG,
      'apply web download start guid=%{public}s pageUa=%{public}s disposition=%{public}s mime=%{public}s',
      event.snapshot.guid,
      'present',
      context.contentDisposition.length > 0 ? 'present' : 'missing',
      context.mimeType.length > 0 ? context.mimeType : 'missing'
    );
  }

  private normalizeDownloadMatchUrl(url: string): string {
    const trimmed = url.trim();
    const hashIndex = trimmed.indexOf('#');
    return hashIndex >= 0 ? trimmed.substring(0, hashIndex) : trimmed;
  }

  private resolvePlatformEventBoundary(event: PlatformDownloadEvent): DownloadTaskBoundary | undefined {
    const task = this.downloadV2Service.findTask(event.snapshot.guid);
    if (task !== undefined) {
      return this.normalizeBoundary({
        windowId: task.windowId,
        profileId: task.profileId,
        privacyMode: task.privacyMode,
        dataScope: task.dataScope,
        sourcePageUrl: task.request.sourcePageUrl
      });
    }
    const captured = this.downloadV2Service.getCapturedRequest(event.snapshot.guid);
    if (captured !== undefined) {
      return this.normalizeBoundary({
        windowId: captured.boundary.windowId,
        profileId: captured.boundary.profileId,
        privacyMode: captured.boundary.privacyMode,
        dataScope: captured.boundary.dataScope,
        sourcePageUrl: captured.boundary.sourcePageUrl
      });
    }
    const remembered = this.downloadGuidBoundaries.get(event.snapshot.guid);
    if (remembered !== undefined) {
      return remembered;
    }
    return this.downloadSourceBoundaries.get(event.snapshot.sourceId ?? '');
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
        this.emitError(resolveAppResourceText($r('app.string.download_private_cleanup_failed', task.suggestedFileName)));
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
      suggestedFileName: v2Task.resolvedFileName?.trim() || v2Task.suggestedFileName,
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

  private emitScopedFileActionResult(
    success: boolean, message?: string, onFailure?: (message: string) => void
  ): void {
    if (!success && onFailure !== undefined) {
      const normalized = message?.trim() ?? '';
      if (normalized.length > 0) onFailure(normalized);
      return;
    }
    this.emitFollowupResult(success, message);
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
      action === 'choose_location' ||
      action === 'rename' ||
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
    if (task.persistence.completionState === 'finalizing' || this.fileActionGuids.has(task.guid)) {
      return [];
    }
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
    if (task.status === 'failed' && !task.failure.retriable) {
      supportedActions = supportedActions.filter((action: DownloadV2ManagementAction) =>
        action !== 'resume' && action !== 'retry');
    }
    if (task.failure.retriable && (task.status === 'failed' || task.status === 'paused') &&
      (task.failure.code === 'permission' || task.persistence.completionState === 'export_failed')) {
      supportedActions.unshift('choose_location');
    }
    const availability = this.fileAvailabilityByGuid.get(task.guid);
    const location = task.persistence.finalFileUri?.trim() || task.persistence.tempFilePath?.trim() || '';
    if (availability?.location === location && availability.availability === 'missing') {
      supportedActions = supportedActions.filter((action: DownloadV2ManagementAction): boolean =>
        action !== 'share_file' && action !== 'rename');
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
