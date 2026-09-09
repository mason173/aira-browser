import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  AiraBookmarkHistoryDescriptor,
  AiraSyncRemoteHead,
  AiraSyncRemoteState,
  AiraSyncRemoteStore,
  AiraSyncSnapshot,
  AiraSyncWriteStateParams,
  AiraSyncWriteStateResult
} from '../../common/models/AiraSyncModels';
import { AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME } from '../../services/sync/AiraSyncConfigStore';
import { AiraBookmarkMergeService } from '../../services/sync/AiraBookmarkMergeService';
import { AiraBookmarkSnapshotValidationService } from '../../services/sync/AiraBookmarkSnapshotValidationService';
import { AiraBookmarkTombstoneLifecycleService } from '../../services/sync/AiraBookmarkTombstoneLifecycleService';
import {
  HuaweiSpaceBookmarkChunkGeneration,
  HuaweiSpaceBookmarkChunkHeadReadResult,
  HuaweiSpaceBookmarkHeadSummary,
  HuaweiSpaceBookmarkChunkRepository
} from './HuaweiSpaceBookmarkChunkRepository';
import { HuaweiSpaceCloudSyncCoordinator } from './HuaweiSpaceCloudSyncCoordinator';
import { HuaweiSpaceRdbStoreOwner } from './HuaweiSpaceRdbStoreOwner';

const HUAWEI_SPACE_LOG_DOMAIN: number = 0x0000;
const HUAWEI_SPACE_LOG_TAG: string = 'AiraHuaweiSpace';
const HUAWEI_SPACE_CLOUD_SYNC_TIMEOUT_MS: number = 300000;

interface HuaweiSpaceBookmarkAggregate {
  snapshot: AiraSyncSnapshot | null;
  commitId: string | null;
  history: AiraBookmarkHistoryDescriptor | null;
  headCommitIds: string[];
  updatedAt: number;
}

export class HuaweiSpaceBookmarkSyncError extends Error {
  retryable: boolean;

  constructor(message: string, retryable: boolean) {
    super(message);
    this.retryable = retryable;
  }
}

export function isRetryableHuaweiSpaceBookmarkSyncError(error: Error): boolean {
  return error instanceof HuaweiSpaceBookmarkSyncError && error.retryable;
}

export class AiraHuaweiSpaceRemoteStore implements AiraSyncRemoteStore {
  private uid: string;
  private databaseName: string;
  private context?: common.ApplicationContext | common.UIAbilityContext;
  private store?: relationalStore.RdbStore;
  private storePromise?: Promise<relationalStore.RdbStore>;
  private mergeService: AiraBookmarkMergeService = new AiraBookmarkMergeService();
  private historyService: AiraBookmarkTombstoneLifecycleService =
    new AiraBookmarkTombstoneLifecycleService();
  private snapshotValidationService: AiraBookmarkSnapshotValidationService =
    new AiraBookmarkSnapshotValidationService();
  private chunkRepository: HuaweiSpaceBookmarkChunkRepository;

  constructor(
    uid: string,
    databaseName: string = AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME,
    context?: common.ApplicationContext | common.UIAbilityContext
  ) {
    this.uid = uid.trim();
    this.databaseName = this.normalizeDatabaseName(databaseName);
    this.context = context;
    this.chunkRepository = new HuaweiSpaceBookmarkChunkRepository(
      this.uid,
      this.snapshotValidationService
    );
  }

  async readState(): Promise<AiraSyncRemoteState> {
    this.assertConfigured();
    const store = await this.getStore();
    const aggregate = await this.readAggregateAfterCloudFirst(store);
    return {
      snapshot: aggregate.snapshot,
      commitId: aggregate.commitId,
      history: aggregate.history
    };
  }

  async readHead(): Promise<AiraSyncRemoteHead> {
    try {
      this.assertConfigured();
      const store = await this.getStore();
      await this.runManualCloudSync(
        store,
        relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
        this.chunkRepository.getHeadCloudTableNames()
      );
      const readResult = await this.chunkRepository.readHeadSummaries(store);
      if (readResult.heads.length <= 0 && readResult.hasAnyRows) {
        throw new HuaweiSpaceBookmarkSyncError(
          '华为云空间书签 G8 Head 尚未完整到达，请稍后重试。',
          true
        );
      }
      const commitIds = readResult.heads.map((row: HuaweiSpaceBookmarkHeadSummary): string => {
        return row.commitId;
      }).sort();
      const singleHead = readResult.heads.length === 1 ? readResult.heads[0] : undefined;
      return {
        commitId: commitIds.length > 0 ? this.buildAggregateCommitId(commitIds) : null,
        updatedAt: readResult.heads.reduce((latest: number, row: HuaweiSpaceBookmarkHeadSummary): number => {
          return Math.max(latest, row.updatedAt);
        }, 0),
        bookmarkFolders: singleHead?.bookmarkFolders ?? 0,
        bookmarkItems: singleHead?.bookmarkItems ?? 0,
        hasBookmarkSummary: singleHead !== undefined
      };
    } catch (error) {
      const message = this.stringifyError(error as Error);
      hilog.error(
        HUAWEI_SPACE_LOG_DOMAIN,
        HUAWEI_SPACE_LOG_TAG,
        'Huawei Space G8 head read failed uid=%{public}s reason=%{public}s',
        this.maskUid(this.uid),
        message
      );
      throw new Error(message);
    }
  }

  async confirmPendingWrites(): Promise<void> {
    this.assertConfigured();
    const store = await this.getStore();
    await this.runIncrementalCommitBarrier(store, this.chunkRepository.getBlockCloudTableNames());
    await this.runIncrementalCommitBarrier(store, this.chunkRepository.getHeadCloudTableNames());
  }

  async writeState(params: AiraSyncWriteStateParams): Promise<AiraSyncWriteStateResult> {
    this.assertConfigured();
    const snapshot = this.snapshotValidationService.validate(params.snapshot, '华为云空间');
    const history = this.historyService.validateHistory(
      params.history,
      '华为云空间书签墓碑历史纪元'
    );
    this.historyService.assertSnapshotWithinHistory(snapshot, history, '华为云空间');
    const store = await this.getStore();
    const current = await this.readAggregateAfterCloudFirst(store);
    if (current.history !== null && !this.historyService.sameHistory(
      this.historyService.selectNewerHistory(current.history, history),
      history
    )) {
      throw new Error('华为云空间书签墓碑历史边界不能回退。');
    }
    if (current.commitId === null &&
      this.buildFallbackParentCommitIds(params.parentCommitId).length <= 0 &&
      this.isEmptyInitialSnapshot(snapshot)) {
      hilog.warn(
        HUAWEI_SPACE_LOG_DOMAIN,
        HUAWEI_SPACE_LOG_TAG,
        'Huawei Space G8 blocked empty root uid=%{public}s reason=remote-not-materialized',
        this.maskUid(this.uid)
      );
      throw new Error(
        '华为云空间尚未返回可确认的书签远端状态，已阻止空快照上传。' +
        '本机书签未被覆盖，请稍后重试。'
      );
    }
    if (params.parentCommitId !== undefined && current.commitId !== null &&
      params.parentCommitId !== current.commitId) {
      throw new Error(`华为云空间远端已更新，请先重新拉取后再同步。当前远端 commit=${current.commitId ?? ''}`);
    }
    const commitId = this.createCommitId(snapshot.meta.deviceId, snapshot.meta.generatedAt);
    if (commitId.length <= 0) {
      throw new Error('华为云空间书签同步无法生成提交标识。');
    }
    const generatedAt = params.createdAt ?? snapshot.meta.generatedAt;
    const updatedAt = Date.now();
    const parentCommitIds = current.headCommitIds.length > 0
      ? current.headCommitIds
      : this.buildFallbackParentCommitIds(params.parentCommitId);
    try {
      const writeResult = await this.chunkRepository.writeSnapshotBlocks(store, {
        commitId,
        parentCommitIds,
        snapshot,
        history: history,
        deviceId: params.deviceId,
        generatedAt,
        updatedAt
      });
      await this.runIncrementalCommitBarrier(store, this.chunkRepository.getBlockCloudTableNames());
      if (!await this.chunkRepository.confirmPublicationBlocks(store, writeResult.publication)) {
        throw new HuaweiSpaceBookmarkSyncError(
          '华为云空间未确认完整的 G8 书签 Blocks，请稍后重试。',
          true
        );
      }
      await this.chunkRepository.publishHead(store, writeResult.publication);
      await this.runIncrementalCommitBarrier(store, this.chunkRepository.getHeadCloudTableNames());
      if (!await this.chunkRepository.hasPublishedHead(store, writeResult.publication)) {
        throw new HuaweiSpaceBookmarkSyncError(
          '华为云空间未确认完整的 G8 书签 Head，请稍后重试。',
          true
        );
      }
    } catch (error) {
      if (error instanceof HuaweiSpaceBookmarkSyncError) {
        throw error;
      }
      throw this.buildCloudCapabilityError(error as Object, '写入华为云空间 G8 书签记录失败');
    }
    if (!await this.chunkRepository.hasCompleteManifest(store, commitId)) {
      throw new HuaweiSpaceBookmarkSyncError(
        '华为云空间未确认完整的 G8 书签 Head/Blocks，请稍后重试。',
        true
      );
    }
    void this.runPhysicalGcSafely(store);
    return {
      commitId,
      writtenAt: generatedAt
    };
  }

  async warmupTransport(): Promise<void> {
    this.assertConfigured();
    await this.getStore();
  }

  async checkCapability(): Promise<void> {
    this.assertConfigured();
    const store = await this.getStore();
    await this.runManualCloudSync(
      store,
      relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
      this.chunkRepository.getCloudTableNames()
    );
  }

  private buildAggregate(readResult: HuaweiSpaceBookmarkChunkHeadReadResult): HuaweiSpaceBookmarkAggregate {
    const heads = readResult.heads;
    if (heads.length <= 0) {
      if (readResult.hasAnyRows) {
        throw new HuaweiSpaceBookmarkSyncError(
          '华为云空间书签 manifest 或 chunk 尚未完整到达，请稍后重试。',
          true
        );
      }
      return {
        snapshot: null,
        commitId: null,
        history: null,
        headCommitIds: [],
        updatedAt: 0
      };
    }
    let snapshot = heads[0].snapshot;
    let history = heads[0].history;
    for (let index = 1; index < heads.length; index += 1) {
      const nextHistory = this.historyService.selectNewerHistory(history, heads[index].history);
      const localProjection = this.historyService.projectSnapshot(snapshot, nextHistory).snapshot;
      const remoteProjection = this.historyService.projectSnapshot(heads[index].snapshot, nextHistory).snapshot;
      snapshot = this.mergeService.merge(
        null,
        localProjection,
        remoteProjection,
        snapshot.meta.deviceId
      ).snapshot;
      history = nextHistory;
    }
    const headCommitIds = heads.map((row: HuaweiSpaceBookmarkChunkGeneration): string => row.commitId).sort();
    return {
      snapshot,
      commitId: this.buildAggregateCommitId(headCommitIds),
      history,
      headCommitIds,
      updatedAt: heads.reduce((latest: number, row: HuaweiSpaceBookmarkChunkGeneration): number => {
        return Math.max(latest, row.updatedAt);
      }, 0)
    };
  }

  private async readAggregateAfterCloudFirst(
    store: relationalStore.RdbStore
  ): Promise<HuaweiSpaceBookmarkAggregate> {
    await this.runManualCloudSync(
      store,
      relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
      this.chunkRepository.getHeadCloudTableNames()
    );
    let readResult = await this.chunkRepository.readMaterializedHeads(store);
    if (readResult.needsBlockSync) {
      await this.runManualCloudSync(
        store,
        relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
        this.chunkRepository.getBlockCloudTableNames()
      );
      readResult = await this.chunkRepository.readMaterializedHeads(store);
    }
    return this.buildAggregate(readResult);
  }

  private buildAggregateCommitId(headCommitIds: string[]): string {
    if (headCommitIds.length <= 0) {
      return '';
    }
    if (headCommitIds.length === 1) {
      return headCommitIds[0];
    }
    return `heads:${headCommitIds.join(',')}`;
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
          throw this.buildCloudCapabilityError(error, '打开华为云空间 G8 书签库失败');
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
    syncMode: relationalStore.SyncMode,
    tableNames: string[],
    requireFreshTask: boolean = false
  ): Promise<void> {
    return HuaweiSpaceCloudSyncCoordinator.run({
      uid: this.uid,
      databaseName: this.databaseName,
      store,
      tableNames,
      syncMode,
      timeoutMs: HUAWEI_SPACE_CLOUD_SYNC_TIMEOUT_MS,
      requireFreshTask,
      buildTimeoutError: (): Error => {
        return new HuaweiSpaceBookmarkSyncError(
          '华为云空间 G8 书签同步确认超时，请稍后重试。',
          true
        );
      },
      buildProgressError: (progressCode: number): Error => {
        return this.buildCloudProgressError(progressCode);
      },
      buildCompletionError: (error: BusinessError): Error => {
        return this.buildCloudCapabilityError(error, '华为云空间 G8 书签同步失败');
      },
      buildInvocationError: (error: Object): Error => {
        return this.buildCloudCapabilityError(error, '华为云空间 G8 书签同步失败');
      }
    });
  }

  private async runIncrementalCommitBarrier(
    store: relationalStore.RdbStore,
    tableNames: string[]
  ): Promise<void> {
    await this.runManualCloudSync(store, relationalStore.SyncMode.SYNC_MODE_TIME_FIRST, tableNames, true);
    await this.runManualCloudSync(store, relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST, tableNames, true);
  }

  private async runPhysicalGcSafely(store: relationalStore.RdbStore): Promise<void> {
    try {
      await this.runManualCloudSync(
        store,
        relationalStore.SyncMode.SYNC_MODE_CLOUD_FIRST,
        this.chunkRepository.getHeadCloudTableNames(),
        true
      );
      const plan = await this.chunkRepository.buildPhysicalGcPlan(store);
      if (plan === undefined) {
        return;
      }
      const deletedHeads = await this.chunkRepository.deleteSupersededHeads(store, plan);
      if (deletedHeads > 0) {
        await this.runIncrementalCommitBarrier(store, this.chunkRepository.getHeadCloudTableNames());
      }
      if (!await this.chunkRepository.confirmSupersededHeadsRemoved(store, plan)) {
        throw new Error('G8 旧 Head 隔离删除尚未确认。');
      }
      const confirmedPlan = await this.chunkRepository.buildPhysicalGcPlan(store);
      if (confirmedPlan === undefined || confirmedPlan.storageEpoch !== plan.storageEpoch ||
        confirmedPlan.supersededHeadRowIds.length > 0) {
        return;
      }
      const deletedBlocks = await this.chunkRepository.deleteBlocksBeforeStorageEpoch(
        store,
        confirmedPlan.storageEpoch
      );
      if (deletedBlocks > 0) {
        await this.runIncrementalCommitBarrier(store, this.chunkRepository.getBlockCloudTableNames());
      }
      if (!await this.chunkRepository.confirmNoBlocksBeforeStorageEpoch(store, confirmedPlan.storageEpoch)) {
        throw new Error('G8 旧 Blocks 清理尚未确认。');
      }
      hilog.info(
        HUAWEI_SPACE_LOG_DOMAIN,
        HUAWEI_SPACE_LOG_TAG,
        'Huawei Space G8 maintenance confirmed uid=%{public}s epoch=%{public}d heads=%{public}d blocks=%{public}d',
        this.maskUid(this.uid),
        confirmedPlan.storageEpoch,
        deletedHeads,
        deletedBlocks
      );
    } catch (error) {
      hilog.warn(
        HUAWEI_SPACE_LOG_DOMAIN,
        HUAWEI_SPACE_LOG_TAG,
        'Huawei Space G8 maintenance deferred uid=%{public}s reason=%{public}s',
        this.maskUid(this.uid),
        this.stringifyError(error as Error)
      );
    }
  }

  private buildCloudProgressError(progressCode: number): Error {
    if (progressCode === relationalStore.ProgressCode.CLOUD_DISABLED) {
      return new HuaweiSpaceBookmarkSyncError(
        '华为云空间书签同步不可用：系统返回 CLOUD_DISABLED（进度码 3）。' +
        '请确认系统云空间同步已开启后再试。',
        false
      );
    }
    if (progressCode === relationalStore.ProgressCode.UNKNOWN_ERROR) {
      return new HuaweiSpaceBookmarkSyncError('华为云空间书签同步未完成（进度码 1）。', true);
    }
    if (progressCode === relationalStore.ProgressCode.NETWORK_ERROR) {
      return new HuaweiSpaceBookmarkSyncError('华为云空间书签同步网络不可用（进度码 2）。', true);
    }
    if (progressCode === relationalStore.ProgressCode.LOCKED_BY_OTHERS) {
      return new HuaweiSpaceBookmarkSyncError(
        '华为云空间书签同步正在被其他任务占用（进度码 4），请稍后重试。',
        true
      );
    }
    if (progressCode === relationalStore.ProgressCode.RECORD_LIMIT_EXCEEDED) {
      return new HuaweiSpaceBookmarkSyncError('华为云空间书签同步记录数量超过平台限制（进度码 5）。', false);
    }
    if (progressCode === relationalStore.ProgressCode.NO_SPACE_FOR_ASSET) {
      return new HuaweiSpaceBookmarkSyncError('华为云空间容量不足（进度码 6）。', false);
    }
    if (progressCode === relationalStore.ProgressCode.BLOCKED_BY_NETWORK_STRATEGY) {
      return new HuaweiSpaceBookmarkSyncError('华为云空间书签同步被系统网络策略阻止（进度码 7）。', false);
    }
    return new HuaweiSpaceBookmarkSyncError(
      `华为云空间书签同步未完成（进度码 ${progressCode}）。`,
      false
    );
  }

  private buildFallbackParentCommitIds(parentCommitId: string | null | undefined): string[] {
    const normalized = parentCommitId?.trim() ?? '';
    return normalized.length > 0 ? [normalized] : [];
  }

  private isEmptyInitialSnapshot(snapshot: AiraSyncSnapshot): boolean {
    return snapshot.bookmarkItems.length <= 0 &&
      snapshot.tombstones.length <= 0 &&
      (snapshot.appPrivateBookmarks?.bookmarkItems.length ?? 0) <= 0 &&
      (snapshot.appPrivateBookmarks?.tombstones.length ?? 0) <= 0;
  }

  private createCommitId(deviceId: string, generatedAt: string): string {
    const safeTimestamp = generatedAt.replace(/[:.]/g, '-');
    const compactDeviceId = deviceId.replace(/[^a-zA-Z0-9_-]/g, '_');
    return `cmt_${safeTimestamp}_${compactDeviceId}`;
  }

  private normalizeDatabaseName(value: string): string {
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME;
  }

  private assertConfigured(): void {
    if (this.uid.length <= 0) {
      throw new Error('请先使用华为账号开启华为云空间同步。');
    }
  }

  private buildCloudCapabilityError(error: Object, prefix: string): Error {
    const businessError = error as BusinessError;
    const code = typeof businessError.code === 'number' ? businessError.code : 0;
    const message = businessError.message ?? JSON.stringify(error);
    if (code === 801) {
      return new Error(`${prefix}：当前系统、云空间或应用配置暂不支持关系型数据库端云同步。`);
    }
    if (code > 0) {
      return new Error(`${prefix}（${code}）：${message}`);
    }
    return new Error(`${prefix}：${message}`);
  }

  private maskUid(uid: string): string {
    const normalized = uid.trim();
    if (normalized.length <= 8) {
      return `len${normalized.length}`;
    }
    return `${normalized.slice(0, 4)}...${normalized.slice(normalized.length - 4)}`;
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }
}
