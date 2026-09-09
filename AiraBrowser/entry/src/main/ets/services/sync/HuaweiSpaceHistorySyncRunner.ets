import { hilog } from '@kit.PerformanceAnalysisKit';
import { HistorySyncRunResult, HuaweiSpaceHistorySyncState } from '../../common/models/HistorySyncModels';
import { BrowserDatabase } from '../../data/database/BrowserDatabase';
import {
  HuaweiSpaceHistoryRemoteStore,
  HuaweiSpaceHistoryWriteResult
} from '../../data/sync/HuaweiSpaceHistoryRemoteStore';
import {
  AiraHistoryInitialMergePlan,
  AiraSyncComputeExecutor
} from './AiraSyncComputeExecutor';
import { HistorySyncMergeService } from './HistorySyncMergeService';

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
    await this.database.initialize();
    let appliedChangeCount = await this.database.pruneHistorySyncProjection(identity.accountUid);
    await this.enrollLocalVisits(identity);
    const local = await this.database.readHuaweiSpaceHistorySyncState(identity.accountUid);
    const useCachedRemote = shouldUseCachedHuaweiHistoryRemote(
      clearOutboxAfterSuccess,
      identity.accountUid,
      this.lastConfirmedAccountUid,
      this.lastConfirmedState
    );
    const remoteStore = this.remoteStoreFactory(identity.accountUid, identity.clientId);
    const cachedRemote = this.lastConfirmedState;
    let remote: HuaweiSpaceHistorySyncState;
    if (useCachedRemote && cachedRemote !== undefined) {
      hilog.info(
        HISTORY_HUAWEI_LOG_DOMAIN,
        HISTORY_HUAWEI_LOG_TAG,
        'Huawei history used cached remote and skipped CLOUD_FIRST'
      );
      remote = cachedRemote;
    } else {
      remote = await remoteStore.readState();
    }
    const initialPlan: AiraHistoryInitialMergePlan =
      await this.computeExecutor.planHuaweiHistoryInitialMerge(remote, local);
    const firstApplied = initialPlan.localApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, initialPlan.merged)
      : 0;
    appliedChangeCount += firstApplied;
    const desired = initialPlan.merged;
    const remoteMaintenanceRequired = remoteStore.requiresMaintenance();
    const remoteWriteRequired = initialPlan.remoteWriteRequired || remoteMaintenanceRequired;
    const writeResult: HuaweiSpaceHistoryWriteResult = remoteWriteRequired
      ? await remoteStore.writeState(desired, useCachedRemote)
      : { state: remote, changedRowCount: 0, localApplyRequired: false };
    const confirmedState = remoteWriteRequired ? writeResult.state : initialPlan.merged;
    const confirmedLocalApplyRequired = remoteWriteRequired && writeResult.localApplyRequired;
    const confirmedApplied = confirmedLocalApplyRequired
      ? await this.database.applyHuaweiSpaceHistorySyncState(identity.accountUid, confirmedState)
      : 0;
    appliedChangeCount += confirmedApplied;
    const pruned = initialPlan.localApplyRequired || confirmedLocalApplyRequired
      ? await this.database.pruneHistorySyncProjection(identity.accountUid)
      : 0;
    appliedChangeCount += pruned;
    if (clearOutboxAfterSuccess) {
      await this.database.clearHistorySyncOutbox(identity.accountUid);
    }
    this.lastConfirmedAccountUid = identity.accountUid;
    this.lastConfirmedState = this.mergeService.normalize(confirmedState);
    return {
      ok: true,
      appliedChangeCount,
      uploadedMutationCount: writeResult.changedRowCount,
      message: appliedChangeCount > 0 || writeResult.changedRowCount > 0
        ? '历史记录已完成华为云空间增量同步。'
        : '历史记录已经是最新。'
    };
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
