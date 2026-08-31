import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import urlUtils from '@ohos.url';
import {
  BookmarkImportBatchRecord,
  BookmarkOrderRecord,
  DEFAULT_BROWSER_PROFILE_ID,
  BookmarkNode,
  BookmarkRootRecord,
  BookmarkSyncLinkRecord,
  HistorySiteAggregate,
  HistoryUrlRecord,
  HistoryVisit,
  RecentlyClosedTabRecord,
  SearchQueryHistoryRecord,
  ShortcutRecord,
  ShortcutScenarioRecord,
  TabRecord
} from '../../common/models/BrowserModels';
import {
  HistorySyncBootstrapResponse,
  HistorySyncChange,
  HistorySyncDeleteRange,
  HistorySyncExactTombstone,
  HistorySyncExchangeResponse,
  HistorySyncLocalState,
  HistorySyncRetentionFrontier,
  HISTORY_SYNC_MAX_VISITS,
  HistorySyncMutation,
  HistorySyncOutboxContext,
  HISTORY_SYNC_RETENTION_MS,
  HistorySyncVisit,
  HuaweiSpaceHistorySyncState
} from '../../common/models/HistorySyncModels';
import {
  SiteIconCandidateSource,
  SiteIconMetadataRecord
} from '../../common/models/SiteIconModels';
import {
  OfflinePageOpenStatus,
  OfflinePageRecord,
  OfflinePageSaveStatus
} from '../../common/models/OfflinePageModels';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  buildBookmarkRootRecords,
  resolveBookmarkScope
} from '../repositories/BookmarkRepositoryCore';

interface DatabaseErrorLike {
  code?: number;
  message?: string;
  name?: string;
}

const DOMAIN = 0x0000;
const TAG = 'BrowserDatabase';
const DATABASE_NAME = 'aira_browser.db';
const CURRENT_BROWSER_DATABASE_SCHEMA_VERSION = 5;
const INITIAL_BROWSER_DATABASE_SCHEMA_VERSION = 1;
const BROWSER_SCHEMA_STATE_TABLE = 'browser_schema_state';
const BROWSER_SCHEMA_STATE_CURRENT_KEY = 'current';
const BROWSER_SCHEMA_STATE_SQL: string = `CREATE TABLE IF NOT EXISTS ${BROWSER_SCHEMA_STATE_TABLE} (
  state_key TEXT PRIMARY KEY,
  version INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)`;
const BOOKMARKS_TABLE = 'bookmarks';
const BOOKMARK_ROOTS_TABLE = 'bookmark_roots';
const BOOKMARK_NODES_TABLE = 'bookmark_nodes';
const BOOKMARK_ORDERS_TABLE = 'bookmark_orders';
const BOOKMARK_SYNC_LINKS_TABLE = 'bookmark_sync_links_g2';
const REMOVED_BOOKMARK_SYNC_OUTBOX_TABLE = 'bookmark_sync_outbox_g2';
const IMPORT_BATCHES_TABLE = 'import_batches';
const BOOKMARK_COLUMNS: string[] = [
  'id',
  'scope',
  'type',
  'parent_id',
  'title',
  'url',
  'position',
  'created_at',
  'updated_at',
  'sync_state',
  'sync_source',
  'last_modified_at',
  'last_modified_by',
  'device_id',
  'origin_id',
  'deleted_at'
];
const BOOKMARK_ROOT_COLUMNS: string[] = [
  'role',
  'node_id',
  'title',
  'position',
  'sync_enabled'
];
const BOOKMARK_NODE_COLUMNS: string[] = [
  'id',
  'scope',
  'type',
  'title',
  'url',
  'created_at',
  'updated_at',
  'sync_state',
  'sync_source',
  'last_modified_at',
  'last_modified_by',
  'device_id',
  'origin_id',
  'deleted_at'
];
const BOOKMARK_ORDER_COLUMNS: string[] = [
  'parent_id',
  'child_id',
  'position',
  'updated_at'
];
const BOOKMARK_SYNC_LINK_COLUMNS: string[] = [
  'node_id',
  'provider',
  'remote_entity_id',
  'origin_id',
  'updated_at'
];
const IMPORT_BATCH_COLUMNS: string[] = [
  'batch_id',
  'source_type',
  'provider_id',
  'source_label',
  'source_ref',
  'created_at',
  'completed_at',
  'imported_folder_count',
  'imported_bookmark_count',
  'skipped_node_count',
  'duplicate_count',
  'root_node_id'
];
const BOOKMARK_IMPORT_BATCH_INSERT_SIZE: number = 250;
const BOOKMARK_DOMAIN_READ_BATCH_SIZE: number = 512;
const BOOKMARK_PREVIEW_CHILD_LIMIT: number = 50;
const BOOKMARK_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${BOOKMARKS_TABLE} (
    id TEXT PRIMARY KEY,
    scope TEXT NOT NULL DEFAULT 'regular',
    type TEXT NOT NULL,
    parent_id TEXT,
    title TEXT NOT NULL,
    url TEXT,
    position INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sync_state TEXT NOT NULL,
    sync_source TEXT NOT NULL,
    last_modified_at INTEGER NOT NULL,
    last_modified_by TEXT NOT NULL,
    device_id TEXT NOT NULL,
    origin_id TEXT,
    deleted_at INTEGER
  )`,
  `CREATE INDEX IF NOT EXISTS idx_bookmarks_parent_position ON ${BOOKMARKS_TABLE}(parent_id, position)`,
  `CREATE INDEX IF NOT EXISTS idx_bookmarks_url ON ${BOOKMARKS_TABLE}(url)`,
  `CREATE INDEX IF NOT EXISTS idx_bookmarks_sync_state ON ${BOOKMARKS_TABLE}(sync_state)`,
  `CREATE INDEX IF NOT EXISTS idx_bookmarks_origin_id ON ${BOOKMARKS_TABLE}(origin_id)`,
  `CREATE INDEX IF NOT EXISTS idx_bookmarks_deleted_at ON ${BOOKMARKS_TABLE}(deleted_at)`
];
const BOOKMARK_SYNC_LINK_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${BOOKMARK_SYNC_LINKS_TABLE} (
    node_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    remote_entity_id TEXT,
    origin_id TEXT,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(node_id, provider)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_bookmark_sync_links_g2_remote ON ${BOOKMARK_SYNC_LINKS_TABLE}(remote_entity_id)`,
  `CREATE INDEX IF NOT EXISTS idx_bookmark_sync_links_g2_origin ON ${BOOKMARK_SYNC_LINKS_TABLE}(origin_id)`
];
const BOOKMARK_DOMAIN_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${BOOKMARK_ROOTS_TABLE} (
    role TEXT PRIMARY KEY,
    node_id TEXT NOT NULL,
    title TEXT NOT NULL,
    position INTEGER NOT NULL,
    sync_enabled INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_bookmark_roots_node_id ON ${BOOKMARK_ROOTS_TABLE}(node_id)`,
  `CREATE TABLE IF NOT EXISTS ${BOOKMARK_NODES_TABLE} (
    id TEXT PRIMARY KEY,
    scope TEXT NOT NULL DEFAULT 'regular',
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    url TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sync_state TEXT NOT NULL,
    sync_source TEXT NOT NULL,
    last_modified_at INTEGER NOT NULL,
    last_modified_by TEXT NOT NULL,
    device_id TEXT NOT NULL,
    origin_id TEXT,
    deleted_at INTEGER
  )`,
  `CREATE INDEX IF NOT EXISTS idx_bookmark_nodes_type ON ${BOOKMARK_NODES_TABLE}(type)`,
  `CREATE INDEX IF NOT EXISTS idx_bookmark_nodes_url ON ${BOOKMARK_NODES_TABLE}(url)`,
  `CREATE INDEX IF NOT EXISTS idx_bookmark_nodes_origin_id ON ${BOOKMARK_NODES_TABLE}(origin_id)`,
  `CREATE INDEX IF NOT EXISTS idx_bookmark_nodes_deleted_at ON ${BOOKMARK_NODES_TABLE}(deleted_at)`,
  `CREATE TABLE IF NOT EXISTS ${BOOKMARK_ORDERS_TABLE} (
    parent_id TEXT,
    child_id TEXT NOT NULL PRIMARY KEY,
    position INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS idx_bookmark_orders_parent_position ON ${BOOKMARK_ORDERS_TABLE}(parent_id, position)`,
  `CREATE TABLE IF NOT EXISTS ${IMPORT_BATCHES_TABLE} (
    batch_id TEXT PRIMARY KEY,
    source_type TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    source_label TEXT NOT NULL,
    source_ref TEXT,
    created_at INTEGER NOT NULL,
    completed_at INTEGER NOT NULL,
    imported_folder_count INTEGER NOT NULL DEFAULT 0,
    imported_bookmark_count INTEGER NOT NULL DEFAULT 0,
    skipped_node_count INTEGER NOT NULL DEFAULT 0,
    duplicate_count INTEGER NOT NULL DEFAULT 0,
    root_node_id TEXT
  )`,
  `CREATE INDEX IF NOT EXISTS idx_import_batches_created_at ON ${IMPORT_BATCHES_TABLE}(created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_import_batches_source_type ON ${IMPORT_BATCHES_TABLE}(source_type)`,
  `CREATE INDEX IF NOT EXISTS idx_import_batches_provider_id ON ${IMPORT_BATCHES_TABLE}(provider_id)`
];
const HISTORY_URLS_TABLE = 'history_urls';
const HISTORY_URL_COLUMNS: string[] = [
  'id',
  'url',
  'normalized_url',
  'url_hash',
  'origin',
  'host',
  'title',
  'visit_count',
  'typed_count',
  'last_visit_at',
  'hidden',
  'favicon_key',
  'created_at',
  'updated_at'
];
const HISTORY_URL_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${HISTORY_URLS_TABLE} (
    id TEXT PRIMARY KEY,
    url TEXT NOT NULL,
    normalized_url TEXT NOT NULL,
    url_hash TEXT NOT NULL,
    origin TEXT NOT NULL,
    host TEXT NOT NULL,
    title TEXT NOT NULL,
    visit_count INTEGER NOT NULL,
    typed_count INTEGER NOT NULL,
    last_visit_at INTEGER NOT NULL,
    hidden INTEGER NOT NULL DEFAULT 0,
    favicon_key TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_history_urls_hash ON ${HISTORY_URLS_TABLE}(url_hash)`,
  `CREATE INDEX IF NOT EXISTS idx_history_urls_last_visit ON ${HISTORY_URLS_TABLE}(last_visit_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_history_urls_host_last_visit ON ${HISTORY_URLS_TABLE}(host, last_visit_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_history_urls_title ON ${HISTORY_URLS_TABLE}(title)`
];
const HISTORY_VISITS_TABLE = 'history_visits';
const HISTORY_VISIT_COLUMNS: string[] = [
  'id',
  'url_id',
  'visited_at',
  'from_visit_id',
  'transition',
  'visit_duration_ms',
  'source',
  'device_id',
  'session_id',
  'profile_id',
  'data_scope',
  'sync_id',
  'sync_account_uid',
  'sync_origin'
];
const HISTORY_VISIT_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${HISTORY_VISITS_TABLE} (
    id TEXT PRIMARY KEY,
    url_id TEXT NOT NULL,
    visited_at INTEGER NOT NULL,
    from_visit_id TEXT,
    transition TEXT NOT NULL DEFAULT 'link',
    visit_duration_ms INTEGER NOT NULL DEFAULT 0,
    source TEXT NOT NULL,
    device_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    profile_id TEXT NOT NULL DEFAULT 'profile-main',
    data_scope TEXT NOT NULL DEFAULT 'profile_persistent',
    sync_id TEXT NOT NULL DEFAULT '',
    sync_account_uid TEXT NOT NULL DEFAULT '',
    sync_origin TEXT NOT NULL DEFAULT ''
  )`,
  `CREATE INDEX IF NOT EXISTS idx_history_visits_url_time ON ${HISTORY_VISITS_TABLE}(url_id, visited_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_history_visits_visited_at ON ${HISTORY_VISITS_TABLE}(visited_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_history_visits_from_visit ON ${HISTORY_VISITS_TABLE}(from_visit_id)`,
  `CREATE INDEX IF NOT EXISTS idx_history_visits_session ON ${HISTORY_VISITS_TABLE}(session_id, visited_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_history_visits_profile_scope ON ${HISTORY_VISITS_TABLE}(profile_id, data_scope, visited_at DESC)`,
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_history_visits_sync_id ON ${HISTORY_VISITS_TABLE}(sync_id) WHERE sync_id <> ''`,
  `CREATE INDEX IF NOT EXISTS idx_history_visits_sync_account ON ${HISTORY_VISITS_TABLE}(sync_account_uid, sync_origin)`
];
const HISTORY_SYNC_OUTBOX_TABLE = 'history_sync_outbox_v1';
const HISTORY_SYNC_STATE_TABLE = 'history_sync_state_v1';
const HISTORY_SYNC_DELETE_RANGES_TABLE = 'history_sync_delete_ranges_v1';
const HISTORY_SYNC_FRONTIERS_TABLE = 'history_sync_frontiers_v1';
const HISTORY_SYNC_CANONICAL_VISITS_TABLE = 'history_sync_canonical_visits_v1';
const HISTORY_SYNC_TOMBSTONES_TABLE = 'history_sync_tombstones_v1';
const HISTORY_SYNC_RETENTION_TABLE = 'history_sync_retention_v1';
const HISTORY_SYNC_CANONICAL_BACKFILL_BATCH_SIZE: number = 200;
const HISTORY_SYNC_CANONICAL_READ_BATCH_SIZE: number = 128;
const HISTORY_SYNC_CANONICAL_BACKFILL_STATE_PREFIX: string = 'history_canonical_backfill:';
const HISTORY_SYNC_CANONICAL_BACKFILL_STATE_VERSION: number = 1;
const HISTORY_SYNC_RETENTION_FRONTIER_GRANULARITY_MS: number = 24 * 60 * 60 * 1000;
const HISTORY_SYNC_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${HISTORY_SYNC_OUTBOX_TABLE} (
    account_uid TEXT NOT NULL,
    mutation_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY(account_uid, mutation_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_history_sync_outbox_account_created
    ON ${HISTORY_SYNC_OUTBOX_TABLE}(account_uid, created_at, mutation_id)`,
  `CREATE TABLE IF NOT EXISTS ${HISTORY_SYNC_STATE_TABLE} (
    account_uid TEXT PRIMARY KEY,
    client_id TEXT NOT NULL,
    initialized INTEGER NOT NULL DEFAULT 0,
    cursor INTEGER NOT NULL DEFAULT 0,
    bootstrap_head INTEGER NOT NULL DEFAULT 0,
    bootstrap_after_updated_seq INTEGER NOT NULL DEFAULT 0,
    bootstrap_after_visit_id TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS ${HISTORY_SYNC_DELETE_RANGES_TABLE} (
    account_uid TEXT NOT NULL,
    range_id TEXT NOT NULL,
    url TEXT NOT NULL,
    started_at INTEGER NOT NULL,
    ended_at INTEGER NOT NULL,
    seq INTEGER NOT NULL,
    PRIMARY KEY(account_uid, range_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_history_sync_delete_ranges_match
    ON ${HISTORY_SYNC_DELETE_RANGES_TABLE}(account_uid, url, started_at, ended_at)`,
  `CREATE TABLE IF NOT EXISTS ${HISTORY_SYNC_FRONTIERS_TABLE} (
    account_uid TEXT PRIMARY KEY,
    clear_before INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS ${HISTORY_SYNC_CANONICAL_VISITS_TABLE} (
    account_uid TEXT NOT NULL,
    visit_id TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    visited_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(account_uid, visit_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_history_sync_canonical_visits_account_time
    ON ${HISTORY_SYNC_CANONICAL_VISITS_TABLE}(account_uid, visited_at DESC, visit_id DESC)`,
  `CREATE TABLE IF NOT EXISTS ${HISTORY_SYNC_TOMBSTONES_TABLE} (
    account_uid TEXT NOT NULL,
    visit_id TEXT NOT NULL,
    deleted_at INTEGER NOT NULL,
    PRIMARY KEY(account_uid, visit_id)
  )`,
  `CREATE INDEX IF NOT EXISTS idx_history_sync_tombstones_account_deleted
    ON ${HISTORY_SYNC_TOMBSTONES_TABLE}(account_uid, deleted_at DESC, visit_id)`,
  `CREATE TABLE IF NOT EXISTS ${HISTORY_SYNC_RETENTION_TABLE} (
    account_uid TEXT PRIMARY KEY,
    cutoff_at INTEGER NOT NULL DEFAULT 0,
    boundary_visited_at INTEGER NOT NULL DEFAULT 0,
    boundary_visit_id TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL DEFAULT 0
  )`
];
const SEARCH_QUERY_HISTORY_TABLE = 'search_query_history';
const SEARCH_QUERY_HISTORY_COLUMNS: string[] = [
  'id',
  'query',
  'normalized_query',
  'compact_query',
  'search_engine_id',
  'use_count',
  'first_searched_at',
  'last_searched_at',
  'profile_id',
  'data_scope'
];
const SEARCH_QUERY_HISTORY_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${SEARCH_QUERY_HISTORY_TABLE} (
    id TEXT PRIMARY KEY,
    query TEXT NOT NULL,
    normalized_query TEXT NOT NULL,
    compact_query TEXT NOT NULL,
    search_engine_id TEXT NOT NULL,
    use_count INTEGER NOT NULL,
    first_searched_at INTEGER NOT NULL,
    last_searched_at INTEGER NOT NULL,
    profile_id TEXT NOT NULL,
    data_scope TEXT NOT NULL
  )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_search_query_history_profile_query ON ${SEARCH_QUERY_HISTORY_TABLE}(profile_id, data_scope, normalized_query)`,
  `CREATE INDEX IF NOT EXISTS idx_search_query_history_recent ON ${SEARCH_QUERY_HISTORY_TABLE}(profile_id, data_scope, last_searched_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_search_query_history_normalized ON ${SEARCH_QUERY_HISTORY_TABLE}(profile_id, data_scope, normalized_query)`,
  `CREATE INDEX IF NOT EXISTS idx_search_query_history_compact ON ${SEARCH_QUERY_HISTORY_TABLE}(profile_id, data_scope, compact_query)`
];
const HISTORY_STRESS_URL_ID_PREFIX = 'history-stress-url-';
const HISTORY_STRESS_VISIT_ID_PREFIX = 'history-stress-visit-';
const HISTORY_STRESS_INSERT_BATCH_SIZE = 200;
const HISTORY_HYDRATE_BATCH_URL_THRESHOLD = 80;
const OFFLINE_PAGES_TABLE = 'offline_pages';
const OFFLINE_PAGE_COLUMNS: string[] = [
  'id',
  'original_url',
  'normalized_url',
  'url_hash',
  'title',
  'site_name',
  'host',
  'saved_at',
  'updated_at',
  'snapshot_path',
  'manifest_path',
  'preview_image_uri',
  'favicon_uri',
  'total_bytes',
  'resource_count',
  'failed_resource_count',
  'save_status',
  'open_status'
];
const OFFLINE_PAGE_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${OFFLINE_PAGES_TABLE} (
    id TEXT PRIMARY KEY,
    original_url TEXT NOT NULL,
    normalized_url TEXT NOT NULL,
    url_hash TEXT NOT NULL,
    title TEXT NOT NULL,
    site_name TEXT NOT NULL,
    host TEXT NOT NULL,
    saved_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    snapshot_path TEXT NOT NULL,
    manifest_path TEXT NOT NULL,
    preview_image_uri TEXT,
    favicon_uri TEXT,
    total_bytes INTEGER NOT NULL,
    resource_count INTEGER NOT NULL,
    failed_resource_count INTEGER NOT NULL,
    save_status TEXT NOT NULL,
    open_status TEXT NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS idx_offline_pages_saved_at ON ${OFFLINE_PAGES_TABLE}(saved_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_offline_pages_url_hash ON ${OFFLINE_PAGES_TABLE}(url_hash)`,
  `CREATE INDEX IF NOT EXISTS idx_offline_pages_host_saved_at ON ${OFFLINE_PAGES_TABLE}(host, saved_at DESC)`
];
const SHORTCUT_SCENARIOS_TABLE = 'shortcut_scenarios';
const SHORTCUT_SCENARIO_COLUMNS: string[] = [
  'id',
  'name',
  'color',
  'icon',
  'position',
  'archived',
  'created_at',
  'updated_at',
  'sync_state',
  'sync_source',
  'last_modified_at',
  'last_modified_by',
  'device_id',
  'origin_id',
  'deleted_at'
];
const SHORTCUT_SCENARIO_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${SHORTCUT_SCENARIOS_TABLE} (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    icon TEXT NOT NULL,
    position INTEGER NOT NULL,
    archived INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sync_state TEXT NOT NULL,
    sync_source TEXT NOT NULL,
    last_modified_at INTEGER NOT NULL,
    last_modified_by TEXT NOT NULL,
    device_id TEXT NOT NULL,
    origin_id TEXT,
    deleted_at INTEGER
  )`,
  `CREATE INDEX IF NOT EXISTS idx_shortcut_scenarios_position ON ${SHORTCUT_SCENARIOS_TABLE}(position)`,
  `CREATE INDEX IF NOT EXISTS idx_shortcut_scenarios_origin_id ON ${SHORTCUT_SCENARIOS_TABLE}(origin_id)`,
  `CREATE INDEX IF NOT EXISTS idx_shortcut_scenarios_deleted_at ON ${SHORTCUT_SCENARIOS_TABLE}(deleted_at)`
];
const SHORTCUTS_TABLE = 'shortcuts';
const SHORTCUT_COLUMNS: string[] = [
  'id',
  'scenario_id',
  'title',
  'url',
  'folder_name',
  'position',
  'icon',
  'description',
  'kind',
  'children',
  'folder_display_mode',
  'use_official_icon',
  'auto_use_official_icon',
  'official_icon_available_at_save',
  'official_icon_color_override',
  'icon_rendering',
  'icon_color',
  'created_at',
  'updated_at',
  'sync_state',
  'sync_source',
  'last_modified_at',
  'last_modified_by',
  'device_id',
  'origin_id',
  'deleted_at'
];
const SHORTCUT_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${SHORTCUTS_TABLE} (
    id TEXT PRIMARY KEY,
    scenario_id TEXT NOT NULL,
    title TEXT NOT NULL,
    url TEXT NOT NULL,
    folder_name TEXT NOT NULL,
    position INTEGER NOT NULL,
    icon TEXT,
    description TEXT,
    kind TEXT,
    children TEXT,
    folder_display_mode TEXT,
    use_official_icon INTEGER,
    auto_use_official_icon INTEGER,
    official_icon_available_at_save INTEGER,
    official_icon_color_override INTEGER,
    icon_rendering TEXT,
    icon_color TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sync_state TEXT NOT NULL,
    sync_source TEXT NOT NULL,
    last_modified_at INTEGER NOT NULL,
    last_modified_by TEXT NOT NULL,
    device_id TEXT NOT NULL,
    origin_id TEXT,
    deleted_at INTEGER
  )`,
  `CREATE INDEX IF NOT EXISTS idx_shortcuts_scenario_position ON ${SHORTCUTS_TABLE}(scenario_id, position)`,
  `CREATE INDEX IF NOT EXISTS idx_shortcuts_url ON ${SHORTCUTS_TABLE}(url)`,
  `CREATE INDEX IF NOT EXISTS idx_shortcuts_origin_id ON ${SHORTCUTS_TABLE}(origin_id)`,
  `CREATE INDEX IF NOT EXISTS idx_shortcuts_deleted_at ON ${SHORTCUTS_TABLE}(deleted_at)`
];
const TAB_SESSIONS_TABLE = 'tab_sessions';
const TAB_SESSION_COLUMNS: string[] = [
  'id',
  'window_id',
  'profile_id',
  'title',
  'url',
  'is_active',
  'is_pinned',
  'last_active_at',
  'tab_order',
  'is_home',
  'pending_url',
  'navigation_history',
  'navigation_index',
  'runtime_state',
  'last_error',
  'last_loaded_at',
  'web_state_path',
  'web_state_updated_at',
  'scroll_offset_y',
  'form_draft',
  'page_runtime_signals',
  'last_good_url',
  'last_good_title',
  'last_restorable_url',
  'last_restorable_title',
  'last_restore_type',
  'last_restore_reason',
  'last_discard_reason',
  'last_crash_reason',
  'privacy_mode',
  'data_scope',
  'launch_source_type',
  'launch_source_id',
  'launch_source_url',
  'launch_key'
];
const TAB_SESSION_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${TAB_SESSIONS_TABLE} (
    id TEXT PRIMARY KEY,
    window_id TEXT NOT NULL,
    profile_id TEXT NOT NULL DEFAULT 'profile-main',
    title TEXT NOT NULL,
    url TEXT NOT NULL,
    is_active INTEGER NOT NULL,
    is_pinned INTEGER NOT NULL,
    last_active_at INTEGER NOT NULL,
    tab_order INTEGER NOT NULL DEFAULT 0,
    is_home INTEGER NOT NULL DEFAULT 0,
    pending_url TEXT,
    navigation_history TEXT,
    navigation_index INTEGER NOT NULL DEFAULT -1,
    runtime_state TEXT NOT NULL DEFAULT 'background',
    last_error TEXT,
    last_loaded_at INTEGER NOT NULL DEFAULT 0,
    web_state_path TEXT,
    web_state_updated_at INTEGER NOT NULL DEFAULT 0,
    scroll_offset_y INTEGER NOT NULL DEFAULT 0,
    form_draft TEXT,
    page_runtime_signals TEXT,
    last_good_url TEXT,
    last_good_title TEXT,
    last_restorable_url TEXT,
    last_restorable_title TEXT,
    last_restore_type TEXT NOT NULL DEFAULT 'none',
    last_restore_reason TEXT,
    last_discard_reason TEXT,
    last_crash_reason TEXT,
    privacy_mode TEXT NOT NULL DEFAULT 'regular',
    data_scope TEXT NOT NULL DEFAULT 'profile_persistent',
    launch_source_type TEXT,
    launch_source_id TEXT,
    launch_source_url TEXT,
    launch_key TEXT
  )`,
  `CREATE INDEX IF NOT EXISTS idx_tab_sessions_window_active ON ${TAB_SESSIONS_TABLE}(window_id, is_active)`,
  `CREATE INDEX IF NOT EXISTS idx_tab_sessions_window_last_active ON ${TAB_SESSIONS_TABLE}(window_id, last_active_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_tab_sessions_window_profile_last_active ON ${TAB_SESSIONS_TABLE}(window_id, profile_id, last_active_at DESC)`
];
const RECENTLY_CLOSED_TABS_TABLE = 'recently_closed_tabs';
const RECENTLY_CLOSED_TAB_COLUMNS: string[] = [
  'id',
  'original_tab_id',
  'closed_at',
  'window_id',
  'profile_id',
  'site_icon_uri',
  'tab_payload'
];
const RECENTLY_CLOSED_TAB_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${RECENTLY_CLOSED_TABS_TABLE} (
    id TEXT PRIMARY KEY,
    original_tab_id TEXT NOT NULL,
    closed_at INTEGER NOT NULL,
    window_id TEXT NOT NULL,
    profile_id TEXT NOT NULL DEFAULT 'profile-main',
    site_icon_uri TEXT,
    tab_payload TEXT NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS idx_recently_closed_window_closed_at ON ${RECENTLY_CLOSED_TABS_TABLE}(window_id, closed_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_recently_closed_window_profile_closed_at ON ${RECENTLY_CLOSED_TABS_TABLE}(window_id, profile_id, closed_at DESC)`
];
const SITE_ICONS_TABLE = 'site_icons';
const SITE_ICON_COLUMNS: string[] = [
  'domain',
  'icon_url',
  'source',
  'extension',
  'file_uri',
  'quality_score',
  'width',
  'height',
  'last_accessed_at',
  'updated_at'
];
const SITE_ICON_SCHEMA_SQL: string[] = [
  `CREATE TABLE IF NOT EXISTS ${SITE_ICONS_TABLE} (
    domain TEXT PRIMARY KEY,
    icon_url TEXT NOT NULL,
    source TEXT NOT NULL,
    extension TEXT NOT NULL,
    file_uri TEXT NOT NULL,
    quality_score INTEGER NOT NULL,
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    last_accessed_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS idx_site_icons_last_accessed_at ON ${SITE_ICONS_TABLE}(last_accessed_at)`,
  `CREATE INDEX IF NOT EXISTS idx_site_icons_updated_at ON ${SITE_ICONS_TABLE}(updated_at)`,
  `CREATE INDEX IF NOT EXISTS idx_site_icons_source ON ${SITE_ICONS_TABLE}(source)`
];

export class BrowserDatabase {
  private store?: relationalStore.RdbStore;
  private storePromise?: Promise<relationalStore.RdbStore>;
  private historySyncCanonicalBackfilledAccounts: Set<string> = new Set<string>();

  async initialize(): Promise<void> {
    await this.getStore();
  }

  async listBookmarkNodes(): Promise<BookmarkNode[]> {
    try {
      const store = await this.getStore();
      return await this.listBookmarkNodesFromDomainTables(store);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load bookmark nodes: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async listBookmarkPreviewChildren(
    parentId?: string,
    limit: number = BOOKMARK_PREVIEW_CHILD_LIMIT,
    scope?: 'regular' | 'private'
  ): Promise<BookmarkNode[]> {
    try {
      const store = await this.getStore();
      return await this.listBookmarkPreviewChildrenFromDomainTables(store, parentId, limit, scope);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load bookmark preview children: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async seedBookmarksIfEmpty(nodes: BookmarkNode[]): Promise<boolean> {
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(BOOKMARK_NODES_TABLE);
      predicates.limitAs(1);
      const resultSet = await store.query(predicates, ['id']);
      try {
        if (resultSet.rowCount > 0) {
          return false;
        }
      } finally {
        try {
          resultSet.close();
        } catch (closeError) {
          hilog.warn(DOMAIN, TAG, 'Failed to close seed query result set: %{public}s', JSON.stringify(closeError));
        }
      }

      await this.seedBookmarkRootsIfEmpty(store);
      for (const node of nodes) {
        await this.upsertBookmarkNodeToDomainTables(store, node);
      }

      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to seed bookmark nodes: %{public}s', JSON.stringify(error));
      throw new Error('Failed to seed bookmark database.');
    }
  }

  async upsertBookmarkNode(node: BookmarkNode): Promise<void> {
    try {
      const store = await this.getStore();
      await this.upsertBookmarkNodeToDomainTables(store, node);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to upsert bookmark node: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save bookmark node.');
    }
  }

  async upsertBookmarkNodes(nodes: BookmarkNode[]): Promise<void> {
    if (nodes.length === 0) {
      return;
    }
    let transactionStarted = false;
    let store: relationalStore.RdbStore | undefined = undefined;
    try {
      store = await this.getStore();
      store.beginTransaction();
      transactionStarted = true;
      await this.batchUpsertBookmarkDomainRows(store, nodes);
      store.commit();
      transactionStarted = false;
    } catch (error) {
      this.rollbackBookmarkTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to upsert bookmark nodes: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save bookmark nodes.');
    }
  }

  async upsertImportedBookmarkNodes(nodes: BookmarkNode[]): Promise<void> {
    if (nodes.length === 0) {
      return;
    }
    let transactionStarted = false;
    let store: relationalStore.RdbStore | undefined = undefined;
    try {
      store = await this.getStore();
      store.beginTransaction();
      transactionStarted = true;
      await this.batchUpsertImportedBookmarkNodeRows(store, nodes);
      await this.batchUpsertImportedBookmarkOrderRows(store, nodes);
      await this.batchUpsertImportedBookmarkSyncLinkRows(store, nodes);
      store.commit();
      transactionStarted = false;
    } catch (error) {
      this.rollbackBookmarkTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to upsert imported bookmark nodes: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save imported bookmark nodes.');
    }
  }

  async updateBookmarkNode(node: BookmarkNode): Promise<boolean> {
    try {
      const store = await this.getStore();
      const existing = await this.findBookmarkNodeById(store, node.id);
      if (existing === undefined) {
        return false;
      }
      await this.upsertBookmarkNodeToDomainTables(store, node);
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update bookmark node: %{public}s', JSON.stringify(error));
      throw new Error('Failed to update bookmark node.');
    }
  }

  async updateBookmarkPositions(nodes: BookmarkNode[]): Promise<void> {
    if (nodes.length === 0) {
      return;
    }
    let transactionStarted = false;
    let store: relationalStore.RdbStore | undefined = undefined;
    try {
      store = await this.getStore();
      store.beginTransaction();
      transactionStarted = true;
      await this.batchUpsertBookmarkDomainRows(store, nodes);
      store.commit();
      transactionStarted = false;
    } catch (error) {
      this.rollbackBookmarkTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to update bookmark positions: %{public}s', JSON.stringify(error));
      throw new Error('Failed to update bookmark positions.');
    }
  }

  async replaceBookmarkTree(nodes: BookmarkNode[], scope: 'regular' | 'private' = 'regular'): Promise<void> {
    try {
      const store = await this.getStore();
      const normalizedScope = resolveBookmarkScope(scope);
      const nodePredicates = new relationalStore.RdbPredicates(BOOKMARK_NODES_TABLE);
      nodePredicates.equalTo('scope', normalizedScope);
      const existingNodes = this.mapBookmarkNodeRows(await store.query(nodePredicates, BOOKMARK_NODE_COLUMNS));
      const existingIds = existingNodes.map((node: BookmarkNode) => node.id);
      if (existingIds.length > 0) {
        const syncPredicates = new relationalStore.RdbPredicates(BOOKMARK_SYNC_LINKS_TABLE);
        syncPredicates.in('node_id', existingIds);
        await store.delete(syncPredicates);
        const orderPredicates = new relationalStore.RdbPredicates(BOOKMARK_ORDERS_TABLE);
        orderPredicates.in('child_id', existingIds);
        await store.delete(orderPredicates);
      }
      await store.delete(nodePredicates);
      await this.seedBookmarkRootsIfEmpty(store);
      await this.batchUpsertBookmarkDomainRows(store, nodes);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to replace bookmark tree: %{public}s', JSON.stringify(error));
      throw new Error('Failed to replace bookmark tree.');
    }
  }

  async purgeDeletedBookmarkNodes(
    scope: 'regular' | 'private',
    deletedBefore?: number
  ): Promise<number> {
    try {
      const store = await this.getStore();
      const normalizedScope = resolveBookmarkScope(scope);
      const nodePredicates = new relationalStore.RdbPredicates(BOOKMARK_NODES_TABLE);
      nodePredicates.equalTo('scope', normalizedScope).isNotNull('deleted_at');
      if (deletedBefore !== undefined) {
        nodePredicates.lessThan('deleted_at', deletedBefore);
      }
      const deletedNodes = this.mapBookmarkNodeRows(await store.query(nodePredicates, BOOKMARK_NODE_COLUMNS));
      const deletedIds = deletedNodes.map((node: BookmarkNode): string => node.id);
      if (deletedIds.length <= 0) {
        return 0;
      }
      const syncPredicates = new relationalStore.RdbPredicates(BOOKMARK_SYNC_LINKS_TABLE);
      syncPredicates.in('node_id', deletedIds);
      await store.delete(syncPredicates);
      const childOrderPredicates = new relationalStore.RdbPredicates(BOOKMARK_ORDERS_TABLE);
      childOrderPredicates.in('child_id', deletedIds);
      await store.delete(childOrderPredicates);
      const parentOrderPredicates = new relationalStore.RdbPredicates(BOOKMARK_ORDERS_TABLE);
      parentOrderPredicates.in('parent_id', deletedIds);
      await store.delete(parentOrderPredicates);
      return await store.delete(nodePredicates);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to purge deleted bookmark nodes: %{public}s', JSON.stringify(error));
      throw new Error('Failed to purge deleted bookmark nodes.');
    }
  }

  async upsertBookmarkImportBatch(batch: BookmarkImportBatchRecord): Promise<void> {
    try {
      const store = await this.getStore();
      const predicates = this.createImportBatchIdPredicates(batch.batchId);
      const count = await store.update(this.toImportBatchValues(batch), predicates);
      if (count === 0) {
        await store.insert(IMPORT_BATCHES_TABLE, this.toImportBatchValues(batch));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to upsert bookmark import batch: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save bookmark import batch.');
    }
  }

  async listBookmarkImportBatches(limit?: number): Promise<BookmarkImportBatchRecord[]> {
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(IMPORT_BATCHES_TABLE);
      predicates.orderByDesc('created_at');
      if (limit !== undefined && limit > 0) {
        predicates.limitAs(limit);
      }
      const resultSet = await store.query(predicates, IMPORT_BATCH_COLUMNS);
      return this.mapImportBatchRows(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load bookmark import batches: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async listHistoryVisits(limit?: number, offset?: number): Promise<HistoryVisit[]> {
    try {
      const startedAt = Date.now();
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
      predicates.orderByDesc('visited_at');
      if (limit !== undefined && limit > 0) {
        predicates.limitAs(limit);
      }
      if (offset !== undefined && offset > 0) {
        predicates.offsetAs(offset);
      }
      const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
      const visits = this.mapHistoryVisitEventRows(resultSet);
      const hydrated = await this.hydrateHistoryVisits(visits);
      hilog.info(DOMAIN, TAG,
        'Loaded history visits count=%{public}d limit=%{public}d offset=%{public}d durationMs=%{public}d',
        hydrated.length, limit ?? 0, offset ?? 0, Date.now() - startedAt);
      return hydrated;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load history visits: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async searchHistoryVisits(query: string, offset: number, limit: number): Promise<HistoryVisit[]> {
    const normalizedQuery = query.trim().toLowerCase();
    const normalizedOffset = Math.max(0, Math.floor(offset));
    const normalizedLimit = Math.max(1, Math.floor(limit));
    if (normalizedQuery.length === 0) {
      return this.listHistoryVisits(normalizedLimit, normalizedOffset);
    }
    try {
      const startedAt = Date.now();
      const store = await this.getStore();
      const pattern = `%${normalizedQuery}%`;
      const resultSet = await store.querySql(
        `SELECT
          v.id AS id,
          v.url_id AS url_id,
          v.visited_at AS visited_at,
          v.from_visit_id AS from_visit_id,
          v.transition AS transition,
          v.visit_duration_ms AS visit_duration_ms,
          v.source AS source,
          v.device_id AS device_id,
          v.session_id AS session_id,
          v.profile_id AS profile_id,
          v.data_scope AS data_scope
        FROM ${HISTORY_VISITS_TABLE} v
        INNER JOIN ${HISTORY_URLS_TABLE} u ON v.url_id = u.id
        WHERE u.hidden = 0 AND (
          lower(u.title) LIKE ? OR
          lower(u.url) LIKE ? OR
          lower(u.host) LIKE ?
        )
        ORDER BY v.visited_at DESC
        LIMIT ? OFFSET ?`,
        [pattern, pattern, pattern, normalizedLimit, normalizedOffset]
      );
      const visits = this.mapHistoryVisitEventRows(resultSet);
      const hydrated = await this.hydrateHistoryVisits(visits);
      hilog.info(DOMAIN, TAG,
        'Searched history visits count=%{public}d limit=%{public}d offset=%{public}d durationMs=%{public}d',
        hydrated.length, normalizedLimit, normalizedOffset, Date.now() - startedAt);
      return hydrated;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to search history visits: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async listHistorySiteAggregates(query: string, offset: number, limit: number): Promise<HistorySiteAggregate[]> {
    const normalizedQuery = query.trim().toLowerCase();
    const normalizedOffset = Math.max(0, Math.floor(offset));
    const normalizedLimit = Math.max(1, Math.floor(limit));
    const hasQuery = normalizedQuery.length > 0;
    const whereClause = hasQuery ?
      `WHERE hidden = 0 AND (lower(host) LIKE ? OR lower(title) LIKE ? OR lower(url) LIKE ?)` :
      `WHERE hidden = 0`;
    const bindArgs: relationalStore.ValueType[] = [];
    if (hasQuery) {
      const pattern = `%${normalizedQuery}%`;
      bindArgs.push(pattern, pattern, pattern);
    }
    bindArgs.push(normalizedLimit, normalizedOffset);
    try {
      const startedAt = Date.now();
      const store = await this.getStore();
      const resultSet = await store.querySql(
        `SELECT
          agg.host AS host,
          latest.origin AS origin,
          latest.title AS latest_title,
          latest.url AS latest_url,
          agg.latest_visited_at AS latest_visited_at,
          agg.visit_count AS visit_count,
          agg.unique_url_count AS unique_url_count
        FROM (
          SELECT
            host,
            SUM(visit_count) AS visit_count,
            COUNT(*) AS unique_url_count,
            MAX(last_visit_at) AS latest_visited_at
          FROM ${HISTORY_URLS_TABLE}
          ${whereClause}
          GROUP BY host
          ORDER BY latest_visited_at DESC
          LIMIT ? OFFSET ?
        ) agg
        INNER JOIN ${HISTORY_URLS_TABLE} latest
          ON latest.host = agg.host AND latest.last_visit_at = agg.latest_visited_at
        GROUP BY agg.host
        ORDER BY agg.latest_visited_at DESC`,
        bindArgs
      );
      const sites = this.mapHistorySiteAggregateRows(resultSet);
      hilog.info(DOMAIN, TAG,
        'Loaded history sites count=%{public}d limit=%{public}d offset=%{public}d durationMs=%{public}d',
        sites.length, normalizedLimit, normalizedOffset, Date.now() - startedAt);
      return sites;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load history sites: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async upsertHistoryVisit(visit: HistoryVisit, syncContext?: HistorySyncOutboxContext): Promise<void> {
    let store: relationalStore.RdbStore | undefined = undefined;
    let transactionStarted = false;
    try {
      store = await this.getStore();
      if (syncContext !== undefined) {
        store.beginTransaction();
        transactionStarted = true;
      }
      await this.upsertHistoryVisitInStore(store, visit);
      if (syncContext !== undefined && syncContext.origin === 'local_capture') {
        await this.enqueueHistoryVisitUpsert(store, visit, syncContext);
      }
      if (transactionStarted) {
        store.commit();
        transactionStarted = false;
      }
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to upsert history visit: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save history visit.');
    }
  }

  async listSearchQueryHistory(
    profileId: string,
    dataScope: string,
    limit?: number
  ): Promise<SearchQueryHistoryRecord[]> {
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(SEARCH_QUERY_HISTORY_TABLE);
      predicates.equalTo('profile_id', profileId);
      predicates.equalTo('data_scope', dataScope);
      predicates.orderByDesc('last_searched_at');
      if (limit !== undefined && limit > 0) {
        predicates.limitAs(Math.floor(limit));
      }
      const resultSet = await store.query(predicates, SEARCH_QUERY_HISTORY_COLUMNS);
      return this.mapSearchQueryHistoryRows(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to list search query history: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async upsertSearchQueryHistory(record: SearchQueryHistoryRecord): Promise<void> {
    try {
      const store = await this.getStore();
      const predicates = this.createSearchQueryHistoryIdPredicates(record.id);
      const values = this.toSearchQueryHistoryValues(record);
      const count = await store.update(values, predicates);
      if (count === 0) {
        await store.insert(SEARCH_QUERY_HISTORY_TABLE, values);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to upsert search query history: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save search query history.');
    }
  }

  async deleteSearchQueryHistoryByIds(ids: string[]): Promise<number> {
    const uniqueIds = Array.from(new Set<string>(ids.map((id: string) => id.trim()).filter((id: string) => id.length > 0)));
    if (uniqueIds.length === 0) {
      return 0;
    }
    try {
      const store = await this.getStore();
      let removed = 0;
      for (const id of uniqueIds) {
        removed += await store.delete(this.createSearchQueryHistoryIdPredicates(id));
      }
      return removed;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete search query history by ids: %{public}s', JSON.stringify(error));
      throw new Error('Failed to delete search query history.');
    }
  }

  async deleteSearchQueryHistoryInRange(startAt: number, endAt: number): Promise<number> {
    const normalizedStartAt = Math.max(0, Math.round(startAt));
    const normalizedEndAt = Math.max(normalizedStartAt, Math.round(endAt));
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(SEARCH_QUERY_HISTORY_TABLE);
      predicates.between('last_searched_at', normalizedStartAt, normalizedEndAt);
      return await store.delete(predicates);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete search query history in range: %{public}s', JSON.stringify(error));
      throw new Error('Failed to delete search query history in range.');
    }
  }

  async clearSearchQueryHistory(profileId?: string, dataScope?: string): Promise<number> {
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(SEARCH_QUERY_HISTORY_TABLE);
      if (profileId !== undefined && profileId.trim().length > 0) {
        predicates.equalTo('profile_id', profileId.trim());
      }
      if (dataScope !== undefined && dataScope.trim().length > 0) {
        predicates.equalTo('data_scope', dataScope.trim());
      }
      return await store.delete(predicates);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear search query history: %{public}s', JSON.stringify(error));
      throw new Error('Failed to clear search query history.');
    }
  }

  async seedHistoryStressFixture(targetTotalCount: number): Promise<number> {
    const safeTarget = Math.max(0, Math.floor(targetTotalCount));
    const store = await this.getStore();
    await store.executeSql(`DELETE FROM ${HISTORY_VISITS_TABLE} WHERE id LIKE '${HISTORY_STRESS_VISIT_ID_PREFIX}%'`);
    await store.executeSql(`DELETE FROM ${HISTORY_URLS_TABLE} WHERE id LIKE '${HISTORY_STRESS_URL_ID_PREFIX}%'`);
    const existingCount = await this.countHistoryVisits(store);
    const insertCount = Math.max(0, safeTarget - existingCount);
    if (insertCount <= 0) {
      return 0;
    }
    const now = Date.now();
    for (let start = 0; start < insertCount; start += HISTORY_STRESS_INSERT_BATCH_SIZE) {
      const end = Math.min(insertCount, start + HISTORY_STRESS_INSERT_BATCH_SIZE);
      await store.executeSql(this.buildHistoryStressUrlInsertSql(start, end, now));
      await store.executeSql(this.buildHistoryStressVisitInsertSql(start, end, now));
    }
    return insertCount;
  }

  async listOfflinePages(limit?: number): Promise<OfflinePageRecord[]> {
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(OFFLINE_PAGES_TABLE);
      predicates.orderByDesc('saved_at');
      if (limit !== undefined && limit > 0) {
        predicates.limitAs(limit);
      }
      const resultSet = await store.query(predicates, OFFLINE_PAGE_COLUMNS);
      return this.mapOfflinePageRows(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load offline pages: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async findOfflinePageById(id: string): Promise<OfflinePageRecord | undefined> {
    const normalizedId = id.trim();
    if (normalizedId.length === 0) {
      return undefined;
    }
    try {
      const store = await this.getStore();
      const resultSet = await store.query(this.createOfflinePageIdPredicates(normalizedId), OFFLINE_PAGE_COLUMNS);
      return this.mapSingleOfflinePageRow(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to find offline page by id: %{public}s', JSON.stringify(error));
      return undefined;
    }
  }

  async findOfflinePageByUrlHash(urlHash: string): Promise<OfflinePageRecord | undefined> {
    const normalizedHash = urlHash.trim();
    if (normalizedHash.length === 0) {
      return undefined;
    }
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(OFFLINE_PAGES_TABLE);
      predicates.equalTo('url_hash', normalizedHash);
      predicates.orderByDesc('saved_at');
      predicates.limitAs(1);
      const resultSet = await store.query(predicates, OFFLINE_PAGE_COLUMNS);
      return this.mapSingleOfflinePageRow(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to find offline page by url hash: %{public}s', JSON.stringify(error));
      return undefined;
    }
  }

  async upsertOfflinePage(record: OfflinePageRecord): Promise<void> {
    try {
      const store = await this.getStore();
      const predicates = this.createOfflinePageIdPredicates(record.id);
      const values = this.toOfflinePageValues(record);
      const count = await store.update(values, predicates);
      if (count === 0) {
        await store.insert(OFFLINE_PAGES_TABLE, values);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to upsert offline page: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save offline page.');
    }
  }

  async deleteOfflinePage(id: string): Promise<boolean> {
    const normalizedId = id.trim();
    if (normalizedId.length === 0) {
      return false;
    }
    try {
      const store = await this.getStore();
      const count = await store.delete(this.createOfflinePageIdPredicates(normalizedId));
      return count > 0;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete offline page: %{public}s', JSON.stringify(error));
      throw new Error('Failed to delete offline page.');
    }
  }

  async deleteHistoryVisit(id: string, syncContext?: HistorySyncOutboxContext): Promise<boolean> {
    let store: relationalStore.RdbStore | undefined = undefined;
    let transactionStarted = false;
    try {
      store = await this.getStore();
      if (syncContext !== undefined) {
        store.beginTransaction();
        transactionStarted = true;
      }
      const existing = await this.findHistoryVisitEventById(store, id);
      await this.enqueueHistoryVisitDelete(store, existing, syncContext);
      const count = await store.delete(this.createHistoryVisitIdPredicates(id));
      if (existing !== undefined && existing.urlId !== undefined) {
        await this.recalculateHistoryUrlAggregate(store, existing.urlId);
      }
      if (transactionStarted) {
        store.commit();
        transactionStarted = false;
      }
      return count > 0;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to delete history visit: %{public}s', JSON.stringify(error));
      throw new Error('Failed to delete history visit.');
    }
  }

  async deleteHistoryVisitsByIds(ids: string[], syncContext?: HistorySyncOutboxContext): Promise<number> {
    const uniqueIds = Array.from(new Set<string>(ids.map((id: string) => id.trim()).filter((id: string) => id.length > 0)));
    if (uniqueIds.length === 0) {
      return 0;
    }
    let store: relationalStore.RdbStore | undefined = undefined;
    let transactionStarted = false;
    try {
      store = await this.getStore();
      if (syncContext !== undefined) {
        store.beginTransaction();
        transactionStarted = true;
      }
      let removed = 0;
      const affectedUrlIds = new Set<string>();
      for (const id of uniqueIds) {
        const existing = await this.findHistoryVisitEventById(store, id);
        await this.enqueueHistoryVisitDelete(store, existing, syncContext);
        removed += await store.delete(this.createHistoryVisitIdPredicates(id));
        if (existing !== undefined && existing.urlId !== undefined) {
          affectedUrlIds.add(existing.urlId);
        }
      }
      for (const urlId of Array.from(affectedUrlIds)) {
        await this.recalculateHistoryUrlAggregate(store, urlId);
      }
      if (transactionStarted) {
        store.commit();
        transactionStarted = false;
      }
      return removed;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to delete history visits by ids: %{public}s', JSON.stringify(error));
      throw new Error('Failed to delete history visits.');
    }
  }

  async deleteHistoryVisitsInRange(
    startAt: number,
    endAt: number,
    syncContext?: HistorySyncOutboxContext
  ): Promise<number> {
    const normalizedStartAt = Math.max(0, Math.round(startAt));
    const normalizedEndAt = Math.max(normalizedStartAt, Math.round(endAt));
    let store: relationalStore.RdbStore | undefined = undefined;
    let transactionStarted = false;
    try {
      store = await this.getStore();
      if (syncContext !== undefined) {
        store.beginTransaction();
        transactionStarted = true;
      }
      const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
      predicates.between('visited_at', normalizedStartAt, normalizedEndAt);
      const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
      const visits = this.mapHistoryVisitEventRows(resultSet);
      for (const visit of visits) {
        await this.enqueueHistoryVisitDelete(store, visit, syncContext);
      }
      const removed = await this.deleteHydratedHistoryVisitEvents(store, visits);
      if (transactionStarted) {
        store.commit();
        transactionStarted = false;
      }
      return removed;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to delete history visits in range: %{public}s', JSON.stringify(error));
      throw new Error('Failed to delete history visits in range.');
    }
  }

  async deleteHistoryVisitsByHost(host: string, syncContext?: HistorySyncOutboxContext): Promise<number> {
    const normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.length === 0) {
      return 0;
    }
    let store: relationalStore.RdbStore | undefined = undefined;
    let transactionStarted = false;
    try {
      const urls = await this.findHistoryUrlsByHost(normalizedHost);
      store = await this.getStore();
      if (syncContext !== undefined) {
        store.beginTransaction();
        transactionStarted = true;
      }
      let removed = 0;
      for (const url of urls) {
        const visits = await this.findHistoryVisitEventsByUrlId(store, url.id);
        for (const visit of visits) {
          await this.enqueueHistoryVisitDelete(store, visit, syncContext);
          removed += await store.delete(this.createHistoryVisitIdPredicates(visit.id));
        }
        await this.recalculateHistoryUrlAggregate(store, url.id);
      }
      if (transactionStarted) {
        store.commit();
        transactionStarted = false;
      }
      return removed;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to delete history visits by host: %{public}s', JSON.stringify(error));
      throw new Error('Failed to delete history visits by host.');
    }
  }

  async clearHistoryVisits(syncContext?: HistorySyncOutboxContext): Promise<number> {
    let store: relationalStore.RdbStore | undefined = undefined;
    let transactionStarted = false;
    try {
      const visits = await this.listHistoryVisits();
      store = await this.getStore();
      if (syncContext !== undefined) {
        store.beginTransaction();
        transactionStarted = true;
        await this.enqueueHistoryClearBefore(store, syncContext, Date.now());
      }
      let removed = 0;
      for (const visit of visits) {
        removed += await store.delete(this.createHistoryVisitIdPredicates(visit.id));
      }
      const urls = await this.listHistoryUrls();
      for (const url of urls) {
        await store.delete(this.createHistoryUrlIdPredicates(url.id));
      }
      if (transactionStarted) {
        store.commit();
        transactionStarted = false;
      }
      return removed;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to clear history visits: %{public}s', JSON.stringify(error));
      throw new Error('Failed to clear history visits.');
    }
  }

  async getHistorySyncLocalState(accountUid: string, clientId: string): Promise<HistorySyncLocalState> {
    const normalizedUid = accountUid.trim();
    const normalizedClientId = clientId.trim();
    const fallback: HistorySyncLocalState = {
      accountUid: normalizedUid,
      clientId: normalizedClientId,
      initialized: false,
      cursor: 0,
      bootstrapHead: 0,
      bootstrapAfterUpdatedSeq: 0,
      bootstrapAfterVisitId: '',
      updatedAt: 0
    };
    if (normalizedUid.length <= 0 || normalizedClientId.length <= 0) {
      return fallback;
    }
    const store = await this.getStore();
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_STATE_TABLE);
    predicates.equalTo('account_uid', normalizedUid);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, [
      'account_uid',
      'client_id',
      'initialized',
      'cursor',
      'bootstrap_head',
      'bootstrap_after_updated_seq',
      'bootstrap_after_visit_id',
      'updated_at'
    ]);
    try {
      if (!resultSet.goToNextRow()) {
        return fallback;
      }
      const storedClientId = resultSet.getString(resultSet.getColumnIndex('client_id'));
      if (storedClientId !== normalizedClientId) {
        return fallback;
      }
      return {
        accountUid: resultSet.getString(resultSet.getColumnIndex('account_uid')),
        clientId: storedClientId,
        initialized: resultSet.getLong(resultSet.getColumnIndex('initialized')) === 1,
        cursor: resultSet.getLong(resultSet.getColumnIndex('cursor')),
        bootstrapHead: resultSet.getLong(resultSet.getColumnIndex('bootstrap_head')),
        bootstrapAfterUpdatedSeq: resultSet.getLong(resultSet.getColumnIndex('bootstrap_after_updated_seq')),
        bootstrapAfterVisitId: resultSet.getString(resultSet.getColumnIndex('bootstrap_after_visit_id')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      };
    } finally {
      resultSet.close();
    }
  }

  async listHistorySyncOutbox(accountUid: string, limit: number): Promise<HistorySyncMutation[]> {
    const normalizedUid = accountUid.trim();
    if (normalizedUid.length <= 0) {
      return [];
    }
    const store = await this.getStore();
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_OUTBOX_TABLE);
    predicates.equalTo('account_uid', normalizedUid);
    predicates.orderByAsc('created_at');
    predicates.orderByAsc('mutation_id');
    predicates.limitAs(Math.max(1, Math.floor(limit)));
    const resultSet = await store.query(predicates, ['payload_json']);
    const mutations: HistorySyncMutation[] = [];
    try {
      const payloadIndex = resultSet.getColumnIndex('payload_json');
      while (resultSet.goToNextRow()) {
        const mutation = this.parseHistorySyncMutation(resultSet.getString(payloadIndex));
        if (mutation !== undefined) {
          mutations.push(mutation);
        }
      }
      return mutations;
    } finally {
      resultSet.close();
    }
  }

  async readHuaweiSpaceHistorySyncState(accountUid: string): Promise<HuaweiSpaceHistorySyncState> {
    const normalizedUid = accountUid.trim();
    if (normalizedUid.length <= 0) {
      return this.emptyHuaweiSpaceHistorySyncState();
    }
    const store = await this.getStore();
    await this.ensureHistorySyncCanonicalVisitsBackfilled(store, normalizedUid);
    return {
      visits: await this.readHistorySyncCanonicalVisits(store, normalizedUid),
      tombstones: await this.readHistorySyncTombstones(store, normalizedUid),
      deleteRanges: await this.readHistorySyncDeleteRanges(store, normalizedUid),
      clearBefore: await this.readHistorySyncClearBefore(store, normalizedUid),
      retentionFrontier: await this.readHistorySyncRetentionFrontier(store, normalizedUid)
    };
  }

  async applyHuaweiSpaceHistorySyncState(
    accountUid: string,
    state: HuaweiSpaceHistorySyncState
  ): Promise<number> {
    const normalizedUid = accountUid.trim();
    if (normalizedUid.length <= 0) {
      return 0;
    }
    const store = await this.getStore();
    const canonicalPayloads = new Map<string, string>();
    const canonicalVisits = await this.readHistorySyncCanonicalVisits(store, normalizedUid);
    canonicalVisits.forEach((visit: HistorySyncVisit): void => {
      canonicalPayloads.set(visit.visitId, JSON.stringify(visit));
    });
    let transactionStarted = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      let applied = 0;
      for (const tombstone of state.tombstones) {
        await this.persistHistorySyncTombstone(store, normalizedUid, tombstone.visitId, tombstone.deletedAt);
        applied += await this.deleteHistoryVisitBySyncIdInStore(store, normalizedUid, tombstone.visitId);
      }
      for (const range of state.deleteRanges) {
        await this.persistHistorySyncDeleteRange(store, normalizedUid, range);
        applied += await this.deleteHistorySyncRangeInStore(store, normalizedUid, range);
      }
      await this.persistHistorySyncClearBefore(store, normalizedUid, state.clearBefore);
      applied += await this.deleteHistorySyncBeforeInStore(store, normalizedUid, state.clearBefore);
      await this.persistHistorySyncRetentionFrontier(store, normalizedUid, state.retentionFrontier);
      applied += await this.deleteHistoryVisitsBehindRetentionFrontierInStore(
        store,
        normalizedUid,
        state.retentionFrontier
      );
      for (const visit of state.visits) {
        const replaceCanonical = canonicalPayloads.get(visit.visitId) !== JSON.stringify(visit);
        applied += await this.applyHistorySyncVisitUpsert(store, normalizedUid, visit, replaceCanonical);
      }
      store.commit();
      transactionStarted = false;
      return applied;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to apply Huawei Space history state: %{public}s', this.describeError(error));
      throw new Error('Failed to apply Huawei Space synchronized history.');
    }
  }

  async clearHistorySyncOutbox(accountUid: string): Promise<number> {
    const normalizedUid = accountUid.trim();
    if (normalizedUid.length <= 0) {
      return 0;
    }
    const store = await this.getStore();
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_OUTBOX_TABLE);
    predicates.equalTo('account_uid', normalizedUid);
    return store.delete(predicates);
  }

  async prepareAiraHistorySyncProviderEnrollment(
    accountUid: string,
    clientId: string,
    visitsUpdatedAfter: number
  ): Promise<number> {
    const normalizedUid = accountUid.trim();
    const normalizedClientId = clientId.trim();
    if (normalizedUid.length <= 0 || normalizedClientId.length <= 0) {
      return 0;
    }
    const store = await this.getStore();
    await this.ensureHistorySyncCanonicalVisitsBackfilled(store, normalizedUid);
    const visits = await this.readHistorySyncCanonicalVisitsUpdatedAfter(
      store,
      normalizedUid,
      visitsUpdatedAfter
    );
    const tombstones = await this.readHistorySyncTombstones(store, normalizedUid);
    const deleteRanges = await this.readHistorySyncDeleteRanges(store, normalizedUid);
    const clearBefore = await this.readHistorySyncClearBefore(store, normalizedUid);
    let transactionStarted = false;
    let count = 0;
    try {
      store.beginTransaction();
      transactionStarted = true;
      for (const visit of visits) {
        await this.insertHistorySyncMutation(store, normalizedUid, {
          mutationId: this.createHistorySyncMutationId(normalizedClientId, 'provider-upsert'),
          kind: 'upsert_visit',
          visit
        });
        count += 1;
      }
      for (const tombstone of tombstones) {
        await this.insertHistorySyncMutation(store, normalizedUid, {
          mutationId: this.createHistorySyncMutationId(normalizedClientId, 'provider-delete'),
          kind: 'delete_visit',
          visitId: tombstone.visitId
        });
        count += 1;
      }
      for (const range of deleteRanges) {
        await this.insertHistorySyncMutation(store, normalizedUid, {
          mutationId: this.createHistorySyncMutationId(normalizedClientId, 'provider-range'),
          kind: 'delete_range',
          url: range.url,
          startedAt: range.startedAt,
          endedAt: range.endedAt
        });
        count += 1;
      }
      if (clearBefore > 0) {
        await this.insertHistorySyncMutation(store, normalizedUid, {
          mutationId: this.createHistorySyncMutationId(normalizedClientId, 'provider-clear'),
          kind: 'clear_before',
          clearBefore
        });
        count += 1;
      }
      store.commit();
      transactionStarted = false;
      return count;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      throw new Error(`Failed to prepare Aira history provider enrollment: ${this.describeError(error)}`);
    }
  }

  async prepareHistorySyncEnrollment(
    accountUid: string,
    clientId: string,
    deviceName: string,
    limit: number
  ): Promise<number> {
    const normalizedUid = accountUid.trim();
    const normalizedClientId = clientId.trim();
    if (normalizedUid.length <= 0 || normalizedClientId.length <= 0) {
      return 0;
    }
    const store = await this.getStore();
    const resultSet = await store.querySql(
      `SELECT ${HISTORY_VISIT_COLUMNS.join(',')} FROM ${HISTORY_VISITS_TABLE} ` +
        `WHERE data_scope = 'profile_persistent' AND sync_origin <> 'remote' ` +
        `AND (sync_id = '' OR sync_account_uid <> ?) ORDER BY visited_at DESC LIMIT ?`,
      [normalizedUid, Math.max(1, Math.floor(limit))]
    );
    const candidates = await this.hydrateHistoryVisits(this.mapHistoryVisitEventRows(resultSet));
    if (candidates.length <= 0) {
      return 0;
    }
    const context: HistorySyncOutboxContext = {
      accountUid: normalizedUid,
      clientId: normalizedClientId,
      deviceName: deviceName.trim(),
      origin: 'migration'
    };
    let transactionStarted = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      for (const candidate of candidates) {
        const syncId = (candidate.syncId ?? '').trim() ||
          this.buildHistorySyncVisitId(normalizedClientId, candidate.id);
        const enrolled: HistoryVisit = {
          id: candidate.id,
          urlId: candidate.urlId,
          title: candidate.title,
          url: candidate.url,
          normalizedUrl: candidate.normalizedUrl,
          origin: candidate.origin,
          host: candidate.host,
          visitedAt: candidate.visitedAt,
          dayBucketLabel: candidate.dayBucketLabel,
          source: candidate.source,
          deviceId: candidate.deviceId,
          sessionId: candidate.sessionId,
          fromVisitId: candidate.fromVisitId,
          transition: candidate.transition,
          visitDurationMs: candidate.visitDurationMs,
          profileId: candidate.profileId,
          dataScope: candidate.dataScope,
          visitCount: candidate.visitCount,
          typedCount: candidate.typedCount,
          lastVisitAt: candidate.lastVisitAt,
          syncId: syncId,
          syncAccountUid: normalizedUid,
          syncOrigin: 'local'
        };
        await store.update(this.toHistoryVisitValues(enrolled), this.createHistoryVisitIdPredicates(candidate.id));
        await this.enqueueHistoryVisitUpsert(store, enrolled, context);
      }
      store.commit();
      transactionStarted = false;
      return candidates.length;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to enroll history sync visits: %{public}s', JSON.stringify(error));
      throw new Error('Failed to prepare local history for sync.');
    }
  }

  async applyHistorySyncExchange(
    accountUid: string,
    clientId: string,
    response: HistorySyncExchangeResponse,
    removeAcknowledgedMutations: boolean = true
  ): Promise<number> {
    const store = await this.getStore();
    let transactionStarted = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      const applied = await this.applyHistorySyncChangesInStore(store, accountUid, response.changes);
      if (removeAcknowledgedMutations) {
        for (const acknowledgement of response.acknowledgements) {
          const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_OUTBOX_TABLE);
          predicates.equalTo('account_uid', accountUid);
          predicates.equalTo('mutation_id', acknowledgement.mutationId);
          await store.delete(predicates);
        }
      }
      await this.upsertHistorySyncState(store, {
        accountUid: accountUid,
        clientId: clientId,
        initialized: true,
        cursor: response.nextCursor,
        bootstrapHead: 0,
        bootstrapAfterUpdatedSeq: 0,
        bootstrapAfterVisitId: '',
        updatedAt: Date.now()
      });
      store.commit();
      transactionStarted = false;
      return applied;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to apply history exchange: %{public}s', this.describeError(error));
      throw new Error('Failed to apply synchronized history changes.');
    }
  }

  async applyHistorySyncBootstrap(
    accountUid: string,
    clientId: string,
    response: HistorySyncBootstrapResponse,
    resetRemoteProjection: boolean
  ): Promise<number> {
    const store = await this.getStore();
    let transactionStarted = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      if (resetRemoteProjection) {
        await this.deleteRemoteHistoryProjectionInStore(store, accountUid);
      }
      await this.persistHistorySyncClearBefore(store, accountUid, response.clearBefore);
      for (const range of response.deleteRanges) {
        await this.persistHistorySyncDeleteRange(store, accountUid, range);
      }
      const frontierChanges: HistorySyncChange[] = [];
      if (response.clearBefore > 0) {
        frontierChanges.push({
          seq: 0,
          kind: 'clear_before',
          visitId: '',
          clearBefore: response.clearBefore
        });
      }
      response.deleteRanges.forEach((range: HistorySyncDeleteRange) => {
        frontierChanges.push({
          seq: range.seq,
          kind: 'delete_range',
          visitId: '',
          rangeId: range.rangeId,
          url: range.url,
          startedAt: range.startedAt,
          endedAt: range.endedAt
        });
      });
      let applied = await this.applyHistorySyncChangesInStore(store, accountUid, frontierChanges);
      for (const visitId of response.deletedVisitIds) {
        await this.persistHistorySyncTombstone(store, accountUid, visitId, Date.now());
        applied += await this.deleteHistoryVisitBySyncIdInStore(store, accountUid, visitId);
      }
      for (const visit of response.visits) {
        applied += await this.applyHistorySyncVisitUpsert(store, accountUid, visit);
      }
      await this.upsertHistorySyncState(store, {
        accountUid: accountUid,
        clientId: clientId,
        initialized: !response.hasMore,
        cursor: response.hasMore ? 0 : response.bootstrapHead,
        bootstrapHead: response.hasMore ? response.bootstrapHead : 0,
        bootstrapAfterUpdatedSeq: response.hasMore ? (response.nextKey?.updatedSeq ?? 0) : 0,
        bootstrapAfterVisitId: response.hasMore ? (response.nextKey?.visitId ?? '') : '',
        updatedAt: Date.now()
      });
      store.commit();
      transactionStarted = false;
      return applied;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to apply history bootstrap: %{public}s', this.describeError(error));
      throw new Error('Failed to initialize synchronized history.');
    }
  }

  async detachHistorySyncRemoteProjection(accountUid: string): Promise<number> {
    const store = await this.getStore();
    let transactionStarted = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      const removed = await this.deleteRemoteHistoryProjectionInStore(store, accountUid.trim());
      store.commit();
      transactionStarted = false;
      return removed;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to detach remote history projection: %{public}s', JSON.stringify(error));
      throw new Error('Failed to detach synchronized history.');
    }
  }

  async pruneHistorySyncProjection(accountUid: string, now: number = Date.now()): Promise<number> {
    const normalizedUid = accountUid.trim();
    if (normalizedUid.length <= 0) {
      return 0;
    }
    const normalizedNow = Math.max(0, Math.round(now));
    const cutoff = normalizedNow - HISTORY_SYNC_RETENTION_MS;
    const store = await this.getStore();
    let transactionStarted = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      if (!(await this.hasHistorySyncProjectionVictims(store, normalizedUid, cutoff))) {
        store.commit();
        transactionStarted = false;
        return 0;
      }
      const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
      predicates.equalTo('sync_account_uid', normalizedUid);
      predicates.equalTo('data_scope', 'profile_persistent');
      predicates.orderByDesc('visited_at');
      predicates.orderByDesc('sync_id');
      const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
      const visits = this.mapHistoryVisitEventRows(resultSet);
      const victims = visits.filter((visit: HistoryVisit, index: number): boolean => {
        return visit.visitedAt < cutoff || index >= HISTORY_SYNC_MAX_VISITS;
      });
      if (victims.length <= 0) {
        store.commit();
        transactionStarted = false;
        return 0;
      }

      const victimSyncIds = new Set<string>();
      victims.forEach((visit: HistoryVisit): void => {
        const syncId = (visit.syncId ?? '').trim();
        if (syncId.length > 0) {
          victimSyncIds.add(syncId);
        }
      });
      if (victimSyncIds.size > 0) {
        const outboxPredicates = new relationalStore.RdbPredicates(HISTORY_SYNC_OUTBOX_TABLE);
        outboxPredicates.equalTo('account_uid', normalizedUid);
        outboxPredicates.equalTo('kind', 'upsert_visit');
        const outboxResult = await store.query(outboxPredicates, ['mutation_id', 'payload_json']);
        const mutationIds: string[] = [];
        try {
          const mutationIdIndex = outboxResult.getColumnIndex('mutation_id');
          const payloadIndex = outboxResult.getColumnIndex('payload_json');
          while (outboxResult.goToNextRow()) {
            const mutation = this.parseHistorySyncMutation(outboxResult.getString(payloadIndex));
            const visitId = (mutation?.visit?.visitId ?? '').trim();
            if (victimSyncIds.has(visitId)) {
              mutationIds.push(outboxResult.getString(mutationIdIndex));
            }
          }
        } finally {
          outboxResult.close();
        }
        for (const mutationId of mutationIds) {
          const mutationPredicates = new relationalStore.RdbPredicates(HISTORY_SYNC_OUTBOX_TABLE);
          mutationPredicates.equalTo('account_uid', normalizedUid);
          mutationPredicates.equalTo('mutation_id', mutationId);
          await store.delete(mutationPredicates);
        }
      }
      const removed = await this.deleteHydratedHistoryVisitEvents(store, victims);
      await this.advanceHistorySyncRetentionForVictims(
        store,
        normalizedUid,
        visits,
        victims,
        cutoff,
        normalizedNow
      );
      store.commit();
      transactionStarted = false;
      return removed;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to prune synchronized history projection: %{public}s', JSON.stringify(error));
      throw new Error('Failed to apply synchronized history retention.');
    }
  }

  async detachHistorySyncRemoteProjectionsExcept(accountUid: string): Promise<number> {
    const normalizedUid = accountUid.trim();
    const store = await this.getStore();
    let transactionStarted = false;
    try {
      store.beginTransaction();
      transactionStarted = true;
      const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
      predicates.equalTo('sync_origin', 'remote');
      const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
      const detachedVisits = this.mapHistoryVisitEventRows(resultSet)
        .filter((visit: HistoryVisit): boolean => (visit.syncAccountUid ?? '').trim() !== normalizedUid);
      const removed = await this.deleteHydratedHistoryVisitEvents(store, detachedVisits);
      store.commit();
      transactionStarted = false;
      return removed;
    } catch (error) {
      this.rollbackHistoryTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to detach stale remote history projections: %{public}s', JSON.stringify(error));
      throw new Error('Failed to detach stale synchronized history.');
    }
  }

  private async listHistoryUrls(): Promise<HistoryUrlRecord[]> {
    const store = await this.getStore();
    const predicates = new relationalStore.RdbPredicates(HISTORY_URLS_TABLE);
    predicates.orderByDesc('last_visit_at');
    const resultSet = await store.query(predicates, HISTORY_URL_COLUMNS);
    return this.mapHistoryUrlRows(resultSet);
  }

  private async findHistoryUrlsByHost(host: string): Promise<HistoryUrlRecord[]> {
    const store = await this.getStore();
    const predicates = new relationalStore.RdbPredicates(HISTORY_URLS_TABLE);
    predicates.equalTo('host', host);
    predicates.orderByDesc('last_visit_at');
    const resultSet = await store.query(predicates, HISTORY_URL_COLUMNS);
    return this.mapHistoryUrlRows(resultSet);
  }

  async listShortcutScenarios(): Promise<ShortcutScenarioRecord[]> {
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(SHORTCUT_SCENARIOS_TABLE);
      predicates.orderByAsc('position');
      const resultSet = await store.query(predicates, SHORTCUT_SCENARIO_COLUMNS);
      return this.mapShortcutScenarioRows(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load shortcut scenarios: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async listShortcuts(): Promise<ShortcutRecord[]> {
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(SHORTCUTS_TABLE);
      predicates.orderByAsc('scenario_id').orderByAsc('position');
      const resultSet = await store.query(predicates, SHORTCUT_COLUMNS);
      return this.mapShortcutRows(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load shortcuts: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async seedShortcutsIfEmpty(scenarios: ShortcutScenarioRecord[], shortcuts: ShortcutRecord[]): Promise<boolean> {
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(SHORTCUTS_TABLE);
      predicates.limitAs(1);
      const resultSet = await store.query(predicates, ['id']);
      try {
        if (resultSet.rowCount > 0) {
          return false;
        }
      } finally {
        try {
          resultSet.close();
        } catch (closeError) {
          hilog.warn(DOMAIN, TAG, 'Failed to close shortcut seed query result set: %{public}s', JSON.stringify(closeError));
        }
      }

      let inserted = false;
      for (const scenario of scenarios) {
        if (!(await this.hasShortcutScenario(store, scenario.id))) {
          await store.insert(SHORTCUT_SCENARIOS_TABLE, this.toShortcutScenarioValues(scenario));
          inserted = true;
        }
      }
      for (const shortcut of shortcuts) {
        if (!(await this.hasShortcut(store, shortcut.id))) {
          await store.insert(SHORTCUTS_TABLE, this.toShortcutValues(shortcut));
          inserted = true;
        }
      }
      return inserted;
    } catch (error) {
      const message = this.describeError(error);
      hilog.error(DOMAIN, TAG, 'Failed to seed shortcuts: %{public}s', message);
      throw new Error(`Failed to seed shortcut database: ${message}`);
    }
  }

  async upsertShortcut(shortcut: ShortcutRecord): Promise<void> {
    try {
      const store = await this.getStore();
      await this.upsertShortcutRecord(store, shortcut);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to upsert shortcut: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save shortcut.');
    }
  }

  async upsertShortcutSnapshot(
    scenarios: ShortcutScenarioRecord[],
    shortcuts: ShortcutRecord[]
  ): Promise<void> {
    if (scenarios.length === 0 && shortcuts.length === 0) {
      return;
    }
    let transactionStarted = false;
    let store: relationalStore.RdbStore | undefined = undefined;
    try {
      store = await this.getStore();
      store.beginTransaction();
      transactionStarted = true;
      for (const scenario of scenarios) {
        await this.upsertShortcutScenarioRecord(store, scenario);
      }
      for (const shortcut of shortcuts) {
        await this.upsertShortcutRecord(store, shortcut);
      }
      store.commit();
      transactionStarted = false;
    } catch (error) {
      this.rollbackShortcutTransaction(store, transactionStarted);
      hilog.error(DOMAIN, TAG, 'Failed to upsert shortcut snapshot: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save shortcut snapshot.');
    }
  }

  async purgeDeletedShortcutSyncRecords(): Promise<number> {
    try {
      const store = await this.getStore();
      const shortcutPredicates = new relationalStore.RdbPredicates(SHORTCUTS_TABLE);
      shortcutPredicates.isNotNull('deleted_at');
      const deletedShortcuts = await store.delete(shortcutPredicates);
      const scenarioPredicates = new relationalStore.RdbPredicates(SHORTCUT_SCENARIOS_TABLE);
      scenarioPredicates.isNotNull('deleted_at');
      const deletedScenarios = await store.delete(scenarioPredicates);
      return deletedShortcuts + deletedScenarios;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to purge deleted shortcut sync records: %{public}s', JSON.stringify(error));
      throw new Error('Failed to purge deleted shortcut sync records.');
    }
  }

  async updateShortcutIcon(id: string, expectedUrl: string, icon: string): Promise<boolean> {
    try {
      const store = await this.getStore();
      const values: relationalStore.ValuesBucket = {
        icon: icon.trim().length > 0 ? icon.trim() : null
      };
      const predicates = this.createShortcutIdPredicates(id);
      predicates.equalTo('url', expectedUrl);
      const count = await store.update(values, predicates);
      return count > 0;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update shortcut icon: %{public}s', JSON.stringify(error));
      throw new Error('Failed to update shortcut icon.');
    }
  }

  async deleteShortcut(id: string): Promise<boolean> {
    try {
      const store = await this.getStore();
      const count = await store.delete(this.createShortcutIdPredicates(id));
      return count > 0;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete shortcut: %{public}s', JSON.stringify(error));
      throw new Error('Failed to delete shortcut.');
    }
  }

  async listTabRecords(windowId: string = 'window-main', profileId?: string): Promise<TabRecord[]> {
    try {
      const store = await this.getStore();
      const predicates = this.createTabWindowPredicates(windowId, profileId);
      predicates.orderByAsc('tab_order').orderByAsc('id');
      const resultSet = await store.query(predicates, TAB_SESSION_COLUMNS);
      return this.mapTabRows(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load tab session records: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async replaceTabRecords(windowId: string, tabs: TabRecord[], profileId?: string): Promise<void> {
    try {
      const store = await this.getStore();
      const existingTabs = await this.listTabRecords(windowId, profileId);
      const nextTabIds = tabs.map((tab: TabRecord) => tab.id);
      for (const tab of tabs) {
        const values = this.toTabValues(tab);
        const updated = await store.update(values, this.createTabIdPredicates(tab.id, windowId));
        if (updated === 0) {
          await store.insert(TAB_SESSIONS_TABLE, values);
        }
      }
      for (const existingTab of existingTabs) {
        if (nextTabIds.indexOf(existingTab.id) < 0) {
          await store.delete(this.createTabIdPredicates(existingTab.id, windowId));
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to replace tab session records: %{public}s', JSON.stringify(error));
      throw new Error('Failed to save tab sessions.');
    }
  }

  async listRecentlyClosedTabRecords(
    windowId: string = 'window-main',
    profileId?: string,
    limit: number = 25
  ): Promise<RecentlyClosedTabRecord[]> {
    try {
      const store = await this.getStore();
      const predicates = this.createRecentlyClosedWindowPredicates(windowId, profileId);
      predicates.orderByDesc('closed_at').orderByAsc('id');
      predicates.limitAs(Math.max(1, limit));
      const resultSet = await store.query(predicates, RECENTLY_CLOSED_TAB_COLUMNS);
      return this.mapRecentlyClosedTabRows(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load recently closed tab records: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  async replaceRecentlyClosedTabRecords(
    windowId: string,
    records: RecentlyClosedTabRecord[],
    profileId?: string
  ): Promise<void> {
    const startedAt = Date.now();
    let transactionStarted = false;
    let store: relationalStore.RdbStore | undefined = undefined;
    try {
      store = await this.getStore();
      const replacementRecords = this.normalizeRecentlyClosedReplacementRecords(records, windowId, profileId);
      const nextIds = replacementRecords.map((record: RecentlyClosedTabRecord): string => record.id);
      const existingRecords = await this.listRecentlyClosedTabRecords(
        windowId,
        profileId,
        Math.max(25, replacementRecords.length)
      );
      store.beginTransaction();
      transactionStarted = true;
      for (const record of replacementRecords) {
        await this.upsertRecentlyClosedTabRecord(store, record);
      }
      for (const existingRecord of existingRecords) {
        if (nextIds.indexOf(existingRecord.id) < 0) {
          await store.delete(this.createRecentlyClosedIdPredicates(existingRecord.id));
        }
      }
      store.commit();
      transactionStarted = false;
      hilog.info(
        DOMAIN,
        TAG,
        'recently_closed_replace_done window=%{public}s profile=%{public}s records=%{public}d durationMs=%{public}d',
        windowId,
        profileId ?? '',
        replacementRecords.length,
        Math.max(0, Date.now() - startedAt)
      );
    } catch (error) {
      this.rollbackRecentlyClosedTransaction(store, transactionStarted);
      hilog.error(
        DOMAIN,
        TAG,
        'Failed to replace recently closed tab records durationMs=%{public}d error=%{public}s',
        Math.max(0, Date.now() - startedAt),
        JSON.stringify(error)
      );
      throw new Error('Failed to save recently closed tabs.');
    }
  }

  async clearRecentlyClosedTabRecords(windowId: string = 'window-main', profileId?: string): Promise<number> {
    try {
      const store = await this.getStore();
      return store.delete(this.createRecentlyClosedWindowPredicates(windowId, profileId));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear recently closed tab records: %{public}s', JSON.stringify(error));
      throw new Error('Failed to clear recently closed tabs.');
    }
  }

  async clearAllRecentlyClosedTabRecords(): Promise<number> {
    try {
      const store = await this.getStore();
      return store.delete(new relationalStore.RdbPredicates(RECENTLY_CLOSED_TABS_TABLE));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear all recently closed tab records: %{public}s', JSON.stringify(error));
      throw new Error('Failed to clear all recently closed tabs.');
    }
  }

  async deleteRecentlyClosedTabRecordsInRange(
    startAt: number,
    endAt: number,
    windowId: string = 'window-main',
    profileId?: string
  ): Promise<number> {
    try {
      const store = await this.getStore();
      const normalizedStartAt = Math.max(0, Math.min(startAt, endAt));
      const normalizedEndAt = Math.max(normalizedStartAt, Math.max(startAt, endAt));
      const predicates = this.createRecentlyClosedWindowPredicates(windowId, profileId);
      predicates.between('closed_at', normalizedStartAt, normalizedEndAt);
      return store.delete(predicates);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete recently closed tab records in range: %{public}s', JSON.stringify(error));
      throw new Error('Failed to delete recently closed tabs in range.');
    }
  }

  async findSiteIconMetadata(domain: string): Promise<SiteIconMetadataRecord | undefined> {
    const normalizedDomain = this.normalizeSiteIconDomain(domain);
    if (normalizedDomain.length === 0) {
      return undefined;
    }

    try {
      const store = await this.getStore();
      const resultSet = await store.query(this.createSiteIconDomainPredicates(normalizedDomain), SITE_ICON_COLUMNS);
      const records = this.mapSiteIconMetadataRows(resultSet);
      return records.length > 0 ? records[0] : undefined;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to find site icon metadata: %{public}s', this.describeError(error));
      return undefined;
    }
  }

  async listSiteIconMetadataByDomains(domains: string[]): Promise<SiteIconMetadataRecord[]> {
    const normalizedDomains = this.normalizeSiteIconDomains(domains);
    if (normalizedDomains.length === 0) {
      return [];
    }

    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(SITE_ICONS_TABLE);
      predicates.in('domain', normalizedDomains);
      const resultSet = await store.query(predicates, SITE_ICON_COLUMNS);
      return this.mapSiteIconMetadataRows(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to list site icon metadata by domains: %{public}s', this.describeError(error));
      return [];
    }
  }

  async listSiteIconMetadataForPrune(): Promise<SiteIconMetadataRecord[]> {
    try {
      const store = await this.getStore();
      const predicates = new relationalStore.RdbPredicates(SITE_ICONS_TABLE);
      predicates.orderByDesc('last_accessed_at').orderByDesc('updated_at');
      const resultSet = await store.query(predicates, SITE_ICON_COLUMNS);
      return this.mapSiteIconMetadataRows(resultSet);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to list site icon metadata for prune: %{public}s', this.describeError(error));
      return [];
    }
  }

  async upsertSiteIconMetadata(record: SiteIconMetadataRecord): Promise<void> {
    const normalizedDomain = this.normalizeSiteIconDomain(record.domain);
    if (normalizedDomain.length === 0) {
      return;
    }

    try {
      const store = await this.getStore();
      await store.batchInsertWithConflictResolution(
        SITE_ICONS_TABLE,
        [this.toSiteIconMetadataValues({
          domain: normalizedDomain,
          iconUrl: record.iconUrl,
          source: record.source,
          extension: record.extension,
          fileUri: record.fileUri,
          qualityScore: record.qualityScore,
          width: record.width,
          height: record.height,
          lastAccessedAt: record.lastAccessedAt,
          updatedAt: record.updatedAt
        })],
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to upsert site icon metadata: %{public}s', this.describeError(error));
      throw new Error('Failed to save site icon metadata.');
    }
  }

  async touchSiteIconMetadata(domain: string, lastAccessedAt: number): Promise<void> {
    const normalizedDomain = this.normalizeSiteIconDomain(domain);
    if (normalizedDomain.length === 0 || lastAccessedAt <= 0) {
      return;
    }

    try {
      const store = await this.getStore();
      const values: relationalStore.ValuesBucket = {
        last_accessed_at: lastAccessedAt
      };
      await store.update(values, this.createSiteIconDomainPredicates(normalizedDomain));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to touch site icon metadata: %{public}s', this.describeError(error));
    }
  }

  async deleteSiteIconMetadata(domain: string): Promise<boolean> {
    const normalizedDomain = this.normalizeSiteIconDomain(domain);
    if (normalizedDomain.length === 0) {
      return false;
    }

    try {
      const store = await this.getStore();
      const count = await store.delete(this.createSiteIconDomainPredicates(normalizedDomain));
      return count > 0;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete site icon metadata: %{public}s', this.describeError(error));
      return false;
    }
  }

  private async getStore(): Promise<relationalStore.RdbStore> {
    if (this.store !== undefined) {
      return this.store;
    }

    if (this.storePromise === undefined) {
      this.storePromise = this.openStore()
        .then(async (store: relationalStore.RdbStore) => {
          await this.ensureSchema(store);
          this.store = store;
          return store;
        })
        .catch((error: Error) => {
          this.storePromise = undefined;
          throw new Error(`Bookmark store initialization failed: ${this.describeError(error)}`);
        });
    }

    try {
      return await this.storePromise;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to get bookmark store: %{public}s', JSON.stringify(error));
      throw new Error('Failed to get bookmark database store.');
    }
  }

  private async openStore(): Promise<relationalStore.RdbStore> {
    try {
      const config: relationalStore.StoreConfig = {
        name: DATABASE_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      return await relationalStore.getRdbStore(this.getContext(), config);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to open bookmark store: %{public}s', JSON.stringify(error));
      throw new Error('Failed to open bookmark database.');
    }
  }

  private async ensureSchema(store: relationalStore.RdbStore): Promise<void> {
    try {
      await this.ensureSchemaStateTable(store);
      const schemaVersion = await this.readSchemaVersion(store);
      if (schemaVersion >= CURRENT_BROWSER_DATABASE_SCHEMA_VERSION) {
        return;
      }
      if (schemaVersion < INITIAL_BROWSER_DATABASE_SCHEMA_VERSION) {
        await this.applyBrowserSchema(store);
      }
      if (schemaVersion < 2) {
        await store.executeSql(`DROP TABLE IF EXISTS ${REMOVED_BOOKMARK_SYNC_OUTBOX_TABLE}`);
      }
      if (schemaVersion >= INITIAL_BROWSER_DATABASE_SCHEMA_VERSION && schemaVersion < 3) {
        await this.ensureBookmarkSyncLinkSchema(store);
      }
      if (schemaVersion < 5) {
        await this.ensureHistorySyncSchema(store);
      }
      await this.writeSchemaVersion(store, CURRENT_BROWSER_DATABASE_SCHEMA_VERSION);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to ensure browser schema: %{public}s', JSON.stringify(error));
      throw new Error('Failed to prepare browser database schema.');
    }
  }

  private async applyBrowserSchema(store: relationalStore.RdbStore): Promise<void> {
    for (const sql of BOOKMARK_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    for (const sql of BOOKMARK_DOMAIN_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    await this.ensureBookmarkSyncLinkSchema(store);
    await this.ensureOptionalBookmarkColumns(store);
    await this.seedBookmarkRootsIfEmpty(store);
    await this.backfillBookmarkDomainTablesIfNeeded(store);
    for (const sql of HISTORY_URL_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    for (const sql of HISTORY_VISIT_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    await this.ensureHistorySyncSchema(store);
    for (const sql of SEARCH_QUERY_HISTORY_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    for (const sql of OFFLINE_PAGE_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    for (const sql of SHORTCUT_SCENARIO_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    for (const sql of SHORTCUT_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    await this.ensureOptionalShortcutColumns(store);
    for (const sql of TAB_SESSION_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    await this.ensureOptionalTabSessionColumns(store);
    for (const sql of RECENTLY_CLOSED_TAB_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    await this.ensureOptionalRecentlyClosedTabColumns(store);
    for (const sql of SITE_ICON_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
  }

  private async ensureSchemaStateTable(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(BROWSER_SCHEMA_STATE_SQL);
  }

  private async readSchemaVersion(store: relationalStore.RdbStore): Promise<number> {
    return this.readSchemaStateVersion(store, BROWSER_SCHEMA_STATE_CURRENT_KEY);
  }

  private async readSchemaStateVersion(
    store: relationalStore.RdbStore,
    stateKey: string
  ): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(BROWSER_SCHEMA_STATE_TABLE);
    predicates.equalTo('state_key', stateKey);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, ['version']);
    try {
      if (!resultSet.goToNextRow()) {
        return 0;
      }
      const versionIndex = resultSet.getColumnIndex('version');
      return resultSet.getLong(versionIndex);
    } finally {
      try {
        resultSet.close();
      } catch (_error) {
      }
    }
  }

  private async writeSchemaVersion(store: relationalStore.RdbStore, version: number): Promise<void> {
    await this.writeSchemaStateVersion(store, BROWSER_SCHEMA_STATE_CURRENT_KEY, version);
  }

  private async writeSchemaStateVersion(
    store: relationalStore.RdbStore,
    stateKey: string,
    version: number
  ): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      state_key: stateKey,
      version: version,
      updated_at: Date.now()
    };
    await store.batchInsertWithConflictResolution(
      BROWSER_SCHEMA_STATE_TABLE,
      [values],
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
    );
  }

  private async ensureOptionalShortcutColumns(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(`ALTER TABLE ${SHORTCUTS_TABLE} ADD COLUMN children TEXT`);
    } catch (_error) {
      // Existing installs already have this column after the first migration run.
    }
  }

  private async ensureOptionalRecentlyClosedTabColumns(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(`ALTER TABLE ${RECENTLY_CLOSED_TABS_TABLE} ADD COLUMN site_icon_uri TEXT`);
    } catch (_error) {
      // Existing installs already have this column after the first migration run.
    }
  }

  private async ensureOptionalBookmarkColumns(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(`ALTER TABLE ${BOOKMARKS_TABLE} ADD COLUMN scope TEXT DEFAULT 'regular'`);
    } catch (_error) {
      // Existing installs already have this column after the first migration run.
    }
    try {
      await store.executeSql(`ALTER TABLE ${BOOKMARK_NODES_TABLE} ADD COLUMN scope TEXT DEFAULT 'regular'`);
    } catch (_error) {
      // Existing installs already have this column after the first migration run.
    }
    try {
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_bookmark_nodes_scope_type ON ${BOOKMARK_NODES_TABLE}(scope, type)`);
    } catch (_error) {
    }
  }

  private async ensureBookmarkSyncLinkSchema(store: relationalStore.RdbStore): Promise<void> {
    for (const sql of BOOKMARK_SYNC_LINK_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
  }

  private async ensureHistorySyncSchema(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(`ALTER TABLE ${HISTORY_VISITS_TABLE} ADD COLUMN sync_id TEXT NOT NULL DEFAULT ''`);
    } catch (_error) {
    }
    try {
      await store.executeSql(
        `ALTER TABLE ${HISTORY_VISITS_TABLE} ADD COLUMN sync_account_uid TEXT NOT NULL DEFAULT ''`
      );
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${HISTORY_VISITS_TABLE} ADD COLUMN sync_origin TEXT NOT NULL DEFAULT ''`);
    } catch (_error) {
    }
    for (const sql of HISTORY_SYNC_SCHEMA_SQL) {
      await store.executeSql(sql);
    }
    try {
      await store.executeSql(
        `ALTER TABLE ${HISTORY_SYNC_STATE_TABLE} ADD COLUMN initialized INTEGER NOT NULL DEFAULT 0`
      );
    } catch (_error) {
    }
    await store.executeSql(
      `CREATE UNIQUE INDEX IF NOT EXISTS idx_history_visits_sync_id ON ${HISTORY_VISITS_TABLE}(sync_id) ` +
        `WHERE sync_id <> ''`
    );
    await store.executeSql(
      `CREATE INDEX IF NOT EXISTS idx_history_visits_sync_account ` +
        `ON ${HISTORY_VISITS_TABLE}(sync_account_uid, sync_origin)`
    );
  }

  private async ensureOptionalTabSessionColumns(store: relationalStore.RdbStore): Promise<void> {
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN is_home INTEGER NOT NULL DEFAULT 0`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN pending_url TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN navigation_history TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN navigation_index INTEGER NOT NULL DEFAULT -1`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN runtime_state TEXT NOT NULL DEFAULT 'background'`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_error TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_loaded_at INTEGER NOT NULL DEFAULT 0`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN web_state_path TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN web_state_updated_at INTEGER NOT NULL DEFAULT 0`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN scroll_offset_y INTEGER NOT NULL DEFAULT 0`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN form_draft TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN page_runtime_signals TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_good_url TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_good_title TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_restorable_url TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_restorable_title TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_restore_type TEXT NOT NULL DEFAULT 'none'`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'profile-main'`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_restore_reason TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_discard_reason TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN last_crash_reason TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN privacy_mode TEXT NOT NULL DEFAULT 'regular'`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN data_scope TEXT NOT NULL DEFAULT 'profile_persistent'`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN launch_source_type TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN launch_source_id TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN launch_source_url TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN launch_key TEXT`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`ALTER TABLE ${TAB_SESSIONS_TABLE} ADD COLUMN tab_order INTEGER NOT NULL DEFAULT 0`);
    } catch (_error) {
    }
    try {
      await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_tab_sessions_window_order ON ${TAB_SESSIONS_TABLE}(window_id, tab_order)`);
    } catch (_error) {
    }
  }

  private async seedBookmarkRootsIfEmpty(store: relationalStore.RdbStore): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(BOOKMARK_ROOTS_TABLE);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, ['role']);
    try {
      if (resultSet.rowCount > 0) {
        return;
      }
    } finally {
      try {
        resultSet.close();
      } catch (_error) {
      }
    }

    for (const root of buildBookmarkRootRecords()) {
      await store.insert(BOOKMARK_ROOTS_TABLE, this.toBookmarkRootValues(root));
    }
  }

  private async backfillBookmarkDomainTablesIfNeeded(store: relationalStore.RdbStore): Promise<void> {
    const domainPredicates = new relationalStore.RdbPredicates(BOOKMARK_NODES_TABLE);
    domainPredicates.limitAs(1);
    const domainRows = await store.query(domainPredicates, ['id']);
    try {
      if (domainRows.rowCount > 0) {
        return;
      }
    } finally {
      try {
        domainRows.close();
      } catch (_error) {
      }
    }

    const legacyPredicates = new relationalStore.RdbPredicates(BOOKMARKS_TABLE);
    legacyPredicates.orderByAsc('parent_id').orderByAsc('position');
    const legacyRows = await store.query(legacyPredicates, BOOKMARK_COLUMNS);
    const legacyNodes = this.mapBookmarkRows(legacyRows);
    if (legacyNodes.length === 0) {
      return;
    }

    for (const node of legacyNodes) {
      await this.upsertBookmarkNodeToDomainTables(store, node);
    }
  }

  private getContext(): common.ApplicationContext {
    try {
      return AppRuntimeContext.getApplicationContext();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Application context unavailable: %{public}s', JSON.stringify(error));
      throw new Error('Application context unavailable for bookmark database.');
    }
  }

  private createBookmarkIdPredicates(id: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(BOOKMARKS_TABLE);
    predicates.equalTo('id', id);
    return predicates;
  }

  private createBookmarkNodeIdPredicates(id: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(BOOKMARK_NODES_TABLE);
    predicates.equalTo('id', id);
    return predicates;
  }

  private createBookmarkOrderChildPredicates(childId: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(BOOKMARK_ORDERS_TABLE);
    predicates.equalTo('child_id', childId);
    return predicates;
  }

  private createBookmarkSyncLinkPredicates(nodeId: string, provider: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(BOOKMARK_SYNC_LINKS_TABLE);
    predicates.equalTo('node_id', nodeId);
    predicates.equalTo('provider', provider);
    return predicates;
  }

  private createImportBatchIdPredicates(batchId: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(IMPORT_BATCHES_TABLE);
    predicates.equalTo('batch_id', batchId);
    return predicates;
  }

  private createHistoryUrlIdPredicates(id: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(HISTORY_URLS_TABLE);
    predicates.equalTo('id', id);
    return predicates;
  }

  private createHistoryUrlHashPredicates(urlHash: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(HISTORY_URLS_TABLE);
    predicates.equalTo('url_hash', urlHash);
    return predicates;
  }

  private createHistoryVisitIdPredicates(id: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    predicates.equalTo('id', id);
    return predicates;
  }

  private createSearchQueryHistoryIdPredicates(id: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(SEARCH_QUERY_HISTORY_TABLE);
    predicates.equalTo('id', id);
    return predicates;
  }

  private createHistoryVisitsByUrlIdPredicates(urlId: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    predicates.equalTo('url_id', urlId);
    return predicates;
  }

  private createOfflinePageIdPredicates(id: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(OFFLINE_PAGES_TABLE);
    predicates.equalTo('id', id);
    return predicates;
  }

  private createShortcutScenarioIdPredicates(id: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(SHORTCUT_SCENARIOS_TABLE);
    predicates.equalTo('id', id);
    return predicates;
  }

  private createShortcutIdPredicates(id: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(SHORTCUTS_TABLE);
    predicates.equalTo('id', id);
    return predicates;
  }

  private async upsertShortcutScenarioRecord(
    store: relationalStore.RdbStore,
    scenario: ShortcutScenarioRecord
  ): Promise<void> {
    const predicates = this.createShortcutScenarioIdPredicates(scenario.id);
    const count = await store.update(this.toShortcutScenarioValues(scenario), predicates);
    if (count === 0) {
      await store.insert(SHORTCUT_SCENARIOS_TABLE, this.toShortcutScenarioValues(scenario));
    }
  }

  private async upsertShortcutRecord(
    store: relationalStore.RdbStore,
    shortcut: ShortcutRecord
  ): Promise<void> {
    const predicates = this.createShortcutIdPredicates(shortcut.id);
    const count = await store.update(this.toShortcutValues(shortcut), predicates);
    if (count === 0) {
      await store.insert(SHORTCUTS_TABLE, this.toShortcutValues(shortcut));
    }
  }

  private rollbackShortcutTransaction(
    store: relationalStore.RdbStore | undefined,
    transactionStarted: boolean
  ): void {
    if (store === undefined || !transactionStarted) {
      return;
    }
    try {
      store.rollBack();
    } catch (rollbackError) {
      hilog.warn(DOMAIN, TAG, 'Failed to rollback shortcut transaction: %{public}s', JSON.stringify(rollbackError));
    }
  }

  private async hasShortcutScenario(store: relationalStore.RdbStore, id: string): Promise<boolean> {
    return this.hasRow(store, this.createShortcutScenarioIdPredicates(id));
  }

  private async hasShortcut(store: relationalStore.RdbStore, id: string): Promise<boolean> {
    return this.hasRow(store, this.createShortcutIdPredicates(id));
  }

  private async hasRow(store: relationalStore.RdbStore, predicates: relationalStore.RdbPredicates): Promise<boolean> {
    const resultSet = await store.query(predicates, ['id']);
    try {
      return resultSet.rowCount > 0;
    } finally {
      try {
        resultSet.close();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Failed to close existence query result set: %{public}s', this.describeError(error));
      }
    }
  }

  private createTabWindowPredicates(windowId: string, profileId?: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(TAB_SESSIONS_TABLE);
    predicates.equalTo('window_id', windowId);
    if (typeof profileId === 'string' && profileId.trim().length > 0) {
      predicates.equalTo('profile_id', profileId.trim());
    }
    return predicates;
  }

  private describeError(error: Error | Object): string {
    const errorLike = error as DatabaseErrorLike;
    const parts: string[] = [];
    if (typeof errorLike.name === 'string' && errorLike.name.length > 0) {
      parts.push(`name=${errorLike.name}`);
    }
    if (typeof errorLike.message === 'string' && errorLike.message.length > 0) {
      parts.push(`message=${errorLike.message}`);
    }
    if (typeof errorLike.code === 'number') {
      parts.push(`code=${errorLike.code}`);
    }
    if (parts.length > 0) {
      return parts.join(', ');
    }
    const json = JSON.stringify(error);
    if (json.length > 0 && json !== '{}') {
      return json;
    }
    return 'unknown error';
  }

  private normalizeSiteIconDomains(domains: string[]): string[] {
    const normalized: string[] = [];
    for (let index = 0; index < domains.length; index += 1) {
      const domain = this.normalizeSiteIconDomain(domains[index]);
      if (domain.length === 0 || normalized.indexOf(domain) >= 0) {
        continue;
      }
      normalized.push(domain);
    }
    return normalized;
  }

  private normalizeSiteIconDomain(domain: string): string {
    let normalized = domain.trim().toLowerCase();
    if (normalized.startsWith('www.')) {
      normalized = normalized.slice(4);
    }
    return normalized;
  }

  private createTabIdPredicates(id: string, windowId?: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(TAB_SESSIONS_TABLE);
    predicates.equalTo('id', id);
    if (typeof windowId === 'string' && windowId.trim().length > 0) {
      predicates.equalTo('window_id', windowId.trim());
    }
    return predicates;
  }

  private createRecentlyClosedWindowPredicates(windowId: string, profileId?: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(RECENTLY_CLOSED_TABS_TABLE);
    predicates.equalTo('window_id', windowId);
    if (typeof profileId === 'string' && profileId.trim().length > 0) {
      predicates.equalTo('profile_id', profileId.trim());
    }
    return predicates;
  }

  private createRecentlyClosedIdPredicates(id: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(RECENTLY_CLOSED_TABS_TABLE);
    predicates.equalTo('id', id);
    return predicates;
  }

  private createSiteIconDomainPredicates(domain: string): relationalStore.RdbPredicates {
    const predicates = new relationalStore.RdbPredicates(SITE_ICONS_TABLE);
    predicates.equalTo('domain', domain);
    return predicates;
  }

  private mapSiteIconMetadataRows(resultSet: relationalStore.ResultSet): SiteIconMetadataRecord[] {
    const records: SiteIconMetadataRecord[] = [];
    try {
      const domainIndex = resultSet.getColumnIndex('domain');
      const iconUrlIndex = resultSet.getColumnIndex('icon_url');
      const sourceIndex = resultSet.getColumnIndex('source');
      const extensionIndex = resultSet.getColumnIndex('extension');
      const fileUriIndex = resultSet.getColumnIndex('file_uri');
      const qualityScoreIndex = resultSet.getColumnIndex('quality_score');
      const widthIndex = resultSet.getColumnIndex('width');
      const heightIndex = resultSet.getColumnIndex('height');
      const lastAccessedAtIndex = resultSet.getColumnIndex('last_accessed_at');
      const updatedAtIndex = resultSet.getColumnIndex('updated_at');

      while (resultSet.goToNextRow()) {
        records.push({
          domain: resultSet.getString(domainIndex),
          iconUrl: resultSet.getString(iconUrlIndex),
          source: resultSet.getString(sourceIndex) as SiteIconCandidateSource,
          extension: resultSet.getString(extensionIndex),
          fileUri: resultSet.getString(fileUriIndex),
          qualityScore: resultSet.getLong(qualityScoreIndex),
          width: resultSet.getLong(widthIndex),
          height: resultSet.getLong(heightIndex),
          lastAccessedAt: resultSet.getLong(lastAccessedAtIndex),
          updatedAt: resultSet.getLong(updatedAtIndex)
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map site icon metadata rows: %{public}s', this.describeError(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close site icon metadata result set: %{public}s', this.describeError(closeError));
      }
    }
    return records;
  }

  private mapBookmarkRows(resultSet: relationalStore.ResultSet): BookmarkNode[] {
    const nodes: BookmarkNode[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const typeIndex = resultSet.getColumnIndex('type');
      const parentIdIndex = resultSet.getColumnIndex('parent_id');
      const titleIndex = resultSet.getColumnIndex('title');
      const urlIndex = resultSet.getColumnIndex('url');
      const positionIndex = resultSet.getColumnIndex('position');
      const createdAtIndex = resultSet.getColumnIndex('created_at');
      const updatedAtIndex = resultSet.getColumnIndex('updated_at');
      const syncStateIndex = resultSet.getColumnIndex('sync_state');
      const syncSourceIndex = resultSet.getColumnIndex('sync_source');
      const lastModifiedAtIndex = resultSet.getColumnIndex('last_modified_at');
      const lastModifiedByIndex = resultSet.getColumnIndex('last_modified_by');
      const deviceIdIndex = resultSet.getColumnIndex('device_id');
      const originIdIndex = resultSet.getColumnIndex('origin_id');
      const deletedAtIndex = resultSet.getColumnIndex('deleted_at');

      while (resultSet.goToNextRow()) {
        nodes.push({
          id: resultSet.getString(idIndex),
          type: resultSet.getString(typeIndex) as 'folder' | 'bookmark',
          parentId: resultSet.isColumnNull(parentIdIndex) ? undefined : resultSet.getString(parentIdIndex),
          title: resultSet.getString(titleIndex),
          url: resultSet.isColumnNull(urlIndex) ? undefined : resultSet.getString(urlIndex),
          position: resultSet.getLong(positionIndex),
          createdAt: resultSet.getLong(createdAtIndex),
          updatedAt: resultSet.getLong(updatedAtIndex),
          sync: {
            state: resultSet.getString(syncStateIndex) as 'local_only' | 'pending_push' | 'synced' | 'conflict',
            source: resultSet.getString(syncSourceIndex) as 'seed' | 'local' | 'chrome_import' | 'chrome_sync' | 'cloud_sync',
            lastModifiedAt: resultSet.getLong(lastModifiedAtIndex),
            lastModifiedBy: resultSet.getString(lastModifiedByIndex),
            deviceId: resultSet.getString(deviceIdIndex),
            originId: resultSet.isColumnNull(originIdIndex) ? undefined : resultSet.getString(originIdIndex),
            deletedAt: resultSet.isColumnNull(deletedAtIndex) ? undefined : resultSet.getLong(deletedAtIndex)
          }
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map bookmark rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close bookmark result set: %{public}s', JSON.stringify(closeError));
      }
    }

    return nodes;
  }

  private async listBookmarkNodesFromDomainTables(store: relationalStore.RdbStore): Promise<BookmarkNode[]> {
    const nodeRows = await this.listBookmarkDomainNodeRowsByPage(store);
    const nodesById = new Map<string, BookmarkNode>();
    nodeRows.forEach((node: BookmarkNode) => {
      nodesById.set(node.id, node);
    });

    const orders = await this.listBookmarkDomainOrderRowsByPage(store);

    const rootsPredicates = new relationalStore.RdbPredicates(BOOKMARK_ROOTS_TABLE);
    rootsPredicates.orderByAsc('position');
    const rootRows = await store.query(rootsPredicates, BOOKMARK_ROOT_COLUMNS);
    const roots = this.mapBookmarkRootRows(rootRows);

    roots.forEach((root: BookmarkRootRecord) => {
      if (!nodesById.has(root.nodeId)) {
        const fallbackTime = Date.now();
        nodesById.set(root.nodeId, {
          id: root.nodeId,
          scope: this.resolveBookmarkRootScope(root.nodeId),
          type: 'folder',
          title: root.title,
          position: root.position,
          createdAt: fallbackTime,
          updatedAt: fallbackTime,
          sync: {
            state: 'local_only',
            source: 'seed',
            lastModifiedAt: fallbackTime,
            lastModifiedBy: DEFAULT_BROWSER_PROFILE_ID,
            deviceId: 'aira-phone-local'
          }
        });
      }
    });

    const parentByChildId = new Map<string, string | undefined>();
    const positionByChildId = new Map<string, number>();
    orders.forEach((order: BookmarkOrderRecord) => {
      parentByChildId.set(order.childId, order.parentId);
      positionByChildId.set(order.childId, order.position);
    });

    const nodes = Array.from(nodesById.values()).map((node: BookmarkNode) => {
      const mappedNode: BookmarkNode = {
        id: node.id,
        type: node.type,
        scope: resolveBookmarkScope(node.scope),
        parentId: parentByChildId.get(node.id),
        title: node.title,
        url: node.url,
        position: positionByChildId.get(node.id) ?? this.resolveBookmarkFallbackPosition(node.id, roots),
        createdAt: node.createdAt,
        updatedAt: node.updatedAt,
        sync: node.sync
      };
      return mappedNode;
    });

    return nodes.sort((left: BookmarkNode, right: BookmarkNode) => {
      if ((left.parentId ?? '') === (right.parentId ?? '')) {
        if (left.position === right.position) {
          return left.id.localeCompare(right.id);
        }
        return left.position - right.position;
      }
      return (left.parentId ?? '').localeCompare(right.parentId ?? '');
    });
  }

  private async listBookmarkDomainNodeRowsByPage(store: relationalStore.RdbStore): Promise<BookmarkNode[]> {
    const nodes: BookmarkNode[] = [];
    let offset = 0;
    while (true) {
      const predicates = new relationalStore.RdbPredicates(BOOKMARK_NODES_TABLE);
      predicates.orderByAsc('created_at').orderByAsc('id');
      predicates.limitAs(BOOKMARK_DOMAIN_READ_BATCH_SIZE);
      if (offset > 0) {
        predicates.offsetAs(offset);
      }
      const resultSet = await store.query(predicates, BOOKMARK_NODE_COLUMNS);
      const batch = this.mapBookmarkNodeRows(resultSet);
      if (batch.length === 0) {
        break;
      }
      batch.forEach((node: BookmarkNode) => {
        nodes.push(node);
      });
      offset += batch.length;
      if (batch.length < BOOKMARK_DOMAIN_READ_BATCH_SIZE) {
        break;
      }
      await this.yieldBookmarkDatabaseWork();
    }
    return nodes;
  }

  private async listBookmarkDomainOrderRowsByPage(store: relationalStore.RdbStore): Promise<BookmarkOrderRecord[]> {
    const orders: BookmarkOrderRecord[] = [];
    let offset = 0;
    while (true) {
      const predicates = new relationalStore.RdbPredicates(BOOKMARK_ORDERS_TABLE);
      predicates.orderByAsc('parent_id').orderByAsc('position').orderByAsc('child_id');
      predicates.limitAs(BOOKMARK_DOMAIN_READ_BATCH_SIZE);
      if (offset > 0) {
        predicates.offsetAs(offset);
      }
      const resultSet = await store.query(predicates, BOOKMARK_ORDER_COLUMNS);
      const batch = this.mapBookmarkOrderRows(resultSet);
      if (batch.length === 0) {
        break;
      }
      batch.forEach((order: BookmarkOrderRecord) => {
        orders.push(order);
      });
      offset += batch.length;
      if (batch.length < BOOKMARK_DOMAIN_READ_BATCH_SIZE) {
        break;
      }
      await this.yieldBookmarkDatabaseWork();
    }
    return orders;
  }

  private async listBookmarkPreviewChildrenFromDomainTables(
    store: relationalStore.RdbStore,
    parentId: string | undefined,
    limit: number,
    scope?: 'regular' | 'private'
  ): Promise<BookmarkNode[]> {
    const normalizedLimit = Math.max(1, Math.floor(limit));
    const previewOrderRows = await this.listBookmarkPreviewOrderRowsByPage(store, parentId, normalizedLimit);
    if (previewOrderRows.length === 0) {
      return [];
    }

    const childIds = previewOrderRows.map((order: BookmarkOrderRecord) => order.childId);
    const nodesById = new Map<string, BookmarkNode>();
    const nodePredicates = new relationalStore.RdbPredicates(BOOKMARK_NODES_TABLE);
    nodePredicates.in('id', childIds);
    nodePredicates.equalTo('scope', resolveBookmarkScope(scope));
    const nodeRows = this.mapBookmarkNodeRows(await store.query(nodePredicates, BOOKMARK_NODE_COLUMNS));
    nodeRows.forEach((node: BookmarkNode) => {
      nodesById.set(node.id, node);
    });

    const ordersPredicates = new relationalStore.RdbPredicates(BOOKMARK_ORDERS_TABLE);
    ordersPredicates.in('child_id', childIds);
    ordersPredicates.orderByAsc('parent_id').orderByAsc('position').orderByAsc('child_id');
    const orderRows = this.mapBookmarkOrderRows(await store.query(ordersPredicates, BOOKMARK_ORDER_COLUMNS));
    const orderByChildId = new Map<string, BookmarkOrderRecord>();
    orderRows.forEach((order: BookmarkOrderRecord) => {
      if (!orderByChildId.has(order.childId)) {
        orderByChildId.set(order.childId, order);
      }
    });

    return Array.from(nodesById.values())
      .map((node: BookmarkNode) => {
        const order = orderByChildId.get(node.id);
        const mappedNode: BookmarkNode = {
          id: node.id,
          type: node.type,
          parentId: order?.parentId,
          title: node.title,
          url: node.url,
          position: order?.position ?? node.position,
          createdAt: node.createdAt,
          updatedAt: node.updatedAt,
          sync: node.sync
        };
        return mappedNode;
      })
      .sort((left: BookmarkNode, right: BookmarkNode) => {
        if ((left.parentId ?? '') === (right.parentId ?? '')) {
          if (left.position === right.position) {
            return left.id.localeCompare(right.id);
          }
          return left.position - right.position;
        }
        return (left.parentId ?? '').localeCompare(right.parentId ?? '');
      });
  }

  private async listBookmarkPreviewOrderRowsByPage(
    store: relationalStore.RdbStore,
    parentId: string | undefined,
    limit: number
  ): Promise<BookmarkOrderRecord[]> {
    const orders: BookmarkOrderRecord[] = [];
    let offset = 0;
    while (orders.length < limit) {
      const remaining = limit - orders.length;
      const pageLimit = Math.min(BOOKMARK_DOMAIN_READ_BATCH_SIZE, remaining);
      const predicates = new relationalStore.RdbPredicates(BOOKMARK_ORDERS_TABLE);
      if (parentId === undefined) {
        predicates.isNull('parent_id');
      } else {
        predicates.equalTo('parent_id', parentId);
      }
      predicates.orderByAsc('position').orderByAsc('child_id');
      predicates.limitAs(pageLimit);
      if (offset > 0) {
        predicates.offsetAs(offset);
      }
      const resultSet = await store.query(predicates, BOOKMARK_ORDER_COLUMNS);
      const batch = this.mapBookmarkOrderRows(resultSet);
      if (batch.length === 0) {
        break;
      }
      batch.forEach((order: BookmarkOrderRecord) => {
        orders.push(order);
      });
      offset += batch.length;
      if (batch.length < pageLimit) {
        break;
      }
      await this.yieldBookmarkDatabaseWork();
    }
    return orders;
  }

  private async findBookmarkNodeById(store: relationalStore.RdbStore, id: string): Promise<BookmarkNode | undefined> {
    const predicates = this.createBookmarkNodeIdPredicates(id);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, BOOKMARK_NODE_COLUMNS);
    const nodes = this.mapBookmarkNodeRows(resultSet);
    return nodes.length > 0 ? nodes[0] : undefined;
  }

  private async upsertBookmarkNodeToDomainTables(store: relationalStore.RdbStore, node: BookmarkNode): Promise<void> {
    const nodeValues = this.toBookmarkNodeValues(node);
    await store.batchInsertWithConflictResolution(
      BOOKMARK_NODES_TABLE,
      [nodeValues],
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
    );

    const orderValues = this.toBookmarkOrderValues(node);
    await store.batchInsertWithConflictResolution(
      BOOKMARK_ORDERS_TABLE,
      [orderValues],
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
    );

    const provider = this.resolveBookmarkSyncProvider(node);
    const syncLink: BookmarkSyncLinkRecord = {
      nodeId: node.id,
      provider: provider,
      remoteEntityId: node.sync.originId,
      originId: node.sync.originId,
      updatedAt: node.sync.lastModifiedAt
    };
    await store.batchInsertWithConflictResolution(
      BOOKMARK_SYNC_LINKS_TABLE,
      [this.toBookmarkSyncLinkValues(syncLink)],
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
    );
  }

  private async batchUpsertBookmarkDomainRows(
    store: relationalStore.RdbStore,
    nodes: BookmarkNode[]
  ): Promise<void> {
    if (nodes.length === 0) {
      return;
    }
    await this.batchUpsertImportedBookmarkNodeRows(store, nodes);
    await this.batchUpsertImportedBookmarkOrderRows(store, nodes);
    await this.batchUpsertImportedBookmarkSyncLinkRows(store, nodes);
  }

  private async batchUpsertImportedBookmarkNodeRows(
    store: relationalStore.RdbStore,
    nodes: BookmarkNode[]
  ): Promise<void> {
    for (let start = 0; start < nodes.length; start += BOOKMARK_IMPORT_BATCH_INSERT_SIZE) {
      const values = nodes
        .slice(start, start + BOOKMARK_IMPORT_BATCH_INSERT_SIZE)
        .map((node: BookmarkNode) => this.toBookmarkNodeValues(node));
      await store.batchInsertWithConflictResolution(
        BOOKMARK_NODES_TABLE,
        values,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
      await this.yieldBetweenBookmarkBatches(start, nodes.length);
    }
  }

  private async batchUpsertImportedBookmarkOrderRows(
    store: relationalStore.RdbStore,
    nodes: BookmarkNode[]
  ): Promise<void> {
    for (let start = 0; start < nodes.length; start += BOOKMARK_IMPORT_BATCH_INSERT_SIZE) {
      const values = nodes
        .slice(start, start + BOOKMARK_IMPORT_BATCH_INSERT_SIZE)
        .map((node: BookmarkNode) => this.toBookmarkOrderValues(node));
      await store.batchInsertWithConflictResolution(
        BOOKMARK_ORDERS_TABLE,
        values,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
      await this.yieldBetweenBookmarkBatches(start, nodes.length);
    }
  }

  private async batchUpsertImportedBookmarkSyncLinkRows(
    store: relationalStore.RdbStore,
    nodes: BookmarkNode[]
  ): Promise<void> {
    for (let start = 0; start < nodes.length; start += BOOKMARK_IMPORT_BATCH_INSERT_SIZE) {
      const values = nodes
        .slice(start, start + BOOKMARK_IMPORT_BATCH_INSERT_SIZE)
        .map((node: BookmarkNode) => {
          const provider = this.resolveBookmarkSyncProvider(node);
          return this.toBookmarkSyncLinkValues({
            nodeId: node.id,
            provider: provider,
            remoteEntityId: node.sync.originId,
            originId: node.sync.originId,
            updatedAt: node.sync.lastModifiedAt
          });
        });
      await store.batchInsertWithConflictResolution(
        BOOKMARK_SYNC_LINKS_TABLE,
        values,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
      await this.yieldBetweenBookmarkBatches(start, nodes.length);
    }
  }

  private async yieldBetweenBookmarkBatches(start: number, total: number): Promise<void> {
    if (start + BOOKMARK_IMPORT_BATCH_INSERT_SIZE >= total) {
      return;
    }
    await this.yieldBookmarkDatabaseWork();
  }

  private async yieldBookmarkDatabaseWork(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 0);
    });
  }

  private rollbackBookmarkTransaction(
    store: relationalStore.RdbStore | undefined,
    transactionStarted: boolean
  ): void {
    if (store === undefined || !transactionStarted) {
      return;
    }
    try {
      store.rollBack();
    } catch (rollbackError) {
      hilog.warn(DOMAIN, TAG, 'Failed to rollback bookmark transaction: %{public}s', JSON.stringify(rollbackError));
    }
  }

  private mapBookmarkRootRows(resultSet: relationalStore.ResultSet): BookmarkRootRecord[] {
    const roots: BookmarkRootRecord[] = [];
    try {
      const roleIndex = resultSet.getColumnIndex('role');
      const nodeIdIndex = resultSet.getColumnIndex('node_id');
      const titleIndex = resultSet.getColumnIndex('title');
      const positionIndex = resultSet.getColumnIndex('position');
      const syncEnabledIndex = resultSet.getColumnIndex('sync_enabled');
      while (resultSet.goToNextRow()) {
        roots.push({
          role: resultSet.getString(roleIndex) as 'toolbar' | 'other',
          nodeId: resultSet.getString(nodeIdIndex),
          title: resultSet.getString(titleIndex),
          position: resultSet.getLong(positionIndex),
          syncEnabled: resultSet.getLong(syncEnabledIndex) > 0
        });
      }
    } finally {
      try {
        resultSet.close();
      } catch (_error) {
      }
    }
    return roots;
  }

  private mapBookmarkNodeRows(resultSet: relationalStore.ResultSet): BookmarkNode[] {
    const nodes: BookmarkNode[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const scopeIndex = resultSet.getColumnIndex('scope');
      const typeIndex = resultSet.getColumnIndex('type');
      const titleIndex = resultSet.getColumnIndex('title');
      const urlIndex = resultSet.getColumnIndex('url');
      const createdAtIndex = resultSet.getColumnIndex('created_at');
      const updatedAtIndex = resultSet.getColumnIndex('updated_at');
      const syncStateIndex = resultSet.getColumnIndex('sync_state');
      const syncSourceIndex = resultSet.getColumnIndex('sync_source');
      const lastModifiedAtIndex = resultSet.getColumnIndex('last_modified_at');
      const lastModifiedByIndex = resultSet.getColumnIndex('last_modified_by');
      const deviceIdIndex = resultSet.getColumnIndex('device_id');
      const originIdIndex = resultSet.getColumnIndex('origin_id');
      const deletedAtIndex = resultSet.getColumnIndex('deleted_at');
      while (resultSet.goToNextRow()) {
        nodes.push({
          id: resultSet.getString(idIndex),
          scope: resolveBookmarkScope(resultSet.isColumnNull(scopeIndex) ? undefined : resultSet.getString(scopeIndex)),
          type: resultSet.getString(typeIndex) as 'folder' | 'bookmark',
          title: resultSet.getString(titleIndex),
          url: resultSet.isColumnNull(urlIndex) ? undefined : resultSet.getString(urlIndex),
          position: 0,
          createdAt: resultSet.getLong(createdAtIndex),
          updatedAt: resultSet.getLong(updatedAtIndex),
          sync: {
            state: resultSet.getString(syncStateIndex) as 'local_only' | 'pending_push' | 'synced' | 'conflict',
            source: resultSet.getString(syncSourceIndex) as 'seed' | 'local' | 'chrome_import' | 'chrome_sync' | 'cloud_sync',
            lastModifiedAt: resultSet.getLong(lastModifiedAtIndex),
            lastModifiedBy: resultSet.getString(lastModifiedByIndex),
            deviceId: resultSet.getString(deviceIdIndex),
            originId: resultSet.isColumnNull(originIdIndex) ? undefined : resultSet.getString(originIdIndex),
            deletedAt: resultSet.isColumnNull(deletedAtIndex) ? undefined : resultSet.getLong(deletedAtIndex)
          }
        });
      }
    } finally {
      try {
        resultSet.close();
      } catch (_error) {
      }
    }
    return nodes;
  }

  private mapBookmarkOrderRows(resultSet: relationalStore.ResultSet): BookmarkOrderRecord[] {
    const orders: BookmarkOrderRecord[] = [];
    try {
      const parentIdIndex = resultSet.getColumnIndex('parent_id');
      const childIdIndex = resultSet.getColumnIndex('child_id');
      const positionIndex = resultSet.getColumnIndex('position');
      const updatedAtIndex = resultSet.getColumnIndex('updated_at');
      while (resultSet.goToNextRow()) {
        orders.push({
          parentId: resultSet.isColumnNull(parentIdIndex) ? undefined : resultSet.getString(parentIdIndex),
          childId: resultSet.getString(childIdIndex),
          position: resultSet.getLong(positionIndex),
          updatedAt: resultSet.getLong(updatedAtIndex)
        });
      }
    } finally {
      try {
        resultSet.close();
      } catch (_error) {
      }
    }
    return orders;
  }

  private resolveBookmarkFallbackPosition(id: string, roots: BookmarkRootRecord[]): number {
    const root = roots.find((item: BookmarkRootRecord) => item.nodeId === id);
    return root ? root.position : 0;
  }

  private resolveBookmarkRootScope(id: string): 'regular' | 'private' {
    if (id.startsWith('private-bookmark-root-')) {
      return 'private';
    }
    return 'regular';
  }

  private toBookmarkValues(node: BookmarkNode): relationalStore.ValuesBucket {
    return {
      id: node.id,
      scope: resolveBookmarkScope(node.scope),
      type: node.type,
      parent_id: node.parentId ?? null,
      title: node.title,
      url: node.url ?? null,
      position: node.position,
      created_at: node.createdAt,
      updated_at: node.updatedAt,
      sync_state: node.sync.state,
      sync_source: node.sync.source,
      last_modified_at: node.sync.lastModifiedAt,
      last_modified_by: node.sync.lastModifiedBy,
      device_id: node.sync.deviceId,
      origin_id: node.sync.originId ?? null,
      deleted_at: node.sync.deletedAt ?? null
    };
  }

  private toBookmarkRootValues(root: BookmarkRootRecord): relationalStore.ValuesBucket {
    return {
      role: root.role,
      node_id: root.nodeId,
      title: root.title,
      position: root.position,
      sync_enabled: root.syncEnabled ? 1 : 0
    };
  }

  private toBookmarkNodeValues(node: BookmarkNode): relationalStore.ValuesBucket {
    return {
      id: node.id,
      scope: resolveBookmarkScope(node.scope),
      type: node.type,
      title: node.title,
      url: node.url ?? null,
      created_at: node.createdAt,
      updated_at: node.updatedAt,
      sync_state: node.sync.state,
      sync_source: node.sync.source,
      last_modified_at: node.sync.lastModifiedAt,
      last_modified_by: node.sync.lastModifiedBy,
      device_id: node.sync.deviceId,
      origin_id: node.sync.originId ?? null,
      deleted_at: node.sync.deletedAt ?? null
    };
  }

  private toBookmarkOrderValues(node: BookmarkNode): relationalStore.ValuesBucket {
    return {
      parent_id: node.parentId ?? null,
      child_id: node.id,
      position: node.position,
      updated_at: node.updatedAt
    };
  }

  private toBookmarkSyncLinkValues(link: BookmarkSyncLinkRecord): relationalStore.ValuesBucket {
    return {
      node_id: link.nodeId,
      provider: link.provider,
      remote_entity_id: link.remoteEntityId ?? null,
      origin_id: link.originId ?? null,
      updated_at: link.updatedAt
    };
  }

  private toImportBatchValues(batch: BookmarkImportBatchRecord): relationalStore.ValuesBucket {
    return {
      batch_id: batch.batchId,
      source_type: batch.sourceType,
      provider_id: batch.providerId,
      source_label: batch.sourceLabel,
      source_ref: batch.sourceRef ?? null,
      created_at: batch.createdAt,
      completed_at: batch.completedAt,
      imported_folder_count: batch.importedFolderCount,
      imported_bookmark_count: batch.importedBookmarkCount,
      skipped_node_count: batch.skippedNodeCount,
      duplicate_count: batch.duplicateCount,
      root_node_id: batch.rootNodeId ?? null
    };
  }

  private toSiteIconMetadataValues(record: SiteIconMetadataRecord): relationalStore.ValuesBucket {
    return {
      domain: this.normalizeSiteIconDomain(record.domain),
      icon_url: record.iconUrl,
      source: record.source,
      extension: record.extension,
      file_uri: record.fileUri,
      quality_score: record.qualityScore,
      width: Math.max(0, Math.floor(record.width)),
      height: Math.max(0, Math.floor(record.height)),
      last_accessed_at: Math.max(0, Math.floor(record.lastAccessedAt)),
      updated_at: Math.max(0, Math.floor(record.updatedAt))
    };
  }

  private mapImportBatchRows(resultSet: relationalStore.ResultSet): BookmarkImportBatchRecord[] {
    const batches: BookmarkImportBatchRecord[] = [];
    try {
      const batchIdIndex = resultSet.getColumnIndex('batch_id');
      const sourceTypeIndex = resultSet.getColumnIndex('source_type');
      const providerIdIndex = resultSet.getColumnIndex('provider_id');
      const sourceLabelIndex = resultSet.getColumnIndex('source_label');
      const sourceRefIndex = resultSet.getColumnIndex('source_ref');
      const createdAtIndex = resultSet.getColumnIndex('created_at');
      const completedAtIndex = resultSet.getColumnIndex('completed_at');
      const importedFolderCountIndex = resultSet.getColumnIndex('imported_folder_count');
      const importedBookmarkCountIndex = resultSet.getColumnIndex('imported_bookmark_count');
      const skippedNodeCountIndex = resultSet.getColumnIndex('skipped_node_count');
      const duplicateCountIndex = resultSet.getColumnIndex('duplicate_count');
      const rootNodeIdIndex = resultSet.getColumnIndex('root_node_id');

      while (resultSet.goToNextRow()) {
        batches.push({
          batchId: resultSet.getString(batchIdIndex),
          sourceType: resultSet.getString(sourceTypeIndex) as 'aira_bundle' | 'chrome_html' | 'chrome_extension' | 'manual',
          providerId: resultSet.getString(providerIdIndex) as 'import_export' | 'chrome_companion' | 'self_hosted' | 'seed',
          sourceLabel: resultSet.getString(sourceLabelIndex),
          sourceRef: resultSet.isColumnNull(sourceRefIndex) ? undefined : resultSet.getString(sourceRefIndex),
          createdAt: resultSet.getLong(createdAtIndex),
          completedAt: resultSet.getLong(completedAtIndex),
          importedFolderCount: resultSet.getLong(importedFolderCountIndex),
          importedBookmarkCount: resultSet.getLong(importedBookmarkCountIndex),
          skippedNodeCount: resultSet.getLong(skippedNodeCountIndex),
          duplicateCount: resultSet.getLong(duplicateCountIndex),
          rootNodeId: resultSet.isColumnNull(rootNodeIdIndex) ? undefined : resultSet.getString(rootNodeIdIndex)
        });
      }
    } finally {
      try {
        resultSet.close();
      } catch (_error) {
      }
    }
    return batches;
  }

  private resolveBookmarkSyncProvider(node: BookmarkNode): 'seed' | 'import_export' | 'chrome_companion' | 'self_hosted' {
    if (node.sync.source === 'seed') {
      return 'seed';
    }
    if (node.sync.source === 'chrome_import') {
      return 'import_export';
    }
    if (node.sync.source === 'chrome_sync') {
      return 'chrome_companion';
    }
    return 'self_hosted';
  }

  private mapHistoryVisitEventRows(resultSet: relationalStore.ResultSet): HistoryVisit[] {
    const visits: HistoryVisit[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const urlIdIndex = resultSet.getColumnIndex('url_id');
      const visitedAtIndex = resultSet.getColumnIndex('visited_at');
      const fromVisitIdIndex = resultSet.getColumnIndex('from_visit_id');
      const transitionIndex = resultSet.getColumnIndex('transition');
      const visitDurationMsIndex = resultSet.getColumnIndex('visit_duration_ms');
      const sourceIndex = resultSet.getColumnIndex('source');
      const deviceIdIndex = resultSet.getColumnIndex('device_id');
      const sessionIdIndex = resultSet.getColumnIndex('session_id');
      const profileIdIndex = resultSet.getColumnIndex('profile_id');
      const dataScopeIndex = resultSet.getColumnIndex('data_scope');
      const syncIdIndex = resultSet.getColumnIndex('sync_id');
      const syncAccountUidIndex = resultSet.getColumnIndex('sync_account_uid');
      const syncOriginIndex = resultSet.getColumnIndex('sync_origin');

      while (resultSet.goToNextRow()) {
        const visitedAt = resultSet.getLong(visitedAtIndex);
        visits.push({
          id: resultSet.getString(idIndex),
          urlId: resultSet.getString(urlIdIndex),
          title: '',
          url: '',
          visitedAt: visitedAt,
          dayBucketLabel: this.resolveDayBucketLabel(visitedAt),
          source: resultSet.getString(sourceIndex) as 'seed' | 'local' | 'chrome_import' | 'chrome_sync' | 'cloud_sync',
          deviceId: resultSet.getString(deviceIdIndex),
          sessionId: resultSet.getString(sessionIdIndex),
          fromVisitId: resultSet.isColumnNull(fromVisitIdIndex) ? undefined : resultSet.getString(fromVisitIdIndex),
          transition: resultSet.getString(transitionIndex) as 'link' | 'typed' | 'auto_bookmark' | 'auto_subframe' |
            'manual_subframe' | 'generated' | 'auto_toplevel' | 'form_submit' | 'reload' | 'keyword' |
            'keyword_generated' | 'unknown',
          visitDurationMs: resultSet.getLong(visitDurationMsIndex),
          profileId: resultSet.getString(profileIdIndex) as 'profile-main',
          dataScope: resultSet.getString(dataScopeIndex) as 'profile_persistent' | 'session_ephemeral',
          syncId: resultSet.getString(syncIdIndex) || undefined,
          syncAccountUid: resultSet.getString(syncAccountUidIndex) || undefined,
          syncOrigin: (resultSet.getString(syncOriginIndex) || undefined) as 'local' | 'remote' | undefined
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map history rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close history result set: %{public}s', JSON.stringify(closeError));
      }
    }

    return visits;
  }

  private mapHistoryUrlRows(resultSet: relationalStore.ResultSet): HistoryUrlRecord[] {
    const urls: HistoryUrlRecord[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const urlIndex = resultSet.getColumnIndex('url');
      const normalizedUrlIndex = resultSet.getColumnIndex('normalized_url');
      const urlHashIndex = resultSet.getColumnIndex('url_hash');
      const originIndex = resultSet.getColumnIndex('origin');
      const hostIndex = resultSet.getColumnIndex('host');
      const titleIndex = resultSet.getColumnIndex('title');
      const visitCountIndex = resultSet.getColumnIndex('visit_count');
      const typedCountIndex = resultSet.getColumnIndex('typed_count');
      const lastVisitAtIndex = resultSet.getColumnIndex('last_visit_at');
      const hiddenIndex = resultSet.getColumnIndex('hidden');
      const faviconKeyIndex = resultSet.getColumnIndex('favicon_key');
      const createdAtIndex = resultSet.getColumnIndex('created_at');
      const updatedAtIndex = resultSet.getColumnIndex('updated_at');

      while (resultSet.goToNextRow()) {
        urls.push({
          id: resultSet.getString(idIndex),
          url: resultSet.getString(urlIndex),
          normalizedUrl: resultSet.getString(normalizedUrlIndex),
          urlHash: resultSet.getString(urlHashIndex),
          origin: resultSet.getString(originIndex),
          host: resultSet.getString(hostIndex),
          title: resultSet.getString(titleIndex),
          visitCount: resultSet.getLong(visitCountIndex),
          typedCount: resultSet.getLong(typedCountIndex),
          lastVisitAt: resultSet.getLong(lastVisitAtIndex),
          hidden: resultSet.getLong(hiddenIndex) === 1,
          faviconKey: resultSet.getString(faviconKeyIndex),
          createdAt: resultSet.getLong(createdAtIndex),
          updatedAt: resultSet.getLong(updatedAtIndex)
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map history url rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close history url result set: %{public}s', JSON.stringify(closeError));
      }
    }

    return urls;
  }

  private mapHistorySiteAggregateRows(resultSet: relationalStore.ResultSet): HistorySiteAggregate[] {
    const sites: HistorySiteAggregate[] = [];
    try {
      const hostIndex = resultSet.getColumnIndex('host');
      const originIndex = resultSet.getColumnIndex('origin');
      const latestTitleIndex = resultSet.getColumnIndex('latest_title');
      const latestUrlIndex = resultSet.getColumnIndex('latest_url');
      const latestVisitedAtIndex = resultSet.getColumnIndex('latest_visited_at');
      const visitCountIndex = resultSet.getColumnIndex('visit_count');
      const uniqueUrlCountIndex = resultSet.getColumnIndex('unique_url_count');

      while (resultSet.goToNextRow()) {
        const host = resultSet.getString(hostIndex);
        const latestVisitedAt = resultSet.getLong(latestVisitedAtIndex);
        const visitCount = resultSet.getLong(visitCountIndex);
        sites.push({
          key: `${host}:${visitCount}:${latestVisitedAt}`,
          host: host.length > 0 ? host : '未知站点',
          origin: resultSet.getString(originIndex),
          title: host.length > 0 ? host : '未知站点',
          latestTitle: resultSet.getString(latestTitleIndex),
          latestUrl: resultSet.getString(latestUrlIndex),
          latestVisitedAt: latestVisitedAt,
          visitCount: visitCount,
          uniqueUrlCount: resultSet.getLong(uniqueUrlCountIndex)
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map history site rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close history site result set: %{public}s', JSON.stringify(closeError));
      }
    }

    return sites;
  }

  private toHistoryVisitValues(visit: HistoryVisit): relationalStore.ValuesBucket {
    return {
      id: visit.id,
      url_id: visit.urlId ?? '',
      visited_at: visit.visitedAt,
      from_visit_id: visit.fromVisitId ?? null,
      transition: visit.transition ?? 'link',
      visit_duration_ms: visit.visitDurationMs ?? 0,
      source: visit.source,
      device_id: visit.deviceId,
      session_id: visit.sessionId,
      profile_id: visit.profileId ?? 'profile-main',
      data_scope: visit.dataScope ?? 'profile_persistent',
      sync_id: visit.syncId ?? '',
      sync_account_uid: visit.syncAccountUid ?? '',
      sync_origin: visit.syncOrigin ?? ''
    };
  }

  private toHistoryUrlValues(record: HistoryUrlRecord): relationalStore.ValuesBucket {
    return {
      id: record.id,
      url: record.url,
      normalized_url: record.normalizedUrl,
      url_hash: record.urlHash,
      origin: record.origin,
      host: record.host,
      title: record.title,
      visit_count: record.visitCount,
      typed_count: record.typedCount,
      last_visit_at: record.lastVisitAt,
      hidden: record.hidden ? 1 : 0,
      favicon_key: record.faviconKey,
      created_at: record.createdAt,
      updated_at: record.updatedAt
    };
  }

  private toSearchQueryHistoryValues(record: SearchQueryHistoryRecord): relationalStore.ValuesBucket {
    return {
      id: record.id,
      query: record.query,
      normalized_query: record.normalizedQuery,
      compact_query: record.compactQuery,
      search_engine_id: record.searchEngineId,
      use_count: record.useCount,
      first_searched_at: record.firstSearchedAt,
      last_searched_at: record.lastSearchedAt,
      profile_id: record.profileId,
      data_scope: record.dataScope
    };
  }

  private mapSearchQueryHistoryRows(resultSet: relationalStore.ResultSet): SearchQueryHistoryRecord[] {
    const records: SearchQueryHistoryRecord[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const queryIndex = resultSet.getColumnIndex('query');
      const normalizedQueryIndex = resultSet.getColumnIndex('normalized_query');
      const compactQueryIndex = resultSet.getColumnIndex('compact_query');
      const searchEngineIdIndex = resultSet.getColumnIndex('search_engine_id');
      const useCountIndex = resultSet.getColumnIndex('use_count');
      const firstSearchedAtIndex = resultSet.getColumnIndex('first_searched_at');
      const lastSearchedAtIndex = resultSet.getColumnIndex('last_searched_at');
      const profileIdIndex = resultSet.getColumnIndex('profile_id');
      const dataScopeIndex = resultSet.getColumnIndex('data_scope');
      while (resultSet.goToNextRow()) {
        records.push({
          id: resultSet.getString(idIndex),
          query: resultSet.getString(queryIndex),
          normalizedQuery: resultSet.getString(normalizedQueryIndex),
          compactQuery: resultSet.getString(compactQueryIndex),
          searchEngineId: resultSet.getString(searchEngineIdIndex),
          useCount: resultSet.getLong(useCountIndex),
          firstSearchedAt: resultSet.getLong(firstSearchedAtIndex),
          lastSearchedAt: resultSet.getLong(lastSearchedAtIndex),
          profileId: resultSet.getString(profileIdIndex) as 'profile-main',
          dataScope: resultSet.getString(dataScopeIndex) as 'profile_persistent' | 'session_ephemeral'
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map search query history rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close search query history result set: %{public}s', JSON.stringify(closeError));
      }
    }
    return records;
  }

  private async hydrateHistoryVisits(visits: HistoryVisit[]): Promise<HistoryVisit[]> {
    if (visits.length === 0) {
      return [];
    }
    const urls: Record<string, HistoryUrlRecord> = {};
    const store = await this.getStore();
    if (visits.length > HISTORY_HYDRATE_BATCH_URL_THRESHOLD) {
      const urlRows = await store.query(new relationalStore.RdbPredicates(HISTORY_URLS_TABLE), HISTORY_URL_COLUMNS);
      this.mapHistoryUrlRows(urlRows).forEach((urlRecord: HistoryUrlRecord) => {
        urls[urlRecord.id] = urlRecord;
      });
      return visits.map((visit: HistoryVisit) => {
        const urlRecord = urls[visit.urlId ?? ''];
        if (urlRecord === undefined) {
          return visit;
        }
        return this.mergeHistoryVisitWithUrlRecord(visit, urlRecord);
      });
    }
    for (const visit of visits) {
      const urlId = visit.urlId ?? '';
      if (urlId.length === 0 || urls[urlId] !== undefined) {
        continue;
      }
      const urlRecord = await this.findHistoryUrlById(store, urlId);
      if (urlRecord !== undefined) {
        urls[urlId] = urlRecord;
      }
    }
    return visits.map((visit: HistoryVisit) => {
      const urlRecord = urls[visit.urlId ?? ''];
      if (urlRecord === undefined) {
        return visit;
      }
      return this.mergeHistoryVisitWithUrlRecord(visit, urlRecord);
    });
  }

  private mergeHistoryVisitWithUrlRecord(visit: HistoryVisit, urlRecord: HistoryUrlRecord): HistoryVisit {
    return {
      id: visit.id,
      urlId: urlRecord.id,
      title: urlRecord.title,
      url: urlRecord.url,
      normalizedUrl: urlRecord.normalizedUrl,
      origin: urlRecord.origin,
      host: urlRecord.host,
      visitedAt: visit.visitedAt,
      dayBucketLabel: this.resolveDayBucketLabel(visit.visitedAt),
      source: visit.source,
      deviceId: visit.deviceId,
      sessionId: visit.sessionId,
      fromVisitId: visit.fromVisitId,
      transition: visit.transition,
      visitDurationMs: visit.visitDurationMs,
      profileId: visit.profileId,
      dataScope: visit.dataScope,
      visitCount: urlRecord.visitCount,
      typedCount: urlRecord.typedCount,
      lastVisitAt: urlRecord.lastVisitAt,
      syncId: visit.syncId,
      syncAccountUid: visit.syncAccountUid,
      syncOrigin: visit.syncOrigin
    };
  }

  private async upsertHistoryVisitInStore(
    store: relationalStore.RdbStore,
    visit: HistoryVisit
  ): Promise<void> {
    const urlRecord = await this.upsertHistoryUrlRecord(store, visit);
    const visitWithUrlId: HistoryVisit = {
      id: visit.id,
      urlId: urlRecord.id,
      title: urlRecord.title,
      url: urlRecord.url,
      normalizedUrl: urlRecord.normalizedUrl,
      origin: urlRecord.origin,
      host: urlRecord.host,
      visitedAt: visit.visitedAt,
      dayBucketLabel: visit.dayBucketLabel,
      source: visit.source,
      deviceId: visit.deviceId,
      sessionId: visit.sessionId,
      fromVisitId: visit.fromVisitId,
      transition: visit.transition,
      visitDurationMs: visit.visitDurationMs,
      profileId: visit.profileId,
      dataScope: visit.dataScope,
      visitCount: urlRecord.visitCount,
      typedCount: urlRecord.typedCount,
      lastVisitAt: urlRecord.lastVisitAt,
      syncId: visit.syncId,
      syncAccountUid: visit.syncAccountUid,
      syncOrigin: visit.syncOrigin
    };
    const predicates = this.createHistoryVisitIdPredicates(visit.id);
    const count = await store.update(this.toHistoryVisitValues(visitWithUrlId), predicates);
    if (count === 0) {
      await store.insert(HISTORY_VISITS_TABLE, this.toHistoryVisitValues(visitWithUrlId));
    }
  }

  private async enqueueHistoryVisitUpsert(
    store: relationalStore.RdbStore,
    visit: HistoryVisit,
    context: HistorySyncOutboxContext
  ): Promise<void> {
    const syncId = (visit.syncId ?? '').trim();
    if (syncId.length <= 0 || context.accountUid.trim().length <= 0 || context.clientId.trim().length <= 0) {
      return;
    }
    const prefix = `h1:${context.clientId}:`;
    if (!syncId.startsWith(prefix)) {
      return;
    }
    const syncUrl = this.normalizeHistorySyncUrl(visit.url);
    if (syncUrl.length <= 0) {
      return;
    }
    const syncVisit: HistorySyncVisit = {
      visitId: syncId,
      clientId: context.clientId,
      nativeVisitId: syncId.slice(prefix.length),
      url: syncUrl,
      title: visit.title,
      visitedAt: visit.visitedAt,
      transition: visit.transition ?? 'link',
      referrer: '',
      deviceName: context.deviceName,
      source: 'app'
    };
    const mutation: HistorySyncMutation = {
      mutationId: this.createHistorySyncMutationId(context.clientId, 'upsert'),
      kind: 'upsert_visit',
      visit: syncVisit
    };
    await this.persistHistorySyncCanonicalVisit(store, context.accountUid, syncVisit);
    await this.insertHistorySyncMutation(store, context.accountUid, mutation);
  }

  private async enqueueHistoryVisitDelete(
    store: relationalStore.RdbStore,
    visit: HistoryVisit | undefined,
    context?: HistorySyncOutboxContext
  ): Promise<void> {
    if (visit === undefined || context === undefined || context.origin !== 'user_deletion') {
      return;
    }
    const syncId = (visit.syncId ?? '').trim();
    const syncAccountUid = (visit.syncAccountUid ?? '').trim();
    if (syncId.length <= 0 || syncAccountUid !== context.accountUid.trim()) {
      return;
    }
    const mutation: HistorySyncMutation = {
      mutationId: this.createHistorySyncMutationId(context.clientId, 'delete'),
      kind: 'delete_visit',
      visitId: syncId
    };
    await this.persistHistorySyncTombstone(store, context.accountUid, syncId, Date.now());
    await this.insertHistorySyncMutation(store, context.accountUid, mutation);
  }

  private async enqueueHistoryClearBefore(
    store: relationalStore.RdbStore,
    context: HistorySyncOutboxContext,
    clearBefore: number
  ): Promise<void> {
    if (context.origin !== 'user_deletion' || context.accountUid.trim().length <= 0) {
      return;
    }
    const mutation: HistorySyncMutation = {
      mutationId: this.createHistorySyncMutationId(context.clientId, 'clear'),
      kind: 'clear_before',
      clearBefore: clearBefore
    };
    await this.persistHistorySyncClearBefore(store, context.accountUid, clearBefore);
    await this.insertHistorySyncMutation(store, context.accountUid, mutation);
  }

  private async insertHistorySyncMutation(
    store: relationalStore.RdbStore,
    accountUid: string,
    mutation: HistorySyncMutation
  ): Promise<void> {
    await store.insert(HISTORY_SYNC_OUTBOX_TABLE, {
      account_uid: accountUid.trim(),
      mutation_id: mutation.mutationId,
      kind: mutation.kind,
      payload_json: JSON.stringify(mutation),
      created_at: Date.now()
    });
  }

  private async applyHistorySyncChangesInStore(
    store: relationalStore.RdbStore,
    accountUid: string,
    changes: HistorySyncChange[]
  ): Promise<number> {
    let applied = 0;
    for (const change of changes) {
      if (change.kind === 'upsert_visit' && change.visit !== undefined) {
        applied += await this.applyHistorySyncVisitUpsert(store, accountUid, change.visit);
        continue;
      }
      if (change.kind === 'delete_visit') {
        await this.persistHistorySyncTombstone(store, accountUid, change.visitId, Date.now());
        applied += await this.deleteHistoryVisitBySyncIdInStore(store, accountUid, change.visitId);
        continue;
      }
      if (change.kind === 'delete_range') {
        const range: HistorySyncDeleteRange = {
          rangeId: change.rangeId ?? '',
          url: change.url ?? '',
          startedAt: change.startedAt ?? 0,
          endedAt: change.endedAt ?? 0,
          seq: change.seq
        };
        await this.persistHistorySyncDeleteRange(store, accountUid, range);
        applied += await this.deleteHistorySyncRangeInStore(store, accountUid, range);
        continue;
      }
      if (change.kind === 'clear_before') {
        const clearBefore = change.clearBefore ?? 0;
        await this.persistHistorySyncClearBefore(store, accountUid, clearBefore);
        applied += await this.deleteHistorySyncBeforeInStore(store, accountUid, clearBefore);
        continue;
      }
      if (change.kind === 'retention_prune') {
        for (const visitId of change.visitIds ?? []) {
          await this.deleteHistorySyncCanonicalVisit(store, accountUid, visitId);
          applied += await this.deleteHistoryVisitBySyncIdInStore(store, accountUid, visitId);
        }
        await this.advanceHistorySyncRetentionFromRemotePrune(store, accountUid, change.cutoff ?? 0);
      }
    }
    return applied;
  }

  private async applyHistorySyncVisitUpsert(
    store: relationalStore.RdbStore,
    accountUid: string,
    visit: HistorySyncVisit,
    replaceCanonical: boolean = false
  ): Promise<number> {
    if (await this.isHistorySyncVisitBehindFrontier(store, accountUid, visit)) {
      return 0;
    }
    await this.persistHistorySyncCanonicalVisit(store, accountUid, visit, replaceCanonical);
    const normalizedVisitUrl = this.normalizeHistorySyncUrl(visit.url);
    if (normalizedVisitUrl.length <= 0) {
      throw new Error('History sync visit URL is invalid.');
    }
    const existing = await this.findHistoryVisitEventBySyncId(store, accountUid, visit.visitId);
    if (existing !== undefined) {
      // The first accepted visit row is canonical. Older clients can retry the
      // same sync ID with different metadata; preserve local content and keep
      // the cursor transaction moving instead of failing the whole exchange.
      const updated: HistoryVisit = {
        id: existing.id,
        urlId: existing.urlId,
        title: existing.title,
        url: existing.url,
        normalizedUrl: existing.normalizedUrl,
        origin: existing.origin,
        host: existing.host,
        visitedAt: existing.visitedAt,
        dayBucketLabel: existing.dayBucketLabel,
        source: existing.source,
        deviceId: existing.deviceId,
        sessionId: existing.sessionId,
        fromVisitId: existing.fromVisitId,
        transition: existing.transition,
        visitDurationMs: existing.visitDurationMs,
        profileId: existing.profileId,
        dataScope: existing.dataScope,
        visitCount: existing.visitCount,
        typedCount: existing.typedCount,
        lastVisitAt: existing.lastVisitAt,
        syncId: existing.syncId,
        syncAccountUid: accountUid,
        syncOrigin: existing.syncOrigin ?? 'local'
      };
      await store.update(this.toHistoryVisitValues(updated), this.createHistoryVisitIdPredicates(existing.id));
      return 0;
    }
    const remoteVisit: HistoryVisit = {
      id: visit.visitId,
      title: visit.title.trim().length > 0 ? visit.title : visit.url,
      url: normalizedVisitUrl,
      visitedAt: visit.visitedAt,
      dayBucketLabel: this.resolveDayBucketLabel(visit.visitedAt),
      source: 'cloud_sync',
      deviceId: visit.clientId,
      sessionId: 'aira-history-sync',
      transition: visit.transition,
      visitDurationMs: 0,
      profileId: 'profile-main',
      dataScope: 'profile_persistent',
      syncId: visit.visitId,
      syncAccountUid: accountUid,
      syncOrigin: 'remote'
    };
    await this.upsertHistoryVisitInStore(store, remoteVisit);
    return 1;
  }

  private async isHistorySyncVisitBehindFrontier(
    store: relationalStore.RdbStore,
    accountUid: string,
    visit: HistorySyncVisit
  ): Promise<boolean> {
    const frontierPredicates = new relationalStore.RdbPredicates(HISTORY_SYNC_FRONTIERS_TABLE);
    frontierPredicates.equalTo('account_uid', accountUid);
    frontierPredicates.limitAs(1);
    const frontierResult = await store.query(frontierPredicates, ['clear_before']);
    try {
      if (frontierResult.goToNextRow() &&
        visit.visitedAt <= frontierResult.getLong(frontierResult.getColumnIndex('clear_before'))) {
        return true;
      }
    } finally {
      frontierResult.close();
    }
    const rangePredicates = new relationalStore.RdbPredicates(HISTORY_SYNC_DELETE_RANGES_TABLE);
    rangePredicates.equalTo('account_uid', accountUid);
    rangePredicates.equalTo('url', visit.url);
    const rangeResult = await store.query(rangePredicates, ['started_at', 'ended_at']);
    try {
      const startIndex = rangeResult.getColumnIndex('started_at');
      const endIndex = rangeResult.getColumnIndex('ended_at');
      while (rangeResult.goToNextRow()) {
        if (visit.visitedAt >= rangeResult.getLong(startIndex) && visit.visitedAt <= rangeResult.getLong(endIndex)) {
          return true;
        }
      }
    } finally {
      rangeResult.close();
    }
    const tombstonePredicates = new relationalStore.RdbPredicates(HISTORY_SYNC_TOMBSTONES_TABLE);
    tombstonePredicates.equalTo('account_uid', accountUid);
    tombstonePredicates.equalTo('visit_id', visit.visitId);
    tombstonePredicates.limitAs(1);
    const tombstoneResult = await store.query(tombstonePredicates, ['visit_id']);
    try {
      if (tombstoneResult.goToNextRow()) {
        return true;
      }
    } finally {
      tombstoneResult.close();
    }
    const retention = await this.readHistorySyncRetentionFrontier(store, accountUid);
    if (visit.visitedAt < retention.cutoffAt) {
      return true;
    }
    if (retention.boundaryVisitedAt > 0 && (visit.visitedAt < retention.boundaryVisitedAt ||
      (visit.visitedAt === retention.boundaryVisitedAt &&
        visit.visitId.localeCompare(retention.boundaryVisitId) < 0))) {
      return true;
    }
    return false;
  }

  private async findHistoryVisitEventBySyncId(
    store: relationalStore.RdbStore,
    accountUid: string,
    syncId: string
  ): Promise<HistoryVisit | undefined> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    predicates.equalTo('sync_account_uid', accountUid.trim());
    predicates.equalTo('sync_id', syncId.trim());
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    const rows = this.mapHistoryVisitEventRows(resultSet);
    const hydrated = await this.hydrateHistoryVisits(rows);
    return hydrated[0];
  }

  private async deleteHistoryVisitBySyncIdInStore(
    store: relationalStore.RdbStore,
    accountUid: string,
    syncId: string
  ): Promise<number> {
    const existing = await this.findHistoryVisitEventBySyncId(store, accountUid, syncId);
    if (existing === undefined) {
      return 0;
    }
    const removed = await store.delete(this.createHistoryVisitIdPredicates(existing.id));
    if (removed > 0 && existing.urlId !== undefined) {
      await this.recalculateHistoryUrlAggregate(store, existing.urlId);
    }
    return removed;
  }

  private async deleteHistorySyncRangeInStore(
    store: relationalStore.RdbStore,
    accountUid: string,
    range: HistorySyncDeleteRange
  ): Promise<number> {
    if (range.url.trim().length <= 0 || range.startedAt < 0 || range.endedAt < range.startedAt) {
      return 0;
    }
    const urlRecord = await this.findHistoryUrlByHash(store, this.hashHistoryUrl(this.normalizeHistoryUrl(range.url)));
    if (urlRecord === undefined) {
      return 0;
    }
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    predicates.equalTo('sync_account_uid', accountUid.trim());
    predicates.equalTo('url_id', urlRecord.id);
    predicates.between('visited_at', range.startedAt, range.endedAt);
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    return this.deleteHydratedHistoryVisitEvents(store, this.mapHistoryVisitEventRows(resultSet));
  }

  private async deleteHistorySyncBeforeInStore(
    store: relationalStore.RdbStore,
    accountUid: string,
    clearBefore: number
  ): Promise<number> {
    if (clearBefore <= 0) {
      return 0;
    }
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    predicates.equalTo('sync_account_uid', accountUid.trim());
    predicates.between('visited_at', 0, clearBefore);
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    return this.deleteHydratedHistoryVisitEvents(store, this.mapHistoryVisitEventRows(resultSet));
  }

  private async persistHistorySyncDeleteRange(
    store: relationalStore.RdbStore,
    accountUid: string,
    range: HistorySyncDeleteRange
  ): Promise<void> {
    if (range.rangeId.trim().length <= 0 || range.url.trim().length <= 0) {
      return;
    }
    await store.batchInsertWithConflictResolution(
      HISTORY_SYNC_DELETE_RANGES_TABLE,
      [{
        account_uid: accountUid,
        range_id: range.rangeId,
        url: range.url,
        started_at: range.startedAt,
        ended_at: range.endedAt,
        seq: range.seq
      }],
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
    );
  }

  private async persistHistorySyncClearBefore(
    store: relationalStore.RdbStore,
    accountUid: string,
    clearBefore: number
  ): Promise<void> {
    if (clearBefore <= 0) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_FRONTIERS_TABLE);
    predicates.equalTo('account_uid', accountUid);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, ['clear_before']);
    let current = 0;
    try {
      if (resultSet.goToNextRow()) {
        current = resultSet.getLong(resultSet.getColumnIndex('clear_before'));
      }
    } finally {
      resultSet.close();
    }
    if (clearBefore <= current) {
      return;
    }
    await store.batchInsertWithConflictResolution(
      HISTORY_SYNC_FRONTIERS_TABLE,
      [{ account_uid: accountUid, clear_before: clearBefore, updated_at: Date.now() }],
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
    );
  }

  private emptyHuaweiSpaceHistorySyncState(): HuaweiSpaceHistorySyncState {
    return {
      visits: [],
      tombstones: [],
      deleteRanges: [],
      clearBefore: 0,
      retentionFrontier: {
        cutoffAt: 0,
        boundaryVisitedAt: 0,
        boundaryVisitId: '',
        updatedAt: 0
      }
    };
  }

  private async persistHistorySyncCanonicalVisit(
    store: relationalStore.RdbStore,
    accountUid: string,
    visit: HistorySyncVisit,
    replaceExisting: boolean = false
  ): Promise<void> {
    const visitId = visit.visitId.trim();
    if (accountUid.trim().length <= 0 || visitId.length <= 0) {
      return;
    }
    await store.insert(
      HISTORY_SYNC_CANONICAL_VISITS_TABLE,
      {
        account_uid: accountUid.trim(),
        visit_id: visitId,
        payload_json: JSON.stringify(visit),
        visited_at: visit.visitedAt,
        updated_at: Date.now()
      },
      replaceExisting
        ? relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
        : relationalStore.ConflictResolution.ON_CONFLICT_IGNORE
    );
  }

  private async deleteHistorySyncCanonicalVisit(
    store: relationalStore.RdbStore,
    accountUid: string,
    visitId: string
  ): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_CANONICAL_VISITS_TABLE);
    predicates.equalTo('account_uid', accountUid.trim());
    predicates.equalTo('visit_id', visitId.trim());
    return store.delete(predicates);
  }

  private async readHistorySyncCanonicalVisits(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<HistorySyncVisit[]> {
    return this.readHistorySyncCanonicalVisitsUpdatedAfter(store, accountUid, 0);
  }

  private async readHistorySyncCanonicalVisitsUpdatedAfter(
    store: relationalStore.RdbStore,
    accountUid: string,
    updatedAfter: number
  ): Promise<HistorySyncVisit[]> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_CANONICAL_VISITS_TABLE);
    predicates.equalTo('account_uid', accountUid);
    const normalizedUpdatedAfter = Math.max(0, Math.floor(updatedAfter));
    if (normalizedUpdatedAfter > 0) {
      predicates.greaterThan('updated_at', normalizedUpdatedAfter - 1);
    }
    predicates.orderByDesc('visited_at');
    predicates.orderByDesc('visit_id');
    const resultSet = await store.queryWithoutRowCount(predicates, ['visit_id', 'payload_json']);
    const rowVisitIds: string[] = [];
    const rowPayloads: string[] = [];
    try {
      const visitIdIndex = resultSet.getColumnIndex('visit_id');
      const payloadIndex = resultSet.getColumnIndex('payload_json');
      while (resultSet.goToNextRow()) {
        rowVisitIds.push(resultSet.getString(visitIdIndex).trim());
        rowPayloads.push(resultSet.getString(payloadIndex));
        if (rowVisitIds.length % HISTORY_SYNC_CANONICAL_READ_BATCH_SIZE === 0) {
          await this.yieldHistorySyncReadBatch();
        }
      }
    } finally {
      resultSet.close();
    }
    const visits: HistorySyncVisit[] = [];
    for (let index = 0; index < rowVisitIds.length; index += 1) {
      const visitId = rowVisitIds[index];
      const visit = JSON.parse(rowPayloads[index]) as HistorySyncVisit;
      if (visitId.length <= 0 || visit.visitId?.trim() !== visitId) {
        throw new Error('History canonical visit identity mismatch.');
      }
      visits.push(visit);
      if ((index + 1) % HISTORY_SYNC_CANONICAL_READ_BATCH_SIZE === 0) {
        await this.yieldHistorySyncReadBatch();
      }
    }
    return visits;
  }

  private async hasHistorySyncProjectionVictims(
    store: relationalStore.RdbStore,
    accountUid: string,
    cutoff: number
  ): Promise<boolean> {
    const agedResult = await store.querySql(
      `SELECT 1 FROM ${HISTORY_VISITS_TABLE} WHERE sync_account_uid = ? ` +
        `AND data_scope = 'profile_persistent' AND visited_at < ? LIMIT 1`,
      [accountUid, cutoff]
    );
    try {
      if (agedResult.goToNextRow()) {
        return true;
      }
    } finally {
      agedResult.close();
    }
    const overflowResult = await store.querySql(
      `SELECT 1 FROM ${HISTORY_VISITS_TABLE} WHERE sync_account_uid = ? ` +
        `AND data_scope = 'profile_persistent' ORDER BY visited_at DESC, sync_id DESC ` +
        `LIMIT 1 OFFSET ${HISTORY_SYNC_MAX_VISITS}`,
      [accountUid]
    );
    try {
      return overflowResult.goToNextRow();
    } finally {
      overflowResult.close();
    }
  }

  private yieldHistorySyncReadBatch(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 0);
    });
  }

  private async backfillHistorySyncCanonicalVisitsInStore(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    predicates.equalTo('sync_account_uid', accountUid);
    predicates.equalTo('data_scope', 'profile_persistent');
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    const visits = await this.hydrateHistoryVisits(this.mapHistoryVisitEventRows(resultSet));
    const values: relationalStore.ValuesBucket[] = [];
    const updatedAt = Date.now();
    for (const visit of visits) {
      const canonical = this.buildCanonicalHistorySyncVisit(visit);
      if (canonical !== undefined) {
        values.push({
          account_uid: accountUid,
          visit_id: canonical.visitId,
          payload_json: JSON.stringify(canonical),
          visited_at: canonical.visitedAt,
          updated_at: updatedAt
        });
      }
    }
    for (let index = 0; index < values.length; index += HISTORY_SYNC_CANONICAL_BACKFILL_BATCH_SIZE) {
      await store.batchInsertWithConflictResolution(
        HISTORY_SYNC_CANONICAL_VISITS_TABLE,
        values.slice(index, index + HISTORY_SYNC_CANONICAL_BACKFILL_BATCH_SIZE),
        relationalStore.ConflictResolution.ON_CONFLICT_IGNORE
      );
    }
  }

  private async ensureHistorySyncCanonicalVisitsBackfilled(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<void> {
    const normalizedUid = accountUid.trim();
    if (normalizedUid.length <= 0 || this.historySyncCanonicalBackfilledAccounts.has(normalizedUid)) {
      return;
    }
    const stateKey = `${HISTORY_SYNC_CANONICAL_BACKFILL_STATE_PREFIX}${normalizedUid}`;
    const completionVersion = await this.readSchemaStateVersion(store, stateKey);
    if (completionVersion < HISTORY_SYNC_CANONICAL_BACKFILL_STATE_VERSION) {
      if (await this.hasMissingHistorySyncCanonicalVisits(store, normalizedUid)) {
        await this.backfillHistorySyncCanonicalVisitsInStore(store, normalizedUid);
      }
      await this.writeSchemaStateVersion(
        store,
        stateKey,
        HISTORY_SYNC_CANONICAL_BACKFILL_STATE_VERSION
      );
    }
    this.historySyncCanonicalBackfilledAccounts.add(normalizedUid);
  }

  private async hasMissingHistorySyncCanonicalVisits(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<boolean> {
    const resultSet = await store.querySql(
      `SELECT 1 FROM ${HISTORY_VISITS_TABLE} visits ` +
        `LEFT JOIN ${HISTORY_SYNC_CANONICAL_VISITS_TABLE} canonical ` +
        `ON canonical.account_uid = ? AND canonical.visit_id = visits.sync_id ` +
        `WHERE visits.sync_account_uid = ? AND visits.data_scope = 'profile_persistent' ` +
        `AND visits.sync_id <> '' AND canonical.visit_id IS NULL LIMIT 1`,
      [accountUid, accountUid]
    );
    try {
      return resultSet.goToNextRow();
    } finally {
      resultSet.close();
    }
  }

  private buildCanonicalHistorySyncVisit(visit: HistoryVisit): HistorySyncVisit | undefined {
    const visitId = (visit.syncId ?? '').trim();
    if (!visitId.startsWith('h1:')) {
      return undefined;
    }
    const clientSeparator = visitId.indexOf(':', 3);
    if (clientSeparator <= 3 || clientSeparator >= visitId.length - 1) {
      return undefined;
    }
    const clientId = visitId.slice(3, clientSeparator);
    const nativeVisitId = visitId.slice(clientSeparator + 1);
    const normalizedUrl = this.normalizeHistorySyncUrl(visit.url);
    if (normalizedUrl.length <= 0) {
      return undefined;
    }
    return {
      visitId,
      clientId,
      nativeVisitId,
      url: normalizedUrl,
      title: visit.title,
      visitedAt: visit.visitedAt,
      transition: visit.transition ?? 'link',
      referrer: '',
      deviceName: visit.syncOrigin === 'local' ? 'Aira HarmonyOS' : 'Aira device',
      source: 'app'
    };
  }

  private async persistHistorySyncTombstone(
    store: relationalStore.RdbStore,
    accountUid: string,
    visitId: string,
    deletedAt: number
  ): Promise<void> {
    const normalizedUid = accountUid.trim();
    const normalizedVisitId = visitId.trim();
    const normalizedDeletedAt = Math.max(0, Math.floor(deletedAt));
    if (normalizedUid.length <= 0 || normalizedVisitId.length <= 0 || normalizedDeletedAt <= 0) {
      return;
    }
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_TOMBSTONES_TABLE);
    predicates.equalTo('account_uid', normalizedUid);
    predicates.equalTo('visit_id', normalizedVisitId);
    const resultSet = await store.query(predicates, ['deleted_at']);
    let current = 0;
    try {
      if (resultSet.goToNextRow()) {
        current = resultSet.getLong(resultSet.getColumnIndex('deleted_at'));
      }
    } finally {
      resultSet.close();
    }
    if (current >= normalizedDeletedAt) {
      return;
    }
    await store.insert(HISTORY_SYNC_TOMBSTONES_TABLE, {
      account_uid: normalizedUid,
      visit_id: normalizedVisitId,
      deleted_at: normalizedDeletedAt
    }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    await this.deleteHistorySyncCanonicalVisit(store, normalizedUid, normalizedVisitId);
  }

  private async readHistorySyncTombstones(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<HistorySyncExactTombstone[]> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_TOMBSTONES_TABLE);
    predicates.equalTo('account_uid', accountUid);
    predicates.orderByDesc('deleted_at');
    const resultSet = await store.queryWithoutRowCount(predicates, ['visit_id', 'deleted_at']);
    const values: HistorySyncExactTombstone[] = [];
    try {
      const visitIdIndex = resultSet.getColumnIndex('visit_id');
      const deletedAtIndex = resultSet.getColumnIndex('deleted_at');
      while (resultSet.goToNextRow()) {
        values.push({
          visitId: resultSet.getString(visitIdIndex),
          deletedAt: resultSet.getLong(deletedAtIndex)
        });
      }
    } finally {
      resultSet.close();
    }
    return values;
  }

  private async readHistorySyncDeleteRanges(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<HistorySyncDeleteRange[]> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_DELETE_RANGES_TABLE);
    predicates.equalTo('account_uid', accountUid);
    const resultSet = await store.queryWithoutRowCount(predicates, [
      'range_id', 'url', 'started_at', 'ended_at', 'seq'
    ]);
    const ranges: HistorySyncDeleteRange[] = [];
    try {
      while (resultSet.goToNextRow()) {
        ranges.push({
          rangeId: resultSet.getString(resultSet.getColumnIndex('range_id')),
          url: resultSet.getString(resultSet.getColumnIndex('url')),
          startedAt: resultSet.getLong(resultSet.getColumnIndex('started_at')),
          endedAt: resultSet.getLong(resultSet.getColumnIndex('ended_at')),
          seq: resultSet.getLong(resultSet.getColumnIndex('seq'))
        });
      }
    } finally {
      resultSet.close();
    }
    return ranges;
  }

  private async readHistorySyncClearBefore(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_FRONTIERS_TABLE);
    predicates.equalTo('account_uid', accountUid);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, ['clear_before']);
    try {
      return resultSet.goToNextRow() ? resultSet.getLong(resultSet.getColumnIndex('clear_before')) : 0;
    } finally {
      resultSet.close();
    }
  }

  private async readHistorySyncRetentionFrontier(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<HistorySyncRetentionFrontier> {
    const empty: HistorySyncRetentionFrontier = {
      cutoffAt: 0,
      boundaryVisitedAt: 0,
      boundaryVisitId: '',
      updatedAt: 0
    };
    const predicates = new relationalStore.RdbPredicates(HISTORY_SYNC_RETENTION_TABLE);
    predicates.equalTo('account_uid', accountUid);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, [
      'cutoff_at', 'boundary_visited_at', 'boundary_visit_id', 'updated_at'
    ]);
    try {
      if (!resultSet.goToNextRow()) {
        return empty;
      }
      return {
        cutoffAt: resultSet.getLong(resultSet.getColumnIndex('cutoff_at')),
        boundaryVisitedAt: resultSet.getLong(resultSet.getColumnIndex('boundary_visited_at')),
        boundaryVisitId: resultSet.getString(resultSet.getColumnIndex('boundary_visit_id')),
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      };
    } finally {
      resultSet.close();
    }
  }

  private async persistHistorySyncRetentionFrontier(
    store: relationalStore.RdbStore,
    accountUid: string,
    frontier: HistorySyncRetentionFrontier
  ): Promise<void> {
    const current = await this.readHistorySyncRetentionFrontier(store, accountUid);
    const candidateBoundaryIsNewer = frontier.boundaryVisitedAt > current.boundaryVisitedAt ||
      (frontier.boundaryVisitedAt === current.boundaryVisitedAt &&
        frontier.boundaryVisitId.localeCompare(current.boundaryVisitId) > 0);
    const merged: HistorySyncRetentionFrontier = {
      cutoffAt: Math.max(current.cutoffAt, Math.max(0, Math.floor(frontier.cutoffAt))),
      boundaryVisitedAt: candidateBoundaryIsNewer
        ? Math.max(0, Math.floor(frontier.boundaryVisitedAt))
        : current.boundaryVisitedAt,
      boundaryVisitId: candidateBoundaryIsNewer ? frontier.boundaryVisitId.trim() : current.boundaryVisitId,
      updatedAt: Math.max(current.updatedAt, Math.max(0, Math.floor(frontier.updatedAt)))
    };
    if (merged.cutoffAt <= 0 && merged.boundaryVisitedAt <= 0) {
      return;
    }
    await store.insert(HISTORY_SYNC_RETENTION_TABLE, {
      account_uid: accountUid,
      cutoff_at: merged.cutoffAt,
      boundary_visited_at: merged.boundaryVisitedAt,
      boundary_visit_id: merged.boundaryVisitId,
      updated_at: merged.updatedAt
    }, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  private async advanceHistorySyncRetentionForVictims(
    store: relationalStore.RdbStore,
    accountUid: string,
    allVisits: HistoryVisit[],
    victims: HistoryVisit[],
    cutoff: number,
    now: number
  ): Promise<void> {
    const roundedCutoff = Math.floor(Math.max(0, cutoff) / HISTORY_SYNC_RETENTION_FRONTIER_GRANULARITY_MS) *
      HISTORY_SYNC_RETENTION_FRONTIER_GRANULARITY_MS;
    const boundary = allVisits.length > HISTORY_SYNC_MAX_VISITS
      ? allVisits[HISTORY_SYNC_MAX_VISITS - 1]
      : undefined;
    await this.persistHistorySyncRetentionFrontier(store, accountUid, {
      cutoffAt: roundedCutoff,
      boundaryVisitedAt: boundary?.visitedAt ?? 0,
      boundaryVisitId: (boundary?.syncId ?? '').trim(),
      updatedAt: now
    });
    for (const victim of victims) {
      const syncId = (victim.syncId ?? '').trim();
      if (syncId.length > 0) {
        await this.deleteHistorySyncCanonicalVisit(store, accountUid, syncId);
      }
    }
    const tombstonePredicates = new relationalStore.RdbPredicates(HISTORY_SYNC_TOMBSTONES_TABLE);
    tombstonePredicates.equalTo('account_uid', accountUid);
    tombstonePredicates.lessThan('deleted_at', roundedCutoff);
    await store.delete(tombstonePredicates);
  }

  private async advanceHistorySyncRetentionFromRemotePrune(
    store: relationalStore.RdbStore,
    accountUid: string,
    cutoff: number
  ): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    predicates.equalTo('sync_account_uid', accountUid.trim());
    predicates.equalTo('data_scope', 'profile_persistent');
    predicates.orderByDesc('visited_at');
    predicates.orderByDesc('sync_id');
    predicates.limitAs(HISTORY_SYNC_MAX_VISITS);
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    const visits = this.mapHistoryVisitEventRows(resultSet);
    const boundary = visits.length >= HISTORY_SYNC_MAX_VISITS
      ? visits[HISTORY_SYNC_MAX_VISITS - 1]
      : undefined;
    const roundedCutoff = Math.floor(Math.max(0, cutoff) / HISTORY_SYNC_RETENTION_FRONTIER_GRANULARITY_MS) *
      HISTORY_SYNC_RETENTION_FRONTIER_GRANULARITY_MS;
    await this.persistHistorySyncRetentionFrontier(store, accountUid, {
      cutoffAt: roundedCutoff,
      boundaryVisitedAt: boundary?.visitedAt ?? 0,
      boundaryVisitId: (boundary?.syncId ?? '').trim(),
      updatedAt: Math.max(roundedCutoff, boundary?.visitedAt ?? 0)
    });
  }

  private async deleteHistoryVisitsBehindRetentionFrontierInStore(
    store: relationalStore.RdbStore,
    accountUid: string,
    frontier: HistorySyncRetentionFrontier
  ): Promise<number> {
    if (frontier.cutoffAt <= 0 && frontier.boundaryVisitedAt <= 0) {
      return 0;
    }
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    predicates.equalTo('sync_account_uid', accountUid);
    predicates.equalTo('data_scope', 'profile_persistent');
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    const visits = await this.hydrateHistoryVisits(this.mapHistoryVisitEventRows(resultSet));
    const victims = visits.filter((visit: HistoryVisit): boolean => {
      const syncId = (visit.syncId ?? '').trim();
      if (syncId.length <= 0 || visit.visitedAt < frontier.cutoffAt) {
        return syncId.length > 0 && visit.visitedAt < frontier.cutoffAt;
      }
      return frontier.boundaryVisitedAt > 0 &&
        (visit.visitedAt < frontier.boundaryVisitedAt ||
          (visit.visitedAt === frontier.boundaryVisitedAt &&
            syncId.localeCompare(frontier.boundaryVisitId) < 0));
    });
    for (const victim of victims) {
      const syncId = (victim.syncId ?? '').trim();
      if (syncId.length > 0) {
        await this.deleteHistorySyncCanonicalVisit(store, accountUid, syncId);
      }
    }
    return this.deleteHydratedHistoryVisitEvents(store, victims);
  }

  private async upsertHistorySyncState(
    store: relationalStore.RdbStore,
    state: HistorySyncLocalState
  ): Promise<void> {
    await store.batchInsertWithConflictResolution(
      HISTORY_SYNC_STATE_TABLE,
      [{
        account_uid: state.accountUid,
        client_id: state.clientId,
        initialized: state.initialized ? 1 : 0,
        cursor: state.cursor,
        bootstrap_head: state.bootstrapHead,
        bootstrap_after_updated_seq: state.bootstrapAfterUpdatedSeq,
        bootstrap_after_visit_id: state.bootstrapAfterVisitId,
        updated_at: state.updatedAt
      }],
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
    );
  }

  private async deleteRemoteHistoryProjectionInStore(
    store: relationalStore.RdbStore,
    accountUid: string
  ): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    predicates.equalTo('sync_account_uid', accountUid);
    predicates.equalTo('sync_origin', 'remote');
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    return this.deleteHydratedHistoryVisitEvents(store, this.mapHistoryVisitEventRows(resultSet));
  }

  private parseHistorySyncMutation(value: string): HistorySyncMutation | undefined {
    try {
      const mutation = JSON.parse(value) as HistorySyncMutation;
      return mutation.mutationId.trim().length > 0 ? mutation : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private buildHistorySyncVisitId(clientId: string, nativeVisitId: string): string {
    return `h1:${clientId.trim()}:${nativeVisitId.trim()}`;
  }

  private createHistorySyncMutationId(clientId: string, kind: string): string {
    const timestamp = Date.now().toString(36);
    const random = Math.floor(Math.random() * 0x100000000).toString(36);
    return `h1m_${clientId.trim()}_${kind}_${timestamp}_${random}`;
  }

  private rollbackHistoryTransaction(
    store: relationalStore.RdbStore | undefined,
    transactionStarted: boolean
  ): void {
    if (!transactionStarted || store === undefined) {
      return;
    }
    try {
      store.rollBack();
    } catch (_error) {
    }
  }

  private async upsertHistoryUrlRecord(
    store: relationalStore.RdbStore,
    visit: HistoryVisit
  ): Promise<HistoryUrlRecord> {
    const now = Date.now();
    const normalizedUrl = this.normalizeHistoryUrl(visit.url);
    const urlHash = this.hashHistoryUrl(normalizedUrl);
    const existing = await this.findHistoryUrlByHash(store, urlHash);
    const title = this.resolveHistoryTitle(visit.title, visit.url);
    const isTyped = visit.transition === 'typed';
    if (existing !== undefined) {
      const updated: HistoryUrlRecord = {
        id: existing.id,
        url: visit.url,
        normalizedUrl: normalizedUrl,
        urlHash: urlHash,
        origin: this.resolveHistoryOrigin(normalizedUrl),
        host: this.resolveHistoryHost(normalizedUrl),
        title: title.length > 0 ? title : existing.title,
        visitCount: existing.visitCount + 1,
        typedCount: existing.typedCount + (isTyped ? 1 : 0),
        lastVisitAt: Math.max(existing.lastVisitAt, visit.visitedAt),
        hidden: existing.hidden,
        faviconKey: existing.faviconKey,
        createdAt: existing.createdAt,
        updatedAt: now
      };
      await store.update(this.toHistoryUrlValues(updated), this.createHistoryUrlIdPredicates(updated.id));
      return updated;
    }
    const created: HistoryUrlRecord = {
      id: this.createHistoryUrlId(urlHash),
      url: visit.url,
      normalizedUrl: normalizedUrl,
      urlHash: urlHash,
      origin: this.resolveHistoryOrigin(normalizedUrl),
      host: this.resolveHistoryHost(normalizedUrl),
      title: title,
      visitCount: 1,
      typedCount: isTyped ? 1 : 0,
      lastVisitAt: visit.visitedAt,
      hidden: false,
      faviconKey: this.resolveHistoryHost(normalizedUrl),
      createdAt: now,
      updatedAt: now
    };
    // Keep the duplicate decision inside SQLite because transaction-local reads
    // may not observe a URL inserted earlier in the same remote-change batch.
    await store.executeSql(
      `INSERT OR IGNORE INTO ${HISTORY_URLS_TABLE} ` +
        `(${HISTORY_URL_COLUMNS.join(',')}) VALUES (` +
        `${this.quoteSql(created.id)},${this.quoteSql(created.url)},${this.quoteSql(created.normalizedUrl)},` +
        `${this.quoteSql(created.urlHash)},${this.quoteSql(created.origin)},${this.quoteSql(created.host)},` +
        `${this.quoteSql(created.title)},0,0,0,` +
        `${created.hidden ? 1 : 0},${this.quoteSql(created.faviconKey)},${created.createdAt},${created.updatedAt})`
    );
    await store.executeSql(
      `UPDATE ${HISTORY_URLS_TABLE} SET ` +
        `url = ${this.quoteSql(created.url)}, ` +
        `normalized_url = ${this.quoteSql(created.normalizedUrl)}, ` +
        `origin = ${this.quoteSql(created.origin)}, ` +
        `host = ${this.quoteSql(created.host)}, ` +
        `title = ${this.quoteSql(created.title)}, ` +
        `visit_count = visit_count + 1, ` +
        `typed_count = typed_count + ${created.typedCount}, ` +
        `last_visit_at = MAX(last_visit_at, ${created.lastVisitAt}), ` +
        `updated_at = ${created.updatedAt} ` +
        `WHERE id = ${this.quoteSql(created.id)} AND url_hash = ${this.quoteSql(created.urlHash)}`
    );
    return created;
  }

  private async recalculateHistoryUrlAggregate(store: relationalStore.RdbStore, urlId: string): Promise<void> {
    const existing = await this.findHistoryUrlById(store, urlId);
    if (existing === undefined) {
      return;
    }
    const predicates = this.createHistoryVisitsByUrlIdPredicates(urlId);
    predicates.orderByDesc('visited_at');
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    const visits = this.mapHistoryVisitEventRows(resultSet);
    if (visits.length === 0) {
      await store.delete(this.createHistoryUrlIdPredicates(urlId));
      return;
    }
    const latest = visits[0];
    const typedCount = visits.filter((visit: HistoryVisit) => visit.transition === 'typed').length;
    const updated: HistoryUrlRecord = {
      id: existing.id,
      url: existing.url,
      normalizedUrl: existing.normalizedUrl,
      urlHash: existing.urlHash,
      origin: existing.origin,
      host: existing.host,
      title: existing.title,
      visitCount: visits.length,
      typedCount: typedCount,
      lastVisitAt: latest.visitedAt,
      hidden: existing.hidden,
      faviconKey: existing.faviconKey,
      createdAt: existing.createdAt,
      updatedAt: Date.now()
    };
    await store.update(this.toHistoryUrlValues(updated), this.createHistoryUrlIdPredicates(urlId));
  }

  private async findHistoryVisitEventById(
    store: relationalStore.RdbStore,
    id: string
  ): Promise<HistoryVisit | undefined> {
    const predicates = this.createHistoryVisitIdPredicates(id);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    return this.mapHistoryVisitEventRows(resultSet)[0];
  }

  private async findHistoryVisitEventsByUrlId(
    store: relationalStore.RdbStore,
    urlId: string
  ): Promise<HistoryVisit[]> {
    const predicates = this.createHistoryVisitsByUrlIdPredicates(urlId);
    predicates.orderByDesc('visited_at');
    const resultSet = await store.query(predicates, HISTORY_VISIT_COLUMNS);
    return this.mapHistoryVisitEventRows(resultSet);
  }

  private async countHistoryVisits(store: relationalStore.RdbStore): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(HISTORY_VISITS_TABLE);
    const resultSet = await store.query(predicates, ['id']);
    const count = resultSet.rowCount;
    try {
      resultSet.close();
    } catch (closeError) {
      hilog.warn(DOMAIN, TAG, 'Failed to close history count result set: %{public}s', JSON.stringify(closeError));
    }
    return count;
  }

  private buildHistoryStressUrlInsertSql(start: number, end: number, now: number): string {
    const values: string[] = [];
    for (let index = start; index < end; index += 1) {
      const normalizedUrl = `https://stress-history.aira.local/item/${index}?bucket=${index % 100}`;
      const urlHash = this.hashHistoryUrl(normalizedUrl);
      const id = `${HISTORY_STRESS_URL_ID_PREFIX}${index}`;
      const title = `历史压测记录 ${index + 1}`;
      const host = 'stress-history.aira.local';
      values.push(`(${this.quoteSql(id)},${this.quoteSql(normalizedUrl)},${this.quoteSql(normalizedUrl)},` +
        `${this.quoteSql(urlHash)},${this.quoteSql('https://stress-history.aira.local')},${this.quoteSql(host)},` +
        `${this.quoteSql(title)},1,${index % 17 === 0 ? 1 : 0},${now - index * 60000},0,` +
        `${this.quoteSql(host)},${now},${now})`);
    }
    return `INSERT OR REPLACE INTO ${HISTORY_URLS_TABLE} (${HISTORY_URL_COLUMNS.join(',')}) VALUES ${values.join(',')}`;
  }

  private buildHistoryStressVisitInsertSql(start: number, end: number, now: number): string {
    const values: string[] = [];
    for (let index = start; index < end; index += 1) {
      values.push(`(${this.quoteSql(`${HISTORY_STRESS_VISIT_ID_PREFIX}${index}`)},` +
        `${this.quoteSql(`${HISTORY_STRESS_URL_ID_PREFIX}${index}`)},${now - index * 60000},NULL,` +
        `${this.quoteSql(index % 17 === 0 ? 'typed' : 'link')},${(index % 11) * 1000},${this.quoteSql('local')},` +
        `${this.quoteSql('stress-device')},${this.quoteSql(`stress-session-${Math.floor(index / 50)}`)},` +
        `${this.quoteSql('profile-main')},${this.quoteSql('profile_persistent')},` +
        `${this.quoteSql('')},${this.quoteSql('')},${this.quoteSql('')})`);
    }
    return `INSERT OR REPLACE INTO ${HISTORY_VISITS_TABLE} (${HISTORY_VISIT_COLUMNS.join(',')}) VALUES ${values.join(',')}`;
  }

  private quoteSql(value: string): string {
    return `'${value.replace(/'/g, "''")}'`;
  }

  private async deleteHydratedHistoryVisitEvents(
    store: relationalStore.RdbStore,
    visits: HistoryVisit[]
  ): Promise<number> {
    let removed = 0;
    const affectedUrlIds = new Set<string>();
    for (const visit of visits) {
      removed += await store.delete(this.createHistoryVisitIdPredicates(visit.id));
      if (visit.urlId !== undefined && visit.urlId.length > 0) {
        affectedUrlIds.add(visit.urlId);
      }
    }
    for (const urlId of Array.from(affectedUrlIds)) {
      await this.recalculateHistoryUrlAggregate(store, urlId);
    }
    return removed;
  }

  private async findHistoryUrlById(
    store: relationalStore.RdbStore,
    id: string
  ): Promise<HistoryUrlRecord | undefined> {
    const predicates = this.createHistoryUrlIdPredicates(id);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, HISTORY_URL_COLUMNS);
    return this.mapHistoryUrlRows(resultSet)[0];
  }

  private async findHistoryUrlByHash(
    store: relationalStore.RdbStore,
    urlHash: string
  ): Promise<HistoryUrlRecord | undefined> {
    const predicates = this.createHistoryUrlHashPredicates(urlHash);
    predicates.limitAs(1);
    const resultSet = await store.query(predicates, HISTORY_URL_COLUMNS);
    return this.mapHistoryUrlRows(resultSet)[0];
  }

  private normalizeHistoryUrl(url: string): string {
    const trimmed = url.trim();
    const lower = trimmed.toLowerCase();
    if (lower.endsWith('/') && lower.indexOf('?') < 0 && lower.indexOf('#') < 0) {
      return lower.substring(0, lower.length - 1);
    }
    return lower;
  }

  private normalizeHistorySyncUrl(url: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(url.trim());
      const protocol = parsed.protocol.trim().toLowerCase();
      if ((protocol !== 'http:' && protocol !== 'https:') || parsed.hostname.trim().length <= 0) {
        return '';
      }
      return parsed.href;
    } catch (_error) {
      return '';
    }
  }

  private resolveHistoryTitle(title: string, url: string): string {
    const trimmed = title.trim();
    if (trimmed.length > 0 && trimmed !== '页面加载中') {
      return trimmed;
    }
    return url.trim();
  }

  private resolveHistoryOrigin(normalizedUrl: string): string {
    const protocolMarker = normalizedUrl.indexOf('://');
    if (protocolMarker < 0) {
      return '';
    }
    const afterProtocol = protocolMarker + 3;
    const pathStart = normalizedUrl.indexOf('/', afterProtocol);
    return pathStart < 0 ? normalizedUrl : normalizedUrl.substring(0, pathStart);
  }

  private resolveHistoryHost(normalizedUrl: string): string {
    const origin = this.resolveHistoryOrigin(normalizedUrl);
    const protocolMarker = origin.indexOf('://');
    const hostWithPort = protocolMarker < 0 ? origin : origin.substring(protocolMarker + 3);
    const portStart = hostWithPort.indexOf(':');
    return portStart < 0 ? hostWithPort : hostWithPort.substring(0, portStart);
  }

  private hashHistoryUrl(normalizedUrl: string): string {
    let hash = 2166136261;
    for (let index = 0; index < normalizedUrl.length; index += 1) {
      hash = (hash ^ normalizedUrl.charCodeAt(index)) * 16777619;
      hash = hash >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
  }

  private createHistoryUrlId(urlHash: string): string {
    return `history-url-${urlHash}`;
  }

  private mapOfflinePageRows(resultSet: relationalStore.ResultSet): OfflinePageRecord[] {
    const pages: OfflinePageRecord[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const originalUrlIndex = resultSet.getColumnIndex('original_url');
      const normalizedUrlIndex = resultSet.getColumnIndex('normalized_url');
      const urlHashIndex = resultSet.getColumnIndex('url_hash');
      const titleIndex = resultSet.getColumnIndex('title');
      const siteNameIndex = resultSet.getColumnIndex('site_name');
      const hostIndex = resultSet.getColumnIndex('host');
      const savedAtIndex = resultSet.getColumnIndex('saved_at');
      const updatedAtIndex = resultSet.getColumnIndex('updated_at');
      const snapshotPathIndex = resultSet.getColumnIndex('snapshot_path');
      const manifestPathIndex = resultSet.getColumnIndex('manifest_path');
      const previewImageUriIndex = resultSet.getColumnIndex('preview_image_uri');
      const faviconUriIndex = resultSet.getColumnIndex('favicon_uri');
      const totalBytesIndex = resultSet.getColumnIndex('total_bytes');
      const resourceCountIndex = resultSet.getColumnIndex('resource_count');
      const failedResourceCountIndex = resultSet.getColumnIndex('failed_resource_count');
      const saveStatusIndex = resultSet.getColumnIndex('save_status');
      const openStatusIndex = resultSet.getColumnIndex('open_status');

      while (resultSet.goToNextRow()) {
        pages.push({
          id: resultSet.getString(idIndex),
          originalUrl: resultSet.getString(originalUrlIndex),
          normalizedUrl: resultSet.getString(normalizedUrlIndex),
          urlHash: resultSet.getString(urlHashIndex),
          title: resultSet.getString(titleIndex),
          siteName: resultSet.getString(siteNameIndex),
          host: resultSet.getString(hostIndex),
          savedAt: resultSet.getLong(savedAtIndex),
          updatedAt: resultSet.getLong(updatedAtIndex),
          snapshotPath: resultSet.getString(snapshotPathIndex),
          manifestPath: resultSet.getString(manifestPathIndex),
          previewImageUri: this.readOptionalString(resultSet, previewImageUriIndex),
          faviconUri: this.readOptionalString(resultSet, faviconUriIndex),
          totalBytes: resultSet.getLong(totalBytesIndex),
          resourceCount: resultSet.getLong(resourceCountIndex),
          failedResourceCount: resultSet.getLong(failedResourceCountIndex),
          saveStatus: this.normalizeOfflinePageSaveStatus(resultSet.getString(saveStatusIndex)),
          openStatus: this.normalizeOfflinePageOpenStatus(resultSet.getString(openStatusIndex))
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map offline page rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close offline page result set: %{public}s', JSON.stringify(closeError));
      }
    }

    return pages;
  }

  private mapSingleOfflinePageRow(resultSet: relationalStore.ResultSet): OfflinePageRecord | undefined {
    const pages = this.mapOfflinePageRows(resultSet);
    return pages.length > 0 ? pages[0] : undefined;
  }

  private toOfflinePageValues(record: OfflinePageRecord): relationalStore.ValuesBucket {
    return {
      id: record.id,
      original_url: record.originalUrl,
      normalized_url: record.normalizedUrl,
      url_hash: record.urlHash,
      title: record.title,
      site_name: record.siteName,
      host: record.host,
      saved_at: record.savedAt,
      updated_at: record.updatedAt,
      snapshot_path: record.snapshotPath,
      manifest_path: record.manifestPath,
      preview_image_uri: record.previewImageUri.length > 0 ? record.previewImageUri : null,
      favicon_uri: record.faviconUri.length > 0 ? record.faviconUri : null,
      total_bytes: record.totalBytes,
      resource_count: record.resourceCount,
      failed_resource_count: record.failedResourceCount,
      save_status: record.saveStatus,
      open_status: record.openStatus
    };
  }

  private normalizeOfflinePageSaveStatus(value: string): OfflinePageSaveStatus {
    if (value === 'saving' || value === 'saved' || value === 'partial_saved' || value === 'failed') {
      return value;
    }
    return 'failed';
  }

  private normalizeOfflinePageOpenStatus(value: string): OfflinePageOpenStatus {
    if (value === 'available' || value === 'missing_snapshot' || value === 'missing_assets' || value === 'corrupted') {
      return value;
    }
    return 'corrupted';
  }

  private mapTabRows(resultSet: relationalStore.ResultSet): TabRecord[] {
    const tabs: TabRecord[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const windowIdIndex = resultSet.getColumnIndex('window_id');
      const profileIdIndex = resultSet.getColumnIndex('profile_id');
      const titleIndex = resultSet.getColumnIndex('title');
      const urlIndex = resultSet.getColumnIndex('url');
      const isActiveIndex = resultSet.getColumnIndex('is_active');
      const isPinnedIndex = resultSet.getColumnIndex('is_pinned');
      const lastActiveAtIndex = resultSet.getColumnIndex('last_active_at');
      const tabOrderIndex = resultSet.getColumnIndex('tab_order');
      const isHomeIndex = resultSet.getColumnIndex('is_home');
      const pendingUrlIndex = resultSet.getColumnIndex('pending_url');
      const navigationHistoryIndex = resultSet.getColumnIndex('navigation_history');
      const navigationIndexIndex = resultSet.getColumnIndex('navigation_index');
      const runtimeStateIndex = resultSet.getColumnIndex('runtime_state');
      const lastErrorIndex = resultSet.getColumnIndex('last_error');
      const lastLoadedAtIndex = resultSet.getColumnIndex('last_loaded_at');
      const webStatePathIndex = resultSet.getColumnIndex('web_state_path');
      const webStateUpdatedAtIndex = resultSet.getColumnIndex('web_state_updated_at');
      const scrollOffsetYIndex = resultSet.getColumnIndex('scroll_offset_y');
      const lastGoodUrlIndex = resultSet.getColumnIndex('last_good_url');
      const lastGoodTitleIndex = resultSet.getColumnIndex('last_good_title');
      const lastRestorableUrlIndex = resultSet.getColumnIndex('last_restorable_url');
      const lastRestorableTitleIndex = resultSet.getColumnIndex('last_restorable_title');
      const lastRestoreTypeIndex = resultSet.getColumnIndex('last_restore_type');
      const lastRestoreReasonIndex = resultSet.getColumnIndex('last_restore_reason');
      const lastDiscardReasonIndex = resultSet.getColumnIndex('last_discard_reason');
      const lastCrashReasonIndex = resultSet.getColumnIndex('last_crash_reason');
      const privacyModeIndex = resultSet.getColumnIndex('privacy_mode');
      const dataScopeIndex = resultSet.getColumnIndex('data_scope');
      const launchSourceTypeIndex = resultSet.getColumnIndex('launch_source_type');
      const launchSourceIdIndex = resultSet.getColumnIndex('launch_source_id');
      const launchSourceUrlIndex = resultSet.getColumnIndex('launch_source_url');
      const launchKeyIndex = resultSet.getColumnIndex('launch_key');

      while (resultSet.goToNextRow()) {
        tabs.push({
          id: resultSet.getString(idIndex),
          windowId: resultSet.getString(windowIdIndex),
          profileId: this.readOptionalString(resultSet, profileIdIndex) as 'profile-main',
          title: resultSet.getString(titleIndex),
          url: resultSet.getString(urlIndex),
          isActive: resultSet.getLong(isActiveIndex) === 1,
          isPinned: resultSet.getLong(isPinnedIndex) === 1,
          lastActiveAt: resultSet.getLong(lastActiveAtIndex),
          tabOrder: resultSet.getLong(tabOrderIndex),
          isHome: resultSet.getLong(isHomeIndex) === 1,
          pendingUrl: this.readOptionalString(resultSet, pendingUrlIndex),
          navigationHistory: this.parseNavigationHistory(this.readOptionalString(resultSet, navigationHistoryIndex)),
          navigationIndex: resultSet.getLong(navigationIndexIndex),
          runtimeState: this.readOptionalString(resultSet, runtimeStateIndex) as
            'active' | 'background' | 'background-hot' | 'background-warm' | 'suspended' | 'cold' | 'discarded' |
            'loading' | 'error' | 'restoring' | 'crashed',
          lastError: this.readOptionalString(resultSet, lastErrorIndex),
          lastLoadedAt: resultSet.getLong(lastLoadedAtIndex),
          webStatePath: this.readOptionalString(resultSet, webStatePathIndex),
          webStateUpdatedAt: resultSet.getLong(webStateUpdatedAtIndex),
          scrollOffsetY: resultSet.getLong(scrollOffsetYIndex),
          lastGoodUrl: this.readOptionalString(resultSet, lastGoodUrlIndex),
          lastGoodTitle: this.readOptionalString(resultSet, lastGoodTitleIndex),
          lastRestorableUrl: this.readOptionalString(resultSet, lastRestorableUrlIndex),
          lastRestorableTitle: this.readOptionalString(resultSet, lastRestorableTitleIndex),
          lastRestoreType: this.readOptionalString(resultSet, lastRestoreTypeIndex) as
            'none' | 'live_page_cache' | 'snapshot_restore' | 'reload',
          lastRestoreReason: this.readOptionalString(resultSet, lastRestoreReasonIndex) as
            'cold_start' | 'controller_attach' | 'tab_switch' | 'discard_restore' | 'crash_restore' |
            'snapshot_restore' | 'snapshot_fallback_reload' | 'manual_reload' | 'external_launch',
          lastDiscardReason: this.readOptionalString(resultSet, lastDiscardReasonIndex) as
            'retention_cold' | 'retention_budget' | 'retention_stale' | 'manual_home' | 'controller_detached',
          lastCrashReason: this.readOptionalString(resultSet, lastCrashReasonIndex) as
            'main_frame_error' | 'snapshot_restore_failed' | 'navigation_failed' | 'render_process_terminated' |
            'recovery_degraded_to_home' | 'unknown',
          privacyMode: this.readOptionalString(resultSet, privacyModeIndex) as 'regular' | 'private',
          dataScope: this.readOptionalString(resultSet, dataScopeIndex) as 'profile_persistent' | 'session_ephemeral',
          launchSourceType: this.readOptionalString(resultSet, launchSourceTypeIndex),
          launchSourceId: this.readOptionalString(resultSet, launchSourceIdIndex),
          launchSourceUrl: this.readOptionalString(resultSet, launchSourceUrlIndex),
          launchKey: this.readOptionalString(resultSet, launchKeyIndex)
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map tab session rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close tab session result set: %{public}s', JSON.stringify(closeError));
      }
    }

    return tabs;
  }

  private toTabValues(tab: TabRecord): relationalStore.ValuesBucket {
    return {
      id: tab.id,
      window_id: tab.windowId,
      profile_id: tab.profileId ?? 'profile-main',
      title: tab.title,
      url: tab.url,
      is_active: tab.isActive ? 1 : 0,
      is_pinned: tab.isPinned ? 1 : 0,
      last_active_at: tab.lastActiveAt,
      tab_order: tab.tabOrder ?? 0,
      is_home: tab.isHome === true ? 1 : 0,
      pending_url: tab.pendingUrl ?? null,
      navigation_history: JSON.stringify(tab.navigationHistory ?? []),
      navigation_index: tab.navigationIndex ?? -1,
      runtime_state: tab.runtimeState ?? 'background',
      last_error: tab.lastError ?? null,
      last_loaded_at: tab.lastLoadedAt ?? 0,
      web_state_path: tab.webStatePath ?? null,
      web_state_updated_at: tab.webStateUpdatedAt ?? 0,
      scroll_offset_y: tab.scrollOffsetY ?? 0,
      last_good_url: tab.lastGoodUrl ?? null,
      last_good_title: tab.lastGoodTitle ?? null,
      last_restorable_url: tab.lastRestorableUrl ?? null,
      last_restorable_title: tab.lastRestorableTitle ?? null,
      last_restore_type: tab.lastRestoreType ?? 'none',
      last_restore_reason: tab.lastRestoreReason ?? null,
      last_discard_reason: tab.lastDiscardReason ?? null,
      last_crash_reason: tab.lastCrashReason ?? null,
      privacy_mode: tab.privacyMode ?? 'regular',
      data_scope: tab.dataScope ?? 'profile_persistent',
      launch_source_type: tab.launchSourceType ?? null,
      launch_source_id: tab.launchSourceId ?? null,
      launch_source_url: tab.launchSourceUrl ?? null,
      launch_key: tab.launchKey ?? null
    };
  }

  private mapRecentlyClosedTabRows(resultSet: relationalStore.ResultSet): RecentlyClosedTabRecord[] {
    const records: RecentlyClosedTabRecord[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const originalTabIdIndex = resultSet.getColumnIndex('original_tab_id');
      const closedAtIndex = resultSet.getColumnIndex('closed_at');
      const windowIdIndex = resultSet.getColumnIndex('window_id');
      const profileIdIndex = resultSet.getColumnIndex('profile_id');
      const siteIconUriIndex = resultSet.getColumnIndex('site_icon_uri');
      const tabPayloadIndex = resultSet.getColumnIndex('tab_payload');

      while (resultSet.goToNextRow()) {
        const payload = this.parseRecentlyClosedTabPayload(this.readOptionalString(resultSet, tabPayloadIndex));
        if (payload === undefined) {
          continue;
        }
        records.push({
          id: resultSet.getString(idIndex),
          originalTabId: resultSet.getString(originalTabIdIndex),
          closedAt: resultSet.getLong(closedAtIndex),
          windowId: resultSet.getString(windowIdIndex),
          profileId: this.readOptionalString(resultSet, profileIdIndex) as 'profile-main',
          siteIconUri: this.readOptionalString(resultSet, siteIconUriIndex),
          tab: payload
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map recently closed tab rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close recently closed result set: %{public}s', JSON.stringify(closeError));
      }
    }

    return records;
  }

  private toRecentlyClosedTabValues(record: RecentlyClosedTabRecord): relationalStore.ValuesBucket {
    return {
      id: record.id,
      original_tab_id: record.originalTabId,
      closed_at: record.closedAt,
      window_id: record.windowId,
      profile_id: record.profileId ?? record.tab.profileId ?? 'profile-main',
      site_icon_uri: (record.siteIconUri ?? '').trim().length > 0 ? (record.siteIconUri ?? '').trim() : null,
      tab_payload: JSON.stringify(record.tab)
    };
  }

  private normalizeRecentlyClosedReplacementRecords(
    records: RecentlyClosedTabRecord[],
    windowId: string,
    profileId?: string
  ): RecentlyClosedTabRecord[] {
    const normalizedProfileId = typeof profileId === 'string' ? profileId.trim() : '';
    const seenIds: string[] = [];
    return records
      .filter((record: RecentlyClosedTabRecord): boolean => record.id.trim().length > 0 && record.windowId === windowId)
      .filter((record: RecentlyClosedTabRecord): boolean => {
        if (normalizedProfileId.length <= 0) {
          return true;
        }
        const recordProfileId = record.profileId ?? record.tab.profileId ?? 'profile-main';
        return recordProfileId === normalizedProfileId;
      })
      .sort((left: RecentlyClosedTabRecord, right: RecentlyClosedTabRecord): number => {
        if (right.closedAt !== left.closedAt) {
          return right.closedAt - left.closedAt;
        }
        return right.id.localeCompare(left.id);
      })
      .filter((record: RecentlyClosedTabRecord): boolean => {
        const id = record.id.trim();
        if (seenIds.indexOf(id) >= 0) {
          return false;
        }
        seenIds.push(id);
        return true;
      });
  }

  private async upsertRecentlyClosedTabRecord(
    store: relationalStore.RdbStore,
    record: RecentlyClosedTabRecord
  ): Promise<void> {
    const values = this.toRecentlyClosedTabValues(record);
    const predicates = this.createRecentlyClosedIdPredicates(record.id);
    const updated = await store.update(values, predicates);
    if (updated > 0) {
      return;
    }
    try {
      await store.insert(RECENTLY_CLOSED_TABS_TABLE, values);
    } catch (error) {
      const retriedUpdate = await store.update(values, this.createRecentlyClosedIdPredicates(record.id));
      if (retriedUpdate > 0) {
        return;
      }
      throw new Error(`Failed to upsert recently closed tab record: ${this.describeError(error as Error)}`);
    }
  }

  private rollbackRecentlyClosedTransaction(
    store: relationalStore.RdbStore | undefined,
    transactionStarted: boolean
  ): void {
    if (store === undefined || !transactionStarted) {
      return;
    }
    try {
      store.rollBack();
    } catch (rollbackError) {
      hilog.warn(DOMAIN, TAG, 'Failed to rollback recently closed transaction: %{public}s', JSON.stringify(rollbackError));
    }
  }

  private parseRecentlyClosedTabPayload(payload: string): TabRecord | undefined {
    if (payload.trim().length === 0) {
      return undefined;
    }
    try {
      const parsed = JSON.parse(payload) as Partial<TabRecord>;
      if (typeof parsed.id !== 'string' || typeof parsed.title !== 'string' || typeof parsed.url !== 'string') {
        return undefined;
      }
      return {
        id: parsed.id,
        windowId: typeof parsed.windowId === 'string' ? parsed.windowId : 'window-main',
        profileId: parsed.profileId,
        title: parsed.title,
        url: parsed.url,
        isActive: parsed.isActive === true,
        isPinned: parsed.isPinned === true,
        lastActiveAt: typeof parsed.lastActiveAt === 'number' ? parsed.lastActiveAt : Date.now(),
        tabOrder: parsed.tabOrder,
        isHome: parsed.isHome,
        pendingUrl: parsed.pendingUrl,
        navigationHistory: Array.isArray(parsed.navigationHistory)
          ? parsed.navigationHistory.filter((item: Object) => typeof item === 'string').map((item: Object) => item as string)
          : undefined,
        navigationIndex: parsed.navigationIndex,
        runtimeState: parsed.runtimeState,
        lastError: parsed.lastError,
        lastRestoreReason: parsed.lastRestoreReason,
        lastDiscardReason: parsed.lastDiscardReason,
        lastCrashReason: parsed.lastCrashReason,
        lastLoadedAt: parsed.lastLoadedAt,
        webStatePath: parsed.webStatePath,
        webStateUpdatedAt: parsed.webStateUpdatedAt,
        scrollOffsetY: parsed.scrollOffsetY,
        lastGoodUrl: parsed.lastGoodUrl,
        lastGoodTitle: parsed.lastGoodTitle,
        lastRestorableUrl: parsed.lastRestorableUrl,
        lastRestorableTitle: parsed.lastRestorableTitle,
        lastRestoreType: parsed.lastRestoreType,
        privacyMode: parsed.privacyMode,
        dataScope: parsed.dataScope,
        launchSourceType: parsed.launchSourceType,
        launchSourceId: parsed.launchSourceId,
        launchSourceUrl: parsed.launchSourceUrl,
        launchKey: parsed.launchKey,
        openerTabId: parsed.openerTabId,
        openSource: parsed.openSource,
        openedByNewWindow: parsed.openedByNewWindow
      };
    } catch (_error) {
      return undefined;
    }
  }

  private parseNavigationHistory(payload: string): string[] {
    if (payload.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(payload) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .filter((item: Object) => typeof item === 'string')
        .map((item: Object) => item as string);
    } catch (_error) {
      return [];
    }
  }

  private readOptionalString(resultSet: relationalStore.ResultSet, columnIndex: number): string {
    try {
      return resultSet.getString(columnIndex);
    } catch (_error) {
      return '';
    }
  }

  private mapShortcutScenarioRows(resultSet: relationalStore.ResultSet): ShortcutScenarioRecord[] {
    const scenarios: ShortcutScenarioRecord[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const nameIndex = resultSet.getColumnIndex('name');
      const colorIndex = resultSet.getColumnIndex('color');
      const iconIndex = resultSet.getColumnIndex('icon');
      const positionIndex = resultSet.getColumnIndex('position');
      const archivedIndex = resultSet.getColumnIndex('archived');
      const createdAtIndex = resultSet.getColumnIndex('created_at');
      const updatedAtIndex = resultSet.getColumnIndex('updated_at');
      const syncStateIndex = resultSet.getColumnIndex('sync_state');
      const syncSourceIndex = resultSet.getColumnIndex('sync_source');
      const lastModifiedAtIndex = resultSet.getColumnIndex('last_modified_at');
      const lastModifiedByIndex = resultSet.getColumnIndex('last_modified_by');
      const deviceIdIndex = resultSet.getColumnIndex('device_id');
      const originIdIndex = resultSet.getColumnIndex('origin_id');
      const deletedAtIndex = resultSet.getColumnIndex('deleted_at');

      while (resultSet.goToNextRow()) {
        scenarios.push({
          id: resultSet.getString(idIndex),
          name: resultSet.getString(nameIndex),
          color: resultSet.getString(colorIndex),
          icon: resultSet.getString(iconIndex),
          position: resultSet.getLong(positionIndex),
          archived: resultSet.getLong(archivedIndex) === 1,
          createdAt: resultSet.getLong(createdAtIndex),
          updatedAt: resultSet.getLong(updatedAtIndex),
          sync: {
            state: resultSet.getString(syncStateIndex) as 'local_only' | 'pending_push' | 'synced' | 'conflict',
            source: resultSet.getString(syncSourceIndex) as 'seed' | 'local' | 'chrome_import' | 'chrome_sync' | 'cloud_sync',
            lastModifiedAt: resultSet.getLong(lastModifiedAtIndex),
            lastModifiedBy: resultSet.getString(lastModifiedByIndex),
            deviceId: resultSet.getString(deviceIdIndex),
            originId: resultSet.isColumnNull(originIdIndex) ? undefined : resultSet.getString(originIdIndex),
            deletedAt: resultSet.isColumnNull(deletedAtIndex) ? undefined : resultSet.getLong(deletedAtIndex)
          }
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map shortcut scenario rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close shortcut scenario result set: %{public}s', JSON.stringify(closeError));
      }
    }

    return scenarios;
  }

  private toShortcutScenarioValues(scenario: ShortcutScenarioRecord): relationalStore.ValuesBucket {
    return {
      id: scenario.id,
      name: scenario.name,
      color: scenario.color,
      icon: scenario.icon,
      position: scenario.position,
      archived: scenario.archived ? 1 : 0,
      created_at: scenario.createdAt,
      updated_at: scenario.updatedAt,
      sync_state: scenario.sync.state,
      sync_source: scenario.sync.source,
      last_modified_at: scenario.sync.lastModifiedAt,
      last_modified_by: scenario.sync.lastModifiedBy,
      device_id: scenario.sync.deviceId,
      origin_id: scenario.sync.originId ?? null,
      deleted_at: scenario.sync.deletedAt ?? null
    };
  }

  private mapShortcutRows(resultSet: relationalStore.ResultSet): ShortcutRecord[] {
    const shortcuts: ShortcutRecord[] = [];
    try {
      const idIndex = resultSet.getColumnIndex('id');
      const scenarioIdIndex = resultSet.getColumnIndex('scenario_id');
      const titleIndex = resultSet.getColumnIndex('title');
      const urlIndex = resultSet.getColumnIndex('url');
      const kindIndex = resultSet.getColumnIndex('kind');
      const folderNameIndex = resultSet.getColumnIndex('folder_name');
      const positionIndex = resultSet.getColumnIndex('position');
      const iconIndex = resultSet.getColumnIndex('icon');
      const descriptionIndex = resultSet.getColumnIndex('description');
      const useOfficialIconIndex = resultSet.getColumnIndex('use_official_icon');
      const autoUseOfficialIconIndex = resultSet.getColumnIndex('auto_use_official_icon');
      const officialIconAvailableIndex = resultSet.getColumnIndex('official_icon_available_at_save');
      const officialIconColorOverrideIndex = resultSet.getColumnIndex('official_icon_color_override');
      const iconRenderingIndex = resultSet.getColumnIndex('icon_rendering');
      const iconColorIndex = resultSet.getColumnIndex('icon_color');
      const createdAtIndex = resultSet.getColumnIndex('created_at');
      const updatedAtIndex = resultSet.getColumnIndex('updated_at');
      const syncStateIndex = resultSet.getColumnIndex('sync_state');
      const syncSourceIndex = resultSet.getColumnIndex('sync_source');
      const lastModifiedAtIndex = resultSet.getColumnIndex('last_modified_at');
      const lastModifiedByIndex = resultSet.getColumnIndex('last_modified_by');
      const deviceIdIndex = resultSet.getColumnIndex('device_id');
      const originIdIndex = resultSet.getColumnIndex('origin_id');
      const deletedAtIndex = resultSet.getColumnIndex('deleted_at');

      while (resultSet.goToNextRow()) {
        const shortcut: ShortcutRecord = {
          id: resultSet.getString(idIndex),
          scenarioId: resultSet.getString(scenarioIdIndex),
          kind: resultSet.isColumnNull(kindIndex) ? undefined : resultSet.getString(kindIndex) as 'web' | 'system',
          title: resultSet.getString(titleIndex),
          url: resultSet.getString(urlIndex),
          folderName: resultSet.getString(folderNameIndex),
          position: resultSet.getLong(positionIndex),
          icon: resultSet.isColumnNull(iconIndex) ? undefined : resultSet.getString(iconIndex),
          description: resultSet.isColumnNull(descriptionIndex) ? undefined : resultSet.getString(descriptionIndex),
          useOfficialIcon: resultSet.isColumnNull(useOfficialIconIndex) ? undefined : resultSet.getLong(useOfficialIconIndex) === 1,
          autoUseOfficialIcon: resultSet.isColumnNull(autoUseOfficialIconIndex) ? undefined : resultSet.getLong(autoUseOfficialIconIndex) === 1,
          officialIconAvailableAtSave: resultSet.isColumnNull(officialIconAvailableIndex) ? undefined : resultSet.getLong(officialIconAvailableIndex) === 1,
          officialIconColorOverride: resultSet.isColumnNull(officialIconColorOverrideIndex) ? undefined : resultSet.getLong(officialIconColorOverrideIndex) === 1,
          iconRendering: resultSet.isColumnNull(iconRenderingIndex) ? undefined : resultSet.getString(iconRenderingIndex),
          iconColor: resultSet.isColumnNull(iconColorIndex) ? undefined : resultSet.getString(iconColorIndex),
          createdAt: resultSet.getLong(createdAtIndex),
          updatedAt: resultSet.getLong(updatedAtIndex),
          sync: {
            state: resultSet.getString(syncStateIndex) as 'local_only' | 'pending_push' | 'synced' | 'conflict',
            source: resultSet.getString(syncSourceIndex) as 'seed' | 'local' | 'chrome_import' | 'chrome_sync' | 'cloud_sync',
            lastModifiedAt: resultSet.getLong(lastModifiedAtIndex),
            lastModifiedBy: resultSet.getString(lastModifiedByIndex),
            deviceId: resultSet.getString(deviceIdIndex),
            originId: resultSet.isColumnNull(originIdIndex) ? undefined : resultSet.getString(originIdIndex),
            deletedAt: resultSet.isColumnNull(deletedAtIndex) ? undefined : resultSet.getLong(deletedAtIndex)
          }
        };
        shortcuts.push(shortcut);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to map shortcut rows: %{public}s', JSON.stringify(error));
      return [];
    } finally {
      try {
        resultSet.close();
      } catch (closeError) {
        hilog.warn(DOMAIN, TAG, 'Failed to close shortcut result set: %{public}s', JSON.stringify(closeError));
      }
    }

    return shortcuts;
  }

  private toShortcutValues(shortcut: ShortcutRecord): relationalStore.ValuesBucket {
    return {
      id: shortcut.id,
      scenario_id: shortcut.scenarioId ?? 'aira_default_scenario',
      title: shortcut.title,
      url: shortcut.url,
      folder_name: shortcut.folderName,
      position: shortcut.position,
      icon: shortcut.icon ?? null,
      description: shortcut.description ?? null,
      kind: shortcut.kind ?? null,
      children: null,
      folder_display_mode: null,
      use_official_icon: shortcut.useOfficialIcon === undefined ? null : shortcut.useOfficialIcon ? 1 : 0,
      auto_use_official_icon: shortcut.autoUseOfficialIcon === undefined ? null : shortcut.autoUseOfficialIcon ? 1 : 0,
      official_icon_available_at_save: shortcut.officialIconAvailableAtSave === undefined ? null : shortcut.officialIconAvailableAtSave ? 1 : 0,
      official_icon_color_override: shortcut.officialIconColorOverride === undefined ? null : shortcut.officialIconColorOverride ? 1 : 0,
      icon_rendering: shortcut.iconRendering ?? null,
      icon_color: shortcut.iconColor ?? null,
      created_at: shortcut.createdAt ?? Date.now(),
      updated_at: shortcut.updatedAt ?? Date.now(),
      sync_state: shortcut.sync?.state ?? 'pending_push',
      sync_source: shortcut.sync?.source ?? 'local',
      last_modified_at: shortcut.sync?.lastModifiedAt ?? Date.now(),
      last_modified_by: shortcut.sync?.lastModifiedBy ?? 'aira-shortcut-manager',
      device_id: shortcut.sync?.deviceId ?? 'aira-phone-local',
      origin_id: shortcut.sync?.originId ?? null,
      deleted_at: shortcut.sync?.deletedAt ?? null
    };
  }

  private resolveDayBucketLabel(visitedAt: number): string {
    const visitedDate = new Date(visitedAt);
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const visitedStart = new Date(visitedDate.getFullYear(), visitedDate.getMonth(), visitedDate.getDate()).getTime();
    const dayDiff = Math.floor((todayStart - visitedStart) / 86400000);
    if (dayDiff === 0) {
      return '今天';
    }
    if (dayDiff === 1) {
      return '昨天';
    }
    const month = `${visitedDate.getMonth() + 1}`.padStart(2, '0');
    const day = `${visitedDate.getDate()}`.padStart(2, '0');
    return `${visitedDate.getFullYear()}-${month}-${day}`;
  }
}
