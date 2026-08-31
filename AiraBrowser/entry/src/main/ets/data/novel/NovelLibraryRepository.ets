import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  buildNovelBookPaletteCacheKey,
  cloneNovelBookCoverPalette,
  cloneNovelBookshelfBook,
  cloneNovelBookshelfTombstone,
  isValidNovelHttpUrl,
  normalizeNovelDetailUrl,
  NOVEL_BOOK_COVER_PALETTE_VERSION,
  NovelBookCoverPalette,
  NovelBookPaletteCacheEntry,
  NovelBookPaletteThemeMode,
  NovelBookshelfBook,
  NovelBookshelfBookInput,
  NovelBookshelfSyncLocalState,
  NovelBookshelfTombstone,
  NovelLibraryChangeHandler,
  NovelLibraryChangeOrigin
} from '../../features/novel/NovelLibraryModels';

interface NovelLibraryDocument {
  schemaVersion: number;
  books: NovelBookshelfBook[];
  palettes: NovelBookPaletteCacheEntry[];
  tombstones: NovelBookshelfTombstone[];
}

const NOVEL_LIBRARY_PREFERENCES_NAME: string = 'aira_novel_library';
const NOVEL_LIBRARY_DOCUMENT_KEY: string = 'library_document';
const NOVEL_LIBRARY_SCHEMA_VERSION: number = 3;
const NOVEL_LIBRARY_MAX_BOOKS: number = 500;
const NOVEL_LIBRARY_MAX_TOMBSTONES: number = 2000;
const NOVEL_LIBRARY_MAX_PALETTES: number = 96;
const NOVEL_LIBRARY_MAX_TITLE_LENGTH: number = 240;
const NOVEL_LIBRARY_MAX_METADATA_LENGTH: number = 1000;
const NOVEL_LIBRARY_MAX_URL_LENGTH: number = 4096;

export class NovelLibraryRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private document?: NovelLibraryDocument;
  private documentPromise?: Promise<NovelLibraryDocument>;
  private mutationTask: Promise<void> = Promise.resolve();
  private changeHandler?: NovelLibraryChangeHandler;

  setChangeHandler(handler?: NovelLibraryChangeHandler): void {
    this.changeHandler = handler;
  }

  async listBookshelf(): Promise<NovelBookshelfBook[]> {
    await this.waitForMutations();
    const document = await this.getDocument();
    return document.books
      .map((book: NovelBookshelfBook): NovelBookshelfBook => cloneNovelBookshelfBook(book))
      .sort((left: NovelBookshelfBook, right: NovelBookshelfBook): number => right.addedAt - left.addedAt);
  }

  async isInBookshelf(detailUrl: string): Promise<boolean> {
    await this.waitForMutations();
    const normalizedUrl: string = normalizeNovelDetailUrl(detailUrl);
    if (normalizedUrl.length === 0) {
      return false;
    }
    const document = await this.getDocument();
    return this.findBookIndex(document.books, normalizedUrl) >= 0;
  }

  async readSyncLocalState(): Promise<NovelBookshelfSyncLocalState> {
    await this.waitForMutations();
    const document = await this.getDocument();
    return {
      books: document.books.map((book: NovelBookshelfBook): NovelBookshelfBook => cloneNovelBookshelfBook(book)),
      tombstones: document.tombstones.map(
        (value: NovelBookshelfTombstone): NovelBookshelfTombstone => cloneNovelBookshelfTombstone(value)
      )
    };
  }

  addToBookshelf(input: NovelBookshelfBookInput): Promise<void> {
    const normalizedInput: NovelBookshelfBookInput = this.normalizeBookInput(input);
    if (normalizedInput.detailUrl.length === 0 || normalizedInput.title.length === 0) {
      return Promise.reject(new Error('novel-bookshelf-book-invalid'));
    }
    return this.enqueueMutation((document: NovelLibraryDocument): NovelLibraryChangeOrigin | undefined => {
      const now: number = Date.now();
      const id: string = normalizeNovelDetailUrl(normalizedInput.detailUrl);
      const index: number = this.findBookIndex(document.books, id);
      const existing: NovelBookshelfBook | undefined = index >= 0 ? document.books[index] : undefined;
      const book: NovelBookshelfBook = {
        id: id,
        detailUrl: normalizedInput.detailUrl,
        title: normalizedInput.title,
        author: normalizedInput.author,
        coverUrl: normalizedInput.coverUrl,
        sourceHost: normalizedInput.sourceHost,
        category: normalizedInput.category,
        latestChapter: normalizedInput.latestChapter,
        synopsis: normalizedInput.synopsis,
        addedAt: existing?.addedAt ?? now,
        updatedAt: now
      };
      if (index >= 0) {
        const portableChanged: boolean = existing === undefined ||
          existing.title !== book.title || existing.author !== book.author || existing.coverUrl !== book.coverUrl ||
          existing.detailUrl !== book.detailUrl;
        const metadataChanged: boolean = existing === undefined || portableChanged ||
          existing.sourceHost !== book.sourceHost || existing.category !== book.category ||
          existing.latestChapter !== book.latestChapter || existing.synopsis !== book.synopsis;
        if (!metadataChanged) {
          return undefined;
        }
        if (!portableChanged && existing !== undefined) {
          book.updatedAt = existing.updatedAt;
        }
        document.books[index] = book;
        if (portableChanged) {
          this.removeTombstone(document.tombstones, id);
          return 'local';
        }
        return 'metadata';
      }
      if (document.books.length >= NOVEL_LIBRARY_MAX_BOOKS) {
        throw new Error('novel-bookshelf-quota-exceeded');
      }
      document.books.push(book);
      this.removeTombstone(document.tombstones, id);
      return 'local';
    });
  }

  removeFromBookshelf(detailUrl: string): Promise<void> {
    const normalizedUrl: string = normalizeNovelDetailUrl(detailUrl);
    if (normalizedUrl.length === 0) {
      return Promise.resolve();
    }
    return this.enqueueMutation((document: NovelLibraryDocument): NovelLibraryChangeOrigin | undefined => {
      const index: number = this.findBookIndex(document.books, normalizedUrl);
      if (index >= 0) {
        document.books.splice(index, 1);
        this.upsertTombstone(document.tombstones, normalizedUrl, Date.now());
        return 'local';
      }
      return undefined;
    });
  }

  applySyncedBookshelf(
    books: NovelBookshelfBook[],
    tombstones: NovelBookshelfTombstone[]
  ): Promise<void> {
    if (books.length > NOVEL_LIBRARY_MAX_BOOKS || tombstones.length > NOVEL_LIBRARY_MAX_TOMBSTONES) {
      return Promise.reject(new Error('novel-bookshelf-sync-local-quota-exceeded'));
    }
    return this.enqueueMutation((document: NovelLibraryDocument): NovelLibraryChangeOrigin | undefined => {
      const normalizedBooks: NovelBookshelfBook[] = this.normalizeBooks(books);
      const normalizedTombstones: NovelBookshelfTombstone[] = this.normalizeTombstones(tombstones);
      if (normalizedBooks.length !== books.length || normalizedTombstones.length !== tombstones.length) {
        throw new Error('novel-bookshelf-sync-local-state-invalid');
      }
      const mergedBooks: NovelBookshelfBook[] = normalizedBooks.map(
        (book: NovelBookshelfBook): NovelBookshelfBook => this.preserveLocalBookMetadata(book, document.books)
      );
      const changed: boolean = JSON.stringify(document.books) !== JSON.stringify(mergedBooks) ||
        JSON.stringify(document.tombstones) !== JSON.stringify(normalizedTombstones);
      if (!changed) {
        return undefined;
      }
      document.books = mergedBooks;
      document.tombstones = normalizedTombstones;
      return 'sync';
    });
  }

  async readPalette(
    coverUrl: string,
    themeMode: NovelBookPaletteThemeMode
  ): Promise<NovelBookCoverPalette | undefined> {
    await this.waitForMutations();
    const key: string = buildNovelBookPaletteCacheKey(coverUrl, themeMode);
    const document = await this.getDocument();
    for (let index: number = 0; index < document.palettes.length; index += 1) {
      if (document.palettes[index].key === key) {
        return cloneNovelBookCoverPalette(document.palettes[index].palette);
      }
    }
    return undefined;
  }

  savePalette(
    coverUrl: string,
    themeMode: NovelBookPaletteThemeMode,
    palette: NovelBookCoverPalette
  ): Promise<void> {
    const normalizedCoverUrl: string = coverUrl.trim();
    if (normalizedCoverUrl.length === 0) {
      return Promise.resolve();
    }
    const key: string = buildNovelBookPaletteCacheKey(normalizedCoverUrl, themeMode);
    const entry: NovelBookPaletteCacheEntry = {
      key: key,
      coverUrl: normalizedCoverUrl,
      themeMode: themeMode,
      paletteVersion: NOVEL_BOOK_COVER_PALETTE_VERSION,
      palette: cloneNovelBookCoverPalette(palette),
      cachedAt: Date.now()
    };
    return this.enqueueMutation((document: NovelLibraryDocument): NovelLibraryChangeOrigin | undefined => {
      const index: number = this.findPaletteIndex(document.palettes, key);
      if (index >= 0) {
        document.palettes[index] = entry;
      } else {
        document.palettes.push(entry);
      }
      document.palettes.sort((left: NovelBookPaletteCacheEntry, right: NovelBookPaletteCacheEntry): number =>
        right.cachedAt - left.cachedAt);
      if (document.palettes.length > NOVEL_LIBRARY_MAX_PALETTES) {
        document.palettes.splice(NOVEL_LIBRARY_MAX_PALETTES);
      }
      return 'metadata';
    });
  }

  private enqueueMutation(
    mutation: (document: NovelLibraryDocument) => NovelLibraryChangeOrigin | undefined
  ): Promise<void> {
    const task: Promise<void> = this.mutationTask
      .catch((_error: Error): void => {})
      .then(async (): Promise<void> => {
        const current: NovelLibraryDocument = await this.getDocument();
        const next: NovelLibraryDocument = this.cloneDocument(current);
        const origin: NovelLibraryChangeOrigin | undefined = mutation(next);
        if (origin === undefined) {
          return;
        }
        await this.persistDocument(next);
        this.document = next;
        this.changeHandler?.(origin);
      });
    this.mutationTask = task;
    return task;
  }

  private async waitForMutations(): Promise<void> {
    await this.mutationTask.catch((_error: Error): void => {});
  }

  private async getDocument(): Promise<NovelLibraryDocument> {
    if (this.document !== undefined) {
      return this.document;
    }
    if (this.documentPromise === undefined) {
      this.documentPromise = this.loadDocument().then((document: NovelLibraryDocument): NovelLibraryDocument => {
        this.document = document;
        return document;
      }).finally((): void => {
        this.documentPromise = undefined;
      });
    }
    return this.documentPromise;
  }

  private async loadDocument(): Promise<NovelLibraryDocument> {
    const store = await this.getStore();
    const raw: string = String(store.getSync(NOVEL_LIBRARY_DOCUMENT_KEY, ''));
    if (raw.length === 0) {
      return this.createEmptyDocument();
    }
    let parsed: NovelLibraryDocument;
    try {
      parsed = JSON.parse(raw) as NovelLibraryDocument;
    } catch (_error) {
      throw new Error('novel-library-document-corrupt');
    }
    if ((parsed.schemaVersion !== 1 && parsed.schemaVersion !== 2 &&
      parsed.schemaVersion !== NOVEL_LIBRARY_SCHEMA_VERSION) ||
      !Array.isArray(parsed.books) || !Array.isArray(parsed.palettes)) {
      throw new Error('novel-library-schema-unsupported');
    }
    return {
      schemaVersion: NOVEL_LIBRARY_SCHEMA_VERSION,
      books: this.normalizeBooks(parsed.books),
      palettes: this.normalizePalettes(parsed.palettes),
      tombstones: this.normalizeTombstones(
        Array.isArray(parsed.tombstones) ? parsed.tombstones : []
      )
    };
  }

  private async persistDocument(document: NovelLibraryDocument): Promise<void> {
    const store = await this.getStore();
    store.putSync(NOVEL_LIBRARY_DOCUMENT_KEY, JSON.stringify(document));
    await store.flush();
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        NOVEL_LIBRARY_PREFERENCES_NAME
      ).then((store: preferences.Preferences): preferences.Preferences => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }

  private normalizeBooks(values: NovelBookshelfBook[]): NovelBookshelfBook[] {
    const books: NovelBookshelfBook[] = [];
    values.forEach((value: NovelBookshelfBook): void => {
      if (books.length >= NOVEL_LIBRARY_MAX_BOOKS) {
        return;
      }
      const input: NovelBookshelfBookInput = this.normalizeBookInput(value);
      const id: string = normalizeNovelDetailUrl(input.detailUrl);
      const addedAt: number = this.normalizeTimestamp(value.addedAt);
      if (id.length === 0 || input.title.length === 0 || addedAt <= 0 ||
        this.findBookIndex(books, id) >= 0) {
        return;
      }
      books.push({
        id: id,
        detailUrl: input.detailUrl,
        title: input.title,
        author: input.author,
        coverUrl: input.coverUrl,
        sourceHost: input.sourceHost,
        category: input.category,
        latestChapter: input.latestChapter,
        synopsis: input.synopsis,
        addedAt: addedAt,
        updatedAt: this.normalizeTimestamp(value.updatedAt) || addedAt
      });
    });
    return books;
  }

  private normalizePalettes(values: NovelBookPaletteCacheEntry[]): NovelBookPaletteCacheEntry[] {
    const palettes: NovelBookPaletteCacheEntry[] = [];
    values.forEach((value: NovelBookPaletteCacheEntry): void => {
      if (palettes.length >= NOVEL_LIBRARY_MAX_PALETTES ||
        value.paletteVersion !== NOVEL_BOOK_COVER_PALETTE_VERSION ||
        (value.themeMode !== 'light' && value.themeMode !== 'dark') ||
        !this.isValidPalette(value.palette)) {
        return;
      }
      const coverUrl: string = String(value.coverUrl ?? '').trim();
      const key: string = buildNovelBookPaletteCacheKey(coverUrl, value.themeMode);
      if (coverUrl.length === 0 || key !== String(value.key ?? '') || this.findPaletteIndex(palettes, key) >= 0) {
        return;
      }
      palettes.push({
        key: key,
        coverUrl: coverUrl,
        themeMode: value.themeMode,
        paletteVersion: NOVEL_BOOK_COVER_PALETTE_VERSION,
        palette: cloneNovelBookCoverPalette(value.palette),
        cachedAt: this.normalizeTimestamp(value.cachedAt)
      });
    });
    return palettes;
  }

  private normalizeTombstones(values: NovelBookshelfTombstone[]): NovelBookshelfTombstone[] {
    const latestById: Record<string, NovelBookshelfTombstone> = {};
    values.forEach((value: NovelBookshelfTombstone): void => {
      const id: string = normalizeNovelDetailUrl(String(value?.id ?? ''));
      const deletedAt: number = this.normalizeTimestamp(value?.deletedAt);
      if (id.length === 0 || deletedAt <= 0) {
        return;
      }
      const previous: NovelBookshelfTombstone | undefined = latestById[id];
      if (previous === undefined || previous.deletedAt < deletedAt) {
        latestById[id] = { id: id, deletedAt: deletedAt };
      }
    });
    return Object.keys(latestById)
      .map((id: string): NovelBookshelfTombstone => latestById[id])
      .sort((left: NovelBookshelfTombstone, right: NovelBookshelfTombstone): number => {
        if (left.deletedAt !== right.deletedAt) {
          return right.deletedAt - left.deletedAt;
        }
        return left.id.localeCompare(right.id);
      })
      .slice(0, NOVEL_LIBRARY_MAX_TOMBSTONES)
      .sort((left: NovelBookshelfTombstone, right: NovelBookshelfTombstone): number =>
        left.id.localeCompare(right.id));
  }

  private normalizeBookInput(input: NovelBookshelfBookInput): NovelBookshelfBookInput {
    return {
      detailUrl: this.normalizeNavigableUrl(input.detailUrl),
      title: this.normalizeText(input.title, NOVEL_LIBRARY_MAX_TITLE_LENGTH),
      author: this.normalizeText(input.author, NOVEL_LIBRARY_MAX_TITLE_LENGTH),
      coverUrl: this.normalizeText(input.coverUrl, NOVEL_LIBRARY_MAX_METADATA_LENGTH),
      sourceHost: this.normalizeText(input.sourceHost, NOVEL_LIBRARY_MAX_TITLE_LENGTH),
      category: this.normalizeText(input.category, NOVEL_LIBRARY_MAX_TITLE_LENGTH),
      latestChapter: this.normalizeText(input.latestChapter, NOVEL_LIBRARY_MAX_TITLE_LENGTH),
      synopsis: this.normalizeText(input.synopsis, NOVEL_LIBRARY_MAX_METADATA_LENGTH)
    };
  }

  private normalizeNavigableUrl(value: string): string {
    let normalized: string = String(value ?? '').trim();
    const hashIndex: number = normalized.indexOf('#');
    if (hashIndex >= 0) {
      normalized = normalized.substring(0, hashIndex);
    }
    if (normalized.length > NOVEL_LIBRARY_MAX_URL_LENGTH ||
      !isValidNovelHttpUrl(normalized)) {
      return '';
    }
    return normalized;
  }

  private normalizeText(value: string, maximumLength: number): string {
    const normalized: string = String(value ?? '').trim();
    return normalized.length > maximumLength ? normalized.substring(0, maximumLength) : normalized;
  }

  private normalizeTimestamp(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  private isValidPalette(palette: NovelBookCoverPalette): boolean {
    return palette !== undefined &&
      this.isColor(palette.backgroundColor) && this.isColor(palette.surfaceColor) &&
      this.isColor(palette.primaryTextColor) && this.isColor(palette.secondaryTextColor) &&
      this.isColor(palette.dividerColor) && this.isColor(palette.glassTintColor);
  }

  private isColor(value: string): boolean {
    const normalized: string = String(value ?? '').trim();
    return /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(normalized);
  }

  private findBookIndex(books: NovelBookshelfBook[], detailUrl: string): number {
    for (let index: number = 0; index < books.length; index += 1) {
      if (books[index].id === detailUrl) {
        return index;
      }
    }
    return -1;
  }

  private findPaletteIndex(palettes: NovelBookPaletteCacheEntry[], key: string): number {
    for (let index: number = 0; index < palettes.length; index += 1) {
      if (palettes[index].key === key) {
        return index;
      }
    }
    return -1;
  }

  private preserveLocalBookMetadata(
    syncedBook: NovelBookshelfBook,
    currentBooks: NovelBookshelfBook[]
  ): NovelBookshelfBook {
    const index: number = this.findBookIndex(currentBooks, syncedBook.id);
    const existing: NovelBookshelfBook | undefined = index >= 0 ? currentBooks[index] : undefined;
    return {
      id: syncedBook.id,
      detailUrl: syncedBook.detailUrl,
      title: syncedBook.title,
      author: syncedBook.author,
      coverUrl: syncedBook.coverUrl,
      sourceHost: existing?.sourceHost ?? this.resolveSourceHost(syncedBook.detailUrl),
      category: existing?.category ?? '',
      latestChapter: existing?.latestChapter ?? '',
      synopsis: existing?.synopsis ?? '',
      addedAt: syncedBook.addedAt,
      updatedAt: syncedBook.updatedAt
    };
  }

  private resolveSourceHost(detailUrl: string): string {
    const schemeIndex: number = detailUrl.indexOf('://');
    if (schemeIndex < 0) {
      return '';
    }
    const start: number = schemeIndex + 3;
    const pathIndex: number = detailUrl.indexOf('/', start);
    return detailUrl.substring(start, pathIndex >= 0 ? pathIndex : detailUrl.length).toLowerCase();
  }

  private removeTombstone(tombstones: NovelBookshelfTombstone[], id: string): void {
    const index: number = tombstones.findIndex((value: NovelBookshelfTombstone): boolean => value.id === id);
    if (index >= 0) {
      tombstones.splice(index, 1);
    }
  }

  private upsertTombstone(tombstones: NovelBookshelfTombstone[], id: string, deletedAt: number): void {
    this.removeTombstone(tombstones, id);
    tombstones.push({ id: id, deletedAt: deletedAt });
    const normalized: NovelBookshelfTombstone[] = this.normalizeTombstones(tombstones);
    tombstones.splice(0, tombstones.length, ...normalized);
  }

  private createEmptyDocument(): NovelLibraryDocument {
    return {
      schemaVersion: NOVEL_LIBRARY_SCHEMA_VERSION,
      books: [],
      palettes: [],
      tombstones: []
    };
  }

  private cloneDocument(document: NovelLibraryDocument): NovelLibraryDocument {
    return {
      schemaVersion: NOVEL_LIBRARY_SCHEMA_VERSION,
      books: document.books.map((book: NovelBookshelfBook): NovelBookshelfBook => cloneNovelBookshelfBook(book)),
      palettes: document.palettes.map((entry: NovelBookPaletteCacheEntry): NovelBookPaletteCacheEntry => ({
        key: entry.key,
        coverUrl: entry.coverUrl,
        themeMode: entry.themeMode,
        paletteVersion: entry.paletteVersion,
        palette: cloneNovelBookCoverPalette(entry.palette),
        cachedAt: entry.cachedAt
      })),
      tombstones: document.tombstones.map(
        (value: NovelBookshelfTombstone): NovelBookshelfTombstone => cloneNovelBookshelfTombstone(value)
      )
    };
  }
}

export const sharedNovelLibraryRepository: NovelLibraryRepository = new NovelLibraryRepository();
