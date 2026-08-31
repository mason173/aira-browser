import {
  BrowserAppServiceMode,
  BrowserAppearanceSettings,
  BrowserExperimentSettings,
  BrowserThemeMode,
  SearchEngineId,
  SitePermissionKind
} from '../../common/models/BrowserModels';
import { SettingsDetailRowAction } from './SettingsDetailViewModel';

export class SettingsDetailActionResolver {
  resolveThemeMode(action: SettingsDetailRowAction): BrowserThemeMode | undefined {
    if (action === 'set_theme_light') {
      return 'light';
    }
    if (action === 'set_theme_dark') {
      return 'dark';
    }
    if (action === 'set_theme_system') {
      return 'system';
    }
    return undefined;
  }

  resolveSearchEngine(action: SettingsDetailRowAction): SearchEngineId | undefined {
    if (action === 'set_search_google') {
      return 'google';
    }
    if (action === 'set_search_duckduckgo') {
      return 'duckduckgo';
    }
    if (action === 'set_search_baidu') {
      return 'baidu';
    }
    if (action === 'set_search_bing') {
      return 'bing';
    }
    if (action === 'set_search_qihoo') {
      return 'qihoo';
    }
    if (action === 'set_search_sogou') {
      return 'sogou';
    }
    if (action === 'set_search_shenma') {
      return 'shenma';
    }
    if (action === 'set_search_brave') {
      return 'brave';
    }
    if (action === 'set_search_startpage') {
      return 'startpage';
    }
    if (action === 'set_search_ecosia') {
      return 'ecosia';
    }
    if (action === 'set_search_yandex') {
      return 'yandex';
    }
    return undefined;
  }

  resolveAppServiceMode(action: SettingsDetailRowAction): BrowserAppServiceMode | undefined {
    if (action === 'set_app_service_mode_full') {
      return 'full';
    }
    if (action === 'set_app_service_mode_basic') {
      return 'basic';
    }
    return undefined;
  }

  resolveSitePermissionDefaultKind(action: SettingsDetailRowAction): SitePermissionKind | undefined {
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

  buildAppearanceSettingsForAction(
    action: SettingsDetailRowAction,
    nextChecked: boolean,
    current: BrowserAppearanceSettings
  ): BrowserAppearanceSettings | undefined {
    if (action === 'toggle_global_immersion') {
      return this.copyAppearanceSettings(current, {
        globalImmersionEnabled: nextChecked,
        alwaysTopImmersionEnabled: nextChecked ? false : current.alwaysTopImmersionEnabled
      });
    }
    if (action === 'toggle_always_top_immersion') {
      return this.copyAppearanceSettings(current, {
        alwaysTopImmersionEnabled: nextChecked,
        globalImmersionEnabled: nextChecked ? false : current.globalImmersionEnabled
      });
    }
    if (action === 'toggle_force_dark_web_content') {
      return this.copyAppearanceSettings(current, { forceDarkWebContentEnabled: nextChecked });
    }
    if (action === 'toggle_blur_private_tab_previews') {
      return this.copyAppearanceSettings(current, { blurPrivateTabPreviews: nextChecked });
    }
    if (action === 'toggle_desktop_bookmark_bar') {
      return this.copyAppearanceSettings(current, { showDesktopBookmarkBar: nextChecked });
    }
    return undefined;
  }

  buildExperimentSettingsForAction(
    action: SettingsDetailRowAction,
    nextChecked: boolean,
    current: BrowserExperimentSettings
  ): BrowserExperimentSettings | undefined {
    if (action === 'toggle_pause_web_animations_during_scroll') {
      return this.copyExperimentSettings(current, { pauseWebAnimationsDuringScroll: nextChecked });
    }
    if (action === 'toggle_reduce_media_motion_during_scroll') {
      return this.copyExperimentSettings(current, { reduceMediaMotionDuringScroll: nextChecked });
    }
    if (action === 'toggle_strengthen_ad_blocking_for_smooth_scroll') {
      return this.copyExperimentSettings(current, { strengthenAdBlockingForSmoothScroll: nextChecked });
    }
    if (action === 'toggle_pull_refresh') {
      return this.copyExperimentSettings(current, { pullRefreshEnabled: nextChecked });
    }
    if (action === 'toggle_force_enable_web_zoom') {
      return this.copyExperimentSettings(current, { forceEnableWebZoom: nextChecked });
    }
    if (action === 'toggle_smart_grip_tabs_actions') {
      return this.copyExperimentSettings(current, { smartGripTabsActionsEnabled: nextChecked });
    }
    if (action === 'toggle_web_video_takeover') {
      return this.copyExperimentSettings(current, { webVideoTakeoverEnabled: nextChecked });
    }
    if (action === 'toggle_novel_mode') {
      return this.copyExperimentSettings(current, { novelModeEnabled: nextChecked });
    }
    if (action === 'toggle_novel_auto_takeover') {
      return this.copyExperimentSettings(current, { novelAutoTakeoverEnabled: nextChecked });
    }
    return undefined;
  }

  private copyAppearanceSettings(
    current: BrowserAppearanceSettings,
    patch: Partial<BrowserAppearanceSettings>
  ): BrowserAppearanceSettings {
    return {
      bottomToolbarScrollBehavior:
        patch.bottomToolbarScrollBehavior ?? current.bottomToolbarScrollBehavior,
      globalImmersionEnabled: patch.globalImmersionEnabled ?? current.globalImmersionEnabled,
      alwaysTopImmersionEnabled: patch.alwaysTopImmersionEnabled ?? current.alwaysTopImmersionEnabled,
      forceDarkWebContentEnabled: patch.forceDarkWebContentEnabled ?? current.forceDarkWebContentEnabled,
      blurPrivateTabPreviews: patch.blurPrivateTabPreviews ?? current.blurPrivateTabPreviews,
      showHomeRecentlyClosed: patch.showHomeRecentlyClosed ?? current.showHomeRecentlyClosed,
      showHomeShortcuts: patch.showHomeShortcuts ?? current.showHomeShortcuts,
      homeRecentlyClosedLimit: patch.homeRecentlyClosedLimit ?? current.homeRecentlyClosedLimit,
      homeShortcutLayoutDensity: patch.homeShortcutLayoutDensity ?? current.homeShortcutLayoutDensity,
      homeShortcutIconSizeRatio: patch.homeShortcutIconSizeRatio ?? current.homeShortcutIconSizeRatio,
      siteIconCornerRadiusRatio: patch.siteIconCornerRadiusRatio ?? current.siteIconCornerRadiusRatio,
      themePaletteId: patch.themePaletteId ?? current.themePaletteId,
      tabsOverviewLayoutStyle: patch.tabsOverviewLayoutStyle ?? current.tabsOverviewLayoutStyle,
      tabsOverviewCloseButtonAlwaysVisible: patch.tabsOverviewCloseButtonAlwaysVisible ??
        current.tabsOverviewCloseButtonAlwaysVisible,
      showDesktopBookmarkBar: patch.showDesktopBookmarkBar ?? current.showDesktopBookmarkBar
    };
  }

  private copyExperimentSettings(
    current: BrowserExperimentSettings,
    patch: Partial<BrowserExperimentSettings>
  ): BrowserExperimentSettings {
    return {
      pauseWebAnimationsDuringScroll:
        patch.pauseWebAnimationsDuringScroll ?? current.pauseWebAnimationsDuringScroll,
      reduceMediaMotionDuringScroll:
        patch.reduceMediaMotionDuringScroll ?? current.reduceMediaMotionDuringScroll,
      strengthenAdBlockingForSmoothScroll:
        patch.strengthenAdBlockingForSmoothScroll ?? current.strengthenAdBlockingForSmoothScroll,
      pullRefreshEnabled: patch.pullRefreshEnabled ?? current.pullRefreshEnabled,
      forceEnableWebZoom: patch.forceEnableWebZoom ?? current.forceEnableWebZoom,
      smartGripTabsActionsEnabled: patch.smartGripTabsActionsEnabled ?? current.smartGripTabsActionsEnabled,
      webVideoTakeoverEnabled: patch.webVideoTakeoverEnabled ?? current.webVideoTakeoverEnabled,
      novelModeEnabled: patch.novelModeEnabled ?? current.novelModeEnabled,
      novelAutoTakeoverEnabled: patch.novelAutoTakeoverEnabled ?? current.novelAutoTakeoverEnabled,
      appProxyActiveProfileId: patch.appProxyActiveProfileId ?? current.appProxyActiveProfileId,
      appProxyProfiles: patch.appProxyProfiles ?? current.appProxyProfiles,
      appProxyEnabled: patch.appProxyEnabled ?? current.appProxyEnabled,
      appProxy: patch.appProxy ?? current.appProxy
    };
  }

}
