import { hilog } from '@kit.PerformanceAnalysisKit';
import { HistorySyncMutation, HistorySyncRunResult, HuaweiSpaceHistorySyncState } from '../../common/models/HistorySyncModels';
import { BrowserDatabase } from '../../data/database/BrowserDatabase';
import {
  HuaweiSpaceHistoryRemoteStore,
  HuaweiSpaceHistoryWriteResult
} from '../../data/sync/HuaweiSpaceHistoryRemoteStore';
import { HuaweiSpaceHistorySnapshotCodec } from '../../data/sync/HuaweiSpaceHistorySnapshotCodec';
import {
  AiraHistoryInitialMergePlan,
  AiraSyncComputeExecutor,
  HuaweiHistoryReplicaPackedOutcome
} from './AiraSyncComputeExecutor';
import { HistorySyncMergeService } from './HistorySyncMergeService';
import { AiraHistoryTaskpoolTransferCodec } from './AiraHistoryTaskpoolTransferCodec';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';

const HISTORY_HUAWEI_ENROLLMENT_BATCH_SIZE: number = 500;
const HISTORY_HUAWEI_MAX_ENROLLMENT_ROUNDS: number = 200;

export interface HuaweiSpaceHistorySyncIdentity {
  accountUid: string;
  clientId: string;
  deviceName: string;
}

export type HuaweiSpaceHistoryRemoteStoreFactory = (
  uid: string,
  clientId: string
) => HuaweiSpaceHistoryRemoteStore;

const HISTORY_HUAWEI_LOG_DOMAIN: number = 0x0000;
const HISTORY_HUAWEI_LOG_TAG: string = 'HuaweiHistorySync';

export function shouldUseCachedHuaweiHistoryRemote(
  ordinaryRun: boolean,
  accountUid: string,
  lastConfirmedAccountUid: string,
  lastConfirmed: HuaweiSpaceHistorySyncState | undefined
): boolean {
  if (!ordinaryRun || lastConfirmed === undefined) {
    return false;
  }
  const normalizedAccount = accountUid.trim();
  return normalizedAccount.length > 0 && normalizedAccount === lastConfirmedAccountUid.trim();
}

export function shouldSkipUnchangedHuaweiHistoryRemote(
  enrolledCount: number,
  hasPendingLocalMutations: boolean,
  knownChecksum: string,
  remoteHeadChecksum: string
): boolean {
  const known = knownChecksum.trim();
  const remote = remoteHeadChecksum.trim();
  return enrolledCount <= 0 && !hasPendingLocalMutations && known.length > 0 && known === remote;
}

export function shouldLoadUnchangedHuaweiHistoryReplica(
  enrolledCount: number,
  hasPendingLocalMutations: boolean,
  knownChecksum: string,
  remoteHeadChecksum: string
): boolean {
  const known = knownChecksum.trim();
  const remote = remoteHeadChecksum.trim();
  return (enrolledCount > 0 || hasPendingLocalMutations) && known.length > 0 && known === remote;
}

export type HuaweiHistoryRemoteReadPlan = 'skip' | 'replica' | 'cloud';

export function hasHuaweiHistoryLocalWork(
  enrolledCount: number,
  hasOutbox: boolean,
  hasRecentTombstones: boolean,
  headMatches: boolean
): boolean {
  return enrolledCount > 0 || hasOutbox || (headMatches && hasRecentTombstones);
}

export function resolveHuaweiHistoryRemoteReadPlan(
  hasLocalWork: boolean,
  headMatches: boolean,
  remoteHeadChecksum: string,
  localReplicaReady: boolean
): HuaweiHistoryRemoteReadPlan {
  if (remoteHeadChecksum.trim().length <= 0) {
    return 'cloud';
  }
  if (!hasLocalWork && (headMatches || localReplicaReady)) {
    return 'skip';
  }
  if (hasLocalWork && (headMatches || localReplicaReady)) {
    return 'replica';
  }
  return 'cloud';
}

export class HuaweiSpaceHistorySyncRunner {
  private readonly database: BrowserDatabase;
  private readonly remoteStoreFactory: HuaweiSpaceHistoryRemoteStoreFactory;
  private readonly computeExecutor: AiraSyncComputeExecutor = new AiraSyncComputeExecutor();
  private readonly mergeService: HistorySyncMergeService = new HistorySyncMergeService();
  private lastConfirmedAccountUid: string = '';
  private lastConfirmedState?: HuaweiSpaceHistorySyncState;

  constructor(
    database: BrowserDatabase,
    remoteStoreFactory?: HuaweiSpaceHistoryRemoteStoreFactory
  ) {
    this.database = database;
    this.remoteStoreFactory = remoteStoreFactory ??
      ((uid: string, clientId: string): HuaweiSpaceHistoryRemoteStore => {
        return new HuaweiSpaceHistoryRemoteStore(uid, clientId);
      });
  }

  async run(
    identity: HuaweiSpaceHistorySyncIdentity,
    clearOutboxAfterSuccess: boolean = true
  ): Promise<HistorySyncRunResult> {
    const runStartedAt = Date.now();
    await this.database.initialize();
    let stageStartedAt = Date.now();
    let appliedChangeCount = await this.database.pruneHistorySyncProjection(identity.accountUid);
    this.logStage('prune', stageStartedAt, `applied=${appliedChangeCount}`);
    stageStartedAt = Date.now();
    const enrolled = await this.enrollLocalVisits(identity);
    this.logStage('enroll', stageStartedAt, `enrolled=${enrolled}`);
    const remoteStore = this.remoteStoreFactory(identity.accountUid, identity.clientId);
    const knownHead = await this.database.readHuaweiHistoryRemoteHead(identity.accountUid);
    const knownChecksum = knownHead.checksum;
    const hasOutbox = await this.database.hasHistorySyncOutbox(identity.accountUid);
    const hasRecentTombstones =
      await this.database.hasHistorySyncTombstonesSince(identity.accountUid, knownHead.updatedAt);
    const useCachedRemote = shouldUseCachedHuaweiHistoryRemote(
      clearOutboxAfterSuccess,
      identity.accountUid,
      this.lastConfirmedAccountUid,
      this.lastConfirmedState
    );
    let remote: HuaweiSpaceHistorySyncState | undefined = undefined;
    if (!useCachedRemote) {
      stageStartedAt = Date.now();
      const peekedChecksum = await remoteStore.peekHeadChecksum();
      const headMatches = knownChecksum.length > 0 && knownChecksum === peekedChecksum;
      const hasLocalWork = hasHuaweiHistoryLocalWork(
        enrolled,
        hasOutbox,
        hasRecentTombstones,
        headMatches
      );
      let localReplicaReady = false;
      if (hasLocalWork && headMatches) {
        localReplicaReady = await remoteStore.preparePackedReplicaRows();
      } else if (!(!hasLocalWork && headMatches) && peekedChecksum.length > 0) {
        remote = await remoteStore.tryReadLocalReplicaMatchingHead(peekedChecksum);
        localReplicaReady = remote !== undefined;
      }
      const plan = resolveHuaweiHistoryRemoteReadPlan(
        hasLocalWork,
        headMatches,
        peekedChecksum,
        localReplicaReady
      );
      AiraSyncJankProbe.markExtra(
        'history_read_plan',
        `plan=${plan} headMatches=${headMatches ? 1 : 0} replicaReady=${localReplicaReady ? 1 : 0}` +
          ` localWork=${hasLocalWork ? 1 : 0} enrolled=${enrolled} outbox=${hasOutbox ? 1 : 0}` +
          ` tombstones=${hasRecentTombstones ? 1 : 0}`
      );
      if (plan === 'skip') {
        this.logStage('read-remote', stageStartedAt, 'source=head-unchanged');
        if (peekedChecksum.length > 0) {
          await this.database.writeHuaweiHistoryRemoteHeadChecksum(identity.accountUid, peekedChecksum);
        }
        this.logStage('run-total', runStartedAt, 'applied=0 uploaded=0 skipped=1');
        return {
          ok: true,
          appliedChangeCount: appliedChangeCount,
          uploadedMutationCount: 0,
          message: '历史记录已经是最新。'
        };
      }
      if (plan === 'replica') {
        this.logStage('read-remote', stageStartedAt, 'source=head-unchanged-replica');
        if (headMatches) {
          const lite = await this.tryLiteReplicaWrite(
            identity,
            remoteStore,
            knownHead.updatedAt,
            clearOutboxAfterSuccess,
            appliedChangeCount,
            runStartedAt
          );
          if (lite !== undefined) {
            return lite;
          }
          const packedRows = remoteStore.takePackedReplicaRows();
          if (packedRows !== undefined) {
            return await this.runPackedReplica(
              identity,
              remoteStore,
              packedRows,
              clearOutboxAfterSuccess,
              appliedChangeCount,
              runStartedAt
            );
          }
        }
      } else {
        remote = await remoteStore.readCloudBlocksAndDecode();
        this.logStage('read-remote', stageStartedAt, 'source=cloud');
      }
    }
    stageStartedAt = Date.now();
    const local = await this.database.readHuaweiSpaceHistorySyncState(identity.accountUid);
    this.logStage('read-local', stageStartedAt);
    const cachedRemote = this.lastConfirmedState;
    stageStartedAt = Date.now();
    if (remote === undefined && useCachedRemote && cachedRemote !== undefined) {
      hilog.info(
        HISTORY_HUAWEI_LOG_DOMAIN,
        HISTORY_HUAWEI_LOG_TAG,
        'Huawei history used cached remote and skipped CLOUD_FIRST'
      );
      remote = cachedRemote;
      this.logStage('read-remote', stageStartedAt, 'source=cache');
    } else if (remote === undefined) {
      remote = await remoteStore.readState();
      this.logStage('read-remote', stageStartedAt, 'source=cloud');
    }
    if (remote === undefined) {
      throw new Error('华为云空间历史记录读取失败。');
    }
    stageStartedAt = Date.now();
    const initialPlan: AiraHistoryInitialMergePlan =
      await this.computeExecutor.planHuaweiHistoryInitialMerge(remote, local);
    this.logStage(
      'plan-merge',
      stageStartedAt,
      `write=${initialPlan.remoteWriteRequired ? 1 : 0} apply=${initialPlan.localApplyRequired ? 1 : 0}`
    );
    stageStartedAt = Date.now();
    const firstApplied = initialPlan.localApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, initialPlan.merged)
      : 0;
    appliedChangeCount += firstApplied;
    this.logStage('apply-local', stageStartedAt, `applied=${firstApplied}`);
    const desired = initialPlan.merged;
    const remoteMaintenanceRequired = remoteStore.requiresMaintenance();
    const remoteWriteRequired = initialPlan.remoteWriteRequired || remoteMaintenanceRequired;
    stageStartedAt = Date.now();
    const writeResult: HuaweiSpaceHistoryWriteResult = remoteWriteRequired
      ? await remoteStore.writeState(desired, useCachedRemote)
      : { state: remote, changedRowCount: 0, localApplyRequired: false };
    this.logStage(
      'write-remote',
      stageStartedAt,
      `required=${remoteWriteRequired ? 1 : 0} changed=${writeResult.changedRowCount} cached=${useCachedRemote ? 1 : 0}`
    );
    const confirmedState = remoteWriteRequired ? writeResult.state : initialPlan.merged;
    const confirmedLocalApplyRequired = remoteWriteRequired && writeResult.localApplyRequired;
    stageStartedAt = Date.now();
    const confirmedApplied = confirmedLocalApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, confirmedState)
      : 0;
    appliedChangeCount += confirmedApplied;
    this.logStage('apply-confirmed', stageStartedAt, `applied=${confirmedApplied}`);
    stageStartedAt = Date.now();
    const pruned = initialPlan.localApplyRequired || confirmedLocalApplyRequired
      ? await this.database.pruneHistorySyncProjection(identity.accountUid)
      : 0;
    appliedChangeCount += pruned;
    this.logStage('prune-final', stageStartedAt, `pruned=${pruned}`);
    if (clearOutboxAfterSuccess) {
      await this.database.clearHistorySyncOutbox(identity.accountUid);
    }
    this.lastConfirmedAccountUid = identity.accountUid;
    this.lastConfirmedState = this.mergeService.normalize(confirmedState);
    const confirmedChecksum = remoteStore.consumeLastHeadChecksum();
    if (confirmedChecksum.length > 0) {
      await this.database.writeHuaweiHistoryRemoteHeadChecksum(identity.accountUid, confirmedChecksum);
    }
    this.logStage(
      'run-total',
      runStartedAt,
      `applied=${appliedChangeCount} uploaded=${writeResult.changedRowCount}`
    );
    return {
      ok: true,
      appliedChangeCount,
      uploadedMutationCount: writeResult.changedRowCount,
      message: appliedChangeCount > 0 || writeResult.changedRowCount > 0
        ? '历史记录已完成华为云空间增量同步。'
        : '历史记录已经是最新。'
    };
  }


  private async tryLiteReplicaWrite(
    identity: HuaweiSpaceHistorySyncIdentity,
    remoteStore: HuaweiSpaceHistoryRemoteStore,
    knownHeadUpdatedAt: number,
    clearOutboxAfterSuccess: boolean,
    appliedChangeCount: number,
    runStartedAt: number
  ): Promise<HistorySyncRunResult | undefined> {
    const rawRows = remoteStore.peekFreshReplicaRows();
    if (rawRows === undefined || rawRows.length <= 0) {
      return undefined;
    }
    let stageStartedAt = Date.now();
    const local = await this.database.readHuaweiSpaceHistorySyncState(identity.accountUid);
    this.logStage('read-local', stageStartedAt);
    const outbox = await this.database.listHistorySyncOutbox(identity.accountUid, 32);
    const outboxVisitIds: string[] = [];
    let hasRangeOrClear = false;
    for (let index = 0; index < outbox.length; index += 1) {
      const mutation: HistorySyncMutation = outbox[index];
      if (mutation.kind === 'delete_range' || mutation.kind === 'clear_before') {
        hasRangeOrClear = true;
        break;
      }
      const visitId = mutation.visit?.visitId ?? mutation.visitId ?? '';
      if (visitId.trim().length > 0) {
        outboxVisitIds.push(visitId.trim());
      }
    }
    const codec = new HuaweiSpaceHistorySnapshotCodec(identity.accountUid, identity.clientId);
    const dirty = codec.collectDirtyBucketIndexes(local, knownHeadUpdatedAt, outboxVisitIds, hasRangeOrClear);
    if (dirty === undefined) {
      return undefined;
    }
    stageStartedAt = Date.now();
    try {
      const projection = AiraHistoryTaskpoolTransferCodec.leanProjection(
        codec.buildProjectionReusingHead(local, rawRows, dirty)
      );
      AiraSyncJankProbe.endExtra(
        'history_replica_lite',
        stageStartedAt,
        `dirty=${dirty.length} upsert=${projection.rowsToUpsert.length} delete=${projection.rowIdsToDeleteBeforePublish.length}`
      );
      this.logStage(
        'plan-merge',
        stageStartedAt,
        `write=1 apply=0 packed=0 lite=1 dirty=${dirty.length}`
      );
      stageStartedAt = Date.now();
      const writeResult: HuaweiSpaceHistoryWriteResult =
        await remoteStore.writePreparedProjection(projection, local);
      this.logStage(
        'write-remote',
        stageStartedAt,
        `required=1 changed=${writeResult.changedRowCount} packed=0 lite=1`
      );
      if (clearOutboxAfterSuccess) {
        await this.database.clearHistorySyncOutbox(identity.accountUid);
      }
      this.lastConfirmedAccountUid = identity.accountUid;
      this.lastConfirmedState = this.mergeService.normalize(local);
      const confirmedChecksum = remoteStore.consumeLastHeadChecksum();
      if (confirmedChecksum.length > 0) {
        await this.database.writeHuaweiHistoryRemoteHeadChecksum(identity.accountUid, confirmedChecksum);
      }
      this.logStage(
        'run-total',
        runStartedAt,
        `applied=${appliedChangeCount} uploaded=${writeResult.changedRowCount} lite=1`
      );
      return {
        ok: true,
        appliedChangeCount: appliedChangeCount,
        uploadedMutationCount: writeResult.changedRowCount,
        message: writeResult.changedRowCount > 0
          ? '历史记录已完成华为云空间增量同步。'
          : '历史记录已经是最新。'
      };
    } catch (error) {
      AiraSyncJankProbe.endExtra(
        'history_replica_lite',
        stageStartedAt,
        `error=1 dirty=${dirty.length}`
      );
      return undefined;
    }
  }

  private async runPackedReplica(
    identity: HuaweiSpaceHistorySyncIdentity,
    remoteStore: HuaweiSpaceHistoryRemoteStore,
    packedRows: ArrayBuffer,
    clearOutboxAfterSuccess: boolean,
    appliedChangeCount: number,
    runStartedAt: number
  ): Promise<HistorySyncRunResult> {
    let stageStartedAt = Date.now();
    const local = await this.database.readHuaweiSpaceHistorySyncState(identity.accountUid);
    this.logStage('read-local', stageStartedAt);
    stageStartedAt = Date.now();
    const packed: HuaweiHistoryReplicaPackedOutcome =
      await this.computeExecutor.planHuaweiHistoryReplicaPacked(
        identity.accountUid,
        identity.clientId,
        packedRows,
        local
      );
    this.logStage(
      'plan-merge',
      stageStartedAt,
      `write=${packed.remoteWriteRequired ? 1 : 0} apply=${packed.localApplyRequired ? 1 : 0} packed=1`
    );
    if (packed.errorMessage.length > 0) {
      throw new Error(packed.errorMessage);
    }
    const desired = packed.mergedBuffer.byteLength > 0
      ? AiraHistoryTaskpoolTransferCodec.decodeState(packed.mergedBuffer)
      : local;
    stageStartedAt = Date.now();
    const firstApplied = packed.localApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, desired)
      : 0;
    appliedChangeCount += firstApplied;
    this.logStage('apply-local', stageStartedAt, `applied=${firstApplied}`);
    stageStartedAt = Date.now();
    const writeResult: HuaweiSpaceHistoryWriteResult = packed.remoteWriteRequired
      ? await remoteStore.writePreparedProjection(packed.projection, desired)
      : { state: desired, changedRowCount: 0, localApplyRequired: false };
    this.logStage(
      'write-remote',
      stageStartedAt,
      `required=${packed.remoteWriteRequired ? 1 : 0} changed=${writeResult.changedRowCount} packed=1`
    );
    stageStartedAt = Date.now();
    const confirmedApplied = writeResult.localApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, writeResult.state)
      : 0;
    appliedChangeCount += confirmedApplied;
    this.logStage('apply-confirmed', stageStartedAt, `applied=${confirmedApplied}`);
    stageStartedAt = Date.now();
    const pruned = packed.localApplyRequired || writeResult.localApplyRequired
      ? await this.database.pruneHistorySyncProjection(identity.accountUid)
      : 0;
    appliedChangeCount += pruned;
    this.logStage('prune-final', stageStartedAt, `pruned=${pruned}`);
    if (clearOutboxAfterSuccess) {
      await this.database.clearHistorySyncOutbox(identity.accountUid);
    }
    this.lastConfirmedAccountUid = identity.accountUid;
    this.lastConfirmedState = this.mergeService.normalize(desired);
    const confirmedChecksum = remoteStore.consumeLastHeadChecksum();
    if (confirmedChecksum.length > 0) {
      await this.database.writeHuaweiHistoryRemoteHeadChecksum(identity.accountUid, confirmedChecksum);
    }
    this.logStage(
      'run-total',
      runStartedAt,
      `applied=${appliedChangeCount} uploaded=${writeResult.changedRowCount}`
    );
    return {
      ok: true,
      appliedChangeCount: appliedChangeCount,
      uploadedMutationCount: writeResult.changedRowCount,
      message: appliedChangeCount > 0 || writeResult.changedRowCount > 0
        ? '历史记录已完成华为云空间增量同步。'
        : '历史记录已经是最新。'
    };
  }

  private logStage(stage: string, startedAt: number, extra: string = ''): void {
    hilog.info(
      HISTORY_HUAWEI_LOG_DOMAIN,
      HISTORY_HUAWEI_LOG_TAG,
      'Huawei history stage=%{public}s durationMs=%{public}d extra=%{public}s',
      stage,
      Date.now() - startedAt,
      extra
    );
    AiraSyncJankProbe.endExtra(`history_stage_${stage}`, startedAt, extra);
  }

  private async enrollLocalVisits(identity: HuaweiSpaceHistorySyncIdentity): Promise<number> {
    let enrolledTotal = 0;
    for (let round = 0; round < HISTORY_HUAWEI_MAX_ENROLLMENT_ROUNDS; round += 1) {
      const enrolled = await this.database.prepareHistorySyncEnrollment(
        identity.accountUid,
        identity.clientId,
        identity.deviceName,
        HISTORY_HUAWEI_ENROLLMENT_BATCH_SIZE
      );
      enrolledTotal += enrolled;
      if (enrolled < HISTORY_HUAWEI_ENROLLMENT_BATCH_SIZE) {
        return enrolledTotal;
      }
    }
    throw new Error('本机历史记录初始化超过安全上限，请稍后继续同步。');
  }

}
