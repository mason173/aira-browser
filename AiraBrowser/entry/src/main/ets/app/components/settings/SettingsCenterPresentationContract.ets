import { SitePermissionKind } from '../../../common/models/BrowserModels';
import { BrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import {
  SettingsCenterDestination,
  SettingsCenterState,
  SettingsCenterViewModel
} from '../../../core/settings/SettingsCenterViewModel';
import {
  DEFAULT_SETTINGS_CENTER_SEARCH_STATE,
  SettingsCenterSearchState,
  SettingsNavigationSnapshot
} from '../../../core/settings/SettingsDestinationNavigationOwner';
import { SettingsAccountCardState } from '../../../core/settings/SettingsAccountCardViewModel';
import {
  DEFAULT_SETTINGS_TWO_PANE_LAYOUT_STATE,
  SettingsShellLayoutState
} from '../../../core/settings/SettingsShellLayoutPolicy';
import {
  SettingsPresentationShellFamily
} from '../../../core/settings/SettingsShellPresentationCoordinator';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';

export interface SettingsCenterPresentationTheme {
  pageBackground: ResourceColor;
  surfaceBackground: ResourceColor;
  headerButtonBackground: ResourceColor;
  headerIconColor: ResourceColor;
  pressedBackground: ResourceColor;
  primaryTextColor: ResourceColor;
  secondaryTextColor: ResourceColor;
  dividerColor: ResourceColor;
  iconForegroundColor: ResourceColor;
  resolvedThemeMode: string;
  settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet;
}

export interface SettingsCenterPresentationSnapshot {
  shellFamily: SettingsPresentationShellFamily;
  showCloseButton: boolean;
  state: SettingsCenterState;
  searchState: SettingsCenterSearchState;
  navigationSnapshot: SettingsNavigationSnapshot;
  boundary: BrowserBoundaryRouteState;
  theme: SettingsCenterPresentationTheme;
  accountCard: SettingsAccountCardState;
  layoutState: SettingsShellLayoutState;
  settingsRefreshRevision: number;
}

export function createDefaultSettingsCenterPresentationSnapshot(): SettingsCenterPresentationSnapshot {
  return {
    shellFamily: 'phone',
    showCloseButton: true,
    state: new SettingsCenterViewModel().buildState(),
    searchState: DEFAULT_SETTINGS_CENTER_SEARCH_STATE,
    navigationSnapshot: new SettingsNavigationSnapshot(
      'compact', 'general', 'primary', 1, '', '', '', 'camera', []
    ),
    boundary: {
      dataScope: '',
      privacyMode: '',
      boundarySource: ''
    },
    theme: {
      pageBackground: '',
      surfaceBackground: '',
      headerButtonBackground: '',
      headerIconColor: '',
      pressedBackground: '',
      primaryTextColor: '',
      secondaryTextColor: '',
      dividerColor: '',
      iconForegroundColor: '',
      resolvedThemeMode: 'light',
      settingsIconBackgrounds: DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
    },
    accountCard: {
      title: '未登录',
      subtitle: '基础浏览权益已开启，登录后可同步账号数据',
      isLoggedIn: false,
      avatarUri: '',
      membershipBadge: 'none',
      recognitionBadge: 'none'
    },
    layoutState: DEFAULT_SETTINGS_TWO_PANE_LAYOUT_STATE,
    settingsRefreshRevision: 0
  };
}

export type SettingsCenterPresentationIntentKind =
  'close' |
  'account_action' |
  'open_app_proxy_quick' |
  'open_app_proxy_settings' |
  'open_embedded_subpage' |
  'edit_secure_dns_profile' |
  'open_user_script_gallery_source' |
  'scan_login' |
  'change_search_query' |
  'select_search_target' |
  'select_destination' |
  'back_detail' |
  'open_web_app_detail' |
  'open_web_app_permission' |
  'open_web_app_desktop_site' |
  'settings_changed';

export class SettingsCenterPresentationIntent {
  kind: SettingsCenterPresentationIntentKind;
  subpageId: string = '';
  profileId: string = '';
  url: string = '';
  query: string = '';
  targetId: string = '';
  shortcutId: string = '';
  destination: SettingsCenterDestination = 'general';
  host: string = '';
  origin: string = '';
  permissionKind: SitePermissionKind = 'camera';

  private constructor(kind: SettingsCenterPresentationIntentKind) {
    this.kind = kind;
  }

  static close(): SettingsCenterPresentationIntent {
    return new SettingsCenterPresentationIntent('close');
  }

  static accountAction(): SettingsCenterPresentationIntent {
    return new SettingsCenterPresentationIntent('account_action');
  }

  static openAppProxyQuick(): SettingsCenterPresentationIntent {
    return new SettingsCenterPresentationIntent('open_app_proxy_quick');
  }

  static openAppProxySettings(): SettingsCenterPresentationIntent {
    return new SettingsCenterPresentationIntent('open_app_proxy_settings');
  }

  static openEmbeddedSubpage(subpageId: string): SettingsCenterPresentationIntent {
    const intent = new SettingsCenterPresentationIntent('open_embedded_subpage');
    intent.subpageId = subpageId;
    return intent;
  }

  static editSecureDnsProfile(profileId: string): SettingsCenterPresentationIntent {
    const intent = new SettingsCenterPresentationIntent('edit_secure_dns_profile');
    intent.profileId = profileId;
    return intent;
  }

  static openUserScriptGallerySource(url: string): SettingsCenterPresentationIntent {
    const intent = new SettingsCenterPresentationIntent('open_user_script_gallery_source');
    intent.url = url;
    return intent;
  }

  static scanLogin(): SettingsCenterPresentationIntent {
    return new SettingsCenterPresentationIntent('scan_login');
  }

  static changeSearchQuery(query: string): SettingsCenterPresentationIntent {
    const intent = new SettingsCenterPresentationIntent('change_search_query');
    intent.query = query;
    return intent;
  }

  static selectSearchTarget(targetId: string): SettingsCenterPresentationIntent {
    const intent = new SettingsCenterPresentationIntent('select_search_target');
    intent.targetId = targetId;
    return intent;
  }

  static selectDestination(destination: SettingsCenterDestination): SettingsCenterPresentationIntent {
    const intent = new SettingsCenterPresentationIntent('select_destination');
    intent.destination = destination;
    return intent;
  }

  static backDetail(): SettingsCenterPresentationIntent {
    return new SettingsCenterPresentationIntent('back_detail');
  }

  static openWebAppDetail(shortcutId: string): SettingsCenterPresentationIntent {
    const intent = new SettingsCenterPresentationIntent('open_web_app_detail');
    intent.shortcutId = shortcutId;
    return intent;
  }

  static openWebAppPermission(
    host: string,
    origin: string,
    permissionKind: SitePermissionKind
  ): SettingsCenterPresentationIntent {
    const intent = new SettingsCenterPresentationIntent('open_web_app_permission');
    intent.host = host;
    intent.origin = origin;
    intent.permissionKind = permissionKind;
    return intent;
  }

  static openWebAppDesktopSite(host: string, origin: string): SettingsCenterPresentationIntent {
    const intent = new SettingsCenterPresentationIntent('open_web_app_desktop_site');
    intent.host = host;
    intent.origin = origin;
    return intent;
  }

  static settingsChanged(): SettingsCenterPresentationIntent {
    return new SettingsCenterPresentationIntent('settings_changed');
  }
}

export type SettingsCenterPresentationIntentDispatcher =
  (intent: SettingsCenterPresentationIntent) => void;
