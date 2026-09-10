#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PAGE_DIR_REL="AiraBrowser/entry/src/main/ets/app/pages"
PAGE_DIR="${REPO_ROOT}/${PAGE_DIR_REL}"
SHELL_PAGE_REL="${PAGE_DIR_REL}/BrowserShellPage.ets"
SHELL_PAGE="${REPO_ROOT}/${SHELL_PAGE_REL}"
MAIN_BACK_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserMainBackCoordinator.ets"
MAIN_BACK_COORDINATOR="${REPO_ROOT}/${MAIN_BACK_COORDINATOR_REL}"
SHELL_LIFECYCLE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellLifecycleCoordinator.ets"
SHELL_LIFECYCLE_COORDINATOR="${REPO_ROOT}/${SHELL_LIFECYCLE_COORDINATOR_REL}"
SETTINGS_CENTER_PAGE_REL="${PAGE_DIR_REL}/SettingsCenterPage.ets"
SETTINGS_CENTER_PAGE="${REPO_ROOT}/${SETTINGS_CENTER_PAGE_REL}"
SETTINGS_CENTER_SCREEN_REL="AiraBrowser/entry/src/main/ets/app/components/settings/SettingsCenterScreen.ets"
SETTINGS_CENTER_SCREEN="${REPO_ROOT}/${SETTINGS_CENTER_SCREEN_REL}"
SETTINGS_DETAIL_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/settings/SettingsDetailViewModel.ets"
SETTINGS_DETAIL_VIEW_MODEL="${REPO_ROOT}/${SETTINGS_DETAIL_VIEW_MODEL_REL}"
APP_SERVICE_MODE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/settings/AppServiceModeCoordinator.ets"
APP_SERVICE_MODE_COORDINATOR="${REPO_ROOT}/${APP_SERVICE_MODE_COORDINATOR_REL}"
SETTINGS_DETAIL_PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/SettingsDetailPage.ets"
SETTINGS_DETAIL_PAGE="${REPO_ROOT}/${SETTINGS_DETAIL_PAGE_REL}"
SETTINGS_INLINE_DETAIL_PANEL_REL="AiraBrowser/entry/src/main/ets/app/components/settings/SettingsInlineDetailPanel.ets"
SETTINGS_INLINE_DETAIL_PANEL="${REPO_ROOT}/${SETTINGS_INLINE_DETAIL_PANEL_REL}"
SETTINGS_DESTINATION_OWNER_REL="AiraBrowser/entry/src/main/ets/core/settings/SettingsDestinationNavigationOwner.ets"
SETTINGS_DESTINATION_OWNER="${REPO_ROOT}/${SETTINGS_DESTINATION_OWNER_REL}"
SETTINGS_DESTINATION_CATALOG_REL="AiraBrowser/entry/src/main/ets/core/settings/SettingsDestinationCatalog.ets"
SETTINGS_DESTINATION_CATALOG="${REPO_ROOT}/${SETTINGS_DESTINATION_CATALOG_REL}"
OLD_SETTINGS_SEARCH_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/settings/SettingsCenterSearchViewModel.ets"
OLD_SETTINGS_SEARCH_VIEW_MODEL="${REPO_ROOT}/${OLD_SETTINGS_SEARCH_VIEW_MODEL_REL}"
OLD_SETTINGS_LARGE_DIRECTORY_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/settings/SettingsLargeScreenDirectoryViewModel.ets"
OLD_SETTINGS_LARGE_DIRECTORY_VIEW_MODEL="${REPO_ROOT}/${OLD_SETTINGS_LARGE_DIRECTORY_VIEW_MODEL_REL}"
PRIVACY_EFFECT_POLICY_REL="AiraBrowser/entry/src/main/ets/services/privacy/BrowserPrivacyEffectPolicyService.ets"
PRIVACY_EFFECT_POLICY="${REPO_ROOT}/${PRIVACY_EFFECT_POLICY_REL}"
NATIVE_TAB_SCENE_SERVICE_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserNativeTabSceneService.ets"
NATIVE_TAB_SCENE_SERVICE="${REPO_ROOT}/${NATIVE_TAB_SCENE_SERVICE_REL}"
LARGE_SCREEN_TAB_SNAPSHOT_ADAPTER_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserLargeScreenTabSnapshotAdapter.ets"
LARGE_SCREEN_TAB_SNAPSHOT_ADAPTER="${REPO_ROOT}/${LARGE_SCREEN_TAB_SNAPSHOT_ADAPTER_REL}"
WEB_VIEWPORT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebViewportCoordinator.ets"
WEB_VIEWPORT_COORDINATOR="${REPO_ROOT}/${WEB_VIEWPORT_COORDINATOR_REL}"
WEB_TOP_CHROME_OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserWebTopChromeOverlay.ets"
WEB_TOP_CHROME_OVERLAY="${REPO_ROOT}/${WEB_TOP_CHROME_OVERLAY_REL}"
WEB_VIEWPORT_SURFACE_HOST_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserWebViewportSurfaceHost.ets"
WEB_VIEWPORT_SURFACE_HOST="${REPO_ROOT}/${WEB_VIEWPORT_SURFACE_HOST_REL}"
QUICK_SEARCH_SWITCHING_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/search/BrowserQuickSearchSwitchingCoordinator.ets"
QUICK_SEARCH_SWITCHING_COORDINATOR="${REPO_ROOT}/${QUICK_SEARCH_SWITCHING_COORDINATOR_REL}"
ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRootBottomPanelSessionCoordinator.ets"
ROOT_BOTTOM_PANEL_SESSION_COORDINATOR="${REPO_ROOT}/${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}"
TRANSIENT_SURFACE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTransientSurfaceCoordinator.ets"
TRANSIENT_SURFACE_COORDINATOR="${REPO_ROOT}/${TRANSIENT_SURFACE_COORDINATOR_REL}"
ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRootBottomPanelActionApplication.ets"
ROOT_BOTTOM_PANEL_ACTION_APPLICATION="${REPO_ROOT}/${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}"
ROOT_BOTTOM_PANEL_SHELL_ACTION_EXECUTOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRootBottomPanelShellActionExecutor.ets"
ROOT_BOTTOM_PANEL_SHELL_ACTION_EXECUTOR="${REPO_ROOT}/${ROOT_BOTTOM_PANEL_SHELL_ACTION_EXECUTOR_REL}"
WEB_LINK_CONTEXT_MENU_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/web/WebLinkContextMenuCoordinator.ets"
WEB_LINK_CONTEXT_MENU_COORDINATOR="${REPO_ROOT}/${WEB_LINK_CONTEXT_MENU_COORDINATOR_REL}"
WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL="AiraBrowser/entry/src/main/ets/core/web/WebLinkContextMenuActionApplication.ets"
WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION="${REPO_ROOT}/${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}"
DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserDownloadConfirmOverlayCoordinator.ets"
DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR="${REPO_ROOT}/${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR_REL}"
FULLSCREEN_SESSION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserFullscreenSessionCoordinator.ets"
FULLSCREEN_SESSION_COORDINATOR="${REPO_ROOT}/${FULLSCREEN_SESSION_COORDINATOR_REL}"
TABS_OVERVIEW_SESSION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabsOverviewSessionCoordinator.ets"
TABS_OVERVIEW_SESSION_COORDINATOR="${REPO_ROOT}/${TABS_OVERVIEW_SESSION_COORDINATOR_REL}"
OLD_VIDEO_FULLSCREEN_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserVideoAssistantFullscreenCoordinator.ets"
OLD_VIDEO_FULLSCREEN_COORDINATOR="${REPO_ROOT}/${OLD_VIDEO_FULLSCREEN_COORDINATOR_REL}"
NATIVE_FULLSCREEN_WINDOW_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/video/NativeVideoFullscreenWindowService.ets"
NATIVE_FULLSCREEN_WINDOW_SERVICE="${REPO_ROOT}/${NATIVE_FULLSCREEN_WINDOW_SERVICE_REL}"
ROOT_BOTTOM_PANEL_LAYOUT_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRootBottomPanelLayoutModel.ets"
ROOT_BOTTOM_PANEL_LAYOUT_MODEL="${REPO_ROOT}/${ROOT_BOTTOM_PANEL_LAYOUT_MODEL_REL}"
WINDOW_DISPLAY_VIEWPORT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWindowDisplayViewportCoordinator.ets"
WINDOW_DISPLAY_VIEWPORT_COORDINATOR="${REPO_ROOT}/${WINDOW_DISPLAY_VIEWPORT_COORDINATOR_REL}"
APP_LAYOUT_TOKENS_REL="AiraBrowser/entry/src/main/ets/app/components/common/AppLayoutTokens.ets"
APP_LAYOUT_TOKENS="${REPO_ROOT}/${APP_LAYOUT_TOKENS_REL}"
BOTTOM_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserModalBottomSheet.ets"
BOTTOM_SHEET="${REPO_ROOT}/${BOTTOM_SHEET_REL}"
SETTINGS_LAYOUT_REL="AiraBrowser/entry/src/main/ets/app/components/settings/SettingsLayout.ets"
SETTINGS_LAYOUT="${REPO_ROOT}/${SETTINGS_LAYOUT_REL}"
BOTTOM_ACTION_STATE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomPanelActionStateCoordinator.ets"
BOTTOM_ACTION_STATE_COORDINATOR="${REPO_ROOT}/${BOTTOM_ACTION_STATE_COORDINATOR_REL}"
BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomPanelActionPresentationCoordinator.ets"
BOTTOM_ACTION_PRESENTATION_COORDINATOR="${REPO_ROOT}/${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}"
BOTTOM_ADDRESS_PANEL_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomAddressPanelViewModel.ets"
BOTTOM_ADDRESS_PANEL_VIEW_MODEL="${REPO_ROOT}/${BOTTOM_ADDRESS_PANEL_VIEW_MODEL_REL}"
BOTTOM_PANEL_MOTION_TOKENS_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomPanelMotionTokens.ets"
BOTTOM_PANEL_MOTION_TOKENS="${REPO_ROOT}/${BOTTOM_PANEL_MOTION_TOKENS_REL}"
BOTTOM_PANEL_HOST_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomPanelHost.ets"
BOTTOM_PANEL_HOST="${REPO_ROOT}/${BOTTOM_PANEL_HOST_REL}"
WEB_LOADING_PROGRESS_BAR_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserWebLoadingProgressBar.ets"
WEB_LOADING_PROGRESS_BAR="${REPO_ROOT}/${WEB_LOADING_PROGRESS_BAR_REL}"
PULL_REFRESH_LOADING_AREA_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserPullRefreshLoadingArea.ets"
PULL_REFRESH_LOADING_AREA="${REPO_ROOT}/${PULL_REFRESH_LOADING_AREA_REL}"
ARKWEB_MEDIA_TAKEOVER_BUTTON_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserArkWebMediaTakeoverFloatingButton.ets"
ARKWEB_MEDIA_TAKEOVER_BUTTON="${REPO_ROOT}/${ARKWEB_MEDIA_TAKEOVER_BUTTON_REL}"
HOME_SYSTEM_SURFACE_REL="AiraBrowser/entry/src/main/ets/app/components/browser/HomeSystemSurface.ets"
HOME_SYSTEM_SURFACE="${REPO_ROOT}/${HOME_SYSTEM_SURFACE_REL}"
BOTTOM_ADDRESS_PANEL_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomAddressPanel.ets"
BOTTOM_ADDRESS_PANEL="${REPO_ROOT}/${BOTTOM_ADDRESS_PANEL_REL}"
BOTTOM_CHROME_RENDERER_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomChromeRenderer.ets"
BOTTOM_CHROME_RENDERER="${REPO_ROOT}/${BOTTOM_CHROME_RENDERER_REL}"
BOTTOM_CHROME_MATERIAL_TOKENS_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserFloatingGlassMaterialTokens.ets"
BOTTOM_CHROME_MATERIAL_TOKENS="${REPO_ROOT}/${BOTTOM_CHROME_MATERIAL_TOKENS_REL}"
BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomChromePresentationViewModel.ets"
BOTTOM_CHROME_PRESENTATION_VIEW_MODEL="${REPO_ROOT}/${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL}"
BOTTOM_ADDRESS_TRANSIENT_MESSAGE_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomAddressTransientMessageViewModel.ets"
BOTTOM_ADDRESS_TRANSIENT_MESSAGE_VIEW_MODEL="${REPO_ROOT}/${BOTTOM_ADDRESS_TRANSIENT_MESSAGE_VIEW_MODEL_REL}"
BOTTOM_ADDRESS_PANEL_METRICS_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomAddressPanelMetrics.ets"
BOTTOM_ADDRESS_PANEL_METRICS="${REPO_ROOT}/${BOTTOM_ADDRESS_PANEL_METRICS_REL}"
SEARCH_SUGGESTIONS_PANEL_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserSearchSuggestionsPanel.ets"
SEARCH_SUGGESTIONS_PANEL="${REPO_ROOT}/${SEARCH_SUGGESTIONS_PANEL_REL}"
SEARCH_LIST_SURFACE_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserSearchListSurface.ets"
SEARCH_LIST_SURFACE="${REPO_ROOT}/${SEARCH_LIST_SURFACE_REL}"
SEARCH_LIST_LAYOUT_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserSearchListSurfaceLayoutViewModel.ets"
SEARCH_LIST_LAYOUT_VIEW_MODEL="${REPO_ROOT}/${SEARCH_LIST_LAYOUT_VIEW_MODEL_REL}"
SEARCH_SUGGESTION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserSearchSuggestionCoordinator.ets"
SEARCH_SUGGESTION_COORDINATOR="${REPO_ROOT}/${SEARCH_SUGGESTION_COORDINATOR_REL}"
SEARCH_INVOCATION_SURFACE_ADAPTER_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellSearchInvocationAdapter.ets"
SEARCH_INVOCATION_SURFACE_ADAPTER="${REPO_ROOT}/${SEARCH_INVOCATION_SURFACE_ADAPTER_REL}"
OLD_SEARCH_OVERLAY_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserSearchOverlayCoordinator.ets"
OLD_SEARCH_OVERLAY_COORDINATOR="${REPO_ROOT}/${OLD_SEARCH_OVERLAY_COORDINATOR_REL}"
OLD_HOME_TRANSIENT_UI_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/HomeTransientUiStateCoordinator.ets"
OLD_HOME_TRANSIENT_UI_COORDINATOR="${REPO_ROOT}/${OLD_HOME_TRANSIENT_UI_COORDINATOR_REL}"
OLD_SEARCH_SUGGESTION_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/search/BrowserSearchSuggestionService.ets"
OLD_SEARCH_SUGGESTION_SERVICE="${REPO_ROOT}/${OLD_SEARCH_SUGGESTION_SERVICE_REL}"
OLD_SEARCH_SOURCE_PREFERENCE_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/search/SearchSuggestionSourcePreferenceService.ets"
OLD_SEARCH_SOURCE_PREFERENCE_SERVICE="${REPO_ROOT}/${OLD_SEARCH_SOURCE_PREFERENCE_SERVICE_REL}"
OLD_SEARCH_PIPELINE_REL="AiraBrowser/entry/src/main/ets/features/search/SearchPipeline.ets"
OLD_SEARCH_PIPELINE="${REPO_ROOT}/${OLD_SEARCH_PIPELINE_REL}"
EXTERNAL_APP_SEARCH_STRIP_REL="AiraBrowser/entry/src/main/ets/app/components/browser/ExternalAppSearchStrip.ets"
EXTERNAL_APP_SEARCH_STRIP="${REPO_ROOT}/${EXTERNAL_APP_SEARCH_STRIP_REL}"
OLD_BOTTOM_ADDRESS_FOCUS_REQUEST_CHANNEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomAddressFocusRequestChannel.ets"
OLD_BOTTOM_ADDRESS_FOCUS_REQUEST_CHANNEL="${REPO_ROOT}/${OLD_BOTTOM_ADDRESS_FOCUS_REQUEST_CHANNEL_REL}"
BOTTOM_PANEL_PRESENTATION_CHANNEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomPanelPresentationChannel.ets"
BOTTOM_PANEL_PRESENTATION_CHANNEL="${REPO_ROOT}/${BOTTOM_PANEL_PRESENTATION_CHANNEL_REL}"
CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/customhome/CustomHomepageBridgeCoordinator.ets"
CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR="${REPO_ROOT}/${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR_REL}"
CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/customhome/CustomHomepageRuntimeCoordinator.ets"
CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR="${REPO_ROOT}/${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}"
BROWSER_TAB_HOME_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabHomeCoordinator.ets"
BROWSER_TAB_HOME_COORDINATOR="${REPO_ROOT}/${BROWSER_TAB_HOME_COORDINATOR_REL}"
CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/customhome/CustomHomepageBridgeService.ets"
CUSTOM_HOMEPAGE_BRIDGE_SERVICE="${REPO_ROOT}/${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}"
CUSTOM_HOMEPAGE_THEME_PALETTE_PROJECTION_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/customhome/CustomHomepageThemePaletteProjectionService.ets"
CUSTOM_HOMEPAGE_THEME_PALETTE_PROJECTION_SERVICE="${REPO_ROOT}/${CUSTOM_HOMEPAGE_THEME_PALETTE_PROJECTION_SERVICE_REL}"
CUSTOM_HOMEPAGE_SYSTEM_ENTRY_CATALOG_REL="AiraBrowser/entry/src/main/ets/services/customhome/CustomHomepageSystemEntryCatalog.ets"
CUSTOM_HOMEPAGE_SYSTEM_ENTRY_CATALOG="${REPO_ROOT}/${CUSTOM_HOMEPAGE_SYSTEM_ENTRY_CATALOG_REL}"
CUSTOM_HOMEPAGE_DEVELOPER_GUIDE_REL="AiraBrowser/entry/src/main/resources/rawfile/custom_homepage_developer_guide.md"
CUSTOM_HOMEPAGE_DEVELOPER_GUIDE="${REPO_ROOT}/${CUSTOM_HOMEPAGE_DEVELOPER_GUIDE_REL}"
WEB_CAPABILITY_PROMPT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebCapabilityPromptApplicationCoordinator.ets"
WEB_CAPABILITY_PROMPT_COORDINATOR="${REPO_ROOT}/${WEB_CAPABILITY_PROMPT_COORDINATOR_REL}"
WEB_CAPABILITY_PROMPT_EFFECT_APPLICATION_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebCapabilityPromptEffectApplication.ets"
WEB_CAPABILITY_PROMPT_EFFECT_APPLICATION="${REPO_ROOT}/${WEB_CAPABILITY_PROMPT_EFFECT_APPLICATION_REL}"
WEB_CAPABILITY_ALERT_DIALOG_PRESENTER_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserWebCapabilityAlertDialogPresenter.ets"
WEB_CAPABILITY_ALERT_DIALOG_PRESENTER="${REPO_ROOT}/${WEB_CAPABILITY_ALERT_DIALOG_PRESENTER_REL}"
BROWSER_NATIVE_ALERT_DIALOG_PRESENTER_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserNativeAlertDialogPresenter.ets"
BROWSER_NATIVE_ALERT_DIALOG_PRESENTER="${REPO_ROOT}/${BROWSER_NATIVE_ALERT_DIALOG_PRESENTER_REL}"
WEB_PERMISSION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/web/WebPermissionCoordinator.ets"
WEB_PERMISSION_COORDINATOR="${REPO_ROOT}/${WEB_PERMISSION_COORDINATOR_REL}"
OLD_POLICY_DECISION_SERVICE_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPolicyDecisionService.ets"
OLD_POLICY_DECISION_SERVICE="${REPO_ROOT}/${OLD_POLICY_DECISION_SERVICE_REL}"
TAB_SCOPED_EVENT_CONTEXT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabScopedEventContextCoordinator.ets"
TAB_SCOPED_EVENT_CONTEXT_COORDINATOR="${REPO_ROOT}/${TAB_SCOPED_EVENT_CONTEXT_COORDINATOR_REL}"
OLD_WEB_DIALOG_APPLICATION_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebDialogApplicationCoordinator.ets"
OLD_WEB_DIALOG_APPLICATION="${REPO_ROOT}/${OLD_WEB_DIALOG_APPLICATION_REL}"
TAB_SWITCH_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabSwitchCoordinator.ets"
TAB_SWITCH_COORDINATOR="${REPO_ROOT}/${TAB_SWITCH_COORDINATOR_REL}"
PRIVATE_MODE_LOCK_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/privacy/BrowserPrivateModeLockCoordinator.ets"
PRIVATE_MODE_LOCK_COORDINATOR="${REPO_ROOT}/${PRIVATE_MODE_LOCK_COORDINATOR_REL}"
PRIVATE_MODE_LOCK_OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserPrivateModeLockOverlay.ets"
PRIVATE_MODE_LOCK_OVERLAY="${REPO_ROOT}/${PRIVATE_MODE_LOCK_OVERLAY_REL}"
SHELL_ROUTE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellRouteCoordinator.ets"
SHELL_ROUTE_COORDINATOR="${REPO_ROOT}/${SHELL_ROUTE_COORDINATOR_REL}"
FOREGROUND_TAB_CREATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserForegroundTabCreationCoordinator.ets"
FOREGROUND_TAB_CREATION_COORDINATOR="${REPO_ROOT}/${FOREGROUND_TAB_CREATION_COORDINATOR_REL}"
STARTUP_TAB_RESTORE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserStartupTabRestoreCoordinator.ets"
STARTUP_TAB_RESTORE_COORDINATOR="${REPO_ROOT}/${STARTUP_TAB_RESTORE_COORDINATOR_REL}"
NATIVE_NAVIGATION_CONSUME_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/navigation/BrowserNativeNavigationConsumeCoordinator.ets"
NATIVE_NAVIGATION_CONSUME_COORDINATOR="${REPO_ROOT}/${NATIVE_NAVIGATION_CONSUME_COORDINATOR_REL}"
PRIVATE_TAB_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPrivateTabCoordinator.ets"
PRIVATE_TAB_COORDINATOR="${REPO_ROOT}/${PRIVATE_TAB_COORDINATOR_REL}"
PRIVATE_WINDOW_LAUNCH_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/browser/BrowserPrivateWindowLaunchService.ets"
PRIVATE_WINDOW_LAUNCH_SERVICE="${REPO_ROOT}/${PRIVATE_WINDOW_LAUNCH_SERVICE_REL}"
PRIVATE_WINDOW_POLICY_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/browser/BrowserPrivateWindowPolicyService.ets"
PRIVATE_WINDOW_POLICY_SERVICE="${REPO_ROOT}/${PRIVATE_WINDOW_POLICY_SERVICE_REL}"
QR_SCAN_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserQrScanCoordinator.ets"
QR_SCAN_COORDINATOR="${REPO_ROOT}/${QR_SCAN_COORDINATOR_REL}"
KEYBOARD_SHORTCUT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserKeyboardShortcutCoordinator.ets"
KEYBOARD_SHORTCUT_COORDINATOR="${REPO_ROOT}/${KEYBOARD_SHORTCUT_COORDINATOR_REL}"
PAGE_FIND_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPageFindCoordinator.ets"
PAGE_FIND_COORDINATOR="${REPO_ROOT}/${PAGE_FIND_COORDINATOR_REL}"
OLD_PAGE_FIND_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPageFindViewModel.ets"
OLD_PAGE_FIND_VIEW_MODEL="${REPO_ROOT}/${OLD_PAGE_FIND_VIEW_MODEL_REL}"
PAGE_FIND_BAR_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserPageFindBar.ets"
PAGE_FIND_BAR="${REPO_ROOT}/${PAGE_FIND_BAR_REL}"
WEB_HISTORY_COMMAND_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebHistoryCommandRuntimeCoordinator.ets"
WEB_HISTORY_COMMAND_COORDINATOR="${REPO_ROOT}/${WEB_HISTORY_COMMAND_COORDINATOR_REL}"
PRIVATE_SESSION_CLEANUP_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPrivateSessionCleanupCoordinator.ets"
PRIVATE_SESSION_CLEANUP_COORDINATOR="${REPO_ROOT}/${PRIVATE_SESSION_CLEANUP_COORDINATOR_REL}"
OLD_SHORTCUT_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShortcutViewModel.ets"
OLD_SHORTCUT_VIEW_MODEL="${REPO_ROOT}/${OLD_SHORTCUT_VIEW_MODEL_REL}"
RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRecentlyClosedApplicationCoordinator.ets"
RECENTLY_CLOSED_APPLICATION_COORDINATOR="${REPO_ROOT}/${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}"
OLD_RECENTLY_CLOSED_PERSISTENCE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRecentlyClosedPersistenceCoordinator.ets"
OLD_RECENTLY_CLOSED_PERSISTENCE_COORDINATOR="${REPO_ROOT}/${OLD_RECENTLY_CLOSED_PERSISTENCE_COORDINATOR_REL}"
OLD_RECENTLY_CLOSED_RECORD_ACTION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRecentlyClosedRecordActionCoordinator.ets"
OLD_RECENTLY_CLOSED_RECORD_ACTION_COORDINATOR="${REPO_ROOT}/${OLD_RECENTLY_CLOSED_RECORD_ACTION_COORDINATOR_REL}"
OLD_RECENTLY_CLOSED_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserRecentlyClosedSheet.ets"
OLD_RECENTLY_CLOSED_SHEET="${REPO_ROOT}/${OLD_RECENTLY_CLOSED_SHEET_REL}"
HOME_SHORTCUT_STATE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/shortcuts/HomeShortcutStateCoordinator.ets"
HOME_SHORTCUT_STATE_COORDINATOR="${REPO_ROOT}/${HOME_SHORTCUT_STATE_COORDINATOR_REL}"
HOME_SHORTCUT_EFFECT_APPLICATION_REL="AiraBrowser/entry/src/main/ets/core/shortcuts/HomeShortcutEffectApplication.ets"
HOME_SHORTCUT_EFFECT_APPLICATION="${REPO_ROOT}/${HOME_SHORTCUT_EFFECT_APPLICATION_REL}"
HOME_SHORTCUT_OPEN_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/shortcuts/HomeShortcutOpenCoordinator.ets"
HOME_SHORTCUT_OPEN_COORDINATOR="${REPO_ROOT}/${HOME_SHORTCUT_OPEN_COORDINATOR_REL}"
OLD_HOME_SHORTCUT_OPEN_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/services/shortcuts/HomeShortcutOpenCoordinator.ets"
OLD_HOME_SHORTCUT_OPEN_COORDINATOR="${REPO_ROOT}/${OLD_HOME_SHORTCUT_OPEN_COORDINATOR_REL}"
HOME_SHORTCUT_ICON_HYDRATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/services/shortcuts/HomeShortcutIconHydrationCoordinator.ets"
HOME_SHORTCUT_ICON_HYDRATION_COORDINATOR="${REPO_ROOT}/${HOME_SHORTCUT_ICON_HYDRATION_COORDINATOR_REL}"
SHORTCUT_REPOSITORIES_REL="AiraBrowser/entry/src/main/ets/data/repositories/BrowserRepositories.ets"
SHORTCUT_REPOSITORIES="${REPO_ROOT}/${SHORTCUT_REPOSITORIES_REL}"
BROWSER_DATABASE_REL="AiraBrowser/entry/src/main/ets/data/database/BrowserDatabase.ets"
BROWSER_DATABASE="${REPO_ROOT}/${BROWSER_DATABASE_REL}"
BROWSER_MODELS_REL="AiraBrowser/entry/src/main/ets/common/models/BrowserModels.ets"
BROWSER_MODELS="${REPO_ROOT}/${BROWSER_MODELS_REL}"
PREFERENCES_REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/preferences/PreferencesRepository.ets"
PREFERENCES_REPOSITORY="${REPO_ROOT}/${PREFERENCES_REPOSITORY_REL}"
ARK_PREFERENCES_STORAGE_ADAPTER_REL="AiraBrowser/entry/src/main/ets/data/preferences/ArkPreferencesStorageAdapter.ets"
ARK_PREFERENCES_STORAGE_ADAPTER="${REPO_ROOT}/${ARK_PREFERENCES_STORAGE_ADAPTER_REL}"
BROWSER_DIAGNOSTICS_RECORDER_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserDiagnosticsRecorder.ets"
BROWSER_DIAGNOSTICS_RECORDER="${REPO_ROOT}/${BROWSER_DIAGNOSTICS_RECORDER_REL}"
MEMBERSHIP_GROWTH_EVENT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/membership/MembershipGrowthEventCoordinator.ets"
MEMBERSHIP_GROWTH_EVENT_COORDINATOR="${REPO_ROOT}/${MEMBERSHIP_GROWTH_EVENT_COORDINATOR_REL}"
RUNTIME_TELEMETRY_SERVICE_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRuntimeTelemetryService.ets"
RUNTIME_TELEMETRY_SERVICE="${REPO_ROOT}/${RUNTIME_TELEMETRY_SERVICE_REL}"
RUNTIME_DIAGNOSTIC_REDACTION_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/diagnostics/BrowserRuntimeDiagnosticRedactionService.ets"
RUNTIME_DIAGNOSTIC_REDACTION_SERVICE="${REPO_ROOT}/${RUNTIME_DIAGNOSTIC_REDACTION_SERVICE_REL}"
PAGE_CACHE_METRICS_SERVICE_REL="AiraBrowser/entry/src/main/ets/core/web/WebPageCacheMetricsService.ets"
PAGE_CACHE_METRICS_SERVICE="${REPO_ROOT}/${PAGE_CACHE_METRICS_SERVICE_REL}"
SHELL_DIAGNOSTIC_PRESENTATION_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellDiagnosticPresentationViewModel.ets"
SHELL_DIAGNOSTIC_PRESENTATION_VIEW_MODEL="${REPO_ROOT}/${SHELL_DIAGNOSTIC_PRESENTATION_VIEW_MODEL_REL}"
DIAGNOSTICS_LIFECYCLE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserDiagnosticsLifecycleCoordinator.ets"
DIAGNOSTICS_LIFECYCLE_COORDINATOR="${REPO_ROOT}/${DIAGNOSTICS_LIFECYCLE_COORDINATOR_REL}"
DIAGNOSTICS_MAINTENANCE_SCHEDULER_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserDiagnosticsMaintenanceScheduler.ets"
DIAGNOSTICS_MAINTENANCE_SCHEDULER="${REPO_ROOT}/${DIAGNOSTICS_MAINTENANCE_SCHEDULER_REL}"
DIAGNOSTICS_SERVICE_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserDiagnosticsService.ets"
DIAGNOSTICS_SERVICE="${REPO_ROOT}/${DIAGNOSTICS_SERVICE_REL}"
HOME_SHORTCUT_SURFACE_REL="AiraBrowser/entry/src/main/ets/app/components/browser/HomeShortcutSurface.ets"
HOME_SHORTCUT_SURFACE="${REPO_ROOT}/${HOME_SHORTCUT_SURFACE_REL}"
HOME_FAVORITES_SECTION_REL="AiraBrowser/entry/src/main/ets/app/components/browser/HomeFavoritesSection.ets"
HOME_FAVORITES_SECTION="${REPO_ROOT}/${HOME_FAVORITES_SECTION_REL}"
HOME_CONTENT_SECTIONS_REL="AiraBrowser/entry/src/main/ets/app/components/browser/HomeContentSections.ets"
HOME_CONTENT_SECTIONS="${REPO_ROOT}/${HOME_CONTENT_SECTIONS_REL}"
HOME_RECENTLY_CLOSED_SECTION_REL="AiraBrowser/entry/src/main/ets/app/components/browser/HomeRecentlyClosedSection.ets"
HOME_RECENTLY_CLOSED_SECTION="${REPO_ROOT}/${HOME_RECENTLY_CLOSED_SECTION_REL}"
RECENTLY_CLOSED_RECORD_LIST_REL="AiraBrowser/entry/src/main/ets/app/components/browser/RecentlyClosedRecordList.ets"
RECENTLY_CLOSED_RECORD_LIST="${REPO_ROOT}/${RECENTLY_CLOSED_RECORD_LIST_REL}"
TAB_CLOSE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabCloseCoordinator.ets"
TAB_CLOSE_COORDINATOR="${REPO_ROOT}/${TAB_CLOSE_COORDINATOR_REL}"
APP_URL_OPEN_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserAppUrlOpenCoordinator.ets"
APP_URL_OPEN_COORDINATOR="${REPO_ROOT}/${APP_URL_OPEN_COORDINATOR_REL}"
BACKGROUND_OPEN_PROMPT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBackgroundOpenPromptCoordinator.ets"
BACKGROUND_OPEN_PROMPT_COORDINATOR="${REPO_ROOT}/${BACKGROUND_OPEN_PROMPT_COORDINATOR_REL}"
TOP_FLOATING_PROMPT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTopFloatingPromptCoordinator.ets"
TOP_FLOATING_PROMPT_COORDINATOR="${REPO_ROOT}/${TOP_FLOATING_PROMPT_COORDINATOR_REL}"
FAVICON_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserFaviconCoordinator.ets"
FAVICON_COORDINATOR="${REPO_ROOT}/${FAVICON_COORDINATOR_REL}"
WEB_PAGE_PRESENTATION_EVENT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebPagePresentationEventCoordinator.ets"
WEB_PAGE_PRESENTATION_EVENT_COORDINATOR="${REPO_ROOT}/${WEB_PAGE_PRESENTATION_EVENT_COORDINATOR_REL}"
SITE_CLEAR_ON_CLOSE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/SiteClearOnCloseCoordinator.ets"
SITE_CLEAR_ON_CLOSE_COORDINATOR="${REPO_ROOT}/${SITE_CLEAR_ON_CLOSE_COORDINATOR_REL}"
ACTIVE_RUNTIME_SYNC_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserActiveRuntimeSyncCoordinator.ets"
ACTIVE_RUNTIME_SYNC_COORDINATOR="${REPO_ROOT}/${ACTIVE_RUNTIME_SYNC_COORDINATOR_REL}"
PROXY_AUTH_REFRESH_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserProxyAuthRefreshCoordinator.ets"
PROXY_AUTH_REFRESH_COORDINATOR="${REPO_ROOT}/${PROXY_AUTH_REFRESH_COORDINATOR_REL}"
PROXY_RUNTIME_REFRESH_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserProxyRuntimeRefreshCoordinator.ets"
PROXY_RUNTIME_REFRESH_COORDINATOR="${REPO_ROOT}/${PROXY_RUNTIME_REFRESH_COORDINATOR_REL}"
WEB_LOAD_RUNTIME_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/services/web/BrowserWebLoadRuntimeCoordinator.ets"
WEB_LOAD_RUNTIME_COORDINATOR="${REPO_ROOT}/${WEB_LOAD_RUNTIME_COORDINATOR_REL}"
OFFLINE_FAST_FAILURE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/services/web/BrowserOfflineFastFailureCoordinator.ets"
OFFLINE_FAST_FAILURE_COORDINATOR="${REPO_ROOT}/${OFFLINE_FAST_FAILURE_COORDINATOR_REL}"
OLD_TAB_SWITCH_ATTACH_RETRY_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabSwitchHostAttachRetryCoordinator.ets"
OLD_TAB_SWITCH_ATTACH_RETRY="${REPO_ROOT}/${OLD_TAB_SWITCH_ATTACH_RETRY_REL}"
TAB_HOME_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabHomeCoordinator.ets"
TAB_HOME_COORDINATOR="${REPO_ROOT}/${TAB_HOME_COORDINATOR_REL}"
HOME_SURFACE_PROFILE_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserHomeSurfaceProfileViewModel.ets"
HOME_SURFACE_PROFILE_VIEW_MODEL="${REPO_ROOT}/${HOME_SURFACE_PROFILE_VIEW_MODEL_REL}"
HOME_CHROME_SCROLL_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserHomeChromeScrollCoordinator.ets"
HOME_CHROME_SCROLL_COORDINATOR="${REPO_ROOT}/${HOME_CHROME_SCROLL_COORDINATOR_REL}"
OLD_HOME_SCROLL_CHROME_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserHomeScrollChromeViewModel.ets"
OLD_HOME_SCROLL_CHROME_VIEW_MODEL="${REPO_ROOT}/${OLD_HOME_SCROLL_CHROME_VIEW_MODEL_REL}"
OLD_HOME_SYSTEM_CHROME_POLICY_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserHomeSystemChromePolicyViewModel.ets"
OLD_HOME_SYSTEM_CHROME_POLICY_VIEW_MODEL="${REPO_ROOT}/${OLD_HOME_SYSTEM_CHROME_POLICY_VIEW_MODEL_REL}"
SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserSearchBackdropPresentationViewModel.ets"
SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL="${REPO_ROOT}/${SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL_REL}"
CUSTOM_HOMEPAGE_SURFACE_REL="AiraBrowser/entry/src/main/ets/app/components/customhome/CustomHomepageSurface.ets"
CUSTOM_HOMEPAGE_SURFACE="${REPO_ROOT}/${CUSTOM_HOMEPAGE_SURFACE_REL}"
OLD_HOME_SURFACE_PLAN_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserHomeSurfacePlanService.ets"
OLD_HOME_SURFACE_PLAN="${REPO_ROOT}/${OLD_HOME_SURFACE_PLAN_REL}"
WINDOW_CONTEXT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWindowContextCoordinator.ets"
WINDOW_CONTEXT_COORDINATOR="${REPO_ROOT}/${WINDOW_CONTEXT_COORDINATOR_REL}"
WINDOW_LAUNCH_APPLICATION_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWindowLaunchApplication.ets"
WINDOW_LAUNCH_APPLICATION="${REPO_ROOT}/${WINDOW_LAUNCH_APPLICATION_REL}"
WEB_APP_SESSION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/webapps/WebAppSessionCoordinator.ets"
WEB_APP_SESSION_COORDINATOR="${REPO_ROOT}/${WEB_APP_SESSION_COORDINATOR_REL}"
WEB_APP_EXIT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/webapps/WebAppExitCoordinator.ets"
WEB_APP_EXIT_COORDINATOR="${REPO_ROOT}/${WEB_APP_EXIT_COORDINATOR_REL}"
WEB_APP_SCOPE_OUT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebAppScopeOutNavigationCoordinator.ets"
WEB_APP_SCOPE_OUT_COORDINATOR="${REPO_ROOT}/${WEB_APP_SCOPE_OUT_COORDINATOR_REL}"
OLD_WEB_APP_IMMERSIVE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/webapps/WebAppImmersiveModeCoordinator.ets"
OLD_WEB_APP_IMMERSIVE_COORDINATOR="${REPO_ROOT}/${OLD_WEB_APP_IMMERSIVE_COORDINATOR_REL}"
OLD_WEB_APP_LAUNCH_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/webapps/WebAppLaunchCoordinator.ets"
OLD_WEB_APP_LAUNCH_COORDINATOR="${REPO_ROOT}/${OLD_WEB_APP_LAUNCH_COORDINATOR_REL}"
OLD_PENDING_WINDOW_LAUNCH_SERVICE_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPendingWindowLaunchService.ets"
OLD_PENDING_WINDOW_LAUNCH_SERVICE="${REPO_ROOT}/${OLD_PENDING_WINDOW_LAUNCH_SERVICE_REL}"
READER_MODE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/ReaderModeCoordinator.ets"
READER_MODE_COORDINATOR="${REPO_ROOT}/${READER_MODE_COORDINATOR_REL}"
READER_MODE_APPLICATION_REL="AiraBrowser/entry/src/main/ets/core/browser/ReaderModeApplication.ets"
READER_MODE_APPLICATION="${REPO_ROOT}/${READER_MODE_APPLICATION_REL}"
READER_MODE_OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/browser/ReaderModeOverlay.ets"
READER_MODE_OVERLAY="${REPO_ROOT}/${READER_MODE_OVERLAY_REL}"
READER_MODE_MODELS_REL="AiraBrowser/entry/src/main/ets/features/reader/ReaderModeModels.ets"
READER_MODE_MODELS="${REPO_ROOT}/${READER_MODE_MODELS_REL}"
NOVEL_READER_OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/browser/NovelReaderOverlay.ets"
NOVEL_READER_OVERLAY="${REPO_ROOT}/${NOVEL_READER_OVERLAY_REL}"
READING_SURFACE_REL="AiraBrowser/entry/src/main/ets/app/components/reading/ReadingSurface.ets"
READING_SURFACE="${REPO_ROOT}/${READING_SURFACE_REL}"
READING_SURFACE_MODELS_REL="AiraBrowser/entry/src/main/ets/features/reading/ReadingSurfaceModels.ets"
READING_SURFACE_MODELS="${REPO_ROOT}/${READING_SURFACE_MODELS_REL}"
READING_EXPERIENCE_CHROME_REL="AiraBrowser/entry/src/main/ets/app/components/reading/ReadingExperienceChrome.ets"
READING_EXPERIENCE_CHROME="${REPO_ROOT}/${READING_EXPERIENCE_CHROME_REL}"
READING_EXPERIENCE_SYSTEM_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/reading/ReadingExperienceSystemSheet.ets"
READING_EXPERIENCE_SYSTEM_SHEET="${REPO_ROOT}/${READING_EXPERIENCE_SYSTEM_SHEET_REL}"
READING_SURFACE_SETTINGS_PANEL_REL="AiraBrowser/entry/src/main/ets/app/components/reading/ReadingSurfaceSettingsPanel.ets"
READING_SURFACE_SETTINGS_PANEL="${REPO_ROOT}/${READING_SURFACE_SETTINGS_PANEL_REL}"
PHONE_SETTINGS_SHEET_HEADER_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserPhoneSettingsSheetHeader.ets"
PHONE_SETTINGS_SHEET_HEADER="${REPO_ROOT}/${PHONE_SETTINGS_SHEET_HEADER_REL}"
HOME_PAGE_SETTINGS_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/browser/HomePageSettingsSheet.ets"
HOME_PAGE_SETTINGS_SHEET="${REPO_ROOT}/${HOME_PAGE_SETTINGS_SHEET_REL}"
READING_THEME_TOKEN_RESOLVER_REL="AiraBrowser/entry/src/main/ets/app/components/reading/ReadingThemeTokenResolver.ets"
READING_THEME_TOKEN_RESOLVER="${REPO_ROOT}/${READING_THEME_TOKEN_RESOLVER_REL}"
OLD_NOVEL_PAGINATOR_REL="AiraBrowser/entry/src/main/ets/features/novel/NovelPaginator.ets"
OLD_NOVEL_PAGINATOR="${REPO_ROOT}/${OLD_NOVEL_PAGINATOR_REL}"
OLD_NOVEL_PAGINATION_MODELS_REL="AiraBrowser/entry/src/main/ets/features/novel/NovelPaginationModels.ets"
OLD_NOVEL_PAGINATION_MODELS="${REPO_ROOT}/${OLD_NOVEL_PAGINATION_MODELS_REL}"
BROWSER_WINDOW_SESSION_APPLICATION_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWindowSessionApplication.ets"
BROWSER_WINDOW_SESSION_APPLICATION="${REPO_ROOT}/${BROWSER_WINDOW_SESSION_APPLICATION_REL}"
MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/adblock/ManualElementHideRuntimeCoordinator.ets"
MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR="${REPO_ROOT}/${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR_REL}"
MANUAL_ELEMENT_HIDE_SELECTION_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/browser/ManualElementHideSelectionOverlay.ets"
MANUAL_ELEMENT_HIDE_SELECTION_COMPONENT="${REPO_ROOT}/${MANUAL_ELEMENT_HIDE_SELECTION_COMPONENT_REL}"
DESKTOP_LOGIN_CONFIRM_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/settings/DesktopLoginConfirmSheetContent.ets"
DESKTOP_LOGIN_CONFIRM_COMPONENT="${REPO_ROOT}/${DESKTOP_LOGIN_CONFIRM_COMPONENT_REL}"
WEB_TEXT_ZOOM_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserWebTextZoomSheet.ets"
WEB_TEXT_ZOOM_COMPONENT="${REPO_ROOT}/${WEB_TEXT_ZOOM_COMPONENT_REL}"
WEB_TEXT_ZOOM_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebTextZoomViewModel.ets"
WEB_TEXT_ZOOM_VIEW_MODEL="${REPO_ROOT}/${WEB_TEXT_ZOOM_VIEW_MODEL_REL}"
WEB_CONTEXT_MENU_OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/browser/WebContextMenuOverlay.ets"
WEB_CONTEXT_MENU_OVERLAY="${REPO_ROOT}/${WEB_CONTEXT_MENU_OVERLAY_REL}"
AD_BLOCK_RUNTIME_STATS_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/adblock/AdBlockRuntimeStatsCoordinator.ets"
AD_BLOCK_RUNTIME_STATS_COORDINATOR="${REPO_ROOT}/${AD_BLOCK_RUNTIME_STATS_COORDINATOR_REL}"
SITE_CUSTOMIZATION_RUNTIME_REFRESH_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/sitecustomization/SiteCustomizationRuntimeRefreshCoordinator.ets"
SITE_CUSTOMIZATION_RUNTIME_REFRESH_COORDINATOR="${REPO_ROOT}/${SITE_CUSTOMIZATION_RUNTIME_REFRESH_COORDINATOR_REL}"
BROWSER_WEB_PRINT_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/web/BrowserWebPrintService.ets"
BROWSER_WEB_PRINT_SERVICE="${REPO_ROOT}/${BROWSER_WEB_PRINT_SERVICE_REL}"
DOCUMENT_VIEWER_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/viewer/DocumentViewerService.ets"
DOCUMENT_VIEWER_SERVICE="${REPO_ROOT}/${DOCUMENT_VIEWER_SERVICE_REL}"
READER_SPEECH_VOICE_DIALOG_REL="AiraBrowser/entry/src/main/ets/app/components/browser/ReaderSpeechVoiceDialog.ets"
READER_SPEECH_VOICE_DIALOG="${REPO_ROOT}/${READER_SPEECH_VOICE_DIALOG_REL}"
READER_SPEECH_PLAYER_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/browser/ReaderSpeechPlayerScreen.ets"
READER_SPEECH_PLAYER_COMPONENT="${REPO_ROOT}/${READER_SPEECH_PLAYER_COMPONENT_REL}"
TRANSLATION_TARGET_LANGUAGE_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/translation/WebpageTranslationTargetLanguageSheet.ets"
TRANSLATION_TARGET_LANGUAGE_COMPONENT="${REPO_ROOT}/${TRANSLATION_TARGET_LANGUAGE_COMPONENT_REL}"
DOWNLOAD_CONFIRM_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDownloadConfirmSheet.ets"
DOWNLOAD_CONFIRM_COMPONENT="${REPO_ROOT}/${DOWNLOAD_CONFIRM_COMPONENT_REL}"
MEDIA_RESOURCES_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserMediaResourcesSheet.ets"
MEDIA_RESOURCES_COMPONENT="${REPO_ROOT}/${MEDIA_RESOURCES_COMPONENT_REL}"
TOOLBAR_SYSTEM_SHEET_CONTENT_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserToolbarSystemSheetContent.ets"
TOOLBAR_SYSTEM_SHEET_CONTENT="${REPO_ROOT}/${TOOLBAR_SYSTEM_SHEET_CONTENT_REL}"
WIFI_QR_RESULT_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserWifiQrResultOverlay.ets"
WIFI_QR_RESULT_COMPONENT="${REPO_ROOT}/${WIFI_QR_RESULT_COMPONENT_REL}"
HLS_TAKEOVER_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserHlsTakeoverSheet.ets"
HLS_TAKEOVER_COMPONENT="${REPO_ROOT}/${HLS_TAKEOVER_COMPONENT_REL}"
OFFLINE_PAGE_VIEWER_REL="AiraBrowser/entry/src/main/ets/app/components/offline/OfflinePageViewerScreen.ets"
OFFLINE_PAGE_VIEWER="${REPO_ROOT}/${OFFLINE_PAGE_VIEWER_REL}"
OFFLINE_PAGES_SCREEN_REL="AiraBrowser/entry/src/main/ets/app/components/offline/OfflinePagesScreen.ets"
OFFLINE_PAGES_SCREEN="${REPO_ROOT}/${OFFLINE_PAGES_SCREEN_REL}"
OFFLINE_PAGE_OPEN_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/offline/OfflinePageOpenCoordinator.ets"
OFFLINE_PAGE_OPEN_COORDINATOR="${REPO_ROOT}/${OFFLINE_PAGE_OPEN_COORDINATOR_REL}"
OFFLINE_PAGE_SAVE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/offline/OfflinePageSaveCoordinator.ets"
OFFLINE_PAGE_SAVE_COORDINATOR="${REPO_ROOT}/${OFFLINE_PAGE_SAVE_COORDINATOR_REL}"
OFFLINE_PAGE_LINK_ACTION_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/offline/OfflinePageLinkActionService.ets"
OFFLINE_PAGE_LINK_ACTION_SERVICE="${REPO_ROOT}/${OFFLINE_PAGE_LINK_ACTION_SERVICE_REL}"
FEATURE_GATE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/membership/FeatureGateCoordinator.ets"
FEATURE_GATE_COORDINATOR="${REPO_ROOT}/${FEATURE_GATE_COORDINATOR_REL}"
OLD_FEATURE_GATE_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/membership/FeatureGateViewModel.ets"
OLD_FEATURE_GATE_VIEW_MODEL="${REPO_ROOT}/${OLD_FEATURE_GATE_VIEW_MODEL_REL}"
FEATURE_GATE_OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/browser/FeatureGateOverlay.ets"
FEATURE_GATE_OVERLAY="${REPO_ROOT}/${FEATURE_GATE_OVERLAY_REL}"
FEATURE_GATE_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/membership/FeatureGateSheet.ets"
FEATURE_GATE_SHEET="${REPO_ROOT}/${FEATURE_GATE_SHEET_REL}"
PHONE_PAGE_PUSH_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPhonePagePushCoordinator.ets"
PHONE_PAGE_PUSH_COORDINATOR="${REPO_ROOT}/${PHONE_PAGE_PUSH_COORDINATOR_REL}"
WEB_APP_INSTALL_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/webapps/WebAppInstallCoordinator.ets"
WEB_APP_INSTALL_COORDINATOR="${REPO_ROOT}/${WEB_APP_INSTALL_COORDINATOR_REL}"
BROWSER_SHELL_DIALOGS_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserShellDialogs.ets"
BROWSER_SHELL_DIALOGS="${REPO_ROOT}/${BROWSER_SHELL_DIALOGS_REL}"
USER_SCRIPT_APPLICATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/userscripts/BrowserUserScriptApplicationCoordinator.ets"
USER_SCRIPT_APPLICATION_COORDINATOR="${REPO_ROOT}/${USER_SCRIPT_APPLICATION_COORDINATOR_REL}"
OLD_DOWNLOAD_EVENT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserDownloadEventCoordinator.ets"
OLD_DOWNLOAD_EVENT_COORDINATOR="${REPO_ROOT}/${OLD_DOWNLOAD_EVENT_COORDINATOR_REL}"
USER_SCRIPT_INSTALL_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/userscripts/UserScriptInstallSheetContent.ets"
USER_SCRIPT_INSTALL_SHEET="${REPO_ROOT}/${USER_SCRIPT_INSTALL_SHEET_REL}"
USER_SCRIPT_PAGE_ACTIONS_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/userscripts/UserScriptPageActionsSheet.ets"
USER_SCRIPT_PAGE_ACTIONS_SHEET="${REPO_ROOT}/${USER_SCRIPT_PAGE_ACTIONS_SHEET_REL}"
HOME_SHORTCUT_SELECTION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/shortcuts/HomeShortcutSelectionCoordinator.ets"
HOME_SHORTCUT_SELECTION_COORDINATOR="${REPO_ROOT}/${HOME_SHORTCUT_SELECTION_COORDINATOR_REL}"
HOME_SHORTCUT_SELECTION_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/browser/HomeShortcutSelectionSheet.ets"
HOME_SHORTCUT_SELECTION_SHEET="${REPO_ROOT}/${HOME_SHORTCUT_SELECTION_SHEET_REL}"
RELEASE_NOTICE_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/update/ReleaseNoticeSheet.ets"
RELEASE_NOTICE_SHEET="${REPO_ROOT}/${RELEASE_NOTICE_SHEET_REL}"
WEB_PAGE_LIFECYCLE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebPageLifecycleApplicationCoordinator.ets"
WEB_PAGE_LIFECYCLE_COORDINATOR="${REPO_ROOT}/${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}"
WEB_PAGE_LIFECYCLE_MODELS_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebPageLifecycleModels.ets"
WEB_PAGE_LIFECYCLE_MODELS="${REPO_ROOT}/${WEB_PAGE_LIFECYCLE_MODELS_REL}"
WEB_EVENT_COMMIT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebEventCommitCoordinator.ets"
WEB_EVENT_COMMIT_COORDINATOR="${REPO_ROOT}/${WEB_EVENT_COMMIT_COORDINATOR_REL}"
RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/services/web/BrowserRuntimeNavigationRecoveryCoordinator.ets"
RUNTIME_NAVIGATION_RECOVERY_COORDINATOR="${REPO_ROOT}/${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL}"
RUNTIME_NAVIGATION_RECOVERY_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/web/BrowserRuntimeNavigationRecoveryService.ets"
RUNTIME_NAVIGATION_RECOVERY_SERVICE="${REPO_ROOT}/${RUNTIME_NAVIGATION_RECOVERY_SERVICE_REL}"
ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/services/web/BrowserActiveTabRuntimeRestoreCoordinator.ets"
ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR="${REPO_ROOT}/${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR_REL}"
HOME_PRESENTATION_SESSION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserHomePresentationSessionCoordinator.ets"
HOME_PRESENTATION_SESSION_COORDINATOR="${REPO_ROOT}/${HOME_PRESENTATION_SESSION_COORDINATOR_REL}"
HOME_PRESENTATION_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserHomePresentationViewModel.ets"
HOME_PRESENTATION_VIEW_MODEL="${REPO_ROOT}/${HOME_PRESENTATION_VIEW_MODEL_REL}"
OLD_HOME_STARTUP_ENTRANCE_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserHomeStartupEntranceViewModel.ets"
OLD_HOME_STARTUP_ENTRANCE_VIEW_MODEL="${REPO_ROOT}/${OLD_HOME_STARTUP_ENTRANCE_VIEW_MODEL_REL}"
PULL_REFRESH_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPullRefreshCoordinator.ets"
PULL_REFRESH_COORDINATOR="${REPO_ROOT}/${PULL_REFRESH_COORDINATOR_REL}"
PULL_REFRESH_MODELS_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPullRefreshModels.ets"
PULL_REFRESH_MODELS="${REPO_ROOT}/${PULL_REFRESH_MODELS_REL}"
OLD_PULL_REFRESH_INPUT_ADAPTER_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPullRefreshInputAdapter.ets"
OLD_PULL_REFRESH_INPUT_ADAPTER="${REPO_ROOT}/${OLD_PULL_REFRESH_INPUT_ADAPTER_REL}"
APP_PROXY_QUICK_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/settings/AppProxyQuickSheetCoordinator.ets"
APP_PROXY_QUICK_COORDINATOR="${REPO_ROOT}/${APP_PROXY_QUICK_COORDINATOR_REL}"
APP_PROXY_QUICK_CONTENT_REL="AiraBrowser/entry/src/main/ets/app/components/settings/AppProxyQuickSheetContent.ets"
APP_PROXY_QUICK_CONTENT="${REPO_ROOT}/${APP_PROXY_QUICK_CONTENT_REL}"
OLD_APP_PROXY_TOOLBAR_ACTIVE_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/settings/AppProxyToolbarActiveViewModel.ets"
OLD_APP_PROXY_TOOLBAR_ACTIVE_VIEW_MODEL="${REPO_ROOT}/${OLD_APP_PROXY_TOOLBAR_ACTIVE_VIEW_MODEL_REL}"
APP_REVIEW_PROMPT_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/review/AppReviewPromptCoordinator.ets"
APP_REVIEW_PROMPT_COORDINATOR="${REPO_ROOT}/${APP_REVIEW_PROMPT_COORDINATOR_REL}"
RELEASE_NOTICE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/update/ReleaseNoticeCoordinator.ets"
RELEASE_NOTICE_COORDINATOR="${REPO_ROOT}/${RELEASE_NOTICE_COORDINATOR_REL}"
RELEASE_NOTICE_PRESENTATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/update/ReleaseNoticePresentationCoordinator.ets"
RELEASE_NOTICE_PRESENTATION_COORDINATOR="${REPO_ROOT}/${RELEASE_NOTICE_PRESENTATION_COORDINATOR_REL}"
BROWSER_APP_RUNTIME_REL="AiraBrowser/entry/src/main/ets/app/bootstrap/BrowserAppRuntime.ets"
BROWSER_APP_RUNTIME="${REPO_ROOT}/${BROWSER_APP_RUNTIME_REL}"
BOOKMARK_ACTION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBookmarkActionCoordinator.ets"
BOOKMARK_ACTION_COORDINATOR="${REPO_ROOT}/${BOOKMARK_ACTION_COORDINATOR_REL}"
BOOKMARK_MANAGEMENT_FEATURE_REL="AiraBrowser/entry/src/main/ets/features/bookmarks/BookmarkManagementFeature.ets"
BOOKMARK_MANAGEMENT_FEATURE="${REPO_ROOT}/${BOOKMARK_MANAGEMENT_FEATURE_REL}"
BOOKMARK_MUTATION_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/bookmarks/BookmarkMutationService.ets"
BOOKMARK_MUTATION_SERVICE="${REPO_ROOT}/${BOOKMARK_MUTATION_SERVICE_REL}"
BOOKMARK_FOLDER_SELECTION_COMPONENT_REL="AiraBrowser/entry/src/main/ets/app/components/bookmarks/BookmarkMoveFolderSelectionSheet.ets"
BOOKMARK_FOLDER_SELECTION_COMPONENT="${REPO_ROOT}/${BOOKMARK_FOLDER_SELECTION_COMPONENT_REL}"
OLD_BOOKMARK_ACTION_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBookmarkActionViewModel.ets"
OLD_BOOKMARK_ACTION_VIEW_MODEL="${REPO_ROOT}/${OLD_BOOKMARK_ACTION_VIEW_MODEL_REL}"
ADDRESS_SUBMISSION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/navigation/BrowserAddressSubmissionCoordinator.ets"
ADDRESS_SUBMISSION_COORDINATOR="${REPO_ROOT}/${ADDRESS_SUBMISSION_COORDINATOR_REL}"
ERROR_DOCUMENT_LOAD_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/services/web/BrowserErrorDocumentLoadCoordinator.ets"
ERROR_DOCUMENT_LOAD_COORDINATOR="${REPO_ROOT}/${ERROR_DOCUMENT_LOAD_COORDINATOR_REL}"
SEARCH_ENGINE_ROUTING_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/search/SearchEngineRoutingService.ets"
SEARCH_ENGINE_ROUTING_SERVICE="${REPO_ROOT}/${SEARCH_ENGINE_ROUTING_SERVICE_REL}"
WEB_LOAD_ERROR_DOCUMENT_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/web/WebLoadErrorDocumentService.ets"
WEB_LOAD_ERROR_DOCUMENT_SERVICE="${REPO_ROOT}/${WEB_LOAD_ERROR_DOCUMENT_SERVICE_REL}"
MEDIA_RESOURCE_SESSION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserMediaResourceSessionCoordinator.ets"
MEDIA_RESOURCE_SESSION_COORDINATOR="${REPO_ROOT}/${MEDIA_RESOURCE_SESSION_COORDINATOR_REL}"
OLD_MEDIA_MANIFEST_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserMediaManifestCoordinator.ets"
OLD_MEDIA_MANIFEST_COORDINATOR="${REPO_ROOT}/${OLD_MEDIA_MANIFEST_COORDINATOR_REL}"
WEBPAGE_TRANSLATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/translation/WebpageTranslationCoordinator.ets"
WEBPAGE_TRANSLATION_COORDINATOR="${REPO_ROOT}/${WEBPAGE_TRANSLATION_COORDINATOR_REL}"
TOP_FLOATING_PROMPT_HOST_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTopFloatingPromptHost.ets"
TOP_FLOATING_PROMPT_HOST="${REPO_ROOT}/${TOP_FLOATING_PROMPT_HOST_REL}"
TOP_FLOATING_SURFACE_REL="AiraBrowser/entry/src/main/ets/app/components/common/TopFloatingSurface.ets"
TOP_FLOATING_SURFACE="${REPO_ROOT}/${TOP_FLOATING_SURFACE_REL}"
OLD_WEBPAGE_TRANSLATION_SURFACE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/translation/WebpageTranslationSurfaceCoordinator.ets"
OLD_WEBPAGE_TRANSLATION_SURFACE_COORDINATOR="${REPO_ROOT}/${OLD_WEBPAGE_TRANSLATION_SURFACE_COORDINATOR_REL}"
SITE_CONTROLS_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserSiteControlsRuntimeCoordinator.ets"
SITE_CONTROLS_COORDINATOR="${REPO_ROOT}/${SITE_CONTROLS_COORDINATOR_REL}"
SITE_CONTROLS_MANAGEMENT_PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/SiteControlsManagementPage.ets"
SITE_CONTROLS_MANAGEMENT_PAGE="${REPO_ROOT}/${SITE_CONTROLS_MANAGEMENT_PAGE_REL}"
COOKIE_MANAGEMENT_PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/CookieManagementPage.ets"
COOKIE_MANAGEMENT_PAGE="${REPO_ROOT}/${COOKIE_MANAGEMENT_PAGE_REL}"
COOKIE_MANAGEMENT_CONTENT_REL="AiraBrowser/entry/src/main/ets/app/components/settings/CookieManagementContent.ets"
COOKIE_MANAGEMENT_CONTENT="${REPO_ROOT}/${COOKIE_MANAGEMENT_CONTENT_REL}"
SITE_INFO_SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserSiteInfoSheet.ets"
SITE_INFO_SHEET="${REPO_ROOT}/${SITE_INFO_SHEET_REL}"
WEB_PAGE_TOOLS_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebPageToolsCoordinator.ets"
WEB_PAGE_TOOLS_COORDINATOR="${REPO_ROOT}/${WEB_PAGE_TOOLS_COORDINATOR_REL}"
WEB_PAGE_TOOLS_OVERLAY_HOST_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserWebPageToolsOverlayHost.ets"
WEB_PAGE_TOOLS_OVERLAY_HOST="${REPO_ROOT}/${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}"
SAMSUNG_VIDEO_ASSISTANT_PLAYER_OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserSamsungVideoAssistantPlayerOverlay.ets"
SAMSUNG_VIDEO_ASSISTANT_PLAYER_OVERLAY="${REPO_ROOT}/${SAMSUNG_VIDEO_ASSISTANT_PLAYER_OVERLAY_REL}"
ARK_WEB_MEDIA_TAKEOVER_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/media/BrowserArkWebMediaTakeoverCoordinator.ets"
ARK_WEB_MEDIA_TAKEOVER_COORDINATOR="${REPO_ROOT}/${ARK_WEB_MEDIA_TAKEOVER_COORDINATOR_REL}"
WEB_ERROR_LAYER_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserWebErrorLayer.ets"
WEB_ERROR_LAYER="${REPO_ROOT}/${WEB_ERROR_LAYER_REL}"
OLD_WEB_PAGE_TOOLS_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebPageToolsSheetViewModel.ets"
OLD_WEB_PAGE_TOOLS_VIEW_MODEL="${REPO_ROOT}/${OLD_WEB_PAGE_TOOLS_VIEW_MODEL_REL}"
USER_AGENT_ACTION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserUserAgentActionCoordinator.ets"
USER_AGENT_ACTION_COORDINATOR="${REPO_ROOT}/${USER_AGENT_ACTION_COORDINATOR_REL}"
USER_AGENT_RUNTIME_POLICY_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserUserAgentRuntimePolicyCoordinator.ets"
USER_AGENT_RUNTIME_POLICY_COORDINATOR="${REPO_ROOT}/${USER_AGENT_RUNTIME_POLICY_COORDINATOR_REL}"
BROWSING_IDENTITY_POLICY_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBrowsingIdentityPolicyCoordinator.ets"
BROWSING_IDENTITY_POLICY_COORDINATOR="${REPO_ROOT}/${BROWSING_IDENTITY_POLICY_COORDINATOR_REL}"
BROWSING_IDENTITY_DECISION_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/web/BrowserBrowsingIdentityDecisionService.ets"
BROWSING_IDENTITY_DECISION_SERVICE="${REPO_ROOT}/${BROWSING_IDENTITY_DECISION_SERVICE_REL}"
UNIFIED_LINK_APPLICATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserUnifiedLinkApplicationCoordinator.ets"
UNIFIED_LINK_APPLICATION_COORDINATOR="${REPO_ROOT}/${UNIFIED_LINK_APPLICATION_COORDINATOR_REL}"
UNIFIED_LINK_NAVIGATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserUnifiedLinkNavigationCoordinator.ets"
UNIFIED_LINK_NAVIGATION_COORDINATOR="${REPO_ROOT}/${UNIFIED_LINK_NAVIGATION_COORDINATOR_REL}"
EXTERNAL_NAVIGATION_INFO_BAR_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserExternalNavigationInfoBarApplicationCoordinator.ets"
EXTERNAL_NAVIGATION_INFO_BAR_COORDINATOR="${REPO_ROOT}/${EXTERNAL_NAVIGATION_INFO_BAR_COORDINATOR_REL}"
EXTERNAL_NAVIGATION_PROMPT_CARD_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserExternalNavigationPromptCard.ets"
EXTERNAL_NAVIGATION_PROMPT_CARD="${REPO_ROOT}/${EXTERNAL_NAVIGATION_PROMPT_CARD_REL}"
WEB_ACTIVE_SURFACE_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebActiveSurfaceCoordinator.ets"
WEB_ACTIVE_SURFACE_COORDINATOR="${REPO_ROOT}/${WEB_ACTIVE_SURFACE_COORDINATOR_REL}"
WEB_PAGE_FEATURE_EFFECTS_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebPageFeatureEffectsCoordinator.ets"
WEB_PAGE_FEATURE_EFFECTS_COORDINATOR="${REPO_ROOT}/${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR_REL}"
PAGE_CHROME_THEME_SAMPLING_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPageChromeThemeSamplingCoordinator.ets"
PAGE_CHROME_THEME_SAMPLING_COORDINATOR="${REPO_ROOT}/${PAGE_CHROME_THEME_SAMPLING_COORDINATOR_REL}"
PAGE_CHROME_THEME_PROBE_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserPageChromeThemeProbe.ets"
PAGE_CHROME_THEME_PROBE="${REPO_ROOT}/${PAGE_CHROME_THEME_PROBE_REL}"
MEDIA_DISCOVERY_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/media/BrowserMediaDiscoveryCoordinator.ets"
MEDIA_DISCOVERY_COORDINATOR="${REPO_ROOT}/${MEDIA_DISCOVERY_COORDINATOR_REL}"
MEDIA_DISCOVERY_MODELS_REL="AiraBrowser/entry/src/main/ets/core/browser/media/BrowserMediaDiscoveryModels.ets"
MEDIA_DISCOVERY_MODELS="${REPO_ROOT}/${MEDIA_DISCOVERY_MODELS_REL}"
MEDIA_RUNTIME_OBSERVATION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/media/BrowserMediaRuntimeObservationApplicationCoordinator.ets"
MEDIA_RUNTIME_OBSERVATION_COORDINATOR="${REPO_ROOT}/${MEDIA_RUNTIME_OBSERVATION_COORDINATOR_REL}"
MEDIA_FRAME_RUNTIME_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/media/BrowserMediaFrameRuntimeCoordinator.ets"
MEDIA_FRAME_RUNTIME_COORDINATOR="${REPO_ROOT}/${MEDIA_FRAME_RUNTIME_COORDINATOR_REL}"
MEDIA_DISCOVERY_RUNTIME_FACTORY_REL="AiraBrowser/entry/src/main/ets/core/browser/media/BrowserMediaDiscoveryRuntimeFactory.ets"
MEDIA_DISCOVERY_RUNTIME_FACTORY="${REPO_ROOT}/${MEDIA_DISCOVERY_RUNTIME_FACTORY_REL}"
MEDIA_CANDIDATE_MODELS_REL="AiraBrowser/entry/src/main/ets/features/mediaDiscovery/MediaCandidateModels.ets"
MEDIA_CANDIDATE_MODELS="${REPO_ROOT}/${MEDIA_CANDIDATE_MODELS_REL}"
MEDIA_EVIDENCE_GRAPH_REL="AiraBrowser/entry/src/main/ets/services/media/MediaEvidenceGraph.ets"
MEDIA_EVIDENCE_GRAPH="${REPO_ROOT}/${MEDIA_EVIDENCE_GRAPH_REL}"
PROFILE_ACQUISITION_RECIPE_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/media/VideoCompatibilityProfileAcquisitionRecipeService.ets"
PROFILE_ACQUISITION_RECIPE_SERVICE="${REPO_ROOT}/${PROFILE_ACQUISITION_RECIPE_SERVICE_REL}"
OLD_YOUTUBE_TAKEOVER_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserYoutubeTakeoverCoordinator.ets"
OLD_YOUTUBE_TAKEOVER_COORDINATOR="${REPO_ROOT}/${OLD_YOUTUBE_TAKEOVER_COORDINATOR_REL}"
OLD_NATIVE_MEDIA_CANDIDATE_PUBLISHER_REL="AiraBrowser/entry/src/main/ets/services/video/NativeMediaCandidatePublisherService.ets"
OLD_NATIVE_MEDIA_CANDIDATE_PUBLISHER="${REPO_ROOT}/${OLD_NATIVE_MEDIA_CANDIDATE_PUBLISHER_REL}"
OLD_NATIVE_MEDIA_SIGNAL_ADAPTER_REL="AiraBrowser/entry/src/main/ets/services/media/NativeMediaSignalAdapter.ets"
OLD_NATIVE_MEDIA_SIGNAL_ADAPTER="${REPO_ROOT}/${OLD_NATIVE_MEDIA_SIGNAL_ADAPTER_REL}"
OLD_NATIVE_MEDIA_CANDIDATE_MODELS_REL="AiraBrowser/entry/src/main/ets/features/nativeVideoTakeover/NativeMediaCandidateModels.ets"
OLD_NATIVE_MEDIA_CANDIDATE_MODELS="${REPO_ROOT}/${OLD_NATIVE_MEDIA_CANDIDATE_MODELS_REL}"
YOUTUBE_EXTRACTOR_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/youtube/YoutubeExtractorService.ets"
YOUTUBE_EXTRACTOR_SERVICE="${REPO_ROOT}/${YOUTUBE_EXTRACTOR_SERVICE_REL}"
YOUTUBE_INNERTUBE_PLAYER_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/youtube/YoutubeInnertubePlayerService.ets"
YOUTUBE_INNERTUBE_PLAYER_SERVICE="${REPO_ROOT}/${YOUTUBE_INNERTUBE_PLAYER_SERVICE_REL}"
MEDIA_PROBE_SCHEDULER_REL="AiraBrowser/entry/src/main/ets/core/browser/media/BrowserMediaProbeScheduler.ets"
MEDIA_PROBE_SCHEDULER="${REPO_ROOT}/${MEDIA_PROBE_SCHEDULER_REL}"
MEDIA_PROBE_POLICY_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/media/MediaProbePolicyService.ets"
MEDIA_PROBE_POLICY_SERVICE="${REPO_ROOT}/${MEDIA_PROBE_POLICY_SERVICE_REL}"
WEB_TOP_IMMERSION_SESSION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebTopImmersionSessionCoordinator.ets"
WEB_TOP_IMMERSION_SESSION_COORDINATOR="${REPO_ROOT}/${WEB_TOP_IMMERSION_SESSION_COORDINATOR_REL}"
WEB_SCROLL_INTERACTION_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebScrollInteractionCoordinator.ets"
WEB_SCROLL_INTERACTION_COORDINATOR="${REPO_ROOT}/${WEB_SCROLL_INTERACTION_COORDINATOR_REL}"
OLD_WEB_BOTTOM_CHROME_SCROLL_INPUT_VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserWebBottomChromeScrollInputViewModel.ets"
OLD_WEB_BOTTOM_CHROME_SCROLL_INPUT_VIEW_MODEL="${REPO_ROOT}/${OLD_WEB_BOTTOM_CHROME_SCROLL_INPUT_VIEW_MODEL_REL}"
OLD_BOTTOM_CHROME_SCROLL_IDLE_SETTLE_SCHEDULER_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomChromeScrollIdleSettleScheduler.ets"
OLD_BOTTOM_CHROME_SCROLL_IDLE_SETTLE_SCHEDULER="${REPO_ROOT}/${OLD_BOTTOM_CHROME_SCROLL_IDLE_SETTLE_SCHEDULER_REL}"
SHELL_PRESENTATION_TOKENS_REL="AiraBrowser/entry/src/main/ets/app/components/browser/BrowserShellPresentationTokens.ets"
SHELL_PRESENTATION_TOKENS="${REPO_ROOT}/${SHELL_PRESENTATION_TOKENS_REL}"
WINDOW_OPEN_CONTRACT_GUARD_REL="scripts/check-aira-window-open-contract.sh"
WINDOW_OPEN_CONTRACT_GUARD="${REPO_ROOT}/${WINDOW_OPEN_CONTRACT_GUARD_REL}"

SHELL_MAX_LINES="${ARCH_GUARD_BROWSER_SHELL_MAX_LINES:-0}"
PAGE_MAX_LINES="${ARCH_GUARD_PAGE_MAX_LINES:-1800}"
SHELL_DIFF_ADDED_LIMIT="${ARCH_GUARD_BROWSER_SHELL_DIFF_ADDED_LIMIT:-0}"
PAGE_DIFF_ADDED_LIMIT="${ARCH_GUARD_PAGE_DIFF_ADDED_LIMIT:-220}"

if [ ! -x "${WINDOW_OPEN_CONTRACT_GUARD}" ]; then
  echo "Architecture guardrail failed: window-open static contract guard is missing or not executable: ${WINDOW_OPEN_CONTRACT_GUARD_REL}" >&2
  exit 1
fi

"${WINDOW_OPEN_CONTRACT_GUARD}"

if [ "${ARCH_GUARD_SKIP:-0}" = "1" ]; then
  echo "Architecture guardrails skipped by ARCH_GUARD_SKIP=1."
  exit 0
fi

if [ ! -d "${PAGE_DIR}" ]; then
  echo "Architecture guardrail failed: page directory not found: ${PAGE_DIR_REL}" >&2
  exit 1
fi

failures=0

report_failure() {
  failures=$((failures + 1))
  printf 'Architecture guardrail failed: %s\n' "$1" >&2
}

line_count() {
  wc -l "$1" | awk '{ print $1 }'
}

check_file_contains_rule() {
  local file_path="$1"
  local rel_path="$2"
  local pattern="$3"
  local message="$4"
  if ! grep -Eq "$pattern" "${file_path}"; then
    report_failure "${rel_path} ${message}"
  fi
}

check_file_not_contains_rule() {
  local file_path="$1"
  local rel_path="$2"
  local pattern="$3"
  local message="$4"
  if grep -Eq "$pattern" "${file_path}"; then
    report_failure "${rel_path} ${message}"
  fi
}

read_numeric_constant() {
  local file_path="$1"
  local constant_name="$2"
  sed -nE "s/.*${constant_name}: number = ([0-9]+);/\1/p" "${file_path}" | head -n 1
}

check_search_list_geometry_invariants() {
  local row_height
  local content_frame_height
  local clip_gap
  local external_strip_height
  local external_item_width
  local external_action_size
  local external_item_center_pitch
  row_height="$(read_numeric_constant "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" "BROWSER_SEARCH_LIST_DEFAULT_ROW_HEIGHT")"
  content_frame_height="$(read_numeric_constant "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" "BROWSER_SEARCH_LIST_ROW_CONTENT_FRAME_HEIGHT")"
  clip_gap="$(read_numeric_constant "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" "BROWSER_SEARCH_LIST_SCROLL_CLIP_SAFETY_GAP")"
  external_strip_height="$(read_numeric_constant "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" "BROWSER_SEARCH_LIST_EXTERNAL_STRIP_HEIGHT")"
  external_item_width="$(read_numeric_constant "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" "BROWSER_SEARCH_LIST_EXTERNAL_ITEM_WIDTH")"
  external_action_size="$(read_numeric_constant "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" "BROWSER_SEARCH_LIST_EXTERNAL_ACTION_SIZE")"
  external_item_center_pitch="$(read_numeric_constant "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" \
    "BROWSER_SEARCH_LIST_EXTERNAL_ITEM_CENTER_PITCH")"

  if [ -z "${row_height}" ] || [ -z "${content_frame_height}" ] || [ -z "${clip_gap}" ] || \
    [ -z "${external_strip_height}" ] || [ -z "${external_item_width}" ] || \
    [ -z "${external_action_size}" ] || [ -z "${external_item_center_pitch}" ]; then
    report_failure "${SEARCH_LIST_LAYOUT_VIEW_MODEL_REL} must declare numeric row, content-frame, clip-gap, and external-strip invariants."
    return
  fi
  if [ "${row_height}" -ne 54 ] || [ "${content_frame_height}" -ne 36 ]; then
    report_failure "${SEARCH_LIST_LAYOUT_VIEW_MODEL_REL} regular rows must keep a 54vp touch frame with one 36vp visible-content frame."
  fi
  if [ "${content_frame_height}" -ge "${row_height}" ]; then
    report_failure "${SEARCH_LIST_LAYOUT_VIEW_MODEL_REL} visible content must retain bottom-placement headroom inside the touch row."
  fi
  if [ "${clip_gap}" -le 0 ]; then
    report_failure "${SEARCH_LIST_LAYOUT_VIEW_MODEL_REL} scroll clipping must retain a positive safety gap above external targets."
  fi
  if [ "${external_strip_height}" -ne 66 ] || [ "${external_item_width}" -ne 48 ] || \
    [ "${external_action_size}" -ne 42 ] || [ "${external_item_center_pitch}" -ne 74 ]; then
    report_failure "${SEARCH_LIST_LAYOUT_VIEW_MODEL_REL} external targets must preserve the 66vp strip, 48vp item frame, 42vp action, and 74vp center pitch."
  fi
  local content_frame_consumers
  content_frame_consumers="$(grep -Ec '\.height\(this\.resolveRowContentFrameHeight\(\)\)' \
    "${SEARCH_SUGGESTIONS_PANEL}" || true)"
  if [ "${content_frame_consumers}" -lt 2 ]; then
    report_failure "${SEARCH_SUGGESTIONS_PANEL_REL} title/history content and delete action must consume the same projected content frame."
  fi
}

while IFS= read -r page_file; do
  lines="$(line_count "${page_file}")"
  rel_path="${page_file#${REPO_ROOT}/}"
  if [ "${rel_path}" = "${SHELL_PAGE_REL}" ]; then
    if [ "${SHELL_MAX_LINES}" -gt 0 ] && [ "${lines}" -gt "${SHELL_MAX_LINES}" ]; then
      report_failure "${SHELL_PAGE_REL} has ${lines} lines; limit is ${SHELL_MAX_LINES}. Move logic into core/services/features before growing the shell."
    fi
    continue
  fi

  if [ "${lines}" -gt "${PAGE_MAX_LINES}" ]; then
    report_failure "${rel_path} has ${lines} lines; limit is ${PAGE_MAX_LINES}. Split logic or repeated UI sections into components/services/view models."
  fi
done < <(find "${PAGE_DIR}" -maxdepth 1 -type f -name '*.ets' | sort)

check_file_contains_rule "${WEB_VIEWPORT_COORDINATOR}" "${WEB_VIEWPORT_COORDINATOR_REL}" \
  'BrowserWebViewportPresentationState' \
  "Web viewport render presentation state must stay owned outside BrowserShellPage."
check_file_contains_rule "${WEB_VIEWPORT_COORDINATOR}" "${WEB_VIEWPORT_COORDINATOR_REL}" \
  'resolvePresentationUpdate' \
  "Web viewport presentation updates must stay centralized in BrowserWebViewportCoordinator."
check_file_contains_rule "${WEB_VIEWPORT_COORDINATOR}" "${WEB_VIEWPORT_COORDINATOR_REL}" \
  'resolveLayerLayout' \
  "Web viewport layer geometry must stay centralized in BrowserWebViewportCoordinator."
check_file_contains_rule "${WEB_VIEWPORT_COORDINATOR}" "${WEB_VIEWPORT_COORDINATOR_REL}" \
  'resolveVisibleTopChromeInset' \
  "Web viewport conditional occupied top-chrome height must stay centralized in BrowserWebViewportCoordinator."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State webViewportPresentation: BrowserWebViewportPresentationState' \
  "Web viewport render path must bind to owner presentation state."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'overlayHeightPx: this\.webViewportPresentation\.topSafeOverlayHeightPx' \
  "BrowserShellPage must pass owner-projected top-overlay height into the extracted top-chrome renderer."
check_file_contains_rule "${WEB_TOP_CHROME_OVERLAY}" "${WEB_TOP_CHROME_OVERLAY_REL}" \
  'height\(this\.overlayHeightPx\)' \
  "The extracted Web top-chrome renderer must bind its height to the owner presentation input."
check_file_contains_rule "${WEB_VIEWPORT_SURFACE_HOST}" "${WEB_VIEWPORT_SURFACE_HOST_REL}" \
  "height\(this\.presentation\.fillParentHeight \? '100%' : Math\.max\(1, this\.presentation\.contentHeightPx\)\)" \
  "Web viewport content height must bind to owner presentation state."
check_file_contains_rule "${WEB_VIEWPORT_SURFACE_HOST}" "${WEB_VIEWPORT_SURFACE_HOST_REL}" \
  'y: this\.presentation\.fillParentHeight \? 0 : this\.presentation\.contentTopPx' \
  "Web viewport content position must bind to owner presentation state."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'presentation: this\.webViewportPresentation' \
  "BrowserShellPage must bind the complete owner-projected Web viewport state into the extracted renderer."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'largeScreenShellActive: this\.isLargeScreenShellFamilyActive\(\)' \
  "BrowserShellPage must forward the current Large-Screen shell fact into Web viewport geometry ownership."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'nativeVideoTakeoverActive: this\.isAssistantVideoTakeoverActive\(\)' \
  "BrowserShellPage must forward only the current shell/takeover facts into Web viewport geometry ownership."
check_file_contains_rule "${WEB_VIEWPORT_SURFACE_HOST}" "${WEB_VIEWPORT_SURFACE_HOST_REL}" \
  "height\(this\.presentation\.fillParentHeight \? '100%' : Math\.max\(1, this\.presentation\.hostHeightPx\)\)" \
  "The extracted Web viewport host must keep normal numeric height while resolving Large-Screen/takeover axes from one parent layout."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'height\(this\.getWebViewportVisualTopInsetPx\(\)\)|height\(this\.resolveWebViewportContentHeightPx\(\)\)|height\(this\.resolveWebViewportHostHeight\(\)\)' \
  "Web viewport render hot path must not call page-owned geometry helpers directly."
check_file_contains_rule "${QUICK_SEARCH_SWITCHING_COORDINATOR}" "${QUICK_SEARCH_SWITCHING_COORDINATOR_REL}" \
  'getBackForwardEntries\(\)' \
  "Quick Search Switching must own fail-closed ArkWeb history correlation outside BrowserShellPage."
check_file_contains_rule "${QUICK_SEARCH_SWITCHING_COORDINATOR}" "${QUICK_SEARCH_SWITCHING_COORDINATOR_REL}" \
  'templateService\.buildSearchUrl' \
  "Quick Search Switching must build an exact selected-engine URL without entering Smart Search Fallback."
check_file_contains_rule "${QUICK_SEARCH_SWITCHING_COORDINATOR}" "${QUICK_SEARCH_SWITCHING_COORDINATOR_REL}" \
  'BROWSER_QUICK_SEARCH_SWITCH_BAR_HEIGHT: number = 48' \
  "Quick Search Switching must preserve the accepted 48vp occupied/touch-height contract."
check_file_contains_rule "${QUICK_SEARCH_SWITCHING_COORDINATOR}" "${QUICK_SEARCH_SWITCHING_COORDINATOR_REL}" \
  'reconcileOwnedHistoryReplacement\(' \
  "Quick Search Switching must distinguish owned result-document replaceState stabilization from later webpage navigation."
check_file_contains_rule "${QUICK_SEARCH_SWITCHING_COORDINATOR}" "${QUICK_SEARCH_SWITCHING_COORDINATOR_REL}" \
  'isPendingOwnedMainFrameNewEntryCommit\(' \
  "Quick Search Switching must own commit-before-page-begin correlation for regionalized result URLs."
check_file_contains_rule "${QUICK_SEARCH_SWITCHING_COORDINATOR}" "${QUICK_SEARCH_SWITCHING_COORDINATOR_REL}" \
  'reconcileOwnedCommittedEntryReplacement\(' \
  "Quick Search Switching must preserve an owned initialization transaction when ArkWeb replaces the same committed history entry."
check_file_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'handleHistoryApiUrlChange\(tabId, normalizedEvent\)' \
  "Web Page Lifecycle must forward normalized typed History API facts to the Quick Search owner."
check_file_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'navigationType: details\.navigationType' \
  "Web Page Lifecycle must forward ArkWeb committed-navigation type facts to the Quick Search owner."
check_file_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'isSameDocument: details\.isSameDocument' \
  "Web Page Lifecycle must forward ArkWeb same-document facts to the Quick Search owner."
check_file_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'didReplaceEntry: details\.didReplaceEntry' \
  "Web Page Lifecycle must forward ArkWeb entry-replacement facts to the Quick Search owner."
check_file_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'quickSearchSwitchingCoordinator\.handleLoadFinished\(tabId\)' \
  "Web Page Lifecycle must close Quick Search result-document initialization at load completion."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'this\.browserQuickSearchSwitchingCoordinator\.selectEngine\(engineId\)' \
  "BrowserShellPage must keep quick-search engine selection as one-line owner forwarding."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'getBackForwardEntries\(\)|buildQuickSearch|resolveQuickSearch|quickSearchContext' \
  "BrowserShellPage must not regain Quick Search context, history correlation, URL construction, or presentation policy."
check_file_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'shouldRenderSharedSnapshotEntryOverlay\(' \
  "Tabs Session must own Shared Snapshot entry-overlay visibility policy."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State tabsOverviewPresentationState: BrowserTabsOverviewSessionPresentationState' \
  "Tabs overview must keep one first-level Session presentation snapshot for ArkUI render observation."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State tabsSharedSnapshotState: BrowserTabsSharedSnapshotTransitionState' \
  "Shared Snapshot image state must keep a first-level ArkUI render binding."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'this\.tabsSharedSnapshotState = state\.sharedSnapshotState' \
  "Shared Snapshot ArkUI render state must mirror the Session-owned presentation state."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'state: this\.tabsSharedSnapshotState' \
  "Shared Snapshot root overlay must consume the first-level ArkUI render binding."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'entrySharedSnapshotState: this\.tabsSharedSnapshotState' \
  "Shared Snapshot entry overlay must consume the first-level ArkUI render binding."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'shouldShowSharedSnapshotOverlay\(this\.tabsSharedSnapshotState\)' \
  "Shared Snapshot root render predicate must explicitly observe the first-level ArkUI state."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'shouldRenderSharedSnapshotEntryOverlay\([[:space:]]*this\.tabsSharedSnapshotState' \
  "Shared Snapshot entry render predicate must explicitly observe the first-level ArkUI state."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'buildRenderState\(this\.tabsOverviewPresentationState\)' \
  "Tabs overview scene render predicates must explicitly observe the Session presentation snapshot."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private shouldRenderTabsOverviewEntrySnapshotOverlay\(' \
  "BrowserShellPage must not regain Shared Snapshot entry-overlay visibility policy."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'tabsOverlayContentOffsetY|tabsOverlayContentOffsetX|tabsOverlayContentOpacity|tabsOverlayContentBlurRadius|tabsOverlayWebChromeOpacity|tabsOverlayWebTopChromeOffsetY|tabsOverlayWebBottomChromeOffsetY|tabsBackdropSnapshotSourceMounted|tabsBackdropHomeRevealVisible|tabsBackdropHomeRevealOpacity|tabsOverviewLockedSnapshotTabId' \
  "BrowserShellPage must not regain deleted Tabs Overview scalar presentation, backdrop-source, or snapshot-lock state."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "case 'ensure_private_mode_unlocked'|case 'restore_private_mode_cookies'|case 'sync_web_app_immersive_visual'|case 'sync_web_top_immersion_policy'|case 'sync_current_active_from_host'" \
  "Tabs Overview fixed Private/Profile/Top-Immersion/Hosted-Runtime dependencies must not return through page tasks or effects."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "case 'play_tabs_overview_entry_backdrop_transition'|case 'play_tabs_overview_home_reveal_entry_animation'|case 'play_tabs_overview_exit_animation'|case 'play_tabs_overview_backdrop_progress_transition'|private playTabsOverviewBackdropProgressTransition\(|private async playTabsOverviewHomeRevealExitAnimation\(|private recoverWebLayerOpacityAfterStaleTabsOverviewEntryAnimation\(|private applyTabsOverviewClosedResetPatch\(" \
  "Tabs Overview timing, run validation, recovery, and closed-reset policy must not return to BrowserShellPage."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "case 'play_shared_snapshot_transition'|private playSharedSnapshotTransition\(|private revealWebChromeForSharedSnapshot\(|private animateSharedSnapshotProgressAfterMount\(|isSharedSnapshotRunCurrent\(|publishSharedSnapshotProgress\(" \
  "Shared Snapshot timing, run validation, progress publication, and handoff completion must stay in the Tabs Session owner."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "case 'play_tabs_overview_arkui_animation'" \
  "BrowserShellPage must keep only the typed ArkUI animation execution boundary for Tabs Overview."
check_file_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'BrowserTabsOverviewArkUiAnimationPlan' \
  "Tabs Session must own typed ArkUI animation plans instead of exposing procedural run controls to the page."
check_file_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'private playSharedSnapshotTransition\(' \
  "Tabs Session must own Shared Snapshot animation scheduling and completion choreography."
check_file_not_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'entryMode: string|entryMode\?: string|ensureTabsBackdropSnapshot\(' \
  "Tabs Session must keep a typed entry mode and must not restore the inert always-success backdrop wrapper."
check_file_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'privateModeLockCoordinator\.ensureUnlocked' \
  "Tabs Session must call the fixed Private Mode lock owner directly."
check_file_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'privateProfileLifecycleCoordinator\.restorePreservedCookiesOnEnterIfNeeded' \
  "Tabs Session must call the fixed Private Profile lifecycle owner directly."
check_file_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'hostedRuntimeSurfacePort\.syncCurrentActiveFromHost' \
  "Tabs Session must call the fixed Hosted Runtime fallback port directly."
check_file_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'webTopImmersionSessionCoordinator\.requestVisible' \
  "Tabs Session must own its fixed Top Immersion entry request."
check_file_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'webTopImmersionSessionCoordinator\.syncPolicy' \
  "Tabs Session must own its fixed Top Immersion reset."
check_file_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  'backgroundOpenPromptCoordinator\.dismissAll' \
  "Tabs Session must call the fixed Background Open Prompt owner directly."
check_file_contains_rule "${FULLSCREEN_SESSION_COORDINATOR}" "${FULLSCREEN_SESSION_COORDINATOR_REL}" \
  'toggleManualFullscreen' \
  "manual fullscreen must stay in the unified Session owner."
check_file_contains_rule "${FULLSCREEN_SESSION_COORDINATOR}" "${FULLSCREEN_SESSION_COORDINATOR_REL}" \
  'enterWebContentFullscreen' \
  "ArkWeb fullscreen must stay in the unified Session owner."
check_file_contains_rule "${FULLSCREEN_SESSION_COORDINATOR}" "${FULLSCREEN_SESSION_COORDINATOR_REL}" \
  'enterVideoAssistantFullscreen' \
  "Video Assistant fullscreen must stay in the unified Session owner."
check_file_contains_rule "${FULLSCREEN_SESSION_COORDINATOR}" "${FULLSCREEN_SESSION_COORDINATOR_REL}" \
  'applyScreenOrientationMode' \
  "screen orientation must stay in the unified Session owner."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State browserFullscreenSessionPresentation: BrowserFullscreenSessionPresentation' \
  "fullscreen and orientation presentation must be bound from the Session-owned snapshot."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserFullscreenSessionCoordinator\.enterWebContentFullscreen' \
  "ArkWeb fullscreen entry must forward to the unified Session owner."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State fullScreenModeEnabled|@State browserScreenOrientationMode|BrowserVideoAssistantFullscreenCoordinator|BrowserWebFullscreenPresentationCoordinator' \
  "must not regain fullscreen/orientation state or the superseded peer owners."
check_file_not_contains_rule "${NATIVE_FULLSCREEN_WINDOW_SERVICE}" "${NATIVE_FULLSCREEN_WINDOW_SERVICE_REL}" \
  'BrowserWebFullscreenPresentationCoordinator|BrowserWebFullscreenState' \
  "native fullscreen window service must remain a platform executor rather than a presentation owner."
if [ -e "${OLD_VIDEO_FULLSCREEN_COORDINATOR}" ]; then
  report_failure "${OLD_VIDEO_FULLSCREEN_COORDINATOR_REL} must stay deleted; Video Assistant fullscreen is subordinate to the unified Fullscreen Session."
fi

check_file_contains_rule "${APP_LAYOUT_TOKENS}" "${APP_LAYOUT_TOKENS_REL}" \
  'export const APP_STANDARD_HORIZONTAL_PADDING: number = 16;' \
  "standard horizontal padding must stay at 16vp for settings-style pages and browser bottom sheets."
check_file_contains_rule "${BOTTOM_SHEET}" "${BOTTOM_SHEET_REL}" \
  'export const BROWSER_MODAL_BOTTOM_SHEET_HORIZONTAL_PADDING: number = APP_STANDARD_HORIZONTAL_PADDING;' \
  "bottom sheet default horizontal padding must use APP_STANDARD_HORIZONTAL_PADDING."
check_file_contains_rule "${SETTINGS_LAYOUT}" "${SETTINGS_LAYOUT_REL}" \
  'left: APP_STANDARD_HORIZONTAL_PADDING' \
  "SettingsScrollBody must use APP_STANDARD_HORIZONTAL_PADDING for left content padding."
check_file_contains_rule "${SETTINGS_LAYOUT}" "${SETTINGS_LAYOUT_REL}" \
  'right: APP_STANDARD_HORIZONTAL_PADDING' \
  "SettingsScrollBody must use APP_STANDARD_HORIZONTAL_PADDING for right content padding."

check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserRootBottomPanelSessionCoordinator\.resolveActionSnapshot' \
  "bottom toolbar page-action state must be projected through BrowserRootBottomPanelSessionCoordinator."
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'resolveActionSnapshot' \
  "bottom action presentation owner must expose the stable action snapshot path."
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'const actionRenderKey = this\.buildAddressPanelActionRenderKey' \
  "stable bottom action snapshots must derive their action render key inside the presentation owner."
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  '^[[:space:]]+actionRenderKey[[:space:]]*$' \
  "stable bottom action snapshots must carry their own action render key."
check_file_not_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  'semanticRenderKey|panelRenderKey|preserveAddressPanelIdentity|address-input-session' \
  "bottom panel identity must not depend on transient semantic, action, or focus state."
check_file_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  '@Prop layoutRenderKey: string' \
  "bottom panel Host must receive the Session-owned responsive layout invalidation key."
check_file_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  'ForEach\(\[this\.resolvePanelLayoutIdentity' \
  "bottom panel Host must invalidate frozen Builder content when responsive geometry changes."
check_file_not_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  '@Prop hostWidth|resolveEffectiveHostWidth' \
  "bottom panel Host must stay full-width instead of accepting externally resolved horizontal geometry."
check_file_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  '@Prop responsiveState: BrowserBottomPanelResponsiveState' \
  "bottom panel Host must receive responsive geometry as an explicit reactive prop."
check_file_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  '@BuilderParam homePanel: \(context: BrowserBottomPanelRenderContext\) => void' \
  "stable Home panel builders must receive one Host-owned render context."
check_file_not_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  'BrowserBottomAddressFocusRequestChannel|addressFocusRequests|homeAddressFocused|webAddressFocused' \
  "bottom panel Host must not split address focus out of the atomic live-presentation channel."
check_file_not_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  'struct BrowserBottomPanelLiveContentHost' \
  "bottom panel Host must not wrap the frozen parent BuilderParam in another nested Builder component."
check_file_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  'this\.homePanel\(this\.buildPanelRenderContext\(\)\)' \
  "Home panel must stay layout-keyed while consuming the Host-owned stable channels."
check_file_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  'this\.webPanel\(this\.buildPanelRenderContext\(\)\)' \
  "Web panel must stay layout-keyed while consuming the Host-owned stable channels."
check_file_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  'presentationChannel: this\.presentationChannel' \
  "layout-keyed panel builders must receive one stable live-presentation channel."
check_file_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  'this\.presentationChannel\.publish\(this\.livePresentation\)' \
  "the reactive Host must publish current bottom-chrome presentation outside the frozen Builder callback."
check_file_contains_rule "${BOTTOM_PANEL_PRESENTATION_CHANNEL}" "${BOTTOM_PANEL_PRESENTATION_CHANNEL_REL}" \
  'publish\(presentation: BrowserBottomPanelLivePresentation\): void' \
  "bottom-chrome presentation channel must expose one Host-side publication entry point."
check_file_contains_rule "${BOTTOM_PANEL_PRESENTATION_CHANNEL}" "${BOTTOM_PANEL_PRESENTATION_CHANNEL_REL}" \
  'connect\(listener: BrowserBottomPanelPresentationListener\): \(\) => boolean' \
  "bottom-chrome presentation channel must expose ownership-aware mounted-panel disconnect."
check_file_contains_rule "${BOTTOM_PANEL_PRESENTATION_CHANNEL}" "${BOTTOM_PANEL_PRESENTATION_CHANNEL_REL}" \
  'listener\(this\.presentation\)' \
  "bottom-chrome presentation channel must replay the latest projection to a late-mounted panel."
check_file_contains_rule "${BOTTOM_PANEL_PRESENTATION_CHANNEL}" "${BOTTOM_PANEL_PRESENTATION_CHANNEL_REL}" \
  'if \(this\.listener !== listener\)' \
  "stale bottom-panel disconnect must not clear a replacement panel listener."
check_file_contains_rule "${BOTTOM_PANEL_PRESENTATION_CHANNEL}" "${BOTTOM_PANEL_PRESENTATION_CHANNEL_REL}" \
  'addressFocused: boolean;' \
  "the atomic bottom-panel presentation must carry its native-focus request."
if [ -e "${OLD_BOTTOM_ADDRESS_FOCUS_REQUEST_CHANNEL}" ]; then
  report_failure "${OLD_BOTTOM_ADDRESS_FOCUS_REQUEST_CHANNEL_REL} must stay deleted; focus belongs to the atomic bottom-panel presentation."
fi
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'this\.presentationChannel\.connect\(this\.presentationListener\)' \
  "bottom address panel must consume Back, compact, motion, and prompt state through the stable presentation channel."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'const nextRequestedAddressFocused = presentation\.addressFocused' \
  "bottom address panel must apply focus from the same live-presentation callback as detent and chrome state."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'const ownsLivePresentation = this\.disconnectPresentationChannel\(\)' \
  "stale panel teardown must not clear the replacement input session after atomic presentation handoff."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  "airaIconId: 'browser\.toolbar\.tabs'" \
  "bottom tabs control must render the canonical font glyph."
check_file_not_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'resolveTabCountBadgeText|WEB_BOTTOM_TAB_COUNTER_' \
  "bottom tabs control must not restore the numeric counter renderer."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'BrowserBottomChromeRenderer\(' \
  "bottom address panel must delegate the five-mode material tree to the stable Bottom Chrome renderer."
check_file_not_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'resolveBottomChromeGeometry|WEB_BOTTOM_CHROME_COMPACT_CENTER_SCALE|bottomChromePresentationMode' \
  "bottom address panel must not regain local Bottom Chrome mode or geometry policy."
check_file_not_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  '\.animation\(' \
  "stable Bottom Chrome materials must use one explicit interruptible timeline instead of per-node animations."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'animateTo\(\{' \
  "stable Bottom Chrome materials must transition through one shared ArkUI property-animation transaction."
check_file_not_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'createAnimator\(|AnimatorResult|AnimatorOptions' \
  "Bottom Chrome must not regress to a complex frame object driven manually from AnimatorResult callbacks."
check_file_contains_rule "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL}" "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL}" \
  'class BrowserBottomChromeCenterContentPresentation' \
  "Bottom Chrome must project display, editing, and Return-Home content through one typed center-content value."
check_file_contains_rule "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL}" "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL}" \
  'BROWSER_BOTTOM_CHROME_COMPACT_WIDTH: number = 96' \
  "Scroll-Compact must keep the refined 96vp capsule width."
check_file_contains_rule "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL}" "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL}" \
  'BROWSER_BOTTOM_CHROME_COMPACT_HEIGHT: number = 32' \
  "Scroll-Compact must keep the refined 32vp capsule height."
check_file_contains_rule "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL}" "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL}" \
  'BROWSER_BOTTOM_CHROME_COMPACT_TRANSLATE_Y: number = 20' \
  "Scroll-Compact must keep the 32vp capsule inside the 52vp interaction rail."
check_file_contains_rule "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL}" "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL}" \
  'BROWSER_BOTTOM_CHROME_COMPACT_FLOATING_SURFACE_TRANSLATE_Y: number = 20' \
  "Scroll-Compact must preserve the requested 40vp movement with the refined capsule."
check_file_contains_rule "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL}" "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL}" \
  'BROWSER_BOTTOM_CHROME_COMPACT_DISPLAY_SCALE: number = 14 / 15' \
  "Scroll-Compact must reduce display text visually without animating paragraph metrics."
check_file_not_contains_rule "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL}" "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL}" \
  'centerTextTranslateY|TEXT_OPTICAL_OFFSET_Y' \
  "Bottom Chrome presentation must not restore device-specific text offsets."
check_file_not_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'BROWSER_BOTTOM_CHROME_SHADOW_OFFSET_[XY]' \
  "Bottom Chrome material shadow must not restore a directional offset token."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'offsetY: 0' \
  "Bottom Chrome material shadow must remain centered around the floating surface."
check_file_contains_rule "${BOTTOM_CHROME_MATERIAL_TOKENS}" "${BOTTOM_CHROME_MATERIAL_TOKENS_REL}" \
  "BROWSER_BOTTOM_CHROME_DARK_MATERIAL_TINT: ResourceColor = '#332C2C2E'" \
  "Bottom Chrome dark material must remain a distinguishable neutral gray instead of a pure-black tint."
check_file_not_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'materialBorderWidth|materialBorderColor|BROWSER_BOTTOM_CHROME_BORDER' \
  "Bottom Chrome floating materials must use the semantic edge-highlight surface API."
check_file_not_contains_rule "${BOTTOM_CHROME_MATERIAL_TOKENS}" "${BOTTOM_CHROME_MATERIAL_TOKENS_REL}" \
  'BROWSER_BOTTOM_CHROME_.*BORDER' \
  "Bottom Chrome must not add ad-hoc theme border tokens."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'edgeHighlightWidth: BROWSER_BOTTOM_CHROME_EDGE_HIGHLIGHT_WIDTH' \
  "Bottom Chrome must render its narrow theme edge highlight through the shared material surface."
check_file_contains_rule "${BOTTOM_CHROME_MATERIAL_TOKENS}" "${BOTTOM_CHROME_MATERIAL_TOKENS_REL}" \
  'resolveBrowserBottomChromeEdgeHighlightColor' \
  "Bottom Chrome edge highlight color must remain theme-aware."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'resolveBrowserBottomChromeMaterialTintForMode\(this\.resolveNeutralThemeMode\(\)\)' \
  "Bottom Address Panel must consume the Bottom Chrome-specific semantic material tint."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  '\.halfLeading\(true\)' \
  "Bottom Chrome display, placeholder, and Return-Home text must split explicit line leading evenly."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  '\.textVerticalAlign\(TextVerticalAlign\.CENTER\)' \
  "Bottom Chrome display, placeholder, and Return-Home text must use native paragraph centering."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  '\.halfLeading\(true\)' \
  "Bottom Chrome editing text and placeholder must use native half-leading layout."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL_METRICS}" "${BOTTOM_ADDRESS_PANEL_METRICS_REL}" \
  'export const BROWSER_BOTTOM_ADDRESS_INPUT_SELECTION_HANDLE_INSET: number = 16;' \
  "Bottom Chrome TextInput must reserve the native horizontal selection-handle inset."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'left: BROWSER_BOTTOM_ADDRESS_INPUT_SELECTION_HANDLE_INSET' \
  "Bottom Chrome TextInput must keep the leading selection handle inside its clipped viewport."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'right: BROWSER_BOTTOM_ADDRESS_INPUT_SELECTION_HANDLE_INSET' \
  "Bottom Chrome TextInput must keep the trailing selection handle inside its clipped viewport."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'floatingHeaderPresentationTranslateY: this.liveBottomChromePresentation.floatingSurfaceTranslateY' \
  "Bottom Address Panel must forward presentation-owned floating Header translation instead of overflowing the capsule rail."
check_file_contains_rule "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDetentBottomPanel.ets" \
  "AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDetentBottomPanel.ets" \
  'this\.floatingHostResizeTranslateY \+ this\.floatingHeaderPresentationTranslateY' \
  "Floating Header shadow and interaction surface must move with the Scroll-Compact host translation."
check_file_contains_rule "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL}" "${BOTTOM_CHROME_PRESENTATION_VIEW_MODEL_REL}" \
  "new BrowserBottomChromeTapIntent\('dispatch-header-action', 'bottomChromeRestore'\)" \
  "Compact center tap must restore the default toolbar instead of activating editing."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'outgoingDisplayText' \
  "stable Bottom Chrome renderer must retain an outgoing fixed-viewport display layer."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'incomingDisplayText' \
  "stable Bottom Chrome renderer must retain an incoming fixed-viewport display layer."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'displaySwapProgress' \
  "center display content must crossfade inside the shared Bottom Chrome animation transaction."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'resolveOutgoingDisplayLeft\(\)' \
  "outgoing display text must keep an explicit horizontal viewport-center anchor."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'resolveIncomingDisplayLeft\(\)' \
  "incoming display text must keep an explicit horizontal viewport-center anchor."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  '\.height\(BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT\)' \
  "display text must keep a fixed line box while the capsule height animates."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'resolveDisplayTextTop\(\)' \
  "display text must center its fixed line box without animating paragraph height."
check_file_contains_rule "${BOTTOM_CHROME_RENDERER}" "${BOTTOM_CHROME_RENDERER_REL}" \
  'this\.animatedFrame\.centerDisplayScale' \
  "display text must consume the presentation-owned compact visual scale."
check_file_not_contains_rule "${BOTTOM_ADDRESS_TRANSIENT_MESSAGE_VIEW_MODEL}" \
  "${BOTTOM_ADDRESS_TRANSIENT_MESSAGE_VIEW_MODEL_REL}" \
  'gesturePromptText' \
  "Return-Home prompt must stay in the typed center-content layer instead of replacing generic address display text."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'const ownsLivePresentation = this\.disconnectPresentationChannel\(\);' \
  "a disappearing keyed panel must consume the ownership result from disconnect."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'this\.releaseAddressFocusSessionIfOwned\(ownsLivePresentation\);' \
  "panel teardown must route shared input cleanup through its ownership-aware method."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'if \(!ownsLivePresentation\)' \
  "ownership-aware teardown must reject stale keyed panel instances before shared input cleanup."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'plan\.shouldEnsureHomeAddressFocusBackdrop = true' \
  "root bottom panel owner must decide positive Home address-focus presentation."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'plan\.shouldEnsureWebAddressFocusBackdrop = true' \
  "root bottom panel owner must decide positive Web address-focus presentation."
check_file_not_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  "@Watch\('syncRequestedAddressFocused'\)" \
  "mounted address focus must not regress to a frozen reactive Builder prop."
check_file_not_contains_rule "${SEARCH_SUGGESTIONS_PANEL}" "${SEARCH_SUGGESTIONS_PANEL_REL}" \
  "syncSuggestionContent|revealRunId|rowsRevealActive|revealTimer|scheduleBottomScrollIfNeeded|SUGGESTION_REVEAL_" \
  "suggestion content refresh must not restart row reveal motion or schedule renderer-owned scroll correction."
check_file_contains_rule "${SEARCH_SUGGESTIONS_PANEL}" "${SEARCH_SUGGESTIONS_PANEL_REL}" \
  'hitTestBehavior\(this\.blankAreaBackEnabled \? HitTestMode\.Block : HitTestMode\.None\)' \
  "blank Search space must remain an explicit hit target instead of relying on parent click bubbling."
if ! awk '
  /airaIconId: .browser\.tabs\.delete./ { in_delete_button = 1 }
  in_delete_button && /justifyContent\(this\.compactContent \? FlexAlign\.Start : FlexAlign\.End\)/ { found = 1 }
  in_delete_button && /\.onClick\(\(\) => \{/ { in_delete_button = 0 }
  END { exit found ? 0 : 1 }
' "${SEARCH_SUGGESTIONS_PANEL}"; then
  report_failure "${SEARCH_SUGGESTIONS_PANEL_REL} delete icon must stay close to the history icon in compact multi-column rows and retain single-column rail alignment without shrinking its touch width."
fi
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'suggestions: this\.homeSuggestionsVisible \? this\.homeSuggestions : \[\]' \
  "the reserved Search suggestion viewport must stay mounted while active content is empty."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'BrowserSearchListSurface\(\{' \
  "Bottom Address Panel must mount the one Search List Surface module."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'onIntent: \(intent: BrowserSearchListSurfaceIntent\)' \
  "Bottom Address Panel must consume one Search List Surface intent stream."
check_file_not_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'BrowserSearchSuggestionsPanel|ExternalAppSearchStrip|WEB_BOTTOM_FLOATING_SEARCH_CONTENT_VERTICAL_PADDING|WEB_BOTTOM_SEARCH_SCROLL_CLIP_SAFETY_GAP|regularCardHorizontalPadding' \
  "Bottom Address Panel must not know Search List Surface implementation details."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'export interface BrowserSearchListSurfacePresentation' \
  "Search List Surface must expose one typed presentation."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'onIntent: \(intent: BrowserSearchListSurfaceIntent\)' \
  "Search List Surface must expose one intent stream."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'BrowserSearchSuggestionsPanel\(\{' \
  "the suggestion list must stay subordinate to Search List Surface."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'ExternalAppSearchStrip\(\{' \
  "external-app targets must stay subordinate to Search List Surface."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'BrowserSearchListSurfaceLayoutViewModel' \
  "Search List Surface must consume one coherent layout implementation."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'regularRowContentFrameHeight: layout\.rowContentFrameHeight' \
  "regular visible-content framing must come from the Search List Surface layout projection."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'regularRowHeight: layout\.rowHeight' \
  "regular row height must come from the Search List Surface layout projection."
check_file_contains_rule "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" "${SEARCH_LIST_LAYOUT_VIEW_MODEL_REL}" \
  'BROWSER_SEARCH_LIST_MULTI_COLUMN_GAP: number = 24' \
  "multi-column Search records must retain a 24vp gutter that is visibly larger than their internal action gap."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'stripHeight: layout\.externalStripHeight' \
  "external strip height must come from the Search List Surface layout projection."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'itemWidth: layout\.externalItemWidth' \
  "external item cadence must come from the Search List Surface layout projection."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'columnGap: layout\.externalColumnGap' \
  "external item center pitch must come from the Search List Surface layout projection."
check_file_contains_rule "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" "${SEARCH_LIST_LAYOUT_VIEW_MODEL_REL}" \
  'scrollClipSafetyGap: number' \
  "Search List Surface layout must own the scroll clipping safety invariant."
check_file_contains_rule "${SEARCH_SUGGESTIONS_PANEL}" "${SEARCH_SUGGESTIONS_PANEL_REL}" \
  'regularRowContentFrameHeight: number' \
  "the subordinate suggestion implementation must consume the projected content frame."
check_file_contains_rule "${SEARCH_SUGGESTIONS_PANEL}" "${SEARCH_SUGGESTIONS_PANEL_REL}" \
  'Stack\(\{ alignContent: Alignment\.BottomStart \}\)' \
  "regular suggestion content must be bottom-placed independently from the Scroll clipping boundary."
check_file_contains_rule "${SEARCH_SUGGESTIONS_PANEL}" "${SEARCH_SUGGESTIONS_PANEL_REL}" \
  '\.height\(this\.resolveRowContentFrameHeight\(\)\)' \
  "title, history/trailing icon, and delete action must share one visible-content frame height."
check_file_not_contains_rule "${SEARCH_SUGGESTIONS_PANEL}" "${SEARCH_SUGGESTIONS_PANEL_REL}" \
  'SUGGESTION_MULTI_COLUMN_TITLE_SLOT_WIDTH|regularCardWidth|resolveCompactOpenButtonMaxWidth|resolveCompactOpenButtonWidth|resolveCompactTitleSlotWidth' \
  "compact suggestions must not restore the rejected fixed title slot or projected card-width calculations."
check_file_not_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'regularCardWidth' \
  "Search List Surface must let the grid size suggestion cards without projecting a separate card width."
check_file_not_contains_rule "${SEARCH_LIST_LAYOUT_VIEW_MODEL}" "${SEARCH_LIST_LAYOUT_VIEW_MODEL_REL}" \
  'regularCardWidth|resolveRegularCardWidth' \
  "Search layout state must not duplicate the grid's responsive card-width calculation."
check_file_contains_rule "${SEARCH_SUGGESTIONS_PANEL}" "${SEARCH_SUGGESTIONS_PANEL_REL}" \
  'Row\(\{ space: this\.compactContent \? 12 : 4 \}\)' \
  "compact rows must retain the accepted 12vp title-to-action separation without changing portrait spacing."
if ! awk '
  /private buildCompactSuggestionOpenButton\(\)/ { in_compact_open = 1 }
  in_compact_open && /\.layoutWeight\(1\)/ { found_weight = 1 }
  in_compact_open && /\.constraintSize\(\{ minWidth: 0 \}\)/ { found_min_width = 1 }
  in_compact_open && /private buildCompactTrailingActionRegion\(\)/ { in_compact_open = 0 }
  END { exit found_weight && found_min_width ? 0 : 1 }
' "${SEARCH_SUGGESTIONS_PANEL}"; then
  report_failure "${SEARCH_SUGGESTIONS_PANEL_REL} compact title/open target must flex into remaining row width with layoutWeight(1) and minWidth 0."
fi
if ! awk '
  /private buildCompactTrailingActionRegion\(\)/ { in_compact_actions = 1 }
  in_compact_actions && /Row\(\{ space: 4 \}\)/ { found_gap = 1 }
  in_compact_actions && /this\.buildTrailingIcon\(\)/ { found_trailing_icon = 1 }
  in_compact_actions && /this\.buildDeleteHistorySuggestionButton\(\)/ { found_delete = 1 }
  in_compact_actions && /SUGGESTION_TRAILING_ICON_SIZE/ { found_fixed_width = 1 }
  in_compact_actions && /SUGGESTION_DELETE_BUTTON_SIZE/ { found_delete_width = 1 }
  in_compact_actions && /private buildDeleteHistorySuggestionButton\(\)/ { in_compact_actions = 0 }
  END {
    exit found_gap && found_trailing_icon && found_delete && found_fixed_width && found_delete_width ? 0 : 1
  }
' "${SEARCH_SUGGESTIONS_PANEL}"; then
  report_failure "${SEARCH_SUGGESTIONS_PANEL_REL} compact rows must reserve one fixed trailing icon/delete region with a 4vp internal gap."
fi
check_file_contains_rule "${SEARCH_SUGGESTIONS_PANEL}" "${SEARCH_SUGGESTIONS_PANEL_REL}" \
  '\.alignItems\(VerticalAlign\.Bottom\)' \
  "the shared visible-content frame must stay bottom-aligned inside the 54vp touch row."
check_file_not_contains_rule "${SEARCH_SUGGESTIONS_PANEL}" "${SEARCH_SUGGESTIONS_PANEL_REL}" \
  'BrowserSearchListRowContentAlignment|regularRowContentAlignment|rowContentAlignment' \
  "the legacy split alignment path must not return."
check_search_list_geometry_invariants
check_file_not_contains_rule "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomPanelResponsiveViewModel.ets" \
  "AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomPanelResponsiveViewModel.ets" \
  'suggestionMaxHeight|WEB_BOTTOM_SUGGESTION_ROW_HEIGHT|suggestionColumns|suggestionColumnGap|suggestionRowGap' \
  "generic responsive layout must not retain Search-specific row or grid geometry."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL_METRICS}" "${BOTTOM_ADDRESS_PANEL_METRICS_REL}" \
  'export const BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP: number = 4;' \
  "floating top/header section spacing must have one shared geometry owner."
check_file_contains_rule "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDetentBottomPanel.ets" \
  "AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDetentBottomPanel.ets" \
  'BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP - this\.resolveFloatingTopSurfaceHeight' \
  "the Detent top/header geometry must consume the shared floating block gap."
check_file_not_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'WEB_BOTTOM_FLOATING_BLOCK_GAP' \
  "the address panel must not duplicate the shared floating block gap."
check_file_not_contains_rule "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDetentBottomPanel.ets" \
  "AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDetentBottomPanel.ets" \
  'BROWSER_DETENT_FLOATING_BLOCK_GAP' \
  "the Detent renderer must not duplicate the shared floating block gap."
check_file_not_contains_rule "${EXTERNAL_APP_SEARCH_STRIP}" "${EXTERNAL_APP_SEARCH_STRIP_REL}" \
  '\.translate\(' \
  "external-app rail alignment must not use transform-based Scroll content compensation."
check_file_not_contains_rule "${EXTERNAL_APP_SEARCH_STRIP}" "${EXTERNAL_APP_SEARCH_STRIP_REL}" \
  'EXTERNAL_APP_SEARCH_HORIZONTAL_PADDING' \
  "the external-app strip must not reintroduce a second horizontal rail inset."
check_file_contains_rule "${EXTERNAL_APP_SEARCH_STRIP}" "${EXTERNAL_APP_SEARCH_STRIP_REL}" \
  'if \(this\.isFullTargetPage\(page\)\)' \
  "external-app pages must branch between complete and incomplete page alignment."
check_file_contains_rule "${EXTERNAL_APP_SEARCH_STRIP}" "${EXTERNAL_APP_SEARCH_STRIP_REL}" \
  '\.justifyContent\(FlexAlign\.SpaceBetween\)' \
  "complete external-app pages must span the shared leading and trailing rails with equal distribution."
check_file_contains_rule "${EXTERNAL_APP_SEARCH_STRIP}" "${EXTERNAL_APP_SEARCH_STRIP_REL}" \
  '\.justifyContent\(FlexAlign\.Start\)' \
  "incomplete external-app pages must stay grouped from the shared leading rail."
check_file_not_contains_rule "${EXTERNAL_APP_SEARCH_STRIP}" "${EXTERNAL_APP_SEARCH_STRIP_REL}" \
  'targets\.length <= 4 \? FlexAlign\.Center' \
  "small external-target sets must not recenter away from the shared rail."
check_file_contains_rule "${SEARCH_LIST_SURFACE}" "${SEARCH_LIST_SURFACE_REL}" \
  'regularCardHorizontalPadding: 0' \
  "Search List Surface must keep transparent suggestion rows on its shared rail."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL}" "${BOTTOM_ADDRESS_PANEL_REL}" \
  'blankAreaBackEnabled: this\.isAddressInputPresentationActive\(\)' \
  "blank-space Back must only be interactive for an active Search input presentation."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'onSearchBlankAreaBack: \(\) => \{ this\.browserMainBackCoordinator\.onBackPress\(this\.browserMainBackHost\); \},' \
  "Search blank-space dismissal must forward directly to the real browser Back coordinator."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'HomeSearchOverlayViewModel|homeSearchOverlayViewModel' \
  "Home Search overlay policy must stay behind BrowserRootBottomPanelSessionCoordinator."
if [ -e "${OLD_SEARCH_OVERLAY_COORDINATOR}" ]; then
  report_failure "${OLD_SEARCH_OVERLAY_COORDINATOR_REL} must stay deleted; Search content projection belongs inside the canonical Suggestion owner."
fi
if [ -e "${OLD_HOME_TRANSIENT_UI_COORDINATOR}" ]; then
  report_failure "${OLD_HOME_TRANSIENT_UI_COORDINATOR_REL} must stay deleted; four boolean Search overlay records do not justify a peer owner."
fi
if [ -e "${OLD_SEARCH_SUGGESTION_SERVICE}" ]; then
  report_failure "${OLD_SEARCH_SUGGESTION_SERVICE_REL} must stay deleted; the unreachable legacy multi-source suggestion path must not return."
fi
if [ -e "${OLD_SEARCH_SOURCE_PREFERENCE_SERVICE}" ]; then
  report_failure "${OLD_SEARCH_SOURCE_PREFERENCE_SERVICE_REL} must stay deleted; history-only plus optional remote content must not regain the old multi-source filter path."
fi
if [ -e "${OLD_SEARCH_PIPELINE}" ]; then
  report_failure "${OLD_SEARCH_PIPELINE_REL} must stay deleted; the unreachable tabs/bookmarks/shortcuts/history mixed pipeline must not return."
fi
check_file_contains_rule "${SEARCH_SUGGESTION_COORDINATOR}" "${SEARCH_SUGGESTION_COORDINATOR_REL}" \
  'export interface BrowserSearchSuggestionSnapshot' \
  "Search suggestion content must expose one canonical presentation snapshot."
check_file_contains_rule "${SEARCH_SUGGESTION_COORDINATOR}" "${SEARCH_SUGGESTION_COORDINATOR_REL}" \
  'private snapshot: BrowserSearchSuggestionSnapshot' \
  "Search suggestion content state must stay canonical inside its owner."
check_file_contains_rule "${SEARCH_SUGGESTION_COORDINATOR}" "${SEARCH_SUGGESTION_COORDINATOR_REL}" \
  'tabSwitchCoordinator\.switchToTab' \
  "tab suggestions must enter the existing Tab Switch owner directly instead of round-tripping through BrowserShell."
check_file_not_contains_rule "${SEARCH_SUGGESTION_COORDINATOR}" "${SEARCH_SUGGESTION_COORDINATOR_REL}" \
  'BrowserSearchSuggestionHostProvider|BrowserSearchSuggestionProviderCallbacks|BrowserSearchOverlayCoordinator|HomeTransientUiStateCoordinator' \
  "the Search suggestion owner must not regain the deleted forwarding Provider or shallow projection peers."
check_file_contains_rule "${SEARCH_INVOCATION_SURFACE_ADAPTER}" "${SEARCH_INVOCATION_SURFACE_ADAPTER_REL}" \
  'tabHomeCoordinator: BrowserTabHomeCoordinator' \
  "the BrowserShell Search surface adapter must compose the fixed Home owner directly."
check_file_contains_rule "${SEARCH_INVOCATION_SURFACE_ADAPTER}" "${SEARCH_INVOCATION_SURFACE_ADAPTER_REL}" \
  'keyboardShortcutCoordinator: BrowserKeyboardShortcutCoordinator' \
  "the BrowserShell Search surface adapter must compose the fixed address-focus owner directly."
check_file_contains_rule "${SEARCH_INVOCATION_SURFACE_ADAPTER}" "${SEARCH_INVOCATION_SURFACE_ADAPTER_REL}" \
  'openSuggestion\(suggestion: SearchSuggestion\)' \
  "suggestion selection must stay readable through the real BrowserShell surface adapter."
check_file_contains_rule "${SEARCH_INVOCATION_SURFACE_ADAPTER}" "${SEARCH_INVOCATION_SURFACE_ADAPTER_REL}" \
  'dismissHomeSearch\(\)' \
  "explicit Search dismissal must stay readable through the real BrowserShell surface adapter."
check_file_contains_rule "${SEARCH_INVOCATION_SURFACE_ADAPTER}" "${SEARCH_INVOCATION_SURFACE_ADAPTER_REL}" \
  'releaseHomeSearchFocus\(\)' \
  "Search focus release must stay readable through the real BrowserShell surface adapter."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserSearchSuggestionSnapshot: BrowserSearchSuggestionSnapshot' \
  "BrowserShell must observe the canonical Search suggestion snapshot as explicit ArkUI state."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'homeSuggestions: this\.browserSearchSuggestionSnapshot\.searchSuggestions' \
  "the Bottom Address Panel must consume Search content from the explicit page snapshot."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State showSearchSuggestions|@State homeSearchOverlayVisible|homeSearchFocused: boolean|@State searchSuggestions|@State currentPageSuggestion|this\.currentPageSuggestion|applyHomeSearchOverlayState|applySearchSuggestionState|buildBrowserSearchSuggestionRuntimeSource|resetHomeSearchOverlayState|openRootBottomPanelSearchSuggestion|private exitHomeSearchFocus|private releaseHomeSearchFocus|BrowserSearchSuggestionHostProvider|BrowserSearchOverlayCoordinator|HomeTransientUiStateCoordinator' \
  "BrowserShell must not regain parallel Search content state, forwarding Providers, or ordinary Search surface flow methods."
check_file_contains_rule "${APP_URL_OPEN_COORDINATOR}" "${APP_URL_OPEN_COORDINATOR_REL}" \
  'searchSuggestionCoordinator\.reset\(\)' \
  "App URL Open must reset Search content through the canonical owner instead of a page callback."
check_file_contains_rule "${APP_URL_OPEN_COORDINATOR}" "${APP_URL_OPEN_COORDINATOR_REL}" \
  'tabScopedEventContextCoordinator\.buildCreateOptions\(' \
  "App URL Open must resolve create options through the fixed tab-scoped context owner."
check_file_contains_rule "${APP_URL_OPEN_COORDINATOR}" "${APP_URL_OPEN_COORDINATOR_REL}" \
  'addressDisplayCoordinator\.resolveCommittedDisplay\(' \
  "App URL Open must keep address formatting behind the fixed Address Display owner."
check_file_contains_rule "${APP_URL_OPEN_COORDINATOR}" "${APP_URL_OPEN_COORDINATOR_REL}" \
  'tabSwitchCoordinator\.synchronizeWebTabsAndPreviewAssets\(' \
  "App URL background creation must synchronize WebTabs and preview assets through the tab-list owner."
check_file_contains_rule "${FOREGROUND_TAB_CREATION_COORDINATOR}" \
  "${FOREGROUND_TAB_CREATION_COORDINATOR_REL}" \
  'privateProfileLifecycleCoordinator\.restorePreservedCookiesOnEnterIfNeeded\(' \
  "Foreground Tab Creation must own private-cookie restore sequencing through the fixed lifecycle owner."
check_file_contains_rule "${FOREGROUND_TAB_CREATION_COORDINATOR}" \
  "${FOREGROUND_TAB_CREATION_COORDINATOR_REL}" \
  'resolveTabSwitchCoordinator\(\)\.synchronizeWebTabsAndPreviewAssets\(' \
  "Foreground Tab Creation must synchronize WebTabs and preview assets through the tab-list owner."
check_file_contains_rule "${FOREGROUND_TAB_CREATION_COORDINATOR}" \
  "${FOREGROUND_TAB_CREATION_COORDINATOR_REL}" \
  'resolveTabSessionPersistenceCoordinator\(\)\.persist\(' \
  "Foreground Tab Creation must persist through the fixed session-persistence owner."
check_file_contains_rule "${FOREGROUND_TAB_CREATION_COORDINATOR}" \
  "${FOREGROUND_TAB_CREATION_COORDINATOR_REL}" \
  'resolveTabsOverviewSessionCoordinator\(\)\.handle\(' \
  "Foreground Tab Creation must enter the fixed Tabs Overview owner for Home creation and overview close."
check_file_contains_rule "${FOREGROUND_TAB_CREATION_COORDINATOR}" \
  "${FOREGROUND_TAB_CREATION_COORDINATOR_REL}" \
  'resolveBrowserNewWindowTestTitle\(' \
  "Foreground Tab Creation must consume internal-debug title policy from its existing source owner."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private resolveInternalDebugPageTitle|private captureCurrentTabPreviewBeforeCreatingForegroundTab|prepareForegroundTabCreation:|applyForegroundTabCreation:|applyBackgroundTabTransition:|applyLaunchContextTabs:' \
  "BrowserShellPage must not regain tab-creation title policy, preview wrappers, or foreground/background application sequencing."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'applyTabCreationState: \(application: BrowserTabCreationStateApplication\)' \
  "BrowserShellPage must keep tab creation as one typed atomic state-publication callback."
foreground_tab_creation_host_callback_count="$(awk '
  /export interface BrowserForegroundTabCreationHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${FOREGROUND_TAB_CREATION_COORDINATOR}")"
if [ "${foreground_tab_creation_host_callback_count}" -gt 5 ]; then
  report_failure "${FOREGROUND_TAB_CREATION_COORDINATOR_REL} must keep Foreground Creation Host at no more than 5 facts/state/platform/diagnostic callbacks; found ${foreground_tab_creation_host_callback_count}."
fi
app_url_open_host_callback_count="$(awk '
  /export interface BrowserAppUrlOpenHost extends BrowserForegroundTabCreationHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${APP_URL_OPEN_COORDINATOR}")"
if [ "${app_url_open_host_callback_count}" -gt 4 ]; then
  report_failure "${APP_URL_OPEN_COORDINATOR_REL} must add no more than 4 App URL facts/state/message callbacks over the shared Foreground Host; found ${app_url_open_host_callback_count}."
fi
tab_creation_state_field_count="$(awk '
  /export interface BrowserTabCreationStateApplication \{/ { in_state = 1; next }
  in_state && /^}/ { print count + 0; exit }
  in_state && /\?:/ { count += 1 }
' "${FOREGROUND_TAB_CREATION_COORDINATOR}")"
if [ "${tab_creation_state_field_count}" -gt 4 ]; then
  report_failure "${FOREGROUND_TAB_CREATION_COORDINATOR_REL} must keep typed tab-creation publication at no more than 4 existing shell fields; found ${tab_creation_state_field_count}."
fi
check_file_contains_rule "${STARTUP_TAB_RESTORE_COORDINATOR}" \
  "${STARTUP_TAB_RESTORE_COORDINATOR_REL}" \
  'tabSwitchCoordinator\.synchronizeActiveTab\(' \
  "Startup Tab Restore must synchronize the active runtime through the fixed Tab Switch owner."
check_file_contains_rule "${STARTUP_TAB_RESTORE_COORDINATOR}" \
  "${STARTUP_TAB_RESTORE_COORDINATOR_REL}" \
  'backgroundSessionSyncCoordinator\.sync\(' \
  "Startup Tab Restore must apply Home materialization through the fixed Background Session owner."
check_file_contains_rule "${STARTUP_TAB_RESTORE_COORDINATOR}" \
  "${STARTUP_TAB_RESTORE_COORDINATOR_REL}" \
  'tabPreviewAssetBoundaryCoordinator\.hydratePersistedPreviewMetadata\(' \
  "Startup Tab Restore must enter the fixed Preview Asset Boundary owner directly."
check_file_contains_rule "${STARTUP_TAB_RESTORE_COORDINATOR}" \
  "${STARTUP_TAB_RESTORE_COORDINATOR_REL}" \
  'nativeNavigationConsumeCoordinator\.consume\(\)' \
  "Startup Tab Restore must enter the fixed Native Navigation owner directly."
check_file_contains_rule "${STARTUP_TAB_RESTORE_COORDINATOR}" \
  "${STARTUP_TAB_RESTORE_COORDINATOR_REL}" \
  'resolveWindowContextCoordinator\(\)' \
  "Startup Tab Restore must enter the fixed Window Context owner through its late resolver."
check_file_not_contains_rule "${STARTUP_TAB_RESTORE_COORDINATOR}" \
  "${STARTUP_TAB_RESTORE_COORDINATOR_REL}" \
  'BrowserStartupTabRestoreApplicationHost|applyTabsSnapshot:|completeRestore:|applyOpenHomeSurface:|syncActiveTabToView:|applyRestoreTrace:|applyRuntimeDegradedMessage:|consumePendingWindowLaunch:|schedulePendingWindowLaunchPolling:|restorePersistedTabPreviews: \(\) =>|consumePendingNativeNavigation: \(\) =>' \
  "Startup Tab Restore must not regain the old application Host or fixed-dependency forwarding callbacks."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserStartupTabRestoreApplicationHost|applyOpenHomeSurface:|syncActiveTabToView: \(materializationPolicy:|applyRestoreTrace:|applyRuntimeDegradedMessage:|consumePendingWindowLaunch:|schedulePendingWindowLaunchPolling:|private consumePendingNativeNavigation\(' \
  "BrowserShellPage must not regain Startup Restore application sequencing or fixed owner forwarding."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'applyState: \(application: BrowserStartupTabRestoreStateApplication\)' \
  "BrowserShellPage must publish Startup Restore state through one typed callback."
startup_tab_restore_host_callback_count="$(awk '
  /export interface BrowserStartupTabRestoreHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${STARTUP_TAB_RESTORE_COORDINATOR}")"
if [ "${startup_tab_restore_host_callback_count}" -gt 6 ]; then
  report_failure "${STARTUP_TAB_RESTORE_COORDINATOR_REL} must keep Startup Restore Host at no more than 6 facts/state/shell-platform/diagnostic callbacks; found ${startup_tab_restore_host_callback_count}."
fi
startup_tab_restore_state_field_count="$(awk '
  /export interface BrowserStartupTabRestoreStateApplication \{/ { in_state = 1; next }
  in_state && /^}/ { print count + 0; exit }
  in_state && /\?:/ { count += 1 }
' "${STARTUP_TAB_RESTORE_COORDINATOR}")"
if [ "${startup_tab_restore_state_field_count}" -gt 6 ]; then
  report_failure "${STARTUP_TAB_RESTORE_COORDINATOR_REL} must keep typed Startup Restore publication at no more than 6 semantic fields; found ${startup_tab_restore_state_field_count}."
fi
check_file_contains_rule "${NATIVE_NAVIGATION_CONSUME_COORDINATOR}" \
  "${NATIVE_NAVIGATION_CONSUME_COORDINATOR_REL}" \
  'private readonly host: BrowserNativeNavigationConsumeHost;' \
  "Native Navigation Consume must retain its fixed facts/effect Host instead of accepting per-flow page wiring."
check_file_contains_rule "${NATIVE_NAVIGATION_CONSUME_COORDINATOR}" \
  "${NATIVE_NAVIGATION_CONSUME_COORDINATOR_REL}" \
  'consume\(\): void' \
  "Native Navigation Consume must expose one argument-free owner entry."
if ! awk '
  /export interface BrowserSearchSuggestionShell/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /: \(/ { callbacks += 1 }
  END { exit callbacks <= 4 ? 0 : 1 }
' "${SEARCH_SUGGESTION_COORDINATOR}"; then
  report_failure "${SEARCH_SUGGESTION_COORDINATOR_REL} Search shell must stay at four callbacks or fewer."
fi
if ! awk '
  /export interface BrowserShellSearchInvocationHost/ { in_host = 1; next }
  in_host && /^}/ { in_host = 0 }
  in_host && /: \(/ { callbacks += 1 }
  END { exit callbacks <= 5 ? 0 : 1 }
' "${SEARCH_INVOCATION_SURFACE_ADAPTER}"; then
  report_failure "${SEARCH_INVOCATION_SURFACE_ADAPTER_REL} surface Host must stay at five callbacks or fewer."
fi
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'shouldMountHomeSearchDismissLayer' \
  "the Root Bottom-Panel Session must own Home Search dismiss-layer eligibility."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'buildHomeSearchReleasePlan' \
  "the Root Bottom-Panel Session must own Home Search release planning."
check_file_not_contains_rule "${BOTTOM_PANEL_HOST}" "${BOTTOM_PANEL_HOST_REL}" \
  'onHostAreaChange|measuredHostWidth|measuredHostHeight' \
  "bottom panel Host adapter must not feed retained ArkUI measurements back into responsive geometry."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'kind: ShortcutKind' \
  "custom-home shortcut projection must distinguish Web and System records with one kind field."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'openShortcutPicker: function' \
  "custom-home bridge must expose the native shortcut picker through one command method."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'GeneratedAiraIconCatalog\.resolveFontGlyph' \
  "custom-home System shortcuts must resolve their glyphs from the Canonical Aira Icon Catalog."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'getRawFileContentSync\(AIRA_ICON_FONT_RAWFILE_PATH\)' \
  "custom-home documents must reuse the one packaged Operational Icon font rather than a parallel image set."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'renderShortcutIcon: function' \
  "custom-home pages must receive one Bridge-owned font/image shortcut renderer."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'prepareIconFont: function' \
  "custom-home pages must retain one explicit opt-in font prewarm method."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'getThemePalette: function' \
  "custom-home pages must expose one focused read-only theme palette API."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'palette: normalizeThemePalette' \
  "custom-home theme snapshots and events must carry the normalized palette projection."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'themePaletteProjectionService\.build' \
  "custom-home runtime must delegate public theme projection to its subordinate service."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'app/bootstrap/BrowserAppRuntime' \
  "custom-home runtime must receive a narrow theme snapshot instead of importing app-bootstrap global preferences."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'updateThemePreferences\(preferences: CustomHomepageThemePreferenceSnapshot\)' \
  "custom-home runtime must expose one narrow theme-preference snapshot update boundary."
check_file_contains_rule "${BROWSER_TAB_HOME_COORDINATOR}" "${BROWSER_TAB_HOME_COORDINATOR_REL}" \
  'customHomepageRuntimeCoordinator\.updateThemePreferences\(' \
  "Browser Tab Home owner must project current theme preferences into the custom-home runtime."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'syncPrivacyBoundaryBridge\(documentGeneration\?: number\)' \
  "custom-home runtime must expose one explicit privacy-boundary synchronization entry point."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  "bridgeCoordinator\.sync\('theme', snapshot\)" \
  "custom-home privacy synchronization must publish the recomputed theme from the same snapshot."
check_file_contains_rule "${BROWSER_TAB_HOME_COORDINATOR}" "${BROWSER_TAB_HOME_COORDINATOR_REL}" \
  'customHomepageRuntimeCoordinator\.syncPrivacyBoundaryBridge\(\)' \
  "Browser Tab Home boundary changes must publish privacy and its recomputed theme atomically."
check_file_contains_rule "${CUSTOM_HOMEPAGE_THEME_PALETTE_PROJECTION_SERVICE}" \
  "${CUSTOM_HOMEPAGE_THEME_PALETTE_PROJECTION_SERVICE_REL}" \
  'themePaletteService\.resolveTokens' \
  "custom-home palette colors must come from the shared Theme Palette authority."
check_file_contains_rule "${CUSTOM_HOMEPAGE_THEME_PALETTE_PROJECTION_SERVICE}" \
  "${CUSTOM_HOMEPAGE_THEME_PALETTE_PROJECTION_SERVICE_REL}" \
  'return `rgba\(\$\{red\},\$\{green\},\$\{blue\},\$\{normalizedAlpha\}\)`' \
  "custom-home Web colors must convert ArkUI alpha-first eight-digit tokens into CSS rgba values."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'buildCustomHomepageThemePalette|resolveCustomHomepageThemePalette' \
  "BrowserShellPage must not own custom-home theme palette projection logic."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  '@font-face' \
  "custom-home documents must register the packaged TTF through CSS font loading supported by Web content."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'data:font/ttf;base64' \
  "custom-home Web font registration must use the one injected packaged TTF payload."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  "request\('iconFont', ''\)" \
  "custom-home Web documents must request the packaged Operational Icon font lazily through the owned native Bridge."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR}" "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR_REL}" \
  "action === 'iconfont'" \
  "custom-home native Bridge must own the lazy Operational Icon font payload request."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'buildDocumentStartScript\(state, this\.resolveOperationalIconFontBase64\(\)\)' \
  "custom-home document-start scripts must stay lightweight instead of embedding the complete font payload."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  '^[[:space:]]*window\.__airaHomeEnsureIconFont\(\);[[:space:]]*$' \
  "custom-home Bridge installation must not eagerly transfer the Operational Icon font before a homepage requests it."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'resolveSystemShortcutIconMediaName|systemShortcutIconCache|new FontFace' \
  "custom-home System shortcuts must not restore SVG lookup or the failed ArkWeb FontFace constructor path."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  "filter\(\(shortcut: ShortcutRecord\) => shortcut\.kind !== 'system'\)" \
  "custom-home shortcut projection must not hide System shortcuts from third-party homepages."
check_file_contains_rule "${CUSTOM_HOMEPAGE_SYSTEM_ENTRY_CATALOG}" "${CUSTOM_HOMEPAGE_SYSTEM_ENTRY_CATALOG_REL}" \
  'resolveCustomHomepageSystemEntry\(' \
  "custom-home System entry names and aliases must stay in one catalog."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE}" "${CUSTOM_HOMEPAGE_BRIDGE_SERVICE_REL}" \
  'normalizeSystemEntry\(' \
  "custom-home bridge serialization must not regain System entry alias policy."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR}" "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR_REL}" \
  'resolveCustomHomepageSystemEntry\(rawEntry\)' \
  "custom-home native routing must consume the shared System entry catalog."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR}" "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR_REL}" \
  'handleRequest\(input: CustomHomepageBridgeRequestInput\)' \
  "custom-home public request classification must stay in the bridge coordinator rather than BrowserShellPage."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR}" "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR_REL}" \
  'isHomeSystemShortcut\(shortcut\).*isAllowedSystemShortcutAction' \
  "custom-home bridge owner must enforce System shortcut open/remove-only policy."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'bridgeCoordinator\.handleRequest\(' \
  "the custom-home Runtime owner must delegate request classification to the Bridge owner."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  "routeCoordinator\.openHomeSystemEntry\('tabs'\)" \
  "Custom Homepage Runtime must own fixed Tabs routing."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'addressSubmissionCoordinator\.submitAddress\(' \
  "Custom Homepage Runtime must own fixed address submission."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'appUrlOpenCoordinator\.openCurrentAppUi\(' \
  "Custom Homepage Runtime must own fixed current-tab URL opening."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'shortcutStateCoordinator\.openSelectionSession\(' \
  "Custom Homepage Runtime must enter the fixed Home Shortcut owner directly."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'CustomHomepageOpenTabsOverviewEffect|CustomHomepageOpenUrlShellEffect|CustomHomepageSubmitSearchEffect|CustomHomepageOpenShortcutPickerEffect' \
  "Custom Homepage Runtime must not re-export fixed owner flows as BrowserShell effects."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State customHomepageRuntimeState: CustomHomepageRuntimeShellState' \
  "BrowserShellPage must observe one explicit custom-home Runtime snapshot for ArkUI mounting and visibility."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "customHomepageBridgeCoordinator|customHomepageLoadTimeoutTimer|CustomHomepageRuntimeTransition|applyCustomHomepageRuntimeTransition|handleCustomHomepageNavigationRequest|handleHomeShortcutActionFromCustomHomepage|normalizedAction ===|normalizedAction ==|effect\.url, '正在从主页打开链接'|effect\.rawInput, effect\.searchEngineId|homeShortcutStateCoordinator\.openSelectionSession\(\)" \
  "BrowserShellPage must not regain custom-home Runtime ordering, Bridge ownership, request classification, or shortcut policy."
check_file_contains_rule "${APP_URL_OPEN_COORDINATOR}" "${APP_URL_OPEN_COORDINATOR_REL}" \
  'openCurrentAppUi\(' \
  "App URL Open must own reusable current-tab App-UI request construction."
check_file_contains_rule "${WEB_CAPABILITY_PROMPT_COORDINATOR}" "${WEB_CAPABILITY_PROMPT_COORDINATOR_REL}" \
  'new WebPermissionCoordinator\(' \
  "Web capability prompt application owner must keep Web Permission as a subordinate policy/session engine."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserWebCapabilityPromptApplicationSink: BrowserWebCapabilityPromptApplicationSink' \
  "BrowserShellPage must expose one narrow Web capability prompt shell/platform sink."
check_file_contains_rule "${WEB_CAPABILITY_PROMPT_COORDINATOR}" "${WEB_CAPABILITY_PROMPT_COORDINATOR_REL}" \
  'resolveEffectHandler\(\)\.apply' \
  "Web capability prompt owner must apply emitted effects through one subordinate handler."
check_file_contains_rule "${WEB_CAPABILITY_PROMPT_EFFECT_APPLICATION}" \
  "${WEB_CAPABILITY_PROMPT_EFFECT_APPLICATION_REL}" \
  'presentAlertDialog\(effect\)' \
  "Web capability effect application must delegate self-contained AlertDialogs to the subordinate presenter."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserNativeAlertDialogPresenter\.confirm\(' \
  "BrowserShellPage must delegate native confirmation mechanics to the shared presenter."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserNativeAlertDialogPresenter\.inform\(' \
  "BrowserShellPage must delegate native information-dialog mechanics to the shared presenter."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'AlertDialog\.show|BrowserConfirmationAlertPresenter|private showDialog\(' \
  "BrowserShellPage must not regain direct native AlertDialog execution or the old generic dialog helper."
check_file_contains_rule "${BROWSER_NATIVE_ALERT_DIALOG_PRESENTER}" \
  "${BROWSER_NATIVE_ALERT_DIALOG_PRESENTER_REL}" \
  'AlertDialog\.show' \
  "browser native alert presenter must remain the generic AlertDialog execution adapter."
check_file_contains_rule "${BROWSER_NATIVE_ALERT_DIALOG_PRESENTER}" \
  "${BROWSER_NATIVE_ALERT_DIALOG_PRESENTER_REL}" \
  "ohos_id_color_warning|ohos_id_color_alert" \
  "browser native alert presenter must retain warning and alert confirmation tones."
check_file_not_contains_rule "${BROWSER_NATIVE_ALERT_DIALOG_PRESENTER}" \
  "${BROWSER_NATIVE_ALERT_DIALOG_PRESENTER_REL}" \
  'Coordinator|Service|Repository|Host|Port' \
  "browser native alert presenter must stay policy-free and owner-agnostic."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "private applyBrowserWebCapabilityPromptEffect\(|dialog\.action === 'open_javascript_confirm'|dialog\.action === 'open_javascript_alert'|dialog\.action === 'open_ssl_warning'" \
  "BrowserShellPage must not regain Web capability effect interpretation or AlertDialog policy."
web_capability_effect_shell_callback_count="$(awk '
  /export interface BrowserWebCapabilityPromptEffectShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${WEB_CAPABILITY_PROMPT_EFFECT_APPLICATION}")"
if [ "${web_capability_effect_shell_callback_count}" -ne 7 ]; then
  report_failure "${WEB_CAPABILITY_PROMPT_EFFECT_APPLICATION_REL} Shell must keep exactly seven UI/platform callbacks; found ${web_capability_effect_shell_callback_count}."
fi
check_file_contains_rule "${WEB_CAPABILITY_ALERT_DIALOG_PRESENTER}" \
  "${WEB_CAPABILITY_ALERT_DIALOG_PRESENTER_REL}" \
  "open_javascript_confirm" \
  "Web capability AlertDialog presenter must retain JavaScript confirm presentation."
check_file_contains_rule "${WEB_CAPABILITY_ALERT_DIALOG_PRESENTER}" \
  "${WEB_CAPABILITY_ALERT_DIALOG_PRESENTER_REL}" \
  "open_javascript_alert" \
  "Web capability AlertDialog presenter must retain JavaScript alert presentation."
check_file_contains_rule "${WEB_CAPABILITY_ALERT_DIALOG_PRESENTER}" \
  "${WEB_CAPABILITY_ALERT_DIALOG_PRESENTER_REL}" \
  "open_ssl_warning" \
  "Web capability AlertDialog presenter must retain SSL-warning presentation."
check_file_contains_rule "${WEB_CAPABILITY_ALERT_DIALOG_PRESENTER}" \
  "${WEB_CAPABILITY_ALERT_DIALOG_PRESENTER_REL}" \
  "open_system_permission_setting" \
  "Web capability AlertDialog presenter must retain system-permission settings presentation."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserWebDialogApplicationCoordinator|browserWebDialogQueue|WebPermissionCoordinatorHostAdapter|browserWebCapabilityPromptApplicationHost|webPermissionCoordinatorHost' \
  "BrowserShellPage must not regain peer JS-dialog application owners or wide capability/permission Host wiring."
check_file_not_contains_rule "${WEB_PERMISSION_COORDINATOR}" "${WEB_PERMISSION_COORDINATOR_REL}" \
  'HostAdapter|WebPermissionCoordinatorHost' \
  "Web Permission must not regain the single-caller 20-callback HostAdapter."
check_file_not_contains_rule "${WEB_CAPABILITY_PROMPT_COORDINATOR}" "${WEB_CAPABILITY_PROMPT_COORDINATOR_REL}" \
  'BrowserPolicyDecisionService|recordPolicyDecision|emitPolicyDecision|emitRuntimeEvent|emitDiagnostic|restore_trace' \
  "Web capability prompt ownership must not rebuild removed policy/runtime diagnostic effects."
check_file_not_contains_rule "${WEB_CAPABILITY_PROMPT_EFFECT_APPLICATION}" \
  "${WEB_CAPABILITY_PROMPT_EFFECT_APPLICATION_REL}" \
  'recordPolicyDecision|recordRuntimeEvent|appendRestoreTraceBreadcrumb|policy_decision|restore_trace|runtime_event' \
  "Web capability effect application must expose only real UI/platform effects."
check_file_not_contains_rule "${WEB_PERMISSION_COORDINATOR}" "${WEB_PERMISSION_COORDINATOR_REL}" \
  'BrowserPolicyDecisionService|recordPolicyDecision|recordRuntimeEvent|appendRestoreTraceBreadcrumb|restore_trace' \
  "Web Permission must keep policy diagnostics deleted while retaining grant/deny and protection behavior."
if [ -e "${OLD_POLICY_DECISION_SERVICE}" ]; then
  report_failure "${OLD_POLICY_DECISION_SERVICE_REL} must stay deleted; its records had no application consumer."
fi
check_file_not_contains_rule "${TAB_SCOPED_EVENT_CONTEXT_COORDINATOR}" \
  "${TAB_SCOPED_EVENT_CONTEXT_COORDINATOR_REL}" \
  'BrowserPolicyDecisionBoundaryContext|buildPolicyDecisionBoundaryContext|projectPolicyDecision' \
  "Tab-scoped event context must not restore the deleted policy-decision projection seam."
if [ -e "${OLD_WEB_DIALOG_APPLICATION}" ]; then
  report_failure "${OLD_WEB_DIALOG_APPLICATION_REL} must stay deleted; JS dialog result/session ordering belongs to the Web capability prompt owner."
fi
check_file_contains_rule "${TAB_SWITCH_COORDINATOR}" "${TAB_SWITCH_COORDINATOR_REL}" \
  'synchronizeAfterTabChange\(' \
  "Tab Switch must keep active-shell publication and runtime activation behind one narrative owner."
check_file_contains_rule "${ACTIVE_RUNTIME_SYNC_COORDINATOR}" "${ACTIVE_RUNTIME_SYNC_COORDINATOR_REL}" \
  'private scheduleAttachRetry\(' \
  "Active Runtime Sync must internally own controller-attach retry ordering."
check_file_not_contains_rule "${ACTIVE_RUNTIME_SYNC_COORDINATOR}" "${ACTIVE_RUNTIME_SYNC_COORDINATOR_REL}" \
  'diagnosticLine|recordRuntimeEvent:|sink\.recordPageCacheDecision' \
  "Active Runtime Sync must keep attach/retry behavior without page-forwarded diagnostics or page-cache diagnostic sinks."
check_file_contains_rule "${PROXY_AUTH_REFRESH_COORDINATOR}" "${PROXY_AUTH_REFRESH_COORDINATOR_REL}" \
  "releaseAllHostedRuntimes\('proxy_settings_changed'\)" \
  "Proxy Auth Refresh must retain full Hosted runtime release before pending controller replacement."
check_file_not_contains_rule "${PROXY_AUTH_REFRESH_COORDINATOR}" "${PROXY_AUTH_REFRESH_COORDINATOR_REL}" \
  'BrowserProxyRuntimeRefreshResult|BrowserProxyRuntimeRefreshResultKind|buildResult\(|generation:' \
  "Proxy Auth Refresh must apply refresh behavior directly without diagnostics-only result DTOs."
check_file_not_contains_rule "${PROXY_RUNTIME_REFRESH_COORDINATOR}" "${PROXY_RUNTIME_REFRESH_COORDINATOR_REL}" \
  'getPendingGeneration|BrowserProxyRuntimeRefreshListener = \(generation: number\)|notifyListeners\(generation' \
  "Proxy Runtime Refresh must keep internal monotonic generations without exposing diagnostic generation payloads."
check_file_not_contains_rule "${WEB_LOAD_RUNTIME_COORDINATOR}" "${WEB_LOAD_RUNTIME_COORDINATOR_REL}" \
  'recordDeferredDataLoadFailure|stringifyError\?:' \
  "Web Load Runtime must keep deferred document loading without empty-recorder error bindings."
web_load_runtime_shell_callback_count="$(awk '
  /export interface BrowserWebLoadRuntimeHostBindings \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${WEB_LOAD_RUNTIME_COORDINATOR}")"
if [ "${web_load_runtime_shell_callback_count}" -gt 5 ]; then
  report_failure "${WEB_LOAD_RUNTIME_COORDINATOR_REL} must keep Web Load shell wiring at no more than 5 facts/state/data/platform callbacks; found ${web_load_runtime_shell_callback_count}."
fi
check_file_not_contains_rule "${WEB_LOAD_RUNTIME_COORDINATOR}" "${WEB_LOAD_RUNTIME_COORDINATOR_REL}" \
  '^  (resolveRuntimeLoadUrl|syncEventContext|applyOfflineFastFailureIfNeeded|prepareUserAgentForNavigation|applyUserAgentToController|isTabStillTargetingUrl):' \
  "Web Load Runtime shell must not regain fixed URL/Event/Lifecycle/Offline/UA/Tab forwarding callbacks."
check_file_contains_rule "${WEB_LOAD_RUNTIME_COORDINATOR}" "${WEB_LOAD_RUNTIME_COORDINATOR_REL}" \
  'new BrowserRuntimeNavigationRecoveryCoordinator\(' \
  "Web Load Runtime must own Runtime Navigation Recovery as a subordinate implementation."
check_file_contains_rule "${WEB_LOAD_RUNTIME_COORDINATOR}" "${WEB_LOAD_RUNTIME_COORDINATOR_REL}" \
  'resolveDocumentViewerService\(\)\.buildLoadingPayload\(' \
  "Web Load Runtime must own Document Viewer payload resolution."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserOpenResolvedUrlHost|new BrowserRuntimeNavigationRecoveryCoordinator\(|browserRuntimeNavigationRecoveryCoordinator|private upsertActiveTab\(|resolveDataPayload: \(url:|resolveDeferredDataPayload:|forcedCompatibilityUserAgentHosts' \
  "BrowserShellPage must not rebuild Open Resolved, Runtime Recovery, payload policy, or single-use Tab mutation plumbing."
check_file_not_contains_rule "${APP_URL_OPEN_COORDINATOR}" "${APP_URL_OPEN_COORDINATOR_REL}" \
  'openResolvedUrlHost' \
  "App URL Open must enter resolved-URL execution through the Web Load owner interface only."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" \
  "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'runtimeNavigationRecoveryCoordinator:' \
  "Web Page Lifecycle must consume Runtime Recovery through the Web Load owner interface."
check_file_not_contains_rule "${WEB_PAGE_PRESENTATION_EVENT_COORDINATOR}" \
  "${WEB_PAGE_PRESENTATION_EVENT_COORDINATOR_REL}" \
  'runtimeNavigationRecoveryCoordinator:' \
  "Web Page Presentation Event must consume Compatibility Recovery through the Web Load owner interface."
check_file_not_contains_rule "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR}" \
  "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL}" \
  'BrowserWebLoadRuntimeCoordinator' \
  "Runtime Navigation Recovery must depend on the Web Load semantic interface without a concrete owner cycle."
offline_fast_failure_host_callback_count="$(awk '
  /export interface BrowserOfflineFastFailureCoordinatorHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${OFFLINE_FAST_FAILURE_COORDINATOR}")"
if [ "${offline_fast_failure_host_callback_count}" -ne 1 ]; then
  report_failure "${OFFLINE_FAST_FAILURE_COORDINATOR_REL} Host must keep exactly one current-facts callback; found ${offline_fast_failure_host_callback_count}."
fi
check_file_not_contains_rule "${OFFLINE_FAST_FAILURE_COORDINATOR}" "${OFFLINE_FAST_FAILURE_COORDINATOR_REL}" \
  '^  (resolveActiveTab|resolvePendingWebUrl|resolveTab|isHomeSurfaceVisible|isLoading|isActiveWebTab|shouldShowLoadFailureSurface|applyActiveFailedUrlState|applyTabRuntimePatch|markLoadFailure|setActivePageLoadCompleted|applyShellPageErrorState|stopLoading|loadErrorDocument):' \
  "Offline Fast Failure Host must not regain fixed Tab/Lifecycle/Error Document callback plumbing."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'document_viewer_load_failed|proxy runtime refresh consumed generation|proxy runtime refresh skipped web rebuild|proxy runtime refresh failed to replace controller|proxy runtime refresh scheduled reload' \
  "BrowserShellPage must not restore deferred document or Proxy refresh diagnostic interpretation."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserTabSwitchApplicationSink: BrowserTabSwitchApplicationSink' \
  "BrowserShellPage must expose one narrow Tab Switch facts/effect sink."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserActiveRuntimeSyncSink: BrowserActiveRuntimeSyncSink' \
  "BrowserShellPage must expose one narrow Active Runtime facts/effect sink."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserTabSwitchHost|BrowserActiveRuntimeSyncHost|BrowserTabSwitchHostAttachRetry|browserTabSwitchCoordinatorHost|browserActiveRuntimeHost|browserActiveRuntimeSyncHost|private syncActiveTabToView|private syncSwitchedTabToView|private syncTabToView|private resumeActiveTabOnPageForeground|private scheduleForegroundResumeFollowup' \
  "BrowserShellPage must not regain Tab Switch/Active Runtime flow ordering or the old wide Host wiring."
check_file_contains_rule "${BACKGROUND_OPEN_PROMPT_COORDINATOR}" "${BACKGROUND_OPEN_PROMPT_COORDINATOR_REL}" \
  'private snapshot: BrowserBackgroundOpenPromptState' \
  "Background Open Prompt must keep its canonical application snapshot inside the single owner."
check_file_contains_rule "${BACKGROUND_OPEN_PROMPT_COORDINATOR}" "${BACKGROUND_OPEN_PROMPT_COORDINATOR_REL}" \
  'private iconResolveTokens: Record<string, number>' \
  "Background Open Prompt icon-generation state must stay inside the application owner."
check_file_contains_rule "${BACKGROUND_OPEN_PROMPT_COORDINATOR}" "${BACKGROUND_OPEN_PROMPT_COORDINATOR_REL}" \
  'showForTab\(tab: BrowserTabState\)' \
  "Background tab creation must enter one semantic Background Open Prompt owner entry."
check_file_contains_rule "${BACKGROUND_OPEN_PROMPT_COORDINATOR}" "${BACKGROUND_OPEN_PROMPT_COORDINATOR_REL}" \
  'consumeOpenRequest\(tabId: string\)' \
  "Background prompt open actions must consume canonical owner state before tab switching."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State backgroundOpenPromptState: BrowserBackgroundOpenPromptState' \
  "BrowserShellPage must keep one explicit reactive Background Open Prompt snapshot for ArkUI mounting and visibility."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserBackgroundOpenPromptShell: BrowserBackgroundOpenPromptShell' \
  "BrowserShellPage must expose only the Background Prompt snapshot/animation/Toast shell."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'backgroundOpenPromptIconResolveTokens|private showBackgroundOpenPromptForTab|private resolveBackgroundOpenPromptIcon|private updateBackgroundOpenPrompt|private hideBackgroundOpenPrompt|private hideBackgroundOpenPromptForTab|private async openBackgroundPromptTab|BrowserFaviconApplyHostAdapter|getBackgroundOpenPromptState|applyBackgroundOpenPromptState' \
  "BrowserShellPage must not regain Background Prompt canonical state mutation, icon generations, open ordering, or favicon/lifecycle callback wiring."
check_file_not_contains_rule "${TOP_FLOATING_PROMPT_COORDINATOR}" "${TOP_FLOATING_PROMPT_COORDINATOR_REL}" \
  'new BrowserBackgroundOpenPromptCoordinator' \
  "Top Floating Prompt must project Background Prompt state without creating a second application owner."
check_file_contains_rule "${TAB_SWITCH_COORDINATOR}" "${TAB_SWITCH_COORDINATOR_REL}" \
  'openBackgroundPromptTab\(tabId: string\)' \
  "Tab Switch must own the Background Prompt open sequence."
check_file_contains_rule "${TAB_SWITCH_COORDINATOR}" "${TAB_SWITCH_COORDINATOR_REL}" \
  'captureOpenerPreviewBeforeBackgroundPromptSwitch' \
  "Background Prompt tab opening must preserve opener-preview-before-switch ordering."
check_file_contains_rule "${APP_URL_OPEN_COORDINATOR}" "${APP_URL_OPEN_COORDINATOR_REL}" \
  'backgroundOpenPromptCoordinator\.showForTab\(createdTab\)' \
  "App URL background opens must enter the canonical Background Prompt owner directly."
check_file_contains_rule "${TAB_CLOSE_COORDINATOR}" "${TAB_CLOSE_COORDINATOR_REL}" \
  'backgroundOpenPromptCoordinator\.dismissTab\(' \
  "Tab Close must remove Background Prompt items through the canonical owner directly."
check_file_contains_rule "${TAB_CLOSE_COORDINATOR}" "${TAB_CLOSE_COORDINATOR_REL}" \
  'tabSwitchCoordinator\.synchronizeWebTabsAndPreviewAssets\(' \
  "Tab Close must synchronize closed-tab runtime and preview assets through the canonical tab-list owner."
check_file_contains_rule "${TAB_CLOSE_COORDINATOR}" "${TAB_CLOSE_COORDINATOR_REL}" \
  'resolveTabHomeCoordinator\(\)\.showHomeSurface\(' \
  "Tab Close Home outcomes must enter the existing Tab Home owner instead of routing through BrowserShell."
check_file_contains_rule "${TAB_CLOSE_COORDINATOR}" "${TAB_CLOSE_COORDINATOR_REL}" \
  'pageFindCoordinator\.handleActiveTabChanged\(' \
  "Tab Close must refresh Page Find through its fixed owner dependency."
check_file_contains_rule "${TAB_CLOSE_COORDINATOR}" "${TAB_CLOSE_COORDINATOR_REL}" \
  'privateModeLockCoordinator\.synchronizeCurrentBoundary\(' \
  "Tab Close must refresh the privacy boundary through its fixed owner dependency."
check_file_contains_rule "${TAB_SWITCH_COORDINATOR}" "${TAB_SWITCH_COORDINATOR_REL}" \
  'synchronizeWebTabsAndPreviewAssets\(\)' \
  "Tab Switch must keep WebTabs and preview-asset synchronization behind one tab-list owner entry."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private commitCloseTabTransition|private removeClosedTabPreview' \
  "BrowserShellPage must not regain CloseTab animation policy or closed-preview orchestration helpers."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'executeTabListAnimation: \(plan: BrowserCloseTabAnimationPlan\)' \
  "BrowserShellPage must keep CloseTab animation execution as explicit ArkUI wiring."
tab_close_host_callback_count="$(awk '
  /export interface BrowserCloseTabApplicationHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${TAB_CLOSE_COORDINATOR}")"
if [ "${tab_close_host_callback_count}" -gt 13 ]; then
  report_failure "${TAB_CLOSE_COORDINATOR_REL} must keep the CloseTab Host at no more than 13 shell-facts/state-publication/ArkUI/diagnostic callbacks; found ${tab_close_host_callback_count}."
fi
check_file_contains_rule "${WEB_PAGE_PRESENTATION_EVENT_COORDINATOR}" "${WEB_PAGE_PRESENTATION_EVENT_COORDINATOR_REL}" \
  'backgroundOpenPromptCoordinator\.updateTab\(' \
  "Web presentation events must update Background Prompt state through the canonical owner."
check_file_not_contains_rule "${FAVICON_COORDINATOR}" "${FAVICON_COORDINATOR_REL}" \
  'BrowserFaviconApplyHostAdapter|updateBackgroundPromptFavicon' \
  "Favicon handling must not regain the single-caller HostAdapter or prompt callback seam."
check_file_contains_rule "${PULL_REFRESH_COORDINATOR}" "${PULL_REFRESH_COORDINATOR_REL}" \
  'private state: BrowserPullRefreshState' \
  "Pull Refresh must keep its canonical application state inside the single owner."
check_file_contains_rule "${PULL_REFRESH_COORDINATOR}" "${PULL_REFRESH_COORDINATOR_REL}" \
  'private refreshCompletionTimeoutTimer: number' \
  "Pull Refresh completion timeout ownership must stay inside the application owner."
check_file_contains_rule "${PULL_REFRESH_COORDINATOR}" "${PULL_REFRESH_COORDINATOR_REL}" \
  'activeTabRuntimeRestoreCoordinator\.reloadActive\(.user_manual_reload.\)' \
  "Pull Refresh reload execution must route directly through the existing Active Runtime Restore owner."
pull_refresh_shell_callback_count="$(awk '
  /export interface BrowserPullRefreshShell/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /=>/ { callbacks += 1 }
  END { print callbacks + 0 }
' "${PULL_REFRESH_COORDINATOR}")"
if [ "${pull_refresh_shell_callback_count}" -gt 3 ]; then
  report_failure "${PULL_REFRESH_COORDINATOR_REL} must keep the Pull Refresh shell at no more than 3 facts/snapshot/UI-effect callbacks."
fi
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State pullRefreshState: BrowserPullRefreshState' \
  "BrowserShellPage must keep the Pull Refresh snapshot as explicit ArkUI presentation state."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State pullRefreshRefreshing: boolean' \
  "BrowserShellPage must keep the ArkUI Refresh two-way refreshing binding explicit."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserPullRefreshShell: BrowserPullRefreshShell' \
  "BrowserShellPage must expose only current facts, snapshot publication, and the atomic chrome preparation effect."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserPullRefreshInputAdapter|browserPullRefreshInputAdapter|private buildPullRefreshContext|private isPullRefreshEnabledForActiveSurface|private handlePullRefreshOffset|private handlePullRefreshStatus|private handlePullRefreshRequested|private applyPullRefreshAction|private resetPullRefreshForSurfaceChange|private schedulePullRefreshCompletionTimeout|private clearPullRefreshCompletionTimeout' \
  "BrowserShellPage must not regain Pull Refresh status mapping, state-machine, reload ordering, or timer ownership."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'getPullRefreshState|applyPullRefreshState|schedulePullRefreshCompletionTimeout|clearPullRefreshCompletionTimeout' \
  "Web Page Lifecycle must call the canonical Pull Refresh owner directly instead of round-tripping state through BrowserShell."
check_file_not_contains_rule "${PULL_REFRESH_MODELS}" "${PULL_REFRESH_MODELS_REL}" \
  'BrowserPullRefreshDecision|BrowserPullRefreshPresentationInput' \
  "Pull Refresh decision and presentation-input DTOs must stay internal instead of widening the external interface."
if [ -e "${OLD_PULL_REFRESH_INPUT_ADAPTER}" ]; then
  report_failure "${OLD_PULL_REFRESH_INPUT_ADAPTER_REL} must stay deleted; RefreshStatus mapping belongs inside the Pull Refresh owner."
fi
check_file_contains_rule "${APP_PROXY_QUICK_COORDINATOR}" "${APP_PROXY_QUICK_COORDINATOR_REL}" \
  'private state: AppProxyQuickSheetState' \
  "App Proxy Quick must keep one canonical application snapshot inside the shared owner."
check_file_contains_rule "${APP_PROXY_QUICK_COORDINATOR}" "${APP_PROXY_QUICK_COORDINATOR_REL}" \
  'private surfaceGeneration: number' \
  "App Proxy Quick dismiss/reopen stale-result ordering must stay owner-held."
app_proxy_quick_shell_callback_count="$(awk '
  /export interface AppProxyQuickSheetShell/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /=>/ { callbacks += 1 }
  END { print callbacks + 0 }
' "${APP_PROXY_QUICK_COORDINATOR}")"
if [ "${app_proxy_quick_shell_callback_count}" -gt 5 ]; then
  report_failure "${APP_PROXY_QUICK_COORDINATOR_REL} must keep the reusable Quick Sheet shell at no more than 5 snapshot/surface/platform callbacks."
fi
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State appProxyQuickSheetState: AppProxyQuickSheetState' \
  "BrowserShellPage must keep one explicit App Proxy Quick snapshot for toolbar and sheet presentation."
check_file_contains_rule "${SETTINGS_CENTER_SCREEN}" "${SETTINGS_CENTER_SCREEN_REL}" \
  '@State private appProxyQuickSheetState: AppProxyQuickSheetState' \
  "SettingsCenterScreen must keep one explicit App Proxy Quick snapshot for sheet presentation."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'appProxyActive: this\.appProxyQuickSheetState\.toolbarActive' \
  "Browser toolbar proxy activity must come from the explicit Quick Session snapshot."
check_file_contains_rule "${APP_PROXY_QUICK_CONTENT}" "${APP_PROXY_QUICK_CONTENT_REL}" \
  'this\.state\.switchingGlobalEnabled' \
  "Quick Sheet content must consume global mutation busy state from the canonical snapshot."
check_file_contains_rule "${APP_PROXY_QUICK_CONTENT}" "${APP_PROXY_QUICK_CONTENT_REL}" \
  'this\.state\.switchingProfileId' \
  "Quick Sheet content must consume profile mutation busy state from the canonical snapshot."
check_file_contains_rule "${APP_PROXY_QUICK_CONTENT}" "${APP_PROXY_QUICK_CONTENT_REL}" \
  'export struct AppProxyQuickSheetContent' \
  "App Proxy Quick must expose reusable content for the shared system Sheet host."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'AppProxyToolbarActiveViewModel|appProxyToolbarActive|switchingAppProxyGlobalEnabled|switchingAppProxyProfileId|AppProxyQuickSheetMutationResult|private openAppProxyQuickSheet|private dismissAppProxyQuickSheet|private async toggleAppProxyGlobalEnabledFromQuickSheet|private async selectAppProxyProfileFromQuickSheet|private applyAppProxyQuickSheetMutationResult|private openAppProxySettingsFromQuickSheet' \
  "BrowserShellPage must not regain App Proxy Quick optimistic state, result interpretation, or toolbar projection ownership."
check_file_not_contains_rule "${SETTINGS_CENTER_SCREEN}" "${SETTINGS_CENTER_SCREEN_REL}" \
  'switchingAppProxyGlobalEnabled|switchingAppProxyProfileId|AppProxyQuickSheetMutationResult|private openAppProxyQuickSheet|private async toggleAppProxyGlobalEnabled|private async selectAppProxyProfile|private applyAppProxyQuickSheetMutationResult|private openAppProxySettingsFromQuickSheet' \
  "SettingsCenterScreen must not regain duplicate App Proxy Quick busy state or mutation-result ordering."
check_file_contains_rule "${SETTINGS_DESTINATION_OWNER}" "${SETTINGS_DESTINATION_OWNER_REL}" \
  'private catalog: SettingsDestinationCatalog = new SettingsDestinationCatalog\(\)' \
  "Settings Destination Navigation owner must privately own the one closed Settings Catalog."
check_file_contains_rule "${SETTINGS_DESTINATION_CATALOG}" "${SETTINGS_DESTINATION_CATALOG_REL}" \
  'class SettingsDestinationCatalog' \
  "Settings search must keep its compiled Catalog subordinate to the Settings Destination Navigation owner."
if [ -e "${OLD_SETTINGS_SEARCH_VIEW_MODEL}" ]; then
  report_failure "${OLD_SETTINGS_SEARCH_VIEW_MODEL_REL} must stay deleted; Settings search belongs to the Settings Destination Navigation owner."
fi
if [ -e "${OLD_SETTINGS_LARGE_DIRECTORY_VIEW_MODEL}" ]; then
  report_failure "${OLD_SETTINGS_LARGE_DIRECTORY_VIEW_MODEL_REL} must stay deleted; two-pane projection belongs to the Settings Destination Navigation owner."
fi
if grep -R -E -n \
  'SettingsCenterSearchViewModel|SETTINGS_CENTER_SEARCH_DOCUMENTS|SettingsLargeScreenDirectoryViewModel' \
  "${REPO_ROOT}/AiraBrowser/entry/src/main" "${REPO_ROOT}/AiraBrowser/entry/src/test" >/dev/null 2>&1; then
  report_failure "Settings source must not restore the deleted standalone search or two-pane directory ownership."
fi
check_file_not_contains_rule "${APP_PROXY_QUICK_COORDINATOR}" "${APP_PROXY_QUICK_COORDINATOR_REL}" \
  'AppProxyQuickSheetMutationResult' \
  "App Proxy Quick mutation results must stay internal instead of widening the shared owner interface."
if [ -e "${OLD_APP_PROXY_TOOLBAR_ACTIVE_VIEW_MODEL}" ]; then
  report_failure "${OLD_APP_PROXY_TOOLBAR_ACTIVE_VIEW_MODEL_REL} must stay deleted; toolbar active projection belongs inside the Quick Session owner."
fi
check_file_contains_rule "${APP_REVIEW_PROMPT_COORDINATOR}" "${APP_REVIEW_PROMPT_COORDINATOR_REL}" \
  'setTimeout\(' \
  "App Review Prompt evaluation timing must stay inside the per-shell application owner."
check_file_contains_rule "${APP_REVIEW_PROMPT_COORDINATOR}" "${APP_REVIEW_PROMPT_COORDINATOR_REL}" \
  'systemSettingsLaunchService\.showAppReviewPrompt\(' \
  "App Review Prompt eligibility must invoke the native AppGallery review dialog through the system service."
check_file_not_contains_rule "${APP_REVIEW_PROMPT_COORDINATOR}" "${APP_REVIEW_PROMPT_COORDINATOR_REL}" \
  'transientSurfaceCoordinator\.present\(|openAppReviewPage\(|repository\.accept\(' \
  "App Review Prompt must not restore a custom pre-prompt, AppGallery fallback, or false accepted-state inference."
if [ -e "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/components/review/AppReviewPromptSheet.ets" ]; then
  report_failure "The retired custom App Review Prompt Sheet must stay deleted; use AppGalleryKit's native dialog."
fi
app_review_prompt_shell_callback_count="$(awk '
  /export interface AppReviewPromptShell/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /=>/ { callbacks += 1 }
  END { print callbacks + 0 }
' "${APP_REVIEW_PROMPT_COORDINATOR}")"
if [ "${app_review_prompt_shell_callback_count}" -gt 2 ]; then
  report_failure "${APP_REVIEW_PROMPT_COORDINATOR_REL} must keep the native App Review shell at no more than 2 facts/Toast callbacks."
fi
app_review_prompt_owner_count="$(grep -c 'new AppReviewPromptCoordinator(' "${SHELL_PAGE}" || true)"
if [ "${app_review_prompt_owner_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must compose exactly one per-shell App Review Prompt narrative owner."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'AppReviewPromptSheet|AppReviewPromptUiState|appReviewPromptState|buildAppReviewPromptOverlay|sharedAppReviewPromptCoordinator|appReviewPromptEvaluateTimer|scheduleAppReviewPromptEvaluation|evaluateAppReviewPrompt|showAppReviewPrompt\(|dismissAppReviewPrompt|acceptAppReviewPrompt|deferAppReviewPrompt|suppressAppReviewPrompt|cancelAppReviewPromptEvaluationTimer|isAppReviewPromptBlockingSurfaceVisible' \
  "BrowserShellPage must not regain App Review UI state, custom surface, eligibility, timer, fallback, or persistence ordering."
check_file_not_contains_rule "${BROWSER_APP_RUNTIME}" "${BROWSER_APP_RUNTIME_REL}" \
  'sharedAppReviewPromptCoordinator|new AppReviewPromptCoordinator' \
  "BrowserAppRuntime must not create a second global App Review Prompt owner."
check_file_contains_rule "${BROWSER_APP_RUNTIME}" "${BROWSER_APP_RUNTIME_REL}" \
  'sharedAppReviewPromptRepository\.recordLaunch\(\)' \
  "BrowserAppRuntime must keep global launch counting directly on the shared App Review repository."
check_file_contains_rule "${RELEASE_NOTICE_PRESENTATION_COORDINATOR}" \
  "${RELEASE_NOTICE_PRESENTATION_COORDINATOR_REL}" \
  'private evaluationGeneration: number' \
  "Release Notice evaluation completion must stay gated by the per-shell owner generation."
check_file_contains_rule "${RELEASE_NOTICE_PRESENTATION_COORDINATOR}" \
  "${RELEASE_NOTICE_PRESENTATION_COORDINATOR_REL}" \
  "transientSurfaceCoordinator\.openSystemSheet\('releaseNotice'\)" \
  "Release Notice System Sheet presentation must stay inside the narrative owner."
check_file_contains_rule "${RELEASE_NOTICE_PRESENTATION_COORDINATOR}" \
  "${RELEASE_NOTICE_PRESENTATION_COORDINATOR_REL}" \
  'appReviewPromptCoordinator\.handleReleaseNoticePresentationCleared\(\)' \
  "Release Notice clear must keep the deferred App Review retry ordering inside the owner."
check_file_contains_rule "${RELEASE_NOTICE_PRESENTATION_COORDINATOR}" \
  "${RELEASE_NOTICE_PRESENTATION_COORDINATOR_REL}" \
  'routeCoordinator\.openChangelogPage\(\)' \
  "Release Notice full changelog navigation must use the fixed BrowserShell route owner."
check_file_contains_rule "${RELEASE_NOTICE_SHEET}" "${RELEASE_NOTICE_SHEET_REL}" \
  'onAction: \(action: ReleaseNoticePresentationAction\)' \
  "Release Notice Sheet must emit one typed presentation action callback."
check_file_not_contains_rule "${RELEASE_NOTICE_SHEET}" "${RELEASE_NOTICE_SHEET_REL}" \
  'onConfirm:|onOpenFullChangelog:' \
  "Release Notice Sheet must not regain peer confirm/changelog callbacks."
release_notice_shell_callback_count="$(awk '
  /^export interface ReleaseNoticePresentationShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /=>/ { callbacks += 1 }
  END { print callbacks + 0 }
' "${RELEASE_NOTICE_PRESENTATION_COORDINATOR}")"
if [ "${release_notice_shell_callback_count}" -gt 2 ]; then
  report_failure "${RELEASE_NOTICE_PRESENTATION_COORDINATOR_REL} must keep the Release Notice shell at no more than 2 facts/snapshot callbacks."
fi
release_notice_owner_count="$(grep -c 'new ReleaseNoticePresentationCoordinator(' "${SHELL_PAGE}" || true)"
if [ "${release_notice_owner_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must compose exactly one per-shell Release Notice Presentation owner."
fi
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State releaseNoticeState: ReleaseNoticeUiState = this\.releaseNoticePresentationCoordinator\.getSnapshot\(\)' \
  "BrowserShellPage must keep one explicit Release Notice snapshot initialized from the owner."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'releaseNoticeVisible: this\.releaseNoticeState\.visible' \
  "Release Notice prompt blocking must observe the first-level ArkUI snapshot explicitly."
check_file_contains_rule "${SHELL_ROUTE_COORDINATOR}" "${SHELL_ROUTE_COORDINATOR_REL}" \
  'openChangelogPage\(\): void' \
  "BrowserShell route ownership must expose the semantic changelog entry."
check_file_not_contains_rule "${SHELL_ROUTE_COORDINATOR}" "${SHELL_ROUTE_COORDINATOR_REL}" \
  'resolveDownloadConfirmOverlayCoordinator|recordDiagnostic\(|buildBoundaryDiagnosticLine\(' \
  "BrowserShell route ownership must not restore removed Download Overlay diagnostics."
check_file_contains_rule "${SHELL_ROUTE_COORDINATOR}" "${SHELL_ROUTE_COORDINATOR_REL}" \
  'resolveSiteInteractionLogicService\(\)\.resolveOrigin' \
  "BrowserShell route ownership must enter site-origin policy directly."
route_shell_callback_count="$(awk '
  /export interface BrowserShellRouteCoordinatorHost \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${SHELL_ROUTE_COORDINATOR}")"
if [ "${route_shell_callback_count}" -gt 5 ]; then
  report_failure "${SHELL_ROUTE_COORDINATOR_REL} must keep Route Host at no more than 5 context/state/platform callbacks; found ${route_shell_callback_count}."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'recordDownloadManagementOpenBeforeReset:|recordDownloadManagementOpenAfterReset:|buildDownloadBoundaryDiagnosticLine:|resolvePageUrlForActiveTab:' \
  "BrowserShellPage must not regain fixed Route owner forwarding callbacks."
check_file_not_contains_rule "${RELEASE_NOTICE_PRESENTATION_COORDINATOR}" \
  "${RELEASE_NOTICE_PRESENTATION_COORDINATOR_REL}" \
  'ReleaseNoticePresentationHost|isDialogVisible\(|dismiss\(\): ReleaseNoticeUiState|acknowledgeCurrentVersion\(\): Promise<void>' \
  "Release Notice must not regain the temporary Host or shallow state/ack forwarding interface."
check_file_not_contains_rule "${RELEASE_NOTICE_COORDINATOR}" "${RELEASE_NOTICE_COORDINATOR_REL}" \
  'ReleaseNoticeEligibilityInput|homeVisible|privateMode|appVisible|blockingSurfaceVisible|BrowserTransientPromptBlockingFacts' \
  "Release Notice domain implementation must not regain presentation eligibility or transient-surface knowledge."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'SETTINGS_CHANGELOG_ROUTE|ReleaseNoticeEligibilityInput|ReleaseNoticePresentationHost|buildReleaseNoticeEligibilityInput|showReleaseNotice\(|dismissReleaseNotice|clearReleaseNoticePresentation|acknowledgeReleaseNotice|openReleaseNoticeFullChangelog|isReleaseNoticeBlockingSurfaceVisible|releaseNoticePresentationCoordinator\.cancelEvaluationTimer|releaseNoticePresentationCoordinator\.isDialogVisible|releaseNoticePresentationCoordinator\.dismiss\(|releaseNoticePresentationCoordinator\.acknowledgeCurrentVersion' \
  "BrowserShellPage must not regain Release Notice eligibility, timer, surface, acknowledgement, routing, or App Review retry ordering."
check_file_contains_rule "${HOME_SHORTCUT_SELECTION_COORDINATOR}" "${HOME_SHORTCUT_SELECTION_COORDINATOR_REL}" \
  'handleAction\(action: HomeShortcutSelectionAction\): void' \
  "Home Shortcut Selection must expose one typed owner action entry."
check_file_not_contains_rule "${HOME_SHORTCUT_SELECTION_COORDINATOR}" "${HOME_SHORTCUT_SELECTION_COORDINATOR_REL}" \
  '^  (selectTab|openFolder|toggleSystemShortcut|toggleBookmarkShortcut)\(' \
  "Home Shortcut Selection ordinary action-specific methods must stay internal behind handleAction."
check_file_contains_rule "${HOME_SHORTCUT_SELECTION_COORDINATOR}" "${HOME_SHORTCUT_SELECTION_COORDINATOR_REL}" \
  'handleSystemBack\(\): void' \
  "Home Shortcut Selection must keep its distinct system Back entry for BrowserMainBackCoordinator."
check_file_contains_rule "${HOME_SHORTCUT_SELECTION_COORDINATOR}" "${HOME_SHORTCUT_SELECTION_COORDINATOR_REL}" \
  'constructor\(shell: HomeShortcutSelectionShell\)' \
  "Home Shortcut Selection must own one fixed shell instead of receiving per-call Host plumbing."
check_file_not_contains_rule "${HOME_SHORTCUT_SELECTION_COORDINATOR}" "${HOME_SHORTCUT_SELECTION_COORDINATOR_REL}" \
  'HomeShortcutSelectionHost|host: HomeShortcutSelection|host\.readState|host\.applyState' \
  "Home Shortcut Selection must not regain per-call Host/state forwarding."
check_file_contains_rule "${HOME_SHORTCUT_SELECTION_SHEET}" "${HOME_SHORTCUT_SELECTION_SHEET_REL}" \
  'onAction: \(action: HomeShortcutSelectionAction\)' \
  "Home Shortcut Selection Sheet must emit one typed action callback."
check_file_not_contains_rule "${HOME_SHORTCUT_SELECTION_SHEET}" "${HOME_SHORTCUT_SELECTION_SHEET_REL}" \
  'onSelectTab:|onBackFolder:|onEnterFolder:|onToggleSystem:|onToggleBookmark:' \
  "Home Shortcut Selection Sheet must not regain peer action callbacks."
if [ -e "${OLD_TAB_SWITCH_ATTACH_RETRY}" ]; then
  report_failure "${OLD_TAB_SWITCH_ATTACH_RETRY_REL} must stay deleted; controller-attach retry belongs inside Active Runtime Sync."
fi
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'private scheduleDeferredWork\(' \
  "Tab Home must internally own deferred Home-surface work scheduling."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'runActiveSnapshotPersistFromHost\(' \
  "Tab Home must enter the fixed active-snapshot owner directly."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'tabSwitchCoordinator\.commitTabs\(' \
  "Tab Home must enter the fixed tab-list commit owner directly."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'private runDeferredHomeSurfaceWork\(' \
  "Tab Home must execute its fixed deferred Home work behind the owner interface."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'applyBoundary\(' \
  "Tab Home must own Home boundary and appearance application behind one semantic entry."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'homeWallpaperCoordinator\.refreshForHomeVisible\(' \
  "Tab Home must enter the fixed Home wallpaper owner directly."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'homepageBackdropAppearanceCoordinator\.sync\(' \
  "Tab Home must enter the fixed Home backdrop appearance owner directly."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'arkWebMediaTakeoverCoordinator\.clearTab\(' \
  "Tab Home must enter the fixed ArkWeb media cleanup owner directly."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'refreshAppearance\(' \
  "Tab Home must own Home appearance refresh behind a semantic entry."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'refreshWallpaperPresentation\(' \
  "Tab Home must own Home wallpaper refresh behind a semantic entry."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'refreshBackdropAppearance\(' \
  "Tab Home must own Home backdrop refresh and diagnostics behind a semantic entry."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'refreshTabsOverviewAppearance\(' \
  "Tab Home must own Tabs Overview theme refresh for the current Home boundary."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'buildContentPresentation\(' \
  "Tab Home must own the combined Home content presentation entry."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'buildContentThemePresentation\(' \
  "Tab Home must own the combined Home content theme presentation entry."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'browserForegroundPresentationViewModel\.resolveHomePresentation\(' \
  "Tab Home content theme presentation must enter the fixed Browser Foreground Presentation owner directly."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'homeWallpaperInteractionColorViewModel\.resolveInteractionColors\(' \
  "Tab Home content theme presentation must enter the fixed wallpaper interaction-color owner directly."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'homeShortcutStateCoordinator\.buildPresentationState\(' \
  "Tab Home content presentation must enter the fixed Home Shortcut owner directly."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'recentlyClosedApplicationCoordinator\.buildHomePresentationState\(' \
  "Tab Home content presentation must enter the fixed Recently Closed owner directly."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'loadSearchEngineSelection\(' \
  "Tab Home must own lifecycle Search Engine selection loading without dependent refresh side effects."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'handleSearchEngineSettingsRevision\(' \
  "Tab Home must own Search Engine settings-revision application sequencing."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'selectSearchEngine\(' \
  "Tab Home must own Search Engine selection application sequencing."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  "customHomepageRuntimeCoordinator\.syncBridge\('search_engines'\)" \
  "Tab Home Search Engine application must synchronize the fixed Custom Homepage bridge directly."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserTabHomeShell: BrowserTabHomeShell' \
  "BrowserShellPage must expose one narrow Tab Home state/ArkUI effect shell."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserTabHomeFlowHost|browserTabHomeFlowHost|BrowserHomeSurfacePlanService|homeSurfaceDeferredWorkTimer|private showHomeSurface|private applyHomeSurfacePreviewFallback|private scheduleHomeSurfaceDeferredWork|private runHomeSurfaceDeferredWork|private async goHome\(|private applyHomeBoundary\(|private refreshHomeAppearanceState\(|private refreshHomeWallpaperPresentation\(|private syncHomepageBackdropAppearanceFromCache\(|private applyHomepageBackdropAppearanceState\(|private refreshTabsSheetAppearanceState\(|private buildHomepageBackdropAppearanceSource\(|private buildHomepageBackdropAppearanceEffect\(|applyTabsOverviewHomeTabMutation:|prepareHomePresentation:|runDeferredHomeSurfaceWork:|completeDirectHomeNavigation:|clearTransientTabState:' \
  "BrowserShellPage must not regain Tab Home planning, timers, flow ordering, or the old wide Host wiring."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State homeShortcutGridWidth:|private buildHomeShortcutPresentationState\(|private syncHomeShortcutGridWidthForViewport\(|private resolveHomeShortcutGridWidth\(|private resolveHomeShortcutGridWidthForViewport\(|private resolveHomeContentHorizontalPadding\(|private resolveHomeContentTopPadding\(|private resolveHomeBottomSpacerExtra\(|private resolveHomeSectionVerticalGap\(|private resolveHomeRecentlyClosedColumns\(|private resolveHomeRecentlyClosedColumnGap\(|private resolveHomeRecentlyClosedRowGap\(|private buildHomeRecentlyClosedPresentationState\(' \
  "BrowserShellPage must not regain derived Home content layout/presentation ownership."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'HomeWallpaperTextColorViewModel|HomeWallpaperInteractionColorViewModel|private resolveHomeWallpaperTextColorState\(|private resolveHomeWallpaperInteractionColorState\(|private resolveHomePrimaryTextColor\(|private resolveHomeSecondaryTextColor\(|private resolveHomeTextShadow\(|private resolveHomePressedBackgroundColor\(|private resolveHomePressedBackdropBlurRadius\(|private buildHomeContentThemePresentationState\(' \
  "BrowserShellPage must not regain Home content theme presentation composition or scalar projection helpers."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private loadSavedSearchEngine\(|private selectSearchEngine\(|private applySearchEngineSelectionSnapshot\(|this\.searchEngineSelectionCoordinator\.getSnapshot\(|this\.searchEngineSelectionCoordinator\.select\(' \
  "BrowserShellPage must not regain Search Engine selection loading, persistence, or dependent-owner orchestration."
tab_home_shell_callback_count="$(awk '
  /export interface BrowserTabHomeShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${TAB_HOME_COORDINATOR}")"
if [ "${tab_home_shell_callback_count}" -gt 9 ]; then
  report_failure "${TAB_HOME_COORDINATOR_REL} must keep Tab Home Shell at no more than 9 facts/state/platform callbacks; found ${tab_home_shell_callback_count}."
fi
check_file_not_contains_rule "${TABS_OVERVIEW_SESSION_COORDINATOR}" "${TABS_OVERVIEW_SESSION_COORDINATOR_REL}" \
  "type: 'show_home_surface'|BrowserTabHomeFlowHost" \
  "Tabs Overview must call the Tab Home owner directly instead of replaying Home through a page effect or Host."
if [ -e "${OLD_HOME_SURFACE_PLAN}" ]; then
  report_failure "${OLD_HOME_SURFACE_PLAN_REL} must stay deleted; Home surface planning and deferred timing belong inside Tab Home."
fi
check_file_contains_rule "${WINDOW_CONTEXT_COORDINATOR}" "${WINDOW_CONTEXT_COORDINATOR_REL}" \
  'private scheduleNextPendingLaunchPoll\(' \
  "Window Context must internally own pending-launch poll timing and generation ordering."
check_file_contains_rule "${WINDOW_CONTEXT_COORDINATOR}" "${WINDOW_CONTEXT_COORDINATOR_REL}" \
  'hostedRuntimeSurfacePort\.parkActiveDesktopWebEntry\(' \
  "Window Context must keep the desktop Web-entry parking decision behind its narrative owner."
check_file_contains_rule "${WINDOW_CONTEXT_COORDINATOR}" "${WINDOW_CONTEXT_COORDINATOR_REL}" \
  'this\.resolveLaunchApplication\(\)\.apply\(launchPayload\)' \
  "Window Context must apply consumed launch payloads inside its narrative owner."
check_file_contains_rule "${WINDOW_CONTEXT_COORDINATOR}" "${WINDOW_CONTEXT_COORDINATOR_REL}" \
  'resolveCurrentTabSessionBoundary\(\): BrowserCreateTabOptions' \
  "Window Context must own current tab-session boundary precedence."
check_file_contains_rule "${WINDOW_CONTEXT_COORDINATOR}" "${WINDOW_CONTEXT_COORDINATOR_REL}" \
  'resolveCurrentTabSessionProfileId\(\): BrowserProfileId' \
  "Window Context must own current tab-session profile projection."
check_file_not_contains_rule "${WINDOW_CONTEXT_COORDINATOR}" "${WINDOW_CONTEXT_COORDINATOR_REL}" \
  'handleLaunchPayload:' \
  "Window Context Shell must not forward consumed launch payloads back to BrowserShell."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserWindowContextShell: BrowserWindowContextShell' \
  "BrowserShellPage must expose one narrow Window Context state/platform shell."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserWindowContextSwitchHost|browserWindowContextSwitchHost|BrowserPendingWindowLaunchService|browserPendingWindowLaunchService|private resolveWindowScope\(|private handleExternalLaunchPayload\(|private openAppShortcutTarget\(|private handleInlineAppShortcutAction\(|private applyDesktopWebEntryLaunchPlan\(|private buildCurrentTabSessionBoundaryCreateOptions\(|private getCurrentTabSessionProfileId\(' \
  "BrowserShellPage must not regain Window Context ordering or the peer Pending Launch service wiring."
check_file_contains_rule "${WINDOW_LAUNCH_APPLICATION}" "${WINDOW_LAUNCH_APPLICATION_REL}" \
  'class BrowserWindowFixedLaunchApplication implements BrowserWindowLaunchApplication' \
  "Window launch application must remain one subordinate executor."
check_file_contains_rule "${WINDOW_LAUNCH_APPLICATION}" "${WINDOW_LAUNCH_APPLICATION_REL}" \
  'webAppSessionCoordinator\.prepareLaunch\(' \
  "Window launch application must prepare desktop Web entries through the fixed WebApp Session owner."
check_file_contains_rule "${WINDOW_LAUNCH_APPLICATION}" "${WINDOW_LAUNCH_APPLICATION_REL}" \
  'appUrlOpenCoordinator\.open\(' \
  "Window launch application must open external URLs through the fixed App URL owner."
check_file_contains_rule "${WINDOW_LAUNCH_APPLICATION}" "${WINDOW_LAUNCH_APPLICATION_REL}" \
  'foregroundTabCreationCoordinator\.createNewTab\(' \
  "Window launch application must create desktop Web-entry tabs through the fixed Foreground Tab owner."
check_file_contains_rule "${WINDOW_LAUNCH_APPLICATION}" "${WINDOW_LAUNCH_APPLICATION_REL}" \
  'tabHomeCoordinator\.applyBoundary\(' \
  "Window launch application must apply Home boundary changes through the fixed Tab Home owner."
check_file_contains_rule "${WINDOW_LAUNCH_APPLICATION}" "${WINDOW_LAUNCH_APPLICATION_REL}" \
  'tabSwitchCoordinator\.switchToTab\(' \
  "Window launch application must reuse desktop Web-entry tabs through the fixed Tab Switch owner."
check_file_not_contains_rule "${WINDOW_LAUNCH_APPLICATION}" "${WINDOW_LAUNCH_APPLICATION_REL}" \
  'BrowserWindowLaunchCoordinator|BrowserWindowLaunchPort|BrowserWindowLaunchHostAdapter' \
  "Window launch application must stay subordinate and must not become a peer Coordinator, Port, or HostAdapter."
window_launch_dependency_callback_count="$(awk '
  /interface BrowserWindowFixedLaunchDependencies \{/ { in_dependencies = 1; next }
  in_dependencies && /^}/ { print count + 0; exit }
  in_dependencies && /: \(/ { count += 1 }
' "${WINDOW_LAUNCH_APPLICATION}")"
if [ "${window_launch_dependency_callback_count}" -ne 0 ]; then
  report_failure "${WINDOW_LAUNCH_APPLICATION_REL} fixed dependencies must be owner objects, not page forwarding callbacks; found ${window_launch_dependency_callback_count}."
fi
window_launch_shell_callback_count="$(awk '
  /export interface BrowserWindowLaunchApplicationShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${WINDOW_LAUNCH_APPLICATION}")"
if [ "${window_launch_shell_callback_count}" -ne 6 ]; then
  report_failure "${WINDOW_LAUNCH_APPLICATION_REL} Shell must keep exactly six live-fact/UI/platform callbacks; found ${window_launch_shell_callback_count}."
fi
if [ -e "${OLD_PENDING_WINDOW_LAUNCH_SERVICE}" ]; then
  report_failure "${OLD_PENDING_WINDOW_LAUNCH_SERVICE_REL} must stay deleted; pending launch arbitration and polling belong inside Window Context."
fi
check_file_contains_rule "${READER_MODE_COORDINATOR}" "${READER_MODE_COORDINATOR_REL}" \
  'voiceDialog: ReaderModeSpeechVoiceDialogPresentation' \
  "Reader Mode must publish speech and voice-dialog state through one canonical Session snapshot."
check_file_contains_rule "${READER_MODE_COORDINATOR}" "${READER_MODE_COORDINATOR_REL}" \
  'effectApplication\.apply\(effect\)' \
  "Reader Mode must apply BrowserShell effects through one subordinate application."
check_file_contains_rule "${OFFLINE_PAGE_VIEWER}" "${OFFLINE_PAGE_VIEWER_REL}" \
  'onEffect: \(effect: ReaderModeEffect\)' \
  "Offline reader must retain its local effect fallback when no BrowserShell application is bound."
check_file_contains_rule "${BROWSER_WINDOW_SESSION_APPLICATION}" \
  "${BROWSER_WINDOW_SESSION_APPLICATION_REL}" \
  'private readonly articleReadingCoordinator: ReaderModeCoordinator;' \
  "Browser Window Session must own the Article Reading Session coordinator."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private articleReadingSession: BrowserWindowSessionArticleReadingPort' \
  "BrowserShellPage must access Article Reading through the Window Session Port."
check_file_contains_rule "${OFFLINE_PAGE_VIEWER}" "${OFFLINE_PAGE_VIEWER_REL}" \
  'private articleReadingSession: BrowserWindowSessionArticleReadingPort' \
  "OfflinePageViewerScreen must access the same Article Reading Window Session Port."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'articleReadingSession\.setEffectApplication\(this\.readerModeApplication\)' \
  "BrowserShellPage must bind the Window-owned Article Reading Session to the subordinate application."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'new ReaderModeCoordinator\(' \
  "BrowserShellPage must not recreate Article Reading Session ownership."
check_file_not_contains_rule "${OFFLINE_PAGE_VIEWER}" "${OFFLINE_PAGE_VIEWER_REL}" \
  'new ReaderModeCoordinator\(' \
  "OfflinePageViewerScreen must not recreate Article Reading Session ownership."
check_file_contains_rule "${READER_MODE_OVERLAY}" "${READER_MODE_OVERLAY_REL}" \
  'ReadingSurface\({' \
  "Article Reading must render through the shared Reading Surface."
check_file_contains_rule "${NOVEL_READER_OVERLAY}" "${NOVEL_READER_OVERLAY_REL}" \
  'ReadingSurface\({' \
  "Novel text reading must render through the shared Reading Surface."
check_file_contains_rule "${READER_MODE_OVERLAY}" "${READER_MODE_OVERLAY_REL}" \
  'ReadingExperienceChrome\({' \
  "Article Reading must mount the complete shared Reading Chrome."
check_file_contains_rule "${NOVEL_READER_OVERLAY}" "${NOVEL_READER_OVERLAY_REL}" \
  'ReadingExperienceChrome\({' \
  "Novel text reading must mount the complete shared Reading Chrome."
check_file_contains_rule "${READING_EXPERIENCE_CHROME}" "${READING_EXPERIENCE_CHROME_REL}" \
  'onPanelRequest' \
  "Shared Reading Chrome must emit common appearance, text, and settings panel requests."
check_file_contains_rule "${READING_EXPERIENCE_SYSTEM_SHEET}" "${READING_EXPERIENCE_SYSTEM_SHEET_REL}" \
  'ReadingSurfaceSettingsPanel\({' \
  "Shared Reading system Sheet must own the common appearance, text, and settings panel assembly."
check_file_contains_rule "${HOME_PAGE_SETTINGS_SHEET}" "${HOME_PAGE_SETTINGS_SHEET_REL}" \
  'BrowserPhoneSettingsSheetHeader\({' \
  "Home Page Settings must retain the standard phone settings Sheet header."
check_file_contains_rule "${PHONE_SETTINGS_SHEET_HEADER}" "${PHONE_SETTINGS_SHEET_HEADER_REL}" \
  'fontSize\(21\)' \
  "The standard phone settings Sheet header must retain the established title typography."
check_file_contains_rule "${READING_EXPERIENCE_SYSTEM_SHEET}" "${READING_EXPERIENCE_SYSTEM_SHEET_REL}" \
  'resolveReadingExperienceSystemSheetTitle' \
  "Shared Reading system Sheets must expose their titles through native Sheet options."
check_file_not_contains_rule "${READING_EXPERIENCE_SYSTEM_SHEET}" "${READING_EXPERIENCE_SYSTEM_SHEET_REL}" \
  'BrowserPhoneSettingsSheetHeader\({' \
  "Reading Sheet content must not draw a second title below the native Sheet header."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'title:[[:space:]]*resolveReadingExperienceSystemSheetTitle' \
  "BrowserShell must pass Reading titles to the root native Sheet host."
check_file_contains_rule "${READING_EXPERIENCE_SYSTEM_SHEET}" "${READING_EXPERIENCE_SYSTEM_SHEET_REL}" \
  'SettingsSwitchRow\({' \
  "Novel Reading settings must reuse standard settings switch rows."
check_file_not_contains_rule "${READING_EXPERIENCE_SYSTEM_SHEET}" "${READING_EXPERIENCE_SYSTEM_SHEET_REL}" \
  "type:[[:space:]]*'update_preferences'" \
  "Reading system Sheets must emit semantic actions instead of owning preference mutation policy."
check_file_contains_rule "${READING_SURFACE_SETTINGS_PANEL}" "${READING_SURFACE_SETTINGS_PANEL_REL}" \
  'SettingsOptionRow\({' \
  "Reading page-mode choices must reuse standard settings option rows and system Radio controls."
check_file_contains_rule "${READING_SURFACE_SETTINGS_PANEL}" "${READING_SURFACE_SETTINGS_PANEL_REL}" \
  'trackThickness\(READING_SETTINGS_SLIDER_TRACK_THICKNESS\)' \
  "Reading brightness must retain the thick settings-style Slider geometry."
check_file_contains_rule "${READING_EXPERIENCE_SYSTEM_SHEET}" "${READING_EXPERIENCE_SYSTEM_SHEET_REL}" \
  'Math.max\(20, Math.ceil\(this.bottomSafeInsetVp\) \+ 12\)' \
  "Reading system Sheets must preserve a device-safe bottom interaction inset."
check_file_not_contains_rule "${READER_MODE_OVERLAY}" "${READER_MODE_OVERLAY_REL}" \
  'buildTopToolbar\(|buildDefaultTopBarContent\(|buildBottomControls\(|buildBottomNavItem\(|buildSharedSettingsPanel\(' \
  "Article Reading must not restore its deleted legacy toolbar, bottom controls, or settings assembly."
check_file_not_contains_rule "${READER_MODE_OVERLAY}" "${READER_MODE_OVERLAY_REL}" \
  'syncSearchTarget|lastSearchTargetKey|shouldScrollToSearchTarget' \
  "Article Reading must not restore the obsolete Overlay-owned search scroll path."
check_file_not_contains_rule "${READER_MODE_COORDINATOR}" "${READER_MODE_COORDINATOR_REL}" \
  'legacyProgressByUrl|ReaderModeProgressState|recordProgress\(|readingAnchor|readingAnchorsByUrl|recordReadingAnchor|reconcileReadingAnchor|normalizeReadingAnchor' \
  "Article Reading must not retain cross-session position or restore progress through Session snapshots."
check_file_not_contains_rule "${READER_MODE_MODELS}" "${READER_MODE_MODELS_REL}" \
  'reading_anchor_change' \
  "Article Reading actions must not turn live Surface progress into a Session navigation channel."
check_file_contains_rule "${READING_SURFACE}" "${READING_SURFACE_REL}" \
  '@Prop initialAnchor: ReadingAnchor' \
  "Shared Reading Surface must expose initial restore as a one-way mount input."
check_file_not_contains_rule "${READING_SURFACE}" "${READING_SURFACE_REL}" \
  "@Watch\\('onAnchorChanged'\\)|onAnchorChanged\\(" \
  "Shared Reading Surface must not reinterpret reported progress echoes as restore commands."
check_file_not_contains_rule "${READING_SURFACE_MODELS}" "${READING_SURFACE_MODELS_REL}" \
  "ReadingSurfaceScrollAction|type:[[:space:]]*'scroll'" \
  "Shared Reading Surface actions must not expose frame-by-frame scroll deltas."
check_file_not_contains_rule "${READER_MODE_OVERLAY}" "${READER_MODE_OVERLAY_REL}" \
  "BrowserTopImmersionScrollCoordinator|handleReaderScroll|applyReaderStatusBarScroll|reader-scroll" \
  "Article Reading must use shared explicit Chrome visibility instead of Web-page scroll immersion."
check_file_not_contains_rule "${READER_MODE_OVERLAY}" "${READER_MODE_OVERLAY_REL}" \
  'initialAnchor:' \
  "Article Reading must start each newly mounted session at the document beginning."
check_file_contains_rule "${NOVEL_READER_OVERLAY}" "${NOVEL_READER_OVERLAY_REL}" \
  'initialAnchor: this\.resolveReadingSurfaceAnchor\(\)' \
  "Novel Reading must retain explicit checkpoint-to-initial-anchor restoration."
check_file_not_contains_rule "${READER_MODE_MODELS}" "${READER_MODE_MODELS_REL}" \
  "progress_change|decrease_font|increase_font|cycle_theme|cycle_line_height|cycle_page_width" \
  "Article Reading actions must not restore legacy renderer-control commands."
check_file_not_contains_rule "${NOVEL_READER_OVERLAY}" "${NOVEL_READER_OVERLAY_REL}" \
  'buildTopBar\(|buildBottomBlock\(|buildNavBar\(|buildNavItem\(|buildSharedSettingsPanel\(' \
  "Novel text reading Chrome must remain behind the same shared owner used by Article Reading."
check_file_not_contains_rule "${READER_MODE_OVERLAY}" "${READER_MODE_OVERLAY_REL}" \
  'ReadingSurfaceSettingsPanel' \
  "Article Reading Overlay must not assemble the shared settings panel outside ReadingExperienceSystemSheet."
check_file_not_contains_rule "${NOVEL_READER_OVERLAY}" "${NOVEL_READER_OVERLAY_REL}" \
  'ReadingSurfaceSettingsPanel' \
  "Novel Reading Overlay must not assemble the shared settings panel outside ReadingExperienceSystemSheet."
check_file_contains_rule "${READING_SURFACE}" "${READING_SURFACE_REL}" \
  'ReadingDocumentPaginator' \
  "Shared Reading Surface must retain one rich-document pagination implementation."
check_file_contains_rule "${READING_THEME_TOKEN_RESOLVER}" "${READING_THEME_TOKEN_RESOLVER_REL}" \
  'resolveReadingThemeTokens' \
  "Shared Reading presentation must keep one theme-token resolver."
check_file_contains_rule "${READER_MODE_OVERLAY}" "${READER_MODE_OVERLAY_REL}" \
  'resolveReadingThemeTokens' \
  "Article-specific reading presentation must consume the shared Reading theme-token resolver."
check_file_contains_rule "${NOVEL_READER_OVERLAY}" "${NOVEL_READER_OVERLAY_REL}" \
  'resolveReadingThemeTokens' \
  "Novel-specific reading presentation must consume the shared Reading theme-token resolver."
check_file_contains_rule "${READING_SURFACE}" "${READING_SURFACE_REL}" \
  'resolveReadingThemeTokens' \
  "Shared Reading Surface must consume the shared Reading theme-token resolver."
check_file_contains_rule "${READING_EXPERIENCE_CHROME}" "${READING_EXPERIENCE_CHROME_REL}" \
  'resolveReadingThemeTokens' \
  "Shared Reading Chrome must consume the shared Reading theme-token resolver."
check_file_not_contains_rule "${READER_MODE_OVERLAY}" "${READER_MODE_OVERLAY_REL}" \
  'topActions:[[:space:]]*this\.' \
  "Article Reading must wrap parent-owned BuilderParam content in a lexical-this arrow builder."
check_file_not_contains_rule "${NOVEL_READER_OVERLAY}" "${NOVEL_READER_OVERLAY_REL}" \
  'contextRow:[[:space:]]*this\.|settingsExtension:[[:space:]]*this\.' \
  "Novel Reading must wrap parent-owned BuilderParam content in lexical-this arrow builders."
article_reading_chrome_passthrough_count="$(awk '
  /ReadingExperienceChrome\(\{/ { in_chrome = 1; next }
  in_chrome && /\.hitTestBehavior\(HitTestMode.None\)/ { count += 1; in_chrome = 0 }
  in_chrome && /\.zIndex\(/ { in_chrome = 0 }
  END { print count + 0 }
' "${READER_MODE_OVERLAY}")"
if [ "${article_reading_chrome_passthrough_count}" -ne 1 ]; then
  report_failure "${READER_MODE_OVERLAY_REL} shared Chrome host must pass body gestures through with HitTestMode.None."
fi
novel_reading_chrome_passthrough_count="$(awk '
  /ReadingExperienceChrome\(\{/ { in_chrome = 1; next }
  in_chrome && /\.hitTestBehavior\(HitTestMode.None\)/ { count += 1; in_chrome = 0 }
  in_chrome && /\.align\(/ { in_chrome = 0 }
  END { print count + 0 }
' "${NOVEL_READER_OVERLAY}")"
if [ "${novel_reading_chrome_passthrough_count}" -ne 1 ]; then
  report_failure "${NOVEL_READER_OVERLAY_REL} shared Chrome host must pass body gestures through with HitTestMode.None."
fi
if [ -e "${OLD_NOVEL_PAGINATOR}" ]; then
  report_failure "${OLD_NOVEL_PAGINATOR_REL} must stay deleted; pagination belongs to the shared Reading Surface."
fi
if [ -e "${OLD_NOVEL_PAGINATION_MODELS}" ]; then
  report_failure "${OLD_NOVEL_PAGINATION_MODELS_REL} must stay deleted; page models belong to the shared Reading Surface."
fi
check_file_contains_rule "${MAIN_BACK_COORDINATOR}" "${MAIN_BACK_COORDINATOR_REL}" \
  "case 'dismiss_novel_reader_panel':" \
  "Novel Reading Back must dismiss its local reading panel before exit confirmation."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private (handleReaderModeEffect|buildReaderBookmarkActionTarget|openReaderModeLink|closeReaderSpeechPlayer|resetReaderSpeechPlayerPresentation)\(' \
  "BrowserShellPage must not regain Reader fixed-action or transient-surface effect interpretation."
reader_mode_application_shell_callback_count="$(awk '
  /export interface ReaderModeApplicationShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${READER_MODE_APPLICATION}")"
if [ "${reader_mode_application_shell_callback_count}" -ne 8 ]; then
  report_failure "${READER_MODE_APPLICATION_REL} Shell must keep exactly eight live-fact/UI/platform callbacks; found ${reader_mode_application_shell_callback_count}."
fi
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State readerModeSessionSnapshot: ReaderModeSessionSnapshot' \
  "BrowserShellPage must observe one explicit Reader Mode Session snapshot."
check_file_contains_rule "${OFFLINE_PAGE_VIEWER}" "${OFFLINE_PAGE_VIEWER_REL}" \
  '@State readerModeSessionSnapshot: ReaderModeSessionSnapshot' \
  "OfflinePageViewerScreen must observe the same explicit Reader Mode Session snapshot contract."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State readerModeState:|@State readerSpeechState:|@State readerSpeechChunks:|@State readerSpeechSpeed:|@State readerSpeechVoiceOptions:|@State selectedReaderSpeechVoiceId:|@State readerSpeechVoiceLabel:|@State readerSpeechVoiceDialogTheme:|@State readerSpeechVoiceDialogLoading:|@State readerSpeechVoiceDialogErrorMessage:|@State readerModeOverlayBackState:' \
  "BrowserShellPage must not regain per-field Reader/Speech Session mirrors."
check_file_not_contains_rule "${OFFLINE_PAGE_VIEWER}" "${OFFLINE_PAGE_VIEWER_REL}" \
  '@State readerModeState:|@State readerSpeechState:|@State readerSpeechChunks:|@State readerSpeechSpeed:|@State readerSpeechVoiceOptions:|@State selectedReaderSpeechVoiceId:|@State readerSpeechVoiceLabel:|@State readerSpeechVoiceDialogTheme:|@State readerSpeechVoiceDialogLoading:|@State readerSpeechVoiceDialogErrorMessage:|@State readerModeOverlayBackState:' \
  "OfflinePageViewerScreen must not duplicate the canonical Reader/Speech Session snapshot."
check_file_contains_rule "${READER_SPEECH_VOICE_DIALOG}" "${READER_SPEECH_VOICE_DIALOG_REL}" \
  '@Link presentation: ReaderModeSpeechVoiceDialogPresentation' \
  "Reader speech voice dialog must keep one explicit object-valued CustomDialog binding."
check_file_not_contains_rule "${READER_SPEECH_VOICE_DIALOG}" "${READER_SPEECH_VOICE_DIALOG_REL}" \
  '@Link readerTheme:|@Link selectedVoiceId:|@Link options:|@Link loading:|@Link errorMessage:' \
  "Reader speech voice dialog must not regain five parallel Link fields."
check_file_contains_rule "${OFFLINE_PAGE_SAVE_COORDINATOR}" "${OFFLINE_PAGE_SAVE_COORDINATOR_REL}" \
  'private async runSave\(' \
  "Offline Page Save must keep membership, save, usage, and prompt ordering behind one narrative owner."
check_file_contains_rule "${OFFLINE_PAGE_SAVE_COORDINATOR}" "${OFFLINE_PAGE_SAVE_COORDINATOR_REL}" \
  'startPendingLinkSave\(tabId: string\)' \
  "Offline Page Save must preserve the requested link tab through load-finished handoff."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State offlinePageSaveSessionSnapshot: OfflinePageSaveSessionSnapshot' \
  "BrowserShellPage must observe one explicit Offline Page Save Session snapshot."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'offlinePageSaveShell: OfflinePageSaveCoordinatorShell' \
  "BrowserShellPage must expose one typed Offline Page Save context/UI-effect shell."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'OfflinePageSaveCoordinatorHost|offlinePageSaveHost|offlineSaveActionPromptVisible|offlineSaveActionPromptMessage|offlineSaveActionPromptTitle|offlineSaveActionPromptUrl|offlineSaveActionPromptIconUri|offlineSaveActionPromptFavicon|offlineSaveActionPromptTimer|private saveActiveOfflinePage\(|private saveActiveOfflinePageWithMembershipGate\(|private showOfflineSaveActionPrompt\(|private hideOfflineSaveActionPrompt\(|private clearOfflineSaveActionPromptTimer\(' \
  "BrowserShellPage must not regain Offline Save state mirrors, timer, membership/save ordering, or the old wide Host."
check_file_not_contains_rule "${OFFLINE_PAGE_SAVE_COORDINATOR}" "${OFFLINE_PAGE_SAVE_COORDINATOR_REL}" \
  'OfflinePageSaveCoordinatorHost|OfflinePageSaveMenuState|buildActiveMenuState\(|canSaveActivePage\(' \
  "Offline Page Save must not regain its unused menu interface or split getter Host."
check_file_contains_rule "${OFFLINE_PAGE_OPEN_COORDINATOR}" "${OFFLINE_PAGE_OPEN_COORDINATOR_REL}" \
  'async open\(pageId: string, dataScope: string, privacyMode: string\)' \
  "Offline Page Open must require the current privacy boundary at its execution seam."
check_file_contains_rule "${OFFLINE_PAGE_OPEN_COORDINATOR}" "${OFFLINE_PAGE_OPEN_COORDINATOR_REL}" \
  "intent: 'regular_profile_management_read'" \
  "Offline Page Open must enforce regular-profile read policy before repository or file access."
check_file_contains_rule "${OFFLINE_PAGE_LINK_ACTION_SERVICE}" "${OFFLINE_PAGE_LINK_ACTION_SERVICE_REL}" \
  "intent: 'regular_profile_management_share'" \
  "Offline Page copy/share must enforce regular-profile share policy at the clipboard/share seam."
check_file_not_contains_rule "${OFFLINE_PAGES_SCREEN}" "${OFFLINE_PAGES_SCREEN_REL}" \
  'canShare\(' \
  "Offline Pages UI must not duplicate the copy/share execution policy."
check_file_not_contains_rule "${OFFLINE_PAGE_VIEWER}" "${OFFLINE_PAGE_VIEWER_REL}" \
  'canShare\(' \
  "Offline Page Viewer UI must not duplicate the copy/share execution policy."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'saveActiveOfflinePage: \(\) => void|host\.saveActiveOfflinePage\(' \
  "Web Page Lifecycle must hand pending-link save directly to the Offline Page Save owner."
check_file_contains_rule "${BOOKMARK_ACTION_COORDINATOR}" "${BOOKMARK_ACTION_COORDINATOR_REL}" \
  'private async addBookmark\(' \
  "Bookmark Action must keep add/private-write/Home Shortcut sequencing behind one narrative owner."
check_file_contains_rule "${BOOKMARK_ACTION_COORDINATOR}" "${BOOKMARK_ACTION_COORDINATOR_REL}" \
  'private async prepareFolderOptions\(' \
  "Bookmark Action must keep Folder Selection preparation behind the same Session owner."
check_file_contains_rule "${BOOKMARK_MANAGEMENT_FEATURE}" "${BOOKMARK_MANAGEMENT_FEATURE_REL}" \
  'applyImportPlan\(plan, this\.requireScope\(\),' \
  "Bookmark HTML import must pass the currently labelled management scope to its mutation seam."
check_file_contains_rule "${BOOKMARK_MUTATION_SERVICE}" "${BOOKMARK_MUTATION_SERVICE_REL}" \
  'scope: BookmarkStorageScope' \
  "Bookmark import mutation must require an explicit target scope."
check_file_not_contains_rule "${BOOKMARK_MUTATION_SERVICE}" "${BOOKMARK_MUTATION_SERVICE_REL}" \
  "createLocalBookmarkId\(type, 'regular'\)" \
  "Bookmark import must not silently redirect private-scope nodes into regular Bookmarks."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State browserBookmarkActionSessionSnapshot: BrowserBookmarkActionSessionSnapshot' \
  "BrowserShellPage must observe one explicit Bookmark Action Session snapshot."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserBookmarkActionShell: BrowserBookmarkActionShell' \
  "BrowserShellPage must expose one narrow Bookmark Action UI/platform shell."
check_file_contains_rule "${BOOKMARK_FOLDER_SELECTION_COMPONENT}" "${BOOKMARK_FOLDER_SELECTION_COMPONENT_REL}" \
  'export struct BookmarkMoveFolderSelectionOverlay' \
  "Bookmark Folder Selection must keep Overlay plus Sheet composition in its feature component."
check_file_contains_rule "${BOOKMARK_ACTION_COORDINATOR}" "${BOOKMARK_ACTION_COORDINATOR_REL}" \
  'handleFolderSelectionAction\(action: BrowserBookmarkFolderSelectionAction\)' \
  "Bookmark Folder Selection actions must enter through one typed owner action."
check_file_contains_rule "${BOOKMARK_FOLDER_SELECTION_COMPONENT}" "${BOOKMARK_FOLDER_SELECTION_COMPONENT_REL}" \
  'onAction: \(action: BrowserBookmarkFolderSelectionAction\)' \
  "Bookmark Folder Selection Overlay must emit one typed action callback."
check_file_contains_rule "${READER_SPEECH_PLAYER_COMPONENT}" "${READER_SPEECH_PLAYER_COMPONENT_REL}" \
  'export struct ReaderSpeechPlayerOverlay' \
  "Reader Speech must keep Overlay plus Sheet composition in its feature component."
check_file_contains_rule "${READER_MODE_COORDINATOR}" "${READER_MODE_COORDINATOR_REL}" \
  'handleSpeechPlayerAction\(action: ReaderSpeechPlayerAction, openVoicePicker: \(\) => void\)' \
  "Reader Speech Overlay actions must enter through the Reader Mode owner."
check_file_contains_rule "${READER_SPEECH_PLAYER_COMPONENT}" "${READER_SPEECH_PLAYER_COMPONENT_REL}" \
  'onAction: \(action: ReaderSpeechPlayerAction\)' \
  "Reader Speech Overlay must emit one typed action callback."
check_file_contains_rule "${TRANSLATION_TARGET_LANGUAGE_COMPONENT}" "${TRANSLATION_TARGET_LANGUAGE_COMPONENT_REL}" \
  'export struct WebpageTranslationTargetLanguageOverlay' \
  "Translation Target Language must keep Overlay plus Sheet composition in its feature component."
check_file_contains_rule "${WEBPAGE_TRANSLATION_COORDINATOR}" "${WEBPAGE_TRANSLATION_COORDINATOR_REL}" \
  'handleTargetLanguageAction\(action: WebpageTranslationTargetLanguageAction\)' \
  "Translation Target Language actions must enter through one typed owner action."
check_file_contains_rule "${TRANSLATION_TARGET_LANGUAGE_COMPONENT}" "${TRANSLATION_TARGET_LANGUAGE_COMPONENT_REL}" \
  'onAction: \(action: WebpageTranslationTargetLanguageAction\)' \
  "Translation Target Language Overlay must emit one typed action callback."
check_file_contains_rule "${USER_SCRIPT_INSTALL_SHEET}" "${USER_SCRIPT_INSTALL_SHEET_REL}" \
  'export struct UserScriptInstallSheetContent' \
  "UserScript Install must keep reusable system Sheet content in its feature component."
check_file_contains_rule "${USER_SCRIPT_PAGE_ACTIONS_SHEET}" "${USER_SCRIPT_PAGE_ACTIONS_SHEET_REL}" \
  'export struct UserScriptPageActionsSheet' \
  "UserScript Page Actions must expose reusable content for the shared system Sheet host."
check_file_contains_rule "${DOWNLOAD_CONFIRM_COMPONENT}" "${DOWNLOAD_CONFIRM_COMPONENT_REL}" \
  'export struct BrowserDownloadConfirmOverlay' \
  "Download Confirm must keep Overlay plus Sheet composition in its feature component."
check_file_contains_rule "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR}" "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR_REL}" \
  'handleAction\(action: BrowserDownloadConfirmOverlayAction\)' \
  "Download Confirm Overlay actions must enter through one typed owner action."
check_file_contains_rule "${DOWNLOAD_CONFIRM_COMPONENT}" "${DOWNLOAD_CONFIRM_COMPONENT_REL}" \
  'onAction: \(action: BrowserDownloadConfirmOverlayAction\)' \
  "Download Confirm Overlay must emit one typed action callback."
check_file_contains_rule "${MEDIA_RESOURCES_COMPONENT}" "${MEDIA_RESOURCES_COMPONENT_REL}" \
  'export struct BrowserMediaResourcesSheet' \
  "Media Resources must expose reusable content for the shared system Sheet host."
check_file_contains_rule "${MEDIA_RESOURCE_SESSION_COORDINATOR}" "${MEDIA_RESOURCE_SESSION_COORDINATOR_REL}" \
  'handleResourcesOverlayAction\(action: BrowserMediaResourcesOverlayAction\)' \
  "Media Resources Overlay actions must enter through one typed owner action."
check_file_contains_rule "${TOOLBAR_SYSTEM_SHEET_CONTENT}" "${TOOLBAR_SYSTEM_SHEET_CONTENT_REL}" \
  'onMediaResourceAction: \(action: BrowserMediaResourcesOverlayAction\)' \
  "Shared toolbar system Sheet content must emit one typed Media Resources action callback."
check_file_contains_rule "${APP_PROXY_QUICK_COORDINATOR}" "${APP_PROXY_QUICK_COORDINATOR_REL}" \
  'handleAction\(action: AppProxyQuickSheetAction\)' \
  "App Proxy Quick Overlay actions must enter through one typed owner action."
check_file_contains_rule "${TOOLBAR_SYSTEM_SHEET_CONTENT}" "${TOOLBAR_SYSTEM_SHEET_CONTENT_REL}" \
  'onAppProxyAction: \(action: AppProxyQuickSheetAction\)' \
  "Shared toolbar system Sheet content must emit one typed App Proxy Quick action callback."
check_file_contains_rule "${QR_SCAN_COORDINATOR}" "${QR_SCAN_COORDINATOR_REL}" \
  'handleWifiResultAction\(action: BrowserWifiQrResultAction\)' \
  "Wi-Fi QR Result actions must enter through the QR Scan owner."
check_file_contains_rule "${WIFI_QR_RESULT_COMPONENT}" "${WIFI_QR_RESULT_COMPONENT_REL}" \
  'onAction: \(action: BrowserWifiQrResultAction\)' \
  "Wi-Fi QR Result Overlay must emit one typed action callback."
check_file_contains_rule "${HLS_TAKEOVER_COMPONENT}" "${HLS_TAKEOVER_COMPONENT_REL}" \
  'export struct BrowserHlsTakeoverOverlay' \
  "HLS Takeover must keep Overlay plus Sheet composition in its feature component."
check_file_contains_rule "${MEDIA_RESOURCE_SESSION_COORDINATOR}" "${MEDIA_RESOURCE_SESSION_COORDINATOR_REL}" \
  'handleHlsTakeoverAction\(action: BrowserHlsTakeoverAction\)' \
  "HLS Takeover actions must enter through one typed Media Resource Session action."
check_file_contains_rule "${HLS_TAKEOVER_COMPONENT}" "${HLS_TAKEOVER_COMPONENT_REL}" \
  'onAction: \(action: BrowserHlsTakeoverAction\)' \
  "HLS Takeover Overlay must emit one typed action callback."
check_file_contains_rule "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR}" \
  "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR_REL}" \
  'handleSelectionAction\(action: ManualElementHideSelectionAction\)' \
  "Manual Element Hide selection actions must enter through one typed owner action."
check_file_contains_rule "${MANUAL_ELEMENT_HIDE_SELECTION_COMPONENT}" \
  "${MANUAL_ELEMENT_HIDE_SELECTION_COMPONENT_REL}" \
  'onAction: \(action: ManualElementHideSelectionAction\)' \
  "Manual Element Hide selection Overlay must emit one typed action callback."
check_file_contains_rule "${QR_SCAN_COORDINATOR}" "${QR_SCAN_COORDINATOR_REL}" \
  'handleDesktopLoginConfirmAction\(action: BrowserDesktopLoginConfirmAction\)' \
  "Desktop Login confirmation actions must enter through the QR Scan owner."
check_file_contains_rule "${DESKTOP_LOGIN_CONFIRM_COMPONENT}" "${DESKTOP_LOGIN_CONFIRM_COMPONENT_REL}" \
  'onAction: \(action: BrowserDesktopLoginConfirmAction\)' \
  "Desktop Login confirmation Sheet must emit one typed action callback."
check_file_not_contains_rule "${DESKTOP_LOGIN_CONFIRM_COMPONENT}" "${DESKTOP_LOGIN_CONFIRM_COMPONENT_REL}" \
  'onCancel: \(\) => void|onConfirm: \(\) => void' \
  "Desktop Login confirmation Sheet must not regain peer cancel/confirm callbacks."
check_file_contains_rule "${WEB_TEXT_ZOOM_VIEW_MODEL}" "${WEB_TEXT_ZOOM_VIEW_MODEL_REL}" \
  'buildActionResult\(currentRatio: number, action: BrowserWebTextZoomAction\)' \
  "Web Text Zoom actions must enter through one typed ViewModel action."
check_file_contains_rule "${WEB_TEXT_ZOOM_COMPONENT}" "${WEB_TEXT_ZOOM_COMPONENT_REL}" \
  'onAction: \(action: BrowserWebTextZoomAction\)' \
  "Web Text Zoom Sheet must emit one typed action callback."
check_file_not_contains_rule "${WEB_TEXT_ZOOM_COMPONENT}" "${WEB_TEXT_ZOOM_COMPONENT_REL}" \
  'onDecrease|onIncrease|onReset' \
  "Web Text Zoom Sheet must not regain peer zoom callbacks."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_COORDINATOR}" "${WEB_LINK_CONTEXT_MENU_COORDINATOR_REL}" \
  'handleOverlayAction\(action: WebContextMenuOverlayAction, facts: WebContextMenuSessionFacts\)' \
  "Web Context Menu Overlay actions must enter through one typed owner action."
check_file_contains_rule "${WEB_CONTEXT_MENU_OVERLAY}" "${WEB_CONTEXT_MENU_OVERLAY_REL}" \
  'onAction: \(action: WebContextMenuOverlayAction\)' \
  "Web Context Menu Overlay must emit one typed action callback."
check_file_not_contains_rule "${WEB_CONTEXT_MENU_OVERLAY}" "${WEB_CONTEXT_MENU_OVERLAY_REL}" \
  'onMeasured:|onDismiss:' \
  "Web Context Menu Overlay must not regain peer measurement/dismiss callbacks."
check_file_contains_rule "${WEB_CONTEXT_MENU_OVERLAY}" "${WEB_CONTEXT_MENU_OVERLAY_REL}" \
  'return this\.isLargeScreenMenu\(\) \? 0 : WEB_CONTEXT_MENU_PHONE_BACKDROP_BLUR_RADIUS' \
  "Desktop Web Context Menu must resolve to zero webpage blur while preserving the phone presentation."
check_file_contains_rule "${WEB_CONTEXT_MENU_OVERLAY}" "${WEB_CONTEXT_MENU_OVERLAY_REL}" \
  "BrowserWindowRuntime\.resolveActiveShellPresentationSurface\(\) === 'large_screen'" \
  "Web Context Menu material must follow the locked Window Session shell family."
check_file_contains_rule "${WEB_CONTEXT_MENU_OVERLAY}" "${WEB_CONTEXT_MENU_OVERLAY_REL}" \
  '\.hitTestBehavior\(HitTestMode\.Block\)' \
  "Web Context Menu outside-dismiss layer must block lower ArkWeb pointer targets."
check_file_contains_rule "${WEB_CONTEXT_MENU_OVERLAY}" "${WEB_CONTEXT_MENU_OVERLAY_REL}" \
  'event\.stopPropagation\(\)' \
  "Web Context Menu surface and rows must consume pointer events before ArkWeb can receive them."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private (buildBookmarkFolderSelectionSheet|buildBookmarkFolderSelectionOverlay|buildAppProxyQuickSheet|buildAppProxyQuickOverlay|buildReaderSpeechPlayerOverlay|buildWebpageTranslationTargetLanguageSheet|buildWebpageTranslationTargetLanguageOverlay|buildUserScriptInstallSheet|buildUserScriptInstallOverlay|buildUserScriptPageActionsSheet|buildUserScriptPageActionsOverlay|buildDownloadConfirmSheet|buildDownloadConfirmOverlay|buildMediaResourcesSheet|buildMediaResourcesOverlay|buildHlsTakeoverSheet|buildHlsTakeoverOverlay)\(' \
  "BrowserShellPage must mount feature-owned modal overlays without local Sheet/Overlay wrapper Builders."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserBookmarkActionCoordinator\.(setAddToHome|previewFolder|dismiss|confirmAdd)|browserDownloadConfirmOverlayCoordinator\.(confirm|cancel)\(|browserMediaResourceSessionCoordinator\.(closeResources|handleResourceAction)\(|browserQrScanCoordinator\.copyWifiPassword\(|readerModeCoordinator\.(dismissSpeechPlayerPresentation|toggleSpeech|playPreviousSpeechChunk|playNextSpeechChunk|replayCurrentSpeechChunk|locateSpeechChunkInReader|changeSpeechSpeed)\(' \
  "BrowserShellPage must forward feature Overlay actions instead of regaining peer action routing."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'manualElementHideRuntimeCoordinator\.(cancelSelectionSession|finishSelectionSession)\(|browserQrScanCoordinator\.confirmDesktopLogin\(|browserMediaResourceSessionCoordinator\.(closeHlsTakeover|parseHlsTakeoverTarget|copyHlsTakeoverUrl|copyHlsTakeoverContext|openResourcesFromHlsTakeover)\(|webContextMenuCoordinator\.(measure|select)\(|private movePageFind\(' \
  "BrowserShellPage must forward compact browser surface actions through their typed owner entries."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserBookmarkActionViewModel|this\.bookmarkActionVersion|@State bookmarkActionVersion|bookmarkMutationService|bookmarkScopeService|bookmarksFeature|privateBookmarksFeature|bookmarkAddDialog|pendingBookmarkAdd|bookmarkFolderSelectionPreparing|bookmarkFolderSelectionOptions|private addBookmarkForTarget|private openBookmarkAddDialog|private prepareBookmarkFolderSelection' \
  "BrowserShellPage must not regain Bookmark mutation, scope, Folder Selection, or parallel Session ownership."
if [ -e "${OLD_BOOKMARK_ACTION_VIEW_MODEL}" ]; then
  report_failure "${OLD_BOOKMARK_ACTION_VIEW_MODEL_REL} must stay deleted; Bookmark action presentation is subordinate to the Action Session owner."
fi
check_file_contains_rule "${ADDRESS_SUBMISSION_COORDINATOR}" "${ADDRESS_SUBMISSION_COORDINATOR_REL}" \
  'resolveSessionFacts: \(\) => BrowserAddressSubmissionSessionFacts' \
  "Address Submission must resolve variable shell facts behind one narrow Session seam."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserAddressSubmissionShell: BrowserAddressSubmissionShell' \
  "BrowserShellPage must expose one narrow Address Submission shell."
check_file_not_contains_rule "${ADDRESS_SUBMISSION_COORDINATOR}" "${ADDRESS_SUBMISSION_COORDINATOR_REL}" \
  'BrowserAddressSubmissionShellAdapter|BrowserAddressSubmissionShellBindings|immediateFeedback|applyImmediateFeedback' \
  "Address Submission must not regain the single-caller adapter or duplicate immediate navigation feedback path."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserAddressSubmissionShellAdapter|browserAddressSubmissionShellAdapter|applyAddressSubmitImmediateFeedback|submitRootBottomExternalAppSearch' \
  "BrowserShellPage must not regain the Address Submission adapter, duplicate feedback mutation, or external-search request construction."
check_file_not_contains_rule "${ERROR_DOCUMENT_LOAD_COORDINATOR}" "${ERROR_DOCUMENT_LOAD_COORDINATOR_REL}" \
  'applyAddressSubmitImmediateFeedback' \
  "error-document fallback search must use the canonical App URL Open state transition instead of duplicate page feedback."
check_file_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'private readonly errorDocumentLoadCoordinator: BrowserErrorDocumentLoadCoordinator' \
  "Ordinary Web Page Lifecycle must own the subordinate error-document implementation."
check_file_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'handleErrorDocumentActionUrl\(tabId: string, targetUrl: string\)' \
  "error-document retry/settings actions must enter through the Web Page Lifecycle narrative owner."
check_file_contains_rule "${WEB_PAGE_LIFECYCLE_MODELS}" "${WEB_PAGE_LIFECYCLE_MODELS_REL}" \
  'interface BrowserWebPageLifecycleApplicationHost' \
  "Ordinary Web Page Lifecycle must keep one shared shell-facts and platform-effects contract."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'BrowserWebPagePresentationEventHost|BrowserWebPageFeatureEffectsHost' \
  "Ordinary Web Page Lifecycle must not regain subordinate peer Host interfaces."
check_file_not_contains_rule "${WEB_PAGE_PRESENTATION_EVENT_COORDINATOR}" \
  "${WEB_PAGE_PRESENTATION_EVENT_COORDINATOR_REL}" \
  'interface BrowserWebPagePresentationEventHost|recordRuntimeEvent' \
  "Web Page Presentation Events must consume the shared Lifecycle Host without restoring a parallel Host or diagnostic callback."
check_file_not_contains_rule "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR}" \
  "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR_REL}" \
  'interface BrowserWebPageFeatureEffectsHost' \
  "Web Page Feature Effects must consume the shared Lifecycle Host instead of a parallel Host interface."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_MODELS}" "${WEB_PAGE_LIFECYCLE_MODELS_REL}" \
  'updateTabById:' \
  "The Lifecycle Host must not route fixed tab mutation and persistence orchestration back through BrowserShell."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'host\.updateTabById|dependencies\.host\.updateTabById' \
  "Ordinary Web Page Lifecycle must apply tab patches through the tab-list owner and fixed runtime/persistence dependencies."
web_page_lifecycle_host_callback_count="$(awk '
  /export interface BrowserWebPageLifecycleApplicationHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${WEB_PAGE_LIFECYCLE_MODELS}")"
if [ "${web_page_lifecycle_host_callback_count}" -gt 16 ]; then
  report_failure "${WEB_PAGE_LIFECYCLE_MODELS_REL} must keep the Lifecycle Host at no more than 16 shell-facts/typed-state/platform-effect callbacks; found ${web_page_lifecycle_host_callback_count}."
fi
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_MODELS}" "${WEB_PAGE_LIFECYCLE_MODELS_REL}" \
  'recordRuntimeEvent:|appendRestoreTraceBreadcrumb:' \
  "Ordinary Web Page Lifecycle Host must not restore callbacks whose BrowserShell diagnostic receivers are empty."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'recordRuntimeEvent|runtimeEventType|runtimeEventMessage|appendRestoreTraceBreadcrumb' \
  "Ordinary Web Page Lifecycle must not rebuild removed runtime-event or Restore-breadcrumb diagnostics."
check_file_not_contains_rule "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR}" \
  "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR_REL}" \
  'recordRuntimeEvent|stringifyError\(' \
  "Web Page Feature Effects must keep AdBlock/UserScript execution without rebuilding diagnostic string emission."
check_file_not_contains_rule "${WEB_EVENT_COMMIT_COORDINATOR}" "${WEB_EVENT_COMMIT_COORDINATOR_REL}" \
  'runtimeEventType|runtimeEventMessage|runtimeEvents:|restoreTraceBreadcrumbs:|commitPageLoadSuccess|recordRuntimeEvent:' \
  "Ordinary Web Event commits must contain behavior/state only, not removed diagnostic collections or callbacks."
snapshot_runtime_event_field_count="$(grep -Ec 'runtimeEvent: BrowserWebRuntimeEventCommit;' \
  "${WEB_EVENT_COMMIT_COORDINATOR}" || true)"
if [ "${snapshot_runtime_event_field_count}" -ne 2 ]; then
  report_failure "${WEB_EVENT_COMMIT_COORDINATOR_REL} must preserve exactly two protected Snapshot persist/restore runtime-event fields; found ${snapshot_runtime_event_field_count}."
fi
check_file_not_contains_rule "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR}" \
  "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL}" \
  'recordRuntimeEvent|appendRestoreTraceBreadcrumb' \
  "Runtime Navigation Recovery must not rebuild page-forwarded diagnostic callbacks."
runtime_navigation_recovery_host_callback_count="$(awk '
  /export interface BrowserRuntimeNavigationRecoveryCoordinatorHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR}")"
if [ "${runtime_navigation_recovery_host_callback_count}" -ne 1 ]; then
  report_failure "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL} Host must keep exactly one current-facts callback; found ${runtime_navigation_recovery_host_callback_count}."
fi
runtime_navigation_recovery_dependency_resolver_count="$(awk '
  /export interface BrowserRuntimeNavigationRecoveryCoordinatorDependencies \{/ { in_dependencies = 1; next }
  in_dependencies && /^}/ { print count + 0; exit }
  in_dependencies && /: \(\) =>/ { count += 1 }
' "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR}")"
if [ "${runtime_navigation_recovery_dependency_resolver_count}" -ne 1 ]; then
  report_failure "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL} dependencies must keep exactly one lazy Lifecycle owner resolver; found ${runtime_navigation_recovery_dependency_resolver_count}."
fi
check_file_not_contains_rule "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR}" \
  "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL}" \
  'host\.applyActiveRetryState|host\.applyMainFrameLoadFailure' \
  "Runtime Navigation Recovery Host must delegate retry/failure sequencing to the fixed Lifecycle narrative owner."
check_file_contains_rule "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR}" \
  "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL}" \
  'runtimeLifecyclePort\.rememberCommittedNavigation\(' \
  "Runtime Navigation Recovery must remember navigation through the fixed Runtime Lifecycle owner."
check_file_contains_rule "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR}" \
  "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL}" \
  'downloadNavigationStateCoordinator\.sanitizeRuntimeNavigationState\(' \
  "Runtime Navigation Recovery must sanitize restored downloads through the fixed Download Navigation owner."
check_file_contains_rule "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR}" \
  "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL}" \
  'dependencies\.commitRetryTabPatch\(' \
  "Runtime Navigation Recovery must apply retry runtime state through the fixed Tab Switch owner."
check_file_not_contains_rule "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR}" \
  "${RUNTIME_NAVIGATION_RECOVERY_COORDINATOR_REL}" \
  '^  (resolveActiveTabId|resolveTab|applyTabRuntimePatch|resolveForcedCompatibilityHosts|prepareUserAgentForNavigation|rememberTabNavigation|markDownloadNavigationRestored|sanitizeDownloadRuntimeNavigationState):' \
  "Runtime Navigation Recovery Host must not regain fixed Tab, Runtime, Download, or UA callbacks."
check_file_not_contains_rule "${RUNTIME_NAVIGATION_RECOVERY_SERVICE}" \
  "${RUNTIME_NAVIGATION_RECOVERY_SERVICE_REL}" \
  'recordRuntimeEvent|appendRestoreTraceBreadcrumb|BrowserRuntimeNavigationReplaySource|recordReplayRequested|recordReplayResult' \
  "Runtime Navigation Recovery Service must keep retry/replay behavior without diagnostics-only request fields or helpers."
check_file_contains_rule "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR}" \
  "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR_REL}" \
  'colorSampler\.sample|dependencies\.colorSampler\.sample' \
  "Page Chrome Theme Sampling must own visual sampling execution and result application."
check_file_contains_rule "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR}" \
  "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR_REL}" \
  'clearTab\(tabId: string\): void' \
  "Page Chrome Theme Sampling must own Chrome state cleanup as part of the same application narrative."
page_chrome_theme_sampling_host_callback_count="$(awk '
  /export interface BrowserPageChromeThemeSamplingHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR}")"
if [ "${page_chrome_theme_sampling_host_callback_count}" -gt 5 ]; then
  report_failure "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR_REL} must keep the Sampling Host at no more than 5 facts/state/platform callbacks; found ${page_chrome_theme_sampling_host_callback_count}."
fi
check_file_not_contains_rule "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR}" \
  "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR_REL}" \
  'recordRuntimeEvent:|host\.recordRuntimeEvent|page_chrome_visual_top_sample' \
  "Page Chrome Theme Sampling must not restore the removed runtime-event seam."
check_file_not_contains_rule "${PAGE_CHROME_THEME_PROBE}" "${PAGE_CHROME_THEME_PROBE_REL}" \
  'recordRuntimeEvent:|host\.recordRuntimeEvent|page_chrome_theme_probe_failed|hasSignal' \
  "Page Chrome Theme Probe must return presentation data without rebuilding diagnostics-only fields."
check_file_not_contains_rule "${MEDIA_DISCOVERY_MODELS}" "${MEDIA_DISCOVERY_MODELS_REL}" \
  'recordRuntimeEvent:|stringifyError:|BrowserMediaDiscoveryManualResourceScanInput|source: string;' \
  "Media Discovery Host/input models must not restore removed runtime diagnostics or scan-source metadata."
check_file_not_contains_rule "${MEDIA_DISCOVERY_COORDINATOR}" "${MEDIA_DISCOVERY_COORDINATOR_REL}" \
  'host\.recordRuntimeEvent|host\.stringifyError|recordValidationResult\(|onProbeFailed:|media_deep_probe|media_candidate_validation|media_assistant_snapshot_(success|failed)' \
  "Media Discovery must retain real surface/validation behavior without rebuilding runtime-event emission."
if [ -e "${OLD_YOUTUBE_TAKEOVER_COORDINATOR}" ]; then
  report_failure "${OLD_YOUTUBE_TAKEOVER_COORDINATOR_REL} must stay deleted; the Profile Recipe is the sole site-specific YouTube acquisition authority."
fi
if [ -e "${OLD_NATIVE_MEDIA_CANDIDATE_PUBLISHER}" ]; then
  report_failure "${OLD_NATIVE_MEDIA_CANDIDATE_PUBLISHER_REL} must stay deleted; Profile reports publish through the shared Media Signal projection."
fi
if [ -e "${OLD_NATIVE_MEDIA_SIGNAL_ADAPTER}" ]; then
  report_failure "${OLD_NATIVE_MEDIA_SIGNAL_ADAPTER_REL} must stay deleted; the legacy publisher adapter must not return."
fi
if [ -e "${OLD_NATIVE_MEDIA_CANDIDATE_MODELS}" ]; then
  report_failure "${OLD_NATIVE_MEDIA_CANDIDATE_MODELS_REL} must stay deleted; site-specific publisher input models must not return."
fi
check_file_not_contains_rule "${MEDIA_DISCOVERY_COORDINATOR}" "${MEDIA_DISCOVERY_COORDINATOR_REL}" \
  'BrowserYoutubeTakeoverCoordinator|youtube(Profile)?Shadow|scheduleYoutube|observeYoutube|youtube_progressive|youtube_adaptive' \
  "Media Discovery must not restore the legacy YouTube authority or its shadow migration path."
check_file_contains_rule "${MEDIA_DISCOVERY_COORDINATOR}" "${MEDIA_DISCOVERY_COORDINATOR_REL}" \
  'acceptScheduledProfileAcquisitionReport' \
  "Media Discovery must accept current scheduled Profile reports through its production acquisition path."
check_file_contains_rule "${MEDIA_DISCOVERY_COORDINATOR}" "${MEDIA_DISCOVERY_COORDINATOR_REL}" \
  'projectProfileAcquisitionReport' \
  "Media Discovery must project Profile reports through the shared site-neutral Media Signal seam."
check_file_contains_rule "${MEDIA_DISCOVERY_COORDINATOR}" "${MEDIA_DISCOVERY_COORDINATOR_REL}" \
  'bumpValidationGeneration\(input\.capture\.tabId\)' \
  "Media Discovery must invalidate prior-route candidate validation when a semantic route advances."
check_file_contains_rule "${MEDIA_EVIDENCE_GRAPH}" "${MEDIA_EVIDENCE_GRAPH_REL}" \
  'state\.store\.clearTab\(state\.scope\.tabId\)' \
  "Media Evidence route epochs must clear route-scoped Resource candidates without site identity."
check_file_not_contains_rule "${MEDIA_DISCOVERY_RUNTIME_FACTORY}" "${MEDIA_DISCOVERY_RUNTIME_FACTORY_REL}" \
  'BrowserYoutubeTakeoverCoordinator|youtubeTakeoverCoordinator' \
  "Media Discovery runtime wiring must not restore the deleted peer YouTube coordinator."
check_file_not_contains_rule "${MEDIA_CANDIDATE_MODELS}" "${MEDIA_CANDIDATE_MODELS_REL}" \
  'youtube_progressive|youtube_adaptive' \
  "Generic Media Candidate kinds must remain site-neutral."
check_file_not_contains_rule "${PROFILE_ACQUISITION_RECIPE_SERVICE}" "${PROFILE_ACQUISITION_RECIPE_SERVICE_REL}" \
  'VideoCompatibilityAcquisitionShadowComparator|legacy_shadow' \
  "The YouTube Recipe must not restore its removed legacy shadow comparator."
check_file_contains_rule "${YOUTUBE_EXTRACTOR_SERVICE}" "${YOUTUBE_EXTRACTOR_SERVICE_REL}" \
  'suppressDiagnostics: boolean' \
  "YouTube Extractor must require the caller's diagnostic-suppression fact without disabling extraction."
check_file_contains_rule "${YOUTUBE_EXTRACTOR_SERVICE}" "${YOUTUBE_EXTRACTOR_SERVICE_REL}" \
  'fetchPlan\(probe, pageUrl, videoId, suppressDiagnostics\)' \
  "YouTube Extractor must propagate diagnostic suppression into Innertube fallback."
youtube_extractor_hilog_count="$(grep -Ec 'hilog\.(debug|info|warn|error|fatal)' \
  "${YOUTUBE_EXTRACTOR_SERVICE}" || true)"
youtube_extractor_diagnostic_guard_count="$(grep -Ec 'this\.runDiagnostics\(suppressDiagnostics' \
  "${YOUTUBE_EXTRACTOR_SERVICE}" || true)"
if [ "${youtube_extractor_hilog_count}" -ne "${youtube_extractor_diagnostic_guard_count}" ]; then
  report_failure "${YOUTUBE_EXTRACTOR_SERVICE_REL} must route every diagnostic write through private-session suppression."
fi
check_file_contains_rule "${YOUTUBE_INNERTUBE_PLAYER_SERVICE}" "${YOUTUBE_INNERTUBE_PLAYER_SERVICE_REL}" \
  'suppressDiagnostics: boolean' \
  "YouTube Innertube must require diagnostic suppression through its request/proxy chain."
youtube_innertube_hilog_count="$(grep -Ec 'hilog\.(debug|info|warn|error|fatal)' \
  "${YOUTUBE_INNERTUBE_PLAYER_SERVICE}" || true)"
youtube_innertube_diagnostic_guard_count="$(grep -Ec 'this\.runDiagnostics\(suppressDiagnostics' \
  "${YOUTUBE_INNERTUBE_PLAYER_SERVICE}" || true)"
if [ "${youtube_innertube_hilog_count}" -ne "${youtube_innertube_diagnostic_guard_count}" ]; then
  report_failure "${YOUTUBE_INNERTUBE_PLAYER_SERVICE_REL} must route every player/proxy diagnostic through private-session suppression."
fi
check_file_contains_rule "${ARK_WEB_MEDIA_TAKEOVER_COORDINATOR}" "${ARK_WEB_MEDIA_TAKEOVER_COORDINATOR_REL}" \
  'if \(!input\.suppressDiagnostics\)' \
  "ArkWeb media observation must suppress diagnostics without disabling private-session takeover."
check_file_not_contains_rule "${ARK_WEB_MEDIA_TAKEOVER_COORDINATOR}" "${ARK_WEB_MEDIA_TAKEOVER_COORDINATOR_REL}" \
  'if \(input\.privateMode\)|!input\.privateMode' \
  "ArkWeb media private facts must not regain observation or presentation capability gates."
check_file_contains_rule "${MEDIA_RUNTIME_OBSERVATION_COORDINATOR}" \
  "${MEDIA_RUNTIME_OBSERVATION_COORDINATOR_REL}" \
  'suppressDiagnostics: this\.host\.resolvePrivateMode\(normalizedTabId\)' \
  "Media Runtime Observation must pass the current private fact only to diagnostic suppression."
media_private_frame_log_guard_count="$(grep -Ec 'if \(this\.host\.resolvePrivateMode\(tabId\)\)' \
  "${MEDIA_RUNTIME_OBSERVATION_COORDINATOR}" || true)"
if [ "${media_private_frame_log_guard_count}" -ne 3 ]; then
  report_failure "${MEDIA_RUNTIME_OBSERVATION_COORDINATOR_REL} must suppress all three frame-probe diagnostic paths in private sessions."
fi
check_file_contains_rule "${MEDIA_RUNTIME_OBSERVATION_COORDINATOR}" \
  "${MEDIA_RUNTIME_OBSERVATION_COORDINATOR_REL}" \
  'mediaFrameRuntimeCoordinator\.beginDocument\([[:space:]]*normalizedTabId,[[:space:]]*this\.host\.resolvePrivateMode\(normalizedTabId\)' \
  "Media Runtime Observation must pass the current private fact into Frame Runtime diagnostic suppression."
check_file_contains_rule "${MEDIA_FRAME_RUNTIME_COORDINATOR}" "${MEDIA_FRAME_RUNTIME_COORDINATOR_REL}" \
  'beginDocument\(tabId: string, suppressDiagnostics: boolean\): void' \
  "Media Frame Runtime must receive diagnostic suppression as a document fact without disabling frame capabilities."
media_private_frame_runtime_log_guard_count="$(grep -Ec 'this\.suppressDiagnosticsByTabId\.get\(' \
  "${MEDIA_FRAME_RUNTIME_COORDINATOR}" || true)"
if [ "${media_private_frame_runtime_log_guard_count}" -ne 3 ]; then
  report_failure "${MEDIA_FRAME_RUNTIME_COORDINATOR_REL} must suppress command-result, command-queue, and channel-read diagnostics in private sessions."
fi
check_file_not_contains_rule "${MEDIA_FRAME_RUNTIME_COORDINATOR}" "${MEDIA_FRAME_RUNTIME_COORDINATOR_REL}" \
  'scriptSupplyLogged|media_frame_probe_script_supplied' \
  "Media Frame Runtime must not emit a privacy-unaware global probe-script diagnostic."
check_file_contains_rule "${MEDIA_DISCOVERY_COORDINATOR}" "${MEDIA_DISCOVERY_COORDINATOR_REL}" \
  'if \(input\.runtime\.privateMode\)' \
  "Media Discovery must suppress media-surface diagnostics for private sessions without disabling discovery."
check_file_not_contains_rule "${MEDIA_DISCOVERY_COORDINATOR}" "${MEDIA_DISCOVERY_COORDINATOR_REL}" \
  'if \(!input\.runtime\.privateMode\)' \
  "Media Discovery must not turn the private diagnostic fact into a capability gate."
check_file_not_contains_rule "${MEDIA_PROBE_SCHEDULER}" "${MEDIA_PROBE_SCHEDULER_REL}" \
  'plan\.reason|reason: string,' \
  "Media probe scheduling must not carry diagnostics-only plan reasons."
check_file_not_contains_rule "${MEDIA_PROBE_POLICY_SERVICE}" "${MEDIA_PROBE_POLICY_SERVICE_REL}" \
  'interface MediaDeepProbePlan extends MediaProbeDecision|enabledDeepProbePlan\([^)]*reason|disabledDeepProbePlan\(reason' \
  "Media deep-probe plans must contain only execution policy, not removed diagnostic metadata."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserPageChromeThemeProbeHost|applyTabPageChromeThemeSnapshot|applyTabPageChromeVisualTopColor|sampleTabPageChromeVisualTopColor' \
  "BrowserShellPage must not regain Page Chrome Theme application policy or async sample-result choreography."
check_file_not_contains_rule "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR}" \
  "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR_REL}" \
  'pageChromeThemeSamplingHost|chromeThemeProbeDelayMs|chromeVisualSampleDelayMs' \
  "Web Page Feature Effects must not carry Page Chrome Theme fixed Host or delay policy."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" \
  "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'clearTabPageChromeTheme|chromeRuntimeCoordinator: BrowserChromeRuntimeCoordinator' \
  "Web Page Lifecycle must delegate Page Chrome Theme cleanup to the Sampling/Application owner."
check_file_not_contains_rule "${SHELL_PRESENTATION_TOKENS}" "${SHELL_PRESENTATION_TOKENS_REL}" \
  'WEB_DEFERRED_CHROME_THEME_PROBE_DELAY_MS|WEB_FAST_CHROME_THEME_PROBE_DELAY_MS|WEB_FAST_CHROME_VISUAL_SAMPLE_DELAY_MS' \
  "Page Chrome Theme delay policy must stay inside its owner instead of presentation tokens."
check_file_contains_rule "${WEB_TOP_IMMERSION_SESSION_COORDINATOR}" \
  "${WEB_TOP_IMMERSION_SESSION_COORDINATOR_REL}" \
  'statusBarVisible: boolean;' \
  "Web Top Immersion must read current status-bar visibility in its facts snapshot."
check_file_contains_rule "${WEB_TOP_IMMERSION_SESSION_COORDINATOR}" \
  "${WEB_TOP_IMMERSION_SESSION_COORDINATOR_REL}" \
  'resolveVisibleTopInsetPx: \(\) => number;' \
  "Web Top Immersion must resolve the stable visible inset lazily outside the scroll facts path."
check_file_contains_rule "${WEB_TOP_IMMERSION_SESSION_COORDINATOR}" \
  "${WEB_TOP_IMMERSION_SESSION_COORDINATOR_REL}" \
  'refreshVisibleInset\(source: string\): void' \
  "Web Top Immersion must own refreshes when already-visible native top chrome changes occupied height."
check_file_contains_rule "${WEB_TOP_IMMERSION_SESSION_COORDINATOR}" \
  "${WEB_TOP_IMMERSION_SESSION_COORDINATOR_REL}" \
  'Failed to set status bar visible=' \
  "Web Top Immersion must own window-visibility failure fallback diagnostics."
check_file_contains_rule "${WEB_TOP_IMMERSION_SESSION_COORDINATOR}" \
  "${WEB_TOP_IMMERSION_SESSION_COORDINATOR_REL}" \
  "TOP_IMMERSION_DEVICE_LOG_TAG: string = 'BrowserShellPage'" \
  "Web Top Immersion must preserve the established BrowserShellPage device-log filter channel explicitly."
web_top_immersion_host_callback_count="$(awk '
  /export interface BrowserWebTopImmersionSessionHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /^  [A-Za-z0-9_]+: \(/ { count += 1 }
' "${WEB_TOP_IMMERSION_SESSION_COORDINATOR}")"
if [ "${web_top_immersion_host_callback_count}" -gt 4 ]; then
  report_failure "${WEB_TOP_IMMERSION_SESSION_COORDINATOR_REL} must keep the Top Immersion Host at no more than 4 lazy-fact/platform-effect callbacks; found ${web_top_immersion_host_callback_count}."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'buildWebTopImmersionFacts|applyWebTopImmersionPresentation|handleWebTopImmersionWindowFailure' \
  "BrowserShellPage must not regain Top Immersion facts, application, or failure policy helpers."
check_file_contains_rule "${WEB_SCROLL_INTERACTION_COORDINATOR}" \
  "${WEB_SCROLL_INTERACTION_COORDINATOR_REL}" \
  'handleScroll\(tabId: string, scrollOffsetY: number\): void' \
  "Web Scroll Interaction must own scroll classification and downstream application ordering."
check_file_contains_rule "${WEB_SCROLL_INTERACTION_COORDINATOR}" \
  "${WEB_SCROLL_INTERACTION_COORDINATOR_REL}" \
  'handleTouch\(tabId: string, phase: BrowserWebScrollTouchPhase\): void' \
  "Web Scroll Interaction must own touch, performance-window, and idle-settle ordering."
check_file_contains_rule "${WEB_SCROLL_INTERACTION_COORDINATOR}" \
  "${WEB_SCROLL_INTERACTION_COORDINATOR_REL}" \
  'smoothModeService: WebScrollSmoothModeService;' \
  "Web Scroll Interaction must compose the fixed Smooth Mode runtime dependency directly."
check_file_contains_rule "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR}" \
  "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR_REL}" \
  'resolveWebScrollInteractionCoordinator: \(\) => BrowserWebScrollInteractionCoordinator;' \
  "Page Chrome Theme sampling must consume Web scroll quiet-window behavior through the fixed owner."
check_file_not_contains_rule "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR}" \
  "${PAGE_CHROME_THEME_SAMPLING_COORDINATOR_REL}" \
  'scrollPerformanceState:|scrollPerformanceCoordinator:' \
  "Page Chrome Theme sampling must not depend on Web Scroll Interaction internal state representation."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_MODELS}" "${WEB_PAGE_LIFECYCLE_MODELS_REL}" \
  'lastWebScrollY:' \
  "Web Page Lifecycle shell facts must not route Web Scroll Interaction internal offset state through BrowserShell."
web_scroll_interaction_shell_callback_count="$(awk '
  /export interface BrowserWebScrollInteractionShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /^  [A-Za-z0-9_]+: \(/ { count += 1 }
' "${WEB_SCROLL_INTERACTION_COORDINATOR}")"
if [ "${web_scroll_interaction_shell_callback_count}" -ne 2 ]; then
  report_failure "${WEB_SCROLL_INTERACTION_COORDINATOR_REL} must keep exactly two current-facts/UI-decision shell callbacks; found ${web_scroll_interaction_shell_callback_count}."
fi
if [ -e "${OLD_WEB_BOTTOM_CHROME_SCROLL_INPUT_VIEW_MODEL}" ]; then
  report_failure "${OLD_WEB_BOTTOM_CHROME_SCROLL_INPUT_VIEW_MODEL_REL} must stay deleted; Web Scroll Interaction owns its Bottom Chrome input construction."
fi
if [ -e "${OLD_BOTTOM_CHROME_SCROLL_IDLE_SETTLE_SCHEDULER}" ]; then
  report_failure "${OLD_BOTTOM_CHROME_SCROLL_IDLE_SETTLE_SCHEDULER_REL} must stay deleted; idle-settle timing is subordinate to the Web Scroll Interaction owner."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserWebBottomChromeScrollInputViewModel|webBottomChromeScrollIdleSettleScheduler|webScrollPerformanceState|lastWebScrollY: number|private (markWebScrollInteractionActive|markWebScrollInteractionActiveForMove|getWebScrollQuietDelayMs|shouldDeferForWebScrollPerformance|buildWebBottomChromeScrollInput|recordWebBottomChromeScrollMove|settleWebBottomChromeScroll|applyWebBottomChromeScrollIdleSettle|applyWebSmoothModeForScroll)\(' \
  "BrowserShellPage must not regain Web scroll policy, timer, performance-state, input-construction, or Smooth Mode ownership."
check_file_not_contains_rule "${SHELL_PRESENTATION_TOKENS}" "${SHELL_PRESENTATION_TOKENS_REL}" \
  'WEB_SCROLL_INTERACTION_QUIET_MS|WEB_SCROLL_INTERACTION_MOVE_REFRESH_MS' \
  "Web Scroll Interaction timing policy must stay inside its owner instead of presentation tokens."
check_file_not_contains_rule "${WEB_SCROLL_INTERACTION_COORDINATOR}" \
  "${WEB_SCROLL_INTERACTION_COORDINATOR_REL}" \
  'WebScrollInteractionPort|WebScrollInteractionHostAdapter' \
  "Web Scroll Interaction must deepen the existing owner instead of adding a shallow Port or HostAdapter."
check_file_not_contains_rule "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}" \
  "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR_REL}" \
  'BrowserActiveTabRuntimeRestoreEffect|applyEffect:|retryActiveTabRestore' \
  "Active Runtime Restore must own restore/reload/snapshot/failure application instead of emitting generic effects or retaining the dead retry flow."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'applyBrowserActiveTabRuntimeRestoreEffect|browserActiveTabRuntimeRestoreSink' \
  "BrowserShellPage must not interpret Active Runtime Restore effects or rebuild its old fixed-dependency Sink."
check_file_contains_rule "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}" \
  "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR_REL}" \
  'tabSwitchCoordinator\.applyTabPatch' \
  "Active Runtime Restore tab mutations must use the canonical tab-list application owner."
check_file_contains_rule "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}" \
  "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR_REL}" \
  'resolveWebTabsController\(\)\.restoreWebState' \
  "Active Runtime Restore WebState application must use the existing WebTabs owner through its fixed late resolver."
check_file_contains_rule "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}" \
  "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR_REL}" \
  'resolveTabHomeCoordinator\(\)\.degradeBrokenActiveTab' \
  "Active Runtime Restore degraded-home fallback must enter the existing Tab Home owner directly."
active_tab_runtime_restore_host_callback_count="$(awk '
  /export interface BrowserActiveTabRuntimeRestoreHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}")"
if [ "${active_tab_runtime_restore_host_callback_count}" -gt 6 ]; then
  report_failure "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR_REL} must keep Active Runtime Restore Host at no more than 6 facts/state/diagnostic/transition callbacks; found ${active_tab_runtime_restore_host_callback_count}."
fi
active_tab_runtime_restore_state_field_count="$(awk '
  /export interface BrowserActiveTabRuntimeRestoreStateApplication \{/ { in_state = 1; next }
  in_state && /^}/ { print count + 0; exit }
  in_state && /\?:/ { count += 1 }
' "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}")"
if [ "${active_tab_runtime_restore_state_field_count}" -gt 11 ]; then
  report_failure "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR_REL} must keep the typed Restore state application at no more than 11 existing publication fields; found ${active_tab_runtime_restore_state_field_count}."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'setTimeout\(|BrowserHomeStartupEntranceViewModel|homeStartupEntranceAnimationRunId|homeContentEntranceAnimationRunId|homeRevealFromTabsAnimationRunId|suppressNextHomeContentEntranceAnimation|scheduleHomeBottomPanelRestoreFromPeek' \
  "BrowserShellPage must not regain Home presentation timers, run state, suppression policy, or the deleted Startup Entrance ViewModel."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State homePresentationSessionState: BrowserHomePresentationSessionState' \
  "BrowserShellPage must keep Home presentation as one explicit observed session state."
check_file_contains_rule "${HOME_PRESENTATION_SESSION_COORDINATOR}" \
  "${HOME_PRESENTATION_SESSION_COORDINATOR_REL}" \
  'initializeStartupEntrance\(\)' \
  "Home Presentation Session must own startup entrance sequencing."
check_file_contains_rule "${HOME_PRESENTATION_SESSION_COORDINATOR}" \
  "${HOME_PRESENTATION_SESSION_COORDINATOR_REL}" \
  'handleHomeBecameVisible\(\)' \
  "Home Presentation Session must own content entrance sequencing."
check_file_contains_rule "${HOME_PRESENTATION_SESSION_COORDINATOR}" \
  "${HOME_PRESENTATION_SESSION_COORDINATOR_REL}" \
  'prepareTabsOverviewReveal\(' \
  "Home Presentation Session must own Tabs Overview to Home reveal preparation."
check_file_contains_rule "${HOME_PRESENTATION_SESSION_COORDINATOR}" \
  "${HOME_PRESENTATION_SESSION_COORDINATOR_REL}" \
  'prepareDirectReveal\(\)' \
  "Home Presentation Session must own direct Home reveal preparation."
check_file_contains_rule "${HOME_PRESENTATION_SESSION_COORDINATOR}" \
  "${HOME_PRESENTATION_SESSION_COORDINATOR_REL}" \
  'playReveal\(' \
  "Home Presentation Session must own Home reveal playback and follow-up scheduling."
check_file_contains_rule "${HOME_PRESENTATION_VIEW_MODEL}" "${HOME_PRESENTATION_VIEW_MODEL_REL}" \
  'buildStartupEntranceVisualState\(' \
  "Home Presentation ViewModel must own startup visual projection after the thin Startup ViewModel is removed."
if [ -e "${OLD_HOME_STARTUP_ENTRANCE_VIEW_MODEL}" ]; then
  report_failure "${OLD_HOME_STARTUP_ENTRANCE_VIEW_MODEL_REL} must stay deleted; startup timing belongs to Home Presentation Session and visual projection belongs to Home Presentation ViewModel."
fi
home_presentation_session_host_callback_count="$(awk '
  /export interface BrowserHomePresentationSessionHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${HOME_PRESENTATION_SESSION_COORDINATOR}")"
if [ "${home_presentation_session_host_callback_count}" -gt 4 ]; then
  report_failure "${HOME_PRESENTATION_SESSION_COORDINATOR_REL} must keep the Home Presentation Session Host at no more than 4 facts/state/ArkUI/atomic-effect callbacks; found ${home_presentation_session_host_callback_count}."
fi
home_presentation_session_state_field_count="$(awk '
  /export interface BrowserHomePresentationSessionState \{/ { in_state = 1; next }
  in_state && /^}/ { print count + 0; exit }
  in_state && /: / { count += 1 }
' "${HOME_PRESENTATION_SESSION_COORDINATOR}")"
if [ "${home_presentation_session_state_field_count}" -gt 5 ]; then
  report_failure "${HOME_PRESENTATION_SESSION_COORDINATOR_REL} must keep Home presentation in no more than 5 explicit ArkUI render fields; found ${home_presentation_session_state_field_count}."
fi
check_file_contains_rule "${ERROR_DOCUMENT_LOAD_COORDINATOR}" "${ERROR_DOCUMENT_LOAD_COORDINATOR_REL}" \
  'webLoadRuntimeCoordinator\.runDataLoad' \
  "error-document Web loading must use the fixed Web Load runtime dependency instead of a page callback."
check_file_contains_rule "${ERROR_DOCUMENT_LOAD_COORDINATOR}" "${ERROR_DOCUMENT_LOAD_COORDINATOR_REL}" \
  'activeTabRuntimeRestoreCoordinator\.reloadActive' \
  "error-document retry must use the fixed Active Runtime Restore dependency instead of a page callback."
check_file_contains_rule "${ERROR_DOCUMENT_LOAD_COORDINATOR}" "${ERROR_DOCUMENT_LOAD_COORDINATOR_REL}" \
  'completeActivePageLoadingProgress' \
  "error-document commit must complete Lifecycle-owned loading progress without an owner-page-owner callback loop."
check_file_contains_rule "${ERROR_DOCUMENT_LOAD_COORDINATOR}" "${ERROR_DOCUMENT_LOAD_COORDINATOR_REL}" \
  'addressSubmissionCoordinator\.consumeAutomaticSearchFallback' \
  "main-frame search failure fallback must consume one eligible Address Submission token before navigating."
check_file_contains_rule "${SEARCH_ENGINE_ROUTING_SERVICE}" "${SEARCH_ENGINE_ROUTING_SERVICE_REL}" \
  'consumeLoadFailureFallback' \
  "Search Engine Routing must own exactly-once load-failure fallback eligibility."
check_file_contains_rule "${ADDRESS_SUBMISSION_COORDINATOR}" "${ADDRESS_SUBMISSION_COORDINATOR_REL}" \
  'openAutomaticSearchFallback' \
  "Address Submission must own automatic fallback history, presentation, and navigation."
check_file_not_contains_rule "${WEB_LOAD_ERROR_DOCUMENT_SERVICE}" "${WEB_LOAD_ERROR_DOCUMENT_SERVICE_REL}" \
  'fallbackSearchAction|fallback-search' \
  "the error document must not restore a manual search-fallback action."
check_file_contains_rule "${ERROR_DOCUMENT_LOAD_COORDINATOR}" "${ERROR_DOCUMENT_LOAD_COORDINATOR_REL}" \
  'loadFailureSurfaceCoordinator\.resolveErrorMessage\(' \
  "error-document active presentation must resolve the stored/fallback error message inside its owner."
check_file_not_contains_rule "${ERROR_DOCUMENT_LOAD_COORDINATOR}" "${ERROR_DOCUMENT_LOAD_COORDINATOR_REL}" \
  'BrowserErrorDocumentLoadHost|markWebDocumentLoading:|runDataLoad:|reloadActivePageAfterLoadError:|openResolvedUrl:' \
  "the error-document implementation must not regain the old 40-callback page Host or fixed-dependency forwarding."
error_document_shell_callback_count="$(awk '
  /export interface BrowserErrorDocumentLoadShell/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /=>/ { callbacks += 1 }
  END { print callbacks + 0 }
' "${ERROR_DOCUMENT_LOAD_COORDINATOR}")"
if [ "${error_document_shell_callback_count}" -gt 3 ]; then
  report_failure "${ERROR_DOCUMENT_LOAD_COORDINATOR_REL} Error Document shell must stay at three presentation/Shared Snapshot callbacks or fewer."
fi
check_file_not_contains_rule "${ERROR_DOCUMENT_LOAD_COORDINATOR}" "${ERROR_DOCUMENT_LOAD_COORDINATOR_REL}" \
  '^  (resolveFacts|commitTabNavigation|applyActivePageErrorSurfaceVisible|applyActiveCommittedErrorDocument|applyActiveCommittedUrlCorrection|clearActiveErrorDocumentCommittedUi|applyActiveErrorDocumentRetryUi|openSystemNetworkSettings):' \
  "Error Document shell must not regain fixed Tab/Lifecycle/Navigation/platform callback plumbing."
check_file_not_contains_rule "${USER_AGENT_ACTION_COORDINATOR}" "${USER_AGENT_ACTION_COORDINATOR_REL}" \
  'resolveForRuntimeWithSystemDefault\(' \
  "User-Agent Action must not regain Browsing Identity policy assembly for Web Load callers."
check_file_contains_rule "${WEB_LOAD_RUNTIME_COORDINATOR}" "${WEB_LOAD_RUNTIME_COORDINATOR_REL}" \
  'resolveBrowsingIdentityPolicyCoordinator\(\)\.resolveWithSystemDefault\(' \
  "Web Load must resolve Browsing Identity directly through the Policy Snapshot owner."
check_file_not_contains_rule "${WEB_LOAD_RUNTIME_COORDINATOR}" "${WEB_LOAD_RUNTIME_COORDINATOR_REL}" \
  'resolveUserAgentActionCoordinator' \
  "Web Load must not route Browsing Identity policy through the UI Action owner."
check_file_contains_rule "${BROWSING_IDENTITY_POLICY_COORDINATOR}" \
  "${BROWSING_IDENTITY_POLICY_COORDINATOR_REL}" \
  'BrowserUserAgentHostPolicyService\.resolveMandatoryCompatibilityForHost\(' \
  "The Policy Snapshot owner must include mandatory signed/bundled Host identity facts."
check_file_contains_rule "${BROWSING_IDENTITY_DECISION_SERVICE}" \
  "${BROWSING_IDENTITY_DECISION_SERVICE_REL}" \
  'snapshot\.mandatoryHost,' \
  "The pure Browsing Identity Decision must keep mandatory Host identity in its fixed precedence list."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserErrorDocumentLoadShell: BrowserErrorDocumentLoadShell' \
  "BrowserShellPage must expose only the Error Document dynamic-fact/UI/platform shell."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State showPageErrorSurface: boolean' \
  "BrowserShellPage must keep Error Document visibility as explicit ArkUI state."
check_file_contains_rule "${WEB_LOADING_PROGRESS_BAR}" "${WEB_LOADING_PROGRESS_BAR_REL}" \
  '@Prop presentation: BrowserWebLoadingProgressBarPresentationState' \
  "the top loading progress component must consume one typed presentation instead of parallel scalar props."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private shouldRenderWebLoadingProgressBar\(|private resolveWebLoadingProgressBarProgress\(|private resolveWebLoadingProgressBarHeight\(' \
  "BrowserShellPage must not regain scalar top loading-progress presentation wrappers."
check_file_contains_rule "${PULL_REFRESH_LOADING_AREA}" "${PULL_REFRESH_LOADING_AREA_REL}" \
  '@Prop presentation: BrowserPullRefreshPresentation' \
  "the Pull Refresh loading area must consume one typed presentation instead of parallel scalar props."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private buildPullRefreshPresentation\(' \
  "BrowserShellPage must not regain the Pull Refresh presentation forwarding helper."
check_file_contains_rule "${ARKWEB_MEDIA_TAKEOVER_BUTTON}" "${ARKWEB_MEDIA_TAKEOVER_BUTTON_REL}" \
  '@Prop state: BrowserArkWebMediaButtonState' \
  "the ArkWeb media takeover floating-button host must consume one typed owner presentation."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'sourceCount: this\.buildArkWebMediaTakeoverButtonState\(\)\.sourceCount|controllable: this\.buildArkWebMediaTakeoverButtonState\(\)\.controllable|busy: this\.buildArkWebMediaTakeoverButtonState\(\)\.busy|x: this\.buildArkWebMediaTakeoverButtonState\(\)\.x|y: this\.buildArkWebMediaTakeoverButtonState\(\)\.y' \
  "BrowserShellPage must not regain scalar ArkWeb media takeover button-state expansion."
check_file_contains_rule "${HOME_SYSTEM_SURFACE}" "${HOME_SYSTEM_SURFACE_REL}" \
  '@Prop contentPresentation: BrowserHomeSurfaceContentPresentationState' \
  "the Home System surface must consume one typed content-session presentation."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'contentOpacity: this\.buildHomeSurfaceContentPresentationState\(\)\.contentOpacity|contentOffsetY: this\.buildHomeSurfaceContentPresentationState\(\)\.contentOffsetY' \
  "BrowserShellPage must not regain scalar Home surface content-session projection."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserErrorDocumentLoadHost|browserErrorDocumentLoadCoordinator|new BrowserErrorDocumentLoadCoordinator|private buildWebLoadErrorPresentation\(' \
  "BrowserShellPage must not regain direct Error Document ownership, the old wide Host, or active-presentation composition."
check_file_contains_rule "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserShellRouteCoordinator.ets" \
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserShellRouteCoordinator.ets' \
  'resolveTabScopedEventContextCoordinator: \(\) => BrowserTabScopedEventContextCoordinator' \
  "BrowserShell Route must resolve fixed route context through the canonical tab-scoped context owner."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'readContext: \(\): BrowserShellRouteContext|private (getCurrentProfileId|getCurrentPrivacyMode|getCurrentDataScope|getPrivacyModeForTab|isCurrentTabPrivate|isCurrentBoundaryPrivate|isBoundaryPrivate|isTabStatePrivate|buildCurrentTabBoundaryCreateOptions|resolvePageUrlForTab|getCurrentSiteOrigin)\(' \
  "BrowserShellPage must not regain route-context publication or page-owned tab boundary/private/page-URL helpers."
check_file_contains_rule "${TAB_SCOPED_EVENT_CONTEXT_COORDINATOR}" "${TAB_SCOPED_EVENT_CONTEXT_COORDINATOR_REL}" \
  'resolveCurrentContext\(\): BrowserTabScopedEventContext' \
  "Tab-scoped context must remain the canonical current/tab URL, boundary, origin, and privacy context owner."
tab_scoped_context_host_callback_count="$(awk '
  /export interface BrowserTabScopedEventContextHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${TAB_SCOPED_EVENT_CONTEXT_COORDINATOR}")"
if [ "${tab_scoped_context_host_callback_count}" -gt 2 ]; then
  report_failure "${TAB_SCOPED_EVENT_CONTEXT_COORDINATOR_REL} must keep its Host at no more than two shell-facts/origin callbacks; found ${tab_scoped_context_host_callback_count}."
fi
check_file_not_contains_rule "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserShellRouteCoordinator.ets" \
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserShellRouteCoordinator.ets' \
  'BrowserShellRouteHostAdapter|BrowserShellRouteHost|buildRouteHost\(|getDataScope|getPrivacyMode|getProfileId|getCurrentUrl|getAddressInput|getCurrentWindowId' \
  "Shell Route must not regain the single-caller adapter or split route-context getters."
check_file_contains_rule "${MEDIA_RESOURCE_SESSION_COORDINATOR}" "${MEDIA_RESOURCE_SESSION_COORDINATOR_REL}" \
  'runManualResourceScanForActiveTab' \
  "Media Resource Session must own resource-panel refresh and scan ordering."
check_file_contains_rule "${MEDIA_RESOURCE_SESSION_COORDINATOR}" "${MEDIA_RESOURCE_SESSION_COORDINATOR_REL}" \
  'private async runManifestParse' \
  "Media Resource Session must own Manifest/HLS parse token and completion ordering."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State mediaResourceSessionSnapshot: BrowserMediaResourceSessionSnapshot' \
  "BrowserShellPage must observe one explicit Media Resource Session snapshot."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserMediaResourceSessionShell: BrowserMediaResourceSessionShell' \
  "BrowserShellPage must expose one narrow Media Resource UI/platform shell."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserMediaManifestCoordinator|browserMediaManifestCoordinator|browserHlsTakeoverViewModel|@State showHlsTakeoverSheet:|@State hlsTakeoverSheetVisible:|@State hlsTakeoverTarget:|@State hlsTakeoverParsingCandidateId:|@State hlsTakeoverParseResult:|@State resourceListItems:|@State resourceTabCounts:|@State resourceScanInProgress:|@State resourceManifestParsingCandidateId:|@State resourceManifestParseResult:|private openMediaResourcesSheet\(|private closeMediaResourcesSheet\(|private parseHlsTakeoverCandidate\(|private handleMediaResourceAction\(' \
  "BrowserShellPage must not regain Media Resource/HLS session state, parse ordering, or action orchestration."
if [ -e "${OLD_MEDIA_MANIFEST_COORDINATOR}" ]; then
  report_failure "${OLD_MEDIA_MANIFEST_COORDINATOR_REL} must stay deleted; Manifest parsing is subordinate to the Media Resource Session owner."
fi
check_file_contains_rule "${WEBPAGE_TRANSLATION_COORDINATOR}" "${WEBPAGE_TRANSLATION_COORDINATOR_REL}" \
  'handleUserAction\(action: WebpageTranslationUserAction' \
  "Webpage Translation must expose one narrative user-action entry point."
check_file_contains_rule "${WEBPAGE_TRANSLATION_COORDINATOR}" "${WEBPAGE_TRANSLATION_COORDINATOR_REL}" \
  'private applicationSurfaceVersion: number' \
  "Webpage Translation must reject stale async publication across close, reopen, and lifecycle resets."
translation_snapshot_count="$(grep -Ec '@State webpageTranslationApplicationSnapshot: WebpageTranslationApplicationSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${translation_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Webpage Translation Application snapshot."
fi
top_floating_prompt_action_callback_count="$(grep -Ec '^  onAction: \(action: BrowserTopFloatingPromptAction\)' \
  "${TOP_FLOATING_PROMPT_HOST}" || true)"
if [ "${top_floating_prompt_action_callback_count}" -ne 1 ]; then
  report_failure "${TOP_FLOATING_PROMPT_HOST_REL} must expose exactly one typed prompt action callback."
fi
check_file_contains_rule "${TOP_FLOATING_PROMPT_HOST}" "${TOP_FLOATING_PROMPT_HOST_REL}" \
  'visible: this\.isPromptPresentationReady\(\)' \
  "must keep shared prompts hidden until their first-frame geometry is ready."
check_file_contains_rule "${TOP_FLOATING_PROMPT_HOST}" "${TOP_FLOATING_PROMPT_HOST_REL}" \
  'return this\.containerWidthVp > 0 && this\.resolveActivePromptVisible\(\);' \
  "must require a positive measured width before shared prompt presentation."
check_file_contains_rule "${TOP_FLOATING_SURFACE}" "${TOP_FLOATING_SURFACE_REL}" \
  'this\.buildPresentationLayer\(\)' \
  "must keep width and position outside the animated prompt presentation layer."
check_file_contains_rule "${TOP_FLOATING_SURFACE}" "${TOP_FLOATING_SURFACE_REL}" \
  'private buildPresentationLayer\(\)' \
  "must isolate opacity and translate animation from responsive geometry."
check_file_contains_rule "${TOP_FLOATING_PROMPT_COORDINATOR}" "${TOP_FLOATING_PROMPT_COORDINATOR_REL}" \
  'handleAction\(action: BrowserTopFloatingPromptAction\)' \
  "Top Floating Prompt actions must enter through the existing presentation owner."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'WebpageTranslationSurfaceCoordinator|webpageTranslationSurfaceCoordinator|webpageTranslationPolicyService|webpageTranslationSettingsViewModel|@State webpageTranslationPanelState:|@State webpageTranslationPanelOrigin:|@State webpageTranslationTargetLanguageHelperText:|@State webpageTranslationTargetLanguageOptions:|webpageTranslationResumeAfterScrollTimer|private openWebpageTranslationPanel\(|private closeWebpageTranslationPanel\(|private cancelWebpageTranslation\(|private translateCurrentWebpage\(|private showWebpageTranslationDisclosureDialog\(|private runWebpageTranslationForCurrentPage\(|private openWebpageTranslationTargetLanguageSheet\(|private selectWebpageTranslationTargetLanguage\(' \
  "BrowserShellPage must not regain Webpage Translation policy, per-field state, timer, target-language, or async flow ownership."
check_file_not_contains_rule "${TOP_FLOATING_PROMPT_HOST}" "${TOP_FLOATING_PROMPT_HOST_REL}" \
  'on(OpenBackgroundTab|DismissBackgroundTab|OpenOfflineSave|DismissOfflineSave|ExternalNavigationAction|WebpageTranslationAction|DismissGestureOnboardingPrompt):' \
  "Top Floating Prompt Host must not regain peer feature callbacks."
external_navigation_snapshot_count="$(grep -Ec '@State externalNavigationPromptState: ExternalNavigationPromptState' \
  "${SHELL_PAGE}" || true)"
if [ "${external_navigation_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level External Navigation prompt state."
fi
check_file_contains_rule "${UNIFIED_LINK_APPLICATION_COORDINATOR}" \
  "${UNIFIED_LINK_APPLICATION_COORDINATOR_REL}" \
  'requestExternalNavigationPrompt\(' \
  "Unified Link Application must remain the narrative entry for External Navigation prompts."
check_file_contains_rule "${UNIFIED_LINK_APPLICATION_COORDINATOR}" \
  "${UNIFIED_LINK_APPLICATION_COORDINATOR_REL}" \
  'private readonly infoBarApplicationCoordinator: BrowserExternalNavigationInfoBarApplicationCoordinator' \
  "External Navigation InfoBar must stay subordinate to Unified Link Application."
check_file_contains_rule "${EXTERNAL_NAVIGATION_INFO_BAR_COORDINATOR}" \
  "${EXTERNAL_NAVIGATION_INFO_BAR_COORDINATOR_REL}" \
  'private readonly infoBarQueue: BrowserInfoBarQueue' \
  "External Navigation InfoBar must own its prompt queue instead of exposing it to BrowserShell."
check_file_contains_rule "${UNIFIED_LINK_NAVIGATION_COORDINATOR}" \
  "${UNIFIED_LINK_NAVIGATION_COORDINATOR_REL}" \
  'readNavigationFacts: \(tabId: string\) => BrowserUnifiedLinkNavigationFacts' \
  "Unified Link Navigation must read one typed shell facts snapshot."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserInfoBarQueue|BrowserExternalNavigationInfoBarApplicationCoordinator|BrowserExternalNavigationInfoBarApplicationHost|BrowserUnifiedLinkApplicationPort|browserUnifiedLinkApplicationPort|browserExternalNavigationInfoBarApplicationHost|confirmExternalNavigationPrompt\(|dismissExternalNavigationPrompt\(' \
  "BrowserShellPage must not regain External Navigation queue, subordinate owner, wide Host/Port, or prompt sequencing."
check_file_not_contains_rule "${EXTERNAL_NAVIGATION_INFO_BAR_COORDINATOR}" \
  "${EXTERNAL_NAVIGATION_INFO_BAR_COORDINATOR_REL}" \
  'rememberChoice|remember_allow_and_open|remember_block|persistExternalNavigationSettings|webLoadRuntimeCoordinator' \
  "External Navigation InfoBar must not restore unreachable remember-choice branches or unrelated dependencies."
check_file_not_contains_rule "${TOP_FLOATING_PROMPT_HOST}" "${TOP_FLOATING_PROMPT_HOST_REL}" \
  'onOpenExternalNavigation|onDismissExternalNavigation' \
  "Top Floating Prompt Host must not regain two peer External Navigation callbacks."
check_file_not_contains_rule "${EXTERNAL_NAVIGATION_PROMPT_CARD}" "${EXTERNAL_NAVIGATION_PROMPT_CARD_REL}" \
  'onDismiss:' \
  "External Navigation Prompt Card must not expose an unused dismiss callback; swipe dismissal belongs to the top host."
if [ -e "${OLD_WEBPAGE_TRANSLATION_SURFACE_COORDINATOR}" ]; then
  report_failure "${OLD_WEBPAGE_TRANSLATION_SURFACE_COORDINATOR_REL} must stay deleted; page identity and surface policy belong inside Webpage Translation."
fi
check_file_contains_rule "${SITE_CONTROLS_COORDINATOR}" "${SITE_CONTROLS_COORDINATOR_REL}" \
  'handleUserAction\(' \
  "Site Controls must expose one narrative user-action entry point."
check_file_contains_rule "${SITE_CONTROLS_COORDINATOR}" "${SITE_CONTROLS_COORDINATOR_REL}" \
  'private pendingTrackingRefreshTimer: number' \
  "Site Controls must own deferred tracking-protection refresh timing."
check_file_not_contains_rule "${SITE_CONTROLS_MANAGEMENT_PAGE}" "${SITE_CONTROLS_MANAGEMENT_PAGE_REL}" \
  'acceptCookies|acceptThirdPartyCookies|cookieRowsEnabled|SettingsSitePolicyCoordinator' \
  "Site Controls must not regain browser-wide Cookie policy controls."
check_file_contains_rule "${COOKIE_MANAGEMENT_PAGE}" "${COOKIE_MANAGEMENT_PAGE_REL}" \
  'CookieManagementContent' \
  "browser-wide Cookie policy must remain available from its dedicated Settings page."
check_file_contains_rule "${COOKIE_MANAGEMENT_CONTENT}" "${COOKIE_MANAGEMENT_CONTENT_REL}" \
  '!this\.state\.canEditCookiePolicy' \
  "Cookie Management must truthfully disable device-wide mutations at a private-session boundary."
site_controls_snapshot_count="$(grep -Ec '@State siteControlsApplicationSnapshot: BrowserSiteControlsApplicationSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${site_controls_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Site Controls Application snapshot."
fi
site_controls_action_callback_count="$(grep -Ec '^  onAction: \(' "${SITE_INFO_SHEET}" || true)"
if [ "${site_controls_action_callback_count}" -ne 1 ]; then
  report_failure "${SITE_INFO_SHEET_REL} must expose exactly one typed Site Controls action callback."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'siteControlsSessionRevision|siteGuardianDays|pendingScrollDeferredTrackingProtectionStatusTimer|scheduleScrollDeferredTrackingProtectionStatusRefresh|private openSiteInfoSheet\(|private refreshSecurityReportGuardianDays\(|private closeSiteInfoSheet\(|private refreshSiteCertificateInfo\(|private configureAdsBlock\(|private refreshTrackingProtectionStatus\(|private refreshActiveSiteProtectionBlockedCount\(|private buildAdBlockPageRuntimeContext\(|private handleAdBlockCosmeticHidden\(|private handleAdBlockNativeAdsBlocked\(|private toggleCurrentAdBlockSiteProtection\(|private refreshCurrentSiteData\(|private confirmClearCurrentSiteBrowsingData\(|private clearCurrentSiteBrowsingData\(|private saveSitePermissionDraft\(' \
  "BrowserShellPage must not regain Site Controls session state, timers, or application sequencing."
check_file_not_contains_rule "${SITE_INFO_SHEET}" "${SITE_INFO_SHEET_REL}" \
  'onCancel:|onSave:|onCopyUrl:|onOpenPermission:|onChangePermission:|onClearSiteData:|onToggleProtectionSite:|onOpenSiteCustomization:|onOpenCertificateDetails:|onOpenProtectionLog:|onOpenFullSiteInfo:|onBackToOverview:|onClose:' \
  "Site Info Sheet must not regain thirteen peer Site Controls callbacks."
check_file_contains_rule "${WEB_ACTIVE_SURFACE_COORDINATOR}" "${WEB_ACTIVE_SURFACE_COORDINATOR_REL}" \
  'applySiteControlsAction' \
  "Web Active Surface must cross the Site Controls seam through one semantic action callback."
check_file_contains_rule "${WEB_ACTIVE_SURFACE_COORDINATOR}" "${WEB_ACTIVE_SURFACE_COORDINATOR_REL}" \
  'new BrowserWebNavigationStateSyncCoordinator\(' \
  "Web Active Surface must own Navigation State Sync as a subordinate implementation."
check_file_contains_rule "${WEB_ACTIVE_SURFACE_COORDINATOR}" "${WEB_ACTIVE_SURFACE_COORDINATOR_REL}" \
  'new BrowserPageChromeThemeSamplingCoordinator\(' \
  "Web Active Surface must own Page Chrome Theme Sampling as a subordinate implementation."
check_file_contains_rule "${WEB_ACTIVE_SURFACE_COORDINATOR}" "${WEB_ACTIVE_SURFACE_COORDINATOR_REL}" \
  'this\.actionExecutor = new BrowserWebActiveSurfaceActionExecutor\(\)' \
  "Web Active Surface must own its fixed action executor."
check_file_contains_rule "${WEB_ACTIVE_SURFACE_COORDINATOR}" "${WEB_ACTIVE_SURFACE_COORDINATOR_REL}" \
  'getPageLifecycleHost\(\): BrowserWebPageLifecycleApplicationHost' \
  "Web Active Surface must provide the shared Lifecycle shell implementation."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'new BrowserWebNavigationStateSyncCoordinator\(|new BrowserPageChromeThemeSamplingCoordinator\(|new BrowserWebActiveSurfaceActionExecutor\(|browserPageChromeThemeSamplingHost: BrowserPageChromeThemeSamplingHost|browserWebActiveSurfaceHost: BrowserWebActiveSurfaceVisualStateHost|browserWebPageLifecycleApplicationHost: BrowserWebPageLifecycleApplicationHost' \
  "BrowserShellPage must not rebuild Active Surface subordinate implementations or their former page-built Hosts."
check_file_not_contains_rule "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}" \
  "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR_REL}" \
  'activeSurfaceExecutor:|activeSurfaceHost:' \
  "Active Runtime Restore must depend only on the Active Surface owner."
check_file_not_contains_rule "${ACTIVE_RUNTIME_SYNC_COORDINATOR}" "${ACTIVE_RUNTIME_SYNC_COORDINATOR_REL}" \
  'activeSurfaceExecutor:|activeSurfaceHost:' \
  "Active Runtime Sync must depend only on the Active Surface owner."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'activeSurfaceExecutor:|activeSurfaceHost:' \
  "Web Page Lifecycle must depend only on the Active Surface owner."
web_active_surface_shell_callback_count="$(awk '
  /export interface BrowserWebActiveSurfaceShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${WEB_ACTIVE_SURFACE_COORDINATOR}")"
if [ "${web_active_surface_shell_callback_count}" -ne 8 ]; then
  report_failure "${WEB_ACTIVE_SURFACE_COORDINATOR_REL} must keep exactly 8 current-facts/state-publication/UI-platform callbacks; found ${web_active_surface_shell_callback_count}."
fi
check_file_not_contains_rule "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR}" \
  "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR_REL}" \
  'refreshActiveSiteProtectionBlockedCount:|refreshTrackingProtectionStatus:' \
  "Web Page Feature Effects must call the Site Controls owner instead of routing protection refresh through BrowserShell."
check_file_not_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'refreshTrackingProtectionStatus:' \
  "Web Page Lifecycle must not carry a page-built Site Controls refresh callback."
check_file_not_contains_rule "${SHELL_ROUTE_COORDINATOR}" "${SHELL_ROUTE_COORDINATOR_REL}" \
  'closeSiteInfoSheet:' \
  "Shell Route must not close Site Controls through a page-built callback; the Site Controls owner owns that order."
private_mode_lock_snapshot_count="$(grep -Ec '@State privateModeLockSessionSnapshot: BrowserPrivateModeLockSessionSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${private_mode_lock_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Private Mode Lock Session snapshot."
fi
check_file_contains_rule "${PRIVATE_MODE_LOCK_COORDINATOR}" "${PRIVATE_MODE_LOCK_COORDINATOR_REL}" \
  'private readonly userAuthService: PrivateModeUserAuthService' \
  "Private Mode Lock must own the system authentication adapter."
check_file_contains_rule "${PRIVATE_MODE_LOCK_COORDINATOR}" "${PRIVATE_MODE_LOCK_COORDINATOR_REL}" \
  'private authenticationGeneration: number' \
  "Private Mode Lock must own stale authentication callback rejection."
check_file_contains_rule "${PRIVATE_MODE_LOCK_COORDINATOR}" "${PRIVATE_MODE_LOCK_COORDINATOR_REL}" \
  'handleForegroundResume\(' \
  "Private Mode Lock must own foreground-resume authentication."
check_file_contains_rule "${PRIVATE_MODE_LOCK_COORDINATOR}" "${PRIVATE_MODE_LOCK_COORDINATOR_REL}" \
  'synchronizeCurrentBoundary\(' \
  "Private Mode Lock must own boundary synchronization."
check_file_contains_rule "${PRIVATE_MODE_LOCK_COORDINATOR}" "${PRIVATE_MODE_LOCK_COORDINATOR_REL}" \
  'ensureUnlocked\(' \
  "Private Mode Lock must expose one private-access gate."
check_file_contains_rule "${PRIVATE_MODE_LOCK_COORDINATOR}" "${PRIVATE_MODE_LOCK_COORDINATOR_REL}" \
  'handleUserAction\(' \
  "Private Mode Lock must own overlay user actions."
check_file_contains_rule "${PRIVATE_MODE_LOCK_OVERLAY}" "${PRIVATE_MODE_LOCK_OVERLAY_REL}" \
  'onAction: \(action: BrowserPrivateModeLockUserAction\)' \
  "Private Mode Lock Overlay must emit one typed action callback."
check_file_not_contains_rule "${PRIVATE_MODE_LOCK_OVERLAY}" "${PRIVATE_MODE_LOCK_OVERLAY_REL}" \
  'onUnlock:|onReturnToRegular:' \
  "Private Mode Lock Overlay must not regain peer action callbacks."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'privateModeLockState|privateModeLockOverlayVisible|privateModeAuthenticationInProgress|privateModeAuthenticationMessage|privateModeAuthenticationGeneration|privateModeUserAuthService|ensurePrivateModeUnlocked\(|authenticatePrivateModeAccess\(|requestPrivateAuthenticationAfterForegroundResume\(|private syncPrivateModeLockForCurrentBoundary\(|returnToRegularModeFromPrivateLock\(|unlockPrivateModeAccessWithoutAuthentication\(|PrivateModeUserAuthResult|PrivateModeUserAuthService|PRIVATE_MODE_AUTH_OVERLAY_PRESENTATION_DELAY_MS' \
  "BrowserShellPage must not regain Private Mode Lock state, timer, authentication service, or application sequencing."
check_file_not_contains_rule "${SHELL_ROUTE_COORDINATOR}" "${SHELL_ROUTE_COORDINATOR_REL}" \
  'ensurePrivateModeUnlocked:' \
  "Shell Route must depend directly on the Private Mode Lock owner instead of a page callback."
check_file_not_contains_rule "${TAB_SWITCH_COORDINATOR}" "${TAB_SWITCH_COORDINATOR_REL}" \
  'ensurePrivateModeUnlocked:|sync_private_mode_lock' \
  "Tab Switch must depend directly on the Private Mode Lock owner instead of page callback/platform wiring."
check_file_not_contains_rule "${FOREGROUND_TAB_CREATION_COORDINATOR}" "${FOREGROUND_TAB_CREATION_COORDINATOR_REL}" \
  'ensurePrivateModeUnlocked:|syncPrivateModeLockForCurrentBoundary:' \
  "Foreground Tab Creation must depend directly on the Private Mode Lock owner."
check_file_not_contains_rule "${PRIVATE_TAB_COORDINATOR}" "${PRIVATE_TAB_COORDINATOR_REL}" \
  'syncPrivateModeLockForCurrentBoundary:' \
  "Private Tab exit must synchronize the Private Mode Lock owner directly."
check_file_contains_rule "${PRIVACY_EFFECT_POLICY}" "${PRIVACY_EFFECT_POLICY_REL}" \
  "intent: 'app_service_mode_sync_deactivation'" \
  "App Service Mode Sync deactivation must remain a separately classified child effect."
check_file_contains_rule "${SETTINGS_DETAIL_VIEW_MODEL}" "${SETTINGS_DETAIL_VIEW_MODEL_REL}" \
  "'app_service_mode_sync_deactivation'" \
  "App Service Mode availability must come from its Sync child-effect decision."
check_file_not_contains_rule "${SETTINGS_DETAIL_VIEW_MODEL}" "${SETTINGS_DETAIL_VIEW_MODEL_REL}" \
  'buildAppServiceModeState\(appServiceMode, isPrivateContext\)' \
  "App Service Mode must not restore one blanket private-context gate for both choices."
check_file_contains_rule "${SETTINGS_DETAIL_VIEW_MODEL}" "${SETTINGS_DETAIL_VIEW_MODEL_REL}" \
  'canEditDevicePreferences && canDeactivateSync' \
  "Basic App Service Mode must require both device-preference and Sync-deactivation effects."
check_file_contains_rule "${APP_SERVICE_MODE_COORDINATOR}" "${APP_SERVICE_MODE_COORDINATOR_REL}" \
  'boundaryInput: BrowserDataBoundaryInput' \
  "App Service Mode must require current boundary facts at its commit seam."
check_file_contains_rule "${APP_SERVICE_MODE_COORDINATOR}" "${APP_SERVICE_MODE_COORDINATOR_REL}" \
  "'app_service_mode_sync_deactivation'" \
  "App Service Mode owner must enforce the Sync child effect before Basic-mode writes."
app_service_mode_boundary_call_count="$(grep -Eh 'appServiceModeCoordinator\.applyMode\(mode, \{' \
  "${SETTINGS_DETAIL_PAGE}" "${SETTINGS_INLINE_DETAIL_PANEL}" | wc -l | tr -d ' ' || true)"
if [ "${app_service_mode_boundary_call_count}" -ne 2 ]; then
  report_failure "Settings App Service Mode hosts must pass current boundary facts at both phone and embedded commit paths."
fi
qr_scan_shell_snapshot_count="$(grep -Ec '@State browserQrScanSessionSnapshot: BrowserQrScanSessionSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${qr_scan_shell_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level QR Scan Session snapshot."
fi
qr_scan_settings_snapshot_count="$(grep -Ec '@State private qrScanSessionSnapshot: BrowserQrScanSessionSnapshot' \
  "${SETTINGS_CENTER_SCREEN}" || true)"
if [ "${qr_scan_settings_snapshot_count}" -ne 1 ]; then
  report_failure "${SETTINGS_CENTER_SCREEN_REL} must observe exactly one first-level QR Scan Session snapshot."
fi
check_file_contains_rule "${QR_SCAN_COORDINATOR}" "${QR_SCAN_COORDINATOR_REL}" \
  'private pendingDesktopLoginSecret: string' \
  "QR Scan owner must keep Desktop Login secrets outside ArkUI page state."
check_file_contains_rule "${QR_SCAN_COORDINATOR}" "${QR_SCAN_COORDINATOR_REL}" \
  'private desktopLoginGeneration: number' \
  "QR Scan owner must reject stale Desktop Login completions after Session reset."
check_file_contains_rule "${QR_SCAN_COORDINATOR}" "${QR_SCAN_COORDINATOR_REL}" \
  'async confirmDesktopLogin\(\): Promise<void>' \
  "QR Scan owner must own Desktop Login confirmation and result interpretation."
check_file_contains_rule "${QR_SCAN_COORDINATOR}" "${QR_SCAN_COORDINATOR_REL}" \
  'handleSurfaceDismissed\(surface: BrowserQrScanSurface\)' \
  "QR Scan owner must own Desktop and Wi-Fi transient cleanup."
check_file_contains_rule "${QR_SCAN_COORDINATOR}" "${QR_SCAN_COORDINATOR_REL}" \
  'resetSession\(\): void' \
  "QR Scan owner must expose one application Session reset entry."
check_file_not_contains_rule "${QR_SCAN_COORDINATOR}" "${QR_SCAN_COORDINATOR_REL}" \
  'export interface BrowserQrScanAction|export interface BrowserQrDesktopLoginResult|scanAndApply\(' \
  "QR Scan owner must not expose the old wide action/result DTO application seam."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserQrScanAction|BrowserQrDesktopLoginResult|BrowserQrScanHost|BrowserWifiQrCredentials|pendingDesktopLogin|pendingWifiQrCredentials|private openDesktopLoginConfirmSheet\(|private finishPendingDesktopLoginFromQrScan\(|private handleDesktopLoginFromQrScanResult\(|private clearPendingDesktopLoginConfirmation\(' \
  "BrowserShellPage must not regain QR/Desktop Login state, secrets, DTO interpretation, or cleanup sequencing."
check_file_not_contains_rule "${SETTINGS_CENTER_SCREEN}" "${SETTINGS_CENTER_SCREEN_REL}" \
  'BrowserQrScanAction|BrowserQrDesktopLoginResult|BrowserQrScanHost|BrowserWifiQrCredentials|pendingDesktopLogin|pendingWifiQrCredentials|private openDesktopLoginConfirmation\(|private confirmDesktopLoginFromSheet\(|private clearPendingDesktopLoginConfirmation\(|private handleDesktopLoginResult\(' \
  "SettingsCenterScreen must not regain its duplicate QR/Desktop Login application state machine."
keyboard_shortcut_owner_count="$(grep -Ec 'private browserKeyboardShortcutCoordinator: BrowserKeyboardShortcutCoordinator' \
  "${SHELL_PAGE}" || true)"
if [ "${keyboard_shortcut_owner_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must compose exactly one Keyboard Shortcut narrative owner."
fi
keyboard_shortcut_shell_callback_count="$(awk '
  /export interface BrowserKeyboardShortcutShell/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /=>/ { callbacks += 1 }
  END { print callbacks + 0 }
' "${KEYBOARD_SHORTCUT_COORDINATOR}")"
if [ "${keyboard_shortcut_shell_callback_count}" -ne 6 ]; then
  report_failure "${KEYBOARD_SHORTCUT_COORDINATOR_REL} must keep exactly 6 variable-fact/UI-effect callbacks; found ${keyboard_shortcut_shell_callback_count}."
fi
check_file_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'handleShortcut\(action: BrowserKeyboardShortcutAction\)' \
  "Keyboard Shortcut owner must expose one ordinary shortcut entry."
check_file_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'handleNumberedShortcut\(digit: number\)' \
  "Keyboard Shortcut owner must expose one numbered-tab shortcut entry."
check_file_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'releaseAddressFocus\(\): void' \
  "Keyboard Shortcut owner must retain the shared semantic address-focus release entry."
check_file_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'recentActionManager\.recordOperate\(\)' \
  "Keyboard Shortcut owner must record keyboard activity without a page wrapper."
check_file_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'foregroundTabCreationCoordinator: BrowserForegroundTabCreationCoordinator' \
  "Keyboard Shortcut owner must compose Foreground Tab Creation directly."
check_file_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'fullscreenSessionCoordinator: BrowserFullscreenSessionCoordinator' \
  "Keyboard Shortcut owner must compose Fullscreen directly."
check_file_not_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'openNewTab: \(\) => void|openPageFind: \(\) => void|setFullScreenEnabled:|releaseHomeAddressFocus:|releaseWebAddressFocus:' \
  "Keyboard Shortcut shell must not regain fixed-owner or peer address-release callbacks."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "\.keyboardShortcut\('t'.*" \
  "BrowserShellPage must keep ArkUI keyboard shortcut bindings explicit."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "browserKeyboardShortcutCoordinator\.handleShortcut\('openNewTab'\)" \
  "ArkUI shortcut bindings must forward directly to the Keyboard narrative owner."
check_file_not_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'BrowserShortcutViewModel|BrowserKeyboardShortcutHostAdapter|BrowserKeyboardShortcutHost|BrowserKeyboardShortcutTabActionHost|BrowserKeyboardShortcutSurfaceHost|focusAddressBarFromShortcut\(|toggleTabsOverviewFromShortcut\(' \
  "Keyboard Shortcut owner must not regain the deleted ViewModel, pass-through Adapter, peer Hosts, or low-level public entry points."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserShortcutViewModel|BrowserKeyboardShortcutHostAdapter|BrowserKeyboardShortcutHost|BrowserKeyboardShortcutTabActionHost|BrowserKeyboardShortcutSurfaceHost|browserKeyboardShortcutHost|browserKeyboardShortcutTabActionHost|browserKeyboardShortcutSurfaceHost|private buildKeyboardShortcutContext\(|private handleKeyboardShortcut\(|private handleNumberedTabShortcut\(|focusAddressBarFromShortcut\(|toggleTabsOverviewFromShortcut\(' \
  "BrowserShellPage must not regain Keyboard policy, circular Host wiring, or wrapper entry points."
if [ -e "${OLD_SHORTCUT_VIEW_MODEL}" ]; then
  report_failure "${OLD_SHORTCUT_VIEW_MODEL_REL} must stay deleted; Keyboard eligibility and message policy belong inside the narrative owner."
fi
page_find_shell_callback_count="$(awk '
  /export interface BrowserPageFindControllerHost/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /=>/ { callbacks += 1 }
  END { print callbacks + 0 }
' "${PAGE_FIND_COORDINATOR}")"
if [ "${page_find_shell_callback_count}" -ne 4 ]; then
  report_failure "${PAGE_FIND_COORDINATOR_REL} must keep exactly four controller/publication/status shell callbacks."
fi
page_find_shell_snapshot_count="$(grep -Ec '@State pageFindBarState: BrowserPageFindBarState' "${SHELL_PAGE}" || true)"
if [ "${page_find_shell_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Page Find bar snapshot."
fi
page_find_offline_snapshot_count="$(grep -Ec '@State pageFindBarState: BrowserPageFindBarState' "${OFFLINE_PAGE_VIEWER}" || true)"
if [ "${page_find_offline_snapshot_count}" -ne 1 ]; then
  report_failure "${OFFLINE_PAGE_VIEWER_REL} must observe exactly one first-level Page Find bar snapshot."
fi
check_file_contains_rule "${PAGE_FIND_COORDINATOR}" "${PAGE_FIND_COORDINATOR_REL}" \
  'publishBarState\(tabId: string\)' \
  "Page Find must publish presentation after canonical state transitions."
check_file_contains_rule "${PAGE_FIND_COORDINATOR}" "${PAGE_FIND_COORDINATOR_REL}" \
  'handleActiveTabChanged\(tabId: string\)' \
  "Page Find must expose one semantic active-tab presentation entry."
check_file_contains_rule "${PAGE_FIND_COORDINATOR}" "${PAGE_FIND_COORDINATOR_REL}" \
  'handleBarAction\(tabId: string, action: BrowserPageFindBarAction\)' \
  "Page Find bar actions must enter through one typed owner action."
check_file_not_contains_rule "${PAGE_FIND_COORDINATOR}" "${PAGE_FIND_COORDINATOR_REL}" \
  'export interface BrowserPageFindTabState|[[:space:]]getState\(' \
  "Page Find canonical tab state must stay private to the narrative owner."
check_file_contains_rule "${PAGE_FIND_BAR}" "${PAGE_FIND_BAR_REL}" \
  "from '../../../core/browser/BrowserPageFindCoordinator'" \
  "Page Find bar must consume the owner-published presentation contract."
check_file_contains_rule "${PAGE_FIND_BAR}" "${PAGE_FIND_BAR_REL}" \
  'onAction: \(action: BrowserPageFindBarAction\)' \
  "Page Find bar must emit one typed action callback."
check_file_contains_rule "${PAGE_FIND_BAR}" "${PAGE_FIND_BAR_REL}" \
  'PAGE_FIND_LARGE_SCREEN_MAX_WIDTH: number = 440' \
  "Desktop Page Find must keep a compact maximum floating-bar width."
check_file_contains_rule "${PAGE_FIND_BAR}" "${PAGE_FIND_BAR_REL}" \
  "BrowserWindowRuntime\.resolveActiveShellPresentationSurface\(\) === 'large_screen'" \
  "Page Find floating width must follow the locked Window Session shell family."
check_file_contains_rule "${PAGE_FIND_BAR}" "${PAGE_FIND_BAR_REL}" \
  'maxWidth: this\.resolveFloatingBarMaxWidth\(\)' \
  "Page Find floating surface must apply its shell-aware maximum width."
check_file_not_contains_rule "${PAGE_FIND_BAR}" "${PAGE_FIND_BAR_REL}" \
  'onQueryChange:|onPrevious:|onNext:|onClose:' \
  "Page Find bar must not regain peer query/navigation callbacks."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserPageFindViewModel|browserPageFindViewModel|refreshPageFindBarState|refresh_page_find' \
  "BrowserShellPage must not regain Page Find projection or refresh sequencing."
check_file_not_contains_rule "${OFFLINE_PAGE_VIEWER}" "${OFFLINE_PAGE_VIEWER_REL}" \
  'BrowserPageFindViewModel|pageFindViewModel|refreshPageFindBarState' \
  "Offline Viewer must not regain duplicate Page Find projection or refresh sequencing."
check_file_not_contains_rule "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR}" \
  "${WEB_PAGE_FEATURE_EFFECTS_COORDINATOR_REL}" \
  'refreshPageFindBarState' \
  "Web Page Feature Effects must rely on the fixed Page Find owner publication."
check_file_contains_rule "${TAB_SWITCH_COORDINATOR}" "${TAB_SWITCH_COORDINATOR_REL}" \
  'resolvePageFindCoordinator: \(\) => BrowserPageFindCoordinator' \
  "Tab Switch must notify the fixed Page Find owner directly."
check_file_not_contains_rule "${TAB_SWITCH_COORDINATOR}" "${TAB_SWITCH_COORDINATOR_REL}" \
  'refresh_page_find' \
  "Tab Switch must not route Page Find refresh through a page platform action."
check_file_contains_rule "${WEB_HISTORY_COMMAND_COORDINATOR}" "${WEB_HISTORY_COMMAND_COORDINATOR_REL}" \
  'pageFindCoordinator: BrowserPageFindCoordinator' \
  "Web History Back must consume Page Find through the fixed owner dependency."
check_file_contains_rule "${WEB_HISTORY_COMMAND_COORDINATOR}" "${WEB_HISTORY_COMMAND_COORDINATOR_REL}" \
  'contextMenuCoordinator: WebLinkContextMenuCoordinator' \
  "Web History Back must consume Context Menu through the fixed owner dependency."
check_file_contains_rule "${WEB_HISTORY_COMMAND_COORDINATOR}" "${WEB_HISTORY_COMMAND_COORDINATOR_REL}" \
  'fullscreenSessionCoordinator: BrowserFullscreenSessionCoordinator' \
  "Web History Back must consume Fullscreen through the fixed owner dependency."
web_history_command_host_callback_count="$(awk '
  /export interface BrowserWebHistoryCommandRuntimeCoordinatorHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /^  [A-Za-z0-9_]+: \(/ { count += 1 }
' "${WEB_HISTORY_COMMAND_COORDINATOR}")"
if [ "${web_history_command_host_callback_count}" -ne 3 ]; then
  report_failure "${WEB_HISTORY_COMMAND_COORDINATOR_REL} must keep exactly 3 active-tab/presentation callbacks; found ${web_history_command_host_callback_count}."
fi
check_file_not_contains_rule "${WEB_HISTORY_COMMAND_COORDINATOR}" "${WEB_HISTORY_COMMAND_COORDINATOR_REL}" \
  'isPageFindVisibleForTab:|closePageFind:|isWebContextMenuVisibleForTab:|closeWebContextMenu:|isWebFullscreenActiveForTab:|disableWebFullscreen:' \
  "Web History Back must not regain Page Find, Context Menu, or Fullscreen page callbacks."
check_file_contains_rule "${PRIVATE_SESSION_CLEANUP_COORDINATOR}" \
  "${PRIVATE_SESSION_CLEANUP_COORDINATOR_REL}" \
  'resolvePageFindCoordinator\(\)\.clearPrivateTabs' \
  "Private cleanup must clear Page Find through the fixed owner dependency."
check_file_not_contains_rule "${PRIVATE_SESSION_CLEANUP_COORDINATOR}" \
  "${PRIVATE_SESSION_CLEANUP_COORDINATOR_REL}" \
  'clearPrivatePageFind:|getTabs: \(\) =>|hasPendingJsPrompt:|hasPendingHttpAuth:|hasActiveDownloadPromptLease:|resolveExternalNavigationUrl:|resolveSitePermissionRelatedOriginCount:|resolvePersistedEphemeralSnapshotPaths:|readPreserveCookiesOnClose:|clearPendingJsPrompt:|clearPendingHttpAuth:|releaseActiveDownloadPromptLease:|clearPendingDownloadPrompt:|clearExternalNavigationState:|clearSitePermissionRelatedOrigins:|clearPrivateSessionSiteData:|clearPrivateDownloads:|clearPrivatePreviews:|clearPrivateSnapshots:|clearSessionSitePermissions:' \
  "Private cleanup must not regain Page Find or fixed owner/service forwarding callbacks."
private_session_cleanup_shell_callback_count="$(awk '
  /export interface BrowserPrivateSessionCleanupShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /^  [A-Za-z0-9_]+: \(/ { count += 1 }
' "${PRIVATE_SESSION_CLEANUP_COORDINATOR}")"
if [ "${private_session_cleanup_shell_callback_count}" -ne 2 ]; then
  report_failure "${PRIVATE_SESSION_CLEANUP_COORDINATOR_REL} must keep exactly 2 current-facts/preview-invalidation callbacks; found ${private_session_cleanup_shell_callback_count}."
fi
check_file_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'pageFindCoordinator: BrowserPageFindCoordinator' \
  "Keyboard shortcuts must use the fixed Page Find owner for visibility and close."
check_file_not_contains_rule "${KEYBOARD_SHORTCUT_COORDINATOR}" "${KEYBOARD_SHORTCUT_COORDINATOR_REL}" \
  'pageFindVisible: boolean|setPageFindVisible' \
  "Keyboard shortcuts must not regain Page Find state or bidirectional command callbacks."
if [ -e "${OLD_PAGE_FIND_VIEW_MODEL}" ]; then
  report_failure "${OLD_PAGE_FIND_VIEW_MODEL_REL} must stay deleted; Page Find projection belongs inside the narrative owner."
fi
web_app_session_snapshot_count="$(grep -Ec '@State webAppSessionSnapshot: WebAppSessionSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${web_app_session_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level WebApp Session snapshot."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'webAppChromeContext|activeWebAppDefaultFullscreen|refreshActiveWebAppSettings|activateWebAppContextFromPayload|WebAppImmersiveModeCoordinator|DesktopWebLaunchPayload|sharedWebAppInstallRepository|private desktopWebEntryLaunchService|new DesktopWebEntryLaunchService' \
  "BrowserShellPage must not regain split WebApp state, repository hydration, launch preparation, or the deleted shallow owners."
check_file_contains_rule "${WEB_APP_SESSION_COORDINATOR}" "${WEB_APP_SESSION_COORDINATOR_REL}" \
  'class WebAppSessionSnapshot' \
  "WebApp Session must publish one atomic per-window context/settings snapshot."
check_file_contains_rule "${WEB_APP_SESSION_COORDINATOR}" "${WEB_APP_SESSION_COORDINATOR_REL}" \
  'async prepareLaunch\(' \
  "WebApp Session must own launch preparation behind one public entry."
check_file_contains_rule "${WEB_APP_SESSION_COORDINATOR}" "${WEB_APP_SESSION_COORDINATOR_REL}" \
  'requestGenerationByWindowId' \
  "WebApp Session must gate async launch/settings hydration by window generation."
check_file_contains_rule "${WEB_APP_SESSION_COORDINATOR}" "${WEB_APP_SESSION_COORDINATOR_REL}" \
  'buildImmersiveVisualState\(' \
  "WebApp immersive projection must stay subordinate to the Session owner."
check_file_contains_rule "${WINDOW_CONTEXT_COORDINATOR}" "${WINDOW_CONTEXT_COORDINATOR_REL}" \
  'webAppSessionCoordinator\.refreshSettings\(windowId\)' \
  "Window Context must refresh WebApp settings through the fixed Session owner."
check_file_not_contains_rule "${WINDOW_CONTEXT_COORDINATOR}" "${WINDOW_CONTEXT_COORDINATOR_REL}" \
  'refreshWebAppSettings|WebAppActiveContext' \
  "Window Context must not make BrowserShell interpret WebApp context/settings refresh ordering."
check_file_contains_rule "${WEB_APP_EXIT_COORDINATOR}" "${WEB_APP_EXIT_COORDINATOR_REL}" \
  'sessionCoordinator\.getActive\(request\.windowId\)' \
  "WebApp Exit must resolve the active context from its fixed Session dependency."
check_file_not_contains_rule "${WEB_APP_EXIT_COORDINATOR}" "${WEB_APP_EXIT_COORDINATOR_REL}" \
  'activeContext: WebAppActiveContext \| undefined|applySessionClearedPresentation' \
  "WebApp Exit must not receive canonical context or field-level presentation clearing from BrowserShell."
if [ -e "${WEB_APP_SCOPE_OUT_COORDINATOR}" ]; then
  report_failure "${WEB_APP_SCOPE_OUT_COORDINATOR_REL} must stay deleted; its only remaining behavior was an unused runtime-event seam followed by false."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserWebAppScopeOutNavigationCoordinator|browserWebAppScopeOutNavigationCoordinator|browserWebAppScopeOutNavigationHost' \
  "BrowserShellPage must not restore the deleted WebApp Scope-out no-op middleman."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'handleWebAppScopeOutNavigation: \(_tabId: string, _url: string, _isMainFrame: boolean\): boolean => false' \
  "BrowserShellPage must keep the existing non-consuming WebApp Scope-out result without a diagnostic-only owner."
if [ -e "${OLD_WEB_APP_IMMERSIVE_COORDINATOR}" ]; then
  report_failure "${OLD_WEB_APP_IMMERSIVE_COORDINATOR_REL} must stay deleted; immersive projection belongs inside WebApp Session."
fi
if [ -e "${OLD_WEB_APP_LAUNCH_COORDINATOR}" ]; then
  report_failure "${OLD_WEB_APP_LAUNCH_COORDINATOR_REL} must stay deleted; DTO-only launch plumbing belongs inside WebApp Session."
fi
recently_closed_snapshot_count="$(grep -Ec '@State recentlyClosedApplicationSnapshot: BrowserRecentlyClosedApplicationSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${recently_closed_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Recently Closed application snapshot."
fi
recently_closed_owner_count="$(grep -Ec 'private browserRecentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator' \
  "${SHELL_PAGE}" || true)"
if [ "${recently_closed_owner_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must compose exactly one Recently Closed narrative owner."
fi
recently_closed_shell_callback_count="$(awk '
  /export interface BrowserRecentlyClosedApplicationShell/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /=>/ { callbacks += 1 }
  END { print callbacks + 0 }
' "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}")"
if [ "${recently_closed_shell_callback_count}" -gt 10 ]; then
  report_failure "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL} must keep the Recently Closed shell at no more than 10 variable-fact/UI-effect callbacks."
fi
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'recordCount: number' \
  "Recently Closed must expose a render-safe count instead of leaking all canonical records into page state."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'recordClosedTab\(' \
  "Recently Closed owner must own close-to-record mutation and persistence."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'activateWindow\(' \
  "Recently Closed owner must reload its window/profile records through one activation entry."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'prepareRestoreByRecordId\(' \
  "Recently Closed owner must prepare typed single-record restore results."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'removeRecordsForHost\(' \
  "Recently Closed owner must hide host-filtered record mutation behind one semantic entry."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'loadForStartup\(' \
  "Recently Closed owner must hide startup load flags behind one semantic entry."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'flushForWindowSwitch\(' \
  "Recently Closed owner must expose a semantic window-switch flush instead of generic persistence wiring."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'private primeGeneration: number' \
  "Recently Closed prime generation must stay owner-held."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'private mutationGeneration: number' \
  "Recently Closed mutation generation must stay owner-held."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  'private sectionRebuildTimer: number' \
  "Recently Closed remount timer must stay owner-held."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserRecentlyClosedPersistence|BrowserRecentlyClosedRecordAction|BrowserRecentlyClosedSheet|recentlyClosedTabs|recentlyClosedPrimeGeneration|recentlyClosedMutationGeneration|recentlyClosedOverlayGeneration|homeRecentlyClosedSectionRebuildGeneration|homeRecentlyClosedSectionMounted|homeRecentlyClosedExpanded|homeRecentlyClosedLimit|homeRecentlyClosedIcons|showRecentlyClosedSheet|recentlyClosedSheetVisible|applyRecentlyClosedTabs|restoreAllRecentlyClosed|copyRecentlyClosedRecordUrl|deleteRecentlyClosedRecord|toggleRecentlyClosedHomeShortcut|refreshAfterRuntimeReady' \
  "BrowserShellPage must not regain Recently Closed records, generations, timers, dead Sheet state, action policy, or persistence sequencing."
check_file_not_contains_rule "${TAB_CLOSE_COORDINATOR}" "${TAB_CLOSE_COORDINATOR_REL}" \
  'recentlyClosedRecords|applyRecentlyClosedRecords|resolveRecentlyClosedPersistenceCoordinator|BrowserRecentlyClosedPersistenceCoordinator|new BrowserRecentlyClosedTabsService' \
  "Tab Close must use the Recently Closed owner instead of reading records or composing persistence/service peers."
check_file_contains_rule "${TAB_CLOSE_COORDINATOR}" "${TAB_CLOSE_COORDINATOR_REL}" \
  'recentlyClosedApplicationCoordinator\.buildRestoreBoundaryDecision\(' \
  "Tab Close must ask the Recently Closed owner to enforce restore privacy for both Home and keyboard entries."
check_file_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  "resolveDataPolicy\('recently_closed_tab'" \
  "the Recently Closed owner must enforce its persistent read/write policy at action seams."
check_file_contains_rule "${WINDOW_CONTEXT_COORDINATOR}" "${WINDOW_CONTEXT_COORDINATOR_REL}" \
  'recentlyClosedApplicationCoordinator\.activateWindow\(' \
  "live window-context restoration must reactivate Recently Closed records before new close mutations."
check_file_contains_rule "${SITE_CLEAR_ON_CLOSE_COORDINATOR}" "${SITE_CLEAR_ON_CLOSE_COORDINATOR_REL}" \
  'removeRecordsForHost\(targetHost\)' \
  "Site Clear must request one semantic Recently Closed mutation instead of reading and rewriting owner state."
check_file_not_contains_rule "${SITE_CLEAR_ON_CLOSE_COORDINATOR}" "${SITE_CLEAR_ON_CLOSE_COORDINATOR_REL}" \
  'getRecentlyClosedRecords|resolveRecentlyClosedRecordUrl|applyRecentlyClosedRecords|persistRecentlyClosedRecords|getRecords\(|replaceRecordsAfterSiteClear' \
  "Site Clear must not regain Recently Closed record or persistence callbacks."
check_file_contains_rule "${HOME_CONTENT_SECTIONS}" "${HOME_CONTENT_SECTIONS_REL}" \
  'onAction: \(action: BrowserTabHomeContentAction\)' \
  "Home content must expose one typed Tab Home action callback."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'handleContentAction\(action: BrowserTabHomeContentAction\)' \
  "Home content actions must enter through the Tab Home owner."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'private readonly homeChromeScrollCoordinator: BrowserHomeChromeScrollCoordinator' \
  "Home Scroll policy, native offset state, and decisions must stay inside one coordinator under the Tab Home owner."
check_file_contains_rule "${HOME_CONTENT_SECTIONS}" "${HOME_CONTENT_SECTIONS_REL}" \
  "scrollAtEnd: this\.homeContentScroller\.isAtEnd\(\)" \
  "Native Home content must forward raw offset/end samples instead of owning chrome policy or bounce state."
check_file_contains_rule "${HOME_CONTENT_SECTIONS}" "${HOME_CONTENT_SECTIONS_REL}" \
  "type: 'scroll_stop'" \
  "Native Home content must tell the Home Chrome Scroll owner when native scrolling stops."
check_file_not_contains_rule "${HOME_CONTENT_SECTIONS}" "${HOME_CONTENT_SECTIONS_REL}" \
  'BrowserHomeChromeScrollCoordinator|BrowserHomeScrollChromeViewModel|resolveNativeHomeScrollOffset|finishNativeHomeScroll' \
  "Home content must remain a raw Scroll adapter and must not regain Home Chrome Scroll ownership."
check_file_not_contains_rule "${HOME_CONTENT_SECTIONS}" "${HOME_CONTENT_SECTIONS_REL}" \
  '^  on(ExitPrivateMode|ShortcutAction|OpenShortcutAddEntry|RecentlyClosedAction|RestoreRecentlyClosedRecord|OpenHomeSettings|HomeScroll):' \
  "Home content must not regain peer action callbacks."
check_file_contains_rule "${HOME_RECENTLY_CLOSED_SECTION}" "${HOME_RECENTLY_CLOSED_SECTION_REL}" \
  'onAction: \(action: BrowserRecentlyClosedUserAction\)' \
  "Recently Closed Home section must forward one typed action callback."
check_file_contains_rule "${RECENTLY_CLOSED_RECORD_LIST}" "${RECENTLY_CLOSED_RECORD_LIST_REL}" \
  'onAction: \(action: BrowserRecentlyClosedUserAction\)' \
  "Recently Closed record list must emit one typed action callback."
check_file_contains_rule "${RECENTLY_CLOSED_RECORD_LIST}" "${RECENTLY_CLOSED_RECORD_LIST_REL}" \
  'onRestoreRecord: \(recordId: string\)' \
  "Recently Closed record list must keep restore as one distinct Tab Close event."
check_file_not_contains_rule "${HOME_CONTENT_SECTIONS}" "${HOME_CONTENT_SECTIONS_REL}" \
  'onToggleRecentlyClosed|onCopyRecentlyClosedUrl|onDeleteRecentlyClosed|onToggleRecentlyClosedHomeShortcut' \
  "Home content must not regain parallel Recently Closed callback wiring."
check_file_not_contains_rule "${HOME_RECENTLY_CLOSED_SECTION}" "${HOME_RECENTLY_CLOSED_SECTION_REL}" \
  'onCopyRecordUrl:|onDeleteRecord:|onToggleHomeShortcut:' \
  "Recently Closed Home section must not regain parallel action callbacks."
check_file_not_contains_rule "${RECENTLY_CLOSED_RECORD_LIST}" "${RECENTLY_CLOSED_RECORD_LIST_REL}" \
  'onCopyRecordUrl:|onDeleteRecord:|onToggleHomeShortcut:' \
  "Recently Closed record list must not regain parallel action callbacks."
check_file_not_contains_rule "${RECENTLY_CLOSED_APPLICATION_COORDINATOR}" \
  "${RECENTLY_CLOSED_APPLICATION_COORDINATOR_REL}" \
  "restoreRecord: \(recordId: string\) => void|'restore_record'" \
  "Recently Closed management owner must not route restore through BrowserShell back into Tab Close."
if [ -e "${OLD_RECENTLY_CLOSED_PERSISTENCE_COORDINATOR}" ]; then
  report_failure "${OLD_RECENTLY_CLOSED_PERSISTENCE_COORDINATOR_REL} must stay deleted; persistence belongs inside the Recently Closed application owner."
fi
if [ -e "${OLD_RECENTLY_CLOSED_RECORD_ACTION_COORDINATOR}" ]; then
  report_failure "${OLD_RECENTLY_CLOSED_RECORD_ACTION_COORDINATOR_REL} must stay deleted; record actions belong inside the Recently Closed application owner."
fi
if [ -e "${OLD_RECENTLY_CLOSED_SHEET}" ]; then
  report_failure "${OLD_RECENTLY_CLOSED_SHEET_REL} must stay deleted; the unreachable Recently Closed Sheet flow must not return."
fi
home_shortcut_snapshot_count="$(grep -Ec '@State homeShortcutApplicationSnapshot: HomeShortcutApplicationSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${home_shortcut_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Home Shortcut application snapshot."
fi
home_shortcut_edit_draft_count="$(grep -Ec '@State homeShortcutEditDraft: HomeShortcutEditDraft' \
  "${SHELL_PAGE}" || true)"
if [ "${home_shortcut_edit_draft_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must keep Home Shortcut edit input as one explicit reactive draft."
fi
home_shortcut_owner_count="$(grep -Ec 'private homeShortcutStateCoordinator: HomeShortcutStateCoordinator' \
  "${SHELL_PAGE}" || true)"
if [ "${home_shortcut_owner_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must compose exactly one Home Shortcut narrative owner."
fi
home_shortcut_shell_callback_count="$(awk '
  /export interface HomeShortcutApplicationShell/ { in_shell = 1; next }
  in_shell && /^}/ { in_shell = 0 }
  in_shell && /=>/ { callbacks += 1 }
  END { print callbacks + 0 }
' "${HOME_SHORTCUT_STATE_COORDINATOR}")"
if [ "${home_shortcut_shell_callback_count}" -gt 5 ]; then
  report_failure "${HOME_SHORTCUT_STATE_COORDINATOR_REL} must keep the Home Shortcut shell at no more than 5 facts/snapshot/effect callbacks."
fi
check_file_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  'effectApplication\.apply\(' \
  "Home Shortcut owner must apply presentation effects through one subordinate application."
check_file_contains_rule "${HOME_SHORTCUT_EFFECT_APPLICATION}" "${HOME_SHORTCUT_EFFECT_APPLICATION_REL}" \
  'class HomeShortcutFixedEffectApplication implements HomeShortcutEffectApplication' \
  "Home Shortcut presentation effects must stay behind the subordinate application."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private executeHomeShortcutApplicationEffect\(|executeEffect: \(effect: HomeShortcutApplicationEffect\)' \
  "BrowserShellPage must not regain Home Shortcut effect interpretation."
home_shortcut_effect_shell_callback_count="$(awk '
  /export interface HomeShortcutEffectApplicationShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${HOME_SHORTCUT_EFFECT_APPLICATION}")"
if [ "${home_shortcut_effect_shell_callback_count}" -ne 8 ]; then
  report_failure "${HOME_SHORTCUT_EFFECT_APPLICATION_REL} Shell must keep exactly eight Home Shortcut UI/platform callbacks; found ${home_shortcut_effect_shell_callback_count}."
fi
check_file_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  'private readonly selectionCoordinator: HomeShortcutSelectionCoordinator' \
  "Home Shortcut Selection must remain subordinate to the single Home Shortcut owner."
check_file_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  'openSelectionSession\(\): void' \
  "Home Shortcut owner must expose one semantic Selection open entry."
check_file_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  'handleSelectionAction\(action: HomeShortcutSelectionAction\): void' \
  "Home Shortcut owner must expose one typed Selection action entry."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'HomeShortcutSelectionHost|homeShortcutSelectionCoordinator|homeShortcutSelectionHost|private allowPersistentWrite\(' \
  "BrowserShellPage must not regain the peer Selection owner, fixed Host, or private-write policy."
check_file_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  'handleUserAction.*HomeShortcutUserAction' \
  "Home Shortcut application flow must expose one typed ordinary user-action entry."
check_file_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  'private loadGeneration: number' \
  "Home Shortcut async load ordering must stay owner-held."
check_file_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  'private persistQueue: HomeShortcutPersistBatch\[\]' \
  "Home Shortcut mutation persistence and recovery must stay owner-held."
check_file_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  'private readonly iconHydrationCoordinator: HomeShortcutIconHydrationCoordinator' \
  "Home Shortcut icon hydration must stay inside the application owner."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" \
  "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'shortcutStateCoordinator\.bindCustomHomepageRuntime\(this\)' \
  "Custom Homepage runtime must bind directly to the Home Shortcut owner instead of routing fixed sync through BrowserShell."
check_file_not_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  "sync_custom_homepage|'refresh_consumers'" \
  "Home Shortcut fixed downstream consumers must not return as BrowserShell-interpreted effects."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "sync_custom_homepage|'refresh_consumers'" \
  "BrowserShellPage must not interpret fixed Home Shortcut downstream-owner effects."
check_file_contains_rule "${HOME_SHORTCUT_ICON_HYDRATION_COORDINATOR}" \
  "${HOME_SHORTCUT_ICON_HYDRATION_COORDINATOR_REL}" \
  'persistResolvedIcon: \(shortcutId: string, sourceUrl: string, iconPath: string\)' \
  "Home Shortcut icon hydration must retain the source URL for stale-write rejection."
check_file_contains_rule "${SHORTCUT_REPOSITORIES}" "${SHORTCUT_REPOSITORIES_REL}" \
  'updateShortcutIcon\(id: string, expectedUrl: string, icon: string\)' \
  "Shortcut icon persistence must require the source URL as a compare-and-set condition."
check_file_contains_rule "${BROWSER_DATABASE}" "${BROWSER_DATABASE_REL}" \
  "predicates\.equalTo\('url', expectedUrl\)" \
  "Shortcut icon database writes must reject a stale source URL."
check_file_not_contains_rule "${HOME_SHORTCUT_STATE_COORDINATOR}" "${HOME_SHORTCUT_STATE_COORDINATOR_REL}" \
  'HomeShortcutMutationHost|loadHomeShortcutsForScenario\(|replaceHomeShortcutByIdAndPersist\(|removeHomeShortcutByIdAndPersist\(|moveHomeShortcutByIdAndPersist\(|moveHomeShortcutByIdStepAndPersist\(|reorderHomeShortcutsByIdListAndPersist\(' \
  "Home Shortcut owner must not regain per-call mutation Hosts or low-level public mutation entries."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'HomeShortcutMutationHost|homeShortcutMutationHost|homeShortcutIconHydrationCallbacks|homeShortcutIconHydrationCoordinator|homeShortcutIconsVersion|homeShortcutLayoutVersion|homeShortcutGroupId|editingHomeShortcut|handleHomeShortcutContextAction|openEditHomeShortcutDialog|confirmEditHomeShortcut|confirmDeleteHomeShortcut|deleteHomeShortcut|moveHomeShortcutToBoundary|moveHomeShortcutByStep|loadHomeShortcuts\(|refreshHomeShortcutsAfterMutation\(' \
  "BrowserShellPage must not regain Home Shortcut records, drafts, icon/load/mutation ownership, or title-driven dispatch."
check_file_contains_rule "${HOME_FAVORITES_SECTION}" "${HOME_FAVORITES_SECTION_REL}" \
  'onShortcutAction: \(action: HomeShortcutUserAction\)' \
  "Home Favorites must forward one typed Home Shortcut action callback."
check_file_contains_rule "${HOME_SHORTCUT_SURFACE}" "${HOME_SHORTCUT_SURFACE_REL}" \
  'onAction: \(action: HomeShortcutUserAction\)' \
  "Home Shortcut surface must emit one typed action callback."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserHomeScrollChromeViewModel[,;]|browserHomeScrollChromeViewModel|homeScrollHideAllowed|homeSearchEligible|private handleHomeContentScroll\(' \
  "BrowserShellPage must not regain Home Scroll chrome state or decision dispatch."
check_file_not_contains_rule "${HOME_SHORTCUT_SURFACE}" "${HOME_SHORTCUT_SURFACE_REL}" \
  'onOpenShortcut:|onContextAction:|onMoveShortcut:|onAction\(shortcut, item\.title\)' \
  "Home Shortcut surface must not regain parallel callbacks or title-based application dispatch."
check_file_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR}" \
  "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR_REL}" \
  'shortcutStateCoordinator\.handleUserAction\(' \
  "Custom Homepage shortcut requests must enter the shared typed Home Shortcut owner directly."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR}" \
  "${CUSTOM_HOMEPAGE_BRIDGE_COORDINATOR_REL}" \
  'HomeShortcutMutationHost|shortcutMutationHost|allowShortcutRemoval|move_shortcut_by_step|handle_shortcut_context_action' \
  "Custom Homepage bridge must not regain the deleted mutation Host or BrowserShell shortcut round trips."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" \
  "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'HomeShortcutMutationHost|shortcutMutationHost|allowShortcutRemoval|move_shortcut_by_step|handle_shortcut_context_action' \
  "Custom Homepage runtime must not regain the deleted Home Shortcut mutation wiring or shell effects."
if [ ! -e "${HOME_SHORTCUT_OPEN_COORDINATOR}" ]; then
  report_failure "${HOME_SHORTCUT_OPEN_COORDINATOR_REL} must keep Home Shortcut open orchestration under core ownership."
fi
if [ -e "${OLD_HOME_SHORTCUT_OPEN_COORDINATOR}" ]; then
  report_failure "${OLD_HOME_SHORTCUT_OPEN_COORDINATOR_REL} must stay deleted; Home Shortcut open orchestration is not a services-layer policy module."
fi
check_file_contains_rule "${CUSTOM_HOMEPAGE_DEVELOPER_GUIDE}" "${CUSTOM_HOMEPAGE_DEVELOPER_GUIDE_REL}" \
  'openShortcutPicker\(\): void' \
  "custom-home developer guide must document the native shortcut picker method."
check_file_contains_rule "${CUSTOM_HOMEPAGE_DEVELOPER_GUIDE}" "${CUSTOM_HOMEPAGE_DEVELOPER_GUIDE_REL}" \
  'kind: .web. \| .system.' \
  "custom-home developer guide must document the concise shortcut kind field."
check_file_not_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'hostWidth|viewportWidth' \
  "bottom panel Session state must not carry horizontal responsive geometry."
check_file_not_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'preserveAddressPanelIdentity' \
  "bottom panel Session state must not treat address focus as a component-identity policy."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'semanticRenderKey:|panelRenderKey:|preserveAddressPanelIdentity:|buildPanelRenderKey\(' \
  "root bottom panel shell must not wire transient presentation facts into component identity."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'rootBottomPanelMeasuredHost|resolveBottomPanelEffectiveViewportState|resolveMeasuredViewportState' \
  "root bottom panel shell must not arbitrate between root and retained Host geometry."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'updateLayoutHostViewport|bottom_panel_host_area' \
  "root bottom panel shell must not use Host measurements or diagnostic logs as responsive geometry authority."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'buildLayoutState' \
  "root bottom panel session owner must expose the single responsive layout path."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'resolveActivePanelHeight' \
  "root bottom panel session owner must select the active panel height from typed layout state."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'resolveActiveHostHeight' \
  "root bottom panel session owner must select the active overlay-host height from typed layout state."
check_file_not_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'BrowserRootBottomPanelHeightInput|resolveHeight\(' \
  "root bottom panel layout interface must not expose stale generic tabs-height inputs."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private (buildRootBottomPanelLayoutState|getWebBottomAddressPanelHeight|resolveHomeSearchHostHeight|buildBottomPanelResponsiveState|getHomeSearchSheetHeight|resolveTabsBottomPanelHostHeight|resolveWebViewportHostHeight|resolveWebBottomPanelHostHeight)\(' \
  "BrowserShellPage must bind the typed Root Bottom Panel layout state without scalar projection aliases."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'buildMotionState' \
  "root bottom panel session owner must build the typed bottom-panel motion presentation."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'this\.buildRootBottomPanelMotionState\(\),' \
  "BrowserShellPage must bind one owner-built Root Bottom Panel motion state into the live presentation."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'panelMotionState: \{|private (resolveRootBottomPanelRequestedDetent|resolveRootBottomPanelHeight|resolveRootBottomPanelOverlayHostHeight|resolveRootBottomPanelDetentDragEnabled|resolveRootBottomPanelPeekEnabled|resolveRootBottomPanelPeekGestureEnabled)\(' \
  "BrowserShellPage must not regain scalar Root Bottom Panel motion composition helpers."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'suppressExpandedContentFromDrag:' \
  "BrowserShellPage must not decide Root Bottom Panel drag-suppression motion policy."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'suppressExpandedContentFromDrag: this\.presentationSnapshot\.returnHomeGestureActive' \
  "root bottom panel session owner must derive drag-suppression policy from its presentation snapshot."
check_file_contains_rule "${BOTTOM_PANEL_MOTION_TOKENS}" "${BOTTOM_PANEL_MOTION_TOKENS_REL}" \
  'BROWSER_BOTTOM_PANEL_PEEK_TO_LOW_ANIMATION_DURATION_MS' \
  "Root Bottom Panel peek-to-low motion duration must stay in the core motion-token owner."
check_file_contains_rule "${BOTTOM_PANEL_MOTION_TOKENS}" "${BOTTOM_PANEL_MOTION_TOKENS_REL}" \
  'BROWSER_BOTTOM_PANEL_COLLAPSE_TO_PEEK_ANIMATION_DURATION_MS' \
  "Root Bottom Panel collapse-to-peek motion duration must stay in the core motion-token owner."
check_file_not_contains_rule "${SHELL_PRESENTATION_TOKENS}" "${SHELL_PRESENTATION_TOKENS_REL}" \
  'TABS_OVERVIEW_PANEL_PEEK_TO_LOW_ANIMATION_MS|ROOT_BOTTOM_PANEL_COLLAPSE_TO_PEEK_ANIMATION_MS' \
  "Root Bottom Panel motion durations must not return to app presentation tokens."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'async toggleThemeModeFromBottomPanel' \
  "Tab Home must own the complete bottom-panel theme-mode mutation flow."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'resolveOptimisticThemeMode' \
  "Tab Home must own optimistic theme-mode resolution for Home and bottom-panel presentation."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private (resolveOptimisticThemeMode|toggleThemeModeFromBottomPanel|bumpThemeModeActionVersion)\(' \
  "BrowserShellPage must not own theme-mode resolution, mutation, or action-version helper methods."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'setThemeModeForBoundary|resolveNextMode' \
  "BrowserShellPage must not orchestrate theme-mode mutation policy."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'optimisticThemeMode: this\.browserTabHomeCoordinator\.resolveOptimisticThemeMode\(\)' \
  "BrowserShellPage must read optimistic theme mode through the Tab Home owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'this\.isCollapsedDetent\(detent\) && this\.pendingActionAfterCollapsedSettle' \
  "Root Bottom Panel pending actions must transfer after any valid collapsed detent settles."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  "return detent === 'low' \\|\\| detent === 'peek';" \
  "Root Bottom Panel collapsed-settle policy must include both low and peek terminals."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'BROWSER_TRANSIENT_SURFACE_MOUNT_FRAME_DELAY_MS' \
  "Transient bottom surfaces must mount hidden for at least one frame before reveal."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'Math\.max\(BROWSER_TRANSIENT_SURFACE_MOUNT_FRAME_DELAY_MS, request\.revealDelayMs\)' \
  "Transient bottom surface reveal must preserve the owner-held mount-then-reveal lifecycle."
check_file_not_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'revealImmediately' \
  "Transient bottom surfaces must not skip their hidden mounted frame."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'activeCustomBottomSurfaceVisible: boolean' \
  "Transient Surface snapshot must expose active custom-surface visibility as reactive presentation state."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserTransientSurfaceCoordinator\.isVisible' \
  "BrowserShellPage must bind transient visibility from the reactive owner snapshot instead of querying coordinator internals."
browser_shell_bind_sheet_count="$(grep -c '\.bindSheet' "${SHELL_PAGE}" || true)"
if [ "${browser_shell_bind_sheet_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must keep exactly one shared bindSheet host; found ${browser_shell_bind_sheet_count}."
fi
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  "return 'userScriptPageActions';" \
  "UserScript Page Actions must map through the shared system Sheet host."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  "return 'appProxyQuick';" \
  "App Proxy Quick must map through the shared system Sheet host."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  "return 'resourceCandidates';" \
  "Page Resources must map through the shared system Sheet host."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'private systemSheetClosingType: BrowserSystemSheetType' \
  "Shared system Sheet lifecycle must retain the closing identity until onDisappear."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'private pendingSystemHostedPresentation: BrowserPendingSystemHostedPresentation' \
  "Shared system Sheet lifecycle must serialize reopen and replacement requests behind dismissal."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'const disappearingType = this\.systemSheetClosingType' \
  "Shared system Sheet cleanup must use the captured closing identity instead of mutable content state."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'handleSystemSheetWillDisappear\(\): void' \
  "Shared system Sheet lifecycle must capture native dismissal before onDisappear cleanup."
check_file_not_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'if \(bindingVisible\)' \
  "Shared system Sheet onDisappear must not treat the still-true bindSheet input as proof that the host remains visible."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserTransientSurfaceCoordinator\.handleSystemSheetWillDisappear\(\)' \
  "BrowserShellPage must forward native onWillDisappear to the transient surface owner."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'private beginSystemSheetHostResetForSurface\(' \
  "Shared system Sheet reset must retain the closing identity until the native exit finishes."
check_file_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'this\.closeCurrentSystemSheetForHostedReplacement\(\);' \
  "A toolbar Sheet queued behind another system Sheet must start the current host dismissal."
check_file_not_contains_rule "${TRANSIENT_SURFACE_COORDINATOR}" "${TRANSIENT_SURFACE_COORDINATOR_REL}" \
  'clearSystemSheetHostForSurface' \
  "Shared system Sheet reset must not mark the native host idle before onDisappear."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserToolbarSystemSheetContent' \
  "BrowserShellPage must mount toolbar Sheet content through the shared system Sheet renderer."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'UserScriptPageActionsOverlay|AppProxyQuickOverlay|BrowserMediaResourcesOverlay' \
  "System-hosted toolbar Sheets must not return to BrowserShell custom overlay branches."
check_file_not_contains_rule "${USER_SCRIPT_PAGE_ACTIONS_SHEET}" "${USER_SCRIPT_PAGE_ACTIONS_SHEET_REL}" \
  'BrowserModalBottomOverlay' \
  "UserScript Page Actions must not regain an independent custom modal overlay."
check_file_not_contains_rule "${APP_PROXY_QUICK_CONTENT}" "${APP_PROXY_QUICK_CONTENT_REL}" \
  'BrowserModalBottomOverlay' \
  "App Proxy Quick must not regain an independent custom modal overlay."
check_file_not_contains_rule "${MEDIA_RESOURCES_COMPONENT}" "${MEDIA_RESOURCES_COMPONENT_REL}" \
  'BrowserModalBottomOverlay' \
  "Page Resources must not regain an independent custom modal overlay."
check_file_contains_rule "${BOTTOM_SHEET}" "${BOTTOM_SHEET_REL}" \
  '@State private presentationVisible: boolean = false' \
  "Shared bottom overlay must own a local hidden entrance state across parent remounts."
check_file_contains_rule "${BOTTOM_SHEET}" "${BOTTOM_SHEET_REL}" \
  'this\.presentationVisible = false;' \
  "Shared bottom overlay must establish its local hidden endpoint before reveal."
check_file_contains_rule "${BOTTOM_SHEET}" "${BOTTOM_SHEET_REL}" \
  'this\.revealTimer = setTimeout' \
  "Shared bottom overlay must reveal through its component-local timer."
check_file_not_contains_rule "${BOTTOM_SHEET}" "${BOTTOM_SHEET_REL}" \
  '\.opacity\(this\.visible|\.translate\(\{ y: this\.visible|\.hitTestBehavior\(this\.visible' \
  "Shared bottom overlay rendering and hit testing must use component-local presentation state."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'tabHomeCoordinator\.toggleThemeModeFromBottomPanel\(\)' \
  "Root Bottom Panel action application must forward the theme action to Tab Home."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'runtimeTelemetryService|runtimeDiagnosticRedactionService|browserDiagnosticsRecorder|browserDiagnosticsService|diagnosticsMaintenanceScheduler|restoreTracesByTabId|sharedBrowserPageCacheMetrics|recordDiagnosticEvent|runtime_event type=' \
  "BrowserShellPage must not restore the removed runtime diagnostics application."
check_file_not_contains_rule "${BROWSER_APP_RUNTIME}" "${BROWSER_APP_RUNTIME_REL}" \
  'sharedBrowserDiagnosticsRecorder|sharedMembershipGrowthEventCoordinator|BrowserDiagnosticsRecorder|MembershipGrowthEventCoordinator' \
  "Browser app runtime must not restore removed diagnostics or write-only membership event recording."
check_file_not_contains_rule "${WEB_ACTIVE_SURFACE_COORDINATOR}" "${WEB_ACTIVE_SURFACE_COORDINATOR_REL}" \
  'BrowserWebActiveSurfaceDiagnosticEvent|diagnosticEvents|recordDiagnosticEvent|BrowserWebActiveSurfaceRuntimeEvent|BrowserWebActiveSurfaceActionExecutionResult|BrowserWebActiveSurfaceExecutionApplicationResult|runtimeEvents|recordRuntimeEvent' \
  "Web Active Surface must execute ordered actions without rebuilding removed diagnostic/result channels."
check_file_not_contains_rule "${SHELL_PRESENTATION_TOKENS}" "${SHELL_PRESENTATION_TOKENS_REL}" \
  'DIAGNOSTICS_CLEANUP_TICK_MS' \
  "Browser presentation tokens must not restore the removed diagnostics cleanup timer."
check_file_not_contains_rule "${BROWSER_DATABASE}" "${BROWSER_DATABASE_REL}" \
  'browser_diagnostics|BrowserDiagnosticEvent|BrowserDiagnosticsWriter|upsertDiagnosticEvent|listDiagnosticEvents|pruneDiagnosticEvents' \
  "BrowserDatabase must not restore the removed runtime diagnostics table or persistence methods."
check_file_not_contains_rule "${BROWSER_MODELS}" "${BROWSER_MODELS_REL}" \
  'BrowserDiagnosticScope|BrowserDiagnosticEvent|BrowserDiagnosticsSettings|BrowserDiagnosticsWriter|diagnostics: BrowserDiagnosticsSettings' \
  "Browser models must not restore removed runtime diagnostics event, settings, or persistence contracts."
check_file_not_contains_rule "${PREFERENCES_REPOSITORY}" "${PREFERENCES_REPOSITORY_REL}" \
  'DEFAULT_BROWSER_DIAGNOSTICS_SETTINGS|BrowserDiagnosticsSettings|readDiagnosticsSettings|writeDiagnosticsSettings|updateDiagnosticsSettings|normalizeDiagnosticsSettings|diagnostics:' \
  "PreferencesRepository must not restore the removed hidden runtime diagnostics settings."
check_file_not_contains_rule "${ARK_PREFERENCES_STORAGE_ADAPTER}" "${ARK_PREFERENCES_STORAGE_ADAPTER_REL}" \
  'DIAGNOSTICS_SETTINGS_KEY|BrowserDiagnosticsSettings|readDiagnosticsSettings|writeDiagnosticsSettings|parseDiagnosticsSettings' \
  "ArkPreferencesStorageAdapter must not restore the removed runtime diagnostics storage key."
for removed_diagnostics_path in \
  "${BROWSER_DIAGNOSTICS_RECORDER}" \
  "${MEMBERSHIP_GROWTH_EVENT_COORDINATOR}" \
  "${RUNTIME_TELEMETRY_SERVICE}" \
  "${RUNTIME_DIAGNOSTIC_REDACTION_SERVICE}" \
  "${PAGE_CACHE_METRICS_SERVICE}" \
  "${SHELL_DIAGNOSTIC_PRESENTATION_VIEW_MODEL}" \
  "${DIAGNOSTICS_LIFECYCLE_COORDINATOR}" \
  "${DIAGNOSTICS_MAINTENANCE_SCHEDULER}" \
  "${DIAGNOSTICS_SERVICE}"; do
  if [ -e "${removed_diagnostics_path}" ]; then
    report_failure "${removed_diagnostics_path#${REPO_ROOT}/} must stay deleted with the unused BrowserShell runtime diagnostics application."
  fi
done
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'siteCustomizationManagementCoordinator|SiteCustomizationManagementCoordinator|policyDecisionRecords|policyDecisionLines' \
  "BrowserShellPage must not recreate the orphan Site Customization manager or write-only policy-decision buffers."
for ordinary_diagnostic_seam_path in \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/adblock/ManualElementHideRuntimeCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserAppUrlOpenCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserHistoryVisitPersistenceCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserRecentlyClosedApplicationCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserSiteControlsRuntimeCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserUnifiedLinkApplicationCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserWebHistoryCommandRuntimeCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserWindowContextCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserWindowLaunchApplication.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/ReaderModeApplication.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/SiteClearOnCloseCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/customhome/CustomHomepageRuntimeCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/web/WebLinkContextMenuActionApplication.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/webapps/WebAppExitCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/webapps/WebAppInstallCoordinator.ets" \
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/services/web/BrowserOfflineFastFailureCoordinator.ets"; do
  if grep -Eq 'recordRuntimeEvent:|recordPolicyDecisionRecord:|appendRestoreTraceBreadcrumb:' \
    "${ordinary_diagnostic_seam_path}"; then
    report_failure "${ordinary_diagnostic_seam_path#${REPO_ROOT}/} must not restore an ordinary application diagnostic callback whose BrowserShell receiver is empty."
  fi
done
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'buildHomeSurfaceProfile\(homeVisibleOverride\?: boolean\)' \
  "Tab Home must own Home Surface Profile composition."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'buildHomeSystemChromePolicyState' \
  "Tab Home must expose the subordinate Home System Chrome policy entry."
if [ ! -e "${HOME_CHROME_SCROLL_COORDINATOR}" ]; then
  report_failure "${HOME_CHROME_SCROLL_COORDINATOR_REL} must own Native Home chrome-scroll policy and event state."
fi
if [ -e "${OLD_HOME_SCROLL_CHROME_VIEW_MODEL}" ]; then
  report_failure "${OLD_HOME_SCROLL_CHROME_VIEW_MODEL_REL} must stay deleted; Home scroll is coordination, not presentation-only ViewModel state."
fi
check_file_contains_rule "${HOME_CHROME_SCROLL_COORDINATOR}" "${HOME_CHROME_SCROLL_COORDINATOR_REL}" \
  'resolvePolicyMode\(' \
  "Home Chrome Scroll must expose one scene-aware policy seam."
check_file_contains_rule "${HOME_CHROME_SCROLL_COORDINATOR}" "${HOME_CHROME_SCROLL_COORDINATOR_REL}" \
  'handleScrollEvent\(' \
  "Home Chrome Scroll must own the raw-event-to-bottom-panel-decision flow."
check_file_not_contains_rule "${HOME_SURFACE_PROFILE_VIEW_MODEL}" "${HOME_SURFACE_PROFILE_VIEW_MODEL_REL}" \
  'homeScrollHideAllowed|hideToolbarOnScroll|buildSystemChromePolicy' \
  "Home Surface Profile must describe rendering only and must not regain Home Chrome Scroll policy."
check_file_contains_rule "${TAB_HOME_COORDINATOR}" "${TAB_HOME_COORDINATOR_REL}" \
  'homeScrollMode: this\.homeChromeScrollCoordinator\.resolvePolicyMode\(' \
  "Tab Home system-chrome transitions must consume the single Home Chrome Scroll policy result."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserHomeSystemChromePolicyViewModel|browserHomeSurfaceProfileViewModel|private (buildHomeSystemChromePolicyState|buildHomeSurfaceProfile|isThirdPartyHomepageRuntimeAllowed)\(' \
  "BrowserShellPage must not own Home Surface Profile or System Chrome policy helpers."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'currentBoundaryPrivate: this\.tabScopedEventContextCoordinator\.isCurrentBoundaryPrivate\(\)' \
  "BrowserShellPage must expose the current private boundary as an explicit Tab Home shell fact."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'customHomepageRuntimeState: this\.customHomepageRuntimeState' \
  "BrowserShellPage must expose Custom Homepage presentation state explicitly to Tab Home."
if [ -e "${OLD_HOME_SYSTEM_CHROME_POLICY_VIEW_MODEL}" ]; then
  report_failure "${OLD_HOME_SYSTEM_CHROME_POLICY_VIEW_MODEL_REL} must stay deleted; its field-alias projection belongs to Home Surface Profile."
fi
check_file_contains_rule "${SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL}" \
  "${SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL_REL}" \
  'beginPanelDrag' \
  "Search Backdrop presentation owner must retain panel-drag interaction state."
check_file_contains_rule "${SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL}" \
  "${SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL_REL}" \
  'prepareDetentSettle' \
  "Search Backdrop presentation owner must retain detent-settle planning."
check_file_contains_rule "${SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL}" \
  "${SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL_REL}" \
  'beginFocusTransition' \
  "Search Backdrop presentation owner must retain focus-transition state."
check_file_contains_rule "${SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL}" \
  "${SEARCH_BACKDROP_PRESENTATION_VIEW_MODEL_REL}" \
  'finishSettle' \
  "Search Backdrop presentation owner must retain settle completion/cancellation state."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'searchBackdrop(ExpandedHeight|PreviousPanelHeight|GestureStartProgress|GestureOffsetActive|GestureSuppressed|SettleRunId)' \
  "BrowserShellPage must not regain Search Backdrop interaction-session scalar state."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private (resolveRootBottomPanelSearchBackdropGestureStartProgress|updateSearchBackdropProgressFromRootBottomPanelGestureOffset)\(' \
  "BrowserShellPage must keep Search Backdrop gesture/session transitions behind the presentation owner."
check_file_contains_rule "${CUSTOM_HOMEPAGE_SURFACE}" "${CUSTOM_HOMEPAGE_SURFACE_REL}" \
  'CustomHomepageRuntimeShellState' \
  "Custom Homepage feature component must render from the Runtime owner snapshot."
check_file_contains_rule "${CUSTOM_HOMEPAGE_SURFACE}" "${CUSTOM_HOMEPAGE_SURFACE_REL}" \
  'NodeContainer.*resolveHostedWebNode' \
  "Custom Homepage feature component must retain Hosted node composition."
check_file_contains_rule "${CUSTOM_HOMEPAGE_SURFACE}" "${CUSTOM_HOMEPAGE_SURFACE_REL}" \
  'buildBrowserTabPreviewComponentSnapshotId' \
  "Custom Homepage feature component must retain preview-snapshot composition."
check_file_contains_rule "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR}" "${CUSTOM_HOMEPAGE_RUNTIME_COORDINATOR_REL}" \
  'handleSurfaceAction\(action: CustomHomepageSurfaceAction\)' \
  "Custom Homepage Surface actions must enter through the Runtime owner."
check_file_contains_rule "${CUSTOM_HOMEPAGE_SURFACE}" "${CUSTOM_HOMEPAGE_SURFACE_REL}" \
  'onAction: \(action: CustomHomepageSurfaceAction\)' \
  "Custom Homepage Surface must emit one typed action callback."
check_file_not_contains_rule "${CUSTOM_HOMEPAGE_SURFACE}" "${CUSTOM_HOMEPAGE_SURFACE_REL}" \
  '^  on(Retry|EditHomepage|OpenTabs|OpenBookmarks|OpenHistory|OpenHomepageSettings|OpenSettingsCenter):' \
  "Custom Homepage Surface must not regain peer action callbacks."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private (buildCustomHomepageLoadFailureSurface|buildCustomHomepageUnavailableSurface|buildCustomHtmlHomepage|shouldRenderHomeWebSurface|shouldRenderHomeFallbackSurface)\(' \
  "BrowserShellPage must not regain Custom Homepage feature-surface composition helpers."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_LAYOUT_MODEL}" "${ROOT_BOTTOM_PANEL_LAYOUT_MODEL_REL}" \
  'responsiveViewModel\.buildState' \
  "root bottom panel layout model must retain the shared responsive policy as its internal implementation."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_LAYOUT_MODEL}" "${ROOT_BOTTOM_PANEL_LAYOUT_MODEL_REL}" \
  'displayViewportWidth' \
  "root bottom panel layout model must consume the Ability-owned display viewport for responsive geometry."
check_file_contains_rule "${WINDOW_DISPLAY_VIEWPORT_COORDINATOR}" \
  "${WINDOW_DISPLAY_VIEWPORT_COORDINATOR_REL}" \
  "display\.on\('change'.*displayChangeCallback" \
  "window display viewport owner must observe physical display changes."
check_file_contains_rule "${WINDOW_DISPLAY_VIEWPORT_COORDINATOR}" \
  "${WINDOW_DISPLAY_VIEWPORT_COORDINATOR_REL}" \
  'getDefaultDisplaySync\(' \
  "window display viewport owner must read the current physical display."
check_file_contains_rule "${WINDOW_DISPLAY_VIEWPORT_COORDINATOR}" \
  "${WINDOW_DISPLAY_VIEWPORT_COORDINATOR_REL}" \
  'densityPixels' \
  "window display viewport owner must convert physical pixels into vp geometry."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@StorageLink\(BROWSER_WINDOW_DISPLAY_VIEWPORT_WIDTH_STORAGE_KEY\)' \
  "browser shell must react directly to the Ability-owned physical display width."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@StorageLink\(BROWSER_WINDOW_DISPLAY_VIEWPORT_HEIGHT_STORAGE_KEY\)' \
  "browser shell must react directly to the Ability-owned physical display height."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  '@State private rootBottomPanelLayoutState: BrowserRootBottomPanelLayoutState' \
  "browser shell must bind the Session-owned layout snapshot as explicit ArkUI presentation state."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'responsiveState: this\.rootBottomPanelLayoutState\.responsiveState' \
  "bottom panel Host must consume the explicit reactive layout snapshot instead of an ephemeral build result."
check_file_contains_rule "${WINDOW_DISPLAY_VIEWPORT_COORDINATOR}" \
  "${WINDOW_DISPLAY_VIEWPORT_COORDINATOR_REL}" \
  "windowSizeChange" \
  "window display viewport owner must use window size changes as a physical-display refresh trigger."
check_file_not_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'buildPanelRenderKey\(' \
  "root bottom panel session owner must not compose renderer-remount keys from transient presentation state."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'buildSemanticProjection' \
  "root bottom panel session owner must expose the semantic projection path."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" \
  "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'resolveLeadingHeaderActions|resolveTrailingHeaderActions' \
  "root bottom panel Session subordinate must calculate scene-sensitive header chrome."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'presentationChannel: renderContext\.presentationChannel' \
  "root bottom panel renderer must consume the Host-owned live presentation channel."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'livePresentation: this\.browserRootBottomPanelSessionCoordinator\.buildLivePresentation\(\{' \
  "browser shell must bind the current Root Bottom-Panel owner projection into the Host-side presentation publisher."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserRootBottomPanelSessionCoordinator\.buildLivePresentation\(\{' \
  "browser shell live-presentation binding must pass one complete facts snapshot through the Root Bottom-Panel owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'buildLivePresentation\(' \
  "Root Bottom-Panel Session must own construction of the complete live presentation."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  "else if \(swipeAction\?\.id === 'bottomChromeMenu'\)" \
  "an outer toolbar swipe assigned to Menu must retain the expanded middle detent."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "@State @Watch\('syncRootBottomPanelBackAvailability'\) canGoBack: boolean" \
  "browser shell must make Web Back availability a direct reactive input to Root Bottom-Panel presentation."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserRootBottomPanelSessionCoordinator\.invalidatePresentation\(\);' \
  "the Back-availability watcher must invalidate only the existing Root Bottom-Panel presentation owner."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'new BrowserBottomPanelLivePresentation\(|chromeProjection: semanticProjection' \
  "browser shell renderer must not duplicate construction-time motion or semantic projection beside the live channel."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'rootBottomPanelSessionRenderVersion|invalidateRootBottomPanelSessionProjection' \
  "browser shell must not own an ad-hoc projection revision workaround."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'invalidatePresentation\(\): void' \
  "Root Bottom-Panel Session must own explicit invalidation of its private presentation state."
check_file_not_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" \
  "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'leadingHeaderActions:|trailingHeaderActions:' \
  "stable bottom action snapshots must not cache scene-sensitive header chrome."
if awk '
  /private buildRootBottomPanelLayoutRenderKey\(\): string/ { in_block = 1 }
  in_block && /buildAddressPanelActionRenderKey/ { found = 1 }
  in_block && /^  }/ { in_block = 0 }
  END { exit found ? 0 : 1 }
' "${SHELL_PAGE}"; then
  report_failure "${SHELL_PAGE_REL} bottom panel layout render keys must stay layout-only; action state belongs to the presentation-owner snapshot."
fi
if [ -e "${BOTTOM_ACTION_STATE_COORDINATOR}" ]; then
  report_failure "${BOTTOM_ACTION_STATE_COORDINATOR_REL} must stay deleted; action state is subordinate to the presentation implementation."
fi
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" \
  "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'buildActionEnablement' \
  "bottom toolbar action enablement must be produced inside the consolidated presentation implementation."
check_file_contains_rule "${BOTTOM_ADDRESS_PANEL_VIEW_MODEL}" "${BOTTOM_ADDRESS_PANEL_VIEW_MODEL_REL}" \
  'applyActionEnablement' \
  "bottom toolbar actions must consume centralized action enablement."
check_file_not_contains_rule "${BOTTOM_ADDRESS_PANEL_VIEW_MODEL}" "${BOTTOM_ADDRESS_PANEL_VIEW_MODEL_REL}" \
  'enabled: input\.bookmarksEnabled|enabled: input\.readerModeEnabled|enabled: input\.webpageTranslationEnabled|enabled: input\.offlinePageSaveEnabled|disabledMessage: .请先打开网页.' \
  "bottom toolbar action enabled/disabledMessage must not be hand-built in BrowserBottomAddressPanelViewModel."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserWebSurfaceActionEntryViewModel|WebpageTranslationEntryViewModel' \
  "must not directly own Web page action entry view models; route through the root bottom panel Session."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'readerModeEnabled: this\.|webpageTranslationEnabled: this\.|offlinePageSaveEnabled: this\.' \
  "must not hand-build page-action availability in the page; route through the root bottom panel Session."
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" \
  "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'targetUrls: string\[\]' \
  "bottom toolbar action presentation must carry target URL fallbacks."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'resolveActionTarget\(input: BrowserBottomPanelActionTargetInput\)' \
  "bottom toolbar target URL resolution must stay behind the root bottom panel Session."
if awk '
  /private resolveCurrentUserAgentMode\(\): BrowserUserAgentMode/ { in_block = 1 }
  in_block && /resolveCurrentSiteUrl\(this\.currentUrl, this\.addressInput\)/ { found = 1 }
  in_block && /^  }/ { in_block = 0 }
  END { exit found ? 0 : 1 }
' "${SHELL_PAGE}"; then
  report_failure "${SHELL_PAGE_REL} bottom toolbar user-agent mode must not use currentUrl/addressInput; use the unified Web page action URL."
fi
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'reader=1.*reader=0|reader=0.*reader=1|reader=' \
  "bottom panel action render key must include reader availability."
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'translate=' \
  "bottom panel action render key must include translation availability."
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'offline=' \
  "bottom panel action render key must include offline-save availability."
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'bookmarkSelected=' \
  "bottom panel action render key must include bookmark selected state."
check_file_contains_rule "${BOTTOM_ACTION_PRESENTATION_COORDINATOR}" "${BOTTOM_ACTION_PRESENTATION_COORDINATOR_REL}" \
  'bookmarkVersion=' \
  "bottom panel action render key must include bookmark action version."

if [ -e "${OLD_FEATURE_GATE_VIEW_MODEL}" ]; then
  report_failure "${OLD_FEATURE_GATE_VIEW_MODEL_REL} must stay deleted; Feature Gate projection and application flow belong to one owner."
fi
feature_gate_snapshot_count="$(grep -Ec '@State featureGateSnapshot: FeatureGateSnapshot' "${SHELL_PAGE}" || true)"
if [ "${feature_gate_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Feature Gate snapshot."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'FeatureGateViewModel|FeatureGateViewState|AIRA_FEATURE_OFFLINE_PAGE_SAVE|private ensureMembershipAccess\(|private showFeatureGateDecision\(|private dismissFeatureGateSheet\(|private handleFeatureGateAction\(|showFeatureGateDecision:|ensureAccess:.*ensureMembershipAccess' \
  "BrowserShellPage must not regain Feature Gate policy, presentation sequencing, or feature-owner callback round trips."
check_file_contains_rule "${FEATURE_GATE_COORDINATOR}" "${FEATURE_GATE_COORDINATOR_REL}" \
  'class FeatureGateCoordinator' \
  "Feature Gate must keep one application narrative owner."
check_file_contains_rule "${FEATURE_GATE_COORDINATOR}" "${FEATURE_GATE_COORDINATOR_REL}" \
  'ensureAccess\(featureKey: AiraFeatureKey' \
  "Feature Gate authorization must remain behind the application owner."
check_file_contains_rule "${FEATURE_GATE_COORDINATOR}" "${FEATURE_GATE_COORDINATOR_REL}" \
  'presentDecision\(decision: EntitlementDecision\)' \
  "Feature Gate denial presentation must remain behind the application owner."
check_file_contains_rule "${FEATURE_GATE_COORDINATOR}" "${FEATURE_GATE_COORDINATOR_REL}" \
  'handleAction\(action: FeatureGateAction\)' \
  "Feature Gate actions must remain behind the application owner."
check_file_contains_rule "${FEATURE_GATE_COORDINATOR}" "${FEATURE_GATE_COORDINATOR_REL}" \
  'BrowserTransientSurfaceCoordinator' \
  "Feature Gate must compose its fixed transient-surface dependency directly."
check_file_contains_rule "${FEATURE_GATE_COORDINATOR}" "${FEATURE_GATE_COORDINATOR_REL}" \
  'BrowserShellRouteCoordinator' \
  "Feature Gate must compose its fixed route dependency directly."
check_file_not_contains_rule "${FEATURE_GATE_COORDINATOR}" "${FEATURE_GATE_COORDINATOR_REL}" \
  'FeatureGatePort|FeatureGateHostAdapter|FeatureGateViewModel' \
  "Feature Gate must not regain a shallow Port, HostAdapter, or peer ViewModel."
check_file_not_contains_rule "${PHONE_PAGE_PUSH_COORDINATOR}" "${PHONE_PAGE_PUSH_COORDINATOR_REL}" \
  'ensureAccess: \(\) => Promise<boolean>|host\.ensureAccess\(' \
  "Phone Page Push must use the fixed Feature Gate owner instead of a page authorization callback."
check_file_not_contains_rule "${PHONE_PAGE_PUSH_COORDINATOR}" "${PHONE_PAGE_PUSH_COORDINATOR_REL}" \
  'recordEvent:|host\.recordEvent|tabId: string;|stringifyError\(' \
  "Phone Page Push must not restore diagnostic-only tab identity, event callbacks, or error formatting."
check_file_not_contains_rule "${WEB_APP_INSTALL_COORDINATOR}" "${WEB_APP_INSTALL_COORDINATOR_REL}" \
  'ensureAccess: \(currentUsage: number\)|host\.ensureAccess\(' \
  "WebApp Install must use the fixed Feature Gate owner instead of a page authorization callback."
check_file_not_contains_rule "${OFFLINE_PAGE_SAVE_COORDINATOR}" "${OFFLINE_PAGE_SAVE_COORDINATOR_REL}" \
  'showFeatureGateDecision:|shell\.showFeatureGateDecision\(' \
  "Offline Save must present denials through the fixed Feature Gate owner."
check_file_contains_rule "${OFFLINE_PAGE_SAVE_COORDINATOR}" "${OFFLINE_PAGE_SAVE_COORDINATOR_REL}" \
  'ensureLinkSaveAccess\(dataScope: string, privacyMode: string\)' \
  "Offline Save must own its context-link membership admission and quota source."
check_file_not_contains_rule "${FEATURE_GATE_OVERLAY}" "${FEATURE_GATE_OVERLAY_REL}" \
  'onPrimaryAction|onSecondaryAction|onDismiss: \(\) => void' \
  "Feature Gate Overlay must expose one typed action callback."
check_file_not_contains_rule "${FEATURE_GATE_SHEET}" "${FEATURE_GATE_SHEET_REL}" \
  'onPrimaryAction|onSecondaryAction' \
  "Feature Gate Sheet must forward both buttons through one typed action callback."

check_file_contains_rule "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR}" \
  "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR_REL}" \
  'featureGateCoordinator\.presentDecision\(' \
  "Manual Element Hide must enter the fixed Feature Gate owner directly."
check_file_contains_rule "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR}" \
  "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR_REL}" \
  'siteControlsRuntimeCoordinator\.refreshActiveProtectionPresentation\(' \
  "Manual Element Hide must enter the fixed Site Controls owner directly."
manual_element_hide_shell_callback_count="$(awk '
  /export interface ManualElementHideRuntimeShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /=>/ { count += 1 }
' "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR}")"
if [ "${manual_element_hide_shell_callback_count}" -ne 5 ]; then
  report_failure "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR_REL} must keep exactly five dynamic-fact/UI callbacks; found ${manual_element_hide_shell_callback_count}."
fi
check_file_not_contains_rule "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR}" \
  "${MANUAL_ELEMENT_HIDE_RUNTIME_COORDINATOR_REL}" \
  'ManualElementHideRuntimeEffect|ManualElementHideRuntimeSink|applyEffect:|private emit\(|runtimeEventType|runtimeEventMessage' \
  "Manual Element Hide must not regain a generic effect interpreter or diagnostics-only result fields."
check_file_not_contains_rule "${AD_BLOCK_RUNTIME_STATS_COORDINATOR}" \
  "${AD_BLOCK_RUNTIME_STATS_COORDINATOR_REL}" \
  'runtimeEventType|runtimeEventMessage' \
  "AdBlock runtime statistics must return protection counts without diagnostics-only event fields."
check_file_not_contains_rule "${SITE_CUSTOMIZATION_RUNTIME_REFRESH_COORDINATOR}" \
  "${SITE_CUSTOMIZATION_RUNTIME_REFRESH_COORDINATOR_REL}" \
  'revision:|activeTabId:|profileId:|dataScope:|runtimeEventType|runtimeEventMessage|buildRuntimeEventMessage' \
  "Site Customization refresh plans must contain refresh/reload behavior only, not empty-recorder diagnostics."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'site_customization_runtime_refresh|system_settings_opened|system_settings_open_failed|user_agent_compatibility_applied|user_agent_compatibility_pre_navigation|web_history_return_quiet_window_started' \
  "BrowserShellPage must not restore ordinary refresh, system-settings, UA, or History quiet-window diagnostic calls."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'manualElementHideRuntimeShell: ManualElementHideRuntimeShell' \
  "BrowserShellPage must expose one narrow Manual Element Hide shell."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'ManualElementHideRuntimeEffect|ManualElementHideRuntimeSink|manualElementHideRuntimeSink|applyManualElementHideRuntimeEffect\(' \
  "BrowserShellPage must not regain Manual Element Hide effect interpretation."
check_file_contains_rule "${BROWSER_WEB_PRINT_SERVICE}" "${BROWSER_WEB_PRINT_SERVICE_REL}" \
  'canPrintCurrentPage\(facts: BrowserWebPrintAvailabilityFacts\)' \
  "Web Print must own current-page availability policy."
check_file_contains_rule "${BROWSER_WEB_PRINT_SERVICE}" "${BROWSER_WEB_PRINT_SERVICE_REL}" \
  'onStatusMessage\?\.\(.打印任务已完成。' \
  "Web Print must map platform task status to its user-facing completion message."
check_file_not_contains_rule "${BROWSER_WEB_PRINT_SERVICE}" "${BROWSER_WEB_PRINT_SERVICE_REL}" \
  'BrowserWebPrintStatus|onStatus\?:' \
  "Web Print must not regain the single-caller raw status seam."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserWebPrintStatus|private canPrintCurrentPage\(|private handleWebPrintStatus\(' \
  "BrowserShellPage must not regain Web Print availability or status interpretation."
check_file_contains_rule "${DOCUMENT_VIEWER_SERVICE}" "${DOCUMENT_VIEWER_SERVICE_REL}" \
  'resolveChromeContext\(candidateUrls: string\[\], fallbackTitle: string\)' \
  "Document Viewer must own current-candidate Chrome policy and title resolution."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'buildCurrentDocumentViewerChromeContext\(\): DocumentViewerChromeContext' \
  "BrowserShellPage must expose one current-facts adapter for Document Viewer Chrome."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private isCurrentDocumentViewerPage\(|private resolveCurrentDocumentViewerTitle\(|private resolveCurrentDocumentViewerChromePolicy\(|private resolveCurrentDocumentViewerUrl\(' \
  "BrowserShellPage must not regain Document Viewer URL ranking, Chrome policy, or title fallback ownership."

web_app_install_dialog_snapshot_count="$(grep -Ec '@State webAppInstallDialogSnapshot: WebAppInstallDialogSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${web_app_install_dialog_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level WebApp Install Dialog snapshot."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'desktopShortcutDialogTitle|desktopShortcutDialogUrl|desktopShortcutDialogIconUri|desktopShortcutDialogIconCustomized|desktopShortcutDialogIconProcessing|WebAppInstallHost|WebAppInstallIconPresentation|selectCustomIcon\(|restoreDefaultIcon\(|webAppInstallCoordinator\.cancel\(|webAppInstallCoordinator\.confirm\(' \
  "BrowserShellPage must not regain split WebApp Install Dialog state or per-action Host sequencing."
check_file_contains_rule "${WEB_APP_INSTALL_COORDINATOR}" "${WEB_APP_INSTALL_COORDINATOR_REL}" \
  'getDialogSnapshot\(\): WebAppInstallDialogSnapshot' \
  "WebApp Install must own one canonical Dialog snapshot."
check_file_contains_rule "${WEB_APP_INSTALL_COORDINATOR}" "${WEB_APP_INSTALL_COORDINATOR_REL}" \
  'handleDialogAction\(action: WebAppInstallDialogAction\)' \
  "WebApp Install Dialog actions must enter through one typed owner method."
check_file_contains_rule "${WEB_APP_INSTALL_COORDINATOR}" "${WEB_APP_INSTALL_COORDINATOR_REL}" \
  'handleDialogDismissed\(\): Promise<void>' \
  "WebApp Install Dialog dismissal cleanup must remain owner-held and idempotent."
check_file_contains_rule "${WEB_APP_INSTALL_COORDINATOR}" "${WEB_APP_INSTALL_COORDINATOR_REL}" \
  'private runtimeLifecyclePort: BrowserRuntimeLifecyclePort' \
  "WebApp Install must compose its fixed runtime lifecycle dependency directly."
check_file_contains_rule "${WEB_APP_INSTALL_COORDINATOR}" "${WEB_APP_INSTALL_COORDINATOR_REL}" \
  'private async confirmDetachedSession\(' \
  "WebApp Install confirm must detach the Dialog session before the asynchronous system request."
check_file_not_contains_rule "${WEB_APP_INSTALL_COORDINATOR}" "${WEB_APP_INSTALL_COORDINATOR_REL}" \
  'WebAppInstallIconPresentation|WebAppInstallHost|selectCustomIcon\(host|restoreDefaultIcon\(host|confirm\(title: string, host|async cancel\(' \
  "WebApp Install must not regain the icon-only DTO, per-action Host arguments, or a duplicate cancel entry."
web_app_install_shell_callback_count="$(awk '
  /export interface WebAppInstallShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${WEB_APP_INSTALL_COORDINATOR}")"
if [ "${web_app_install_shell_callback_count}" -ne 4 ]; then
  report_failure "${WEB_APP_INSTALL_COORDINATOR_REL} WebAppInstallShell must keep exactly four true shell/platform callbacks; found ${web_app_install_shell_callback_count}."
fi
web_app_install_dialog_link_count="$(grep -Ec '@Link snapshot: WebAppInstallDialogSnapshot' \
  "${BROWSER_SHELL_DIALOGS}" || true)"
if [ "${web_app_install_dialog_link_count}" -ne 1 ]; then
  report_failure "${BROWSER_SHELL_DIALOGS_REL} must bind the WebApp Install Dialog through one explicit snapshot Link."
fi
web_app_install_dialog_action_count="$(grep -Ec 'onAction: \(action: WebAppInstallDialogAction\)' \
  "${BROWSER_SHELL_DIALOGS}" || true)"
if [ "${web_app_install_dialog_action_count}" -ne 1 ]; then
  report_failure "${BROWSER_SHELL_DIALOGS_REL} must expose exactly one typed WebApp Install Dialog action callback."
fi
check_file_not_contains_rule "${BROWSER_SHELL_DIALOGS}" "${BROWSER_SHELL_DIALOGS_REL}" \
  '@Link shortcutTitle|@Link shortcutUrl|@Link shortcutIconUri|@Link shortcutIconCustomized|@Link shortcutIconProcessing' \
  "DesktopShortcutNameDialog must not regain scalar Links."
web_app_install_legacy_dialog_callback_count="$(awk '
  /export struct DesktopShortcutNameDialog \{/ { in_dialog = 1; next }
  in_dialog && /^export struct / { print count + 0; exit }
  in_dialog && /^[[:space:]]+(selectIcon|restoreIcon|cancel|confirm): \(\) => void/ { count += 1 }
' "${BROWSER_SHELL_DIALOGS}")"
if [ "${web_app_install_legacy_dialog_callback_count}" -ne 0 ]; then
  report_failure "${BROWSER_SHELL_DIALOGS_REL} DesktopShortcutNameDialog must not regain split select/restore/cancel/confirm callbacks."
fi

if [ -e "${OLD_DOWNLOAD_EVENT_COORDINATOR}" ]; then
  report_failure "${OLD_DOWNLOAD_EVENT_COORDINATOR_REL} must stay deleted; UserScript browser application flow belongs to one owner."
fi
user_script_application_snapshot_count="$(grep -Ec '@State browserUserScriptApplicationSnapshot: BrowserUserScriptApplicationSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${user_script_application_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Browser UserScript Application snapshot."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserDownloadEvent|pendingUserScriptInstallUrl|userScriptPageActionsState|userScriptPageActionsBusyCommandId|private showUserScriptInstallPrompt\(|private dismissUserScriptInstallSheet\(|private openUserScriptPageActionsSheet\(|private refreshUserScriptPageActionsState\(|private runUserScriptPageMenuCommand\(|private openUserScriptsManagerFromPageActions\(|private dismissUserScriptPageActionsSheet\(|private confirmUserScriptInstallSheet\(|private installUserScriptFromUrl\(|USER_SCRIPT_DETAIL_ROUTE' \
  "BrowserShellPage must not regain UserScript install/Page Actions state, sequencing, or direct detail-route ownership."
check_file_contains_rule "${USER_SCRIPT_APPLICATION_COORDINATOR}" "${USER_SCRIPT_APPLICATION_COORDINATOR_REL}" \
  'class BrowserUserScriptApplicationCoordinator' \
  "Browser UserScript flow must keep one application narrative owner."
check_file_contains_rule "${USER_SCRIPT_APPLICATION_COORDINATOR}" "${USER_SCRIPT_APPLICATION_COORDINATOR_REL}" \
  'handleInstallCandidate\(url: string\): boolean' \
  "All UserScript install ingress must enter through one candidate method."
check_file_contains_rule "${USER_SCRIPT_APPLICATION_COORDINATOR}" "${USER_SCRIPT_APPLICATION_COORDINATOR_REL}" \
  'handleAction\(action: BrowserUserScriptApplicationAction\): void' \
  "Browser UserScript UI actions must enter through one typed owner method."
check_file_contains_rule "${USER_SCRIPT_APPLICATION_COORDINATOR}" "${USER_SCRIPT_APPLICATION_COORDINATOR_REL}" \
  'handleSurfaceUpdate\(update: BrowserTransientSurfaceUpdate\): void' \
  "Browser UserScript surface cleanup must remain inside the application owner."
check_file_not_contains_rule "${USER_SCRIPT_APPLICATION_COORDINATOR}" "${USER_SCRIPT_APPLICATION_COORDINATOR_REL}" \
  'BrowserUserScriptApplicationHost|BrowserUserScriptApplicationPort|HostAdapter|BrowserDownloadEventPlan|record_runtime_event|eventType\?:|tabId\?:' \
  "Browser UserScript must not regain a shallow seam or the deleted install diagnostic effect."
user_script_application_callback_count="$(awk '
  /export interface BrowserUserScriptApplicationDependencies \{/ { in_dependencies = 1; next }
  in_dependencies && /^}/ { print count + 0; exit }
  in_dependencies && /: \(/ { count += 1 }
' "${USER_SCRIPT_APPLICATION_COORDINATOR}")"
if [ "${user_script_application_callback_count}" -ne 3 ]; then
  report_failure "${USER_SCRIPT_APPLICATION_COORDINATOR_REL} must expose exactly three true shell callbacks; found ${user_script_application_callback_count}."
fi
check_file_not_contains_rule "${USER_SCRIPT_INSTALL_SHEET}" "${USER_SCRIPT_INSTALL_SHEET_REL}" \
  'onConfirm:|onCancel:' \
  "UserScript Install Sheet must expose one typed action callback."
check_file_not_contains_rule "${USER_SCRIPT_PAGE_ACTIONS_SHEET}" "${USER_SCRIPT_PAGE_ACTIONS_SHEET_REL}" \
  'onClose:|onRefresh:|onOpenManager:|onRunCommand:|busyCommandId' \
  "UserScript Page Actions Sheet must expose one typed action callback and must not regain transient busy state."
check_file_contains_rule "${SHELL_ROUTE_COORDINATOR}" "${SHELL_ROUTE_COORDINATOR_REL}" \
  'openUserScriptDetailPage\(scriptId: string\): void' \
  "UserScript detail navigation must remain behind the Browser Shell Route owner."

check_file_contains_rule "${MAIN_BACK_COORDINATOR}" "${MAIN_BACK_COORDINATOR_REL}" \
  'export interface BrowserMainBackDependencies' \
  "Main Back must compose its fixed browser-flow owners directly."
check_file_contains_rule "${MAIN_BACK_COORDINATOR}" "${MAIN_BACK_COORDINATOR_REL}" \
  'webHistoryCommandRuntimeCoordinator\.handleSystemBack\(\)' \
  "Main Back must apply Web-history command results inside its narrative owner."
check_file_contains_rule "${MAIN_BACK_COORDINATOR}" "${MAIN_BACK_COORDINATOR_REL}" \
  'windowOpenApplicationCoordinator\.handleActiveChildTerminalBack\(reason\)' \
  "Main Back must preserve terminal child Back through the frozen Window-open application owner."
check_file_contains_rule "${MAIN_BACK_COORDINATOR}" "${MAIN_BACK_COORDINATOR_REL}" \
  'tabCloseCoordinator\.closeActiveTabBackToLastTabOrHome\(reason\)' \
  "Main Back must keep ordinary terminal Back on the opener-aware tab-close fallback."
check_file_contains_rule "${MAIN_BACK_COORDINATOR}" "${MAIN_BACK_COORDINATOR_REL}" \
  "tabsOverviewSessionCoordinator\.handle\(\{ type: 'dismiss_to_home' \}\)" \
  "Main Back must dispatch Tabs Overview dismissal directly to the existing Session owner."
check_file_not_contains_rule "${MAIN_BACK_COORDINATOR}" "${MAIN_BACK_COORDINATOR_REL}" \
  'BrowserMainBackPort|BrowserMainBackHostAdapter|BrowserMainBackEffectPlan' \
  "Main Back must not regain a shallow Port, HostAdapter, or page-interpreted effect plan."
main_back_host_callback_count="$(awk '
  /export interface BrowserMainBackHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${MAIN_BACK_COORDINATOR}")"
if [ "${main_back_host_callback_count}" -ne 8 ]; then
  report_failure "${MAIN_BACK_COORDINATOR_REL} must expose exactly eight live shell fact/effect callbacks; found ${main_back_host_callback_count}."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'handleBrowserShellBackAction|handleRootBottomPanelBackAction|handleShellBackAction:|handleBottomAddressPanelBackAction:|handleWebTabsBack:|handleUnavailableWebBack:|handleFailedWebBack:|handleWindowOpenChildTerminalBack:' \
  "BrowserShellPage must not regain Main Back action interpretation or fixed-owner forwarding."

check_file_contains_rule "${SHELL_LIFECYCLE_COORDINATOR}" "${SHELL_LIFECYCLE_COORDINATOR_REL}" \
  'class BrowserShellLifecycleCoordinator' \
  "Browser Shell lifecycle must keep one durable narrative owner."
check_file_contains_rule "${SHELL_LIFECYCLE_COORDINATOR}" "${SHELL_LIFECYCLE_COORDINATOR_REL}" \
  'handleAppear\(\): void' \
  "Browser Shell appearance ordering must enter the lifecycle owner."
check_file_contains_rule "${SHELL_LIFECYCLE_COORDINATOR}" "${SHELL_LIFECYCLE_COORDINATOR_REL}" \
  'handleDisappear\(\): void' \
  "Browser Shell disappearance ordering must enter the lifecycle owner."
check_file_contains_rule "${SHELL_LIFECYCLE_COORDINATOR}" "${SHELL_LIFECYCLE_COORDINATOR_REL}" \
  'handlePageShow\(\): void' \
  "Browser Shell resumed foreground ordering must enter the lifecycle owner."
check_file_contains_rule "${SHELL_LIFECYCLE_COORDINATOR}" "${SHELL_LIFECYCLE_COORDINATOR_REL}" \
  'sharedSyncExperienceCoordinator\.notifyBookmarkSurfaceForeground\(\)' \
  "Browser Shell lifecycle must preserve the frozen Bookmark foreground notification in its original sequence."
check_file_contains_rule "${SHELL_LIFECYCLE_COORDINATOR}" "${SHELL_LIFECYCLE_COORDINATOR_REL}" \
  'hostedRuntimeSurfacePort\.releaseForPageDisappear\(\)' \
  "Browser Shell lifecycle must preserve Hosted runtime release on page disappearance."
check_file_contains_rule "${SHELL_LIFECYCLE_COORDINATOR}" "${SHELL_LIFECYCLE_COORDINATOR_REL}" \
  'backgroundSessionSyncCoordinator\.handleAppBackground\(' \
  "Browser Shell lifecycle must preserve background-protection synchronization."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'this\.browserShellLifecycleCoordinator\.handleAppear\(\);' \
  "BrowserShellPage aboutToAppear must forward to the lifecycle owner."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'this\.browserShellLifecycleCoordinator\.handleDisappear\(\);' \
  "BrowserShellPage aboutToDisappear must forward to the lifecycle owner."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'this\.browserShellLifecycleCoordinator\.handlePageShow\(\);' \
  "BrowserShellPage onPageShow must forward to the lifecycle owner."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'themePreferencesListenerKey|proxyRuntimeRefreshListenerKey|private (bindThemePreferencesUpdates|unbindThemePreferencesUpdates|bindProxyRuntimeRefreshUpdates|unbindProxyRuntimeRefreshUpdates|consumePendingProxyRuntimeRefresh|refreshWebScrollAppearanceCache|refreshWebScrollExperimentCache|bindSmartGripUpdates|unbindSmartGripUpdates|consumeRouteLaunchUrl|consumeReturnHomeRouteRequest|openResolvedUrl|applyRuntimeRetentionSettingsFromPreferences)\(' \
  "BrowserShellPage must not regain lifecycle subscription state, route activation, or retention ordering."
check_file_not_contains_rule "${SHELL_LIFECYCLE_COORDINATOR}" "${SHELL_LIFECYCLE_COORDINATOR_REL}" \
  'BrowserShellLifecyclePort|BrowserShellLifecycleHostAdapter|BrowserShellLifecycleEffectPlan' \
  "Browser Shell lifecycle must not add a shallow Port, HostAdapter, or page-interpreted effect plan."
shell_lifecycle_callback_count="$(awk '
  /export interface BrowserShellLifecycleShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${SHELL_LIFECYCLE_COORDINATOR}")"
if [ "${shell_lifecycle_callback_count}" -gt 31 ]; then
  report_failure "${SHELL_LIFECYCLE_COORDINATOR_REL} shell must stay at no more than 31 live facts/state/UI/platform callbacks; found ${shell_lifecycle_callback_count}."
fi

if [ -e "${OLD_WEB_PAGE_TOOLS_VIEW_MODEL}" ]; then
  report_failure "${OLD_WEB_PAGE_TOOLS_VIEW_MODEL_REL} must stay deleted; Page Tools presentation and transient lifecycle belong to one application owner."
fi
web_page_tools_snapshot_count="$(grep -Ec '@State browserWebPageToolsSnapshot: BrowserWebPageToolsSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${web_page_tools_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Web Page Tools snapshot."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserWebPageToolsSheetViewModel|webPageToolsSheetType|browserWebPageToolsSheetViewModel|private resolveWebPageToolsSheetHeight\(|private closeWebPageToolsSheet\(|private handleWebPageToolsSheetBackAction\(|private openWebPageToolsOverlay\(|private dismissWebPageToolsOverlay\(|private resetWebPageToolsOverlayState\(|private buildScreenOrientationSheet\(|private buildDesktopSiteModeSheet\(|private buildUserAgentPresetSheet\(|private buildSiteInfoSheet\(|BrowserScreenOrientationSheet|BrowserDesktopSiteModeSheet|BrowserUserAgentPresetSheet|BrowserSiteInfoSheet|siteInfoVisible:|setOverlayVisible:' \
  "BrowserShellPage must not regain Page Tools canonical state, transient sequencing, or Site Controls surface callbacks."
check_file_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  '@Prop fullscreenPresentation: BrowserFullscreenSessionPresentation' \
  "Web Page Tools Host must consume the typed Fullscreen presentation directly."
check_file_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  '@Prop userAgentPresentation: BrowserUserAgentActionPresentation' \
  "Web Page Tools Host must consume the typed User Agent presentation directly."
check_file_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  '@Prop siteControlsSnapshot: BrowserSiteControlsApplicationSnapshot' \
  "Web Page Tools Host must consume the typed Site Controls snapshot directly."
check_file_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  'BrowserScreenOrientationSheet' \
  "Web Page Tools Host must render the Screen Orientation sheet."
check_file_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  'BrowserDesktopSiteModeSheet' \
  "Web Page Tools Host must render the Desktop Site sheet."
check_file_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  'BrowserUserAgentPresetSheet' \
  "Web Page Tools Host must render the User Agent sheet."
check_file_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  'BrowserSiteInfoSheet' \
  "Web Page Tools Host must render the Site Info sheet."
check_file_not_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  '@BuilderParam' \
  "Web Page Tools Host must not push its owned sheet rendering back through page-built Builder callbacks."
check_file_contains_rule "${WEB_PAGE_TOOLS_COORDINATOR}" "${WEB_PAGE_TOOLS_COORDINATOR_REL}" \
  'class BrowserWebPageToolsCoordinator' \
  "Web Page Tools must keep one application narrative owner."
check_file_contains_rule "${WEB_PAGE_TOOLS_COORDINATOR}" "${WEB_PAGE_TOOLS_COORDINATOR_REL}" \
  'open\(type: BrowserWebPageToolsSheetType, replaceCurrentSheet: boolean = false\)' \
  "Web Page Tools open and in-surface replacement must remain behind one owner entry."
check_file_contains_rule "${WEB_PAGE_TOOLS_COORDINATOR}" "${WEB_PAGE_TOOLS_COORDINATOR_REL}" \
  'handleBack\(\): void' \
  "Web Page Tools Back ordering must remain owner-held."
check_file_contains_rule "${WEB_PAGE_TOOLS_COORDINATOR}" "${WEB_PAGE_TOOLS_COORDINATOR_REL}" \
  'handleTransientSurfaceUpdate\(update: BrowserTransientSurfaceUpdate\): void' \
  "Web Page Tools transient dismissal cleanup must remain owner-held."
check_file_contains_rule "${WEB_PAGE_TOOLS_COORDINATOR}" "${WEB_PAGE_TOOLS_COORDINATOR_REL}" \
  'handleOverlayAction\(action: BrowserWebPageToolsOverlayAction\): void' \
  "Web Page Tools Overlay actions must enter through one typed owner action."
check_file_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  'onAction: \(action: BrowserWebPageToolsOverlayAction\)' \
  "Web Page Tools Overlay Host must emit one typed owner action callback."
check_file_not_contains_rule "${WEB_PAGE_TOOLS_OVERLAY_HOST}" "${WEB_PAGE_TOOLS_OVERLAY_HOST_REL}" \
  '^  (onDismiss|onSelectScreenOrientation|onSelectDesktopSiteMode|onOpenDefaultUserAgent|onSelectUserAgentPreset|onSelectCustomUserAgent|onSiteControlsAction):' \
  "Web Page Tools Overlay Host must not regain peer surface callbacks."
check_file_contains_rule "${WEB_PAGE_TOOLS_COORDINATOR}" "${WEB_PAGE_TOOLS_COORDINATOR_REL}" \
  'BrowserTransientSurfaceCoordinator' \
  "Web Page Tools must compose its fixed Transient Surface dependency directly."
check_file_contains_rule "${WEB_PAGE_TOOLS_COORDINATOR}" "${WEB_PAGE_TOOLS_COORDINATOR_REL}" \
  'BrowserSiteControlsRuntimeCoordinator' \
  "Web Page Tools must compose the Site Controls content owner directly for close, Back, and reset."
check_file_not_contains_rule "${WEB_PAGE_TOOLS_COORDINATOR}" "${WEB_PAGE_TOOLS_COORDINATOR_REL}" \
  'PageToolsPort|PageToolsHostAdapter|PageToolsViewModel' \
  "Web Page Tools must not regain a shallow Port, HostAdapter, or peer ViewModel."
check_file_not_contains_rule "${SITE_CONTROLS_COORDINATOR}" "${SITE_CONTROLS_COORDINATOR_REL}" \
  'siteInfoVisible:|setOverlayVisible:|resolvePageToolsSurface:' \
  "Site Controls must use the fixed Page Tools surface owner instead of page facts or callbacks."
check_file_contains_rule "${SITE_CONTROLS_COORDINATOR}" "${SITE_CONTROLS_COORDINATOR_REL}" \
  'bindPageToolsSurface\(surface: BrowserSiteControlsPageToolsSurface\): void' \
  "Site Controls must receive the Page Tools surface through one construction-time binding."
check_file_contains_rule "${WEB_PAGE_TOOLS_COORDINATOR}" "${WEB_PAGE_TOOLS_COORDINATOR_REL}" \
  'siteControlsCoordinator\.bindPageToolsSurface\(this\)' \
  "Web Page Tools must complete the mutual Site Controls composition without page callback wiring."
check_file_not_contains_rule "${USER_AGENT_ACTION_COORDINATOR}" "${USER_AGENT_ACTION_COORDINATOR_REL}" \
  "'present_sheet'|'close_sheet'|sheetType\?:|replaceCurrentSheet\?:" \
  "User Agent actions must call the fixed Page Tools owner instead of emitting sheet effects for BrowserShell."
check_file_contains_rule "${USER_AGENT_ACTION_COORDINATOR}" "${USER_AGENT_ACTION_COORDINATOR_REL}" \
  'pageToolsCoordinator: BrowserWebPageToolsCoordinator' \
  "User Agent actions must compose the fixed Page Tools owner directly."
check_file_contains_rule "${USER_AGENT_ACTION_COORDINATOR}" "${USER_AGENT_ACTION_COORDINATOR_REL}" \
  'runtimePolicyCoordinator: BrowserUserAgentRuntimePolicyCoordinator' \
  "User Agent actions must delegate effective-identity runtime changes to the fixed runtime policy owner."
check_file_contains_rule "${USER_AGENT_RUNTIME_POLICY_COORDINATOR}" "${USER_AGENT_RUNTIME_POLICY_COORDINATOR_REL}" \
  'activeTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator' \
  "User Agent runtime policy must compose the fixed Active Runtime Restore owner directly."
check_file_contains_rule "${USER_AGENT_RUNTIME_POLICY_COORDINATOR}" "${USER_AGENT_RUNTIME_POLICY_COORDINATOR_REL}" \
  'activeTabRuntimeRestoreCoordinator\.reloadActive\(reloadReason\)' \
  "User Agent runtime policy must own its fixed active-page reload sequence."
check_file_not_contains_rule "${USER_AGENT_ACTION_COORDINATOR}" "${USER_AGENT_ACTION_COORDINATOR_REL}" \
  'BrowserUserAgentActionEffect|applyEffect:|private emit\(' \
  "User Agent actions must not return fixed reload sequencing to a page effect interpreter."
user_agent_action_sink_callback_count="$(awk '
  /export interface BrowserUserAgentActionSink \{/ { in_sink = 1; next }
  in_sink && /^}/ { print count + 0; exit }
  in_sink && /: \(/ { count += 1 }
' "${USER_AGENT_ACTION_COORDINATOR}")"
if [ "${user_agent_action_sink_callback_count}" -ne 4 ]; then
  report_failure "${USER_AGENT_ACTION_COORDINATOR_REL} Sink must keep exactly 4 facts/presentation/platform callbacks; found ${user_agent_action_sink_callback_count}."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private applyBrowserUserAgentActionEffect\(|BrowserUserAgentActionEffect' \
  "BrowserShellPage must not regain the User Agent effect-union interpreter."
check_file_not_contains_rule "${FULLSCREEN_SESSION_COORDINATOR}" "${FULLSCREEN_SESSION_COORDINATOR_REL}" \
  "'open_orientation_overlay'|'close_orientation_overlay'" \
  "Fullscreen must call the fixed Page Tools owner instead of emitting orientation-sheet effects for BrowserShell."
check_file_contains_rule "${FULLSCREEN_SESSION_COORDINATOR}" "${FULLSCREEN_SESSION_COORDINATOR_REL}" \
  'pageToolsCoordinator: BrowserWebPageToolsCoordinator' \
  "Fullscreen must compose the fixed Page Tools owner directly."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'onSelectScreenOrientation: \(|onSelectDesktopSiteMode: \(|onOpenDefaultUserAgent: \(\) => \{|onSelectUserAgentPreset: \(|onSelectCustomUserAgent: \(|onSiteControlsAction: \(|browserWebPageToolsCoordinator\.close\(\)' \
  "BrowserShellPage must forward Web Page Tools Overlay actions through one owner entry."
check_file_contains_rule "${ARK_WEB_MEDIA_TAKEOVER_COORDINATOR}" "${ARK_WEB_MEDIA_TAKEOVER_COORDINATOR_REL}" \
  'handleAssistantPlayerAction\(' \
  "Samsung Video Assistant actions must enter through the ArkWeb Media Takeover owner."
check_file_contains_rule "${SAMSUNG_VIDEO_ASSISTANT_PLAYER_OVERLAY}" \
  "${SAMSUNG_VIDEO_ASSISTANT_PLAYER_OVERLAY_REL}" \
  'onAction: \(action: BrowserArkWebMediaAssistantPlayerAction\)' \
  "Samsung Video Assistant Overlay must emit one typed owner action callback."
check_file_not_contains_rule "${SAMSUNG_VIDEO_ASSISTANT_PLAYER_OVERLAY}" \
  "${SAMSUNG_VIDEO_ASSISTANT_PLAYER_OVERLAY_REL}" \
  '^  (onClosePlayer|onRequestRotate|onWebLiveCommand):' \
  "Samsung Video Assistant Overlay must not regain peer player callbacks."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'arkWebMediaTakeoverCoordinator\.(closeAssistantPlayer|requestAssistantOrientation|executeWebLiveCommand)\(' \
  "BrowserShellPage must forward Samsung Video Assistant actions through one owner entry."
check_file_contains_rule "${WEB_PAGE_LIFECYCLE_COORDINATOR}" "${WEB_PAGE_LIFECYCLE_COORDINATOR_REL}" \
  'handleActiveLoadErrorSurfaceAction\(action: BrowserWebLoadErrorSurfaceAction\): void' \
  "Web Error surface actions must enter through the Web Page Lifecycle owner."
check_file_contains_rule "${WEB_ERROR_LAYER}" "${WEB_ERROR_LAYER_REL}" \
  'onAction: \(action: BrowserWebLoadErrorSurfaceAction\)' \
  "Web Error Layer must emit one typed owner action callback."
check_file_not_contains_rule "${WEB_ERROR_LAYER}" "${WEB_ERROR_LAYER_REL}" \
  '^  (onReload|onSecondaryAction):' \
  "Web Error Layer must not regain peer reload and platform callbacks."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserWebPageLifecycleApplicationCoordinator\.retryActivePageAfterLoadError\(|onSecondaryAction: \(\) => \{' \
  "BrowserShellPage must forward Web Error actions through the Lifecycle owner."

root_bottom_panel_presentation_snapshot_count="$(grep -Ec \
  '@State rootBottomPanelPresentationSnapshot: BrowserRootBottomPanelPresentationSnapshot' \
  "${SHELL_PAGE}" || true)"
if [ "${root_bottom_panel_presentation_snapshot_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must observe exactly one first-level Root Bottom Panel presentation snapshot."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserBottomAddressTransientMessageViewModel|browserBottomAddressTransientMessageViewModel|bottomAddressTransientPromptClearTimer|bottomAddressTransientPromptState|rootBottomPanelGesturePromptText|rootBottomPanelGesturePromptIntent|rootBottomPanelGesturePromptArmed|rootBottomPanelReturnHomeGestureActive|applyRootBottomPanelGesturePresentation|clearRootBottomPanelGesturePrompt' \
  "BrowserShellPage must not regain Root Bottom Panel gesture-prompt or transient-message canonical state and timers."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private (beginTransientBottomSheetPresentation|clearVideoAssistantForTab|resetWebBottomAddressPanelToDefaultHeightForNavigation)\(' \
  "BrowserShellPage must not regain orphan browser-flow methods with no receivers."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'this\.rootBottomPanelPresentationSnapshot\.revision;' \
  "Root Bottom Panel motion rendering must retain the explicit owner-published ArkUI revision dependency."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'transientMessageState: this\.rootBottomPanelPresentationSnapshot\.transientMessage' \
  "Bottom Address transient message rendering must remain an explicit ArkUI snapshot dependency."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'interface BrowserRootBottomPanelPresentationSnapshot' \
  "Root Bottom Panel must keep one canonical presentation snapshot."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'showTransientMessage\(' \
  "Bottom Address transient-message lifecycle must enter through the Root Bottom Panel owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'thresholdFeedbackRequested' \
  "Root Bottom Panel must own armed-threshold transition knowledge while leaving vibrator execution at the page boundary."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'transientMessageClearTimer' \
  "Root Bottom Panel must own transient-message timeout cleanup."
check_file_not_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'RootBottomPanelPresentationCoordinator|RootBottomPanelPresentationHostAdapter|RootBottomPanelPresentationPort' \
  "Root Bottom Panel presentation must deepen the existing owner instead of adding a peer Coordinator, HostAdapter, or Port."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'private executeActionDispatch\(dispatch: BrowserRootBottomPanelActionDispatch\): void' \
  "Root Bottom Panel immediate and deferred action dispatch must stay private to the Session owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'this\.resolveActionApplication\(\)\.apply\(dispatch, this\.sink\.isHomePageVisible\(\)\)' \
  "Root Bottom Panel Session must resolve one late-bound subordinate action application."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'this\.sink\.applyChromePlan\(plan\.chromePlan\);' \
  "Root Bottom Panel Session must apply chrome plans before immediate fixed-action execution."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'completePanelSettleAfterEffects\(\): void' \
  "Root Bottom Panel deferred actions must expose one semantic post-settle-effects completion entry."
check_file_not_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'actionPresentationCoordinator' \
  "Root Bottom Panel Session must not regain subordinate action-presentation implementation details."
root_bottom_panel_session_sink_callback_count="$(awk '
  /export interface BrowserRootBottomPanelSessionSink \{/ { in_sink = 1; next }
  in_sink && /^}/ { print count + 0; exit }
  in_sink && /: \(/ { count += 1 }
' "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}")"
if [ "${root_bottom_panel_session_sink_callback_count}" -ne 4 ]; then
  report_failure "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL} Session Sink must keep exactly four presentation/live-fact/chrome-effect/shell-effect callbacks; found ${root_bottom_panel_session_sink_callback_count}."
fi
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'class BrowserRootBottomPanelFixedActionApplication implements BrowserRootBottomPanelActionApplication' \
  "Root Bottom Panel fixed actions must remain in one subordinate application executor."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'private readonly actionPresentationCoordinator: BrowserBottomPanelActionPresentationCoordinator' \
  "Root Bottom Panel fixed action application must own subordinate action-presentation calculation."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'shellRouteCoordinator\.dispatchHomeRouteAction\(actionId\)' \
  "Root Bottom Panel Home route actions must execute through the fixed Shell Route owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  "return 'request_browser_back';" \
  "Root Bottom Panel Web Back must request the fixed Main Back narrative owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SHELL_ACTION_EXECUTOR}" \
  "${ROOT_BOTTOM_PANEL_SHELL_ACTION_EXECUTOR_REL}" \
  "case 'request_browser_back':" \
  "Root Bottom Panel Shell Action executor must retain the typed Browser Back boundary."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserMainBackCoordinator\.onBackPress\(this\.browserMainBackHost\)' \
  "BrowserShellPage must forward the typed Browser Back request to the fixed Main Back owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'fullscreenSessionCoordinator\.toggleManualFullscreen\(\)' \
  "Root Bottom Panel Fullscreen action must execute through the fixed Fullscreen owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'mediaResourceSessionCoordinator\.openResources\(\)' \
  "Root Bottom Panel resource action must execute through the fixed Media Resource owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'const dispatchAfterLowSettle = this\.isExpandedDetent\(snapshot\.currentDetent\);' \
  "Root Bottom Panel ordinary actions must inherit safe expanded-panel dispatch timing from the Session owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  "dispatchTiming: dispatchAfterLowSettle \? 'after_low_settle' : 'immediate'" \
  "Root Bottom Panel expanded actions must execute only after the low-detent settle effects complete."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'bookmarkActionCoordinator\.toggle\(this\.shell\.resolveBookmarkTarget\(\)\)' \
  "Root Bottom Panel Bookmark action must execute through the fixed Bookmark owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'pageFindCoordinator\.open\(facts\.activeTabId\)' \
  "Root Bottom Panel Page Find action must execute through the fixed Page Find owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'userReturnHomeCoordinator\.runFlow\(' \
  "Root Bottom Panel Home action must execute through the fixed User Return Home owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'phonePagePushCoordinator\.sendCurrentPageFromHost\(this\.shell\)' \
  "Root Bottom Panel Send to Desktop action must execute through the fixed Phone Page Push owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'webPrintService\.printCurrentPageFromLifecyclePort\(' \
  "Root Bottom Panel Print action must execute through the fixed Web Print owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'readerModeCoordinator\.openSessionFromLifecyclePort\(' \
  "Root Bottom Panel Reader action must execute through the fixed Reader Mode owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'export interface BrowserRootBottomPanelFixedActionShell extends' \
  "Root Bottom Panel fixed actions must read variable facts and UI effects through one typed shell."
check_file_not_contains_rule "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}" "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL}" \
  'BrowserRootBottomPanelActionCoordinator|BrowserRootBottomPanelActionPort|BrowserRootBottomPanelActionHost|HostAdapter' \
  "Root Bottom Panel action application must stay subordinate and must not become a peer Coordinator, Port, Host, or HostAdapter."
root_bottom_panel_action_dependency_callback_count="$(awk '
  /interface BrowserRootBottomPanelFixedActionDependencies \{/ { in_dependencies = 1; next }
  in_dependencies && /^}/ { print count + 0; exit }
  in_dependencies && /: \(/ { count += 1 }
' "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION}")"
if [ "${root_bottom_panel_action_dependency_callback_count}" -ne 0 ]; then
  report_failure "${ROOT_BOTTOM_PANEL_ACTION_APPLICATION_REL} fixed dependencies must be owner objects, not page forwarding callbacks; found ${root_bottom_panel_action_dependency_callback_count}."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private executeRootBottomPanelActionDispatch\(|private dispatchBottomAddressPanelBusinessAction\(|private dispatchRootBottomPanelHeaderBusinessAction\(|private dispatchHomeBottomPanelBusinessAction\(' \
  "BrowserShellPage must not regain Root Bottom Panel fixed-owner action interpreters."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'BrowserBottomPanelActionSnapshotInput|BrowserBottomPanelActionSurfaceInput|immediateDispatch|deferredDispatch|executeActionDispatch\(' \
  "BrowserShellPage must not regain Root Bottom Panel action-presentation assembly or dispatch representation."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private (shareCurrentPageUrl|sendCurrentPageToDesktop|printCurrentPage|openReaderMode|openPageFind|goHomeFromWebBottomPanel)\(|phonePagePushHost|browserUserReturnHomeFlowHost' \
  "BrowserShellPage must not regain Root Bottom Panel fixed-action wrappers or parallel feature hosts."
check_file_not_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" \
  "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'toggle_current_page_bookmark|open_page_find|go_home_from_web|share_current_page|send_current_page_to_desktop|print_current_page|open_reader_mode' \
  "Root Bottom Panel Session must not route fixed owner actions back through the page shell."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SHELL_ACTION_EXECUTOR}" \
  "${ROOT_BOTTOM_PANEL_SHELL_ACTION_EXECUTOR_REL}" \
  'class BrowserRootBottomPanelShellActionExecutor' \
  "Root Bottom Panel native/UI/platform shell effects must remain behind one typed executor."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'browserRootBottomPanelShellActionExecutor\.applyEffect\(effect\)' \
  "BrowserShellPage must keep only one-line Root Bottom Panel shell-effect forwarding."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private applyRootBottomPanelShellAction\(' \
  "BrowserShellPage must not regain Root Bottom Panel shell-action interpretation."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'private buildAddressInputChromePlan\(' \
  "Root Bottom Panel Address Input end/submit effects must converge inside the Session owner."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'shouldSyncBottomPanelStatusBarStyle: boolean' \
  "Root Bottom Panel Chrome Plan must preserve Address Input low-detent status-bar synchronization."
check_file_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'shouldReleaseHomeSearchBeforeBackdropEffects: boolean' \
  "Root Bottom Panel Chrome Plan must preserve Home Scrim release-before-backdrop ordering."
check_file_not_contains_rule "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR}" "${ROOT_BOTTOM_PANEL_SESSION_COORDINATOR_REL}" \
  'BrowserRootBottomPanelExpandedScrimDismissPlan|homeSearchDismissAction' \
  "Expanded Scrim dismissal must return the canonical Root Bottom Panel Chrome Plan without a wrapper result."
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private (applyRootAddressInputSessionEndPlan|applyRootAddressInputSubmitPlan|applyRootBottomPanelExpandedScrimDismissPlan)\(' \
  "BrowserShellPage must not regain duplicate Root Bottom Panel Address Input or Scrim plan interpreters."

check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_COORDINATOR}" "${WEB_LINK_CONTEXT_MENU_COORDINATOR_REL}" \
  'class WebLinkContextMenuCoordinator' \
  "Web Link Context Menu must keep one narrative owner."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_COORDINATOR}" "${WEB_LINK_CONTEXT_MENU_COORDINATOR_REL}" \
  'this\.resolveActionApplication\(\)\.applyEffects\(result\.effects\)' \
  "Web Link Context Menu must apply immediate effects inside its narrative owner."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_COORDINATOR}" "${WEB_LINK_CONTEXT_MENU_COORDINATOR_REL}" \
  'result\.completion\.then\(\(effects: WebContextMenuEffect\[\]\): void =>' \
  "Web Link Context Menu must apply asynchronous completion effects inside its narrative owner."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_COORDINATOR}" "${WEB_LINK_CONTEXT_MENU_COORDINATOR_REL}" \
  'hide\(tabId: string\): void' \
  "Web Link Context Menu callbacks must not expose internally applied effect arrays."
web_link_context_menu_sink_callback_count="$(awk '
  /export interface WebLinkContextMenuApplicationSink \{/ { in_sink = 1; next }
  in_sink && /^}/ { print count + 0; exit }
  in_sink && /: \(/ { count += 1 }
' "${WEB_LINK_CONTEXT_MENU_COORDINATOR}")"
if [ "${web_link_context_menu_sink_callback_count}" -ne 1 ]; then
  report_failure "${WEB_LINK_CONTEXT_MENU_COORDINATOR_REL} Application Sink must keep exactly one presentation callback; found ${web_link_context_menu_sink_callback_count}."
fi
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'class WebLinkContextMenuFixedActionApplication implements WebLinkContextMenuActionApplication' \
  "Web Link Context Menu fixed actions must remain in one subordinate application executor."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'appUrlOpenCoordinator\.open\(' \
  "Web Link Context Menu current-link opening must execute through the fixed App URL owner."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'privateTabCoordinator\.openPrivateWindow\(url\)' \
  "Web Link Context Menu private opening must execute through the existing Private Window owner."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_COORDINATOR}" "${WEB_LINK_CONTEXT_MENU_COORDINATOR_REL}" \
  "privateWindowPolicyService\.resolveTarget\(\) === 'new_window'" \
  "Web Link Context Menu private action must route through the device form-factor policy before choosing a new window."
check_file_contains_rule "${PRIVATE_WINDOW_POLICY_SERVICE}" "${PRIVATE_WINDOW_POLICY_SERVICE_REL}" \
  "deviceType === 'pc'" \
  "Private Window policy must recognize the PC device family."
check_file_contains_rule "${PRIVATE_WINDOW_POLICY_SERVICE}" "${PRIVATE_WINDOW_POLICY_SERVICE_REL}" \
  "deviceType === '2in1'" \
  "Private Window policy must recognize the 2-in-1 device family."
check_file_not_contains_rule "${PRIVATE_WINDOW_POLICY_SERVICE}" "${PRIVATE_WINDOW_POLICY_SERVICE_REL}" \
  "deviceType === 'tablet'" \
  "HarmonyOS tablets must not be classified as Private Window devices."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'foregroundTabCreationCoordinator\.createNewTab\(' \
  "Web Link Context Menu must preserve the phone and tablet private-tab fallback."
check_file_contains_rule "${PRIVATE_WINDOW_LAUNCH_SERVICE}" "${PRIVATE_WINDOW_LAUNCH_SERVICE_REL}" \
  "async openNewPrivateWindow\(initialUrl: string = ''\): Promise<void>" \
  "Private Window launch must accept an optional initial link target."
check_file_contains_rule "${WINDOW_LAUNCH_APPLICATION}" "${WINDOW_LAUNCH_APPLICATION_REL}" \
  'const targetUrl = payload\.uri\.trim\(\);' \
  "Private Window launch application must consume the carried initial link URL."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'bookmarkActionCoordinator\.startAdd\(' \
  "Web Link Context Menu bookmark creation must execute through the fixed Bookmark owner."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'downloadConfirmOverlayCoordinator\.requestAndPresent\(' \
  "Web Link Context Menu download confirmation must execute through the fixed Download Confirm owner."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'clipboardService\.copyText\(' \
  "Web Link Context Menu copy must execute through the fixed Clipboard service."
check_file_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'webPageShareService\.shareWebPage\(' \
  "Web Link Context Menu share must execute through the fixed Share service."
check_file_not_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" \
  "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'WebLinkContextMenuActionCoordinator|WebLinkContextMenuActionPort|WebLinkContextMenuActionHostAdapter|record_runtime_event' \
  "Web Link Context Menu action application must stay subordinate and must not regain a peer layer or dead runtime-event effect."
check_file_not_contains_rule "${WEB_LINK_CONTEXT_MENU_COORDINATOR}" \
  "${WEB_LINK_CONTEXT_MENU_COORDINATOR_REL}" \
  'record_runtime_event' \
  "Web Link Context Menu owner must not recreate runtime-event effects whose BrowserShell receiver is empty."
web_link_context_menu_dependency_callback_count="$(awk '
  /interface WebLinkContextMenuFixedActionDependencies \{/ { in_dependencies = 1; next }
  in_dependencies && /^}/ { print count + 0; exit }
  in_dependencies && /: \(/ { count += 1 }
' "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}")"
if [ "${web_link_context_menu_dependency_callback_count}" -ne 0 ]; then
  report_failure "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL} fixed dependencies must be owner objects, not page forwarding callbacks; found ${web_link_context_menu_dependency_callback_count}."
fi
web_link_context_menu_shell_callback_count="$(awk '
  /export interface WebLinkContextMenuActionShell \{/ { in_shell = 1; next }
  in_shell && /^}/ { print count + 0; exit }
  in_shell && /: \(/ { count += 1 }
' "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}")"
if [ "${web_link_context_menu_shell_callback_count}" -ne 5 ]; then
  report_failure "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL} Action Shell must keep exactly five live-fact/UI/Shared-Snapshot callbacks; found ${web_link_context_menu_shell_callback_count}."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private applyWebContextMenuResult\(|private applyWebContextMenuEffects\(|private shareWebPageUrl\(' \
  "BrowserShellPage must not regain Web Link Context Menu result/effect interpretation or fixed Share wrapper."
check_file_not_contains_rule "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION}" \
  "${WEB_LINK_CONTEXT_MENU_ACTION_APPLICATION_REL}" \
  'copyLink: \(url: string\) => void;|shareLink: \(title: string, url: string\) => void;' \
  "Web Link Context Menu shell must not regain fixed Clipboard or Share callbacks."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private async saveWebLinkFromContextMenuOffline\(' \
  "BrowserShellPage must preserve the Shared Snapshot-adjacent offline link save boundary."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'captureForegroundSeedSource\(' \
  "Web Link Context Menu offline save must preserve foreground Shared Snapshot seed capture."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  "source: 'web-page-container'" \
  "Web Link Context Menu offline save must preserve the protected Web-page-container preview seed path."

download_confirm_prompt_state_count="$(grep -Ec '@State pendingDownloadPrompt\?: PendingDownloadPromptState' \
  "${SHELL_PAGE}" || true)"
if [ "${download_confirm_prompt_state_count}" -ne 1 ]; then
  report_failure "${SHELL_PAGE_REL} must keep exactly one explicit first-level Download Confirm prompt state."
fi
check_file_not_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'private showManualDownloadConfirmSheet\(|private presentDownloadConfirmPrompt\(|private presentDownloadPromptRequest\(|private applyDownloadConfirmOverlayState\(|private resetDownloadConfirmOverlayState\(|private abandonPendingDownloadPromptForDisappear\(|private confirmPendingDownload\(|private cancelPendingDownload\(|private resolvePendingDownloadPromptFromServices\(|private recordDownloadOverlayDiagnostic\(|private buildDownloadBoundaryDiagnosticLine\(' \
  "BrowserShellPage must not regain Download Confirm request, presentation, action, reset, or diagnostic wrappers."
check_file_contains_rule "${SHELL_PAGE}" "${SHELL_PAGE_REL}" \
  'prompt: this\.pendingDownloadPrompt' \
  "Download Confirm content must keep the pending prompt as an explicit ArkUI state dependency."
check_file_contains_rule "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR}" "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR_REL}" \
  'class BrowserDownloadConfirmOverlayCoordinator' \
  "Download Confirm must keep one narrative owner."
check_file_contains_rule "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR}" "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR_REL}" \
  'requestAndPresent\(input: ManualDownloadRequestInput\): string' \
  "Manual Download Confirm requests must enter through the existing owner."
check_file_not_contains_rule "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR}" "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR_REL}" \
  'recordRuntimeEvent:|recordDiagnostic\(|buildBoundaryDiagnosticLine\(|pendingRevealDiagnosticStage|diagnosticViewModel|BrowserShellDiagnosticPresentationViewModel|currentUrl:|surfaceMounted:|surfaceVisible:|boundary:' \
  "Download Confirm must not regain removed runtime diagnostics or page-built diagnostic facts."
download_confirm_host_callback_count="$(awk '
  /export interface BrowserDownloadConfirmOverlayHost \{/ { in_host = 1; next }
  in_host && /^}/ { print count + 0; exit }
  in_host && /: \(/ { count += 1 }
' "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR}")"
if [ "${download_confirm_host_callback_count}" -ne 3 ]; then
  report_failure "${DOWNLOAD_CONFIRM_OVERLAY_COORDINATOR_REL} Host must keep exactly three true shell callbacks; found ${download_confirm_host_callback_count}."
fi

check_file_contains_rule "${NATIVE_TAB_SCENE_SERVICE}" "${NATIVE_TAB_SCENE_SERVICE_REL}" \
  "BOOKMARK_NATIVE_TAB_TITLE: string = '书签'" \
  "must keep the canonical Bookmarks native-tab title."
check_file_contains_rule "${NATIVE_TAB_SCENE_SERVICE}" "${NATIVE_TAB_SCENE_SERVICE_REL}" \
  "HISTORY_NATIVE_TAB_TITLE: string = '历史记录'" \
  "must keep the canonical History native-tab title."
check_file_contains_rule "${NATIVE_TAB_SCENE_SERVICE}" "${NATIVE_TAB_SCENE_SERVICE_REL}" \
  "SETTINGS_NATIVE_TAB_TITLE: string = '设置'" \
  "must keep the canonical Settings native-tab title."
check_file_contains_rule "${NATIVE_TAB_SCENE_SERVICE}" "${NATIVE_TAB_SCENE_SERVICE_REL}" \
  "DOWNLOADS_NATIVE_TAB_TITLE: string = '下载管理'" \
  "must keep the canonical Downloads native-tab title."
check_file_contains_rule "${NATIVE_TAB_SCENE_SERVICE}" "${NATIVE_TAB_SCENE_SERVICE_REL}" \
  "resolveCanonicalTitleForTab\(url: string, pendingUrl: string = ''\): string \| undefined" \
  "must own canonical native-tab title resolution for creation, restore, reuse, and projection."
check_file_contains_rule "${LARGE_SCREEN_TAB_SNAPSHOT_ADAPTER}" "${LARGE_SCREEN_TAB_SNAPSHOT_ADAPTER_REL}" \
  "browserNativeTabSceneService\.resolveCanonicalTitleForTab\(tab\.url, tab\.pendingUrl\)" \
  "must project canonical native-scene titles before applying the ordinary Home title fallback."

if [ "${ARCH_GUARD_ALLOW_PAGE_GROWTH:-0}" = "1" ]; then
  echo "Architecture page-growth diff guard bypassed by ARCH_GUARD_ALLOW_PAGE_GROWTH=1."
else
  while IFS=$'\t' read -r added deleted rel_path; do
    if [ -z "${rel_path:-}" ] || [ "${added}" = "-" ]; then
      continue
    fi
    case "${rel_path}" in
      ${PAGE_DIR_REL}/*.ets)
        net_added=$((added - deleted))
        if [ "${rel_path}" = "${SHELL_PAGE_REL}" ]; then
          if [ "${SHELL_DIFF_ADDED_LIMIT}" -gt 0 ] && [ "${added}" -gt "${SHELL_DIFF_ADDED_LIMIT}" ] && [ "${net_added}" -gt 0 ]; then
            report_failure "${SHELL_PAGE_REL} adds ${added} lines in the current diff and grows by ${net_added} lines; added-line limit is ${SHELL_DIFF_ADDED_LIMIT}. Keep shell edits small and move logic out of the page."
          fi
        elif [ "${added}" -gt "${PAGE_DIFF_ADDED_LIMIT}" ] && [ "${net_added}" -gt 0 ]; then
          report_failure "${rel_path} adds ${added} lines in the current diff and grows by ${net_added} lines; added-line limit is ${PAGE_DIFF_ADDED_LIMIT}. Large UI changes need components or a deliberate ARCH_GUARD_ALLOW_PAGE_GROWTH=1 override."
        fi
        ;;
    esac
  done < <(cd "${REPO_ROOT}" && git diff --numstat HEAD -- "${PAGE_DIR_REL}" || true)
fi

if ! "${REPO_ROOT}/scripts/check-novel-chapter-cache-contract.sh"; then
  report_failure "Novel Chapter Cache source contract must remain valid."
fi

if ! "${REPO_ROOT}/scripts/check-open-source-source-tree.sh"; then
  report_failure "Committed source tree must remain Community; Official identity is a packaging input."
fi

if [ "${failures}" -gt 0 ]; then
  cat >&2 <<'EOF'

Page files are UI shells. Put business logic in core/, services/, features/, or data/.
See AGENTS.md for the repository rule.

For deliberate large UI-only work, rerun with:
  ARCH_GUARD_ALLOW_PAGE_GROWTH=1 ./scripts/build-aira-browser.sh
EOF
  exit 1
fi

echo "Architecture guardrails passed."
