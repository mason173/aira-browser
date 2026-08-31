import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_release_notice';
const STATE_KEY: string = 'state_v1';

export interface ReleaseNoticeRepositoryState {
  firstObservedVersionCode: number;
  lastObservedVersionCode: number;
  lastAcknowledgedVersionCode: number;
  lastAcknowledgedVersionName: string;
  lastAcknowledgedAt: number;
  updatedAt: number;
}

const DEFAULT_RELEASE_NOTICE_STATE: ReleaseNoticeRepositoryState = {
  firstObservedVersionCode: 0,
  lastObservedVersionCode: 0,
  lastAcknowledgedVersionCode: 0,
  lastAcknowledgedVersionName: '',
  lastAcknowledgedAt: 0,
  updatedAt: 0
};

export class ReleaseNoticeRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: ReleaseNoticeRepositoryState = this.cloneState(DEFAULT_RELEASE_NOTICE_STATE);
  private initialized: boolean = false;

  async initialize(currentVersionCode: number, currentVersionName: string, now: number = Date.now()):
    Promise<ReleaseNoticeRepositoryState> {
    const store = await this.getStore();
    this.state = this.normalizeState(store.getSync(STATE_KEY, JSON.stringify(DEFAULT_RELEASE_NOTICE_STATE)));
    const normalizedVersionCode = this.normalizeCount(currentVersionCode);
    if (this.state.firstObservedVersionCode <= 0) {
      this.state.firstObservedVersionCode = normalizedVersionCode;
      this.state.lastObservedVersionCode = normalizedVersionCode;
      this.state.lastAcknowledgedVersionCode = normalizedVersionCode;
      this.state.lastAcknowledgedVersionName = currentVersionName.trim();
      this.state.lastAcknowledgedAt = now;
      this.state.updatedAt = now;
      await this.persist();
    } else if (normalizedVersionCode > this.state.lastObservedVersionCode) {
      this.state.lastObservedVersionCode = normalizedVersionCode;
      this.state.updatedAt = now;
      await this.persist();
    }
    this.initialized = true;
    return this.getState();
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  getState(): ReleaseNoticeRepositoryState {
    return this.cloneState(this.state);
  }

  async acknowledge(versionCode: number, versionName: string, now: number = Date.now()):
    Promise<ReleaseNoticeRepositoryState> {
    this.state.lastAcknowledgedVersionCode = this.normalizeCount(versionCode);
    this.state.lastAcknowledgedVersionName = versionName.trim();
    this.state.lastAcknowledgedAt = now;
    this.state.updatedAt = now;
    await this.persist();
    return this.getState();
  }

  private async persist(): Promise<void> {
    const store = await this.getStore();
    store.putSync(STATE_KEY, JSON.stringify(this.state));
    store.flushSync();
  }

  private normalizeState(value: preferences.ValueType): ReleaseNoticeRepositoryState {
    try {
      const parsed = JSON.parse(String(value)) as ReleaseNoticeRepositoryState;
      return {
        firstObservedVersionCode: this.normalizeCount(parsed.firstObservedVersionCode),
        lastObservedVersionCode: this.normalizeCount(parsed.lastObservedVersionCode),
        lastAcknowledgedVersionCode: this.normalizeCount(parsed.lastAcknowledgedVersionCode),
        lastAcknowledgedVersionName: `${parsed.lastAcknowledgedVersionName ?? ''}`.trim(),
        lastAcknowledgedAt: this.normalizeTimestamp(parsed.lastAcknowledgedAt),
        updatedAt: this.normalizeTimestamp(parsed.updatedAt)
      };
    } catch (_error) {
      return this.cloneState(DEFAULT_RELEASE_NOTICE_STATE);
    }
  }

  private normalizeCount(value: number | undefined): number {
    const count = Number(value);
    return Number.isFinite(count) && count > 0 ? Math.round(count) : 0;
  }

  private normalizeTimestamp(value: number | undefined): number {
    const timestamp = Number(value);
    return Number.isFinite(timestamp) && timestamp > 0 ? Math.round(timestamp) : 0;
  }

  private cloneState(state: ReleaseNoticeRepositoryState): ReleaseNoticeRepositoryState {
    return {
      firstObservedVersionCode: state.firstObservedVersionCode,
      lastObservedVersionCode: state.lastObservedVersionCode,
      lastAcknowledgedVersionCode: state.lastAcknowledgedVersionCode,
      lastAcknowledgedVersionName: state.lastAcknowledgedVersionName,
      lastAcknowledgedAt: state.lastAcknowledgedAt,
      updatedAt: state.updatedAt
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
