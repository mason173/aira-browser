import { http } from '@kit.NetworkKit';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import { HuaweiAccountSyncAuthService } from '../sync/HuaweiAccountSyncAuthService';
import {
  AIRA_DISTRIBUTION_CAPABILITY_OWNER,
  AIRA_HOSTED_API_BASE_URL
} from '../../common/config/AiraDistributionCapabilityOwner';

const AIRA_IAP_VERIFY_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/verify';
const AIRA_SUITE_CHECKOUT_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/membership/purchase/aira/suite/checkout';
const AIRA_IAP_VERIFY_TIMEOUT_MS: number = 45000;
const AIRA_SUITE_CHECKOUT_TIMEOUT_MS: number = 12000;

export interface HuaweiIapVerificationRequestBody {
  uid: string;
  purchaseData?: string;
  source?: string;
  authToken?: string;
}

export interface HuaweiIapVerificationResponseBody {
  ok?: boolean;
  code?: string;
  message?: string;
  uidSuffix?: string;
  purchaseDataLength?: number;
  purchaseDataKeys?: string[];
  productId?: string;
  purchaseTokenExists?: boolean;
  expiresTime?: string;
  expiresAt?: number;
  productType?: string;
  signatureVerified?: boolean;
  signatureVerificationConfigured?: boolean;
  developerPayload?: string;
}

export interface HuaweiIapVerificationHttpAdapter {
  post(url: string, body: HuaweiIapVerificationRequestBody, timeoutMs: number):
    Promise<Object | string | null | undefined>;
}

class NetworkHuaweiIapVerificationHttpAdapter implements HuaweiIapVerificationHttpAdapter {
  async post(
    url: string,
    body: HuaweiIapVerificationRequestBody,
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
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': 'AiraBrowser/1.0'
        },
        extraData: JSON.stringify(body)
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return this.buildHttpErrorResponse(response.responseCode);
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }

  private buildHttpErrorResponse(responseCode: number): HuaweiIapVerificationResponseBody {
    return {
      ok: false,
      code: 'http_error',
      message: resolveAppResourceText($r('app.string.membership_iap_verify_http_failed', responseCode))
    };
  }
}

export class HuaweiIapVerificationFunctionService {
  private adapter: HuaweiIapVerificationHttpAdapter;
  private authService: HuaweiAccountSyncAuthService;

  constructor(adapter?: HuaweiIapVerificationHttpAdapter, authService?: HuaweiAccountSyncAuthService) {
    this.adapter = adapter ?? new NetworkHuaweiIapVerificationHttpAdapter();
    this.authService = authService ?? new HuaweiAccountSyncAuthService();
  }

  async submitPurchaseData(
    uid: string,
    purchaseData: string,
    source: string = 'purchase'
  ): Promise<HuaweiIapVerificationResponseBody> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_iap')) {
      return {
        ok: false,
        code: 'distribution_unavailable',
        message: AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_iap')
      };
    }
    const normalizedUid = uid.trim();
    const normalizedPurchaseData = purchaseData.trim();
    if (normalizedUid.length <= 0) {
      return {
        ok: false,
        code: 'missing_uid',
        message: resolveAppResourceText($r('app.string.membership_iap_verify_login_required'))
      };
    }
    if (normalizedPurchaseData.length <= 0) {
      return {
        ok: false,
        code: 'missing_purchase_data',
        message: resolveAppResourceText($r('app.string.settings_pro_iap_missing_purchase'))
      };
    }
    const body: HuaweiIapVerificationRequestBody = {
      uid: normalizedUid,
      purchaseData: normalizedPurchaseData,
      source: source
    };
    const authToken = await this.resolveAuthToken(normalizedUid);
    if (authToken.length > 0) { body.authToken = authToken; }
    const value = await this.adapter.post(AIRA_IAP_VERIFY_ENDPOINT, body, AIRA_IAP_VERIFY_TIMEOUT_MS);
    return this.parseFunctionValue(value);
  }

  async prepareSuiteCheckout(uid: string): Promise<HuaweiIapVerificationResponseBody> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_iap')) {
      return { ok: false, code: 'distribution_unavailable' };
    }
    const normalizedUid = uid.trim();
    const authToken = normalizedUid ? await this.resolveAuthToken(normalizedUid) : '';
    if (!authToken) { return { ok: false, code: 'auth_token_required' }; }
    const body: HuaweiIapVerificationRequestBody = { uid: normalizedUid, authToken: authToken };
    const value = await this.adapter.post(AIRA_SUITE_CHECKOUT_ENDPOINT, body, AIRA_SUITE_CHECKOUT_TIMEOUT_MS);
    return this.parseFunctionValue(value);
  }

  private async resolveAuthToken(uid: string): Promise<string> {
    try { return await this.authService.getCurrentAccessTokenForUid(uid, false); }
    catch (_error) { return ''; }
  }

  private parseFunctionValue(value: Object | string | null | undefined): HuaweiIapVerificationResponseBody {
    if (value === undefined || value === null) {
      return {
        ok: false,
        code: 'empty_response',
        message: resolveAppResourceText($r('app.string.membership_iap_verify_empty'))
      };
    }
    if (typeof value === 'string') {
      try {
        return this.parseFunctionObject(JSON.parse(value) as Object);
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response',
          message: resolveAppResourceText($r('app.string.membership_iap_verify_invalid_json'))
        };
      }
    }
    return this.parseFunctionObject(value);
  }

  private parseFunctionObject(value: Object): HuaweiIapVerificationResponseBody {
    const raw = value as Record<string, Object | string | boolean | number | string[] | undefined>;
    const body = raw.body;
    if (typeof body === 'string') {
      try {
        return JSON.parse(body) as HuaweiIapVerificationResponseBody;
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response_body',
          message: resolveAppResourceText($r('app.string.membership_iap_verify_invalid_body'))
        };
      }
    }
    if (body !== undefined && body !== null && typeof body === 'object') {
      return body as HuaweiIapVerificationResponseBody;
    }
    return raw as HuaweiIapVerificationResponseBody;
  }
}
