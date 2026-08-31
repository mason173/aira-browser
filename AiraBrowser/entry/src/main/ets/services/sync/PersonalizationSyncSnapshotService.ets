import {
  BrowserBottomToolbarScrollBehavior,
  BrowserHomeShortcutLayoutDensity,
  BrowserPrivateTabRestorePolicy,
  BrowserStartupRestorePolicy,
  BrowserTabAutoClosePolicy,
  BrowserThemeMode,
  BrowserThemePaletteId,
  BrowserTabsOverviewLayoutStyle,
  SearchEngineRecord,
  SearchEngineSettings,
  ShortcutRecord,
  ShortcutScenarioRecord
} from '../../common/models/BrowserModels';
import { WallpaperMode } from '../../common/models/WallpaperModels';
import {
  AiraActivityDailyAggregate,
  AiraActivityStoreState
} from '../../common/models/ActivityModels';
import {
  PERSONALIZATION_SYNC_ITEM_IDS,
  PERSONALIZATION_SYNC_SCHEMA_VERSION,
  PersonalizationActivityHeatmapPayload,
  PersonalizationCollectionPayload,
  PersonalizationCorePreferencesPayload,
  PersonalizationCoreToolbarLayoutPreferences,
  PersonalizationHomeShortcutOrder,
  PersonalizationHomeShortcutsPayload,
  PersonalizationSearchPayload,
  PersonalizationSyncConfig,
  PersonalizationSyncDeletionState,
  PersonalizationSyncItemId,
  PersonalizationSyncItemSetting,
  PersonalizationSyncItemTombstone,
  PersonalizationSyncSection,
  PersonalizationSyncSectionState,
  PersonalizationSyncSnapshot
} from '../../common/models/PersonalizationSyncModels';
import { ActivityRepository } from '../../data/activity/ActivityRepository';
import { CustomHomepageRepository } from '../../data/customhome/CustomHomepageRepository';
import { HomePagePresentationSettingsRepository } from '../../data/preferences/HomePagePresentationSettingsRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { ShortcutRepository } from '../../data/repositories/BrowserRepositories';
import { SearchEngineRepository } from '../../data/search/SearchEngineRepository';
import { WallpaperRepository } from '../../data/wallpaper/WallpaperRepository';
import { BUILT_IN_THEME_PALETTES } from '../../features/theme/BrowserThemePalettes';
import { ActivityContributionService } from '../activity/ActivityContributionService';
import { HomePageRecoveryEntryPolicyService } from '../settings/HomePageRecoveryEntryPolicyService';
import { HomeShortcutLogicService } from '../shortcuts/HomeShortcutLogicService';
import {
  PersonalizationSyncCollectionMergeIntent,
  PersonalizationSyncCollectionMergeService
} from './PersonalizationSyncCollectionMergeService';

export type PersonalizationSyncMergeIntent = PersonalizationSyncCollectionMergeIntent;

const LOCAL_BACKUP_ACTIVITY_SOURCE_ID: string = 'aira-local-backup-portable-totals';

export interface PersonalizationSyncSnapshotDependencies {
  preferencesRepository: PreferencesRepository;
  homePagePresentationSettingsRepository: HomePagePresentationSettingsRepository;
  customHomepageRepository: CustomHomepageRepository;
  wallpaperRepository: WallpaperRepository;
  shortcutRepository: ShortcutRepository;
  searchEngineRepository: SearchEngineRepository;
  activityRepository: ActivityRepository;
  canUseSmartSearchFallback?: () => boolean;
}

type PersonalizationSyncItemPrepareHandler = (accountUid: string) => Promise<void>;
type PersonalizationSyncItemBuildHandler = (deviceId: string, config: PersonalizationSyncConfig) => Object;
type PersonalizationSyncItemApplyHandler = (
  payload: Object,
  deviceId: string,
  accountUid: string
) => Promise<void>;
type PersonalizationSyncItemMergeHandler = (
  localSection: PersonalizationSyncSection,
  remoteSection: PersonalizationSyncSection,
  intent?: PersonalizationSyncMergeIntent
) => PersonalizationSyncSection;

interface PersonalizationSyncItemAdapter {
  id: PersonalizationSyncItemId;
  prepare: PersonalizationSyncItemPrepareHandler;
  build: PersonalizationSyncItemBuildHandler;
  apply: PersonalizationSyncItemApplyHandler;
  merge?: PersonalizationSyncItemMergeHandler;
}

export class PersonalizationSyncSnapshotService {
  private dependencies: PersonalizationSyncSnapshotDependencies;
  private itemAdapters: PersonalizationSyncItemAdapter[];
  private collectionMergeService: PersonalizationSyncCollectionMergeService =
    new PersonalizationSyncCollectionMergeService();
  private activityContributionService: ActivityContributionService = new ActivityContributionService();
  private homePageRecoveryEntryPolicyService: HomePageRecoveryEntryPolicyService =
    new HomePageRecoveryEntryPolicyService();
  private homeShortcutLogicService: HomeShortcutLogicService = new HomeShortcutLogicService();

  constructor(dependencies: PersonalizationSyncSnapshotDependencies) {
    this.dependencies = dependencies;
    this.itemAdapters = this.buildItemAdapters();
  }

  async buildLocalSnapshot(
    deviceId: string,
    config: PersonalizationSyncConfig,
    now: number = Date.now(),
    accountUid: string = ''
  ): Promise<PersonalizationSyncSnapshot> {
    if (config.lastSyncAt <= 0) {
      await this.dependencies.shortcutRepository.initialize();
      await this.dependencies.shortcutRepository.purgeDeletedSyncRecords();
    }
    const sections: Record<string, PersonalizationSyncSection> = {};
    for (let index = 0; index < PERSONALIZATION_SYNC_ITEM_IDS.length; index += 1) {
      const id = PERSONALIZATION_SYNC_ITEM_IDS[index];
      const item = this.findItemSetting(config, id);
      const previous = this.findPreviousSection(config, id);
      if (id === 'activity_heatmap') {
        await this.prepareActivityHistoryStateForSnapshot(
          config,
          item?.enabled !== false,
          accountUid,
          now
        );
      }
      if (item !== undefined && item.enabled === false) {
        const emptyPayload: Record<string, string> = {};
        const disabledSection: PersonalizationSyncSection = {
          enabled: false,
          updatedAt: this.normalizeTimestamp(previous?.updatedAt),
          payload: emptyPayload
        };
        sections[id] = disabledSection;
        continue;
      }
      const adapter = this.findItemAdapter(id);
      await adapter.prepare(accountUid);
      const payload = adapter.build(deviceId, config);
      const checksum = this.buildChecksum(payload);
      const updatedAt = previous !== undefined && previous.checksum === checksum
        ? previous.updatedAt
        : now;
      sections[id] = {
        enabled: true,
        updatedAt: updatedAt,
        payload: payload
      };
    }
    return {
      meta: {
        version: PERSONALIZATION_SYNC_SCHEMA_VERSION,
        deviceId: deviceId,
        generatedAt: new Date(now).toISOString()
      },
      sections: sections,
      checksum: this.buildChecksum(sections)
    };
  }

  buildLocalSectionStates(
    snapshot: PersonalizationSyncSnapshot,
    config: PersonalizationSyncConfig
  ): PersonalizationSyncSectionState[] {
    const result: PersonalizationSyncSectionState[] = [];
    PERSONALIZATION_SYNC_ITEM_IDS.forEach((id: PersonalizationSyncItemId) => {
      const item = this.findItemSetting(config, id);
      if (item?.enabled === false) {
        const previous = this.findPreviousSection(config, id);
        if (previous !== undefined) {
          result.push(previous);
        }
        return;
      }
      const section = snapshot.sections[id];
      if (section === undefined) {
        return;
      }
      result.push({
        id: id,
        enabled: section.enabled !== false,
        updatedAt: this.normalizeTimestamp(section.updatedAt),
        checksum: this.buildChecksum(section.payload)
      });
    });
    return result;
  }

  buildLocalDeletionStates(
    snapshot: PersonalizationSyncSnapshot,
    config: PersonalizationSyncConfig
  ): PersonalizationSyncDeletionState[] {
    const result: PersonalizationSyncDeletionState[] = [];
    config.deletions.forEach((value: PersonalizationSyncDeletionState): void => {
      const item = this.findItemSetting(config, value.sectionId);
      if (item?.enabled === false) {
        result.push(value);
      }
    });
    const append = (sectionId: PersonalizationSyncItemId, tombstones: PersonalizationSyncItemTombstone[]): void => {
      const item = this.findItemSetting(config, sectionId);
      if (item?.enabled === false) {
        return;
      }
      tombstones.forEach((value: PersonalizationSyncItemTombstone) => {
        const id = `${value?.id ?? ''}`.trim();
        const deletedAt = this.normalizeTimestamp(value?.deletedAt);
        if (id.length > 0 && deletedAt > 0) {
          result.push({
            sectionId: sectionId,
            id: id,
            deletedAt: deletedAt
          });
        }
      });
    };
    append('search', this.readTombstones(snapshot.sections.search?.payload));
    return result;
  }

  async applySection(
    id: PersonalizationSyncItemId,
    section: PersonalizationSyncSection,
    deviceId: string,
    accountUid: string
  ): Promise<void> {
    const adapter = this.findItemAdapter(id);
    await adapter.prepare(accountUid);
    await adapter.apply(section.payload, deviceId, accountUid);
  }

  mergeConcurrentSection(
    id: PersonalizationSyncItemId,
    localSection: PersonalizationSyncSection,
    remoteSection: PersonalizationSyncSection,
    intent: PersonalizationSyncMergeIntent = 'ordinary'
  ): PersonalizationSyncSection | undefined {
    const adapter = this.findItemAdapter(id);
    if (adapter.merge === undefined) {
      return undefined;
    }
    return adapter.merge(localSection, remoteSection, intent);
  }

  mergeLocalBackupSection(
    id: PersonalizationSyncItemId,
    localSection: PersonalizationSyncSection,
    backupSection: PersonalizationSyncSection
  ): PersonalizationSyncSection | undefined {
    if (id === 'search') {
      return this.mergeSearchSection(localSection, backupSection, 'provider-switch', true);
    }
    return this.mergeConcurrentSection(id, localSection, backupSection, 'provider-switch');
  }

  buildLocalBackupActivityHeatmapPayload(): PersonalizationActivityHeatmapPayload {
    const state = this.dependencies.activityRepository.getState();
    return this.activityContributionService.buildGenerationPayload(
      LOCAL_BACKUP_ACTIVITY_SOURCE_ID,
      [],
      state.totals,
      state.updatedAt
    );
  }

  async applyLocalBackupActivityHeatmapPayload(
    payload: PersonalizationActivityHeatmapPayload,
    accountUid: string
  ): Promise<void> {
    await this.dependencies.activityRepository.initialize();
    await this.dependencies.activityRepository.ensureAccountScope(accountUid);
    await this.dependencies.activityRepository.prepareG2VisibleHistorySeed(accountUid);
    const incomingTotals = this.activityContributionService.buildTotals(payload);
    await this.dependencies.activityRepository.updateActivityState(
      accountUid,
      (state: AiraActivityStoreState) => {
        const totals: AiraActivityDailyAggregate[] = this.activityContributionService.mergePortableTotals(
          state.totals,
          incomingTotals
        );
        const localBackupTotalsFloor: AiraActivityDailyAggregate[] =
          this.activityContributionService.mergePortableTotals(
            state.localBackupTotalsFloor,
            incomingTotals
          );
        return {
          totals: totals,
          localContributions: state.localContributions,
          localBackupTotalsFloor: localBackupTotalsFloor
        };
      },
      Date.now()
    );
  }

  mergePreferredCorePreferencesSection(
    preferredSection: PersonalizationSyncSection,
    alternateSection: PersonalizationSyncSection
  ): PersonalizationSyncSection {
    const preferredPayload = preferredSection.payload as PersonalizationCorePreferencesPayload;
    const alternatePayload = alternateSection.payload as PersonalizationCorePreferencesPayload;
    const preferredToolbar = preferredPayload.toolbarLayout;
    const alternateToolbar = alternatePayload.toolbarLayout;
    if (alternateToolbar === undefined || (preferredToolbar !== undefined &&
      this.normalizeTimestamp(alternateToolbar.updatedAt) <= this.normalizeTimestamp(preferredToolbar.updatedAt))) {
      return preferredSection;
    }
    const mergedToolbar: PersonalizationCoreToolbarLayoutPreferences = {
      primaryActionIds: alternateToolbar.primaryActionIds?.slice(),
      secondaryActionIds: alternateToolbar.secondaryActionIds?.slice(),
      updatedAt: alternateToolbar.updatedAt
    };
    const mergedPayload = this.cloneObject<PersonalizationCorePreferencesPayload>(preferredPayload);
    mergedPayload.toolbarLayout = mergedToolbar;
    return {
      enabled: preferredSection.enabled,
      updatedAt: Math.max(
        this.normalizeTimestamp(preferredSection.updatedAt),
        this.normalizeTimestamp(alternateSection.updatedAt)
      ),
      payload: mergedPayload
    };
  }

  buildCorePreferencesFingerprint(): string {
    return this.buildChecksum(this.buildCorePreferencesPayload());
  }

  sanitizeSectionForProvider(
    id: PersonalizationSyncItemId,
    section: PersonalizationSyncSection
  ): PersonalizationSyncSection {
    let payload: Object = this.cloneObject(section.payload);
    if (id === 'core_preferences') {
      payload = this.sanitizeCorePreferencesPayload(section.payload as PersonalizationCorePreferencesPayload);
    } else if (id === 'activity_heatmap') {
      payload = this.activityContributionService.sanitizePayload(
        section.payload as PersonalizationActivityHeatmapPayload
      );
    }
    return {
      enabled: section.enabled !== false,
      updatedAt: this.normalizeTimestamp(section.updatedAt),
      payload: payload
    };
  }

  areSectionContentsEqual(
    id: PersonalizationSyncItemId,
    left: PersonalizationSyncSection | undefined,
    right: PersonalizationSyncSection | undefined
  ): boolean {
    if (left === undefined || right === undefined) {
      return left === right;
    }
    const normalizedLeft = this.sanitizeSectionForProvider(id, left);
    const normalizedRight = this.sanitizeSectionForProvider(id, right);
    return normalizedLeft.enabled === normalizedRight.enabled &&
      this.arePayloadsEqual(normalizedLeft.payload, normalizedRight.payload);
  }

  areSectionPayloadsEqual(
    id: PersonalizationSyncItemId,
    left: PersonalizationSyncSection | undefined,
    right: PersonalizationSyncSection | undefined
  ): boolean {
    if (left === undefined || right === undefined) {
      return left === right;
    }
    const normalizedLeft = this.sanitizeSectionForProvider(id, left);
    const normalizedRight = this.sanitizeSectionForProvider(id, right);
    return this.arePayloadsEqual(normalizedLeft.payload, normalizedRight.payload);
  }

  areSnapshotContentsEqual(
    left: PersonalizationSyncSnapshot,
    right: PersonalizationSyncSnapshot
  ): boolean {
    for (let index = 0; index < PERSONALIZATION_SYNC_ITEM_IDS.length; index += 1) {
      const id = PERSONALIZATION_SYNC_ITEM_IDS[index];
      if (!this.areSectionContentsEqual(id, left.sections[id], right.sections[id])) {
        return false;
      }
    }
    return true;
  }

  areSnapshotSectionsExactlyEqual(
    left: PersonalizationSyncSnapshot,
    right: PersonalizationSyncSnapshot
  ): boolean {
    for (let index = 0; index < PERSONALIZATION_SYNC_ITEM_IDS.length; index += 1) {
      const id = PERSONALIZATION_SYNC_ITEM_IDS[index];
      const leftSection = left.sections[id];
      const rightSection = right.sections[id];
      if (!this.areSectionContentsEqual(id, leftSection, rightSection) || leftSection === undefined ||
        rightSection === undefined || this.normalizeTimestamp(leftSection.updatedAt) !==
        this.normalizeTimestamp(rightSection.updatedAt)) {
        return false;
      }
    }
    return true;
  }

  isSectionCanonicalForProvider(id: PersonalizationSyncItemId, section: PersonalizationSyncSection): boolean {
    return this.buildChecksum(section) === this.buildChecksum(this.sanitizeSectionForProvider(id, section));
  }

  private buildItemAdapters(): PersonalizationSyncItemAdapter[] {
    return [{
      id: 'home_shortcuts',
      prepare: async (_accountUid: string): Promise<void> => {
        await this.dependencies.shortcutRepository.initialize();
      },
      build: (deviceId: string, config: PersonalizationSyncConfig): Object => {
        return this.buildHomeShortcutsPayload(deviceId, config.lastSyncAt <= 0);
      },
      apply: async (payload: Object, _deviceId: string, _accountUid: string): Promise<void> => {
        await this.applyHomeShortcuts(payload as PersonalizationHomeShortcutsPayload);
      },
      merge: (
        localSection: PersonalizationSyncSection,
        remoteSection: PersonalizationSyncSection,
        intent: PersonalizationSyncMergeIntent = 'ordinary'
      ): PersonalizationSyncSection => this.mergeHomeShortcutsSection(localSection, remoteSection, intent)
    }, {
      id: 'core_preferences',
      prepare: async (_accountUid: string): Promise<void> => {
        await this.dependencies.preferencesRepository.initialize();
        await this.dependencies.homePagePresentationSettingsRepository.initialize();
        await this.dependencies.customHomepageRepository.initialize();
        await this.dependencies.wallpaperRepository.initialize();
      },
      build: (_deviceId: string, _config: PersonalizationSyncConfig): Object => this.buildCorePreferencesPayload(),
      apply: async (payload: Object, _deviceId: string, _accountUid: string): Promise<void> => {
        await this.applyCorePreferences(payload as PersonalizationCorePreferencesPayload);
      }
    }, {
      id: 'activity_heatmap',
      prepare: async (accountUid: string): Promise<void> => {
        await this.dependencies.activityRepository.initialize();
        await this.dependencies.activityRepository.ensureAccountScope(accountUid);
      },
      build: (deviceId: string, _config: PersonalizationSyncConfig): Object => {
        return this.buildActivityHeatmapPayload(deviceId);
      },
      apply: async (payload: Object, deviceId: string, accountUid: string): Promise<void> => {
        await this.applyActivityHeatmap(
          payload as PersonalizationActivityHeatmapPayload,
          deviceId,
          accountUid
        );
      },
      merge: (
        localSection: PersonalizationSyncSection,
        remoteSection: PersonalizationSyncSection
      ): PersonalizationSyncSection => this.mergeActivityHeatmapSection(localSection, remoteSection)
    }, {
      id: 'search',
      prepare: async (_accountUid: string): Promise<void> => {
        const preferences = await this.dependencies.preferencesRepository.initialize();
        await this.dependencies.searchEngineRepository.initialize(preferences.searchEngineId);
      },
      build: (_deviceId: string, config: PersonalizationSyncConfig): Object => this.buildSearchPayload(config),
      apply: async (payload: Object, _deviceId: string, _accountUid: string): Promise<void> => {
        await this.applySearch(payload as PersonalizationSearchPayload);
      },
      merge: (
        localSection: PersonalizationSyncSection,
        remoteSection: PersonalizationSyncSection,
        intent: PersonalizationSyncMergeIntent = 'ordinary'
      ): PersonalizationSyncSection => this.mergeSearchSection(localSection, remoteSection, intent)
    }];
  }

  private findItemAdapter(id: PersonalizationSyncItemId): PersonalizationSyncItemAdapter {
    const adapter = this.itemAdapters.find((value: PersonalizationSyncItemAdapter): boolean => value.id === id);
    if (adapter === undefined) {
      throw new Error(`Unsupported personalization sync item: ${id}`);
    }
    return adapter;
  }

  private buildHomeShortcutsPayload(
    deviceId: string,
    generationSeed: boolean
  ): PersonalizationHomeShortcutsPayload {
    const scenarios = this.dependencies.shortcutRepository.listSyncScenarios()
      .filter((scenario: ShortcutScenarioRecord): boolean => {
        return !generationSeed || scenario.sync.deletedAt === undefined;
      })
      .map((scenario: ShortcutScenarioRecord): ShortcutScenarioRecord => {
        return generationSeed ? this.buildFreshScenarioSeed(scenario, deviceId) : this.cloneObject(scenario);
      });
    const activeShortcuts = this.homeShortcutLogicService
      .projectUniqueActiveDestinations(this.dependencies.shortcutRepository.listAll())
      .map((shortcut: ShortcutRecord): ShortcutRecord => {
        return generationSeed ? this.buildFreshShortcutSeed(shortcut, deviceId) : this.cloneObject(shortcut);
      });
    const preparedShortcuts = this.dependencies.shortcutRepository.listSyncShortcuts()
      .filter((shortcut: ShortcutRecord): boolean => {
        return (!generationSeed || shortcut.sync?.deletedAt === undefined) &&
          this.shouldSyncHomeShortcut(shortcut);
      })
      .map((shortcut: ShortcutRecord): ShortcutRecord => {
        const prepared = generationSeed ?
          this.buildFreshShortcutSeed(shortcut, deviceId) : this.cloneObject(shortcut);
        return this.stripDeviceLocalIconFromShortcut(prepared);
      });
    const shortcuts = this.homeShortcutLogicService.convergeDuplicateDestinations(preparedShortcuts).shortcuts
      .sort((left: ShortcutRecord, right: ShortcutRecord): number => {
        return this.compareHomeShortcutRecordOrder(left, right);
      });
    return {
      scenarios: scenarios,
      shortcuts: shortcuts,
      orders: this.buildHomeShortcutOrders(scenarios, activeShortcuts)
    };
  }

  private buildFreshScenarioSeed(
    scenario: ShortcutScenarioRecord,
    deviceId: string
  ): ShortcutScenarioRecord {
    const next = this.cloneObject<ShortcutScenarioRecord>(scenario);
    next.sync = {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: Math.max(scenario.updatedAt, scenario.createdAt),
      lastModifiedBy: deviceId,
      deviceId: deviceId
    };
    return next;
  }

  private buildFreshShortcutSeed(shortcut: ShortcutRecord, deviceId: string): ShortcutRecord {
    const next = this.cloneObject<ShortcutRecord>(shortcut);
    next.sync = {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: Math.max(shortcut.updatedAt ?? 0, shortcut.createdAt ?? 0),
      lastModifiedBy: deviceId,
      deviceId: deviceId
    };
    return next;
  }

  private buildCorePreferencesPayload(): PersonalizationCorePreferencesPayload {
    const preferences = this.dependencies.preferencesRepository.getPreferences();
    const presentation = this.dependencies.homePagePresentationSettingsRepository.getSettings();
    const customHomepage = this.dependencies.customHomepageRepository.getSettings();
    const wallpaper = this.dependencies.wallpaperRepository.getSettings();
    const payload: PersonalizationCorePreferencesPayload = {
      themeMode: preferences.themeMode,
      appearance: {
        bottomToolbarScrollBehavior: preferences.appearance.bottomToolbarScrollBehavior,
        globalImmersionEnabled: preferences.appearance.globalImmersionEnabled,
        alwaysTopImmersionEnabled: preferences.appearance.alwaysTopImmersionEnabled,
        forceDarkWebContentEnabled: preferences.appearance.forceDarkWebContentEnabled,
        blurPrivateTabPreviews: preferences.appearance.blurPrivateTabPreviews,
        showHomeRecentlyClosed: preferences.appearance.showHomeRecentlyClosed,
        showHomeShortcuts: preferences.appearance.showHomeShortcuts,
        showHomeFavoritesTitle: presentation.showFavoritesTitle,
        showHomeShortcutNames: presentation.showShortcutNames,
        showHomeRecentlyClosedTitle: presentation.showRecentlyClosedTitle,
        showHomeSettingsButton: presentation.showSettingsButton,
        showHomeSystemSearch: customHomepage.systemHomepageShowSystemSearchBar,
        hideHomeSystemSearchOnScroll: customHomepage.hideToolbarOnScroll,
        homeWallpaperMode: wallpaper.mode,
        homeRecentlyClosedLimit: preferences.appearance.homeRecentlyClosedLimit,
        homeShortcutLayoutDensity: preferences.appearance.homeShortcutLayoutDensity,
        homeShortcutIconSizeRatio: preferences.appearance.homeShortcutIconSizeRatio,
        siteIconCornerRadiusRatio: preferences.appearance.siteIconCornerRadiusRatio,
        themePaletteId: preferences.appearance.themePaletteId,
        tabsOverviewLayoutStyle: preferences.appearance.tabsOverviewLayoutStyle,
        tabsOverviewCloseButtonAlwaysVisible: preferences.appearance.tabsOverviewCloseButtonAlwaysVisible
      },
      general: {
        startupRestorePolicy: preferences.general.startupRestorePolicy,
        tabAutoClosePolicy: preferences.general.tabAutoClosePolicy,
        privateTabRestorePolicy: preferences.general.privateTabRestorePolicy,
        privateModeThemeEnabled: preferences.general.privateModeThemeEnabled
      },
      toolbarLayout: {
        primaryActionIds: preferences.toolbarLayout.primaryActionIds.slice(),
        secondaryActionIds: preferences.toolbarLayout.secondaryActionIds.slice(),
        updatedAt: preferences.toolbarLayout.updatedAt
      }
    };
    return payload;
  }

  private sanitizeCorePreferencesPayload(
    payload: PersonalizationCorePreferencesPayload
  ): PersonalizationCorePreferencesPayload {
    const safePayload: PersonalizationCorePreferencesPayload = {};
    const themeMode = this.sanitizeThemeMode(payload?.themeMode);
    if (themeMode !== undefined) {
      safePayload.themeMode = themeMode;
    }
    if (payload?.appearance !== undefined) {
      safePayload.appearance = {
        bottomToolbarScrollBehavior:
          this.sanitizeBottomToolbarScrollBehavior(payload.appearance.bottomToolbarScrollBehavior),
        globalImmersionEnabled: this.sanitizeBoolean(payload.appearance.globalImmersionEnabled),
        alwaysTopImmersionEnabled: this.sanitizeBoolean(payload.appearance.alwaysTopImmersionEnabled),
        forceDarkWebContentEnabled: this.sanitizeBoolean(payload.appearance.forceDarkWebContentEnabled),
        blurPrivateTabPreviews: this.sanitizeBoolean(payload.appearance.blurPrivateTabPreviews),
        showHomeRecentlyClosed: this.sanitizeBoolean(payload.appearance.showHomeRecentlyClosed),
        showHomeShortcuts: this.sanitizeBoolean(payload.appearance.showHomeShortcuts),
        showHomeFavoritesTitle: this.sanitizeBoolean(payload.appearance.showHomeFavoritesTitle),
        showHomeShortcutNames: this.sanitizeBoolean(payload.appearance.showHomeShortcutNames),
        showHomeRecentlyClosedTitle: this.sanitizeBoolean(payload.appearance.showHomeRecentlyClosedTitle),
        showHomeSettingsButton: this.sanitizeBoolean(payload.appearance.showHomeSettingsButton),
        showHomeSystemSearch: this.sanitizeBoolean(payload.appearance.showHomeSystemSearch),
        hideHomeSystemSearchOnScroll: this.sanitizeBoolean(payload.appearance.hideHomeSystemSearchOnScroll),
        homeWallpaperMode: this.sanitizeWallpaperMode(payload.appearance.homeWallpaperMode),
        homeRecentlyClosedLimit: this.sanitizeFiniteNumber(payload.appearance.homeRecentlyClosedLimit),
        homeShortcutLayoutDensity:
          this.sanitizeHomeShortcutLayoutDensity(payload.appearance.homeShortcutLayoutDensity),
        homeShortcutIconSizeRatio: this.sanitizeFiniteNumber(payload.appearance.homeShortcutIconSizeRatio),
        siteIconCornerRadiusRatio: this.sanitizeFiniteNumber(payload.appearance.siteIconCornerRadiusRatio),
        themePaletteId: this.sanitizeThemePaletteId(payload.appearance.themePaletteId),
        tabsOverviewLayoutStyle: this.sanitizeTabsOverviewLayoutStyle(payload.appearance.tabsOverviewLayoutStyle),
        tabsOverviewCloseButtonAlwaysVisible:
          this.sanitizeBoolean(payload.appearance.tabsOverviewCloseButtonAlwaysVisible)
      };
    }
    if (payload?.general !== undefined) {
      safePayload.general = {
        startupRestorePolicy: this.sanitizeStartupRestorePolicy(payload.general.startupRestorePolicy),
        tabAutoClosePolicy: this.sanitizeTabAutoClosePolicy(payload.general.tabAutoClosePolicy),
        privateTabRestorePolicy: this.sanitizePrivateTabRestorePolicy(payload.general.privateTabRestorePolicy),
        privateModeThemeEnabled: this.sanitizeBoolean(payload.general.privateModeThemeEnabled)
      };
    }
    if (payload?.toolbarLayout !== undefined) {
      safePayload.toolbarLayout = {
        primaryActionIds: this.sanitizeStringArray(payload.toolbarLayout.primaryActionIds),
        secondaryActionIds: this.sanitizeStringArray(payload.toolbarLayout.secondaryActionIds),
        updatedAt: this.sanitizeNonNegativeInteger(payload.toolbarLayout.updatedAt)
      };
    }
    return safePayload;
  }

  private sanitizeBoolean(value: boolean | undefined): boolean | undefined {
    return typeof value === 'boolean' ? value : undefined;
  }

  private sanitizeBottomToolbarScrollBehavior(
    value: BrowserBottomToolbarScrollBehavior | undefined
  ): BrowserBottomToolbarScrollBehavior | undefined {
    return value === 'fixed' || value === 'compact' || value === 'hidden' ? value : undefined;
  }

  private sanitizeWallpaperMode(value: WallpaperMode | undefined): WallpaperMode | undefined {
    return value === 'theme' || value === 'bing' || value === 'custom' ? value : undefined;
  }

  private sanitizeFiniteNumber(value: number | undefined): number | undefined {
    return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
  }

  private sanitizeNonNegativeInteger(value: number | undefined): number | undefined {
    const numberValue = this.sanitizeFiniteNumber(value);
    return numberValue !== undefined && numberValue >= 0 ? Math.floor(numberValue) : undefined;
  }

  private sanitizeStringArray(value: string[] | undefined): string[] | undefined {
    if (!Array.isArray(value)) {
      return undefined;
    }
    return value
      .filter((item: string): boolean => typeof item === 'string')
      .map((item: string): string => item.trim())
      .filter((item: string): boolean => item.length > 0);
  }

  private sanitizeThemeMode(value: BrowserThemeMode | undefined): BrowserThemeMode | undefined {
    return value === 'light' || value === 'dark' || value === 'system' ? value : undefined;
  }

  private sanitizeThemePaletteId(value: BrowserThemePaletteId | undefined): BrowserThemePaletteId | undefined {
    return BUILT_IN_THEME_PALETTES.some((palette): boolean => palette.id === value) ? value : undefined;
  }

  private sanitizeTabsOverviewLayoutStyle(
    value: BrowserTabsOverviewLayoutStyle | undefined
  ): BrowserTabsOverviewLayoutStyle | undefined {
    return value === 'grid' || value === 'horizontal_cards' ? value : undefined;
  }

  private sanitizeHomeShortcutLayoutDensity(
    value: BrowserHomeShortcutLayoutDensity | undefined
  ): BrowserHomeShortcutLayoutDensity | undefined {
    return value === 'standard' || value === 'compact' ? value : undefined;
  }

  private sanitizeStartupRestorePolicy(
    value: BrowserStartupRestorePolicy | undefined
  ): BrowserStartupRestorePolicy | undefined {
    return value === 'restore_regular_tabs' || value === 'open_home' ? value : undefined;
  }

  private sanitizeTabAutoClosePolicy(
    value: BrowserTabAutoClosePolicy | undefined
  ): BrowserTabAutoClosePolicy | undefined {
    return value === 'manual' || value === 'after_15_days' || value === 'after_7_days' ||
      value === 'after_3_days' || value === 'after_1_day' || value === 'on_app_exit' ? value : undefined;
  }

  private sanitizePrivateTabRestorePolicy(
    value: BrowserPrivateTabRestorePolicy | undefined
  ): BrowserPrivateTabRestorePolicy | undefined {
    return value === 'never_restore' || value === 'restore_private_tabs' ? value : undefined;
  }

  private buildActivityHeatmapPayload(deviceId: string): PersonalizationActivityHeatmapPayload {
    const state = this.dependencies.activityRepository.getState();
    const sourceId = deviceId.trim().length > 0 ? deviceId.trim() : 'aira-personalization-device';
    return this.activityContributionService.buildGenerationPayload(
      sourceId,
      state.g2VisibleHistorySeed,
      state.localContributions,
      state.updatedAt
    );
  }

  private shouldPrepareVisibleActivityHistory(config: PersonalizationSyncConfig): boolean {
    const previous = this.findPreviousSection(config, 'activity_heatmap');
    return previous === undefined || previous.enabled === false;
  }

  private async prepareActivityHistoryStateForSnapshot(
    config: PersonalizationSyncConfig,
    enabled: boolean,
    accountUid: string,
    now: number
  ): Promise<void> {
    await this.dependencies.activityRepository.initialize();
    await this.dependencies.activityRepository.ensureAccountScope(accountUid);
    if (this.dependencies.activityRepository.getState().g2VisibleHistorySeedPrepared) {
      return;
    }
    const previous = this.findPreviousSection(config, 'activity_heatmap');
    if (enabled && this.shouldPrepareVisibleActivityHistory(config)) {
      await this.dependencies.activityRepository.prepareG2VisibleHistorySeed(accountUid, now);
      return;
    }
    if (previous?.enabled === true) {
      await this.dependencies.activityRepository.markG2VisibleHistorySeedPrepared(accountUid, now);
    }
  }

  private async applyActivityHeatmap(
    payload: PersonalizationActivityHeatmapPayload,
    deviceId: string,
    accountUid: string
  ): Promise<void> {
    const syncedTotals = this.activityContributionService.buildTotals(payload);
    const syncedLocalContributions = this.activityContributionService.findSourceItems(payload, deviceId);
    await this.dependencies.activityRepository.updateActivityState(
      accountUid,
      (state: AiraActivityStoreState) => {
        const syncedProjection = this.activityContributionService.reconcileSyncedTotals(
          syncedTotals,
          syncedLocalContributions,
          state.localContributions
        );
        return {
          totals: this.activityContributionService.mergePortableTotals(
            syncedProjection,
            state.localBackupTotalsFloor
          ),
          localContributions: state.localContributions
        };
      },
      Date.now()
    );
  }

  private mergeActivityHeatmapSection(
    localSection: PersonalizationSyncSection,
    remoteSection: PersonalizationSyncSection
  ): PersonalizationSyncSection {
    if (localSection.enabled === false) {
      return localSection;
    }
    const localPayload = localSection.payload as PersonalizationActivityHeatmapPayload;
    const remotePayload = remoteSection.payload as PersonalizationActivityHeatmapPayload;
    const payload = this.activityContributionService.mergePayloads(localPayload, remotePayload);
    const localUpdatedAt = this.normalizeTimestamp(localSection.updatedAt);
    const remoteUpdatedAt = this.normalizeTimestamp(remoteSection.updatedAt);
    const enabled = remoteSection.enabled !== false || localUpdatedAt > remoteUpdatedAt;
    const updatedAt = Math.max(localUpdatedAt, remoteUpdatedAt);
    const payloadJson = JSON.stringify(payload);
    if (enabled && updatedAt === localUpdatedAt &&
      payloadJson === JSON.stringify(localSection.payload)) {
      return localSection;
    }
    if (enabled === (remoteSection.enabled !== false) && updatedAt === remoteUpdatedAt &&
      payloadJson === JSON.stringify(remoteSection.payload)) {
      return remoteSection;
    }
    return {
      enabled: enabled,
      updatedAt: updatedAt,
      payload: payload
    };
  }

  private mergeHomeShortcutsSection(
    localSection: PersonalizationSyncSection,
    remoteSection: PersonalizationSyncSection,
    intent: PersonalizationSyncMergeIntent
  ): PersonalizationSyncSection {
    if (localSection.enabled === false || remoteSection.enabled === false) {
      return localSection;
    }
    const localPayload = localSection.payload as PersonalizationHomeShortcutsPayload;
    const remotePayload = remoteSection.payload as PersonalizationHomeShortcutsPayload;
    const mergedShortcuts = this.mergeHomeShortcutRecords(localPayload, remotePayload, intent);
    const mergedOrders = this.mergeHomeShortcutOrders(
      localPayload,
      remotePayload,
      mergedShortcuts
    );
    const payload: PersonalizationHomeShortcutsPayload = {
      scenarios: this.applyHomeShortcutOrderRevisions(
        this.mergeHomeShortcutScenarios(localPayload, remotePayload, intent),
        mergedOrders
      ),
      shortcuts: this.applyHomeShortcutOrders(mergedShortcuts, mergedOrders),
      orders: mergedOrders
    };
    const payloadJson = JSON.stringify(payload);
    if (payloadJson === JSON.stringify(remoteSection.payload)) {
      return remoteSection;
    }
    if (payloadJson === JSON.stringify(localSection.payload)) {
      return localSection;
    }
    return {
      enabled: true,
      updatedAt: Math.max(
        this.normalizeTimestamp(localSection.updatedAt),
        this.normalizeTimestamp(remoteSection.updatedAt)
      ),
      payload: payload
    };
  }

  private mergeHomeShortcutScenarios(
    localPayload: PersonalizationHomeShortcutsPayload,
    remotePayload: PersonalizationHomeShortcutsPayload,
    intent: PersonalizationSyncMergeIntent
  ): ShortcutScenarioRecord[] {
    const byId: Record<string, ShortcutScenarioRecord> = {};
    const append = (scenario: ShortcutScenarioRecord): void => {
      const id = String(scenario.id ?? '').trim();
      if (id.length <= 0) {
        return;
      }
      const existing = byId[id];
      if (intent === 'provider-switch' && existing !== undefined &&
        (existing.sync?.deletedAt === undefined) !== (scenario.sync?.deletedAt === undefined)) {
        byId[id] = existing.sync?.deletedAt === undefined ? existing : scenario;
        return;
      }
      if (existing === undefined || this.resolveScenarioModifiedAt(scenario) >=
        this.resolveScenarioModifiedAt(existing)) {
        byId[id] = scenario;
      }
    };
    (Array.isArray(localPayload?.scenarios) ? localPayload.scenarios : []).forEach(append);
    (Array.isArray(remotePayload?.scenarios) ? remotePayload.scenarios : []).forEach(append);
    return Object.keys(byId).map((id: string): ShortcutScenarioRecord => byId[id]);
  }

  private mergeHomeShortcutRecords(
    localPayload: PersonalizationHomeShortcutsPayload,
    remotePayload: PersonalizationHomeShortcutsPayload,
    intent: PersonalizationSyncMergeIntent
  ): ShortcutRecord[] {
    const byId: Record<string, ShortcutRecord> = {};
    const append = (shortcut: ShortcutRecord): void => {
      const sanitizedShortcut = this.stripDeviceLocalIconFromShortcut(shortcut);
      const id = String(sanitizedShortcut.id ?? '').trim();
      if (id.length <= 0) {
        return;
      }
      const existing = byId[id];
      if (intent === 'provider-switch' && existing !== undefined &&
        (existing.sync?.deletedAt === undefined) !== (sanitizedShortcut.sync?.deletedAt === undefined)) {
        byId[id] = existing.sync?.deletedAt === undefined ? existing : sanitizedShortcut;
        return;
      }
      if (existing === undefined || this.resolveShortcutModifiedAt(sanitizedShortcut) >=
        this.resolveShortcutModifiedAt(existing)) {
        byId[id] = sanitizedShortcut;
      }
    };
    (Array.isArray(localPayload?.shortcuts) ? localPayload.shortcuts : []).forEach(append);
    (Array.isArray(remotePayload?.shortcuts) ? remotePayload.shortcuts : []).forEach(append);
    const merged = Object.keys(byId).map((id: string): ShortcutRecord => byId[id]);
    return this.homeShortcutLogicService.convergeDuplicateDestinations(merged).shortcuts
      .sort((left: ShortcutRecord, right: ShortcutRecord): number => {
        return this.compareHomeShortcutRecordOrder(left, right);
      });
  }

  private buildHomeShortcutOrders(
    scenarios: ShortcutScenarioRecord[],
    shortcuts: ShortcutRecord[]
  ): PersonalizationHomeShortcutOrder[] {
    const scenarioIds: string[] = [];
    const appendScenarioId = (value: string | undefined): void => {
      const scenarioId = `${value ?? 'aira_default_scenario'}`.trim();
      if (scenarioId.length > 0 && scenarioIds.indexOf(scenarioId) < 0) {
        scenarioIds.push(scenarioId);
      }
    };
    scenarios.forEach((scenario: ShortcutScenarioRecord): void => {
      if (scenario.sync?.deletedAt === undefined) {
        appendScenarioId(scenario.id);
      }
    });
    shortcuts.forEach((shortcut: ShortcutRecord): void => appendScenarioId(shortcut.scenarioId));
    return scenarioIds.sort().map((scenarioId: string): PersonalizationHomeShortcutOrder => {
      const scenario = scenarios.find((item: ShortcutScenarioRecord) => item.id === scenarioId);
      const scenarioShortcuts = shortcuts
        .filter((shortcut: ShortcutRecord): boolean => {
          return shortcut.sync?.deletedAt === undefined &&
            (shortcut.scenarioId ?? 'aira_default_scenario') === scenarioId;
        })
        .sort((left: ShortcutRecord, right: ShortcutRecord): number => {
          const positionDelta = (left.position ?? 0) - (right.position ?? 0);
          return positionDelta !== 0 ? positionDelta : this.compareStableString(left.id, right.id);
        });
      let fullListModifiedAt = 0;
      if (scenarioShortcuts.length > 0) {
        fullListModifiedAt = scenarioShortcuts.reduce((earliest: number, shortcut: ShortcutRecord): number => {
          return Math.min(earliest, this.resolveShortcutModifiedAt(shortcut));
        }, this.resolveShortcutModifiedAt(scenarioShortcuts[0]));
      }
      return {
        scenarioId: scenarioId,
        shortcutIds: scenarioShortcuts.map((shortcut: ShortcutRecord): string => shortcut.id),
        updatedAt: Math.max(
          scenario === undefined ? 0 : this.resolveScenarioModifiedAt(scenario),
          fullListModifiedAt
        )
      };
    });
  }

  private mergeHomeShortcutOrders(
    localPayload: PersonalizationHomeShortcutsPayload,
    remotePayload: PersonalizationHomeShortcutsPayload,
    mergedShortcuts: ShortcutRecord[]
  ): PersonalizationHomeShortcutOrder[] {
    const localOrders = this.readHomeShortcutOrders(localPayload);
    const remoteOrders = this.readHomeShortcutOrders(remotePayload);
    const scenarioIds: string[] = [];
    const appendScenarioId = (scenarioId: string): void => {
      if (scenarioId.length > 0 && scenarioIds.indexOf(scenarioId) < 0) {
        scenarioIds.push(scenarioId);
      }
    };
    localOrders.forEach((order: PersonalizationHomeShortcutOrder): void => appendScenarioId(order.scenarioId));
    remoteOrders.forEach((order: PersonalizationHomeShortcutOrder): void => appendScenarioId(order.scenarioId));
    mergedShortcuts.forEach((shortcut: ShortcutRecord): void => {
      appendScenarioId(shortcut.scenarioId ?? 'aira_default_scenario');
    });
    const deletedIds = new Set<string>();
    mergedShortcuts.forEach((shortcut: ShortcutRecord): void => {
      if (shortcut.sync?.deletedAt !== undefined) {
        deletedIds.add(shortcut.id);
      }
    });
    return scenarioIds.sort().map((scenarioId: string): PersonalizationHomeShortcutOrder => {
      const localOrder = localOrders.find((order: PersonalizationHomeShortcutOrder) => {
        return order.scenarioId === scenarioId;
      });
      const remoteOrder = remoteOrders.find((order: PersonalizationHomeShortcutOrder) => {
        return order.scenarioId === scenarioId;
      });
      const winner = this.selectHomeShortcutOrder(localOrder, remoteOrder);
      const loser = winner === localOrder ? remoteOrder : localOrder;
      const shortcutIds: string[] = [];
      const appendId = (id: string): void => {
        if (id.length > 0 && !deletedIds.has(id) && shortcutIds.indexOf(id) < 0) {
          shortcutIds.push(id);
        }
      };
      (winner?.shortcutIds ?? []).forEach(appendId);
      (loser?.shortcutIds ?? []).forEach(appendId);
      mergedShortcuts
        .filter((shortcut: ShortcutRecord): boolean => {
          return shortcut.sync?.deletedAt === undefined &&
            (shortcut.scenarioId ?? 'aira_default_scenario') === scenarioId;
        })
        .sort((left: ShortcutRecord, right: ShortcutRecord): number => {
          const positionDelta = (left.position ?? 0) - (right.position ?? 0);
          return positionDelta !== 0 ? positionDelta : this.compareStableString(left.id, right.id);
        })
        .forEach((shortcut: ShortcutRecord): void => appendId(shortcut.id));
      return {
        scenarioId: scenarioId,
        shortcutIds: shortcutIds,
        updatedAt: Math.max(localOrder?.updatedAt ?? 0, remoteOrder?.updatedAt ?? 0)
      };
    });
  }

  private readHomeShortcutOrders(payload: PersonalizationHomeShortcutsPayload): PersonalizationHomeShortcutOrder[] {
    const orders = Array.isArray(payload?.orders) ? payload.orders : [];
    return orders
      .map((order: PersonalizationHomeShortcutOrder): PersonalizationHomeShortcutOrder => {
        const shortcutIds: string[] = [];
        (Array.isArray(order?.shortcutIds) ? order.shortcutIds : []).forEach((value: string): void => {
          const id = `${value ?? ''}`.trim();
          if (id.length > 0 && shortcutIds.indexOf(id) < 0) {
            shortcutIds.push(id);
          }
        });
        return {
          scenarioId: `${order?.scenarioId ?? ''}`.trim(),
          shortcutIds: shortcutIds,
          updatedAt: this.normalizeTimestamp(order?.updatedAt)
        };
      })
      .filter((order: PersonalizationHomeShortcutOrder): boolean => order.scenarioId.length > 0);
  }

  private selectHomeShortcutOrder(
    localOrder: PersonalizationHomeShortcutOrder | undefined,
    remoteOrder: PersonalizationHomeShortcutOrder | undefined
  ): PersonalizationHomeShortcutOrder | undefined {
    if (localOrder === undefined) {
      return remoteOrder;
    }
    if (remoteOrder === undefined) {
      return localOrder;
    }
    if (localOrder.updatedAt !== remoteOrder.updatedAt) {
      return localOrder.updatedAt > remoteOrder.updatedAt ? localOrder : remoteOrder;
    }
    const localFingerprint = JSON.stringify(localOrder.shortcutIds);
    const remoteFingerprint = JSON.stringify(remoteOrder.shortcutIds);
    return localFingerprint >= remoteFingerprint ? localOrder : remoteOrder;
  }

  private applyHomeShortcutOrders(
    shortcuts: ShortcutRecord[],
    orders: PersonalizationHomeShortcutOrder[]
  ): ShortcutRecord[] {
    const orderByScenario: Record<string, PersonalizationHomeShortcutOrder> = {};
    orders.forEach((order: PersonalizationHomeShortcutOrder): void => {
      orderByScenario[order.scenarioId] = order;
    });
    const appendPositionByScenario: Record<string, number> = {};
    return shortcuts.map((shortcut: ShortcutRecord): ShortcutRecord => {
      if (shortcut.sync?.deletedAt !== undefined) {
        return shortcut;
      }
      const scenarioId = shortcut.scenarioId ?? 'aira_default_scenario';
      const order = orderByScenario[scenarioId];
      if (order === undefined) {
        return shortcut;
      }
      const orderedPosition = order.shortcutIds.indexOf(shortcut.id);
      let position = orderedPosition;
      if (orderedPosition < 0) {
        const nextPosition = appendPositionByScenario[scenarioId] ?? order.shortcutIds.length;
        position = nextPosition;
        appendPositionByScenario[scenarioId] = nextPosition + 1;
      }
      const next = this.cloneObject<ShortcutRecord>(shortcut);
      next.position = position;
      return next;
    }).sort((left: ShortcutRecord, right: ShortcutRecord): number => {
      return this.compareHomeShortcutRecordOrder(left, right);
    });
  }

  private compareHomeShortcutRecordOrder(left: ShortcutRecord, right: ShortcutRecord): number {
    const leftScenarioId = left.scenarioId ?? 'aira_default_scenario';
    const rightScenarioId = right.scenarioId ?? 'aira_default_scenario';
    const scenarioDelta = this.compareStableString(leftScenarioId, rightScenarioId);
    if (scenarioDelta !== 0) {
      return scenarioDelta;
    }
    const positionDelta = (left.position ?? 0) - (right.position ?? 0);
    return positionDelta !== 0 ? positionDelta : this.compareStableString(left.id, right.id);
  }

  private applyHomeShortcutOrderRevisions(
    scenarios: ShortcutScenarioRecord[],
    orders: PersonalizationHomeShortcutOrder[]
  ): ShortcutScenarioRecord[] {
    return scenarios.map((scenario: ShortcutScenarioRecord): ShortcutScenarioRecord => {
      const order = orders.find((item: PersonalizationHomeShortcutOrder) => item.scenarioId === scenario.id);
      if (order === undefined) {
        return scenario;
      }
      const revision = Math.max(
        this.resolveScenarioModifiedAt(scenario),
        this.normalizeTimestamp(order.updatedAt)
      );
      const next = this.cloneObject<ShortcutScenarioRecord>(scenario);
      next.updatedAt = Math.max(next.updatedAt, revision);
      next.sync.lastModifiedAt = Math.max(next.sync.lastModifiedAt, revision);
      return next;
    }).sort((left: ShortcutScenarioRecord, right: ShortcutScenarioRecord): number => {
      const positionDelta = left.position - right.position;
      return positionDelta !== 0 ? positionDelta : this.compareStableString(left.id, right.id);
    });
  }

  private resolveShortcutModifiedAt(shortcut: ShortcutRecord): number {
    return Math.max(
      this.normalizeTimestamp(shortcut.sync?.deletedAt),
      this.normalizeTimestamp(shortcut.sync?.lastModifiedAt),
      this.normalizeTimestamp(shortcut.updatedAt),
      this.normalizeTimestamp(shortcut.createdAt)
    );
  }

  private resolveScenarioModifiedAt(scenario: ShortcutScenarioRecord): number {
    return Math.max(
      this.normalizeTimestamp(scenario.sync?.deletedAt),
      this.normalizeTimestamp(scenario.sync?.lastModifiedAt),
      this.normalizeTimestamp(scenario.updatedAt),
      this.normalizeTimestamp(scenario.createdAt)
    );
  }

  private mergeSearchSection(
    localSection: PersonalizationSyncSection,
    remoteSection: PersonalizationSyncSection,
    intent: PersonalizationSyncMergeIntent,
    preferRemoteScalarSettings: boolean = false
  ): PersonalizationSyncSection {
    if (localSection.enabled === false || remoteSection.enabled === false) {
      return localSection;
    }
    const localPayload = localSection.payload as PersonalizationSearchPayload;
    const remotePayload = remoteSection.payload as PersonalizationSearchPayload;
    const baseSettings = preferRemoteScalarSettings || this.useRemoteScalarSettings(localSection, remoteSection)
      ? remotePayload.settings
      : localPayload.settings;
    const merged = this.collectionMergeService.merge<SearchEngineRecord>(
      localPayload.settings?.customEngines ?? [],
      remotePayload.settings?.customEngines ?? [],
      this.readTombstones(localPayload),
      this.readTombstones(remotePayload),
      (item: SearchEngineRecord): string => item.id,
      (item: SearchEngineRecord): number => item.updatedAt,
      intent
    );
    const payload: PersonalizationSearchPayload = {
      settings: {
        defaultSearchEngineId: baseSettings.defaultSearchEngineId,
        builtInEngineOrder: baseSettings.builtInEngineOrder.slice(),
        enabledBuiltInEngineIds: baseSettings.enabledBuiltInEngineIds.slice(),
        customEngines: merged.items,
        searchSuggestions: this.cloneObject(baseSettings.searchSuggestions),
        fallbackSearch: this.cloneObject(baseSettings.fallbackSearch),
        updatedAt: Math.max(localPayload.settings?.updatedAt ?? 0, remotePayload.settings?.updatedAt ?? 0)
      },
      tombstones: merged.tombstones
    };
    return this.buildMergedCollectionSection(localSection, remoteSection, payload);
  }

  private buildMergedCollectionSection(
    localSection: PersonalizationSyncSection,
    remoteSection: PersonalizationSyncSection,
    payload: Object
  ): PersonalizationSyncSection {
    const payloadJson = JSON.stringify(payload);
    if (payloadJson === JSON.stringify(localSection.payload)) {
      return localSection;
    }
    if (payloadJson === JSON.stringify(remoteSection.payload)) {
      return remoteSection;
    }
    return {
      enabled: true,
      updatedAt: Math.max(
        this.normalizeTimestamp(localSection.updatedAt),
        this.normalizeTimestamp(remoteSection.updatedAt)
      ),
      payload: payload
    };
  }

  private useRemoteScalarSettings(
    localSection: PersonalizationSyncSection,
    remoteSection: PersonalizationSyncSection
  ): boolean {
    return this.normalizeTimestamp(remoteSection.updatedAt) > this.normalizeTimestamp(localSection.updatedAt);
  }

  private readConfigTombstones(
    config: PersonalizationSyncConfig,
    sectionId: PersonalizationSyncItemId
  ): PersonalizationSyncItemTombstone[] {
    return (config.deletions ?? [])
      .filter((value: PersonalizationSyncDeletionState): boolean => value.sectionId === sectionId)
      .map((value: PersonalizationSyncDeletionState): PersonalizationSyncItemTombstone => {
        return {
          id: value.id,
          deletedAt: value.deletedAt
        };
      });
  }

  private readTombstones(payload: Object | undefined): PersonalizationSyncItemTombstone[] {
    if (payload === undefined || payload === null) {
      return [];
    }
    const value = payload as PersonalizationCollectionPayload;
    if (!Array.isArray(value.tombstones)) {
      return [];
    }
    return value.tombstones
      .map((item: PersonalizationSyncItemTombstone): PersonalizationSyncItemTombstone => {
        return {
          id: `${item?.id ?? ''}`.trim(),
          deletedAt: this.normalizeTimestamp(item?.deletedAt)
        };
      })
      .filter((item: PersonalizationSyncItemTombstone): boolean => item.id.length > 0 && item.deletedAt > 0);
  }

  private buildSearchPayload(config: PersonalizationSyncConfig): PersonalizationSearchPayload {
    return {
      settings: this.sanitizeSearchSettings(
        this.cloneObject<SearchEngineSettings>(this.dependencies.searchEngineRepository.getSettings())
      ),
      tombstones: this.readConfigTombstones(config, 'search')
    };
  }

  private async applyHomeShortcuts(payload: PersonalizationHomeShortcutsPayload): Promise<void> {
    return this.dependencies.shortcutRepository.runExclusiveMutation(async (): Promise<void> => {
      await this.applyHomeShortcutsNow(payload);
    });
  }

  private async applyHomeShortcutsNow(payload: PersonalizationHomeShortcutsPayload): Promise<void> {
    const scenarios = Array.isArray(payload?.scenarios) ? payload.scenarios : [];
    const incomingShortcuts = this.homeShortcutLogicService.convergeDuplicateDestinations(
      Array.isArray(payload?.shortcuts) ? payload.shortcuts : []
    ).shortcuts;
    const orders = this.readHomeShortcutOrders(payload);
    const currentById: Record<string, ShortcutRecord> = {};
    this.dependencies.shortcutRepository.listSyncShortcuts().forEach((shortcut: ShortcutRecord): void => {
      currentById[shortcut.id] = shortcut;
    });
    const shortcuts = incomingShortcuts.map((shortcut: ShortcutRecord): ShortcutRecord => {
      return this.restoreLocalHomeShortcutIcon(shortcut, currentById[shortcut.id]);
    });
    const incomingIds = new Set<string>(shortcuts.map((shortcut: ShortcutRecord): string => shortcut.id));
    const records = shortcuts.slice();
    orders.forEach((order: PersonalizationHomeShortcutOrder): void => {
      order.shortcutIds.forEach((id: string): void => {
        const current = currentById[id];
        if (!incomingIds.has(id) && current !== undefined && current.sync?.deletedAt === undefined) {
          records.push(current);
          incomingIds.add(id);
        }
      });
    });
    const activeIncomingIdentities = new Set<string>();
    records.forEach((shortcut: ShortcutRecord): void => {
      if (shortcut.sync?.deletedAt !== undefined) {
        return;
      }
      const identity = this.homeShortcutLogicService.resolveShortcutDestinationIdentity(shortcut);
      if (identity.length > 0) {
        activeIncomingIdentities.add(identity);
      }
    });
    Object.keys(currentById).forEach((id: string): void => {
      const current = currentById[id];
      if (incomingIds.has(id) || current.sync?.deletedAt !== undefined) {
        return;
      }
      const identity = this.homeShortcutLogicService.resolveShortcutDestinationIdentity(current);
      if (identity.length > 0 && activeIncomingIdentities.has(identity)) {
        records.push(current);
        incomingIds.add(id);
      }
    });
    const convergedRecords = this.homeShortcutLogicService.convergeDuplicateDestinations(records).shortcuts;
    await this.dependencies.shortcutRepository.applySyncSnapshot(
      this.applyHomeShortcutOrderRevisions(scenarios, orders),
      this.applyHomeShortcutOrders(convergedRecords, orders)
    );
  }

  private async applyCorePreferences(payload: PersonalizationCorePreferencesPayload): Promise<void> {
    const preferences = this.dependencies.preferencesRepository.getPreferences();
    const currentAppearance = preferences.appearance;
    const incomingAppearance = payload.appearance;
    const nextShowFavorites = incomingAppearance?.showHomeShortcuts ?? currentAppearance.showHomeShortcuts;
    const nextShowRecentlyClosed =
      incomingAppearance?.showHomeRecentlyClosed ?? currentAppearance.showHomeRecentlyClosed;
    if (payload.themeMode !== undefined) {
      await this.dependencies.preferencesRepository.updateThemeMode(payload.themeMode, 'sync');
    }
    if (incomingAppearance !== undefined) {
      const current = currentAppearance;
      await this.dependencies.preferencesRepository.updateAppearanceSettings({
        bottomToolbarScrollBehavior:
          incomingAppearance.bottomToolbarScrollBehavior ?? current.bottomToolbarScrollBehavior,
        globalImmersionEnabled: incomingAppearance.globalImmersionEnabled ?? current.globalImmersionEnabled,
        alwaysTopImmersionEnabled: incomingAppearance.alwaysTopImmersionEnabled ?? current.alwaysTopImmersionEnabled,
        forceDarkWebContentEnabled: incomingAppearance.forceDarkWebContentEnabled ?? current.forceDarkWebContentEnabled,
        blurPrivateTabPreviews: incomingAppearance.blurPrivateTabPreviews ?? current.blurPrivateTabPreviews,
        showHomeRecentlyClosed: nextShowRecentlyClosed,
        showHomeShortcuts: nextShowFavorites,
        homeRecentlyClosedLimit: incomingAppearance.homeRecentlyClosedLimit ?? current.homeRecentlyClosedLimit,
        homeShortcutLayoutDensity:
          incomingAppearance.homeShortcutLayoutDensity ?? current.homeShortcutLayoutDensity,
        homeShortcutIconSizeRatio:
          incomingAppearance.homeShortcutIconSizeRatio ?? current.homeShortcutIconSizeRatio,
        siteIconCornerRadiusRatio:
          incomingAppearance.siteIconCornerRadiusRatio ?? current.siteIconCornerRadiusRatio,
        themePaletteId: incomingAppearance.themePaletteId ?? current.themePaletteId,
        tabsOverviewLayoutStyle:
          incomingAppearance.tabsOverviewLayoutStyle ?? current.tabsOverviewLayoutStyle,
        tabsOverviewCloseButtonAlwaysVisible:
          incomingAppearance.tabsOverviewCloseButtonAlwaysVisible ?? current.tabsOverviewCloseButtonAlwaysVisible,
        // Desktop chrome is device-local and must never be overwritten by a synced snapshot.
        showDesktopBookmarkBar: current.showDesktopBookmarkBar
      }, 'sync');
    }
    const presentation = this.dependencies.homePagePresentationSettingsRepository.getSettings();
    const requestedShowSettingsButton =
      incomingAppearance?.showHomeSettingsButton ?? presentation.showSettingsButton;
    const nextShowSettingsButton = this.homePageRecoveryEntryPolicyService.resolveSettingsButtonVisibility({
      showFavorites: nextShowFavorites,
      showRecentlyClosed: nextShowRecentlyClosed,
      showSettingsButton: requestedShowSettingsButton
    });
    const repairedRecoveryEntry = nextShowSettingsButton !== requestedShowSettingsButton;
    if (incomingAppearance?.showHomeFavoritesTitle !== undefined ||
      incomingAppearance?.showHomeShortcutNames !== undefined ||
      incomingAppearance?.showHomeRecentlyClosedTitle !== undefined ||
      incomingAppearance?.showHomeSettingsButton !== undefined ||
      nextShowSettingsButton !== presentation.showSettingsButton) {
      presentation.showFavoritesTitle =
        incomingAppearance?.showHomeFavoritesTitle ?? presentation.showFavoritesTitle;
      presentation.showShortcutNames = incomingAppearance?.showHomeShortcutNames ?? presentation.showShortcutNames;
      presentation.showRecentlyClosedTitle =
        incomingAppearance?.showHomeRecentlyClosedTitle ?? presentation.showRecentlyClosedTitle;
      presentation.showSettingsButton = nextShowSettingsButton;
      await this.dependencies.homePagePresentationSettingsRepository.updateSettings(
        presentation,
        repairedRecoveryEntry ? 'local' : 'sync'
      );
    }
    if (incomingAppearance?.showHomeSystemSearch !== undefined ||
      incomingAppearance?.hideHomeSystemSearchOnScroll !== undefined) {
      const customHomepage = this.dependencies.customHomepageRepository.getSettings();
      customHomepage.systemHomepageShowSystemSearchBar =
        incomingAppearance.showHomeSystemSearch ?? customHomepage.systemHomepageShowSystemSearchBar;
      customHomepage.hideToolbarOnScroll =
        incomingAppearance.hideHomeSystemSearchOnScroll ?? customHomepage.hideToolbarOnScroll;
      await this.dependencies.customHomepageRepository.saveSettings(customHomepage, 'sync');
    }
    if (incomingAppearance?.homeWallpaperMode !== undefined) {
      await this.dependencies.wallpaperRepository.updateSettings({
        mode: incomingAppearance.homeWallpaperMode
      }, 'sync');
    }
    if (payload.general !== undefined) {
      const current = preferences.general;
      await this.dependencies.preferencesRepository.updateGeneralSettings({
        startupRestorePolicy: payload.general.startupRestorePolicy ?? current.startupRestorePolicy,
        tabAutoClosePolicy: payload.general.tabAutoClosePolicy ?? current.tabAutoClosePolicy,
        privateTabRestorePolicy: payload.general.privateTabRestorePolicy ?? current.privateTabRestorePolicy,
        privateModeAuthenticationEnabled: current.privateModeAuthenticationEnabled,
        privateModePreserveCookiesOnClose: current.privateModePreserveCookiesOnClose,
        privateModeThemeEnabled: payload.general.privateModeThemeEnabled ?? current.privateModeThemeEnabled
      }, 'sync');
    }
    if (payload.toolbarLayout !== undefined) {
      const current = preferences.toolbarLayout;
      await this.dependencies.preferencesRepository.updateToolbarLayoutSettings({
        primaryActionIds: payload.toolbarLayout.primaryActionIds?.slice() ?? current.primaryActionIds.slice(),
        secondaryActionIds: payload.toolbarLayout.secondaryActionIds?.slice() ?? current.secondaryActionIds.slice(),
        updatedAt: payload.toolbarLayout.updatedAt ?? current.updatedAt
      }, 'sync');
    }
  }

  private async applySearch(payload: PersonalizationSearchPayload): Promise<void> {
    if (payload?.settings === undefined) {
      return;
    }
    const current = this.dependencies.searchEngineRepository.getSettings();
    const incoming = this.sanitizeSearchSettings(payload.settings);
    const merged = this.collectionMergeService.merge<SearchEngineRecord>(
      current.customEngines,
      incoming.customEngines,
      [],
      this.readTombstones(payload),
      (item: SearchEngineRecord): string => item.id,
      (item: SearchEngineRecord): number => item.updatedAt
    );
    const safeSettings: SearchEngineSettings = {
      defaultSearchEngineId: incoming.defaultSearchEngineId,
      builtInEngineOrder: incoming.builtInEngineOrder.slice(),
      enabledBuiltInEngineIds: incoming.enabledBuiltInEngineIds.slice(),
      customEngines: merged.items,
      searchSuggestions: this.cloneObject(incoming.searchSuggestions),
      fallbackSearch: this.cloneObject(incoming.fallbackSearch),
      updatedAt: Math.max(current.updatedAt, incoming.updatedAt)
    };
    await this.dependencies.searchEngineRepository.replaceSettings(safeSettings);
    await this.dependencies.preferencesRepository.updateSearchEngine(safeSettings.defaultSearchEngineId);
    await this.dependencies.preferencesRepository.updateSearchSuggestionPreferences(safeSettings.searchSuggestions);
  }

  private sanitizeSearchSettings(settings: SearchEngineSettings): SearchEngineSettings {
    const safeSettings = this.cloneObject<SearchEngineSettings>(settings);
    if (this.dependencies.canUseSmartSearchFallback?.() !== false) {
      return safeSettings;
    }
    safeSettings.fallbackSearch.enabled = false;
    return safeSettings;
  }

  private shouldSyncHomeShortcut(shortcut: ShortcutRecord): boolean {
    const source = shortcut.sync?.source ?? '';
    if (source !== 'seed') {
      return true;
    }
    return shortcut.sync?.deletedAt !== undefined;
  }

  private stripDeviceLocalIconFromShortcut(shortcut: ShortcutRecord): ShortcutRecord {
    const sanitized = this.cloneObject<ShortcutRecord>(shortcut);
    if (this.isDeviceLocalIconPath(sanitized.icon)) {
      sanitized.icon = undefined;
    }
    return sanitized;
  }

  private restoreLocalHomeShortcutIcon(
    incoming: ShortcutRecord,
    current: ShortcutRecord | undefined
  ): ShortcutRecord {
    const sanitized = this.stripDeviceLocalIconFromShortcut(incoming);
    if (current === undefined || (sanitized.iconRendering ?? '') === 'letter' ||
      sanitized.url.trim() !== current.url.trim() || (sanitized.icon ?? '').trim().length > 0) {
      return sanitized;
    }
    const localIconPath = (current.icon ?? '').trim();
    if (!this.isDeviceLocalIconPath(localIconPath)) {
      return sanitized;
    }
    sanitized.icon = localIconPath;
    return sanitized;
  }

  private isDeviceLocalIconPath(value: string | undefined): boolean {
    const normalized = (value ?? '').trim();
    return normalized.startsWith('file://') || normalized.startsWith('/');
  }

  private findItemSetting(
    config: PersonalizationSyncConfig,
    id: PersonalizationSyncItemId
  ): PersonalizationSyncItemSetting | undefined {
    return config.items.find((value) => value.id === id);
  }

  private findPreviousSection(
    config: PersonalizationSyncConfig,
    id: PersonalizationSyncItemId
  ): PersonalizationSyncSectionState | undefined {
    return config.sections.find((section: PersonalizationSyncSectionState) => section.id === id);
  }

  private normalizeTimestamp(value: number | undefined): number {
    const numberValue = Number(value ?? 0);
    if (!Number.isFinite(numberValue) || numberValue < 0) {
      return 0;
    }
    return Math.floor(numberValue);
  }

  private compareStableString(left: string, right: string): number {
    if (left === right) {
      return 0;
    }
    return left < right ? -1 : 1;
  }

  private buildChecksum(value: Object): string {
    return JSON.stringify(value);
  }

  private arePayloadsEqual(left: Object, right: Object): boolean {
    return this.buildChecksum(left) === this.buildChecksum(right);
  }

  private cloneObject<T>(value: T): T {
    return JSON.parse(JSON.stringify(value)) as T;
  }
}
