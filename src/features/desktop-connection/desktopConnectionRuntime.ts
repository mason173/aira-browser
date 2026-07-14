import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import {
  AiraDesktopConnectionModule,
  AiraDesktopConnectionRemoteError,
  type AiraDesktopAuthorizedSession,
  type AiraDesktopConnectionRecord,
  type AiraDesktopConnectionRemote,
  type AiraDesktopConnectionSnapshot,
  type AiraDesktopConnectionStorage,
  type AiraDesktopMembershipResponse,
  type AiraDesktopPairingSession,
  type AiraDesktopPairingStatus,
} from './AiraDesktopConnectionModule';

const AIRA_API_BASE_URL = 'https://api.aira.cool';
const AIRA_DESKTOP_REQUEST_TIMEOUT_MS = 25_000;
export const AIRA_DESKTOP_CONNECTION_STORAGE_KEY = 'aira_desktop_connection_v1';
const AIRA_DESKTOP_DEVICE_ID_KEY = 'aira_desktop_device_id_v1';
const LEGACY_DESKTOP_LOGIN_PROFILE_KEY = 'aira_desktop_login_profile_v1';
const LEGACY_SYNC_DEVICE_ID_KEY = 'leaftab_sync_v1_device_id';

type RemoteResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  [key: string]: unknown;
};

type LegacyDesktopLoginProfile = {
  uid?: string;
  uidSuffix?: string;
  displayName?: string;
  avatarUri?: string;
  membershipPlan?: string;
  membershipStatus?: string;
  membershipExpiresAt?: number;
  membershipCheckedAt?: string;
  desktopPushToken?: string;
};

let modulePromise: Promise<AiraDesktopConnectionModule> | null = null;

export async function getAiraDesktopConnectionModule(): Promise<AiraDesktopConnectionModule> {
  if (!modulePromise) {
    modulePromise = createRuntimeModule().catch((error) => {
      modulePromise = null;
      throw error;
    });
  }
  return modulePromise;
}

export async function readAiraDesktopConnectionSnapshot(): Promise<AiraDesktopConnectionSnapshot> {
  return (await getAiraDesktopConnectionModule()).getSnapshot();
}

export async function readAiraDesktopAuthorizedSession(): Promise<AiraDesktopAuthorizedSession | null> {
  return (await getAiraDesktopConnectionModule()).getAuthorizedSession();
}

export async function refreshAiraDesktopConnectionMembership(
  options: { force?: boolean } = {},
): Promise<AiraDesktopConnectionSnapshot> {
  return (await getAiraDesktopConnectionModule()).refreshMembership(options);
}

export async function disconnectAiraDesktopDevice(): Promise<AiraDesktopConnectionSnapshot> {
  return (await getAiraDesktopConnectionModule()).disconnectCurrentDevice();
}

export async function recordAiraDesktopConnectionFailure(error: unknown): Promise<AiraDesktopConnectionSnapshot> {
  return (await getAiraDesktopConnectionModule()).recordRemoteFailure(error);
}

async function createRuntimeModule(): Promise<AiraDesktopConnectionModule> {
  const device = await getOrCreateDesktopDeviceIdentity();
  return new AiraDesktopConnectionModule({
    storage: new ChromeDesktopConnectionStorage(device),
    remote: new HttpAiraDesktopConnectionRemote(),
    device,
  });
}

class ChromeDesktopConnectionStorage implements AiraDesktopConnectionStorage {
  constructor(private readonly device: { deviceId: string; deviceName: string }) {}

  async read(): Promise<AiraDesktopConnectionRecord | null> {
    const record = await readExtensionStorageRecord([
      AIRA_DESKTOP_CONNECTION_STORAGE_KEY,
      LEGACY_DESKTOP_LOGIN_PROFILE_KEY,
    ]);
    const stored = parseConnectionRecord(record[AIRA_DESKTOP_CONNECTION_STORAGE_KEY]);
    if (stored) {
      if (record[LEGACY_DESKTOP_LOGIN_PROFILE_KEY] !== undefined) {
        await removeExtensionStorageKeys([LEGACY_DESKTOP_LOGIN_PROFILE_KEY]);
      }
      removeLegacyProfileFromPopup();
      return stored;
    }
    const migrated = migrateLegacyProfile(
      parseLegacyProfile(record[LEGACY_DESKTOP_LOGIN_PROFILE_KEY]) || readLegacyProfileFromPopup(),
      this.device,
    );
    if (!migrated) {
      return null;
    }
    await this.write(migrated);
    await removeExtensionStorageKeys([LEGACY_DESKTOP_LOGIN_PROFILE_KEY]);
    removeLegacyProfileFromPopup();
    return migrated;
  }

  async write(record: AiraDesktopConnectionRecord): Promise<void> {
    const serialized = JSON.stringify(record);
    await writeExtensionStorageRecord({
      [AIRA_DESKTOP_CONNECTION_STORAGE_KEY]: serialized,
    });
  }

  async clear(): Promise<void> {
    await removeExtensionStorageKeys([
      AIRA_DESKTOP_CONNECTION_STORAGE_KEY,
      LEGACY_DESKTOP_LOGIN_PROFILE_KEY,
    ]);
    removeLegacyProfileFromPopup();
  }
}

class HttpAiraDesktopConnectionRemote implements AiraDesktopConnectionRemote {
  async createPairing(device: { deviceId: string; deviceName: string }): Promise<AiraDesktopPairingSession> {
    const response = await postAiraDesktopJson<RemoteResponse>('/desktop-login/create', device);
    return {
      sessionId: requiredString(response.sessionId, 'Login service returned an invalid session.'),
      pollToken: requiredString(response.pollToken, 'Login service returned an invalid poll token.'),
      deviceCredential: requiredString(response.desktopPushToken, 'Login service returned an invalid device credential.'),
      deviceId: requiredString(response.deviceId || device.deviceId, 'Login service returned an invalid device id.'),
      deviceName: String(response.deviceName || device.deviceName || '').trim(),
      qrPayload: requiredString(response.qrPayload, 'Login service returned an invalid QR payload.'),
      expiresAt: Number(response.expiresAt || 0),
      pollIntervalMs: normalizePollInterval(response.pollIntervalMs),
    };
  }

  async pollPairing(session: AiraDesktopPairingSession): Promise<AiraDesktopPairingStatus> {
    const response = await postAiraDesktopJson<RemoteResponse>('/desktop-login/status', {
      sessionId: session.sessionId,
      pollToken: session.pollToken,
    });
    if (response.status === 'confirmed' && response.account && typeof response.account === 'object') {
      const account = response.account as Record<string, unknown>;
      return {
        status: 'confirmed',
        account: {
          uid: requiredString(account.uid, 'Login service returned an invalid account.'),
          uidSuffix: String(account.uidSuffix || '').trim(),
          displayName: String(account.displayName || '').trim(),
          avatarUri: String(account.avatarUri || '').trim(),
        },
        membership: {
          plan: String(account.membershipPlan || 'club').trim(),
          status: String(account.membershipStatus || 'missing_plan_default_club').trim(),
          expiresAt: Number(account.membershipExpiresAt || 0),
          checkedAt: new Date().toISOString(),
        },
        confirmedAt: Number(response.confirmedAt || Date.now()),
      };
    }
    return {
      status: response.status === 'expired' ? 'expired' : 'pending',
      expiresAt: Number(response.expiresAt || session.expiresAt),
      pollIntervalMs: normalizePollInterval(response.pollIntervalMs),
    };
  }

  async refreshMembership(session: AiraDesktopAuthorizedSession): Promise<AiraDesktopMembershipResponse> {
    const response = await postAiraDesktopJson<RemoteResponse>('/desktop-login/membership-state', {
      desktopPushToken: session.deviceCredential,
      deviceId: session.deviceId,
      deviceName: session.deviceName,
      source: 'airatab_desktop_membership_refresh',
    });
    const grant = response.membershipGrant && typeof response.membershipGrant === 'object'
      ? response.membershipGrant as Record<string, unknown>
      : {};
    return {
      account: {
        uid: String(response.uid || session.uid).trim(),
        uidSuffix: String(response.uidSuffix || '').trim(),
      },
      membership: {
        plan: String(response.membershipPlan || grant.currentPlan || grant.plan || 'club').trim(),
        status: String(response.membershipStatus || grant.status || 'missing_plan_default_club').trim(),
        expiresAt: Number(grant.expiresAt || 0),
        checkedAt: new Date().toISOString(),
      },
    };
  }

  async revoke(session: AiraDesktopAuthorizedSession): Promise<void> {
    await postAiraDesktopJson<RemoteResponse>('/desktop-session/revoke', {
      desktopPushToken: session.deviceCredential,
      deviceId: session.deviceId,
      deviceName: session.deviceName,
    });
  }
}

async function getOrCreateDesktopDeviceIdentity(): Promise<{ deviceId: string; deviceName: string }> {
  const record = await readExtensionStorageRecord([
    AIRA_DESKTOP_DEVICE_ID_KEY,
    LEGACY_SYNC_DEVICE_ID_KEY,
  ]);
  const existing = String(record[AIRA_DESKTOP_DEVICE_ID_KEY] || record[LEGACY_SYNC_DEVICE_ID_KEY] || '').trim();
  const deviceId = existing || createDeviceId();
  if (!existing || !record[AIRA_DESKTOP_DEVICE_ID_KEY]) {
    await writeExtensionStorageRecord({
      [AIRA_DESKTOP_DEVICE_ID_KEY]: deviceId,
    });
  }
  return {
    deviceId,
    deviceName: resolveDeviceName(),
  };
}

export async function postAiraDesktopJson<T>(path: string, body: unknown): Promise<T> {
  const controller = new AbortController();
  const timeout = globalThis.setTimeout(() => controller.abort(), AIRA_DESKTOP_REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(`${AIRA_API_BASE_URL}${path}`, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const text = await response.text();
    let parsed: RemoteResponse = {};
    try {
      parsed = text ? JSON.parse(text) as RemoteResponse : {};
    } catch {
      throw new AiraDesktopConnectionRemoteError('invalid_response', 'Aira 服务返回了无法解析的数据。', response.status);
    }
    if (!response.ok || parsed.ok !== true) {
      throw new AiraDesktopConnectionRemoteError(
        String(parsed.code || (response.ok ? 'remote_rejected' : 'http_error')),
        String(parsed.message || `Aira 服务请求失败（${response.status}）。`),
        response.status,
      );
    }
    return parsed as T;
  } catch (error) {
    if (error instanceof AiraDesktopConnectionRemoteError) {
      throw error;
    }
    throw new AiraDesktopConnectionRemoteError(
      'network_unavailable',
      String((error as Error)?.message || 'Aira 服务暂时不可用。'),
    );
  } finally {
    globalThis.clearTimeout(timeout);
  }
}

function parseConnectionRecord(value: unknown): AiraDesktopConnectionRecord | null {
  try {
    const raw = typeof value === 'string' ? JSON.parse(value) as AiraDesktopConnectionRecord : value as AiraDesktopConnectionRecord;
    const status = String(raw?.status || '');
    const accountUid = String(raw?.account?.uid || '').trim();
    const credential = String(raw?.credential || '').trim();
    if (
      !raw
      || raw.version !== 1
      || !String(raw.deviceId || '').trim()
      || !['disconnected', 'connected', 'degraded', 'reauth-required'].includes(status)
      || ((status === 'connected' || status === 'degraded') && (!accountUid || !credential))
      || (status === 'reauth-required' && !accountUid)
    ) {
      return null;
    }
    return {
      ...raw,
      status: status as AiraDesktopConnectionRecord['status'],
      deviceId: String(raw.deviceId || '').trim(),
      deviceName: String(raw.deviceName || '').trim(),
      credential,
    };
  } catch {
    return null;
  }
}

function parseLegacyProfile(value: unknown): LegacyDesktopLoginProfile | null {
  try {
    if (!value) return null;
    return typeof value === 'string'
      ? JSON.parse(value) as LegacyDesktopLoginProfile
      : value as LegacyDesktopLoginProfile;
  } catch {
    return null;
  }
}

function readLegacyProfileFromPopup(): LegacyDesktopLoginProfile | null {
  try {
    return parseLegacyProfile(localStorage.getItem(LEGACY_DESKTOP_LOGIN_PROFILE_KEY));
  } catch {
    return null;
  }
}

function migrateLegacyProfile(
  legacy: LegacyDesktopLoginProfile | null,
  device: { deviceId: string; deviceName: string },
): AiraDesktopConnectionRecord | null {
  const uid = String(legacy?.uid || '').trim();
  const credential = String(legacy?.desktopPushToken || '').trim();
  if (!uid || !credential) {
    return null;
  }
  return {
    version: 1,
    status: 'connected',
    deviceId: device.deviceId,
    deviceName: device.deviceName,
    account: {
      uid,
      uidSuffix: String(legacy?.uidSuffix || uid.slice(-6)).trim(),
      displayName: String(legacy?.displayName || '').trim() || `Aira ${uid.slice(-6)}`,
      avatarUri: String(legacy?.avatarUri || '').trim(),
    },
    membership: {
      plan: String(legacy?.membershipPlan || 'club').trim(),
      status: String(legacy?.membershipStatus || 'missing_plan_default_club').trim(),
      expiresAt: Number(legacy?.membershipExpiresAt || 0),
      checkedAt: String(legacy?.membershipCheckedAt || '').trim(),
    },
    credential,
    lastError: null,
  };
}

function removeLegacyProfileFromPopup(): void {
  try {
    localStorage.removeItem(LEGACY_DESKTOP_LOGIN_PROFILE_KEY);
  } catch {
    // Extension service workers do not expose localStorage.
  }
}

function requiredString(value: unknown, message: string): string {
  const normalized = String(value || '').trim();
  if (!normalized) {
    throw new AiraDesktopConnectionRemoteError('invalid_response', message);
  }
  return normalized;
}

function normalizePollInterval(value: unknown): number {
  const interval = Number(value || 1800);
  if (!Number.isFinite(interval)) return 1800;
  return Math.min(5000, Math.max(1000, Math.floor(interval)));
}

function createDeviceId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `desktop_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function resolveDeviceName(): string {
  const userAgent = typeof navigator !== 'undefined' ? String(navigator.userAgent || '').trim() : '';
  return userAgent.slice(0, 120) || 'AiraTab Desktop';
}
