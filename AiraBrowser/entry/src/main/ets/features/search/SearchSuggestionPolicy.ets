export interface SearchSuggestionCandidateCaps {
  emptyBookmarks: number;
  activeBookmarks: number;
  activeHistory: number;
}

export interface SearchSuggestionPresentationCaps {
  emptyLimit: number;
  activeLimit: number;
  emptyTabs: number;
  emptyBookmarks: number;
  activeTabs: number;
  navigateTabs: number;
  activeLocal: number;
  remoteSearch: number;
  navigateRemoteSearch: number;
}

export interface SearchSuggestionTimingPolicy {
  revealRefreshDelayMs: number;
  deferredRefreshDelayMs: number;
  prewarmDelayMs: number;
}

export interface SearchSuggestionPolicy {
  candidates: SearchSuggestionCandidateCaps;
  presentation: SearchSuggestionPresentationCaps;
  timing: SearchSuggestionTimingPolicy;
}

export const DEFAULT_SEARCH_SUGGESTION_POLICY: SearchSuggestionPolicy = {
  candidates: {
    emptyBookmarks: 20,
    activeBookmarks: 60,
    activeHistory: 60
  },
  presentation: {
    emptyLimit: 5,
    activeLimit: 5,
    emptyTabs: 2,
    emptyBookmarks: 3,
    activeTabs: 1,
    navigateTabs: 2,
    activeLocal: 2,
    remoteSearch: 2,
    navigateRemoteSearch: 1
  },
  timing: {
    revealRefreshDelayMs: 96,
    deferredRefreshDelayMs: 96,
    prewarmDelayMs: 48
  }
};
