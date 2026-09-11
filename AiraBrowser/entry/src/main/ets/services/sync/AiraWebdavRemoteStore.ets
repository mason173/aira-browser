import http from '@ohos.net.http';
import buffer from '@ohos.buffer';
import {
  AIRA_SYNC_DEFAULT_ROOT,
  AiraBookmarkHistoryDescriptor,
  AiraSyncCommitSummary,
  AiraSyncRemoteHead,
  AiraSyncRemoteState,
  AiraSyncRemoteStore,
  AiraSyncSnapshot,
  AiraSyncWebdavConfig,
  AiraSyncWriteStateParams,
  AiraSyncWriteStateResult
} from '../../common/models/AiraSyncModels';
import { AiraBookmarkSnapshotValidationService } from './AiraBookmarkSnapshotValidationService';
import { AiraBookmarkTombstoneLifecycleService } from './AiraBookmarkTombstoneLifecycleService';

type AiraWebdavMethod = 'GET' | 'PUT' | 'DELETE' | 'OPTIONS' | 'MKCOL' | 'MOVE';
type AiraWebdavCreateMode = 'if-none-match' | 'move-no-overwrite';
type AiraWebdavRevisionCondition = 'if-match' | 'webdav-if';

interface AiraWebdavConditionalWriteSupport {
  createMode: AiraWebdavCreateMode;
  weakEtagIfVerified: boolean;
}

interface AiraWebdavResponse {
  status: number;
  body: string;
  headers: Object;
}

interface AiraWebdavHeaders {
  Accept: string;
  Authorization: string;
  'Content-Type'?: string;
  'If'?: string;
  'If-Match'?: string;
  'If-None-Match'?: string;
}

interface AiraWebdavMoveHeaders {
  Accept: string;
  Authorization: string;
  Destination: string;
  Overwrite: string;
}

interface AiraWebdavConditionalHeaders {
  webdavIf?: string;
  ifMatch?: string;
  ifNoneMatch?: string;
}

interface AiraWebdavBookmarkSnapshotFile {
  version: number;
  history: AiraBookmarkHistoryDescriptor;
  commitId: string;
  parentCommitId: string | null;
  deviceId: string;
  createdAt: string;
  snapshot: AiraSyncSnapshot;
}

interface AiraWebdavSnapshotRead {
  file: AiraWebdavBookmarkSnapshotFile | null;
  etag: string;
}

const BOOKMARK_WEBDAV_FILE_VERSION: number = 2;
const BOOKMARK_WEBDAV_SNAPSHOT_FILE: string = 'snapshot.json';
const REQUEST_TIMEOUT_MS: number = 15000;
const REMOTE_READ_MAX_ATTEMPTS: number = 3;
const REMOTE_READ_RETRY_DELAY_MS: number = 350;
const VERIFIED_CONDITIONAL_WRITE_PROVIDERS: Map<string, AiraWebdavConditionalWriteSupport> =
  new Map<string, AiraWebdavConditionalWriteSupport>();

export class AiraWebdavRemoteStore implements AiraSyncRemoteStore {
  private config: AiraSyncWebdavConfig;
  private rootPath: string;
  private requestTimeoutMs: number;
  private snapshotValidationService: AiraBookmarkSnapshotValidationService =
    new AiraBookmarkSnapshotValidationService();
  private historyService: AiraBookmarkTombstoneLifecycleService =
    new AiraBookmarkTombstoneLifecycleService();

  constructor(config: AiraSyncWebdavConfig, rootPath: string, requestTimeoutMs: number = REQUEST_TIMEOUT_MS) {
    this.config = config;
    this.rootPath = this.normalizeRootPath(rootPath);
    this.requestTimeoutMs = Math.max(1000, requestTimeoutMs);
  }

  async readState(): Promise<AiraSyncRemoteState> {
    let lastError: Error | undefined = undefined;
    for (let attempt = 0; attempt < REMOTE_READ_MAX_ATTEMPTS; attempt += 1) {
      try {
        const read = await this.readSnapshotFile();
        return {
          snapshot: read.file?.snapshot ?? null,
          commitId: read.file?.commitId ?? null,
          history: read.file?.history ?? null
        };
      } catch (error) {
        lastError = error as Error;
        if (attempt < REMOTE_READ_MAX_ATTEMPTS - 1) {
          await this.delay(REMOTE_READ_RETRY_DELAY_MS);
        }
      }
    }
    throw lastError ?? new Error('WebDAV 远端状态暂时不稳定，请稍后重试。');
  }

  async readHead(): Promise<AiraSyncRemoteHead> {
    const read = await this.readSnapshotFile();
    if (read.file === null) {
      return {
        commitId: null,
        updatedAt: 0,
        bookmarkFolders: -1,
        bookmarkItems: -1,
        hasBookmarkSummary: false
      };
    }
    const file = read.file;
    const summary = this.buildSummary(file.snapshot);
    return {
      commitId: file.commitId,
      updatedAt: this.parseUpdatedAt(file.createdAt),
      bookmarkFolders: summary.bookmarkFolders,
      bookmarkItems: summary.bookmarkItems,
      hasBookmarkSummary: true
    };
  }

  async writeState(params: AiraSyncWriteStateParams): Promise<AiraSyncWriteStateResult> {
    this.assertConfigured();
    const snapshot = this.snapshotValidationService.validate(params.snapshot, 'WebDAV ');
    const history = this.historyService.validateHistory(params.history, 'WebDAV 书签墓碑历史纪元');
    this.historyService.assertSnapshotWithinHistory(snapshot, history, 'WebDAV ');
    await this.ensureRemoteLayout();
    const conditionalWriteSupport = await this.ensureConditionalWriteSupport();
    const createMode = conditionalWriteSupport.createMode;
    const current = await this.readSnapshotFile();
    const overwriteExisting = params.overwriteExisting === true;
    const expectedParentCommitId = overwriteExisting
      ? (current.file?.commitId ?? null)
      : (params.parentCommitId ?? null);
    if (!overwriteExisting) {
      this.assertExactParent(current.file, expectedParentCommitId);
      if (current.file !== null && !this.historyService.sameHistory(
        this.historyService.selectNewerHistory(current.file.history, history),
        history
      )) {
        throw new Error('WebDAV 书签墓碑历史边界不能回退。');
      }
    }
    const createdAt = params.createdAt ?? snapshot.meta.generatedAt;
    const nextFile: AiraWebdavBookmarkSnapshotFile = {
      version: BOOKMARK_WEBDAV_FILE_VERSION,
      history: history,
      commitId: this.createCommitId(params.deviceId, createdAt),
      parentCommitId: expectedParentCommitId,
      deviceId: params.deviceId,
      createdAt: createdAt,
      snapshot: snapshot
    };
    let response: AiraWebdavResponse;
    if (expectedParentCommitId === null && createMode === 'move-no-overwrite') {
      response = await this.createWithMoveNoOverwrite(this.snapshotPath(), JSON.stringify(nextFile));
    } else {
      let condition: AiraWebdavConditionalHeaders;
      if (expectedParentCommitId === null) {
        condition = { ifNoneMatch: '*' };
      } else {
        if (current.etag.length <= 0) {
          throw new Error('WebDAV 服务未提供 ETag，无法安全写入同步快照。');
        }
        condition = this.buildVerifiedRevisionCondition(current.etag, conditionalWriteSupport);
      }
      response = await this.request(
        'PUT',
        this.snapshotPath(),
        JSON.stringify(nextFile),
        condition
      );
    }
    if (response.status === 409 || response.status === 412) {
      throw new Error('WebDAV 远端已被其他设备更新，请重新同步。');
    }
    this.assertSuccess(response, this.snapshotPath());
    return {
      commitId: nextFile.commitId,
      writtenAt: createdAt
    };
  }

  private async createWithMoveNoOverwrite(path: string, body: string): Promise<AiraWebdavResponse> {
    const tempPath = this.buildCreateTempPath(path);
    try {
      const upload = await this.request('PUT', tempPath, body);
      this.assertSuccess(upload, tempPath);
      const moved = await this.requestMove(tempPath, path, false);
      if (moved.status < 200 || moved.status >= 300) {
        return moved;
      }
      const readBack = await this.request('GET', path);
      this.assertSuccess(readBack, path);
      if (readBack.body !== body || this.readHeaderValue(readBack.headers, 'etag').length <= 0) {
        throw new Error('WebDAV 服务无法确认 MOVE 首次写入结果，不支持安全同步。');
      }
      return readBack;
    } finally {
      await this.request('DELETE', tempPath).catch((_error: Error): void => {
      });
    }
  }

  private buildCreateTempPath(path: string): string {
    const suffix = `${Date.now().toString(36)}-${Math.floor(Math.random() * 0x100000000).toString(36)}`;
    return `${path}.create-${suffix}.tmp`;
  }

  private async requestMove(
    sourcePath: string,
    destinationPath: string,
    overwrite: boolean
  ): Promise<AiraWebdavResponse> {
    const request = http.createHttp();
    try {
      const headers: AiraWebdavMoveHeaders = {
        Accept: 'application/json,text/plain,*/*',
        Authorization: this.buildAuthorizationHeader(),
        Destination: this.buildUrl(destinationPath),
        Overwrite: overwrite ? 'T' : 'F'
      };
      const response = await request.request(this.buildUrl(sourcePath), {
        method: 'MOVE' as http.RequestMethod,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.requestTimeoutMs,
        readTimeout: this.requestTimeoutMs,
        header: headers
      });
      return {
        status: response.responseCode,
        body: typeof response.result === 'string' ? response.result : '',
        headers: response.header ?? {}
      };
    } finally {
      request.destroy();
    }
  }

  async testConnection(): Promise<void> {
    this.assertConfigured();
    const response = await this.request('OPTIONS', '');
    if (response.status === 401 || response.status === 403) {
      throw new Error('WebDAV 认证失败，请检查用户名和密码。');
    }
    if (response.status >= 400) {
      throw new Error(`WebDAV 连接失败：HTTP ${response.status}`);
    }
  }

  async ensureRemoteLayout(): Promise<void> {
    this.assertConfigured();
    const directories = this.buildRequiredDirectories();
    for (let index = 0; index < directories.length; index += 1) {
      await this.ensureDirectory(directories[index]);
    }
  }

  private async readSnapshotFile(): Promise<AiraWebdavSnapshotRead> {
    this.assertConfigured();
    const path = this.snapshotPath();
    let response = await this.request('GET', path);
    if (response.status === 409) {
      await this.ensureRemoteLayout();
      response = await this.request('GET', path);
    }
    if (response.status === 404) {
      return { file: null, etag: '' };
    }
    this.assertSuccess(response, path);
    return {
      file: this.parseSnapshotFile(response.body),
      etag: this.readHeaderValue(response.headers, 'etag')
    };
  }

  private parseSnapshotFile(payload: string): AiraWebdavBookmarkSnapshotFile {
    let parsed: Object;
    try {
      parsed = JSON.parse(payload) as Object;
    } catch (_error) {
      throw new Error('WebDAV 书签同步快照无法解析。');
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('WebDAV 书签同步快照格式无效。');
    }
    const file = parsed as AiraWebdavBookmarkSnapshotFile;
    if (file.version !== BOOKMARK_WEBDAV_FILE_VERSION ||
      !this.isNonEmptyString(file.commitId) ||
      (file.parentCommitId !== null && !this.isNonEmptyString(file.parentCommitId)) ||
      !this.isNonEmptyString(file.deviceId) ||
      !this.isNonEmptyString(file.createdAt) ||
      !this.isValidBookmarkSnapshot(file.snapshot) ||
      file.snapshot.meta.deviceId !== file.deviceId) {
      throw new Error('WebDAV 书签同步快照格式无效。');
    }
    try {
      file.history = this.historyService.validateHistory(file.history, 'WebDAV 书签墓碑历史纪元');
      this.historyService.assertSnapshotWithinHistory(file.snapshot, file.history, 'WebDAV ');
    } catch (_error) {
      throw new Error('WebDAV 书签同步快照格式无效。');
    }
    return file;
  }

  private isValidBookmarkSnapshot(snapshot: AiraSyncSnapshot): boolean {
    try {
      this.snapshotValidationService.validate(snapshot, 'WebDAV ');
      return true;
    } catch (_error) {
      return false;
    }
  }

  private isNonEmptyString(value: string | undefined): boolean {
    return typeof value === 'string' && value.trim().length > 0;
  }

  private assertExactParent(
    current: AiraWebdavBookmarkSnapshotFile | null,
    expectedParentCommitId: string | null
  ): void {
    const actualParentCommitId = current?.commitId ?? null;
    if (actualParentCommitId !== expectedParentCommitId) {
      throw new Error(
        `WebDAV 远端已更新，请先重新拉取后再同步。当前远端 commit=${actualParentCommitId ?? ''}`
      );
    }
  }

  private buildSummary(snapshot: AiraSyncSnapshot): AiraSyncCommitSummary {
    return {
      bookmarkFolders: snapshot.bookmarkFolders.length,
      bookmarkItems: snapshot.bookmarkItems.length,
      tombstones: snapshot.tombstones.length
    };
  }

  private createCommitId(deviceId: string, createdAt: string): string {
    const timestamp = Date.parse(createdAt);
    const safeTimestamp = Number.isFinite(timestamp) ? timestamp : Date.now();
    const safeDeviceId = deviceId.trim().replace(/[^a-zA-Z0-9_-]+/g, '').slice(-16) || 'device';
    const random = Math.floor(Math.random() * 0x100000000).toString(36);
    return `${safeTimestamp.toString(36)}-${safeDeviceId}-${random}`;
  }

  private parseUpdatedAt(value: string): number {
    const timestamp = Date.parse(value);
    return Number.isFinite(timestamp) ? timestamp : 0;
  }

  private snapshotPath(): string {
    return `${this.rootPath}/${BOOKMARK_WEBDAV_SNAPSHOT_FILE}`;
  }

  private normalizeRootPath(rootPath: string): string {
    const normalized = rootPath.trim().replace(/^\/+|\/+$/g, '');
    return normalized.length > 0 ? normalized : AIRA_SYNC_DEFAULT_ROOT;
  }

  private buildRequiredDirectories(): string[] {
    const segments = this.rootPath.split('/').filter((item: string) => item.length > 0);
    const directories: string[] = [];
    let current = '';
    for (let index = 0; index < segments.length; index += 1) {
      current = current.length === 0 ? segments[index] : `${current}/${segments[index]}`;
      directories.push(current);
    }
    return directories;
  }

  private async ensureDirectory(path: string): Promise<void> {
    const response = await this.request('MKCOL', path);
    if ((response.status >= 200 && response.status < 300) || response.status === 405) {
      return;
    }
    throw new Error(`WebDAV 创建目录失败：${path}，HTTP ${response.status}`);
  }

  private conditionalWriteProviderKey(): string {
    return [
      this.config.endpoint.trim().replace(/\/+$/, ''),
      this.config.username.trim(),
      this.rootPath
    ].join('|');
  }

  private async ensureConditionalWriteSupport(): Promise<AiraWebdavConditionalWriteSupport> {
    const providerKey = this.conditionalWriteProviderKey();
    const verifiedMode = VERIFIED_CONDITIONAL_WRITE_PROVIDERS.get(providerKey);
    if (verifiedMode !== undefined) {
      return verifiedMode;
    }
    const probeId = `${Date.now().toString(36)}-${Math.floor(Math.random() * 0x100000000).toString(36)}`;
    const probePath = `${this.rootPath}/cas-probe-${probeId}.json`;
    try {
      let first = await this.request('PUT', probePath, '{"step":1}', { ifNoneMatch: '*' });
      let createMode: AiraWebdavCreateMode = 'if-none-match';
      if (first.status === 409 || first.status === 412) {
        const probeReadAfterRejectedCreate = await this.request('GET', probePath);
        if (probeReadAfterRejectedCreate.status !== 404) {
          if (probeReadAfterRejectedCreate.status >= 200 && probeReadAfterRejectedCreate.status < 300) {
            throw new Error('WebDAV 服务拒绝首次条件写入，但探测文件实际存在，无法安全判断首次写入能力。');
          }
          this.assertSuccess(probeReadAfterRejectedCreate, probePath);
        }
        first = await this.request('PUT', probePath, '{"step":1}');
        this.assertSuccess(first, probePath);
        await this.verifyMoveNoOverwriteSupport(probeId);
        createMode = 'move-no-overwrite';
      } else {
        this.assertSuccess(first, probePath);
      }
      let read = await this.request('GET', probePath);
      this.assertSuccess(read, probePath);
      let etag = this.readHeaderValue(read.headers, 'etag');
      if (etag.length <= 0) {
        throw new Error('WebDAV 服务未提供 ETag，不支持安全同步。');
      }
      const duplicateCreate = await this.request('PUT', probePath, '{"step":2}', { ifNoneMatch: '*' });
      if (duplicateCreate.status !== 409 && duplicateCreate.status !== 412) {
        this.assertSuccess(duplicateCreate, probePath);
        read = await this.request('GET', probePath);
        this.assertSuccess(read, probePath);
        etag = this.readHeaderValue(read.headers, 'etag');
        if (etag.length <= 0) {
          throw new Error('WebDAV 服务未提供 ETag，不支持安全同步。');
        }
        if (createMode !== 'move-no-overwrite') {
          await this.verifyMoveNoOverwriteSupport(probeId);
        }
        createMode = 'move-no-overwrite';
      }
      const revisionCondition = this.revisionConditionForEtag(etag);
      const matchedUpdate = await this.request(
        'PUT',
        probePath,
        '{"step":3}',
        this.buildRevisionCondition(etag, revisionCondition)
      );
      this.assertSuccess(matchedUpdate, probePath);
      const staleUpdate = await this.request(
        'PUT',
        probePath,
        '{"step":4}',
        this.buildRevisionCondition(etag, revisionCondition)
      );
      if (staleUpdate.status !== 409 && staleUpdate.status !== 412) {
        throw new Error('WebDAV 服务忽略条件版本，不支持安全同步。');
      }
      const support: AiraWebdavConditionalWriteSupport = {
        createMode,
        weakEtagIfVerified: revisionCondition === 'webdav-if'
      };
      VERIFIED_CONDITIONAL_WRITE_PROVIDERS.set(providerKey, support);
      return support;
    } finally {
      await this.request('DELETE', probePath).catch((_error: Error): void => {
      });
    }
  }

  private async verifyMoveNoOverwriteSupport(probeId: string): Promise<void> {
    const sourcePath = `${this.rootPath}/move-probe-${probeId}-source.json`;
    const destinationPath = `${this.rootPath}/move-probe-${probeId}-destination.json`;
    const preservedBody = '{"target":1}';
    const movedBody = '{"source":2}';
    try {
      const destinationCreate = await this.request('PUT', destinationPath, preservedBody);
      this.assertSuccess(destinationCreate, destinationPath);
      const sourceCreate = await this.request('PUT', sourcePath, movedBody);
      this.assertSuccess(sourceCreate, sourcePath);
      const rejectedMove = await this.requestMove(sourcePath, destinationPath, false);
      if (rejectedMove.status !== 409 && rejectedMove.status !== 412) {
        throw new Error(`WebDAV 服务忽略 MOVE Overwrite: F，不支持安全首次写入（HTTP ${rejectedMove.status}）。`);
      }
      const preserved = await this.request('GET', destinationPath);
      this.assertSuccess(preserved, destinationPath);
      if (preserved.body !== preservedBody) {
        throw new Error('WebDAV 服务在拒绝 MOVE 后仍修改了目标文件，不支持安全首次写入。');
      }
      await this.request('DELETE', sourcePath).catch((_error: Error): void => {
      });
      await this.request('DELETE', destinationPath).catch((_error: Error): void => {
      });
      const createSource = await this.request('PUT', sourcePath, movedBody);
      this.assertSuccess(createSource, sourcePath);
      const acceptedMove = await this.requestMove(sourcePath, destinationPath, false);
      this.assertSuccess(acceptedMove, destinationPath);
      const moved = await this.request('GET', destinationPath);
      this.assertSuccess(moved, destinationPath);
      if (moved.body !== movedBody || this.readHeaderValue(moved.headers, 'etag').length <= 0) {
        throw new Error('WebDAV 服务无法确认 MOVE 首次写入结果，不支持安全同步。');
      }
    } finally {
      await this.request('DELETE', sourcePath).catch((_error: Error): void => {
      });
      await this.request('DELETE', destinationPath).catch((_error: Error): void => {
      });
    }
  }

  private revisionConditionForEtag(etag: string): AiraWebdavRevisionCondition {
    return etag.indexOf('W/') === 0 ? 'webdav-if' : 'if-match';
  }

  private buildRevisionCondition(
    etag: string,
    revisionCondition: AiraWebdavRevisionCondition
  ): AiraWebdavConditionalHeaders {
    if (revisionCondition === 'webdav-if') {
      return { webdavIf: `([${etag}])` };
    }
    return { ifMatch: etag };
  }

  private buildVerifiedRevisionCondition(
    etag: string,
    support: AiraWebdavConditionalWriteSupport
  ): AiraWebdavConditionalHeaders {
    const revisionCondition = this.revisionConditionForEtag(etag);
    if (revisionCondition === 'webdav-if' && !support.weakEtagIfVerified) {
      throw new Error('WebDAV 服务未验证弱 ETag 条件能力，无法安全写入同步快照。');
    }
    return this.buildRevisionCondition(etag, revisionCondition);
  }

  private delay(durationMs: number): Promise<void> {
    return new Promise((resolve: () => void) => {
      setTimeout(resolve, durationMs);
    });
  }

  private async request(
    method: AiraWebdavMethod,
    path: string,
    body?: string,
    conditionalHeaders?: AiraWebdavConditionalHeaders
  ): Promise<AiraWebdavResponse> {
    const request = http.createHttp();
    try {
      const response = await request.request(this.buildUrl(path), {
        method: this.toRequestMethod(method),
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.requestTimeoutMs,
        readTimeout: this.requestTimeoutMs,
        header: this.buildHeaders(body !== undefined, conditionalHeaders)
      });
      return {
        status: response.responseCode,
        body: typeof response.result === 'string' ? response.result : '',
        headers: response.header ?? {}
      };
    } finally {
      request.destroy();
    }
  }

  private buildUrl(path: string): string {
    const endpoint = this.config.endpoint.trim().replace(/\/+$/, '');
    const normalizedPath = path.trim().replace(/^\/+/, '');
    return normalizedPath.length > 0 ? `${endpoint}/${normalizedPath}` : `${endpoint}/`;
  }

  private buildHeaders(
    hasBody: boolean,
    conditionalHeaders?: AiraWebdavConditionalHeaders
  ): Object {
    const ifMatch = conditionalHeaders?.ifMatch ?? '';
    const ifNoneMatch = conditionalHeaders?.ifNoneMatch ?? '';
    const webdavIf = conditionalHeaders?.webdavIf ?? '';
    if (hasBody) {
      if (webdavIf.length > 0) {
        return {
          Accept: 'application/json,text/plain,*/*',
          Authorization: this.buildAuthorizationHeader(),
          'Content-Type': 'application/json; charset=utf-8',
          'If': webdavIf
        } as AiraWebdavHeaders;
      }
      if (ifMatch.length > 0) {
        return {
          Accept: 'application/json,text/plain,*/*',
          Authorization: this.buildAuthorizationHeader(),
          'Content-Type': 'application/json; charset=utf-8',
          'If-Match': ifMatch
        } as AiraWebdavHeaders;
      }
      if (ifNoneMatch.length > 0) {
        return {
          Accept: 'application/json,text/plain,*/*',
          Authorization: this.buildAuthorizationHeader(),
          'Content-Type': 'application/json; charset=utf-8',
          'If-None-Match': ifNoneMatch
        } as AiraWebdavHeaders;
      }
      return {
        Accept: 'application/json,text/plain,*/*',
        Authorization: this.buildAuthorizationHeader(),
        'Content-Type': 'application/json; charset=utf-8'
      } as AiraWebdavHeaders;
    }
    if (webdavIf.length > 0) {
      return {
        Accept: 'application/json,text/plain,*/*',
        Authorization: this.buildAuthorizationHeader(),
        'If': webdavIf
      } as AiraWebdavHeaders;
    }
    if (ifMatch.length > 0) {
      return {
        Accept: 'application/json,text/plain,*/*',
        Authorization: this.buildAuthorizationHeader(),
        'If-Match': ifMatch
      } as AiraWebdavHeaders;
    }
    if (ifNoneMatch.length > 0) {
      return {
        Accept: 'application/json,text/plain,*/*',
        Authorization: this.buildAuthorizationHeader(),
        'If-None-Match': ifNoneMatch
      } as AiraWebdavHeaders;
    }
    return {
      Accept: 'application/json,text/plain,*/*',
      Authorization: this.buildAuthorizationHeader()
    } as AiraWebdavHeaders;
  }

  private readHeaderValue(headers: Object, targetName: string): string {
    const record = headers as Record<string, string>;
    const target = targetName.toLowerCase();
    const keys = Object.keys(record);
    for (let index = 0; index < keys.length; index += 1) {
      const key = keys[index];
      if (key.toLowerCase() === target) {
        const value = record[key];
        return typeof value === 'string' ? value.trim() : '';
      }
    }
    return '';
  }

  private buildAuthorizationHeader(): string {
    if (this.config.username.length === 0 && this.config.password.length === 0) {
      return '';
    }
    const token = buffer.from(`${this.config.username}:${this.config.password}`, 'utf8').toString('base64');
    return `Basic ${token}`;
  }

  private toRequestMethod(method: AiraWebdavMethod): http.RequestMethod {
    if (method === 'PUT') {
      return http.RequestMethod.PUT;
    }
    if (method === 'DELETE') {
      return http.RequestMethod.DELETE;
    }
    if (method === 'OPTIONS') {
      return http.RequestMethod.OPTIONS;
    }
    if (method === 'MKCOL') {
      return 'MKCOL' as http.RequestMethod;
    }
    if (method === 'MOVE') {
      return 'MOVE' as http.RequestMethod;
    }
    return http.RequestMethod.GET;
  }

  private assertSuccess(response: AiraWebdavResponse, path: string): void {
    if (response.status >= 200 && response.status < 300) {
      return;
    }
    throw new Error(`WebDAV 请求失败：${path}，HTTP ${response.status}`);
  }

  private assertConfigured(): void {
    if (this.config.endpoint.trim().length <= 0) {
      throw new Error('请先配置 WebDAV 服务。');
    }
  }
}
