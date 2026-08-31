import { PasswordSettingsScreen } from '../components/password/PasswordSettingsScreen';
import {
  PasswordSettingsViewModel,
  PasswordSettingsViewState
} from '../../core/password/PasswordSettingsViewModel';
import {
  sharedPasswordSettingsRepository,
  sharedPreferencesRepository
} from '../bootstrap/BrowserAppRuntime';
import {
  PasswordManagerPreferences,
  PasswordManagerSettings
} from '../../common/models/BrowserModels';
import { CredentialSecurityService } from '../../services/password/CredentialSecurityService';
import {
  readBrowserBoundaryRouteState,
  readSettingsTargetRouteState
} from '../../common/utils/RouteParamUtils';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../core/theme/BrowserThemeViewState';

@Entry
@Component
struct PasswordSettingsPage {
  private viewModel: PasswordSettingsViewModel = new PasswordSettingsViewModel();
  private securityService: CredentialSecurityService = new CredentialSecurityService();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private themePreferencesListenerKey: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private settingsRevealTargetId: string = '';
  @State private state: PasswordSettingsViewState = this.buildState();
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshState();
    this.applyWindowPrivacyMode(true);
  }

  onPageShow(): void {
    this.refreshState();
    this.applyWindowPrivacyMode(true);
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
    this.applyWindowPrivacyMode(false);
  }

  build() {
    Column() {
      PasswordSettingsScreen({
        state: this.state,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        pageBackground: this.theme.pageBackground,
        surfaceBackground: this.theme.surfaceBackground,
        controlBackground: this.theme.controlBackground,
        pressedBackground: this.theme.pressedBackground,
        accentColor: this.theme.accent,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        revealTargetId: this.settingsRevealTargetId,
        revealRevision: this.settingsRevealTargetId.length > 0 ? 1 : 0,
        onOfficialVaultChange: (enabled: boolean) => {
          this.updatePreference('officialVaultEnabled', enabled);
        },
        onRegularAutofillChange: (enabled: boolean) => {
          this.updatePreference('regularAutofillEnabled', enabled);
        },
        onRegularSavePromptChange: (enabled: boolean) => {
          this.updatePreference('regularSavePromptEnabled', enabled);
        },
        onPrivateAutofillChange: (enabled: boolean) => {
          this.updatePreference('privateAutofillEnabled', enabled);
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private buildState(): PasswordSettingsViewState {
    return this.viewModel.buildState(sharedPasswordSettingsRepository.getSettings());
  }

  private refreshState(): void {
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.settingsRevealTargetId = readSettingsTargetRouteState({
      settingsTargetId: '',
      settingsRevealTargetId: this.settingsRevealTargetId
    }).settingsRevealTargetId;
    this.refreshThemeState();
    this.state = this.buildState();
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  private bindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length > 0) {
      return;
    }
    this.themePreferencesListenerKey = sharedPreferencesRepository.subscribe((_preferences, scope) => {
      if (scope === 'theme_mode' || scope === 'appearance') {
        this.refreshThemeState();
      }
    });
  }

  private unbindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length <= 0) {
      return;
    }
    sharedPreferencesRepository.unsubscribe(this.themePreferencesListenerKey);
    this.themePreferencesListenerKey = '';
  }

  private updatePreference(
    key: 'officialVaultEnabled' | 'regularAutofillEnabled' | 'regularSavePromptEnabled' | 'privateAutofillEnabled',
    enabled: boolean
  ): void {
    const current = sharedPasswordSettingsRepository.getSettings().preferences;
    const nextPreferences: PasswordManagerPreferences = this.viewModel.buildPreferencesPatch(current, key, enabled);
    const previousState = this.state;
    const currentSettings = sharedPasswordSettingsRepository.getSettings();
    this.state = this.viewModel.buildState({
      provider: currentSettings.provider,
      preferences: nextPreferences,
      officialVaultVerifiedAt: currentSettings.officialVaultVerifiedAt,
      officialVaultVerificationNote: currentSettings.officialVaultVerificationNote,
      selfHostedCredentialStoreEnabled: currentSettings.selfHostedCredentialStoreEnabled,
      updatedAt: currentSettings.updatedAt
    });
    sharedPasswordSettingsRepository.updatePreferences(nextPreferences)
      .then((settings: PasswordManagerSettings) => {
        this.state = this.viewModel.buildState(settings);
      })
      .catch((_error: Error) => {
        this.state = previousState;
      });
  }

  private applyWindowPrivacyMode(enabled: boolean): void {
    this.securityService.setPasswordWindowPrivacyMode(enabled)
      .catch((_error: Error) => {});
  }
}
