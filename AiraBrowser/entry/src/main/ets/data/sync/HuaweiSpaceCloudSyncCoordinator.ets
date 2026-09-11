import { BusinessError } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';

const HUAWEI_SPACE_CLOUD_SYNC_LOG_DOMAIN: number = 0x0000;
const HUAWEI_SPACE_CLOUD_SYNC_LOG_TAG: string = 'HuaweiSpaceCloud';
const CLOUD_SYNC_UI_YIELD_MS: number = 16;

export interface HuaweiSpaceCloudSyncRequest {
  uid: string;
  databaseName: string;
  store: relationalStore.RdbStore;
  tableNames: string[];
  syncMode?: relationalStore.SyncMode;
  timeoutMs: number;
  requireFreshTask?: boolean;
  buildTimeoutError: () => Error;
  buildProgressError: (progressCode: number) => Error;
  buildCompletionError: (error: BusinessError) => Error;
  buildInvocationError: (error: Object) => Error;
}

interface HuaweiSpaceCloudSyncTask {
  request: HuaweiSpaceCloudSyncRequest;
  requestKey: string;
  promise: Promise<void>;
  resolve: () => void;
  reject: (reason: Error) => void;
  settled: boolean;
  released: boolean;
  callbackCompleted: boolean;
  finalProgressCode: number;
  tableDetails: string;
  timeoutId: number;
  timedOut: boolean;
  startedAt: number;
}

interface HuaweiSpaceCloudSyncQueueState {
  active?: HuaweiSpaceCloudSyncTask;
  pending: HuaweiSpaceCloudSyncTask[];
  latestByRequestKey: Map<string, HuaweiSpaceCloudSyncTask>;
  yieldTimerId: number;
}

export class HuaweiSpaceCloudSyncCoordinator {
  private static states: Map<string, HuaweiSpaceCloudSyncQueueState> =
    new Map<string, HuaweiSpaceCloudSyncQueueState>();

  static run(request: HuaweiSpaceCloudSyncRequest): Promise<void> {
    const transportKey = HuaweiSpaceCloudSyncCoordinator.buildTransportKey(request);
    const syncMode = HuaweiSpaceCloudSyncCoordinator.resolveSyncMode(request);
    const requestKey = HuaweiSpaceCloudSyncCoordinator.buildRequestKey(request.tableNames, syncMode);
    const state = HuaweiSpaceCloudSyncCoordinator.resolveState(transportKey);
    if (HuaweiSpaceCloudSyncCoordinator.isTransportQuarantined(state)) {
      hilog.warn(
        HUAWEI_SPACE_CLOUD_SYNC_LOG_DOMAIN,
        HUAWEI_SPACE_CLOUD_SYNC_LOG_TAG,
        'cloudSync rejected while transport awaits timed-out native task uid=%{public}s tables=%{public}s',
        HuaweiSpaceCloudSyncCoordinator.maskValue(request.uid),
        request.tableNames.join(',')
      );
      return Promise.reject(request.buildTimeoutError());
    }
    if (request.requireFreshTask !== true) {
      const existing = state.latestByRequestKey.get(requestKey);
      if (existing !== undefined) {
        return existing.promise;
      }
    }
    const task = HuaweiSpaceCloudSyncCoordinator.createTask(request, requestKey);
    state.pending.push(task);
    state.latestByRequestKey.set(requestKey, task);
    HuaweiSpaceCloudSyncCoordinator.startNext(transportKey, state);
    return task.promise;
  }

  private static createTask(
    request: HuaweiSpaceCloudSyncRequest,
    requestKey: string
  ): HuaweiSpaceCloudSyncTask {
    let resolveTask: () => void = (): void => undefined;
    let rejectTask: (reason: Error) => void = (_reason: Error): void => undefined;
    const promise = new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
      resolveTask = resolve;
      rejectTask = reject;
    });
    return {
      request,
      requestKey,
      promise,
      resolve: resolveTask,
      reject: rejectTask,
      settled: false,
      released: false,
      callbackCompleted: false,
      finalProgressCode: -1,
      tableDetails: '',
      timeoutId: -1,
      timedOut: false,
      startedAt: 0
    };
  }

  private static resolveState(transportKey: string): HuaweiSpaceCloudSyncQueueState {
    const existing = HuaweiSpaceCloudSyncCoordinator.states.get(transportKey);
    if (existing !== undefined) {
      return existing;
    }
    const created: HuaweiSpaceCloudSyncQueueState = {
      pending: [],
      latestByRequestKey: new Map<string, HuaweiSpaceCloudSyncTask>(),
      yieldTimerId: -1
    };
    HuaweiSpaceCloudSyncCoordinator.states.set(transportKey, created);
    return created;
  }

  private static startNext(transportKey: string, state: HuaweiSpaceCloudSyncQueueState): void {
    if (state.yieldTimerId >= 0 || state.active !== undefined || state.pending.length <= 0) {
      return;
    }
    const task = state.pending.shift();
    if (task === undefined) {
      return;
    }
    state.active = task;
    HuaweiSpaceCloudSyncCoordinator.startTask(transportKey, state, task);
  }

  private static startTask(
    transportKey: string,
    state: HuaweiSpaceCloudSyncQueueState,
    task: HuaweiSpaceCloudSyncTask
  ): void {
    const request = task.request;
    const syncMode = HuaweiSpaceCloudSyncCoordinator.resolveSyncMode(request);
    task.startedAt = Date.now();
    hilog.info(
      HUAWEI_SPACE_CLOUD_SYNC_LOG_DOMAIN,
      HUAWEI_SPACE_CLOUD_SYNC_LOG_TAG,
      'cloudSync start uid=%{public}s tables=%{public}s mode=%{public}d timeoutMs=%{public}d',
      HuaweiSpaceCloudSyncCoordinator.maskValue(request.uid),
      request.tableNames.join(','),
      syncMode,
      request.timeoutMs
    );
    task.timeoutId = setTimeout((): void => {
      HuaweiSpaceCloudSyncCoordinator.handleTimeout(transportKey, state, task);
    }, request.timeoutMs);
    const rejectAndRelease = (error: Error): void => {
      if (task.released) {
        return;
      }
      HuaweiSpaceCloudSyncCoordinator.logFinished(task, 'failed', task.finalProgressCode);
      hilog.error(
        HUAWEI_SPACE_CLOUD_SYNC_LOG_DOMAIN,
        HUAWEI_SPACE_CLOUD_SYNC_LOG_TAG,
        'cloudSync failed uid=%{public}s tables=%{public}s details=%{public}s message=%{public}s',
        HuaweiSpaceCloudSyncCoordinator.maskValue(request.uid),
        request.tableNames.join(','),
        task.tableDetails,
        error.message ?? JSON.stringify(error)
      );
      HuaweiSpaceCloudSyncCoordinator.rejectOnce(task, error);
      HuaweiSpaceCloudSyncCoordinator.releaseTask(transportKey, state, task);
    };
    const resolveWhenConfirmed = (): void => {
      if (task.released || !task.callbackCompleted || task.finalProgressCode < 0) {
        return;
      }
      if (task.finalProgressCode !== relationalStore.ProgressCode.SUCCESS) {
        rejectAndRelease(request.buildProgressError(task.finalProgressCode));
        return;
      }
      HuaweiSpaceCloudSyncCoordinator.logFinished(task, 'success', task.finalProgressCode);
      HuaweiSpaceCloudSyncCoordinator.resolveOnce(task);
      HuaweiSpaceCloudSyncCoordinator.releaseTask(transportKey, state, task);
    };
    try {
      request.store.cloudSync(
        syncMode,
        request.tableNames,
        (progressDetails: relationalStore.ProgressDetails): void => {
          if (task.released) {
            return;
          }
          if (progressDetails.schedule !== relationalStore.Progress.SYNC_FINISH) {
            return;
          }
          task.finalProgressCode = progressDetails.code;
          task.tableDetails = HuaweiSpaceCloudSyncCoordinator.formatTableDetails(progressDetails, request.tableNames);
          if (task.finalProgressCode !== relationalStore.ProgressCode.SUCCESS) {
            rejectAndRelease(request.buildProgressError(task.finalProgressCode));
            return;
          }
          resolveWhenConfirmed();
        },
        (error?: BusinessError): void => {
          if (task.released) {
            return;
          }
          if (error !== undefined) {
            rejectAndRelease(request.buildCompletionError(error));
            return;
          }
          task.callbackCompleted = true;
          resolveWhenConfirmed();
        }
      );
    } catch (error) {
      rejectAndRelease(request.buildInvocationError(error as Object));
    }
  }

  private static handleTimeout(
    transportKey: string,
    state: HuaweiSpaceCloudSyncQueueState,
    task: HuaweiSpaceCloudSyncTask
  ): void {
    if (task.released) {
      return;
    }
    HuaweiSpaceCloudSyncCoordinator.logFinished(task, 'timeout', task.finalProgressCode);
    hilog.warn(
      HUAWEI_SPACE_CLOUD_SYNC_LOG_DOMAIN,
      HUAWEI_SPACE_CLOUD_SYNC_LOG_TAG,
      'cloudSync timeout; quarantining transport uid=%{public}s tables=%{public}s',
      HuaweiSpaceCloudSyncCoordinator.maskValue(task.request.uid),
      task.request.tableNames.join(',')
    );
    task.timedOut = true;
    task.timeoutId = -1;
    HuaweiSpaceCloudSyncCoordinator.rejectOnce(task, task.request.buildTimeoutError());
    HuaweiSpaceCloudSyncCoordinator.rejectPendingForQuarantine(state);
  }

  private static rejectPendingForQuarantine(state: HuaweiSpaceCloudSyncQueueState): void {
    const pending = state.pending.splice(0, state.pending.length);
    pending.forEach((task: HuaweiSpaceCloudSyncTask): void => {
      task.released = true;
      HuaweiSpaceCloudSyncCoordinator.rejectOnce(task, task.request.buildTimeoutError());
      if (state.latestByRequestKey.get(task.requestKey) === task) {
        state.latestByRequestKey.delete(task.requestKey);
      }
    });
  }

  private static isTransportQuarantined(state: HuaweiSpaceCloudSyncQueueState): boolean {
    return state.active !== undefined && state.active.timedOut && !state.active.released;
  }

  private static resolveOnce(task: HuaweiSpaceCloudSyncTask): void {
    if (task.settled) {
      return;
    }
    task.settled = true;
    task.resolve();
  }

  private static rejectOnce(task: HuaweiSpaceCloudSyncTask, error: Error): void {
    if (task.settled) {
      return;
    }
    task.settled = true;
    task.reject(error);
  }

  private static releaseTask(
    transportKey: string,
    state: HuaweiSpaceCloudSyncQueueState,
    task: HuaweiSpaceCloudSyncTask
  ): void {
    if (task.released) {
      return;
    }
    task.released = true;
    if (task.timeoutId >= 0) {
      clearTimeout(task.timeoutId);
      task.timeoutId = -1;
    }
    if (state.active === task) {
      state.active = undefined;
    }
    if (state.latestByRequestKey.get(task.requestKey) === task) {
      state.latestByRequestKey.delete(task.requestKey);
    }
    if (state.pending.length > 0) {
      if (state.yieldTimerId >= 0) {
        clearTimeout(state.yieldTimerId);
      }
      state.yieldTimerId = setTimeout((): void => {
        state.yieldTimerId = -1;
        HuaweiSpaceCloudSyncCoordinator.startNext(transportKey, state);
      }, CLOUD_SYNC_UI_YIELD_MS);
      return;
    }
    if (state.active === undefined && state.latestByRequestKey.size <= 0) {
      HuaweiSpaceCloudSyncCoordinator.states.delete(transportKey);
    }
  }

  private static buildTransportKey(request: HuaweiSpaceCloudSyncRequest): string {
    return `${request.databaseName.trim()}|${request.uid.trim()}`;
  }

  private static buildRequestKey(tableNames: string[], syncMode: relationalStore.SyncMode): string {
    const tableKey = tableNames.slice().sort((left: string, right: string): number => {
      return left.localeCompare(right);
    }).join('|');
    return `${syncMode}|${tableKey}`;
  }

  private static resolveSyncMode(request: HuaweiSpaceCloudSyncRequest): relationalStore.SyncMode {
    return request.syncMode ?? relationalStore.SyncMode.SYNC_MODE_TIME_FIRST;
  }

  private static logFinished(task: HuaweiSpaceCloudSyncTask, outcome: string, progressCode: number): void {
    const durationMs = task.startedAt > 0 ? Date.now() - task.startedAt : -1;
    const syncMode = HuaweiSpaceCloudSyncCoordinator.resolveSyncMode(task.request);
    hilog.info(
      HUAWEI_SPACE_CLOUD_SYNC_LOG_DOMAIN,
      HUAWEI_SPACE_CLOUD_SYNC_LOG_TAG,
      'cloudSync %{public}s uid=%{public}s tables=%{public}s mode=%{public}d durationMs=%{public}d code=%{public}d details=%{public}s',
      outcome,
      HuaweiSpaceCloudSyncCoordinator.maskValue(task.request.uid),
      task.request.tableNames.join(','),
      syncMode,
      durationMs,
      progressCode,
      task.tableDetails
    );
    AiraSyncJankProbe.endExtra(
      'cloud_sync',
      task.startedAt > 0 ? task.startedAt : Date.now(),
      `outcome=${outcome} tables=${task.request.tableNames.join(',')} code=${progressCode}`
    );
  }

  private static formatTableDetails(
    progressDetails: relationalStore.ProgressDetails,
    tableNames: string[]
  ): string {
    const details = progressDetails.details;
    if (details === undefined) {
      return 'none';
    }
    const parts: string[] = [];
    for (let index = 0; index < tableNames.length; index++) {
      const tableName = tableNames[index];
      const table = details[tableName];
      if (table === undefined) {
        continue;
      }
      parts.push(
        `${tableName} up=${table.upload.total}/${table.upload.successful}/${table.upload.failed}/${table.upload.remained}` +
          ` down=${table.download.total}/${table.download.successful}/${table.download.failed}/${table.download.remained}`
      );
    }
    return parts.length > 0 ? parts.join(';') : 'none';
  }

  private static maskValue(value: string): string {
    const normalized = value.trim();
    if (normalized.length <= 8) {
      return `len${normalized.length}`;
    }
    return `${normalized.slice(0, 4)}...${normalized.slice(normalized.length - 4)}(len${normalized.length})`;
  }
}
