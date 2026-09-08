import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  createCenteredDialogMaterial,
  showCenteredAlertDialog
} from '../components/common/CenteredDialogSurface';
import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  SettingsDetailActionButtonState,
  SettingsDetailRowAction,
  SettingsDetailRowState,
  SettingsDetailState,
  SettingsDetailViewModel
} from '../../core/settings/SettingsDetailViewModel';
import {
  SettingsRiskPromptState,
  SettingsRiskPromptViewModel
} from '../../core/settings/SettingsRiskPromptViewModel';
import { AppServiceModeConfirmationPrompt } from '../../core/settings/AppServiceModeConfirmationViewModel';
import {
  BrowserThemeMode,
  BrowserAppServiceMode,
  BrowserAppearanceSettings,
  BrowserGeneralSettings,
  BrowserExperimentSettings,
  BrowserRetentionSettings,
  DEFAULT_BROWSER_PROFILE_ID,
  ExternalNavigationAppOpenPolicy,
  SearchEngineId
} from '../../common/models/BrowserModels';
import { BrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import {
  sharedBrowserThemeModeCoordinator,
  sharedBookmarkRepository,
  sharedHistoryRepository,
  sharedOfflinePageRepository,
  sharedBrowserTabletInterfaceModeRepository,
  sharedPreferencesRepository,
  sharedRecentlyClosedTabRepository,
  sharedShortcutRepository,
  sharedSitePolicyService,
  sharedCustomHomepageRepository,
  sharedWallpaperRepository,
  sharedAdBlockRepository,
  sharedSearchEngineRepository,
  sharedSearchEngineSettingsCoordinator,
  sharedSecureDnsSettingsCoordinator,
  sharedSyncExperienceCoordinator
} from '../bootstrap/BrowserAppRuntime';
import { BrowserThemeModeBoundary } from '../../core/browser/BrowserThemeModeCoordinator';
import { SettingsSiteDataClearCoordinator } from '../../core/settings/SettingsSiteDataClearCoordinator';
import {
  SettingsBrowsingDataClearDialogState,
  SettingsBrowsingDataClearItemId,
  SettingsBrowsingDataClearTimeRangeId
} from '../../core/settings/SettingsSiteDataClearCoordinator';
import { SearchSettingsBoundary } from '../../core/search/SearchEngineSettingsCoordinator';
import {
  SettingsSitePolicyBoundary,
  SettingsSitePolicyCoordinator
} from '../../core/settings/SettingsSitePolicyCoordinator';
import { SettingsAboutCoordinator } from '../../core/settings/SettingsAboutCoordinator';
import { SettingsAboutOverviewState } from '../../core/settings/SettingsAboutOverviewViewModel';
import { SettingsGeneralCoordinator } from '../../core/settings/SettingsGeneralCoordinator';
import { SettingsSitePermissionsCoordinator } from '../../core/settings/SettingsSitePermissionsCoordinator';
import { SiteIconCacheMaintenanceCoordinator } from '../../core/settings/SiteIconCacheMaintenanceCoordinator';
import { AppServiceModeCoordinator } from '../../core/settings/AppServiceModeCoordinator';
import { BrowserExperimentSettingsRefreshSignal } from '../../core/settings/BrowserExperimentSettingsRefreshSignal';
import {
  SettingsDetailInteractionCallbackHandlers,
  SettingsDetailInteractionCoordinator,
  SettingsDetailInteractionHandlers
} from '../../core/settings/SettingsDetailInteractionCoordinator';
import { SettingsDetailStateBuilder } from '../../core/settings/SettingsDetailStateBuilder';
import { BrowserTabletInterfaceModeSettingsCoordinator } from '../../core/settings/BrowserTabletInterfaceModeSettingsCoordinator';
import { BrowserThemePaletteService } from '../../services/theme/BrowserThemePaletteService';
import { SystemSettingsLaunchService } from '../../services/system/SystemSettingsLaunchService';
import { AppModeSwitchRestartService } from '../../services/settings/AppModeSwitchRestartService';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { SettingsAboutOverviewContent } from '../components/settings/SettingsAboutOverviewContent';
import { SettingsDetailContent } from '../components/settings/SettingsDetailContent';
import { AlwaysPrivateModeConfirmationDialog } from '../components/settings/AlwaysPrivateModeConfirmationDialog';
import { ClearBrowsingDataDialog } from '../components/settings/ClearBrowsingDataDialog';
import { SupportQqGroupDialog } from '../components/settings/SupportQqGroupDialog';
import { SettingsScrollBody } from '../components/settings/SettingsLayout';
import {
  SettingsNavigationCoordinator
} from '../router/SettingsNavigationCoordinator';
import {
  SettingsDetailNavigationActionCallbackHandlers,
  SettingsDetailNavigationActionCoordinator,
  SettingsDetailNavigationActionHandlers
} from '../router/SettingsDetailNavigationActionCoordinator';

interface SettingsDetailPageParams {
  sectionId?: string;
  subpage?: string;
  settingsTargetId?: string;
  settingsRevealTargetId?: string;
  dataScope?: string;
  privacyMode?: string;
  boundarySource?: string;
}

const AIRA_SUPPORT_QQ_GROUP_NUMBER: string = '1049806927';

@Entry
@Component
struct SettingsDetailPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private viewModel: SettingsDetailViewModel = new SettingsDetailViewModel();
  private riskPromptViewModel: SettingsRiskPromptViewModel = new SettingsRiskPromptViewModel();
  private siteDataClearCoordinator: SettingsSiteDataClearCoordinator =
    new SettingsSiteDataClearCoordinator(
      sharedPreferencesRepository,
      sharedSitePolicyService,
      sharedRecentlyClosedTabRepository,
      sharedHistoryRepository
    );
  private sitePolicyCoordinator: SettingsSitePolicyCoordinator =
    new SettingsSitePolicyCoordinator(sharedPreferencesRepository);
  private aboutCoordinator: SettingsAboutCoordinator = new SettingsAboutCoordinator();
  private generalCoordinator: SettingsGeneralCoordinator =
    new SettingsGeneralCoordinator(sharedPreferencesRepository, sharedCustomHomepageRepository);
  private sitePermissionsCoordinator: SettingsSitePermissionsCoordinator =
    new SettingsSitePermissionsCoordinator(sharedPreferencesRepository, sharedSitePolicyService);
  private stateBuilder: SettingsDetailStateBuilder =
    new SettingsDetailStateBuilder(
      this.viewModel,
      this.sitePolicyCoordinator,
      this.generalCoordinator,
      this.aboutCoordinator,
      this.sitePermissionsCoordinator
    );
  private tabletInterfaceModeSettingsCoordinator: BrowserTabletInterfaceModeSettingsCoordinator =
    new BrowserTabletInterfaceModeSettingsCoordinator(sharedBrowserTabletInterfaceModeRepository);
  private siteIconCacheMaintenanceCoordinator: SiteIconCacheMaintenanceCoordinator =
    new SiteIconCacheMaintenanceCoordinator(
      sharedBookmarkRepository,
      sharedHistoryRepository,
      sharedShortcutRepository,
      sharedOfflinePageRepository
    );
  private appServiceModeCoordinator: AppServiceModeCoordinator =
    new AppServiceModeCoordinator(
      sharedPreferencesRepository,
      sharedSyncExperienceCoordinator,
      sharedWallpaperRepository,
      sharedAdBlockRepository
    );
  private experimentSettingsRefreshSignal: BrowserExperimentSettingsRefreshSignal =
    new BrowserExperimentSettingsRefreshSignal();
  private interactionCoordinator: SettingsDetailInteractionCoordinator =
    new SettingsDetailInteractionCoordinator(sharedPreferencesRepository);
  private themePaletteService: BrowserThemePaletteService = new BrowserThemePaletteService();
  private systemSettingsLaunchService: SystemSettingsLaunchService = new SystemSettingsLaunchService();
  private navigationActionCoordinator: SettingsDetailNavigationActionCoordinator =
    new SettingsDetailNavigationActionCoordinator(this.navigationCoordinator, this.systemSettingsLaunchService);
  private appModeSwitchRestartService: AppModeSwitchRestartService = new AppModeSwitchRestartService();
  private aboutOverviewScroller: Scroller = new Scroller();
  private detailScroller: Scroller = new Scroller();
  @State private state: SettingsDetailState = this.viewModel.buildState('general');
  @State private selectedThemeMode: BrowserThemeMode = sharedBrowserThemeModeCoordinator.resolveCurrentMode();
  @State private selectedExternalNavigationPolicy: ExternalNavigationAppOpenPolicy =
    sharedPreferencesRepository.getPreferences().externalNavigation.appOpenPolicy;
  @State private appearanceSettings: BrowserAppearanceSettings = sharedPreferencesRepository.getPreferences().appearance;
  @State private experimentSettings: BrowserExperimentSettings = sharedPreferencesRepository.getPreferences().experiments;
  @State private retentionSettings: BrowserRetentionSettings = sharedPreferencesRepository.getPreferences().retention;
  @State private settingsRenderVersion: number = 0;
  @State private sectionId: string = 'general';
  @State private subpage: string = '';
  @State private settingsTargetId: string = '';
  @State private settingsRevealTargetId: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private siteIconRefreshing: boolean = false;
  @State private effectiveThemeMode: BrowserThemeMode = 'light';
  @State private themedPageBackground: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private themedSurfaceBackground: string = '#FFFFFF';
  @State private themedAccentColor: string = '#0A59F7';
  @State private themedOnPrimaryColor: string = '#FFFFFF';
  @State private themedPressedBackgroundColor: string = '#DDE4EC';
  @State private themedTextPrimaryColor: string = '#111318';
  @State private themedTextSecondaryColor: string = '#5F6875';
  @State private clearBrowsingDataDialogState: SettingsBrowsingDataClearDialogState =
    this.siteDataClearCoordinator.buildDialogState({});
  @State private clearBrowsingDataTimeRangeId: SettingsBrowsingDataClearTimeRangeId = 'all';
  @State private clearBrowsingDataSelectedItemIds: SettingsBrowsingDataClearItemId[] =
    this.buildDefaultClearBrowsingDataItemIds(this.clearBrowsingDataDialogState);
  @State private alwaysPrivateConfirmationAccepted: boolean = false;
  @State private aboutOverviewState: SettingsAboutOverviewState = {
    appTitle: 'Aira',
    versionTitle: '当前版本',
    versionText: '',
    moreButtonTitle: '查看更多'
  };
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) @Watch('handleStoredThemeChanged')
  private storedResolvedThemeMode: string = 'light';
  private clearBrowsingDataDialogController: CustomDialogController = new CustomDialogController({
    builder: ClearBrowsingDataDialog({
      dialogState: $clearBrowsingDataDialogState,
      selectedTimeRangeId: $clearBrowsingDataTimeRangeId,
      selectedItemIds: $clearBrowsingDataSelectedItemIds,
      confirm: () => {
        void this.clearSelectedBrowsingData();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
  });
  private supportQqGroupDialogController: CustomDialogController = new CustomDialogController({
    builder: SupportQqGroupDialog({
      groupNumber: AIRA_SUPPORT_QQ_GROUP_NUMBER,
      copyGroupNumber: () => {
        void this.copySupportQqGroupNumber();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
  });
  private alwaysPrivateConfirmationDialogController: CustomDialogController = new CustomDialogController({
    builder: AlwaysPrivateModeConfirmationDialog({
      accepted: $alwaysPrivateConfirmationAccepted,
      onCancel: () => {
        this.alwaysPrivateConfirmationAccepted = false;
        this.refreshState();
      },
      onConfirm: () => {
        this.alwaysPrivateConfirmationAccepted = false;
        void this.applyAlwaysUsePrivateModeEnabledConfirmed(true);
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
  });

  aboutToAppear(): void {
    this.syncRouteState();
    this.refreshState();
  }

  onPageShow(): void {
    this.refreshState();
  }

  build() {
    Column() {
      ForEach([this.resolvePageRenderKey()], (_renderKey: string) => {
        SettingsHdsScaffold({
          title: this.state.title,
          backIconKind: 'back',
          pageBackground: this.themedPageBackground,
          headerButtonBackground: this.resolveHeaderButtonBackground(),
          primaryTextColor: this.themedTextPrimaryColor,
          dividerColor: this.storedDividerColor,
          showPrivateIndicator: this.isPrivateContext(),
          scrollers: this.resolveScaffoldScrollers(),
          onBack: () => {
            this.navigationCoordinator.back();
          }
        }) {
          if (this.shouldShowAboutOverview()) {
            SettingsAboutOverviewContent({
              state: this.aboutOverviewState,
              surfaceBackground: this.themedSurfaceBackground,
              accentColor: this.themedAccentColor,
              pressedBackground: this.themedPressedBackgroundColor,
              scroller: this.aboutOverviewScroller,
              onOpenChangelog: () => {
                this.openAboutChangelog();
              },
              onShowMore: () => {
                this.showAboutDetails();
              }
            })
          } else {
            SettingsScrollBody({
              bottomPadding: 28,
              scroller: this.detailScroller
            }) {
              SettingsDetailContent({
                state: this.state,
                surfaceBackground: this.themedSurfaceBackground,
                dividerColor: this.storedDividerColor,
                accentColor: this.themedAccentColor,
                onAccentColor: this.themedOnPrimaryColor,
                pressedBackground: this.themedPressedBackgroundColor,
                primaryTextColor: this.themedTextPrimaryColor,
                secondaryTextColor: this.themedTextSecondaryColor,
                renderVersion: this.settingsRenderVersion,
                themeRenderKey: this.resolveThemeRenderKey(),
                dataScope: this.dataScope,
                privacyMode: this.privacyMode,
                revealTargetId: this.settingsRevealTargetId,
                revealRevision: this.settingsRevealTargetId.length > 0 ? 1 : 0,
                scroller: this.detailScroller,
                onRowAction: (row: SettingsDetailRowState, nextChecked?: boolean) => {
                  this.handleRowAction(row, nextChecked);
                },
                onActionButton: (button: SettingsDetailActionButtonState) => {
                  this.handleActionButton(button);
                },
                onTabOverviewLayoutApplied: () => {
                  this.refreshState();
                },
                onOpenJavaScriptExceptions: (): void => {
                  this.navigationCoordinator.openSiteControlsCustomizationCapability(
                    'javascript',
                    DEFAULT_BROWSER_PROFILE_ID,
                    {
                      dataScope: this.dataScope,
                      privacyMode: this.privacyMode,
                      boundarySource: 'privacy_security'
                    },
                    'JavaScript'
                  );
                }
              })
            }
          }
        }
      }, (renderKey: string) => renderKey)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themedPageBackground)
  }

  private isPrivateContext(): boolean {
    return this.dataScope === 'session_ephemeral' || this.privacyMode === 'private';
  }

  private resolveHeaderButtonBackground(): ResourceColor {
    return this.themedPressedBackgroundColor.length > 0 ?
      this.themedPressedBackgroundColor :
      this.storedPressedBackgroundColor;
  }

  private shouldShowAboutOverview(): boolean {
    return this.state.id === 'about' && this.subpage !== 'details';
  }

  private resolveScaffoldScrollers(): Scroller[] {
    return this.shouldShowAboutOverview() ? [this.aboutOverviewScroller] : [this.detailScroller];
  }

  private openAboutChangelog(): void {
    this.navigationCoordinator.openChangelog(this.buildForwardRouteParams());
  }

  private showAboutDetails(): void {
    this.navigationCoordinator.openSettingsDetailSubpage('about', 'details', this.buildForwardRouteParams());
  }

  private syncRouteState(): void {
    const params = router.getParams() as SettingsDetailPageParams | undefined;
    this.sectionId = params?.sectionId ?? this.sectionId;
    this.subpage = params?.subpage ?? '';
    this.settingsTargetId = params?.settingsTargetId ?? '';
    this.settingsRevealTargetId = params?.settingsRevealTargetId ?? '';
    this.dataScope = params?.dataScope ?? this.dataScope;
    this.privacyMode = params?.privacyMode ?? this.privacyMode;
    this.boundarySource = params?.boundarySource ?? this.boundarySource;
  }

  private refreshState(): void {
    this.syncLocalSettingsFromPreferences();
    this.refreshStateWithExternalNavigationPolicy(
      sharedPreferencesRepository.getPreferences().externalNavigation.appOpenPolicy
    );
    this.settingsRenderVersion += 1;
  }

  private syncLocalSettingsFromPreferences(): void {
    this.appearanceSettings = sharedPreferencesRepository.getPreferences().appearance;
    this.experimentSettings = sharedPreferencesRepository.getPreferences().experiments;
    this.retentionSettings = sharedPreferencesRepository.getPreferences().retention;
    this.refreshThemeTokens();
  }

  private refreshThemeTokens(): void {
    const preferences = sharedPreferencesRepository.getPreferences();
    const effectiveMode = sharedBrowserThemeModeCoordinator.resolveEffectiveMode(preferences.themeMode);
    const tokens = this.themePaletteService.resolveTokens(
      preferences.appearance.themePaletteId,
      effectiveMode
    );
    this.effectiveThemeMode = effectiveMode;
    this.themedPageBackground = tokens.pageBackground;
    this.themedSurfaceBackground = tokens.surfaceBackground;
    this.themedAccentColor = tokens.accent;
    this.themedOnPrimaryColor = tokens.onPrimary;
    this.themedPressedBackgroundColor = tokens.pressedBackground;
    this.themedTextPrimaryColor = tokens.textPrimary;
    this.themedTextSecondaryColor = tokens.textSecondary;
  }

  private handleStoredThemeChanged(): void {
    this.refreshThemeTokens();
  }

  private resolvePageRenderKey(): string {
    return `${this.state.id}:${this.subpage}:${this.settingsTargetId}:${this.settingsRevealTargetId}:` +
      `${this.storedResolvedThemeMode}:${this.resolveThemeRenderKey()}`;
  }

  private resolveThemeRenderKey(): string {
    return `${this.effectiveThemeMode}:${this.themedPageBackground}:${this.themedSurfaceBackground}:` +
      `${this.themedAccentColor}:${this.themedOnPrimaryColor}:${this.themedPressedBackgroundColor}:` +
      `${this.themedTextPrimaryColor}:${this.themedTextSecondaryColor}:${this.storedDividerColor}`;
  }

  private rebuildStateFromLocalSettings(): void {
    this.refreshStateWithExternalNavigationPolicy(this.selectedExternalNavigationPolicy);
  }

  private refreshStateWithExternalNavigationPolicy(
    externalNavigationPolicy: ExternalNavigationAppOpenPolicy,
    appServiceModeOverride?: BrowserAppServiceMode
  ): void {
    this.selectedThemeMode = sharedBrowserThemeModeCoordinator.resolveCurrentMode();
    this.selectedExternalNavigationPolicy = externalNavigationPolicy;
    const tabletInterfaceModeState = this.tabletInterfaceModeSettingsCoordinator.buildState();
    const result = this.stateBuilder.build({
      destinationId: this.sectionId,
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      themeMode: this.selectedThemeMode,
      searchEngineId: sharedSearchEngineSettingsCoordinator.getDefaultEngineId(),
      externalNavigationPolicy: externalNavigationPolicy,
      appearanceSettings: this.appearanceSettings,
      experimentSettings: this.experimentSettings,
      retentionSettings: this.retentionSettings,
      siteIconRefreshing: this.siteIconRefreshing,
      appServiceMode: appServiceModeOverride ?? sharedPreferencesRepository.getPreferences().appServiceMode,
      tabletInterfaceModeVisible: tabletInterfaceModeState.visible,
      tabletInterfaceModeLabel: tabletInterfaceModeState.selectedLabel,
      secureDnsSummaryLabel: sharedSecureDnsSettingsCoordinator.getSummaryLabel(),
      adBlockEnabled: sharedAdBlockRepository.getSettings().preferences.enabled
    });
    this.aboutOverviewState = result.aboutOverviewState;
    this.state = result.detailState;
  }

  private handleRowAction(row: SettingsDetailRowState, nextChecked?: boolean): void {
    this.interactionCoordinator.handleRowAction(row, nextChecked, this.buildInteractionHandlers());
  }

  private getAbilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async copySupportQqGroupNumber(): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, AIRA_SUPPORT_QQ_GROUP_NUMBER);
      await pasteboard.getSystemPasteboard().setData(data);
      this.showToast('已复制QQ群号');
    } catch (_error) {
      this.showToast('QQ群号复制失败，请稍后再试。');
    }
  }

  private handleActionButton(button: SettingsDetailActionButtonState): void {
    this.interactionCoordinator.handleActionButton(button, this.buildInteractionHandlers());
  }

  private buildInteractionHandlers(): SettingsDetailInteractionHandlers {
    return new SettingsDetailInteractionCallbackHandlers(
      (action: SettingsDetailRowAction): boolean => {
        return this.navigationActionCoordinator.handle(action, this.buildNavigationActionHandlers());
      },
      (): BrowserAppearanceSettings => this.appearanceSettings,
      (): BrowserExperimentSettings => this.experimentSettings,
      (): BrowserAppServiceMode => sharedPreferencesRepository.getPreferences().appServiceMode,
      (mode: BrowserThemeMode): void => {
        void this.applyThemeMode(mode);
      },
      (searchEngineId: SearchEngineId): void => {
        void this.applySearchEngine(searchEngineId);
      },
      (mode: BrowserAppServiceMode): void => {
        void this.applyAppServiceMode(mode);
      },
      (enabled: boolean): void => {
        void this.applyPrivateModeAuthenticationEnabled(enabled);
      },
      (enabled: boolean): void => {
        void this.applyAlwaysUsePrivateModeEnabled(enabled);
      },
      (enabled: boolean): void => {
        void this.applyPrivateModePreserveCookiesOnClose(enabled);
      },
      (settings: BrowserAppearanceSettings): void => {
        void this.applyAppearanceSettings(settings);
      },
      (
        action: SettingsDetailRowAction,
        targetChecked: boolean,
        settings: BrowserExperimentSettings
      ): void => {
        void this.applyExperimentSettingsWithRiskPrompt(action, targetChecked, settings);
      },
      (): void => {
        this.confirmClearAllSiteData();
      },
      (): void => {
        this.confirmResetSitePermissions();
      },
      (): void => {
        this.confirmRefreshSiteIcons();
      },
      (prompt: SettingsRiskPromptState, onConfirm: () => void): void => {
        this.showRiskPrompt(prompt, onConfirm);
      },
      (prompt: AppServiceModeConfirmationPrompt, onConfirm: () => void): void => {
        this.showAppServiceModeConfirmation(prompt, onConfirm);
      }
    );
  }

  private buildNavigationActionHandlers(): SettingsDetailNavigationActionHandlers {
    return new SettingsDetailNavigationActionCallbackHandlers(
      (): BrowserBoundaryRouteState => this.buildForwardRouteParams(),
      (): common.UIAbilityContext => this.getAbilityContext(),
      (message: string): void => {
        this.showToast(message);
      },
      (): void => {
        this.supportQqGroupDialogController.open();
      },
      (): void => {
        this.confirmClearAllSiteData();
      },
      (): void => {
        this.confirmResetSitePermissions();
      },
      (): void => {
        this.confirmRefreshSiteIcons();
      }
    );
  }

  private async applyThemeMode(themeMode: BrowserThemeMode): Promise<void> {
    const previousThemeMode = this.selectedThemeMode;
    this.selectedThemeMode = themeMode;
    try {
      const result = await sharedBrowserThemeModeCoordinator.setThemeModeForBoundary(
        themeMode,
        this.buildThemeModeBoundary()
      );
      this.selectedThemeMode = result.mode;
      this.refreshState();
      this.showToast(result.message);
    } catch (_error) {
      this.selectedThemeMode = previousThemeMode;
      this.refreshState();
      this.showToast('外观模式更新失败。');
    }
  }

  private async applySearchEngine(searchEngineId: SearchEngineId): Promise<void> {
    try {
      await sharedSearchEngineSettingsCoordinator.setDefaultEngine(searchEngineId, this.buildSearchBoundary());
      this.refreshState();
      this.showToast('搜索引擎已更新。');
    } catch (_error) {
      this.showToast('搜索引擎更新失败。');
    }
  }

  private async applyAppearanceSettings(nextSettings: BrowserAppearanceSettings): Promise<void> {
    const previousSettings = this.appearanceSettings;
    this.appearanceSettings = nextSettings;
    this.refreshStateWithExternalNavigationPolicy(this.selectedExternalNavigationPolicy);
    try {
      const appearance = await this.interactionCoordinator.commitAppearanceSettings({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      }, nextSettings);
      this.appearanceSettings = appearance;
      this.refreshStateWithExternalNavigationPolicy(this.selectedExternalNavigationPolicy);
    } catch (_error) {
      this.appearanceSettings = previousSettings;
      this.refreshStateWithExternalNavigationPolicy(this.selectedExternalNavigationPolicy);
      this.showToast('外观设置更新失败。');
    }
  }

  private async applyAppServiceMode(mode: BrowserAppServiceMode): Promise<void> {
    try {
      this.settingsRenderVersion += 1;
      this.refreshStateWithExternalNavigationPolicy(this.selectedExternalNavigationPolicy, mode);
      const result = await this.appServiceModeCoordinator.applyMode(mode, {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      });
      this.syncLocalSettingsFromPreferences();
      this.settingsRenderVersion += 1;
      this.refreshState();
      this.showToast(result.message);
      this.appModeSwitchRestartService.scheduleRestartForModeSwitch();
    } catch (_error) {
      this.settingsRenderVersion += 1;
      this.refreshState();
      this.showToast('应用服务模式更新失败。');
    }
  }

  private async applyPrivateModeAuthenticationEnabled(enabled: boolean): Promise<void> {
    const previousSettings = sharedPreferencesRepository.getPreferences().general;
    const nextSettings: BrowserGeneralSettings = {
      startupRestorePolicy: previousSettings.startupRestorePolicy,
      tabAutoClosePolicy: previousSettings.tabAutoClosePolicy,
      privateTabRestorePolicy: previousSettings.privateTabRestorePolicy,
      privateModeAuthenticationEnabled: enabled,
      alwaysUsePrivateMode: previousSettings.alwaysUsePrivateMode === true,
      privateModePreserveCookiesOnClose: previousSettings.privateModePreserveCookiesOnClose,
      privateModeThemeEnabled: previousSettings.privateModeThemeEnabled
    };
    try {
      await this.interactionCoordinator.commitGeneralSettings({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      }, nextSettings);
      this.refreshState();
      this.showToast(nextSettings.privateModeAuthenticationEnabled ? '隐私模式验证已开启。' : '隐私模式验证已关闭。');
    } catch (_error) {
      this.refreshState();
      this.showToast('隐私模式验证设置更新失败。');
    }
  }

  private applyAlwaysUsePrivateModeEnabled(enabled: boolean): void {
    const currentEnabled = sharedPreferencesRepository.getPreferences().general.alwaysUsePrivateMode === true;
    if (currentEnabled === enabled) {
      return;
    }
    if (enabled) {
      this.alwaysPrivateConfirmationAccepted = false;
      this.alwaysPrivateConfirmationDialogController.open();
      return;
    }
    void this.applyAlwaysUsePrivateModeEnabledConfirmed(false);
  }

  private async applyAlwaysUsePrivateModeEnabledConfirmed(enabled: boolean): Promise<void> {
    const previousSettings = sharedPreferencesRepository.getPreferences().general;
    const nextSettings: BrowserGeneralSettings = {
      startupRestorePolicy: previousSettings.startupRestorePolicy,
      tabAutoClosePolicy: previousSettings.tabAutoClosePolicy,
      privateTabRestorePolicy: previousSettings.privateTabRestorePolicy,
      privateModeAuthenticationEnabled: previousSettings.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: enabled,
      privateModePreserveCookiesOnClose: previousSettings.privateModePreserveCookiesOnClose,
      privateModeThemeEnabled: previousSettings.privateModeThemeEnabled
    };
    try {
      await this.interactionCoordinator.commitGeneralSettings({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      }, nextSettings);
      this.refreshState();
      this.showToast(nextSettings.alwaysUsePrivateMode === true ? '重启后将默认进入隐私模式。' : '已关闭始终保持隐私模式。');
    } catch (_error) {
      this.refreshState();
      this.showToast('始终保持隐私模式设置更新失败。');
    }
  }

  private async applyPrivateModePreserveCookiesOnClose(enabled: boolean): Promise<void> {
    const previousSettings = sharedPreferencesRepository.getPreferences().general;
    const nextSettings: BrowserGeneralSettings = {
      startupRestorePolicy: previousSettings.startupRestorePolicy,
      tabAutoClosePolicy: previousSettings.tabAutoClosePolicy,
      privateTabRestorePolicy: previousSettings.privateTabRestorePolicy,
      privateModeAuthenticationEnabled: previousSettings.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: previousSettings.alwaysUsePrivateMode === true,
      privateModePreserveCookiesOnClose: enabled,
      privateModeThemeEnabled: previousSettings.privateModeThemeEnabled
    };
    try {
      await this.interactionCoordinator.commitGeneralSettings({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      }, nextSettings);
      this.refreshState();
      this.showToast(nextSettings.privateModePreserveCookiesOnClose ? '隐私模式会保留 Cookie。' : '隐私模式会清除 Cookie。');
    } catch (_error) {
      this.refreshState();
      this.showToast('隐私模式 Cookie 设置更新失败。');
    }
  }

  private async applyExperimentSettingsWithRiskPrompt(
    action: SettingsDetailRowAction,
    targetChecked: boolean,
    nextExperimentSettings: BrowserExperimentSettings
  ): Promise<void> {
    this.applyOptimisticExperimentSettings(nextExperimentSettings);
    const prompt = this.riskPromptViewModel.buildPrompt(action, targetChecked);
    if (prompt !== undefined) {
      this.showRiskPrompt(prompt, () => {
        this.applyExperimentSettings(nextExperimentSettings);
      });
    } else {
      this.applyExperimentSettings(nextExperimentSettings);
    }
  }

  private applyOptimisticExperimentSettings(nextExperimentSettings: BrowserExperimentSettings): void {
    this.experimentSettings = nextExperimentSettings;
    this.settingsRenderVersion += 1;
    this.rebuildStateFromLocalSettings();
  }

  private applyExperimentSettings(nextExperimentSettings: BrowserExperimentSettings): void {
    const previousSettings = this.experimentSettings;
    this.experimentSettings = nextExperimentSettings;
    this.rebuildStateFromLocalSettings();
    this.interactionCoordinator.commitExperimentSettings({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    }, nextExperimentSettings)
      .then((settings: BrowserExperimentSettings) => {
        this.experimentSettings = settings;
        this.rebuildStateFromLocalSettings();
        this.experimentSettingsRefreshSignal.bump();
        this.showToast(this.viewModel.buildExperimentUpdateToast(previousSettings, settings));
      })
      .catch((_error: Error) => {
        this.experimentSettings = previousSettings;
        this.rebuildStateFromLocalSettings();
        this.showToast('实验室设置更新失败。');
      });
  }

  private confirmClearAllSiteData(): void {
    const clearState = this.siteDataClearCoordinator.buildDialogState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    });
    this.clearBrowsingDataDialogState = clearState;
    this.clearBrowsingDataTimeRangeId = clearState.defaultTimeRangeId;
    this.clearBrowsingDataSelectedItemIds = this.buildDefaultClearBrowsingDataItemIds(clearState);
    this.clearBrowsingDataDialogController.open();
  }

  private async clearSelectedBrowsingData(): Promise<void> {
    const result = await this.siteDataClearCoordinator.clearSelected({
      rangeId: this.clearBrowsingDataTimeRangeId,
      selectedItemIds: this.clearBrowsingDataSelectedItemIds,
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    });
    this.showToast(result.message);
    this.refreshState();
  }

  private buildDefaultClearBrowsingDataItemIds(
    state: SettingsBrowsingDataClearDialogState
  ): SettingsBrowsingDataClearItemId[] {
    return state.items
      .filter((item) => item.isEnabled && item.defaultSelected)
      .map((item) => item.id);
  }

  private confirmResetSitePermissions(): void {
    const resetState = this.sitePermissionsCoordinator.buildResetState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    });
    showCenteredAlertDialog({
      title: resetState.title,
      message: resetState.message,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: resetState.confirmLabel,
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          if (!resetState.canResetPermissions) {
            return;
          }
          void this.resetSitePermissions();
        }
      }
    });
  }

  private async resetSitePermissions(): Promise<void> {
    const result = await this.sitePermissionsCoordinator.resetAll({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    });
    this.showToast(result.message);
    this.refreshState();
  }

  private confirmRefreshSiteIcons(): void {
    showCenteredAlertDialog({
      title: '刷新网站图标？',
      message: '会保留当前图标，并在后台重新获取高清图标。获取失败的网站会继续显示文字图标或旧图标。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '开始刷新',
        action: () => {
          void this.refreshSiteIcons();
        }
      }
    });
  }

  private async refreshSiteIcons(): Promise<void> {
    if (this.siteIconRefreshing) {
      return;
    }
    this.siteIconRefreshing = true;
    this.refreshState();
    this.showToast('正在刷新网站图标...');
    try {
      const result = await this.siteIconCacheMaintenanceCoordinator.refreshKnownSiteIcons();
      this.showToast(result.message);
    } catch (_error) {
      this.showToast('网站图标刷新失败，请稍后再试。');
    } finally {
      this.siteIconRefreshing = false;
      this.refreshState();
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_error) {
    }
  }

  private showRiskPrompt(prompt: SettingsRiskPromptState, onConfirm: () => void): void {
    showCenteredAlertDialog({
      title: prompt.title,
      message: prompt.message,
      autoCancel: true,
      primaryButton: {
        value: prompt.cancelLabel,
        action: () => {
          this.refreshState();
        }
      },
      secondaryButton: {
        value: prompt.confirmLabel,
        fontColor: prompt.confirmIsDestructive ? $r('app.color.permission_blocked') : this.themedAccentColor,
        action: () => {
          onConfirm();
        }
      }
    });
  }

  private showAppServiceModeConfirmation(prompt: AppServiceModeConfirmationPrompt, onConfirm: () => void): void {
    showCenteredAlertDialog({
      title: prompt.title,
      message: prompt.message,
      autoCancel: true,
      primaryButton: {
        value: prompt.cancelLabel,
        action: () => {
          this.refreshState();
        }
      },
      secondaryButton: {
        value: prompt.confirmLabel,
        fontColor: prompt.confirmIsDestructive ? $r('app.color.permission_blocked') : this.themedAccentColor,
        action: () => {
          onConfirm();
        }
      }
    });
  }

  private buildForwardRouteParams(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }

  private buildSearchBoundary(): SearchSettingsBoundary {
    return new SearchSettingsBoundary(this.dataScope, this.privacyMode);
  }

  private buildSitePolicyBoundary(): SettingsSitePolicyBoundary {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private buildThemeModeBoundary(): BrowserThemeModeBoundary {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

}
