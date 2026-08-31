import { AdBlockSettingsScreen } from '../components/adblock/AdBlockSettingsScreen';
import { showCenteredAlertDialog } from '../components/common/CenteredDialogSurface';
import {
  AdBlockSettingsViewModel,
  AdBlockSettingsViewState
} from '../../core/adblock/AdBlockSettingsViewModel';
import {
  AdBlockRiskConsentSheetState,
  AdBlockRiskConsentViewModel
} from '../../core/adblock/AdBlockRiskConsentViewModel';
import {
  AdBlockSettingsBoundary,
  AdBlockSettingsCoordinator,
  AdBlockSettingsMutationResult
} from '../../core/adblock/AdBlockSettingsCoordinator';
import {
  sharedAdBlockRepository,
  sharedAdBlockRuntimeGenerationCoordinator,
  sharedPreferencesRepository
} from '../bootstrap/BrowserAppRuntime';
import {
  AdBlockPreferences,
  AdBlockSettings
} from '../../common/models/BrowserModels';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState,
  readSettingsTargetRouteState
} from '../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../core/theme/BrowserThemeViewState';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import { AdBlockRiskConsentSheet } from '../components/adblock/AdBlockRiskConsentSheet';

@Entry
@Component
struct AdBlockSettingsPage {
  private viewModel: AdBlockSettingsViewModel = new AdBlockSettingsViewModel();
  private riskConsentViewModel: AdBlockRiskConsentViewModel = new AdBlockRiskConsentViewModel();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private settingsCoordinator: AdBlockSettingsCoordinator = new AdBlockSettingsCoordinator(
    sharedAdBlockRepository,
    sharedAdBlockRuntimeGenerationCoordinator
  );
  private themePreferencesListenerKey: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private controlsEnabled: boolean = true;
  @State private settingsRevealTargetId: string = '';
  @State private state: AdBlockSettingsViewState =
    this.buildViewState(sharedAdBlockRepository.getSettings());
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @State private riskConsentVisible: boolean = false;
  @State private pendingEnableAfterConsent: boolean = false;
  @State private riskConsentState: AdBlockRiskConsentSheetState = this.riskConsentViewModel.buildState();

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshState();
    this.loadAdBlockSettings();
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  onPageShow(): void {
    this.refreshState();
    this.loadAdBlockSettings();
  }

  build() {
    Column() {
      AdBlockSettingsScreen({
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
        controlsEnabled: this.controlsEnabled,
        revealTargetId: this.settingsRevealTargetId,
        revealRevision: this.settingsRevealTargetId.length > 0 ? 1 : 0,
        onEnabledChange: (enabled: boolean) => {
          this.requestEnabledChange(enabled);
        },
        onOpenCustomRules: () => {
          this.openCustomRulesPage();
        },
        onOpenManualElementHideSettings: () => {
          this.openManualElementHideSettingsPage();
        },
        onClearStats: () => {
          this.confirmClearStats();
        },
        onRemoveException: (host: string) => {
          this.removeException(host);
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet($$this.riskConsentVisible, this.buildRiskConsentSheet(), {
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.handleRiskConsentDisappear();
      }
    })
  }

  @Builder
  private buildRiskConsentSheet() {
    AdBlockRiskConsentSheet({
      state: this.riskConsentState,
      onAccept: () => {
        this.acceptRiskConsent();
      },
      onDecline: () => {
        this.declineRiskConsent();
      }
    })
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
    this.refreshThemeState();
    this.state = this.buildViewState(sharedAdBlockRepository.getSettings());
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  private loadAdBlockSettings(): void {
    sharedAdBlockRepository.initializeMetadata()
      .then(() => {
        this.refreshState();
      })
      .catch((_error: Error) => undefined);
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

  private requestEnabledChange(enabled: boolean): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      return;
    }
    if (!enabled) {
      this.updatePreference('enabled', enabled);
      return;
    }
    this.riskConsentState = this.riskConsentViewModel.buildState();
    this.pendingEnableAfterConsent = true;
    this.riskConsentVisible = true;
  }

  private acceptRiskConsent(): void {
    const shouldEnable = this.pendingEnableAfterConsent;
    this.pendingEnableAfterConsent = false;
    this.riskConsentVisible = false;
    if (shouldEnable) {
      this.updatePreference('enabled', true);
    }
  }

  private declineRiskConsent(): void {
    this.pendingEnableAfterConsent = false;
    this.riskConsentVisible = false;
    this.refreshState();
  }

  private handleRiskConsentDisappear(): void {
    this.pendingEnableAfterConsent = false;
    this.riskConsentVisible = false;
    this.refreshState();
  }

  private updatePreference(key: 'enabled', enabled: boolean): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      return;
    }
    const current = sharedAdBlockRepository.getSettings().preferences;
    const nextPreferences: AdBlockPreferences = this.viewModel.buildPreferencesPatch(current, key, enabled);
    const previousState = this.state;
    const currentSettings = sharedAdBlockRepository.getSettings();
    this.state = this.buildViewState({
      preferences: nextPreferences,
      siteExceptions: currentSettings.siteExceptions,
      customRuleSources: currentSettings.customRuleSources,
      stats: currentSettings.stats,
      lastRuleUpdateAt: currentSettings.lastRuleUpdateAt,
      engineUnavailableReason: currentSettings.engineUnavailableReason,
      updatedAt: currentSettings.updatedAt
    });
    this.settingsCoordinator.updatePreferences(nextPreferences, this.buildSettingsBoundary())
      .then((result: AdBlockSettingsMutationResult) => {
        if (!result.allowed) {
          this.state = previousState;
          return;
        }
        this.state = this.buildViewState(result.settings);
      })
      .catch((_error: Error) => {
        this.state = previousState;
      });
  }

  private clearStats(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      return;
    }
    this.settingsCoordinator.clearStats(this.buildSettingsBoundary())
      .then((result: AdBlockSettingsMutationResult) => {
        if (result.allowed) {
          this.state = this.buildViewState(result.settings);
        }
      })
      .catch((_error: Error) => {});
  }

  private confirmClearStats(): void {
    showCenteredAlertDialog({
      title: '清空拦截统计',
      message: '清空后不会影响网页内容过滤规则和站点例外。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.clearStats();
        }
      }
    });
  }

  private removeException(host: string): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      return;
    }
    this.settingsCoordinator.removeSiteException(host, this.buildSettingsBoundary())
      .then((result: AdBlockSettingsMutationResult) => {
        if (result.allowed) {
          this.state = this.buildViewState(result.settings);
        }
      })
      .catch((_error: Error) => {});
  }

  private openCustomRulesPage(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      return;
    }
    this.navigationCoordinator.openAdBlockCustomRules(this.buildBoundaryState());
  }

  private openManualElementHideSettingsPage(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      return;
    }
    this.navigationCoordinator.openManualElementHideSettings(this.buildBoundaryState());
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }

  private buildSettingsBoundary(): AdBlockSettingsBoundary {
    return new AdBlockSettingsBoundary(this.dataScope, this.privacyMode);
  }

  private buildViewState(settings: AdBlockSettings): AdBlockSettingsViewState {
    return this.viewModel.buildState(
      this.settingsCoordinator.projectSettingsForBoundary(settings, this.buildSettingsBoundary())
    );
  }
}
