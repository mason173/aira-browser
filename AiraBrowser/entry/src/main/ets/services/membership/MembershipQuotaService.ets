import { AiraFeatureKey } from '../../common/constants/MembershipFeatureKeys';
import { AiraFeatureQuota } from '../../common/models/MembershipModels';

export class MembershipQuotaService {
  findQuota(quotas: AiraFeatureQuota[], featureKey: AiraFeatureKey, now: number = Date.now()): AiraFeatureQuota {
    const existing = quotas.find((quota: AiraFeatureQuota) => quota.featureKey === featureKey);
    if (existing !== undefined) {
      return this.resolveActiveQuota(existing, now);
    }
    return {
      featureKey: featureKey,
      used: 0,
      limit: 0,
      resetAt: this.resolveNextMonthlyResetAt(now)
    };
  }

  recordUsage(
    quotas: AiraFeatureQuota[],
    featureKey: AiraFeatureKey,
    amount: number = 1,
    now: number = Date.now()
  ): AiraFeatureQuota[] {
    const normalizedAmount = Math.max(0, Math.floor(amount));
    const nextQuotas = quotas.map((quota: AiraFeatureQuota) => this.cloneQuota(quota));
    const index = nextQuotas.findIndex((quota: AiraFeatureQuota) => quota.featureKey === featureKey);
    if (index < 0) {
      nextQuotas.push({
        featureKey: featureKey,
        used: normalizedAmount,
        limit: 0,
        resetAt: this.resolveNextMonthlyResetAt(now)
      });
      return nextQuotas;
    }
    const current = this.resolveActiveQuota(nextQuotas[index], now);
    nextQuotas[index] = {
      featureKey: current.featureKey,
      used: current.used + normalizedAmount,
      limit: current.limit,
      resetAt: current.resetAt
    };
    return nextQuotas;
  }

  private resolveActiveQuota(quota: AiraFeatureQuota, now: number): AiraFeatureQuota {
    const resetAt = quota.resetAt > 0 ? quota.resetAt : this.resolveNextMonthlyResetAt(now);
    if (resetAt <= now) {
      return {
        featureKey: quota.featureKey,
        used: 0,
        limit: quota.limit,
        resetAt: this.resolveNextMonthlyResetAt(now)
      };
    }
    return {
      featureKey: quota.featureKey,
      used: quota.used,
      limit: quota.limit,
      resetAt: resetAt
    };
  }

  private resolveNextMonthlyResetAt(now: number): number {
    const current = new Date(now);
    return new Date(current.getFullYear(), current.getMonth() + 1, 1, 0, 0, 0, 0).getTime();
  }

  private cloneQuota(quota: AiraFeatureQuota): AiraFeatureQuota {
    return {
      featureKey: quota.featureKey,
      used: quota.used,
      limit: quota.limit,
      resetAt: quota.resetAt
    };
  }
}
