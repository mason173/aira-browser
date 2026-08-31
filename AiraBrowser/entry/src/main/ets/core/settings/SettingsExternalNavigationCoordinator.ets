import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  ExternalNavigationAppOpenPolicy,
  ExternalNavigationSettings,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export interface SettingsExternalNavigationBoundary {
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
}

export interface SettingsExternalNavigationResult {
  settings: ExternalNavigationSettings;
  message: string;
}

export class SettingsExternalNavigationCoordinator {
  private preferencesRepository: PreferencesRepository;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    preferencesRepository: PreferencesRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.preferencesRepository = preferencesRepository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  async setAppOpenPolicy(
    policy: ExternalNavigationAppOpenPolicy,
    boundary: SettingsExternalNavigationBoundary
  ): Promise<SettingsExternalNavigationResult> {
    const normalizedBoundary = this.normalizeBoundary(boundary);
    const decision = this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary(normalizedBoundary),
      targetScope: 'device_preferences',
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      return {
        settings: this.preferencesRepository.getPreferences().externalNavigation,
        message: '当前会话不可更改全局外部应用策略。'
      };
    }
    const currentSettings = this.preferencesRepository.getPreferences().externalNavigation;
    const nextSettings: ExternalNavigationSettings = {
      appOpenPolicy: policy,
      suppressAfterCancelMs: currentSettings.suppressAfterCancelMs,
      siteRules: currentSettings.siteRules
    };
    const preferences = await this.preferencesRepository.updateExternalNavigationSettings(nextSettings);
    return {
      settings: preferences.externalNavigation,
      message: this.buildResultMessage(preferences.externalNavigation.appOpenPolicy)
    };
  }

  private normalizeBoundary(boundary: SettingsExternalNavigationBoundary): Required<SettingsExternalNavigationBoundary> {
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    return {
      privacyMode: privacyMode,
      dataScope: normalizeBrowserDataScope(boundary.dataScope, privacyMode)
    };
  }

  private buildResultMessage(policy: ExternalNavigationAppOpenPolicy): string {
    if (policy === 'block') {
      return '已阻止网站打开外部应用。';
    }
    if (policy === 'allow') {
      return '已允许网站直接打开外部应用。';
    }
    return '打开外部应用前会先询问。';
  }
}
