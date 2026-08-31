import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const BOOKMARK_FOLDER_COUNT_CACHE_STORE_NAME: string = 'aira_browser_bookmark_folder_count_cache';
const BOOKMARK_FOLDER_COUNT_CACHE_KEY: string = 'folder_bookmark_counts_v1';

export interface BookmarkFolderCountCacheEntry {
  folderId: string;
  count: number;
}

export interface BookmarkFolderCountCacheSnapshot {
  entries: BookmarkFolderCountCacheEntry[];
  updatedAt: number;
  statsVersion: number;
}

export class BookmarkFolderCountCacheRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private snapshot?: BookmarkFolderCountCacheSnapshot;

  async initialize(): Promise<BookmarkFolderCountCacheSnapshot | undefined> {
    return this.loadSnapshot();
  }

  getCachedSnapshot(): BookmarkFolderCountCacheSnapshot | undefined {
    return this.cloneSnapshot(this.snapshot);
  }

  async loadSnapshot(): Promise<BookmarkFolderCountCacheSnapshot | undefined> {
    const store = await this.getStore();
    const rawValue = store.getSync(BOOKMARK_FOLDER_COUNT_CACHE_KEY, '');
    this.snapshot = this.parseSnapshot(String(rawValue));
    return this.cloneSnapshot(this.snapshot);
  }

  async saveSnapshot(snapshot: BookmarkFolderCountCacheSnapshot): Promise<void> {
    const normalized = this.normalizeSnapshot(snapshot);
    if (normalized === undefined) {
      return;
    }
    this.snapshot = normalized;
    const store = await this.getStore();
    store.putSync(BOOKMARK_FOLDER_COUNT_CACHE_KEY, JSON.stringify(normalized));
    store.flushSync();
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        BOOKMARK_FOLDER_COUNT_CACHE_STORE_NAME
      ).then((store: preferences.Preferences) => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }

  private parseSnapshot(value: string): BookmarkFolderCountCacheSnapshot | undefined {
    try {
      const parsed = JSON.parse(value) as BookmarkFolderCountCacheSnapshot;
      return this.normalizeSnapshot(parsed);
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeSnapshot(snapshot?: BookmarkFolderCountCacheSnapshot): BookmarkFolderCountCacheSnapshot | undefined {
    if (snapshot === undefined || !Array.isArray(snapshot.entries)) {
      return undefined;
    }
    const entries: BookmarkFolderCountCacheEntry[] = [];
    const seenFolderIds = new Set<string>();
    snapshot.entries.forEach((entry: BookmarkFolderCountCacheEntry) => {
      const folderId = String(entry.folderId ?? '').trim();
      const count = Number(entry.count);
      if (folderId.length <= 0 || seenFolderIds.has(folderId) || !Number.isFinite(count) || count < 0) {
        return;
      }
      seenFolderIds.add(folderId);
      entries.push({
        folderId: folderId,
        count: Math.floor(count)
      });
    });
    if (entries.length <= 0) {
      return undefined;
    }
    const updatedAt = Number(snapshot.updatedAt);
    return {
      entries: entries,
      updatedAt: Number.isFinite(updatedAt) && updatedAt > 0 ? updatedAt : Date.now(),
      statsVersion: this.normalizeVersion(snapshot.statsVersion)
    };
  }

  private cloneSnapshot(snapshot?: BookmarkFolderCountCacheSnapshot): BookmarkFolderCountCacheSnapshot | undefined {
    if (snapshot === undefined) {
      return undefined;
    }
    return {
      entries: snapshot.entries.map((entry: BookmarkFolderCountCacheEntry): BookmarkFolderCountCacheEntry => {
        return {
          folderId: entry.folderId,
          count: entry.count
        };
      }),
      updatedAt: snapshot.updatedAt,
      statsVersion: snapshot.statsVersion
    };
  }

  private normalizeVersion(value: number | undefined): number {
    const version = Number(value ?? 0);
    return Number.isFinite(version) && version > 0 ? Math.floor(version) : 0;
  }
}
