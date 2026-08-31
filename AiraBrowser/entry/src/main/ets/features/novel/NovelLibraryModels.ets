export type NovelBookPaletteThemeMode = 'light' | 'dark';
export type NovelBookshelfCategory = 'novel' | 'comic';

export const NOVEL_BOOK_COVER_PALETTE_VERSION: number = 1;

export interface NovelBookCoverPalette {
  backgroundColor: string;
  surfaceColor: string;
  primaryTextColor: string;
  secondaryTextColor: string;
  dividerColor: string;
  glassTintColor: string;
}

export interface NovelBookshelfBookInput {
  detailUrl: string;
  title: string;
  author: string;
  coverUrl: string;
  sourceHost: string;
  category: string;
  latestChapter: string;
  synopsis: string;
}

export interface NovelBookshelfBook extends NovelBookshelfBookInput {
  id: string;
  addedAt: number;
  updatedAt: number;
}

export interface NovelBookshelfTombstone {
  id: string;
  deletedAt: number;
}

export interface NovelBookshelfSyncLocalState {
  books: NovelBookshelfBook[];
  tombstones: NovelBookshelfTombstone[];
}

export type NovelLibraryChangeOrigin = 'local' | 'sync' | 'metadata';
export type NovelLibraryChangeHandler = (origin: NovelLibraryChangeOrigin) => void;

export interface NovelBookPaletteCacheEntry {
  key: string;
  coverUrl: string;
  themeMode: NovelBookPaletteThemeMode;
  paletteVersion: number;
  palette: NovelBookCoverPalette;
  cachedAt: number;
}

export interface NovelBookshelfState {
  loading: boolean;
  novels: NovelBookshelfBook[];
  comics: NovelBookshelfBook[];
  errorMessage: string;
}

export function normalizeNovelDetailUrl(value: string): string {
  let normalized: string = value.trim();
  const hashIndex: number = normalized.indexOf('#');
  if (hashIndex >= 0) {
    normalized = normalized.substring(0, hashIndex);
  }
  const schemeIndex: number = normalized.indexOf('://');
  if (schemeIndex < 0) {
    return normalized;
  }
  const authorityStart: number = schemeIndex + 3;
  let authorityEnd: number = normalized.length;
  const separators: string[] = ['/', '?'];
  for (let index: number = 0; index < separators.length; index += 1) {
    const separatorIndex: number = normalized.indexOf(separators[index], authorityStart);
    if (separatorIndex >= 0) {
      authorityEnd = Math.min(authorityEnd, separatorIndex);
    }
  }
  const scheme: string = normalized.substring(0, schemeIndex).toLowerCase();
  const authority: string = normalized.substring(authorityStart, authorityEnd).toLowerCase();
  const suffix: string = normalized.substring(authorityEnd);
  return `${scheme}://${authority}${suffix}`;
}

export function isValidNovelHttpUrl(value: string): boolean {
  const lower: string = value.toLowerCase();
  const authorityStart: number = lower.startsWith('https://')
    ? 'https://'.length
    : (lower.startsWith('http://') ? 'http://'.length : -1);
  if (authorityStart < 0) {
    return false;
  }
  let authorityEnd: number = value.length;
  const separators: string[] = ['/', '?', '#'];
  for (let index: number = 0; index < separators.length; index += 1) {
    const separatorIndex: number = value.indexOf(separators[index], authorityStart);
    if (separatorIndex >= 0) {
      authorityEnd = Math.min(authorityEnd, separatorIndex);
    }
  }
  const authority: string = value.substring(authorityStart, authorityEnd);
  return authority.length > 0 && !/\s/.test(authority) && !authority.startsWith(':');
}

export function buildNovelBookPaletteCacheKey(
  coverUrl: string,
  themeMode: NovelBookPaletteThemeMode,
  paletteVersion: number = NOVEL_BOOK_COVER_PALETTE_VERSION
): string {
  return `${paletteVersion}|${themeMode}|${coverUrl.trim()}`;
}

export function cloneNovelBookCoverPalette(palette: NovelBookCoverPalette): NovelBookCoverPalette {
  return {
    backgroundColor: palette.backgroundColor,
    surfaceColor: palette.surfaceColor,
    primaryTextColor: palette.primaryTextColor,
    secondaryTextColor: palette.secondaryTextColor,
    dividerColor: palette.dividerColor,
    glassTintColor: palette.glassTintColor
  };
}

export function cloneNovelBookshelfBook(book: NovelBookshelfBook): NovelBookshelfBook {
  return {
    id: book.id,
    detailUrl: book.detailUrl,
    title: book.title,
    author: book.author,
    coverUrl: book.coverUrl,
    sourceHost: book.sourceHost,
    category: book.category,
    latestChapter: book.latestChapter,
    synopsis: book.synopsis,
    addedAt: book.addedAt,
    updatedAt: book.updatedAt
  };
}

export function cloneNovelBookshelfTombstone(tombstone: NovelBookshelfTombstone): NovelBookshelfTombstone {
  return {
    id: tombstone.id,
    deletedAt: tombstone.deletedAt
  };
}
