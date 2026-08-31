import {
  BrowserCookiePolicySettings,
  BrowserGeneralSettings,
  BrowserPreferences
} from '../../common/models/BrowserModels';
import { BrowserPrivacyRuntimeAdapter } from './BrowserPrivacyRuntimeAdapter';

export type BrowserTrackingProtectionMode = 'standard' | 'enhanced';

export interface BrowserFingerprintPrivacyPolicyState {
  mode: BrowserTrackingProtectionMode;
  enhanced: boolean;
  clientHintsEnabled: boolean;
  thirdPartyCookiesAllowed: boolean;
  stableBrowserIdentityEnabled: boolean;
  clientHintsRuntimeApplied: boolean;
  cookiePolicyRuntimeApplied: boolean;
  runtimeApplied: boolean;
  message: string;
}

export class BrowserFingerprintPrivacyPolicyService {
  private static currentMode: BrowserTrackingProtectionMode = 'standard';
  private static currentClientHintsRuntimeApplied: boolean = false;
  private static currentCookiePolicyRuntimeApplied: boolean = false;
  private readonly runtimeAdapter: BrowserPrivacyRuntimeAdapter;

  constructor(runtimeAdapter: BrowserPrivacyRuntimeAdapter = new BrowserPrivacyRuntimeAdapter()) {
    this.runtimeAdapter = runtimeAdapter;
  }

  static resolveCurrentMode(): BrowserTrackingProtectionMode {
    return BrowserFingerprintPrivacyPolicyService.currentMode;
  }

  static isEnhancedEnabled(): boolean {
    return BrowserFingerprintPrivacyPolicyService.currentMode === 'enhanced';
  }

  static areClientHintsEnabledAtApplicationScope(): boolean {
    return false;
  }

  static isCurrentRuntimeApplied(): boolean {
    return BrowserFingerprintPrivacyPolicyService.currentClientHintsRuntimeApplied &&
      BrowserFingerprintPrivacyPolicyService.currentCookiePolicyRuntimeApplied;
  }

  static resolveCurrentSummary(): string {
    if (BrowserFingerprintPrivacyPolicyService.isEnhancedEnabled()) {
      return BrowserFingerprintPrivacyPolicyService.isCurrentRuntimeApplied()
        ? '增强已开启'
        : '增强未完全生效';
    }
    return BrowserFingerprintPrivacyPolicyService.isCurrentRuntimeApplied() ? '标准' : '标准模式待应用';
  }

  static reportClientHintsRuntimeApplied(applied: boolean): void {
    BrowserFingerprintPrivacyPolicyService.currentClientHintsRuntimeApplied = applied;
  }

  static reportCookiePolicyRuntimeApplied(applied: boolean): void {
    BrowserFingerprintPrivacyPolicyService.currentCookiePolicyRuntimeApplied = applied;
  }

  static resolveMode(settings: BrowserGeneralSettings | undefined): BrowserTrackingProtectionMode {
    return settings?.enhancedTrackingProtectionEnabled === true ? 'enhanced' : 'standard';
  }

  static resolveEffectiveThirdPartyCookiesAllowed(requestedAllowed: boolean): boolean {
    return BrowserFingerprintPrivacyPolicyService.isEnhancedEnabled() ? false : requestedAllowed;
  }

  buildState(preferences: BrowserPreferences): BrowserFingerprintPrivacyPolicyState {
    const mode = BrowserFingerprintPrivacyPolicyService.resolveMode(preferences.general);
    const runtimeModeMatches = mode === BrowserFingerprintPrivacyPolicyService.currentMode;
    return this.buildStateForMode(
      mode,
      preferences.cookiePolicy,
      runtimeModeMatches && BrowserFingerprintPrivacyPolicyService.currentClientHintsRuntimeApplied,
      runtimeModeMatches && BrowserFingerprintPrivacyPolicyService.currentCookiePolicyRuntimeApplied,
      runtimeModeMatches && BrowserFingerprintPrivacyPolicyService.isCurrentRuntimeApplied()
        ? '防跟踪策略已应用。'
        : '防跟踪策略尚未完全应用。'
    );
  }

  applyRuntime(preferences: BrowserPreferences): BrowserFingerprintPrivacyPolicyState {
    const mode = BrowserFingerprintPrivacyPolicyService.resolveMode(preferences.general);
    BrowserFingerprintPrivacyPolicyService.currentMode = mode;
    const enhanced = mode === 'enhanced';
    // ArkWeb's process default is disabled on the target runtime. Keeping it
    // disabled avoids adding a second UA identity dimension to native-default
    // pages; explicit compatibility identities may enable it at controller
    // scope when their metadata is intentionally selected.
    const clientHintsRuntimeApplied = this.runtimeAdapter.applyClientHintsEnabled(false);
    const cookiePolicyRuntimeApplied = this.runtimeAdapter.applyCookiePolicy(
      preferences.cookiePolicy.acceptCookies,
      BrowserFingerprintPrivacyPolicyService.resolveEffectiveThirdPartyCookiesAllowed(
        preferences.cookiePolicy.acceptThirdPartyCookies
      )
    );
    BrowserFingerprintPrivacyPolicyService.reportClientHintsRuntimeApplied(clientHintsRuntimeApplied);
    BrowserFingerprintPrivacyPolicyService.reportCookiePolicyRuntimeApplied(cookiePolicyRuntimeApplied);
    const runtimeApplied = clientHintsRuntimeApplied && cookiePolicyRuntimeApplied;
    return this.buildStateForMode(
      mode,
      preferences.cookiePolicy,
      clientHintsRuntimeApplied,
      cookiePolicyRuntimeApplied,
      runtimeApplied ? '防跟踪策略已应用。' : '部分防跟踪策略未能应用，请重启 Aira 后重试。'
    );
  }

  private buildStateForMode(
    mode: BrowserTrackingProtectionMode,
    cookiePolicy: BrowserCookiePolicySettings,
    clientHintsRuntimeApplied: boolean,
    cookiePolicyRuntimeApplied: boolean,
    message: string
  ): BrowserFingerprintPrivacyPolicyState {
    const enhanced = mode === 'enhanced';
    return {
      mode: mode,
      enhanced: enhanced,
      clientHintsEnabled: false,
      thirdPartyCookiesAllowed: enhanced ? false : cookiePolicy.acceptThirdPartyCookies,
      stableBrowserIdentityEnabled: enhanced,
      clientHintsRuntimeApplied: clientHintsRuntimeApplied,
      cookiePolicyRuntimeApplied: cookiePolicyRuntimeApplied,
      runtimeApplied: clientHintsRuntimeApplied && cookiePolicyRuntimeApplied,
      message: message
    };
  }
}
