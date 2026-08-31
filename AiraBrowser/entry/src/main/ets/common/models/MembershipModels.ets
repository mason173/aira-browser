export type AiraPlan = 'guest' | 'club' | 'pro';
export type AiraMembershipBadgeKind = 'none' | 'club' | 'pro' | 'long_term';
export type AiraAccountRecognition = 'none' | 'aira_insider';
export type AiraAccountRecognitionBadgeKind = 'none' | 'insider';

export type AiraAccessFlag = 'club' | 'founder';

export type AiraSubscriptionStatus =
  'none' |
  'active' |
  'grace_period' |
  'expired' |
  'cancelled' |
  'unknown';

export type EntitlementDenyReason =
  'allowed' |
  'login_required' |
  'club_required' |
  'pro_required' |
  'quota_exceeded' |
  'offline_unknown' |
  'unsupported_context';

export type EntitlementPrimaryAction =
  'none' |
  'open_pro' |
  'login' |
  'manage_usage' |
  'restore_purchase';

export interface AiraMembershipState {
  userId: string;
  plan: AiraPlan;
  accountRecognition: AiraAccountRecognition;
  accessFlags: AiraAccessFlag[];
  subscriptionStatus: AiraSubscriptionStatus;
  subscriptionProductId: string;
  planExpiresAt: number;
  accountFirstSeenAt: number;
  accountLastSeenAt: number;
  lastSyncedAt: number;
  updatedAt: number;
}

export interface AiraFeatureQuota {
  featureKey: string;
  used: number;
  limit: number;
  resetAt: number;
}

export interface EntitlementDecision {
  featureKey: string;
  allowed: boolean;
  reason: EntitlementDenyReason;
  title: string;
  message: string;
  primaryAction: EntitlementPrimaryAction;
  quota?: AiraFeatureQuota;
}

export interface AiraMembershipEntitlementClaims {
  v: number;
  kid: string;
  iss: string;
  sub: string;
  plan: AiraPlan;
  source: string;
  productId: string;
  subscriptionStatus: AiraSubscriptionStatus;
  accountRecognition: AiraAccountRecognition;
  grantExpiresAt: number;
  issuedAt: number;
  offlineUntil: number;
}

export interface AiraMembershipEntitlementProofRecord {
  uid: string;
  proof: string;
}

export interface MembershipRepositorySnapshot {
  state: AiraMembershipState;
  quotas: AiraFeatureQuota[];
}

export function buildDefaultMembershipState(now: number = Date.now()): AiraMembershipState {
  return {
    userId: 'local',
    plan: 'guest',
    accountRecognition: 'none',
    accessFlags: [],
    subscriptionStatus: 'none',
    subscriptionProductId: '',
    planExpiresAt: 0,
    accountFirstSeenAt: 0,
    accountLastSeenAt: 0,
    lastSyncedAt: 0,
    updatedAt: now
  };
}
