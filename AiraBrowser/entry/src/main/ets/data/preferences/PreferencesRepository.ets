import {
  BrowserDownloadAutoClearPolicy,
  BrowserHlsSegmentConcurrency,
  BrowserPrivateDownloadFilePolicy,
  BrowserPrivateDownloadRecordPolicy,
  BrowserDownloadLocation,
  BrowserDownloadSettings,
  BrowserToolbarLayoutSettings,
  BrowserAppServiceMode,
  BrowserAppearanceSettings,
  BrowserBottomToolbarScrollBehavior,
  BrowserHomeShortcutLayoutDensity,
  BrowserGeneralSettings,
  BrowserCookiePolicySettings,
  BrowserPrivateTabRestorePolicy,
  BrowserStartupRestorePolicy,
  BrowserAppProxyProfile,
  BrowserAppProxyScheme,
  BrowserAppProxySettings,
  BrowserExperimentSettings,
  BrowserProfileId,
  BrowserTabAutoClosePolicy,
  BrowserDeviceTierHint,
  BrowserThemePaletteId,
  BrowserPreferences,
  ExternalNavigationAppOpenPolicy,
  ExternalNavigationSettings,
  ExternalNavigationSiteRule,
  ReaderModeLineHeight,
  ReaderModeBrightnessMode,
  ReaderModePageWidth,
  ReaderModePreferences,
  ReaderModeTheme,
  ReadingPageMode,
  BrowserRetentionProfileId,
  BrowserRetentionSettings,
  HistoryRetentionSettings,
  BrowserThemeMode,
  BrowserTabsOverviewLayoutStyle,
  DEFAULT_BROWSER_PROFILE_ID,
  DEFAULT_SEARCH_ENGINE_ID,
  SEARCH_ENGINE_OPTIONS,
  SearchEngineId,
  SearchEngineOption,
  SearchSuggestionPreferences,
  SitePermissionDefaultSettings,
  SitePermissionKind,
  SitePermissionRule,
  SitePermissionSettings,
  normalizeBrowserProfileId
} from '../../common/models/BrowserModels';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DEFAULT_BROWSER_THEME_PALETTE_ID } from '../../features/theme/BrowserThemePalettes';
import { SiteIdentityService } from '../../services/web/SiteIdentityService';

const PREFERENCES_LOG_DOMAIN: number = 0x0000;
const PREFERENCES_LOG_TAG: string = 'PreferencesRepository';

export const DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS: BrowserToolbarLayoutSettings = {
  primaryActionIds: [
    'history',
    'openBookmarks',
    'novel',
    'sendToDesktop',
    'settings',
    'appProxySettings',
    'home',
    'newPrivateTab',
    'scanQr',
    'scripts',
    'video',
    'downloads',
    'bookmark',
    'copyLink',
    'share',
    'print',
    'userAgent',
    'textZoom',
    'find',
    'fullScreenMode',
    'manualElementHide',
    'elementInspection',
    'reader',
    'translate',
    'themeMode',
    'screenOrientation',
    'addToDesktop',
    'offline',
    'siteInfo',
    'reportSite',
    'savedPages'
  ],
  secondaryActionIds: [],
  leadingSlotActionId: '',
  menuSlotActionId: '',
  refreshSlotActionId: '',
  tabsSlotActionId: '',
  leadingSlotLongPressActionId: 'none',
  menuSlotLongPressActionId: 'none',
  refreshSlotLongPressActionId: 'none',
  tabsSlotLongPressActionId: 'none',
  leadingSlotSwipeUpActionId: 'home',
  tabsSlotSwipeUpActionId: 'home',
  updatedAt: 0
};

const BROWSER_TOOLBAR_CONFIGURABLE_ACTION_IDS: string[] = [
  'bookmark',
  'scanQr',
  'copyLink',
  'share',
  'sendToDesktop',
  'print',
  'userAgent',
  'textZoom',
  'find',
  'fullScreenMode',
  'manualElementHide',
  'elementInspection',
  'reader',
  'novel',
  'translate',
  'scripts',
  'themeMode',
  'screenOrientation',
  'addToDesktop',
  'offline',
  'video',
  'siteInfo',
  'reportSite',
  'openBookmarks',
  'history',
  'savedPages',
  'downloads',
  'settings',
  'appProxySettings',
  'newPrivateTab',
  'home'
];

const BROWSER_TOOLBAR_CORE_ACTION_IDS: string[] = [
  'webBack',
  'webForward',
  'bottomChromeMenu',
  'webReload',
  'openTabs',
  'newTab'
];

export const HUAWEI_BROWSER_PHONE_NORMAL_RUNTIME_TAB_LIMIT: number = 15;
export const HUAWEI_BROWSER_PHONE_MEMORY_PRESSURE_RUNTIME_TAB_LIMIT: number = 8;
export const HUAWEI_BROWSER_PHONE_CRITICAL_RUNTIME_TAB_LIMIT: number = 3;
export const HUAWEI_BROWSER_NON_MOBILE_NORMAL_RUNTIME_TAB_LIMIT: number = 30;
export const HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS: number = 24 * 60 * 60 * 1000;

export const DEFAULT_BROWSER_RETENTION_SETTINGS: BrowserRetentionSettings = {
  profileId: 'balanced',
  deviceTierHint: 'auto',
  maxMountedRuntimeTabs: HUAWEI_BROWSER_PHONE_NORMAL_RUNTIME_TAB_LIMIT,
  maxHotBackgroundTabs: 5,
  maxWarmBackgroundTabs: 10,
  hotBackgroundMaxAgeMs: 30 * 60 * 1000,
  warmBackgroundMaxAgeMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS,
  staleAfterMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS
};

export const DEFAULT_HISTORY_RETENTION_SETTINGS: HistoryRetentionSettings = {
  enabled: true,
  maxAgeDays: 90,
  maxRows: 10000
};

export const HISTORY_RETENTION_MIN_DAYS: number = 1;
export const HISTORY_RETENTION_MAX_DAYS: number = DEFAULT_HISTORY_RETENTION_SETTINGS.maxAgeDays;
export const HISTORY_RETENTION_MIN_ROWS: number = 100;
export const HISTORY_RETENTION_MAX_ROWS: number = 50000;

export const DEFAULT_BROWSER_DOWNLOAD_SETTINGS: BrowserDownloadSettings = {
  defaultLocation: 'system_downloads',
  askBeforeDownload: true,
  allowCellularDownloads: true,
  autoResumeAfterRestart: true,
  hlsSegmentConcurrency: '8',
  autoClearPolicy: 'manual',
  privateFilePolicy: 'prompt_for_location',
  privateRecordPolicy: 'keep_until_window_close'
};

export const DEFAULT_READER_MODE_PREFERENCES: ReaderModePreferences = {
  fontSize: 18,
  theme: 'system',
  lineHeight: 'comfortable',
  pageWidth: 'wide',
  brightnessMode: 'system',
  brightnessPercent: 60,
  pageMode: 'vertical'
};

export const DEFAULT_BROWSER_APPEARANCE_SETTINGS: BrowserAppearanceSettings = {
  bottomToolbarScrollBehavior: 'compact',
  globalImmersionEnabled: false,
  alwaysTopImmersionEnabled: false,
  forceDarkWebContentEnabled: true,
  blurPrivateTabPreviews: true,
  showHomeRecentlyClosed: true,
  showHomeShortcuts: true,
  homeRecentlyClosedLimit: 8,
  homeShortcutLayoutDensity: 'standard',
  homeShortcutIconSizeRatio: 0.54,
  siteIconCornerRadiusRatio: 0.3,
  themePaletteId: DEFAULT_BROWSER_THEME_PALETTE_ID,
  tabsOverviewLayoutStyle: 'grid',
  tabsOverviewCloseButtonAlwaysVisible: false,
  showDesktopBookmarkBar: true
};

export const DEFAULT_BROWSER_GENERAL_SETTINGS: BrowserGeneralSettings = {
  startupRestorePolicy: 'restore_regular_tabs',
  tabAutoClosePolicy: 'manual',
  privateTabRestorePolicy: 'never_restore',
  privateModeAuthenticationEnabled: false,
  alwaysUsePrivateMode: false,
  privateModePreserveCookiesOnClose: false,
  privateModeThemeEnabled: true,
  enhancedTrackingProtectionEnabled: false
};

export const DEFAULT_BROWSER_COOKIE_POLICY_SETTINGS: BrowserCookiePolicySettings = {
  acceptCookies: true,
  acceptThirdPartyCookies: true
};

export const DEFAULT_BROWSER_APP_PROXY_SETTINGS: BrowserAppProxySettings = {
  scheme: 'http',
  host: '',
  port: 0,
  username: '',
  password: '',
  bypassHosts: 'localhost,127.0.0.1,::1',
  updatedAt: 0
};

export const DEFAULT_BROWSER_APP_PROXY_PROFILE: BrowserAppProxyProfile = {
  id: 'default',
  name: '默认代理',
  settings: DEFAULT_BROWSER_APP_PROXY_SETTINGS,
  createdAt: 0,
  updatedAt: 0
};

export const DEFAULT_BROWSER_EXPERIMENT_SETTINGS: BrowserExperimentSettings = {
  pauseWebAnimationsDuringScroll: false,
  reduceMediaMotionDuringScroll: false,
  strengthenAdBlockingForSmoothScroll: false,
  pullRefreshEnabled: true,
  forceEnableWebZoom: false,
  smartGripTabsActionsEnabled: true,
  webVideoTakeoverEnabled: true,
  novelModeEnabled: true,
  novelAutoTakeoverEnabled: false,
  appProxyActiveProfileId: '',
  appProxyProfiles: [],
  appProxyEnabled: false,
  appProxy: DEFAULT_BROWSER_APP_PROXY_SETTINGS
};

interface LegacyBrowserExperimentSettings extends BrowserExperimentSettings {
  edgePullRefreshEnabled?: boolean;
}

export function resolveExperimentPullRefreshEnabled(
  settings: BrowserExperimentSettings | undefined,
  fallback: boolean
): boolean {
  if (typeof settings?.pullRefreshEnabled === 'boolean') {
    return settings.pullRefreshEnabled;
  }
  if (settings === undefined) {
    return fallback;
  }
  const legacySettings = settings as LegacyBrowserExperimentSettings;
  return typeof legacySettings.edgePullRefreshEnabled === 'boolean' ? legacySettings.edgePullRefreshEnabled : fallback;
}

export const DEFAULT_BROWSER_APP_SERVICE_MODE: BrowserAppServiceMode = 'full';

export const DEFAULT_SEARCH_SUGGESTION_PREFERENCES: SearchSuggestionPreferences = {
  regularEnabled: true,
  privateEnabled: false,
  openTabsEnabled: false,
  bookmarksEnabled: false,
  shortcutsEnabled: false,
  historyEnabled: true,
  remoteEnabled: true
};

export const DEFAULT_SITE_PERMISSION_DEFAULT_SETTINGS: SitePermissionDefaultSettings = {
  camera: 'ask',
  microphone: 'ask',
  location: 'ask',
  sensor: 'ask',
  clipboard: 'ask'
};

export const DEFAULT_EXTERNAL_NAVIGATION_SETTINGS: ExternalNavigationSettings = {
  appOpenPolicy: 'ask',
  suppressAfterCancelMs: 24 * 60 * 60 * 1000,
  siteRules: []
};

export function buildBrowserRetentionSettingsForProfile(
  profileId: BrowserRetentionProfileId,
  deviceTierHint: BrowserDeviceTierHint = DEFAULT_BROWSER_RETENTION_SETTINGS.deviceTierHint
): BrowserRetentionSettings {
  if (profileId === 'memory_saver') {
    return {
      profileId: 'memory_saver',
      deviceTierHint: deviceTierHint,
      maxMountedRuntimeTabs: HUAWEI_BROWSER_PHONE_MEMORY_PRESSURE_RUNTIME_TAB_LIMIT,
      maxHotBackgroundTabs: 2,
      maxWarmBackgroundTabs: 6,
      hotBackgroundMaxAgeMs: 15 * 60 * 1000,
      warmBackgroundMaxAgeMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS,
      staleAfterMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS
    };
  }
  if (profileId === 'keep_more_tabs') {
    if (deviceTierHint === 'ultra_memory') {
      return {
        profileId: 'keep_more_tabs',
        deviceTierHint: deviceTierHint,
        maxMountedRuntimeTabs: HUAWEI_BROWSER_NON_MOBILE_NORMAL_RUNTIME_TAB_LIMIT,
        maxHotBackgroundTabs: 10,
        maxWarmBackgroundTabs: 20,
        hotBackgroundMaxAgeMs: 30 * 60 * 1000,
        warmBackgroundMaxAgeMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS,
        staleAfterMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS
      };
    }
    if (deviceTierHint === 'high_memory') {
      return {
        profileId: 'keep_more_tabs',
        deviceTierHint: deviceTierHint,
        maxMountedRuntimeTabs: HUAWEI_BROWSER_NON_MOBILE_NORMAL_RUNTIME_TAB_LIMIT,
        maxHotBackgroundTabs: 10,
        maxWarmBackgroundTabs: 20,
        hotBackgroundMaxAgeMs: 25 * 60 * 1000,
        warmBackgroundMaxAgeMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS,
        staleAfterMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS
      };
    }
    return {
      profileId: 'keep_more_tabs',
      deviceTierHint: deviceTierHint,
      maxMountedRuntimeTabs: HUAWEI_BROWSER_NON_MOBILE_NORMAL_RUNTIME_TAB_LIMIT,
      maxHotBackgroundTabs: 10,
      maxWarmBackgroundTabs: 20,
      hotBackgroundMaxAgeMs: 20 * 60 * 1000,
      warmBackgroundMaxAgeMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS,
      staleAfterMs: HUAWEI_BROWSER_TAB_MAX_LIVE_TIME_MS
    };
  }
  return {
    profileId: DEFAULT_BROWSER_RETENTION_SETTINGS.profileId,
    deviceTierHint: deviceTierHint,
    maxMountedRuntimeTabs: DEFAULT_BROWSER_RETENTION_SETTINGS.maxMountedRuntimeTabs,
    maxHotBackgroundTabs: DEFAULT_BROWSER_RETENTION_SETTINGS.maxHotBackgroundTabs,
    maxWarmBackgroundTabs: DEFAULT_BROWSER_RETENTION_SETTINGS.maxWarmBackgroundTabs,
    hotBackgroundMaxAgeMs: DEFAULT_BROWSER_RETENTION_SETTINGS.hotBackgroundMaxAgeMs,
    warmBackgroundMaxAgeMs: DEFAULT_BROWSER_RETENTION_SETTINGS.warmBackgroundMaxAgeMs,
    staleAfterMs: DEFAULT_BROWSER_RETENTION_SETTINGS.staleAfterMs
  };
}

const DEFAULT_PREFERENCES: BrowserPreferences = {
  appServiceMode: DEFAULT_BROWSER_APP_SERVICE_MODE,
  searchEngineId: DEFAULT_SEARCH_ENGINE_ID,
  searchSuggestions: DEFAULT_SEARCH_SUGGESTION_PREFERENCES,
  homeLayout: 'search + bookmarks',
  wallpaperEnabled: false,
  bookmarkSyncEnabled: false,
  historySyncEnabled: false,
  themeMode: 'system',
  appearance: DEFAULT_BROWSER_APPEARANCE_SETTINGS,
  general: DEFAULT_BROWSER_GENERAL_SETTINGS,
  cookiePolicy: DEFAULT_BROWSER_COOKIE_POLICY_SETTINGS,
  experiments: DEFAULT_BROWSER_EXPERIMENT_SETTINGS,
  readerMode: DEFAULT_READER_MODE_PREFERENCES,
  downloads: DEFAULT_BROWSER_DOWNLOAD_SETTINGS,
  toolbarLayout: DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS,
  sitePermissionDefaults: DEFAULT_SITE_PERMISSION_DEFAULT_SETTINGS,
  externalNavigation: DEFAULT_EXTERNAL_NAVIGATION_SETTINGS,
  retention: DEFAULT_BROWSER_RETENTION_SETTINGS,
  historyRetention: DEFAULT_HISTORY_RETENTION_SETTINGS
};

export type BrowserPreferencesChangeScope =
  'theme_mode' |
  'appearance' |
  'general' |
  'app_service_mode' |
  'experiments' |
  'downloads' |
  'toolbar_layout';
export type BrowserPreferencesChangeOrigin = 'local' | 'sync' | 'presentation';
export type BrowserPreferencesChangeListener =
  (
    preferences: BrowserPreferences,
    scope: BrowserPreferencesChangeScope,
    origin: BrowserPreferencesChangeOrigin
  ) => void;

export interface PreferencesStorageAdapter {
  readAppServiceMode(defaultValue: BrowserAppServiceMode): Promise<BrowserAppServiceMode>;
  writeAppServiceMode(mode: BrowserAppServiceMode): Promise<void>;
  readSearchEngineId(defaultValue: SearchEngineId): Promise<SearchEngineId>;
  writeSearchEngineId(searchEngineId: SearchEngineId): Promise<void>;
  readSearchSuggestionPreferences(defaultValue: SearchSuggestionPreferences): Promise<SearchSuggestionPreferences>;
  writeSearchSuggestionPreferences(preferences: SearchSuggestionPreferences): Promise<void>;
  readThemeMode(defaultValue: BrowserThemeMode): Promise<BrowserThemeMode>;
  writeThemeMode(themeMode: BrowserThemeMode): Promise<void>;
  readAppearanceSettings(defaultValue: BrowserAppearanceSettings): Promise<BrowserAppearanceSettings>;
  writeAppearanceSettings(settings: BrowserAppearanceSettings): Promise<void>;
  readGeneralSettings(defaultValue: BrowserGeneralSettings): Promise<BrowserGeneralSettings>;
  writeGeneralSettings(settings: BrowserGeneralSettings): Promise<void>;
  readCookiePolicySettings(defaultValue: BrowserCookiePolicySettings): Promise<BrowserCookiePolicySettings>;
  writeCookiePolicySettings(settings: BrowserCookiePolicySettings): Promise<void>;
  readExperimentSettings(defaultValue: BrowserExperimentSettings): Promise<BrowserExperimentSettings>;
  writeExperimentSettings(settings: BrowserExperimentSettings): Promise<void>;
  readReaderModePreferences(defaultValue: ReaderModePreferences): Promise<ReaderModePreferences>;
  writeReaderModePreferences(preferences: ReaderModePreferences): Promise<void>;
  readDownloadSettings(defaultValue: BrowserDownloadSettings): Promise<BrowserDownloadSettings>;
  writeDownloadSettings(settings: BrowserDownloadSettings): Promise<void>;
  readToolbarLayoutSettings(defaultValue: BrowserToolbarLayoutSettings): Promise<BrowserToolbarLayoutSettings>;
  writeToolbarLayoutSettings(settings: BrowserToolbarLayoutSettings): Promise<void>;
  readSitePermissionDefaultSettings(defaultValue: SitePermissionDefaultSettings): Promise<SitePermissionDefaultSettings>;
  writeSitePermissionDefaultSettings(settings: SitePermissionDefaultSettings): Promise<void>;
  readExternalNavigationSettings(defaultValue: ExternalNavigationSettings): Promise<ExternalNavigationSettings>;
  writeExternalNavigationSettings(settings: ExternalNavigationSettings): Promise<void>;
  readRetentionSettings(defaultValue: BrowserRetentionSettings): Promise<BrowserRetentionSettings>;
  writeRetentionSettings(settings: BrowserRetentionSettings): Promise<void>;
  readHistoryRetentionSettings(defaultValue: HistoryRetentionSettings): Promise<HistoryRetentionSettings>;
  writeHistoryRetentionSettings(settings: HistoryRetentionSettings): Promise<void>;
  readSitePermissionSettings(): Promise<SitePermissionSettings[]>;
  writeSitePermissionSettings(settings: SitePermissionSettings[]): Promise<void>;
  flush?(): Promise<void>;
}

class MemoryPreferencesStorageAdapter implements PreferencesStorageAdapter {
  private appServiceMode: BrowserAppServiceMode = DEFAULT_BROWSER_APP_SERVICE_MODE;
  private searchEngineId: SearchEngineId = DEFAULT_PREFERENCES.searchEngineId;
  private searchSuggestionPreferences: SearchSuggestionPreferences = DEFAULT_SEARCH_SUGGESTION_PREFERENCES;
  private themeMode: BrowserThemeMode = DEFAULT_PREFERENCES.themeMode;
  private appearanceSettings: BrowserAppearanceSettings = DEFAULT_BROWSER_APPEARANCE_SETTINGS;
  private generalSettings: BrowserGeneralSettings = DEFAULT_BROWSER_GENERAL_SETTINGS;
  private cookiePolicySettings: BrowserCookiePolicySettings = DEFAULT_BROWSER_COOKIE_POLICY_SETTINGS;
  private experimentSettings: BrowserExperimentSettings = DEFAULT_BROWSER_EXPERIMENT_SETTINGS;
  private readerModePreferences: ReaderModePreferences = DEFAULT_READER_MODE_PREFERENCES;
  private downloadSettings: BrowserDownloadSettings = DEFAULT_BROWSER_DOWNLOAD_SETTINGS;
  private toolbarLayoutSettings: BrowserToolbarLayoutSettings = DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS;
  private sitePermissionDefaultSettings: SitePermissionDefaultSettings = DEFAULT_SITE_PERMISSION_DEFAULT_SETTINGS;
  private externalNavigationSettings: ExternalNavigationSettings = DEFAULT_EXTERNAL_NAVIGATION_SETTINGS;
  private retentionSettings: BrowserRetentionSettings = DEFAULT_BROWSER_RETENTION_SETTINGS;
  private historyRetentionSettings: HistoryRetentionSettings = DEFAULT_HISTORY_RETENTION_SETTINGS;
  private sitePermissionSettings: SitePermissionSettings[] = [];

  readAppServiceMode(_defaultValue: BrowserAppServiceMode): Promise<BrowserAppServiceMode> {
    return Promise.resolve(this.appServiceMode);
  }

  writeAppServiceMode(mode: BrowserAppServiceMode): Promise<void> {
    this.appServiceMode = mode;
    return Promise.resolve();
  }

  readSearchEngineId(_defaultValue: SearchEngineId): Promise<SearchEngineId> {
    return Promise.resolve(this.searchEngineId);
  }

  writeSearchEngineId(searchEngineId: SearchEngineId): Promise<void> {
    this.searchEngineId = searchEngineId;
    return Promise.resolve();
  }

  readSearchSuggestionPreferences(_defaultValue: SearchSuggestionPreferences): Promise<SearchSuggestionPreferences> {
    return Promise.resolve(this.searchSuggestionPreferences);
  }

  writeSearchSuggestionPreferences(preferences: SearchSuggestionPreferences): Promise<void> {
    this.searchSuggestionPreferences = preferences;
    return Promise.resolve();
  }

  readThemeMode(_defaultValue: BrowserThemeMode): Promise<BrowserThemeMode> {
    return Promise.resolve(this.themeMode);
  }

  writeThemeMode(themeMode: BrowserThemeMode): Promise<void> {
    this.themeMode = themeMode;
    return Promise.resolve();
  }

  readAppearanceSettings(_defaultValue: BrowserAppearanceSettings): Promise<BrowserAppearanceSettings> {
    return Promise.resolve(this.appearanceSettings);
  }

  writeAppearanceSettings(settings: BrowserAppearanceSettings): Promise<void> {
    this.appearanceSettings = settings;
    return Promise.resolve();
  }

  readGeneralSettings(_defaultValue: BrowserGeneralSettings): Promise<BrowserGeneralSettings> {
    return Promise.resolve(this.generalSettings);
  }

  writeGeneralSettings(settings: BrowserGeneralSettings): Promise<void> {
    this.generalSettings = settings;
    return Promise.resolve();
  }

  readCookiePolicySettings(_defaultValue: BrowserCookiePolicySettings): Promise<BrowserCookiePolicySettings> {
    return Promise.resolve(this.cookiePolicySettings);
  }

  writeCookiePolicySettings(settings: BrowserCookiePolicySettings): Promise<void> {
    this.cookiePolicySettings = settings;
    return Promise.resolve();
  }

  readExperimentSettings(_defaultValue: BrowserExperimentSettings): Promise<BrowserExperimentSettings> {
    return Promise.resolve(this.experimentSettings);
  }

  writeExperimentSettings(settings: BrowserExperimentSettings): Promise<void> {
    this.experimentSettings = settings;
    return Promise.resolve();
  }

  readReaderModePreferences(_defaultValue: ReaderModePreferences): Promise<ReaderModePreferences> {
    return Promise.resolve(this.readerModePreferences);
  }

  writeReaderModePreferences(preferences: ReaderModePreferences): Promise<void> {
    this.readerModePreferences = preferences;
    return Promise.resolve();
  }

  readDownloadSettings(_defaultValue: BrowserDownloadSettings): Promise<BrowserDownloadSettings> {
    return Promise.resolve(this.downloadSettings);
  }

  writeDownloadSettings(settings: BrowserDownloadSettings): Promise<void> {
    this.downloadSettings = settings;
    return Promise.resolve();
  }

  readToolbarLayoutSettings(_defaultValue: BrowserToolbarLayoutSettings): Promise<BrowserToolbarLayoutSettings> {
    return Promise.resolve(this.toolbarLayoutSettings);
  }

  writeToolbarLayoutSettings(settings: BrowserToolbarLayoutSettings): Promise<void> {
    this.toolbarLayoutSettings = settings;
    return Promise.resolve();
  }

  readSitePermissionDefaultSettings(_defaultValue: SitePermissionDefaultSettings): Promise<SitePermissionDefaultSettings> {
    return Promise.resolve(this.sitePermissionDefaultSettings);
  }

  writeSitePermissionDefaultSettings(settings: SitePermissionDefaultSettings): Promise<void> {
    this.sitePermissionDefaultSettings = settings;
    return Promise.resolve();
  }

  readExternalNavigationSettings(_defaultValue: ExternalNavigationSettings): Promise<ExternalNavigationSettings> {
    return Promise.resolve(this.externalNavigationSettings);
  }

  writeExternalNavigationSettings(settings: ExternalNavigationSettings): Promise<void> {
    this.externalNavigationSettings = settings;
    return Promise.resolve();
  }

  readRetentionSettings(_defaultValue: BrowserRetentionSettings): Promise<BrowserRetentionSettings> {
    return Promise.resolve(this.retentionSettings);
  }

  writeRetentionSettings(settings: BrowserRetentionSettings): Promise<void> {
    this.retentionSettings = settings;
    return Promise.resolve();
  }

  readHistoryRetentionSettings(_defaultValue: HistoryRetentionSettings): Promise<HistoryRetentionSettings> {
    return Promise.resolve(this.historyRetentionSettings);
  }

  writeHistoryRetentionSettings(settings: HistoryRetentionSettings): Promise<void> {
    this.historyRetentionSettings = settings;
    return Promise.resolve();
  }

  readSitePermissionSettings(): Promise<SitePermissionSettings[]> {
    return Promise.resolve(this.sitePermissionSettings);
  }

  writeSitePermissionSettings(settings: SitePermissionSettings[]): Promise<void> {
    this.sitePermissionSettings = settings;
    return Promise.resolve();
  }
}

export class PreferencesRepository {
  private storageAdapter: PreferencesStorageAdapter;
  private siteIdentityService: SiteIdentityService = new SiteIdentityService();
  private cachedPreferences: BrowserPreferences = DEFAULT_PREFERENCES;
  private cachedSitePermissionSettings: SitePermissionSettings[] = [];
  private pendingStorageWrite: Promise<void> = Promise.resolve();
  private listenerSequence: number = 0;
  private listeners: Record<string, BrowserPreferencesChangeListener | undefined> = {};

  constructor(storageAdapter?: PreferencesStorageAdapter) {
    this.storageAdapter = storageAdapter === undefined ? new MemoryPreferencesStorageAdapter() : storageAdapter;
  }

  getPreferences(): BrowserPreferences {
    return this.cachedPreferences;
  }

  async flush(): Promise<void> {
    await this.pendingStorageWrite;
    if (this.storageAdapter.flush !== undefined) {
      await this.storageAdapter.flush();
    }
  }

  subscribe(listener: BrowserPreferencesChangeListener): string {
    this.listenerSequence += 1;
    const key = `preferences-listener-${this.listenerSequence}`;
    this.listeners[key] = listener;
    return key;
  }

  unsubscribe(key: string): void {
    this.listeners[key] = undefined;
  }

  notifyThemeModePresentationChanged(): void {
    this.notifyChanged('theme_mode', 'presentation');
  }

  normalizeThemeModeForPersistence(value: BrowserThemeMode | string | undefined): BrowserThemeMode {
    return this.normalizeThemeMode(value);
  }

  async initialize(): Promise<BrowserPreferences> {
    const storedAppServiceMode = await this.storageAdapter.readAppServiceMode(DEFAULT_BROWSER_APP_SERVICE_MODE);
    const storedSearchEngine = await this.storageAdapter.readSearchEngineId(DEFAULT_PREFERENCES.searchEngineId);
    const storedSearchSuggestions =
      await this.storageAdapter.readSearchSuggestionPreferences(DEFAULT_SEARCH_SUGGESTION_PREFERENCES);
    const storedThemeMode = await this.storageAdapter.readThemeMode(DEFAULT_PREFERENCES.themeMode);
    const storedAppearanceSettings =
      await this.storageAdapter.readAppearanceSettings(DEFAULT_BROWSER_APPEARANCE_SETTINGS);
    const storedGeneralSettings =
      await this.storageAdapter.readGeneralSettings(DEFAULT_BROWSER_GENERAL_SETTINGS);
    const storedCookiePolicySettings =
      await this.storageAdapter.readCookiePolicySettings(DEFAULT_BROWSER_COOKIE_POLICY_SETTINGS);
    const storedExperimentSettings =
      await this.storageAdapter.readExperimentSettings(DEFAULT_BROWSER_EXPERIMENT_SETTINGS);
    const storedReaderMode = await this.storageAdapter.readReaderModePreferences(DEFAULT_READER_MODE_PREFERENCES);
    const storedDownloadSettings = await this.storageAdapter.readDownloadSettings(DEFAULT_BROWSER_DOWNLOAD_SETTINGS);
    const storedToolbarLayoutSettings =
      await this.storageAdapter.readToolbarLayoutSettings(DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS);
    const storedSitePermissionDefaultSettings =
      await this.storageAdapter.readSitePermissionDefaultSettings(DEFAULT_SITE_PERMISSION_DEFAULT_SETTINGS);
    const storedExternalNavigationSettings =
      await this.storageAdapter.readExternalNavigationSettings(DEFAULT_EXTERNAL_NAVIGATION_SETTINGS);
    const storedRetentionSettings = await this.storageAdapter.readRetentionSettings(DEFAULT_BROWSER_RETENTION_SETTINGS);
    const storedHistoryRetentionSettings =
      await this.storageAdapter.readHistoryRetentionSettings(DEFAULT_HISTORY_RETENTION_SETTINGS);
    this.cachedSitePermissionSettings =
      this.normalizeSitePermissionSettings(await this.storageAdapter.readSitePermissionSettings());
    this.cachedPreferences = {
      appServiceMode: this.normalizeAppServiceMode(storedAppServiceMode),
      searchEngineId: this.normalizeSearchEngineId(storedSearchEngine),
      searchSuggestions: this.normalizeSearchSuggestionPreferences(storedSearchSuggestions),
      homeLayout: DEFAULT_PREFERENCES.homeLayout,
      wallpaperEnabled: DEFAULT_PREFERENCES.wallpaperEnabled,
      bookmarkSyncEnabled: DEFAULT_PREFERENCES.bookmarkSyncEnabled,
      historySyncEnabled: DEFAULT_PREFERENCES.historySyncEnabled,
      themeMode: this.normalizeThemeMode(storedThemeMode),
      appearance: this.normalizeAppearanceSettings(storedAppearanceSettings),
      general: this.normalizeGeneralSettings(storedGeneralSettings),
      cookiePolicy: this.normalizeCookiePolicySettings(storedCookiePolicySettings),
      experiments: this.normalizeExperimentSettings(storedExperimentSettings),
      readerMode: this.normalizeReaderModePreferences(storedReaderMode),
      downloads: this.normalizeDownloadSettings(storedDownloadSettings),
      toolbarLayout: this.normalizeToolbarLayoutSettings(storedToolbarLayoutSettings),
      sitePermissionDefaults: this.normalizeSitePermissionDefaultSettings(storedSitePermissionDefaultSettings),
      externalNavigation: this.normalizeExternalNavigationSettings(storedExternalNavigationSettings),
      retention: this.normalizeRetentionSettings(storedRetentionSettings),
      historyRetention: this.normalizeHistoryRetentionSettings(storedHistoryRetentionSettings)
    };
    return this.cachedPreferences;
  }

  async updateSearchEngine(searchEngineId: SearchEngineId): Promise<BrowserPreferences> {
    this.mergeCachedPreferences({ searchEngineId: searchEngineId });
    await this.storageAdapter.writeSearchEngineId(searchEngineId);
    return this.cachedPreferences;
  }

  async updateAppServiceMode(mode: BrowserAppServiceMode): Promise<BrowserPreferences> {
    const normalizedMode = this.normalizeAppServiceMode(mode);
    this.mergeCachedPreferences({ appServiceMode: normalizedMode });
    await this.storageAdapter.writeAppServiceMode(normalizedMode);
    this.notifyChanged('app_service_mode');
    return this.cachedPreferences;
  }

  async updateSearchSuggestionPreferences(preferences: SearchSuggestionPreferences): Promise<BrowserPreferences> {
    const normalizedPreferences = this.normalizeSearchSuggestionPreferences(preferences);
    this.mergeCachedPreferences({ searchSuggestions: normalizedPreferences });
    await this.storageAdapter.writeSearchSuggestionPreferences(normalizedPreferences);
    return this.cachedPreferences;
  }

  async updateRetentionSettings(settings: BrowserRetentionSettings): Promise<BrowserPreferences> {
    const normalizedRetentionSettings = this.normalizeRetentionSettings(settings);
    this.mergeCachedPreferences({ retention: normalizedRetentionSettings });
    await this.storageAdapter.writeRetentionSettings(normalizedRetentionSettings);
    return this.cachedPreferences;
  }

  async updateHistoryRetentionSettings(settings: HistoryRetentionSettings): Promise<BrowserPreferences> {
    const normalizedHistoryRetentionSettings = this.normalizeHistoryRetentionSettings(settings);
    this.mergeCachedPreferences({ historyRetention: normalizedHistoryRetentionSettings });
    await this.storageAdapter.writeHistoryRetentionSettings(normalizedHistoryRetentionSettings);
    return this.cachedPreferences;
  }

  async updateThemeMode(
    themeMode: BrowserThemeMode,
    origin: BrowserPreferencesChangeOrigin = 'local'
  ): Promise<BrowserPreferences> {
    const normalizedThemeMode = this.normalizeThemeMode(themeMode);
    this.mergeCachedPreferences({ themeMode: normalizedThemeMode });
    await this.storageAdapter.writeThemeMode(normalizedThemeMode);
    this.notifyChanged('theme_mode', origin);
    return this.cachedPreferences;
  }

  async updateAppearanceSettings(
    settings: BrowserAppearanceSettings,
    origin: BrowserPreferencesChangeOrigin = 'local'
  ): Promise<BrowserPreferences> {
    const normalizedAppearanceSettings = this.normalizeAppearanceSettings(settings);
    this.mergeCachedPreferences({ appearance: normalizedAppearanceSettings });
    await this.enqueueStorageWrite(() => this.storageAdapter.writeAppearanceSettings(normalizedAppearanceSettings));
    this.notifyChanged('appearance', origin);
    return this.cachedPreferences;
  }

  async updateBottomToolbarScrollBehavior(
    behavior: BrowserBottomToolbarScrollBehavior
  ): Promise<BrowserPreferences> {
    const current = this.cachedPreferences.appearance;
    return this.updateAppearanceSettings({
      bottomToolbarScrollBehavior: behavior,
      globalImmersionEnabled: current.globalImmersionEnabled,
      alwaysTopImmersionEnabled: current.alwaysTopImmersionEnabled,
      forceDarkWebContentEnabled: current.forceDarkWebContentEnabled,
      blurPrivateTabPreviews: current.blurPrivateTabPreviews,
      showHomeRecentlyClosed: current.showHomeRecentlyClosed,
      showHomeShortcuts: current.showHomeShortcuts,
      homeRecentlyClosedLimit: current.homeRecentlyClosedLimit,
      homeShortcutLayoutDensity: current.homeShortcutLayoutDensity,
      homeShortcutIconSizeRatio: current.homeShortcutIconSizeRatio,
      siteIconCornerRadiusRatio: current.siteIconCornerRadiusRatio,
      themePaletteId: current.themePaletteId,
      tabsOverviewLayoutStyle: current.tabsOverviewLayoutStyle,
      tabsOverviewCloseButtonAlwaysVisible: current.tabsOverviewCloseButtonAlwaysVisible,
      showDesktopBookmarkBar: current.showDesktopBookmarkBar
    });
  }

  async updateTabsOverviewPresentation(
    style: BrowserTabsOverviewLayoutStyle,
    closeButtonAlwaysVisible: boolean
  ): Promise<BrowserPreferences> {
    const current = this.cachedPreferences.appearance;
    return this.updateAppearanceSettings({
      bottomToolbarScrollBehavior: current.bottomToolbarScrollBehavior,
      globalImmersionEnabled: current.globalImmersionEnabled,
      alwaysTopImmersionEnabled: current.alwaysTopImmersionEnabled,
      forceDarkWebContentEnabled: current.forceDarkWebContentEnabled,
      blurPrivateTabPreviews: current.blurPrivateTabPreviews,
      showHomeRecentlyClosed: current.showHomeRecentlyClosed,
      showHomeShortcuts: current.showHomeShortcuts,
      homeRecentlyClosedLimit: current.homeRecentlyClosedLimit,
      homeShortcutLayoutDensity: current.homeShortcutLayoutDensity,
      homeShortcutIconSizeRatio: current.homeShortcutIconSizeRatio,
      siteIconCornerRadiusRatio: current.siteIconCornerRadiusRatio,
      themePaletteId: current.themePaletteId,
      tabsOverviewLayoutStyle: this.normalizeTabsOverviewLayoutStyle(style),
      tabsOverviewCloseButtonAlwaysVisible: closeButtonAlwaysVisible,
      showDesktopBookmarkBar: current.showDesktopBookmarkBar
    });
  }

  async updateGeneralSettings(
    settings: BrowserGeneralSettings,
    origin: BrowserPreferencesChangeOrigin = 'local'
  ): Promise<BrowserPreferences> {
    const current = this.cachedPreferences.general;
    const next: BrowserGeneralSettings = {
      startupRestorePolicy: settings.startupRestorePolicy,
      tabAutoClosePolicy: settings.tabAutoClosePolicy,
      privateTabRestorePolicy: settings.privateTabRestorePolicy,
      privateModeAuthenticationEnabled: settings.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: settings.alwaysUsePrivateMode ?? current.alwaysUsePrivateMode,
      privateModePreserveCookiesOnClose: settings.privateModePreserveCookiesOnClose,
      privateModeThemeEnabled: settings.privateModeThemeEnabled,
      enhancedTrackingProtectionEnabled: settings.enhancedTrackingProtectionEnabled ??
        current.enhancedTrackingProtectionEnabled
    };
    const normalizedGeneralSettings = this.normalizeGeneralSettings(next);
    this.mergeCachedPreferences({ general: normalizedGeneralSettings });
    await this.storageAdapter.writeGeneralSettings(normalizedGeneralSettings);
    this.notifyChanged('general', origin);
    return this.cachedPreferences;
  }

  async updateExperimentSettings(settings: BrowserExperimentSettings): Promise<BrowserPreferences> {
    const previousSettings = this.cachedPreferences.experiments;
    const normalizedExperimentSettings = this.normalizeExperimentSettings(settings);
    this.mergeCachedPreferences({ experiments: normalizedExperimentSettings });
    await this.storageAdapter.writeExperimentSettings(normalizedExperimentSettings);
    this.logExperimentSettingsUpdate(previousSettings, normalizedExperimentSettings);
    this.notifyChanged('experiments');
    return this.cachedPreferences;
  }

  async updateReaderModePreferences(preferences: ReaderModePreferences): Promise<BrowserPreferences> {
    const normalizedReaderModePreferences = this.normalizeReaderModePreferences(preferences);
    this.mergeCachedPreferences({ readerMode: normalizedReaderModePreferences });
    await this.storageAdapter.writeReaderModePreferences(normalizedReaderModePreferences);
    return this.cachedPreferences;
  }

  async updateDownloadSettings(settings: BrowserDownloadSettings): Promise<BrowserPreferences> {
    const normalizedDownloadSettings = this.normalizeDownloadSettings(settings);
    this.mergeCachedPreferences({ downloads: normalizedDownloadSettings });
    await this.storageAdapter.writeDownloadSettings(normalizedDownloadSettings);
    this.notifyChanged('downloads');
    return this.cachedPreferences;
  }

  async updateToolbarLayoutSettings(
    settings: BrowserToolbarLayoutSettings,
    origin: BrowserPreferencesChangeOrigin = 'local'
  ): Promise<BrowserPreferences> {
    const current = this.cachedPreferences.toolbarLayout;
    const mergedSettings: BrowserToolbarLayoutSettings = {
      primaryActionIds: settings.primaryActionIds,
      secondaryActionIds: settings.secondaryActionIds,
      leadingSlotActionId: settings.leadingSlotActionId !== undefined ?
        settings.leadingSlotActionId : current.leadingSlotActionId,
      menuSlotActionId: settings.menuSlotActionId !== undefined ?
        settings.menuSlotActionId : current.menuSlotActionId,
      refreshSlotActionId: settings.refreshSlotActionId !== undefined ?
        settings.refreshSlotActionId : current.refreshSlotActionId,
      tabsSlotActionId: settings.tabsSlotActionId !== undefined ?
        settings.tabsSlotActionId : current.tabsSlotActionId,
      leadingSlotLongPressActionId: settings.leadingSlotLongPressActionId !== undefined ?
        settings.leadingSlotLongPressActionId : current.leadingSlotLongPressActionId,
      menuSlotLongPressActionId: settings.menuSlotLongPressActionId !== undefined ?
        settings.menuSlotLongPressActionId : current.menuSlotLongPressActionId,
      refreshSlotLongPressActionId: settings.refreshSlotLongPressActionId !== undefined ?
        settings.refreshSlotLongPressActionId : current.refreshSlotLongPressActionId,
      tabsSlotLongPressActionId: settings.tabsSlotLongPressActionId !== undefined ?
        settings.tabsSlotLongPressActionId : current.tabsSlotLongPressActionId,
      leadingSlotSwipeUpActionId: settings.leadingSlotSwipeUpActionId !== undefined ?
        settings.leadingSlotSwipeUpActionId : current.leadingSlotSwipeUpActionId,
      tabsSlotSwipeUpActionId: settings.tabsSlotSwipeUpActionId !== undefined ?
        settings.tabsSlotSwipeUpActionId : current.tabsSlotSwipeUpActionId,
      updatedAt: settings.updatedAt
    };
    const normalizedToolbarLayoutSettings = this.normalizeToolbarLayoutSettings(mergedSettings);
    this.mergeCachedPreferences({ toolbarLayout: normalizedToolbarLayoutSettings });
    await this.storageAdapter.writeToolbarLayoutSettings(normalizedToolbarLayoutSettings);
    this.notifyChanged('toolbar_layout', origin);
    return this.cachedPreferences;
  }

  async updateSitePermissionDefaultSettings(settings: SitePermissionDefaultSettings): Promise<BrowserPreferences> {
    const normalizedSettings = this.normalizeSitePermissionDefaultSettings(settings);
    this.mergeCachedPreferences({ sitePermissionDefaults: normalizedSettings });
    await this.storageAdapter.writeSitePermissionDefaultSettings(normalizedSettings);
    return this.cachedPreferences;
  }

  async updateExternalNavigationSettings(settings: ExternalNavigationSettings): Promise<BrowserPreferences> {
    const normalizedSettings = this.normalizeExternalNavigationSettings(settings);
    this.mergeCachedPreferences({ externalNavigation: normalizedSettings });
    await this.storageAdapter.writeExternalNavigationSettings(normalizedSettings);
    return this.cachedPreferences;
  }

  async clearAllExternalNavigationSiteRules(): Promise<void> {
    const current = this.cachedPreferences.externalNavigation;
    if (current.siteRules.length === 0) {
      return;
    }
    await this.updateExternalNavigationSettings({
      appOpenPolicy: current.appOpenPolicy,
      suppressAfterCancelMs: current.suppressAfterCancelMs,
      siteRules: []
    });
  }

  async updateCookiePolicySettings(settings: BrowserCookiePolicySettings): Promise<BrowserPreferences> {
    const normalizedSettings = this.normalizeCookiePolicySettings(settings);
    this.mergeCachedPreferences({ cookiePolicy: normalizedSettings });
    await this.storageAdapter.writeCookiePolicySettings(normalizedSettings);
    return this.cachedPreferences;
  }

  getSitePermissionSettings(
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): SitePermissionSettings {
    const normalizedOrigin = this.normalizeOrigin(origin);
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    const storedSettings = this.cachedSitePermissionSettings.find((settings: SitePermissionSettings) => {
      return settings.primaryOrigin === normalizedOrigin && settings.profileId === normalizedProfileId;
    });
    if (storedSettings !== undefined) {
      return storedSettings;
    }
    return this.createDefaultSitePermissionSettings(normalizedOrigin, normalizedProfileId);
  }

  async updateSitePermissionRule(origin: string, kind: SitePermissionKind,
    rule: SitePermissionRule,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<SitePermissionSettings> {
    const normalizedOrigin = this.normalizeOrigin(origin);
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    const currentSettings = this.getSitePermissionSettings(normalizedOrigin, normalizedProfileId);
    const identity = this.siteIdentityService.resolve(normalizedOrigin);
    const nextSettings: SitePermissionSettings = {
      profileId: normalizedProfileId,
      origin: identity.primaryOrigin,
      siteKey: identity.siteKey,
      displayHost: identity.displayHost,
      primaryOrigin: identity.primaryOrigin,
      camera: kind === 'camera' ? rule : currentSettings.camera,
      microphone: kind === 'microphone' ? rule : currentSettings.microphone,
      location: kind === 'location' ? rule : currentSettings.location,
      sensor: kind === 'sensor' ? rule : currentSettings.sensor,
      clipboard: kind === 'clipboard' ? rule : currentSettings.clipboard,
      updatedAt: Date.now()
    };

    this.cachedSitePermissionSettings = this.cachedSitePermissionSettings
      .filter((settings: SitePermissionSettings) => {
        return settings.primaryOrigin !== normalizedOrigin || settings.profileId !== normalizedProfileId;
      });
    if (!this.isDefaultSitePermissionSettings(nextSettings)) {
      this.cachedSitePermissionSettings = this.cachedSitePermissionSettings.concat([nextSettings]);
    }
    await this.storageAdapter.writeSitePermissionSettings(this.cachedSitePermissionSettings);
    return nextSettings;
  }

  private normalizeThemeMode(value: BrowserThemeMode | string | undefined): BrowserThemeMode {
    if (value === 'light' || value === 'dark' || value === 'system') {
      return value;
    }
    return 'system';
  }

  private normalizeAppServiceMode(value: BrowserAppServiceMode | string | undefined): BrowserAppServiceMode {
    return value === 'basic' ? 'basic' : DEFAULT_BROWSER_APP_SERVICE_MODE;
  }

  private normalizeAppearanceSettings(settings: BrowserAppearanceSettings | undefined): BrowserAppearanceSettings {
    return {
      bottomToolbarScrollBehavior: this.normalizeBottomToolbarScrollBehavior(
        settings?.bottomToolbarScrollBehavior
      ),
      globalImmersionEnabled: typeof settings?.globalImmersionEnabled === 'boolean'
        ? settings.globalImmersionEnabled
        : DEFAULT_BROWSER_APPEARANCE_SETTINGS.globalImmersionEnabled,
      alwaysTopImmersionEnabled: typeof settings?.alwaysTopImmersionEnabled === 'boolean'
        ? settings.alwaysTopImmersionEnabled
        : DEFAULT_BROWSER_APPEARANCE_SETTINGS.alwaysTopImmersionEnabled,
      forceDarkWebContentEnabled: typeof settings?.forceDarkWebContentEnabled === 'boolean'
        ? settings.forceDarkWebContentEnabled
        : DEFAULT_BROWSER_APPEARANCE_SETTINGS.forceDarkWebContentEnabled,
      blurPrivateTabPreviews: typeof settings?.blurPrivateTabPreviews === 'boolean'
        ? settings.blurPrivateTabPreviews
        : DEFAULT_BROWSER_APPEARANCE_SETTINGS.blurPrivateTabPreviews,
      showHomeRecentlyClosed: typeof settings?.showHomeRecentlyClosed === 'boolean'
        ? settings.showHomeRecentlyClosed
        : DEFAULT_BROWSER_APPEARANCE_SETTINGS.showHomeRecentlyClosed,
      showHomeShortcuts: typeof settings?.showHomeShortcuts === 'boolean'
        ? settings.showHomeShortcuts
        : DEFAULT_BROWSER_APPEARANCE_SETTINGS.showHomeShortcuts,
      homeRecentlyClosedLimit: this.normalizeRecentLimit(
        settings?.homeRecentlyClosedLimit,
        DEFAULT_BROWSER_APPEARANCE_SETTINGS.homeRecentlyClosedLimit
      ),
      homeShortcutLayoutDensity: this.normalizeHomeShortcutLayoutDensity(settings?.homeShortcutLayoutDensity),
      homeShortcutIconSizeRatio: this.normalizeHomeShortcutIconSizeRatio(settings?.homeShortcutIconSizeRatio),
      siteIconCornerRadiusRatio: this.normalizeSiteIconCornerRadiusRatio(settings?.siteIconCornerRadiusRatio),
      themePaletteId: settings?.themePaletteId ?? DEFAULT_BROWSER_APPEARANCE_SETTINGS.themePaletteId,
      tabsOverviewLayoutStyle: this.normalizeTabsOverviewLayoutStyle(settings?.tabsOverviewLayoutStyle),
      tabsOverviewCloseButtonAlwaysVisible: typeof settings?.tabsOverviewCloseButtonAlwaysVisible === 'boolean'
        ? settings.tabsOverviewCloseButtonAlwaysVisible
        : DEFAULT_BROWSER_APPEARANCE_SETTINGS.tabsOverviewCloseButtonAlwaysVisible,
      showDesktopBookmarkBar: typeof settings?.showDesktopBookmarkBar === 'boolean'
        ? settings.showDesktopBookmarkBar
        : DEFAULT_BROWSER_APPEARANCE_SETTINGS.showDesktopBookmarkBar
    };
  }

  private normalizeBottomToolbarScrollBehavior(
    value: BrowserBottomToolbarScrollBehavior | string | undefined
  ): BrowserBottomToolbarScrollBehavior {
    if (value === 'fixed' || value === 'compact' || value === 'hidden') {
      return value;
    }
    return DEFAULT_BROWSER_APPEARANCE_SETTINGS.bottomToolbarScrollBehavior;
  }

  private normalizeTabsOverviewLayoutStyle(
    value: BrowserTabsOverviewLayoutStyle | string | undefined
  ): BrowserTabsOverviewLayoutStyle {
    return value === 'horizontal_cards' ?
      'horizontal_cards' :
      DEFAULT_BROWSER_APPEARANCE_SETTINGS.tabsOverviewLayoutStyle;
  }

  private normalizeSiteIconCornerRadiusRatio(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return DEFAULT_BROWSER_APPEARANCE_SETTINGS.siteIconCornerRadiusRatio;
    }
    return Math.max(0.12, Math.min(0.5, Math.round(value * 100) / 100));
  }

  private normalizeHomeShortcutIconSizeRatio(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return DEFAULT_BROWSER_APPEARANCE_SETTINGS.homeShortcutIconSizeRatio;
    }
    return Math.max(0.45, Math.min(1, Math.round(value * 100) / 100));
  }

  private normalizeHomeShortcutLayoutDensity(
    value: BrowserHomeShortcutLayoutDensity | string | undefined
  ): BrowserHomeShortcutLayoutDensity {
    return value === 'compact' ? 'compact' : DEFAULT_BROWSER_APPEARANCE_SETTINGS.homeShortcutLayoutDensity;
  }

  private normalizeGeneralSettings(settings: BrowserGeneralSettings | undefined): BrowserGeneralSettings {
    return {
      startupRestorePolicy: this.normalizeStartupRestorePolicy(settings?.startupRestorePolicy),
      tabAutoClosePolicy: this.normalizeTabAutoClosePolicy(settings?.tabAutoClosePolicy),
      privateTabRestorePolicy: this.normalizePrivateTabRestorePolicy(settings?.privateTabRestorePolicy),
      privateModeAuthenticationEnabled: typeof settings?.privateModeAuthenticationEnabled === 'boolean'
        ? settings.privateModeAuthenticationEnabled
        : DEFAULT_BROWSER_GENERAL_SETTINGS.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: typeof settings?.alwaysUsePrivateMode === 'boolean'
        ? settings.alwaysUsePrivateMode
        : DEFAULT_BROWSER_GENERAL_SETTINGS.alwaysUsePrivateMode,
      privateModePreserveCookiesOnClose: typeof settings?.privateModePreserveCookiesOnClose === 'boolean'
        ? settings.privateModePreserveCookiesOnClose
        : DEFAULT_BROWSER_GENERAL_SETTINGS.privateModePreserveCookiesOnClose,
      privateModeThemeEnabled: typeof settings?.privateModeThemeEnabled === 'boolean'
        ? settings.privateModeThemeEnabled
        : DEFAULT_BROWSER_GENERAL_SETTINGS.privateModeThemeEnabled,
      enhancedTrackingProtectionEnabled: typeof settings?.enhancedTrackingProtectionEnabled === 'boolean'
        ? settings.enhancedTrackingProtectionEnabled
        : DEFAULT_BROWSER_GENERAL_SETTINGS.enhancedTrackingProtectionEnabled
    };
  }

  private normalizeCookiePolicySettings(settings: BrowserCookiePolicySettings | undefined): BrowserCookiePolicySettings {
    return {
      acceptCookies: typeof settings?.acceptCookies === 'boolean'
        ? settings.acceptCookies
        : DEFAULT_BROWSER_COOKIE_POLICY_SETTINGS.acceptCookies,
      acceptThirdPartyCookies: typeof settings?.acceptThirdPartyCookies === 'boolean'
        ? settings.acceptThirdPartyCookies
        : DEFAULT_BROWSER_COOKIE_POLICY_SETTINGS.acceptThirdPartyCookies
    };
  }

  private normalizeStartupRestorePolicy(
    value: BrowserStartupRestorePolicy | string | undefined
  ): BrowserStartupRestorePolicy {
    if (value === 'open_home') {
      return 'open_home';
    }
    return DEFAULT_BROWSER_GENERAL_SETTINGS.startupRestorePolicy;
  }

  private normalizeTabAutoClosePolicy(
    value: BrowserTabAutoClosePolicy | string | undefined
  ): BrowserTabAutoClosePolicy {
    if (value === 'after_15_days' ||
      value === 'after_7_days' ||
      value === 'after_3_days' ||
      value === 'after_1_day' ||
      value === 'on_app_exit') {
      return value;
    }
    return DEFAULT_BROWSER_GENERAL_SETTINGS.tabAutoClosePolicy;
  }

  private normalizePrivateTabRestorePolicy(
    value: BrowserPrivateTabRestorePolicy | string | undefined
  ): BrowserPrivateTabRestorePolicy {
    if (value === 'restore_private_tabs') {
      return 'restore_private_tabs';
    }
    return DEFAULT_BROWSER_GENERAL_SETTINGS.privateTabRestorePolicy;
  }

  private normalizeRecentLimit(value: number | undefined, defaultValue: number): number {
    const numberValue = Number(value);
    if (!Number.isFinite(numberValue)) {
      return defaultValue;
    }
    return Math.min(Math.max(Math.floor(numberValue), 1), 24);
  }

  private normalizeExperimentSettings(settings: BrowserExperimentSettings | undefined): BrowserExperimentSettings {
    const normalizedProxy = this.normalizeAppProxySettings(settings?.appProxy);
    const normalizedProfiles = this.buildNormalizedAppProxyProfiles(settings, normalizedProxy);
    const normalizedActiveProfileId = this.normalizeAppProxyActiveProfileId(
      settings?.appProxyActiveProfileId,
      normalizedProfiles
    );
    const effectiveProxyProfile = this.findAppProxyProfileById(normalizedProfiles, normalizedActiveProfileId);
    const effectiveProxyEnabled = typeof settings?.appProxyEnabled === 'boolean'
      ? settings.appProxyEnabled
      : DEFAULT_BROWSER_EXPERIMENT_SETTINGS.appProxyEnabled;
    const effectiveProxySettings = effectiveProxyProfile?.settings ?? normalizedProxy;
    return {
      pauseWebAnimationsDuringScroll: typeof settings?.pauseWebAnimationsDuringScroll === 'boolean'
        ? settings.pauseWebAnimationsDuringScroll
        : DEFAULT_BROWSER_EXPERIMENT_SETTINGS.pauseWebAnimationsDuringScroll,
      reduceMediaMotionDuringScroll: typeof settings?.reduceMediaMotionDuringScroll === 'boolean'
        ? settings.reduceMediaMotionDuringScroll
        : DEFAULT_BROWSER_EXPERIMENT_SETTINGS.reduceMediaMotionDuringScroll,
      strengthenAdBlockingForSmoothScroll: typeof settings?.strengthenAdBlockingForSmoothScroll === 'boolean'
        ? settings.strengthenAdBlockingForSmoothScroll
        : DEFAULT_BROWSER_EXPERIMENT_SETTINGS.strengthenAdBlockingForSmoothScroll,
      pullRefreshEnabled: resolveExperimentPullRefreshEnabled(
        settings,
        DEFAULT_BROWSER_EXPERIMENT_SETTINGS.pullRefreshEnabled
      ),
      forceEnableWebZoom: typeof settings?.forceEnableWebZoom === 'boolean'
        ? settings.forceEnableWebZoom
        : DEFAULT_BROWSER_EXPERIMENT_SETTINGS.forceEnableWebZoom,
      smartGripTabsActionsEnabled: typeof settings?.smartGripTabsActionsEnabled === 'boolean'
        ? settings.smartGripTabsActionsEnabled
        : DEFAULT_BROWSER_EXPERIMENT_SETTINGS.smartGripTabsActionsEnabled,
      webVideoTakeoverEnabled: typeof settings?.webVideoTakeoverEnabled === 'boolean'
        ? settings.webVideoTakeoverEnabled
        : DEFAULT_BROWSER_EXPERIMENT_SETTINGS.webVideoTakeoverEnabled,
      novelModeEnabled: typeof settings?.novelModeEnabled === 'boolean'
        ? settings.novelModeEnabled
        : DEFAULT_BROWSER_EXPERIMENT_SETTINGS.novelModeEnabled,
      novelAutoTakeoverEnabled: typeof settings?.novelAutoTakeoverEnabled === 'boolean'
        ? settings.novelAutoTakeoverEnabled
        : DEFAULT_BROWSER_EXPERIMENT_SETTINGS.novelAutoTakeoverEnabled,
      appProxyActiveProfileId: normalizedActiveProfileId,
      appProxyProfiles: normalizedProfiles,
      appProxyEnabled: effectiveProxyEnabled,
      appProxy: effectiveProxySettings
    };
  }

  private normalizeAppProxySettings(settings: BrowserAppProxySettings | undefined): BrowserAppProxySettings {
    return {
      scheme: this.normalizeAppProxyScheme(settings?.scheme),
      host: this.normalizeShortText(settings?.host, DEFAULT_BROWSER_APP_PROXY_SETTINGS.host, 180),
      port: this.normalizePort(settings?.port),
      username: this.normalizeShortText(settings?.username, DEFAULT_BROWSER_APP_PROXY_SETTINGS.username, 180),
      password: this.normalizeShortText(settings?.password, DEFAULT_BROWSER_APP_PROXY_SETTINGS.password, 256),
      bypassHosts: this.normalizeShortText(
        settings?.bypassHosts,
        DEFAULT_BROWSER_APP_PROXY_SETTINGS.bypassHosts,
        500
      ),
      updatedAt: this.normalizeNonNegativeTimestamp(settings?.updatedAt)
    };
  }

  private normalizeAppProxyProfiles(
    profiles: BrowserAppProxyProfile[] | undefined
  ): BrowserAppProxyProfile[] {
    if (!Array.isArray(profiles) || profiles.length <= 0) {
      return [];
    }
    const result: BrowserAppProxyProfile[] = [];
    const seenIds: Record<string, boolean> = {};
    for (let index = 0; index < profiles.length; index += 1) {
      const profile = profiles[index];
      const id = this.normalizeShortText(profile?.id, '', 80);
      if (id.length <= 0 || seenIds[id]) {
        continue;
      }
      seenIds[id] = true;
      result.push({
        id: id,
        name: this.normalizeShortText(profile?.name, '未命名代理', 80),
        settings: this.normalizeAppProxySettings(profile?.settings),
        createdAt: this.normalizeNonNegativeTimestamp(profile?.createdAt),
        updatedAt: this.normalizeNonNegativeTimestamp(profile?.updatedAt)
      });
    }
    return result;
  }

  private buildNormalizedAppProxyProfiles(
    settings: BrowserExperimentSettings | undefined,
    normalizedProxy: BrowserAppProxySettings
  ): BrowserAppProxyProfile[] {
    const normalizedProfiles = this.normalizeAppProxyProfiles(settings?.appProxyProfiles);
    if (normalizedProfiles.length > 0) {
      return normalizedProfiles;
    }
    const hasLegacyProxyContent = normalizedProxy.host.trim().length > 0 ||
      normalizedProxy.port > 0 ||
      normalizedProxy.username.trim().length > 0 ||
      normalizedProxy.password.trim().length > 0;
    if (!hasLegacyProxyContent) {
      return [];
    }
    return [{
      id: 'legacy-imported-proxy',
      name: '已导入代理',
      settings: normalizedProxy,
      createdAt: normalizedProxy.updatedAt,
      updatedAt: normalizedProxy.updatedAt
    }];
  }

  private normalizeAppProxyActiveProfileId(
    value: string | undefined,
    profiles: BrowserAppProxyProfile[]
  ): string {
    const normalized = this.normalizeShortText(value, '', 80);
    if (normalized.length > 0 && this.findAppProxyProfileById(profiles, normalized) !== undefined) {
      return normalized;
    }
    if (profiles.length > 0) {
      return profiles[0].id;
    }
    return '';
  }

  private findAppProxyProfileById(
    profiles: BrowserAppProxyProfile[],
    profileId: string
  ): BrowserAppProxyProfile | undefined {
    for (let index = 0; index < profiles.length; index += 1) {
      const profile = profiles[index];
      if (profile.id === profileId) {
        return profile;
      }
    }
    return undefined;
  }

  private normalizeAppProxyScheme(value: BrowserAppProxyScheme | string | undefined): BrowserAppProxyScheme {
    if (value === 'https' || value === 'socks5') {
      return value;
    }
    return DEFAULT_BROWSER_APP_PROXY_SETTINGS.scheme;
  }

  private normalizePort(value: number | undefined): number {
    const numberValue = Number(value);
    if (!Number.isFinite(numberValue)) {
      return DEFAULT_BROWSER_APP_PROXY_SETTINGS.port;
    }
    return Math.min(Math.max(Math.floor(numberValue), 0), 65535);
  }

  private normalizeShortText(value: string | undefined, defaultValue: string, maxLength: number): string {
    if (typeof value !== 'string') {
      return defaultValue;
    }
    return value.trim().slice(0, maxLength);
  }

  private normalizeNonNegativeTimestamp(value: number | undefined): number {
    const numberValue = Number(value);
    if (!Number.isFinite(numberValue) || numberValue < 0) {
      return 0;
    }
    return Math.floor(numberValue);
  }

  private normalizeDownloadSettings(settings: BrowserDownloadSettings | undefined): BrowserDownloadSettings {
    return {
      defaultLocation: this.normalizeDownloadLocation(settings?.defaultLocation),
      askBeforeDownload: typeof settings?.askBeforeDownload === 'boolean'
        ? settings.askBeforeDownload
        : DEFAULT_BROWSER_DOWNLOAD_SETTINGS.askBeforeDownload,
      allowCellularDownloads: typeof settings?.allowCellularDownloads === 'boolean'
        ? settings.allowCellularDownloads
        : DEFAULT_BROWSER_DOWNLOAD_SETTINGS.allowCellularDownloads,
      autoResumeAfterRestart: typeof settings?.autoResumeAfterRestart === 'boolean'
        ? settings.autoResumeAfterRestart
        : DEFAULT_BROWSER_DOWNLOAD_SETTINGS.autoResumeAfterRestart,
      hlsSegmentConcurrency: this.normalizeHlsSegmentConcurrency(settings?.hlsSegmentConcurrency),
      autoClearPolicy: this.normalizeDownloadAutoClearPolicy(settings?.autoClearPolicy),
      privateFilePolicy: this.normalizePrivateDownloadFilePolicy(settings?.privateFilePolicy),
      privateRecordPolicy: this.normalizePrivateDownloadRecordPolicy(settings?.privateRecordPolicy)
    };
  }

  private normalizeToolbarLayoutSettings(settings: BrowserToolbarLayoutSettings | undefined): BrowserToolbarLayoutSettings {
    const fallbackActionIds = DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS.primaryActionIds.concat(
      DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS.secondaryActionIds
    );
    const hasStoredActionIds = Array.isArray(settings?.primaryActionIds) || Array.isArray(settings?.secondaryActionIds);
    const storedActionIds = hasStoredActionIds ?
      (settings?.primaryActionIds ?? []).concat(settings?.secondaryActionIds ?? []) :
      fallbackActionIds;
    const primaryActionIds = this.normalizeToolbarActionIdList(
      storedActionIds,
      fallbackActionIds,
      BROWSER_TOOLBAR_CONFIGURABLE_ACTION_IDS.length
    );
    const missingActionIds = BROWSER_TOOLBAR_CONFIGURABLE_ACTION_IDS.filter((actionId: string) => {
      return !primaryActionIds.includes(actionId);
    });
    const normalizedActionIds = this.insertNewToolbarFindAction(
      primaryActionIds,
      missingActionIds
    );
    return {
      primaryActionIds: normalizedActionIds,
      secondaryActionIds: [],
      leadingSlotActionId: this.normalizeToolbarSlotActionId(settings?.leadingSlotActionId),
      menuSlotActionId: this.normalizeToolbarSlotActionId(settings?.menuSlotActionId),
      refreshSlotActionId: this.normalizeToolbarSlotActionId(settings?.refreshSlotActionId),
      tabsSlotActionId: this.normalizeToolbarSlotActionId(settings?.tabsSlotActionId),
      leadingSlotLongPressActionId: this.normalizeToolbarInteractionActionId(
        settings?.leadingSlotLongPressActionId,
        'none',
        true
      ),
      menuSlotLongPressActionId: this.normalizeToolbarInteractionActionId(
        settings?.menuSlotLongPressActionId,
        'none',
        true
      ),
      refreshSlotLongPressActionId: this.normalizeToolbarInteractionActionId(
        settings?.refreshSlotLongPressActionId,
        'none',
        true
      ),
      tabsSlotLongPressActionId: this.normalizeToolbarInteractionActionId(
        settings?.tabsSlotLongPressActionId,
        'none',
        true
      ),
      leadingSlotSwipeUpActionId: this.normalizeToolbarInteractionActionId(
        settings?.leadingSlotSwipeUpActionId,
        'home',
        true
      ),
      tabsSlotSwipeUpActionId: this.normalizeToolbarInteractionActionId(
        settings?.tabsSlotSwipeUpActionId,
        'home',
        true
      ),
      updatedAt: this.normalizeNonNegativeTimestamp(settings?.updatedAt)
    };
  }

  private normalizeToolbarSlotActionId(actionId: string | undefined): string {
    const normalizedActionId = String(actionId ?? '').trim();
    if (normalizedActionId === 'none') {
      return normalizedActionId;
    }
    return this.isToolbarInteractionActionId(normalizedActionId) ? normalizedActionId : '';
  }

  private normalizeToolbarInteractionActionId(
    actionId: string | undefined,
    fallbackActionId: string,
    allowNone: boolean
  ): string {
    const normalizedActionId = String(actionId ?? '').trim();
    if (allowNone && normalizedActionId === 'none') {
      return normalizedActionId;
    }
    return this.isToolbarInteractionActionId(normalizedActionId) ? normalizedActionId : fallbackActionId;
  }

  private isToolbarInteractionActionId(actionId: string): boolean {
    return BROWSER_TOOLBAR_CORE_ACTION_IDS.includes(actionId) ||
      BROWSER_TOOLBAR_CONFIGURABLE_ACTION_IDS.includes(actionId);
  }

  private insertNewToolbarFindAction(primaryActionIds: string[], missingActionIds: string[]): string[] {
    const remainingMissingActionIds = missingActionIds.filter((actionId: string) => actionId !== 'find');
    const normalizedActionIds = primaryActionIds.concat(remainingMissingActionIds);
    if (!missingActionIds.includes('find')) {
      return normalizedActionIds;
    }
    const textZoomIndex = normalizedActionIds.indexOf('textZoom');
    if (textZoomIndex < 0) {
      normalizedActionIds.push('find');
      return normalizedActionIds;
    }
    normalizedActionIds.splice(textZoomIndex + 1, 0, 'find');
    return normalizedActionIds;
  }

  private normalizeToolbarActionIdList(
    actionIds: string[] | undefined,
    fallback: string[],
    maxCount: number
  ): string[] {
    const source = Array.isArray(actionIds) ? actionIds : fallback;
    const normalized: string[] = [];
    source.forEach((rawActionId: string) => {
      const actionId = String(rawActionId ?? '').trim();
      if (!BROWSER_TOOLBAR_CONFIGURABLE_ACTION_IDS.includes(actionId)) {
        return;
      }
      if (normalized.includes(actionId)) {
        return;
      }
      if (normalized.length >= maxCount) {
        return;
      }
      normalized.push(actionId);
    });
    return normalized;
  }

  private normalizeSitePermissionDefaultSettings(
    settings: SitePermissionDefaultSettings | undefined
  ): SitePermissionDefaultSettings {
    return {
      camera: this.normalizeSitePermissionRule(settings?.camera),
      microphone: this.normalizeSitePermissionRule(settings?.microphone),
      location: this.normalizeSitePermissionRule(settings?.location),
      sensor: this.normalizeSitePermissionRule(settings?.sensor),
      clipboard: this.normalizeSitePermissionRule(settings?.clipboard)
    };
  }

  private normalizeExternalNavigationSettings(
    settings: ExternalNavigationSettings | undefined
  ): ExternalNavigationSettings {
    return {
      appOpenPolicy: this.normalizeExternalNavigationAppOpenPolicy(settings?.appOpenPolicy),
      suppressAfterCancelMs: this.normalizePositiveInt(
        settings?.suppressAfterCancelMs ?? DEFAULT_EXTERNAL_NAVIGATION_SETTINGS.suppressAfterCancelMs,
        DEFAULT_EXTERNAL_NAVIGATION_SETTINGS.suppressAfterCancelMs,
        DEFAULT_EXTERNAL_NAVIGATION_SETTINGS.suppressAfterCancelMs
      ),
      siteRules: this.normalizeExternalNavigationSiteRules(settings?.siteRules)
    };
  }

  private normalizeExternalNavigationSiteRules(
    siteRules: ExternalNavigationSiteRule[] | undefined
  ): ExternalNavigationSiteRule[] {
    if (!Array.isArray(siteRules)) {
      return [];
    }
    const normalizedRules: ExternalNavigationSiteRule[] = [];
    siteRules.forEach((rule: ExternalNavigationSiteRule) => {
      if (typeof rule.siteKey !== 'string' || typeof rule.displayHost !== 'string' ||
        typeof rule.primaryOrigin !== 'string') {
        return;
      }
      const identity = this.siteIdentityService.resolve(rule.primaryOrigin);
      const policy = this.normalizeExternalNavigationAppOpenPolicy(rule.policy);
      if (identity.primaryOrigin.length <= 0 || identity.siteKey.length <= 0 ||
        identity.displayHost.length <= 0 || policy === 'ask') {
        return;
      }
      normalizedRules.push({
        profileId: normalizeBrowserProfileId(rule.profileId ?? DEFAULT_BROWSER_PROFILE_ID),
        origin: identity.primaryOrigin,
        siteKey: identity.siteKey,
        displayHost: identity.displayHost,
        primaryOrigin: identity.primaryOrigin,
        policy: policy,
        updatedAt: Number(rule.updatedAt) > 0 ? Number(rule.updatedAt) : Date.now()
      });
    });
    return normalizedRules.slice(-120);
  }

  private normalizeExternalNavigationAppOpenPolicy(
    value: ExternalNavigationAppOpenPolicy | string | undefined
  ): ExternalNavigationAppOpenPolicy {
    if (value === 'block' || value === 'allow') {
      return value;
    }
    return 'ask';
  }

  normalizeReaderModePreferencesForPersistence(
    preferences: ReaderModePreferences | undefined
  ): ReaderModePreferences {
    return this.normalizeReaderModePreferences(preferences);
  }

  private normalizeReaderModePreferences(preferences: ReaderModePreferences | undefined): ReaderModePreferences {
    return {
      fontSize: this.clampNumber(preferences?.fontSize ?? DEFAULT_READER_MODE_PREFERENCES.fontSize,
        DEFAULT_READER_MODE_PREFERENCES.fontSize, 15, 26),
      theme: this.normalizeReaderModeTheme(preferences?.theme),
      lineHeight: this.normalizeReaderModeLineHeight(preferences?.lineHeight),
      pageWidth: this.normalizeReaderModePageWidth(preferences?.pageWidth),
      brightnessMode: this.normalizeReaderModeBrightnessMode(preferences?.brightnessMode),
      brightnessPercent: this.clampNumber(preferences?.brightnessPercent ??
        DEFAULT_READER_MODE_PREFERENCES.brightnessPercent,
      DEFAULT_READER_MODE_PREFERENCES.brightnessPercent, 20, 100),
      pageMode: this.normalizeReadingPageMode(preferences?.pageMode)
    };
  }

  private normalizeReaderModeBrightnessMode(
    value: ReaderModeBrightnessMode | string | undefined
  ): ReaderModeBrightnessMode {
    return value === 'manual' ? 'manual' : 'system';
  }

  private normalizeReaderModeTheme(value: ReaderModeTheme | string | undefined): ReaderModeTheme {
    if (value === 'light' || value === 'paper' || value === 'dark' || value === 'sepia' ||
      value === 'sage' || value === 'charcoal' || value === 'system') {
      return value;
    }
    return DEFAULT_READER_MODE_PREFERENCES.theme;
  }

  private normalizeReaderModeLineHeight(
    value: ReaderModeLineHeight | string | undefined
  ): ReaderModeLineHeight {
    if (value === 'compact' || value === 'comfortable' || value === 'loose') {
      return value;
    }
    return DEFAULT_READER_MODE_PREFERENCES.lineHeight;
  }

  private normalizeReaderModePageWidth(value: ReaderModePageWidth | string | undefined): ReaderModePageWidth {
    if (value === 'narrow' || value === 'standard' || value === 'wide') {
      return value;
    }
    return DEFAULT_READER_MODE_PREFERENCES.pageWidth;
  }

  private normalizeReadingPageMode(value: string | undefined): ReadingPageMode {
    if (value === 'horizontal' || value === 'horizontalFast' || value === 'vertical') {
      return value;
    }
    return DEFAULT_READER_MODE_PREFERENCES.pageMode;
  }

  private normalizeDownloadLocation(value: BrowserDownloadLocation | string | undefined): BrowserDownloadLocation {
    return value === 'system_downloads' ? 'system_downloads' : DEFAULT_BROWSER_DOWNLOAD_SETTINGS.defaultLocation;
  }

  private normalizeDownloadAutoClearPolicy(
    value: BrowserDownloadAutoClearPolicy | string | undefined
  ): BrowserDownloadAutoClearPolicy {
    if (value === 'clear_completed' || value === 'clear_completed_and_failed') {
      return value;
    }
    return DEFAULT_BROWSER_DOWNLOAD_SETTINGS.autoClearPolicy;
  }

  private normalizeHlsSegmentConcurrency(
    value: BrowserHlsSegmentConcurrency | string | undefined
  ): BrowserHlsSegmentConcurrency {
    if (value === '4' || value === '8' || value === '16') {
      return value;
    }
    return DEFAULT_BROWSER_DOWNLOAD_SETTINGS.hlsSegmentConcurrency;
  }

  private normalizePrivateDownloadFilePolicy(
    value: BrowserPrivateDownloadFilePolicy | string | undefined
  ): BrowserPrivateDownloadFilePolicy {
    if (value === 'session_temp_only') {
      return value;
    }
    return DEFAULT_BROWSER_DOWNLOAD_SETTINGS.privateFilePolicy;
  }

  private normalizePrivateDownloadRecordPolicy(
    value: BrowserPrivateDownloadRecordPolicy | string | undefined
  ): BrowserPrivateDownloadRecordPolicy {
    if (value === 'clear_after_export') {
      return value;
    }
    return DEFAULT_BROWSER_DOWNLOAD_SETTINGS.privateRecordPolicy;
  }



  listSitePermissionSettings(profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID): SitePermissionSettings[] {
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    return this.cachedSitePermissionSettings.filter((settings: SitePermissionSettings) => {
      return settings.profileId === normalizedProfileId;
    });
  }

  async removeSitePermissionSettings(
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<void> {
    const normalizedOrigin = this.normalizeOrigin(origin);
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    this.cachedSitePermissionSettings = this.cachedSitePermissionSettings.filter((settings: SitePermissionSettings) => {
      return settings.primaryOrigin !== normalizedOrigin || settings.profileId !== normalizedProfileId;
    });
    await this.storageAdapter.writeSitePermissionSettings(this.cachedSitePermissionSettings);
  }

  async clearAllSitePermissionSettings(profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID): Promise<void> {
    const normalizedProfileId = normalizeBrowserProfileId(profileId);
    this.cachedSitePermissionSettings = this.cachedSitePermissionSettings.filter((settings: SitePermissionSettings) => {
      return settings.profileId !== normalizedProfileId;
    });
    await this.storageAdapter.writeSitePermissionSettings(this.cachedSitePermissionSettings);
  }

  async clearAllSitePermissionSettingsForAllProfiles(): Promise<void> {
    if (this.cachedSitePermissionSettings.length === 0) {
      return;
    }
    this.cachedSitePermissionSettings = [];
    await this.storageAdapter.writeSitePermissionSettings(this.cachedSitePermissionSettings);
  }

  private normalizeSearchEngineId(value: string): SearchEngineId {
    if (SEARCH_ENGINE_OPTIONS.some((option: SearchEngineOption): boolean => option.id === value)) {
      return value;
    }

    return DEFAULT_SEARCH_ENGINE_ID;
  }

  private normalizeSearchSuggestionPreferences(
    value: SearchSuggestionPreferences | undefined
  ): SearchSuggestionPreferences {
    return {
      regularEnabled: typeof value?.regularEnabled === 'boolean'
        ? value.regularEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.regularEnabled,
      privateEnabled: typeof value?.privateEnabled === 'boolean'
        ? value.privateEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.privateEnabled,
      openTabsEnabled: typeof value?.openTabsEnabled === 'boolean'
        ? value.openTabsEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.openTabsEnabled,
      bookmarksEnabled: typeof value?.bookmarksEnabled === 'boolean'
        ? value.bookmarksEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.bookmarksEnabled,
      shortcutsEnabled: typeof value?.shortcutsEnabled === 'boolean'
        ? value.shortcutsEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.shortcutsEnabled,
      historyEnabled: typeof value?.historyEnabled === 'boolean'
        ? value.historyEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.historyEnabled,
      remoteEnabled: typeof value?.remoteEnabled === 'boolean'
        ? value.remoteEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.remoteEnabled
    };
  }

  private normalizeRetentionSettings(settings: BrowserRetentionSettings): BrowserRetentionSettings {
    const profileId = this.normalizeRetentionProfileId(settings.profileId);
    const deviceTierHint = this.normalizeRetentionDeviceTierHint(settings.deviceTierHint);
    return buildBrowserRetentionSettingsForProfile(profileId, deviceTierHint);
  }

  private normalizeHistoryRetentionSettings(settings: HistoryRetentionSettings): HistoryRetentionSettings {
    const fallback = DEFAULT_HISTORY_RETENTION_SETTINGS;
    if (settings.enabled === false) {
      return {
        enabled: false,
        maxAgeDays: 0,
        maxRows: 0
      };
    }
    return {
      enabled: true,
      maxAgeDays: this.clampNumber(
        settings.maxAgeDays,
        fallback.maxAgeDays,
        HISTORY_RETENTION_MIN_DAYS,
        HISTORY_RETENTION_MAX_DAYS
      ),
      maxRows: this.clampNumber(
        this.normalizeLegacyHistoryRetentionRows(settings),
        fallback.maxRows,
        HISTORY_RETENTION_MIN_ROWS,
        HISTORY_RETENTION_MAX_ROWS
      )
    };
  }

  private normalizeLegacyHistoryRetentionRows(settings: HistoryRetentionSettings): number {
    if (settings.maxAgeDays === 90 && settings.maxRows === 1000) {
      return 10000;
    }
    if (settings.maxAgeDays === 30 && settings.maxRows === 500) {
      return 3000;
    }
    return settings.maxRows;
  }

  private normalizeRetentionProfileId(profileId: BrowserRetentionProfileId): BrowserRetentionProfileId {
    if (profileId === 'memory_saver' || profileId === 'keep_more_tabs') {
      return profileId;
    }
    return 'balanced';
  }

  private normalizeRetentionDeviceTierHint(deviceTierHint: BrowserDeviceTierHint): BrowserDeviceTierHint {
    if (
      deviceTierHint === 'low_memory' ||
      deviceTierHint === 'balanced_device' ||
      deviceTierHint === 'high_memory' ||
      deviceTierHint === 'ultra_memory'
    ) {
      return deviceTierHint;
    }
    return 'auto';
  }

  private createDefaultSitePermissionSettings(origin: string, profileId: BrowserProfileId): SitePermissionSettings {
    const defaults = this.cachedPreferences.sitePermissionDefaults;
    const identity = this.siteIdentityService.resolve(origin);
    return {
      profileId: profileId,
      origin: identity.primaryOrigin,
      siteKey: identity.siteKey,
      displayHost: identity.displayHost,
      primaryOrigin: identity.primaryOrigin,
      camera: defaults.camera,
      microphone: defaults.microphone,
      location: defaults.location,
      sensor: defaults.sensor,
      clipboard: defaults.clipboard,
      updatedAt: 0
    };
  }

  private isDefaultSitePermissionSettings(settings: SitePermissionSettings): boolean {
    const defaults = this.cachedPreferences.sitePermissionDefaults;
    return settings.camera === defaults.camera && settings.microphone === defaults.microphone &&
      settings.location === defaults.location && settings.sensor === defaults.sensor &&
      settings.clipboard === defaults.clipboard;
  }

  private normalizeSitePermissionSettings(settings: SitePermissionSettings[]): SitePermissionSettings[] {
    if (!Array.isArray(settings)) {
      return [];
    }
    return settings
      .filter((item: SitePermissionSettings) => typeof item.origin === 'string' && item.origin.trim().length > 0)
      .filter((item: SitePermissionSettings) => {
        return typeof item.siteKey === 'string' && typeof item.displayHost === 'string' &&
          typeof item.primaryOrigin === 'string';
      })
      .map((item: SitePermissionSettings) => {
        const identity = this.siteIdentityService.resolve(item.primaryOrigin);
        const normalizedItem: SitePermissionSettings = {
          profileId: normalizeBrowserProfileId(item.profileId),
          origin: identity.primaryOrigin,
          siteKey: identity.siteKey,
          displayHost: identity.displayHost,
          primaryOrigin: identity.primaryOrigin,
          camera: this.normalizeSitePermissionRule(item.camera),
          microphone: this.normalizeSitePermissionRule(item.microphone),
          location: this.normalizeSitePermissionRule(item.location),
          sensor: this.normalizeSitePermissionRule(item.sensor),
          clipboard: this.normalizeSitePermissionRule(item.clipboard),
          updatedAt: Number(item.updatedAt) > 0 ? Number(item.updatedAt) : 0
        };
        return normalizedItem;
      })
      .filter((item: SitePermissionSettings) => {
        return item.origin.length > 0 && item.siteKey.length > 0 &&
          item.displayHost.length > 0 && item.primaryOrigin.length > 0;
      });
  }

  private normalizeSitePermissionRule(rule: SitePermissionRule | string | undefined): SitePermissionRule {
    if (rule === 'allow' || rule === 'block') {
      return rule;
    }
    return 'ask';
  }

  private normalizeOrigin(origin: string): string {
    return this.siteIdentityService.resolve(origin).primaryOrigin;
  }

  private mergeCachedPreferences(patch: Partial<BrowserPreferences>): void {
    this.cachedPreferences = {
      appServiceMode: patch.appServiceMode ?? this.cachedPreferences.appServiceMode,
      searchEngineId: patch.searchEngineId ?? this.cachedPreferences.searchEngineId,
      searchSuggestions: patch.searchSuggestions ?? this.cachedPreferences.searchSuggestions,
      homeLayout: patch.homeLayout ?? this.cachedPreferences.homeLayout,
      wallpaperEnabled: patch.wallpaperEnabled ?? this.cachedPreferences.wallpaperEnabled,
      bookmarkSyncEnabled: patch.bookmarkSyncEnabled ?? this.cachedPreferences.bookmarkSyncEnabled,
      historySyncEnabled: patch.historySyncEnabled ?? this.cachedPreferences.historySyncEnabled,
      themeMode: patch.themeMode ?? this.cachedPreferences.themeMode,
      appearance: patch.appearance ?? this.cachedPreferences.appearance,
      general: patch.general ?? this.cachedPreferences.general,
      cookiePolicy: patch.cookiePolicy ?? this.cachedPreferences.cookiePolicy,
      experiments: patch.experiments ?? this.cachedPreferences.experiments,
      readerMode: patch.readerMode ?? this.cachedPreferences.readerMode,
      downloads: patch.downloads ?? this.cachedPreferences.downloads,
      toolbarLayout: patch.toolbarLayout ?? this.cachedPreferences.toolbarLayout,
      sitePermissionDefaults: patch.sitePermissionDefaults ?? this.cachedPreferences.sitePermissionDefaults,
      externalNavigation: patch.externalNavigation ?? this.cachedPreferences.externalNavigation,
      retention: patch.retention ?? this.cachedPreferences.retention,
      historyRetention: patch.historyRetention ?? this.cachedPreferences.historyRetention
    };
  }

  private logExperimentSettingsUpdate(
    previousSettings: BrowserExperimentSettings,
    nextSettings: BrowserExperimentSettings
  ): void {
    if (previousSettings.webVideoTakeoverEnabled === nextSettings.webVideoTakeoverEnabled &&
      previousSettings.appProxyEnabled === nextSettings.appProxyEnabled &&
      previousSettings.pullRefreshEnabled === nextSettings.pullRefreshEnabled) {
      return;
    }
    hilog.info(
      PREFERENCES_LOG_DOMAIN,
      PREFERENCES_LOG_TAG,
      'experiment settings update takeover %{public}s->%{public}s proxy %{public}s->%{public}s pullRefresh %{public}s->%{public}s caller=%{public}s',
      previousSettings.webVideoTakeoverEnabled ? 'true' : 'false',
      nextSettings.webVideoTakeoverEnabled ? 'true' : 'false',
      previousSettings.appProxyEnabled ? 'true' : 'false',
      nextSettings.appProxyEnabled ? 'true' : 'false',
      previousSettings.pullRefreshEnabled ? 'true' : 'false',
      nextSettings.pullRefreshEnabled ? 'true' : 'false',
      this.buildExperimentSettingsUpdateCaller()
    );
  }

  private buildExperimentSettingsUpdateCaller(): string {
    try {
      const stack = new Error('experiment_settings_update').stack ?? '';
      const lines = stack.split('\n');
      const selectedLines: string[] = [];
      for (let index = 0; index < lines.length && selectedLines.length < 3; index++) {
        const line = lines[index].trim();
        if (line.length === 0 ||
          line.indexOf('experiment_settings_update') >= 0 ||
          line.indexOf('PreferencesRepository') >= 0) {
          continue;
        }
        selectedLines.push(this.compactDiagnosticText(line, 180));
      }
      return selectedLines.length > 0 ? selectedLines.join(' | ') : 'unknown';
    } catch (_error) {
      return 'unavailable';
    }
  }

  private compactDiagnosticText(value: string, maxLength: number): string {
    if (value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }

  private notifyChanged(
    scope: BrowserPreferencesChangeScope,
    origin: BrowserPreferencesChangeOrigin = 'local'
  ): void {
    Object.keys(this.listeners).forEach((key: string) => {
      const listener = this.listeners[key];
      if (listener !== undefined) {
        listener(this.cachedPreferences, scope, origin);
      }
    });
  }

  private enqueueStorageWrite(write: () => Promise<void>): Promise<void> {
    const nextWrite = this.pendingStorageWrite.then(() => write());
    this.pendingStorageWrite = nextWrite.catch((_error: Error) => {
    });
    return nextWrite;
  }

  private normalizePositiveInt(value: number, fallback: number, defaultValue: number): number {
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric <= 0) {
      return fallback > 0 ? fallback : defaultValue;
    }
    return Math.round(numeric);
  }

  private clampNumber(value: number, fallback: number, min: number, max: number): number {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) {
      return fallback;
    }
    return Math.min(max, Math.max(min, Math.round(numeric)));
  }
}
