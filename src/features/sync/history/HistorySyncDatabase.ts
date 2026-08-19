import {
  HISTORY_SYNC_MAX_VISITS,
  HISTORY_SYNC_RETENTION_MS,
  type HistorySyncBootstrapResponse,
  type HistorySyncChange,
  type HistorySyncDeleteRange,
  type HistorySyncExchangeResponse,
  type HistorySyncLocalState,
  type HistorySyncMutation,
  type HistorySyncVisit,
  type HistoryTimelinePage,
  type NativeHistoryVisitDraft,
} from './HistorySyncModels';

const DATABASE_NAME = 'aira_history_sync_v1';
const DATABASE_VERSION = 1;
const VISITS_STORE = 'visits';
const OUTBOX_STORE = 'outbox';
const STATE_STORE = 'state';
const LEDGER_STORE = 'nativeLedger';
const RANGES_STORE = 'deleteRanges';
const ACCOUNT_INDEX = 'accountUid';

type StoredVisit = HistorySyncVisit & {
  key: string;
  accountUid: string;
};

type StoredMutation = {
  key: string;
  accountUid: string;
  createdAt: number;
  mutation: HistorySyncMutation;
};

type StoredState = HistorySyncLocalState & {
  key: string;
};

type StoredNativeLedger = {
  key: string;
  accountUid: string;
  clientId: string;
  nativeVisitId: string;
  visitId: string;
  url: string;
  visitedAt: number;
  deleted: boolean;
  syncState: 'pending' | 'accepted' | 'deleted';
  updatedAt: number;
};

type StoredDeleteRange = HistorySyncDeleteRange & {
  key: string;
  accountUid: string;
};

type AccountStores = {
  visits: IDBObjectStore;
  outbox: IDBObjectStore;
  state: IDBObjectStore;
  ledger: IDBObjectStore;
  ranges: IDBObjectStore;
};

export class HistorySyncDatabase {
  private databasePromise: Promise<IDBDatabase> | null = null;

  async initialize(): Promise<void> {
    await this.getDatabase();
  }

  async getState(accountUid: string, clientId: string): Promise<HistorySyncLocalState> {
    const database = await this.getDatabase();
    const transaction = database.transaction(STATE_STORE, 'readonly');
    const done = transactionDone(transaction);
    const stored = await requestResult<StoredState | undefined>(
      transaction.objectStore(STATE_STORE).get(stateKey(accountUid, clientId)),
    );
    await done;
    return stored ? stripStoredState(stored) : createDefaultState(accountUid, clientId);
  }

  async captureNativeVisits(
    accountUid: string,
    clientId: string,
    deviceName: string,
    drafts: NativeHistoryVisitDraft[],
    completeReconciliation: boolean,
    now: number,
  ): Promise<number> {
    if (drafts.length <= 0 && !completeReconciliation) return 0;
    return this.withAccountTransaction('readwrite', async (stores) => {
      const [state, ledgerRows, rangeRows, outboxRows] = await Promise.all([
        readStateFromStore(stores.state, accountUid, clientId),
        readAccountRows<StoredNativeLedger>(stores.ledger, accountUid),
        readAccountRows<StoredDeleteRange>(stores.ranges, accountUid),
        readAccountRows<StoredMutation>(stores.outbox, accountUid),
      ]);
      const ledgerByNativeId = new Map(
        ledgerRows
          .filter((row) => row.clientId === clientId)
          .map((row) => [row.nativeVisitId, row]),
      );
      const pendingVisitIds = new Set(
        outboxRows
          .filter((row) => row.mutation.kind === 'upsert_visit' && row.mutation.visit)
          .map((row) => row.mutation.visit?.visitId || ''),
      );
      const incomingNativeIds = new Set<string>();
      let changed = 0;

      for (const draft of drafts) {
        incomingNativeIds.add(draft.nativeVisitId);
        const existing = ledgerByNativeId.get(draft.nativeVisitId);
        if (existing) {
          if (existing.syncState === 'pending' && !pendingVisitIds.has(existing.visitId)) {
            const visit = toHistoryVisit(clientId, deviceName, draft);
            putMutation(stores.outbox, accountUid, createUpsertMutation(clientId, visit, now), now);
          }
          continue;
        }
        const visit = toHistoryVisit(clientId, deviceName, draft);
        const blocked = isVisitBlocked(visit, state.clearBefore, rangeRows);
        const ledger: StoredNativeLedger = {
          key: ledgerKey(accountUid, clientId, draft.nativeVisitId),
          accountUid,
          clientId,
          nativeVisitId: draft.nativeVisitId,
          visitId: visit.visitId,
          url: visit.url,
          visitedAt: visit.visitedAt,
          deleted: blocked,
          syncState: blocked ? 'deleted' : 'pending',
          updatedAt: now,
        };
        stores.ledger.put(ledger);
        ledgerByNativeId.set(draft.nativeVisitId, ledger);
        if (!blocked) {
          stores.visits.put(toStoredVisit(accountUid, visit));
          putMutation(stores.outbox, accountUid, createUpsertMutation(clientId, visit, now), now);
          changed += 1;
        }
      }

      if (completeReconciliation) {
        const retentionCutoff = now - HISTORY_SYNC_RETENTION_MS;
        for (const ledger of ledgerRows) {
          if (
            ledger.clientId !== clientId
            || ledger.deleted
            || ledger.visitedAt < retentionCutoff
            || incomingNativeIds.has(ledger.nativeVisitId)
          ) {
            continue;
          }
          const deletedLedger: StoredNativeLedger = {
            ...ledger,
            deleted: true,
            syncState: 'deleted',
            updatedAt: now,
          };
          stores.ledger.put(deletedLedger);
          stores.visits.delete(visitKey(accountUid, ledger.visitId));
          putMutation(stores.outbox, accountUid, createDeleteVisitMutation(clientId, ledger.visitId, now), now);
          changed += 1;
        }
      }
      return changed;
    });
  }

  async recordNativeRemoval(
    accountUid: string,
    clientId: string,
    urls: string[],
    clearAll: boolean,
    now: number,
  ): Promise<number> {
    return this.withAccountTransaction('readwrite', async (stores) => {
      const [state, visits, ledgerRows] = await Promise.all([
        readStateFromStore(stores.state, accountUid, clientId),
        readAccountRows<StoredVisit>(stores.visits, accountUid),
        readAccountRows<StoredNativeLedger>(stores.ledger, accountUid),
      ]);
      const normalizedUrls = new Set(urls.map(normalizeHttpUrl).filter(Boolean));
      let changed = 0;
      if (clearAll) {
        for (const visit of visits) {
          if (visit.visitedAt <= now) {
            stores.visits.delete(visit.key);
            changed += 1;
          }
        }
        markLedgerDeleted(stores.ledger, ledgerRows, (row) => row.visitedAt <= now, now);
        putMutation(stores.outbox, accountUid, createClearMutation(clientId, now), now);
        writeState(stores.state, {
          ...state,
          clearBefore: Math.max(state.clearBefore, now),
          updatedAt: now,
        });
        return changed;
      }

      for (const ledger of ledgerRows) {
        if (ledger.deleted || !normalizedUrls.has(ledger.url)) continue;
        stores.ledger.put({
          ...ledger,
          deleted: true,
          syncState: 'deleted',
          updatedAt: now,
        } satisfies StoredNativeLedger);
        stores.visits.delete(visitKey(accountUid, ledger.visitId));
        putMutation(stores.outbox, accountUid, createDeleteVisitMutation(clientId, ledger.visitId, now), now);
        changed += 1;
      }
      return changed;
    });
  }

  async listOutbox(accountUid: string, limit: number): Promise<HistorySyncMutation[]> {
    const database = await this.getDatabase();
    const transaction = database.transaction(OUTBOX_STORE, 'readonly');
    const done = transactionDone(transaction);
    const rows = await readAccountRows<StoredMutation>(transaction.objectStore(OUTBOX_STORE), accountUid);
    await done;
    return rows
      .sort((left, right) => left.createdAt - right.createdAt || left.key.localeCompare(right.key))
      .slice(0, Math.max(0, limit))
      .map((row) => row.mutation);
  }

  async applyExchange(
    accountUid: string,
    clientId: string,
    response: HistorySyncExchangeResponse,
    now: number,
  ): Promise<number> {
    return this.withAccountTransaction('readwrite', async (stores) => {
      const [state, ledgerRows, rangeRows] = await Promise.all([
        readStateFromStore(stores.state, accountUid, clientId),
        readAccountRows<StoredNativeLedger>(stores.ledger, accountUid),
        readAccountRows<StoredDeleteRange>(stores.ranges, accountUid),
      ]);
      const ledgerByVisitId = new Map(ledgerRows.map((row) => [row.visitId, row]));
      const ranges = rangeRows.slice();

      for (const acknowledgement of response.acknowledgements) {
        const key = mutationKey(accountUid, acknowledgement.mutationId);
        const stored = await requestResult<StoredMutation | undefined>(stores.outbox.get(key));
        stores.outbox.delete(key);
        const visitId = stored?.mutation.kind === 'upsert_visit'
          ? stored.mutation.visit?.visitId || ''
          : '';
        const ledger = visitId ? ledgerByVisitId.get(visitId) : undefined;
        if (ledger && !ledger.deleted) {
          const accepted: StoredNativeLedger = {
            ...ledger,
            syncState: 'accepted',
            updatedAt: now,
          };
          stores.ledger.put(accepted);
          ledgerByVisitId.set(visitId, accepted);
        }
      }

      let clearBefore = state.clearBefore;
      let applied = 0;
      for (const change of response.changes) {
        const result = await applyRemoteChange(
          stores,
          accountUid,
          change,
          clearBefore,
          ranges,
          ledgerByVisitId,
          now,
        );
        clearBefore = result.clearBefore;
        applied += result.applied;
      }
      writeState(stores.state, {
        ...state,
        initialized: true,
        cursor: response.nextCursor,
        clearBefore,
        lastSyncAt: now,
        lastError: '',
        updatedAt: now,
      });
      return applied;
    });
  }

  async applyBootstrap(
    accountUid: string,
    clientId: string,
    response: HistorySyncBootstrapResponse,
    firstPage: boolean,
    now: number,
  ): Promise<number> {
    return this.withAccountTransaction('readwrite', async (stores) => {
      const [state, ledgerRows, existingRanges, outboxRows] = await Promise.all([
        readStateFromStore(stores.state, accountUid, clientId),
        readAccountRows<StoredNativeLedger>(stores.ledger, accountUid),
        readAccountRows<StoredDeleteRange>(stores.ranges, accountUid),
        readAccountRows<StoredMutation>(stores.outbox, accountUid),
      ]);
      const ledgerByVisitId = new Map(ledgerRows.map((row) => [row.visitId, row]));
      const ranges = firstPage ? response.deleteRanges.map((range) => toStoredRange(accountUid, range)) : existingRanges;
      const clearBefore = Math.max(state.clearBefore, response.clearBefore);
      let applied = 0;

      if (firstPage) {
        const existingVisits = await readAccountRows<StoredVisit>(stores.visits, accountUid);
        existingVisits.forEach((visit) => stores.visits.delete(visit.key));
        existingRanges.forEach((range) => stores.ranges.delete(range.key));
        ranges.forEach((range) => stores.ranges.put(range));
        for (const row of outboxRows) {
          const visit = row.mutation.kind === 'upsert_visit' ? row.mutation.visit : undefined;
          if (visit && !isVisitBlocked(visit, clearBefore, ranges)) {
            stores.visits.put(toStoredVisit(accountUid, visit));
          }
        }
      }

      for (const visit of response.visits) {
        if (!isVisitBlocked(visit, clearBefore, ranges)) {
          stores.visits.put(toStoredVisit(accountUid, visit));
          applied += 1;
        }
      }
      for (const visitId of response.deletedVisitIds) {
        stores.visits.delete(visitKey(accountUid, visitId));
        const ledger = ledgerByVisitId.get(visitId);
        if (ledger && !ledger.deleted) {
          stores.ledger.put({
            ...ledger,
            deleted: true,
            syncState: 'deleted',
            updatedAt: now,
          } satisfies StoredNativeLedger);
        }
        applied += 1;
      }
      for (const range of ranges) {
        applied += await applyRangeToAccount(stores, accountUid, range, ledgerByVisitId, now);
      }
      applied += await applyClearToAccount(
        stores,
        accountUid,
        clearBefore,
        ledgerByVisitId,
        now,
      );

      const nextKey = response.nextKey;
      writeState(stores.state, {
        ...state,
        initialized: !response.hasMore,
        cursor: response.hasMore ? 0 : response.bootstrapHead,
        bootstrapHead: response.hasMore ? response.bootstrapHead : 0,
        bootstrapAfterUpdatedSeq: response.hasMore ? nextKey?.updatedSeq || 0 : 0,
        bootstrapAfterVisitId: response.hasMore ? nextKey?.visitId || '' : '',
        clearBefore,
        lastSyncAt: response.hasMore ? state.lastSyncAt : now,
        lastError: '',
        updatedAt: now,
      });
      return applied;
    });
  }

  async restartBootstrap(accountUid: string, clientId: string, now: number): Promise<void> {
    const state = await this.getState(accountUid, clientId);
    const database = await this.getDatabase();
    const transaction = database.transaction(STATE_STORE, 'readwrite');
    const done = transactionDone(transaction);
    writeState(transaction.objectStore(STATE_STORE), {
      ...state,
      initialized: false,
      cursor: 0,
      bootstrapHead: 0,
      bootstrapAfterUpdatedSeq: 0,
      bootstrapAfterVisitId: '',
      updatedAt: now,
    });
    await done;
  }

  async updateNativeReconcileTime(
    accountUid: string,
    clientId: string,
    reconciledAt: number,
    full: boolean,
  ): Promise<void> {
    const state = await this.getState(accountUid, clientId);
    const database = await this.getDatabase();
    const transaction = database.transaction(STATE_STORE, 'readwrite');
    const done = transactionDone(transaction);
    writeState(transaction.objectStore(STATE_STORE), {
      ...state,
      lastNativeReconcileAt: reconciledAt,
      lastFullNativeReconcileAt: full ? reconciledAt : state.lastFullNativeReconcileAt,
      updatedAt: reconciledAt,
    });
    await done;
  }

  async markSyncError(accountUid: string, clientId: string, message: string): Promise<void> {
    const state = await this.getState(accountUid, clientId);
    const database = await this.getDatabase();
    const transaction = database.transaction(STATE_STORE, 'readwrite');
    const done = transactionDone(transaction);
    writeState(transaction.objectStore(STATE_STORE), {
      ...state,
      lastError: message.slice(0, 500),
      updatedAt: Date.now(),
    });
    await done;
  }

  async deleteVisit(accountUid: string, clientId: string, visitId: string, now: number): Promise<boolean> {
    return this.withAccountTransaction('readwrite', async (stores) => {
      const stored = await requestResult<StoredVisit | undefined>(stores.visits.get(visitKey(accountUid, visitId)));
      if (!stored) return false;
      stores.visits.delete(stored.key);
      const ledgerRows = await readAccountRows<StoredNativeLedger>(stores.ledger, accountUid);
      markLedgerDeleted(stores.ledger, ledgerRows, (row) => row.visitId === visitId, now);
      putMutation(stores.outbox, accountUid, createDeleteVisitMutation(clientId, visitId, now), now);
      return true;
    });
  }

  async clearHistory(accountUid: string, clientId: string, now: number): Promise<number> {
    return this.recordNativeRemoval(accountUid, clientId, [], true, now);
  }

  async listTimeline(
    accountUid: string,
    options: { query?: string; deviceId?: string; offset?: number; limit?: number } = {},
  ): Promise<HistoryTimelinePage> {
    const database = await this.getDatabase();
    const transaction = database.transaction([VISITS_STORE, STATE_STORE], 'readonly');
    const done = transactionDone(transaction);
    const visits = await readAccountRows<StoredVisit>(transaction.objectStore(VISITS_STORE), accountUid);
    const states = await requestResult<StoredState[]>(transaction.objectStore(STATE_STORE).getAll());
    await done;

    const query = String(options.query || '').trim().toLocaleLowerCase();
    const deviceId = String(options.deviceId || '').trim();
    const filtered = visits.filter((visit) => {
      if (deviceId && visit.clientId !== deviceId) return false;
      if (!query) return true;
      return visit.title.toLocaleLowerCase().includes(query)
        || visit.url.toLocaleLowerCase().includes(query)
        || visit.deviceName.toLocaleLowerCase().includes(query);
    });
    filtered.sort((left, right) => right.visitedAt - left.visitedAt || right.visitId.localeCompare(left.visitId));
    const offset = Math.max(0, Math.floor(options.offset || 0));
    const limit = Math.min(500, Math.max(1, Math.floor(options.limit || 200)));
    const deviceNames = new Map<string, string>();
    visits.forEach((visit) => {
      if (!deviceNames.has(visit.clientId)) {
        deviceNames.set(visit.clientId, visit.deviceName || visit.clientId);
      }
    });
    const state = states
      .filter((item) => item.accountUid === accountUid)
      .sort((left, right) => right.updatedAt - left.updatedAt)[0];
    return {
      visits: filtered.slice(offset, offset + limit).map(stripStoredVisit),
      total: filtered.length,
      devices: Array.from(deviceNames, ([id, name]) => ({ id, name }))
        .sort((left, right) => left.name.localeCompare(right.name)),
      lastSyncAt: state?.lastSyncAt || 0,
      lastError: state?.lastError || '',
    };
  }

  async pruneProjection(accountUid: string, now: number): Promise<void> {
    const database = await this.getDatabase();
    const transaction = database.transaction(VISITS_STORE, 'readwrite');
    const done = transactionDone(transaction);
    const store = transaction.objectStore(VISITS_STORE);
    const visits = await readAccountRows<StoredVisit>(store, accountUid);
    const cutoff = now - HISTORY_SYNC_RETENTION_MS;
    visits.sort((left, right) => right.visitedAt - left.visitedAt || right.visitId.localeCompare(left.visitId));
    visits.forEach((visit, index) => {
      if (visit.visitedAt < cutoff || index >= HISTORY_SYNC_MAX_VISITS) {
        store.delete(visit.key);
      }
    });
    await done;
  }

  private async withAccountTransaction<T>(
    mode: IDBTransactionMode,
    operation: (stores: AccountStores) => Promise<T>,
  ): Promise<T> {
    const database = await this.getDatabase();
    const transaction = database.transaction(
      [VISITS_STORE, OUTBOX_STORE, STATE_STORE, LEDGER_STORE, RANGES_STORE],
      mode,
    );
    const done = transactionDone(transaction);
    try {
      const result = await operation({
        visits: transaction.objectStore(VISITS_STORE),
        outbox: transaction.objectStore(OUTBOX_STORE),
        state: transaction.objectStore(STATE_STORE),
        ledger: transaction.objectStore(LEDGER_STORE),
        ranges: transaction.objectStore(RANGES_STORE),
      });
      await done;
      return result;
    } catch (error) {
      try {
        transaction.abort();
      } catch {
        // The browser may already have aborted or completed the transaction.
      }
      try {
        await done;
      } catch {
      }
      throw error;
    }
  }

  private getDatabase(): Promise<IDBDatabase> {
    if (this.databasePromise) return this.databasePromise;
    this.databasePromise = new Promise((resolve, reject) => {
      const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
      request.onupgradeneeded = () => {
        const database = request.result;
        createAccountStore(database, VISITS_STORE);
        createAccountStore(database, OUTBOX_STORE);
        if (!database.objectStoreNames.contains(STATE_STORE)) {
          database.createObjectStore(STATE_STORE, { keyPath: 'key' });
        }
        createAccountStore(database, LEDGER_STORE);
        createAccountStore(database, RANGES_STORE);
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => {
        this.databasePromise = null;
        reject(request.error || new Error('Unable to open the Aira History database.'));
      };
      request.onblocked = () => {
        this.databasePromise = null;
        reject(new Error('The Aira History database upgrade is blocked.'));
      };
    });
    return this.databasePromise;
  }
}

function createAccountStore(database: IDBDatabase, name: string): void {
  if (database.objectStoreNames.contains(name)) return;
  const store = database.createObjectStore(name, { keyPath: 'key' });
  store.createIndex(ACCOUNT_INDEX, 'accountUid', { unique: false });
}

function requestResult<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error('IndexedDB request failed.'));
  });
}

function transactionDone(transaction: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error || new Error('IndexedDB transaction failed.'));
    transaction.onabort = () => reject(transaction.error || new Error('IndexedDB transaction was aborted.'));
  });
}

function readAccountRows<T>(store: IDBObjectStore, accountUid: string): Promise<T[]> {
  return requestResult(store.index(ACCOUNT_INDEX).getAll(accountUid)) as Promise<T[]>;
}

async function readStateFromStore(
  store: IDBObjectStore,
  accountUid: string,
  clientId: string,
): Promise<HistorySyncLocalState> {
  const stored = await requestResult<StoredState | undefined>(store.get(stateKey(accountUid, clientId)));
  return stored ? stripStoredState(stored) : createDefaultState(accountUid, clientId);
}

function writeState(store: IDBObjectStore, state: HistorySyncLocalState): void {
  store.put({ ...state, key: stateKey(state.accountUid, state.clientId) } satisfies StoredState);
}

function createDefaultState(accountUid: string, clientId: string): HistorySyncLocalState {
  return {
    accountUid,
    clientId,
    initialized: false,
    cursor: 0,
    bootstrapHead: 0,
    bootstrapAfterUpdatedSeq: 0,
    bootstrapAfterVisitId: '',
    clearBefore: 0,
    lastNativeReconcileAt: 0,
    lastFullNativeReconcileAt: 0,
    lastSyncAt: 0,
    lastError: '',
    updatedAt: 0,
  };
}

function stripStoredState(state: StoredState): HistorySyncLocalState {
  const { key: _key, ...plain } = state;
  return plain;
}

function stripStoredVisit(visit: StoredVisit): HistorySyncVisit {
  const { key: _key, accountUid: _accountUid, ...plain } = visit;
  return plain;
}

function toStoredVisit(accountUid: string, visit: HistorySyncVisit): StoredVisit {
  return { ...visit, key: visitKey(accountUid, visit.visitId), accountUid };
}

function toStoredRange(accountUid: string, range: HistorySyncDeleteRange): StoredDeleteRange {
  return { ...range, key: rangeKey(accountUid, range.rangeId), accountUid };
}

function toHistoryVisit(
  clientId: string,
  deviceName: string,
  draft: NativeHistoryVisitDraft,
): HistorySyncVisit {
  const nativeVisitId = encodeURIComponent(draft.nativeVisitId);
  const prefix = `h1:${clientId}:`;
  return {
    visitId: `${prefix}${nativeVisitId.slice(0, Math.max(1, 512 - prefix.length))}`,
    clientId,
    nativeVisitId,
    url: draft.url,
    title: draft.title.slice(0, 2048),
    visitedAt: draft.visitedAt,
    transition: draft.transition.slice(0, 64),
    referrer: '',
    deviceName: deviceName.slice(0, 128),
    source: 'airatab_native',
  };
}

function createUpsertMutation(clientId: string, visit: HistorySyncVisit, now: number): HistorySyncMutation {
  return {
    mutationId: createMutationId(clientId, now),
    kind: 'upsert_visit',
    visit,
  };
}

function createDeleteVisitMutation(clientId: string, visitId: string, now: number): HistorySyncMutation {
  return {
    mutationId: createMutationId(clientId, now),
    kind: 'delete_visit',
    visitId,
  };
}

function createClearMutation(clientId: string, clearBefore: number): HistorySyncMutation {
  return {
    mutationId: createMutationId(clientId, clearBefore),
    kind: 'clear_before',
    clearBefore,
  };
}

function createMutationId(clientId: string, now: number): string {
  const random = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `${now.toString(36)}_${Math.random().toString(36).slice(2)}`;
  return `h1m:${clientId}:${random}`;
}

function putMutation(
  store: IDBObjectStore,
  accountUid: string,
  mutation: HistorySyncMutation,
  createdAt: number,
): void {
  store.put({
    key: mutationKey(accountUid, mutation.mutationId),
    accountUid,
    createdAt,
    mutation,
  } satisfies StoredMutation);
}

async function applyRemoteChange(
  stores: AccountStores,
  accountUid: string,
  change: HistorySyncChange,
  currentClearBefore: number,
  ranges: StoredDeleteRange[],
  ledgerByVisitId: Map<string, StoredNativeLedger>,
  now: number,
): Promise<{ clearBefore: number; applied: number }> {
  if (change.kind === 'upsert_visit' && change.visit) {
    if (!isVisitBlocked(change.visit, currentClearBefore, ranges)) {
      stores.visits.put(toStoredVisit(accountUid, change.visit));
      return { clearBefore: currentClearBefore, applied: 1 };
    }
    return { clearBefore: currentClearBefore, applied: 0 };
  }
  if (change.kind === 'delete_visit' && change.visitId) {
    stores.visits.delete(visitKey(accountUid, change.visitId));
    const ledger = ledgerByVisitId.get(change.visitId);
    if (ledger && !ledger.deleted) {
      const deleted = { ...ledger, deleted: true, syncState: 'deleted' as const, updatedAt: now };
      stores.ledger.put(deleted);
      ledgerByVisitId.set(change.visitId, deleted);
    }
    return { clearBefore: currentClearBefore, applied: 1 };
  }
  if (change.kind === 'delete_range' && change.rangeId && change.url && change.startedAt && change.endedAt) {
    const range = toStoredRange(accountUid, {
      rangeId: change.rangeId,
      url: change.url,
      startedAt: change.startedAt,
      endedAt: change.endedAt,
      seq: change.seq,
    });
    stores.ranges.put(range);
    ranges.push(range);
    const applied = await applyRangeToAccount(stores, accountUid, range, ledgerByVisitId, now);
    return { clearBefore: currentClearBefore, applied: Math.max(1, applied) };
  }
  if (change.kind === 'clear_before' && change.clearBefore) {
    const nextClearBefore = Math.max(currentClearBefore, change.clearBefore);
    const applied = await applyClearToAccount(stores, accountUid, nextClearBefore, ledgerByVisitId, now);
    return { clearBefore: nextClearBefore, applied: Math.max(1, applied) };
  }
  if (change.kind === 'retention_prune') {
    for (const visitId of change.visitIds || []) {
      stores.visits.delete(visitKey(accountUid, visitId));
    }
    return { clearBefore: currentClearBefore, applied: (change.visitIds || []).length };
  }
  return { clearBefore: currentClearBefore, applied: 0 };
}

async function applyRangeToAccount(
  stores: AccountStores,
  accountUid: string,
  range: HistorySyncDeleteRange,
  ledgerByVisitId: Map<string, StoredNativeLedger>,
  now: number,
): Promise<number> {
  const visits = await readAccountRows<StoredVisit>(stores.visits, accountUid);
  let applied = 0;
  for (const visit of visits) {
    if (visit.url === range.url && visit.visitedAt >= range.startedAt && visit.visitedAt <= range.endedAt) {
      stores.visits.delete(visit.key);
      applied += 1;
    }
  }
  for (const ledger of ledgerByVisitId.values()) {
    if (
      !ledger.deleted
      && ledger.url === range.url
      && ledger.visitedAt >= range.startedAt
      && ledger.visitedAt <= range.endedAt
    ) {
      const deleted = { ...ledger, deleted: true, syncState: 'deleted' as const, updatedAt: now };
      stores.ledger.put(deleted);
      ledgerByVisitId.set(ledger.visitId, deleted);
    }
  }
  return applied;
}

async function applyClearToAccount(
  stores: AccountStores,
  accountUid: string,
  clearBefore: number,
  ledgerByVisitId: Map<string, StoredNativeLedger>,
  now: number,
): Promise<number> {
  if (clearBefore <= 0) return 0;
  const visits = await readAccountRows<StoredVisit>(stores.visits, accountUid);
  let applied = 0;
  for (const visit of visits) {
    if (visit.visitedAt <= clearBefore) {
      stores.visits.delete(visit.key);
      applied += 1;
    }
  }
  for (const ledger of ledgerByVisitId.values()) {
    if (!ledger.deleted && ledger.visitedAt <= clearBefore) {
      const deleted = { ...ledger, deleted: true, syncState: 'deleted' as const, updatedAt: now };
      stores.ledger.put(deleted);
      ledgerByVisitId.set(ledger.visitId, deleted);
    }
  }
  return applied;
}

function markLedgerDeleted(
  store: IDBObjectStore,
  rows: StoredNativeLedger[],
  predicate: (row: StoredNativeLedger) => boolean,
  now: number,
): void {
  rows.forEach((row) => {
    if (!row.deleted && predicate(row)) {
      store.put({
        ...row,
        deleted: true,
        syncState: 'deleted',
        updatedAt: now,
      } satisfies StoredNativeLedger);
    }
  });
}

function isVisitBlocked(
  visit: Pick<HistorySyncVisit, 'url' | 'visitedAt'>,
  clearBefore: number,
  ranges: HistorySyncDeleteRange[],
): boolean {
  if (visit.visitedAt <= clearBefore) return true;
  return ranges.some((range) => (
    range.url === visit.url
    && visit.visitedAt >= range.startedAt
    && visit.visitedAt <= range.endedAt
  ));
}

function normalizeHttpUrl(value: string): string {
  try {
    const url = new URL(value);
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.toString() : '';
  } catch {
    return '';
  }
}

function stateKey(accountUid: string, clientId: string): string {
  return `${accountUid}\u001f${clientId}`;
}

function visitKey(accountUid: string, visitId: string): string {
  return `${accountUid}\u001f${visitId}`;
}

function mutationKey(accountUid: string, mutationId: string): string {
  return `${accountUid}\u001f${mutationId}`;
}

function ledgerKey(accountUid: string, clientId: string, nativeVisitId: string): string {
  return `${accountUid}\u001f${clientId}\u001f${nativeVisitId}`;
}

function rangeKey(accountUid: string, rangeId: string): string {
  return `${accountUid}\u001f${rangeId}`;
}
