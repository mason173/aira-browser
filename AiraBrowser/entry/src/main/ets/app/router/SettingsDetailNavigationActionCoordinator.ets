import { common } from '@kit.AbilityKit';
import { APP_ICP_FILING_QUERY_URL } from '../../common/constants/AppVersionInfo';
import {
  AIRA_COMMUNITY_LICENSE_URL,
  AIRA_COMMUNITY_REPOSITORY_URL,
  AIRA_COMMUNITY_SECURITY_POLICY_URL,
  AIRA_COMMUNITY_THIRD_PARTY_NOTICES_URL
} from '../../common/constants/AiraCommunityProjectLinks';
import { BrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { SettingsDetailActionResolver } from '../../core/settings/SettingsDetailActionResolver';
import { SettingsDetailRowAction } from '../../core/settings/SettingsDetailViewModel';
import { SystemSettingsLaunchService } from '../../services/system/SystemSettingsLaunchService';
import { SettingsNavigationCoordinator } from './SettingsNavigationCoordinator';

export interface SettingsDetailNavigationActionHandlers {
  buildBoundaryRouteState(): BrowserBoundaryRouteState;
  getAbilityContext(): common.UIAbilityContext;
  showToast(message: string): void;
  openSupportQqGroupDialog(): void;
  confirmClearAllSiteData(): void;
  confirmResetSitePermissions(): void;
  confirmRefreshSiteIcons(): void;
}

export class SettingsDetailNavigationActionCallbackHandlers implements SettingsDetailNavigationActionHandlers {
  private buildBoundaryRouteStateHandler: () => BrowserBoundaryRouteState;
  private getAbilityContextHandler: () => common.UIAbilityContext;
  private showToastHandler: (message: string) => void;
  private openSupportQqGroupDialogHandler: () => void;
  private confirmClearAllSiteDataHandler: () => void;
  private confirmResetSitePermissionsHandler: () => void;
  private confirmRefreshSiteIconsHandler: () => void;

  constructor(
    buildBoundaryRouteStateHandler: () => BrowserBoundaryRouteState,
    getAbilityContextHandler: () => common.UIAbilityContext,
    showToastHandler: (message: string) => void,
    openSupportQqGroupDialogHandler: () => void,
    confirmClearAllSiteDataHandler: () => void,
    confirmResetSitePermissionsHandler: () => void,
    confirmRefreshSiteIconsHandler: () => void
  ) {
    this.buildBoundaryRouteStateHandler = buildBoundaryRouteStateHandler;
    this.getAbilityContextHandler = getAbilityContextHandler;
    this.showToastHandler = showToastHandler;
    this.openSupportQqGroupDialogHandler = openSupportQqGroupDialogHandler;
    this.confirmClearAllSiteDataHandler = confirmClearAllSiteDataHandler;
    this.confirmResetSitePermissionsHandler = confirmResetSitePermissionsHandler;
    this.confirmRefreshSiteIconsHandler = confirmRefreshSiteIconsHandler;
  }

  buildBoundaryRouteState(): BrowserBoundaryRouteState {
    return this.buildBoundaryRouteStateHandler();
  }

  getAbilityContext(): common.UIAbilityContext {
    return this.getAbilityContextHandler();
  }

  showToast(message: string): void {
    this.showToastHandler(message);
  }

  openSupportQqGroupDialog(): void {
    this.openSupportQqGroupDialogHandler();
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
}

export class SettingsDetailNavigationActionCoordinator {
  private actionResolver: SettingsDetailActionResolver = new SettingsDetailActionResolver();
  private navigationCoordinator: SettingsNavigationCoordinator;
  private systemSettingsLaunchService: SystemSettingsLaunchService;

  constructor(
    navigationCoordinator: SettingsNavigationCoordinator,
    systemSettingsLaunchService: SystemSettingsLaunchService
  ) {
    this.navigationCoordinator = navigationCoordinator;
    this.systemSettingsLaunchService = systemSettingsLaunchService;
  }

  handle(action: SettingsDetailRowAction, handlers: SettingsDetailNavigationActionHandlers): boolean {
    const boundary = handlers.buildBoundaryRouteState();
    if (action === 'open_changelog') {
      this.navigationCoordinator.openChangelog(boundary);
      return true;
    }
    if (action === 'open_privacy_statement') {
      this.navigationCoordinator.openPrivacyStatement(boundary);
      return true;
    }
    if (action === 'open_user_service_agreement_web') {
      this.navigationCoordinator.openLegalWebDocument('user_service_agreement', boundary);
      return true;
    }
    if (action === 'open_pro_membership_service_agreement') {
      this.navigationCoordinator.openLegalWebDocument('pro_membership_service_agreement', boundary);
      return true;
    }
    if (action === 'open_pro_auto_renewal_service_agreement') {
      this.navigationCoordinator.openLegalWebDocument('pro_auto_renewal_service_agreement', boundary);
      return true;
    }
    if (action === 'open_third_party_sdk_and_services') {
      this.navigationCoordinator.openLegalWebDocument('third_party_sdk_and_services', boundary);
      return true;
    }
    if (action === 'open_personal_info_and_permissions') {
      this.navigationCoordinator.openLegalWebDocument('personal_info_and_permissions', boundary);
      return true;
    }
    if (action === 'open_community_source_repository') {
      this.navigationCoordinator.openBrowserUrlFromGuide(AIRA_COMMUNITY_REPOSITORY_URL, boundary);
      return true;
    }
    if (action === 'open_community_license') {
      this.navigationCoordinator.openBrowserUrlFromGuide(AIRA_COMMUNITY_LICENSE_URL, boundary);
      return true;
    }
    if (action === 'open_community_third_party_notices') {
      this.navigationCoordinator.openBrowserUrlFromGuide(AIRA_COMMUNITY_THIRD_PARTY_NOTICES_URL, boundary);
      return true;
    }
    if (action === 'open_community_security_policy') {
      this.navigationCoordinator.openBrowserUrlFromGuide(AIRA_COMMUNITY_SECURITY_POLICY_URL, boundary);
      return true;
    }
    if (action === 'copy_support_qq_group') {
      handlers.openSupportQqGroupDialog();
      return true;
    }
    if (action === 'open_icp_filing_query') {
      this.openIcpFilingQuery(handlers);
      return true;
    }
    if (action === 'open_app_review_page') {
      this.openAppReviewPage(handlers);
      return true;
    }
    if (action === 'open_search_settings') {
      this.navigationCoordinator.openSearchSettings(boundary);
      return true;
    }
    if (action === 'open_password_settings') {
      this.navigationCoordinator.openPasswordSettings(boundary);
      return true;
    }
    if (action === 'open_ad_block_settings') {
      this.navigationCoordinator.openAdBlockSettings(boundary);
      return true;
    }
    if (action === 'open_site_settings') {
      this.navigationCoordinator.openSiteControlsManagement(boundary);
      return true;
    }
    if (action === 'open_cookie_management') {
      this.navigationCoordinator.openCookieManagement(boundary);
      return true;
    }
    if (action === 'open_external_navigation_settings') {
      this.navigationCoordinator.openSiteControlsExternalNavigationDefault(boundary);
      return true;
    }
    if (action === 'open_download_settings') {
      this.navigationCoordinator.openDownloadSettings(boundary);
      return true;
    }
    if (action === 'open_webpage_translation_settings') {
      this.navigationCoordinator.openWebpageTranslationSettings(boundary);
      return true;
    }
    if (action === 'open_app_service_mode_settings') {
      this.navigationCoordinator.openSettingsDetail('app_service_mode', boundary);
      return true;
    }
    if (action === 'open_theme_palette_settings') {
      this.navigationCoordinator.openThemePaletteSettings(boundary, () => {
        handlers.showToast('主题色设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_tablet_interface_mode_settings') {
      this.navigationCoordinator.openBrowserTabletInterfaceModeSettings(boundary, () => {
        handlers.showToast('界面模式设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_tracking_protection_settings') {
      this.navigationCoordinator.openBrowserTrackingProtectionSettings(boundary, () => {
        handlers.showToast('防跟踪设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_app_icon_settings') {
      this.navigationCoordinator.openAppIconSettings(boundary, () => {
        handlers.showToast('应用图标设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_browser_toolbar_customization') {
      this.navigationCoordinator.openBrowserToolbarCustomization(boundary, () => {
        handlers.showToast('工具栏设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_general_startup_settings') {
      this.navigationCoordinator.openGeneralStartupSettings(boundary, () => {
        handlers.showToast('通用设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_general_tab_auto_close_settings') {
      this.navigationCoordinator.openGeneralTabAutoCloseSettings(boundary, () => {
        handlers.showToast('通用设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_general_private_tabs_settings') {
      this.navigationCoordinator.openGeneralPrivateTabsSettings(boundary, () => {
        handlers.showToast('通用设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_general_history_retention_settings') {
      this.navigationCoordinator.openGeneralHistoryRetentionSettings(boundary, () => {
        handlers.showToast('通用设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_retention_runtime_policy_settings') {
      this.navigationCoordinator.openRetentionRuntimePolicySettings(boundary);
      return true;
    }
    if (action === 'open_local_backup') {
      this.navigationCoordinator.openLocalBackup(boundary);
      return true;
    }
    if (action === 'open_keyboard_shortcuts_settings') {
      this.navigationCoordinator.openKeyboardShortcutsSettings(boundary, () => {
        handlers.showToast('快捷键说明暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_app_proxy_settings') {
      this.navigationCoordinator.openAppProxySettings(boundary, () => {
        handlers.showToast('代理设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_secure_dns_settings') {
      this.navigationCoordinator.openSecureDnsSettings(boundary, () => {
        handlers.showToast('安全 DNS 设置暂时无法打开，请稍后重试。');
      });
      return true;
    }
    if (action === 'open_default_browser_settings') {
      this.openDefaultBrowserSettings(handlers);
      return true;
    }
    if (action === 'clear_all_site_data') {
      handlers.confirmClearAllSiteData();
      return true;
    }
    if (action === 'reset_site_permissions') {
      handlers.confirmResetSitePermissions();
      return true;
    }
    if (action === 'refresh_site_icons') {
      handlers.confirmRefreshSiteIcons();
      return true;
    }
    const defaultPermissionKind = this.actionResolver.resolveSitePermissionDefaultKind(action);
    if (defaultPermissionKind !== undefined) {
      this.navigationCoordinator.openSitePermissionDefault(defaultPermissionKind, boundary);
      return true;
    }
    return false;
  }

  private openIcpFilingQuery(handlers: SettingsDetailNavigationActionHandlers): void {
    this.systemSettingsLaunchService.openExternalUrl(handlers.getAbilityContext(), APP_ICP_FILING_QUERY_URL)
      .then((result) => {
        handlers.showToast(result.success ? '已打开工信部备案系统。' : '备案系统暂时无法打开，请稍后重试。');
      })
      .catch((_error: Error) => {
        handlers.showToast('备案系统暂时无法打开，请稍后重试。');
      });
  }

  private openAppReviewPage(handlers: SettingsDetailNavigationActionHandlers): void {
    this.systemSettingsLaunchService.openAppReviewPage(handlers.getAbilityContext())
      .then((result) => {
        if (!result.success) {
          handlers.showToast(result.message.length > 0 ? result.message : '暂时无法打开应用市场，请稍后重试。');
        }
      })
      .catch((_error: Error) => {
        handlers.showToast('暂时无法打开应用市场，请稍后重试。');
      });
  }

  private openDefaultBrowserSettings(handlers: SettingsDetailNavigationActionHandlers): void {
    this.systemSettingsLaunchService.openDefaultBrowserSettings(handlers.getAbilityContext())
      .then((result) => {
        handlers.showToast(result.message);
      })
      .catch((_error: Error) => {
        handlers.showToast('无法打开默认浏览器设置，请手动进入系统设置更改。');
      });
  }
}
