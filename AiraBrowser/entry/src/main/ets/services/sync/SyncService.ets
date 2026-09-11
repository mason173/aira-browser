import {
  AiraBookmarkConflictResolution,
  AiraBookmarkHistoryDescriptor,
  AiraBookmarkMergeSyncResult,
  AiraBookmarkOverview,
  AiraBookmarkSyncFailure,
  AiraBookmarkSyncFailureStage,
  AiraBookmarkSyncApplyResult,
  AiraBookmarkSyncRemoteObservation,
  AIRA_SYNC_DEFAULT_ROOT,
  AIRA_SYNC_ROOT_ORDER_KEY,
  AiraSyncBaselineRecord,
  AiraSyncBookmarkFolderEntity,
  AiraSyncBookmarkItemEntity,
  AiraSyncBookmarkOrder,
  AiraSyncProviderKind,
  AiraSyncRemoteKind,
  AiraSyncRemoteHead,
  AiraSyncRemoteStatusCache,
  AiraSyncRemoteState,
  AiraSyncRemoteStore,
  AiraSyncSettings,
  AiraSyncSnapshot,
  AiraSyncStatusSummary,
  AiraSyncTombstone,
  isAiraBookmarkProviderTransition,
  isAiraSyncProviderEnabled,
  resolveAiraSyncProviderRuntimeState,
  AiraSyncWriteStateResult
} from '../../common/models/AiraSyncModels';
import { SYNC_ADDITIONAL_BACKUP_MERGE_REQUIRED } from '../../common/constants/SyncFlowErrorCodes';
import {
  AiraCloudBookmarkV4BootstrapDomain,
  shouldAcknowledgeNativeAiraCloudBookmarkV4Activation
} from '../../common/models/AiraCloudBookmarkV4BootstrapModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BookmarkRepository } from '../../data/repositories/BrowserRepositories';
import { AiraBookmarkSnapshotService } from './AiraBookmarkSnapshotService';
import {
  AiraBookmarkMergeResult,
  AiraBookmarkMergeService
} from './AiraBookmarkMergeService';
import {
  AiraBookmarkSyncDecisionService,
  AiraBookmarkSyncIntent
} from './AiraBookmarkSyncDecisionService';
import {
  AiraBookmarkIdentityNoOpProbe,
  AiraBookmarkIdentityNoOpService
} from './AiraBookmarkIdentityNoOpService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME,
  AiraSyncConfigStore
} from './AiraSyncConfigStore';
import { SyncAdditionalBackupPolicyService } from './SyncAdditionalBackupPolicyService';
import { AiraWebdavRemoteStore } from './AiraWebdavRemoteStore';
import {
  AiraCloudBookmarkRemoteError,
  createAiraCloudBookmarkRemoteStore
} from './AiraCloudBookmarkRemoteStore';
import {
  AiraHuaweiSpaceRemoteStore,
  isRetryableHuaweiSpaceBookmarkSyncError
} from '../../data/sync/AiraHuaweiSpaceRemoteStore';
import { AiraSyncWorkThrottleService } from './AiraSyncWorkThrottleService';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';
import { AiraBookmarkTombstoneLifecycleService } from './AiraBookmarkTombstoneLifecycleService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AIRA_PERSONAL_SERVER_INSTANCE_SERVICE } from './AiraPersonalServerInstanceService';

type AiraWebdavRemoteStoreFactory = (settings: AiraSyncSettings) => AiraSyncRemoteStore;
type AiraHuaweiCloudRemoteStoreFactory = (settings: AiraSyncSettings) => AiraSyncRemoteStore;
type AiraHuaweiSpaceRemoteStoreFactory = (settings: AiraSyncSettings) => AiraSyncRemoteStore;
type AiraPersonalServerRemoteStoreFactory = (settings: AiraSyncSettings) => AiraSyncRemoteStore;

export type AiraBookmarkTargetMergeIntent = 'ordinary' | 'provider-switch';

interface AiraVisibleBookmarkCounts {
  folders: number;
  items: number;
}

interface AiraReachableBookmarkEntityIds {
  folders: Set<string>;
  items: Set<string>;
}

const AIRA_TOOLBAR_ROOT_ID = 'browser_root_toolbar';
const AIRA_OTHER_ROOT_ID = 'browser_root_other';
const AIRA_CHROME_SYNC_ROOT_IDS: string[] = [
  AIRA_TOOLBAR_ROOT_ID,
  AIRA_OTHER_ROOT_ID
];
const HUAWEI_SPACE_BOOKMARK_WRITE_CONFLICT_MESSAGE: string = '华为云空间远端已更新，请先重新拉取后再同步。';
const HUAWEI_SPACE_BOOKMARK_WRITE_CONFLICT_RETRY_LIMIT: number = 3;

class AiraBookmarkSyncStageError extends Error {
  readonly failure: AiraBookmarkSyncFailure;
  readonly originalError: Error;

  constructor(failure: AiraBookmarkSyncFailure, originalError: Error) {
    super(originalError.message);
    this.failure = failure;
    this.originalError = originalError;
  }
}

export class SyncService implements AiraCloudBookmarkV4BootstrapDomain {
  private static bookmarkMergeQueue: Promise<void> = Promise.resolve();
  private bookmarkSnapshotService: AiraBookmarkSnapshotService;
  private bookmarkMergeService: AiraBookmarkMergeService = new AiraBookmarkMergeService();
  private bookmarkDecisionService: AiraBookmarkSyncDecisionService = new AiraBookmarkSyncDecisionService();
  private bookmarkHistoryService: AiraBookmarkTombstoneLifecycleService =
    new AiraBookmarkTombstoneLifecycleService();
  private additionalBackupPolicyService: SyncAdditionalBackupPolicyService =
    new SyncAdditionalBackupPolicyService();
  private workThrottle: AiraSyncWorkThrottleService;
  private bookmarkIdentityNoOpService: AiraBookmarkIdentityNoOpService =
    new AiraBookmarkIdentityNoOpService();
  private syncConfigStore?: AiraSyncConfigStore;
  private webdavRemoteStoreFactory: AiraWebdavRemoteStoreFactory;
  private huaweiCloudRemoteStoreFactory: AiraHuaweiCloudRemoteStoreFactory;
  private huaweiSpaceRemoteStoreFactory: AiraHuaweiSpaceRemoteStoreFactory;
  private personalServerRemoteStoreFactory: AiraPersonalServerRemoteStoreFactory;
  private nativeAiraCloudGenerationHandler?: (uid: string, commitId: string) => Promise<void>;
  constructor(
    bookmarkRepository: BookmarkRepository,
    preferencesRepository: PreferencesRepository,
    syncConfigStore?: AiraSyncConfigStore,
    webdavRemoteStoreFactory?: AiraWebdavRemoteStoreFactory,
    huaweiCloudRemoteStoreFactory?: AiraHuaweiCloudRemoteStoreFactory,
    workThrottle?: AiraSyncWorkThrottleService,
    huaweiSpaceRemoteStoreFactory?: AiraHuaweiSpaceRemoteStoreFactory,
    personalServerRemoteStoreFactory?: AiraPersonalServerRemoteStoreFactory
  ) {
    this.workThrottle = workThrottle ?? new AiraSyncWorkThrottleService();
    this.bookmarkSnapshotService = new AiraBookmarkSnapshotService(
      bookmarkRepository,
      preferencesRepository,
      this.workThrottle
    );
    this.syncConfigStore = syncConfigStore;
    this.webdavRemoteStoreFactory = webdavRemoteStoreFactory ?? ((settings: AiraSyncSettings) => {
      return new AiraWebdavRemoteStore(settings.webdav, AIRA_SYNC_DEFAULT_ROOT);
    });
    this.huaweiCloudRemoteStoreFactory = huaweiCloudRemoteStoreFactory ?? ((settings: AiraSyncSettings) => {
      return createAiraCloudBookmarkRemoteStore(settings.huaweiCloud.uid);
    });
    this.huaweiSpaceRemoteStoreFactory = huaweiSpaceRemoteStoreFactory ?? ((settings: AiraSyncSettings) => {
      return new AiraHuaweiSpaceRemoteStore(
        settings.huaweiSpace.uid,
        settings.huaweiSpace.databaseName || AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME
      );
    });
    this.personalServerRemoteStoreFactory = personalServerRemoteStoreFactory ?? ((settings: AiraSyncSettings) => {
      return AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.createBookmarkStore(settings);
    });
  }

  setNativeAiraCloudGenerationHandler(
    handler: (uid: string, commitId: string) => Promise<void>
  ): void {
    this.nativeAiraCloudGenerationHandler = handler;
  }

  buildFreshAiraBookmarkOverview(): Promise<AiraBookmarkOverview> {
    return this.bookmarkSnapshotService.buildFreshBookmarkOverview();
  }

  async buildFreshAiraBookmarkSnapshot(
    preferCurrentCache: boolean = false,
    previousSnapshot?: AiraSyncSnapshot | null
  ): Promise<AiraSyncSnapshot> {
    const snapshot = await this.bookmarkSnapshotService.buildFreshBookmarkSnapshot(
      this.resolveLocalSyncSourceId(),
      preferCurrentCache,
      previousSnapshot
    );
    return snapshot;
  }

  async buildLocalBackupBookmarkSnapshot(): Promise<AiraSyncSnapshot> {
    return this.stripBookmarkTombstones(await this.buildFreshAiraBookmarkSnapshot());
  }

  async importLocalBackupBookmarkSnapshot(snapshot: AiraSyncSnapshot): Promise<AiraBookmarkSyncApplyResult> {
    const validated = this.bookmarkSnapshotService.validateBookmarkSnapshot(snapshot, '本地备份');
    const incoming = this.stripBookmarkTombstones(validated);
    const local = await this.buildFreshAiraBookmarkSnapshot();
    const mergeResult = await this.bookmarkMergeService.mergeCooperatively(
      null,
      local,
      incoming,
      this.workThrottle,
      local.meta.deviceId
    );
    if (!mergeResult.localApplyRequired) {
      return {
        upsertedFolderCount: 0,
        upsertedBookmarkCount: 0,
        deletedNodeCount: 0,
        skippedNodeCount: 0,
        blocked: false,
        summary: '本机已经包含备份中的书签。'
      };
    }
    return this.bookmarkSnapshotService.applyBookmarkSnapshotToLocalDb(mergeResult.snapshot);
  }

  replaceLocalBookmarksFromRecoverySnapshot(snapshot: AiraSyncSnapshot): Promise<AiraBookmarkSyncApplyResult> {
    return this.runSerializedBookmarkTask<AiraBookmarkSyncApplyResult>(async (): Promise<AiraBookmarkSyncApplyResult> => {
      const validated = this.bookmarkSnapshotService.validateBookmarkSnapshot(snapshot, '升级前书签备份');
      const incoming = this.stripBookmarkTombstones(validated);
      return this.runBookmarkStage('local_apply', (): Promise<AiraBookmarkSyncApplyResult> => {
        return this.bookmarkSnapshotService.replaceLocalBookmarksFromRemoteSnapshot(incoming);
      });
    });
  }

  validateLocalBackupBookmarkSnapshot(snapshot: AiraSyncSnapshot): AiraSyncSnapshot {
    return this.bookmarkSnapshotService.validateBookmarkSnapshot(snapshot, '本地备份');
  }

  getLocalBookmarkSyncNodeCount(): number {
    return this.bookmarkSnapshotService.getLocalBookmarkSyncNodeCount();
  }

  getAiraSyncSettings(): AiraSyncSettings {
    return this.requireSyncConfigStore().getSettings();
  }

  initializeAiraSyncSettings(): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().initialize();
  }

  resolveBookmarkSyncFailure(error: Error | Object): AiraBookmarkSyncFailure {
    if (error instanceof AiraBookmarkSyncStageError) {
      return error.failure;
    }
    if (error instanceof AiraCloudBookmarkRemoteError && error.code === 'client_update_required') {
      return {
        code: 'BKM-PROTOCOL-UPDATE-001',
        stage: 'authentication',
        safeDetail: '当前书签同步协议已停止服务，请升级鸿蒙 App 或 Aira-sync 插件后再试。本机和云端书签均未被覆盖。'
      };
    }
    return this.createBookmarkSyncFailure('unknown');
  }

  resolveAiraProviderIdForKind(remoteKind: AiraSyncRemoteKind): string {
    return this.resolveProviderId(remoteKind);
  }

  saveAiraWebdavConfig(
    endpoint: string,
    username: string,
    password: string
  ): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().saveWebdavConfig(endpoint, username, password);
  }

  async testAiraWebdavConnectionForConfig(
    endpoint: string,
    username: string,
    password: string
  ): Promise<void> {
    const store = new AiraWebdavRemoteStore({
      endpoint: endpoint.trim(),
      username: username.trim(),
      password: password,
      remoteStatusCache: null
    }, AIRA_SYNC_DEFAULT_ROOT);
    await store.testConnection();
  }

  saveHuaweiCloudConfig(
    uid: string,
    displayName: string = '',
    photoUrl: string = ''
  ): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().saveHuaweiCloudConfig(uid, displayName, photoUrl);
  }

  saveHuaweiSpaceConfig(
    uid: string,
    displayName: string = '',
    photoUrl: string = '',
    databaseName: string = AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME
  ): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().saveHuaweiSpaceConfig(uid, displayName, photoUrl, databaseName);
  }

  clearHuaweiIdentity(): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().clearHuaweiIdentity();
  }

  deactivateCurrentSync(): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().deactivateCurrentSync();
  }

  async warmupHuaweiSpaceTransport(): Promise<void> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
      return;
    }
    const startedAt = Date.now();
    AiraSyncJankProbe.mark('warmup_start');
    try {
      const settings = await this.initializeAiraSyncSettings();
      if (settings.remoteKind !== 'huawei_space') {
        AiraSyncJankProbe.endExtra('warmup', startedAt, 'skip=not_huawei_space');
        return;
      }
      const uid = settings.huaweiSpace.uid.trim();
      if (uid.length <= 0) {
        AiraSyncJankProbe.endExtra('warmup', startedAt, 'skip=no_uid');
        return;
      }
      const databaseName = settings.huaweiSpace.databaseName.trim().length > 0
        ? settings.huaweiSpace.databaseName.trim()
        : AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME;
      const store = new AiraHuaweiSpaceRemoteStore(uid, databaseName);
      await store.warmupTransport();
      AiraSyncJankProbe.end('warmup', startedAt);
    } catch (error) {
      const candidate = error as Error;
      AiraSyncJankProbe.endExtra('warmup', startedAt, 'failed');
      hilog.warn(
        0x0000,
        'HuaweiSpaceRdb',
        'transport warmup failed message=%{public}s',
        candidate.message ?? JSON.stringify(error)
      );
    }
  }

  async checkHuaweiSpaceCapability(
    uid?: string,
    databaseName: string = AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME
  ): Promise<void> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_space'));
    }
    const settings = this.getAiraSyncSettings();
    const resolvedUid = (uid ?? settings.huaweiSpace.uid).trim();
    const resolvedDatabaseName = databaseName.trim().length > 0
      ? databaseName.trim()
      : (settings.huaweiSpace.databaseName || AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME);
    const store = new AiraHuaweiSpaceRemoteStore(
      resolvedUid,
      resolvedDatabaseName
    );
    await store.checkCapability();
  }

  selectActiveProvider(remoteKind: AiraSyncRemoteKind): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().setActiveRemoteKind(remoteKind);
  }

  selectActiveProviderWithPendingBookmarkSync(
    remoteKind: AiraSyncRemoteKind,
    providerSwitchFrom: AiraSyncProviderKind,
    changedAt: number = Date.now()
  ): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().setActiveRemoteKindWithPendingBookmarkSync(
      remoteKind,
      providerSwitchFrom,
      changedAt
    );
  }

  async writeAdditionalBookmarkBackup(
    remoteKind: AiraSyncProviderKind
  ): Promise<AiraSyncWriteStateResult> {
    return this.prepareBookmarkBackup(remoteKind);
  }

  prepareBookmarkBackup(
    remoteKind: AiraSyncProviderKind
  ): Promise<AiraSyncWriteStateResult> {
    return this.runSerializedBookmarkTask<AiraSyncWriteStateResult>(async () => {
      const settings = this.getAiraSyncSettings();
      const activeProvider = this.resolveActiveProviderForSync(settings);
      if (remoteKind === activeProvider) {
        throw new Error('当前同步方式不能同时作为附加备份位置。');
      }
      if (!this.isRemoteKindConfigured(settings, remoteKind)) {
        throw new Error('请先配置对应的附加备份位置。');
      }
      const providerId = this.resolveProviderId(remoteKind);
      const baseline = await this.requireSyncConfigStore().readBaseline(providerId);
      const store = this.createRemoteStoreForKind(settings, remoteKind);
      if (store.readHead === undefined) {
        throw new Error(SYNC_ADDITIONAL_BACKUP_MERGE_REQUIRED);
      }
      const remoteHead = await store.readHead();
      const canResumeKnownLineage = baseline !== undefined && baseline.commitId.length > 0 &&
        remoteHead.commitId === baseline.commitId;
      if (remoteHead.commitId !== null && !canResumeKnownLineage) {
        throw new Error(SYNC_ADDITIONAL_BACKUP_MERGE_REQUIRED);
      }
      const history = await this.bookmarkHistoryService.readConfirmedHistory();
      if (baseline !== undefined &&
        !this.bookmarkHistoryService.sameHistory(
          this.bookmarkHistoryService.selectNewerHistory(history, baseline.history),
          history
        )) {
        throw new Error(SYNC_ADDITIONAL_BACKUP_MERGE_REQUIRED);
      }
      const localSnapshot = await this.buildFreshAiraBookmarkSnapshot();
      const snapshot = this.bookmarkHistoryService.projectSnapshot(localSnapshot, history).snapshot;
      const writeResult = await store.writeState({
        snapshot: snapshot,
        history: history,
        deviceId: snapshot.meta.deviceId,
        parentCommitId: remoteHead.commitId,
        createdAt: snapshot.meta.generatedAt
      });
      await this.confirmRemoteBookmarkCommit(
        store,
        remoteKind,
        writeResult.commitId,
        snapshot,
        history
      );
      await this.recordSuccessfulSync(
        remoteKind,
        snapshot,
        history,
        writeResult.commitId,
        false,
        'bookmark_backup'
      );
      return writeResult;
    });
  }

  setAdditionalBackupProviderEnabled(
    remoteKind: AiraSyncProviderKind,
    enabled: boolean
  ): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().setBackupRemoteEnabled(remoteKind, enabled);
  }

  syncBookmarksToProvider(
    remoteKind: AiraSyncProviderKind,
    intent: AiraBookmarkTargetMergeIntent = 'ordinary'
  ): Promise<AiraBookmarkMergeSyncResult> {
    return this.runSerializedBookmarkTask<AiraBookmarkMergeSyncResult>(async () => {
      const settings = this.getAiraSyncSettings();
      try {
        await this.runBookmarkStage('authentication', async (): Promise<void> => {
          this.assertRemoteKindConfigured(settings, remoteKind);
        });
        const result = await this.mergeAiraRemoteBookmarksForKind(
          remoteKind,
          intent
        );
        if (result.blocked || result.conflictCount > 0) {
          await this.requireSyncConfigStore().saveBookmarkBlockedState(
            remoteKind,
            result.summary,
            this.createBookmarkConflictFailure()
          );
        } else {
          await this.saveBookmarkSyncCompletion(remoteKind, result);
        }
        return result;
      } catch (error) {
        const syncError = this.ensureBookmarkStageError(error as Error, 'unknown');
        await this.requireSyncConfigStore().saveProviderRuntimeState(
          remoteKind,
          'unavailable',
          this.stringifyError(syncError.originalError),
          false,
          'bookmark',
          undefined,
          false,
          syncError.failure
        );
        throw syncError;
      }
    });
  }

  initializeBookmarkSyncDomain(): Promise<AiraBookmarkMergeSyncResult> {
    return this.runSerializedBookmarkTask<AiraBookmarkMergeSyncResult>(async () => {
      const settings = this.getAiraSyncSettings();
      const completedPendingBookmarkSyncAt = settings.pendingBookmarkSyncAt ?? 0;
      const activeProvider = this.resolveActiveProviderForConfiguredSettings(settings);
      let result: AiraBookmarkMergeSyncResult;
      try {
        result = await this.mergeAiraRemoteBookmarksForKind(
          activeProvider,
          this.resolveTargetMergeIntentForActiveMerge(settings, activeProvider)
        );
        if (result.blocked || result.conflictCount > 0) {
          await this.requireSyncConfigStore().saveBookmarkBlockedState(
            activeProvider,
            result.summary,
            this.createBookmarkConflictFailure()
          );
          return result;
        }
        await this.saveBookmarkSyncCompletion(activeProvider, result);
        await this.requireSyncConfigStore().setBookmarkSyncEnabled(true);
      } catch (error) {
        const syncError = this.ensureBookmarkStageError(error as Error, 'unknown');
        await this.requireSyncConfigStore().saveProviderRuntimeState(
          activeProvider,
          'unavailable',
          this.stringifyError(syncError.originalError),
          false,
          'bookmark',
          undefined,
          false,
          syncError.failure
        );
        throw syncError;
      }
      const backupSummary = await this.writeBookmarkBackupSnapshotsSafely(settings, activeProvider);
      await this.clearBookmarkSyncPending(completedPendingBookmarkSyncAt);
      if (backupSummary.length <= 0) {
        return result;
      }
      return {
        commitId: result.commitId,
        merged: result.merged,
        blocked: false,
        conflictCount: result.conflictCount,
        localChangeCount: result.localChangeCount,
        remoteChangeCount: result.remoteChangeCount,
        conflictDetails: result.conflictDetails,
        remoteObservation: result.remoteObservation,
        summary: `${result.summary}\n${backupSummary}`
      };
    });
  }

  readRemoteSummary(remoteKind: AiraSyncProviderKind): Promise<AiraSyncStatusSummary> {
    if (remoteKind === 'aira_cloud') {
      return this.readAiraCloudRemoteSummary();
    }
    if (remoteKind === 'huawei_space') {
      return this.readHuaweiSpaceRemoteSummary();
    }
    if (remoteKind === 'self_hosted') {
      const settings = this.getAiraSyncSettings();
      this.assertPersonalServerConfigured(settings);
      return this.readAiraRemoteSummary(
        settings,
        this.createPersonalServerRemoteStore(settings),
        'self_hosted',
        '个人服务器'
      );
    }
    return this.readAiraWebdavRemoteSummary();
  }

  private async readAiraWebdavRemoteSummary(): Promise<AiraSyncStatusSummary> {
    const settings = this.getAiraSyncSettings();
    this.assertWebdavConfigured(settings);
    return this.readAiraRemoteSummary(
      settings,
      this.createWebdavRemoteStore(settings),
      'webdav',
      `远端 ${AIRA_SYNC_DEFAULT_ROOT}`
    );
  }

  private async readAiraCloudRemoteSummary(): Promise<AiraSyncStatusSummary> {
    const settings = this.getAiraSyncSettings();
    this.assertCloudConfigured(settings);
    return this.readHuaweiCloudRemoteSummary(settings);
  }

  private async readHuaweiSpaceRemoteSummary(): Promise<AiraSyncStatusSummary> {
    const settings = this.getAiraSyncSettings();
    this.assertHuaweiSpaceConfigured(settings);
    this.assertHuaweiPendingRemoteStatusReadable(settings);
    const store = this.createHuaweiSpaceRemoteStore(settings);
    return this.readAiraRemoteSummary(
      settings,
      store,
      'huawei_space',
      '华为云空间'
    );
  }

  async readAiraCloudRemoteHead(): Promise<AiraSyncRemoteHead> {
    const settings = this.getAiraSyncSettings();
    this.assertCloudConfigured(settings);
    return this.readRemoteHeadForStore(this.createHuaweiCloudRemoteStore(settings));
  }

  async readAiraCloudBookmarkV4BootstrapCommitId(expectedUid: string): Promise<string> {
    const settings = this.getAiraSyncSettings();
    this.assertAiraCloudBootstrapAccount(settings, expectedUid);
    const store = this.createHuaweiCloudRemoteStore(settings);
    const remoteState = await this.readValidatedAiraCloudBootstrapState(store);
    return remoteState.commitId as string;
  }

  replaceLocalBookmarksFromAiraCloudV4(expectedUid: string, expectedCommitId: string): Promise<string> {
    return this.runSerializedBookmarkTask<string>(async (): Promise<string> => {
      const settings = this.getAiraSyncSettings();
      this.assertAiraCloudBootstrapAccount(settings, expectedUid);
      const store = this.createHuaweiCloudRemoteStore(settings);
      const remoteState = await this.readValidatedAiraCloudBootstrapState(store);
      const snapshot = remoteState.snapshot as AiraSyncSnapshot;
      const history = remoteState.history as AiraBookmarkHistoryDescriptor;
      const commitId = remoteState.commitId as string;
      if (commitId !== expectedCommitId.trim()) {
        throw new Error('Aira 云端书签在备份期间发生变化，请重新开始 V4 初始化。');
      }
      const completedPendingBookmarkSyncAt = settings.pendingBookmarkSyncAt ?? 0;

      await this.runBookmarkStage('local_apply', (): Promise<AiraBookmarkSyncApplyResult> => {
        return this.bookmarkSnapshotService.replaceLocalBookmarksFromRemoteSnapshot(snapshot);
      });
      await this.recordSuccessfulSync(
        'aira_cloud',
        snapshot,
        history,
        commitId,
        true,
        'bookmark',
        completedPendingBookmarkSyncAt
      );
      await this.saveBookmarkSyncCompletion('aira_cloud', {
        commitId: commitId,
        merged: false,
        blocked: false,
        conflictCount: 0,
        localChangeCount: 0,
        remoteChangeCount: 0,
        conflictDetails: [],
        remoteObservation: this.buildBookmarkRemoteObservation(snapshot, commitId),
        summary: '已使用 Aira 云端书签完成 V4 初始化。'
      });
      await this.requireSyncConfigStore().setBookmarkSyncEnabled(true);
      return commitId;
    });
  }

  async disableAiraCloudBookmarkSync(): Promise<void> {
    const settings = this.getAiraSyncSettings();
    if (settings.remoteKind !== 'aira_cloud') {
      throw new Error('当前书签同步源不是 Aira 云。');
    }
    await this.requireSyncConfigStore().setBookmarkSyncEnabled(false);
  }

  private async readValidatedAiraCloudBootstrapState(
    store: AiraSyncRemoteStore
  ): Promise<AiraSyncRemoteState> {
    const remoteState = this.projectRemoteStateForBookmarkSync(await store.readState());
    if (remoteState.snapshot === null || remoteState.commitId === null ||
      remoteState.commitId.trim().length === 0 || remoteState.history === null) {
      throw new Error('Aira 云端没有完整的 V4 书签快照。');
    }
    this.bookmarkSnapshotService.validateBookmarkSnapshot(remoteState.snapshot, 'Aira 云端');
    const history = this.bookmarkHistoryService.validateHistory(remoteState.history, 'Aira 云端书签墓碑历史纪元');
    this.bookmarkHistoryService.assertSnapshotWithinHistory(remoteState.snapshot, history, 'Aira 云端');
    return {
      snapshot: remoteState.snapshot,
      commitId: remoteState.commitId,
      history: history
    };
  }

  private assertAiraCloudBootstrapAccount(settings: AiraSyncSettings, expectedUid: string): void {
    this.assertCloudConfigured(settings);
    const uid = settings.huaweiCloud.uid.trim();
    if (settings.remoteKind !== 'aira_cloud' ||
      uid.length === 0 || uid !== expectedUid.trim()) {
      throw new Error('Aira 云书签初始化账号或同步状态已变化。');
    }
  }

  private async readRemoteHeadForStore(store: AiraSyncRemoteStore): Promise<AiraSyncRemoteHead> {
    if (store.readHead !== undefined) {
      return store.readHead();
    }
    const remoteState = this.projectRemoteStateForBookmarkSync(await store.readState());
    const remoteCounts = this.countVisibleBookmarkEntities(remoteState.snapshot);
    return {
      commitId: remoteState.commitId,
      updatedAt: 0,
      bookmarkFolders: remoteCounts.folders,
      bookmarkItems: remoteCounts.items,
      hasBookmarkSummary: true
    };
  }

  async readHuaweiSpaceRemoteHead(): Promise<AiraSyncRemoteHead> {
    const settings = this.getAiraSyncSettings();
    this.assertHuaweiSpaceConfigured(settings);
    this.assertHuaweiPendingRemoteStatusReadable(settings);
    return this.readRemoteHeadForStore(this.createHuaweiSpaceRemoteStore(settings));
  }

  async mergeActiveAiraBookmarks(
    forceBackupWrites: boolean = false,
    allowDisabledBookmarkDomain: boolean = false
  ): Promise<AiraBookmarkMergeSyncResult> {
    return this.runSerializedBookmarkTask<AiraBookmarkMergeSyncResult>(async () => {
      const completedPendingBookmarkSyncAt = this.getAiraSyncSettings().pendingBookmarkSyncAt ?? 0;
      const result = await this.mergeActiveAiraBookmarksUnsafe(forceBackupWrites, allowDisabledBookmarkDomain);
      if (!result.blocked) {
        await this.clearBookmarkSyncPending(completedPendingBookmarkSyncAt);
      }
      return result;
    });
  }

  async resolveAiraBookmarkConflicts(
    remoteKind: AiraSyncProviderKind,
    resolution: AiraBookmarkConflictResolution
  ): Promise<AiraBookmarkMergeSyncResult> {
    return this.runSerializedBookmarkTask(async () => {
      const settings = this.getAiraSyncSettings();
      const completedPendingBookmarkSyncAt = settings.pendingBookmarkSyncAt ?? 0;
      this.assertRemoteKindConfigured(settings, remoteKind);
      const store = this.createRemoteStoreForKind(settings, remoteKind);
      const result = await this.mergeAiraRemoteBookmarksWithResolution(
        settings,
        store,
        remoteKind,
        resolution === 'prefer-remote' ? 'cloud-over-local' : 'local-over-cloud'
      );
      if (result.blocked || result.conflictCount > 0) {
        await this.requireSyncConfigStore().saveBookmarkBlockedState(
          remoteKind,
          result.summary,
          this.createBookmarkConflictFailure()
        );
      } else {
        await this.saveBookmarkSyncCompletion(remoteKind, result);
        await this.clearBookmarkSyncPending(completedPendingBookmarkSyncAt);
      }
      return result;
    });
  }

  private async mergeActiveAiraBookmarksUnsafe(
    forceBackupWrites: boolean = false,
    allowDisabledBookmarkDomain: boolean = false
  ): Promise<AiraBookmarkMergeSyncResult> {
    const settings = this.getAiraSyncSettings();
    if (settings.bookmarkSyncEnabled !== true && !allowDisabledBookmarkDomain) {
      throw new Error('书签同步尚未开启。');
    }
    const activeProvider = this.resolveActiveProviderForSync(settings);
    let activeResult: AiraBookmarkMergeSyncResult;
    try {
      activeResult = await this.mergeAiraRemoteBookmarksForKind(
        activeProvider,
        this.resolveTargetMergeIntentForActiveMerge(settings, activeProvider)
      );
      if (activeResult.blocked) {
        await this.requireSyncConfigStore().saveBookmarkBlockedState(
          activeProvider,
          activeResult.summary,
          this.createBookmarkConflictFailure()
        );
        return activeResult;
      }
      await this.saveBookmarkSyncCompletion(activeProvider, activeResult);
    } catch (error) {
      const syncError = this.ensureBookmarkStageError(error as Error, 'unknown');
      const errorMessage = this.stringifyError(syncError.originalError);
      const blocked = activeProvider === 'huawei_space' &&
        !isRetryableHuaweiSpaceBookmarkSyncError(syncError.originalError);
      await this.requireSyncConfigStore().saveProviderRuntimeState(
        activeProvider,
        'unavailable',
        errorMessage,
        false,
        'bookmark',
        undefined,
        blocked,
        syncError.failure
      );
      throw syncError;
    }
    const backupSummary = await this.writeBookmarkBackupSnapshotsSafely(
      settings,
      activeProvider,
      forceBackupWrites
    );
    if (backupSummary.length <= 0) {
      return activeResult;
    }
    return {
      commitId: activeResult.commitId,
      merged: activeResult.merged,
      blocked: false,
      conflictCount: activeResult.conflictCount,
      localChangeCount: activeResult.localChangeCount,
      remoteChangeCount: activeResult.remoteChangeCount,
      conflictDetails: activeResult.conflictDetails,
      remoteObservation: activeResult.remoteObservation,
      summary: `${activeResult.summary}\n${backupSummary}`
    };
  }

  private async writeBookmarkBackupSnapshotsSafely(
    settings: AiraSyncSettings,
    activeProvider: AiraSyncProviderKind,
    forceBackupWrites: boolean = false
  ): Promise<string> {
    try {
      return await this.writeBookmarkBackupSnapshots(settings, activeProvider, forceBackupWrites);
    } catch (error) {
      const failure = this.resolveBookmarkSyncFailure(error as Error);
      return `附加备份待处理：${failure.safeDetail}（错误码：${failure.code}）`;
    }
  }

  private async writeBookmarkBackupSnapshots(
    settings: AiraSyncSettings,
    activeProvider: AiraSyncProviderKind,
    forceBackupWrites: boolean = false
  ): Promise<string> {
    const backupKinds = this.resolveBackupRemoteKinds(settings);
    if (backupKinds.length <= 0 || !this.additionalBackupPolicyService.shouldWriteBackups(
      settings,
      'bookmarks',
      forceBackupWrites
    )) {
      return '';
    }
    const summaries: string[] = [];
    const history = await this.bookmarkHistoryService.readConfirmedHistory();
    let snapshot: AiraSyncSnapshot;
    try {
      snapshot = await this.buildFreshAiraBookmarkSnapshot();
    } catch (error) {
      const syncError = this.ensureBookmarkStageError(error as Error, 'local_snapshot');
      const message = this.stringifyError(syncError.originalError);
      for (let index = 0; index < backupKinds.length; index += 1) {
        const remoteKind = backupKinds[index];
        if (remoteKind === activeProvider) {
          continue;
        }
        await this.requireSyncConfigStore().saveProviderRuntimeState(
          remoteKind,
          'degraded',
          message,
          false,
          'bookmark_backup',
          undefined,
          false,
          syncError.failure
        ).catch((_inner: Error): void => {});
        summaries.push(`${this.resolveRemoteLabel(remoteKind)}备份待处理：${syncError.failure.safeDetail}` +
          `（错误码：${syncError.failure.code}）`);
      }
      return summaries.join('\n');
    }
    for (let index = 0; index < backupKinds.length; index++) {
      const remoteKind = backupKinds[index];
      if (remoteKind === activeProvider) {
        continue;
      }
      let failureStage: AiraBookmarkSyncFailureStage = 'merge';
      try {
        const providerId = this.resolveProviderId(remoteKind);
        const baseline = await this.requireSyncConfigStore().readBaseline(providerId);
        if (baseline === undefined || baseline.snapshot === null || baseline.commitId.length <= 0) {
          throw new Error('附加备份位置尚未完成初始化。');
        }
        if (!this.bookmarkHistoryService.sameHistory(
          this.bookmarkHistoryService.selectNewerHistory(history, baseline.history),
          history
        )) {
          throw new Error('附加备份历史已变化，请先将该位置设为当前同步方式完成合并。');
        }
        const store = this.createRemoteStoreForKind(this.getAiraSyncSettings(), remoteKind);
        const providerSnapshot = this.bookmarkHistoryService.projectSnapshot(
          snapshot,
          history
        ).snapshot;
        failureStage = 'remote_read_validation';
        const remoteHead = await this.readRemoteHeadSafely(store);
        if (remoteHead === undefined || remoteHead.commitId !== baseline.commitId) {
          throw new Error('附加备份历史已变化，请先将该位置设为当前同步方式完成合并。');
        }
        const baselineSnapshot = this.projectSnapshotForChromeSync(baseline.snapshot);
        const historyMatches = this.bookmarkHistoryService.sameHistory(baseline.history, history);
        if (baselineSnapshot !== null && historyMatches &&
          this.bookmarkMergeService.sameSnapshotContent(providerSnapshot, baselineSnapshot)) {
          await this.requireSyncConfigStore().saveProviderRuntimeState(
            remoteKind,
            'healthy',
            '',
            true,
            'bookmark_backup'
          );
          summaries.push(`${this.resolveRemoteLabel(remoteKind)}备份已是最新。`);
          continue;
        }
        failureStage = 'remote_commit';
        const writeResult = await store.writeState({
          snapshot: providerSnapshot,
          history: history,
          deviceId: providerSnapshot.meta.deviceId,
          parentCommitId: baseline.commitId,
          createdAt: providerSnapshot.meta.generatedAt
        });
        failureStage = 'remote_confirmation';
        await this.confirmRemoteBookmarkCommit(
          store,
          remoteKind,
          writeResult.commitId,
          providerSnapshot,
          history
        );
        failureStage = 'local_apply';
        await this.recordSuccessfulSync(
          remoteKind,
          providerSnapshot,
          history,
          writeResult.commitId,
          false,
          'bookmark_backup'
        );
        summaries.push(`${this.resolveRemoteLabel(remoteKind)}备份已更新。`);
      } catch (error) {
        const syncError = this.ensureBookmarkStageError(error as Error, failureStage);
        const message = this.stringifyError(syncError.originalError);
        await this.requireSyncConfigStore().saveProviderRuntimeState(
          remoteKind,
          'degraded',
          message,
          false,
          'bookmark_backup',
          undefined,
          false,
          syncError.failure
        );
        summaries.push(`${this.resolveRemoteLabel(remoteKind)}备份待处理：${syncError.failure.safeDetail}` +
          `（错误码：${syncError.failure.code}）`);
      }
    }
    return summaries.join('\n');
  }

  private async runSerializedBookmarkTask<T>(task: () => Promise<T>): Promise<T> {
    const previous = SyncService.bookmarkMergeQueue;
    let releaseQueue = (): void => {};
    SyncService.bookmarkMergeQueue = new Promise<void>((resolve: () => void) => {
      releaseQueue = resolve;
    });
    await previous;
    try {
      return await task();
    } finally {
      releaseQueue();
    }
  }

  private async mergeAiraWebdavBookmarksWithResolution(
    intent: AiraBookmarkSyncIntent = 'merge',
    conservativeMerge: boolean = false
  ): Promise<AiraBookmarkMergeSyncResult> {
    const settings = this.getAiraSyncSettings();
    this.assertWebdavConfigured(settings);
    return this.mergeAiraRemoteBookmarksWithResolution(
      settings,
      this.createWebdavRemoteStore(settings),
      'webdav',
      intent,
      conservativeMerge
    );
  }

  private async mergeAiraCloudBookmarksWithResolution(
    intent: AiraBookmarkSyncIntent = 'merge',
    conservativeMerge: boolean = false
  ): Promise<AiraBookmarkMergeSyncResult> {
    const settings = this.getAiraSyncSettings();
    this.assertCloudConfigured(settings);
    return this.mergeAiraRemoteBookmarksWithResolution(
      settings,
      this.createHuaweiCloudRemoteStore(settings),
      'aira_cloud',
      intent,
      conservativeMerge
    );
  }

  private async mergeHuaweiSpaceBookmarksWithResolution(
    intent: AiraBookmarkSyncIntent = 'merge',
    conservativeMerge: boolean = false
  ): Promise<AiraBookmarkMergeSyncResult> {
    const settings = this.getAiraSyncSettings();
    this.assertHuaweiSpaceConfigured(settings);
    return this.mergeAiraRemoteBookmarksWithResolution(
      settings,
      this.createHuaweiSpaceRemoteStore(settings),
      'huawei_space',
      intent,
      conservativeMerge
    );
  }

  private mergeAiraRemoteBookmarksForKind(
    remoteKind: AiraSyncRemoteKind,
    targetIntent: AiraBookmarkTargetMergeIntent = 'ordinary'
  ): Promise<AiraBookmarkMergeSyncResult> {
    const conservativeMerge = targetIntent === 'provider-switch';
    if (remoteKind === 'aira_cloud') {
      return this.mergeAiraCloudBookmarksWithResolution('merge', conservativeMerge);
    }
    if (remoteKind === 'huawei_space') {
      return this.mergeHuaweiSpaceBookmarksWithResolution('merge', conservativeMerge);
    }
    if (remoteKind === 'webdav') {
      return this.mergeAiraWebdavBookmarksWithResolution('merge', conservativeMerge);
    }
    if (remoteKind === 'self_hosted') {
      const settings = this.getAiraSyncSettings();
      this.assertPersonalServerConfigured(settings);
      return this.mergeAiraRemoteBookmarksWithResolution(
        settings,
        this.createPersonalServerRemoteStore(settings),
        'self_hosted',
        'merge',
        conservativeMerge
      );
    }
    return Promise.reject(new Error('请先启用书签同步源。'));
  }

  private async mergeAiraRemoteBookmarksWithResolution(
    initialSettings: AiraSyncSettings,
    store: AiraSyncRemoteStore,
    remoteKind: AiraSyncRemoteKind,
    intent: AiraBookmarkSyncIntent = 'merge',
    conservativeMerge: boolean = false
  ): Promise<AiraBookmarkMergeSyncResult> {
    let retryCount = 0;
    while (true) {
      try {
        return await this.mergeAiraRemoteBookmarksAttempt(
          initialSettings,
          store,
          remoteKind,
          intent,
          conservativeMerge
        );
      } catch (error) {
        if (!this.isHuaweiSpaceBookmarkWriteConflict(remoteKind, error as Error) ||
          retryCount >= HUAWEI_SPACE_BOOKMARK_WRITE_CONFLICT_RETRY_LIMIT) {
          throw error as Error;
        }
        retryCount += 1;
        await this.workThrottle.afterStage();
      }
    }
  }

  private async mergeAiraRemoteBookmarksAttempt(
    initialSettings: AiraSyncSettings,
    store: AiraSyncRemoteStore,
    remoteKind: AiraSyncRemoteKind,
    intent: AiraBookmarkSyncIntent = 'merge',
    conservativeMerge: boolean = false
  ): Promise<AiraBookmarkMergeSyncResult> {
    let settings = initialSettings;
    const providerId = this.resolveProviderId(remoteKind);
    const storedBaseline = await this.runBookmarkStage(
      'local_snapshot',
      (): Promise<AiraSyncBaselineRecord | undefined> => this.requireSyncConfigStore().readBaseline(providerId)
    );
    const baseline = (settings.bookmarkGenerationInitializedAt ?? 0) <= 0
      ? undefined
      : storedBaseline;
    await this.runBookmarkStage('remote_confirmation', (): Promise<void> => {
      return this.confirmPendingRemoteWrites(settings, store, remoteKind);
    });
    const identityProbe = this.buildHuaweiBookmarkIdentityNoOpProbe(
      remoteKind,
      intent,
      conservativeMerge,
      settings,
      baseline
    );
    if (this.bookmarkIdentityNoOpService.isEligible(identityProbe) &&
      store.readHead !== undefined && baseline !== undefined) {
      const identityNoOp = await this.tryHuaweiBookmarkIdentityNoOp(
        store,
        remoteKind,
        identityProbe,
        baseline,
        settings.pendingBookmarkSyncAt ?? 0
      );
      if (identityNoOp !== undefined) {
        return identityNoOp;
      }
    }
    const loadedRemoteState: AiraSyncRemoteState = await this.runBookmarkStage(
      'remote_read_validation',
      (): Promise<AiraSyncRemoteState> => this.resolveBookmarkRemoteStateForMerge(
        store,
        remoteKind,
        identityProbe,
        baseline
      )
    );
    await this.workThrottle.afterStage();
    const recoveredHuaweiRemoteFromBaseline = remoteKind === 'huawei_space' && baseline !== undefined &&
      loadedRemoteState.snapshot === null && loadedRemoteState.commitId === null;
    const remoteState: AiraSyncRemoteState = await this.runBookmarkStage(
      'remote_read_validation',
      async (): Promise<AiraSyncRemoteState> => {
        return this.reconcileRemoteStateForMerge(remoteKind, baseline, loadedRemoteState);
      }
    );
    const completedPendingBookmarkSyncAt = settings.pendingBookmarkSyncAt ?? 0;
    const localSnapshot = await this.runBookmarkStage(
      'local_snapshot',
      (): Promise<AiraSyncSnapshot> => this.resolveLocalSnapshotForMerge(settings, baseline)
    );
    await this.workThrottle.afterStage();
    const historyPlan = await this.runBookmarkStage(
      'merge',
      () => this.bookmarkHistoryService.planMerge(
        baseline,
        localSnapshot,
        remoteState,
        localSnapshot.meta.deviceId,
        Date.now()
      )
    );
    const decisionLocalSnapshot = this.resolveMaterializedLocalSnapshotForDecision(
      historyPlan.localSnapshot,
      historyPlan.baselineSnapshot
    );
    const mergeResult = await this.runBookmarkStage(
      'merge',
      () => this.bookmarkDecisionService.decideCooperatively({
        intent: intent,
        baseline: conservativeMerge ? null : historyPlan.baselineSnapshot,
        local: decisionLocalSnapshot,
        remote: historyPlan.remoteSnapshot
      }, this.workThrottle)
    );
    await this.workThrottle.afterStage();
    if (mergeResult.hasConflicts) {
      if (!historyPlan.requiresRemoteHistoryWrite &&
        historyPlan.remoteSnapshot !== null && remoteState.commitId !== null &&
        this.canRecoverMissingBaselineFromMatchingRemote(historyPlan.localSnapshot, historyPlan.remoteSnapshot)) {
        await this.recordSuccessfulSync(
          remoteKind,
          historyPlan.remoteSnapshot,
          historyPlan.history,
          remoteState.commitId,
          true,
          'bookmark',
          completedPendingBookmarkSyncAt
        );
        return {
          commitId: remoteState.commitId,
          merged: false,
          blocked: false,
          conflictCount: 0,
          localChangeCount: 0,
          remoteChangeCount: 0,
          conflictDetails: [],
          remoteObservation: this.buildBookmarkRemoteObservation(historyPlan.remoteSnapshot, remoteState.commitId),
          summary: '本机和云端内容一致，已恢复同步基线。'
        };
      }
      return this.createBlockedMergeResult(mergeResult);
    }
    if (!recoveredHuaweiRemoteFromBaseline && remoteState.snapshot !== null && remoteState.commitId !== null) {
      const completedCommitId = remoteState.commitId;
      const localApplyRequired = mergeResult.localApplyRequired;
      const remoteWriteRequired = mergeResult.remoteWriteRequired || historyPlan.requiresRemoteHistoryWrite;
      if (localApplyRequired && !remoteWriteRequired) {
        const applyResult = await this.runBookmarkStage(
          'local_apply',
          () => this.bookmarkSnapshotService.applyBookmarkSnapshotToLocalDb(mergeResult.snapshot)
        );
        if (applyResult.blocked) {
          return {
            commitId: completedCommitId,
            merged: false,
            blocked: true,
            conflictCount: 0,
            localChangeCount: 0,
            remoteChangeCount: 0,
            conflictDetails: [],
            remoteObservation: null,
            summary: applyResult.summary
          };
        }
        await this.runBookmarkStage('local_apply', (): Promise<void> => {
          return this.assertBookmarkSnapshotMaterializedLocally(mergeResult.snapshot);
        });
        await this.recordSuccessfulSync(
          remoteKind,
          mergeResult.snapshot,
          historyPlan.history,
          completedCommitId,
          true,
          'bookmark',
          completedPendingBookmarkSyncAt
        );
        return {
          commitId: completedCommitId,
          merged: false,
          blocked: false,
          conflictCount: 0,
          localChangeCount: 0,
          remoteChangeCount: 0,
          conflictDetails: [],
          remoteObservation: this.buildBookmarkRemoteObservation(mergeResult.snapshot, completedCommitId),
          summary: '本机和云端已经一致，已确认本机内容可用。'
        };
      }
      if (!localApplyRequired && !remoteWriteRequired) {
        await this.recordSuccessfulSync(
          remoteKind,
          mergeResult.snapshot,
          historyPlan.history,
          completedCommitId,
          true,
          'bookmark',
          completedPendingBookmarkSyncAt
        );
        return {
          commitId: completedCommitId,
          merged: false,
          blocked: false,
          conflictCount: 0,
          localChangeCount: 0,
          remoteChangeCount: 0,
          conflictDetails: [],
          remoteObservation: this.buildBookmarkRemoteObservation(mergeResult.snapshot, completedCommitId),
          summary: '本机和云端已经一致，已确认本机内容可用。'
        };
      }
    }
    await this.workThrottle.beforeMainThreadWrite();
    const writeResult = await this.runBookmarkStage(
      'remote_commit',
      () => store.writeState({
        snapshot: mergeResult.snapshot,
        history: historyPlan.history,
        deviceId: mergeResult.snapshot.meta.deviceId,
        parentCommitId: remoteState.commitId,
        createdAt: mergeResult.snapshot.meta.generatedAt
      })
    );
    await this.runBookmarkStage(
      'remote_confirmation',
      (): Promise<void> => this.confirmRemoteBookmarkCommit(
        store,
        remoteKind,
        writeResult.commitId,
        mergeResult.snapshot,
        historyPlan.history
      )
    );
    if (this.shouldApplyMergedBookmarkSnapshotToLocal(settings, mergeResult)) {
      const applyResult = await this.runBookmarkStage(
        'local_apply',
        () => this.bookmarkSnapshotService.applyBookmarkSnapshotToLocalDb(mergeResult.snapshot)
      );
      if (applyResult.blocked) {
        return {
          commitId: writeResult.commitId,
          merged: false,
          blocked: true,
          conflictCount: mergeResult.conflictCount,
          localChangeCount: mergeResult.localChangeCount,
          remoteChangeCount: mergeResult.remoteChangeCount,
          conflictDetails: mergeResult.conflictDetails,
          remoteObservation: null,
          summary: applyResult.summary
        };
      }
      await this.runBookmarkStage('local_apply', (): Promise<void> => {
        return this.assertBookmarkSnapshotMaterializedLocally(mergeResult.snapshot);
      });
    }
    await this.recordSuccessfulSync(
      remoteKind,
      mergeResult.snapshot,
      historyPlan.history,
      writeResult.commitId,
      true,
      'bookmark',
      completedPendingBookmarkSyncAt
    );
    return {
      commitId: writeResult.commitId,
      merged: true,
      blocked: false,
      conflictCount: 0,
      localChangeCount: mergeResult.localChangeCount,
      remoteChangeCount: mergeResult.remoteChangeCount,
      conflictDetails: [],
      remoteObservation: this.buildBookmarkRemoteObservation(mergeResult.snapshot, writeResult.commitId),
      summary: this.buildRemoteWriteSummary(remoteKind, mergeResult.summary)
    };
  }

  private isHuaweiSpaceBookmarkWriteConflict(remoteKind: AiraSyncRemoteKind, error: Error): boolean {
    if (remoteKind !== 'huawei_space') {
      return false;
    }
    return this.stringifyError(error).indexOf(HUAWEI_SPACE_BOOKMARK_WRITE_CONFLICT_MESSAGE) === 0;
  }

  private buildHuaweiBookmarkIdentityNoOpProbe(
    remoteKind: AiraSyncRemoteKind,
    intent: AiraBookmarkSyncIntent,
    conservativeMerge: boolean,
    settings: AiraSyncSettings,
    baseline?: AiraSyncBaselineRecord
  ): AiraBookmarkIdentityNoOpProbe {
    const snapshot = baseline?.snapshot ?? null;
    return {
      remoteKind: remoteKind,
      intent: intent,
      conservativeMerge: conservativeMerge,
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt ?? 0,
      baselineCommitId: baseline?.commitId ?? '',
      baselineFolderCount: snapshot === null ? 0 : snapshot.bookmarkFolders.length,
      baselineItemCount: snapshot === null ? 0 : snapshot.bookmarkItems.length,
      hasBaselineSnapshot: snapshot !== null
    };
  }

  private async tryHuaweiBookmarkIdentityNoOp(
    store: AiraSyncRemoteStore,
    remoteKind: AiraSyncRemoteKind,
    probe: AiraBookmarkIdentityNoOpProbe,
    baseline: AiraSyncBaselineRecord,
    completedPendingBookmarkSyncAt: number
  ): Promise<AiraBookmarkMergeSyncResult | undefined> {
    if (store.readHead === undefined || baseline.snapshot === null) {
      return undefined;
    }
    const readHead = store.readHead;
    let head: AiraSyncRemoteHead;
    try {
      head = await readHead();
    } catch (_error) {
      return undefined;
    }
    if (!this.bookmarkIdentityNoOpService.matchesConfirmedHead(probe, head)) {
      AiraSyncJankProbe.markExtra(
        'bookmark_identity_noop',
        `hit=0 commit=${head.commitId ?? ''} baseline=${probe.baselineCommitId}`
      );
      return undefined;
    }
    AiraSyncJankProbe.markExtra('bookmark_identity_noop', `hit=1 commit=${probe.baselineCommitId}`);
    const snapshot = baseline.snapshot;
    const commitId = baseline.commitId;
    await this.recordSuccessfulSync(
      remoteKind,
      snapshot,
      baseline.history,
      commitId,
      true,
      'bookmark',
      completedPendingBookmarkSyncAt
    );
    hilog.info(
      0x0000,
      'AiraBookmarkSync',
      'Huawei bookmark identity no-op commit=%{public}s folders=%{public}d items=%{public}d',
      commitId,
      probe.baselineFolderCount,
      probe.baselineItemCount
    );
    return {
      commitId: commitId,
      merged: false,
      blocked: false,
      conflictCount: 0,
      localChangeCount: 0,
      remoteChangeCount: 0,
      conflictDetails: [],
      remoteObservation: this.buildBookmarkRemoteObservation(snapshot, commitId),
      summary: '本机和云端已经一致，已确认本机内容可用。'
    };
  }

  private async readRemoteHeadSafely(store: AiraSyncRemoteStore): Promise<AiraSyncRemoteHead | undefined> {
    if (store.readHead === undefined) {
      return undefined;
    }
    try {
      return await store.readHead();
    } catch (_error) {
      return undefined;
    }
  }

  private async resolveLocalSnapshotForMerge(
    settings: AiraSyncSettings,
    baseline?: AiraSyncBaselineRecord
  ): Promise<AiraSyncSnapshot> {
    return this.buildFreshAiraBookmarkSnapshot(
      this.shouldPreferCachedLocalSnapshot(settings),
      baseline?.snapshot
    );
  }

  private async confirmRemoteBookmarkCommit(
    store: AiraSyncRemoteStore,
    remoteKind: AiraSyncRemoteKind,
    expectedCommitId: string,
    expectedSnapshot: AiraSyncSnapshot,
    expectedHistory: AiraBookmarkHistoryDescriptor
  ): Promise<void> {
    if (remoteKind === 'huawei_space') {
      AiraSyncJankProbe.markExtra('bookmark_confirm', 'mode=write-already-confirmed');
      return;
    }
    const confirmed = this.projectRemoteStateForBookmarkSync(await store.readState());
    if (confirmed.snapshot === null || confirmed.commitId !== expectedCommitId || confirmed.history === null ||
      !this.bookmarkHistoryService.sameHistory(confirmed.history, expectedHistory) ||
      !this.bookmarkMergeService.sameSnapshotContent(confirmed.snapshot, expectedSnapshot)) {
      throw new Error(`${this.resolveRemoteLabel(remoteKind)}未能确认完整的书签提交。`);
    }
  }

  private async confirmPendingRemoteWrites(
    settings: AiraSyncSettings,
    store: AiraSyncRemoteStore,
    remoteKind: AiraSyncRemoteKind
  ): Promise<void> {
    if (settings.bookmarkSyncEnabled !== true || remoteKind !== 'huawei_space' ||
      settings.remoteKind !== 'huawei_space' ||
      (settings.pendingBookmarkSyncAt ?? 0) <= 0 || store.confirmPendingWrites === undefined) {
      return;
    }
    AiraSyncJankProbe.markExtra('bookmark_confirm_pending', 'skip=write-will-time-first');
    await this.workThrottle.afterStage();
  }

  private assertHuaweiPendingRemoteStatusReadable(settings: AiraSyncSettings): void {
    if (settings.bookmarkSyncEnabled === true && settings.remoteKind === 'huawei_space' &&
      (settings.pendingBookmarkSyncAt ?? 0) > 0) {
      throw new Error('华为云空间书签仍在等待上传确认，暂时无法确认远端状态。');
    }
  }

  private shouldPreferCachedLocalSnapshot(settings: AiraSyncSettings): boolean {
    return (settings.pendingBookmarkSyncAt ?? 0) > 0;
  }

  private resolveTargetMergeIntentForActiveMerge(
    settings: AiraSyncSettings,
    activeProvider: AiraSyncProviderKind
  ): AiraBookmarkTargetMergeIntent {
    if (isAiraBookmarkProviderTransition(settings.remoteKind, activeProvider)) {
      return 'provider-switch';
    }
    const providerSwitchFrom = settings.pendingBookmarkProviderSwitchFrom ?? 'none';
    if ((settings.pendingBookmarkSyncAt ?? 0) > 0 && settings.remoteKind === activeProvider &&
      isAiraBookmarkProviderTransition(providerSwitchFrom, activeProvider)) {
      return 'provider-switch';
    }
    return 'ordinary';
  }

  private buildRemoteWriteSummary(remoteKind: AiraSyncRemoteKind, detail: string): string {
    if (remoteKind === 'huawei_space') {
      return `已保存到华为云空间同步库，等待系统云空间同步：${detail}`;
    }
    return `同步完成：${detail}`;
  }

  private async resolveBookmarkRemoteStateForMerge(
    store: AiraSyncRemoteStore,
    remoteKind: AiraSyncRemoteKind,
    identityProbe: AiraBookmarkIdentityNoOpProbe,
    baseline: AiraSyncBaselineRecord | undefined
  ): Promise<AiraSyncRemoteState> {
    if (remoteKind === 'huawei_space' && store.readHead !== undefined && baseline !== undefined &&
      baseline.snapshot !== null && baseline.commitId.trim().length > 0) {
      try {
        const head = await store.readHead();
        if (this.bookmarkIdentityNoOpService.matchesConfirmedHead(identityProbe, head)) {
          AiraSyncJankProbe.markExtra('bookmark_baseline_remote', 'hit=1');
          return {
            snapshot: baseline.snapshot,
            commitId: baseline.commitId,
            history: baseline.history
          };
        }
      } catch (_error) {
      }
    }
    AiraSyncJankProbe.markExtra('bookmark_baseline_remote', 'hit=0');
    return this.projectRemoteStateForBookmarkSync(await store.readState());
  }

  private reconcileRemoteStateForMerge(
    remoteKind: AiraSyncRemoteKind,
    baseline: AiraSyncBaselineRecord | undefined,
    remoteState: AiraSyncRemoteState
  ): AiraSyncRemoteState {
    if (remoteKind !== 'huawei_space' || baseline === undefined) {
      return remoteState;
    }
    if (remoteState.snapshot !== null && remoteState.commitId !== null) {
      return remoteState;
    }
    const baselineSnapshot = this.projectSnapshotForChromeSync(baseline.snapshot);
    if (baselineSnapshot === null || baseline.commitId.trim().length <= 0) {
      throw new Error('华为云空间同步状态暂时不可确认，已保留本机书签和待同步变更。请确认华为账号与系统云空间同步可用后再试。');
    }
    return {
      snapshot: baselineSnapshot,
      commitId: baseline.commitId,
      history: baseline.history
    };
  }

  private shouldApplyMergedBookmarkSnapshotToLocal(
    settings: AiraSyncSettings,
    mergeResult: AiraBookmarkMergeResult
  ): boolean {
    return (settings.bookmarkGenerationInitializedAt ?? 0) <= 0 ||
      mergeResult.localApplyRequired;
  }

  private async assertBookmarkSnapshotMaterializedLocally(expectedSnapshot: AiraSyncSnapshot): Promise<void> {
    const actualSnapshot = await this.bookmarkSnapshotService.buildFreshBookmarkSnapshot(
      expectedSnapshot.meta.deviceId
    );
    if (!this.bookmarkMergeService.sameLocalMaterializationContent(actualSnapshot, expectedSnapshot)) {
      throw new Error('本地书签落地校验未通过，未更新同步基线或完成待同步状态。');
    }
  }

  private canRecoverMissingBaselineFromMatchingRemote(
    localSnapshot: AiraSyncSnapshot,
    remoteSnapshot: AiraSyncSnapshot
  ): boolean {
    if (localSnapshot.meta.deviceId !== remoteSnapshot.meta.deviceId) {
      return false;
    }
    return this.bookmarkMergeService.sameSnapshotContent(localSnapshot, remoteSnapshot);
  }

  private resolveMaterializedLocalSnapshotForDecision(
    localSnapshot: AiraSyncSnapshot,
    baselineSnapshot: AiraSyncSnapshot | null
  ): AiraSyncSnapshot {
    if (baselineSnapshot !== null &&
      this.bookmarkMergeService.sameLocalMaterializationContent(localSnapshot, baselineSnapshot)) {
      return baselineSnapshot;
    }
    return localSnapshot;
  }

  readAiraSyncBaselineForKind(remoteKind: AiraSyncRemoteKind): Promise<AiraSyncBaselineRecord | undefined> {
    return this.requireSyncConfigStore().readBaseline(this.resolveProviderId(remoteKind));
  }

  saveAiraRemoteStatusCacheForKind(
    remoteKind: AiraSyncRemoteKind,
    cache: AiraSyncRemoteStatusCache
  ): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().saveRemoteStatusCacheForKind(remoteKind, cache);
  }

  markBookmarkSyncPending(changedAt: number = Date.now()): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().markBookmarkSyncPending(changedAt);
  }

  setBookmarkSyncEnabled(enabled: boolean): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().setBookmarkSyncEnabled(enabled);
  }

  beginHuaweiBookmarkInitialization(changedAt: number = Date.now()): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().beginHuaweiBookmarkInitialization(changedAt);
  }

  clearBookmarkSyncPending(expectedPendingAt: number): Promise<AiraSyncSettings> {
    return this.requireSyncConfigStore().clearBookmarkSyncPending(expectedPendingAt);
  }

  private async readAiraRemoteSummary(
    settings: AiraSyncSettings,
    store: AiraSyncRemoteStore,
    remoteKind: AiraSyncRemoteKind,
    remoteLabel: string
  ): Promise<AiraSyncStatusSummary> {
    const remoteHead = await this.readRemoteHeadSafely(store);
    if (remoteHead !== undefined && remoteHead.commitId === null) {
      return {
        providerId: this.resolveProviderId(remoteKind),
        enabled: this.isRemoteKindEnabled(settings, remoteKind),
        remoteKind: remoteKind,
        rootPath: AIRA_SYNC_DEFAULT_ROOT,
        baselineCommitId: remoteHead.commitId ?? '',
        lastSuccessAt: this.resolveLastSuccessAt(settings, remoteKind),
        localBookmarkFolders: 0,
        localBookmarkItems: 0,
        summary: `${remoteLabel} 还没有书签同步状态。`
      };
    }
    if (remoteHead !== undefined && remoteHead.hasBookmarkSummary) {
      return {
        providerId: this.resolveProviderId(remoteKind),
        enabled: this.isRemoteKindEnabled(settings, remoteKind),
        remoteKind: remoteKind,
        rootPath: AIRA_SYNC_DEFAULT_ROOT,
        baselineCommitId: remoteHead.commitId ?? '',
        lastSuccessAt: this.resolveLastSuccessAt(settings, remoteKind),
        localBookmarkFolders: remoteHead.bookmarkFolders,
        localBookmarkItems: remoteHead.bookmarkItems,
        summary: `${remoteLabel} commit=${remoteHead.commitId ?? ''}，包含 ${remoteHead.bookmarkFolders} 个文件夹和 ${remoteHead.bookmarkItems} 个书签。`
      };
    }
    const remoteState = this.projectRemoteStateForBookmarkSync(await store.readState());
    const remoteCounts = this.countVisibleBookmarkEntities(remoteState.snapshot);
    return {
      providerId: this.resolveProviderId(remoteKind),
      enabled: this.isRemoteKindEnabled(settings, remoteKind),
      remoteKind: remoteKind,
      rootPath: AIRA_SYNC_DEFAULT_ROOT,
      baselineCommitId: remoteState.commitId ?? '',
      lastSuccessAt: this.resolveLastSuccessAt(settings, remoteKind),
      localBookmarkFolders: remoteCounts.folders,
      localBookmarkItems: remoteCounts.items,
      summary: remoteState.snapshot === null
        ? `${remoteLabel} 还没有书签同步状态。`
        : `${remoteLabel} commit=${remoteState.commitId}，包含 ${remoteCounts.folders} 个文件夹和 ${remoteCounts.items} 个书签。`
    };
  }

  private countVisibleBookmarkEntities(snapshot: AiraSyncSnapshot | null): AiraVisibleBookmarkCounts {
    if (snapshot === null) {
      return {
        folders: 0,
        items: 0
      };
    }
    const deletedFolderIds = this.buildDeletedEntityIdSet(snapshot.tombstones, 'bookmark-folder');
    const deletedItemIds = this.buildDeletedEntityIdSet(snapshot.tombstones, 'bookmark-item');
    const reachableIds = this.collectReachableBookmarkEntityIds(snapshot, deletedFolderIds, deletedItemIds);
    return {
      folders: reachableIds.folders.size,
      items: reachableIds.items.size
    };
  }

  private projectRemoteStateForBookmarkSync(state: AiraSyncRemoteState): AiraSyncRemoteState {
    return {
      snapshot: this.projectSnapshotForChromeSync(state.snapshot),
      commitId: state.commitId,
      history: state.history
    };
  }

  private projectSnapshotForChromeSync(snapshot: AiraSyncSnapshot | null): AiraSyncSnapshot | null {
    if (snapshot === null) {
      return null;
    }
    const deletedFolderIds = this.buildDeletedEntityIdSet(snapshot.tombstones, 'bookmark-folder');
    const deletedItemIds = this.buildDeletedEntityIdSet(snapshot.tombstones, 'bookmark-item');
    const foldersById = new Map<string, AiraSyncBookmarkFolderEntity>();
    snapshot.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      if (!deletedFolderIds.has(folder.id)) {
        foldersById.set(folder.id, folder);
      }
    });
    const itemsById = new Map<string, AiraSyncBookmarkItemEntity>();
    snapshot.bookmarkItems.forEach((item: AiraSyncBookmarkItemEntity) => {
      if (!deletedItemIds.has(item.id)) {
        itemsById.set(item.id, item);
      }
    });
    const ordersByParent = new Map<string, string[]>();
    snapshot.bookmarkOrders.forEach((order: AiraSyncBookmarkOrder) => {
      ordersByParent.set(order.parentId === null ? AIRA_SYNC_ROOT_ORDER_KEY : order.parentId, order.ids.slice());
    });

    const keptFolderIds = new Set<string>();
    const keptItemIds = new Set<string>();
    AIRA_CHROME_SYNC_ROOT_IDS.forEach((rootId: string) => {
      this.collectChromeSyncSnapshotEntityIds(rootId, foldersById, itemsById, ordersByParent, keptFolderIds, keptItemIds);
    });
    const keptIds = new Set<string>();
    keptFolderIds.forEach((id: string) => keptIds.add(id));
    keptItemIds.forEach((id: string) => keptIds.add(id));

    const bookmarkFolders = snapshot.bookmarkFolders.filter((folder: AiraSyncBookmarkFolderEntity) => keptFolderIds.has(folder.id));
    const bookmarkItems = snapshot.bookmarkItems.filter((item: AiraSyncBookmarkItemEntity) => keptItemIds.has(item.id));
    const bookmarkOrders = snapshot.bookmarkOrders
      .map((order: AiraSyncBookmarkOrder): AiraSyncBookmarkOrder => {
        const orderKey = order.parentId === null ? AIRA_SYNC_ROOT_ORDER_KEY : order.parentId;
        const allowedRootOrderIds = orderKey === AIRA_SYNC_ROOT_ORDER_KEY
          ? AIRA_CHROME_SYNC_ROOT_IDS
          : order.ids;
        return {
          type: order.type,
          parentId: order.parentId,
          ids: allowedRootOrderIds.filter((id: string) => keptIds.has(id)),
          updatedAt: order.updatedAt,
          updatedBy: order.updatedBy,
          revision: order.revision
        };
      })
      .filter((order: AiraSyncBookmarkOrder) => {
        if (order.parentId === null) {
          return order.ids.length > 0;
        }
        return keptFolderIds.has(order.parentId);
      });
    const tombstones = this.filterChromeSyncSnapshotTombstones(snapshot.tombstones);

    return {
      meta: snapshot.meta,
      bookmarkFolders: bookmarkFolders,
      bookmarkItems: bookmarkItems,
      bookmarkOrders: bookmarkOrders,
      tombstones: tombstones,
      appPrivateBookmarks: snapshot.appPrivateBookmarks
    };
  }

  private collectChromeSyncSnapshotEntityIds(
    parentKey: string,
    foldersById: Map<string, AiraSyncBookmarkFolderEntity>,
    itemsById: Map<string, AiraSyncBookmarkItemEntity>,
    ordersByParent: Map<string, string[]>,
    keptFolderIds: Set<string>,
    keptItemIds: Set<string>
  ): void {
    if (foldersById.has(parentKey)) {
      keptFolderIds.add(parentKey);
    }
    const ids = ordersByParent.get(parentKey) ?? [];
    ids.forEach((id: string) => {
      if (foldersById.has(id)) {
        if (keptFolderIds.has(id)) {
          return;
        }
        keptFolderIds.add(id);
        this.collectChromeSyncSnapshotEntityIds(id, foldersById, itemsById, ordersByParent, keptFolderIds, keptItemIds);
        return;
      }
      if (itemsById.has(id)) {
        keptItemIds.add(id);
      }
    });
  }

  private filterChromeSyncSnapshotTombstones(tombstones: AiraSyncTombstone[]): AiraSyncTombstone[] {
    return tombstones.filter((entry: AiraSyncTombstone) => {
      return entry.type === 'bookmark-folder' || entry.type === 'bookmark-item';
    });
  }

  private collectReachableBookmarkEntityIds(
    snapshot: AiraSyncSnapshot,
    deletedFolderIds: Set<string>,
    deletedItemIds: Set<string>
  ): AiraReachableBookmarkEntityIds {
    const foldersById = new Map<string, AiraSyncBookmarkFolderEntity>();
    snapshot.bookmarkFolders.forEach((folder: AiraSyncBookmarkFolderEntity) => {
      if (!deletedFolderIds.has(folder.id)) {
        foldersById.set(folder.id, folder);
      }
    });
    const itemsById = new Map<string, AiraSyncBookmarkItemEntity>();
    snapshot.bookmarkItems.forEach((item: AiraSyncBookmarkItemEntity) => {
      if (!deletedItemIds.has(item.id)) {
        itemsById.set(item.id, item);
      }
    });
    const ordersByParent = new Map<string, string[]>();
    snapshot.bookmarkOrders.forEach((order: AiraSyncBookmarkOrder) => {
      ordersByParent.set(order.parentId === null ? AIRA_SYNC_ROOT_ORDER_KEY : order.parentId, order.ids.slice());
    });

    const result: AiraReachableBookmarkEntityIds = {
      folders: new Set<string>(),
      items: new Set<string>()
    };
    this.collectReachableBookmarkEntityIdsForParent(
      AIRA_SYNC_ROOT_ORDER_KEY,
      foldersById,
      itemsById,
      ordersByParent,
      result
    );
    return result;
  }

  private collectReachableBookmarkEntityIdsForParent(
    parentKey: string,
    foldersById: Map<string, AiraSyncBookmarkFolderEntity>,
    itemsById: Map<string, AiraSyncBookmarkItemEntity>,
    ordersByParent: Map<string, string[]>,
    result: AiraReachableBookmarkEntityIds
  ): void {
    const ids = ordersByParent.get(parentKey) ?? [];
    ids.forEach((id: string) => {
      if (foldersById.has(id)) {
        if (result.folders.has(id)) {
          return;
        }
        result.folders.add(id);
        this.collectReachableBookmarkEntityIdsForParent(id, foldersById, itemsById, ordersByParent, result);
        return;
      }
      if (itemsById.has(id)) {
        result.items.add(id);
      }
    });
  }

  private buildDeletedEntityIdSet(tombstones: AiraSyncTombstone[], type: string): Set<string> {
    const deletedIds = new Set<string>();
    tombstones.forEach((entry: AiraSyncTombstone) => {
      if (entry.type === type) {
        deletedIds.add(entry.id);
      }
    });
    return deletedIds;
  }

  private requireSyncConfigStore(): AiraSyncConfigStore {
    if (this.syncConfigStore === undefined) {
      throw new Error('Aira sync config store is not configured.');
    }
    return this.syncConfigStore;
  }

  private resolveLocalSyncSourceId(): string {
    const settings = this.requireSyncConfigStore().getSettings();
    const sourceId = (settings.sourceId ?? '').trim();
    return sourceId.length > 0 ? sourceId : 'aira-browser-local';
  }

  private assertWebdavConfigured(settings: AiraSyncSettings): void {
    if (settings.webdav.endpoint.trim().length === 0) {
      throw new Error('请先填写 WebDAV 服务器地址。');
    }
  }

  private assertCloudConfigured(settings: AiraSyncSettings): void {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud'));
    }
    if (settings.huaweiCloud.uid.trim().length === 0) {
      throw new Error('请先使用华为账号开启书签同步。');
    }
  }

  private assertHuaweiSpaceConfigured(settings: AiraSyncSettings): void {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_space'));
    }
    if (settings.huaweiSpace.uid.trim().length === 0) {
      throw new Error('请先使用华为账号开启华为云空间同步。');
    }
  }

  private assertPersonalServerConfigured(settings: AiraSyncSettings): void {
    AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.requireConfigured(settings);
  }

  private assertRemoteKindConfigured(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): void {
    if (remoteKind === 'aira_cloud') {
      this.assertCloudConfigured(settings);
      return;
    }
    if (remoteKind === 'huawei_space') {
      this.assertHuaweiSpaceConfigured(settings);
      return;
    }
    if (remoteKind === 'webdav') {
      this.assertWebdavConfigured(settings);
      return;
    }
    if (remoteKind === 'self_hosted') {
      this.assertPersonalServerConfigured(settings);
      return;
    }
    throw new Error('不支持的同步方式。');
  }

  private isRemoteKindConfigured(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): boolean {
    if (remoteKind === 'aira_cloud') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud') &&
        settings.huaweiCloud.uid.trim().length > 0;
    }
    if (remoteKind === 'huawei_space') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space') &&
        settings.huaweiSpace.uid.trim().length > 0;
    }
    if (remoteKind === 'webdav') {
      return settings.webdav.endpoint.trim().length > 0;
    }
    if (remoteKind === 'self_hosted') {
      try {
        this.assertPersonalServerConfigured(settings);
        return true;
      } catch (_error) {
        return false;
      }
    }
    return false;
  }

  private createRemoteStoreForKind(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): AiraSyncRemoteStore {
    if (remoteKind === 'aira_cloud') {
      return this.createHuaweiCloudRemoteStore(settings);
    }
    if (remoteKind === 'huawei_space') {
      return this.createHuaweiSpaceRemoteStore(settings);
    }
    if (remoteKind === 'webdav') {
      return this.createWebdavRemoteStore(settings);
    }
    if (remoteKind === 'self_hosted') {
      return this.createPersonalServerRemoteStore(settings);
    }
    throw new Error('不支持的同步源。');
  }

  private readHuaweiCloudRemoteSummary(settings: AiraSyncSettings): Promise<AiraSyncStatusSummary> {
    if (settings.huaweiCloud.uid.trim().length === 0) {
      return Promise.reject(new Error('请先使用华为账号开启书签同步。'));
    }
    return this.readAiraRemoteSummary(settings, this.createHuaweiCloudRemoteStore(settings), 'aira_cloud', 'Aira 云同步');
  }

  private createHuaweiCloudRemoteStore(settings: AiraSyncSettings): AiraSyncRemoteStore {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud'));
    }
    return this.huaweiCloudRemoteStoreFactory(settings);
  }

  private createBlockedMergeResult(mergeResult: AiraBookmarkMergeResult): AiraBookmarkMergeSyncResult {
    return {
      commitId: '',
      merged: false,
      blocked: true,
      conflictCount: mergeResult.conflictCount,
      localChangeCount: mergeResult.localChangeCount,
      remoteChangeCount: mergeResult.remoteChangeCount,
      conflictDetails: mergeResult.conflictDetails,
      remoteObservation: null,
      summary: mergeResult.summary
    };
  }

  private buildBookmarkRemoteObservation(
    snapshot: AiraSyncSnapshot,
    commitId: string
  ): AiraBookmarkSyncRemoteObservation {
    const counts = this.countVisibleBookmarkEntities(snapshot);
    return {
      commitId: commitId,
      bookmarkFolders: counts.folders,
      bookmarkItems: counts.items
    };
  }

  private async saveBookmarkSyncCompletion(
    remoteKind: AiraSyncProviderKind,
    result: AiraBookmarkMergeSyncResult
  ): Promise<AiraSyncSettings> {
    const observation = result.remoteObservation;
    if (observation === null || observation.commitId !== result.commitId) {
      throw new Error('书签同步完成结果缺少已确认的远端状态。');
    }
    return this.requireSyncConfigStore().saveBookmarkSyncCompletion(remoteKind, observation);
  }

  private async recordSuccessfulSync(
    remoteKind: AiraSyncRemoteKind,
    snapshot: AiraSyncSnapshot,
    history: AiraBookmarkHistoryDescriptor,
    commitId: string,
    initializeBookmarkGeneration: boolean = true,
    runtimeDomain: 'bookmark' | 'bookmark_backup' = 'bookmark',
    completedPendingBookmarkSyncAt: number = 0
  ): Promise<void> {
    const providerId = this.resolveProviderId(remoteKind);
    const baseline = await this.requireSyncConfigStore().readBaseline(providerId);
    const baselineMatches = baseline !== undefined && baseline.snapshot !== null &&
      baseline.commitId === commitId &&
      this.bookmarkHistoryService.sameHistory(baseline.history, history) &&
      this.bookmarkMergeService.sameSnapshotContent(baseline.snapshot, snapshot);
    if (!baselineMatches) {
      await this.requireSyncConfigStore().writeBaseline(
        commitId,
        snapshot,
        history,
        providerId
      );
    }
    const settingsForNativeActivation = this.getAiraSyncSettings();
    const nativeAiraCloudGeneration = shouldAcknowledgeNativeAiraCloudBookmarkV4Activation(
      remoteKind,
      settingsForNativeActivation.remoteKind,
      settingsForNativeActivation.bookmarkGenerationInitializedAt ?? 0,
      initializeBookmarkGeneration
    );
    if (initializeBookmarkGeneration) {
      await this.requireSyncConfigStore().markBookmarkGenerationInitialized();
    }
    if (nativeAiraCloudGeneration && this.nativeAiraCloudGenerationHandler !== undefined) {
      const uid = this.getAiraSyncSettings().huaweiCloud.uid.trim();
      if (uid.length > 0) {
        await this.nativeAiraCloudGenerationHandler(uid, commitId);
      }
    }
    if (runtimeDomain === 'bookmark') {
      await this.bookmarkHistoryService.confirm(history);
      await this.bookmarkSnapshotService.purgeBookmarkTombstonesBefore(history.retainedFrom);
    }
    const currentSettings = this.getAiraSyncSettings();
    if (runtimeDomain === 'bookmark') {
      if (!this.isRemoteKindEnabled(currentSettings, remoteKind)) {
        return;
      }
      if (this.shouldClearBookmarkSyncPendingAfterProviderSuccess(currentSettings)) {
        await this.requireSyncConfigStore().clearBookmarkSyncPending(completedPendingBookmarkSyncAt);
      }
      return;
    }
    await this.requireSyncConfigStore().saveProviderRuntimeState(
      remoteKind as AiraSyncProviderKind,
      'healthy',
      '',
      true,
      runtimeDomain
    );
  }

  private shouldClearBookmarkSyncPendingAfterProviderSuccess(settings: AiraSyncSettings): boolean {
    return this.resolveEnabledRemoteKinds(settings).length <= 1;
  }

  private resolveEnabledRemoteKinds(settings: AiraSyncSettings): AiraSyncRemoteKind[] {
    const result: AiraSyncRemoteKind[] = [];
    if (settings.remoteKind !== 'none' && this.isRemoteKindEnabled(settings, settings.remoteKind)) {
      result.push(settings.remoteKind);
    }
    this.resolveBackupRemoteKinds(settings).forEach((kind: AiraSyncProviderKind) => {
      if (result.indexOf(kind) < 0 && this.isRemoteKindEnabled(settings, kind)) {
        result.push(kind);
      }
    });
    return result;
  }

  private resolveActiveProviderForSync(settings: AiraSyncSettings): AiraSyncProviderKind {
    const activeProvider = settings.remoteKind;
    if (activeProvider === 'aira_cloud' || activeProvider === 'huawei_space' || activeProvider === 'webdav' ||
      activeProvider === 'self_hosted') {
      if (this.isRemoteKindEnabled(settings, activeProvider)) {
        return activeProvider;
      }
    }
    throw new Error('请先选择并配置当前同步方式。');
  }

  private resolveActiveProviderForConfiguredSettings(settings: AiraSyncSettings): AiraSyncProviderKind {
    const activeProvider = settings.remoteKind;
    if ((activeProvider === 'aira_cloud' || activeProvider === 'huawei_space' || activeProvider === 'webdav' ||
      activeProvider === 'self_hosted') &&
      this.isRemoteKindConfigured(settings, activeProvider)) {
      return activeProvider;
    }
    throw new Error('请先选择并配置当前同步方式。');
  }

  private resolveBackupRemoteKinds(settings: AiraSyncSettings): AiraSyncProviderKind[] {
    const result: AiraSyncProviderKind[] = [];
    const backups = settings.additionalBackupRemoteKinds ?? [];
    backups.forEach((kind: AiraSyncProviderKind) => {
      if (kind !== settings.remoteKind && this.isRemoteKindEnabled(settings, kind) && result.indexOf(kind) < 0) {
        result.push(kind);
      }
    });
    return result;
  }

  private isRemoteKindEnabled(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): boolean {
    return remoteKind !== 'none' &&
      isAiraSyncProviderEnabled(settings, remoteKind) &&
      this.isRemoteKindConfigured(settings, remoteKind);
  }

  private resolveProviderId(remoteKind: AiraSyncRemoteKind): string {
    return this.requireSyncConfigStore().getProviderId(remoteKind);
  }

  private resolveLastSuccessAt(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): number {
    if (remoteKind === 'none') {
      return 0;
    }
    return resolveAiraSyncProviderRuntimeState(settings, remoteKind).bookmark.lastSuccessAt;
  }

  private resolveRemoteLabel(remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'aira_cloud') {
      return '书签云同步';
    }
    if (remoteKind === 'huawei_space') {
      return '华为云空间';
    }
    if (remoteKind === 'webdav') {
      return 'WebDAV';
    }
    if (remoteKind === 'self_hosted') {
      return '个人服务器';
    }
    return '同步服务';
  }

  private async runBookmarkStage<T>(
    stage: AiraBookmarkSyncFailureStage,
    operation: () => Promise<T>
  ): Promise<T> {
    try {
      return await operation();
    } catch (error) {
      throw this.ensureBookmarkStageError(error as Error, stage);
    }
  }

  private ensureBookmarkStageError(
    error: Error,
    fallbackStage: AiraBookmarkSyncFailureStage
  ): AiraBookmarkSyncStageError {
    if (error instanceof AiraBookmarkSyncStageError) {
      return error;
    }
    return new AiraBookmarkSyncStageError(
      this.createBookmarkSyncFailure(fallbackStage),
      error
    );
  }

  private createBookmarkConflictFailure(): AiraBookmarkSyncFailure {
    return {
      code: 'BKM-CONFLICT-001',
      stage: 'merge',
      safeDetail: '检测到需要确认的书签冲突，已保留本机和云端内容。请按页面提示处理。'
    };
  }

  private createBookmarkSyncFailure(stage: AiraBookmarkSyncFailureStage): AiraBookmarkSyncFailure {
    if (stage === 'authentication') {
      return {
        code: 'BKM-AUTH-001',
        stage: stage,
        safeDetail: '同步账号或同步源配置尚未通过校验，请重新确认账号状态和同步设置。'
      };
    }
    if (stage === 'network') {
      return {
        code: 'BKM-NETWORK-001',
        stage: stage,
        safeDetail: '网络请求未完成，请检查网络后重试。'
      };
    }
    if (stage === 'remote_read_validation') {
      return {
        code: 'BKM-REMOTE-READ-001',
        stage: stage,
        safeDetail: '无法读取或校验同步源中的书签快照，已停止后续写入以保护书签。'
      };
    }
    if (stage === 'local_snapshot') {
      return {
        code: 'BKM-LOCAL-SNAPSHOT-001',
        stage: stage,
        safeDetail: '无法生成或读取本机书签快照，尚未向同步源写入数据。'
      };
    }
    if (stage === 'merge') {
      return {
        code: 'BKM-MERGE-001',
        stage: stage,
        safeDetail: '书签合并未完成，已保留本机和同步源中的现有内容。'
      };
    }
    if (stage === 'remote_commit') {
      return {
        code: 'BKM-REMOTE-WRITE-001',
        stage: stage,
        safeDetail: '书签提交到同步源时未完成，本机内容和待同步状态已保留。'
      };
    }
    if (stage === 'remote_confirmation') {
      return {
        code: 'BKM-REMOTE-CONFIRM-001',
        stage: stage,
        safeDetail: '同步源未能确认完整提交，本次同步不会标记为成功。'
      };
    }
    if (stage === 'local_apply') {
      return {
        code: 'BKM-LOCAL-APPLY-001',
        stage: stage,
        safeDetail: '合并结果未能完整写入并校验到本机，本次同步不会标记为成功。'
      };
    }
    return {
      code: 'BKM-UNKNOWN-001',
      stage: 'unknown',
      safeDetail: '书签同步在未识别的阶段中断，请重试并向客服提供错误码。'
    };
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }

  private createWebdavRemoteStore(settings: AiraSyncSettings): AiraSyncRemoteStore {
    return this.webdavRemoteStoreFactory(settings);
  }

  private createPersonalServerRemoteStore(settings: AiraSyncSettings): AiraSyncRemoteStore {
    return this.personalServerRemoteStoreFactory(settings);
  }

  private createHuaweiSpaceRemoteStore(settings: AiraSyncSettings): AiraSyncRemoteStore {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_space'));
    }
    return this.huaweiSpaceRemoteStoreFactory(settings);
  }

  private stripBookmarkTombstones(snapshot: AiraSyncSnapshot): AiraSyncSnapshot {
    const result: AiraSyncSnapshot = {
      meta: {
        version: snapshot.meta.version,
        deviceId: snapshot.meta.deviceId,
        generatedAt: snapshot.meta.generatedAt
      },
      bookmarkFolders: snapshot.bookmarkFolders.slice(),
      bookmarkItems: snapshot.bookmarkItems.slice(),
      bookmarkOrders: snapshot.bookmarkOrders.slice(),
      tombstones: []
    };
    if (snapshot.appPrivateBookmarks !== undefined) {
      result.appPrivateBookmarks = {
        bookmarkFolders: snapshot.appPrivateBookmarks.bookmarkFolders.slice(),
        bookmarkItems: snapshot.appPrivateBookmarks.bookmarkItems.slice(),
        bookmarkOrders: snapshot.appPrivateBookmarks.bookmarkOrders.slice(),
        tombstones: []
      };
    }
    return result;
  }
}
