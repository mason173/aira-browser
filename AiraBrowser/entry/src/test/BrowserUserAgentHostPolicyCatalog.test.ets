import { describe, expect, it } from '@ohos/hypium';
import { BrowserUserAgentHostPolicyCatalog } from
  '../main/ets/services/web/BrowserUserAgentHostPolicyCatalog';

export default function browserUserAgentHostPolicyCatalogTest(): void {
  describe('BrowserUserAgentHostPolicyCatalog', () => {
    it('covers Google Search country domains with exact mobile and desktop Hosts', 0, () => {
      const catalog = new BrowserUserAgentHostPolicyCatalog();

      const hongKongMobile = catalog.resolveMandatoryCompatibility(
        'mobile',
        'google.com.hk'
      );
      const unitedKingdomDesktop = catalog.resolveMandatoryCompatibility(
        'desktop',
        'www.google.co.uk'
      );

      expect(hongKongMobile?.profileId).assertEqual('aira_android_compat');
      expect(unitedKingdomDesktop?.profileId).assertEqual('aira_desktop_compat');
      expect(catalog.resolveMandatoryCompatibility(
        'desktop',
        'httpbingo.org'
      )).assertUndefined();
    });

    it('does not broaden Google Search policy to lookalike Hosts', 0, () => {
      const catalog = new BrowserUserAgentHostPolicyCatalog();

      expect(catalog.resolveMandatoryCompatibility(
        'mobile',
        'www.google.com.evil'
      )).assertUndefined();
      expect(catalog.resolveMandatoryCompatibility(
        'mobile',
        'accounts.google.com'
      )).assertUndefined();
    });
  });
}
