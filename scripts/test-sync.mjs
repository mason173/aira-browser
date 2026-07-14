import assert from 'node:assert/strict';
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
  const { resolveAiraDesktopSyncStatus } = await vite.ssrLoadModule(
    '/src/features/sync/bookmarks/desktopSyncEligibility.ts',
  );
  const login = await vite.ssrLoadModule('/src/popup/desktopLogin.ts');
  const { LeafTabSyncEngine } = await vite.ssrLoadModule('/src/sync/leaftab/engine.ts');
  const { LeafTabSyncMemoryBaselineStore } = await vite.ssrLoadModule('/src/sync/leaftab/baseline.ts');

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

  console.log(`${passed} sync tests passed`);
} finally {
  await vite.close();
}
