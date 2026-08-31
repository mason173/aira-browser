import {
  BrowserAppServiceMode,
  BrowserAppearanceSettings,
  BrowserDataBoundaryInput,
  BrowserExperimentSettings,
  BrowserGeneralSettings,
  BrowserThemeMode,
  SearchEngineId
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import {
  AppServiceModeConfirmationPrompt,
  AppServiceModeConfirmationViewModel
} from './AppServiceModeConfirmationViewModel';
import { SettingsDetailActionResolver } from './SettingsDetailActionResolver';
import {
  SettingsDetailActionButtonState,
  SettingsDetailRowAction,
  SettingsDetailRowState
} from './SettingsDetailViewModel';
import {
  SettingsRiskPromptState,
  SettingsRiskPromptViewModel
} from './SettingsRiskPromptViewModel';

export interface SettingsDetailInteractionHandlers {
  handleNavigationAction(action: SettingsDetailRowAction): boolean;
  getAppearanceSettings(): BrowserAppearanceSettings;
  getExperimentSettings(): BrowserExperimentSettings;
  getCurrentAppServiceMode(): BrowserAppServiceMode;
  applyThemeMode(mode: BrowserThemeMode): void;
  applySearchEngine(searchEngineId: SearchEngineId): void;
  applyAppServiceMode(mode: BrowserAppServiceMode): void;
  applyPrivateModeAuthenticationEnabled(enabled: boolean): void;
  applyAlwaysUsePrivateModeEnabled(enabled: boolean): void;
  applyPrivateModePreserveCookiesOnClose(enabled: boolean): void;
  applyAppearanceSettings(settings: BrowserAppearanceSettings): void;
  applyExperimentSettingsWithRiskPrompt(
    action: SettingsDetailRowAction,
    targetChecked: boolean,
    settings: BrowserExperimentSettings
  ): void;
  confirmClearAllSiteData(): void;
  confirmResetSitePermissions(): void;
  confirmRefreshSiteIcons(): void;
  showRiskPrompt(prompt: SettingsRiskPromptState, onConfirm: () => void): void;
  showAppServiceModeConfirmation(prompt: AppServiceModeConfirmationPrompt, onConfirm: () => void): void;
}

export class SettingsDetailInteractionCallbackHandlers implements SettingsDetailInteractionHandlers {
  private handleNavigationActionHandler: (action: SettingsDetailRowAction) => boolean;
  private getAppearanceSettingsHandler: () => BrowserAppearanceSettings;
  private getExperimentSettingsHandler: () => BrowserExperimentSettings;
  private getCurrentAppServiceModeHandler: () => BrowserAppServiceMode;
  private applyThemeModeHandler: (mode: BrowserThemeMode) => void;
  private applySearchEngineHandler: (searchEngineId: SearchEngineId) => void;
  private applyAppServiceModeHandler: (mode: BrowserAppServiceMode) => void;
  private applyPrivateModeAuthenticationEnabledHandler: (enabled: boolean) => void;
  private applyAlwaysUsePrivateModeEnabledHandler: (enabled: boolean) => void;
  private applyPrivateModePreserveCookiesOnCloseHandler: (enabled: boolean) => void;
  private applyAppearanceSettingsHandler: (settings: BrowserAppearanceSettings) => void;
  private applyExperimentSettingsWithRiskPromptHandler: (
    action: SettingsDetailRowAction,
    targetChecked: boolean,
    settings: BrowserExperimentSettings
  ) => void;
  private confirmClearAllSiteDataHandler: () => void;
  private confirmResetSitePermissionsHandler: () => void;
  private confirmRefreshSiteIconsHandler: () => void;
  private showRiskPromptHandler: (prompt: SettingsRiskPromptState, onConfirm: () => void) => void;
  private showAppServiceModeConfirmationHandler: (
    prompt: AppServiceModeConfirmationPrompt,
    onConfirm: () => void
  ) => void;

  constructor(
    handleNavigationActionHandler: (action: SettingsDetailRowAction) => boolean,
    getAppearanceSettingsHandler: () => BrowserAppearanceSettings,
    getExperimentSettingsHandler: () => BrowserExperimentSettings,
    getCurrentAppServiceModeHandler: () => BrowserAppServiceMode,
    applyThemeModeHandler: (mode: BrowserThemeMode) => void,
    applySearchEngineHandler: (searchEngineId: SearchEngineId) => void,
    applyAppServiceModeHandler: (mode: BrowserAppServiceMode) => void,
    applyPrivateModeAuthenticationEnabledHandler: (enabled: boolean) => void,
    applyAlwaysUsePrivateModeEnabledHandler: (enabled: boolean) => void,
    applyPrivateModePreserveCookiesOnCloseHandler: (enabled: boolean) => void,
    applyAppearanceSettingsHandler: (settings: BrowserAppearanceSettings) => void,
    applyExperimentSettingsWithRiskPromptHandler: (
      action: SettingsDetailRowAction,
      targetChecked: boolean,
      settings: BrowserExperimentSettings
    ) => void,
    confirmClearAllSiteDataHandler: () => void,
    confirmResetSitePermissionsHandler: () => void,
    confirmRefreshSiteIconsHandler: () => void,
    showRiskPromptHandler: (prompt: SettingsRiskPromptState, onConfirm: () => void) => void,
    showAppServiceModeConfirmationHandler: (
      prompt: AppServiceModeConfirmationPrompt,
      onConfirm: () => void
    ) => void
  ) {
    this.handleNavigationActionHandler = handleNavigationActionHandler;
    this.getAppearanceSettingsHandler = getAppearanceSettingsHandler;
    this.getExperimentSettingsHandler = getExperimentSettingsHandler;
    this.getCurrentAppServiceModeHandler = getCurrentAppServiceModeHandler;
    this.applyThemeModeHandler = applyThemeModeHandler;
    this.applySearchEngineHandler = applySearchEngineHandler;
    this.applyAppServiceModeHandler = applyAppServiceModeHandler;
    this.applyPrivateModeAuthenticationEnabledHandler = applyPrivateModeAuthenticationEnabledHandler;
    this.applyAlwaysUsePrivateModeEnabledHandler = applyAlwaysUsePrivateModeEnabledHandler;
    this.applyPrivateModePreserveCookiesOnCloseHandler = applyPrivateModePreserveCookiesOnCloseHandler;
    this.applyAppearanceSettingsHandler = applyAppearanceSettingsHandler;
    this.applyExperimentSettingsWithRiskPromptHandler = applyExperimentSettingsWithRiskPromptHandler;
    this.confirmClearAllSiteDataHandler = confirmClearAllSiteDataHandler;
    this.confirmResetSitePermissionsHandler = confirmResetSitePermissionsHandler;
    this.confirmRefreshSiteIconsHandler = confirmRefreshSiteIconsHandler;
    this.showRiskPromptHandler = showRiskPromptHandler;
    this.showAppServiceModeConfirmationHandler = showAppServiceModeConfirmationHandler;
  }

  handleNavigationAction(action: SettingsDetailRowAction): boolean {
    return this.handleNavigationActionHandler(action);
  }

  getAppearanceSettings(): BrowserAppearanceSettings {
    return this.getAppearanceSettingsHandler();
  }

  getExperimentSettings(): BrowserExperimentSettings {
    return this.getExperimentSettingsHandler();
  }

  getCurrentAppServiceMode(): BrowserAppServiceMode {
    return this.getCurrentAppServiceModeHandler();
  }

  applyThemeMode(mode: BrowserThemeMode): void {
    this.applyThemeModeHandler(mode);
  }

  applySearchEngine(searchEngineId: SearchEngineId): void {
    this.applySearchEngineHandler(searchEngineId);
  }

  applyAppServiceMode(mode: BrowserAppServiceMode): void {
    this.applyAppServiceModeHandler(mode);
  }

  applyPrivateModeAuthenticationEnabled(enabled: boolean): void {
    this.applyPrivateModeAuthenticationEnabledHandler(enabled);
  }

  applyAlwaysUsePrivateModeEnabled(enabled: boolean): void {
    this.applyAlwaysUsePrivateModeEnabledHandler(enabled);
  }

  applyPrivateModePreserveCookiesOnClose(enabled: boolean): void {
    this.applyPrivateModePreserveCookiesOnCloseHandler(enabled);
  }

  applyAppearanceSettings(settings: BrowserAppearanceSettings): void {
    this.applyAppearanceSettingsHandler(settings);
  }

  applyExperimentSettingsWithRiskPrompt(
    action: SettingsDetailRowAction,
    targetChecked: boolean,
    settings: BrowserExperimentSettings
  ): void {
    this.applyExperimentSettingsWithRiskPromptHandler(action, targetChecked, settings);
  }

  confirmClearAllSiteData(): void {
    this.confirmClearAllSiteDataHandler();
  }

  confirmResetSitePermissions(): void {
    this.confirmResetSitePermissionsHandler();
  }

  confirmRefreshSiteIcons(): void {
    this.confirmRefreshSiteIconsHandler();
  }

  showRiskPrompt(prompt: SettingsRiskPromptState, onConfirm: () => void): void {
    this.showRiskPromptHandler(prompt, onConfirm);
  }

  showAppServiceModeConfirmation(prompt: AppServiceModeConfirmationPrompt, onConfirm: () => void): void {
    this.showAppServiceModeConfirmationHandler(prompt, onConfirm);
  }
}

export class SettingsDetailInteractionCoordinator {
  private actionResolver: SettingsDetailActionResolver = new SettingsDetailActionResolver();
  private riskPromptViewModel: SettingsRiskPromptViewModel = new SettingsRiskPromptViewModel();
  private appServiceModeConfirmationViewModel: AppServiceModeConfirmationViewModel =
    new AppServiceModeConfirmationViewModel();
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

  async commitExperimentSettings(
    boundaryInput: BrowserDataBoundaryInput,
    settings: BrowserExperimentSettings
  ): Promise<BrowserExperimentSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundaryInput);
    const preferences = await this.preferencesRepository.updateExperimentSettings(settings);
    return preferences.experiments;
  }

  async commitAppearanceSettings(
    boundaryInput: BrowserDataBoundaryInput,
    settings: BrowserAppearanceSettings
  ): Promise<BrowserAppearanceSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundaryInput);
    const preferences = await this.preferencesRepository.updateAppearanceSettings(settings);
    return preferences.appearance;
  }

  async commitGeneralSettings(
    boundaryInput: BrowserDataBoundaryInput,
    settings: BrowserGeneralSettings
  ): Promise<BrowserGeneralSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundaryInput);
    const preferences = await this.preferencesRepository.updateGeneralSettings(settings);
    return preferences.general;
  }

  private ensureDevicePreferenceWriteAllowed(boundaryInput: BrowserDataBoundaryInput): void {
    const decision = this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: 'device_preferences',
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      throw new Error('Settings device preference write privacy effect was not allowed.');
    }
  }

  handleRowAction(
    row: SettingsDetailRowState,
    nextChecked: boolean | undefined,
    handlers: SettingsDetailInteractionHandlers
  ): void {
    if (!row.isEnabled && row.action !== 'open_app_icon_settings') {
      return;
    }
    if (handlers.handleNavigationAction(row.action)) {
      return;
    }
    const themeMode = this.actionResolver.resolveThemeMode(row.action);
    if (themeMode !== undefined) {
      handlers.applyThemeMode(themeMode);
      return;
    }
    const searchEngineId = this.actionResolver.resolveSearchEngine(row.action);
    if (searchEngineId !== undefined) {
      handlers.applySearchEngine(searchEngineId);
      return;
    }
    const appServiceMode = this.actionResolver.resolveAppServiceMode(row.action);
    if (appServiceMode !== undefined) {
      this.requestAppServiceModeChange(appServiceMode, handlers);
      return;
    }
    const targetChecked = nextChecked ?? !row.checked;
    if (row.action === 'toggle_private_mode_authentication') {
      handlers.applyPrivateModeAuthenticationEnabled(targetChecked);
      return;
    }
    if (row.action === 'toggle_always_use_private_mode') {
      handlers.applyAlwaysUsePrivateModeEnabled(targetChecked);
      return;
    }
    if (row.action === 'toggle_private_mode_preserve_cookies_on_close') {
      handlers.applyPrivateModePreserveCookiesOnClose(targetChecked);
      return;
    }
    const nextAppearanceSettings = this.actionResolver.buildAppearanceSettingsForAction(
      row.action,
      targetChecked,
      handlers.getAppearanceSettings()
    );
    if (nextAppearanceSettings !== undefined) {
      handlers.applyAppearanceSettings(nextAppearanceSettings);
      return;
    }
    const nextExperimentSettings = this.actionResolver.buildExperimentSettingsForAction(
      row.action,
      targetChecked,
      handlers.getExperimentSettings()
    );
    if (nextExperimentSettings !== undefined) {
      handlers.applyExperimentSettingsWithRiskPrompt(row.action, targetChecked, nextExperimentSettings);
      return;
    }
  }

  handleActionButton(
    button: SettingsDetailActionButtonState,
    handlers: SettingsDetailInteractionHandlers
  ): void {
    if (!button.isEnabled) {
      return;
    }
    if (button.action === 'clear_all_site_data') {
      handlers.confirmClearAllSiteData();
      return;
    }
    if (button.action === 'reset_site_permissions') {
      handlers.confirmResetSitePermissions();
      return;
    }
    if (button.action === 'refresh_site_icons') {
      handlers.confirmRefreshSiteIcons();
    }
  }

  private requestAppServiceModeChange(
    mode: BrowserAppServiceMode,
    handlers: SettingsDetailInteractionHandlers
  ): void {
    const prompt = this.appServiceModeConfirmationViewModel.buildPrompt(
      handlers.getCurrentAppServiceMode(),
      mode
    );
    if (prompt !== undefined) {
      handlers.showAppServiceModeConfirmation(prompt, () => {
        handlers.applyAppServiceMode(mode);
      });
      return;
    }
    handlers.applyAppServiceMode(mode);
  }

  private applyRiskGatedToggle(
    action: SettingsDetailRowAction,
    targetChecked: boolean,
    handlers: SettingsDetailInteractionHandlers,
    apply: (enabled: boolean) => void
  ): void {
    const prompt = this.riskPromptViewModel.buildPrompt(action, targetChecked);
    if (prompt !== undefined) {
      handlers.showRiskPrompt(prompt, () => {
        apply(targetChecked);
      });
      return;
    }
    apply(targetChecked);
  }
}
