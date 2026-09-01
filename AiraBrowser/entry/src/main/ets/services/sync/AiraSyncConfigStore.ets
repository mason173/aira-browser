import {
  AIRA_BOOKMARK_SYNC_PROTOCOL_ID,
  AIRA_SYNC_DEFAULT_ROOT,
  AiraAdditionalBackupIntervalDays,
  AiraBookmarkSyncFailure,
  AiraBookmarkSyncFailureStage,
  AiraBookmarkHistoryDescriptor,
  AiraBookmarkSyncRemoteObservation,
  AiraSyncDomainRuntimeState,
  AiraSyncBaselineRecord,
  AiraSyncDomainId,
  AiraSyncProviderHealth,
  AiraSyncProviderKind,
  AiraSyncProviderRuntimeState,
  AiraSyncRuntimeDomainId,
  AiraSyncRemoteKind,
  AiraSyncRemoteStatusCache,
  AiraSyncSettings,
  AiraSyncSnapshot,
  buildAiraHuaweiSpaceRemoteStatusProviderKey,
  buildAiraWebdavRemoteStatusProviderKey,
  createAiraSyncDomainRuntimeState,
  createDefaultAiraPersonalServerConfig,
  resolveAiraHuaweiAccountIdentity,
  resolveAiraPersonalServerConfig
} from '../../common/models/AiraSyncModels';

const DEFAULT_PROVIDER_ID = 'aira-webdav';
const AIRA_SYNC_SOURCE_ID_PREFIX = 'aira-sync-source';
export const AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME: string = 'aira_huawei_space_bookmarks_g2.db';

function createAiraSyncSourceId(): string {
  const timestamp = Date.now().toString(36);
  const randomPart = Math.floor(Math.random() * 0x100000000).toString(36);
  return `${AIRA_SYNC_SOURCE_ID_PREFIX}-${timestamp}-${randomPart}`;
}

export interface AiraSyncConfigStorageAdapter {
  readSettings(defaultValue: AiraSyncSettings): Promise<AiraSyncSettings>;
  writeSettings(settings: AiraSyncSettings): Promise<void>;
  readBaseline(providerId: string): Promise<AiraSyncBaselineRecord | undefined>;
  writeBaseline(record: AiraSyncBaselineRecord): Promise<void>;
}

export class AiraSyncConfigStore {
  private storageAdapter: AiraSyncConfigStorageAdapter;
  private cachedSettings: AiraSyncSettings = createDefaultAiraSyncSettings();
  private defaultSettings: AiraSyncSettings = createDefaultAiraSyncSettings();
  private initializationPromise?: Promise<AiraSyncSettings>;
  private initialized: boolean = false;
  private mutationTail: Promise<void> = Promise.resolve();

  constructor(storageAdapter: AiraSyncConfigStorageAdapter) {
    this.storageAdapter = storageAdapter;
  }

  getSettings(): AiraSyncSettings {
    return this.cachedSettings;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  async initialize(): Promise<AiraSyncSettings> {
    if (this.initialized) {
      return this.cachedSettings;
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.storageAdapter.readSettings(createDefaultAiraSyncSettings())
        .then((settings: AiraSyncSettings) => {
          this.cachedSettings = this.normalizeSettings(settings);
          this.initialized = true;
          return this.cachedSettings;
        })
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw new Error(`Aira sync config initialization failed: ${JSON.stringify(error)}`);
        });
    }
    return this.initializationPromise;
  }

  private async initializeForMutation(): Promise<void> {
    if (this.initialized) {
      return;
    }
    await this.initialize();
  }

  private async saveSettingsUnlocked(settings: AiraSyncSettings): Promise<AiraSyncSettings> {
    const normalized = this.normalizeSettings({
      sourceId: settings.sourceId ?? this.cachedSettings.sourceId ?? this.defaultSettings.sourceId,
      bookmarkGenerationInitializedAt: settings.bookmarkGenerationInitializedAt ??
        this.cachedSettings.bookmarkGenerationInitializedAt ?? 0,
      remoteKind: settings.remoteKind,
      bookmarkSyncEnabled: settings.bookmarkSyncEnabled ?? this.cachedSettings.bookmarkSyncEnabled ?? false,
      personalizationSyncEnabled: settings.personalizationSyncEnabled ??
        this.cachedSettings.personalizationSyncEnabled ?? false,
      providerStates: settings.providerStates ?? this.cachedSettings.providerStates ?? [],
      additionalBackupEnabled: settings.additionalBackupEnabled ??
        this.cachedSettings.additionalBackupEnabled ?? false,
      additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds ??
        this.cachedSettings.additionalBackupRemoteKinds ?? [],
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays ??
        this.cachedSettings.additionalBackupIntervalDays ?? 7,
      webdav: settings.webdav,
      huaweiCloud: settings.huaweiCloud,
      huaweiSpace: settings.huaweiSpace ?? this.cachedSettings.huaweiSpace ?? this.defaultSettings.huaweiSpace,
      selfHosted: settings.selfHosted ?? this.cachedSettings.selfHosted ?? this.defaultSettings.selfHosted,
      updatedAt: Date.now(),
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt ?? this.cachedSettings.pendingBookmarkSyncAt ?? 0,
      pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom ??
        this.cachedSettings.pendingBookmarkProviderSwitchFrom ?? 'none'
    });
    await this.storageAdapter.writeSettings(normalized);
    this.cachedSettings = normalized;
    this.initialized = true;
    return normalized;
  }

  private mutateSettings(
    updater: (settings: AiraSyncSettings) => AiraSyncSettings
  ): Promise<AiraSyncSettings> {
    const mutation = this.mutationTail.then(async (): Promise<AiraSyncSettings> => {
      await this.initializeForMutation();
      const current = this.cachedSettings;
      const next = updater(current);
      return next === current ? current : this.saveSettingsUnlocked(next);
    });
    this.mutationTail = mutation.then(
      (): void => {},
      (): void => {}
    );
    return mutation;
  }

  async markBookmarkSyncPending(changedAt: number = Date.now()): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const currentPendingAt = settings.pendingBookmarkSyncAt ?? 0;
      const requestedPendingAt = changedAt > 0 ? changedAt : Date.now();
      return {
        sourceId: settings.sourceId,
        remoteKind: settings.remoteKind,
        bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
        personalizationSyncEnabled: settings.personalizationSyncEnabled,
        providerStates: settings.providerStates,
        additionalBackupEnabled: settings.additionalBackupEnabled,
        additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
        additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
        webdav: settings.webdav,
        huaweiCloud: settings.huaweiCloud,
        huaweiSpace: settings.huaweiSpace,
        updatedAt: Date.now(),
        pendingBookmarkSyncAt: this.resolveNextPendingBookmarkSyncAt(currentPendingAt, requestedPendingAt),
        pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  private resolveNextPendingBookmarkSyncAt(currentPendingAt: number, requestedPendingAt: number): number {
    return requestedPendingAt > currentPendingAt ? requestedPendingAt : currentPendingAt + 1;
  }

  async clearBookmarkSyncPending(expectedPendingAt: number): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      if (expectedPendingAt <= 0 || (settings.pendingBookmarkSyncAt ?? 0) !== expectedPendingAt) {
        return settings;
      }
      return {
        sourceId: settings.sourceId,
        remoteKind: settings.remoteKind,
        bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
        personalizationSyncEnabled: settings.personalizationSyncEnabled,
        providerStates: settings.providerStates,
        additionalBackupEnabled: settings.additionalBackupEnabled,
        additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
        additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
        webdav: settings.webdav,
        huaweiCloud: settings.huaweiCloud,
        huaweiSpace: settings.huaweiSpace,
        updatedAt: Date.now(),
        pendingBookmarkSyncAt: 0,
        pendingBookmarkProviderSwitchFrom: 'none'
      };
    });
  }

  async markBookmarkGenerationInitialized(initializedAt: number = Date.now()): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      if ((settings.bookmarkGenerationInitializedAt ?? 0) > 0) {
        return settings;
      }
      return {
        sourceId: settings.sourceId,
        bookmarkGenerationInitializedAt: initializedAt > 0 ? initializedAt : Date.now(),
        remoteKind: settings.remoteKind,
        bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
        personalizationSyncEnabled: settings.personalizationSyncEnabled,
        providerStates: settings.providerStates,
        additionalBackupEnabled: settings.additionalBackupEnabled,
        additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
        additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
        webdav: settings.webdav,
        huaweiCloud: settings.huaweiCloud,
        huaweiSpace: settings.huaweiSpace,
        updatedAt: Date.now(),
        pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
        pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async setAdditionalBackupEnabled(enabled: boolean): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const backupKinds = settings.additionalBackupRemoteKinds ?? [];
      if (enabled && backupKinds.length <= 0) {
        throw new Error('请先选择至少一个备份位置。');
      }
      return {
      sourceId: settings.sourceId,
      remoteKind: settings.remoteKind,
      additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
      bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
      personalizationSyncEnabled: settings.personalizationSyncEnabled,
      providerStates: settings.providerStates,
      additionalBackupEnabled: enabled,
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
      webdav: settings.webdav,
      huaweiCloud: settings.huaweiCloud,
      huaweiSpace: settings.huaweiSpace,
      updatedAt: Date.now(),
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async setAdditionalBackupIntervalDays(days: AiraAdditionalBackupIntervalDays): Promise<AiraSyncSettings> {
    const normalizedDays = this.normalizeAdditionalBackupIntervalDays(days);
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => ({
      sourceId: settings.sourceId,
      remoteKind: settings.remoteKind,
      additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
      bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
      personalizationSyncEnabled: settings.personalizationSyncEnabled,
      providerStates: settings.providerStates,
      additionalBackupEnabled: settings.additionalBackupEnabled,
      additionalBackupIntervalDays: normalizedDays,
      webdav: settings.webdav,
      huaweiCloud: settings.huaweiCloud,
      huaweiSpace: settings.huaweiSpace,
      updatedAt: Date.now(),
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
    }));
  }

  async setBookmarkSyncEnabled(enabled: boolean): Promise<AiraSyncSettings> {
    return this.setSyncDomainEnabled('bookmarks', enabled);
  }

  async beginHuaweiBookmarkInitialization(changedAt: number = Date.now()): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      if (settings.remoteKind !== 'huawei_space' || settings.huaweiSpace.uid.trim().length <= 0) {
        throw new Error('请先选择并配置华为云空间同步。');
      }
      const now = Date.now();
      const pendingAt = this.resolveNextPendingBookmarkSyncAt(
        settings.pendingBookmarkSyncAt ?? 0,
        changedAt > 0 ? changedAt : now
      );
      const pendingSettings: AiraSyncSettings = {
        sourceId: settings.sourceId,
        remoteKind: settings.remoteKind,
        additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
        bookmarkSyncEnabled: true,
        personalizationSyncEnabled: settings.personalizationSyncEnabled,
        providerStates: settings.providerStates,
        additionalBackupEnabled: settings.additionalBackupEnabled,
        additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
        webdav: settings.webdav,
        huaweiCloud: settings.huaweiCloud,
        huaweiSpace: settings.huaweiSpace,
        updatedAt: now,
        pendingBookmarkSyncAt: pendingAt,
        pendingBookmarkProviderSwitchFrom: 'none'
      };
      return this.buildSettingsWithProviderRuntimeState(
        pendingSettings,
        'huawei_space',
        'idle',
        '',
        false,
        'bookmark',
        undefined,
        false,
        undefined,
        now
      );
    });
  }

  async prepareHuaweiSpaceBookmarkReenable(): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const activeHuaweiBookmark = settings.remoteKind === 'huawei_space' &&
        settings.bookmarkSyncEnabled === true;
      const backupKinds = settings.additionalBackupRemoteKinds ?? [];
      const huaweiBookmarkBackup = settings.bookmarkSyncEnabled === true &&
        backupKinds.indexOf('huawei_space') >= 0;
      if (!activeHuaweiBookmark && !huaweiBookmarkBackup) {
        return settings;
      }
      const previousHuaweiState = this.resolveProviderRuntimeStateForSettings(settings, 'huawei_space');
      const providerStates = (settings.providerStates ?? []).filter((state: AiraSyncProviderRuntimeState): boolean => {
        return state.remoteKind !== 'huawei_space';
      });
      providerStates.push({
        remoteKind: 'huawei_space',
        bookmark: activeHuaweiBookmark ? createAiraSyncDomainRuntimeState() : previousHuaweiState.bookmark,
        personalization: previousHuaweiState.personalization,
        bookmarkBackup: huaweiBookmarkBackup
          ? createAiraSyncDomainRuntimeState()
          : previousHuaweiState.bookmarkBackup,
        personalizationBackup: previousHuaweiState.personalizationBackup
      });
      const remainingBackupKinds = huaweiBookmarkBackup
        ? backupKinds.filter((kind: AiraSyncProviderKind): boolean => kind !== 'huawei_space')
        : backupKinds;
      return {
        sourceId: settings.sourceId,
        remoteKind: settings.remoteKind,
        bookmarkSyncEnabled: activeHuaweiBookmark ? false : settings.bookmarkSyncEnabled,
        personalizationSyncEnabled: settings.personalizationSyncEnabled,
        providerStates: providerStates,
        additionalBackupEnabled: remainingBackupKinds.length > 0 && settings.additionalBackupEnabled === true,
        additionalBackupRemoteKinds: remainingBackupKinds,
        additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
        webdav: settings.webdav,
        huaweiCloud: settings.huaweiCloud,
        huaweiSpace: {
          uid: settings.huaweiSpace.uid,
          displayName: settings.huaweiSpace.displayName,
          photoUrl: settings.huaweiSpace.photoUrl,
          databaseName: settings.huaweiSpace.databaseName,
          remoteStatusCache: null,
          lastAuthAt: settings.huaweiSpace.lastAuthAt
        },
        updatedAt: Date.now(),
        pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
        pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async setPersonalizationSyncEnabled(enabled: boolean): Promise<AiraSyncSettings> {
    return this.setSyncDomainEnabled('personalization', enabled);
  }

  async setSyncDomainEnabled(domainId: AiraSyncDomainId, enabled: boolean): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      if (enabled && settings.remoteKind === 'none') {
        throw new Error('请先选择当前同步方式。');
      }
      return {
        sourceId: settings.sourceId,
        remoteKind: settings.remoteKind,
        additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
        bookmarkSyncEnabled: domainId === 'bookmarks' ? enabled : settings.bookmarkSyncEnabled === true,
        personalizationSyncEnabled: domainId === 'personalization'
          ? enabled
          : settings.personalizationSyncEnabled === true,
        providerStates: settings.providerStates,
        additionalBackupEnabled: settings.additionalBackupEnabled,
        additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
        webdav: settings.webdav,
        huaweiCloud: settings.huaweiCloud,
        huaweiSpace: settings.huaweiSpace,
        updatedAt: Date.now(),
        pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
        pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async setBackupRemoteEnabled(
    remoteKind: AiraSyncProviderKind,
    enabled: boolean
  ): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      if (remoteKind === settings.remoteKind) {
        throw new Error('当前同步方式不能重复设置为附加备份。');
      }
      if (enabled && !this.isRemoteKindConfigured(settings, remoteKind)) {
        throw new Error('请先配置对应的附加备份位置。');
      }
      const backupRemoteKinds = enabled
        ? this.appendBackupKind(settings.additionalBackupRemoteKinds ?? [], remoteKind)
        : (settings.additionalBackupRemoteKinds ?? [])
          .filter((kind: AiraSyncProviderKind) => kind !== remoteKind);
      return {
      sourceId: settings.sourceId,
      remoteKind: settings.remoteKind,
      additionalBackupRemoteKinds: backupRemoteKinds,
      bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
      personalizationSyncEnabled: settings.personalizationSyncEnabled,
      providerStates: settings.providerStates,
      additionalBackupEnabled: backupRemoteKinds.length > 0,
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
      webdav: settings.webdav,
      huaweiCloud: settings.huaweiCloud,
      huaweiSpace: settings.huaweiSpace,
      updatedAt: Date.now(),
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async saveProviderRuntimeState(
    remoteKind: AiraSyncProviderKind,
    health: AiraSyncProviderHealth,
    errorMessage: string = '',
    successful: boolean = false,
    domain: AiraSyncRuntimeDomainId = 'bookmark',
    revision?: string,
    blocked?: boolean,
    failure?: AiraBookmarkSyncFailure
  ): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const now = Date.now();
      return this.buildSettingsWithProviderRuntimeState(
        settings,
        remoteKind,
        health,
        errorMessage,
        successful,
        domain,
        revision,
        blocked,
        failure,
        now
      );
    });
  }

  async saveBookmarkSyncCompletion(
    remoteKind: AiraSyncProviderKind,
    observation: AiraBookmarkSyncRemoteObservation
  ): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const now = Date.now();
      const runtimeSettings = this.buildSettingsWithProviderRuntimeState(
        settings,
        remoteKind,
        'healthy',
        '',
        true,
        'bookmark',
        observation.commitId,
        false,
        undefined,
        now
      );
      const bookmarkFolders = Math.max(0, Math.floor(observation.bookmarkFolders));
      const bookmarkItems = Math.max(0, Math.floor(observation.bookmarkItems));
      const cache: AiraSyncRemoteStatusCache = {
        providerKey: this.buildRemoteStatusProviderKey(runtimeSettings, remoteKind),
        summary: `${bookmarkFolders} 个文件夹，${bookmarkItems} 个书签`,
        bookmarkFolders: bookmarkFolders,
        bookmarkItems: bookmarkItems,
        commitId: observation.commitId.trim(),
        checkedAt: now
      };
      return this.buildSettingsWithRemoteStatusCache(runtimeSettings, remoteKind, cache, now);
    });
  }

  saveBookmarkBlockedState(
    remoteKind: AiraSyncProviderKind,
    summary: string,
    failure?: AiraBookmarkSyncFailure
  ): Promise<AiraSyncSettings> {
    return this.saveProviderRuntimeState(
      remoteKind,
      'degraded',
      summary,
      false,
      'bookmark',
      undefined,
      true,
      failure
    );
  }

  async setActiveRemoteKind(remoteKind: AiraSyncRemoteKind): Promise<AiraSyncSettings> {
    return this.setActiveRemoteKindInternal(remoteKind, undefined, 'none');
  }

  async setActiveRemoteKindWithPendingBookmarkSync(
    remoteKind: AiraSyncRemoteKind,
    providerSwitchFrom: AiraSyncProviderKind,
    changedAt: number = Date.now()
  ): Promise<AiraSyncSettings> {
    return this.setActiveRemoteKindInternal(
      remoteKind,
      changedAt > 0 ? changedAt : Date.now(),
      providerSwitchFrom
    );
  }

  private setActiveRemoteKindInternal(
    remoteKind: AiraSyncRemoteKind,
    pendingBookmarkSyncAt?: number,
    providerSwitchFrom: AiraSyncRemoteKind = 'none'
  ): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      if (remoteKind !== 'aira_cloud' && remoteKind !== 'webdav' && remoteKind !== 'huawei_space' &&
        remoteKind !== 'self_hosted') {
        throw new Error('不支持的同步方式。');
      }
      if (!this.isRemoteKindConfigured(settings, remoteKind)) {
        throw new Error('请先配置对应的同步方式。');
      }
      const backups = (settings.additionalBackupRemoteKinds ?? [])
        .filter((kind: AiraSyncProviderKind) => kind !== remoteKind);
      const currentPendingAt = settings.pendingBookmarkSyncAt ?? 0;
      const nextPendingAt = pendingBookmarkSyncAt === undefined
        ? currentPendingAt
        : this.resolveNextPendingBookmarkSyncAt(currentPendingAt, pendingBookmarkSyncAt);
      const now = Date.now();
      const nextSettings: AiraSyncSettings = {
        sourceId: settings.sourceId,
        remoteKind: remoteKind,
        additionalBackupRemoteKinds: backups,
        bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
        personalizationSyncEnabled: settings.personalizationSyncEnabled,
        providerStates: settings.providerStates,
        additionalBackupEnabled: backups.length > 0 && settings.additionalBackupEnabled === true,
        additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
        webdav: settings.webdav,
        huaweiCloud: settings.huaweiCloud,
        huaweiSpace: settings.huaweiSpace,
        selfHosted: settings.selfHosted,
        updatedAt: now,
        pendingBookmarkSyncAt: nextPendingAt,
        pendingBookmarkProviderSwitchFrom: pendingBookmarkSyncAt !== undefined &&
          remoteKind === 'huawei_space' && providerSwitchFrom !== remoteKind
          ? providerSwitchFrom
          : 'none'
      };
      if (pendingBookmarkSyncAt === undefined || remoteKind !== 'huawei_space') {
        return nextSettings;
      }
      return this.buildSettingsWithProviderRuntimeState(
        nextSettings,
        'huawei_space',
        'idle',
        '',
        false,
        'bookmark',
        undefined,
        false,
        undefined,
        now
      );
    });
  }

  async deactivateCurrentSync(): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => ({
      sourceId: settings.sourceId,
      remoteKind: settings.remoteKind,
      additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
      bookmarkSyncEnabled: false,
      personalizationSyncEnabled: false,
      providerStates: settings.providerStates,
      additionalBackupEnabled: settings.additionalBackupEnabled,
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
      webdav: settings.webdav,
      huaweiCloud: settings.huaweiCloud,
      huaweiSpace: settings.huaweiSpace,
      selfHosted: settings.selfHosted,
      updatedAt: Date.now(),
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
    }));
  }

  async clearHuaweiIdentity(): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const activeProviderRemoved = settings.remoteKind === 'aira_cloud' || settings.remoteKind === 'huawei_space';
      const activeRemoteKind: AiraSyncRemoteKind = activeProviderRemoved ? 'none' : settings.remoteKind;
      const backupRemoteKinds = (settings.additionalBackupRemoteKinds ?? [])
        .filter((kind: AiraSyncProviderKind) => kind !== 'aira_cloud' && kind !== 'huawei_space');
      return {
      sourceId: settings.sourceId,
      remoteKind: activeRemoteKind,
      additionalBackupRemoteKinds: backupRemoteKinds,
      bookmarkSyncEnabled: activeProviderRemoved ? false : settings.bookmarkSyncEnabled,
      personalizationSyncEnabled: activeProviderRemoved ? false : settings.personalizationSyncEnabled,
      providerStates: settings.providerStates,
      additionalBackupEnabled: backupRemoteKinds.length > 0 && settings.additionalBackupEnabled === true,
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
      webdav: settings.webdav,
      huaweiCloud: {
        uid: '',
        displayName: '',
        photoUrl: '',
        remoteStatusCache: null,
        lastAuthAt: 0
      },
      huaweiSpace: {
        uid: '',
        displayName: '',
        photoUrl: '',
        databaseName: settings.huaweiSpace.databaseName,
        remoteStatusCache: null,
        lastAuthAt: 0
      },
      updatedAt: Date.now(),
      pendingBookmarkSyncAt: activeProviderRemoved ? 0 : settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: activeProviderRemoved
        ? 'none'
        : settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async saveWebdavConfig(
    endpoint: string,
    username: string,
    password: string
  ): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const normalizedEndpoint = endpoint.trim();
      const resolvedRootPath = AIRA_SYNC_DEFAULT_ROOT;
      const webdavCache = settings.webdav.remoteStatusCache !== null &&
        settings.webdav.remoteStatusCache.providerKey ===
          buildAiraWebdavRemoteStatusProviderKey(normalizedEndpoint, username, resolvedRootPath)
        ? settings.webdav.remoteStatusCache
        : null;
      return {
      sourceId: settings.sourceId,
      remoteKind: settings.remoteKind,
      bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
      personalizationSyncEnabled: settings.personalizationSyncEnabled,
      providerStates: settings.providerStates,
      additionalBackupEnabled: settings.additionalBackupEnabled,
      additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
      webdav: {
        endpoint: normalizedEndpoint,
        username: username.trim(),
        password: password,
        remoteStatusCache: webdavCache
      },
      huaweiCloud: settings.huaweiCloud,
      huaweiSpace: settings.huaweiSpace,
      updatedAt: Date.now(),
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async savePersonalServerConfig(
    baseUrl: string,
    instanceId: string,
    protocolVersion: number,
    credentialId: string,
    deviceToken: string,
    deviceName: string
  ): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const previous = resolveAiraPersonalServerConfig(settings);
      const normalizedBaseUrl = baseUrl.trim().replace(/\/+$/, '');
      const normalizedInstanceId = instanceId.trim();
      const sameInstance = previous.baseUrl === normalizedBaseUrl && previous.instanceId === normalizedInstanceId;
      return {
        sourceId: settings.sourceId,
        bookmarkGenerationInitializedAt: settings.bookmarkGenerationInitializedAt,
        remoteKind: settings.remoteKind,
        bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
        personalizationSyncEnabled: settings.personalizationSyncEnabled,
        providerStates: settings.providerStates,
        additionalBackupEnabled: settings.additionalBackupEnabled,
        additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
        additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
        webdav: settings.webdav,
        huaweiCloud: settings.huaweiCloud,
        huaweiSpace: settings.huaweiSpace,
        selfHosted: {
          baseUrl: normalizedBaseUrl,
          instanceId: normalizedInstanceId,
          protocolVersion: Math.floor(protocolVersion),
          credentialId: credentialId.trim(),
          deviceToken: deviceToken.trim(),
          deviceName: deviceName.trim(),
          remoteStatusCache: sameInstance ? previous.remoteStatusCache : null
        },
        updatedAt: Date.now(),
        pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
        pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async clearPersonalServerConfig(): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const activeRemoved = settings.remoteKind === 'self_hosted';
      const backupRemoteKinds = settings.additionalBackupRemoteKinds.filter(
        (kind: AiraSyncProviderKind): boolean => kind !== 'self_hosted'
      );
      return {
        sourceId: settings.sourceId,
        bookmarkGenerationInitializedAt: settings.bookmarkGenerationInitializedAt,
        remoteKind: activeRemoved ? 'none' : settings.remoteKind,
        bookmarkSyncEnabled: activeRemoved ? false : settings.bookmarkSyncEnabled,
        personalizationSyncEnabled: activeRemoved ? false : settings.personalizationSyncEnabled,
        providerStates: settings.providerStates.filter((state: AiraSyncProviderRuntimeState): boolean => {
          return state.remoteKind !== 'self_hosted';
        }),
        additionalBackupEnabled: settings.additionalBackupEnabled && backupRemoteKinds.length > 0,
        additionalBackupRemoteKinds: backupRemoteKinds,
        additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
        webdav: settings.webdav,
        huaweiCloud: settings.huaweiCloud,
        huaweiSpace: settings.huaweiSpace,
        selfHosted: createDefaultAiraPersonalServerConfig(),
        updatedAt: Date.now(),
        pendingBookmarkSyncAt: activeRemoved ? 0 : settings.pendingBookmarkSyncAt,
        pendingBookmarkProviderSwitchFrom: activeRemoved ? 'none' : settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async saveHuaweiCloudConfig(
    uid: string,
    displayName: string = '',
    photoUrl: string = ''
  ): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const normalizedUid = uid.trim();
      const hasHuaweiIdentity = normalizedUid.length > 0;
      const previousIdentity = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
      const previousSameUser = hasHuaweiIdentity && previousIdentity.uid === normalizedUid;
      const identityChanged = hasHuaweiIdentity && previousIdentity.uid.trim().length > 0 && !previousSameUser;
      const activeHuaweiProviderRemoved = identityChanged &&
        (settings.remoteKind === 'aira_cloud' || settings.remoteKind === 'huawei_space');
      const backupRemoteKinds = identityChanged
        ? (settings.additionalBackupRemoteKinds ?? []).filter((kind: AiraSyncProviderKind): boolean => {
            return kind !== 'aira_cloud' && kind !== 'huawei_space';
          })
        : settings.additionalBackupRemoteKinds;
      const providerStates = identityChanged
        ? (settings.providerStates ?? []).filter((state: AiraSyncProviderRuntimeState): boolean => {
            return state.remoteKind !== 'aira_cloud' && state.remoteKind !== 'huawei_space';
          })
        : settings.providerStates;
      const cloudCache = settings.huaweiCloud.remoteStatusCache !== null &&
        settings.huaweiCloud.remoteStatusCache.providerKey ===
          this.buildHuaweiCloudStatusProviderKey(normalizedUid, AIRA_SYNC_DEFAULT_ROOT)
        ? settings.huaweiCloud.remoteStatusCache
        : null;
      const spaceCache = settings.huaweiSpace.remoteStatusCache !== null &&
        settings.huaweiSpace.remoteStatusCache.providerKey === this.buildHuaweiSpaceStatusProviderKey(
          normalizedUid,
          settings.huaweiSpace.databaseName,
          AIRA_SYNC_DEFAULT_ROOT
        )
        ? settings.huaweiSpace.remoteStatusCache
        : null;
      const resolvedDisplayName = this.resolveHuaweiDisplayNameForSave(
        displayName,
        normalizedUid,
        previousSameUser,
        previousIdentity.displayName
      );
      const resolvedPhotoUrl = this.resolveHuaweiPhotoUrlForSave(
        photoUrl,
        previousSameUser,
        previousIdentity.photoUrl
      );
      const lastAuthAt = hasHuaweiIdentity ? Date.now() : 0;
      return {
      sourceId: settings.sourceId,
      remoteKind: activeHuaweiProviderRemoved ? 'none' : settings.remoteKind,
      bookmarkSyncEnabled: activeHuaweiProviderRemoved ? false : settings.bookmarkSyncEnabled,
      personalizationSyncEnabled: activeHuaweiProviderRemoved ? false : settings.personalizationSyncEnabled,
      providerStates: providerStates,
      additionalBackupEnabled: (backupRemoteKinds ?? []).length > 0 && settings.additionalBackupEnabled === true,
      additionalBackupRemoteKinds: backupRemoteKinds,
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
      webdav: settings.webdav,
      huaweiCloud: {
        uid: normalizedUid,
        displayName: resolvedDisplayName,
        photoUrl: resolvedPhotoUrl,
        remoteStatusCache: cloudCache,
        lastAuthAt: lastAuthAt
      },
      huaweiSpace: {
        uid: normalizedUid,
        displayName: resolvedDisplayName,
        photoUrl: resolvedPhotoUrl,
        databaseName: settings.huaweiSpace.databaseName,
        remoteStatusCache: spaceCache,
        lastAuthAt: lastAuthAt
      },
      updatedAt: Date.now(),
      pendingBookmarkSyncAt: activeHuaweiProviderRemoved ? 0 : settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: activeHuaweiProviderRemoved
        ? 'none'
        : settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  async saveHuaweiSpaceConfig(
    uid: string,
    displayName: string = '',
    photoUrl: string = '',
    databaseName: string = AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME
  ): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      const normalizedUid = uid.trim();
      const hasHuaweiIdentity = normalizedUid.length > 0;
      const previousIdentity = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
      const previousSameUser = hasHuaweiIdentity && previousIdentity.uid === normalizedUid;
      const identityChanged = hasHuaweiIdentity && previousIdentity.uid.trim().length > 0 && !previousSameUser;
      const activeHuaweiProviderRemoved = identityChanged &&
        (settings.remoteKind === 'aira_cloud' || settings.remoteKind === 'huawei_space');
      const backupRemoteKinds = identityChanged
        ? (settings.additionalBackupRemoteKinds ?? []).filter((kind: AiraSyncProviderKind): boolean => {
            return kind !== 'aira_cloud' && kind !== 'huawei_space';
          })
        : settings.additionalBackupRemoteKinds;
      const providerStates = identityChanged
        ? (settings.providerStates ?? []).filter((state: AiraSyncProviderRuntimeState): boolean => {
            return state.remoteKind !== 'aira_cloud' && state.remoteKind !== 'huawei_space';
          })
        : settings.providerStates;
      const resolvedDatabaseName = this.normalizeHuaweiSpaceDatabaseName(databaseName);
      const cloudCache = settings.huaweiCloud.remoteStatusCache !== null &&
        settings.huaweiCloud.remoteStatusCache.providerKey ===
          this.buildHuaweiCloudStatusProviderKey(normalizedUid, AIRA_SYNC_DEFAULT_ROOT)
        ? settings.huaweiCloud.remoteStatusCache
        : null;
      const spaceCache = settings.huaweiSpace.remoteStatusCache !== null &&
        settings.huaweiSpace.remoteStatusCache.providerKey ===
          this.buildHuaweiSpaceStatusProviderKey(normalizedUid, resolvedDatabaseName, AIRA_SYNC_DEFAULT_ROOT)
        ? settings.huaweiSpace.remoteStatusCache
        : null;
      const resolvedDisplayName = this.resolveHuaweiDisplayNameForSave(
        displayName,
        normalizedUid,
        previousSameUser,
        previousIdentity.displayName
      );
      const resolvedPhotoUrl = this.resolveHuaweiPhotoUrlForSave(
        photoUrl,
        previousSameUser,
        previousIdentity.photoUrl
      );
      const lastAuthAt = hasHuaweiIdentity ? Date.now() : 0;
      return {
      sourceId: settings.sourceId,
      remoteKind: activeHuaweiProviderRemoved ? 'none' : settings.remoteKind,
      bookmarkSyncEnabled: activeHuaweiProviderRemoved ? false : settings.bookmarkSyncEnabled,
      personalizationSyncEnabled: activeHuaweiProviderRemoved ? false : settings.personalizationSyncEnabled,
      providerStates: providerStates,
      additionalBackupEnabled: (backupRemoteKinds ?? []).length > 0 && settings.additionalBackupEnabled === true,
      additionalBackupRemoteKinds: backupRemoteKinds,
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
      webdav: settings.webdav,
      huaweiCloud: {
        uid: normalizedUid,
        displayName: resolvedDisplayName,
        photoUrl: resolvedPhotoUrl,
        remoteStatusCache: cloudCache,
        lastAuthAt: lastAuthAt
      },
      huaweiSpace: {
        uid: normalizedUid,
        displayName: resolvedDisplayName,
        photoUrl: resolvedPhotoUrl,
        databaseName: resolvedDatabaseName,
        remoteStatusCache: spaceCache,
        lastAuthAt: lastAuthAt
      },
      updatedAt: Date.now(),
      pendingBookmarkSyncAt: activeHuaweiProviderRemoved ? 0 : settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: activeHuaweiProviderRemoved
        ? 'none'
        : settings.pendingBookmarkProviderSwitchFrom
      };
    });
  }

  private resolveHuaweiDisplayNameForSave(
    displayName: string,
    uid: string,
    previousSameUser: boolean,
    previousDisplayName: string
  ): string {
    const normalizedDisplayName = displayName.trim();
    if (normalizedDisplayName.length <= 0) {
      return previousSameUser ? previousDisplayName.trim() : '';
    }
    if (previousSameUser && this.isFallbackHuaweiDisplayName(normalizedDisplayName, uid)) {
      const normalizedPrevious = previousDisplayName.trim();
      if (normalizedPrevious.length > 0 && !this.isFallbackHuaweiDisplayName(normalizedPrevious, uid)) {
        return normalizedPrevious;
      }
    }
    return normalizedDisplayName;
  }

  private resolveHuaweiPhotoUrlForSave(
    photoUrl: string,
    previousSameUser: boolean,
    previousPhotoUrl: string
  ): string {
    const normalizedPhotoUrl = photoUrl.trim();
    if (normalizedPhotoUrl.length > 0) {
      return normalizedPhotoUrl;
    }
    return previousSameUser ? previousPhotoUrl.trim() : '';
  }

  private isFallbackHuaweiDisplayName(displayName: string, uid: string): boolean {
    const normalizedUid = uid.trim();
    const suffix = normalizedUid.length > 6 ? normalizedUid.slice(normalizedUid.length - 6) : normalizedUid;
    return displayName === '华为账号' || (suffix.length > 0 && displayName === `华为账号 ${suffix}`);
  }

  getProviderId(remoteKind: AiraSyncRemoteKind): string {
    return this.resolveProviderId(remoteKind);
  }

  getProviderRuntimeIdentity(
    remoteKind: AiraSyncProviderKind,
    domain: AiraSyncRuntimeDomainId
  ): string {
    return this.buildProviderRuntimeIdentity(this.cachedSettings, remoteKind, domain);
  }

  async readBaseline(providerId: string): Promise<AiraSyncBaselineRecord | undefined> {
    return this.storageAdapter.readBaseline(providerId);
  }

  async writeBaseline(
    commitId: string,
    snapshot: AiraSyncSnapshot | null,
    history: AiraBookmarkHistoryDescriptor,
    providerId: string
  ): Promise<AiraSyncBaselineRecord> {
    const record: AiraSyncBaselineRecord = {
      providerId: providerId,
      commitId: commitId,
      snapshot: snapshot,
      history: history,
      updatedAt: Date.now()
    };
    await this.storageAdapter.writeBaseline(record);
    return record;
  }

  async saveRemoteStatusCacheForKind(
    remoteKind: AiraSyncRemoteKind,
    cache: AiraSyncRemoteStatusCache
  ): Promise<AiraSyncSettings> {
    return this.mutateSettings((settings: AiraSyncSettings): AiraSyncSettings => {
      return this.buildSettingsWithRemoteStatusCache(settings, remoteKind, cache, Date.now());
    });
  }

  private buildSettingsWithProviderRuntimeState(
    settings: AiraSyncSettings,
    remoteKind: AiraSyncProviderKind,
    health: AiraSyncProviderHealth,
    errorMessage: string,
    successful: boolean,
    domain: AiraSyncRuntimeDomainId,
    revision: string | undefined,
    blocked: boolean | undefined,
    failure: AiraBookmarkSyncFailure | undefined,
    now: number
  ): AiraSyncSettings {
    const states = (settings.providerStates ?? []).filter((state: AiraSyncProviderRuntimeState): boolean => {
      return state.remoteKind !== remoteKind;
    });
    const previous = this.resolveProviderRuntimeStateForSettings(settings, remoteKind);
    const providerIdentity = this.buildProviderRuntimeIdentity(settings, remoteKind, domain);
    const storedDomain = this.resolveDomainRuntimeState(previous, domain);
    const previousDomain = storedDomain.providerIdentity === providerIdentity
      ? storedDomain
      : createAiraSyncDomainRuntimeState();
    const nextDomain: AiraSyncDomainRuntimeState = {
      providerIdentity: providerIdentity,
      health: health,
      lastAttemptAt: now,
      lastSuccessAt: successful ? now : previousDomain.lastSuccessAt,
      revision: successful && revision !== undefined ? revision.trim() : previousDomain.revision,
      lastError: errorMessage.trim(),
      failureCode: health === 'healthy' ? '' : (failure?.code.trim() ?? ''),
      failureStage: health === 'healthy' ? '' : (failure?.stage ?? ''),
      failureDetail: health === 'healthy' ? '' : (failure?.safeDetail.trim() ?? ''),
      blocked: health === 'healthy' ? false : (blocked ?? previousDomain.blocked)
    };
    states.push({
      remoteKind: remoteKind,
      bookmark: domain === 'bookmark' ? nextDomain : previous.bookmark,
      personalization: domain === 'personalization' ? nextDomain : previous.personalization,
      bookmarkBackup: domain === 'bookmark_backup' ? nextDomain : previous.bookmarkBackup,
      personalizationBackup: domain === 'personalization_backup' ? nextDomain : previous.personalizationBackup
    });
    return {
      sourceId: settings.sourceId,
      remoteKind: settings.remoteKind,
      additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
      bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
      personalizationSyncEnabled: settings.personalizationSyncEnabled,
      providerStates: states,
      additionalBackupEnabled: settings.additionalBackupEnabled,
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
      webdav: settings.webdav,
      huaweiCloud: settings.huaweiCloud,
      huaweiSpace: settings.huaweiSpace,
      selfHosted: settings.selfHosted,
      updatedAt: now,
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
    };
  }

  private buildSettingsWithRemoteStatusCache(
    settings: AiraSyncSettings,
    remoteKind: AiraSyncRemoteKind,
    cache: AiraSyncRemoteStatusCache,
    now: number
  ): AiraSyncSettings {
    const normalizedCache = this.normalizeRemoteStatusCache(cache);
    const nextSettings: AiraSyncSettings = {
      sourceId: settings.sourceId,
      remoteKind: settings.remoteKind,
      bookmarkSyncEnabled: settings.bookmarkSyncEnabled,
      personalizationSyncEnabled: settings.personalizationSyncEnabled,
      providerStates: settings.providerStates,
      additionalBackupEnabled: settings.additionalBackupEnabled,
      additionalBackupRemoteKinds: settings.additionalBackupRemoteKinds,
      additionalBackupIntervalDays: settings.additionalBackupIntervalDays,
      webdav: settings.webdav,
      huaweiCloud: settings.huaweiCloud,
      huaweiSpace: settings.huaweiSpace,
      updatedAt: now,
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt,
      pendingBookmarkProviderSwitchFrom: settings.pendingBookmarkProviderSwitchFrom
    };
    if (remoteKind === 'webdav') {
      nextSettings.webdav = {
        endpoint: settings.webdav.endpoint,
        username: settings.webdav.username,
        password: settings.webdav.password,
        remoteStatusCache: normalizedCache
      };
    }
    if (remoteKind === 'aira_cloud') {
      nextSettings.huaweiCloud = {
        uid: settings.huaweiCloud.uid,
        displayName: settings.huaweiCloud.displayName,
        photoUrl: settings.huaweiCloud.photoUrl,
        remoteStatusCache: normalizedCache,
        lastAuthAt: settings.huaweiCloud.lastAuthAt
      };
    }
    if (remoteKind === 'huawei_space') {
      nextSettings.huaweiSpace = {
        uid: settings.huaweiSpace.uid,
        displayName: settings.huaweiSpace.displayName,
        photoUrl: settings.huaweiSpace.photoUrl,
        databaseName: settings.huaweiSpace.databaseName,
        remoteStatusCache: normalizedCache,
        lastAuthAt: settings.huaweiSpace.lastAuthAt
      };
    }
    if (remoteKind === 'self_hosted') {
      const config = resolveAiraPersonalServerConfig(settings);
      nextSettings.selfHosted = {
        baseUrl: config.baseUrl,
        instanceId: config.instanceId,
        protocolVersion: config.protocolVersion,
        credentialId: config.credentialId,
        deviceToken: config.deviceToken,
        deviceName: config.deviceName,
        remoteStatusCache: normalizedCache
      };
    }
    return nextSettings;
  }

  private normalizeSettings(settings: AiraSyncSettings): AiraSyncSettings {
    const rawWebdav = settings.webdav ?? this.defaultSettings.webdav;
    const rawHuaweiCloud = settings.huaweiCloud ?? this.defaultSettings.huaweiCloud;
    const rawHuaweiSpace = settings.huaweiSpace ?? this.defaultSettings.huaweiSpace;
    const rawSelfHosted = settings.selfHosted ?? createDefaultAiraPersonalServerConfig();
    const huaweiIdentity = resolveAiraHuaweiAccountIdentity(rawHuaweiCloud, rawHuaweiSpace);
    const sourceId = this.normalizeSourceId(settings.sourceId ?? this.defaultSettings.sourceId);
    const endpoint = rawWebdav.endpoint.trim();
    const huaweiSpaceDatabaseName = this.normalizeHuaweiSpaceDatabaseName(rawHuaweiSpace.databaseName);
    const rawRemoteKind = this.normalizeRemoteKindValue(settings.remoteKind);
    const webdavConfigured = endpoint.length > 0;
    const airaCloudConfigured = huaweiIdentity.uid.length > 0;
    const huaweiSpaceConfigured = huaweiIdentity.uid.length > 0;
    const selfHostedConfigured = rawSelfHosted.baseUrl.trim().length > 0 &&
      rawSelfHosted.instanceId.trim().length > 0 && rawSelfHosted.deviceToken.trim().length > 0;
    const remoteKind = this.isConfiguredKindValue(
      rawRemoteKind,
      webdavConfigured,
      airaCloudConfigured,
      huaweiSpaceConfigured,
      selfHostedConfigured
    ) ? rawRemoteKind : 'none';
    const additionalBackupRemoteKinds = this.normalizeAdditionalBackupRemoteKinds(
      settings.additionalBackupRemoteKinds,
      remoteKind,
      webdavConfigured,
      airaCloudConfigured,
      huaweiSpaceConfigured,
      selfHostedConfigured
    );
    const bookmarkSyncEnabled = remoteKind !== 'none' && settings.bookmarkSyncEnabled === true;
    const personalizationSyncEnabled = remoteKind !== 'none' && settings.personalizationSyncEnabled === true;
    const additionalBackupIntervalDays = this.normalizeAdditionalBackupIntervalDays(
      settings.additionalBackupIntervalDays
    );
    const additionalBackupEnabled = additionalBackupRemoteKinds.length > 0 && settings.additionalBackupEnabled === true;
    return {
      sourceId: sourceId,
      bookmarkGenerationInitializedAt: this.normalizeTimestamp(settings.bookmarkGenerationInitializedAt),
      remoteKind: remoteKind,
      bookmarkSyncEnabled: bookmarkSyncEnabled,
      personalizationSyncEnabled: personalizationSyncEnabled,
      providerStates: this.normalizeProviderStates(
        settings.providerStates,
        huaweiIdentity.uid,
        huaweiSpaceDatabaseName
      ),
      additionalBackupEnabled: additionalBackupEnabled,
      additionalBackupRemoteKinds: additionalBackupRemoteKinds,
      additionalBackupIntervalDays: additionalBackupIntervalDays,
      webdav: {
        endpoint: endpoint,
        username: rawWebdav.username.trim(),
        password: rawWebdav.password,
        remoteStatusCache: this.normalizeRemoteStatusCache(rawWebdav.remoteStatusCache)
      },
      huaweiCloud: {
        uid: huaweiIdentity.uid,
        displayName: huaweiIdentity.displayName,
        photoUrl: huaweiIdentity.photoUrl,
        remoteStatusCache: this.normalizeRemoteStatusCache(rawHuaweiCloud.remoteStatusCache),
        lastAuthAt: huaweiIdentity.lastAuthAt
      },
      huaweiSpace: {
        uid: huaweiIdentity.uid,
        displayName: huaweiIdentity.displayName,
        photoUrl: huaweiIdentity.photoUrl,
        databaseName: huaweiSpaceDatabaseName,
        remoteStatusCache: this.normalizeHuaweiSpaceRemoteStatusCache(
          rawHuaweiSpace.remoteStatusCache,
          huaweiIdentity.uid,
          huaweiSpaceDatabaseName
        ),
        lastAuthAt: huaweiIdentity.lastAuthAt
      },
      selfHosted: {
        baseUrl: rawSelfHosted.baseUrl.trim().replace(/\/+$/, ''),
        instanceId: rawSelfHosted.instanceId.trim(),
        protocolVersion: Math.max(0, Math.floor(rawSelfHosted.protocolVersion)),
        credentialId: rawSelfHosted.credentialId.trim(),
        deviceToken: rawSelfHosted.deviceToken.trim(),
        deviceName: rawSelfHosted.deviceName.trim(),
        remoteStatusCache: this.normalizeRemoteStatusCache(rawSelfHosted.remoteStatusCache)
      },
      updatedAt: settings.updatedAt > 0 ? settings.updatedAt : Date.now(),
      pendingBookmarkSyncAt: settings.pendingBookmarkSyncAt !== undefined && settings.pendingBookmarkSyncAt > 0
        ? settings.pendingBookmarkSyncAt
        : 0,
      pendingBookmarkProviderSwitchFrom: this.normalizePendingBookmarkProviderSwitchFrom(settings)
    };
  }

  private normalizePendingBookmarkProviderSwitchFrom(settings: AiraSyncSettings): AiraSyncRemoteKind {
    if ((settings.pendingBookmarkSyncAt ?? 0) <= 0 || settings.remoteKind !== 'huawei_space') {
      return 'none';
    }
    const remoteKind = settings.pendingBookmarkProviderSwitchFrom ?? 'none';
    if (remoteKind === 'aira_cloud') {
      return remoteKind;
    }
    return 'none';
  }

  private normalizeRemoteStatusCache(cache: AiraSyncRemoteStatusCache | null | undefined): AiraSyncRemoteStatusCache | null {
    if (cache === null || cache === undefined || cache.providerKey.trim().length === 0 || cache.summary.trim().length === 0) {
      return null;
    }
    return {
      providerKey: cache.providerKey.trim(),
      summary: cache.summary.trim(),
      bookmarkFolders: Math.max(0, Math.floor(cache.bookmarkFolders)),
      bookmarkItems: Math.max(0, Math.floor(cache.bookmarkItems)),
      commitId: (cache.commitId || '').trim(),
      checkedAt: cache.checkedAt > 0 ? cache.checkedAt : Date.now()
    };
  }

  private normalizeHuaweiSpaceRemoteStatusCache(
    cache: AiraSyncRemoteStatusCache | null | undefined,
    uid: string,
    databaseName: string
  ): AiraSyncRemoteStatusCache | null {
    const normalized = this.normalizeRemoteStatusCache(cache);
    if (normalized === null || normalized.providerKey !== this.buildHuaweiSpaceStatusProviderKey(
      uid,
      databaseName,
      AIRA_SYNC_DEFAULT_ROOT
    )) {
      return null;
    }
    return normalized;
  }

  private normalizeAdditionalBackupIntervalDays(value: number | undefined): AiraAdditionalBackupIntervalDays {
    if (value === 1 || value === 3 || value === 7) {
      return value;
    }
    return 7;
  }

  private appendBackupKind(
    backupRemoteKinds: AiraSyncProviderKind[],
    remoteKind: AiraSyncProviderKind
  ): AiraSyncProviderKind[] {
    const result = backupRemoteKinds.filter((kind: AiraSyncProviderKind) => kind !== remoteKind);
    result.push(remoteKind);
    return result;
  }

  private normalizeProviderStates(
    values: AiraSyncProviderRuntimeState[] | undefined,
    huaweiSpaceUid: string,
    huaweiSpaceDatabaseName: string
  ): AiraSyncProviderRuntimeState[] {
    const kinds: AiraSyncProviderKind[] = ['huawei_space', 'webdav', 'aira_cloud', 'self_hosted'];
    return kinds.map((remoteKind: AiraSyncProviderKind): AiraSyncProviderRuntimeState => {
      const value = Array.isArray(values)
        ? values.find((item: AiraSyncProviderRuntimeState) => item.remoteKind === remoteKind)
        : undefined;
      const normalized: AiraSyncProviderRuntimeState = {
        remoteKind: remoteKind,
        bookmark: this.normalizeDomainRuntimeState(value?.bookmark),
        personalization: this.normalizeDomainRuntimeState(value?.personalization),
        bookmarkBackup: this.normalizeDomainRuntimeState(value?.bookmarkBackup),
        personalizationBackup: this.normalizeDomainRuntimeState(value?.personalizationBackup)
      };
      if (remoteKind !== 'huawei_space') {
        return normalized;
      }
      normalized.bookmark = this.retainDomainRuntimeStateForIdentity(
        normalized.bookmark,
        this.buildHuaweiSpaceRuntimeIdentity(
          huaweiSpaceUid,
          huaweiSpaceDatabaseName,
          'bookmark'
        )
      );
      normalized.bookmarkBackup = this.retainDomainRuntimeStateForIdentity(
        normalized.bookmarkBackup,
        this.buildHuaweiSpaceRuntimeIdentity(
          huaweiSpaceUid,
          huaweiSpaceDatabaseName,
          'bookmark_backup'
        )
      );
      return normalized;
    });
  }

  private retainDomainRuntimeStateForIdentity(
    state: AiraSyncDomainRuntimeState,
    expectedIdentity: string
  ): AiraSyncDomainRuntimeState {
    return state.providerIdentity === expectedIdentity ? state : createAiraSyncDomainRuntimeState();
  }

  private resolveProviderRuntimeStateForSettings(
    settings: AiraSyncSettings,
    remoteKind: AiraSyncProviderKind
  ): AiraSyncProviderRuntimeState {
    const state = (settings.providerStates ?? []).find((item: AiraSyncProviderRuntimeState) => {
      return item.remoteKind === remoteKind;
    });
    return state ?? {
      remoteKind: remoteKind,
      bookmark: createAiraSyncDomainRuntimeState(),
      personalization: createAiraSyncDomainRuntimeState(),
      bookmarkBackup: createAiraSyncDomainRuntimeState(),
      personalizationBackup: createAiraSyncDomainRuntimeState()
    };
  }

  private resolveDomainRuntimeState(
    state: AiraSyncProviderRuntimeState,
    domain: AiraSyncRuntimeDomainId
  ): AiraSyncDomainRuntimeState {
    if (domain === 'personalization') {
      return state.personalization;
    }
    if (domain === 'bookmark_backup') {
      return state.bookmarkBackup;
    }
    if (domain === 'personalization_backup') {
      return state.personalizationBackup;
    }
    return state.bookmark;
  }

  private normalizeDomainRuntimeState(
    value: AiraSyncDomainRuntimeState | undefined
  ): AiraSyncDomainRuntimeState {
    return {
      providerIdentity: `${value?.providerIdentity ?? ''}`.trim(),
      health: this.normalizeProviderHealth(value?.health),
      lastAttemptAt: this.normalizeTimestamp(value?.lastAttemptAt),
      lastSuccessAt: this.normalizeTimestamp(value?.lastSuccessAt),
      revision: `${value?.revision ?? ''}`.trim(),
      lastError: `${value?.lastError ?? ''}`.trim(),
      failureCode: `${value?.failureCode ?? ''}`.trim(),
      failureStage: this.normalizeBookmarkFailureStage(value?.failureStage),
      failureDetail: `${value?.failureDetail ?? ''}`.trim(),
      blocked: value?.blocked === true
    };
  }

  private normalizeBookmarkFailureStage(
    value: AiraBookmarkSyncFailureStage | '' | undefined
  ): AiraBookmarkSyncFailureStage | '' {
    if (value === 'authentication' || value === 'network' || value === 'remote_read_validation' ||
      value === 'local_snapshot' || value === 'merge' || value === 'remote_commit' ||
      value === 'remote_confirmation' || value === 'local_apply' || value === 'unknown') {
      return value;
    }
    return '';
  }

  private normalizeProviderHealth(value: AiraSyncProviderHealth | undefined): AiraSyncProviderHealth {
    if (value === 'healthy' || value === 'degraded' || value === 'unavailable') {
      return value;
    }
    return 'idle';
  }

  private normalizeTimestamp(value: number | undefined): number {
    const timestamp = Number(value ?? 0);
    return Number.isFinite(timestamp) && timestamp > 0 ? Math.floor(timestamp) : 0;
  }

  private normalizeProviderKindValue(value: AiraSyncProviderKind | undefined): AiraSyncProviderKind | undefined {
    if (value === 'aira_cloud' || value === 'huawei_space' || value === 'webdav' || value === 'self_hosted') {
      return value;
    }
    return undefined;
  }

  private normalizeAdditionalBackupRemoteKinds(
    values: AiraSyncProviderKind[] | undefined,
    activeRemoteKind: AiraSyncRemoteKind,
    webdavConfigured: boolean,
    airaCloudConfigured: boolean,
    huaweiSpaceConfigured: boolean,
    selfHostedConfigured: boolean
  ): AiraSyncProviderKind[] {
    const result: AiraSyncProviderKind[] = [];
    const rawValues = Array.isArray(values) ? values : [];
    rawValues.forEach((value: AiraSyncProviderKind) => {
      const remoteKind = this.normalizeProviderKindValue(value);
      if (remoteKind === undefined || remoteKind === activeRemoteKind || result.indexOf(remoteKind) >= 0 ||
        !this.isConfiguredKindValue(
          remoteKind,
          webdavConfigured,
          airaCloudConfigured,
          huaweiSpaceConfigured,
          selfHostedConfigured
        )) {
        return;
      }
      result.push(remoteKind);
    });
    return result;
  }

  private isConfiguredKindValue(
    remoteKind: AiraSyncRemoteKind,
    webdavConfigured: boolean,
    airaCloudConfigured: boolean,
    huaweiSpaceConfigured: boolean,
    selfHostedConfigured: boolean
  ): boolean {
    if (remoteKind === 'webdav') {
      return webdavConfigured;
    }
    if (remoteKind === 'aira_cloud') {
      return airaCloudConfigured;
    }
    if (remoteKind === 'huawei_space') {
      return huaweiSpaceConfigured;
    }
    if (remoteKind === 'self_hosted') {
      return selfHostedConfigured;
    }
    return remoteKind === 'none';
  }

  private normalizeSourceId(sourceId: string | undefined): string {
    const normalized = (sourceId ?? '').trim()
      .replace(/[^a-zA-Z0-9_-]+/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '');
    return normalized.length > 0 ? normalized : this.createSourceId();
  }

  private createSourceId(): string {
    return createAiraSyncSourceId();
  }

  private normalizeRemoteKindValue(value: AiraSyncRemoteKind): AiraSyncRemoteKind {
    const rawValue = `${value}`.trim();
    if (rawValue === 'aira_cloud' || rawValue === 'huawei_space' || rawValue === 'webdav' ||
      rawValue === 'self_hosted') {
      return rawValue as AiraSyncRemoteKind;
    }
    return 'none';
  }

  private normalizeHuaweiSpaceDatabaseName(_databaseName: string): string {
    return AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME;
  }

  private buildWebdavProviderId(endpoint: string, username: string): string {
    const normalizedEndpoint = endpoint.trim().replace(/\/+$/, '');
    const normalizedUsername = username.trim();
    const suffix = [
      AIRA_BOOKMARK_SYNC_PROTOCOL_ID,
      normalizedEndpoint,
      normalizedUsername,
      AIRA_SYNC_DEFAULT_ROOT
    ].map((value: string) => encodeURIComponent(value)).join(':');
    return `${DEFAULT_PROVIDER_ID}:${suffix}`;
  }

  private buildHuaweiCloudProviderId(uid: string): string {
    const suffix = uid.trim()
      .replace(/[^a-zA-Z0-9_-]+/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '');
    return suffix.length > 0 ? `aira-cloud-v3:${suffix}` : 'aira-cloud-v3';
  }

  private buildHuaweiSpaceProviderId(uid: string): string {
    const suffix = uid.trim()
      .replace(/[^a-zA-Z0-9_-]+/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '');
    return suffix.length > 0 ? `huawei-space-g8-blocks-v1:${suffix}` : 'huawei-space-g8-blocks-v1';
  }

  private buildProviderRuntimeIdentity(
    settings: AiraSyncSettings,
    remoteKind: AiraSyncProviderKind,
    domain: AiraSyncRuntimeDomainId
  ): string {
    if (remoteKind === 'webdav') {
      return [
        'sync-provider-g3',
        'webdav',
        settings.webdav.endpoint.trim().replace(/\/+$/, ''),
        settings.webdav.username.trim(),
        AIRA_SYNC_DEFAULT_ROOT
      ].map((value: string): string => encodeURIComponent(value)).join('|');
    }
    if (remoteKind === 'huawei_space') {
      return this.buildHuaweiSpaceRuntimeIdentity(
        settings.huaweiSpace.uid,
        settings.huaweiSpace.databaseName,
        domain
      );
    }
    if (remoteKind === 'self_hosted') {
      const config = resolveAiraPersonalServerConfig(settings);
      return [
        'sync-provider-g3',
        'self_hosted',
        config.instanceId.trim(),
        config.baseUrl.trim().replace(/\/+$/, '')
      ].map((value: string): string => encodeURIComponent(value)).join('|');
    }
    return [
      'sync-provider-g3',
      'aira_cloud',
      settings.huaweiCloud.uid.trim()
    ].map((value: string): string => encodeURIComponent(value)).join('|');
  }

  private buildHuaweiSpaceRuntimeIdentity(
    uid: string,
    databaseName: string,
    domain: AiraSyncRuntimeDomainId
  ): string {
    const protocolIdentity = domain === 'bookmark' || domain === 'bookmark_backup'
      ? 'sync-provider-g8-blocks-v1'
      : 'sync-provider-g2';
    return [
      protocolIdentity,
      'huawei_space',
      uid.trim(),
      this.normalizeHuaweiSpaceDatabaseName(databaseName)
    ].map((value: string): string => encodeURIComponent(value)).join('|');
  }

  private resolveProviderId(remoteKind: AiraSyncRemoteKind): string {
    return this.resolveProviderIdForSettings(this.cachedSettings, remoteKind);
  }

  private resolveProviderIdForSettings(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'webdav') {
      return this.buildWebdavProviderId(settings.webdav.endpoint, settings.webdav.username);
    }
    if (remoteKind === 'aira_cloud') {
      return this.buildHuaweiCloudProviderId(settings.huaweiCloud.uid);
    }
    if (remoteKind === 'huawei_space') {
      return this.buildHuaweiSpaceProviderId(settings.huaweiSpace.uid);
    }
    if (remoteKind === 'self_hosted') {
      const config = resolveAiraPersonalServerConfig(settings);
      return `aira-personal-server-v1:${encodeURIComponent(config.instanceId.trim())}`;
    }
    return DEFAULT_PROVIDER_ID;
  }

  private isRemoteKindConfigured(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): boolean {
    if (remoteKind === 'aira_cloud') {
      return settings.huaweiCloud.uid.trim().length > 0;
    }
    if (remoteKind === 'huawei_space') {
      return settings.huaweiSpace.uid.trim().length > 0;
    }
    if (remoteKind === 'webdav') {
      return settings.webdav.endpoint.trim().length > 0;
    }
    if (remoteKind === 'self_hosted') {
      const config = resolveAiraPersonalServerConfig(settings);
      return config.baseUrl.trim().length > 0 && config.instanceId.trim().length > 0 &&
        config.deviceToken.trim().length > 0;
    }
    return false;
  }

  private buildHuaweiCloudStatusProviderKey(uid: string, rootPath: string): string {
    return `aira_cloud|${uid.trim()}|${rootPath.trim()}`;
  }

  private buildHuaweiSpaceStatusProviderKey(uid: string, databaseName: string, rootPath: string): string {
    return buildAiraHuaweiSpaceRemoteStatusProviderKey(
      uid,
      this.normalizeHuaweiSpaceDatabaseName(databaseName),
      rootPath
    );
  }

  private buildRemoteStatusProviderKey(
    settings: AiraSyncSettings,
    remoteKind: AiraSyncProviderKind
  ): string {
    if (remoteKind === 'aira_cloud') {
      return this.buildHuaweiCloudStatusProviderKey(settings.huaweiCloud.uid, AIRA_SYNC_DEFAULT_ROOT);
    }
    if (remoteKind === 'huawei_space') {
      return this.buildHuaweiSpaceStatusProviderKey(
        settings.huaweiSpace.uid,
        settings.huaweiSpace.databaseName,
        AIRA_SYNC_DEFAULT_ROOT
      );
    }
    if (remoteKind === 'self_hosted') {
      const config = resolveAiraPersonalServerConfig(settings);
      return `self_hosted|${config.instanceId.trim()}|${config.baseUrl.trim().replace(/\/+$/, '')}`;
    }
    return buildAiraWebdavRemoteStatusProviderKey(
      settings.webdav.endpoint,
      settings.webdav.username,
      AIRA_SYNC_DEFAULT_ROOT
    );
  }
}

export function createDefaultAiraSyncSettings(): AiraSyncSettings {
  const sourceId = createAiraSyncSourceId();
  return {
    sourceId: sourceId,
    bookmarkGenerationInitializedAt: 0,
    remoteKind: 'none',
    bookmarkSyncEnabled: false,
    personalizationSyncEnabled: false,
    additionalBackupEnabled: false,
    additionalBackupRemoteKinds: [],
    additionalBackupIntervalDays: 7,
    providerStates: [
      {
        remoteKind: 'huawei_space',
        bookmark: createAiraSyncDomainRuntimeState(),
        personalization: createAiraSyncDomainRuntimeState(),
        bookmarkBackup: createAiraSyncDomainRuntimeState(),
        personalizationBackup: createAiraSyncDomainRuntimeState()
      },
      {
        remoteKind: 'webdav',
        bookmark: createAiraSyncDomainRuntimeState(),
        personalization: createAiraSyncDomainRuntimeState(),
        bookmarkBackup: createAiraSyncDomainRuntimeState(),
        personalizationBackup: createAiraSyncDomainRuntimeState()
      },
      {
        remoteKind: 'aira_cloud',
        bookmark: createAiraSyncDomainRuntimeState(),
        personalization: createAiraSyncDomainRuntimeState(),
        bookmarkBackup: createAiraSyncDomainRuntimeState(),
        personalizationBackup: createAiraSyncDomainRuntimeState()
      },
      {
        remoteKind: 'self_hosted',
        bookmark: createAiraSyncDomainRuntimeState(),
        personalization: createAiraSyncDomainRuntimeState(),
        bookmarkBackup: createAiraSyncDomainRuntimeState(),
        personalizationBackup: createAiraSyncDomainRuntimeState()
      }
    ],
    webdav: {
      endpoint: '',
      username: '',
      password: '',
      remoteStatusCache: null
    },
    huaweiCloud: {
      uid: '',
      displayName: '',
      photoUrl: '',
      remoteStatusCache: null,
      lastAuthAt: 0
    },
    huaweiSpace: {
      uid: '',
      displayName: '',
      photoUrl: '',
      databaseName: AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME,
      remoteStatusCache: null,
      lastAuthAt: 0
    },
    selfHosted: createDefaultAiraPersonalServerConfig(),
    updatedAt: 0,
    pendingBookmarkSyncAt: 0,
    pendingBookmarkProviderSwitchFrom: 'none'
  };
}
