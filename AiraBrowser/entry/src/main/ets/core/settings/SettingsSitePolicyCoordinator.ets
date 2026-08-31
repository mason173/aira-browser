import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { SiteDataControlService } from '../../services/web/SiteDataControlService';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import { BrowserFingerprintPrivacyPolicyService } from '../../services/privacy/BrowserFingerprintPrivacyPolicyService';

export interface SettingsSitePolicyBoundary {
  profileId?: BrowserProfileId | string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
}

export type SettingsCookiePolicyMode = 'allow_all' | 'block_third_party' | 'block_all';

export interface SettingsSitePolicyState {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  acceptCookies: boolean;
  acceptThirdPartyCookies: boolean;
  thirdPartyCookiePolicyLocked: boolean;
  cookiePolicyMode: SettingsCookiePolicyMode;
  canEditCookiePolicy: boolean;
}

export interface SettingsSitePolicyMutationResult {
  allowed: boolean;
  state: SettingsSitePolicyState;
}

export class SettingsSitePolicyCoordinator {
  private siteDataControlService: SiteDataControlService;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    preferencesRepository: PreferencesRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.siteDataControlService = new SiteDataControlService(preferencesRepository);
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  buildState(boundary: SettingsSitePolicyBoundary = {}): SettingsSitePolicyState {
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    const dataScope = normalizeBrowserDataScope(boundary.dataScope, privacyMode);
    const profileId = normalizeBrowserProfileId(boundary.profileId ?? DEFAULT_BROWSER_PROFILE_ID);
    const snapshot = this.siteDataControlService.getBoundarySnapshot(profileId, privacyMode, dataScope);
    const thirdPartyCookiePolicyLocked = BrowserFingerprintPrivacyPolicyService.isEnhancedEnabled();
    const canEditCookiePolicy = this.isDevicePreferenceWriteAllowedForBoundary(
      privacyMode,
      dataScope
    );
    return {
      profileId: profileId,
      privacyMode: privacyMode,
      dataScope: dataScope,
      acceptCookies: snapshot.acceptCookies,
      acceptThirdPartyCookies: snapshot.acceptThirdPartyCookies,
      thirdPartyCookiePolicyLocked: thirdPartyCookiePolicyLocked,
      cookiePolicyMode: this.resolveCookiePolicyMode(
        snapshot.acceptCookies,
        snapshot.acceptThirdPartyCookies,
        thirdPartyCookiePolicyLocked
      ),
      canEditCookiePolicy: canEditCookiePolicy
    };
  }

  async setCookiePolicyMode(
    mode: SettingsCookiePolicyMode,
    boundary: SettingsSitePolicyBoundary
  ): Promise<SettingsSitePolicyMutationResult> {
    const boundaryState = this.buildState(boundary);
    if (!boundaryState.canEditCookiePolicy) {
      return {
        allowed: false,
        state: boundaryState
      };
    }
    if (mode === 'allow_all' && boundaryState.thirdPartyCookiePolicyLocked) {
      return {
        allowed: false,
        state: boundaryState
      };
    }
    await this.siteDataControlService.setCookiePolicyEnabledState(
      mode !== 'block_all',
      mode === 'allow_all'
    );
    const nextState = this.buildState(boundary);
    return {
      allowed: true,
      state: nextState
    };
  }

  private isDevicePreferenceWriteAllowedForBoundary(
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): boolean {
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

  private resolveCookiePolicyMode(
    acceptCookies: boolean,
    acceptThirdPartyCookies: boolean,
    thirdPartyCookiePolicyLocked: boolean
  ): SettingsCookiePolicyMode {
    if (!acceptCookies) {
      return 'block_all';
    }
    if (thirdPartyCookiePolicyLocked || !acceptThirdPartyCookies) {
      return 'block_third_party';
    }
    return 'allow_all';
  }

}
