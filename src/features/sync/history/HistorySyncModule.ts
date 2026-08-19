import type { AiraDesktopAuthorizedSession } from '@/features/desktop-connection/AiraDesktopConnectionModule';
import {
  AiraCloudHistoryRemoteError,
  AiraCloudHistoryRemoteStore,
} from './AiraCloudHistoryRemoteStore';
import { HistorySyncDatabase } from './HistorySyncDatabase';
import {
  HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE,
  HISTORY_SYNC_EXCHANGE_BATCH_SIZE,
  HISTORY_SYNC_MAX_VISITS,
  HISTORY_SYNC_RETENTION_MS,
  type HistorySyncRunResult,
  type HistoryTimelinePage,
  type HistoryNativeCaptureDiagnostics,
  type NativeHistoryVisitDraft,
} from './HistorySyncModels';

const MAX_NETWORK_ROUNDS = 200;
const HISTORY_SEARCH_RESULT_LIMIT = 10_000;
const HISTORY_QUERY_CONCURRENCY = 16;
const FULL_RECONCILIATION_INTERVAL_MS = 6 * 60 * 60 * 1000;
const INCREMENTAL_RECONCILIATION_OVERLAP_MS = 5 * 60 * 1000;

export class HistorySyncModule {
  private readonly database = new HistorySyncDatabase();
  private activeSyncPromise: Promise<HistorySyncRunResult> | null = null;
  private activeSyncKey = '';

  async initialize(): Promise<void> {
    await this.database.initialize();
  }

  runSync(session: AiraDesktopAuthorizedSession): Promise<HistorySyncRunResult> {
    const syncKey = `${session.uid}\n${session.deviceId}`;
    if (this.activeSyncPromise) {
      if (this.activeSyncKey === syncKey) return this.activeSyncPromise;
      return this.activeSyncPromise.then(
        () => this.runSync(session),
        () => this.runSync(session),
      );
    }
    const run = this.runSyncInternal(session).finally(() => {
      if (this.activeSyncPromise === run) {
        this.activeSyncPromise = null;
        this.activeSyncKey = '';
      }
    });
    this.activeSyncKey = syncKey;
    this.activeSyncPromise = run;
    return run;
  }

  async reconcileNativeHistory(
    session: AiraDesktopAuthorizedSession,
    forceFull = false,
  ): Promise<number> {
    const history = globalThis.chrome?.history;
    const now = Date.now();
    const state = await this.database.getState(session.uid, session.deviceId);
    const full = forceFull
      || state.lastFullNativeReconcileAt <= 0
      || now - state.lastFullNativeReconcileAt >= FULL_RECONCILIATION_INTERVAL_MS;
    const diagnostics = createNativeDiagnostics(now, full);
    if (!history?.search || !history.getVisits) {
      diagnostics.error = 'Chrome History API is unavailable in the background context.';
      await this.database.recordNativeDiagnostics(session.uid, session.deviceId, diagnostics);
      console.warn('[DEBUG-HISTORY-V1] history API unavailable');
      return 0;
    }
    const cutoff = now - HISTORY_SYNC_RETENTION_MS;
    const startTime = full
      ? cutoff
      : Math.max(cutoff, state.lastNativeReconcileAt - INCREMENTAL_RECONCILIATION_OVERLAP_MS);
    try {
      const items = await readHistorySearch(history, {
        text: '',
        startTime,
        endTime: now,
        maxResults: HISTORY_SEARCH_RESULT_LIMIT,
      });
      diagnostics.searchItemCount = items.length;
      const drafts: NativeHistoryVisitDraft[] = [];
      for (let offset = 0; offset < items.length; offset += HISTORY_QUERY_CONCURRENCY) {
        const page = items.slice(offset, offset + HISTORY_QUERY_CONCURRENCY);
        diagnostics.queriedItemCount += page.length;
        const results = await Promise.allSettled(page.map(async (item) => {
          const url = normalizeHistoryUrl(item.url);
          if (!url) {
            diagnostics.invalidUrlCount += 1;
            return [];
          }
          const visits = await readHistoryVisits(history, url);
          diagnostics.successfulQueryCount += 1;
          return toNativeDrafts(item, visits, cutoff, now, diagnostics);
        }));
        results.forEach((result) => {
          if (result.status === 'fulfilled') {
            drafts.push(...result.value);
          } else {
            diagnostics.failedQueryCount += 1;
          }
        });
      }
      const uniqueDrafts = Array.from(
        new Map(drafts.map((draft) => [draft.nativeVisitId, draft])).values(),
      ).sort((left, right) => right.visitedAt - left.visitedAt);
      diagnostics.draftCount = uniqueDrafts.length;
      const reconciliationSucceeded = diagnostics.failedQueryCount === 0
        && items.length < HISTORY_SEARCH_RESULT_LIMIT
        && uniqueDrafts.length <= HISTORY_SYNC_MAX_VISITS
        && diagnostics.invalidTimeCount === 0
        && diagnostics.approximateTimeCount === 0;
      const complete = full && reconciliationSucceeded;
      diagnostics.completeReconciliation = complete;
      const changed = await this.database.captureNativeVisits(
        session.uid,
        session.deviceId,
        session.deviceName || 'Aira Desktop',
        uniqueDrafts.slice(0, HISTORY_SYNC_MAX_VISITS),
        complete,
        now,
      );
      diagnostics.changedCount = changed;
      await this.database.recordNativeDiagnostics(session.uid, session.deviceId, diagnostics);
      await this.database.updateNativeReconcileTime(
        session.uid,
        session.deviceId,
        reconciliationSucceeded ? now : state.lastNativeReconcileAt,
        complete,
      );
      await this.database.pruneProjection(session.uid, now);
      console.info('[DEBUG-HISTORY-V1] native reconcile', summarizeDiagnostics(diagnostics));
      return changed;
    } catch (error) {
      diagnostics.error = errorMessage(error);
      await this.database.recordNativeDiagnostics(session.uid, session.deviceId, diagnostics).catch(() => undefined);
      console.error('[DEBUG-HISTORY-V1] native reconcile failed', diagnostics.error);
      throw error;
    }
  }

  async captureVisitedItem(
    session: AiraDesktopAuthorizedSession,
    item: chrome.history.HistoryItem,
  ): Promise<number> {
    const history = globalThis.chrome?.history;
    const url = normalizeHistoryUrl(item.url);
    if (!url) return 0;
    const now = Date.now();
    const visits = history ? await readHistoryVisits(history, url) : [];
    const drafts = toNativeDrafts(item, visits, now - HISTORY_SYNC_RETENTION_MS, now);
    const eventDraft = drafts.length > 0
      ? drafts
      : toNativeEventDraft(item, now - HISTORY_SYNC_RETENTION_MS, now);
    const changed = await this.database.captureNativeVisits(
      session.uid,
      session.deviceId,
      session.deviceName || 'Aira Desktop',
      eventDraft,
      false,
      now,
    );
    await this.database.pruneProjection(session.uid, now);
    return changed;
  }

  async recordNativeRemoval(
    session: AiraDesktopAuthorizedSession,
    removed: chrome.history.RemovedResult,
  ): Promise<number> {
    const changed = await this.database.recordNativeRemoval(
      session.uid,
      session.deviceId,
      removed.urls || [],
      removed.allHistory,
      Date.now(),
    );
    await this.database.pruneProjection(session.uid, Date.now());
    return changed;
  }

  listTimeline(
    accountUid: string,
    options: { query?: string; deviceId?: string; offset?: number; limit?: number } = {},
  ): Promise<HistoryTimelinePage> {
    return this.database.listTimeline(accountUid, options);
  }

  async deleteVisit(session: AiraDesktopAuthorizedSession, visitId: string): Promise<boolean> {
    return this.database.deleteVisit(session.uid, session.deviceId, visitId, Date.now());
  }

  async clearHistory(session: AiraDesktopAuthorizedSession): Promise<number> {
    return this.database.clearHistory(session.uid, session.deviceId, Date.now());
  }

  async markSyncError(session: AiraDesktopAuthorizedSession, error: unknown): Promise<void> {
    await this.database.markSyncError(
      session.uid,
      session.deviceId,
      String((error as Error)?.message || error || 'History sync failed.'),
    );
  }

  private async runSyncInternal(session: AiraDesktopAuthorizedSession): Promise<HistorySyncRunResult> {
    await this.database.initialize();
    const remote = new AiraCloudHistoryRemoteStore(session);
    let state = await this.database.getState(session.uid, session.deviceId);
    let appliedChangeCount = 0;
    let uploadedMutationCount = 0;
    if (!state.initialized || state.bootstrapHead > 0) {
      appliedChangeCount += await this.runBootstrap(session, remote, false);
      state = await this.database.getState(session.uid, session.deviceId);
    }

    let resetAttempted = false;
    for (let round = 0; round < MAX_NETWORK_ROUNDS; round += 1) {
      const mutations = await this.database.listOutbox(
        session.uid,
        HISTORY_SYNC_EXCHANGE_BATCH_SIZE,
      );
      state = await this.database.getState(session.uid, session.deviceId);
      try {
        const response = await remote.exchange({ cursor: state.cursor, mutations });
        appliedChangeCount += await this.database.applyExchange(
          session.uid,
          session.deviceId,
          response,
          Date.now(),
        );
        uploadedMutationCount += response.acknowledgements.length;
        if (response.hasMore) continue;
        const remaining = await this.database.listOutbox(session.uid, 1);
        if (remaining.length > 0) continue;
        await this.database.pruneProjection(session.uid, Date.now());
        return { appliedChangeCount, uploadedMutationCount };
      } catch (error) {
        if (resetAttempted || !requiresBootstrap(error)) throw error;
        resetAttempted = true;
        await this.database.restartBootstrap(session.uid, session.deviceId, Date.now());
        appliedChangeCount += await this.runBootstrap(session, remote, true);
      }
    }
    throw new Error('History sync exceeded the bounded incremental round limit.');
  }

  private async runBootstrap(
    session: AiraDesktopAuthorizedSession,
    remote: AiraCloudHistoryRemoteStore,
    forceRestart: boolean,
  ): Promise<number> {
    if (forceRestart) {
      await this.database.restartBootstrap(session.uid, session.deviceId, Date.now());
    }
    let state = await this.database.getState(session.uid, session.deviceId);
    let firstPage = state.bootstrapHead <= 0 && !state.bootstrapAfterVisitId;
    let applied = 0;
    for (let page = 0; page < MAX_NETWORK_ROUNDS; page += 1) {
      const response = await remote.bootstrap({
        bootstrapHead: state.bootstrapHead > 0 ? state.bootstrapHead : undefined,
        afterUpdatedSeq: state.bootstrapAfterUpdatedSeq > 0
          ? state.bootstrapAfterUpdatedSeq
          : undefined,
        afterVisitId: state.bootstrapAfterVisitId || undefined,
      });
      applied += await this.database.applyBootstrap(
        session.uid,
        session.deviceId,
        response,
        firstPage,
        Date.now(),
      );
      firstPage = false;
      if (!response.hasMore) return applied;
      state = await this.database.getState(session.uid, session.deviceId);
    }
    throw new Error(
      `History bootstrap exceeded ${MAX_NETWORK_ROUNDS * HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE} records in one run.`,
    );
  }
}

function toNativeDrafts(
  item: chrome.history.HistoryItem,
  visits: chrome.history.VisitItem[],
  cutoff: number,
  now: number,
  diagnostics?: HistoryNativeCaptureDiagnostics,
): NativeHistoryVisitDraft[] {
  const url = normalizeHistoryUrl(item.url);
  if (!url) return [];
  return visits.flatMap((visit) => {
    if (diagnostics) diagnostics.rawVisitCount += 1;
    recordHistoryShape(diagnostics, item, visit);
    const exactVisitTime = readHistoryTimestamp(visit, VISIT_TIMESTAMP_KEYS);
    const itemTime = readHistoryTimestamp(item, ITEM_TIMESTAMP_KEYS);
    const canUseItemTime = !exactVisitTime && visits.length === 1 && itemTime > 0;
    const visitedAt = exactVisitTime || (canUseItemTime ? itemTime : 0);
    if (!exactVisitTime && diagnostics) diagnostics.approximateTimeCount += 1;
    const isLocal = (visit as chrome.history.VisitItem & { isLocal?: boolean }).isLocal;
    if (!visitedAt) {
      if (diagnostics) diagnostics.invalidTimeCount += 1;
      return [];
    }
    if (isLocal === false) {
      if (diagnostics) diagnostics.localVisitCount += 1;
      return [];
    }
    if (visitedAt < cutoff || visitedAt > now) {
      if (diagnostics) diagnostics.outOfRangeVisitCount += 1;
      return [];
    }
    const nativeVisitId = String(visit.visitId || '').trim()
      || `${item.id}:${visitedAt}:${String(visit.referringVisitId || '')}`;
    return [{
      nativeVisitId,
      url,
      title: String(item.title || '').trim(),
      visitedAt,
      transition: String(visit.transition || '').trim(),
    }];
  });
}

function toNativeEventDraft(
  item: chrome.history.HistoryItem,
  cutoff: number,
  now: number,
): NativeHistoryVisitDraft[] {
  const url = normalizeHistoryUrl(item.url);
  const visitedAt = readHistoryTimestamp(item, ITEM_TIMESTAMP_KEYS);
  if (!url || !visitedAt || visitedAt < cutoff || visitedAt > now) return [];
  return [{
    nativeVisitId: `event:${item.id}:${visitedAt}`,
    url,
    title: String(item.title || '').trim(),
    visitedAt,
    transition: '',
  }];
}

function normalizeHistoryUrl(value: string | undefined): string {
  try {
    const parsed = new URL(String(value || '').trim());
    return parsed.protocol === 'http:' || parsed.protocol === 'https:' ? parsed.toString() : '';
  } catch {
    return '';
  }
}

function readHistorySearch(
  history: typeof chrome.history,
  query: chrome.history.HistoryQuery,
): Promise<chrome.history.HistoryItem[]> {
  return callHistoryApi((callback) => history.search(query, callback));
}

function readHistoryVisits(
  history: typeof chrome.history,
  url: string,
): Promise<chrome.history.VisitItem[]> {
  return callHistoryApi((callback) => history.getVisits({ url }, callback));
}

function callHistoryApi<T>(
  invoke: (callback: (value: T) => void) => unknown,
): Promise<T> {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (value: T) => {
      if (settled) return;
      settled = true;
      resolve(value);
    };
    try {
      const result = invoke(finish);
      if (result && typeof (result as Promise<T>).then === 'function') {
        void (result as Promise<T>).then(finish, (error: unknown) => {
          if (!settled) {
            settled = true;
            reject(error);
          }
        });
      }
    } catch (error) {
      if (!settled) {
        settled = true;
        reject(error);
      }
    }
  });
}

function requiresBootstrap(error: unknown): boolean {
  return error instanceof AiraCloudHistoryRemoteError
    && (error.code === 'history_cursor_expired' || error.code === 'history_cursor_ahead');
}

function createNativeDiagnostics(now: number, fullReconciliation: boolean): HistoryNativeCaptureDiagnostics {
  return {
    checkedAt: now,
    fullReconciliation,
    historyApiAvailable: true,
    searchItemCount: 0,
    queriedItemCount: 0,
    rawVisitCount: 0,
    successfulQueryCount: 0,
    failedQueryCount: 0,
    invalidUrlCount: 0,
    localVisitCount: 0,
    invalidTimeCount: 0,
    outOfRangeVisitCount: 0,
    approximateTimeCount: 0,
    visitShape: '',
    itemShape: '',
    visitTimeType: '',
    itemLastVisitTimeType: '',
    visitTimeValueKind: '',
    itemLastVisitTimeValueKind: '',
    draftCount: 0,
    changedCount: 0,
    completeReconciliation: false,
    error: '',
  };
}

function errorMessage(error: unknown): string {
  return String((error as Error)?.message || error || 'Unknown history capture error.').slice(0, 500);
}

function summarizeDiagnostics(diagnostics: HistoryNativeCaptureDiagnostics): string {
  return JSON.stringify({
    search: diagnostics.searchItemCount,
    rawVisits: diagnostics.rawVisitCount,
    drafts: diagnostics.draftCount,
    changed: diagnostics.changedCount,
    approximateTimes: diagnostics.approximateTimeCount,
    visitShape: diagnostics.visitShape,
    itemShape: diagnostics.itemShape,
    visitTimeType: diagnostics.visitTimeType,
    itemLastVisitTimeType: diagnostics.itemLastVisitTimeType,
    visitTimeValueKind: diagnostics.visitTimeValueKind,
    itemLastVisitTimeValueKind: diagnostics.itemLastVisitTimeValueKind,
    failedQueries: diagnostics.failedQueryCount,
    error: diagnostics.error,
  });
}

function recordHistoryShape(
  diagnostics: HistoryNativeCaptureDiagnostics | undefined,
  item: chrome.history.HistoryItem,
  visit: chrome.history.VisitItem,
): void {
  if (!diagnostics || diagnostics.visitShape) return;
  diagnostics.visitShape = Object.keys(visit).sort().join(',').slice(0, 500);
  diagnostics.itemShape = Object.keys(item).sort().join(',').slice(0, 500);
  const visitRecord = visit as unknown as Record<string, unknown>;
  const itemRecord = item as unknown as Record<string, unknown>;
  const visitTime = readFirstField(visitRecord, VISIT_TIMESTAMP_KEYS);
  const itemTime = readFirstField(itemRecord, ITEM_TIMESTAMP_KEYS);
  diagnostics.visitTimeType = typeof visitTime;
  diagnostics.itemLastVisitTimeType = typeof itemTime;
  diagnostics.visitTimeValueKind = describeValueKind(visitTime);
  diagnostics.itemLastVisitTimeValueKind = describeValueKind(itemTime);
}

const VISIT_TIMESTAMP_KEYS = ['visitTime', 'visit_time'];
const ITEM_TIMESTAMP_KEYS = ['lastVisitTime', 'last_visit_time'];

function readHistoryTimestamp(record: unknown, keys: readonly string[]): number {
  return parseHistoryTimestamp(readFirstField(record, keys));
}

function readFirstField(record: unknown, keys: readonly string[]): unknown {
  if (!record || typeof record !== 'object') return undefined;
  const values = record as Record<string, unknown>;
  for (const key of keys) {
    if (values[key] !== undefined && values[key] !== null) return values[key];
  }
  return undefined;
}

function describeValueKind(value: unknown): string {
  if (value === undefined) return 'undefined';
  if (value === null) return 'null';
  if (value instanceof Date) return 'Date';
  if (typeof value !== 'object') return typeof value;
  const constructorName = (value as { constructor?: { name?: unknown } }).constructor?.name;
  const keys = Reflect.ownKeys(value as object)
    .filter((key): key is string => typeof key === 'string')
    .slice(0, 8);
  return `object:${String(constructorName || 'unknown')}:${keys.join(',')}`.slice(0, 160);
}

function parseHistoryTimestamp(value: unknown): number {
  if (value instanceof Date) {
    const timestamp = value.getTime();
    return Number.isSafeInteger(timestamp) && timestamp > 0 ? timestamp : 0;
  }
  const raw = typeof value === 'string' ? value.trim() : value;
  if (raw === '' || raw === null || raw === undefined) return 0;
  let number = Number(raw);
  if (!Number.isFinite(number)) {
    const parsed = Date.parse(String(raw));
    number = Number.isFinite(parsed) ? parsed : 0;
  }
  if (!Number.isFinite(number) || number <= 0) return 0;
  if (number < 100_000_000_000) number *= 1_000;
  else if (number > 100_000_000_000_000_000) number /= 1_000_000;
  else if (number > 100_000_000_000_000) number /= 1_000;
  const timestamp = Math.trunc(number);
  return Number.isSafeInteger(timestamp) && timestamp > 0 ? timestamp : 0;
}
