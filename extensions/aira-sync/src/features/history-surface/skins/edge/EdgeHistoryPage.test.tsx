import 'fake-indexeddb/auto';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { EdgeHistoryPage } from './EdgeHistoryPage';
import { HistorySyncModule } from '@/features/sync/history/HistorySyncModule';
import type { HistorySyncDatabase } from '@/features/sync/history/HistorySyncDatabase';
import type { HistoryRuntimeMessage, HistoryRuntimeResponse } from '@/features/sync/history/historyMessages';

vi.mock('react-i18next', () => ({ useTranslation: () => ({ i18n: { language: 'en' } }) }));

const NOW = 1_793_584_800_000;
let accountNumber = 0;
let renderer: ReactTestRenderer | undefined;
let sendMessage: ReturnType<typeof vi.fn<(message: HistoryRuntimeMessage) => Promise<HistoryRuntimeResponse>>>;
const listNode = { scrollTop: 0, clientHeight: 400, scrollHeight: 5000, addEventListener: vi.fn(), removeEventListener: vi.fn() };

beforeEach(async () => {
  vi.stubGlobal('window', {
    location: { search: '' },
    matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} }),
  });
  vi.stubGlobal('document', { documentElement: { dataset: {} }, body: { classList: { add() {}, remove() {} } } });
  const module = new HistorySyncModule();
  const uid = `edge-surface-${++accountNumber}`;
  const database = (module as unknown as { database: HistorySyncDatabase }).database;
  await database.captureNativeVisits(uid, 'edge', 'Edge test', Array.from({ length: 601 }, (_, i) => ({
    nativeVisitId: String(i), url: `https://example.com/${i}`, title: `Synthetic title ${i}`,
    visitedAt: NOW - i - 1, transition: 'link',
  })), false, NOW);
  sendMessage = vi.fn(async message => ({
    success: true, status: 'ready', page: await module.listTimeline(uid, message),
  }));
  vi.stubGlobal('chrome', {
    runtime: { sendMessage },
    storage: { onChanged: { addListener() {}, removeListener() {} } },
  });
  listNode.scrollTop = 0;
  await act(async () => {
    renderer = create(<EdgeHistoryPage />, { createNodeMock: () => listNode });
  });
  await waitForRows(200);
});

afterEach(() => {
  act(() => renderer?.unmount());
  renderer = undefined;
  vi.unstubAllGlobals();
});

async function waitForRows(count: number) {
  await act(async () => {
    await vi.waitFor(() => {
      expect(renderer!.root.findAllByProps({ className: 'edge-history-row' })).toHaveLength(count);
    });
  });
}

test('search finds a visit outside the first 200 rows', async () => {
  await act(async () => {
    renderer!.root.findByType('input').props.onChange({ target: { value: 'Synthetic title 600' } });
  });
  await waitForRows(1);
  expect(sendMessage.mock.calls.some(([message]) => message.query === 'Synthetic title 600')).toBe(true);
  const row = renderer!.root.findByProps({ className: 'edge-history-row' });
  expect(row.findByProps({ className: 'title' }).children).toEqual(['Synthetic title 600']);
  expect(sendMessage.mock.calls.every(([message]) => message.includeNative === true)).toBe(true);
});

test('scrolling loads every page past both 200 and 500 records', async () => {
  for (const count of [400, 600, 601]) {
    await act(async () => {
      listNode.scrollTop = 4800;
      renderer!.root.findByProps({ className: 'edge-history-list' }).props.onScroll?.({ currentTarget: listNode });
      listNode.scrollTop = 0;
    });
    await waitForRows(count);
  }
  expect(sendMessage.mock.calls.some(([message]) => message.limit === 600)).toBe(true);
});
