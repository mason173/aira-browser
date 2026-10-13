import { SearchSuggestion } from '../../common/models/BrowserModels';
import {
  normalizeLocalOmniboxQuery,
  scoreLocalOmniboxText
} from '../../services/search/LocalOmniboxSuggestionMatcher';
import { DEFAULT_SEARCH_SUGGESTION_POLICY } from './SearchSuggestionPolicy';

export interface SearchSuggestionCompositionInput {
  query: string;
  tabs: SearchSuggestion[];
  bookmarks: SearchSuggestion[];
  browsingHistory: SearchSuggestion[];
  searchHistory: SearchSuggestion[];
  remote: SearchSuggestion[];
  remotePending: boolean;
}

export interface SearchSuggestionComposition {
  suggestions: SearchSuggestion[];
  hasMoreBookmarks: boolean;
}

interface RankedNavigationSuggestion {
  suggestion: SearchSuggestion;
  score: number;
  order: number;
}

/** Composes bounded source snapshots; never queries or mutates repositories or source caches. */
export function composeSearchSuggestions(input: SearchSuggestionCompositionInput): SearchSuggestionComposition {
  const policy = DEFAULT_SEARCH_SUGGESTION_POLICY.presentation;
  if (input.query.trim().length === 0) {
    return { suggestions: uniqueSearchTerms(input.searchHistory).slice(0, policy.emptyLimit), hasMoreBookmarks: false };
  }
  const local = rankNavigationSuggestions(input);
  const terms = composeSearchTerms(input.searchHistory, input.remote);
  // Reserve slots while the request is pending, so its late response never evicts a visible URL.
  const reservedSearch = input.remotePending ? policy.preferredSearch : Math.min(policy.preferredSearch, terms.length);
  const localBudget = input.remotePending ? policy.preferredLocal : policy.activeLimit - reservedSearch;
  let selectedLocal = local.slice(0, localBudget);
  const selectedTerms = terms.slice(0, policy.activeLimit - selectedLocal.length);
  if (!input.remotePending && selectedLocal.length + selectedTerms.length < policy.activeLimit) {
    selectedLocal = local.slice(0, policy.activeLimit - selectedTerms.length);
  }
  const visibleUrls: Set<string> = new Set<string>();
  selectedLocal.forEach((suggestion: SearchSuggestion) => {
    visibleUrls.add(navigationKey(suggestion));
  });
  return {
    suggestions: selectedLocal.concat(selectedTerms),
    hasMoreBookmarks: input.bookmarks.some((suggestion: SearchSuggestion): boolean => {
      return !visibleUrls.has(navigationKey(suggestion));
    })
  };
}

function rankNavigationSuggestions(input: SearchSuggestionCompositionInput): SearchSuggestion[] {
  const query = normalizeLocalOmniboxQuery(input.query);
  const ranked: RankedNavigationSuggestion[] = [];
  const byUrl: Map<string, RankedNavigationSuggestion> = new Map<string, RankedNavigationSuggestion>();
  const candidates = input.tabs.concat(input.bookmarks, input.browsingHistory);
  candidates.forEach((suggestion: SearchSuggestion, order: number) => {
    const key = navigationKey(suggestion);
    if (key.length === 0) {
      return;
    }
    const quality = scoreLocalOmniboxText(query, suggestion.title, suggestion.subtitle ?? '', suggestion.target);
    // Matching quality is shared; providers supply only a separately bounded behavioral boost.
    const providerSignal = Math.max(0, suggestion.rankingBoost ?? 0);
    const signal = suggestion.source === 'tabs' ? Math.min(40, providerSignal) + 25
      : (suggestion.source === 'bookmarks' ? 20 : Math.min(88, providerSignal));
    const score = quality + signal;
    const existing = byUrl.get(key);
    if (existing !== undefined) {
      existing.score = Math.max(existing.score, score);
      // One URL keeps the useful existing action: switch tab, then bookmark, then history.
      if (navigationActionPriority(suggestion) > navigationActionPriority(existing.suggestion)) {
        existing.suggestion = suggestion;
      }
      return;
    }
    const item: RankedNavigationSuggestion = { suggestion: suggestion, score: score, order: order };
    byUrl.set(key, item);
    ranked.push(item);
  });
  ranked.sort((left: RankedNavigationSuggestion, right: RankedNavigationSuggestion): number => {
    if (right.score !== left.score) {
      return right.score - left.score;
    }
    return left.order - right.order;
  });
  return ranked.map((item: RankedNavigationSuggestion): SearchSuggestion => item.suggestion);
}

function navigationActionPriority(suggestion: SearchSuggestion): number {
  return suggestion.source === 'tabs' ? 3 : (suggestion.source === 'bookmarks' ? 2 : 1);
}

function navigationKey(suggestion: SearchSuggestion): string {
  return suggestion.target.trim().toLowerCase();
}

function uniqueSearchTerms(suggestions: SearchSuggestion[]): SearchSuggestion[] {
  const seen: Set<string> = new Set<string>();
  return suggestions.filter((suggestion: SearchSuggestion): boolean => {
    const key = suggestion.target.trim().toLowerCase().replace(/\s+/g, ' ');
    if (key.length === 0 || seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

function composeSearchTerms(history: SearchSuggestion[], remote: SearchSuggestion[]): SearchSuggestion[] {
  const recent = uniqueSearchTerms(history);
  const combined = uniqueSearchTerms(recent.concat(remote));
  const engine = combined.slice(recent.length);
  // Give both kinds a useful first result; either can borrow every remaining search slot.
  return recent.slice(0, 1).concat(engine.slice(0, 1), recent.slice(1), engine.slice(1));
}
