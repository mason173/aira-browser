import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { BrowserWebSecuritySettings } from '../../common/models/BrowserWebSecurityModels';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import { SiteCustomizationRefreshSignal } from '../sitecustomization/SiteCustomizationRefreshSignal';
import { SavedSiteSettingEntry } from '../../common/models/SiteSettingModels';
import {
  SavedSiteSettingRepository,
  sharedSavedSiteSettingRepository
} from '../../data/browser/SavedSiteSettingRepository';
import {
  BrowserWebSecuritySettingsRepository,
  sharedBrowserWebSecuritySettingsRepository
} from '../../data/preferences/BrowserWebSecuritySettingsRepository';
export type BrowserWebSecuritySettingId = 'https_first' | 'safe_browsing' | 'javascript';

export interface BrowserWebSecuritySettingsState extends BrowserWebSecuritySettings {
  javaScriptSiteExceptionCount: number;
  canEditSettings: boolean;
}

export class BrowserWebSecuritySettingsCoordinator {
  private readonly settingsRepository: BrowserWebSecuritySettingsRepository;
  private readonly savedSiteSettingRepository: SavedSiteSettingRepository;
  private readonly refreshSignal: SiteCustomizationRefreshSignal;
  private readonly profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  constructor(
    settingsRepository: BrowserWebSecuritySettingsRepository,
    savedSiteSettingRepository: SavedSiteSettingRepository,
    refreshSignal: SiteCustomizationRefreshSignal = new SiteCustomizationRefreshSignal()
  ) {
    this.settingsRepository = settingsRepository;
    this.savedSiteSettingRepository = savedSiteSettingRepository;
    this.refreshSignal = refreshSignal;
  }

  buildState(boundary: BrowserDataBoundaryInput = {}): BrowserWebSecuritySettingsState {
    const settings = this.settingsRepository.getSettings();
    return {
      httpsFirstEnabled: settings.httpsFirstEnabled,
      safeBrowsingEnabled: settings.safeBrowsingEnabled,
      javaScriptEnabled: settings.javaScriptEnabled,
      javaScriptSiteExceptionCount: this.savedSiteSettingRepository.listEntries()
        .filter((entry: SavedSiteSettingEntry): boolean =>
          typeof entry.overrides.javaScriptEnabled === 'boolean').length,
      canEditSettings: !this.profileBoundaryService.isSessionEphemeral(boundary)
    };
  }

  async setSetting(
    settingId: BrowserWebSecuritySettingId,
    enabled: boolean,
    boundary: BrowserDataBoundaryInput
  ): Promise<BrowserWebSecuritySettingsState> {
    if (this.profileBoundaryService.isSessionEphemeral(boundary)) {
      return this.buildState(boundary);
    }
    const current = this.settingsRepository.getSettings();
    await this.settingsRepository.updateSettings({
      httpsFirstEnabled: settingId === 'https_first' ? enabled : current.httpsFirstEnabled,
      safeBrowsingEnabled: settingId === 'safe_browsing' ? enabled : current.safeBrowsingEnabled,
      javaScriptEnabled: settingId === 'javascript' ? enabled : current.javaScriptEnabled
    });
    this.refreshSignal.bump(settingId === 'javascript' ? 'javascript' : 'web_security');
    return this.buildState(boundary);
  }
}

export const sharedBrowserWebSecuritySettingsCoordinator: BrowserWebSecuritySettingsCoordinator =
  new BrowserWebSecuritySettingsCoordinator(
    sharedBrowserWebSecuritySettingsRepository,
    sharedSavedSiteSettingRepository
  );
