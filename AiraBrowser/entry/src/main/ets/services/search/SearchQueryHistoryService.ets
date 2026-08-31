import {
  BrowserDataScope,
  BrowserDataBoundaryInput,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  SearchEngineId,
  SearchQueryHistoryRecord,
  SearchSuggestion,
  SearchSuggestionPreferences
} from '../../common/models/BrowserModels';
import { looksLikeUrl } from '../../common/utils/UrlUtils';
import {
  SearchQueryHistoryBoundary,
  SearchQueryHistoryRepository
} from '../../data/search/SearchQueryHistoryRepository';
import { BrowserPrivacyEffectPolicyService } from '../privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';

export interface SearchQueryHistoryRecordInput {
  query: string;
  searchEngineId: SearchEngineId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  profileId?: BrowserProfileId;
  preferences: SearchSuggestionPreferences;
}

export interface SearchQueryHistorySuggestionInput {
  query: string;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  profileId?: BrowserProfileId;
  preferences: SearchSuggestionPreferences;
  limit?: number;
}

export interface SearchQueryHistoryClearResult {
  removedCount: number;
}

export interface SearchQueryHistoryHydrationResult {
  hydrated: boolean;
}

interface NormalizedSearchQuery {
  query: string;
  normalizedQuery: string;
  compactQuery: string;
}

interface RankedSearchQueryHistoryRecord {
  record: SearchQueryHistoryRecord;
  score: number;
}

export const SEARCH_QUERY_HISTORY_MAX_RECORDS: number = 200;
export const SEARCH_QUERY_HISTORY_VISIBLE_LIMIT: number = 5;
const SEARCH_QUERY_HISTORY_MAX_AGE_DAYS: number = 90;
const SEARCH_QUERY_HISTORY_MAX_QUERY_LENGTH: number = 120;

export class SearchQueryHistoryService {
  private readonly repository: SearchQueryHistoryRepository;
  private readonly privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private readonly profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    repository: SearchQueryHistoryRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.repository = repository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  buildSuggestions(input: SearchQueryHistorySuggestionInput): SearchSuggestion[] {
    if (!this.shouldUseSearchQueryHistory(input.privacyMode, input.dataScope, input.preferences)) {
      return [];
    }
    const boundary = this.buildBoundary(input.profileId, input.dataScope);
    if (!this.repository.isInitialized(boundary)) {
      return [];
    }
    const limit = Math.max(0, Math.floor(input.limit ?? SEARCH_QUERY_HISTORY_VISIBLE_LIMIT));
    const normalized = this.normalizeQuery(input.query);
    if (normalized === undefined) {
      return this.repository.listRecent(boundary, limit).map((record: SearchQueryHistoryRecord) => {
        return this.toSuggestion(record);
      });
    }
    return this.matchRecords(this.repository.listRecords(boundary), normalized)
      .slice(0, limit)
      .map((record: SearchQueryHistoryRecord) => this.toSuggestion(record));
  }

  async recordSubmittedSearch(input: SearchQueryHistoryRecordInput): Promise<SearchQueryHistoryRecord | undefined> {
    if (!this.shouldUseSearchQueryHistory(input.privacyMode, input.dataScope, input.preferences)) {
      return undefined;
    }
    const normalized = this.normalizeQuery(input.query);
    if (normalized === undefined || looksLikeUrl(normalized.query) ||
      normalized.query.length > SEARCH_QUERY_HISTORY_MAX_QUERY_LENGTH) {
      return undefined;
    }
    const boundary = this.buildBoundary(input.profileId, input.dataScope);
    await this.repository.initialize(boundary);
    const existing = this.repository.listRecords(boundary).find((record: SearchQueryHistoryRecord) => {
      return record.normalizedQuery === normalized.normalizedQuery;
    });
    const now = Date.now();
    const record: SearchQueryHistoryRecord = {
      id: existing?.id ?? this.buildRecordId(boundary, normalized.normalizedQuery),
      query: normalized.query,
      normalizedQuery: normalized.normalizedQuery,
      compactQuery: normalized.compactQuery,
      searchEngineId: input.searchEngineId,
      useCount: (existing?.useCount ?? 0) + 1,
      firstSearchedAt: existing?.firstSearchedAt ?? now,
      lastSearchedAt: now,
      profileId: boundary.profileId,
      dataScope: boundary.dataScope
    };
    const saved = await this.repository.upsert(record);
    await this.repository.applyRetention(boundary, SEARCH_QUERY_HISTORY_MAX_RECORDS, SEARCH_QUERY_HISTORY_MAX_AGE_DAYS);
    return saved;
  }

  async hydrateSuggestions(input: SearchQueryHistorySuggestionInput): Promise<SearchQueryHistoryHydrationResult> {
    if (!this.shouldUseSearchQueryHistory(input.privacyMode, input.dataScope, input.preferences)) {
      return { hydrated: false };
    }
    const boundary = this.buildBoundary(input.profileId, input.dataScope);
    if (this.repository.isInitialized(boundary)) {
      return { hydrated: false };
    }
    await this.repository.initialize(boundary);
    return { hydrated: true };
  }

  async clearRegularProfileSearchHistory(
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<SearchQueryHistoryClearResult> {
    const decision = this.privacyEffectPolicy.decide({
      intent: 'regular_profile_management_mutation',
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: 'regular_profile_data',
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      throw new Error('Regular search history management privacy effect was not allowed.');
    }
    const removedCount = await this.repository.clearAll();
    return { removedCount: removedCount };
  }

  async deleteSearchHistoryById(recordId: string): Promise<SearchQueryHistoryClearResult> {
    const normalizedRecordId = recordId.trim();
    if (normalizedRecordId.length === 0) {
      return { removedCount: 0 };
    }
    const removedCount = await this.repository.deleteByIds([normalizedRecordId]);
    return { removedCount: removedCount };
  }

  async clearSearchHistoryInRange(startAt: number, endAt: number): Promise<SearchQueryHistoryClearResult> {
    const removedCount = await this.repository.deleteInRange(startAt, endAt);
    return { removedCount: removedCount };
  }

  private shouldUseSearchQueryHistory(
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope,
    preferences: SearchSuggestionPreferences
  ): boolean {
    return preferences.historyEnabled && privacyMode !== 'private' && dataScope !== 'session_ephemeral';
  }

  private buildBoundary(profileId: BrowserProfileId | undefined, dataScope: BrowserDataScope): SearchQueryHistoryBoundary {
    return {
      profileId: profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      dataScope: dataScope
    };
  }

  private normalizeQuery(value: string): NormalizedSearchQuery | undefined {
    const query = value.trim().replace(/\s+/g, ' ');
    if (query.length === 0) {
      return undefined;
    }
    const normalizedQuery = query.toLowerCase();
    return {
      query: query,
      normalizedQuery: normalizedQuery,
      compactQuery: normalizedQuery.replace(/\s+/g, '')
    };
  }

  private matchRecords(
    records: SearchQueryHistoryRecord[],
    normalized: NormalizedSearchQuery
  ): SearchQueryHistoryRecord[] {
    return records
      .map((record: SearchQueryHistoryRecord): RankedSearchQueryHistoryRecord => {
        return {
          record: record,
          score: this.scoreRecord(record, normalized)
        };
      })
      .filter((item: RankedSearchQueryHistoryRecord) => item.score > 0)
      .sort((left: RankedSearchQueryHistoryRecord, right: RankedSearchQueryHistoryRecord) => {
        if (right.score !== left.score) {
          return right.score - left.score;
        }
        if (right.record.lastSearchedAt !== left.record.lastSearchedAt) {
          return right.record.lastSearchedAt - left.record.lastSearchedAt;
        }
        return right.record.useCount - left.record.useCount;
      })
      .map((item: RankedSearchQueryHistoryRecord) => item.record);
  }

  private scoreRecord(record: SearchQueryHistoryRecord, normalized: NormalizedSearchQuery): number {
    if (record.normalizedQuery === normalized.normalizedQuery) {
      return 500;
    }
    if (record.normalizedQuery.startsWith(normalized.normalizedQuery)) {
      return 400;
    }
    if (normalized.compactQuery.length > 0 && record.compactQuery.startsWith(normalized.compactQuery)) {
      return 300;
    }
    if (record.normalizedQuery.indexOf(normalized.normalizedQuery) >= 0) {
      return 200;
    }
    if (normalized.compactQuery.length > 0 && record.compactQuery.indexOf(normalized.compactQuery) >= 0) {
      return 100;
    }
    return 0;
  }

  private toSuggestion(record: SearchQueryHistoryRecord): SearchSuggestion {
    return {
      id: `search-history-${record.id}`,
      title: record.query,
      source: 'search_history',
      target: record.query,
      subtitle: '',
      icon: '',
      refId: record.id
    };
  }

  private buildRecordId(boundary: SearchQueryHistoryBoundary, normalizedQuery: string): string {
    return `search-query-${this.hashText(`${boundary.profileId}:${boundary.dataScope}:${normalizedQuery}`)}`;
  }

  private hashText(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash = (hash ^ value.charCodeAt(index)) * 16777619;
      hash = hash >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
  }
}
