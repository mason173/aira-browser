import { BookmarkSearchRecord } from '../../common/models/BookmarkSearchIndexModels';
import { normalizeNavigationSearchText } from '../../common/utils/NavigationSearchText';
import {
  BookmarkNode,
  BookmarkStorageScope,
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  SearchSuggestion
} from '../../common/models/BrowserModels';
import { isUserSearchableBookmark } from '../../data/repositories/BookmarkRepositoryCore';
import { BrowserTabState } from '../../core/tabs/TabManager';

export interface OpenTabSuggestionQuery {
  query: string;
  activeTabId: string;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  profileId?: BrowserProfileId;
  limit: number;
}

interface RankedLocalSuggestion {
  suggestion: SearchSuggestion;
  score: number;
}

export interface PreparedBookmarkSuggestion {
  suggestion: SearchSuggestion;
  normalizedTitle: string;
  normalizedHost: string;
  compactUrl: string;
}

export function prepareBookmarkSuggestion(bookmark: BookmarkNode): PreparedBookmarkSuggestion | undefined {
  if (!isUserSearchableBookmark(bookmark)) {
    return undefined;
  }
  return prepareBookmarkSearchRecord({ id: bookmark.id, title: bookmark.title, url: bookmark.url ?? '' });
}

export function prepareBookmarkSearchRecord(bookmark: BookmarkSearchRecord): PreparedBookmarkSuggestion {
  const url = bookmark.url.trim();
  const title = bookmark.title.trim();
  const host = hostFromLocalOmniboxUrl(url);
  return {
    suggestion: {
      id: `bookmark-suggestion-${bookmark.id}`,
      title: displayLocalOmniboxTitle(title, host),
      source: 'bookmarks',
      target: url,
      subtitle: host,
      icon: '',
      refId: bookmark.id
    },
    normalizedTitle: title.toLowerCase(),
    normalizedHost: host.trim().toLowerCase(),
    compactUrl: normalizeLocalOmniboxQuery(url)
  };
}

/** Candidates remain in repository order, including duplicates, to preserve tie and URL-dedup rules. */
export function matchPreparedBookmarkSuggestions(
  candidates: PreparedBookmarkSuggestion[],
  query: string,
  limit: number
): SearchSuggestion[] {
  const normalizedLimit = Math.max(0, Math.floor(limit));
  const normalizedQuery = normalizeLocalOmniboxQuery(query);
  if (normalizedLimit === 0 || normalizedQuery.length === 0) {
    return [];
  }
  const ranked: RankedLocalSuggestion[] = [];
  const seenUrls: Set<string> = new Set<string>();
  for (let index = 0; index < candidates.length; index += 1) {
    const entry = candidates[index];
    if (seenUrls.has(entry.compactUrl)) {
      continue;
    }
    const score = scoreNormalizedLocalOmniboxText(
      normalizedQuery, entry.normalizedTitle, entry.normalizedHost, entry.compactUrl
    );
    if (score <= 0) {
      continue;
    }
    seenUrls.add(entry.compactUrl);
    const suggestion: SearchSuggestion = {
      id: entry.suggestion.id,
      title: entry.suggestion.title,
      source: entry.suggestion.source,
      target: entry.suggestion.target,
      subtitle: entry.suggestion.subtitle,
      icon: entry.suggestion.icon,
      refId: entry.suggestion.refId,
      score: score
    };
    considerLocalSuggestion(ranked, { suggestion: suggestion, score: score }, normalizedLimit);
  }
  return ranked.map((item: RankedLocalSuggestion): SearchSuggestion => item.suggestion);
}

/**
 * Ranks bookmarks and open tabs already held in memory. Address-bar keystrokes
 * must not query the bookmark database. The bookmark service uses this scan only
 * while its versioned in-memory index is warming up.
 */
export function matchBookmarkSuggestions(
  bookmarks: BookmarkNode[],
  query: string,
  limit: number
): SearchSuggestion[] {
  const normalizedLimit = Math.max(0, Math.floor(limit));
  const normalizedQuery = normalizeLocalOmniboxQuery(query);
  if (normalizedLimit === 0 || normalizedQuery.length === 0) {
    return [];
  }
  const ranked: RankedLocalSuggestion[] = [];
  const seenUrls: Set<string> = new Set<string>();
  for (let index = 0; index < bookmarks.length; index += 1) {
    const bookmark = bookmarks[index];
    if (!isUserSearchableBookmark(bookmark)) {
      continue;
    }
    const url = (bookmark.url ?? '').trim();
    const urlKey = normalizeLocalOmniboxQuery(url);
    if (url.length === 0 || seenUrls.has(urlKey)) {
      continue;
    }
    const title = bookmark.title.trim();
    const host = hostFromLocalOmniboxUrl(url);
    const score = scoreLocalOmniboxText(normalizedQuery, title, host, url);
    if (score <= 0) {
      continue;
    }
    seenUrls.add(urlKey);
    considerLocalSuggestion(ranked, {
      suggestion: {
        id: `bookmark-suggestion-${bookmark.id}`,
        title: displayLocalOmniboxTitle(title, host),
        source: 'bookmarks',
        target: url,
        subtitle: host,
        icon: '',
        refId: bookmark.id,
        score: score
      },
      score: score
    }, normalizedLimit);
  }
  return ranked.map((item: RankedLocalSuggestion): SearchSuggestion => item.suggestion);
}

export function matchOpenTabSuggestions(
  tabs: BrowserTabState[],
  input: OpenTabSuggestionQuery
): SearchSuggestion[] {
  const normalizedLimit = Math.max(0, Math.floor(input.limit));
  const normalizedQuery = normalizeLocalOmniboxQuery(input.query);
  if (normalizedLimit === 0 || normalizedQuery.length === 0) {
    return [];
  }
  const ranked: RankedLocalSuggestion[] = [];
  for (let index = 0; index < tabs.length; index += 1) {
    const tab = tabs[index];
    if (!isSuggestableOpenTab(tab, input)) {
      continue;
    }
    const url = resolveOpenTabUrl(tab);
    const title = tab.title.trim().length > 0 ? tab.title.trim() : tab.lastGoodTitle.trim();
    const host = hostFromLocalOmniboxUrl(url);
    const textScore = scoreLocalOmniboxText(normalizedQuery, title, host, url);
    if (textScore <= 0) {
      continue;
    }
    const ageHours = Math.max(0, (Date.now() - tab.lastActiveAt) / 3600000);
    const rankingBoost = Math.max(0, 40 - Math.floor(ageHours));
    const score = textScore + rankingBoost;
    considerLocalSuggestion(ranked, {
      suggestion: {
        id: `tab-suggestion-${tab.id}`,
        title: displayLocalOmniboxTitle(title, host),
        source: 'tabs',
        target: url,
        subtitle: host,
        icon: '',
        refId: tab.id,
        score: score,
        rankingBoost: rankingBoost
      },
      score: score
    }, normalizedLimit);
  }
  return ranked.map((item: RankedLocalSuggestion): SearchSuggestion => item.suggestion);
}

export function resolveBookmarkSuggestionScope(
  privacyMode: BrowserSessionPrivacyMode,
  dataScope: BrowserDataScope
): BookmarkStorageScope {
  return privacyMode === 'private' || dataScope === 'session_ephemeral' ? 'private' : 'regular';
}

function isSuggestableOpenTab(tab: BrowserTabState, input: OpenTabSuggestionQuery): boolean {
  if (tab.id === input.activeTabId || tab.isHome) {
    return false;
  }
  if (tab.privacyMode !== input.privacyMode || tab.dataScope !== input.dataScope) {
    return false;
  }
  if (input.profileId !== undefined && tab.profileId !== input.profileId) {
    return false;
  }
  const url = resolveOpenTabUrl(tab).toLowerCase();
  return url.length > 0 && url !== 'about:blank' && !url.startsWith('aira:');
}

function resolveOpenTabUrl(tab: BrowserTabState): string {
  const url = tab.url.trim();
  if (url.length > 0) {
    return url;
  }
  const pending = tab.pendingUrl.trim();
  if (pending.length > 0) {
    return pending;
  }
  return tab.lastGoodUrl.trim();
}

function considerLocalSuggestion(
  ranked: RankedLocalSuggestion[],
  candidate: RankedLocalSuggestion,
  limit: number
): void {
  if (ranked.length < limit) {
    ranked.push(candidate);
    ranked.sort(compareLocalSuggestions);
    return;
  }
  if (candidate.score <= ranked[ranked.length - 1].score) {
    return;
  }
  ranked[ranked.length - 1] = candidate;
  ranked.sort(compareLocalSuggestions);
}

function compareLocalSuggestions(left: RankedLocalSuggestion, right: RankedLocalSuggestion): number {
  return right.score - left.score;
}

export function scoreLocalOmniboxText(query: string, title: string, host: string, url: string): number {
  return scoreNormalizedLocalOmniboxText(
    query, title.trim().toLowerCase(), host.trim().toLowerCase(), normalizeLocalOmniboxQuery(url)
  );
}

function scoreNormalizedLocalOmniboxText(
  query: string,
  normalizedTitle: string,
  normalizedHost: string,
  compactUrl: string
): number {
  if (normalizedHost === query || compactUrl === query || normalizedTitle === query) {
    return 800;
  }
  if (normalizedHost.startsWith(query) || normalizedTitle.startsWith(query) || compactUrl.startsWith(query)) {
    return 600;
  }
  if (normalizedTitle.indexOf(query) >= 0 || normalizedHost.indexOf(query) >= 0 || compactUrl.indexOf(query) >= 0) {
    return 300;
  }
  return 0;
}

function displayLocalOmniboxTitle(title: string, host: string): string {
  const trimmedTitle = title.trim();
  if (trimmedTitle.length > 0) {
    return trimmedTitle;
  }
  return host.length > 0 ? host : '';
}

export function normalizeLocalOmniboxQuery(value: string): string {
  return normalizeNavigationSearchText(value);
}

function hostFromLocalOmniboxUrl(url: string): string {
  const compact = normalizeLocalOmniboxQuery(url);
  const slash = compact.indexOf('/');
  const hostWithPort = slash < 0 ? compact : compact.substring(0, slash);
  const port = hostWithPort.indexOf(':');
  return port < 0 ? hostWithPort : hostWithPort.substring(0, port);
}
