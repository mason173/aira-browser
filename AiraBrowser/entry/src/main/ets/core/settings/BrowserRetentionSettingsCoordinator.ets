import {
  BrowserDataBoundaryInput,
  BrowserRetentionProfileId,
  BrowserRetentionSettings
} from '../../common/models/BrowserModels';
import {
  buildBrowserRetentionSettingsForProfile,
  PreferencesRepository
} from '../../data/preferences/PreferencesRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export interface BrowserRetentionSettingsApplyResult {
  settings: BrowserRetentionSettings;
  message: string;
}

export class BrowserRetentionSettingsCoordinator {
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

  buildSettingsForProfile(
    profileId: BrowserRetentionProfileId,
    currentSettings: BrowserRetentionSettings
  ): BrowserRetentionSettings {
    return buildBrowserRetentionSettingsForProfile(profileId, currentSettings.deviceTierHint);
  }

  async applyProfile(
    profileId: BrowserRetentionProfileId,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<BrowserRetentionSettingsApplyResult> {
    const decision = this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: 'device_preferences',
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      throw new Error('Retention device preference write privacy effect was not allowed.');
    }
    const currentSettings = this.preferencesRepository.getPreferences().retention;
    const nextSettings = this.buildSettingsForProfile(profileId, currentSettings);
    const preferences = await this.preferencesRepository.updateRetentionSettings(nextSettings);
    return {
      settings: preferences.retention,
      message: this.buildResultMessage(preferences.retention.profileId)
    };
  }

  buildResultMessage(profileId: BrowserRetentionProfileId): string {
    if (profileId === 'memory_saver') {
      return '已切换为省电优先。';
    }
    if (profileId === 'keep_more_tabs') {
      return '已切换为多标签性能。';
    }
    return '已切换为均衡策略。';
  }
}
