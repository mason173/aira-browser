import { AiraBookmarkOverview } from '../../common/models/AiraSyncModels';
import {
  AiraLocalBookmarkOverviewCacheRepository,
  AiraLocalBookmarkOverviewCacheSnapshot
} from '../../data/sync/AiraLocalBookmarkOverviewCacheRepository';
import { BookmarkStatsVersionSignal } from './BookmarkStatsVersionSignal';

export interface BookmarkLocalOverviewCounts {
  bookmarkFolderCount: number;
  bookmarkItemCount: number;
}

type BookmarkLocalOverviewLoader = () => Promise<AiraBookmarkOverview>;

export class BookmarkLocalOverviewViewModel {
  private cacheVerifiedThisSession: boolean = false;
  private currentCountsPromise?: Promise<BookmarkLocalOverviewCounts>;

  formatSummary(folderCount: number, itemCount: number): string {
    return `${Math.max(0, Math.floor(folderCount))} 个文件夹，${Math.max(0, Math.floor(itemCount))} 个书签`;
  }

  formatSnapshot(snapshot: AiraLocalBookmarkOverviewCacheSnapshot): string {
    return this.formatSummary(snapshot.bookmarkFolderCount, snapshot.bookmarkItemCount);
  }

  async loadCurrentCounts(
    repository: AiraLocalBookmarkOverviewCacheRepository,
    loadFreshOverview: BookmarkLocalOverviewLoader
  ): Promise<BookmarkLocalOverviewCounts> {
    if (this.currentCountsPromise !== undefined) {
      return this.currentCountsPromise;
    }
    this.currentCountsPromise = this.loadCurrentCountsInternal(repository, loadFreshOverview)
      .finally((): void => {
        this.currentCountsPromise = undefined;
      });
    return this.currentCountsPromise;
  }

  private async loadCurrentCountsInternal(
    repository: AiraLocalBookmarkOverviewCacheRepository,
    loadFreshOverview: BookmarkLocalOverviewLoader
  ): Promise<BookmarkLocalOverviewCounts> {
    const currentStatsVersion = BookmarkStatsVersionSignal.readVersion();
    let snapshot = repository.getCachedSnapshot();
    if (snapshot === undefined) {
      snapshot = await repository.loadSnapshot()
        .catch((_error: Error): AiraLocalBookmarkOverviewCacheSnapshot | undefined => undefined);
    }
    if (snapshot !== undefined && this.isSnapshotFresh(snapshot, currentStatsVersion)) {
      this.cacheVerifiedThisSession = true;
      return this.buildCounts(snapshot.bookmarkFolderCount, snapshot.bookmarkItemCount);
    }
    const overview = await loadFreshOverview();
    const counts = this.buildCounts(overview.bookmarkFolderCount, overview.bookmarkItemCount);
    try {
      await repository.saveSnapshot(this.buildCacheSnapshot(overview));
      this.cacheVerifiedThisSession = true;
    } catch (_error) {
      this.cacheVerifiedThisSession = false;
    }
    return counts;
  }

  saveOverviewCache(
    overview: AiraBookmarkOverview,
    repository: AiraLocalBookmarkOverviewCacheRepository
  ): void {
    repository.saveSnapshot(this.buildCacheSnapshot(overview))
      .then((): void => {
        this.cacheVerifiedThisSession = true;
      })
      .catch((_error: Error): void => {
      });
  }

  private isSnapshotFresh(snapshot: AiraLocalBookmarkOverviewCacheSnapshot, currentStatsVersion: number): boolean {
    if (currentStatsVersion <= 0) {
      return this.cacheVerifiedThisSession;
    }
    return snapshot.statsVersion >= currentStatsVersion;
  }

  private buildCounts(folderCount: number, itemCount: number): BookmarkLocalOverviewCounts {
    return {
      bookmarkFolderCount: Math.max(0, Math.floor(folderCount)),
      bookmarkItemCount: Math.max(0, Math.floor(itemCount))
    };
  }

  private buildCacheSnapshot(overview: AiraBookmarkOverview): AiraLocalBookmarkOverviewCacheSnapshot {
    return {
      bookmarkFolderCount: overview.bookmarkFolderCount,
      bookmarkItemCount: overview.bookmarkItemCount,
      updatedAt: Date.now(),
      statsVersion: BookmarkStatsVersionSignal.readVersion()
    };
  }
}
