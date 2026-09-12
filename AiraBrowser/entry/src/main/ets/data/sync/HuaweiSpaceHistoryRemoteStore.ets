import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { HuaweiSpaceHistorySyncState } from '../../common/models/HistorySyncModels';
import { AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME } from '../../services/sync/AiraSyncConfigStore';
import {
  AiraHistoryMirrorDecodeError,
  AiraHistoryRemoteStateDecode,
  AiraHistoryRemoteWriteConfirmation,
  AiraHistoryRemoteWritePlan,
  AiraSyncComputeExecutor
} from '../../services/sync/AiraSyncComputeExecutor';
import {
  AiraHistoryRemoteWriteProjection,
  AiraHistoryTaskpoolTransferCodec
} from '../../services/sync/AiraHistoryTaskpoolTransferCodec';
import { AiraSyncWorkThrottleService } from '../../services/sync/AiraSyncWorkThrottleService';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';
import { HuaweiSpaceCloudSyncCoordinator } from './HuaweiSpaceCloudSyncCoordinator';
import {
  HuaweiSpaceHistoryPhysicalMirror,
  HuaweiSpaceHistoryRecordKind,
  HuaweiSpaceHistoryRow,
  HuaweiSpaceHistorySnapshotCodec,
  huaweiHistoryPhysicalTable
} from './HuaweiSpaceHistorySnapshotCodec';
import {
  HUAWEI_SPACE_HISTORY_BLOCK_TABLE,
  HUAWEI_SPACE_HISTORY_HEAD_TABLE,
  HUAWEI_SPACE_HISTORY_TABLE,
  HuaweiSpaceRdbStoreOwner
} from './HuaweiSpaceRdbStoreOwner';

interface HuaweiSpaceHistoryHeadChecksum {
  deviceId: string;
  generation: number;
  stateChecksum: string;
}

const HUAWEI_SPACE_HISTORY_SYNC_TIMEOUT_MS: number = 45000;
const HUAWEI_HISTORY_LOG_DOMAIN: number = 0x0000;
const HUAWEI_HISTORY_LOG_TAG: string = 'HuaweiHistorySync';

export interface HuaweiSpaceHistoryWriteResult {
  state: HuaweiSpaceHistorySyncState;
  changedRowCount: number;
  localApplyRequired: boolean;
}

export class HuaweiSpaceHistoryRemoteStore {
  private readonly uid: string;
  private readonly deviceId: string;
  private readonly databaseName: string;
  private readonly context?: common.ApplicationContext | common.UIAbilityContext;
  private readonly computeExecutor: AiraSyncComputeExecutor = new AiraSyncComputeExecutor();
  private readonly rowReadThrottle: AiraSyncWorkThrottleService = new AiraSyncWorkThrottleService(
    undefined,
    { batchSize: 100000, batchPauseMs: 16, stagePauseMs: 16 }
  );
  private store?: relationalStore.RdbStore;
  private storePromise?: Promise<relationalStore.RdbStore>;
  private freshRows?: HuaweiSpaceHistoryRow[];
  private freshLegacyRowIds: string[] = [];
  private lastMirror?: HuaweiSpaceHistoryPhysicalMirror;
  private lastHeadChecksum: string = '';
  private peekedHeadRows?: HuaweiSpaceHistoryRow[];
  private lastPackedRows?: ArrayBuffer;

  constructor(
    uid: string,
    deviceId: string,
    databaseName: string = AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME,
    context?: common.ApplicationContext | common.UIAbilityContext
  ) {
    this.uid = uid.trim();
    this.deviceId = deviceId.trim();
    this.databaseName = databaseName.trim().length > 0
      ? databaseName.trim()
      : AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME;
    this.context = context;
  }

  async readState(): Promise<HuaweiSpaceHistorySyncState> {
    const state = await this.readStateUnlessHeadMatches('');
    if (state === undefined) {
      throw new Error('华为云空间历史记录读取失败。');
    }
    return state;
  }

  consumeLastHeadChecksum(): string {
    return this.lastHeadChecksum.trim();
  }

  async peekHeadChecksum(): Promise<string> {
    this.assertConfigured();
    const store = await this.getStore();
    const stageStartedAt = Date.now();
    await this.runCloudSync(
      store,
      relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
      true,
      [HUAWEI_SPACE_HISTORY_HEAD_TABLE]
    );
    this.logStage('read-cloud-heads', stageStartedAt);
    const headStartedAt = Date.now();
    this.peekedHeadRows = await this.readRawRows(store, HUAWEI_SPACE_HISTORY_HEAD_TABLE);
    this.lastHeadChecksum = this.extractHeadChecksum(this.peekedHeadRows);
    this.logStage(
      'read-head-checksum',
      headStartedAt,
      `checksum=${this.lastHeadChecksum.length > 0 ? 1 : 0}`
    );
    return this.lastHeadChecksum;
  }

  async tryReadLocalReplicaMatchingHead(
    expectedChecksum: string
  ): Promise<HuaweiSpaceHistorySyncState | undefined> {
    const expected = expectedChecksum.trim();
    if (expected.length <= 0) {
      return undefined;
    }
    this.assertConfigured();
    const store = await this.getStore();
    const headRows = this.peekedHeadRows ?? await this.readRawRows(store, HUAWEI_SPACE_HISTORY_HEAD_TABLE);
    const rows = headRows.concat(await this.readRawRows(store, HUAWEI_SPACE_HISTORY_BLOCK_TABLE));
    if (this.needsBlockCloudSync(rows) || this.extractHeadChecksum(rows) !== expected) {
      return undefined;
    }
    try {
      const decoded = await this.decodeRemoteState(rows);
      this.freshRows = rows;
      this.freshLegacyRowIds = decoded.legacyRowIds;
      return decoded.state;
    } catch (_error) {
      this.lastMirror = undefined;
      this.freshRows = undefined;
      this.freshLegacyRowIds = [];
      return undefined;
    }
  }

  async readCloudBlocksAndDecode(): Promise<HuaweiSpaceHistorySyncState> {
    this.assertConfigured();
    const store = await this.getStore();
    const stageStartedAt = Date.now();
    const rows = await this.syncBlocksAndReload(store);
    this.logStage('read-cloud-blocks', stageStartedAt, `rows=${rows.length}`);
    const decoded = await this.decodeRemoteState(rows);
    this.freshRows = rows;
    this.freshLegacyRowIds = decoded.legacyRowIds;
    this.peekedHeadRows = undefined;
    this.lastHeadChecksum = this.extractHeadChecksum(rows);
    return decoded.state;
  }

  async readStateUnlessHeadMatches(knownChecksum: string): Promise<HuaweiSpaceHistorySyncState | undefined> {
    const peekedChecksum = await this.peekHeadChecksum();
    const expected = knownChecksum.trim();
    if (expected.length > 0 && peekedChecksum === expected) {
      this.logStage('read-head-unchanged', Date.now(), 'skip=1');
      return undefined;
    }
    const replica = await this.tryReadLocalReplicaMatchingHead(peekedChecksum);
    if (replica !== undefined) {
      return replica;
    }
    return this.readCloudBlocksAndDecode();
  }


  async preparePackedReplicaRows(): Promise<boolean> {
    this.assertConfigured();
    const store = await this.getStore();
    const headRows = this.peekedHeadRows ?? await this.readRawRows(store, HUAWEI_SPACE_HISTORY_HEAD_TABLE);
    let rows = headRows.concat(await this.readRawRows(store, HUAWEI_SPACE_HISTORY_BLOCK_TABLE));
    if (this.needsOwnHeadComplete(rows)) {
      const repairStartedAt = Date.now();
      await this.runCloudSync(
        store,
        relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
        true,
        [HUAWEI_SPACE_HISTORY_BLOCK_TABLE]
      );
      const repairedHeads = await this.readRawRows(store, HUAWEI_SPACE_HISTORY_HEAD_TABLE);
      rows = repairedHeads.concat(await this.readRawRows(store, HUAWEI_SPACE_HISTORY_BLOCK_TABLE));
      const stillIncomplete = this.needsOwnHeadComplete(rows);
      this.logStage('replica-repair', repairStartedAt, `complete=${stillIncomplete ? 0 : 1}`);
      if (stillIncomplete) {
        return false;
      }
    } else if (this.needsBlockCloudSync(rows)) {
      AiraSyncJankProbe.markExtra(
        'history_replica_partial',
        `scope=self ownHeadComplete=1 otherDevicesIncomplete=1 rows=${rows.length}`
      );
    }
    const packStartedAt = Date.now();
    const packed = AiraHistoryTaskpoolTransferCodec.encodeRows(rows);
    AiraSyncJankProbe.endExtra(
      'history_row_pack',
      packStartedAt,
      `bytes=${packed.byteLength} rows=${rows.length}`
    );
    this.freshRows = rows;
    this.lastPackedRows = packed;
    return true;
  }

  takePackedReplicaRows(): ArrayBuffer | undefined {
    const packed = this.lastPackedRows;
    this.lastPackedRows = undefined;
    return packed;
  }

  repackFreshReplicaRows(): ArrayBuffer | undefined {
    const rows = this.freshRows;
    if (rows === undefined) {
      return undefined;
    }
    const packed = AiraHistoryTaskpoolTransferCodec.encodeRows(rows);
    this.lastPackedRows = packed;
    return packed;
  }

  peekFreshReplicaRows(): HuaweiSpaceHistoryRow[] | undefined {
    return this.freshRows;
  }

  async writePreparedProjection(
    projection: AiraHistoryRemoteWriteProjection,
    desired: HuaweiSpaceHistorySyncState
  ): Promise<HuaweiSpaceHistoryWriteResult> {
    this.assertConfigured();
    const store = await this.getStore();
    let changedRowCount = await this.stageProjection(store, projection);
    if (changedRowCount > 0) {
      await this.runIncrementalCommitBarrier(store, this.changedCloudTables(projection));
    }
    let confirmedRows = await this.readAllPhysicalRows(store);
    let confirmation = await this.assertProjectionAndDesiredStateConfirmed(confirmedRows, projection, desired);
    const cleanedLegacyRows = await this.deleteConfirmedLegacyRows(store, projection);
    changedRowCount += cleanedLegacyRows;
    if (cleanedLegacyRows > 0) {
      confirmedRows = await this.readAllPhysicalRows(store);
      this.assertLegacyCleanupConfirmed(confirmedRows, projection);
      confirmation = await this.assertProjectionAndDesiredStateConfirmed(confirmedRows, projection, desired);
    }
    this.lastHeadChecksum = this.extractHeadChecksum(confirmedRows);
    return {
      state: confirmation.confirmed,
      changedRowCount,
      localApplyRequired: confirmation.localApplyRequired
    };
  }

  requiresMaintenance(): boolean {
    return this.freshLegacyRowIds.length > 0;
  }

  async readLocalReplicaState(): Promise<HuaweiSpaceHistorySyncState> {
    this.assertConfigured();
    const store = await this.getStore();
    const rows = await this.readAllPhysicalRows(store);
    if (rows.length <= 0) {
      throw new Error('Huawei History local replica is empty.');
    }
    const decoded = await this.decodeRemoteState(rows);
    this.freshRows = rows;
    this.freshLegacyRowIds = decoded.legacyRowIds;
    return decoded.state;
  }

  async writeState(
    state: HuaweiSpaceHistorySyncState,
    skipCloudTransport: boolean = false
  ): Promise<HuaweiSpaceHistoryWriteResult> {
    this.assertConfigured();
    const store = await this.getStore();
    let stageStartedAt = Date.now();
    const canReuseMirror = this.lastMirror !== undefined && this.freshRows !== undefined;
    const currentRows = await this.consumeFreshRows(store, skipCloudTransport);
    this.logStage('write-load-rows', stageStartedAt, `rows=${currentRows.length} skipCloud=${skipCloudTransport ? 1 : 0}`);
    stageStartedAt = Date.now();
    const packedRows = this.lastPackedRows;
    this.lastPackedRows = undefined;
    const writePlan: AiraHistoryRemoteWritePlan = canReuseMirror && this.lastMirror !== undefined
      ? this.planWriteFromMirror(this.lastMirror, state)
      : await this.computeExecutor.planHuaweiHistoryRemoteWrite(
        this.uid,
        this.deviceId,
        currentRows,
        state,
        packedRows
      );
    const projection = writePlan.projection;
    this.logStage(
      'write-plan',
      stageStartedAt,
      `upsert=${projection.rowsToUpsert.length} delete=${projection.rowIdsToDeleteBeforePublish.length}` +
        ` reused=${canReuseMirror ? 1 : 0}`
    );
    stageStartedAt = Date.now();
    let changedRowCount = await this.stageProjection(store, projection, currentRows);
    this.logStage('write-stage', stageStartedAt, `changed=${changedRowCount}`);
    if (changedRowCount > 0 && !skipCloudTransport) {
      stageStartedAt = Date.now();
      await this.runIncrementalCommitBarrier(store, this.changedCloudTables(projection));
      this.logStage('write-barrier', stageStartedAt, 'mode=time+cloud');
    } else if (changedRowCount > 0) {
      stageStartedAt = Date.now();
      await this.runCloudSync(
        store,
        relationalStore.SyncMode.SYNC_MODE_TIME_FIRST,
        true,
        this.changedCloudTables(projection)
      );
      this.logStage('write-barrier', stageStartedAt, 'mode=time-only');
    }
    stageStartedAt = Date.now();
    let confirmedRows = await this.readAllPhysicalRows(store);
    this.logStage('write-reload', stageStartedAt, `rows=${confirmedRows.length}`);
    stageStartedAt = Date.now();
    let confirmation = await this.assertProjectionAndDesiredStateConfirmed(confirmedRows, projection, state);
    this.logStage('write-confirm', stageStartedAt, `ok=${confirmation.projectionConfirmed ? 1 : 0}`);

    const cleanedLegacyRows = await this.deleteConfirmedLegacyRows(store, projection);
    changedRowCount += cleanedLegacyRows;
    if (cleanedLegacyRows > 0) {
      confirmedRows = await this.readAllPhysicalRows(store);
      this.assertLegacyCleanupConfirmed(confirmedRows, projection);
      confirmation = await this.assertProjectionAndDesiredStateConfirmed(confirmedRows, projection, state);
    }
    this.lastHeadChecksum = this.extractHeadChecksum(confirmedRows);
    return {
      state: confirmation.confirmed,
      changedRowCount,
      localApplyRequired: confirmation.localApplyRequired
    };
  }

  private async consumeFreshRows(
    store: relationalStore.RdbStore,
    skipCloudTransport: boolean = false
  ): Promise<HuaweiSpaceHistoryRow[]> {
    const rows = this.freshRows;
    this.freshRows = undefined;
    this.freshLegacyRowIds = [];
    if (rows !== undefined) {
      return rows;
    }
    if (!skipCloudTransport) {
      await this.runCloudSync(
        store,
        relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
        true,
        [HUAWEI_SPACE_HISTORY_HEAD_TABLE]
      );
      let loaded = await this.readAllPhysicalRows(store);
      if (this.needsBlockCloudSync(loaded)) {
        await this.runCloudSync(
          store,
          relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
          true,
          [HUAWEI_SPACE_HISTORY_BLOCK_TABLE]
        );
        loaded = await this.readAllPhysicalRows(store);
      }
      return loaded;
    }
    return this.readAllPhysicalRows(store);
  }

  private async assertProjectionAndDesiredStateConfirmed(
    confirmedRows: HuaweiSpaceHistoryRow[],
    projection: AiraHistoryRemoteWriteProjection,
    desired: HuaweiSpaceHistorySyncState
  ): Promise<AiraHistoryRemoteWriteConfirmation> {
    if (this.isHeadChecksumConfirmed(confirmedRows, projection)) {
      return {
        confirmed: desired,
        projectionConfirmed: true,
        desiredStateConfirmed: true,
        localApplyRequired: false
      };
    }
    const confirmation = await this.computeExecutor.confirmHuaweiHistoryRemoteWrite(
        this.uid,
        this.deviceId,
        confirmedRows,
        projection,
        desired
      );
    if (!confirmation.projectionConfirmed) {
      throw new Error('华为云空间历史记录紧凑快照尚未完整确认，请稍后重试。');
    }
    if (!confirmation.desiredStateConfirmed) {
      throw new Error('华为云空间历史记录写入后未能完整确认，请稍后重试。');
    }
    return confirmation;
  }

  private async stageProjection(
    store: relationalStore.RdbStore,
    projection: AiraHistoryRemoteWriteProjection,
    knownRows?: HuaweiSpaceHistoryRow[]
  ): Promise<number> {
    const existingRows = knownRows ?? await this.readAllPhysicalRows(store);
    const existingById = new Map<string, HuaweiSpaceHistoryRow>();
    existingRows.forEach((row: HuaweiSpaceHistoryRow): void => {
      existingById.set(row.rowId, row);
    });
    let changed = 0;
    let transactionStarted = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      for (const row of projection.rowsToUpsert) {
        const existing = existingById.get(row.rowId);
        if (existing !== undefined && this.samePhysicalRow(existing, row)) {
          continue;
        }
        await store.insert(
          this.tableNameForKind(row.recordKind),
          {
            rowId: row.rowId,
            accountUid: this.uid,
            recordKind: row.recordKind,
            logicalId: row.logicalId,
            data: row.data,
            updatedAt: row.updatedAt
          },
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
        );
        changed += 1;
      }
      for (const rowId of projection.rowIdsToDeleteBeforePublish) {
        changed += await this.deletePhysicalRow(store, rowId);
      }
      store.commit();
      transactionStarted = false;
      return changed;
    } catch (error) {
      if (transactionStarted) {
        try {
          store.rollBack();
        } catch (_rollbackError) {
        }
      }
      const candidate = error as Error;
      throw new Error(`写入华为云空间历史记录失败：${candidate.message ?? JSON.stringify(error)}`);
    }
  }

  private async deleteConfirmedLegacyRows(
    store: relationalStore.RdbStore,
    projection: AiraHistoryRemoteWriteProjection
  ): Promise<number> {
    if (projection.legacyRowIdsToDeleteAfterConfirmation.length <= 0) {
      return 0;
    }
    let deleted = 0;
    let transactionStarted = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      for (const rowId of projection.legacyRowIdsToDeleteAfterConfirmation) {
        deleted += await this.deletePhysicalRow(store, rowId);
      }
      store.commit();
      transactionStarted = false;
      return deleted;
    } catch (error) {
      if (transactionStarted) {
        try {
          store.rollBack();
        } catch (_rollbackError) {
        }
      }
      const candidate = error as Error;
      throw new Error(`清理已迁移的华为云空间历史记录失败：${candidate.message ?? JSON.stringify(error)}`);
    }
  }

  private async deletePhysicalRow(store: relationalStore.RdbStore, rowId: string): Promise<number> {
    const tables: string[] = [
      HUAWEI_SPACE_HISTORY_HEAD_TABLE,
      HUAWEI_SPACE_HISTORY_BLOCK_TABLE,
      HUAWEI_SPACE_HISTORY_TABLE
    ];
    let deleted = 0;
    for (const tableName of tables) {
      const predicates = new relationalStore.RdbPredicates(tableName);
      predicates.equalTo('accountUid', this.uid);
      predicates.equalTo('rowId', rowId);
      deleted += await store.delete(predicates);
    }
    return deleted;
  }

  private assertLegacyCleanupConfirmed(
    rows: HuaweiSpaceHistoryRow[],
    projection: AiraHistoryRemoteWriteProjection
  ): void {
    const remainingIds = new Set<string>();
    rows.forEach((row: HuaweiSpaceHistoryRow): void => {
      remainingIds.add(row.rowId);
    });
    if (projection.legacyRowIdsToDeleteAfterConfirmation.some((rowId: string): boolean => {
      return remainingIds.has(rowId);
    })) {
      throw new Error('华为云空间历史记录旧格式清理尚未完整确认，请稍后重试。');
    }
  }

  private extractHeadChecksum(rows: HuaweiSpaceHistoryRow[]): string {
    let bestChecksum = '';
    let bestUpdatedAt = -1;
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      if (row.recordKind !== 'snapshot_head') {
        continue;
      }
      try {
        const parsed = JSON.parse(row.data) as HuaweiSpaceHistoryHeadChecksum;
        const checksum = parsed.stateChecksum.trim();
        if (checksum.length > 0 && row.updatedAt >= bestUpdatedAt) {
          bestUpdatedAt = row.updatedAt;
          bestChecksum = checksum;
        }
      } catch (_error) {
      }
    }
    return bestChecksum;
  }

  private isHeadChecksumConfirmed(
    rows: HuaweiSpaceHistoryRow[],
    projection: AiraHistoryRemoteWriteProjection
  ): boolean {
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      if (row.rowId !== projection.targetHeadRowId || row.recordKind !== 'snapshot_head') {
        continue;
      }
      try {
        const parsed = JSON.parse(row.data) as HuaweiSpaceHistoryHeadChecksum;
        return parsed.generation === projection.targetGeneration &&
          parsed.stateChecksum === projection.targetStateChecksum &&
          parsed.deviceId === projection.targetDeviceId;
      } catch (_error) {
        return false;
      }
    }
    return false;
  }

  private logStage(stage: string, startedAt: number, extra: string = ''): void {
    hilog.info(
      HUAWEI_HISTORY_LOG_DOMAIN,
      HUAWEI_HISTORY_LOG_TAG,
      'Huawei history stage=%{public}s durationMs=%{public}d extra=%{public}s',
      stage,
      Date.now() - startedAt,
      extra
    );
  }

  private samePhysicalRow(left: HuaweiSpaceHistoryRow, right: HuaweiSpaceHistoryRow): boolean {
    return left.rowId === right.rowId && left.recordKind === right.recordKind &&
      left.logicalId === right.logicalId && left.data === right.data && left.updatedAt === right.updatedAt;
  }

  private async decodeRemoteState(rows: HuaweiSpaceHistoryRow[]): Promise<AiraHistoryRemoteStateDecode> {
    const startedAt = Date.now();
    try {
      const packStartedAt = Date.now();
      const packed = AiraHistoryTaskpoolTransferCodec.encodeRows(rows);
      AiraSyncJankProbe.endExtra(
        'history_row_pack',
        packStartedAt,
        `bytes=${packed.byteLength} rows=${rows.length}`
      );
      this.lastPackedRows = AiraHistoryTaskpoolTransferCodec.copyBuffer(packed);
      const decoded = await this.computeExecutor.decodePackedHuaweiHistoryRemoteState(
        this.uid,
        this.deviceId,
        packed
      );
      this.lastMirror = undefined;
      AiraSyncJankProbe.endExtra('history_decode', startedAt, `rows=${rows.length} taskpool=1`);
      return decoded;
    } catch (error) {
      this.lastMirror = undefined;
      this.lastPackedRows = undefined;
      AiraSyncJankProbe.endExtra('history_decode', startedAt, `rows=${rows.length} taskpool=0`);
      return this.rethrowDecodeError(error);
    }
  }

  private planWriteFromMirror(
    mirror: HuaweiSpaceHistoryPhysicalMirror,
    desired: HuaweiSpaceHistorySyncState
  ): AiraHistoryRemoteWritePlan {
    const codec = new HuaweiSpaceHistorySnapshotCodec(this.uid, this.deviceId);
    return {
      projection: AiraHistoryTaskpoolTransferCodec.leanProjection(codec.buildProjection(desired, mirror))
    };
  }

  private rethrowDecodeError<T>(error: Object): T {
    if (!(error instanceof AiraHistoryMirrorDecodeError)) {
      const candidate = error as Error;
      throw candidate instanceof Error ? candidate : new Error(JSON.stringify(error));
    }
    this.logStage('decode-failed', Date.now(), `reason=${error.message}`);
    throw new Error('华为云空间历史记录快照不一致，已停止同步，请稍后重试。');
  }

  private async syncBlocksAndReload(store: relationalStore.RdbStore): Promise<HuaweiSpaceHistoryRow[]> {
    await this.runCloudSync(
      store,
      relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
      true,
      [HUAWEI_SPACE_HISTORY_BLOCK_TABLE]
    );
    return this.readAllPhysicalRows(store);
  }

  private isIncompleteHistoryError(error: Object): boolean {
    const message = error instanceof Error ? error.message : JSON.stringify(error);
    return message.indexOf('incomplete') >= 0;
  }

  private needsBlockCloudSync(rows: HuaweiSpaceHistoryRow[]): boolean {
    if (rows.length <= 0) {
      return false;
    }
    return new HuaweiSpaceHistorySnapshotCodec(this.uid, this.deviceId).needsBlockCloudSync(rows);
  }

  private needsOwnHeadComplete(rows: HuaweiSpaceHistoryRow[]): boolean {
    if (rows.length <= 0) {
      return true;
    }
    return new HuaweiSpaceHistorySnapshotCodec(this.uid, this.deviceId)
      .needsBlockCloudSync(rows, this.deviceId);
  }

  private changedCloudTables(projection: AiraHistoryRemoteWriteProjection): string[] {
    const tables: string[] = [];
    let hasBlocks = false;
    let hasHeads = false;
    projection.rowsToUpsert.forEach((row: HuaweiSpaceHistoryRow): void => {
      const table = huaweiHistoryPhysicalTable(row.recordKind);
      if (table === 'block') {
        hasBlocks = true;
      }
      if (table === 'head') {
        hasHeads = true;
      }
    });
    if (projection.rowIdsToDeleteBeforePublish.length > 0) {
      hasBlocks = true;
    }
    if (hasBlocks) {
      tables.push(HUAWEI_SPACE_HISTORY_BLOCK_TABLE);
    }
    if (hasHeads) {
      tables.push(HUAWEI_SPACE_HISTORY_HEAD_TABLE);
    }
    return tables;
  }

  private tableNameForKind(recordKind: HuaweiSpaceHistoryRecordKind): string {
    const table = huaweiHistoryPhysicalTable(recordKind);
    if (table === 'head') {
      return HUAWEI_SPACE_HISTORY_HEAD_TABLE;
    }
    if (table === 'block') {
      return HUAWEI_SPACE_HISTORY_BLOCK_TABLE;
    }
    return HUAWEI_SPACE_HISTORY_TABLE;
  }

  private async readAllPhysicalRows(store: relationalStore.RdbStore): Promise<HuaweiSpaceHistoryRow[]> {
    const heads = await this.readRawRows(store, HUAWEI_SPACE_HISTORY_HEAD_TABLE);
    const blocks = await this.readRawRows(store, HUAWEI_SPACE_HISTORY_BLOCK_TABLE);
    return heads.concat(blocks);
  }

  private async readRawRows(
    store: relationalStore.RdbStore,
    tableName: string = HUAWEI_SPACE_HISTORY_HEAD_TABLE
  ): Promise<HuaweiSpaceHistoryRow[]> {
    const predicates = new relationalStore.RdbPredicates(tableName);
    predicates.equalTo('accountUid', this.uid);
    const resultSet = await store.queryWithoutRowCount(predicates, [
      'rowId',
      'recordKind',
      'logicalId',
      'data',
      'updatedAt'
    ]);
    const rows: HuaweiSpaceHistoryRow[] = [];
    try {
      const rowIdIndex = resultSet.getColumnIndex('rowId');
      const recordKindIndex = resultSet.getColumnIndex('recordKind');
      const logicalIdIndex = resultSet.getColumnIndex('logicalId');
      const dataIndex = resultSet.getColumnIndex('data');
      const updatedAtIndex = resultSet.getColumnIndex('updatedAt');
      const readStartedAt = Date.now();
      while (resultSet.goToNextRow()) {
        const row: HuaweiSpaceHistoryRow = {
          rowId: resultSet.getString(rowIdIndex).trim(),
          recordKind: resultSet.getString(recordKindIndex) as HuaweiSpaceHistoryRecordKind,
          logicalId: resultSet.getString(logicalIdIndex).trim(),
          data: resultSet.getString(dataIndex),
          updatedAt: resultSet.getLong(updatedAtIndex)
        };
        rows.push(row);
        await this.rowReadThrottle.afterBatchItem(rows.length);
      }
      this.logStage('read-rows', readStartedAt, `table=${tableName} rows=${rows.length}`);
    } finally {
      resultSet.close();
    }
    return rows;
  }

  private async runIncrementalCommitBarrier(
    store: relationalStore.RdbStore,
    tableNames: string[]
  ): Promise<void> {
    if (tableNames.length <= 0) {
      return;
    }
    await this.runCloudSync(store, relationalStore.SyncMode.SYNC_MODE_TIME_FIRST, true, tableNames);
    const headTables: string[] = [];
    for (let index = 0; index < tableNames.length; index += 1) {
      if (tableNames[index] === HUAWEI_SPACE_HISTORY_HEAD_TABLE) {
        headTables.push(tableNames[index]);
      }
    }
    if (headTables.length > 0) {
      await this.runCloudSync(store, relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST, true, headTables);
    }
  }

  private runCloudSync(
    store: relationalStore.RdbStore,
    syncMode: relationalStore.SyncMode,
    requireFreshTask: boolean,
    tableNames: string[]
  ): Promise<void> {
    return HuaweiSpaceCloudSyncCoordinator.run({
      uid: this.uid,
      databaseName: this.databaseName,
      store,
      tableNames: tableNames,
      syncMode,
      timeoutMs: HUAWEI_SPACE_HISTORY_SYNC_TIMEOUT_MS,
      requireFreshTask,
      buildTimeoutError: (): Error => new Error('华为云空间历史记录同步确认超时，请稍后重试。'),
      buildProgressError: (progressCode: number): Error => this.buildProgressError(progressCode),
      buildCompletionError: (error: BusinessError): Error => {
        return new Error(`华为云空间历史记录同步失败：${error.message}`);
      },
      buildInvocationError: (error: Object): Error => {
        const message = error instanceof Error ? error.message : JSON.stringify(error);
        return new Error(`华为云空间历史记录同步失败：${message}`);
      }
    });
  }

  private buildProgressError(progressCode: number): Error {
    if (progressCode === relationalStore.ProgressCode.CLOUD_DISABLED) {
      return new Error('华为云空间历史记录同步不可用，请确认系统云空间同步已开启。');
    }
    if (progressCode === relationalStore.ProgressCode.NETWORK_ERROR) {
      return new Error('华为云空间历史记录同步网络不可用。');
    }
    if (progressCode === relationalStore.ProgressCode.LOCKED_BY_OTHERS) {
      return new Error('华为云空间历史记录同步正在被其他任务占用，请稍后重试。');
    }
    if (progressCode === relationalStore.ProgressCode.RECORD_LIMIT_EXCEEDED) {
      return new Error('华为云空间历史记录数量超过平台限制。');
    }
    if (progressCode === relationalStore.ProgressCode.NO_SPACE_FOR_ASSET) {
      return new Error('华为云空间容量不足。');
    }
    if (progressCode === relationalStore.ProgressCode.BLOCKED_BY_NETWORK_STRATEGY) {
      return new Error('华为云空间历史记录同步被系统网络策略阻止。');
    }
    return new Error(`华为云空间历史记录同步未完成（进度码 ${progressCode}）。`);
  }

  private async getStore(): Promise<relationalStore.RdbStore> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = HuaweiSpaceRdbStoreOwner.getStore(this.resolveContext(), this.databaseName)
        .then((store: relationalStore.RdbStore): relationalStore.RdbStore => {
          this.store = store;
          return store;
        })
        .catch((error: Error) => {
          this.storePromise = undefined;
          throw error;
        });
    }
    return this.storePromise;
  }

  private resolveContext(): common.ApplicationContext | common.UIAbilityContext {
    if (this.context !== undefined) {
      return this.context;
    }
    if (AppRuntimeContext.hasUIAbilityContext()) {
      return AppRuntimeContext.getUIAbilityContext();
    }
    return AppRuntimeContext.getApplicationContext();
  }

  private assertConfigured(): void {
    if (this.uid.length <= 0 || this.deviceId.length <= 0) {
      throw new Error('请先使用华为账号开启华为云空间历史记录同步。');
    }
  }
}
