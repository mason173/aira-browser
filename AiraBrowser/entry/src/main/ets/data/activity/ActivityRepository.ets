import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  AiraActivityDailyAggregate,
  AiraActivityStoreState
} from '../../common/models/ActivityModels';

const PREFERENCES_NAME: string = 'aira_activity_daily';
const STATE_KEY: string = 'state_v1';
const MAX_LOCAL_DAYS: number = 420;

const DEFAULT_ACTIVITY_STORE_STATE: AiraActivityStoreState = {
  accountUid: '',
  totals: [],
  localContributions: [],
  localBackupTotalsFloor: [],
  g2VisibleHistorySeed: [],
  g2VisibleHistorySeedPrepared: false,
  updatedAt: 0
};

export interface ActivityRepositoryContentUpdate {
  totals: AiraActivityDailyAggregate[];
  localContributions: AiraActivityDailyAggregate[];
  localBackupTotalsFloor?: AiraActivityDailyAggregate[];
}

export type ActivityRepositoryContentUpdater = (
  state: AiraActivityStoreState
) => ActivityRepositoryContentUpdate;

type ActivityRepositoryStateMutation = (
  state: AiraActivityStoreState
) => AiraActivityStoreState | undefined;

export class ActivityRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: AiraActivityStoreState = this.cloneState(DEFAULT_ACTIVITY_STORE_STATE);
  private initializationPromise?: Promise<AiraActivityStoreState>;
  private mutationQueue: Promise<void> = Promise.resolve();

  async initialize(): Promise<AiraActivityStoreState> {
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.getStore()
        .then((store: preferences.Preferences) => {
          this.state = this.normalizeState(store.getSync(STATE_KEY, JSON.stringify(DEFAULT_ACTIVITY_STORE_STATE)));
          return this.getState();
        });
    }
    return this.initializationPromise;
  }

  getState(): AiraActivityStoreState {
    return this.cloneState(this.state);
  }

  listTotals(): AiraActivityDailyAggregate[] {
    return this.cloneAggregates(this.state.totals);
  }

  listLocalContributions(): AiraActivityDailyAggregate[] {
    return this.cloneAggregates(this.state.localContributions);
  }

  listTotalsForAccount(accountUid: string): AiraActivityDailyAggregate[] {
    if (this.state.accountUid !== accountUid.trim()) {
      return [];
    }
    return this.listTotals();
  }

  async ensureAccountScope(accountUid: string, now: number = Date.now()): Promise<AiraActivityStoreState> {
    const normalizedUid = accountUid.trim();
    return this.mutateState((state: AiraActivityStoreState): AiraActivityStoreState | undefined => {
      if (state.accountUid === normalizedUid) {
        return undefined;
      }
      return {
        accountUid: normalizedUid,
        totals: [],
        localContributions: [],
        localBackupTotalsFloor: [],
        g2VisibleHistorySeed: [],
        g2VisibleHistorySeedPrepared: false,
        updatedAt: now
      };
    });
  }

  async prepareG2VisibleHistorySeed(
    accountUid: string,
    now: number = Date.now()
  ): Promise<AiraActivityStoreState> {
    const normalizedUid = accountUid.trim();
    return this.mutateState((state: AiraActivityStoreState): AiraActivityStoreState | undefined => {
      const scopedState: AiraActivityStoreState = state.accountUid === normalizedUid ? state : {
        accountUid: normalizedUid,
        totals: [],
        localContributions: [],
        localBackupTotalsFloor: [],
        g2VisibleHistorySeed: [],
        g2VisibleHistorySeedPrepared: false,
        updatedAt: now
      };
      if (scopedState.g2VisibleHistorySeedPrepared) {
        return state.accountUid === normalizedUid ? undefined : scopedState;
      }
      return {
        accountUid: normalizedUid,
        totals: scopedState.totals,
        localContributions: [],
        localBackupTotalsFloor: scopedState.localBackupTotalsFloor,
        g2VisibleHistorySeed: scopedState.totals,
        g2VisibleHistorySeedPrepared: true,
        updatedAt: Math.max(scopedState.updatedAt, now)
      };
    });
  }

  async markG2VisibleHistorySeedPrepared(
    accountUid: string,
    now: number = Date.now()
  ): Promise<AiraActivityStoreState> {
    const normalizedUid = accountUid.trim();
    return this.mutateState((state: AiraActivityStoreState): AiraActivityStoreState | undefined => {
      const scopedState: AiraActivityStoreState = state.accountUid === normalizedUid ? state : {
        accountUid: normalizedUid,
        totals: [],
        localContributions: [],
        localBackupTotalsFloor: [],
        g2VisibleHistorySeed: [],
        g2VisibleHistorySeedPrepared: false,
        updatedAt: now
      };
      if (scopedState.g2VisibleHistorySeedPrepared) {
        return state.accountUid === normalizedUid ? undefined : scopedState;
      }
      return {
        accountUid: normalizedUid,
        totals: scopedState.totals,
        localContributions: scopedState.localContributions,
        localBackupTotalsFloor: scopedState.localBackupTotalsFloor,
        g2VisibleHistorySeed: [],
        g2VisibleHistorySeedPrepared: true,
        updatedAt: scopedState.updatedAt
      };
    });
  }

  async updateActivityState(
    accountUid: string,
    updater: ActivityRepositoryContentUpdater,
    now: number = Date.now()
  ): Promise<AiraActivityStoreState> {
    const normalizedUid = accountUid.trim();
    return this.mutateState((state: AiraActivityStoreState): AiraActivityStoreState | undefined => {
      const accountMatches = state.accountUid === normalizedUid;
      const scopedState: AiraActivityStoreState = state.accountUid === normalizedUid ? state : {
        accountUid: normalizedUid,
        totals: [],
        localContributions: [],
        localBackupTotalsFloor: [],
        g2VisibleHistorySeed: [],
        g2VisibleHistorySeedPrepared: false,
        updatedAt: now
      };
      const update = updater(scopedState);
      const totals = this.normalizeAggregates(update.totals);
      const localContributions = this.normalizeAggregates(update.localContributions);
      const localBackupTotalsFloor = update.localBackupTotalsFloor === undefined
        ? scopedState.localBackupTotalsFloor
        : this.normalizeAggregates(update.localBackupTotalsFloor);
      if (accountMatches && this.sameAggregates(scopedState.totals, totals) &&
        this.sameAggregates(scopedState.localContributions, localContributions) &&
        this.sameAggregates(scopedState.localBackupTotalsFloor, localBackupTotalsFloor)) {
        return undefined;
      }
      return {
        accountUid: normalizedUid,
        totals: totals,
        localContributions: localContributions,
        localBackupTotalsFloor: localBackupTotalsFloor,
        g2VisibleHistorySeed: scopedState.g2VisibleHistorySeed,
        g2VisibleHistorySeedPrepared: scopedState.g2VisibleHistorySeedPrepared,
        updatedAt: now
      };
    });
  }

  private normalizeState(value: preferences.ValueType): AiraActivityStoreState {
    try {
      const parsed = JSON.parse(String(value)) as AiraActivityStoreState;
      return this.normalizeStateValue(parsed);
    } catch (_error) {
      return this.cloneState(DEFAULT_ACTIVITY_STORE_STATE);
    }
  }

  private normalizeStateValue(value: AiraActivityStoreState): AiraActivityStoreState {
    const totals = this.normalizeAggregates(value.totals);
    const localContributions = Array.isArray(value.localContributions)
      ? this.normalizeAggregates(value.localContributions)
      : this.cloneAggregates(totals);
    const localBackupTotalsFloor = Array.isArray(value.localBackupTotalsFloor)
      ? this.normalizeAggregates(value.localBackupTotalsFloor)
      : [];
    const g2VisibleHistorySeedPrepared = value.g2VisibleHistorySeedPrepared === true;
    return {
      accountUid: this.normalizeAccountUid(value.accountUid),
      totals: totals,
      localContributions: localContributions,
      localBackupTotalsFloor: localBackupTotalsFloor,
      g2VisibleHistorySeed: g2VisibleHistorySeedPrepared
        ? this.normalizeAggregates(value.g2VisibleHistorySeed)
        : [],
      g2VisibleHistorySeedPrepared: g2VisibleHistorySeedPrepared,
      updatedAt: this.normalizeTimestamp(value.updatedAt)
    };
  }

  private normalizeAccountUid(value: string | undefined): string {
    return `${value ?? ''}`.trim();
  }

  private normalizeAggregates(value: AiraActivityDailyAggregate[] | undefined): AiraActivityDailyAggregate[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const byDate = new Map<string, AiraActivityDailyAggregate>();
    value.forEach((item: AiraActivityDailyAggregate) => {
      const date = `${item.date ?? ''}`.trim();
      if (!this.isValidDateKey(date)) {
        return;
      }
      const previous = byDate.get(date);
      const normalized: AiraActivityDailyAggregate = {
        date,
        score: this.normalizeCount(item.score),
        pageVisits: this.normalizeCount(item.pageVisits),
        searches: this.normalizeCount(item.searches),
        bookmarkActions: this.normalizeCount(item.bookmarkActions),
        downloads: this.normalizeCount(item.downloads),
        featureActions: this.normalizeCount(item.featureActions),
        activeSeconds: this.normalizeCount(item.activeSeconds),
        updatedAt: this.normalizeTimestamp(item.updatedAt)
      };
      if (previous === undefined) {
        byDate.set(date, normalized);
        return;
      }
      const merged: AiraActivityDailyAggregate = {
        date,
        score: previous.score + normalized.score,
        pageVisits: previous.pageVisits + normalized.pageVisits,
        searches: previous.searches + normalized.searches,
        bookmarkActions: previous.bookmarkActions + normalized.bookmarkActions,
        downloads: previous.downloads + normalized.downloads,
        featureActions: previous.featureActions + normalized.featureActions,
        activeSeconds: previous.activeSeconds + normalized.activeSeconds,
        updatedAt: Math.max(previous.updatedAt, normalized.updatedAt)
      };
      byDate.set(date, merged);
    });
    return Array.from(byDate.values())
      .sort((left: AiraActivityDailyAggregate, right: AiraActivityDailyAggregate) => left.date.localeCompare(right.date))
      .slice(-MAX_LOCAL_DAYS);
  }

  private async persist(): Promise<void> {
    const store = await this.getStore();
    await store.put(STATE_KEY, JSON.stringify(this.state));
    await store.flush();
  }

  private async mutateState(mutation: ActivityRepositoryStateMutation): Promise<AiraActivityStoreState> {
    await this.initialize();
    let result = this.getState();
    const operation = this.mutationQueue.then(async (): Promise<void> => {
      const nextState = mutation(this.getState());
      if (nextState === undefined) {
        result = this.getState();
        return;
      }
      this.state = this.normalizeStateValue(nextState);
      await this.persist();
      result = this.getState();
    });
    this.mutationQueue = operation.catch((_error: Error): void => {});
    await operation;
    return result;
  }

  private isValidDateKey(value: string): boolean {
    return /^\d{4}-\d{2}-\d{2}$/.test(value);
  }

  private normalizeTimestamp(value: number | undefined): number {
    const timestamp = Number(value);
    return Number.isFinite(timestamp) && timestamp > 0 ? Math.round(timestamp) : 0;
  }

  private normalizeCount(value: number | undefined): number {
    const count = Number(value);
    return Number.isFinite(count) && count > 0 ? Math.round(count) : 0;
  }

  private sameAggregates(
    left: AiraActivityDailyAggregate[],
    right: AiraActivityDailyAggregate[]
  ): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let index = 0; index < left.length; index += 1) {
      const leftItem = left[index];
      const rightItem = right[index];
      if (leftItem.date !== rightItem.date || leftItem.score !== rightItem.score ||
        leftItem.pageVisits !== rightItem.pageVisits || leftItem.searches !== rightItem.searches ||
        leftItem.bookmarkActions !== rightItem.bookmarkActions || leftItem.downloads !== rightItem.downloads ||
        leftItem.featureActions !== rightItem.featureActions || leftItem.activeSeconds !== rightItem.activeSeconds ||
        leftItem.updatedAt !== rightItem.updatedAt) {
        return false;
      }
    }
    return true;
  }

  private cloneState(state: AiraActivityStoreState): AiraActivityStoreState {
    return {
      accountUid: state.accountUid,
      totals: this.cloneAggregates(state.totals),
      localContributions: this.cloneAggregates(state.localContributions),
      localBackupTotalsFloor: this.cloneAggregates(state.localBackupTotalsFloor),
      g2VisibleHistorySeed: this.cloneAggregates(state.g2VisibleHistorySeed),
      g2VisibleHistorySeedPrepared: state.g2VisibleHistorySeedPrepared,
      updatedAt: state.updatedAt
    };
  }

  private cloneAggregates(items: AiraActivityDailyAggregate[]): AiraActivityDailyAggregate[] {
    return items.map((item: AiraActivityDailyAggregate) => this.cloneAggregate(item));
  }

  private cloneAggregate(item: AiraActivityDailyAggregate): AiraActivityDailyAggregate {
    return {
      date: item.date,
      score: item.score,
      pageVisits: item.pageVisits,
      searches: item.searches,
      bookmarkActions: item.bookmarkActions,
      downloads: item.downloads,
      featureActions: item.featureActions,
      activeSeconds: item.activeSeconds,
      updatedAt: item.updatedAt
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
