import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { FrameCallback, KeyboardAvoidMode, window } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import router from '@ohos.router';
import {
  BrowserDataScope,
  AdBlockSettings,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  SearchEngineId,
  SearchEngineRecord,
  SearchSuggestion,
  ShortcutRecord,
  BrowserExperimentSettings,
  ExternalAppSearchTargetId,
  BrowserHomeShortcutLayoutDensity,
  TabDiscardReason,
  TabRecord,
  TabRestoreReason,
  TabRuntimeState
} from '../../common/models/BrowserModels';
import {
  QUICK_SEARCH_SWITCHING_PREFERENCES_REVISION_KEY,
  SEARCH_ENGINE_SETTINGS_REVISION_KEY
} from '../../common/constants/SearchPreferenceKeys';
import {
  CustomHomepageRuntimeCoordinator,
  CustomHomepageRuntimeShellEffect,
  CustomHomepageRuntimeShellFacts,
  CustomHomepageRuntimeShellHost,
  CustomHomepageRuntimeShellState
} from '../../core/customhome/CustomHomepageRuntimeCoordinator';
import {
  CustomHomepageHostedWebNodeController
} from '../../core/customhome/CustomHomepageHostedWebNode';
import { SearchEngineSelectionCoordinator } from '../../core/search/SearchEngineSelectionCoordinator';
import {
  SITE_CUSTOMIZATION_REFRESH_REVISION_KEY,
  SiteCustomizationRefreshSignal
} from '../../core/sitecustomization/SiteCustomizationRefreshSignal';
import {
  SiteCustomizationRuntimeRefreshCoordinator,
  SiteCustomizationRuntimeRefreshPlan
} from '../../core/sitecustomization/SiteCustomizationRuntimeRefreshCoordinator';
import { HistoryFeature } from '../../features/history/HistoryFeature';
import { BrowserThemePaletteService } from '../../services/theme/BrowserThemePaletteService';
import {
  BrowserActiveTabRuntimeRestoreCoordinator,
  BrowserActiveTabRuntimeRestoreHost,
  BrowserActiveTabRuntimeRestoreStateApplication
} from '../../services/web/BrowserActiveTabRuntimeRestoreCoordinator';
import {
  BrowserControllerAttachmentRuntimeCoordinator,
  BrowserControllerAttachmentRuntimeCoordinatorHost
} from '../../services/web/BrowserControllerAttachmentRuntimeCoordinator';
import {
  BrowserRuntimeLifecyclePort,
  BrowserRuntimeLifecyclePortHost,
  BrowserRuntimeMutationPort
} from '../../services/web/BrowserRuntimeLifecyclePort';
import {
  BrowserWebLoadOpenResolvedUrlState,
  BrowserWebLoadRuntimeCoordinator,
  BrowserWebLoadRuntimeDependencies,
  BrowserWebLoadRuntimeFacts,
  BrowserWebLoadRuntimeHostBindings
} from '../../services/web/BrowserWebLoadRuntimeCoordinator';
import { BrowserWebHistoryCommandRuntimeCoordinator } from '../../core/browser/BrowserWebHistoryCommandRuntimeCoordinator';
import {
  BrowserActiveTabShellStateCoordinator
} from '../../services/web/BrowserActiveTabShellStateCoordinator';
import { BrowserTabRuntimeLifecycleService } from '../../services/web/BrowserTabRuntimeLifecycleService';
import {
  BrowserHostedRuntimeActiveSurfaceConfig,
  BrowserHostedRuntimePreviewSurfaceConfig,
  BrowserHostedRuntimeSurfacePort,
  BrowserHostedRuntimeSurfacePortHost
} from '../../services/web/BrowserHostedRuntimeSurfacePort';
import {
  BrowserTabBackgroundSessionSyncCoordinator,
  BrowserTabBackgroundSessionSyncCoordinatorHost
} from '../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import { BrowserClipboardCopyResult, BrowserClipboardService } from '../../services/share/BrowserClipboardService';
import { BrowserDesktopBookmarkBarAction } from '../../core/browser/BrowserDesktopBookmarkBarViewModel';
import { WebPageShareService } from '../../services/share/WebPageShareService';
import { BrowserUserAgentClientHintsService } from '../../services/web/BrowserUserAgentClientHintsService';
import { BrowserUserAgentRuntimeService } from '../../services/web/BrowserUserAgentRuntimeService';
import { WebScrollSmoothModeService } from '../../services/web/WebScrollSmoothModeService';
import {
  DocumentViewerChromeContext,
  DocumentViewerFileInfo,
  DocumentViewerService
} from '../../services/viewer/DocumentViewerService';
import {
  sharedBookmarkRepository,
  sharedAdBlockRepository,
  sharedManualElementHideRepository,
  sharedDownloadRuntimeService,
  sharedHistoryRepository,
  sharedOfflinePageRepository,
  sharedPreferencesRepository,
  sharedRecentlyClosedTabRepository,
  sharedQuickSearchSwitchPreferencesRepository,
  sharedSearchEngineRepository,
  sharedSearchEngineRoutingService,
  sharedSearchQueryHistoryService,
  sharedShortcutIconResolverService,
  sharedShortcutRepository,
  sharedSitePolicyService,
  sharedSiteClearOnClosePendingRepository,
  sharedPrivateModeCookieSnapshotRepository,
  sharedWallpaperRepository,
  sharedCustomHomepageRepository,
  sharedBrowserSitePrivacyRuleRepository,
  sharedSavedSiteSettingRepository,
  sharedBrowserSecurityReportMetricsRepository,
  sharedBrowserUserAgentSettingsRepository,
  sharedTranslationSecretStore,
  sharedTranslationSettingsRepository,
  createUserScriptBrowserRuntimeCoordinator,
  sharedMembershipFeature,
  sharedAiraSyncConfigStore,
  sharedBookmarkFolderSelectionPreparationCoordinator,
  sharedArkWebAppProxyService,
  sharedBrowserProxyRuntimeRefreshCoordinator,
  sharedActivityTracker,
  sharedAppReviewPromptRepository,
  sharedReleaseNoticeCoordinator,
  sharedClientUpdatePolicyService,
  sharedAiraCloudBookmarkV4BootstrapRuntime,
  sharedBrowserGestureOnboardingPromptCoordinator,
  syncBrowserThemeAppStorage
} from '../bootstrap/BrowserAppRuntime';
import {
  AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_REVISION_KEY
} from '../../core/sync/AiraCloudBookmarkV4BootstrapRuntime';
import {
  AiraCloudBookmarkV4BootstrapViewState
} from '../../core/sync/AiraCloudBookmarkV4BootstrapViewModelService';
import {
  AppReviewPromptCoordinator,
  AppReviewPromptShell,
  AppReviewPromptShellFacts
} from '../../core/review/AppReviewPromptCoordinator';
import { ReleaseNoticeUiState } from '../../core/update/ReleaseNoticeCoordinator';
import {
  ClientUpdatePolicyState
} from '../../services/update/ClientUpdatePolicyService';
import {
  ReleaseNoticePresentationCoordinator,
  ReleaseNoticePresentationShellFacts
} from '../../core/update/ReleaseNoticePresentationCoordinator';
import {
  BrowserHomePagePresentationState,
  BrowserHomePresentationViewModel,
  BrowserHomeSurfaceContentPresentationState
} from '../../core/browser/BrowserHomePresentationViewModel';
import {
  BrowserHomePresentationAnimationPlan,
  BrowserHomePresentationSessionCoordinator,
  BrowserHomePresentationSessionFacts,
  BrowserHomePresentationSessionHost,
  BrowserHomePresentationSessionState
} from '../../core/browser/BrowserHomePresentationSessionCoordinator';
import {
  BrowserBackdropEffectState,
  DEFAULT_BROWSER_BACKDROP_EFFECT_STATE,
  BrowserBackdropEffectViewModel
} from '../../core/browser/BrowserBackdropEffectViewModel';
import {
  BrowserHomepageBackdropAppearanceCoordinator
} from '../../core/browser/BrowserHomepageBackdropAppearanceCoordinator';
import {
  BrowserHomepageBackdropAppearanceState,
  DEFAULT_BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_STATE,
  cloneBrowserHomepageBackdropAppearanceState
} from '../../common/models/BackdropAppearanceModels';
import { sharedBrowserTabPreviewMetrics } from '../../core/browser/BrowserTabPreviewMetricsService';
import { TelegramWebCompatibilityService } from '../../services/web/TelegramWebCompatibilityService';
import { BrowserWebLayerGeometryStore } from '../../data/browser/BrowserWebLayerGeometryStore';
import {
  BrowserAddressSubmissionCoordinator,
  BrowserAddressSubmissionPresentation,
  BrowserAddressSubmissionResult,
  BrowserAddressSubmissionShell
} from '../../core/navigation/BrowserAddressSubmissionCoordinator';
import { SearchEngineRoutingMode } from '../../services/search/SearchEngineRoutingService';
import { BrowserSearchSubmissionHistoryCoordinator } from '../../core/navigation/BrowserSearchSubmissionHistoryCoordinator';
import { ExternalAppSearchPrivateConfirmation } from '../../services/search/ExternalAppSearchService';
import {
  resolveCurrentSiteUrl
} from '../../core/browser/AddressDisplayFormatter';
import { BrowserAddressDisplayCoordinator } from '../../core/browser/BrowserAddressDisplayCoordinator';
import { BrowserThemeModeCoordinator } from '../../core/browser/BrowserThemeModeCoordinator';
import {
  BrowserUserAgentActionCoordinator,
  BrowserUserAgentActionFacts,
  BrowserUserAgentActionPresentation,
  BrowserUserAgentActionSink
} from '../../core/browser/BrowserUserAgentActionCoordinator';
import { BrowserBrowsingIdentityPolicyCoordinator } from '../../core/browser/BrowserBrowsingIdentityPolicyCoordinator';
import {
  BrowserUserAgentRuntimeTransitionCoordinator,
  BrowserUserAgentRuntimeTransitionHost
} from '../../core/browser/BrowserUserAgentRuntimeTransitionCoordinator';
import { BrowserUserAgentRuntimePolicyCoordinator } from '../../core/browser/BrowserUserAgentRuntimePolicyCoordinator';
import { BrowserFaultClassifier } from '../../core/browser/BrowserFaultClassifier';
import { BrowserRestoreCoordinator } from '../../core/browser/BrowserRestoreCoordinator';
import {
  BrowserActiveRuntimeSyncCoordinator,
  BrowserActiveRuntimeSyncSink
} from '../../core/browser/BrowserActiveRuntimeSyncCoordinator';
import {
  BrowserPrivateBoundaryNavigationService,
  BrowserPrivateBoundaryRouteParams
} from '../../core/browser/BrowserPrivateBoundaryNavigationService';
import {
  BROWSER_EXPERIMENT_SETTINGS_REFRESH_REVISION_KEY
} from '../../core/settings/BrowserExperimentSettingsRefreshSignal';
import {
  BrowserPrivateSessionCleanupCoordinator,
  BrowserPrivateSessionCleanupFacts,
  BrowserPrivateSessionCleanupShell
} from '../../core/browser/BrowserPrivateSessionCleanupCoordinator';
import {
  BrowserPrivateProfileCookieLifecycleHost,
  BrowserPrivateProfileLifecycleCoordinator
} from '../../core/browser/BrowserPrivateProfileLifecycleCoordinator';
import {
  BrowserPrivateModeConfirmationHost,
  BrowserPrivateModeConfirmationState,
  BrowserPrivateModeEntryPlan,
  BrowserPrivateModeExitHost,
  BrowserPrivateModeTogglePresentationHost,
  BrowserPrivateTabCoordinator
} from '../../core/browser/BrowserPrivateTabCoordinator';
import {
  BrowserPrivateModeLockCoordinator,
  BrowserPrivateModeLockSessionFacts,
  BrowserPrivateModeLockSessionSnapshot
} from '../../core/privacy/BrowserPrivateModeLockCoordinator';
import {
  BROWSER_PRIVATE_FOREGROUND_REVISION_KEY
} from '../../core/privacy/BrowserPrivateModeForegroundSignal';
import {
  BROWSER_TAB_PREVIEW_LIFECYCLE_CAPTURE_REVISION_KEY
} from '../../core/browser/BrowserTabPreviewLifecycleSignal';
import {
  BrowserShellRouteCoordinator,
  BrowserShellRouteCoordinatorHost
} from '../../core/browser/BrowserShellRouteCoordinator';
import {
  BrowserMediaResourceSessionCoordinator,
  BrowserMediaResourceSessionShell,
  BrowserMediaResourceSessionSnapshot,
  createBrowserMediaResourceSessionSnapshot
} from '../../core/browser/BrowserMediaResourceSessionCoordinator';
import {
  BrowserTabSessionPersistenceHost,
  BrowserTabSessionPersistenceCoordinator
} from '../../core/browser/BrowserTabSessionPersistenceCoordinator';
import { BrowserTabPreviewAssetBoundaryCoordinator } from '../../core/browser/BrowserTabPreviewAssetBoundaryCoordinator';
import { BROWSER_SYSTEM_MEMORY_PRESSURE_REVISION_KEY } from '../../core/browser/BrowserSystemMemoryPressureSignal';
import {
  BrowserChromeRuntimeCoordinator,
  BrowserChromeRuntimeState
} from '../../core/browser/BrowserChromeRuntimeCoordinator';
import {
  BrowserSmartGripCoordinator,
  BrowserSmartGripState
} from '../../core/browser/BrowserSmartGripCoordinator';
import { BrowserSmartGripTabsOverviewViewModel } from '../../core/browser/BrowserSmartGripTabsOverviewViewModel';
import { BrowserLoadingProgressState } from '../../core/browser/BrowserLoadingProgressCoordinator';
import {
  BrowserWebLoadingProgressBarPresentationState,
  BrowserWebLoadingProgressBarPresentationViewModel
} from '../../core/browser/BrowserWebLoadingProgressBarPresentationViewModel';
import {
  BrowserPullRefreshCoordinator,
  BrowserPullRefreshShell,
  BrowserPullRefreshSurfaceFacts
} from '../../core/browser/BrowserPullRefreshCoordinator';
import { BrowserPullRefreshState } from '../../core/browser/BrowserPullRefreshModels';
import { BrowserScrollPerformanceCoordinator } from '../../core/browser/BrowserScrollPerformanceCoordinator';
import {
  BrowserTabsOverviewHeaderMode,
  BrowserTabsOverviewSceneRenderState
} from '../../core/browser/tabsOverview/BrowserTabsOverviewSceneDriver';
import { BrowserTabsOverlayRect } from '../../core/browser/BrowserTabsOverlayViewModel';
import { BrowserTabsSharedSnapshotTransitionState } from
  '../../core/browser/BrowserTabsSharedSnapshotTransitionCoordinator';
import {
  BrowserTabsOverviewAsyncTask,
  BrowserTabsOverviewAsyncTaskResult,
  BrowserTabsOverviewSessionEffect,
  BrowserTabsOverviewBackgroundRenderState,
  BrowserTabsOverviewSessionAction,
  BrowserTabsOverviewSessionCoordinator,
  BrowserTabsOverviewSessionFacts,
  BrowserTabsOverviewSessionHost,
  BrowserTabsOverviewSessionPresentationState,
  BrowserTabsOverviewSessionSection
} from '../../core/browser/BrowserTabsOverviewSessionCoordinator';
import {
  BrowserTabsOverviewSnapshotPipelineEntryCaptureInput,
  BrowserTabsOverviewSnapshotPipelineExternalCaptureInput,
  BrowserTabsOverviewSnapshotPipelineCoordinator,
  BrowserTabsOverviewSnapshotPipelineState
} from '../../core/browser/tabsOverview/BrowserTabsOverviewSnapshotPipelineCoordinator';
import {
  BrowserWebLayerGeometryCache,
  BrowserWebLayerGeometrySnapshot,
  BrowserWebLayerRect
} from '../../core/browser/BrowserWebLayerGeometryCache';
import {
  BrowserSearchSuggestionCoordinator,
  BrowserSearchSuggestionRuntimeFacts,
  BrowserSearchSuggestionShell,
  BrowserSearchSuggestionSnapshot
} from '../../core/browser/BrowserSearchSuggestionCoordinator';
import { BrowserAdBlockCoordinator } from '../../core/browser/BrowserAdBlockCoordinator';
import {
  BrowserSiteControlsApplicationShell,
  BrowserSiteControlsApplicationSnapshot,
  BrowserSiteControlsRuntimeFacts,
  BrowserSiteControlsRuntimeCoordinator
} from '../../core/browser/BrowserSiteControlsRuntimeCoordinator';
import { BrowserMediaDiscoveryCoordinator } from '../../core/browser/media/BrowserMediaDiscoveryCoordinator';
import { BrowserMediaDiscoveryRuntimeContextFactory } from '../../core/browser/media/BrowserMediaDiscoveryRuntimeContextFactory';
import {
  BrowserMediaDiscoveryHost,
  BrowserMediaDiscoveryRuntimeContext,
  BrowserMediaDiscoverySurfaceState
} from '../../core/browser/media/BrowserMediaDiscoveryModels';
import {
  BrowserMediaDiscoveryRuntime,
  createBrowserMediaDiscoveryRuntime
} from '../../core/browser/media/BrowserMediaDiscoveryRuntimeFactory';
import {
  BrowserArkWebMediaAssistantOrientation,
  BrowserArkWebMediaAssistantPlayerHost,
  BrowserArkWebMediaLaunchHost,
  BrowserArkWebMediaTakeoverCoordinator
} from '../../core/browser/media/BrowserArkWebMediaTakeoverCoordinator';
import {
  BrowserMediaRuntimeObservationApplicationCoordinator,
  BrowserMediaRuntimeObservationApplicationHost
} from '../../core/browser/media/BrowserMediaRuntimeObservationApplicationCoordinator';
import {
  BrowserPhonePagePushCoordinator,
  BrowserPhonePagePushSnapshot,
} from '../../core/browser/BrowserPhonePagePushCoordinator';
import {
  BrowserToolbarSystemSheetContent,
  isBrowserToolbarSystemSheetType
} from '../components/browser/BrowserToolbarSystemSheetContent';
import { BrowserHlsTakeoverOverlay } from '../components/browser/BrowserHlsTakeoverSheet';
import {
  BrowserVideoAssistantPlayerOverlay
} from '../components/browser/BrowserVideoAssistantPlayerOverlay';
import {
  BrowserWindowOpenApplicationCoordinator,
  BrowserWindowOpenApplicationHost
} from '../../core/browser/BrowserWindowOpenApplicationCoordinator';
import {
  BrowserStartupTabRestoreCoordinator,
  BrowserStartupTabRestoreHost,
  BrowserStartupTabRestoreStateApplication
} from '../../core/browser/BrowserStartupTabRestoreCoordinator';
import {
  BrowserTabScopedEventContextCoordinator,
  BrowserTabScopedEventContextFacts,
  BrowserTabScopedEventContextHost,
} from '../../core/browser/BrowserTabScopedEventContextCoordinator';
import {
  BrowserHistoryVisitPersistenceCoordinator
} from '../../core/browser/BrowserHistoryVisitPersistenceCoordinator';
import {
  BrowserHostedWebNodeDisposeReason,
  BrowserPageReloadReason
} from '../../core/browser/BrowserRuntimeActionReason';
import {
  BrowserHistoryApiBridgePolicy
} from '../../core/web/BrowserHistoryApiBridge';
import { BrowserShellStateCoordinator, BrowserShellVisualState } from '../../core/browser/BrowserShellStateCoordinator';
import {
  BrowserMainBackCoordinator,
  BrowserMainBackHost
} from '../../core/browser/BrowserMainBackCoordinator';
import {
  ElementInspectionPresentation,
  ElementInspectionSessionCoordinator,
  ElementInspectionSessionFacts,
  ElementInspectionSessionShell
} from '../../core/browser/ElementInspectionSessionCoordinator';
import {
  BrowserShellLifecycleAppearanceState,
  BrowserShellLifecycleCoordinator,
  BrowserShellLifecycleFacts,
  BrowserShellLifecycleShell
} from '../../core/browser/BrowserShellLifecycleCoordinator';
import {
  BrowserShellBackState
} from '../../core/browser/BrowserShellBackCoordinator';
import {
  BrowserBottomAddressPanelBackRequest
} from '../../core/browser/BrowserBottomAddressPanelBackController';
import { BrowserSystemBackRequest } from '../../core/browser/BrowserSystemBackCoordinator';
import {
  BrowserAppUrlOpenCoordinator,
  BrowserAppUrlOpenHost,
  BrowserAppUrlOpenRequest
} from '../../core/browser/BrowserAppUrlOpenCoordinator';
import {
  BrowserUrlThreatNoticeState,
  BrowserUrlThreatProtectionCoordinator,
  BrowserUrlThreatProtectionHost,
  HIDDEN_BROWSER_URL_THREAT_NOTICE_STATE
} from '../../core/browser/BrowserUrlThreatProtectionCoordinator';
import {
  BrowserForegroundTabCreationCoordinator,
  BrowserTabCreationStateApplication
} from '../../core/browser/BrowserForegroundTabCreationCoordinator';
import {
  BrowserTabSwitchApplicationSink,
  BrowserTabSwitchCoordinator
} from '../../core/browser/BrowserTabSwitchCoordinator';
import {
  BrowserBottomChromeScrollCoordinator,
  BrowserBottomChromeWebScrollDecision
} from '../../core/browser/BrowserBottomChromeScrollCoordinator';
import {
  BrowserBottomAddressContextAction,
  BrowserBottomChromeGestureSource
} from '../../core/browser/BrowserBottomChromePresentationViewModel';
import { HomeWallpaperCoordinator } from '../../core/wallpaper/HomeWallpaperCoordinator';
import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState
} from '../../common/models/WallpaperModels';
import {
  BrowserSnapshotApplicationHost,
  BrowserSnapshotPersistenceHost,
  BrowserTabRecoveryCoordinator
} from '../../core/browser/BrowserTabRecoveryCoordinator';
import { BrowserTabHomeCoordinator, BrowserTabHomeShell } from '../../core/browser/BrowserTabHomeCoordinator';
import {
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT,
  BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT
} from '../../core/browser/BrowserBottomAddressPanelMetrics';
import {
  BrowserCloseTabAnimationPlan,
  BrowserCloseTabApplicationHost,
  BrowserCloseTabHomeRevealMotion,
  BrowserTabCloseApplicationState,
  BrowserTabCloseCoordinator
} from '../../core/browser/BrowserTabCloseCoordinator';
import {
  BrowserTabsOverviewThemeState,
  BrowserTabsOverviewThemeViewModel
} from '../../core/browser/tabsOverview/BrowserTabsOverviewThemeViewModel';
import { BrowserRootBackgroundViewModel } from '../../core/browser/BrowserRootBackgroundViewModel';
import { BrowserOpenTabsButtonViewModel } from '../../core/browser/BrowserOpenTabsButtonViewModel';
import {
  BrowserRecentlyClosedApplicationCoordinator,
  BrowserRecentlyClosedApplicationFacts,
  BrowserRecentlyClosedApplicationShell,
  BrowserRecentlyClosedApplicationSnapshot,
  createBrowserRecentlyClosedApplicationSnapshot
} from '../../core/browser/BrowserRecentlyClosedApplicationCoordinator';
import { BrowserConfirmationRequest } from '../../core/browser/BrowserConfirmationSink';
import { BrowserRecentlyClosedTabsService } from '../../core/browser/BrowserRecentlyClosedTabsService';
import {
  BrowserTabPreviewCaptureRequest,
  BrowserTabPreviewCaptureShellInput,
  BrowserTabPreviewCoordinator,
  BrowserTabPreviewSurfaceHost,
  BrowserTabPreviewState
} from '../../core/browser/BrowserTabPreviewCoordinator';
import { BrowserFaviconApplyHost } from '../../core/browser/BrowserFaviconCoordinator';
import {
  BrowserTabPreviewActionCoordinator,
  BrowserTabPreviewActionPort,
  BrowserTabPreviewActionRequestOptions,
  BrowserTabPreviewOpenerBeforeSwitchInput,
  BrowserTabPreviewOpenerBeforeSwitchSource
} from '../../core/browser/BrowserTabPreviewActionCoordinator';
import {
  BrowserBackgroundTabPreviewRequest
} from '../../core/browser/BrowserBackgroundTabPreviewCoordinator';
import {
  BrowserBackgroundTabPreviewRuntimeCoordinator,
  BrowserBackgroundTabPreviewRuntimeHost,
  BrowserBackgroundTabPreviewRuntimeOptions
} from '../../core/browser/BrowserBackgroundTabPreviewRuntimeCoordinator';
import {
  BrowserBackgroundOpenPromptCoordinator,
  BrowserBackgroundOpenPromptShell,
  BrowserBackgroundOpenPromptState
} from '../../core/browser/BrowserBackgroundOpenPromptCoordinator';
import {
  BrowserTopFloatingPromptActionShell,
  BrowserTopFloatingPromptCoordinator,
  BrowserTopFloatingPromptHostState,
  BrowserTopFloatingPromptShellInput
} from '../../core/browser/BrowserTopFloatingPromptCoordinator';
import {
  BrowserGestureOnboardingTopPromptState,
  HIDDEN_BROWSER_GESTURE_ONBOARDING_TOP_PROMPT_STATE
} from '../../core/browser/BrowserGestureOnboardingPromptCoordinator';
import {
  ExternalNavigationPromptPageContext,
  ExternalNavigationPromptPresentationContext,
  ExternalNavigationPromptState
} from '../../core/browser/ExternalNavigationPromptViewModel';
import { BrowserTabPreviewDebugExportService } from '../../services/web/BrowserTabPreviewDebugExportService';
import { BrowserTabTransitionResult } from '../../core/browser/BrowserTabTransitionCoordinator';
import {
  BrowserUserReturnHomeCoordinator,
  BrowserUserReturnHomeSource
} from '../../core/browser/BrowserUserReturnHomeCoordinator';
import {
  BrowserSystemSheetLifecycleEffect,
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceCoordinator,
  BrowserTransientSurfaceId,
  BrowserTransientSurfaceSnapshot,
  BrowserTransientSurfaceUpdate
} from '../../core/browser/BrowserTransientSurfaceCoordinator';
import {
  BrowserBottomPanelActionTarget,
  BrowserBottomPanelBackdropSurface,
  BrowserBottomAddressPresentationInput,
  BrowserBottomAddressSuggestionInput,
  BrowserBottomAddressTransientMessageContext,
  BrowserRootBottomPanelActionSource,
  BrowserRootBottomPanelChromePlan,
  BrowserRootBottomPanelExpandedScrimState,
  BrowserRootBottomPanelGestureInput,
  BrowserRootBottomPanelPresentationSnapshot,
  BrowserBottomPanelHostInput,
  BrowserBottomPanelHostState,
  BrowserRootBottomPanelLayoutState,
  BrowserRootBottomPanelMotionInput,
  BrowserRootBottomPanelScene,
  BrowserRootBottomPanelSemanticInput,
  BrowserRootBottomPanelSemanticState,
  BrowserRootBottomPanelSessionCoordinator,
  BrowserRootBottomPanelSessionSnapshot,
  BrowserRootBottomPanelShellEffect,
  BrowserRootBottomPanelTransientSheetFacts,
  BrowserRootBottomPanelTransientSheetOwner,
  BrowserRootAddressInputSessionSnapshot
} from '../../core/browser/BrowserRootBottomPanelSessionCoordinator';
import { BrowserToolbarSlotId } from '../../core/browser/BrowserToolbarCustomizationViewModel';
import {
  BrowserRootBottomPanelFixedActionApplication,
  BrowserRootBottomPanelFixedActionFacts,
  BrowserRootBottomPanelFixedActionShell
} from '../../core/browser/BrowserRootBottomPanelActionApplication';
import {
  BrowserRootBottomPanelShellActionExecutor
} from '../../core/browser/BrowserRootBottomPanelShellActionExecutor';
import {
  BrowserShellSearchInvocationAdapter,
  BrowserShellSearchInvocationHost
} from '../../core/browser/BrowserShellSearchInvocationAdapter';
import {
  SiteClearOnCloseCoordinator,
  SiteClearOnCloseCoordinatorHost
} from '../../core/browser/SiteClearOnCloseCoordinator';
import {
  BrowserWebActiveSurfaceCoordinator,
  BrowserWebActiveSurfaceFacts,
  BrowserWebActiveSurfaceShell,
  BrowserWebActiveSurfaceStateApplication
} from '../../core/browser/BrowserWebActiveSurfaceCoordinator';
import {
  BrowserWebEventCommitCoordinator,
  BrowserWebRuntimeEventCommit
} from '../../core/browser/BrowserWebEventCommitCoordinator';
import { BrowserWebEventHostCoordinator } from '../../core/browser/BrowserWebEventHostCoordinator';
import {
  BrowserWebHostAttachState,
  BrowserWebHostCoordinator
} from '../../core/browser/BrowserWebHostCoordinator';
import { BrowserHostedWebDocumentStartScriptCoordinator } from '../../core/web/BrowserHostedWebDocumentStartScriptCoordinator';
import {
  BrowserHostedWebHiddenSlot,
  BrowserHostedWebOwnershipCoordinator
} from '../../core/browser/BrowserHostedWebOwnershipCoordinator';
import { BROWSER_SYSTEM_FONT_SIZE_SCALE_STORAGE_KEY } from '../../core/browser/BrowserSystemFontScaleCoordinator';
import {
  BrowserWebTextZoomAction,
  BrowserWebTextZoomState,
  BrowserWebTextZoomViewModel
} from '../../core/browser/BrowserWebTextZoomViewModel';
import {
  BrowserWebScrollInteractionCoordinator,
  BrowserWebScrollInteractionShell
} from '../../core/browser/BrowserWebScrollInteractionCoordinator';
import { BrowserWebLoadFailureSurfaceCoordinator } from '../../core/browser/BrowserWebLoadFailureSurfaceCoordinator';
import {
  BrowserDownloadNavigationRuntimeSanitizationPatch,
  BrowserDownloadNavigationStateCoordinator
} from '../../core/browser/BrowserDownloadNavigationStateCoordinator';
import {
  BrowserDownloadConfirmOverlayCoordinator,
  BrowserDownloadConfirmOverlayFacts,
  BrowserDownloadConfirmOverlayHost
} from '../../core/browser/BrowserDownloadConfirmOverlayCoordinator';
import {
  BrowserWebActiveTabChange,
  BrowserWebTabsController,
  BrowserWebTabsControllerDependencies,
  BrowserWebTabsControllerHost,
  BrowserWebTabsControllerTabSnapshot
} from '../../core/browser/BrowserWebTabsController';
import {
  BrowserUnifiedLinkApplicationCoordinator,
  BrowserUnifiedLinkApplicationShell
} from '../../core/browser/BrowserUnifiedLinkApplicationCoordinator';
import { BrowserExternalNavigationRuntimeStateCoordinator } from '../../core/browser/BrowserExternalNavigationRuntimeStateCoordinator';
import {
  BrowserHttpAuthDialogPresentation,
  BrowserSitePermissionDialogPresentation,
  BrowserWebCapabilityPromptApplicationEffect,
  BrowserWebCapabilityPromptApplicationCoordinator,
  BrowserWebCapabilityPromptApplicationSink,
  BrowserWebPromptDialogPresentation,
  createEmptyBrowserHttpAuthDialogPresentation,
  createEmptyBrowserSitePermissionDialogPresentation,
  createEmptyBrowserWebPromptDialogPresentation
} from '../../core/browser/BrowserWebCapabilityPromptApplicationCoordinator';
import {
  BrowserWebCapabilityPromptEffectApplication,
  BrowserWebCapabilityPromptEffectShell,
  BrowserWebCapabilityPromptMessageKind
} from '../../core/browser/BrowserWebCapabilityPromptEffectApplication';
import { BrowserWebDialogQueueKind } from '../../core/browser/BrowserWebDialogQueue';
import {
  BrowserUnifiedLinkNavigationCoordinator,
  BrowserUnifiedLinkNavigationFacts,
  BrowserUnifiedLinkNavigationHost
} from '../../core/browser/BrowserUnifiedLinkNavigationCoordinator';
import {
  BrowserWebNavigationInterceptionCoordinator,
  BrowserWebNavigationInterceptionHost
} from '../../core/browser/BrowserWebNavigationInterceptionCoordinator';
import {
  BrowserWebSpecialNavigationActionCoordinator,
  BrowserWebSpecialNavigationActionHost
} from '../../core/browser/BrowserWebSpecialNavigationActionCoordinator';
import {
  BrowserWebPageLifecycleApplicationCoordinator
} from '../../core/browser/BrowserWebPageLifecycleApplicationCoordinator';
import { WebRuntimeBridge } from '../../core/web/WebRuntimeBridge';
import { WebEventRouter } from '../../core/web/WebEventRouter';
import { BrowserRecentActionManager } from '../../core/web/BrowserRecentActionManager';
import {
  BrowserWebDialogKind,
  BrowserWebHistoryDirection,
  BrowserWebComponentLinkRequest,
  BrowserWebComponentNavigationEventSource,
  BrowserWebComponentWebUrlDecision
} from '../../core/web/BrowserWebComponentController';
import {
  BrowserUnifiedLinkResult
} from '../../services/web/BrowserUnifiedLinkLogic';
import {
  WebpageTranslationApplicationContext,
  WebpageTranslationApplicationSnapshot,
  WebpageTranslationCloudDisclosureRequest,
  WebpageTranslationCoordinator
} from '../../core/translation/WebpageTranslationCoordinator';
import {
  BrowserUserScriptApplicationCoordinator,
  BrowserUserScriptApplicationEffect,
  BrowserUserScriptApplicationFacts,
  BrowserUserScriptApplicationSnapshot
} from '../../core/userscripts/BrowserUserScriptApplicationCoordinator';
import { UserScriptRuntimeCoordinator } from '../../core/userscripts/UserScriptRuntimeCoordinator';
import { UserScriptPackageSuccessResult } from '../../core/userscripts/UserScriptPackageLifecycleCoordinator';
import {
  AppProxyQuickSheetCoordinator,
  AppProxyQuickSheetShell,
  AppProxyQuickSheetState
} from '../../core/settings/AppProxyQuickSheetCoordinator';
import { AppProxySettingsCoordinator } from '../../core/settings/AppProxySettingsCoordinator';
import { AppProxySettingsViewModel } from '../../core/settings/AppProxySettingsViewModel';
import {
  resolveWebAppearancePolicy,
  resolveWebAppearancePolicyForTheme,
  WebAppearancePolicy
} from '../../core/web/WebAppearancePolicy';
import { WebControllerBootstrapConfig, WebControllerBootstrapper } from '../../core/web/WebControllerBootstrapper';
import {
  WebContextMenuPresentation,
  WebContextMenuSessionFacts,
  WebLinkContextMenuCoordinator
} from '../../core/web/WebLinkContextMenuCoordinator';
import {
  WebLinkContextMenuFixedActionApplication
} from '../../core/web/WebLinkContextMenuActionApplication';
import { WebRecoveryManager } from '../../core/web/WebRecoveryManager';
import { WebSessionStateStore } from '../../core/web/WebSessionStateStore';
import { WebStateSnapshotStore } from '../../core/web/WebStateSnapshotStore';
import { WebTabRuntimeRecord } from '../../core/web/WebTabRuntime';
import {
  BrowserCreateTabOptions,
  BrowserTabRuntimePatch,
  BrowserTabState,
} from '../../core/tabs/TabManager';
import {
  AppShortcutNavigationCoordinator,
  AiraAppShortcutNavigationResult
} from '../router/AppShortcutNavigationCoordinator';
import {
  BrowserAppShortcutActionCoordinator
} from '../../core/browser/BrowserAppShortcutActionCoordinator';
import {
  FeatureGateAction,
  FeatureGateCoordinator,
  FeatureGateSnapshot
} from '../../core/membership/FeatureGateCoordinator';
import {
  CrossDeviceTabPresenceEntryHost,
  sharedCrossDeviceTabPresenceCoordinator
} from '../../core/deviceTabs/CrossDeviceTabPresenceCoordinator';
import { FeatureGateOverlay } from '../components/browser/FeatureGateOverlay';
import {
  isBrowserNewWindowTestUrl,
  resolveBrowserNewWindowTestTitle
} from '../debug/BrowserNewWindowTestPage';
import {
  BrowserLaunchPayload,
  BrowserWindowRuntime
} from '../runtime/BrowserWindowRuntime';
import {
  BrowserWindowSessionTabManagerPort,
  BrowserWindowSessionArticleReadingPort,
  BrowserWindowSessionNovelReaderPort,
  BrowserWindowSessionShellPresentationOperations,
  resolveBrowserWindowSessionShellPresentationBinding
} from '../../core/browser/BrowserWindowSessionApplication';
import { BrowserShellPresentationSnapshot } from '../../core/browser/BrowserShellPresentationCoordinator';
import {
  BrowserSearchInvocationAuthorityGateAdapter,
  BrowserSearchInvocationRuntime,
  BrowserSearchInvocationSurfaceConnection
} from '../runtime/BrowserSearchInvocationRuntime';
import { BrowserNavigationRouteParams } from '../../core/navigation/BrowserNativeNavigationRequestCenter';
import {
  BrowserNativeNavigationConsumeCoordinator,
  BrowserNativeNavigationConsumeHost
} from '../../core/navigation/BrowserNativeNavigationConsumeCoordinator';
import {
  BrowserBottomAddressPanel,
  BrowserBottomAddressPanelGestureFrame
} from '../components/browser/BrowserBottomAddressPanel';
import { ExternalAppSearchDisclosurePresenter } from '../components/browser/ExternalAppSearchDisclosurePresenter';
import { BrowserNativeAlertDialogPresenter } from '../components/browser/BrowserNativeAlertDialogPresenter';
import {
  BrowserWebCapabilityAlertDialogPresenter
} from '../components/browser/BrowserWebCapabilityAlertDialogPresenter';
import { HomeBackdropLayer } from '../components/browser/HomeBackdropLayer';
import { BrowserHomePrimarySurface } from '../components/browser/BrowserHomePrimarySurface';
import {
  BrowserBottomPanelHost,
  BrowserBottomPanelRenderContext
} from '../components/browser/BrowserBottomPanelHost';
import { BrowserRootBottomPanelExpandedScrim } from '../components/browser/BrowserRootBottomPanelExpandedScrim';
import { BrowserPageFindBar } from '../components/browser/BrowserPageFindBar';
import {
  BrowserHomeChromeInteractionInput
} from '../../core/browser/BrowserHomeChromeScrollCoordinator';
import {
  BrowserHostedWebLayerPresentationState,
  BrowserHostedWebLayerPresentationViewModel
} from '../../core/browser/BrowserHostedWebLayerPresentationViewModel';
import {
  BrowserBottomAddressPanelActionId,
  BrowserBottomPanelMotionState
} from '../../core/browser/BrowserBottomAddressPanelViewModel';
import { AppChromeIconTone } from '../../core/resources/AppIconResources';
import {
  BrowserKeyboardShortcutCoordinator,
  BrowserKeyboardShortcutFacts
} from '../../core/browser/BrowserKeyboardShortcutCoordinator';
import {
  BrowserLargeScreenNavigationIntent,
  BrowserLargeScreenShellIntentApplication,
  BrowserLargeScreenTabStripIntent,
} from '../../core/browser/BrowserLargeScreenShellIntentApplication';
import {
  BrowserLargeScreenOmniboxPresentation,
  createBrowserLargeScreenOmniboxPresentation
} from '../../core/browser/BrowserLargeScreenSearchInvocationAdapter';
import {
  BrowserLargeScreenWebZoomAction,
  BrowserLargeScreenWebZoomCoordinator,
  BrowserLargeScreenWebZoomSnapshot,
  createBrowserLargeScreenWebZoomSnapshot
} from '../../core/browser/BrowserLargeScreenWebZoomCoordinator';
import { HomeSearchPanelDetent } from '../../core/browser/HomeSearchPanelDetentViewModel';
import { BrowserKeyboardAvoidModeCoordinator } from '../../core/browser/BrowserKeyboardAvoidModeCoordinator';
import {
  BrowserWebPageToolsCoordinator,
  BrowserWebPageToolsSnapshot
} from '../../core/browser/BrowserWebPageToolsCoordinator';
import {
  BrowserFullscreenSessionCoordinator,
  BrowserFullscreenSessionEffect,
  BrowserFullscreenSessionPresentation,
  BrowserFullscreenSessionSink,
  BrowserFullscreenSurfaceFacts
} from '../../core/browser/BrowserFullscreenSessionCoordinator';
import {
  BROWSER_TOP_FLOATING_PROMPT_HOST_Z_INDEX,
  BrowserTopFloatingPromptHost
} from '../components/browser/BrowserTopFloatingPromptHost';
import {
  BrowserWebPageToolsContent,
  BrowserWebPageToolsLargeScreenOverlayHost
} from '../components/browser/BrowserWebPageToolsOverlayHost';
import { ElementInspectionOverlay } from '../components/browser/ElementInspectionOverlay';
import { BrowserDownloadConfirmOverlay } from '../components/browser/BrowserDownloadConfirmSheet';
import { WebContextMenuOverlay } from '../components/browser/WebContextMenuOverlay';
import {
  BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS,
  BROWSER_MODAL_BOTTOM_SHEET_OPEN_DELAY_MS
} from '../components/browser/BrowserModalBottomSheet';
import {
  APP_PROXY_QUICK_OVERLAY_ANIMATION_DURATION_MS,
  APP_PROXY_QUICK_OVERLAY_OPEN_DELAY_MS,
  BACKGROUND_OPEN_PROMPT_STACK_ANIMATION_MS,
  BACKGROUND_TAB_PREVIEW_ATTACH_RETRY_DELAY_MS,
  BACKGROUND_TAB_PREVIEW_MAX_ATTACH_ATTEMPTS,
  BOOKMARK_FOLDER_OVERLAY_ANIMATION_DURATION_MS,
  BOOKMARK_FOLDER_OVERLAY_OPEN_DELAY_MS,
  ROOT_BOTTOM_PANEL_EXPANDED_SCRIM_Z_INDEX,
  CONTROLLER_ATTACH_RESTORE_FALLBACK_DELAY_MS,
  FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
  FEATURE_GATE_OVERLAY_OPEN_DELAY_MS,
  HLS_TAKEOVER_OVERLAY_ANIMATION_DURATION_MS,
  HOME_FLOATING_SEARCH_SIDE_PADDING,
  HOME_SEARCH_PANEL_EXPANDED_TOP,
  HOME_SEARCH_PANEL_MIN_VIEWPORT_RATIO,
  HOME_TAB_URL,
  LOG_DOMAIN,
  LOG_TAG,
  MAIN_WINDOW_ID,
  MANUAL_ELEMENT_HIDE_OVERLAY_Z_INDEX,
  MAX_BACKGROUND_HOT_TAB_COUNT,
  NEW_WINDOW_TEST_URL,
  OFFLINE_SAVE_ACTION_PROMPT_HIDE_DELAY_MS,
  OPENER_TAB_PREVIEW_BEFORE_SWITCH_WAIT_MS,
  PRIVATE_MODE_LOCK_OVERLAY_Z_INDEX,
  READER_MODE_THEME_TRANSITION_DURATION_MS,
  READER_SPEECH_PLAYER_OPEN_DELAY_MS,
  READER_SPEECH_PLAYER_OVERLAY_ANIMATION_DURATION_MS,
  REGULAR_CREATE_TAB_OPTIONS,
  RESOURCE_CANDIDATES_OVERLAY_ANIMATION_DURATION_MS,
  RESOURCE_CANDIDATES_OVERLAY_OPEN_DELAY_MS,
  ROOT_BOTTOM_PANEL_COLLAPSE_TO_PEEK_NAVIGATION_DELAY_MS,
  RUNTIME_COOLING_TICK_MS,
  SITE_INFO_SHEET_OPEN_DELAY_MS,
  TABS_OVERVIEW_OVERLAY_Z_INDEX,
  TABS_OVERVIEW_DEBUG_SNAPSHOT_EXPORT_ENABLED,
  TABS_OVERVIEW_ENTRY_PIXELMAP_SCALE,
  TABS_OVERVIEW_PREVIEW_HYDRATE_BATCH_DELAY_MS,
  TABS_OVERVIEW_PREVIEW_HYDRATE_BATCH_SIZE,
  USER_SCRIPT_PAGE_ACTIONS_OVERLAY_ANIMATION_DURATION_MS,
  USER_SCRIPT_PAGE_ACTIONS_OVERLAY_OPEN_DELAY_MS,
  TRANSLATION_TARGET_LANGUAGE_OVERLAY_ANIMATION_DURATION_MS,
  TRANSLATION_TARGET_LANGUAGE_OVERLAY_OPEN_DELAY_MS,
  WEB_BACKDROP_SNAPSHOT_ID,
  WEB_LOADING_PROGRESS_TERMINAL_HOLD_MS,
  WEB_OFFLINE_FAST_FAIL_DELAY_MS,
  WEB_PAGE_FIND_BAR_TOP_MARGIN,
  WEB_PAGE_TOOLS_OVERLAY_ANIMATION_DURATION_MS,
  WEB_PAGE_TOOLS_OVERLAY_OPEN_DELAY_MS,
  WEB_SAFE_INSET_SETTLE_SYNC_DELAY_MS,
  WEB_SAFE_INSET_SYSTEM_BAR_REFRESH_SETTLE_DELAY_MS,
  WEB_SCROLL_NAVIGATION_STATE_UPDATE_DELAY_MS,
  WEB_SCROLL_PAGE_METADATA_VISUAL_UPDATE_DELAY_MS,
  WEB_SCROLL_TRACKING_PROTECTION_STATUS_UPDATE_DELAY_MS,
  WEB_TOP_CHROME_CONTENT_GAP_VP,
  WEB_TOP_SAFE_AREA_COLOR_TRANSITION_MS,
  NATIVE_VIDEO_TAKEOVER_OVERLAY_Z_INDEX,
  WEB_VIDEO_EPHEMERAL_PLAYER_OVERLAY_Z_INDEX,
  WEB_VIEWPORT_DARK_SAFE_AREA_BACKGROUND_COLOR
} from '../components/browser/BrowserShellPresentationTokens';
import { BrowserWifiQrResultOverlay } from '../components/browser/BrowserWifiQrResultOverlay';
import { UserScriptInstallSheetContent } from '../components/userscripts/UserScriptInstallSheetContent';
import {
  BrowserShellHttpAuthDialog,
  DocumentViewerFileInfoDialog,
  BrowserShellWebPromptDialog,
  DesktopShortcutNameDialog,
  HomeShortcutEditDialog,
  SiteReportDialog
} from '../components/browser/BrowserShellDialogs';
import { BrowserSitePermissionPromptHost } from '../components/browser/BrowserSitePermissionPromptHost';
import { BookmarkMoveFolderSelectionOverlay } from '../components/bookmarks/BookmarkMoveFolderSelectionSheet';
import { BrowserWebTextZoomSheet } from '../components/browser/BrowserWebTextZoomSheet';
import { BrowserLargeScreenWebZoomDialog } from '../components/browser/BrowserLargeScreenWebZoomDialog';
import { BrowserTabOverviewCardSelectRect } from '../components/browser/BrowserTabOverviewCard';
import { BrowserTabsFloatingOverlay } from '../components/browser/BrowserTabsFloatingOverlay';
import { BrowserCrossDeviceTabsSheet } from '../components/browser/BrowserCrossDeviceTabsOverlay';
import { BrowserTabsSharedSnapshotOverlay } from '../components/browser/BrowserTabsSharedSnapshotOverlay';
import { BrowserPrivateModeLockOverlay } from '../components/browser/BrowserPrivateModeLockOverlay';
import {
  BrowserPrivateModeConfirmationDialog
} from '../components/browser/BrowserPrivateModeConfirmationDialog';
import { BrowserWebErrorLayer } from '../components/browser/BrowserWebErrorLayer';
import { BrowserWebLoadingProgressBar } from '../components/browser/BrowserWebLoadingProgressBar';
import { BrowserWebTopChromeOverlay } from '../components/browser/BrowserWebTopChromeOverlay';
import { BrowserWebViewportSurfaceHost } from '../components/browser/BrowserWebViewportSurfaceHost';
import { BrowserPullRefreshLoadingArea } from '../components/browser/BrowserPullRefreshLoadingArea';
import { ManualElementHideSelectionOverlay } from '../components/browser/ManualElementHideSelectionOverlay';
import {
  BrowserHostedWebFixedSlots,
  BrowserHostedWebParkingSlots
} from '../components/browser/BrowserHostedWebSurfaceSlots';
import { ReleaseNoticeSheet } from '../components/update/ReleaseNoticeSheet';
import {
  ClientUpdateRequiredAction,
  ClientUpdateRequiredOverlay
} from '../components/update/ClientUpdateRequiredSheet';
import {
  AiraCloudBookmarkV4BootstrapOverlay
} from '../components/sync/AiraCloudBookmarkV4BootstrapOverlay';
import { DesktopLoginConfirmSheetContent } from '../components/settings/DesktopLoginConfirmSheetContent';
import { HomeShortcutSelectionSheet } from '../components/browser/HomeShortcutSelectionSheet';
import { BrowserSystemSurfaceHost } from '../components/browser/BrowserSystemSurfaceHost';
import { HomePageSettingsSheet } from '../components/browser/HomePageSettingsSheet';
import { ReaderModeOverlay } from '../components/browser/ReaderModeOverlay';
import { NovelReaderSurfaceHost } from '../components/browser/NovelReaderSurfaceHost';
import {
  ReadingExperienceSystemSheet, isReadingExperienceSystemSheetType,
  resolveReadingExperienceSystemSheetHeight, resolveReadingExperienceSystemSheetTitle
} from '../components/reading/ReadingExperienceSystemSheet';
import {
  createDefaultNovelReaderSnapshot,
  NovelReaderAction,
  NovelReaderSnapshot
} from '../../features/novel/NovelReaderModels';
import {
  NovelReaderApplication,
  NovelReaderApplicationDependencies
} from '../../core/browser/NovelReaderApplication';
import { ReadingWindowBrightnessService } from '../../services/reading/ReadingWindowBrightnessService';
import { ReaderSpeechPlayerOverlay } from '../components/browser/ReaderSpeechPlayerScreen';
import { ReaderSpeechVoiceDialog } from '../components/browser/ReaderSpeechVoiceDialog';
import { createCenteredDialogMaterial } from '../components/common/CenteredDialogSurface';
import {
  WebpageTranslationTargetLanguageOverlay
} from '../components/translation/WebpageTranslationTargetLanguageSheet';
import {
  SiteReportDialogViewModel,
  SiteReportReasonId
} from '../../core/browser/SiteReportDialogViewModel';
import { CustomHomepageSurface } from '../components/customhome/CustomHomepageSurface';
import { HomeContentSections } from '../components/browser/HomeContentSections';
import { HomeSystemSurface } from '../components/browser/HomeSystemSurface';
import { PrivateHomeWatermark } from '../components/browser/PrivateHomeWatermark';
import {
  DownloadRuntimeService,
  ManualDownloadRequestInput,
  PendingDownloadPromptState
} from '../../services/download/DownloadRuntimeService';
import { DownloadTaskBoundary } from '../../domain/download/DownloadTypes';
import {
  ExternalNavigationPolicyService
} from '../../services/web/ExternalNavigationPolicyService';
import { SiteInteractionLogicService } from '../../services/web/SiteInteractionLogicService';
import { SiteCertificatePresentationService } from '../../services/web/SiteCertificatePresentationService';
import {
  BrowserErrorDocumentLoadShell,
  BrowserErrorDocumentPresentationFacts
} from '../../services/web/BrowserErrorDocumentLoadCoordinator';
import {
  BrowserOfflineFastFailureCoordinator,
  BrowserOfflineFastFailureFacts
} from '../../services/web/BrowserOfflineFastFailureCoordinator';
import { SitePolicyService } from '../../services/web/SitePolicyService';
import {
  PrivateModeCookiePreservationResult,
  SiteDataClearDialogState,
  SiteDataControlService
} from '../../services/web/SiteDataControlService';
import { SiteClearOnCloseLifecycleService } from '../../services/web/SiteClearOnCloseLifecycleService';
import {
  BrowserQrScanCoordinator,
  BrowserQrScanNavigationTarget,
  BrowserQrScanSessionSnapshot,
  BrowserQrScanShell,
  BrowserQrScanSurface,
  DEFAULT_BROWSER_QR_SCAN_SESSION_SNAPSHOT
} from '../../core/browser/BrowserQrScanCoordinator';
import { BrowserStatusBarStyleService } from '../../services/browser/BrowserStatusBarStyleService';
import { BrowserWebTopSafeAreaColorSampler } from '../../services/browser/BrowserWebTopSafeAreaColorSampler';
import { SystemSettingsLaunchService } from '../../services/system/SystemSettingsLaunchService';
import {
  BrowserUserAgentResolution,
  BrowserUserAgentRiskNotice,
  BrowserUserAgentService
} from '../../services/web/BrowserUserAgentService';
import { ManualElementHideService } from '../../services/adblock/ManualElementHideService';
import {
  ManualElementHideRuntimeCoordinator,
  ManualElementHideRuntimeShell,
  ManualElementHideSelectionPresentation
} from '../../core/adblock/ManualElementHideRuntimeCoordinator';
import {
  OfflinePageSaveCoordinator,
  OfflinePageSaveCoordinatorShell,
  OfflinePageSaveSessionSnapshot,
  OfflinePageSaveShellContext
} from '../../core/offline/OfflinePageSaveCoordinator';
import {
  BrowserWebPrintService
} from '../../services/web/BrowserWebPrintService';
import {
  HomeShortcutApplicationShell,
  HomeShortcutApplicationSnapshot,
  HomeShortcutStateCoordinator
} from '../../core/shortcuts/HomeShortcutStateCoordinator';
import {
  HomeShortcutConfirmationPresentation,
  HomeShortcutEffectApplicationShell,
  HomeShortcutFixedEffectApplication,
  HomeShortcutInformationPresentation
} from '../../core/shortcuts/HomeShortcutEffectApplication';
import { HomeShortcutSelectionState } from '../../core/shortcuts/HomeShortcutSelectionCoordinator';
import { HomeShortcutOpenCoordinator } from '../../core/shortcuts/HomeShortcutOpenCoordinator';
import { HomeShortcutToggleService } from '../../services/shortcuts/HomeShortcutToggleService';
import {
  WebAppInstallCoordinator,
  WebAppInstallDialogAction,
  WebAppInstallDialogSnapshot,
  WebAppInstallShell,
  WebAppInstallShellSnapshot
} from '../../core/webapps/WebAppInstallCoordinator';
import {
  WebAppSessionCoordinator,
  WebAppSessionSnapshot,
  sharedWebAppSessionCoordinator
} from '../../core/webapps/WebAppSessionCoordinator';
import {
  WebAppExitCoordinator,
  WebAppExitHost
} from '../../core/webapps/WebAppExitCoordinator';
import {
  BrowserWindowContextFacts,
  BrowserWindowLaunchApplication,
  BrowserWindowContextShell,
  BrowserWindowContextPort,
} from '../../core/browser/BrowserWindowContextCoordinator';
import {
  BrowserWindowSessionContextComposition,
  BrowserWindowSessionContextPort
} from '../../core/browser/BrowserWindowSessionContextApplication';
import { BrowserWindowSuspendedContext } from '../../core/browser/BrowserWindowContextState';
import {
  BrowserWindowFixedLaunchApplication
} from '../../core/browser/BrowserWindowLaunchApplication';
import {
  WebAppCurrentUrlService
} from '../../services/webapps/WebAppCurrentUrlService';
import { ShortcutIconResolverService } from '../../services/shortcuts/ShortcutIconResolverService';
import {
  HomeShortcutEditDraft
} from '../../features/newtab/HomeShortcutTypes';
import {
  HomeResponsiveLayoutState
} from '../../features/newtab/HomeResponsiveLayoutViewModel';
import { BrowserShellViewModel } from '../../core/browser/BrowserShellViewModel';
import {
  BrowserPageFindBarState,
  BrowserPageFindCoordinator,
  createBrowserPageFindClosedBarState
} from '../../core/browser/BrowserPageFindCoordinator';
import { ReaderModeAction } from '../../features/reader/ReaderModeModels';
import {
  ReaderModeSessionSnapshot,
  ReaderModeSessionSnapshotTransition,
  ReaderModeSpeechVoiceDialogPresentation
} from '../../core/browser/ReaderModeCoordinator';
import {
  ReaderModeApplication,
  ReaderModeApplicationFacts,
  ReaderModeApplicationShell
} from '../../core/browser/ReaderModeApplication';
import {
  BrowserWindowAvoidAreaCoordinator,
  BrowserWindowFullscreenInsetRestoreHost,
  BrowserWindowAvoidAreaInsets,
  BrowserWindowKeyboardInsetSyncHost
} from '../../core/browser/BrowserWindowAvoidAreaCoordinator';
import {
  BROWSER_WINDOW_DISPLAY_VIEWPORT_HEIGHT_STORAGE_KEY,
  BROWSER_WINDOW_DISPLAY_VIEWPORT_WIDTH_STORAGE_KEY
} from '../../core/browser/BrowserWindowDisplayViewportCoordinator';
import {
  BROWSER_SHELL_PRESENTATION_REVISION_STORAGE_KEY
} from '../../core/browser/BrowserShellPresentationRefreshSignal';
import {
  BrowserWebViewportCoordinator,
  BrowserWebViewportPresentationState
} from '../../core/browser/BrowserWebViewportCoordinator';
import {
  BrowserWebTopImmersionFacts,
  BrowserWebTopImmersionSessionCoordinator,
  BrowserWebTopImmersionSessionHost
} from '../../core/browser/BrowserWebTopImmersionSessionCoordinator';
import {
  BrowserQuickSearchSwitchingCoordinator,
  BrowserQuickSearchSwitchingHost,
  BrowserQuickSearchSwitchingPresentation,
  createHiddenBrowserQuickSearchSwitchingPresentation
} from '../../core/search/BrowserQuickSearchSwitchingCoordinator';
import {
  BrowserProxyAuthRefreshCoordinator,
  BrowserProxyRuntimeRefreshHost
} from '../../core/browser/BrowserProxyAuthRefreshCoordinator';
import { BrowserRuntimeRefreshStateSink } from '../../core/browser/BrowserRuntimeRefreshStateSink';
import {
  BrowserBookmarkActionCoordinator,
  BrowserBookmarkFolderSelectionAction,
  BrowserBookmarkActionSessionSnapshot,
  BrowserBookmarkActionShell,
  BrowserBookmarkActionTarget,
  BrowserBookmarkRemoveConfirmation
} from '../../core/browser/BrowserBookmarkActionCoordinator';
import { WebRuntimeRetentionPlan } from '../../core/web/WebRuntimePoolPolicy';
import {
  HostedWebNodeCallbacks,
  HostedWebNodeController
} from '../../core/web/HostedWebNode';
import { BrowserShellPrimarySurfaceHost } from '../components/browser/BrowserShellPrimarySurfaceHost';
import {
  BrowserTabPreviewWebViewportSize,
  buildBrowserTabPreviewVisibleSurfaceSnapshotId,
  buildBrowserTabPreviewVisibleSnapshotId
} from '../../services/web/BrowserTabPreviewCaptureService';
import {
  BrowserSystemSheetType,
  TabMutationCommitOptions
} from '../../core/browser/BrowserShellRuntimeContracts';

const BROWSER_KEYBOARD_AVOID_OWNER_CUSTOM_HOMEPAGE: string = 'custom-homepage-web';
const BROWSER_KEYBOARD_AVOID_OWNER_ROOT_BOTTOM_ADDRESS_INPUT: string = 'root-bottom-address-input';
const BROWSER_KEYBOARD_AVOID_PRIORITY_CUSTOM_HOMEPAGE: number = 10;
const BROWSER_KEYBOARD_AVOID_PRIORITY_ROOT_BOTTOM_ADDRESS_INPUT: number = 20;

class BrowserColdStartDeferredSurfaceContentFrameCallback extends FrameCallback {
  private readonly task: () => void;

  constructor(task: () => void) {
    super();
    this.task = task;
  }

  onFrame(_frameTimeInNano: number): void {
  }

  onIdle(_timeLeftInNano: number): void {
    this.task();
  }
}

@Entry({ useSharedStorage: true })
@Component
struct BrowserShellPage {
  private browserSearchSubmissionHistoryCoordinator: BrowserSearchSubmissionHistoryCoordinator =
    new BrowserSearchSubmissionHistoryCoordinator(sharedSearchQueryHistoryService,
      (): void => this.browserSearchSuggestionCoordinator.invalidate());
  private externalAppSearchDisclosurePresenter: ExternalAppSearchDisclosurePresenter = new ExternalAppSearchDisclosurePresenter();
  private browserNativeAlertDialogPresenter: BrowserNativeAlertDialogPresenter =
    new BrowserNativeAlertDialogPresenter();
  private crossDeviceTabPresenceEntryHost: CrossDeviceTabPresenceEntryHost =
    new CrossDeviceTabPresenceEntryHost(
      (): void => {
        this.browserTransientSurfaceCoordinator.openSystemSheet('crossDeviceTabs');
      },
      (): void => {
        this.browserShellRouteCoordinator.openAiraProPage();
      },
      (): void => {
        this.browserShellRouteCoordinator.openSyncSettingsPage();
      },
      (title: string, message: string): void => {
        this.browserNativeAlertDialogPresenter.inform({
          title: title,
          message: message,
          confirmLabel: '知道了'
        });
      }
    );
  private browserAddressSubmissionShell: BrowserAddressSubmissionShell = {
      resolveSessionFacts: () => ({
        availableSearchEngines: this.availableSearchEngines,
        searchEngineSettings: sharedSearchEngineRepository.getSettings(),
        experiments: sharedPreferencesRepository.getPreferences().experiments,
        boundary: this.tabScopedEventContextCoordinator.resolveCurrentBoundary(),
        searchSuggestionPreferences: sharedPreferencesRepository.getPreferences().searchSuggestions,
        abilityContext: this.getAbilityContext()
      }),
      prepareForNavigation: (): void => {
        this.cancelRootBottomPanelAddressFocusBackdropTransition();
        this.browserRecentActionManager.recordOperate(Date.now());
        this.browserSearchSuggestionCoordinator.reset();
      },
      completeSearchSession: (): void => {
        BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'submitted');
      },
      present: (presentation: BrowserAddressSubmissionPresentation): void => {
        this.helperMessage = presentation.helperMessage;
        this.errorMessage = presentation.errorMessage;
        if (presentation.toastMessage.length > 0) {
          this.showNativeToast(presentation.toastMessage);
        }
      },
      confirmPrivateExternalSearch: (
        presentation: ExternalAppSearchPrivateConfirmation
      ): Promise<boolean> => this.externalAppSearchDisclosurePresenter.confirm(presentation)
  };
  private browserHomePresentationViewModel: BrowserHomePresentationViewModel =
    new BrowserHomePresentationViewModel();
  private browserBackdropEffectViewModel: BrowserBackdropEffectViewModel =
    new BrowserBackdropEffectViewModel();
  private browserDownloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator =
    new BrowserDownloadNavigationStateCoordinator(undefined, {
      resolveTab: (tabId: string): BrowserTabState | undefined => this.tabManager.getTab(this.tabs, tabId),
      resolveActiveTab: (): BrowserTabState | undefined =>
        this.tabManager.getActiveTab(this.tabs, this.activeTabId),
      resolveLastKnownUrl: (tabId: string): string =>
        this.browserRuntimeLifecyclePort.resolveRuntimeLastKnownUrl(tabId),
      applyTabPatch: (tabId: string, patch: BrowserTabRuntimePatch, persistTabs: boolean): void => {
        this.browserTabSwitchCoordinator.applyTabPatch(tabId, patch, {
          persistTabs: persistTabs
        });
      },
      clearDownloadSnapshotForTab: (tab: BrowserTabState, reason: string): void => {
        this.browserTabRecoveryCoordinator.clearDownloadSnapshotForTab(
          this.webStateSnapshotStore,
          tab,
          reason,
          this.browserSnapshotPersistenceHost
        );
      },
      applyActiveTabShellState: (): void => {
        this.browserTabSwitchCoordinator.publishActiveTabShellState();
      },
      patchRuntimeNavigationState: (
        tabId: string,
        patch: BrowserDownloadNavigationRuntimeSanitizationPatch
      ): void => {
        this.browserRuntimeLifecyclePort.patchRuntimeNavigationMemory(tabId, {
          currentUrl: patch.currentUrl,
          pendingUrl: patch.pendingUrl,
          lastKnownUrl: patch.lastKnownUrl,
          snapshotPath: patch.snapshotPath,
          snapshotUpdatedAt: patch.snapshotUpdatedAt
        });
      },
      restoreWebViewToRestorableUrl: (
        tabId: string,
        skippedUrl: string,
        restoredUrl: string,
        reason: string
      ): void => {
        this.browserWebLoadRuntimeCoordinator.restoreWebViewToRestorableUrl(
          tabId,
          skippedUrl,
          restoredUrl,
          reason
        );
      }
    });
  private webRuntimeBridge: WebRuntimeBridge =
    new WebRuntimeBridge(this.browserDownloadNavigationStateCoordinator);
  private searchEngineSelectionCoordinator: SearchEngineSelectionCoordinator =
    new SearchEngineSelectionCoordinator(sharedSearchEngineRepository, sharedPreferencesRepository);
  private tabManager: BrowserWindowSessionTabManagerPort = new BrowserWindowSessionTabManagerPort();
  private browserShellPresentationOperations?: BrowserWindowSessionShellPresentationOperations;
  private browserShellViewModel: BrowserShellViewModel = new BrowserShellViewModel();
  private browserAddressDisplayCoordinator: BrowserAddressDisplayCoordinator =
    new BrowserAddressDisplayCoordinator();
  private browserFaultClassifier: BrowserFaultClassifier = new BrowserFaultClassifier();
  private browserRestoreCoordinator: BrowserRestoreCoordinator =
    new BrowserRestoreCoordinator(this.browserDownloadNavigationStateCoordinator);
  private privateBoundaryNavigationService: BrowserPrivateBoundaryNavigationService =
    new BrowserPrivateBoundaryNavigationService();
  private appShortcutNavigationCoordinator: AppShortcutNavigationCoordinator =
    new AppShortcutNavigationCoordinator();
  private appShortcutActionCoordinator: BrowserAppShortcutActionCoordinator =
    new BrowserAppShortcutActionCoordinator();
  private browserPrivateModeLockCoordinator: BrowserPrivateModeLockCoordinator =
    new BrowserPrivateModeLockCoordinator({
      readFacts: (): BrowserPrivateModeLockSessionFacts => ({
        tabs: this.tabs,
        privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
        dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
        activeTabId: this.activeTabId,
        browserShellVisible: this.isBrowserShellVisible
      }),
      publishSnapshot: (snapshot: BrowserPrivateModeLockSessionSnapshot): void => {
        this.privateModeLockSessionSnapshot = snapshot;
      },
      returnToRegularMode: (): void => {
        this.browserTabHomeCoordinator.showHomeSurface('已回到主页', REGULAR_CREATE_TAB_OPTIONS);
        this.tabsOverviewSessionCoordinator.setActiveSection('tabs');
      }
    }, sharedPreferencesRepository);
  private browserPrivateTabCoordinator: BrowserPrivateTabCoordinator =
    new BrowserPrivateTabCoordinator(this.browserPrivateModeLockCoordinator);
  private browserPrivateModeTogglePresentationHost: BrowserPrivateModeTogglePresentationHost = {
    resolveCurrentBoundaryPrivate: (): boolean => this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
    resolveTabs: (): BrowserTabState[] => this.tabs,
    presentConfirmation: (state: BrowserPrivateModeConfirmationState): void => {
      this.presentPrivateModeToggleConfirmation(state);
    }
  };
  private browserPrivateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator =
    new BrowserPrivateProfileLifecycleCoordinator();
  private browserPrivateSessionCleanupShell: BrowserPrivateSessionCleanupShell = {
    readFacts: (): BrowserPrivateSessionCleanupFacts => ({
      tabs: this.tabs,
      pendingDownloadPrompt: this.pendingDownloadPrompt !== undefined,
      currentWindowId: this.currentWindowId
    }),
    notifyTabPreviewChanged: (): void => this.notifyTabPreviewChanged()
  };
  private browserPrivateSessionCleanupCoordinator: BrowserPrivateSessionCleanupCoordinator =
    new BrowserPrivateSessionCleanupCoordinator(
      {
        resolveWebCapabilityPromptApplicationCoordinator: () =>
          this.browserWebCapabilityPromptApplicationCoordinator,
        resolveDownloadConfirmOverlayCoordinator: () => this.browserDownloadConfirmOverlayCoordinator,
        resolveExternalNavigationRuntimeStateCoordinator: () =>
          this.browserExternalNavigationRuntimeStateCoordinator,
        resolveSiteControlsRuntimeCoordinator: () => this.browserSiteControlsRuntimeCoordinator,
        privateProfileLifecycleCoordinator: this.browserPrivateProfileLifecycleCoordinator,
        preferencesRepository: sharedPreferencesRepository,
        resolveSiteDataControlService: () => this.siteDataControlService,
        resolveDownloadRuntimeService: () => this.downloadService,
        resolveTabPreviewCoordinator: () => this.browserTabPreviewCoordinator,
        resolveSnapshotStore: () => this.webStateSnapshotStore,
        resolveSitePolicyService: () => this.sitePolicyService,
        resolvePageFindCoordinator: () => this.browserPageFindCoordinator
      },
      this.browserPrivateSessionCleanupShell
    );
  private browserPrivateProfileCookieLifecycleHost: BrowserPrivateProfileCookieLifecycleHost = {
    isPreserveCookiesOnCloseEnabled: (): boolean => {
      return sharedPreferencesRepository.getPreferences().general.privateModePreserveCookiesOnClose;
    },
    restorePreservedPrivateModeCookies: (): Promise<PrivateModeCookiePreservationResult> => {
      return this.siteDataControlService.restorePreservedPrivateModeCookies();
    },
    savePreservedPrivateModeCookies: (): Promise<PrivateModeCookiePreservationResult> => {
      return this.siteDataControlService.savePreservedPrivateModeCookies();
    },
    findTabById: (tabId: string): BrowserTabState | undefined => {
      return this.tabManager.getTab(this.tabs, tabId);
    },
    getActiveTabId: (): string => this.activeTabId
  };
  private browserShellRouteCoordinatorHost: BrowserShellRouteCoordinatorHost = {
    presentRouteFailure: (errorMessage: string, toastMessage: string = ''): void => {
      this.errorMessage = errorMessage;
      if (toastMessage.length > 0) this.showNativeToast(toastMessage);
    },
    resetTransientOverlayStateForRouteTransition: (): void => {
      this.resetTransientOverlayStateForRouteTransition(false);
    },
    openTabsOverview: (): void => {
      void this.openTabsOverview();
    },
    isLargeScreenShellActive: (): boolean =>
      this.browserShellPresentationOperations?.surface() === 'large_screen',
    openLargeScreenNativeRoute: (request): void =>
      this.browserLargeScreenShellIntentApplication.openNativeRoute(request)
  };
  private browserShellRouteCoordinator: BrowserShellRouteCoordinator =
    new BrowserShellRouteCoordinator(
      this.browserShellRouteCoordinatorHost,
      {
        privateModeLockCoordinator: this.browserPrivateModeLockCoordinator,
        resolveSiteInteractionLogicService: (): SiteInteractionLogicService => this.siteInteractionLogicService,
        resolveTabScopedEventContextCoordinator: () => this.tabScopedEventContextCoordinator,
        resolveTabCloseCoordinator: (): BrowserTabCloseCoordinator => this.browserTabCloseCoordinator,
        resolveUIContext: () => this.getUIContext()
      }
    );
  private browserTabRuntimeLifecycleService: BrowserTabRuntimeLifecycleService =
    new BrowserTabRuntimeLifecycleService();
  private browserUserAgentClientHintsService: BrowserUserAgentClientHintsService =
    new BrowserUserAgentClientHintsService();
  private browserUserAgentRuntimeService: BrowserUserAgentRuntimeService =
    new BrowserUserAgentRuntimeService(this.browserUserAgentClientHintsService);
  private browserRuntimeLifecyclePortHost: BrowserRuntimeLifecyclePortHost = {
    getTabs: (): BrowserTabState[] => this.tabs,
    getWindowScopeId: (): string => this.getWindowScopeId(),
    getActiveTabId: (): string => this.activeTabId,
    isHomeVisible: (): boolean => this.showHomePage,
    applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch): void => {
      this.browserTabSwitchCoordinator.applyTabPatch(tabId, patch);
    },
    recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
      this.recordRuntimeEvent(type, message, tabId);
    }
  };
  private browserRuntimeLifecyclePort: BrowserRuntimeLifecyclePort =
    new BrowserRuntimeLifecyclePort(
      this.tabManager,
      this.browserRuntimeLifecyclePortHost,
      (): webview.WebviewController => this.webRuntimeBridge.createController(),
      {
        persistMountedRuntimeSnapshot: (tabId: string, releaseHostedNodeAfterPersist: boolean): void => {
          this.browserTabRecoveryCoordinator.runMountedSnapshotPersistFromHost(
            this.webStateSnapshotStore,
            tabId,
            releaseHostedNodeAfterPersist,
            this.browserSnapshotPersistenceHost
          );
        },
        hostedRuntimeReleaseSink: this.browserUserAgentRuntimeService
      },
      this.browserTabRuntimeLifecycleService
    );
  private browserMediaDiscoveryRuntime: BrowserMediaDiscoveryRuntime =
    createBrowserMediaDiscoveryRuntime(this.browserRuntimeLifecyclePort);
  private browserRuntimeMutationPort: BrowserRuntimeMutationPort =
    new BrowserRuntimeMutationPort(this.browserRuntimeLifecyclePort);
  private browserShellStateCoordinator: BrowserShellStateCoordinator =
    new BrowserShellStateCoordinator(this.browserShellViewModel, this.browserAddressDisplayCoordinator);
  private browserActiveTabShellStateCoordinator: BrowserActiveTabShellStateCoordinator =
    new BrowserActiveTabShellStateCoordinator(this.browserShellStateCoordinator);
  private browserTabPreviewAssetBoundaryCoordinator: BrowserTabPreviewAssetBoundaryCoordinator =
    new BrowserTabPreviewAssetBoundaryCoordinator();
  private browserHistoryApiBridgePolicy: BrowserHistoryApiBridgePolicy = new BrowserHistoryApiBridgePolicy();
  private browserChromeRuntimeCoordinator: BrowserChromeRuntimeCoordinator = new BrowserChromeRuntimeCoordinator();
  private browserScrollPerformanceCoordinator: BrowserScrollPerformanceCoordinator =
    new BrowserScrollPerformanceCoordinator();
  private browserWebTopSafeAreaColorSampler: BrowserWebTopSafeAreaColorSampler = new BrowserWebTopSafeAreaColorSampler();
  private browserWebActiveSurfaceShell: BrowserWebActiveSurfaceShell = {
    readFacts: (): BrowserWebActiveSurfaceFacts => ({
      tabs: this.tabs,
      activeTabId: this.activeTabId,
      currentUrl: this.currentUrl,
      pendingWebUrl: this.pendingWebUrl,
      addressInput: this.addressInput,
      currentTitle: this.currentTitle,
      webPageVisible: this.isWebPageVisible(),
      showTabsSheet: this.showTabsSheet,
      controllerAttached: this.controllerAttached,
      pageErrorSurfaceVisible: this.showPageErrorSurface,
      renderedPageErrorSurfaceVisible: this.shouldRenderWebPageErrorSurface(),
      pageErrorSurfaceReloadHold: this.holdPageErrorSurfaceDuringReload,
      activeErrorDocumentRetryTabId: this.activeErrorDocumentRetryTabId,
      chromeRuntimeState: this.browserChromeRuntimeState,
      webScrollExperimentSettings: this.webScrollExperimentSettings,
      currentWindowId: this.currentWindowId,
      hostedWebSurfaceSuspended: this.shouldSuspendHostedWebSurface(),
      visualSamplingSuppressed: this.isTopImmersionPreferenceEnabled()
    }),
    applyState: (application: BrowserWebActiveSurfaceStateApplication): void => {
      if (application.visualState !== undefined) {
        this.applyShellVisualState(application.visualState);
      }
      if (application.navigationState !== undefined) {
        this.canGoBack = application.navigationState.canGoBack;
        this.canGoForward = application.navigationState.canGoForward;
      }
      if (application.committedUrlRestoreState !== undefined) {
        const state = application.committedUrlRestoreState;
        this.currentUrl = state.currentUrl;
        this.pendingWebUrl = state.pendingWebUrl;
        this.addressInput = state.addressInput;
        this.currentTitle = state.currentTitle;
        this.isLoading = false;
      }
      if (application.historyTargetPreviewState !== undefined) {
        const state = application.historyTargetPreviewState;
        this.currentUrl = state.currentUrl;
        this.pendingWebUrl = state.pendingWebUrl;
        this.addressInput = state.addressInput;
      }
      if (application.chromeRuntimeState !== undefined) {
        this.browserChromeRuntimeState = application.chromeRuntimeState;
      }
      if (application.helperMessage !== undefined) {
        this.helperMessage = application.helperMessage;
      }
      if (application.loadingProgressState !== undefined) {
        this.loadingProgressState = application.loadingProgressState;
        this.isLoading = application.loadingProgressState.isLoading;
      }
      if (application.incrementVideoAssistantPresentationRevision === true) {
        this.arkWebMediaTakeoverRevision += 1;
      }
      if (application.tabs !== undefined) {
        this.tabs = application.tabs;
        this.tabCount = application.tabs.length;
      }
      if (application.activeDocumentState !== undefined) {
        this.currentUrl = application.activeDocumentState.currentUrl;
        this.pendingWebUrl = application.activeDocumentState.pendingWebUrl;
        this.addressInput = application.activeDocumentState.addressInput;
        this.currentTitle = application.activeDocumentState.currentTitle;
      }
      if (application.errorMessage !== undefined) {
        this.errorMessage = application.errorMessage;
      }
      if (application.runtimeDegradedMessage !== undefined) {
        this.runtimeDegradedMessage = application.runtimeDegradedMessage;
      }
      if (application.loading !== undefined) {
        this.isLoading = application.loading;
      }
      if (application.controllerAttached !== undefined) {
        this.controllerAttached = application.controllerAttached;
      }
      if (application.errorSurfaceState !== undefined) {
        this.showPageErrorSurface = application.errorSurfaceState.visible;
        this.holdPageErrorSurfaceDuringReload = application.errorSurfaceState.reloadHold;
        this.activeErrorDocumentRetryTabId = application.errorSurfaceState.retryTabId;
      }
    },
    persistActiveTabSnapshot: (snapshotReason: string): void => {
      this.persistActiveTabSnapshot(snapshotReason);
    },
    resolvePageChromeThemeVisualSamplingContext: () => ({
      uiContext: this.getUIContext(),
      systemTopInsetPx: this.browserWebTopImmersionSessionCoordinator.resolveWebTopSystemInsetVp(
        this.browserWindowAvoidAreaCoordinator.readStoredWebTopGeometryInsets(this.getSharedStageStorage())
      ),
      contentGapPx: WEB_TOP_CHROME_CONTENT_GAP_VP
    }),
    syncBottomPanelStatusBarStyle: (): void => {
      this.syncBottomPanelStatusBarStyle();
    },
    exitVideoAssistantFullscreen: (): void => {
      void this.exitVideoAssistantFullscreenAsync(false);
    },
    clearRootBottomChromeScrollVisualCollapse: (): void => {
      this.browserRootBottomPanelSessionCoordinator.restoreScrollPresentation();
    },
    openSystemNetworkSettings: (): void => {
      void this.openSystemNetworkSettings();
    }
  };
  private browserWebActiveSurfaceCoordinator: BrowserWebActiveSurfaceCoordinator =
    new BrowserWebActiveSurfaceCoordinator({
      tabManager: this.tabManager,
      shellStateCoordinator: this.browserShellStateCoordinator,
      shellViewModel: this.browserShellViewModel,
      resolveTabSwitchCoordinator: (): BrowserTabSwitchCoordinator => this.browserTabSwitchCoordinator,
      runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
      addressDisplayCoordinator: this.browserAddressDisplayCoordinator,
      resolveVisibleUrlService: (): TelegramWebCompatibilityService => this.telegramWebCompatibilityService,
      chromeRuntimeCoordinator: this.browserChromeRuntimeCoordinator,
      colorSampler: this.browserWebTopSafeAreaColorSampler,
      resolveWebTabsController: (): BrowserWebTabsController => this.browserWebTabsController,
      resolveWebScrollInteractionCoordinator: (): BrowserWebScrollInteractionCoordinator =>
        this.browserWebScrollInteractionCoordinator,
      resolveSiteControlsRuntimeCoordinator: (): BrowserSiteControlsRuntimeCoordinator =>
        this.browserSiteControlsRuntimeCoordinator,
      finishActivePageLoadingProgress: (): void => {
        this.browserWebPageLifecycleApplicationCoordinator.finishActivePageLoadingProgress();
      },
      navigationStateScrollDeferredDelayMs: WEB_SCROLL_NAVIGATION_STATE_UPDATE_DELAY_MS
    }, this.browserWebActiveSurfaceShell);
  private browserWebActiveSurfaceActionExecutor = this.browserWebActiveSurfaceCoordinator.getActionExecutor();
  private browserWebNavigationStateSyncCoordinator = this.browserWebActiveSurfaceCoordinator.getNavigationStateSyncCoordinator();
  private browserPageChromeThemeSamplingCoordinator = this.browserWebActiveSurfaceCoordinator.getPageChromeThemeSamplingCoordinator();
  private browserWebActiveSurfaceHost = this.browserWebActiveSurfaceCoordinator.getVisualStateHost();
  private browserWebPageLifecycleApplicationHost = this.browserWebActiveSurfaceCoordinator.getPageLifecycleHost();
  private browserTabRecoveryCoordinator: BrowserTabRecoveryCoordinator =
    new BrowserTabRecoveryCoordinator(this.browserRuntimeLifecyclePort);
  private browserStartupTabRestoreHost: BrowserStartupTabRestoreHost = {
    resolveFacts: () => ({
      activeTabId: this.activeTabId,
      tabSequence: this.tabSequence,
      runtimeDegradedMessage: this.runtimeDegradedMessage,
      tabs: this.tabs,
      currentWindowId: this.currentWindowId
    }),
    setStartupHomeSurfacePending: (pending: boolean): void => {
      this.startupHomeSurfacePending = pending;
    },
    applyState: (application: BrowserStartupTabRestoreStateApplication): void => {
      const snapshot = application.tabSnapshot;
      if (snapshot !== undefined) {
        this.tabs = snapshot.tabs;
        this.activeTabId = snapshot.activeTabId;
        this.tabSequence = snapshot.tabSequence;
      }
      if (application.restoreCompleted === true) this.isRestoringTabs = false;
      if (application.runtimeDegradedMessage !== undefined) this.runtimeDegradedMessage =
        application.runtimeDegradedMessage;
      if (application.resetHomeNavigationState === true) {
        this.canGoBack = false;
        this.canGoForward = false;
        this.controllerAttached = false;
      }
      if (application.previewRenderRevisionIncrement === true) this.tabPreviewRenderVersion += 1;
    },
    resetHomeTransientUiState: (): void => this.resetHomeTransientUiState(),
    applyShellVisualState: (state: BrowserShellVisualState): void => this.applyShellVisualState(state),
    connectSearchInvocationSurfaceIfReady: (): void => this.connectBrowserSearchInvocationSurfaceIfReady()
  };
  private browserTabSessionPersistenceHost: BrowserTabSessionPersistenceHost = {
    isRestoringTabs: (): boolean => this.isRestoringTabs,
    getTabs: (): BrowserTabState[] => this.tabs,
    getActiveTabId: (): string => this.activeTabId,
    getCurrentWindowId: (): string => this.currentWindowId,
    getCurrentTabSessionProfileId: (): BrowserProfileId =>
      this.browserWindowContextCoordinator.resolveCurrentTabSessionProfileId()
  };
  private browserWebPrintService: BrowserWebPrintService = new BrowserWebPrintService();
  private browserQrScanShell: BrowserQrScanShell = {
    publishSnapshot: (snapshot: BrowserQrScanSessionSnapshot): void => {
      this.browserQrScanSessionSnapshot = snapshot;
    },
    showToast: (message: string): void => {
      this.showNativeToast(message);
    },
    openNavigation: (target: BrowserQrScanNavigationTarget, value: string): void => {
      if (target === 'account_settings') {
        this.browserShellRouteCoordinator.openSettingsCenterPage();
      } else {
        void this.openSubmittedAddress(value);
      }
    },
    setSurfaceVisible: (surface: BrowserQrScanSurface, visible: boolean): void => {
      if (surface === 'desktop_login_confirm') {
        if (visible) {
          this.browserTransientSurfaceCoordinator.openSystemSheet('desktopLoginConfirm');
        } else {
          this.closeSystemSheet();
        }
        return;
      }
      if (visible) {
        this.browserTransientSurfaceCoordinator.present({
          id: 'wifi_qr_result',
          revealDelayMs: BROWSER_MODAL_BOTTOM_SHEET_OPEN_DELAY_MS,
          dismissDurationMs: BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS
        });
      } else {
        this.browserTransientSurfaceCoordinator.dismiss('wifi_qr_result');
      }
    }
  };
  private browserQrScanCoordinator: BrowserQrScanCoordinator =
    new BrowserQrScanCoordinator(sharedAiraSyncConfigStore, this.browserQrScanShell);
  private appProxySettingsViewModel: AppProxySettingsViewModel = new AppProxySettingsViewModel();
  private appProxySettingsCoordinator: AppProxySettingsCoordinator = new AppProxySettingsCoordinator(
    sharedPreferencesRepository,
    sharedArkWebAppProxyService,
    this.appProxySettingsViewModel,
    (): void => {
      sharedBrowserProxyRuntimeRefreshCoordinator.requestRefresh();
    }
  );
  private appProxyQuickSheetShell: AppProxyQuickSheetShell = {
    publishState: (state: AppProxyQuickSheetState): void => {
      this.appProxyQuickSheetState = state;
    },
    setSurfaceVisible: (visible: boolean): void => {
      if (visible) {
        this.browserTransientSurfaceCoordinator.present({
          id: 'app_proxy_quick',
          revealDelayMs: APP_PROXY_QUICK_OVERLAY_OPEN_DELAY_MS,
          dismissDurationMs: APP_PROXY_QUICK_OVERLAY_ANIMATION_DURATION_MS
        });
      } else {
        this.browserTransientSurfaceCoordinator.dismiss('app_proxy_quick');
      }
    },
    showMessage: (message: string): void => {
      this.showNativeToast(message);
    },
    openSettings: (): void => {
      this.browserShellRouteCoordinator.openAppProxySettingsPage();
    }
  };
  private appProxyQuickSheetCoordinator: AppProxyQuickSheetCoordinator =
    new AppProxyQuickSheetCoordinator(this.appProxySettingsCoordinator, this.appProxyQuickSheetShell);
  private userScriptRuntimeCoordinator: UserScriptRuntimeCoordinator =
    createUserScriptBrowserRuntimeCoordinator(
      this.browserRuntimeLifecyclePort,
      {
        openInTab: (openerTabId: string, url: string, active: boolean): void =>
          this.browserAppUrlOpenCoordinator.openUserScriptRequestedTab(openerTabId, url, active),
        requestDownload: (request: ManualDownloadRequestInput): string =>
          this.browserDownloadConfirmOverlayCoordinator.requestAndPresent(request),
        showMessage: (message: string): void => {
          this.helperMessage = message;
          this.showNativeToast(message);
        },
        runMediaSniff: (tabId: string, sourcePageUrl: string): void =>
          this.browserMediaDiscoveryCoordinator.runUserScriptMediaScanForTab(
            tabId,
            sourcePageUrl,
            this.browserMediaDiscoveryHost
          )
      }
    );
  private browserHostedWebDocumentStartScriptCoordinator: BrowserHostedWebDocumentStartScriptCoordinator =
    new BrowserHostedWebDocumentStartScriptCoordinator(
      this.userScriptRuntimeCoordinator,
      sharedSitePolicyService,
      this.browserMediaDiscoveryRuntime.mediaFrameRuntimeCoordinator
    );
  private tabScopedEventContextHost: BrowserTabScopedEventContextHost = {
    readFacts: (): BrowserTabScopedEventContextFacts => ({
      tabs: this.tabs,
      activeTabId: this.activeTabId,
      showHomePage: this.showHomePage,
      homeProfileId: this.homeProfileId,
      homePrivacyMode: this.homePrivacyMode,
      homeDataScope: this.homeDataScope,
      currentUrl: this.currentUrl,
      addressInput: this.addressInput
    }),
    resolveOrigin: (url: string): string => this.siteInteractionLogicService.resolveOrigin(url)
  };
  private tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator =
    new BrowserTabScopedEventContextCoordinator(
      this.tabScopedEventContextHost,
      this.browserPrivateProfileLifecycleCoordinator
    );
  private browserWindowOpenApplicationHost: BrowserWindowOpenApplicationHost = {
    getWebRuntimeBridge: (): WebRuntimeBridge => this.webRuntimeBridge,
    findTabById: (tabId: string): BrowserTabState | undefined => this.tabManager.getTab(this.tabs, tabId),
    buildCreateOptions: (tabId: string): BrowserCreateTabOptions =>
      this.tabScopedEventContextCoordinator.buildCreateOptions(tabId),
    hasRecentAction: (now: number): boolean => this.browserRecentActionManager.isRecentAction(now),
    setHelperMessage: (message: string): void => {
      this.helperMessage = message;
    },
    recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
      this.recordRuntimeEvent(type, message, tabId);
    },
    showManualDownloadConfirmSheet: (_tabId: string, url: string): void => {
      this.browserDownloadConfirmOverlayCoordinator.requestAndPresent({
        url: url,
        totalBytes: 0
      });
    },
    getTabs: (): BrowserTabState[] => this.tabs,
    setTabs: (tabs: BrowserTabState[]): void => {
      this.tabs = tabs;
    },
    getTabSequence: (): number => this.tabSequence,
    setTabSequence: (tabSequence: number): void => {
      this.tabSequence = tabSequence;
    },
    getHomeUrl: (): string => HOME_TAB_URL,
    getActiveTabId: (): string => this.activeTabId,
    setActiveTabId: (tabId: string): void => {
      this.activeTabId = tabId;
    },
    captureOpenerPreviewBeforeManagedTabOpen: (
      openerTabId: string,
      targetTabId: string,
      source: BrowserTabPreviewOpenerBeforeSwitchSource
    ): Promise<void> => {
      return this.captureCurrentTabPreviewBeforeLeavingOpenerTab(openerTabId, targetTabId, source);
    },
    retainWindowOpenOpener: (openerTabId: string, targetTabId: string): void => {
      this.browserHostedRuntimeSurfacePort.retainWindowOpenOpener(openerTabId, targetTabId);
    },
    switchToTab: (tabId: string): Promise<void> =>
      this.browserTabSwitchCoordinator.switchToTab(tabId),
    closeTab: (tabId: string): Promise<void> => this.browserTabCloseCoordinator.closeTab(tabId),
    closeActiveTabBackToLastTabOrHome: (reason: string): Promise<void> =>
      this.browserTabCloseCoordinator.closeActiveTabBackToLastTabOrHome(reason),
    syncTabPreviewCacheWithTabs: (): void => {
      this.syncTabPreviewCacheWithTabs();
    },
    requestCloseTabsOverview: (): void => {
      this.dispatchTabsOverviewSession({ type: 'request_close' });
    },
    syncActiveTabToView: (): void => {
      this.browserTabSwitchCoordinator.synchronizeActiveTab();
    },
    recordRecentCreate: (now: number): void => {
      this.browserRecentActionManager.recordCreate(now);
    },
    persistTabs: (): void => {
      this.browserTabSessionPersistenceCoordinator.persist();
    },
    syncPrivateModeLockForCurrentBoundary: (): void => {
      this.browserPrivateModeLockCoordinator.synchronizeCurrentBoundary();
    }
  };
  private browserWindowOpenApplicationCoordinator: BrowserWindowOpenApplicationCoordinator =
    new BrowserWindowOpenApplicationCoordinator(
      this.tabManager,
      this.browserWindowOpenApplicationHost
    );
  private browserForegroundTabCreationCoordinator: BrowserForegroundTabCreationCoordinator =
    new BrowserForegroundTabCreationCoordinator(
      this.tabManager,
      (): BrowserAppUrlOpenHost => this.browserAppUrlOpenHost,
      {
        privateModeLockCoordinator: this.browserPrivateModeLockCoordinator,
        privateProfileLifecycleCoordinator: this.browserPrivateProfileLifecycleCoordinator,
        privateProfileCookieLifecycleHost: this.browserPrivateProfileCookieLifecycleHost,
        resolveTabSwitchCoordinator: (): BrowserTabSwitchCoordinator => this.browserTabSwitchCoordinator,
        resolveTabSessionPersistenceCoordinator: (): BrowserTabSessionPersistenceCoordinator =>
          this.browserTabSessionPersistenceCoordinator,
        resolveTabsOverviewSessionCoordinator: (): BrowserTabsOverviewSessionCoordinator =>
          this.tabsOverviewSessionCoordinator
      }
    );
  private shortcutIconResolver: ShortcutIconResolverService = sharedShortcutIconResolverService;
  private browserBackgroundOpenPromptShell: BrowserBackgroundOpenPromptShell = {
    publishSnapshot: (state: BrowserBackgroundOpenPromptState, animateStack: boolean): void => {
      if (!animateStack) {
        this.backgroundOpenPromptState = state;
        return;
      }
      animateTo({
        duration: BACKGROUND_OPEN_PROMPT_STACK_ANIMATION_MS,
        curve: Curve.Friction
      }, () => {
        this.backgroundOpenPromptState = state;
      });
    },
    showQueuedToast: (): void => {
      this.showNativeToast('已加入等待打开队列');
    }
  };
  private browserBackgroundOpenPromptCoordinator: BrowserBackgroundOpenPromptCoordinator =
    new BrowserBackgroundOpenPromptCoordinator(
      this.shortcutIconResolver,
      this.browserBackgroundOpenPromptShell
    );
  private browserTabSwitchApplicationSink: BrowserTabSwitchApplicationSink = {
    resolveFacts: () => ({
      tabs: this.tabs,
      activeTabId: this.activeTabId,
      tabSequence: this.tabSequence,
      showHomePage: this.showHomePage,
      controllerAttached: this.controllerAttached,
      currentWindowId: this.currentWindowId,
      activeDownloadCount: this.activeDownloadCount,
      runtimeDegradedMessage: this.runtimeDegradedMessage,
      fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled
    }),
    persistActiveTabSnapshot: (reason: string): void => {
      this.persistActiveTabSnapshotAsync(reason);
    },
    applyTabSelection: (tabs: BrowserTabState[], activeTabId: string): void => {
      this.tabs = tabs;
      this.syncTabPreviewCacheWithTabs();
      this.activeTabId = activeTabId;
    },
    applyTabs: (tabs: BrowserTabState[]): void => {
      this.tabs = tabs;
      this.tabCount = tabs.length;
    },
    notifyTabPreviewChanged: (): void => this.notifyTabPreviewChanged(),
    applyTabSequence: (tabSequence: number): void => {
      this.tabSequence = tabSequence;
    },
    captureOpenerPreviewBeforeBackgroundPromptSwitch: (openerTabId: string, targetTabId: string): Promise<void> =>
      this.captureCurrentTabPreviewBeforeLeavingOpenerTab(openerTabId, targetTabId, 'background_prompt'),
    applyShellApplication: (application): void => {
      if (application.resetHomeTransientUiState) {
        this.resetHomeTransientUiState();
      }
      if (application.invalidateWebSessionTransition) {
        this.invalidateWebSessionTransition();
      }
      this.applyShellVisualState(application.visualState);
      if (application.resetHomeNavigationState) {
        this.canGoBack = false;
        this.canGoForward = false;
        this.controllerAttached = false;
      }
      this.tabCount = application.tabCount;
    },
    applyHelperMessage: (message: string): void => {
      this.helperMessage = message;
    },
    executePlatformAction: (action): void => {
      switch (action) {
        case 'cancel_bottom_panel_backdrop_focus':
          this.cancelRootBottomPanelAddressFocusBackdropTransition();
          return;
        case 'request_close_tabs_overview':
          this.dispatchTabsOverviewSession({ type: 'request_close' });
          return;
        case 'restore_web_bottom_address_panel':
          this.restoreWebBottomAddressPanelFromPeek();
          return;
        case 'sync_download_boundary':
          this.syncDownloadBoundary();
          return;
        case 'disable_fullscreen':
          this.disableFullScreenMode();
          return;
        case 'sync_bottom_panel_status_bar':
          this.syncBottomPanelStatusBarStyle();
          return;
      }
    }
  };
  private browserTabSwitchCoordinator: BrowserTabSwitchCoordinator =
    new BrowserTabSwitchCoordinator(this.tabManager, {
      privateModeLockCoordinator: this.browserPrivateModeLockCoordinator,
      activeTabShellStateCoordinator: this.browserActiveTabShellStateCoordinator,
      backgroundOpenPromptCoordinator: this.browserBackgroundOpenPromptCoordinator,
      resolveActiveRuntimeSyncCoordinator: (): BrowserActiveRuntimeSyncCoordinator =>
        this.browserActiveRuntimeSyncCoordinator,
      resolveWebTabsController: (): BrowserWebTabsController => this.browserWebTabsController,
      resolveBackgroundTabPreviewRuntimeCoordinator: (): BrowserBackgroundTabPreviewRuntimeCoordinator =>
        this.browserBackgroundTabPreviewRuntimeCoordinator,
      resolveBackgroundSessionSyncCoordinator: (): BrowserTabBackgroundSessionSyncCoordinator =>
        this.browserTabBackgroundSessionSyncCoordinator,
      resolveBottomChromeScrollCoordinator: (): BrowserBottomChromeScrollCoordinator =>
        this.browserBottomChromeScrollCoordinator,
      resolveTopImmersionSessionCoordinator: (): BrowserWebTopImmersionSessionCoordinator =>
        this.browserWebTopImmersionSessionCoordinator,
      resolveMediaDiscoveryCoordinator: (): BrowserMediaDiscoveryCoordinator =>
        this.browserMediaDiscoveryCoordinator,
      resolveMediaDiscoveryHost: (): BrowserMediaDiscoveryHost => this.browserMediaDiscoveryHost,
      resolveTabSessionPersistenceCoordinator: (): BrowserTabSessionPersistenceCoordinator =>
        this.browserTabSessionPersistenceCoordinator,
      resolveUserAgentActionCoordinator: (): BrowserUserAgentActionCoordinator =>
        this.browserUserAgentActionCoordinator,
      resolvePageFindCoordinator: (): BrowserPageFindCoordinator => this.browserPageFindCoordinator,
      resolveAddressDisplayCoordinator: (): BrowserAddressDisplayCoordinator =>
        this.browserAddressDisplayCoordinator,
      resolveRuntimeMutationPort: (): BrowserRuntimeMutationPort => this.browserRuntimeMutationPort,
      resolveTabPreviewAssetBoundaryCoordinator: (): BrowserTabPreviewAssetBoundaryCoordinator =>
        this.browserTabPreviewAssetBoundaryCoordinator,
      resolveTabPreviewCoordinator: (): BrowserTabPreviewCoordinator => this.browserTabPreviewCoordinator,
      resolveTabsOverviewSnapshotPipelineCoordinator: (): BrowserTabsOverviewSnapshotPipelineCoordinator =>
        this.tabsOverviewSnapshotPipelineCoordinator,
      resolveElementInspectionSessionCoordinator: (): ElementInspectionSessionCoordinator =>
        this.elementInspectionSessionCoordinator,
      resolveSuspendedWindowTabsByWindowId: (): Record<string, BrowserTabState[] | undefined> =>
        this.browserWindowContextCoordinator.getSuspendedWindowTabsByWindowId(),
      resolveRuntimeDegradedReason: (tabId: string): string => this.webRecoveryManager.getDegradedReason(tabId),
      sink: this.browserTabSwitchApplicationSink
    });
  private consumedBrowserNavigationRouteToken: string = '';
  private browserNativeNavigationConsumeHost: BrowserNativeNavigationConsumeHost = {
    getRouteParams: (): BrowserNavigationRouteParams | undefined =>
      router.getParams() as BrowserNavigationRouteParams | undefined,
    getConsumedRouteToken: (): string => this.consumedBrowserNavigationRouteToken,
    setConsumedRouteToken: (routeToken: string): void => {
      this.consumedBrowserNavigationRouteToken = routeToken;
    },
    getActiveTabId: (): string => this.activeTabId,
    openBrowserRequest: (request: BrowserAppUrlOpenRequest): void => this.browserAppUrlOpenCoordinator.open(request),
    openTabsOverview: (): void => {
      void this.openTabsOverview();
    },
    returnHome: (): void => {
      void this.browserTabHomeCoordinator.goHome();
    }
  };
  private browserNativeNavigationConsumeCoordinator: BrowserNativeNavigationConsumeCoordinator =
    new BrowserNativeNavigationConsumeCoordinator(this.browserNativeNavigationConsumeHost);
  private browserTabsOverviewThemeViewModel: BrowserTabsOverviewThemeViewModel =
    new BrowserTabsOverviewThemeViewModel();
  private browserRootBackgroundViewModel: BrowserRootBackgroundViewModel = new BrowserRootBackgroundViewModel();
  private browserOpenTabsButtonViewModel: BrowserOpenTabsButtonViewModel = new BrowserOpenTabsButtonViewModel();
  private browserTabPreviewSurfaceHost: BrowserTabPreviewSurfaceHost = {
    isHostedControllerAttached: (tabId: string): boolean =>
      this.browserHostedRuntimeSurfacePort.isHostedControllerAttached(tabId),
    isBackgroundHot: (tabId: string): boolean =>
      this.browserHostedRuntimeSurfacePort.isBackgroundHot(tabId),
    resolveWebViewportSnapshotSize: (): BrowserTabPreviewWebViewportSize => {
      if (this.hostedWebLayerMeasured && this.hostedWebLayerWidth > 1 && this.hostedWebLayerHeight > 1) {
        return {
          width: this.hostedWebLayerWidth,
          height: this.hostedWebLayerHeight
        };
      }
      return {
        width: this.rootViewportWidth,
        height: this.rootViewportHeight
      };
    }
  };
  private browserTabPreviewCoordinator: BrowserTabPreviewCoordinator =
    new BrowserTabPreviewCoordinator(this.browserRuntimeLifecyclePort, this.browserTabPreviewSurfaceHost);
  private browserFaviconApplyHost: BrowserFaviconApplyHost = {
    updatePreviewFavicon: (tabId: string, favicon: image.PixelMap): boolean => {
      return this.browserTabPreviewCoordinator.updateFavicon(tabId, favicon);
    },
    notifyPreviewChanged: (): void => {
      this.notifyTabPreviewChanged();
    }
  };
  private browserTabPreviewActionCoordinator: BrowserTabPreviewActionCoordinator =
    new BrowserTabPreviewActionCoordinator();
  private browserBackgroundTabPreviewRuntimeOptions: BrowserBackgroundTabPreviewRuntimeOptions = {
    maxBackgroundHotTabCount: MAX_BACKGROUND_HOT_TAB_COUNT,
    maxAttachAttempts: BACKGROUND_TAB_PREVIEW_MAX_ATTACH_ATTEMPTS,
    attachRetryDelayMs: BACKGROUND_TAB_PREVIEW_ATTACH_RETRY_DELAY_MS
  };
  private browserBackgroundTabPreviewRuntimeHost: BrowserBackgroundTabPreviewRuntimeHost =
    {
      resolveTab: (tabId: string): BrowserTabState | undefined => this.tabManager.getTab(this.tabs, tabId),
      getActiveTabId: (): string => this.activeTabId,
      getPreviewHostedTabId: (): string => this.browserHostedRuntimeSurfacePort.getPreviewHostedTabId(),
      hasUsablePreview: (tabId: string): boolean => this.browserTabPreviewCoordinator.hasUsableSharedSnapshot(tabId),
      markBackgroundHot: (tabId: string, maxCount: number, releaseReason: BrowserHostedWebNodeDisposeReason): void => {
        this.browserHostedRuntimeSurfacePort.markBackgroundHot(tabId, maxCount, releaseReason);
      },
      refreshRuntime: (tab: BrowserTabState, tabIdWhenMissing: string): WebTabRuntimeRecord | undefined => {
        return this.browserRuntimeMutationPort.refreshTab(tab, tabIdWhenMissing);
      },
      markControllerAttached: (tabId: string): WebTabRuntimeRecord | undefined => {
        return this.browserControllerAttachmentRuntimeCoordinator.markControllerAttached(tabId);
      },
      applyUserAgent: (tabId: string, controller?: webview.WebviewController): void => {
        this.browserWebLoadRuntimeCoordinator.applyUserAgentToControllerForTab(
          tabId, controller, this.tabManager.getTab(this.tabs, tabId)?.pendingUrl ?? '');
      },
      syncPreview: (
        tab: BrowserTabState,
        runtime: WebTabRuntimeRecord
      ): BrowserWebHostAttachState => this.browserHostedRuntimeSurfacePort.syncPreviewAttachStateFromHost(tab, runtime),
      isHostedControllerAttached: (tabId: string): boolean => {
        return this.browserHostedRuntimeSurfacePort.isHostedControllerAttached(tabId);
      },
      capturePreview: (tabId: string): Promise<boolean> => {
        return this.captureTabPreviewForExplicitAction(tabId, true, true);
      },
      applyBackgroundPreviewRuntimeState: (tabId: string, runtimeState: TabRuntimeState): void => {
        this.browserHostedRuntimeSurfacePort.applyBackgroundRuntimeState(
          tabId,
          runtimeState
        );
      },
      loadUrl: (request: BrowserBackgroundTabPreviewRequest): boolean => {
        return this.browserWebLoadRuntimeCoordinator.runBackgroundTabPreviewLoad(
          request.tabId,
          request.url
        );
      },
      releaseBackgroundHot: (tabId: string, releaseReason: BrowserHostedWebNodeDisposeReason): void => {
        this.browserHostedRuntimeSurfacePort.releaseBackgroundHot(tabId, releaseReason);
      },
      recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
        this.recordRuntimeEvent(type, message, tabId);
      }
    };
  private browserBackgroundTabPreviewRuntimeCoordinator: BrowserBackgroundTabPreviewRuntimeCoordinator =
    new BrowserBackgroundTabPreviewRuntimeCoordinator(
      this.browserBackgroundTabPreviewRuntimeHost,
      this.browserBackgroundTabPreviewRuntimeOptions
    );
  private browserRecentActionManager: BrowserRecentActionManager = new BrowserRecentActionManager();
  private browserTabPreviewDebugExportService: BrowserTabPreviewDebugExportService =
    new BrowserTabPreviewDebugExportService();
  private browserTabBackgroundSessionSyncCoordinatorHost: BrowserTabBackgroundSessionSyncCoordinatorHost = {
    isRestoringTabs: (): boolean => {
      return this.isRestoringTabs;
    },
    getTabs: (): BrowserTabState[] => {
      return this.tabs;
    },
    getActiveTabId: (): string => {
      return this.activeTabId;
    },
    getWindowId: (): string => {
      return this.getWindowScopeId();
    },
    getPreviousRetentionPlan: (): WebRuntimeRetentionPlan => {
      return this.currentRuntimeRetentionPlan;
    },
    applySessionSyncState: (tabs: BrowserTabState[], retentionPlan: WebRuntimeRetentionPlan): void => {
      this.currentRuntimeRetentionPlan = retentionPlan;
      this.tabs = tabs;
      this.tabCount = tabs.length;
    },
    recordRuntimeEvent: (type: string, message: string, tabId?: string): void => {
      this.recordRuntimeEvent(type, message, tabId);
    }
  };
  private browserWebLayerGeometryCache: BrowserWebLayerGeometryCache = new BrowserWebLayerGeometryCache();
  private browserWebLayerGeometryStore: BrowserWebLayerGeometryStore = new BrowserWebLayerGeometryStore();
  private browserTabsOverviewSessionHost: BrowserTabsOverviewSessionHost = {
    readSessionFacts: (): BrowserTabsOverviewSessionFacts => {
      const safeInsets = this.browserWindowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage());
      return {
        tabs: this.tabs,
        tabSequence: this.tabSequence,
        tabsOverviewMounted: this.showTabsSheet,
        homeSurfaceVisible: this.showHomePage,
        keepHomeResident: this.shouldKeepCustomHomepageWebResident() || this.homeSurfacePaintedOnce,
        currentTabPrivate: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
        activeTabId: this.activeTabId,
        homeUrl: HOME_TAB_URL,
        runtimeDegradedMessage: this.runtimeDegradedMessage,
        rootBottomPanelDetent: this.resolveRootBottomPanelDetent(),
        rootBottomPanelEffectiveHomeMode: this.isRootBottomPanelEffectiveHomeMode(),
        backdropOpenStartProgress: this.resolveTabsOverviewBackdropOpenStartProgress(),
        sharedSnapshotWindow: {
          rootViewportLeft: this.rootViewportLeft,
          rootViewportTop: this.rootViewportTop,
          rootViewportWidth: this.rootViewportWidth,
          rootViewportHeight: this.rootViewportHeight,
          webViewportHostHeight: this.rootBottomPanelLayoutState.webHostHeight,
          webVisualTopInset: this.getWebViewportTopInsetPx(),
          topSafeInsetVp: safeInsets.topInsetVp,
          bottomSafeInsetVp: safeInsets.bottomInsetVp,
          showHomePage: this.showHomePage,
          webAppImmersiveMode: this.isWebAppImmersiveMode(),
          hostedWebLayerMeasured: this.hostedWebLayerMeasured,
          hostedWebLayerLeft: this.hostedWebLayerLeft,
          hostedWebLayerTop: this.hostedWebLayerTop,
          hostedWebLayerWidth: this.hostedWebLayerWidth,
          hostedWebLayerHeight: this.hostedWebLayerHeight,
          reusableGeometry: this.resolveReusableWebLayerGeometry()
        }
      };
    },
    executeAsyncTask: async (
      task: BrowserTabsOverviewAsyncTask
    ): Promise<BrowserTabsOverviewAsyncTaskResult> => {
      switch (task.type) {
        case 'capture_fresh_active_tab_preview':
          return {
            success: await this.captureFreshActiveTabPreviewForOverview(task.tab, task.generation)
          };
      }
      return { success: false };
    },
    executeEffect: (effect: BrowserTabsOverviewSessionEffect): void => {
      switch (effect.type) {
        case 'cancel_bottom_panel_backdrop_focus_transition':
          this.cancelRootBottomPanelAddressFocusBackdropTransition();
          return;
        case 'clear_root_bottom_chrome_scroll':
          this.browserRootBottomPanelSessionCoordinator.restoreScrollPresentation();
          return;
        case 'release_home_search_focus':
          this.browserShellSearchInvocationAdapter.releaseHomeSearchFocus();
          this.addressInput = '';
          return;
        case 'release_web_bottom_address_focus':
          this.setWebBottomAddressFocused(false);
          this.webBottomAddressDraft = '';
          return;
        case 'apply_root_bottom_panel_detent':
          this.applyRootBottomPanelDetent(effect.detent);
          return;
        case 'record_session_trace':
          return;
        case 'sync_bottom_panel_status_bar_style':
          this.syncBottomPanelStatusBarStyle();
          return;
        case 'reset_home_reveal':
          this.browserHomePresentationSessionCoordinator.resetReveal();
          return;
        case 'notify_tab_preview_changed':
          this.notifyTabPreviewChanged();
          return;
        case 'reconcile_external_navigation_prompt':
          this.reconcileExternalNavigationPromptForCurrentPage();
          return;
        case 'refresh_tabs_sheet_appearance':
          this.browserTabHomeCoordinator.refreshTabsOverviewAppearance();
          return;
        case 'show_native_toast':
          this.showNativeToast(effect.message);
          return;
        case 'export_tabs_overview_debug_snapshot':
          this.exportTabsOverviewDebugSnapshot(effect.tabId);
          return;
        case 'flush_scroll_deferred_page_metadata':
          this.browserWebPageLifecycleApplicationCoordinator.flushDeferredPageMetadata(effect.tabId);
          return;
        case 'reset_web_bottom_address_panel_for_tab_selection':
          this.resetWebBottomAddressPanelForTabSelection();
          return;
        case 'prepare_home_reveal_from_tabs_overview':
          this.browserHomePresentationSessionCoordinator.prepareTabsOverviewReveal('scale');
          return;
        case 'prepare_optimistic_home_reveal':
          this.browserHomePresentationSessionCoordinator.prepareTabsOverviewReveal(effect.motion);
          return;
        case 'play_home_reveal_from_tabs_overview':
          this.browserHomePresentationSessionCoordinator.playReveal();
          return;
        case 'apply_section_change':
          this.browserTabHomeCoordinator.applyBoundary(
            effect.options.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
            effect.options.privacyMode ?? 'regular',
            effect.options.dataScope ?? 'profile_persistent'
          );
          this.browserTabHomeCoordinator.refreshTabsOverviewAppearance();
          this.showNativeToast(effect.userMessage);
          return;
        case 'finish_tabs_overview_dismiss_home':
          this.restoreHomeBottomPanelForDirectHomeNavigation();
          return;
        case 'record_runtime_event':
          this.recordRuntimeEvent(effect.eventType, effect.message, effect.tabId);
          return;
        case 'show_close_all_confirmation':
          this.browserNativeAlertDialogPresenter.confirm({
            title: effect.plan.title,
            message: effect.plan.message,
            cancelLabel: '取消',
            confirmLabel: effect.plan.confirmLabel,
            confirmTone: 'alert',
            onConfirm: () => {
              this.dispatchTabsOverviewSession({ type: 'confirm_close_all' });
            }
          });
          return;
        case 'confirm_private_mode_switch':
          this.presentPrivateModeToggleConfirmation(
            this.browserPrivateTabCoordinator.buildModeSwitchConfirmationState(
              effect.plan,
              this.browserPrivateTabCoordinator.countPrivateTabs(this.tabs)
            )
          );
          return;
        case 'show_keyboard_shortcut_message':
          this.showKeyboardShortcutMessage(effect.message);
          return;
        case 'apply_closed_overview_reset':
          this.showTabsSheet = false;
          return;
        case 'play_tabs_overview_arkui_animation':
          animateTo({
            duration: effect.plan.durationMs,
            curve: effect.plan.curve,
            onFinish: effect.plan.onFinish
          }, effect.plan.apply);
          return;
        case 'apply_tabs_overview_entry_shell_state':
          if (effect.shouldResetHomeReveal) {
            this.browserHomePresentationSessionCoordinator.resetReveal();
          }
          if (effect.shouldShowTabsSheet && !this.showTabsSheet) {
            // Opening the sheet: refresh the cached gallery states before the overlay
            // build reads them, so the first frame already carries the current previews.
            this.refreshTabPreviewStates();
            if (this.tabsOverviewOverlayResident) {
              // Already mounted from a previous open: ask it to replay its per-open
              // setup, since a resident overlay never re-enters aboutToAppear.
              this.tabsOverviewOpenRequestVersion += 1;
            } else {
              // First open: the overlay mounts now and runs its own setup.
              this.tabsOverviewOverlayResident = true;
            }
          }
          this.showTabsSheet = effect.shouldShowTabsSheet;
          this.reconcileExternalNavigationPromptForCurrentPage();
          return;
      }
    },
    publishPresentationState: (state: BrowserTabsOverviewSessionPresentationState): void => {
      this.tabsSharedSnapshotState = state.sharedSnapshotState;
      this.tabsOverviewPresentationState = state;
    }
  };
  private browserHomePresentationSessionHost: BrowserHomePresentationSessionHost = {
    resolveFacts: (): BrowserHomePresentationSessionFacts => ({
      showHomePage: this.showHomePage,
      thirdPartyHomepageActive: this.customHomepageRuntimeState.presentation.kind === 'custom_web',
      showTabsSheet: this.showTabsSheet,
      homeSearchFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
      rootBottomPanelDetent: this.rootBottomAddressPanelDetent,
      startupRestorePolicy: sharedPreferencesRepository.getPreferences().general.startupRestorePolicy,
      tabsOverviewAnimationVersion: this.tabsOverviewPresentationState.animationVersion
    }),
    publishState: (state: BrowserHomePresentationSessionState): void => {
      this.homePresentationSessionState = state;
    },
    executeAnimation: (plan: BrowserHomePresentationAnimationPlan): void => {
      animateTo({
        duration: plan.durationMs,
        curve: plan.curve,
        onFinish: plan.onFinish
      }, plan.apply);
    },
    restoreBottomPanelFromPeek: (): void => {
      this.rootBottomAddressPanelDetent = 'low';
      this.syncBottomPanelStatusBarStyle();
    }
  };
  private browserKeyboardAvoidModeCoordinator: BrowserKeyboardAvoidModeCoordinator =
    new BrowserKeyboardAvoidModeCoordinator();
  private browserRootAddressKeyboardInsetSyncHost: BrowserWindowKeyboardInsetSyncHost = {
    isKeyboardInsetSyncActive: (): boolean => {
      return this.browserRootBottomPanelSessionCoordinator.isKeyboardInsetSyncActive(
        this.buildRootAddressInputSessionSnapshot()
      );
    },
    shouldConfirmKeyboardHidden: (): boolean => {
      return this.browserRootBottomPanelSessionCoordinator.shouldConfirmKeyboardHidden(
        this.buildRootAddressInputSessionSnapshot(true)
      );
    },
    resolveWindow: (): Promise<window.Window> => window.getLastWindow(this.getAbilityContext()),
    resolveStorage: (): LocalStorage | undefined => this.getSharedStageStorage(),
    applyKeyboardInset: (insetVp: number): void => {
      this.applyRootAddressKeyboardOverlayInset(insetVp);
    },
    handleKeyboardHidden: (): void => {
      this.handleRootAddressKeyboardHidden();
    }
  };
  private browserRootBottomPanelShellActionExecutor: BrowserRootBottomPanelShellActionExecutor =
    new BrowserRootBottomPanelShellActionExecutor({
      openDocumentViewerInfo: (): void => { void this.openCurrentDocumentViewerInfoDialog(); },
      scanQrCode: (): void => { void this.scanQrCodeFromBottomPanel(); },
      togglePrivateMode: (): void => this.browserPrivateTabCoordinator.requestBottomPanelModeToggle(
        this.browserPrivateModeTogglePresentationHost
      ),
      openTextZoom: (): void => this.openWebTextZoomSheet(),
      openSiteReport: (): void => this.openSiteReportDialog(),
      openTabsOverview: (): void => this.requestOpenTabsOverviewFromRootBottomPanel(),
      requestBrowserBack: (): void => {
        this.browserMainBackCoordinator.onBackPress(this.browserMainBackHost);
      },
      showActionRejection: (message: string): void => this.showNativeToast(message)
    });
  private browserRootBottomPanelSessionCoordinator: BrowserRootBottomPanelSessionCoordinator =
    new BrowserRootBottomPanelSessionCoordinator({
      publishPresentationSnapshot: (snapshot: BrowserRootBottomPanelPresentationSnapshot): void => {
        this.rootBottomPanelPresentationSnapshot = snapshot;
      },
      isHomePageVisible: (): boolean => this.showHomePage,
      applyChromePlan: (plan: BrowserRootBottomPanelChromePlan): void => {
        this.applyRootBottomPanelSessionChromePlan(plan);
      },
      applyShellEffect: (effect: BrowserRootBottomPanelShellEffect): void =>
        this.browserRootBottomPanelShellActionExecutor.applyEffect(effect)
    }, (): BrowserRootBottomPanelFixedActionApplication => this.browserRootBottomPanelActionApplication);
  private browserTransientSurfaceCoordinator: BrowserTransientSurfaceCoordinator =
    new BrowserTransientSurfaceCoordinator(
      this.browserRootBottomPanelSessionCoordinator,
      (): BrowserRootBottomPanelTransientSheetFacts => this.buildRootBottomPanelTransientSheetFacts(),
      (update: BrowserTransientSurfaceUpdate): void => this.applyBrowserTransientSurfaceUpdate(update)
    );
  private webpageTranslationCoordinator: WebpageTranslationCoordinator =
    new WebpageTranslationCoordinator(
      sharedTranslationSecretStore,
      this.browserRuntimeLifecyclePort,
      {
        settingsRepository: sharedTranslationSettingsRepository,
        transientSurfaceCoordinator: this.browserTransientSurfaceCoordinator,
        targetLanguageRevealDelayMs: TRANSLATION_TARGET_LANGUAGE_OVERLAY_OPEN_DELAY_MS,
        targetLanguageDismissDurationMs: TRANSLATION_TARGET_LANGUAGE_OVERLAY_ANIMATION_DURATION_MS
      },
      {
        readContext: (): WebpageTranslationApplicationContext => this.buildWebpageTranslationApplicationContext(),
        publishSnapshot: (snapshot: WebpageTranslationApplicationSnapshot): void => {
          this.webpageTranslationApplicationSnapshot = snapshot;
        },
        showToast: (message: string): void => this.showNativeToast(message),
        showCloudDisclosure: (request: WebpageTranslationCloudDisclosureRequest): void => {
          this.browserNativeAlertDialogPresenter.confirm({
            title: request.title,
            message: request.message,
            cancelLabel: request.cancelLabel,
            confirmLabel: request.acceptLabel,
            onConfirm: request.onAccept
          });
        }
      }
    );
  private browserHomepageBackdropAppearanceCoordinator: BrowserHomepageBackdropAppearanceCoordinator =
    new BrowserHomepageBackdropAppearanceCoordinator();
  private browserHostedWebLayerPresentationViewModel: BrowserHostedWebLayerPresentationViewModel =
    new BrowserHostedWebLayerPresentationViewModel();
  private featureGateCoordinator: FeatureGateCoordinator = new FeatureGateCoordinator(
    sharedMembershipFeature,
    this.browserTransientSurfaceCoordinator,
    this.browserShellRouteCoordinator,
    (snapshot: FeatureGateSnapshot): void => {
      this.featureGateSnapshot = snapshot;
    },
    FEATURE_GATE_OVERLAY_OPEN_DELAY_MS,
    FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS
  );
  private browserActiveTabRuntimeRestoreHost: BrowserActiveTabRuntimeRestoreHost = {
    resolveFacts: () => ({
      activeTabId: this.activeTabId,
      controllerAttached: this.controllerAttached,
      currentUrl: this.currentUrl,
      pendingWebUrl: this.pendingWebUrl,
      addressInput: this.addressInput,
      selectedSearchEngine: this.selectedSearchEngine,
      availableSearchEngines: this.availableSearchEngines,
      tabs: this.tabs,
      showTabsSheet: this.showTabsSheet,
      showHomePage: this.showHomePage,
      holdPageErrorSurfaceDuringReload: this.holdPageErrorSurfaceDuringReload
    }),
    applyState: (application: BrowserActiveTabRuntimeRestoreStateApplication): void => {
      if (application.helperMessage !== undefined) {
        this.helperMessage = application.helperMessage;
      }
      if (application.errorMessage !== undefined) {
        this.errorMessage = application.errorMessage;
      }
      if (application.runtimeDegradedMessage !== undefined) {
        this.runtimeDegradedMessage = application.runtimeDegradedMessage;
      }
      if (application.isLoading !== undefined) {
        this.isLoading = application.isLoading;
      }
      if (application.pageErrorSurfaceVisible !== undefined) {
        this.showPageErrorSurface = application.pageErrorSurfaceVisible;
      }
      if (application.holdPageErrorSurfaceDuringReload !== undefined) {
        this.holdPageErrorSurfaceDuringReload = application.holdPageErrorSurfaceDuringReload;
      }
      if (application.invalidateTransition === true) {
        this.invalidateWebSessionTransition();
      }
      if (application.currentUrl !== undefined) {
        this.currentUrl = application.currentUrl;
      }
      if (application.pendingWebUrl !== undefined) {
        this.pendingWebUrl = application.pendingWebUrl;
      }
    },
    recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
      this.recordRuntimeEvent(type, message, tabId);
    },
    appendRestoreTraceBreadcrumb: (tabId: string, breadcrumb: string): void => {
      this.appendRestoreTraceBreadcrumb(tabId, breadcrumb);
    },
    beginTransition: (): number => this.beginWebSessionTransition(),
    isTransitionCurrent: (token: number, tabId: string): boolean =>
      this.isWebSessionTransitionCurrent(token, tabId)
  };
  private browserActiveRuntimeSyncSink: BrowserActiveRuntimeSyncSink = {
    resolveFacts: () => ({
      activeTabId: this.activeTabId,
      tabs: this.tabs,
      showHomePage: this.showHomePage,
      controllerAttached: this.controllerAttached
    }),
    attachHostedRuntime: (tab: BrowserTabState, runtime: WebTabRuntimeRecord): boolean => {
      const attached = this.browserHostedRuntimeSurfacePort.syncActiveFromHost(tab, runtime);
      this.webController = runtime.controller;
      this.controllerAttached = attached;
      this.applyUserAgentToController(runtime.controller, tab.pendingUrl.length > 0 ? tab.pendingUrl : tab.url);
      return attached;
    },
    beginTransition: (): number => this.beginWebSessionTransition(),
    isTransitionCurrent: (token: number, tabId: string): boolean =>
      this.isWebSessionTransitionCurrent(token, tabId),
    applyControllerAttached: (attached: boolean): void => {
      this.controllerAttached = attached;
    },
    applyRestoreType: (tab: BrowserTabState, restoreType): void => {
      this.tabs = this.tabManager.updateTab(
        this.tabs,
        tab.id,
        this.webSessionStateStore.buildRestoreTypePatch(restoreType, tab)
      );
      this.tabCount = this.tabs.length;
    }
  };
  private browserControllerAttachmentRuntimeCoordinatorHost: BrowserControllerAttachmentRuntimeCoordinatorHost = {
    getActiveTabId: (): string => {
      return this.activeTabId;
    },
    buildBootstrapConfig: (): WebControllerBootstrapConfig => {
      return this.buildWebRuntimeBootstrapConfig();
    },
    applyBootstrapConfig: (config: WebControllerBootstrapConfig): void => {
      this.webRuntimeBootstrapConfig = config;
    },
    applyActiveController: (controller: webview.WebviewController): void => {
      this.webController = controller;
      this.controllerAttached = true;
    },
    applyUserAgent: (controller: webview.WebviewController, pageUrl: string): void => {
      this.applyUserAgentToController(controller, pageUrl);
    },
    finalizeControllerAttachment: (): void => {
      this.browserSiteControlsRuntimeCoordinator.configureCurrentPageAdBlock();
      this.browserWebNavigationStateSyncCoordinator.sync();
      this.browserWebNavigationStateSyncCoordinator.syncSoon();
      this.browserSiteControlsRuntimeCoordinator.handleActiveSurfaceAction('refresh_certificate');
      this.browserSiteControlsRuntimeCoordinator.refreshTrackingProtectionStatus();
    },
    recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
      this.recordRuntimeEvent(type, message, tabId);
    },
    appendRestoreTraceBreadcrumb: (tabId: string, breadcrumb: string): void => {
      this.appendRestoreTraceBreadcrumb(tabId, breadcrumb);
    },
    recordLoadFailure: (tabId: string, message: string): void => {
      this.webRecoveryManager.recordLoadFailure(tabId, message);
    },
    applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch): void => {
      this.browserTabSwitchCoordinator.applyTabPatch(tabId, patch);
    },
    setRestoreEventContext: (tabId: string, targetUrl: string): void => {
      this.webEventRouter.beginNavigation(tabId, this.telegramWebCompatibilityService.resolveVisibleUrl(targetUrl), true);
    },
    releaseEventContext: (tabId: string): void => {
      this.webEventRouter.releaseNavigation(tabId);
    },
    restoreActiveSession: (reason: TabRestoreReason): void => {
      this.browserActiveTabRuntimeRestoreCoordinator.restoreActive(reason);
    }
  };
  private browserSnapshotApplicationHost: BrowserSnapshotApplicationHost = {
    recordRestoreTraceDiagnostic: (
      _type: string,
      _message: string,
      _tabId: string,
      _faultCode: string
    ): void => {},
    recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
      this.recordRuntimeEvent(type, message, tabId);
    },
    appendRestoreTraceBreadcrumb: (tabId: string, breadcrumb: string): void => {
      this.appendRestoreTraceBreadcrumb(tabId, breadcrumb);
    },
    applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch): void => {
      this.browserTabSwitchCoordinator.applyTabPatch(tabId, patch);
    }
  };
  private browserSnapshotPersistenceHost: BrowserSnapshotPersistenceHost = {
    getActiveTabId: (): string => {
      return this.activeTabId;
    },
    getActiveTab: (): BrowserTabState | undefined => {
      return this.tabManager.getActiveTab(this.tabs, this.activeTabId);
    },
    resolveTab: (tabId: string): BrowserTabState | undefined => {
      return this.tabManager.getTab(this.tabs, tabId);
    },
    isDownloadSnapshotPersistenceSuppressed: (tabId: string): boolean => {
      return this.browserDownloadNavigationStateCoordinator.shouldSkipSnapshotPersistence(tabId);
    },
    isTabNavigationProvisional: (tabId: string): boolean => {
      return this.browserRuntimeLifecyclePort.isTabNavigationProvisional(tabId);
    },
    serializeWebState: (tabId: string): Uint8Array | undefined => {
      return this.browserWebTabsController.serializeWebState(tabId);
    },
    isHomeVisible: (): boolean => {
      return this.showHomePage;
    },
    recordRestoreTraceDiagnostic: (type: string, message: string, tabId: string, faultCode: string): void => {
      this.browserSnapshotApplicationHost.recordRestoreTraceDiagnostic(type, message, tabId, faultCode);
    },
    recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
      this.browserSnapshotApplicationHost.recordRuntimeEvent(type, message, tabId);
    },
    appendRestoreTraceBreadcrumb: (tabId: string, breadcrumb: string): void => {
      this.browserSnapshotApplicationHost.appendRestoreTraceBreadcrumb(tabId, breadcrumb);
    },
    applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch): void => {
      this.browserSnapshotApplicationHost.applyTabRuntimePatch(tabId, patch);
    },
    releaseHostedRuntime: (tabId: string, reason: BrowserHostedWebNodeDisposeReason): void => {
      this.browserHostedRuntimeSurfacePort.release(tabId, reason);
    }
  };
  private browserTabHomeShell: BrowserTabHomeShell = {
    readState: () => ({
      tabs: this.tabs,
      activeTabId: this.activeTabId,
      runtimeDegradedMessage: this.runtimeDegradedMessage,
      showHomePage: this.showHomePage,
      showTabsSheet: this.showTabsSheet,
      controllerAttached: this.controllerAttached,
      bottomAddressTransientMessageContext: this.buildBottomAddressTransientMessageContext(),
      homeDataScope: this.homeDataScope,
      currentDataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
      currentPrivacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
      currentBoundaryPrivate: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      customHomepageRuntimeState: this.customHomepageRuntimeState,
      optimisticThemeMode: this.browserTabHomeCoordinator.resolveOptimisticThemeMode(),
      viewportWidth: this.rootViewportWidth,
      viewportHeight: this.rootViewportHeight,
      homeSearchFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
      homepageBackdropPrivateMode: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      homepageBackdropAppearanceState: this.homepageBackdropAppearanceState,
      homeShortcutApplicationSnapshot: this.homeShortcutApplicationSnapshot
    }),
    applyState: (application): void => {
      if (application.runtimeDegradedMessage !== undefined) {
        this.runtimeDegradedMessage = application.runtimeDegradedMessage;
      }
      if (application.resetHomeTransientUiState === true) {
        this.resetHomeTransientUiState();
      }
      if (application.tabsForOverviewPreviewSync !== undefined) {
        this.tabs = application.tabsForOverviewPreviewSync;
      }
      if (application.activeTabId !== undefined) {
        this.activeTabId = application.activeTabId;
      }
      if (application.tabSequence !== undefined) {
        this.tabSequence = application.tabSequence;
        this.tabCount = this.tabs.length;
      }
      if (application.visualState !== undefined) {
        this.applyShellVisualState(application.visualState);
      }
      if (application.helperMessage !== undefined) {
        this.helperMessage = application.helperMessage;
      }
      if (application.boundaryState !== undefined) {
        this.homeProfileId = application.boundaryState.profileId;
        this.homePrivacyMode = application.boundaryState.privacyMode;
        this.homeDataScope = application.boundaryState.dataScope;
        this.availableSearchEngines = application.boundaryState.searchEngineSelection.availableSearchEngines;
        this.selectedSearchEngine = application.boundaryState.searchEngineSelection.selectedSearchEngineId;
      }
      if (application.searchEngineSelection !== undefined) {
        this.availableSearchEngines = application.searchEngineSelection.availableSearchEngines;
        this.selectedSearchEngine = application.searchEngineSelection.selectedSearchEngineId;
      }
      if (application.errorMessage !== undefined) {
        this.errorMessage = application.errorMessage;
      }
      if (application.appearanceState !== undefined) {
        const appearance = application.appearanceState;
        this.showHomeShortcuts = appearance.showHomeShortcuts;
        this.homeShortcutLayoutDensity = appearance.homeShortcutLayoutDensity;
        this.themedHomeBackground = appearance.homeTokens.pageBackground;
        this.themedHomeSurfaceBackground = appearance.homeTokens.floatingSurface;
        this.themedHomeControlBackground = appearance.homeTokens.controlBackground;
        this.themedHomePressedBackground = appearance.homeTokens.pressedBackground;
        this.themedHomeOutlineColor = appearance.homeTokens.outline;
        this.themedHomeTextPrimaryColor = appearance.homeTokens.textPrimary;
        this.themedHomeTextSecondaryColor = appearance.homeTokens.textSecondary;
        this.themedHomeAccentColor = appearance.homeTokens.accent;
        this.themedHomeOnPrimaryColor = appearance.homeTokens.onPrimary;
        this.applyTabsOverviewThemeState(appearance.tabsOverviewThemeState);
      }
      if (application.homeWallpaperState !== undefined) {
        this.homeWallpaperState = application.homeWallpaperState;
      }
      if (application.homepageBackdropAppearanceState !== undefined) {
        this.homepageBackdropAppearanceState = application.homepageBackdropAppearanceState;
      }
      if (application.tabsOverviewThemeState !== undefined) {
        this.applyTabsOverviewThemeState(application.tabsOverviewThemeState);
      }
      if (application.incrementArkWebMediaTakeoverRevision === true) {
        this.arkWebMediaTakeoverRevision += 1;
      }
      if (application.clearNavigationState === true) {
        this.canGoBack = false;
        this.canGoForward = false;
      }
      if (application.clearControllerAttachment === true) {
        this.controllerAttached = false;
      }
      if (application.invalidateWebSessionTransition === true) {
        this.invalidateWebSessionTransition();
      }
      if (application.incrementThemeModeActionVersion === true) {
        this.themeModeActionVersion += 1;
      }
      if (application.themeModeToastMessage !== undefined) {
        this.showNativeToast(application.themeModeToastMessage);
      }
      if (application.endSearchInvocation === true) {
        BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'explicit_exit');
      }
      if (application.resetHomeSearchPresentation === true) {
        this.addressInput = '';
        this.rootBottomAddressPanelDetent = 'low';
        this.browserRootBottomPanelSessionCoordinator.resetSearchBackdropPresentation();
      }
    },
    cancelBottomPanelBackdropFocusTransition: (): void =>
      this.cancelRootBottomPanelAddressFocusBackdropTransition(),
    restoreHomeBottomPanel: (detent: 'peek' | 'low'): void =>
      this.restoreHomeBottomPanelForDirectHomeNavigation(detent),
    syncThemeAppStorage: (): void => syncBrowserThemeAppStorage(),
    syncBottomPanelStatusBarStyle: (): void => this.syncBottomPanelStatusBarStyle(),
    showToast: (message: string): void => this.showNativeToast(message),
    resolveHomeScrollActionFacts: () => ({
      input: this.buildHomeScrollChromeInput(),
      currentPresentation: this.rootBottomPanelPresentationSnapshot.scrollPresentation
    }),
    applyHomeScrollDecision: (decision): void =>
      this.browserRootBottomPanelSessionCoordinator.applyHomeScrollDecision(decision)
  };
  private browserCloseTabApplicationHost: BrowserCloseTabApplicationHost = {
    readState: (): BrowserTabCloseApplicationState => ({
      tabs: this.tabs,
      activeTabId: this.activeTabId,
      tabSequence: this.tabSequence,
      dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
      privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
      tabsOverviewVisible: this.showTabsSheet
    }),
    persistActiveTabSnapshot: (reason: string): void => {
      this.persistActiveTabSnapshotAsync(reason);
    },
    applyRestoredTabState: (
      tabs: BrowserTabState[],
      activeTabId: string
    ): void => {
      this.tabs = tabs;
      this.activeTabId = activeTabId;
    },
    requestCloseTabsOverview: (): void => {
      this.dispatchTabsOverviewSession({ type: 'request_close' });
    },
    showToast: (message: string): void => {
      this.showNativeToast(message);
    },
    restoreHomeBottomPanelForDirectHomeNavigation: (detent: 'peek' | 'low'): void => {
      this.restoreHomeBottomPanelForDirectHomeNavigation(detent);
    },
    executeTabListAnimation: (plan: BrowserCloseTabAnimationPlan): void => {
      animateTo({
        duration: plan.durationMs,
        curve: plan.curve
      }, plan.apply);
    },
    applyTabList: (tabs: BrowserTabState[]): void => {
      this.tabs = tabs;
    },
    applyActiveTabState: (activeTabId: string, tabSequence: number): void => {
      this.activeTabId = activeTabId;
      this.tabSequence = tabSequence;
    },
    notifyTabPreviewChanged: (): void => {
      this.notifyTabPreviewChanged();
    },
    setHelperMessage: (message: string): void => {
      this.helperMessage = message;
    }
  };
  private browserPrivateModeExitHost: BrowserPrivateModeExitHost = {
    applyTabsAfterPrivateModeExit: (tabs: BrowserTabState[], activeTabId: string): void => {
      this.activeTabId = activeTabId;
      this.browserTabSwitchCoordinator.commitTabs(tabs, {
        syncRuntimeGraph: true,
        persistTabs: false
      });
    },
    showRegularHomeSurface: (helperMessage: string, options: BrowserCreateTabOptions): void => {
      this.browserTabHomeCoordinator.showHomeSurface(helperMessage, options);
    },
    setTabsOverviewSection: (section: BrowserTabsOverviewSessionSection): void => {
      this.tabsOverviewSessionCoordinator.setActiveSection(section);
    }
  };
  private browserPrivateModeConfirmationHost: BrowserPrivateModeConfirmationHost = {
    enterPrivateTabInCurrentWindow: (plan: BrowserPrivateModeEntryPlan): void => {
      this.dispatchTabsOverviewSession({
        type: 'enter_private',
        helperMessage: plan.helperMessage,
        options: plan.options
      });
    },
    isLargeScreenShellActive: (): boolean =>
      this.browserShellPresentationOperations?.surface() === 'large_screen',
    showMessage: (message: string): void => this.showNativeToast(message),
    requestExitPrivateMode: (clearPrivateData: boolean): void => {
      void this.exitPrivateModeAsync(clearPrivateData);
    }
  };
  private browserWebEventCommitCoordinator: BrowserWebEventCommitCoordinator = new BrowserWebEventCommitCoordinator();
  private webEventRouter: WebEventRouter = new WebEventRouter();
  private browserWebEventHostCoordinator: BrowserWebEventHostCoordinator = new BrowserWebEventHostCoordinator();
  private browserWebHostCoordinator: BrowserWebHostCoordinator =
    new BrowserWebHostCoordinator(this.browserHostedWebDocumentStartScriptCoordinator,
      this.browserMediaDiscoveryRuntime.mediaFrameRuntimeCoordinator);
  private browserHostedWebOwnershipCoordinator: BrowserHostedWebOwnershipCoordinator =
    new BrowserHostedWebOwnershipCoordinator();
  private browserWebLoadFailureSurfaceCoordinator: BrowserWebLoadFailureSurfaceCoordinator =
    new BrowserWebLoadFailureSurfaceCoordinator();
  private browserErrorDocumentLoadShell: BrowserErrorDocumentLoadShell = {
    resolvePresentationFacts: (tabId: string): BrowserErrorDocumentPresentationFacts => {
      return {
        fallbackErrorMessage: this.errorMessage,
        runtimeDegradedMessage: this.runtimeDegradedMessage,
        bottomChromeInsetVp: this.resolveErrorDocumentBottomInsetVp(tabId),
        accentColor: this.themedHomeAccentColor,
        onAccentColor: this.themedHomeOnPrimaryColor,
        createOptions: this.tabScopedEventContextCoordinator.resolveCurrentBoundary()
      };
    },
    scheduleActiveErrorDocumentPreview: (): void => {
      this.scheduleCurrentTabPreviewAfterErrorPageCommit(120, true);
    },
    lockActiveTabsOverviewSnapshot: (): void => {
      this.tabsOverviewSessionCoordinator.lockTransitionSnapshot(this.activeTabId);
    }
  };
  private telegramWebCompatibilityService: TelegramWebCompatibilityService = new TelegramWebCompatibilityService();
  private buildBrowserWebTabsControllerDependencies(): BrowserWebTabsControllerDependencies {
    return {
      resolveWebController: (tabId: string): webview.WebviewController | undefined =>
        this.browserRuntimeLifecyclePort.resolveController(tabId),
      isWebControllerAttached: (tabId: string): boolean =>
        this.browserRuntimeLifecyclePort.hasAttachedController(tabId, this.controllerAttached),
      isNormalRuntimeAttached: (tabId: string): boolean => this.browserRuntimeLifecyclePort.hasRuntime(tabId),
      isHostedWebNodeAttached: (tabId: string): boolean =>
        this.browserHostedRuntimeSurfacePort.isHostedNodeAttached(tabId),
      isArkWebControllerAttached: (tabId: string): boolean =>
        this.browserHostedRuntimeSurfacePort.isHostedControllerAttached(tabId),
      resolveWebId: (tabId: string): number => this.browserRuntimeLifecyclePort.resolveWebId(tabId),
      handleJavaScriptDialogBack: (tabId: string, kind: BrowserWebDialogQueueKind): boolean =>
        this.browserWebCapabilityPromptApplicationCoordinator.handleJavaScriptDialogBack(tabId, kind),
      handleHttpAuthDialogBack: (_tabId: string): boolean =>
        this.browserWebCapabilityPromptApplicationCoordinator.cancelHttpAuthFromBack(),
      handleSslErrorDialogBack: (tabId: string): boolean =>
        this.browserWebCapabilityPromptApplicationCoordinator.cancelSslErrorWarningFromBack(tabId),
      handleSpecialNavigationAction: (
        tabId: string,
        url: string,
        source: BrowserWebComponentNavigationEventSource,
        isMainFrame: boolean
      ): BrowserWebComponentWebUrlDecision => {
        return this.browserWebSpecialNavigationActionCoordinator.handleNavigationAction({
          tabId: tabId,
          targetUrl: url,
          source: source,
          isMainFrame: isMainFrame
        });
      },
      canLoadUrlInWebView: (url: string): boolean => this.webRuntimeBridge.canLoadInWebView(url),
      handleWebAppScopeOutNavigation: (_tabId: string, _url: string, _isMainFrame: boolean): boolean => false,
      resolveMainFrameWebUrlDecision: (
        tabId: string,
        url: string,
        request: WebResourceRequest | undefined,
        source: BrowserWebComponentNavigationEventSource
      ): BrowserWebComponentWebUrlDecision => {
        return this.browserWebNavigationInterceptionCoordinator.resolveMainFrameWebUrlDecision({
          tabId: tabId,
          targetUrl: url,
          request: request,
          source: source
        }, this.browserWebNavigationInterceptionHost);
      },
      executeSameWebNavigationRewrite: (tabId: string, url: string, reason: string): boolean =>
        this.browserWebNavigationInterceptionCoordinator.executeSameWebNavigationRewrite(tabId, url, reason),
      prepareMainFrameWebNavigation: (tabId: string, url: string, startsNewTransaction: boolean): boolean =>
        this.browserWebLoadRuntimeCoordinator.prepareWebMainFrameNavigation(tabId, url, startsNewTransaction),
      observeMainFrameWebRequest: (tabId: string, url: string): void =>
        this.webEventRouter.observeMainFrameRequest(tabId, url),
      evaluateUnifiedLinkNavigation: (request: BrowserWebComponentLinkRequest): BrowserUnifiedLinkResult => {
        return this.browserUnifiedLinkNavigationCoordinator.evaluate({
          tabId: request.tabId,
          url: request.url,
          source: request.source,
          isMainFrame: request.isMainFrame,
          isRequestGesture: request.isRequestGesture
      }, this.browserUnifiedLinkNavigationHost);
      },
      applyUnifiedLinkNavigationResult: (result: BrowserUnifiedLinkResult): void => {
        this.browserUnifiedLinkNavigationCoordinator.applyEvaluatedResult(result);
      },
      applyWebPageCommittedUrlRestore: (tabId: string, url: string): void =>
        this.browserWebNavigationStateSyncCoordinator.applyCommittedUrlRestore(tabId, url),
      applyWebHistoryTargetUrlPreview: (
        tabId: string,
        direction: BrowserWebHistoryDirection,
        targetUrl: string
      ): void => {
        this.browserWebNavigationStateSyncCoordinator.applyHistoryTargetUrlPreview(tabId, direction, targetUrl);
      },
      beginHistoryReturnQuietWindow: (tabId: string, _direction: BrowserWebHistoryDirection): void => {
        if (tabId !== this.activeTabId) {
          return;
        }
        this.browserWebScrollInteractionCoordinator.beginHistoryReturnQuietWindow();
      },
      prepareHistoryNavigation: (
        tabId: string,
        direction: BrowserWebHistoryDirection,
        targetUrl: string,
        targetHistoryIndex: number
      ): boolean => this.browserWebLoadRuntimeCoordinator.prepareHistoryNavigation(
        tabId,
        targetUrl,
        targetHistoryIndex,
        direction
      ),
      cancelPreparedNavigation: (tabId: string): void =>
        this.browserWebLoadRuntimeCoordinator.cancelUserAgentNavigation(tabId),
      syncWebNavigationStateSoon: (): void => this.browserWebNavigationStateSyncCoordinator.syncSoon(),
      handleWebpageTranslationRefreshOrHistory: (tabId: string, url: string): void =>
        this.webpageTranslationCoordinator.handleRefreshOrBackForwardForRuntimeTab(tabId, this.activeTabId, url),
      handleActiveTabChanged: (change: BrowserWebActiveTabChange): void =>
        this.browserWebPageLifecycleApplicationCoordinator.handleActiveTabChanged(change)
    };
  }

  private browserWebTabsControllerHost: BrowserWebTabsControllerHost = {
    recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
      this.recordRuntimeEvent(type, message, tabId);
    },
    applyWebPageNavigationState: (tabId: string, canGoBackward: boolean, canGoForward: boolean): void => {
      if (!this.shouldHandleActiveWebTab(tabId)) {
        return;
      }
      this.canGoBack = canGoBackward;
      this.canGoForward = canGoForward;
    },
    applyWebNavigationHelperMessage: (message: string): void => {
      this.helperMessage = message;
    },
    applyWebNavigationErrorMessage: (message: string): void => {
      this.errorMessage = message;
    },
    clearWebNavigationErrorMessage: (): void => {
      this.errorMessage = '';
    },
    resolveActiveWebTabId: (): string => {
      return this.activeTabId;
    },
    resolveWebTabSnapshot: (tabId: string): BrowserWebTabsControllerTabSnapshot | undefined => {
      return this.resolveWebTabSnapshot(tabId);
    },
    isWebSurfaceVisible: (): boolean => {
      return this.isWebPageVisible();
    }
  };
  private browserMainBackHost: BrowserMainBackHost = {
    resolveShellBackState: (): BrowserShellBackState => {
      return this.buildBrowserShellBackState();
    },
    confirmCloseReaderMode: (): void => {
      this.readerModeApplication.requestExitConfirmation();
    },
    resolveBottomAddressPanelBackRequest: (): BrowserBottomAddressPanelBackRequest => {
      const request: BrowserBottomAddressPanelBackRequest = {
        visible: this.isRootBottomPanelBackHandlingVisible(),
        addressFocused: this.resolveRootBottomPanelAddressFocused(),
        panelDetent: this.resolveRootBottomPanelDetent()
      };
      return request;
    },
    endSearchInvocation: (): void => {
      BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'explicit_exit');
    },
    collapseRootBottomPanel: (): void => {
      this.requestRootBottomPanelCollapse();
    },
    resolveSystemBackRequest: (now: number): BrowserSystemBackRequest => {
      const request: BrowserSystemBackRequest = {
        showHomePage: this.showHomePage,
        webPageVisible: this.isWebPageVisible(),
        webAppMode: this.webAppSessionSnapshot.activeContext !== undefined,
        lastExitPromptAt: this.lastSystemBackExitPromptAt,
        now: now
      };
      return request;
    },
    handleWebAppTerminalBack: (reason: string): boolean => {
      return this.webAppExitCoordinator.requestTerminalBackExit({
        windowId: this.currentWindowId,
        activeTab: this.tabManager.getTab(this.tabs, this.activeTabId),
        currentUrl: this.currentUrl,
        reason: reason
      }, this.webAppExitHost).consumed;
    },
    promptExit: (now: number): void => {
      this.lastSystemBackExitPromptAt = now;
      this.showNativeToast('再按一次返回关闭应用');
    }
  };
  private browserWebLoadRuntimeDependencies: BrowserWebLoadRuntimeDependencies = {
    runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
    runtimeMutationPort: this.browserRuntimeMutationPort,
    visibleUrlService: this.telegramWebCompatibilityService,
    webEventRouter: this.webEventRouter,
    tabManager: this.tabManager,
    downloadNavigationStateCoordinator: this.browserDownloadNavigationStateCoordinator,
    commitTabs: (tabs: BrowserTabState[], options: TabMutationCommitOptions): void => {
      this.browserTabSwitchCoordinator.commitTabs(tabs, options);
    },
    syncActiveRuntime: (): void => this.browserActiveRuntimeSyncCoordinator.syncActiveRuntime(),
    syncCustomHomepageVisibility: (): void => this.customHomepageRuntimeCoordinator.syncVisibility(),
    resolveOfflineFastFailureCoordinator: () => this.browserOfflineFastFailureCoordinator,
    resolveLifecycleApplication: () => this.browserWebPageLifecycleApplicationCoordinator,
    resolveDocumentViewerService: () => this.documentViewerService,
    resolveRecoveryManager: () => this.webRecoveryManager,
    resolveUserAgentService: () => this.browserUserAgentService,
    resolveBrowsingIdentityPolicyCoordinator: () => this.browserBrowsingIdentityPolicyCoordinator,
    resolveUserAgentRuntimeService: () => this.browserUserAgentRuntimeService,
    scheduleOpenResolvedUrlWork: (work: () => void) =>
      this.browserRootBottomPanelSessionCoordinator.scheduleNavigationWorkAfterPresentation(work)
  };
  private browserWebLoadRuntimeHostBindings: BrowserWebLoadRuntimeHostBindings = {
    readFacts: (): BrowserWebLoadRuntimeFacts => ({
      tabs: this.tabs,
      activeTabId: this.activeTabId,
      currentUrl: this.currentUrl,
      controllerAttached: this.controllerAttached,
      currentProfileId: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().profileId
    }),
    applyControllerState: (
      controller: webview.WebviewController | undefined,
      controllerAttached: boolean
    ): void => {
      if (controller !== undefined) {
        this.webController = controller;
      }
      this.controllerAttached = controllerAttached;
    },
    applyOpenResolvedUrlState: (state: BrowserWebLoadOpenResolvedUrlState): void => {
      if (state.revealWebSurface) {
        this.showHomePage = false;
        return;
      }
      this.resetHomeTransientUiState();
      this.errorMessage = '';
      this.runtimeDegradedMessage = '';
      this.helperMessage = state.helperMessage;
      this.currentUrl = state.targetUrl;
      this.pendingWebUrl = state.targetUrl;
      this.currentTitle = state.title;
      this.browserRootBottomPanelSessionCoordinator.scheduleHomeToWebBottomPanelTransitionCompletion();
    },
    invalidateWebSessionTransition: (): void => {
      this.invalidateWebSessionTransition();
    },
    showRuntimeToast: (message: string): void => this.showNativeToast(message)
  };
  private browserWebLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator =
    new BrowserWebLoadRuntimeCoordinator(
      this.browserWebLoadRuntimeDependencies,
      this.browserWebLoadRuntimeHostBindings
    );
  private browserPageFindCoordinator: BrowserPageFindCoordinator = new BrowserPageFindCoordinator({
    resolveController: (tabId: string) => this.browserRuntimeLifecyclePort.resolveController(tabId),
    isControllerAttached: (tabId: string): boolean =>
      this.browserHostedRuntimeSurfacePort.isHostedControllerAttached(tabId),
    publishBarState: (tabId: string, state: BrowserPageFindBarState): void => {
      if (tabId === this.activeTabId) {
        this.pageFindBarState = state;
        this.browserHostedRuntimeSurfacePort.updateCurrentActiveConfigFromHost();
      }
    },
    showStatusMessage: (message: string): void => this.showNativeToast(message)
  });
  private browserClipboardService: BrowserClipboardService = new BrowserClipboardService();
  private elementInspectionSessionShell: ElementInspectionSessionShell = {
    resolveFacts: (): ElementInspectionSessionFacts => {
      return {
        activeTabId: this.activeTabId,
        showHomePage: this.showHomePage,
        showTabsSheet: this.showTabsSheet,
        webPageVisible: this.isWebPageVisible() && !this.shouldSuspendHostedWebSurface(),
        highlightColor: this.themedHomeAccentColor
      };
    },
    publishPresentation: (presentation: ElementInspectionPresentation): void => {
      this.elementInspectionPresentation = presentation;
    },
    showToast: (message: string): void => {
      this.showNativeToast(message);
    }
  };
  private elementInspectionSessionCoordinator: ElementInspectionSessionCoordinator =
    new ElementInspectionSessionCoordinator(
      this.browserRuntimeLifecyclePort,
      this.browserTransientSurfaceCoordinator,
      this.browserClipboardService,
      this.elementInspectionSessionShell
    );
  private webPageShareService: WebPageShareService = new WebPageShareService();
  private phonePagePushCoordinator: BrowserPhonePagePushCoordinator =
    new BrowserPhonePagePushCoordinator(this.featureGateCoordinator, sharedAiraSyncConfigStore);
  private systemSettingsLaunchService: SystemSettingsLaunchService = new SystemSettingsLaunchService();
  private clientUpdatePolicyUnsubscribe?: () => void;
  private appReviewPromptShell: AppReviewPromptShell = {
    resolveFacts: (): AppReviewPromptShellFacts => {
      return {
        context: this.getAbilityContext(),
        homeVisible: this.showHomePage,
        privateMode: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
        appVisible: this.isBrowserShellVisible,
        promptBlockingFacts: this.buildTransientPromptBlockingFacts()
      };
    },
    showToast: (message: string): void => this.showNativeToast(message)
  };
  private appReviewPromptCoordinator: AppReviewPromptCoordinator = new AppReviewPromptCoordinator(
    sharedAppReviewPromptRepository,
    this.systemSettingsLaunchService,
    this.browserTransientSurfaceCoordinator,
    this.appReviewPromptShell
  );
  private offlinePageSaveShell: OfflinePageSaveCoordinatorShell = {
    readContext: (requestedTabId: string): OfflinePageSaveShellContext => {
      const targetTabId = requestedTabId.length > 0 ? requestedTabId : this.activeTabId;
      const targetTab = this.tabManager.getTab(this.tabs, targetTabId);
      const target = this.resolveWebPageActionTargetForTab(targetTabId);
      const activeTitle = targetTabId === this.activeTabId ? this.currentTitle.trim() : '';
      const useErrorDocumentSnapshot = targetTabId === this.activeTabId &&
        this.browserWebLoadFailureSurfaceCoordinator.shouldShow(targetTabId);
      return {
        targetTab: targetTab,
        targetControllerAttached: targetTabId === this.activeTabId && this.controllerAttached,
        currentUrl: target.networkUrlAvailable ? target.url : '',
        currentTitle: activeTitle.length > 0 ? activeTitle : (targetTab?.title.trim() ?? ''),
        useErrorDocumentSnapshot: useErrorDocumentSnapshot,
        errorDocumentPresentation: useErrorDocumentSnapshot
          ? this.browserWebPageLifecycleApplicationCoordinator.buildActiveLoadErrorPresentation()
          : undefined,
        errorDocumentTargetUrlCandidates: [this.pendingWebUrl, this.currentUrl, this.addressInput],
        promptFavicon: targetTabId.length > 0
          ? this.browserTabPreviewCoordinator.getPreviewState(targetTabId)?.favicon
          : undefined
      };
    },
    publishSessionSnapshot: (snapshot: OfflinePageSaveSessionSnapshot): void => {
      this.offlinePageSaveSessionSnapshot = snapshot;
    },
    showToast: (message: string): void => this.showNativeToast(message),
    reportError: (message: string): void => {
      this.errorMessage = message;
    }
  };
  private offlinePageSaveCoordinator: OfflinePageSaveCoordinator = new OfflinePageSaveCoordinator({
    membershipFeature: sharedMembershipFeature,
    featureGateCoordinator: this.featureGateCoordinator,
    shell: this.offlinePageSaveShell,
    repository: sharedOfflinePageRepository,
    activityTracker: sharedActivityTracker,
    runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
    resolveHostedRuntimeSurfacePort: (): BrowserHostedRuntimeSurfacePort => this.browserHostedRuntimeSurfacePort,
    promptHideDelayMs: OFFLINE_SAVE_ACTION_PROMPT_HIDE_DELAY_MS
  });
  private browserOfflineFastFailureCoordinator: BrowserOfflineFastFailureCoordinator =
    new BrowserOfflineFastFailureCoordinator({
      tabManager: this.tabManager,
      loadFailureSurfaceCoordinator: this.browserWebLoadFailureSurfaceCoordinator,
      resolveApplication: () => this.browserWebPageLifecycleApplicationCoordinator
    }, {
      readFacts: (): BrowserOfflineFastFailureFacts => ({
        tabs: this.tabs,
        activeTabId: this.activeTabId,
        pendingWebUrl: this.pendingWebUrl,
        homeSurfaceVisible: this.showHomePage,
        loading: this.isLoading
      })
    }, WEB_OFFLINE_FAST_FAIL_DELAY_MS);
  private documentViewerService: DocumentViewerService = new DocumentViewerService();
  private browserHostedRuntimeSurfacePortHost: BrowserHostedRuntimeSurfacePortHost = {
    applyActiveHostedSurfaceState: (tabId: string, renderKey: string): void => {
      this.activeHostedWebNodeTabId = tabId;
      this.activeHostedWebNodeRenderKey = renderKey;
    },
    applyControllerAttachedState: (attached: boolean): void => {
      this.controllerAttached = attached;
    },
    applyHostedHiddenSlots: (hiddenSlots: BrowserHostedWebHiddenSlot[]): void => {
      this.hostedWebHiddenSlots = hiddenSlots;
    },
    getActiveTabId: (): string => this.activeTabId,
    resolveActiveTab: (): BrowserTabState | undefined => this.tabManager.getActiveTab(this.tabs, this.activeTabId),
    getCurrentWindowId: (): string => this.currentWindowId,
    createUserScriptNativeBridge: (tabId: string, controller: webview.WebviewController): Object =>
      this.userScriptRuntimeCoordinator.createNativeBridge(
        controller,
        tabId,
        (): string => this.resolveTabBridgeUrlById(tabId)
      ),
    shouldSuspendActiveWebSurface: (): boolean => this.shouldSuspendHostedWebSurface(),
    isHomeVisible: (): boolean => this.showHomePage,
    isTabsVisible: (): boolean => this.showTabsSheet,
    handleActiveRuntimeDetached: (): void => {
      this.webpageTranslationCoordinator.handleActiveRuntimeDetached();
    },
    handleWebpageTranslationActiveSurfaceDetached: (tabId: string): void => {
      this.webpageTranslationCoordinator.handleRuntimeDetachedForRuntimeTab(tabId, this.activeTabId);
    },
    applyBackgroundRuntimeTabState: (tabId: string, runtimeState: TabRuntimeState): void => {
      this.browserTabSwitchCoordinator.applyTabPatch(tabId, {
        runtimeState: runtimeState
      }, {
        persistTabs: true,
        refreshRuntimeTabIds: []
      });
    },
    recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
      this.recordRuntimeEvent(type, message, tabId);
    },
    attachForegroundHostedRuntime: (): void => {
      this.browserActiveRuntimeSyncCoordinator.syncActiveRuntimeAfterSwitch();
    },
    buildActiveSurfaceConfig: (activeTab?: BrowserTabState): BrowserHostedRuntimeActiveSurfaceConfig => {
      return {
        uiContext: this.getUIContext(),
        appearancePolicy: this.buildWebAppearancePolicyForTab(activeTab),
        forceEnableWebZoom: this.browserLargeScreenWebZoomCoordinator.resolveForceEnableWebZoom(
          this.webScrollExperimentSettings.forceEnableWebZoom,
          this.browserShellPresentationOperations?.surface() === 'large_screen'
        ),
        textZoomRatio: this.resolveEffectiveWebTextZoomRatio(),
        pullRefreshNestedScrollEnabled: this.browserPullRefreshCoordinator.isEnabledForActiveSurface(activeTab),
        callbacks: this.buildHostedWebNodeCallbacks()
      };
    },
    buildPreviewSurfaceConfig: (
      tab: BrowserTabState,
      runtime: WebTabRuntimeRecord
    ): BrowserHostedRuntimePreviewSurfaceConfig => {
      return {
        uiContext: this.getUIContext(),
        appearancePolicy: this.buildWebAppearancePolicyForTab(tab),
        forceEnableWebZoom: this.browserLargeScreenWebZoomCoordinator.resolveForceEnableWebZoom(
          this.webScrollExperimentSettings.forceEnableWebZoom,
          this.browserShellPresentationOperations?.surface() === 'large_screen'
        ),
        textZoomRatio: this.resolveEffectiveWebTextZoomRatio(),
        userScriptNativeBridge: this.userScriptRuntimeCoordinator.createNativeBridge(
          runtime.controller,
          tab.id,
          (): string => this.resolveTabBridgeUrlById(tab.id)
        ),
        callbacks: this.buildHostedWebNodeCallbacks()
      };
    }
  };
  private browserHostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort =
    new BrowserHostedRuntimeSurfacePort(
      this.browserWebHostCoordinator,
      this.browserHostedWebOwnershipCoordinator,
      this.browserRuntimeLifecyclePort,
      this.browserTabRuntimeLifecycleService,
      this.browserPageFindCoordinator,
      this.browserBackgroundTabPreviewRuntimeCoordinator,
      this.browserHostedRuntimeSurfacePortHost
    );
  private webControllerBootstrapper: WebControllerBootstrapper = new WebControllerBootstrapper();
  private browserTabBackgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator =
    new BrowserTabBackgroundSessionSyncCoordinator(
      this.browserRuntimeLifecyclePort,
      this.browserTabPreviewAssetBoundaryCoordinator,
      this.browserBackgroundTabPreviewRuntimeCoordinator,
      this.browserHostedRuntimeSurfacePort,
      {
        persistTabs: (): void => {
          this.browserTabSessionPersistenceCoordinator.persist();
        },
        getActiveDownloadCountSnapshot: (): number => {
          const counts = this.downloadService.getStatusCountsSnapshot(this.getCurrentDownloadBoundary());
          return counts.active + counts.pending;
        },
        getPreviewStates: (): BrowserTabPreviewState[] => {
          return this.getTabPreviewStates();
        },
        pruneRuntimeTelemetry: (_tabIds: string[]): void => {}
      },
      this.browserTabBackgroundSessionSyncCoordinatorHost
    );
  private tabsOverviewSnapshotPipelineCoordinator: BrowserTabsOverviewSnapshotPipelineCoordinator =
    new BrowserTabsOverviewSnapshotPipelineCoordinator({
      previewCoordinator: this.browserTabPreviewCoordinator,
      readState: (): BrowserTabsOverviewSnapshotPipelineState => this.tabsOverviewSnapshotPipelineState,
      updateState: (state: BrowserTabsOverviewSnapshotPipelineState): void => {
        this.tabsOverviewSnapshotPipelineState = state;
      },
      releasePixelMap: (pixelMap: image.PixelMap): void => {
        void pixelMap.release().catch((_error: Error) => {});
      },
      notifyChanged: (): void => {
        this.notifyTabPreviewChanged();
      },
      onCapturedEntryReady: (tabId: string, generation: number): void => {
        this.dispatchTabsOverviewSession({
          type: 'captured_entry_ready',
          tabId: tabId,
          generation: generation
        });
      },
      recordFailure: (eventType: string, error: Error, tabId: string): void => {
        this.recordRuntimeEvent(eventType, this.stringifyError(error), tabId);
      }
    });
  private browserSearchSuggestionShell: BrowserSearchSuggestionShell = {
    resolveFacts: (): BrowserSearchSuggestionRuntimeFacts => {
      const boundary = this.tabScopedEventContextCoordinator.resolveCurrentBoundary();
      return {
        query: this.browserRootBottomPanelSessionCoordinator.resolveSuggestionQuery(
          this.buildBottomAddressSuggestionInput()
        ),
        addressFocused: this.resolveRootBottomPanelAddressFocused(),
        tabs: this.tabs,
        activeTabId: this.activeTabId,
        currentPageSuggestionEnabled: this.isWebPageVisible(),
        profileId: boundary.profileId,
        privacyMode: boundary.privacyMode,
        dataScope: boundary.dataScope,
        preferences: sharedPreferencesRepository.getPreferences().searchSuggestions
      };
    },
    publishSnapshot: (snapshot: BrowserSearchSuggestionSnapshot): void => {
      this.browserSearchSuggestionSnapshot = snapshot;
      this.syncRootAddressKeyboardOverlayInset();
    },
    protectAddressKeyboardSession: (): void => {
      this.protectRootAddressKeyboardSessionFromTransientHide();
    },
    openAddressSuggestion: (target: string): void => {
      void this.openSubmittedAddress(target);
    }
  };
  private browserSearchSuggestionCoordinator: BrowserSearchSuggestionCoordinator =
    new BrowserSearchSuggestionCoordinator(
      this.browserSearchSuggestionShell,
      sharedSearchQueryHistoryService,
      this.browserTabSwitchCoordinator
    );
  private browserWindowAvoidAreaCoordinator: BrowserWindowAvoidAreaCoordinator = new BrowserWindowAvoidAreaCoordinator();
  private browserFullscreenInsetRestoreHost: BrowserWindowFullscreenInsetRestoreHost = {
    resolveWindow: (): Promise<window.Window> => window.getLastWindow(this.getAbilityContext()),
    resolveStorage: (): LocalStorage | undefined => this.getSharedStageStorage(),
    applyRestoredInsets: (_insets: BrowserWindowAvoidAreaInsets): void => {
      this.webViewportVisualTopInset = this.resolveTargetWebViewportVisualTopInsetPx();
      this.webViewportVisualTopInsetInitialized = true;
      this.refreshWebViewportPresentation(this.webViewportVisualTopInset);
    }
  };
  private browserWebTopImmersionSessionHost: BrowserWebTopImmersionSessionHost = {
    resolveVisibleTopInsetPx: (): number => this.getWebTopChromeStableInsetPx(),
    applyPresentation: (visible: boolean, targetTopInsetPx: number, _source: string): void => {
      if (!this.webViewportVisualTopInsetInitialized) {
        this.webViewportVisualTopInset = this.getWebViewportVisualTopInsetPx();
        this.webViewportVisualTopInsetInitialized = true;
      }
      this.webStatusBarVisible = visible;
      this.webViewportVisualTopInset = targetTopInsetPx;
      this.refreshWebViewportPresentation(targetTopInsetPx);
    },
    applyWindowVisibility: (
      visible: boolean,
      source: string,
      shouldApply: () => boolean
    ): Promise<boolean> => {
      return this.browserStatusBarStyleService.applyVisibility(
        this.getAbilityContext(), visible, source, shouldApply
      );
    },
    scheduleSafeInsetSettle: (source: string): void => {
      this.scheduleWebSafeInsetSettleSync(`${source}-status-bar-settle`);
    }
  };
  private browserWebTopImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator =
    new BrowserWebTopImmersionSessionCoordinator({
      resolveFacts: (): BrowserWebTopImmersionFacts => ({
        activeTabId: this.activeTabId,
        browserShellVisible: this.isBrowserShellVisible,
        webPageVisible: this.isWebPageVisible(),
        homePageVisible: this.showHomePage,
        tabsSheetVisible: this.showTabsSheet,
        scrollTopImmersionEnabled: this.webScrollGlobalImmersionEnabled &&
          !this.isLargeScreenShellFamilyActive(),
        alwaysTopImmersionEnabled: this.webScrollAlwaysTopImmersionEnabled &&
          !this.isLargeScreenShellFamilyActive(),
        fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled,
        webAppTopSafeAreaHidden: this.shouldHideWebAppTopSafeArea(),
        assistantVideoTakeoverActive: this.isAssistantVideoTakeoverActive(),
        scrollOffsetY: this.browserWebScrollInteractionCoordinator.getLastScrollY(),
        addressFocused: this.webBottomAddressFocused,
        bottomPanelInteractive: this.rootBottomAddressPanelDetent !== 'peek' &&
          !this.browserRootBottomPanelSessionCoordinator.isScrollPresentationActive(),
        statusBarVisible: this.webStatusBarVisible
      }),
      host: this.browserWebTopImmersionSessionHost
    });
  private downloadService: DownloadRuntimeService = sharedDownloadRuntimeService;
  private browserUserScriptApplicationCoordinator: BrowserUserScriptApplicationCoordinator =
    new BrowserUserScriptApplicationCoordinator({
      runtimeCoordinator: this.userScriptRuntimeCoordinator,
      transientSurfaceCoordinator: this.browserTransientSurfaceCoordinator,
      routeCoordinator: this.browserShellRouteCoordinator,
      pageActionsRevealDelayMs: USER_SCRIPT_PAGE_ACTIONS_OVERLAY_OPEN_DELAY_MS,
      pageActionsDismissDurationMs: USER_SCRIPT_PAGE_ACTIONS_OVERLAY_ANIMATION_DURATION_MS,
      captureFacts: (): BrowserUserScriptApplicationFacts => {
        const activeTab = this.tabManager.getTab(this.tabs, this.activeTabId);
        return {
          activeTabId: this.activeTabId,
          currentUrl: this.tabScopedEventContextCoordinator.resolvePageUrl(this.activeTabId),
          privateMode: this.browserPrivateProfileLifecycleCoordinator.isSessionEphemeralTabState(activeTab),
          installDataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
          installPrivacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
          presentationMode: this.browserShellPresentationOperations?.surface() === 'large_screen'
            ? 'large_screen'
            : 'phone'
        };
      },
      publishSnapshot: (snapshot: BrowserUserScriptApplicationSnapshot): void => {
        this.browserUserScriptApplicationSnapshot = snapshot;
      },
      executeEffect: (effect: BrowserUserScriptApplicationEffect): void => {
        if (effect.type === 'set_helper_message') {
          this.helperMessage = effect.message;
        } else {
          this.errorMessage = effect.message;
        }
      }
    });
  private homeShortcutToggleService: HomeShortcutToggleService = new HomeShortcutToggleService(sharedShortcutRepository);
  private webAppInstallShell: WebAppInstallShell = {
    captureSnapshot: (): WebAppInstallShellSnapshot => {
      const url = this.resolveCurrentWebPageActionUrl();
      return {
        context: this.getAbilityContext(),
        entitlementContext: {
          dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
          privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
          loggedIn: true
        },
        tabId: this.activeTabId,
        url: url,
        title: this.currentTitle.length > 0 ? this.currentTitle : url,
        favicon: this.browserTabPreviewCoordinator.getPreviewState(this.activeTabId)?.favicon
      };
    },
    publishDialogSnapshot: (snapshot: WebAppInstallDialogSnapshot): void => {
      this.webAppInstallDialogSnapshot = snapshot;
    },
    openDialog: (): void => {
      this.desktopShortcutNameDialogController.open();
    },
    showToast: (message: string): void => this.showNativeToast(message)
  };
  private webAppInstallCoordinator: WebAppInstallCoordinator = new WebAppInstallCoordinator(
    sharedMembershipFeature,
    this.featureGateCoordinator,
    this.browserRuntimeLifecyclePort,
    this.webAppInstallShell
  );
  private webAppSessionCoordinator: WebAppSessionCoordinator = sharedWebAppSessionCoordinator;
  private webAppCurrentUrlService: WebAppCurrentUrlService = new WebAppCurrentUrlService();
  private webAppExitCoordinator: WebAppExitCoordinator = new WebAppExitCoordinator();
  private webAppExitHost: WebAppExitHost = {
    applySessionSnapshot: (snapshot: WebAppSessionSnapshot, source: string): void =>
      this.applyWebAppSessionSnapshot(snapshot, source),
    terminateSelf: (): Promise<void> => this.getAbilityContext().terminateSelf()
  };
  private browserWindowContextShell: BrowserWindowContextShell = {
    resolveFacts: (): BrowserWindowContextFacts => {
      return {
        storage: this.getSharedStageStorage(),
        currentWindowId: this.currentWindowId,
        homeProfileId: this.homeProfileId,
        homePrivacyMode: this.homePrivacyMode,
        homeDataScope: this.homeDataScope,
        windowScopeId: this.getWindowScopeId(),
        tabs: this.tabs,
        activeTabId: this.activeTabId,
        tabSequence: this.tabSequence,
        showHomePage: this.showHomePage,
        isRestoringTabs: this.isRestoringTabs,
        isBrowserShellVisible: this.isBrowserShellVisible
      };
    },
    persistActiveTabSnapshot: (): void => {
      this.persistActiveTabSnapshot('context-switch');
    },
    applySuspendedWindowPresentation: (_reason: string): void => {
      this.tabs = [];
      this.activeTabId = '';
      this.currentUrl = '';
      this.currentTitle = '';
      this.addressInput = '';
      this.tabSequence = 1;
      this.runtimeDegradedMessage = '';
      this.isRestoringTabs = true;
    },
    applyWindowPresentation: (
      windowId: string,
      webAppSessionSnapshot: WebAppSessionSnapshot,
      reason: string
    ): void => {
      this.currentWindowId = windowId;
      this.applyWebAppSessionSnapshot(webAppSessionSnapshot, reason);
    },
    applyRestoredWindowPresentation: (context: BrowserWindowSuspendedContext, _reason: string): void => {
      this.tabs = context.tabs.slice();
      this.activeTabId = context.activeTabId;
      this.tabSequence = context.tabSequence;
      this.showHomePage = context.showHomePage;
      this.tabCount = this.tabs.length;
      this.syncTabPreviewCacheWithTabs();
      this.isRestoringTabs = false;
    },
    restoreTabsForCurrentWindow: (_reason: string): void => {
      this.isRestoringTabs = true;
      this.restoreSavedTabs();
    },
    connectSearchInvocationSurface: (): void => {
      this.connectBrowserSearchInvocationSurfaceIfReady();
    }
  };
  @State webAppSessionSnapshot: WebAppSessionSnapshot =
    sharedWebAppSessionCoordinator.snapshot(MAIN_WINDOW_ID);
  private externalNavigationPolicyService: ExternalNavigationPolicyService = new ExternalNavigationPolicyService();
  private browserExternalNavigationRuntimeStateCoordinator: BrowserExternalNavigationRuntimeStateCoordinator =
    new BrowserExternalNavigationRuntimeStateCoordinator();
  private browserUnifiedLinkApplicationShell: BrowserUnifiedLinkApplicationShell = {
    readPromptPresentationContext: (tabId: string): ExternalNavigationPromptPresentationContext => ({
      sourcePageUrl: this.tabScopedEventContextCoordinator.resolvePageUrl(tabId),
      favicon: this.browserTabPreviewCoordinator.getPreviewState(tabId)?.favicon
    }),
    publishPromptState: (state: ExternalNavigationPromptState): void => {
      this.externalNavigationPromptState = state;
    },
    openExternalLink: (url: string) => this.externalNavigationPolicyService.openExternalLink(
      this.getAbilityContext(),
      url
    ),
    setExternalNavigationHelperMessage: (message: string): void => {
      this.helperMessage = message;
    },
    setExternalNavigationErrorMessage: (message: string): void => {
      this.errorMessage = message;
    },
    showToast: (message: string): void => this.showNativeToast(message)
  };
  private browserUnifiedLinkApplicationCoordinator: BrowserUnifiedLinkApplicationCoordinator =
    new BrowserUnifiedLinkApplicationCoordinator({
      externalNavigationPolicyService: this.externalNavigationPolicyService,
      externalNavigationRuntimeStateCoordinator: this.browserExternalNavigationRuntimeStateCoordinator,
      faultClassifier: this.browserFaultClassifier,
      preferencesRepository: sharedPreferencesRepository,
      tabScopedEventContextCoordinator: this.tabScopedEventContextCoordinator,
      recentActionManager: this.browserRecentActionManager
    }, this.browserUnifiedLinkApplicationShell);
  private novelReaderSession: BrowserWindowSessionNovelReaderPort = new BrowserWindowSessionNovelReaderPort();
  private browserTopFloatingPromptActionShell: BrowserTopFloatingPromptActionShell = {
    readGestureOnboardingState: (): BrowserGestureOnboardingTopPromptState =>
      this.gestureOnboardingPromptState,
    readGestureOnboardingEligibilityInput: () => ({
      shellFamily: this.browserShellPresentationOperations?.snapshot()?.shellFamily ?? 'phone',
      appVisible: this.isBrowserShellVisible,
      privateMode: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      blockingSurfaceVisible: this.browserTransientSurfaceCoordinator.isGestureOnboardingPromptBlocked(
        this.buildTransientPromptBlockingFacts()
      ),
      topOffsetVp: this.browserTopFloatingPromptCoordinator.resolveBackgroundOpenTopOffsetVp({
        showHomePage: this.showHomePage,
        topInsetVp: this.browserWindowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage()).topInsetVp,
        webTopChromeOverlayHeightVp: 0
      })
    }),
    publishGestureOnboardingState: (state: BrowserGestureOnboardingTopPromptState): void => {
      this.gestureOnboardingPromptState = state;
    },
    dismissUrlThreatNotice: (): void => this.browserUrlThreatProtectionCoordinator.dismissNotice()
  };
  private browserTopFloatingPromptCoordinator: BrowserTopFloatingPromptCoordinator =
    new BrowserTopFloatingPromptCoordinator({
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      backgroundOpenPromptCoordinator: this.browserBackgroundOpenPromptCoordinator,
      offlinePageSaveCoordinator: this.offlinePageSaveCoordinator,
      routeCoordinator: this.browserShellRouteCoordinator,
      unifiedLinkApplicationCoordinator: this.browserUnifiedLinkApplicationCoordinator,
      webpageTranslationCoordinator: this.webpageTranslationCoordinator,
      userScriptApplicationCoordinator: this.browserUserScriptApplicationCoordinator,
      gestureOnboardingPromptCoordinator: sharedBrowserGestureOnboardingPromptCoordinator,
      novelReaderSession: this.novelReaderSession
    }, this.browserTopFloatingPromptActionShell);
  private browserWebSpecialNavigationActionHost: BrowserWebSpecialNavigationActionHost = {
    handleUserScriptInstallNavigation: (url: string, _source: string, _tabId: string): boolean =>
      this.browserUserScriptApplicationCoordinator.handleInstallCandidate(url),
    handleErrorDocumentActionUrl: (tabId: string, url: string): boolean =>
      this.browserWebPageLifecycleApplicationCoordinator.handleErrorDocumentActionUrl(tabId, url),
    isInternalDebugPageUrl: (url: string): boolean => isBrowserNewWindowTestUrl(url)
  };
  private browserWebSpecialNavigationActionCoordinator: BrowserWebSpecialNavigationActionCoordinator =
    new BrowserWebSpecialNavigationActionCoordinator({
      host: this.browserWebSpecialNavigationActionHost
    });
  private browserUnifiedLinkNavigationHost: BrowserUnifiedLinkNavigationHost = {
    readNavigationFacts: (tabId: string): BrowserUnifiedLinkNavigationFacts => ({
      tabVisible: tabId === this.activeTabId && this.isWebPageVisible(),
      windowVisible: this.isBrowserShellVisible
    })
  };
  private browserUnifiedLinkNavigationCoordinator: BrowserUnifiedLinkNavigationCoordinator =
    new BrowserUnifiedLinkNavigationCoordinator({
      externalNavigationPolicyService: this.externalNavigationPolicyService,
      externalNavigationRuntimeStateCoordinator: this.browserExternalNavigationRuntimeStateCoordinator,
      recentActionManager: this.browserRecentActionManager,
      webRuntimeBridge: this.webRuntimeBridge,
      preferencesRepository: sharedPreferencesRepository,
      tabScopedEventContextCoordinator: this.tabScopedEventContextCoordinator,
      applicationCoordinator: this.browserUnifiedLinkApplicationCoordinator
    });
  private siteCertificatePresentationService: SiteCertificatePresentationService =
    new SiteCertificatePresentationService();
  private siteInteractionLogicService: SiteInteractionLogicService = new SiteInteractionLogicService();
  private sitePolicyService: SitePolicyService = sharedSitePolicyService;
  private browserAdBlockCoordinator: BrowserAdBlockCoordinator = new BrowserAdBlockCoordinator(sharedAdBlockRepository);
  private browserWebNavigationInterceptionCoordinator: BrowserWebNavigationInterceptionCoordinator =
    new BrowserWebNavigationInterceptionCoordinator({
      adBlockCoordinator: this.browserAdBlockCoordinator,
      telegramWebCompatibilityService: this.telegramWebCompatibilityService,
      webLoadRuntimeCoordinator: this.browserWebLoadRuntimeCoordinator,
      tabScopedEventContextCoordinator: this.tabScopedEventContextCoordinator
    });
  private browserWebNavigationInterceptionHost: BrowserWebNavigationInterceptionHost = {
    isAdBlockCapabilitySupported: (): boolean =>
      this.browserSiteControlsRuntimeCoordinator.isAdBlockCapabilitySupported(),
    isControllerAttached: (): boolean => this.controllerAttached,
    shouldStrengthenAdBlockingForSmoothScroll: (): boolean => this.shouldStrengthenAdBlockingForSmoothScroll(),
    refreshSiteProtectionAfterNavigationClean: (): void => {
      this.browserSiteControlsRuntimeCoordinator.refreshActiveProtectionPresentation();
    }
  };
  private arkWebMediaTakeoverCoordinator: BrowserArkWebMediaTakeoverCoordinator =
    this.browserMediaDiscoveryRuntime.arkWebMediaTakeoverCoordinator;
  private arkWebMediaLaunchHost: BrowserArkWebMediaLaunchHost = {
    showToast: (message: string): void => {
      this.showNativeToast(message);
    },
    invalidatePresentation: (): void => {
      this.arkWebMediaTakeoverRevision += 1;
    },
    prepareWebVideoFullscreen: (tabId: string): Promise<void> => {
      return this.browserFullscreenSessionCoordinator.prepareVideoWebFullscreen(tabId);
    },
    cancelWebVideoFullscreenPreparation: (tabId: string): void => {
      this.browserFullscreenSessionCoordinator.cancelVideoWebFullscreenPreparation(tabId);
    },
    enterWebVideoFullscreen: (
      tabId: string,
      videoWidth: number,
      videoHeight: number
    ): Promise<boolean> => {
      return this.browserFullscreenSessionCoordinator.enterVideoWebFullscreen({
        tabId: tabId,
        videoWidth: videoWidth,
        videoHeight: videoHeight
      });
    },
    enterWebLiveFullscreen: (
      tabId: string,
      videoWidth: number,
      videoHeight: number
    ): Promise<boolean> => {
      return this.browserFullscreenSessionCoordinator.enterVideoAssistantFullscreen({
        tabId: tabId,
        videoWidth: videoWidth,
        videoHeight: videoHeight
      });
    },
    exitWebLiveFullscreen: (_tabId: string): void => {
      void this.exitVideoAssistantFullscreenAsync(false);
    },
    onStarted: (): void => {
      this.browserMediaResourceSessionCoordinator.handleTakeoverStarted();
      this.setWebBottomAddressFocused(false);
      this.webBottomAddressDraft = '';
    }
  };
  private arkWebMediaAssistantPlayerHost: BrowserArkWebMediaAssistantPlayerHost = {
    applyOrientation: (
      orientation: BrowserArkWebMediaAssistantOrientation,
      _reason: string
    ): Promise<void> => {
      return this.browserFullscreenSessionCoordinator.applyTemporaryMediaOrientation(orientation);
    },
    exitWebLiveFullscreen: (_tabId: string): Promise<void> => {
      return this.exitVideoAssistantFullscreenAsync(false);
    },
    invalidatePresentation: (): void => {
      this.arkWebMediaTakeoverRevision += 1;
    },
    requestDownload: (tabId: string, playbackTargetId: string): Promise<void> =>
      this.browserMediaResourceSessionCoordinator.requestActivePlaybackDownload(tabId, playbackTargetId),
    showToast: (message: string): void => {
      this.showNativeToast(message);
    }
  };
  private browserMediaDiscoveryCoordinator: BrowserMediaDiscoveryCoordinator =
    this.browserMediaDiscoveryRuntime.mediaDiscoveryCoordinator;
  private browserMediaDiscoveryRuntimeContextFactory: BrowserMediaDiscoveryRuntimeContextFactory =
    new BrowserMediaDiscoveryRuntimeContextFactory(sharedPreferencesRepository);
  private browserMediaDiscoveryHost: BrowserMediaDiscoveryHost = {
    resolveActiveTabId: (): string => this.activeTabId,
    isActiveTab: (tabId: string): boolean => tabId === this.activeTabId,
    resolvePageUrlForTab: (tabId: string): string => this.tabScopedEventContextCoordinator.resolvePageUrl(tabId),
    resolvePageTitleForTab: (tabId: string): string => this.tabManager.getTab(this.tabs, tabId)?.title ?? '',
    resolvePrivacyModeForTab: (tabId: string): BrowserSessionPrivacyMode => this.tabScopedEventContextCoordinator.resolvePrivacyMode(tabId),
    buildRuntimeContext: (): BrowserMediaDiscoveryRuntimeContext => this.buildMediaDiscoveryRuntimeContext(),
    resolveInteractionQuietDelayMs: (baseDelayMs: number): number =>
      this.browserWebScrollInteractionCoordinator.getQuietDelayMs(baseDelayMs),
    applyMediaDiscoverySurfaceState: (state: BrowserMediaDiscoverySurfaceState): void => {
      this.browserMediaResourceSessionCoordinator.applyDiscoverySurfaceState(state);
    },
    showToast: (message: string): void => this.showNativeToast(message)
  };
  private browserMediaRuntimeObservationApplicationHost: BrowserMediaRuntimeObservationApplicationHost = {
    resolvePageUrl: (tabId: string): string => this.tabScopedEventContextCoordinator.resolvePageUrl(tabId),
    resolvePageTitle: (tabId: string): string => this.tabManager.getTab(this.tabs, tabId)?.title ?? '',
    resolvePrivateMode: (tabId: string): boolean => this.browserPrivateProfileLifecycleCoordinator
      .isSessionEphemeralTabState(this.tabManager.getTab(this.tabs, tabId)),
    resolveWebActionToolbarEnabled: (tabId: string): boolean =>
      tabId === this.activeTabId && this.isWebPageVisible() && this.isWebVideoTakeoverExperimentEnabled(),
    requestWebActionToolbarFullscreen: (tabId: string, payloadJson: string): void => {
      void this.arkWebMediaTakeoverCoordinator.launchFromWebActionToolbar(
        tabId,
        payloadJson,
        this.isWebVideoTakeoverExperimentEnabled(),
        this.arkWebMediaLaunchHost
      );
    },
    invalidateTakeoverPresentation: (): void => {
      this.arkWebMediaTakeoverRevision += 1;
    }
  };
  private browserMediaRuntimeObservationApplicationCoordinator:
    BrowserMediaRuntimeObservationApplicationCoordinator =
    new BrowserMediaRuntimeObservationApplicationCoordinator(
      this.browserMediaDiscoveryCoordinator,
      this.arkWebMediaTakeoverCoordinator,
      this.browserTabBackgroundSessionSyncCoordinator,
      this.browserMediaDiscoveryRuntime.mediaFrameRuntimeCoordinator,
      this.browserMediaRuntimeObservationApplicationHost
    );
  private browserMediaResourceSessionShell: BrowserMediaResourceSessionShell = {
    publishSnapshot: (snapshot: BrowserMediaResourceSessionSnapshot): void => {
      this.mediaResourceSessionSnapshot = snapshot;
    },
    copyText: (value: string, emptyMessage: string, successMessage: string): void => {
      this.copyTextToClipboard(value, emptyMessage, successMessage);
    },
    endDormantHlsPresentation: (): void => {
      this.endTransientBottomSheetPresentation('hls_takeover');
    }
  };
  private siteDataControlService: SiteDataControlService =
    new SiteDataControlService(sharedPreferencesRepository, sharedPrivateModeCookieSnapshotRepository);
  private browserSiteControlsApplicationShell: BrowserSiteControlsApplicationShell = {
    resolveAbilityContext: (): common.UIAbilityContext => this.getAbilityContext(),
    readRuntimeFacts: (): BrowserSiteControlsRuntimeFacts => ({
      controllerAttached: this.controllerAttached,
      shouldDeferTrackingRefresh:
        this.browserWebScrollInteractionCoordinator.shouldDeferTask('page_tracking_protection_status_update'),
      trackingRefreshDelayMs: this.browserWebScrollInteractionCoordinator.getQuietDelayMs(
        WEB_SCROLL_TRACKING_PROTECTION_STATUS_UPDATE_DELAY_MS
      ),
      strengthenAdBlockingForSmoothScroll: this.shouldStrengthenAdBlockingForSmoothScroll()
    }),
    publishSnapshot: (snapshot: BrowserSiteControlsApplicationSnapshot): void => {
      this.siteControlsApplicationSnapshot = snapshot;
    },
    presentMessage: (kind, message): void => {
      if (kind === 'error') {
        this.errorMessage = message;
        return;
      }
      this.showNativeToast(message);
    },
    presentClearSiteDataDialog: (state: SiteDataClearDialogState): void => {
      this.browserNativeAlertDialogPresenter.confirm({
        title: state.title,
        message: state.message,
        cancelLabel: '取消',
        confirmLabel: state.confirmLabel,
        confirmTone: 'alert',
        onConfirm: () => {
          this.browserSiteControlsRuntimeCoordinator.handleUserAction('confirm_clear_site_data');
        }
      });
    },
    copyCurrentUrl: (): void =>
      this.browserRootBottomPanelActionApplication.handleAddressContextAction('copy_link')
  };
  private browserSiteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator =
    new BrowserSiteControlsRuntimeCoordinator(
      this.siteCertificatePresentationService,
      this.browserAdBlockCoordinator,
      this.siteDataControlService,
      this.sitePolicyService,
      this.siteInteractionLogicService,
      this.browserRuntimeLifecyclePort,
      {
        securityReportMetricsRepository: sharedBrowserSecurityReportMetricsRepository,
        routeCoordinator: this.browserShellRouteCoordinator,
        hostedRuntimeSurfacePort: this.browserHostedRuntimeSurfacePort,
        tabScopedEventContextCoordinator: this.tabScopedEventContextCoordinator,
        reloadActive: (reason: BrowserPageReloadReason): void => {
          this.browserActiveTabRuntimeRestoreCoordinator.reloadActive(reason);
        }
      },
      this.browserSiteControlsApplicationShell
    );
  private browserWebPageToolsCoordinator: BrowserWebPageToolsCoordinator =
    new BrowserWebPageToolsCoordinator(
      this.browserTransientSurfaceCoordinator,
      this.browserSiteControlsRuntimeCoordinator,
      {
        resolveFullscreenActionOwner: () => this.browserFullscreenSessionCoordinator,
        resolveUserAgentActionOwner: () => this.browserUserAgentActionCoordinator
      },
      (snapshot: BrowserWebPageToolsSnapshot): void => {
        this.browserWebPageToolsSnapshot = snapshot;
      },
      {
        revealDelayMs: WEB_PAGE_TOOLS_OVERLAY_OPEN_DELAY_MS,
        dismissDurationMs: WEB_PAGE_TOOLS_OVERLAY_ANIMATION_DURATION_MS,
        useNativeSystemSheet: (): boolean => !this.isLargeScreenShellFamilyActive()
      }
    );
  private browserFullscreenSessionSink: BrowserFullscreenSessionSink = {
    resolveSurfaceFacts: (): BrowserFullscreenSurfaceFacts => this.buildBrowserFullscreenSurfaceFacts(),
    publishPresentation: (presentation: BrowserFullscreenSessionPresentation): void => {
      this.browserFullscreenSessionPresentation = presentation;
    },
    applyEffect: (effect: BrowserFullscreenSessionEffect): void => {
      this.applyBrowserFullscreenSessionEffect(effect);
    }
  };
  private browserFullscreenSessionCoordinator: BrowserFullscreenSessionCoordinator =
    new BrowserFullscreenSessionCoordinator(
      this.browserFullscreenSessionSink,
      this.browserWebPageToolsCoordinator
    );
  private manualElementHideRuntimeShell: ManualElementHideRuntimeShell = {
    resolveFacts: () => {
      return {
        activeTabId: this.activeTabId,
        showHomePage: this.showHomePage,
        showTabsSheet: this.showTabsSheet,
        pageHost: this.resolveCurrentWebPageActionHost(),
        pageUrl: this.resolveCurrentWebPageActionUrl()
      };
    },
    publishSelection: (presentation: ManualElementHideSelectionPresentation): void => {
      this.manualElementHideSelectionPresentation = presentation;
    },
    prepareSelectionChrome: (): void => {
      this.setWebBottomAddressFocused(false);
      this.webBottomAddressDraft = '';
      this.rootBottomAddressPanelDetent = 'peek';
    },
    showToast: (message: string): void => {
      this.showNativeToast(message);
    },
    publishError: (message: string): void => {
      this.errorMessage = message;
    }
  };
  private manualElementHideRuntimeCoordinator: ManualElementHideRuntimeCoordinator =
    new ManualElementHideRuntimeCoordinator(
      new ManualElementHideService(sharedManualElementHideRepository),
      this.browserRuntimeLifecyclePort,
      this.browserAdBlockCoordinator,
      this.tabScopedEventContextCoordinator,
      sharedMembershipFeature,
      this.featureGateCoordinator,
      this.browserSiteControlsRuntimeCoordinator,
      this.manualElementHideRuntimeShell
    );
  private browserWebCapabilityPromptApplicationSink: BrowserWebCapabilityPromptApplicationSink = {
    resolveAbilityContext: (): common.UIAbilityContext => this.getAbilityContext(),
    resolveExperiments: (): BrowserExperimentSettings =>
      sharedPreferencesRepository.getPreferences().experiments,
    setWebDialogVisible: (tabId: string, kind: BrowserWebDialogKind, visible: boolean): void => {
      this.browserWebTabsController.setDialogVisible(tabId, kind, visible);
    },
    resolveEffectHandler: () => this.browserWebCapabilityPromptEffectApplication
  };
  private browserWebCapabilityPromptApplicationCoordinator: BrowserWebCapabilityPromptApplicationCoordinator =
    new BrowserWebCapabilityPromptApplicationCoordinator({
      webRuntimeBridge: this.webRuntimeBridge,
      tabScopedEventContextCoordinator: this.tabScopedEventContextCoordinator,
      backgroundSessionSyncCoordinator: this.browserTabBackgroundSessionSyncCoordinator,
      appProxySettingsCoordinator: this.appProxySettingsCoordinator,
      sitePolicyService: this.sitePolicyService,
      siteControlsRuntimeCoordinator: this.browserSiteControlsRuntimeCoordinator,
      siteInteractionLogicService: this.siteInteractionLogicService,
      systemSettingsLaunchService: this.systemSettingsLaunchService,
      browserFaultClassifier: this.browserFaultClassifier,
      webEventRouter: this.webEventRouter
  }, this.browserWebCapabilityPromptApplicationSink);
  private browserWebCapabilityAlertDialogPresenter: BrowserWebCapabilityAlertDialogPresenter =
    new BrowserWebCapabilityAlertDialogPresenter(this.browserWebCapabilityPromptApplicationCoordinator);
  private browserWebCapabilityPromptEffectShell: BrowserWebCapabilityPromptEffectShell = {
    applyMessage: (kind: BrowserWebCapabilityPromptMessageKind, message: string): void => {
      if (kind === 'helper') {
        this.helperMessage = message;
      } else if (kind === 'error') {
        this.errorMessage = message;
      } else {
        this.showNativeToast(message);
      }
    },
    openJavaScriptPrompt: (presentation: BrowserWebPromptDialogPresentation): void => {
      this.webPromptDialogPresentation = presentation;
      this.webPromptDialogController.open();
    },
    closeJavaScriptPrompt: (): void => {
      try {
        this.webPromptDialogController.close();
      } catch (_error) {
      }
    },
    openHttpAuth: (presentation: BrowserHttpAuthDialogPresentation): void => {
      this.httpAuthDialogPresentation = presentation;
      this.httpAuthDialogController.open();
    },
    clearHttpAuth: (): void => {
      this.httpAuthDialogPresentation = createEmptyBrowserHttpAuthDialogPresentation();
    },
    closeHttpAuth: (): void => {
      try {
        this.httpAuthDialogController.close();
      } catch (_error) {
      }
    },
    openSitePermission: (presentation: BrowserSitePermissionDialogPresentation): void => {
      this.sitePermissionDialogPresentation = presentation;
      this.sitePermissionPromptVisible = true;
    }
  };
  private browserWebCapabilityPromptEffectApplication: BrowserWebCapabilityPromptEffectApplication =
    new BrowserWebCapabilityPromptEffectApplication(
      (effect: BrowserWebCapabilityPromptApplicationEffect): void => {
        this.browserWebCapabilityAlertDialogPresenter.present(effect);
      },
      this.browserWebCapabilityPromptEffectShell
    );
  private articleReadingSession: BrowserWindowSessionArticleReadingPort =
    new BrowserWindowSessionArticleReadingPort();
  private browserBookmarkActionShell: BrowserBookmarkActionShell = {
    applySnapshot: (snapshot: BrowserBookmarkActionSessionSnapshot): void => {
      this.browserBookmarkActionSessionSnapshot = snapshot;
    },
    showToast: (message: string): void => {
      this.showNativeToast(message);
    },
    presentPersistentWriteBlocked: (helperText: string, _summaryLine: string): void => {
      this.showNativeToast(helperText);
    },
    confirmRemove: (confirmation: BrowserBookmarkRemoveConfirmation): void => {
      this.confirmBookmarkRemoval(confirmation);
    },
    refreshHomeShortcuts: (): void => {
      this.homeShortcutStateCoordinator.refresh();
    }
  };
  private browserBookmarkActionCoordinator: BrowserBookmarkActionCoordinator =
    new BrowserBookmarkActionCoordinator({
      repository: sharedBookmarkRepository,
      folderPreparationCoordinator: sharedBookmarkFolderSelectionPreparationCoordinator,
      searchSuggestionCoordinator: this.browserSearchSuggestionCoordinator,
      homeShortcutToggleService: this.homeShortcutToggleService,
      transientSurfaceCoordinator: this.browserTransientSurfaceCoordinator,
      overlayRevealDelayMs: BOOKMARK_FOLDER_OVERLAY_OPEN_DELAY_MS,
      overlayDismissDurationMs: BOOKMARK_FOLDER_OVERLAY_ANIMATION_DURATION_MS
    }, this.browserBookmarkActionShell);
  private siteClearOnCloseLifecycleService: SiteClearOnCloseLifecycleService =
    new SiteClearOnCloseLifecycleService(
      sharedBrowserSitePrivacyRuleRepository,
      this.siteDataControlService,
      this.siteInteractionLogicService
    );
  private browserRecentlyClosedApplicationShell: BrowserRecentlyClosedApplicationShell = {
    resolveFacts: (): BrowserRecentlyClosedApplicationFacts => {
      return {
        currentWindowId: this.currentWindowId,
        currentProfileId: this.browserWindowContextCoordinator.resolveCurrentTabSessionProfileId(),
        dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
        privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
        showHomePage: this.showHomePage
      };
    },
    publishSnapshot: (snapshot: BrowserRecentlyClosedApplicationSnapshot): void => {
      this.recentlyClosedApplicationSnapshot = snapshot;
    },
    presentBoundaryBlock: (_eventType: string, _summaryLine: string, helperText: string): void => {
      this.showNativeToast(helperText);
    },
    showToast: (message: string): void => {
      this.showNativeToast(message);
    },
    showDialog: (title: string, message: string): void => {
      this.browserNativeAlertDialogPresenter.inform({
        title: title,
        message: message,
        confirmLabel: '知道了'
      });
    },
    confirmDelete: (confirmation: BrowserConfirmationRequest): void => {
      this.browserNativeAlertDialogPresenter.confirm(confirmation);
    },
    refreshHomeShortcuts: (): void => {
      this.homeShortcutStateCoordinator.refresh();
    }
  };
  private browserRecentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator =
    new BrowserRecentlyClosedApplicationCoordinator({
      repository: sharedRecentlyClosedTabRepository,
      preferencesRepository: sharedPreferencesRepository,
      homeShortcutToggleService: this.homeShortcutToggleService,
      clipboardService: this.browserClipboardService,
      tabsService: new BrowserRecentlyClosedTabsService(this.browserDownloadNavigationStateCoordinator),
      homePresentationViewModel: this.browserHomePresentationViewModel,
      siteClearOnCloseLifecycleService: this.siteClearOnCloseLifecycleService
    }, this.browserRecentlyClosedApplicationShell);
  private historyFeature: HistoryFeature =
    new HistoryFeature(sharedHistoryRepository, sharedPreferencesRepository, sharedRecentlyClosedTabRepository);
  private siteClearOnCloseCoordinator: SiteClearOnCloseCoordinator =
    new SiteClearOnCloseCoordinator(
      this.siteClearOnCloseLifecycleService,
      this.browserRecentlyClosedApplicationCoordinator
    );
  private browserTabCloseCoordinator: BrowserTabCloseCoordinator =
    new BrowserTabCloseCoordinator(this.tabManager, {
      resolveApplicationHost: (): BrowserCloseTabApplicationHost => this.browserCloseTabApplicationHost,
      resolveWebPageLifecycleCoordinator: (): BrowserWebPageLifecycleApplicationCoordinator =>
        this.browserWebPageLifecycleApplicationCoordinator,
      resolveTabSessionPersistenceCoordinator: (): BrowserTabSessionPersistenceCoordinator =>
        this.browserTabSessionPersistenceCoordinator,
      resolveTabHomeCoordinator: (): BrowserTabHomeCoordinator => this.browserTabHomeCoordinator,
      revealHomeSurfaceFromTabsOverview: (
        helperMessage: string,
        homeOptions: BrowserCreateTabOptions,
        homeRevealMotion: BrowserCloseTabHomeRevealMotion
      ): Promise<void> => this.tabsOverviewSessionCoordinator.revealHomeSurfaceAfterTabClose(
        helperMessage,
        homeOptions,
        homeRevealMotion
      ),
      playDirectHomeReveal: (): void => {
        this.browserHomePresentationSessionCoordinator.playReveal({
          fadeBackdrop: true,
          restoreBottomPanelFromPeek: true
        });
      },
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      pageFindCoordinator: this.browserPageFindCoordinator,
      privateModeLockCoordinator: this.browserPrivateModeLockCoordinator,
      tabPreviewCoordinator: this.browserTabPreviewCoordinator,
      tabsOverviewSnapshotPipelineCoordinator: this.tabsOverviewSnapshotPipelineCoordinator,
      backgroundOpenPromptCoordinator: this.browserBackgroundOpenPromptCoordinator,
      recentlyClosedApplicationCoordinator: this.browserRecentlyClosedApplicationCoordinator,
      privateSessionCleanupCoordinator: this.browserPrivateSessionCleanupCoordinator,
      documentViewerService: this.documentViewerService,
      siteClearOnCloseCoordinator: this.siteClearOnCloseCoordinator,
      resolveSiteClearOnCloseHost: (): SiteClearOnCloseCoordinatorHost => this.siteClearOnCloseCoordinatorHost
    });
  private browserUserReturnHomeCoordinator: BrowserUserReturnHomeCoordinator =
    new BrowserUserReturnHomeCoordinator(this.browserTabCloseCoordinator);
  private browserHistoryVisitPersistenceCoordinator: BrowserHistoryVisitPersistenceCoordinator =
    new BrowserHistoryVisitPersistenceCoordinator(
      this.browserWebEventCommitCoordinator,
      this.historyFeature,
      this.appReviewPromptCoordinator,
      sharedActivityTracker,
      this.documentViewerService,
      this.siteClearOnCloseCoordinator,
      {
        resolveTab: (tabId: string): BrowserTabState | undefined => this.tabManager.getTab(this.tabs, tabId),
        resolveProfileId: (tabId: string): BrowserProfileId => this.tabScopedEventContextCoordinator.resolveProfileId(tabId),
        resolvePrivacyMode: (tabId: string): BrowserSessionPrivacyMode => this.tabScopedEventContextCoordinator.resolvePrivacyMode(tabId),
        resolveDataScope: (tabId: string): BrowserDataScope => this.tabScopedEventContextCoordinator.resolveDataScope(tabId),
        invalidateSearchSuggestionCache: (): void => {
          this.browserSearchSuggestionCoordinator.invalidate();
        }
      }
    );
  private siteClearOnCloseCoordinatorHost: SiteClearOnCloseCoordinatorHost = {
    deleteHistoryByHost: (host: string): Promise<number> => {
      return this.historyFeature.deleteVisitsByHost(host);
    },
    invalidateHistoryCaches: (): void => {
      this.browserSearchSuggestionCoordinator.invalidate();
    },
    persistPendingRecords: (records: TabRecord[]): Promise<void> => {
      return sharedSiteClearOnClosePendingRepository.replaceRecords(
        this.currentWindowId,
        this.browserWindowContextCoordinator.resolveCurrentTabSessionProfileId(),
        records
      );
    }
  };
  private browserTabSessionPersistenceCoordinator: BrowserTabSessionPersistenceCoordinator =
    new BrowserTabSessionPersistenceCoordinator({
      tabManager: this.tabManager,
      documentViewerService: this.documentViewerService,
      downloadNavigationStateCoordinator: this.browserDownloadNavigationStateCoordinator,
      siteClearOnCloseCoordinator: this.siteClearOnCloseCoordinator,
      siteClearOnCloseHost: this.siteClearOnCloseCoordinatorHost
    }, this.browserTabSessionPersistenceHost);
  private browserUrlThreatProtectionHost: BrowserUrlThreatProtectionHost = {
    isActiveTab: (tabId: string): boolean => tabId === this.activeTabId,
    publishNoticeState: (state: BrowserUrlThreatNoticeState): void => {
      this.urlThreatNoticeState = state;
    }
  };
  private browserUrlThreatProtectionCoordinator: BrowserUrlThreatProtectionCoordinator =
    new BrowserUrlThreatProtectionCoordinator(this.browserUrlThreatProtectionHost);
  private browserAppUrlOpenHost: BrowserAppUrlOpenHost = {
    resolveForegroundTabCreationState: () => {
      return {
        tabs: this.tabs,
        activeTabId: this.activeTabId,
        tabSequence: this.tabSequence,
        homeUrl: HOME_TAB_URL
      };
    },
    persistActiveTabSnapshot: (reason: string): void => this.persistActiveTabSnapshotAsync(reason),
    captureCurrentTabPreviewForForegroundCreationAsync: (): Promise<boolean> => {
      return this.captureOutgoingTabVisibleSurfacePreview();
    },
    cancelOutgoingTabPreviewCapture: (): void => {
      this.cancelOutgoingTabPreviewCapture();
    },
    applyTabCreationState: (application: BrowserTabCreationStateApplication): void => {
      if (application.tabs !== undefined) {
        this.tabs = application.tabs;
      }
      if (application.activeTabId !== undefined) {
        this.activeTabId = application.activeTabId;
      }
      if (application.tabSequence !== undefined) {
        this.tabSequence = application.tabSequence;
      }
      if (application.helperMessage !== undefined) {
        this.helperMessage = application.helperMessage;
      }
    },
    isHomeSurfaceVisible: (): boolean => this.showHomePage,
    getOpenErrorMessage: (): string => this.errorMessage,
    applyAddressInput: (addressInput: string): void => {
      this.addressInput = addressInput;
    },
    applyMessage: (kind: 'helper' | 'error' | 'toast', message: string): void => {
      if (kind === 'helper') {
        this.helperMessage = message;
        return;
      }
      if (kind === 'error') {
        this.errorMessage = message;
        return;
      }
      this.showNativeToast(message);
    }
  };
  private browserAppUrlOpenCoordinator: BrowserAppUrlOpenCoordinator = new BrowserAppUrlOpenCoordinator(
    this.browserAppUrlOpenHost,
    {
      tabManager: this.tabManager,
      foregroundTabCreationCoordinator: this.browserForegroundTabCreationCoordinator,
      recentActionManager: this.browserRecentActionManager,
      offlineFastFailureCoordinator: this.browserOfflineFastFailureCoordinator,
      webLoadRuntimeCoordinator: this.browserWebLoadRuntimeCoordinator,
      tabSessionPersistenceCoordinator: this.browserTabSessionPersistenceCoordinator,
      backgroundTabPreviewRuntimeCoordinator: this.browserBackgroundTabPreviewRuntimeCoordinator,
      backgroundOpenPromptCoordinator: this.browserBackgroundOpenPromptCoordinator,
      searchSuggestionCoordinator: this.browserSearchSuggestionCoordinator,
      webRuntimeBridge: this.webRuntimeBridge,
      unifiedLinkNavigationCoordinator: this.browserUnifiedLinkNavigationCoordinator,
      unifiedLinkNavigationHost: this.browserUnifiedLinkNavigationHost,
      tabScopedEventContextCoordinator: this.tabScopedEventContextCoordinator,
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      addressDisplayCoordinator: this.browserAddressDisplayCoordinator,
      resolveLifecycleApplication: () => this.browserWebPageLifecycleApplicationCoordinator
    }
  );
  private browserQuickSearchSwitchingHost: BrowserQuickSearchSwitchingHost = {
    resolveActiveTabId: (): string => this.activeTabId,
    resolveTabIds: (): string[] => this.tabs.map((tab: BrowserTabState): string => tab.id),
    resolveCurrentBoundary: (): BrowserCreateTabOptions =>
      this.tabScopedEventContextCoordinator.resolveCurrentBoundary(),
    isWebPageVisible: (): boolean => this.isWebPageVisible(),
    isWebAppActive: (): boolean => this.webAppSessionSnapshot.activeContext !== undefined && this.isWebPageVisible(),
    publishPresentation: (presentation: BrowserQuickSearchSwitchingPresentation): void => {
      this.quickSearchSwitchingPresentation = presentation;
    }
  };
  private browserQuickSearchSwitchingCoordinator: BrowserQuickSearchSwitchingCoordinator =
    new BrowserQuickSearchSwitchingCoordinator(
      sharedSearchEngineRepository,
      sharedQuickSearchSwitchPreferencesRepository,
      this.browserRuntimeLifecyclePort,
      this.browserAppUrlOpenCoordinator,
      this.browserWebTopImmersionSessionCoordinator,
      this.browserQuickSearchSwitchingHost
    );
  private addressSubmissionCoordinator: BrowserAddressSubmissionCoordinator =
    new BrowserAddressSubmissionCoordinator(
      this.browserAddressSubmissionShell,
      sharedSearchEngineRoutingService,
      this.browserSearchSubmissionHistoryCoordinator,
      this.browserAddressDisplayCoordinator,
      this.browserAppUrlOpenCoordinator,
      this.browserQuickSearchSwitchingCoordinator
    );
  private readerModeApplicationShell: ReaderModeApplicationShell = {
    readFacts: (): ReaderModeApplicationFacts => ({
      activeTabId: this.activeTabId,
      currentWebActionUrl: this.resolveCurrentWebPageActionUrl(),
      currentTitle: this.currentTitle,
      articleTitle: this.readerModeSessionSnapshot.state.article.title,
      dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
      privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
      homeShortcutScenarioId: this.homeShortcutApplicationSnapshot.scenarioId,
      readerVisible: this.readerModeSessionSnapshot.state.visible
    }),
    resolveCreateOptions: (): BrowserCreateTabOptions => this.tabScopedEventContextCoordinator.resolveCurrentBoundary(),
    resolveAbilityContext: (): common.UIAbilityContext => this.getAbilityContext(),
    showToast: (message: string): void => this.showNativeToast(message),
    publishHelper: (message: string): void => {
      this.helperMessage = message;
    },
    publishError: (message: string): void => {
      this.errorMessage = message;
    },
    syncStatusBarStyle: (): void => this.syncBottomPanelStatusBarStyle(),
    closeSpeechVoiceDialog: (): void => this.readerSpeechVoiceDialogController.close()
  };
  private readingWindowBrightnessService: ReadingWindowBrightnessService =
    new ReadingWindowBrightnessService();
  private readerModeApplication: ReaderModeApplication = new ReaderModeApplication({
    readerModeCoordinator: this.articleReadingSession,
    clipboardService: this.browserClipboardService,
    webPageShareService: this.webPageShareService,
    bookmarkActionCoordinator: this.browserBookmarkActionCoordinator,
    shellRouteCoordinator: this.browserShellRouteCoordinator,
    transientSurfaceCoordinator: this.browserTransientSurfaceCoordinator,
    unifiedLinkApplicationCoordinator: this.browserUnifiedLinkApplicationCoordinator,
    webTopImmersionSessionCoordinator: this.browserWebTopImmersionSessionCoordinator,
    appUrlOpenCoordinator: this.browserAppUrlOpenCoordinator,
    confirmationPresenter: this.browserNativeAlertDialogPresenter,
    readingWindowBrightnessService: this.readingWindowBrightnessService
  }, this.readerModeApplicationShell, {
    revealDelayMs: READER_SPEECH_PLAYER_OPEN_DELAY_MS,
    dismissDurationMs: READER_SPEECH_PLAYER_OVERLAY_ANIMATION_DURATION_MS
  });
  private webContextMenuCoordinator: WebLinkContextMenuCoordinator = new WebLinkContextMenuCoordinator(
    {
      userScriptRuntimeCoordinator: this.userScriptRuntimeCoordinator,
      webLoadRuntimeCoordinator: this.browserWebLoadRuntimeCoordinator,
      appUrlOpenCoordinator: this.browserAppUrlOpenCoordinator
    },
    {
      publishPresentation: (presentation: WebContextMenuPresentation): void => {
        this.webContextMenuPresentation = presentation;
      }
    },
    (): WebLinkContextMenuFixedActionApplication => this.webContextMenuActionApplication
  );
  private webScrollSmoothModeService: WebScrollSmoothModeService = new WebScrollSmoothModeService();
  private browserThemeModeCoordinator: BrowserThemeModeCoordinator =
    new BrowserThemeModeCoordinator(sharedPreferencesRepository);
  private homeShortcutOpenCoordinator: HomeShortcutOpenCoordinator = new HomeShortcutOpenCoordinator(
    this.browserAppUrlOpenCoordinator,
    this.browserShellRouteCoordinator
  );
  private homeShortcutEffectApplicationShell: HomeShortcutEffectApplicationShell = {
    dismissContextMenu: (): void => {
      this.contextMenuHomeShortcutId = '';
    },
    openEditDialog: (draft: HomeShortcutEditDraft): void => {
      this.homeShortcutEditDraft = draft;
      this.editHomeShortcutDialogController.open();
    },
    showToast: (message: string): void => this.showNativeToast(message),
    publishHelper: (message: string): void => {
      this.helperMessage = message;
    },
    presentBoundaryBlock: (_summaryLine: string, helperText: string): void => {
      this.showNativeToast(helperText);
    },
    publishSelectionSnapshot: (snapshot: HomeShortcutSelectionState): void => {
      this.homeShortcutSelectionState = snapshot;
    },
    openSelectionSheet: (): void => {
      this.browserTransientSurfaceCoordinator.openSystemSheet('homeShortcutSelection');
    },
    closeSelectionSheet: (): void => {
      this.closeSystemSheet();
    }
  };
  private homeShortcutEffectApplication: HomeShortcutFixedEffectApplication =
    new HomeShortcutFixedEffectApplication(
      (presentation: HomeShortcutConfirmationPresentation): void => {
        this.browserNativeAlertDialogPresenter.confirm({
          title: presentation.title,
          message: presentation.message,
          cancelLabel: presentation.cancelLabel,
          confirmLabel: presentation.confirmLabel,
          onConfirm: presentation.onConfirm
        });
      },
      (presentation: HomeShortcutInformationPresentation): void => {
        this.browserNativeAlertDialogPresenter.inform({
          title: presentation.title,
          message: presentation.message,
          confirmLabel: presentation.confirmLabel
        });
      },
      this.homeShortcutEffectApplicationShell
    );
  private homeShortcutApplicationShell: HomeShortcutApplicationShell = {
    resolveFacts: () => ({
      activeTabId: this.activeTabId,
      dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
      privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode
    }),
    publishSnapshot: (snapshot: HomeShortcutApplicationSnapshot): void => {
      this.homeShortcutApplicationSnapshot = snapshot;
    }
  };
  private homeShortcutStateCoordinator: HomeShortcutStateCoordinator = new HomeShortcutStateCoordinator({
    clipboardService: this.browserClipboardService,
    shortcutIconResolver: this.shortcutIconResolver,
    openCoordinator: this.homeShortcutOpenCoordinator,
    recentlyClosedApplicationCoordinator: this.browserRecentlyClosedApplicationCoordinator,
    searchSuggestionCoordinator: this.browserSearchSuggestionCoordinator,
    effectApplication: this.homeShortcutEffectApplication
  }, this.homeShortcutApplicationShell);
  private customHomepageRuntimeShellHost: CustomHomepageRuntimeShellHost = {
    resolveFacts: (): CustomHomepageRuntimeShellFacts => this.buildCustomHomepageRuntimeFacts(),
    publishState: (state: CustomHomepageRuntimeShellState): void => {
      this.applyCustomHomepageRuntimeState(state);
    },
    notifyDocumentCommitted: (): void => {
      this.browserHomePresentationSessionCoordinator.handleThirdPartyHomeDocumentCommitted();
    },
    executeEffect: (effect: CustomHomepageRuntimeShellEffect): void => {
      this.executeCustomHomepageShellEffect(effect);
    }
  };
  private customHomepageRuntimeCoordinator: CustomHomepageRuntimeCoordinator =
    new CustomHomepageRuntimeCoordinator({
      repository: sharedCustomHomepageRepository,
      selectionCoordinator: this.searchEngineSelectionCoordinator,
      addressSubmissionCoordinator: this.addressSubmissionCoordinator,
      appUrlOpenCoordinator: this.browserAppUrlOpenCoordinator,
      routeCoordinator: this.browserShellRouteCoordinator,
      shortcutStateCoordinator: this.homeShortcutStateCoordinator,
      windowOpenApplicationCoordinator: this.browserWindowOpenApplicationCoordinator,
      webRuntimeBridge: this.webRuntimeBridge
    }, this.customHomepageRuntimeShellHost);
  private themePaletteService: BrowserThemePaletteService = new BrowserThemePaletteService();
  private homeWallpaperCoordinator: HomeWallpaperCoordinator =
    new HomeWallpaperCoordinator(sharedWallpaperRepository);
  private webRecoveryManager: WebRecoveryManager =
    new WebRecoveryManager(this.browserDownloadNavigationStateCoordinator);
  private browserStartupTabRestoreCoordinator: BrowserStartupTabRestoreCoordinator =
    new BrowserStartupTabRestoreCoordinator({
      restoreCoordinator: this.browserRestoreCoordinator,
      downloadNavigationStateCoordinator: this.browserDownloadNavigationStateCoordinator,
      recentlyClosedApplicationCoordinator: this.browserRecentlyClosedApplicationCoordinator,
      siteClearOnCloseCoordinator: this.siteClearOnCloseCoordinator,
      siteClearOnCloseHost: this.siteClearOnCloseCoordinatorHost,
      privateSessionCleanupCoordinator: this.browserPrivateSessionCleanupCoordinator,
      privateProfileLifecycleCoordinator: this.browserPrivateProfileLifecycleCoordinator,
      tabSessionPersistenceCoordinator: this.browserTabSessionPersistenceCoordinator,
      tabManager: this.tabManager,
      documentViewerService: this.documentViewerService,
      webRecoveryManager: this.webRecoveryManager,
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      resolveTabHomeCoordinator: (): BrowserTabHomeCoordinator => this.browserTabHomeCoordinator,
      backgroundSessionSyncCoordinator: this.browserTabBackgroundSessionSyncCoordinator,
      shellStateCoordinator: this.browserShellStateCoordinator,
      tabPreviewAssetBoundaryCoordinator: this.browserTabPreviewAssetBoundaryCoordinator,
      tabPreviewCoordinator: this.browserTabPreviewCoordinator,
      nativeNavigationConsumeCoordinator: this.browserNativeNavigationConsumeCoordinator,
      previewHydrateBatchSize: TABS_OVERVIEW_PREVIEW_HYDRATE_BATCH_SIZE,
      previewHydrateBatchDelayMs: TABS_OVERVIEW_PREVIEW_HYDRATE_BATCH_DELAY_MS,
      resolveWindowContextCoordinator: (): BrowserWindowContextPort => this.browserWindowContextCoordinator
    }, this.browserStartupTabRestoreHost);
  private browserWindowContextComposition: BrowserWindowSessionContextComposition = {
    dependencies: {
      runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
      hostedRuntimeSurfacePort: this.browserHostedRuntimeSurfacePort,
      backgroundSessionSyncCoordinator: this.browserTabBackgroundSessionSyncCoordinator,
      tabSessionPersistenceCoordinator: this.browserTabSessionPersistenceCoordinator,
      recentlyClosedApplicationCoordinator: this.browserRecentlyClosedApplicationCoordinator,
      tabManager: this.tabManager,
      tabPreviewCoordinator: this.browserTabPreviewCoordinator,
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      webAppSessionCoordinator: this.webAppSessionCoordinator
    },
    shell: this.browserWindowContextShell,
    resolveLaunchApplication: (): BrowserWindowLaunchApplication => this.browserWindowLaunchApplication
  };
  private browserWindowContextCoordinator: BrowserWindowSessionContextPort =
    new BrowserWindowSessionContextPort();
  private webSessionStateStore: WebSessionStateStore = new WebSessionStateStore();
  private webStateSnapshotStore: WebStateSnapshotStore = new WebStateSnapshotStore();
  private browserActiveTabRuntimeRestoreCoordinator: BrowserActiveTabRuntimeRestoreCoordinator =
    new BrowserActiveTabRuntimeRestoreCoordinator({
      runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
      restoreCoordinator: this.browserRestoreCoordinator,
      recoveryManager: this.webRecoveryManager,
      sessionStateStore: this.webSessionStateStore,
      snapshotStore: this.webStateSnapshotStore,
      snapshotRecoveryCoordinator: this.browserTabRecoveryCoordinator,
      faultClassifier: this.browserFaultClassifier,
      webEventCommitCoordinator: this.browserWebEventCommitCoordinator,
      webLoadRuntimeCoordinator: this.browserWebLoadRuntimeCoordinator,
      tabManager: this.tabManager,
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      shellStateCoordinator: this.browserShellStateCoordinator,
      runtimeMutationPort: this.browserRuntimeMutationPort,
      loadFailureSurfaceCoordinator: this.browserWebLoadFailureSurfaceCoordinator,
      hostedRuntimeSurfacePort: this.browserHostedRuntimeSurfacePort,
      webpageTranslationCoordinator: this.webpageTranslationCoordinator,
      webEventRouter: this.webEventRouter,
      visibleUrlService: this.telegramWebCompatibilityService,
      activeSurfaceCoordinator: this.browserWebActiveSurfaceCoordinator,
      snapshotApplicationHost: this.browserSnapshotApplicationHost,
      resolveWebTabsController: (): BrowserWebTabsController => this.browserWebTabsController,
      resolveTabHomeCoordinator: (): BrowserTabHomeCoordinator => this.browserTabHomeCoordinator,
      primeNavigationVisualFeedback: (
        tabId: string,
        targetUrl: string,
        helperMessage?: string
      ): void => {
        this.browserWebPageLifecycleApplicationCoordinator.primeNavigationVisualFeedback(
          tabId,
          targetUrl,
          helperMessage ?? ''
        );
      },
      clearUserAgentTransitionSnapshotReloadMarker: (tabId: string): void => {
        this.browserUserAgentRuntimeTransitionCoordinator.clearSnapshotRestoreReloadMarker(tabId);
      },
      consumeUserAgentTransitionSnapshotReloadReason: (tabId: string): BrowserPageReloadReason | undefined => {
        return this.browserUserAgentRuntimeTransitionCoordinator.consumeSnapshotRestoreReloadReason(tabId);
      }
    }, this.browserActiveTabRuntimeRestoreHost);
  private browserWebTabsController: BrowserWebTabsController =
    new BrowserWebTabsController(
      this.buildBrowserWebTabsControllerDependencies(),
      this.browserWebTabsControllerHost,
      this.browserWindowOpenApplicationCoordinator
    );
  private browserTabHomeCoordinator: BrowserTabHomeCoordinator =
    new BrowserTabHomeCoordinator({
      runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
      runtimeMutationPort: this.browserRuntimeMutationPort,
      hostedRuntimeSurfacePort: this.browserHostedRuntimeSurfacePort,
      webTabsController: this.browserWebTabsController,
      offlineFastFailureCoordinator: this.browserOfflineFastFailureCoordinator,
      snapshotStore: this.webStateSnapshotStore,
      tabRecoveryCoordinator: this.browserTabRecoveryCoordinator,
      snapshotApplicationHost: this.browserSnapshotApplicationHost,
      webpageTranslationCoordinator: this.webpageTranslationCoordinator,
      webEventRouter: this.webEventRouter,
      visibleUrlService: this.telegramWebCompatibilityService,
      snapshotPersistenceHost: this.browserSnapshotPersistenceHost,
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      tabPreviewCoordinator: this.browserTabPreviewCoordinator,
      webRecoveryManager: this.webRecoveryManager,
      customHomepageRuntimeCoordinator: this.customHomepageRuntimeCoordinator,
      backgroundSessionSyncCoordinator: this.browserTabBackgroundSessionSyncCoordinator,
      tabSessionPersistenceCoordinator: this.browserTabSessionPersistenceCoordinator,
      searchSuggestionCoordinator: this.browserSearchSuggestionCoordinator,
      appReviewPromptCoordinator: this.appReviewPromptCoordinator,
      resolveReleaseNoticePresentationCoordinator: (): ReleaseNoticePresentationCoordinator =>
        this.releaseNoticePresentationCoordinator,
      resolveTabsOverviewSessionCoordinator: (): BrowserTabsOverviewSessionCoordinator =>
        this.tabsOverviewSessionCoordinator,
      resolveHomePresentationSessionCoordinator: (): BrowserHomePresentationSessionCoordinator =>
        this.browserHomePresentationSessionCoordinator,
      resolveRootBottomPanelSessionCoordinator: (): BrowserRootBottomPanelSessionCoordinator =>
        this.browserRootBottomPanelSessionCoordinator,
      preferencesRepository: sharedPreferencesRepository,
      searchEngineSelectionCoordinator: this.searchEngineSelectionCoordinator,
      homeShortcutStateCoordinator: this.homeShortcutStateCoordinator,
      recentlyClosedApplicationCoordinator: this.browserRecentlyClosedApplicationCoordinator,
      restoreRecentlyClosedRecord: (recordId: string): void => {
        this.browserTabCloseCoordinator.restoreRecentlyClosedRecord(recordId);
      },
      transientSurfaceCoordinator: this.browserTransientSurfaceCoordinator,
      themeModeCoordinator: this.browserThemeModeCoordinator,
      themePaletteService: this.themePaletteService,
      tabsOverviewThemeViewModel: this.browserTabsOverviewThemeViewModel,
      homeWallpaperCoordinator: this.homeWallpaperCoordinator,
      wallpaperRepository: sharedWallpaperRepository,
      backdropEffectViewModel: this.browserBackdropEffectViewModel,
      homepageBackdropAppearanceCoordinator: this.browserHomepageBackdropAppearanceCoordinator,
      arkWebMediaTakeoverCoordinator: this.arkWebMediaTakeoverCoordinator,
      fullscreenSessionCoordinator: this.browserFullscreenSessionCoordinator
    }, this.browserTabHomeShell);
  private novelReaderApplicationDependencies: NovelReaderApplicationDependencies =
    new NovelReaderApplicationDependencies(
      this.browserWebTopImmersionSessionCoordinator,
      this.browserWebLoadRuntimeCoordinator,
      this.browserTransientSurfaceCoordinator,
      this.browserNativeAlertDialogPresenter,
      this.readingWindowBrightnessService,
      this.browserTabHomeCoordinator,
      this.browserTabSwitchCoordinator,
      this.tabScopedEventContextCoordinator,
      this.browserRuntimeLifecyclePort,
      this.browserAppUrlOpenCoordinator,
      (tabId: string): Promise<boolean> => this.captureTabPreviewForExplicitAction(tabId, true, true),
      (tabId: string): boolean => this.activeTabId === tabId && this.isWebPageVisible(),
      (action: NovelReaderAction): void => this.novelReaderSession.handleAction(action)
    );
  private novelReaderApplication: NovelReaderApplication =
    new NovelReaderApplication(this.novelReaderApplicationDependencies);
  private browserWindowLaunchApplication: BrowserWindowFixedLaunchApplication =
    new BrowserWindowFixedLaunchApplication(
      {
        appShortcutActionCoordinator: this.appShortcutActionCoordinator,
        appUrlOpenCoordinator: this.browserAppUrlOpenCoordinator,
        foregroundTabCreationCoordinator: this.browserForegroundTabCreationCoordinator,
        privateBoundaryNavigationService: this.privateBoundaryNavigationService,
        tabHomeCoordinator: this.browserTabHomeCoordinator,
        tabSwitchCoordinator: this.browserTabSwitchCoordinator,
        webAppSessionCoordinator: this.webAppSessionCoordinator
      },
      {
        readFacts: () => ({
          currentWindowId: this.currentWindowId,
          tabs: this.tabs,
          activeTabId: this.activeTabId,
          showHomePage: this.showHomePage
        }),
        applyWebAppSessionSnapshot: (snapshot: WebAppSessionSnapshot, source: string): void => {
          this.applyWebAppSessionSnapshot(snapshot, source);
        },
        scanQr: (): void => {
          void this.scanQrCodeFromBottomPanel();
        },
        openRoutedAppShortcut: (
          payload: BrowserLaunchPayload,
          boundary: BrowserPrivateBoundaryRouteParams
        ): void => {
          this.appShortcutNavigationCoordinator.openShortcut(payload.appShortcut, boundary)
            .then((result: AiraAppShortcutNavigationResult): void => {
              if (!result.handled) {
                this.errorMessage = `打开快捷入口失败：${result.errorMessage}`;
              }
            });
        },
        showToast: (message: string): void => {
          this.showNativeToast(message);
        },
        publishHelper: (message: string): void => {
          this.helperMessage = message;
        }
      }
    );
  private tabsOverviewSessionCoordinator: BrowserTabsOverviewSessionCoordinator =
    new BrowserTabsOverviewSessionCoordinator(
      this.tabManager,
      this.browserPrivateTabCoordinator,
      this.browserTabSwitchCoordinator,
      this.browserTabHomeCoordinator,
      this.browserTabCloseCoordinator,
      (): Promise<void> => this.restorePersistedTabPreviews(),
      TABS_OVERVIEW_DEBUG_SNAPSHOT_EXPORT_ENABLED,
      {
        privateModeLockCoordinator: this.browserPrivateModeLockCoordinator,
        privateProfileLifecycleCoordinator: this.browserPrivateProfileLifecycleCoordinator,
        privateProfileCookieLifecycleHost: this.browserPrivateProfileCookieLifecycleHost,
        hostedRuntimeSurfacePort: this.browserHostedRuntimeSurfacePort,
        webTopImmersionSessionCoordinator: this.browserWebTopImmersionSessionCoordinator,
        backgroundOpenPromptCoordinator: this.browserBackgroundOpenPromptCoordinator
      },
      {
        previewCoordinator: this.browserTabPreviewCoordinator,
        snapshotPipelineCoordinator: this.tabsOverviewSnapshotPipelineCoordinator,
        hostedWebLayerPresentationViewModel: this.browserHostedWebLayerPresentationViewModel
      },
      () => this.browserTabsOverviewSessionHost
    );
  private browserHomePresentationSessionCoordinator: BrowserHomePresentationSessionCoordinator =
    new BrowserHomePresentationSessionCoordinator(
      this.browserHomePresentationViewModel,
      this.tabsOverviewSessionCoordinator,
      this.browserHomePresentationSessionHost
    );
  private browserControllerAttachmentRuntimeCoordinator: BrowserControllerAttachmentRuntimeCoordinator =
    new BrowserControllerAttachmentRuntimeCoordinator(
      this.webControllerBootstrapper,
      this.browserRuntimeLifecyclePort,
      this.browserHostedRuntimeSurfacePort,
      this.browserFaultClassifier,
      this.browserWebActiveSurfaceCoordinator,
      this.browserWebActiveSurfaceActionExecutor,
      this.browserWebActiveSurfaceHost,
      this.browserWebTabsController,
      this.browserControllerAttachmentRuntimeCoordinatorHost
    );
  private browserActiveRuntimeSyncCoordinator: BrowserActiveRuntimeSyncCoordinator =
    new BrowserActiveRuntimeSyncCoordinator(
      CONTROLLER_ATTACH_RESTORE_FALLBACK_DELAY_MS,
      {
        runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
        hostedRuntimeSurfacePort: this.browserHostedRuntimeSurfacePort,
        runtimeMutationPort: this.browserRuntimeMutationPort,
        controllerAttachmentRuntimeCoordinator: this.browserControllerAttachmentRuntimeCoordinator,
        activeSurfaceCoordinator: this.browserWebActiveSurfaceCoordinator,
        webRecoveryManager: this.webRecoveryManager,
        webEventRouter: this.webEventRouter,
        visibleUrlService: this.telegramWebCompatibilityService,
        activeTabRuntimeRestoreCoordinator: this.browserActiveTabRuntimeRestoreCoordinator,
        sink: this.browserActiveRuntimeSyncSink
      }
    );
  private browserWebHistoryCommandRuntimeCoordinator: BrowserWebHistoryCommandRuntimeCoordinator =
    new BrowserWebHistoryCommandRuntimeCoordinator(
      {
        webTabsController: this.browserWebTabsController,
        pageFindCoordinator: this.browserPageFindCoordinator,
        contextMenuCoordinator: this.webContextMenuCoordinator,
        fullscreenSessionCoordinator: this.browserFullscreenSessionCoordinator,
        quickSearchSwitchingCoordinator: this.browserQuickSearchSwitchingCoordinator
      },
      {
        resolveActiveTabId: (): string => this.activeTabId,
        showNativeToast: (message: string): void => this.showNativeToast(message),
        showKeyboardShortcutMessage: (message: string): void => this.showKeyboardShortcutMessage(message)
      }
    );
  private browserKeyboardShortcutCoordinator: BrowserKeyboardShortcutCoordinator =
    new BrowserKeyboardShortcutCoordinator(
      {
        routeCoordinator: this.browserShellRouteCoordinator,
        tabSwitchCoordinator: this.browserTabSwitchCoordinator,
        tabCloseCoordinator: this.browserTabCloseCoordinator,
        activeTabRuntimeRestoreCoordinator: this.browserActiveTabRuntimeRestoreCoordinator,
        tabsOverviewSessionCoordinator: this.tabsOverviewSessionCoordinator,
        webHistoryCommandRuntimeCoordinator: this.browserWebHistoryCommandRuntimeCoordinator,
        webTabsController: this.browserWebTabsController,
        offlinePageSaveCoordinator: this.offlinePageSaveCoordinator,
        recentActionManager: this.browserRecentActionManager,
        pageFindCoordinator: this.browserPageFindCoordinator,
        foregroundTabCreationCoordinator: this.browserForegroundTabCreationCoordinator,
        windowContextCoordinator: this.browserWindowContextCoordinator,
        fullscreenSessionCoordinator: this.browserFullscreenSessionCoordinator,
        homeUrl: HOME_TAB_URL,
        newTabTitle: '新标签页'
      },
      {
        readFacts: (): BrowserKeyboardShortcutFacts => {
          return {
            showHomePage: this.showHomePage,
            showTabsSheet: this.showTabsSheet,
            fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled,
            webBottomAddressFocused: this.webBottomAddressFocused,
            homeSearchFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
            activeTabId: this.activeTabId,
            tabs: this.tabs,
            recentlyClosedCount: this.recentlyClosedApplicationSnapshot.recordCount,
            controllerAttached: this.controllerAttached,
            loading: this.shouldShowWebLoadingProgress()
          };
        },
        showMessage: (message: string): void => this.showKeyboardShortcutMessage(message),
        focusAddressBar: (): void => {
          BrowserSearchInvocationRuntime.triggers(this.getWindowScopeId()).keyboard.open();
        },
        setTabsOverviewVisible: (visible: boolean): void => {
          if (visible) {
            void this.openTabsOverview();
            return;
          }
          this.dispatchTabsOverviewSession({ type: 'request_close' });
        },
        releaseAddressFocus: (homePage: boolean): void => {
          if (this.browserShellPresentationOperations?.surface() === 'large_screen') {
            BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'explicit_exit');
            return;
          }
          if (homePage) {
            this.browserShellSearchInvocationAdapter.releaseHomeSearchFocus();
            this.rootBottomAddressPanelDetent = 'low';
            this.syncBottomPanelStatusBarStyle();
            return;
          }
          this.browserRootBottomPanelSessionCoordinator.restoreScrollPresentation();
          this.setWebBottomAddressFocused(false);
          this.webBottomAddressDraft = '';
          this.rootBottomAddressPanelDetent = 'low';
          this.syncBottomPanelStatusBarStyle();
          this.browserWebTopImmersionSessionCoordinator.requestVisible('shortcut-address-blur');
        },
        bookmarkCurrentPage: (): void => this.browserRootBottomPanelActionApplication.toggleCurrentPageBookmark()
      }
    );
  private browserLargeScreenWebZoomCoordinator: BrowserLargeScreenWebZoomCoordinator =
    new BrowserLargeScreenWebZoomCoordinator(
      this.browserRuntimeLifecyclePort,
      this.browserHostedRuntimeSurfacePort,
      (): void => {
        this.largeScreenWebZoomRevision += 1;
      }
    );
  private browserLargeScreenShellIntentApplication: BrowserLargeScreenShellIntentApplication =
    new BrowserLargeScreenShellIntentApplication({
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      tabCloseCoordinator: this.browserTabCloseCoordinator,
      recentlyClosedApplicationCoordinator: this.browserRecentlyClosedApplicationCoordinator,
      foregroundTabCreationCoordinator: this.browserForegroundTabCreationCoordinator,
      appUrlOpenCoordinator: this.browserAppUrlOpenCoordinator,
      windowContextCoordinator: this.browserWindowContextCoordinator,
      webHistoryCommandRuntimeCoordinator: this.browserWebHistoryCommandRuntimeCoordinator,
      activeTabRuntimeRestoreCoordinator: this.browserActiveTabRuntimeRestoreCoordinator,
      webTabsController: this.browserWebTabsController,
      addressSubmissionCoordinator: this.addressSubmissionCoordinator,
      searchSuggestionCoordinator: this.browserSearchSuggestionCoordinator,
      searchInvocationHost: {
        resolveSceneFacts: () => ({
          homeScene: this.showHomePage,
          webSceneVisible: this.isWebPageVisible(),
          editableWebAddress: this.resolveEditableWebBottomAddress()
        }),
        publishPresentation: (presentation: BrowserLargeScreenOmniboxPresentation): void => {
          this.browserLargeScreenOmniboxPresentation = presentation;
        }
      },
      webZoomCoordinator: this.browserLargeScreenWebZoomCoordinator,
      tabHomeCoordinator: this.browserTabHomeCoordinator,
      resolveRootBottomPanelActionApplication: (): BrowserRootBottomPanelFixedActionApplication =>
        this.browserRootBottomPanelActionApplication,
      siteControlsRuntimeCoordinator: this.browserSiteControlsRuntimeCoordinator,
      homeUrl: HOME_TAB_URL,
      newTabTitle: '新标签页',
      openOverflow: (): void => {
        void this.openTabsOverview();
      },
      dispatchBrowserAction: (actionId: BrowserBottomAddressPanelActionId): void =>
        this.dispatchRootBottomPanelAction('panel', actionId),
      requestBrowserBack: (): void => {
        this.browserMainBackCoordinator.onBackPress(this.browserMainBackHost);
      },
      presentWebZoom: (snapshot: BrowserLargeScreenWebZoomSnapshot): void => {
        this.largeScreenWebZoomDialogSnapshot = snapshot;
        this.largeScreenWebZoomDialogController.open();
      },
      updateWebZoom: (snapshot: BrowserLargeScreenWebZoomSnapshot): void => {
        this.largeScreenWebZoomDialogSnapshot = snapshot;
      },
      dismissWebZoom: (): void => this.largeScreenWebZoomDialogController.close(),
      readFacts: () => {
        return {
          windowId: this.getWindowScopeId(),
          activeTabId: this.activeTabId,
          loading: this.shouldShowWebLoadingProgress(),
          selectedSearchEngine: this.selectedSearchEngine,
          largeScreenShellActive:
            this.browserShellPresentationOperations?.snapshot()?.shellFamily === 'large_screen'
        };
      }
    });
  private browserShellSearchInvocationHost: BrowserShellSearchInvocationHost = {
    resolveSceneFacts: () => ({
      homeScene: this.showHomePage,
      webSceneVisible: this.isWebPageVisible(),
      editableWebAddress: this.resolveEditableWebBottomAddress(),
      homeCreateOptions: this.browserWindowContextCoordinator.resolveCurrentTabSessionBoundary()
    }),
    resolveAddressSessionSnapshot: (): BrowserRootAddressInputSessionSnapshot =>
      this.buildRootAddressInputSessionSnapshot(),
    applyDraft: (scene: 'home' | 'web', draft: string): void => {
      if (scene === 'home') {
        this.addressInput = draft;
      } else {
        this.webBottomAddressDraft = draft;
      }
    },
    applySearchChromePlan: (plan: BrowserRootBottomPanelChromePlan): void => {
      this.applyRootBottomPanelSessionChromePlan(plan);
    },
    suspendSearch: (): void => {
      this.releaseRootBottomAddressInputKeyboardAvoidMode();
    }
  };
  private browserShellSearchInvocationAdapter: BrowserShellSearchInvocationAdapter =
    new BrowserShellSearchInvocationAdapter(
      this.browserRootBottomPanelSessionCoordinator,
      this.browserSearchSuggestionCoordinator,
      this.browserTabHomeCoordinator,
      this.browserKeyboardShortcutCoordinator,
      this.browserShellSearchInvocationHost
    );
  private browserSearchInvocationSurfaceConnection: BrowserSearchInvocationSurfaceConnection =
    new BrowserSearchInvocationSurfaceConnection(this.browserShellSearchInvocationAdapter);
  private webAppearancePolicy: WebAppearancePolicy = resolveWebAppearancePolicy();
  private browserUserAgentService: BrowserUserAgentService = new BrowserUserAgentService();
  private browserBrowsingIdentityPolicyCoordinator: BrowserBrowsingIdentityPolicyCoordinator =
    new BrowserBrowsingIdentityPolicyCoordinator(
      sharedBrowserUserAgentSettingsRepository,
      sharedSavedSiteSettingRepository,
      this.browserUserAgentService
    );
  private browserPullRefreshShell: BrowserPullRefreshShell = {
    readSurfaceFacts: (activeTab?: BrowserTabState): BrowserPullRefreshSurfaceFacts => {
      const presentation = this.browserShellPresentationOperations?.snapshot();
      return {
        enabled: this.webScrollExperimentSettings.pullRefreshEnabled,
        activeTab: activeTab ?? this.tabManager.getTab(this.tabs, this.activeTabId),
        fallbackActiveTabId: this.activeTabId,
        fallbackPageUrl: this.tabScopedEventContextCoordinator.resolvePageUrl(this.activeTabId),
        showHomePage: this.showHomePage,
        showTabsSheet: this.showTabsSheet,
        webPageVisible: this.isWebPageVisible() && !this.shouldSuspendHostedWebSurface(),
        pageErrorSurfaceVisible: this.shouldRenderWebPageErrorSurface(),
        shellFamily: presentation?.shellFamily ?? 'phone',
        inputProfile: presentation?.largeScreenWindowFacts?.inputProfile ?? 'touch'
      };
    },
    publishState: (state: BrowserPullRefreshState): void => {
      this.pullRefreshState = state;
      this.pullRefreshRefreshing = state.refreshInFlight;
    },
    prepareRootChromeForReload: (): void => {
      this.applyRootBottomPanelSessionChromePlan(
        this.browserRootBottomPanelSessionCoordinator.buildPullRefreshRestorePlan(
          this.buildRootBottomPanelSessionSnapshot()
        )
      );
    }
  };
  private browserPullRefreshCoordinator: BrowserPullRefreshCoordinator = new BrowserPullRefreshCoordinator(
    this.browserActiveTabRuntimeRestoreCoordinator,
    this.browserPullRefreshShell
  );
  private browserWebPageLifecycleApplicationCoordinator: BrowserWebPageLifecycleApplicationCoordinator =
    new BrowserWebPageLifecycleApplicationCoordinator({
      visibleUrlService: this.telegramWebCompatibilityService,
      webEventRouter: this.webEventRouter,
      webRuntimeBridge: this.webRuntimeBridge,
      commitCoordinator: this.browserWebEventCommitCoordinator,
      recoveryManager: this.webRecoveryManager,
      downloadNavigationStateCoordinator: this.browserDownloadNavigationStateCoordinator,
      errorDocumentLoadShell: this.browserErrorDocumentLoadShell,
      loadFailureSurfaceCoordinator: this.browserWebLoadFailureSurfaceCoordinator,
      offlineFastFailureCoordinator: this.browserOfflineFastFailureCoordinator,
      webLoadRuntimeCoordinator: this.browserWebLoadRuntimeCoordinator,
      activeTabRuntimeRestoreCoordinator: this.browserActiveTabRuntimeRestoreCoordinator,
      addressSubmissionCoordinator: this.addressSubmissionCoordinator,
      appUrlOpenCoordinator: this.browserAppUrlOpenCoordinator,
      recentActionManager: this.browserRecentActionManager,
      searchEngineRepository: sharedSearchEngineRepository,
      preferencesRepository: sharedPreferencesRepository,
      quickSearchSwitchingCoordinator: this.browserQuickSearchSwitchingCoordinator,
      webTabsController: this.browserWebTabsController,
      webpageTranslationCoordinator: this.webpageTranslationCoordinator,
      pageFindCoordinator: this.browserPageFindCoordinator,
      elementInspectionSessionCoordinator: this.elementInspectionSessionCoordinator,
      navigationStateSyncCoordinator: this.browserWebNavigationStateSyncCoordinator,
      runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
      webScrollSmoothModeService: this.webScrollSmoothModeService,
      sessionStateStore: this.webSessionStateStore,
      historyApiBridgePolicy: this.browserHistoryApiBridgePolicy,
      mediaDiscoveryCoordinator: this.browserMediaDiscoveryCoordinator,
      mediaDiscoveryHost: this.browserMediaDiscoveryHost,
      backgroundTabPreviewRuntimeCoordinator: this.browserBackgroundTabPreviewRuntimeCoordinator,
      backgroundSessionSyncCoordinator: this.browserTabBackgroundSessionSyncCoordinator,
      arkWebMediaTakeoverCoordinator: this.arkWebMediaTakeoverCoordinator,
      mediaRuntimeObservationCoordinator: this.browserMediaRuntimeObservationApplicationCoordinator,
      pullRefreshCoordinator: this.browserPullRefreshCoordinator,
      backgroundOpenPromptCoordinator: this.browserBackgroundOpenPromptCoordinator,
      hostedRuntimeSurfacePort: this.browserHostedRuntimeSurfacePort,
      faultClassifier: this.browserFaultClassifier,
      runtimeMutationPort: this.browserRuntimeMutationPort,
      controllerAttachmentRuntimeCoordinator: this.browserControllerAttachmentRuntimeCoordinator,
      activeSurfaceCoordinator: this.browserWebActiveSurfaceCoordinator,
      historyVisitPersistenceCoordinator: this.browserHistoryVisitPersistenceCoordinator,
      tabManager: this.tabManager,
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      faviconHost: this.browserFaviconApplyHost,
      privateProfileLifecycleCoordinator: this.browserPrivateProfileLifecycleCoordinator,
      privateProfileCookieLifecycleHost: this.browserPrivateProfileCookieLifecycleHost,
      featureEffectsDependencies: {
        tabManager: this.tabManager,
        adBlockCoordinator: this.browserAdBlockCoordinator,
        siteControlsRuntimeCoordinator: this.browserSiteControlsRuntimeCoordinator,
        mediaDiscoveryCoordinator: this.browserMediaDiscoveryCoordinator,
        mediaDiscoveryHost: this.browserMediaDiscoveryHost,
        pageChromeThemeSamplingCoordinator: this.browserPageChromeThemeSamplingCoordinator,
        privateProfileLifecycleCoordinator: this.browserPrivateProfileLifecycleCoordinator,
        privateProfileCookieLifecycleHost: this.browserPrivateProfileCookieLifecycleHost,
        backgroundTabPreviewRuntimeCoordinator: this.browserBackgroundTabPreviewRuntimeCoordinator,
        runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
        preferencesRepository: sharedPreferencesRepository,
        manualElementHideRuntimeCoordinator: this.manualElementHideRuntimeCoordinator,
        userScriptRuntimeCoordinator: this.userScriptRuntimeCoordinator,
        tabScopedEventContextCoordinator: this.tabScopedEventContextCoordinator,
      },
      webAppSessionCoordinator: this.webAppSessionCoordinator,
      webAppCurrentUrlService: this.webAppCurrentUrlService,
      offlinePageSaveCoordinator: this.offlinePageSaveCoordinator,
      tabHomeCoordinator: this.browserTabHomeCoordinator,
      addressDisplayCoordinator: this.browserAddressDisplayCoordinator,
      shellStateCoordinator: this.browserShellStateCoordinator,
      topImmersionSessionCoordinator: this.browserWebTopImmersionSessionCoordinator,
      resolveWebScrollInteractionCoordinator: (): BrowserWebScrollInteractionCoordinator =>
        this.browserWebScrollInteractionCoordinator,
      resolveBottomChromeScrollCoordinator: (): BrowserBottomChromeScrollCoordinator =>
        this.browserBottomChromeScrollCoordinator,
      unifiedLinkApplicationCoordinator: this.browserUnifiedLinkApplicationCoordinator,
      tabSessionPersistenceCoordinator: this.browserTabSessionPersistenceCoordinator,
      webStateSnapshotStore: this.webStateSnapshotStore,
      tabRecoveryCoordinator: this.browserTabRecoveryCoordinator,
      snapshotApplicationHost: this.browserSnapshotApplicationHost,
      pageChromeThemeSamplingCoordinator: this.browserPageChromeThemeSamplingCoordinator,
      httpsFirstPromptCoordinator: this.browserWebCapabilityPromptApplicationCoordinator,
      urlThreatProtectionCoordinator: this.browserUrlThreatProtectionCoordinator,
      loadingProgressTerminalHoldMs: WEB_LOADING_PROGRESS_TERMINAL_HOLD_MS,
      metadataVisualUpdateDelayMs: WEB_SCROLL_PAGE_METADATA_VISUAL_UPDATE_DELAY_MS,
      pageEventFallbackUrl: NEW_WINDOW_TEST_URL,
      host: this.browserWebPageLifecycleApplicationHost
    });
  private webTextZoomViewModel: BrowserWebTextZoomViewModel = new BrowserWebTextZoomViewModel();
  private siteReportDialogViewModel: SiteReportDialogViewModel = new SiteReportDialogViewModel();
  private releaseNoticePresentationCoordinator: ReleaseNoticePresentationCoordinator =
    new ReleaseNoticePresentationCoordinator(
      sharedReleaseNoticeCoordinator,
      this.browserTransientSurfaceCoordinator,
      this.appReviewPromptCoordinator,
      this.browserShellRouteCoordinator,
      {
        resolveFacts: (): ReleaseNoticePresentationShellFacts => {
          return {
            context: this.getUIContext().getHostContext() as common.Context,
            homeVisible: this.showHomePage,
            privateMode: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
            appVisible: this.isBrowserShellVisible,
            shellFamily: this.browserShellPresentationOperations?.snapshot()?.shellFamily,
            promptBlockingFacts: this.buildTransientPromptBlockingFacts()
          };
        },
        publishState: (state: ReleaseNoticeUiState): void => {
          this.releaseNoticeState = state;
        }
      }
    );
  private siteCustomizationRuntimeRefreshCoordinator: SiteCustomizationRuntimeRefreshCoordinator =
    new SiteCustomizationRuntimeRefreshCoordinator();
  private browserUserAgentActionSink: BrowserUserAgentActionSink = {
    resolveFacts: (): BrowserUserAgentActionFacts => {
      const activeTab = this.tabManager.getTab(this.tabs, this.activeTabId);
      return {
        activeTabId: this.activeTabId,
        activeTabIsWebPage: activeTab !== undefined && !activeTab.isHome,
        currentUrl: this.resolveCurrentWebPageActionUrl(),
        profileId: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().profileId,
        privateTabIds: this.tabs
          .filter((tab: BrowserTabState) => this.tabScopedEventContextCoordinator.isBoundaryPrivate(
            tab.privacyMode,
            tab.dataScope
          ))
          .map((tab: BrowserTabState) => tab.id)
      };
    },
    publishPresentation: (presentation: BrowserUserAgentActionPresentation): void => {
      this.browserUserAgentActionPresentation = presentation;
    },
    confirmRisk: (
      notice: BrowserUserAgentRiskNotice,
      onConfirm: () => void,
      onCancel?: () => void
    ): void => {
      this.browserNativeAlertDialogPresenter.confirm({
        title: notice.title,
        message: notice.message,
        cancelLabel: notice.cancelText,
        confirmLabel: notice.confirmText,
        onCancel: onCancel,
        onConfirm: onConfirm
      });
    },
    showToast: (message: string): void => this.showNativeToast(message)
  };
  private browserUserAgentRuntimeTransitionHost: BrowserUserAgentRuntimeTransitionHost = {
    resolveActiveTab: (): BrowserTabState | undefined => {
      return this.tabManager.getActiveTab(this.tabs, this.activeTabId);
    },
    applyActiveRuntimeController: (tab: BrowserTabState, runtime: WebTabRuntimeRecord): void => {
      this.webController = runtime.controller;
      this.controllerAttached = false;
      this.browserHostedRuntimeSurfacePort.syncActiveFromHost(tab, runtime);
    },
    recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
      this.recordRuntimeEvent(type, message, tabId);
    }
  };
  private browserUserAgentRuntimeTransitionCoordinator: BrowserUserAgentRuntimeTransitionCoordinator =
    new BrowserUserAgentRuntimeTransitionCoordinator({
      webTabsController: this.browserWebTabsController,
      snapshotStore: this.webStateSnapshotStore,
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
      hostedRuntimeSurfacePort: this.browserHostedRuntimeSurfacePort,
      quickSearchReloadOwner: this.browserQuickSearchSwitchingCoordinator
    }, this.browserUserAgentRuntimeTransitionHost);
  private browserUserAgentRuntimePolicyCoordinator: BrowserUserAgentRuntimePolicyCoordinator =
    new BrowserUserAgentRuntimePolicyCoordinator({
      activeTabRuntimeRestoreCoordinator: this.browserActiveTabRuntimeRestoreCoordinator,
      quickSearchReloadOwner: this.browserQuickSearchSwitchingCoordinator,
      userAgentRuntimeService: this.browserUserAgentRuntimeService,
      runtimeTransitionCoordinator: this.browserUserAgentRuntimeTransitionCoordinator,
      browsingIdentityPolicyCoordinator: this.browserBrowsingIdentityPolicyCoordinator
    }, {
      resolveFacts: () => this.browserUserAgentActionSink.resolveFacts()
    });
  private browserUserAgentActionCoordinator: BrowserUserAgentActionCoordinator =
    new BrowserUserAgentActionCoordinator(
      sharedBrowserUserAgentSettingsRepository,
      this.browserUserAgentService,
      this.browserWebPageToolsCoordinator,
      this.browserUserAgentRuntimePolicyCoordinator,
      this.browserBrowsingIdentityPolicyCoordinator,
      this.browserUserAgentActionSink
    );
  @State browserUserAgentActionPresentation: BrowserUserAgentActionPresentation =
    this.browserUserAgentActionCoordinator.snapshot();
  private siteCustomizationRefreshSignal: SiteCustomizationRefreshSignal = new SiteCustomizationRefreshSignal();
  @StorageLink(SITE_CUSTOMIZATION_REFRESH_REVISION_KEY) @Watch('handleSiteCustomizationRefreshRevisionChange')
  private siteCustomizationRefreshRevision: number = 0;
  @StorageLink(BROWSER_EXPERIMENT_SETTINGS_REFRESH_REVISION_KEY) @Watch('refreshActivePageExperimentRuntimes')
  private browserExperimentSettingsRefreshRevision: number = 0;
  @StorageLink(BROWSER_TAB_PREVIEW_LIFECYCLE_CAPTURE_REVISION_KEY)
  @Watch('handleTabPreviewLifecycleCaptureRevisionChange')
  private tabPreviewLifecycleCaptureRevision: number = 0;
  @StorageLink(BROWSER_SYSTEM_MEMORY_PRESSURE_REVISION_KEY)
  @Watch('handleSystemMemoryPressureRevisionChange')
  private systemMemoryPressureRevision: number = 0;
  @State browserFullscreenSessionPresentation: BrowserFullscreenSessionPresentation =
    this.browserFullscreenSessionCoordinator.snapshot();
  @State webTextZoomRatio: number = 100;
  @State privateModeConfirmationState: BrowserPrivateModeConfirmationState =
    this.browserPrivateTabCoordinator.buildModeSwitchConfirmationState({
      target: 'confirm_enter_private'
    }, 0);
  @State privateModeClearDataSelected: boolean = false;
  @StorageProp(BROWSER_SYSTEM_FONT_SIZE_SCALE_STORAGE_KEY) @Watch('handleSystemFontSizeScaleChange')
  private systemFontSizeScale: number = 1;
  @State webTextZoomActionVersion: number = 0;
  @State webTextZoomSheetState: BrowserWebTextZoomState =
    this.webTextZoomViewModel.buildState(this.webTextZoomRatio);
  @State largeScreenWebZoomDialogSnapshot: BrowserLargeScreenWebZoomSnapshot =
    createBrowserLargeScreenWebZoomSnapshot();
  @State themeModeActionVersion: number = 0;
  @State arkWebMediaTakeoverRevision: number = 0;
  @State gestureOnboardingPromptState: BrowserGestureOnboardingTopPromptState =
    HIDDEN_BROWSER_GESTURE_ONBOARDING_TOP_PROMPT_STATE;
  @State urlThreatNoticeState: BrowserUrlThreatNoticeState = HIDDEN_BROWSER_URL_THREAT_NOTICE_STATE;
  private webRuntimeBootstrapConfig: WebControllerBootstrapConfig = {};
  private webController: webview.WebviewController = this.webRuntimeBridge.createController();
  private customHomepageHostedWebNode: CustomHomepageHostedWebNodeController | undefined = undefined;
  private webTextZoomDialogController: CustomDialogController = new CustomDialogController({
    builder: BrowserWebTextZoomSheet({
      state: $webTextZoomSheetState,
      onAction: (action: BrowserWebTextZoomAction): void => {
        this.applyWebTextZoomAction(action);
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true
  });
  private largeScreenWebZoomDialogController: CustomDialogController = new CustomDialogController({
    builder: BrowserLargeScreenWebZoomDialog({
      snapshot: $largeScreenWebZoomDialogSnapshot,
      onAction: (action: BrowserLargeScreenWebZoomAction): void => {
        this.browserLargeScreenShellIntentApplication.dispatchNavigation({
          kind: 'web_zoom',
          text: '',
          zoomAction: action
        });
      },
      onClose: (): void => {
        this.browserLargeScreenShellIntentApplication.handleWebZoomDialogDismissed();
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true,
    onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
      this.browserLargeScreenShellIntentApplication.handleWebZoomDialogDismissed();
      dismissDialogAction.dismiss();
    }
  });
  private privateModeConfirmationDialogController: CustomDialogController = new CustomDialogController({
    builder: BrowserPrivateModeConfirmationDialog({
      confirmation: $privateModeConfirmationState,
      clearPrivateData: $privateModeClearDataSelected,
      cancel: (): void => {
        this.privateModeClearDataSelected = false;
      },
      confirm: (): void => {
        void this.browserPrivateTabCoordinator.confirmModeSwitch(
          this.privateModeConfirmationState,
          this.privateModeClearDataSelected,
          this.browserPrivateModeConfirmationHost
        );
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: false
  });
  private editHomeShortcutDialogController: CustomDialogController = new CustomDialogController({
    builder: HomeShortcutEditDialog({
      draft: $homeShortcutEditDraft,
      confirm: () => {
        this.homeShortcutStateCoordinator.handleUserAction({
          type: 'confirm_edit_shortcut',
          draft: this.homeShortcutEditDraft
        });
      }
    }),
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true
  });
  private desktopShortcutNameDialogController: CustomDialogController = new CustomDialogController({
    builder: DesktopShortcutNameDialog({
      snapshot: $webAppInstallDialogSnapshot,
      onAction: (action: WebAppInstallDialogAction): void => {
        this.webAppInstallCoordinator.handleDialogAction(action);
      }
    }),
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true,
    onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
      void this.webAppInstallCoordinator.handleDialogDismissed();
      dismissDialogAction.dismiss();
    }
  });
  private webPromptDialogController: CustomDialogController = new CustomDialogController({
    builder: BrowserShellWebPromptDialog({
      presentation: $webPromptDialogPresentation,
      confirm: (value: string) => {
        this.browserWebCapabilityPromptApplicationCoordinator.confirmJavaScriptPrompt(value);
      },
      cancel: () => {
        this.browserWebCapabilityPromptApplicationCoordinator.cancelJavaScriptPrompt();
      }
    }),
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: false
  });
  private httpAuthDialogController: CustomDialogController = new CustomDialogController({
    builder: BrowserShellHttpAuthDialog({
      presentation: $httpAuthDialogPresentation,
      confirm: (username: string, password: string) => {
        this.browserWebCapabilityPromptApplicationCoordinator.confirmHttpAuth(username, password);
      },
      cancel: () => {
        this.browserWebCapabilityPromptApplicationCoordinator.cancelHttpAuth();
      }
    }),
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: false
  });
  private siteReportDialogController: CustomDialogController = new CustomDialogController({
    builder: SiteReportDialog({
      selectedReasonId: $siteReportReasonId,
      remark: $siteReportRemark,
      reasons: this.siteReportDialogViewModel.buildReasonOptions(),
      confirm: () => {
        this.confirmSiteReport();
      }
    }),
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true
  });
  private documentViewerFileInfoDialogController: CustomDialogController = new CustomDialogController({
    builder: DocumentViewerFileInfoDialog({
      fileInfo: $documentViewerFileInfoDialogInfo
    }),
    alignment: DialogAlignment.Center,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true
  });
  private readerSpeechVoiceDialogController: CustomDialogController = new CustomDialogController({
    builder: ReaderSpeechVoiceDialog({
      presentation: $readerSpeechVoiceDialogPresentation,
      onSelectVoiceId: (voiceId: string) => {
        void this.articleReadingSession.selectSpeechVoiceById(voiceId);
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true
  });
  @State addressInput: string = '';
  @State currentUrl: string = '';
  @State pendingWebUrl: string = '';
  @State currentTitle: string = 'Aira';
  @State @Watch('reconcileShellTabPresentation') showHomePage: boolean = true;
  @State coldStartDeferredSurfaceContentMounted: boolean = false;
  private coldStartDeferredContentMountGeneration: number = 0;
  // Once the Home surface has painted, keep it resident behind web tabs so opening
  // the tabs overview never rebuilds it (that rebuild is ~100ms on the entry frame).
  // Deferring until the first Home paint avoids adding that cost to a cold start
  // that restores straight into a web tab.
  private homeSurfacePaintedOnce: boolean = false;
  @State homeWallpaperState: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @State @Watch('syncRootBottomPanelBackAvailability') canGoBack: boolean = false;
  @State canGoForward: boolean = false;
  @State isLoading: boolean = false;
  @State controllerAttached: boolean = false;
  @State helperMessage: string = '在这里输入网址或关键词，直接开始浏览。';
  @State rootBottomPanelPresentationSnapshot: BrowserRootBottomPanelPresentationSnapshot =
    this.browserRootBottomPanelSessionCoordinator.getPresentationSnapshot();
  @State errorMessage: string = '';
  @State showPageErrorSurface: boolean = false;
  @State holdPageErrorSurfaceDuringReload: boolean = false;
  @State activeErrorDocumentRetryTabId: string = '';
  @State tabCount: number = 0;
  @State selectedSearchEngine: SearchEngineId = 'bing';
  @State availableSearchEngines: SearchEngineRecord[] = sharedSearchEngineRepository.listEngines();
  @StorageLink(SEARCH_ENGINE_SETTINGS_REVISION_KEY) @Watch('handleSearchEngineSettingsRevisionChange')
  private searchEngineSettingsRevision: number = 0;
  @StorageLink(QUICK_SEARCH_SWITCHING_PREFERENCES_REVISION_KEY)
  @Watch('handleQuickSearchSwitchingPreferencesRevisionChange')
  private quickSearchSwitchingPreferencesRevision: number = 0;
  @State quickSearchSwitchingPresentation: BrowserQuickSearchSwitchingPresentation =
    createHiddenBrowserQuickSearchSwitchingPresentation();
  @State webpageTranslationApplicationSnapshot: WebpageTranslationApplicationSnapshot =
    this.webpageTranslationCoordinator.getApplicationSnapshot();
  @State webContextMenuPresentation: WebContextMenuPresentation =
    this.webContextMenuCoordinator.createHiddenPresentation();
  @State backgroundOpenPromptState: BrowserBackgroundOpenPromptState =
    this.browserBackgroundOpenPromptCoordinator.getSnapshot();
  @State readerModeSessionSnapshot: ReaderModeSessionSnapshot = this.articleReadingSession.getSessionSnapshot();
  @State novelReaderSnapshot: NovelReaderSnapshot = createDefaultNovelReaderSnapshot();
  @State readerSpeechVoiceDialogPresentation: ReaderModeSpeechVoiceDialogPresentation =
    this.readerModeSessionSnapshot.speech.voiceDialog;
  @State pendingDownloadPrompt?: PendingDownloadPromptState = undefined;
  @State browserUserScriptApplicationSnapshot: BrowserUserScriptApplicationSnapshot =
    this.browserUserScriptApplicationCoordinator.getSnapshot();
  @State featureGateSnapshot: FeatureGateSnapshot = this.featureGateCoordinator.getSnapshot();
  @State phoneSystemSheetVisible: boolean = false;
  @State homeShortcutSelectionState: HomeShortcutSelectionState =
    this.homeShortcutStateCoordinator.getSelectionSnapshot();
  @State browserQrScanSessionSnapshot: BrowserQrScanSessionSnapshot =
    DEFAULT_BROWSER_QR_SCAN_SESSION_SNAPSHOT;
  @State releaseNoticeState: ReleaseNoticeUiState = this.releaseNoticePresentationCoordinator.getSnapshot();
  @State clientUpdatePolicyState: ClientUpdatePolicyState = sharedClientUpdatePolicyService.getSnapshot();
  @StorageProp(AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_REVISION_KEY) @Watch('refreshAiraCloudBookmarkV4BootstrapState')
  private airaCloudBookmarkV4BootstrapRevision: number = 0;
  @State private airaCloudBookmarkV4BootstrapState: AiraCloudBookmarkV4BootstrapViewState =
    sharedAiraCloudBookmarkV4BootstrapRuntime.getViewState();
  @State mediaResourceSessionSnapshot: BrowserMediaResourceSessionSnapshot =
    createBrowserMediaResourceSessionSnapshot();
  @State showTabsSheet: boolean = false;
  @State tabsOverviewPresentationState: BrowserTabsOverviewSessionPresentationState =
    this.tabsOverviewSessionCoordinator.getPresentationState();
  @State tabsSharedSnapshotState: BrowserTabsSharedSnapshotTransitionState =
    this.tabsOverviewPresentationState.sharedSnapshotState;
  @State tabsOverviewSnapshotPipelineState: BrowserTabsOverviewSnapshotPipelineState =
    this.tabsOverviewSnapshotPipelineCoordinator.buildIdleState();
  @State rootViewportLeft: number = 0;
  @State rootViewportTop: number = 0;
  @State rootViewportWidth: number = 390;
  @State rootViewportHeight: number = 844;
  @StorageLink(BROWSER_WINDOW_DISPLAY_VIEWPORT_WIDTH_STORAGE_KEY)
  @Watch('refreshRootBottomPanelLayoutState')
  private browserWindowDisplayViewportWidth: number = 0;
  @StorageLink(BROWSER_WINDOW_DISPLAY_VIEWPORT_HEIGHT_STORAGE_KEY)
  @Watch('refreshRootBottomPanelLayoutState')
  private browserWindowDisplayViewportHeight: number = 0;
  @State private rootBottomPanelLayoutState: BrowserRootBottomPanelLayoutState =
    this.browserRootBottomPanelSessionCoordinator.buildLayoutState({
      viewportWidth: this.rootViewportWidth,
      viewportHeight: this.rootViewportHeight,
      displayViewportWidth: this.browserWindowDisplayViewportWidth,
      displayViewportHeight: this.browserWindowDisplayViewportHeight,
      homeAddressFocused: false,
      webAddressFocused: false
    });
  @State homeTopSafeInsetVp: number = 0;
  @State homeBottomSafeInsetVp: number = 0;
  @State homeLeftSafeInsetVp: number = 0;
  @State homeRightSafeInsetVp: number = 0;
  @State
  @Watch('syncRootAddressKeyboardOverlayInset')
  private rootKeyboardInsetVp: number = 0;
  @State rootAddressKeyboardOverlayInsetVp: number = 0;
  private rootAddressKeyboardHideProtectionUntilMs: number = 0;
  @State hostedWebLayerLeft: number = 0;
  @State hostedWebLayerTop: number = 0;
  @State hostedWebLayerWidth: number = 0;
  @State hostedWebLayerHeight: number = 0;
  @State hostedWebLayerMeasured: boolean = false;
  private restoredWebLayerGeometry?: BrowserWebLayerGeometrySnapshot;
  @State tabPreviewRenderVersion: number = 0;
  // Cached gallery preview states. Refreshed only when previews change
  // (`notifyTabPreviewChanged`) or the sheet is (re)opened; the overlay build then
  // reads this field instead of rebuilding the list on every render pass.
  private tabsOverviewPreviewStates: BrowserTabPreviewState[] = [];
  // Once the tabs overview has been opened it stays mounted (hidden) instead of
  // being torn down, so later opens reuse the built grid/chrome subtree instead of
  // paying for it again. The overlay replays its per-open setup from
  // tabsOverviewOpenRequestVersion.
  private tabsOverviewOverlayResident: boolean = false;
  @State private tabsOverviewOpenRequestVersion: number = 0;
  @State
  @Watch('refreshRootBottomPanelLayoutState')
  browserSearchSuggestionSnapshot: BrowserSearchSuggestionSnapshot =
    this.browserSearchSuggestionCoordinator.getSnapshot();
  @State homepageBackdropAppearanceState: BrowserHomepageBackdropAppearanceState =
    cloneBrowserHomepageBackdropAppearanceState(DEFAULT_BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_STATE);
  @State homePresentationSessionState: BrowserHomePresentationSessionState =
    this.browserHomePresentationSessionCoordinator.getState();
  @State rootBottomAddressPanelDetent: HomeSearchPanelDetent = 'low';
  @State rootBottomPanelImmediateLowDetentRequestVersion: number = 0;
  @State
  @Watch('refreshRootBottomPanelLayoutState')
  webBottomAddressFocused: boolean = false;
  @State webBottomAddressDraft: string = '';
  @State browserLargeScreenOmniboxPresentation: BrowserLargeScreenOmniboxPresentation =
    createBrowserLargeScreenOmniboxPresentation();
  @State webStatusBarVisible: boolean = true;
  @State webViewportVisualTopInset: number = 0;
  @State webViewportPresentation: BrowserWebViewportPresentationState =
    BrowserWebViewportCoordinator.resolvePresentation({
      hostHeightPx: 844,
      visualTopInsetPx: 0,
      fullViewport: false,
      largeScreenShellActive: false,
      nativeVideoTakeoverActive: false
    });
  private webViewportVisualTopInsetInitialized: boolean = false;
  @State siteControlsApplicationSnapshot: BrowserSiteControlsApplicationSnapshot =
    this.browserSiteControlsRuntimeCoordinator.getApplicationSnapshot();
  @State currentWindowId: string = MAIN_WINDOW_ID;
  @State webTopSafeAreaPageBackdropColor: string = '';
  private browserChromeRuntimeState: BrowserChromeRuntimeState = this.browserChromeRuntimeCoordinator.createState();
  private browserBottomChromeScrollCoordinator: BrowserBottomChromeScrollCoordinator =
    new BrowserBottomChromeScrollCoordinator();
  private browserWebScrollInteractionShell: BrowserWebScrollInteractionShell = {
    resolveFacts: () => ({
      activeTabId: this.activeTabId,
      webPageVisible: this.isWebPageVisible(),
      addressFocused: this.webBottomAddressFocused,
      currentDetent: this.rootBottomAddressPanelDetent,
      currentPresentation: this.rootBottomPanelPresentationSnapshot.scrollPresentation,
      tabsSheetVisible: this.showTabsSheet,
      webAppImmersiveMode: this.isWebAppImmersiveMode(),
      fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled,
      smoothModeRuntimeEnabled: this.webScrollSmoothModeRuntimeEnabled,
      experimentSettings: this.webScrollExperimentSettings
    }),
    applyBottomChromeDecision: (decision: BrowserBottomChromeWebScrollDecision): void =>
      this.browserRootBottomPanelSessionCoordinator.applyWebScrollDecision(decision)
  };
  private browserWebScrollInteractionCoordinator: BrowserWebScrollInteractionCoordinator =
    new BrowserWebScrollInteractionCoordinator(
      {
        bottomChromeScrollCoordinator: this.browserBottomChromeScrollCoordinator,
        topImmersionSessionCoordinator: this.browserWebTopImmersionSessionCoordinator,
        recentActionManager: this.browserRecentActionManager,
        scrollPerformanceCoordinator: this.browserScrollPerformanceCoordinator,
        smoothModeService: this.webScrollSmoothModeService,
        runtimeLifecyclePort: this.browserRuntimeLifecyclePort
      },
      this.browserWebScrollInteractionShell
    );
  private browserStatusBarStyleService: BrowserStatusBarStyleService = new BrowserStatusBarStyleService();
  private webScrollGlobalImmersionEnabled: boolean =
    sharedPreferencesRepository.getPreferences().appearance.globalImmersionEnabled;
  private webScrollAlwaysTopImmersionEnabled: boolean =
    sharedPreferencesRepository.getPreferences().appearance.alwaysTopImmersionEnabled;
  private webScrollExperimentSettings: BrowserExperimentSettings =
    sharedPreferencesRepository.getPreferences().experiments;
  private browserRuntimeRefreshStateSink: BrowserRuntimeRefreshStateSink = {
    applyReplacementRuntimeState: (runtime: WebTabRuntimeRecord): void => {
      this.webController = runtime.controller;
      this.controllerAttached = false;
    }
  };
  private browserProxyAuthRefreshCoordinator: BrowserProxyAuthRefreshCoordinator =
    new BrowserProxyAuthRefreshCoordinator(
      this.browserHostedRuntimeSurfacePort,
      this.browserRuntimeLifecyclePort,
      this.browserRuntimeRefreshStateSink
    );
  private browserProxyRuntimeRefreshHost: BrowserProxyRuntimeRefreshHost = {
    resetProxyCredentialAttempts: (): void => {
      this.browserWebCapabilityPromptApplicationCoordinator.resetProxyCredentialAttempts();
    }
  };
  private webScrollSmoothModeRuntimeEnabled: boolean =
    this.webScrollExperimentSettings.pauseWebAnimationsDuringScroll ||
      this.webScrollExperimentSettings.reduceMediaMotionDuringScroll;
  private browserSmartGripCoordinator: BrowserSmartGripCoordinator = new BrowserSmartGripCoordinator();
  private smartGripTabsOverviewViewModel: BrowserSmartGripTabsOverviewViewModel =
    new BrowserSmartGripTabsOverviewViewModel();
  @State browserSmartGripState: BrowserSmartGripState = this.browserSmartGripCoordinator.createState();
  private browserWebLoadingProgressBarPresentationViewModel: BrowserWebLoadingProgressBarPresentationViewModel =
    new BrowserWebLoadingProgressBarPresentationViewModel();
  @State loadingProgressState: BrowserLoadingProgressState =
    this.browserWebPageLifecycleApplicationCoordinator.createLoadingProgressState();
  @State pullRefreshState: BrowserPullRefreshState = this.browserPullRefreshCoordinator.getSnapshot();
  @State pullRefreshRefreshing: boolean = false;
  @State homeShortcutApplicationSnapshot: HomeShortcutApplicationSnapshot =
    this.homeShortcutStateCoordinator.getSnapshot();
  @State recentlyClosedApplicationSnapshot: BrowserRecentlyClosedApplicationSnapshot =
    createBrowserRecentlyClosedApplicationSnapshot();
  @State showHomeShortcuts: boolean = true;
  @State homeShortcutLayoutDensity: BrowserHomeShortcutLayoutDensity = 'standard';
  @State themedHomeBackground: string = '#F2F3F5';
  @State themedHomeSurfaceBackground: string = '#FFFFFF';
  @State themedHomeControlBackground: string = '#E9EDF2';
  @State themedHomePressedBackground: string = '#DDE5EF';
  @State themedHomeOutlineColor: string = '#D8DEE8';
  @State themedHomeTextPrimaryColor: string = '#111827';
  @State themedHomeTextSecondaryColor: string = '#667085';
  @State themedHomeAccentColor: string = '#0A59F7';
  @State themedHomeOnPrimaryColor: string = '#FFFFFF';
  @State tabsSheetBackgroundColor: string = '#F2F3F5';
  @State tabsSheetSurfaceBackground: string = '#FFFFFF';
  @State tabsSheetControlBackground: string = '#E9EDF2';
  @State tabsSheetPressedBackground: string = '#DDE5EF';
  @State tabsSheetOutlineColor: string = '#D8DEE8';
  @State tabsSheetTextPrimaryColor: string = '#111827';
  @State tabsSheetTextSecondaryColor: string = '#667085';
  @State tabsSheetAccentColor: string = '#0A59F7';
  @State tabsSheetBlurPrivateTabPreviews: boolean = true;
  @State toolbarLayoutVersion: number = 0;
  @State contextMenuHomeShortcutId: string = '';
  @State homeShortcutEditDraft: HomeShortcutEditDraft = {
    shortcutId: '',
    title: '',
    url: '',
    iconPath: ''
  };
  @State webAppInstallDialogSnapshot: WebAppInstallDialogSnapshot =
    this.webAppInstallCoordinator.getDialogSnapshot();
  @State activeDownloadCount: number = 0;
  @State webPromptDialogPresentation: BrowserWebPromptDialogPresentation =
    createEmptyBrowserWebPromptDialogPresentation();
  @State httpAuthDialogPresentation: BrowserHttpAuthDialogPresentation =
    createEmptyBrowserHttpAuthDialogPresentation();
  @State externalNavigationPromptState: ExternalNavigationPromptState =
    this.browserUnifiedLinkApplicationCoordinator.createInitialPromptState();
  @State sitePermissionDialogPresentation: BrowserSitePermissionDialogPresentation =
    createEmptyBrowserSitePermissionDialogPresentation();
  @State sitePermissionPromptVisible: boolean = false;
  @State siteReportReasonId: SiteReportReasonId = this.siteReportDialogViewModel.getDefaultReasonId();
  @State siteReportRemark: string = '';
  @State documentViewerFileInfoDialogInfo: DocumentViewerFileInfo = {
    kind: 'text',
    displayName: '',
    sourceUri: '',
    typeLabel: '',
    sizeBytes: 0,
    sizeLabel: '',
    modifiedAtSeconds: 0,
    modifiedAtLabel: '',
    readOnlyLabel: '只读查看',
    rows: []
  };
  @StorageLink(BROWSER_PRIVATE_FOREGROUND_REVISION_KEY) @Watch('handlePrivateForegroundRevisionChange')
  private privateForegroundRevision: number = 0;
  @State privateModeLockSessionSnapshot: BrowserPrivateModeLockSessionSnapshot =
    this.browserPrivateModeLockCoordinator.getSessionSnapshot();
  @State homeProfileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID;
  @State homePrivacyMode: BrowserSessionPrivacyMode = 'regular';
  @State homeDataScope: BrowserDataScope = 'profile_persistent';
  @StorageLink(BROWSER_SHELL_PRESENTATION_REVISION_STORAGE_KEY)
  @Watch('reconcileShellTabPresentation')
  private browserShellPresentationRevision: number = 0;
  @State private largeScreenWebZoomRevision: number = 0;
  @State @Watch('reconcileShellTabPresentation') activeTabId: string = '';
  @State @Watch('reconcileShellTabPresentation') tabs: BrowserTabState[] = [];
  @State runtimeDegradedMessage: string = '';
  @State pageFindBarState: BrowserPageFindBarState = createBrowserPageFindClosedBarState();
  @State offlinePageSaveSessionSnapshot: OfflinePageSaveSessionSnapshot =
    this.offlinePageSaveCoordinator.getSessionSnapshot();
  private lastSystemBackExitPromptAt: number = 0;
  @State customHomepageRuntimeState: CustomHomepageRuntimeShellState =
    this.customHomepageRuntimeCoordinator.getShellState();
  @State browserBookmarkActionSessionSnapshot: BrowserBookmarkActionSessionSnapshot =
    this.browserBookmarkActionCoordinator.getSnapshot();
  @State browserTransientSurfaceSnapshot: BrowserTransientSurfaceSnapshot =
    this.browserTransientSurfaceCoordinator.snapshot();
  @State appProxyQuickSheetState: AppProxyQuickSheetState = this.appProxyQuickSheetCoordinator.getSnapshot();
  @State browserWebPageToolsSnapshot: BrowserWebPageToolsSnapshot =
    this.browserWebPageToolsCoordinator.snapshot();
  private tabSequence: number = 1;
  private isRestoringTabs: boolean = true;
  @State private startupHomeSurfacePending: boolean = false;
  private hasHandledInitialPageShow: boolean = false;
  private isBrowserShellVisible: boolean = false;
  private webSessionTransitionToken: number = 0;
  private currentRuntimeRetentionPlan: WebRuntimeRetentionPlan = {
    activeTabId: '',
    mountedTabIds: [],
    hotTabIds: [],
    warmTabIds: [],
    coldTabIds: [],
    forcedDiscardTabIds: [],
    webStateRestoreCandidateTabIds: [],
    runtimeStates: {},
    retentionReasonsByTabId: {},
    retentionScoresByTabId: {},
    restorePrioritiesByTabId: {},
    nonReclaimableReasonsByTabId: {},
    discardReasonsByTabId: {},
    pressureAssist: {
      level: 'idle',
      extraWarmSlots: 0,
      extraMountedSlots: 0,
      warmTabIds: [],
      mountedTabIds: [],
      summaryLine: 'retentionPressure level=idle extraWarm=0 extraMounted=0 aidedWarm=0 aidedMounted=0 warmTabs=none mountedTabs=none'
    }
  };
  private browserDownloadConfirmOverlayHost: BrowserDownloadConfirmOverlayHost = {
      resolveFacts: (): BrowserDownloadConfirmOverlayFacts => {
        return {
          activeTabId: this.activeTabId
        };
      },
      publishPendingPrompt: (prompt?: PendingDownloadPromptState): void => {
        this.pendingDownloadPrompt = prompt;
      },
      showToast: (message: string): void => {
        this.showNativeToast(message);
      }
    };
  private browserDownloadConfirmOverlayCoordinator: BrowserDownloadConfirmOverlayCoordinator =
    new BrowserDownloadConfirmOverlayCoordinator(
      this.downloadService,
      this.browserDownloadNavigationStateCoordinator,
      this.browserDownloadConfirmOverlayHost,
      this.browserWebPageLifecycleApplicationCoordinator
    );
  private webContextMenuActionApplication: WebLinkContextMenuFixedActionApplication =
    new WebLinkContextMenuFixedActionApplication(
      {
        appUrlOpenCoordinator: this.browserAppUrlOpenCoordinator,
        bookmarkActionCoordinator: this.browserBookmarkActionCoordinator,
        clipboardService: this.browserClipboardService,
        downloadConfirmOverlayCoordinator: this.browserDownloadConfirmOverlayCoordinator,
        foregroundTabCreationCoordinator: this.browserForegroundTabCreationCoordinator,
        privateTabCoordinator: this.browserPrivateTabCoordinator,
        tabScopedEventContextCoordinator: this.tabScopedEventContextCoordinator,
        webPageShareService: this.webPageShareService
      },
      {
        readFacts: () => ({
          context: this.getAbilityContext(),
          activeTabId: this.activeTabId,
          homeShortcutScenarioId: this.homeShortcutApplicationSnapshot.scenarioId
        }),
        showToast: (message: string): void => this.showNativeToast(message),
        publishError: (message: string): void => {
          this.errorMessage = message;
        },
        publishHelper: (message: string): void => {
          this.helperMessage = message;
        },
        saveOffline: (tabId: string, url: string, title: string): void => {
          void this.saveWebLinkFromContextMenuOffline(tabId, url, title);
        }
      }
    );
  private browserMediaResourceSessionCoordinator: BrowserMediaResourceSessionCoordinator =
    new BrowserMediaResourceSessionCoordinator(
      this.browserMediaDiscoveryCoordinator,
      this.browserMediaDiscoveryHost,
      this.browserTransientSurfaceCoordinator,
      this.downloadService,
      this.browserDownloadConfirmOverlayCoordinator,
      this.browserMediaResourceSessionShell,
      {
        resourceRevealDelayMs: RESOURCE_CANDIDATES_OVERLAY_OPEN_DELAY_MS,
        resourceDismissDurationMs: RESOURCE_CANDIDATES_OVERLAY_ANIMATION_DURATION_MS,
        hlsDismissDurationMs: HLS_TAKEOVER_OVERLAY_ANIMATION_DURATION_MS
      }
    );
  private browserRootBottomPanelFixedActionShell: BrowserRootBottomPanelFixedActionShell = {
    readFacts: (): BrowserRootBottomPanelFixedActionFacts => ({
      context: this.getAbilityContext(),
      tabs: this.tabs,
      activeTabId: this.activeTabId,
      showHomePage: this.showHomePage,
      showTabsSheet: this.showTabsSheet,
      webPageVisible: this.isWebPageVisible(),
      currentUrl: this.currentUrl,
      pendingWebUrl: this.pendingWebUrl,
      addressInput: this.addressInput,
      currentTitle: this.currentTitle,
      currentDocumentViewerPage: this.buildCurrentDocumentViewerChromeContext().policy.active,
      canGoBack: this.canGoBack,
      privateModeActive: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
      dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
      appProxyActive: this.appProxyQuickSheetState.toolbarActive,
      bookmarkActionVersion: this.browserBookmarkActionSessionSnapshot.actionVersion,
      userAgentPresentation: this.browserUserAgentActionPresentation,
      fullscreenPresentation: this.browserFullscreenSessionPresentation,
      textZoomRatio: this.webTextZoomRatio,
      textZoomActionVersion: this.webTextZoomActionVersion,
      themeModeActionVersion: this.themeModeActionVersion,
      toolbarLayoutVersion: this.toolbarLayoutVersion
    }),
    resolveBookmarkTarget: (): BrowserBookmarkActionTarget => this.buildCurrentBookmarkActionTarget(),
    resolveCurrentPageActionUrl: (): string => this.resolveCurrentWebPageActionUrl(),
    submitAddress: (rawInput: string): void => this.submitRootBottomAddressInput(rawInput),
    resolveSnapshot: (): BrowserPhonePagePushSnapshot => {
      const tabId = this.activeTabId;
      return {
        entitlementContext: {
          dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
          privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
          loggedIn: true
        },
        uid: sharedAiraSyncConfigStore.getSettings().huaweiCloud.uid.trim(),
        url: this.resolveCurrentWebPageActionUrl(),
        title: this.currentTitle,
        controller: this.browserRuntimeLifecyclePort.resolveController(tabId)
      };
    },
    showToast: (message: string): void => this.showNativeToast(message),
    goHomePreservingCurrentTab: (): Promise<void> => this.browserTabHomeCoordinator.goHome(),
    prepareDirectHomeReveal: async (): Promise<void> => {
      this.browserTabHomeCoordinator.prepareDirectHomeReveal();
    }
  };
  private browserRootBottomPanelActionApplication: BrowserRootBottomPanelFixedActionApplication =
    new BrowserRootBottomPanelFixedActionApplication({
      activeTabRuntimeRestoreCoordinator: this.browserActiveTabRuntimeRestoreCoordinator,
      appProxyQuickSheetCoordinator: this.appProxyQuickSheetCoordinator,
      bookmarkActionCoordinator: this.browserBookmarkActionCoordinator,
      clipboardService: this.browserClipboardService,
      foregroundTabCreationCoordinator: this.browserForegroundTabCreationCoordinator,
      fullscreenSessionCoordinator: this.browserFullscreenSessionCoordinator,
      elementInspectionSessionCoordinator: this.elementInspectionSessionCoordinator,
      manualElementHideRuntimeCoordinator: this.manualElementHideRuntimeCoordinator,
      mediaResourceSessionCoordinator: this.browserMediaResourceSessionCoordinator,
      offlinePageSaveCoordinator: this.offlinePageSaveCoordinator,
      pageFindCoordinator: this.browserPageFindCoordinator,
      phonePagePushCoordinator: this.phonePagePushCoordinator,
      readerModeCoordinator: this.articleReadingSession,
      novelReaderSession: this.novelReaderSession,
      runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
      shellRouteCoordinator: this.browserShellRouteCoordinator,
      siteControlsRuntimeCoordinator: this.browserSiteControlsRuntimeCoordinator,
      tabHomeCoordinator: this.browserTabHomeCoordinator,
      themeModeCoordinator: this.browserThemeModeCoordinator,
      userReturnHomeCoordinator: this.browserUserReturnHomeCoordinator,
      userAgentActionCoordinator: this.browserUserAgentActionCoordinator,
      userScriptApplicationCoordinator: this.browserUserScriptApplicationCoordinator,
      webAppInstallCoordinator: this.webAppInstallCoordinator,
      webHistoryCommandRuntimeCoordinator: this.browserWebHistoryCommandRuntimeCoordinator,
      webPageShareService: this.webPageShareService,
      webPrintService: this.browserWebPrintService,
      webpageTranslationCoordinator: this.webpageTranslationCoordinator,
      windowContextCoordinator: this.browserWindowContextCoordinator,
      homeUrl: HOME_TAB_URL,
      newTabTitle: '新标签页'
    }, this.browserRootBottomPanelFixedActionShell);
  private browserMainBackCoordinator: BrowserMainBackCoordinator = new BrowserMainBackCoordinator({
    manualElementHideRuntimeCoordinator: this.manualElementHideRuntimeCoordinator,
    elementInspectionSessionCoordinator: this.elementInspectionSessionCoordinator,
    webpageTranslationCoordinator: this.webpageTranslationCoordinator,
    bookmarkActionCoordinator: this.browserBookmarkActionCoordinator,
    appProxyQuickSheetCoordinator: this.appProxyQuickSheetCoordinator,
    webPageToolsCoordinator: this.browserWebPageToolsCoordinator,
    readerModeCoordinator: this.articleReadingSession,
    customHomepageRuntimeCoordinator: this.customHomepageRuntimeCoordinator,
    tabsOverviewSessionCoordinator: this.tabsOverviewSessionCoordinator,
    downloadConfirmOverlayCoordinator: this.browserDownloadConfirmOverlayCoordinator,
    mediaResourceSessionCoordinator: this.browserMediaResourceSessionCoordinator,
    userScriptApplicationCoordinator: this.browserUserScriptApplicationCoordinator,
    transientSurfaceCoordinator: this.browserTransientSurfaceCoordinator,
    featureGateCoordinator: this.featureGateCoordinator,
    homeShortcutStateCoordinator: this.homeShortcutStateCoordinator,
    releaseNoticePresentationCoordinator: this.releaseNoticePresentationCoordinator,
    unifiedLinkApplicationCoordinator: this.browserUnifiedLinkApplicationCoordinator,
    keyboardShortcutCoordinator: this.browserKeyboardShortcutCoordinator,
    webHistoryCommandRuntimeCoordinator: this.browserWebHistoryCommandRuntimeCoordinator,
    windowOpenApplicationCoordinator: this.browserWindowOpenApplicationCoordinator,
    tabCloseCoordinator: this.browserTabCloseCoordinator,
    novelReaderSession: this.novelReaderSession
  });
  private browserShellLifecycleShell: BrowserShellLifecycleShell = {
    readFacts: (): BrowserShellLifecycleFacts => ({
      tabs: this.tabs,
      activeTabId: this.activeTabId,
      currentWindowId: this.currentWindowId,
      windowScopeId: this.getWindowScopeId(),
      currentUrl: this.currentUrl,
      addressInput: this.addressInput,
      showHomePage: this.showHomePage,
      isRestoringTabs: this.isRestoringTabs,
      hasHandledInitialPageShow: this.hasHandledInitialPageShow,
      rootBottomPanelDetent: this.resolveRootBottomPanelDetent()
    }),
    setBrowserShellVisible: (visible: boolean): void => {
      this.isBrowserShellVisible = visible;
    },
    setStartupHomeSurfacePending: (pending: boolean): void => {
      this.startupHomeSurfacePending = pending;
    },
    setInitialPageShowHandled: (handled: boolean): void => {
      this.hasHandledInitialPageShow = handled;
    },
    refreshRootBottomPanelLayoutState: (): void => this.refreshRootBottomPanelLayoutState(),
    applyDownloadInfo: (message: string): void => {
      this.helperMessage = message;
      this.showNativeToast(message);
    },
    applyDownloadError: (userMessage: string, sourceMessage: string): void => {
      this.errorMessage = userMessage;
      this.showNativeToast(sourceMessage);
    },
    syncDownloadBoundary: (): void => this.syncDownloadBoundary(),
    applyInitialWebPresentation: (): void => {
      this.webAppearancePolicy = this.buildWebAppearancePolicy();
      this.webRuntimeBootstrapConfig = this.buildWebRuntimeBootstrapConfig();
      this.refreshWebViewportPresentation();
    },
    syncWindowSafeInsets: (): void => this.syncWindowSafeInsetsForShell(),
    applyAppearanceState: (state: BrowserShellLifecycleAppearanceState): void => {
      this.webScrollGlobalImmersionEnabled = state.globalImmersionEnabled;
      this.webScrollAlwaysTopImmersionEnabled = state.alwaysTopImmersionEnabled;
    },
    applyExperimentSettings: (settings: BrowserExperimentSettings): void => {
      this.webScrollExperimentSettings = settings;
      this.webScrollSmoothModeRuntimeEnabled = settings.pauseWebAnimationsDuringScroll ||
        settings.reduceMediaMotionDuringScroll;
    },
    incrementThemeModeActionVersion: (): void => {
      this.themeModeActionVersion += 1;
    },
    incrementToolbarLayoutVersion: (): void => {
      this.toolbarLayoutVersion += 1;
    },
    syncBottomPanelStatusBarStyle: (): void => this.syncBottomPanelStatusBarStyle(),
    applySmartGripState: (state: BrowserSmartGripState): void => {
      this.browserSmartGripState = state;
    },
    bindReaderModeSession: (): void => this.bindReaderModeSession(),
    applyRestoredWebLayerGeometry: (snapshot?: BrowserWebLayerGeometrySnapshot): void => {
      this.restoredWebLayerGeometry = snapshot;
    },
    setColdStartDeferredSurfaceContentMounted: (mounted: boolean): void => {
      this.coldStartDeferredSurfaceContentMounted = mounted;
    },
    restoreSavedTabs: (): void => this.restoreSavedTabs(),
    captureLifecycleExitPreview: (): void => this.captureCurrentTabPreviewForLifecycleExit('page-disappear'),
    releaseAllKeyboardAvoidModes: (): void => this.releaseAllBrowserKeyboardAvoidModes(),
    restoreBottomPanelStatusBarStyle: (): void => this.restoreBottomPanelStatusBarStyle(),
    resetTransientOverlays: (
      syncPromptFromService: boolean,
      preservedCustomBottomSurfaceIds?: BrowserTransientSurfaceId[]
    ): void => {
      this.resetTransientOverlayStateForRouteTransition(syncPromptFromService, preservedCustomBottomSurfaceIds);
    },
    persistActiveTabSnapshot: (reason: string): void => this.persistActiveTabSnapshot(reason),
    dismissWebContextMenu: (): void => this.dismissWebContextMenu(),
    cancelDeferredTabsOverviewOpen: (): void => this.cancelDeferredTabsOverviewOpen(),
    scheduleWebSafeInsetSettleSync: (source: string): void => this.scheduleWebSafeInsetSettleSync(source),
    applyGestureOnboardingPromptState: (state): void => {
      this.gestureOnboardingPromptState = state;
    },
    connectSearchInvocationSurface: (): void => this.connectBrowserSearchInvocationSurfaceIfReady()
  };
  private browserShellLifecycleCoordinator: BrowserShellLifecycleCoordinator =
    new BrowserShellLifecycleCoordinator({
      windowContextCoordinator: this.browserWindowContextCoordinator,
      searchInvocationSurfaceConnection: this.browserSearchInvocationSurfaceConnection,
      runtimeMutationPort: this.browserRuntimeMutationPort,
      downloadService: this.downloadService,
      downloadNavigationStateCoordinator: this.browserDownloadNavigationStateCoordinator,
      appUrlOpenCoordinator: this.browserAppUrlOpenCoordinator,
      downloadConfirmOverlayCoordinator: this.browserDownloadConfirmOverlayCoordinator,
      faultClassifier: this.browserFaultClassifier,
      backgroundSessionSyncCoordinator: this.browserTabBackgroundSessionSyncCoordinator,
      tabHomeCoordinator: this.browserTabHomeCoordinator,
      customHomepageRuntimeCoordinator: this.customHomepageRuntimeCoordinator,
      homePresentationSessionCoordinator: this.browserHomePresentationSessionCoordinator,
      offlineFastFailureCoordinator: this.browserOfflineFastFailureCoordinator,
      readerModeCoordinator: this.articleReadingSession,
      homeShortcutStateCoordinator: this.homeShortcutStateCoordinator,
      recentlyClosedApplicationCoordinator: this.browserRecentlyClosedApplicationCoordinator,
      tabCloseCoordinator: this.browserTabCloseCoordinator,
      tabSessionPersistenceCoordinator: this.browserTabSessionPersistenceCoordinator,
      tabPreviewCoordinator: this.browserTabPreviewCoordinator,
      webPageLifecycleApplicationCoordinator: this.browserWebPageLifecycleApplicationCoordinator,
      pullRefreshCoordinator: this.browserPullRefreshCoordinator,
      windowAvoidAreaCoordinator: this.browserWindowAvoidAreaCoordinator,
      manualElementHideRuntimeCoordinator: this.manualElementHideRuntimeCoordinator,
      elementInspectionSessionCoordinator: this.elementInspectionSessionCoordinator,
      webpageTranslationCoordinator: this.webpageTranslationCoordinator,
      webScrollInteractionCoordinator: this.browserWebScrollInteractionCoordinator,
      offlinePageSaveCoordinator: this.offlinePageSaveCoordinator,
      fullscreenSessionCoordinator: this.browserFullscreenSessionCoordinator,
      hostedRuntimeSurfacePort: this.browserHostedRuntimeSurfacePort,
      runtimeLifecyclePort: this.browserRuntimeLifecyclePort,
      adBlockCoordinator: this.browserAdBlockCoordinator,
      tabsOverviewSessionCoordinator: this.tabsOverviewSessionCoordinator,
      privateTabCoordinator: this.browserPrivateTabCoordinator,
      privateModeLockCoordinator: this.browserPrivateModeLockCoordinator,
      siteControlsRuntimeCoordinator: this.browserSiteControlsRuntimeCoordinator,
      nativeNavigationConsumeCoordinator: this.browserNativeNavigationConsumeCoordinator,
      tabSwitchCoordinator: this.browserTabSwitchCoordinator,
      tabScopedEventContextCoordinator: this.tabScopedEventContextCoordinator,
      webTopImmersionSessionCoordinator: this.browserWebTopImmersionSessionCoordinator,
      userScriptRuntimeCoordinator: this.userScriptRuntimeCoordinator,
      tabManager: this.tabManager,
      proxyAuthRefreshCoordinator: this.browserProxyAuthRefreshCoordinator,
      proxyRuntimeRefreshHost: this.browserProxyRuntimeRefreshHost,
      runtimeRefreshStateSink: this.browserRuntimeRefreshStateSink,
      mediaDiscoveryRuntimeContextFactory: this.browserMediaDiscoveryRuntimeContextFactory,
      smartGripCoordinator: this.browserSmartGripCoordinator,
      webLayerGeometryStore: this.browserWebLayerGeometryStore,
      runtimeCoolingTickMs: RUNTIME_COOLING_TICK_MS,
      rootBottomPanelSessionCoordinator: this.browserRootBottomPanelSessionCoordinator
    }, this.browserShellLifecycleShell);
  @State activeHostedWebNodeTabId: string = '';
  @State activeHostedWebNodeRenderKey: string = '';
  @State hostedWebHiddenSlots: BrowserHostedWebHiddenSlot[] = [];
  @State manualElementHideSelectionPresentation: ManualElementHideSelectionPresentation =
    this.manualElementHideRuntimeCoordinator.snapshotSelection();
  @State elementInspectionPresentation: ElementInspectionPresentation =
    this.elementInspectionSessionCoordinator.snapshot();
  aboutToAppear(): void {
    this.clientUpdatePolicyUnsubscribe = sharedClientUpdatePolicyService.subscribe(
      (state: ClientUpdatePolicyState): void => {
        this.clientUpdatePolicyState = state;
      }
    );
    this.refreshAiraCloudBookmarkV4BootstrapState();
    const storage = this.getSharedStageStorage();
    const initialViewport = BrowserWindowRuntime.resolveInitialShellViewport(storage);
    this.rootViewportWidth = initialViewport.width;
    this.rootViewportHeight = initialViewport.height;
    this.refreshRootBottomPanelLayoutState();
    this.showHomePage = BrowserWindowRuntime.consumeInitialHomeSurfaceVisibility(storage);
    this.tabManager.connect(BrowserWindowRuntime.connectTabManagerSession(storage));
    this.articleReadingSession.connect(BrowserWindowRuntime.connectArticleReadingSession(storage));
    this.readerModeSessionSnapshot = this.articleReadingSession.getSessionSnapshot();
    this.novelReaderSession.connect(BrowserWindowRuntime.connectNovelReaderSession(storage));
    this.novelReaderSnapshot = this.novelReaderSession.getSnapshot();
    this.browserShellPresentationOperations = resolveBrowserWindowSessionShellPresentationBinding(
      BrowserWindowRuntime.connectShellPresentation(storage)
    );
    this.browserRuntimeLifecyclePort.connectRuntimeSession(
      BrowserWindowRuntime.connectRuntimeSession(storage),
      BrowserWindowRuntime.connectBackground(storage)
    );
    this.browserWindowContextCoordinator.connect(
      BrowserWindowRuntime.connectWindowContext(storage, this.browserWindowContextComposition)
    );
    this.browserWindowContextCoordinator.connectSessionContextState(
      BrowserWindowRuntime.connectWindowContextState(storage)
    );
    this.browserUserAgentRuntimePolicyCoordinator.bindPresentationRefresh();
    this.reconcileShellTabPresentation();
    this.browserShellLifecycleCoordinator.handleAppear();
    this.scheduleColdStartPostFirstFrameWork();
    void this.checkClientUpdatePolicy();
  }

  aboutToDisappear(): void {
    this.clientUpdatePolicyUnsubscribe?.();
    this.clientUpdatePolicyUnsubscribe = undefined;
    this.coldStartDeferredContentMountGeneration += 1;
    this.userScriptRuntimeCoordinator.cancelDocumentStartScriptWarmup();
    this.browserUserAgentRuntimePolicyCoordinator.dispose();
    this.browserRootBottomPanelSessionCoordinator.cancelHomeToWebBottomPanelTransition();
    const storage = this.getSharedStageStorage();
    this.browserLargeScreenShellIntentApplication.dispose();
    this.browserUserScriptApplicationCoordinator.dispose();
    this.browserStartupTabRestoreCoordinator.cancelStartupRestore();
    this.browserShellLifecycleCoordinator.handleDisappear();
    this.browserWindowContextCoordinator.disconnectSessionContextState();
    BrowserWindowRuntime.disconnectWindowContext(storage);
    this.browserWindowContextCoordinator.disconnect();
    this.browserShellPresentationOperations = undefined;
    this.articleReadingSession.disconnect();
    this.novelReaderSession.disconnect();
    this.tabManager.disconnect();
  }

  onPageShow(): void {
    this.browserShellLifecycleCoordinator.handlePageShow();
    void this.checkClientUpdatePolicy();
  }

  private checkClientUpdatePolicy(): Promise<void> {
    return sharedClientUpdatePolicyService.check(sharedAiraSyncConfigStore.getSettings())
      .then((): void => undefined)
      .catch((_error: Error): void => {
        // The policy is fail-open; a transient network error must not affect local browsing.
      });
  }

  private handleClientUpdateRequiredAction(action: ClientUpdateRequiredAction): void {
    const state = this.clientUpdatePolicyState;
    sharedClientUpdatePolicyService.deferCurrentRequirement();
    if (action === 'continue_local') {
      this.browserNativeAlertDialogPresenter.inform({
        title: '云同步已暂停',
        message: '当前版本仍可正常浏览和使用本机书签。升级 Aira 后，Aira 云书签同步才会恢复。',
        confirmLabel: '知道了'
      });
      return;
    }
    const updateTask = state.updateUrl.length > 0
      ? this.systemSettingsLaunchService.openExternalUrl(this.getAbilityContext(), state.updateUrl)
      : this.systemSettingsLaunchService.openAppGalleryDetailPage(this.getAbilityContext());
    updateTask.then((result): void => {
      if (!result.success) {
        this.browserNativeAlertDialogPresenter.inform({
          title: '暂时无法打开升级页面',
          message: `${result.message} 请稍后在应用市场搜索 Aira。`,
          confirmLabel: '知道了'
        });
      }
    });
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      this.buildBrowserPrimarySurfaceLayers()

      if (this.shouldRenderTabsBackdropSnapshot()) {
        this.buildTabsBackdropSnapshot()
      }

      this.buildRootBottomPanelExpandedScrim()

      // Mount the overlay whenever it is open OR still resident from a previous
      // open. Once resident it is kept mounted (opacity 0, hit-test off) so later
      // opens skip rebuilding the grid and the chrome subtree. Residency flips in
      // the sheet-open state path, never here: writing state from build() would
      // re-enter the renderer.
      if (this.tabsOverviewOverlayResident || this.buildTabsOverviewSceneRenderState().cardsLayerMounted) {
        this.buildTabsOverlay()
      }

      if (this.shouldRenderSharedSnapshotOverlay() &&
        !this.tabsOverviewSessionCoordinator.shouldRenderSharedSnapshotEntryOverlay(this.tabsSharedSnapshotState)) {
        BrowserTabsSharedSnapshotOverlay({
          state: this.tabsSharedSnapshotState,
          snapshotBackgroundColor: this.getWebViewportTopSafeAreaBackgroundColor(),
          viewportLeft: this.rootViewportLeft,
          viewportTop: this.rootViewportTop,
          onSnapshotRectChange: (rect: BrowserTabsOverlayRect) => {
            if (this.tabsOverviewSessionCoordinator.shouldRenderSharedSnapshotEntryOverlay(
              this.tabsSharedSnapshotState
            )) {
              this.tabsOverviewSessionCoordinator.rememberSharedSnapshotEntryFrame(rect);
            }
          },
          onSnapshotTap: (tabId: string) => {
            this.dispatchTabsOverviewSession({ type: 'interrupt_entry_selection', tabId: tabId });
          }
        })
      }

      if (this.shouldMountRootBottomPanelHost()) {
        this.buildRootBottomPanelHost()
      }

      if (this.readerModeSessionSnapshot.state.visible) {
        this.buildReaderModeOverlay()
      }

      this.buildNovelReaderSurface()

      if (this.buildTopFloatingPromptHostState().mounted) {
        BrowserTopFloatingPromptHost({
          state: this.buildTopFloatingPromptHostState(),
          onAction: (action) => this.browserTopFloatingPromptCoordinator.handleAction(action)
        })
          .zIndex(BROWSER_TOP_FLOATING_PROMPT_HOST_Z_INDEX)
      }

      if (this.webContextMenuPresentation.state.visible) {
        this.buildWebContextMenuOverlay()
      }

      this.buildActiveBrowserTransientSurface()

      if (this.pendingDownloadPrompt !== undefined) {
        BrowserDownloadConfirmOverlay({
          visible: true,
          prompt: this.pendingDownloadPrompt,
          onAction: (action) => this.browserDownloadConfirmOverlayCoordinator.handleAction(action)
        })
      }

      if (this.clientUpdatePolicyState.required) {
        ClientUpdateRequiredOverlay({
          state: this.clientUpdatePolicyState,
          onAction: (action: ClientUpdateRequiredAction): void => {
            this.handleClientUpdateRequiredAction(action);
          }
        })
      }

      if (this.browserTransientSurfaceSnapshot.systemSheet.type !== 'none') {
        BrowserSystemSurfaceHost({
          phoneSheetVisible: $phoneSystemSheetVisible,
          selectionState: $homeShortcutSelectionState,
          systemSheet: this.browserTransientSurfaceSnapshot.systemSheet,
          shellFamily: this.browserShellPresentationOperations?.snapshot()?.shellFamily ?? 'phone',
          privateModeVisible: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
          resolveUserScriptInstallUrl: (): string => this.browserUserScriptApplicationSnapshot.installUrl,
          resolveUserScriptInstallBoundary: () => this.browserUserScriptApplicationSnapshot.installBoundary,
          onSelectionAction: (action) => this.homeShortcutStateCoordinator.handleSelectionAction(action),
          onSelectionBack: (): void => this.homeShortcutStateCoordinator.handleSelectionBack(),
          onHomeSettingsWallpaperChanged: (): void => {
            this.browserTabHomeCoordinator.refreshWallpaperPresentation();
          },
          onUserScriptInstalled: (result: UserScriptPackageSuccessResult): void => this.browserUserScriptApplicationCoordinator.handleInstallCompleted(result),
          onCloseRequested: (): void => this.closeSystemSheet(),
          onDisappear: (): void => this.handleSystemSheetDisappear(),
          largeScreenReadingContent: () => {
            this.buildSystemSheet()
          }
        })
      }

      if (this.sitePermissionPromptVisible) {
        BrowserSitePermissionPromptHost({
          visible: $sitePermissionPromptVisible,
          presentation: $sitePermissionDialogPresentation,
          onAction: (action): Promise<boolean> =>
            this.browserWebCapabilityPromptApplicationCoordinator.handlePendingSitePermissionAction(action),
          onDismiss: () => this.browserWebCapabilityPromptApplicationCoordinator.dismissPendingPermissionPrompt()
        })
      }

      if (this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceId === 'web_page_tools' &&
        this.isLargeScreenShellFamilyActive()) {
        BrowserWebPageToolsLargeScreenOverlayHost({
          visible: this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceVisible,
          sheetType: this.browserWebPageToolsSnapshot.type,
          fullscreenPresentation: this.browserFullscreenSessionPresentation,
          userAgentPresentation: this.browserUserAgentActionPresentation,
          siteControlsSnapshot: this.siteControlsApplicationSnapshot,
          onAction: (action) => {
            this.browserWebPageToolsCoordinator.handleOverlayAction(action);
          }
        })
      }

      if (this.mediaResourceSessionSnapshot.hlsTakeoverMounted) {
        BrowserHlsTakeoverOverlay({
          visible: this.mediaResourceSessionSnapshot.hlsTakeoverVisible,
          target: this.mediaResourceSessionSnapshot.hlsTakeoverTarget,
          parsing: this.mediaResourceSessionSnapshot.hlsTakeoverParsingCandidateId.length > 0,
          parseResult: this.mediaResourceSessionSnapshot.hlsTakeoverParseResult,
          onAction: (action) => {
            this.browserMediaResourceSessionCoordinator.handleHlsTakeoverAction(action);
          }
        })
      }

      if (this.manualElementHideSelectionPresentation.active) {
        this.buildManualElementHideSelectionOverlay()
      }

      if (this.browserPrivateModeLockCoordinator.shouldShowOverlay(
        this.privateModeLockSessionSnapshot,
        this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate()
      )) {
        this.buildPrivateModeLockOverlay()
      }

      if (this.isAssistantVideoTakeoverActive()) {
        this.buildVideoAssistantPlayerOverlay()
      }

      if (this.airaCloudBookmarkV4BootstrapState.visible) {
        AiraCloudBookmarkV4BootstrapOverlay({
          state: this.airaCloudBookmarkV4BootstrapState,
          onStart: (): void => this.startAiraCloudBookmarkV4Bootstrap(),
          onRetry: (): void => this.startAiraCloudBookmarkV4Bootstrap(),
          onRestore: (): void => this.restoreAiraCloudBookmarkV4Backup()
        })
          .zIndex(10000)
      }

    }
    .id(buildBrowserTabPreviewVisibleSurfaceSnapshotId(this.activeTabId))
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolveHomeRootBackgroundColor())
    .keyboardShortcut('t', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('openNewTab');
    })
    .keyboardShortcut('w', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('closeActiveTab');
    })
    .keyboardShortcut('t', [ModifierKey.CTRL, ModifierKey.SHIFT], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('restoreRecentlyClosedTab');
    })
    .keyboardShortcut('1', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleNumberedShortcut(1);
    })
    .keyboardShortcut('2', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleNumberedShortcut(2);
    })
    .keyboardShortcut('3', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleNumberedShortcut(3);
    })
    .keyboardShortcut('4', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleNumberedShortcut(4);
    })
    .keyboardShortcut('5', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleNumberedShortcut(5);
    })
    .keyboardShortcut('6', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleNumberedShortcut(6);
    })
    .keyboardShortcut('7', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleNumberedShortcut(7);
    })
    .keyboardShortcut('8', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleNumberedShortcut(8);
    })
    .keyboardShortcut('9', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleNumberedShortcut(9);
    })
    .keyboardShortcut(FunctionKey.TAB, [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('switchToNextTab');
    })
    .keyboardShortcut(FunctionKey.TAB, [ModifierKey.CTRL, ModifierKey.SHIFT], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('switchToPreviousTab');
    })
    .keyboardShortcut('h', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('openHistory');
    })
    .keyboardShortcut('j', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('openDownloads');
    })
    .keyboardShortcut('d', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('bookmarkCurrentPage');
    })
    .keyboardShortcut('s', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('saveOfflinePage');
    })
    .keyboardShortcut('d', [ModifierKey.ALT], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('focusAddressBar');
    })
    .keyboardShortcut('l', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('focusAddressBar');
    })
    .keyboardShortcut('f', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('openPageFind');
    })
    .keyboardShortcut(FunctionKey.F11, [], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('toggleFullScreen');
    })
    .keyboardShortcut(FunctionKey.DPAD_LEFT, [ModifierKey.ALT], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('navigateBack');
    })
    .keyboardShortcut(FunctionKey.DPAD_RIGHT, [ModifierKey.ALT], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('navigateForward');
    })
    .keyboardShortcut('r', [ModifierKey.CTRL], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('reloadPage');
    })
    .keyboardShortcut(FunctionKey.F5, [], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('reloadPage');
    })
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('escape');
    })
    .keyboardShortcut('a', [ModifierKey.CTRL, ModifierKey.SHIFT], () => {
      this.browserKeyboardShortcutCoordinator.handleShortcut('toggleTabsOverview');
    })
    .bindSheet($$this.phoneSystemSheetVisible, this.buildSystemSheet(), {
      preferType: SheetType.BOTTOM,
      height: resolveReadingExperienceSystemSheetHeight(this.browserTransientSurfaceSnapshot.systemSheet.type),
      title: resolveReadingExperienceSystemSheetTitle(this.browserTransientSurfaceSnapshot.systemSheet.type),
      dragBar: true,
      showClose: this.browserTransientSurfaceCoordinator.shouldShowSystemSheetClose(),
      onWillDisappear: () => {
        this.browserTransientSurfaceCoordinator.handleSystemSheetWillDisappear();
      },
      onDisappear: () => {
        this.handleSystemSheetDisappear();
      }
    })
    .onKeyPreIme((event: KeyEvent): boolean =>
      this.browserLargeScreenShellIntentApplication.handleWebZoomShortcutKey(event))
    .onKeyEvent((event: KeyEvent): boolean => {
      return this.tabsOverviewSessionCoordinator.handleShellKeyEvent(this.showTabsSheet, event);
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.rootViewportLeft = Math.round(this.parseAreaPosition(newArea.globalPosition.x));
      this.rootViewportTop = Math.round(this.parseAreaPosition(newArea.globalPosition.y));
      const nextViewportWidth = Math.max(1, Math.round(this.parseAreaDimension(newArea.width)));
      const nextViewportHeight = Math.max(1, Math.round(this.parseAreaDimension(newArea.height)));
      const viewportChanged = nextViewportWidth !== this.rootViewportWidth ||
        nextViewportHeight !== this.rootViewportHeight;
      this.rootViewportWidth = nextViewportWidth;
      this.rootViewportHeight = nextViewportHeight;
      this.refreshRootBottomPanelLayoutState();
      this.syncWindowSafeInsetsForShell();
      this.scheduleWebSafeInsetSettleSync('root-area-change');
      this.refreshWebViewportPresentation();
      if (viewportChanged && this.showHomePage) {
        this.browserTabHomeCoordinator.refreshWallpaperPresentation();
      }
    })
  }

  @Builder
  private buildBrowserPrimarySurfaceLayers() {
    Stack({ alignContent: Alignment.Top }) {
      BrowserHostedWebParkingSlots({
        slots: this.hostedWebHiddenSlots,
        activeHostedTabId: this.activeHostedWebNodeTabId,
        resolveController: (tabId: string) => this.browserHostedRuntimeSurfacePort.getHostedController(tabId),
        resolveGeometry: (slot: BrowserHostedWebHiddenSlot) =>
          this.browserHostedWebLayerPresentationViewModel.resolveHiddenHostedWebNodeParkingSlotGeometry(slot, {
            hostedWebLayerMeasured: this.hostedWebLayerMeasured,
            hostedWebLayerWidth: this.hostedWebLayerWidth,
            hostedWebLayerHeight: this.hostedWebLayerHeight,
            rootViewportWidth: this.rootViewportWidth,
            rootViewportHeight: this.rootViewportHeight,
            fallbackTopInsetPx: this.showHomePage ? 0 : this.getWebViewportLayoutTopInsetPx()
          })
      })

      BrowserShellPrimarySurfaceHost({
        presentationSurface: this.browserShellPresentationOperations?.surface(),
        presentationSnapshot: this.resolveBrowserShellPresentationSnapshot(
          this.browserShellPresentationRevision
        ),
        tabsOverviewSceneRenderState: this.buildTabsOverviewSceneRenderState(),
        showHomePage: this.showHomePage,
        largeScreenOmniboxPresentation: this.browserLargeScreenOmniboxPresentation,
        searchSuggestionSnapshot: this.browserSearchSuggestionSnapshot,
        largeScreenSearchEnginePresentation: this.browserTabHomeCoordinator.buildSearchEngineChromePresentation(
          this.selectedSearchEngine,
          this.availableSearchEngines
        ),
        largeScreenActionSnapshot: this.browserRootBottomPanelSessionCoordinator.resolveActionSnapshot(
          this.buildRootBottomPanelSemanticState(),
          this.rootBottomPanelLayoutState.responsiveState,
          this.rootBottomPanelLayoutState.layoutRenderKey
        ),
        largeScreenBookmarkActionSession: this.browserBookmarkActionSessionSnapshot,
        largeScreenSiteInfoVisible: this.browserWebPageToolsSnapshot.type === 'siteInfo' &&
          this.browserTransientSurfaceCoordinator.isMounted('web_page_tools'),
        largeScreenSiteControlsSnapshot: this.siteControlsApplicationSnapshot,
        largeScreenWebZoomSnapshot: this.browserLargeScreenWebZoomCoordinator.snapshot(
          this.activeTabId,
          this.largeScreenWebZoomRevision
        ),
        userScriptApplicationSnapshot: this.browserUserScriptApplicationSnapshot,
        largeScreenNativeVideoTakeoverActive: this.isAssistantVideoTakeoverActive(),
        largeScreenQuickSearchPresentation: this.quickSearchSwitchingPresentation,
        recentlyClosedApplicationSnapshot: this.recentlyClosedApplicationSnapshot,
        onLargeScreenSelectQuickSearchEngine: (engineId: string): void => {
          this.browserQuickSearchSwitchingCoordinator.selectEngine(engineId);
        },
        onLargeScreenTabStripIntent: (intent: BrowserLargeScreenTabStripIntent): void => {
          this.browserLargeScreenShellIntentApplication.dispatchTabStrip(intent);
        },
        onLargeScreenNavigationIntent: (intent: BrowserLargeScreenNavigationIntent): void => {
          this.browserLargeScreenShellIntentApplication.dispatchNavigation(intent);
        },
        onUserScriptAction: (action): void => {
          this.browserUserScriptApplicationCoordinator.handleAction(action);
        },
        onLargeScreenBookmarkBarAction: (action: BrowserDesktopBookmarkBarAction): void => {
          this.browserLargeScreenShellIntentApplication.dispatchBookmarkBarAction(action);
        },
        homeSurfaceSlot: () => {
          this.buildHomePage()
        },
        homeBackdropSurfaceSlot: () => {
          this.buildHomeBackdropOnlySurface()
        },
        webSurfaceSlot: () => {
          this.buildWebModeShell()
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  private reconcileShellTabPresentation(): void {
    if (this.showHomePage) {
      this.homeSurfacePaintedOnce = true;
    }
    // The overlay reads cached gallery states, so a tab add/close/reorder must
    // invalidate them here (this runs on every `tabs` change). Otherwise a tab
    // closed while the sheet is open would keep its stale preview entry.
    this.refreshTabPreviewStates();
    const presentation = this.browserShellPresentationOperations?.reconcileTabs(this.tabs, this.activeTabId);
    this.browserShellRouteCoordinator.reconcilePhoneNativeTabHandoff(
      presentation?.surface,
      this.tabs,
      this.activeTabId,
      this.showHomePage
    );
    // Re-bind the search-invocation surface to the CURRENT shell surface here.
    // The lifecycle/window-context connect() calls fire before the presentation
    // surface finishes resolving to 'large_screen' (notably on emulators, whose
    // device type reports "default" so the large-screen decision waits on a
    // display-width fallback). Without this, the phone surface adapter stays
    // registered on large screen, the large-screen omnibox never enters editing,
    // and the suggestion panel/Enter-to-search never activate. This reconcile
    // runs on tab-restore completion and every tab change, so it re-selects the
    // adapter that matches the now-resolved surface. connect() is idempotent.
    this.connectBrowserSearchInvocationSurfaceIfReady();
    this.browserWebPageLifecycleApplicationCoordinator.handleWebSurfaceVisibilityChanged(
      this.activeTabId,
      this.isWebPageVisible()
    );
  }

  private resolveBrowserShellPresentationSnapshot(
    _presentationRevision: number
  ): BrowserShellPresentationSnapshot | undefined {
    return this.browserShellPresentationOperations?.snapshot();
  }

  @Builder
  private buildHomeBackdropOnlySurface() {
    HomeBackdropLayer({
      wallpaperState: this.resolveHomeWallpaperPresentationState(),
      darkModeActive: this.resolveHomeWallpaperDarkModeActive(),
      themeBackgroundColor: this.resolveHomeRootBackgroundColor(),
      privateModeVisible: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      frameWidth: this.rootViewportWidth,
      frameHeight: this.rootViewportHeight
    })
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  onBackPress(): boolean {
    if (this.airaCloudBookmarkV4BootstrapState.visible) {
      return true;
    }
    if (this.isAssistantVideoTakeoverActive()) {
      void this.arkWebMediaTakeoverCoordinator.handleAssistantBack(
        this.rootViewportWidth > this.rootViewportHeight,
        this.arkWebMediaAssistantPlayerHost
      );
      return true;
    }
    return this.browserMainBackCoordinator.onBackPress(this.browserMainBackHost);
  }

  private refreshAiraCloudBookmarkV4BootstrapState(): void {
    this.airaCloudBookmarkV4BootstrapState = sharedAiraCloudBookmarkV4BootstrapRuntime.getViewState();
  }

  private startAiraCloudBookmarkV4Bootstrap(): void {
    void sharedAiraCloudBookmarkV4BootstrapRuntime.start(this.getAbilityContext()).catch((error: Error): void => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Aira Cloud Bookmark V4 bootstrap action failed: %{public}s',
        JSON.stringify(error));
      this.refreshAiraCloudBookmarkV4BootstrapState();
    });
  }

  private restoreAiraCloudBookmarkV4Backup(): void {
    void sharedAiraCloudBookmarkV4BootstrapRuntime.restoreBackupAndDisable().catch((error: Error): void => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Aira Cloud Bookmark V4 restore action failed: %{public}s',
        JSON.stringify(error));
      this.refreshAiraCloudBookmarkV4BootstrapState();
    });
  }

  private buildBrowserShellBackState(): BrowserShellBackState {
    return {
      manualElementHideSelectionActive: this.manualElementHideSelectionPresentation.active,
      managedSurfaceBackTarget: this.browserTransientSurfaceSnapshot.backTarget,
      largeScreenOmniboxEditing: this.isLargeScreenShellFamilyActive() &&
        this.browserLargeScreenOmniboxPresentation.editing,
      readerModeVisible: this.readerModeSessionSnapshot.state.visible,
      readerModeImagePreviewVisible: this.readerModeSessionSnapshot.overlayBackState.imagePreviewVisible,
      readerModePanelVisible: this.readerModeSessionSnapshot.overlayBackState.panelVisible,
      novelReaderVisible: this.novelReaderSnapshot.visible,
      novelReaderPanelVisible: this.novelReaderSnapshot.overlayBackState.panelVisible,
      customHomepageTransientBackActive: this.customHomepageRuntimeState.surfaceVisible &&
        this.customHomepageRuntimeState.transientBackHandlerActive,
      tabsSheetVisible: this.showTabsSheet,
      downloadPromptGuid: this.pendingDownloadPrompt?.guid ?? '',
      externalNavigationPromptVisible: this.externalNavigationPromptState.visible
    };
  }

  private isRootBottomPanelBackHandlingVisible(): boolean {
    return !this.showTabsSheet && (this.showHomePage || this.isWebPageVisible());
  }


  @Builder
  private buildPrivateModeLockOverlay() {
    BrowserPrivateModeLockOverlay({
      message: this.privateModeLockSessionSnapshot.message,
      authenticationInProgress: this.privateModeLockSessionSnapshot.authenticationInProgress,
      zIndexValue: PRIVATE_MODE_LOCK_OVERLAY_Z_INDEX,
      onAction: (action) => {
        this.browserPrivateModeLockCoordinator.handleUserAction(action);
      }
    })
  }

  private buildTopFloatingPromptHostState(): BrowserTopFloatingPromptHostState {
    const input: BrowserTopFloatingPromptShellInput = {
      urlThreatNotice: this.urlThreatNoticeState,
      backgroundOpenState: this.backgroundOpenPromptState,
      tabsSheetVisible: this.showTabsSheet,
      novelPrompt: this.novelReaderSnapshot.topPrompt,
      userScriptInstallPrompt: this.browserUserScriptApplicationSnapshot.installSuccessPrompt,
      externalNavigationState: this.externalNavigationPromptState,
      externalNavigationPageContext: this.buildExternalNavigationPromptPageContext(),
      offlineSave: this.offlinePageSaveSessionSnapshot,
      webpageTranslationState: this.webpageTranslationApplicationSnapshot.panel,
      webpageTranslationSurfaceVisible: this.isWebpageTranslationPanelSurfaceVisible(),
      gestureOnboardingState: this.gestureOnboardingPromptState,
      nativeVideoTakeoverVisible: this.isAssistantVideoTakeoverActive(),
      offsets: {
        showHomePage: this.showHomePage,
        topInsetVp: this.browserWindowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage()).topInsetVp,
        webTopChromeOverlayHeightVp: 0
      }
    };
    return this.browserTopFloatingPromptCoordinator.buildShellState(input);
  }

  @Builder
  private buildManualElementHideSelectionOverlay() {
    ManualElementHideSelectionOverlay({
      rootViewportWidth: this.rootViewportWidth,
      rootViewportHeight: this.rootViewportHeight,
      topOffsetVp: this.resolveWebpageTranslationOverlayTopOffsetVp(),
      presentation: this.manualElementHideSelectionPresentation,
      zIndexValue: MANUAL_ELEMENT_HIDE_OVERLAY_Z_INDEX,
      onAction: (action) => {
        this.manualElementHideRuntimeCoordinator.handleSelectionAction(action);
      }
    })
  }

  @Builder
  private buildWebModeShell() {
    BrowserWebViewportSurfaceHost({
      presentation: this.webViewportPresentation,
      backdropSnapshotId: WEB_BACKDROP_SNAPSHOT_ID,
      overlayVisible: this.pageFindBarState.visible && this.canOpenPageFind(),
      surfaceColor: this.getWebViewportBackdropColor(),
      surfaceOpacity: this.buildHostedWebLayerPresentationState().webSurfaceOpacity,
      surfaceScale: this.resolveWebSurfaceScale(),
      blurRadius: this.resolveWebSurfaceBlurRadius(),
      interactive: this.buildTabsOverviewSceneRenderState().webLayerInteractive,
      topChrome: (): void => {
        this.buildWebTopChrome();
      },
      content: () => {
        this.buildPullRefreshWebViewport()
      },
      loadingProgress: () => {
        this.buildWebLoadingProgressBar()
      },
      overlayContent: () => {
        this.buildWebPageFindOverlay()
      }
    })
    .id(buildBrowserTabPreviewVisibleSnapshotId(this.activeTabId))
  }

  @Builder
  private buildWebTopChrome() {
    BrowserWebTopChromeOverlay({
      overlayHeightPx: this.webViewportPresentation.topSafeOverlayHeightPx,
      surfaceColor: this.getWebViewportTopSafeAreaBackgroundColor(),
      colorTransitionDurationMs: WEB_TOP_SAFE_AREA_COLOR_TRANSITION_MS,
      quickSearchPresentation: this.quickSearchSwitchingPresentation,
      onSelectQuickSearchEngine: (engineId: string) =>
        this.browserQuickSearchSwitchingCoordinator.selectEngine(engineId)
    })
  }

  @Builder
  private buildPullRefreshWebViewport() {
    Refresh({
      refreshing: $$this.pullRefreshRefreshing,
      builder: () => {
        this.buildPullRefreshLoadingArea()
      }
    }) {
      Column() {
        this.buildWebViewportContent()
      }
      .width('100%')
      .height('100%')
    }
      .width('100%')
      .height('100%')
      .pullToRefresh(this.browserPullRefreshCoordinator.isEnabledForActiveSurface())
      .refreshOffset(48)
      .pullDownRatio(62)
      .pullUpToCancelRefresh(true)
      .onOffsetChange((offsetY: number) => {
        this.browserPullRefreshCoordinator.handleOffset(offsetY);
      })
      .onStateChange((status: RefreshStatus) => {
        this.browserPullRefreshCoordinator.handleStatus(status);
      })
      .onRefreshing(() => {
        this.browserPullRefreshCoordinator.requestRefresh();
      })
  }

  @Builder
  private buildPullRefreshLoadingArea() {
    BrowserPullRefreshLoadingArea({
      presentation: this.browserPullRefreshCoordinator.buildPresentation(this.pullRefreshState, 0),
      accentColor: this.themedHomeAccentColor,
      surfaceColor: this.getWebViewportBackdropColor()
    })
      .width('100%')
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildWebLoadingProgressBar() {
    if (this.buildWebLoadingProgressBarPresentationState().visible) {
      BrowserWebLoadingProgressBar({
        presentation: this.buildWebLoadingProgressBarPresentationState(),
        accentColor: this.themedHomeAccentColor
      })
        .width('100%')
        .position({
          x: 0,
          y: this.webViewportPresentation.contentTopPx
        })
        .hitTestBehavior(HitTestMode.None)
        .zIndex(8)
    }
  }

  @Builder
  private buildWebViewportContent() {
    Stack() {
      this.buildHostedWebLayer()
      BrowserWebErrorLayer({
        visible: this.shouldRenderWebPageErrorSurface(),
        presentation: this.browserWebPageLifecycleApplicationCoordinator.buildActiveLoadErrorPresentation(),
        bottomChromeInsetVp: this.getWebErrorSurfaceBottomInsetVp(),
        onAction: (action) => {
          this.browserWebPageLifecycleApplicationCoordinator.handleActiveLoadErrorSurfaceAction(action);
        }
      })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.getWebViewportBackdropColor())
  }

  private shouldRenderWebPageErrorSurface(): boolean {
    return this.buildHostedWebLayerPresentationState().pageErrorSurfaceVisible;
  }

  @Builder
  private buildHostedWebLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
        if (this.coldStartDeferredSurfaceContentMounted) {
          BrowserHostedWebFixedSlots({
            tabs: this.tabs,
            activeHostedTabId: this.activeHostedWebNodeTabId,
            hiddenSlots: this.hostedWebHiddenSlots,
            activeSurfaceVisible: this.activeHostedWebNodeTabId === this.activeTabId &&
              this.shouldMountHostedWebLayer() && !this.shouldSuspendHostedWebSurface(),
            surfaceRevision: this.activeHostedWebNodeRenderKey,
            resolveController: (tabId: string) => this.browserHostedRuntimeSurfacePort.getHostedController(tabId),
            resolveControllerGeneration: (tabId: string) =>
              this.browserHostedRuntimeSurfacePort.getHostedNodeGeneration(tabId)
          })
        }
    }
    .width('100%').height('100%')
    .backgroundColor(this.getWebViewportBackdropColor())
    .opacity(this.resolveHostedWebLayerOpacity())
    .hitTestBehavior(
      this.shouldRenderWebPageErrorSurface() ||
        this.shouldHideHostedWebLayerForErrorDocumentRetry()
        ? HitTestMode.None
        : HitTestMode.Default
    )
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const nextLeft = Math.round(this.parseAreaPosition(newArea.globalPosition.x) - this.rootViewportLeft);
      const nextTop = Math.round(this.parseAreaPosition(newArea.globalPosition.y) - this.rootViewportTop);
      const nextWidth = Math.max(1, Math.round(this.parseAreaDimension(newArea.width)));
      const nextHeight = Math.max(1, Math.round(this.parseAreaDimension(newArea.height)));
      this.hostedWebLayerLeft = nextLeft;
      this.hostedWebLayerTop = nextTop;
      this.hostedWebLayerWidth = nextWidth;
      this.hostedWebLayerHeight = nextHeight;
      this.hostedWebLayerMeasured = true;
      this.persistMeasuredWebLayerGeometry();
    })
  }

  private shouldSuspendHostedWebSurface(): boolean {
    return this.buildHostedWebLayerPresentationState().hostedWebSurfaceSuspended;
  }

  private shouldMountHostedWebLayer(): boolean {
    return this.buildHostedWebLayerPresentationState().hostedWebLayerMounted;
  }

  private resolveHostedWebLayerOpacity(): number {
    if (this.shouldHideHostedWebLayerForErrorDocumentRetry()) {
      return 0;
    }
    return this.buildHostedWebLayerPresentationState().hostedWebLayerOpacity;
  }

  private shouldHideHostedWebLayerForErrorDocumentRetry(): boolean {
    return this.activeErrorDocumentRetryTabId.length > 0 &&
      this.activeErrorDocumentRetryTabId === this.activeTabId;
  }

  private resolveWebSurfaceScale(): number {
    return this.buildHostedWebLayerPresentationState().webSurfaceScale;
  }

  private resolveWebSurfaceBlurRadius(): number {
    return this.buildHostedWebLayerPresentationState().webSurfaceBlurRadius;
  }

  private resolveTabsOverviewBackdropProgress(): number {
    if (!this.showTabsSheet) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.tabsOverviewPresentationState.surface.backdropProgress));
  }

  private resolveTabsOverviewBackdropOpenStartProgress(): number {
    return Math.max(0, Math.min(1, this.tabsOverviewPresentationState.surface.backdropProgress));
  }

  private buildHostedWebLayerPresentationState(): BrowserHostedWebLayerPresentationState {
    return this.browserHostedWebLayerPresentationViewModel.buildState({
      showPageErrorSurface: this.showPageErrorSurface,
      holdPageErrorSurfaceDuringReload: this.holdPageErrorSurfaceDuringReload,
      showTabsSheet: this.showTabsSheet,
      tabsSharedSnapshotState: this.tabsSharedSnapshotState,
      tabsOverviewScenePhase: this.tabsOverviewPresentationState.sceneState.phase,
      tabsOverviewEntryAnimationActive: this.tabsOverviewPresentationState.entryAnimationActive,
      tabsOverlayEntryMode: this.tabsOverviewPresentationState.surface.entryMode,
      tabsOverlayWebEntryProgress: this.tabsOverviewPresentationState.surface.webEntryProgress,
      tabsOverlayExiting: this.tabsOverviewPresentationState.exiting,
      tabsOverlayWebLayerOpacity: this.tabsOverviewPresentationState.surface.webLayerOpacity,
      tabsOverviewBackdropProgress: this.resolveTabsOverviewBackdropProgress()
    });
  }

  @Builder
  private buildRootAddressBottomPanel(
    scene: BrowserRootBottomPanelScene,
    renderContext: BrowserBottomPanelRenderContext
  ) {
    Stack() {
      if (!this.shouldHideRootBottomChromeForImmersion()) {
      BrowserBottomAddressPanel({
      presentationChannel: renderContext.presentationChannel,
      privateMode: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      appProxyActive: this.appProxyQuickSheetState.toolbarActive,
      liveBackdropBlurSuppressed: false,
      addressEditable: !this.buildCurrentDocumentViewerChromeContext().policy.active,
      viewerInfoActionEnabled: this.buildCurrentDocumentViewerChromeContext().policy.active && scene !== 'home',
      homeSuggestions: this.browserSearchSuggestionSnapshot.searchSuggestions,
      homeSuggestionsVisible: this.browserSearchSuggestionSnapshot.showSearchSuggestions,
      currentTabSuggestionRefId: this.activeTabId,
      responsiveState: renderContext.responsiveState,
      onPanelDetentChange: (detent: HomeSearchPanelDetent) => {
        this.applyRootBottomPanelDetent(detent);
      },
      onPanelGestureFrame: (frame: BrowserBottomAddressPanelGestureFrame) => {
        this.handleRootBottomPanelGestureFrame(frame);
      },
      onPanelVisualHeightChange: (panelHeight: number, expandedHeight: number) => {
        this.browserRootBottomPanelSessionCoordinator.updateSearchBackdropVisualHeight(
          panelHeight,
          expandedHeight,
          BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT,
          this.isRootBottomPanelExpansionEnabled()
        );
      },
      onPresentationHostReady: (hostHeight: number) => {
        this.browserRootBottomPanelSessionCoordinator.reportSearchPresentationHostReady(hostHeight);
      },
      onPanelDragEnd: (_panelHeight: number, targetDetent: HomeSearchPanelDetent) => {
        this.browserRootBottomPanelSessionCoordinator.endGestureWithSearchBackdrop(targetDetent);
      },
      onPanelSettled: (detent: HomeSearchPanelDetent) => {
        this.handleRootBottomPanelSettled(detent);
      },
      onPresentationHostDisconnected: () => {
        this.browserRootBottomPanelSessionCoordinator.reportSearchPresentationHostDisconnected();
      },
      onPanelDragEndIntercept: (
        panelHeight: number,
        targetDetent: HomeSearchPanelDetent,
        offsetY: number,
        source: BrowserBottomChromeGestureSource
      ) => {
        return this.interceptRootBottomPanelGestureEnd(panelHeight, targetDetent, offsetY, source);
      },
      onAddressFocusPrepare: () => {
        BrowserSearchInvocationRuntime.triggers(this.getWindowScopeId()).browserChrome.open();
        this.userScriptRuntimeCoordinator.scheduleDocumentStartScriptWarmup(
          this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate()
        );
      },
      onAddressFocusStateChange: (focused: boolean) => {
        this.applyRootBottomPanelSessionChromePlan(
          this.browserRootBottomPanelSessionCoordinator.buildAddressFocusStateChangePlan({
            focused: focused,
            isHomeMode: this.isRootBottomPanelEffectiveHomeMode(),
            isWebMode: this.isRootBottomPanelEffectiveWebMode()
          })
        );
      },
      onAddressChange: (value: string) => {
        this.protectRootAddressKeyboardSessionFromTransientHide();
        BrowserSearchInvocationRuntime.updateCurrentDraft(this.getWindowScopeId(), value);
        if (this.isRootBottomPanelEffectiveHomeMode()) {
          this.addressInput = value;
          this.browserSearchSuggestionCoordinator.refreshDeferred();
          return;
        }
        this.webBottomAddressDraft = value;
        this.browserSearchSuggestionCoordinator.refreshDeferred();
      },
      onAddressSubmit: (rawInput: string) => this.submitRootBottomAddressInput(rawInput),
      onAddressContextAction: (action: BrowserBottomAddressContextAction) =>
        this.browserRootBottomPanelActionApplication.handleAddressContextAction(action),
      onExternalAppSearch: (targetId: ExternalAppSearchTargetId, query: string) =>
        void this.addressSubmissionCoordinator.submitExternalAppSearch(
          targetId,
          query,
          this.selectedSearchEngine
        ),
      onHeaderAction: (actionId: string) => {
        this.dispatchRootBottomPanelAction('header', actionId);
      },
      onToolbarLongPress: (slotId: string) => {
        this.dispatchRootBottomPanelLongPress(slotId as BrowserToolbarSlotId);
      },
      onOpenSuggestion: (suggestion: SearchSuggestion) => {
        BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'submitted');
        this.browserShellSearchInvocationAdapter.openSuggestion(suggestion);
      },
      onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => {
        void this.browserSearchSuggestionCoordinator.deleteHistorySuggestion(suggestion);
      },
      onSearchBlankAreaBack: () => { this.browserMainBackCoordinator.onBackPress(this.browserMainBackHost); },
      onSelectSearchEngine: (engineId: SearchEngineId) => {
        this.browserTabHomeCoordinator.selectSearchEngine(engineId);
      },
      onHomeRevealSuggestions: () => {
        this.browserSearchSuggestionCoordinator.reveal();
      },
      onHomeDismiss: () => {
        BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'explicit_exit');
        this.browserShellSearchInvocationAdapter.dismissHomeSearch();
      },
      onAction: (actionId: BrowserBottomAddressPanelActionId) => {
        this.dispatchRootBottomPanelAction('panel', actionId);
      },
      onContinueReading: (): void => this.novelReaderSession.handleAction({ type: 'continue_reading' }),
      onKeyboardResizeSessionBegin: () => {
        this.requestRootBottomAddressInputKeyboardAvoidMode();
      },
      onKeyboardResizeSessionEnd: () => {
        this.releaseRootBottomAddressInputKeyboardAvoidMode();
      }
      })
      .width('100%')
      .height('100%')
      .zIndex(2)
      }

    }
    .width('100%')
    .height('100%')
  }

  private buildRootBottomPanelSemanticState(
    scene?: BrowserRootBottomPanelScene
  ): BrowserRootBottomPanelSemanticState {
    const input: BrowserRootBottomPanelSemanticInput = {
      showHomePage: this.showHomePage,
      webPageVisible: this.isWebPageVisible(),
      homeAddressFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
      webAddressFocused: this.webBottomAddressFocused
    };
    if (scene !== undefined) {
      return this.browserRootBottomPanelSessionCoordinator.buildSemanticStateForScene(scene, input);
    }
    return this.browserRootBottomPanelSessionCoordinator.buildSemanticState(input);
  }

  private syncRootBottomPanelBackAvailability(): void {
    this.browserRootBottomPanelSessionCoordinator.invalidatePresentation();
  }

  private isRootBottomPanelEffectiveHomeMode(): boolean {
    return this.buildRootBottomPanelSemanticState().effectiveHome;
  }

  private isRootBottomPanelEffectiveWebMode(): boolean {
    return this.buildRootBottomPanelSemanticState().effectiveWeb;
  }

  private resolveRootBottomPanelDetent(): HomeSearchPanelDetent {
    const documentViewerPolicy = this.buildCurrentDocumentViewerChromeContext().policy;
    return this.browserRootBottomPanelSessionCoordinator.resolveDetent({
      webVideoControllerActive: false,
      documentViewerActive: documentViewerPolicy.active,
      documentViewerExpansionEnabled: documentViewerPolicy.expansionEnabled,
      webAppImmersiveMode: this.isWebAppImmersiveMode(),
      fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled,
      currentDetent: this.rootBottomAddressPanelDetent
    });
  }

  private buildHomeScrollChromeInput(): BrowserHomeChromeInteractionInput {
    return {
      showTabsSheet: this.showTabsSheet,
      addressFocused: this.resolveRootBottomPanelAddressFocused(),
      currentDetent: this.resolveRootBottomPanelDetent(),
      documentViewerActive: this.buildCurrentDocumentViewerChromeContext().policy.active,
      webVideoControllerActive: false,
      webAppImmersiveMode: this.isWebAppImmersiveMode(),
      fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled,
    };
  }

  private shouldHideRootBottomChromeForImmersion(): boolean {
    return this.browserRootBottomPanelSessionCoordinator.shouldHideBottomChromeForImmersion({
      effectiveWebMode: this.isRootBottomPanelEffectiveWebMode(),
      webAppImmersiveMode: this.isWebAppImmersiveMode(),
      fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled,
      assistantVideoTakeoverActive: this.isAssistantVideoTakeoverActive()
    });
  }

  private isAssistantVideoTakeoverActive(): boolean {
    return this.arkWebMediaTakeoverCoordinator.getAssistantPlayerState(this.arkWebMediaTakeoverRevision).active;
  }

  private handleRootBottomPanelSettled(detent: HomeSearchPanelDetent): void {
    if (detent === 'low' || detent === 'peek') {
      this.browserRootBottomPanelSessionCoordinator.clearSearchBackdropExpandedHeight();
      this.browserRootBottomPanelSessionCoordinator.settleSearchBackdropToDetent(detent);
      this.browserRootBottomPanelSessionCoordinator.completeHomeToWebBottomPanelTransition(
        detent === 'low'
      );
    } else if (detent === 'middle') {
      this.browserRootBottomPanelSessionCoordinator.settleSearchBackdropToDetent(detent);
      this.browserRootBottomPanelSessionCoordinator.completeBackdropFocusTransition(detent);
    }
    const transition = this.browserRootBottomPanelSessionCoordinator.handlePanelSettled(detent);
    this.browserRootBottomPanelSessionCoordinator.invalidatePresentation();
    if (transition.shouldCommitRequestedDetent) {
      this.rootBottomAddressPanelDetent = detent;
    }
    if (transition.shouldDismissHomeSearch) {
      BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'explicit_exit');
      this.browserShellSearchInvocationAdapter.dismissHomeSearch();
      this.addressInput = '';
    }
    if (transition.shouldCommitRequestedDetent) {
      this.syncBottomPanelStatusBarStyle();
    }
    this.browserRootBottomPanelSessionCoordinator.completePanelSettleAfterEffects();
  }

  private handleRootBottomPanelGestureFrame(frame: BrowserBottomAddressPanelGestureFrame): void {
    this.browserRootBottomPanelSessionCoordinator.handleGestureFrame(
      this.buildRootBottomPanelGestureInput(frame.offsetY, frame.source),
      {
        phase: frame.phase,
        panelHeight: frame.panelHeight,
        middlePanelHeight: frame.middlePanelHeight,
        lowPanelHeight: BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT,
        expansionEnabled: this.isRootBottomPanelExpansionEnabled()
      }
    );
  }

  private buildRootBottomPanelGestureInput(
    offsetY: number,
    source: BrowserBottomChromeGestureSource
  ): BrowserRootBottomPanelGestureInput {
    const documentViewerPolicy = this.buildCurrentDocumentViewerChromeContext().policy;
    const semanticState = this.buildRootBottomPanelSemanticState();
    return {
      showHomePage: semanticState.effectiveHome,
      showTabsSheet: this.showTabsSheet,
      webPageVisible: semanticState.effectiveWeb,
      currentDetent: this.rootBottomAddressPanelDetent,
      addressFocused: this.resolveRootBottomPanelAddressFocused(),
      offsetY,
      source,
      peekGestureEnabled: this.browserRootBottomPanelSessionCoordinator.resolvePeekGestureEnabled({
        documentViewerActive: documentViewerPolicy.active
      }),
      documentViewerActive: documentViewerPolicy.active,
      webVideoControllerActive: false,
      webAppImmersiveMode: this.isWebAppImmersiveMode(),
      fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled
    };
  }

  private interceptRootBottomPanelGestureEnd(
    _panelHeight: number,
    _targetDetent: HomeSearchPanelDetent,
    offsetY: number,
    source: BrowserBottomChromeGestureSource
  ): HomeSearchPanelDetent | undefined {
    return this.browserRootBottomPanelSessionCoordinator.commitGestureRelease(
      this.buildRootBottomPanelGestureInput(offsetY, source),
      {
        settleBackdropToLow: (): void =>
          this.browserRootBottomPanelSessionCoordinator.settleSearchBackdropToDetent('low'),
        returnHome: (): void => { void this.returnHomeFromWebByClosingCurrentTab('bottom_gesture'); }
      },
      this.buildRootBottomPanelSessionSnapshot()
    );
  }

  private isRootBottomPanelExpansionEnabled(): boolean {
    const policy = this.buildCurrentDocumentViewerChromeContext().policy;
    return this.browserRootBottomPanelSessionCoordinator.resolveExpansionEnabled({
      documentViewerActive: policy.active,
      documentViewerExpansionEnabled: policy.expansionEnabled
    });
  }

  private applyRootBottomPanelDetent(detent: HomeSearchPanelDetent): void {
    const nextDetent = detent;
    this.browserRootBottomPanelSessionCoordinator.noteDetentApplication(nextDetent);
    this.browserRootBottomPanelSessionCoordinator.invalidatePresentation();
    this.browserRootBottomPanelSessionCoordinator.restoreScrollPresentation();
    const documentViewerPolicy = this.buildCurrentDocumentViewerChromeContext().policy;
    const committedState = this.browserRootBottomPanelSessionCoordinator.resolveCommittedDetent({
      effectiveWebMode: this.isRootBottomPanelEffectiveWebMode(),
      nextDetent,
      webVideoControllerActive: false,
      documentViewerActive: documentViewerPolicy.active,
      documentViewerExpansionEnabled: documentViewerPolicy.expansionEnabled,
      webAppImmersiveMode: this.isWebAppImmersiveMode(),
      fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled
    });
    if (committedState.clearWebAddressDraft) {
      this.setWebBottomAddressFocused(false);
      this.webBottomAddressDraft = '';
    }
    if (committedState.hideStatusBarForFullScreenMode) {
      this.browserWebTopImmersionSessionCoordinator.requestFullscreenHidden();
    }
    const committedDetent = committedState.detent;
    this.rootBottomAddressPanelDetent = committedDetent;
    this.browserRootBottomPanelSessionCoordinator.settleSearchBackdropForCommittedDetent(committedDetent);
    this.syncBottomPanelStatusBarStyle();
    if (!this.isRootBottomPanelEffectiveHomeMode() && committedDetent !== 'peek' && !this.webBottomAddressFocused) {
      this.browserWebTopImmersionSessionCoordinator.requestVisible('bottom-panel-detent');
    }
  }

  private syncBottomPanelStatusBarStyle(): void {
    this.refreshWebTopSafeAreaPageBackdropColor();
    this.browserStatusBarStyleService.applyLightContentStyle(
      getContext(this) as common.UIAbilityContext,
      this.shouldUseLightStatusBarContent()
    );
  }

  private restoreBottomPanelStatusBarStyle(): void {
    this.browserStatusBarStyleService.restoreDefaultStyle(getContext(this) as common.UIAbilityContext);
  }

  private shouldUseLightStatusBarContent(): boolean {
    const preferences = sharedPreferencesRepository.getPreferences();
    const homeDirectBackdropToneEffect = this.buildHomeDirectBackdropToneEffectState();
    return this.browserChromeRuntimeCoordinator.shouldUseLightStatusBarContent({
      state: this.browserChromeRuntimeState,
      activeTabId: this.activeTabId,
      webPageVisible: !this.showHomePage,
      globalImmersionEnabled: this.isTopImmersionPreferenceEnabled(),
      resolvedThemeMode: this.browserThemeModeCoordinator.resolveEffectiveMode(preferences.themeMode),
      readerModeVisible: this.readerModeSessionSnapshot.state.visible,
      readerModeTheme: this.articleReadingSession.resolveEffectiveTheme(
        this.browserThemeModeCoordinator.resolveEffectiveMode('system')
      ),
      homePageVisible: this.showHomePage,
      homeWallpaperState: this.resolveHomeWallpaperPresentationState(),
      homeThemeBackgroundColor: this.themedHomeBackground,
      homeBackdropEffectTintColor: homeDirectBackdropToneEffect?.tintColor,
      homeBackdropEffectTintOpacity: homeDirectBackdropToneEffect?.tintOpacity,
      webVideoControllerActive: false,
      bottomPanelHigh: false,
      bottomPanelVisible: this.isRootBottomPanelEffectiveHomeMode() || this.isRootBottomPanelEffectiveWebMode()
    });
  }

  private buildRootBottomPanelTransientSheetFacts(): BrowserRootBottomPanelTransientSheetFacts {
    return {
      isWebPageVisible: this.isWebPageVisible(),
      showTabsSheet: this.showTabsSheet,
      showHomePage: this.showHomePage,
      currentDetent: this.rootBottomAddressPanelDetent,
      activeTabId: this.activeTabId,
      webAddressFocused: this.webBottomAddressFocused
    };
  }

  private endTransientBottomSheetPresentation(owner: BrowserRootBottomPanelTransientSheetOwner): void {
    this.applyRootBottomPanelSessionChromePlan(
      this.browserRootBottomPanelSessionCoordinator.endTransientSheetPresentation(
        owner,
        this.buildRootBottomPanelTransientSheetFacts()
      )
    );
  }

  private resolveRootBottomPanelAddressFocused(): boolean {
    return this.browserRootBottomPanelSessionCoordinator.resolveAddressFocused(
      this.buildRootBottomAddressPresentationInput()
    );
  }

  private buildRootBottomAddressPresentationInput(): BrowserBottomAddressPresentationInput {
    return {
      addressInput: this.addressInput,
      isHomeMode: this.isRootBottomPanelEffectiveHomeMode(),
      isDocumentViewerPage: this.buildCurrentDocumentViewerChromeContext().policy.active,
      documentTitle: this.buildCurrentDocumentViewerChromeContext().title,
      transientMessageState: this.rootBottomPanelPresentationSnapshot.transientMessage,
      transientMessageContext: this.buildBottomAddressTransientMessageContext(),
      nowMs: Date.now(),
      homeSearchFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
      webBottomAddressFocused: this.webBottomAddressFocused,
      webBottomAddressInput: this.resolveWebBottomAddressInput()
    };
  }

  private buildBottomAddressTransientMessageContext(): BrowserBottomAddressTransientMessageContext {
    return {
      surface: this.isRootBottomPanelEffectiveHomeMode() ? 'home' : 'web',
      tabId: this.activeTabId,
      profileId: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().profileId,
      privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
      dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope
    };
  }

  private buildBottomAddressSuggestionInput(): BrowserBottomAddressSuggestionInput {
    return {
      addressInput: this.addressInput,
      webBottomAddressInput: this.resolveWebBottomAddressInput(),
      webPageVisible: this.isWebPageVisible(),
      showTabsSheet: this.showTabsSheet,
      showHomePage: this.showHomePage,
      webBottomAddressFocused: this.webBottomAddressFocused,
      webBottomAddressPanelDetent: this.rootBottomAddressPanelDetent
    };
  }

  @Builder
  private buildWebPageFindOverlay() {
    Column() {
      BrowserPageFindBar({
        state: this.pageFindBarState,
        onAction: (action) => {
          this.browserPageFindCoordinator.handleBarAction(this.activeTabId, action);
        }
      })
    }
    .width('100%')
    .margin({ top: WEB_PAGE_FIND_BAR_TOP_MARGIN })
    .zIndex(20)
  }

  private shouldRenderSharedSnapshotOverlay(): boolean {
    return this.tabsOverviewSessionCoordinator.shouldShowSharedSnapshotOverlay(this.tabsSharedSnapshotState);
  }

  private shouldMountRootBottomPanelHost(): boolean {
    const hostState = this.buildBottomPanelHostState();
    const tabsOverviewSceneRenderState = this.buildTabsOverviewSceneRenderState();
    if (hostState.mode === 'hidden') {
      return false;
    }
    return this.browserRootBottomPanelSessionCoordinator.shouldMountHost({
      showTabsSheet: this.showTabsSheet,
      retainForTabsOverviewEntry: tabsOverviewSceneRenderState.rootBottomPanelHostRetained,
      readerModeVisible: this.readerModeSessionSnapshot.state.visible,
      novelReaderVisible: this.novelReaderSnapshot.visible,
      webAppImmersiveMode: this.isWebAppImmersiveMode(),
      webVideoControllerFullscreenActive: false,
      largeScreenShellActive: this.browserShellPresentationOperations?.surface() === 'large_screen'
    });
  }

  private isWebAppImmersiveMode(): boolean {
    return this.webAppSessionCoordinator.isImmersive(this.webAppSessionSnapshot, {
      showHomePage: this.showHomePage,
      showTabsSheet: this.showTabsSheet
    });
  }

  private shouldHideWebAppTopSafeArea(): boolean {
    return this.webAppSessionCoordinator.buildImmersiveVisualState(this.webAppSessionSnapshot, {
      showHomePage: this.showHomePage,
      showTabsSheet: this.showTabsSheet,
      webPageVisible: this.isWebPageVisible(),
      fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled,
      globalImmersionEnabled: this.isTopImmersionPreferenceEnabled()
    }).hideTopSafeArea;
  }

  private applyWebAppSessionSnapshot(snapshot: WebAppSessionSnapshot, source: string): void {
    if (snapshot.windowId !== this.currentWindowId) {
      return;
    }
    this.webAppSessionSnapshot = snapshot;
    this.browserWebTopImmersionSessionCoordinator.syncPolicy(source);
    this.browserQuickSearchSwitchingCoordinator.refreshEligibility(source);
  }

  private getWebTopChromeStableInsetPx(): number {
    if (this.isLargeScreenShellFamilyActive()) {
      return 0;
    }
    const baseTopInsetPx = this.browserChromeRuntimeCoordinator.buildWebTopChromeInsetPx(
      this.browserWebTopImmersionSessionCoordinator.resolveWebTopSystemInsetVp(
        this.browserWindowAvoidAreaCoordinator.readStoredWebTopGeometryInsets(this.getSharedStageStorage())
      ),
      WEB_TOP_CHROME_CONTENT_GAP_VP
    );
    return BrowserWebViewportCoordinator.resolveVisibleTopChromeInset({
      baseTopInsetPx: baseTopInsetPx,
      occupiedChromeHeightPx: this.quickSearchSwitchingPresentation.occupiedHeightPx
    });
  }

  private isLargeScreenShellFamilyActive(): boolean {
    return (this.browserShellPresentationOperations?.snapshot()?.shellFamily ?? 'phone') === 'large_screen';
  }

  private getWebViewportTopInsetPx(): number {
    return this.getWebViewportVisualTopInsetPx();
  }

  private getWebViewportLayoutTopInsetPx(): number {
    return this.getWebTopChromeStableInsetPx();
  }

  private getWebViewportVisualTopInsetPx(): number {
    if (!this.webViewportVisualTopInsetInitialized) {
      return this.resolveTargetWebViewportVisualTopInsetPx();
    }
    return Math.max(0, Math.ceil(this.webViewportVisualTopInset));
  }

  private resolveWebViewportPresentationState(
    visualTopInsetPx: number = this.getWebViewportVisualTopInsetPx()
  ): BrowserWebViewportPresentationState {
    return BrowserWebViewportCoordinator.resolvePresentation({
      hostHeightPx: this.rootBottomPanelLayoutState.webHostHeight,
      visualTopInsetPx: visualTopInsetPx,
      fullViewport: this.buildCurrentDocumentViewerChromeContext().policy.fullViewport,
      largeScreenShellActive: this.isLargeScreenShellFamilyActive(),
      nativeVideoTakeoverActive: this.isAssistantVideoTakeoverActive()
    });
  }

  private refreshWebViewportPresentation(
    visualTopInsetPx: number = this.getWebViewportVisualTopInsetPx()
  ): void {
    this.webViewportPresentation = BrowserWebViewportCoordinator.resolvePresentationUpdate({
      current: this.webViewportPresentation,
      next: this.resolveWebViewportPresentationState(visualTopInsetPx)
    });
  }

  private setWebBottomAddressFocused(focused: boolean): void {
    this.webBottomAddressFocused = focused;
    this.syncRootAddressKeyboardOverlayInset();
    this.refreshWebViewportPresentation();
  }

  private alignWebViewportVisualTopInsetAfterSafeAreaSync(safeInsetsChanged: boolean, forceAlign: boolean = false): void {
    const alignment = BrowserWebViewportCoordinator.resolveTopInsetAlignment({
      safeInsetsChanged: safeInsetsChanged,
      forceAlign: forceAlign,
      webStatusBarVisible: this.webStatusBarVisible,
      webPageVisible: this.isWebPageVisible(),
      tabsSheetVisible: this.showTabsSheet,
      currentTopInsetPx: this.getWebViewportVisualTopInsetPx(),
      targetTopInsetPx: this.resolveTargetWebViewportVisualTopInsetPx()
    });
    if (!alignment.shouldAlign) {
      this.refreshWebViewportPresentation();
      return;
    }
    this.webViewportVisualTopInset = alignment.topInsetPx;
    this.webViewportVisualTopInsetInitialized = true;
    this.refreshWebViewportPresentation(alignment.topInsetPx);
  }

  private resolveTargetWebViewportVisualTopInsetPx(): number {
    if (!this.webStatusBarVisible) {
      return 0;
    }
    return this.getWebTopChromeStableInsetPx();
  }

  private buildCurrentDocumentViewerChromeContext(): DocumentViewerChromeContext {
    const tab = this.tabManager.getTab(this.tabs, this.activeTabId);
    return this.documentViewerService.resolveChromeContext(
      [
        tab?.pendingUrl ?? '',
        tab?.url ?? '',
        tab?.lastGoodUrl ?? '',
        this.currentUrl,
        this.pendingWebUrl
      ],
      this.currentTitle
    );
  }

  private buildCurrentBookmarkActionTarget(): BrowserBookmarkActionTarget {
    const url = this.resolveCurrentWebPageActionUrl();
    return {
      source: 'current_page',
      title: this.currentTitle.trim().length > 0 ? this.currentTitle : url,
      url: url,
      dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
      privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
      enabled: this.browserRootBottomPanelSessionCoordinator.resolveBookmarkActionAvailability(),
      homeShortcutScenarioId: this.homeShortcutApplicationSnapshot.scenarioId
    };
  }

  private getWebViewportBackdropColor(): ResourceColor {
    return this.browserRootBackgroundViewModel.resolveWebRootBackgroundColor({
      showHomePage: this.showHomePage,
      webVideoControllerActive: false,
      videoBackdropColor: WEB_VIEWPORT_DARK_SAFE_AREA_BACKGROUND_COLOR,
      themeHomeBackgroundColor: this.themedHomeBackground,
      themeHomeSurfaceBackgroundColor: this.themedHomeSurfaceBackground,
      webPageBackdropColor: this.webTopSafeAreaPageBackdropColor
    });
  }

  private getWebViewportTopSafeAreaBackgroundColor(): ResourceColor {
    return this.getWebViewportBackdropColor();
  }

  private resolveHomeRootBackgroundColor(): ResourceColor {
    return this.browserRootBackgroundViewModel.resolveHomeRootBackgroundColor({
      themeBackgroundColor: this.themedHomeBackground
    });
  }

  private resolveTabsSheetChromeIconTone(): AppChromeIconTone {
    return this.browserChromeRuntimeCoordinator.resolveChromeIconTone(
      this.browserThemeModeCoordinator.resolveEffectiveMode()
    );
  }

  private refreshWebTopSafeAreaPageBackdropColor(): void {
    const nextColor = this.resolveWebTopSafeAreaPageBackdropColor();
    if (this.webTopSafeAreaPageBackdropColor === nextColor) {
      return;
    }
    this.webTopSafeAreaPageBackdropColor = nextColor;
  }

  private resolveWebTopSafeAreaPageBackdropColor(): string {
    return this.browserChromeRuntimeCoordinator.resolveWebTopSafeAreaBackdropColor({
      state: this.browserChromeRuntimeState,
      activeTabId: this.activeTabId,
      webPageVisible: !this.showHomePage,
      globalImmersionEnabled: this.isTopImmersionPreferenceEnabled(),
      resolvedThemeMode: this.browserThemeModeCoordinator.resolveEffectiveMode()
    });
  }

  private resolveHomeWallpaperPresentationState(): HomeWallpaperPresentationState {
    if (!this.shouldUseSystemHomepageWallpaperBackdrop()) {
      return DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
    }
    return this.homeWallpaperState;
  }

  private shouldUseSystemHomepageWallpaperBackdrop(): boolean {
    return this.browserHomePresentationViewModel.shouldUseSystemHomepageWallpaperBackdrop(
      this.browserTabHomeCoordinator.buildHomeSurfaceProfile()
    );
  }

  private resolveHomeWallpaperDarkModeActive(): boolean {
    return this.browserThemeModeCoordinator.resolveEffectiveMode() === 'dark';
  }

  @Builder
  private buildTabsOverlay() {
    Stack() {
      this.buildTabsFloatingOverlay()
    }
    .width('100%')
    .height('100%')
    // Hidden while resident-but-closed (overlayOpacity is 1 after a close reset
    // because the old design unmounted the layer; residency must mask it here).
    .opacity(this.resolveTabsOverlayLayerOpacity())
    // opacity(0) does NOT disable hit-testing in ArkUI, and HitTestMode.None on a
    // container only disables the container itself (children still hit-test). A
    // resident-but-closed overlay therefore kept swallowing taps meant for the shell
    // beneath it, which read as the app freezing. enabled(false) disables the whole
    // subtree's interaction while keeping it mounted.
    .enabled(this.buildTabsOverviewSceneRenderState().cardsLayerMounted)
    .zIndex(TABS_OVERVIEW_OVERLAY_Z_INDEX)
  }

  private resolveTabsOverlayLayerOpacity(): number {
    if (!this.buildTabsOverviewSceneRenderState().cardsLayerMounted) {
      return 0;
    }
    return this.tabsOverviewPresentationState.surface.overlayOpacity;
  }

  @Builder
  private buildTabsFloatingOverlay() {
    BrowserTabsFloatingOverlay({
      tabs: this.tabs,
      previewStates: this.getTabPreviewStates(),
      openRequestVersion: this.tabsOverviewOpenRequestVersion,
      activeTabId: this.activeTabId,
      activeSection: this.resolveTabsSheetActiveSection(),
      morphCoveredTabId: this.tabsOverviewSessionCoordinator
        .projectScene(this.tabsOverviewPresentationState.sceneState).galleryCoveredTabId,
      selectionDisplacementTabId: this.tabsOverviewSessionCoordinator
        .projectScene(this.tabsOverviewPresentationState.sceneState).selectionDisplacementTabId,
      entryDisplacementTabId: this.tabsOverviewSessionCoordinator
        .projectScene(this.tabsOverviewPresentationState.sceneState).entryDisplacementTabId,
      entryDisplacementSettlingEnabled: this.tabsOverviewSessionCoordinator
        .projectScene(this.tabsOverviewPresentationState.sceneState).entryDisplacementSettlingEnabled,
      interactionEnabled: this.buildTabsOverviewSceneRenderState().cardsLayerInteractive,
      sideEntryAnimationEnabled: this.tabsOverviewSessionCoordinator
        .projectScene(this.tabsOverviewPresentationState.sceneState).sideEntryAnimationEnabled,
      viewportLeft: this.rootViewportLeft,
      viewportTop: this.rootViewportTop,
      viewportWidth: this.rootBottomPanelLayoutState.viewport.width,
      viewportHeight: this.rootBottomPanelLayoutState.viewport.height,
      topSafeInsetVp: this.browserWindowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage()).topInsetVp,
      backdropBlurRadius: 0,
      backgroundTintEnabled: false,
      backgroundSurfaceOpacity: this.buildTabsOverviewBackgroundRenderState().floatingGlassOpacity,
      layerOpacity: this.buildTabsOverviewSceneRenderState().cardsLayerOpacity,
      homeExitProgress: this.tabsOverviewPresentationState.surface.homeExitProgress,
      exiting: this.tabsOverviewPresentationState.exiting,
      blurPrivateTabPreviews: this.tabsSheetBlurPrivateTabPreviews,
      panelPageBackgroundColor: this.tabsSheetBackgroundColor,
      panelSecondaryTextColor: this.tabsSheetTextSecondaryColor,
      regularChromeIconTone: this.resolveTabsSheetChromeIconTone(),
      closeAllTabsAnimationRequestVersion: this.tabsOverviewPresentationState.closeAllAnimationRequestVersion,
      entrySharedSnapshotMounted: this.tabsOverviewSessionCoordinator.shouldRenderSharedSnapshotEntryOverlay(
        this.tabsSharedSnapshotState
      ),
      entrySharedSnapshotState: this.tabsSharedSnapshotState,
      entrySharedSnapshotBackgroundColor: this.getWebViewportTopSafeAreaBackgroundColor(),
      onDismiss: () => {
        this.dispatchTabsOverviewSession({ type: 'dismiss_to_home' });
      },
      onCreateTab: () => {
        this.dispatchTabsOverviewSession({ type: 'create_home' });
      },
      onRequestCloseAll: () => {
        this.tabsOverviewSessionCoordinator.requestCloseAllFromOverlay();
      },
      onCloseAllAnimationFinished: () => {
        this.tabsOverviewSessionCoordinator.finishCloseAllAnimationFromOverlay();
      },
      onSwitchSectionHome: (section: BrowserTabsOverviewSessionSection) => {
        this.dispatchTabsOverviewSession({ type: 'activate_section_home', section: section });
      },
      onActiveSectionChange: (section: BrowserTabsOverviewSessionSection) => {
        this.dispatchTabsOverviewSession({ type: 'change_section', section: section });
      },
      onSelectTab: (tabId: string, rect?: BrowserTabOverviewCardSelectRect) => {
        this.tabsOverviewSessionCoordinator.selectTabFromOverlay(
          tabId,
          rect?.left,
          rect?.top,
          rect?.width,
          rect?.height
        );
      },
      onCloseTab: (tabId: string) => {
        this.tabsOverviewSessionCoordinator.closeTabFromOverlay(tabId);
      },
      onPreviewRectChange: (tabId: string, left: number, top: number, width: number, height: number) => {
        this.tabsOverviewSessionCoordinator.rememberSharedSnapshotPreviewRect(tabId, left, top, width, height);
      },
      onEntryTargetPreviewRectReady: (tabId: string, left: number, top: number, width: number, height: number) => {
        this.tabsOverviewSessionCoordinator.rememberSharedSnapshotPreviewRect(tabId, left, top, width, height);
        this.dispatchTabsOverviewSession({
          type: 'entry_target_ready',
          tabId: tabId,
          left: left,
          top: top,
          width: width,
          height: height
        });
      },
      onEntrySharedSnapshotRectChange: (rect: BrowserTabsOverlayRect) => {
        if (this.tabsOverviewSessionCoordinator.shouldRenderSharedSnapshotEntryOverlay(this.tabsSharedSnapshotState)) {
          this.tabsOverviewSessionCoordinator.rememberSharedSnapshotEntryFrame(rect);
        }
      },
      onEntrySharedSnapshotTap: (tabId: string) => {
        this.dispatchTabsOverviewSession({ type: 'interrupt_entry_selection', tabId: tabId });
      },
      onOpenDeviceTabs: () => {
        sharedCrossDeviceTabPresenceCoordinator.requestOpenPanel(
          this.featureGateCoordinator,
          this.crossDeviceTabPresenceEntryHost
        );
      }
    })
  }

  @Builder
  private buildTabsBackdropSnapshot() {
    HomeBackdropLayer({
      wallpaperState: this.resolveHomeWallpaperPresentationState(),
      darkModeActive: this.resolveHomeWallpaperDarkModeActive(),
      themeBackgroundColor: this.resolveHomeRootBackgroundColor(),
      privateModeVisible: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      frameWidth: this.rootViewportWidth,
      frameHeight: this.rootViewportHeight,
      contentScale: this.buildTabsHomeBackdropEffectState().contentScale,
      blurRadius: this.buildTabsHomeBackdropEffectState().blurRadius,
      blurEdgeScale: this.buildTabsHomeBackdropEffectState().blurEdgeScale,
      tintColor: this.buildTabsHomeBackdropEffectState().tintColor,
      tintOpacity: this.buildTabsHomeBackdropEffectState().tintOpacity
    })
    .width('100%')
    .height('100%')
    .opacity(this.buildTabsOverviewBackgroundRenderState().homeBackdropOpacity)
    .hitTestBehavior(HitTestMode.None)
    .zIndex(TABS_OVERVIEW_OVERLAY_Z_INDEX - 2)
  }

  @Builder
  private buildRootBottomPanelHost() {
    BrowserBottomPanelHost({
      mode: this.buildBottomPanelHostState().mode,
      scene: this.buildBottomPanelHostState().scene,
      tabsOverviewHomeEntryRequestVersion:
        this.homePresentationSessionState.bottomPanelEntryFromTabsOverviewRequestVersion,
      tabsOverviewHomeEntryEligible: this.buildBottomPanelHostState().tabsOverviewHomeEntryEligible,
      hostHeight: this.buildBottomPanelHostState().hostHeight,
      responsiveState: this.rootBottomPanelLayoutState.responsiveState,
      livePresentation: this.browserRootBottomPanelSessionCoordinator.buildLivePresentation({
        panelMotionState: this.buildRootBottomPanelMotionState(),
        semanticState: this.buildRootBottomPanelSemanticState(),
        responsiveState: this.rootBottomPanelLayoutState.responsiveState,
        responsiveLayoutKey: this.rootBottomPanelLayoutState.layoutRenderKey,
        currentDetent: this.resolveRootBottomPanelDetent(),
        panelExpansionEnabled: this.buildRootBottomPanelMotionState().panelExpansionEnabled,
        addressPresentation: this.buildRootBottomAddressPresentationInput(),
        searchEnginePresentation: this.browserTabHomeCoordinator.buildSearchEngineChromePresentation(
          this.selectedSearchEngine,
          this.availableSearchEngines
        ),
        addressEditable: !this.buildCurrentDocumentViewerChromeContext().policy.active,
        webProtectionFeedback: this.siteControlsApplicationSnapshot.webProtectionFeedback,
        readingSnapshot: this.novelReaderSnapshot
      }),
      layoutRenderKey: this.rootBottomPanelLayoutState.layoutRenderKey,
      layerZIndex: this.buildBottomPanelHostState().zIndex,
      interactiveOutsidePanel: this.buildBottomPanelHostState().interactiveOutsidePanel,
      homePanel: (renderContext: BrowserBottomPanelRenderContext) => {
        this.buildRootAddressBottomPanel('home', renderContext)
      },
      webPanel: (renderContext: BrowserBottomPanelRenderContext) => {
        this.buildRootAddressBottomPanel('web', renderContext)
      }
    })
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .zIndex(this.buildBottomPanelHostState().zIndex)
  }

  @Builder
  private buildRootBottomPanelExpandedScrim() {
    BrowserRootBottomPanelExpandedScrim({
      scrimOpacity: this.buildRootBottomPanelExpandedScrimState().backdropProgress,
      blockHitTest: this.buildRootBottomPanelExpandedScrimState().blockHitTest,
      surfaceEligible: this.buildRootBottomPanelExpandedScrimState().surfaceEligible,
      settledVisible: this.buildRootBottomPanelExpandedScrimState().visible,
      presentationChannel:
        this.browserRootBottomPanelSessionCoordinator.getSearchBackdropPresentationChannel(),
      onDismiss: () => {
        this.collapseRootBottomPanelFromScrim();
      }
    })
      .zIndex(ROOT_BOTTOM_PANEL_EXPANDED_SCRIM_Z_INDEX)
  }

  @Builder
  private buildVideoAssistantPlayerOverlay() {
    BrowserVideoAssistantPlayerOverlay({
      playerState: this.arkWebMediaTakeoverCoordinator.getAssistantPlayerState(this.arkWebMediaTakeoverRevision),
      webLiveTransitionPending: this.arkWebMediaTakeoverCoordinator.isWebLiveAssistantTransitionPending(
        this.arkWebMediaTakeoverRevision
      ),
      playerBackgroundColor: $r('app.color.browser_video_assistant_background'),
      playerControlColor: $r('app.color.browser_video_assistant_control'),
      playerControlScrimColor: $r('app.color.browser_video_assistant_control_scrim'),
      playerProgressTrackColor: $r('app.color.browser_video_assistant_progress_track'),
      playerTransparentColor: $r('app.color.browser_video_assistant_transparent'),
      onAction: (action): void => {
        this.arkWebMediaTakeoverCoordinator.handleAssistantPlayerAction(
          action,
          this.arkWebMediaAssistantPlayerHost
        );
      }
    })
      .width('100%')
      .height('100%')
      .zIndex(NATIVE_VIDEO_TAKEOVER_OVERLAY_Z_INDEX + 1)
  }

  private isVideoTakeoverBlockingSurfaceVisible(): boolean {
    return this.browserTransientSurfaceCoordinator.isVideoTakeoverBlocked(this.buildTransientPromptBlockingFacts());
  }

  private async exitVideoAssistantFullscreenAsync(showToast: boolean): Promise<void> {
    await this.browserFullscreenSessionCoordinator.exitVideoAssistantFullscreen(showToast, false);
  }

  private resolveSearchBackdropRawProgress(): number {
    return this.browserRootBottomPanelSessionCoordinator.resolveSearchBackdropProgress(
      this.showTabsSheet,
      this.browserShellPresentationOperations?.surface() !== 'large_screen' &&
        this.buildBottomPanelHostState().mode === 'browser'
    );
  }

  private buildRootBottomPanelExpandedScrimState(): BrowserRootBottomPanelExpandedScrimState {
    const semanticState = this.buildRootBottomPanelSemanticState();
    return this.browserRootBottomPanelSessionCoordinator.buildExpandedScrimState({
      readerModeVisible: this.readerModeSessionSnapshot.state.visible,
      novelReaderVisible: this.novelReaderSnapshot.visible,
      homePageVisible: semanticState.effectiveHome,
      tabsSheetVisible: this.showTabsSheet,
      webPageVisible: semanticState.effectiveWeb,
      bottomPanelHostVisible: this.browserShellPresentationOperations?.surface() !== 'large_screen' &&
        this.buildBottomPanelHostState().mode === 'browser',
      detent: this.resolveRootBottomPanelDetent(),
      backdropProgress: this.resolveSearchBackdropRawProgress()
    });
  }

  private collapseRootBottomPanelFromScrim(): void {
    BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'explicit_exit');
    const plan = this.browserRootBottomPanelSessionCoordinator.buildExpandedScrimDismissPlan({
      showHomePage: this.showHomePage,
      homeSearchFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
      homeSearchOverlayVisible: this.browserSearchSuggestionSnapshot.homeSearchOverlayVisible,
      expandedScrimVisible: this.buildRootBottomPanelExpandedScrimState().visible,
      isHomeMode: this.isRootBottomPanelEffectiveHomeMode(),
      isWebMode: this.isRootBottomPanelEffectiveWebMode(),
      currentDetent: this.resolveRootBottomPanelDetent(),
      panelExpansionEnabled: this.isRootBottomPanelExpansionEnabled()
    });
    this.applyRootBottomPanelSessionChromePlan(plan);
  }

  private requestRootBottomPanelCollapse(): void {
    if (!this.buildRootBottomPanelExpandedScrimState().visible) {
      return;
    }
    this.applyRootBottomPanelSessionChromePlan(
      this.browserRootBottomPanelSessionCoordinator.buildProgrammaticCollapsePlan(
        this.buildRootBottomPanelSessionSnapshot()
      )
    );
  }

  private ensureRootBottomPanelAddressFocusBackdropTransition(
    surface: BrowserBottomPanelBackdropSurface
  ): void {
    this.beginRootBottomPanelLiveAddressFocusBackdropTransition(surface);
  }

  private beginRootBottomPanelLiveAddressFocusBackdropTransition(
    surface: BrowserBottomPanelBackdropSurface
  ): void {
    this.browserRootBottomPanelSessionCoordinator.beginSearchBackdropFocusTransition(
      surface,
      this.resolveRootBottomPanelDetent()
    );
  }

  private cancelRootBottomPanelAddressFocusBackdropTransition(): void {
    this.browserRootBottomPanelSessionCoordinator.cancelBackdropFocusTransition();
  }

  private shouldKeepRootBottomPanelHomeBackdropSurfaceEligible(): boolean {
    return this.isRootBottomPanelEffectiveHomeMode() &&
      this.shouldKeepRootBottomPanelBackdropSurfaceEligible();
  }

  private shouldKeepRootBottomPanelBackdropSurfaceEligible(): boolean {
    return !this.showTabsSheet &&
      !this.readerModeSessionSnapshot.state.visible &&
      !this.novelReaderSnapshot.visible &&
      this.isRootBottomPanelExpansionEnabled();
  }

  private buildHomeDirectBackdropToneEffectState(): BrowserBackdropEffectState | undefined {
    if (!this.shouldUseHomeDirectBackdropToneEffect()) {
      return undefined;
    }
    return this.browserBackdropEffectViewModel.buildHomeLiveState(1);
  }

  private shouldUseHomeDirectBackdropToneEffect(): boolean {
    return this.browserRootBottomPanelSessionCoordinator.shouldUseDirectSearchBackdropToneEffect(
      this.shouldKeepRootBottomPanelHomeBackdropSurfaceEligible(),
      this.resolveSearchBackdropRawProgress()
    );
  }

  private buildTabsHomeBackdropEffectState(): BrowserBackdropEffectState {
    return this.browserBackdropEffectViewModel.buildTabsHomeRevealState(
      this.buildTabsOverviewBackgroundRenderState().homeBackdropEffectProgress
    );
  }

  private buildBottomPanelHostState(): BrowserBottomPanelHostState {
    const viewportState = this.rootBottomPanelLayoutState.viewport;
    const semanticState = this.buildRootBottomPanelSemanticState();
    const homeChromePolicy = this.browserTabHomeCoordinator.buildHomeSystemChromePolicyState(
      semanticState.effectiveHome ? true : undefined
    );
    const input: BrowserBottomPanelHostInput = {
      scene: semanticState.scene,
      homeSearchBarVisible: homeChromePolicy.bottomPanelHomeSearchVisible,
      homeSearchSessionActive: this.browserSearchSuggestionSnapshot.homeSearchFocused ||
        this.browserSearchSuggestionSnapshot.homeSearchOverlayVisible ||
        this.browserRootBottomPanelSessionCoordinator.isHomeToWebBottomPanelTransitionActive(),
      readerModeVisible: this.readerModeSessionSnapshot.state.visible,
      novelReaderVisible: this.novelReaderSnapshot.visible,
      viewportHeight: viewportState.height,
      browserHostHeight: this.browserRootBottomPanelSessionCoordinator.resolveActiveHostHeight(
        this.rootBottomPanelLayoutState,
        semanticState.effectiveHome
      )
    };
    return this.browserRootBottomPanelSessionCoordinator.buildHostState(input);
  }

  private buildRootBottomPanelMotionState(): BrowserBottomPanelMotionState {
    // Keep the ArkUI dependency on the Session-owned requested detent reactive.
    this.rootBottomPanelPresentationSnapshot.revision;
    const documentViewerPolicy = this.buildCurrentDocumentViewerChromeContext().policy;
    const input: BrowserRootBottomPanelMotionInput = {
      currentDetent: this.resolveRootBottomPanelDetent(),
      immediateLowDetentRequestVersion: this.rootBottomPanelImmediateLowDetentRequestVersion,
      layoutState: this.rootBottomPanelLayoutState,
      showHomePage: this.isRootBottomPanelEffectiveHomeMode(),
      keyboardOverlayInset: this.rootAddressKeyboardOverlayInsetVp,
      fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled,
      documentViewerActive: documentViewerPolicy.active,
      documentViewerScrollCollapseEnabled: documentViewerPolicy.scrollCollapseEnabled,
      documentViewerExpansionEnabled: documentViewerPolicy.expansionEnabled
    };
    return this.browserRootBottomPanelSessionCoordinator.buildMotionState(input);
  }

  @Builder
  private buildHomePage() {
    BrowserHomePrimarySurface({
      presentation: this.buildHomePagePresentationState(),
      surfaceBackgroundColor: this.resolveHomeRootBackgroundColor(),
      content: () => {
        this.buildHomeLiveContent()
      }
    })
  }

  @Builder
  private buildHomeLiveContent() {
    CustomHomepageSurface({
      renderer: this.browserTabHomeCoordinator.buildHomeSurfaceProfile().renderer,
      runtimeState: this.customHomepageRuntimeState,
      wallpaperState: this.resolveHomeWallpaperPresentationState(),
      darkModeActive: this.resolveHomeWallpaperDarkModeActive(),
      themeBackgroundColor: this.resolveHomeRootBackgroundColor(),
      privateModeVisible: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      contentPresentation: this.buildHomeSurfaceContentPresentationState(),
      errorBottomInsetVp: this.browserTabHomeCoordinator.resolveCustomHomepageErrorBottomInset(
        this.buildHomeResponsiveLayoutState(),
        BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT
      ),
      systemEntryButtonVisible: this.browserTabHomeCoordinator
        .buildHomeSystemChromePolicyState().systemEntryButtonVisible,
      viewportWidth: this.rootBottomPanelLayoutState.viewport.width,
      viewportHeight: this.rootBottomPanelLayoutState.viewport.height,
      primaryTextColor: this.themedHomeTextPrimaryColor,
      secondaryTextColor: this.themedHomeTextSecondaryColor,
      resolveHostedWebNode: () => this.customHomepageHostedWebNode,
      onAction: (action) => this.customHomepageRuntimeCoordinator.handleSurfaceAction(action)
    }) {
      this.buildSystemHomePage()
    }
  }

  @Builder
  private buildSystemHomePage() {
    HomeSystemSurface({
      wallpaperState: this.resolveHomeWallpaperPresentationState(),
      darkModeActive: this.resolveHomeWallpaperDarkModeActive(),
      themeBackgroundColor: this.resolveHomeRootBackgroundColor(),
      privateModeVisible: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      backdropEffectState: DEFAULT_BROWSER_BACKDROP_EFFECT_STATE,
      searchFocused: this.browserRootBottomPanelSessionCoordinator.shouldMountHomeSearchDismissLayer({
        showHomePage: this.showHomePage,
        homeSearchFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
        homeSearchOverlayVisible: this.browserSearchSuggestionSnapshot.homeSearchOverlayVisible,
        expandedScrimVisible: this.buildRootBottomPanelExpandedScrimState().visible
      }),
      contentPresentation: this.buildHomeSurfaceContentPresentationState(),
      onDismissSearchFocus: () => {
        this.collapseRootBottomPanelFromScrim();
      }
    }) {
      if (this.coldStartDeferredSurfaceContentMounted) {
        this.buildHomeScrollableContent()
      }
    }
  }

  private scheduleColdStartPostFirstFrameWork(): void {
    const generation = ++this.coldStartDeferredContentMountGeneration;
    try {
      this.getUIContext().postFrameCallback(new BrowserColdStartDeferredSurfaceContentFrameCallback((): void => {
        if (generation !== this.coldStartDeferredContentMountGeneration) {
          return;
        }
        this.browserShellLifecycleCoordinator.handlePostFirstFrame();
      }));
    } catch (error) {
      this.browserShellLifecycleCoordinator.handlePostFirstFrame();
    }
  }


  @Builder
  private buildHomeScrollableContent() {
    HomeContentSections({
      showShortcuts: this.showHomeShortcuts,
      recentlyClosedExpanded: this.recentlyClosedApplicationSnapshot.homeSectionExpanded,
      presentation: this.browserTabHomeCoordinator.buildContentPresentation({
        responsiveLayout: this.buildHomeResponsiveLayoutState(),
        shortcuts: this.homeShortcutApplicationSnapshot,
        recentlyClosed: this.recentlyClosedApplicationSnapshot,
        viewportWidth: this.rootBottomPanelLayoutState.viewport.width,
        viewportHeight: this.rootBottomPanelLayoutState.viewport.height,
        bottomPanelLowHeight: BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT,
        privateMode: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate()
      }),
      theme: this.browserTabHomeCoordinator.buildContentThemePresentation({
        wallpaperState: this.resolveHomeWallpaperPresentationState(),
        themeBackgroundColor: this.themedHomeBackground,
        themedPrimaryTextColor: this.themedHomeTextPrimaryColor,
        themedSecondaryTextColor: this.themedHomeTextSecondaryColor,
        themedPressedBackgroundColor: this.themedHomePressedBackground,
        controlBackgroundColor: this.themedHomeControlBackground,
        accentColor: this.themedHomeAccentColor
      }),
      contextMenuShortcutId: $contextMenuHomeShortcutId,
      onAction: (action) => {
        this.browserTabHomeCoordinator.handleContentAction(action);
      }
    })
  }

  private buildTabsOverviewSceneRenderState(): BrowserTabsOverviewSceneRenderState {
    return this.tabsOverviewSessionCoordinator.buildRenderState(this.tabsOverviewPresentationState);
  }

  private shouldKeepCustomHomepageWebResident(): boolean {
    return this.browserHomePresentationViewModel.shouldKeepCustomHomepageWebResident(
      this.customHomepageRuntimeState.presentation
    );
  }

  private buildTabsOverviewBackgroundRenderState(): BrowserTabsOverviewBackgroundRenderState {
    return this.tabsOverviewSessionCoordinator.buildBackgroundRenderState({
      showTabsSheet: this.showTabsSheet,
      tabsOverlayExiting: this.tabsOverviewPresentationState.exiting,
      snapshotVisible: this.tabsOverviewPresentationState.surface.backdropSnapshotVisible,
      openedFromHome: this.tabsOverviewPresentationState.sceneState.openedFromHome,
      scenePhase: this.tabsOverviewPresentationState.sceneState.phase,
      snapshotOpacity: this.tabsOverviewPresentationState.surface.backdropSnapshotOpacity,
      homeExitProgress: this.tabsOverviewPresentationState.surface.homeExitProgress,
      backdropProgress: this.tabsOverviewPresentationState.surface.backdropProgress
    });
  }

  private shouldRenderTabsBackdropSnapshot(): boolean {
    return this.buildTabsOverviewBackgroundRenderState().homeBackdropVisible;
  }

  private applyBrowserTransientSurfaceUpdate(update: BrowserTransientSurfaceUpdate): void {
    this.browserTransientSurfaceSnapshot = update.snapshot;
    this.browserMediaResourceSessionCoordinator.handleTransientSurfaceUpdate(update);
    this.browserUserScriptApplicationCoordinator.handleSurfaceUpdate(update);
    this.browserWebPageToolsCoordinator.handleTransientSurfaceUpdate(update);
    if (update.lane === 'custom_bottom' &&
      (update.reason === 'dismissed' || update.reason === 'reset')) {
      if (update.surfaceId === 'app_proxy_quick') {
        this.appProxyQuickSheetCoordinator.handleSurfaceDismissed();
      } else if (update.surfaceId === 'wifi_qr_result') {
        this.browserQrScanCoordinator.handleSurfaceDismissed('wifi_credentials');
      } else if (update.surfaceId === 'feature_gate') {
        this.featureGateCoordinator.handleSurfaceDismissed();
      }
    }
    if (update.lane === 'custom_bottom' && update.chromePlan !== undefined) {
      this.applyRootBottomPanelSessionChromePlan(update.chromePlan);
    }
  }

  @Builder
  private buildActiveBrowserTransientSurface() {
    if (this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceId === 'element_inspection') {
      ElementInspectionOverlay({
        visible: this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceVisible,
        topOffsetVp: this.resolveWebpageTranslationOverlayTopOffsetVp(),
        webLayerLeftVp: this.hostedWebLayerLeft,
        webLayerTopVp: this.hostedWebLayerTop,
        webLayerWidthVp: this.hostedWebLayerWidth,
        webLayerHeightVp: this.hostedWebLayerHeight,
        presentation: this.elementInspectionPresentation,
        onAction: (action) => {
          this.elementInspectionSessionCoordinator.handleAction(action);
        },
        onSelectNormalizedPoint: (normalizedX: number, normalizedY: number): void => {
          this.elementInspectionSessionCoordinator.selectAtNormalizedPoint(normalizedX, normalizedY);
        }
      })
    } else if (this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceId === 'wifi_qr_result' &&
      this.browserQrScanSessionSnapshot.wifiCredentials !== undefined) {
      BrowserWifiQrResultOverlay({
        credentials: this.browserQrScanSessionSnapshot.wifiCredentials,
        accentColor: this.themedHomeAccentColor,
        externallyControlled: true,
        presentationVisible: this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceVisible,
        layoutMode: this.browserShellPresentationOperations?.snapshot()?.shellFamily ?? 'phone',
        onAction: (action) => {
          this.browserQrScanCoordinator.handleWifiResultAction(action);
        }
      })
    } else if (this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceId === 'feature_gate') {
      FeatureGateOverlay({
        visible: this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceVisible,
        state: this.featureGateSnapshot,
        layoutMode: this.browserShellPresentationOperations?.snapshot()?.shellFamily ?? 'phone',
        onAction: (action: FeatureGateAction) => {
          this.featureGateCoordinator.handleAction(action);
        }
      })
    } else if (this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceId === 'bookmark_folder_selection') {
      BookmarkMoveFolderSelectionOverlay({
        visible: this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceVisible,
        snapshot: this.browserBookmarkActionSessionSnapshot,
        layoutMode: this.browserShellPresentationOperations?.snapshot()?.shellFamily ?? 'phone',
        onAction: (action) => {
          this.browserBookmarkActionCoordinator.handleFolderSelectionAction(action);
        }
      })
    } else if (this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceId === 'translation_target_language') {
      WebpageTranslationTargetLanguageOverlay({
        visible: this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceVisible,
        layoutMode: this.browserShellPresentationOperations?.snapshot()?.shellFamily ?? 'phone',
        selectedLanguage: this.webpageTranslationApplicationSnapshot.panel.targetLanguage,
        helperText: this.webpageTranslationApplicationSnapshot.targetLanguage.helperText,
        options: this.webpageTranslationApplicationSnapshot.targetLanguage.options,
        onAction: (action) => {
          this.webpageTranslationCoordinator.handleTargetLanguageAction(action);
        }
      })
    } else if (this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceId === 'reader_speech_player') {
      ReaderSpeechPlayerOverlay({
        visible: this.browserTransientSurfaceSnapshot.activeCustomBottomSurfaceVisible,
        article: this.readerModeSessionSnapshot.state.article,
        chunks: this.readerModeSessionSnapshot.speech.chunks,
        speechState: this.readerModeSessionSnapshot.speech.state,
        readerTheme: this.articleReadingSession.resolveEffectiveTheme(
          this.browserThemeModeCoordinator.resolveEffectiveMode('system')
        ),
        speed: this.readerModeSessionSnapshot.speech.speed,
        voiceLabel: this.readerModeSessionSnapshot.speech.voiceLabel,
        bottomSafeInsetVp: this.getReaderModeBottomSafeInsetVp(),
        onAction: (action) => {
          this.articleReadingSession.handleSpeechPlayerAction(
            action,
            () => this.openReaderSpeechVoiceDialog()
          );
        }
      })
    }
  }

  private refreshRootBottomPanelLayoutState(): void {
    this.rootBottomPanelLayoutState = this.browserRootBottomPanelSessionCoordinator.buildLayoutState({
      viewportWidth: this.rootViewportWidth,
      viewportHeight: this.rootViewportHeight,
      displayViewportWidth: this.browserWindowDisplayViewportWidth,
      displayViewportHeight: this.browserWindowDisplayViewportHeight,
      homeAddressFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
      webAddressFocused: this.webBottomAddressFocused
    });
  }

  private async exitPrivateModeAsync(clearPrivateData: boolean): Promise<void> {
    await this.browserPrivateTabCoordinator.exitPrivateMode(
      this.tabs,
      this.activeTabId,
      this.browserTabCloseCoordinator,
      clearPrivateData,
      this.browserPrivateModeExitHost
    );
  }

  private handlePrivateForegroundRevisionChange(): void {
    this.browserPrivateModeLockCoordinator.handleForegroundResume();
  }

  private resolveOpenTabsButtonTabCount(): number {
    return this.browserOpenTabsButtonViewModel.resolveTabCount({
      tabs: this.tabs,
      privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
      dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope
    });
  }

  private syncWindowSafeInsetsForShell(forceWebTopInsetAlign: boolean = false): void {
    window.getLastWindow(this.getAbilityContext())
      .then((mainWindow: window.Window) => {
        const syncResult = this.browserWindowAvoidAreaCoordinator.syncStorageWithResult(
          mainWindow,
          this.getSharedStageStorage()
        );
        const safeInsets = syncResult.nextInsets;
        this.homeTopSafeInsetVp = safeInsets.topInsetVp;
        this.homeBottomSafeInsetVp = safeInsets.bottomInsetVp;
        this.homeLeftSafeInsetVp = safeInsets.leftInsetVp;
        this.homeRightSafeInsetVp = safeInsets.rightInsetVp;
        this.rootKeyboardInsetVp = this.browserWindowAvoidAreaCoordinator.readKeyboardInset(this.getSharedStageStorage());
        this.syncRootAddressKeyboardOverlayInset();
        this.alignWebViewportVisualTopInsetAfterSafeAreaSync(syncResult.changed, forceWebTopInsetAlign);
      })
      .catch((_error: Error) => {
        const safeInsets = this.browserWindowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage());
        this.homeTopSafeInsetVp = safeInsets.topInsetVp;
        this.homeBottomSafeInsetVp = safeInsets.bottomInsetVp;
        this.homeLeftSafeInsetVp = safeInsets.leftInsetVp;
        this.homeRightSafeInsetVp = safeInsets.rightInsetVp;
        this.rootKeyboardInsetVp = this.browserWindowAvoidAreaCoordinator.readKeyboardInset(this.getSharedStageStorage());
        this.syncRootAddressKeyboardOverlayInset();
        this.refreshWebViewportPresentation();
      });
  }

  private syncRootAddressKeyboardOverlayInset(): void {
    if (!this.resolveRootBottomPanelAddressFocused()) {
      this.rootAddressKeyboardOverlayInsetVp = 0;
      return;
    }
    const keyboardInset = Math.max(0, Math.ceil(this.rootKeyboardInsetVp));
    if (keyboardInset > 0) {
      this.rootAddressKeyboardOverlayInsetVp = keyboardInset;
    }
  }

  private applyRootAddressKeyboardOverlayInset(insetVp: number): void {
    const nextInsetVp = Math.max(0, Math.ceil(insetVp));
    if (nextInsetVp !== this.rootKeyboardInsetVp) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'root_address_keyboard_inset_sync inset=%{public}d focused=%{public}s',
        nextInsetVp, String(this.resolveRootBottomPanelAddressFocused()));
    }
    this.rootKeyboardInsetVp = nextInsetVp;
    if (nextInsetVp <= 0) {
      this.rootAddressKeyboardOverlayInsetVp = 0;
      return;
    }
    this.syncRootAddressKeyboardOverlayInset();
  }

  private handleRootAddressKeyboardHidden(): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'root_address_keyboard_hidden_end_input');
    this.endRootAddressInputSession(true);
  }

  private scheduleRootAddressKeyboardOverlayInsetSync(): void {
    this.browserWindowAvoidAreaCoordinator.scheduleKeyboardInsetSync(this.browserRootAddressKeyboardInsetSyncHost);
  }

  private cancelRootAddressKeyboardOverlayInsetSync(): void {
    this.browserWindowAvoidAreaCoordinator.cancelKeyboardInsetSync();
  }

  private buildHomeResponsiveLayoutState(): HomeResponsiveLayoutState {
    return this.browserTabHomeCoordinator.buildResponsiveLayoutState({
      shellFamily: this.browserShellPresentationOperations?.snapshot()?.shellFamily ?? 'phone',
      viewportWidth: this.rootBottomPanelLayoutState.viewport.width,
      viewportHeight: this.rootBottomPanelLayoutState.viewport.height,
      topSafeInsetVp: this.homeTopSafeInsetVp,
      bottomSafeInsetVp: this.homeBottomSafeInsetVp,
      leftSafeInsetVp: this.homeLeftSafeInsetVp,
      rightSafeInsetVp: this.homeRightSafeInsetVp
    }, this.homeShortcutLayoutDensity);
  }

  private applyTabsOverviewThemeState(state: BrowserTabsOverviewThemeState): void {
    this.tabsSheetBackgroundColor = state.backgroundColor;
    this.tabsSheetSurfaceBackground = state.surfaceBackground;
    this.tabsSheetControlBackground = state.controlBackground;
    this.tabsSheetPressedBackground = state.pressedBackground;
    this.tabsSheetOutlineColor = state.outlineColor;
    this.tabsSheetTextPrimaryColor = state.textPrimaryColor;
    this.tabsSheetTextSecondaryColor = state.textSecondaryColor;
    this.tabsSheetAccentColor = state.accentColor;
    this.tabsSheetBlurPrivateTabPreviews = state.blurPrivateTabPreviews;
  }

  private isWebVideoTakeoverExperimentEnabled(): boolean {
    return this.webScrollExperimentSettings.webVideoTakeoverEnabled;
  }

  private parseAreaDimension(value: Length): number {
    const rawValue = `${value}`.replace('vp', '').replace('px', '');
    const parsedValue = Number(rawValue);
    return Number.isFinite(parsedValue) ? parsedValue : 0;
  }

  private parseAreaPosition(value?: Length): number {
    if (value === undefined) {
      return 0;
    }
    return this.parseAreaDimension(value);
  }

  private resetHomeTransientUiState(): void {
    this.browserSearchSuggestionCoordinator.reset();
    this.contextMenuHomeShortcutId = '';
    this.endRootAddressInputSession();
    this.browserRootBottomPanelSessionCoordinator.clearTransientMessage();
  }

  private endRootAddressInputSession(keyboardHiddenConfirmed: boolean = false): void {
    const plan = this.browserRootBottomPanelSessionCoordinator.buildAddressSessionEndPlan(
      this.buildRootAddressInputSessionSnapshot(keyboardHiddenConfirmed)
    );
    this.applyRootBottomPanelSessionChromePlan(plan);
  }

  private buildRootAddressInputSessionSnapshot(
    keyboardHiddenConfirmed: boolean = false
  ): BrowserRootAddressInputSessionSnapshot {
    return {
      isHomeMode: this.isRootBottomPanelEffectiveHomeMode(),
      homeSearchFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
      homeSearchOverlayVisible: this.browserSearchSuggestionSnapshot.homeSearchOverlayVisible,
      homeAddressInput: this.addressInput,
      searchSuggestionsVisible: this.browserSearchSuggestionCoordinator.hasVisibleSuggestions(),
      webBottomAddressFocused: this.webBottomAddressFocused,
      webBottomAddressDraft: this.webBottomAddressDraft,
      keyboardOverlayInsetVp: this.rootAddressKeyboardOverlayInsetVp,
      keyboardHiddenConfirmed: keyboardHiddenConfirmed,
      keyboardHideProtectionUntilMs: this.rootAddressKeyboardHideProtectionUntilMs,
      nowMs: Date.now()
    };
  }

  private buildRootBottomPanelSessionSnapshot(): BrowserRootBottomPanelSessionSnapshot {
    const semanticState = this.buildRootBottomPanelSemanticState();
    return {
      isHomeMode: semanticState.effectiveHome,
      isWebMode: semanticState.effectiveWeb,
      showHomePage: semanticState.effectiveHome,
      homeSearchFocused: this.browserSearchSuggestionSnapshot.homeSearchFocused,
      homeSearchOverlayVisible: this.browserSearchSuggestionSnapshot.homeSearchOverlayVisible,
      currentDetent: this.resolveRootBottomPanelDetent(),
      panelExpansionEnabled: this.isRootBottomPanelExpansionEnabled()
    };
  }

  private applyRootBottomPanelSessionChromePlan(plan: BrowserRootBottomPanelChromePlan): void {
    if (plan.shouldReleaseHomeSearchBeforeBackdropEffects) {
      this.browserShellSearchInvocationAdapter.releaseHomeSearchFocus();
      this.addressInput = '';
    }
    if (plan.shouldCollapseSearchBackdropProgress) {
      this.browserRootBottomPanelSessionCoordinator.settleSearchBackdropToProgress(0);
    }
    if (plan.shouldCancelBackdropFocusTransition) {
      this.cancelRootBottomPanelAddressFocusBackdropTransition();
    }
    if (plan.shouldResetSearchOverlay) {
      this.browserSearchSuggestionCoordinator.reset();
    }
    if (plan.shouldReleaseHomeSearchFocus) {
      this.browserShellSearchInvocationAdapter.releaseHomeSearchFocus();
    }
    if (plan.shouldClearHomeSearchFocus) {
      this.browserSearchSuggestionCoordinator.setHomeSearchFocused(false);
    }
    if (plan.shouldClearHomeAddressInput) {
      this.addressInput = '';
    }
    if (plan.shouldRestoreScrollPresentation) {
      this.browserRootBottomPanelSessionCoordinator.restoreScrollPresentation();
    }
    if (plan.shouldClearWebAddressFocus) {
      this.setWebBottomAddressFocused(false);
    }
    if (plan.shouldFocusWebAddressInput) {
      this.setWebBottomAddressFocused(true);
    }
    if (plan.shouldClearWebAddressDraft) {
      this.webBottomAddressDraft = '';
    }
    if (plan.shouldFocusHomeSearchInput) {
      this.browserSearchSuggestionCoordinator.setHomeSearchFocused(true);
    }
    if (plan.shouldEnsureHomeAddressFocusBackdrop) {
      this.ensureRootBottomPanelAddressFocusBackdropTransition('home');
    }
    if (plan.shouldEnsureWebAddressFocusBackdrop) {
      this.ensureRootBottomPanelAddressFocusBackdropTransition('web');
    }
    this.applyRootBottomPanelSessionDetentPlan(plan);
    if (plan.shouldSyncBottomPanelStatusBarStyle) {
      this.syncBottomPanelStatusBarStyle();
    }
    if (plan.shouldRequestKeyboardInsetSync) {
      this.requestRootBottomAddressInputKeyboardAvoidMode();
    }
    if (plan.webStatusBarRestoreReason.length > 0) {
      this.browserWebTopImmersionSessionCoordinator.requestVisible(plan.webStatusBarRestoreReason);
    }
    if (plan.shouldReleaseKeyboardAvoidMode) {
      this.releaseRootBottomAddressInputKeyboardAvoidMode();
    }
    if (plan.shouldHideTextInput) {
      inputMethod.getController().hideTextInput()
        .catch((_error: Error) => {
        });
    }
    if (plan.shouldEndSearchInvocationForAction) {
      BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'other_surface_selected');
    }
  }

  private applyRootBottomPanelSessionDetentPlan(plan: BrowserRootBottomPanelChromePlan): void {
    const execution = this.browserRootBottomPanelSessionCoordinator.prepareDetentExecution(plan);
    this.browserRootBottomPanelSessionCoordinator.invalidatePresentation();
    if (execution.targetDetent === undefined || execution.detentApplication === 'none') {
      return;
    }
    if (execution.detentApplication === 'assign') {
      this.rootBottomAddressPanelDetent = execution.targetDetent;
    } else {
      this.applyRootBottomPanelDetent(execution.targetDetent);
    }
    if (execution.immediateLowDetent && execution.targetDetent === 'low') {
      this.rootBottomPanelImmediateLowDetentRequestVersion += 1;
    }
  }

  private protectRootAddressKeyboardSessionFromTransientHide(): void {
    this.rootAddressKeyboardHideProtectionUntilMs =
      this.browserRootBottomPanelSessionCoordinator.buildKeyboardHideProtectionUntil(Date.now());
  }

  private buildCustomHomepageRuntimeFacts(): CustomHomepageRuntimeShellFacts {
    const themeMode = this.browserThemeModeCoordinator.resolveCurrentMode();
    const privacyMode = this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode;
    const dataScope = this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope;
    return {
      uiContext: this.getUIContext(),
      shellVisible: this.isBrowserShellVisible,
      showHomePage: this.showHomePage,
      runtimeAllowed: !this.tabScopedEventContextCoordinator.isBoundaryPrivate(privacyMode, dataScope),
      theme: {
        mode: themeMode,
        effectiveMode: this.browserThemeModeCoordinator.resolveEffectiveMode(themeMode)
      },
      privacy: {
        privacyMode: privacyMode,
        isPrivate: this.tabScopedEventContextCoordinator.isBoundaryPrivate(privacyMode, dataScope)
      },
      dataScope: dataScope,
      createOptions: this.tabScopedEventContextCoordinator.resolveCurrentBoundary(),
      homeBackgroundColor: this.themedHomeBackground,
      forceEnableWebZoom: this.webScrollExperimentSettings.forceEnableWebZoom,
      shortcuts: this.homeShortcutApplicationSnapshot.shortcuts,
      shortcutIcons: this.homeShortcutApplicationSnapshot.icons
    };
  }

  private applyCustomHomepageRuntimeState(state: CustomHomepageRuntimeShellState): void {
    const previousPresentationRevision = this.customHomepageRuntimeState.presentationRevision;
    const previousHomeChromePolicy = this.browserTabHomeCoordinator.buildHomeSystemChromePolicyState();
    this.customHomepageRuntimeState = state;
    this.customHomepageHostedWebNode = this.customHomepageRuntimeCoordinator.getHostedWebNodeController();
    if (previousPresentationRevision !== state.presentationRevision) {
      this.browserTabHomeCoordinator.applyHomeSystemChromePolicyTransition(
        previousHomeChromePolicy,
        this.browserTabHomeCoordinator.buildHomeSystemChromePolicyState()
      );
      this.browserTabHomeCoordinator.refreshBackdropAppearance('custom_homepage');
    }
    if (state.activityState === 'active') {
      this.setCustomHomepageKeyboardOverlayMode();
      return;
    }
    this.restoreCustomHomepageKeyboardAvoidMode();
  }

  private executeCustomHomepageShellEffect(effect: CustomHomepageRuntimeShellEffect): void {
    switch (effect.type) {
      case 'apply_search_engine_snapshot':
        this.browserTabHomeCoordinator.applySearchEngineSelectionSnapshot(effect.snapshot);
        return;
      case 'open_search':
        this.browserShellSearchInvocationAdapter.openThirdPartyHomepageSearch(
          this.getWindowScopeId(),
          new BrowserSearchInvocationAuthorityGateAdapter((): boolean => {
            return this.customHomepageRuntimeCoordinator.authorizeActiveDocumentEvent(
              effect.documentGeneration,
              'openSearch'
            );
          })
        );
        return;
      case 'open_toolbar':
        this.browserRootBottomPanelSessionCoordinator.requestProgrammaticToolbarExpansion(
          this.buildRootBottomPanelSessionSnapshot()
        );
        return;
      case 'open_novel_bookshelf':
        this.browserShellRouteCoordinator.openNovelBookshelfPage();
        return;
      case 'toggle_private_mode':
        this.browserRootBottomPanelShellActionExecutor.apply('toggle_private_mode');
        return;
      case 'scan_qr':
        void this.scanQrCodeFromBottomPanel();
        return;
      case 'show_message':
        this.showNativeToast(effect.message);
        return;
      case 'handle_scroll':
        this.handleCustomHomepageScroll(effect.event);
        return;
    }
  }

  private setCustomHomepageKeyboardOverlayMode(): void {
    this.browserKeyboardAvoidModeCoordinator.requestMode(
      this.getUIContext(),
      BROWSER_KEYBOARD_AVOID_OWNER_CUSTOM_HOMEPAGE,
      KeyboardAvoidMode.NONE,
      BROWSER_KEYBOARD_AVOID_PRIORITY_CUSTOM_HOMEPAGE
    );
  }

  private restoreCustomHomepageKeyboardAvoidMode(): void {
    this.browserKeyboardAvoidModeCoordinator.releaseOwner(
      this.getUIContext(),
      BROWSER_KEYBOARD_AVOID_OWNER_CUSTOM_HOMEPAGE
    );
  }

  private requestRootBottomAddressInputKeyboardAvoidMode(): void {
    this.browserKeyboardAvoidModeCoordinator.requestMode(
      this.getUIContext(),
      BROWSER_KEYBOARD_AVOID_OWNER_ROOT_BOTTOM_ADDRESS_INPUT,
      KeyboardAvoidMode.NONE,
      BROWSER_KEYBOARD_AVOID_PRIORITY_ROOT_BOTTOM_ADDRESS_INPUT
    );
    this.syncRootAddressKeyboardOverlayInset();
    this.scheduleRootAddressKeyboardOverlayInsetSync();
  }

  private releaseRootBottomAddressInputKeyboardAvoidMode(): void {
    this.cancelRootAddressKeyboardOverlayInsetSync();
    this.browserKeyboardAvoidModeCoordinator.releaseOwner(
      this.getUIContext(),
      BROWSER_KEYBOARD_AVOID_OWNER_ROOT_BOTTOM_ADDRESS_INPUT
    );
    this.rootKeyboardInsetVp = 0;
    this.rootAddressKeyboardOverlayInsetVp = 0;
  }

  private releaseAllBrowserKeyboardAvoidModes(): void {
    this.browserKeyboardAvoidModeCoordinator.releaseAll(this.getUIContext());
  }

  private getTabPreviewStates() {
    // Pure read: the overlay build calls this, so it must not write shared state.
    // The thumbnail store is refreshed from notifyTabPreviewChanged instead.
    return this.tabsOverviewPreviewStates;
  }

  private refreshTabPreviewStates(capturedAt: number = Date.now()): void {
    this.tabsOverviewPreviewStates = this.tabsOverviewSnapshotPipelineCoordinator.buildGalleryPreviewStates(
      this.tabsOverviewSnapshotPipelineState,
      this.browserTabPreviewCoordinator.listPreviewStates(this.tabs),
      this.tabs,
      capturedAt
    );
  }

  private notifyTabPreviewChanged(): void {
    // Publish the freshest previews into the thumbnail store here, on the change
    // event, instead of from getTabPreviewStates(). That getter is read during the
    // overlay build, and the store write bumps a version the renderer observes, so
    // doing it there spun a render -> write -> render loop (the tabs overview froze
    // the app whenever it stayed mounted).
    const capturedAt = Date.now();
    this.tabsOverviewSnapshotPipelineCoordinator.publishPreviewStatesToThumbnailStore(
      this.tabsOverviewSnapshotPipelineState,
      this.browserTabPreviewCoordinator.listPreviewStates(this.tabs),
      capturedAt
    );
    this.refreshTabPreviewStates(capturedAt);
    this.tabPreviewRenderVersion += 1;
  }

  private persistMeasuredWebLayerGeometry(): void {
    if (!this.hostedWebLayerMeasured || this.rootViewportWidth <= 1 || this.rootViewportHeight <= 1 ||
      this.hostedWebLayerWidth <= 1 || this.hostedWebLayerHeight <= 1) {
      return;
    }
    const snapshot = this.browserWebLayerGeometryCache.buildSnapshot({
      rootWidth: this.rootViewportWidth,
      rootHeight: this.rootViewportHeight,
      webLeft: this.hostedWebLayerLeft,
      webTop: this.hostedWebLayerTop,
      webWidth: this.hostedWebLayerWidth,
      webHeight: this.hostedWebLayerHeight,
      layoutTop: this.getWebViewportLayoutTopInsetPx(),
      visualTop: this.getWebViewportTopInsetPx(),
      capturedAt: Date.now()
    });
    this.restoredWebLayerGeometry = snapshot;
    void this.browserWebLayerGeometryStore.writeSnapshot(snapshot);
  }

  private resolveReusableWebLayerGeometry(): BrowserWebLayerGeometrySnapshot | undefined {
    if (this.hostedWebLayerMeasured || this.showHomePage) {
      return undefined;
    }
    return this.browserWebLayerGeometryCache.resolveReusableSnapshot(this.restoredWebLayerGeometry, {
      rootWidth: this.rootViewportWidth,
      rootHeight: this.rootViewportHeight,
      layoutTop: this.getWebViewportLayoutTopInsetPx(),
      visualTop: this.getWebViewportTopInsetPx()
    });
  }

  private resolveEffectiveWebLayerRect(): BrowserWebLayerRect {
    return this.browserWebLayerGeometryCache.resolveEffectiveRect({
      measured: this.hostedWebLayerMeasured,
      showHome: this.showHomePage,
      webLeft: this.hostedWebLayerLeft,
      webTop: this.hostedWebLayerTop,
      webWidth: this.hostedWebLayerWidth,
      webHeight: this.hostedWebLayerHeight,
      rootWidth: this.rootViewportWidth,
      rootHeight: this.rootViewportHeight,
      layoutTop: this.getWebViewportLayoutTopInsetPx(),
      visualTop: this.getWebViewportTopInsetPx(),
      restored: this.restoredWebLayerGeometry
    });
  }

  private getWebErrorSurfaceBottomInsetVp(): number {
    return this.resolveErrorDocumentBottomInsetVp(this.activeTabId);
  }

  private resolveErrorDocumentBottomInsetVp(tabId: string): number {
    const safeInsets = this.browserWindowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage());
    const tab = this.tabManager.getTab(this.tabs, tabId);
    const webPageVisible = tab !== undefined && !tab.isHome;
    if (this.isWebAppImmersiveMode() && webPageVisible) {
      return 0;
    }
    return this.browserChromeRuntimeCoordinator.buildStableWebViewportBottomInsetPx(
      safeInsets.bottomInsetVp,
      this.browserSearchSuggestionSnapshot.homeSearchOverlayVisible,
      webPageVisible
    );
  }

  private buildTabPreviewCaptureRequest(tabId: string, force: boolean = false): BrowserTabPreviewCaptureRequest | undefined {
    return this.buildTabPreviewCaptureRequestWithOptions(tabId, force, false);
  }

  private buildTabPreviewCaptureRequestWithOptions(
    tabId: string,
    force: boolean = false,
    requireSharedSnapshot: boolean = false,
    options?: BrowserTabPreviewActionRequestOptions
  ): BrowserTabPreviewCaptureRequest | undefined {
    const input: BrowserTabPreviewCaptureShellInput = {
      tab: this.tabManager.getTab(this.tabs, tabId),
      tabId: tabId,
      uiContext: this.getUIContext(),
      activeTabId: this.activeTabId,
      showTabsSheet: this.showTabsSheet,
      showHomePage: this.showHomePage,
      suspendHostedWebSurface: this.shouldSuspendHostedWebSurface(),
      activeControllerAttached: this.controllerAttached,
      activeErrorSurfaceVisible: this.shouldRenderWebPageErrorSurface(),
      requireSharedSnapshot: requireSharedSnapshot,
      force: force,
      componentSnapshotOnly: options?.componentSnapshotOnly,
      captureVisibleTabSurface: options?.captureVisibleTabSurface
    };
    return this.browserTabPreviewCoordinator.buildCaptureRequestFromShellState(input);
  }

  private scheduleCurrentTabPreviewAfterErrorPageCommit(delayMs: number, force: boolean): void {
    this.browserTabPreviewCoordinator.scheduleActiveCapture(delayMs, () => this.buildTabPreviewCaptureRequest(this.activeTabId, force),
      () => this.notifyTabPreviewChanged());
  }

  private buildTabPreviewActionPort(): BrowserTabPreviewActionPort {
    return {
      buildRequest: (
        tabId: string,
        force: boolean,
        requireSharedSnapshot: boolean,
        options?: BrowserTabPreviewActionRequestOptions
      ): BrowserTabPreviewCaptureRequest | undefined =>
        this.buildTabPreviewCaptureRequestWithOptions(tabId, force, requireSharedSnapshot, options),
      previewCoordinator: this.browserTabPreviewCoordinator,
      notifyChanged: (): void => {
        this.notifyTabPreviewChanged();
      },
      recordRuntimeEvent: (event: string, details: string, tabId?: string): void => {
        this.recordRuntimeEvent(event, details, tabId);
      }
    };
  }

  private async captureTabPreviewForExplicitAction(
    tabId: string,
    force: boolean,
    requireSharedSnapshot: boolean,
    notifyOnChanged: boolean = true
  ): Promise<boolean> {
    return await this.browserTabPreviewActionCoordinator.captureExplicit(
      this.buildTabPreviewActionPort(),
      {
        tabId: tabId,
        force: force,
        requireSharedSnapshot: requireSharedSnapshot,
        notifyOnChanged: notifyOnChanged
      }
    );
  }

  private async captureFreshActiveTabPreviewForOverview(
    tab: BrowserTabState,
    generation: number
  ): Promise<boolean> {
    const input: BrowserTabsOverviewSnapshotPipelineEntryCaptureInput = {
      tab: tab,
      generation: generation,
      uiContext: this.getUIContext(),
      componentSnapshotId: buildBrowserTabPreviewVisibleSurfaceSnapshotId(tab.id),
      componentSnapshotScale: TABS_OVERVIEW_ENTRY_PIXELMAP_SCALE,
      fallbackWidth: this.rootViewportWidth * TABS_OVERVIEW_ENTRY_PIXELMAP_SCALE,
      fallbackHeight: this.rootViewportHeight * TABS_OVERVIEW_ENTRY_PIXELMAP_SCALE,
      transitionSource: this.tabsOverviewSnapshotPipelineCoordinator.buildEntryVisibleTabSurfaceTransitionSource(
        this.rootViewportWidth,
        this.rootViewportHeight
      ),
      shouldKeepPixelMap: (): boolean => {
        return this.activeTabId === tab.id && !this.showHomePage && !this.showTabsSheet;
      }
    };
    return await this.tabsOverviewSnapshotPipelineCoordinator.captureEntryPixelMapBeforeOpen(input);
  }

  private captureCurrentTabPreviewForLifecycleExit(source: string): void {
    this.browserTabPreviewActionCoordinator.captureLifecycleExit(
      this.buildTabPreviewActionPort(),
      {
        activeTabId: this.activeTabId,
        showHomePage: this.showHomePage,
        source: source
      }
    );
  }

  private requestOpenTabsOverviewFromRootBottomPanel(
    activeSection: BrowserTabsOverviewSessionSection = 'tabs'
  ): void {
    const section: BrowserTabsOverviewSessionSection = activeSection === 'privacy' ? 'privacy' : 'tabs';
    this.dispatchTabsOverviewSession({ type: 'request_open_from_root_bottom_panel', section: section });
  }

  private cancelDeferredTabsOverviewOpen(): void {
    this.dispatchTabsOverviewSession({ type: 'cancel_deferred_open' });
  }

  private dispatchTabsOverviewSession(action: BrowserTabsOverviewSessionAction): void {
    this.tabsOverviewSessionCoordinator.handle(action);
  }

  private async openTabsOverview(activeSection: BrowserTabsOverviewSessionSection = 'tabs'): Promise<void> {
    this.dumpTabPreviewDiagnostics('overview-open');
    this.dispatchTabsOverviewSession({ type: 'request_open', section: activeSection });
  }

  // Leave-capture for the outgoing foreground web tab. On the large-screen
  // shell it grabs the full visible surface (page + omnibox/tab strip) so the
  // overview thumbnail matches the open-overview capture; the phone shell
  // keeps its original bare-page capture untouched.
  private lastOutgoingPreviewCaptureTabId: string = '';

  private async captureOutgoingTabVisibleSurfacePreview(): Promise<boolean> {
    if (this.showHomePage || this.activeTabId.trim().length <= 0) {
      return false;
    }
    this.lastOutgoingPreviewCaptureTabId = this.activeTabId;
    if (await this.probeAndAdoptVisibleSurfaceSnapshot(this.activeTabId)) {
      return true;
    }
    return await this.browserTabPreviewActionCoordinator.captureExplicit(
      this.buildTabPreviewActionPort(),
      {
        tabId: this.activeTabId,
        force: true,
        requireSharedSnapshot: true,
        captureVisibleTabSurface: this.isLargeScreenShellFamilyActive()
      }
    );
  }

  // Called when the "+" flow's leave-capture time-box expires: the shell is
  // about to swap to home, so a still-running snapshot must not be allowed to
  // store whatever surface it ends up seeing (it could capture the HOME page
  // and attribute it to the outgoing web tab).
  private cancelOutgoingTabPreviewCapture(): void {
    const tabId = this.lastOutgoingPreviewCaptureTabId.trim();
    if (tabId.length > 0) {
      this.browserTabPreviewCoordinator.invalidateActiveCaptureRun(tabId);
    }
  }

  // Temporary THUMB-DIAG instrumentation: dump what each tab's card would show
  // right before the overview opens (remove after the thumbnail bug is closed).
  private dumpTabPreviewDiagnostics(reason: string): void {
    try {
      hilog.info(0x0000, 'ThumbDiag',
        '[THUMB-DIAG] dump reason=%{public}s active=%{public}s home=%{public}s viewport=%{public}s webLayer=%{public}s',
        reason,
        this.activeTabId,
        `${this.showHomePage}`,
        `${this.rootViewportWidth}x${this.rootViewportHeight}`,
        `${this.hostedWebLayerMeasured}:${this.hostedWebLayerWidth}x${this.hostedWebLayerHeight}`);
      this.tabs.forEach((tab: BrowserTabState): void => {
        const preview = this.browserTabPreviewCoordinator.getSharedSnapshotState(tab.id);
        hilog.info(0x0000, 'ThumbDiag',
          '[THUMB-DIAG] tab=%{public}s isHome=%{public}s url=%{public}s preview=%{public}s src=%{public}s age=%{public}s',
          tab.id,
          `${tab.isHome}`,
          tab.url.slice(0, 48),
          preview === undefined
            ? 'none'
            : `uri:${(preview.sharedSnapshotImageUri?.trim().length ?? 0) > 0} pm:${preview.sharedSnapshotPixelMap !== undefined} ${preview.sharedSnapshotImageWidth}x${preview.sharedSnapshotImageHeight}`,
          `${preview?.captureSource ?? preview?.transitionSource?.captureSource ?? ''}`,
          preview === undefined ? '-' : `${Math.round((Date.now() - preview.capturedAt) / 1000)}s`);
      });
    } catch (_error) {
      // diagnostics must never break the overview flow
    }
  }

  private handleTabPreviewLifecycleCaptureRevisionChange(): void {
    if (this.tabPreviewLifecycleCaptureRevision <= 0) {
      return;
    }
    this.captureCurrentTabPreviewForLifecycleExit('ability-background');
  }

  private handleSystemMemoryPressureRevisionChange(): void {
    this.browserTabBackgroundSessionSyncCoordinator
      .handleSystemMemoryPressureRevision(this.systemMemoryPressureRevision);
  }

  private resolveTabsSheetActiveSection(): BrowserTabsOverviewSessionSection {
    return this.tabsOverviewPresentationState.activeSection;
  }

  private exportTabsOverviewDebugSnapshot(tabId: string): void {
    if (!TABS_OVERVIEW_DEBUG_SNAPSHOT_EXPORT_ENABLED) {
      return;
    }
    const candidate = this.browserTabPreviewCoordinator.getDebugSnapshotExportCandidate(tabId);
    if (candidate === undefined) {
      this.showNativeToast('标签页动画快照还没有生成。');
      return;
    }
    void this.browserTabPreviewDebugExportService.exportSnapshot(this.getAbilityContext(), candidate)
      .then((result) => {
        this.showNativeToast(result.userMessage);
      })
      .catch((_error: Error) => {
        this.showNativeToast('标签页动画快照导出失败，请稍后重试。');
      });
  }

  private syncTabPreviewCacheWithTabs(): void {
    this.browserTabSwitchCoordinator.synchronizeWebTabsAndPreviewAssets();
  }

  private async restorePersistedTabPreviews(): Promise<void> {
    await this.browserTabPreviewAssetBoundaryCoordinator.hydratePersistedPreviewMetadata({
      previewCoordinator: this.browserTabPreviewCoordinator,
      tabs: this.tabs,
      suspendedWindowTabsByWindowId: this.browserWindowContextCoordinator.getSuspendedWindowTabsByWindowId(),
      currentWindowId: this.currentWindowId,
      options: {
        batchSize: TABS_OVERVIEW_PREVIEW_HYDRATE_BATCH_SIZE,
        batchDelayMs: TABS_OVERVIEW_PREVIEW_HYDRATE_BATCH_DELAY_MS
      },
      notifyChanged: (): void => {
        this.notifyTabPreviewChanged();
      }
    });
  }

  @Builder
  private buildReaderModeOverlay() {
    ReaderModeOverlay({
      state: this.readerModeSessionSnapshot.state,
      presentationMode: this.readerModeSessionSnapshot.reading.presentationMode,
      topSafeInsetVp: this.getReaderModeTopSafeInsetVp(),
      bottomSafeInsetVp: this.getReaderModeBottomSafeInsetVp(),
      globalImmersionEnabled: this.isTopImmersionPreferenceEnabled(),
      alwaysTopImmersionEnabled: this.isAlwaysTopImmersionEnabled(),
      statusBarVisible: this.webStatusBarVisible,
      dismissImagePreviewRequestVersion:
        this.readerModeSessionSnapshot.overlayBackState.dismissImagePreviewRequestVersion,
      dismissPanelRequestVersion:
        this.readerModeSessionSnapshot.overlayBackState.dismissPanelRequestVersion,
      onAction: (action: ReaderModeAction): void => this.readerModeApplication.handleAction(action)
    })
      .zIndex(140)
  }

  @Builder
  private buildNovelReaderSurface() {
    NovelReaderSurfaceHost({
      state: this.novelReaderSnapshot,
      webPageVisible: this.isWebPageVisible(),
      activeTabId: this.activeTabId,
      currentPageUrl: this.resolveCurrentWebPageActionUrl(),
      viewportWidth: this.rootViewportWidth,
      viewportHeight: this.rootViewportHeight,
      onAction: (action: NovelReaderAction): void => this.novelReaderSession.handleAction(action),
      onPageEntryTap: (): void => this.novelReaderSession.handleAction({ type: 'activate_page_entry' }),
      onReentryTap: (): void => {
        void this.browserRootBottomPanelActionApplication.openNovelModeFromCurrentPage();
      }
    })
  }

  private resolveWebpageTranslationOverlayTopOffsetVp(): number {
    return this.browserTopFloatingPromptCoordinator.resolveTranslationTopOffsetVp({
      showHomePage: this.showHomePage,
      topInsetVp: this.browserWindowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage()).topInsetVp,
      webTopChromeOverlayHeightVp: 0
    });
  }

  private getReaderModeTopSafeInsetVp(): number {
    return this.browserWindowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage()).topInsetVp;
  }

  private getReaderModeBottomSafeInsetVp(): number {
    return this.browserWindowAvoidAreaCoordinator.readStorage(this.getSharedStageStorage()).bottomInsetVp;
  }

  private isWebpageTranslationPanelSurfaceVisible(): boolean {
    return this.webpageTranslationCoordinator.isPanelSurfaceVisible(
      this.webpageTranslationApplicationSnapshot,
      this.buildWebpageTranslationApplicationContext()
    );
  }

  private buildWebpageTranslationApplicationContext(): WebpageTranslationApplicationContext {
    return {
      activeTabId: this.activeTabId,
      activeUrl: this.resolveWebPageActionTargetForTab(this.activeTabId).url,
      appServiceModeFull: this.isFullAppServiceMode(),
      privateMode: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
      tabsSheetVisible: this.showTabsSheet,
      promptSurfaceAvailable:
        this.browserRootBottomPanelSessionCoordinator.resolveWebpageTranslationPromptAvailability()
    };
  }

  private bindReaderModeSession(): void {
    this.articleReadingSession.setEffectApplication(this.readerModeApplication);
    this.articleReadingSession.connectSessionListener({
      onSnapshotChanged: (
        snapshot: ReaderModeSessionSnapshot,
        transition: ReaderModeSessionSnapshotTransition
      ): void => {
        this.applyReaderModeSessionSnapshot(snapshot, transition);
      }
    });
    this.novelReaderApplication.bindSession(
      this.novelReaderSession,
      (snapshot: NovelReaderSnapshot): void => {
        this.novelReaderSnapshot = snapshot;
      }
    );
  }

  private applyReaderModeSessionSnapshot(
    snapshot: ReaderModeSessionSnapshot,
    transition: ReaderModeSessionSnapshotTransition
  ): void {
    if (transition === 'theme') {
      animateTo({
        duration: READER_MODE_THEME_TRANSITION_DURATION_MS,
        curve: Curve.EaseInOut
      }, () => {
        this.readerModeSessionSnapshot = snapshot;
        this.readerSpeechVoiceDialogPresentation = snapshot.speech.voiceDialog;
      });
      return;
    }
    this.readerModeSessionSnapshot = snapshot;
    this.readerSpeechVoiceDialogPresentation = snapshot.speech.voiceDialog;
  }

  private openReaderSpeechVoiceDialog(): void {
    this.articleReadingSession.openSpeechVoicePicker(
      this.browserThemeModeCoordinator.resolveEffectiveMode('system')
    );
    this.readerSpeechVoiceDialogController.open();
  }

  @Builder
  private buildWebContextMenuOverlay() {
    WebContextMenuOverlay({
      state: this.webContextMenuPresentation.state,
      layout: this.webContextMenuPresentation.layout,
      onAction: (action) => {
        this.webContextMenuCoordinator.handleOverlayAction(
          action,
          this.buildWebContextMenuSessionFacts(this.webContextMenuPresentation.state.tabId)
        );
      }
    })
  }

  private confirmBookmarkRemoval(confirmation: BrowserBookmarkRemoveConfirmation): void {
    this.browserNativeAlertDialogPresenter.confirm({
      title: '取消书签',
      message: confirmation.source === 'reader_article' ?
        '这篇文章已经在书签里，要取消收藏吗？' : '这个网页已经在书签里，要取消收藏吗？',
      cancelLabel: '保留',
      confirmLabel: '取消书签',
      confirmTone: 'warning',
      onConfirm: () => {
        void this.browserBookmarkActionCoordinator.removeConfirmed(confirmation);
      }
    });
  }

  private showWebContextMenu(
    tabId: string,
    event: OnContextMenuShowEvent,
    controller: webview.WebviewController
  ): boolean {
    return this.webContextMenuCoordinator.show(
      tabId,
      event,
      controller,
      this.buildWebContextMenuSessionFacts(tabId)
    );
  }

  private dismissWebContextMenu(): void {
    this.webContextMenuCoordinator.dismiss();
  }

  private buildWebContextMenuSessionFacts(tabId: string): WebContextMenuSessionFacts {
    const tab = this.tabManager.getTab(this.tabs, tabId);
    return {
      activeTabId: this.activeTabId,
      showPageErrorSurface: this.showPageErrorSurface,
      tabTitle: tab?.title ?? '',
      currentTitle: this.currentTitle,
      pageUrl: this.tabScopedEventContextCoordinator.resolvePageUrl(tabId),
      privacyMode: this.tabScopedEventContextCoordinator.resolvePrivacyMode(tabId),
      dataScope: this.tabScopedEventContextCoordinator.resolveDataScope(tabId),
      viewport: {
        rootWidthVp: this.rootViewportWidth,
        rootHeightVp: this.rootViewportHeight,
        hostedWebLayerMeasured: this.hostedWebLayerMeasured,
        hostedWebLayerLeftVp: this.hostedWebLayerLeft,
        hostedWebLayerTopVp: this.hostedWebLayerTop,
        hostedWebLayerWidthVp: this.hostedWebLayerWidth,
        hostedWebLayerHeightVp: this.hostedWebLayerHeight,
        reusableGeometry: this.resolveReusableWebLayerGeometry(),
        webViewportTopInsetVp: this.getWebViewportTopInsetPx()
      }
    };
  }

  private async saveWebLinkFromContextMenuOffline(tabId: string, url: string, title: string): Promise<void> {
    if (!await this.offlinePageSaveCoordinator.ensureLinkSaveAccess(
      this.tabScopedEventContextCoordinator.resolveDataScope(tabId),
      this.tabScopedEventContextCoordinator.resolvePrivacyMode(tabId)
    )) {
      return;
    }
    this.offlinePageSaveCoordinator.clearPendingLinkSave();
    const sourceTab = this.tabManager.getTab(this.tabs, tabId);
    await this.browserTabPreviewActionCoordinator.captureForegroundSeedSource(
      this.buildTabPreviewActionPort(),
      {
        sourceTabId: tabId,
        activeTabId: this.activeTabId,
        showHomePage: this.showHomePage,
        reason: 'web_context_menu_save_offline'
      }
    );
    await this.browserForegroundTabCreationCoordinator.createNewTab({
      initialUrl: url,
      initialTitle: title,
      options: this.tabScopedEventContextCoordinator.buildCreateOptions(tabId),
      runtimeOptions: { skipCurrentTabPreviewForForegroundOpen: true }
    });
    const targetTabId = this.activeTabId;
    await this.browserTabPreviewActionCoordinator.seedFromTab(
      this.buildTabPreviewActionPort(),
      {
        sourceTab: sourceTab,
        targetTab: this.tabManager.getTab(this.tabs, targetTabId),
        source: 'web-page-container',
        reason: 'web_context_menu_save_offline'
      }
    );
    this.offlinePageSaveCoordinator.markPendingLinkSave(targetTabId, url);
    this.showNativeToast('页面加载完成后将保存离线。');
  }

  @Builder
  private buildSystemSheet() {
    if (this.browserTransientSurfaceSnapshot.systemSheet.type === 'webPageTools') {
      BrowserWebPageToolsContent({
        sheetType: this.browserWebPageToolsSnapshot.type,
        layoutMode: 'phone',
        fullscreenPresentation: this.browserFullscreenSessionPresentation,
        userAgentPresentation: this.browserUserAgentActionPresentation,
        siteControlsSnapshot: this.siteControlsApplicationSnapshot,
        onAction: (action): void => {
          this.browserWebPageToolsCoordinator.handleOverlayAction(action);
        }
      })
        .width('100%')
        .height('100%')
    } else if (isBrowserToolbarSystemSheetType(this.browserTransientSurfaceSnapshot.systemSheet.type)) {
      BrowserToolbarSystemSheetContent({
        type: this.browserTransientSurfaceSnapshot.systemSheet.type,
        userScriptState: this.browserUserScriptApplicationSnapshot.pageActionsState,
        appProxyState: this.appProxyQuickSheetState,
        mediaResourceState: this.mediaResourceSessionSnapshot,
        onUserScriptAction: (action) => {
          this.browserUserScriptApplicationCoordinator.handleAction(action);
        },
        onAppProxyAction: (action) => {
          this.appProxyQuickSheetCoordinator.handleAction(action);
        },
        onMediaResourceAction: (action) => {
          this.browserMediaResourceSessionCoordinator.handleResourcesOverlayAction(action);
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.browserTransientSurfaceSnapshot.systemSheet.type === 'userScriptInstall') {
      UserScriptInstallSheetContent({
        initialSourceUrl: this.browserUserScriptApplicationSnapshot.installUrl,
        dataScope: this.browserUserScriptApplicationSnapshot.installBoundary.dataScope,
        privacyMode: this.browserUserScriptApplicationSnapshot.installBoundary.privacyMode,
        onRequestClose: (): void => this.browserUserScriptApplicationCoordinator.closeInstallSheet(),
        onInstalled: (result: UserScriptPackageSuccessResult): void => this.browserUserScriptApplicationCoordinator.handleInstallCompleted(result)
      })
        .width('100%')
        .height('100%')
    } else if (this.browserTransientSurfaceSnapshot.systemSheet.type === 'homeShortcutSelection') {
      HomeShortcutSelectionSheet({
        state: this.homeShortcutSelectionState,
        onAction: (action) => this.homeShortcutStateCoordinator.handleSelectionAction(action),
        onClose: (): void => this.closeSystemSheet()
      })
    } else if (this.browserTransientSurfaceSnapshot.systemSheet.type === 'homeSettings') {
      HomePageSettingsSheet({
        privateModeVisible: this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate(),
        onWallpaperChanged: (): void => {
          this.browserTabHomeCoordinator.refreshWallpaperPresentation();
        }
      })
    } else if (this.browserTransientSurfaceSnapshot.systemSheet.type === 'desktopLoginConfirm') {
      this.buildDesktopLoginConfirmSheet()
    } else if (this.browserTransientSurfaceSnapshot.systemSheet.type === 'crossDeviceTabs') {
      BrowserCrossDeviceTabsSheet({
        onOpenRemoteTab: (url: string, title: string) => {
          this.closeSystemSheet();
          this.browserAppUrlOpenCoordinator.open({
            url: url,
            title: title,
            intent: 'new_tab',
            source: 'app_ui'
          });
        }
      })
        .width('100%')
        .height('100%')
    } else if (isReadingExperienceSystemSheetType(
      this.browserTransientSurfaceSnapshot.systemSheet.type
    )) {
      ReadingExperienceSystemSheet({
        type: this.browserTransientSurfaceSnapshot.systemSheet.type,
        readerState: this.readerModeSessionSnapshot.state,
        readerPresentationMode: this.readerModeSessionSnapshot.reading.presentationMode,
        novelState: this.novelReaderSnapshot,
        bottomSafeInsetVp: this.getReaderModeBottomSafeInsetVp(),
        onReaderAction: (action: ReaderModeAction): void => this.readerModeApplication.handleAction(action),
        onNovelAction: (action: NovelReaderAction): void => this.novelReaderSession.handleAction(action)
      })
    } else {
      this.buildReleaseNoticeSheet()
    }
  }

  @Builder
  private buildDesktopLoginConfirmSheet() {
    DesktopLoginConfirmSheetContent({
      displayName: this.browserQrScanSessionSnapshot.desktopLoginDisplayName,
      uid: this.browserQrScanSessionSnapshot.desktopLoginUid,
      avatarUri: this.browserQrScanSessionSnapshot.desktopLoginAvatarUri,
      confirming: this.browserQrScanSessionSnapshot.desktopLoginConfirming,
      onAction: (action) => {
        this.browserQrScanCoordinator.handleDesktopLoginConfirmAction(action);
      }
    })
  }

  private closeSystemSheet(): void {
    this.browserTransientSurfaceCoordinator.closeSystemSheet();
  }

  private handleSystemSheetDisappear(): void {
    const effect = this.browserTransientSurfaceCoordinator.handleSystemSheetDisappear(
      this.browserQrScanSessionSnapshot.desktopLoginConfirming
    );
    this.applyBrowserSystemSheetDisappearEffect(effect);
  }

  private applyBrowserSystemSheetDisappearEffect(effect: BrowserSystemSheetLifecycleEffect): void {
    if (effect === 'clear_release_notice') {
      this.releaseNoticePresentationCoordinator.handleSystemSheetDisappear();
      return;
    }
    if (effect === 'clear_desktop_login') {
      this.browserQrScanCoordinator.handleSurfaceDismissed('desktop_login_confirm');
      return;
    }
    if (effect === 'reset_home_shortcut_selection') {
      this.homeShortcutStateCoordinator.resetSelectionSession();
    }
  }

  private resolveCurrentWebPageActionTarget(): BrowserBottomPanelActionTarget {
    return this.resolveWebPageActionTargetForTab(this.activeTabId);
  }

  private resolveWebPageActionTargetForTab(tabId: string): BrowserBottomPanelActionTarget {
    const activeTab = this.tabManager.getTab(this.tabs, tabId);
    return this.browserRootBottomPanelSessionCoordinator.resolveActionTarget({
      currentUrl: tabId === this.activeTabId ? this.currentUrl : '',
      pendingWebUrl: tabId === this.activeTabId ? this.pendingWebUrl : '',
      addressInput: tabId === this.activeTabId ? this.addressInput : '',
      activeTab: activeTab
    });
  }

  private resolveCurrentWebPageActionUrl(): string {
    return this.resolveCurrentWebPageActionTarget().url;
  }

  private resolveCurrentWebPageActionHost(): string {
    return this.resolveCurrentWebPageActionTarget().host;
  }

  private canOpenPageFind(): boolean {
    const activeTab = this.tabManager.getTab(this.tabs, this.activeTabId);
    return this.browserPageFindCoordinator.canOpen({
      tab: activeTab,
      webPageVisible: !this.showHomePage
    });
  }

  private dispatchRootBottomPanelAction(source: BrowserRootBottomPanelActionSource, actionId: string): void {
    this.browserRootBottomPanelSessionCoordinator.handleActionTap(
      source,
      actionId,
      this.buildRootBottomPanelSessionSnapshot()
    );
  }

  private dispatchRootBottomPanelLongPress(slotId: BrowserToolbarSlotId): void {
    this.browserRootBottomPanelSessionCoordinator.handleToolbarLongPress(
      slotId,
      this.buildRootBottomPanelSessionSnapshot()
    );
  }

  private async openCurrentDocumentViewerInfoDialog(): Promise<void> {
    const viewerUrl = this.buildCurrentDocumentViewerChromeContext().url;
    if (viewerUrl.length <= 0) {
      this.showNativeToast('当前没有可查看的文件信息。');
      return;
    }
    try {
      const info = await this.documentViewerService.resolveFileInfo(viewerUrl);
      if (info === undefined) {
        this.showNativeToast('当前没有可查看的文件信息。');
        return;
      }
      this.showDocumentViewerFileInfoDialog(info);
    } catch (error) {
      this.browserNativeAlertDialogPresenter.inform({
        title: '文件信息',
        message: `读取文件信息失败：${this.stringifyError(error)}`,
        confirmLabel: '知道了'
      });
    }
  }

  private showDocumentViewerFileInfoDialog(info: DocumentViewerFileInfo): void {
    this.documentViewerFileInfoDialogInfo = info;
    this.documentViewerFileInfoDialogController.open();
  }

  private presentPrivateModeToggleConfirmation(state: BrowserPrivateModeConfirmationState): void {
    this.privateModeConfirmationState = state;
    this.privateModeClearDataSelected = false;
    this.privateModeConfirmationDialogController.open();
  }

  private syncDownloadBoundary(): void {
    this.downloadService.setActiveBoundary(
      this.tabScopedEventContextCoordinator.resolveCurrentBoundary().profileId,
      this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
      this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
      this.currentWindowId,
      this.currentUrl
    );
  }

  private getCurrentDownloadBoundary(): DownloadTaskBoundary {
    return {
      windowId: this.currentWindowId,
      profileId: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().profileId,
      privacyMode: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().privacyMode,
      dataScope: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().dataScope,
      sourcePageUrl: this.currentUrl
    };
  }

  private submitRootBottomAddressInput(rawInput: string): void {
    BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'submitted');
    const addressSessionSnapshot = this.buildRootAddressInputSessionSnapshot();
    if (addressSessionSnapshot.isHomeMode) {
      this.browserRootBottomPanelSessionCoordinator.beginHomeToWebBottomPanelTransition();
    }
    const plan = this.browserRootBottomPanelSessionCoordinator.buildAddressSubmitPlan(
      rawInput,
      addressSessionSnapshot
    );
    this.applyRootBottomPanelSessionChromePlan(plan.chromePlan);
    void this.openSubmittedAddress(plan.rawInput);
  }

  private async openSubmittedAddress(
    rawInput: string,
    searchEngineId: SearchEngineId = this.selectedSearchEngine,
    routingMode: SearchEngineRoutingMode = 'configured'
  ): Promise<void> {
    await this.addressSubmissionCoordinator.submitAddress(rawInput, searchEngineId, routingMode, 900);
  }

  private shouldShowWebLoadingProgress(): boolean {
    return this.browserWebPageLifecycleApplicationCoordinator
      .shouldShowLoadingProgressVisualState(this.loadingProgressState);
  }

  private buildWebLoadingProgressBarPresentationState(): BrowserWebLoadingProgressBarPresentationState {
    return this.browserWebLoadingProgressBarPresentationViewModel.buildState({
      loadingProgressState: this.loadingProgressState,
      showHomePage: this.showHomePage,
      showTabsSheet: this.showTabsSheet
    });
  }

  private handleDownloadStart(tabId: string, event: OnDownloadStartEvent): void {
    this.browserTabBackgroundSessionSyncCoordinator.markDownloadStarted(tabId);
    this.browserUserScriptApplicationCoordinator.handleInstallCandidate(event.url);
  }

  @Builder
  private buildReleaseNoticeSheet() {
    ReleaseNoticeSheet({
      state: this.releaseNoticeState,
      onAction: (action) => {
        this.releaseNoticePresentationCoordinator.handleAction(action);
      }
    })
  }

  private buildTransientPromptBlockingFacts(): BrowserTransientPromptBlockingFacts {
    return {
      tabsSheetVisible: this.showTabsSheet,
      readerModeVisible: this.readerModeSessionSnapshot.state.visible,
      releaseNoticeVisible: this.releaseNoticeState.visible,
      hlsTakeoverVisible: this.mediaResourceSessionSnapshot.hlsTakeoverMounted,
      topFloatingPromptVisible: this.buildTopFloatingPromptHostState().mounted,
      webContextMenuVisible: this.webContextMenuPresentation.state.visible,
      pendingJavaScriptPrompt:
        this.browserWebCapabilityPromptApplicationCoordinator.hasAnyPendingJavaScriptDialog(),
      pendingSitePermissionPrompt:
        this.browserWebCapabilityPromptApplicationCoordinator.hasPendingSitePermissionPrompt(),
      manualElementHideSelectionActive: this.manualElementHideSelectionPresentation.active,
      privateModeLockVisible: this.browserPrivateModeLockCoordinator.shouldShowOverlay(
        this.privateModeLockSessionSnapshot,
        this.tabScopedEventContextCoordinator.isCurrentBoundaryPrivate()
      ),
      downloadPromptVisible: this.pendingDownloadPrompt !== undefined
    };
  }

  private handleInterceptRequest(tabId: string, event: OnInterceptRequestEvent): WebResourceResponse | null {
    const response = this.browserSiteControlsRuntimeCoordinator.handleInterceptRequest(tabId, event.request);
    if (response === null) {
      const pageUrlForObserve = this.tabScopedEventContextCoordinator.resolvePageUrl(tabId);
      const pageTitleForObserve = this.tabManager.getTab(this.tabs, tabId)?.title ?? '';
      const privacyModeForObserve = this.tabScopedEventContextCoordinator.resolvePrivacyMode(tabId);
      this.browserMediaDiscoveryCoordinator.handleInterceptRequest({
        tabId: tabId,
        pageUrl: pageUrlForObserve,
        pageTitle: pageTitleForObserve,
        privacyMode: privacyModeForObserve,
        request: event.request,
        runtime: this.buildMediaDiscoveryRuntimeContext()
      }, this.browserMediaDiscoveryHost);
    }
    return response;
  }

  private buildMediaDiscoveryRuntimeContext(): BrowserMediaDiscoveryRuntimeContext {
    return this.browserMediaDiscoveryRuntimeContextFactory.build({
      fullAppServiceMode: this.isFullAppServiceMode(),
      cachedExperimentSettings: this.webScrollExperimentSettings,
      mediaResourcesPanelOpen: this.browserTransientSurfaceCoordinator.isMounted('resource_candidates')
    });
  }

  private shouldStrengthenAdBlockingForSmoothScroll(): boolean {
    const experiments = sharedPreferencesRepository.getPreferences().experiments;
    return experiments.strengthenAdBlockingForSmoothScroll;
  }

  private buildExternalNavigationPromptPageContext(committedUrl: string = ''): ExternalNavigationPromptPageContext {
    const currentPageUrl = committedUrl.trim().length > 0 ? committedUrl : this.tabScopedEventContextCoordinator.resolvePageUrl(this.activeTabId);
    return this.browserUnifiedLinkApplicationCoordinator.buildExternalNavigationPromptPageContext({
      activeTabId: this.activeTabId,
      currentPageUrl: currentPageUrl,
      webPageVisible: this.isWebPageVisible(),
      tabsOverviewVisible: this.showTabsSheet
    });
  }

  private reconcileExternalNavigationPromptForCurrentPage(committedUrl: string = ''): void {
    this.browserUnifiedLinkApplicationCoordinator.reconcileExternalNavigationPromptForPageContext(
      this.buildExternalNavigationPromptPageContext(committedUrl)
    );
  }

  private openSiteReportDialog(): void {
    this.siteReportReasonId = this.siteReportDialogViewModel.getDefaultReasonId();
    this.siteReportRemark = '';
    this.siteReportDialogController.open();
  }

  private confirmSiteReport(): void {
    this.showNativeToast('举报已发送');
  }

  private getAbilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async openSystemNetworkSettings(): Promise<void> {
    const result = await this.systemSettingsLaunchService.openNetworkSettings(this.getAbilityContext());
    this.helperMessage = result.message;
    this.showNativeToast(result.message);
  }

  private copyTextToClipboard(value: string, emptyMessage: string, successMessage: string): void {
    this.browserClipboardService.copyText({
      value: value,
      emptyMessage: emptyMessage,
      successMessage: successMessage
    }).then((result: BrowserClipboardCopyResult) => {
      this.helperMessage = result.message;
      this.showNativeToast(result.message);
    }).catch((error: Error) => {
      this.handleCopyError(error);
    });
  }

  private showNativeToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (error) {
      this.helperMessage = message;
    }
  }

  private showKeyboardShortcutMessage(message: string): void {
    if (message.length <= 0) {
      return;
    }
    this.helperMessage = message;
    this.showNativeToast(message);
  }

  private handleCopyError(error: Object): void {
    this.errorMessage = `复制失败：${JSON.stringify(error)}`;
    this.showNativeToast('复制失败，请稍后重试。');
  }

  private async scanQrCodeFromBottomPanel(): Promise<void> {
    await this.browserQrScanCoordinator.scan(getContext(this) as common.UIAbilityContext);
  }

  private resolveWebBottomAddressInput(): string {
    return this.webBottomAddressFocused ? this.webBottomAddressDraft : this.addressInput;
  }

  private resolveEditableWebBottomAddress(): string {
    return this.browserAddressDisplayCoordinator.resolveEditingText(
      this.activeTabId,
      this.currentUrl,
      this.addressInput
    );
  }

  private isFullAppServiceMode(): boolean {
    return sharedPreferencesRepository.getPreferences().appServiceMode !== 'basic';
  }

  private resolveCommittedAddressDisplayText(url: string): string {
    return this.browserAddressDisplayCoordinator.resolveCommittedDisplay(
      this.activeTabId,
      this.telegramWebCompatibilityService.resolveVisibleUrl(url)
    );
  }

  private handleSearchEngineSettingsRevisionChange(): void {
    this.browserTabHomeCoordinator.handleSearchEngineSettingsRevision();
    this.browserQuickSearchSwitchingCoordinator.refreshEligibility('search-engine-settings');
  }

  private handleQuickSearchSwitchingPreferencesRevisionChange(): void {
    this.browserQuickSearchSwitchingCoordinator.refreshEligibility('preference');
  }

  private buildWebRuntimeBootstrapConfig(): WebControllerBootstrapConfig {
    return this.browserWebLoadRuntimeCoordinator.buildControllerBootstrapConfig(
      this.downloadService.getDelegate()
    );
  }

  private handleSiteCustomizationRefreshRevisionChange(): void {
    const impact = this.siteCustomizationRefreshSignal.getLatestImpact();
    const plan = this.siteCustomizationRuntimeRefreshCoordinator.buildRefreshPlan({
      reason: impact.reason,
      pageUrl: this.resolveCurrentWebPageActionUrl(),
      webPageVisible: this.isWebPageVisible(),
      controllerAttached: this.controllerAttached,
      hasActiveController: this.browserRuntimeLifecyclePort.resolveActiveController() !== undefined,
      targetOrigin: impact.targetOrigin,
      targetProfileId: impact.profileId,
      currentProfileId: this.tabScopedEventContextCoordinator.resolveCurrentBoundary().profileId
    });
    this.applySiteCustomizationRuntimeRefreshPlan(plan);
  }

  private applySiteCustomizationRuntimeRefreshPlan(plan: SiteCustomizationRuntimeRefreshPlan): void {
    if (plan.shouldRefreshCurrentSitePermissions) {
      this.browserSiteControlsRuntimeCoordinator.refreshCurrentSitePermissions();
    }
    if (plan.shouldApplyUserAgent) {
      this.browserUserAgentActionCoordinator.synchronize();
    }
    if (plan.shouldReloadActivePage) {
      this.browserActiveTabRuntimeRestoreCoordinator.reloadActive(plan.reloadReason);
    }
  }

  private disableFullScreenMode(): void {
    void this.browserFullscreenSessionCoordinator.disableFullscreen(true);
  }

  private buildBrowserFullscreenSurfaceFacts(): BrowserFullscreenSurfaceFacts {
    return {
      context: this.getAbilityContext(),
      activeTabId: this.activeTabId,
      webPageVisible: this.isWebPageVisible(),
      homePageVisible: this.showHomePage,
      tabsSheetVisible: this.showTabsSheet,
      assistantVideoTakeoverActive: this.isAssistantVideoTakeoverActive()
    };
  }

  private applyBrowserFullscreenSessionEffect(effect: BrowserFullscreenSessionEffect): void {
    switch (effect.type) {
      case 'capture_restore_insets':
      this.browserWindowAvoidAreaCoordinator.captureFullscreenRestoreInsets(this.getSharedStageStorage());
        return;
      case 'fullscreen_chrome_entered':
        this.setWebBottomAddressFocused(false);
        this.webBottomAddressDraft = '';
        this.rootBottomAddressPanelDetent = 'peek';
        this.browserWebTopImmersionSessionCoordinator.requestFullscreenHidden();
        return;
      case 'fullscreen_chrome_exited':
        this.rootBottomAddressPanelDetent = 'low';
        this.browserWebTopImmersionSessionCoordinator.requestVisible(effect.source);
        if (effect.source === 'video-web-fullscreen-exit') {
          this.arkWebMediaTakeoverCoordinator.handleWebFullscreenExited(this.activeTabId);
        }
        if (effect.restoreInsets) {
          this.browserWindowAvoidAreaCoordinator.scheduleFullscreenInsetRestore(this.browserFullscreenInsetRestoreHost);
        }
        return;
      case 'toast':
        this.showNativeToast(effect.message);
        return;
    }
  }

  private openWebTextZoomSheet(): void {
    this.webTextZoomSheetState = this.webTextZoomViewModel.buildState(this.webTextZoomRatio);
    this.webTextZoomDialogController.open();
  }

  private applyWebTextZoomAction(action: BrowserWebTextZoomAction): void {
    const result = this.webTextZoomViewModel.buildActionResult(this.webTextZoomRatio, action);
    if (!result.changed) {
      this.webTextZoomSheetState = result.state;
      return;
    }
    this.webTextZoomRatio = result.state.ratio;
    this.webTextZoomSheetState = result.state;
    this.webTextZoomActionVersion += 1;
    this.browserHostedRuntimeSurfacePort.updateCurrentActiveConfigFromHost();
  }

  private handleSystemFontSizeScaleChange(): void {
    this.browserHostedRuntimeSurfacePort.updateCurrentActiveConfigFromHost();
  }

  private resolveEffectiveWebTextZoomRatio(): number {
    return this.webTextZoomViewModel.resolveEffectiveRatio(this.webTextZoomRatio, this.systemFontSizeScale);
  }

  private applyUserAgentToController(controller: webview.WebviewController | undefined, pageUrl: string = ''): void {
    this.browserWebLoadRuntimeCoordinator.applyUserAgentToController(controller, pageUrl);
  }

  private buildWebAppearancePolicy(): WebAppearancePolicy {
    const preferences = sharedPreferencesRepository.getPreferences();
    return resolveWebAppearancePolicyForTheme({
      paletteId: preferences.appearance.themePaletteId,
      resolvedThemeMode: this.browserThemeModeCoordinator.resolveEffectiveMode(preferences.themeMode),
      forceDarkWebContentEnabled: preferences.appearance.forceDarkWebContentEnabled
    });
  }

  private buildWebAppearancePolicyForTab(_tab: BrowserTabState | undefined): WebAppearancePolicy {
    return this.buildWebAppearancePolicy();
  }

  private getSharedStageStorage(): LocalStorage | undefined {
    return this.getUIContext().getSharedLocalStorage();
  }

  private connectBrowserSearchInvocationSurfaceIfReady(): void {
    this.browserSearchInvocationSurfaceConnection.connectForShell(
      this.currentWindowId,
      this.isBrowserShellVisible && !this.isRestoringTabs,
      this.browserShellPresentationOperations?.surface() === 'large_screen',
      this.browserShellSearchInvocationAdapter,
      this.browserLargeScreenShellIntentApplication.resolveSearchInvocationAdapter()
    );
  }

  private scheduleWebSafeInsetSettleSync(source: string): void {
    this.browserWindowAvoidAreaCoordinator.scheduleSafeInsetSettleSync(source, {
      resolveInput: () => {
        return {
          webPageVisible: this.isWebPageVisible(),
          tabsSheetVisible: this.showTabsSheet,
          fullScreenModeEnabled: this.browserFullscreenSessionPresentation.fullScreenModeEnabled,
          webStatusBarVisible: this.webStatusBarVisible
        };
      },
      refreshSystemBars: (syncSource: string): Promise<void> => {
        return this.browserWebTopImmersionSessionCoordinator.reassertVisibleWindow(
          `safe-inset-settle-${syncSource}`
        );
      },
      runSync: (_source: string): void => {
        this.syncWindowSafeInsetsForShell(true);
      },
      logSync: (_syncSource: string): void => {
      }
    }, WEB_SAFE_INSET_SETTLE_SYNC_DELAY_MS, WEB_SAFE_INSET_SYSTEM_BAR_REFRESH_SETTLE_DELAY_MS);
  }

  private getWindowScopeId(): string {
    return this.currentWindowId.length > 0 ? this.currentWindowId : MAIN_WINDOW_ID;
  }

  private buildHostedWebNodeCallbacks(): HostedWebNodeCallbacks {
    return this.browserWebEventHostCoordinator.buildCallbacks({
      onControllerAttached: (tabId: string) => this.handleTabWebControllerAttached(tabId),
      onBeforeWebBuild: (tabId: string) => {
        this.browserWebTabsController.onBeforeWebBuild(tabId);
        this.browserWebTopImmersionSessionCoordinator.handleBeforeWebBuild(tabId);
        this.browserMediaRuntimeObservationApplicationCoordinator.beginDocument(tabId);
      },
      onPageVisible: (tabId: string, _event: OnPageVisibleEvent) =>
        this.browserWebTopImmersionSessionCoordinator.handlePageVisible(tabId),
      onPageBegin: (tabId: string, event: OnPageBeginEvent) =>
        this.browserWebPageLifecycleApplicationCoordinator.handlePageBegin(tabId, event),
      onPageEnd: (tabId: string, event: OnPageEndEvent) => {
        this.browserWebPageLifecycleApplicationCoordinator.handlePageEnd(tabId, event);
        this.novelReaderApplication.handlePageReady(
          this.novelReaderSession, tabId, this.activeTabId, this.isWebPageVisible(), event.url);
      },
      onNativeMediaPlayerObserved: (tabId: string, mediaInfo: webview.MediaInfo) =>
        this.browserMediaRuntimeObservationApplicationCoordinator.handleNativeMediaPlayerObserved(tabId, mediaInfo),
      onAudioStateChanged: (tabId: string, playing: boolean) =>
        this.browserTabSwitchCoordinator.applyTabAudibleState(tabId, playing),
      onLoadFinished: (tabId: string) =>
        this.browserWebPageLifecycleApplicationCoordinator.handleLoadFinished(tabId),
      onProgressChange: (tabId: string, event: OnProgressChangeEvent) =>
        this.browserWebPageLifecycleApplicationCoordinator.handleProgressChange(tabId, event.newProgress),
      onScroll: (tabId: string, event: OnScrollEvent) =>
        this.browserWebScrollInteractionCoordinator.handleScroll(tabId, event.yOffset),
      onTouch: (tabId: string, event: TouchEvent) =>
        this.browserWebScrollInteractionCoordinator.handleTouchEvent(tabId, event.type),
      onNavigationEntryCommitted: (tabId: string, details: LoadCommittedDetails) => {
        this.browserWebPageLifecycleApplicationCoordinator.handleNavigationEntryCommitted(tabId, details);
        this.novelReaderApplication.handleNavigationEntryCommitted(this.novelReaderSession, {
          tabId: tabId,
          activeTabId: this.activeTabId,
          webPageVisible: this.isWebPageVisible(),
          pageUrl: details.url,
          isMainFrame: details.isMainFrame,
          isSameDocument: details.isSameDocument
        });
      },
      onTitleReceive: (tabId: string, event: OnTitleReceiveEvent) =>
        this.browserWebPageLifecycleApplicationCoordinator.handleTitleReceive(tabId, event.title),
      onFaviconReceived: (tabId: string, event: OnFaviconReceivedEvent) =>
        this.browserWebPageLifecycleApplicationCoordinator.handleFaviconReceived(tabId, event),
      onSearchResultReceive: (tabId: string, event: OnSearchResultReceiveEvent) =>
        this.browserPageFindCoordinator.handleSearchResult(tabId, event),
      onErrorReceive: (tabId: string, event: OnErrorReceiveEvent) =>
        this.browserWebPageLifecycleApplicationCoordinator.handleErrorReceive(tabId, event),
      onPermissionRequest: (tabId: string, request: PermissionRequest) =>
        this.browserWebCapabilityPromptApplicationCoordinator.handleProtectedResourcePermissionRequest(tabId, request),
      onGeolocationShow: (tabId: string, event: OnGeolocationShowEvent) =>
        this.browserWebCapabilityPromptApplicationCoordinator.handleGeolocationPermissionRequest(tabId, event),
      onWindowNew: (tabId: string, event: OnWindowNewEvent) =>
        this.browserWindowOpenApplicationCoordinator.handle(tabId, event),
      onWindowExit: (tabId: string) => this.browserWindowOpenApplicationCoordinator.handleChildExit(tabId),
      onActivateContent: (tabId: string) => this.browserWindowOpenApplicationCoordinator.handleChildActivate(tabId),
      onShowFileSelector: (tabId: string, event: OnShowFileSelectorEvent) =>
        this.browserWebCapabilityPromptApplicationCoordinator.handleShowFileSelector(tabId, event),
      onPrompt: (tabId: string, event: OnPromptEvent) =>
        this.browserWebCapabilityPromptApplicationCoordinator.handleJavaScriptPrompt(tabId, event),
      onConfirm: (tabId: string, event: OnConfirmEvent) =>
        this.browserWebCapabilityPromptApplicationCoordinator.handleJavaScriptConfirm(tabId, event),
      onAlert: (tabId: string, event: OnAlertEvent) =>
        this.browserWebCapabilityPromptApplicationCoordinator.handleJavaScriptAlert(tabId, event),
      onHttpAuthRequest: (tabId: string, event: OnHttpAuthRequestEvent) =>
        this.browserWebCapabilityPromptApplicationCoordinator.handleHttpAuthRequest(tabId, event),
      onSslErrorEvent: (tabId: string, event: SslErrorEvent) =>
        this.browserWebCapabilityPromptApplicationCoordinator.handleSslErrorEvent(tabId, event),
      onLoadIntercept: (tabId: string, event: OnLoadInterceptEvent): boolean =>
        this.browserWebTabsController.onLoadIntercept(tabId, event),
      onInterceptRequest: (tabId: string, event: OnInterceptRequestEvent) => this.handleInterceptRequest(tabId, event),
      onOverrideUrlLoading: (tabId: string, request: WebResourceRequest): boolean =>
        this.browserWebTabsController.onOverrideUrlLoading(tabId, request),
      onDownloadStart: (tabId: string, event: OnDownloadStartEvent) => this.handleDownloadStart(tabId, event),
      onUserScriptInstallRequest: (_tabId: string, url: string) =>
        this.browserUserScriptApplicationCoordinator.handleInstallCandidate(url),
      onHistoryApiUrlChange: (tabId: string, payloadJson: string) =>
        this.browserWebPageLifecycleApplicationCoordinator.handleHistoryApiUrlChange(tabId, payloadJson),
      onPageChromeThemeSignal: (tabId: string, payloadJson: string) => {
        this.browserPageChromeThemeSamplingCoordinator.handleThemeSignal(
          tabId,
          payloadJson
        );
      },
      onPageBehaviorSignal: (tabId: string, payloadJson: string) =>
        this.browserMediaRuntimeObservationApplicationCoordinator.handlePageBehaviorSignal(tabId, payloadJson),
      onAdBlockCosmeticHidden: (tabId: string, payloadJson: string) =>
        this.browserSiteControlsRuntimeCoordinator.handleAdBlockCosmeticHidden(tabId, payloadJson),
      onAdBlockManualHidden: (tabId: string, payloadJson: string) => {
        this.manualElementHideRuntimeCoordinator.recordHiddenFromPayload({
          tabId: tabId,
          payloadJson: payloadJson
        });
      },
      onContextMenuShow: (tabId: string, event: OnContextMenuShowEvent, controller: webview.WebviewController) =>
        this.showWebContextMenu(tabId, event, controller),
      onContextMenuHide: (tabId: string): void => {
        this.webContextMenuCoordinator.hide(tabId);
      },
      onFullScreenEnter: (tabId: string, event: FullScreenEnterEvent) => {
        void this.browserFullscreenSessionCoordinator.enterWebContentFullscreen(tabId, event);
      },
      onFullScreenExit: (tabId: string) =>
        this.browserFullscreenSessionCoordinator.handleWebContentFullscreenExit(tabId)
    });
  }

  private resolveTabBridgeUrl(tab: BrowserTabState | undefined): string {
    if (tab === undefined) {
      return '';
    }
    const pendingUrl = tab.pendingUrl.trim();
    return pendingUrl.length > 0 ? pendingUrl : tab.url.trim();
  }

  private resolveTabBridgeUrlById(tabId: string): string {
    if (tabId.length === 0) {
      return '';
    }
    return this.resolveTabBridgeUrl(this.tabManager.getTab(this.tabs, tabId));
  }

  private recordRuntimeEvent(_type: string, _message: string, _tabId: string = this.activeTabId): void {}

  private appendRestoreTraceBreadcrumb(_tabId: string, _breadcrumb: string): void {}

  private applyShellVisualState(state: BrowserShellVisualState): void {
    if (this.startupHomeSurfacePending && !state.showHomePage) {
      return;
    }
    this.browserWebLoadFailureSurfaceCoordinator.prune(this.tabs.map((tab: BrowserTabState): string => tab.id));
    const wasShowingHomePage = this.showHomePage;
    const wasShowingPageErrorSurface = this.showPageErrorSurface;
    const correctedErrorDocumentTargetUrl = this.browserWebPageLifecycleApplicationCoordinator
      .resolveErrorDocumentCommittedUrl(
        this.activeTabId,
        state.currentUrl,
        'apply_shell_visual_state'
    ).targetUrl;
    this.showHomePage = state.showHomePage;
    if (state.showHomePage) {
      this.browserRootBottomPanelSessionCoordinator.cancelHomeToWebBottomPanelTransition();
    } else {
      this.browserRootBottomPanelSessionCoordinator.scheduleHomeToWebBottomPanelTransitionCompletion();
    }
    this.customHomepageRuntimeCoordinator.syncVisibility();
    syncBrowserThemeAppStorage();
    this.browserTabHomeCoordinator.refreshAppearance();
    if (!wasShowingHomePage && state.showHomePage) {
      this.browserHomePresentationSessionCoordinator.handleHomeBecameVisible();
    }
    const shouldForceErrorSurface = this.browserWebLoadFailureSurfaceCoordinator.shouldShow(this.activeTabId);
    this.showPageErrorSurface = state.showPageErrorSurface &&
      this.browserWebLoadFailureSurfaceCoordinator.shouldShowNativeSurface(this.activeTabId);
    this.currentUrl = correctedErrorDocumentTargetUrl.length > 0 ? correctedErrorDocumentTargetUrl : state.currentUrl;
    this.pendingWebUrl = correctedErrorDocumentTargetUrl.length > 0 ? correctedErrorDocumentTargetUrl : state.pendingWebUrl;
    this.addressInput = correctedErrorDocumentTargetUrl.length > 0
      ? this.resolveCommittedAddressDisplayText(correctedErrorDocumentTargetUrl)
      : state.addressInput;
    if (wasShowingHomePage !== state.showHomePage) {
      this.reconcileExternalNavigationPromptForCurrentPage(this.currentUrl);
    }
    this.currentTitle = state.currentTitle;
    this.errorMessage = this.showPageErrorSurface
      ? this.browserWebLoadFailureSurfaceCoordinator.resolveErrorMessage(this.activeTabId, state.errorMessage)
      : state.errorMessage;
    this.helperMessage = state.helperMessage;
    this.runtimeDegradedMessage = state.runtimeDegradedMessage;
    this.browserWebPageLifecycleApplicationCoordinator.restoreLoadingProgressState(
      state.pageProgress,
      state.isLoading
    );
    this.isLoading = state.isLoading;
    if (state.showHomePage) {
      this.homeShortcutStateCoordinator.refresh();
      this.browserTabHomeCoordinator.schedulePromptEvaluations();
      this.browserTopFloatingPromptCoordinator.scheduleGestureOnboardingPrompt();
    }
    if (wasShowingHomePage && !state.showHomePage) {
      this.scheduleWebSafeInsetSettleSync('web-surface-enter');
    }
    if (state.resetScrollMask) {
      this.browserWebScrollInteractionCoordinator.resetForNavigation(this.activeTabId);
      this.restoreWebBottomAddressPanelFromPeek();
      this.browserWebTopImmersionSessionCoordinator.requestVisible('scroll-reset');
    }
    this.browserWebTopImmersionSessionCoordinator.syncPolicy('shell-visual-state');
    this.browserQuickSearchSwitchingCoordinator.syncActivePresentation('shell-visual-state');
    if (!wasShowingPageErrorSurface && this.shouldSuspendHostedWebSurface()) {
      this.browserHostedRuntimeSurfacePort.detachActive();
    }
  }

  private handleTabWebControllerAttached(tabId: string): void {
    this.browserWebScrollInteractionCoordinator.handleControllerAttached(tabId);
    if (this.browserBackgroundTabPreviewRuntimeCoordinator.tryHandleControllerAttached(tabId)) {
      return;
    }
    this.browserControllerAttachmentRuntimeCoordinator.handleControllerAttachedSignal(tabId);
    this.browserWebTopImmersionSessionCoordinator.handleControllerAttached(tabId);
    this.browserPageFindCoordinator.handleControllerAttached(tabId);
  }

  private async captureCurrentTabPreviewBeforeLeavingOpenerTab(
    openerTabId: string,
    targetTabId: string,
    source: BrowserTabPreviewOpenerBeforeSwitchSource
  ): Promise<void> {
    if (openerTabId === this.activeTabId && !this.showHomePage &&
      await this.probeAndAdoptVisibleSurfaceSnapshot(openerTabId)) {
      return;
    }
    const input: BrowserTabPreviewOpenerBeforeSwitchInput = {
      openerTabId: openerTabId,
      activeTabId: this.activeTabId,
      showHomePage: this.showHomePage,
      targetTabId: targetTabId,
      waitMs: OPENER_TAB_PREVIEW_BEFORE_SWITCH_WAIT_MS,
      source: source,
      captureVisibleTabSurface: this.isLargeScreenShellFamilyActive()
    };
    await this.browserTabPreviewActionCoordinator.captureOpenerBeforeSwitch(
      this.buildTabPreviewActionPort(),
      input
    );
  }

  private async probeAndAdoptVisibleSurfaceSnapshot(tabId: string): Promise<boolean> {
    if (!this.isLargeScreenShellFamilyActive()) {
      return false;
    }
    const tab = this.tabManager.getTab(this.tabs, tabId);
    if (tab === undefined || tab.isHome) {
      return false;
    }
    const input: BrowserTabsOverviewSnapshotPipelineExternalCaptureInput = {
      tab: tab,
      uiContext: this.getUIContext(),
      componentSnapshotId: buildBrowserTabPreviewVisibleSurfaceSnapshotId(tab.id),
      componentSnapshotScale: TABS_OVERVIEW_ENTRY_PIXELMAP_SCALE,
      transitionSource: this.tabsOverviewSnapshotPipelineCoordinator
        .buildCurrentWebVisibleTabSurfaceTransitionSource(),
      shouldKeepPixelMap: (): boolean => this.activeTabId === tab.id && !this.showHomePage
    };
    return await this.tabsOverviewSnapshotPipelineCoordinator.captureAndAdoptExternalTransitionSnapshot(input);
  }

  private handleCustomHomepageScroll(event: OnScrollEvent): void {
    this.browserTabHomeCoordinator.handleContentAction({
      type: 'scroll',
      scrollSource: 'custom',
      scrollOffsetY: Math.max(0, Math.round(event.yOffset))
    });
  }

  private restoreWebBottomAddressPanelFromPeek(): void {
    this.browserRootBottomPanelSessionCoordinator.restoreScrollPresentation();
    if (this.isWebAppImmersiveMode()) {
      this.setWebBottomAddressFocused(false);
      this.webBottomAddressDraft = '';
      this.rootBottomAddressPanelDetent = 'peek';
      this.syncBottomPanelStatusBarStyle();
      return;
    }
    if (this.rootBottomAddressPanelDetent === 'peek') {
      this.rootBottomAddressPanelDetent = 'low';
      this.syncBottomPanelStatusBarStyle();
    }
  }

  private buildHomePagePresentationState(): BrowserHomePagePresentationState {
    return this.browserHomePresentationViewModel.buildPageState({
      showHomePage: this.showHomePage,
      tabsOverviewSceneBackgroundVisible: this.buildTabsOverviewSceneRenderState().homeLayerMounted,
      sceneHitTestEnabled: this.buildTabsOverviewSceneRenderState().homeLayerInteractive,
      homeRevealFromTabsProgress: this.homePresentationSessionState.revealProgress,
      homeRevealFromTabsInteractionBlocked:
        this.homePresentationSessionState.revealInteractionBlocked,
      startupEntranceState: this.homePresentationSessionState.startupEntranceState
    });
  }

  private buildHomeSurfaceContentPresentationState(): BrowserHomeSurfaceContentPresentationState {
    return this.browserHomePresentationViewModel.buildSurfaceContentPresentationState({
      entranceProgress: this.homePresentationSessionState.contentEntranceProgress
    });
  }

  private resetWebBottomAddressPanelForTabSelection(): void {
    this.browserRootBottomPanelSessionCoordinator.restoreScrollPresentation();
    this.setWebBottomAddressFocused(false);
    this.webBottomAddressDraft = '';
  }

  private isTopImmersionPreferenceEnabled(): boolean {
    return this.webScrollGlobalImmersionEnabled || this.webScrollAlwaysTopImmersionEnabled;
  }

  private isAlwaysTopImmersionEnabled(): boolean {
    return this.webScrollAlwaysTopImmersionEnabled;
  }

  private refreshActivePageExperimentRuntimes(): void {
    this.browserShellLifecycleCoordinator.refreshExperimentSettings();
    this.appProxyQuickSheetCoordinator.refresh();
    this.browserHostedRuntimeSurfacePort.updateCurrentActiveConfigFromHost();
    this.customHomepageRuntimeCoordinator.refresh(true);
    if (this.activeTabId.length <= 0) {
      return;
    }
    this.browserWebPageLifecycleApplicationCoordinator.refreshWebSmoothModeRuntime(this.activeTabId);
    if (!this.isWebVideoTakeoverExperimentEnabled()) {
      this.browserMediaDiscoveryCoordinator.refreshActiveMediaDiscoverySurface(this.browserMediaDiscoveryHost);
    }
  }

  private persistActiveTabSnapshot(reason: string): void {
    void this.persistActiveTabSnapshotInternal(reason);
  }

  private persistActiveTabSnapshotAsync(reason: string): void {
    this.persistActiveTabSnapshot(reason);
  }

  private invalidateWebSessionTransition(): void {
    this.webSessionTransitionToken += 1;
  }

  private beginWebSessionTransition(): number {
    this.webSessionTransitionToken += 1;
    return this.webSessionTransitionToken;
  }

  private isWebSessionTransitionCurrent(token: number, tabId: string): boolean {
    return token === this.webSessionTransitionToken && this.activeTabId === tabId && !this.showHomePage;
  }

  private async persistActiveTabSnapshotInternal(reason: string): Promise<void> {
    await this.browserTabRecoveryCoordinator.runActiveSnapshotPersistFromHost(
      this.webStateSnapshotStore,
      reason,
      this.browserSnapshotPersistenceHost,
      this.controllerAttached
    );
  }

  private stringifyError(error: Error): string {
    if (error.message !== undefined && error.message.length > 0) {
      return error.message;
    }
    try {
      const serialized = JSON.stringify(error);
      return serialized.length > 0 ? serialized : '未知错误';
    } catch (_stringifyError) {
      return '未知错误';
    }
  }

  private async returnHomeFromWebByClosingCurrentTab(source: BrowserUserReturnHomeSource): Promise<void> {
    const activeTab = this.tabManager.getActiveTab(this.tabs, this.activeTabId);
    await this.browserUserReturnHomeCoordinator.runFlow({
      source: source,
      showHomePage: this.showHomePage,
      showTabsSheet: this.showTabsSheet,
      activeTab: activeTab,
      activeTabId: this.activeTabId,
      tabs: this.tabs
    }, this.browserRootBottomPanelFixedActionShell);
  }

  private restoreHomeBottomPanelForDirectHomeNavigation(detent: HomeSearchPanelDetent = 'low'): void {
    this.browserShellSearchInvocationAdapter.releaseHomeSearchFocus();
    this.addressInput = '';
    this.browserRootBottomPanelSessionCoordinator.resetSearchBackdropPresentation();
    this.cancelRootBottomPanelAddressFocusBackdropTransition();
    this.rootBottomAddressPanelDetent = detent;
    this.syncBottomPanelStatusBarStyle();
  }

  private isWebPageVisible(): boolean {
    return !this.showHomePage && !this.startupHomeSurfacePending;
  }

  private shouldHandleActiveWebTab(tabId: string): boolean {
    return tabId === this.activeTabId && this.isWebPageVisible();
  }

  private resolveWebTabSnapshot(tabId: string): BrowserWebTabsControllerTabSnapshot | undefined {
    const tab = this.tabManager.getTab(this.tabs, tabId);
    if (tab === undefined) {
      return undefined;
    }
    return {
      id: tab.id,
      url: tab.url,
      pendingUrl: tab.pendingUrl,
      isHome: tab.isHome
    };
  }

  private resetTransientOverlayStateForRouteTransition(
    syncPromptFromService: boolean,
    preservedCustomBottomSurfaceIds: BrowserTransientSurfaceId[] = []
  ): void {
    this.browserRootBottomPanelSessionCoordinator
      .resetForRouteTransitionPresentation(preservedCustomBottomSurfaceIds);
    const systemSheetResetEffect = this.browserTransientSurfaceCoordinator.resetSystemSheet();
    this.browserQrScanCoordinator.resetSession();
    this.browserWebPageToolsCoordinator.reset();
    this.releaseNoticePresentationCoordinator.handleShellReset();
    this.applyBrowserSystemSheetDisappearEffect(systemSheetResetEffect);
    this.appReviewPromptCoordinator.handleShellReset();
    this.articleReadingSession.resetSpeechVoicePickerState();
    this.articleReadingSession.resetSpeechPlayerPresentation();
    this.browserTransientSurfaceCoordinator.resetAllCustomBottomSurfaces(preservedCustomBottomSurfaceIds);
    if (this.browserFullscreenSessionPresentation.fullScreenModeEnabled) {
      this.disableFullScreenMode();
    }
    this.browserSiteControlsRuntimeCoordinator.handleShellDisappear();
    this.browserDownloadConfirmOverlayCoordinator.reset(syncPromptFromService);
  }

  private restoreSavedTabs(): void {
    const tabSessionBoundaryOptions = this.browserWindowContextCoordinator.resolveCurrentTabSessionBoundary();
    const tabSessionProfileId = this.browserWindowContextCoordinator.resolveCurrentTabSessionProfileId();
    this.browserStartupTabRestoreCoordinator.runStartupRestore({
      tabSessionBoundaryOptions: tabSessionBoundaryOptions,
      profileId: tabSessionProfileId,
      windowId: this.currentWindowId
    });
  }

}
