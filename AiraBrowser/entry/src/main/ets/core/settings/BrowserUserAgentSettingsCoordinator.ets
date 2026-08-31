import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  BrowserUserAgentSettings,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { BrowserUserAgentSettingsRepository } from '../../data/browser/BrowserUserAgentSettingsRepository';
import { SavedSiteSettingRepository } from '../../data/browser/SavedSiteSettingRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export class BrowserUserAgentSettingsBoundary {
  dataScope: BrowserDataScope | string;
  privacyMode: BrowserSessionPrivacyMode | string;

  constructor(dataScope: BrowserDataScope | string = '', privacyMode: BrowserSessionPrivacyMode | string = '') {
    this.dataScope = dataScope;
    this.privacyMode = privacyMode;
  }
}

export interface BrowserUserAgentSettingsMutationResult {
  allowed: boolean;
  settings: BrowserUserAgentSettings;
}

export class BrowserUserAgentSettingsCoordinator {
  private repository: BrowserUserAgentSettingsRepository;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private savedSiteSettingRepository?: SavedSiteSettingRepository;

  constructor(
    repository: BrowserUserAgentSettingsRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService(),
    savedSiteSettingRepository?: SavedSiteSettingRepository
  ) {
    this.repository = repository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
    this.savedSiteSettingRepository = savedSiteSettingRepository;
  }

  async saveSettings(
    settings: BrowserUserAgentSettings,
    boundary: BrowserUserAgentSettingsBoundary
  ): Promise<BrowserUserAgentSettingsMutationResult> {
    return this.commit(boundary, (): Promise<BrowserUserAgentSettings> => this.repository.saveSettings(settings));
  }

  async upsertCustomUserAgent(
    name: string,
    userAgent: string,
    boundary: BrowserUserAgentSettingsBoundary
  ): Promise<BrowserUserAgentSettingsMutationResult> {
    return this.commit(
      boundary,
      (): Promise<BrowserUserAgentSettings> => this.repository.upsertCustomUserAgent(name, userAgent)
    );
  }

  async selectCustomUserAgent(
    recordId: string,
    boundary: BrowserUserAgentSettingsBoundary
  ): Promise<BrowserUserAgentSettingsMutationResult> {
    return this.commit(
      boundary,
      (): Promise<BrowserUserAgentSettings> => this.repository.selectCustomUserAgent(recordId)
    );
  }

  async removeCustomUserAgent(
    recordId: string,
    boundary: BrowserUserAgentSettingsBoundary
  ): Promise<BrowserUserAgentSettingsMutationResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return {
        allowed: false,
        settings: this.repository.getSettings()
      };
    }
    const referencesReassigned = this.savedSiteSettingRepository === undefined
      ? true
      : await this.savedSiteSettingRepository.replaceIdentityReferences(recordId);
    if (!referencesReassigned) {
      throw new Error('站点网页标识引用回退失败。');
    }
    return this.commit(
      boundary,
      (): Promise<BrowserUserAgentSettings> => this.repository.removeCustomUserAgent(recordId)
    );
  }

  countCustomUserAgentReferences(recordId: string): number {
    return this.savedSiteSettingRepository?.countIdentityReferences(recordId) ?? 0;
  }

  private async commit(
    boundary: BrowserUserAgentSettingsBoundary,
    mutation: () => Promise<BrowserUserAgentSettings>
  ): Promise<BrowserUserAgentSettingsMutationResult> {
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

  private canWriteDevicePreference(boundary: BrowserUserAgentSettingsBoundary): boolean {
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
}
