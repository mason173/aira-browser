export const HISTORY_OMNIBOX_HOT_SET_LIMIT: number = 8000;
export const HISTORY_OMNIBOX_CANDIDATE_CAP: number = 160;
export const HISTORY_OMNIBOX_VISIBLE_LIMIT: number = 3;
const HISTORY_OMNIBOX_TOKEN_SPAN: number = 64;
const HISTORY_OMNIBOX_POSTING_SCAN_CAP: number = 480;

export interface HistoryOmniboxEntry {
  id: string;
  title: string;
  url: string;
  host: string;
  visitCount: number;
  typedCount: number;
  lastVisitAt: number;
}

export interface HistoryOmniboxMatch {
  entry: HistoryOmniboxEntry;
  score: number;
}

export interface HistoryOmniboxQueryStats {
  examined: number;
  candidates: number;
  hotSetSize: number;
}

interface HistoryOmniboxSlot {
  entry: HistoryOmniboxEntry;
  key: string;
  normalizedTitle: string;
  normalizedHost: string;
  compactUrl: string;
  rank: number;
  live: boolean;
}

interface RankedHistoryOmniboxMatch {
  slotIndex: number;
  score: number;
}

/**
 * In-memory index of recent unique history URLs.
 *
 * Address-bar matching must not scan history_visits. A 10k–50k visit table with
 * a leading-wildcard LIKE is a full scan on the UI thread. This index keeps only
 * the recent hot set and resolves a keystroke from prefix and bigram postings,
 * so the examined set stays capped even when the database is much larger.
 * Native code is unnecessary: the cost was the query shape, not ArkTS.
 */
export class HistoryOmniboxIndex {
  private slots: HistoryOmniboxSlot[] = [];
  private slotByKey: Map<string, number> = new Map<string, number>();
  private postings: Map<string, number[]> = new Map<string, number[]>();
  private liveCount: number = 0;
  private examined: number = 0;
  private candidateCount: number = 0;

  size(): number {
    return this.liveCount;
  }

  lastQueryStats(): HistoryOmniboxQueryStats {
    return {
      examined: this.examined,
      candidates: this.candidateCount,
      hotSetSize: this.liveCount
    };
  }

  clear(): void {
    this.slots = [];
    this.slotByKey = new Map<string, number>();
    this.postings = new Map<string, number[]>();
    this.liveCount = 0;
  }

  replace(entries: HistoryOmniboxEntry[], now: number = Date.now()): void {
    const ranked = this.rankEntries(entries, now);
    this.clear();
    this.appendRanked(ranked, false);
  }

  async replaceYielding(
    entries: HistoryOmniboxEntry[],
    now: number,
    isCancelled: () => boolean
  ): Promise<boolean> {
    const ranked = this.rankEntries(entries, now);
    const built = new HistoryOmniboxIndex();
    const batchSize = 250;
    for (let start = 0; start < ranked.length; start += batchSize) {
      if (isCancelled()) {
        return false;
      }
      built.appendRanked(ranked.slice(start, start + batchSize), false);
      await pauseHistoryOmniboxIndexWork();
    }
    if (isCancelled()) {
      return false;
    }
    this.adopt(built);
    return true;
  }

  upsert(entry: HistoryOmniboxEntry, now: number = Date.now()): void {
    const slot = this.toSlot(entry, now);
    if (slot === undefined) {
      return;
    }
    const existingIndex = this.slotByKey.get(slot.key);
    if (existingIndex !== undefined) {
      const existing = this.slots[existingIndex];
      const wasLive = existing.live;
      this.slots[existingIndex] = slot;
      if (!wasLive) {
        this.liveCount += 1;
      }
      this.pushTokens(existingIndex, slot, true);
      return;
    }
    if (this.liveCount >= HISTORY_OMNIBOX_HOT_SET_LIMIT && slot.rank <= this.lowestLiveRank()) {
      return;
    }
    if (this.liveCount >= HISTORY_OMNIBOX_HOT_SET_LIMIT) {
      this.evictLowest();
    }
    const slotIndex = this.slots.length;
    this.slots.push(slot);
    this.slotByKey.set(slot.key, slotIndex);
    this.liveCount += 1;
    this.pushTokens(slotIndex, slot, true);
  }

  /**
   * Most recently visited live entries, newest first. This is the resting list an empty search
   * field shows; `match` is the typed-query path and needs a query.
   */
  listRecent(limit: number): HistoryOmniboxEntry[] {
    const normalizedLimit = Math.max(0, Math.floor(limit));
    if (normalizedLimit === 0 || this.liveCount === 0) {
      return [];
    }
    const entries: HistoryOmniboxEntry[] = [];
    for (let index = 0; index < this.slots.length; index += 1) {
      if (this.slots[index].live) {
        entries.push(this.slots[index].entry);
      }
    }
    entries.sort((left: HistoryOmniboxEntry, right: HistoryOmniboxEntry): number => {
      return right.lastVisitAt - left.lastVisitAt;
    });
    return entries.slice(0, normalizedLimit);
  }

  match(query: string, limit: number, now: number = Date.now()): HistoryOmniboxMatch[] {
    const normalizedLimit = Math.max(0, Math.floor(limit));
    this.examined = 0;
    this.candidateCount = 0;
    if (normalizedLimit === 0 || this.liveCount === 0) {
      return [];
    }
    const normalizedQuery = normalizeHistoryOmniboxQuery(query);
    if (normalizedQuery.length === 0) {
      return [];
    }
    const candidateIndexes = this.collectCandidates(normalizedQuery);
    this.candidateCount = candidateIndexes.length;
    const ranked: RankedHistoryOmniboxMatch[] = [];
    for (let index = 0; index < candidateIndexes.length; index += 1) {
      const slotIndex = candidateIndexes[index];
      const slot = this.slots[slotIndex];
      if (slot === undefined || !slot.live) {
        continue;
      }
      this.examined += 1;
      const score = this.scoreSlot(slot, normalizedQuery, now);
      if (score <= 0) {
        continue;
      }
      ranked.push({ slotIndex: slotIndex, score: score });
    }
    ranked.sort((left: RankedHistoryOmniboxMatch, right: RankedHistoryOmniboxMatch): number => {
      if (right.score !== left.score) {
        return right.score - left.score;
      }
      return this.slots[right.slotIndex].rank - this.slots[left.slotIndex].rank;
    });
    const matches: HistoryOmniboxMatch[] = [];
    for (let index = 0; index < ranked.length && matches.length < normalizedLimit; index += 1) {
      matches.push({
        entry: this.slots[ranked[index].slotIndex].entry,
        score: ranked[index].score
      });
    }
    return matches;
  }

  private adopt(source: HistoryOmniboxIndex): void {
    this.slots = source.slots;
    this.slotByKey = source.slotByKey;
    this.postings = source.postings;
    this.liveCount = source.liveCount;
  }

  private rankEntries(entries: HistoryOmniboxEntry[], now: number): HistoryOmniboxSlot[] {
    const ranked: HistoryOmniboxSlot[] = [];
    const seen: Set<string> = new Set<string>();
    for (let index = 0; index < entries.length; index += 1) {
      const slot = this.toSlot(entries[index], now);
      if (slot === undefined || seen.has(slot.key)) {
        continue;
      }
      seen.add(slot.key);
      ranked.push(slot);
    }
    ranked.sort((left: HistoryOmniboxSlot, right: HistoryOmniboxSlot): number => right.rank - left.rank);
    if (ranked.length > HISTORY_OMNIBOX_HOT_SET_LIMIT) {
      return ranked.slice(0, HISTORY_OMNIBOX_HOT_SET_LIMIT);
    }
    return ranked;
  }

  private appendRanked(ranked: HistoryOmniboxSlot[], front: boolean): void {
    for (let index = 0; index < ranked.length; index += 1) {
      const slot = ranked[index];
      const existingIndex = this.slotByKey.get(slot.key);
      if (existingIndex !== undefined) {
        this.slots[existingIndex] = slot;
        this.pushTokens(existingIndex, slot, front);
        continue;
      }
      const slotIndex = this.slots.length;
      this.slots.push(slot);
      this.slotByKey.set(slot.key, slotIndex);
      this.liveCount += 1;
      this.pushTokens(slotIndex, slot, front);
    }
  }

  private collectCandidates(normalizedQuery: string): number[] {
    const chosen: number[] = [];
    const seen: Set<number> = new Set<number>();
    const prefix = normalizedQuery.substring(0, Math.min(2, normalizedQuery.length));
    if (normalizedQuery.length >= 2) {
      this.takePosting(`h2:${prefix}`, chosen, seen, HISTORY_OMNIBOX_CANDIDATE_CAP);
      this.takePosting(`t2:${prefix}`, chosen, seen, HISTORY_OMNIBOX_CANDIDATE_CAP);
      this.takePosting(`u2:${prefix}`, chosen, seen, HISTORY_OMNIBOX_CANDIDATE_CAP);
      const bigram = this.rarestBigram(normalizedQuery);
      if (bigram.length > 0) {
        this.takePosting(`b:${bigram}`, chosen, seen, HISTORY_OMNIBOX_CANDIDATE_CAP);
      }
      return chosen;
    }
    this.takePosting(`h1:${prefix}`, chosen, seen, HISTORY_OMNIBOX_CANDIDATE_CAP);
    this.takePosting(`t1:${prefix}`, chosen, seen, HISTORY_OMNIBOX_CANDIDATE_CAP);
    this.takePosting(`u1:${prefix}`, chosen, seen, HISTORY_OMNIBOX_CANDIDATE_CAP);
    return chosen;
  }

  private rarestBigram(normalizedQuery: string): string {
    let best = '';
    let bestLength = HISTORY_OMNIBOX_POSTING_SCAN_CAP + 1;
    const max = Math.min(normalizedQuery.length - 1, 8);
    for (let index = 0; index < max; index += 1) {
      const gram = normalizedQuery.substring(index, index + 2);
      const posting = this.postings.get(`b:${gram}`);
      const length = posting === undefined ? 0 : posting.length;
      if (length > 0 && length < bestLength) {
        best = gram;
        bestLength = length;
      }
    }
    return best;
  }

  private takePosting(key: string, chosen: number[], seen: Set<number>, cap: number): void {
    if (chosen.length >= cap) {
      return;
    }
    const posting = this.postings.get(key);
    if (posting === undefined) {
      return;
    }
    const scanLimit = Math.min(posting.length, HISTORY_OMNIBOX_POSTING_SCAN_CAP);
    for (let index = 0; index < scanLimit && chosen.length < cap; index += 1) {
      const slotIndex = posting[index];
      if (seen.has(slotIndex)) {
        continue;
      }
      const slot = this.slots[slotIndex];
      if (slot === undefined || !slot.live) {
        continue;
      }
      seen.add(slotIndex);
      chosen.push(slotIndex);
    }
  }

  private scoreSlot(slot: HistoryOmniboxSlot, normalizedQuery: string, now: number): number {
    let quality = 0;
    if (slot.normalizedHost === normalizedQuery || slot.compactUrl === normalizedQuery) {
      quality = 800;
    } else if (slot.normalizedHost.startsWith(normalizedQuery) || slot.normalizedTitle.startsWith(normalizedQuery)) {
      quality = 600;
    } else if (slot.compactUrl.startsWith(normalizedQuery)) {
      quality = 500;
    } else if (slot.normalizedTitle.indexOf(normalizedQuery) >= 0 ||
      slot.normalizedHost.indexOf(normalizedQuery) >= 0 ||
      slot.compactUrl.indexOf(normalizedQuery) >= 0) {
      quality = 300;
    }
    if (quality === 0) {
      return 0;
    }
    const ageHours = Math.max(0, (now - slot.entry.lastVisitAt) / 3600000);
    const freshness = Math.max(0, 48 - Math.floor(ageHours / 6));
    return quality + Math.min(40, Math.floor(slot.rank / 8)) + freshness;
  }

  private pushTokens(slotIndex: number, slot: HistoryOmniboxSlot, front: boolean): void {
    this.pushPrefix(slotIndex, 'h', slot.normalizedHost, front);
    this.pushPrefix(slotIndex, 't', slot.normalizedTitle, front);
    this.pushPrefix(slotIndex, 'u', slot.compactUrl, front);
    this.pushBigrams(slotIndex, slot.normalizedTitle, front);
    this.pushBigrams(slotIndex, slot.normalizedHost, front);
    this.pushBigrams(slotIndex, slot.compactUrl, front);
  }

  private pushPrefix(slotIndex: number, kind: string, value: string, front: boolean): void {
    if (value.length === 0) {
      return;
    }
    this.pushPosting(`${kind}1:${value.charAt(0)}`, slotIndex, front);
    if (value.length >= 2) {
      this.pushPosting(`${kind}2:${value.substring(0, 2)}`, slotIndex, front);
    }
  }

  private pushBigrams(slotIndex: number, value: string, front: boolean): void {
    const max = Math.min(value.length - 1, HISTORY_OMNIBOX_TOKEN_SPAN);
    for (let index = 0; index < max; index += 1) {
      this.pushPosting(`b:${value.substring(index, index + 2)}`, slotIndex, front);
    }
  }

  private pushPosting(key: string, slotIndex: number, front: boolean): void {
    const existing = this.postings.get(key);
    if (existing === undefined) {
      this.postings.set(key, [slotIndex]);
      return;
    }
    if (existing.length > 0 && existing[0] === slotIndex) {
      return;
    }
    if (front) {
      existing.unshift(slotIndex);
      return;
    }
    existing.push(slotIndex);
  }

  private lowestLiveRank(): number {
    let lowest = Number.POSITIVE_INFINITY;
    for (let index = 0; index < this.slots.length; index += 1) {
      const slot = this.slots[index];
      if (slot.live && slot.rank < lowest) {
        lowest = slot.rank;
      }
    }
    return lowest === Number.POSITIVE_INFINITY ? 0 : lowest;
  }

  private evictLowest(): void {
    let lowestIndex = -1;
    let lowestRank = Number.POSITIVE_INFINITY;
    for (let index = 0; index < this.slots.length; index += 1) {
      const slot = this.slots[index];
      if (!slot.live) {
        continue;
      }
      if (slot.rank < lowestRank) {
        lowestRank = slot.rank;
        lowestIndex = index;
      }
    }
    if (lowestIndex < 0) {
      return;
    }
    this.slots[lowestIndex].live = false;
    this.slotByKey.delete(this.slots[lowestIndex].key);
    this.liveCount = Math.max(0, this.liveCount - 1);
  }

  private toSlot(entry: HistoryOmniboxEntry, now: number): HistoryOmniboxSlot | undefined {
    const url = entry.url.trim();
    if (!isSuggestableHistoryUrl(url)) {
      return undefined;
    }
    const normalizedUrl = normalizeHistoryOmniboxUrl(url);
    const host = normalizeHistoryOmniboxHost(entry.host, normalizedUrl);
    const title = entry.title.trim();
    return {
      entry: {
        id: entry.id.trim().length > 0 ? entry.id.trim() : normalizedUrl,
        title: title.length > 0 ? title : host,
        url: url,
        host: host,
        visitCount: Math.max(0, Math.floor(entry.visitCount)),
        typedCount: Math.max(0, Math.floor(entry.typedCount)),
        lastVisitAt: entry.lastVisitAt
      },
      key: normalizedUrl,
      normalizedTitle: title.toLowerCase(),
      normalizedHost: host,
      compactUrl: compactHistoryOmniboxUrl(normalizedUrl),
      rank: rankHistoryOmniboxEntry(entry, now),
      live: true
    };
  }
}

export function rankHistoryOmniboxEntry(entry: HistoryOmniboxEntry, now: number): number {
  const ageHours = Math.max(0, (now - entry.lastVisitAt) / 3600000);
  const recency = Math.max(0, 240 - ageHours);
  const frequency = Math.min(120, Math.log(1 + Math.max(0, entry.visitCount)) * 24);
  const typed = Math.min(80, Math.max(0, entry.typedCount) * 20);
  return recency + frequency + typed;
}

export function normalizeHistoryOmniboxQuery(value: string): string {
  return compactHistoryOmniboxUrl(value.trim().toLowerCase().replace(/\s+/g, ''));
}

function normalizeHistoryOmniboxUrl(url: string): string {
  const lower = url.trim().toLowerCase();
  if (lower.endsWith('/') && lower.indexOf('?') < 0 && lower.indexOf('#') < 0) {
    return lower.substring(0, lower.length - 1);
  }
  return lower;
}

function normalizeHistoryOmniboxHost(host: string, normalizedUrl: string): string {
  const trimmed = host.trim().toLowerCase();
  if (trimmed.length > 0) {
    return trimmed.startsWith('www.') ? trimmed.substring(4) : trimmed;
  }
  return hostFromHistoryOmniboxUrl(normalizedUrl);
}

function hostFromHistoryOmniboxUrl(normalizedUrl: string): string {
  const protocolMarker = normalizedUrl.indexOf('://');
  const start = protocolMarker < 0 ? 0 : protocolMarker + 3;
  const rest = normalizedUrl.substring(start);
  const slash = rest.indexOf('/');
  const hostWithPort = slash < 0 ? rest : rest.substring(0, slash);
  const port = hostWithPort.indexOf(':');
  const host = port < 0 ? hostWithPort : hostWithPort.substring(0, port);
  return host.startsWith('www.') ? host.substring(4) : host;
}

function compactHistoryOmniboxUrl(value: string): string {
  let compact = value.trim().toLowerCase();
  if (compact.startsWith('https://')) {
    compact = compact.substring('https://'.length);
  } else if (compact.startsWith('http://')) {
    compact = compact.substring('http://'.length);
  }
  if (compact.startsWith('www.')) {
    compact = compact.substring('www.'.length);
  }
  if (compact.endsWith('/') && compact.indexOf('?') < 0 && compact.indexOf('#') < 0) {
    compact = compact.substring(0, compact.length - 1);
  }
  return compact;
}

function isSuggestableHistoryUrl(url: string): boolean {
  const lower = url.trim().toLowerCase();
  if (lower.length === 0 || lower === 'about:blank') {
    return false;
  }
  return !lower.startsWith('about:') &&
    !lower.startsWith('aira:') &&
    !lower.startsWith('data:') &&
    !lower.startsWith('javascript:') &&
    !lower.startsWith('blob:') &&
    !lower.startsWith('chrome:');
}

function pauseHistoryOmniboxIndexWork(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve();
    }, 0);
  });
}
