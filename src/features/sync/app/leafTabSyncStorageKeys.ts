export const LEAFTAB_SYNC_DEVICE_ID_KEY = 'leaftab_sync_g2_device_id';
export const LEAFTAB_SYNC_DEFAULT_ROOT_PATH = 'aira/g2/bookmarks';
export const LEAFTAB_SELECTED_SYNC_SOURCE_KEY = 'leaftab_sync_g2_active_provider';
export const LEAFTAB_LEGACY_SELECTED_SYNC_SOURCE_KEY = 'leaftab_primary_sync_remote_kind';
export const LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY = 'leaftab_sync_g2_pending_bookmark_conflict';
export const AIRA_CLOUD_SYNC_ENABLED_KEY = 'aira_cloud_bookmark_sync_enabled';
export const AIRA_CLOUD_LAST_SYNC_AT_KEY = 'aira_cloud_bookmark_sync_g2_last_sync_at';
export const AIRA_CLOUD_LAST_ERROR_AT_KEY = 'aira_cloud_bookmark_sync_g2_last_error_at';
export const AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY = 'aira_cloud_bookmark_sync_g2_last_error_message';
export const WEBDAV_LAST_SYNC_AT_KEY = 'webdav_bookmark_sync_g2_last_sync_at';
export const WEBDAV_LAST_ERROR_AT_KEY = 'webdav_bookmark_sync_g2_last_error_at';
export const WEBDAV_LAST_ERROR_MESSAGE_KEY = 'webdav_bookmark_sync_g2_last_error_message';
export const AIRA_PHONE_PAGE_PUSH_ENABLED_KEY = 'aira_phone_page_push_enabled_v1';

export const createLeafTabSyncBaselineStorageKey = (
  remoteKind: 'aira-cloud' | 'webdav',
  rootPath: string = LEAFTAB_SYNC_DEFAULT_ROOT_PATH,
  uid: string = '',
): string => {
  const suffix = (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT_PATH).replace(/[^a-zA-Z0-9_-]+/g, '_');
  if (remoteKind === 'aira-cloud') {
    const safeUid = (uid || 'unknown').replace(/[^a-zA-Z0-9_-]+/g, '_');
    return `leaftab_sync_g2_baseline:aira_cloud:${safeUid}:${suffix}`;
  }
  return `leaftab_sync_g2_baseline:${suffix}`;
};

export const LEAFTAB_BACKGROUND_STORAGE_KEYS = {
  pendingLocalChangedAt: 'leaftab_sync_g2_background_pending_local_changed_at',
  lastRemoteProbeAt: 'leaftab_sync_g2_background_last_remote_probe_at',
  nextRemoteProbeAt: 'leaftab_sync_g2_background_next_remote_probe_at',
  autoSyncRunning: 'leaftab_sync_g2_background_auto_sync_running',
  autoSyncLastError: 'leaftab_sync_g2_background_auto_sync_last_error',
  autoSyncRetryProvider: 'leaftab_sync_g2_background_auto_sync_retry_provider',
  debugState: 'leaftab_sync_g2_background_debug_state',
} as const;
