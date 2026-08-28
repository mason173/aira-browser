import type { AiraDesktopAuthorizedSession } from '@/features/desktop-connection/AiraDesktopConnectionModule';
import {
  HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE,
  HISTORY_SYNC_EXCHANGE_BATCH_SIZE,
  type HistorySyncBootstrapResponse,
  type HistorySyncChange,
  type HistorySyncDeleteRange,
  type HistorySyncExchangeResponse,
  type HistorySyncMutation,
  type HistorySyncMutationAcknowledgement,
  type HistorySyncVisit,
} from './HistorySyncModels';

const AIRA_HISTORY_ENDPOINT = 'https://api.aira.cool/sync/v1/history';
const REQUEST_TIMEOUT_MS = 45_000;

type RemoteResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  acknowledgements?: unknown;
  changes?: unknown;
  nextCursor?: unknown;
  headCursor?: unknown;
  hasMore?: unknown;
  bootstrapHead?: unknown;
  visits?: unknown;
  deletedVisitIds?: unknown;
  clearBefore?: unknown;
  deleteRanges?: unknown;
  nextKey?: unknown;
};

export class AiraCloudHistoryRemoteError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, message: string, status = 0) {
    super(message);
    this.name = 'AiraCloudHistoryRemoteError';
    this.code = code;
    this.status = status;
  }
}

export class AiraCloudHistoryRemoteStore {
  constructor(
    private readonly session: AiraDesktopAuthorizedSession,
    private readonly endpoint = AIRA_HISTORY_ENDPOINT,
  ) {}

  async exchange(params: {
    cursor: number;
    mutations: HistorySyncMutation[];
  }): Promise<HistorySyncExchangeResponse> {
    const response = await this.post('/exchange', {
      uid: this.session.uid,
      desktopPushToken: this.session.deviceCredential,
      source: 'airatab_history_sync',
      clientId: this.session.deviceId,
      cursor: params.cursor,
      mutations: params.mutations.slice(0, HISTORY_SYNC_EXCHANGE_BATCH_SIZE),
      pullLimit: HISTORY_SYNC_EXCHANGE_BATCH_SIZE,
    });
    const acknowledgements = readArray(response.acknowledgements, parseAcknowledgement, 'acknowledgements');
    const changes = readArray(response.changes, parseChange, 'changes');
    return {
      acknowledgements,
      changes,
      nextCursor: readNonNegativeInteger(response.nextCursor, 'nextCursor'),
      headCursor: readNonNegativeInteger(response.headCursor, 'headCursor'),
      hasMore: response.hasMore === true,
    };
  }

  async bootstrap(params: {
    bootstrapHead?: number;
    afterUpdatedSeq?: number;
    afterVisitId?: string;
  }): Promise<HistorySyncBootstrapResponse> {
    const body: Record<string, unknown> = {
      uid: this.session.uid,
      desktopPushToken: this.session.deviceCredential,
      source: 'airatab_history_sync',
      clientId: this.session.deviceId,
      pageLimit: HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE,
    };
    if (params.bootstrapHead !== undefined) body.bootstrapHead = params.bootstrapHead;
    if (params.afterUpdatedSeq !== undefined && params.afterVisitId) {
      body.afterUpdatedSeq = params.afterUpdatedSeq;
      body.afterVisitId = params.afterVisitId;
    }
    const response = await this.post('/bootstrap', body);
    const nextKey = parseBootstrapKey(response.nextKey);
    const hasMore = response.hasMore === true;
    if (hasMore && !nextKey) {
      throw invalidResponse('nextKey');
    }
    return {
      bootstrapHead: readNonNegativeInteger(response.bootstrapHead, 'bootstrapHead'),
      headCursor: readNonNegativeInteger(response.headCursor, 'headCursor'),
      visits: readArray(response.visits, parseVisit, 'visits'),
      deletedVisitIds: readArray(response.deletedVisitIds, readVisitId, 'deletedVisitIds'),
      clearBefore: readNonNegativeInteger(response.clearBefore, 'clearBefore'),
      deleteRanges: readArray(response.deleteRanges, parseDeleteRange, 'deleteRanges'),
      nextKey: nextKey || undefined,
      hasMore,
    };
  }

  private async post(path: string, body: unknown): Promise<RemoteResponse> {
    const controller = new AbortController();
    const timeout = globalThis.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const response = await fetch(`${this.endpoint}${path}`, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      const text = await response.text();
      let parsed: RemoteResponse;
      try {
        parsed = text ? JSON.parse(text) as RemoteResponse : {};
      } catch {
        throw new AiraCloudHistoryRemoteError(
          'invalid_response',
          `Aira History returned invalid data (${response.status}).`,
          response.status,
        );
      }
      if (!response.ok || parsed.ok !== true) {
        throw new AiraCloudHistoryRemoteError(
          String(parsed.code || (response.ok ? 'remote_rejected' : 'http_error')),
          String(parsed.message || `Aira History request failed (${response.status}).`),
          response.status,
        );
      }
      return parsed;
    } catch (error) {
      if (error instanceof AiraCloudHistoryRemoteError) throw error;
      throw new AiraCloudHistoryRemoteError(
        'network_unavailable',
        String((error as Error)?.message || 'Aira History is temporarily unavailable.'),
      );
    } finally {
      globalThis.clearTimeout(timeout);
    }
  }
}

function parseAcknowledgement(value: unknown): HistorySyncMutationAcknowledgement {
  const record = readRecord(value, 'acknowledgement');
  return {
    mutationId: readRequiredString(record.mutationId, 'mutationId'),
    acceptedSeq: readNonNegativeInteger(record.acceptedSeq, 'acceptedSeq'),
    applied: record.applied === true,
  };
}

function parseChange(value: unknown): HistorySyncChange {
  const record = readRecord(value, 'change');
  const kind = readRequiredString(record.kind, 'change.kind');
  if (!['upsert_visit', 'delete_visit', 'delete_range', 'clear_before', 'retention_prune'].includes(kind)) {
    throw invalidResponse('change.kind');
  }
  return {
    seq: readNonNegativeInteger(record.seq, 'change.seq'),
    kind: kind as HistorySyncChange['kind'],
    visitId: typeof record.visitId === 'string' ? record.visitId : '',
    visit: record.visit === undefined ? undefined : parseVisit(record.visit),
    rangeId: optionalString(record.rangeId),
    url: optionalString(record.url),
    startedAt: optionalInteger(record.startedAt),
    endedAt: optionalInteger(record.endedAt),
    clearBefore: optionalInteger(record.clearBefore),
    visitIds: record.visitIds === undefined
      ? undefined
      : readArray(record.visitIds, readVisitId, 'change.visitIds'),
    cutoff: optionalInteger(record.cutoff),
  };
}

function parseVisit(value: unknown): HistorySyncVisit {
  const record = readRecord(value, 'visit');
  const url = readRequiredString(record.url, 'visit.url');
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') throw new Error('unsupported');
  } catch {
    throw invalidResponse('visit.url');
  }
  return {
    visitId: readVisitId(record.visitId),
    clientId: readRequiredString(record.clientId, 'visit.clientId'),
    nativeVisitId: readRequiredString(record.nativeVisitId, 'visit.nativeVisitId'),
    url,
    title: optionalString(record.title) || '',
    visitedAt: readPositiveInteger(record.visitedAt, 'visit.visitedAt'),
    transition: optionalString(record.transition) || '',
    referrer: optionalString(record.referrer) || '',
    deviceName: optionalString(record.deviceName) || '',
    source: optionalString(record.source) || '',
  };
}

function parseDeleteRange(value: unknown): HistorySyncDeleteRange {
  const record = readRecord(value, 'deleteRange');
  return {
    rangeId: readRequiredString(record.rangeId, 'rangeId'),
    url: readRequiredString(record.url, 'range.url'),
    startedAt: readPositiveInteger(record.startedAt, 'range.startedAt'),
    endedAt: readPositiveInteger(record.endedAt, 'range.endedAt'),
    seq: readNonNegativeInteger(record.seq, 'range.seq'),
  };
}

function parseBootstrapKey(value: unknown): { updatedSeq: number; visitId: string } | null {
  if (value === null || value === undefined) return null;
  const record = readRecord(value, 'nextKey');
  return {
    updatedSeq: readPositiveInteger(record.updatedSeq, 'nextKey.updatedSeq'),
    visitId: readVisitId(record.visitId),
  };
}

function readArray<T>(
  value: unknown,
  mapper: (item: unknown) => T,
  field: string,
): T[] {
  if (!Array.isArray(value)) throw invalidResponse(field);
  return value.map(mapper);
}

function readRecord(value: unknown, field: string): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw invalidResponse(field);
  return value as Record<string, unknown>;
}

function readVisitId(value: unknown): string {
  const visitId = readRequiredString(value, 'visitId');
  if (!visitId.startsWith('h1:')) throw invalidResponse('visitId');
  return visitId;
}

function readRequiredString(value: unknown, field: string): string {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text) throw invalidResponse(field);
  return text;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

function optionalInteger(value: unknown): number | undefined {
  return value === undefined ? undefined : readNonNegativeInteger(value, 'integer');
}

function readPositiveInteger(value: unknown, field: string): number {
  const number = readNonNegativeInteger(value, field);
  if (number <= 0) throw invalidResponse(field);
  return number;
}

function readNonNegativeInteger(value: unknown, field: string): number {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0) throw invalidResponse(field);
  return number;
}

function invalidResponse(field: string): AiraCloudHistoryRemoteError {
  return new AiraCloudHistoryRemoteError(
    'invalid_history_response',
    `Aira History response field is invalid: ${field}.`,
  );
}
