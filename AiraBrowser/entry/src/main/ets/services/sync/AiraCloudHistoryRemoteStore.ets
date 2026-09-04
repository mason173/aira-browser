import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AIRA_HOSTED_API_BASE_URL } from '../../common/config/AiraDistributionCapabilityOwner';
import {
  HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE,
  HISTORY_SYNC_EXCHANGE_BATCH_SIZE,
  HistorySyncBootstrapKey,
  HistorySyncBootstrapResponse,
  HistorySyncChange,
  HistorySyncDeleteRange,
  HistorySyncExchangeResponse,
  HistorySyncMutation,
  HistorySyncMutationAcknowledgement,
  HistorySyncVisit
} from '../../common/models/HistorySyncModels';
import {
  AiraCloudBookmarkApiAuthProvider,
  RuntimeAiraCloudBookmarkApiAuthProvider
} from './AiraCloudBookmarkRemoteStore';

export const AIRA_CLOUD_HISTORY_SYNC_API_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/sync/v1/history';

const DOMAIN: number = 0x0000;
const TAG: string = 'AiraCloudHistory';
const HISTORY_API_TIMEOUT_MS: number = 45000;

export interface HistorySyncExchangeRequest {
  clientId: string;
  cursor: number;
  mutations: HistorySyncMutation[];
  pullLimit: number;
}

export interface HistorySyncBootstrapRequest {
  clientId: string;
  bootstrapHead?: number;
  afterUpdatedSeq?: number;
  afterVisitId?: string;
  pageLimit: number;
}

interface HistorySyncExchangeRequestBody {
  uid: string;
  source: string;
  clientId: string;
  cursor: number;
  mutations: HistorySyncMutation[];
  pullLimit: number;
}

interface HistorySyncBootstrapRequestBody {
  uid: string;
  source: string;
  clientId: string;
  pageLimit: number;
  bootstrapHead?: number;
  afterUpdatedSeq?: number;
  afterVisitId?: string;
}

export interface AiraCloudHistoryRemoteStore {
  exchange(request: HistorySyncExchangeRequest): Promise<HistorySyncExchangeResponse>;
  bootstrap(request: HistorySyncBootstrapRequest): Promise<HistorySyncBootstrapResponse>;
}

export interface AiraCloudHistoryApiHttpAdapter {
  post(url: string, body: Object, authorization: string, timeoutMs: number):
    Promise<Object | string | null | undefined>;
}

interface AiraCloudHistoryApiResponseBody {
  ok?: boolean;
  code?: string;
  message?: string;
  acknowledgements?: HistorySyncMutationAcknowledgement[];
  changes?: HistorySyncChange[];
  nextCursor?: number;
  headCursor?: number;
  hasMore?: boolean;
  bootstrapHead?: number;
  visits?: HistorySyncVisit[];
  deletedVisitIds?: string[];
  clearBefore?: number;
  deleteRanges?: HistorySyncDeleteRange[];
  nextKey?: HistorySyncBootstrapKey | null;
}

interface AiraCloudHistoryApiResponseEnvelope extends AiraCloudHistoryApiResponseBody {
  body?: Object | string;
}

class NetworkAiraCloudHistoryApiHttpAdapter implements AiraCloudHistoryApiHttpAdapter {
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
        return {
          ok: false,
          code: 'http_error',
          message: `Aira 云历史记录同步请求失败（${response.responseCode}）。`
        } as AiraCloudHistoryApiResponseBody;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

export class HistorySyncRemoteError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

export class NetworkAiraCloudHistoryRemoteStore implements AiraCloudHistoryRemoteStore {
  private endpoint: string;
  private uid: string;
  private authProvider: AiraCloudBookmarkApiAuthProvider;
  private adapter: AiraCloudHistoryApiHttpAdapter;

  constructor(
    endpoint: string,
    uid: string,
    authProvider?: AiraCloudBookmarkApiAuthProvider,
    adapter?: AiraCloudHistoryApiHttpAdapter
  ) {
    this.endpoint = endpoint.trim().replace(/\/+$/, '');
    this.uid = uid.trim();
    this.authProvider = authProvider ?? new RuntimeAiraCloudBookmarkApiAuthProvider();
    this.adapter = adapter ?? new NetworkAiraCloudHistoryApiHttpAdapter();
  }

  async exchange(request: HistorySyncExchangeRequest): Promise<HistorySyncExchangeResponse> {
    this.assertConfigured(request.clientId);
    const body: HistorySyncExchangeRequestBody = {
      uid: this.uid,
      source: 'app_history_sync',
      clientId: request.clientId,
      cursor: Math.max(0, Math.floor(request.cursor)),
      mutations: request.mutations,
      pullLimit: Math.min(
        HISTORY_SYNC_EXCHANGE_BATCH_SIZE,
        Math.max(1, Math.floor(request.pullLimit))
      )
    };
    const response = await this.post('/exchange', body);
    const acknowledgements = response.acknowledgements;
    const changes = response.changes;
    if (!Array.isArray(acknowledgements) || !Array.isArray(changes)) {
      throw new HistorySyncRemoteError('invalid_history_exchange', 'Aira 云返回的历史记录增量不完整。');
    }
    return {
      acknowledgements: acknowledgements,
      changes: changes,
      nextCursor: this.requireNonNegativeInteger(response.nextCursor, 'nextCursor'),
      headCursor: this.requireNonNegativeInteger(response.headCursor, 'headCursor'),
      hasMore: response.hasMore === true
    };
  }

  async bootstrap(request: HistorySyncBootstrapRequest): Promise<HistorySyncBootstrapResponse> {
    this.assertConfigured(request.clientId);
    const body: HistorySyncBootstrapRequestBody = {
      uid: this.uid,
      source: 'app_history_sync',
      clientId: request.clientId,
      pageLimit: Math.min(
        HISTORY_SYNC_BOOTSTRAP_PAGE_SIZE,
        Math.max(1, Math.floor(request.pageLimit))
      )
    };
    if (request.bootstrapHead !== undefined && request.bootstrapHead > 0) {
      body.bootstrapHead = Math.floor(request.bootstrapHead);
    }
    if (request.afterUpdatedSeq !== undefined && request.afterUpdatedSeq > 0) {
      body.afterUpdatedSeq = Math.floor(request.afterUpdatedSeq);
      body.afterVisitId = request.afterVisitId ?? '';
    }
    const response = await this.post('/bootstrap', body);
    const visits = response.visits;
    const deletedVisitIds = response.deletedVisitIds;
    const deleteRanges = response.deleteRanges;
    if (!Array.isArray(visits) || !Array.isArray(deletedVisitIds) || !Array.isArray(deleteRanges)) {
      throw new HistorySyncRemoteError('invalid_history_bootstrap', 'Aira 云返回的历史记录初始化数据不完整。');
    }
    const nextKey = response.nextKey ?? undefined;
    if (response.hasMore === true &&
      (nextKey === undefined || nextKey.visitId.trim().length <= 0 || nextKey.updatedSeq <= 0)) {
      throw new HistorySyncRemoteError('invalid_history_bootstrap', 'Aira 云返回的历史记录分页位置无效。');
    }
    return {
      bootstrapHead: this.requireNonNegativeInteger(response.bootstrapHead, 'bootstrapHead'),
      headCursor: this.requireNonNegativeInteger(response.headCursor, 'headCursor'),
      visits: visits,
      deletedVisitIds: deletedVisitIds,
      clearBefore: this.requireNonNegativeInteger(response.clearBefore, 'clearBefore'),
      deleteRanges: deleteRanges,
      nextKey: nextKey,
      hasMore: response.hasMore === true
    };
  }

  private async post(path: string, body: Object): Promise<AiraCloudHistoryApiResponseBody> {
    const authorization = await this.authProvider.getAuthorizationHeader(this.uid);
    try {
      const value = await this.adapter.post(
        `${this.endpoint}${path}`,
        body,
        authorization,
        HISTORY_API_TIMEOUT_MS
      );
      const response = this.parseResponseValue(value);
      if (response.ok !== true) {
        throw new HistorySyncRemoteError(
          (response.code ?? 'history_sync_failed').trim(),
          response.message ?? 'Aira 云历史记录同步暂时失败。'
        );
      }
      return response;
    } catch (error) {
      const normalizedError = error instanceof Error
        ? error
        : new HistorySyncRemoteError('history_sync_failed', JSON.stringify(error));
      const message = normalizedError.message;
      hilog.error(
        DOMAIN,
        TAG,
        'request failed path=%{public}s uid=%{public}s error=%{public}s',
        path,
        this.maskUid(this.uid),
        message
      );
      throw normalizedError;
    }
  }

  private parseResponseValue(value: Object | string | null | undefined): AiraCloudHistoryApiResponseBody {
    if (value === undefined || value === null) {
      return {
        ok: false,
        code: 'empty_response',
        message: 'Aira 云历史记录同步没有返回结果。'
      };
    }
    if (typeof value === 'string') {
      try {
        return this.parseResponseObject(JSON.parse(value) as Object);
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response',
          message: 'Aira 云历史记录同步返回的 JSON 无法解析。'
        };
      }
    }
    return this.parseResponseObject(value);
  }

  private parseResponseObject(value: Object): AiraCloudHistoryApiResponseBody {
    const raw = value as AiraCloudHistoryApiResponseEnvelope;
    if (typeof raw.body === 'string') {
      try {
        return JSON.parse(raw.body) as AiraCloudHistoryApiResponseBody;
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response_body',
          message: 'Aira 云历史记录同步返回的 body 无法解析。'
        };
      }
    }
    if (raw.body !== undefined && raw.body !== null && typeof raw.body === 'object') {
      return raw.body as AiraCloudHistoryApiResponseBody;
    }
    return raw;
  }

  private assertConfigured(clientId: string): void {
    if (this.endpoint.length <= 0) {
      throw new HistorySyncRemoteError('history_endpoint_missing', 'Aira 云历史记录同步地址未配置。');
    }
    if (this.uid.length <= 0) {
      throw new HistorySyncRemoteError('history_account_missing', '请先登录华为账号再同步历史记录。');
    }
    if (!/^[A-Za-z0-9._-]{1,160}$/.test(clientId.trim())) {
      throw new HistorySyncRemoteError('history_client_invalid', '本机历史记录同步标识无效。');
    }
  }

  private requireNonNegativeInteger(value: number | undefined, field: string): number {
    if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
      throw new HistorySyncRemoteError('invalid_history_response', `Aira 云返回的 ${field} 无效。`);
    }
    return value;
  }

  private maskUid(uid: string): string {
    const normalized = uid.trim();
    if (normalized.length <= 8) {
      return normalized;
    }
    return `${normalized.slice(0, 4)}...${normalized.slice(normalized.length - 4)}`;
  }
}

export function createAiraCloudHistoryRemoteStore(uid: string): AiraCloudHistoryRemoteStore {
  return new NetworkAiraCloudHistoryRemoteStore(AIRA_CLOUD_HISTORY_SYNC_API_ENDPOINT, uid);
}
