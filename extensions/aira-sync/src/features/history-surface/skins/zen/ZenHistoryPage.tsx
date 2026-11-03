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
  zenDisplayUrl,
  zenHistoryCopy,
  type ZenHistorySort,
  type ZenHistoryWhen,
} from './zenHistorySpec';
import { HistoryLoadMore } from '../../HistoryLoadMore';
import './zen-history.css';

const DAY_MS = 86_400_000;
const WHEN_DAYS: Record<ZenHistoryWhen, number> = { today: 1, week: 7, month: 30 };

export function ZenHistoryPage() {
  const { i18n } = useTranslation();
  const copy = zenHistoryCopy(i18n.language);
  const data = useHistorySurfaceData();
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [when, setWhen] = useState<ZenHistoryWhen | null>(null);
  const [sort, setSort] = useState<ZenHistorySort>('date');
  const [theme, setTheme] = useState<'light' | 'dark'>(readZenTheme);

  useEffect(() => {
    document.title = copy.title;
    document.body.classList.add('zen-history-body');
    return () => {
      document.body.classList.remove('zen-history-body');
    };
  }, [copy.title]);

  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const apply = () => setTheme(readZenTheme());
    media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, []);

  const groups = useMemo(
    () => groupZenVisits(data.visits, when, sort, i18n.language, copy.other),
    [copy.other, data.visits, i18n.language, sort, when],
  );

  const openVisit = (url: string) => {
    if (globalThis.chrome?.tabs?.create) void globalThis.chrome.tabs.create({ url, active: true });
    else window.location.assign(url);
  };

  const toggleWhen = (next: ZenHistoryWhen) => setWhen((current) => (current === next ? null : next));
  const toggleSort = (next: ZenHistorySort) => setSort((current) => (current === next ? 'date' : next));

  return (
    <div className="zen-history" data-zen-theme={theme}>
      <aside className="zen-history-panel" aria-label={copy.history}>
        <nav className="zen-history-side">
          <button type="button" className="zen-history-tab is-active" aria-current="page">
            <HistoryIcon />
            <span>{copy.history}</span>
          </button>
          <div className="zen-history-tab"><span>{copy.downloads}</span></div>
          <div className="zen-history-tab"><span>{copy.boosts}</span></div>
          <div className="zen-history-tab"><span>{copy.spaces}</span></div>
          <div className="zen-history-tab"><span>{copy.media}</span></div>
        </nav>
        <section className="zen-history-content">
          <div className={`zen-history-search-top${filtersOpen ? ' is-open' : ''}`}>
            <div className="zen-history-search-header">
              <label className="zen-history-search-box">
                <SearchIcon />
                <input
                  type="search"
                  value={data.query}
                  placeholder={copy.search}
                  aria-label={copy.search}
                  onChange={(event) => data.setQuery(event.target.value)}
                />
              </label>
              <button type="button" className="zen-history-filter-button" onClick={() => setFiltersOpen(true)}>
                {copy.filter}
              </button>
            </div>
            <div className="zen-history-filter-header">
              <h2>{copy.filterTitle}</h2>
              <button type="button" className="zen-history-filter-done" onClick={() => setFiltersOpen(false)}>{copy.done}</button>
            </div>
            <div className="zen-history-filter-panel">
              <div className="zen-history-filter-group">
                <h3>{copy.when}</h3>
                <div className="zen-history-filter-options">
                  <FilterChip active={when === 'today'} label={copy.today} onClick={() => toggleWhen('today')} />
                  <FilterChip active={when === 'week'} label={copy.week} onClick={() => toggleWhen('week')} />
                  <FilterChip active={when === 'month'} label={copy.month} onClick={() => toggleWhen('month')} />
                </div>
              </div>
              <div className="zen-history-filter-group">
                <h3>{copy.sort}</h3>
                <div className="zen-history-filter-options">
                  <FilterChip active={sort === 'date'} label={copy.byDate} onClick={() => toggleSort('date')} />
                  <FilterChip active={sort === 'site'} label={copy.bySite} onClick={() => toggleSort('site')} />
                  <FilterChip active={sort === 'mostvisited'} label={copy.mostVisited} onClick={() => toggleSort('mostvisited')} />
                  <FilterChip active={sort === 'lastvisited'} label={copy.lastVisited} onClick={() => toggleSort('lastvisited')} />
                </div>
              </div>
            </div>
          </div>
          <div className="zen-history-results">
            {data.loading && groups.length === 0 ? <p className="zen-history-empty">{copy.loading}</p> : null}
            {!data.loading && groups.length === 0 ? <p className="zen-history-empty">{copy.empty}</p> : null}
            {groups.map((group) => (
              <div className="zen-history-group" key={group.key}>
                {group.label ? <h3>{group.label}</h3> : null}
                {group.visits.map((visit) => (
                  <div key={visit.visitId} className="zen-history-row" role="link" tabIndex={0} onClick={() => openVisit(visit.url)}>
                    <Favicon url={visit.url} />
                    <span className="zen-history-row-text">
                      <span className="zen-history-row-title">{visit.title || visit.url}</span>
                      <span className="zen-history-row-subtitle">
                        <span className="zen-history-url">{zenDisplayUrl(visit.url)}</span>
                        <span className="zen-history-date">{formatVisitTime(visit.visitedAt, i18n.language)}</span>
                      </span>
                    </span>
                    <span className="zen-history-actions">
                      <button type="button" aria-label={historyRemoveLabel(visit.visitId, i18n.language, copy.remove)} title={historyRemoveLabel(visit.visitId, i18n.language, copy.remove)} onClick={(event) => { event.stopPropagation(); void data.deleteVisit(visit.visitId); }}>
                        <TrashIcon />
                      </button>
                      <button type="button" aria-label={copy.reopen} onClick={(event) => { event.stopPropagation(); openVisit(visit.url); }}>
                        <ReopenIcon />
                      </button>
                    </span>
                  </div>
                ))}
              </div>
            ))}
            <HistoryLoadMore {...data} language={i18n.language} />
          </div>
        </section>
      </aside>
    </div>
  );
}

function FilterChip({ active, label, onClick }: { active: boolean; label: string; onClick: () => void }) {
  return <button type="button" className={`zen-history-chip${active ? ' is-active' : ''}`} onClick={onClick}>{label}</button>;
}

function readZenTheme(): 'light' | 'dark' {
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function groupZenVisits(
  visits: HistorySyncVisit[],
  when: ZenHistoryWhen | null,
  sort: ZenHistorySort,
  language: string,
  otherLabel: string,
): Array<{ key: string; label: string; visits: HistorySyncVisit[] }> {
  const cutoff = when ? Date.now() - WHEN_DAYS[when] * DAY_MS : 0;
  const filtered = visits.filter((visit) => visit.visitedAt >= cutoff);
  if (sort === 'mostvisited') {
    return [{ key: 'most', label: '', visits: sortByVisitCount(filtered) }];
  }
  if (sort === 'lastvisited') {
    return [{ key: 'last', label: '', visits: latestByUrl(filtered) }];
  }
  if (sort === 'site') return groupBySite(filtered, otherLabel);
  return groupByDay(filtered, language);
}

function sortByVisitCount(visits: HistorySyncVisit[]): HistorySyncVisit[] {
  const counts = new Map<string, number>();
  visits.forEach((visit) => counts.set(visit.url, (counts.get(visit.url) || 0) + 1));
  return latestByUrl(visits).sort((left, right) => (counts.get(right.url) || 0) - (counts.get(left.url) || 0));
}

function latestByUrl(visits: HistorySyncVisit[]): HistorySyncVisit[] {
  const latest = new Map<string, HistorySyncVisit>();
  visits.forEach((visit) => {
    const current = latest.get(visit.url);
    if (!current || visit.visitedAt > current.visitedAt) latest.set(visit.url, visit);
  });
  return [...latest.values()].sort((left, right) => right.visitedAt - left.visitedAt);
}

function groupBySite(visits: HistorySyncVisit[], otherLabel: string) {
  const groups = new Map<string, HistorySyncVisit[]>();
  latestByUrl(visits).forEach((visit) => {
    const key = historyHostname(visit.url) || otherLabel;
    groups.set(key, [...(groups.get(key) || []), visit]);
  });
  return [...groups.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, items]) => ({ key, label: key, visits: items }));
}

function groupByDay(visits: HistorySyncVisit[], language: string) {
  const groups = new Map<number, HistorySyncVisit[]>();
  [...visits].sort((left, right) => right.visitedAt - left.visitedAt).forEach((visit) => {
    const day = startOfDay(visit.visitedAt);
    groups.set(day, [...(groups.get(day) || []), visit]);
  });
  return [...groups.entries()].map(([day, items]) => ({
    key: String(day),
    label: formatDay(day, language),
    visits: items,
  }));
}

function startOfDay(timestamp: number): number {
  const date = new Date(timestamp);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

function formatDay(day: number, language: string): string {
  const locale = language.toLowerCase().startsWith('zh') ? 'zh-CN' : language || 'en';
  const daysAgo = Math.round((startOfDay(Date.now()) - day) / DAY_MS);
  const formatted = daysAgo <= 6
    ? new Intl.RelativeTimeFormat(locale, { numeric: 'auto' }).format(-daysAgo, 'day')
    : new Intl.DateTimeFormat(locale, { dateStyle: 'medium' }).format(day);
  return formatted.charAt(0).toLocaleUpperCase() + formatted.slice(1);
}

function formatVisitTime(timestamp: number, language: string): string {
  const locale = language.toLowerCase().startsWith('zh') ? 'zh-CN' : language || 'en';
  return new Intl.DateTimeFormat(locale, { dateStyle: 'medium', timeStyle: 'short' }).format(timestamp);
}

function Favicon({ url }: { url: string }) {
  const [failed, setFailed] = useState(false);
  const src = historyFaviconUrl(url);
  if (!src || failed) return <span className="zen-history-favicon" />;
  return <img className="zen-history-favicon" src={src} alt="" onError={() => setFailed(true)} />;
}

function ZenIcon({ className, path }: { className?: string; path: string }) {
  return (
    <svg className={className} width="16" height="16" viewBox="0 0 18 18" aria-hidden="true">
      <path fill="currentColor" d={path} />
    </svg>
  );
}

function HistoryIcon() {
  return (
    <svg className="zen-history-tab-icon" viewBox="0 0 18 18" aria-hidden="true">
      <path fill="currentColor" d="M9 1a8 8 0 1 1-8 8 .75.75 0 0 1 1.5 0 6.5 6.5 0 1 0 1.152-3.697L5.13 5.1a.75.75 0 0 1 .206 1.486l-2.944.406-.084.006H2.28q-.041-.001-.082-.007-.046-.004-.094-.015l-.017-.004-.082-.028-.044-.02-.006-.003a1 1 0 0 1-.102-.063l-.06-.048-.047-.044a1 1 0 0 1-.058-.073q-.016-.018-.028-.037a1 1 0 0 1-.047-.087l-.02-.043a.8.8 0 0 1-.048-.173l-.408-2.946a.751.751 0 0 1 1.486-.205l.113.822A7.99 7.99 0 0 1 9 1" />
      <path fill="currentColor" d="M9 4a.75.75 0 0 1 .75.75v3.857l2.927 2.027a.75.75 0 1 1-.854 1.232l-3.25-2.25A.75.75 0 0 1 8.25 9V4.75A.75.75 0 0 1 9 4" />
    </svg>
  );
}

function SearchIcon() {
  return <ZenIcon path="M7.75 1.5A6.25 6.25 0 0 1 14 7.75a6.22 6.22 0 0 1-1.334 3.855l3.614 3.615a.75.75 0 0 1-1.06 1.06l-3.615-3.614A6.22 6.22 0 0 1 7.75 14a6.25 6.25 0 0 1 0-12.5m0 1.5a4.75 4.75 0 1 0 0 9.5 4.75 4.75 0 0 0 0-9.5" />;
}

function TrashIcon() {
  return <ZenIcon path="M4.488 6.501a.75.75 0 0 1 .788.71l.374 7.104A1.25 1.25 0 0 0 6.898 15.5h4.206a1.25 1.25 0 0 0 1.248-1.185l.374-7.104a.75.75 0 0 1 1.498.078l-.374 7.106A2.75 2.75 0 0 1 11.104 17H6.898a2.75 2.75 0 0 1-2.746-2.605l-.374-7.106a.75.75 0 0 1 .71-.788M10.25 1c.966 0 1.75.784 1.75 1.75V4h3.25a.75.75 0 0 1 0 1.5H2.75a.75.75 0 0 1 0-1.5H6V2.75C6 1.784 6.784 1 7.75 1zm-2.5 1.5a.25.25 0 0 0-.25.25V4h3V2.75a.25.25 0 0 0-.25-.25z" />;
}

function ReopenIcon() {
  return <ZenIcon path="M5.22 2.22a.75.75 0 1 1 1.06 1.06L4.06 5.5H12a4.5 4.5 0 0 1 0 9H8.25a.75.75 0 0 1 0-1.5H12a3 3 0 0 0 0-6H4.06l2.22 2.22a.75.75 0 0 1-1.06 1.06l-3.5-3.5a.75.75 0 0 1-.165-.812l.004-.01a1 1 0 0 1 .056-.105 1 1 0 0 1 .105-.133z" />;
}
