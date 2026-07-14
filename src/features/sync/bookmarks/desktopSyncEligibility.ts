import {
  isAiraDesktopProfilePro,
  type AiraDesktopLoginProfile,
} from '@/popup/desktopLogin';

export type AiraDesktopSyncStatus = 'login-required' | 'pro-required' | 'disabled' | 'ready';

export const resolveAiraDesktopSyncStatus = (
  profile: Pick<AiraDesktopLoginProfile, 'uid' | 'desktopPushToken' | 'membershipPlan' | 'membershipExpiresAt'> | null,
  syncEnabled: boolean,
): AiraDesktopSyncStatus => {
  if (!profile?.uid || !profile.desktopPushToken) {
    return 'login-required';
  }
  if (!isAiraDesktopProfilePro(profile as AiraDesktopLoginProfile)) {
    return 'pro-required';
  }
  return syncEnabled ? 'ready' : 'disabled';
};
