import { BrowserProfileId, DEFAULT_BROWSER_PROFILE_ID } from '../../common/models/BrowserModels';
import {
  BrowserWebRuntimeSecurityPolicy,
  DEFAULT_BROWSER_WEB_SECURITY_SETTINGS
} from '../../common/models/BrowserWebSecurityModels';
import {
  SavedSiteSettingRepository,
  sharedSavedSiteSettingRepository
} from '../../data/browser/SavedSiteSettingRepository';
import {
  BrowserWebSecuritySettingsRepository,
  sharedBrowserWebSecuritySettingsRepository
} from '../../data/preferences/BrowserWebSecuritySettingsRepository';
import { SiteIdentityService } from './SiteIdentityService';

export class BrowserWebRuntimeSecurityPolicyService {
  private readonly savedSiteSettingRepository: SavedSiteSettingRepository;
  private readonly settingsRepository: BrowserWebSecuritySettingsRepository;
  private readonly siteIdentityService: SiteIdentityService = new SiteIdentityService();

  constructor(
    settingsRepository: BrowserWebSecuritySettingsRepository,
    savedSiteSettingRepository: SavedSiteSettingRepository
  ) {
    this.settingsRepository = settingsRepository;
    this.savedSiteSettingRepository = savedSiteSettingRepository;
  }

  resolve(
    url: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): BrowserWebRuntimeSecurityPolicy {
    const settings = this.settingsRepository.getSettings() ?? DEFAULT_BROWSER_WEB_SECURITY_SETTINGS;
    const target = this.siteIdentityService.resolveSiteSettingTarget(url);
    const entry = target === undefined
      ? undefined
      : this.savedSiteSettingRepository.findEntry(target, profileId);
    const siteJavaScriptEnabled = entry?.overrides.javaScriptEnabled;
    return {
      httpsFirstEnabled: settings.httpsFirstEnabled,
      safeBrowsingEnabled: settings.safeBrowsingEnabled,
      javaScriptEnabled: typeof siteJavaScriptEnabled === 'boolean'
        ? siteJavaScriptEnabled
        : settings.javaScriptEnabled,
      javaScriptUsesSiteOverride: typeof siteJavaScriptEnabled === 'boolean'
    };
  }
}

export const sharedBrowserWebRuntimeSecurityPolicyService: BrowserWebRuntimeSecurityPolicyService =
  new BrowserWebRuntimeSecurityPolicyService(
    sharedBrowserWebSecuritySettingsRepository,
    sharedSavedSiteSettingRepository
  );
