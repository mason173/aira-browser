import { preferences } from '@kit.ArkData';
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
  BrowserGeneralSettings,
  BrowserCookiePolicySettings,
  BrowserPrivateTabRestorePolicy,
  BrowserStartupRestorePolicy,
  BrowserTabAutoClosePolicy,
  BrowserAppProxyProfile,
  BrowserAppProxyScheme,
  BrowserAppProxySettings,
  BrowserExperimentSettings,
  BrowserDeviceTierHint,
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
  ExternalNavigationAppOpenPolicy,
  ExternalNavigationSettings,
  ExternalNavigationSiteRule,
  DEFAULT_BROWSER_PROFILE_ID,
  DEFAULT_SEARCH_ENGINE_ID,
  SEARCH_ENGINE_OPTIONS,
  SearchEngineId,
  SearchEngineOption,
  SearchSuggestionPreferences,
  SitePermissionDefaultSettings,
  SitePermissionRule,
  SitePermissionSettings,
  normalizeBrowserProfileId
} from '../../common/models/BrowserModels';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  DEFAULT_BROWSER_DOWNLOAD_SETTINGS,
  DEFAULT_HISTORY_RETENTION_SETTINGS,
  DEFAULT_EXTERNAL_NAVIGATION_SETTINGS,
  DEFAULT_BROWSER_APPEARANCE_SETTINGS,
  DEFAULT_BROWSER_GENERAL_SETTINGS,
  DEFAULT_BROWSER_COOKIE_POLICY_SETTINGS,
  DEFAULT_BROWSER_APP_PROXY_SETTINGS,
  DEFAULT_BROWSER_EXPERIMENT_SETTINGS,
  DEFAULT_BROWSER_RETENTION_SETTINGS,
  DEFAULT_READER_MODE_PREFERENCES,
  DEFAULT_BROWSER_APP_SERVICE_MODE,
  DEFAULT_SEARCH_SUGGESTION_PREFERENCES,
  DEFAULT_SITE_PERMISSION_DEFAULT_SETTINGS,
  DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS,
  resolveExperimentPullRefreshEnabled
} from './PreferencesRepository';
import { PreferencesStorageAdapter } from './PreferencesRepository';
import { SiteIdentityService } from '../../services/web/SiteIdentityService';
import { ReadingSurfaceAppearance } from '../../features/reading/ReadingSurfaceModels';
import {
  sharedReadingAppearancePreferencesRepository
} from '../reading/ReadingAppearancePreferencesRepository';

interface ReaderModeBehaviorPreferencesRecord {
  pageMode: ReadingPageMode;
}

const PREFERENCES_NAME = 'aira_browser_preferences';
const APP_SERVICE_MODE_KEY = 'app_service_mode';
const SEARCH_ENGINE_KEY = 'search_engine_id';
const SEARCH_SUGGESTIONS_KEY = 'search_suggestions';
const THEME_MODE_KEY = 'theme_mode';
const APPEARANCE_SETTINGS_KEY = 'appearance_settings';
const GENERAL_SETTINGS_KEY = 'general_settings';
const COOKIE_POLICY_SETTINGS_KEY = 'cookie_policy_settings';
const EXPERIMENT_SETTINGS_KEY = 'experiment_settings';
const READER_MODE_PREFERENCES_KEY = 'reader_mode_preferences';
const DOWNLOAD_SETTINGS_KEY = 'download_settings';
const TOOLBAR_LAYOUT_SETTINGS_KEY = 'toolbar_layout_settings';
const SITE_PERMISSION_DEFAULTS_KEY = 'site_permission_defaults';
const EXTERNAL_NAVIGATION_SETTINGS_KEY = 'external_navigation_settings';
const RETENTION_SETTINGS_KEY = 'retention_settings';
const HISTORY_RETENTION_SETTINGS_KEY = 'history_retention_settings';
const SITE_PERMISSIONS_KEY = 'site_permissions';

export class ArkPreferencesStorageAdapter implements PreferencesStorageAdapter {
  private siteIdentityService: SiteIdentityService = new SiteIdentityService();

  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  async readAppServiceMode(defaultValue: BrowserAppServiceMode): Promise<BrowserAppServiceMode> {
    const store = await this.getStore();
    const value = store.getSync(APP_SERVICE_MODE_KEY, defaultValue);
    return this.normalizeAppServiceMode(String(value), defaultValue);
  }

  async writeAppServiceMode(mode: BrowserAppServiceMode): Promise<void> {
    const store = await this.getStore();
    store.putSync(APP_SERVICE_MODE_KEY, mode);
    store.flushSync();
  }

  async readSearchEngineId(defaultValue: SearchEngineId): Promise<SearchEngineId> {
    const store = await this.getStore();
    const value = store.getSync(SEARCH_ENGINE_KEY, defaultValue);
    return this.normalizeSearchEngineId(String(value), defaultValue);
  }

  async writeSearchEngineId(searchEngineId: SearchEngineId): Promise<void> {
    const store = await this.getStore();
    store.putSync(SEARCH_ENGINE_KEY, searchEngineId);
    store.flushSync();
  }

  async readSearchSuggestionPreferences(defaultValue: SearchSuggestionPreferences): Promise<SearchSuggestionPreferences> {
    const store = await this.getStore();
    const value = store.getSync(SEARCH_SUGGESTIONS_KEY, JSON.stringify(defaultValue));
    return this.parseSearchSuggestionPreferences(String(value), defaultValue);
  }

  async writeSearchSuggestionPreferences(preferences: SearchSuggestionPreferences): Promise<void> {
    const store = await this.getStore();
    store.putSync(SEARCH_SUGGESTIONS_KEY, JSON.stringify(preferences));
    store.flushSync();
  }

  async readThemeMode(defaultValue: BrowserThemeMode): Promise<BrowserThemeMode> {
    const store = await this.getStore();
    const value = store.getSync(THEME_MODE_KEY, defaultValue);
    return this.normalizeThemeMode(String(value), defaultValue);
  }

  async writeThemeMode(themeMode: BrowserThemeMode): Promise<void> {
    const store = await this.getStore();
    store.putSync(THEME_MODE_KEY, themeMode);
    store.flushSync();
  }

  async readAppearanceSettings(defaultValue: BrowserAppearanceSettings): Promise<BrowserAppearanceSettings> {
    const store = await this.getStore();
    const value = store.getSync(APPEARANCE_SETTINGS_KEY, JSON.stringify(defaultValue));
    return this.parseAppearanceSettings(String(value), defaultValue);
  }

  async writeAppearanceSettings(settings: BrowserAppearanceSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(APPEARANCE_SETTINGS_KEY, JSON.stringify(settings));
    await store.flush();
  }

  async readGeneralSettings(defaultValue: BrowserGeneralSettings): Promise<BrowserGeneralSettings> {
    const store = await this.getStore();
    const value = store.getSync(GENERAL_SETTINGS_KEY, JSON.stringify(defaultValue));
    return this.parseGeneralSettings(String(value), defaultValue);
  }

  async writeGeneralSettings(settings: BrowserGeneralSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(GENERAL_SETTINGS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async readCookiePolicySettings(defaultValue: BrowserCookiePolicySettings): Promise<BrowserCookiePolicySettings> {
    const store = await this.getStore();
    const value = store.getSync(COOKIE_POLICY_SETTINGS_KEY, JSON.stringify(defaultValue));
    return this.parseCookiePolicySettings(String(value), defaultValue);
  }

  async writeCookiePolicySettings(settings: BrowserCookiePolicySettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(COOKIE_POLICY_SETTINGS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async readExperimentSettings(defaultValue: BrowserExperimentSettings): Promise<BrowserExperimentSettings> {
    const store = await this.getStore();
    const value = store.getSync(EXPERIMENT_SETTINGS_KEY, JSON.stringify(defaultValue));
    return this.parseExperimentSettings(String(value), defaultValue);
  }

  async writeExperimentSettings(settings: BrowserExperimentSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(EXPERIMENT_SETTINGS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async readReaderModePreferences(defaultValue: ReaderModePreferences): Promise<ReaderModePreferences> {
    const store = await this.getStore();
    const value = store.getSync(READER_MODE_PREFERENCES_KEY, JSON.stringify(defaultValue));
    const legacyPreferences = this.parseReaderModePreferences(String(value), defaultValue);
    const appearance = await sharedReadingAppearancePreferencesRepository.load(
      this.buildReadingAppearance(legacyPreferences)
    );
    return this.mergeReadingAppearance(legacyPreferences, appearance);
  }

  async writeReaderModePreferences(preferences: ReaderModePreferences): Promise<void> {
    const store = await this.getStore();
    const behavior: ReaderModeBehaviorPreferencesRecord = {
      pageMode: preferences.pageMode
    };
    store.putSync(READER_MODE_PREFERENCES_KEY, JSON.stringify(behavior));
    await sharedReadingAppearancePreferencesRepository.save(this.buildReadingAppearance(preferences));
    await store.flush();
  }

  async readDownloadSettings(defaultValue: BrowserDownloadSettings): Promise<BrowserDownloadSettings> {
    const store = await this.getStore();
    const value = store.getSync(DOWNLOAD_SETTINGS_KEY, JSON.stringify(defaultValue));
    return this.parseDownloadSettings(String(value), defaultValue);
  }

  async writeDownloadSettings(settings: BrowserDownloadSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(DOWNLOAD_SETTINGS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async readToolbarLayoutSettings(defaultValue: BrowserToolbarLayoutSettings): Promise<BrowserToolbarLayoutSettings> {
    const store = await this.getStore();
    const value = store.getSync(TOOLBAR_LAYOUT_SETTINGS_KEY, JSON.stringify(defaultValue));
    return this.parseToolbarLayoutSettings(String(value), defaultValue);
  }

  async writeToolbarLayoutSettings(settings: BrowserToolbarLayoutSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(TOOLBAR_LAYOUT_SETTINGS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async readSitePermissionDefaultSettings(
    defaultValue: SitePermissionDefaultSettings
  ): Promise<SitePermissionDefaultSettings> {
    const store = await this.getStore();
    const value = store.getSync(SITE_PERMISSION_DEFAULTS_KEY, JSON.stringify(defaultValue));
    return this.parseSitePermissionDefaultSettings(String(value), defaultValue);
  }

  async writeSitePermissionDefaultSettings(settings: SitePermissionDefaultSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(SITE_PERMISSION_DEFAULTS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async readExternalNavigationSettings(
    defaultValue: ExternalNavigationSettings
  ): Promise<ExternalNavigationSettings> {
    const store = await this.getStore();
    const value = store.getSync(EXTERNAL_NAVIGATION_SETTINGS_KEY, JSON.stringify(defaultValue));
    return this.parseExternalNavigationSettings(String(value), defaultValue);
  }

  async writeExternalNavigationSettings(settings: ExternalNavigationSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(EXTERNAL_NAVIGATION_SETTINGS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async readRetentionSettings(defaultValue: BrowserRetentionSettings): Promise<BrowserRetentionSettings> {
    const store = await this.getStore();
    const value = store.getSync(RETENTION_SETTINGS_KEY, JSON.stringify(defaultValue));
    return this.parseRetentionSettings(String(value), defaultValue);
  }

  async writeRetentionSettings(settings: BrowserRetentionSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(RETENTION_SETTINGS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async readHistoryRetentionSettings(defaultValue: HistoryRetentionSettings): Promise<HistoryRetentionSettings> {
    const store = await this.getStore();
    const value = store.getSync(HISTORY_RETENTION_SETTINGS_KEY, JSON.stringify(defaultValue));
    return this.parseHistoryRetentionSettings(String(value), defaultValue);
  }

  async writeHistoryRetentionSettings(settings: HistoryRetentionSettings): Promise<void> {
    const store = await this.getStore();
    store.putSync(HISTORY_RETENTION_SETTINGS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async readSitePermissionSettings(): Promise<SitePermissionSettings[]> {
    const store = await this.getStore();
    const value = store.getSync(SITE_PERMISSIONS_KEY, '[]');
    return this.parseSitePermissionSettings(String(value));
  }

  async writeSitePermissionSettings(settings: SitePermissionSettings[]): Promise<void> {
    const store = await this.getStore();
    store.putSync(SITE_PERMISSIONS_KEY, JSON.stringify(settings));
    store.flushSync();
  }

  async flush(): Promise<void> {
    const store = await this.getStore();
    await store.flush();
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }

    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }

    return this.storePromise;
  }

  private normalizeSearchEngineId(value: string, defaultValue: SearchEngineId): SearchEngineId {
    if (SEARCH_ENGINE_OPTIONS.some((option: SearchEngineOption): boolean => option.id === value)) {
      return value;
    }

    return defaultValue.length > 0 ? defaultValue : DEFAULT_SEARCH_ENGINE_ID;
  }

  private normalizeAppServiceMode(value: string, defaultValue: BrowserAppServiceMode): BrowserAppServiceMode {
    if (value === 'basic' || value === 'full') {
      return value;
    }
    return defaultValue.length > 0 ? defaultValue : DEFAULT_BROWSER_APP_SERVICE_MODE;
  }

  private parseSearchSuggestionPreferences(
    value: string,
    defaultValue: SearchSuggestionPreferences = DEFAULT_SEARCH_SUGGESTION_PREFERENCES
  ): SearchSuggestionPreferences {
    try {
      const parsed = JSON.parse(value) as SearchSuggestionPreferences;
      return {
        regularEnabled: typeof parsed.regularEnabled === 'boolean'
          ? parsed.regularEnabled
          : defaultValue.regularEnabled,
        privateEnabled: typeof parsed.privateEnabled === 'boolean'
          ? parsed.privateEnabled
          : defaultValue.privateEnabled,
        openTabsEnabled: typeof parsed.openTabsEnabled === 'boolean'
          ? parsed.openTabsEnabled
          : defaultValue.openTabsEnabled,
        bookmarksEnabled: typeof parsed.bookmarksEnabled === 'boolean'
          ? parsed.bookmarksEnabled
          : defaultValue.bookmarksEnabled,
        shortcutsEnabled: typeof parsed.shortcutsEnabled === 'boolean'
          ? parsed.shortcutsEnabled
          : defaultValue.shortcutsEnabled,
        historyEnabled: typeof parsed.historyEnabled === 'boolean'
          ? parsed.historyEnabled
          : defaultValue.historyEnabled,
        remoteEnabled: typeof parsed.remoteEnabled === 'boolean'
          ? parsed.remoteEnabled
          : defaultValue.remoteEnabled
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private normalizeThemeMode(value: string, defaultValue: BrowserThemeMode): BrowserThemeMode {
    if (value === 'light' || value === 'dark' || value === 'system') {
      return value;
    }
    return defaultValue;
  }

  private normalizeTabsOverviewLayoutStyle(
    value: BrowserTabsOverviewLayoutStyle | string | undefined,
    defaultValue: BrowserTabsOverviewLayoutStyle
  ): BrowserTabsOverviewLayoutStyle {
    return value === 'grid' || value === 'horizontal_cards' ? value : defaultValue;
  }

  private parseAppearanceSettings(
    value: string,
    defaultValue: BrowserAppearanceSettings = DEFAULT_BROWSER_APPEARANCE_SETTINGS
  ): BrowserAppearanceSettings {
    try {
      const parsed = JSON.parse(value) as BrowserAppearanceSettings;
      return {
        bottomToolbarScrollBehavior: this.normalizeBottomToolbarScrollBehavior(
          parsed.bottomToolbarScrollBehavior,
          defaultValue.bottomToolbarScrollBehavior
        ),
        globalImmersionEnabled: typeof parsed.globalImmersionEnabled === 'boolean'
          ? parsed.globalImmersionEnabled
          : defaultValue.globalImmersionEnabled,
        alwaysTopImmersionEnabled: typeof parsed.alwaysTopImmersionEnabled === 'boolean'
          ? parsed.alwaysTopImmersionEnabled
          : defaultValue.alwaysTopImmersionEnabled,
        forceDarkWebContentEnabled: typeof parsed.forceDarkWebContentEnabled === 'boolean'
          ? parsed.forceDarkWebContentEnabled
          : defaultValue.forceDarkWebContentEnabled,
        blurPrivateTabPreviews: typeof parsed.blurPrivateTabPreviews === 'boolean'
          ? parsed.blurPrivateTabPreviews
          : defaultValue.blurPrivateTabPreviews,
        showHomeRecentlyClosed: typeof parsed.showHomeRecentlyClosed === 'boolean'
          ? parsed.showHomeRecentlyClosed
          : defaultValue.showHomeRecentlyClosed,
        showHomeShortcuts: typeof parsed.showHomeShortcuts === 'boolean'
          ? parsed.showHomeShortcuts
          : defaultValue.showHomeShortcuts,
        homeRecentlyClosedLimit: this.clampNumber(
          parsed.homeRecentlyClosedLimit,
          defaultValue.homeRecentlyClosedLimit,
          1,
          24
        ),
        homeShortcutLayoutDensity: parsed.homeShortcutLayoutDensity === 'compact'
          ? 'compact'
          : defaultValue.homeShortcutLayoutDensity,
        homeShortcutIconSizeRatio: this.clampRatio(
          parsed.homeShortcutIconSizeRatio,
          defaultValue.homeShortcutIconSizeRatio,
          0.45,
          1
        ),
        siteIconCornerRadiusRatio: this.clampRatio(
          parsed.siteIconCornerRadiusRatio,
          defaultValue.siteIconCornerRadiusRatio,
          0.12,
          0.5
        ),
        themePaletteId: parsed.themePaletteId,
        tabsOverviewLayoutStyle: this.normalizeTabsOverviewLayoutStyle(
          parsed.tabsOverviewLayoutStyle,
          defaultValue.tabsOverviewLayoutStyle
        ),
        tabsOverviewCloseButtonAlwaysVisible: typeof parsed.tabsOverviewCloseButtonAlwaysVisible === 'boolean'
          ? parsed.tabsOverviewCloseButtonAlwaysVisible
          : defaultValue.tabsOverviewCloseButtonAlwaysVisible,
        showDesktopBookmarkBar: typeof parsed.showDesktopBookmarkBar === 'boolean'
          ? parsed.showDesktopBookmarkBar
          : defaultValue.showDesktopBookmarkBar
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private normalizeBottomToolbarScrollBehavior(
    value: BrowserBottomToolbarScrollBehavior | string | undefined,
    defaultValue: BrowserBottomToolbarScrollBehavior
  ): BrowserBottomToolbarScrollBehavior {
    if (value === 'fixed' || value === 'compact' || value === 'hidden') {
      return value;
    }
    return defaultValue;
  }

  private parseGeneralSettings(
    value: string,
    defaultValue: BrowserGeneralSettings = DEFAULT_BROWSER_GENERAL_SETTINGS
  ): BrowserGeneralSettings {
    try {
      const parsed = JSON.parse(value) as BrowserGeneralSettings;
      return {
        startupRestorePolicy: this.normalizeStartupRestorePolicy(
          parsed.startupRestorePolicy,
          defaultValue.startupRestorePolicy
        ),
        tabAutoClosePolicy: this.normalizeTabAutoClosePolicy(
          parsed.tabAutoClosePolicy,
          defaultValue.tabAutoClosePolicy
        ),
        privateTabRestorePolicy: this.normalizePrivateTabRestorePolicy(
          parsed.privateTabRestorePolicy,
          defaultValue.privateTabRestorePolicy
        ),
        privateModeAuthenticationEnabled: typeof parsed.privateModeAuthenticationEnabled === 'boolean'
          ? parsed.privateModeAuthenticationEnabled
          : defaultValue.privateModeAuthenticationEnabled,
        alwaysUsePrivateMode: typeof parsed.alwaysUsePrivateMode === 'boolean'
          ? parsed.alwaysUsePrivateMode
          : defaultValue.alwaysUsePrivateMode,
        privateModePreserveCookiesOnClose: typeof parsed.privateModePreserveCookiesOnClose === 'boolean'
          ? parsed.privateModePreserveCookiesOnClose
          : defaultValue.privateModePreserveCookiesOnClose,
        privateModeThemeEnabled: typeof parsed.privateModeThemeEnabled === 'boolean'
          ? parsed.privateModeThemeEnabled
          : defaultValue.privateModeThemeEnabled,
        enhancedTrackingProtectionEnabled: typeof parsed.enhancedTrackingProtectionEnabled === 'boolean'
          ? parsed.enhancedTrackingProtectionEnabled
          : defaultValue.enhancedTrackingProtectionEnabled
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private normalizeTabAutoClosePolicy(
    value: BrowserTabAutoClosePolicy | string | undefined,
    defaultValue: BrowserTabAutoClosePolicy
  ): BrowserTabAutoClosePolicy {
    if (value === 'manual' ||
      value === 'after_15_days' ||
      value === 'after_7_days' ||
      value === 'after_3_days' ||
      value === 'after_1_day' ||
      value === 'on_app_exit') {
      return value;
    }
    return defaultValue;
  }

  private parseCookiePolicySettings(
    value: string,
    defaultValue: BrowserCookiePolicySettings = DEFAULT_BROWSER_COOKIE_POLICY_SETTINGS
  ): BrowserCookiePolicySettings {
    try {
      const parsed = JSON.parse(value) as BrowserCookiePolicySettings;
      return {
        acceptCookies: typeof parsed.acceptCookies === 'boolean'
          ? parsed.acceptCookies
          : defaultValue.acceptCookies,
        acceptThirdPartyCookies: typeof parsed.acceptThirdPartyCookies === 'boolean'
          ? parsed.acceptThirdPartyCookies
          : defaultValue.acceptThirdPartyCookies
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private normalizeStartupRestorePolicy(
    value: BrowserStartupRestorePolicy | string | undefined,
    defaultValue: BrowserStartupRestorePolicy
  ): BrowserStartupRestorePolicy {
    if (value === 'restore_regular_tabs' || value === 'open_home') {
      return value;
    }
    return defaultValue;
  }

  private normalizePrivateTabRestorePolicy(
    value: BrowserPrivateTabRestorePolicy | string | undefined,
    defaultValue: BrowserPrivateTabRestorePolicy
  ): BrowserPrivateTabRestorePolicy {
    if (value === 'never_restore' || value === 'restore_private_tabs') {
      return value;
    }
    return defaultValue;
  }

  private parseExperimentSettings(
    value: string,
    defaultValue: BrowserExperimentSettings = DEFAULT_BROWSER_EXPERIMENT_SETTINGS
  ): BrowserExperimentSettings {
    try {
      const parsed = JSON.parse(value) as BrowserExperimentSettings;
      return {
        pauseWebAnimationsDuringScroll: typeof parsed.pauseWebAnimationsDuringScroll === 'boolean'
          ? parsed.pauseWebAnimationsDuringScroll
          : defaultValue.pauseWebAnimationsDuringScroll,
        reduceMediaMotionDuringScroll: typeof parsed.reduceMediaMotionDuringScroll === 'boolean'
          ? parsed.reduceMediaMotionDuringScroll
          : defaultValue.reduceMediaMotionDuringScroll,
        strengthenAdBlockingForSmoothScroll: typeof parsed.strengthenAdBlockingForSmoothScroll === 'boolean'
          ? parsed.strengthenAdBlockingForSmoothScroll
          : defaultValue.strengthenAdBlockingForSmoothScroll,
        pullRefreshEnabled: resolveExperimentPullRefreshEnabled(parsed, defaultValue.pullRefreshEnabled),
        forceEnableWebZoom: typeof parsed.forceEnableWebZoom === 'boolean'
          ? parsed.forceEnableWebZoom
          : defaultValue.forceEnableWebZoom,
        smartGripTabsActionsEnabled: typeof parsed.smartGripTabsActionsEnabled === 'boolean'
          ? parsed.smartGripTabsActionsEnabled
          : defaultValue.smartGripTabsActionsEnabled,
        webVideoTakeoverEnabled: typeof parsed.webVideoTakeoverEnabled === 'boolean'
          ? parsed.webVideoTakeoverEnabled
          : defaultValue.webVideoTakeoverEnabled,
        novelModeEnabled: typeof parsed.novelModeEnabled === 'boolean'
          ? parsed.novelModeEnabled
          : defaultValue.novelModeEnabled,
        novelAutoTakeoverEnabled: typeof parsed.novelAutoTakeoverEnabled === 'boolean'
          ? parsed.novelAutoTakeoverEnabled
          : defaultValue.novelAutoTakeoverEnabled,
        appProxyActiveProfileId: this.normalizeShortText(parsed.appProxyActiveProfileId, '', 80),
        appProxyProfiles: this.parseAppProxyProfiles(parsed.appProxyProfiles),
        appProxyEnabled: typeof parsed.appProxyEnabled === 'boolean'
          ? parsed.appProxyEnabled
          : defaultValue.appProxyEnabled,
        appProxy: this.parseAppProxySettings(parsed.appProxy, defaultValue.appProxy)
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private parseAppProxyProfiles(value: BrowserAppProxyProfile[] | undefined): BrowserAppProxyProfile[] {
    if (!Array.isArray(value) || value.length <= 0) {
      return [];
    }
    const result: BrowserAppProxyProfile[] = [];
    const seenIds: Record<string, boolean> = {};
    for (let index = 0; index < value.length; index += 1) {
      const profile = value[index];
      const id = this.normalizeShortText(profile?.id, '', 80);
      if (id.length <= 0 || seenIds[id]) {
        continue;
      }
      seenIds[id] = true;
      result.push({
        id: id,
        name: this.normalizeShortText(profile?.name, '未命名代理', 80),
        settings: this.parseAppProxySettings(profile?.settings, DEFAULT_BROWSER_APP_PROXY_SETTINGS),
        createdAt: this.normalizeNonNegativeTimestamp(profile?.createdAt, 0),
        updatedAt: this.normalizeNonNegativeTimestamp(profile?.updatedAt, 0)
      });
    }
    return result;
  }

  private parseAppProxySettings(
    value: BrowserAppProxySettings | undefined,
    defaultValue: BrowserAppProxySettings = DEFAULT_BROWSER_APP_PROXY_SETTINGS
  ): BrowserAppProxySettings {
    return {
      scheme: this.normalizeAppProxyScheme(value?.scheme, defaultValue.scheme),
      host: this.normalizeShortText(value?.host, defaultValue.host, 180),
      port: this.normalizePort(value?.port, defaultValue.port),
      username: this.normalizeShortText(value?.username, defaultValue.username, 180),
      password: this.normalizeShortText(value?.password, defaultValue.password, 256),
      bypassHosts: this.normalizeShortText(value?.bypassHosts, defaultValue.bypassHosts, 500),
      updatedAt: this.normalizeNonNegativeTimestamp(value?.updatedAt, defaultValue.updatedAt)
    };
  }

  private normalizeAppProxyScheme(
    value: BrowserAppProxyScheme | string | undefined,
    defaultValue: BrowserAppProxyScheme
  ): BrowserAppProxyScheme {
    if (value === 'http' || value === 'https' || value === 'socks5') {
      return value;
    }
    return defaultValue;
  }

  private normalizePort(value: number | undefined, defaultValue: number): number {
    const numberValue = Number(value);
    if (!Number.isFinite(numberValue)) {
      return defaultValue;
    }
    return Math.min(Math.max(Math.floor(numberValue), 0), 65535);
  }

  private normalizeShortText(value: string | undefined, defaultValue: string, maxLength: number): string {
    if (typeof value !== 'string') {
      return defaultValue;
    }
    return value.trim().slice(0, maxLength);
  }

  private normalizeNonNegativeTimestamp(value: number | undefined, defaultValue: number): number {
    const numberValue = Number(value);
    if (!Number.isFinite(numberValue) || numberValue < 0) {
      return defaultValue;
    }
    return Math.floor(numberValue);
  }

  private parseReaderModePreferences(value: string, defaultValue: ReaderModePreferences): ReaderModePreferences {
    try {
      const parsed = JSON.parse(value) as ReaderModePreferences;
      return {
        fontSize: this.clampNumber(parsed.fontSize, defaultValue.fontSize, 15, 26),
        theme: this.normalizeReaderModeTheme(parsed.theme, defaultValue.theme),
        lineHeight: this.normalizeReaderModeLineHeight(parsed.lineHeight, defaultValue.lineHeight),
        pageWidth: this.normalizeReaderModePageWidth(parsed.pageWidth, defaultValue.pageWidth),
        brightnessMode: this.normalizeReaderModeBrightnessMode(parsed.brightnessMode),
        brightnessPercent: this.clampNumber(
          parsed.brightnessPercent,
          defaultValue.brightnessPercent,
          20,
          100
        ),
        pageMode: this.normalizeReadingPageMode(parsed.pageMode, defaultValue.pageMode)
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private normalizeReaderModeTheme(
    value: ReaderModeTheme | string | undefined,
    defaultValue: ReaderModeTheme
  ): ReaderModeTheme {
    if (value === 'light' || value === 'dark' || value === 'sepia' || value === 'paper' ||
      value === 'sage' || value === 'charcoal' || value === 'system') {
      return value;
    }
    return defaultValue;
  }

  private normalizeReaderModeBrightnessMode(
    value: ReaderModeBrightnessMode | string | undefined
  ): ReaderModeBrightnessMode {
    return value === 'manual' ? 'manual' : 'system';
  }

  private normalizeReadingPageMode(
    value: string | undefined,
    defaultValue: ReadingPageMode
  ): ReadingPageMode {
    if (value === 'horizontal' || value === 'horizontalFast' || value === 'vertical') {
      return value;
    }
    return defaultValue;
  }

  private normalizeReaderModeLineHeight(
    value: ReaderModeLineHeight | string | undefined,
    defaultValue: ReaderModeLineHeight
  ): ReaderModeLineHeight {
    if (value === 'compact' || value === 'comfortable' || value === 'loose') {
      return value;
    }
    return defaultValue;
  }

  private normalizeReaderModePageWidth(
    value: ReaderModePageWidth | string | undefined,
    defaultValue: ReaderModePageWidth
  ): ReaderModePageWidth {
    if (value === 'narrow' || value === 'standard' || value === 'wide') {
      return value;
    }
    return defaultValue;
  }

  private buildReadingAppearance(preferences: ReaderModePreferences): ReadingSurfaceAppearance {
    return {
      fontSize: preferences.fontSize,
      theme: preferences.theme,
      lineHeight: preferences.lineHeight,
      pageWidth: preferences.pageWidth,
      brightnessMode: preferences.brightnessMode,
      brightnessPercent: preferences.brightnessPercent
    };
  }

  private mergeReadingAppearance(
    preferences: ReaderModePreferences,
    appearance: ReadingSurfaceAppearance
  ): ReaderModePreferences {
    return {
      fontSize: appearance.fontSize,
      theme: appearance.theme,
      lineHeight: appearance.lineHeight,
      pageWidth: appearance.pageWidth,
      brightnessMode: appearance.brightnessMode,
      brightnessPercent: appearance.brightnessPercent,
      pageMode: preferences.pageMode
    };
  }

  private parseDownloadSettings(value: string, defaultValue: BrowserDownloadSettings): BrowserDownloadSettings {
    try {
      const parsed = JSON.parse(value) as BrowserDownloadSettings;
      return {
        defaultLocation: this.normalizeDownloadLocation(parsed.defaultLocation, defaultValue.defaultLocation),
        askBeforeDownload: typeof parsed.askBeforeDownload === 'boolean'
          ? parsed.askBeforeDownload
          : defaultValue.askBeforeDownload,
        allowCellularDownloads: typeof parsed.allowCellularDownloads === 'boolean'
          ? parsed.allowCellularDownloads
          : defaultValue.allowCellularDownloads,
        autoResumeAfterRestart: typeof parsed.autoResumeAfterRestart === 'boolean'
          ? parsed.autoResumeAfterRestart
          : defaultValue.autoResumeAfterRestart,
        hlsSegmentConcurrency: this.normalizeHlsSegmentConcurrency(
          parsed.hlsSegmentConcurrency,
          defaultValue.hlsSegmentConcurrency
        ),
        autoClearPolicy: this.normalizeDownloadAutoClearPolicy(parsed.autoClearPolicy, defaultValue.autoClearPolicy),
        privateFilePolicy: this.normalizePrivateDownloadFilePolicy(parsed.privateFilePolicy, defaultValue.privateFilePolicy),
        privateRecordPolicy: this.normalizePrivateDownloadRecordPolicy(
          parsed.privateRecordPolicy,
          defaultValue.privateRecordPolicy
        )
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private normalizeDownloadLocation(
    value: BrowserDownloadLocation | string | undefined,
    defaultValue: BrowserDownloadLocation
  ): BrowserDownloadLocation {
    return value === 'system_downloads' ? 'system_downloads' : defaultValue;
  }

  private normalizeDownloadAutoClearPolicy(
    value: BrowserDownloadAutoClearPolicy | string | undefined,
    defaultValue: BrowserDownloadAutoClearPolicy
  ): BrowserDownloadAutoClearPolicy {
    if (value === 'clear_completed' || value === 'clear_completed_and_failed') {
      return value;
    }
    if (value === 'manual') {
      return 'manual';
    }
    return defaultValue;
  }

  private normalizeHlsSegmentConcurrency(
    value: BrowserHlsSegmentConcurrency | string | undefined,
    defaultValue: BrowserHlsSegmentConcurrency
  ): BrowserHlsSegmentConcurrency {
    if (value === '4' || value === '8' || value === '16') {
      return value;
    }
    return defaultValue;
  }

  private normalizePrivateDownloadFilePolicy(
    value: BrowserPrivateDownloadFilePolicy | string | undefined,
    defaultValue: BrowserPrivateDownloadFilePolicy
  ): BrowserPrivateDownloadFilePolicy {
    if (value === 'session_temp_only') {
      return value;
    }
    if (value === 'prompt_for_location') {
      return value;
    }
    return defaultValue;
  }

  private normalizePrivateDownloadRecordPolicy(
    value: BrowserPrivateDownloadRecordPolicy | string | undefined,
    defaultValue: BrowserPrivateDownloadRecordPolicy
  ): BrowserPrivateDownloadRecordPolicy {
    if (value === 'clear_after_export') {
      return value;
    }
    if (value === 'keep_until_window_close') {
      return value;
    }
    return defaultValue;
  }

  private parseToolbarLayoutSettings(
    value: string,
    defaultValue: BrowserToolbarLayoutSettings = DEFAULT_BROWSER_TOOLBAR_LAYOUT_SETTINGS
  ): BrowserToolbarLayoutSettings {
    try {
      const parsed = JSON.parse(value) as BrowserToolbarLayoutSettings;
      return {
        primaryActionIds: Array.isArray(parsed.primaryActionIds)
          ? parsed.primaryActionIds.map((actionId: string) => String(actionId ?? ''))
          : defaultValue.primaryActionIds,
        secondaryActionIds: Array.isArray(parsed.secondaryActionIds)
          ? parsed.secondaryActionIds.map((actionId: string) => String(actionId ?? ''))
          : defaultValue.secondaryActionIds,
        leadingSlotActionId: String(parsed.leadingSlotActionId ?? defaultValue.leadingSlotActionId ?? ''),
        menuSlotActionId: String(parsed.menuSlotActionId ?? defaultValue.menuSlotActionId ?? ''),
        refreshSlotActionId: String(parsed.refreshSlotActionId ?? defaultValue.refreshSlotActionId ?? ''),
        tabsSlotActionId: String(parsed.tabsSlotActionId ?? defaultValue.tabsSlotActionId ?? ''),
        leadingSlotLongPressActionId: String(parsed.leadingSlotLongPressActionId ??
          defaultValue.leadingSlotLongPressActionId ?? 'none'),
        menuSlotLongPressActionId: String(parsed.menuSlotLongPressActionId ??
          defaultValue.menuSlotLongPressActionId ?? 'none'),
        refreshSlotLongPressActionId: String(parsed.refreshSlotLongPressActionId ??
          defaultValue.refreshSlotLongPressActionId ?? 'none'),
        tabsSlotLongPressActionId: String(parsed.tabsSlotLongPressActionId ??
          defaultValue.tabsSlotLongPressActionId ?? 'none'),
        leadingSlotSwipeUpActionId: String(parsed.leadingSlotSwipeUpActionId ??
          defaultValue.leadingSlotSwipeUpActionId ?? 'home'),
        tabsSlotSwipeUpActionId: String(parsed.tabsSlotSwipeUpActionId ??
          defaultValue.tabsSlotSwipeUpActionId ?? 'home'),
        updatedAt: this.normalizeNonNegativeTimestamp(parsed.updatedAt, defaultValue.updatedAt)
      };
    } catch (_error) {
      return defaultValue;
    }
  }



  private parseSitePermissionDefaultSettings(
    value: string,
    defaultValue: SitePermissionDefaultSettings = DEFAULT_SITE_PERMISSION_DEFAULT_SETTINGS
  ): SitePermissionDefaultSettings {
    try {
      const parsed = JSON.parse(value) as SitePermissionDefaultSettings;
      return {
        camera: this.normalizeSitePermissionRuleWithDefault(parsed.camera, defaultValue.camera),
        microphone: this.normalizeSitePermissionRuleWithDefault(parsed.microphone, defaultValue.microphone),
        location: this.normalizeSitePermissionRuleWithDefault(parsed.location, defaultValue.location),
        sensor: this.normalizeSitePermissionRuleWithDefault(parsed.sensor, defaultValue.sensor),
        clipboard: this.normalizeSitePermissionRuleWithDefault(parsed.clipboard, defaultValue.clipboard)
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private parseExternalNavigationSettings(
    value: string,
    defaultValue: ExternalNavigationSettings = DEFAULT_EXTERNAL_NAVIGATION_SETTINGS
  ): ExternalNavigationSettings {
    try {
      const parsed = JSON.parse(value) as ExternalNavigationSettings;
      return {
        appOpenPolicy: this.normalizeExternalNavigationAppOpenPolicy(parsed.appOpenPolicy, defaultValue.appOpenPolicy),
        suppressAfterCancelMs: this.normalizePositiveInt(
          parsed.suppressAfterCancelMs,
          defaultValue.suppressAfterCancelMs,
          DEFAULT_EXTERNAL_NAVIGATION_SETTINGS.suppressAfterCancelMs
        ),
        siteRules: this.parseExternalNavigationSiteRules(parsed.siteRules)
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private normalizeExternalNavigationAppOpenPolicy(
    value: ExternalNavigationAppOpenPolicy | string | undefined,
    defaultValue: ExternalNavigationAppOpenPolicy
  ): ExternalNavigationAppOpenPolicy {
    if (value === 'block' || value === 'allow') {
      return value;
    }
    if (value === 'ask') {
      return value;
    }
    return defaultValue;
  }

  private parseExternalNavigationSiteRules(siteRules: ExternalNavigationSiteRule[] | undefined): ExternalNavigationSiteRule[] {
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
      const policy = this.normalizeExternalNavigationAppOpenPolicy(rule.policy, 'ask');
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

  private parseSitePermissionSettings(value: string): SitePermissionSettings[] {
    try {
      const parsed = JSON.parse(value) as SitePermissionSettings[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .filter((settings: SitePermissionSettings) => settings.origin !== undefined && settings.origin.length > 0)
        .filter((settings: SitePermissionSettings) => {
          return typeof settings.siteKey === 'string' && typeof settings.displayHost === 'string' &&
            typeof settings.primaryOrigin === 'string';
        })
        .map((settings: SitePermissionSettings) => {
          const identity = this.siteIdentityService.resolve(settings.primaryOrigin);
          const normalizedSettings: SitePermissionSettings = {
            profileId: normalizeBrowserProfileId(settings.profileId ?? DEFAULT_BROWSER_PROFILE_ID),
            origin: identity.primaryOrigin,
            siteKey: identity.siteKey,
            displayHost: identity.displayHost,
            primaryOrigin: identity.primaryOrigin,
            camera: this.normalizeSitePermissionRule(settings.camera),
            microphone: this.normalizeSitePermissionRule(settings.microphone),
            location: this.normalizeSitePermissionRule(settings.location),
            sensor: this.normalizeSitePermissionRule(settings.sensor),
            clipboard: this.normalizeSitePermissionRule(settings.clipboard),
            updatedAt: Number(settings.updatedAt) > 0 ? Number(settings.updatedAt) : 0
          };
          return normalizedSettings;
        })
        .filter((settings: SitePermissionSettings) => {
          return settings.origin.length > 0 && settings.siteKey.length > 0 &&
            settings.displayHost.length > 0 && settings.primaryOrigin.length > 0;
        });
    } catch (_error) {
      return [];
    }
  }

  private normalizeSitePermissionRule(value: string): SitePermissionRule {
    if (value === 'allow' || value === 'block') {
      return value;
    }
    return 'ask';
  }

  private normalizeSitePermissionRuleWithDefault(
    value: SitePermissionRule | string | undefined,
    defaultValue: SitePermissionRule
  ): SitePermissionRule {
    if (value === 'ask' || value === 'allow' || value === 'block') {
      return value;
    }
    return defaultValue;
  }

  private parseRetentionSettings(value: string, defaultValue: BrowserRetentionSettings): BrowserRetentionSettings {
    try {
      const parsed = JSON.parse(value) as BrowserRetentionSettings;
      return {
        profileId: this.normalizeRetentionProfileId(parsed.profileId, defaultValue.profileId),
        deviceTierHint: this.normalizeRetentionDeviceTierHint(parsed.deviceTierHint, defaultValue.deviceTierHint),
        maxMountedRuntimeTabs: this.normalizePositiveInt(
          parsed.maxMountedRuntimeTabs,
          defaultValue.maxMountedRuntimeTabs,
          DEFAULT_BROWSER_RETENTION_SETTINGS.maxMountedRuntimeTabs
        ),
        maxHotBackgroundTabs: this.normalizeNonNegativeInt(
          parsed.maxHotBackgroundTabs,
          defaultValue.maxHotBackgroundTabs,
          DEFAULT_BROWSER_RETENTION_SETTINGS.maxHotBackgroundTabs
        ),
        maxWarmBackgroundTabs: this.normalizeNonNegativeInt(
          parsed.maxWarmBackgroundTabs,
          defaultValue.maxWarmBackgroundTabs,
          DEFAULT_BROWSER_RETENTION_SETTINGS.maxWarmBackgroundTabs
        ),
        hotBackgroundMaxAgeMs: this.normalizePositiveInt(
          parsed.hotBackgroundMaxAgeMs,
          defaultValue.hotBackgroundMaxAgeMs,
          DEFAULT_BROWSER_RETENTION_SETTINGS.hotBackgroundMaxAgeMs
        ),
        warmBackgroundMaxAgeMs: this.normalizePositiveInt(
          parsed.warmBackgroundMaxAgeMs,
          defaultValue.warmBackgroundMaxAgeMs,
          DEFAULT_BROWSER_RETENTION_SETTINGS.warmBackgroundMaxAgeMs
        ),
        staleAfterMs: this.normalizePositiveInt(
          parsed.staleAfterMs,
          defaultValue.staleAfterMs,
          DEFAULT_BROWSER_RETENTION_SETTINGS.staleAfterMs
        )
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private parseHistoryRetentionSettings(
    value: string,
    defaultValue: HistoryRetentionSettings
  ): HistoryRetentionSettings {
    try {
      const parsed = JSON.parse(value) as HistoryRetentionSettings;
      return {
        enabled: parsed.enabled !== false,
        maxAgeDays: this.normalizePositiveInt(
          parsed.maxAgeDays,
          defaultValue.maxAgeDays,
          DEFAULT_HISTORY_RETENTION_SETTINGS.maxAgeDays
        ),
        maxRows: this.normalizePositiveInt(
          parsed.maxRows,
          defaultValue.maxRows,
          DEFAULT_HISTORY_RETENTION_SETTINGS.maxRows
        )
      };
    } catch (_error) {
      return defaultValue;
    }
  }

  private normalizeRetentionProfileId(value: BrowserRetentionProfileId, defaultValue: BrowserRetentionProfileId): BrowserRetentionProfileId {
    if (value === 'memory_saver' || value === 'balanced' || value === 'keep_more_tabs') {
      return value;
    }
    return defaultValue;
  }

  private normalizeRetentionDeviceTierHint(
    value: BrowserDeviceTierHint,
    defaultValue: BrowserDeviceTierHint
  ): BrowserDeviceTierHint {
    if (
      value === 'low_memory' ||
      value === 'balanced_device' ||
      value === 'high_memory' ||
      value === 'ultra_memory'
    ) {
      return value;
    }
    if (value === 'auto') {
      return value;
    }
    return defaultValue;
  }

  private normalizePositiveInt(value: number, fallback: number, defaultValue: number): number {
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric <= 0) {
      return fallback > 0 ? fallback : defaultValue;
    }
    return Math.round(numeric);
  }

  private normalizeNonNegativeInt(value: number, fallback: number, defaultValue: number): number {
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric < 0) {
      return fallback >= 0 ? fallback : defaultValue;
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

  private clampRatio(value: number, fallback: number, min: number, max: number): number {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) {
      return fallback;
    }
    return Math.min(max, Math.max(min, Math.round(numeric * 100) / 100));
  }
}
