import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import {
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  LEAFTAB_SYNC_DEVICE_ID_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import { withBookmarkSyncExecutionLock } from '@/sync/leaftab/executionLock';

export const PERSONAL_SERVER_CONNECTION_STORAGE_KEY = 'aira_personal_server_connection_v2';
const REQUEST_TIMEOUT_MS = 30_000;

export type PersonalServerCapabilities = {
  bookmarks: boolean;
  history: boolean;
  pagePush: boolean;
  crossDeviceTabs: boolean;
};

export type PersonalServerConnection = {
  version: 2;
  baseUrl: string;
  instanceId: string;
  protocolVersion: number;
  credentialId: string;
  deviceToken: string;
  deviceId: string;
  deviceName: string;
  capabilities: PersonalServerCapabilities;
  pairedAt: number;
};

type DiscoveryResponse = {
  ok?: boolean;
  product?: string;
  message?: string;
  protocolVersion?: number;
  minimumClientProtocolVersion?: number;
  instanceId?: string;
  baseUrl?: string;
  capabilities?: Record<string, unknown>;
};

type PairingResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  instanceId?: string;
  protocolVersion?: number;
  deviceId?: string;
  credentialId?: string;
  token?: string;
};

type RemoteResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  [key: string]: unknown;
};

export class PersonalServerRemoteError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, message: string, status = 0) {
    super(message);
    this.name = 'PersonalServerRemoteError';
    this.code = code;
    this.status = status;
  }
}

export async function readPersonalServerConnection(): Promise<PersonalServerConnection | null> {
  const record = await readExtensionStorageRecord([PERSONAL_SERVER_CONNECTION_STORAGE_KEY]);
  return parseConnection(record[PERSONAL_SERVER_CONNECTION_STORAGE_KEY]);
}

export async function pairPersonalServer(
  baseUrl: string,
  pairingCode: string,
): Promise<PersonalServerConnection> {
  return withBookmarkSyncExecutionLock(async () => {
    const normalizedBaseUrl = normalizeBaseUrl(baseUrl);
    const discovery = await requestJson<DiscoveryResponse>(
      `${normalizedBaseUrl}/.well-known/aira`,
      'GET',
    );
    assertDiscovery(discovery);
    const device = await getOrCreatePersonalServerDevice();
    const canonicalBaseUrl = normalizeBaseUrl(String(discovery.baseUrl || normalizedBaseUrl));
    const response = await requestJson<PairingResponse>(
      `${canonicalBaseUrl}/v1/pairing/exchange`,
      'POST',
      {
        code: pairingCode.trim(),
        deviceId: device.deviceId,
        deviceName: device.deviceName,
        deviceKind: 'desktop',
      },
    );
    const instanceId = String(discovery.instanceId || '').trim();
    const credentialId = String(response.credentialId || '').trim();
    const deviceToken = String(response.token || '').trim();
    if (
      response.ok !== true
      || String(response.instanceId || '').trim() !== instanceId
      || String(response.deviceId || '').trim() !== device.deviceId
      || !credentialId
      || !deviceToken
    ) {
      throw new PersonalServerRemoteError(
        'invalid_pairing_response',
        response.message || '个人服务器没有返回完整的设备凭据。',
      );
    }
    const connection: PersonalServerConnection = {
      version: 2,
      baseUrl: canonicalBaseUrl,
      instanceId,
      protocolVersion: 1,
      credentialId,
      deviceToken,
      deviceId: device.deviceId,
      deviceName: device.deviceName,
      capabilities: parseCapabilities(discovery.capabilities),
      pairedAt: Date.now(),
    };
    await writeExtensionStorageRecord({
      [PERSONAL_SERVER_CONNECTION_STORAGE_KEY]: connection,
    });
    return connection;
  });
}

export async function disconnectPersonalServer(): Promise<void> {
  return withBookmarkSyncExecutionLock(async () => {
    const selectedRecord = await readExtensionStorageRecord([LEAFTAB_SELECTED_SYNC_SOURCE_KEY]);
    const keys = [PERSONAL_SERVER_CONNECTION_STORAGE_KEY];
    if (selectedRecord[LEAFTAB_SELECTED_SYNC_SOURCE_KEY] === 'personal-server') {
      keys.push(LEAFTAB_SELECTED_SYNC_SOURCE_KEY);
    }
    await removeExtensionStorageKeys(keys);
  });
}

export async function postPersonalServerJson<T extends RemoteResponse>(
  path: string,
  body: unknown,
  timeoutMs = REQUEST_TIMEOUT_MS,
  connectionOverride?: PersonalServerConnection,
): Promise<T> {
  const connection = connectionOverride || await readPersonalServerConnection();
  if (!connection) {
    throw new PersonalServerRemoteError('personal_server_required', '请先连接个人服务器。');
  }
  return requestJson<T>(
    `${connection.baseUrl}${path.startsWith('/') ? path : `/${path}`}`,
    'POST',
    body,
    connection.deviceToken,
    timeoutMs,
  );
}

export function personalServerAccountScope(connection: PersonalServerConnection): string {
  return `personal-server:${connection.instanceId}`;
}

async function getOrCreatePersonalServerDevice(): Promise<{ deviceId: string; deviceName: string }> {
  const record = await readExtensionStorageRecord([LEAFTAB_SYNC_DEVICE_ID_KEY]);
  const existing = String(record[LEAFTAB_SYNC_DEVICE_ID_KEY] || '').trim();
  const deviceId = existing || createDeviceId();
  if (!existing) {
    await writeExtensionStorageRecord({ [LEAFTAB_SYNC_DEVICE_ID_KEY]: deviceId });
  }
  return { deviceId, deviceName: resolveDeviceName() };
}

function assertDiscovery(value: DiscoveryResponse): void {
  const capabilities = parseCapabilities(value.capabilities);
  if (
    value.ok !== true
    || value.product !== 'aira-personal-server'
    || Number(value.protocolVersion || 0) !== 1
    || Number(value.minimumClientProtocolVersion || 0) > 1
    || !String(value.instanceId || '').trim()
    || !capabilities.bookmarks
    || !capabilities.history
    || !capabilities.pagePush
    || !capabilities.crossDeviceTabs
  ) {
    throw new PersonalServerRemoteError(
      'unsupported_personal_server',
      value.message || '该服务器不支持 Aira-sync 所需的 Personal Server 协议。',
    );
  }
}

function parseCapabilities(value: unknown): PersonalServerCapabilities {
  const raw = value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
  return {
    bookmarks: hasVersionAndProtocol(raw.bookmarks, 4, 'aira-cloud-bookmarks-v4'),
    history: hasVersion(raw.history, 1),
    pagePush: hasVersion(raw.pagePush, 1),
    crossDeviceTabs: hasVersion(raw.crossDeviceTabs, 1),
  };
}

function hasVersion(value: unknown, expected: number): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  return Number((value as { version?: unknown }).version || 0) === expected;
}

function hasVersionAndProtocol(value: unknown, expected: number, protocol: string): boolean {
  if (!hasVersion(value, expected)) return false;
  return String((value as { protocol?: unknown }).protocol || '').trim() === protocol;
}

function parseConnection(value: unknown): PersonalServerConnection | null {
  try {
    const raw = typeof value === 'string'
      ? JSON.parse(value) as Partial<PersonalServerConnection>
      : value as Partial<PersonalServerConnection>;
    if (
      !raw
      || raw.version !== 2
      || raw.protocolVersion !== 1
      || !raw.baseUrl
      || !raw.instanceId
      || !raw.credentialId
      || !raw.deviceToken
      || !raw.deviceId
    ) return null;
    return {
      version: 2,
      baseUrl: normalizeBaseUrl(raw.baseUrl),
      instanceId: String(raw.instanceId).trim(),
      protocolVersion: 1,
      credentialId: String(raw.credentialId).trim(),
      deviceToken: String(raw.deviceToken).trim(),
      deviceId: String(raw.deviceId).trim(),
      deviceName: String(raw.deviceName || 'Aira-sync Desktop').trim(),
      capabilities: {
        bookmarks: raw.capabilities?.bookmarks === true,
        history: raw.capabilities?.history === true,
        pagePush: raw.capabilities?.pagePush === true,
        crossDeviceTabs: raw.capabilities?.crossDeviceTabs === true,
      },
      pairedAt: Number(raw.pairedAt || 0),
    };
  } catch {
    return null;
  }
}

function normalizeBaseUrl(value: string): string {
  try {
    const url = new URL(String(value || '').trim());
    if ((url.protocol !== 'http:' && url.protocol !== 'https:') || url.username || url.password) throw new Error();
    url.hash = '';
    url.search = '';
    return url.toString().replace(/\/+$/, '');
  } catch {
    throw new PersonalServerRemoteError(
      'invalid_personal_server_url',
      '请输入有效的 Personal Server HTTP(S) 地址。',
    );
  }
}

async function requestJson<T extends RemoteResponse>(
  url: string,
  method: 'GET' | 'POST',
  body?: unknown,
  token = '',
  timeoutMs = REQUEST_TIMEOUT_MS,
): Promise<T> {
  const controller = new AbortController();
  const timeout = globalThis.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method,
      headers: {
        Accept: 'application/json',
        ...(method === 'POST' ? { 'Content-Type': 'application/json; charset=utf-8' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: method === 'POST' ? JSON.stringify(body || {}) : undefined,
      signal: controller.signal,
      cache: 'no-store',
    });
    const text = await response.text();
    let parsed: RemoteResponse;
    try {
      parsed = text ? JSON.parse(text) as RemoteResponse : {};
    } catch {
      throw new PersonalServerRemoteError('invalid_response', '个人服务器返回了无法解析的数据。', response.status);
    }
    if (!response.ok || parsed.ok !== true) {
      throw new PersonalServerRemoteError(
        String(parsed.code || (response.ok ? 'remote_rejected' : 'http_error')),
        String(parsed.message || `个人服务器请求失败（${response.status}）。`),
        response.status,
      );
    }
    return parsed as T;
  } catch (error) {
    if (error instanceof PersonalServerRemoteError) throw error;
    throw new PersonalServerRemoteError(
      'network_unavailable',
      String((error as Error)?.message || '无法连接个人服务器。'),
    );
  } finally {
    globalThis.clearTimeout(timeout);
  }
}

function createDeviceId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return `desktop_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function resolveDeviceName(): string {
  const userAgent = typeof navigator === 'undefined' ? '' : String(navigator.userAgent || '');
  if (userAgent.includes('Edg/')) return 'Microsoft Edge Desktop';
  if (userAgent.includes('Chrome/')) return 'Google Chrome Desktop';
  if (userAgent.includes('Firefox/')) return 'Firefox Desktop';
  return 'Aira-sync Desktop';
}
