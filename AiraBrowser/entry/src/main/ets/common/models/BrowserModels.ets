export type BuiltInSearchEngineId =
  'bing' |
  'google' |
  'duckduckgo' |
  'baidu' |
  'qihoo' |
  'sogou' |
  'shenma' |
  'brave' |
  'startpage' |
  'ecosia' |
  'yandex';
export type SearchEngineId = string;
export type ExternalAppSearchTargetId =
  'zhihu' |
  'bilibili' |
  'douyin' |
  'xiaohongshu' |
  'douban' |
  'quark' |
  'appgallery' |
  'jd' |
  'taobao' |
  'pinduoduo' |
  'xianyu' |
  'meituan' |
  'baidu_map' |
  'qqmusic' |
  'alipay' |
  'youdao';
export type ExternalAppSearchIconTargetId = ExternalAppSearchTargetId;
export const ALL_EXTERNAL_APP_SEARCH_TARGET_IDS: ExternalAppSearchTargetId[] = [
  'zhihu',
  'bilibili',
  'douyin',
  'xiaohongshu',
  'douban',
  'quark',
  'appgallery',
  'jd',
  'taobao',
  'pinduoduo',
  'xianyu',
  'meituan',
  'baidu_map',
  'qqmusic',
  'alipay',
  'youdao'
];
export interface ExternalAppSearchPreferences {
  enabled: boolean;
  selectedTargetIds: ExternalAppSearchTargetId[];
  targetOrder: ExternalAppSearchTargetId[];
  updatedAt: number;
}
export type SearchEngineKind = 'built_in' | 'custom';
export type SearchEngineSelectionScope = 'persistent' | 'session';
export interface SearchEngineOption {
  id: SearchEngineId;
  name: string;
  searchUrlTemplate?: string;
  homepageUrl?: string;
  iconUrl?: string;
  availabilityProbeUrl?: string;
  availabilityExpectedStatus?: number;
  kind?: SearchEngineKind;
  isEditable?: boolean;
}

export const SEARCH_ENGINE_OPTIONS: SearchEngineOption[] = [
  {
    id: 'bing',
    name: 'Bing',
    searchUrlTemplate: 'https://www.bing.com/search?q={searchTerms}',
    homepageUrl: 'https://www.bing.com',
    availabilityProbeUrl: 'https://www.bing.com',
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'google',
    name: 'Google',
    searchUrlTemplate: 'https://www.google.com/search?q={searchTerms}',
    homepageUrl: 'https://www.google.com',
    availabilityProbeUrl: 'https://www.google.com/generate_204',
    availabilityExpectedStatus: 204,
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'duckduckgo',
    name: 'DuckDuckGo',
    searchUrlTemplate: 'https://duckduckgo.com/?q={searchTerms}',
    homepageUrl: 'https://duckduckgo.com',
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'baidu',
    name: 'Baidu',
    searchUrlTemplate: 'https://www.baidu.com/s?wd={searchTerms}',
    homepageUrl: 'https://www.baidu.com',
    availabilityProbeUrl: 'https://www.baidu.com',
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'qihoo',
    name: '360 搜索',
    searchUrlTemplate: 'https://www.so.com/s?q={searchTerms}',
    homepageUrl: 'https://www.so.com',
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'sogou',
    name: '搜狗',
    searchUrlTemplate: 'https://www.sogou.com/web?query={searchTerms}',
    homepageUrl: 'https://www.sogou.com',
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'shenma',
    name: '神马',
    searchUrlTemplate: 'https://m.sm.cn/s?q={searchTerms}',
    homepageUrl: 'https://m.sm.cn',
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'brave',
    name: 'Brave Search',
    searchUrlTemplate: 'https://search.brave.com/search?q={searchTerms}',
    homepageUrl: 'https://search.brave.com',
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'startpage',
    name: 'Startpage',
    searchUrlTemplate: 'https://www.startpage.com/sp/search?query={searchTerms}',
    homepageUrl: 'https://www.startpage.com',
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'ecosia',
    name: 'Ecosia',
    searchUrlTemplate: 'https://www.ecosia.org/search?q={searchTerms}',
    homepageUrl: 'https://www.ecosia.org',
    kind: 'built_in',
    isEditable: false
  },
  {
    id: 'yandex',
    name: 'Yandex',
    searchUrlTemplate: 'https://yandex.com/search/?text={searchTerms}',
    homepageUrl: 'https://yandex.com',
    kind: 'built_in',
    isEditable: false
  }
];

export const DEFAULT_SEARCH_ENGINE_ID: BuiltInSearchEngineId = 'bing';
export const DEFAULT_ENABLED_BUILT_IN_SEARCH_ENGINE_IDS: BuiltInSearchEngineId[] = [
  'bing',
  'google',
  'duckduckgo',
  'baidu',
  'yandex'
];

export interface SearchEngineRecord {
  id: SearchEngineId;
  kind: SearchEngineKind;
  name: string;
  searchUrlTemplate: string;
  homepageUrl: string;
  iconUrl?: string;
  availabilityProbeUrl?: string;
  availabilityExpectedStatus?: number;
  isEditable: boolean;
  position: number;
  createdAt: number;
  updatedAt: number;
}

export interface SearchSuggestionPreferences {
  regularEnabled: boolean;
  privateEnabled: boolean;
  openTabsEnabled: boolean;
  bookmarksEnabled: boolean;
  shortcutsEnabled: boolean;
  historyEnabled: boolean;
  remoteEnabled: boolean;
}

export interface SearchEngineFallbackSettings {
  enabled: boolean;
  fallbackSearchEngineId: SearchEngineId;
  noticeEnabled: boolean;
}

export interface SearchQueryHistoryRecord {
  id: string;
  query: string;
  normalizedQuery: string;
  compactQuery: string;
  searchEngineId: SearchEngineId;
  useCount: number;
  firstSearchedAt: number;
  lastSearchedAt: number;
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
}

export interface SearchEngineSettings {
  defaultSearchEngineId: SearchEngineId;
  builtInEngineOrder: SearchEngineId[];
  enabledBuiltInEngineIds: SearchEngineId[];
  customEngines: SearchEngineRecord[];
  searchSuggestions: SearchSuggestionPreferences;
  fallbackSearch: SearchEngineFallbackSettings;
  updatedAt: number;
}

export interface AdBlockPreferences {
  enabled: boolean;
  updateOnForeground: boolean;
}

export type AdBlockCustomRuleSourceType = 'system' | 'remote' | 'local';
export type AdBlockResourceType =
  'document' |
  'popup' |
  'script' |
  'image' |
  'stylesheet' |
  'xmlhttprequest' |
  'websocket' |
  'ping' |
  'subdocument' |
  'media' |
  'font' |
  'object' |
  'other';

export interface AdBlockSiteException {
  profileId: BrowserProfileId;
  host: string;
  includeSubdomains: boolean;
  createdAt: number;
}

export interface AdBlockCustomRuleSource {
  id: string;
  payloadIdentity: string;
  title: string;
  url: string;
  sourceType: AdBlockCustomRuleSourceType;
  enabled: boolean;
  nativeNetworkRuleCount?: number;
  nativeCosmeticRuleCount?: number;
  ruleCount: number;
  lastUpdatedAt: number;
  lastError: string;
  createdAt: number;
  updatedAt: number;
}

export interface AdBlockStats {
  statisticsVersion: number;
  totalBlockedCount: number;
  networkBlockedCount: number;
  urlParameterRemovedCount: number;
  cosmeticElementHiddenCount: number;
  manualElementHiddenCount: number;
  totalProtectionActionCount: number;
  dailyProtectionActivity: AdBlockDailyProtectionActivity[];
  updatedAt: number;
}

export interface AdBlockDailyProtectionActivity {
  dayStartedAt: number;
  networkBlockedCount: number;
  urlParameterRemovedCount: number;
  cosmeticElementHiddenCount: number;
  manualElementHiddenCount: number;
  totalProtectionActionCount: number;
}

export interface AdBlockSettings {
  preferences: AdBlockPreferences;
  siteExceptions: AdBlockSiteException[];
  customRuleSources: AdBlockCustomRuleSource[];
  stats: AdBlockStats;
  lastRuleUpdateAt: number;
  engineUnavailableReason: string;
  updatedAt: number;
}

export interface ManualElementHideRule {
  id: string;
  host: string;
  selector: string;
  pageUrl: string;
  createdAt: number;
  updatedAt: number;
}

export interface ManualElementHideSiteRules {
  host: string;
  enabled: boolean;
  rules: ManualElementHideRule[];
  createdAt: number;
  updatedAt: number;
}

export interface ManualElementHideSettings {
  sites: ManualElementHideSiteRules[];
  updatedAt: number;
}

export type PasswordVaultProvider = 'arkweb_official_vault';

export interface PasswordManagerPreferences {
  officialVaultEnabled: boolean;
  regularAutofillEnabled: boolean;
  regularSavePromptEnabled: boolean;
  privateAutofillEnabled: boolean;
  privateSavePromptEnabled: boolean;
}

export interface PasswordManagerSettings {
  provider: PasswordVaultProvider;
  preferences: PasswordManagerPreferences;
  officialVaultVerifiedAt: number;
  officialVaultVerificationNote: string;
  selfHostedCredentialStoreEnabled: boolean;
  updatedAt: number;
}

export type TranslationProviderTemplateId =
  'aira_system' |
  'custom_http' |
  'deepl' |
  'google_cloud' |
  'tencent_cloud' |
  'baidu' |
  'microsoft' |
  'alibaba_cloud' |
  'volcano' |
  'youdao';
export type TranslationProviderStatus = 'not_configured' | 'configured' | 'failed' | 'unavailable';
export type TranslationRuleType = 'always_translate_language' | 'never_translate_language' | 'never_translate_site';

export interface TranslationProviderTemplate {
  id: TranslationProviderTemplateId;
  displayName: string;
  description: string;
  setupStatus: TranslationProviderStatus;
  requiresSecret: boolean;
  supportsDirectClientRequest: boolean;
  builtIn: boolean;
  requiresPro: boolean;
}

export interface TranslationSettingsPreferences {
  enabled: boolean;
  offerToTranslate: boolean;
  allowInPrivateTabs: boolean;
  preferredTargetLanguage: string;
  firstCloudDisclosureAcceptedAt: number;
}

export interface TranslationProviderConfig {
  id: string;
  templateId: TranslationProviderTemplateId;
  displayName: string;
  endpoint: string;
  apiKey: string;
  appId: string;
  secretKey: string;
  region: string;
  model: string;
  optionsJson: string;
  secretRefsJson: string;
  status: TranslationProviderStatus;
  failureReason: string;
  updatedAt: number;
}

export interface TranslationRule {
  type: TranslationRuleType;
  languageCode: string;
  host: string;
  targetLanguageCode: string;
  createdAt: number;
}

export interface TranslationSettings {
  preferences: TranslationSettingsPreferences;
  activeProviderId: string;
  providers: TranslationProviderConfig[];
  rules: TranslationRule[];
  updatedAt: number;
}

export type SitePermissionKind = 'camera' | 'microphone' | 'location' | 'sensor' | 'clipboard';
export type SitePermissionRule = 'ask' | 'allow' | 'block';
export interface SitePermissionDefaultSettings {
  camera: SitePermissionRule;
  microphone: SitePermissionRule;
  location: SitePermissionRule;
  sensor: SitePermissionRule;
  clipboard: SitePermissionRule;
}

export type ExternalNavigationAppOpenPolicy = 'block' | 'ask' | 'allow';

export interface ExternalNavigationSiteRule {
  profileId: BrowserProfileId;
  origin: string;
  siteKey: string;
  displayHost: string;
  primaryOrigin: string;
  policy: ExternalNavigationAppOpenPolicy;
  updatedAt: number;
}

export interface ExternalNavigationSettings {
  appOpenPolicy: ExternalNavigationAppOpenPolicy;
  suppressAfterCancelMs: number;
  siteRules: ExternalNavigationSiteRule[];
}

export type BookmarkNodeType = 'folder' | 'bookmark';
export type BookmarkRootRole = 'toolbar' | 'other';
export type BookmarkStorageScope = 'regular' | 'private';
export type BrowserDataSource = 'seed' | 'local' | 'chrome_import' | 'chrome_sync' | 'cloud_sync';
export type BrowserProfileId = 'profile-main';
export type BrowserSessionPrivacyMode = 'regular' | 'private';
export type BrowserDataScope = 'profile_persistent' | 'session_ephemeral';
export interface BrowserDataBoundary {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  sessionId: string;
  storagePartitionId: string;
}

export interface BrowserDataBoundaryInput {
  profileId?: BrowserProfileId | string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
  sessionId?: string;
  storagePartitionId?: string;
}

export interface BrowserDataBoundaryTabLikeInput extends BrowserDataBoundaryInput {
  id?: string;
}
export type SyncState = 'local_only' | 'pending_push' | 'synced' | 'conflict';
export type SyncProviderId =
  | 'import_export'
  | 'aira_cloud_bookmarks'
  | 'webdav'
  | 'chrome_companion'
  | 'self_hosted';
export type TabRuntimeState =
  'active' |
  'background' |
  'background-hot' |
  'background-warm' |
  'suspended' |
  'cold' |
  'discarded' |
  'loading' |
  'error' |
  'restoring' |
  'crashed';

export type TabRestoreReason =
  'cold_start' |
  'controller_attach' |
  'tab_switch' |
  'discard_restore' |
  'crash_restore' |
  'snapshot_restore' |
  'snapshot_fallback_reload' |
  'manual_reload' |
  'external_launch';

export type TabDiscardReason =
  'retention_cold' |
  'retention_budget' |
  'retention_stale' |
  'manual_home' |
  'controller_detached';

export type TabCrashReason =
  'main_frame_error' |
  'snapshot_restore_failed' |
  'navigation_failed' |
  'render_process_terminated' |
  'recovery_degraded_to_home' |
  'unknown';

export type WebSessionRestoreType =
  'none' |
  'live_page_cache' |
  'snapshot_restore' |
  'reload';

export interface SyncMetadata {
  state: SyncState;
  source: BrowserDataSource;
  lastModifiedAt: number;
  lastModifiedBy: string;
  deviceId: string;
  originId?: string;
  deletedAt?: number;
}

export interface TabRecord {
  id: string;
  windowId: string;
  profileId?: BrowserProfileId;
  title: string;
  url: string;
  isActive: boolean;
  isPinned: boolean;
  lastActiveAt: number;
  tabOrder?: number;
  isHome?: boolean;
  pendingUrl?: string;
  navigationHistory?: string[];
  navigationIndex?: number;
  runtimeState?: TabRuntimeState;
  lastError?: string;
  lastRestoreReason?: TabRestoreReason;
  lastDiscardReason?: TabDiscardReason;
  lastCrashReason?: TabCrashReason;
  lastLoadedAt?: number;
  webStatePath?: string;
  webStateUpdatedAt?: number;
  scrollOffsetY?: number;
  lastGoodUrl?: string;
  lastGoodTitle?: string;
  lastRestorableUrl?: string;
  lastRestorableTitle?: string;
  lastRestoreType?: WebSessionRestoreType;
  privacyMode?: BrowserSessionPrivacyMode;
  dataScope?: BrowserDataScope;
  launchSourceType?: string;
  launchSourceId?: string;
  launchSourceUrl?: string;
  launchKey?: string;
  openerTabId?: string;
  openSource?: BrowserTabOpenSource;
  openedByNewWindow?: boolean;
}

export interface RecentlyClosedTabRecord {
  id: string;
  originalTabId: string;
  closedAt: number;
  windowId: string;
  profileId?: BrowserProfileId;
  siteIconUri?: string;
  tab: TabRecord;
}

export type TabLaunchSourceType = '' | 'home_shortcut' | 'desktop_web_entry' | 'app_continuation';

export type BrowserTabOpenSource =
  '' |
  'user_new_tab' |
  'web_context_menu' |
  'window_open' |
  'restore' |
  'home' |
  'external';

export interface TabLaunchContext {
  sourceType: TabLaunchSourceType;
  sourceId: string;
  sourceUrl: string;
  key: string;
}

export const DEFAULT_BROWSER_PROFILE_ID: BrowserProfileId = 'profile-main';

export function normalizeBrowserProfileId(value: BrowserProfileId | string | undefined): BrowserProfileId {
  return value === DEFAULT_BROWSER_PROFILE_ID ? DEFAULT_BROWSER_PROFILE_ID : DEFAULT_BROWSER_PROFILE_ID;
}

export function normalizeBrowserSessionPrivacyMode(
  value: BrowserSessionPrivacyMode | string | undefined
): BrowserSessionPrivacyMode {
  return value === 'private' ? 'private' : 'regular';
}

export function resolveBrowserDataScopeForPrivacyMode(privacyMode: BrowserSessionPrivacyMode): BrowserDataScope {
  return privacyMode === 'private' ? 'session_ephemeral' : 'profile_persistent';
}

export function normalizeBrowserDataScope(
  value: BrowserDataScope | string | undefined,
  privacyMode: BrowserSessionPrivacyMode = 'regular'
): BrowserDataScope {
  if (value === 'profile_persistent' || value === 'session_ephemeral') {
    return value;
  }
  return resolveBrowserDataScopeForPrivacyMode(privacyMode);
}

export function buildBrowserDataBoundary(input: BrowserDataBoundaryInput = {}): BrowserDataBoundary {
  const privacyMode = normalizeBrowserSessionPrivacyMode(input.privacyMode);
  const dataScope = privacyMode === 'private'
    ? 'session_ephemeral'
    : normalizeBrowserDataScope(input.dataScope, privacyMode);
  const profileId = normalizeBrowserProfileId(input.profileId);
  const sessionId = normalizeBrowserDataBoundarySessionId(input.sessionId, privacyMode, dataScope);
  return {
    profileId: profileId,
    privacyMode: privacyMode,
    dataScope: dataScope,
    sessionId: sessionId,
    storagePartitionId: normalizeBrowserDataBoundaryStoragePartitionId(
      input.storagePartitionId,
      profileId,
      privacyMode,
      dataScope,
      sessionId
    )
  };
}

export function buildBrowserDataBoundaryFromTabLike(input: BrowserDataBoundaryTabLikeInput): BrowserDataBoundary {
  return buildBrowserDataBoundary({
    profileId: input.profileId,
    privacyMode: input.privacyMode,
    dataScope: input.dataScope,
    sessionId: input.sessionId ?? input.id,
    storagePartitionId: input.storagePartitionId
  });
}

export function isBrowserDataBoundarySessionEphemeral(boundary: BrowserDataBoundaryInput | undefined): boolean {
  const normalized = buildBrowserDataBoundary(boundary);
  return normalized.privacyMode === 'private' || normalized.dataScope === 'session_ephemeral';
}

export function isBrowserDataBoundarySessionEphemeralTabLike(boundary: BrowserDataBoundaryTabLikeInput): boolean {
  const normalized = buildBrowserDataBoundaryFromTabLike(boundary);
  return normalized.privacyMode === 'private' || normalized.dataScope === 'session_ephemeral';
}

export function shouldPersistBrowserDataBoundary(boundary: BrowserDataBoundaryInput | undefined): boolean {
  return !isBrowserDataBoundarySessionEphemeral(boundary);
}

export function shouldPersistBrowserDataBoundaryTabLike(boundary: BrowserDataBoundaryTabLikeInput): boolean {
  return !isBrowserDataBoundarySessionEphemeralTabLike(boundary);
}

function normalizeBrowserDataBoundarySessionId(
  value: string | undefined,
  privacyMode: BrowserSessionPrivacyMode,
  dataScope: BrowserDataScope
): string {
  const normalized = String(value ?? '').trim();
  if (normalized.length > 0) {
    return normalized;
  }
  if (privacyMode === 'private' || dataScope === 'session_ephemeral') {
    return 'private-session';
  }
  return 'profile-session';
}

function normalizeBrowserDataBoundaryStoragePartitionId(
  value: string | undefined,
  profileId: BrowserProfileId,
  privacyMode: BrowserSessionPrivacyMode,
  dataScope: BrowserDataScope,
  sessionId: string
): string {
  const normalized = String(value ?? '').trim();
  if (normalized.length > 0) {
    return normalized;
  }
  if (privacyMode === 'private' || dataScope === 'session_ephemeral') {
    return `${profileId}:private:${sessionId}`;
  }
  return `${profileId}:persistent`;
}

export type ShortcutKind = 'web' | 'system';

export type HomeSystemShortcutTarget =
  'bookmarks' |
  'history' |
  'downloads' |
  'saved_pages' |
  'tabs' |
  'user_scripts' |
  'ad_block' |
  'settings';

export interface ShortcutRecord {
  id: string;
  scenarioId?: string;
  kind?: ShortcutKind;
  title: string;
  url: string;
  folderName: string;
  position: number;
  icon?: string;
  description?: string;
  useOfficialIcon?: boolean;
  autoUseOfficialIcon?: boolean;
  officialIconAvailableAtSave?: boolean;
  officialIconColorOverride?: boolean;
  iconRendering?: string;
  iconColor?: string;
  createdAt?: number;
  updatedAt?: number;
  sync?: SyncMetadata;
}

export interface CreateShortcutCommand {
  title: string;
  url: string;
  kind?: ShortcutKind;
  folderName?: string;
  scenarioId?: string;
  icon?: string;
}

export interface UpdateShortcutCommand {
  id: string;
  title: string;
  url: string;
  folderName?: string;
}

export interface ReplaceScenarioShortcutsCommand {
  scenarioId: string;
  shortcuts: ShortcutRecord[];
}

export interface ShortcutScenarioRecord {
  id: string;
  name: string;
  color: string;
  icon: string;
  position: number;
  archived: boolean;
  createdAt: number;
  updatedAt: number;
  sync: SyncMetadata;
}

export interface BookmarkNode {
  id: string;
  type: BookmarkNodeType;
  scope?: BookmarkStorageScope;
  parentId?: string;
  title: string;
  url?: string;
  position: number;
  createdAt: number;
  updatedAt: number;
  sync: SyncMetadata;
}

export interface BookmarkRootRecord {
  role: BookmarkRootRole;
  nodeId: string;
  title: string;
  position: number;
  syncEnabled: boolean;
}

export interface BookmarkOrderRecord {
  childId: string;
  parentId?: string;
  position: number;
  updatedAt: number;
}

export interface BookmarkSyncLinkRecord {
  nodeId: string;
  provider: SyncProviderId | 'seed';
  remoteEntityId?: string;
  originId?: string;
  updatedAt: number;
}

export type BookmarkImportSourceType = 'aira_bundle' | 'chrome_html' | 'chrome_extension' | 'manual';

export interface BookmarkImportBatchRecord {
  batchId: string;
  sourceType: BookmarkImportSourceType;
  providerId: SyncProviderId | 'seed';
  sourceLabel: string;
  sourceRef?: string;
  createdAt: number;
  completedAt: number;
  importedFolderCount: number;
  importedBookmarkCount: number;
  skippedNodeCount: number;
  duplicateCount: number;
  rootNodeId?: string;
}

export interface BookmarkImportBatchSummary {
  sourceType: BookmarkImportSourceType;
  providerId: SyncProviderId | 'seed';
  sourceLabel: string;
  sourceRef?: string;
}

export interface BookmarkCreateNodeCommand {
  type: BookmarkNodeType;
  title: string;
  scope?: BookmarkStorageScope;
  parentId?: string;
  url?: string;
}

export interface BookmarkReorderChildrenCommand {
  parentId?: string;
  childIds: string[];
}

export interface BookmarkMoveSubtreeCommand {
  nodeId: string;
  parentId?: string;
  targetIndex: number;
}

export interface BookmarkMoveSubtreesCommand {
  nodeIds: string[];
  parentId?: string;
  targetIndex: number;
}

export interface BookmarkRepositorySnapshot {
  roots: BookmarkRootRecord[];
  nodes: BookmarkNode[];
}

export interface UpdateBookmarkCommand {
  id: string;
  title: string;
  url?: string;
}

export interface CreateHistoryVisitCommand {
  title: string;
  url: string;
  visitedAt?: number;
  sessionId?: string;
  fromVisitId?: string;
  transition?: BrowserHistoryTransition;
  visitDurationMs?: number;
  profileId?: BrowserProfileId;
  dataScope?: BrowserDataScope;
}

export type BrowserHistoryTransition =
  'link' |
  'typed' |
  'auto_bookmark' |
  'auto_subframe' |
  'manual_subframe' |
  'generated' |
  'auto_toplevel' |
  'form_submit' |
  'reload' |
  'keyword' |
  'keyword_generated' |
  'unknown';

export interface HistoryUrlRecord {
  id: string;
  url: string;
  normalizedUrl: string;
  urlHash: string;
  origin: string;
  host: string;
  title: string;
  visitCount: number;
  typedCount: number;
  lastVisitAt: number;
  hidden: boolean;
  faviconKey: string;
  createdAt: number;
  updatedAt: number;
}

export interface HistorySiteAggregate {
  key: string;
  host: string;
  origin: string;
  title: string;
  latestTitle: string;
  latestUrl: string;
  latestVisitedAt: number;
  visitCount: number;
  uniqueUrlCount: number;
}

export interface BookmarkTreeRow {
  id: string;
  title: string;
  subtitle: string;
  type: BookmarkNodeType;
  depth: number;
  canMoveUp: boolean;
  canMoveDown: boolean;
}

export interface HistoryVisit {
  id: string;
  urlId?: string;
  title: string;
  url: string;
  normalizedUrl?: string;
  origin?: string;
  host?: string;
  visitedAt: number;
  dayBucketLabel: string;
  source: BrowserDataSource;
  deviceId: string;
  sessionId: string;
  fromVisitId?: string;
  transition?: BrowserHistoryTransition;
  visitDurationMs?: number;
  profileId?: BrowserProfileId;
  dataScope?: BrowserDataScope;
  visitCount?: number;
  typedCount?: number;
  lastVisitAt?: number;
  syncId?: string;
  syncAccountUid?: string;
  syncOrigin?: 'local' | 'remote';
}

export interface HistoryRetentionSettings {
  enabled: boolean;
  maxAgeDays: number;
  maxRows: number;
}

export interface HistoryTransferVisit {
  title: string;
  url: string;
  visitedAt: number;
  sessionId?: string;
  fromVisitId?: string;
  transition?: BrowserHistoryTransition;
  visitDurationMs?: number;
  profileId?: BrowserProfileId;
  dataScope?: BrowserDataScope;
}

export interface HistoryTransferBundle {
  version: number;
  app: string;
  exportedAt: number;
  visits: HistoryTransferVisit[];
}

export interface HistoryImportResult {
  importedCount: number;
  skippedCount: number;
}

export type BrowserRetentionProfileId = 'memory_saver' | 'balanced' | 'keep_more_tabs';
export type BrowserDeviceTierHint = 'auto' | 'low_memory' | 'balanced_device' | 'high_memory' | 'ultra_memory';
export type BrowserThemeMode = 'light' | 'dark' | 'system';
export type BrowserResolvedThemeMode = 'light' | 'dark';
export type BrowserThemePaletteId =
  'default' |
  'aira_classic' |
  'aira_origin' |
  'aurora' |
  'sage' |
  'cedar' |
  'lagoon' |
  'glacier' |
  'indigo' |
  'wisteria' |
  'rosewood' |
  'terracotta' |
  'amber' |
  'moss' |
  'cyan' |
  'steel' |
  'plum' |
  'coral';

export interface BrowserRetentionSettings {
  profileId: BrowserRetentionProfileId;
  deviceTierHint: BrowserDeviceTierHint;
  maxMountedRuntimeTabs: number;
  maxHotBackgroundTabs: number;
  maxWarmBackgroundTabs: number;
  hotBackgroundMaxAgeMs: number;
  warmBackgroundMaxAgeMs: number;
  staleAfterMs: number;
}

export type BrowserDownloadLocation = 'system_downloads';
export type BrowserDownloadAutoClearPolicy =
  'manual' |
  'clear_completed' |
  'clear_completed_and_failed';
export type BrowserHlsSegmentConcurrency = '4' | '8' | '16';
export type BrowserPrivateDownloadFilePolicy =
  'prompt_for_location' |
  'session_temp_only';
export type BrowserPrivateDownloadRecordPolicy =
  'keep_until_window_close' |
  'clear_after_export';
export type BrowserUserAgentMode =
  'mobile' |
  'desktop' |
  'custom';

export type BrowserUserAgentPresetId = string;

export interface BrowserCustomUserAgentRecord {
  id: string;
  name: string;
  userAgent: string;
  createdAt: number;
  updatedAt: number;
}

export interface BrowserDownloadSettings {
  defaultLocation: BrowserDownloadLocation;
  askBeforeDownload: boolean;
  allowCellularDownloads: boolean;
  autoResumeAfterRestart: boolean;
  hlsSegmentConcurrency: BrowserHlsSegmentConcurrency;
  autoClearPolicy: BrowserDownloadAutoClearPolicy;
  privateFilePolicy: BrowserPrivateDownloadFilePolicy;
  privateRecordPolicy: BrowserPrivateDownloadRecordPolicy;
}

export interface BrowserToolbarLayoutSettings {
  primaryActionIds: string[];
  secondaryActionIds: string[];
  leadingSlotActionId?: string;
  menuSlotActionId?: string;
  refreshSlotActionId?: string;
  tabsSlotActionId?: string;
  leadingSlotLongPressActionId?: string;
  menuSlotLongPressActionId?: string;
  refreshSlotLongPressActionId?: string;
  tabsSlotLongPressActionId?: string;
  leadingSlotSwipeUpActionId?: string;
  tabsSlotSwipeUpActionId?: string;
  updatedAt: number;
}

export interface BrowserUserAgentSettings {
  defaultMode: BrowserUserAgentMode;
  selectedPresetId: BrowserUserAgentPresetId;
  customUserAgent: string;
  selectedCustomUserAgentId: string;
  customUserAgents: BrowserCustomUserAgentRecord[];
  updatedAt: number;
}

export type BrowserSitePrivacyMode = 'clear_on_close';

export interface BrowserSitePrivacyRule {
  profileId: BrowserProfileId;
  origin: string;
  siteKey: string;
  displayHost: string;
  primaryOrigin: string;
  mode: BrowserSitePrivacyMode;
  includeSubdomains: boolean;
  preserveCookiesOnClose: boolean;
  updatedAt: number;
}

export type ReaderModeTheme = 'light' | 'paper' | 'sepia' | 'sage' | 'charcoal' | 'dark' | 'system';
export type ReaderModeLineHeight = 'compact' | 'comfortable' | 'loose';
export type ReaderModePageWidth = 'narrow' | 'standard' | 'wide';
export type ReaderModeBrightnessMode = 'system' | 'manual';
export type ReadingPageMode = 'horizontal' | 'horizontalFast' | 'vertical';

export interface ReaderModePreferences {
  fontSize: number;
  theme: ReaderModeTheme;
  lineHeight: ReaderModeLineHeight;
  pageWidth: ReaderModePageWidth;
  brightnessMode: ReaderModeBrightnessMode;
  brightnessPercent: number;
  pageMode: ReadingPageMode;
}

export type BrowserTabsOverviewLayoutStyle = 'grid' | 'horizontal_cards';
export type BrowserHomeShortcutLayoutDensity = 'standard' | 'compact';
export type BrowserBottomToolbarScrollBehavior = 'fixed' | 'compact' | 'hidden';

export interface BrowserAppearanceSettings {
  bottomToolbarScrollBehavior: BrowserBottomToolbarScrollBehavior;
  globalImmersionEnabled: boolean;
  alwaysTopImmersionEnabled: boolean;
  forceDarkWebContentEnabled: boolean;
  blurPrivateTabPreviews: boolean;
  showHomeRecentlyClosed: boolean;
  showHomeShortcuts: boolean;
  homeRecentlyClosedLimit: number;
  homeShortcutLayoutDensity: BrowserHomeShortcutLayoutDensity;
  homeShortcutIconSizeRatio: number;
  siteIconCornerRadiusRatio: number;
  themePaletteId: BrowserThemePaletteId;
  tabsOverviewLayoutStyle: BrowserTabsOverviewLayoutStyle;
  tabsOverviewCloseButtonAlwaysVisible: boolean;
  /** Device-local Large-Screen chrome preference; intentionally excluded from Personalization Sync. */
  showDesktopBookmarkBar?: boolean;
}

export type BrowserStartupRestorePolicy = 'restore_regular_tabs' | 'open_home';
export type BrowserPrivateTabRestorePolicy = 'never_restore' | 'restore_private_tabs';
export type BrowserTabAutoClosePolicy =
  'manual' |
  'after_15_days' |
  'after_7_days' |
  'after_3_days' |
  'after_1_day' |
  'on_app_exit';

export interface BrowserGeneralSettings {
  startupRestorePolicy: BrowserStartupRestorePolicy;
  tabAutoClosePolicy: BrowserTabAutoClosePolicy;
  privateTabRestorePolicy: BrowserPrivateTabRestorePolicy;
  privateModeAuthenticationEnabled: boolean;
  alwaysUsePrivateMode?: boolean;
  privateModePreserveCookiesOnClose: boolean;
  privateModeThemeEnabled: boolean;
  enhancedTrackingProtectionEnabled?: boolean;
}

export interface BrowserCookiePolicySettings {
  acceptCookies: boolean;
  acceptThirdPartyCookies: boolean;
}

export interface BrowserExperimentSettings {
  pauseWebAnimationsDuringScroll: boolean;
  reduceMediaMotionDuringScroll: boolean;
  strengthenAdBlockingForSmoothScroll: boolean;
  pullRefreshEnabled: boolean;
  forceEnableWebZoom: boolean;
  smartGripTabsActionsEnabled: boolean;
  webVideoTakeoverEnabled: boolean;
  novelModeEnabled: boolean;
  novelAutoTakeoverEnabled: boolean;
  appProxyActiveProfileId: string;
  appProxyProfiles: BrowserAppProxyProfile[];
  appProxyEnabled: boolean;
  appProxy: BrowserAppProxySettings;
}

export type BrowserAppProxyScheme = 'http' | 'https' | 'socks5';

export interface BrowserAppProxySettings {
  scheme: BrowserAppProxyScheme;
  host: string;
  port: number;
  username: string;
  password: string;
  bypassHosts: string;
  updatedAt: number;
}

export interface BrowserAppProxyProfile {
  id: string;
  name: string;
  settings: BrowserAppProxySettings;
  createdAt: number;
  updatedAt: number;
}

export type BrowserAppServiceMode = 'full' | 'basic';

export interface BrowserPreferences {
  appServiceMode: BrowserAppServiceMode;
  searchEngineId: SearchEngineId;
  searchSuggestions: SearchSuggestionPreferences;
  homeLayout: string;
  wallpaperEnabled: boolean;
  bookmarkSyncEnabled: boolean;
  historySyncEnabled: boolean;
  themeMode: BrowserThemeMode;
  appearance: BrowserAppearanceSettings;
  general: BrowserGeneralSettings;
  cookiePolicy: BrowserCookiePolicySettings;
  experiments: BrowserExperimentSettings;
  readerMode: ReaderModePreferences;
  downloads: BrowserDownloadSettings;
  toolbarLayout: BrowserToolbarLayoutSettings;
  sitePermissionDefaults: SitePermissionDefaultSettings;
  externalNavigation: ExternalNavigationSettings;
  retention: BrowserRetentionSettings;
  historyRetention: HistoryRetentionSettings;
}

export interface SitePermissionSettings {
  profileId: BrowserProfileId;
  origin: string;
  siteKey: string;
  displayHost: string;
  primaryOrigin: string;
  camera: SitePermissionRule;
  microphone: SitePermissionRule;
  location: SitePermissionRule;
  sensor: SitePermissionRule;
  clipboard: SitePermissionRule;
  updatedAt: number;
}

export interface SearchSuggestion {
  id: string;
  title: string;
  source: string;
  target: string;
  subtitle?: string;
  icon?: string;
  score?: number;
  refId?: string;
}

export interface BookmarkStats {
  totalNodes: number;
  bookmarkCount: number;
  folderCount: number;
}

export interface HistoryStats {
  totalVisits: number;
  latestVisitedAt: number;
}
