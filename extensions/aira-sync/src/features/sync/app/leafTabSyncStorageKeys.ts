export const LEAFTAB_SYNC_DEVICE_ID_KEY = 'leaftab_sync_g2_device_id';
export const LEAFTAB_SYNC_DEVICE_ID_REQUEST_TYPE = 'AIRA_LEAFTAB_SYNC_G2_DEVICE_ID';
export const LEAFTAB_SYNC_DEFAULT_ROOT_PATH = 'aira/g3/bookmarks';
export const LEAFTAB_BOOKMARK_MAPPING_KEY = 'leaftab_sync_g2_bookmark_mapping:roots:toolbar+other';
export const LEAFTAB_SELECTED_SYNC_SOURCE_KEY = 'leaftab_sync_g2_active_provider';
export const LEAFTAB_SYNC_HISTORY_KEY = 'leaftab_sync_g3_confirmed_bookmark_history';
export const LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY = 'leaftab_sync_g3_pending_bookmark_conflict';
export const AIRA_CLOUD_LAST_SYNC_AT_KEY = 'aira_cloud_bookmark_sync_g3_last_sync_at';
export const AIRA_CLOUD_LAST_ERROR_AT_KEY = 'aira_cloud_bookmark_sync_g3_last_error_at';
export const AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY = 'aira_cloud_bookmark_sync_g3_last_error_message';
export const WEBDAV_LAST_SYNC_AT_KEY = 'webdav_bookmark_sync_g3_last_sync_at';
export const WEBDAV_LAST_ERROR_AT_KEY = 'webdav_bookmark_sync_g3_last_error_at';
export const WEBDAV_LAST_ERROR_MESSAGE_KEY = 'webdav_bookmark_sync_g3_last_error_message';
export const PERSONAL_SERVER_LAST_SYNC_AT_KEY = 'personal_server_bookmark_sync_g3_last_sync_at';
export const PERSONAL_SERVER_LAST_ERROR_AT_KEY = 'personal_server_bookmark_sync_g3_last_error_at';
export const PERSONAL_SERVER_LAST_ERROR_MESSAGE_KEY = 'personal_server_bookmark_sync_g3_last_error_message';

type LeafTabSyncBaselineProvider =
  | {
      remoteKind: 'aira-cloud';
      uid: string;
    }
  | {
      remoteKind: 'webdav';
      url: string;
      username?: string;
    }
  | {
      remoteKind: 'personal-server';
      instanceId: string;
    };

const BOOKMARK_WEBDAV_BASELINE_PROTOCOL = 'bookmark-snapshot-v2';

export const createLeafTabSyncBaselineStorageKey = (
  provider: LeafTabSyncBaselineProvider,
  rootPath: string = LEAFTAB_SYNC_DEFAULT_ROOT_PATH,
): string => {
  const normalizedRootPath = (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT_PATH).trim()
    .replace(/^\/+/, '')
    .replace(/\/+$/, '') || LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
  const suffix = normalizedRootPath.replace(/[^a-zA-Z0-9_-]+/g, '_');
  if (provider.remoteKind === 'aira-cloud') {
    const safeUid = (provider.uid || 'unknown').replace(/[^a-zA-Z0-9_-]+/g, '_');
    return `leaftab_sync_g3_baseline:aira_cloud:${safeUid}:${suffix}`;
  }
  if (provider.remoteKind === 'personal-server') {
    const safeInstanceId = (provider.instanceId || 'unknown').replace(/[^a-zA-Z0-9_-]+/g, '_');
    return `leaftab_sync_g3_baseline:personal_server:${safeInstanceId}:${suffix}`;
  }
  const endpoint = String(provider.url || '').trim().replace(/\/+$/, '');
  const username = String(provider.username || '').trim();
  const identity = [
    BOOKMARK_WEBDAV_BASELINE_PROTOCOL,
    endpoint,
    username,
    normalizedRootPath,
  ].map((value) => encodeURIComponent(value)).join(':');
  return `leaftab_sync_bookmark_snapshot_v2_baseline:webdav:${identity}`;
};

export const LEAFTAB_BACKGROUND_STORAGE_KEYS = {
  lastRemoteProbeAt: 'leaftab_sync_g3_background_last_remote_probe_at',
  nextRemoteProbeAt: 'leaftab_sync_g3_background_next_remote_probe_at',
  autoSyncLastError: 'leaftab_sync_g3_background_auto_sync_last_error',
  autoSyncRetryProvider: 'leaftab_sync_g3_background_auto_sync_retry_provider',
  airaCloudClientUpdateRequired: 'leaftab_sync_g3_aira_cloud_client_update_required',
} as const;
