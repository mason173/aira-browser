import {
  useCallback,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { useTranslation } from 'react-i18next';
import {
  ExternalLink,
  Globe2,
  History,
  Monitor,
  RefreshCw,
  Search,
  Trash2,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { toast } from '@/components/ui/sonner';
import {
  HISTORY_REVISION_STORAGE_KEY,
  sendHistoryRuntimeMessage,
  type HistoryCapabilityStatus,
} from './historyMessages';
import type {
  HistorySyncVisit,
  HistoryTimelinePage,
} from './HistorySyncModels';

const PAGE_SIZE = 200;

type HistoryViewState = {
  page: HistoryTimelinePage;
  status: HistoryCapabilityStatus;
};

const EMPTY_PAGE: HistoryTimelinePage = {
  visits: [],
  total: 0,
  devices: [],
  lastSyncAt: 0,
  lastError: '',
};

export function HistoryApp() {
  const { t, i18n } = useTranslation();
  const [query, setQuery] = useState('');
  const deferredQuery = useDeferredValue(query.trim());
  const [deviceId, setDeviceId] = useState('');
  const [state, setState] = useState<HistoryViewState>({
    page: EMPTY_PAGE,
    status: 'temporarily-unavailable',
  });
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [limit, setLimit] = useState(PAGE_SIZE);
  const requestId = useRef(0);
  const opened = useRef(false);

  const load = useCallback(async (action: 'open' | 'list' | 'sync' = 'list') => {
    const currentRequest = ++requestId.current;
    if (action === 'sync') setSyncing(true);
    else setLoading(true);
    try {
      const response = await sendHistoryRuntimeMessage({
        action,
        query: deferredQuery,
        deviceId,
        limit,
      });
      if (currentRequest !== requestId.current) return;
      if (response.page) {
        setState({ page: response.page, status: response.status });
      } else {
        setState((current) => ({ ...current, status: response.status }));
      }
      if (!response.success && response.error && action === 'sync') {
        toast.error(response.error);
      }
    } catch (error) {
      if (currentRequest === requestId.current) {
        toast.error(String((error as Error)?.message || error));
      }
    } finally {
      if (currentRequest === requestId.current) {
        setLoading(false);
        setSyncing(false);
      }
    }
  }, [deferredQuery, deviceId, limit]);

  useEffect(() => {
    if (!opened.current) {
      opened.current = true;
      void load('open');
      return;
    }
    void load('list');
  }, [load]);

  useEffect(() => {
    const listener = (changes: Record<string, chrome.storage.StorageChange>, areaName: string) => {
      if (areaName === 'local' && changes[HISTORY_REVISION_STORAGE_KEY]) {
        void load('list');
      }
    };
    globalThis.chrome?.storage?.onChanged?.addListener?.(listener);
    return () => globalThis.chrome?.storage?.onChanged?.removeListener?.(listener);
  }, [load]);

  const groupedVisits = useMemo(() => groupVisitsByDay(state.page.visits, i18n.language), [
    i18n.language,
    state.page.visits,
  ]);

  const deleteVisit = useCallback(async (visitId: string) => {
    const response = await sendHistoryRuntimeMessage({
      action: 'delete',
      visitId,
      query: deferredQuery,
      deviceId,
      limit,
    });
    if (!response.success) {
      toast.error(response.error || t('history.errors.delete', { defaultValue: 'Unable to delete this visit.' }));
      return;
    }
    if (response.page) setState({ page: response.page, status: response.status });
  }, [deferredQuery, deviceId, limit, t]);

  const clearHistory = useCallback(async () => {
    const confirmed = window.confirm(t('history.clear.confirm', {
      defaultValue: 'Clear the synchronized history for all devices?',
    }));
    if (!confirmed) return;
    const response = await sendHistoryRuntimeMessage({
      action: 'clear',
      query: deferredQuery,
      deviceId,
      limit,
    });
    if (!response.success) {
      toast.error(response.error || t('history.errors.clear', { defaultValue: 'Unable to clear history.' }));
      return;
    }
    if (response.page) setState({ page: response.page, status: response.status });
  }, [deferredQuery, deviceId, limit, t]);

  return (
    <main className="min-h-screen bg-background text-foreground [font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe_UI',sans-serif]">
      <header className="sticky top-0 z-20 border-b border-border bg-background/95 backdrop-blur">
        <div className="mx-auto flex min-h-16 max-w-6xl items-center gap-3 px-4 sm:px-6">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[8px] bg-primary text-primary-foreground">
            <History className="size-5" aria-hidden="true" />
          </span>
          <div className="min-w-0 flex-1">
            <h1 className="truncate text-base font-semibold leading-6">
              {t('history.title', { defaultValue: 'Aira History' })}
            </h1>
            <p className="truncate text-xs leading-4 text-muted-foreground">
              {formatSyncStatus(state.status, state.page.lastSyncAt, i18n.language, t)}
            </p>
          </div>
          <Button
            type="button"
            variant="outline"
            size="icon"
            className="h-9 w-9 rounded-[8px]"
            disabled={syncing}
            onClick={() => void load('sync')}
            title={t('history.actions.sync', { defaultValue: 'Sync now' })}
            aria-label={t('history.actions.sync', { defaultValue: 'Sync now' })}
          >
            <RefreshCw className={`size-4 ${syncing ? 'animate-spin' : ''}`} aria-hidden="true" />
          </Button>
          <Button
            type="button"
            variant="outline"
            size="icon"
            className="h-9 w-9 rounded-[8px] text-destructive hover:text-destructive"
            disabled={state.page.total <= 0}
            onClick={() => void clearHistory()}
            title={t('history.actions.clear', { defaultValue: 'Clear history' })}
            aria-label={t('history.actions.clear', { defaultValue: 'Clear history' })}
          >
            <Trash2 className="size-4" aria-hidden="true" />
          </Button>
        </div>
      </header>

      <section className="mx-auto max-w-6xl px-4 py-4 sm:px-6">
        <div className="grid gap-3 border-b border-border pb-4 sm:grid-cols-[minmax(0,1fr)_240px]">
          <label className="relative block">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
            <input
              type="search"
              value={query}
              onChange={(event) => {
                setQuery(event.target.value);
                setLimit(PAGE_SIZE);
              }}
              placeholder={t('history.search.placeholder', { defaultValue: 'Search history' })}
              className="h-10 w-full rounded-[8px] border border-input bg-input-background pl-9 pr-3 text-sm outline-none focus:ring-2 focus:ring-ring/40"
            />
          </label>
          <label className="relative block">
            <Monitor className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
            <select
              value={deviceId}
              onChange={(event) => {
                setDeviceId(event.target.value);
                setLimit(PAGE_SIZE);
              }}
              className="h-10 w-full appearance-none rounded-[8px] border border-input bg-input-background pl-9 pr-8 text-sm outline-none focus:ring-2 focus:ring-ring/40"
              aria-label={t('history.devices.label', { defaultValue: 'Device' })}
            >
              <option value="">{t('history.devices.all', { defaultValue: 'All devices' })}</option>
              {state.page.devices.map((device) => (
                <option key={device.id} value={device.id}>{device.name}</option>
              ))}
            </select>
          </label>
        </div>

        {state.page.lastError ? (
          <div className="mt-4 border-l-2 border-destructive px-3 py-2 text-sm text-destructive">
            {state.page.lastError}
          </div>
        ) : null}

        {state.status === 'login-required' ? (
          <EmptyState
            icon={<Monitor className="size-6" />}
            title={t('history.states.login', { defaultValue: 'Connect this desktop to Aira' })}
          />
        ) : loading && state.page.visits.length <= 0 ? (
          <EmptyState
            icon={<RefreshCw className="size-6 animate-spin" />}
            title={t('history.states.loading', { defaultValue: 'Loading history' })}
          />
        ) : state.page.visits.length <= 0 ? (
          <EmptyState
            icon={<History className="size-6" />}
            title={t('history.states.empty', { defaultValue: 'No history found' })}
          />
        ) : (
          <div className="pt-2">
            {groupedVisits.map((group) => (
              <section key={group.label} className="py-3">
                <h2 className="mb-2 text-xs font-semibold leading-5 text-muted-foreground">
                  {group.label}
                </h2>
                <div className="border-y border-border">
                  {group.visits.map((visit) => (
                    <HistoryRow
                      key={visit.visitId}
                      visit={visit}
                      language={i18n.language}
                      onDelete={deleteVisit}
                    />
                  ))}
                </div>
              </section>
            ))}
            {state.page.visits.length < state.page.total ? (
              <div className="flex justify-center py-4">
                <Button
                  type="button"
                  variant="outline"
                  className="h-9 rounded-[8px] px-4"
                  onClick={() => setLimit((current) => current + PAGE_SIZE)}
                >
                  {t('history.actions.more', { defaultValue: 'Load more' })}
                </Button>
              </div>
            ) : null}
          </div>
        )}
      </section>
    </main>
  );
}

function HistoryRow({
  visit,
  language,
  onDelete,
}: {
  visit: HistorySyncVisit;
  language: string;
  onDelete: (visitId: string) => Promise<void>;
}) {
  const { t } = useTranslation();
  const host = safeHostname(visit.url);
  const openVisit = () => {
    const tabs = globalThis.chrome?.tabs;
    if (tabs?.create) void tabs.create({ url: visit.url, active: true });
    else window.open(visit.url, '_blank', 'noopener,noreferrer');
  };
  return (
    <article className="group grid min-h-16 grid-cols-[minmax(0,1fr)_auto] items-center gap-3 border-b border-border py-2.5 last:border-b-0 [content-visibility:auto]">
      <button type="button" className="min-w-0 text-left" onClick={openVisit}>
        <span className="flex min-w-0 items-center gap-2">
          <Globe2 className="size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
          <span className="truncate text-sm font-medium leading-5 text-foreground">
            {visit.title || host || visit.url}
          </span>
          <ExternalLink className="size-3.5 shrink-0 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100" aria-hidden="true" />
        </span>
        <span className="mt-1 flex min-w-0 items-center gap-2 pl-6 text-xs leading-4 text-muted-foreground">
          <span className="truncate">{host || visit.url}</span>
          <span aria-hidden="true">·</span>
          <time className="shrink-0">{formatVisitTime(visit.visitedAt, language)}</time>
          <span aria-hidden="true">·</span>
          <span className="shrink-0 truncate">{visit.deviceName || visit.clientId}</span>
        </span>
      </button>
      <Button
        type="button"
        variant="ghost"
        size="icon"
        className="h-8 w-8 rounded-[8px] text-muted-foreground hover:text-destructive"
        onClick={() => void onDelete(visit.visitId)}
        title={t('history.actions.delete', { defaultValue: 'Delete visit' })}
        aria-label={t('history.actions.delete', { defaultValue: 'Delete visit' })}
      >
        <Trash2 className="size-4" aria-hidden="true" />
      </Button>
    </article>
  );
}

function EmptyState({ icon, title }: { icon: React.ReactNode; title: string }) {
  return (
    <div className="flex min-h-72 flex-col items-center justify-center gap-3 text-center text-muted-foreground">
      <span className="flex h-12 w-12 items-center justify-center rounded-[8px] bg-muted">{icon}</span>
      <p className="text-sm font-medium leading-5">{title}</p>
    </div>
  );
}

function groupVisitsByDay(visits: HistorySyncVisit[], language: string) {
  const formatter = new Intl.DateTimeFormat(language, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'short',
  });
  const groups = new Map<string, HistorySyncVisit[]>();
  visits.forEach((visit) => {
    const label = formatter.format(new Date(visit.visitedAt));
    const group = groups.get(label) || [];
    group.push(visit);
    groups.set(label, group);
  });
  return Array.from(groups, ([label, grouped]) => ({ label, visits: grouped }));
}

function formatVisitTime(timestamp: number, language: string): string {
  return new Intl.DateTimeFormat(language, { hour: '2-digit', minute: '2-digit' })
    .format(new Date(timestamp));
}

function formatSyncStatus(
  status: HistoryCapabilityStatus,
  lastSyncAt: number,
  language: string,
  t: ReturnType<typeof useTranslation>['t'],
): string {
  if (status === 'login-required') return t('history.status.login', { defaultValue: 'Not connected' });
  if (status === 'pro-required') return t('history.status.pro', { defaultValue: 'Pro required' });
  if (status === 'temporarily-unavailable') return t('history.status.unavailable', { defaultValue: 'Temporarily unavailable' });
  if (lastSyncAt <= 0) return t('history.status.pending', { defaultValue: 'Waiting for first sync' });
  return t('history.status.synced', {
    defaultValue: 'Synced {{time}}',
    time: new Intl.DateTimeFormat(language, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    }).format(new Date(lastSyncAt)),
  });
}

function safeHostname(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return '';
  }
}
