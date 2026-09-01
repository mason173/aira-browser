import {
  parseCanonicalLeafTabSyncWireSnapshot,
  toLeafTabSyncWireSnapshot,
  validateCanonicalLeafTabSyncSnapshot,
  type LeafTabSyncHistoryDescriptor,
  type LeafTabSyncWireSnapshot,
} from './schema';
import type {
  LeafTabSyncRemoteHead,
  LeafTabSyncRemoteState,
  LeafTabSyncRemoteStore,
  LeafTabSyncWriteStateParams,
  LeafTabSyncWriteStateResult,
} from './remoteStore';
import { LeafTabSyncTombstoneLifecycle } from './historyLifecycle';
import {
  PersonalServerRemoteError,
  postPersonalServerJson,
  type PersonalServerConnection,
} from '@/features/personal-server/PersonalServerConnection';

const LARGE_REQUEST_TIMEOUT_MS = 600_000;

type PersonalServerBookmarkResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  snapshot?: Partial<LeafTabSyncWireSnapshot> | null;
  history?: LeafTabSyncHistoryDescriptor | null;
  commitId?: string | null;
  updatedAt?: number;
  bookmarkFolders?: number;
  bookmarkItems?: number;
  tombstones?: number;
  writtenAt?: string;
};

export class LeafTabSyncPersonalServerStore implements LeafTabSyncRemoteStore {
  private readonly historyLifecycle = new LeafTabSyncTombstoneLifecycle();

  constructor(private readonly connection: PersonalServerConnection) {}

  async readHead(): Promise<LeafTabSyncRemoteHead> {
    const response = await this.post('/head', {});
    return {
      commitId: normalizeCommitId(response.commitId),
      updatedAt: Number(response.updatedAt || 0),
      summary: {
        bookmarkFolders: normalizeCount(response.bookmarkFolders),
        bookmarkItems: normalizeCount(response.bookmarkItems),
        tombstones: normalizeCount(response.tombstones),
      },
    };
  }

  async readState(): Promise<LeafTabSyncRemoteState> {
    const response = await this.post('/read', {});
    const snapshot = response.snapshot == null
      ? null
      : parseCanonicalLeafTabSyncWireSnapshot(response.snapshot);
    if (response.snapshot != null && !snapshot) {
      throw new PersonalServerRemoteError('invalid_snapshot', '个人服务器书签快照格式无效。');
    }
    const history = response.history == null
      ? null
      : this.historyLifecycle.validateHistory(response.history);
    const commitId = normalizeCommitId(response.commitId);
    if (Boolean(snapshot) !== Boolean(commitId) || Boolean(snapshot) !== Boolean(history)) {
      throw new PersonalServerRemoteError('invalid_snapshot', '个人服务器书签同步状态不完整。');
    }
    if (snapshot && history) {
      this.historyLifecycle.assertSnapshotWithinHistory(snapshot, history, '个人服务器');
    }
    return { snapshot, history, commitId };
  }

  async writeState(params: LeafTabSyncWriteStateParams): Promise<LeafTabSyncWriteStateResult> {
    const snapshot = validateCanonicalLeafTabSyncSnapshot(params.snapshot, '个人服务器');
    const history = this.historyLifecycle.validateHistory(params.history);
    this.historyLifecycle.assertSnapshotWithinHistory(snapshot, history, '个人服务器');
    const response = await this.post('/write', {
      deviceId: params.deviceId,
      parentCommitId: params.parentCommitId ?? null,
      createdAt: params.createdAt ?? snapshot.meta.generatedAt,
      history,
      snapshot: toLeafTabSyncWireSnapshot(snapshot),
    });
    const commitId = normalizeCommitId(response.commitId);
    if (!commitId) {
      throw new PersonalServerRemoteError('invalid_response', '个人服务器没有返回书签 commitId。');
    }
    return {
      commitId,
      writtenAt: String(response.writtenAt || params.createdAt || snapshot.meta.generatedAt),
    };
  }

  private post(path: string, body: unknown): Promise<PersonalServerBookmarkResponse> {
    return postPersonalServerJson<PersonalServerBookmarkResponse>(
      `/v1/sync/bookmarks${path}`,
      body,
      LARGE_REQUEST_TIMEOUT_MS,
      this.connection,
    );
  }
}

function normalizeCommitId(value: unknown): string | null {
  const commitId = String(value || '').trim();
  return commitId || null;
}

function normalizeCount(value: unknown): number {
  const count = Number(value);
  return Number.isFinite(count) && count >= 0 ? Math.floor(count) : 0;
}
