import router from '@ohos.router';
import {
  AD_BLOCK_SETTINGS_ROUTE,
  AIRA_PRO_ROUTE,
  APP_PROXY_SETTINGS_ROUTE,
  BOOKMARK_MANAGER_ROUTE,
  CUSTOM_HOMEPAGE_SETTINGS_ROUTE,
  DOWNLOAD_MANAGEMENT_ROUTE,
  DOWNLOAD_SETTINGS_ROUTE,
  GENERAL_HISTORY_RETENTION_SETTINGS_ROUTE,
  GENERAL_PRIVATE_TABS_SETTINGS_ROUTE,
  GENERAL_STARTUP_SETTINGS_ROUTE,
  HISTORY_MANAGER_ROUTE,
  KEYBOARD_SHORTCUTS_SETTINGS_ROUTE,
  OFFLINE_PAGES_ROUTE,
  PASSWORD_SETTINGS_ROUTE,
  SEARCH_SETTINGS_ROUTE,
  SETTINGS_CENTER_ROUTE,
  SETTINGS_DETAIL_ROUTE,
  SITE_CONTROLS_MANAGEMENT_ROUTE,
  SYNC_SETTINGS_ROUTE,
  THEME_PALETTE_SETTINGS_ROUTE,
  USER_AGENT_SETTINGS_ROUTE,
  USER_SCRIPTS_ROUTE,
  WEBPAGE_TRANSLATION_SETTINGS_ROUTE
} from './AppRoutes';
import { BrowserPrivateBoundaryRouteParams } from '../../core/browser/BrowserPrivateBoundaryNavigationService';

export type AiraAppShortcutTarget =
  'bookmarks' |
  'history' |
  'history_stress_50000' |
  'downloads' |
  'settings' |
  'search' |
  'scanQr' |
  'saved_pages' |
  'sync' |
  'aira_pro' |
  'search_settings' |
  'ad_block_settings' |
  'site_settings' |
  'webpage_translation_settings' |
  'password_settings' |
  'user_scripts' |
  'user_agent_settings' |
  'download_settings' |
  'custom_homepage_settings' |
  'general_settings' |
  'appearance_settings' |
  'appearance_toolbar_settings' |
  'privacy_security_settings' |
  'experiments_settings' |
  'about_settings' |
  'startup_settings' |
  'private_tabs_settings' |
  'history_retention_settings' |
  'theme_palette_settings' |
  'keyboard_shortcuts_settings' |
  'app_proxy_settings';

export interface AiraAppShortcutNavigationResult {
  handled: boolean;
  route: string;
  errorMessage: string;
}

interface AiraAppShortcutRouteParams extends BrowserPrivateBoundaryRouteParams {
  sectionId?: string;
  seedHistoryCount?: string;
}

export class AppShortcutNavigationCoordinator {
  openShortcut(
    target: AiraAppShortcutTarget | '',
    boundary: BrowserPrivateBoundaryRouteParams
  ): Promise<AiraAppShortcutNavigationResult> {
    const route = this.resolveRoute(target);
    if (route.length === 0) {
      const result: AiraAppShortcutNavigationResult = {
        handled: false,
        route: '',
        errorMessage: '未知快捷入口'
      };
      return Promise.resolve(result);
    }
    return router.pushUrl({
      url: route,
      params: this.buildRouteParams(target, boundary)
    })
      .then((): AiraAppShortcutNavigationResult => {
        return {
          handled: true,
          route: route,
          errorMessage: ''
        };
      })
      .catch((error: Error): AiraAppShortcutNavigationResult => {
        return {
          handled: false,
          route: route,
          errorMessage: JSON.stringify(error)
        };
      });
  }

  private resolveRoute(target: AiraAppShortcutTarget | ''): string {
    if (target === 'bookmarks') {
      return BOOKMARK_MANAGER_ROUTE;
    }
    if (target === 'history' || target === 'history_stress_50000') {
      return HISTORY_MANAGER_ROUTE;
    }
    if (target === 'downloads') {
      return DOWNLOAD_MANAGEMENT_ROUTE;
    }
    if (target === 'settings') {
      return SETTINGS_CENTER_ROUTE;
    }
    if (target === 'saved_pages') {
      return OFFLINE_PAGES_ROUTE;
    }
    if (target === 'sync') {
      return SYNC_SETTINGS_ROUTE;
    }
    if (target === 'aira_pro') {
      return AIRA_PRO_ROUTE;
    }
    if (target === 'search_settings') {
      return SEARCH_SETTINGS_ROUTE;
    }
    if (target === 'ad_block_settings') {
      return AD_BLOCK_SETTINGS_ROUTE;
    }
    if (target === 'site_settings') {
      return SITE_CONTROLS_MANAGEMENT_ROUTE;
    }
    if (target === 'webpage_translation_settings') {
      return WEBPAGE_TRANSLATION_SETTINGS_ROUTE;
    }
    if (target === 'password_settings') {
      return PASSWORD_SETTINGS_ROUTE;
    }
    if (target === 'user_scripts') {
      return USER_SCRIPTS_ROUTE;
    }
    if (target === 'user_agent_settings') {
      return USER_AGENT_SETTINGS_ROUTE;
    }
    if (target === 'download_settings') {
      return DOWNLOAD_SETTINGS_ROUTE;
    }
    if (target === 'custom_homepage_settings') {
      return CUSTOM_HOMEPAGE_SETTINGS_ROUTE;
    }
    if (target === 'startup_settings') {
      return GENERAL_STARTUP_SETTINGS_ROUTE;
    }
    if (target === 'private_tabs_settings') {
      return GENERAL_PRIVATE_TABS_SETTINGS_ROUTE;
    }
    if (target === 'history_retention_settings') {
      return GENERAL_HISTORY_RETENTION_SETTINGS_ROUTE;
    }
    if (target === 'theme_palette_settings') {
      return THEME_PALETTE_SETTINGS_ROUTE;
    }
    if (target === 'keyboard_shortcuts_settings') {
      return KEYBOARD_SHORTCUTS_SETTINGS_ROUTE;
    }
    if (target === 'app_proxy_settings') {
      return APP_PROXY_SETTINGS_ROUTE;
    }
    if (target === 'general_settings' ||
      target === 'appearance_settings' ||
      target === 'appearance_toolbar_settings' ||
      target === 'privacy_security_settings' ||
      target === 'experiments_settings' ||
      target === 'about_settings') {
      return SETTINGS_DETAIL_ROUTE;
    }
    return '';
  }

  private buildRouteParams(
    target: AiraAppShortcutTarget | '',
    boundary: BrowserPrivateBoundaryRouteParams
  ): AiraAppShortcutRouteParams {
    const sectionId = this.resolveSettingsDetailSectionId(target);
    if (sectionId.length === 0) {
      if (target === 'history_stress_50000') {
        return {
          dataScope: boundary.dataScope,
          privacyMode: boundary.privacyMode,
          boundarySource: boundary.boundarySource,
          seedHistoryCount: '50000'
        };
      }
      return boundary;
    }
    return {
      dataScope: boundary.dataScope,
      privacyMode: boundary.privacyMode,
      boundarySource: boundary.boundarySource,
      sectionId: sectionId
    };
  }

  private resolveSettingsDetailSectionId(target: AiraAppShortcutTarget | ''): string {
    switch (target) {
      case 'general_settings':
        return 'general';
      case 'appearance_toolbar_settings':
      case 'appearance_settings':
        return 'appearance_toolbar';
      case 'privacy_security_settings':
        return 'privacy_security';
      case 'experiments_settings':
        return 'experiments';
      case 'about_settings':
        return 'about';
      default:
        return '';
    }
  }
}
