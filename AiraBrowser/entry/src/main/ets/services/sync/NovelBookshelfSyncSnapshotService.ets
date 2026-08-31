import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import {
  NOVEL_BOOKSHELF_SYNC_MAX_BOOKS,
  NOVEL_BOOKSHELF_SYNC_MAX_JSON_BYTES,
  NOVEL_BOOKSHELF_SYNC_MAX_READING_PROGRESS,
  NOVEL_BOOKSHELF_SYNC_MAX_TOMBSTONES,
  NOVEL_BOOKSHELF_SYNC_SCHEMA_VERSION,
  NovelBookshelfSyncBook,
  NovelBookshelfSyncReadingProgress,
  NovelBookshelfSyncSnapshot,
  NovelBookshelfSyncTombstone
} from '../../common/models/NovelBookshelfSyncModels';
import {
  isValidNovelHttpUrl,
  normalizeNovelDetailUrl,
  NovelBookshelfBook,
  NovelBookshelfSyncLocalState,
  NovelBookshelfTombstone
} from '../../features/novel/NovelLibraryModels';
import { NovelReadingCheckpointRecord } from '../../features/novel/NovelReaderModels';

const NOVEL_BOOKSHELF_SYNC_MAX_TITLE_LENGTH: number = 240;
const NOVEL_BOOKSHELF_SYNC_MAX_URL_LENGTH: number = 4096;
const NOVEL_BOOKSHELF_SYNC_MAX_COVER_URL_LENGTH: number = 1000;
const NOVEL_BOOKSHELF_SYNC_MAX_ID_LENGTH: number = 512;
const NOVEL_BOOKSHELF_SYNC_MAX_CHARACTER_OFFSET: number = 2147483647;

export class NovelBookshelfSyncSnapshotService {
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');

  buildLocalSnapshot(
    deviceId: string,
    state: NovelBookshelfSyncLocalState,
    checkpoints: NovelReadingCheckpointRecord[],
    generatedAt: number = Date.now()
  ): NovelBookshelfSyncSnapshot {
    const books: NovelBookshelfSyncBook[] = state.books.map(
      (book: NovelBookshelfBook): NovelBookshelfSyncBook => {
        const coverUrl: string = book.coverUrl.trim();
        return {
          id: normalizeNovelDetailUrl(book.detailUrl),
          detailUrl: book.detailUrl.trim(),
          title: book.title.trim(),
          author: book.author.trim(),
          coverUrl: isValidNovelHttpUrl(coverUrl) ? coverUrl : '',
          addedAt: Math.floor(book.addedAt),
          updatedAt: Math.floor(book.updatedAt)
        };
      }
    );
    const tombstones: NovelBookshelfSyncTombstone[] = state.tombstones.map(
      (value: NovelBookshelfTombstone): NovelBookshelfSyncTombstone => ({
        id: normalizeNovelDetailUrl(value.id),
        deletedAt: Math.floor(value.deletedAt)
      })
    );
    const liveBookIds = new Set<string>(books.map((book: NovelBookshelfSyncBook): string => book.id));
    const readingProgress: NovelBookshelfSyncReadingProgress[] = checkpoints
      .filter((checkpoint: NovelReadingCheckpointRecord): boolean =>
        liveBookIds.has(normalizeNovelDetailUrl(checkpoint.bookDetailUrl)))
      .map((checkpoint: NovelReadingCheckpointRecord): NovelBookshelfSyncReadingProgress => ({
        bookId: normalizeNovelDetailUrl(checkpoint.bookDetailUrl),
        sessionBookId: checkpoint.bookId,
        chapterId: checkpoint.chapterId,
        chapterUrl: checkpoint.canonicalUrl,
        chapterTitle: checkpoint.chapterTitle,
        characterOffset: checkpoint.characterOffset,
        updatedAt: checkpoint.updatedAt
      }));
    return this.buildSnapshot(deviceId, books, readingProgress, tombstones, generatedAt);
  }

  buildSnapshot(
    deviceId: string,
    books: NovelBookshelfSyncBook[],
    readingProgress: NovelBookshelfSyncReadingProgress[],
    tombstones: NovelBookshelfSyncTombstone[],
    generatedAt: number = Date.now()
  ): NovelBookshelfSyncSnapshot {
    const canonicalBooks: NovelBookshelfSyncBook[] = this.canonicalBooks(books);
    const canonicalReadingProgress: NovelBookshelfSyncReadingProgress[] =
      this.canonicalReadingProgress(readingProgress, canonicalBooks);
    const canonicalTombstones: NovelBookshelfSyncTombstone[] = this.canonicalTombstones(tombstones);
    if (canonicalBooks.length !== books.length) {
      throw new Error('本机小说书架包含无法同步的书籍地址或标题。');
    }
    const snapshot: NovelBookshelfSyncSnapshot = {
      meta: {
        version: NOVEL_BOOKSHELF_SYNC_SCHEMA_VERSION,
        deviceId: deviceId.trim().length > 0 ? deviceId.trim() : 'aira-novel-bookshelf-device',
        generatedAt: new Date(generatedAt).toISOString()
      },
      books: canonicalBooks,
      readingProgress: canonicalReadingProgress,
      tombstones: canonicalTombstones,
      checksum: this.buildChecksum(canonicalBooks, canonicalReadingProgress, canonicalTombstones)
    };
    return this.validate(snapshot, '本机');
  }

  validate(snapshot: NovelBookshelfSyncSnapshot, sourceLabel: string): NovelBookshelfSyncSnapshot {
    if (snapshot === undefined || snapshot === null || typeof snapshot !== 'object' ||
      snapshot.meta === undefined || snapshot.meta === null ||
      snapshot.meta.version !== NOVEL_BOOKSHELF_SYNC_SCHEMA_VERSION ||
      !this.isNonEmptyString(snapshot.meta.deviceId) || !this.isNonEmptyString(snapshot.meta.generatedAt) ||
      !Array.isArray(snapshot.books) || !Array.isArray(snapshot.readingProgress) ||
      !Array.isArray(snapshot.tombstones) ||
      snapshot.books.length > NOVEL_BOOKSHELF_SYNC_MAX_BOOKS ||
      snapshot.readingProgress.length > NOVEL_BOOKSHELF_SYNC_MAX_READING_PROGRESS ||
      snapshot.tombstones.length > NOVEL_BOOKSHELF_SYNC_MAX_TOMBSTONES ||
      !this.isNonEmptyString(snapshot.checksum)) {
      throw new Error(`${sourceLabel}小说书架同步快照格式无效。`);
    }
    const canonicalBooks: NovelBookshelfSyncBook[] = this.canonicalBooks(snapshot.books);
    const canonicalReadingProgress: NovelBookshelfSyncReadingProgress[] =
      this.canonicalReadingProgress(snapshot.readingProgress, canonicalBooks);
    const canonicalTombstones: NovelBookshelfSyncTombstone[] = this.canonicalTombstones(snapshot.tombstones);
    if (canonicalBooks.length !== snapshot.books.length ||
      canonicalReadingProgress.length !== snapshot.readingProgress.length ||
      canonicalTombstones.length !== snapshot.tombstones.length ||
      JSON.stringify(canonicalBooks) !== JSON.stringify(snapshot.books) ||
      JSON.stringify(canonicalReadingProgress) !== JSON.stringify(snapshot.readingProgress) ||
      JSON.stringify(canonicalTombstones) !== JSON.stringify(snapshot.tombstones) ||
      snapshot.checksum !== this.buildChecksum(canonicalBooks, canonicalReadingProgress, canonicalTombstones)) {
      throw new Error(`${sourceLabel}小说书架同步快照内容无效。`);
    }
    if (this.encoder.encodeInto(JSON.stringify(snapshot)).byteLength > NOVEL_BOOKSHELF_SYNC_MAX_JSON_BYTES) {
      throw new Error(`${sourceLabel}小说书架同步数据超过大小上限。`);
    }
    return snapshot;
  }

  sameContent(left: NovelBookshelfSyncSnapshot, right: NovelBookshelfSyncSnapshot): boolean {
    return left.checksum === right.checksum && JSON.stringify(left.books) === JSON.stringify(right.books) &&
      JSON.stringify(left.readingProgress) === JSON.stringify(right.readingProgress) &&
      JSON.stringify(left.tombstones) === JSON.stringify(right.tombstones);
  }

  toLocalBooks(snapshot: NovelBookshelfSyncSnapshot): NovelBookshelfBook[] {
    return snapshot.books.map((book: NovelBookshelfSyncBook): NovelBookshelfBook => ({
      id: book.id,
      detailUrl: book.detailUrl,
      title: book.title,
      author: book.author,
      coverUrl: book.coverUrl,
      sourceHost: '',
      category: '',
      latestChapter: '',
      synopsis: '',
      addedAt: book.addedAt,
      updatedAt: book.updatedAt
    }));
  }

  toLocalTombstones(snapshot: NovelBookshelfSyncSnapshot): NovelBookshelfTombstone[] {
    return snapshot.tombstones.map((value: NovelBookshelfSyncTombstone): NovelBookshelfTombstone => ({
      id: value.id,
      deletedAt: value.deletedAt
    }));
  }

  toLocalReadingCheckpoints(snapshot: NovelBookshelfSyncSnapshot): NovelReadingCheckpointRecord[] {
    return snapshot.readingProgress.map(
      (value: NovelBookshelfSyncReadingProgress): NovelReadingCheckpointRecord => ({
        bookId: value.sessionBookId,
        bookDetailUrl: value.bookId,
        chapterId: value.chapterId,
        canonicalUrl: value.chapterUrl,
        chapterTitle: value.chapterTitle,
        characterOffset: value.characterOffset,
        updatedAt: value.updatedAt
      })
    );
  }

  private canonicalBooks(values: NovelBookshelfSyncBook[]): NovelBookshelfSyncBook[] {
    const result: NovelBookshelfSyncBook[] = [];
    const seen = new Set<string>();
    values.forEach((value: NovelBookshelfSyncBook): void => {
      const detailUrl: string = String(value?.detailUrl ?? '').trim();
      const id: string = normalizeNovelDetailUrl(detailUrl);
      const title: string = String(value?.title ?? '').trim();
      const author: string = String(value?.author ?? '').trim();
      const coverUrl: string = String(value?.coverUrl ?? '').trim();
      const addedAt: number = this.normalizePositiveInteger(value?.addedAt);
      const updatedAt: number = this.normalizePositiveInteger(value?.updatedAt);
      if (id.length === 0 || id !== String(value?.id ?? '') || seen.has(id) ||
        !isValidNovelHttpUrl(detailUrl) || detailUrl.length > NOVEL_BOOKSHELF_SYNC_MAX_URL_LENGTH ||
        title.length === 0 || title.length > NOVEL_BOOKSHELF_SYNC_MAX_TITLE_LENGTH ||
        author.length > NOVEL_BOOKSHELF_SYNC_MAX_TITLE_LENGTH ||
        coverUrl.length > NOVEL_BOOKSHELF_SYNC_MAX_COVER_URL_LENGTH ||
        (coverUrl.length > 0 && !isValidNovelHttpUrl(coverUrl)) || addedAt <= 0 || updatedAt <= 0) {
        return;
      }
      seen.add(id);
      result.push({
        id: id,
        detailUrl: detailUrl,
        title: title,
        author: author,
        coverUrl: coverUrl,
        addedAt: addedAt,
        updatedAt: updatedAt
      });
    });
    return result.sort((left: NovelBookshelfSyncBook, right: NovelBookshelfSyncBook): number =>
      left.id.localeCompare(right.id));
  }

  private canonicalTombstones(values: NovelBookshelfSyncTombstone[]): NovelBookshelfSyncTombstone[] {
    const latestById: Record<string, NovelBookshelfSyncTombstone> = {};
    values.forEach((value: NovelBookshelfSyncTombstone): void => {
      const id: string = normalizeNovelDetailUrl(String(value?.id ?? ''));
      const deletedAt: number = this.normalizePositiveInteger(value?.deletedAt);
      if (id.length === 0 || id !== String(value?.id ?? '') || !isValidNovelHttpUrl(id) || deletedAt <= 0) {
        return;
      }
      const previous: NovelBookshelfSyncTombstone | undefined = latestById[id];
      if (previous === undefined || previous.deletedAt < deletedAt) {
        latestById[id] = { id: id, deletedAt: deletedAt };
      }
    });
    return Object.keys(latestById)
      .map((id: string): NovelBookshelfSyncTombstone => latestById[id])
      .sort((left: NovelBookshelfSyncTombstone, right: NovelBookshelfSyncTombstone): number => {
        if (left.deletedAt !== right.deletedAt) {
          return right.deletedAt - left.deletedAt;
        }
        return left.id.localeCompare(right.id);
      })
      .slice(0, NOVEL_BOOKSHELF_SYNC_MAX_TOMBSTONES)
      .sort((left: NovelBookshelfSyncTombstone, right: NovelBookshelfSyncTombstone): number =>
        left.id.localeCompare(right.id));
  }

  private canonicalReadingProgress(
    values: NovelBookshelfSyncReadingProgress[],
    books: NovelBookshelfSyncBook[]
  ): NovelBookshelfSyncReadingProgress[] {
    const liveBookIds = new Set<string>(books.map((book: NovelBookshelfSyncBook): string => book.id));
    const result: NovelBookshelfSyncReadingProgress[] = [];
    const seen = new Set<string>();
    values.forEach((value: NovelBookshelfSyncReadingProgress): void => {
      const bookId: string = normalizeNovelDetailUrl(String(value?.bookId ?? ''));
      const sessionBookId: string = String(value?.sessionBookId ?? '').trim();
      const chapterId: string = String(value?.chapterId ?? '').trim();
      const chapterUrl: string = String(value?.chapterUrl ?? '').trim();
      const chapterTitle: string = String(value?.chapterTitle ?? '').trim();
      const characterOffset: number = this.normalizeNonNegativeInteger(value?.characterOffset);
      const updatedAt: number = this.normalizePositiveInteger(value?.updatedAt);
      if (bookId.length === 0 || bookId !== String(value?.bookId ?? '') || seen.has(bookId) ||
        !liveBookIds.has(bookId) || !isValidNovelHttpUrl(bookId) ||
        sessionBookId.length === 0 || sessionBookId.length > NOVEL_BOOKSHELF_SYNC_MAX_ID_LENGTH ||
        chapterId.length === 0 || chapterId.length > NOVEL_BOOKSHELF_SYNC_MAX_ID_LENGTH ||
        !isValidNovelHttpUrl(chapterUrl) || chapterUrl.length > NOVEL_BOOKSHELF_SYNC_MAX_URL_LENGTH ||
        chapterTitle.length > NOVEL_BOOKSHELF_SYNC_MAX_TITLE_LENGTH ||
        characterOffset < 0 || characterOffset > NOVEL_BOOKSHELF_SYNC_MAX_CHARACTER_OFFSET || updatedAt <= 0) {
        return;
      }
      seen.add(bookId);
      result.push({
        bookId: bookId,
        sessionBookId: sessionBookId,
        chapterId: chapterId,
        chapterUrl: chapterUrl,
        chapterTitle: chapterTitle,
        characterOffset: characterOffset,
        updatedAt: updatedAt
      });
    });
    return result.sort((left: NovelBookshelfSyncReadingProgress, right: NovelBookshelfSyncReadingProgress): number =>
      left.bookId.localeCompare(right.bookId));
  }

  private buildChecksum(
    books: NovelBookshelfSyncBook[],
    readingProgress: NovelBookshelfSyncReadingProgress[],
    tombstones: NovelBookshelfSyncTombstone[]
  ): string {
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({
      data: this.encoder.encodeInto(JSON.stringify({
        books: books,
        readingProgress: readingProgress,
        tombstones: tombstones
      }))
    });
    const bytes: Uint8Array = (digest.digestSync() as cryptoFramework.DataBlob).data;
    let result: string = '';
    for (let index: number = 0; index < bytes.length; index += 1) {
      result += bytes[index].toString(16).padStart(2, '0');
    }
    return result;
  }

  private normalizePositiveInteger(value: number | undefined): number {
    const numeric: number = Number(value ?? 0);
    return Number.isFinite(numeric) && numeric > 0 ? Math.floor(numeric) : 0;
  }

  private normalizeNonNegativeInteger(value: number | undefined): number {
    const numeric: number = Number(value ?? -1);
    return Number.isFinite(numeric) && numeric >= 0 ? Math.floor(numeric) : -1;
  }

  private isNonEmptyString(value: string | undefined): boolean {
    return typeof value === 'string' && value.trim().length > 0;
  }
}
