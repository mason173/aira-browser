import { useEffect, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import type { HistorySyncVisit } from '@/features/sync/history/HistorySyncModels';
import {
  historyFaviconUrl,
  historyRemoveLabel,
  historyHostname,
  useHistorySurfaceData,
} from '../../useHistorySurfaceData';
import {
  firefoxFolderLabel,
  firefoxHistoryCopy,
  type FirefoxHistoryFolder,
} from './firefoxHistorySpec';
import { HistoryLoadMore } from '../../HistoryLoadMore';
import './firefox-history.css';

const FOLDERS: FirefoxHistoryFolder[] = ['all', 'today', 'yesterday', 'week', 'month'];

export function FirefoxHistoryPage() {
  const { i18n } = useTranslation();
  const copy = firefoxHistoryCopy(i18n.language);
  const data = useHistorySurfaceData();
  const [folder, setFolder] = useState<FirefoxHistoryFolder>('all');
  const [historyStack, setHistoryStack] = useState<FirefoxHistoryFolder[]>(['all']);
  const [historyIndex, setHistoryIndex] = useState(0);
  const { query, setQuery } = data;
  const [sortKey, setSortKey] = useState<'title' | 'url' | 'date'>('date');
  const [selectedId, setSelectedId] = useState('');
  const [menu, setMenu] = useState<{ x: number; y: number; visit: HistorySyncVisit } | null>(null);
  const [theme, setTheme] = useState<'light' | 'dark'>(readFirefoxTheme);

  useEffect(() => {
    document.title = copy.title;
    document.documentElement.dataset.firefoxTheme = theme;
    document.body.classList.add('firefox-history-body');
    return () => {
      document.body.classList.remove('firefox-history-body');
      delete document.documentElement.dataset.firefoxTheme;
    };
  }, [copy.title, theme]);

  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const apply = () => setTheme(readFirefoxTheme());
    media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, []);

  const rows = useMemo(() => {
    const filtered = data.visits.filter((visit) => {
      return matchesFolder(visit.visitedAt, folder);
    });
    return filtered.sort((left, right) => {
      if (sortKey === 'title') return (left.title || left.url).localeCompare(right.title || right.url);
      if (sortKey === 'url') return left.url.localeCompare(right.url);
      return right.visitedAt - left.visitedAt;
    });
  }, [data.visits, folder, sortKey]);

  const selectFolder = (next: FirefoxHistoryFolder) => {
    setFolder(next);
    setHistoryStack((current) => [...current.slice(0, historyIndex + 1), next]);
    setHistoryIndex((current) => current + 1);
    setMenu(null);
  };

  const go = (direction: -1 | 1) => {
    const nextIndex = historyIndex + direction;
    const next = historyStack[nextIndex];
    if (!next) return;
    setHistoryIndex(nextIndex);
    setFolder(next);
  };

  const openVisit = (url: string, newTab = false) => {
    if (newTab && globalThis.chrome?.tabs?.create) {
      void globalThis.chrome.tabs.create({ url, active: true });
      return;
    }
    if (globalThis.chrome?.tabs?.create) void globalThis.chrome.tabs.create({ url, active: true });
    else window.location.assign(url);
  };

  return (
    <div className="firefox-history" data-firefox-theme={theme} onClick={() => setMenu(null)}>
      <header className="firefox-history-toolbar">
        <div className="firefox-history-nav-buttons">
          <button type="button" aria-label={copy.back} disabled={historyIndex <= 0} onClick={() => go(-1)}><BackIcon /></button>
          <button type="button" aria-label={copy.forward} disabled={historyIndex >= historyStack.length - 1} onClick={() => go(1)}><ForwardIcon /></button>
        </div>
        <div className="firefox-history-organize">
          <button type="button" onClick={(event) => event.stopPropagation()}>{copy.organize}</button>
        </div>
        <input
          className="firefox-history-search"
          type="search"
          value={query}
          placeholder={copy.search}
          aria-label={copy.search}
          onChange={(event) => setQuery(event.target.value)}
        />
      </header>
      <div className="firefox-history-body">
        <nav className="firefox-history-tree" aria-label={copy.history}>
          <button type="button" className={folder === 'all' ? 'is-selected' : undefined} onClick={() => selectFolder('all')}>
            {copy.history}
          </button>
          {FOLDERS.filter((item) => item !== 'all').map((item) => (
            <button
              key={item}
              type="button"
              className={`is-child${folder === item ? ' is-selected' : ''}`}
              onClick={() => selectFolder(item)}
            >
              {firefoxFolderLabel(item, copy)}
            </button>
          ))}
        </nav>
        <section className="firefox-history-table">
          <div className="firefox-history-columns">
            <button type="button" onClick={() => setSortKey('title')}>{copy.name}</button>
            <button type="button" onClick={() => setSortKey('url')}>{copy.url}</button>
            <button type="button" onClick={() => setSortKey('date')}>{copy.date}</button>
          </div>
          <div className="firefox-history-rows">
            {data.loading && rows.length === 0 ? <p className="firefox-history-status">{copy.loading}</p> : null}
            {!data.loading && rows.length === 0 ? <p className="firefox-history-status">{copy.empty}</p> : null}
            {rows.map((visit) => (
              <button
                key={visit.visitId}
                type="button"
                className={`firefox-history-row${selectedId === visit.visitId ? ' is-selected' : ''}`}
                onClick={() => {
                  setSelectedId(visit.visitId);
                  openVisit(visit.url);
                }}
                onContextMenu={(event) => {
                  event.preventDefault();
                  setSelectedId(visit.visitId);
                  setMenu({ x: event.clientX, y: event.clientY, visit });
                }}
              >
                <span className="firefox-history-name">
                  <Favicon url={visit.url} />
                  <span>{visit.title || historyHostname(visit.url) || visit.url}</span>
                </span>
                <span className="firefox-history-url">{visit.url}</span>
                <span className="firefox-history-date">{formatVisitDate(visit.visitedAt, i18n.language)}</span>
              </button>
            ))}
            <HistoryLoadMore {...data} language={i18n.language} />
          </div>
        </section>
      </div>
      {menu ? (
        <div className="firefox-history-menu" style={{ left: menu.x, top: menu.y }} onClick={(event) => event.stopPropagation()}>
          <button type="button" onClick={() => { openVisit(menu.visit.url); setMenu(null); }}>{copy.open}</button>
          <button type="button" onClick={() => { openVisit(menu.visit.url, true); setMenu(null); }}>{copy.openTab}</button>
          <button type="button" onClick={() => { void navigator.clipboard?.writeText(menu.visit.url); setMenu(null); }}>{copy.copy}</button>
          <button type="button" onClick={() => { void data.deleteVisit(menu.visit.visitId); setMenu(null); }}>{historyRemoveLabel(menu.visit.visitId, i18n.language, copy.delete)}</button>
        </div>
      ) : null}
    </div>
  );
}

function readFirefoxTheme(): 'light' | 'dark' {
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function matchesFolder(visitedAt: number, folder: FirefoxHistoryFolder): boolean {
  if (folder === 'all') return true;
  const date = new Date(visitedAt);
  const start = new Date(date);
  start.setHours(0, 0, 0, 0);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const diff = Math.round((today.getTime() - start.getTime()) / 86_400_000);
  if (folder === 'today') return diff === 0;
  if (folder === 'yesterday') return diff === 1;
  if (folder === 'week') return diff >= 0 && diff < 7;
  const sameMonth = date.getFullYear() === today.getFullYear() && date.getMonth() === today.getMonth();
  return sameMonth;
}

function formatVisitDate(timestamp: number, language: string): string {
  const locale = language.toLowerCase().startsWith('zh') ? 'zh-CN' : language || 'en';
  return new Intl.DateTimeFormat(locale, {
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(timestamp));
}

function PlacesArrow({ direction }: { direction: 'back' | 'forward' }) {
  const path = direction === 'back'
    ? 'M6.69 2.25 1.22 7.72a.75.75 0 0 0 0 1.06l5.47 5.47 1.06-1.061L3.56 9H15V7.5H3.56l4.19-4.19-1.06-1.06z'
    : 'M12.44 9H1V7.5h11.44L8.25 3.31l1.06-1.06 5.47 5.47a.75.75 0 0 1 0 1.06l-5.47 5.47-1.06-1.061L12.44 9z';
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true">
      <path fill="currentColor" d={path} />
    </svg>
  );
}

function BackIcon() {
  return <PlacesArrow direction="back" />;
}

function ForwardIcon() {
  return <PlacesArrow direction="forward" />;
}

function Favicon({ url }: { url: string }) {
  const [failed, setFailed] = useState(false);
  const src = historyFaviconUrl(url);
  if (!src || failed) return <span className="firefox-history-favicon" />;
  return <img className="firefox-history-favicon" src={src} alt="" onError={() => setFailed(true)} />;
}
