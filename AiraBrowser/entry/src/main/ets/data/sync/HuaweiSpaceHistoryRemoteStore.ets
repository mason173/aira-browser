import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
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
import { AiraHistoryRemoteWriteProjection } from '../../services/sync/AiraHistoryTaskpoolTransferCodec';
import { AiraSyncWorkThrottleService } from '../../services/sync/AiraSyncWorkThrottleService';
import { HuaweiSpaceCloudSyncCoordinator } from './HuaweiSpaceCloudSyncCoordinator';
import {
  HuaweiSpaceHistoryRecordKind,
  HuaweiSpaceHistoryRow,
  huaweiHistoryPhysicalTable
} from './HuaweiSpaceHistorySnapshotCodec';
import {
  HUAWEI_SPACE_HISTORY_BLOCK_TABLE,
  HUAWEI_SPACE_HISTORY_HEAD_TABLE,
  HUAWEI_SPACE_HISTORY_TABLE,
  HuaweiSpaceRdbStoreOwner
} from './HuaweiSpaceRdbStoreOwner';

const HUAWEI_SPACE_HISTORY_SYNC_TIMEOUT_MS: number = 45000;

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
    { batchSize: 16, batchPauseMs: 0, stagePauseMs: 0 }
  );
  private store?: relationalStore.RdbStore;
  private storePromise?: Promise<relationalStore.RdbStore>;
  private freshRows?: HuaweiSpaceHistoryRow[];
  private freshLegacyRowIds: string[] = [];

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
    this.assertConfigured();
    const store = await this.getStore();
    await this.runCloudSync(
      store,
      relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
      true,
      [HUAWEI_SPACE_HISTORY_HEAD_TABLE]
    );
    let rows = await this.readAllPhysicalRows(store);
    if (this.needsBlockCloudSync(rows)) {
      rows = await this.syncBlocksAndReload(store);
    }
    let decoded: AiraHistoryRemoteStateDecode;
    try {
      decoded = await this.decodeRemoteState(rows);
    } catch (error) {
      if (!this.isIncompleteHistoryError(error)) {
        throw error as Error;
      }
      rows = await this.syncBlocksAndReload(store);
      decoded = await this.decodeRemoteState(rows);
    }
    this.freshRows = rows;
    this.freshLegacyRowIds = decoded.legacyRowIds;
    return decoded.state;
  }

  requiresMaintenance(): boolean {
    return this.freshLegacyRowIds.length > 0;
  }

  async writeState(
    state: HuaweiSpaceHistorySyncState,
    skipCloudTransport: boolean = false
  ): Promise<HuaweiSpaceHistoryWriteResult> {
    this.assertConfigured();
    const store = await this.getStore();
    const currentRows = await this.consumeFreshRows(store, skipCloudTransport);
    const writePlan: AiraHistoryRemoteWritePlan =
      await this.computeExecutor.planHuaweiHistoryRemoteWrite(this.uid, this.deviceId, currentRows, state);
    const projection = writePlan.projection;
    let changedRowCount = await this.stageProjection(store, projection);
    if (changedRowCount > 0 && !skipCloudTransport) {
      await this.runIncrementalCommitBarrier(store, this.changedCloudTables(projection));
    } else if (changedRowCount > 0) {
      await this.runCloudSync(
        store,
        relationalStore.SyncMode.SYNC_MODE_TIME_FIRST,
        true,
        this.changedCloudTables(projection)
      );
    }
    let confirmedRows = await this.readAllPhysicalRows(store);
    let confirmation = await this.assertProjectionAndDesiredStateConfirmed(confirmedRows, projection, state);

    const cleanedLegacyRows = await this.deleteConfirmedLegacyRows(store, projection);
    changedRowCount += cleanedLegacyRows;
    if (cleanedLegacyRows > 0) {
      confirmedRows = await this.readAllPhysicalRows(store);
      this.assertLegacyCleanupConfirmed(confirmedRows, projection);
      confirmation = await this.assertProjectionAndDesiredStateConfirmed(confirmedRows, projection, state);
    }
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
    projection: AiraHistoryRemoteWriteProjection
  ): Promise<number> {
    const existingRows = await this.readAllPhysicalRows(store);
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

  private samePhysicalRow(left: HuaweiSpaceHistoryRow, right: HuaweiSpaceHistoryRow): boolean {
    return left.rowId === right.rowId && left.recordKind === right.recordKind &&
      left.logicalId === right.logicalId && left.data === right.data && left.updatedAt === right.updatedAt;
  }

  private async decodeRemoteState(rows: HuaweiSpaceHistoryRow[]): Promise<AiraHistoryRemoteStateDecode> {
    try {
      return await this.computeExecutor.decodeHuaweiHistoryRemoteState(this.uid, this.deviceId, rows);
    } catch (error) {
      return this.rethrowDecodeError(error);
    }
  }

  private rethrowDecodeError<T>(error: Object): T {
    if (!(error instanceof AiraHistoryMirrorDecodeError)) {
      const candidate = error as Error;
      throw candidate instanceof Error ? candidate : new Error(JSON.stringify(error));
    }
    throw new Error('华为云空间历史记录中存在无法解析的数据，已停止同步。');
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
    let headCount = 0;
    let blockCount = 0;
    rows.forEach((row: HuaweiSpaceHistoryRow): void => {
      const table = huaweiHistoryPhysicalTable(row.recordKind);
      if (table === 'head') {
        headCount += 1;
      }
      if (table === 'block') {
        blockCount += 1;
      }
    });
    return headCount > 0 && blockCount <= 0;
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
    await this.runCloudSync(store, relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST, true, tableNames);
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
