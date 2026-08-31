import {
  BrowserDataBoundaryInput,
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  buildBrowserDataBoundary,
  SearchSuggestion,
  SearchSuggestionPreferences
} from '../../common/models/BrowserModels';
import { looksLikeUrl } from '../../common/utils/UrlUtils';
import { DEFAULT_SEARCH_SUGGESTION_POLICY } from '../../features/search/SearchSuggestionPolicy';
import {
  SEARCH_QUERY_HISTORY_VISIBLE_LIMIT,
  SearchQueryHistorySuggestionInput,
  SearchQueryHistoryService
} from '../../services/search/SearchQueryHistoryService';
import { QihooSearchSuggestionService } from '../../services/search/QihooSearchSuggestionService';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';

export interface BrowserSearchSuggestionSnapshot {
  homeSearchFocused: boolean;
  homeSearchOverlayVisible: boolean;
  showSearchSuggestions: boolean;
  searchSuggestions: SearchSuggestion[];
}

export interface BrowserSearchSuggestionRuntimeFacts {
  query: string;
  addressFocused: boolean;
  tabs: BrowserTabState[];
  activeTabId: string;
  currentPageSuggestionEnabled: boolean;
  profileId?: BrowserProfileId;
  privacyMode?: BrowserSessionPrivacyMode;
  dataScope?: BrowserDataScope;
  preferences: SearchSuggestionPreferences;
}

export interface BrowserSearchSuggestionSessionInput {
  query: string;
  focused: boolean;
  protectKeyboardSession?: boolean;
}

export interface BrowserSearchSuggestionShell {
  resolveFacts: () => BrowserSearchSuggestionRuntimeFacts;
  publishSnapshot: (snapshot: BrowserSearchSuggestionSnapshot) => void;
  protectAddressKeyboardSession: () => void;
  openAddressSuggestion: (target: string) => void;
}

interface BrowserSearchSuggestionRuntimeSource {
  activeTab?: BrowserTabState;
  currentPageSuggestionEnabled: boolean;
  boundary: SearchSuggestionBoundary;
  preferences: SearchSuggestionPreferences;
}

interface SearchSuggestionBoundary {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

interface BrowserSearchSuggestionContentState {
  suggestions: SearchSuggestion[];
}

interface CachedEmptySuggestions {
  key: string;
  suggestions: SearchSuggestion[];
}

const HOME_DEFERRED_SUGGESTION_REFRESH_DELAY_MS: number =
  DEFAULT_SEARCH_SUGGESTION_POLICY.timing.deferredRefreshDelayMs;

function createHiddenBrowserSearchSuggestionSnapshot(): BrowserSearchSuggestionSnapshot {
  return {
    homeSearchFocused: false,
    homeSearchOverlayVisible: false,
    showSearchSuggestions: false,
    searchSuggestions: []
  };
}

export class BrowserSearchSuggestionCoordinator {
  private readonly shell: BrowserSearchSuggestionShell;
  private readonly searchQueryHistoryService: SearchQueryHistoryService;
  private readonly tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  private readonly remoteSearchSuggestionService: QihooSearchSuggestionService = new QihooSearchSuggestionService();
  private snapshot: BrowserSearchSuggestionSnapshot = createHiddenBrowserSearchSuggestionSnapshot();
  private emptyCache?: CachedEmptySuggestions;
  private revealRefreshTimeout: number = -1;
  private deferredRefreshTimeout: number = -1;
  private prewarmTimeout: number = -1;
  private remoteRefreshGeneration: number = 0;
  private searchHistoryHydrationGeneration: number = 0;
  private searchSessionActive: boolean = false;
  private searchSessionAuthorityId: string = '';
  private searchSessionInput?: BrowserSearchSuggestionSessionInput;

  constructor(
    shell: BrowserSearchSuggestionShell,
    searchQueryHistoryService: SearchQueryHistoryService,
    tabSwitchCoordinator: BrowserTabSwitchCoordinator
  ) {
    this.shell = shell;
    this.searchQueryHistoryService = searchQueryHistoryService;
    this.tabSwitchCoordinator = tabSwitchCoordinator;
  }

  getSnapshot(): BrowserSearchSuggestionSnapshot {
    return this.copySnapshot(this.snapshot);
  }

  hasVisibleSuggestions(): boolean {
    return this.snapshot.showSearchSuggestions && this.snapshot.searchSuggestions.length > 0;
  }

  refresh(): void {
    if (!this.searchSessionActive) {
      return;
    }
    this.clearRevealRefresh();
    this.clearDeferredRefresh();
    const query = this.resolveRuntimeFacts().query;
    this.publishContent(this.refreshWithQuery(query));
    this.refreshRemoteSearchSuggestions(query);
  }

  refreshDeferred(): void {
    if (!this.searchSessionActive) {
      return;
    }
    this.clearDeferredRefresh();
    this.deferredRefreshTimeout = setTimeout(() => {
      this.deferredRefreshTimeout = -1;
      this.refresh();
    }, HOME_DEFERRED_SUGGESTION_REFRESH_DELAY_MS);
  }

  reveal(): void {
    if (!this.searchSessionActive) {
      return;
    }
    this.publishOverlay(false, true, this.hasVisibleSuggestions());
    if (this.hasVisibleSuggestions()) {
      return;
    }
    const query = this.resolveRuntimeFacts().query;
    const trimmedQuery = query.trim();
    if (trimmedQuery.length === 0 && this.emptyCache !== undefined) {
      this.publishContent({ suggestions: this.emptyCache.suggestions });
      return;
    }
    this.scheduleRevealRefresh();
  }

  prewarm(): void {
    this.clearPrewarm();
    this.prewarmTimeout = setTimeout(() => {
      this.prewarmTimeout = -1;
      this.buildEmptySuggestionsForCache();
    }, DEFAULT_SEARCH_SUGGESTION_POLICY.timing.prewarmDelayMs);
  }

  invalidate(): void {
    this.emptyCache = undefined;
    if (this.searchSessionActive && this.hasVisibleSuggestions()) {
      this.refresh();
    }
  }

  deleteHistorySuggestion(suggestion: SearchSuggestion): Promise<boolean> {
    const recordId = suggestion.source === 'search_history' ? suggestion.refId?.trim() ?? '' : '';
    if (recordId.length === 0) {
      return Promise.resolve(false);
    }
    return this.searchQueryHistoryService.deleteSearchHistoryById(recordId)
      .then((result) => {
        if (result.removedCount <= 0) {
          return false;
        }
        this.emptyCache = undefined;
        if (this.searchSessionActive) {
          this.refresh();
        }
        return true;
      })
      .catch((_error: Error) => false);
  }

  openSuggestion(suggestion: SearchSuggestion): void {
    this.reset();
    if (suggestion.source === 'tabs' && suggestion.refId !== undefined && suggestion.refId.length > 0) {
      void this.tabSwitchCoordinator.switchToTab(suggestion.refId);
      return;
    }
    this.shell.openAddressSuggestion(suggestion.target);
  }

  beginSearchSession(
    authorityId: string = '',
    input?: BrowserSearchSuggestionSessionInput
  ): void {
    const normalizedAuthorityId = authorityId.trim().length > 0 ? authorityId.trim() : 'legacy-search-session';
    if (this.searchSessionActive && this.searchSessionAuthorityId === normalizedAuthorityId) {
      if (input !== undefined) {
        this.searchSessionInput = this.copySessionInput(input);
      }
      this.publishOverlay(true, true, this.hasVisibleSuggestions());
      return;
    }
    if (this.searchSessionActive) {
      this.cancelPendingWork();
    }
    this.searchSessionActive = true;
    this.searchSessionAuthorityId = normalizedAuthorityId;
    this.searchSessionInput = input === undefined ? undefined : this.copySessionInput(input);
    this.publishOverlay(true, true, this.hasVisibleSuggestions());
    this.refresh();
  }

  updateSearchSessionInput(
    authorityId: string,
    input: BrowserSearchSuggestionSessionInput
  ): boolean {
    if (!this.searchSessionActive || authorityId.trim() !== this.searchSessionAuthorityId) {
      return false;
    }
    this.searchSessionInput = this.copySessionInput(input);
    return true;
  }

  beginClosingOverlay(): void {
    this.searchSessionActive = false;
    this.searchSessionAuthorityId = '';
    this.searchSessionInput = undefined;
    this.publishOverlay(false, true, this.hasVisibleSuggestions());
  }

  setHomeSearchFocused(focused: boolean): void {
    this.publishOverlay(
      focused,
      focused || this.snapshot.homeSearchOverlayVisible,
      this.hasVisibleSuggestions()
    );
  }

  reset(): void {
    this.cancelPendingWork();
    this.publishSnapshot(createHiddenBrowserSearchSuggestionSnapshot());
  }

  cancelPendingWork(): void {
    this.searchSessionActive = false;
    this.searchSessionAuthorityId = '';
    this.searchSessionInput = undefined;
    this.clearRevealRefresh();
    this.clearDeferredRefresh();
    this.clearPrewarm();
    this.cancelRemoteSearchSuggestions();
    this.cancelSearchHistoryHydration();
  }

  private publishOverlay(focused: boolean, visible: boolean, showSuggestions: boolean): void {
    this.publishSnapshot({
      homeSearchFocused: focused,
      homeSearchOverlayVisible: visible,
      showSearchSuggestions: showSuggestions && this.snapshot.searchSuggestions.length > 0,
      searchSuggestions: this.snapshot.searchSuggestions
    });
  }

  private publishContent(content: BrowserSearchSuggestionContentState): void {
    const facts = this.resolveRuntimeFacts();
    if (facts.addressFocused && this.shouldProtectKeyboardSession()) {
      this.shell.protectAddressKeyboardSession();
    }
    this.publishSnapshot({
      homeSearchFocused: this.snapshot.homeSearchFocused,
      homeSearchOverlayVisible: this.snapshot.homeSearchOverlayVisible,
      showSearchSuggestions: content.suggestions.length > 0,
      searchSuggestions: content.suggestions
    });
  }

  private publishSnapshot(snapshot: BrowserSearchSuggestionSnapshot): void {
    this.snapshot = this.copySnapshot(snapshot);
    this.shell.publishSnapshot(this.copySnapshot(this.snapshot));
  }

  private copySnapshot(snapshot: BrowserSearchSuggestionSnapshot): BrowserSearchSuggestionSnapshot {
    return {
      homeSearchFocused: snapshot.homeSearchFocused,
      homeSearchOverlayVisible: snapshot.homeSearchOverlayVisible,
      showSearchSuggestions: snapshot.showSearchSuggestions,
      searchSuggestions: snapshot.searchSuggestions.slice()
    };
  }

  private scheduleRevealRefresh(): void {
    this.clearRevealRefresh();
    this.revealRefreshTimeout = setTimeout(() => {
      this.revealRefreshTimeout = -1;
      this.refresh();
    }, DEFAULT_SEARCH_SUGGESTION_POLICY.timing.revealRefreshDelayMs);
  }

  private clearRevealRefresh(): void {
    if (this.revealRefreshTimeout >= 0) {
      clearTimeout(this.revealRefreshTimeout);
      this.revealRefreshTimeout = -1;
    }
  }

  private clearDeferredRefresh(): void {
    if (this.deferredRefreshTimeout >= 0) {
      clearTimeout(this.deferredRefreshTimeout);
      this.deferredRefreshTimeout = -1;
    }
  }

  private clearPrewarm(): void {
    if (this.prewarmTimeout >= 0) {
      clearTimeout(this.prewarmTimeout);
      this.prewarmTimeout = -1;
    }
  }

  private refreshWithQuery(query: string, hydrateHistory: boolean = true): BrowserSearchSuggestionContentState {
    if (query.trim().length === 0) {
      const cacheKey = this.buildEmptyCacheKey(this.buildRuntimeSource());
      if (!hydrateHistory && this.emptyCache !== undefined && this.emptyCache.key === cacheKey) {
        return { suggestions: this.emptyCache.suggestions.slice() };
      }
      const content = this.buildSearchHistoryContent(query, hydrateHistory);
      this.emptyCache = {
        key: cacheKey,
        suggestions: content.suggestions.slice()
      };
      return content;
    }
    return this.buildSearchHistoryContent(query, hydrateHistory);
  }

  private buildEmptySuggestionsForCache(): void {
    const runtimeSource = this.buildRuntimeSource();
    const content = this.buildSearchHistoryContent('', false);
    this.emptyCache = {
      key: this.buildEmptyCacheKey(runtimeSource),
      suggestions: content.suggestions.slice()
    };
  }

  private buildSearchHistoryContent(
    query: string,
    hydrateHistory: boolean = true
  ): BrowserSearchSuggestionContentState {
    const runtimeSource = this.buildRuntimeSource();
    const suggestionInput: SearchQueryHistorySuggestionInput = {
      query: query,
      profileId: runtimeSource.boundary.profileId,
      privacyMode: runtimeSource.boundary.privacyMode,
      dataScope: runtimeSource.boundary.dataScope,
      preferences: runtimeSource.preferences,
      limit: SEARCH_QUERY_HISTORY_VISIBLE_LIMIT
    };
    let suggestions: SearchSuggestion[] = this.searchQueryHistoryService.buildSuggestions(suggestionInput);
    if (hydrateHistory) {
      this.hydrateSearchHistory(query, suggestionInput);
    }
    suggestions = this.removeActiveTabSuggestion(suggestions, runtimeSource);
    return { suggestions: suggestions };
  }

  private hydrateSearchHistory(query: string, input: SearchQueryHistorySuggestionInput): void {
    const generation = this.beginSearchHistoryHydration();
    this.searchQueryHistoryService.hydrateSuggestions(input)
      .then((result) => {
        if (!result.hydrated || !this.isCurrentSearchHistoryHydration(generation, query)) {
          return;
        }
        this.emptyCache = undefined;
        this.publishContent(this.refreshWithQuery(query, false));
      })
      .catch((_error: Error) => {});
  }

  private refreshRemoteSearchSuggestions(query: string): void {
    const runtimeSource = this.buildRuntimeSource();
    const generation = this.beginRemoteSearchSuggestionRefresh();
    if (!this.shouldFetchRemoteSearchSuggestions(query, runtimeSource)) {
      return;
    }
    const trimmedQuery = query.trim();
    this.remoteSearchSuggestionService.fetchSuggestions(trimmedQuery, SEARCH_QUERY_HISTORY_VISIBLE_LIMIT)
      .then((remoteWords: string[]) => {
        if (!this.isCurrentRemoteSearchSuggestionRefresh(generation, query)) {
          return;
        }
        const latestSource = this.buildRuntimeSource();
        if (!this.shouldFetchRemoteSearchSuggestions(query, latestSource)) {
          return;
        }
        const historyContent = this.buildSearchHistoryContent(query);
        const mergedSuggestions = this.mergeSearchSuggestions(
          historyContent.suggestions,
          this.buildRemoteSearchSuggestions(remoteWords),
          SEARCH_QUERY_HISTORY_VISIBLE_LIMIT
        );
        this.publishContent({ suggestions: mergedSuggestions });
      })
      .catch((_error: Error) => {});
  }

  private buildRuntimeSource(): BrowserSearchSuggestionRuntimeSource {
    const facts = this.resolveRuntimeFacts();
    const boundaryInput: BrowserDataBoundaryInput = {
      profileId: facts.profileId,
      privacyMode: facts.privacyMode,
      dataScope: facts.dataScope
    };
    const boundary = buildBrowserDataBoundary(boundaryInput);
    return {
      activeTab: facts.tabs.find((tab: BrowserTabState): boolean => tab.id === facts.activeTabId),
      currentPageSuggestionEnabled: facts.currentPageSuggestionEnabled,
      boundary: {
        profileId: boundary.profileId,
        privacyMode: boundary.privacyMode,
        dataScope: boundary.dataScope
      },
      preferences: facts.preferences
    };
  }

  private removeActiveTabSuggestion(
    suggestions: SearchSuggestion[],
    runtimeSource: BrowserSearchSuggestionRuntimeSource
  ): SearchSuggestion[] {
    if (!runtimeSource.currentPageSuggestionEnabled || runtimeSource.activeTab === undefined) {
      return suggestions;
    }
    const activeTabId = runtimeSource.activeTab.id;
    return suggestions.filter((suggestion: SearchSuggestion): boolean => {
      return suggestion.source !== 'tabs' || suggestion.refId !== activeTabId;
    });
  }

  private shouldFetchRemoteSearchSuggestions(
    query: string,
    source: BrowserSearchSuggestionRuntimeSource
  ): boolean {
    const trimmedQuery = query.trim();
    return source.preferences.regularEnabled &&
      source.preferences.remoteEnabled &&
      source.boundary.privacyMode !== 'private' &&
      source.boundary.dataScope !== 'session_ephemeral' &&
      trimmedQuery.length > 0 &&
      !looksLikeUrl(trimmedQuery);
  }

  private buildRemoteSearchSuggestions(words: string[]): SearchSuggestion[] {
    const suggestions: SearchSuggestion[] = [];
    const seenKeys: Set<string> = new Set<string>();
    words.forEach((word: string, index: number) => {
      const trimmedWord = word.trim();
      const key = trimmedWord.toLowerCase();
      if (trimmedWord.length === 0 || seenKeys.has(key) || suggestions.length >= SEARCH_QUERY_HISTORY_VISIBLE_LIMIT) {
        return;
      }
      seenKeys.add(key);
      suggestions.push({
        id: `remote-search-suggestion-${this.compactSuggestionKey(trimmedWord)}-${index}`,
        title: trimmedWord,
        source: 'suggestions',
        target: trimmedWord,
        subtitle: '',
        icon: ''
      });
    });
    return suggestions;
  }

  private mergeSearchSuggestions(
    historySuggestions: SearchSuggestion[],
    remoteSuggestions: SearchSuggestion[],
    limit: number
  ): SearchSuggestion[] {
    const merged: SearchSuggestion[] = [];
    const seenKeys: Set<string> = new Set<string>();
    this.appendUniqueSearchSuggestions(merged, seenKeys, historySuggestions, limit);
    this.appendUniqueSearchSuggestions(merged, seenKeys, remoteSuggestions, limit);
    return merged;
  }

  private appendUniqueSearchSuggestions(
    target: SearchSuggestion[],
    seenKeys: Set<string>,
    source: SearchSuggestion[],
    limit: number
  ): void {
    const normalizedLimit = Math.max(0, Math.floor(limit));
    for (let index = 0; index < source.length && target.length < normalizedLimit; index += 1) {
      const suggestion = source[index];
      const key = this.buildSuggestionDedupKey(suggestion);
      if (key.length === 0 || seenKeys.has(key)) {
        continue;
      }
      seenKeys.add(key);
      target.push(suggestion);
    }
  }

  private buildSuggestionDedupKey(suggestion: SearchSuggestion): string {
    const target = suggestion.target.trim();
    const title = suggestion.title.trim();
    return (target.length > 0 ? target : title).toLowerCase();
  }

  private compactSuggestionKey(value: string): string {
    return value.trim().toLowerCase().replace(/\s+/g, '');
  }

  private beginRemoteSearchSuggestionRefresh(): number {
    this.remoteRefreshGeneration += 1;
    return this.remoteRefreshGeneration;
  }

  private cancelRemoteSearchSuggestions(): void {
    this.remoteRefreshGeneration += 1;
  }

  private cancelSearchHistoryHydration(): void {
    this.searchHistoryHydrationGeneration += 1;
  }

  private isCurrentRemoteSearchSuggestionRefresh(generation: number, query: string): boolean {
    return generation === this.remoteRefreshGeneration &&
      this.searchSessionActive &&
      this.resolveRuntimeFacts().query === query;
  }

  private beginSearchHistoryHydration(): number {
    this.searchHistoryHydrationGeneration += 1;
    return this.searchHistoryHydrationGeneration;
  }

  private isCurrentSearchHistoryHydration(generation: number, query: string): boolean {
    return generation === this.searchHistoryHydrationGeneration &&
      this.searchSessionActive &&
      this.resolveRuntimeFacts().query === query;
  }

  private resolveRuntimeFacts(): BrowserSearchSuggestionRuntimeFacts {
    const facts = this.shell.resolveFacts();
    if (this.searchSessionInput === undefined) {
      return facts;
    }
    return {
      query: this.searchSessionInput.query,
      addressFocused: this.searchSessionInput.focused,
      tabs: facts.tabs,
      activeTabId: facts.activeTabId,
      currentPageSuggestionEnabled: facts.currentPageSuggestionEnabled,
      profileId: facts.profileId,
      privacyMode: facts.privacyMode,
      dataScope: facts.dataScope,
      preferences: facts.preferences
    };
  }

  private copySessionInput(input: BrowserSearchSuggestionSessionInput): BrowserSearchSuggestionSessionInput {
    return {
      query: input.query,
      focused: input.focused,
      protectKeyboardSession: input.protectKeyboardSession
    };
  }

  private shouldProtectKeyboardSession(): boolean {
    return this.searchSessionInput?.protectKeyboardSession !== false;
  }

  private buildEmptyCacheKey(source: BrowserSearchSuggestionRuntimeSource): string {
    return [
      source.boundary.profileId,
      source.boundary.privacyMode,
      source.boundary.dataScope,
      source.preferences.historyEnabled ? 'history-enabled' : 'history-disabled',
      source.currentPageSuggestionEnabled ? 'current-page-enabled' : 'current-page-disabled',
      source.activeTab?.id ?? '',
      source.activeTab?.url ?? ''
    ].join('::');
  }
}
