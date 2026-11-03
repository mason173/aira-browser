import 'fake-indexeddb/auto';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { HistorySyncModule } from './HistorySyncModule';
import { createHistoryBackgroundSyncRuntime } from './HistoryBackgroundSyncRuntime';
import { HISTORY_MESSAGE_TYPE, type HistoryRuntimeMessage, type HistoryRuntimeResponse } from './historyMessages';
import { HISTORY_SYNC_DOMAIN_ENABLED_KEY, LEAFTAB_SELECTED_SYNC_SOURCE_KEY } from '../app/leafTabSyncStorageKeys';
import type { HistorySyncMutation } from './HistorySyncModels';

const state = vi.hoisted(() => ({
  storage: {} as Record<string, unknown>,
  session: { uid: '', deviceId: 'edge-runtime', deviceName: 'Edge test', deviceCredential: 'synthetic' },
  refreshMembership: vi.fn(async () => ({})),
  bootstrap: vi.fn(async () => ({ visits: [], deletedVisitIds: [], deleteRanges: [], clearBefore: 0, bootstrapHead: 0, headCursor: 0, hasMore: false })),
  exchange: vi.fn(async ({ mutations }: { mutations: HistorySyncMutation[] }) => ({
    acknowledgements: mutations.map(m => ({ mutationId: m.mutationId, acceptedSeq: 1, applied: true })),
    changes: mutations.filter(m => m.kind === 'delete_visit').map(m => ({ seq: 1, kind: 'delete_visit', visitId: m.visitId })),
    nextCursor: 1, headCursor: 1, hasMore: false,
  })),
}));
vi.mock('@/platform/extensionStorage', () => ({
  readExtensionStorageRecord: async () => state.storage,
  writeExtensionStorageRecord: async (values: object) => { Object.assign(state.storage, values); },
}));
vi.mock('@/features/personal-server/PersonalServerConnection', () => ({
  PERSONAL_SERVER_CONNECTION_STORAGE_KEY: 'personal', readPersonalServerConnection: async () => null,
  personalServerAccountScope: () => 'unused',
}));
vi.mock('@/features/desktop-connection/desktopConnectionRuntime', () => ({
  readAiraDesktopAuthorizedSession: async () => state.session, recordAiraDesktopConnectionFailure: async () => {},
}));
vi.mock('@/features/desktop-connection/desktopConnectionProfile', () => ({
  readAiraDesktopConnectionProfile: async () => ({}), refreshAiraDesktopConnectionProfileMembership: state.refreshMembership,
  resolveAiraDesktopProCapability: () => 'ready', shouldRefreshAiraDesktopConnectionMembership: () => true,
}));
vi.mock('./AiraCloudHistoryRemoteStore', () => ({
  AiraCloudHistoryRemoteError: class extends Error {},
  AiraCloudHistoryRemoteStore: class { bootstrap = state.bootstrap; exchange = state.exchange; },
}));

const NOW = 1_793_584_800_000;
let accountNumber = 0;
const nativeItem = (id: string): chrome.history.HistoryItem => ({
  id, url: `https://example.com/${id}`, title: id, lastVisitTime: NOW - (id === 'old' ? 20 * 60_000 : 1000),
});
beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(Date, 'now').mockReturnValue(NOW);
  state.session.uid = `runtime-history-${++accountNumber}`;
  state.storage = { [LEAFTAB_SELECTED_SYNC_SOURCE_KEY]: 'aira-cloud', [HISTORY_SYNC_DOMAIN_ENABLED_KEY]: 'false' };
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

function setup() {
  const items = [nativeItem('old'), nativeItem('new')];
  let onVisited!: (item: chrome.history.HistoryItem) => void;
  let onRemoved!: (removed: chrome.history.RemovedResult) => void;
  const search = vi.fn((_query: chrome.history.HistoryQuery, callback: (items: chrome.history.HistoryItem[]) => void) => callback(items));
  vi.stubGlobal('chrome', {
    history: {
      search,
      getVisits: ({ url }: chrome.history.UrlDetails, callback: (visits: chrome.history.VisitItem[]) => void) => {
        const item = items.find(i => i.url === url)!;
        callback([{ id: item.id, visitId: item.id, visitTime: item.lastVisitTime, isLocal: true, transition: 'link', referringVisitId: '0' }]);
      },
      onVisited: { addListener: (listener: typeof onVisited) => { onVisited = listener; } },
      onVisitRemoved: { addListener: (listener: typeof onRemoved) => { onRemoved = listener; } },
    },
    alarms: { clear: vi.fn(async () => true), create: vi.fn() },
  });
  const runtime = createHistoryBackgroundSyncRuntime({ connectionStorageKey: 'connection', startKeepAlive: () => ({ stop() {} }) });
  const send = (action: 'open' | 'list' | 'sync' | 'delete', visitId?: string, options: Partial<HistoryRuntimeMessage> & { includeNative?: boolean } = {}) => new Promise<HistoryRuntimeResponse>(resolve => {
    runtime.handleMessage({ type: HISTORY_MESSAGE_TYPE, action, limit: 200, visitId, ...options }, resolve);
  });
  return { runtime, send, search, items, visited: (item: chrome.history.HistoryItem) => onVisited(item), removed: (event: chrome.history.RemovedResult) => onRemoved(event) };
}

test.each([false, true])('opening history refreshes local visits with remote sync enabled=%s', async enabled => {
  state.storage[HISTORY_SYNC_DOMAIN_ENABLED_KEY] = String(enabled);
  const scenario = setup();
  const module = new HistorySyncModule();
  await module.captureVisitedItem(state.session, scenario.items[0]);
  const response = await scenario.send('open');
  expect(response.page?.visits.map(v => v.title)).toEqual(['new', 'old']);
  expect(response.success).toBe(true);
  expect(state.bootstrap).toHaveBeenCalledTimes(enabled ? 1 : 0);
  expect(state.exchange).toHaveBeenCalledTimes(enabled ? 1 : 0);
  expect(state.refreshMembership).toHaveBeenCalledTimes(enabled ? 1 : 0);
});

test('native events keep a paused timeline current and explicit removals still queue for re-enablement', async () => {
  const scenario = setup();
  scenario.runtime.initialize();
  scenario.visited(scenario.items[1]);
  await vi.waitFor(async () => { expect((await scenario.send('list')).page?.total).toBe(1); });
  scenario.removed({ allHistory: false, urls: [scenario.items[1].url!] });
  await vi.waitFor(async () => { expect((await scenario.send('list')).page?.total).toBe(0); });
  expect(state.exchange).not.toHaveBeenCalled();
  expect(state.refreshMembership).not.toHaveBeenCalled();
  state.storage[HISTORY_SYNC_DOMAIN_ENABLED_KEY] = 'true';
  await scenario.send('sync');
  const uploaded = state.exchange.mock.calls.flatMap(([request]) => request.mutations);
  expect(uploaded.some(m => m.kind === 'delete_visit')).toBe(true);
  expect((await scenario.send('list')).page?.visits.some(v => v.title === 'new')).toBe(false);
});

test('turning sync off while native scanning is in flight prevents remote exchange', async () => {
  state.storage[HISTORY_SYNC_DOMAIN_ENABLED_KEY] = 'true';
  const scenario = setup();
  scenario.search.mockImplementation((_query, callback) => {
    state.storage[HISTORY_SYNC_DOMAIN_ENABLED_KEY] = 'false';
    callback(scenario.items);
  });
  const response = await scenario.send('open');
  expect(response.page?.total).toBe(2);
  expect(state.bootstrap).not.toHaveBeenCalled();
  expect(state.exchange).not.toHaveBeenCalled();
});

test('the desktop surface can page and search all 100,000 native visits independently of the sync mirror', async () => {
  const scenario = setup();
  const items = Array.from({ length: 100_000 }, (_, i) => ({
    id: String(i), url: `https://example.com/visit-${i}`, title: `Native title ${i}`,
    lastVisitTime: NOW - i - 1,
  }));
  const byUrl = new Map(items.map(item => [item.url, item]));
  scenario.search.mockImplementation((query, callback) => callback(items
    .filter(item => !query.text || item.title.includes(query.text))
    .slice(0, query.maxResults)));
  const getVisits = vi.fn(({ url }: chrome.history.UrlDetails, callback: (visits: chrome.history.VisitItem[]) => void) => {
    const item = byUrl.get(url)!;
    callback([{ id: item.id, visitId: item.id, visitTime: item.lastVisitTime, isLocal: true, transition: 'link', referringVisitId: '0' }]);
  });
  globalThis.chrome.history.getVisits = getVisits as unknown as typeof chrome.history.getVisits;
  const first = await scenario.send('list', undefined, { includeNative: true });
  expect(first.page?.visits).toHaveLength(200);
  expect(getVisits.mock.calls.length).toBeLessThan(1000);
  const beyondSyncLimit = await scenario.send('list', undefined, { includeNative: true, offset: 10_000, limit: 200 });
  expect(beyondSyncLimit.page?.visits).toHaveLength(200);
  expect(beyondSyncLimit.page?.visits[0].title).toBe('Native title 10000');
  const oldest = await scenario.send('list', undefined, { includeNative: true, query: 'Native title 99999' });
  expect(oldest.page?.visits.map(visit => visit.title)).toEqual(['Native title 99999']);
  const last = await scenario.send('list', undefined, { includeNative: true, offset: 99_800, limit: 200 });
  expect(last.page?.visits).toHaveLength(200);
  expect(last.page?.visits[199].title).toBe('Native title 99999');
  expect(last.page?.hasMore).toBe(false);
  const syncMirror = await new HistorySyncModule().listTimeline(state.session.uid);
  expect(syncMirror.total).toBe(0);
  expect(state.exchange).not.toHaveBeenCalled();
});

test('local history remains available without pairing or a supported sync provider', async () => {
  state.storage[LEAFTAB_SELECTED_SYNC_SOURCE_KEY] = 'webdav';
  const scenario = setup();
  const response = await scenario.send('open', undefined, { includeNative: true });
  expect(response.status).toBe('ready');
  expect(response.page?.visits.map(visit => visit.title)).toEqual(['new', 'old']);
  expect(state.bootstrap).not.toHaveBeenCalled();
  expect(state.exchange).not.toHaveBeenCalled();
});

test('opening the desktop surface does not wait for a background reconciliation', async () => {
  const scenario = setup();
  let finishScan!: () => void;
  scenario.search.mockImplementation((query, callback) => {
    if (query.maxResults === 10_000) finishScan = () => callback(scenario.items);
    else callback(scenario.items);
  });
  const response = await scenario.send('open', undefined, { includeNative: true });
  expect(response.page?.visits).toHaveLength(2);
  await vi.waitFor(() => expect(finishScan).toBeDefined());
  finishScan();
  await vi.waitFor(async () => expect((await new HistorySyncModule().listTimeline(state.session.uid)).total).toBe(2));
});

test('only an explicit native row removal deletes its URL, including outside sync retention', async () => {
  const scenario = setup();
  const deleteUrl = vi.fn(({ url }: chrome.history.UrlDetails, callback: () => void) => {
    scenario.items.splice(scenario.items.findIndex(item => item.url === url), 1);
    callback();
  });
  globalThis.chrome.history.deleteUrl = deleteUrl as unknown as typeof chrome.history.deleteUrl;
  const response = await scenario.send('list', undefined, { includeNative: true });
  expect(deleteUrl).not.toHaveBeenCalled();
  const after = await scenario.send('delete', response.page!.visits[0].visitId, { includeNative: true });
  expect(deleteUrl).toHaveBeenCalledTimes(1);
  expect(deleteUrl.mock.calls[0][0].url).toBe('https://example.com/new');
  expect(after.page?.visits.map(visit => visit.title)).toEqual(['old']);
  expect(state.exchange).not.toHaveBeenCalled();
});
