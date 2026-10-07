import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER, AIRA_HOSTED_API_BASE_URL } from '../../common/config/AiraDistributionCapabilityOwner';
import { HuaweiAccountSyncAuthService } from '../sync/HuaweiAccountSyncAuthService';

const AIRA_ACCOUNT_LINK_UNION_ENDPOINT: string = AIRA_HOSTED_API_BASE_URL + '/account/link-union';
const AIRA_ACCOUNT_LINK_UNION_TIMEOUT_MS: number = 15000;
// Resolve the API hostname through a fixed-IP DoH endpoint so a device-side DNS
// hijack cannot redirect the request; the TLS hostname check still applies.
const AIRA_ACCOUNT_LINK_DOH_ENDPOINT: string = 'https://223.5.5.5/dns-query';
const ACCOUNT_UNION_LINK_DOMAIN: number = 0x0000;
const ACCOUNT_UNION_LINK_TAG: string = 'AiraAccountUnionLink';

interface AiraAccountLinkUnionRequestBody {
  uid: string;
  unionId: string;
  authToken?: string;
  source: string;
}

export interface AiraAccountUnionLinkHttpAdapter {
  post(url: string, body: Object, timeoutMs: number): Promise<Object | string | null | undefined>;
}

class NetworkAiraAccountUnionLinkHttpAdapter implements AiraAccountUnionLinkHttpAdapter {
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
        dnsOverHttps: AIRA_ACCOUNT_LINK_DOH_ENDPOINT,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': 'AiraBrowser/1.0'
        },
        extraData: JSON.stringify(body)
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return undefined;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

/**
 * Reports the signed-in account's Huawei UnionID to the Aira backend so a
 * sibling App (Pinecone List) can be recognized as the same person through the
 * shareable UnionID. Best-effort: a failure never blocks login, it only means
 * the sibling App cannot resolve this account until a later attempt succeeds.
 */
export class AiraAccountUnionLinkFunctionService {
  private adapter: AiraAccountUnionLinkHttpAdapter;
  private authService: HuaweiAccountSyncAuthService;

  constructor(adapter?: AiraAccountUnionLinkHttpAdapter, authService?: HuaweiAccountSyncAuthService) {
    this.adapter = adapter ?? new NetworkAiraAccountUnionLinkHttpAdapter();
    this.authService = authService ?? new HuaweiAccountSyncAuthService();
  }

  async linkUnionId(uid: string): Promise<boolean> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      return false;
    }
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 0) {
      return false;
    }
    let unionId = '';
    try {
      unionId = (await this.authService.getCurrentUnionId()).trim();
    } catch (error) {
      hilog.warn(
        ACCOUNT_UNION_LINK_DOMAIN,
        ACCOUNT_UNION_LINK_TAG,
        'union id unavailable error=%{public}s',
        JSON.stringify(error)
      );
      return false;
    }
    if (unionId.length <= 0) {
      return false;
    }
    const body: AiraAccountLinkUnionRequestBody = {
      uid: normalizedUid,
      unionId: unionId,
      source: 'app'
    };
    try {
      const token = await this.authService.getCurrentAccessTokenForUid(normalizedUid, false);
      if (token.length <= 0) {
        return false;
      }
      body.authToken = token;
    } catch (_error) {
      return false;
    }
    try {
      const value = await this.adapter.post(
        AIRA_ACCOUNT_LINK_UNION_ENDPOINT,
        body,
        AIRA_ACCOUNT_LINK_UNION_TIMEOUT_MS
      );
      return this.parseLinked(value);
    } catch (error) {
      hilog.warn(
        ACCOUNT_UNION_LINK_DOMAIN,
        ACCOUNT_UNION_LINK_TAG,
        'link request failed error=%{public}s',
        JSON.stringify(error)
      );
      return false;
    }
  }

  private parseLinked(value: Object | string | null | undefined): boolean {
    if (value === undefined || value === null) {
      return false;
    }
    let parsed: Object | string | null | undefined = value;
    if (typeof value === 'string') {
      const text = value.trim();
      if (text.length <= 0) {
        return false;
      }
      try {
        parsed = JSON.parse(text) as Object;
      } catch (_error) {
        return false;
      }
    }
    const record = parsed as Record<string, Object>;
    return record.ok === true;
  }
}
