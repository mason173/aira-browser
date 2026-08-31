import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserProfileId,
  BrowserUserAgentSettings,
  DEFAULT_BROWSER_PROFILE_ID
} from '../main/ets/common/models/BrowserModels';
import {
  BrowserBrowsingIdentityHostPolicyAdapter,
  BrowserBrowsingIdentityPolicyCoordinator
} from '../main/ets/core/browser/BrowserBrowsingIdentityPolicyCoordinator';
import { BrowserUserAgentSettingsReader } from
  '../main/ets/data/browser/BrowserUserAgentSettingsRepository';
import {
  InMemorySavedSiteSettingStorageAdapter,
  SavedSiteSettingRepository
} from '../main/ets/data/browser/SavedSiteSettingRepository';
import { BrowserBrowsingIdentityDecisionService } from
  '../main/ets/services/web/BrowserBrowsingIdentityDecisionService';
import {
  BrowserUserAgentApplicationFamily,
  BrowserUserAgentMandatoryCompatibility,
  BrowserUserAgentService,
  AIRA_COMPAT_DESKTOP_USER_AGENT,
  AIRA_COMPAT_MOBILE_USER_AGENT,
  CHROME_ANDROID_USER_AGENT,
  DEFAULT_BROWSER_USER_AGENT_SETTINGS,
  DESKTOP_CHROME_USER_AGENT_PRESET_ID
} from '../main/ets/services/web/BrowserUserAgentService';

class InMemoryBrowsingIdentitySettingsReader implements BrowserUserAgentSettingsReader {
  private settings: BrowserUserAgentSettings;

  constructor(settings: BrowserUserAgentSettings) {
    this.settings = settings;
  }

  getSettings(): BrowserUserAgentSettings {
    return this.settings;
  }

  setSettings(settings: BrowserUserAgentSettings): void {
    this.settings = settings;
  }
}

class FixedBrowsingIdentityHostPolicyAdapter implements BrowserBrowsingIdentityHostPolicyAdapter {
  private readonly applicationFamily: BrowserUserAgentApplicationFamily;
  private readonly mandatoryCompatibility?: BrowserUserAgentMandatoryCompatibility;

  constructor(
    applicationFamily: BrowserUserAgentApplicationFamily,
    mandatoryCompatibility?: BrowserUserAgentMandatoryCompatibility
  ) {
    this.applicationFamily = applicationFamily;
    this.mandatoryCompatibility = mandatoryCompatibility;
  }

  resolveApplicationFamily(): BrowserUserAgentApplicationFamily {
    return this.applicationFamily;
  }

  resolveMandatoryCompatibility(
    _host: string,
    _requestedApplicationFamily?: BrowserUserAgentApplicationFamily
  ): BrowserUserAgentMandatoryCompatibility | undefined {
    return this.mandatoryCompatibility;
  }
}

interface BrowsingIdentityPolicyFixture {
  coordinator: BrowserBrowsingIdentityPolicyCoordinator;
  settingsReader: InMemoryBrowsingIdentitySettingsReader;
  siteRepository: SavedSiteSettingRepository;
  userAgentService: BrowserUserAgentService;
}

async function createPolicyFixture(
  settings: BrowserUserAgentSettings,
  applicationFamily: BrowserUserAgentApplicationFamily,
  mandatoryCompatibility?: BrowserUserAgentMandatoryCompatibility
): Promise<BrowsingIdentityPolicyFixture> {
  const siteRepository = new SavedSiteSettingRepository(new InMemorySavedSiteSettingStorageAdapter());
  await siteRepository.initialize();
  const userAgentService = new BrowserUserAgentService();
  const settingsReader = new InMemoryBrowsingIdentitySettingsReader(settings);
  return {
    coordinator: new BrowserBrowsingIdentityPolicyCoordinator(
      settingsReader,
      siteRepository,
      userAgentService,
      new BrowserBrowsingIdentityDecisionService(),
      new FixedBrowsingIdentityHostPolicyAdapter(applicationFamily, mandatoryCompatibility)
    ),
    settingsReader: settingsReader,
    siteRepository: siteRepository,
    userAgentService: userAgentService
  };
}

function resolvePolicy(
  coordinator: BrowserBrowsingIdentityPolicyCoordinator,
  url: string,
  privateBrowsing: boolean = false,
  profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
  tabId: string = 'tab-policy'
) {
  return coordinator.resolve({
    tabId: tabId,
    currentUrl: url,
    profileId: profileId,
    privateBrowsing: privateBrowsing,
    systemDefaultUserAgent: 'ArkWeb/System'
  });
}

export default function browserBrowsingIdentityPolicyCoordinatorTest(): void {
  describe('BrowserBrowsingIdentityPolicyCoordinator', () => {
    it('mandatory Host policy wins over current-tab, exact-Origin, and global choices', 0, async () => {
      const userAgentService = new BrowserUserAgentService();
      const globalSettings = userAgentService.buildPresetSettings(
        DESKTOP_CHROME_USER_AGENT_PRESET_ID,
        DEFAULT_BROWSER_USER_AGENT_SETTINGS
      );
      const fixture = await createPolicyFixture(globalSettings, 'mobile', {
        host: 'example.com',
        ruleId: 'fixture-rule',
        identityId: 'host_profile:fixture',
        reason: 'Fixture mandatory Host policy.',
        userAgent: 'FixtureMandatory/1.0',
        mode: 'desktop'
      });
      const target = fixture.userAgentService.resolveSiteSettingTarget('https://example.com/article')!;
      await fixture.siteRepository.commit(target, DEFAULT_BROWSER_PROFILE_ID, {
        userAgentIdentityId: DESKTOP_CHROME_USER_AGENT_PRESET_ID
      }, 0);
      fixture.coordinator.setCurrentTabIdentity('tab-policy', 'mobile_safari_iphone');

      const decision = resolvePolicy(fixture.coordinator, 'https://example.com/article');

      expect(decision.winningSource).assertEqual('mandatory_host');
      expect(decision.userAgent).assertEqual('FixtureMandatory/1.0');
    });

    it('current-tab choice wins over exact-Origin and global choices', 0, async () => {
      const userAgentService = new BrowserUserAgentService();
      const fixture = await createPolicyFixture(
        userAgentService.buildPresetSettings(
          DESKTOP_CHROME_USER_AGENT_PRESET_ID,
          DEFAULT_BROWSER_USER_AGENT_SETTINGS
        ),
        'mobile'
      );
      const target = fixture.userAgentService.resolveSiteSettingTarget('https://example.com/article')!;
      await fixture.siteRepository.commit(target, DEFAULT_BROWSER_PROFILE_ID, {
        userAgentIdentityId: DESKTOP_CHROME_USER_AGENT_PRESET_ID
      }, 0);
      fixture.coordinator.setCurrentTabIdentity('tab-policy', 'mobile_chrome_android');

      const decision = resolvePolicy(fixture.coordinator, 'https://example.com/article');

      expect(decision.winningSource).assertEqual('current_tab');
      expect(decision.identityId ?? '').assertEqual('mobile_chrome_android');
    });

    it('current-tab choice stays tab-local and is released with the tab lifetime', 0, async () => {
      const fixture = await createPolicyFixture(DEFAULT_BROWSER_USER_AGENT_SETTINGS, 'mobile');
      fixture.coordinator.setCurrentTabIdentity('tab-temporary', DESKTOP_CHROME_USER_AGENT_PRESET_ID);

      const selected = resolvePolicy(
        fixture.coordinator,
        'https://example.com/article',
        false,
        DEFAULT_BROWSER_PROFILE_ID,
        'tab-temporary'
      );
      const unrelatedTab = resolvePolicy(
        fixture.coordinator,
        'https://example.com/article',
        false,
        DEFAULT_BROWSER_PROFILE_ID,
        'tab-unrelated'
      );
      fixture.coordinator.releaseTab('tab-temporary');
      const released = resolvePolicy(
        fixture.coordinator,
        'https://example.com/article',
        false,
        DEFAULT_BROWSER_PROFILE_ID,
        'tab-temporary'
      );

      expect(selected.winningSource).assertEqual('current_tab');
      expect(selected.profile.presentationMode).assertEqual('desktop-request');
      expect(unrelatedTab.winningSource).assertEqual('applicable_default');
      expect(unrelatedTab.profile.presentationMode).assertEqual('mobile');
      expect(released.winningSource).assertEqual('applicable_default');
      expect(released.profile.presentationMode).assertEqual('mobile');
    });

    it('exact-Origin choice wins over the explicit global choice', 0, async () => {
      const userAgentService = new BrowserUserAgentService();
      const fixture = await createPolicyFixture(
        userAgentService.buildPresetSettings('mobile_chrome_android', DEFAULT_BROWSER_USER_AGENT_SETTINGS),
        'mobile'
      );
      const target = fixture.userAgentService.resolveSiteSettingTarget('https://example.com/article')!;
      await fixture.siteRepository.commit(target, DEFAULT_BROWSER_PROFILE_ID, {
        userAgentIdentityId: DESKTOP_CHROME_USER_AGENT_PRESET_ID
      }, 0);

      const decision = resolvePolicy(fixture.coordinator, 'https://example.com/article');

      expect(decision.winningSource).assertEqual('exact_origin');
      expect(decision.identityId ?? '').assertEqual(DESKTOP_CHROME_USER_AGENT_PRESET_ID);
    });

    it('private browsing ignores a regular exact-Origin choice', 0, async () => {
      const userAgentService = new BrowserUserAgentService();
      const fixture = await createPolicyFixture(
        userAgentService.buildPresetSettings('mobile_chrome_android', DEFAULT_BROWSER_USER_AGENT_SETTINGS),
        'mobile'
      );
      const target = fixture.userAgentService.resolveSiteSettingTarget('https://example.com/article')!;
      await fixture.siteRepository.commit(target, DEFAULT_BROWSER_PROFILE_ID, {
        userAgentIdentityId: DESKTOP_CHROME_USER_AGENT_PRESET_ID
      }, 0);

      const decision = resolvePolicy(fixture.coordinator, 'https://example.com/article', true);

      expect(decision.winningSource).assertEqual('global');
      expect(decision.userAgent).assertEqual(CHROME_ANDROID_USER_AGENT);
    });

    it('physical phone, tablet, and desktop select their stable default identities', 0, async () => {
      const phone = await createPolicyFixture(DEFAULT_BROWSER_USER_AGENT_SETTINGS, 'mobile');
      const tablet = await createPolicyFixture(DEFAULT_BROWSER_USER_AGENT_SETTINGS, 'tablet');
      const desktop = await createPolicyFixture(DEFAULT_BROWSER_USER_AGENT_SETTINGS, 'desktop');

      const phoneDecision = resolvePolicy(phone.coordinator, 'https://example.com/');
      const tabletDecision = resolvePolicy(tablet.coordinator, 'https://example.com/');
      const desktopDecision = resolvePolicy(desktop.coordinator, 'https://example.com/');

      expect(phoneDecision.winningSource).assertEqual('applicable_default');
      expect(phoneDecision.userAgent).assertEqual(AIRA_COMPAT_MOBILE_USER_AGENT);
      expect(tabletDecision.userAgent).assertEqual(AIRA_COMPAT_DESKTOP_USER_AGENT);
      expect(desktopDecision.userAgent).assertEqual(AIRA_COMPAT_DESKTOP_USER_AGENT);
    });

    it('decision carries selected evidence, snapshot identity, and execution fingerprint', 0, async () => {
      const userAgentService = new BrowserUserAgentService();
      const fixture = await createPolicyFixture(
        userAgentService.buildPresetSettings('mobile_chrome_android', DEFAULT_BROWSER_USER_AGENT_SETTINGS),
        'mobile'
      );

      const decision = resolvePolicy(fixture.coordinator, 'https://example.com/');
      const selectedGlobal = decision.explanation.find((item): boolean => {
        return item.source === 'global' && item.status === 'selected';
      });

      expect(decision.policySnapshotKey.length > 0).assertTrue();
      expect(decision.executionFingerprint.length > 0).assertTrue();
      expect(decision.explanation.length).assertEqual(6);
      expect(selectedGlobal !== undefined).assertTrue();
    });

    it('an existing decision remains immutable after later global settings change', 0, async () => {
      const userAgentService = new BrowserUserAgentService();
      const mobileSettings = userAgentService.buildPresetSettings(
        'mobile_chrome_android',
        DEFAULT_BROWSER_USER_AGENT_SETTINGS
      );
      mobileSettings.updatedAt = 100;
      const fixture = await createPolicyFixture(mobileSettings, 'mobile');
      const firstDecision = resolvePolicy(fixture.coordinator, 'https://example.com/');
      const firstFingerprint = firstDecision.executionFingerprint;
      const desktopSettings = userAgentService.buildPresetSettings(
        DESKTOP_CHROME_USER_AGENT_PRESET_ID,
        mobileSettings
      );
      desktopSettings.updatedAt = 101;

      fixture.settingsReader.setSettings(desktopSettings);
      const nextDecision = resolvePolicy(fixture.coordinator, 'https://example.com/');

      expect(firstDecision.userAgent).assertEqual(CHROME_ANDROID_USER_AGENT);
      expect(firstDecision.executionFingerprint).assertEqual(firstFingerprint);
      expect(nextDecision.userAgent).assertEqual(AIRA_COMPAT_DESKTOP_USER_AGENT);
      expect(nextDecision.executionFingerprint === firstFingerprint).assertFalse();
    });
  });
}
