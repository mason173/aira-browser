import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

export const HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION: number = 8;

const PREFERENCES_NAME: string = 'aira_huawei_space_bookmark_upgrade';
const STATE_KEY: string = 'state';

export interface HuaweiSpaceBookmarkUpgradeState {
  completedVersion: number;
  requiredVersion: number;
  promptedVersion: number;
  updatedAt: number;
}

export class HuaweiSpaceBookmarkUpgradeStore {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: HuaweiSpaceBookmarkUpgradeState = this.defaultState();
  private initializationPromise?: Promise<HuaweiSpaceBookmarkUpgradeState>;
  private initialized: boolean = false;

  async initialize(): Promise<HuaweiSpaceBookmarkUpgradeState> {
    if (this.initialized) {
      return this.getState();
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.getStore()
        .then((store: preferences.Preferences): HuaweiSpaceBookmarkUpgradeState => {
          const storedValue = String(store.getSync(STATE_KEY, ''));
          this.state = this.parseState(storedValue) ?? this.defaultState();
          this.initialized = true;
          return this.getState();
        })
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw error;
        });
    }
    return this.initializationPromise;
  }

  getState(): HuaweiSpaceBookmarkUpgradeState {
    return {
      completedVersion: this.state.completedVersion,
      requiredVersion: this.state.requiredVersion,
      promptedVersion: this.state.promptedVersion,
      updatedAt: this.state.updatedAt
    };
  }

  async prepareCurrentVersion(affectedLegacySelection: boolean): Promise<HuaweiSpaceBookmarkUpgradeState> {
    await this.initialize();
    if (this.state.completedVersion >= HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION) {
      return this.getState();
    }
    if (this.state.requiredVersion >= HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION) {
      return this.getState();
    }
    if (affectedLegacySelection || this.state.requiredVersion > 0) {
      return this.persist({
        completedVersion: this.state.completedVersion,
        requiredVersion: HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION,
        promptedVersion: this.state.promptedVersion,
        updatedAt: Date.now()
      });
    }
    return this.persist({
      completedVersion: HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION,
      requiredVersion: 0,
      promptedVersion: HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION,
      updatedAt: Date.now()
    });
  }

  async markPrompted(): Promise<HuaweiSpaceBookmarkUpgradeState> {
    await this.initialize();
    if (this.state.requiredVersion < HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION ||
      this.state.promptedVersion >= HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION) {
      return this.getState();
    }
    return this.persist({
      completedVersion: this.state.completedVersion,
      requiredVersion: this.state.requiredVersion,
      promptedVersion: HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION,
      updatedAt: Date.now()
    });
  }

  async markCompleted(): Promise<HuaweiSpaceBookmarkUpgradeState> {
    await this.initialize();
    if (this.state.completedVersion >= HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION &&
      this.state.requiredVersion === 0) {
      return this.getState();
    }
    return this.persist({
      completedVersion: HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION,
      requiredVersion: 0,
      promptedVersion: HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION,
      updatedAt: Date.now()
    });
  }

  isCurrentVersionRequired(): boolean {
    return this.state.completedVersion < HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION &&
      this.state.requiredVersion >= HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION;
  }

  shouldPresentCurrentVersion(): boolean {
    return this.isCurrentVersionRequired() &&
      this.state.promptedVersion < HUAWEI_SPACE_BOOKMARK_CURRENT_UPGRADE_VERSION;
  }

  private async persist(state: HuaweiSpaceBookmarkUpgradeState): Promise<HuaweiSpaceBookmarkUpgradeState> {
    const normalized = this.normalizeState(state);
    const store = await this.getStore();
    store.putSync(STATE_KEY, JSON.stringify(normalized));
    store.flushSync();
    this.state = normalized;
    this.initialized = true;
    return this.getState();
  }

  private parseState(value: string): HuaweiSpaceBookmarkUpgradeState | undefined {
    if (value.trim().length <= 0) {
      return undefined;
    }
    try {
      return this.normalizeState(JSON.parse(value) as HuaweiSpaceBookmarkUpgradeState);
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeState(value: HuaweiSpaceBookmarkUpgradeState): HuaweiSpaceBookmarkUpgradeState {
    return {
      completedVersion: this.normalizeVersion(value?.completedVersion),
      requiredVersion: this.normalizeVersion(value?.requiredVersion),
      promptedVersion: this.normalizeVersion(value?.promptedVersion),
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizeVersion(value: number | undefined): number {
    const numberValue = Number(value ?? 0);
    if (!Number.isFinite(numberValue) || numberValue < 0) {
      return 0;
    }
    return Math.floor(numberValue);
  }

  private normalizeTimestamp(value: number | undefined): number {
    const numberValue = Number(value ?? 0);
    if (!Number.isFinite(numberValue) || numberValue < 0) {
      return 0;
    }
    return Math.floor(numberValue);
  }

  private defaultState(): HuaweiSpaceBookmarkUpgradeState {
    return {
      completedVersion: 0,
      requiredVersion: 0,
      promptedVersion: 0,
      updatedAt: 0
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
