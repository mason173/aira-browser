import { http } from '@kit.NetworkKit';
import {
  AIRA_DISTRIBUTION_CAPABILITY_OWNER,
  AIRA_HOSTED_API_BASE_URL
} from '../../common/config/AiraDistributionCapabilityOwner';
import {
  AIRA_CLOUD_BOOKMARK_SYNC_PROTOCOL_ID,
  AiraSyncSettings,
  isAiraSyncProviderEnabled
} from '../../common/models/AiraSyncModels';
import {
  APP_BUNDLE_NAME
} from '../../common/constants/AppVersionInfo';
import { ChangelogContentService } from '../settings/ChangelogContentService';

export const AIRA_CLIENT_UPDATE_POLICY_ENDPOINT: string =
  AIRA_HOSTED_API_BASE_URL + '/client/v1/update-policy';

const CLIENT_UPDATE_POLICY_TIMEOUT_MS: number = 15000;
const CLIENT_UPDATE_POLICY_CACHE_MS: number = 10 * 60 * 1000;

export interface ClientUpdatePolicyState {
  required: boolean;
  policyId: string;
  minimumVersionCode: number;
  minimumVersionName: string;
  updateUrl: string;
  message: string;
  checkedAt: number;
}

export const HIDDEN_CLIENT_UPDATE_POLICY_STATE: ClientUpdatePolicyState = {
  required: false,
  policyId: '',
  minimumVersionCode: 0,
  minimumVersionName: '',
  updateUrl: '',
  message: '',
  checkedAt: 0
};

export interface ClientUpdatePolicyRequestBody {
  appId: string;
  bundleName: string;
  versionCode: number;
  versionName: string;
  source: string;
  distribution: string;
  protocol: string;
}

export interface ClientUpdatePolicyResponseBody {
  ok?: boolean;
  code?: string;
  message?: string;
  policyId?: string;
  required?: boolean;
  minimumVersionCode?: number;
  minimumVersionName?: string;
  updateUrl?: string;
  updateMessage?: string;
}

export interface ClientUpdatePolicyHttpAdapter {
  post(url: string, body: Object, timeoutMs: number): Promise<Object | string | null | undefined>;
}

class NetworkClientUpdatePolicyHttpAdapter implements ClientUpdatePolicyHttpAdapter {
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
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': 'AiraBrowser/1.0'
        },
        extraData: JSON.stringify(body)
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return {
          ok: false,
          code: 'http_error',
          message: `Aira 更新策略服务请求失败（${response.responseCode}）。`
        } as ClientUpdatePolicyResponseBody;
      }
      return response.result as string | Object | null | undefined;
    } finally {
      request.destroy();
    }
  }
}

type ClientUpdatePolicyListener = (state: ClientUpdatePolicyState) => void;

/**
 * Reads the hosted minimum-version policy without making local browsing depend on the network.
 * A missing or unavailable policy is fail-open; only an explicit valid response can require an update.
 */
export class ClientUpdatePolicyService {
  private readonly adapter: ClientUpdatePolicyHttpAdapter;
  private readonly changelogService: ChangelogContentService;
  private state: ClientUpdatePolicyState = HIDDEN_CLIENT_UPDATE_POLICY_STATE;
  private listeners: ClientUpdatePolicyListener[] = [];
  private inFlight?: Promise<ClientUpdatePolicyState>;
  private lastCheckedAt: number = 0;
  private suppressedPolicyId: string = '';

  constructor(
    adapter?: ClientUpdatePolicyHttpAdapter,
    changelogService?: ChangelogContentService
  ) {
    this.adapter = adapter ?? new NetworkClientUpdatePolicyHttpAdapter();
    this.changelogService = changelogService ?? new ChangelogContentService();
  }

  getSnapshot(): ClientUpdatePolicyState {
    return this.copyState(this.state);
  }

  subscribe(listener: ClientUpdatePolicyListener): () => void {
    this.listeners.push(listener);
    listener(this.getSnapshot());
    return (): void => {
      this.listeners = this.listeners.filter((candidate: ClientUpdatePolicyListener) => candidate !== listener);
    };
  }

  async check(settings: AiraSyncSettings, force: boolean = false): Promise<ClientUpdatePolicyState> {
    if (!this.shouldCheck(settings)) {
      this.publish(HIDDEN_CLIENT_UPDATE_POLICY_STATE);
      return this.getSnapshot();
    }
    const now = Date.now();
    if (!force && this.inFlight !== undefined) {
      return this.inFlight;
    }
    if (!force && this.lastCheckedAt > 0 && now - this.lastCheckedAt < CLIENT_UPDATE_POLICY_CACHE_MS) {
      return this.getSnapshot();
    }
    this.inFlight = this.fetchPolicy()
      .catch((_error: Error) => HIDDEN_CLIENT_UPDATE_POLICY_STATE)
      .then((nextState: ClientUpdatePolicyState) => {
        this.lastCheckedAt = Date.now();
        this.publish(nextState);
        return this.getSnapshot();
      })
      .finally((): void => {
        this.inFlight = undefined;
      });
    return this.inFlight;
  }

  deferCurrentRequirement(): void {
    if (!this.state.required) {
      return;
    }
    this.suppressedPolicyId = this.state.policyId;
    this.publish(HIDDEN_CLIENT_UPDATE_POLICY_STATE);
  }

  private async fetchPolicy(): Promise<ClientUpdatePolicyState> {
    const version = this.changelogService.resolveCurrentVersion();
    const requestBody: ClientUpdatePolicyRequestBody = {
      appId: APP_BUNDLE_NAME,
      bundleName: APP_BUNDLE_NAME,
      versionCode: version.versionCode,
      versionName: version.versionName,
      source: 'app',
      distribution: 'official',
      protocol: AIRA_CLOUD_BOOKMARK_SYNC_PROTOCOL_ID
    };
    const value = await this.adapter.post(
      AIRA_CLIENT_UPDATE_POLICY_ENDPOINT,
      requestBody,
      CLIENT_UPDATE_POLICY_TIMEOUT_MS
    );
    const response = this.parseResponse(value);
    if (response.ok !== true) {
      return HIDDEN_CLIENT_UPDATE_POLICY_STATE;
    }
    const minimumVersionCode = this.normalizeVersionCode(response.minimumVersionCode);
    const required = response.required === true || minimumVersionCode > version.versionCode;
    const policyId = this.normalizeText(response.policyId, `minimum-${minimumVersionCode}`);
    if (!required || policyId === this.suppressedPolicyId) {
      return HIDDEN_CLIENT_UPDATE_POLICY_STATE;
    }
    return {
      required: true,
      policyId: policyId,
      minimumVersionCode: minimumVersionCode,
      minimumVersionName: this.normalizeText(response.minimumVersionName, '当前版本'),
      updateUrl: this.normalizeUpdateUrl(response.updateUrl),
      message: this.normalizeText(
        response.updateMessage ?? response.message,
        '当前版本无法继续使用 Aira 云书签同步。升级后即可恢复云端同步，本机书签和其他同步方式不受影响。'
      ),
      checkedAt: Date.now()
    };
  }

  private shouldCheck(settings: AiraSyncSettings): boolean {
    return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud') &&
      isAiraSyncProviderEnabled(settings, 'aira_cloud');
  }

  private publish(nextState: ClientUpdatePolicyState): void {
    this.state = this.copyState(nextState);
    const snapshot = this.getSnapshot();
    this.listeners.slice().forEach((listener: ClientUpdatePolicyListener): void => listener(snapshot));
  }

  private copyState(state: ClientUpdatePolicyState): ClientUpdatePolicyState {
    return {
      required: state.required,
      policyId: state.policyId,
      minimumVersionCode: state.minimumVersionCode,
      minimumVersionName: state.minimumVersionName,
      updateUrl: state.updateUrl,
      message: state.message,
      checkedAt: state.checkedAt
    };
  }

  private parseResponse(value: Object | string | null | undefined): ClientUpdatePolicyResponseBody {
    if (value === undefined || value === null) {
      return { ok: false, code: 'empty_response' };
    }
    if (typeof value === 'string') {
      try {
        return this.parseResponseObject(JSON.parse(value) as Object);
      } catch (_error) {
        return { ok: false, code: 'invalid_response' };
      }
    }
    return this.parseResponseObject(value);
  }

  private parseResponseObject(value: Object): ClientUpdatePolicyResponseBody {
    const raw = value as Record<string, Object | string | boolean | number | undefined | null>;
    const body = raw.body;
    if (typeof body === 'string') {
      try {
        return JSON.parse(body) as ClientUpdatePolicyResponseBody;
      } catch (_error) {
        return { ok: false, code: 'invalid_response_body' };
      }
    }
    if (body !== undefined && body !== null && typeof body === 'object') {
      return body as ClientUpdatePolicyResponseBody;
    }
    return raw as ClientUpdatePolicyResponseBody;
  }

  private normalizeVersionCode(value: number | undefined): number {
    const normalized = Number(value);
    return Number.isFinite(normalized) && normalized > 0 ? Math.round(normalized) : 0;
  }

  private normalizeText(value: string | undefined, fallback: string): string {
    const normalized = `${value ?? ''}`.trim();
    return normalized.length > 0 ? normalized : fallback;
  }

  private normalizeUpdateUrl(value: string | undefined): string {
    const normalized = `${value ?? ''}`.trim();
    if (normalized.startsWith('https://') || normalized.startsWith('store://')) {
      return normalized;
    }
    return '';
  }
}

export const sharedClientUpdatePolicyService: ClientUpdatePolicyService =
  new ClientUpdatePolicyService();
