import {
  parseCanonicalLeafTabSyncWireSnapshot,
  toLeafTabSyncWireSnapshot,
  validateCanonicalLeafTabSyncSnapshot,
  type LeafTabSyncHistoryDescriptor,
  type LeafTabSyncSnapshot,
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
import { requireAiratabOfficialApiRoute } from '@/config/AiratabDistribution';
import { getExtensionManifest } from '@/platform/runtime';

const AIRA_CLOUD_REQUEST_TIMEOUT_MS = 60_000;
const AIRA_CLOUD_LARGE_REQUEST_TIMEOUT_MS = 600_000;

type AiraCloudSnapshot = Partial<LeafTabSyncWireSnapshot>;

type AiraCloudResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  snapshot?: AiraCloudSnapshot | null;
  history?: LeafTabSyncHistoryDescriptor | null;
  commitId?: string | null;
  updatedAt?: number;
  bookmarkFolders?: number;
  bookmarkItems?: number;
  tombstones?: number;
  writtenAt?: string;
};

const normalizeCount = (value: unknown) => {
  const count = Number(value);
  return Number.isFinite(count) && count >= 0 ? Math.floor(count) : 0;
};

const toCloudSnapshot = (snapshot: LeafTabSyncSnapshot): AiraCloudSnapshot => toLeafTabSyncWireSnapshot(snapshot);

const fromCloudSnapshot = (snapshot: AiraCloudSnapshot | null | undefined): LeafTabSyncSnapshot | null => {
  if (snapshot === null || snapshot === undefined) return null;
  const parsed = parseCanonicalLeafTabSyncWireSnapshot(snapshot);
  if (!parsed) {
    throw new LeafTabSyncAiraCloudError('Aira 云书签同步快照格式无效。', 'invalid_snapshot');
  }
  return parsed;
};

export class LeafTabSyncAiraCloudError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(message: string, code = '', status = 0) {
    super(message);
    this.name = 'LeafTabSyncAiraCloudError';
    this.code = code;
    this.status = status;
  }
}

export class LeafTabSyncAiraCloudStore implements LeafTabSyncRemoteStore {
  private readonly uid: string;
  private readonly deviceCredential: string;
  private readonly endpoint: string;
  private readonly clientVersion: string;
  private readonly historyLifecycle = new LeafTabSyncTombstoneLifecycle();

  constructor(
    uid: string,
    deviceCredential: string,
    endpoint = '',
    clientVersion = getExtensionManifest()?.version ?? '',
  ) {
    this.uid = uid.trim();
    this.deviceCredential = deviceCredential.trim();
    this.endpoint = (endpoint.trim() || requireAiratabOfficialApiRoute('bookmarkSync')).replace(/\/+$/, '');
    this.clientVersion = clientVersion.trim();
  }

  async readHead(): Promise<LeafTabSyncRemoteHead> {
    this.assertConfigured();
    const response = await this.post('/head', {
      uid: this.uid,
      desktopPushToken: this.deviceCredential,
      source: 'airatab',
      clientVersion: this.clientVersion,
    });
    const commitId = typeof response.commitId === 'string' && response.commitId.trim()
      ? response.commitId.trim()
      : null;
    return {
      commitId,
      updatedAt: typeof response.updatedAt === 'number' ? response.updatedAt : 0,
      summary: {
        bookmarkFolders: normalizeCount(response.bookmarkFolders),
        bookmarkItems: normalizeCount(response.bookmarkItems),
        tombstones: normalizeCount(response.tombstones),
      },
    };
  }

  async readState(): Promise<LeafTabSyncRemoteState> {
    this.assertConfigured();
    const response = await this.post('/read', {
      uid: this.uid,
      desktopPushToken: this.deviceCredential,
      source: 'airatab',
      clientVersion: this.clientVersion,
    }, AIRA_CLOUD_LARGE_REQUEST_TIMEOUT_MS);
    const snapshot = fromCloudSnapshot(response.snapshot);
    const history = response.history === null || response.history === undefined
      ? null
      : this.historyLifecycle.validateHistory(response.history);
    const commitId = typeof response.commitId === 'string' && response.commitId.trim()
      ? response.commitId.trim()
      : null;
    if (Boolean(snapshot) !== Boolean(commitId) || Boolean(snapshot) !== Boolean(history)) {
      throw new LeafTabSyncAiraCloudError('Aira 云书签同步状态不完整。', 'invalid_snapshot');
    }
    if (snapshot && history) {
      this.historyLifecycle.assertSnapshotWithinHistory(snapshot, history, 'Aira 云');
    }
    return {
      snapshot,
      commitId,
      history,
    };
  }

  async writeState(params: LeafTabSyncWriteStateParams): Promise<LeafTabSyncWriteStateResult> {
    this.assertConfigured();
    const snapshot = validateCanonicalLeafTabSyncSnapshot(params.snapshot, 'Aira 云');
    const history = this.historyLifecycle.validateHistory(params.history);
    this.historyLifecycle.assertSnapshotWithinHistory(snapshot, history, 'Aira 云');
    const response = await this.post('/write', {
      uid: this.uid,
      desktopPushToken: this.deviceCredential,
      source: 'airatab',
      clientVersion: this.clientVersion,
      deviceId: params.deviceId,
      parentCommitId: params.parentCommitId ?? null,
      createdAt: params.createdAt ?? snapshot.meta.generatedAt,
      history,
      snapshot: toCloudSnapshot(snapshot),
    }, AIRA_CLOUD_LARGE_REQUEST_TIMEOUT_MS);
    const commitId = typeof response.commitId === 'string' && response.commitId.trim()
      ? response.commitId.trim()
      : '';
    if (!commitId) {
      throw new Error('Aira 云同步服务没有返回 commitId。');
    }
    const writtenAt = response.writtenAt || params.createdAt || snapshot.meta.generatedAt;
    return {
      commitId,
      writtenAt,
    };
  }

  private assertConfigured() {
    if (!this.uid) {
      throw new Error('请先扫码登录 Aira 账号。');
    }
    if (!this.deviceCredential) {
      throw new LeafTabSyncAiraCloudError('Aira 桌面登录状态无效，请重新扫码登录。', 'invalid_desktop_push_token');
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
      let parsed: AiraCloudResponse = {};
      try {
        parsed = text ? JSON.parse(text) as AiraCloudResponse : {};
      } catch {
        throw new LeafTabSyncAiraCloudError(
          `Aira 云同步响应格式错误（${response.status}）。`,
          'invalid_response',
          response.status,
        );
      }
      if (!response.ok || parsed.ok !== true) {
        throw new LeafTabSyncAiraCloudError(
          parsed.message || `Aira 云同步请求失败（${response.status}）。`,
          String(parsed.code || ''),
          response.status,
        );
      }
      return parsed;
    } finally {
      globalThis.clearTimeout(timeout);
    }
  }
}
