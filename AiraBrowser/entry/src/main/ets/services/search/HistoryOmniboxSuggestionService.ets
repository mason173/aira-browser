import { HistoryUrlRecord, HistoryVisit, SearchSuggestion } from '../../common/models/BrowserModels';
import { BrowserDatabase } from '../../data/database/BrowserDatabase';
import {
  HISTORY_OMNIBOX_HOT_SET_LIMIT,
  HISTORY_OMNIBOX_VISIBLE_LIMIT,
  HistoryOmniboxEntry,
  HistoryOmniboxIndex,
  HistoryOmniboxMatch
} from './HistoryOmniboxIndex';

const HISTORY_OMNIBOX_LOAD_ATTEMPTS: number = 3;
const HISTORY_OMNIBOX_LOAD_RETRY_MS: number = 2000;

/**
 * Loads the recent unique-URL hot set once, then answers address-bar queries from
 * memory. Keystrokes never call the history-page LIKE search.
 */
export class HistoryOmniboxSuggestionService {
  private readonly database: BrowserDatabase;
  private index: HistoryOmniboxIndex = new HistoryOmniboxIndex();
  private loadedRevision: number = -1;
  private loadPromise?: Promise<boolean>;
  private retryNotBefore: number = 0;
  private loadGeneration: number = 0;

  constructor(database: BrowserDatabase) {
    this.database = database;
  }

  buildSuggestions(query: string, limit: number = HISTORY_OMNIBOX_VISIBLE_LIMIT): SearchSuggestion[] {
    const normalizedLimit = Math.max(0, Math.floor(limit));
    if (query.trim().length === 0 || normalizedLimit === 0) {
      return [];
    }
    return this.index.match(query, normalizedLimit).map((match: HistoryOmniboxMatch): SearchSuggestion => {
      return this.toSuggestion(match.entry);
    });
  }

  /** Recently visited pages, newest first. Drives the empty search field's history list. */
  buildRecentSuggestions(limit: number = HISTORY_OMNIBOX_VISIBLE_LIMIT): SearchSuggestion[] {
    const normalizedLimit = Math.max(0, Math.floor(limit));
    if (normalizedLimit === 0) {
      return [];
    }
    return this.index.listRecent(normalizedLimit).map((entry: HistoryOmniboxEntry): SearchSuggestion => {
      return this.toSuggestion(entry);
    });
  }

  noteVisit(visit: HistoryVisit): void {
    const entry = this.entryFromVisit(visit);
    if (entry === undefined) {
      return;
    }
    this.index.upsert(entry);
  }

  ensureLoaded(): Promise<boolean> {
    if (this.loadPromise !== undefined) {
      return this.loadPromise;
    }
    const revision = this.database.getHistoryDataRevision();
    if (revision === this.loadedRevision) {
      return Promise.resolve(false);
    }
    if (Date.now() < this.retryNotBefore && this.loadedRevision >= 0) {
      return Promise.resolve(false);
    }
    this.loadGeneration += 1;
    const generation = this.loadGeneration;
    this.loadPromise = this.loadUntilStable(generation)
      .then((loaded: boolean) => {
        if (generation === this.loadGeneration) {
          this.loadPromise = undefined;
        }
        return loaded;
      })
      .catch((_error: Error) => {
        this.retryNotBefore = Date.now() + HISTORY_OMNIBOX_LOAD_RETRY_MS;
        if (generation === this.loadGeneration) {
          this.loadPromise = undefined;
        }
        return false;
      });
    return this.loadPromise;
  }

  private async loadUntilStable(generation: number): Promise<boolean> {
    for (let attempt = 0; attempt < HISTORY_OMNIBOX_LOAD_ATTEMPTS; attempt += 1) {
      if (generation !== this.loadGeneration) {
        return false;
      }
      const loaded = await this.loadOnce(generation);
      if (loaded) {
        return true;
      }
      if (this.database.getHistoryDataRevision() === this.loadedRevision) {
        return false;
      }
    }
    return false;
  }

  private async loadOnce(generation: number): Promise<boolean> {
    const startRevision = this.database.getHistoryDataRevision();
    if (this.database.isHistoryMutationPending()) {
      return false;
    }
    const rows = await this.database.listRecentHistoryUrls(HISTORY_OMNIBOX_HOT_SET_LIMIT);
    if (generation !== this.loadGeneration) {
      return false;
    }
    if (this.database.getHistoryDataRevision() !== startRevision || this.database.isHistoryMutationPending()) {
      return false;
    }
    const next = new HistoryOmniboxIndex();
    const entries: HistoryOmniboxEntry[] = [];
    for (let index = 0; index < rows.length; index += 1) {
      entries.push(this.entryFromUrl(rows[index]));
    }
    const adopted = await next.replaceYielding(
      entries,
      Date.now(),
      (): boolean => generation !== this.loadGeneration ||
        this.database.getHistoryDataRevision() !== startRevision
    );
    if (!adopted || generation !== this.loadGeneration) {
      return false;
    }
    if (this.database.getHistoryDataRevision() !== startRevision) {
      return false;
    }
    this.index = next;
    this.loadedRevision = startRevision;
    this.retryNotBefore = 0;
    return true;
  }

  private entryFromUrl(row: HistoryUrlRecord): HistoryOmniboxEntry {
    return {
      id: row.id,
      title: row.title,
      url: row.url,
      host: row.host,
      visitCount: row.visitCount,
      typedCount: row.typedCount,
      lastVisitAt: row.lastVisitAt
    };
  }

  private entryFromVisit(visit: HistoryVisit): HistoryOmniboxEntry | undefined {
    const url = visit.url.trim();
    if (url.length === 0) {
      return undefined;
    }
    return {
      id: (visit.urlId ?? '').trim().length > 0 ? (visit.urlId ?? '').trim() : url,
      title: visit.title,
      url: url,
      host: visit.host ?? '',
      visitCount: visit.visitCount ?? 1,
      typedCount: visit.typedCount ?? (visit.transition === 'typed' ? 1 : 0),
      lastVisitAt: visit.lastVisitAt ?? visit.visitedAt
    };
  }

  private toSuggestion(entry: HistoryOmniboxEntry): SearchSuggestion {
    const host = entry.host.trim();
    const title = entry.title.trim();
    const displayTitle = title.length > 0 ? title : (host.length > 0 ? host : entry.url);
    return {
      id: `history-url-${entry.id}`,
      title: displayTitle,
      source: 'history',
      target: entry.url,
      subtitle: host,
      icon: '',
      refId: entry.id
    };
  }
}
