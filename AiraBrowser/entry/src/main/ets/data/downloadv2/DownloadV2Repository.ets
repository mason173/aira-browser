import {
  ArkDownloadV2RecordStore,
  DownloadV2RecordStore
} from './DownloadV2RecordStore';
import {
  DownloadV2TaskEntity,
  MutableDownloadV2TaskEntityPatch,
  patchDownloadV2TaskEntity
} from '../../domain/downloadv2/DownloadV2TaskEntity';
import {
  DownloadV2Status,
  DownloadV2TaskBoundary
} from '../../domain/downloadv2/DownloadV2Types';
import { cloneDownloadV2SegmentPlanSnapshot } from '../../domain/downloadv2/DownloadV2SegmentTypes';
import {
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { matchesDownloadTaskBoundary } from '../../domain/download/DownloadTypes';
import {
  bucketRuntimeDiagnosticDuration,
  DownloadRuntimeDiagnosticEvent,
  DownloadRuntimeDiagnosticRecorder
} from '../../common/models/RuntimeDiagnosticModels';

export interface DownloadV2TaskLookup {
  id?: string;
  guid?: string;
}

export interface DownloadV2TaskListQuery extends DownloadV2TaskBoundary {
  status?: DownloadV2Status | 'all';
}

export interface DownloadV2Repository {
  initialize(): Promise<void>;
  list(query?: Partial<DownloadV2TaskListQuery>): DownloadV2TaskEntity[];
  findOne(lookup: DownloadV2TaskLookup): DownloadV2TaskEntity | undefined;
  exists(lookup: DownloadV2TaskLookup): boolean;
  upsert(task: DownloadV2TaskEntity): DownloadV2TaskEntity;
  patch(lookup: DownloadV2TaskLookup, patch: MutableDownloadV2TaskEntityPatch): DownloadV2TaskEntity | undefined;
  remove(lookup: DownloadV2TaskLookup): boolean;
  clear(query?: Partial<DownloadV2TaskListQuery>): number;
  flushPersistence(): Promise<void>;
}

export class InMemoryDownloadV2Repository implements DownloadV2Repository {
  private tasks: DownloadV2TaskEntity[] = [];

  async initialize(): Promise<void> {
    return Promise.resolve();
  }

  list(query?: Partial<DownloadV2TaskListQuery>): DownloadV2TaskEntity[] {
    return this.tasks
      .filter((task: DownloadV2TaskEntity) => this.matchesQuery(task, query))
      .map((task: DownloadV2TaskEntity) => this.cloneTask(task));
  }

  findOne(lookup: DownloadV2TaskLookup): DownloadV2TaskEntity | undefined {
    const task = this.findStoredTask(lookup);
    return task === undefined ? undefined : this.cloneTask(task);
  }

  exists(lookup: DownloadV2TaskLookup): boolean {
    return this.findStoredTask(lookup) !== undefined;
  }

  upsert(task: DownloadV2TaskEntity): DownloadV2TaskEntity {
    const nextTask = this.cloneTask(task);
    const index = this.findStoredTaskIndex({ id: task.id, guid: task.guid });
    if (index >= 0) {
      this.tasks[index] = nextTask;
    } else {
      this.tasks.push(nextTask);
    }
    return this.cloneTask(nextTask);
  }

  patch(lookup: DownloadV2TaskLookup, patch: MutableDownloadV2TaskEntityPatch): DownloadV2TaskEntity | undefined {
    const index = this.findStoredTaskIndex(lookup);
    if (index < 0) {
      return undefined;
    }
    const nextTask = patchDownloadV2TaskEntity(this.tasks[index], patch);
    this.tasks[index] = nextTask;
    return this.cloneTask(nextTask);
  }

  remove(lookup: DownloadV2TaskLookup): boolean {
    const index = this.findStoredTaskIndex(lookup);
    if (index < 0) {
      return false;
    }
    this.tasks.splice(index, 1);
    return true;
  }

  clear(query?: Partial<DownloadV2TaskListQuery>): number {
    if (query === undefined) {
      const count = this.tasks.length;
      this.tasks = [];
      return count;
    }
    const remaining: DownloadV2TaskEntity[] = [];
    let removedCount = 0;
    this.tasks.forEach((task: DownloadV2TaskEntity) => {
      if (this.matchesQuery(task, query)) {
        removedCount += 1;
        return;
      }
      remaining.push(task);
    });
    this.tasks = remaining;
    return removedCount;
  }

  flushPersistence(): Promise<void> {
    return Promise.resolve();
  }

  private matchesQuery(task: DownloadV2TaskEntity, query?: Partial<DownloadV2TaskListQuery>): boolean {
    if (query === undefined) {
      return true;
    }
    if (!matchesDownloadTaskBoundary(
      {
        windowId: task.windowId,
        profileId: task.profileId,
        privacyMode: task.privacyMode,
        dataScope: task.dataScope
      },
      {
        windowId: query.windowId,
        profileId: query.profileId,
        privacyMode: query.privacyMode,
        dataScope: query.dataScope
      }
    )) {
      return false;
    }
    if (query.status !== undefined && query.status !== 'all' && task.status !== query.status) {
      return false;
    }
    return true;
  }

  private findStoredTask(lookup: DownloadV2TaskLookup): DownloadV2TaskEntity | undefined {
    const index = this.findStoredTaskIndex(lookup);
    return index < 0 ? undefined : this.tasks[index];
  }

  private findStoredTaskIndex(lookup: DownloadV2TaskLookup): number {
    const id = lookup.id?.trim() ?? '';
    if (id.length > 0) {
      return this.tasks.findIndex((task: DownloadV2TaskEntity) => task.id === id);
    }
    const guid = lookup.guid?.trim() ?? '';
    if (guid.length > 0) {
      return this.tasks.findIndex((task: DownloadV2TaskEntity) => task.guid === guid);
    }
    return -1;
  }

  private cloneTask(task: DownloadV2TaskEntity): DownloadV2TaskEntity {
    const nextHeaders: Record<string, string> | undefined = this.cloneHeaders(task.request.headers);
    return {
      request: {
        url: task.request.url,
        method: task.request.method,
        sourcePageUrl: task.request.sourcePageUrl,
        sourceHost: task.request.sourceHost,
        userAgent: task.request.userAgent,
        referer: task.request.referer,
        mimeType: task.request.mimeType,
        contentDisposition: task.request.contentDisposition,
        headers: nextHeaders
      },
      progress: {
        totalBytes: task.progress.totalBytes,
        receivedBytes: task.progress.receivedBytes,
        speedBytesPerSecond: task.progress.speedBytesPerSecond
      },
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
        restartReason: task.persistence.restartReason,
        segmentPlan: cloneDownloadV2SegmentPlanSnapshot(task.persistence.segmentPlan)
      },
      runtime: {
        platformTaskId: task.runtime.platformTaskId,
        platformTaskToken: task.runtime.platformTaskToken,
        resumeCapability: task.runtime.resumeCapability
      },
      failure: {
        code: task.failure.code,
        sourceCode: task.failure.sourceCode,
        message: task.failure.message,
        retriable: task.failure.retriable
      },
      timing: {
        createdAt: task.timing.createdAt,
        updatedAt: task.timing.updatedAt,
        confirmedAt: task.timing.confirmedAt,
        startedAt: task.timing.startedAt,
        completedAt: task.timing.completedAt,
        failedAt: task.timing.failedAt,
        canceledAt: task.timing.canceledAt,
        removedAt: task.timing.removedAt
      },
      id: task.id,
      guid: task.guid,
      windowId: task.windowId,
      profileId: task.profileId,
      privacyMode: task.privacyMode,
      dataScope: task.dataScope,
      suggestedFileName: task.suggestedFileName,
      resolvedFileName: task.resolvedFileName,
      status: task.status
    };
  }

  private cloneHeaders(headers?: Record<string, string>): Record<string, string> | undefined {
    if (headers === undefined) {
      return undefined;
    }
    const nextHeaders: Record<string, string> = {};
    Object.keys(headers).forEach((key: string) => {
      nextHeaders[key] = headers[key];
    });
    return nextHeaders;
  }
}

export class PersistentDownloadV2Repository implements DownloadV2Repository {
  private memoryRepository: InMemoryDownloadV2Repository = new InMemoryDownloadV2Repository();
  private recordStore: DownloadV2RecordStore;
  private initializationPromise?: Promise<void>;
  private persistPromise: Promise<void> = Promise.resolve();
  private diagnosticRecorder?: DownloadRuntimeDiagnosticRecorder;

  constructor(
    recordStore: DownloadV2RecordStore = new ArkDownloadV2RecordStore(),
    diagnosticRecorder?: DownloadRuntimeDiagnosticRecorder
  ) {
    this.recordStore = recordStore;
    this.diagnosticRecorder = diagnosticRecorder;
  }

  async initialize(): Promise<void> {
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.recordStore.loadRecords()
        .then(async (records: DownloadV2TaskEntity[]): Promise<void> => {
          const hydrateStartEvent: DownloadRuntimeDiagnosticEvent = {
            owner: 'repository',
            operation: 'hydrate',
            state: `records=${records.length}`,
            result: 'begin'
          };
          await this.diagnosticRecorder?.recordDownloadRuntimeDiagnosticAndWait(hydrateStartEvent);
          const startedAt = Date.now();
          records.forEach((record: DownloadV2TaskEntity) => {
            this.memoryRepository.upsert(record);
          });
          const hydrateResultEvent: DownloadRuntimeDiagnosticEvent = {
            owner: 'repository',
            operation: 'hydrate',
            state: `records=${records.length} elapsed=${bucketRuntimeDiagnosticDuration(Date.now() - startedAt)}`,
            result: 'ok'
          };
          this.diagnosticRecorder?.recordDownloadRuntimeDiagnostic(hydrateResultEvent);
        })
        .catch(() => {
          this.initializationPromise = undefined;
          throw new Error('DownloadV2 repository initialization failed.');
        });
    }
    return this.initializationPromise;
  }

  list(query?: Partial<DownloadV2TaskListQuery>): DownloadV2TaskEntity[] {
    return this.memoryRepository.list(query);
  }

  findOne(lookup: DownloadV2TaskLookup): DownloadV2TaskEntity | undefined {
    return this.memoryRepository.findOne(lookup);
  }

  exists(lookup: DownloadV2TaskLookup): boolean {
    return this.memoryRepository.exists(lookup);
  }

  upsert(task: DownloadV2TaskEntity): DownloadV2TaskEntity {
    const result = this.memoryRepository.upsert(task);
    this.schedulePersist();
    return result;
  }

  patch(lookup: DownloadV2TaskLookup, patch: MutableDownloadV2TaskEntityPatch): DownloadV2TaskEntity | undefined {
    const result = this.memoryRepository.patch(lookup, patch);
    if (result !== undefined) {
      this.schedulePersist();
    }
    return result;
  }

  remove(lookup: DownloadV2TaskLookup): boolean {
    const removed = this.memoryRepository.remove(lookup);
    if (removed) {
      this.schedulePersist();
    }
    return removed;
  }

  clear(query?: Partial<DownloadV2TaskListQuery>): number {
    const removedCount = this.memoryRepository.clear(query);
    if (removedCount > 0) {
      this.schedulePersist();
    }
    return removedCount;
  }

  flushPersistence(): Promise<void> {
    return this.persistPromise;
  }

  private schedulePersist(): void {
    const persistentRecords = this.memoryRepository.list().filter((task: DownloadV2TaskEntity) => {
      return shouldPersistDownloadV2Task(task);
    });
    this.persistPromise = this.persistPromise
      .catch(() => Promise.resolve())
      .then(() => this.recordStore.saveRecords(persistentRecords));
  }
}

export function buildPersistentDownloadV2Repository(
  diagnosticRecorder?: DownloadRuntimeDiagnosticRecorder,
  recordStore?: DownloadV2RecordStore
): PersistentDownloadV2Repository {
  const resolvedRecordStore = recordStore ?? new ArkDownloadV2RecordStore(diagnosticRecorder);
  return new PersistentDownloadV2Repository(resolvedRecordStore, diagnosticRecorder);
}

function shouldPersistDownloadV2Task(task: DownloadV2TaskEntity): boolean {
  const privacyMode = normalizeBrowserSessionPrivacyMode(task.privacyMode);
  const dataScope = normalizeBrowserDataScope(task.dataScope, privacyMode);
  return privacyMode !== 'private' &&
    dataScope !== 'session_ephemeral' &&
    task.status !== 'removed' &&
    task.status !== 'awaiting_confirmation' &&
    task.status !== 'canceled';
}
