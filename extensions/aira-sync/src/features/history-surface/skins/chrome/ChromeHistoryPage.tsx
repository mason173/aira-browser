import { useEffect, useMemo, useRef, useState, type ReactElement } from 'react';
import { useTranslation } from 'react-i18next';
import type { HistorySyncVisit } from '@/features/sync/history/HistorySyncModels';
import {
  historyFaviconUrl,
  historyRemoveLabel,
  historyRemoveSelectionLabel,
  historyHostname,
  useHistorySurfaceData,
} from '../../useHistorySurfaceData';
import {
  chromeHistoryCopy,
  formatChromeHistoryDay,
  formatChromeHistoryTime,
} from './chromeHistorySpec';
import { useChromeOtherDeviceTabs } from './useChromeOtherDeviceTabs';
import { HistoryLoadMore } from '../../HistoryLoadMore';
import './chrome-history.css';

type ChromeHistorySection = 'history' | 'other-devices';
type HistoryBrandLogo = (props: { theme: 'light' | 'dark' }) => ReactElement;

export function ChromeHistoryPage({
  copyFor = chromeHistoryCopy,
  Logo = ChromeLogo,
}: {
  copyFor?: typeof chromeHistoryCopy;
  Logo?: HistoryBrandLogo;
} = {}) {
  const { i18n } = useTranslation();
  const copy = copyFor(i18n.language);
  const data = useHistorySurfaceData();
  const [section, setSection] = useState<ChromeHistorySection>('history');
  const [theme, setTheme] = useState<'light' | 'dark'>(readChromeTheme);
  const [menuVisitId, setMenuVisitId] = useState('');
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [compact, setCompact] = useState(() => window.matchMedia('(max-width: 960px)').matches);
  const [navOpen, setNavOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    document.title = copy.title;
    document.documentElement.dataset.chromeTheme = theme;
    document.body.classList.add('chrome-history-body');
    return () => {
      document.body.classList.remove('chrome-history-body');
      delete document.documentElement.dataset.chromeTheme;
    };
  }, [copy.title, theme]);

  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const apply = () => setTheme(readChromeTheme());
    media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, []);

  useEffect(() => {
    const media = window.matchMedia('(max-width: 960px)');
    const apply = () => {
      setCompact(media.matches);
      if (!media.matches) {
        setNavOpen(false);
        setSearchOpen(false);
      }
    };
    apply();
    media.addEventListener('change', apply);
    return () => media.removeEventListener('change', apply);
  }, []);

  useEffect(() => {
    if (searchOpen) searchRef.current?.focus();
  }, [searchOpen]);

  useEffect(() => {
    if (!navOpen && !searchOpen && !menuVisitId) return undefined;
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      setNavOpen(false);
      setSearchOpen(false);
      setMenuVisitId('');
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [menuVisitId, navOpen, searchOpen]);

  useEffect(() => {
    if (!menuVisitId) return undefined;
    const closeMenu = (event: Event) => {
      const target = event.target;
      if (target instanceof Element && target.closest('.chrome-history-menu, .chrome-history-more')) return;
      setMenuVisitId('');
    };
    document.addEventListener('pointerdown', closeMenu);
    return () => document.removeEventListener('pointerdown', closeMenu);
  }, [menuVisitId]);

  useEffect(() => {
    const list = listRef.current;
    if (!list) return undefined;
    const onScroll = () => {
      if (!data.hasMore || data.loading) return;
      if (list.scrollTop + list.clientHeight >= list.scrollHeight - 240) data.loadMore();
    };
    list.addEventListener('scroll', onScroll, { passive: true });
    return () => list.removeEventListener('scroll', onScroll);
  }, [data]);

  const otherDevices = useChromeOtherDeviceTabs(section === 'other-devices');
  const visits = data.visits;
  const groups = useMemo(
    () => groupChromeVisits(visits, i18n.language),
    [i18n.language, visits],
  );

  const openVisit = (url: string, newTab = false) => {
    if (newTab && globalThis.chrome?.tabs?.create) {
      void globalThis.chrome.tabs.create({ url, active: true });
      return;
    }
    window.location.assign(url);
  };

  const openClearData = () => {
    const url = 'chrome://settings/clearBrowserData';
    if (globalThis.chrome?.tabs?.create) void globalThis.chrome.tabs.create({ url });
    else window.location.assign(url);
  };

  const closeNav = () => setNavOpen(false);
  const selectedVisits = visits.filter((visit) => selectedIds.includes(visit.visitId));
  const toggleSelected = (visitId: string) => {
    setSelectedIds((current) => current.includes(visitId)
      ? current.filter((id) => id !== visitId)
      : [...current, visitId]);
  };
  const openSelected = () => {
    selectedVisits.forEach((visit) => openVisit(visit.url, true));
  };
  const deleteSelected = () => {
    const ids = selectedVisits.map((visit) => visit.visitId);
    setSelectedIds([]);
    void ids.reduce(async (previous, visitId) => {
      await previous;
      await data.deleteVisit(visitId);
    }, Promise.resolve());
  };

  return (
    <div
      className={`chrome-history${navOpen ? ' is-nav-open' : ''}${searchOpen ? ' is-search-open' : ''}`}
      data-chrome-theme={theme}
    >
      {selectedVisits.length > 0 ? (
        <div className="chrome-history-selection">
          <div className="chrome-history-selection-start">
            <button
              type="button"
              className="chrome-history-icon-button"
              style={{ display: 'flex' }}
              aria-label={copy.closeSelection}
              onClick={() => setSelectedIds([])}
            >
              <CloseIcon />
            </button>
            <span>{copy.selected(selectedVisits.length)}</span>
          </div>
          <div className="chrome-history-selection-actions">
            <button type="button" className="chrome-history-selection-button" onClick={openSelected}>{copy.open}</button>
            <button type="button" className="chrome-history-selection-button" onClick={deleteSelected}>{historyRemoveSelectionLabel(selectedIds, i18n.language, copy.deleteSelected)}</button>
          </div>
        </div>
      ) : (
      <header className="chrome-history-header">
        <div className="chrome-history-brand">
          <button
            type="button"
            className="chrome-history-icon-button chrome-history-menu-button"
            aria-label={copy.title}
            aria-expanded={navOpen}
            onClick={() => setNavOpen((open) => !open)}
          >
            <MenuIcon />
          </button>
          <Logo theme={theme} />
          <h1>{copy.title}</h1>
        </div>
        <form className="chrome-history-search" role="search" onSubmit={(event) => event.preventDefault()}>
          <SearchIcon />
          <input
            ref={searchRef}
            type="search"
            value={data.query}
            placeholder={copy.search}
            aria-label={copy.search}
            onChange={(event) => data.setQuery(event.target.value)}
          />
        </form>
        <button
          type="button"
          className="chrome-history-icon-button chrome-history-search-button"
          aria-label={copy.search}
          onClick={() => setSearchOpen((open) => !open)}
        >
          <SearchIcon />
        </button>
      </header>
      )}
      {compact ? (
        <>
          <button type="button" className="chrome-history-scrim" aria-label={copy.title} onClick={closeNav} />
          <aside className="chrome-history-drawer">
            <div className="chrome-history-drawer-brand">
              <Logo theme={theme} />
              <h1>{copy.title}</h1>
            </div>
            <HistoryNav
              copy={copy}
              section={section}
              onSelect={(next) => {
                setSection(next);
                closeNav();
              }}
              onClear={() => {
                closeNav();
                openClearData();
              }}
            />
          </aside>
        </>
      ) : null}
      <div className="chrome-history-body">
        <HistoryNav
          copy={copy}
          section={section}
          onSelect={setSection}
          onClear={openClearData}
        />
        <div className="chrome-history-main" ref={listRef}>
        <main className="chrome-history-card" onClick={() => setMenuVisitId('')}>
          {section === 'other-devices' ? (
            <OtherDeviceTabs
              copy={copy}
              devices={otherDevices.devices}
              loading={otherDevices.loading}
              error={otherDevices.error}
              onOpen={openVisit}
            />
          ) : data.status === 'login-required' ? (
            <p className="chrome-history-status">{copy.login}</p>
          ) : data.loading && visits.length === 0 ? (
            <p className="chrome-history-status">{copy.loading}</p>
          ) : groups.length === 0 ? (
            <p className="chrome-history-status">{copy.empty}</p>
          ) : groups.map((group) => (
            <section className="chrome-history-day" key={group.label}>
              <h2>{group.label}</h2>
              {group.visits.map((visit) => (
                <article className="chrome-history-row" key={visit.visitId}>
                  <input
                    type="checkbox"
                    checked={selectedIds.includes(visit.visitId)}
                    aria-label={visit.title || visit.url}
                    onChange={() => toggleSelected(visit.visitId)}
                  />
                  <span className="chrome-history-time">{formatChromeHistoryTime(visit.visitedAt, i18n.language)}</span>
                  <Favicon url={visit.url} />
                  <button type="button" className="chrome-history-link" onClick={() => openVisit(visit.url)}>
                    <span className="title">{visit.title || historyHostname(visit.url) || visit.url}</span>
                    <span className="domain">{historyHostname(visit.url) || visit.url}</span>
                  </button>
                  <button
                    type="button"
                    className="chrome-history-more"
                    aria-label={historyRemoveLabel(visit.visitId, i18n.language, copy.remove)}
                    aria-expanded={menuVisitId === visit.visitId}
                    onClick={(event) => {
                      event.stopPropagation();
                      setMenuVisitId((current) => current === visit.visitId ? '' : visit.visitId);
                    }}
                  >
                    <MoreIcon />
                  </button>
                  {menuVisitId === visit.visitId ? (
                    <div className="chrome-history-menu" style={{ top: 40, right: 12 }} onClick={(event) => event.stopPropagation()}>
                      <button type="button" onClick={() => openVisit(visit.url)}>{copy.open}</button>
                      <button type="button" onClick={() => openVisit(visit.url, true)}>{copy.openNewTab}</button>
                      <button type="button" onClick={() => {
                        setMenuVisitId('');
                        void data.deleteVisit(visit.visitId);
                      }}
                      >{historyRemoveLabel(visit.visitId, i18n.language, copy.remove)}</button>
                    </div>
                  ) : null}
                </article>
              ))}
            </section>
          ))}
          {section === 'history' ? <HistoryLoadMore {...data} language={i18n.language} /> : null}
        </main>
        </div>
      </div>
    </div>
  );
}

function OtherDeviceTabs({
  copy,
  devices,
  loading,
  error,
  onOpen,
}: {
  copy: ReturnType<typeof chromeHistoryCopy>;
  devices: ReturnType<typeof useChromeOtherDeviceTabs>['devices'];
  loading: boolean;
  error: string;
  onOpen: (url: string, newTab?: boolean) => void;
}) {
  if (loading && devices.length === 0) {
    return <p className="chrome-history-status">{copy.loading}</p>;
  }
  if (error && devices.length === 0) {
    return <p className="chrome-history-status">{error}</p>;
  }
  if (devices.length === 0) {
    return <p className="chrome-history-status">{copy.emptyOther}</p>;
  }
  return (
    <>
      {devices.map((device) => {
        const label = device.deviceName || device.model || device.platform || device.browserName;
        return (
          <section className="chrome-history-day" key={device.deviceId}>
            <h2>{label}</h2>
            {device.tabs.map((tab, index) => (
              <article className="chrome-history-row is-remote" key={`${device.deviceId}:${tab.url}:${index}`}>
                <Favicon url={tab.url} />
                <button type="button" className="chrome-history-link" onClick={() => onOpen(tab.url, true)}>
                  <span className="title">{tab.title || historyHostname(tab.url) || tab.url}</span>
                  <span className="domain">{historyHostname(tab.url) || tab.url}</span>
                </button>
              </article>
            ))}
          </section>
        );
      })}
    </>
  );
}

function HistoryNav({
  copy,
  section,
  onSelect,
  onClear,
}: {
  copy: ReturnType<typeof chromeHistoryCopy>;
  section: ChromeHistorySection;
  onSelect: (section: ChromeHistorySection) => void;
  onClear: () => void;
}) {
  return (
    <nav className="chrome-history-nav" aria-label={copy.title}>
      <button
        type="button"
        className={section === 'history' ? 'is-selected' : undefined}
        onClick={() => onSelect('history')}
      >
        <HistoryIcon />
        <span className="nav-label">{copy.history}</span>
      </button>
      <button
        type="button"
        className={section === 'other-devices' ? 'is-selected' : undefined}
        onClick={() => onSelect('other-devices')}
      >
        <DevicesIcon />
        <span className="nav-label">{copy.otherDevices}</span>
      </button>
      <button type="button" onClick={onClear}>
        <DeleteIcon />
        <span className="nav-label">{copy.clearData}</span>
        <OpenInNewIcon />
      </button>
    </nav>
  );
}

function readChromeTheme(): 'light' | 'dark' {
  if (document.documentElement.classList.contains('dark')) return 'dark';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function groupChromeVisits(visits: HistorySyncVisit[], language: string) {
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
  return (
    <img
      className="chrome-history-favicon"
      src={src}
      alt=""
      onError={() => setFailed(true)}
    />
  );
}

function ChromeLogo({ theme }: { theme: 'light' | 'dark' }) {
  const file = theme === 'dark' ? 'history-skins/chrome-logo-dark.svg' : 'history-skins/chrome-logo.png';
  const src = globalThis.chrome?.runtime?.getURL?.(file) || `/${file}`;
  return <img src={src} width={24} height={24} alt="" />;
}

function MaterialIcon({
  size,
  className,
  path,
}: {
  size: number;
  className?: string;
  path: string;
}) {
  return (
    <svg className={className} width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path fill="currentColor" d={path} />
    </svg>
  );
}

function CloseIcon() {
  return <MaterialIcon size={20} path="M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z" />;
}

function MenuIcon() {
  return <MaterialIcon size={24} path="M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z" />;
}

function SearchIcon() {
  return <MaterialIcon size={20} path="M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z" />;
}

function HistoryIcon() {
  return <MaterialIcon size={20} path="M13 3a9 9 0 0 0-9 9H1l3.89 3.89.07.14L9 12H6a7 7 0 1 1 7 7 6.97 6.97 0 0 1-4.94-2.06l-1.42 1.42A8.96 8.96 0 0 0 13 21a9 9 0 0 0 0-18zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8z" />;
}

function DevicesIcon() {
  return <MaterialIcon size={20} path="M4 6h18V4H4c-1.1 0-2 .9-2 2v11H0v3h14v-3H4V6zm19 2h-6c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h6c.55 0 1-.45 1-1V9c0-.55-.45-1-1-1zm-1 9h-4v-7h4v7z" />;
}

function DeleteIcon() {
  return <MaterialIcon size={20} path="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z" />;
}

function OpenInNewIcon() {
  return <MaterialIcon className="external" size={16} path="M19 19H5V5h7V3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2v-7h-2v7zM14 3v2h3.59l-9.83 9.83 1.41 1.41L19 6.41V10h2V3h-7z" />;
}

function MoreIcon() {
  return <MaterialIcon size={18} path="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z" />;
}

function GlobeIcon() {
  return <MaterialIcon className="chrome-history-favicon" size={16} path="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />;
}
