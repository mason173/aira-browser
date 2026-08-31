import { AiraFeatureKey } from '../../common/constants/MembershipFeatureKeys';
import {
  AiraFeatureQuota,
  AiraMembershipState,
  AiraPlan,
  EntitlementDenyReason,
  EntitlementDecision,
  EntitlementPrimaryAction
} from '../../common/models/MembershipModels';
import {
  FeaturePolicy,
  MembershipPlanPolicyService
} from './MembershipPlanPolicyService';
import { MembershipQuotaService } from './MembershipQuotaService';

export interface EntitlementContext {
  dataScope: string;
  privacyMode: string;
  loggedIn?: boolean;
  currentUsage?: number;
}

export class EntitlementService {
  private policyService: MembershipPlanPolicyService;
  private quotaService: MembershipQuotaService;

  constructor(
    policyService: MembershipPlanPolicyService = new MembershipPlanPolicyService(),
    quotaService: MembershipQuotaService = new MembershipQuotaService()
  ) {
    this.policyService = policyService;
    this.quotaService = quotaService;
  }

  canUse(
    featureKey: AiraFeatureKey,
    state: AiraMembershipState,
    quotas: AiraFeatureQuota[],
    context: EntitlementContext
  ): EntitlementDecision {
    const policy = this.policyService.getPolicy(featureKey);
    if (policy === undefined) {
      return {
        featureKey: featureKey,
        allowed: true,
        reason: 'allowed',
        title: '',
        message: '',
        primaryAction: 'none'
      };
    }

    const entitlementPlan = this.policyService.resolveEntitlementPlan(state.plan);

    if (policy.requiresPro && entitlementPlan !== 'pro') {
      return this.buildDeniedDecision(
        featureKey,
        policy,
        'pro_required',
        '升级 Aira Pro 后可继续',
        `${policy.title} 是 Aira Pro 能力。`,
        'open_pro'
      );
    }

    if (policy.requiresClub && !this.policyService.hasClubEntitlement(state.plan)) {
      return this.buildDeniedDecision(
        featureKey,
        policy,
        'club_required',
        '当前版本暂不可用',
        `${policy.title} 当前无法使用。`,
        'none'
      );
    }

    if (policy.requiresLogin && !context.loggedIn) {
      return this.buildDeniedDecision(
        featureKey,
        policy,
        'login_required',
        '需要登录后使用',
        `${policy.title} 需要绑定华为账号后使用。`,
        'login'
      );
    }

    const limit = this.policyService.getLimit(policy, entitlementPlan);
    const currentQuota = this.quotaService.findQuota(quotas, featureKey);
    const currentUsage = this.resolveCurrentUsage(context, currentQuota.used);
    const quota: AiraFeatureQuota = {
      featureKey: featureKey,
      used: currentUsage,
      limit: limit,
      resetAt: currentQuota.resetAt
    };
    if (limit < 0) {
      return {
        featureKey: featureKey,
        allowed: true,
        reason: 'allowed',
        title: '',
        message: '',
        primaryAction: 'none',
        quota: quota
      };
    }
    if (limit <= 0) {
      return this.buildDeniedDecision(
        featureKey,
        policy,
        'pro_required',
        '升级 Aira Pro 后可继续',
        `${policy.title} 当前需要 Aira Pro。`,
        'open_pro',
        quota
      );
    }

    if (currentUsage >= limit) {
      return this.buildDeniedDecision(
        featureKey,
        policy,
        'quota_exceeded',
        '升级 Aira Pro 后可继续',
        `当前 ${this.resolvePlanLabel(entitlementPlan)} 的${policy.title}能力受限。`,
        'open_pro',
        quota
      );
    }

    return {
      featureKey: featureKey,
      allowed: true,
      reason: 'allowed',
      title: '',
      message: '',
      primaryAction: 'none',
      quota: quota
    };
  }

  private buildDeniedDecision(
    featureKey: AiraFeatureKey,
    policy: FeaturePolicy,
    reason: EntitlementDenyReason,
    title: string,
    message: string,
    primaryAction: EntitlementPrimaryAction,
    quota?: AiraFeatureQuota
  ): EntitlementDecision {
    return {
      featureKey: featureKey,
      allowed: false,
      reason: reason,
      title: title,
      message: message.length > 0 ? message : `${policy.title} 当前不可用。`,
      primaryAction: primaryAction,
      quota: quota
    };
  }

  private resolveCurrentUsage(context: EntitlementContext, fallback: number): number {
    if (typeof context.currentUsage !== 'number' || !Number.isFinite(context.currentUsage)) {
      return fallback;
    }
    return Math.max(0, Math.floor(context.currentUsage));
  }

  private resolvePlanLabel(plan: AiraPlan): string {
    return this.policyService.resolveEntitlementPlanLabel(plan);
  }
}
