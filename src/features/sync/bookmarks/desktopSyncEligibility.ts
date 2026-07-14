import {
  isAiraDesktopConnectionProfilePro,
  type AiraDesktopConnectionProfile,
} from '@/features/desktop-connection/desktopConnectionProfile';

export type AiraDesktopSyncStatus = 'login-required' | 'pro-required' | 'disabled' | 'ready';

export const resolveAiraDesktopSyncStatus = (
  profile: Pick<AiraDesktopConnectionProfile, 'uid' | 'deviceCredential' | 'membershipPlan' | 'membershipExpiresAt'> | null,
  syncEnabled: boolean,
): AiraDesktopSyncStatus => {
  if (!profile?.uid || !profile.deviceCredential) {
    return 'login-required';
  }
  if (!isAiraDesktopConnectionProfilePro(profile as AiraDesktopConnectionProfile)) {
    return 'pro-required';
  }
  return syncEnabled ? 'ready' : 'disabled';
};
