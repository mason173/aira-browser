import {
  BrowserDataBoundaryInput,
  BrowserGeneralSettings
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  BrowserFingerprintPrivacyPolicyService,
  BrowserFingerprintPrivacyPolicyState,
  BrowserTrackingProtectionMode
} from '../../services/privacy/BrowserFingerprintPrivacyPolicyService';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export interface BrowserTrackingProtectionOptionState {
  mode: BrowserTrackingProtectionMode;
  title: string;
}

export interface BrowserTrackingProtectionSettingsState extends BrowserFingerprintPrivacyPolicyState {
  selectedLabel: string;
  options: BrowserTrackingProtectionOptionState[];
  footerText: string;
  limitationText: string;
}

export class BrowserTrackingProtectionSettingsCoordinator {
  private readonly preferencesRepository: PreferencesRepository;
  private readonly fingerprintPolicyService: BrowserFingerprintPrivacyPolicyService;
  private readonly privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private readonly profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    preferencesRepository: PreferencesRepository,
    fingerprintPolicyService: BrowserFingerprintPrivacyPolicyService,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.preferencesRepository = preferencesRepository;
    this.fingerprintPolicyService = fingerprintPolicyService;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  buildState(): BrowserTrackingProtectionSettingsState {
    return this.buildStateFromPolicy(
      this.fingerprintPolicyService.buildState(this.preferencesRepository.getPreferences())
    );
  }

  setMode(
    mode: BrowserTrackingProtectionMode,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<BrowserTrackingProtectionSettingsState> {
    if (!this.canWriteDevicePreference(boundaryInput)) {
      return Promise.reject(new Error('Tracking protection device preference write was not allowed.'));
    }
    const current = this.preferencesRepository.getPreferences().general;
    const next: BrowserGeneralSettings = {
      startupRestorePolicy: current.startupRestorePolicy,
      tabAutoClosePolicy: current.tabAutoClosePolicy,
      privateTabRestorePolicy: current.privateTabRestorePolicy,
      privateModeAuthenticationEnabled: current.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: current.alwaysUsePrivateMode === true,
      privateModePreserveCookiesOnClose: current.privateModePreserveCookiesOnClose,
      privateModeThemeEnabled: current.privateModeThemeEnabled,
      enhancedTrackingProtectionEnabled: mode === 'enhanced'
    };
    return this.preferencesRepository.updateGeneralSettings(next)
      .then((): BrowserTrackingProtectionSettingsState => {
        const applied = this.fingerprintPolicyService.applyRuntime(this.preferencesRepository.getPreferences());
        return this.buildStateFromPolicy(applied);
      });
  }

  private buildStateFromPolicy(
    policy: BrowserFingerprintPrivacyPolicyState
  ): BrowserTrackingProtectionSettingsState {
    return {
      mode: policy.mode,
      enhanced: policy.enhanced,
      clientHintsEnabled: policy.clientHintsEnabled,
      thirdPartyCookiesAllowed: policy.thirdPartyCookiesAllowed,
      stableBrowserIdentityEnabled: policy.stableBrowserIdentityEnabled,
      clientHintsRuntimeApplied: policy.clientHintsRuntimeApplied,
      cookiePolicyRuntimeApplied: policy.cookiePolicyRuntimeApplied,
      runtimeApplied: policy.runtimeApplied,
      message: policy.message,
      selectedLabel: policy.enhanced ? '增强' : '标准',
      options: [
        { mode: 'standard', title: '标准' },
        { mode: 'enhanced', title: '增强反跟踪' }
      ],
      footerText: policy.enhanced
        ? '减少跨网站关联：收紧网页客户端提示、拦截第三方 Cookie，并保持网页标识一致。现有网页重新加载后完整生效。'
        : '使用当前网页兼容性策略，第三方 Cookie 和网页客户端提示由各自设置控制。',
      limitationText: policy.runtimeApplied
        ? '增强反跟踪不会伪装 Canvas、WebGL、字体、时区或屏幕渲染，也不是匿名度评分。'
        : `${policy.message}增强反跟踪不会伪装 Canvas、WebGL、字体、时区或屏幕渲染。`
    };
  }

  private canWriteDevicePreference(boundaryInput: BrowserDataBoundaryInput): boolean {
    return this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }
}
