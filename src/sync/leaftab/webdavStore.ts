import { ensureOriginPermission } from '@/utils/extensionPermissions';
import {
  createLeafTabSyncCommitFile,
  createLeafTabSyncHeadFile,
  getLeafTabSyncCommitPath,
  getLeafTabSyncHeadPath,
  LEAFTAB_SYNC_DEFAULT_ROOT,
  type LeafTabSyncManifestFile,
  type LeafTabSyncCommitFile,
  type LeafTabSyncHeadFile,
  type LeafTabSyncSnapshot,
} from './schema';
import { createLeafTabSyncSerializedSnapshot } from './fileMap';
import { materializeLeafTabSyncSnapshotFromPayloadMap } from './snapshotCodec';
import type {
  LeafTabSyncRemoteHead,
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

type WebdavMethod = 'GET' | 'PUT' | 'DELETE' | 'MKCOL';

type WebdavRequestResult = {
  status: number;
  ok: boolean;
  text: string;
  headers: Record<string, string>;
};

type LeafTabSyncRemoteCacheEntry = {
  commitId: string;
  commit: LeafTabSyncCommitFile;
  snapshot: LeafTabSyncSnapshot;
  savedAt: string;
};

type LeafTabSyncWebdavHeadRead = {
  head: LeafTabSyncHeadFile | null;
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

const normalizeBaseUrl = (url: string) => {
  const trimmed = (url || '').trim().replace(/\/+$/, '');
  if (!trimmed) throw new Error('Invalid WebDAV URL');
  return trimmed;
};

const normalizeRootPath = (rootPath?: string) => {
  return (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT).trim().replace(/^\/+/, '').replace(/\/+$/, '') || LEAFTAB_SYNC_DEFAULT_ROOT;
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

const REMOTE_CACHE_STORAGE_PREFIX = 'leaftab_sync_g2_remote_state:';
const READ_BATCH_CONCURRENCY = 4;
const WRITE_BATCH_CONCURRENCY = 2;
const BATCH_COOPERATIVE_PAUSE_MS = 16;
const DEFAULT_WEBDAV_REQUEST_TIMEOUT_MS = 15_000;

const createRemoteCacheStorageKey = (url: string, rootPath: string) => {
  const suffix = `${normalizeBaseUrl(url)}|${normalizeRootPath(rootPath)}`
    .replace(/[^a-zA-Z0-9_-]+/g, '_');
  return `${REMOTE_CACHE_STORAGE_PREFIX}${suffix}`;
};

const runInBatches = async <T, R>(
  items: T[],
  batchSize: number,
  task: (item: T) => Promise<R>,
) => {
  const results: R[] = [];
  for (let index = 0; index < items.length; index += batchSize) {
    const batch = items.slice(index, index + batchSize);
    results.push(...(await Promise.all(batch.map((item) => task(item)))));
    if (index + batchSize < items.length) {
      await delay(BATCH_COOPERATIVE_PAUSE_MS);
    }
  }
  return results;
};

const delay = (durationMs: number) => new Promise<void>((resolve) => {
  globalThis.setTimeout(resolve, Math.max(0, durationMs));
});

export class LeafTabSyncWebdavStore implements LeafTabSyncRemoteStore {
  private readonly config: Required<LeafTabSyncWebdavStoreConfig>;
  private readonly remoteCacheStorageKey: string;
  private permissionGranted = false;
  private conditionalWritesVerified = false;
  private readonly ensuredCollections = new Set<string>();
  private static readonly memoryRemoteCache = new Map<string, LeafTabSyncRemoteCacheEntry>();

  constructor(config: LeafTabSyncWebdavStoreConfig) {
    this.config = {
      url: normalizeBaseUrl(config.url),
      username: config.username || '',
      password: config.password || '',
      rootPath: normalizeRootPath(config.rootPath),
      requestPermission: config.requestPermission !== false,
      requestTimeoutMs: Math.max(1_000, config.requestTimeoutMs ?? DEFAULT_WEBDAV_REQUEST_TIMEOUT_MS),
    };
    this.remoteCacheStorageKey = createRemoteCacheStorageKey(this.config.url, this.config.rootPath);
  }

  private readRemoteCache(commitId: string) {
    const inMemory = LeafTabSyncWebdavStore.memoryRemoteCache.get(this.remoteCacheStorageKey);
    if (inMemory?.commitId === commitId) {
      return inMemory;
    }

    try {
      const raw = globalThis.localStorage?.getItem(this.remoteCacheStorageKey);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as LeafTabSyncRemoteCacheEntry | null;
      if (!parsed || parsed.commitId !== commitId || !parsed.snapshot || !parsed.commit) {
        return null;
      }
      LeafTabSyncWebdavStore.memoryRemoteCache.set(this.remoteCacheStorageKey, parsed);
      return parsed;
    } catch {
      return null;
    }
  }

  private writeRemoteCache(entry: LeafTabSyncRemoteCacheEntry) {
    LeafTabSyncWebdavStore.memoryRemoteCache.set(this.remoteCacheStorageKey, entry);
    try {
      globalThis.localStorage?.setItem(this.remoteCacheStorageKey, JSON.stringify(entry));
    } catch {}
  }

  private clearRemoteCache() {
    LeafTabSyncWebdavStore.memoryRemoteCache.delete(this.remoteCacheStorageKey);
    try {
      globalThis.localStorage?.removeItem(this.remoteCacheStorageKey);
    } catch {}
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
    options?: { headers?: Record<string, string>; body?: string; skipPermission?: boolean },
  ): Promise<WebdavRequestResult> {
    if (!options?.skipPermission) {
      await this.ensurePermission(relativePath);
    }

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
      const text = await response.text();
      return {
        status: response.status,
        ok: response.ok,
        text,
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
      const response = await this.request('MKCOL', current, {
        headers: {},
      });
      if (!(response.status === 201 || response.status === 405 || response.status === 301 || response.status === 200)) {
        throw new LeafTabSyncWebdavError('mkcol', response.status, current);
      }
      this.ensuredCollections.add(current);
    }
  }

  private async getTextResult(relativePath: string): Promise<WebdavRequestResult | null> {
    const response = await this.request('GET', relativePath, {
      headers: {},
    });
    // Some providers (for example Jianguoyun WebDAV) may return 409 for reads
    // before the parent collection has been created. Treat it as "not found"
    // so first-time sync can initialize the remote structure.
    if (response.status === 404 || response.status === 409) return null;
    if (!response.ok) {
      throw new LeafTabSyncWebdavError('download', response.status, relativePath);
    }
    return response;
  }

  private async getText(relativePath: string): Promise<string | null> {
    const response = await this.getTextResult(relativePath);
    return response?.text || null;
  }

  private async getJson<T>(relativePath: string): Promise<T | null> {
    const text = await this.getText(relativePath);
    return text ? parseJsonOrNull<T>(text) : null;
  }

  private async putText(
    relativePath: string,
    body: string,
    contentType = 'application/json',
    headers?: Record<string, string>,
  ) {
    await this.ensureCollections(relativePath);
    const response = await this.request('PUT', relativePath, {
      headers: {
        'Content-Type': contentType,
        ...(headers || {}),
      },
      body,
    });
    if (!response.ok) {
      throw new LeafTabSyncWebdavError('upload', response.status, relativePath);
    }
    return response;
  }

  private async putJson(relativePath: string, payload: unknown, headers?: Record<string, string>) {
    await this.putText(relativePath, JSON.stringify(payload, null, 2), 'application/json', headers);
  }

  private async deletePath(relativePath: string) {
    const response = await this.request('DELETE', relativePath, { headers: {} });
    if (!(response.ok || response.status === 404)) {
      throw new LeafTabSyncWebdavError('delete', response.status, relativePath);
    }
  }

  async readJsonFile<T>(relativePath: string): Promise<T | null> {
    const normalizedPath = (relativePath || '').trim().replace(/^\/+/, '');
    if (!normalizedPath) return null;
    return this.getJson<T>(normalizedPath);
  }

  async readTextFile(relativePath: string): Promise<string | null> {
    const normalizedPath = (relativePath || '').trim().replace(/^\/+/, '');
    if (!normalizedPath) return null;
    return this.getText(normalizedPath);
  }

  async writeJsonFile(relativePath: string, payload: unknown) {
    const normalizedPath = (relativePath || '').trim().replace(/^\/+/, '');
    if (!normalizedPath) {
      throw new Error('Invalid WebDAV relative path');
    }
    await this.putJson(normalizedPath, payload);
  }

  async writeTextFile(relativePath: string, body: string, contentType = 'application/json') {
    const normalizedPath = (relativePath || '').trim().replace(/^\/+/, '');
    if (!normalizedPath) {
      throw new Error('Invalid WebDAV relative path');
    }
    await this.putText(normalizedPath, body, contentType);
  }

  async deleteFile(relativePath: string) {
    const normalizedPath = (relativePath || '').trim().replace(/^\/+/, '');
    if (!normalizedPath) return;
    await this.deletePath(normalizedPath);
  }

  async readState(): Promise<{
    head: LeafTabSyncHeadFile | null;
    commit: LeafTabSyncCommitFile | null;
    snapshot: LeafTabSyncSnapshot | null;
  }> {
    const remoteHead = await this.readHead();
    if (!remoteHead.head?.commitId) {
      this.clearRemoteCache();
      return { head: null, commit: null, snapshot: null };
    }
    const head = remoteHead.head;

    const cached = this.readRemoteCache(head.commitId);
    if (cached) {
      return {
        head,
        commit: cached.commit,
        snapshot: cached.snapshot,
      };
    }

    const commit = remoteHead.commit || await this.getJson<LeafTabSyncCommitFile>(
      getLeafTabSyncCommitPath(head.commitId, this.config.rootPath),
    );
    if (!commit) {
      this.clearRemoteCache();
      return { head, commit: null, snapshot: null };
    }

    const manifest = await this.getJson<LeafTabSyncManifestFile>(commit.manifestPath);
    if (!manifest?.packs?.length) {
      this.clearRemoteCache();
      return { head, commit, snapshot: null };
    }

    const packEntries = await runInBatches(
      manifest.packs,
      READ_BATCH_CONCURRENCY,
      async (pack) => [pack, await this.getJson<unknown>(pack.path)] as const,
    );
    const payloadMap = Object.fromEntries([
      [commit.manifestPath, manifest],
      [
        commit.appPrivateBookmarksPath || '',
        commit.appPrivateBookmarksPath
          ? await this.getJson<unknown>(commit.appPrivateBookmarksPath)
          : null,
      ],
      ...packEntries.map(([packRef, value]) => [packRef.path, value]),
    ]);
    const snapshot = materializeLeafTabSyncSnapshotFromPayloadMap(payloadMap, commit);
    if (!snapshot) {
      this.clearRemoteCache();
      return { head, commit, snapshot: null };
    }
    this.writeRemoteCache({
      commitId: commit.id,
      commit,
      snapshot,
      savedAt: new Date().toISOString(),
    });

    return {
      head,
      commit,
      snapshot,
    };
  }

  async readHead(): Promise<LeafTabSyncRemoteHead> {
    const headRead = await this.readHeadWithValidator();
    const head = headRead.head;
    if (!head?.commitId) {
      return {
        head: null,
        commit: null,
        commitId: null,
        updatedAt: 0,
      };
    }

    const commit = await this.getJson<LeafTabSyncCommitFile>(
      getLeafTabSyncCommitPath(head.commitId, this.config.rootPath),
    );
    return {
      head,
      commit,
      commitId: head.commitId,
      updatedAt: Date.parse(head.updatedAt || commit?.createdAt || '') || 0,
      summary: commit?.summary
        ? {
            bookmarkFolders: Number(commit.summary.bookmarkFolders || 0),
            bookmarkItems: Number(commit.summary.bookmarkItems || 0),
            tombstones: Number(commit.summary.tombstones || 0),
          }
        : undefined,
    };
  }

  private async readHeadWithValidator(): Promise<LeafTabSyncWebdavHeadRead> {
    const response = await this.getTextResult(getLeafTabSyncHeadPath(this.config.rootPath));
    if (!response) {
      return { head: null, etag: null };
    }
    const head = parseJsonOrNull<LeafTabSyncHeadFile>(response.text);
    return {
      head: head?.commitId ? head : null,
      etag: this.readHeaderValue(response.headers, 'etag'),
    };
  }

  private readHeaderValue(headers: Record<string, string>, targetName: string) {
    const target = targetName.toLowerCase();
    const key = Object.keys(headers).find((candidate) => candidate.toLowerCase() === target);
    const value = key ? headers[key] : '';
    return typeof value === 'string' && value.trim() ? value.trim() : null;
  }

  private assertExactParent(head: LeafTabSyncHeadFile | null, expectedParentCommitId: string | null) {
    const actualParentCommitId = head?.commitId || null;
    if (actualParentCommitId !== expectedParentCommitId) {
      throw new Error(
        `WebDAV 远端已更新，请先重新拉取后再同步。当前远端 commit=${actualParentCommitId || ''}`,
      );
    }
  }

  private async publishHeadConditionally(
    headRead: LeafTabSyncWebdavHeadRead,
    expectedParentCommitId: string | null,
    nextHead: LeafTabSyncHeadFile,
  ) {
    this.assertExactParent(headRead.head, expectedParentCommitId);
    const headers: Record<string, string> = expectedParentCommitId === null
      ? { 'If-None-Match': '*' }
      : (() => {
          if (!headRead.etag) {
            throw new Error('WebDAV 服务未提供 ETag，无法安全发布同步提交。');
          }
          return { 'If-Match': headRead.etag };
        })();
    try {
      await this.putJson(getLeafTabSyncHeadPath(this.config.rootPath), nextHead, headers);
    } catch (error) {
      if (error instanceof LeafTabSyncWebdavError && (error.status === 409 || error.status === 412)) {
        this.clearRemoteCache();
        throw new Error('WebDAV 远端已被其他设备更新，请重新同步。');
      }
      throw error;
    }
  }

  async writeState(params: LeafTabSyncWriteStateParams): Promise<LeafTabSyncWriteStateResult> {
    await this.ensureConditionalWriteSupport();
    const expectedParentCommitId = params.parentCommitId ?? null;
    const headRead = await this.readHeadWithValidator();
    this.assertExactParent(headRead.head, expectedParentCommitId);
    const commit = createLeafTabSyncCommitFile({
      deviceId: params.deviceId,
      createdAt: params.createdAt,
      parentCommitId: expectedParentCommitId,
      snapshot: params.snapshot,
      rootPath: this.config.rootPath,
    });
    const serialized = createLeafTabSyncSerializedSnapshot(params.snapshot, {
      rootPath: this.config.rootPath,
      commit,
      head: createLeafTabSyncHeadFile(commit.id, commit.createdAt),
    });

    const writes = Object.entries(serialized.payloads)
      .map(([path, payload]) => ({ path, payload }));

    await runInBatches(writes, WRITE_BATCH_CONCURRENCY, async ({ path, payload }) => {
      await this.putJson(path, payload);
      return null;
    });

    await this.putJson(getLeafTabSyncCommitPath(commit.id, this.config.rootPath), commit);
    const head = serialized.head;
    await this.publishHeadConditionally(headRead, expectedParentCommitId, head);

    this.writeRemoteCache({
      commitId: commit.id,
      commit,
      snapshot: params.snapshot,
      savedAt: new Date().toISOString(),
    });

    return { head, commit };
  }

  private async ensureConditionalWriteSupport() {
    if (this.conditionalWritesVerified) return;
    const probeId = `${Date.now().toString(36)}-${Math.floor(Math.random() * 0x100000000).toString(36)}`;
    const probePath = `${this.config.rootPath}/cas/cas-probe-${probeId}.json`;
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
      const read = await this.getTextResult(probePath);
      const etag = read ? this.readHeaderValue(read.headers, 'etag') : null;
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
        throw new Error('WebDAV 服务忽略 If-None-Match，不支持安全同步。');
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
      this.conditionalWritesVerified = true;
    } finally {
      await this.deletePath(probePath).catch(() => undefined);
    }
  }

}
