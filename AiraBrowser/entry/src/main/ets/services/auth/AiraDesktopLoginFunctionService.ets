import { http } from '@kit.NetworkKit';
import {
  AIRA_DISTRIBUTION_CAPABILITY_OWNER,
  AIRA_HOSTED_API_BASE_URL
} from '../../common/config/AiraDistributionCapabilityOwner';
import { HuaweiAccountSyncAuthService } from '../sync/HuaweiAccountSyncAuthService';

const AIRA_DESKTOP_LOGIN_CONFIRM_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/desktop-login/confirm';
const AIRA_DESKTOP_LOGIN_TIMEOUT_MS: number = 30000;

export interface AiraDesktopLoginConfirmRequestBody {
  sessionId: string;
  secret: string;
  uid: string;
  displayName: string;
  avatarUri: string;
  source: string;
  authToken?: string;
}

export interface AiraDesktopLoginConfirmResponseBody {
  ok?: boolean;
  code?: string;
  message?: string;
  status?: string;
  uidSuffix?: string;
  membershipPlan?: string;
}

export interface AiraDesktopLoginHttpAdapter {
  post(url: string, body: Object, timeoutMs: number): Promise<Object | string | null | undefined>;
}

class NetworkAiraDesktopLoginHttpAdapter implements AiraDesktopLoginHttpAdapter {
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
        const errorResponse: AiraDesktopLoginConfirmResponseBody = {
          ok: false,
          code: 'http_error',
          message: `Aira 桌面登录服务请求失败（${response.responseCode}）。`
        };
        return errorResponse;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

export class AiraDesktopLoginFunctionService {
  private adapter: AiraDesktopLoginHttpAdapter;
  private authService: HuaweiAccountSyncAuthService;

  constructor(adapter?: AiraDesktopLoginHttpAdapter, authService?: HuaweiAccountSyncAuthService) {
    this.adapter = adapter ?? new NetworkAiraDesktopLoginHttpAdapter();
    this.authService = authService ?? new HuaweiAccountSyncAuthService();
  }

  async confirm(
    sessionId: string,
    secret: string,
    uid: string,
    displayName: string,
    avatarUri: string
  ): Promise<AiraDesktopLoginConfirmResponseBody> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return {
        ok: false,
        code: 'distribution_unavailable',
        message: AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud')
      };
    }
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 0) {
      return {
        ok: false,
        code: 'missing_uid',
        message: '请先使用华为账号登录后再扫码。'
      };
    }
    const body: AiraDesktopLoginConfirmRequestBody = {
      sessionId: sessionId.trim(),
      secret: secret.trim(),
      uid: normalizedUid,
      displayName: displayName.trim(),
      avatarUri: avatarUri.trim(),
      source: 'app_desktop_login'
    };
    try {
      const token = await this.authService.getCurrentAccessTokenForUid(normalizedUid, true);
      if (token.length > 0) {
        body.authToken = token;
      }
    } catch (_error) {
      return {
        ok: false,
        code: 'auth_token_required',
        message: '请重新登录华为账号后再扫码。'
      };
    }
    const value = await this.adapter.post(AIRA_DESKTOP_LOGIN_CONFIRM_ENDPOINT, body, AIRA_DESKTOP_LOGIN_TIMEOUT_MS);
    return this.parseFunctionValue(value);
  }

  private parseFunctionValue(value: Object | string | null | undefined): AiraDesktopLoginConfirmResponseBody {
    if (value === undefined || value === null) {
      return {
        ok: false,
        code: 'empty_response',
        message: 'Aira 桌面登录服务没有返回结果。'
      };
    }
    if (typeof value === 'string') {
      try {
        return this.parseFunctionObject(JSON.parse(value) as Object);
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response',
          message: 'Aira 桌面登录服务返回的 JSON 无法解析。'
        };
      }
    }
    return this.parseFunctionObject(value);
  }

  private parseFunctionObject(value: Object): AiraDesktopLoginConfirmResponseBody {
    const raw = value as Record<string, Object | string | boolean | number | undefined | null>;
    const body = raw.body;
    if (typeof body === 'string') {
      try {
        return JSON.parse(body) as AiraDesktopLoginConfirmResponseBody;
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response_body',
          message: 'Aira 桌面登录服务返回的 body 无法解析。'
        };
      }
    }
    if (body !== undefined && body !== null && typeof body === 'object') {
      return body as AiraDesktopLoginConfirmResponseBody;
    }
    return raw as AiraDesktopLoginConfirmResponseBody;
  }
}
