import {
  createLeafTabSyncCommitFile,
  createLeafTabSyncHeadFile,
  type LeafTabSyncBookmarkFolderEntity,
  type LeafTabSyncBookmarkItemEntity,
  type LeafTabSyncBookmarkOrder,
  type LeafTabSyncBookmarkDataSet,
  type LeafTabSyncCommitFile,
  type LeafTabSyncHeadFile,
  type LeafTabSyncSnapshot,
  type LeafTabSyncTombstone,
} from './schema';
import type {
  LeafTabSyncRemoteHead,
  LeafTabSyncRemoteState,
  LeafTabSyncRemoteStore,
  LeafTabSyncReadOperationsParams,
  LeafTabSyncReadOperationsResult,
  LeafTabSyncOperation,
  LeafTabSyncWriteOperationsParams,
  LeafTabSyncWriteOperationsResult,
  LeafTabSyncWriteStateParams,
  LeafTabSyncWriteStateResult,
} from './remoteStore';

const AIRA_CLOUD_SYNC_ENDPOINT = 'https://api.aira.cool/sync/huawei';
const AIRA_CLOUD_REQUEST_TIMEOUT_MS = 60_000;
const AIRA_CLOUD_LARGE_REQUEST_TIMEOUT_MS = 600_000;

type AiraCloudSnapshot = {
  meta?: LeafTabSyncSnapshot['meta'];
  bookmarkFolders?: LeafTabSyncBookmarkFolderEntity[];
  bookmarkItems?: LeafTabSyncBookmarkItemEntity[];
  bookmarkOrders?: LeafTabSyncBookmarkOrder[];
  tombstones?: LeafTabSyncTombstone[];
  appPrivateBookmarks?: LeafTabSyncBookmarkDataSet;
};

type AiraCloudResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  snapshot?: AiraCloudSnapshot | null;
  commitId?: string | null;
  updatedAt?: number;
  bookmarkFolders?: number;
  bookmarkItems?: number;
  tombstones?: number;
  writtenAt?: string;
  operations?: LeafTabSyncOperation[];
  supportsIncremental?: boolean;
  reason?: string;
  sinceCommitId?: string;
  deviceId?: string;
  createdAt?: string;
  appliedOperationCount?: number;
};

const objectValues = <T>(record: Record<string, T> | null | undefined): T[] => {
  return Object.values(record || {});
};

const normalizeCount = (value: unknown) => {
  const count = Number(value);
  return Number.isFinite(count) && count >= 0 ? Math.floor(count) : 0;
};

const recordById = <T extends { id: string }>(items: T[] | null | undefined): Record<string, T> => {
  return Object.fromEntries((items || []).map((item) => [item.id, item]));
};

const orderRecordByParent = (
  orders: LeafTabSyncBookmarkOrder[] | null | undefined,
): Record<string, LeafTabSyncBookmarkOrder> => {
  return Object.fromEntries((orders || []).map((order) => [order.parentId || '__root__', order]));
};

const toCloudSnapshot = (snapshot: LeafTabSyncSnapshot): AiraCloudSnapshot => ({
  meta: snapshot.meta,
  bookmarkFolders: objectValues(snapshot.bookmarkFolders),
  bookmarkItems: objectValues(snapshot.bookmarkItems),
  bookmarkOrders: objectValues(snapshot.bookmarkOrders),
  tombstones: objectValues(snapshot.tombstones),
  appPrivateBookmarks: snapshot.appPrivateBookmarks,
});

const fromCloudSnapshot = (snapshot: AiraCloudSnapshot | null | undefined): LeafTabSyncSnapshot | null => {
  if (!snapshot?.meta) return null;
  return {
    meta: {
      version: 2,
      deviceId: String(snapshot.meta.deviceId || 'aira-cloud'),
      generatedAt: String(snapshot.meta.generatedAt || new Date(0).toISOString()),
    },
    bookmarkFolders: recordById(snapshot.bookmarkFolders),
    bookmarkItems: recordById(snapshot.bookmarkItems),
    bookmarkOrders: orderRecordByParent(snapshot.bookmarkOrders),
    tombstones: recordById(snapshot.tombstones),
    appPrivateBookmarks: snapshot.appPrivateBookmarks,
  };
};

const createCommitFromSnapshot = (
  commitId: string,
  snapshot: LeafTabSyncSnapshot,
  parentCommitId: string | null,
): LeafTabSyncCommitFile => {
  const commit = createLeafTabSyncCommitFile({
    deviceId: snapshot.meta.deviceId,
    createdAt: snapshot.meta.generatedAt,
    parentCommitId,
    snapshot,
  });
  return {
    ...commit,
    id: commitId,
    parentCommitId,
  };
};

const createHead = (commitId: string | null, updatedAt?: number | string): LeafTabSyncHeadFile | null => {
  if (!commitId) return null;
  const updatedAtIso = typeof updatedAt === 'number'
    ? new Date(updatedAt).toISOString()
    : String(updatedAt || new Date().toISOString());
  return createLeafTabSyncHeadFile(commitId, updatedAtIso);
};

export class LeafTabSyncAiraCloudStore implements LeafTabSyncRemoteStore {
  private readonly uid: string;
  private readonly endpoint: string;

  constructor(uid: string, endpoint = AIRA_CLOUD_SYNC_ENDPOINT) {
    this.uid = uid.trim();
    this.endpoint = endpoint.trim().replace(/\/+$/, '');
  }

  async acquireLock() {
    return null;
  }

  async releaseLock() {}

  async readCommitId(): Promise<string | null> {
    const head = await this.readHead();
    return head.commitId;
  }

  async readHead(): Promise<LeafTabSyncRemoteHead> {
    this.assertConfigured();
    const response = await this.post('/head', {
      uid: this.uid,
      source: 'airatab',
    });
    const commitId = typeof response.commitId === 'string' && response.commitId.trim()
      ? response.commitId.trim()
      : null;
    const head = createHead(commitId, response.updatedAt);
    return {
      head,
      commit: null,
      commitId,
      updatedAt: typeof response.updatedAt === 'number' ? response.updatedAt : 0,
      summary: {
        bookmarkFolders: normalizeCount(response.bookmarkFolders),
        bookmarkItems: normalizeCount(response.bookmarkItems),
        tombstones: normalizeCount(response.tombstones),
      },
    };
  }

  async readOperations(params: LeafTabSyncReadOperationsParams): Promise<LeafTabSyncReadOperationsResult> {
    this.assertConfigured();
    const response = await this.post('/read-ops', {
      uid: this.uid,
      source: 'airatab',
      sinceCommitId: params.sinceCommitId,
    });
    return {
      commitId: typeof response.commitId === 'string' && response.commitId.trim()
        ? response.commitId.trim()
        : null,
      sinceCommitId: typeof response.sinceCommitId === 'string' && response.sinceCommitId.trim()
        ? response.sinceCommitId.trim()
        : params.sinceCommitId,
      deviceId: typeof response.deviceId === 'string' ? response.deviceId.trim() : '',
      createdAt: typeof response.createdAt === 'string' ? response.createdAt.trim() : '',
      operations: Array.isArray(response.operations) ? response.operations : [],
      supportsIncremental: response.supportsIncremental === true,
      reason: typeof response.reason === 'string' ? response.reason : undefined,
    };
  }

  async readState(): Promise<LeafTabSyncRemoteState> {
    this.assertConfigured();
    const response = await this.post('/read', {
      uid: this.uid,
      source: 'airatab',
    }, AIRA_CLOUD_LARGE_REQUEST_TIMEOUT_MS);
    const snapshot = fromCloudSnapshot(response.snapshot);
    const commitId = typeof response.commitId === 'string' && response.commitId.trim()
      ? response.commitId.trim()
      : null;
    const head = createHead(commitId);
    const commit = commitId && snapshot
      ? createCommitFromSnapshot(commitId, snapshot, null)
      : null;
    return {
      head,
      commit,
      snapshot,
    };
  }

  async writeState(params: LeafTabSyncWriteStateParams): Promise<LeafTabSyncWriteStateResult> {
    this.assertConfigured();
    const response = await this.post('/write', {
      uid: this.uid,
      source: 'airatab',
      deviceId: params.deviceId,
      parentCommitId: params.parentCommitId ?? null,
      createdAt: params.createdAt ?? params.snapshot.meta.generatedAt,
      snapshot: toCloudSnapshot(params.snapshot),
    }, AIRA_CLOUD_LARGE_REQUEST_TIMEOUT_MS);
    const commitId = typeof response.commitId === 'string' && response.commitId.trim()
      ? response.commitId.trim()
      : '';
    if (!commitId) {
      throw new Error('Aira 云同步服务没有返回 commitId。');
    }
    const writtenAt = response.writtenAt || params.createdAt || params.snapshot.meta.generatedAt;
    return {
      head: createLeafTabSyncHeadFile(commitId, writtenAt),
      commit: createCommitFromSnapshot(commitId, params.snapshot, params.parentCommitId ?? null),
    };
  }

  async writeOperations(params: LeafTabSyncWriteOperationsParams): Promise<LeafTabSyncWriteOperationsResult> {
    this.assertConfigured();
    if (params.operations.length <= 0) {
      throw new Error('没有可上传的书签变更。');
    }
    const response = await this.post('/write-ops', {
      uid: this.uid,
      source: 'airatab',
      deviceId: params.deviceId,
      parentCommitId: params.parentCommitId,
      createdAt: params.createdAt ?? params.snapshot.meta.generatedAt,
      operations: params.operations,
    }, AIRA_CLOUD_LARGE_REQUEST_TIMEOUT_MS);
    const commitId = typeof response.commitId === 'string' && response.commitId.trim()
      ? response.commitId.trim()
      : '';
    if (!commitId) {
      throw new Error('Aira 云同步服务没有返回 commitId。');
    }
    const writtenAt = response.writtenAt || params.createdAt || params.snapshot.meta.generatedAt;
    return {
      head: createLeafTabSyncHeadFile(commitId, writtenAt),
      commit: createCommitFromSnapshot(commitId, params.snapshot, params.parentCommitId),
      appliedOperationCount: normalizeCount(response.appliedOperationCount),
    };
  }

  private assertConfigured() {
    if (!this.uid) {
      throw new Error('请先扫码登录 Aira 账号。');
    }
  }

  private async post(path: string, body: unknown, timeoutMs = AIRA_CLOUD_REQUEST_TIMEOUT_MS): Promise<AiraCloudResponse> {
    const controller = new AbortController();
    const timeout = globalThis.setTimeout(() => controller.abort(), timeoutMs);
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
      const parsed = text ? JSON.parse(text) as AiraCloudResponse : {};
      if (!response.ok || parsed.ok !== true) {
        throw new Error(parsed.message || `Aira 云同步请求失败（${response.status}）。`);
      }
      return parsed;
    } finally {
      globalThis.clearTimeout(timeout);
    }
  }
}
