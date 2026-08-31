import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_browser_userscript_risk_consent';
const ACCEPTED_VERSION_KEY: string = 'accepted_version';

export const USER_SCRIPT_RISK_CONSENT_VERSION: number = 1;

export interface UserScriptRiskConsentState {
  acceptedVersion: number;
  acceptedAt: number;
}

export class UserScriptRiskConsentRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private initializationPromise?: Promise<void>;
  private state: UserScriptRiskConsentState = {
    acceptedVersion: 0,
    acceptedAt: 0
  };

  async initialize(): Promise<UserScriptRiskConsentState> {
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.loadState();
    }
    try {
      await this.initializationPromise;
    } catch (error) {
      this.initializationPromise = undefined;
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('User script risk consent initialization failed.');
    }
    return this.getState();
  }

  private async loadState(): Promise<void> {
    const store = await this.getStore();
    this.state = {
      acceptedVersion: this.normalizeVersion(store.getSync(ACCEPTED_VERSION_KEY, 0)),
      acceptedAt: this.normalizeTimestamp(store.getSync(`${ACCEPTED_VERSION_KEY}_at`, 0))
    };
  }

  getState(): UserScriptRiskConsentState {
    return {
      acceptedVersion: this.state.acceptedVersion,
      acceptedAt: this.state.acceptedAt
    };
  }

  hasAcceptedCurrentVersion(): boolean {
    return this.state.acceptedVersion >= USER_SCRIPT_RISK_CONSENT_VERSION;
  }

  async acceptCurrentVersion(): Promise<UserScriptRiskConsentState> {
    await this.initialize();
    const acceptedAt = Date.now();
    this.state = {
      acceptedVersion: USER_SCRIPT_RISK_CONSENT_VERSION,
      acceptedAt: acceptedAt
    };
    const store = await this.getStore();
    store.putSync(ACCEPTED_VERSION_KEY, this.state.acceptedVersion);
    store.putSync(`${ACCEPTED_VERSION_KEY}_at`, acceptedAt);
    store.flushSync();
    return this.getState();
  }

  private normalizeVersion(value: preferences.ValueType): number {
    const version = Number(value);
    return Number.isFinite(version) && version > 0 ? Math.round(version) : 0;
  }

  private normalizeTimestamp(value: preferences.ValueType): number {
    const timestamp = Number(value);
    return Number.isFinite(timestamp) && timestamp > 0 ? Math.round(timestamp) : 0;
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
