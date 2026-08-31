import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AiraCloudBookmarkApiAuthProvider,
  RuntimeAiraCloudBookmarkApiAuthProvider
} from './AiraCloudBookmarkRemoteStore';

const AIRA_CLOUD_CONDITIONAL_SNAPSHOT_TIMEOUT_MS: number = 45000;
const DOMAIN: number = 0x0000;
const TAG: string = 'AiraCloudSnapshot';

export interface AiraCloudConditionalSnapshotRemoteState<T extends Object> {
  snapshot: T | null;
  revision: string;
}

export interface AiraCloudConditionalSnapshotWriteResult {
  revision: string;
}

export interface AiraCloudConditionalSnapshotHttpAdapter {
  post(url: string, body: Object, authorization: string, timeoutMs: number):
    Promise<Object | string | null | undefined>;
}

export interface AiraCloudConditionalSnapshotOptions {
  serviceLabel: string;
  conflictResponseCode: string;
  conflictErrorMessage: string;
  missingUidMessage: string;
}

interface AiraCloudConditionalSnapshotReadRequest {
  uid: string;
  source: string;
}

interface AiraCloudConditionalSnapshotTransportError {
  ok: boolean;
  code: string;
  message: string;
}

interface AiraCloudConditionalSnapshotWriteRequest<T extends Object> {
  uid: string;
  source: string;
  deviceId: string;
  snapshot: T;
  expectedRevision: string;
}

interface AiraCloudConditionalSnapshotResponseBody<T extends Object> {
  ok?: boolean;
  code?: string;
  message?: string;
  snapshot?: T | null;
  revision?: string;
  updatedAt?: number;
  writtenAt?: string;
}

interface AiraCloudConditionalSnapshotResponseEnvelope<T extends Object> {
  body?: Object | string;
  ok?: boolean;
  code?: string;
  message?: string;
  snapshot?: T | null;
  revision?: string;
  updatedAt?: number;
  writtenAt?: string;
}

class NetworkAiraCloudConditionalSnapshotHttpAdapter implements AiraCloudConditionalSnapshotHttpAdapter {
  async post(
    url: string,
    body: Object,
    authorization: string,
    timeoutMs: number
  ): Promise<Object | string | null | undefined> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        usingCache: false,
        header: {
          'Accept': 'application/json',
          'Authorization': authorization,
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': 'AiraBrowser/1.0'
        },
        extraData: JSON.stringify(body)
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const responseBody = `${response.result ?? ''}`.trim();
        if (responseBody.length > 0) {
          return responseBody;
        }
        const failure: AiraCloudConditionalSnapshotTransportError = {
          ok: false,
          code: 'http_error',
          message: `Aira 云同步请求失败（${response.responseCode}）。`
        };
        return failure;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

export class AiraCloudConditionalSnapshotRemoteStore<T extends Object> {
  private readonly endpoint: string;
  private readonly uid: string;
  private readonly options: AiraCloudConditionalSnapshotOptions;
  private readonly authProvider: AiraCloudBookmarkApiAuthProvider;
  private readonly adapter: AiraCloudConditionalSnapshotHttpAdapter;

  constructor(
    endpoint: string,
    uid: string,
    options: AiraCloudConditionalSnapshotOptions,
    authProvider?: AiraCloudBookmarkApiAuthProvider,
    adapter?: AiraCloudConditionalSnapshotHttpAdapter
  ) {
    this.endpoint = endpoint.trim().replace(/\/+$/, '');
    this.uid = uid.trim();
    this.options = options;
    this.authProvider = authProvider ?? new RuntimeAiraCloudBookmarkApiAuthProvider();
    this.adapter = adapter ?? new NetworkAiraCloudConditionalSnapshotHttpAdapter();
  }

  async readState(): Promise<AiraCloudConditionalSnapshotRemoteState<T>> {
    this.assertConfigured();
    const body: AiraCloudConditionalSnapshotReadRequest = {
      uid: this.uid,
      source: 'app'
    };
    const response = await this.post('/read', body);
    return {
      snapshot: response.snapshot === undefined ? null : response.snapshot,
      revision: `${response.revision ?? ''}`.trim()
    };
  }

  async writeSnapshot(
    deviceId: string,
    snapshot: T,
    expectedRevision: string
  ): Promise<AiraCloudConditionalSnapshotWriteResult> {
    this.assertConfigured();
    const body: AiraCloudConditionalSnapshotWriteRequest<T> = {
      uid: this.uid,
      source: 'app',
      deviceId: deviceId,
      snapshot: snapshot,
      expectedRevision: expectedRevision
    };
    const response = await this.post('/write', body);
    return { revision: `${response.revision ?? ''}`.trim() };
  }

  private async post(path: string, body: Object): Promise<AiraCloudConditionalSnapshotResponseBody<T>> {
    const authorization = await this.authProvider.getAuthorizationHeader();
    try {
      const value = await this.adapter.post(
        `${this.endpoint}${path}`,
        body,
        authorization,
        AIRA_CLOUD_CONDITIONAL_SNAPSHOT_TIMEOUT_MS
      );
      const response = this.parseResponseValue(value);
      if (response.ok !== true) {
        if (response.code === this.options.conflictResponseCode) {
          throw new Error(this.options.conflictErrorMessage);
        }
        throw new Error(response.message ??
          `${this.options.serviceLabel}返回失败：${response.code ?? 'unknown'}`);
      }
      return response;
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      hilog.error(DOMAIN, TAG, 'request failed path=%{public}s uid=%{public}s error=%{public}s',
        path,
        this.maskUid(this.uid),
        message);
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(message);
    }
  }

  private parseResponseValue(
    value: Object | string | null | undefined
  ): AiraCloudConditionalSnapshotResponseBody<T> {
    if (value === undefined || value === null) {
      return {
        ok: false,
        code: 'empty_response',
        message: `${this.options.serviceLabel}没有返回结果。`
      };
    }
    if (typeof value === 'string') {
      try {
        return this.parseResponseObject(JSON.parse(value) as Object);
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response',
          message: `${this.options.serviceLabel}返回的 JSON 无法解析。`
        };
      }
    }
    return this.parseResponseObject(value);
  }

  private parseResponseObject(value: Object): AiraCloudConditionalSnapshotResponseBody<T> {
    const raw = value as AiraCloudConditionalSnapshotResponseEnvelope<T>;
    const body = raw.body;
    if (typeof body === 'string') {
      try {
        return JSON.parse(body) as AiraCloudConditionalSnapshotResponseBody<T>;
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response_body',
          message: `${this.options.serviceLabel}返回的 body 无法解析。`
        };
      }
    }
    if (body !== undefined && body !== null && typeof body === 'object') {
      return body as AiraCloudConditionalSnapshotResponseBody<T>;
    }
    return raw as AiraCloudConditionalSnapshotResponseBody<T>;
  }

  private assertConfigured(): void {
    if (this.endpoint.length <= 0) {
      throw new Error(`${this.options.serviceLabel}地址未配置。`);
    }
    if (this.uid.length <= 0) {
      throw new Error(this.options.missingUidMessage);
    }
  }

  private maskUid(uid: string): string {
    const normalized = uid.trim();
    if (normalized.length <= 8) {
      return normalized;
    }
    return `${normalized.slice(0, 4)}...${normalized.slice(normalized.length - 4)}`;
  }
}
