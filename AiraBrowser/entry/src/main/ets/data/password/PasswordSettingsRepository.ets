import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  PasswordManagerPreferences,
  PasswordManagerSettings
} from '../../common/models/BrowserModels';

const PREFERENCES_NAME: string = 'aira_browser_password';
const PASSWORD_SETTINGS_KEY: string = 'password_settings';

export const DEFAULT_PASSWORD_MANAGER_PREFERENCES: PasswordManagerPreferences = {
  officialVaultEnabled: true,
  regularAutofillEnabled: true,
  regularSavePromptEnabled: true,
  privateAutofillEnabled: true,
  privateSavePromptEnabled: false
};

export class PasswordSettingsRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settings: PasswordManagerSettings = this.buildDefaultSettings();

  async initialize(): Promise<PasswordManagerSettings> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(PASSWORD_SETTINGS_KEY, ''));
    this.settings = this.normalizeSettings(this.parseSettings(rawSettings));
    if (rawSettings.trim().length === 0) {
      await this.persistSettings(this.settings);
    }
    return this.getSettings();
  }

  getSettings(): PasswordManagerSettings {
    return this.cloneSettings(this.settings);
  }

  async updatePreferences(preferences: PasswordManagerPreferences): Promise<PasswordManagerSettings> {
    const nextSettings: PasswordManagerSettings = {
      provider: this.settings.provider,
      preferences: this.normalizePreferences(preferences),
      officialVaultVerifiedAt: this.settings.officialVaultVerifiedAt,
      officialVaultVerificationNote: this.settings.officialVaultVerificationNote,
      selfHostedCredentialStoreEnabled: false,
      updatedAt: Date.now()
    };
    return this.persistSettings(nextSettings);
  }

  async markOfficialVaultVerification(note: string): Promise<PasswordManagerSettings> {
    const nextSettings: PasswordManagerSettings = {
      provider: this.settings.provider,
      preferences: this.clonePreferences(this.settings.preferences),
      officialVaultVerifiedAt: Date.now(),
      officialVaultVerificationNote: note.trim(),
      selfHostedCredentialStoreEnabled: false,
      updatedAt: Date.now()
    };
    return this.persistSettings(nextSettings);
  }

  private normalizeSettings(value: PasswordManagerSettings | undefined): PasswordManagerSettings {
    return {
      provider: 'arkweb_official_vault',
      preferences: this.normalizePreferences(value?.preferences),
      officialVaultVerifiedAt: this.normalizeTimestamp(value?.officialVaultVerifiedAt),
      officialVaultVerificationNote: (value?.officialVaultVerificationNote ?? '').trim(),
      selfHostedCredentialStoreEnabled: false,
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizePreferences(value: PasswordManagerPreferences | undefined): PasswordManagerPreferences {
    return {
      officialVaultEnabled: typeof value?.officialVaultEnabled === 'boolean'
        ? value.officialVaultEnabled
        : DEFAULT_PASSWORD_MANAGER_PREFERENCES.officialVaultEnabled,
      regularAutofillEnabled: typeof value?.regularAutofillEnabled === 'boolean'
        ? value.regularAutofillEnabled
        : DEFAULT_PASSWORD_MANAGER_PREFERENCES.regularAutofillEnabled,
      regularSavePromptEnabled: typeof value?.regularSavePromptEnabled === 'boolean'
        ? value.regularSavePromptEnabled
        : DEFAULT_PASSWORD_MANAGER_PREFERENCES.regularSavePromptEnabled,
      privateAutofillEnabled: typeof value?.privateAutofillEnabled === 'boolean'
        ? value.privateAutofillEnabled
        : DEFAULT_PASSWORD_MANAGER_PREFERENCES.privateAutofillEnabled,
      privateSavePromptEnabled: false
    };
  }

  private parseSettings(value: string): PasswordManagerSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as PasswordManagerSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private buildDefaultSettings(): PasswordManagerSettings {
    return {
      provider: 'arkweb_official_vault',
      preferences: this.clonePreferences(DEFAULT_PASSWORD_MANAGER_PREFERENCES),
      officialVaultVerifiedAt: 0,
      officialVaultVerificationNote: '',
      selfHostedCredentialStoreEnabled: false,
      updatedAt: 0
    };
  }

  private async persistSettings(settings: PasswordManagerSettings): Promise<PasswordManagerSettings> {
    this.settings = this.cloneSettings(settings);
    const store = await this.getStore();
    store.putSync(PASSWORD_SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    return this.getSettings();
  }

  private cloneSettings(settings: PasswordManagerSettings): PasswordManagerSettings {
    return {
      provider: settings.provider,
      preferences: this.clonePreferences(settings.preferences),
      officialVaultVerifiedAt: settings.officialVaultVerifiedAt,
      officialVaultVerificationNote: settings.officialVaultVerificationNote,
      selfHostedCredentialStoreEnabled: settings.selfHostedCredentialStoreEnabled,
      updatedAt: settings.updatedAt
    };
  }

  private clonePreferences(value: PasswordManagerPreferences): PasswordManagerPreferences {
    return {
      officialVaultEnabled: value.officialVaultEnabled,
      regularAutofillEnabled: value.regularAutofillEnabled,
      regularSavePromptEnabled: value.regularSavePromptEnabled,
      privateAutofillEnabled: value.privateAutofillEnabled,
      privateSavePromptEnabled: false
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
