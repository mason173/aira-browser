import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  PasswordManagerSettings
} from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';

export interface PasswordPagePolicyResult {
  officialVaultEnabled: boolean;
  autofillEnabled: boolean;
  savePromptEnabled: boolean;
  summary: string;
}

export class PasswordPolicyService {
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  resolvePagePolicy(
    settings: PasswordManagerSettings,
    privacyMode: BrowserSessionPrivacyMode = 'regular',
    dataScope: BrowserDataScope = 'profile_persistent'
  ): PasswordPagePolicyResult {
    if (!settings.preferences.officialVaultEnabled) {
      return {
        officialVaultEnabled: false,
        autofillEnabled: false,
        savePromptEnabled: false,
        summary: '网页密码保险箱未开启'
      };
    }
    if (this.profileBoundaryService.isSessionEphemeral({
      privacyMode: privacyMode,
      dataScope: dataScope
    })) {
      return {
        officialVaultEnabled: true,
        autofillEnabled: settings.preferences.privateAutofillEnabled,
        savePromptEnabled: false,
        summary: settings.preferences.privateAutofillEnabled
          ? '仅填充，不保存'
          : '不读取，不保存'
      };
    }
    return {
      officialVaultEnabled: true,
      autofillEnabled: settings.preferences.regularAutofillEnabled,
      savePromptEnabled: settings.preferences.regularSavePromptEnabled,
      summary: this.buildRegularSummary(settings)
    };
  }

  buildRegularSummary(settings: PasswordManagerSettings): string {
    if (!settings.preferences.regularAutofillEnabled && !settings.preferences.regularSavePromptEnabled) {
      return '不填充，不保存';
    }
    if (!settings.preferences.regularAutofillEnabled) {
      return '只提示保存';
    }
    if (!settings.preferences.regularSavePromptEnabled) {
      return '只填充已有密码';
    }
    return '填充并提示保存';
  }
}
