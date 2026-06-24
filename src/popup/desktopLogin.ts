const AIRA_API_BASE_URL = 'https://api.aira.cool';
const AIRA_DESKTOP_LOGIN_PROFILE_KEY = 'aira_desktop_login_profile_v1';

export type AiraDesktopLoginProfile = {
  uid: string;
  uidSuffix: string;
  displayName: string;
  avatarUri: string;
  membershipPlan: string;
  membershipStatus: string;
  loggedInAt: string;
};

export type AiraDesktopLoginSession = {
  sessionId: string;
  pollToken: string;
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

export async function createAiraDesktopLoginSession(): Promise<AiraDesktopLoginSession> {
  const response = await postJson<CreateSessionResponse>('/desktop-login/create', {});
  if (!response.ok) {
    throw new Error(response.message || 'Unable to create login QR code.');
  }
  const sessionId = String(response.sessionId || '').trim();
  const pollToken = String(response.pollToken || '').trim();
  const qrPayload = String(response.qrPayload || '').trim();
  const expiresAt = Number(response.expiresAt || 0);
  if (!sessionId || !pollToken || !qrPayload || !Number.isFinite(expiresAt) || expiresAt <= 0) {
    throw new Error('Login service returned an invalid QR session.');
  }
  return {
    sessionId,
    pollToken,
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
    const raw = localStorage.getItem(AIRA_DESKTOP_LOGIN_PROFILE_KEY);
    if (!raw) return null;
    return normalizeProfile(JSON.parse(raw) as Partial<AiraDesktopLoginProfile>);
  } catch {
    return null;
  }
}

export function writeAiraDesktopLoginProfile(profile: AiraDesktopLoginProfile): void {
  localStorage.setItem(AIRA_DESKTOP_LOGIN_PROFILE_KEY, JSON.stringify(profile));
}

export function clearAiraDesktopLoginProfile(): void {
  localStorage.removeItem(AIRA_DESKTOP_LOGIN_PROFILE_KEY);
}

function normalizeProfile(raw: Partial<AiraDesktopLoginProfile>): AiraDesktopLoginProfile {
  const uid = String(raw.uid || '').trim();
  const uidSuffix = String(raw.uidSuffix || '').trim() || uid.slice(-6);
  return {
    uid,
    uidSuffix,
    displayName: String(raw.displayName || '').trim() || (uidSuffix ? `Aira ${uidSuffix}` : 'Aira'),
    avatarUri: String(raw.avatarUri || '').trim(),
    membershipPlan: String(raw.membershipPlan || '').trim() || 'club',
    membershipStatus: String(raw.membershipStatus || '').trim() || 'missing_plan_default_club',
    loggedInAt: String(raw.loggedInAt || '').trim() || new Date().toISOString(),
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
