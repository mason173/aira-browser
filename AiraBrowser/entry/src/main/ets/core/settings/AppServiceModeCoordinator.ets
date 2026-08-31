import {
  BrowserAppServiceMode,
  BrowserDataBoundaryInput,
  BrowserExperimentSettings,
  SearchSuggestionPreferences
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { AdBlockRepository } from '../../data/adblock/AdBlockRepository';
import { WallpaperRepository } from '../../data/wallpaper/WallpaperRepository';
import { SyncExperienceCoordinator } from '../sync/SyncExperienceCoordinator';
import { AdBlockRuntimeGenerationCoordinator } from '../adblock/AdBlockRuntimeGenerationCoordinator';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export interface AppServiceModeApplyResult {
  mode: BrowserAppServiceMode;
  message: string;
}

export class AppServiceModeCoordinator {
  private preferencesRepository: PreferencesRepository;
  private syncExperienceCoordinator: SyncExperienceCoordinator;
  private wallpaperRepository: WallpaperRepository;
  private adBlockRepository: AdBlockRepository;
  private adBlockRuntimeGeneration: AdBlockRuntimeGenerationCoordinator;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    preferencesRepository: PreferencesRepository,
    syncExperienceCoordinator: SyncExperienceCoordinator,
    wallpaperRepository: WallpaperRepository,
    adBlockRepository: AdBlockRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.preferencesRepository = preferencesRepository;
    this.syncExperienceCoordinator = syncExperienceCoordinator;
    this.wallpaperRepository = wallpaperRepository;
    this.adBlockRepository = adBlockRepository;
    this.adBlockRuntimeGeneration = AdBlockRuntimeGenerationCoordinator.forRepository(adBlockRepository);
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  async applyMode(
    mode: BrowserAppServiceMode,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<AppServiceModeApplyResult> {
    this.ensureEffectAllowed(
      'settings_device_preference_write',
      'device_preferences',
      boundaryInput
    );
    if (mode === 'basic') {
      this.ensureEffectAllowed(
        'app_service_mode_sync_deactivation',
        'remote_account_sync_state',
        boundaryInput
      );
      await this.applyBasicMode();
      return {
        mode: 'basic',
        message: '已切换为基本模式，已关闭可选联网和增强功能。'
      };
    }

    await this.preferencesRepository.updateAppServiceMode('full');
    return {
      mode: 'full',
      message: '已切换为全量模式。'
    };
  }

  private ensureEffectAllowed(
    intent: 'settings_device_preference_write' | 'app_service_mode_sync_deactivation',
    targetScope: 'device_preferences' | 'remote_account_sync_state',
    boundaryInput: BrowserDataBoundaryInput
  ): void {
    const decision = this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: targetScope,
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      throw new Error(`App Service Mode privacy effect was not allowed: ${intent}`);
    }
  }

  private async applyBasicMode(): Promise<void> {
    await this.preferencesRepository.updateAppServiceMode('basic');
    await this.disableRemoteSearchSuggestions();
    await this.syncExperienceCoordinator.deactivateForAppServiceMode();
    await this.wallpaperRepository.updateSettings({ mode: 'theme' });
    await this.disableAdBlock();
    await this.disableExperiments();
  }

  private async disableRemoteSearchSuggestions(): Promise<void> {
    const current = this.preferencesRepository.getPreferences().searchSuggestions;
    const next: SearchSuggestionPreferences = {
      regularEnabled: current.regularEnabled,
      privateEnabled: current.privateEnabled,
      openTabsEnabled: current.openTabsEnabled,
      bookmarksEnabled: current.bookmarksEnabled,
      shortcutsEnabled: current.shortcutsEnabled,
      historyEnabled: current.historyEnabled,
      remoteEnabled: false
    };
    await this.preferencesRepository.updateSearchSuggestionPreferences(next);
  }

  private async disableAdBlock(): Promise<void> {
    await this.adBlockRepository.initializeMetadata();
    const settings = this.adBlockRepository.getSettings();
    await this.adBlockRuntimeGeneration.updatePreferences({
      enabled: false,
      updateOnForeground: settings.preferences.updateOnForeground
    });
  }

  private async disableExperiments(): Promise<void> {
    const current = this.preferencesRepository.getPreferences().experiments;
    const next: BrowserExperimentSettings = {
      pauseWebAnimationsDuringScroll: false,
      reduceMediaMotionDuringScroll: false,
      strengthenAdBlockingForSmoothScroll: false,
      pullRefreshEnabled: false,
      forceEnableWebZoom: false,
      smartGripTabsActionsEnabled: current.smartGripTabsActionsEnabled,
      webVideoTakeoverEnabled: false,
      novelModeEnabled: current.novelModeEnabled,
      novelAutoTakeoverEnabled: current.novelAutoTakeoverEnabled,
      appProxyActiveProfileId: current.appProxyActiveProfileId,
      appProxyProfiles: current.appProxyProfiles,
      appProxyEnabled: false,
      appProxy: current.appProxy
    };
    await this.preferencesRepository.updateExperimentSettings(next);
  }
}
