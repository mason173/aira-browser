import { http } from '@kit.NetworkKit';
import { HuaweiAccountSyncAuthService } from '../sync/HuaweiAccountSyncAuthService';
import {
  AIRA_DISTRIBUTION_CAPABILITY_OWNER,
  AIRA_HOSTED_API_BASE_URL
} from '../../common/config/AiraDistributionCapabilityOwner';

const AIRA_MEMBERSHIP_STATE_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/membership/state';
const AIRA_ACCOUNT_PROFILE_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/account/profile';
const AIRA_MEMBERSHIP_STATE_TIMEOUT_MS: number = 30000;
// Resolve the API hostname through a fixed-IP DoH endpoint so a device-side
// DNS hijack cannot send the request to an unrelated HTTPS host. The DoH
// endpoint certificate includes this IP; the API request still uses the
// configured Official host, so normal TLS hostname checks remain in force.
const AIRA_MEMBERSHIP_DOH_ENDPOINT: string = 'https://223.5.5.5/dns-query';

export interface AiraMembershipGrantResponseRecord {
  uid?: string;
  plan?: string;
  source?: string;
  productId?: string;
  subscriptionStatus?: string;
  expiresAt?: number;
  updatedAt?: number;
  currentPlan?: string;
  status?: string;
  active?: boolean;
}

export interface AiraAccountProfileResponseRecord {
  uid?: string;
  firstSeenAt?: number;
  lastSeenAt?: number;
}

export interface AiraMembershipStateRequestBody {
  uid: string;
  source: string;
  entitlementOnly?: boolean;
  authToken?: string;
}

export interface AiraAccountProfileRequestBody {
  uid: string;
  source: string;
  authToken?: string;
}

export interface AiraMembershipStateResponseBody {
  ok?: boolean;
  code?: string;
  message?: string;
  uidSuffix?: string;
  accountProfile?: AiraAccountProfileResponseRecord | null;
  recognitions?: string[];
  membershipGrant?: AiraMembershipGrantResponseRecord | null;
  entitlementProof?: string | null;
}

export interface AiraMembershipStateHttpAdapter {
  post(url: string, body: Object, timeoutMs: number): Promise<Object | string | null | undefined>;
}

class NetworkAiraMembershipStateHttpAdapter implements AiraMembershipStateHttpAdapter {
  async post(
    url: string,
    body: Object,
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
        dnsOverHttps: AIRA_MEMBERSHIP_DOH_ENDPOINT,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': 'AiraBrowser/1.0'
        },
        extraData: JSON.stringify(body)
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const errorResponse: AiraMembershipStateResponseBody = {
          ok: false,
          code: 'http_error',
          message: `Aira 会员状态服务请求失败（${response.responseCode}）。`
        };
        return errorResponse;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

export class AiraMembershipStateFunctionService {
  private adapter: AiraMembershipStateHttpAdapter;
  private authService: HuaweiAccountSyncAuthService;

  constructor(adapter?: AiraMembershipStateHttpAdapter, authService?: HuaweiAccountSyncAuthService) {
    this.adapter = adapter ?? new NetworkAiraMembershipStateHttpAdapter();
    this.authService = authService ?? new HuaweiAccountSyncAuthService();
  }

  async fetchEntitlementState(uid: string): Promise<AiraMembershipStateResponseBody> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return this.buildDistributionUnavailableResponse('aira_cloud');
    }
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 0) {
      return {
        ok: false,
        code: 'missing_uid',
        message: '请先使用华为账号登录。'
      };
    }
    const body: AiraMembershipStateRequestBody = {
      uid: normalizedUid,
      source: 'app',
      entitlementOnly: true
    };
    await this.attachAuthToken(body);
    const value = await this.adapter.post(AIRA_MEMBERSHIP_STATE_ENDPOINT, body, AIRA_MEMBERSHIP_STATE_TIMEOUT_MS);
    return this.parseFunctionValue(value);
  }

  async fetchAccountProfile(uid: string): Promise<AiraMembershipStateResponseBody> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return this.buildDistributionUnavailableResponse('aira_cloud');
    }
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 0) {
      return {
        ok: false,
        code: 'missing_uid',
        message: '请先使用华为账号登录。'
      };
    }
    const body: AiraAccountProfileRequestBody = {
      uid: normalizedUid,
      source: 'app'
    };
    try {
      const token = await this.authService.getCurrentAccessTokenForUid(normalizedUid, true);
      if (token.length <= 0) {
        return {
          ok: false,
          code: 'auth_token_required',
          message: '请重新登录华为账号后再继续。'
        };
      }
      body.authToken = token;
    } catch (_error) {
      return {
        ok: false,
        code: 'auth_token_required',
        message: '请重新登录华为账号后再继续。'
      };
    }
    const value = await this.adapter.post(AIRA_ACCOUNT_PROFILE_ENDPOINT, body, AIRA_MEMBERSHIP_STATE_TIMEOUT_MS);
    return this.parseFunctionValue(value);
  }

  private async attachAuthToken(
    body: AiraMembershipStateRequestBody | AiraAccountProfileRequestBody
  ): Promise<void> {
    try {
      const token = await this.authService.getCurrentAccessToken(false);
      if (token.length > 0) {
        body.authToken = token;
      }
    } catch (_error) {
      body.authToken = undefined;
    }
  }

  private buildDistributionUnavailableResponse(
    capability: 'aira_cloud' | 'huawei_account' | 'huawei_space' | 'huawei_iap' | 'personal_server'
  ): AiraMembershipStateResponseBody {
    return {
      ok: false,
      code: 'distribution_unavailable',
      message: AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason(capability)
    };
  }

  private parseFunctionValue(value: Object | string | null | undefined): AiraMembershipStateResponseBody {
    if (value === undefined || value === null) {
      return {
        ok: false,
        code: 'empty_response',
        message: 'Aira 会员状态服务没有返回结果。'
      };
    }
    if (typeof value === 'string') {
      try {
        return this.parseFunctionObject(JSON.parse(value) as Object);
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response',
          message: 'Aira 会员状态服务返回的 JSON 无法解析。'
        };
      }
    }
    return this.parseFunctionObject(value);
  }

  private parseFunctionObject(value: Object): AiraMembershipStateResponseBody {
    const raw = value as Record<string, Object | string | boolean | number | Object[] | undefined | null>;
    const body = raw.body;
    if (typeof body === 'string') {
      try {
        return JSON.parse(body) as AiraMembershipStateResponseBody;
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response_body',
          message: 'Aira 会员状态服务返回的 body 无法解析。'
        };
      }
    }
    if (body !== undefined && body !== null && typeof body === 'object') {
      return body as AiraMembershipStateResponseBody;
    }
    return raw as AiraMembershipStateResponseBody;
  }

}
