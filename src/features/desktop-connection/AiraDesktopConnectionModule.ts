export type AiraDesktopConnectionStatus =
  | 'disconnected'
  | 'connected'
  | 'degraded'
  | 'reauth-required';

export type AiraDesktopConnectionAccount = {
  uid: string;
  uidSuffix: string;
  displayName: string;
  avatarUri: string;
};

export type AiraDesktopConnectionMembership = {
  plan: string;
  status: string;
  expiresAt: number;
  checkedAt: string;
};

export type AiraDesktopConnectionErrorState = {
  code: string;
  message: string;
  occurredAt: string;
} | null;

export type AiraDesktopConnectionRecord = {
  version: 1;
  status: AiraDesktopConnectionStatus;
  deviceId: string;
  deviceName: string;
  account: AiraDesktopConnectionAccount | null;
  membership: AiraDesktopConnectionMembership | null;
  credential: string;
  lastError: AiraDesktopConnectionErrorState;
};

export type AiraDesktopConnectionSnapshot = Omit<AiraDesktopConnectionRecord, 'credential'> & {
  hasCredential: boolean;
};

export type AiraDesktopAuthorizedSession = {
  uid: string;
  deviceId: string;
  deviceName: string;
  deviceCredential: string;
};

export type AiraDesktopConnectionIdentityExpectation = Pick<
  AiraDesktopAuthorizedSession,
  'uid' | 'deviceCredential'
>;

export type AiraDesktopPairingSession = {
  sessionId: string;
  pollToken: string;
  deviceCredential: string;
  deviceId: string;
  deviceName: string;
  qrPayload: string;
  expiresAt: number;
  pollIntervalMs: number;
};

export type AiraDesktopPairingStatus =
  | { status: 'pending' | 'expired'; expiresAt: number; pollIntervalMs: number }
  | {
    status: 'confirmed';
    account: AiraDesktopConnectionAccount;
    membership: AiraDesktopConnectionMembership;
    confirmedAt: number;
  };

export type AiraDesktopMembershipResponse = {
  account?: Partial<AiraDesktopConnectionAccount>;
  membership: AiraDesktopConnectionMembership;
};

export type AiraDesktopConnectionStorage = {
  read(): Promise<AiraDesktopConnectionRecord | null>;
  write(record: AiraDesktopConnectionRecord): Promise<void>;
  clear(): Promise<void>;
};

export type AiraDesktopConnectionRemote = {
  createPairing(device: { deviceId: string; deviceName: string }): Promise<AiraDesktopPairingSession>;
  pollPairing(session: AiraDesktopPairingSession): Promise<AiraDesktopPairingStatus>;
  refreshMembership(session: AiraDesktopAuthorizedSession): Promise<AiraDesktopMembershipResponse>;
  revoke(session: AiraDesktopAuthorizedSession): Promise<void>;
};

export class AiraDesktopConnectionRemoteError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, message: string, status = 0) {
    super(message);
    this.name = 'AiraDesktopConnectionRemoteError';
    this.code = code;
    this.status = status;
  }
}

export type AiraDesktopConnectionModuleParams = {
  storage: AiraDesktopConnectionStorage;
  remote: AiraDesktopConnectionRemote;
  device?: { deviceId: string; deviceName: string };
  now?: () => number;
};

const MEMBERSHIP_REFRESH_MIN_INTERVAL_MS = 5 * 60 * 1000;

const REAUTH_REQUIRED_CODES = new Set([
  'invalid_desktop_push_token',
  'desktop_session_expired',
  'desktop_device_session_revoked',
]);

export function isAiraDesktopCredentialRejection(error: unknown): boolean {
  if (!error || typeof error !== 'object') {
    return false;
  }
  return REAUTH_REQUIRED_CODES.has(String((error as { code?: unknown }).code || '').trim());
}

export class AiraDesktopConnectionModule {
  private readonly storage: AiraDesktopConnectionStorage;
  private readonly remote: AiraDesktopConnectionRemote;
  private readonly device: { deviceId: string; deviceName: string };
  private readonly now: () => number;

  constructor(params: AiraDesktopConnectionModuleParams) {
    this.storage = params.storage;
    this.remote = params.remote;
    this.device = params.device || { deviceId: '', deviceName: '' };
    this.now = params.now || Date.now;
  }

  async createPairing(): Promise<AiraDesktopPairingSession> {
    return this.remote.createPairing(this.device);
  }

  async pollPairing(session: AiraDesktopPairingSession): Promise<AiraDesktopPairingStatus> {
    const result = await this.remote.pollPairing(session);
    if (result.status !== 'confirmed') {
      return result;
    }
    const nextRecord: AiraDesktopConnectionRecord = {
      version: 1,
      status: 'connected',
      deviceId: session.deviceId || this.device.deviceId,
      deviceName: session.deviceName || this.device.deviceName,
      account: result.account,
      membership: result.membership,
      credential: session.deviceCredential,
      lastError: null,
    };
    await this.storage.write(nextRecord);
    return result;
  }

  async getSnapshot(): Promise<AiraDesktopConnectionSnapshot> {
    return toSnapshot(await this.storage.read());
  }

  async getAuthorizedSession(): Promise<AiraDesktopAuthorizedSession | null> {
    const record = await this.storage.read();
    if (!record?.credential || !record.account?.uid) {
      return null;
    }
    if (record.status === 'disconnected' || record.status === 'reauth-required') {
      return null;
    }
    return {
      uid: record.account.uid,
      deviceId: record.deviceId,
      deviceName: record.deviceName,
      deviceCredential: record.credential,
    };
  }

  async disconnectCurrentDevice(): Promise<AiraDesktopConnectionSnapshot> {
    const record = await this.storage.read();
    const session = toAuthorizedSession(record);
    if (session) {
      try {
        await this.remote.revoke(session);
      } catch (error) {
        if (!isAiraDesktopCredentialRejection(error)) {
          throw error;
        }
      }
    }
    await this.storage.clear();
    return toSnapshot(null);
  }

  async recordRemoteFailure(
    error: unknown,
    expectedIdentity?: AiraDesktopConnectionIdentityExpectation,
  ): Promise<AiraDesktopConnectionSnapshot> {
    const record = await this.storage.read();
    if (!record) {
      return toSnapshot(null);
    }
    if (!matchesExpectedIdentity(record, expectedIdentity)) {
      return toSnapshot(record);
    }
    const normalized = normalizeRemoteError(error, this.now());
    const reauthRequired = isAiraDesktopCredentialRejection(normalized);
    const nextRecord: AiraDesktopConnectionRecord = {
      ...record,
      status: reauthRequired ? 'reauth-required' : 'degraded',
      credential: reauthRequired ? '' : record.credential,
      lastError: normalized,
    };
    await this.storage.write(nextRecord);
    return toSnapshot(nextRecord);
  }

  async refreshMembership(options: { force?: boolean } = {}): Promise<AiraDesktopConnectionSnapshot> {
    const record = await this.storage.read();
    const session = toAuthorizedSession(record);
    if (!record || !session) {
      return toSnapshot(record);
    }
    if (!options.force && canUseCachedMembership(record, this.now())) {
      return toSnapshot(record);
    }
    try {
      const response = await this.remote.refreshMembership(session);
      const currentAccount = record.account as AiraDesktopConnectionAccount;
      const nextRecord: AiraDesktopConnectionRecord = {
        ...record,
        status: 'connected',
        account: {
          uid: response.account?.uid || currentAccount.uid,
          uidSuffix: response.account?.uidSuffix || currentAccount.uidSuffix,
          displayName: response.account?.displayName || currentAccount.displayName,
          avatarUri: response.account?.avatarUri || currentAccount.avatarUri,
        },
        membership: response.membership,
        lastError: null,
      };
      await this.storage.write(nextRecord);
      return toSnapshot(nextRecord);
    } catch (error) {
      return this.recordRemoteFailure(error, {
        uid: session.uid,
        deviceCredential: session.deviceCredential,
      });
    }
  }
}

function matchesExpectedIdentity(
  record: AiraDesktopConnectionRecord,
  expectedIdentity?: AiraDesktopConnectionIdentityExpectation,
): boolean {
  if (!expectedIdentity) {
    return true;
  }
  return record.account?.uid === expectedIdentity.uid
    && record.credential === expectedIdentity.deviceCredential;
}

function canUseCachedMembership(record: AiraDesktopConnectionRecord, now: number): boolean {
  if (record.status !== 'connected' || !record.membership) {
    return false;
  }
  const checkedAt = Date.parse(record.membership.checkedAt || '');
  if (!Number.isFinite(checkedAt) || now - checkedAt >= MEMBERSHIP_REFRESH_MIN_INTERVAL_MS) {
    return false;
  }
  const expiresAt = Number(record.membership.expiresAt || 0);
  return expiresAt === 0 || expiresAt > now;
}

function toAuthorizedSession(record: AiraDesktopConnectionRecord | null): AiraDesktopAuthorizedSession | null {
  if (!record?.credential || !record.account?.uid) {
    return null;
  }
  return {
    uid: record.account.uid,
    deviceId: record.deviceId,
    deviceName: record.deviceName,
    deviceCredential: record.credential,
  };
}

function toSnapshot(record: AiraDesktopConnectionRecord | null): AiraDesktopConnectionSnapshot {
  if (record) {
    const { credential, ...snapshot } = record;
    return {
      ...snapshot,
      hasCredential: credential.length > 0,
    };
  }
  return {
    version: 1,
    status: 'disconnected',
    deviceId: '',
    deviceName: '',
    account: null,
    membership: null,
    lastError: null,
    hasCredential: false,
  };
}

function normalizeRemoteError(error: unknown, now: number): NonNullable<AiraDesktopConnectionErrorState> {
  const semanticError = readSemanticRemoteError(error);
  if (semanticError) {
    return {
      code: semanticError.code,
      message: semanticError.message,
      occurredAt: new Date(now).toISOString(),
    };
  }
  return {
    code: 'temporary_failure',
    message: String((error as Error)?.message || error || 'Aira 桌面连接暂时不可用。'),
    occurredAt: new Date(now).toISOString(),
  };
}

function readSemanticRemoteError(error: unknown): { code: string; message: string } | null {
  if (!error || typeof error !== 'object') {
    return null;
  }
  const code = String((error as { code?: unknown }).code || '').trim();
  if (!code) {
    return null;
  }
  return {
    code,
    message: String((error as { message?: unknown }).message || 'Aira 桌面连接暂时不可用。'),
  };
}
