import { describe, expect, it } from '@ohos/hypium';
import {
  AIRA_PRO_SELLABLE_IAP_PLANS,
  isAiraProSellablePlanId
} from '../main/ets/services/membership/HuaweiIapProductCatalog';

export default function huaweiIapProductCatalogTest(): void {
  describe('Aira Pro storefront catalog', () => {
    it('sells only monthly and yearly subscriptions on the Aira Pro page', 0, () => {
      expect(AIRA_PRO_SELLABLE_IAP_PLANS.length).assertEqual(2);
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[0].period).assertEqual('monthly');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[0].title).assertEqual('连续包月');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[0].displayPrice).assertEqual('¥1 / 月自动续费');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[1].period).assertEqual('yearly');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[1].title).assertEqual('连续包年');
      expect(AIRA_PRO_SELLABLE_IAP_PLANS[1].displayPrice).assertEqual('¥7.89 / 年自动续费');
      expect(isAiraProSellablePlanId('monthly')).assertTrue();
      expect(isAiraProSellablePlanId('yearly')).assertTrue();
      expect(isAiraProSellablePlanId('quarterly')).assertFalse();
      expect(isAiraProSellablePlanId('one_time')).assertFalse();
    });
  });
}
