import {
  BrowserAppServiceMode,
  BrowserAppearanceSettings,
  BrowserExperimentSettings,
  BrowserRetentionSettings,
  BrowserThemeMode,
  ExternalNavigationAppOpenPolicy,
  SearchEngineId
} from '../../common/models/BrowserModels';
import { SettingsAboutCoordinator } from './SettingsAboutCoordinator';
import {
  SettingsAboutOverviewState,
  SettingsAboutOverviewViewModel
} from './SettingsAboutOverviewViewModel';
import { SettingsGeneralCoordinator } from './SettingsGeneralCoordinator';
import { SettingsSitePermissionsCoordinator } from './SettingsSitePermissionsCoordinator';
import { SettingsSitePolicyCoordinator } from './SettingsSitePolicyCoordinator';
import {
  SettingsDetailState,
  SettingsDetailViewModel
} from './SettingsDetailViewModel';

export interface SettingsDetailStateBuildInput {
  destinationId: string;
  dataScope: string;
  privacyMode: string;
  themeMode: BrowserThemeMode;
  searchEngineId: SearchEngineId;
  externalNavigationPolicy: ExternalNavigationAppOpenPolicy;
  appearanceSettings: BrowserAppearanceSettings;
  experimentSettings: BrowserExperimentSettings;
  retentionSettings: BrowserRetentionSettings;
  siteIconRefreshing: boolean;
  appServiceMode: BrowserAppServiceMode;
  hideTopSafeAreaSettings?: boolean;
  isLargeScreen?: boolean;
  tabletInterfaceModeVisible?: boolean;
  tabletInterfaceModeLabel?: string;
  secureDnsSummaryLabel: string;
  adBlockEnabled: boolean;
}

export interface SettingsDetailStateBuildResult {
  detailState: SettingsDetailState;
  aboutOverviewState: SettingsAboutOverviewState;
}

export class SettingsDetailStateBuilder {
  private viewModel: SettingsDetailViewModel;
  private sitePolicyCoordinator: SettingsSitePolicyCoordinator;
  private generalCoordinator: SettingsGeneralCoordinator;
  private aboutCoordinator: SettingsAboutCoordinator;
  private aboutOverviewViewModel: SettingsAboutOverviewViewModel = new SettingsAboutOverviewViewModel();
  private sitePermissionsCoordinator: SettingsSitePermissionsCoordinator;

  constructor(
    viewModel: SettingsDetailViewModel,
    sitePolicyCoordinator: SettingsSitePolicyCoordinator,
    generalCoordinator: SettingsGeneralCoordinator,
    aboutCoordinator: SettingsAboutCoordinator,
    sitePermissionsCoordinator: SettingsSitePermissionsCoordinator
  ) {
    this.viewModel = viewModel;
    this.sitePolicyCoordinator = sitePolicyCoordinator;
    this.generalCoordinator = generalCoordinator;
    this.aboutCoordinator = aboutCoordinator;
    this.sitePermissionsCoordinator = sitePermissionsCoordinator;
  }

  build(input: SettingsDetailStateBuildInput): SettingsDetailStateBuildResult {
    const sitePolicyState = this.sitePolicyCoordinator.buildState({
      dataScope: input.dataScope,
      privacyMode: input.privacyMode
    });
    const sitePermissionsState = this.sitePermissionsCoordinator.buildState({
      dataScope: input.dataScope,
      privacyMode: input.privacyMode
    });
    const generalState = this.generalCoordinator.buildState();
    const aboutIdentity = this.aboutCoordinator.buildAppIdentity();
    const detailState = this.viewModel.buildState(
      input.destinationId,
      input.dataScope,
      input.privacyMode,
      input.themeMode,
      input.searchEngineId,
      {
        homeLayoutLabel: generalState.homeLayoutLabel,
        customHomepageLabel: generalState.customHomepageLabel,
        startupBehaviorLabel: generalState.startupBehaviorLabel,
        tabAutoCloseLabel: generalState.tabAutoCloseLabel,
        defaultBrowserLabel: generalState.defaultBrowserLabel,
        historyRetentionLabel: generalState.historyRetentionLabel,
        privateBrowsingLabel: generalState.privateBrowsingLabel,
        privateModeAuthenticationEnabled: generalState.privateModeAuthenticationEnabled,
        alwaysUsePrivateMode: generalState.alwaysUsePrivateMode,
        privateModePreserveCookiesOnClose: generalState.privateModePreserveCookiesOnClose,
        enhancedTrackingProtectionEnabled: generalState.enhancedTrackingProtectionEnabled
      },
      {
        acceptCookies: sitePolicyState.acceptCookies,
        acceptThirdPartyCookies: sitePolicyState.acceptThirdPartyCookies,
        thirdPartyCookiePolicyLocked: sitePolicyState.thirdPartyCookiePolicyLocked
      },
      {
        appOpenPolicy: input.externalNavigationPolicy
      },
      input.appearanceSettings,
      input.experimentSettings,
      input.retentionSettings,
      {
        savedOriginCount: sitePermissionsState.savedOriginCount,
        allowRuleCount: sitePermissionsState.allowRuleCount,
        blockRuleCount: sitePermissionsState.blockRuleCount,
        askRuleCount: sitePermissionsState.askRuleCount,
        defaults: sitePermissionsState.defaults,
        defaultCapabilities: sitePermissionsState.defaultCapabilities,
        canClearPermissions: sitePermissionsState.canClearPermissions,
        summaryLine: sitePermissionsState.summaryLine
      },
      {
        appName: aboutIdentity.appName,
        bundleName: aboutIdentity.bundleName,
        versionName: aboutIdentity.versionName,
        versionCode: aboutIdentity.versionCode
      },
      input.siteIconRefreshing,
      input.appServiceMode,
      input.hideTopSafeAreaSettings === true,
      input.isLargeScreen === true,
      input.tabletInterfaceModeVisible === true,
      input.tabletInterfaceModeLabel ?? '自动',
      input.secureDnsSummaryLabel,
      input.adBlockEnabled
    );
    return {
      detailState: detailState,
      aboutOverviewState: this.aboutOverviewViewModel.buildState(aboutIdentity)
    };
  }
}
