import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_sync_experience_state_g2';
const STATE_KEY: string = 'state';

export interface SyncExperiencePersistedState {
  suspended: boolean;
  bookmarkSelected: boolean;
  personalizationSelected: boolean;
  historySelected: boolean;
  historyAccountUid: string;
  updatedAt: number;
}

export class SyncExperienceStateStore {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: SyncExperiencePersistedState = this.defaultState();
  private initializationPromise?: Promise<SyncExperiencePersistedState>;
  private initialized: boolean = false;

  async initialize(
    bookmarkEnabled: boolean = false,
    personalizationEnabled: boolean = false,
    hasActiveProvider: boolean = false,
    historyEnabled: boolean = true
  ): Promise<SyncExperiencePersistedState> {
    if (this.initialized) {
      return this.getState();
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.getStore()
        .then((store: preferences.Preferences) => {
          const storedValue = String(store.getSync(STATE_KEY, ''));
          const parsed = this.parseState(storedValue);
          this.state = parsed === undefined
            ? this.buildInitialState(bookmarkEnabled, personalizationEnabled, hasActiveProvider, historyEnabled)
            : this.normalizeState(parsed);
          if (storedValue.trim().length === 0) {
            this.persistSync(this.state, store);
          }
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

  getState(): SyncExperiencePersistedState {
    return this.cloneState(this.state);
  }

  async suspend(
    bookmarkSelected: boolean,
    personalizationSelected: boolean,
    historySelected: boolean = this.state.historySelected
  ): Promise<SyncExperiencePersistedState> {
    await this.initialize();
    return this.persist({
      suspended: true,
      bookmarkSelected: bookmarkSelected,
      personalizationSelected: personalizationSelected,
      historySelected: historySelected,
      historyAccountUid: historySelected ? this.state.historyAccountUid : '',
      updatedAt: Date.now()
    });
  }

  async resume(): Promise<SyncExperiencePersistedState> {
    await this.initialize();
    return this.persist({
      suspended: false,
      bookmarkSelected: this.state.bookmarkSelected,
      personalizationSelected: this.state.personalizationSelected,
      historySelected: this.state.historySelected,
      historyAccountUid: this.state.historyAccountUid,
      updatedAt: Date.now()
    });
  }

  async setSelections(
    bookmarkSelected: boolean,
    personalizationSelected: boolean,
    suspended: boolean = this.state.suspended,
    historySelected: boolean = this.state.historySelected,
    historyAccountUid: string = this.state.historyAccountUid
  ): Promise<SyncExperiencePersistedState> {
    await this.initialize();
    return this.persist({
      suspended: suspended,
      bookmarkSelected: bookmarkSelected,
      personalizationSelected: personalizationSelected,
      historySelected: historySelected,
      historyAccountUid: historySelected ? historyAccountUid.trim() : '',
      updatedAt: Date.now()
    });
  }

  async setBookmarkSelected(selected: boolean): Promise<SyncExperiencePersistedState> {
    await this.initialize();
    return this.setSelections(selected, this.state.personalizationSelected);
  }

  async setPersonalizationSelected(selected: boolean): Promise<SyncExperiencePersistedState> {
    await this.initialize();
    return this.setSelections(this.state.bookmarkSelected, selected);
  }

  async setHistorySelected(
    selected: boolean,
    accountUid: string = this.state.historyAccountUid
  ): Promise<SyncExperiencePersistedState> {
    await this.initialize();
    return this.setSelections(
      this.state.bookmarkSelected,
      this.state.personalizationSelected,
      this.state.suspended,
      selected,
      accountUid
    );
  }

  private buildInitialState(
    bookmarkEnabled: boolean,
    personalizationEnabled: boolean,
    hasActiveProvider: boolean,
    historyEnabled: boolean
  ): SyncExperiencePersistedState {
    const hasEnabledDomain = bookmarkEnabled || personalizationEnabled;
    return {
      suspended: false,
      bookmarkSelected: hasActiveProvider && hasEnabledDomain ? bookmarkEnabled : true,
      personalizationSelected: hasActiveProvider && hasEnabledDomain ? personalizationEnabled : true,
      historySelected: historyEnabled,
      historyAccountUid: '',
      updatedAt: 0
    };
  }

  private defaultState(): SyncExperiencePersistedState {
    return {
      suspended: false,
      bookmarkSelected: true,
      personalizationSelected: true,
      historySelected: true,
      historyAccountUid: '',
      updatedAt: 0
    };
  }

  private async persist(state: SyncExperiencePersistedState): Promise<SyncExperiencePersistedState> {
    this.state = this.normalizeState(state);
    const store = await this.getStore();
    this.persistSync(this.state, store);
    this.initialized = true;
    return this.getState();
  }

  private persistSync(state: SyncExperiencePersistedState, store: preferences.Preferences): void {
    store.putSync(STATE_KEY, JSON.stringify(state));
    store.flushSync();
  }

  private parseState(value: string): SyncExperiencePersistedState | undefined {
    if (value.trim().length <= 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as SyncExperiencePersistedState;
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeState(value: SyncExperiencePersistedState): SyncExperiencePersistedState {
    return {
      suspended: value?.suspended === true,
      bookmarkSelected: value?.bookmarkSelected !== false,
      personalizationSelected: value?.personalizationSelected !== false,
      historySelected: value?.historySelected !== false,
      historyAccountUid: value?.historySelected === true ? (value.historyAccountUid ?? '').trim() : '',
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizeTimestamp(value: number | undefined): number {
    const numberValue = Number(value ?? 0);
    if (!Number.isFinite(numberValue) || numberValue < 0) {
      return 0;
    }
    return Math.floor(numberValue);
  }

  private cloneState(value: SyncExperiencePersistedState): SyncExperiencePersistedState {
    return {
      suspended: value.suspended,
      bookmarkSelected: value.bookmarkSelected,
      personalizationSelected: value.personalizationSelected,
      historySelected: value.historySelected,
      historyAccountUid: value.historyAccountUid,
      updatedAt: value.updatedAt
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
