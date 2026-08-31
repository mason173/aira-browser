import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  AdBlockCustomRuleSource,
  AdBlockCustomRuleSourceType,
  AdBlockDailyProtectionActivity,
  AdBlockPreferences,
  AdBlockSettings,
  AdBlockSiteException,
  AdBlockStats,
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID
} from '../../common/models/BrowserModels';
import {
  APP_PROMOTION_BANNER_RULE_SOURCE_ID,
  BUILT_IN_AD_BLOCK_RULE_SOURCE_ID,
  SMOOTH_MODE_AD_BLOCK_RULE_SOURCE_ID
} from '../../features/adblock/AdBlockBuiltInRuleSource';
import { isAdBlockThirdPartyRuleSourceId } from '../../features/adblock/AdBlockThirdPartyRuleSourceCatalog';

const PREFERENCES_NAME: string = 'aira_browser_adblock_v4';
const AD_BLOCK_SETTINGS_KEY: string = 'ad_block_settings';
const AD_BLOCK_RUNTIME_BOOT_SETTINGS_KEY: string = 'ad_block_runtime_boot_settings';
const AD_BLOCK_ENGINE_EPOCH_KEY: string = 'ad_block_engine_epoch';
const AD_BLOCK_LEGACY_PAYLOAD_CLEANUP_EPOCH_KEY: string = 'ad_block_legacy_payload_cleanup_epoch';
const AD_BLOCK_NATIVE_ARTIFACT_CLEANUP_EPOCH_KEY: string = 'ad_block_native_artifact_cleanup_epoch';
const AD_BLOCK_RUST_V1_ENGINE_EPOCH: string = 'rust-v1';
const LEGACY_AD_BLOCK_RULE_PAYLOAD_SOURCE_IDS_KEY: string = 'ad_block_rule_payload_source_ids';
const LEGACY_AD_BLOCK_RULE_PAYLOAD_PREFIX: string = 'ad_block_rule_payload_';
const LEGACY_AD_BLOCK_RULE_PAYLOAD_CHUNK_COUNT_SUFFIX: string = '__chunk_count';
const LEGACY_AD_BLOCK_RULE_PAYLOAD_CHUNK_PREFIX_SUFFIX: string = '__chunk_';
const MAX_LEGACY_AD_BLOCK_RULE_PAYLOAD_CHUNKS: number = 1024;
const MAX_CUSTOM_RULE_SOURCES: number = 12;
const AD_BLOCK_STATS_PERSIST_BATCH_SIZE: number = 20;
const AD_BLOCK_STATS_PERSIST_INTERVAL_MS: number = 5000;
const AD_BLOCK_STATS_DAILY_RETENTION_DAYS: number = 8;
export const AD_BLOCK_STATS_VERSION: number = 2;

export type AdBlockSettingsMutationKind =
  'update_preferences' |
  'add_site_exception' |
  'remove_site_exception' |
  'upsert_rule_source' |
  'set_rule_source_enabled' |
  'remove_rule_source';

export interface AdBlockSettingsMutation {
  kind: AdBlockSettingsMutationKind;
  changedAt: number;
  preferences?: AdBlockPreferences;
  host?: string;
  profileId?: BrowserProfileId;
  source?: AdBlockCustomRuleSource;
  sourceId?: string;
  enabled?: boolean;
}

export interface AdBlockPreparedSettingsCommit {
  settings: AdBlockSettings;
  shouldPersist: boolean;
}

export interface AdBlockProtectionActivityBreakdown {
  requestBlockingCount: number;
  linkCleaningCount: number;
  elementHidingCount: number;
  totalActionCount: number;
}

export interface AdBlockProtectionActivitySummary {
  today: AdBlockProtectionActivityBreakdown;
  lastSevenDays: AdBlockProtectionActivityBreakdown;
  lifetimeTotalActionCount: number;
  updatedAt: number;
}

export const DEFAULT_AD_BLOCK_PREFERENCES: AdBlockPreferences = {
  enabled: false,
  updateOnForeground: true
};

export const DEFAULT_AD_BLOCK_STATS: AdBlockStats = {
  statisticsVersion: AD_BLOCK_STATS_VERSION,
  totalBlockedCount: 0,
  networkBlockedCount: 0,
  urlParameterRemovedCount: 0,
  cosmeticElementHiddenCount: 0,
  manualElementHiddenCount: 0,
  totalProtectionActionCount: 0,
  dailyProtectionActivity: [],
  updatedAt: 0
};

export class AdBlockRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settings: AdBlockSettings = this.buildDefaultSettings();
  private metadataInitializationPromise?: Promise<AdBlockSettings>;
  private metadataInitialized: boolean = false;
  private runtimeBootStateInitializationPromise?: Promise<AdBlockSettings>;
  private runtimeBootStateInitialized: boolean = false;
  private engineEpochMigrationPromise?: Promise<void>;
  private nativeRuleArtifactCleanupPromise?: Promise<void>;
  private pendingStatsPersistCount: number = 0;
  private lastStatsPersistAt: number = 0;
  async initialize(): Promise<AdBlockSettings> {
    return this.initializeMetadata();
  }

  async initializeMetadata(): Promise<AdBlockSettings> {
    if (this.metadataInitialized) {
      return this.getSettings();
    }
    if (this.metadataInitializationPromise === undefined) {
      this.metadataInitializationPromise = this.loadMetadataFromStore()
        .catch((error: Error) => {
          this.metadataInitializationPromise = undefined;
          throw error;
        });
    }
    return this.metadataInitializationPromise;
  }

  async initializeRuntimeBootState(): Promise<AdBlockSettings> {
    if (this.metadataInitialized || this.runtimeBootStateInitialized) {
      return this.getSettings();
    }
    if (this.runtimeBootStateInitializationPromise === undefined) {
      this.runtimeBootStateInitializationPromise = this.loadRuntimeBootStateFromStore()
        .catch((error: Error) => {
          this.runtimeBootStateInitializationPromise = undefined;
          throw error;
        });
    }
    return this.runtimeBootStateInitializationPromise;
  }

  isRuntimeBootStateReady(): boolean {
    return this.metadataInitialized || this.runtimeBootStateInitialized;
  }

  async ensureRustV1NativeRuleArtifactCleanup(cleanup: () => Promise<void>): Promise<void> {
    const store = await this.getStore();
    await this.ensureRustV1EngineEpochMigration(store);
    if (String(store.getSync(AD_BLOCK_NATIVE_ARTIFACT_CLEANUP_EPOCH_KEY, '')).trim() ===
      AD_BLOCK_RUST_V1_ENGINE_EPOCH) {
      return;
    }
    if (this.nativeRuleArtifactCleanupPromise === undefined) {
      const cleanupPromise = cleanup()
        .then((): void => {
          store.putSync(AD_BLOCK_NATIVE_ARTIFACT_CLEANUP_EPOCH_KEY, AD_BLOCK_RUST_V1_ENGINE_EPOCH);
          store.flushSync();
        })
        .catch((error: Error): void => {
          if (this.nativeRuleArtifactCleanupPromise === cleanupPromise) {
            this.nativeRuleArtifactCleanupPromise = undefined;
          }
          throw error;
        });
      this.nativeRuleArtifactCleanupPromise = cleanupPromise;
    }
    return this.nativeRuleArtifactCleanupPromise;
  }

  getSettings(): AdBlockSettings {
    return this.cloneSettings(this.settings);
  }

  getProtectionActivitySummary(now: number = Date.now()): AdBlockProtectionActivitySummary {
    const todayStartedAt = this.resolveLocalDayStart(now);
    const sevenDayStartedAt = this.shiftLocalDayStart(todayStartedAt, -6);
    const today = this.emptyProtectionActivityBreakdown();
    const lastSevenDays = this.emptyProtectionActivityBreakdown();
    this.settings.stats.dailyProtectionActivity.forEach((activity: AdBlockDailyProtectionActivity): void => {
      if (activity.dayStartedAt >= sevenDayStartedAt && activity.dayStartedAt <= todayStartedAt) {
        this.accumulateProtectionActivity(lastSevenDays, activity);
      }
      if (activity.dayStartedAt === todayStartedAt) {
        this.accumulateProtectionActivity(today, activity);
      }
    });
    return {
      today: today,
      lastSevenDays: lastSevenDays,
      lifetimeTotalActionCount: this.settings.stats.totalProtectionActionCount,
      updatedAt: this.settings.stats.updatedAt
    };
  }

  getDailyProtectionActivityTimeline(
    dayCount: number = 7,
    now: number = Date.now()
  ): AdBlockDailyProtectionActivity[] {
    const normalizedDayCount: number = Math.max(1, Math.min(31, Math.floor(dayCount)));
    const todayStartedAt: number = this.resolveLocalDayStart(now);
    const timeline: AdBlockDailyProtectionActivity[] = [];
    for (let index: number = 0; index < normalizedDayCount; index += 1) {
      const dayStartedAt: number = this.shiftLocalDayStart(
        todayStartedAt,
        index - (normalizedDayCount - 1)
      );
      let matchingActivity: AdBlockDailyProtectionActivity | undefined = undefined;
      for (let activityIndex: number = 0;
        activityIndex < this.settings.stats.dailyProtectionActivity.length;
        activityIndex += 1) {
        const activity: AdBlockDailyProtectionActivity = this.settings.stats.dailyProtectionActivity[activityIndex];
        if (activity.dayStartedAt === dayStartedAt) {
          matchingActivity = activity;
          break;
        }
      }
      timeline.push(matchingActivity === undefined ? {
        dayStartedAt: dayStartedAt,
        networkBlockedCount: 0,
        urlParameterRemovedCount: 0,
        cosmeticElementHiddenCount: 0,
        manualElementHiddenCount: 0,
        totalProtectionActionCount: 0
      } : this.cloneDailyProtectionActivity(matchingActivity));
    }
    return timeline;
  }

  async prepareSettingsMutation(mutation: AdBlockSettingsMutation): Promise<AdBlockPreparedSettingsCommit> {
    await this.initializeMetadata();
    const changedAt = mutation.changedAt > 0 ? Math.floor(mutation.changedAt) : Date.now();
    if (mutation.kind === 'update_preferences' && mutation.preferences !== undefined) {
      return this.preparedSettingsCommit({
        preferences: this.normalizePreferences(mutation.preferences),
        siteExceptions: this.settings.siteExceptions.map((item: AdBlockSiteException) => this.cloneSiteException(item)),
        customRuleSources: this.settings.customRuleSources.map((item: AdBlockCustomRuleSource) =>
          this.cloneCustomRuleSource(item)),
        stats: this.cloneStats(this.settings.stats),
        lastRuleUpdateAt: this.settings.lastRuleUpdateAt,
        engineUnavailableReason: this.settings.engineUnavailableReason,
        updatedAt: changedAt
      });
    }
    if (mutation.kind === 'add_site_exception') {
      const normalizedHost = this.normalizeHost(mutation.host ?? '');
      const profileId = mutation.profileId ?? DEFAULT_BROWSER_PROFILE_ID;
      const existing = this.settings.siteExceptions.some((item: AdBlockSiteException) => {
        return item.host === normalizedHost && item.profileId === profileId;
      });
      if (normalizedHost.length === 0 || existing) {
        return this.preparedSettingsCommit(this.getSettings(), false);
      }
      return this.preparedSettingsCommit({
        preferences: this.clonePreferences(this.settings.preferences),
        siteExceptions: this.settings.siteExceptions.concat([{
          profileId: profileId,
          host: normalizedHost,
          includeSubdomains: true,
          createdAt: changedAt
        }]),
        customRuleSources: this.settings.customRuleSources.map((item: AdBlockCustomRuleSource) =>
          this.cloneCustomRuleSource(item)),
        stats: this.cloneStats(this.settings.stats),
        lastRuleUpdateAt: this.settings.lastRuleUpdateAt,
        engineUnavailableReason: this.settings.engineUnavailableReason,
        updatedAt: changedAt
      });
    }
    if (mutation.kind === 'remove_site_exception') {
      const normalizedHost = this.normalizeHost(mutation.host ?? '');
      const profileId = mutation.profileId ?? DEFAULT_BROWSER_PROFILE_ID;
      return this.preparedSettingsCommit({
        preferences: this.clonePreferences(this.settings.preferences),
        siteExceptions: this.settings.siteExceptions.filter((item: AdBlockSiteException) => {
          return item.host !== normalizedHost || item.profileId !== profileId;
        }),
        customRuleSources: this.settings.customRuleSources.map((item: AdBlockCustomRuleSource) =>
          this.cloneCustomRuleSource(item)),
        stats: this.cloneStats(this.settings.stats),
        lastRuleUpdateAt: this.settings.lastRuleUpdateAt,
        engineUnavailableReason: this.settings.engineUnavailableReason,
        updatedAt: changedAt
      });
    }
    if (mutation.kind === 'upsert_rule_source' && mutation.source !== undefined) {
      const normalizedSource = this.normalizeCustomRuleSource(mutation.source);
      if (normalizedSource.url.length === 0) {
        return this.preparedSettingsCommit(this.getSettings(), false);
      }
      const existingSources = this.settings.customRuleSources.filter((item: AdBlockCustomRuleSource) => {
        return item.id !== normalizedSource.id && item.url !== normalizedSource.url;
      });
      return this.preparedSettingsCommit({
        preferences: this.clonePreferences(this.settings.preferences),
        siteExceptions: this.settings.siteExceptions.map((item: AdBlockSiteException) => this.cloneSiteException(item)),
        customRuleSources: this.limitCustomRuleSources(existingSources.concat([normalizedSource])),
        stats: this.cloneStats(this.settings.stats),
        lastRuleUpdateAt: changedAt,
        engineUnavailableReason: this.settings.engineUnavailableReason,
        updatedAt: changedAt
      });
    }
    if (mutation.kind === 'set_rule_source_enabled') {
      const sourceId = mutation.sourceId ?? '';
      const nextSources = this.settings.customRuleSources.map((item: AdBlockCustomRuleSource) => {
        if (item.id !== sourceId) {
          return this.cloneCustomRuleSource(item);
        }
        const nextItem = this.cloneCustomRuleSource(item);
        nextItem.enabled = mutation.enabled === true;
        nextItem.updatedAt = changedAt;
        return nextItem;
      });
      return this.preparedSettingsCommit({
        preferences: this.clonePreferences(this.settings.preferences),
        siteExceptions: this.settings.siteExceptions.map((item: AdBlockSiteException) => this.cloneSiteException(item)),
        customRuleSources: nextSources,
        stats: this.cloneStats(this.settings.stats),
        lastRuleUpdateAt: this.settings.lastRuleUpdateAt,
        engineUnavailableReason: this.settings.engineUnavailableReason,
        updatedAt: changedAt
      });
    }
    if (mutation.kind === 'remove_rule_source') {
      const sourceId = mutation.sourceId ?? '';
      return this.preparedSettingsCommit({
        preferences: this.clonePreferences(this.settings.preferences),
        siteExceptions: this.settings.siteExceptions.map((item: AdBlockSiteException) => this.cloneSiteException(item)),
        customRuleSources: this.settings.customRuleSources.filter((item: AdBlockCustomRuleSource) => item.id !== sourceId),
        stats: this.cloneStats(this.settings.stats),
        lastRuleUpdateAt: this.settings.lastRuleUpdateAt,
        engineUnavailableReason: this.settings.engineUnavailableReason,
        updatedAt: changedAt
      });
    }
    return this.preparedSettingsCommit(this.getSettings(), false);
  }

  async commitPreparedSettings(prepared: AdBlockPreparedSettingsCommit): Promise<AdBlockSettings> {
    if (!prepared.shouldPersist) {
      return this.getSettings();
    }
    return this.persistSettings(prepared.settings);
  }

  async clearStats(): Promise<AdBlockSettings> {
    await this.initializeMetadata();
    this.pendingStatsPersistCount = 0;
    this.lastStatsPersistAt = Date.now();
    const now = Date.now();
    const nextSettings: AdBlockSettings = {
      preferences: this.clonePreferences(this.settings.preferences),
      siteExceptions: this.settings.siteExceptions.map((item: AdBlockSiteException) => this.cloneSiteException(item)),
      customRuleSources: this.settings.customRuleSources.map((item: AdBlockCustomRuleSource) => this.cloneCustomRuleSource(item)),
      stats: {
        statisticsVersion: AD_BLOCK_STATS_VERSION,
        totalBlockedCount: 0,
        networkBlockedCount: 0,
        urlParameterRemovedCount: 0,
        cosmeticElementHiddenCount: 0,
        manualElementHiddenCount: 0,
        totalProtectionActionCount: 0,
        dailyProtectionActivity: [],
        updatedAt: now
      },
      lastRuleUpdateAt: this.settings.lastRuleUpdateAt,
      engineUnavailableReason: this.settings.engineUnavailableReason,
      updatedAt: now
    };
    return this.persistSettings(nextSettings);
  }

  async recordBlockedRequest(
    _profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: string = 'profile_persistent'
  ): Promise<AdBlockSettings> {
    if (dataScope === 'session_ephemeral') {
      return this.getSettings();
    }
    return this.recordStatsDelta(1, 0, 0, 0);
  }

  async recordUrlParametersRemoved(
    _profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: string = 'profile_persistent',
    _removedParameterCount: number = 1
  ): Promise<AdBlockSettings> {
    if (dataScope === 'session_ephemeral') {
      return this.getSettings();
    }
    // The user-visible unit is one cleaned navigation URL, not the number of
    // query parameters that happened to be removed from it.
    return this.recordStatsDelta(0, 1, 0, 0);
  }

  async recordCosmeticElementsHidden(
    _profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: string = 'profile_persistent',
    hiddenElementCount: number = 1
  ): Promise<AdBlockSettings> {
    if (dataScope === 'session_ephemeral') {
      return this.getSettings();
    }
    const count = Math.max(0, Math.floor(hiddenElementCount));
    if (count <= 0) {
      return this.getSettings();
    }
    return this.recordStatsDelta(0, 0, count, 0);
  }

  async recordManualElementsHidden(
    _profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: string = 'profile_persistent',
    hiddenElementCount: number = 1
  ): Promise<AdBlockSettings> {
    if (dataScope === 'session_ephemeral') {
      return this.getSettings();
    }
    const count = Math.max(0, Math.floor(hiddenElementCount));
    if (count <= 0) {
      return this.getSettings();
    }
    return this.recordStatsDelta(0, 0, 0, count);
  }

  private normalizeSettings(value: AdBlockSettings | undefined): AdBlockSettings {
    return {
      preferences: this.normalizePreferences(value?.preferences),
      siteExceptions: this.normalizeSiteExceptions(value?.siteExceptions ?? []),
      customRuleSources: this.normalizeCustomRuleSources(value?.customRuleSources ?? []),
      stats: this.normalizeStats(value?.stats),
      lastRuleUpdateAt: this.normalizeTimestamp(value?.lastRuleUpdateAt),
      engineUnavailableReason: (value?.engineUnavailableReason ?? '').trim(),
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizePreferences(value: AdBlockPreferences | undefined): AdBlockPreferences {
    return {
      enabled: typeof value?.enabled === 'boolean' ? value.enabled : DEFAULT_AD_BLOCK_PREFERENCES.enabled,
      updateOnForeground: typeof value?.updateOnForeground === 'boolean'
        ? value.updateOnForeground
        : DEFAULT_AD_BLOCK_PREFERENCES.updateOnForeground
    };
  }

  private normalizeSiteExceptions(values: AdBlockSiteException[]): AdBlockSiteException[] {
    const results: AdBlockSiteException[] = [];
    values.forEach((item: AdBlockSiteException) => {
      const host = this.normalizeHost(item.host);
      if (host.length === 0) {
        return;
      }
      results.push({
        profileId: item.profileId === DEFAULT_BROWSER_PROFILE_ID ? DEFAULT_BROWSER_PROFILE_ID : DEFAULT_BROWSER_PROFILE_ID,
        host: host,
        includeSubdomains: typeof item.includeSubdomains === 'boolean' ? item.includeSubdomains : true,
        createdAt: this.normalizeTimestamp(item.createdAt)
      });
    });
    return results;
  }

  private normalizeCustomRuleSources(values: AdBlockCustomRuleSource[]): AdBlockCustomRuleSource[] {
    const results: AdBlockCustomRuleSource[] = [];
    values.forEach((item: AdBlockCustomRuleSource) => {
      const source = this.normalizeCustomRuleSource(item);
      if (source.id !== BUILT_IN_AD_BLOCK_RULE_SOURCE_ID &&
        source.id !== SMOOTH_MODE_AD_BLOCK_RULE_SOURCE_ID &&
        source.id !== APP_PROMOTION_BANNER_RULE_SOURCE_ID &&
        source.url.length > 0 &&
        !this.isFailedEmptyCustomRuleSource(source)) {
        results.push(source);
      }
    });
    return this.limitCustomRuleSources(results);
  }

  private isFailedEmptyCustomRuleSource(source: AdBlockCustomRuleSource): boolean {
    return source.ruleCount <= 0 && source.lastError.trim().length > 0;
  }

  private normalizeCustomRuleSource(value: AdBlockCustomRuleSource): AdBlockCustomRuleSource {
    const url = (value.url ?? '').trim();
    const now = Date.now();
    const nativeNetworkRuleCount: number | undefined = typeof value.nativeNetworkRuleCount === 'number'
      ? Math.max(0, Math.floor(value.nativeNetworkRuleCount))
      : undefined;
    const nativeCosmeticRuleCount: number | undefined = typeof value.nativeCosmeticRuleCount === 'number'
      ? Math.max(0, Math.floor(value.nativeCosmeticRuleCount))
      : undefined;
    const explicitRuleCount = typeof value.ruleCount === 'number' && value.ruleCount > 0
      ? Math.floor(value.ruleCount)
      : 0;
    const normalizedRuleCount = nativeNetworkRuleCount !== undefined && nativeCosmeticRuleCount !== undefined
      ? nativeNetworkRuleCount + nativeCosmeticRuleCount
      : explicitRuleCount;
    return {
      id: (value.id ?? '').trim().length > 0 ? value.id.trim() : this.buildSourceId(url),
      payloadIdentity: typeof value.payloadIdentity === 'string' ? value.payloadIdentity.trim().slice(0, 128) : '',
      title: (value.title ?? '').trim().length > 0 ? value.title.trim() : this.buildSourceTitle(url),
      url: url,
      sourceType: this.normalizeSourceType(value.sourceType),
      enabled: typeof value.enabled === 'boolean' ? value.enabled : true,
      nativeNetworkRuleCount: nativeNetworkRuleCount,
      nativeCosmeticRuleCount: nativeCosmeticRuleCount,
      ruleCount: normalizedRuleCount > 0 ? normalizedRuleCount : explicitRuleCount,
      lastUpdatedAt: this.normalizeTimestamp(value.lastUpdatedAt),
      lastError: (value.lastError ?? '').trim(),
      createdAt: this.normalizeTimestamp(value.createdAt) > 0 ? this.normalizeTimestamp(value.createdAt) : now,
      updatedAt: this.normalizeTimestamp(value.updatedAt) > 0 ? this.normalizeTimestamp(value.updatedAt) : now
    };
  }

  private normalizeStats(value: AdBlockStats | undefined): AdBlockStats {
    if (value?.statisticsVersion !== AD_BLOCK_STATS_VERSION) {
      return this.cloneStats(DEFAULT_AD_BLOCK_STATS);
    }
    const networkBlockedCount = this.normalizeCount(value.networkBlockedCount);
    const urlParameterRemovedCount = this.normalizeCount(value?.urlParameterRemovedCount);
    const cosmeticElementHiddenCount = this.normalizeCount(value?.cosmeticElementHiddenCount);
    const manualElementHiddenCount = this.normalizeCount(value?.manualElementHiddenCount);
    const computedTotal = networkBlockedCount +
      urlParameterRemovedCount +
      cosmeticElementHiddenCount +
      manualElementHiddenCount;
    const totalProtectionActionCount = computedTotal;
    return {
      statisticsVersion: AD_BLOCK_STATS_VERSION,
      totalBlockedCount: computedTotal,
      networkBlockedCount: networkBlockedCount,
      urlParameterRemovedCount: urlParameterRemovedCount,
      cosmeticElementHiddenCount: cosmeticElementHiddenCount,
      manualElementHiddenCount: manualElementHiddenCount,
      totalProtectionActionCount: totalProtectionActionCount,
      dailyProtectionActivity: this.normalizeDailyProtectionActivity(value?.dailyProtectionActivity ?? []),
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizeDailyProtectionActivity(
    values: AdBlockDailyProtectionActivity[],
    now: number = Date.now()
  ): AdBlockDailyProtectionActivity[] {
    if (!Array.isArray(values)) {
      return [];
    }
    const todayStartedAt = this.resolveLocalDayStart(now);
    const earliestRetainedAt = this.shiftLocalDayStart(
      todayStartedAt,
      -(AD_BLOCK_STATS_DAILY_RETENTION_DAYS - 1)
    );
    const normalized: AdBlockDailyProtectionActivity[] = [];
    values.forEach((value: AdBlockDailyProtectionActivity): void => {
      const timestamp = this.normalizeTimestamp(value?.dayStartedAt);
      if (timestamp <= 0) {
        return;
      }
      const dayStartedAt = this.resolveLocalDayStart(timestamp);
      if (dayStartedAt < earliestRetainedAt || dayStartedAt > todayStartedAt) {
        return;
      }
      const candidate = this.buildDailyProtectionActivity(
        dayStartedAt,
        this.normalizeCount(value?.networkBlockedCount),
        this.normalizeCount(value?.urlParameterRemovedCount),
        this.normalizeCount(value?.cosmeticElementHiddenCount),
        this.normalizeCount(value?.manualElementHiddenCount)
      );
      const existingIndex = normalized.findIndex((item: AdBlockDailyProtectionActivity): boolean => {
        return item.dayStartedAt === dayStartedAt;
      });
      if (existingIndex < 0) {
        normalized.push(candidate);
        return;
      }
      const existing = normalized[existingIndex];
      normalized[existingIndex] = this.buildDailyProtectionActivity(
        dayStartedAt,
        existing.networkBlockedCount + candidate.networkBlockedCount,
        existing.urlParameterRemovedCount + candidate.urlParameterRemovedCount,
        existing.cosmeticElementHiddenCount + candidate.cosmeticElementHiddenCount,
        existing.manualElementHiddenCount + candidate.manualElementHiddenCount
      );
    });
    normalized.sort((left: AdBlockDailyProtectionActivity, right: AdBlockDailyProtectionActivity): number => {
      return left.dayStartedAt - right.dayStartedAt;
    });
    return normalized.slice(-AD_BLOCK_STATS_DAILY_RETENTION_DAYS);
  }

  private mergeDailyProtectionActivity(
    values: AdBlockDailyProtectionActivity[],
    now: number,
    networkBlockedDelta: number,
    cleanedUrlDelta: number,
    cosmeticHiddenDelta: number,
    manualHiddenDelta: number
  ): AdBlockDailyProtectionActivity[] {
    const dayStartedAt = this.resolveLocalDayStart(now);
    const normalized = this.normalizeDailyProtectionActivity(values, now);
    const existingIndex = normalized.findIndex((item: AdBlockDailyProtectionActivity): boolean => {
      return item.dayStartedAt === dayStartedAt;
    });
    const current = existingIndex >= 0
      ? normalized[existingIndex]
      : this.buildDailyProtectionActivity(dayStartedAt, 0, 0, 0, 0);
    const next = this.buildDailyProtectionActivity(
      dayStartedAt,
      current.networkBlockedCount + this.normalizeCount(networkBlockedDelta),
      current.urlParameterRemovedCount + this.normalizeCount(cleanedUrlDelta),
      current.cosmeticElementHiddenCount + this.normalizeCount(cosmeticHiddenDelta),
      current.manualElementHiddenCount + this.normalizeCount(manualHiddenDelta)
    );
    if (existingIndex >= 0) {
      normalized[existingIndex] = next;
    } else {
      normalized.push(next);
    }
    return this.normalizeDailyProtectionActivity(normalized, now);
  }

  private buildDailyProtectionActivity(
    dayStartedAt: number,
    networkBlockedCount: number,
    urlParameterRemovedCount: number,
    cosmeticElementHiddenCount: number,
    manualElementHiddenCount: number
  ): AdBlockDailyProtectionActivity {
    const totalProtectionActionCount = networkBlockedCount +
      urlParameterRemovedCount +
      cosmeticElementHiddenCount +
      manualElementHiddenCount;
    return {
      dayStartedAt: dayStartedAt,
      networkBlockedCount: networkBlockedCount,
      urlParameterRemovedCount: urlParameterRemovedCount,
      cosmeticElementHiddenCount: cosmeticElementHiddenCount,
      manualElementHiddenCount: manualElementHiddenCount,
      totalProtectionActionCount: totalProtectionActionCount
    };
  }

  private emptyProtectionActivityBreakdown(): AdBlockProtectionActivityBreakdown {
    return {
      requestBlockingCount: 0,
      linkCleaningCount: 0,
      elementHidingCount: 0,
      totalActionCount: 0
    };
  }

  private accumulateProtectionActivity(
    target: AdBlockProtectionActivityBreakdown,
    activity: AdBlockDailyProtectionActivity
  ): void {
    target.requestBlockingCount += activity.networkBlockedCount;
    target.linkCleaningCount += activity.urlParameterRemovedCount;
    target.elementHidingCount += activity.cosmeticElementHiddenCount + activity.manualElementHiddenCount;
    target.totalActionCount = target.requestBlockingCount +
      target.linkCleaningCount +
      target.elementHidingCount;
  }

  private resolveLocalDayStart(timestamp: number): number {
    const date = new Date(timestamp);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  }

  private shiftLocalDayStart(dayStartedAt: number, dayOffset: number): number {
    const date = new Date(dayStartedAt);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + dayOffset).getTime();
  }

  private normalizeCount(value: number | undefined): number {
    return typeof value === 'number' && value > 0 ? Math.floor(value) : 0;
  }

  private normalizeHost(value: string): string {
    let host = value.trim().toLowerCase();
    if (host.startsWith('http://')) {
      host = host.substring(7);
    } else if (host.startsWith('https://')) {
      host = host.substring(8);
    }
    const pathStart = host.indexOf('/');
    if (pathStart >= 0) {
      host = host.substring(0, pathStart);
    }
    const portStart = host.indexOf(':');
    if (portStart >= 0) {
      host = host.substring(0, portStart);
    }
    return host;
  }

  private parseSettings(value: string): AdBlockSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as AdBlockSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private buildDefaultSettings(): AdBlockSettings {
    return {
      preferences: this.clonePreferences(DEFAULT_AD_BLOCK_PREFERENCES),
      siteExceptions: [],
      customRuleSources: [],
      stats: this.cloneStats(DEFAULT_AD_BLOCK_STATS),
      lastRuleUpdateAt: 0,
      engineUnavailableReason: '',
      updatedAt: 0
    };
  }

  private async loadMetadataFromStore(): Promise<AdBlockSettings> {
    const store = await this.getStore();
    await this.ensureRustV1EngineEpochMigration(store);
    const rawSettings = String(store.getSync(AD_BLOCK_SETTINGS_KEY, ''));
    const parsedSettings = this.parseSettings(rawSettings);
    const statsResetRequired = parsedSettings?.stats?.statisticsVersion !== AD_BLOCK_STATS_VERSION;
    this.settings = this.normalizeSettings(parsedSettings);
    if (rawSettings.trim().length === 0) {
      await this.persistSettings(this.settings);
      return this.getSettings();
    }
    const parsedSources = parsedSettings === undefined ? [] : parsedSettings.customRuleSources;
    const parsedSourceCount = Array.isArray(parsedSources) ? parsedSources.length : 0;
    if (statsResetRequired || parsedSourceCount !== this.settings.customRuleSources.length) {
      await this.persistSettings(this.settings);
      return this.getSettings();
    }
    this.writeRuntimeBootSettings(store, this.settings);
    store.flushSync();
    this.metadataInitialized = true;
    this.runtimeBootStateInitialized = true;
    return this.getSettings();
  }

  private async loadRuntimeBootStateFromStore(): Promise<AdBlockSettings> {
    const store = await this.getStore();
    await this.ensureRustV1EngineEpochMigration(store);
    const rawBootSettings = String(store.getSync(AD_BLOCK_RUNTIME_BOOT_SETTINGS_KEY, ''));
    const parsedBootSettings = this.parseSettings(rawBootSettings);
    if (parsedBootSettings !== undefined) {
      this.settings = this.normalizeSettings(parsedBootSettings);
      this.runtimeBootStateInitialized = true;
      return this.getSettings();
    }

    const rawSettings = String(store.getSync(AD_BLOCK_SETTINGS_KEY, ''));
    const parsedSettings = this.parseSettings(rawSettings);
    if (parsedSettings !== undefined) {
      this.settings = this.normalizeSettings(parsedSettings);
      this.writeRuntimeBootSettings(store, this.settings);
      store.flushSync();
      this.metadataInitialized = true;
      this.runtimeBootStateInitialized = true;
      return this.getSettings();
    }

    this.runtimeBootStateInitialized = true;
    return this.getSettings();
  }

  private async persistSettings(settings: AdBlockSettings): Promise<AdBlockSettings> {
    const committedSettings = this.cloneSettings(settings);
    const store = await this.getStore();
    store.putSync(AD_BLOCK_SETTINGS_KEY, JSON.stringify(committedSettings));
    this.writeRuntimeBootSettings(store, committedSettings);
    store.flushSync();
    this.settings = committedSettings;
    this.pendingStatsPersistCount = 0;
    this.lastStatsPersistAt = Date.now();
    this.metadataInitialized = true;
    this.runtimeBootStateInitialized = true;
    return this.getSettings();
  }

  private ensureRustV1EngineEpochMigration(store: preferences.Preferences): Promise<void> {
    if (this.engineEpochMigrationPromise === undefined) {
      const migrationPromise = this.migrateToRustV1EngineEpoch(store)
        .catch((error: Error): void => {
          if (this.engineEpochMigrationPromise === migrationPromise) {
            this.engineEpochMigrationPromise = undefined;
          }
          throw error;
        });
      this.engineEpochMigrationPromise = migrationPromise;
    }
    return this.engineEpochMigrationPromise;
  }

  private async migrateToRustV1EngineEpoch(store: preferences.Preferences): Promise<void> {
    const rawSettings = String(store.getSync(AD_BLOCK_SETTINGS_KEY, ''));
    const rawBootSettings = String(store.getSync(AD_BLOCK_RUNTIME_BOOT_SETTINGS_KEY, ''));
    const parsedSettings = this.parseSettings(rawSettings);
    const parsedBootSettings = this.parseSettings(rawBootSettings);
    const engineEpoch = String(store.getSync(AD_BLOCK_ENGINE_EPOCH_KEY, '')).trim();
    if (engineEpoch !== AD_BLOCK_RUST_V1_ENGINE_EPOCH) {
      const migratedSettings = this.buildRustV1MigratedSettings(parsedSettings ?? parsedBootSettings);
      store.putSync(AD_BLOCK_SETTINGS_KEY, JSON.stringify(migratedSettings));
      this.writeRuntimeBootSettings(store, migratedSettings);
      store.putSync(AD_BLOCK_ENGINE_EPOCH_KEY, AD_BLOCK_RUST_V1_ENGINE_EPOCH);
      store.deleteSync(AD_BLOCK_NATIVE_ARTIFACT_CLEANUP_EPOCH_KEY);
      store.flushSync();
    }

    const legacyCleanupEpoch = String(store.getSync(AD_BLOCK_LEGACY_PAYLOAD_CLEANUP_EPOCH_KEY, '')).trim();
    if (legacyCleanupEpoch === AD_BLOCK_RUST_V1_ENGINE_EPOCH) {
      return;
    }
    const sourceIds = this.collectLegacyRulePayloadSourceIds(store, parsedSettings, parsedBootSettings);
    sourceIds.forEach((sourceId: string): void => {
      this.clearLegacyRulePayload(store, sourceId);
    });
    store.deleteSync(LEGACY_AD_BLOCK_RULE_PAYLOAD_SOURCE_IDS_KEY);
    store.putSync(AD_BLOCK_LEGACY_PAYLOAD_CLEANUP_EPOCH_KEY, AD_BLOCK_RUST_V1_ENGINE_EPOCH);
    store.flushSync();
  }

  private buildRustV1MigratedSettings(value: AdBlockSettings | undefined): AdBlockSettings {
    const normalized = this.normalizeSettings(value);
    const now = Date.now();
    let rawSources: AdBlockCustomRuleSource[] = [];
    if (value !== undefined && Array.isArray(value.customRuleSources)) {
      rawSources = value.customRuleSources;
    }
    const migratedSources: AdBlockCustomRuleSource[] = [];
    rawSources.forEach((value: AdBlockCustomRuleSource): void => {
      const source = this.normalizeCustomRuleSource(value);
      if (source.sourceType === 'system' || source.id === BUILT_IN_AD_BLOCK_RULE_SOURCE_ID ||
        source.id === SMOOTH_MODE_AD_BLOCK_RULE_SOURCE_ID || source.id === APP_PROMOTION_BANNER_RULE_SOURCE_ID ||
        source.url.length <= 0) {
        return;
      }
      source.enabled = false;
      source.payloadIdentity = '';
      source.nativeNetworkRuleCount = undefined;
      source.nativeCosmeticRuleCount = undefined;
      source.ruleCount = 0;
      source.lastUpdatedAt = 0;
      source.lastError = '';
      source.updatedAt = now;
      migratedSources.push(source);
    });
    return {
      preferences: {
        enabled: false,
        updateOnForeground: normalized.preferences.updateOnForeground
      },
      siteExceptions: normalized.siteExceptions.map((item: AdBlockSiteException) => this.cloneSiteException(item)),
      customRuleSources: this.limitCustomRuleSources(migratedSources),
      stats: this.cloneStats(normalized.stats),
      lastRuleUpdateAt: 0,
      engineUnavailableReason: '',
      updatedAt: now
    };
  }

  private collectLegacyRulePayloadSourceIds(
    store: preferences.Preferences,
    settings: AdBlockSettings | undefined,
    bootSettings: AdBlockSettings | undefined
  ): string[] {
    const sourceIds: string[] = [];
    this.appendLegacyRulePayloadSourceIds(sourceIds, this.readLegacyRulePayloadSourceIds(store));
    this.appendLegacyRulePayloadSourceIdsFromSettings(sourceIds, settings);
    this.appendLegacyRulePayloadSourceIdsFromSettings(sourceIds, bootSettings);
    return sourceIds;
  }

  private appendLegacyRulePayloadSourceIdsFromSettings(
    target: string[],
    settings: AdBlockSettings | undefined
  ): void {
    let sources: AdBlockCustomRuleSource[] = [];
    if (settings !== undefined && Array.isArray(settings.customRuleSources)) {
      sources = settings.customRuleSources;
    }
    this.appendLegacyRulePayloadSourceIds(
      target,
      sources.map((source: AdBlockCustomRuleSource): string => String(source.id ?? '').trim())
    );
  }

  private appendLegacyRulePayloadSourceIds(target: string[], candidates: string[]): void {
    candidates.forEach((candidate: string): void => {
      const sourceId = candidate.trim();
      if (!/^[A-Za-z0-9._-]{1,128}$/.test(sourceId) || target.indexOf(sourceId) >= 0) {
        return;
      }
      target.push(sourceId);
    });
  }

  private readLegacyRulePayloadSourceIds(store: preferences.Preferences): string[] {
    const payload = String(store.getSync(LEGACY_AD_BLOCK_RULE_PAYLOAD_SOURCE_IDS_KEY, ''));
    if (payload.trim().length <= 0) {
      return [];
    }
    try {
      const values = JSON.parse(payload) as string[];
      return Array.isArray(values) ? values : [];
    } catch (_error) {
      return [];
    }
  }

  private clearLegacyRulePayload(store: preferences.Preferences, sourceId: string): void {
    const chunkCountKey = this.buildLegacyRulePayloadChunkCountKey(sourceId);
    const rawChunkCount = Number(store.getSync(chunkCountKey, 0));
    const chunkCount = Number.isFinite(rawChunkCount) && rawChunkCount > 0
      ? Math.min(MAX_LEGACY_AD_BLOCK_RULE_PAYLOAD_CHUNKS, Math.floor(rawChunkCount))
      : 0;
    store.deleteSync(this.buildLegacyRulePayloadKey(sourceId));
    for (let index = 0; index < chunkCount; index += 1) {
      store.deleteSync(this.buildLegacyRulePayloadChunkKey(sourceId, index));
    }
    store.deleteSync(chunkCountKey);
  }

  private buildLegacyRulePayloadKey(sourceId: string): string {
    return `${LEGACY_AD_BLOCK_RULE_PAYLOAD_PREFIX}${sourceId}`;
  }

  private buildLegacyRulePayloadChunkCountKey(sourceId: string): string {
    return `${this.buildLegacyRulePayloadKey(sourceId)}${LEGACY_AD_BLOCK_RULE_PAYLOAD_CHUNK_COUNT_SUFFIX}`;
  }

  private buildLegacyRulePayloadChunkKey(sourceId: string, index: number): string {
    return `${this.buildLegacyRulePayloadKey(sourceId)}${LEGACY_AD_BLOCK_RULE_PAYLOAD_CHUNK_PREFIX_SUFFIX}${index}`;
  }

  private async recordStatsDelta(
    networkBlockedDelta: number,
    cleanedUrlDelta: number,
    cosmeticHiddenDelta: number,
    manualHiddenDelta: number
  ): Promise<AdBlockSettings> {
    if (!this.metadataInitialized) {
      await this.initializeMetadata();
    }
    const now = Date.now();
    const networkBlockedCount = this.settings.stats.networkBlockedCount + Math.max(0, Math.floor(networkBlockedDelta));
    const urlParameterRemovedCount = this.settings.stats.urlParameterRemovedCount + Math.max(0, Math.floor(cleanedUrlDelta));
    const cosmeticElementHiddenCount = this.settings.stats.cosmeticElementHiddenCount + Math.max(0, Math.floor(cosmeticHiddenDelta));
    const manualElementHiddenCount = this.settings.stats.manualElementHiddenCount + Math.max(0, Math.floor(manualHiddenDelta));
    const totalProtectionActionCount = networkBlockedCount + urlParameterRemovedCount +
      cosmeticElementHiddenCount + manualElementHiddenCount;
    this.settings.stats = {
      statisticsVersion: AD_BLOCK_STATS_VERSION,
      totalBlockedCount: totalProtectionActionCount,
      networkBlockedCount: networkBlockedCount,
      urlParameterRemovedCount: urlParameterRemovedCount,
      cosmeticElementHiddenCount: cosmeticElementHiddenCount,
      manualElementHiddenCount: manualElementHiddenCount,
      totalProtectionActionCount: totalProtectionActionCount,
      dailyProtectionActivity: this.mergeDailyProtectionActivity(
        this.settings.stats.dailyProtectionActivity,
        now,
        networkBlockedDelta,
        cleanedUrlDelta,
        cosmeticHiddenDelta,
        manualHiddenDelta
      ),
      updatedAt: now
    };
    this.settings.updatedAt = now;
    this.pendingStatsPersistCount += 1;
    if (!this.shouldPersistStats(now)) {
      return this.getSettings();
    }
    this.pendingStatsPersistCount = 0;
    this.lastStatsPersistAt = now;
    return this.persistSettings(this.settings);
  }

  private preparedSettingsCommit(
    settings: AdBlockSettings,
    shouldPersist: boolean = true
  ): AdBlockPreparedSettingsCommit {
    return {
      settings: settings,
      shouldPersist: shouldPersist
    };
  }

  private writeRuntimeBootSettings(store: preferences.Preferences, settings: AdBlockSettings): void {
    store.putSync(AD_BLOCK_RUNTIME_BOOT_SETTINGS_KEY, JSON.stringify(settings));
  }

  private shouldPersistStats(now: number): boolean {
    if (this.lastStatsPersistAt <= 0) {
      this.lastStatsPersistAt = now;
      return this.pendingStatsPersistCount >= AD_BLOCK_STATS_PERSIST_BATCH_SIZE;
    }
    return this.pendingStatsPersistCount >= AD_BLOCK_STATS_PERSIST_BATCH_SIZE ||
      now - this.lastStatsPersistAt >= AD_BLOCK_STATS_PERSIST_INTERVAL_MS;
  }

  private cloneSettings(settings: AdBlockSettings): AdBlockSettings {
    return {
      preferences: this.clonePreferences(settings.preferences),
      siteExceptions: settings.siteExceptions.map((item: AdBlockSiteException) => this.cloneSiteException(item)),
      customRuleSources: settings.customRuleSources.map((item: AdBlockCustomRuleSource) => this.cloneCustomRuleSource(item)),
      stats: this.cloneStats(settings.stats),
      lastRuleUpdateAt: settings.lastRuleUpdateAt,
      engineUnavailableReason: settings.engineUnavailableReason,
      updatedAt: settings.updatedAt
    };
  }

  private clonePreferences(value: AdBlockPreferences): AdBlockPreferences {
    return {
      enabled: value.enabled,
      updateOnForeground: value.updateOnForeground
    };
  }

  private cloneStats(value: AdBlockStats): AdBlockStats {
    return {
      statisticsVersion: value.statisticsVersion,
      totalBlockedCount: value.totalBlockedCount,
      networkBlockedCount: value.networkBlockedCount,
      urlParameterRemovedCount: value.urlParameterRemovedCount,
      cosmeticElementHiddenCount: value.cosmeticElementHiddenCount,
      manualElementHiddenCount: value.manualElementHiddenCount,
      totalProtectionActionCount: value.totalProtectionActionCount,
      dailyProtectionActivity: value.dailyProtectionActivity.map((activity: AdBlockDailyProtectionActivity) => {
        return this.cloneDailyProtectionActivity(activity);
      }),
      updatedAt: value.updatedAt
    };
  }

  private cloneDailyProtectionActivity(value: AdBlockDailyProtectionActivity): AdBlockDailyProtectionActivity {
    return {
      dayStartedAt: value.dayStartedAt,
      networkBlockedCount: value.networkBlockedCount,
      urlParameterRemovedCount: value.urlParameterRemovedCount,
      cosmeticElementHiddenCount: value.cosmeticElementHiddenCount,
      manualElementHiddenCount: value.manualElementHiddenCount,
      totalProtectionActionCount: value.totalProtectionActionCount
    };
  }

  private cloneSiteException(value: AdBlockSiteException): AdBlockSiteException {
    return {
      profileId: value.profileId,
      host: value.host,
      includeSubdomains: value.includeSubdomains,
      createdAt: value.createdAt
    };
  }

  private cloneCustomRuleSource(value: AdBlockCustomRuleSource): AdBlockCustomRuleSource {
    return {
      id: value.id,
      payloadIdentity: value.payloadIdentity,
      title: value.title,
      url: value.url,
      sourceType: value.sourceType,
      enabled: value.enabled,
      nativeNetworkRuleCount: value.nativeNetworkRuleCount,
      nativeCosmeticRuleCount: value.nativeCosmeticRuleCount,
      ruleCount: value.ruleCount,
      lastUpdatedAt: value.lastUpdatedAt,
      lastError: value.lastError,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt
    };
  }

  private buildSourceId(url: string): string {
    let hash = 0;
    for (let index = 0; index < url.length; index += 1) {
      hash = ((hash * 31) + url.charCodeAt(index)) >>> 0;
    }
    return `custom-${hash}`;
  }

  private buildSourceTitle(url: string): string {
    const normalized = this.normalizeHost(url);
    return normalized.length > 0 ? normalized : '自定义规则';
  }

  private normalizeSourceType(value: string): AdBlockCustomRuleSourceType {
    if (value === 'system' || value === 'local') {
      return value;
    }
    return 'remote';
  }

  private limitCustomRuleSources(values: AdBlockCustomRuleSource[]): AdBlockCustomRuleSource[] {
    const protectedSources = values.filter((item: AdBlockCustomRuleSource) => {
      return item.sourceType === 'system' || isAdBlockThirdPartyRuleSourceId(item.id);
    });
    const customSources = values.filter((item: AdBlockCustomRuleSource) => {
      return item.sourceType !== 'system' && !isAdBlockThirdPartyRuleSourceId(item.id);
    });
    return protectedSources.concat(customSources.slice(Math.max(0, customSources.length - MAX_CUSTOM_RULE_SOURCES)));
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && value > 0 ? value : 0;
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }

}
