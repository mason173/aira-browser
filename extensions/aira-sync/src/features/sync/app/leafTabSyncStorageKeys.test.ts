import { describe, expect, test } from 'vitest';
import {
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  createLeafTabSyncBaselineStorageKey,
  LEAFTAB_BOOKMARK_MAPPING_KEY,
  LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  LEAFTAB_SYNC_DEFAULT_ROOT_PATH,
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  LEAFTAB_SYNC_HISTORY_KEY,
  WEBDAV_LAST_SYNC_AT_KEY,
} from './leafTabSyncStorageKeys';

describe('LeafTab Sync storage generations', () => {
  test('keeps local identity and user selection while isolating all v3 provider state', () => {
    const airaBaseline = createLeafTabSyncBaselineStorageKey({
      remoteKind: 'aira-cloud',
      uid: 'uid-a',
    });
    const webdavBaseline = createLeafTabSyncBaselineStorageKey({
      remoteKind: 'webdav',
      url: 'https://dav.example/',
      username: 'mason',
    });

    expect({
      preserved: [
        LEAFTAB_SYNC_DEVICE_ID_KEY,
        LEAFTAB_BOOKMARK_MAPPING_KEY,
        LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
      ],
      isolated: [
        LEAFTAB_SYNC_DEFAULT_ROOT_PATH,
        LEAFTAB_SYNC_HISTORY_KEY,
        LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
        AIRA_CLOUD_LAST_SYNC_AT_KEY,
        WEBDAV_LAST_SYNC_AT_KEY,
        airaBaseline,
        webdavBaseline,
      ],
    }).toEqual({
      preserved: [
        'leaftab_sync_g2_device_id',
        'leaftab_sync_g2_bookmark_mapping:roots:toolbar+other',
        'leaftab_sync_g2_active_provider',
      ],
      isolated: [
        'aira/g3/bookmarks',
        'leaftab_sync_g3_confirmed_bookmark_history',
        'leaftab_sync_g3_pending_bookmark_conflict',
        'aira_cloud_bookmark_sync_g3_last_sync_at',
        'webdav_bookmark_sync_g3_last_sync_at',
        'leaftab_sync_g3_baseline:aira_cloud:uid-a:aira_g3_bookmarks',
        'leaftab_sync_bookmark_snapshot_v2_baseline:webdav:bookmark-snapshot-v2:https%3A%2F%2Fdav.example:mason:aira%2Fg3%2Fbookmarks',
      ],
    });
  });
});
