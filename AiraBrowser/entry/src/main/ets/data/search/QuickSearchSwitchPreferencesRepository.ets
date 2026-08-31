import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { QUICK_SEARCH_SWITCHING_PREFERENCES_REVISION_KEY } from
  '../../common/constants/SearchPreferenceKeys';

const PREFERENCES_NAME: string = 'aira_browser_quick_search_switching';
const ENABLED_KEY: string = 'quick_search_switching_enabled';

export class QuickSearchSwitchPreferencesRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private enabled: boolean = true;

  async initialize(): Promise<boolean> {
    const store = await this.getStore();
    const storedEnabled = Boolean(store.getSync(ENABLED_KEY, true));
    if (!store.hasSync(ENABLED_KEY)) {
      store.putSync(ENABLED_KEY, true);
      store.flushSync();
    }
    this.enabled = storedEnabled;
    this.publishRevision();
    return this.enabled;
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  async setEnabled(enabled: boolean): Promise<boolean> {
    return this.persistEnabled(enabled);
  }

  private async persistEnabled(enabled: boolean): Promise<boolean> {
    const store = await this.getStore();
    store.putSync(ENABLED_KEY, enabled);
    store.flushSync();
    this.enabled = enabled;
    this.publishRevision();
    return this.enabled;
  }

  private publishRevision(): void {
    const nextRevision = (AppStorage.get<number>(QUICK_SEARCH_SWITCHING_PREFERENCES_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(QUICK_SEARCH_SWITCHING_PREFERENCES_REVISION_KEY, nextRevision);
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
