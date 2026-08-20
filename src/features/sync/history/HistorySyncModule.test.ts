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

  test('does not enqueue two payloads for one native visit when capture and reconcile overlap', async () => {
    const visitTime = Date.now() - 1_000;
    const overlapSession = { ...SESSION, uid: 'history-test-account-overlap' };
    let historyReadCount = 0;
    vi.stubGlobal('chrome', {
      history: {
        search: vi.fn((_query, callback) => callback([{
          id: 'native-item-overlap',
          url: 'https://example.com/overlap',
          title: 'Reconciled title',
          lastVisitTime: visitTime,
        }])),
        getVisits: vi.fn((_details, callback) => {
          historyReadCount += 1;
          const title = historyReadCount === 1 ? 'Event title' : 'Reconciled title';
          queueMicrotask(() => callback([{
            id: 'native-item-overlap',
            visitId: 'native-overlap-1',
            referringVisitId: '0',
            transition: 'link',
            isLocal: true,
            visitTime,
            title,
          }]));
        }),
      },
    });

    const module = new HistorySyncModule();
    await module.initialize();
    await Promise.all([
      module.captureVisitedItem(overlapSession, {
        id: 'native-item-overlap',
        url: 'https://example.com/overlap',
        title: 'Event title',
        lastVisitTime: visitTime,
      }),
      module.reconcileNativeHistory(overlapSession, true),
    ]);

    const database = (module as unknown as {
      database: { listOutbox(accountUid: string, limit: number): Promise<unknown[]> };
    }).database;
    const outbox = await database.listOutbox(overlapSession.uid, 20) as Array<{
      kind?: string;
      visit?: { visitId?: string; title?: string };
    }>;
    const upserts = outbox.filter((mutation) => mutation.kind === 'upsert_visit');
    expect(upserts).toHaveLength(1);
    expect(upserts[0]?.visit?.visitId).toBe(
      `h1:${SESSION.deviceId}:${encodeURIComponent('native-overlap-1')}`,
    );
    expect(upserts[0]?.visit?.title).toBe('Event title');
  });

  test('keeps long native IDs canonical between visitId and nativeVisitId', async () => {
    const visitTime = Date.now() - 1_000;
    const longNativeVisitId = 'native-' + 'x'.repeat(700);
    const longSession = { ...SESSION, uid: 'history-test-account-long-id' };
    vi.stubGlobal('chrome', {
      history: {
        getVisits: vi.fn((_details, callback) => callback([{
          id: 'native-item-long',
          visitId: longNativeVisitId,
          referringVisitId: '0',
          transition: 'link',
          isLocal: true,
          visitTime,
        }])),
      },
    });

    const module = new HistorySyncModule();
    await module.initialize();
    await module.captureVisitedItem(longSession, {
      id: 'native-item-long',
      url: 'https://example.com/long-id',
      title: 'Long ID',
      lastVisitTime: visitTime,
    });

    const database = (module as unknown as {
      database: { listOutbox(accountUid: string, limit: number): Promise<unknown[]> };
    }).database;
    const outbox = await database.listOutbox(longSession.uid, 20) as Array<{
      visit?: { visitId?: string; nativeVisitId?: string };
    }>;
    expect(outbox[0]?.visit?.nativeVisitId).toBe(
      outbox[0]?.visit?.visitId?.slice(`h1:${SESSION.deviceId}:`.length),
    );
    expect(outbox[0]?.visit?.nativeVisitId?.length).toBeLessThanOrEqual(
      512 - `h1:${SESSION.deviceId}:`.length,
    );
  });

  test('keeps the first local visit when a remote retry has different metadata', async () => {
    const visitTime = Date.now() - 1_000;
    const projectionSession = { ...SESSION, uid: 'history-test-account-first-write' };
    vi.stubGlobal('chrome', {
      history: {
        getVisits: vi.fn((_details, callback) => callback([{
          id: 'native-item-first-write',
          visitId: 'native-first-write',
          referringVisitId: '0',
          transition: 'link',
          isLocal: true,
          visitTime,
        }])),
      },
    });

    const module = new HistorySyncModule();
    await module.initialize();
    await module.captureVisitedItem(projectionSession, {
      id: 'native-item-first-write',
      url: 'https://example.com/first-write',
      title: 'Local title',
      lastVisitTime: visitTime,
    });
    const database = (module as unknown as {
      database: {
        applyExchange(accountUid: string, clientId: string, response: unknown, now: number): Promise<number>;
      };
    }).database;
    await database.applyExchange(projectionSession.uid, projectionSession.deviceId, {
      acknowledgements: [],
      changes: [{
        seq: 1,
        kind: 'upsert_visit',
        visitId: `h1:${projectionSession.deviceId}:${encodeURIComponent('native-first-write')}`,
        visit: {
          visitId: `h1:${projectionSession.deviceId}:${encodeURIComponent('native-first-write')}`,
          clientId: projectionSession.deviceId,
          nativeVisitId: encodeURIComponent('native-first-write'),
          url: 'https://example.com/first-write',
          title: 'Remote title',
          visitedAt: visitTime + 1000,
          transition: 'typed',
          referrer: '',
          deviceName: 'Other device',
          source: 'airatab_native',
        },
      }],
      nextCursor: 1,
      headCursor: 1,
      hasMore: false,
    }, Date.now());

    const page = await module.listTimeline(projectionSession.uid);
    expect(page.visits[0]).toMatchObject({ title: 'Local title', visitedAt: visitTime });
  });
});
