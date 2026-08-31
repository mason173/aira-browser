import { AiraPlan } from '../../common/models/MembershipModels';
import { AiraFeatureKey } from '../../common/constants/MembershipFeatureKeys';

export interface FeaturePolicy {
  featureKey: AiraFeatureKey;
  guestLimit: number;
  clubLimit: number;
  proLimit: number;
  requiresLogin: boolean;
  requiresClub: boolean;
  requiresPro: boolean;
  title: string;
}

export class MembershipPlanPolicyService {
  private policies: FeaturePolicy[] = [
    {
      featureKey: 'offline_page_save',
      guestLimit: -1,
      clubLimit: -1,
      proLimit: -1,
      requiresLogin: false,
      requiresClub: false,
      requiresPro: false,
      title: '离线页面'
    },
    {
      featureKey: 'userscript_install',
      guestLimit: -1,
      clubLimit: -1,
      proLimit: -1,
      requiresLogin: false,
      requiresClub: false,
      requiresPro: false,
      title: '用户脚本'
    },
    {
      featureKey: 'manual_element_hide',
      guestLimit: -1,
      clubLimit: -1,
      proLimit: -1,
      requiresLogin: false,
      requiresClub: false,
      requiresPro: false,
      title: '手动隐藏规则'
    },
    {
      featureKey: 'cloud_translation',
      guestLimit: -1,
      clubLimit: -1,
      proLimit: -1,
      requiresLogin: false,
      requiresClub: false,
      requiresPro: false,
      title: 'Aira 系统翻译'
    },
    {
      featureKey: 'cloud_sync',
      guestLimit: 0,
      clubLimit: 0,
      proLimit: -1,
      requiresLogin: true,
      requiresClub: false,
      requiresPro: true,
      title: '跨系统同步书签'
    },
    {
      featureKey: 'webdav_sync',
      guestLimit: -1,
      clubLimit: -1,
      proLimit: -1,
      requiresLogin: false,
      requiresClub: false,
      requiresPro: false,
      title: 'WebDAV 同步'
    },
    {
      featureKey: 'bookmark_auto_sync',
      guestLimit: -1,
      clubLimit: -1,
      proLimit: -1,
      requiresLogin: false,
      requiresClub: false,
      requiresPro: false,
      title: '书签自动同步'
    },
    {
      featureKey: 'phone_page_push',
      guestLimit: 0,
      clubLimit: 0,
      proLimit: -1,
      requiresLogin: true,
      requiresClub: false,
      requiresPro: true,
      title: '网页推送到电脑'
    },
    {
      featureKey: 'cross_device_tabs',
      guestLimit: 0,
      clubLimit: 0,
      proLimit: -1,
      requiresLogin: true,
      requiresClub: false,
      requiresPro: true,
      title: '跨设备标签页'
    },
    {
      featureKey: 'labs_feature',
      guestLimit: -1,
      clubLimit: -1,
      proLimit: -1,
      requiresLogin: false,
      requiresClub: false,
      requiresPro: false,
      title: '实验室功能'
    }
  ];

  getPolicy(featureKey: AiraFeatureKey): FeaturePolicy | undefined {
    return this.policies.find((policy: FeaturePolicy) => policy.featureKey === featureKey);
  }

  getLimit(policy: FeaturePolicy, plan: AiraPlan): number {
    const effectivePlan = this.resolveEntitlementPlan(plan);
    if (effectivePlan === 'pro') {
      return policy.proLimit;
    }
    if (effectivePlan === 'club') {
      return policy.clubLimit;
    }
    return policy.guestLimit;
  }

  resolveEntitlementPlan(plan: AiraPlan): AiraPlan {
    if (plan === 'pro') {
      return 'pro';
    }
    return 'club';
  }

  hasClubEntitlement(plan: AiraPlan): boolean {
    const entitlementPlan = this.resolveEntitlementPlan(plan);
    return entitlementPlan === 'club' || entitlementPlan === 'pro';
  }

  hasProEntitlement(plan: AiraPlan): boolean {
    return this.resolveEntitlementPlan(plan) === 'pro';
  }

  resolveEntitlementPlanLabel(plan: AiraPlan): string {
    if (this.hasProEntitlement(plan)) {
      return 'Aira Pro';
    }
    return 'Aira Club';
  }

  listPolicies(): FeaturePolicy[] {
    return this.policies.map((policy: FeaturePolicy) => {
      const result: FeaturePolicy = {
        featureKey: policy.featureKey,
        guestLimit: policy.guestLimit,
        clubLimit: policy.clubLimit,
        proLimit: policy.proLimit,
        requiresLogin: policy.requiresLogin,
        requiresClub: policy.requiresClub,
        requiresPro: policy.requiresPro,
        title: policy.title
      };
      return result;
    });
  }
}
