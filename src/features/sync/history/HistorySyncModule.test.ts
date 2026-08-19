import 'fake-indexeddb/auto';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { HistorySyncModule } from './HistorySyncModule';

const SESSION = {
  uid: 'history-test-account',
  deviceId: 'history-test-device',
  deviceName: 'Chrome test device',
  deviceCredential: 'test-credential',
};

describe('HistorySyncModule native capture', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  test('projects a local Chrome visit into the account timeline', async () => {
    const visitTime = Date.now() - 1_000;
    vi.stubGlobal('chrome', {
      history: {
        search: vi.fn().mockResolvedValue([
          {
            id: 'native-item-1',
            url: 'https://example.com/',
            title: 'Example',
            lastVisitTime: visitTime,
          },
        ]),
        getVisits: vi.fn().mockResolvedValue([
          {
            id: 'native-item-1',
            visitId: 'native-visit-1',
            referringVisitId: '0',
            transition: 'link',
            isLocal: true,
          },
        ]),
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
});
