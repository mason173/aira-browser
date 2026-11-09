export const AIRA_PRO_MONTHLY_PRODUCT_ID: string = 'aira_pro_monthly';
export const AIRA_PRO_YEARLY_PRODUCT_ID: string = 'aira_pro_yearly';
export const AIRA_PRO_ONE_TIME_PRODUCT_ID: string = 'aira_pro_lifetime';
const AIRA_PRO_LEGACY_ONE_TIME_PRODUCT_ID: string = 'aira_pro_one_time';
const AIRA_PRO_ONE_TIME_DISPLAY_PRICE: string = '¥68.8';
const AIRA_PRO_ONE_TIME_ORIGINAL_PRICE_TEXT: string = '原价¥98.8';

export type HuaweiIapProductPeriod = 'monthly' | 'yearly';
export const AIRA_SUITE_LIFETIME_PLAN_ID: string = 'suite_lifetime';
export const AIRA_SUITE_LIFETIME_PRODUCT_ID: string = 'aira_suite_lifetime';
export type HuaweiIapPlanId = HuaweiIapProductPeriod | 'one_time' | 'suite_lifetime';

export interface HuaweiIapProductPlan {
  productId: string;
  featurePlan: 'pro';
  period: HuaweiIapProductPeriod;
  title: string;
  displayPrice: string;
  /**
   * Price split for the membership page's price cards: the card renders the
   * amount large and the cadence small beside it. `displayPrice` stays the
   * single-line form for callers that render one string (the renewal sheet).
   */
  amountText: string;
  periodText: string;
  /** Period-end discount badge. Empty when the plan carries no discount. */
  discountBadgeText: string;
  description: string;
  badgeText: string;
}

export interface HuaweiIapOneTimePlan {
  productId: string;
  planId: 'one_time';
  featurePlan: 'pro';
  title: string;
  displayPrice: string;
  amountText: string;
  periodText: string;
  /**
   * Struck-through list price for the membership card's top-right capsule.
   * Empty hides the capsule.
   */
  originalPriceText: string;
  description: string;
  badgeText: string;
}

export const AIRA_PRO_MONTHLY_PLAN: HuaweiIapProductPlan = {
  productId: AIRA_PRO_MONTHLY_PRODUCT_ID,
  featurePlan: 'pro',
  period: 'monthly',
  title: '连续包月',
  displayPrice: '¥1 / 月自动续费',
  amountText: '¥1',
  periodText: '/ 月',
  discountBadgeText: '',
  description: '按月自动续费，可在订阅管理中取消',
  badgeText: ''
};

export const AIRA_PRO_YEARLY_PLAN: HuaweiIapProductPlan = {
  productId: AIRA_PRO_YEARLY_PRODUCT_ID,
  featurePlan: 'pro',
  period: 'yearly',
  title: '连续包年',
  displayPrice: '¥7.89 / 年自动续费',
  amountText: '¥7.89',
  periodText: '/ 年',
  // 包月 ¥1 首月特惠 vs 包年 ¥7.89：按当前价对比约省 34%。
  discountBadgeText: '−34%',
  description: '按年自动续费，可在订阅管理中取消',
  badgeText: '推荐'
};

export const AIRA_PRO_ONE_TIME_PLAN: HuaweiIapOneTimePlan = {
  productId: AIRA_PRO_ONE_TIME_PRODUCT_ID,
  planId: 'one_time',
  featurePlan: 'pro',
  title: '长期会员',
  displayPrice: `${AIRA_PRO_ONE_TIME_DISPLAY_PRICE} 长期`,
  amountText: AIRA_PRO_ONE_TIME_DISPLAY_PRICE,
  periodText: '长期',
  originalPriceText: AIRA_PRO_ONE_TIME_ORIGINAL_PRICE_TEXT,
  description: '一次购买，长期有效，不自动续费',
  badgeText: ''
};

export const AIRA_PRO_SELLABLE_IAP_PLANS: HuaweiIapProductPlan[] = [
  AIRA_PRO_MONTHLY_PLAN,
  AIRA_PRO_YEARLY_PLAN
];

export const AIRA_PRO_IAP_PLANS: HuaweiIapProductPlan[] = [
  AIRA_PRO_MONTHLY_PLAN,
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

/** The lease period as it reads under a price: `/ 月`, `/ 年`. */
export function resolveAiraProPlanPeriodText(period: HuaweiIapProductPeriod): string {
  if (period === 'yearly') {
    return '/ 年';
  }
  return '/ 月';
}

export function isAiraProIapPlanId(planId: string): boolean {
  const normalizedPlanId = planId.trim().toLowerCase();
  return normalizedPlanId === AIRA_SUITE_LIFETIME_PLAN_ID || normalizedPlanId === AIRA_PRO_ONE_TIME_PLAN.planId || findAiraProIapPlan(normalizedPlanId) !== undefined;
}

export function isAiraProSellablePlanId(planId: string): boolean {
  const normalizedPlanId = planId.trim().toLowerCase();
  return AIRA_PRO_SELLABLE_IAP_PLANS.some((item: HuaweiIapProductPlan) => item.period === normalizedPlanId);
}

export function resolveAiraProProductId(planId: string): string {
  const normalizedPlanId = planId.trim().toLowerCase();
  if (normalizedPlanId === AIRA_SUITE_LIFETIME_PLAN_ID) { return AIRA_SUITE_LIFETIME_PRODUCT_ID; }
  if (normalizedPlanId === AIRA_PRO_ONE_TIME_PLAN.planId) {
    return AIRA_PRO_ONE_TIME_PRODUCT_ID;
  }
  return resolveAiraProIapPlan(normalizedPlanId).productId;
}

/** Current store id is `aira_pro_lifetime`; older builds sold `aira_pro_one_time`. */
export function isAiraProLifetimeProductId(productId: string): boolean {
  const normalizedProductId = productId.trim();
  return normalizedProductId === AIRA_PRO_ONE_TIME_PRODUCT_ID ||
    normalizedProductId === AIRA_PRO_LEGACY_ONE_TIME_PRODUCT_ID;
}
