import { BookmarkSearchRecord } from '../../common/models/BookmarkSearchIndexModels';
import { BookmarkNode, SearchSuggestion } from '../../common/models/BrowserModels';
import {
  PreparedBookmarkSuggestion,
  matchPreparedBookmarkSuggestions,
  normalizeLocalOmniboxQuery,
  prepareBookmarkSearchRecord,
  prepareBookmarkSuggestion
} from './LocalOmniboxSuggestionMatcher';

const BOOKMARK_OMNIBOX_BUILD_BATCH_SIZE: number = 200;
const INDEX_CHUNK_LENGTH: number = 32000;

interface BookmarkIndexSnapshotRecord {
  entry?: PreparedBookmarkSuggestion;
  token?: string;
  slots?: number[];
}

/** Full-field postings preserve substring and single-character Chinese matches without a recall cap. */
export class BookmarkOmniboxIndex {
  private entries: PreparedBookmarkSuggestion[] = [];
  private postings: Map<string, number[]> = new Map<string, number[]>();
  private candidateCount: number = 0;

  async replaceYielding(bookmarks: BookmarkNode[], isCancelled: () => boolean): Promise<boolean> {
    const next = new BookmarkOmniboxIndex();
    for (let start = 0; start < bookmarks.length; start += BOOKMARK_OMNIBOX_BUILD_BATCH_SIZE) {
      // Yield before the first batch too: a cold query publishes its fallback before index work.
      await pauseBookmarkOmniboxIndexWork();
      if (isCancelled()) {
        return false;
      }
      const end = Math.min(bookmarks.length, start + BOOKMARK_OMNIBOX_BUILD_BATCH_SIZE);
      for (let index = start; index < end; index += 1) {
        next.append(bookmarks[index]);
      }
    }
    if (isCancelled()) {
      return false;
    }
    this.entries = next.entries;
    this.postings = next.postings;
    return true;
  }

  async replaceRecordsYielding(records: BookmarkSearchRecord[], isCancelled: () => boolean): Promise<boolean> {
    const next = new BookmarkOmniboxIndex();
    for (let start = 0; start < records.length; start += BOOKMARK_OMNIBOX_BUILD_BATCH_SIZE) {
      await pauseBookmarkOmniboxIndexWork();
      if (isCancelled()) {
        return false;
      }
      const end = Math.min(records.length, start + BOOKMARK_OMNIBOX_BUILD_BATCH_SIZE);
      for (let index = start; index < end; index += 1) {
        next.appendPrepared(prepareBookmarkSearchRecord(records[index]));
      }
    }
    if (isCancelled()) {
      return false;
    }
    this.entries = next.entries;
    this.postings = next.postings;
    return true;
  }

  /** Save normalized entries AND postings so restart does not tokenize the collection again. */
  async exportChunksYielding(): Promise<string[]> {
    const chunks: string[] = [];
    let records: string[] = [];
    let length = 2;
    const append = (record: BookmarkIndexSnapshotRecord): boolean => {
      const encoded = JSON.stringify(record);
      if (encoded.length + 2 > INDEX_CHUNK_LENGTH) {
        return false;
      }
      if (length + encoded.length + 1 > INDEX_CHUNK_LENGTH) {
        chunks.push(`[${records.join(',')}]`);
        records = [];
        length = 2;
      }
      records.push(encoded);
      length += encoded.length + 1;
      return true;
    };
    for (let index = 0; index < this.entries.length; index += 1) {
      if (index % BOOKMARK_OMNIBOX_BUILD_BATCH_SIZE === 0) {
        await pauseBookmarkOmniboxIndexWork();
      }
      if (!append({ entry: this.entries[index] })) {
        return [];
      }
    }
    const tokens = Array.from(this.postings.keys());
    for (let index = 0; index < tokens.length; index += 1) {
      if (index % 20 === 0) {
        await pauseBookmarkOmniboxIndexWork();
      }
      const slots = this.postings.get(tokens[index]) ?? [];
      for (let start = 0; start < slots.length; start += 1000) {
        if (!append({ token: tokens[index], slots: slots.slice(start, start + 1000) })) {
          return [];
        }
      }
    }
    chunks.push(`[${records.join(',')}]`);
    return chunks;
  }

  async restoreChunksYielding(chunks: string[], isCancelled: () => boolean): Promise<boolean> {
    if (chunks.length === 0) {
      return false;
    }
    const next = new BookmarkOmniboxIndex();
    let readingPostings = false;
    try {
      for (let part = 0; part < chunks.length; part += 1) {
        await pauseBookmarkOmniboxIndexWork();
        if (isCancelled() || chunks[part].length > INDEX_CHUNK_LENGTH) {
          return false;
        }
        const records = JSON.parse(chunks[part]) as BookmarkIndexSnapshotRecord[];
        if (!Array.isArray(records)) {
          return false;
        }
        for (let index = 0; index < records.length; index += 1) {
          const record = records[index];
          if (record.entry !== undefined) {
            if (readingPostings || !isValidBookmarkIndexEntry(record.entry)) {
              return false;
            }
            next.entries.push(record.entry);
          } else {
            readingPostings = true;
            if (typeof record.token !== 'string' || !Array.isArray(record.slots) ||
              !((record.token.startsWith('c:') && record.token.length === 3) ||
                (record.token.startsWith('b:') && record.token.length === 4))) {
              return false;
            }
            const slots = next.postings.get(record.token) ?? [];
            let previous = slots.length === 0 ? -1 : slots[slots.length - 1];
            for (let offset = 0; offset < record.slots.length; offset += 1) {
              const slot = record.slots[offset];
              if (!Number.isInteger(slot) || slot <= previous || slot >= next.entries.length) {
                return false;
              }
              slots.push(slot);
              previous = slot;
            }
            next.postings.set(record.token, slots);
          }
        }
      }
    } catch (_error) {
      return false;
    }
    if (isCancelled() || (next.entries.length > 0 && next.postings.size === 0)) {
      return false;
    }
    this.entries = next.entries;
    this.postings = next.postings;
    return true;
  }

  match(query: string, limit: number): SearchSuggestion[] {
    const normalizedQuery = normalizeLocalOmniboxQuery(query);
    this.candidateCount = 0;
    if (normalizedQuery.length === 0 || limit <= 0) {
      return [];
    }
    const posting = this.findShortestPosting(normalizedQuery);
    const candidates: PreparedBookmarkSuggestion[] = [];
    for (let index = 0; index < posting.length; index += 1) {
      candidates.push(this.entries[posting[index]]);
    }
    this.candidateCount = candidates.length;
    return matchPreparedBookmarkSuggestions(candidates, query, limit);
  }

  lastQueryCandidateCount(): number {
    return this.candidateCount;
  }

  private append(bookmark: BookmarkNode): void {
    const entry = prepareBookmarkSuggestion(bookmark);
    if (entry === undefined) {
      return;
    }
    this.appendPrepared(entry);
  }

  private appendPrepared(entry: PreparedBookmarkSuggestion): void {
    const slot = this.entries.length;
    this.entries.push(entry);
    const tokens: Set<string> = new Set<string>();
    const fields: string[] = [entry.normalizedTitle, entry.normalizedHost, entry.compactUrl];
    for (let fieldIndex = 0; fieldIndex < fields.length; fieldIndex += 1) {
      const field = fields[fieldIndex];
      for (let index = 0; index < field.length; index += 1) {
        tokens.add(`c:${field.charAt(index)}`);
        if (index + 1 < field.length) {
          tokens.add(`b:${field.substring(index, index + 2)}`);
        }
      }
    }
    tokens.forEach((token: string) => {
      const posting = this.postings.get(token);
      if (posting === undefined) {
        this.postings.set(token, [slot]);
      } else {
        posting.push(slot);
      }
    });
  }

  private findShortestPosting(query: string): number[] {
    if (query.length === 1) {
      return this.postings.get(`c:${query}`) ?? [];
    }
    let shortest: number[] | undefined;
    for (let index = 0; index + 1 < query.length; index += 1) {
      const posting = this.postings.get(`b:${query.substring(index, index + 2)}`);
      if (posting === undefined) {
        return [];
      }
      if (shortest === undefined || posting.length < shortest.length) {
        shortest = posting;
      }
    }
    return shortest ?? [];
  }
}

function pauseBookmarkOmniboxIndexWork(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve();
    }, 0);
  });
}

function isValidBookmarkIndexEntry(entry: PreparedBookmarkSuggestion): boolean {
  return entry !== null && typeof entry.normalizedTitle === 'string' && typeof entry.normalizedHost === 'string' &&
    typeof entry.compactUrl === 'string' && entry.suggestion !== undefined && entry.suggestion !== null &&
    typeof entry.suggestion.id === 'string' && typeof entry.suggestion.title === 'string' &&
    typeof entry.suggestion.target === 'string' && entry.suggestion.target.trim().length > 0 &&
    entry.suggestion.source === 'bookmarks' && typeof entry.suggestion.refId === 'string';
}
