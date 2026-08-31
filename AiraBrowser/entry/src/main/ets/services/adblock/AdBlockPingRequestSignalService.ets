interface AdBlockPingRequestSignalEntry {
  count: number;
  expiresAt: number;
}

const PING_REQUEST_SIGNAL_TTL_MS: number = 2000;
const MAX_PING_REQUEST_SIGNALS_PER_TAB: number = 64;
const MAX_PING_REQUEST_SIGNAL_TABS: number = 64;

export class AdBlockPingRequestSignalService {
  private readonly signalsByTabId: Map<string, Map<string, AdBlockPingRequestSignalEntry>> =
    new Map<string, Map<string, AdBlockPingRequestSignalEntry>>();

  record(tabId: string, url: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedUrl = url.trim();
    if (normalizedTabId.length <= 0 || !this.isHttpUrl(normalizedUrl)) {
      return;
    }
    const now = Date.now();
    let signals = this.signalsByTabId.get(normalizedTabId);
    if (signals === undefined) {
      this.evictOldestTabIfNeeded();
      signals = new Map<string, AdBlockPingRequestSignalEntry>();
      this.signalsByTabId.set(normalizedTabId, signals);
    }
    this.pruneExpired(signals, now);
    const existing = signals.get(normalizedUrl);
    if (existing !== undefined) {
      existing.count += 1;
      existing.expiresAt = now + PING_REQUEST_SIGNAL_TTL_MS;
      return;
    }
    if (signals.size >= MAX_PING_REQUEST_SIGNALS_PER_TAB) {
      let oldestUrl = '';
      let oldestExpiresAt = Number.MAX_VALUE;
      signals.forEach((entry: AdBlockPingRequestSignalEntry, candidateUrl: string) => {
        if (oldestUrl.length <= 0 || entry.expiresAt < oldestExpiresAt) {
          oldestUrl = candidateUrl;
          oldestExpiresAt = entry.expiresAt;
        }
      });
      if (oldestUrl.length > 0) {
        signals.delete(oldestUrl);
      }
    }
    signals.set(normalizedUrl, {
      count: 1,
      expiresAt: now + PING_REQUEST_SIGNAL_TTL_MS
    });
  }

  consume(tabId: string, url: string, method: string): boolean {
    if (method.trim().toUpperCase() !== 'POST') {
      return false;
    }
    const normalizedTabId = tabId.trim();
    const signals = this.signalsByTabId.get(normalizedTabId);
    if (signals === undefined) {
      return false;
    }
    const now = Date.now();
    this.pruneExpired(signals, now);
    const normalizedUrl = url.trim();
    const entry = signals.get(normalizedUrl);
    if (entry === undefined || entry.expiresAt < now) {
      this.removeEmptyTab(normalizedTabId, signals);
      return false;
    }
    if (entry.count <= 1) {
      signals.delete(normalizedUrl);
    } else {
      entry.count -= 1;
    }
    this.removeEmptyTab(normalizedTabId, signals);
    return true;
  }

  clearTab(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length > 0) {
      this.signalsByTabId.delete(normalizedTabId);
    }
  }

  private pruneExpired(signals: Map<string, AdBlockPingRequestSignalEntry>, now: number): void {
    const expiredUrls: string[] = [];
    signals.forEach((entry: AdBlockPingRequestSignalEntry, url: string) => {
      if (entry.expiresAt < now) {
        expiredUrls.push(url);
      }
    });
    expiredUrls.forEach((url: string) => signals.delete(url));
  }

  private removeEmptyTab(tabId: string, signals: Map<string, AdBlockPingRequestSignalEntry>): void {
    if (signals.size <= 0) {
      this.signalsByTabId.delete(tabId);
    }
  }

  private evictOldestTabIfNeeded(): void {
    if (this.signalsByTabId.size < MAX_PING_REQUEST_SIGNAL_TABS) {
      return;
    }
    let oldestTabId = '';
    this.signalsByTabId.forEach((_signals: Map<string, AdBlockPingRequestSignalEntry>, tabId: string) => {
      if (oldestTabId.length <= 0) {
        oldestTabId = tabId;
      }
    });
    if (oldestTabId.length > 0) {
      this.signalsByTabId.delete(oldestTabId);
    }
  }

  private isHttpUrl(url: string): boolean {
    return url.startsWith('http://') || url.startsWith('https://');
  }
}
