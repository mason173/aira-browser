import { ensureOriginPermission } from '@/utils/extensionPermissions';
import {
  createLeafTabSyncCommitId,
  LEAFTAB_SYNC_DEFAULT_ROOT,
  parseCanonicalLeafTabSyncWireSnapshot,
  toLeafTabSyncWireSnapshot,
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

export interface LeafTabSyncWebdavStoreConfig {
  url: string;
  username?: string;
  password?: string;
  rootPath?: string;
  requestPermission?: boolean;
  requestTimeoutMs?: number;
}

type WebdavMethod = 'GET' | 'PUT' | 'DELETE' | 'MKCOL' | 'MOVE';
type WebdavCreateMode = 'if-none-match' | 'move-no-overwrite';

type WebdavRequestResult = {
  status: number;
  ok: boolean;
  text: string;
  headers: Record<string, string>;
};

type LeafTabSyncWebdavSnapshotFile = {
  version: number;
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

const BOOKMARK_WEBDAV_FILE_VERSION = 1;
const BOOKMARK_WEBDAV_SNAPSHOT_FILE = 'snapshot.json';
const DEFAULT_WEBDAV_REQUEST_TIMEOUT_MS = 15_000;
const VERIFIED_CONDITIONAL_WRITE_PROVIDERS = new Map<string, WebdavCreateMode>();

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
      return { snapshot: null, commitId: null };
    }
    return { snapshot: read.snapshot, commitId: read.file.commitId };
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
    const createMode = await this.ensureConditionalWriteSupport();
    const expectedParentCommitId = params.parentCommitId ?? null;
    const current = await this.readSnapshotWithValidator();
    this.assertExactParent(current.file, expectedParentCommitId);
    const createdAt = params.createdAt || params.snapshot.meta.generatedAt;
    const commitId = createLeafTabSyncCommitId(params.deviceId, createdAt);
    const file: LeafTabSyncWebdavSnapshotFile = {
      version: BOOKMARK_WEBDAV_FILE_VERSION,
      commitId,
      parentCommitId: expectedParentCommitId,
      deviceId: params.deviceId,
      createdAt,
      snapshot: toLeafTabSyncWireSnapshot(params.snapshot),
    };
    try {
      if (expectedParentCommitId === null && createMode === 'move-no-overwrite') {
        await this.putJsonWithMoveNoOverwrite(this.snapshotPath(), file);
      } else {
        const headers = expectedParentCommitId === null
          ? { 'If-None-Match': '*' }
          : (() => {
              if (!current.etag) {
                throw new Error('WebDAV 服务未提供 ETag，无法安全写入同步快照。');
              }
              return { 'If-Match': current.etag };
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
    const response = await this.getTextResult(this.snapshotPath());
    if (!response) {
      return { file: null, snapshot: null, etag: null };
    }
    const file = parseJsonOrNull<LeafTabSyncWebdavSnapshotFile>(response.text);
    const snapshot = parseCanonicalLeafTabSyncWireSnapshot(file?.snapshot);
    if (file?.version !== BOOKMARK_WEBDAV_FILE_VERSION
      || !file.commitId?.trim()
      || (file.parentCommitId !== null && !file.parentCommitId?.trim())
      || !file.deviceId?.trim()
      || !file.createdAt?.trim()
      || !snapshot
      || snapshot.meta.deviceId !== file.deviceId) {
      throw new Error('WebDAV 书签同步快照格式无效。');
    }
    return {
      file,
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
    await this.ensureCollections(probePath);
    try {
      const first = await this.request('PUT', probePath, {
        headers: {
          'Content-Type': 'application/json',
          'If-None-Match': '*',
        },
        body: '{"step":1}',
      });
      if (!first.ok) {
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
      let createMode: WebdavCreateMode = 'if-none-match';
      if (duplicateCreate.status !== 409 && duplicateCreate.status !== 412) {
        if (!duplicateCreate.ok) {
          throw new LeafTabSyncWebdavError('cas-probe-duplicate-create', duplicateCreate.status, probePath);
        }
        read = await this.getTextResult(probePath);
        etag = read ? this.readHeaderValue(read.headers, 'etag') : null;
        if (!etag) {
          throw new Error('WebDAV 服务未提供 ETag，不支持安全同步。');
        }
        await this.verifyMoveNoOverwriteSupport(probeId);
        createMode = 'move-no-overwrite';
      }
      const matchedUpdate = await this.request('PUT', probePath, {
        headers: {
          'Content-Type': 'application/json',
          'If-Match': etag,
        },
        body: '{"step":3}',
      });
      if (!matchedUpdate.ok) {
        throw new LeafTabSyncWebdavError('cas-probe-update', matchedUpdate.status, probePath);
      }
      const staleUpdate = await this.request('PUT', probePath, {
        headers: {
          'Content-Type': 'application/json',
          'If-Match': etag,
        },
        body: '{"step":4}',
      });
      if (staleUpdate.status !== 409 && staleUpdate.status !== 412) {
        throw new Error('WebDAV 服务忽略 If-Match，不支持安全同步。');
      }
      VERIFIED_CONDITIONAL_WRITE_PROVIDERS.set(providerKey, createMode);
      return createMode;
    } finally {
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
    const headers = this.getHeaders(options?.headers);
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
    if (response.status === 404 || response.status === 409) return null;
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
