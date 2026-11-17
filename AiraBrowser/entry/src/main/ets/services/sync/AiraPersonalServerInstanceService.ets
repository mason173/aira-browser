import { http } from '@kit.NetworkKit';
import {
  AIRA_CLOUD_BOOKMARK_SYNC_PROTOCOL_ID,
  AiraPersonalServerConfig,
  AiraSyncSettings,
  createDefaultAiraPersonalServerConfig,
  resolveAiraPersonalServerConfig
} from '../../common/models/AiraSyncModels';
import {
  AiraCloudBookmarkApiAuthProvider,
  AiraCloudBookmarkRemoteStore
} from './AiraCloudBookmarkRemoteStore';
import {
  AiraCloudHistoryRemoteStore,
  NetworkAiraCloudHistoryRemoteStore
} from './AiraCloudHistoryRemoteStore';
import { AiraCloudConditionalSnapshotRemoteStore } from './AiraCloudConditionalSnapshotRemoteStore';
import { PERSONALIZATION_SYNC_WRITE_CONFLICT } from '../../common/constants/SyncFlowErrorCodes';
import { NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT } from '../../common/constants/SyncFlowErrorCodes';
import {
  PersonalizationSyncRemoteStore,
  PersonalizationSyncSnapshot
} from '../../common/models/PersonalizationSyncModels';
import {
  NovelBookshelfSyncRemoteStore,
  NovelBookshelfSyncSnapshot
} from '../../common/models/NovelBookshelfSyncModels';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';

const PERSONAL_SERVER_TIMEOUT_MS: number = 45000;
const PERSONAL_SERVER_MIN_PROTOCOL_VERSION: number = 1;
const PERSONAL_SERVER_MAX_PROTOCOL_VERSION: number = 1;

interface PersonalServerCapabilityDescriptor {
  version?: number;
  protocol?: string;
  path?: string;
}

interface PersonalServerCapabilities {
  bookmarks?: PersonalServerCapabilityDescriptor;
  history?: PersonalServerCapabilityDescriptor;
  personalization?: PersonalServerCapabilityDescriptor;
  novelBookshelf?: PersonalServerCapabilityDescriptor;
  deviceManagement?: PersonalServerCapabilityDescriptor;
  pagePush?: PersonalServerCapabilityDescriptor;
  crossDeviceTabs?: PersonalServerCapabilityDescriptor;
}

interface PersonalServerDiscoveryResponse {
  ok?: boolean;
  product?: string;
  instanceId?: string;
  protocolVersion?: number;
  minimumClientProtocolVersion?: number;
  capabilities?: PersonalServerCapabilities;
  code?: string;
  message?: string;
}

interface PersonalServerPairingResponse {
  ok?: boolean;
  instanceId?: string;
  protocolVersion?: number;
  credentialId?: string;
  deviceId?: string;
  token?: string;
  code?: string;
  message?: string;
}

interface PersonalServerPairingRequest {
  code: string;
  deviceId: string;
  deviceName: string;
  deviceKind: 'phone';
}

export interface AiraPersonalServerDiscovery {
  baseUrl: string;
  instanceId: string;
  protocolVersion: number;
}

export interface AiraPersonalServerPairingResult {
  config: AiraPersonalServerConfig;
}

export class AiraPersonalServerDeviceAuthProvider implements AiraCloudBookmarkApiAuthProvider {
  private readonly token: string;

  constructor(token: string) {
    this.token = token.trim();
  }

  getAuthorizationHeader(_expectedUid: string): Promise<string> {
    if (this.token.length <= 0) {
      return Promise.reject(new Error(
        resolveAppResourceText($r('app.string.settings_sync_self_host_error_credential_missing'))
      ));
    }
    return Promise.resolve(`Bearer ${this.token}`);
  }
}

export class AiraPersonalServerInstanceService {
  normalizeBaseUrl(value: string): string {
    const normalized = value.trim().replace(/\/+$/, '');
    if (!/^https?:\/\/[^\s/?#]+(?::\d+)?(?:\/[^\s?#]*)?$/i.test(normalized)) {
      throw new Error(resolveAppResourceText($r('app.string.settings_sync_self_host_error_url_invalid')));
    }
    if (normalized.indexOf('@') >= 0) {
      throw new Error(resolveAppResourceText($r('app.string.settings_sync_self_host_error_url_credentials')));
    }
    return normalized;
  }

  async discover(baseUrl: string): Promise<AiraPersonalServerDiscovery> {
    const normalizedBaseUrl = this.normalizeBaseUrl(baseUrl);
    const response = await this.request<PersonalServerDiscoveryResponse>(
      http.RequestMethod.GET,
      `${normalizedBaseUrl}/.well-known/aira`
    );
    const instanceId = `${response.instanceId ?? ''}`.trim();
    const protocolVersion = Math.floor(Number(response.protocolVersion ?? 0));
    const minimumClientProtocolVersion = Math.floor(Number(response.minimumClientProtocolVersion ?? 0));
    const capabilities = response.capabilities;
    if (response.ok !== true || response.product !== 'aira-personal-server' || instanceId.length <= 0 ||
      protocolVersion < PERSONAL_SERVER_MIN_PROTOCOL_VERSION ||
      protocolVersion > PERSONAL_SERVER_MAX_PROTOCOL_VERSION ||
      minimumClientProtocolVersion > PERSONAL_SERVER_MAX_PROTOCOL_VERSION || capabilities === undefined ||
      capabilities.bookmarks?.version !== 4 ||
      capabilities.bookmarks?.protocol !== AIRA_CLOUD_BOOKMARK_SYNC_PROTOCOL_ID ||
      capabilities.history?.version !== 1 ||
      capabilities.personalization?.version !== 2 || capabilities.novelBookshelf?.version !== 2 ||
      capabilities.pagePush?.version !== 1 || capabilities.crossDeviceTabs?.version !== 1) {
      throw new Error(resolveAppResourceText($r('app.string.settings_sync_self_host_error_incompatible')));
    }
    return {
      baseUrl: normalizedBaseUrl,
      instanceId: instanceId,
      protocolVersion: protocolVersion
    };
  }

  async pair(
    baseUrl: string,
    pairingCode: string,
    deviceId: string,
    deviceName: string = 'Aira HarmonyOS'
  ): Promise<AiraPersonalServerPairingResult> {
    const discovery = await this.discover(baseUrl);
    const request: PersonalServerPairingRequest = {
      code: pairingCode.trim(),
      deviceId: deviceId.trim(),
      deviceName: deviceName.trim().length > 0 ? deviceName.trim() : 'Aira HarmonyOS',
      deviceKind: 'phone'
    };
    if (request.code.length <= 0 || request.deviceId.length <= 0) {
      throw new Error(resolveAppResourceText($r('app.string.settings_sync_self_host_error_pairing_input')));
    }
    const response = await this.request<PersonalServerPairingResponse>(
      http.RequestMethod.POST,
      `${discovery.baseUrl}/v1/pairing/exchange`,
      request
    );
    const token = `${response.token ?? ''}`.trim();
    const credentialId = `${response.credentialId ?? ''}`.trim();
    if (response.ok !== true || response.instanceId !== discovery.instanceId || token.length <= 0 ||
      credentialId.length <= 0 || response.deviceId !== request.deviceId) {
      throw new Error(response.message ?? resolveAppResourceText(
        $r('app.string.settings_sync_self_host_error_pairing_incomplete')));
    }
    return {
      config: {
        baseUrl: discovery.baseUrl,
        instanceId: discovery.instanceId,
        protocolVersion: discovery.protocolVersion,
        credentialId: credentialId,
        deviceToken: token,
        deviceName: request.deviceName,
        remoteStatusCache: null
      }
    };
  }

  createBookmarkStore(settings: AiraSyncSettings): AiraCloudBookmarkRemoteStore {
    const config = this.requireConfigured(settings);
    return new AiraCloudBookmarkRemoteStore(
      `${config.baseUrl}/v1/sync/bookmarks`,
      config.instanceId,
      new AiraPersonalServerDeviceAuthProvider(config.deviceToken)
    );
  }

  createHistoryStore(settings: AiraSyncSettings): AiraCloudHistoryRemoteStore {
    const config = this.requireConfigured(settings);
    return new NetworkAiraCloudHistoryRemoteStore(
      `${config.baseUrl}/v1/sync/history`,
      config.instanceId,
      new AiraPersonalServerDeviceAuthProvider(config.deviceToken)
    );
  }

  // The shared conditional-snapshot store still formats its own messages in Chinese, so the
  // serviceLabel below stays Chinese; localizing only the label would mix languages mid-sentence.
  createPersonalizationStore(settings: AiraSyncSettings): PersonalizationSyncRemoteStore {
    const config = this.requireConfigured(settings);
    return new AiraCloudConditionalSnapshotRemoteStore<PersonalizationSyncSnapshot>(
      `${config.baseUrl}/v1/sync/personalization`,
      config.instanceId,
      {
        serviceLabel: '私有化部署个性化同步',
        conflictResponseCode: 'personalization_sync_write_conflict',
        conflictErrorMessage: PERSONALIZATION_SYNC_WRITE_CONFLICT,
        missingUidMessage: resolveAppResourceText($r('app.string.settings_sync_self_host_error_not_connected'))
      },
      new AiraPersonalServerDeviceAuthProvider(config.deviceToken)
    );
  }

  createNovelBookshelfStore(settings: AiraSyncSettings): NovelBookshelfSyncRemoteStore {
    const config = this.requireConfigured(settings);
    return new AiraCloudConditionalSnapshotRemoteStore<NovelBookshelfSyncSnapshot>(
      `${config.baseUrl}/v1/sync/novel-bookshelf`,
      config.instanceId,
      {
        // Same Chinese serviceLabel reason as createPersonalizationStore.
        serviceLabel: '私有化部署小说书架同步',
        conflictResponseCode: 'novel_bookshelf_sync_write_conflict',
        conflictErrorMessage: NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT,
        missingUidMessage: resolveAppResourceText($r('app.string.settings_sync_self_host_error_not_connected'))
      },
      new AiraPersonalServerDeviceAuthProvider(config.deviceToken)
    );
  }

  requireConfigured(settings: AiraSyncSettings): AiraPersonalServerConfig {
    const config = resolveAiraPersonalServerConfig(settings);
    if (config.baseUrl.trim().length <= 0 || config.instanceId.trim().length <= 0 ||
      config.protocolVersion !== 1 || config.credentialId.trim().length <= 0 ||
      config.deviceToken.trim().length <= 0) {
      throw new Error(resolveAppResourceText($r('app.string.settings_sync_self_host_error_not_paired')));
    }
    return config;
  }

  clearConfig(): AiraPersonalServerConfig {
    return createDefaultAiraPersonalServerConfig();
  }

  private async request<T extends Object>(
    method: http.RequestMethod,
    url: string,
    body?: Object
  ): Promise<T> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: method,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: PERSONAL_SERVER_TIMEOUT_MS,
        readTimeout: PERSONAL_SERVER_TIMEOUT_MS,
        usingCache: false,
        header: {
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          'User-Agent': 'AiraBrowser/1.0'
        },
        extraData: body === undefined ? undefined : JSON.stringify(body)
      });
      const raw = `${response.result ?? ''}`;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(this.readFailureMessage(raw, response.responseCode));
      }
      let value: T;
      try {
        value = JSON.parse(raw) as T;
      } catch (_error) {
        throw new Error(resolveAppResourceText(
          $r('app.string.settings_sync_self_host_error_response_unreadable', response.responseCode)));
      }
      return value;
    } finally {
      request.destroy();
    }
  }

  /**
   * A reverse proxy can answer before the server does, so a failure body is not guaranteed to be
   * JSON. Prefer the server's own message; otherwise name the likely cause, because "unreadable
   * response" blamed the protocol for what was usually a routing or proxy problem.
   */
  private readFailureMessage(raw: string, responseCode: number): string {
    let message: string = '';
    try {
      const body = JSON.parse(raw) as PersonalServerPairingResponse;
      message = `${body.message ?? ''}`.trim();
    } catch (_error) {
      message = '';
    }
    if (message.length > 0) {
      return message;
    }
    if (responseCode === 404) {
      return resolveAppResourceText($r('app.string.settings_sync_self_host_error_http_not_found'));
    }
    if (responseCode === 403) {
      return resolveAppResourceText($r('app.string.settings_sync_self_host_error_http_forbidden'));
    }
    if (responseCode === 413) {
      return resolveAppResourceText($r('app.string.settings_sync_self_host_error_http_too_large'));
    }
    if (responseCode === 301 || responseCode === 302 || responseCode === 303 ||
      responseCode === 307 || responseCode === 308) {
      return resolveAppResourceText(
        $r('app.string.settings_sync_self_host_error_http_redirect', responseCode));
    }
    if (responseCode >= 500 && responseCode <= 599) {
      return resolveAppResourceText(
        $r('app.string.settings_sync_self_host_error_http_server', responseCode));
    }
    return resolveAppResourceText(
      $r('app.string.settings_sync_self_host_error_http_failed', responseCode));
  }
}

export const AIRA_PERSONAL_SERVER_INSTANCE_SERVICE: AiraPersonalServerInstanceService =
  new AiraPersonalServerInstanceService();
