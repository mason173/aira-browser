import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BrowserCustomUserAgentRecord,
  BrowserUserAgentSettings
} from '../../common/models/BrowserModels';
import {
  BrowserUserAgentService,
  DEFAULT_BROWSER_USER_AGENT_SETTINGS,
  SYSTEM_DEFAULT_USER_AGENT_PRESET_ID
} from '../../services/web/BrowserUserAgentService';

const PREFERENCES_NAME: string = 'aira_browser_user_agent';
const USER_AGENT_SETTINGS_KEY: string = 'user_agent_settings';
const LEGACY_DESKTOP_SITE_RULES_KEY: string = 'desktop_site_rules';

export type BrowserUserAgentSettingsChangeHandler = (settings: BrowserUserAgentSettings) => void;

export interface BrowserUserAgentSettingsReader {
  getSettings(): BrowserUserAgentSettings;
}

export class BrowserUserAgentSettingsRepository implements BrowserUserAgentSettingsReader {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private service: BrowserUserAgentService = new BrowserUserAgentService();
  private settings: BrowserUserAgentSettings = DEFAULT_BROWSER_USER_AGENT_SETTINGS;
  private settingsChangeHandler?: BrowserUserAgentSettingsChangeHandler;

  setSettingsChangeHandler(handler: BrowserUserAgentSettingsChangeHandler): void {
    this.settingsChangeHandler = handler;
  }

  async initialize(): Promise<BrowserUserAgentSettings> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(USER_AGENT_SETTINGS_KEY, ''));
    this.settings = this.service.normalizeSettings(this.parseSettings(rawSettings));
    if (rawSettings.trim().length === 0) {
      await this.persistSettings(this.settings);
    }
    return this.getSettings();
  }

  getSettings(): BrowserUserAgentSettings {
    return {
      defaultMode: this.settings.defaultMode,
      selectedPresetId: this.settings.selectedPresetId,
      customUserAgent: this.settings.customUserAgent,
      selectedCustomUserAgentId: this.settings.selectedCustomUserAgentId,
      customUserAgents: this.settings.customUserAgents.map((record: BrowserCustomUserAgentRecord) =>
        this.copyCustomUserAgentRecord(record)
      ),
      updatedAt: this.settings.updatedAt
    };
  }

  async saveSettings(settings: BrowserUserAgentSettings): Promise<BrowserUserAgentSettings> {
    const nextSettings = this.service.normalizeSettings({
      defaultMode: settings.defaultMode,
      selectedPresetId: settings.selectedPresetId,
      customUserAgent: settings.customUserAgent,
      selectedCustomUserAgentId: settings.selectedCustomUserAgentId,
      customUserAgents: this.resolveCustomUserAgentsForSave(settings),
      updatedAt: settings.updatedAt
    });
    return this.persistSettings(nextSettings);
  }

  async upsertCustomUserAgent(
    name: string,
    userAgent: string,
    recordId: string = ''
  ): Promise<BrowserUserAgentSettings> {
    const existingRecord = this.settings.customUserAgents.find((record: BrowserCustomUserAgentRecord) => {
      return record.id === recordId.trim();
    });
    const record = this.service.buildCustomUserAgentRecord({
      name: name,
      userAgent: userAgent
    }, existingRecord);
    if (record === undefined) {
      return this.getSettings();
    }
    return this.persistSettings(this.service.buildSettingsForCustomRecord(record, this.settings));
  }

  async selectCustomUserAgent(recordId: string): Promise<BrowserUserAgentSettings> {
    const record = this.service.findCustomUserAgent(this.settings.customUserAgents, recordId);
    if (record === undefined) {
      return this.getSettings();
    }
    return this.persistSettings(this.service.buildSettingsForCustomRecord(record, this.settings));
  }

  async removeCustomUserAgent(recordId: string): Promise<BrowserUserAgentSettings> {
    const normalizedRecordId = recordId.trim();
    if (normalizedRecordId.length <= 0) {
      return this.getSettings();
    }
    const nextRecords = this.settings.customUserAgents.filter((record: BrowserCustomUserAgentRecord) => {
      return record.id !== normalizedRecordId;
    });
    if (nextRecords.length === this.settings.customUserAgents.length) {
      return this.getSettings();
    }
    const removingSelectedRecord = this.settings.selectedCustomUserAgentId === normalizedRecordId;
    const fallbackSettings = this.service.buildPresetSettings(SYSTEM_DEFAULT_USER_AGENT_PRESET_ID, this.settings);
    const nextSettings: BrowserUserAgentSettings = {
      defaultMode: removingSelectedRecord ? fallbackSettings.defaultMode : this.settings.defaultMode,
      selectedPresetId: removingSelectedRecord ? fallbackSettings.selectedPresetId : this.settings.selectedPresetId,
      customUserAgent: removingSelectedRecord ? '' : this.settings.customUserAgent,
      selectedCustomUserAgentId: removingSelectedRecord ? '' : this.settings.selectedCustomUserAgentId,
      customUserAgents: nextRecords,
      updatedAt: Date.now()
    };
    return this.persistSettings(this.service.normalizeSettings(nextSettings));
  }

  async clearLegacySiteRules(): Promise<void> {
    const store = await this.getStore();
    if (!store.hasSync(LEGACY_DESKTOP_SITE_RULES_KEY)) {
      return;
    }
    store.deleteSync(LEGACY_DESKTOP_SITE_RULES_KEY);
    store.flushSync();
  }

  private parseSettings(value: string): BrowserUserAgentSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as BrowserUserAgentSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private async persistSettings(settings: BrowserUserAgentSettings): Promise<BrowserUserAgentSettings> {
    this.settings = {
      defaultMode: settings.defaultMode,
      selectedPresetId: settings.selectedPresetId,
      customUserAgent: settings.customUserAgent,
      selectedCustomUserAgentId: settings.selectedCustomUserAgentId,
      customUserAgents: settings.customUserAgents.map((record: BrowserCustomUserAgentRecord) =>
        this.copyCustomUserAgentRecord(record)
      ),
      updatedAt: settings.updatedAt > 0 ? settings.updatedAt : Date.now()
    };
    const store = await this.getStore();
    store.putSync(USER_AGENT_SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    const savedSettings = this.getSettings();
    try {
      this.settingsChangeHandler?.(savedSettings);
    } catch (_error) {
    }
    return savedSettings;
  }

  private copyCustomUserAgentRecord(record: BrowserCustomUserAgentRecord): BrowserCustomUserAgentRecord {
    return {
      id: record.id,
      name: record.name,
      userAgent: record.userAgent,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt
    };
  }

  private resolveCustomUserAgentsForSave(settings: BrowserUserAgentSettings): BrowserCustomUserAgentRecord[] {
    if (settings.customUserAgents.length > 0) {
      return settings.customUserAgents;
    }
    if (this.settings.customUserAgents.length > 0) {
      return this.settings.customUserAgents;
    }
    const legacyCustomUserAgent = this.service.normalizeCustomUserAgent(settings.customUserAgent);
    if (legacyCustomUserAgent.length <= 0) {
      return [];
    }
    const record = this.service.buildCustomUserAgentRecord({
      name: '自定义 UA',
      userAgent: legacyCustomUserAgent
    });
    return record === undefined ? [] : [record];
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
