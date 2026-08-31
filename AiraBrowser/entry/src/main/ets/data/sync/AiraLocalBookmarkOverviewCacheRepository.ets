import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const AIRA_LOCAL_BOOKMARK_OVERVIEW_CACHE_STORE_NAME: string = 'aira_local_bookmark_overview_cache';
const AIRA_LOCAL_BOOKMARK_OVERVIEW_CACHE_KEY: string = 'overview_v1';
const AIRA_LOCAL_BOOKMARK_ROOT_OVERVIEW_CACHE_KEY: string = 'root_overview_v1';

export interface AiraLocalBookmarkOverviewCacheSnapshot {
  bookmarkFolderCount: number;
  bookmarkItemCount: number;
  updatedAt: number;
  statsVersion: number;
}

export interface AiraLocalBookmarkRootOverviewCacheEntry {
  id: string;
  title: string;
  bookmarkFolderCount: number;
  bookmarkItemCount: number;
}

export interface AiraLocalBookmarkRootOverviewCacheSnapshot {
  entries: AiraLocalBookmarkRootOverviewCacheEntry[];
  updatedAt: number;
  statsVersion: number;
}

export class AiraLocalBookmarkOverviewCacheRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private snapshot?: AiraLocalBookmarkOverviewCacheSnapshot;
  private rootSnapshot?: AiraLocalBookmarkRootOverviewCacheSnapshot;

  async initialize(): Promise<AiraLocalBookmarkOverviewCacheSnapshot | undefined> {
    const snapshot = await this.loadSnapshot();
    await this.loadRootSnapshot();
    return snapshot;
  }

  getCachedSnapshot(): AiraLocalBookmarkOverviewCacheSnapshot | undefined {
    return this.cloneSnapshot(this.snapshot);
  }

  getCachedRootSnapshot(): AiraLocalBookmarkRootOverviewCacheSnapshot | undefined {
    return this.cloneRootSnapshot(this.rootSnapshot);
  }

  async loadSnapshot(): Promise<AiraLocalBookmarkOverviewCacheSnapshot | undefined> {
    const store = await this.getStore();
    const rawValue = store.getSync(AIRA_LOCAL_BOOKMARK_OVERVIEW_CACHE_KEY, '');
    this.snapshot = this.parseSnapshot(String(rawValue));
    return this.cloneSnapshot(this.snapshot);
  }

  async loadRootSnapshot(): Promise<AiraLocalBookmarkRootOverviewCacheSnapshot | undefined> {
    const store = await this.getStore();
    const rawValue = store.getSync(AIRA_LOCAL_BOOKMARK_ROOT_OVERVIEW_CACHE_KEY, '');
    this.rootSnapshot = this.parseRootSnapshot(String(rawValue));
    return this.cloneRootSnapshot(this.rootSnapshot);
  }

  async saveSnapshot(snapshot: AiraLocalBookmarkOverviewCacheSnapshot): Promise<void> {
    const normalized = this.normalizeSnapshot(snapshot);
    if (normalized === undefined) {
      return;
    }
    this.snapshot = normalized;
    const store = await this.getStore();
    store.putSync(AIRA_LOCAL_BOOKMARK_OVERVIEW_CACHE_KEY, JSON.stringify(normalized));
    await store.flush();
  }

  async saveRootSnapshot(snapshot: AiraLocalBookmarkRootOverviewCacheSnapshot): Promise<void> {
    const normalized = this.normalizeRootSnapshot(snapshot);
    if (normalized === undefined) {
      return;
    }
    this.rootSnapshot = normalized;
    const store = await this.getStore();
    store.putSync(AIRA_LOCAL_BOOKMARK_ROOT_OVERVIEW_CACHE_KEY, JSON.stringify(normalized));
    await store.flush();
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        AIRA_LOCAL_BOOKMARK_OVERVIEW_CACHE_STORE_NAME
      ).then((store: preferences.Preferences) => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }

  private parseSnapshot(value: string): AiraLocalBookmarkOverviewCacheSnapshot | undefined {
    try {
      const parsed = JSON.parse(value) as AiraLocalBookmarkOverviewCacheSnapshot;
      return this.normalizeSnapshot(parsed);
    } catch (_error) {
      return undefined;
    }
  }

  private parseRootSnapshot(value: string): AiraLocalBookmarkRootOverviewCacheSnapshot | undefined {
    try {
      const parsed = JSON.parse(value) as AiraLocalBookmarkRootOverviewCacheSnapshot;
      return this.normalizeRootSnapshot(parsed);
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeSnapshot(
    snapshot?: AiraLocalBookmarkOverviewCacheSnapshot
  ): AiraLocalBookmarkOverviewCacheSnapshot | undefined {
    if (snapshot === undefined) {
      return undefined;
    }
    const folderCount = Number(snapshot.bookmarkFolderCount);
    const itemCount = Number(snapshot.bookmarkItemCount);
    const updatedAt = Number(snapshot.updatedAt);
    if (!Number.isFinite(folderCount) || folderCount < 0 || !Number.isFinite(itemCount) || itemCount < 0) {
      return undefined;
    }
    return {
      bookmarkFolderCount: Math.floor(folderCount),
      bookmarkItemCount: Math.floor(itemCount),
      updatedAt: Number.isFinite(updatedAt) && updatedAt > 0 ? Math.floor(updatedAt) : Date.now(),
      statsVersion: this.normalizeVersion(snapshot.statsVersion)
    };
  }

  private normalizeRootSnapshot(
    snapshot?: AiraLocalBookmarkRootOverviewCacheSnapshot
  ): AiraLocalBookmarkRootOverviewCacheSnapshot | undefined {
    if (snapshot === undefined || !Array.isArray(snapshot.entries)) {
      return undefined;
    }
    const entries: AiraLocalBookmarkRootOverviewCacheEntry[] = [];
    snapshot.entries.forEach((entry: AiraLocalBookmarkRootOverviewCacheEntry) => {
      const id = String(entry.id ?? '').trim();
      if (id.length <= 0) {
        return;
      }
      const folderCount = Number(entry.bookmarkFolderCount);
      const itemCount = Number(entry.bookmarkItemCount);
      if (!Number.isFinite(folderCount) || folderCount < 0 || !Number.isFinite(itemCount) || itemCount < 0) {
        return;
      }
      entries.push({
        id: id,
        title: String(entry.title ?? '').trim(),
        bookmarkFolderCount: Math.floor(folderCount),
        bookmarkItemCount: Math.floor(itemCount)
      });
    });
    const updatedAt = Number(snapshot.updatedAt);
    return {
      entries: entries,
      updatedAt: Number.isFinite(updatedAt) && updatedAt > 0 ? Math.floor(updatedAt) : Date.now(),
      statsVersion: this.normalizeVersion(snapshot.statsVersion)
    };
  }

  private cloneSnapshot(
    snapshot?: AiraLocalBookmarkOverviewCacheSnapshot
  ): AiraLocalBookmarkOverviewCacheSnapshot | undefined {
    if (snapshot === undefined) {
      return undefined;
    }
    return {
      bookmarkFolderCount: snapshot.bookmarkFolderCount,
      bookmarkItemCount: snapshot.bookmarkItemCount,
      updatedAt: snapshot.updatedAt,
      statsVersion: snapshot.statsVersion
    };
  }

  private cloneRootSnapshot(
    snapshot?: AiraLocalBookmarkRootOverviewCacheSnapshot
  ): AiraLocalBookmarkRootOverviewCacheSnapshot | undefined {
    if (snapshot === undefined) {
      return undefined;
    }
    const entries = snapshot.entries.map((entry: AiraLocalBookmarkRootOverviewCacheEntry) => {
      const cloned: AiraLocalBookmarkRootOverviewCacheEntry = {
        id: entry.id,
        title: entry.title,
        bookmarkFolderCount: entry.bookmarkFolderCount,
        bookmarkItemCount: entry.bookmarkItemCount
      };
      return cloned;
    });
    return {
      entries: entries,
      updatedAt: snapshot.updatedAt,
      statsVersion: snapshot.statsVersion
    };
  }

  private normalizeVersion(value: number | undefined): number {
    const version = Number(value ?? 0);
    return Number.isFinite(version) && version > 0 ? Math.floor(version) : 0;
  }
}
