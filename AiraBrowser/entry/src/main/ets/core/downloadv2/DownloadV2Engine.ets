import {
  DownloadV2TaskEntity,
  MutableDownloadV2TaskEntityPatch,
  createDownloadV2TaskEntity
} from '../../domain/downloadv2/DownloadV2TaskEntity';
import {
  DownloadV2Event,
  transitionDownloadV2Status
} from '../../domain/downloadv2/DownloadV2StateMachine';
import {
  DownloadV2Failure,
  DownloadV2ProgressSnapshot,
  DownloadV2RequestContext,
  DownloadV2Status,
  DownloadV2TaskBoundary,
  buildDownloadV2EmptyFailure
} from '../../domain/downloadv2/DownloadV2Types';
import {
  DownloadV2Repository,
  InMemoryDownloadV2Repository
} from '../../data/downloadv2/DownloadV2Repository';

export interface CreateDownloadV2TaskCommand {
  guid: string;
  suggestedFileName: string;
  request: DownloadV2RequestContext;
  boundary: DownloadV2TaskBoundary;
  progress?: Partial<DownloadV2ProgressSnapshot>;
  requiresConfirmation: boolean;
}

export interface DownloadV2EngineObserver {
  onTaskChanged?: (task: DownloadV2TaskEntity) => void;
  onTaskRemoved?: (guid: string) => void;
}

interface DownloadV2TimingPatch {
  updatedAt?: number;
  confirmedAt?: number;
  startedAt?: number;
  completedAt?: number;
  failedAt?: number;
  canceledAt?: number;
  removedAt?: number;
}

export class DownloadV2Engine {
  private repository: DownloadV2Repository;
  private observer: DownloadV2EngineObserver = {};

  constructor(repository: DownloadV2Repository = new InMemoryDownloadV2Repository()) {
    this.repository = repository;
  }

  async initialize(): Promise<void> {
    await this.repository.initialize();
  }

  setObserver(observer: DownloadV2EngineObserver): void {
    this.observer = observer;
  }

  createTask(command: CreateDownloadV2TaskCommand): DownloadV2TaskEntity {
    const initialStatus: DownloadV2Status = command.requiresConfirmation ? 'awaiting_confirmation' : 'queued';
    const task = createDownloadV2TaskEntity({
      guid: command.guid,
      request: command.request,
      suggestedFileName: command.suggestedFileName,
      status: initialStatus,
      profileId: command.boundary.profileId,
      privacyMode: command.boundary.privacyMode,
      dataScope: command.boundary.dataScope,
      windowId: command.boundary.windowId,
      progress: command.progress,
      timing: {
        createdAt: Date.now(),
        updatedAt: Date.now()
      },
      failure: buildDownloadV2EmptyFailure()
    });
    return this.commitTask(task);
  }

  dispatch(guid: string, event: DownloadV2Event, patch?: MutableDownloadV2TaskEntityPatch): DownloadV2TaskEntity | undefined {
    const currentTask = this.repository.findOne({ guid: guid });
    if (currentTask === undefined) {
      return undefined;
    }
    const transition = transitionDownloadV2Status(currentTask.status, event);
    if (!transition.valid) {
      return currentTask;
    }
    const nextTimingPatch = this.buildTimingPatch(currentTask, transition.nextStatus, event, patch?.timing);
    const nextPatch: MutableDownloadV2TaskEntityPatch = {
      request: patch?.request,
      suggestedFileName: patch?.suggestedFileName,
      resolvedFileName: patch?.resolvedFileName,
      status: transition.nextStatus,
      progress: patch?.progress,
      persistence: patch?.persistence,
      runtime: patch?.runtime,
      failure: patch?.failure,
      timing: nextTimingPatch,
      windowId: patch?.windowId
    };
    const nextTask = this.repository.patch({ guid: guid }, nextPatch);
    if (nextTask !== undefined) {
      this.observer.onTaskChanged?.(nextTask);
    }
    return nextTask;
  }

  markFailure(guid: string, failure: DownloadV2Failure): DownloadV2TaskEntity | undefined {
    return this.dispatch(guid, 'fail', {
      failure: failure
    });
  }

  listTasks(boundary?: Partial<DownloadV2TaskBoundary>): DownloadV2TaskEntity[] {
    return this.repository.list(boundary);
  }

  findTask(guid: string): DownloadV2TaskEntity | undefined {
    return this.repository.findOne({ guid: guid });
  }

  synchronizeTask(guid: string, patch: MutableDownloadV2TaskEntityPatch): DownloadV2TaskEntity | undefined {
    const nextTask = this.repository.patch({ guid: guid }, patch);
    if (nextTask !== undefined) {
      this.observer.onTaskChanged?.(nextTask);
    }
    return nextTask;
  }

  removeTaskRecord(guid: string): boolean {
    const removed = this.repository.remove({ guid: guid });
    if (removed) {
      this.observer.onTaskRemoved?.(guid);
    }
    return removed;
  }

  private commitTask(task: DownloadV2TaskEntity): DownloadV2TaskEntity {
    const stored = this.repository.upsert(task);
    this.observer.onTaskChanged?.(stored);
    return stored;
  }

  private buildTimingPatch(
    currentTask: DownloadV2TaskEntity,
    nextStatus: DownloadV2Status,
    event: DownloadV2Event,
    patchTiming?: DownloadV2TimingPatch
  ): DownloadV2TimingPatch {
    const now = Date.now();
    return {
      updatedAt: now,
      confirmedAt: nextStatus === 'queued' && event === 'confirm'
        ? now
        : patchTiming?.confirmedAt,
      startedAt: nextStatus === 'running'
        ? (patchTiming?.startedAt ?? currentTask.timing.startedAt ?? now)
        : patchTiming?.startedAt,
      completedAt: nextStatus === 'completed'
        ? (patchTiming?.completedAt ?? now)
        : patchTiming?.completedAt,
      failedAt: nextStatus === 'failed'
        ? (patchTiming?.failedAt ?? now)
        : patchTiming?.failedAt,
      canceledAt: nextStatus === 'canceled'
        ? (patchTiming?.canceledAt ?? now)
        : patchTiming?.canceledAt,
      removedAt: nextStatus === 'removed'
        ? (patchTiming?.removedAt ?? now)
        : patchTiming?.removedAt
    };
  }
}
