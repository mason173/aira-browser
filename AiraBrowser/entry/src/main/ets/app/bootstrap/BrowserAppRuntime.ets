import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../runtime/AppRuntimeContext';
import { BrowserDatabase } from '../../data/database/BrowserDatabase';
import { ArkAiraSyncConfigStorageAdapter } from '../../data/preferences/ArkAiraSyncConfigStorageAdapter';
import { ArkPreferencesStorageAdapter } from '../../data/preferences/ArkPreferencesStorageAdapter';
import { BrowserMigrationRepository } from '../../data/preferences/BrowserMigrationRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { HomePagePresentationSettingsRepository } from '../../data/preferences/HomePagePresentationSettingsRepository';
import { BrowserTabletInterfaceModeRepository } from '../../data/preferences/BrowserTabletInterfaceModeRepository';
import { SecureDnsSettingsRepository } from '../../data/preferences/SecureDnsSettingsRepository';
import {
  BrowserWebSecuritySettingsRepository,
  sharedBrowserWebSecuritySettingsRepository as dataSharedBrowserWebSecuritySettingsRepository
} from '../../data/preferences/BrowserWebSecuritySettingsRepository';
import { HomePageSettingsCoordinator } from '../../core/settings/HomePageSettingsCoordinator';
import { SecureDnsSettingsCoordinator } from '../../core/settings/SecureDnsSettingsCoordinator';
import { SecureDnsSettingsModel } from '../../core/settings/SecureDnsSettingsModel';
import { SiteCustomizationManagementCoordinator } from '../../core/sitecustomization/SiteCustomizationManagementCoordinator';
import { SettingsNoticeDismissalRepository } from '../../data/preferences/SettingsNoticeDismissalRepository';
import { AdBlockRepository } from '../../data/adblock/AdBlockRepository';
import { ManualElementHideRepository } from '../../data/adblock/ManualElementHideRepository';
import { BrowserSecurityReportMetricsRepository } from '../../data/browser/BrowserSecurityReportMetricsRepository';
import { BrowserSitePrivacyRuleRepository } from '../../data/browser/BrowserSitePrivacyRuleRepository';
import { PrivateModeCookieSnapshotRepository } from '../../data/browser/PrivateModeCookieSnapshotRepository';
import { SiteClearOnClosePendingRepository } from '../../data/browser/SiteClearOnClosePendingRepository';
import { BrowserUserAgentSettingsRepository } from '../../data/browser/BrowserUserAgentSettingsRepository';
import {
  SavedSiteSettingRepository,
  sharedSavedSiteSettingRepository as dataSharedSavedSiteSettingRepository
} from '../../data/browser/SavedSiteSettingRepository';
import { PasswordSettingsRepository } from '../../data/password/PasswordSettingsRepository';
import { ExternalAppSearchPreferencesRepository } from '../../data/search/ExternalAppSearchPreferencesRepository';
import { QuickSearchSwitchPreferencesRepository } from
  '../../data/search/QuickSearchSwitchPreferencesRepository';
import { SearchEngineRepository } from '../../data/search/SearchEngineRepository';
import { SearchQueryHistoryRepository } from '../../data/search/SearchQueryHistoryRepository';
import { TranslationSettingsRepository } from '../../data/translation/TranslationSettingsRepository';
import { TranslationSecretStore } from '../../data/translation/TranslationSecretStore';
import { UserScriptRepository } from '../../data/userscripts/UserScriptRepository';
import { UserScriptRiskConsentRepository } from '../../data/userscripts/UserScriptRiskConsentRepository';
import {
  UserScriptRuntimeStateRepository,
  UserScriptValueDiagnosticRecorderAdapter
} from '../../data/userscripts/UserScriptRuntimeStateRepository';
import { UserScriptValueFileAdapter } from '../../data/userscripts/UserScriptValueFileAdapter';
import { UserScriptValueStateStore } from '../../data/userscripts/UserScriptValueStateStore';
import { UserScriptValueDiagnosticEvent } from '../../features/userscripts/UserScriptValueModels';
import { WallpaperRepository } from '../../data/wallpaper/WallpaperRepository';
import { CustomHomepageRepository } from '../../data/customhome/CustomHomepageRepository';
import { StartupWelcomeIntroRepository } from '../../data/onboarding/StartupWelcomeIntroRepository';
import { GestureOnboardingPromptRepository } from '../../data/onboarding/GestureOnboardingPromptRepository';
import { AppReviewPromptRepository } from '../../data/review/AppReviewPromptRepository';
import { ActivityRepository } from '../../data/activity/ActivityRepository';
import { ReleaseNoticeRepository } from '../../data/update/ReleaseNoticeRepository';
import { BookmarkFolderCountCacheRepository } from '../../data/bookmarks/BookmarkFolderCountCacheRepository';
import { AiraLocalBookmarkOverviewCacheRepository } from '../../data/sync/AiraLocalBookmarkOverviewCacheRepository';
import { PersonalizationSyncConfigStore } from '../../data/sync/PersonalizationSyncConfigStore';
import { NovelBookshelfSyncStateStore } from '../../data/sync/NovelBookshelfSyncStateStore';
import { SyncExperienceStateStore } from '../../data/sync/SyncExperienceStateStore';
import { HuaweiSpaceBookmarkUpgradeStore } from '../../data/sync/HuaweiSpaceBookmarkUpgradeStore';
import { ActivityTracker } from '../../services/activity/ActivityTracker';
import { SearchEngineAvailabilityProbeService } from '../../services/search/SearchEngineAvailabilityProbeService';
import { SearchEngineRoutingService } from '../../services/search/SearchEngineRoutingService';
import { SearchQueryHistoryService } from '../../services/search/SearchQueryHistoryService';
import {
  WebNetworkAvailabilityService,
  WebNetworkAvailabilitySnapshot
} from '../../services/web/WebNetworkAvailabilityService';
import { TranslationProviderSecretService } from '../../services/translation/TranslationProviderSecretService';
import { UserScriptInstallSessionCoordinator } from '../../core/userscripts/UserScriptInstallSessionCoordinator';
import { UserScriptManagementSessionCoordinator } from '../../core/userscripts/UserScriptManagementSessionCoordinator';
import { UserScriptPackageLifecycleCoordinator } from '../../core/userscripts/UserScriptPackageLifecycleCoordinator';
import {
  UserScriptNativeBridgeCoordinator,
  UserScriptNativeBridgeHost
} from '../../core/userscripts/UserScriptNativeBridgeCoordinator';
import { UserScriptPageActionsViewModel } from '../../core/userscripts/UserScriptPageActionsViewModel';
import { UserScriptRuntimeCoordinator } from '../../core/userscripts/UserScriptRuntimeCoordinator';
import { UserScriptRuntimeReadinessCoordinator } from '../../core/userscripts/UserScriptRuntimeReadinessCoordinator';
import {
  sharedAdBlockDocumentStartScriptProviderRegistry
} from '../../core/adblock/AdBlockDocumentStartScriptProviderRegistry';
import { AdBlockDocumentStartCoordinator } from '../../core/adblock/AdBlockDocumentStartCoordinator';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BookmarkFolderSelectionPreparationCoordinator } from '../../core/browser/BookmarkFolderSelectionPreparationCoordinator';
import { AccountIdentityChangeCoordinator } from '../../core/account/AccountIdentityChangeCoordinator';
import { HuaweiAccountMutationCoordinator } from '../../core/account/HuaweiAccountMutationCoordinator';
import { sharedCrossDeviceTabPresenceCoordinator } from '../../core/deviceTabs/CrossDeviceTabPresenceCoordinator';
import { ActivityForegroundSessionCoordinator } from '../../core/activity/ActivityForegroundSessionCoordinator';
import { ReleaseNoticeCoordinator } from '../../core/update/ReleaseNoticeCoordinator';
import { BrowserGestureOnboardingPromptCoordinator } from '../../core/browser/BrowserGestureOnboardingPromptCoordinator';
import { SearchEngineSettingsCoordinator } from '../../core/search/SearchEngineSettingsCoordinator';
import { BrowserThemeModeCoordinator } from '../../core/browser/BrowserThemeModeCoordinator';
import {
  BrowserRuntimeMaintenanceCoordinator,
  BrowserRuntimeMaintenanceTask
} from '../../core/browser/BrowserRuntimeMaintenanceCoordinator';
import { BrowserThemeViewStateFactory } from '../../core/theme/BrowserThemeViewState';
import { isBrowserThemePresentationScope } from '../../core/theme/BrowserThemePreferenceScopes';
import { AdBlockRuleSourceCoordinator } from '../../core/adblock/AdBlockRuleSourceCoordinator';
import { AdBlockRuntimeGenerationCoordinator } from '../../core/adblock/AdBlockRuntimeGenerationCoordinator';
import { BrowserExperimentMigrationCoordinator } from '../../core/settings/BrowserExperimentMigrationCoordinator';
import { buildBrowserDataBoundary, SearchEngineRecord } from '../../common/models/BrowserModels';
import { resolveAiraHuaweiAccountIdentity } from '../../common/models/AiraSyncModels';
import {
  BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY,
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_CLOSE_BUTTON_ALWAYS_VISIBLE_KEY,
  BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBLE_KEY,
  BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_LAYOUT_STYLE_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_APP_PROXY_ACTIVE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { DownloadRuntimeService } from '../../services/download/DownloadRuntimeService';
import { DownloadPolicyService } from '../../services/download/DownloadPolicyService';
import { DownloadV2Service } from '../../services/downloadv2/DownloadV2Service';
import { DownloadV2SystemNotificationService } from
  '../../services/downloadv2/DownloadV2SystemNotificationService';
import { SitePolicyService } from '../../services/web/SitePolicyService';
import { ShortcutIconResolverService } from '../../services/shortcuts/ShortcutIconResolverService';
import { ArkWebAppProxyService } from '../../services/web/ArkWebAppProxyService';
import { SecureDnsService } from '../../services/web/SecureDnsService';
import { BrowserProxyRuntimeRefreshCoordinator } from '../../core/browser/BrowserProxyRuntimeRefreshCoordinator';
import { AppCrashDiagnosticsService } from '../../services/diagnostics/AppCrashDiagnosticsService';
import { buildPersistentDownloadV2Repository } from '../../data/downloadv2/DownloadV2Repository';
import { ArkWebDownloadBridge } from '../../platform/download/ArkWebDownloadBridge';
import {
  RdbBookmarkRepository,
  RdbHistoryRepository,
  RdbRecentlyClosedTabRepository,
  RdbShortcutRepository,
  RdbTabSessionRepository
} from '../../data/repositories/BrowserRepositories';
import { RecentlyClosedTabSnapshotStore } from '../../data/repositories/RecentlyClosedTabSnapshotStore';
import { RdbOfflinePageRepository } from '../../data/offline/OfflinePageRepository';
import { MembershipRepository } from '../../data/membership/MembershipRepository';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { HistoryFeature } from '../../features/history/HistoryFeature';
import { sharedDesktopCardSearchEngineService } from
  '../../features/desktopcard/DesktopCardSearchEngineService';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
import {
  HistorySyncService,
  resolveHistorySyncProviderKind
} from '../../services/sync/HistorySyncService';
import { SyncService } from '../../services/sync/SyncService';
import { PersonalizationSyncService } from '../../services/sync/PersonalizationSyncService';
import { PersonalizationSyncSnapshotService } from '../../services/sync/PersonalizationSyncSnapshotService';
import { NovelBookshelfSyncModule } from '../../services/sync/NovelBookshelfSyncModule';
import { sharedNovelLibraryRepository } from '../../data/novel/NovelLibraryRepository';
import {
  sharedNovelReadingCheckpointRepository
} from '../../data/novel/NovelReadingCheckpointRepository';
import { BookmarkMutationService } from '../../services/bookmarks/BookmarkMutationService';
import { SyncBookmarkDomain } from '../../core/sync/SyncBookmarkDomain';
import { SyncExperienceAutomaticRuntime } from '../../core/sync/SyncExperienceAutomaticRuntime';
import { SyncExperienceAdvancedOperations } from '../../core/sync/SyncExperienceAdvancedOperations';
import { SyncRemoteStatusCoordinator } from '../../core/sync/SyncRemoteStatusCoordinator';
import { SyncExperienceProviderOperations } from '../../core/sync/SyncExperienceProviderOperations';
import { SyncPersonalizationDomain } from '../../core/sync/SyncPersonalizationDomain';
import { SyncExperienceProviderActivation } from '../../core/sync/SyncExperienceProviderActivation';
import { SyncExperienceCoordinator } from '../../core/sync/SyncExperienceCoordinator';
import { LocalBackupCoordinator } from '../../core/backup/LocalBackupCoordinator';
import { LocalBackupService } from '../../services/backup/LocalBackupService';
import { BrowserUserAgentHostPolicyService } from '../../services/web/BrowserUserAgentHostPolicyService';
import {
  BrowserFingerprintPrivacyPolicyService
} from '../../services/privacy/BrowserFingerprintPrivacyPolicyService';

const DOMAIN = 0x0000;
const TAG = 'BrowserAppRuntime';
const BOOKMARK_RUNTIME_WARMUP_DELAY_MS: number = 8000;
const SEARCH_ENGINE_FALLBACK_WARMUP_DELAY_MS: number = 2800;
const DEFERRED_RUNTIME_WARMUP_DELAY_MS: number = 6500;
const DEFERRED_BROWSER_REPOSITORY_WARMUP_DELAY_MS: number = 2500;
const RUNTIME_IDLE_WARMUP_START_DELAY_MS: number = 6000;
// Keep a cooperative yield between repository initializers without adding nearly a second of idle time per task.
const RUNTIME_IDLE_WARMUP_TASK_GAP_MS: number = 80;
const DEFERRED_RUNTIME_WARMUP_TASK_GAP_MS: number = 700;
const BOOKMARK_RUNTIME_WARMUP_TASK_GAP_MS: number = 900;
const DEFERRED_BROWSER_REPOSITORY_WARMUP_TASK_GAP_MS: number = 700;
const RUNTIME_MAINTENANCE_START_DELAY_MS: number = 90000;
const RUNTIME_MAINTENANCE_TASK_GAP_MS: number = 15000;

interface BrowserRuntimeIdleWarmupTask {
  id: string;
  run: () => Promise<void>;
}

export const sharedBrowserDatabase: BrowserDatabase = new BrowserDatabase();
export const sharedPersonalizationSyncConfigStore: PersonalizationSyncConfigStore =
  new PersonalizationSyncConfigStore();
export const sharedPreferencesRepository: PreferencesRepository =
  new PreferencesRepository(new ArkPreferencesStorageAdapter());
export const sharedBrowserFingerprintPrivacyPolicyService: BrowserFingerprintPrivacyPolicyService =
  new BrowserFingerprintPrivacyPolicyService();
export const sharedHomePagePresentationSettingsRepository: HomePagePresentationSettingsRepository =
  new HomePagePresentationSettingsRepository();
export const sharedBrowserTabletInterfaceModeRepository: BrowserTabletInterfaceModeRepository =
  new BrowserTabletInterfaceModeRepository();
const sharedSecureDnsSettingsModel: SecureDnsSettingsModel = new SecureDnsSettingsModel();
const sharedSecureDnsService: SecureDnsService = new SecureDnsService(sharedSecureDnsSettingsModel);
export const sharedSecureDnsSettingsRepository: SecureDnsSettingsRepository =
  new SecureDnsSettingsRepository(sharedSecureDnsSettingsModel);
export const sharedSecureDnsSettingsCoordinator: SecureDnsSettingsCoordinator =
  new SecureDnsSettingsCoordinator(
    sharedSecureDnsSettingsRepository,
    sharedSecureDnsService,
    sharedSecureDnsSettingsModel
  );
export const sharedBrowserMigrationRepository: BrowserMigrationRepository =
  new BrowserMigrationRepository();
export const sharedSettingsNoticeDismissalRepository: SettingsNoticeDismissalRepository =
  new SettingsNoticeDismissalRepository();
export const sharedBrowserExperimentMigrationCoordinator: BrowserExperimentMigrationCoordinator =
  new BrowserExperimentMigrationCoordinator(sharedPreferencesRepository, sharedBrowserMigrationRepository);
export const sharedAdBlockRepository: AdBlockRepository = new AdBlockRepository();
export const sharedAdBlockRuntimeGenerationCoordinator: AdBlockRuntimeGenerationCoordinator =
  AdBlockRuntimeGenerationCoordinator.forRepository(sharedAdBlockRepository);
sharedAdBlockDocumentStartScriptProviderRegistry.register(
  new AdBlockDocumentStartCoordinator(sharedAdBlockRepository)
);
export const sharedManualElementHideRepository: ManualElementHideRepository = new ManualElementHideRepository();
export const sharedPasswordSettingsRepository: PasswordSettingsRepository = new PasswordSettingsRepository();
export const sharedExternalAppSearchPreferencesRepository: ExternalAppSearchPreferencesRepository =
  new ExternalAppSearchPreferencesRepository();
export const sharedQuickSearchSwitchPreferencesRepository: QuickSearchSwitchPreferencesRepository =
  new QuickSearchSwitchPreferencesRepository();
export const sharedSearchEngineRepository: SearchEngineRepository = new SearchEngineRepository(
  (itemId: string, deletedAt: number): Promise<void> => {
    return sharedPersonalizationSyncConfigStore.recordItemDeletion('search', itemId, deletedAt)
      .then((): void => undefined);
  }
);
const sharedUserScriptRepository: UserScriptRepository = new UserScriptRepository();
const sharedUserScriptRiskConsentRepository: UserScriptRiskConsentRepository =
  new UserScriptRiskConsentRepository();
const sharedUserScriptRuntimeStateRepository: UserScriptRuntimeStateRepository =
  new UserScriptRuntimeStateRepository();
const sharedUserScriptValueStateStore: UserScriptValueStateStore =
  new UserScriptValueStateStore(new UserScriptValueFileAdapter());
sharedUserScriptValueStateStore.attachDiagnosticSink(sharedUserScriptRuntimeStateRepository);
const sharedUserScriptRuntimeReadinessCoordinator: UserScriptRuntimeReadinessCoordinator =
  new UserScriptRuntimeReadinessCoordinator(
    sharedUserScriptRepository,
    sharedUserScriptRiskConsentRepository,
    sharedUserScriptValueStateStore,
    sharedUserScriptRuntimeStateRepository
  );
export const sharedTranslationSecretStore: TranslationSecretStore = new TranslationSecretStore();
export const sharedTranslationProviderSecretService: TranslationProviderSecretService =
  new TranslationProviderSecretService(sharedTranslationSecretStore);
export const sharedTranslationSettingsRepository: TranslationSettingsRepository = new TranslationSettingsRepository();
export const sharedBrowserUserAgentSettingsRepository: BrowserUserAgentSettingsRepository =
  new BrowserUserAgentSettingsRepository();
export const sharedSavedSiteSettingRepository: SavedSiteSettingRepository =
  dataSharedSavedSiteSettingRepository;
export const sharedBrowserWebSecuritySettingsRepository: BrowserWebSecuritySettingsRepository =
  dataSharedBrowserWebSecuritySettingsRepository;
const SITE_SETTING_LEGACY_RETIREMENT_MIGRATION_ID: string = 'site_settings_exact_origin_retire_legacy_v1';
export const sharedBrowserUserAgentHostPolicyService: BrowserUserAgentHostPolicyService =
  new BrowserUserAgentHostPolicyService();
sharedBrowserUserAgentSettingsRepository.setSettingsChangeHandler((settings) => {
  const policyResult = sharedBrowserUserAgentHostPolicyService.applyApplicationUserAgentForSettings(settings);
  if (!policyResult.applied) {
    hilog.warn(DOMAIN, TAG, '%{public}s', policyResult.message);
  }
});
export const sharedBrowserSitePrivacyRuleRepository: BrowserSitePrivacyRuleRepository =
  new BrowserSitePrivacyRuleRepository();
export const sharedPrivateModeCookieSnapshotRepository: PrivateModeCookieSnapshotRepository =
  new PrivateModeCookieSnapshotRepository();
export const sharedSiteClearOnClosePendingRepository: SiteClearOnClosePendingRepository =
  new SiteClearOnClosePendingRepository();
export const sharedBrowserSecurityReportMetricsRepository: BrowserSecurityReportMetricsRepository =
  new BrowserSecurityReportMetricsRepository();
export const sharedWallpaperRepository: WallpaperRepository = new WallpaperRepository();
export const sharedCustomHomepageRepository: CustomHomepageRepository = new CustomHomepageRepository();
export const sharedStartupWelcomeIntroRepository: StartupWelcomeIntroRepository = new StartupWelcomeIntroRepository();
export const sharedGestureOnboardingPromptRepository: GestureOnboardingPromptRepository =
  new GestureOnboardingPromptRepository();
export const sharedBrowserGestureOnboardingPromptCoordinator: BrowserGestureOnboardingPromptCoordinator =
  new BrowserGestureOnboardingPromptCoordinator(sharedGestureOnboardingPromptRepository);
export const sharedBrowserRuntimeMaintenanceCoordinator: BrowserRuntimeMaintenanceCoordinator =
  new BrowserRuntimeMaintenanceCoordinator();
export const sharedAppReviewPromptRepository: AppReviewPromptRepository = new AppReviewPromptRepository();
export const sharedActivityRepository: ActivityRepository = new ActivityRepository();
export const sharedActivityTracker: ActivityTracker = new ActivityTracker(
  sharedActivityRepository,
  () => {
    const settings = sharedAiraSyncConfigStore.getSettings();
    return resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid;
  },
  () => {
    sharedSyncExperienceCoordinator.notifyPersonalizationLocalSettingsChanged();
  }
);
export const sharedActivityForegroundSessionCoordinator: ActivityForegroundSessionCoordinator =
  new ActivityForegroundSessionCoordinator(sharedActivityTracker);
export const sharedReleaseNoticeRepository: ReleaseNoticeRepository = new ReleaseNoticeRepository();
export const sharedReleaseNoticeCoordinator: ReleaseNoticeCoordinator =
  new ReleaseNoticeCoordinator(sharedReleaseNoticeRepository);
export const sharedSitePolicyService: SitePolicyService =
  new SitePolicyService(sharedPreferencesRepository);
export const sharedArkWebAppProxyService: ArkWebAppProxyService = new ArkWebAppProxyService();
export const sharedBrowserProxyRuntimeRefreshCoordinator: BrowserProxyRuntimeRefreshCoordinator =
  new BrowserProxyRuntimeRefreshCoordinator();
export const sharedAppCrashDiagnosticsService: AppCrashDiagnosticsService = new AppCrashDiagnosticsService();
sharedUserScriptRuntimeStateRepository.attachDiagnosticRecorder(
  new UserScriptValueDiagnosticRecorderAdapter((event: UserScriptValueDiagnosticEvent): void => {
    if (!AppRuntimeContext.hasApplicationContext()) {
      return;
    }
    sharedAppCrashDiagnosticsService.recordDiagnostic(
      AppRuntimeContext.getApplicationContext(),
      'userscript',
      'value_state',
      event.kind,
      event.stage,
      event.code
    );
  })
);
export const sharedPlatformDownloadBridge: ArkWebDownloadBridge =
  new ArkWebDownloadBridge(sharedAppCrashDiagnosticsService);
export const sharedDownloadPolicyService: DownloadPolicyService =
  new DownloadPolicyService(sharedPreferencesRepository);
export const sharedDownloadV2SystemNotificationService: DownloadV2SystemNotificationService =
  new DownloadV2SystemNotificationService();
export const sharedDownloadV2Service: DownloadV2Service = new DownloadV2Service(
  undefined,
  undefined,
  buildPersistentDownloadV2Repository(sharedAppCrashDiagnosticsService),
  sharedPlatformDownloadBridge,
  undefined,
  sharedDownloadPolicyService,
  undefined,
  undefined,
  sharedActivityTracker
);
sharedDownloadV2Service.attachRuntimeDiagnosticRecorder(sharedAppCrashDiagnosticsService);
sharedDownloadV2Service.attachSystemNotificationService(sharedDownloadV2SystemNotificationService);
export const sharedDownloadRuntimeService: DownloadRuntimeService = new DownloadRuntimeService(
  sharedPlatformDownloadBridge,
  sharedDownloadPolicyService,
  sharedDownloadV2Service
);
export const sharedBrowserThemeModeCoordinator: BrowserThemeModeCoordinator =
  new BrowserThemeModeCoordinator(sharedPreferencesRepository);
export const sharedAdBlockRuleSourceCoordinator: AdBlockRuleSourceCoordinator =
  new AdBlockRuleSourceCoordinator(sharedAdBlockRepository, sharedAdBlockRuntimeGenerationCoordinator);
export const sharedBrowserThemeViewStateFactory: BrowserThemeViewStateFactory =
  new BrowserThemeViewStateFactory(undefined, sharedBrowserThemeModeCoordinator);
export const sharedBookmarkRepository: RdbBookmarkRepository =
  new RdbBookmarkRepository(sharedBrowserDatabase, sharedActivityTracker);
export const sharedBookmarkFolderCountCacheRepository: BookmarkFolderCountCacheRepository =
  new BookmarkFolderCountCacheRepository();
export const sharedAiraLocalBookmarkOverviewCacheRepository: AiraLocalBookmarkOverviewCacheRepository =
  new AiraLocalBookmarkOverviewCacheRepository();
export const sharedBookmarkFolderSelectionPreparationCoordinator: BookmarkFolderSelectionPreparationCoordinator =
  new BookmarkFolderSelectionPreparationCoordinator(
    sharedBookmarkRepository,
    sharedAiraLocalBookmarkOverviewCacheRepository
  );
export const sharedSyncExperienceStateStore: SyncExperienceStateStore =
  new SyncExperienceStateStore();
export const sharedHistoryRepository: RdbHistoryRepository = new RdbHistoryRepository(sharedBrowserDatabase);
export const sharedSearchQueryHistoryRepository: SearchQueryHistoryRepository =
  new SearchQueryHistoryRepository(sharedBrowserDatabase);
export const sharedSearchQueryHistoryService: SearchQueryHistoryService =
  new SearchQueryHistoryService(sharedSearchQueryHistoryRepository);
export const sharedSearchEngineAvailabilityProbeService: SearchEngineAvailabilityProbeService =
  new SearchEngineAvailabilityProbeService();
export const sharedSearchEngineRoutingService: SearchEngineRoutingService =
  new SearchEngineRoutingService(sharedSearchEngineAvailabilityProbeService);
const sharedSearchEngineFallbackNetworkAvailabilityService: WebNetworkAvailabilityService =
  new WebNetworkAvailabilityService();
export const sharedShortcutRepository: RdbShortcutRepository = new RdbShortcutRepository(sharedBrowserDatabase);
export const sharedShortcutIconResolverService: ShortcutIconResolverService = new ShortcutIconResolverService();
export const sharedTabSessionRepository: RdbTabSessionRepository = new RdbTabSessionRepository(sharedBrowserDatabase);
export const sharedRecentlyClosedTabSnapshotStore: RecentlyClosedTabSnapshotStore =
  new RecentlyClosedTabSnapshotStore();
export const sharedRecentlyClosedTabRepository: RdbRecentlyClosedTabRepository =
  new RdbRecentlyClosedTabRepository(sharedBrowserDatabase, undefined, sharedRecentlyClosedTabSnapshotStore);
export const sharedOfflinePageRepository: RdbOfflinePageRepository =
  new RdbOfflinePageRepository(sharedBrowserDatabase);
export const sharedAiraSyncConfigStore: AiraSyncConfigStore =
  new AiraSyncConfigStore(new ArkAiraSyncConfigStorageAdapter());
const sharedHistorySyncService: HistorySyncService = new HistorySyncService(
  sharedBrowserDatabase,
  sharedAiraSyncConfigStore,
  undefined,
  async (): Promise<void> => {
    await sharedHistoryRepository.refreshPreview(100);
  }
);
export const sharedHuaweiSpaceBookmarkUpgradeStore: HuaweiSpaceBookmarkUpgradeStore =
  new HuaweiSpaceBookmarkUpgradeStore();
const sharedSyncService: SyncService = new SyncService(
  sharedBookmarkRepository,
  sharedPreferencesRepository,
  sharedAiraSyncConfigStore
);
BookmarkMutationService.configureDefaultSyncPendingMarker((changedAt: number) => {
  return sharedSyncExperienceCoordinator.recordBookmarkMutation(changedAt);
});
export const sharedMembershipRepository: MembershipRepository = new MembershipRepository();
export const sharedMembershipFeature: MembershipFeature =
  new MembershipFeature(sharedMembershipRepository, undefined, undefined, undefined, sharedAiraSyncConfigStore);
const sharedUserScriptPackageLifecycleCoordinator: UserScriptPackageLifecycleCoordinator =
  new UserScriptPackageLifecycleCoordinator(
    sharedUserScriptRepository,
    sharedUserScriptValueStateStore,
    sharedUserScriptRuntimeStateRepository,
    sharedMembershipFeature
  );
export const sharedUserScriptInstallSessionCoordinator: UserScriptInstallSessionCoordinator =
  new UserScriptInstallSessionCoordinator(sharedUserScriptPackageLifecycleCoordinator);
export function createUserScriptManagementSessionCoordinator(): UserScriptManagementSessionCoordinator {
  return new UserScriptManagementSessionCoordinator(
    sharedUserScriptRepository,
    sharedUserScriptRuntimeStateRepository,
    sharedUserScriptValueStateStore,
    sharedUserScriptRiskConsentRepository,
    sharedSettingsNoticeDismissalRepository,
    sharedUserScriptPackageLifecycleCoordinator
  );
}
export function createUserScriptBrowserRuntimeCoordinator(
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
  nativeBridgeHost: UserScriptNativeBridgeHost
): UserScriptRuntimeCoordinator {
  const nativeBridgeCoordinator = new UserScriptNativeBridgeCoordinator(
    sharedUserScriptValueStateStore,
    sharedUserScriptRuntimeStateRepository,
    sharedUserScriptRuntimeReadinessCoordinator,
    nativeBridgeHost
  );
  return new UserScriptRuntimeCoordinator(
    sharedUserScriptValueStateStore,
    sharedUserScriptRuntimeStateRepository,
    nativeBridgeCoordinator,
    new UserScriptPageActionsViewModel(),
    runtimeLifecyclePort,
    sharedUserScriptRuntimeReadinessCoordinator,
    sharedPreferencesRepository
  );
}
sharedSearchEngineRoutingService.setSmartFallbackEligibilityResolver(
  async (): Promise<boolean> => true
);
const sharedSyncRemoteStatusCoordinator: SyncRemoteStatusCoordinator =
  new SyncRemoteStatusCoordinator(sharedSyncService);
const sharedSyncBookmarkDomain: SyncBookmarkDomain =
  new SyncBookmarkDomain(
    sharedSyncService,
    sharedMembershipFeature,
    sharedSyncRemoteStatusCoordinator
  );
const sharedNovelBookshelfSyncModule: NovelBookshelfSyncModule = new NovelBookshelfSyncModule(
  sharedNovelLibraryRepository,
  new NovelBookshelfSyncStateStore(),
  sharedNovelReadingCheckpointRepository
);
const sharedPersonalizationSyncService: PersonalizationSyncService =
  new PersonalizationSyncService(
    sharedPersonalizationSyncConfigStore,
    sharedAiraSyncConfigStore,
    sharedMembershipFeature,
    new PersonalizationSyncSnapshotService({
      preferencesRepository: sharedPreferencesRepository,
      homePagePresentationSettingsRepository: sharedHomePagePresentationSettingsRepository,
      customHomepageRepository: sharedCustomHomepageRepository,
      wallpaperRepository: sharedWallpaperRepository,
      shortcutRepository: sharedShortcutRepository,
      searchEngineRepository: sharedSearchEngineRepository,
      activityRepository: sharedActivityRepository,
      canUseSmartSearchFallback: (): boolean => true
    }),
    undefined,
    sharedNovelBookshelfSyncModule
  );
export const sharedSearchEngineSettingsCoordinator: SearchEngineSettingsCoordinator =
  new SearchEngineSettingsCoordinator(
    sharedSearchEngineRepository,
    sharedPreferencesRepository,
    sharedQuickSearchSwitchPreferencesRepository,
    sharedExternalAppSearchPreferencesRepository
  );
const sharedSyncPersonalizationDomain: SyncPersonalizationDomain =
  new SyncPersonalizationDomain(
    sharedPersonalizationSyncConfigStore,
    sharedAiraSyncConfigStore,
    sharedPersonalizationSyncService
  );
const sharedSyncExperienceAutomaticRuntime: SyncExperienceAutomaticRuntime =
  new SyncExperienceAutomaticRuntime(
    sharedSyncService,
    sharedPersonalizationSyncService,
    sharedAiraSyncConfigStore,
    sharedMembershipFeature,
    sharedSyncBookmarkDomain,
    sharedSyncPersonalizationDomain,
    sharedHistorySyncService,
    sharedSyncExperienceStateStore
  );
sharedHistoryRepository.setSyncContextProvider(() => {
  const settings = sharedAiraSyncConfigStore.getSettings();
  const account = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
  const historyProvider = resolveHistorySyncProviderKind(settings.remoteKind);
  return {
    enabled: sharedSyncExperienceStateStore.getState().historySelected &&
      sharedSyncExperienceStateStore.getState().historyAccountUid === account.uid &&
      historyProvider !== undefined &&
      (historyProvider === 'huawei_space' || sharedMembershipFeature.getState().plan === 'pro'),
    accountUid: account.uid,
    clientId: settings.sourceId,
    deviceName: 'Aira HarmonyOS'
  };
});
sharedHistoryRepository.setSyncChangeHandler(() => {
  sharedSyncExperienceAutomaticRuntime.notifyHistoryLocalChanged();
});
export const sharedAccountIdentityChangeCoordinator: AccountIdentityChangeCoordinator =
  new AccountIdentityChangeCoordinator(
    sharedMembershipFeature,
    sharedActivityRepository,
    undefined,
    () => sharedActivityTracker.flush(),
    undefined,
    async (_uid: string): Promise<void> => {
      await sharedSyncExperienceCoordinator.reconcileHistoryAccountLifecycle();
    }
  );
const sharedSyncExperienceProviderActivation: SyncExperienceProviderActivation = new SyncExperienceProviderActivation(
  sharedSyncService,
  async (uid: string): Promise<void> => {
    await sharedAccountIdentityChangeCoordinator.handleHuaweiIdentityChanged(uid);
  }
);
const sharedSyncExperienceProviderOperations: SyncExperienceProviderOperations =
  new SyncExperienceProviderOperations(
    sharedSyncService,
    sharedPersonalizationSyncService,
    sharedMembershipFeature,
    sharedSyncExperienceProviderActivation,
    sharedSyncExperienceAutomaticRuntime,
    sharedSyncRemoteStatusCoordinator
  );
const sharedSyncExperienceAdvancedOperations: SyncExperienceAdvancedOperations =
  new SyncExperienceAdvancedOperations(
    sharedSyncService,
    sharedSyncRemoteStatusCoordinator,
    sharedAiraLocalBookmarkOverviewCacheRepository,
    sharedSyncExperienceProviderOperations
  );
export const sharedSyncExperienceCoordinator: SyncExperienceCoordinator =
  new SyncExperienceCoordinator(
    sharedSyncService,
    sharedAiraSyncConfigStore,
    sharedPersonalizationSyncConfigStore,
    sharedSyncExperienceStateStore,
    sharedSyncExperienceProviderOperations,
    sharedSyncPersonalizationDomain,
    sharedSyncBookmarkDomain,
    sharedHistorySyncService,
    sharedSyncExperienceAutomaticRuntime,
    sharedSyncExperienceAdvancedOperations,
    sharedMembershipFeature,
    sharedHuaweiSpaceBookmarkUpgradeStore
  );
export const sharedLocalBackupCoordinator: LocalBackupCoordinator = new LocalBackupCoordinator(
  new LocalBackupService(
    sharedSyncService,
    sharedPersonalizationSyncService,
    sharedHistoryRepository,
    new HistoryFeature(
      sharedHistoryRepository,
      sharedPreferencesRepository,
      sharedRecentlyClosedTabRepository
    ),
    sharedUserScriptRepository,
    sharedUserScriptPackageLifecycleCoordinator,
    sharedUserScriptValueStateStore
  ),
  sharedSyncExperienceCoordinator
);
export const sharedHuaweiAccountMutationCoordinator: HuaweiAccountMutationCoordinator =
  new HuaweiAccountMutationCoordinator(
    sharedSyncExperienceCoordinator,
    sharedAccountIdentityChangeCoordinator,
    sharedMembershipFeature
  );
sharedSearchEngineRepository.setLocalChangeHandler(() => {
  sharedSyncExperienceCoordinator.notifyPersonalizationLocalSettingsChanged();
});
sharedSearchEngineRepository.setDefaultSearchEngineChangeHandler((engineId) => {
  sharedDesktopCardSearchEngineService.refreshRegisteredForms(engineId);
});
sharedHomePagePresentationSettingsRepository.setLocalChangeHandler(() => {
  sharedSyncExperienceCoordinator.notifyPersonalizationLocalSettingsChanged();
});
sharedCustomHomepageRepository.setLocalChangeHandler(() => {
  sharedSyncExperienceCoordinator.notifyPersonalizationLocalSettingsChanged();
});
sharedWallpaperRepository.setLocalChangeHandler(() => {
  sharedSyncExperienceCoordinator.notifyPersonalizationLocalSettingsChanged();
});
sharedShortcutRepository.setLocalChangeHandler(() => {
  sharedSyncExperienceCoordinator.notifyHomeShortcutsChanged();
});
sharedNovelLibraryRepository.setChangeHandler((origin) => {
  if (origin === 'local') {
    sharedSyncExperienceCoordinator.notifyPersonalizationLocalSettingsChanged();
  }
});
sharedNovelReadingCheckpointRepository.setChangeHandler((origin) => {
  if (origin === 'local') {
    sharedSyncExperienceCoordinator.notifyPersonalizationLocalSettingsChanged();
  }
});
sharedMembershipFeature.setStateChangeHandler((state) => {
  void sharedCrossDeviceTabPresenceCoordinator.reconcileMembershipState(state);
  sharedSyncExperienceCoordinator.notifyMembershipStateChanged();
});
let runtimeInitializationPromise: Promise<void> | undefined = undefined;
let runtimeIdleWarmupPromise: Promise<void> | undefined = undefined;
let runtimeIdleWarmupTimer: number = -1;
let firstPaintReadinessPromise: Promise<void> | undefined = undefined;
let launchReadinessPromise: Promise<void> | undefined = undefined;
let deferredRuntimeWarmupPromise: Promise<void> | undefined = undefined;
let deferredRuntimeWarmupTimer: number = -1;
let bookmarkRuntimeWarmupPromise: Promise<void> | undefined = undefined;
let bookmarkRuntimeWarmupTimer: number = -1;
let searchEngineFallbackWarmupTimer: number = -1;
let searchEngineFallbackNetworkMonitoringStarted: boolean = false;
let deferredBrowserRepositoryWarmupPromise: Promise<void> | undefined = undefined;
let deferredBrowserRepositoryWarmupTimer: number = -1;
let browserThemePreferenceSubscriptionAttached: boolean = false;
let browserExperimentPreferenceSubscriptionAttached: boolean = false;
let downloadPreferenceSubscriptionAttached: boolean = false;

export function initializeBrowserAppFirstPaintReadiness(abilityContext: common.UIAbilityContext): Promise<void> {
  const applicationContext = abilityContext.getApplicationContext();
  AppRuntimeContext.setApplicationContext(applicationContext);
  sharedDesktopCardSearchEngineService.bindApplicationContext(applicationContext);
  sharedDesktopCardSearchEngineService.reconcileRunningForms();
  sharedAppCrashDiagnosticsService.initialize(abilityContext);

  if (firstPaintReadinessPromise === undefined) {
    firstPaintReadinessPromise = measureStartupStep('first_paint_readiness_total', () =>
      sharedPreferencesRepository.initialize()
      .then(() => {
        const readinessTasks: Promise<void>[] = [
          measureStartupStep('home_page_presentation_settings_repository', () =>
            sharedHomePagePresentationSettingsRepository.initialize().then((): void => undefined)),
          measureStartupStep('user_script_first_paint_repositories', () =>
            sharedUserScriptRuntimeReadinessCoordinator.initializeExecutionState()),
          measureStartupStep('browser_experiment_migrations', () =>
            sharedBrowserExperimentMigrationCoordinator.enableDefaultWebVideoTakeoverIfNeeded().then((result): void => {
              hilog.info(
                DOMAIN,
                TAG,
                'Browser experiment migration video_takeover_default applied=%{public}s reason=%{public}s.',
                result.applied ? 'true' : 'false',
                result.reason
              );
            })),
          measureStartupStep('startup_intro_repository', () =>
            sharedStartupWelcomeIntroRepository.initialize().then((): void => undefined)),
          measureStartupStep('gesture_onboarding_repository', () =>
            sharedGestureOnboardingPromptRepository.initialize().then((): void => undefined)),
          measureStartupStep('aira_sync_config_store', () =>
            sharedAiraSyncConfigStore.initialize().then((): void => undefined))
            .then(() => measureStartupStep('novel_bookshelf_sync_state_store', () =>
              sharedPersonalizationSyncService.initializeNovelBookshelfSelection().then((): void => undefined))),
          measureStartupStep('membership_repository', () =>
            sharedMembershipFeature.loadState().then((): void => undefined)),
          measureStartupStep('personalization_sync_config_store', () =>
            sharedPersonalizationSyncConfigStore.initialize().then((): void => undefined))
        ];
        return Promise.all(readinessTasks).then((): void => undefined);
      })
      .then(() => {
        sharedSyncExperienceCoordinator.bindPreferenceChanges(sharedPreferencesRepository);
        sharedBrowserThemeModeCoordinator.applyThemeMode(sharedPreferencesRepository.getPreferences().themeMode);
        syncBrowserThemeAppStorage();
        if (!browserThemePreferenceSubscriptionAttached) {
          browserThemePreferenceSubscriptionAttached = true;
          sharedPreferencesRepository.subscribe((_preferences, scope) => {
            if (isBrowserThemePresentationScope(scope)) {
              syncBrowserThemeAppStorage();
            }
          });
        }
        sharedDownloadV2Service.setCellularDownloadsAllowed(
          sharedPreferencesRepository.getPreferences().downloads.allowCellularDownloads,
          false
        );
        if (!downloadPreferenceSubscriptionAttached) {
          downloadPreferenceSubscriptionAttached = true;
          sharedPreferencesRepository.subscribe((preferences, scope) => {
            if (scope === 'downloads') {
              sharedDownloadV2Service.setCellularDownloadsAllowed(
                preferences.downloads.allowCellularDownloads
              );
            }
          });
        }
      })
      .then(() => sharedArkWebAppProxyService.applyFromExperimentSettings(
        sharedPreferencesRepository.getPreferences().experiments
      ))
      .then(() => {
        if (!browserExperimentPreferenceSubscriptionAttached) {
          browserExperimentPreferenceSubscriptionAttached = true;
          sharedPreferencesRepository.subscribe((preferences, scope) => {
            if (scope === 'experiments') {
              sharedSearchEngineRoutingService.invalidateAvailabilityCache();
              scheduleSearchEngineFallbackWarmup();
              sharedArkWebAppProxyService.applyFromExperimentSettings(preferences.experiments)
                .then(() => {})
                .catch((error: Error) => {
                  hilog.warn(DOMAIN, TAG, 'ArkWeb proxy preference sync failed: %{public}s', JSON.stringify(error));
                });
            }
          });
        }
      })
      .then(() => measureStartupStep('external_app_search_preferences_repository', () =>
        sharedExternalAppSearchPreferencesRepository.initialize().then(() => undefined)))
      .then(() => measureStartupStep('quick_search_switch_preferences_repository', () =>
        sharedQuickSearchSwitchPreferencesRepository.initialize().then(() => undefined)))
      .then(() => measureStartupStep('search_engine_repository', () =>
        sharedSearchEngineRepository.initialize(sharedPreferencesRepository.getPreferences().searchEngineId)))
      .then(() => sharedPreferencesRepository.updateSearchSuggestionPreferences(
        sharedSearchEngineRepository.getSettings().searchSuggestions
      ))
      .then(() => {
        hilog.info(DOMAIN, TAG, 'Browser first paint readiness initialized.');
      }))
      .catch((error: Error) => {
        firstPaintReadinessPromise = undefined;
        hilog.error(DOMAIN, TAG, 'Browser first paint readiness init failed: %{public}s', JSON.stringify(error));
        throw new Error('Browser first paint readiness initialization failed.');
      });
  }

  return firstPaintReadinessPromise;
}

export function initializeBrowserAppLaunchReadiness(abilityContext: common.UIAbilityContext): Promise<void> {
  const applicationContext = abilityContext.getApplicationContext();
  AppRuntimeContext.setApplicationContext(applicationContext);
  sharedAppCrashDiagnosticsService.initialize(abilityContext);

  if (launchReadinessPromise === undefined) {
    launchReadinessPromise = measureStartupStep('launch_readiness_total', () =>
      initializeBrowserAppFirstPaintReadiness(abilityContext)
      .then(() => {
        const repositoryTasks: Promise<void>[] = [
          measureStartupStep('tablet_interface_mode_repository', () =>
            sharedBrowserTabletInterfaceModeRepository.initialize().then(() => undefined)),
          measureStartupStep('secure_dns_settings', () =>
            sharedSecureDnsSettingsCoordinator.initializeAndApply()
              .then((result): void => {
                if (result.applyResult.applied) {
                  hilog.info(DOMAIN, TAG, '%{public}s', result.applyResult.message);
                } else {
                  hilog.warn(DOMAIN, TAG, '%{public}s', result.applyResult.message);
                }
              })
              .catch((error: Error): void => {
                hilog.warn(DOMAIN, TAG, 'Secure DNS startup configuration skipped: %{public}s', JSON.stringify(error));
              })),
          measureStartupStep('browser_web_security_settings_repository', () =>
            sharedBrowserWebSecuritySettingsRepository.initialize().then(() => undefined)),
          measureStartupStep('browser_user_agent_repository', () =>
            sharedBrowserUserAgentSettingsRepository.initialize().then((settings) => {
              const policyResult =
                sharedBrowserUserAgentHostPolicyService.applyApplicationUserAgentForSettings(settings);
              if (!policyResult.applied) {
                hilog.warn(DOMAIN, TAG, '%{public}s', policyResult.message);
              }
              return undefined;
            })),
          measureStartupStep('browser_site_privacy_repository', () =>
            sharedBrowserSitePrivacyRuleRepository.initialize()),
          measureStartupStep('saved_site_setting_repository', () =>
            sharedSavedSiteSettingRepository.initialize()),
          measureStartupStep('custom_homepage_repository', () =>
            sharedCustomHomepageRepository.initialize().then(() => undefined)),
          measureStartupStep('shortcut_repository', () =>
            sharedShortcutRepository.initialize().then(() => undefined))
        ];
        return Promise.all(repositoryTasks).then((): void => undefined);
      })
      .then(() => measureStartupStep('retire_legacy_site_rules', async () => {
        if (sharedBrowserMigrationRepository.hasCompleted(SITE_SETTING_LEGACY_RETIREMENT_MIGRATION_ID)) {
          return;
        }
        await new SiteCustomizationManagementCoordinator(
          sharedPreferencesRepository,
          sharedBrowserUserAgentSettingsRepository,
          sharedBrowserSitePrivacyRuleRepository,
          sharedSitePolicyService,
          sharedSavedSiteSettingRepository
        ).retireLegacySingleSiteRules();
        await sharedBrowserMigrationRepository.markCompleted(SITE_SETTING_LEGACY_RETIREMENT_MIGRATION_ID);
      }))
      .then(() => measureStartupStep('home_page_recovery_entry_guard', () =>
        new HomePageSettingsCoordinator(
          sharedPreferencesRepository,
          sharedCustomHomepageRepository,
          sharedHomePagePresentationSettingsRepository
        ).ensureRecoveryEntryAvailable()))
      .then(() => {
        hilog.info(DOMAIN, TAG, 'Browser launch readiness initialized.');
      }))
      .catch((error: Error) => {
        launchReadinessPromise = undefined;
        hilog.error(DOMAIN, TAG, 'Browser launch readiness init failed: %{public}s', JSON.stringify(error));
        throw new Error('Browser launch readiness initialization failed.');
      });
  }

  return launchReadinessPromise;
}

export function initializeBrowserAppRuntime(abilityContext: common.UIAbilityContext): Promise<void> {
  const applicationContext = abilityContext.getApplicationContext();
  AppRuntimeContext.setApplicationContext(applicationContext);

  if (runtimeInitializationPromise === undefined) {
    runtimeInitializationPromise = measureStartupStep('runtime_core_total', () =>
      initializeBrowserAppLaunchReadiness(abilityContext)
      .then(() => {
        scheduleRuntimeIdleWarmup();
        hilog.info(
          DOMAIN,
          TAG,
          'Browser runtime idle warmup scheduled after %{public}dms.',
          RUNTIME_IDLE_WARMUP_START_DELAY_MS
        );
        hilog.info(DOMAIN, TAG, 'Browser runtime initialized.');
      }))
      .catch((error: Error) => {
        runtimeInitializationPromise = undefined;
        hilog.error(DOMAIN, TAG, 'Browser runtime init failed: %{public}s', JSON.stringify(error));
        throw new Error('Browser runtime initialization failed.');
      });
  }

  return runtimeInitializationPromise;
}

function buildBrowserRuntimeIdleWarmupTasks(): BrowserRuntimeIdleWarmupTask[] {
  return [{
    id: 'app_review_prompt_runtime',
    run: () => initializeAppReviewPromptRuntimeSafely()
  }, {
    id: 'release_notice_runtime',
    run: () => initializeReleaseNoticeRuntimeSafely()
  }, {
    id: 'settings_notice_repository',
    run: () => sharedSettingsNoticeDismissalRepository.initialize().then(() => undefined)
  }, {
    id: 'manual_element_hide_repository',
    run: () => sharedManualElementHideRepository.initialize().then(() => undefined)
  }, {
    id: 'password_settings_repository',
    run: () => sharedPasswordSettingsRepository.initialize().then(() => undefined)
  }, {
    id: 'browser_security_metrics_repository',
    run: () => sharedBrowserSecurityReportMetricsRepository.initialize().then(() => undefined)
  }, {
    id: 'wallpaper_repository',
    run: () => sharedWallpaperRepository.initialize().then(() => undefined)
  }, {
    id: 'activity_repository',
    run: () => sharedActivityRepository.initialize().then(() => undefined)
  }, {
    id: 'history_repository',
    run: () => sharedHistoryRepository.initialize()
  }, {
    id: 'sync_experience_history_account_lifecycle',
    run: () => sharedSyncExperienceCoordinator.reconcileHistoryAccountLifecycle().then(() => undefined)
  }, {
    id: 'recently_closed_repository',
    run: () => sharedRecentlyClosedTabRepository.initialize()
  }, {
    id: 'tab_session_repository',
    run: () => sharedTabSessionRepository.initialize()
  }, {
    id: 'offline_page_repository',
    run: () => sharedOfflinePageRepository.initialize()
  }];
}

function scheduleRuntimeIdleWarmup(): void {
  if (runtimeIdleWarmupPromise !== undefined || runtimeIdleWarmupTimer >= 0) {
    return;
  }
  runtimeIdleWarmupTimer = setTimeout(() => {
    runtimeIdleWarmupTimer = -1;
    runtimeIdleWarmupPromise = measureStartupStep('runtime_idle_core_total', () =>
      runRuntimeIdleWarmupTasks(buildBrowserRuntimeIdleWarmupTasks()))
      .then(() => {
        startSearchEngineFallbackNetworkMonitoring();
        scheduleSearchEngineFallbackWarmup();
        scheduleDeferredRuntimeWarmup();
      })
      .catch((error: Error) => {
        runtimeIdleWarmupPromise = undefined;
        hilog.warn(DOMAIN, TAG, 'Browser runtime idle warmup skipped: %{public}s', JSON.stringify(error));
      });
  }, RUNTIME_IDLE_WARMUP_START_DELAY_MS);
}

function runRuntimeIdleWarmupTasks(
  tasks: BrowserRuntimeIdleWarmupTask[],
  index: number = 0,
  taskGapMs: number = RUNTIME_IDLE_WARMUP_TASK_GAP_MS
): Promise<void> {
  if (index >= tasks.length) {
    return Promise.resolve();
  }
  const task = tasks[index];
  return measureStartupStepSafely(task.id, task.run)
    .then(() => {
      const nextIndex = index + 1;
      if (nextIndex >= tasks.length) {
        return Promise.resolve();
      }
      return waitForRuntimeIdleWarmupDelay(taskGapMs)
        .then(() => runRuntimeIdleWarmupTasks(tasks, nextIndex, taskGapMs));
    });
}

function waitForRuntimeIdleWarmupDelay(delayMs: number): Promise<void> {
  const normalizedDelayMs = Math.max(0, Math.floor(delayMs));
  if (normalizedDelayMs <= 0) {
    return Promise.resolve();
  }
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, normalizedDelayMs);
  });
}

function scheduleDeferredRuntimeWarmup(): void {
  if (deferredRuntimeWarmupPromise !== undefined || deferredRuntimeWarmupTimer >= 0) {
    return;
  }
  deferredRuntimeWarmupTimer = setTimeout(() => {
    deferredRuntimeWarmupTimer = -1;
    void warmUpDeferredBrowserRuntime();
  }, DEFERRED_RUNTIME_WARMUP_DELAY_MS);
}

function warmUpDeferredBrowserRuntime(): Promise<void> {
  if (deferredRuntimeWarmupPromise === undefined) {
    deferredRuntimeWarmupPromise = measureStartupStep('runtime_deferred_total', () =>
      runRuntimeIdleWarmupTasks(buildDeferredRuntimeWarmupTasks(), 0, DEFERRED_RUNTIME_WARMUP_TASK_GAP_MS)
      .then(() => {
        scheduleBookmarkRuntimeWarmup();
        sharedSyncExperienceCoordinator.markSyncRepositoriesReady();
        scheduleDeferredBrowserRepositoryWarmup();
        scheduleBrowserRuntimeMaintenance();
        hilog.info(DOMAIN, TAG, 'Browser deferred runtime initialized.');
      }))
      .catch((error: Error) => {
        deferredRuntimeWarmupPromise = undefined;
        hilog.warn(DOMAIN, TAG, 'Browser deferred runtime init skipped: %{public}s', JSON.stringify(error));
      });
  }
  return deferredRuntimeWarmupPromise;
}

function buildDeferredRuntimeWarmupTasks(): BrowserRuntimeIdleWarmupTask[] {
  return [{
    id: 'user_script_runtime_state_repository',
    run: () => sharedUserScriptRuntimeReadinessCoordinator.initializeDiagnostics()
  }, {
    id: 'translation_settings_repository',
    run: () => sharedTranslationSettingsRepository.initialize().then(() => undefined)
  }, {
    id: 'translation_secret_migration',
    run: () => sharedTranslationProviderSecretService.migratePlaintextSecrets(sharedTranslationSettingsRepository)
  }, {
    id: 'membership_runtime_reconcile',
    run: () => sharedMembershipFeature.loadState()
      .then(async (state): Promise<void> => {
        await sharedCrossDeviceTabPresenceCoordinator.reconcileMembershipState(state);
      })
  }, {
    id: 'download_runtime_repository',
    run: () => sharedDownloadRuntimeService.initializeRepository()
  }];
}

function scheduleBookmarkRuntimeWarmup(): void {
  if (bookmarkRuntimeWarmupPromise !== undefined || bookmarkRuntimeWarmupTimer >= 0) {
    return;
  }
  bookmarkRuntimeWarmupTimer = setTimeout(() => {
    bookmarkRuntimeWarmupTimer = -1;
    void warmUpBrowserBookmarkRuntime();
  }, BOOKMARK_RUNTIME_WARMUP_DELAY_MS);
}

function scheduleSearchEngineFallbackWarmup(delayMs: number = SEARCH_ENGINE_FALLBACK_WARMUP_DELAY_MS): void {
  if (searchEngineFallbackWarmupTimer >= 0) {
    return;
  }
  searchEngineFallbackWarmupTimer = setTimeout(() => {
    searchEngineFallbackWarmupTimer = -1;
    void warmUpSearchEngineFallbackProbe();
  }, Math.max(0, Math.floor(delayMs)));
}

function startSearchEngineFallbackNetworkMonitoring(): void {
  if (searchEngineFallbackNetworkMonitoringStarted) {
    return;
  }
  searchEngineFallbackNetworkMonitoringStarted = true;
  sharedSearchEngineFallbackNetworkAvailabilityService.start((snapshot: WebNetworkAvailabilitySnapshot): void => {
    sharedSearchEngineRoutingService.invalidateAvailabilityCache();
    if (snapshot.reliable && snapshot.available) {
      scheduleSearchEngineFallbackWarmup(900);
    }
  });
}

async function warmUpSearchEngineFallbackProbe(): Promise<void> {
  try {
    const settings = sharedSearchEngineRepository.getSettings();
    if (!settings.fallbackSearch.enabled) {
      return;
    }
    const engines = sharedSearchEngineRepository.listEngines();
    const primary = engines.find((engine: SearchEngineRecord): boolean => engine.id === settings.defaultSearchEngineId);
    const fallback = engines.find((engine: SearchEngineRecord): boolean => {
      return engine.id === settings.fallbackSearch.fallbackSearchEngineId;
    });
    if (primary === undefined || fallback === undefined || primary.id === fallback.id) {
      return;
    }
    await sharedSearchEngineAvailabilityProbeService.resolveAvailability({
      engine: primary,
      experiments: sharedPreferencesRepository.getPreferences().experiments,
      maxWaitMs: 1800
    });
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'Search engine fallback warmup skipped: %{public}s', JSON.stringify(error));
  }
}

function warmUpBrowserBookmarkRuntime(): Promise<void> {
  if (bookmarkRuntimeWarmupPromise === undefined) {
    bookmarkRuntimeWarmupPromise = measureStartupStep('bookmark_runtime_warmup', () =>
      runRuntimeIdleWarmupTasks(buildBookmarkRuntimeWarmupTasks(), 0, BOOKMARK_RUNTIME_WARMUP_TASK_GAP_MS))
      .then(() => {
        hilog.info(DOMAIN, TAG, 'Bookmark runtime warmup initialized.');
      })
      .catch((error: Error) => {
        bookmarkRuntimeWarmupPromise = undefined;
        hilog.warn(DOMAIN, TAG, 'Bookmark runtime warmup skipped: %{public}s', JSON.stringify(error));
      });
  }
  return bookmarkRuntimeWarmupPromise;
}

function buildBookmarkRuntimeWarmupTasks(): BrowserRuntimeIdleWarmupTask[] {
  return [{
    id: 'bookmark_folder_regular_options',
    run: () => sharedBookmarkFolderSelectionPreparationCoordinator.prepare('regular', true).then(() => undefined)
  }, {
    id: 'bookmark_folder_private_options',
    run: () => sharedBookmarkFolderSelectionPreparationCoordinator.prepare('private', true).then(() => undefined)
  }];
}

function scheduleDeferredBrowserRepositoryWarmup(): void {
  if (deferredBrowserRepositoryWarmupPromise !== undefined || deferredBrowserRepositoryWarmupTimer >= 0) {
    return;
  }
  deferredBrowserRepositoryWarmupTimer = setTimeout(() => {
    deferredBrowserRepositoryWarmupTimer = -1;
    void warmUpDeferredBrowserRepositories();
  }, DEFERRED_BROWSER_REPOSITORY_WARMUP_DELAY_MS);
}

function warmUpDeferredBrowserRepositories(): Promise<void> {
  if (deferredBrowserRepositoryWarmupPromise === undefined) {
    deferredBrowserRepositoryWarmupPromise = runRuntimeIdleWarmupTasks(
      buildDeferredBrowserRepositoryWarmupTasks(),
      0,
      DEFERRED_BROWSER_REPOSITORY_WARMUP_TASK_GAP_MS
    )
      .catch((error: Error) => {
        deferredBrowserRepositoryWarmupPromise = undefined;
        hilog.warn(DOMAIN, TAG, 'Deferred browser repository warmup skipped: %{public}s', JSON.stringify(error));
      });
  }
  return deferredBrowserRepositoryWarmupPromise;
}

function buildDeferredBrowserRepositoryWarmupTasks(): BrowserRuntimeIdleWarmupTask[] {
  return [{
    id: 'bookmark_folder_count_cache',
    run: () => sharedBookmarkFolderCountCacheRepository.initialize().then(() => undefined)
  }, {
    id: 'aira_local_bookmark_overview_cache',
    run: () => sharedAiraLocalBookmarkOverviewCacheRepository.initialize().then(() => undefined)
  }];
}

function measureStartupStep<T>(name: string, task: () => Promise<T>): Promise<T> {
  const startedAt = Date.now();
  return task()
    .then((result: T) => {
      hilog.info(DOMAIN, TAG, 'Startup step %{public}s completed in %{public}dms.', name, Date.now() - startedAt);
      return result;
    })
    .catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'Startup step %{public}s failed after %{public}dms: %{public}s',
        name,
        Date.now() - startedAt,
        JSON.stringify(error));
      throw error;
    });
}

function measureStartupStepSafely<T>(name: string, task: () => Promise<T>): Promise<void> {
  return measureStartupStep(name, task)
    .then(() => undefined)
    .catch((_error: Error) => undefined);
}

function refreshMembershipStateAfterLaunch(): Promise<void> {
  return sharedMembershipFeature.refreshState({ loadSyncConfig: false })
    .then(async (state): Promise<void> => {
      await sharedCrossDeviceTabPresenceCoordinator.reconcileMembershipState(state);
      hilog.info(DOMAIN, TAG, 'Membership launch refresh completed: %{public}s', state.plan);
      sharedSyncExperienceCoordinator.runPendingBookmarksOnForeground();
    })
    .catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'Membership launch refresh skipped: %{public}s', JSON.stringify(error));
    });
}

function scheduleBrowserRuntimeMaintenance(): void {
  sharedBrowserRuntimeMaintenanceCoordinator.schedule(buildBrowserRuntimeMaintenanceTasks(),
    RUNTIME_MAINTENANCE_START_DELAY_MS,
    RUNTIME_MAINTENANCE_TASK_GAP_MS);
}

function buildBrowserRuntimeMaintenanceTasks(): BrowserRuntimeMaintenanceTask[] {
  return [{
    id: 'adblock_remote_source_update',
    run: () => measureStartupStepSafely('maintenance_adblock_remote_source_update', async () => {
      const result = await sharedAdBlockRuleSourceCoordinator.autoUpdateDueRemoteSources();
      if (result === undefined) {
        hilog.info(DOMAIN, TAG, 'Adblock rule source maintenance skipped: no due source.');
      }
    })
  }, {
    id: 'membership_refresh',
    run: () => refreshMembershipStateAfterLaunch()
  }, {
    id: 'download_restore',
    run: () => measureStartupStepSafely('maintenance_download_v2_reconnect_tasks', () => {
      if (!sharedPreferencesRepository.getPreferences().downloads.autoResumeAfterRestart) {
        hilog.info(DOMAIN, TAG, 'Download startup reconnect skipped by user setting.');
        return Promise.resolve();
      }
      return sharedDownloadV2Service.reconnectPersistedActiveTasks();
    })
  }];
}

async function initializeAppReviewPromptRuntimeSafely(): Promise<void> {
  try {
    await sharedAppReviewPromptRepository.initialize();
    await sharedAppReviewPromptRepository.recordLaunch();
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'App review prompt init skipped: %{public}s', JSON.stringify(error));
  }
}

async function initializeReleaseNoticeRuntimeSafely(): Promise<void> {
  try {
    await sharedReleaseNoticeCoordinator.initializeForCurrentVersion();
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'Release notice init skipped: %{public}s', JSON.stringify(error));
  }
}

export function getBrowserAppRuntimeInitializationPromise(): Promise<void> | undefined {
  return runtimeInitializationPromise;
}

export function restoreArkWebAppProxyAfterForeground(): void {
  const experiments = sharedPreferencesRepository.getPreferences().experiments;
  sharedArkWebAppProxyService.forceApplyFromExperimentSettings(experiments)
    .then((result) => {
      hilog.info(
        DOMAIN,
        TAG,
        'ArkWeb proxy foreground restore completed status=%{public}s rule=%{public}s',
        result.status,
        result.proxyRule
      );
      sharedSearchEngineRoutingService.invalidateAvailabilityCache();
      scheduleSearchEngineFallbackWarmup(1200);
    })
    .catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'ArkWeb proxy foreground restore failed: %{public}s', JSON.stringify(error));
    });
}

export function syncBrowserThemeAppStorage(): void {
  const preferences = sharedPreferencesRepository.getPreferences();
  const theme = sharedBrowserThemeViewStateFactory.build(preferences);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY, theme.pageBackground);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY, theme.surfaceBackground);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY, theme.floatingSurface);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY, theme.controlBackground);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_ACCENT_KEY, theme.accent);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_ON_ACCENT_KEY, theme.onAccent);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY, theme.onPrimary);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY, theme.resolvedMode);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY, theme.settingsIconForeground);
  AppStorage.setOrCreate(
    BROWSER_THEME_STORAGE_APP_PROXY_ACTIVE_BACKGROUND_KEY,
    theme.settingsIconBackgrounds.experiments
  );
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY, theme.pressedBackground);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_DIVIDER_KEY, theme.divider);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_OUTLINE_KEY, theme.outline);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY, theme.textPrimary);
  AppStorage.setOrCreate(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY, theme.textSecondary);
  AppStorage.setOrCreate(
    BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY,
    preferences.appearance.homeShortcutIconSizeRatio
  );
  AppStorage.setOrCreate(
    BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
    preferences.appearance.siteIconCornerRadiusRatio
  );
  AppStorage.setOrCreate(
    BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_LAYOUT_STYLE_KEY,
    preferences.appearance.tabsOverviewLayoutStyle
  );
  AppStorage.setOrCreate(
    BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_CLOSE_BUTTON_ALWAYS_VISIBLE_KEY,
    preferences.appearance.tabsOverviewCloseButtonAlwaysVisible
  );
  AppStorage.setOrCreate(
    BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBLE_KEY,
    preferences.appearance.showDesktopBookmarkBar !== false
  );
}

export function refreshBrowserThemeForSystemConfigurationChange(
  colorMode?: ConfigurationConstant.ColorMode
): void {
  if (sharedPreferencesRepository.getPreferences().themeMode !== 'system') {
    return;
  }
  sharedBrowserThemeModeCoordinator.syncSystemColorMode(colorMode ?? AppRuntimeContext.getUIAbilityContext().config.colorMode);
  syncBrowserThemeAppStorage();
  sharedPreferencesRepository.notifyThemeModePresentationChanged();
}
