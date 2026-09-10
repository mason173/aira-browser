export const AIRA_PRO_MONTHLY_PRODUCT_ID: string = 'aira_pro_monthly';
export const AIRA_PRO_QUARTERLY_PRODUCT_ID: string = 'aira_pro_quarterly';
export const AIRA_PRO_YEARLY_PRODUCT_ID: string = 'aira_pro_yearly';
export const AIRA_PRO_ONE_TIME_PRODUCT_ID: string = 'aira_pro_one_time';
const AIRA_PRO_ONE_TIME_DISPLAY_PRICE: string = '¥38.8';

export type HuaweiIapProductPeriod = 'monthly' | 'quarterly' | 'yearly';
export type HuaweiIapPlanId = HuaweiIapProductPeriod | 'one_time';

export interface HuaweiIapProductPlan {
  productId: string;
  featurePlan: 'pro';
  period: HuaweiIapProductPeriod;
  title: string;
  displayPrice: string;
  description: string;
  badgeText: string;
}

export interface HuaweiIapOneTimePlan {
  productId: string;
  planId: 'one_time';
  featurePlan: 'pro';
  title: string;
  displayPrice: string;
  description: string;
  badgeText: string;
}

export const AIRA_PRO_MONTHLY_PLAN: HuaweiIapProductPlan = {
  productId: AIRA_PRO_MONTHLY_PRODUCT_ID,
  featurePlan: 'pro',
  period: 'monthly',
  title: '连续包月',
  displayPrice: '¥1 / 月自动续费',
  description: '按月自动续费，可在订阅管理中取消',
  badgeText: ''
};

export const AIRA_PRO_QUARTERLY_PLAN: HuaweiIapProductPlan = {
  productId: AIRA_PRO_QUARTERLY_PRODUCT_ID,
  featurePlan: 'pro',
  period: 'quarterly',
  title: '连续包季',
  displayPrice: '¥8 / 季自动续费',
  description: '按季自动续费，可在订阅管理中取消',
  badgeText: ''
};

export const AIRA_PRO_YEARLY_PLAN: HuaweiIapProductPlan = {
  productId: AIRA_PRO_YEARLY_PRODUCT_ID,
  featurePlan: 'pro',
  period: 'yearly',
  title: '连续包年',
  displayPrice: '¥7.89 / 年自动续费',
  description: '按年自动续费，可在订阅管理中取消',
  badgeText: '推荐'
};

export const AIRA_PRO_ONE_TIME_PLAN: HuaweiIapOneTimePlan = {
  productId: AIRA_PRO_ONE_TIME_PRODUCT_ID,
  planId: 'one_time',
  featurePlan: 'pro',
  title: '长期会员',
  displayPrice: AIRA_PRO_ONE_TIME_DISPLAY_PRICE,
  description: `早鸟价 ${AIRA_PRO_ONE_TIME_DISPLAY_PRICE} · 长期有效 · 不自动续费`,
  badgeText: '推荐'
};

export const AIRA_PRO_SELLABLE_IAP_PLANS: HuaweiIapProductPlan[] = [
  AIRA_PRO_MONTHLY_PLAN,
  AIRA_PRO_YEARLY_PLAN
];

export const AIRA_PRO_IAP_PLANS: HuaweiIapProductPlan[] = [
  AIRA_PRO_MONTHLY_PLAN,
  AIRA_PRO_QUARTERLY_PLAN,
  AIRA_PRO_YEARLY_PLAN
];

export function resolveAiraProIapPlan(period: string): HuaweiIapProductPlan {
  const plan = findAiraProIapPlan(period);
  return plan ?? AIRA_PRO_MONTHLY_PLAN;
}

export function findAiraProIapPlan(period: string): HuaweiIapProductPlan | undefined {
  const normalizedPeriod = period.trim().toLowerCase();
  return AIRA_PRO_IAP_PLANS.find((item: HuaweiIapProductPlan) => item.period === normalizedPeriod);
}

export function findAiraProIapPlanByProductId(productId: string): HuaweiIapProductPlan | undefined {
  const normalizedProductId = productId.trim();
  return AIRA_PRO_IAP_PLANS.find((item: HuaweiIapProductPlan) => item.productId === normalizedProductId);
}

export function isAiraProIapPlanId(planId: string): boolean {
  const normalizedPlanId = planId.trim().toLowerCase();
  return normalizedPlanId === AIRA_PRO_ONE_TIME_PLAN.planId || findAiraProIapPlan(normalizedPlanId) !== undefined;
}

export function isAiraProSellablePlanId(planId: string): boolean {
  const normalizedPlanId = planId.trim().toLowerCase();
  return AIRA_PRO_SELLABLE_IAP_PLANS.some((item: HuaweiIapProductPlan) => item.period === normalizedPlanId);
}

export function resolveAiraProProductId(planId: string): string {
  const normalizedPlanId = planId.trim().toLowerCase();
  if (normalizedPlanId === AIRA_PRO_ONE_TIME_PLAN.planId) {
    return AIRA_PRO_ONE_TIME_PRODUCT_ID;
  }
  return resolveAiraProIapPlan(normalizedPlanId).productId;
}
