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
import { composeSearchSuggestions } from '../../features/search/SearchSuggestionComposer';
import { resolveAppResourceText } from '../resources/AppResourceText';
import { browserNativeTabSceneService } from './BrowserNativeTabSceneService';
import {
  SearchQueryHistorySuggestionInput,
  SearchQueryHistoryService
} from '../../services/search/SearchQueryHistoryService';
import { QihooSearchSuggestionService } from '../../services/search/QihooSearchSuggestionService';
import { HistoryOmniboxSuggestionService } from '../../services/search/HistoryOmniboxSuggestionService';
import { BookmarkOmniboxSuggestionService } from '../../services/search/BookmarkOmniboxSuggestionService';
import {
  matchOpenTabSuggestions,
  resolveBookmarkSuggestionScope
} from '../../services/search/LocalOmniboxSuggestionMatcher';
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

interface BrowserSearchSuggestionSourceContent {
  key: string;
  query: string;
  tabs: SearchSuggestion[];
  bookmarks: SearchSuggestion[];
  browsingHistory: SearchSuggestion[];
  searchHistory: SearchSuggestion[];
  remotePending: boolean;
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
  private readonly historyOmniboxSuggestionService: HistoryOmniboxSuggestionService;
  private readonly bookmarkOmniboxSuggestionService: BookmarkOmniboxSuggestionService;
  private readonly remoteSearchSuggestionService: QihooSearchSuggestionService = new QihooSearchSuggestionService();
  private snapshot: BrowserSearchSuggestionSnapshot = createHiddenBrowserSearchSuggestionSnapshot();
  private emptyCache?: CachedEmptySuggestions;
  private sourceContent?: BrowserSearchSuggestionSourceContent;
  private revealRefreshTimeout: number = -1;
  private deferredRefreshTimeout: number = -1;
  private remoteRefreshTimeout: number = -1;
  private prewarmTimeout: number = -1;
  private remoteRefreshGeneration: number = 0;
  private searchHistoryHydrationGeneration: number = 0;
  private browsingHistoryHydrationGeneration: number = 0;
  private bookmarkHydrationGeneration: number = 0;
  private cachedRemoteSuggestions: SearchSuggestion[] = [];
  private cachedRemoteKey: string = '';
  private searchSessionActive: boolean = false;
  private searchSessionAuthorityId: string = '';
  private searchSessionInput?: BrowserSearchSuggestionSessionInput;

  constructor(
    shell: BrowserSearchSuggestionShell,
    searchQueryHistoryService: SearchQueryHistoryService,
    tabSwitchCoordinator: BrowserTabSwitchCoordinator,
    historyOmniboxSuggestionService: HistoryOmniboxSuggestionService,
    bookmarkOmniboxSuggestionService: BookmarkOmniboxSuggestionService
  ) {
    this.shell = shell;
    this.searchQueryHistoryService = searchQueryHistoryService;
    this.tabSwitchCoordinator = tabSwitchCoordinator;
    this.historyOmniboxSuggestionService = historyOmniboxSuggestionService;
    this.bookmarkOmniboxSuggestionService = bookmarkOmniboxSuggestionService;
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
    this.cancelSearchHistoryHydration();
    this.cancelBrowsingHistoryHydration();
    this.cancelBookmarkHydration();
    const query = this.resolveRuntimeFacts().query;
    const source = this.buildRuntimeSource();
    const content = this.buildSourceContent(query, source);
    this.sourceContent = content;
    this.publishSuggestionContent(content);
    this.hydrateSearchHistory(content, this.buildSearchHistoryInput(query, source));
    this.scheduleRemoteSearchSuggestions(content);
    this.refreshBrowsingHistoryIndex(content);
    this.refreshBookmarkIndex(content);
  }

  refreshDeferred(): void {
    if (!this.searchSessionActive) {
      return;
    }
    // Invalidate callbacks at input time, before the coalesced local refresh runs.
    this.cancelRemoteSearchSuggestions();
    this.cancelSearchHistoryHydration();
    this.cancelBrowsingHistoryHydration();
    this.cancelBookmarkHydration();
    if (this.deferredRefreshTimeout >= 0) {
      return;
    }
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
    if (trimmedQuery.length === 0 && this.emptyCache !== undefined &&
      this.emptyCache.key === this.buildEmptyCacheKey(this.buildRuntimeSource())) {
      this.publishContent({ suggestions: this.emptyCache.suggestions });
      return;
    }
    this.scheduleRevealRefresh();
  }

  prewarm(): void {
    this.clearPrewarm();
    this.prewarmTimeout = setTimeout(() => {
      this.prewarmTimeout = -1;
      const source = this.buildRuntimeSource();
      if (this.shouldUseBrowsingHistory(source)) {
        this.historyOmniboxSuggestionService.ensureLoaded().catch((_error: Error) => {});
      }
      if (source.preferences.bookmarksEnabled) {
        this.bookmarkOmniboxSuggestionService.prewarm(
          resolveBookmarkSuggestionScope(source.boundary.privacyMode, source.boundary.dataScope)
        ).catch((_error: Error) => {});
      }
      this.buildEmptySuggestionsForCache();
    }, DEFAULT_SEARCH_SUGGESTION_POLICY.timing.prewarmDelayMs);
  }

  invalidate(): void {
    this.emptyCache = undefined;
    if (this.searchSessionActive) {
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

  /**
   * Clears every search-history record for the current boundary.
   *
   * Runs against the same session boundary the suggestions were built from, so
   * clearing from the dropdown cannot reach another profile's history. The
   * privacy effect policy still gates the mutation inside the service.
   */
  clearHistorySuggestions(): Promise<boolean> {
    const facts = this.resolveRuntimeFacts();
    const boundaryInput: BrowserDataBoundaryInput = {
      profileId: facts.profileId,
      privacyMode: facts.privacyMode,
      dataScope: facts.dataScope
    };
    return this.searchQueryHistoryService.clearRegularProfileSearchHistory(boundaryInput)
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
    this.cancelPendingWork();
    this.searchSessionActive = true;
    this.searchSessionAuthorityId = normalizedAuthorityId;
    this.searchSessionInput = input === undefined ? undefined : this.copySessionInput(input);
    this.publishSnapshot({
      homeSearchFocused: true,
      homeSearchOverlayVisible: true,
      showSearchSuggestions: false,
      searchSuggestions: []
    });
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
    this.cancelBrowsingHistoryHydration();
    this.cancelBookmarkHydration();
    this.sourceContent = undefined;
    this.cachedRemoteSuggestions = [];
    this.cachedRemoteKey = '';
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

  private buildEmptySuggestionsForCache(): void {
    const source = this.buildRuntimeSource();
    this.emptyCache = {
      key: this.buildEmptyCacheKey(source),
      suggestions: this.searchQueryHistoryService.buildSuggestions(this.buildSearchHistoryInput('', source))
    };
  }

  private buildSearchHistoryInput(
    query: string,
    source: BrowserSearchSuggestionRuntimeSource
  ): SearchQueryHistorySuggestionInput {
    return {
      query: query,
      profileId: source.boundary.profileId,
      privacyMode: source.boundary.privacyMode,
      dataScope: source.boundary.dataScope,
      preferences: source.preferences,
      limit: query.trim().length === 0 ? DEFAULT_SEARCH_SUGGESTION_POLICY.presentation.emptyLimit
        : DEFAULT_SEARCH_SUGGESTION_POLICY.candidates.search
    };
  }

  private buildSourceContent(
    query: string,
    source: BrowserSearchSuggestionRuntimeSource
  ): BrowserSearchSuggestionSourceContent {
    return {
      key: this.buildContentKey(query, source),
      query: query,
      tabs: this.buildOpenTabSuggestions(query, source),
      bookmarks: this.buildBookmarkSuggestions(query, source),
      browsingHistory: this.buildBrowsingHistorySuggestions(query, source),
      // The resting list carries search terms only. Clearing search history must empty it.
      searchHistory: this.searchQueryHistoryService.buildSuggestions(this.buildSearchHistoryInput(query, source)),
      remotePending: this.shouldFetchRemoteSearchSuggestions(query, source) &&
        this.cachedRemoteKey !== this.buildContentKey(query, source)
    };
  }

  private hydrateSearchHistory(
    content: BrowserSearchSuggestionSourceContent,
    input: SearchQueryHistorySuggestionInput
  ): void {
    const generation = this.beginSearchHistoryHydration();
    this.searchQueryHistoryService.hydrateSuggestions(input)
      .then((result) => {
        if (!result.hydrated || generation !== this.searchHistoryHydrationGeneration ||
          !this.isCurrentContent(content)) {
          return;
        }
        content.searchHistory = this.searchQueryHistoryService.buildSuggestions(input);
        this.publishSuggestionContent(content);
      })
      .catch((_error: Error) => {});
  }

  private buildOpenTabSuggestions(
    query: string,
    runtimeSource: BrowserSearchSuggestionRuntimeSource
  ): SearchSuggestion[] {
    if (!runtimeSource.preferences.openTabsEnabled || query.trim().length === 0) {
      return [];
    }
    return matchOpenTabSuggestions(this.resolveRuntimeFacts().tabs, {
      query: query,
      activeTabId: runtimeSource.activeTab?.id ?? '',
      privacyMode: runtimeSource.boundary.privacyMode,
      dataScope: runtimeSource.boundary.dataScope,
      profileId: runtimeSource.boundary.profileId,
      limit: DEFAULT_SEARCH_SUGGESTION_POLICY.candidates.local
    });
  }

  private buildBookmarkSuggestions(
    query: string,
    runtimeSource: BrowserSearchSuggestionRuntimeSource
  ): SearchSuggestion[] {
    if (!runtimeSource.preferences.bookmarksEnabled || query.trim().length === 0) {
      return [];
    }
    const activeUrl = (runtimeSource.activeTab?.url ?? '').trim().toLowerCase();
    return this.bookmarkOmniboxSuggestionService.buildSuggestions(
      query,
      resolveBookmarkSuggestionScope(runtimeSource.boundary.privacyMode, runtimeSource.boundary.dataScope),
      DEFAULT_SEARCH_SUGGESTION_POLICY.candidates.local
    ).filter((suggestion: SearchSuggestion): boolean => {
      return activeUrl.length === 0 || suggestion.target.trim().toLowerCase() !== activeUrl;
    });
  }

  private buildBrowsingHistorySuggestions(
    query: string,
    runtimeSource: BrowserSearchSuggestionRuntimeSource
  ): SearchSuggestion[] {
    if (!this.shouldUseBrowsingHistory(runtimeSource) || query.trim().length === 0) {
      return [];
    }
    const activeUrl = (runtimeSource.activeTab?.url ?? '').trim().toLowerCase();
    return this.historyOmniboxSuggestionService.buildSuggestions(query, DEFAULT_SEARCH_SUGGESTION_POLICY.candidates.local)
      .filter((suggestion: SearchSuggestion): boolean => {
        return activeUrl.length === 0 || suggestion.target.trim().toLowerCase() !== activeUrl;
      });
  }

  private shouldUseBrowsingHistory(source: BrowserSearchSuggestionRuntimeSource): boolean {
    return source.preferences.browsingHistoryEnabled &&
      source.boundary.privacyMode !== 'private' &&
      source.boundary.dataScope !== 'session_ephemeral';
  }

  private refreshBookmarkIndex(content: BrowserSearchSuggestionSourceContent): void {
    const source = this.buildRuntimeSource();
    const generation = ++this.bookmarkHydrationGeneration;
    if (!source.preferences.bookmarksEnabled || content.query.trim().length === 0) {
      return;
    }
    const scope = resolveBookmarkSuggestionScope(source.boundary.privacyMode, source.boundary.dataScope);
    this.bookmarkOmniboxSuggestionService.ensureLoaded(scope)
      .then((loaded: boolean) => {
        if (!loaded || generation !== this.bookmarkHydrationGeneration || !this.isCurrentContent(content)) {
          return;
        }
        content.bookmarks = this.buildBookmarkSuggestions(content.query, this.buildRuntimeSource());
        this.publishSuggestionContent(content);
      })
      .catch((_error: Error) => {});
  }

  private refreshBrowsingHistoryIndex(content: BrowserSearchSuggestionSourceContent): void {
    const runtimeSource = this.buildRuntimeSource();
    const generation = this.beginBrowsingHistoryHydration();
    if (!this.shouldUseBrowsingHistory(runtimeSource) || content.query.trim().length === 0) {
      return;
    }
    this.historyOmniboxSuggestionService.ensureLoaded()
      .then((loaded: boolean) => {
        if (!loaded || generation !== this.browsingHistoryHydrationGeneration || !this.isCurrentContent(content)) {
          return;
        }
        content.browsingHistory = this.buildBrowsingHistorySuggestions(content.query, this.buildRuntimeSource());
        this.publishSuggestionContent(content);
      })
      .catch((_error: Error) => {});
  }

  private publishSuggestionContent(content: BrowserSearchSuggestionSourceContent): void {
    if (!this.isCurrentContent(content)) {
      return;
    }
    const remote = this.cachedRemoteKey === content.key ? this.cachedRemoteSuggestions : [];
    const composition = composeSearchSuggestions({
      query: content.query,
      tabs: this.removeActiveTabSuggestion(content.tabs, this.buildRuntimeSource()),
      bookmarks: content.bookmarks,
      browsingHistory: content.browsingHistory,
      searchHistory: content.searchHistory,
      remote: remote,
      remotePending: content.remotePending
    });
    const suggestions = composition.suggestions;
    if (composition.hasMoreBookmarks) {
      suggestions.push(this.buildBookmarkSearchSuggestion(content.query));
    }
    if (content.query.trim().length === 0) {
      this.emptyCache = {
        key: this.buildEmptyCacheKey(this.buildRuntimeSource()),
        suggestions: suggestions.slice()
      };
    }
    this.publishContent({ suggestions: suggestions });
  }

  private buildBookmarkSearchSuggestion(query: string): SearchSuggestion {
    const source = this.buildRuntimeSource();
    const scope = resolveBookmarkSuggestionScope(source.boundary.privacyMode, source.boundary.dataScope);
    return {
      id: `bookmark-search-${scope}-${this.compactSuggestionKey(query)}`,
      source: 'bookmark_search',
      title: resolveAppResourceText($r('app.string.search_suggestion_all_bookmarks')),
      subtitle: query.trim(),
      target: browserNativeTabSceneService.buildBookmarkRoute({ folderId: '', query: query, scope: scope }),
      icon: ''
    };
  }

  private scheduleRemoteSearchSuggestions(content: BrowserSearchSuggestionSourceContent): void {
    this.cancelRemoteSearchSuggestions();
    if (!this.shouldFetchRemoteSearchSuggestions(content.query, this.buildRuntimeSource())) {
      this.cachedRemoteSuggestions = [];
      this.cachedRemoteKey = '';
      return;
    }
    if (this.cachedRemoteKey === content.key) {
      return;
    }
    const generation = this.remoteRefreshGeneration;
    this.remoteRefreshTimeout = setTimeout(() => {
      this.remoteRefreshTimeout = -1;
      if (generation !== this.remoteRefreshGeneration || !this.isCurrentContent(content)) {
        return;
      }
      this.refreshRemoteSearchSuggestions(content, generation);
    }, DEFAULT_SEARCH_SUGGESTION_POLICY.timing.remoteRefreshDelayMs);
  }

  private refreshRemoteSearchSuggestions(content: BrowserSearchSuggestionSourceContent, generation: number): void {
    this.remoteSearchSuggestionService.fetchSuggestions(content.query.trim(), DEFAULT_SEARCH_SUGGESTION_POLICY.candidates.search)
      .then((remoteWords: string[]) => {
        if (generation !== this.remoteRefreshGeneration || !this.isCurrentContent(content) ||
          !this.shouldFetchRemoteSearchSuggestions(content.query, this.buildRuntimeSource())) {
          return;
        }
        content.remotePending = false;
        this.cachedRemoteKey = content.key;
        this.cachedRemoteSuggestions = this.buildRemoteSearchSuggestions(remoteWords);
        this.publishSuggestionContent(content);
      })
      .catch((_error: Error) => {
        if (generation === this.remoteRefreshGeneration && this.isCurrentContent(content)) {
          content.remotePending = false;
          this.publishSuggestionContent(content);
        }
      });
  }

  private buildContentKey(query: string, source: BrowserSearchSuggestionRuntimeSource): string {
    // JSON encoding avoids delimiter collisions in user-controlled queries/URLs.
    return JSON.stringify([
      query,
      this.buildEmptyCacheKey(source),
      source.preferences.regularEnabled,
      source.preferences.remoteEnabled
    ]);
  }

  private isCurrentContent(content: BrowserSearchSuggestionSourceContent): boolean {
    return this.searchSessionActive && this.sourceContent === content &&
      this.buildContentKey(this.resolveRuntimeFacts().query, this.buildRuntimeSource()) === content.key;
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
      if (trimmedWord.length === 0 || seenKeys.has(key) || suggestions.length >= DEFAULT_SEARCH_SUGGESTION_POLICY.candidates.search) {
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

  private compactSuggestionKey(value: string): string {
    return value.trim().toLowerCase().replace(/\s+/g, '');
  }

  private cancelRemoteSearchSuggestions(): void {
    this.remoteRefreshGeneration += 1;
    if (this.remoteRefreshTimeout >= 0) {
      clearTimeout(this.remoteRefreshTimeout);
      this.remoteRefreshTimeout = -1;
    }
  }

  private cancelSearchHistoryHydration(): void {
    this.searchHistoryHydrationGeneration += 1;
  }

  private cancelBrowsingHistoryHydration(): void {
    this.browsingHistoryHydrationGeneration += 1;
  }

  private cancelBookmarkHydration(): void {
    this.bookmarkHydrationGeneration += 1;
  }

  private beginBrowsingHistoryHydration(): number {
    this.browsingHistoryHydrationGeneration += 1;
    return this.browsingHistoryHydrationGeneration;
  }

  private beginSearchHistoryHydration(): number {
    this.searchHistoryHydrationGeneration += 1;
    return this.searchHistoryHydrationGeneration;
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
    return JSON.stringify([
      source.boundary.profileId,
      source.boundary.privacyMode,
      source.boundary.dataScope,
      source.preferences.historyEnabled ? 'history-enabled' : 'history-disabled',
      source.preferences.browsingHistoryEnabled ? 'browsing-history-enabled' : 'browsing-history-disabled',
      source.preferences.bookmarksEnabled ? 'bookmarks-enabled' : 'bookmarks-disabled',
      source.preferences.openTabsEnabled ? 'tabs-enabled' : 'tabs-disabled',
      source.currentPageSuggestionEnabled ? 'current-page-enabled' : 'current-page-disabled',
      source.activeTab?.id ?? '',
      source.activeTab?.url ?? ''
    ]);
  }
}
