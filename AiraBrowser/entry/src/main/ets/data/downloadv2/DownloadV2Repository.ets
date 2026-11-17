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
import { hilog } from '@kit.PerformanceAnalysisKit';
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
    // Keep copying in the entity owner so new recovery fields survive every repository boundary.
    return patchDownloadV2TaskEntity(task, { timing: { updatedAt: task.timing.updatedAt } });
  }

}

export interface DownloadV2PersistenceConfig {
  progressIntervalMs?: number;
}

const DOWNLOAD_PROGRESS_PERSIST_INTERVAL_MS = 500;
const DOWNLOAD_REPOSITORY_DOMAIN = 0x0000;
const DOWNLOAD_REPOSITORY_TAG = 'DownloadV2Repository';

export class PersistentDownloadV2Repository implements DownloadV2Repository {
  private memoryRepository: InMemoryDownloadV2Repository = new InMemoryDownloadV2Repository();
  private recordStore: DownloadV2RecordStore;
  private initializationPromise?: Promise<void>;
  private persistPromise?: Promise<void>;
  private progressTimer?: number;
  private progressIntervalMs: number;
  private pendingRevision: number = 0;
  private persistedRevision: number = 0;
  private lastPersistError?: Error;
  private diagnosticRecorder?: DownloadRuntimeDiagnosticRecorder;

  constructor(
    recordStore: DownloadV2RecordStore = new ArkDownloadV2RecordStore(),
    diagnosticRecorder?: DownloadRuntimeDiagnosticRecorder,
    persistenceConfig?: DownloadV2PersistenceConfig
  ) {
    this.recordStore = recordStore;
    this.diagnosticRecorder = diagnosticRecorder;
    const requestedInterval = persistenceConfig?.progressIntervalMs;
    this.progressIntervalMs = requestedInterval !== undefined && Number.isFinite(requestedInterval)
      ? Math.max(0, Math.floor(requestedInterval)) : DOWNLOAD_PROGRESS_PERSIST_INTERVAL_MS;
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
    const previous = this.memoryRepository.findOne({ id: task.id, guid: task.guid });
    const result = this.memoryRepository.upsert(task);
    this.persistMutation(previous, result);
    return result;
  }

  patch(lookup: DownloadV2TaskLookup, patch: MutableDownloadV2TaskEntityPatch): DownloadV2TaskEntity | undefined {
    const previous = this.memoryRepository.findOne(lookup);
    const result = this.memoryRepository.patch(lookup, patch);
    if (result !== undefined) {
      this.persistMutation(previous, result);
    }
    return result;
  }

  remove(lookup: DownloadV2TaskLookup): boolean {
    const previous = this.memoryRepository.findOne(lookup);
    const removed = this.memoryRepository.remove(lookup);
    if (removed && previous !== undefined && shouldPersistDownloadV2Task(previous)) {
      this.schedulePersist(true);
    }
    return removed;
  }

  clear(query?: Partial<DownloadV2TaskListQuery>): number {
    const affectsPersistedRecords = this.memoryRepository.list(query).some((task: DownloadV2TaskEntity) =>
      shouldPersistDownloadV2Task(task));
    const removedCount = this.memoryRepository.clear(query);
    if (removedCount > 0 && affectsPersistedRecords) {
      this.schedulePersist(true);
    }
    return removedCount;
  }

  async flushPersistence(): Promise<void> {
    this.clearProgressTimer();
    // A timer-driven failure has no awaiting caller. Report it to the next explicit barrier;
    // leave the dirty revision intact so a subsequent barrier or mutation can retry it.
    if (this.persistPromise === undefined && this.lastPersistError !== undefined) {
      const error = this.lastPersistError;
      this.lastPersistError = undefined;
      throw error;
    }
    do {
      try {
        await this.startPersistDrain();
      } catch (error) {
        this.lastPersistError = undefined;
        const persistenceError = error as Error;
        throw new Error(persistenceError.message ?? 'Download records save failed.');
      }
      this.clearProgressTimer();
    } while (this.persistedRevision !== this.pendingRevision);
  }

  private persistMutation(previous: DownloadV2TaskEntity | undefined, next: DownloadV2TaskEntity): void {
    const wasPersisted = previous !== undefined && shouldPersistDownloadV2Task(previous);
    const willPersist = shouldPersistDownloadV2Task(next);
    if (!wasPersisted && !willPersist) {
      return;
    }
    this.schedulePersist(previous === undefined || wasPersisted !== willPersist ||
      !this.isProgressOnlyChange(previous, next));
  }

  private schedulePersist(immediate: boolean): void {
    this.pendingRevision += 1;
    if (immediate || this.progressIntervalMs === 0) {
      this.clearProgressTimer();
      this.persistInBackground();
      return;
    }
    if (this.persistPromise !== undefined || this.progressTimer !== undefined) {
      return;
    }
    this.progressTimer = setTimeout(() => {
      this.progressTimer = undefined;
      this.persistInBackground();
    }, this.progressIntervalMs);
  }

  private clearProgressTimer(): void {
    if (this.progressTimer !== undefined) {
      clearTimeout(this.progressTimer);
      this.progressTimer = undefined;
    }
  }

  private persistInBackground(): void {
    // Observe rejection without changing the promise returned by flushPersistence(). No failed
    // revision is marked saved, and no unbounded retry loop runs against a failing storage device.
    void this.startPersistDrain().catch((_error: Error): void => {
      hilog.error(DOWNLOAD_REPOSITORY_DOMAIN, DOWNLOAD_REPOSITORY_TAG,
        'download records save failed; latest state remains pending');
      this.diagnosticRecorder?.recordDownloadRuntimeDiagnostic({
        owner: 'repository', operation: 'persist', state: 'latest_pending', result: 'failed'
      });
    });
  }

  private startPersistDrain(): Promise<void> {
    if (this.persistPromise !== undefined) {
      return this.persistPromise;
    }
    if (this.persistedRevision === this.pendingRevision) {
      return Promise.resolve();
    }
    // Install the promise before entering the store, which may synchronously trigger callbacks.
    this.persistPromise = Promise.resolve().then(() => this.drainLatestRecords())
      .catch((error: Error): void => {
        this.lastPersistError = error;
        throw error;
      })
      .finally((): void => {
        this.persistPromise = undefined;
        // A mutation can arrive in the microtask between the drain settling and this cleanup.
        if (this.pendingRevision !== this.persistedRevision && this.lastPersistError === undefined) {
          this.persistInBackground();
        }
      });
    return this.persistPromise;
  }

  private async drainLatestRecords(): Promise<void> {
    while (this.persistedRevision !== this.pendingRevision) {
      const savingRevision = this.pendingRevision;
      // Clone once per actual write, not once per progress event. A slow write retains only one
      // latest pending revision and drains changes that arrive while it is in flight.
      const records = this.memoryRepository.list().filter((task: DownloadV2TaskEntity) =>
        shouldPersistDownloadV2Task(task));
      await this.recordStore.saveRecords(records);
      this.persistedRevision = savingRevision;
      this.lastPersistError = undefined;
    }
  }

  private isProgressOnlyChange(previous: DownloadV2TaskEntity, next: DownloadV2TaskEntity): boolean {
    const before = previous.persistence;
    const after = next.persistence;
    return previous.status === next.status && previous.windowId === next.windowId &&
      previous.suggestedFileName === next.suggestedFileName && previous.resolvedFileName === next.resolvedFileName &&
      JSON.stringify(previous.request) === JSON.stringify(next.request) &&
      JSON.stringify(previous.failure) === JSON.stringify(next.failure) &&
      before.completionState === after.completionState &&
      JSON.stringify(before.destination) === JSON.stringify(after.destination) &&
      before.tempFilePath === after.tempFilePath && before.finalFileUri === after.finalFileUri &&
      before.finalDisplayPath === after.finalDisplayPath && before.partialFilePath === after.partialFilePath &&
      before.finalFilePath === after.finalFilePath && before.expectedTotalBytes === after.expectedTotalBytes &&
      before.etag === after.etag && before.lastModified === after.lastModified &&
      before.acceptRanges === after.acceptRanges && before.contentRange === after.contentRange &&
      before.downloadDriver === after.downloadDriver && before.resumeMode === after.resumeMode &&
      before.needsFullRestart === after.needsFullRestart && before.restartReason === after.restartReason &&
      before.segmentPlan?.guid === after.segmentPlan?.guid &&
      before.segmentPlan?.segmentCount === after.segmentPlan?.segmentCount &&
      before.segmentPlan?.partFileBasePath === after.segmentPlan?.partFileBasePath &&
      previous.runtime.platformTaskId === next.runtime.platformTaskId &&
      previous.runtime.resumeCapability === next.runtime.resumeCapability &&
      previous.runtime.pauseReason === next.runtime.pauseReason &&
      ((previous.runtime.platformTaskToken?.length ?? 0) > 0) === ((next.runtime.platformTaskToken?.length ?? 0) > 0) &&
      previous.timing.confirmedAt === next.timing.confirmedAt && previous.timing.startedAt === next.timing.startedAt &&
      previous.timing.completedAt === next.timing.completedAt && previous.timing.failedAt === next.timing.failedAt &&
      previous.timing.canceledAt === next.timing.canceledAt && previous.timing.removedAt === next.timing.removedAt;
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
