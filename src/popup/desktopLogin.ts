import { readExtensionStorageRecord, removeExtensionStorageKeys, writeExtensionStorageRecord } from '@/platform/extensionStorage';

const AIRA_API_BASE_URL = 'https://api.aira.cool';
const AIRA_DESKTOP_LOGIN_PROFILE_KEY = 'aira_desktop_login_profile_v1';
const AIRA_DESKTOP_MEMBERSHIP_REFRESH_MIN_INTERVAL_MS = 5 * 60 * 1000;

export type AiraDesktopLoginProfile = {
  uid: string;
  uidSuffix: string;
  displayName: string;
  avatarUri: string;
  membershipPlan: string;
  membershipStatus: string;
  membershipExpiresAt: number;
  membershipCheckedAt: string;
  loggedInAt: string;
  desktopPushToken: string;
};

export type AiraDesktopLoginSession = {
  sessionId: string;
  pollToken: string;
  desktopPushToken: string;
  qrPayload: string;
  expiresAt: number;
  pollIntervalMs: number;
};

export type AiraDesktopLoginStatus =
  | {
    status: 'pending' | 'expired';
    expiresAt: number;
    pollIntervalMs: number;
  }
  | {
    status: 'confirmed';
    account: AiraDesktopLoginProfile;
    confirmedAt: number;
  };

type CreateSessionResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  sessionId?: string;
  pollToken?: string;
  desktopPushToken?: string;
  qrPayload?: string;
  expiresAt?: number;
  pollIntervalMs?: number;
};

type StatusResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  status?: string;
  account?: Partial<AiraDesktopLoginProfile>;
  expiresAt?: number;
  pollIntervalMs?: number;
  confirmedAt?: number;
};

type DesktopMembershipStateResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  uid?: string;
  uidSuffix?: string;
  membershipPlan?: string;
  membershipStatus?: string;
  membershipGrant?: {
    currentPlan?: string;
    plan?: string;
    status?: string;
    expiresAt?: number;
  };
};

export async function createAiraDesktopLoginSession(): Promise<AiraDesktopLoginSession> {
  const response = await postJson<CreateSessionResponse>('/desktop-login/create', {});
  if (!response.ok) {
    throw new Error(response.message || 'Unable to create login QR code.');
  }
  const sessionId = String(response.sessionId || '').trim();
  const pollToken = String(response.pollToken || '').trim();
  const desktopPushToken = String(response.desktopPushToken || '').trim();
  const qrPayload = String(response.qrPayload || '').trim();
  const expiresAt = Number(response.expiresAt || 0);
  if (!sessionId || !pollToken || !desktopPushToken || !qrPayload || !Number.isFinite(expiresAt) || expiresAt <= 0) {
    throw new Error('Login service returned an invalid QR session.');
  }
  return {
    sessionId,
    pollToken,
    desktopPushToken,
    qrPayload,
    expiresAt,
    pollIntervalMs: normalizePollInterval(response.pollIntervalMs),
  };
}

export async function pollAiraDesktopLoginStatus(session: AiraDesktopLoginSession): Promise<AiraDesktopLoginStatus> {
  const response = await postJson<StatusResponse>('/desktop-login/status', {
    sessionId: session.sessionId,
    pollToken: session.pollToken,
  });
  if (!response.ok) {
    throw new Error(response.message || 'Unable to check login status.');
  }
  if (response.status === 'confirmed' && response.account) {
    return {
      status: 'confirmed',
      account: normalizeProfile(response.account),
      confirmedAt: Number(response.confirmedAt || Date.now()),
    };
  }
  if (response.status === 'expired') {
    return {
      status: 'expired',
      expiresAt: Number(response.expiresAt || session.expiresAt),
      pollIntervalMs: normalizePollInterval(response.pollIntervalMs),
    };
  }
  return {
    status: 'pending',
    expiresAt: Number(response.expiresAt || session.expiresAt),
    pollIntervalMs: normalizePollInterval(response.pollIntervalMs),
  };
}

export function readAiraDesktopLoginProfile(): AiraDesktopLoginProfile | null {
  try {
    if (typeof localStorage === 'undefined') return null;
    const raw = localStorage.getItem(AIRA_DESKTOP_LOGIN_PROFILE_KEY);
    if (!raw) return null;
    return normalizeProfile(JSON.parse(raw) as Partial<AiraDesktopLoginProfile>);
  } catch {
    return null;
  }
}

export function writeAiraDesktopLoginProfile(profile: AiraDesktopLoginProfile): void {
  try {
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem(AIRA_DESKTOP_LOGIN_PROFILE_KEY, JSON.stringify(profile));
    }
  } catch {
    // Extension service workers do not expose localStorage.
  }
  void writeExtensionStorageRecord({
    [AIRA_DESKTOP_LOGIN_PROFILE_KEY]: JSON.stringify(profile),
  });
}

export function clearAiraDesktopLoginProfile(): void {
  try {
    if (typeof localStorage !== 'undefined') {
      localStorage.removeItem(AIRA_DESKTOP_LOGIN_PROFILE_KEY);
    }
  } catch {
    // Extension service workers do not expose localStorage.
  }
  void removeExtensionStorageKeys([AIRA_DESKTOP_LOGIN_PROFILE_KEY]);
}

export async function readAiraDesktopLoginProfileFromExtensionStorage(): Promise<AiraDesktopLoginProfile | null> {
  try {
    const result = await readExtensionStorageRecord([AIRA_DESKTOP_LOGIN_PROFILE_KEY]);
    const raw = String(result[AIRA_DESKTOP_LOGIN_PROFILE_KEY] || '').trim();
    if (!raw) return null;
    return normalizeProfile(JSON.parse(raw) as Partial<AiraDesktopLoginProfile>);
  } catch {
    return null;
  }
}

export async function syncAiraDesktopLoginProfileToExtensionStorage(): Promise<void> {
  const profile = readAiraDesktopLoginProfile();
  if (!profile) {
    await removeExtensionStorageKeys([AIRA_DESKTOP_LOGIN_PROFILE_KEY]);
    return;
  }
  await writeExtensionStorageRecord({
    [AIRA_DESKTOP_LOGIN_PROFILE_KEY]: JSON.stringify(profile),
  });
}

export function isAiraDesktopProfilePro(profile: AiraDesktopLoginProfile | null): boolean {
  if (String(profile?.membershipPlan || '').trim().toLowerCase() !== 'pro') {
    return false;
  }
  const expiresAt = Number(profile?.membershipExpiresAt || 0);
  return expiresAt === 0 || expiresAt > Date.now();
}

export async function refreshAiraDesktopMembershipProfile(
  profile: AiraDesktopLoginProfile | null = readAiraDesktopLoginProfile(),
  options: { force?: boolean } = {},
): Promise<AiraDesktopLoginProfile | null> {
  if (!profile?.uid || !profile.desktopPushToken) {
    return profile;
  }
  if (!options.force && !shouldRefreshAiraDesktopMembershipProfile(profile)) {
    return profile;
  }
  const response = await postJson<DesktopMembershipStateResponse>('/desktop-login/membership-state', {
    desktopPushToken: profile.desktopPushToken,
    source: 'airatab_desktop_membership_refresh',
  });
  if (!response.ok) {
    throw new Error(response.message || 'Unable to refresh Aira membership.');
  }
  const membershipGrant = response.membershipGrant || {};
  const nextProfile = normalizeProfile({
    ...profile,
    uid: String(response.uid || profile.uid || '').trim(),
    uidSuffix: String(response.uidSuffix || profile.uidSuffix || '').trim(),
    membershipPlan: String(response.membershipPlan || membershipGrant.currentPlan || membershipGrant.plan || '').trim(),
    membershipStatus: String(response.membershipStatus || membershipGrant.status || '').trim(),
    membershipExpiresAt: Number(membershipGrant.expiresAt || 0),
    membershipCheckedAt: new Date().toISOString(),
  });
  writeAiraDesktopLoginProfile(nextProfile);
  return nextProfile;
}

export function shouldRefreshAiraDesktopMembershipProfile(profile: AiraDesktopLoginProfile | null): boolean {
  if (!profile?.desktopPushToken) {
    return false;
  }
  const expiresAt = Number(profile.membershipExpiresAt || 0);
  if (expiresAt > 0 && expiresAt <= Date.now()) {
    return true;
  }
  const checkedAt = Date.parse(profile.membershipCheckedAt || '');
  if (!Number.isFinite(checkedAt)) {
    return true;
  }
  return Date.now() - checkedAt >= AIRA_DESKTOP_MEMBERSHIP_REFRESH_MIN_INTERVAL_MS;
}

function normalizeProfile(raw: Partial<AiraDesktopLoginProfile>): AiraDesktopLoginProfile {
  const uid = String(raw.uid || '').trim();
  const uidSuffix = String(raw.uidSuffix || '').trim() || uid.slice(-6);
  const membershipPlan = String(raw.membershipPlan || '').trim() || 'club';
  return {
    uid,
    uidSuffix,
    displayName: String(raw.displayName || '').trim() || (uidSuffix ? `Aira ${uidSuffix}` : 'Aira'),
    avatarUri: String(raw.avatarUri || '').trim(),
    membershipPlan,
    membershipStatus: String(raw.membershipStatus || '').trim() || 'missing_plan_default_club',
    membershipExpiresAt: Number(raw.membershipExpiresAt || 0),
    membershipCheckedAt: String(raw.membershipCheckedAt || '').trim(),
    loggedInAt: String(raw.loggedInAt || '').trim() || new Date().toISOString(),
    desktopPushToken: String(raw.desktopPushToken || '').trim(),
  };
}

function normalizePollInterval(value: unknown): number {
  const interval = Number(value || 1800);
  if (!Number.isFinite(interval)) return 1800;
  return Math.min(5000, Math.max(1000, Math.floor(interval)));
}

async function postJson<T>(path: string, body: unknown): Promise<T> {
  const response = await fetch(`${AIRA_API_BASE_URL}${path}`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  const parsed = text ? JSON.parse(text) as T : {} as T;
  if (!response.ok) {
    const error = parsed as { message?: string };
    throw new Error(error.message || `Aira API request failed (${response.status}).`);
  }
  return parsed;
}
