export interface SearchSuggestionCandidateCaps {
  local: number;
  search: number;
}

export interface SearchSuggestionPresentationCaps {
  emptyLimit: number;
  activeLimit: number;
  preferredLocal: number;
  preferredSearch: number;
}

export interface SearchSuggestionTimingPolicy {
  revealRefreshDelayMs: number;
  deferredRefreshDelayMs: number;
  remoteRefreshDelayMs: number;
  prewarmDelayMs: number;
}

export interface SearchSuggestionPolicy {
  candidates: SearchSuggestionCandidateCaps;
  presentation: SearchSuggestionPresentationCaps;
  timing: SearchSuggestionTimingPolicy;
}

export const DEFAULT_SEARCH_SUGGESTION_POLICY: SearchSuggestionPolicy = {
  // Retrieve beyond the visible limit so duplicates and the active page do not leave holes.
  candidates: {
    local: 16,
    search: 16
  },
  presentation: {
    emptyLimit: 8,
    activeLimit: 8,
    preferredLocal: 6,
    preferredSearch: 2
  },
  timing: {
    revealRefreshDelayMs: 96,
    deferredRefreshDelayMs: 0,
    remoteRefreshDelayMs: 96,
    prewarmDelayMs: 48
  }
};
