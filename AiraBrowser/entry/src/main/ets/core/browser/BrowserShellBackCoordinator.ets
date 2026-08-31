import { BrowserTransientSurfaceBackTarget } from './BrowserTransientSurfaceCoordinator';

export type BrowserShellBackAction =
  'cancel_manual_element_hide' |
  'dismiss_translation_language_sheet' |
  'handle_bookmark_folder_selection_back' |
  'dismiss_app_proxy_quick_sheet' |
  'handle_web_page_tools_sheet_back' |
  'close_element_inspection' |
  'dismiss_reader_image_preview' |
  'dismiss_reader_panel' |
  'confirm_close_reader_mode' |
  'dismiss_novel_reader_panel' |
  'confirm_close_novel_reader' |
  'dismiss_custom_homepage_transient' |
  'close_tabs_overview' |
  'cancel_download_prompt' |
  'close_resource_candidates' |
  'close_user_script_install_sheet' |
  'dismiss_user_script_page_actions' |
  'dismiss_wifi_qr_result' |
  'dismiss_feature_gate' |
  'handle_home_shortcut_selection_back' |
  'close_desktop_login_sheet' |
  'close_system_sheet' |
  'acknowledge_release_notice' |
  'dismiss_external_navigation_prompt' |
  'dismiss_search_invocation' |
  'pass_through';

export interface BrowserShellBackState {
  manualElementHideSelectionActive: boolean;
  managedSurfaceBackTarget?: BrowserTransientSurfaceBackTarget;
  largeScreenOmniboxEditing: boolean;
  readerModeVisible: boolean;
  readerModeImagePreviewVisible: boolean;
  readerModePanelVisible: boolean;
  novelReaderVisible: boolean;
  novelReaderPanelVisible: boolean;
  customHomepageTransientBackActive: boolean;
  tabsSheetVisible: boolean;
  downloadPromptGuid: string;
  externalNavigationPromptVisible: boolean;
}

export class BrowserShellBackCoordinator {
  resolveBackAction(state: BrowserShellBackState): BrowserShellBackAction {
    if (state.manualElementHideSelectionActive) {
      return 'cancel_manual_element_hide';
    }
    if (state.downloadPromptGuid.length > 0) {
      return 'cancel_download_prompt';
    }
    const managedSurfaceAction = this.resolveManagedSurfaceBackAction(
      state.managedSurfaceBackTarget
    );
    if (managedSurfaceAction !== 'pass_through') {
      return managedSurfaceAction;
    }
    if (state.largeScreenOmniboxEditing) {
      return 'dismiss_search_invocation';
    }
    if (state.readerModeVisible) {
      if (state.readerModeImagePreviewVisible) {
        return 'dismiss_reader_image_preview';
      }
      if (state.readerModePanelVisible) {
        return 'dismiss_reader_panel';
      }
      return 'confirm_close_reader_mode';
    }
    if (state.novelReaderVisible) {
      if (state.novelReaderPanelVisible) {
        return 'dismiss_novel_reader_panel';
      }
      return 'confirm_close_novel_reader';
    }
    if (state.customHomepageTransientBackActive) {
      return 'dismiss_custom_homepage_transient';
    }
    if (state.tabsSheetVisible) {
      return 'close_tabs_overview';
    }
    if (state.externalNavigationPromptVisible) {
      return 'dismiss_external_navigation_prompt';
    }
    return 'pass_through';
  }

  private resolveManagedSurfaceBackAction(
    target: BrowserTransientSurfaceBackTarget | undefined
  ): BrowserShellBackAction {
    if (target === undefined || target.disposition === 'none') {
      return 'pass_through';
    }
    if (target.lane === 'system_sheet') {
      if (target.type === 'homeShortcutSelection') {
        return 'handle_home_shortcut_selection_back';
      }
      if (target.type === 'desktopLoginConfirm') {
        return 'close_desktop_login_sheet';
      }
      if (target.type === 'userScriptInstall') {
        return 'close_user_script_install_sheet';
      }
      return target.type === 'releaseNotice' ? 'acknowledge_release_notice' : 'close_system_sheet';
    }
    if (target.surfaceId === 'translation_target_language') {
      return 'dismiss_translation_language_sheet';
    }
    if (target.surfaceId === 'bookmark_folder_selection') {
      return 'handle_bookmark_folder_selection_back';
    }
    if (target.surfaceId === 'app_proxy_quick') {
      return 'dismiss_app_proxy_quick_sheet';
    }
    if (target.surfaceId === 'web_page_tools') {
      return 'handle_web_page_tools_sheet_back';
    }
    if (target.surfaceId === 'element_inspection') {
      return 'close_element_inspection';
    }
    if (target.surfaceId === 'resource_candidates') {
      return 'close_resource_candidates';
    }
    if (target.surfaceId === 'userscript_page_actions') {
      return 'dismiss_user_script_page_actions';
    }
    if (target.surfaceId === 'wifi_qr_result') {
      return 'dismiss_wifi_qr_result';
    }
    if (target.surfaceId === 'feature_gate') {
      return 'dismiss_feature_gate';
    }
    return 'pass_through';
  }
}
