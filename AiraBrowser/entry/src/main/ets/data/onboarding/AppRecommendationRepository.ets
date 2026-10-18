import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_app_recommendation';
const STATE_KEY: string = 'state_v1';

/**
 * One device-local fact per recommendation campaign: that this device already
 * showed it (`shownAt`) and that the user closed it (`dismissedAt`).
 *
 * `id` is the campaign identity, not the app identity. Recommending the same app
 * again later is a new push and takes a new id, so "the user said no to this once"
 * never silently becomes "the user said no to this app forever".
 */
export interface AppRecommendationRecord {
  id: string;
  shownAt: number;
  dismissedAt: number;
}

/**
 * Device-local memory for the app recommendations. It records only presentation
 * facts, keyed by campaign: which recommendations this device has been told about,
 * and which ones the user closed.
 *
 * Nothing here models the recommended app. It stores no bundle name, no store URL,
 * and no install flag, because the install question belongs to the AppGallery and
 * answering it inside Aira would mean reading the user's installed-app list for no
 * reason. This is why adding a new recommendation is a source change plus one new
 * campaign id, and never a migration of this record.
 *
 * The memory is deliberately device-local rather than account-bound. A fresh install
 * starts from an empty store, so someone who uninstalls and installs again is told
 * once more; a user who keeps the app is never told twice about the same campaign.
 */
export interface AppRecommendationState {
  records: AppRecommendationRecord[];
}

export function buildEmptyAppRecommendationState(): AppRecommendationState {
  return {
    records: []
  };
}

export class AppRecommendationRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: AppRecommendationState = buildEmptyAppRecommendationState();

  async initialize(): Promise<void> {
    const store = await this.getStore();
    this.state = this.normalizeState(store.getSync(STATE_KEY, '{}'));
  }

  getState(): AppRecommendationState {
    const records: AppRecommendationRecord[] = [];
    for (let index = 0; index < this.state.records.length; index++) {
      const record = this.state.records[index];
      records.push({ id: record.id, shownAt: record.shownAt, dismissedAt: record.dismissedAt });
    }
    return { records: records };
  }

  /**
   * Whether this campaign is spent. Shown once, or closed once, is the end of it —
   * and it ends only this campaign, never the ones that come after it.
   */
  hasCompleted(id: string): boolean {
    const record = this.findRecord(id);
    return record !== undefined && (record.shownAt > 0 || record.dismissedAt > 0);
  }

  async markShown(id: string, now: number = Date.now()): Promise<AppRecommendationState> {
    return this.commit(id, now, false);
  }

  async markDismissed(id: string, now: number = Date.now()): Promise<AppRecommendationState> {
    return this.commit(id, now, true);
  }

  private async commit(id: string, now: number, dismissed: boolean): Promise<AppRecommendationState> {
    if (id.length === 0) {
      return this.getState();
    }
    // The in-memory state flips before the write so the caller never re-evaluates
    // against a campaign it has just spent, even while the flush is in flight.
    const record = this.ensureRecord(id);
    if (record.shownAt <= 0) {
      record.shownAt = now;
    }
    if (dismissed && record.dismissedAt <= 0) {
      record.dismissedAt = now;
    }
    await this.persist();
    return this.getState();
  }

  private findRecord(id: string): AppRecommendationRecord | undefined {
    for (let index = 0; index < this.state.records.length; index++) {
      const record = this.state.records[index];
      if (record.id === id) {
        return record;
      }
    }
    return undefined;
  }

  private ensureRecord(id: string): AppRecommendationRecord {
    const existing = this.findRecord(id);
    if (existing !== undefined) {
      return existing;
    }
    const created: AppRecommendationRecord = { id: id, shownAt: 0, dismissedAt: 0 };
    this.state.records.push(created);
    return created;
  }

  private async persist(): Promise<void> {
    const store = await this.getStore();
    store.putSync(STATE_KEY, JSON.stringify(this.state));
    store.flushSync();
  }

  private normalizeState(value: preferences.ValueType): AppRecommendationState {
    const raw = String(value ?? '').trim();
    if (raw.length === 0) {
      return buildEmptyAppRecommendationState();
    }
    try {
      const parsed = JSON.parse(raw) as Record<string, Object> | undefined;
      const stored = parsed?.records;
      if (!Array.isArray(stored)) {
        return buildEmptyAppRecommendationState();
      }
      const records: AppRecommendationRecord[] = [];
      for (let index = 0; index < stored.length; index++) {
        const candidate = stored[index] as Record<string, Object> | undefined;
        const id = typeof candidate?.id === 'string' ? candidate.id : '';
        if (id.length === 0) {
          continue;
        }
        records.push({
          id: id,
          shownAt: this.normalizeTimestamp(candidate?.shownAt),
          dismissedAt: this.normalizeTimestamp(candidate?.dismissedAt)
        });
      }
      return { records: records };
    } catch (_error) {
      return buildEmptyAppRecommendationState();
    }
  }

  private normalizeTimestamp(value: Object | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.floor(value));
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
