import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  DEFAULT_SECURE_DNS_SETTINGS,
  SecureDnsCustomProfile,
  SecureDnsSettings,
  SecureDnsSettingsModel
} from '../../core/settings/SecureDnsSettingsModel';

const PREFERENCES_NAME: string = 'aira_browser_secure_dns';
const SETTINGS_KEY: string = 'secure_dns_settings';
const LEGACY_CUSTOM_PROFILE_ID: string = 'legacy-imported-secure-dns';

interface LegacySecureDnsSettings extends SecureDnsSettings {
  customEndpoint?: string;
}

export class SecureDnsSettingsRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settingsModel: SecureDnsSettingsModel;
  private settings: SecureDnsSettings = DEFAULT_SECURE_DNS_SETTINGS;

  constructor(settingsModel: SecureDnsSettingsModel = new SecureDnsSettingsModel()) {
    this.settingsModel = settingsModel;
  }

  async initialize(): Promise<SecureDnsSettings> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(SETTINGS_KEY, ''));
    const parsedSettings = this.parseSettings(rawSettings);
    const isLegacySettings = this.isLegacySettings(parsedSettings);
    this.settings = this.settingsModel.normalize(this.migrateLegacySettings(parsedSettings));
    if (isLegacySettings) {
      store.putSync(SETTINGS_KEY, JSON.stringify(this.settings));
      await store.flush();
    }
    return this.getSettings();
  }

  getSettings(): SecureDnsSettings {
    return this.settingsModel.normalize(this.settings);
  }

  async save(settings: SecureDnsSettings): Promise<SecureDnsSettings> {
    const normalized = this.settingsModel.normalize(settings);
    const store = await this.getStore();
    store.putSync(SETTINGS_KEY, JSON.stringify(normalized));
    await store.flush();
    this.settings = normalized;
    return this.getSettings();
  }

  private parseSettings(value: string): SecureDnsSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as SecureDnsSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private isLegacySettings(settings: SecureDnsSettings | undefined): boolean {
    if (settings === undefined || settings.customProfiles !== undefined) {
      return false;
    }
    return (settings as LegacySecureDnsSettings).customEndpoint !== undefined;
  }

  private migrateLegacySettings(settings: SecureDnsSettings | undefined): SecureDnsSettings | undefined {
    if (!this.isLegacySettings(settings) || settings === undefined) {
      return settings;
    }
    const legacyEndpoint = ((settings as LegacySecureDnsSettings).customEndpoint ?? '').trim();
    const customProfiles: SecureDnsCustomProfile[] = [];
    if (legacyEndpoint.length > 0) {
      customProfiles.push({
        id: LEGACY_CUSTOM_PROFILE_ID,
        name: '已导入 DNS',
        endpoint: legacyEndpoint
      });
    }
    return {
      selectionId: settings.selectionId,
      activeCustomProfileId: customProfiles.length > 0 ? LEGACY_CUSTOM_PROFILE_ID : '',
      customProfiles: customProfiles
    };
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences): preferences.Preferences => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}
