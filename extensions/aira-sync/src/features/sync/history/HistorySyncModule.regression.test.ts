import 'fake-indexeddb/auto';
import { afterEach, expect, test, vi } from 'vitest';
import { HistorySyncModule } from './HistorySyncModule';
import type { HistorySyncDatabase } from './HistorySyncDatabase';

const NOW = 1_793_584_800_000;
const session = (uid: string) => ({ uid, deviceId: 'edge-regression', deviceName: 'Edge test', deviceCredential: 'synthetic' });
const item = (time: number): chrome.history.HistoryItem => ({
  id: 'item', url: 'https://example.com/history', title: 'Native visit', lastVisitTime: time,
});
const visit = (time: number): chrome.history.VisitItem => ({
  id: 'item', visitId: 'visit', visitTime: time, isLocal: true, transition: 'link', referringVisitId: '0',
});
const database = (module: HistorySyncModule) => (module as unknown as { database: HistorySyncDatabase }).database;

afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

test.each(['new', 'same-millisecond', 'delayed-event', 'reobserved'])(
  'full reconciliation preserves a %s visit captured while its native query is in flight', async scenario => {
    let now = NOW - 10_000;
    vi.spyOn(Date, 'now').mockImplementation(() => now);
    const identity = session(`overlap-${scenario}`);
    const module = new HistorySyncModule();
    let releaseSearch!: () => void;
    let searchStarted!: () => void;
    const started = new Promise<void>(resolve => { searchStarted = resolve; });
    let visitTime = now - 1000;
    const search = vi.fn((_query: chrome.history.HistoryQuery, callback: (items: chrome.history.HistoryItem[]) => void) => {
      releaseSearch = () => callback([]);
      searchStarted();
    });
    const nativeDelete = vi.fn();
    vi.stubGlobal('chrome', { history: {
      search,
      getVisits: (_details: chrome.history.UrlDetails, callback: (visits: chrome.history.VisitItem[]) => void) => callback([visit(visitTime)]),
      deleteUrl: nativeDelete, deleteAll: nativeDelete, deleteRange: nativeDelete,
    } });
    if (scenario === 'reobserved') await module.captureVisitedItem(identity, item(visitTime));
    now = NOW;
    const reconciliation = module.reconcileNativeHistory(identity, true);
    await started;
    now = scenario === 'same-millisecond' ? NOW : NOW + 1000;
    if (scenario === 'new') visitTime = now - 1;
    await module.captureVisitedItem(identity, item(visitTime));
    expect((await module.listTimeline(identity.uid)).total).toBe(1);
    releaseSearch();
    await reconciliation;
    expect((await module.listTimeline(identity.uid)).total).toBe(1);
    expect((await database(module).listOutbox(identity.uid, 20)).some(m => m.kind === 'delete_visit')).toBe(false);
    search.mockImplementation((_query, callback) => callback([item(visitTime)]));
    await module.reconcileNativeHistory(identity, true);
    expect((await module.listTimeline(identity.uid)).total).toBe(1);
    expect(nativeDelete).not.toHaveBeenCalled();
  },
);

test('a complete later scan still propagates a genuine native removal', async () => {
  let now = NOW;
  vi.spyOn(Date, 'now').mockImplementation(() => now);
  vi.stubGlobal('chrome', { history: {
    search: (_query: chrome.history.HistoryQuery, callback: (items: chrome.history.HistoryItem[]) => void) => callback([]),
    getVisits: (_details: chrome.history.UrlDetails, callback: (visits: chrome.history.VisitItem[]) => void) => callback([visit(NOW - 1000)]),
  } });
  const identity = session('actual-removal');
  const module = new HistorySyncModule();
  await module.captureVisitedItem(identity, item(NOW - 1000));
  now += 1000;
  await module.reconcileNativeHistory(identity, true);
  expect((await module.listTimeline(identity.uid)).total).toBe(0);
  expect((await database(module).listOutbox(identity.uid, 20)).filter(m => m.kind === 'delete_visit')).toHaveLength(1);
  await module.captureVisitedItem(identity, item(NOW - 1000));
  expect((await module.listTimeline(identity.uid)).total).toBe(0);
});

test('a failed native search cannot masquerade as an empty history and enqueue deletions', async () => {
  let now = NOW;
  vi.spyOn(Date, 'now').mockImplementation(() => now);
  const runtime: { lastError?: { message: string } } = {};
  vi.stubGlobal('chrome', { runtime, history: {
    search: (_query: chrome.history.HistoryQuery, callback: (items: chrome.history.HistoryItem[]) => void) => {
      runtime.lastError = { message: 'Synthetic native query failure' };
      callback([]);
      delete runtime.lastError;
    },
    getVisits: (_details: chrome.history.UrlDetails, callback: (visits: chrome.history.VisitItem[]) => void) => callback([visit(NOW - 1000)]),
  } });
  const identity = session('native-search-error');
  const module = new HistorySyncModule();
  await module.captureVisitedItem(identity, item(NOW - 1000));
  now += 1000;
  await expect(module.reconcileNativeHistory(identity, true)).rejects.toThrow('Synthetic native query failure');
  expect((await module.listTimeline(identity.uid)).total).toBe(1);
  expect((await database(module).listOutbox(identity.uid, 20)).some(m => m.kind === 'delete_visit')).toBe(false);
});

test('the surface can extend its timeline past 500 records', async () => {
  const module = new HistorySyncModule();
  const identity = session('timeline-pagination');
  await database(module).captureNativeVisits(identity.uid, identity.deviceId, identity.deviceName,
    Array.from({ length: 601 }, (_, i) => ({
      nativeVisitId: String(i), url: `https://example.com/${i}`, title: `Visit ${i}`,
      visitedAt: NOW - i - 1, transition: 'link',
    })), false, NOW);
  const page = await module.listTimeline(identity.uid, { limit: 600 });
  expect(page.total).toBe(601);
  expect(page.visits).toHaveLength(600);
  expect((await module.listTimeline(identity.uid, { limit: 800 })).visits).toHaveLength(601);
});

test('offline accumulation keeps only the newest 10,000 pending uploads without native deletion', async () => {
  const module = new HistorySyncModule();
  const identity = session('bounded-upload');
  const db = database(module);
  const nativeDelete = vi.fn();
  vi.stubGlobal('chrome', { history: { deleteUrl: nativeDelete, deleteAll: nativeDelete, deleteRange: nativeDelete } });
  await db.captureNativeVisits(identity.uid, identity.deviceId, identity.deviceName,
    Array.from({ length: 10_001 }, (_, i) => ({
      nativeVisitId: String(i), url: `https://example.com/${i}`, title: `Visit ${i}`,
      visitedAt: NOW - i - 1, transition: 'link',
    })), false, NOW);
  await db.pruneProjection(identity.uid);
  expect((await module.listTimeline(identity.uid)).total).toBe(10_000);
  const pending = await db.listOutbox(identity.uid, 20_000);
  expect(pending).toHaveLength(10_000);
  expect(pending.every(mutation => mutation.kind === 'upsert_visit')).toBe(true);
  expect(pending.some(mutation => mutation.visit?.nativeVisitId === '10000')).toBe(false);
  expect(nativeDelete).not.toHaveBeenCalled();
}, 30_000);
