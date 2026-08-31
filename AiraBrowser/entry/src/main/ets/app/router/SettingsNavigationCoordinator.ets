import router from '@ohos.router';
import {
  SettingsCenterDestination
} from '../../core/settings/SettingsCenterViewModel';
import { SettingsRoutedDestination } from '../../core/settings/SettingsDestinationNavigationOwner';
import {
  BrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import {
  AD_BLOCK_CUSTOM_RULES_ROUTE,
  AD_BLOCK_SETTINGS_ROUTE,
  AIRA_PRO_ROUTE,
  APP_ICON_SETTINGS_ROUTE,
  APP_PROXY_PROFILE_EDIT_ROUTE,
  APP_PROXY_PROTOCOL_SETTINGS_ROUTE,
  APP_PROXY_SETTINGS_ROUTE,
  BROWSER_TOOLBAR_CUSTOMIZATION_ROUTE,
  BROWSER_TOOLBAR_SCROLL_BEHAVIOR_SETTINGS_ROUTE,
  BROWSER_TABLET_INTERFACE_MODE_SETTINGS_ROUTE,
  BROWSER_TRACKING_PROTECTION_SETTINGS_ROUTE,
  BROWSER_SHELL_ROUTE,
  COOKIE_MANAGEMENT_ROUTE,
  DOWNLOAD_SETTINGS_OPTION_ROUTE,
  DOWNLOAD_SETTINGS_ROUTE,
  EXTERNAL_APP_SEARCH_SETTINGS_ROUTE,
  CUSTOM_HOMEPAGE_SETTINGS_ROUTE,
  CUSTOM_HOMEPAGE_DEVELOPER_GUIDE_ROUTE,
  GENERAL_HISTORY_RETENTION_SETTINGS_ROUTE,
  GENERAL_PRIVATE_TABS_SETTINGS_ROUTE,
  GENERAL_STARTUP_SETTINGS_ROUTE,
  GENERAL_TAB_AUTO_CLOSE_SETTINGS_ROUTE,
  RETENTION_RUNTIME_POLICY_SETTINGS_ROUTE,
  HUAWEI_ACCOUNT_INFO_ROUTE,
  KEYBOARD_SHORTCUTS_SETTINGS_ROUTE,
  LOCAL_BACKUP_ROUTE,
  MANUAL_ELEMENT_HIDE_SETTINGS_ROUTE,
  PASSWORD_SETTINGS_ROUTE,
  SEARCH_BUILT_IN_ENGINES_ROUTE,
  SEARCH_DEFAULT_ENGINE_ROUTE,
  SEARCH_ENGINE_EDIT_ROUTE,
  SEARCH_FALLBACK_ENGINE_ROUTE,
  SEARCH_SETTINGS_ROUTE,
  SECURE_DNS_PROFILE_EDIT_ROUTE,
  SECURE_DNS_SETTINGS_ROUTE,
  SETTINGS_CHANGELOG_ROUTE,
  SETTINGS_AUTO_RENEWAL_NOTICE_ROUTE,
  SETTINGS_DETAIL_ROUTE,
  SETTINGS_LEGAL_WEB_DOCUMENT_ROUTE,
  SETTINGS_PRIVACY_STATEMENT_ROUTE,
  SETTINGS_SITE_PERMISSION_DEFAULT_ROUTE,
  SITE_CONTROLS_CAPABILITY_ROUTE,
  SITE_CONTROLS_EXTERNAL_NAVIGATION_DEFAULT_ROUTE,
  SITE_CONTROLS_MANAGEMENT_ROUTE,
  SITE_CUSTOMIZATION_DETAIL_ROUTE,
  SITE_CUSTOMIZATION_DESKTOP_SITE_ROUTE,
  SITE_CUSTOMIZATION_PERMISSION_ROUTE,
  SYNC_ADDITIONAL_BACKUP_OPTIONS_ROUTE,
  SYNC_ADDITIONAL_BACKUP_ROUTE,
  SYNC_ADVANCED_SETTINGS_ROUTE,
  SYNC_DESKTOP_BOOKMARK_GUIDE_ROUTE,
  SYNC_PERSONAL_SERVER_CONFIG_ROUTE,
  SYNC_SETTINGS_ROUTE,
  SYNC_WEBDAV_CONFIG_ROUTE,
  SYNC_WEBDAV_PROVIDER_ROUTE,
  THEME_PALETTE_SETTINGS_ROUTE,
  TRANSLATION_PROVIDER_CONFIG_ROUTE,
  TRANSLATION_PROVIDER_EDIT_ROUTE,
  USER_AGENT_SETTINGS_ROUTE,
  USER_SCRIPTS_ROUTE,
  WEB_APP_DETAIL_SETTINGS_ROUTE,
  WEB_APP_SETTINGS_ROUTE,
  WEBPAGE_TRANSLATION_SETTINGS_ROUTE
} from './AppRoutes';
import { sharedPreferencesRepository } from '../bootstrap/BrowserAppRuntime';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import { SiteCustomizationFocusCapability } from '../../core/sitecontrols/SiteControlsNavigationDecision';
import { requestOpenBrowserUrlWithRouteParams } from '../../core/navigation/BrowserNativeNavigationRequestCenter';

export interface SettingsRouteParams extends BrowserBoundaryRouteState {
  sectionId?: string;
  kind?: string;
  customizationKind?: string;
  engineId?: string;
  providerId?: string;
  subpage?: string;
  focusCapability?: SiteCustomizationFocusCapability;
  capabilityTitle?: string;
  templateId?: string;
  host?: string;
  origin?: string;
  profileId?: string;
  returnHome?: string;
  returnHomeToken?: string;
  syncTargetRole?: 'active' | 'additional_backup';
  syncActivateExperience?: string;
  shortcutId?: string;
  settingsTargetId?: string;
  settingsRevealTargetId?: string;
}

export class SettingsNavigationCoordinator {
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);

  back(): void {
    router.back();
  }

  backToBrowserShell(params?: SettingsRouteParams): boolean {
    try {
      router.back({
        url: BROWSER_SHELL_ROUTE,
        params: params
      });
      return true;
    } catch (_error) {
      return false;
    }
  }

  openBrowserUrlFromGuide(url: string, boundary: BrowserBoundaryRouteState): void {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length === 0) {
      return;
    }
    router.back({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(
        normalizedUrl,
        'current_tab',
        '',
        'app_ui',
        {
          privacyMode: boundary.privacyMode,
          dataScope: boundary.dataScope
        }
      )
    });
  }

  pushUrl(url: string, params?: SettingsRouteParams, onError?: () => void): void {
    router.pushUrl({
      url: url,
      params: params
    }).catch((_error: Error) => {
      onError?.();
    });
  }

  async pushUrlCommitted(url: string, params?: SettingsRouteParams): Promise<boolean> {
    try {
      await router.pushUrl({
        url: url,
        params: params
      });
      return true;
    } catch (_error) {
      return false;
    }
  }

  openRoutedDestinationCommitted(
    target: SettingsRoutedDestination,
    boundary: BrowserBoundaryRouteState
  ): Promise<boolean> {
    const params = this.buildParams(boundary);
    params.settingsTargetId = target.targetId;
    params.settingsRevealTargetId = target.revealTargetId;
    if (target.subpageId === 'privacy_ad_blocker') {
      return this.pushUrlCommitted(AD_BLOCK_SETTINGS_ROUTE, params);
    }
    if (target.subpageId === 'privacy_site_settings') {
      return this.pushUrlCommitted(SITE_CONTROLS_MANAGEMENT_ROUTE, params);
    }
    if (target.subpageId === 'privacy_external_navigation') {
      return this.pushUrlCommitted(SITE_CONTROLS_EXTERNAL_NAVIGATION_DEFAULT_ROUTE, params);
    }
    if (target.subpageId === 'privacy_cookie_management') {
      return this.pushUrlCommitted(COOKIE_MANAGEMENT_ROUTE, params);
    }
    if (target.subpageId === 'keyboard_shortcuts') {
      return this.pushUrlCommitted(KEYBOARD_SHORTCUTS_SETTINGS_ROUTE, params);
    }
    if (target.subpageId === 'local_backup') {
      return this.pushUrlCommitted(LOCAL_BACKUP_ROUTE, params);
    }
    if (target.subpageId === 'passwords') {
      return this.pushUrlCommitted(PASSWORD_SETTINGS_ROUTE, params);
    }
    if (target.subpageId === 'downloads') {
      return this.pushUrlCommitted(DOWNLOAD_SETTINGS_ROUTE, params);
    }
    if (target.subpageId === 'webpage_translation') {
      return this.pushUrlCommitted(WEBPAGE_TRANSLATION_SETTINGS_ROUTE, params);
    }
    if (target.subpageId === 'theme_palette') {
      return this.pushUrlCommitted(THEME_PALETTE_SETTINGS_ROUTE, params);
    }
    if (target.subpageId === 'app_icon') {
      return this.pushUrlCommitted(APP_ICON_SETTINGS_ROUTE, params);
    }
    if (target.subpageId === 'tablet_interface_mode') {
      return this.pushUrlCommitted(BROWSER_TABLET_INTERFACE_MODE_SETTINGS_ROUTE, params);
    }
    if (target.subpageId === 'search_built_in_engines') {
      return this.pushUrlCommitted(SEARCH_BUILT_IN_ENGINES_ROUTE, params);
    }
    if (target.subpageId === 'toolbar_scroll_behavior') {
      return this.pushUrlCommitted(BROWSER_TOOLBAR_SCROLL_BEHAVIOR_SETTINGS_ROUTE, params);
    }
    if (target.subpageId === 'app_service_mode') {
      params.sectionId = 'app_service_mode';
      return this.pushUrlCommitted(SETTINGS_DETAIL_ROUTE, params);
    }
    if (target.subpageId === 'about_details') {
      params.sectionId = 'about';
      params.subpage = 'details';
      return this.pushUrlCommitted(SETTINGS_DETAIL_ROUTE, params);
    }
    return this.openCenterDestinationCommitted(target.destination, params);
  }

  private openCenterDestinationCommitted(
    destination: SettingsCenterDestination,
    params: SettingsRouteParams
  ): Promise<boolean> {
    if (destination === 'search') {
      return this.pushUrlCommitted(SEARCH_SETTINGS_ROUTE, params);
    }
    if (destination === 'webpage_translation') {
      return this.pushUrlCommitted(WEBPAGE_TRANSLATION_SETTINGS_ROUTE, params);
    }
    if (destination === 'web_apps') {
      return this.pushUrlCommitted(WEB_APP_SETTINGS_ROUTE, params);
    }
    if (destination === 'passwords') {
      return this.pushUrlCommitted(PASSWORD_SETTINGS_ROUTE, params);
    }
    if (destination === 'user_scripts') {
      return this.pushUrlCommitted(USER_SCRIPTS_ROUTE, params);
    }
    if (destination === 'downloads') {
      return this.pushUrlCommitted(DOWNLOAD_SETTINGS_ROUTE, params);
    }
    if (destination === 'user_agent') {
      return this.pushUrlCommitted(USER_AGENT_SETTINGS_ROUTE, params);
    }
    if (destination === 'sync') {
      return this.pushUrlCommitted(SYNC_SETTINGS_ROUTE, params);
    }
    if (destination === 'aira_pro') {
      return this.pushUrlCommitted(AIRA_PRO_ROUTE, params);
    }
    if (destination === 'custom_homepage') {
      return this.pushUrlCommitted(CUSTOM_HOMEPAGE_SETTINGS_ROUTE, params);
    }
    if (destination === 'toolbar_customization') {
      return this.pushUrlCommitted(BROWSER_TOOLBAR_CUSTOMIZATION_ROUTE, params);
    }
    params.sectionId = destination;
    return this.pushUrlCommitted(SETTINGS_DETAIL_ROUTE, params);
  }

  openAiraPro(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(AIRA_PRO_ROUTE, this.buildParams(boundary));
  }

  openHuaweiAccountInfo(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(HUAWEI_ACCOUNT_INFO_ROUTE, this.buildParams(boundary));
  }

  openSettingsDetail(sectionId: string, boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SETTINGS_DETAIL_ROUTE, this.buildParams(boundary, sectionId));
  }

  openSettingsDetailSubpage(sectionId: string, subpage: string, boundary: BrowserBoundaryRouteState): void {
    const params = this.buildParams(boundary, sectionId);
    params.subpage = subpage;
    this.pushUrl(SETTINGS_DETAIL_ROUTE, params);
  }

  openChangelog(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SETTINGS_CHANGELOG_ROUTE, this.buildParams(boundary));
  }

  openLegalWebDocument(documentId: string, boundary: BrowserBoundaryRouteState): void {
    const params = this.buildParams(boundary);
    params.kind = documentId;
    this.pushUrl(SETTINGS_LEGAL_WEB_DOCUMENT_ROUTE, params);
  }

  openPrivacyStatement(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SETTINGS_PRIVACY_STATEMENT_ROUTE, this.buildParams(boundary));
  }

  openAutoRenewalNotice(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SETTINGS_AUTO_RENEWAL_NOTICE_ROUTE, this.buildParams(boundary));
  }

  openAdBlockSettings(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(AD_BLOCK_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openDownloadSettings(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(DOWNLOAD_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openUserAgentSettings(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(USER_AGENT_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openUserScriptsSettings(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(USER_SCRIPTS_ROUTE, this.buildParams(boundary));
  }

  openAdBlockCustomRules(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(AD_BLOCK_CUSTOM_RULES_ROUTE, this.buildParams(boundary));
  }

  openManualElementHideSettings(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(MANUAL_ELEMENT_HIDE_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openThemePaletteSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(THEME_PALETTE_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openCustomHomepageSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(CUSTOM_HOMEPAGE_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openBrowserToolbarCustomization(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(BROWSER_TOOLBAR_CUSTOMIZATION_ROUTE, this.buildParams(boundary), onError);
  }

  openBrowserToolbarScrollBehavior(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(BROWSER_TOOLBAR_SCROLL_BEHAVIOR_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openBrowserTabletInterfaceModeSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(BROWSER_TABLET_INTERFACE_MODE_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openBrowserTrackingProtectionSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(BROWSER_TRACKING_PROTECTION_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openCustomHomepageDeveloperGuide(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(CUSTOM_HOMEPAGE_DEVELOPER_GUIDE_ROUTE, this.buildParams(boundary), onError);
  }

  openGeneralStartupSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(GENERAL_STARTUP_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openGeneralTabAutoCloseSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(GENERAL_TAB_AUTO_CLOSE_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openGeneralPrivateTabsSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(GENERAL_PRIVATE_TABS_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openGeneralHistoryRetentionSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(GENERAL_HISTORY_RETENTION_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openKeyboardShortcutsSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(KEYBOARD_SHORTCUTS_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openAppProxySettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(APP_PROXY_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openSecureDnsSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(SECURE_DNS_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openSecureDnsProfileEdit(
    boundary: BrowserBoundaryRouteState,
    profileId?: string,
    onError?: () => void
  ): void {
    const params = this.buildParams(boundary);
    if (profileId !== undefined && profileId.trim().length > 0) {
      params.profileId = profileId;
    }
    this.pushUrl(SECURE_DNS_PROFILE_EDIT_ROUTE, params, onError);
  }

  openAppProxyProfileEdit(
    boundary: BrowserBoundaryRouteState,
    profileId?: string,
    onError?: () => void
  ): void {
    const params = this.buildParams(boundary);
    if (profileId !== undefined && profileId.trim().length > 0) {
      params.profileId = profileId;
    }
    this.pushUrl(APP_PROXY_PROFILE_EDIT_ROUTE, params, onError);
  }

  openAppIconSettings(boundary: BrowserBoundaryRouteState, onError?: () => void): void {
    this.pushUrl(APP_ICON_SETTINGS_ROUTE, this.buildParams(boundary), onError);
  }

  openAppProxyProtocolSettings(
    boundary: BrowserBoundaryRouteState,
    profileId?: string,
    onError?: () => void
  ): void {
    const params = this.buildParams(boundary);
    if (profileId !== undefined && profileId.trim().length > 0) {
      params.profileId = profileId;
    }
    this.pushUrl(APP_PROXY_PROTOCOL_SETTINGS_ROUTE, params, onError);
  }

  openSitePermissionDefault(kind: string, boundary: BrowserBoundaryRouteState): void {
    const params = this.buildParams(boundary);
    params.kind = kind;
    this.pushUrl(SETTINGS_SITE_PERMISSION_DEFAULT_ROUTE, params);
  }

  openSiteControlsManagement(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SITE_CONTROLS_MANAGEMENT_ROUTE, this.buildParams(boundary));
  }

  openSiteControlsCapability(
    kind: string,
    profileId: string,
    boundary: BrowserBoundaryRouteState,
    capabilityTitle: string = ''
  ): void {
    const params = this.buildParams(boundary);
    params.kind = kind;
    params.profileId = profileId;
    params.capabilityTitle = capabilityTitle;
    this.pushUrl(SITE_CONTROLS_CAPABILITY_ROUTE, params);
  }

  openSiteControlsCustomizationCapability(
    customizationKind: string,
    profileId: string,
    boundary: BrowserBoundaryRouteState,
    capabilityTitle: string
  ): void {
    const params = this.buildParams(boundary);
    params.customizationKind = customizationKind;
    params.profileId = profileId;
    params.capabilityTitle = capabilityTitle;
    this.pushUrl(SITE_CONTROLS_CAPABILITY_ROUTE, params);
  }

  openSiteControlsExternalNavigationDefault(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SITE_CONTROLS_EXTERNAL_NAVIGATION_DEFAULT_ROUTE, this.buildParams(boundary));
  }

  openCookieManagement(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(COOKIE_MANAGEMENT_ROUTE, this.buildParams(boundary));
  }

  openSearchSettings(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SEARCH_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openExternalAppSearchSettings(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(EXTERNAL_APP_SEARCH_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openSearchDefaultEngine(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SEARCH_DEFAULT_ENGINE_ROUTE, this.buildParams(boundary));
  }

  openSearchFallbackEngine(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SEARCH_FALLBACK_ENGINE_ROUTE, this.buildParams(boundary));
  }

  openSearchBuiltInEngines(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(SEARCH_BUILT_IN_ENGINES_ROUTE, this.buildParams(boundary));
  }

  openSearchEngineEditor(engineId: string, boundary: BrowserBoundaryRouteState): void {
    const params = this.buildParams(boundary);
    params.engineId = engineId;
    this.pushUrl(SEARCH_ENGINE_EDIT_ROUTE, params);
  }

  openRetentionRuntimePolicySettings(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(RETENTION_RUNTIME_POLICY_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openPasswordSettings(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(PASSWORD_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openWebpageTranslationSettings(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(WEBPAGE_TRANSLATION_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openWebAppSettings(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(WEB_APP_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openWebAppDetailSettings(shortcutId: string, boundary: BrowserBoundaryRouteState): void {
    const params = this.buildParams(boundary);
    params.shortcutId = shortcutId.trim();
    this.pushUrl(WEB_APP_DETAIL_SETTINGS_ROUTE, params);
  }

  openTranslationProviderSelection(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(TRANSLATION_PROVIDER_EDIT_ROUTE, this.buildParams(boundary));
  }

  openTranslationProviderConfig(boundary: BrowserBoundaryRouteState, providerId: string): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    const params = this.buildParams(boundary);
    params.providerId = providerId;
    this.pushUrl(TRANSLATION_PROVIDER_CONFIG_ROUTE, params);
  }

  openTranslationProviderTemplateConfig(boundary: BrowserBoundaryRouteState, templateId: string): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    const params = this.buildParams(boundary);
    params.templateId = templateId;
    this.pushUrl(TRANSLATION_PROVIDER_CONFIG_ROUTE, params);
  }

  openSyncSettings(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(SYNC_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openSyncAdvancedSettings(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(SYNC_ADVANCED_SETTINGS_ROUTE, this.buildParams(boundary));
  }

  openSyncAdditionalBackup(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(SYNC_ADDITIONAL_BACKUP_ROUTE, this.buildParams(boundary));
  }

  openLocalBackup(boundary: BrowserBoundaryRouteState): void {
    this.pushUrl(LOCAL_BACKUP_ROUTE, this.buildParams(boundary));
  }

  openSyncAdditionalBackupOptions(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(SYNC_ADDITIONAL_BACKUP_OPTIONS_ROUTE, this.buildParams(boundary));
  }

  openSyncDesktopBookmarkGuide(boundary: BrowserBoundaryRouteState): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(SYNC_DESKTOP_BOOKMARK_GUIDE_ROUTE, this.buildParams(boundary));
  }

  openSyncWebdavConfig(
    boundary: BrowserBoundaryRouteState,
    targetRole: 'active' | 'additional_backup' = 'active',
    activateExperience: boolean = false
  ): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    const params = this.buildParams(boundary);
    params.syncTargetRole = targetRole;
    params.syncActivateExperience = activateExperience ? 'true' : 'false';
    this.pushUrl(SYNC_WEBDAV_CONFIG_ROUTE, params);
  }

  openSyncPersonalServerConfig(
    boundary: BrowserBoundaryRouteState,
    activateExperience: boolean = false
  ): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    const params = this.buildParams(boundary);
    params.syncActivateExperience = activateExperience ? 'true' : 'false';
    this.pushUrl(SYNC_PERSONAL_SERVER_CONFIG_ROUTE, params);
  }

  openSyncWebdavProvider(): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    this.pushUrl(SYNC_WEBDAV_PROVIDER_ROUTE);
  }

  openDownloadSettingsOption(subpage: string, boundary: BrowserBoundaryRouteState): void {
    const params = this.buildParams(boundary);
    params.subpage = subpage;
    this.pushUrl(DOWNLOAD_SETTINGS_OPTION_ROUTE, params);
  }

  openSiteCustomizationDetail(
    host: string,
    origin: string,
    profileId: string,
    boundary: BrowserBoundaryRouteState,
    focusCapability?: SiteCustomizationFocusCapability
  ): void {
    const params = this.buildParams(boundary);
    params.host = host;
    params.origin = origin;
    params.profileId = profileId;
    params.focusCapability = focusCapability;
    this.pushUrl(SITE_CUSTOMIZATION_DETAIL_ROUTE, params);
  }

  openSiteCustomizationPermission(
    host: string,
    origin: string,
    profileId: string,
    kind: string,
    boundary: BrowserBoundaryRouteState
  ): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    const params = this.buildParams(boundary);
    params.host = host;
    params.origin = origin;
    params.profileId = profileId;
    params.kind = kind;
    this.pushUrl(SITE_CUSTOMIZATION_PERMISSION_ROUTE, params);
  }

  openSiteCustomizationDesktopSite(
    host: string,
    origin: string,
    profileId: string,
    boundary: BrowserBoundaryRouteState
  ): void {
    if (!this.canOpenOptionalServiceRoute()) {
      return;
    }
    const params = this.buildParams(boundary);
    params.host = host;
    params.origin = origin;
    params.profileId = profileId;
    this.pushUrl(SITE_CUSTOMIZATION_DESKTOP_SITE_ROUTE, params);
  }

  buildParams(boundary: BrowserBoundaryRouteState, sectionId?: string): SettingsRouteParams {
    return {
      sectionId: sectionId,
      dataScope: boundary.dataScope,
      privacyMode: boundary.privacyMode,
      boundarySource: boundary.boundarySource,
      subpage: boundary.subpage
    };
  }

  private canOpenOptionalServiceRoute(): boolean {
    return this.appServiceModeGateService.canUseOptionalService();
  }
}
