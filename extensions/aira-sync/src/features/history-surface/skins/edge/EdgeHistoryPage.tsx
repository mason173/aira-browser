import { useCallback, useEffect, useMemo, useRef, useState, type MouseEvent } from 'react';
import { useTranslation } from 'react-i18next';
import type { HistorySyncVisit } from '@/features/sync/history/HistorySyncModels';
import {
  historyFaviconUrl,
  historyRemoveLabel,
  historyHostname,
  useHistorySurfaceData,
} from '../../useHistorySurfaceData';
import { useChromeOtherDeviceTabs } from '../chrome/useChromeOtherDeviceTabs';
import {
  edgeHistoryCopy,
  edgeHistorySearchPlaceholder,
  type EdgeHistorySection,
} from './edgeHistorySpec';
import {
  restoreEdgeSession,
  useEdgeRecentlyClosed,
  type EdgeClosedEntry,
} from './useEdgeRecentlyClosed';
import { formatChromeHistoryDay, formatChromeHistoryTime } from '../chrome/chromeHistorySpec';
import { rememberEdgeHistoryWindow, requestEdgeHistoryDock } from './edgeHistoryDock';
import { HistoryLoadMore } from '../../HistoryLoadMore';
import './edge-history.css';

type EdgeMenuState = {
  x: number;
  y: number;
  url: string;
  visitId: string;
};

export function EdgeHistoryPage() {
  const { i18n } = useTranslation();
  const copy = edgeHistoryCopy(i18n.language, globalThis.navigator?.platform || '');
  const data = useHistorySurfaceData();
  const [section, setSection] = useState<EdgeHistorySection>('all');
  const { query, setQuery } = data;
  const listRef = useRef<HTMLDivElement>(null);
  const [theme, setTheme] = useState<'light' | 'dark'>(readEdgeTheme);
  const [menu, setMenu] = useState<EdgeMenuState | null>(null);
  const [hubMenu, setHubMenu] = useState(false);
  const [showDuplicates, setShowDuplicates] = useState(false);
  const docked = new URLSearchParams(window.location.search).get('dock') === '1';
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const closed = useEdgeRecentlyClosed(section === 'closed');
  const devices = useChromeOtherDeviceTabs(section === 'devices');

  useEffect(() => {
    rememberEdgeHistoryWindow();
  }, []);

  useEffect(() => {
    document.title = copy.title;
    document.documentElement.dataset.edgeTheme = theme;
    document.body.classList.add('edge-history-body');
    return () => {
      document.body.classList.remove('edge-history-body');
      delete document.documentElement.dataset.edgeTheme;
    };
  }, [copy.title, theme]);

  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const apply = () => setTheme(readEdgeTheme());
    media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, []);

  const filteredVisits = useMemo(() => {
    return showDuplicates ? data.visits : uniqueByUrl(data.visits);
  }, [data.visits, showDuplicates]);
  const groups = useMemo(
    () => groupVisits(filteredVisits, i18n.language),
    [filteredVisits, i18n.language],
  );

  const loadNearBottom = useCallback((list: HTMLDivElement | null) => {
    if (!list || section !== 'all' || data.loading || !data.hasMore) return;
    if (list.scrollTop + list.clientHeight >= list.scrollHeight - 240) data.loadMore();
  }, [section, data.loading, data.hasMore, data.loadMore]);

  useEffect(() => {
    // URL deduplication can leave a page too short to scroll. Fill the viewport
    // from subsequent pages as well as responding to explicit scrolling.
    loadNearBottom(listRef.current);
  }, [loadNearBottom, filteredVisits.length]);

  const openUrl = (url: string, mode: 'tab' | 'window' | 'private' = 'tab') => {
    if (!url) return;
    if (mode === 'window' || mode === 'private') {
      const windows = globalThis.chrome?.windows;
      if (windows?.create) {
        void windows.create({ url, incognito: mode === 'private', focused: true }).catch(() => {
          void globalThis.chrome?.tabs?.create({ url, active: true });
        });
        return;
      }
    }
    if (globalThis.chrome?.tabs?.create) void globalThis.chrome.tabs.create({ url, active: true });
    else window.open(url, '_blank', 'noopener,noreferrer');
  };

  const openMenu = (event: MouseEvent, url: string, visitId = '') => {
    event.preventDefault();
    const width = 260;
    const height = 280;
    const x = Math.min(event.clientX, window.innerWidth - width - 8);
    const y = Math.min(event.clientY, window.innerHeight - height - 8);
    setMenu({ x: Math.max(8, x), y: Math.max(8, y), url, visitId });
  };

  return (
    <div className="edge-history" data-edge-theme={theme} onClick={() => { setMenu(null); setHubMenu(false); }}>
      <header className="edge-history-header">
        <h1>{copy.title}</h1>
        <div className="edge-history-tools">
          <button type="button" className="edge-history-icon" aria-label={copy.clearData} onClick={(event) => { event.stopPropagation(); openClearData(); }}>
            <TrashIcon />
          </button>
          <button
            type="button"
            className={`edge-history-icon${hubMenu ? ' is-open' : ''}`}
            aria-label={copy.more}
            aria-expanded={hubMenu}
            onClick={(event) => {
              event.stopPropagation();
              setMenu(null);
              setHubMenu((open) => !open);
            }}
          >
            <MoreIcon />
          </button>
          <button
            type="button"
            className={`edge-history-icon${docked ? ' is-open' : ''}`}
            aria-label={docked ? copy.unpin : copy.pin}
            aria-pressed={docked}
            onClick={(event) => {
              event.stopPropagation();
              requestEdgeHistoryDock(docked);
            }}
          >
            <PinIcon />
          </button>
          {hubMenu ? (
            <div className="edge-history-hub-menu" onClick={(event) => event.stopPropagation()}>
              <button type="button" onClick={() => { setHubMenu(false); openHistoryPage(); }}>
                <OpenIcon />
                <span>{copy.openHistoryPage}</span>
              </button>
              <button type="button" onClick={() => { setHubMenu(false); void exportBrowsingData(); }}>
                <ExportIcon />
                <span>{copy.exportData}</span>
              </button>
              <div className="edge-history-hub-separator" />
              <button type="button" onClick={() => { setShowDuplicates((current) => !current); setHubMenu(false); }}>
                <span>{copy.showDuplicates}</span>
              </button>
            </div>
          ) : null}
        </div>
      </header>
      <form className="edge-history-search" role="search" onSubmit={(event) => event.preventDefault()}>
        <SearchIcon />
        <input
          type="search"
          value={query}
          placeholder={edgeHistorySearchPlaceholder(section, copy)}
          aria-label={edgeHistorySearchPlaceholder(section, copy)}
          onChange={(event) => setQuery(event.target.value)}
        />
      </form>
      <div className="edge-history-tabs" role="tablist">
        {(['all', 'closed', 'devices'] as const).map((item) => (
          <button
            key={item}
            type="button"
            role="tab"
            className={section === item ? 'is-selected' : undefined}
            aria-selected={section === item}
            onClick={() => setSection(item)}
          >
            {item === 'all' ? copy.all : item === 'closed' ? copy.closed : copy.devices}
          </button>
        ))}
      </div>
      <div className="edge-history-list" ref={listRef} onScroll={(event) => loadNearBottom(event.currentTarget)}>
        {section === 'all' ? (
          data.status === 'login-required' ? <p className="edge-history-status">{copy.login}</p>
            : data.loading && groups.length === 0 ? <p className="edge-history-status">{copy.loading}</p>
              : groups.length === 0 ? <p className="edge-history-status">{copy.empty}</p>
                : groups.map((group) => (
                  <section key={group.label}>
                    <h2 className="edge-history-day">{group.label}</h2>
                    {group.visits.map((visit) => (
                      <div
                        key={visit.visitId}
                        className="edge-history-row"
                        onClick={() => openUrl(visit.url)}
                        onContextMenu={(event) => openMenu(event, visit.url, visit.visitId)}
                      >
                        <Favicon url={visit.url} />
                        <span className="title">{visit.title || historyHostname(visit.url) || visit.url}</span>
                        <span className="edge-history-time">{formatChromeHistoryTime(visit.visitedAt, i18n.language)}</span>
                        <button
                          type="button"
                          className="edge-history-remove"
                          aria-label={historyRemoveLabel(visit.visitId, i18n.language, copy.remove)} title={historyRemoveLabel(visit.visitId, i18n.language, copy.remove)}
                          onClick={(event) => {
                            event.stopPropagation();
                            void data.deleteVisit(visit.visitId);
                          }}
                        >
                          <DismissIcon />
                        </button>
                      </div>
                    ))}
                  </section>
                ))
        ) : null}
        {section === 'all' ? <HistoryLoadMore {...data} language={i18n.language} /> : null}
        {section === 'closed' ? (
          <ClosedList
            copy={copy}
            entries={filterClosed(closed.entries, query)}
            loading={closed.loading}
            expanded={expanded}
            onToggle={(id) => setExpanded((current) => ({ ...current, [id]: !current[id] }))}
          />
        ) : null}
        {section === 'devices' ? (
          <DeviceList
            copy={copy}
            devices={devices.devices}
            loading={devices.loading}
            error={devices.error}
            query={query}
            onOpen={openUrl}
          />
        ) : null}
      </div>
      {menu ? (
        <div className="edge-history-menu" style={{ left: menu.x, top: menu.y }} onClick={(event) => event.stopPropagation()}>
          <button type="button" onClick={() => { openUrl(menu.url); setMenu(null); }}><TabIcon />{copy.openTab}</button>
          <button type="button" onClick={() => { openUrl(menu.url, 'window'); setMenu(null); }}><WindowIcon />{copy.openWindow}</button>
          <button type="button" onClick={() => { openUrl(menu.url, 'private'); setMenu(null); }}><PrivateIcon />{copy.openPrivate}</button>
          <div className="divider" />
          <button type="button" onClick={() => { void navigator.clipboard?.writeText(menu.url); setMenu(null); }}><CopyIcon />{copy.copyLink}</button>
          <button type="button" onClick={() => { if (menu.visitId) void data.deleteVisit(menu.visitId); setMenu(null); }}><TrashIcon />{historyRemoveLabel(menu.visitId, i18n.language, copy.remove)}</button>
          <div className="divider" />
          <button
            type="button"
            className="site-more"
            onClick={() => {
              setSection('all');
              setQuery(historyHostname(menu.url));
              setMenu(null);
            }}
          >{copy.moreFromSite}</button>
        </div>
      ) : null}
    </div>
  );
}

function ClosedList({
  copy,
  entries,
  loading,
  expanded,
  onToggle,
}: {
  copy: ReturnType<typeof edgeHistoryCopy>;
  entries: EdgeClosedEntry[];
  loading: boolean;
  expanded: Record<string, boolean>;
  onToggle: (id: string) => void;
}) {
  if (loading && entries.length === 0) return <p className="edge-history-status">{copy.loading}</p>;
  if (entries.length === 0) return <p className="edge-history-status">{copy.emptyClosed}</p>;
  return (
    <>
      {entries.map((entry, index) => {
        const grouped = entry.tabs.length > 1;
        const title = grouped ? `${entry.title} ${copy.andMore(entry.tabs.length - 1)}` : entry.title;
        return (
          <div key={entry.id}>
            <button
              type="button"
              className="edge-history-closed"
              onClick={() => grouped ? onToggle(entry.id) : restoreEdgeSession(entry.sessionId, entry.url)}
            >
              {grouped ? <ChevronIcon open={expanded[entry.id] === true} /> : <Favicon url={entry.url} />}
              <span className="title">{title}</span>
              <span className="edge-history-hint">{index === 0 && !grouped ? copy.reopenHint : ''}</span>
            </button>
            {grouped && expanded[entry.id] ? entry.tabs.map((tab) => (
              <button
                key={tab.sessionId || tab.url}
                type="button"
                className="edge-history-closed is-child"
                onClick={() => restoreEdgeSession(tab.sessionId, tab.url)}
              >
                <Favicon url={tab.url} />
                <span className="title">{tab.title || tab.url}</span>
                <span />
              </button>
            )) : null}
          </div>
        );
      })}
    </>
  );
}

function DeviceList({
  copy,
  devices,
  loading,
  error,
  query,
  onOpen,
}: {
  copy: ReturnType<typeof edgeHistoryCopy>;
  devices: ReturnType<typeof useChromeOtherDeviceTabs>['devices'];
  loading: boolean;
  error: string;
  query: string;
  onOpen: (url: string) => void;
}) {
  const needle = query.trim().toLowerCase();
  const visible = devices.map((device) => ({
    ...device,
    tabs: device.tabs.filter((tab) => !needle || `${tab.title} ${tab.url}`.toLowerCase().includes(needle)),
  })).filter((device) => device.tabs.length > 0);
  if (loading && visible.length === 0) return <p className="edge-history-status">{copy.loading}</p>;
  if (error && visible.length === 0) return <p className="edge-history-status">{error}</p>;
  if (visible.length === 0) return <p className="edge-history-status">{copy.emptyDevices}</p>;
  return (
    <>
      {visible.map((device) => (
        <section key={device.deviceId}>
          <h2 className="edge-history-day">{device.deviceName || device.model || device.platform}</h2>
          {device.tabs.map((tab, index) => (
            <button
              key={`${device.deviceId}:${tab.url}:${index}`}
              type="button"
              className="edge-history-row"
              onClick={() => onOpen(tab.url)}
            >
              <Favicon url={tab.url} />
              <span className="title">{tab.title || historyHostname(tab.url) || tab.url}</span>
              <span />
            </button>
          ))}
        </section>
      ))}
    </>
  );
}

function readEdgeTheme(): 'light' | 'dark' {
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function openClearData(): void {
  const url = 'edge://settings/clearBrowserData';
  const tabs = globalThis.chrome?.tabs;
  if (!tabs?.create) {
    window.location.assign(url);
    return;
  }
  tabs.create({ url }, () => {
    if (globalThis.chrome?.runtime?.lastError) window.location.assign(url);
  });
}

function openHistoryPage(): void {
  const url = globalThis.chrome?.runtime?.getURL?.('history-override.html') || 'history-override.html';
  if (globalThis.chrome?.tabs?.create) void globalThis.chrome.tabs.create({ url, active: true });
  else window.open(url, '_blank', 'noopener,noreferrer');
}

async function exportBrowsingData(): Promise<void> {
  const historyApi = globalThis.chrome?.history;
  const items = historyApi?.search
    ? await new Promise<chrome.history.HistoryItem[]>((resolve) => {
      historyApi.search({ text: '', startTime: 0, maxResults: 10000 }, (result) => resolve(result || []));
    })
    : [];
  const rows = ['Date,Title,URL', ...items.map((item) => {
    const when = item.lastVisitTime ? new Date(item.lastVisitTime).toISOString() : '';
    return [when, item.title || '', item.url || ''].map(csvCell).join(',');
  })];
  const blob = new Blob([rows.join('\n')], { type: 'text/csv;charset=utf-8' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = 'edge-history.csv';
  link.click();
  URL.revokeObjectURL(link.href);
}

function csvCell(value: string): string {
  return `"${value.replace(/"/g, '""')}"`;
}

function uniqueByUrl(visits: HistorySyncVisit[]): HistorySyncVisit[] {
  const seen = new Set<string>();
  return visits.filter((visit) => {
    if (seen.has(visit.url)) return false;
    seen.add(visit.url);
    return true;
  });
}

function filterClosed(entries: EdgeClosedEntry[], query: string): EdgeClosedEntry[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return entries;
  return entries.filter((entry) => `${entry.title} ${entry.url} ${entry.tabs.map((tab) => `${tab.title} ${tab.url}`).join(' ')}`.toLowerCase().includes(needle));
}

function groupVisits(visits: HistorySyncVisit[], language: string) {
  const groups = new Map<string, HistorySyncVisit[]>();
  visits.forEach((visit) => {
    const label = formatChromeHistoryDay(visit.visitedAt, language);
    const group = groups.get(label) || [];
    group.push(visit);
    groups.set(label, group);
  });
  return Array.from(groups, ([label, grouped]) => ({ label, visits: grouped }));
}

function Favicon({ url }: { url: string }) {
  const [failed, setFailed] = useState(false);
  const src = historyFaviconUrl(url);
  if (!src || failed) return <GlobeIcon />;
  return <img className="edge-history-favicon" src={src} alt="" onError={() => setFailed(true)} />;
}

function FluentIcon({ size, className, path }: { size: number; className?: string; path: string }) {
  return (
    <svg className={className} width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
      <path fill="currentColor" d={path} />
    </svg>
  );
}

function SearchIcon() {
  return <FluentIcon size={16} path="M11.0195 11.7266C10.0658 12.5217 8.83875 13 7.5 13C4.46243 13 2 10.5376 2 7.5C2 4.46243 4.46243 2 7.5 2C10.5376 2 13 4.46243 13 7.5C13 8.83875 12.5217 10.0658 11.7266 11.0195L14.8535 14.1464C15.0488 14.3417 15.0488 14.6583 14.8535 14.8536C14.6583 15.0488 14.3417 15.0488 14.1464 14.8536L11.0195 11.7266ZM12 7.5C12 5.01472 9.98528 3 7.5 3C5.01472 3 3 5.01472 3 7.5C3 9.98528 5.01472 12 7.5 12C9.98528 12 12 9.98528 12 7.5Z" />;
}

function TrashIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
      <path fill="currentColor" d="M8.5 4H11.5C11.5 3.17157 10.8284 2.5 10 2.5C9.17157 2.5 8.5 3.17157 8.5 4ZM7.5 4C7.5 2.61929 8.61929 1.5 10 1.5C11.3807 1.5 12.5 2.61929 12.5 4H17.5C17.7761 4 18 4.22386 18 4.5C18 4.77614 17.7761 5 17.5 5H16.4456L15.2521 15.3439C15.0774 16.8576 13.7957 18 12.2719 18H7.72813C6.20431 18 4.92256 16.8576 4.7479 15.3439L3.55437 5H2.5C2.22386 5 2 4.77614 2 4.5C2 4.22386 2.22386 4 2.5 4H7.5ZM5.74131 15.2292C5.85775 16.2384 6.71225 17 7.72813 17H12.2719C13.2878 17 14.1422 16.2384 14.2587 15.2292L15.439 5H4.56101L5.74131 15.2292ZM8.5 7.5C8.77614 7.5 9 7.72386 9 8V14C9 14.2761 8.77614 14.5 8.5 14.5C8.22386 14.5 8 14.2761 8 14V8C8 7.72386 8.22386 7.5 8.5 7.5ZM12 8C12 7.72386 11.7761 7.5 11.5 7.5C11.2239 7.5 11 7.72386 11 8V14C11 14.2761 11.2239 14.5 11.5 14.5C11.7761 14.5 12 14.2761 12 14V8Z" />
    </svg>
  );
}

function MoreIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
      <path fill="currentColor" d="M6.25 10C6.25 10.6904 5.69036 11.25 5 11.25C4.30964 11.25 3.75 10.6904 3.75 10C3.75 9.30964 4.30964 8.75 5 8.75C5.69036 8.75 6.25 9.30964 6.25 10ZM11.25 10C11.25 10.6904 10.6904 11.25 10 11.25C9.30964 11.25 8.75 10.6904 8.75 10C8.75 9.30964 9.30964 8.75 10 8.75C10.6904 8.75 11.25 9.30964 11.25 10ZM15 11.25C15.6904 11.25 16.25 10.6904 16.25 10C16.25 9.30964 15.6904 8.75 15 8.75C14.3096 8.75 13.75 9.30964 13.75 10C13.75 10.6904 14.3096 11.25 15 11.25Z" />
    </svg>
  );
}

function PinIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" aria-hidden="true">
      <path fill="currentColor" d="M10.1221 3.13715C10.7326 1.91616 12.3599 1.65208 13.3251 2.61737L17.382 6.67419C18.3472 7.63947 18.0832 9.26676 16.8622 9.87726L13.4037 11.6065C13.0751 11.7708 12.8183 12.0499 12.6818 12.391L11.2459 15.981C10.9792 16.6476 10.1179 16.8244 9.61027 16.3167L7 13.7064L3.70711 16.9993H3V16.2922L6.29289 12.9993L3.68262 10.3891C3.17498 9.88142 3.35177 9.02011 4.01834 8.75348L7.60829 7.3175C7.94939 7.18106 8.22855 6.92419 8.39285 6.5956L10.1221 3.13715ZM12.618 3.32447C12.1354 2.84183 11.3217 2.97387 11.0165 3.58437L9.28727 7.04282C9.01345 7.59046 8.54818 8.01858 7.97968 8.24598L4.38973 9.68196L10.3174 15.6096L11.7534 12.0197C11.9808 11.4512 12.4089 10.9859 12.9565 10.7121L16.415 8.98283C17.0255 8.67758 17.1575 7.86394 16.6749 7.3813L12.618 3.32447Z" />
    </svg>
  );
}

function OpenIcon() {
  return <FluentIcon size={16} path="M4.49999 3C3.67157 3 3 3.67157 3 4.5V11.5C3 12.3284 3.67157 13 4.49999 13H11.5C12.3284 13 12.9999 12.3284 12.9999 11.5V9.26923C12.9999 8.99309 13.2238 8.76923 13.4999 8.76923C13.7761 8.76923 13.9999 8.99309 13.9999 9.26923V11.5C13.9999 12.8807 12.8807 14 11.5 14H4.49999C3.11928 14 2 12.8807 2 11.5V4.5C2 3.11929 3.11928 2 4.49999 2H6.73075C7.00689 2 7.23074 2.22386 7.23074 2.5C7.23074 2.77614 7.00689 3 6.73075 3H4.49999ZM8.76926 2.5C8.76926 2.22386 8.99311 2 9.26925 2H13.5C13.7761 2 14 2.22386 14 2.5V6.73077C14 7.00691 13.7761 7.23077 13.5 7.23077C13.2239 7.23077 13 7.00691 13 6.73077V3.70711L9.6228 7.08433C9.42754 7.27959 9.11096 7.27959 8.9157 7.08433C8.72044 6.88906 8.72044 6.57248 8.9157 6.37722L12.2929 3H9.26925C8.99311 3 8.76926 2.77614 8.76926 2.5Z" />;
}

function ExportIcon() {
  return <FluentIcon size={16} path="M1.5 3C1.77614 3 2 3.22386 2 3.5V12C2 12.2761 1.77614 12.5 1.5 12.5C1.22386 12.5 1 12.2761 1 12V3.5C1 3.22386 1.22386 3 1.5 3ZM10.6464 3.64645C10.8417 3.45118 11.1583 3.45118 11.3536 3.64645L14.8536 7.14645C15.0488 7.34171 15.0488 7.65829 14.8536 7.85355L11.3536 11.3536C11.1583 11.5488 10.8417 11.5488 10.6464 11.3536C10.4512 11.1583 10.4512 10.8417 10.6464 10.6464L13.2929 8H4.5C4.22386 8 4 7.77614 4 7.5C4 7.22386 4.22386 7 4.5 7H13.2929L10.6464 4.35355C10.4512 4.15829 10.4512 3.84171 10.6464 3.64645Z" />;
}

function DismissIcon() {
  return <FluentIcon size={16} path="M2.58859 2.71569L2.64645 2.64645C2.82001 2.47288 3.08944 2.4536 3.28431 2.58859L3.35355 2.64645L8 7.293L12.6464 2.64645C12.8417 2.45118 13.1583 2.45118 13.3536 2.64645C13.5488 2.84171 13.5488 3.15829 13.3536 3.35355L8.707 8L13.3536 12.6464C13.5271 12.82 13.5464 13.0894 13.4114 13.2843L13.3536 13.3536C13.18 13.5271 12.9106 13.5464 12.7157 13.4114L12.6464 13.3536L8 8.707L3.35355 13.3536C3.15829 13.5488 2.84171 13.5488 2.64645 13.3536C2.45118 13.1583 2.45118 12.8417 2.64645 12.6464L7.293 8L2.64645 3.35355C2.47288 3.17999 2.4536 2.91056 2.58859 2.71569L2.64645 2.64645L2.58859 2.71569Z" />;
}

function GlobeIcon() {
  return <FluentIcon className="edge-history-favicon" size={16} path="M8 14C11.3137 14 14 11.3137 14 8C14 4.68629 11.3137 2 8 2C4.68629 2 2 4.68629 2 8C2 11.3137 4.68629 14 8 14ZM8 3C8.37372 3 8.87543 3.35608 9.31258 4.31781C9.4073 4.52619 9.49448 4.75446 9.57265 5H6.42735C6.50552 4.75446 6.5927 4.52619 6.68742 4.31781C7.12457 3.35608 7.62628 3 8 3ZM5.77705 3.90401C5.62614 4.23601 5.49428 4.6038 5.38411 5H3.99963C4.52341 4.30269 5.22525 3.74677 6.03766 3.39978C5.94287 3.56117 5.85596 3.7304 5.77705 3.90401ZM5.16299 6C5.05694 6.6275 5 7.30146 5 8C5 8.69854 5.05694 9.3725 5.16299 10H3.41604C3.14845 9.38754 3 8.7111 3 8C3 7.2889 3.14845 6.61246 3.41604 6H5.16299ZM5.38411 11C5.49428 11.3962 5.62614 11.764 5.77705 12.096C5.85596 12.2696 5.94287 12.4388 6.03766 12.6002C5.22525 12.2532 4.52341 11.6973 3.99963 11H5.38411ZM6.42735 11H9.57265C9.49448 11.2455 9.4073 11.4738 9.31258 11.6822C8.87543 12.6439 8.37372 13 8 13C7.62628 13 7.12457 12.6439 6.68742 11.6822C6.5927 11.4738 6.50552 11.2455 6.42735 11ZM9.82134 10H6.17866C6.06438 9.3892 6 8.71396 6 8C6 7.28604 6.06438 6.6108 6.17866 6H9.82134C9.93562 6.6108 10 7.28604 10 8C10 8.71396 9.93562 9.3892 9.82134 10ZM10.6159 11H12.0004C11.4766 11.6973 10.7747 12.2532 9.96234 12.6002C10.0571 12.4388 10.144 12.2696 10.2229 12.096C10.3739 11.764 10.5057 11.3962 10.6159 11ZM12.584 10H10.837C10.9431 9.3725 11 8.69854 11 8C11 7.30146 10.9431 6.6275 10.837 6H12.584C12.8516 6.61246 13 7.2889 13 8C13 8.7111 12.8516 9.38754 12.584 10ZM9.96234 3.39978C10.7747 3.74677 11.4766 4.30269 12.0004 5H10.6159C10.5057 4.6038 10.3739 4.23601 10.2229 3.90401C10.144 3.7304 10.0571 3.56117 9.96234 3.39978Z" />;
}

function ChevronIcon({ open }: { open: boolean }) {
  return (
    <svg width={12} height={12} viewBox="0 0 12 12" aria-hidden="true" style={{ transform: open ? 'rotate(90deg)' : undefined }}>
      <path fill="currentColor" d="M4.64645 2.14645C4.45118 2.34171 4.45118 2.65829 4.64645 2.85355L7.79289 6L4.64645 9.14645C4.45118 9.34171 4.45118 9.65829 4.64645 9.85355C4.84171 10.0488 5.15829 10.0488 5.35355 9.85355L8.85355 6.35355C9.04882 6.15829 9.04882 5.84171 8.85355 5.64645L5.35355 2.14645C5.15829 1.95118 4.84171 1.95118 4.64645 2.14645Z" />
    </svg>
  );
}

function TabIcon() {
  return <FluentIcon size={16} path="M1.99994 4C1.99994 2.89543 2.89537 2 3.99994 2H11.9999C13.1045 2 13.9999 2.89543 13.9999 4V12C13.9999 13.1046 13.1045 14 11.9999 14H3.99994C2.89537 14 1.99994 13.1046 1.99994 12V4ZM3.99994 3C3.44765 3 2.99994 3.44772 2.99994 4V12C2.99994 12.5523 3.44765 13 3.99994 13H11.9999C12.5522 13 12.9999 12.5523 12.9999 12V4C12.9999 3.44772 12.5522 3 11.9999 3H3.99994Z" />;
}

function WindowIcon() {
  return <FluentIcon size={16} path="M4.5 2C3.11929 2 2 3.11929 2 4.5V11.5C2 12.8807 3.11929 14 4.5 14H11.5C12.8807 14 14 12.8807 14 11.5V4.5C14 3.11929 12.8807 2 11.5 2H4.5ZM13 5H3V4.5C3 3.67157 3.67157 3 4.5 3H11.5C12.3284 3 13 3.67157 13 4.5V5ZM3 6H13V11.5C13 12.3284 12.3284 13 11.5 13H4.5C3.67157 13 3 12.3284 3 11.5V6Z" />;
}

function PrivateIcon() {
  return <FluentIcon size={16} path="M8 1C9.65685 1 11 2.34315 11 4V6C12.1046 6 13 6.89543 13 8V13C13 14.1046 12.1046 15 11 15H5C3.89543 15 3 14.1046 3 13V8C3 6.89543 3.89543 6 5 6V4C5 2.34315 6.34315 1 8 1ZM5 7C4.44772 7 4 7.44772 4 8V13C4 13.5523 4.44772 14 5 14H11C11.5523 14 12 13.5523 12 13V8C12 7.44772 11.5523 7 11 7H5ZM8 9.5C8.55228 9.5 9 9.94772 9 10.5C9 11.0523 8.55228 11.5 8 11.5C7.44772 11.5 7 11.0523 7 10.5C7 9.94772 7.44772 9.5 8 9.5ZM8 2C6.89543 2 6 2.89543 6 4V6H10V4C10 2.89543 9.10457 2 8 2Z" />;
}

function CopyIcon() {
  return <FluentIcon size={16} path="M5 6H4C3.44772 6 3 6.44772 3 7V12C3 12.5523 3.44772 13 4 13H8C8.55228 13 9 12.5523 9 12H10C10 13.1046 9.10457 14 8 14H4C2.89543 14 2 13.1046 2 12V7C2 5.89543 2.89543 5 4 5H5V6ZM12 2C13.1046 2 14 2.89543 14 4V9C14 10.1046 13.1046 11 12 11H8C6.89543 11 6 10.1046 6 9V4C6 2.89543 6.89543 2 8 2H12ZM8 3C7.44772 3 7 3.44772 7 4V9C7 9.55228 7.44772 10 8 10H12C12.5523 10 13 9.55228 13 9V4C13 3.44772 12.5523 3 12 3H8Z" />;
}
