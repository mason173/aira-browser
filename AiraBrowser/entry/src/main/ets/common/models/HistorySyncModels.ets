import { BrowserHistoryTransition } from './BrowserModels';

export const HISTORY_SYNC_EXCHANGE_BATCH_SIZE: number = 200;
export const HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE: number = 500;
export const HISTORY_SYNC_RETENTION_MS: number = 90 * 24 * 60 * 60 * 1000;
export const HISTORY_SYNC_MAX_VISITS: number = 10000;

export type HistorySyncProviderKind = 'aira_cloud' | 'huawei_space' | 'self_hosted';

export type HistorySyncMutationOrigin =
  'local_capture' |
  'user_deletion' |
  'retention' |
  'migration';

export type HistorySyncMutationKind =
  'upsert_visit' |
  'delete_visit' |
  'delete_range' |
  'clear_before';

export type HistorySyncChangeKind = HistorySyncMutationKind | 'retention_prune';

export interface HistorySyncVisit {
  visitId: string;
  clientId: string;
  nativeVisitId: string;
  url: string;
  title: string;
  visitedAt: number;
  transition: BrowserHistoryTransition;
  referrer: string;
  deviceName: string;
  source: string;
}

export interface HistorySyncMutation {
  mutationId: string;
  kind: HistorySyncMutationKind;
  visit?: HistorySyncVisit;
  visitId?: string;
  url?: string;
  startedAt?: number;
  endedAt?: number;
  clearBefore?: number;
}

export interface HistorySyncOutboxContext {
  accountUid: string;
  clientId: string;
  deviceName: string;
  origin: HistorySyncMutationOrigin;
}

export interface HistorySyncLocalState {
  accountUid: string;
  clientId: string;
  initialized: boolean;
  cursor: number;
  bootstrapHead: number;
  bootstrapAfterUpdatedSeq: number;
  bootstrapAfterVisitId: string;
  updatedAt: number;
}

export interface HistorySyncMutationAcknowledgement {
  mutationId: string;
  acceptedSeq: number;
  applied: boolean;
}

export interface HistorySyncDeleteRange {
  rangeId: string;
  url: string;
  startedAt: number;
  endedAt: number;
  seq: number;
}

export interface HistorySyncExactTombstone {
  visitId: string;
  deletedAt: number;
}

export interface HistorySyncRetentionFrontier {
  cutoffAt: number;
  boundaryVisitedAt: number;
  boundaryVisitId: string;
  updatedAt: number;
}

export interface HuaweiSpaceHistorySyncState {
  visits: HistorySyncVisit[];
  tombstones: HistorySyncExactTombstone[];
  deleteRanges: HistorySyncDeleteRange[];
  clearBefore: number;
  retentionFrontier: HistorySyncRetentionFrontier;
}

export interface HistorySyncChange {
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
}

export interface HistorySyncExchangeResponse {
  acknowledgements: HistorySyncMutationAcknowledgement[];
  changes: HistorySyncChange[];
  nextCursor: number;
  headCursor: number;
  hasMore: boolean;
}

export interface HistorySyncBootstrapResponse {
  bootstrapHead: number;
  headCursor: number;
  visits: HistorySyncVisit[];
  deletedVisitIds: string[];
  clearBefore: number;
  deleteRanges: HistorySyncDeleteRange[];
  nextKey?: HistorySyncBootstrapKey;
  hasMore: boolean;
}

export interface HistorySyncBootstrapKey {
  updatedSeq: number;
  visitId: string;
}

export interface HistorySyncRunResult {
  ok: boolean;
  appliedChangeCount: number;
  uploadedMutationCount: number;
  message: string;
}
