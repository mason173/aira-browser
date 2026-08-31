import { BookmarkFolderBookmarkCountsResult } from '../../services/bookmarks/BookmarkTreeQueryService';
import { BookmarkManagementFeature } from '../../features/bookmarks/BookmarkManagementFeature';
import {
  BookmarkFolderCountCacheEntry,
  BookmarkFolderCountCacheRepository,
  BookmarkFolderCountCacheSnapshot
} from '../../data/bookmarks/BookmarkFolderCountCacheRepository';
import { AiraLocalBookmarkOverviewCacheRepository } from '../../data/sync/AiraLocalBookmarkOverviewCacheRepository';
import { BookmarkLocalOverviewViewModel } from './BookmarkLocalOverviewViewModel';
import { BookmarkStatsVersionSignal } from './BookmarkStatsVersionSignal';

export interface BookmarkFolderCountState {
  ready: boolean;
  counts: Map<string, number>;
  loadedFromRealData: boolean;
}

export class BookmarkFolderCountViewModel {
  private localOverviewViewModel: BookmarkLocalOverviewViewModel = new BookmarkLocalOverviewViewModel();

  createInitialState(): BookmarkFolderCountState {
    return {
      ready: false,
      counts: new Map(),
      loadedFromRealData: false
    };
  }

  buildRealState(bookmarkManagementFeature: BookmarkManagementFeature): BookmarkFolderCountState {
    const result: BookmarkFolderBookmarkCountsResult = bookmarkManagementFeature.buildFolderBookmarkCounts();
    return {
      ready: result.ready,
      counts: result.counts,
      loadedFromRealData: result.ready
    };
  }

  refreshRealState(
    currentState: BookmarkFolderCountState,
    bookmarkManagementFeature: BookmarkManagementFeature
  ): BookmarkFolderCountState {
    const nextState = this.buildRealState(bookmarkManagementFeature);
    if (nextState.ready || !currentState.ready) {
      return nextState;
    }
    return currentState;
  }

  buildCachedState(
    currentState: BookmarkFolderCountState,
    snapshot: BookmarkFolderCountCacheSnapshot
  ): BookmarkFolderCountState {
    if (currentState.loadedFromRealData) {
      return currentState;
    }
    if (!this.isSnapshotFresh(snapshot.statsVersion)) {
      return currentState;
    }
    const counts = new Map<string, number>();
    snapshot.entries.forEach((entry: BookmarkFolderCountCacheEntry) => {
      counts.set(entry.folderId, entry.count);
    });
    if (counts.size <= 0) {
      return currentState;
    }
    return {
      ready: true,
      counts: counts,
      loadedFromRealData: false
    };
  }

  saveCache(state: BookmarkFolderCountState, repository: BookmarkFolderCountCacheRepository): void {
    if (!state.loadedFromRealData || !state.ready) {
      return;
    }
    const entries: BookmarkFolderCountCacheEntry[] = [];
    state.counts.forEach((count: number, folderId: string) => {
      entries.push({
        folderId: folderId,
        count: count
      });
    });
    if (entries.length <= 0) {
      return;
    }
    repository.saveSnapshot({
      entries: entries,
      updatedAt: Date.now(),
      statsVersion: BookmarkStatsVersionSignal.readVersion()
    }).catch((_error: Error) => {
    });
  }

  refreshAndSaveCaches(
    currentState: BookmarkFolderCountState,
    bookmarkManagementFeature: BookmarkManagementFeature,
    folderCountRepository: BookmarkFolderCountCacheRepository,
    localOverviewRepository: AiraLocalBookmarkOverviewCacheRepository
  ): BookmarkFolderCountState {
    const nextState = this.refreshRealState(currentState, bookmarkManagementFeature);
    this.saveCache(nextState, folderCountRepository);
    this.localOverviewViewModel.saveOverviewCache(
      bookmarkManagementFeature.buildLocalBookmarkOverview(),
      localOverviewRepository
    );
    return nextState;
  }

  loadCache(
    currentState: BookmarkFolderCountState,
    repository: BookmarkFolderCountCacheRepository,
    apply: (state: BookmarkFolderCountState) => void
  ): void {
    const cachedSnapshot = repository.getCachedSnapshot();
    if (cachedSnapshot !== undefined) {
      apply(this.buildCachedState(currentState, cachedSnapshot));
      return;
    }
    repository.loadSnapshot()
      .then((snapshot?: BookmarkFolderCountCacheSnapshot) => {
        if (snapshot !== undefined) {
          apply(this.buildCachedState(currentState, snapshot));
        }
      })
      .catch((_error: Error) => {
      });
  }

  private isSnapshotFresh(statsVersion: number): boolean {
    const currentVersion = BookmarkStatsVersionSignal.readVersion();
    if (currentVersion <= 0) {
      return true;
    }
    const snapshotVersion = Math.max(0, Math.floor(Number(statsVersion)));
    return snapshotVersion >= currentVersion;
  }

  resolveSubtitle(state: BookmarkFolderCountState, folderId: string): string {
    if (!state.ready) {
      return '正在统计';
    }
    return `${state.counts.get(folderId) ?? 0} 个书签`;
  }

  resolveCount(state: BookmarkFolderCountState, folderId: string): number {
    if (!state.ready) {
      return -1;
    }
    return state.counts.get(folderId) ?? 0;
  }

  hasFolderContent(state: BookmarkFolderCountState, folderId: string): boolean {
    if (!state.ready) {
      return false;
    }
    return (state.counts.get(folderId) ?? 0) > 0;
  }
}
