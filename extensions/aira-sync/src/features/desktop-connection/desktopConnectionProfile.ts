import type {
  AiraDesktopConnectionSnapshot,
  AiraDesktopConnectionStatus,
} from './AiraDesktopConnectionModule';
import {
  readAiraDesktopAuthorizedSession,
  readAiraDesktopConnectionSnapshot,
  refreshAiraDesktopConnectionMembershipWithinExecutionLock,
} from './desktopConnectionRuntime';
import { withBookmarkSyncExecutionLock } from '@/sync/leaftab/executionLock';

const MEMBERSHIP_REFRESH_MIN_INTERVAL_MS = 5 * 60 * 1000;

export type AiraDesktopConnectionProfile = {
  uid: string;
  uidSuffix: string;
  displayName: string;
  avatarUri: string;
  membershipPlan: string;
  membershipStatus: string;
  membershipExpiresAt: number;
  membershipCheckedAt: string;
  deviceCredential: string;
  deviceId: string;
  deviceName: string;
  connectionStatus: AiraDesktopConnectionStatus;
  lastErrorCode: string;
};

export type AiraDesktopProCapabilityStatus =
  | 'ready'
  | 'login-required'
  | 'pro-required'
  | 'temporarily-unavailable';

export async function readAiraDesktopConnectionProfile(): Promise<AiraDesktopConnectionProfile | null> {
  return withBookmarkSyncExecutionLock(() => {
    return readAiraDesktopConnectionProfileWithinExecutionLock();
  });
}

export async function readAiraDesktopConnectionProfileWithinExecutionLock(
): Promise<AiraDesktopConnectionProfile | null> {
  const [snapshot, session] = await Promise.all([
    readAiraDesktopConnectionSnapshot(),
    readAiraDesktopAuthorizedSession(),
  ]);
  return profileFromConnection(snapshot, session?.deviceCredential || '');
}

export function isAiraDesktopConnectionProfilePro(profile: AiraDesktopConnectionProfile | null): boolean {
  if (!profile?.deviceCredential || profile.connectionStatus === 'reauth-required') return false;
  if (profile.membershipPlan.trim().toLowerCase() !== 'pro') return false;
  const expiresAt = Number(profile.membershipExpiresAt || 0);
  return expiresAt === 0 || expiresAt > Date.now();
}

export function resolveAiraDesktopProCapability(
  profile: AiraDesktopConnectionProfile | null,
): AiraDesktopProCapabilityStatus {
  if (!profile?.uid || !profile.deviceCredential || profile.connectionStatus === 'reauth-required') {
    return 'login-required';
  }
  if (profile.connectionStatus === 'degraded') {
    return isAiraDesktopConnectionProfilePro(profile) ? 'ready' : 'temporarily-unavailable';
  }
  return isAiraDesktopConnectionProfilePro(profile) ? 'ready' : 'pro-required';
}

export async function refreshAiraDesktopConnectionProfileMembership(
  options: { force?: boolean } = {},
): Promise<AiraDesktopConnectionProfile | null> {
  return withBookmarkSyncExecutionLock(() => {
    return refreshAiraDesktopConnectionProfileMembershipWithinExecutionLock(options);
  });
}

export async function refreshAiraDesktopConnectionProfileMembershipWithinExecutionLock(
  options: { force?: boolean } = {},
): Promise<AiraDesktopConnectionProfile | null> {
  const snapshot = await refreshAiraDesktopConnectionMembershipWithinExecutionLock(options);
  const session = await readAiraDesktopAuthorizedSession();
  return profileFromConnection(snapshot, session?.deviceCredential || '');
}

export function shouldRefreshAiraDesktopConnectionMembership(
  profile: AiraDesktopConnectionProfile | null,
): boolean {
  if (!profile?.deviceCredential) return false;
  const expiresAt = Number(profile.membershipExpiresAt || 0);
  if (expiresAt > 0 && expiresAt <= Date.now()) return true;
  const checkedAt = Date.parse(profile.membershipCheckedAt || '');
  return !Number.isFinite(checkedAt) || Date.now() - checkedAt >= MEMBERSHIP_REFRESH_MIN_INTERVAL_MS;
}

function normalizeProfile(raw: Record<string, unknown>): AiraDesktopConnectionProfile {
  const uid = String(raw.uid || '').trim();
  const uidSuffix = String(raw.uidSuffix || '').trim() || uid.slice(-6);
  return {
    uid,
    uidSuffix,
    displayName: String(raw.displayName || '').trim() || (uidSuffix ? `Aira ${uidSuffix}` : 'Aira'),
    avatarUri: String(raw.avatarUri || '').trim(),
    membershipPlan: String(raw.membershipPlan || 'club').trim(),
    membershipStatus: String(raw.membershipStatus || 'missing_plan_default_club').trim(),
    membershipExpiresAt: Number(raw.membershipExpiresAt || 0),
    membershipCheckedAt: String(raw.membershipCheckedAt || '').trim(),
    deviceCredential: String(raw.deviceCredential || '').trim(),
    deviceId: String(raw.deviceId || '').trim(),
    deviceName: String(raw.deviceName || '').trim(),
    connectionStatus: normalizeConnectionStatus(raw.connectionStatus),
    lastErrorCode: String(raw.lastErrorCode || '').trim(),
  };
}

function profileFromConnection(
  snapshot: AiraDesktopConnectionSnapshot,
  deviceCredential: string,
): AiraDesktopConnectionProfile | null {
  if (!snapshot.account?.uid) return null;
  return normalizeProfile({
    ...snapshot.account,
    membershipPlan: snapshot.membership?.plan || 'club',
    membershipStatus: snapshot.membership?.status || 'missing_plan_default_club',
    membershipExpiresAt: snapshot.membership?.expiresAt || 0,
    membershipCheckedAt: snapshot.membership?.checkedAt || '',
    deviceCredential,
    deviceId: snapshot.deviceId,
    deviceName: snapshot.deviceName,
    connectionStatus: snapshot.status,
    lastErrorCode: snapshot.lastError?.code || '',
  });
}

function normalizeConnectionStatus(value: unknown): AiraDesktopConnectionStatus {
  const status = String(value || '').trim();
  if (status === 'disconnected' || status === 'degraded' || status === 'reauth-required') return status;
  return 'connected';
}
