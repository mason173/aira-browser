import { http } from '@kit.NetworkKit';
import { HuaweiAccountSyncAuthService } from '../sync/HuaweiAccountSyncAuthService';
import {
  AIRA_DISTRIBUTION_CAPABILITY_OWNER,
  AIRA_HOSTED_API_BASE_URL
} from '../../common/config/AiraDistributionCapabilityOwner';

const AIRA_IAP_VERIFY_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/verify';
const AIRA_IAP_VERIFY_TIMEOUT_MS: number = 45000;

export interface HuaweiIapVerificationRequestBody {
  uid: string;
  purchaseData: string;
  source: string;
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
      message: `Aira IAP 验签服务请求失败（${responseCode}）。`
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
        message: '请先登录华为账号后再恢复 Aira Pro 权益。'
      };
    }
    if (normalizedPurchaseData.length <= 0) {
      return {
        ok: false,
        code: 'missing_purchase_data',
        message: '华为 IAP 未返回可提交的购买凭证。'
      };
    }
    const body: HuaweiIapVerificationRequestBody = {
      uid: normalizedUid,
      purchaseData: normalizedPurchaseData,
      source: source
    };
    try {
      const authToken = await this.authService.getCurrentAccessTokenForUid(normalizedUid, false);
      if (authToken.length > 0) {
        body.authToken = authToken;
      }
    } catch (_error) {
      body.authToken = undefined;
    }
    const value = await this.adapter.post(AIRA_IAP_VERIFY_ENDPOINT, body, AIRA_IAP_VERIFY_TIMEOUT_MS);
    return this.parseFunctionValue(value);
  }

  private parseFunctionValue(value: Object | string | null | undefined): HuaweiIapVerificationResponseBody {
    if (value === undefined || value === null) {
      return {
        ok: false,
        code: 'empty_response',
        message: 'Aira IAP 验签云函数没有返回结果。'
      };
    }
    if (typeof value === 'string') {
      try {
        return this.parseFunctionObject(JSON.parse(value) as Object);
      } catch (_error) {
        return {
          ok: false,
          code: 'invalid_response',
          message: 'Aira IAP 验签云函数返回的 JSON 无法解析。'
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
          message: 'Aira IAP 验签云函数返回的 body 无法解析。'
        };
      }
    }
    if (body !== undefined && body !== null && typeof body === 'object') {
      return body as HuaweiIapVerificationResponseBody;
    }
    return raw as HuaweiIapVerificationResponseBody;
  }
}
