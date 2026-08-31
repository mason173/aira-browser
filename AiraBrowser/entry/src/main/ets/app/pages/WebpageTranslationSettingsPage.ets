import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { WebpageTranslationSettingsScreen } from '../components/translation/WebpageTranslationSettingsScreen';
import { AIRA_SYSTEM_TRANSLATION_PROVIDER_ID } from '../../data/translation/TranslationSettingsRepository';
import {
  WebpageTranslationSettingsViewModel,
  WebpageTranslationSettingsViewState
} from '../../core/translation/WebpageTranslationSettingsViewModel';
import {
  sharedPreferencesRepository,
  sharedTranslationSecretStore,
  sharedTranslationSettingsRepository
} from '../bootstrap/BrowserAppRuntime';
import {
  TranslationSettingsBoundary,
  TranslationSettingsCoordinator,
  TranslationSettingsMutationResult
} from '../../core/translation/TranslationSettingsCoordinator';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState,
  readSettingsTargetRouteState
} from '../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';

@Entry
@Component
struct WebpageTranslationSettingsPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private viewModel: WebpageTranslationSettingsViewModel = new WebpageTranslationSettingsViewModel();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsCoordinator: TranslationSettingsCoordinator = new TranslationSettingsCoordinator(
    sharedTranslationSettingsRepository,
    sharedTranslationSecretStore
  );
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private controlsEnabled: boolean = true;
  @State private settingsRevealTargetId: string = '';
  @State private state: WebpageTranslationSettingsViewState =
    this.viewModel.buildState(sharedTranslationSettingsRepository.getSettings());

  aboutToAppear(): void {
    this.refreshState();
  }

  onPageShow(): void {
    this.refreshState();
  }

  build() {
    Column() {
      WebpageTranslationSettingsScreen({
        state: this.state,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        controlsEnabled: this.controlsEnabled,
        revealTargetId: this.settingsRevealTargetId,
        revealRevision: this.settingsRevealTargetId.length > 0 ? 1 : 0,
        onEnabledChange: (enabled: boolean) => {
          this.updatePreference('enabled', enabled);
        },
        onAllowPrivateTabsChange: (enabled: boolean) => {
          this.updatePreference('allowInPrivateTabs', enabled);
        },
        onOpenProviderSelection: () => {
          this.openProviderSelection();
        },
        onEditActiveProvider: () => {
          this.openActiveProviderEditor();
        },
        onSelectTargetLanguage: (languageCode: string) => {
          this.selectTargetLanguage(languageCode);
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private refreshState(): void {
    this.controlsEnabled = this.appServiceModeGateService.canUseOptionalService();
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
    this.state = this.viewModel.buildState(sharedTranslationSettingsRepository.getSettings());
  }


  private updatePreference(
    key: 'enabled' | 'allowInPrivateTabs' | 'preferredTargetLanguage',
    value: boolean | string | number
  ): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      return;
    }
    const previousState = this.state;
    this.settingsCoordinator.updatePreference(key, value, this.buildSettingsBoundary())
      .then((result: TranslationSettingsMutationResult) => {
        this.state = result.allowed ? this.viewModel.buildState(result.settings) : previousState;
      })
      .catch((_error: Error) => {
        this.state = previousState;
      });
  }

  private openProviderSelection(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      return;
    }
    this.navigationCoordinator.openTranslationProviderSelection(this.buildBoundaryState());
  }

  private openActiveProviderEditor(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      return;
    }
    const activeProviderId = sharedTranslationSettingsRepository.getSettings().activeProviderId;
    if (activeProviderId.length === 0 || activeProviderId === AIRA_SYSTEM_TRANSLATION_PROVIDER_ID) {
      this.openProviderSelection();
      return;
    }
    this.openProviderEditor(activeProviderId);
  }

  private openProviderEditor(providerId: string): void {
    this.navigationCoordinator.openTranslationProviderConfig(this.buildBoundaryState(), providerId);
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }

  private buildSettingsBoundary(): TranslationSettingsBoundary {
    return new TranslationSettingsBoundary(this.dataScope, this.privacyMode);
  }

  private selectTargetLanguage(languageCode: string): void {
    this.updatePreference('preferredTargetLanguage', languageCode);
  }

}
