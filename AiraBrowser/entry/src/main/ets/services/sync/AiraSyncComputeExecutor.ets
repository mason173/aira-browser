import { taskpool } from '@kit.ArkTS';
import {
  HuaweiSpaceHistorySyncState
} from '../../common/models/HistorySyncModels';
import {
  HuaweiSpaceHistoryPhysicalMirror,
  HuaweiSpaceHistoryRow,
  HuaweiSpaceHistorySnapshotCodec
} from '../../data/sync/HuaweiSpaceHistorySnapshotCodec';
import { HistorySyncMergeService } from './HistorySyncMergeService';
import {
  AiraHistoryRemoteWriteProjection,
  AiraHistoryTaskpoolTransferCodec
} from './AiraHistoryTaskpoolTransferCodec';
import { AiraSyncWorkThrottleService } from './AiraSyncWorkThrottleService';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';

const AIRA_SYNC_TASKPOOL_TRANSFER_BUDGET_BYTES: number = 8 * 1024 * 1024;
const AIRA_SYNC_TASKPOOL_PACK_PREFLIGHT_BUDGET_BYTES: number = 16 * 1024 * 1024;

export interface AiraHistoryInitialMergePlan {
  merged: HuaweiSpaceHistorySyncState;
  localApplyRequired: boolean;
  remoteWriteRequired: boolean;
}

export interface AiraHistoryRemoteStateDecode {
  state: HuaweiSpaceHistorySyncState;
  legacyRowIds: string[];
}

export interface AiraHistoryRemoteWritePlan {
  projection: AiraHistoryRemoteWriteProjection;
}

export interface AiraHistoryRemoteWriteConfirmation {
  confirmed: HuaweiSpaceHistorySyncState;
  projectionConfirmed: boolean;
  desiredStateConfirmed: boolean;
  localApplyRequired: boolean;
}

interface AiraHistoryRemoteStateDecodeOutcome {
  decoded?: AiraHistoryRemoteStateDecode;
  errorMessage: string;
}

interface AiraHistoryRemoteWritePlanOutcome {
  plan?: AiraHistoryRemoteWritePlan;
  decodeErrorMessage: string;
  computeErrorMessage: string;
}

interface AiraHistoryRemoteWriteConfirmationOutcome {
  confirmation?: AiraHistoryRemoteWriteConfirmation;
  decodeErrorMessage: string;
  computeErrorMessage: string;
}

export class AiraHistoryMirrorDecodeError extends Error {
}

@Concurrent
function decodeHuaweiHistoryRemoteState(
  uid: string,
  deviceId: string,
  rowBuffer: ArrayBuffer,
  now: number
): AiraHistoryRemoteStateDecodeOutcome {
  try {
    const rows = AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer);
    const mirror = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId).decodeRows(rows, now);
    return {
      decoded: {
        state: mirror.state,
        legacyRowIds: mirror.legacyRowIds
      },
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}


export interface HuaweiHistoryReplicaPackedOutcome {
  localApplyRequired: boolean;
  remoteWriteRequired: boolean;
  mergedBuffer: ArrayBuffer;
  projection: AiraHistoryRemoteWriteProjection;
  errorMessage: string;
}


interface AiraHistoryInitialMergePackedOutcome {
  localApplyRequired: boolean;
  remoteWriteRequired: boolean;
  mergedBuffer: ArrayBuffer;
  errorMessage: string;
}

@Concurrent
function planHuaweiHistoryInitialMergePacked(
  remoteBuffer: ArrayBuffer,
  localBuffer: ArrayBuffer,
  now: number
): AiraHistoryInitialMergePackedOutcome {
  try {
    const remote = AiraHistoryTaskpoolTransferCodec.decodeState(remoteBuffer);
    const local = AiraHistoryTaskpoolTransferCodec.decodeState(localBuffer);
    const mergeService = new HistorySyncMergeService();
    const merged = mergeService.mergeKeepingPreferredVisits(remote, local, now);
    const localApplyRequired = !mergeService.sameState(merged, local);
    const remoteWriteRequired = !mergeService.sameState(merged, remote);
    if (!localApplyRequired && !remoteWriteRequired) {
      return {
        localApplyRequired: false,
        remoteWriteRequired: false,
        mergedBuffer: new ArrayBuffer(0),
        errorMessage: ''
      };
    }
    return {
      localApplyRequired: localApplyRequired,
      remoteWriteRequired: remoteWriteRequired,
      mergedBuffer: AiraHistoryTaskpoolTransferCodec.encodeState(merged),
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      localApplyRequired: false,
      remoteWriteRequired: false,
      mergedBuffer: new ArrayBuffer(0),
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}


@Concurrent
function planHuaweiHistoryReplicaPacked(
  uid: string,
  deviceId: string,
  rowBuffer: ArrayBuffer,
  localBuffer: ArrayBuffer,
  now: number
): HuaweiHistoryReplicaPackedOutcome {
  try {
    const current = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .decodeRows(AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer), now);
    const local = AiraHistoryTaskpoolTransferCodec.decodeState(localBuffer);
    const mergeService = new HistorySyncMergeService();
    const merged = mergeService.mergeKeepingPreferredVisits(current.state, local, now);
    const localApplyRequired = !mergeService.sameState(merged, local);
    const remoteWriteRequired = !mergeService.sameState(merged, current.state);
    if (!localApplyRequired && !remoteWriteRequired) {
      return {
        localApplyRequired: false,
        remoteWriteRequired: false,
        mergedBuffer: new ArrayBuffer(0),
        projection: {
          rowsToUpsert: [],
          rowIdsToDeleteBeforePublish: [],
          legacyRowIdsToDeleteAfterConfirmation: [],
          targetHeadRowId: '',
          targetDeviceId: '',
          targetGeneration: 0,
          targetStateChecksum: ''
        },
        errorMessage: ''
      };
    }
    const projection = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .buildProjection(merged, current, now);
    return {
      localApplyRequired: localApplyRequired,
      remoteWriteRequired: remoteWriteRequired,
      mergedBuffer: AiraHistoryTaskpoolTransferCodec.encodeState(merged),
      projection: AiraHistoryTaskpoolTransferCodec.leanProjection(projection),
      errorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      localApplyRequired: false,
      remoteWriteRequired: false,
      mergedBuffer: new ArrayBuffer(0),
      projection: {
        rowsToUpsert: [],
        rowIdsToDeleteBeforePublish: [],
        legacyRowIdsToDeleteAfterConfirmation: [],
        targetHeadRowId: '',
        targetDeviceId: '',
        targetGeneration: 0,
        targetStateChecksum: ''
      },
      errorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

@Concurrent
function planHuaweiHistoryInitialMerge(
  remote: HuaweiSpaceHistorySyncState,
  local: HuaweiSpaceHistorySyncState,
  now: number
): AiraHistoryInitialMergePlan {
  const mergeService = new HistorySyncMergeService();
  const merged = mergeService.mergeKeepingPreferredVisits(remote, local, now);
  return {
    merged,
    localApplyRequired: !mergeService.sameState(merged, local),
    remoteWriteRequired: !mergeService.sameState(merged, remote)
  };
}

@Concurrent
function planHuaweiHistoryRemoteWrite(
  uid: string,
  deviceId: string,
  rowBuffer: ArrayBuffer,
  desiredBuffer: ArrayBuffer,
  generatedAt: number
): AiraHistoryRemoteWritePlanOutcome {
  let current: HuaweiSpaceHistoryPhysicalMirror;
  try {
    current = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .decodeRows(AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer), generatedAt);
  } catch (error) {
    const candidate = error as Error;
    return {
      decodeErrorMessage: candidate.message ?? JSON.stringify(error),
      computeErrorMessage: ''
    };
  }
  try {
    const desired = AiraHistoryTaskpoolTransferCodec.decodeState(desiredBuffer);
    const projection = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .buildProjection(desired, current, generatedAt);
    return {
      plan: { projection: AiraHistoryTaskpoolTransferCodec.leanProjection(projection) },
      decodeErrorMessage: '',
      computeErrorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      decodeErrorMessage: '',
      computeErrorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

@Concurrent
function confirmHuaweiHistoryRemoteWrite(
  uid: string,
  deviceId: string,
  rowBuffer: ArrayBuffer,
  desiredBuffer: ArrayBuffer,
  projection: AiraHistoryRemoteWriteProjection,
  now: number
): AiraHistoryRemoteWriteConfirmationOutcome {
  let confirmedMirror: HuaweiSpaceHistoryPhysicalMirror;
  try {
    confirmedMirror = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .decodeRows(AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer), now);
  } catch (error) {
    const candidate = error as Error;
    return {
      decodeErrorMessage: candidate.message ?? JSON.stringify(error),
      computeErrorMessage: ''
    };
  }
  try {
    const desired = AiraHistoryTaskpoolTransferCodec.decodeState(desiredBuffer);
    const mergeService = new HistorySyncMergeService();
    const projectionConfirmed = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .isProjectionTargetConfirmed(
        confirmedMirror,
        projection.targetHeadRowId,
        projection.targetDeviceId,
        projection.targetGeneration,
        projection.targetStateChecksum
      );
    if (projectionConfirmed) {
      return {
        confirmation: {
          confirmed: confirmedMirror.state,
          projectionConfirmed: true,
          desiredStateConfirmed: true,
          localApplyRequired: false
        },
        decodeErrorMessage: '',
        computeErrorMessage: ''
      };
    }
    const confirmed = mergeService.merge(confirmedMirror.state, mergeService.emptyState(), now);
    const confirmedWithDesired = mergeService.merge(confirmedMirror.state, desired, now);
    return {
      confirmation: {
        confirmed,
        projectionConfirmed: false,
        desiredStateConfirmed: mergeService.sameState(confirmed, confirmedWithDesired),
        localApplyRequired: !mergeService.sameState(confirmed, desired)
      },
      decodeErrorMessage: '',
      computeErrorMessage: ''
    };
  } catch (error) {
    const candidate = error as Error;
    return {
      decodeErrorMessage: '',
      computeErrorMessage: candidate.message ?? JSON.stringify(error)
    };
  }
}

function resolveHuaweiHistoryRemoteWritePlanOutcome(
  outcome: AiraHistoryRemoteWritePlanOutcome
): AiraHistoryRemoteWritePlan {
  if (outcome.decodeErrorMessage.length > 0) {
    throw new AiraHistoryMirrorDecodeError(outcome.decodeErrorMessage);
  }
  if (outcome.plan === undefined) {
    throw new Error(outcome.computeErrorMessage);
  }
  return outcome.plan;
}

function resolveHuaweiHistoryRemoteWriteConfirmationOutcome(
  outcome: AiraHistoryRemoteWriteConfirmationOutcome
): AiraHistoryRemoteWriteConfirmation {
  if (outcome.decodeErrorMessage.length > 0) {
    throw new AiraHistoryMirrorDecodeError(outcome.decodeErrorMessage);
  }
  if (outcome.confirmation === undefined) {
    throw new Error(outcome.computeErrorMessage);
  }
  return outcome.confirmation;
}

function estimateTransferStringBytes(value: string): number {
  return value.length * 2 + 32;
}

function estimateHuaweiHistoryStateTransferBytes(state: HuaweiSpaceHistorySyncState): number {
  let total = 64;
  state.visits.forEach((visit): void => {
    total += 128 +
      estimateTransferStringBytes(visit.visitId) +
      estimateTransferStringBytes(visit.clientId) +
      estimateTransferStringBytes(visit.nativeVisitId) +
      estimateTransferStringBytes(visit.url) +
      estimateTransferStringBytes(visit.title) +
      estimateTransferStringBytes(visit.transition) +
      estimateTransferStringBytes(visit.referrer) +
      estimateTransferStringBytes(visit.deviceName) +
      estimateTransferStringBytes(visit.source);
  });
  state.tombstones.forEach((value): void => {
    total += 64 + estimateTransferStringBytes(value.visitId);
  });
  state.deleteRanges.forEach((value): void => {
    total += 96 + estimateTransferStringBytes(value.rangeId) + estimateTransferStringBytes(value.url);
  });
  return total + 128 + estimateTransferStringBytes(state.retentionFrontier.boundaryVisitId);
}

function estimateHuaweiHistoryRowsTransferBytes(rows: HuaweiSpaceHistoryRow[]): number {
  let total = 64;
  rows.forEach((row: HuaweiSpaceHistoryRow): void => {
    total += 128 +
      estimateTransferStringBytes(row.rowId) +
      estimateTransferStringBytes(row.recordKind) +
      estimateTransferStringBytes(row.logicalId) +
      estimateTransferStringBytes(row.data);
  });
  return total;
}

function fitsTaskpoolTransferBudget(estimatedBytes: number): boolean {
  return estimatedBytes > 0 && estimatedBytes <= AIRA_SYNC_TASKPOOL_TRANSFER_BUDGET_BYTES;
}

function fitsTaskpoolPackPreflightBudget(estimatedBytes: number): boolean {
  return estimatedBytes > 0 && estimatedBytes <= AIRA_SYNC_TASKPOOL_PACK_PREFLIGHT_BUDGET_BYTES;
}

function resolveHuaweiHistoryRemoteStateDecodeOutcome(
  outcome: AiraHistoryRemoteStateDecodeOutcome
): AiraHistoryRemoteStateDecode {
  if (outcome.decoded === undefined) {
    throw new AiraHistoryMirrorDecodeError(outcome.errorMessage);
  }
  return outcome.decoded;
}

export class AiraSyncComputeExecutor {
  private readonly cooperativeThrottle: AiraSyncWorkThrottleService = new AiraSyncWorkThrottleService(
    undefined,
    { batchSize: 250, batchPauseMs: 16, stagePauseMs: 16 }
  );

  async decodeHuaweiHistoryRemoteState(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[]
  ): Promise<AiraHistoryRemoteStateDecode> {
    const now = Date.now();
    const estimatedBytes = estimateHuaweiHistoryRowsTransferBytes(rows);
    if (!fitsTaskpoolPackPreflightBudget(estimatedBytes)) {
      try {
        const mirror = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
          .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
        return {
          state: mirror.state,
          legacyRowIds: mirror.legacyRowIds
        };
      } catch (error) {
        const candidate = error as Error;
        throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
      }
    }
    const rowBuffer = await this.packHuaweiHistoryRowsForTransfer(rows);
    const transferBytes = rowBuffer.byteLength;
    if (!fitsTaskpoolTransferBudget(transferBytes)) {
      try {
        const mirror = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
          .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
        return {
          state: mirror.state,
          legacyRowIds: mirror.legacyRowIds
        };
      } catch (error) {
        const candidate = error as Error;
        throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
      }
    }
    const task = new taskpool.Task(
      'aira-sync-history-decode-state',
      decodeHuaweiHistoryRemoteState,
      uid,
      deviceId,
      rowBuffer,
      now
    );
    task.setTransferList([rowBuffer]);
    const outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryRemoteStateDecodeOutcome;
    return resolveHuaweiHistoryRemoteStateDecodeOutcome(outcome);
  }

  async decodePackedHuaweiHistoryRemoteState(
    uid: string,
    deviceId: string,
    rowBuffer: ArrayBuffer
  ): Promise<AiraHistoryRemoteStateDecode> {
    const now = Date.now();
    if (!fitsTaskpoolTransferBudget(rowBuffer.byteLength)) {
      const rows = AiraHistoryTaskpoolTransferCodec.decodeRows(rowBuffer);
      try {
        const mirror = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
          .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
        return {
          state: mirror.state,
          legacyRowIds: mirror.legacyRowIds
        };
      } catch (error) {
        const candidate = error as Error;
        throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
      }
    }
    const task = new taskpool.Task(
      'aira-sync-history-decode-state',
      decodeHuaweiHistoryRemoteState,
      uid,
      deviceId,
      rowBuffer,
      now
    );
    task.setTransferList([rowBuffer]);
    const outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryRemoteStateDecodeOutcome;
    return resolveHuaweiHistoryRemoteStateDecodeOutcome(outcome);
  }


  async planHuaweiHistoryReplicaPacked(
    uid: string,
    deviceId: string,
    rowBuffer: ArrayBuffer,
    local: HuaweiSpaceHistorySyncState
  ): Promise<HuaweiHistoryReplicaPackedOutcome> {
    const localBuffer = await this.packHuaweiHistoryStateForTransfer(local);
    const task = new taskpool.Task(
      'aira-sync-history-replica-packed',
      planHuaweiHistoryReplicaPacked,
      uid,
      deviceId,
      rowBuffer,
      localBuffer,
      Date.now()
    );
    task.setTransferList([rowBuffer, localBuffer]);
    const startedAt = Date.now();
    const outcome = await taskpool.execute(task, taskpool.Priority.LOW) as HuaweiHistoryReplicaPackedOutcome;
    AiraSyncJankProbe.endExtra(
      'history_replica_packed',
      startedAt,
      `error=${outcome.errorMessage.length > 0 ? 1 : 0} write=${outcome.remoteWriteRequired ? 1 : 0}`
    );
    return outcome;
  }

  async planHuaweiHistoryInitialMerge(
    remote: HuaweiSpaceHistorySyncState,
    local: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryInitialMergePlan> {
    const estimatedBytes = estimateHuaweiHistoryStateTransferBytes(remote) +
      estimateHuaweiHistoryStateTransferBytes(local);
    if (!fitsTaskpoolTransferBudget(estimatedBytes)) {
      return this.planHuaweiHistoryInitialMergeCooperatively(remote, local);
    }
    const packStartedAt = Date.now();
    const remoteBuffer = await this.packHuaweiHistoryStateForTransfer(remote);
    const localBuffer = await this.packHuaweiHistoryStateForTransfer(local);
    AiraSyncJankProbe.endExtra(
      'history_merge_pack',
      packStartedAt,
      `bytes=${remoteBuffer.byteLength + localBuffer.byteLength}`
    );
    if (!fitsTaskpoolTransferBudget(remoteBuffer.byteLength + localBuffer.byteLength)) {
      AiraSyncJankProbe.mark('history_merge_fallback_budget');
      return this.planHuaweiHistoryInitialMergeCooperatively(remote, local);
    }
    const task = new taskpool.Task(
      'aira-sync-history-initial-merge-packed',
      planHuaweiHistoryInitialMergePacked,
      remoteBuffer,
      localBuffer,
      Date.now()
    );
    task.setTransferList([remoteBuffer, localBuffer]);
    const taskStartedAt = Date.now();
    let outcome: AiraHistoryInitialMergePackedOutcome;
    try {
      outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryInitialMergePackedOutcome;
    } catch (_error) {
      AiraSyncJankProbe.endExtra('history_merge_taskpool', taskStartedAt, 'error=throw');
      return this.planHuaweiHistoryInitialMergeCooperatively(remote, local);
    }
    AiraSyncJankProbe.endExtra(
      'history_merge_taskpool',
      taskStartedAt,
      `error=${outcome.errorMessage.length > 0 ? 1 : 0}`
    );
    if (outcome.errorMessage.length > 0) {
      AiraSyncJankProbe.markExtra('history_merge_fallback_cooperative', outcome.errorMessage);
      return this.planHuaweiHistoryInitialMergeCooperatively(remote, local);
    }
    if (!outcome.localApplyRequired && !outcome.remoteWriteRequired) {
      return {
        merged: remote,
        localApplyRequired: false,
        remoteWriteRequired: false
      };
    }
    const unpackStartedAt = Date.now();
    const merged = AiraHistoryTaskpoolTransferCodec.decodeState(outcome.mergedBuffer);
    AiraSyncJankProbe.endExtra(
      'history_merge_unpack',
      unpackStartedAt,
      `apply=${outcome.localApplyRequired ? 1 : 0} write=${outcome.remoteWriteRequired ? 1 : 0}`
    );
    await this.cooperativeThrottle.afterStage();
    return {
      merged: merged,
      localApplyRequired: outcome.localApplyRequired,
      remoteWriteRequired: outcome.remoteWriteRequired
    };
  }

  private async planHuaweiHistoryInitialMergeCooperatively(
    remote: HuaweiSpaceHistorySyncState,
    local: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryInitialMergePlan> {
    const now = Date.now();
    const mergeService = new HistorySyncMergeService();
    const merged = await mergeService.mergeKeepingPreferredVisitsCooperatively(
      remote,
      local,
      this.cooperativeThrottle,
      now
    );
    return {
      merged,
      localApplyRequired: !(await mergeService.sameStateCooperatively(
        merged,
        local,
        this.cooperativeThrottle
      )),
      remoteWriteRequired: !(await mergeService.sameStateCooperatively(
        merged,
        remote,
        this.cooperativeThrottle
      ))
    };
  }

  async planHuaweiHistoryRemoteWrite(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[],
    desired: HuaweiSpaceHistorySyncState,
    packedRows: ArrayBuffer | undefined = undefined
  ): Promise<AiraHistoryRemoteWritePlan> {
    const rowBuffer = packedRows !== undefined ? packedRows : await this.packHuaweiHistoryRowsForTransfer(rows);
    const desiredBuffer = await this.packHuaweiHistoryStateForTransfer(desired);
    const transferBytes = rowBuffer.byteLength + desiredBuffer.byteLength;
    if (!fitsTaskpoolTransferBudget(transferBytes)) {
      return this.planHuaweiHistoryRemoteWriteCooperatively(uid, deviceId, rows, desired);
    }
    const task = new taskpool.Task(
      'aira-sync-history-remote-write-plan',
      planHuaweiHistoryRemoteWrite,
      uid,
      deviceId,
      rowBuffer,
      desiredBuffer,
      Date.now()
    );
    task.setTransferList([rowBuffer, desiredBuffer]);
    let outcome: AiraHistoryRemoteWritePlanOutcome;
    try {
      outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryRemoteWritePlanOutcome;
    } catch (_error) {
      return this.planHuaweiHistoryRemoteWriteCooperatively(uid, deviceId, rows, desired);
    }
    return resolveHuaweiHistoryRemoteWritePlanOutcome(outcome);
  }

  async confirmHuaweiHistoryRemoteWrite(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[],
    projection: AiraHistoryRemoteWriteProjection,
    desired: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryRemoteWriteConfirmation> {
    const rowBuffer = await this.packHuaweiHistoryRowsForTransfer(rows);
    const desiredBuffer = await this.packHuaweiHistoryStateForTransfer(desired);
    const transferBytes = rowBuffer.byteLength + desiredBuffer.byteLength;
    if (!fitsTaskpoolTransferBudget(transferBytes)) {
      return this.confirmHuaweiHistoryRemoteWriteCooperatively(
        uid,
        deviceId,
        rows,
        projection,
        desired
      );
    }
    const task = new taskpool.Task(
      'aira-sync-history-remote-write-confirm',
      confirmHuaweiHistoryRemoteWrite,
      uid,
      deviceId,
      rowBuffer,
      desiredBuffer,
      projection,
      Date.now()
    );
    task.setTransferList([rowBuffer, desiredBuffer]);
    let outcome: AiraHistoryRemoteWriteConfirmationOutcome;
    try {
      outcome = await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryRemoteWriteConfirmationOutcome;
    } catch (_error) {
      return this.confirmHuaweiHistoryRemoteWriteCooperatively(
        uid,
        deviceId,
        rows,
        projection,
        desired
      );
    }
    return resolveHuaweiHistoryRemoteWriteConfirmationOutcome(outcome);
  }

  private async planHuaweiHistoryRemoteWriteCooperatively(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[],
    desired: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryRemoteWritePlan> {
    const now = Date.now();
    let current: HuaweiSpaceHistoryPhysicalMirror;
    try {
      current = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
        .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
    } catch (error) {
      const candidate = error as Error;
      throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
    }
    const projection = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .buildProjectionCooperatively(desired, current, this.cooperativeThrottle, now);
    return { projection: AiraHistoryTaskpoolTransferCodec.leanProjection(projection) };
  }

  private async confirmHuaweiHistoryRemoteWriteCooperatively(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[],
    projection: AiraHistoryRemoteWriteProjection,
    desired: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryRemoteWriteConfirmation> {
    const now = Date.now();
    let mirror: HuaweiSpaceHistoryPhysicalMirror;
    try {
      mirror = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
        .decodeRowsCooperatively(rows, this.cooperativeThrottle, now);
    } catch (error) {
      const candidate = error as Error;
      throw new AiraHistoryMirrorDecodeError(candidate.message ?? JSON.stringify(error));
    }
    const mergeService = new HistorySyncMergeService();
    const projectionConfirmed = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .isProjectionTargetConfirmed(
        mirror,
        projection.targetHeadRowId,
        projection.targetDeviceId,
        projection.targetGeneration,
        projection.targetStateChecksum
      );
    if (projectionConfirmed) {
      return {
        confirmed: mirror.state,
        projectionConfirmed: true,
        desiredStateConfirmed: true,
        localApplyRequired: false
      };
    }
    const confirmed = await mergeService.mergeCooperatively(
      mirror.state,
      mergeService.emptyState(),
      this.cooperativeThrottle,
      now
    );
    const confirmedWithDesired = await mergeService.mergeCooperatively(
      mirror.state,
      desired,
      this.cooperativeThrottle,
      now
    );
    return {
      confirmed,
      projectionConfirmed: false,
      desiredStateConfirmed: await mergeService.sameStateCooperatively(
        confirmed,
        confirmedWithDesired,
        this.cooperativeThrottle
      ),
      localApplyRequired: !(await mergeService.sameStateCooperatively(
        confirmed,
        desired,
        this.cooperativeThrottle
      ))
    };
  }

  private async packHuaweiHistoryRowsForTransfer(
    rows: HuaweiSpaceHistoryRow[]
  ): Promise<ArrayBuffer> {
    const packed = AiraHistoryTaskpoolTransferCodec.encodeRows(rows);
    await this.cooperativeThrottle.afterStage();
    return packed;
  }

  private async packHuaweiHistoryStateForTransfer(
    state: HuaweiSpaceHistorySyncState
  ): Promise<ArrayBuffer> {
    const packed = AiraHistoryTaskpoolTransferCodec.encodeState(state);
    await this.cooperativeThrottle.afterStage();
    return packed;
  }

}
