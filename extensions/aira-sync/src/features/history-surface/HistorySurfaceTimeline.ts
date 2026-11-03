import { callBrowserHistoryApi } from '@/platform/browserHistoryApi';
import { historyDeviceDisplayLabel, type HistorySyncVisit, type HistoryTimelinePage } from '@/features/sync/history/HistorySyncModels';

const NATIVE_PREFIX = 'browser-native:';
const QUERY_CONCURRENCY = 16;

type TimelineOptions = { query?: string; deviceId?: string; offset?: number; limit?: number };
type CachedVisits = { signature: string; visits: HistorySyncVisit[] };

/** A read-only view of browser-owned history. Nothing read here enters the sync ledger/outbox. */
export class HistorySurfaceTimeline {
  private readonly cache = new Map<string, CachedVisits>();
  private revision = 0;

  invalidate(url?: string): void {
    this.revision += 1;
    if (url) this.cache.delete(url);
    else this.cache.clear();
  }

  async list(
    synced: HistoryTimelinePage,
    localDeviceId: string,
    localDeviceName: string,
    options: TimelineOptions,
  ): Promise<HistoryTimelinePage> {
    const history = globalThis.chrome?.history;
    if (!history?.search || !history.getVisits) return synced;
    const offset = Math.max(0, Math.floor(options.offset || 0));
    const limit = Math.max(1, Math.floor(options.limit || 200));
    const needed = offset + limit;
    const deviceName = historyDeviceDisplayLabel(localDeviceName) || 'This device';
    const native = !options.deviceId || options.deviceId === deviceName
      ? await this.readNative(options.query || '', needed + 1, deviceName)
      : { visits: [], hasMore: false };
    // This browser's native store is authoritative for its local rows. A bounded
    // sync mirror (including remote tombstones/pruning) cannot hide those rows or
    // make a removed native row reappear as a second copy of this device's history.
    const remote = synced.visits.filter(visit => visit.clientId !== localDeviceId);
    const merged = [...native.visits, ...remote].sort(compareVisits);
    return {
      ...synced,
      visits: merged.slice(offset, needed),
      // The native API has no count query. This is a lower bound until exhausted;
      // consumers use hasMore, not this number as a claimed browser-wide total.
      total: merged.length + (native.hasMore ? 1 : 0),
      hasMore: native.hasMore || merged.length > needed,
      devices: [{ id: deviceName, name: deviceName }, ...synced.devices.filter(device => device.id !== deviceName)],
    };
  }

  private async readNative(query: string, needed: number, deviceName: string) {
    const history = globalThis.chrome.history;
    const items = await callBrowserHistoryApi<chrome.history.HistoryItem[]>(callback => history.search({
      text: query, startTime: 0, maxResults: needed,
    }, callback));
    const visits: HistorySyncVisit[] = [];
    for (let index = 0; index < items.length; index += QUERY_CONCURRENCY) {
      const batch = items.slice(index, index + QUERY_CONCURRENCY);
      const results = await Promise.all(batch.map(item => this.readItem(item, deviceName)));
      for (const result of results) for (const visit of result) visits.push(visit);
    }
    visits.sort(compareVisits);
    return { visits: visits.slice(0, needed), hasMore: items.length >= needed || visits.length > needed };
  }

  private async readItem(item: chrome.history.HistoryItem, deviceName: string): Promise<HistorySyncVisit[]> {
    const url = item.url;
    if (!url) return [];
    const signature = JSON.stringify([item.id, item.title, item.lastVisitTime, item.visitCount, deviceName]);
    const cached = this.cache.get(url);
    if (cached?.signature === signature) return cached.visits;
    const revision = this.revision;
    const native = await callBrowserHistoryApi<chrome.history.VisitItem[]>(callback =>
      globalThis.chrome.history.getVisits({ url }, callback));
    const visits = native.flatMap(visit => {
      const visitedAt = visit.visitTime;
      if (!visitedAt || !Number.isFinite(visitedAt)) return [];
      return [makeNativeVisit(url, item.title || '', String(visit.visitId), visitedAt, deviceName, visit.transition)];
    });
    // Some browsers expose a HistoryItem without individual visit details. Keep
    // that native entry visible; this fallback is never eligible for upload.
    if (visits.length === 0 && item.lastVisitTime) {
      visits.push(makeNativeVisit(url, item.title || '', item.id, item.lastVisitTime, deviceName, ''));
    }
    if (revision === this.revision) this.cache.set(url, { signature, visits });
    return visits;
  }
}

function makeNativeVisit(url: string, title: string, id: string, visitedAt: number, deviceName: string, transition: string): HistorySyncVisit {
  return {
    visitId: `${NATIVE_PREFIX}${encodeURIComponent(url)}:${encodeURIComponent(id)}`,
    clientId: 'browser-native', nativeVisitId: id, url, title, visitedAt, deviceName,
    transition, referrer: '', source: 'browser-native',
  };
}

function compareVisits(left: HistorySyncVisit, right: HistorySyncVisit): number {
  return right.visitedAt - left.visitedAt || right.visitId.localeCompare(left.visitId);
}

export function nativeHistoryUrlForVisitId(visitId: string): string | null {
  if (!visitId.startsWith(NATIVE_PREFIX)) return null;
  const encoded = visitId.slice(NATIVE_PREFIX.length);
  const separator = encoded.lastIndexOf(':');
  if (separator < 0) throw new Error('Invalid native history visit ID.');
  return new URL(decodeURIComponent(encoded.slice(0, separator))).href;
}
