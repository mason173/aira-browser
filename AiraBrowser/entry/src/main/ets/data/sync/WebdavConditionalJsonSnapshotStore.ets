import http from '@ohos.net.http';
import buffer from '@ohos.buffer';
import { AiraSyncWebdavConfig } from '../../common/models/AiraSyncModels';

type WebdavConditionalJsonMethod = 'GET' | 'PUT' | 'DELETE' | 'MKCOL' | 'MOVE' | 'LOCK' | 'UNLOCK';
type WebdavConditionalJsonCreateMode = 'if-none-match' | 'move-no-overwrite' | 'lock-serialized';
type WebdavConditionalJsonRevisionCondition = 'if-match' | 'webdav-if';

interface WebdavConditionalJsonWriteSupport {
  createMode: WebdavConditionalJsonCreateMode;
  weakEtagIfVerified: boolean;
  lockSerialized: boolean;
}

interface WebdavConditionalJsonResponse {
  status: number;
  body: string;
  headers: Record<string, string>;
}

const WEBDAV_CONDITIONAL_JSON_TIMEOUT_MS: number = 20000;
const WEBDAV_LOCK_TIMEOUT_SECONDS: number = 120;
const WEBDAV_LOCK_REQUEST_BODY: string =
  '<?xml version="1.0" encoding="utf-8"?>' +
  '<D:lockinfo xmlns:D="DAV:"><D:lockscope><D:exclusive/></D:lockscope>' +
  '<D:locktype><D:write/></D:locktype><D:owner><D:href>aira</D:href></D:owner></D:lockinfo>';
const VERIFIED_CONDITIONAL_JSON_WRITE_PROVIDERS:
  Map<string, WebdavConditionalJsonWriteSupport> =
  new Map<string, WebdavConditionalJsonWriteSupport>();

export interface WebdavConditionalJsonSnapshotOptions<T extends Object> {
  rootPath: string;
  filePath: string;
  sourceLabel: string;
  operationLabel: string;
  writeConflictError: string;
  parse: (payload: string, sourceLabel: string) => T;
}

export interface WebdavConditionalJsonRemoteState<T extends Object> {
  snapshot: T | null;
  revision: string;
}

export class WebdavConditionalJsonSnapshotStore<T extends Object> {
  private config: AiraSyncWebdavConfig;
  private options: WebdavConditionalJsonSnapshotOptions<T>;

  constructor(config: AiraSyncWebdavConfig, options: WebdavConditionalJsonSnapshotOptions<T>) {
    this.config = config;
    this.options = options;
  }

  async readState(): Promise<WebdavConditionalJsonRemoteState<T>> {
    this.assertConfigured();
    let response = await this.request('GET', this.options.filePath);
    if (response.status === 409) {
      await this.ensureRemoteLayout();
      response = await this.request('GET', this.options.filePath);
    }
    if (response.status === 404) {
      return { snapshot: null, revision: '' };
    }
    this.assertSuccess(response, this.options.filePath);
    return {
      snapshot: this.parseSnapshot(response.body),
      revision: this.headerValue(response.headers, 'etag')
    };
  }

  async writeSnapshot(
    _deviceId: string,
    snapshot: T,
    expectedRevision: string
  ): Promise<string> {
    this.assertConfigured();
    await this.ensureRemoteLayout();
    const conditionalWriteSupport = await this.ensureConditionalWriteSupport();
    const createMode = conditionalWriteSupport.createMode;
    let response: WebdavConditionalJsonResponse;
    if (conditionalWriteSupport.lockSerialized) {
      response = await this.writeSnapshotWithLock(
        this.options.filePath,
        JSON.stringify(snapshot),
        expectedRevision.trim()
      );
    } else if (expectedRevision.trim().length <= 0 && createMode === 'move-no-overwrite') {
      response = await this.createWithMoveNoOverwrite(
        this.options.filePath,
        JSON.stringify(snapshot)
      );
    } else {
      let conditionalHeaders: Record<string, string>;
      if (expectedRevision.trim().length > 0) {
        conditionalHeaders = this.buildRevisionCondition(
          expectedRevision.trim(),
          this.verifiedRevisionCondition(expectedRevision.trim(), conditionalWriteSupport)
        );
      } else {
        conditionalHeaders = { 'If-None-Match': '*' };
      }
      response = await this.request(
        'PUT',
        this.options.filePath,
        JSON.stringify(snapshot),
        conditionalHeaders
      );
    }
    if (response.status === 409 || response.status === 412) {
      throw new Error(this.options.writeConflictError);
    }
    this.assertSuccess(response, this.options.filePath);
    let revision = this.headerValue(response.headers, 'etag');
    if (revision.length <= 0) {
      const readBack = await this.request('GET', this.options.filePath);
      this.assertSuccess(readBack, this.options.filePath);
      const readBackSnapshot = this.parseSnapshot(readBack.body);
      if (JSON.stringify(readBackSnapshot) !== JSON.stringify(snapshot)) {
        throw new Error(`WebDAV ${this.options.operationLabel}写入后回读内容不一致。`);
      }
      revision = this.headerValue(readBack.headers, 'etag');
    }
    if (revision.length <= 0) {
      throw new Error(`WebDAV ${this.options.operationLabel}未返回 ETag，无法安全确认写入。`);
    }
    return revision;
  }

  /**
   * Publishes the snapshot under an exclusive WebDAV lock. Providers such as OpenList ignore
   * `If-None-Match`, `If-Match`, and `MOVE Overwrite: F`, leaving the lock as the only mutual-exclusion
   * primitive. Re-reading under the lock re-establishes compare-and-swap: the write proceeds only when
   * the remote revision still matches the one the caller merged against.
   */
  private async writeSnapshotWithLock(
    path: string,
    body: string,
    expectedRevision: string
  ): Promise<WebdavConditionalJsonResponse> {
    const lock = await this.requestLock(path);
    if (lock.status < 200 || lock.status >= 300) {
      throw new Error(`WebDAV ${this.options.operationLabel}获取写入锁失败：HTTP ${lock.status}`);
    }
    const token = this.normalizeLockToken(this.headerValue(lock.headers, 'lock-token'));
    if (token.length <= 0) {
      throw new Error(`WebDAV ${this.options.operationLabel}写入锁缺少 Lock-Token，无法安全写入。`);
    }
    try {
      const current = await this.readState();
      const currentRevision = current.revision.trim();
      if (expectedRevision.length <= 0) {
        if (current.snapshot !== null) {
          throw new Error(this.options.writeConflictError);
        }
      } else if (currentRevision !== expectedRevision) {
        throw new Error(this.options.writeConflictError);
      }
      const written = await this.request('PUT', path, body, {
        'If': this.buildLockIfHeader(token)
      });
      if (written.status === 409 || written.status === 412 || written.status === 423) {
        throw new Error(this.options.writeConflictError);
      }
      this.assertSuccess(written, path);
      const readBack = await this.request('GET', path);
      this.assertSuccess(readBack, path);
      if (readBack.body !== body) {
        throw new Error(`WebDAV ${this.options.operationLabel}写入后回读内容不一致。`);
      }
      return readBack;
    } finally {
      await this.requestUnlock(path, token).catch((_error: Error): void => {});
    }
  }

  private async requestLock(path: string): Promise<WebdavConditionalJsonResponse> {
    const request = http.createHttp();
    try {
      const response = await request.request(this.buildUrl(path), {
        method: 'LOCK' as http.RequestMethod,
        extraData: WEBDAV_LOCK_REQUEST_BODY,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: WEBDAV_CONDITIONAL_JSON_TIMEOUT_MS,
        readTimeout: WEBDAV_CONDITIONAL_JSON_TIMEOUT_MS,
        header: {
          'Accept': 'application/xml,text/xml,*/*',
          'Authorization': this.buildAuthorizationHeader(),
          'Content-Type': 'application/xml; charset=utf-8',
          'Timeout': `Second-${WEBDAV_LOCK_TIMEOUT_SECONDS}`,
          'Depth': '0'
        } as Record<string, string>
      });
      return {
        status: response.responseCode,
        body: typeof response.result === 'string' ? response.result : '',
        headers: this.normalizeHeaders(response.header)
      };
    } finally {
      request.destroy();
    }
  }

  private async requestUnlock(path: string, token: string): Promise<WebdavConditionalJsonResponse> {
    const request = http.createHttp();
    try {
      const response = await request.request(this.buildUrl(path), {
        method: 'UNLOCK' as http.RequestMethod,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: WEBDAV_CONDITIONAL_JSON_TIMEOUT_MS,
        readTimeout: WEBDAV_CONDITIONAL_JSON_TIMEOUT_MS,
        header: {
          'Accept': 'application/json,text/plain,*/*',
          'Authorization': this.buildAuthorizationHeader(),
          'Lock-Token': `<${token}>`
        } as Record<string, string>
      });
      return {
        status: response.responseCode,
        body: typeof response.result === 'string' ? response.result : '',
        headers: this.normalizeHeaders(response.header)
      };
    } finally {
      request.destroy();
    }
  }

  private normalizeLockToken(rawToken: string): string {
    let token = rawToken.trim();
    if (token.length >= 2 && token.indexOf('<') === 0 && token.lastIndexOf('>') === token.length - 1) {
      token = token.slice(1, token.length - 1).trim();
    }
    return token;
  }

  private buildLockIfHeader(token: string): string {
    return `(<${token}>)`;
  }

  private async createWithMoveNoOverwrite(
    path: string,
    body: string
  ): Promise<WebdavConditionalJsonResponse> {
    const suffix = `${Date.now().toString(36)}-${Math.floor(Math.random() * 0x100000000).toString(36)}`;
    const tempPath = `${path}.create-${suffix}.tmp`;
    try {
      const upload = await this.request('PUT', tempPath, body);
      this.assertSuccess(upload, tempPath);
      return await this.requestMove(tempPath, path, false);
    } finally {
      await this.request('DELETE', tempPath).catch((_error: Error): void => {});
    }
  }

  private async requestMove(
    sourcePath: string,
    destinationPath: string,
    overwrite: boolean
  ): Promise<WebdavConditionalJsonResponse> {
    const request = http.createHttp();
    try {
      const response = await request.request(this.buildUrl(sourcePath), {
        method: 'MOVE' as http.RequestMethod,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: WEBDAV_CONDITIONAL_JSON_TIMEOUT_MS,
        readTimeout: WEBDAV_CONDITIONAL_JSON_TIMEOUT_MS,
        header: {
          'Accept': 'application/json,text/plain,*/*',
          'Authorization': this.buildAuthorizationHeader(),
          'Destination': this.buildUrl(destinationPath),
          'Overwrite': overwrite ? 'T' : 'F'
        } as Record<string, string>
      });
      return {
        status: response.responseCode,
        body: typeof response.result === 'string' ? response.result : '',
        headers: this.normalizeHeaders(response.header)
      };
    } finally {
      request.destroy();
    }
  }

  private async ensureConditionalWriteSupport(): Promise<WebdavConditionalJsonWriteSupport> {
    const providerKey = this.conditionalWriteProviderKey();
    const verifiedMode = VERIFIED_CONDITIONAL_JSON_WRITE_PROVIDERS.get(providerKey);
    if (verifiedMode !== undefined) {
      return verifiedMode;
    }
    const probeId = `${Date.now().toString(36)}-${Math.floor(Math.random() * 0x100000000).toString(36)}`;
    const probePath = `${this.options.rootPath}/cas-probe-${probeId}.json`;
    let conditionalSupport: WebdavConditionalJsonWriteSupport | null = null;
    let conditionalError: Error | null = null;
    try {
      conditionalSupport = await this.verifyConditionalWriteSupport(probePath, probeId);
    } catch (error) {
      conditionalError = error as Error;
    }
    if (conditionalSupport !== null) {
      VERIFIED_CONDITIONAL_JSON_WRITE_PROVIDERS.set(providerKey, conditionalSupport);
      return conditionalSupport;
    }
    try {
      await this.verifyLockSerializedSupport(probeId);
    } catch (_lockError) {
      throw conditionalError ?? new Error(`WebDAV 服务不支持安全${this.options.operationLabel}。`);
    }
    const lockSupport: WebdavConditionalJsonWriteSupport = {
      createMode: 'lock-serialized',
      weakEtagIfVerified: false,
      lockSerialized: true
    };
    VERIFIED_CONDITIONAL_JSON_WRITE_PROVIDERS.set(providerKey, lockSupport);
    return lockSupport;
  }

  private async verifyConditionalWriteSupport(
    probePath: string,
    probeId: string
  ): Promise<WebdavConditionalJsonWriteSupport> {
    try {
      let first = await this.request('PUT', probePath, '{"step":1}', { 'If-None-Match': '*' });
      let createMode: WebdavConditionalJsonCreateMode = 'if-none-match';
      if (first.status === 409 || first.status === 412) {
        const probeReadAfterRejectedCreate = await this.request('GET', probePath);
        if (probeReadAfterRejectedCreate.status !== 404) {
          if (probeReadAfterRejectedCreate.status >= 200 && probeReadAfterRejectedCreate.status < 300) {
            throw new Error(
              `WebDAV 服务拒绝首次条件写入，但${this.options.operationLabel}探测文件实际存在，无法安全判断首次写入能力。`
            );
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
      let etag = this.headerValue(read.headers, 'etag');
      if (etag.length <= 0) {
        throw new Error(`WebDAV 服务未提供 ETag，不支持安全${this.options.operationLabel}。`);
      }
      const duplicateCreate = await this.request('PUT', probePath, '{"step":2}', { 'If-None-Match': '*' });
      if (duplicateCreate.status !== 409 && duplicateCreate.status !== 412) {
        this.assertSuccess(duplicateCreate, probePath);
        read = await this.request('GET', probePath);
        this.assertSuccess(read, probePath);
        etag = this.headerValue(read.headers, 'etag');
        if (etag.length <= 0) {
          throw new Error(`WebDAV 服务未提供 ETag，不支持安全${this.options.operationLabel}。`);
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
        throw new Error(`WebDAV 服务忽略条件版本，不支持安全${this.options.operationLabel}。`);
      }
      const support: WebdavConditionalJsonWriteSupport = {
        createMode,
        weakEtagIfVerified: revisionCondition === 'webdav-if',
        lockSerialized: false
      };
      return support;
    } finally {
      await this.request('DELETE', probePath).catch((_error: Error): void => {});
    }
  }

  /**
   * Verifies that the provider can serialize a publication with an exclusive lock even though it
   * ignores the HTTP conditional headers. Every step mirrors a real write: the lock must be granted
   * on an absent path, exclude a competing lock and an unauthenticated write, admit the token-holding
   * write, expose a validator, and release cleanly. A provider that fails any step stays fail-closed.
   */
  private async verifyLockSerializedSupport(probeId: string): Promise<void> {
    const probePath = `${this.options.rootPath}/lock-probe-${probeId}.json`;
    const body = '{"lock":1}';
    let lockToken = '';
    try {
      await this.request('DELETE', probePath).catch((_error: Error): void => {});
      const lock = await this.requestLock(probePath);
      if (lock.status < 200 || lock.status >= 300) {
        throw new Error(`WebDAV 服务不支持 LOCK 写入（HTTP ${lock.status}）。`);
      }
      lockToken = this.normalizeLockToken(this.headerValue(lock.headers, 'lock-token'));
      if (lockToken.length <= 0) {
        throw new Error('WebDAV 服务未返回 Lock-Token，不支持安全首次写入。');
      }
      const competingLock = await this.requestLock(probePath);
      if (competingLock.status !== 423 && competingLock.status !== 409) {
        throw new Error(`WebDAV 服务未独占加锁，不支持安全首次写入（HTTP ${competingLock.status}）。`);
      }
      const unauthenticatedWrite = await this.request('PUT', probePath, body);
      if (unauthenticatedWrite.status !== 423 && unauthenticatedWrite.status !== 409) {
        throw new Error(`WebDAV 服务未阻止无锁写入，不支持安全首次写入（HTTP ${unauthenticatedWrite.status}）。`);
      }
      const authorizedWrite = await this.request('PUT', probePath, body, {
        'If': this.buildLockIfHeader(lockToken)
      });
      this.assertSuccess(authorizedWrite, probePath);
      const read = await this.request('GET', probePath);
      this.assertSuccess(read, probePath);
      if (read.body !== body || this.headerValue(read.headers, 'etag').length <= 0) {
        throw new Error(`WebDAV 服务无法确认加锁写入结果，不支持安全${this.options.operationLabel}。`);
      }
      const unlock = await this.requestUnlock(probePath, lockToken);
      if (unlock.status < 200 || unlock.status >= 300) {
        throw new Error(`WebDAV 服务无法释放写入锁（HTTP ${unlock.status}）。`);
      }
      lockToken = '';
      const afterUnlock = await this.request('PUT', probePath, '{"unlocked":1}');
      this.assertSuccess(afterUnlock, probePath);
    } finally {
      if (lockToken.length > 0) {
        await this.requestUnlock(probePath, lockToken).catch((_error: Error): void => {});
      }
      await this.request('DELETE', probePath).catch((_error: Error): void => {});
    }
  }

  private async verifyMoveNoOverwriteSupport(probeId: string): Promise<void> {
    const sourcePath = `${this.options.rootPath}/move-probe-${probeId}-source.json`;
    const destinationPath = `${this.options.rootPath}/move-probe-${probeId}-destination.json`;
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
      await this.request('DELETE', sourcePath).catch((_error: Error): void => {});
      await this.request('DELETE', destinationPath).catch((_error: Error): void => {});
      const createSource = await this.request('PUT', sourcePath, movedBody);
      this.assertSuccess(createSource, sourcePath);
      const acceptedMove = await this.requestMove(sourcePath, destinationPath, false);
      this.assertSuccess(acceptedMove, destinationPath);
      const moved = await this.request('GET', destinationPath);
      this.assertSuccess(moved, destinationPath);
      if (moved.body !== movedBody || this.headerValue(moved.headers, 'etag').length <= 0) {
        throw new Error(`WebDAV 服务无法确认 MOVE 首次写入结果，不支持安全${this.options.operationLabel}。`);
      }
    } finally {
      await this.request('DELETE', sourcePath).catch((_error: Error): void => {});
      await this.request('DELETE', destinationPath).catch((_error: Error): void => {});
    }
  }

  private revisionConditionForEtag(etag: string): WebdavConditionalJsonRevisionCondition {
    return etag.indexOf('W/') === 0 ? 'webdav-if' : 'if-match';
  }

  private buildRevisionCondition(
    etag: string,
    revisionCondition: WebdavConditionalJsonRevisionCondition
  ): Record<string, string> {
    if (revisionCondition === 'webdav-if') {
      return { 'If': `([${etag}])` };
    }
    return { 'If-Match': etag };
  }

  private verifiedRevisionCondition(
    etag: string,
    support: WebdavConditionalJsonWriteSupport
  ): WebdavConditionalJsonRevisionCondition {
    const revisionCondition = this.revisionConditionForEtag(etag);
    if (revisionCondition === 'webdav-if' && !support.weakEtagIfVerified) {
      throw new Error(`WebDAV 服务未验证弱 ETag 条件能力，无法安全写入${this.options.operationLabel}快照。`);
    }
    return revisionCondition;
  }

  private conditionalWriteProviderKey(): string {
    return [
      this.config.endpoint.trim().replace(/\/+$/, ''),
      this.config.username.trim(),
      this.options.rootPath
    ].join('|');
  }

  private parseSnapshot(payload: string): T {
    return this.options.parse(payload, this.options.sourceLabel);
  }

  private async ensureCollection(path: string): Promise<void> {
    const response = await this.request('MKCOL', path);
    if ((response.status >= 200 && response.status < 300) || response.status === 405) {
      return;
    }
    throw new Error(`WebDAV ${this.options.operationLabel}目录创建失败：${path}，HTTP ${response.status}`);
  }

  private async ensureRemoteLayout(): Promise<void> {
    await this.ensureCollection('aira');
    await this.ensureCollection('aira/g2');
    await this.ensureCollection(this.options.rootPath);
  }

  private async request(
    method: WebdavConditionalJsonMethod,
    path: string,
    body?: string,
    additionalHeaders: Record<string, string> = {}
  ): Promise<WebdavConditionalJsonResponse> {
    const request = http.createHttp();
    try {
      const response = await request.request(this.buildUrl(path), {
        method: this.toRequestMethod(method),
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: WEBDAV_CONDITIONAL_JSON_TIMEOUT_MS,
        readTimeout: WEBDAV_CONDITIONAL_JSON_TIMEOUT_MS,
        header: this.buildHeaders(body !== undefined, additionalHeaders)
      });
      return {
        status: response.responseCode,
        body: typeof response.result === 'string' ? response.result : '',
        headers: this.normalizeHeaders(response.header)
      };
    } finally {
      request.destroy();
    }
  }

  private buildUrl(path: string): string {
    const endpoint = this.config.endpoint.trim().replace(/\/+$/, '');
    return `${endpoint}/${path.trim().replace(/^\/+/, '')}`;
  }

  private buildHeaders(hasBody: boolean, additionalHeaders: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'application/json,text/plain,*/*',
      'Authorization': this.buildAuthorizationHeader()
    };
    if (hasBody) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    const keys = Object.keys(additionalHeaders);
    for (let index = 0; index < keys.length; index += 1) {
      headers[keys[index]] = additionalHeaders[keys[index]];
    }
    return headers;
  }

  private normalizeHeaders(rawHeaders: Object | undefined): Record<string, string> {
    const headers: Record<string, string> = {};
    if (rawHeaders === undefined || rawHeaders === null) {
      return headers;
    }
    const source = rawHeaders as Record<string, Object>;
    const keys = Object.keys(source);
    for (let index = 0; index < keys.length; index += 1) {
      const value = source[keys[index]];
      if (value !== undefined && value !== null) {
        headers[keys[index]] = String(value);
      }
    }
    return headers;
  }

  private headerValue(headers: Record<string, string>, name: string): string {
    const expected = name.trim().toLowerCase();
    const keys = Object.keys(headers);
    for (let index = 0; index < keys.length; index += 1) {
      if (keys[index].trim().toLowerCase() === expected) {
        return headers[keys[index]].trim();
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

  private toRequestMethod(method: WebdavConditionalJsonMethod): http.RequestMethod {
    if (method === 'PUT') {
      return http.RequestMethod.PUT;
    }
    if (method === 'MKCOL') {
      return 'MKCOL' as http.RequestMethod;
    }
    if (method === 'DELETE') {
      return http.RequestMethod.DELETE;
    }
    if (method === 'MOVE') {
      return 'MOVE' as http.RequestMethod;
    }
    if (method === 'LOCK') {
      return 'LOCK' as http.RequestMethod;
    }
    if (method === 'UNLOCK') {
      return 'UNLOCK' as http.RequestMethod;
    }
    return http.RequestMethod.GET;
  }

  private assertSuccess(response: WebdavConditionalJsonResponse, path: string): void {
    if (response.status >= 200 && response.status < 300) {
      return;
    }
    throw new Error(`WebDAV ${this.options.operationLabel}请求失败：${path}，HTTP ${response.status}`);
  }

  private assertConfigured(): void {
    if (this.config.endpoint.trim().length <= 0) {
      throw new Error('请先配置 WebDAV 服务。');
    }
  }
}
