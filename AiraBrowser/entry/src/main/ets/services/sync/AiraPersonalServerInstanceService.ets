import { http } from '@kit.NetworkKit';
import {
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

const PERSONAL_SERVER_TIMEOUT_MS: number = 45000;
const PERSONAL_SERVER_MIN_PROTOCOL_VERSION: number = 1;
const PERSONAL_SERVER_MAX_PROTOCOL_VERSION: number = 1;

interface PersonalServerCapabilityDescriptor {
  version?: number;
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

  getAuthorizationHeader(): Promise<string> {
    if (this.token.length <= 0) {
      return Promise.reject(new Error('个人服务器设备凭据为空，请重新配对。'));
    }
    return Promise.resolve(`Bearer ${this.token}`);
  }
}

export class AiraPersonalServerInstanceService {
  normalizeBaseUrl(value: string): string {
    const normalized = value.trim().replace(/\/+$/, '');
    if (!/^https?:\/\/[^\s/?#]+(?::\d+)?(?:\/[^\s?#]*)?$/i.test(normalized)) {
      throw new Error('请输入完整的 HTTP 或 HTTPS 个人服务器地址。');
    }
    if (normalized.indexOf('@') >= 0) {
      throw new Error('个人服务器地址不能包含用户名或密码。');
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
      capabilities.bookmarks?.version !== 3 || capabilities.history?.version !== 1 ||
      capabilities.personalization?.version !== 2 || capabilities.novelBookshelf?.version !== 2 ||
      capabilities.pagePush?.version !== 1 || capabilities.crossDeviceTabs?.version !== 1) {
      throw new Error('该地址不是兼容的 Aira 个人服务器，或协议版本暂不受支持。');
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
      throw new Error('请输入配对码，并确认当前设备标识可用。');
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
      throw new Error(response.message ?? '个人服务器没有返回完整的设备凭据。');
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

  createPersonalizationStore(settings: AiraSyncSettings): PersonalizationSyncRemoteStore {
    const config = this.requireConfigured(settings);
    return new AiraCloudConditionalSnapshotRemoteStore<PersonalizationSyncSnapshot>(
      `${config.baseUrl}/v1/sync/personalization`,
      config.instanceId,
      {
        serviceLabel: '个人服务器个性化同步',
        conflictResponseCode: 'personalization_sync_write_conflict',
        conflictErrorMessage: PERSONALIZATION_SYNC_WRITE_CONFLICT,
        missingUidMessage: '请先连接个人服务器。'
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
        serviceLabel: '个人服务器小说书架同步',
        conflictResponseCode: 'novel_bookshelf_sync_write_conflict',
        conflictErrorMessage: NOVEL_BOOKSHELF_SYNC_WRITE_CONFLICT,
        missingUidMessage: '请先连接个人服务器。'
      },
      new AiraPersonalServerDeviceAuthProvider(config.deviceToken)
    );
  }

  requireConfigured(settings: AiraSyncSettings): AiraPersonalServerConfig {
    const config = resolveAiraPersonalServerConfig(settings);
    if (config.baseUrl.trim().length <= 0 || config.instanceId.trim().length <= 0 ||
      config.protocolVersion !== 1 || config.credentialId.trim().length <= 0 ||
      config.deviceToken.trim().length <= 0) {
      throw new Error('请先完成个人服务器发现与设备配对。');
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
      let value: T;
      try {
        value = JSON.parse(raw) as T;
      } catch (_error) {
        throw new Error('个人服务器返回了无法解析的响应。');
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const failure = value as PersonalServerPairingResponse;
        throw new Error(failure.message ?? `个人服务器请求失败（${response.responseCode}）。`);
      }
      return value;
    } finally {
      request.destroy();
    }
  }
}

export const AIRA_PERSONAL_SERVER_INSTANCE_SERVICE: AiraPersonalServerInstanceService =
  new AiraPersonalServerInstanceService();
