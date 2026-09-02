import { describe, expect, it } from '@ohos/hypium';
import { BookmarkNode } from '../main/ets/common/models/BrowserModels';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID
} from '../main/ets/data/repositories/BookmarkRepositoryCore';
import {
  BookmarkRepository,
  InMemoryBookmarkRepository
} from '../main/ets/data/repositories/BrowserRepositories';
import { PreferencesRepository } from '../main/ets/data/preferences/PreferencesRepository';
import { AiraSyncSnapshot } from '../main/ets/common/models/AiraSyncModels';
import { AiraBookmarkSnapshotService } from '../main/ets/services/sync/AiraBookmarkSnapshotService';
import { parseAiraCloudBookmarkHttpError } from '../main/ets/services/sync/AiraCloudBookmarkRemoteStore';

const T0: string = '2026-08-31T00:00:00.000Z';

function createNode(
  id: string,
  type: 'folder' | 'bookmark',
  title: string,
  parentId: string | undefined,
  position: number,
  url?: string
): BookmarkNode {
  return {
    id: id,
    type: type,
    scope: 'regular',
    parentId: parentId,
    title: title,
    url: url,
    position: position,
    createdAt: Date.parse(T0),
    updatedAt: Date.parse(T0),
    sync: {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: Date.parse(T0),
      lastModifiedBy: 'test-device',
      deviceId: 'test-device'
    }
  };
}

function createPreviousSnapshot(): AiraSyncSnapshot {
  return {
    meta: {
      version: 2,
      deviceId: 'old-device',
      generatedAt: T0
    },
    bookmarkFolders: [{
      id: 'bkf_bookmark_knw408',
      type: 'bookmark-folder',
      parentId: 'browser_root_toolbar',
      title: '开发收藏夹',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: 'old-device',
      revision: 1
    }, {
      id: 'bkf_bookmark_1aws9kc',
      type: 'bookmark-folder',
      parentId: 'browser_root_other',
      title: '阅读收藏夹',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: 'old-device',
      revision: 1
    }],
    bookmarkItems: [{
      id: 'bkm_bookmark_6fw06t',
      type: 'bookmark-item',
      parentId: 'bkf_bookmark_knw408',
      title: '同名书签',
      url: 'https://example.com/same',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: 'old-device',
      revision: 1
    }, {
      id: 'bkm_bookmark_3mzkha',
      type: 'bookmark-item',
      parentId: 'bkf_bookmark_1aws9kc',
      title: '同名书签',
      url: 'https://example.com/same',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: 'old-device',
      revision: 1
    }],
    bookmarkOrders: [],
    tombstones: []
  };
}

class FixtureBookmarkRepository extends InMemoryBookmarkRepository implements BookmarkRepository {}

async function createRepository(nodes: BookmarkNode[]): Promise<FixtureBookmarkRepository> {
  const repository = new FixtureBookmarkRepository();
  await repository.upsertSyncNodes(nodes);
  return repository;
}

export default function airaBookmarkSnapshotServiceTest(): void {
  describe('AiraBookmarkSnapshotService stable ID migration', () => {
    it('reuses old IDs for repeated title and URL entries in distinct folders', 0, async () => {
      const nodes: BookmarkNode[] = [
        createNode(BOOKMARK_TOOLBAR_ROOT_ID, 'folder', '书签栏', undefined, 0),
        createNode(BOOKMARK_OTHER_ROOT_ID, 'folder', '其他书签', undefined, 1),
        createNode('local-folder-toolbar', 'folder', '开发收藏夹', BOOKMARK_TOOLBAR_ROOT_ID, 0),
        createNode('local-folder-other', 'folder', '阅读收藏夹', BOOKMARK_OTHER_ROOT_ID, 0),
        createNode(
          'local-item-toolbar',
          'bookmark',
          '同名书签',
          'local-folder-toolbar',
          0,
          'https://example.com/same'
        ),
        createNode(
          'local-item-other',
          'bookmark',
          '同名书签',
          'local-folder-other',
          0,
          'https://example.com/same'
        )
      ];
      const repository = await createRepository(nodes);
      const service = new AiraBookmarkSnapshotService(
        repository,
        new PreferencesRepository()
      );

      const snapshot = await service.buildFreshBookmarkSnapshot('test-device', true, createPreviousSnapshot());
      const itemIds = snapshot.bookmarkItems.map((item) => item.id).sort();

      expect(JSON.stringify(itemIds)).assertEqual(JSON.stringify(['bkm_bookmark_3mzkha', 'bkm_bookmark_6fw06t']));
      expect(snapshot.bookmarkItems.length).assertEqual(2);

      const nextSnapshot = await service.buildFreshBookmarkSnapshot('test-device', true, snapshot);
      const nextItemIds = nextSnapshot.bookmarkItems.map((item) => item.id).sort();
      expect(JSON.stringify(nextItemIds)).assertEqual(JSON.stringify(itemIds));
      expect(nextSnapshot.bookmarkItems.length).assertEqual(2);
    });

    it('keeps the server error code from a non-2xx JSON response', 0, () => {
      const response = parseAiraCloudBookmarkHttpError(409, JSON.stringify({
        ok: false,
        code: 'sync_conflict',
        message: '云端书签已经更新，请先重新拉取后再同步。'
      }));

      expect(response.ok).assertEqual(false);
      expect(response.code).assertEqual('sync_conflict');
      expect(response.message).assertEqual('云端书签已经更新，请先重新拉取后再同步。');
    });
  });
}
