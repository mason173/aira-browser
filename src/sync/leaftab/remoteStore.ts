import type {
  LeafTabSyncCommitFile,
  LeafTabSyncHeadFile,
  LeafTabSyncSnapshot,
} from './schema';

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
  deviceId: string;
  parentCommitId?: string | null;
  createdAt?: string;
}

export interface LeafTabSyncWriteStateResult {
  head: LeafTabSyncHeadFile;
  commit: LeafTabSyncCommitFile;
}

export interface LeafTabSyncRemoteStore {
  readHead?(): Promise<LeafTabSyncRemoteHead>;
  readState(): Promise<LeafTabSyncRemoteState>;
  writeState(params: LeafTabSyncWriteStateParams): Promise<LeafTabSyncWriteStateResult>;
}
