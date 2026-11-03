export type BookmarkSortMode = 'manual' | 'newest' | 'oldest' | 'name_asc' | 'name_desc';

export const BOOKMARK_SORT_PREFERENCES_REVISION_KEY: string = 'bookmarkSortPreferencesRevision';

export function normalizeBookmarkSortMode(value: string): BookmarkSortMode {
  return value === 'newest' || value === 'oldest' || value === 'name_asc' || value === 'name_desc'
    ? value : 'manual';
}
