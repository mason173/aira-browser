import {
  NOVEL_BOOKSHELF_SYNC_MAX_TOMBSTONES,
  NovelBookshelfSyncBook,
  NovelBookshelfSyncReadingProgress,
  NovelBookshelfSyncSnapshot,
  NovelBookshelfSyncTombstone
} from '../../common/models/NovelBookshelfSyncModels';
import { NovelBookshelfSyncSnapshotService } from './NovelBookshelfSyncSnapshotService';

export interface NovelBookshelfSyncMergeResult {
  snapshot: NovelBookshelfSyncSnapshot;
  appliedRemoteCount: number;
  shouldApplyLocal: boolean;
  shouldUpload: boolean;
}

export type NovelBookshelfSyncMergeIntent = 'ordinary' | 'provider-switch';

export class NovelBookshelfSyncMergeService {
  private readonly snapshotService: NovelBookshelfSyncSnapshotService;

  constructor(snapshotService: NovelBookshelfSyncSnapshotService = new NovelBookshelfSyncSnapshotService()) {
    this.snapshotService = snapshotService;
  }

  merge(
    localSnapshot: NovelBookshelfSyncSnapshot,
    remoteSnapshot: NovelBookshelfSyncSnapshot | null,
    intent: NovelBookshelfSyncMergeIntent = 'ordinary'
  ): NovelBookshelfSyncMergeResult {
    if (remoteSnapshot === null) {
      return {
        snapshot: localSnapshot,
        appliedRemoteCount: 0,
        shouldApplyLocal: false,
        shouldUpload: true
      };
    }
    const liveById: Record<string, NovelBookshelfSyncBook> = {};
    const earliestAddedAt: Record<string, number> = {};
    const tombstoneById: Record<string, NovelBookshelfSyncTombstone> = {};
    const readingProgressByBookId: Record<string, NovelBookshelfSyncReadingProgress> = {};
    const supersededTombstoneIds = new Set<string>();
    this.mergeBooks(liveById, earliestAddedAt, localSnapshot.books);
    this.mergeBooks(liveById, earliestAddedAt, remoteSnapshot.books);
    this.mergeTombstones(tombstoneById, localSnapshot.tombstones);
    this.mergeTombstones(tombstoneById, remoteSnapshot.tombstones);
    this.mergeReadingProgress(readingProgressByBookId, localSnapshot.readingProgress);
    this.mergeReadingProgress(readingProgressByBookId, remoteSnapshot.readingProgress);

    const books: NovelBookshelfSyncBook[] = [];
    Object.keys(liveById).forEach((id: string): void => {
      const live: NovelBookshelfSyncBook = liveById[id];
      const tombstone: NovelBookshelfSyncTombstone | undefined = tombstoneById[id];
      if (tombstone !== undefined && tombstone.deletedAt >= live.updatedAt && intent !== 'provider-switch') {
        return;
      }
      if (tombstone !== undefined) {
        supersededTombstoneIds.add(id);
      }
      books.push({
        id: live.id,
        detailUrl: live.detailUrl,
        title: live.title,
        author: live.author,
        coverUrl: live.coverUrl,
        addedAt: earliestAddedAt[id],
        updatedAt: live.updatedAt
      });
    });
    const tombstones: NovelBookshelfSyncTombstone[] = Object.keys(tombstoneById)
      .filter((id: string): boolean => !supersededTombstoneIds.has(id))
      .map((id: string): NovelBookshelfSyncTombstone => tombstoneById[id])
      .sort((left: NovelBookshelfSyncTombstone, right: NovelBookshelfSyncTombstone): number => {
        if (left.deletedAt !== right.deletedAt) {
          return right.deletedAt - left.deletedAt;
        }
        return left.id.localeCompare(right.id);
      })
      .slice(0, NOVEL_BOOKSHELF_SYNC_MAX_TOMBSTONES);
    const liveBookIds = new Set<string>(books.map((book: NovelBookshelfSyncBook): string => book.id));
    const readingProgress: NovelBookshelfSyncReadingProgress[] = Object.keys(readingProgressByBookId)
      .filter((bookId: string): boolean => liveBookIds.has(bookId))
      .map((bookId: string): NovelBookshelfSyncReadingProgress => readingProgressByBookId[bookId]);
    const snapshot: NovelBookshelfSyncSnapshot = this.snapshotService.buildSnapshot(
      localSnapshot.meta.deviceId,
      books,
      readingProgress,
      tombstones
    );
    const shouldApplyLocal: boolean = !this.snapshotService.sameContent(localSnapshot, snapshot);
    const shouldUpload: boolean = !this.snapshotService.sameContent(remoteSnapshot, snapshot);
    return {
      snapshot: snapshot,
      appliedRemoteCount: shouldApplyLocal ? this.countLocalDifferences(localSnapshot, snapshot) : 0,
      shouldApplyLocal: shouldApplyLocal,
      shouldUpload: shouldUpload
    };
  }

  private mergeBooks(
    liveById: Record<string, NovelBookshelfSyncBook>,
    earliestAddedAt: Record<string, number>,
    values: NovelBookshelfSyncBook[]
  ): void {
    values.forEach((value: NovelBookshelfSyncBook): void => {
      const current: NovelBookshelfSyncBook | undefined = liveById[value.id];
      earliestAddedAt[value.id] = current === undefined
        ? value.addedAt
        : Math.min(earliestAddedAt[value.id], value.addedAt);
      if (current === undefined || this.compareLive(value, current) > 0) {
        liveById[value.id] = value;
      }
    });
  }

  private mergeTombstones(
    tombstoneById: Record<string, NovelBookshelfSyncTombstone>,
    values: NovelBookshelfSyncTombstone[]
  ): void {
    values.forEach((value: NovelBookshelfSyncTombstone): void => {
      const current: NovelBookshelfSyncTombstone | undefined = tombstoneById[value.id];
      if (current === undefined || current.deletedAt < value.deletedAt) {
        tombstoneById[value.id] = value;
      }
    });
  }

  private mergeReadingProgress(
    progressByBookId: Record<string, NovelBookshelfSyncReadingProgress>,
    values: NovelBookshelfSyncReadingProgress[]
  ): void {
    values.forEach((value: NovelBookshelfSyncReadingProgress): void => {
      const current: NovelBookshelfSyncReadingProgress | undefined = progressByBookId[value.bookId];
      if (current === undefined || this.compareReadingProgress(value, current) > 0) {
        progressByBookId[value.bookId] = value;
      }
    });
  }

  private compareLive(left: NovelBookshelfSyncBook, right: NovelBookshelfSyncBook): number {
    if (left.updatedAt !== right.updatedAt) {
      return left.updatedAt - right.updatedAt;
    }
    return JSON.stringify(left).localeCompare(JSON.stringify(right));
  }

  private compareReadingProgress(
    left: NovelBookshelfSyncReadingProgress,
    right: NovelBookshelfSyncReadingProgress
  ): number {
    if (left.updatedAt !== right.updatedAt) {
      return left.updatedAt - right.updatedAt;
    }
    return JSON.stringify(left).localeCompare(JSON.stringify(right));
  }

  private countLocalDifferences(
    localSnapshot: NovelBookshelfSyncSnapshot,
    mergedSnapshot: NovelBookshelfSyncSnapshot
  ): number {
    const localById: Record<string, string> = {};
    localSnapshot.books.forEach((book: NovelBookshelfSyncBook): void => {
      localById[`book:${book.id}`] = JSON.stringify(book);
    });
    localSnapshot.readingProgress.forEach((value: NovelBookshelfSyncReadingProgress): void => {
      localById[`progress:${value.bookId}`] = JSON.stringify(value);
    });
    localSnapshot.tombstones.forEach((value: NovelBookshelfSyncTombstone): void => {
      localById[`tombstone:${value.id}`] = JSON.stringify(value);
    });
    const mergedById: Record<string, string> = {};
    mergedSnapshot.books.forEach((book: NovelBookshelfSyncBook): void => {
      mergedById[`book:${book.id}`] = JSON.stringify(book);
    });
    mergedSnapshot.readingProgress.forEach((value: NovelBookshelfSyncReadingProgress): void => {
      mergedById[`progress:${value.bookId}`] = JSON.stringify(value);
    });
    mergedSnapshot.tombstones.forEach((value: NovelBookshelfSyncTombstone): void => {
      mergedById[`tombstone:${value.id}`] = JSON.stringify(value);
    });
    const keys = new Set<string>(Object.keys(localById).concat(Object.keys(mergedById)));
    let count: number = 0;
    keys.forEach((key: string): void => {
      if (localById[key] !== mergedById[key]) {
        count += 1;
      }
    });
    return count;
  }
}
