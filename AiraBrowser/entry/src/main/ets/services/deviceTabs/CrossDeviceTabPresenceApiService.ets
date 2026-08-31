import { http } from '@kit.NetworkKit';
import {
  AIRA_DISTRIBUTION_CAPABILITY_OWNER,
  AIRA_HOSTED_API_BASE_URL
} from '../../common/config/AiraDistributionCapabilityOwner';
import {
  CrossDeviceTabPresenceDevice,
  CrossDeviceTabPresenceListResult,
  CrossDeviceTabPresenceLocalDevice,
  CrossDeviceTabPresenceTab
} from '../../core/deviceTabs/CrossDeviceTabPresenceModels';
import { HuaweiAccountSyncAuthService } from '../sync/HuaweiAccountSyncAuthService';

const AIRA_DEVICE_TABS_API_BASE_URL: string = AIRA_HOSTED_API_BASE_URL + '/device-tabs/v1';
const AIRA_DEVICE_TABS_TIMEOUT_MS: number = 15000;

interface CrossDeviceTabPresencePublishBody {
  uid: string;
  deviceId: string;
  source: string;
  authToken: string;
  device: CrossDeviceTabPresenceLocalDevice;
  tabs: CrossDeviceTabPresenceTab[];
}

interface CrossDeviceTabPresenceAccessBody {
  uid: string;
  deviceId: string;
  source: string;
  authToken: string;
}

interface CrossDeviceTabPresenceApiResponse {
  ok?: boolean;
  code?: string;
  message?: string;
  serverTime?: number;
  onlineWindowMs?: number;
  devices?: Object[];
}

export interface CrossDeviceTabPresenceHttpAdapter {
  post(url: string, body: Object, timeoutMs: number): Promise<Object | string | null | undefined>;
}

export class CrossDeviceTabPresenceApiError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

class NetworkCrossDeviceTabPresenceHttpAdapter implements CrossDeviceTabPresenceHttpAdapter {
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
      if (typeof response.result === 'string' || typeof response.result === 'object') {
        return response.result as string | Object | null | undefined;
      }
      const fallback: CrossDeviceTabPresenceApiResponse = {
        ok: false,
        code: 'http_error',
        message: `跨设备标签页服务请求失败（${response.responseCode}）。`
      };
      return fallback;
    } finally {
      request.destroy();
    }
  }
}

export class CrossDeviceTabPresenceApiService {
  private readonly adapter: CrossDeviceTabPresenceHttpAdapter;
  private readonly authService: HuaweiAccountSyncAuthService;

  constructor(
    adapter?: CrossDeviceTabPresenceHttpAdapter,
    authService?: HuaweiAccountSyncAuthService
  ) {
    this.adapter = adapter ?? new NetworkCrossDeviceTabPresenceHttpAdapter();
    this.authService = authService ?? new HuaweiAccountSyncAuthService();
  }

  async publish(
    uid: string,
    device: CrossDeviceTabPresenceLocalDevice,
    tabs: CrossDeviceTabPresenceTab[]
  ): Promise<void> {
    this.assertDistributionAvailable();
    const token = await this.requireAccessToken(uid);
    const body: CrossDeviceTabPresencePublishBody = {
      uid: uid.trim(),
      deviceId: device.deviceId,
      source: 'harmonyos_cross_device_tabs_publish',
      authToken: token,
      device: device,
      tabs: tabs
    };
    const response = await this.post('/publish', body);
    this.requireSuccess(response, '暂时无法发布这台手机的标签页。');
  }

  async list(uid: string, deviceId: string): Promise<CrossDeviceTabPresenceListResult> {
    this.assertDistributionAvailable();
    const body = await this.buildAccessBody(uid, deviceId, 'harmonyos_cross_device_tabs_list');
    const response = await this.post('/list', body);
    this.requireSuccess(response, '暂时无法读取电脑标签页。');
    const devices: CrossDeviceTabPresenceDevice[] = [];
    const rawDevices = response.devices ?? [];
    rawDevices.forEach((raw: Object): void => {
      const device = this.parseDesktopDevice(raw);
      if (device !== undefined) {
        devices.push(device);
      }
    });
    return {
      serverTime: this.normalizeNumber(response.serverTime, Date.now()),
      onlineWindowMs: this.normalizeNumber(response.onlineWindowMs, 120000),
      devices: devices
    };
  }

  async clear(uid: string, deviceId: string): Promise<void> {
    this.assertDistributionAvailable();
    const body = await this.buildAccessBody(uid, deviceId, 'harmonyos_cross_device_tabs_clear');
    const response = await this.post('/clear', body);
    this.requireSuccess(response, '暂时无法清除这台手机的标签页状态。');
  }

  private async buildAccessBody(
    uid: string,
    deviceId: string,
    source: string
  ): Promise<CrossDeviceTabPresenceAccessBody> {
    const token = await this.requireAccessToken(uid);
    return {
      uid: uid.trim(),
      deviceId: deviceId.trim(),
      source: source,
      authToken: token
    };
  }

  private assertDistributionAvailable(): void {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      throw new CrossDeviceTabPresenceApiError(
        'distribution_unavailable',
        AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud')
      );
    }
  }

  private async requireAccessToken(uid: string): Promise<string> {
    const normalizedUid = uid.trim();
    if (normalizedUid.length === 0) {
      throw new Error('请先使用华为账号登录。');
    }
    const token = await this.authService.getCurrentAccessTokenForUid(normalizedUid, false);
    if (token.length === 0) {
      throw new Error('请重新登录华为账号后再继续。');
    }
    return token;
  }

  private async post(path: string, body: Object): Promise<CrossDeviceTabPresenceApiResponse> {
    const value = await this.adapter.post(
      `${AIRA_DEVICE_TABS_API_BASE_URL}${path}`,
      body,
      AIRA_DEVICE_TABS_TIMEOUT_MS
    );
    if (value === undefined || value === null) {
      throw new Error('跨设备标签页服务没有返回结果。');
    }
    if (typeof value === 'string') {
      try {
        return JSON.parse(value) as CrossDeviceTabPresenceApiResponse;
      } catch (_error) {
        throw new Error('跨设备标签页服务返回的数据无法解析。');
      }
    }
    return value as CrossDeviceTabPresenceApiResponse;
  }

  private requireSuccess(response: CrossDeviceTabPresenceApiResponse, fallback: string): void {
    if (response.ok === true) {
      return;
    }
    const message = response.message?.trim() ?? '';
    throw new CrossDeviceTabPresenceApiError(
      response.code?.trim() ?? '',
      message.length > 0 ? message : fallback
    );
  }

  private parseDesktopDevice(value: Object): CrossDeviceTabPresenceDevice | undefined {
    const raw = value as Record<string, Object | string | boolean | number | undefined | null>;
    const deviceId = String(raw.deviceId ?? '').trim();
    if (deviceId.length === 0 || String(raw.deviceKind ?? '') !== 'desktop') {
      return undefined;
    }
    const tabs: CrossDeviceTabPresenceTab[] = [];
    if (Array.isArray(raw.tabs)) {
      (raw.tabs as Object[]).forEach((tabValue: Object): void => {
        const tab = this.parseTab(tabValue);
        if (tab !== undefined) {
          tabs.push(tab);
        }
      });
    }
    return {
      deviceId: deviceId,
      deviceKind: 'desktop',
      deviceName: String(raw.deviceName ?? '').trim(),
      platform: String(raw.platform ?? '').trim(),
      model: String(raw.model ?? '').trim(),
      browserName: String(raw.browserName ?? '').trim(),
      browserVersion: String(raw.browserVersion ?? '').trim(),
      tabs: tabs,
      tabCount: this.normalizeNumber(raw.tabCount, tabs.length),
      updatedAt: this.normalizeNumber(raw.updatedAt, 0),
      expiresAt: this.normalizeNumber(raw.expiresAt, 0),
      freshnessMs: this.normalizeNumber(raw.freshnessMs, 0)
    };
  }

  private parseTab(value: Object): CrossDeviceTabPresenceTab | undefined {
    const raw = value as Record<string, Object | string | boolean | number | undefined | null>;
    const url = this.normalizeHttpUrl(String(raw.url ?? ''));
    if (url.length === 0) {
      return undefined;
    }
    return {
      title: String(raw.title ?? '').trim(),
      url: url,
      active: raw.active === true,
      lastActiveAt: this.normalizeNumber(raw.lastActiveAt, 0),
      windowOrder: this.normalizeNumber(raw.windowOrder, 0),
      tabOrder: this.normalizeNumber(raw.tabOrder, 0)
    };
  }

  private normalizeHttpUrl(value: string): string {
    const url = value.trim();
    const lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return '';
    }
    const schemeEnd = url.indexOf('://');
    const authorityStart = schemeEnd + 3;
    let authorityEnd = url.length;
    const separators: string[] = ['/', '?', '#'];
    separators.forEach((separator: string): void => {
      const index = url.indexOf(separator, authorityStart);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    });
    const authority = url.slice(authorityStart, authorityEnd);
    if (authority.length === 0 || authority.includes('@')) {
      return '';
    }
    return url;
  }

  private normalizeNumber(value: Object | string | boolean | number | undefined | null, fallback: number): number {
    const normalized = Number(value ?? fallback);
    return Number.isFinite(normalized) && normalized >= 0 ? normalized : fallback;
  }
}
