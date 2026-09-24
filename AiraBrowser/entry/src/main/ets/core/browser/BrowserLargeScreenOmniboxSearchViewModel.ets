import {
  ExternalAppSearchPreferences,
  SearchSuggestion
} from '../../common/models/BrowserModels';
import {
  ExternalAppSearchService,
  ExternalAppSearchTarget
} from '../../services/search/ExternalAppSearchService';

const LARGE_SCREEN_EXTERNAL_APP_MIN_PAGE_SIZE: number = 4;
const LARGE_SCREEN_EXTERNAL_APP_MAX_PAGE_SIZE: number = 12;
const LARGE_SCREEN_EXTERNAL_APP_ITEM_WIDTH_VP: number = 48;
const LARGE_SCREEN_EXTERNAL_APP_MIN_GAP_VP: number = 8;
const LARGE_SCREEN_EXTERNAL_APP_CONTENT_PADDING_VP: number = 24;

export type OmniboxSuggestionNavigationDirection = 'up' | 'down';

/** Stable row identity shared by the dropdown and keyboard selection. */
export function omniboxSuggestionSelectionKey(suggestion: SearchSuggestion): string {
  return `${suggestion.id}:${suggestion.refId ?? ''}:${suggestion.target}`;
}

/** Rows the desktop dropdown actually paints. Keyboard movement must use this same list. */
export function resolveOmniboxKeyboardSuggestions(suggestions: SearchSuggestion[]): SearchSuggestion[] {
  return suggestions.filter((suggestion: SearchSuggestion): boolean => {
    return suggestion.source === 'search_history' || suggestion.source === 'suggestions';
  });
}

/**
 * Move the highlighted suggestion. An empty key means the typed query itself is active,
 * so Enter still searches what the user typed. Down from there selects the first row;
 * Up from the first row returns to the typed query. The ends do not wrap.
 */
export function moveOmniboxSuggestionSelection(
  suggestions: SearchSuggestion[],
  selectedKey: string,
  direction: OmniboxSuggestionNavigationDirection
): string {
  const visible = resolveOmniboxKeyboardSuggestions(suggestions);
  if (visible.length === 0) {
    return '';
  }
  const currentIndex = visible.findIndex((suggestion: SearchSuggestion): boolean => {
    return omniboxSuggestionSelectionKey(suggestion) === selectedKey;
  });
  if (direction === 'down') {
    const nextIndex = currentIndex < 0 ? 0 : Math.min(visible.length - 1, currentIndex + 1);
    return omniboxSuggestionSelectionKey(visible[nextIndex]);
  }
  if (currentIndex <= 0) {
    return '';
  }
  return omniboxSuggestionSelectionKey(visible[currentIndex - 1]);
}

/** Drop a highlight that no longer exists after suggestions refresh. */
export function retainOmniboxSuggestionSelection(
  suggestions: SearchSuggestion[],
  selectedKey: string
): string {
  if (selectedKey.length === 0) {
    return '';
  }
  const stillVisible = resolveOmniboxKeyboardSuggestions(suggestions).some((suggestion: SearchSuggestion): boolean => {
    return omniboxSuggestionSelectionKey(suggestion) === selectedKey;
  });
  return stillVisible ? selectedKey : '';
}

export interface BrowserLargeScreenOmniboxSearchPresentationInput {
  editing: boolean;
  inputFocused: boolean;
  surfaceWidthVp: number;
  suggestions: SearchSuggestion[];
  externalAppSearchPreferences: ExternalAppSearchPreferences;
}

export interface BrowserLargeScreenOmniboxSearchPresentation {
  visible: boolean;
  searchSuggestions: SearchSuggestion[];
  // The history header (title + clear-all action) is only meaningful when the
  // list actually carries search history; remote-only suggestions never show it.
  hasHistorySuggestions: boolean;
  externalAppSearchTargets: ExternalAppSearchTarget[];
  externalAppSearchPageSize: number;
}

/**
 * Desktop-only presentation projection for the shared Search Invocation.
 * Search history, remote suggestions, and external-app eligibility remain
 * owned by their existing services; ArkUI receives single-column list data.
 */
export class BrowserLargeScreenOmniboxSearchViewModel {
  private readonly externalAppSearchService: ExternalAppSearchService = new ExternalAppSearchService();

  resolve(
    input: BrowserLargeScreenOmniboxSearchPresentationInput
  ): BrowserLargeScreenOmniboxSearchPresentation {
    const externalAppSearchTargets = this.externalAppSearchService.listVisibleTargets({
      inputEditing: input.editing,
      inputFocused: input.inputFocused,
      preferences: input.externalAppSearchPreferences
    });
    const searchSuggestions = resolveOmniboxKeyboardSuggestions(input.suggestions);
    return {
      visible: input.editing && input.inputFocused,
      searchSuggestions: searchSuggestions,
      hasHistorySuggestions: searchSuggestions.some((suggestion: SearchSuggestion): boolean => {
        return suggestion.source === 'search_history';
      }),
      externalAppSearchTargets: externalAppSearchTargets,
      externalAppSearchPageSize: this.resolveExternalAppSearchPageSize(
        input.surfaceWidthVp,
        externalAppSearchTargets.length
      )
    };
  }

  private resolveExternalAppSearchPageSize(surfaceWidthVp: number, targetCount: number): number {
    if (targetCount <= 0) {
      return 0;
    }
    if (!Number.isFinite(surfaceWidthVp) || surfaceWidthVp <= 0) {
      return Math.min(LARGE_SCREEN_EXTERNAL_APP_MIN_PAGE_SIZE, targetCount);
    }
    const availableWidth = Math.max(0, surfaceWidthVp - LARGE_SCREEN_EXTERNAL_APP_CONTENT_PADDING_VP);
    const fittedCount = Math.floor(
      (availableWidth + LARGE_SCREEN_EXTERNAL_APP_MIN_GAP_VP) /
      (LARGE_SCREEN_EXTERNAL_APP_ITEM_WIDTH_VP + LARGE_SCREEN_EXTERNAL_APP_MIN_GAP_VP)
    );
    return Math.max(
      1,
      Math.min(targetCount, LARGE_SCREEN_EXTERNAL_APP_MAX_PAGE_SIZE, fittedCount)
    );
  }
}
