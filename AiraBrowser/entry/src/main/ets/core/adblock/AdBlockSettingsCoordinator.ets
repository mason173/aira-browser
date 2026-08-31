import {
  AdBlockPreferences,
  AdBlockSettings,
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { AdBlockRepository, DEFAULT_AD_BLOCK_STATS } from '../../data/adblock/AdBlockRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import { AdBlockRuntimeGenerationCoordinator } from './AdBlockRuntimeGenerationCoordinator';

export class AdBlockSettingsBoundary {
  dataScope: BrowserDataScope | string;
  privacyMode: BrowserSessionPrivacyMode | string;

  constructor(dataScope: BrowserDataScope | string = '', privacyMode: BrowserSessionPrivacyMode | string = '') {
    this.dataScope = dataScope;
    this.privacyMode = privacyMode;
  }
}

export interface AdBlockSettingsMutationResult {
  allowed: boolean;
  settings: AdBlockSettings;
}

export class AdBlockSettingsCoordinator {
  private repository: AdBlockRepository;
  private runtimeGeneration: AdBlockRuntimeGenerationCoordinator;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    repository: AdBlockRepository,
    runtimeGeneration: AdBlockRuntimeGenerationCoordinator,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.repository = repository;
    this.runtimeGeneration = runtimeGeneration;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  updatePreferences(
    preferences: AdBlockPreferences,
    boundary: AdBlockSettingsBoundary
  ): Promise<AdBlockSettingsMutationResult> {
    return this.commit(boundary, (): Promise<AdBlockSettings> =>
      this.runtimeGeneration.updatePreferences(preferences));
  }

  getSettingsForBoundary(boundary: AdBlockSettingsBoundary): AdBlockSettings {
    return this.projectSettingsForBoundary(this.repository.getSettings(), boundary);
  }

  projectSettingsForBoundary(settings: AdBlockSettings, boundary: AdBlockSettingsBoundary): AdBlockSettings {
    const statsPolicy = this.privacyEffectPolicy.resolveDataPolicy('adblock_stats', {
      dataScope: boundary.dataScope,
      privacyMode: boundary.privacyMode
    });
    if (statsPolicy.persistentReadAllowed) {
      return settings;
    }
    return {
      preferences: settings.preferences,
      siteExceptions: settings.siteExceptions,
      customRuleSources: settings.customRuleSources,
      stats: DEFAULT_AD_BLOCK_STATS,
      lastRuleUpdateAt: settings.lastRuleUpdateAt,
      engineUnavailableReason: settings.engineUnavailableReason,
      updatedAt: settings.updatedAt
    };
  }

  removeSiteException(
    host: string,
    boundary: AdBlockSettingsBoundary,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<AdBlockSettingsMutationResult> {
    return this.commit(boundary, (): Promise<AdBlockSettings> =>
      this.runtimeGeneration.removeSiteException(host, profileId));
  }

  clearStats(boundary: AdBlockSettingsBoundary): Promise<AdBlockSettingsMutationResult> {
    if (!this.canWriteStats(boundary)) {
      const denied: AdBlockSettingsMutationResult = {
        allowed: false,
        settings: this.getSettingsForBoundary(boundary)
      };
      return Promise.resolve(denied);
    }
    return this.commit(boundary, (): Promise<AdBlockSettings> => this.repository.clearStats());
  }

  private async commit(
    boundary: AdBlockSettingsBoundary,
    mutation: () => Promise<AdBlockSettings>
  ): Promise<AdBlockSettingsMutationResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return {
        allowed: false,
        settings: this.repository.getSettings()
      };
    }
    return {
      allowed: true,
      settings: await mutation()
    };
  }

  private canWriteDevicePreference(boundary: AdBlockSettingsBoundary): boolean {
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    const dataScope = normalizeBrowserDataScope(boundary.dataScope, privacyMode);
    return this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: dataScope,
        privacyMode: privacyMode
      }),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private canWriteStats(boundary: AdBlockSettingsBoundary): boolean {
    return this.privacyEffectPolicy.resolveDataPolicy('adblock_stats', {
      dataScope: boundary.dataScope,
      privacyMode: boundary.privacyMode
    }).persistentWriteAllowed;
  }
}
