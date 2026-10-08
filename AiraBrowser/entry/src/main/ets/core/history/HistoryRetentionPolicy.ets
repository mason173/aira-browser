import { HistoryRetentionSettings } from '../../common/models/BrowserModels';

/**
 * The part of a visit a retention decision depends on. Keeping the input this narrow lets the
 * rule be read — and tested — without standing up a whole history record.
 */
export interface HistoryRetentionEntry {
  id: string;
  visitedAt: number;
}

/**
 * Which history entries a retention policy drops.
 *
 * History is kept by count, not by age: an entry is dropped only once it falls past the newest
 * `maxRows` entries. Anything still inside that budget survives however old it is, so a page
 * visited a year ago stays until the budget pushes it out. A disabled policy drops everything.
 */
export function resolveHistoryRetentionDeletingIds(
  entries: HistoryRetentionEntry[],
  settings: HistoryRetentionSettings
): string[] {
  if (!settings.enabled) {
    return entries.map((entry: HistoryRetentionEntry) => entry.id);
  }
  const ordered = entries
    .slice()
    .sort((left: HistoryRetentionEntry, right: HistoryRetentionEntry) => right.visitedAt - left.visitedAt);
  const deletingIds: string[] = [];
  ordered.forEach((entry: HistoryRetentionEntry, index: number) => {
    if (index >= settings.maxRows) {
      deletingIds.push(entry.id);
    }
  });
  return Array.from(new Set<string>(deletingIds));
}
