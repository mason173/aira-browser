import { BrowserBrowsingIdentityPolicyCoordinator } from '../main/ets/core/browser/BrowserBrowsingIdentityPolicyCoordinator';
import { BrowserBrowsingIdentityDecisionService } from '../main/ets/services/web/BrowserBrowsingIdentityDecisionService';
import { describe, expect, it } from '@ohos/hypium';
import { DEFAULT_BROWSER_PROFILE_ID } from '../main/ets/common/models/BrowserModels';
import {
  InMemorySavedSiteSettingStorageAdapter,
  SavedSiteSettingRepository
} from '../main/ets/data/browser/SavedSiteSettingRepository';
import { SiteIdentityService } from '../main/ets/services/web/SiteIdentityService';
import {
  AIRA_DEFAULT_BROWSER_IDENTITY_ID,
  BrowserUserAgentService,
  CHROME_ANDROID_USER_AGENT,
  DEFAULT_BROWSER_USER_AGENT_SETTINGS,
  DESKTOP_CHROME_USER_AGENT_PRESET_ID
} from '../main/ets/services/web/BrowserUserAgentService';

export default function siteSettingTargetAndUserAgentTest(): void {
  describe('SiteSettingTargetAndUserAgent', () => {
    it('normalizes default ports and isolates scheme and non-default ports', 0, () => {
      const service = new SiteIdentityService();
      const httpDefault = service.resolveSiteSettingTarget('http://Example.COM:80/path');
      const httpImplicit = service.resolveSiteSettingTarget('http://example.com/other');
      const httpService = service.resolveSiteSettingTarget('http://example.com:8080');
      const httpsService = service.resolveSiteSettingTarget('https://example.com:8080');

      expect(httpDefault?.canonicalOrigin ?? '').assertEqual('http://example.com');
      expect(httpDefault?.effectivePort ?? 0).assertEqual(80);
      expect(httpImplicit?.canonicalOrigin ?? '').assertEqual('http://example.com');
      expect(httpService?.canonicalOrigin ?? '').assertEqual('http://example.com:8080');
      expect(httpsService?.canonicalOrigin ?? '').assertEqual('https://example.com:8080');
      expect(service.matchesSiteSettingTarget('http://example.com:80/a', httpDefault!)).assertTrue();
      expect(service.matchesSiteSettingTarget('http://example.com:8080/a', httpDefault!)).assertFalse();
      expect(service.matchesSiteSettingTarget('https://example.com/a', httpDefault!)).assertFalse();
    });

    it('supports IPv4, bracketed IPv6 and localhost while rejecting invalid schemes', 0, () => {
      const service = new SiteIdentityService();
      const ipv4 = service.resolveSiteSettingTarget('http://192.168.1.8:3000/dashboard');
      const ipv6 = service.resolveSiteSettingTarget('https://[2001:db8::1]:9443/a');
      const localhost = service.resolveSiteSettingTarget('http://localhost:5173');

      expect(ipv4?.canonicalOrigin ?? '').assertEqual('http://192.168.1.8:3000');
      expect(ipv6?.canonicalOrigin ?? '').assertEqual('https://[2001:db8::1]:9443');
      expect(ipv6?.displayHost ?? '').assertEqual('[2001:db8::1]');
      expect(localhost?.canonicalOrigin ?? '').assertEqual('http://localhost:5173');
      expect(service.resolveSiteSettingTarget('file:///data/index.html') === undefined).assertTrue();
      expect(service.resolveSiteSettingTarget('about:blank') === undefined).assertTrue();
    });

    it('commits with revision CAS and deletes the row when the final override returns to default', 0, async () => {
      const adapter = new InMemorySavedSiteSettingStorageAdapter();
      const repository = new SavedSiteSettingRepository(adapter);
      await repository.initialize();
      const target = new SiteIdentityService().resolveSiteSettingTarget('http://10.0.0.2:8080')!;

      const first = await repository.commit(target, DEFAULT_BROWSER_PROFILE_ID, {
        userAgentIdentityId: DESKTOP_CHROME_USER_AGENT_PRESET_ID
      }, 0);
      const stale = await repository.commit(target, DEFAULT_BROWSER_PROFILE_ID, {
        userAgentIdentityId: AIRA_DEFAULT_BROWSER_IDENTITY_ID
      }, 0);
      const reset = await repository.reset(target, DEFAULT_BROWSER_PROFILE_ID, first.entry?.revision ?? 0);

      expect(first.status).assertEqual('saved');
      expect(first.entry?.revision ?? 0).assertEqual(1);
      expect(stale.status).assertEqual('conflict');
      expect(reset.status).assertEqual('deleted');
      expect(repository.findEntry(target, DEFAULT_BROWSER_PROFILE_ID) === undefined).assertTrue();
    });

    it('resolves temporary, exact-Origin and explicit-global identities through the policy owner', 0, async () => {
      const identityService = new SiteIdentityService();
      const service = new BrowserUserAgentService();
      const target = identityService.resolveSiteSettingTarget('http://server.local:8080')!;
      const repository = new SavedSiteSettingRepository(new InMemorySavedSiteSettingStorageAdapter());
      await repository.initialize();
      await repository.commit(target, DEFAULT_BROWSER_PROFILE_ID, {
        userAgentIdentityId: DESKTOP_CHROME_USER_AGENT_PRESET_ID
      }, 0);
      let settings = DEFAULT_BROWSER_USER_AGENT_SETTINGS;
      const coordinator = new BrowserBrowsingIdentityPolicyCoordinator(
        { getSettings: () => settings }, repository, service,
        new BrowserBrowsingIdentityDecisionService(), {
          resolveApplicationFamily: () => 'mobile',
          resolveMandatoryCompatibility: () => undefined
        }
      );
      const resolve = (url: string) => coordinator.resolve({
        tabId: 'tab', currentUrl: url, profileId: DEFAULT_BROWSER_PROFILE_ID,
        privateBrowsing: false, systemDefaultUserAgent: 'ArkWeb/System'
      });
      const exact = resolve('http://server.local:8080/login');
      const otherPort = resolve('http://server.local:9090/login');
      coordinator.setCurrentTabIdentity('tab', AIRA_DEFAULT_BROWSER_IDENTITY_ID);
      const temporary = resolve('http://server.local:8080/login');
      coordinator.releaseTab('tab');
      settings = service.buildPresetSettings('mobile_chrome_android', DEFAULT_BROWSER_USER_AGENT_SETTINGS);
      const explicitGlobal = resolve('https://compat.example/');

      expect(exact.source).assertEqual('site_setting');
      expect(exact.identityId ?? '').assertEqual(DESKTOP_CHROME_USER_AGENT_PRESET_ID);
      expect(otherPort.source).assertEqual('app_default');
      expect(temporary.identityId ?? '').assertEqual(AIRA_DEFAULT_BROWSER_IDENTITY_ID);
      expect(explicitGlobal.userAgent).assertEqual(CHROME_ANDROID_USER_AGENT);
      expect(explicitGlobal.source).assertEqual('preset');
    });
  });
}
