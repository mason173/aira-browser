import { afterEach, expect, test, vi } from 'vitest';
import { HistorySurfaceTimeline } from './HistorySurfaceTimeline';
import type { HistorySyncVisit, HistoryTimelinePage } from '@/features/sync/history/HistorySyncModels';

afterEach(() => vi.unstubAllGlobals());

const syncedVisit = (id: string, clientId: string, visitedAt: number): HistorySyncVisit => ({
  visitId: id, clientId, nativeVisitId: id, visitedAt, url: 'https://example.com/',
  title: id, deviceName: clientId, source: 'aira', transition: 'link', referrer: '',
});
const page = (visits: HistorySyncVisit[]): HistoryTimelinePage => ({ visits, total: visits.length, devices: [], lastSyncAt: 0, lastError: '' });

test('native repeats remain distinct, this device is not duplicated, and remote retention cannot hide local records', async () => {
  const nativeDelete = vi.fn();
  // Promise-only APIs exercise the Firefox path, including repeated visits to one URL.
  vi.stubGlobal('chrome', { history: {
    search: async () => [{ id: 'url', url: 'https://example.com/', title: 'Native', lastVisitTime: 500, visitCount: 2 }],
    getVisits: async () => [{ visitId: 'new', visitTime: 500, transition: 'link' }, { visitId: 'old', visitTime: 100, transition: 'link' }],
    deleteUrl: nativeDelete, deleteAll: nativeDelete, deleteRange: nativeDelete,
  } });
  const timeline = new HistorySurfaceTimeline();
  const before = await timeline.list(page([syncedVisit('duplicate', 'desktop', 500), syncedVisit('phone-visit', 'phone', 300)]), 'desktop', 'Desktop', {});
  expect(before.visits.map(visit => visit.visitedAt)).toEqual([500, 300, 100]);
  expect(before.visits.map(visit => visit.title)).toEqual(['Native', 'phone-visit', 'Native']);
  const after = await timeline.list(page([]), 'desktop', 'Desktop', {});
  expect(after.visits.map(visit => visit.visitedAt)).toEqual([500, 100]);
  expect(nativeDelete).not.toHaveBeenCalled();
});

test('paging reuses native visit details, while an actual native removal invalidates them', async () => {
  let details = [{ visitId: 'new', visitTime: 500, transition: 'link' }, { visitId: 'old', visitTime: 100, transition: 'link' }];
  const getVisits = vi.fn(async () => details);
  vi.stubGlobal('chrome', { history: {
    search: async () => [{ id: 'url', url: 'https://example.com/', title: 'Native', lastVisitTime: 500 }], getVisits,
  } });
  const timeline = new HistorySurfaceTimeline();
  expect((await timeline.list(page([]), '', '', { limit: 1 })).hasMore).toBe(true);
  expect((await timeline.list(page([]), '', '', { limit: 200 })).visits).toHaveLength(2);
  expect(getVisits).toHaveBeenCalledTimes(1);
  details = details.slice(0, 1);
  timeline.invalidate();
  expect((await timeline.list(page([]), '', '', {})).visits).toHaveLength(1);
  expect(getVisits).toHaveBeenCalledTimes(2);
});

test('a failed native query remains an explicit error instead of an empty successful page', async () => {
  const runtime: { lastError?: { message: string } } = {};
  vi.stubGlobal('chrome', { runtime, history: {
    search: (_query: unknown, callback: (items: unknown[]) => void) => {
      runtime.lastError = { message: 'Native query failed' };
      callback([]);
      delete runtime.lastError;
    }, getVisits: vi.fn(),
  } });
  await expect(new HistorySurfaceTimeline().list(page([]), '', '', {})).rejects.toThrow('Native query failed');
});
