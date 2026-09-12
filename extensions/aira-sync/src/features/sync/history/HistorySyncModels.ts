export const HISTORY_SYNC_EXCHANGE_BATCH_SIZE = 200;
export const HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE = 500;
export const HISTORY_SYNC_RETENTION_MS = 90 * 24 * 60 * 60 * 1000;
export const HISTORY_SYNC_MAX_VISITS = 10_000;

export type HistorySyncMutationKind =
  | 'upsert_visit'
  | 'delete_visit'
  | 'delete_range'
  | 'clear_before';

export type HistorySyncChangeKind = HistorySyncMutationKind | 'retention_prune';

export type HistorySyncVisit = {
  visitId: string;
  clientId: string;
  nativeVisitId: string;
  url: string;
  title: string;
  visitedAt: number;
  transition: string;
  referrer: string;
  deviceName: string;
  source: string;
};

export type HistorySyncMutation = {
  mutationId: string;
  kind: HistorySyncMutationKind;
  visit?: HistorySyncVisit;
  visitId?: string;
  url?: string;
  startedAt?: number;
  endedAt?: number;
  clearBefore?: number;
};

export type HistorySyncMutationAcknowledgement = {
  mutationId: string;
  acceptedSeq: number;
  applied: boolean;
};

export type HistorySyncDeleteRange = {
  rangeId: string;
  url: string;
  startedAt: number;
  endedAt: number;
  seq: number;
};

export type HistorySyncChange = {
  seq: number;
  kind: HistorySyncChangeKind;
  visitId: string;
  visit?: HistorySyncVisit;
  rangeId?: string;
  url?: string;
  startedAt?: number;
  endedAt?: number;
  clearBefore?: number;
  visitIds?: string[];
  cutoff?: number;
};

export type HistorySyncExchangeResponse = {
  acknowledgements: HistorySyncMutationAcknowledgement[];
  changes: HistorySyncChange[];
  nextCursor: number;
  headCursor: number;
  hasMore: boolean;
};

export type HistorySyncBootstrapKey = {
  updatedSeq: number;
  visitId: string;
};

export type HistorySyncBootstrapResponse = {
  bootstrapHead: number;
  headCursor: number;
  visits: HistorySyncVisit[];
  deletedVisitIds: string[];
  clearBefore: number;
  deleteRanges: HistorySyncDeleteRange[];
  nextKey?: HistorySyncBootstrapKey;
  hasMore: boolean;
};

export type HistorySyncLocalState = {
  accountUid: string;
  clientId: string;
  initialized: boolean;
  cursor: number;
  bootstrapHead: number;
  bootstrapAfterUpdatedSeq: number;
  bootstrapAfterVisitId: string;
  clearBefore: number;
  lastNativeReconcileAt: number;
  lastFullNativeReconcileAt: number;
  lastSyncAt: number;
  lastError: string;
  updatedAt: number;
};

export type NativeHistoryVisitDraft = {
  nativeVisitId: string;
  url: string;
  title: string;
  visitedAt: number;
  transition: string;
};

export type HistorySyncRunResult = {
  appliedChangeCount: number;
  uploadedMutationCount: number;
};

export type HistoryTimelineDevice = {
  id: string;
  name: string;
};

export type HistoryTimelinePage = {
  visits: HistorySyncVisit[];
  total: number;
  devices: HistoryTimelineDevice[];
  lastSyncAt: number;
  lastError: string;
};

// A desktop extension reports its raw User-Agent as the device name, which changes
// with every browser update and never identifies one physical device across
// reinstalls. Reduce it to a stable, human label for grouping and display; leave
// explicit names (such as "Aira HarmonyOS") untouched.
export function historyDeviceDisplayLabel(deviceName: string): string {
  const name = String(deviceName || '').trim();
  if (!name) return '';
  if (!/Mozilla\/|AppleWebKit|Chrome\/|Safari\/|Firefox\//i.test(name)) return name;
  const platform = /Windows/i.test(name) ? 'Windows'
    : /Android/i.test(name) ? 'Android'
      : /iPhone|iPad|iPod/i.test(name) ? 'iOS'
        : /Macintosh|Mac OS X/i.test(name) ? 'macOS'
          : /Linux/i.test(name) ? 'Linux'
            : '';
  const browser = /Edg\//.test(name) ? 'Edge'
    : /OPR\/|Opera\//.test(name) ? 'Opera'
      : /Firefox\//.test(name) ? 'Firefox'
        : /Chrome\//.test(name) ? 'Chrome'
          : /Safari\//.test(name) ? 'Safari'
            : '';
  const label = [browser, platform].filter(Boolean).join(' · ');
  return label || name.slice(0, 120);
}
