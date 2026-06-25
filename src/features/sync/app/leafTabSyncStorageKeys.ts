export const LEAFTAB_SYNC_DEVICE_ID_KEY = 'leaftab_sync_v1_device_id';
export const LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY = 'leaftab_sync_v1_local_summary_at';
export const LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY = 'leaftab_primary_sync_remote_kind';
export const LEAFTAB_BOOKMARK_AUTO_SYNC_ENABLED_KEY = 'leaftab_bookmark_auto_sync_enabled';
export const AIRA_CLOUD_SYNC_ENABLED_KEY = 'aira_cloud_bookmark_sync_enabled';
export const AIRA_CLOUD_LAST_SYNC_AT_KEY = 'aira_cloud_last_sync_at';
export const AIRA_CLOUD_LAST_ERROR_AT_KEY = 'aira_cloud_last_error_at';
export const AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY = 'aira_cloud_last_error_message';

export const LEAFTAB_BACKGROUND_STORAGE_KEYS = {
  pendingLocalChangedAt: 'leaftab_background_pending_local_changed_at',
  lastRemoteProbeAt: 'leaftab_background_last_remote_probe_at',
  nextRemoteProbeAt: 'leaftab_background_next_remote_probe_at',
  autoSyncRunning: 'leaftab_background_auto_sync_running',
  autoSyncLastError: 'leaftab_background_auto_sync_last_error',
  debugState: 'leaftab_background_debug_state',
} as const;
