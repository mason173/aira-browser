import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_gesture_onboarding_prompt';
const STATE_KEY: string = 'state_v1';

export interface GestureOnboardingPromptState {
  firstSeenAt: number;
  promptShownAt: number;
  dismissedAt: number;
  showCount: number;
  updatedAt: number;
}

const DEFAULT_GESTURE_ONBOARDING_PROMPT_STATE: GestureOnboardingPromptState = {
  firstSeenAt: 0,
  promptShownAt: 0,
  dismissedAt: 0,
  showCount: 0,
  updatedAt: 0
};

export class GestureOnboardingPromptRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: GestureOnboardingPromptState = this.cloneState(DEFAULT_GESTURE_ONBOARDING_PROMPT_STATE);

  async initialize(): Promise<GestureOnboardingPromptState> {
    const store = await this.getStore();
    this.state = this.normalizeState(store.getSync(STATE_KEY, JSON.stringify(DEFAULT_GESTURE_ONBOARDING_PROMPT_STATE)));
    if (this.state.firstSeenAt <= 0) {
      const now = Date.now();
      this.state.firstSeenAt = now;
      this.state.updatedAt = now;
      await this.persist();
    }
    return this.getState();
  }

  getState(): GestureOnboardingPromptState {
    return this.cloneState(this.state);
  }

  hasCompleted(): boolean {
    return this.state.dismissedAt > 0;
  }

  async markShown(now: number = Date.now()): Promise<GestureOnboardingPromptState> {
    if (this.hasCompleted()) {
      return this.getState();
    }
    this.state.promptShownAt = now;
    this.state.showCount += 1;
    this.state.updatedAt = now;
    await this.persist();
    return this.getState();
  }

  async dismiss(now: number = Date.now()): Promise<GestureOnboardingPromptState> {
    if (this.state.dismissedAt <= 0) {
      this.state.dismissedAt = now;
      this.state.updatedAt = now;
      await this.persist();
    }
    return this.getState();
  }

  private async persist(): Promise<void> {
    const store = await this.getStore();
    store.putSync(STATE_KEY, JSON.stringify(this.state));
    store.flushSync();
  }

  private normalizeState(value: preferences.ValueType): GestureOnboardingPromptState {
    try {
      const parsed = JSON.parse(String(value)) as GestureOnboardingPromptState;
      return {
        firstSeenAt: this.normalizeTimestamp(parsed.firstSeenAt),
        promptShownAt: this.normalizeTimestamp(parsed.promptShownAt),
        dismissedAt: this.normalizeTimestamp(parsed.dismissedAt),
        showCount: this.normalizeCount(parsed.showCount),
        updatedAt: this.normalizeTimestamp(parsed.updatedAt)
      };
    } catch (_error) {
      return this.cloneState(DEFAULT_GESTURE_ONBOARDING_PROMPT_STATE);
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

  private cloneState(state: GestureOnboardingPromptState): GestureOnboardingPromptState {
    return {
      firstSeenAt: state.firstSeenAt,
      promptShownAt: state.promptShownAt,
      dismissedAt: state.dismissedAt,
      showCount: state.showCount,
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
