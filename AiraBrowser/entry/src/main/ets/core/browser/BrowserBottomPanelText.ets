import { BrowserBottomPanelActionId } from './BrowserBottomPanelActionCatalog';

export function resourceStrPresent(value: ResourceStr | undefined): boolean {
  if (value === undefined) {
    return false;
  }
  if (typeof value === 'string') {
    return value.trim().length > 0;
  }
  return true;
}

export function resourceStrKey(value: ResourceStr | undefined): string {
  if (value === undefined) {
    return '';
  }
  if (typeof value === 'string') {
    return value;
  }
  return `r:${value.id}`;
}

export function sameResourceStr(left: ResourceStr, right: ResourceStr): boolean {
  return resourceStrKey(left) === resourceStrKey(right);
}

export function bottomPanelActionTitle(actionId: BrowserBottomPanelActionId): Resource {
  switch (actionId) {
    case 'bookmark':
      return $r('app.string.bottom_panel_action_bookmark');
    case 'scanQr':
      return $r('app.string.bottom_panel_action_scan_qr');
    case 'openBookmarks':
      return $r('app.string.bottom_panel_action_open_bookmarks');
    case 'scripts':
      return $r('app.string.bottom_panel_action_scripts');
    case 'find':
      return $r('app.string.bottom_panel_action_find');
    case 'settings':
      return $r('app.string.bottom_panel_action_settings');
    case 'appProxySettings':
      return $r('app.string.bottom_panel_action_app_proxy_settings');
    case 'home':
      return $r('app.string.bottom_panel_action_home');
    case 'share':
      return $r('app.string.bottom_panel_action_share');
    case 'sendToDesktop':
      return $r('app.string.bottom_panel_action_send_to_desktop');
    case 'print':
      return $r('app.string.bottom_panel_action_print');
    case 'copyLink':
      return $r('app.string.bottom_panel_action_copy_link');
    case 'addToDesktop':
      return $r('app.string.bottom_panel_action_add_to_desktop');
    case 'userAgent':
      return $r('app.string.bottom_panel_action_user_agent');
    case 'textZoom':
      return $r('app.string.bottom_panel_action_text_zoom');
    case 'webZoom':
      return $r('app.string.bottom_panel_action_web_zoom');
    case 'userAgentPreset':
      return $r('app.string.bottom_panel_action_user_agent_preset');
    case 'screenOrientation':
      return $r('app.string.bottom_panel_action_screen_orientation');
    case 'themeMode':
      return $r('app.string.bottom_panel_action_theme_mode');
    case 'fullScreenMode':
      return $r('app.string.bottom_panel_action_full_screen_mode');
    case 'manualElementHide':
      return $r('app.string.bottom_panel_action_manual_element_hide');
    case 'elementInspection':
      return $r('app.string.bottom_panel_action_element_inspection');
    case 'translate':
      return $r('app.string.bottom_panel_action_translate');
    case 'reader':
      return $r('app.string.bottom_panel_action_reader');
    case 'novel':
      return $r('app.string.bottom_panel_action_novel');
    case 'video':
      return $r('app.string.bottom_panel_action_video');
    case 'offline':
      return $r('app.string.bottom_panel_action_offline');
    case 'savedPages':
      return $r('app.string.bottom_panel_action_saved_pages');
    case 'downloads':
      return $r('app.string.bottom_panel_action_downloads');
    case 'history':
      return $r('app.string.bottom_panel_action_history');
    case 'siteInfo':
      return $r('app.string.bottom_panel_action_site_info');
    case 'reportSite':
      return $r('app.string.bottom_panel_action_report_site');
    case 'openOriginal':
      return $r('app.string.bottom_panel_action_open_original');
    case 'details':
      return $r('app.string.bottom_panel_action_details');
    case 'exportPage':
      return $r('app.string.bottom_panel_action_export_page');
    case 'deletePage':
      return $r('app.string.bottom_panel_action_delete_page');
    case 'decreaseFont':
      return $r('app.string.bottom_panel_action_decrease_font');
    case 'increaseFont':
      return $r('app.string.bottom_panel_action_increase_font');
    case 'theme':
      return $r('app.string.bottom_panel_action_theme');
    case 'readAloud':
      return $r('app.string.bottom_panel_action_read_aloud');
    case 'lineHeight':
      return $r('app.string.bottom_panel_action_line_height');
    case 'pageWidth':
      return $r('app.string.bottom_panel_action_page_width');
    case 'viewerInfo':
      return $r('app.string.bottom_panel_action_viewer_info');
    case 'newTab':
      return $r('app.string.bottom_panel_action_new_tab');
    case 'newPrivateTab':
      return $r('app.string.bottom_panel_action_new_private_tab');
    case 'closeAllTabs':
      return $r('app.string.bottom_panel_action_close_all_tabs');
    case 'clearHistory':
      return $r('app.string.bottom_panel_action_clear_history');
    default:
      return $r('app.string.bottom_panel_tool');
  }
}

export function bottomPanelActionSubtitle(actionId: BrowserBottomPanelActionId): Resource {
  switch (actionId) {
    case 'bookmark':
      return $r('app.string.bottom_panel_action_bookmark_subtitle');
    case 'scanQr':
      return $r('app.string.bottom_panel_action_scan_qr_subtitle');
    case 'openBookmarks':
      return $r('app.string.bottom_panel_action_open_bookmarks_subtitle');
    case 'scripts':
      return $r('app.string.bottom_panel_action_scripts_subtitle');
    case 'find':
      return $r('app.string.bottom_panel_action_find_subtitle');
    case 'settings':
      return $r('app.string.bottom_panel_action_settings_subtitle');
    case 'appProxySettings':
      return $r('app.string.bottom_panel_action_app_proxy_settings_subtitle');
    case 'home':
      return $r('app.string.bottom_panel_action_home_subtitle');
    case 'share':
      return $r('app.string.web_page_share_options');
    case 'sendToDesktop':
      return $r('app.string.bottom_panel_action_send_to_desktop_subtitle');
    case 'print':
      return $r('app.string.bottom_panel_action_print_subtitle');
    case 'copyLink':
      return $r('app.string.bottom_panel_action_copy_link_subtitle');
    case 'addToDesktop':
      return $r('app.string.bottom_panel_action_add_to_desktop_subtitle');
    case 'userAgent':
      return $r('app.string.bottom_panel_action_user_agent_subtitle');
    case 'textZoom':
      return $r('app.string.bottom_panel_action_text_zoom_subtitle');
    case 'webZoom':
      return $r('app.string.bottom_panel_action_web_zoom_subtitle');
    case 'userAgentPreset':
      return $r('app.string.bottom_panel_action_user_agent_preset_subtitle');
    case 'screenOrientation':
      return $r('app.string.bottom_panel_action_screen_orientation_subtitle');
    case 'themeMode':
      return $r('app.string.bottom_panel_action_theme_mode_subtitle');
    case 'fullScreenMode':
      return $r('app.string.bottom_panel_action_full_screen_mode_subtitle');
    case 'manualElementHide':
      return $r('app.string.bottom_panel_action_manual_element_hide_subtitle');
    case 'elementInspection':
      return $r('app.string.bottom_panel_action_element_inspection_subtitle');
    case 'translate':
      return $r('app.string.bottom_panel_action_translate_subtitle');
    case 'reader':
      return $r('app.string.bottom_panel_action_reader_subtitle');
    case 'novel':
      return $r('app.string.bottom_panel_action_novel_subtitle');
    case 'video':
      return $r('app.string.bottom_panel_action_video_subtitle');
    case 'offline':
      return $r('app.string.bottom_panel_action_offline_subtitle');
    case 'savedPages':
      return $r('app.string.bottom_panel_action_saved_pages_subtitle');
    case 'downloads':
      return $r('app.string.bottom_panel_action_downloads_subtitle');
    case 'history':
      return $r('app.string.bottom_panel_action_history_subtitle');
    case 'siteInfo':
      return $r('app.string.bottom_panel_action_site_info_subtitle');
    case 'reportSite':
      return $r('app.string.bottom_panel_action_report_site_subtitle');
    case 'openOriginal':
      return $r('app.string.bottom_panel_action_open_original_subtitle');
    case 'details':
      return $r('app.string.bottom_panel_action_details_subtitle');
    case 'exportPage':
      return $r('app.string.bottom_panel_action_export_page_subtitle');
    case 'deletePage':
      return $r('app.string.bottom_panel_action_delete_page_subtitle');
    case 'decreaseFont':
      return $r('app.string.bottom_panel_action_decrease_font_subtitle');
    case 'increaseFont':
      return $r('app.string.bottom_panel_action_increase_font_subtitle');
    case 'theme':
      return $r('app.string.bottom_panel_action_theme_subtitle');
    case 'readAloud':
      return $r('app.string.bottom_panel_action_read_aloud_subtitle');
    case 'lineHeight':
      return $r('app.string.bottom_panel_action_line_height_subtitle');
    case 'pageWidth':
      return $r('app.string.bottom_panel_action_page_width_subtitle');
    case 'viewerInfo':
      return $r('app.string.bottom_panel_action_viewer_info_subtitle');
    case 'newTab':
      return $r('app.string.bottom_panel_action_new_tab_subtitle');
    case 'newPrivateTab':
      return $r('app.string.bottom_panel_action_new_private_tab_subtitle');
    case 'closeAllTabs':
      return $r('app.string.bottom_panel_action_close_all_tabs_subtitle');
    case 'clearHistory':
      return $r('app.string.bottom_panel_action_clear_history_subtitle');
    default:
      return $r('app.string.bottom_panel_tool');
  }
}

export function bottomPanelReleasePrompt(actionId: string): Resource {
  switch (actionId) {
    case 'webBack':
      return $r('app.string.bottom_panel_release_back');
    case 'webForward':
      return $r('app.string.bottom_panel_release_forward');
    case 'bottomChromeMenu':
      return $r('app.string.bottom_panel_release_toolbar');
    case 'webReload':
      return $r('app.string.bottom_panel_release_reload');
    case 'openTabs':
      return $r('app.string.bottom_panel_release_tabs');
    case 'bookmark':
      return $r('app.string.bottom_panel_release_bookmark');
    case 'scanQr':
      return $r('app.string.bottom_panel_release_scan_qr');
    case 'openBookmarks':
      return $r('app.string.bottom_panel_release_open_bookmarks');
    case 'scripts':
      return $r('app.string.bottom_panel_release_scripts');
    case 'find':
      return $r('app.string.bottom_panel_release_find');
    case 'settings':
      return $r('app.string.bottom_panel_release_settings');
    case 'appProxySettings':
      return $r('app.string.bottom_panel_release_app_proxy_settings');
    case 'home':
      return $r('app.string.bottom_panel_release_home');
    case 'share':
      return $r('app.string.bottom_panel_release_share');
    case 'sendToDesktop':
      return $r('app.string.bottom_panel_release_send_to_desktop');
    case 'print':
      return $r('app.string.bottom_panel_release_print');
    case 'copyLink':
      return $r('app.string.bottom_panel_release_copy_link');
    case 'addToDesktop':
      return $r('app.string.bottom_panel_release_add_to_desktop');
    case 'userAgent':
      return $r('app.string.bottom_panel_release_user_agent');
    case 'textZoom':
      return $r('app.string.bottom_panel_release_text_zoom');
    case 'webZoom':
      return $r('app.string.bottom_panel_release_web_zoom');
    case 'userAgentPreset':
      return $r('app.string.bottom_panel_release_user_agent_preset');
    case 'screenOrientation':
      return $r('app.string.bottom_panel_release_screen_orientation');
    case 'themeMode':
      return $r('app.string.bottom_panel_release_theme_mode');
    case 'fullScreenMode':
      return $r('app.string.bottom_panel_release_full_screen_mode');
    case 'manualElementHide':
      return $r('app.string.bottom_panel_release_manual_element_hide');
    case 'elementInspection':
      return $r('app.string.bottom_panel_release_element_inspection');
    case 'translate':
      return $r('app.string.bottom_panel_release_translate');
    case 'reader':
      return $r('app.string.bottom_panel_release_reader');
    case 'novel':
      return $r('app.string.bottom_panel_release_novel');
    case 'video':
      return $r('app.string.bottom_panel_release_video');
    case 'offline':
      return $r('app.string.bottom_panel_release_offline');
    case 'savedPages':
      return $r('app.string.bottom_panel_release_saved_pages');
    case 'downloads':
      return $r('app.string.bottom_panel_release_downloads');
    case 'history':
      return $r('app.string.bottom_panel_release_history');
    case 'siteInfo':
      return $r('app.string.bottom_panel_release_site_info');
    case 'reportSite':
      return $r('app.string.bottom_panel_release_report_site');
    case 'openOriginal':
      return $r('app.string.bottom_panel_release_open_original');
    case 'details':
      return $r('app.string.bottom_panel_release_details');
    case 'exportPage':
      return $r('app.string.bottom_panel_release_export_page');
    case 'deletePage':
      return $r('app.string.bottom_panel_release_delete_page');
    case 'decreaseFont':
      return $r('app.string.bottom_panel_release_decrease_font');
    case 'increaseFont':
      return $r('app.string.bottom_panel_release_increase_font');
    case 'theme':
      return $r('app.string.bottom_panel_release_theme');
    case 'readAloud':
      return $r('app.string.bottom_panel_release_read_aloud');
    case 'lineHeight':
      return $r('app.string.bottom_panel_release_line_height');
    case 'pageWidth':
      return $r('app.string.bottom_panel_release_page_width');
    case 'viewerInfo':
      return $r('app.string.bottom_panel_release_viewer_info');
    case 'newTab':
      return $r('app.string.bottom_panel_release_new_tab');
    case 'newPrivateTab':
      return $r('app.string.bottom_panel_release_new_private_tab');
    case 'closeAllTabs':
      return $r('app.string.bottom_panel_release_close_all_tabs');
    case 'clearHistory':
      return $r('app.string.bottom_panel_release_clear_history');
    default:
      return $r('app.string.bottom_panel_release_open_home');
  }
}

export function bottomPanelHideRuleCount(count: number): Resource {
  return $r('app.plural.bottom_panel_hide_rule_count', count, count);
}

export function bottomPanelExitPrivate(): Resource {
  return $r('app.string.bottom_panel_exit_private');
}

export function bottomPanelExit(): Resource {
  return $r('app.string.bottom_panel_exit');
}

export function bottomPanelExitFullScreen(): Resource {
  return $r('app.string.bottom_panel_exit_fullscreen');
}

export function bottomPanelRemoveBookmark(): Resource {
  return $r('app.string.bottom_panel_remove_bookmark');
}

export function bottomPanelFindUnavailable(): Resource {
  return $r('app.string.bottom_panel_find_unavailable');
}

export function bottomPanelHideAdsUnavailable(): Resource {
  return $r('app.string.bottom_panel_hide_ads_unavailable');
}

export function bottomPanelInspectUnavailable(): Resource {
  return $r('app.string.bottom_panel_inspect_unavailable');
}

export function bottomPanelSaveUnavailable(): Resource {
  return $r('app.string.bottom_panel_save_unavailable');
}

export function bottomPanelBookmarkUnavailable(): Resource {
  return $r('app.string.bottom_panel_bookmark_unavailable');
}

export function bottomPanelPrivateBookmarkUnavailable(): Resource {
  return $r('app.string.bottom_panel_private_bookmark_unavailable');
}

export function bottomPanelArticleLinkUnavailable(): Resource {
  return $r('app.string.bottom_panel_article_link_unavailable');
}

export function bottomPanelArticlePrivateBookmarkUnavailable(): Resource {
  return $r('app.string.bottom_panel_article_private_bookmark_unavailable');
}

export function bottomPanelOpenPageFirst(): Resource {
  return $r('app.string.bottom_panel_open_page_first');
}

export function bottomPanelZoomUnavailable(): Resource {
  return $r('app.string.bottom_panel_zoom_unavailable');
}

export function bottomPanelActionUnavailable(): Resource {
  return $r('app.string.bottom_panel_action_unavailable');
}

export function bottomPanelToolbarUnavailable(): Resource {
  return $r('app.string.bottom_panel_toolbar_unavailable');
}

export function bottomPanelNewTabUnavailable(): Resource {
  return $r('app.string.bottom_panel_new_tab_unavailable');
}

export function bottomPanelThemePage(): Resource {
  return $r('app.string.bottom_panel_theme_page');
}

export function bottomPanelThemeUpdateFailed(): Resource {
  return $r('app.string.bottom_panel_theme_update_failed');
}

export function bottomPanelToolbarUpdateFailed(): Resource {
  return $r('app.string.bottom_panel_toolbar_update_failed');
}

export function bottomPanelNoEditableAddress(): Resource {
  return $r('app.string.bottom_panel_no_editable_address');
}

export function bottomPanelContinueReading(): Resource {
  return $r('app.string.bottom_panel_continue_reading');
}

export function bottomPanelContinueReadingA11y(title: string): Resource {
  return $r('app.string.bottom_panel_continue_reading_a11y', title);
}

export function bottomPanelAccountCapsuleA11y(label: string): Resource {
  return $r('app.string.bottom_panel_account_capsule_a11y', label);
}

export function bottomPanelBack(): Resource {
  return $r('app.string.bottom_panel_back');
}

export function bottomPanelForward(): Resource {
  return $r('app.string.bottom_panel_forward');
}

export function bottomPanelReload(): Resource {
  return $r('app.string.bottom_panel_reload');
}

export function bottomPanelTabs(): Resource {
  return $r('app.string.bottom_panel_tabs');
}

export function bottomPanelMenu(): Resource {
  return $r('app.string.bottom_panel_menu');
}

export function bottomPanelNewTabPage(): Resource {
  return $r('app.string.bottom_panel_new_tab_page');
}

export function bottomPanelCoreBackSubtitle(): Resource {
  return $r('app.string.bottom_panel_core_back_subtitle');
}

export function bottomPanelCoreForwardSubtitle(): Resource {
  return $r('app.string.bottom_panel_core_forward_subtitle');
}

export function bottomPanelCoreMenuSubtitle(): Resource {
  return $r('app.string.bottom_panel_core_menu_subtitle');
}

export function bottomPanelCoreReloadSubtitle(): Resource {
  return $r('app.string.bottom_panel_core_reload_subtitle');
}

export function bottomPanelCoreTabsSubtitle(): Resource {
  return $r('app.string.bottom_panel_core_tabs_subtitle');
}

export function bottomPanelCoreNewTabSubtitle(): Resource {
  return $r('app.string.bottom_panel_core_new_tab_subtitle');
}

export function bottomPanelNone(): Resource {
  return $r('app.string.bottom_panel_none');
}

export function bottomPanelNoneSubtitle(): Resource {
  return $r('app.string.bottom_panel_none_subtitle');
}

export function bottomPanelOpenTools(): Resource {
  return $r('app.string.bottom_panel_open_tools');
}

export function bottomPanelOpenTabsPage(): Resource {
  return $r('app.string.bottom_panel_open_tabs_page');
}

export function bottomPanelPinnedAs(): Resource {
  return $r('app.string.bottom_panel_pinned_as');
}

export function bottomPanelSlotTitle(slotId: string): Resource {
  switch (slotId) {
    case 'menu':
      return $r('app.string.bottom_panel_slot_menu');
    case 'refresh':
      return $r('app.string.bottom_panel_slot_refresh');
    case 'tabs':
      return $r('app.string.bottom_panel_slot_tabs');
    case 'leading':
    default:
      return $r('app.string.bottom_panel_slot_leading');
  }
}

export function bottomPanelInteractionTitle(kind: string): Resource {
  if (kind === 'longPress') {
    return $r('app.string.bottom_panel_interaction_long_press');
  }
  if (kind === 'swipeUp') {
    return $r('app.string.bottom_panel_interaction_swipe_up');
  }
  return $r('app.string.bottom_panel_interaction_tap');
}

export function bottomPanelPickerBrowser(): Resource {
  return $r('app.string.bottom_panel_picker_browser');
}

export function bottomPanelPickerToolbar(): Resource {
  return $r('app.string.bottom_panel_picker_toolbar');
}

export function bottomPanelCustomizeSlot(slotId: string): Resource {
  switch (slotId) {
    case 'menu':
      return $r('app.string.bottom_panel_customize_menu');
    case 'refresh':
      return $r('app.string.bottom_panel_customize_refresh');
    case 'tabs':
      return $r('app.string.bottom_panel_customize_tabs');
    case 'leading':
    default:
      return $r('app.string.bottom_panel_customize_leading');
  }
}

export function bottomPanelHideSearchContinue(): Resource {
  return $r('app.string.bottom_panel_hide_search_continue');
}

export function bottomPanelReleaseHide(): Resource {
  return $r('app.string.bottom_panel_release_hide');
}

export function bottomPanelReleaseOpenHome(): Resource {
  return $r('app.string.bottom_panel_release_open_home');
}

export function bottomPanelGroupReading(): Resource {
  return $r('app.string.bottom_panel_group_reading');
}

export function bottomPanelGroupMedia(): Resource {
  return $r('app.string.bottom_panel_group_media');
}

export function bottomPanelGroupDevelopment(): Resource {
  return $r('app.string.bottom_panel_group_development');
}

export function bottomPanelManageScripts(): Resource {
  return $r('app.string.bottom_panel_manage_scripts');
}

export function bottomPanelWebZoom(): Resource {
  return $r('app.string.bottom_panel_web_zoom');
}

export function bottomPanelPageTools(): Resource {
  return $r('app.string.bottom_panel_page_tools');
}

export function bottomPanelHomeUnavailable(actionId: string): Resource {
  switch (actionId) {
    case 'video':
      return $r('app.string.bottom_panel_home_no_media');
    case 'bookmark':
      return $r('app.string.bottom_panel_home_no_bookmark');
    case 'copyLink':
      return $r('app.string.bottom_panel_home_no_link');
    case 'share':
      return $r('app.string.bottom_panel_home_no_share');
    case 'sendToDesktop':
      return $r('app.string.bottom_panel_home_no_send');
    case 'print':
      return $r('app.string.bottom_panel_home_no_print');
    case 'find':
      return $r('app.string.bottom_panel_home_no_find');
    case 'reader':
      return $r('app.string.bottom_panel_home_no_reader');
    case 'translate':
      return $r('app.string.bottom_panel_home_no_translate');
    case 'offline':
      return $r('app.string.bottom_panel_home_no_save');
    case 'siteInfo':
      return $r('app.string.bottom_panel_home_no_site_info');
    case 'addToDesktop':
      return $r('app.string.bottom_panel_home_no_install');
    case 'manualElementHide':
      return $r('app.string.bottom_panel_home_no_hide_ads');
    case 'textZoom':
      return $r('app.string.bottom_panel_home_text_zoom');
    case 'webZoom':
      return $r('app.string.bottom_panel_home_web_zoom');
    default:
      return $r('app.string.bottom_panel_home_tool');
  }
}

export function bottomPanelThemeTitle(mode: string): Resource {
  if (mode === 'light') {
    return $r('app.string.bottom_panel_theme_light');
  }
  if (mode === 'dark') {
    return $r('app.string.bottom_panel_theme_dark');
  }
  return $r('app.string.bottom_panel_theme_system');
}

export function bottomPanelThemeSwitched(mode: string): Resource {
  if (mode === 'light') {
    return $r('app.string.bottom_panel_theme_switched_light');
  }
  if (mode === 'dark') {
    return $r('app.string.bottom_panel_theme_switched_dark');
  }
  return $r('app.string.bottom_panel_theme_switched_system');
}

