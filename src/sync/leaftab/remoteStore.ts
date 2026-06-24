import type {
  LeafTabSyncCommitFile,
  LeafTabSyncEntityType,
  LeafTabSyncHeadFile,
  LeafTabSyncSnapshot,
} from './schema';

export type LeafTabSyncOperationKind =
  | 'upsert_folder'
  | 'upsert_item'
  | 'upsert_order'
  | 'delete_entity';

export interface LeafTabSyncOperation {
  id: string;
  kind: LeafTabSyncOperationKind;
  entityId: string;
  entityType?: LeafTabSyncEntityType;
  parentId?: string | null;
  title?: string;
  url?: string;
  ids?: string[];
  createdAt?: string;
  updatedAt: string;
  updatedBy: string;
  revision: number;
  lastKnownRevision?: number;
}

export interface LeafTabSyncRemoteState {
  head: LeafTabSyncHeadFile | null;
  commit: LeafTabSyncCommitFile | null;
  snapshot: LeafTabSyncSnapshot | null;
}

export interface LeafTabSyncRemoteHead {
  head: LeafTabSyncHeadFile | null;
  commit: LeafTabSyncCommitFile | null;
  commitId: string | null;
  updatedAt: number;
  summary?: {
    bookmarkFolders: number;
    bookmarkItems: number;
    tombstones: number;
  };
}

export interface LeafTabSyncWriteStateParams {
  snapshot: LeafTabSyncSnapshot;
  previousSnapshot?: LeafTabSyncSnapshot | null;
  previousFiles?: unknown[];
  deviceId: string;
  parentCommitId?: string | null;
  createdAt?: string;
}

export interface LeafTabSyncWriteStateResult {
  head: LeafTabSyncHeadFile;
  commit: LeafTabSyncCommitFile;
}

export interface LeafTabSyncReadOperationsParams {
  sinceCommitId: string;
}

export interface LeafTabSyncReadOperationsResult {
  commitId: string | null;
  sinceCommitId: string;
  deviceId: string;
  createdAt: string;
  operations: LeafTabSyncOperation[];
  supportsIncremental: boolean;
  reason?: string;
}

export interface LeafTabSyncWriteOperationsParams {
  snapshot: LeafTabSyncSnapshot;
  operations: LeafTabSyncOperation[];
  previousSnapshot?: LeafTabSyncSnapshot | null;
  previousFiles?: unknown[];
  deviceId: string;
  parentCommitId: string;
  createdAt?: string;
}

export interface LeafTabSyncWriteOperationsResult extends LeafTabSyncWriteStateResult {
  appliedOperationCount: number;
}

export interface LeafTabSyncRemoteStore {
  acquireLock(deviceId: string, ttlMs?: number): Promise<unknown>;
  releaseLock(): Promise<void>;
  readHead?(): Promise<LeafTabSyncRemoteHead>;
  readCommitId?(): Promise<string | null>;
  readOperations?(params: LeafTabSyncReadOperationsParams): Promise<LeafTabSyncReadOperationsResult>;
  readState(): Promise<LeafTabSyncRemoteState>;
  writeState(params: LeafTabSyncWriteStateParams): Promise<LeafTabSyncWriteStateResult>;
  writeOperations?(params: LeafTabSyncWriteOperationsParams): Promise<LeafTabSyncWriteOperationsResult>;
}
