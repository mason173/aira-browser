import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createServer } from 'vite';

const vite = await createServer({
  server: { middlewareMode: true },
  appType: 'custom',
  logLevel: 'silent',
});

const storage = new Map();
globalThis.localStorage = {
  getItem: (key) => storage.has(key) ? storage.get(key) : null,
  setItem: (key, value) => storage.set(key, String(value)),
  removeItem: (key) => storage.delete(key),
};

let passed = 0;

const test = (name, fn) => {
  try {
    fn();
    passed += 1;
    console.log(`PASS ${name}`);
  } catch (error) {
    console.error(`FAIL ${name}`);
    throw error;
  }
};

const asyncTest = async (name, fn) => {
  try {
    await fn();
    passed += 1;
    console.log(`PASS ${name}`);
  } catch (error) {
    console.error(`FAIL ${name}`);
    throw error;
  }
};

try {
  const manifest = JSON.parse(readFileSync(new URL('../public/manifest.final.json', import.meta.url), 'utf8'));
  const [
    { resolveAiraDesktopSyncStatus },
    { BookmarkSyncModule, createBookmarkSyncSourceIdentity },
    login,
    { LeafTabSyncEngine },
    { LeafTabSyncMemoryBaselineStore },
    {
      probeLeafTabBookmarkSyncChanges,
      shouldRunLeafTabBookmarkSyncForProbe,
    },
    source,
  ] = await Promise.all([
    vite.ssrLoadModule('/src/features/sync/bookmarks/desktopSyncEligibility.ts'),
    vite.ssrLoadModule('/src/features/sync/bookmarks/BookmarkSyncModule.ts'),
    vite.ssrLoadModule('/src/popup/desktopLogin.ts'),
    vite.ssrLoadModule('/src/sync/leaftab/engine.ts'),
    vite.ssrLoadModule('/src/sync/leaftab/baseline.ts'),
    vite.ssrLoadModule('/src/sync/leaftab/changeProbe.ts'),
    vite.ssrLoadModule('/src/sync/leaftab/source.ts'),
  ]);

  test('release manifest grants all HTTP and HTTPS hosts without optional prompts', () => {
    assert.ok(manifest.host_permissions?.includes('https://*/*'));
    assert.ok(manifest.host_permissions?.includes('http://*/*'));
    assert.equal(manifest.optional_host_permissions, undefined);
  });

  test('Pro profile with disabled sync is reported as disabled, not Pro-required', () => {
    assert.equal(resolveAiraDesktopSyncStatus({
      uid: '1956796357180173504',
      desktopPushToken: 'desktop-token',
      membershipPlan: 'pro',
      membershipExpiresAt: 0,
    }, false), 'disabled');
  });

  test('Pro profile with enabled sync is ready', () => {
    assert.equal(resolveAiraDesktopSyncStatus({
      uid: '1956796357180173504',
      desktopPushToken: 'desktop-token',
      membershipPlan: 'pro',
      membershipExpiresAt: 0,
    }, true), 'ready');
  });

  test('missing desktop token requires desktop login', () => {
    assert.equal(resolveAiraDesktopSyncStatus({
      uid: '1956796357180173504',
      desktopPushToken: '',
      membershipPlan: 'pro',
      membershipExpiresAt: 0,
    }, true), 'login-required');
  });

  test('non-Pro profile requires Pro', () => {
    assert.equal(resolveAiraDesktopSyncStatus({
      uid: '1956796357180173504',
      desktopPushToken: 'desktop-token',
      membershipPlan: 'club',
      membershipExpiresAt: 0,
    }, true), 'pro-required');
  });

  test('selected Aira cloud source schedules auto-sync even with stale cached entitlement', () => {
    assert.equal(source.canRunLeafTabSelectedAutoSync({
      selectedSource: 'aira-cloud',
      cloudUid: '1956796357180173504',
      cloudDesktopPushToken: 'desktop-token',
      cloudEntitled: false,
      airaCloudEnabled: false,
      webdavEnabled: false,
      webdavUrl: '',
    }), true);
  });

  test('bookmark overview source identity separates WebDAV endpoints without using passwords', () => {
    const createIdentity = (url, password) => createBookmarkSyncSourceIdentity({
      source: 'webdav',
      webdav: {
        url,
        username: 'leo',
        password,
        rootPath: 'AiraTab',
        requestPermission: false,
      },
    }, 'AiraTab');
    assert.notEqual(createIdentity('https://dav-a.example', 'secret'), createIdentity('https://dav-b.example', 'secret'));
    assert.equal(createIdentity('https://dav-a.example', 'first'), createIdentity('https://dav-a.example', 'second'));
  });

  test('writing a desktop profile emits a profile-changed event', () => {
    const events = [];
    globalThis.window = new EventTarget();
    window.addEventListener(login.AIRA_DESKTOP_LOGIN_PROFILE_CHANGED_EVENT, () => events.push('changed'));
    login.writeAiraDesktopLoginProfile({
      uid: '1956796357180173504',
      uidSuffix: '173504',
      displayName: 'Leo',
      avatarUri: '',
      membershipPlan: 'pro',
      membershipStatus: 'active_pro',
      membershipExpiresAt: 0,
      membershipCheckedAt: new Date().toISOString(),
      loggedInAt: new Date().toISOString(),
      desktopPushToken: 'desktop-token',
    });
    assert.deepEqual(events, ['changed']);
  });

  test('profile-changed event refreshes the cached sync identity after login', () => {
    storage.delete('aira_desktop_login_profile_v1');
    globalThis.window = new EventTarget();
    let controllerProfile = login.readAiraDesktopLoginProfile();
    window.addEventListener(login.AIRA_DESKTOP_LOGIN_PROFILE_CHANGED_EVENT, () => {
      controllerProfile = login.readAiraDesktopLoginProfile();
    });
    login.writeAiraDesktopLoginProfile({
      uid: '1956796357180173504',
      uidSuffix: '173504',
      displayName: 'Leo',
      avatarUri: '',
      membershipPlan: 'pro',
      membershipStatus: 'active_pro',
      membershipExpiresAt: 0,
      membershipCheckedAt: new Date().toISOString(),
      loggedInAt: new Date().toISOString(),
      desktopPushToken: 'desktop-token',
    });
    assert.equal(resolveAiraDesktopSyncStatus(controllerProfile, true), 'ready');
  });

  await asyncTest('sync analysis keeps local and remote bookmark counts separate', async () => {
    const makeSnapshot = (folderCount, itemCount) => ({
      meta: { version: 2, deviceId: 'fixture', generatedAt: '2026-01-01T00:00:00.000Z' },
      bookmarkFolders: Object.fromEntries(Array.from({ length: folderCount }, (_, index) => [
        `folder-${index}`,
        {
          id: `folder-${index}`,
          type: 'bookmark-folder',
          parentId: null,
          title: `Folder ${index}`,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          updatedBy: 'fixture',
          revision: 1,
        },
      ])),
      bookmarkItems: Object.fromEntries(Array.from({ length: itemCount }, (_, index) => [
        `item-${index}`,
        {
          id: `item-${index}`,
          type: 'bookmark-item',
          parentId: null,
          title: `Item ${index}`,
          url: `https://example.com/${index}`,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
          updatedBy: 'fixture',
          revision: 1,
        },
      ])),
      bookmarkOrders: {
        __root__: {
          type: 'bookmark-order',
          parentId: null,
          ids: [],
          updatedAt: '2026-01-01T00:00:00.000Z',
          updatedBy: 'fixture',
          revision: 1,
        },
      },
      tombstones: {},
    });
    const localSnapshot = makeSnapshot(2, 3);
    const remoteSnapshot = makeSnapshot(4, 5);
    const engine = new LeafTabSyncEngine({
      deviceId: 'fixture-device',
      baselineStore: new LeafTabSyncMemoryBaselineStore(),
      buildLocalSnapshot: async () => localSnapshot,
      applyLocalSnapshot: async () => undefined,
      createEmptySnapshot: () => makeSnapshot(0, 0),
      remoteStore: {
        acquireLock: async () => undefined,
        releaseLock: async () => undefined,
        readHead: async () => ({
          head: null,
          commit: null,
          commitId: 'remote-1',
          updatedAt: 0,
          summary: { bookmarkFolders: 4, bookmarkItems: 5, tombstones: 0 },
        }),
        readState: async () => ({
          head: null,
          commit: { id: 'remote-1' },
          snapshot: remoteSnapshot,
        }),
        writeState: async () => ({ head: {}, commit: { id: 'remote-2' } }),
      },
    });
    const analysis = await engine.analyze();
    assert.deepEqual(analysis.localSummary, { bookmarkFolders: 2, bookmarkItems: 3, tombstones: 0 });
    assert.deepEqual(analysis.remoteSummary, { bookmarkFolders: 4, bookmarkItems: 5, tombstones: 0 });
  });

  await asyncTest('bookmark overview keeps local counts when the remote summary is unavailable', async () => {
    const timestamp = '2026-01-01T00:00:00.000Z';
    const localSnapshot = {
      meta: { version: 2, deviceId: 'fixture', generatedAt: timestamp },
      bookmarkFolders: {
        folder: {
          id: 'folder',
          type: 'bookmark-folder',
          parentId: null,
          title: 'Folder',
          createdAt: timestamp,
          updatedAt: timestamp,
          updatedBy: 'fixture',
          revision: 1,
        },
      },
      bookmarkItems: {
        item: {
          id: 'item',
          type: 'bookmark-item',
          parentId: 'folder',
          title: 'Item',
          url: 'https://example.com',
          createdAt: timestamp,
          updatedAt: timestamp,
          updatedBy: 'fixture',
          revision: 1,
        },
      },
      bookmarkOrders: {},
      tombstones: {},
    };
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => {
      throw new Error('simulated remote outage');
    };
    try {
      const module = new BookmarkSyncModule({
        sourceConfig: {
          source: 'webdav',
          webdav: {
            url: 'https://example.invalid/dav',
            rootPath: 'AiraTab',
            requestPermission: false,
          },
        },
        deviceId: 'fixture-device',
        rootPath: 'AiraTab',
        baselineStorageKey: 'fixture-overview-baseline',
        local: {
          buildSnapshot: async () => localSnapshot,
          applySnapshot: async () => undefined,
          createEmptySnapshot: () => localSnapshot,
        },
      });
      const overview = await module.readSummary();
      assert.deepEqual(overview.local, { bookmarkFolders: 1, bookmarkItems: 1, tombstones: 0 });
      assert.equal(overview.remote, null);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  await asyncTest('remote bookmark deletion is applied to the local tree', async () => {
    const timestamp = '2026-01-01T00:00:00.000Z';
    const item = {
      id: 'item-1',
      type: 'bookmark-item',
      parentId: null,
      title: 'Item 1',
      url: 'https://example.com/1',
      createdAt: timestamp,
      updatedAt: timestamp,
      updatedBy: 'fixture',
      revision: 1,
    };
    const baseSnapshot = {
      meta: { version: 2, deviceId: 'fixture', generatedAt: timestamp },
      bookmarkFolders: {},
      bookmarkItems: { [item.id]: item },
      bookmarkOrders: {
        __root__: {
          type: 'bookmark-order',
          parentId: null,
          ids: [item.id],
          updatedAt: timestamp,
          updatedBy: 'fixture',
          revision: 1,
        },
      },
      tombstones: {},
    };
    const remoteSnapshot = {
      ...baseSnapshot,
      bookmarkItems: {},
      bookmarkOrders: {
        __root__: {
          ...baseSnapshot.bookmarkOrders.__root__,
          ids: [],
        },
      },
      tombstones: {
        'bookmark-item|item-1': {
          id: item.id,
          type: 'bookmark-item',
          deletedAt: '2026-01-01T00:01:00.000Z',
          deletedBy: 'phone',
          lastKnownRevision: item.revision,
        },
      },
    };
    const baselineStore = new LeafTabSyncMemoryBaselineStore();
    await baselineStore.save({
      commitId: 'base-1',
      snapshot: baseSnapshot,
      files: {},
      savedAt: timestamp,
    });
    let appliedSnapshot = null;
    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop',
      baselineStore,
      buildLocalSnapshot: async () => baseSnapshot,
      applyLocalSnapshot: async (snapshot) => {
        appliedSnapshot = snapshot;
      },
      createEmptySnapshot: () => ({
        meta: { version: 2, deviceId: 'desktop', generatedAt: timestamp },
        bookmarkFolders: {},
        bookmarkItems: {},
        bookmarkOrders: {},
        tombstones: {},
      }),
      remoteStore: {
        acquireLock: async () => undefined,
        releaseLock: async () => undefined,
        readHead: async () => ({
          head: null,
          commit: null,
          commitId: 'remote-2',
          updatedAt: 0,
          summary: { bookmarkFolders: 0, bookmarkItems: 0, tombstones: 1 },
        }),
        readState: async () => ({
          head: null,
          commit: { id: 'remote-2' },
          snapshot: remoteSnapshot,
        }),
        writeState: async () => ({ head: {}, commit: { id: 'remote-3' } }),
      },
    });

    const result = await engine.sync('auto');
    assert.equal(result.kind, 'pull');
    assert.ok(appliedSnapshot);
    assert.equal(Object.keys(appliedSnapshot.bookmarkItems).length, 0);
    assert.equal(Object.keys(appliedSnapshot.tombstones).length, 1);
  });

  await asyncTest('failed local apply does not advance the sync baseline', async () => {
    const timestamp = '2026-01-01T00:00:00.000Z';
    const item = {
      id: 'item-1',
      type: 'bookmark-item',
      parentId: null,
      title: 'Item 1',
      url: 'https://example.com/1',
      createdAt: timestamp,
      updatedAt: timestamp,
      updatedBy: 'fixture',
      revision: 1,
    };
    const baseSnapshot = {
      meta: { version: 2, deviceId: 'fixture', generatedAt: timestamp },
      bookmarkFolders: {},
      bookmarkItems: { [item.id]: item },
      bookmarkOrders: {},
      tombstones: {},
    };
    const remoteSnapshot = {
      ...baseSnapshot,
      bookmarkItems: {},
      tombstones: {
        'bookmark-item|item-1': {
          id: item.id,
          type: 'bookmark-item',
          deletedAt: '2026-01-01T00:01:00.000Z',
          deletedBy: 'phone',
          lastKnownRevision: item.revision,
        },
      },
    };
    const baselineStore = new LeafTabSyncMemoryBaselineStore();
    await baselineStore.save({
      commitId: 'base-1',
      snapshot: baseSnapshot,
      files: {},
      savedAt: timestamp,
    });

    const engine = new LeafTabSyncEngine({
      deviceId: 'desktop',
      baselineStore,
      buildLocalSnapshot: async () => baseSnapshot,
      applyLocalSnapshot: async () => {
        throw new Error('simulated bookmark API failure');
      },
      hasPendingLocalChanges: () => true,
      createEmptySnapshot: () => ({
        meta: { version: 2, deviceId: 'desktop', generatedAt: timestamp },
        bookmarkFolders: {},
        bookmarkItems: {},
        bookmarkOrders: {},
        tombstones: {},
      }),
      remoteStore: {
        acquireLock: async () => undefined,
        releaseLock: async () => undefined,
        readHead: async () => ({
          head: null,
          commit: null,
          commitId: 'remote-2',
          updatedAt: 0,
          summary: { bookmarkFolders: 0, bookmarkItems: 0, tombstones: 1 },
        }),
        readState: async () => ({
          head: null,
          commit: { id: 'remote-2' },
          snapshot: remoteSnapshot,
        }),
        writeState: async () => ({ head: {}, commit: { id: 'remote-3' } }),
      },
    });

    await assert.rejects(() => engine.sync('auto'), /simulated bookmark API failure/);
    const baseline = await baselineStore.load();
    assert.equal(baseline?.commitId, 'base-1');
  });

  await asyncTest('same remote commit does not skip when local counts differ from the baseline', async () => {
    const baselineKey = 'stale-baseline';
    const timestamp = '2026-01-01T00:00:00.000Z';
    storage.set(baselineKey, JSON.stringify({
      commitId: 'remote-2',
      snapshot: {
        meta: { version: 2, deviceId: 'fixture', generatedAt: timestamp },
        bookmarkFolders: { folder: { id: 'folder', type: 'bookmark-folder' } },
        bookmarkItems: { item: { id: 'item', type: 'bookmark-item' } },
        bookmarkOrders: {},
        tombstones: {},
      },
      files: {},
      savedAt: timestamp,
    }));
    const result = await probeLeafTabBookmarkSyncChanges({
      provider: 'aira-cloud',
      baselineStorageKey: baselineKey,
      createRemoteStore: () => ({
        acquireLock: async () => undefined,
        releaseLock: async () => undefined,
        readCommitId: async () => 'remote-2',
        readState: async () => ({ head: null, commit: null, snapshot: null }),
        writeState: async () => ({ head: {}, commit: { id: 'remote-2' } }),
      }),
      hasPendingLocalChanges: async () => false,
      readLocalSummary: async () => ({ bookmarkFolders: 2, bookmarkItems: 2 }),
    });
    assert.equal(result.canSkipSync, false);
    assert.equal(result.hasLocalChanges, true);
    assert.equal(shouldRunLeafTabBookmarkSyncForProbe(result), true);
  });

  console.log(`${passed} sync tests passed`);
} finally {
  await vite.close();
}
