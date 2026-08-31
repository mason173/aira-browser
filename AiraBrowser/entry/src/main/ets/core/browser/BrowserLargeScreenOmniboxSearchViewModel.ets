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
    return {
      visible: input.editing && input.inputFocused,
      searchSuggestions: input.suggestions.filter((suggestion: SearchSuggestion): boolean => {
        return suggestion.source === 'search_history' || suggestion.source === 'suggestions';
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
