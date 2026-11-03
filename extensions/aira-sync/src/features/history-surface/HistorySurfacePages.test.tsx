import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { afterEach, expect, test, vi } from 'vitest';
import { FirefoxHistoryPage } from './skins/firefox/FirefoxHistoryPage';
import { ZenHistoryPage } from './skins/zen/ZenHistoryPage';
import type { HistoryRuntimeMessage } from '@/features/sync/history/historyMessages';

vi.mock('react-i18next', () => ({ useTranslation: () => ({ i18n: { language: 'en' } }) }));
let renderer: ReactTestRenderer | undefined;
afterEach(() => { act(() => renderer?.unmount()); renderer = undefined; vi.unstubAllGlobals(); });

test.each([['firefox', FirefoxHistoryPage], ['zen', ZenHistoryPage]] as const)(
  '%s can load older pages and search beyond the initial page', async (skin, Page) => {
    vi.stubGlobal('window', { matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} }) });
    vi.stubGlobal('document', { documentElement: { dataset: {} }, body: { classList: { add() {}, remove() {} } } });
    const visits = Array.from({ length: 201 }, (_, index) => ({
      visitId: `native-${index}`, nativeVisitId: String(index), clientId: 'desktop',
      title: `Title ${index}`, url: `https://example.com/${index}`, visitedAt: Date.now() - index * 1000,
      deviceName: 'Desktop', source: 'browser-native', transition: 'link', referrer: '',
    }));
    const sendMessage = vi.fn(async (message: HistoryRuntimeMessage) => {
      const rows = visits.filter(visit => !message.query || visit.title === message.query);
      return { success: true, status: 'ready', page: {
        visits: rows.slice(0, message.limit), total: rows.length, hasMore: rows.length > (message.limit || 200),
        devices: [], lastSyncAt: 0, lastError: '',
      } };
    });
    vi.stubGlobal('chrome', { runtime: { sendMessage }, storage: { onChanged: { addListener() {}, removeListener() {} } } });
    await act(async () => { renderer = create(<Page />); });
    const rowCount = () => renderer!.root.findAll(node => typeof node.props.className === 'string' && node.props.className.split(' ').includes(`${skin}-history-row`)).length;
    expect(rowCount()).toBe(200);
    const loadMore = renderer!.root.findAllByType('button').find(button => button.children.includes('Load more'))!;
    await act(async () => loadMore.props.onClick());
    expect(rowCount()).toBe(201);
    await act(async () => renderer!.root.findByType('input').props.onChange({ target: { value: 'Title 200' } }));
    expect(rowCount()).toBe(1);
    expect(sendMessage.mock.calls.at(-1)?.[0]).toMatchObject({ includeNative: true, query: 'Title 200', limit: 200 });
  },
);
