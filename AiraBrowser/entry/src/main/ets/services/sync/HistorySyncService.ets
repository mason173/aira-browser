import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE,
  HISTORY_SYNC_EXCHANGE_BATCH_SIZE,
  HistorySyncBootstrapResponse,
  HistorySyncLocalState,
  HistorySyncMutation,
  HistorySyncProviderKind,
  HistorySyncRunResult
} from '../../common/models/HistorySyncModels';
import {
  AiraSyncRemoteKind,
  AiraSyncSettings,
  resolveAiraHuaweiAccountIdentity
} from '../../common/models/AiraSyncModels';
import { BrowserDatabase } from '../../data/database/BrowserDatabase';
import { AiraSyncConfigStore } from './AiraSyncConfigStore';
import {
  AiraCloudHistoryRemoteStore,
  createAiraCloudHistoryRemoteStore,
  HistorySyncRemoteError
} from './AiraCloudHistoryRemoteStore';
import {
  HuaweiSpaceHistorySyncIdentity,
  HuaweiSpaceHistorySyncRunner
} from './HuaweiSpaceHistorySyncRunner';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AIRA_PERSONAL_SERVER_INSTANCE_SERVICE } from './AiraPersonalServerInstanceService';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';

const DOMAIN: number = 0x0000;
const TAG: string = 'HistorySyncService';
const HISTORY_ENROLLMENT_BATCH_SIZE: number = 500;
const HISTORY_SYNC_MAX_NETWORK_ROUNDS: number = 200;

export interface HistorySyncIdentity {
  accountUid: string;
  clientId: string;
  deviceName: string;
  provider: HistorySyncProviderKind;
}

export type HistorySyncRemoteStoreFactory = (uid: string) => AiraCloudHistoryRemoteStore;
export type HistorySyncProjectionRefreshHandler = () => Promise<void>;
export type HistorySyncProviderResolver = () => HistorySyncProviderKind | undefined;
export type HistorySyncProviderRunMode = 'ordinary' | 'source_transition' | 'target_transition';

export function resolveHistorySyncProviderKind(
  remoteKind: AiraSyncRemoteKind
): HistorySyncProviderKind | undefined {
  if (remoteKind === 'aira_cloud' && AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
    return remoteKind;
  }
  if (remoteKind === 'huawei_space' && AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
    return remoteKind;
  }
  if (remoteKind === 'self_hosted') {
    return remoteKind;
  }
  return undefined;
}

export class HistorySyncService {
  private database: BrowserDatabase;
  private syncConfigStore: AiraSyncConfigStore;
  private remoteStoreFactory: HistorySyncRemoteStoreFactory;
  private huaweiSpaceRunner: HuaweiSpaceHistorySyncRunner;
  private providerResolver: HistorySyncProviderResolver;
  private projectionRefreshHandler?: HistorySyncProjectionRefreshHandler;
  private runPromise?: Promise<HistorySyncRunResult>;
  private runIdentityKey: string = '';
  private runAccountUid: string = '';
  private identityGeneration: number = 0;

  constructor(
    database: BrowserDatabase,
    syncConfigStore: AiraSyncConfigStore,
    remoteStoreFactory?: HistorySyncRemoteStoreFactory,
    projectionRefreshHandler?: HistorySyncProjectionRefreshHandler,
    huaweiSpaceRunner?: HuaweiSpaceHistorySyncRunner,
    providerResolver?: HistorySyncProviderResolver
  ) {
    this.database = database;
    this.syncConfigStore = syncConfigStore;
    this.remoteStoreFactory = remoteStoreFactory ?? createAiraCloudHistoryRemoteStore;
    this.projectionRefreshHandler = projectionRefreshHandler;
    this.huaweiSpaceRunner = huaweiSpaceRunner ?? new HuaweiSpaceHistorySyncRunner(database);
    this.providerResolver = providerResolver ?? ((): HistorySyncProviderKind | undefined => {
      return resolveHistorySyncProviderKind(this.syncConfigStore.getSettings().remoteKind);
    });
  }

  runNow(): Promise<HistorySyncRunResult> {
    return this.resolveAndRun()
      .catch((error: Error): HistorySyncRunResult => {
        return this.buildFailureResult(error);
      });
  }

  runForProvider(
    provider: HistorySyncProviderKind,
    runMode: HistorySyncProviderRunMode = 'ordinary'
  ): Promise<HistorySyncRunResult> {
    return this.resolveAndRun(provider, runMode)
      .catch((error: Error): HistorySyncRunResult => this.buildFailureResult(error));
  }

  resolveCurrentIdentity(): HistorySyncIdentity | undefined {
    const settings = this.syncConfigStore.getSettings();
    return this.resolveIdentity(settings, this.providerResolver());
  }

  async cancelForIdentityChange(nextAccountUid: string): Promise<void> {
    const activeRun = this.runPromise;
    if (activeRun === undefined) {
      return;
    }
    const cancelActiveRun = this.runAccountUid !== nextAccountUid.trim();
    if (cancelActiveRun) {
      this.identityGeneration += 1;
    }
    await activeRun;
  }

  async detachRemoteProjectionsExcept(accountUid: string): Promise<void> {
    const detachedCount = await this.database.detachHistorySyncRemoteProjectionsExcept(accountUid);
    await this.refreshProjectionIfNeeded(detachedCount);
  }

  private async resolveAndRun(
    providerOverride?: HistorySyncProviderKind,
    runMode: HistorySyncProviderRunMode = 'ordinary'
  ): Promise<HistorySyncRunResult> {
    const settings = await this.syncConfigStore.initialize();
    const identity = this.resolveIdentity(settings, providerOverride ?? this.providerResolver());
    if (identity === undefined) {
      if (settings.remoteKind === 'webdav' && providerOverride === undefined) {
        throw new Error('当前 WebDAV 同步方式不支持历史记录同步。');
      }
      throw new Error('请先登录华为账号再同步历史记录。');
    }
    const identityKey = this.buildIdentityKey(identity, runMode);
    if (this.runPromise !== undefined) {
      if (this.runIdentityKey === identityKey) {
        return this.runPromise;
      }
      await this.runPromise;
      return this.resolveAndRun(providerOverride, runMode);
    }
    const generation = this.identityGeneration;
    const run = this.runInternal(identity, generation, runMode)
      .catch((error: Error): HistorySyncRunResult => {
        return this.buildFailureResult(error);
      })
      .finally(() => {
        if (this.runPromise === run) {
          this.runPromise = undefined;
          this.runIdentityKey = '';
          this.runAccountUid = '';
        }
      });
    this.runIdentityKey = identityKey;
    this.runAccountUid = identity.accountUid;
    this.runPromise = run;
    return run;
  }

  private async runInternal(
    identity: HistorySyncIdentity,
    generation: number,
    runMode: HistorySyncProviderRunMode
  ): Promise<HistorySyncRunResult> {
    const startedAt = Date.now();
    AiraSyncJankProbe.markExtra('history_run_start', `provider=${identity.provider} mode=${runMode}`);
    if (identity.provider === 'huawei_space' &&
      !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_space'));
    }
    if (identity.provider === 'huawei_space') {
      this.assertRunIdentity(identity, generation);
      const huaweiIdentity: HuaweiSpaceHistorySyncIdentity = {
        accountUid: identity.accountUid,
        clientId: identity.clientId,
        deviceName: identity.deviceName
      };
      const result = await this.huaweiSpaceRunner.run(huaweiIdentity, runMode === 'ordinary');
      this.assertRunIdentity(identity, generation);
      await this.refreshProjectionIfNeeded(result.appliedChangeCount);
      AiraSyncJankProbe.endExtra(
        'history_run',
        startedAt,
        `provider=huawei_space applied=${result.appliedChangeCount} uploaded=${result.uploadedMutationCount}`
      );
      return result;
    }
    const cloudResult = await this.runAiraCloud(identity, generation, runMode);
    AiraSyncJankProbe.endExtra(
      'history_run',
      startedAt,
      `provider=${identity.provider} applied=${cloudResult.appliedChangeCount} uploaded=${cloudResult.uploadedMutationCount}`
    );
    return cloudResult;
  }

  private async runAiraCloud(
    identity: HistorySyncIdentity,
    generation: number,
    runMode: HistorySyncProviderRunMode
  ): Promise<HistorySyncRunResult> {
    if (identity.provider === 'aira_cloud' && !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud'));
    }
    const targetTransition = runMode === 'target_transition';
    const retainAcknowledgedOutbox = runMode === 'source_transition';
    this.assertRunIdentity(identity, generation);
    await this.database.initialize();
    this.assertRunIdentity(identity, generation);
    const remoteStore = identity.provider === 'self_hosted'
      ? AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.createHistoryStore(this.syncConfigStore.getSettings())
      : this.remoteStoreFactory(identity.accountUid);
    let state = await this.database.getHistorySyncLocalState(identity.accountUid, identity.clientId);
    const providerEnrollmentUpdatedAfter = state.initialized && state.bootstrapHead <= 0
      ? state.updatedAt
      : 0;
    let appliedChangeCount = await this.database.pruneHistorySyncProjection(identity.accountUid);
    let uploadedMutationCount = 0;
    this.assertRunIdentity(identity, generation);
    if (!state.initialized || state.bootstrapHead > 0) {
      const bootstrapped = await this.runBootstrap(remoteStore, identity, state, generation);
      appliedChangeCount += bootstrapped;
      state = await this.database.getHistorySyncLocalState(identity.accountUid, identity.clientId);
    }
    if (targetTransition) {
      await this.database.prepareAiraHistorySyncProviderEnrollment(
        identity.accountUid,
        identity.clientId,
        providerEnrollmentUpdatedAfter
      );
    }

    let resetAttempted = false;
    const acknowledgedMutationIds: Set<string> = new Set<string>();
    for (let round = 0; round < HISTORY_SYNC_MAX_NETWORK_ROUNDS; round += 1) {
      this.assertRunIdentity(identity, generation);
      const pendingBeforeEnrollment = await this.listAiraCloudMutationsForRun(
        identity.accountUid,
        acknowledgedMutationIds
      );
      if (pendingBeforeEnrollment.length <= 0) {
        this.assertRunIdentity(identity, generation);
        await this.database.prepareHistorySyncEnrollment(
          identity.accountUid,
          identity.clientId,
          identity.deviceName,
          HISTORY_ENROLLMENT_BATCH_SIZE
        );
      }
      const mutations = await this.listAiraCloudMutationsForRun(
        identity.accountUid,
        acknowledgedMutationIds
      );
      state = await this.database.getHistorySyncLocalState(identity.accountUid, identity.clientId);
      try {
        this.assertRunIdentity(identity, generation);
        const response = await remoteStore.exchange({
          clientId: identity.clientId,
          cursor: state.cursor,
          mutations: mutations,
          pullLimit: HISTORY_SYNC_EXCHANGE_BATCH_SIZE
        });
        this.assertRunIdentity(identity, generation);
        const roundApplied = await this.database.applyHistorySyncExchange(
          identity.accountUid,
          identity.clientId,
          response,
          !retainAcknowledgedOutbox
        );
        appliedChangeCount += roundApplied;
        if (retainAcknowledgedOutbox) {
          response.acknowledgements.forEach((acknowledgement): void => {
            acknowledgedMutationIds.add(acknowledgement.mutationId);
          });
        }
        this.assertRunIdentity(identity, generation);
        const roundPruned = await this.database.pruneHistorySyncProjection(identity.accountUid);
        appliedChangeCount += roundPruned;
        uploadedMutationCount += response.acknowledgements.length;
        if (response.hasMore) {
          continue;
        }
        const remaining = await this.listAiraCloudMutationsForRun(identity.accountUid, acknowledgedMutationIds);
        if (remaining.length > 0) {
          continue;
        }
        const enrolled = await this.database.prepareHistorySyncEnrollment(
          identity.accountUid,
          identity.clientId,
          identity.deviceName,
          HISTORY_ENROLLMENT_BATCH_SIZE
        );
        if (enrolled > 0) {
          continue;
        }
        this.assertRunIdentity(identity, generation);
        await this.refreshProjectionIfNeeded(appliedChangeCount);
        return {
          ok: true,
          appliedChangeCount: appliedChangeCount,
          uploadedMutationCount: uploadedMutationCount,
          message: appliedChangeCount > 0 || uploadedMutationCount > 0
            ? '历史记录已完成增量同步。'
            : '历史记录已经是最新。'
        };
      } catch (error) {
        const normalizedError = error instanceof Error ? error : new Error(JSON.stringify(error));
        if (resetAttempted || !this.requiresBootstrap(normalizedError)) {
          throw normalizedError;
        }
        resetAttempted = true;
        const current = await this.database.getHistorySyncLocalState(identity.accountUid, identity.clientId);
        const bootstrapped = await this.runBootstrap(remoteStore, identity, current, generation, true);
        appliedChangeCount += bootstrapped;
      }
    }
    throw new Error('历史记录增量过多，本轮未能在安全上限内完成，请稍后继续同步。');
  }

  private async listAiraCloudMutationsForRun(
    accountUid: string,
    acknowledgedMutationIds: Set<string>
  ): Promise<HistorySyncMutation[]> {
    const candidates = await this.database.listHistorySyncOutbox(
      accountUid,
      acknowledgedMutationIds.size + HISTORY_SYNC_EXCHANGE_BATCH_SIZE
    );
    return candidates.filter((mutation: HistorySyncMutation): boolean => {
      return !acknowledgedMutationIds.has(mutation.mutationId);
    }).slice(0, HISTORY_SYNC_EXCHANGE_BATCH_SIZE);
  }

  private async runBootstrap(
    remoteStore: AiraCloudHistoryRemoteStore,
    identity: HistorySyncIdentity,
    initialState: HistorySyncLocalState,
    generation: number,
    forceRestart: boolean = false
  ): Promise<number> {
    let state = initialState;
    let applied = 0;
    let firstPage = forceRestart || (state.bootstrapHead <= 0 && state.bootstrapAfterVisitId.length <= 0);
    if (forceRestart) {
      state = {
        accountUid: identity.accountUid,
        clientId: identity.clientId,
        initialized: false,
        cursor: 0,
        bootstrapHead: 0,
        bootstrapAfterUpdatedSeq: 0,
        bootstrapAfterVisitId: '',
        updatedAt: 0
      };
    }
    for (let page = 0; page < HISTORY_SYNC_MAX_NETWORK_ROUNDS; page += 1) {
      this.assertRunIdentity(identity, generation);
      const response: HistorySyncBootstrapResponse = await remoteStore.bootstrap({
        clientId: identity.clientId,
        bootstrapHead: state.bootstrapHead > 0 ? state.bootstrapHead : undefined,
        afterUpdatedSeq: state.bootstrapAfterUpdatedSeq > 0 ? state.bootstrapAfterUpdatedSeq : undefined,
        afterVisitId: state.bootstrapAfterVisitId.length > 0 ? state.bootstrapAfterVisitId : undefined,
        pageLimit: HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE
      });
      this.assertRunIdentity(identity, generation);
      applied += await this.database.applyHistorySyncBootstrap(
        identity.accountUid,
        identity.clientId,
        response,
        firstPage
      );
      this.assertRunIdentity(identity, generation);
      applied += await this.database.pruneHistorySyncProjection(identity.accountUid);
      firstPage = false;
      if (!response.hasMore) {
        return applied;
      }
      state = await this.database.getHistorySyncLocalState(identity.accountUid, identity.clientId);
    }
    throw new Error('历史记录初始化页数超过安全上限，请稍后继续。');
  }

  private resolveIdentity(
    settings: AiraSyncSettings,
    provider: HistorySyncProviderKind | undefined
  ): HistorySyncIdentity | undefined {
    const account = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
    let accountUid = account.uid.trim();
    if (provider === 'self_hosted') {
      try {
        accountUid = AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.requireConfigured(settings).instanceId.trim();
      } catch (_error) {
        return undefined;
      }
    }
    const clientId = settings.sourceId.trim();
    if (provider === undefined || accountUid.length <= 0 || clientId.length <= 0) {
      return undefined;
    }
    return {
      accountUid: accountUid,
      clientId: clientId,
      deviceName: 'Aira HarmonyOS',
      provider
    };
  }

  private buildIdentityKey(identity: HistorySyncIdentity, runMode: HistorySyncProviderRunMode): string {
    return identity.accountUid + '\n' + identity.clientId + '\n' + identity.provider + '\n' + runMode;
  }

  private assertRunIdentity(identity: HistorySyncIdentity, generation: number): void {
    const current = this.resolveIdentity(this.syncConfigStore.getSettings(), identity.provider);
    if (generation !== this.identityGeneration || current === undefined ||
      current.accountUid !== identity.accountUid || current.clientId !== identity.clientId) {
      throw new Error('账号已切换，本轮历史记录同步已停止。');
    }
  }

  private requiresBootstrap(error: Error): boolean {
    return error instanceof HistorySyncRemoteError &&
      (error.code === 'history_cursor_expired' || error.code === 'history_cursor_ahead');
  }

  private async refreshProjectionIfNeeded(appliedChangeCount: number): Promise<void> {
    if (appliedChangeCount <= 0 || this.projectionRefreshHandler === undefined) {
      return;
    }
    await this.projectionRefreshHandler();
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }

  private buildFailureResult(error: Error): HistorySyncRunResult {
    const message = this.stringifyError(error);
    hilog.warn(DOMAIN, TAG, 'history sync failed error=%{public}s', message);
    return {
      ok: false,
      appliedChangeCount: 0,
      uploadedMutationCount: 0,
      message: message
    };
  }
}
