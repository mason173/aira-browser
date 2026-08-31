import {
  DEFAULT_BROWSER_PROFILE_ID,
  SearchSuggestionPreferences
} from '../../common/models/BrowserModels';
import { BrowserCreateTabOptions } from '../tabs/TabManager';
import { SearchQueryHistoryService } from '../../services/search/SearchQueryHistoryService';
import {
  BrowserAddressSubmissionHistoryRecorder,
  BrowserAddressSubmissionResult
} from './BrowserAddressSubmissionCoordinator';

export interface BrowserSearchSubmissionHistoryInput {
  submission: BrowserAddressSubmissionResult;
  boundary: BrowserCreateTabOptions;
  preferences: SearchSuggestionPreferences;
}

export class BrowserSearchSubmissionHistoryCoordinator implements BrowserAddressSubmissionHistoryRecorder {
  private searchQueryHistoryService: SearchQueryHistoryService;
  private onSearchRecorded: () => void;

  constructor(
    searchQueryHistoryService: SearchQueryHistoryService,
    onSearchRecorded: () => void = () => {}
  ) {
    this.searchQueryHistoryService = searchQueryHistoryService;
    this.onSearchRecorded = onSearchRecorded;
  }

  async recordSubmittedSearch(input: BrowserSearchSubmissionHistoryInput): Promise<boolean> {
    if (input.submission.intent !== 'search') {
      return false;
    }
    const record = await this.searchQueryHistoryService.recordSubmittedSearch({
      query: input.submission.searchQuery,
      searchEngineId: input.submission.searchEngineId,
      profileId: input.boundary.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      privacyMode: input.boundary.privacyMode ?? 'regular',
      dataScope: input.boundary.dataScope ?? 'profile_persistent',
      preferences: input.preferences
    });
    const recorded = record !== undefined;
    if (recorded) {
      this.onSearchRecorded();
    }
    return recorded;
  }
}
