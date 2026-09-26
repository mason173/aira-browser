import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  AIRA_FEATURE_INTRO_COMPLETED_AT_KEY,
  AIRA_FEATURE_INTRO_COMPLETED_VERSION_KEY,
  AIRA_FEATURE_INTRO_PREFERENCES_NAME,
  AIRA_FEATURE_INTRO_VERSION
} from '../../services/onboarding/AiraFeatureIntro';

export interface FeatureIntroState {
  completedVersion: number;
  completedAt: number;
}

export class FeatureIntroRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: FeatureIntroState = {
    completedVersion: 0,
    completedAt: 0
  };

  async initialize(): Promise<FeatureIntroState> {
    const store = await this.getStore();
    this.state = {
      completedVersion: this.normalizeVersion(store.getSync(AIRA_FEATURE_INTRO_COMPLETED_VERSION_KEY, 0)),
      completedAt: this.normalizeTimestamp(store.getSync(AIRA_FEATURE_INTRO_COMPLETED_AT_KEY, 0))
    };
    return this.getState();
  }

  getState(): FeatureIntroState {
    return {
      completedVersion: this.state.completedVersion,
      completedAt: this.state.completedAt
    };
  }

  hasCompletedCurrentVersion(): boolean {
    return this.state.completedVersion >= AIRA_FEATURE_INTRO_VERSION;
  }

  async completeCurrentVersion(): Promise<FeatureIntroState> {
    const completedAt = Date.now();
    this.state = {
      completedVersion: AIRA_FEATURE_INTRO_VERSION,
      completedAt: completedAt
    };
    const store = await this.getStore();
    store.putSync(AIRA_FEATURE_INTRO_COMPLETED_VERSION_KEY, this.state.completedVersion);
    store.putSync(AIRA_FEATURE_INTRO_COMPLETED_AT_KEY, completedAt);
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
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        AIRA_FEATURE_INTRO_PREFERENCES_NAME
      ).then((store: preferences.Preferences) => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }
}
