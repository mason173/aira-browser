export const NOVEL_BOOKSHELF_SYNC_SCHEMA_VERSION: number = 2;
export const NOVEL_BOOKSHELF_SYNC_MAX_BOOKS: number = 500;
export const NOVEL_BOOKSHELF_SYNC_MAX_READING_PROGRESS: number = 200;
export const NOVEL_BOOKSHELF_SYNC_MAX_TOMBSTONES: number = 2000;
export const NOVEL_BOOKSHELF_SYNC_MAX_JSON_BYTES: number = 1024 * 1024;

export interface NovelBookshelfSyncBook {
  id: string;
  detailUrl: string;
  title: string;
  author: string;
  coverUrl: string;
  addedAt: number;
  updatedAt: number;
}

export interface NovelBookshelfSyncTombstone {
  id: string;
  deletedAt: number;
}

export interface NovelBookshelfSyncReadingProgress {
  bookId: string;
  sessionBookId: string;
  chapterId: string;
  chapterUrl: string;
  chapterTitle: string;
  characterOffset: number;
  updatedAt: number;
}

export interface NovelBookshelfSyncSnapshotMeta {
  version: number;
  deviceId: string;
  generatedAt: string;
}

export interface NovelBookshelfSyncSnapshot {
  meta: NovelBookshelfSyncSnapshotMeta;
  books: NovelBookshelfSyncBook[];
  readingProgress: NovelBookshelfSyncReadingProgress[];
  tombstones: NovelBookshelfSyncTombstone[];
  checksum: string;
}

export interface NovelBookshelfSyncRemoteState {
  snapshot: NovelBookshelfSyncSnapshot | null;
  revision: string;
  headSnapshots?: NovelBookshelfSyncSnapshot[];
}

export interface NovelBookshelfSyncWriteResult {
  revision: string;
}

export interface NovelBookshelfSyncRemoteStore {
  readState(): Promise<NovelBookshelfSyncRemoteState>;
  writeSnapshot(
    deviceId: string,
    snapshot: NovelBookshelfSyncSnapshot,
    expectedRevision: string
  ): Promise<NovelBookshelfSyncWriteResult>;
}

export interface NovelBookshelfSyncRunResult {
  appliedRemoteCount: number;
  uploaded: boolean;
  snapshot: NovelBookshelfSyncSnapshot;
  revision: string;
}

export interface NovelBookshelfSyncSelectionState {
  initialized: boolean;
  enabled: boolean;
  updatedAt: number;
}
