import { http } from '@kit.NetworkKit';
import {
  AIRA_DISTRIBUTION_CAPABILITY_OWNER,
  AIRA_HOSTED_API_BASE_URL
} from '../../common/config/AiraDistributionCapabilityOwner';
import { HuaweiAccountSyncAuthService } from '../sync/HuaweiAccountSyncAuthService';

const AIRA_PHONE_PAGE_PUSH_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/phone-page-push/enqueue';
const AIRA_PHONE_PAGE_PUSH_TIMEOUT_MS: number = 30000;

export interface AiraPhonePagePushRequestBody {
  uid: string;
  url: string;
  originalUrl: string;
  desktopUrl?: string;
  title: string;
  source: string;
  authToken?: string;
}

export interface AiraPhonePagePushTaskResponse {
  taskId?: string;
  url?: string;
  originalUrl?: string;
  desktopUrl?: string;
  title?: string;
  source?: string;
  status?: string;
  createdAt?: number;
  updatedAt?: number;
  expiresAt?: number;
  deliveredAt?: number;
  openedAt?: number;
  ackedAt?: number;
}

export interface AiraPhonePagePushResponseBody {
  ok?: boolean;
  code?: string;
  message?: string;
  version?: string;
  uidSuffix?: string;
  membershipPlan?: string;
  duplicate?: boolean;
  task?: AiraPhonePagePushTaskResponse;
}

export interface AiraPhonePagePushHttpAdapter {
  post(url: string, body: Object, timeoutMs: number): Promise<Object | string | null | undefined>;
}

class NetworkAiraPhonePagePushHttpAdapter implements AiraPhonePagePushHttpAdapter {
  async post(url: string, body: Object, timeoutMs: number): Promise<Object | string | null | undefined> {
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
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': 'AiraBrowser/1.0'
        },
        extraData: JSON.stringify(body)
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const errorResponse: AiraPhonePagePushResponseBody = {
          ok: false,
          code: 'http_error',
          message: `网页推送服务请求失败（${response.responseCode}）。`
        };
        return errorResponse;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

export class AiraPhonePagePushFunctionService {
  private adapter: AiraPhonePagePushHttpAdapter;
  private authService: HuaweiAccountSyncAuthService;

  constructor(adapter?: AiraPhonePagePushHttpAdapter, authService?: HuaweiAccountSyncAuthService) {
    this.adapter = adapter ?? new NetworkAiraPhonePagePushHttpAdapter();
    this.authService = authService ?? new HuaweiAccountSyncAuthService();
  }

  async enqueue(uid: string, url: string, title: string, desktopUrl: string = ''): Promise<AiraPhonePagePushResponseBody> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return {
        ok: false,
        code: 'distribution_unavailable',
        message: AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud')
      };
    }
    const normalizedUid = uid.trim();
    const normalizedUrl = url.trim();
    if (normalizedUid.length <= 0) {
      return {
        ok: false,
        code: 'missing_uid',
        message: '请先使用华为账号登录后再推送网页。'
      };
    }
    if (!this.isHttpUrl(normalizedUrl)) {
      return {
        ok: false,
        code: 'invalid_url',
        message: '当前页面不能推送到电脑。'
      };
    }
    const normalizedDesktopUrl = this.isHttpUrl(desktopUrl) && desktopUrl.trim() !== normalizedUrl
      ? desktopUrl.trim()
      : '';
    const body: AiraPhonePagePushRequestBody = {
      uid: normalizedUid,
      url: normalizedDesktopUrl.length > 0 ? normalizedDesktopUrl : normalizedUrl,
      originalUrl: normalizedUrl,
      title: title.trim(),
      source: 'harmonyos_app'
    };
    if (normalizedDesktopUrl.length > 0) {
      body.desktopUrl = normalizedDesktopUrl;
    }
    try {
      const token = await this.authService.getCurrentAccessTokenForUid(normalizedUid, true);
      if (token.length > 0) {
        body.authToken = token;
      }
    } catch (_error) {
      return {
        ok: false,
        code: 'auth_token_required',
        message: '请重新登录华为账号后再推送网页。'
      };
    }
    const value = await this.adapter.post(AIRA_PHONE_PAGE_PUSH_ENDPOINT, body, AIRA_PHONE_PAGE_PUSH_TIMEOUT_MS);
    return this.parseFunctionValue(value);
  }

  private parseFunctionValue(value: Object | string | null | undefined): AiraPhonePagePushResponseBody {
    if (value === undefined || value === null) {
      return {
        ok: false,
        code: 'empty_response',
        message: '网页推送服务没有返回结果。'
      };
    }
    if (typeof value === 'string') {
      try {
        return this.parseFunctionObject(JSON.parse(value) as Object);
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response',
          message: '网页推送服务返回的 JSON 无法解析。'
        };
      }
    }
    return this.parseFunctionObject(value);
  }

  private parseFunctionObject(value: Object): AiraPhonePagePushResponseBody {
    const raw = value as Record<string, Object | string | boolean | number | undefined | null>;
    const body = raw.body;
    if (typeof body === 'string') {
      try {
        return JSON.parse(body) as AiraPhonePagePushResponseBody;
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response_body',
          message: '网页推送服务返回的 body 无法解析。'
        };
      }
    }
    if (body !== undefined && body !== null && typeof body === 'object') {
      return body as AiraPhonePagePushResponseBody;
    }
    return raw as AiraPhonePagePushResponseBody;
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }
}
