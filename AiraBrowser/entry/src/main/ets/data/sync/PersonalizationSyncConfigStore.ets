import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  createDefaultPersonalizationSyncConfig,
  PERSONALIZATION_SYNC_ITEM_IDS,
  PersonalizationSyncConfig,
  PersonalizationSyncDeletionState,
  PersonalizationSyncItemId,
  PersonalizationSyncItemSetting,
  PersonalizationSyncSectionState
} from '../../common/models/PersonalizationSyncModels';

const PREFERENCES_NAME: string = 'aira_personalization_sync_config_g2';
const SETTINGS_KEY: string = 'settings';

export class PersonalizationSyncConfigStore {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private config: PersonalizationSyncConfig = createDefaultPersonalizationSyncConfig();
  private initializationPromise?: Promise<PersonalizationSyncConfig>;
  private initialized: boolean = false;

  async initialize(): Promise<PersonalizationSyncConfig> {
    if (this.initialized) {
      return this.getConfig();
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.getStore()
        .then((store: preferences.Preferences) => {
          const storedValue = String(store.getSync(SETTINGS_KEY, ''));
          const parsedConfig = this.parseConfig(storedValue);
          this.config = this.normalizeConfig(parsedConfig);
          if (storedValue.trim().length === 0) {
            void this.persistConfig(this.config);
          }
          this.initialized = true;
          return this.getConfig();
        })
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw error;
        });
    }
    return this.initializationPromise;
  }

  getConfig(): PersonalizationSyncConfig {
    return this.cloneConfig(this.config);
  }

  async setItemEnabled(
    id: PersonalizationSyncItemId,
    enabled: boolean,
    updatedAt: number = Date.now()
  ): Promise<PersonalizationSyncConfig> {
    await this.initialize();
    const nextItems = this.config.items.map((item: PersonalizationSyncItemSetting): PersonalizationSyncItemSetting => {
      return {
        id: item.id,
        enabled: item.id === id ? enabled : item.enabled,
        updatedAt: item.id === id ? this.normalizeTimestamp(updatedAt, Date.now()) : item.updatedAt
      };
    });
    return this.persistConfig({
      items: nextItems,
      sections: this.config.sections,
      deletions: this.config.deletions,
      lastSyncAt: this.config.lastSyncAt,
      updatedAt: Date.now()
    });
  }

  async saveSectionStates(
    sections: PersonalizationSyncSectionState[],
    syncedAt: number = Date.now(),
    deletions?: PersonalizationSyncDeletionState[]
  ): Promise<PersonalizationSyncConfig> {
    await this.initialize();
    const nextSections = this.normalizeSectionStates(sections);
    return this.persistConfig({
      items: this.config.items,
      sections: nextSections,
      deletions: this.normalizeDeletionStates(deletions ?? this.config.deletions),
      lastSyncAt: syncedAt,
      updatedAt: syncedAt
    });
  }

  async recordItemDeletion(
    sectionId: PersonalizationSyncItemId,
    itemId: string,
    deletedAt: number = Date.now()
  ): Promise<PersonalizationSyncConfig> {
    await this.initialize();
    const normalizedId = itemId.trim();
    if (normalizedId.length <= 0) {
      return this.getConfig();
    }
    const nextDeletedAt = this.normalizeTimestamp(deletedAt, Date.now());
    const nextDeletions = this.config.deletions.filter((value: PersonalizationSyncDeletionState): boolean => {
      return value.sectionId !== sectionId || value.id !== normalizedId;
    });
    nextDeletions.push({
      sectionId: sectionId,
      id: normalizedId,
      deletedAt: nextDeletedAt
    });
    return this.persistConfig({
      items: this.config.items,
      sections: this.config.sections,
      deletions: nextDeletions,
      lastSyncAt: this.config.lastSyncAt,
      updatedAt: Date.now()
    });
  }

  findSectionState(id: PersonalizationSyncItemId): PersonalizationSyncSectionState | undefined {
    return this.config.sections.find((section: PersonalizationSyncSectionState) => section.id === id);
  }

  private async persistConfig(config: PersonalizationSyncConfig): Promise<PersonalizationSyncConfig> {
    const nextConfig = this.normalizeConfig(config);
    const store = await this.getStore();
    store.putSync(SETTINGS_KEY, JSON.stringify(nextConfig));
    store.flushSync();
    this.config = nextConfig;
    this.initialized = true;
    return this.getConfig();
  }

  private parseConfig(value: string): PersonalizationSyncConfig | undefined {
    if (value.trim().length <= 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as PersonalizationSyncConfig;
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeConfig(value: PersonalizationSyncConfig | undefined): PersonalizationSyncConfig {
    const defaultConfig = createDefaultPersonalizationSyncConfig();
    const rawItems = Array.isArray(value?.items) ? value?.items ?? [] : [];
    const itemLookup: Record<string, boolean> = {};
    rawItems.forEach((item: PersonalizationSyncItemSetting) => {
      if (this.isValidItemId(item?.id)) {
        itemLookup[item.id as PersonalizationSyncItemId] = item.enabled !== false;
      }
    });
    const updatedAtLookup: Record<string, number> = {};
    rawItems.forEach((item: PersonalizationSyncItemSetting) => {
      if (this.isValidItemId(item?.id)) {
        updatedAtLookup[item.id as PersonalizationSyncItemId] = this.normalizeTimestamp(item.updatedAt, 0);
      }
    });
    return {
      items: PERSONALIZATION_SYNC_ITEM_IDS.map((id: PersonalizationSyncItemId): PersonalizationSyncItemSetting => {
        return {
          id: id,
          enabled: itemLookup[id] !== undefined ? itemLookup[id] : true,
          updatedAt: updatedAtLookup[id] !== undefined ? updatedAtLookup[id] : 0
        };
      }),
      sections: this.normalizeSectionStates(value?.sections ?? []),
      deletions: this.normalizeDeletionStates(value?.deletions ?? []),
      lastSyncAt: this.normalizeTimestamp(value?.lastSyncAt, defaultConfig.lastSyncAt),
      updatedAt: this.normalizeTimestamp(value?.updatedAt, defaultConfig.updatedAt)
    };
  }

  private normalizeSectionStates(values: PersonalizationSyncSectionState[]): PersonalizationSyncSectionState[] {
    const result: PersonalizationSyncSectionState[] = [];
    values.forEach((value: PersonalizationSyncSectionState) => {
      if (!this.isValidItemId(value?.id)) {
        return;
      }
      const id = value.id as PersonalizationSyncItemId;
      const checksum = `${value.checksum ?? ''}`.trim();
      result.push({
        id: id,
        enabled: this.normalizeSectionEnabled(value, checksum),
        updatedAt: this.normalizeTimestamp(value.updatedAt, 0),
        checksum: checksum
      });
    });
    return result;
  }

  private normalizeDeletionStates(values: PersonalizationSyncDeletionState[]): PersonalizationSyncDeletionState[] {
    const latestByKey: Record<string, PersonalizationSyncDeletionState> = {};
    values.forEach((value: PersonalizationSyncDeletionState) => {
      if (!this.isValidItemId(value?.sectionId)) {
        return;
      }
      const itemId = `${value?.id ?? ''}`.trim();
      const deletedAt = this.normalizeTimestamp(value?.deletedAt, 0);
      if (itemId.length <= 0 || deletedAt <= 0) {
        return;
      }
      const sectionId = value.sectionId as PersonalizationSyncItemId;
      const key = `${sectionId}|${itemId}`;
      const previous = latestByKey[key];
      if (previous === undefined || previous.deletedAt < deletedAt) {
        latestByKey[key] = {
          sectionId: sectionId,
          id: itemId,
          deletedAt: deletedAt
        };
      }
    });
    return Object.keys(latestByKey).sort().map((key: string): PersonalizationSyncDeletionState => latestByKey[key]);
  }

  private isValidItemId(id: string | undefined): boolean {
    return PERSONALIZATION_SYNC_ITEM_IDS.indexOf(id as PersonalizationSyncItemId) >= 0;
  }

  private normalizeSectionEnabled(value: PersonalizationSyncSectionState, checksum: string): boolean {
    if (typeof value.enabled === 'boolean') {
      return value.enabled;
    }
    return checksum !== '{}';
  }

  private normalizeTimestamp(value: number | undefined, fallback: number): number {
    const numberValue = Number(value ?? fallback);
    if (!Number.isFinite(numberValue) || numberValue < 0) {
      return fallback;
    }
    return Math.floor(numberValue);
  }

  private cloneConfig(config: PersonalizationSyncConfig): PersonalizationSyncConfig {
    return {
      items: config.items.map((item: PersonalizationSyncItemSetting): PersonalizationSyncItemSetting => {
        return {
          id: item.id,
          enabled: item.enabled,
          updatedAt: item.updatedAt
        };
      }),
      sections: config.sections.map((section: PersonalizationSyncSectionState): PersonalizationSyncSectionState => {
        return {
          id: section.id,
          enabled: section.enabled,
          updatedAt: section.updatedAt,
          checksum: section.checksum
        };
      }),
      deletions: config.deletions.map((value: PersonalizationSyncDeletionState): PersonalizationSyncDeletionState => {
        return {
          sectionId: value.sectionId,
          id: value.id,
          deletedAt: value.deletedAt
        };
      }),
      lastSyncAt: config.lastSyncAt,
      updatedAt: config.updatedAt
    };
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
