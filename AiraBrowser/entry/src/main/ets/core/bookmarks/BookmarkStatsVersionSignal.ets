export const BOOKMARK_STATS_VERSION_KEY: string = 'aira.bookmarks.statsVersion';

export class BookmarkStatsVersionSignal {
  static readVersion(): number {
    const raw = AppStorage.get<number>(BOOKMARK_STATS_VERSION_KEY) ?? 0;
    const value = Number(raw);
    return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  static bumpVersion(): number {
    const next = Math.max(Date.now(), BookmarkStatsVersionSignal.readVersion() + 1);
    AppStorage.setOrCreate(BOOKMARK_STATS_VERSION_KEY, next);
    return next;
  }
}
