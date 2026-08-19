import 'fake-indexeddb/auto';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { HistorySyncModule } from './HistorySyncModule';

const SESSION = {
  uid: 'history-test-account',
  deviceId: 'history-test-device',
  deviceName: 'Chrome test device',
  deviceCredential: 'test-credential',
};

const SESSION_MULTI = {
  ...SESSION,
  uid: 'history-test-account-multiple',
};

const SESSION_EVENT = {
  ...SESSION,
  uid: 'history-test-account-event',
};

describe('HistorySyncModule native capture', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test('projects a local Chrome visit into the account timeline', async () => {
    const visitTime = Date.now() - 1_000;
    vi.stubGlobal('chrome', {
      history: {
        search: vi.fn((
          _query: chrome.history.HistoryQuery,
          callback: (items: chrome.history.HistoryItem[]) => void,
        ) => callback([
          {
            id: 'native-item-1',
            url: 'https://example.com/',
            title: 'Example',
            lastVisitTime: visitTime,
          },
        ])),
        getVisits: vi.fn((
          _details: chrome.history.UrlDetails,
          callback: (visits: chrome.history.VisitItem[]) => void,
        ) => callback([
          {
            id: 'native-item-1',
            visitId: 'native-visit-1',
            referringVisitId: '0',
            transition: 'link',
            isLocal: true,
            visitTime,
          },
        ])),
      },
    });

    const module = new HistorySyncModule();
    await module.initialize();
    await module.reconcileNativeHistory(SESSION, true);

    const page = await module.listTimeline(SESSION.uid);
    expect(page.total).toBe(1);
    expect(page.visits[0]).toMatchObject({
      url: 'https://example.com/',
      title: 'Example',
      clientId: SESSION.deviceId,
      source: 'airatab_native',
    });
    expect(page.nativeDiagnostics).toMatchObject({
      historyApiAvailable: true,
      searchItemCount: 1,
      rawVisitCount: 1,
      draftCount: 1,
      changedCount: 1,
      invalidTimeCount: 0,
      error: '',
    });
  });

  test('does not copy one item timestamp across multiple visits without visit timestamps', async () => {
    const lastVisitTime = Date.now() - 1_000;
    vi.stubGlobal('chrome', {
      history: {
        search: vi.fn((_query, callback) => callback([{
          id: 'native-item-2',
          url: 'https://example.com/multiple',
          title: 'Example multiple',
          lastVisitTime,
        }])),
        getVisits: vi.fn((_details, callback) => callback([
          {
            id: 'native-item-2',
            visitId: 'native-visit-2a',
            referringVisitId: '0',
            transition: 'link',
            isLocal: true,
          },
          {
            id: 'native-item-2',
            visitId: 'native-visit-2b',
            referringVisitId: 'native-visit-2a',
            transition: 'link',
            isLocal: true,
          },
        ])),
      },
    });

    const module = new HistorySyncModule();
    await module.initialize();
    await module.reconcileNativeHistory(SESSION_MULTI, true);

    const page = await module.listTimeline(SESSION_MULTI.uid);
    expect(page.total).toBe(0);
    expect(page.nativeDiagnostics).toMatchObject({
      rawVisitCount: 2,
      draftCount: 0,
      invalidTimeCount: 2,
      approximateTimeCount: 2,
      completeReconciliation: false,
    });
  });

  test('captures one real event timestamp when getVisits omits timestamps', async () => {
    const lastVisitTime = Date.now() - 1_000;
    vi.stubGlobal('chrome', {
      history: {
        getVisits: vi.fn((_details, callback) => callback([
          {
            id: 'native-item-3',
            visitId: 'native-visit-3a',
            referringVisitId: '0',
            transition: 'link',
            isLocal: true,
          },
          {
            id: 'native-item-3',
            visitId: 'native-visit-3b',
            referringVisitId: 'native-visit-3a',
            transition: 'link',
            isLocal: true,
          },
        ])),
      },
    });

    const module = new HistorySyncModule();
    await module.initialize();
    const changed = await module.captureVisitedItem(SESSION_EVENT, {
      id: 'native-item-3',
      url: 'https://example.com/event',
      title: 'Example event',
      lastVisitTime,
    });

    expect(changed).toBe(1);
    const page = await module.listTimeline(SESSION_EVENT.uid);
    expect(page.visits[0]).toMatchObject({
      nativeVisitId: encodeURIComponent(`event:native-item-3:${lastVisitTime}`),
      visitedAt: lastVisitTime,
    });
  });
});
