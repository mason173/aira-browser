import {
  PERSONALIZATION_SYNC_WRITE_CONFLICT,
  SYNC_ADDITIONAL_BACKUP_MERGE_REQUIRED
} from '../../common/constants/SyncFlowErrorCodes';
import {
  PERSONALIZATION_SYNC_ITEM_IDS,
  PersonalizationActivityHeatmapPayload,
  PersonalizationSyncConfig,
  PersonalizationSyncItemId,
  PersonalizationSyncItemSetting,
  PersonalizationSyncRemoteStore,
  PersonalizationSyncRemoteState,
  PersonalizationSyncRunResult,
  PersonalizationSyncSection,
  PersonalizationSyncSnapshot
} from '../../common/models/PersonalizationSyncModels';
import {
  AiraSyncProviderKind,
  AiraSyncSettings,
  resolveAiraHuaweiAccountIdentity,
  resolveAiraSyncDomainRuntimeState
} from '../../common/models/AiraSyncModels';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { PersonalizationSyncConfigStore } from '../../data/sync/PersonalizationSyncConfigStore';
import { AiraSyncConfigStore } from './AiraSyncConfigStore';
import { createAiraCloudPersonalizationRemoteStore } from './AiraCloudPersonalizationRemoteStore';
import {
  PersonalizationSyncMergeIntent,
  PersonalizationSyncSnapshotService
} from './PersonalizationSyncSnapshotService';
import { WebdavPersonalizationSyncStore } from '../../data/sync/WebdavPersonalizationSyncStore';
import { HuaweiSpacePersonalizationSyncStore } from '../../data/sync/HuaweiSpacePersonalizationSyncStore';
import { AiraSyncWorkThrottleService } from './AiraSyncWorkThrottleService';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';
import { SyncAdditionalBackupPolicyService } from './SyncAdditionalBackupPolicyService';
import { PersonalizationSyncSnapshotValidationService } from './PersonalizationSyncSnapshotValidationService';
import {
  NovelBookshelfSyncRunResult,
  NovelBookshelfSyncSelectionState,
  NovelBookshelfSyncSnapshot
} from '../../common/models/NovelBookshelfSyncModels';
import { NovelBookshelfSyncModule } from './NovelBookshelfSyncModule';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AIRA_PERSONAL_SERVER_INSTANCE_SERVICE } from './AiraPersonalServerInstanceService';

const PERSONALIZATION_SYNC_WRITE_MAX_ATTEMPTS: number = 3;

export type PersonalizationSyncRemoteStoreFactory = (
  remoteKind: AiraSyncProviderKind,
  settings: AiraSyncSettings
) => PersonalizationSyncRemoteStore;

export interface PersonalizationSyncOptions {
  allowWithoutActiveSync?: boolean;
  targetRemoteKind?: AiraSyncProviderKind;
  skipBackupWrites?: boolean;
  forceBackupWrites?: boolean;
}

export class PersonalizationSyncService {
  private configStore: PersonalizationSyncConfigStore;
  private syncConfigStore: AiraSyncConfigStore;
  private membershipFeature: MembershipFeature;
  private snapshotService: PersonalizationSyncSnapshotService;
  private remoteStoreFactory: PersonalizationSyncRemoteStoreFactory;
  private syncPromise?: Promise<PersonalizationSyncRunResult>;
  private syncPromiseAllowsWithoutActiveSync: boolean = false;
  private additionalBackupPolicyService: SyncAdditionalBackupPolicyService =
    new SyncAdditionalBackupPolicyService();
  private snapshotValidationService: PersonalizationSyncSnapshotValidationService =
    new PersonalizationSyncSnapshotValidationService();
  private novelBookshelfSyncModule?: NovelBookshelfSyncModule;
  private workThrottle: AiraSyncWorkThrottleService = new AiraSyncWorkThrottleService();

  constructor(
    configStore: PersonalizationSyncConfigStore,
    syncConfigStore: AiraSyncConfigStore,
    membershipFeature: MembershipFeature,
    snapshotService: PersonalizationSyncSnapshotService,
    remoteStoreFactory?: PersonalizationSyncRemoteStoreFactory,
    novelBookshelfSyncModule?: NovelBookshelfSyncModule
  ) {
    this.configStore = configStore;
    this.syncConfigStore = syncConfigStore;
    this.membershipFeature = membershipFeature;
    this.snapshotService = snapshotService;
    this.novelBookshelfSyncModule = novelBookshelfSyncModule;
    this.remoteStoreFactory = remoteStoreFactory ?? ((remoteKind: AiraSyncProviderKind, settings: AiraSyncSettings) => {
      if (remoteKind === 'webdav') {
        return new WebdavPersonalizationSyncStore(settings.webdav);
      }
      if (remoteKind === 'huawei_space') {
        return new HuaweiSpacePersonalizationSyncStore(
          settings.huaweiSpace.uid,
          settings.huaweiSpace.databaseName
        );
      }
      if (remoteKind === 'self_hosted') {
        return AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.createPersonalizationStore(settings);
      }
      return createAiraCloudPersonalizationRemoteStore(settings.huaweiCloud.uid);
    });
  }

  async buildLocalBackupSnapshot(): Promise<PersonalizationSyncSnapshot> {
    await this.configStore.initialize();
    const settings = await this.syncConfigStore.initialize();
    const config = this.buildLocalBackupConfig(this.configStore.getConfig());
    const snapshot = await this.snapshotService.buildLocalSnapshot(
      this.buildDeviceId(settings),
      config,
      Date.now(),
      this.resolveAccountUid(settings)
    );
    const activitySection = snapshot.sections.activity_heatmap;
    snapshot.sections.activity_heatmap = {
      enabled: true,
      updatedAt: activitySection.updatedAt,
      payload: this.snapshotService.buildLocalBackupActivityHeatmapPayload()
    };
    return this.snapshotValidationService.validate(snapshot, '本地备份');
  }

  async importLocalBackupSnapshot(snapshot: PersonalizationSyncSnapshot): Promise<number> {
    const incoming = this.snapshotValidationService.validate(snapshot, '本地备份');
    await this.configStore.initialize();
    const settings = await this.syncConfigStore.initialize();
    const config = this.buildLocalBackupConfig(this.configStore.getConfig());
    const deviceId = this.buildDeviceId(settings);
    const accountUid = this.resolveAccountUid(settings);
    const local = await this.snapshotService.buildLocalSnapshot(
      deviceId,
      config,
      Date.now(),
      accountUid
    );
    let appliedCount = 0;
    for (let index = 0; index < PERSONALIZATION_SYNC_ITEM_IDS.length; index += 1) {
      const id = PERSONALIZATION_SYNC_ITEM_IDS[index];
      const incomingSection = this.activatePortableSection(id, incoming.sections[id]);
      if (incomingSection === undefined) {
        continue;
      }
      const localSection = this.activatePortableSection(id, local.sections[id]);
      if (id === 'activity_heatmap') {
        await this.snapshotService.applyLocalBackupActivityHeatmapPayload(
          incomingSection.payload as PersonalizationActivityHeatmapPayload,
          accountUid
        );
        appliedCount += 1;
        continue;
      }
      let applyingSection = incomingSection;
      if (id !== 'core_preferences' && localSection !== undefined) {
        applyingSection = this.snapshotService.mergeLocalBackupSection(
          id,
          localSection,
          incomingSection
        ) ?? incomingSection;
      }
      await this.snapshotService.applySection(id, applyingSection, deviceId, accountUid);
      appliedCount += 1;
    }
    return appliedCount;
  }

  validateLocalBackupSnapshot(snapshot: PersonalizationSyncSnapshot): PersonalizationSyncSnapshot {
    return this.snapshotValidationService.validate(snapshot, '本地备份');
  }

  async syncNow(options: PersonalizationSyncOptions = {}): Promise<PersonalizationSyncRunResult> {
    const allowWithoutActiveSync = options.allowWithoutActiveSync === true;
    if (this.syncPromise !== undefined) {
      if ((allowWithoutActiveSync && !this.syncPromiseAllowsWithoutActiveSync) ||
        options.targetRemoteKind !== undefined || options.skipBackupWrites === true ||
        options.forceBackupWrites === true) {
        return this.syncPromise
          .catch((_error: Error) => this.buildResult(false, '个性化设置暂时未同步。', 0, false))
          .then(() => this.syncNow(options));
      }
      return this.syncPromise;
    }
    const promise = this.runSyncNow(options)
      .finally(() => {
        if (this.syncPromise === promise) {
          this.syncPromise = undefined;
          this.syncPromiseAllowsWithoutActiveSync = false;
        }
      });
    this.syncPromise = promise;
    this.syncPromiseAllowsWithoutActiveSync = allowWithoutActiveSync;
    return this.syncPromise;
  }

  buildCorePreferencesFingerprint(): string {
    return this.snapshotService.buildCorePreferencesFingerprint();
  }

  async initializeNovelBookshelfSelection(): Promise<NovelBookshelfSyncSelectionState> {
    await this.syncConfigStore.initialize();
    const settings: AiraSyncSettings = this.syncConfigStore.getSettings();
    if (this.novelBookshelfSyncModule === undefined) {
      return { initialized: true, enabled: false, updatedAt: 0 };
    }
    return this.novelBookshelfSyncModule.initialize(settings.remoteKind !== 'none');
  }

  async setNovelBookshelfSelection(enabled: boolean): Promise<NovelBookshelfSyncSelectionState> {
    const selection: NovelBookshelfSyncSelectionState = await this.initializeNovelBookshelfSelection();
    if (this.novelBookshelfSyncModule === undefined || selection.enabled === enabled) {
      return selection;
    }
    const settings: AiraSyncSettings = this.syncConfigStore.getSettings();
    if (enabled && settings.remoteKind !== 'none') {
      await this.assertProviderEligible(settings.remoteKind);
      await this.novelBookshelfSyncModule.sync(
        settings.remoteKind,
        settings,
        this.buildDeviceId(settings)
      );
    }
    return this.novelBookshelfSyncModule.setSelection(enabled);
  }

  async restoreNovelBookshelfSelection(enabled: boolean): Promise<NovelBookshelfSyncSelectionState> {
    await this.initializeNovelBookshelfSelection();
    if (this.novelBookshelfSyncModule === undefined) {
      return { initialized: true, enabled: false, updatedAt: 0 };
    }
    return this.novelBookshelfSyncModule.setSelection(enabled);
  }

  async syncToProvider(remoteKind: AiraSyncProviderKind): Promise<PersonalizationSyncRunResult> {
    const result = await this.syncNow({
      allowWithoutActiveSync: true,
      targetRemoteKind: remoteKind,
      skipBackupWrites: true
    });
    if (!result.ok) {
      throw new Error(result.message);
    }
    return result;
  }

  async writeAdditionalBackup(remoteKind: AiraSyncProviderKind): Promise<void> {
    await this.configStore.initialize();
    await this.syncConfigStore.initialize();
    const settings = this.syncConfigStore.getSettings();
    if (settings.personalizationSyncEnabled !== true) {
      return;
    }
    if (!this.isProviderConfigured(settings, remoteKind)) {
      throw new Error('目标同步方式尚未完成个性化同步配置。');
    }
    await this.assertProviderEligible(remoteKind);
    const currentResult = await this.syncNow({ skipBackupWrites: true });
    if (!currentResult.ok) {
      throw new Error(currentResult.message);
    }
    const currentSettings = this.syncConfigStore.getSettings();
    const activeProvider = this.resolveActiveProvider(currentSettings);
    if (activeProvider === undefined) {
      throw new Error('请先选择主同步方式。');
    }
    const activeRemoteStore = this.remoteStoreFactory(activeProvider, currentSettings);
    const activeRemoteState = await this.readValidatedRemoteState(activeRemoteStore, '当前同步方式');
    const remoteStore = this.remoteStoreFactory(remoteKind, currentSettings);
    const remoteState = await this.readValidatedRemoteState(remoteStore, '附加备份位置');
    const existingSnapshot = remoteState.snapshot;
    if (existingSnapshot !== null && !this.hasKnownBackupLineage(currentSettings, remoteKind, remoteState)) {
      throw new Error(SYNC_ADDITIONAL_BACKUP_MERGE_REQUIRED);
    }
    const config = this.configStore.getConfig();
    const deviceId = this.buildDeviceId(currentSettings);
    const localSnapshot = this.buildActiveProviderSnapshot(await this.snapshotService.buildLocalSnapshot(
      deviceId,
      config,
      Date.now(),
      this.resolveAccountUid(currentSettings)
    ));
    const activeMergeResult = await this.mergeRemoteHeads(localSnapshot, activeRemoteState, config);
    const snapshot = this.snapshotValidationService.validate(
      this.buildBackupSnapshot(activeMergeResult.snapshot, remoteState, config),
      '待写入附加备份的'
    );
    try {
      const writeResult = await remoteStore.writeSnapshot(deviceId, snapshot, remoteState.revision);
      const writtenRevision = this.requireConfirmedRevision(writeResult.revision, '附加备份位置');
      const confirmedState = await this.confirmRemoteSnapshot(
        remoteStore,
        snapshot,
        writtenRevision,
        '附加备份位置'
      );
      const completedRevision = confirmedState.revision;
      const bookshelfSelection: NovelBookshelfSyncSelectionState =
        await this.initializeNovelBookshelfSelection();
      if (bookshelfSelection.enabled && this.novelBookshelfSyncModule !== undefined) {
        await this.novelBookshelfSyncModule.writeBackup(
          remoteKind,
          currentSettings,
          deviceId,
          await this.novelBookshelfSyncModule.buildLocalSnapshot(deviceId)
        );
      }
      await this.syncConfigStore.saveProviderRuntimeState(
        remoteKind,
        'healthy',
        '',
        true,
        'personalization_backup',
        completedRevision
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      await this.syncConfigStore.saveProviderRuntimeState(
        remoteKind,
        'degraded',
        message,
        false,
        'personalization_backup'
      );
      throw new Error(message);
    }
  }

  private async runSyncNow(options: PersonalizationSyncOptions): Promise<PersonalizationSyncRunResult> {
    await this.configStore.initialize();
    await this.syncConfigStore.initialize();
    let settings = this.syncConfigStore.getSettings();
    if (settings.personalizationSyncEnabled !== true && options.allowWithoutActiveSync !== true) {
      return this.buildResult(false, '请先开启同步后再同步个性化设置。', 0, false);
    }
    const activeProvider = options.targetRemoteKind ?? this.resolveActiveProvider(settings);
    if (activeProvider === undefined) {
      return this.buildResult(false, '请先选择同步方式。', 0, false);
    }
    await this.assertProviderEligible(activeProvider);
    const mergeIntent: PersonalizationSyncMergeIntent = options.targetRemoteKind !== undefined &&
      settings.remoteKind !== 'none' && settings.remoteKind !== activeProvider
      ? 'provider-switch'
      : 'ordinary';
    let config = this.configStore.getConfig();
    const deviceId = this.buildDeviceId(settings);
    const remoteStore = this.remoteStoreFactory(activeProvider, settings);
    let mergeResult: PersonalizationSyncMergeResult | undefined = undefined;
    let bookshelfResult: NovelBookshelfSyncRunResult | undefined = undefined;
    let completedLocalSnapshot: PersonalizationSyncSnapshot | undefined = undefined;
    let completedRevision: string = '';
    try {
      for (let attempt = 0; attempt < PERSONALIZATION_SYNC_WRITE_MAX_ATTEMPTS; attempt += 1) {
        const remoteState = await this.readValidatedRemoteState(remoteStore, '同步源');
        await this.workThrottle.afterStage();
        config = this.configStore.getConfig();
        const localBaseSnapshot = await this.snapshotService.buildLocalSnapshot(
          deviceId,
          config,
          Date.now(),
          this.resolveAccountUid(settings)
        );
        completedLocalSnapshot = localBaseSnapshot;
        await this.workThrottle.afterStage();
        mergeResult = await this.mergeRemoteHeads(localBaseSnapshot, remoteState, config, mergeIntent);
        await this.workThrottle.afterStage();
        if (!mergeResult.shouldUpload) {
          completedRevision = remoteState.revision;
          break;
        }
        try {
          const outgoingSnapshot = this.snapshotValidationService.validate(
            mergeResult.snapshot,
            '待写入同步源的'
          );
          const writeResult = await remoteStore.writeSnapshot(
            deviceId,
            outgoingSnapshot,
            remoteState.revision
          );
          const writtenRevision = this.requireConfirmedRevision(writeResult.revision, '同步源');
          const confirmedState = await this.confirmRemoteSnapshot(
            remoteStore,
            outgoingSnapshot,
            writtenRevision,
            '同步源'
          );
          completedRevision = confirmedState.revision;
          break;
        } catch (error) {
          const message = error instanceof Error ? error.message : JSON.stringify(error);
          if (!this.isWriteConflict(new Error(message)) || attempt + 1 >= PERSONALIZATION_SYNC_WRITE_MAX_ATTEMPTS) {
            throw new Error(message);
          }
          mergeResult = undefined;
        }
      }
      if (mergeResult === undefined || completedLocalSnapshot === undefined) {
        throw new Error('个性化同步并发更新较多，请稍后重试。');
      }
      const completedMergeResult = mergeResult as PersonalizationSyncMergeResult;
      const localApplyItemIds = this.buildLocalApplyItemIds(
        completedLocalSnapshot,
        completedMergeResult.snapshot,
        config
      );
      if (localApplyItemIds.length > 0) {
        await this.applyMergedSnapshot(completedMergeResult.snapshot, localApplyItemIds);
      }
      if (localApplyItemIds.length > 0 || completedMergeResult.shouldUpload) {
        await this.configStore.saveSectionStates(
          this.snapshotService.buildLocalSectionStates(completedMergeResult.snapshot, config),
          Date.now(),
          this.snapshotService.buildLocalDeletionStates(completedMergeResult.snapshot, config)
        );
      }
      const bookshelfSelection: NovelBookshelfSyncSelectionState =
        await this.initializeNovelBookshelfSelection();
      if (bookshelfSelection.enabled && this.novelBookshelfSyncModule !== undefined) {
        bookshelfResult = await this.novelBookshelfSyncModule.sync(
          activeProvider,
          settings,
          deviceId,
          'active',
          mergeIntent
        );
      }
      await this.syncConfigStore.saveProviderRuntimeState(
        activeProvider,
        'healthy',
        '',
        true,
        'personalization',
        completedRevision
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      await this.syncConfigStore.saveProviderRuntimeState(activeProvider, 'unavailable', message, false, 'personalization');
      throw new Error(message);
    }
    const completedMergeResult = mergeResult as PersonalizationSyncMergeResult;
    const backupFailureCount = options.skipBackupWrites === true
      ? 0
      : await this.writeBackupSnapshots(
        settings,
        deviceId,
        completedMergeResult.snapshot,
        config,
        options.forceBackupWrites === true,
        bookshelfResult?.snapshot
      );
    const appliedRemoteCount: number = completedMergeResult.appliedRemoteCount +
      (bookshelfResult?.appliedRemoteCount ?? 0);
    const uploaded: boolean = completedMergeResult.shouldUpload || bookshelfResult?.uploaded === true;
    const legacyContentSelected: boolean = config.items.some((item): boolean => item.enabled);
    const syncedContentLabel: string = bookshelfResult === undefined
      ? '个性化设置'
      : (legacyContentSelected ? '个性化设置和小说书架' : '小说书架');
    const message = appliedRemoteCount > 0
      ? `已恢复 ${appliedRemoteCount} 项并完成同步。`
      : (uploaded ? `${syncedContentLabel}已同步。` : `${syncedContentLabel}已是最新。`);
    const finalMessage = backupFailureCount > 0
      ? `${message} ${backupFailureCount} 个附加备份位置暂未写入。`
      : message;
    return this.buildResult(
      true,
      finalMessage,
      appliedRemoteCount,
      uploaded
    );
  }

  private async mergeSnapshots(
    localSnapshot: PersonalizationSyncSnapshot,
    remoteSnapshot: PersonalizationSyncSnapshot | null,
    config: PersonalizationSyncConfig,
    preferRemoteWithoutBaseline: boolean = false,
    intent: PersonalizationSyncMergeIntent = 'ordinary'
  ): Promise<PersonalizationSyncMergeResult> {
    if (remoteSnapshot === null) {
      return {
        snapshot: this.buildActiveProviderSnapshot(localSnapshot),
        appliedRemoteCount: 0,
        shouldUpload: true
      };
    }
    const remoteNeedsCleanup = this.hasNonPortableRemoteContent(remoteSnapshot);
    const activeRemoteSnapshot = this.buildActiveProviderSnapshot(remoteSnapshot);
    const mergedSections: Record<string, PersonalizationSyncSection> = {};
    let appliedRemoteCount = 0;
    for (let index = 0; index < PERSONALIZATION_SYNC_ITEM_IDS.length; index += 1) {
      const id = PERSONALIZATION_SYNC_ITEM_IDS[index];
      const localSection = localSnapshot.sections[id];
      const remoteSection = activeRemoteSnapshot.sections[id];
      if (!this.isItemSelected(config, id)) {
        const preservedSection = this.preserveUnselectedSection(id, localSection, remoteSection, intent);
        if (preservedSection !== undefined) {
          mergedSections[id] = preservedSection;
        }
        continue;
      }
      const activeRemoteSection = this.activatePortableSection(id, remoteSection);
      if (localSection === undefined && remoteSection === undefined) {
        continue;
      }
      if (localSection !== undefined && activeRemoteSection !== undefined) {
        if (id === 'core_preferences') {
          const useRemote = this.shouldUseRemoteSection(
            id,
            localSection,
            activeRemoteSection,
            config,
            preferRemoteWithoutBaseline
          );
          const preferredSection = useRemote ? activeRemoteSection : localSection;
          const alternateSection = useRemote ? localSection : activeRemoteSection;
          const mergedSection = this.snapshotService.mergePreferredCorePreferencesSection(
            preferredSection,
            alternateSection
          );
          mergedSections[id] = mergedSection;
          if (useRemote) {
            appliedRemoteCount += 1;
          }
          continue;
        }
        const mergedSection = this.snapshotService.mergeConcurrentSection(
          id,
          localSection,
          activeRemoteSection,
          intent
        );
        if (mergedSection !== undefined) {
          mergedSections[id] = mergedSection;
          continue;
        }
      }
      if (activeRemoteSection !== undefined &&
        this.shouldUseRemoteSection(
          id,
          localSection,
          activeRemoteSection,
          config,
          preferRemoteWithoutBaseline
        )) {
        mergedSections[id] = activeRemoteSection;
        appliedRemoteCount += 1;
        continue;
      }
      if (localSection !== undefined) {
        mergedSections[id] = localSection;
      }
    }
    const snapshot: PersonalizationSyncSnapshot = {
      meta: localSnapshot.meta,
      sections: mergedSections,
      checksum: JSON.stringify(mergedSections)
    };
    const activeSnapshot = this.buildActiveProviderSnapshot(snapshot);
    const contentDiffers = !this.snapshotService.areSnapshotContentsEqual(activeSnapshot, activeRemoteSnapshot);
    return {
      snapshot: activeSnapshot,
      appliedRemoteCount: appliedRemoteCount,
      shouldUpload: contentDiffers || remoteNeedsCleanup
    };
  }

  private async mergeRemoteHeads(
    localSnapshot: PersonalizationSyncSnapshot,
    remoteState: PersonalizationSyncRemoteState,
    config: PersonalizationSyncConfig,
    intent: PersonalizationSyncMergeIntent = 'ordinary'
  ): Promise<PersonalizationSyncMergeResult> {
    const headSnapshots = Array.isArray(remoteState.headSnapshots) && remoteState.headSnapshots.length > 0
      ? remoteState.headSnapshots
      : (remoteState.snapshot === null ? [] : [remoteState.snapshot]);
    if (headSnapshots.length <= 0) {
      return this.mergeSnapshots(localSnapshot, null, config);
    }
    let aggregateSnapshot = localSnapshot;
    let appliedRemoteCount = 0;
    let shouldUpload = headSnapshots.length > 1;
    for (let index = 0; index < headSnapshots.length; index += 1) {
      const result = await this.mergeSnapshots(
        aggregateSnapshot,
        headSnapshots[index],
        config,
        index === 0,
        intent
      );
      aggregateSnapshot = result.snapshot;
      appliedRemoteCount += result.appliedRemoteCount;
      shouldUpload = shouldUpload || result.shouldUpload;
    }
    return {
      snapshot: aggregateSnapshot,
      appliedRemoteCount: appliedRemoteCount,
      shouldUpload: shouldUpload
    };
  }

  private shouldUseRemoteSection(
    id: PersonalizationSyncItemId,
    localSection: PersonalizationSyncSection | undefined,
    remoteSection: PersonalizationSyncSection,
    config: PersonalizationSyncConfig,
    preferRemoteWithoutBaseline: boolean
  ): boolean {
    if (localSection === undefined) {
      return true;
    }
    const localItem = config.items.find((item) => item.id === id);
    const localToggleExplicitAt = this.normalizeTimestamp(localItem?.updatedAt);
    if (preferRemoteWithoutBaseline && localToggleExplicitAt <= 0 &&
      config.sections.find((section) => section.id === id) === undefined) {
      return true;
    }
    return this.normalizeTimestamp(remoteSection.updatedAt) > this.normalizeTimestamp(localSection.updatedAt);
  }

  private preserveUnselectedSection(
    id: PersonalizationSyncItemId,
    localSection: PersonalizationSyncSection | undefined,
    remoteSection: PersonalizationSyncSection | undefined,
    intent: PersonalizationSyncMergeIntent = 'ordinary'
  ): PersonalizationSyncSection | undefined {
    if (localSection === undefined) {
      return remoteSection;
    }
    if (remoteSection === undefined) {
      return localSection;
    }
    const localContent = this.activatePortableSection(id, localSection);
    const remoteContent = this.activatePortableSection(id, remoteSection);
    if (localContent === undefined) {
      return remoteSection;
    }
    if (remoteContent === undefined) {
      return localSection;
    }
    const mergedSection = this.snapshotService.mergeConcurrentSection(id, localContent, remoteContent, intent);
    if (mergedSection !== undefined) {
      return mergedSection;
    }
    return this.normalizeTimestamp(remoteContent.updatedAt) > this.normalizeTimestamp(localContent.updatedAt)
      ? remoteContent
      : localContent;
  }

  private activatePortableSection(
    id: PersonalizationSyncItemId,
    section: PersonalizationSyncSection | undefined
  ): PersonalizationSyncSection | undefined {
    if (section === undefined) {
      return undefined;
    }
    if (section.enabled !== false) {
      return section;
    }
    if (!this.snapshotValidationService.canUseSectionAsEnabled(id, section)) {
      return undefined;
    }
    return {
      enabled: true,
      updatedAt: section.updatedAt,
      payload: section.payload
    };
  }

  private isItemSelected(config: PersonalizationSyncConfig, id: PersonalizationSyncItemId): boolean {
    const item = config.items.find((candidate) => candidate.id === id);
    return item === undefined || item.enabled !== false;
  }

  private async applyRemoteSection(
    id: PersonalizationSyncItemId,
    section: PersonalizationSyncSection
  ): Promise<void> {
    if (section.enabled === false) {
      return;
    }
    const settings = this.syncConfigStore.getSettings();
    await this.snapshotService.applySection(
      id,
      section,
      this.buildDeviceId(settings),
      this.resolveAccountUid(settings)
    );
  }

  private async applyMergedSnapshot(
    snapshot: PersonalizationSyncSnapshot,
    itemIds: PersonalizationSyncItemId[]
  ): Promise<void> {
    const startedAt = Date.now();
    AiraSyncJankProbe.markExtra('personalization_local_apply_start', `items=${itemIds.length}`);
    for (let index = 0; index < itemIds.length; index += 1) {
      const id = itemIds[index];
      const section = this.activatePortableSection(id, snapshot.sections[id]);
      if (section !== undefined) {
        await this.applyRemoteSection(id, section);
      }
    }
    AiraSyncJankProbe.endExtra('personalization_local_apply', startedAt, `items=${itemIds.length}`);
  }

  private buildLocalApplyItemIds(
    localSnapshot: PersonalizationSyncSnapshot,
    mergedSnapshot: PersonalizationSyncSnapshot,
    config: PersonalizationSyncConfig
  ): PersonalizationSyncItemId[] {
    const itemIds: PersonalizationSyncItemId[] = [];
    for (let index = 0; index < PERSONALIZATION_SYNC_ITEM_IDS.length; index += 1) {
      const id = PERSONALIZATION_SYNC_ITEM_IDS[index];
      if (!this.isItemSelected(config, id)) {
        continue;
      }
      const localSection = this.activatePortableSection(id, localSnapshot.sections[id]);
      const mergedSection = this.activatePortableSection(id, mergedSnapshot.sections[id]);
      const payloadSame = this.snapshotService.areSectionPayloadsEqual(id, localSection, mergedSection);
      const applyRequired = mergedSection !== undefined && !payloadSame;
      if (applyRequired) {
        itemIds.push(id);
      }
    }
    return itemIds;
  }

  private buildDeviceId(settings: AiraSyncSettings): string {
    const sourceId = `${settings.sourceId ?? ''}`.trim();
    return sourceId.length > 0 ? sourceId : 'aira-personalization-device';
  }

  private resolveActiveProvider(settings: AiraSyncSettings): AiraSyncProviderKind | undefined {
    const activeProvider = settings.remoteKind;
    if ((activeProvider === 'aira_cloud' && AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) ||
      activeProvider === 'webdav' ||
      activeProvider === 'self_hosted' ||
      (activeProvider === 'huawei_space' && AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space'))) {
      return activeProvider;
    }
    return undefined;
  }

  private isProviderConfigured(settings: AiraSyncSettings, remoteKind: AiraSyncProviderKind): boolean {
    if (remoteKind === 'aira_cloud') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud') &&
        settings.huaweiCloud.uid.trim().length > 0;
    }
    if (remoteKind === 'huawei_space') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space') &&
        settings.huaweiSpace.uid.trim().length > 0;
    }
    if (remoteKind === 'self_hosted') {
      try {
        AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.requireConfigured(settings);
        return true;
      } catch (_error) {
        return false;
      }
    }
    return settings.webdav.endpoint.trim().length > 0;
  }

  private async assertProviderEligible(remoteKind: AiraSyncProviderKind): Promise<void> {
    if (remoteKind === 'self_hosted') {
      AIRA_PERSONAL_SERVER_INSTANCE_SERVICE.requireConfigured(this.syncConfigStore.getSettings());
      return;
    }
    if (remoteKind !== 'aira_cloud') {
      if (remoteKind === 'huawei_space' && !AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
        throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_space'));
      }
      return;
    }
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud'));
    }
    await this.membershipFeature.refreshState({ force: false });
    if (this.membershipFeature.getState().plan !== 'pro') {
      throw new Error('Aira 云同步需要 Aira Pro；华为云空间和 WebDAV 个性化同步免费。');
    }
  }

  private async writeBackupSnapshots(
    settings: AiraSyncSettings,
    deviceId: string,
    snapshot: PersonalizationSyncSnapshot,
    config: PersonalizationSyncConfig,
    forceBackupWrites: boolean = false,
    bookshelfSnapshot?: NovelBookshelfSyncSnapshot
  ): Promise<number> {
    const backupKinds = settings.additionalBackupRemoteKinds ?? [];
    if (!this.additionalBackupPolicyService.shouldWriteBackups(
      settings,
      'personalization',
      forceBackupWrites
    )) {
      return 0;
    }
    let failureCount = 0;
    for (let index = 0; index < backupKinds.length; index += 1) {
      const remoteKind = backupKinds[index];
      try {
        await this.assertProviderEligible(remoteKind);
        const currentSettings = this.syncConfigStore.getSettings();
        const store = this.remoteStoreFactory(remoteKind, currentSettings);
        const remoteState = await this.readValidatedRemoteState(store, '附加备份位置');
        if (remoteState.snapshot !== null && !this.hasKnownBackupLineage(currentSettings, remoteKind, remoteState)) {
          throw new Error(SYNC_ADDITIONAL_BACKUP_MERGE_REQUIRED);
        }
        const backupSnapshot = this.snapshotValidationService.validate(
          this.buildBackupSnapshot(snapshot, remoteState, config),
          '待写入附加备份的'
        );
        const writeResult = await store.writeSnapshot(
          deviceId,
          backupSnapshot,
          remoteState.revision
        );
        const writtenRevision = this.requireConfirmedRevision(writeResult.revision, '附加备份位置');
        const confirmedState = await this.confirmRemoteSnapshot(
          store,
          backupSnapshot,
          writtenRevision,
          '附加备份位置'
        );
        const completedRevision = confirmedState.revision;
        if (bookshelfSnapshot !== undefined && this.novelBookshelfSyncModule !== undefined) {
          await this.novelBookshelfSyncModule.writeBackup(
            remoteKind,
            currentSettings,
            deviceId,
            bookshelfSnapshot
          );
        }
        await this.syncConfigStore.saveProviderRuntimeState(
          remoteKind,
          'healthy',
          '',
          true,
          'personalization_backup',
          completedRevision
        );
      } catch (error) {
        failureCount += 1;
        const message = error instanceof Error ? error.message : JSON.stringify(error);
        await this.syncConfigStore.saveProviderRuntimeState(
          remoteKind,
          'degraded',
          message,
          false,
          'personalization_backup'
        );
      }
    }
    return failureCount;
  }

  private normalizeTimestamp(value: number | undefined): number {
    const numberValue = Number(value ?? 0);
    if (!Number.isFinite(numberValue) || numberValue < 0) {
      return 0;
    }
    return Math.floor(numberValue);
  }

  private buildLocalBackupConfig(config: PersonalizationSyncConfig): PersonalizationSyncConfig {
    return {
      items: PERSONALIZATION_SYNC_ITEM_IDS.map((id: PersonalizationSyncItemId): PersonalizationSyncItemSetting => {
        const existing = config.items.find((item) => item.id === id);
        return {
          id: id,
          enabled: true,
          updatedAt: existing?.updatedAt ?? 0
        };
      }),
      sections: config.sections.slice(),
      deletions: config.deletions.slice(),
      lastSyncAt: Math.max(1, config.lastSyncAt),
      updatedAt: config.updatedAt
    };
  }

  private resolveAccountUid(settings: AiraSyncSettings): string {
    return resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid;
  }

  private isWriteConflict(error: Error): boolean {
    return error.message === PERSONALIZATION_SYNC_WRITE_CONFLICT;
  }

  private hasKnownBackupLineage(
    settings: AiraSyncSettings,
    remoteKind: AiraSyncProviderKind,
    remoteState: PersonalizationSyncRemoteState
  ): boolean {
    const snapshot = remoteState.snapshot;
    if (snapshot === null) {
      return false;
    }
    const providerIdentity = this.syncConfigStore.getProviderRuntimeIdentity(remoteKind, 'personalization');
    const backupState = resolveAiraSyncDomainRuntimeState(settings, remoteKind, 'personalization_backup');
    const activeState = resolveAiraSyncDomainRuntimeState(settings, remoteKind, 'personalization');
    const candidates = [backupState, activeState];
    return candidates.some((runtimeState): boolean => {
      if (runtimeState.lastSuccessAt <= 0 || runtimeState.providerIdentity !== providerIdentity) {
        return false;
      }
      const knownRevision = runtimeState.revision.trim();
      return knownRevision.length > 0 && knownRevision === remoteState.revision;
    });
  }

  private async readValidatedRemoteState(
    store: PersonalizationSyncRemoteStore,
    sourceLabel: string
  ): Promise<PersonalizationSyncRemoteState> {
    const state = await store.readState();
    const revision = state.revision.trim();
    if ((state.snapshot === null) !== (revision.length <= 0)) {
      throw new Error(`${sourceLabel}返回的个性化同步快照和版本标识不完整。`);
    }
    if (state.snapshot !== null) {
      this.snapshotValidationService.validate(state.snapshot, sourceLabel);
    }
    const headSnapshots = state.headSnapshots ?? [];
    for (let index = 0; index < headSnapshots.length; index += 1) {
      this.snapshotValidationService.validate(headSnapshots[index], sourceLabel);
    }
    return {
      snapshot: state.snapshot,
      revision: revision,
      headSnapshots: state.headSnapshots
    };
  }

  private requireConfirmedRevision(revision: string, sourceLabel: string): string {
    const normalized = revision.trim();
    if (normalized.length <= 0) {
      throw new Error(`${sourceLabel}没有返回可用于条件写入的个性化同步版本标识。`);
    }
    return normalized;
  }

  private async confirmRemoteSnapshot(
    store: PersonalizationSyncRemoteStore,
    expectedSnapshot: PersonalizationSyncSnapshot,
    expectedRevision: string,
    sourceLabel: string
  ): Promise<PersonalizationSyncRemoteState> {
    const confirmedState = await this.readValidatedRemoteState(store, sourceLabel);
    if (confirmedState.revision !== expectedRevision || confirmedState.snapshot === null ||
      !this.snapshotService.areSnapshotSectionsExactlyEqual(confirmedState.snapshot, expectedSnapshot)) {
      throw new Error(`${sourceLabel}写入后未能回读确认完整的个性化同步快照。`);
    }
    return confirmedState;
  }

  private buildActiveProviderSnapshot(snapshot: PersonalizationSyncSnapshot): PersonalizationSyncSnapshot {
    const sections: Record<string, PersonalizationSyncSection> = {};
    PERSONALIZATION_SYNC_ITEM_IDS.forEach((id: PersonalizationSyncItemId): void => {
      const activeSection = snapshot.sections[id];
      if (activeSection !== undefined) {
        sections[id] = this.snapshotService.sanitizeSectionForProvider(id, activeSection);
      }
    });
    return {
      meta: snapshot.meta,
      sections: sections,
      checksum: JSON.stringify(sections)
    };
  }

  private buildBackupSnapshot(
    snapshot: PersonalizationSyncSnapshot,
    remoteState: PersonalizationSyncRemoteState,
    config: PersonalizationSyncConfig
  ): PersonalizationSyncSnapshot {
    const activeSnapshot = this.buildActiveProviderSnapshot(snapshot);
    const sections: Record<string, PersonalizationSyncSection> = {};
    PERSONALIZATION_SYNC_ITEM_IDS.forEach((id: PersonalizationSyncItemId): void => {
      const section = activeSnapshot.sections[id];
      if (section !== undefined) {
        sections[id] = section;
      }
    });
    const remoteHeads = Array.isArray(remoteState.headSnapshots) && remoteState.headSnapshots.length > 0
      ? remoteState.headSnapshots
      : (remoteState.snapshot === null ? [] : [remoteState.snapshot]);
    remoteHeads.forEach((remoteSnapshot: PersonalizationSyncSnapshot): void => {
      const activeRemoteSnapshot = this.buildActiveProviderSnapshot(remoteSnapshot);
      PERSONALIZATION_SYNC_ITEM_IDS.forEach((id: PersonalizationSyncItemId): void => {
        const localSection = sections[id];
        const remoteSection = activeRemoteSnapshot.sections[id];
        if (this.isItemSelected(config, id) || remoteSection === undefined) {
          return;
        }
        const preservedSection = this.preserveUnselectedSection(id, localSection, remoteSection);
        if (preservedSection !== undefined) {
          sections[id] = preservedSection;
        }
      });
    });
    return {
      meta: activeSnapshot.meta,
      sections: sections,
      checksum: JSON.stringify(sections)
    };
  }

  private hasNonPortableRemoteContent(snapshot: PersonalizationSyncSnapshot): boolean {
    const sectionIds = Object.keys(snapshot.sections);
    if (sectionIds.some((id: string): boolean => {
      return PERSONALIZATION_SYNC_ITEM_IDS.indexOf(id as PersonalizationSyncItemId) < 0;
    })) {
      return true;
    }
    const activeSnapshot = this.buildActiveProviderSnapshot(snapshot);
    return PERSONALIZATION_SYNC_ITEM_IDS.some((id: PersonalizationSyncItemId): boolean => {
      return !this.snapshotService.isSectionCanonicalForProvider(id, snapshot.sections[id]);
    });
  }

  private buildResult(
    ok: boolean,
    message: string,
    appliedRemoteCount: number,
    uploaded: boolean
  ): PersonalizationSyncRunResult {
    return {
      ok: ok,
      message: message,
      appliedRemoteCount: appliedRemoteCount,
      uploaded: uploaded,
      syncedAt: Date.now()
    };
  }

}

interface PersonalizationSyncMergeResult {
  snapshot: PersonalizationSyncSnapshot;
  appliedRemoteCount: number;
  shouldUpload: boolean;
}
