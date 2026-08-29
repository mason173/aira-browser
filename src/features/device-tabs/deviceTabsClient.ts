import {
  postAiraDesktopJson,
  readAiraDesktopAuthorizedSession,
  readAiraDesktopConnectionSnapshot,
} from '@/features/desktop-connection/desktopConnectionRuntime';
import type {
  CrossDeviceTab,
  CrossDeviceTabDevice,
  CrossDeviceTabList,
  DesktopDeviceMetadata,
} from './deviceTabsModels';

type ApiResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  serverTime?: number;
  onlineWindowMs?: number;
  devices?: unknown[];
};

type NavigatorUserAgentData = {
  platform?: string;
};

export async function publishCurrentDesktopTabs(): Promise<boolean> {
  const context = await readDesktopContext();
  if (!context || !context.pro) {
    return false;
  }
  const tabs = await queryPublishableTabs();
  await postAiraDesktopJson<ApiResponse>('/device-tabs/v1/publish', {
    ...toCredentials(context),
    source: 'airatab_cross_device_tabs_publish',
    device: context.device,
    tabs,
  });
  return true;
}

export async function listPhoneTabs(): Promise<CrossDeviceTabList> {
  const context = await readDesktopContext();
  if (!context) {
    throw new Error('请先连接 Aira 手机端。');
  }
  if (!context.pro) {
    throw new Error('跨设备标签页需要 Aira Pro。');
  }
  const response = await postAiraDesktopJson<ApiResponse>('/device-tabs/v1/list', {
    ...toCredentials(context),
    source: 'airatab_cross_device_tabs_list',
  });
  return {
    serverTime: numberOr(response.serverTime, Date.now()),
    onlineWindowMs: numberOr(response.onlineWindowMs, 120_000),
    devices: Array.isArray(response.devices)
      ? response.devices.map(parseDevice).filter((device): device is CrossDeviceTabDevice => device !== null)
      : [],
  };
}

export async function clearDesktopTabSnapshot(): Promise<boolean> {
  const context = await readDesktopContext();
  if (!context) {
    return false;
  }
  await postAiraDesktopJson<ApiResponse>('/device-tabs/v1/clear', {
    ...toCredentials(context),
    source: 'airatab_cross_device_tabs_clear',
  });
  return true;
}

async function readDesktopContext(): Promise<{
  uid: string;
  deviceCredential: string;
  pro: boolean;
  device: DesktopDeviceMetadata;
} | null> {
  const [session, snapshot] = await Promise.all([
    readAiraDesktopAuthorizedSession(),
    readAiraDesktopConnectionSnapshot(),
  ]);
  if (!session?.uid || !session.deviceCredential || snapshot.status === 'reauth-required') {
    return null;
  }
  const metadata = resolveBrowserMetadata();
  const expiresAt = Number(snapshot.membership?.expiresAt || 0);
  const pro = String(snapshot.membership?.plan || '').trim().toLowerCase() === 'pro'
    && (expiresAt === 0 || expiresAt > Date.now());
  return {
    uid: session.uid,
    deviceCredential: session.deviceCredential,
    pro,
    device: {
      deviceId: session.deviceId,
      deviceName: `${metadata.browserName} · ${metadata.platform}`,
      platform: metadata.platform,
      model: '',
      browserName: metadata.browserName,
      browserVersion: metadata.browserVersion,
    },
  };
}

async function queryPublishableTabs(): Promise<CrossDeviceTab[]> {
  const tabsApi = globalThis.chrome?.tabs;
  if (!tabsApi?.query) {
    return [];
  }
  const browserTabs = await tabsApi.query({});
  const windowOrder = new Map<number, number>();
  const projected: CrossDeviceTab[] = [];
  for (const tab of browserTabs) {
    if (tab.incognito) continue;
    const url = normalizeHttpUrl(tab.url || tab.pendingUrl || '');
    if (!url) continue;
    const browserWindowId = Number(tab.windowId || 0);
    if (!windowOrder.has(browserWindowId)) {
      windowOrder.set(browserWindowId, windowOrder.size);
    }
    projected.push({
      title: String(tab.title || '').trim().slice(0, 512),
      url,
      active: tab.active === true,
      lastActiveAt: normalizeTimestamp(tab.lastAccessed),
      windowOrder: windowOrder.get(browserWindowId) || 0,
      tabOrder: Math.max(0, Number(tab.index || 0)),
    });
    if (projected.length >= 100) break;
  }
  return projected;
}

function normalizeHttpUrl(value: string): string {
  try {
    const parsed = new URL(value);
    if ((parsed.protocol !== 'http:' && parsed.protocol !== 'https:') || parsed.username || parsed.password) {
      return '';
    }
    return parsed.toString();
  } catch {
    return '';
  }
}

function resolveBrowserMetadata(): { platform: string; browserName: string; browserVersion: string } {
  const userAgent = typeof navigator === 'undefined' ? '' : String(navigator.userAgent || '');
  const userAgentData = typeof navigator === 'undefined'
    ? undefined
    : (navigator as Navigator & { userAgentData?: NavigatorUserAgentData }).userAgentData;
  const platform = String(userAgentData?.platform || '').trim()
    || (userAgent.includes('Windows') ? 'Windows'
      : userAgent.includes('Mac OS X') ? 'macOS'
        : userAgent.includes('Linux') ? 'Linux'
          : 'Desktop');
  const edge = userAgent.match(/Edg\/([0-9.]+)/);
  if (edge) return { platform, browserName: 'Microsoft Edge', browserVersion: edge[1] };
  const chrome = userAgent.match(/Chrome\/([0-9.]+)/);
  if (chrome) return { platform, browserName: 'Google Chrome', browserVersion: chrome[1] };
  return { platform, browserName: 'AiraTab', browserVersion: '' };
}

function parseDevice(value: unknown): CrossDeviceTabDevice | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const deviceId = String(raw.deviceId || '').trim();
  if (!deviceId || raw.deviceKind !== 'phone') return null;
  return {
    deviceId,
    deviceKind: 'phone',
    deviceName: String(raw.deviceName || '').trim(),
    platform: String(raw.platform || '').trim(),
    model: String(raw.model || '').trim(),
    browserName: String(raw.browserName || '').trim(),
    browserVersion: String(raw.browserVersion || '').trim(),
    tabs: Array.isArray(raw.tabs) ? raw.tabs.map(parseTab).filter((tab): tab is CrossDeviceTab => tab !== null) : [],
    tabCount: numberOr(raw.tabCount, 0),
    updatedAt: numberOr(raw.updatedAt, 0),
    expiresAt: numberOr(raw.expiresAt, 0),
    freshnessMs: numberOr(raw.freshnessMs, 0),
  };
}

function parseTab(value: unknown): CrossDeviceTab | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const url = normalizeHttpUrl(String(raw.url || ''));
  if (!url) return null;
  return {
    title: String(raw.title || '').trim(),
    url,
    active: raw.active === true,
    lastActiveAt: numberOr(raw.lastActiveAt, 0),
    windowOrder: numberOr(raw.windowOrder, 0),
    tabOrder: numberOr(raw.tabOrder, 0),
  };
}

function toCredentials(context: { uid: string; deviceCredential: string; device: DesktopDeviceMetadata }) {
  return {
    uid: context.uid,
    desktopPushToken: context.deviceCredential,
    deviceId: context.device.deviceId,
  };
}

function normalizeTimestamp(value: unknown): number {
  const timestamp = Number(value || 0);
  return Number.isSafeInteger(timestamp) && timestamp > 0 ? timestamp : 0;
}

function numberOr(value: unknown, fallback: number): number {
  const normalized = Number(value);
  return Number.isFinite(normalized) ? normalized : fallback;
}
