import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME } from '../../services/sync/AiraSyncConfigStore';
import { HuaweiSpaceCloudSyncCoordinator } from './HuaweiSpaceCloudSyncCoordinator';
import { HuaweiSpaceRdbStoreOwner } from './HuaweiSpaceRdbStoreOwner';
import { HuaweiSpaceSnapshotBlobCodec } from './HuaweiSpaceSnapshotBlobCodec';

const HUAWEI_SPACE_CONDITIONAL_SNAPSHOT_TIMEOUT_MS: number = 30000;
const HUAWEI_SPACE_CONDITIONAL_SNAPSHOT_LOG_DOMAIN: number = 0x0000;
const HUAWEI_SPACE_CONDITIONAL_SNAPSHOT_DELETE_BATCH_SIZE: number = 100;

interface HuaweiSpaceSnapshotCommitRow<T extends Object> {
  commitId: string;
  parentCommitIds: string[];
  snapshot: T;
  updatedAt: number;
}

interface HuaweiSpaceSnapshotAggregate<T extends Object> {
  snapshot: T | null;
  revision: string;
  headCommitIds: string[];
  headSnapshots: T[];
  ancestorCommitIds: string[];
}

export interface HuaweiSpaceConditionalSnapshotOptions<T extends Object> {
  tableName: string;
  operationLabel: string;
  logTag: string;
  writeConflictError: string;
  parse: (snapshotJson: string) => T;
}

export interface HuaweiSpaceConditionalSnapshotRemoteState<T extends Object> {
  snapshot: T | null;
  revision: string;
  headSnapshots: T[];
}

export class HuaweiSpaceConditionalSnapshotStore<T extends Object> {
  private uid: string;
  private databaseName: string;
  private context?: common.ApplicationContext | common.UIAbilityContext;
  private store?: relationalStore.RdbStore;
  private storePromise?: Promise<relationalStore.RdbStore>;
  private snapshotBlobCodec: HuaweiSpaceSnapshotBlobCodec = new HuaweiSpaceSnapshotBlobCodec();
  private options: HuaweiSpaceConditionalSnapshotOptions<T>;

  constructor(
    uid: string,
    options: HuaweiSpaceConditionalSnapshotOptions<T>,
    databaseName: string = AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME,
    context?: common.ApplicationContext | common.UIAbilityContext
  ) {
    this.uid = uid.trim();
    this.options = options;
    this.databaseName = databaseName.trim().length > 0
      ? databaseName.trim()
      : AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME;
    this.context = context;
  }

  async readState(): Promise<HuaweiSpaceConditionalSnapshotRemoteState<T>> {
    this.assertConfigured();
    const store = await this.getStore();
    await this.runManualCloudSync(
      store,
      false,
      relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST
    );
    let aggregate = await this.readAggregate(store);
    aggregate = await this.compactObservedAncestorsBestEffort(store, aggregate);
    return {
      snapshot: aggregate.snapshot,
      revision: aggregate.revision,
      headSnapshots: aggregate.headSnapshots
    };
  }

  async writeSnapshot(
    deviceId: string,
    snapshot: T,
    expectedRevision: string
  ): Promise<string> {
    this.assertConfigured();
    const store = await this.getStore();
    await this.runManualCloudSync(store);
    const current = await this.readAggregate(store);
    if (current.revision !== expectedRevision.trim()) {
      throw new Error(this.options.writeConflictError);
    }
    const updatedAt = Date.now();
    const commitId = this.buildCommitId(deviceId, snapshot, updatedAt);
    const snapshotJson = JSON.stringify(snapshot);
    const snapshotBlob = await this.snapshotBlobCodec.encodeJson(snapshotJson);
    try {
      await store.insert(
        this.options.tableName,
        {
          rowId: `${this.uid}|${commitId}`,
          accountUid: this.uid,
          commitId: commitId,
          parentCommitIdsJson: JSON.stringify(current.headCommitIds),
          snapshotJson: snapshotBlob,
          deviceId: deviceId,
          updatedAt: updatedAt
        },
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
    } catch (_error) {
      hilog.warn(
        HUAWEI_SPACE_CONDITIONAL_SNAPSHOT_LOG_DOMAIN,
        this.options.logTag,
        'write local insert conflict uid=%{public}s commit=%{public}s',
        this.maskValue(this.uid),
        this.maskValue(commitId)
      );
      throw new Error(this.options.writeConflictError);
    }
    await this.runManualCloudSync(store, true);
    await this.confirmAndCompactAncestors(store, commitId);
    return commitId;
  }

  private async readAggregate(store: relationalStore.RdbStore): Promise<HuaweiSpaceSnapshotAggregate<T>> {
    const rows = await this.readCommitRows(store);
    if (rows.length <= 0) {
      return {
        snapshot: null,
        revision: '',
        headCommitIds: [],
        headSnapshots: [],
        ancestorCommitIds: []
      };
    }
    const referenced = new Set<string>();
    rows.forEach((row: HuaweiSpaceSnapshotCommitRow<T>) => {
      row.parentCommitIds.forEach((commitId: string) => referenced.add(commitId));
    });
    let heads = rows.filter((row: HuaweiSpaceSnapshotCommitRow<T>) => !referenced.has(row.commitId));
    const hasNaturalHead = heads.length > 0;
    if (heads.length <= 0) {
      heads = [rows[rows.length - 1]];
    }
    heads.sort((left: HuaweiSpaceSnapshotCommitRow<T>, right: HuaweiSpaceSnapshotCommitRow<T>) => {
      if (left.updatedAt !== right.updatedAt) {
        return left.updatedAt - right.updatedAt;
      }
      return left.commitId.localeCompare(right.commitId);
    });
    const headCommitIds: string[] = heads
      .map((row: HuaweiSpaceSnapshotCommitRow<T>): string => row.commitId)
      .sort();
    const headSnapshots: T[] = heads.map((row: HuaweiSpaceSnapshotCommitRow<T>): T => row.snapshot);
    const headCommitIdSet = new Set<string>(headCommitIds);
    return {
      snapshot: headSnapshots[headSnapshots.length - 1],
      revision: headCommitIds.length === 1 ? headCommitIds[0] : `heads:${headCommitIds.join(',')}`,
      headCommitIds,
      headSnapshots,
      ancestorCommitIds: hasNaturalHead
        ? rows
          .map((row: HuaweiSpaceSnapshotCommitRow<T>): string => row.commitId)
          .filter((candidate: string): boolean => !headCommitIdSet.has(candidate))
        : []
    };
  }

  private async confirmAndCompactAncestors(
    store: relationalStore.RdbStore,
    commitId: string
  ): Promise<void> {
    await this.runManualCloudSync(
      store,
      true,
      relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST
    );
    const confirmed = await this.readAggregate(store);
    if (!await this.hasCommit(store, commitId)) {
      throw new Error(this.options.writeConflictError);
    }
    await this.compactObservedAncestorsBestEffort(store, confirmed, commitId);
  }

  private async compactObservedAncestorsBestEffort(
    store: relationalStore.RdbStore,
    aggregate: HuaweiSpaceSnapshotAggregate<T>,
    protectedCommitId: string = ''
  ): Promise<HuaweiSpaceSnapshotAggregate<T>> {
    try {
      return await this.compactObservedAncestors(store, aggregate, protectedCommitId);
    } catch (error) {
      const candidate = error as Error;
      hilog.warn(
        HUAWEI_SPACE_CONDITIONAL_SNAPSHOT_LOG_DOMAIN,
        this.options.logTag,
        'snapshot ancestor maintenance deferred table=%{public}s message=%{public}s',
        this.options.tableName,
        candidate.message ?? JSON.stringify(error)
      );
      try {
        await this.runManualCloudSync(
          store,
          true,
          relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST
        );
        const recovered = await this.readAggregate(store);
        if (aggregate.snapshot === null || recovered.snapshot !== null) {
          return recovered;
        }
      } catch (_recoveryError) {
      }
      return aggregate;
    }
  }

  private async compactObservedAncestors(
    store: relationalStore.RdbStore,
    aggregate: HuaweiSpaceSnapshotAggregate<T>,
    protectedCommitId: string = ''
  ): Promise<HuaweiSpaceSnapshotAggregate<T>> {
    const ancestors = aggregate.ancestorCommitIds.filter((candidate: string): boolean => {
      return candidate !== protectedCommitId;
    });
    if (ancestors.length <= 0) {
      return aggregate;
    }
    const deleted = await this.deleteCommits(store, ancestors);
    if (deleted <= 0) {
      return aggregate;
    }
    await this.runManualCloudSync(
      store,
      true,
      relationalStore.SyncMode.SYNC_MODE_TIME_FIRST
    );
    await this.runManualCloudSync(
      store,
      true,
      relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST
    );
    const refreshed = await this.readAggregate(store);
    if ((protectedCommitId.length > 0 && !await this.hasCommit(store, protectedCommitId)) ||
      (aggregate.snapshot !== null && refreshed.snapshot === null)) {
      throw new Error(this.options.writeConflictError);
    }
    return refreshed;
  }

  private async deleteCommits(store: relationalStore.RdbStore, commitIds: string[]): Promise<number> {
    let deleted = 0;
    for (let offset = 0; offset < commitIds.length;
      offset += HUAWEI_SPACE_CONDITIONAL_SNAPSHOT_DELETE_BATCH_SIZE) {
      const predicates = new relationalStore.RdbPredicates(this.options.tableName);
      predicates.equalTo('accountUid', this.uid);
      predicates.in(
        'commitId',
        commitIds.slice(offset, offset + HUAWEI_SPACE_CONDITIONAL_SNAPSHOT_DELETE_BATCH_SIZE)
      );
      deleted += await store.delete(predicates);
    }
    return deleted;
  }

  private async readCommitRows(store: relationalStore.RdbStore): Promise<HuaweiSpaceSnapshotCommitRow<T>[]> {
    const predicates = new relationalStore.RdbPredicates(this.options.tableName);
    predicates.equalTo('accountUid', this.uid);
    const resultSet = await store.queryWithoutRowCount(predicates, [
      'commitId',
      'parentCommitIdsJson',
      'snapshotJson',
      'updatedAt'
    ]);
    const rows: HuaweiSpaceSnapshotCommitRow<T>[] = [];
    try {
      const commitIndex = resultSet.getColumnIndex('commitId');
      const parentIndex = resultSet.getColumnIndex('parentCommitIdsJson');
      const snapshotIndex = resultSet.getColumnIndex('snapshotJson');
      const updatedAtIndex = resultSet.getColumnIndex('updatedAt');
      while (resultSet.goToNextRow()) {
        const commitId = resultSet.getString(commitIndex).trim();
        if (commitId.length <= 0) {
          continue;
        }
        try {
          const snapshotJson = await this.snapshotBlobCodec.decodeJson(resultSet.getBlob(snapshotIndex));
          rows.push({
            commitId,
            parentCommitIds: this.parseStringArray(resultSet.getString(parentIndex)),
            snapshot: this.options.parse(snapshotJson),
            updatedAt: resultSet.getLong(updatedAtIndex)
          });
        } catch (_error) {
          throw new Error(`华为云空间${this.options.operationLabel}提交无法解析。`);
        }
      }
    } finally {
      resultSet.close();
    }
    return rows.sort((left: HuaweiSpaceSnapshotCommitRow<T>, right: HuaweiSpaceSnapshotCommitRow<T>) => {
      if (left.updatedAt !== right.updatedAt) {
        return left.updatedAt - right.updatedAt;
      }
      return left.commitId.localeCompare(right.commitId);
    });
  }

  private async hasCommit(store: relationalStore.RdbStore, commitId: string): Promise<boolean> {
    const predicates = new relationalStore.RdbPredicates(this.options.tableName);
    predicates.equalTo('accountUid', this.uid);
    predicates.equalTo('commitId', commitId);
    const resultSet = await store.query(predicates, ['commitId']);
    try {
      return resultSet.goToFirstRow();
    } finally {
      resultSet.close();
    }
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

  private runManualCloudSync(
    store: relationalStore.RdbStore,
    requireFreshTask: boolean = false,
    syncMode: relationalStore.SyncMode = relationalStore.SyncMode.SYNC_MODE_TIME_FIRST
  ): Promise<void> {
    return HuaweiSpaceCloudSyncCoordinator.run({
      uid: this.uid,
      databaseName: this.databaseName,
      store,
      tableNames: [this.options.tableName],
      syncMode,
      timeoutMs: HUAWEI_SPACE_CONDITIONAL_SNAPSHOT_TIMEOUT_MS,
      requireFreshTask,
      buildTimeoutError: (): Error => {
        return new Error(`华为云空间${this.options.operationLabel}确认超时，请稍后重试。`);
      },
      buildProgressError: (progressCode: number): Error => {
        return this.buildCloudProgressError(progressCode);
      },
      buildCompletionError: (error: BusinessError): Error => {
        return new Error(`华为云空间${this.options.operationLabel}失败：${error.message}`);
      },
      buildInvocationError: (error: Object): Error => {
        const message = error instanceof Error ? error.message : JSON.stringify(error);
        return new Error(`华为云空间${this.options.operationLabel}失败：${message}`);
      }
    });
  }

  private buildCloudProgressError(progressCode: number): Error {
    if (progressCode === relationalStore.ProgressCode.CLOUD_DISABLED) {
      return new Error(`华为云空间${this.options.operationLabel}不可用：系统返回 CLOUD_DISABLED（进度码 3）。`);
    }
    if (progressCode === relationalStore.ProgressCode.NETWORK_ERROR) {
      return new Error(`华为云空间${this.options.operationLabel}网络不可用（进度码 2）。`);
    }
    if (progressCode === relationalStore.ProgressCode.LOCKED_BY_OTHERS) {
      return new Error(`华为云空间${this.options.operationLabel}正在被其他任务占用（进度码 4），请稍后重试。`);
    }
    if (progressCode === relationalStore.ProgressCode.RECORD_LIMIT_EXCEEDED) {
      return new Error(`华为云空间${this.options.operationLabel}记录数量超过平台限制（进度码 5）。`);
    }
    if (progressCode === relationalStore.ProgressCode.NO_SPACE_FOR_ASSET) {
      return new Error('华为云空间容量不足（进度码 6）。');
    }
    if (progressCode === relationalStore.ProgressCode.BLOCKED_BY_NETWORK_STRATEGY) {
      return new Error(`华为云空间${this.options.operationLabel}被系统网络策略阻止（进度码 7）。`);
    }
    return new Error(`华为云空间${this.options.operationLabel}未完成（进度码 ${progressCode}）。`);
  }

  private buildCommitId(deviceId: string, snapshot: T, updatedAt: number): string {
    const seed = JSON.stringify(snapshot).length.toString(36);
    const safeDeviceId = deviceId.trim().replace(/[^a-zA-Z0-9_-]+/g, '_').slice(0, 48) || 'device';
    const random = Math.floor(Math.random() * 0x1000000).toString(36);
    return `${safeDeviceId}-${updatedAt.toString(36)}-${seed.length.toString(36)}-${random}`;
  }

  private parseStringArray(value: string): string[] {
    try {
      const raw = JSON.parse(value) as Object;
      if (!Array.isArray(raw)) {
        return [];
      }
      const values: string[] = [];
      raw.forEach((item: Object) => {
        if (typeof item !== 'string') {
          return;
        }
        const normalized = item.trim();
        if (normalized.length > 0 && values.indexOf(normalized) < 0) {
          values.push(normalized);
        }
      });
      return values;
    } catch (_error) {
      return [];
    }
  }

  private maskValue(value: string): string {
    const normalized = value.trim();
    if (normalized.length <= 8) {
      return `len${normalized.length}`;
    }
    return `${normalized.slice(0, 4)}...${normalized.slice(normalized.length - 4)}(len${normalized.length})`;
  }

  private assertConfigured(): void {
    if (this.uid.length <= 0) {
      throw new Error('请先使用华为账号开启华为云空间同步。');
    }
  }
}
