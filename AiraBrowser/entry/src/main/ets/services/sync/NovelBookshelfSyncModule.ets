import {
  NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT
} from '../../common/constants/SyncFlowErrorCodes';
import {
  AiraSyncProviderKind,
  AiraSyncSettings,
  resolveAiraHuaweiAccountIdentity
} from '../../common/models/AiraSyncModels';
import {
  NovelBookshelfSyncRemoteState,
  NovelBookshelfSyncRemoteStore,
  NovelBookshelfSyncRunResult,
  NovelBookshelfSyncSelectionState,
  NovelBookshelfSyncSnapshot
} from '../../common/models/NovelBookshelfSyncModels';
import { NovelLibraryRepository } from '../../data/novel/NovelLibraryRepository';
import { NovelReadingCheckpointRepository } from '../../data/novel/NovelReadingCheckpointRepository';
import {
  NovelBookshelfSyncLineageRole,
  NovelBookshelfSyncLineageState,
  NovelBookshelfSyncStateStore
} from '../../data/sync/NovelBookshelfSyncStateStore';
import { HuaweiSpaceNovelBookshelfSyncStore } from '../../data/sync/HuaweiSpaceNovelBookshelfSyncStore';
import { WebdavNovelBookshelfSyncStore } from '../../data/sync/WebdavNovelBookshelfSyncStore';
import { AiraCloudNovelBookshelfRemoteStore } from './AiraCloudNovelBookshelfRemoteStore';
import {
  NovelBookshelfSyncMergeIntent,
  NovelBookshelfSyncMergeResult,
  NovelBookshelfSyncMergeService
} from './NovelBookshelfSyncMergeService';
import { NovelBookshelfSyncSnapshotService } from './NovelBookshelfSyncSnapshotService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AIRA_PERSONAL_SERVER_INSTANCE_SERVICE } from './AiraPersonalServerInstanceService';

const NOVEL_BOOKSHELF_SYNC_WRITE_MAX_ATTEMPTS: number = 3;

export type NovelBookshelfSyncRemoteStoreFactory = (
  remoteKind: AiraSyncProviderKind,
  settings: AiraSyncSettings
) => NovelBookshelfSyncRemoteStore;

export class NovelBookshelfSyncModule {
  private readonly repository: NovelLibraryRepository;
  private readonly checkpointRepository: NovelReadingCheckpointRepository;
  private readonly stateStore: NovelBookshelfSyncStateStore;
  private readonly snapshotService: NovelBookshelfSyncSnapshotService;
  private readonly mergeService: NovelBookshelfSyncMergeService;
  private readonly remoteStoreFactory: NovelBookshelfSyncRemoteStoreFactory;

  constructor(
    repository: NovelLibraryRepository,
    stateStore: NovelBookshelfSyncStateStore,
    checkpointRepository: NovelReadingCheckpointRepository,
    snapshotService: NovelBookshelfSyncSnapshotService = new NovelBookshelfSyncSnapshotService(),
    mergeService?: NovelBookshelfSyncMergeService,
    remoteStoreFactory?: NovelBookshelfSyncRemoteStoreFactory
  ) {
    this.repository = repository;
    this.stateStore = stateStore;
    this.checkpointRepository = checkpointRepository;
    this.snapshotService = snapshotService;
    this.mergeService = mergeService ?? new NovelBookshelfSyncMergeService(snapshotService);
    this.remoteStoreFactory = remoteStoreFactory ?? ((remoteKind: AiraSyncProviderKind, settings: AiraSyncSettings) => {
      if (remoteKind === 'webdav') {
        return new WebdavNovelBookshelfSyncStore(settings.webdav);
      }
      if (remoteKind === 'huawei_space') {
        return new HuaweiSpaceNovelBookshelfSyncStore(
          settings.huaweiSpace.uid,
          settings.huaweiSpace.databaseName
        );
      }
      if (remoteKind === 'self_hosted') {
        return AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.createNovelBookshelfStore(settings);
      }
      return new AiraCloudNovelBookshelfRemoteStore(settings.huaweiCloud.uid);
    });
  }

  async initialize(activeProviderPresent: boolean): Promise<NovelBookshelfSyncSelectionState> {
    await this.stateStore.initialize();
    const current: NovelBookshelfSyncSelectionState = this.stateStore.getSelection(activeProviderPresent);
    if (current.initialized) {
      return current;
    }
    return this.stateStore.setSelection(current.enabled);
  }

  getSelection(activeProviderPresent: boolean): NovelBookshelfSyncSelectionState {
    return this.stateStore.getSelection(activeProviderPresent);
  }

  setSelection(enabled: boolean): Promise<NovelBookshelfSyncSelectionState> {
    return this.stateStore.setSelection(enabled);
  }

  async buildLocalSnapshot(deviceId: string): Promise<NovelBookshelfSyncSnapshot> {
    const localState = await this.repository.readSyncLocalState();
    const checkpoints = await this.checkpointRepository.listSyncable();
    return this.snapshotService.buildLocalSnapshot(deviceId, localState, checkpoints);
  }

  async sync(
    remoteKind: AiraSyncProviderKind,
    settings: AiraSyncSettings,
    deviceId: string,
    role: NovelBookshelfSyncLineageRole = 'active',
    mergeIntent: NovelBookshelfSyncMergeIntent = 'ordinary'
  ): Promise<NovelBookshelfSyncRunResult> {
    if (remoteKind === 'aira_cloud' && !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud'));
    }
    if (remoteKind === 'huawei_space' && !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_space'));
    }
    await this.stateStore.initialize();
    const remoteStore: NovelBookshelfSyncRemoteStore = this.remoteStoreFactory(remoteKind, settings);
    let completedResult: NovelBookshelfSyncMergeResult | undefined = undefined;
    let completedRevision: string = '';
    for (let attempt: number = 0; attempt < NOVEL_BOOKSHELF_SYNC_WRITE_MAX_ATTEMPTS; attempt += 1) {
      const remoteState: NovelBookshelfSyncRemoteState = await this.readValidatedRemoteState(remoteStore, '同步源');
      const localSnapshot: NovelBookshelfSyncSnapshot = await this.buildLocalSnapshot(deviceId);
      const mergeResult: NovelBookshelfSyncMergeResult = this.mergeRemoteHeads(
        localSnapshot,
        remoteState,
        mergeIntent
      );
      if (!mergeResult.shouldUpload) {
        completedResult = mergeResult;
        completedRevision = remoteState.revision;
        break;
      }
      try {
        const writeResult = await remoteStore.writeSnapshot(deviceId, mergeResult.snapshot, remoteState.revision);
        completedResult = mergeResult;
        const writtenRevision = this.requireRevision(writeResult.revision, '同步源');
        const confirmedState = await this.confirmRemoteSnapshot(
          remoteStore,
          mergeResult.snapshot,
          writtenRevision,
          '同步源'
        );
        completedRevision = confirmedState.revision;
        break;
      } catch (error) {
        const message: string = this.stringifyError(error as Error);
        if (message !== NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT ||
          attempt + 1 >= NOVEL_BOOKSHELF_SYNC_WRITE_MAX_ATTEMPTS) {
          throw new Error(message);
        }
      }
    }
    if (completedResult === undefined) {
      throw new Error('小说书架并发更新较多，请稍后重试。');
    }
    if (completedResult.shouldApplyLocal) {
      await this.repository.applySyncedBookshelf(
        this.snapshotService.toLocalBooks(completedResult.snapshot),
        this.snapshotService.toLocalTombstones(completedResult.snapshot)
      );
      await this.checkpointRepository.applySynced(
        this.snapshotService.toLocalReadingCheckpoints(completedResult.snapshot)
      );
    }
    await this.stateStore.saveLineage(
      remoteKind,
      role,
      this.buildProviderIdentity(remoteKind, settings),
      completedRevision
    );
    return {
      appliedRemoteCount: completedResult.appliedRemoteCount,
      uploaded: completedResult.shouldUpload,
      snapshot: completedResult.snapshot,
      revision: completedRevision
    };
  }

  async writeBackup(
    remoteKind: AiraSyncProviderKind,
    settings: AiraSyncSettings,
    deviceId: string,
    snapshot: NovelBookshelfSyncSnapshot
  ): Promise<void> {
    await this.stateStore.initialize();
    const remoteStore: NovelBookshelfSyncRemoteStore = this.remoteStoreFactory(remoteKind, settings);
    const remoteState: NovelBookshelfSyncRemoteState = await this.readValidatedRemoteState(
      remoteStore,
      '附加备份位置'
    );
    if (remoteState.snapshot !== null && this.snapshotService.sameContent(remoteState.snapshot, snapshot)) {
      await this.stateStore.saveLineage(
        remoteKind,
        'backup',
        this.buildProviderIdentity(remoteKind, settings),
        remoteState.revision
      );
      return;
    }
    const writeResult = await remoteStore.writeSnapshot(deviceId, snapshot, remoteState.revision);
    const writtenRevision = this.requireRevision(writeResult.revision, '附加备份位置');
    const confirmedState = await this.confirmRemoteSnapshot(
      remoteStore,
      snapshot,
      writtenRevision,
      '附加备份位置'
    );
    await this.stateStore.saveLineage(
      remoteKind,
      'backup',
      this.buildProviderIdentity(remoteKind, settings),
      confirmedState.revision
    );
  }

  private mergeRemoteHeads(
    localSnapshot: NovelBookshelfSyncSnapshot,
    remoteState: NovelBookshelfSyncRemoteState,
    intent: NovelBookshelfSyncMergeIntent = 'ordinary'
  ): NovelBookshelfSyncMergeResult {
    const headSnapshots: NovelBookshelfSyncSnapshot[] =
      Array.isArray(remoteState.headSnapshots) && remoteState.headSnapshots.length > 0
        ? remoteState.headSnapshots
        : (remoteState.snapshot === null ? [] : [remoteState.snapshot]);
    if (headSnapshots.length <= 0) {
      return this.mergeService.merge(localSnapshot, null, intent);
    }
    let aggregate: NovelBookshelfSyncMergeResult = this.mergeService.merge(
      localSnapshot,
      headSnapshots[0],
      intent
    );
    let appliedRemoteCount: number = aggregate.appliedRemoteCount;
    let shouldApplyLocal: boolean = aggregate.shouldApplyLocal;
    let shouldUpload: boolean = aggregate.shouldUpload || headSnapshots.length > 1;
    for (let index: number = 1; index < headSnapshots.length; index += 1) {
      aggregate = this.mergeService.merge(aggregate.snapshot, headSnapshots[index], intent);
      appliedRemoteCount += aggregate.appliedRemoteCount;
      shouldApplyLocal = shouldApplyLocal || aggregate.shouldApplyLocal;
      shouldUpload = shouldUpload || aggregate.shouldUpload;
    }
    return {
      snapshot: aggregate.snapshot,
      appliedRemoteCount: appliedRemoteCount,
      shouldApplyLocal: shouldApplyLocal,
      shouldUpload: shouldUpload
    };
  }

  private async readValidatedRemoteState(
    store: NovelBookshelfSyncRemoteStore,
    sourceLabel: string
  ): Promise<NovelBookshelfSyncRemoteState> {
    const state: NovelBookshelfSyncRemoteState = await store.readState();
    const revision: string = state.revision.trim();
    if ((state.snapshot === null) !== (revision.length <= 0)) {
      throw new Error(`${sourceLabel}返回的小说书架快照和版本标识不完整。`);
    }
    if (state.snapshot !== null) {
      this.snapshotService.validate(state.snapshot, sourceLabel);
    }
    const heads: NovelBookshelfSyncSnapshot[] = state.headSnapshots ?? [];
    for (let index: number = 0; index < heads.length; index += 1) {
      this.snapshotService.validate(heads[index], sourceLabel);
    }
    return {
      snapshot: state.snapshot,
      revision: revision,
      headSnapshots: state.headSnapshots
    };
  }

  private buildProviderIdentity(remoteKind: AiraSyncProviderKind, settings: AiraSyncSettings): string {
    if (remoteKind === 'webdav') {
      return [
        'webdav',
        settings.webdav.endpoint.trim().replace(/\/+$/, ''),
        settings.webdav.username.trim(),
        'aira/g2/personalization/novel-bookshelf.json'
      ].join('|');
    }
    const uid: string = resolveAiraHuaweiAccountIdentity(
      settings.huaweiCloud,
      settings.huaweiSpace
    ).uid;
    if (remoteKind === 'huawei_space') {
      return ['huawei_space', uid, settings.huaweiSpace.databaseName.trim(), 'AiraG2NovelBookshelfCommits'].join('|');
    }
    if (remoteKind === 'self_hosted') {
      const config = AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.requireConfigured(settings);
      return ['self_hosted', config.instanceId, config.baseUrl, 'novel-bookshelf-v2'].join('|');
    }
    return ['aira_cloud', uid, 'novel-bookshelf-v2'].join('|');
  }

  private requireRevision(revision: string, sourceLabel: string): string {
    const normalized: string = revision.trim();
    if (normalized.length <= 0) {
      throw new Error(`${sourceLabel}没有返回小说书架条件写入版本标识。`);
    }
    return normalized;
  }

  private async confirmRemoteSnapshot(
    store: NovelBookshelfSyncRemoteStore,
    expectedSnapshot: NovelBookshelfSyncSnapshot,
    expectedRevision: string,
    sourceLabel: string
  ): Promise<NovelBookshelfSyncRemoteState> {
    const confirmedState: NovelBookshelfSyncRemoteState = await this.readValidatedRemoteState(store, sourceLabel);
    if (confirmedState.revision !== expectedRevision || confirmedState.snapshot === null ||
      !this.snapshotService.sameContent(confirmedState.snapshot, expectedSnapshot)) {
      throw new Error(`${sourceLabel}写入后未能回读确认完整的小说书架同步快照。`);
    }
    return confirmedState;
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }
}
