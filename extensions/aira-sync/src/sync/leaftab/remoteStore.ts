import type { LeafTabSyncHistoryDescriptor, LeafTabSyncSnapshot } from './schema';

export const AIRA_CLOUD_BOOKMARK_SYNC_PROTOCOL = 'aira-cloud-bookmarks-v4' as const;

export interface LeafTabSyncRemoteState {
  snapshot: LeafTabSyncSnapshot | null;
  commitId: string | null;
  history: LeafTabSyncHistoryDescriptor | null;
}

export interface LeafTabSyncRemoteHead {
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
  history: LeafTabSyncHistoryDescriptor;
  deviceId: string;
  parentCommitId?: string | null;
  createdAt?: string;
}

export interface LeafTabSyncWriteStateResult {
  commitId: string;
  writtenAt: string;
}

export interface LeafTabSyncRemoteStore {
  readHead?(): Promise<LeafTabSyncRemoteHead>;
  readState(): Promise<LeafTabSyncRemoteState>;
  writeState(params: LeafTabSyncWriteStateParams): Promise<LeafTabSyncWriteStateResult>;
}
