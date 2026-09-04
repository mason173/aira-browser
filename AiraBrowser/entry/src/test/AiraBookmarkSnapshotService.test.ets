import { describe, expect, it } from '@ohos/hypium';
import { BookmarkNode } from '../main/ets/common/models/BrowserModels';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../main/ets/data/repositories/BookmarkRepositoryCore';
import {
  BookmarkRepository,
  InMemoryBookmarkRepository
} from '../main/ets/data/repositories/BrowserRepositories';
import { PreferencesRepository } from '../main/ets/data/preferences/PreferencesRepository';
import { AiraSyncSnapshot } from '../main/ets/common/models/AiraSyncModels';
import { AiraBookmarkSnapshotService } from '../main/ets/services/sync/AiraBookmarkSnapshotService';
import { HuaweiAccountAccessTokenProvider } from
  '../main/ets/services/sync/HuaweiAccountSyncAuthService';
import {
  AiraCloudBookmarkRemoteError,
  AiraCloudBookmarkApiAuthProvider,
  AiraCloudBookmarkApiHttpAdapter,
  AiraCloudBookmarkRemoteStore,
  parseAiraCloudBookmarkHttpError,
  RuntimeAiraCloudBookmarkApiAuthProvider
} from '../main/ets/services/sync/AiraCloudBookmarkRemoteStore';

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

function createBootstrapSnapshot(): AiraSyncSnapshot {
  return {
    meta: {
      version: 2,
      deviceId: 'cloud-device',
      generatedAt: T0
    },
    bookmarkFolders: [{
      id: 'browser_root_toolbar',
      type: 'bookmark-folder',
      parentId: null,
      title: '书签栏',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: 'cloud-device',
      revision: 1
    }],
    bookmarkItems: [{
      id: 'cloud-regular-item',
      type: 'bookmark-item',
      parentId: 'browser_root_toolbar',
      title: '云端普通书签',
      url: 'https://example.com/cloud-regular',
      createdAt: T0,
      updatedAt: T0,
      updatedBy: 'cloud-device',
      revision: 1
    }],
    bookmarkOrders: [{
      type: 'bookmark-order',
      parentId: null,
      ids: ['browser_root_toolbar'],
      updatedAt: T0,
      updatedBy: 'cloud-device',
      revision: 1
    }, {
      type: 'bookmark-order',
      parentId: 'browser_root_toolbar',
      ids: ['cloud-regular-item'],
      updatedAt: T0,
      updatedBy: 'cloud-device',
      revision: 1
    }],
    tombstones: [],
    appPrivateBookmarks: {
      bookmarkFolders: [{
        id: 'aira_private_root_toolbar',
        type: 'bookmark-folder',
        parentId: null,
        title: '隐私书签栏',
        createdAt: T0,
        updatedAt: T0,
        updatedBy: 'cloud-device',
        revision: 1
      }],
      bookmarkItems: [{
        id: 'cloud-private-item',
        type: 'bookmark-item',
        parentId: 'aira_private_root_toolbar',
        title: '云端隐私书签',
        url: 'https://example.com/cloud-private',
        createdAt: T0,
        updatedAt: T0,
        updatedBy: 'cloud-device',
        revision: 1
      }],
      bookmarkOrders: [{
        type: 'bookmark-order',
        parentId: null,
        ids: ['aira_private_root_toolbar'],
        updatedAt: T0,
        updatedBy: 'cloud-device',
        revision: 1
      }, {
        type: 'bookmark-order',
        parentId: 'aira_private_root_toolbar',
        ids: ['cloud-private-item'],
        updatedAt: T0,
        updatedBy: 'cloud-device',
        revision: 1
      }],
      tombstones: []
    }
  };
}

class FixtureBookmarkRepository extends InMemoryBookmarkRepository implements BookmarkRepository {}

class FixtureCloudAuthProvider implements AiraCloudBookmarkApiAuthProvider {
  getAuthorizationHeader(_expectedUid: string): Promise<string> {
    return Promise.resolve('Bearer fixture-token');
  }
}

class FixtureCloudAccessTokenProvider implements HuaweiAccountAccessTokenProvider {
  lastRequestedUid: string = '';

  getCurrentAccessToken(_forceRefresh: boolean): Promise<string> {
    return Promise.resolve('local-test-token');
  }

  getCurrentAccessTokenForUid(uid: string, _forceRefresh: boolean): Promise<string> {
    this.lastRequestedUid = uid;
    return Promise.resolve('local-test-token');
  }
}

class FixtureCloudAdapter implements AiraCloudBookmarkApiHttpAdapter {
  response: Object | string | null | undefined;

  post(
    _url: string,
    _body: Object,
    _authorization: string,
    _timeoutMs: number
  ): Promise<Object | string | null | undefined> {
    return Promise.resolve(this.response);
  }
}

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

    it('replaces regular and private local trees from one validated cloud snapshot', 0, async () => {
      const privateNode = createNode(
        'local-private-item',
        'bookmark',
        '本地隐私书签',
        PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID,
        0,
        'https://example.com/local-private'
      );
      privateNode.scope = 'private';
      const repository = await createRepository([
        createNode(
          'local-regular-item',
          'bookmark',
          '本地普通书签',
          BOOKMARK_TOOLBAR_ROOT_ID,
          0,
          'https://example.com/local-regular'
        ),
        privateNode
      ]);
      const service = new AiraBookmarkSnapshotService(repository, new PreferencesRepository());

      const result = await service.replaceLocalBookmarksFromRemoteSnapshot(createBootstrapSnapshot());
      const regularTitles = repository.listNodes('regular').map((node: BookmarkNode): string => node.title);
      const privateTitles = repository.listNodes('private').map((node: BookmarkNode): string => node.title);

      expect(result.blocked).assertFalse();
      expect(regularTitles.indexOf('本地普通书签')).assertEqual(-1);
      expect(privateTitles.indexOf('本地隐私书签')).assertEqual(-1);
      expect(regularTitles.indexOf('云端普通书签') >= 0).assertTrue();
      expect(privateTitles.indexOf('云端隐私书签') >= 0).assertTrue();
    });

    it('rejects a successful response that omits the current cloud protocol', 0, async () => {
      const adapter = new FixtureCloudAdapter();
      adapter.response = JSON.stringify({
        ok: true,
        commitId: null,
        snapshot: null,
        history: null
      });
      const store = new AiraCloudBookmarkRemoteStore(
        'https://sync.example.test/sync/v4/bookmarks',
        'fixture-user',
        new FixtureCloudAuthProvider(),
        adapter
      );
      let rejected = false;
      let errorCode: string = '';
      try {
        await store.readState();
      } catch (error) {
        rejected = true;
        if (error instanceof AiraCloudBookmarkRemoteError) {
          errorCode = error.code;
        }
      }
      expect(rejected).assertTrue();
      expect(errorCode).assertEqual('client_update_required');
    });

    it('binds cloud authorization to the requested account', 0, async () => {
      const tokenProvider = new FixtureCloudAccessTokenProvider();
      const authProvider = new RuntimeAiraCloudBookmarkApiAuthProvider(
        tokenProvider
      );

      const authorization = await authProvider.getAuthorizationHeader('fixture-user');

      expect(authorization).assertEqual('Bearer local-test-token');
      expect(tokenProvider.lastRequestedUid).assertEqual('fixture-user');
    });
  });
}
