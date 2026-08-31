import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  TranslationProviderTemplateId
} from '../../common/models/BrowserModels';
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
import { TranslationProviderEditScreen } from '../components/translation/TranslationProviderEditScreen';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';

@Entry
@Component
struct TranslationProviderEditPage {
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
      TranslationProviderEditScreen({
        providers: this.state.providers,
        onSelectProvider: (providerId: string) => {
          this.selectProvider(providerId);
        },
        onConfigureTemplate: (templateId: TranslationProviderTemplateId) => {
          this.openProviderConfig(templateId);
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
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.state = this.viewModel.buildState(sharedTranslationSettingsRepository.getSettings());
  }

  private selectProvider(providerId: string): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.settingsCoordinator.selectProvider(providerId, this.buildSettingsBoundary())
      .then((result: TranslationSettingsMutationResult) => {
        if (result.allowed) {
          this.navigationCoordinator.back();
        }
      })
      .catch((_error: Error) => {});
  }

  private openProviderConfig(templateId: TranslationProviderTemplateId): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.navigationCoordinator.openTranslationProviderTemplateConfig(this.buildBoundaryState(), templateId);
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource.length > 0 ? this.boundarySource : 'translation_provider_edit'
    };
  }

  private buildSettingsBoundary(): TranslationSettingsBoundary {
    return new TranslationSettingsBoundary(this.dataScope, this.privacyMode);
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }
}
