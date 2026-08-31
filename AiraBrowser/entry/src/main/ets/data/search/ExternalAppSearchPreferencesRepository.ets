import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  ALL_EXTERNAL_APP_SEARCH_TARGET_IDS,
  ExternalAppSearchPreferences,
  ExternalAppSearchTargetId
} from '../../common/models/BrowserModels';
import { EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY } from '../../common/constants/SearchPreferenceKeys';

const PREFERENCES_NAME: string = 'aira_browser_external_app_search';
const SETTINGS_KEY: string = 'external_app_search_preferences';
const DEFAULT_DISABLED_RESET_VERSION_KEY: string = 'default_disabled_reset_version';
const DEFAULT_DISABLED_RESET_VERSION: number = 1;

export class ExternalAppSearchPreferencesRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settings: ExternalAppSearchPreferences = this.buildDefaultSettings();

  async initialize(): Promise<ExternalAppSearchPreferences> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(SETTINGS_KEY, ''));
    const parsedSettings = this.parseSettings(rawSettings);
    this.settings = this.normalizeSettings(parsedSettings);
    const storedResetVersion = Number(store.getSync(DEFAULT_DISABLED_RESET_VERSION_KEY, 0));
    const shouldResetEnabled = !Number.isFinite(storedResetVersion) ||
      storedResetVersion < DEFAULT_DISABLED_RESET_VERSION;
    if (shouldResetEnabled) {
      this.settings.enabled = false;
      this.settings.updatedAt = Date.now();
    }
    this.publishSettings();
    if (rawSettings.trim().length === 0 ||
      parsedSettings?.enabled === undefined ||
      parsedSettings?.selectedTargetIds === undefined ||
      parsedSettings?.targetOrder === undefined ||
      shouldResetEnabled) {
      store.putSync(SETTINGS_KEY, JSON.stringify(this.settings));
      if (shouldResetEnabled) {
        store.putSync(DEFAULT_DISABLED_RESET_VERSION_KEY, DEFAULT_DISABLED_RESET_VERSION);
      }
      store.flushSync();
    }
    return this.getSettings();
  }

  getSettings(): ExternalAppSearchPreferences {
    return this.copySettings(this.settings);
  }

  async setEnabled(enabled: boolean): Promise<ExternalAppSearchPreferences> {
    return this.persistSettings({
      enabled: enabled,
      selectedTargetIds: this.settings.selectedTargetIds.slice(),
      targetOrder: this.settings.targetOrder.slice(),
      updatedAt: Date.now()
    });
  }

  async setTargetEnabled(
    targetId: ExternalAppSearchTargetId,
    enabled: boolean
  ): Promise<ExternalAppSearchPreferences> {
    const normalizedTargetId = this.normalizeTargetId(targetId);
    if (normalizedTargetId === undefined) {
      return this.getSettings();
    }
    const nextTargetIds = this.settings.selectedTargetIds.filter((candidate: ExternalAppSearchTargetId) => {
      return candidate !== normalizedTargetId;
    });
    if (enabled) {
      nextTargetIds.push(normalizedTargetId);
    }
    return this.persistSettings({
      enabled: this.settings.enabled,
      selectedTargetIds: this.normalizeSelectedTargetIds(nextTargetIds),
      targetOrder: this.settings.targetOrder.slice(),
      updatedAt: Date.now()
    });
  }

  async setTargetOrder(
    targetOrder: ExternalAppSearchTargetId[]
  ): Promise<ExternalAppSearchPreferences> {
    return this.persistSettings({
      enabled: this.settings.enabled,
      selectedTargetIds: this.settings.selectedTargetIds.slice(),
      targetOrder: this.normalizeTargetOrder(targetOrder),
      updatedAt: Date.now()
    });
  }

  private async persistSettings(
    settings: ExternalAppSearchPreferences
  ): Promise<ExternalAppSearchPreferences> {
    this.settings = this.normalizeSettings(settings);
    const store = await this.getStore();
    store.putSync(SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    this.publishSettings();
    return this.getSettings();
  }

  private publishSettings(): void {
    const nextRevision = (AppStorage.get<number>(EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY, nextRevision);
  }

  private normalizeSettings(
    settings: ExternalAppSearchPreferences | undefined
  ): ExternalAppSearchPreferences {
    return {
      enabled: settings?.enabled === true,
      selectedTargetIds: settings?.selectedTargetIds === undefined
        ? ALL_EXTERNAL_APP_SEARCH_TARGET_IDS.slice()
        : this.normalizeSelectedTargetIds(settings.selectedTargetIds),
      targetOrder: this.normalizeTargetOrder(settings?.targetOrder),
      updatedAt: this.normalizeTimestamp(settings?.updatedAt)
    };
  }

  private normalizeSelectedTargetIds(
    targetIds: ExternalAppSearchTargetId[]
  ): ExternalAppSearchTargetId[] {
    const normalizedTargetIds: ExternalAppSearchTargetId[] = [];
    ALL_EXTERNAL_APP_SEARCH_TARGET_IDS.forEach((targetId: ExternalAppSearchTargetId) => {
      if (targetIds.indexOf(targetId) >= 0) {
        normalizedTargetIds.push(targetId);
      }
    });
    return normalizedTargetIds;
  }

  private normalizeTargetId(targetId: ExternalAppSearchTargetId): ExternalAppSearchTargetId | undefined {
    return ALL_EXTERNAL_APP_SEARCH_TARGET_IDS.indexOf(targetId) >= 0 ? targetId : undefined;
  }

  private normalizeTargetOrder(
    targetOrder: ExternalAppSearchTargetId[] | undefined
  ): ExternalAppSearchTargetId[] {
    const normalizedOrder: ExternalAppSearchTargetId[] = [];
    if (targetOrder !== undefined) {
      targetOrder.forEach((targetId: ExternalAppSearchTargetId) => {
        if (this.normalizeTargetId(targetId) !== undefined && normalizedOrder.indexOf(targetId) < 0) {
          normalizedOrder.push(targetId);
        }
      });
    }
    ALL_EXTERNAL_APP_SEARCH_TARGET_IDS.forEach((targetId: ExternalAppSearchTargetId) => {
      if (normalizedOrder.indexOf(targetId) < 0) {
        normalizedOrder.push(targetId);
      }
    });
    return normalizedOrder;
  }

  private parseSettings(value: string): ExternalAppSearchPreferences | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as ExternalAppSearchPreferences;
    } catch (_error) {
      return undefined;
    }
  }

  private buildDefaultSettings(): ExternalAppSearchPreferences {
    return {
      enabled: false,
      selectedTargetIds: ALL_EXTERNAL_APP_SEARCH_TARGET_IDS.slice(),
      targetOrder: ALL_EXTERNAL_APP_SEARCH_TARGET_IDS.slice(),
      updatedAt: 0
    };
  }

  private copySettings(settings: ExternalAppSearchPreferences): ExternalAppSearchPreferences {
    return {
      enabled: settings.enabled,
      selectedTargetIds: settings.selectedTargetIds.slice(),
      targetOrder: settings.targetOrder.slice(),
      updatedAt: settings.updatedAt
    };
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
