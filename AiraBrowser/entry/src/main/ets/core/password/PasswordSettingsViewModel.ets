import {
  PasswordManagerPreferences,
  PasswordManagerSettings
} from '../../common/models/BrowserModels';
import {
  PasswordPagePolicyResult,
  PasswordPolicyService
} from '../../services/password/PasswordPolicyService';

export interface PasswordSettingsViewState {
  officialVaultEnabled: boolean;
  regularAutofillEnabled: boolean;
  regularSavePromptEnabled: boolean;
  privateAutofillEnabled: boolean;
  regularSummary: string;
  privateSummary: string;
}

export class PasswordSettingsViewModel {
  private policyService: PasswordPolicyService = new PasswordPolicyService();

  buildState(settings: PasswordManagerSettings): PasswordSettingsViewState {
    const regularPolicy = this.policyService.resolvePagePolicy(settings, 'regular', 'profile_persistent');
    const privatePolicy = this.policyService.resolvePagePolicy(settings, 'private', 'session_ephemeral');
    return {
      officialVaultEnabled: settings.preferences.officialVaultEnabled,
      regularAutofillEnabled: settings.preferences.regularAutofillEnabled,
      regularSavePromptEnabled: settings.preferences.regularSavePromptEnabled,
      privateAutofillEnabled: settings.preferences.privateAutofillEnabled,
      regularSummary: this.buildPolicySummary(regularPolicy),
      privateSummary: this.buildPolicySummary(privatePolicy)
    };
  }

  buildPreferencesPatch(
    current: PasswordManagerPreferences,
    key: 'officialVaultEnabled' | 'regularAutofillEnabled' | 'regularSavePromptEnabled' | 'privateAutofillEnabled',
    value: boolean
  ): PasswordManagerPreferences {
    return {
      officialVaultEnabled: key === 'officialVaultEnabled' ? value : current.officialVaultEnabled,
      regularAutofillEnabled: key === 'regularAutofillEnabled' ? value : current.regularAutofillEnabled,
      regularSavePromptEnabled: key === 'regularSavePromptEnabled' ? value : current.regularSavePromptEnabled,
      privateAutofillEnabled: key === 'privateAutofillEnabled' ? value : current.privateAutofillEnabled,
      privateSavePromptEnabled: false
    };
  }

  private buildPolicySummary(policy: PasswordPagePolicyResult): string {
    return policy.summary;
  }

}
