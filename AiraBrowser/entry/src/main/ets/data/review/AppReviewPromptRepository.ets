import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_app_review_prompt';
const STATE_KEY: string = 'state_v1';

export type AppReviewPromptLastAction = 'none' | 'shown' | 'deferred' | 'suppressed' | 'accepted';

export interface AppReviewPromptState {
  firstSeenAt: number;
  launchCount: number;
  regularPageVisitCount: number;
  promptCount: number;
  lastPromptAt: number;
  lastDeferredAt: number;
  suppressedAt: number;
  acceptedAt: number;
  acceptedVersionName: string;
  lastAction: AppReviewPromptLastAction;
  updatedAt: number;
}

const DEFAULT_APP_REVIEW_PROMPT_STATE: AppReviewPromptState = {
  firstSeenAt: 0,
  launchCount: 0,
  regularPageVisitCount: 0,
  promptCount: 0,
  lastPromptAt: 0,
  lastDeferredAt: 0,
  suppressedAt: 0,
  acceptedAt: 0,
  acceptedVersionName: '',
  lastAction: 'none',
  updatedAt: 0
};

export class AppReviewPromptRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: AppReviewPromptState = this.cloneState(DEFAULT_APP_REVIEW_PROMPT_STATE);

  async initialize(): Promise<AppReviewPromptState> {
    const store = await this.getStore();
    this.state = this.normalizeState(store.getSync(STATE_KEY, JSON.stringify(DEFAULT_APP_REVIEW_PROMPT_STATE)));
    if (this.state.firstSeenAt <= 0) {
      const now = Date.now();
      this.state.firstSeenAt = now;
      this.state.updatedAt = now;
      await this.persist();
    }
    return this.getState();
  }

  getState(): AppReviewPromptState {
    return this.cloneState(this.state);
  }

  async recordLaunch(now: number = Date.now()): Promise<AppReviewPromptState> {
    this.state.firstSeenAt = this.state.firstSeenAt > 0 ? this.state.firstSeenAt : now;
    this.state.launchCount += 1;
    this.state.updatedAt = now;
    await this.persist();
    return this.getState();
  }

  async recordRegularPageVisit(now: number = Date.now()): Promise<AppReviewPromptState> {
    this.state.firstSeenAt = this.state.firstSeenAt > 0 ? this.state.firstSeenAt : now;
    this.state.regularPageVisitCount += 1;
    this.state.updatedAt = now;
    await this.persist();
    return this.getState();
  }

  async markPromptShown(now: number = Date.now()): Promise<AppReviewPromptState> {
    this.state.promptCount += 1;
    this.state.lastPromptAt = now;
    this.state.lastAction = 'shown';
    this.state.updatedAt = now;
    await this.persist();
    return this.getState();
  }

  async defer(now: number = Date.now()): Promise<AppReviewPromptState> {
    this.state.lastDeferredAt = now;
    this.state.lastAction = 'deferred';
    this.state.updatedAt = now;
    await this.persist();
    return this.getState();
  }

  async suppress(now: number = Date.now()): Promise<AppReviewPromptState> {
    this.state.suppressedAt = now;
    this.state.lastAction = 'suppressed';
    this.state.updatedAt = now;
    await this.persist();
    return this.getState();
  }

  async accept(versionName: string, now: number = Date.now()): Promise<AppReviewPromptState> {
    this.state.acceptedAt = now;
    this.state.acceptedVersionName = versionName.trim();
    this.state.lastAction = 'accepted';
    this.state.updatedAt = now;
    await this.persist();
    return this.getState();
  }

  private async persist(): Promise<void> {
    const store = await this.getStore();
    store.putSync(STATE_KEY, JSON.stringify(this.state));
    store.flushSync();
  }

  private normalizeState(value: preferences.ValueType): AppReviewPromptState {
    try {
      const parsed = JSON.parse(String(value)) as AppReviewPromptState;
      return {
        firstSeenAt: this.normalizeTimestamp(parsed.firstSeenAt),
        launchCount: this.normalizeCount(parsed.launchCount),
        regularPageVisitCount: this.normalizeCount(parsed.regularPageVisitCount),
        promptCount: this.normalizeCount(parsed.promptCount),
        lastPromptAt: this.normalizeTimestamp(parsed.lastPromptAt),
        lastDeferredAt: this.normalizeTimestamp(parsed.lastDeferredAt),
        suppressedAt: this.normalizeTimestamp(parsed.suppressedAt),
        acceptedAt: this.normalizeTimestamp(parsed.acceptedAt),
        acceptedVersionName: `${parsed.acceptedVersionName ?? ''}`.trim(),
        lastAction: this.normalizeLastAction(parsed.lastAction),
        updatedAt: this.normalizeTimestamp(parsed.updatedAt)
      };
    } catch (_error) {
      return this.cloneState(DEFAULT_APP_REVIEW_PROMPT_STATE);
    }
  }

  private normalizeTimestamp(value: number | undefined): number {
    const timestamp = Number(value);
    return Number.isFinite(timestamp) && timestamp > 0 ? Math.round(timestamp) : 0;
  }

  private normalizeCount(value: number | undefined): number {
    const count = Number(value);
    return Number.isFinite(count) && count > 0 ? Math.round(count) : 0;
  }

  private normalizeLastAction(value: string | undefined): AppReviewPromptLastAction {
    if (value === 'shown' || value === 'deferred' || value === 'suppressed' || value === 'accepted') {
      return value;
    }
    return 'none';
  }

  private cloneState(state: AppReviewPromptState): AppReviewPromptState {
    return {
      firstSeenAt: state.firstSeenAt,
      launchCount: state.launchCount,
      regularPageVisitCount: state.regularPageVisitCount,
      promptCount: state.promptCount,
      lastPromptAt: state.lastPromptAt,
      lastDeferredAt: state.lastDeferredAt,
      suppressedAt: state.suppressedAt,
      acceptedAt: state.acceptedAt,
      acceptedVersionName: state.acceptedVersionName,
      lastAction: state.lastAction,
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
