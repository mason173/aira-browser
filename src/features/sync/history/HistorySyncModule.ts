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
    if (!history?.search || !history.getVisits) return 0;
    const now = Date.now();
    const state = await this.database.getState(session.uid, session.deviceId);
    const full = forceFull
      || state.lastFullNativeReconcileAt <= 0
      || now - state.lastFullNativeReconcileAt >= FULL_RECONCILIATION_INTERVAL_MS;
    const cutoff = now - HISTORY_SYNC_RETENTION_MS;
    const startTime = full
      ? cutoff
      : Math.max(cutoff, state.lastNativeReconcileAt - INCREMENTAL_RECONCILIATION_OVERLAP_MS);
    const items = await history.search({
      text: '',
      startTime,
      endTime: now,
      maxResults: HISTORY_SEARCH_RESULT_LIMIT,
    });
    const drafts: NativeHistoryVisitDraft[] = [];
    let failedQueries = 0;
    for (let offset = 0; offset < items.length; offset += HISTORY_QUERY_CONCURRENCY) {
      const page = items.slice(offset, offset + HISTORY_QUERY_CONCURRENCY);
      const results = await Promise.allSettled(page.map(async (item) => {
        const url = normalizeHistoryUrl(item.url);
        if (!url) return [];
        const visits = await history.getVisits({ url });
        return toNativeDrafts(item, visits, cutoff, now);
      }));
      results.forEach((result) => {
        if (result.status === 'fulfilled') {
          drafts.push(...result.value);
        } else {
          failedQueries += 1;
        }
      });
    }
    const uniqueDrafts = Array.from(
      new Map(drafts.map((draft) => [draft.nativeVisitId, draft])).values(),
    ).sort((left, right) => right.visitedAt - left.visitedAt);
    const complete = full
      && failedQueries === 0
      && items.length < HISTORY_SEARCH_RESULT_LIMIT
      && uniqueDrafts.length <= HISTORY_SYNC_MAX_VISITS;
    const changed = await this.database.captureNativeVisits(
      session.uid,
      session.deviceId,
      session.deviceName || 'Aira Desktop',
      uniqueDrafts.slice(0, HISTORY_SYNC_MAX_VISITS),
      complete,
      now,
    );
    await this.database.updateNativeReconcileTime(session.uid, session.deviceId, now, full);
    await this.database.pruneProjection(session.uid, now);
    return changed;
  }

  async captureVisitedItem(
    session: AiraDesktopAuthorizedSession,
    item: chrome.history.HistoryItem,
  ): Promise<number> {
    const history = globalThis.chrome?.history;
    const url = normalizeHistoryUrl(item.url);
    if (!history?.getVisits || !url) return 0;
    const now = Date.now();
    const visits = await history.getVisits({ url });
    const changed = await this.database.captureNativeVisits(
      session.uid,
      session.deviceId,
      session.deviceName || 'Aira Desktop',
      toNativeDrafts(item, visits, now - HISTORY_SYNC_RETENTION_MS, now),
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
): NativeHistoryVisitDraft[] {
  const url = normalizeHistoryUrl(item.url);
  if (!url) return [];
  return visits.flatMap((visit) => {
    const visitedAt = Number(visit.visitTime || 0);
    const isLocal = (visit as chrome.history.VisitItem & { isLocal?: boolean }).isLocal;
    if (!Number.isSafeInteger(visitedAt) || visitedAt < cutoff || visitedAt > now || isLocal === false) {
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

function normalizeHistoryUrl(value: string | undefined): string {
  try {
    const parsed = new URL(String(value || '').trim());
    return parsed.protocol === 'http:' || parsed.protocol === 'https:' ? parsed.toString() : '';
  } catch {
    return '';
  }
}

function requiresBootstrap(error: unknown): boolean {
  return error instanceof AiraCloudHistoryRemoteError
    && (error.code === 'history_cursor_expired' || error.code === 'history_cursor_ahead');
}
