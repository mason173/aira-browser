import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { BookmarkStorageScope } from '../../common/models/BrowserModels';
import {
  BOOKMARK_SORT_PREFERENCES_REVISION_KEY,
  BookmarkSortMode,
  normalizeBookmarkSortMode
} from '../../common/models/BookmarkSortModels';

/** Device-local presentation preferences, separate from bookmark and personalization sync. */
export class BookmarkSortPreferencesRepository {
  private store?: preferences.Preferences;

  getMode(scope: BookmarkStorageScope): BookmarkSortMode {
    try {
      return normalizeBookmarkSortMode(String(this.getStore().getSync(scope, 'manual')));
    } catch (_error) {
      return 'manual';
    }
  }

  setMode(scope: BookmarkStorageScope, mode: BookmarkSortMode): void {
    const store = this.getStore();
    const previous = store.getSync(scope, 'manual');
    store.putSync(scope, mode);
    try {
      store.flushSync();
    } catch (error) {
      store.putSync(scope, previous);
      throw error as Error;
    }
    const revision = (AppStorage.get<number>(BOOKMARK_SORT_PREFERENCES_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(BOOKMARK_SORT_PREFERENCES_REVISION_KEY, revision);
  }

  private getStore(): preferences.Preferences {
    if (this.store === undefined) {
      this.store = preferences.getPreferencesSync(AppRuntimeContext.getApplicationContext(), {
        name: 'aira_bookmark_sort_preferences'
      });
    }
    return this.store;
  }
}

export const sharedBookmarkSortPreferencesRepository: BookmarkSortPreferencesRepository =
  new BookmarkSortPreferencesRepository();
