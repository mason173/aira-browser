import { BookmarkStorageScope } from '../../common/models/BrowserModels';
import { BookmarkWorkspaceSessionCoordinator } from '../../core/bookmarks/BookmarkWorkspaceSessionCoordinator';
import { BookmarksFeature } from '../../features/bookmarks/BookmarksFeature';
import {
  BookmarkManagementBoundary,
  BookmarkManagementFeature
} from '../../features/bookmarks/BookmarkManagementFeature';
import { BookmarkMutationService } from '../../services/bookmarks/BookmarkMutationService';
import {
  sharedBookmarkRepository,
  sharedBrowserDatabase
} from '../bootstrap/BrowserAppRuntime';

interface BookmarkWorkspaceSessionEntry {
  key: string;
  coordinator: BookmarkWorkspaceSessionCoordinator;
  lastAccessAt: number;
}

/** Keeps native bookmark-tab state alive while its ArkUI presentation is unmounted. */
export class BookmarkWorkspaceSessionRuntime {
  private readonly entries: Map<string, BookmarkWorkspaceSessionEntry> =
    new Map<string, BookmarkWorkspaceSessionEntry>();
  private readonly maximumRetainedSessions: number = 8;

  acquire(
    tabId: string,
    scope: BookmarkStorageScope,
    boundary: BookmarkManagementBoundary
  ): BookmarkWorkspaceSessionCoordinator {
    const key = this.buildKey(tabId, scope);
    const existing = this.entries.get(key);
    if (existing !== undefined) {
      existing.lastAccessAt = Date.now();
      return existing.coordinator;
    }
    const bookmarksFeature = new BookmarksFeature(sharedBookmarkRepository);
    const coordinator = new BookmarkWorkspaceSessionCoordinator(
      new BookmarkManagementFeature(
        bookmarksFeature,
        new BookmarkMutationService(sharedBookmarkRepository, sharedBrowserDatabase)
      ),
      boundary
    );
    this.entries.set(key, {
      key: key,
      coordinator: coordinator,
      lastAccessAt: Date.now()
    });
    this.prune(key);
    return coordinator;
  }

  private buildKey(tabId: string, scope: BookmarkStorageScope): string {
    return `${scope}:${tabId.trim()}`;
  }

  private prune(retainedKey: string): void {
    if (this.entries.size <= this.maximumRetainedSessions) {
      return;
    }
    const candidates = Array.from(this.entries.values())
      .filter((entry: BookmarkWorkspaceSessionEntry): boolean => entry.key !== retainedKey)
      .sort((left: BookmarkWorkspaceSessionEntry, right: BookmarkWorkspaceSessionEntry): number =>
        left.lastAccessAt - right.lastAccessAt);
    while (this.entries.size > this.maximumRetainedSessions && candidates.length > 0) {
      const candidate = candidates.shift();
      if (candidate !== undefined) {
        this.entries.delete(candidate.key);
      }
    }
  }
}

export const bookmarkWorkspaceSessionRuntime: BookmarkWorkspaceSessionRuntime =
  new BookmarkWorkspaceSessionRuntime();
