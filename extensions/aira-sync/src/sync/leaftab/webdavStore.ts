import { ensureOriginPermission } from '@/utils/extensionPermissions';
import {
  createLeafTabSyncCommitId,
  LEAFTAB_SYNC_DEFAULT_ROOT,
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

export interface LeafTabSyncWebdavStoreConfig {
  url: string;
  username?: string;
  password?: string;
  rootPath?: string;
  requestPermission?: boolean;
  requestTimeoutMs?: number;
}

type WebdavMethod = 'GET' | 'PUT' | 'DELETE' | 'MKCOL' | 'MOVE' | 'LOCK' | 'UNLOCK';
type WebdavCreateMode = 'if-none-match' | 'move-no-overwrite' | 'lock-serialized';
type WebdavRevisionCondition = 'if-match' | 'webdav-if';

type WebdavConditionalWriteSupport = {
  createMode: WebdavCreateMode;
  weakEtagIfVerified: boolean;
  lockSerialized: boolean;
};

type WebdavRequestResult = {
  status: number;
  ok: boolean;
  text: string;
  headers: Record<string, string>;
};

type LeafTabSyncWebdavSnapshotFile = {
  version: number;
  history: LeafTabSyncHistoryDescriptor;
  commitId: string;
  parentCommitId: string | null;
  deviceId: string;
  createdAt: string;
  snapshot: LeafTabSyncWireSnapshot;
};

type LeafTabSyncWebdavSnapshotRead = {
  file: LeafTabSyncWebdavSnapshotFile | null;
  snapshot: LeafTabSyncSnapshot | null;
  etag: string | null;
};

export class LeafTabSyncWebdavError extends Error {
  status: number;
  operation: string;
  relativePath: string | null;

  constructor(operation: string, status: number, relativePath?: string | null, message?: string) {
    super(message || `LeafTab sync WebDAV ${operation} failed: ${status}${relativePath ? ` @ ${relativePath}` : ''}`);
    this.name = 'LeafTabSyncWebdavError';
    this.status = status;
    this.operation = operation;
    this.relativePath = relativePath || null;
  }
}

const BOOKMARK_WEBDAV_FILE_VERSION = 2;
const BOOKMARK_WEBDAV_SNAPSHOT_FILE = 'snapshot.json';
const DEFAULT_WEBDAV_REQUEST_TIMEOUT_MS = 15_000;
const WEBDAV_LOCK_TIMEOUT_SECONDS = 120;
const WEBDAV_LOCK_REQUEST_BODY = '<?xml version="1.0" encoding="utf-8"?>'
  + '<D:lockinfo xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope>'
  + '<D:locktype><D:write/></D:locktype><D:owner><D:href>aira</D:href></D:owner></D:lockinfo>';
const CAS_PROBE_CONFIRMATION_DELAYS_MS = [0, 100, 250, 500] as const;
const VERIFIED_CONDITIONAL_WRITE_PROVIDERS = new Map<string, WebdavConditionalWriteSupport>();

const normalizeBaseUrl = (url: string) => {
  const trimmed = (url || '').trim().replace(/\/+$/, '');
  if (!trimmed) throw new Error('Invalid WebDAV URL');
  return trimmed;
};

const normalizeRootPath = (rootPath?: string) => {
  return (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT).trim().replace(/^\/+/, '').replace(/\/+$/, '')
    || LEAFTAB_SYNC_DEFAULT_ROOT;
};

const joinUrl = (baseUrl: string, relativePath: string) => {
  return `${normalizeBaseUrl(baseUrl)}/${relativePath.replace(/^\/+/, '')}`;
};

const encodeBasicAuth = (username?: string, password?: string) => {
  if (!username && !password) return '';
  return `Basic ${btoa(`${username || ''}:${password || ''}`)}`;
};

const isRuntimeProxyUnavailable = (message: string) => {
  return /Receiving end does not exist|Could not establish connection|The message port closed/i.test(message);
};

const parseJsonOrNull = <T>(text: string): T | null => {
  if (!text) return null;
  try {
    return JSON.parse(text) as T;
  } catch {
    return null;
  }
};

export class LeafTabSyncWebdavStore implements LeafTabSyncRemoteStore {
  private readonly config: Required<LeafTabSyncWebdavStoreConfig>;
  private permissionGranted = false;
  private readonly ensuredCollections = new Set<string>();
  private readonly historyLifecycle = new LeafTabSyncTombstoneLifecycle();

  constructor(config: LeafTabSyncWebdavStoreConfig) {
    this.config = {
      url: normalizeBaseUrl(config.url),
      username: config.username || '',
      password: config.password || '',
      rootPath: normalizeRootPath(config.rootPath),
      requestPermission: config.requestPermission !== false,
      requestTimeoutMs: Math.max(1_000, config.requestTimeoutMs ?? DEFAULT_WEBDAV_REQUEST_TIMEOUT_MS),
    };
  }

  async readState(): Promise<LeafTabSyncRemoteState> {
    const read = await this.readSnapshotWithValidator();
    if (!read.file || !read.snapshot) {
      return { snapshot: null, commitId: null, history: null };
    }
    return {
      snapshot: read.snapshot,
      commitId: read.file.commitId,
      history: read.file.history,
    };
  }

  async readHead(): Promise<LeafTabSyncRemoteHead> {
    const read = await this.readSnapshotWithValidator();
    if (!read.file || !read.snapshot) {
      return {
        commitId: null,
        updatedAt: 0,
      };
    }
    return {
      commitId: read.file.commitId,
      updatedAt: Date.parse(read.file.createdAt) || 0,
      summary: {
        bookmarkFolders: Object.keys(read.snapshot.bookmarkFolders).length,
        bookmarkItems: Object.keys(read.snapshot.bookmarkItems).length,
        tombstones: Object.keys(read.snapshot.tombstones).length,
      },
    };
  }

  async writeState(params: LeafTabSyncWriteStateParams): Promise<LeafTabSyncWriteStateResult> {
    const snapshot = validateCanonicalLeafTabSyncSnapshot(params.snapshot, 'WebDAV ');
    const history = this.historyLifecycle.validateHistory(params.history);
    this.historyLifecycle.assertSnapshotWithinHistory(snapshot, history, 'WebDAV ');
    const conditionalWriteSupport = await this.ensureConditionalWriteSupport();
    const createMode = conditionalWriteSupport.createMode;
    const expectedParentCommitId = params.parentCommitId ?? null;
    const current = await this.readSnapshotWithValidator();
    this.assertExactParent(current.file, expectedParentCommitId);
    if (current.file && !this.historyLifecycle.sameHistory(
      this.historyLifecycle.selectNewerHistory(current.file.history, history),
      history,
    )) {
      throw new Error('WebDAV 书签墓碑历史边界不能回退。');
    }
    const createdAt = params.createdAt || snapshot.meta.generatedAt;
    const commitId = createLeafTabSyncCommitId(params.deviceId, createdAt);
    const file: LeafTabSyncWebdavSnapshotFile = {
      version: BOOKMARK_WEBDAV_FILE_VERSION,
      history,
      commitId,
      parentCommitId: expectedParentCommitId,
      deviceId: params.deviceId,
      createdAt,
      snapshot: toLeafTabSyncWireSnapshot(snapshot),
    };
    try {
      if (conditionalWriteSupport.lockSerialized) {
        await this.putJsonWithLock(this.snapshotPath(), file, expectedParentCommitId);
      } else if (expectedParentCommitId === null && createMode === 'move-no-overwrite') {
        await this.putJsonWithMoveNoOverwrite(this.snapshotPath(), file);
      } else {
        const headers = expectedParentCommitId === null
          ? { 'If-None-Match': '*' }
          : (() => {
              if (!current.etag) {
                throw new Error('WebDAV 服务未提供 ETag，无法安全写入同步快照。');
              }
              return this.buildVerifiedRevisionCondition(current.etag, conditionalWriteSupport);
            })();
        await this.putJson(this.snapshotPath(), file, headers);
      }
    } catch (error) {
      if (error instanceof LeafTabSyncWebdavError && (error.status === 409 || error.status === 412)) {
        throw new Error('WebDAV 远端已被其他设备更新，请重新同步。');
      }
      throw error;
    }
    return {
      commitId,
      writtenAt: createdAt,
    };
  }

  /**
   * Publishes the snapshot under an exclusive WebDAV lock. Providers such as OpenList ignore
   * `If-None-Match`, `If-Match`, and `MOVE Overwrite: F`, leaving the lock as the only mutual-exclusion
   * primitive. Re-reading under the lock re-establishes compare-and-swap: the write proceeds only when
   * the remote parent is still the one the merge was built from.
   */
  private async putJsonWithLock(
    relativePath: string,
    payload: unknown,
    expectedParentCommitId: string | null,
  ) {
    const body = JSON.stringify(payload);
    await this.ensureCollections(relativePath);
    const lockToken = await this.acquireWriteLock(relativePath);
    try {
      const current = await this.readSnapshotWithValidator();
      this.assertExactParent(current.file, expectedParentCommitId);
      const response = await this.request('PUT', relativePath, {
        headers: {
          'Content-Type': 'application/json',
          If: `(<${lockToken}>)`,
        },
        body,
      });
      if (response.status === 409 || response.status === 412 || response.status === 423) {
        throw new LeafTabSyncWebdavError('lock-conflict', 409, relativePath);
      }
      if (!response.ok) {
        throw new LeafTabSyncWebdavError('upload', response.status, relativePath);
      }
      const readBack = await this.getTextResult(relativePath);
      if (!readBack || readBack.text !== body) {
        throw new Error('WebDAV 写入后回读内容不一致，无法安全同步。');
      }
    } finally {
      await this.releaseWriteLock(relativePath, lockToken).catch(() => undefined);
    }
  }

  private async acquireWriteLock(relativePath: string): Promise<string> {
    const response = await this.request('LOCK', relativePath, {
      headers: {
        'Content-Type': 'application/xml; charset=utf-8',
        Timeout: `Second-${WEBDAV_LOCK_TIMEOUT_SECONDS}`,
        Depth: '0',
      },
      body: WEBDAV_LOCK_REQUEST_BODY,
    });
    if (!response.ok) {
      throw new LeafTabSyncWebdavError('lock', response.status, relativePath);
    }
    const token = this.normalizeLockToken(this.readHeaderValue(response.headers, 'lock-token'));
    if (!token) {
      throw new Error('WebDAV 写入锁缺少 Lock-Token，无法安全同步。');
    }
    return token;
  }

  private async releaseWriteLock(relativePath: string, token: string) {
    await this.request('UNLOCK', relativePath, {
      headers: { 'Lock-Token': `<${token}>` },
    });
  }

  private normalizeLockToken(rawToken: string | null) {
    let token = (rawToken || '').trim();
    if (token.length >= 2 && token.startsWith('<') && token.endsWith('>')) {
      token = token.slice(1, -1).trim();
    }
    return token;
  }

  private async putJsonWithMoveNoOverwrite(relativePath: string, payload: unknown) {
    const suffix = `${Date.now().toString(36)}-${Math.floor(Math.random() * 0x100000000).toString(36)}`;
    const tempPath = `${relativePath}.create-${suffix}.tmp`;
    const body = JSON.stringify(payload);
    try {
      await this.ensureCollections(tempPath);
      const upload = await this.request('PUT', tempPath, {
        headers: { 'Content-Type': 'application/json' },
        body,
      });
      if (!upload.ok) {
        throw new LeafTabSyncWebdavError('move-upload', upload.status, tempPath);
      }
      const response = await this.movePath(tempPath, relativePath, false);
      if (!response.ok) {
        throw new LeafTabSyncWebdavError('move-create', response.status, relativePath);
      }
      const readBack = await this.getTextResult(relativePath);
      if (!readBack || readBack.text !== body || !this.readHeaderValue(readBack.headers, 'etag')) {
        throw new Error('WebDAV 服务无法确认 MOVE 首次写入结果，不支持安全同步。');
      }
    } finally {
      await this.deletePath(tempPath).catch(() => undefined);
    }
  }

  private movePath(sourcePath: string, destinationPath: string, overwrite: boolean) {
    return this.request('MOVE', sourcePath, {
      headers: {
        Destination: joinUrl(this.config.url, destinationPath),
        Overwrite: overwrite ? 'T' : 'F',
      },
    });
  }

  private snapshotPath() {
    return `${this.config.rootPath}/${BOOKMARK_WEBDAV_SNAPSHOT_FILE}`;
  }

  private async readSnapshotWithValidator(): Promise<LeafTabSyncWebdavSnapshotRead> {
    const path = this.snapshotPath();
    let response = await this.request('GET', path, { headers: {} });
    if (response.status === 409) {
      await this.ensureCollections(path);
      response = await this.request('GET', path, { headers: {} });
    }
    if (response.status === 404) {
      return { file: null, snapshot: null, etag: null };
    }
    if (!response.ok) {
      throw new LeafTabSyncWebdavError('download', response.status, path);
    }
    const file = parseJsonOrNull<LeafTabSyncWebdavSnapshotFile>(response.text);
    const snapshot = parseCanonicalLeafTabSyncWireSnapshot(file?.snapshot);
    const history = file?.history
      ? this.historyLifecycle.validateHistory(file.history)
      : null;
    if (file?.version !== BOOKMARK_WEBDAV_FILE_VERSION
      || !file.commitId?.trim()
      || (file.parentCommitId !== null && !file.parentCommitId?.trim())
      || !file.deviceId?.trim()
      || !file.createdAt?.trim()
      || !history
      || !snapshot
      || snapshot.meta.deviceId !== file.deviceId) {
      throw new Error('WebDAV 书签同步快照格式无效。');
    }
    this.historyLifecycle.assertSnapshotWithinHistory(snapshot, history, 'WebDAV ');
    return {
      file: { ...file, history },
      snapshot,
      etag: this.readHeaderValue(response.headers, 'etag'),
    };
  }

  private assertExactParent(
    file: LeafTabSyncWebdavSnapshotFile | null,
    expectedParentCommitId: string | null,
  ) {
    const actualParentCommitId = file?.commitId || null;
    if (actualParentCommitId !== expectedParentCommitId) {
      throw new Error(
        `WebDAV 远端已更新，请先重新拉取后再同步。当前远端 commit=${actualParentCommitId || ''}`,
      );
    }
  }

  private conditionalWriteProviderKey() {
    return [this.config.url, this.config.username, this.config.rootPath].join('|');
  }

  private async ensureConditionalWriteSupport() {
    const providerKey = this.conditionalWriteProviderKey();
    const verifiedMode = VERIFIED_CONDITIONAL_WRITE_PROVIDERS.get(providerKey);
    if (verifiedMode) return verifiedMode;
    const probeId = `${Date.now().toString(36)}-${Math.floor(Math.random() * 0x100000000).toString(36)}`;
    const probePath = `${this.config.rootPath}/cas-probe-${probeId}.json`;
    let conditionalSupport: WebdavConditionalWriteSupport | null = null;
    let conditionalError: Error | null = null;
    try {
      conditionalSupport = await this.verifyConditionalWriteSupport(probePath, probeId);
    } catch (error) {
      conditionalError = error as Error;
    }
    if (conditionalSupport) {
      VERIFIED_CONDITIONAL_WRITE_PROVIDERS.set(providerKey, conditionalSupport);
      return conditionalSupport;
    }
    try {
      await this.verifyLockSerializedSupport(probeId);
    } catch {
      throw conditionalError || new Error('WebDAV 服务不支持安全同步。');
    }
    const lockSupport: WebdavConditionalWriteSupport = {
      createMode: 'lock-serialized',
      weakEtagIfVerified: false,
      lockSerialized: true,
    };
    VERIFIED_CONDITIONAL_WRITE_PROVIDERS.set(providerKey, lockSupport);
    return lockSupport;
  }

  private async verifyConditionalWriteSupport(probePath: string, probeId: string) {
    await this.ensureCollections(probePath);
    try {
      let first = await this.request('PUT', probePath, {
        headers: {
          'Content-Type': 'application/json',
          'If-None-Match': '*',
        },
        body: '{"step":1}',
      });
      let createMode: WebdavCreateMode = 'if-none-match';
      if (first.status === 409 || first.status === 412) {
        const probeReadAfterRejectedCreate = await this.getTextResult(probePath);
        if (probeReadAfterRejectedCreate) {
          throw new Error(
            'WebDAV 服务拒绝首次条件写入，但探测文件实际存在，无法安全判断首次写入能力。',
          );
        }
        first = await this.request('PUT', probePath, {
          headers: { 'Content-Type': 'application/json' },
          body: '{"step":1}',
        });
        if (!first.ok) {
          throw new LeafTabSyncWebdavError('cas-probe-fallback-create', first.status, probePath);
        }
        await this.verifyMoveNoOverwriteSupport(probeId);
        createMode = 'move-no-overwrite';
      } else if (!first.ok) {
        throw new LeafTabSyncWebdavError('cas-probe-create', first.status, probePath);
      }
      let read = await this.getTextResult(probePath);
      let etag = read ? this.readHeaderValue(read.headers, 'etag') : null;
      if (!etag) {
        throw new Error('WebDAV 服务未提供 ETag，不支持安全同步。');
      }
      const duplicateCreate = await this.request('PUT', probePath, {
        headers: {
          'Content-Type': 'application/json',
          'If-None-Match': '*',
        },
        body: '{"step":2}',
      });
      if (duplicateCreate.status !== 409 && duplicateCreate.status !== 412) {
        if (!duplicateCreate.ok) {
          throw new LeafTabSyncWebdavError('cas-probe-duplicate-create', duplicateCreate.status, probePath);
        }
        etag = await this.confirmProbeState(probePath, '{"step":2}');
        if (createMode !== 'move-no-overwrite') {
          await this.verifyMoveNoOverwriteSupport(probeId);
        }
        createMode = 'move-no-overwrite';
      }
      const revisionCondition = this.revisionConditionForEtag(etag);
      const matchedUpdate = await this.request('PUT', probePath, {
        headers: {
          'Content-Type': 'application/json',
          ...this.buildRevisionCondition(etag, revisionCondition),
        },
        body: '{"step":3}',
      });
      if (!matchedUpdate.ok) {
        throw new LeafTabSyncWebdavError('cas-probe-update', matchedUpdate.status, probePath);
      }
      const staleUpdate = await this.request('PUT', probePath, {
        headers: {
          'Content-Type': 'application/json',
          ...this.buildRevisionCondition(etag, revisionCondition),
        },
        body: '{"step":4}',
      });
      if (staleUpdate.status !== 409 && staleUpdate.status !== 412) {
        throw new Error('WebDAV 服务忽略条件版本，不支持安全同步。');
      }
      const support: WebdavConditionalWriteSupport = {
        createMode,
        weakEtagIfVerified: revisionCondition === 'webdav-if',
        lockSerialized: false,
      };
      return support;
    } finally {
      await this.deletePath(probePath).catch(() => undefined);
    }
  }

  /**
   * Verifies that the provider can serialize a publication with an exclusive lock even though it
   * ignores the HTTP conditional headers. Every step mirrors a real write: the lock must be granted
   * on an absent path, exclude a competing lock and an unauthenticated write, admit the token-holding
   * write, expose a validator, and release cleanly. A provider that fails any step stays fail-closed.
   */
  private async verifyLockSerializedSupport(probeId: string) {
    const probePath = `${this.config.rootPath}/lock-probe-${probeId}.json`;
    const body = '{"lock":1}';
    await this.ensureCollections(probePath);
    let lockToken = '';
    try {
      await this.deletePath(probePath).catch(() => undefined);
      lockToken = await this.acquireWriteLock(probePath);
      const competingLock = await this.request('LOCK', probePath, {
        headers: {
          'Content-Type': 'application/xml; charset=utf-8',
          Timeout: `Second-${WEBDAV_LOCK_TIMEOUT_SECONDS}`,
          Depth: '0',
        },
        body: WEBDAV_LOCK_REQUEST_BODY,
      });
      if (competingLock.status !== 423 && competingLock.status !== 409) {
        throw new Error(`WebDAV 服务未独占加锁，不支持安全首次写入（HTTP ${competingLock.status}）。`);
      }
      const unauthenticatedWrite = await this.request('PUT', probePath, {
        headers: { 'Content-Type': 'application/json' },
        body,
      });
      if (unauthenticatedWrite.status !== 423 && unauthenticatedWrite.status !== 409) {
        throw new Error(`WebDAV 服务未阻止无锁写入，不支持安全首次写入（HTTP ${unauthenticatedWrite.status}）。`);
      }
      const authorizedWrite = await this.request('PUT', probePath, {
        headers: {
          'Content-Type': 'application/json',
          If: `(<${lockToken}>)`,
        },
        body,
      });
      if (!authorizedWrite.ok) {
        throw new LeafTabSyncWebdavError('lock-probe-write', authorizedWrite.status, probePath);
      }
      const read = await this.getTextResult(probePath);
      if (!read || read.text !== body || !this.readHeaderValue(read.headers, 'etag')) {
        throw new Error('WebDAV 服务无法确认加锁写入结果，不支持安全同步。');
      }
      await this.releaseWriteLock(probePath, lockToken);
      lockToken = '';
      const afterUnlock = await this.request('PUT', probePath, {
        headers: { 'Content-Type': 'application/json' },
        body: '{"unlocked":1}',
      });
      if (!afterUnlock.ok) {
        throw new LeafTabSyncWebdavError('lock-probe-unlock', afterUnlock.status, probePath);
      }
    } finally {
      if (lockToken) {
        await this.releaseWriteLock(probePath, lockToken).catch(() => undefined);
      }
      await this.deletePath(probePath).catch(() => undefined);
    }
  }

  private async verifyMoveNoOverwriteSupport(probeId: string) {
    const sourcePath = `${this.config.rootPath}/move-probe-${probeId}-source.json`;
    const destinationPath = `${this.config.rootPath}/move-probe-${probeId}-destination.json`;
    const preservedBody = '{"target":1}';
    const movedBody = '{"source":2}';
    try {
      const destinationCreate = await this.request('PUT', destinationPath, {
        headers: { 'Content-Type': 'application/json' },
        body: preservedBody,
      });
      if (!destinationCreate.ok) {
        throw new LeafTabSyncWebdavError('move-probe-target', destinationCreate.status, destinationPath);
      }
      const sourceCreate = await this.request('PUT', sourcePath, {
        headers: { 'Content-Type': 'application/json' },
        body: movedBody,
      });
      if (!sourceCreate.ok) {
        throw new LeafTabSyncWebdavError('move-probe-source', sourceCreate.status, sourcePath);
      }
      const rejectedMove = await this.movePath(sourcePath, destinationPath, false);
      if (rejectedMove.status !== 409 && rejectedMove.status !== 412) {
        throw new Error(
          `WebDAV 服务忽略 MOVE Overwrite: F，不支持安全首次写入（HTTP ${rejectedMove.status}）。`,
        );
      }
      const preserved = await this.getTextResult(destinationPath);
      if (!preserved || preserved.text !== preservedBody) {
        throw new Error('WebDAV 服务在拒绝 MOVE 后仍修改了目标文件，不支持安全首次写入。');
      }
      await this.deletePath(sourcePath).catch(() => undefined);
      await this.deletePath(destinationPath).catch(() => undefined);
      const createSource = await this.request('PUT', sourcePath, {
        headers: { 'Content-Type': 'application/json' },
        body: movedBody,
      });
      if (!createSource.ok) {
        throw new LeafTabSyncWebdavError('move-probe-create-source', createSource.status, sourcePath);
      }
      const acceptedMove = await this.movePath(sourcePath, destinationPath, false);
      if (!acceptedMove.ok) {
        throw new LeafTabSyncWebdavError('move-probe-create', acceptedMove.status, destinationPath);
      }
      const moved = await this.getTextResult(destinationPath);
      if (!moved || moved.text !== movedBody || !this.readHeaderValue(moved.headers, 'etag')) {
        throw new Error('WebDAV 服务无法确认 MOVE 首次写入结果，不支持安全同步。');
      }
    } finally {
      await this.deletePath(sourcePath).catch(() => undefined);
      await this.deletePath(destinationPath).catch(() => undefined);
    }
  }

  private revisionConditionForEtag(etag: string): WebdavRevisionCondition {
    return etag.startsWith('W/') ? 'webdav-if' : 'if-match';
  }

  private buildRevisionCondition(
    etag: string,
    revisionCondition: WebdavRevisionCondition,
  ): Record<string, string> {
    if (revisionCondition === 'webdav-if') {
      return { If: `([${etag}])` };
    }
    return { 'If-Match': etag };
  }

  private buildVerifiedRevisionCondition(
    etag: string,
    support: WebdavConditionalWriteSupport,
  ): Record<string, string> {
    const revisionCondition = this.revisionConditionForEtag(etag);
    if (revisionCondition === 'webdav-if' && !support.weakEtagIfVerified) {
      throw new Error('WebDAV 服务未验证弱 ETag 条件能力，无法安全写入同步快照。');
    }
    return this.buildRevisionCondition(etag, revisionCondition);
  }

  private async confirmProbeState(relativePath: string, expectedBody: string): Promise<string> {
    for (const delayMs of CAS_PROBE_CONFIRMATION_DELAYS_MS) {
      if (delayMs > 0) {
        await new Promise<void>((resolve) => {
          globalThis.setTimeout(resolve, delayMs);
        });
      }
      const read = await this.getTextResult(relativePath);
      const etag = read ? this.readHeaderValue(read.headers, 'etag') : null;
      if (read?.text === expectedBody && etag) {
        return etag;
      }
    }
    throw new Error('WebDAV 服务未及时返回最新探测文件版本，无法安全同步。');
  }

  private async ensurePermission(_relativePath: string) {
    if (this.permissionGranted) return;
    const granted = await ensureOriginPermission(this.config.url, {
      requestIfNeeded: this.config.requestPermission,
    });
    if (!granted) {
      throw new Error('WebDAV origin permission denied');
    }
    this.permissionGranted = true;
  }

  private getHeaders(extra?: Record<string, string>) {
    const auth = encodeBasicAuth(this.config.username, this.config.password);
    return {
      ...(auth ? { Authorization: auth } : {}),
      ...(extra || {}),
    };
  }

  private async requestViaExtensionProxy(
    method: WebdavMethod,
    relativePath: string,
    headers: Record<string, string>,
    body?: string,
  ): Promise<WebdavRequestResult | null> {
    const runtime = (globalThis as typeof globalThis & { chrome?: typeof chrome }).chrome?.runtime;
    if (!runtime?.id || typeof runtime.sendMessage !== 'function') {
      return null;
    }
    try {
      const response = await new Promise<any>((resolve, reject) => {
        const timeout = globalThis.setTimeout(() => {
          reject(new Error('WebDAV request timeout'));
        }, this.config.requestTimeoutMs);
        runtime.sendMessage(
          {
            type: 'LEAFTAB_WEBDAV_PROXY',
            payload: {
              url: joinUrl(this.config.url, relativePath),
              method,
              headers,
              body,
              timeoutMs: this.config.requestTimeoutMs,
            },
          },
          (result: any) => {
            globalThis.clearTimeout(timeout);
            const lastError = runtime.lastError;
            if (lastError) {
              reject(new Error(lastError.message || 'WebDAV proxy unavailable'));
              return;
            }
            resolve(result);
          },
        );
      });
      if (!response?.success) {
        throw new Error(response?.error || 'WebDAV proxy request failed');
      }
      return {
        status: Number(response?.status || 0),
        ok: Boolean(response?.ok),
        text: typeof response?.bodyText === 'string' ? response.bodyText : '',
        headers: response?.headers && typeof response.headers === 'object'
          ? response.headers as Record<string, string>
          : {},
      };
    } catch (error) {
      const message = String((error as Error)?.message || '');
      if (isRuntimeProxyUnavailable(message)) return null;
      throw error;
    }
  }

  private async request(
    method: WebdavMethod,
    relativePath: string,
    options?: { headers?: Record<string, string>; body?: string },
  ): Promise<WebdavRequestResult> {
    await this.ensurePermission(relativePath);
    const headers = this.getHeaders({
      ...(options?.headers || {}),
      ...(method === 'GET' ? { 'Cache-Control': 'no-cache' } : {}),
    });
    const proxied = await this.requestViaExtensionProxy(method, relativePath, headers, options?.body);
    if (proxied) return proxied;
    const controller = new AbortController();
    const timeout = globalThis.setTimeout(() => {
      controller.abort();
    }, this.config.requestTimeoutMs);
    try {
      const response = await fetch(joinUrl(this.config.url, relativePath), {
        method,
        headers,
        body: options?.body,
        signal: controller.signal,
        cache: method === 'GET' ? 'no-store' : undefined,
      });
      return {
        status: response.status,
        ok: response.ok,
        text: await response.text(),
        headers: Object.fromEntries(response.headers.entries()),
      };
    } finally {
      globalThis.clearTimeout(timeout);
    }
  }

  private async ensureCollections(relativeFilePath: string) {
    const parts = relativeFilePath.split('/').slice(0, -1);
    let current = '';
    for (const part of parts) {
      current = current ? `${current}/${part}` : part;
      if (this.ensuredCollections.has(current)) continue;
      const response = await this.request('MKCOL', current, { headers: {} });
      if (!(response.status === 201 || response.status === 405 || response.status === 301 || response.status === 200)) {
        throw new LeafTabSyncWebdavError('mkcol', response.status, current);
      }
      this.ensuredCollections.add(current);
    }
  }

  private async getTextResult(relativePath: string): Promise<WebdavRequestResult | null> {
    const response = await this.request('GET', relativePath, { headers: {} });
    if (response.status === 404) return null;
    if (!response.ok) {
      throw new LeafTabSyncWebdavError('download', response.status, relativePath);
    }
    return response;
  }

  private async putJson(relativePath: string, payload: unknown, headers?: Record<string, string>) {
    await this.ensureCollections(relativePath);
    const response = await this.request('PUT', relativePath, {
      headers: {
        'Content-Type': 'application/json',
        ...(headers || {}),
      },
      body: JSON.stringify(payload),
    });
    if (!response.ok) {
      throw new LeafTabSyncWebdavError('upload', response.status, relativePath);
    }
  }

  private async deletePath(relativePath: string) {
    const response = await this.request('DELETE', relativePath, { headers: {} });
    if (!(response.ok || response.status === 404)) {
      throw new LeafTabSyncWebdavError('delete', response.status, relativePath);
    }
  }

  private readHeaderValue(headers: Record<string, string>, targetName: string) {
    const target = targetName.toLowerCase();
    const key = Object.keys(headers).find((candidate) => candidate.toLowerCase() === target);
    const value = key ? headers[key] : '';
    return typeof value === 'string' && value.trim() ? value.trim() : null;
  }
}
