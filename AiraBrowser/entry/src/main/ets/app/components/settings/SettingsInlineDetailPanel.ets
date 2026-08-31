import { common } from '@kit.AbilityKit';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  BrowserAppServiceMode,
  BrowserAppearanceSettings,
  BrowserExperimentSettings,
  BrowserGeneralSettings,
  BrowserPrivateTabRestorePolicy,
  BrowserRetentionProfileId,
  BrowserRetentionSettings,
  BrowserStartupRestorePolicy,
  BrowserTabAutoClosePolicy,
  BrowserThemeMode,
  DEFAULT_BROWSER_PROFILE_ID,
  ExternalNavigationAppOpenPolicy,
  HistoryRetentionSettings,
  SearchEngineId,
  SitePermissionKind,
  SitePermissionRule
} from '../../../common/models/BrowserModels';
import { BrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import { BrowserThemeModeBoundary } from '../../../core/browser/BrowserThemeModeCoordinator';
import {
  SettingsCenterDestination
} from '../../../core/settings/SettingsCenterViewModel';
import {
  SettingsDetailActionButtonState,
  SettingsDetailRowAction,
  SettingsDetailRowState,
  SettingsDetailState,
  SettingsDetailViewModel,
  SettingsSingleChoiceSelectionSnapshot
} from '../../../core/settings/SettingsDetailViewModel';
import { BrowserRetentionSettingsCoordinator } from '../../../core/settings/BrowserRetentionSettingsCoordinator';
import { HistoryFeature, HistoryManagementBoundary } from '../../../features/history/HistoryFeature';
import { SettingsGeneralCoordinator } from '../../../core/settings/SettingsGeneralCoordinator';
import { SettingsAboutCoordinator } from '../../../core/settings/SettingsAboutCoordinator';
import {
  SettingsRiskPromptState,
  SettingsRiskPromptViewModel
} from '../../../core/settings/SettingsRiskPromptViewModel';
import { AppServiceModeConfirmationPrompt } from '../../../core/settings/AppServiceModeConfirmationViewModel';
import { SearchSettingsBoundary } from '../../../core/search/SearchEngineSettingsCoordinator';
import { SettingsSiteDataClearCoordinator } from '../../../core/settings/SettingsSiteDataClearCoordinator';
import {
  SettingsBrowsingDataClearDialogState,
  SettingsBrowsingDataClearItemId,
  SettingsBrowsingDataClearTimeRangeId
} from '../../../core/settings/SettingsSiteDataClearCoordinator';
import { SettingsSitePermissionsCoordinator } from '../../../core/settings/SettingsSitePermissionsCoordinator';
import {
  SettingsSitePolicyBoundary,
  SettingsSitePolicyCoordinator
} from '../../../core/settings/SettingsSitePolicyCoordinator';
import { SiteIconCacheMaintenanceCoordinator } from '../../../core/settings/SiteIconCacheMaintenanceCoordinator';
import { AppServiceModeCoordinator } from '../../../core/settings/AppServiceModeCoordinator';
import { BrowserExperimentSettingsRefreshSignal } from '../../../core/settings/BrowserExperimentSettingsRefreshSignal';
import {
  SettingsDetailInteractionCallbackHandlers,
  SettingsDetailInteractionCoordinator,
  SettingsDetailInteractionHandlers
} from '../../../core/settings/SettingsDetailInteractionCoordinator';
import { SettingsDetailStateBuilder } from '../../../core/settings/SettingsDetailStateBuilder';
import { BrowserTabletInterfaceModeSettingsCoordinator } from '../../../core/settings/BrowserTabletInterfaceModeSettingsCoordinator';
import {
  sharedBookmarkRepository,
  sharedBrowserThemeModeCoordinator,
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
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  SettingsDetailNavigationActionCallbackHandlers,
  SettingsDetailNavigationActionCoordinator,
  SettingsDetailNavigationActionHandlers
} from '../../router/SettingsDetailNavigationActionCoordinator';
import { SystemSettingsLaunchService } from '../../../services/system/SystemSettingsLaunchService';
import { AppModeSwitchRestartService } from '../../../services/settings/AppModeSwitchRestartService';
import { AlwaysPrivateModeConfirmationDialog } from './AlwaysPrivateModeConfirmationDialog';
import { ClearBrowsingDataDialog } from './ClearBrowsingDataDialog';
import { SettingsDetailContent } from './SettingsDetailContent';
import { SupportQqGroupDialog } from './SupportQqGroupDialog';

const AIRA_SUPPORT_QQ_GROUP_NUMBER: string = '1049806927';

@Component
export struct SettingsInlineDetailPanel {
  private viewModel: SettingsDetailViewModel = new SettingsDetailViewModel();
  private riskPromptViewModel: SettingsRiskPromptViewModel = new SettingsRiskPromptViewModel();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private sitePolicyCoordinator: SettingsSitePolicyCoordinator =
    new SettingsSitePolicyCoordinator(sharedPreferencesRepository);
  private generalCoordinator: SettingsGeneralCoordinator =
    new SettingsGeneralCoordinator(sharedPreferencesRepository, sharedCustomHomepageRepository);
  private aboutCoordinator: SettingsAboutCoordinator = new SettingsAboutCoordinator();
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
  private siteDataClearCoordinator: SettingsSiteDataClearCoordinator =
    new SettingsSiteDataClearCoordinator(
      sharedPreferencesRepository,
      sharedSitePolicyService,
      sharedRecentlyClosedTabRepository,
      sharedHistoryRepository
    );
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
  private systemSettingsLaunchService: SystemSettingsLaunchService = new SystemSettingsLaunchService();
  private navigationActionCoordinator: SettingsDetailNavigationActionCoordinator =
    new SettingsDetailNavigationActionCoordinator(this.navigationCoordinator, this.systemSettingsLaunchService);
  private appModeSwitchRestartService: AppModeSwitchRestartService = new AppModeSwitchRestartService();
  private retentionSettingsCoordinator: BrowserRetentionSettingsCoordinator =
    new BrowserRetentionSettingsCoordinator(sharedPreferencesRepository);
  private historyFeature: HistoryFeature =
    new HistoryFeature(sharedHistoryRepository, sharedPreferencesRepository, sharedRecentlyClosedTabRepository);
  @Prop
  @Watch('refreshState')
  shellFamily: 'phone' | 'large_screen' = 'phone';
  @Prop
  @Watch('refreshState')
  selectedDestination: SettingsCenterDestination = 'general';
  @Prop
  @Watch('refreshState')
  dataScope: string = '';
  @Prop
  @Watch('refreshState')
  privacyMode: string = '';
  @Prop boundarySource: string = '';
  @Prop surfaceBackground: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop onAccentColor: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop revealTargetId: string = '';
  @Prop revealRevision: number = 0;
  scroller?: Scroller;
  onOpenAppProxySettings?: () => void;
  onOpenEmbeddedSubpage?: (subpageId: string) => void;
  onSettingsChanged?: () => void;
  @State private state: SettingsDetailState = this.viewModel.buildState('general');
  @State private selectedThemeMode: BrowserThemeMode = sharedBrowserThemeModeCoordinator.resolveCurrentMode();
  @State private selectedExternalNavigationPolicy: ExternalNavigationAppOpenPolicy =
    sharedPreferencesRepository.getPreferences().externalNavigation.appOpenPolicy;
  @State private appearanceSettings: BrowserAppearanceSettings = sharedPreferencesRepository.getPreferences().appearance;
  @State private experimentSettings: BrowserExperimentSettings = sharedPreferencesRepository.getPreferences().experiments;
  @State private retentionSettings: BrowserRetentionSettings = sharedPreferencesRepository.getPreferences().retention;
  @State private settingsRenderVersion: number = 0;
  @State private siteIconRefreshing: boolean = false;
  @State private clearBrowsingDataDialogState: SettingsBrowsingDataClearDialogState =
    this.siteDataClearCoordinator.buildDialogState({});
  @State private clearBrowsingDataTimeRangeId: SettingsBrowsingDataClearTimeRangeId = 'all';
  @State private clearBrowsingDataSelectedItemIds: SettingsBrowsingDataClearItemId[] =
    this.buildDefaultClearBrowsingDataItemIds(this.clearBrowsingDataDialogState);
  @State private alwaysPrivateConfirmationAccepted: boolean = false;
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
    customStyle: true
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
    customStyle: true
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
    customStyle: true
  });

  aboutToAppear(): void {
    this.refreshState();
  }

  build() {
    SettingsDetailContent({
      state: this.state,
      surfaceBackground: this.surfaceBackground,
      dividerColor: this.dividerColor,
      accentColor: this.accentColor,
      onAccentColor: this.onAccentColor,
      pressedBackground: this.pressedBackground,
      primaryTextColor: this.primaryTextColor,
      secondaryTextColor: this.secondaryTextColor,
      renderVersion: this.settingsRenderVersion,
      themeRenderKey: this.resolveThemeRenderKey(),
      isLargeScreen: this.shellFamily === 'large_screen',
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      revealTargetId: this.revealTargetId,
      revealRevision: this.revealRevision,
      scroller: this.scroller,
      onRowAction: (row: SettingsDetailRowState, nextChecked?: boolean) => {
        this.handleRowAction(row, nextChecked);
      },
      onDropdownSelect: (row: SettingsDetailRowState, optionId: string) => {
        this.handleDropdownSelection(row, optionId);
      },
      onActionButton: (button: SettingsDetailActionButtonState) => {
        this.handleActionButton(button);
      },
      onTabOverviewLayoutApplied: () => {
        this.refreshState();
        this.onSettingsChanged?.();
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

  private refreshState(): void {
    this.syncLocalSettingsFromPreferences();
    this.rebuildStateFromLocalSettings();
    this.settingsRenderVersion += 1;
  }

  private resolveThemeRenderKey(): string {
    return `${this.surfaceBackground}:${this.dividerColor}:${this.accentColor}:${this.onAccentColor}:` +
      `${this.pressedBackground}:${this.primaryTextColor}:${this.secondaryTextColor}`;
  }

  private syncLocalSettingsFromPreferences(): void {
    const preferences = sharedPreferencesRepository.getPreferences();
    this.selectedThemeMode = sharedBrowserThemeModeCoordinator.resolveCurrentMode();
    this.selectedExternalNavigationPolicy = preferences.externalNavigation.appOpenPolicy;
    this.appearanceSettings = preferences.appearance;
    this.experimentSettings = preferences.experiments;
    this.retentionSettings = preferences.retention;
  }

  private rebuildStateFromLocalSettings(appServiceModeOverride?: BrowserAppServiceMode): void {
    const tabletInterfaceModeState = this.tabletInterfaceModeSettingsCoordinator.buildState();
    const result = this.stateBuilder.build({
      destinationId: this.selectedDestination,
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      themeMode: this.selectedThemeMode,
      searchEngineId: sharedSearchEngineSettingsCoordinator.getDefaultEngineId(),
      externalNavigationPolicy: this.selectedExternalNavigationPolicy,
      appearanceSettings: this.appearanceSettings,
      experimentSettings: this.experimentSettings,
      retentionSettings: this.retentionSettings,
      siteIconRefreshing: this.siteIconRefreshing,
      appServiceMode: appServiceModeOverride ?? sharedPreferencesRepository.getPreferences().appServiceMode,
      hideTopSafeAreaSettings: this.shellFamily === 'large_screen',
      isLargeScreen: this.shellFamily === 'large_screen',
      tabletInterfaceModeVisible: tabletInterfaceModeState.visible,
      tabletInterfaceModeLabel: tabletInterfaceModeState.selectedLabel,
      secureDnsSummaryLabel: sharedSecureDnsSettingsCoordinator.getSummaryLabel(),
      adBlockEnabled: sharedAdBlockRepository.getSettings().preferences.enabled
    });
    this.state = this.shellFamily === 'large_screen'
      ? this.viewModel.applyLargeScreenSingleChoiceDropdowns(result.detailState, this.buildSingleChoiceSnapshot())
      : result.detailState;
  }

  private buildSingleChoiceSnapshot(): SettingsSingleChoiceSelectionSnapshot {
    const preferences = sharedPreferencesRepository.getPreferences();
    return {
      startupRestorePolicy: preferences.general.startupRestorePolicy,
      tabAutoClosePolicy: preferences.general.tabAutoClosePolicy,
      privateTabRestorePolicy: preferences.general.privateTabRestorePolicy,
      historyRetention: preferences.historyRetention,
      retentionProfileId: this.retentionSettings.profileId,
      sitePermissionDefaults: preferences.sitePermissionDefaults,
      appServiceMode: preferences.appServiceMode
    };
  }

  private handleRowAction(row: SettingsDetailRowState, nextChecked?: boolean): void {
    this.interactionCoordinator.handleRowAction(row, nextChecked, this.buildInteractionHandlers());
  }

  private handleActionButton(button: SettingsDetailActionButtonState): void {
    this.interactionCoordinator.handleActionButton(button, this.buildInteractionHandlers());
  }

  private buildInteractionHandlers(): SettingsDetailInteractionHandlers {
    return new SettingsDetailInteractionCallbackHandlers(
      (action: SettingsDetailRowAction): boolean => {
        if (action === 'open_app_proxy_settings' && this.onOpenAppProxySettings !== undefined) {
          this.onOpenAppProxySettings();
          return true;
        }
        if (this.shellFamily === 'large_screen' && this.onOpenEmbeddedSubpage !== undefined) {
          const subpageId = this.resolveEmbeddedSubpageId(action);
          if (subpageId !== undefined) {
            this.onOpenEmbeddedSubpage(subpageId);
            return true;
          }
        }
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

  private async copySupportQqGroupNumber(): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, AIRA_SUPPORT_QQ_GROUP_NUMBER);
      await pasteboard.getSystemPasteboard().setData(data);
      this.showToast('已复制QQ群号');
    } catch (_error) {
      this.showToast('QQ群号复制失败，请稍后再试。');
    }
  }

  private async applyThemeMode(themeMode: BrowserThemeMode): Promise<void> {
    const previousThemeMode = this.selectedThemeMode;
    this.selectedThemeMode = themeMode;
    this.rebuildStateFromLocalSettings();
    try {
      const result = await sharedBrowserThemeModeCoordinator.setThemeModeForBoundary(
        themeMode,
        this.buildThemeModeBoundary()
      );
      this.selectedThemeMode = result.mode;
      this.refreshState();
      this.onSettingsChanged?.();
      this.showToast(result.message);
    } catch (_error) {
      this.selectedThemeMode = previousThemeMode;
      this.rebuildStateFromLocalSettings();
      this.showToast('外观模式更新失败。');
    }
  }

  private async applySearchEngine(searchEngineId: SearchEngineId): Promise<void> {
    try {
      await sharedSearchEngineSettingsCoordinator.setDefaultEngine(searchEngineId, this.buildSearchBoundary());
      this.refreshState();
      this.onSettingsChanged?.();
      this.showToast('搜索引擎已更新。');
    } catch (_error) {
      this.showToast('搜索引擎更新失败。');
    }
  }

  private async applyAppServiceMode(mode: BrowserAppServiceMode): Promise<void> {
    try {
      this.settingsRenderVersion += 1;
      this.rebuildStateFromLocalSettings(mode);
      const result = await this.appServiceModeCoordinator.applyMode(mode, {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      });
      this.settingsRenderVersion += 1;
      this.refreshState();
      this.onSettingsChanged?.();
      this.showToast(result.message);
      this.appModeSwitchRestartService.scheduleRestartForModeSwitch();
    } catch (_error) {
      this.settingsRenderVersion += 1;
      this.refreshState();
      this.showToast('应用服务模式更新失败。');
    }
  }

  private async applyAppearanceSettings(nextSettings: BrowserAppearanceSettings): Promise<void> {
    const previousSettings = this.appearanceSettings;
    this.appearanceSettings = nextSettings;
    this.rebuildStateFromLocalSettings();
    try {
      const appearance = await this.interactionCoordinator.commitAppearanceSettings({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      }, nextSettings);
      this.appearanceSettings = appearance;
      this.refreshState();
      this.onSettingsChanged?.();
    } catch (_error) {
      this.appearanceSettings = previousSettings;
      this.rebuildStateFromLocalSettings();
      this.showToast('外观设置更新失败。');
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
      this.onSettingsChanged?.();
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
      this.onSettingsChanged?.();
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
      this.onSettingsChanged?.();
    } catch (_error) {
      this.refreshState();
      this.showToast('隐私模式 Cookie 设置更新失败。');
    }
  }

  private async applyExperimentSettings(nextSettings: BrowserExperimentSettings): Promise<void> {
    const previousSettings = this.experimentSettings;
    this.experimentSettings = nextSettings;
    this.rebuildStateFromLocalSettings();
    try {
      const settings = await this.interactionCoordinator.commitExperimentSettings({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      }, nextSettings);
      this.experimentSettings = settings;
      this.refreshState();
      this.onSettingsChanged?.();
      this.experimentSettingsRefreshSignal.bump();
      this.showToast(this.viewModel.buildExperimentUpdateToast(previousSettings, settings));
    } catch (_error) {
      this.experimentSettings = previousSettings;
      this.rebuildStateFromLocalSettings();
      this.showToast('实验室设置更新失败。');
    }
  }

  private async applyExperimentSettingsWithRiskPrompt(
    action: SettingsDetailRowAction,
    targetChecked: boolean,
    nextSettings: BrowserExperimentSettings
  ): Promise<void> {
    this.applyOptimisticExperimentSettings(nextSettings);
    const prompt = this.riskPromptViewModel.buildPrompt(action, targetChecked);
    if (prompt !== undefined) {
      this.showRiskPrompt(prompt, () => {
        void this.applyExperimentSettings(nextSettings);
      });
    } else {
      void this.applyExperimentSettings(nextSettings);
    }
  }

  private applyOptimisticExperimentSettings(nextSettings: BrowserExperimentSettings): void {
    this.experimentSettings = nextSettings;
    this.settingsRenderVersion += 1;
    this.rebuildStateFromLocalSettings();
  }

  private handleDropdownSelection(row: SettingsDetailRowState, optionId: string): void {
    const action = row.action;
    if (action === 'open_general_startup_settings') {
      void this.applyStartupRestorePolicy(optionId as BrowserStartupRestorePolicy);
      return;
    }
    if (action === 'open_general_tab_auto_close_settings') {
      void this.applyTabAutoClosePolicy(optionId as BrowserTabAutoClosePolicy);
      return;
    }
    if (action === 'open_general_history_retention_settings') {
      void this.applyHistoryRetentionOption(optionId);
      return;
    }
    if (action === 'open_general_private_tabs_settings') {
      void this.applyPrivateTabRestorePolicy(optionId as BrowserPrivateTabRestorePolicy);
      return;
    }
    if (action === 'open_retention_runtime_policy_settings') {
      void this.applyRetentionProfile(optionId as BrowserRetentionProfileId);
      return;
    }
    if (action === 'open_app_service_mode_settings') {
      this.requestAppServiceModeFromDropdown(optionId);
      return;
    }
    const permissionKind = this.resolveSitePermissionKind(action);
    if (permissionKind !== undefined) {
      this.applySitePermissionDefaultRule(permissionKind, optionId as SitePermissionRule);
    }
  }

  private buildNextGeneralSettings(patch: Partial<BrowserGeneralSettings>): BrowserGeneralSettings {
    const previous = sharedPreferencesRepository.getPreferences().general;
    return {
      startupRestorePolicy: patch.startupRestorePolicy ?? previous.startupRestorePolicy,
      tabAutoClosePolicy: patch.tabAutoClosePolicy ?? previous.tabAutoClosePolicy,
      privateTabRestorePolicy: patch.privateTabRestorePolicy ?? previous.privateTabRestorePolicy,
      privateModeAuthenticationEnabled: previous.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: previous.alwaysUsePrivateMode === true,
      privateModePreserveCookiesOnClose: previous.privateModePreserveCookiesOnClose,
      privateModeThemeEnabled: previous.privateModeThemeEnabled
    };
  }

  private async applyGeneralSettings(nextSettings: BrowserGeneralSettings, failureMessage: string): Promise<void> {
    try {
      await this.interactionCoordinator.commitGeneralSettings({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      }, nextSettings);
      this.refreshState();
      this.onSettingsChanged?.();
    } catch (_error) {
      this.refreshState();
      this.showToast(failureMessage);
    }
  }

  private async applyStartupRestorePolicy(policy: BrowserStartupRestorePolicy): Promise<void> {
    await this.applyGeneralSettings(this.buildNextGeneralSettings({ startupRestorePolicy: policy }), '启动行为更新失败。');
  }

  private async applyTabAutoClosePolicy(policy: BrowserTabAutoClosePolicy): Promise<void> {
    await this.applyGeneralSettings(this.buildNextGeneralSettings({ tabAutoClosePolicy: policy }), '自动关闭标签页更新失败。');
  }

  private async applyPrivateTabRestorePolicy(policy: BrowserPrivateTabRestorePolicy): Promise<void> {
    await this.applyGeneralSettings(this.buildNextGeneralSettings({ privateTabRestorePolicy: policy }), '私密标签页恢复更新失败。');
  }

  private async applyHistoryRetentionOption(optionId: string): Promise<void> {
    const settings = this.resolveHistoryRetentionSettings(optionId);
    try {
      const saved = await this.historyFeature.updateHistoryRetentionSettingsForBoundary(settings, {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      });
      await this.historyFeature.applyRetentionPolicyForManagement(
        saved,
        new HistoryManagementBoundary(this.dataScope, this.privacyMode)
      );
      this.refreshState();
      this.onSettingsChanged?.();
    } catch (_error) {
      this.refreshState();
      this.showToast('历史保留更新失败。');
    }
  }

  private resolveHistoryRetentionSettings(optionId: string): HistoryRetentionSettings {
    if (optionId === 'off') {
      return { enabled: false, maxAgeDays: 0, maxRows: 0 };
    }
    if (optionId === '30_3000') {
      return { enabled: true, maxAgeDays: 30, maxRows: 3000 };
    }
    return { enabled: true, maxAgeDays: 90, maxRows: 10000 };
  }

  private async applyRetentionProfile(profileId: BrowserRetentionProfileId): Promise<void> {
    try {
      const result = await this.retentionSettingsCoordinator.applyProfile(profileId, {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      });
      this.retentionSettings = result.settings;
      this.refreshState();
      this.onSettingsChanged?.();
      this.showToast(result.message);
    } catch (_error) {
      this.refreshState();
      this.showToast('后台标签页策略更新失败。');
    }
  }

  private applySitePermissionDefaultRule(kind: SitePermissionKind, rule: SitePermissionRule): void {
    this.sitePermissionsCoordinator.updateDefaultRule(kind, rule, {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    })
      .then(() => {
        this.refreshState();
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.refreshState();
        this.showToast('站点默认权限更新失败。');
      });
  }

  private requestAppServiceModeFromDropdown(optionId: string): void {
    const mode: BrowserAppServiceMode = optionId === 'basic' ? 'basic' : 'full';
    if (mode === sharedPreferencesRepository.getPreferences().appServiceMode) {
      return;
    }
    const syntheticRow: SettingsDetailRowState = {
      id: mode === 'basic' ? 'app_service_mode_basic' : 'app_service_mode_full',
      kind: 'option',
      action: mode === 'basic' ? 'set_app_service_mode_basic' : 'set_app_service_mode_full',
      title: '',
      value: '',
      valueSwatchColor: '',
      helperText: '',
      isEnabled: true,
      isSelected: false,
      checked: false
    };
    this.handleRowAction(syntheticRow);
  }

  private resolveSitePermissionKind(action: SettingsDetailRowAction): SitePermissionKind | undefined {
    if (action === 'open_site_permission_default_camera') {
      return 'camera';
    }
    if (action === 'open_site_permission_default_microphone') {
      return 'microphone';
    }
    if (action === 'open_site_permission_default_location') {
      return 'location';
    }
    if (action === 'open_site_permission_default_sensor') {
      return 'sensor';
    }
    if (action === 'open_site_permission_default_clipboard') {
      return 'clipboard';
    }
    return undefined;
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
    this.onSettingsChanged?.();
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
    this.onSettingsChanged?.();
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
    this.rebuildStateFromLocalSettings();
    this.showToast('正在刷新网站图标...');
    try {
      const result = await this.siteIconCacheMaintenanceCoordinator.refreshKnownSiteIcons();
      this.showToast(result.message);
    } catch (_error) {
      this.showToast('网站图标刷新失败，请稍后再试。');
    } finally {
      this.siteIconRefreshing = false;
      this.refreshState();
      this.onSettingsChanged?.();
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
        fontColor: prompt.confirmIsDestructive ? $r('app.color.permission_blocked') : this.accentColor,
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
        fontColor: prompt.confirmIsDestructive ? $r('app.color.permission_blocked') : this.accentColor,
        action: () => {
          onConfirm();
        }
      }
    });
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

  private getAbilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private resolveEmbeddedSubpageId(action: SettingsDetailRowAction): string | undefined {
    if (action === 'open_external_navigation_settings') {
      return 'privacy_external_navigation';
    }
    if (action === 'open_ad_block_settings') {
      return 'privacy_ad_blocker';
    }
    if (action === 'open_site_settings') {
      return 'privacy_site_settings';
    }
    if (action === 'open_cookie_management') {
      return 'privacy_cookie_management';
    }
    if (action === 'open_password_settings') {
      return 'passwords';
    }
    if (action === 'open_download_settings') {
      return 'downloads';
    }
    if (action === 'open_webpage_translation_settings') {
      return 'webpage_translation';
    }
    if (action === 'open_keyboard_shortcuts_settings') {
      return 'keyboard_shortcuts';
    }
    if (action === 'open_local_backup') {
      return 'local_backup';
    }
    if (action === 'open_app_icon_settings') {
      return 'app_icon';
    }
    if (action === 'open_theme_palette_settings') {
      return 'theme_palette';
    }
    if (action === 'open_tablet_interface_mode_settings') {
      return 'tablet_interface_mode';
    }
    if (action === 'open_tracking_protection_settings') {
      return 'tracking_protection';
    }
    if (action === 'open_secure_dns_settings') {
      return 'secure_dns_settings';
    }
    return undefined;
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
