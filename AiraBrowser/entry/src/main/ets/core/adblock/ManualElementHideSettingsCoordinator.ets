import {
  ManualElementHideSiteRules,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { ManualElementHideRepository } from '../../data/adblock/ManualElementHideRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export interface ManualElementHideSettingsBoundary {
  dataScope: string;
  privacyMode: string;
}

export interface ManualElementHideSettingsMutationResult {
  allowed: boolean;
  changed: boolean;
}

export class ManualElementHideSettingsCoordinator {
  private readonly repository: ManualElementHideRepository;
  private readonly privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private readonly profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    repository: ManualElementHideRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.repository = repository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  setSiteEnabled(
    host: string,
    enabled: boolean,
    boundary: ManualElementHideSettingsBoundary
  ): Promise<ManualElementHideSettingsMutationResult> {
    return this.commit(boundary, async (): Promise<boolean> => {
      const site: ManualElementHideSiteRules | undefined = await this.repository.setSiteEnabled(host, enabled);
      return site !== undefined;
    });
  }

  removeRule(
    host: string,
    ruleId: string,
    boundary: ManualElementHideSettingsBoundary
  ): Promise<ManualElementHideSettingsMutationResult> {
    return this.commit(boundary, (): Promise<boolean> => this.repository.removeRule(host, ruleId));
  }

  clearSite(
    host: string,
    boundary: ManualElementHideSettingsBoundary
  ): Promise<ManualElementHideSettingsMutationResult> {
    return this.commit(boundary, (): Promise<boolean> => this.repository.clearSite(host));
  }

  private async commit(
    boundary: ManualElementHideSettingsBoundary,
    mutation: () => Promise<boolean>
  ): Promise<ManualElementHideSettingsMutationResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return {
        allowed: false,
        changed: false
      };
    }
    return {
      allowed: true,
      changed: await mutation()
    };
  }

  private canWriteDevicePreference(boundary: ManualElementHideSettingsBoundary): boolean {
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
