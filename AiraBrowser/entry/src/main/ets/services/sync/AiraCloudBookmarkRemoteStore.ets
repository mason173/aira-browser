import auth from '@hw-agconnect/auth';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { AIRA_HOSTED_API_BASE_URL } from '../../common/config/AiraDistributionCapabilityOwner';
import {
  AiraBookmarkHistoryDescriptor,
  AiraSyncRemoteHead,
  AiraSyncRemoteState,
  AiraSyncRemoteStore,
  AiraSyncSnapshot,
  AiraSyncWriteStateParams,
  AiraSyncWriteStateResult
} from '../../common/models/AiraSyncModels';
import { HuaweiCloudSyncInitService } from './HuaweiCloudSyncInitService';
import { AiraBookmarkSnapshotValidationService } from './AiraBookmarkSnapshotValidationService';
import { AiraBookmarkTombstoneLifecycleService } from './AiraBookmarkTombstoneLifecycleService';

export const AIRA_CLOUD_BOOKMARK_SYNC_API_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/sync/v3/bookmarks';

const AIRA_CLOUD_BOOKMARK_API_TIMEOUT_MS: number = 45000;
export const AIRA_CLOUD_BOOKMARK_API_LARGE_PAYLOAD_TIMEOUT_MS: number = 600000;
const AIRA_CLOUD_BOOKMARK_API_LOG_DOMAIN: number = 0x0000;
const AIRA_CLOUD_BOOKMARK_API_LOG_TAG: string = 'AiraCloudBookmark';
const sharedHuaweiBookmarkSyncInitService: HuaweiCloudSyncInitService = new HuaweiCloudSyncInitService();

export interface AiraCloudBookmarkApiReadRequest {
  uid: string;
  source: string;
}

export interface AiraCloudBookmarkApiHeadRequest {
  uid: string;
  source: string;
}

export interface AiraCloudBookmarkApiWriteRequest {
  uid: string;
  source: string;
  deviceId: string;
  parentCommitId: string | null;
  createdAt: string;
  history: AiraBookmarkHistoryDescriptor;
  snapshot?: AiraSyncSnapshot;
}

export interface AiraCloudBookmarkApiResponseBody {
  ok?: boolean;
  code?: string;
  message?: string;
  snapshot?: AiraSyncSnapshot | null;
  history?: AiraBookmarkHistoryDescriptor | null;
  commitId?: string | null;
  updatedAt?: number;
  bookmarkFolders?: number;
  bookmarkItems?: number;
  writtenAt?: string;
}

interface AiraCloudBookmarkApiResponseEnvelope {
  body?: Object | string;
  ok?: boolean;
  code?: string;
  message?: string;
  snapshot?: AiraSyncSnapshot | null;
  history?: AiraBookmarkHistoryDescriptor | null;
  commitId?: string | null;
  updatedAt?: number;
  bookmarkFolders?: number;
  bookmarkItems?: number;
  writtenAt?: string;
}

export interface AiraCloudBookmarkApiAuthProvider {
  getAuthorizationHeader(): Promise<string>;
}

export interface HuaweiBookmarkSyncAuthInitializer {
  initializeAuth(): Promise<void>;
}

export interface HuaweiBookmarkSyncToken {
  tokenString: string;
  expiration: number;
}

export interface HuaweiBookmarkSyncTokenProvider {
  getToken(forceRefresh: boolean): Promise<HuaweiBookmarkSyncToken>;
}

export interface AiraCloudBookmarkApiHttpAdapter {
  post(url: string, body: Object, authorization: string, timeoutMs: number):
    Promise<Object | string | null | undefined>;
}

class RuntimeHuaweiBookmarkSyncAuthInitializer implements HuaweiBookmarkSyncAuthInitializer {
  initializeAuth(): Promise<void> {
    return sharedHuaweiBookmarkSyncInitService.initializeAuth(
      AppRuntimeContext.getUIAbilityContext()
    );
  }
}

class AgcHuaweiBookmarkSyncTokenProvider implements HuaweiBookmarkSyncTokenProvider {
  async getToken(forceRefresh: boolean): Promise<HuaweiBookmarkSyncToken> {
    const user = await auth.getCurrentUser();
    if (user === null) {
      throw new Error('No AGC user signed in.');
    }
    const token = await user.getToken(forceRefresh);
    return {
      tokenString: token.getString(),
      expiration: token.getExpirePeriod()
    };
  }
}

export class RuntimeAiraCloudBookmarkApiAuthProvider implements AiraCloudBookmarkApiAuthProvider {
  private initializer: HuaweiBookmarkSyncAuthInitializer;
  private tokenProvider: HuaweiBookmarkSyncTokenProvider;

  constructor(
    initializer?: HuaweiBookmarkSyncAuthInitializer,
    tokenProvider?: HuaweiBookmarkSyncTokenProvider
  ) {
    this.initializer = initializer ?? new RuntimeHuaweiBookmarkSyncAuthInitializer();
    this.tokenProvider = tokenProvider ?? new AgcHuaweiBookmarkSyncTokenProvider();
  }

  async getAuthorizationHeader(): Promise<string> {
    await this.initializer.initializeAuth();
    const token = await this.tokenProvider.getToken(true);
    const tokenString = token.tokenString.trim();
    if (tokenString.length <= 0) {
      throw new Error('华为账号登录凭证为空，请重新登录后再开启书签同步。');
    }
    return `Bearer ${tokenString}`;
  }
}

class NetworkAiraCloudBookmarkApiHttpAdapter implements AiraCloudBookmarkApiHttpAdapter {
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
        const errorResponse: AiraCloudBookmarkApiResponseBody = {
          ok: false,
          code: 'http_error',
          message: `Aira 云同步服务请求失败（${response.responseCode}）。`
        };
        return errorResponse;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

export class AiraCloudBookmarkRemoteStore implements AiraSyncRemoteStore {
  private endpoint: string;
  private uid: string;
  private authProvider: AiraCloudBookmarkApiAuthProvider;
  private adapter: AiraCloudBookmarkApiHttpAdapter;
  private snapshotValidationService: AiraBookmarkSnapshotValidationService =
    new AiraBookmarkSnapshotValidationService();
  private historyService: AiraBookmarkTombstoneLifecycleService =
    new AiraBookmarkTombstoneLifecycleService();
  constructor(
    endpoint: string,
    uid: string,
    authProvider?: AiraCloudBookmarkApiAuthProvider,
    adapter?: AiraCloudBookmarkApiHttpAdapter
  ) {
    this.endpoint = endpoint.trim().replace(/\/+$/, '');
    this.uid = uid.trim();
    this.authProvider = authProvider ?? new RuntimeAiraCloudBookmarkApiAuthProvider();
    this.adapter = adapter ?? new NetworkAiraCloudBookmarkApiHttpAdapter();
  }

  async readState(): Promise<AiraSyncRemoteState> {
    this.assertConfigured();
    const body: AiraCloudBookmarkApiReadRequest = {
      uid: this.uid,
      source: 'app'
    };
    const response = await this.post('/read', body);
    const commitId = `${response.commitId ?? ''}`.trim();
    const snapshot = response.snapshot ?? null;
    const history = response.history ?? null;
    if ((commitId.length <= 0) !== (snapshot === null) ||
      (snapshot === null) !== (history === null)) {
      throw new Error('Aira 云书签同步状态不完整。');
    }
    if (snapshot !== null && history !== null) {
      const validatedSnapshot = this.snapshotValidationService.validate(snapshot, 'Aira 云');
      const validatedHistory = this.historyService.validateHistory(history, 'Aira 云书签墓碑历史纪元');
      this.historyService.assertSnapshotWithinHistory(validatedSnapshot, validatedHistory, 'Aira 云');
      return {
        snapshot: validatedSnapshot,
        commitId: commitId,
        history: validatedHistory
      };
    }
    return {
      snapshot: null,
      commitId: null,
      history: null
    };
  }

  async readHead(): Promise<AiraSyncRemoteHead> {
    this.assertConfigured();
    const body: AiraCloudBookmarkApiHeadRequest = {
      uid: this.uid,
      source: 'app'
    };
    const response = await this.post('/head', body);
    const bookmarkFolders = this.normalizeOptionalCount(response.bookmarkFolders);
    const bookmarkItems = this.normalizeOptionalCount(response.bookmarkItems);
    return {
      commitId: response.commitId === undefined ? null : response.commitId,
      updatedAt: typeof response.updatedAt === 'number' ? response.updatedAt : 0,
      bookmarkFolders: bookmarkFolders,
      bookmarkItems: bookmarkItems,
      hasBookmarkSummary: bookmarkFolders >= 0 && bookmarkItems >= 0
    };
  }

  async writeState(params: AiraSyncWriteStateParams): Promise<AiraSyncWriteStateResult> {
    this.assertConfigured();
    const snapshot = this.snapshotValidationService.validate(params.snapshot, 'Aira 云');
    const history = this.historyService.validateHistory(params.history, 'Aira 云书签墓碑历史纪元');
    this.historyService.assertSnapshotWithinHistory(snapshot, history, 'Aira 云');
    const body: AiraCloudBookmarkApiWriteRequest = {
      uid: this.uid,
      source: 'app',
      deviceId: params.deviceId,
      parentCommitId: params.parentCommitId ?? null,
      createdAt: params.createdAt ?? snapshot.meta.generatedAt,
      history: history,
      snapshot: snapshot
    };
    const response = await this.post('/write', body);
    const commitId = (response.commitId ?? '').trim();
    if (commitId.length <= 0) {
      throw new Error('Aira 云同步服务没有返回 commitId。');
    }
    return {
      commitId: commitId,
      writtenAt: (response.writtenAt ?? body.createdAt).trim()
    };
  }

  private async post(path: string, body: Object): Promise<AiraCloudBookmarkApiResponseBody> {
    const authorization = await this.authProvider.getAuthorizationHeader();
    try {
      const value = await this.adapter.post(
        `${this.endpoint}${path}`,
        body,
        authorization,
        this.resolveRequestTimeoutMs(path)
      );
      const response = this.parseResponseValue(value);
      if (response.ok !== true) {
        if (response.code === 'sync_conflict') {
          throw new Error('Aira 云远端已更新，请重新拉取后再同步。');
        }
        throw new Error(response.message ?? `Aira 云同步服务返回失败：${response.code ?? 'unknown'}`);
      }
      return response;
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      hilog.error(
        AIRA_CLOUD_BOOKMARK_API_LOG_DOMAIN,
        AIRA_CLOUD_BOOKMARK_API_LOG_TAG,
        'request failed path=%{public}s uid=%{public}s error=%{public}s',
        path,
        this.maskUid(this.uid),
        message
      );
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(message);
    }
  }

  private parseResponseValue(value: Object | string | null | undefined): AiraCloudBookmarkApiResponseBody {
    if (value === undefined || value === null) {
      return {
        ok: false,
        code: 'empty_response',
        message: 'Aira 云同步服务没有返回结果。'
      };
    }
    if (typeof value === 'string') {
      try {
        return this.parseResponseObject(JSON.parse(value) as Object);
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response',
          message: 'Aira 云同步服务返回的 JSON 无法解析。'
        };
      }
    }
    return this.parseResponseObject(value);
  }

  private resolveRequestTimeoutMs(path: string): number {
    if (path === '/read' || path === '/write') {
      return AIRA_CLOUD_BOOKMARK_API_LARGE_PAYLOAD_TIMEOUT_MS;
    }
    return AIRA_CLOUD_BOOKMARK_API_TIMEOUT_MS;
  }

  private parseResponseObject(value: Object): AiraCloudBookmarkApiResponseBody {
    const raw = value as AiraCloudBookmarkApiResponseEnvelope;
    const body = raw.body;
    if (typeof body === 'string') {
      try {
        return JSON.parse(body) as AiraCloudBookmarkApiResponseBody;
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response_body',
          message: 'Aira 云同步服务返回的 body 无法解析。'
        };
      }
    }
    if (body !== undefined && body !== null && typeof body === 'object') {
      return body as AiraCloudBookmarkApiResponseBody;
    }
    return raw as AiraCloudBookmarkApiResponseBody;
  }

  private assertConfigured(): void {
    if (this.endpoint.length <= 0) {
      throw new Error('Aira 云同步代理地址未配置。');
    }
    if (this.uid.length <= 0) {
      throw new Error('请先使用华为账号开启书签同步。');
    }
  }

  private normalizeOptionalCount(value: number | undefined): number {
    if (typeof value !== 'number' || value < 0) {
      return -1;
    }
    return Math.floor(value);
  }

  private maskUid(uid: string): string {
    const normalized = uid.trim();
    if (normalized.length <= 8) {
      return normalized;
    }
    return `${normalized.slice(0, 4)}...${normalized.slice(normalized.length - 4)}`;
  }
}

export function createAiraCloudBookmarkRemoteStore(uid: string): AiraCloudBookmarkRemoteStore {
  return new AiraCloudBookmarkRemoteStore(AIRA_CLOUD_BOOKMARK_SYNC_API_ENDPOINT, uid);
}
