import {
  BrowserDataScope,
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID,
  SearchQueryHistoryRecord
} from '../../common/models/BrowserModels';
import { BrowserDatabase } from '../database/BrowserDatabase';

export interface SearchQueryHistoryBoundary {
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
}

const DEFAULT_SEARCH_QUERY_HISTORY_BOUNDARY: SearchQueryHistoryBoundary = {
  profileId: DEFAULT_BROWSER_PROFILE_ID,
  dataScope: 'profile_persistent'
};

export class SearchQueryHistoryRepository {
  private readonly database: BrowserDatabase;
  private recordsByScope: Map<string, SearchQueryHistoryRecord[]> = new Map<string, SearchQueryHistoryRecord[]>();
  private initializationPromises: Map<string, Promise<void>> = new Map<string, Promise<void>>();

  constructor(database: BrowserDatabase) {
    this.database = database;
  }

  async initialize(boundary: SearchQueryHistoryBoundary = DEFAULT_SEARCH_QUERY_HISTORY_BOUNDARY): Promise<void> {
    const key = this.buildScopeKey(boundary);
    if (this.initializationPromises.has(key)) {
      return this.initializationPromises.get(key) as Promise<void>;
    }
    const promise = this.refresh(boundary)
      .then(() => undefined)
      .catch((error: Error) => {
        this.initializationPromises.delete(key);
        throw error;
      });
    this.initializationPromises.set(key, promise);
    return promise;
  }

  isInitialized(boundary: SearchQueryHistoryBoundary = DEFAULT_SEARCH_QUERY_HISTORY_BOUNDARY): boolean {
    return this.recordsByScope.has(this.buildScopeKey(boundary));
  }

  async refresh(boundary: SearchQueryHistoryBoundary = DEFAULT_SEARCH_QUERY_HISTORY_BOUNDARY): Promise<SearchQueryHistoryRecord[]> {
    const records = await this.database.listSearchQueryHistory(boundary.profileId, boundary.dataScope);
    this.recordsByScope.set(this.buildScopeKey(boundary), this.sortRecords(records));
    return this.listRecords(boundary);
  }

  listRecords(boundary: SearchQueryHistoryBoundary = DEFAULT_SEARCH_QUERY_HISTORY_BOUNDARY): SearchQueryHistoryRecord[] {
    return (this.recordsByScope.get(this.buildScopeKey(boundary)) ?? []).slice();
  }

  listRecent(boundary: SearchQueryHistoryBoundary, limit: number): SearchQueryHistoryRecord[] {
    return this.listRecords(boundary)
      .sort((left: SearchQueryHistoryRecord, right: SearchQueryHistoryRecord) => right.lastSearchedAt - left.lastSearchedAt)
      .slice(0, Math.max(0, Math.floor(limit)));
  }

  async upsert(record: SearchQueryHistoryRecord): Promise<SearchQueryHistoryRecord> {
    const boundary: SearchQueryHistoryBoundary = {
      profileId: record.profileId,
      dataScope: record.dataScope
    };
    await this.initialize(boundary);
    await this.database.upsertSearchQueryHistory(record);
    const current = this.listRecords(boundary).filter((item: SearchQueryHistoryRecord) => item.id !== record.id);
    current.push(record);
    this.recordsByScope.set(this.buildScopeKey(boundary), this.sortRecords(current));
    return record;
  }

  async deleteByIds(ids: string[]): Promise<number> {
    const removed = await this.database.deleteSearchQueryHistoryByIds(ids);
    if (removed > 0) {
      this.removeCachedIds(ids);
    }
    return removed;
  }

  async deleteInRange(startAt: number, endAt: number): Promise<number> {
    const removed = await this.database.deleteSearchQueryHistoryInRange(startAt, endAt);
    if (removed > 0) {
      await this.refreshLoadedScopes();
    }
    return removed;
  }

  async clearAll(): Promise<number> {
    const removed = await this.database.clearSearchQueryHistory();
    this.recordsByScope.clear();
    this.initializationPromises.clear();
    return removed;
  }

  async applyRetention(boundary: SearchQueryHistoryBoundary, maxRecords: number, maxAgeDays: number): Promise<number> {
    await this.initialize(boundary);
    const now = Date.now();
    const maxAgeMs = Math.max(1, Math.floor(maxAgeDays)) * 24 * 60 * 60 * 1000;
    const cutoff = now - maxAgeMs;
    const ordered = this.listRecords(boundary)
      .sort((left: SearchQueryHistoryRecord, right: SearchQueryHistoryRecord) => right.lastSearchedAt - left.lastSearchedAt);
    const deletingIds: string[] = [];
    ordered.forEach((record: SearchQueryHistoryRecord, index: number) => {
      if (record.lastSearchedAt < cutoff || index >= maxRecords) {
        deletingIds.push(record.id);
      }
    });
    return this.deleteByIds(deletingIds);
  }

  private buildScopeKey(boundary: SearchQueryHistoryBoundary): string {
    return `${boundary.profileId}:${boundary.dataScope}`;
  }

  private sortRecords(records: SearchQueryHistoryRecord[]): SearchQueryHistoryRecord[] {
    return records
      .slice()
      .sort((left: SearchQueryHistoryRecord, right: SearchQueryHistoryRecord) => right.lastSearchedAt - left.lastSearchedAt);
  }

  private removeCachedIds(ids: string[]): void {
    const idSet = new Set<string>(ids);
    this.recordsByScope.forEach((records: SearchQueryHistoryRecord[], key: string) => {
      this.recordsByScope.set(key, records.filter((record: SearchQueryHistoryRecord) => !idSet.has(record.id)));
    });
  }

  private async refreshLoadedScopes(): Promise<void> {
    const keys = Array.from(this.recordsByScope.keys());
    for (const key of keys) {
      const boundary = this.parseScopeKey(key);
      if (boundary !== undefined) {
        await this.refresh(boundary);
      }
    }
  }

  private parseScopeKey(key: string): SearchQueryHistoryBoundary | undefined {
    const parts = key.split(':');
    if (parts.length !== 2) {
      return undefined;
    }
    return {
      profileId: parts[0] as BrowserProfileId,
      dataScope: parts[1] as BrowserDataScope
    };
  }
}
