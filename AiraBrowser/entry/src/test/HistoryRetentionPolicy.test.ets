import { describe, expect, it } from '@ohos/hypium';
import { HistoryRetentionSettings } from '../main/ets/common/models/BrowserModels';
import { HistoryRetentionEntry, resolveHistoryRetentionDeletingIds } from
  '../main/ets/core/history/HistoryRetentionPolicy';

// History keeps a row budget and no longer expires on time. The rule used to be "drop anything
// older than N days OR past M rows", which silently deleted a page the user had visited a few
// months ago even when they were nowhere near the row budget. These cases pin the count-only
// rule: age alone never deletes, and only the overflow past `maxRows` does.
const DAY_MS = 24 * 60 * 60 * 1000;

function visit(id: string, ageDays: number, now: number): HistoryRetentionEntry {
  return { id: id, visitedAt: now - ageDays * DAY_MS };
}

function settings(enabled: boolean, maxRows: number): HistoryRetentionSettings {
  return { enabled: enabled, maxRows: maxRows };
}

export default function historyRetentionPolicyTest(): void {
  describe('HistoryRetentionPolicy', () => {
    it('keeps visits of any age while they are inside the row budget', 0, () => {
      const now = Date.now();
      const visits = [visit('today', 0, now), visit('last-year', 365, now), visit('two-years', 730, now)];
      expect(resolveHistoryRetentionDeletingIds(visits, settings(true, 10000)).length).assertEqual(0);
    });

    it('drops only the visits past the row budget', 0, () => {
      const now = Date.now();
      const visits = [visit('newest', 0, now), visit('middle', 10, now), visit('oldest', 400, now)];
      const deleting = resolveHistoryRetentionDeletingIds(visits, settings(true, 2));
      expect(deleting.length).assertEqual(1);
      expect(deleting[0]).assertEqual('oldest');
    });

    it('ranks by recency, not by array order', 0, () => {
      const now = Date.now();
      // The oldest entry sits first in the list, so a naive prefix cut would drop the wrong visit.
      const visits = [visit('oldest', 900, now), visit('newest', 0, now), visit('middle', 5, now)];
      const deleting = resolveHistoryRetentionDeletingIds(visits, settings(true, 2));
      expect(deleting.length).assertEqual(1);
      expect(deleting[0]).assertEqual('oldest');
    });

    it('keeps a year-old visit that a time limit would have deleted', 0, () => {
      const now = Date.now();
      const visits = [visit('recent', 1, now), visit('ancient', 500, now)];
      // A 90-day limit would have removed `ancient`; the row budget must not.
      expect(resolveHistoryRetentionDeletingIds(visits, settings(true, 10000)).length).assertEqual(0);
    });

    it('drops everything when retention is disabled', 0, () => {
      const now = Date.now();
      const visits = [visit('a', 0, now), visit('b', 1, now)];
      expect(resolveHistoryRetentionDeletingIds(visits, settings(false, 0)).length).assertEqual(2);
    });

    it('reports each dropped visit once', 0, () => {
      const now = Date.now();
      const visits = [visit('newest', 0, now), visit('dup', 30, now), visit('dup', 30, now)];
      const deleting = resolveHistoryRetentionDeletingIds(visits, settings(true, 1));
      expect(deleting.length).assertEqual(1);
      expect(deleting[0]).assertEqual('dup');
    });

    it('handles an empty history', 0, () => {
      expect(resolveHistoryRetentionDeletingIds([], settings(true, 10000)).length).assertEqual(0);
    });
  });
}
