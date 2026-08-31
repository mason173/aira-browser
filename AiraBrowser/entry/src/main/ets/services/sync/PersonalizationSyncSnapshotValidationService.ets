import {
  PERSONALIZATION_SYNC_ITEM_IDS,
  PERSONALIZATION_SYNC_SCHEMA_VERSION,
  PersonalizationActivityHeatmapPayload,
  PersonalizationCorePreferencesPayload,
  PersonalizationHomeShortcutsPayload,
  PersonalizationSearchPayload,
  PersonalizationSyncItemId,
  PersonalizationSyncSection,
  PersonalizationSyncSnapshot
} from '../../common/models/PersonalizationSyncModels';

const MAX_ACTIVITY_DAYS_PER_SOURCE: number = 420;

export class PersonalizationSyncSnapshotValidationService {
  validate(snapshot: PersonalizationSyncSnapshot, sourceLabel: string): PersonalizationSyncSnapshot {
    if (snapshot === undefined || snapshot === null || typeof snapshot !== 'object' ||
      snapshot.meta === undefined || snapshot.meta === null ||
      snapshot.meta.version !== PERSONALIZATION_SYNC_SCHEMA_VERSION ||
      !this.isNonEmptyString(snapshot.meta.deviceId) ||
      !this.isNonEmptyString(snapshot.meta.generatedAt) ||
      snapshot.sections === undefined || snapshot.sections === null ||
      typeof snapshot.sections !== 'object' || Array.isArray(snapshot.sections)) {
      throw new Error(`${sourceLabel}个性化同步快照格式无效。`);
    }
    const sectionKeys = Object.keys(snapshot.sections).sort();
    const expectedKeys = PERSONALIZATION_SYNC_ITEM_IDS.slice().sort();
    if (!this.sameStringArray(sectionKeys, expectedKeys)) {
      throw new Error(`${sourceLabel}个性化同步快照内容不完整。`);
    }
    for (let index = 0; index < PERSONALIZATION_SYNC_ITEM_IDS.length; index += 1) {
      const id = PERSONALIZATION_SYNC_ITEM_IDS[index];
      const section = snapshot.sections[id];
      if (!this.isValidSection(id, section)) {
        throw new Error(`${sourceLabel}个性化同步快照中的 ${id} 无效。`);
      }
    }
    return snapshot;
  }

  canUseSectionAsEnabled(
    id: PersonalizationSyncItemId,
    section: PersonalizationSyncSection
  ): boolean {
    return this.isValidSection(id, {
      enabled: true,
      updatedAt: section.updatedAt,
      payload: section.payload
    });
  }

  private isValidSection(id: PersonalizationSyncItemId, section: PersonalizationSyncSection): boolean {
    if (section === undefined || section === null || typeof section !== 'object' ||
      typeof section.enabled !== 'boolean' || !this.isNonNegativeInteger(section.updatedAt) ||
      !this.isRecord(section.payload)) {
      return false;
    }
    if (!section.enabled) {
      return true;
    }
    if (id === 'home_shortcuts') {
      return this.isValidHomeShortcutsPayload(section.payload as PersonalizationHomeShortcutsPayload);
    }
    if (id === 'core_preferences') {
      return this.isValidCorePreferencesPayload(section.payload as PersonalizationCorePreferencesPayload);
    }
    if (id === 'activity_heatmap') {
      return this.isValidActivityHeatmapPayload(section.payload as PersonalizationActivityHeatmapPayload);
    }
    return this.isValidSearchPayload(section.payload as PersonalizationSearchPayload);
  }

  private isValidHomeShortcutsPayload(payload: PersonalizationHomeShortcutsPayload): boolean {
    if (!Array.isArray(payload.scenarios) || !Array.isArray(payload.shortcuts) || !Array.isArray(payload.orders) ||
      !this.hasValidUniqueObjects(payload.scenarios as Object[], 'id', (value: Object): boolean => {
        return this.isValidShortcutScenario(value);
      }) ||
      !this.hasValidUniqueObjects(payload.shortcuts as Object[], 'id', (value: Object): boolean => {
        return this.isValidShortcut(value);
      }) ||
      !this.hasValidUniqueObjects(payload.orders as Object[], 'scenarioId', (value: Object): boolean => {
        return this.isValidShortcutOrder(value);
      })) {
      return false;
    }
    return true;
  }

  private isValidShortcutScenario(value: Object): boolean {
    if (!this.isRecord(value)) return false;
    const record = value as Record<string, Object>;
    return this.isNonEmptyString(record.id as string) &&
      typeof record.name === 'string' && typeof record.color === 'string' && typeof record.icon === 'string' &&
      this.isNonNegativeInteger(record.position as number) && typeof record.archived === 'boolean' &&
      this.isNonNegativeInteger(record.createdAt as number) &&
      this.isNonNegativeInteger(record.updatedAt as number) && this.isValidSyncMetadata(record.sync);
  }

  private isValidShortcut(value: Object): boolean {
    if (!this.isRecord(value)) return false;
    const record = value as Record<string, Object>;
    return this.isNonEmptyString(record.id as string) && typeof record.title === 'string' &&
      typeof record.url === 'string' && typeof record.folderName === 'string' &&
      this.isNonNegativeInteger(record.position as number) && this.isValidSyncMetadata(record.sync) &&
      this.isOptionalNonEmptyString(record.scenarioId) && this.isOptionalAllowedString(record.kind, ['web', 'system']) &&
      this.isOptionalString(record.icon) && this.isOptionalString(record.description) &&
      this.isOptionalBoolean(record.useOfficialIcon) && this.isOptionalBoolean(record.autoUseOfficialIcon) &&
      this.isOptionalBoolean(record.officialIconAvailableAtSave) &&
      this.isOptionalBoolean(record.officialIconColorOverride) &&
      this.isOptionalString(record.iconRendering) && this.isOptionalString(record.iconColor) &&
      this.isOptionalNonNegativeInteger(record.createdAt) && this.isOptionalNonNegativeInteger(record.updatedAt);
  }

  private isValidShortcutOrder(value: Object): boolean {
    if (!this.isRecord(value)) return false;
    const record = value as Record<string, Object>;
    return this.isNonEmptyString(record.scenarioId as string) &&
      this.isUniqueStringArray(record.shortcutIds) && this.isNonNegativeInteger(record.updatedAt as number);
  }

  private isValidSyncMetadata(value: Object | undefined): boolean {
    if (!this.isRecord(value)) return false;
    const record = value as Record<string, Object>;
    return this.isAllowedString(record.state, ['local_only', 'pending_push', 'synced', 'conflict']) &&
      this.isAllowedString(record.source, ['seed', 'local', 'chrome_import', 'chrome_sync', 'cloud_sync']) &&
      this.isNonNegativeInteger(record.lastModifiedAt as number) &&
      this.isNonEmptyString(record.lastModifiedBy as string) &&
      this.isNonEmptyString(record.deviceId as string) && this.isOptionalString(record.originId) &&
      this.isOptionalNonNegativeInteger(record.deletedAt);
  }

  private isValidCorePreferencesPayload(payload: PersonalizationCorePreferencesPayload): boolean {
    if (!this.isRecord(payload) || !this.isAllowedString(payload.themeMode as Object, ['light', 'dark', 'system']) ||
      !this.isRecord(payload.appearance) || !this.isRecord(payload.general) || !this.isRecord(payload.toolbarLayout)) {
      return false;
    }
    const appearance = payload.appearance as Record<string, Object>;
    const booleanAppearanceFields = [
      'globalImmersionEnabled', 'alwaysTopImmersionEnabled',
      'forceDarkWebContentEnabled', 'blurPrivateTabPreviews', 'showHomeRecentlyClosed',
      'showHomeShortcuts', 'tabsOverviewCloseButtonAlwaysVisible'
    ];
    const optionalBooleanAppearanceFields = [
      'showHomeFavoritesTitle', 'showHomeShortcutNames', 'showHomeRecentlyClosedTitle',
      'showHomeSettingsButton', 'showHomeSystemSearch', 'hideHomeSystemSearchOnScroll'
    ];
    if (!this.hasBooleanFields(appearance, booleanAppearanceFields) ||
      !this.isOptionalAllowedString(
        appearance.bottomToolbarScrollBehavior,
        ['fixed', 'compact', 'hidden']
      ) ||
      !optionalBooleanAppearanceFields.every((field: string): boolean => {
        return this.isOptionalBoolean(appearance[field]);
      }) ||
      !this.isFiniteNumber(appearance.homeRecentlyClosedLimit) ||
      !this.isFiniteNumber(appearance.homeShortcutIconSizeRatio) ||
      !this.isFiniteNumber(appearance.siteIconCornerRadiusRatio) ||
      !this.isAllowedString(appearance.homeShortcutLayoutDensity, ['standard', 'compact']) ||
      !this.isAllowedString(appearance.themePaletteId, [
        'default', 'aira_classic', 'aira_origin', 'aurora', 'sage', 'cedar', 'lagoon', 'glacier',
        'indigo', 'wisteria', 'rosewood', 'terracotta', 'amber', 'moss', 'cyan', 'steel', 'plum', 'coral'
      ]) || !this.isAllowedString(appearance.tabsOverviewLayoutStyle, ['grid', 'horizontal_cards']) ||
      !this.isOptionalAllowedString(appearance.homeWallpaperMode, ['theme', 'bing', 'custom'])) {
      return false;
    }
    const general = payload.general as Record<string, Object>;
    if (!this.isAllowedString(general.startupRestorePolicy, ['restore_regular_tabs', 'open_home']) ||
      !this.isAllowedString(general.tabAutoClosePolicy, [
        'manual', 'after_15_days', 'after_7_days', 'after_3_days', 'after_1_day', 'on_app_exit'
      ]) || !this.isAllowedString(general.privateTabRestorePolicy, ['never_restore', 'restore_private_tabs']) ||
      typeof general.privateModeThemeEnabled !== 'boolean') {
      return false;
    }
    const toolbar = payload.toolbarLayout as Record<string, Object>;
    return this.isUniqueStringArray(toolbar.primaryActionIds) &&
      this.isUniqueStringArray(toolbar.secondaryActionIds) &&
      this.isNonNegativeInteger(toolbar.updatedAt as number);
  }

  private isValidActivityHeatmapPayload(payload: PersonalizationActivityHeatmapPayload): boolean {
    return Array.isArray(payload.contributions) &&
      this.hasValidUniqueObjects(payload.contributions as Object[], 'sourceId', (value: Object): boolean => {
        if (!this.isRecord(value)) return false;
        const record = value as Record<string, Object>;
        const items = record.items;
        return this.isNonEmptyString(record.sourceId as string) && Array.isArray(items) &&
          items.length <= MAX_ACTIVITY_DAYS_PER_SOURCE &&
          this.hasValidUniqueObjects(items as Object[], 'date', (item: Object): boolean => {
            return this.isValidActivityItem(item);
          }) && this.isNonNegativeInteger(record.updatedAt as number);
      });
  }

  private isValidActivityItem(value: Object): boolean {
    if (!this.isRecord(value)) return false;
    const record = value as Record<string, Object>;
    return typeof record.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(record.date) &&
      ['score', 'pageVisits', 'searches', 'bookmarkActions', 'downloads', 'featureActions', 'activeSeconds', 'updatedAt']
        .every((field: string): boolean => this.isNonNegativeInteger(record[field] as number));
  }

  private isValidSearchPayload(payload: PersonalizationSearchPayload): boolean {
    if (!this.isRecord(payload) || !this.isRecord(payload.settings) || !Array.isArray(payload.tombstones)) {
      return false;
    }
    const settings = payload.settings;
    if (!this.isNonEmptyString(settings.defaultSearchEngineId as string) ||
      !this.isUniqueStringArray(settings.builtInEngineOrder) ||
      !this.isUniqueStringArray(settings.enabledBuiltInEngineIds) ||
      !Array.isArray(settings.customEngines) ||
      !this.hasValidUniqueObjects(settings.customEngines as Object[], 'id', (value: Object): boolean => {
        return this.isValidSearchEngine(value);
      }) ||
      !this.isValidSearchSuggestionPreferences(settings.searchSuggestions as Object) ||
      !this.isValidSearchFallback(settings.fallbackSearch as Object) ||
      !this.isNonNegativeInteger(settings.updatedAt)) {
      return false;
    }
    return this.hasValidUniqueObjects(payload.tombstones as Object[], 'id', (value: Object): boolean => {
      if (!this.isRecord(value)) return false;
      const record = value as Record<string, Object>;
      return this.isNonEmptyString(record.id as string) &&
        this.isPositiveInteger(record.deletedAt as number);
    });
  }

  private isValidSearchEngine(value: Object): boolean {
    if (!this.isRecord(value)) return false;
    const record = value as Record<string, Object>;
    return this.isNonEmptyString(record.id as string) && record.kind === 'custom' &&
      this.isNonEmptyString(record.name as string) && this.isNonEmptyString(record.searchUrlTemplate as string) &&
      typeof record.homepageUrl === 'string' && typeof record.isEditable === 'boolean' &&
      this.isNonNegativeInteger(record.position as number) &&
      this.isNonNegativeInteger(record.createdAt as number) && this.isNonNegativeInteger(record.updatedAt as number) &&
      this.isOptionalString(record.iconUrl) && this.isOptionalString(record.availabilityProbeUrl) &&
      this.isOptionalNonNegativeInteger(record.availabilityExpectedStatus);
  }

  private isValidSearchSuggestionPreferences(value: Object | undefined): boolean {
    if (!this.isRecord(value)) return false;
    return this.hasBooleanFields(value as Record<string, Object>, [
      'regularEnabled', 'privateEnabled', 'openTabsEnabled', 'bookmarksEnabled',
      'shortcutsEnabled', 'historyEnabled', 'remoteEnabled'
    ]);
  }

  private isValidSearchFallback(value: Object | undefined): boolean {
    if (!this.isRecord(value)) return false;
    const record = value as Record<string, Object>;
    return typeof record.enabled === 'boolean' &&
      this.isNonEmptyString(record.fallbackSearchEngineId as string) && typeof record.noticeEnabled === 'boolean';
  }

  private hasValidUniqueObjects(
    values: Object[],
    field: string,
    isValid: (value: Object) => boolean
  ): boolean {
    const ids = new Set<string>();
    for (let index = 0; index < values.length; index += 1) {
      const value = values[index];
      if (!this.isRecord(value) || !isValid(value)) return false;
      const id = `${(value as Record<string, Object>)[field] ?? ''}`.trim();
      if (id.length <= 0 || ids.has(id)) return false;
      ids.add(id);
    }
    return true;
  }

  private hasBooleanFields(record: Record<string, Object>, fields: string[]): boolean {
    return fields.every((field: string): boolean => typeof record[field] === 'boolean');
  }

  private isUniqueStringArray(value: Object | undefined): boolean {
    if (!Array.isArray(value)) return false;
    const items = value as Object[];
    const values = new Set<string>();
    for (let index = 0; index < items.length; index += 1) {
      const item: Object = items[index];
      if (!this.isNonEmptyString(item as string) || values.has(item as string)) return false;
      values.add(item as string);
    }
    return true;
  }

  private isRecord(value: Object | undefined): boolean {
    return value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  private isAllowedString(value: Object | undefined, allowed: string[]): boolean {
    return typeof value === 'string' && allowed.indexOf(value) >= 0;
  }

  private isOptionalAllowedString(value: Object | undefined, allowed: string[]): boolean {
    return value === undefined || this.isAllowedString(value, allowed);
  }

  private isOptionalString(value: Object | undefined): boolean {
    return value === undefined || typeof value === 'string';
  }

  private isOptionalNonEmptyString(value: Object | undefined): boolean {
    return value === undefined || this.isNonEmptyString(value as string);
  }

  private isOptionalBoolean(value: Object | undefined): boolean {
    return value === undefined || typeof value === 'boolean';
  }

  private isOptionalNonNegativeInteger(value: Object | undefined): boolean {
    return value === undefined || this.isNonNegativeInteger(value as number);
  }

  private sameStringArray(left: string[], right: string[]): boolean {
    if (left.length !== right.length) return false;
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) return false;
    }
    return true;
  }

  private isNonEmptyString(value: string | undefined): boolean {
    return typeof value === 'string' && value.trim().length > 0;
  }

  private isFiniteNumber(value: Object | undefined): boolean {
    return typeof value === 'number' && Number.isFinite(value);
  }

  private isPositiveInteger(value: number): boolean {
    return this.isNonNegativeInteger(value) && value > 0;
  }

  private isNonNegativeInteger(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 && Math.floor(value) === value;
  }
}
