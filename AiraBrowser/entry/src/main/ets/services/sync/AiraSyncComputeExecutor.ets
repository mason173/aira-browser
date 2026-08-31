import { taskpool, util } from '@kit.ArkTS';
import {
  HistorySyncRetentionFrontier,
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

const AIRA_SYNC_TASKPOOL_TRANSFER_BUDGET_BYTES: number = 8 * 1024 * 1024;
const AIRA_SYNC_TASKPOOL_PACK_PREFLIGHT_BUDGET_BYTES: number = 16 * 1024 * 1024;
const AIRA_SYNC_HISTORY_ROW_LENGTH_BYTES: number = 4;
const AIRA_SYNC_HISTORY_STATE_FRAME_HEADER_BYTES: number = 5;
const AIRA_SYNC_HISTORY_STATE_FRAME_METADATA: number = 0;
const AIRA_SYNC_HISTORY_STATE_FRAME_VISIT: number = 1;
const AIRA_SYNC_HISTORY_STATE_FRAME_TOMBSTONE: number = 2;
const AIRA_SYNC_HISTORY_STATE_FRAME_DELETE_RANGE: number = 3;

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

interface AiraHistoryStateMetadata {
  clearBefore: number;
  retentionFrontier: HistorySyncRetentionFrontier;
}

interface AiraHistoryTransferFrame {
  kind: number;
  bytes: Uint8Array;
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
    const rowLengthBytes = 4;
    const decoder = util.TextDecoder.create('utf-8');
    const bytes = new Uint8Array(rowBuffer);
    const rows: HuaweiSpaceHistoryRow[] = [];
    let offset = 0;
    while (offset < bytes.byteLength) {
      if (offset + rowLengthBytes > bytes.byteLength) {
        throw new Error('Huawei History TaskPool row frame is truncated.');
      }
      const rowLength = (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
      offset += rowLengthBytes;
      if (rowLength <= 0 || offset + rowLength > bytes.byteLength) {
        throw new Error('Huawei History TaskPool row frame length is invalid.');
      }
      const rowBytes = bytes.subarray(offset, offset + rowLength);
      rows.push(JSON.parse(decoder.decodeToString(rowBytes)) as HuaweiSpaceHistoryRow);
      offset += rowLength;
    }
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
    const mergeService = new HistorySyncMergeService();
    const merged = mergeService.merge(current.state, desired, generatedAt);
    const projection = new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .buildProjection(merged, current, generatedAt);
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
    const confirmed = mergeService.merge(confirmedMirror.state, mergeService.emptyState(), now);
    const confirmedWithDesired = mergeService.merge(confirmedMirror.state, desired, now);
    return {
      confirmation: {
        confirmed,
        projectionConfirmed: new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
          .isProjectionTargetConfirmed(
            confirmedMirror,
            projection.targetHeadRowId,
            projection.targetDeviceId,
            projection.targetGeneration,
            projection.targetStateChecksum
          ),
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

function writeHuaweiHistoryTransferFrame(
  target: Uint8Array,
  offset: number,
  frame: AiraHistoryTransferFrame
): number {
  const frameLength = frame.bytes.byteLength;
  target[offset] = frame.kind;
  target[offset + 1] = (frameLength >>> 24) & 0xff;
  target[offset + 2] = (frameLength >>> 16) & 0xff;
  target[offset + 3] = (frameLength >>> 8) & 0xff;
  target[offset + 4] = frameLength & 0xff;
  target.set(frame.bytes, offset + AIRA_SYNC_HISTORY_STATE_FRAME_HEADER_BYTES);
  return offset + AIRA_SYNC_HISTORY_STATE_FRAME_HEADER_BYTES + frameLength;
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
    { batchSize: 16, batchPauseMs: 0, stagePauseMs: 4 }
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

  async planHuaweiHistoryInitialMerge(
    remote: HuaweiSpaceHistorySyncState,
    local: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryInitialMergePlan> {
    const estimatedBytes = estimateHuaweiHistoryStateTransferBytes(remote) +
      estimateHuaweiHistoryStateTransferBytes(local);
    if (!fitsTaskpoolTransferBudget(estimatedBytes)) {
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
    const task = new taskpool.Task(
      'aira-sync-history-initial-merge',
      planHuaweiHistoryInitialMerge,
      remote,
      local,
      Date.now()
    );
    return await taskpool.execute(task, taskpool.Priority.LOW) as AiraHistoryInitialMergePlan;
  }

  async planHuaweiHistoryRemoteWrite(
    uid: string,
    deviceId: string,
    rows: HuaweiSpaceHistoryRow[],
    desired: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryRemoteWritePlan> {
    const rowBuffer = await this.packHuaweiHistoryRowsForTransfer(rows);
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
    const merged = await new HistorySyncMergeService().mergeCooperatively(
      current.state,
      desired,
      this.cooperativeThrottle,
      now
    );
    const projection = await new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
      .buildProjectionCooperatively(merged, current, this.cooperativeThrottle, now);
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
      projectionConfirmed: new HuaweiSpaceHistorySnapshotCodec(uid, deviceId)
        .isProjectionTargetConfirmed(
          mirror,
          projection.targetHeadRowId,
          projection.targetDeviceId,
          projection.targetGeneration,
          projection.targetStateChecksum
        ),
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
    const encoder = util.TextEncoder.create('utf-8');
    const encodedRows: Uint8Array[] = [];
    let packedByteLength = 0;
    for (let index = 0; index < rows.length; index += 1) {
      const encoded = encoder.encodeInto(JSON.stringify(rows[index]));
      encodedRows.push(encoded);
      packedByteLength += AIRA_SYNC_HISTORY_ROW_LENGTH_BYTES + encoded.byteLength;
      await this.cooperativeThrottle.afterBatchItem(index + 1);
    }
    const packed = new ArrayBuffer(packedByteLength);
    const packedBytes = new Uint8Array(packed);
    let offset = 0;
    for (let index = 0; index < encodedRows.length; index += 1) {
      const encoded = encodedRows[index];
      const rowLength = encoded.byteLength;
      packedBytes[offset] = (rowLength >>> 24) & 0xff;
      packedBytes[offset + 1] = (rowLength >>> 16) & 0xff;
      packedBytes[offset + 2] = (rowLength >>> 8) & 0xff;
      packedBytes[offset + 3] = rowLength & 0xff;
      offset += AIRA_SYNC_HISTORY_ROW_LENGTH_BYTES;
      packedBytes.set(encoded, offset);
      offset += rowLength;
      await this.cooperativeThrottle.afterBatchItem(index + 1);
    }
    return packed;
  }

  private async packHuaweiHistoryStateForTransfer(
    state: HuaweiSpaceHistorySyncState
  ): Promise<ArrayBuffer> {
    const encoder = util.TextEncoder.create('utf-8');
    const frames: AiraHistoryTransferFrame[] = [];
    let packedByteLength = 0;
    const append = (kind: number, value: Object): void => {
      const bytes = encoder.encodeInto(JSON.stringify(value));
      frames.push({ kind, bytes });
      packedByteLength += AIRA_SYNC_HISTORY_STATE_FRAME_HEADER_BYTES + bytes.byteLength;
    };
    const metadata: AiraHistoryStateMetadata = {
      clearBefore: state.clearBefore,
      retentionFrontier: state.retentionFrontier
    };
    append(AIRA_SYNC_HISTORY_STATE_FRAME_METADATA, metadata);
    let processed = 0;
    for (let index = 0; index < state.visits.length; index += 1) {
      append(AIRA_SYNC_HISTORY_STATE_FRAME_VISIT, state.visits[index]);
      processed += 1;
      await this.cooperativeThrottle.afterBatchItem(processed);
    }
    for (let index = 0; index < state.tombstones.length; index += 1) {
      append(AIRA_SYNC_HISTORY_STATE_FRAME_TOMBSTONE, state.tombstones[index]);
      processed += 1;
      await this.cooperativeThrottle.afterBatchItem(processed);
    }
    for (let index = 0; index < state.deleteRanges.length; index += 1) {
      append(AIRA_SYNC_HISTORY_STATE_FRAME_DELETE_RANGE, state.deleteRanges[index]);
      processed += 1;
      await this.cooperativeThrottle.afterBatchItem(processed);
    }
    const packed = new ArrayBuffer(packedByteLength);
    const packedBytes = new Uint8Array(packed);
    let offset = 0;
    for (let index = 0; index < frames.length; index += 1) {
      offset = writeHuaweiHistoryTransferFrame(packedBytes, offset, frames[index]);
      await this.cooperativeThrottle.afterBatchItem(index + 1);
    }
    return packed;
  }

}
