import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createServer } from 'vite';

const vite = await createServer({
  server: { middlewareMode: true },
  appType: 'custom',
  logLevel: 'silent',
});

const storage = new Map();
const extensionStorage = new Map();
globalThis.localStorage = {
  getItem: (key) => storage.has(key) ? storage.get(key) : null,
  setItem: (key, value) => storage.set(key, String(value)),
  removeItem: (key) => storage.delete(key),
};
globalThis.chrome = {
  storage: {
    local: {
      get: async (keys) => {
        const selectedKeys = Array.isArray(keys) ? keys : Array.from(extensionStorage.keys());
        return Object.fromEntries(selectedKeys
          .filter((key) => extensionStorage.has(key))
          .map((key) => [key, extensionStorage.get(key)]));
      },
      set: async (values) => {
        Object.entries(values).forEach(([key, value]) => extensionStorage.set(key, value));
      },
      remove: async (keys) => {
        (Array.isArray(keys) ? keys : [keys]).forEach((key) => extensionStorage.delete(key));
      },
    },
  },
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
    connectionProfile,
    pagePushPreferences,
    { LeafTabSyncEngine },
    { LeafTabSyncMemoryBaselineStore },
    {
      probeLeafTabBookmarkSyncChanges,
      shouldRunLeafTabBookmarkSyncForProbe,
    },
    source,
    desktopConnection,
    desktopConnectionRuntime,
    airaCloudPreferences,
    { LeafTabSyncAiraCloudError },
  ] = await Promise.all([
    vite.ssrLoadModule('/src/features/sync/bookmarks/desktopSyncEligibility.ts'),
    vite.ssrLoadModule('/src/features/sync/bookmarks/BookmarkSyncModule.ts'),
    vite.ssrLoadModule('/src/features/desktop-connection/desktopConnectionProfile.ts'),
    vite.ssrLoadModule('/src/features/phone-page-push/pagePushPreferences.ts'),
    vite.ssrLoadModule('/src/sync/leaftab/engine.ts'),
    vite.ssrLoadModule('/src/sync/leaftab/baseline.ts'),
    vite.ssrLoadModule('/src/sync/leaftab/changeProbe.ts'),
    vite.ssrLoadModule('/src/sync/leaftab/source.ts'),
    vite.ssrLoadModule('/src/features/desktop-connection/AiraDesktopConnectionModule.ts'),
    vite.ssrLoadModule('/src/features/desktop-connection/desktopConnectionRuntime.ts'),
    vite.ssrLoadModule('/src/features/sync/bookmarks/airaCloudPreferences.ts'),
    vite.ssrLoadModule('/src/sync/leaftab/airaCloudStore.ts'),
  ]);

  test('release manifest grants all HTTP and HTTPS hosts without optional prompts', () => {
    assert.ok(manifest.host_permissions?.includes('https://*/*'));
    assert.ok(manifest.host_permissions?.includes('http://*/*'));
    assert.equal(manifest.optional_host_permissions, undefined);
  });

  test('Pro profile with disabled sync is reported as disabled, not Pro-required', () => {
    assert.equal(resolveAiraDesktopSyncStatus({
      uid: '1956796357180173504',
      deviceCredential: 'desktop-token',
      membershipPlan: 'pro',
      membershipExpiresAt: 0,
    }, false), 'disabled');
  });

  test('Pro profile with enabled sync is ready', () => {
    assert.equal(resolveAiraDesktopSyncStatus({
      uid: '1956796357180173504',
      deviceCredential: 'desktop-token',
      membershipPlan: 'pro',
      membershipExpiresAt: 0,
    }, true), 'ready');
  });

  test('missing Device Credential requires reconnecting the Desktop Device Session', () => {
    assert.equal(resolveAiraDesktopSyncStatus({
      uid: '1956796357180173504',
      deviceCredential: '',
      membershipPlan: 'pro',
      membershipExpiresAt: 0,
    }, true), 'login-required');
  });

  test('non-Pro profile requires Pro', () => {
    assert.equal(resolveAiraDesktopSyncStatus({
      uid: '1956796357180173504',
      deviceCredential: 'desktop-token',
      membershipPlan: 'club',
      membershipExpiresAt: 0,
    }, true), 'pro-required');
  });

  test('selected Aira cloud source schedules auto-sync even with stale cached entitlement', () => {
    assert.equal(source.canRunLeafTabSelectedAutoSync({
      selectedSource: 'aira-cloud',
      cloudUid: '1956796357180173504',
      cloudDeviceCredential: 'desktop-token',
      cloudEntitled: false,
      airaCloudEnabled: false,
      webdavEnabled: false,
      webdavUrl: '',
    }), true);
  });

  test('phone page push defaults to enabled and honors explicit choices', () => {
    const phonePagePushEnabledKey = pagePushPreferences.PHONE_PAGE_PUSH_ENABLED_KEY;
    storage.delete(phonePagePushEnabledKey);
    assert.equal(pagePushPreferences.readPhonePagePushEnabledFromLocalStorage(''), true);
    try {
      storage.set(phonePagePushEnabledKey, 'true');
      assert.equal(pagePushPreferences.readPhonePagePushEnabledFromLocalStorage(''), true);
      storage.set(phonePagePushEnabledKey, 'false');
      assert.equal(pagePushPreferences.readPhonePagePushEnabledFromLocalStorage(''), false);
    } finally {
      storage.delete(phonePagePushEnabledKey);
    }
  });

  test('phone page push preference is isolated by Aira account on the same Desktop Device', () => {
    try {
      pagePushPreferences.writePhonePagePushEnabled('preference-account-a', true);
      pagePushPreferences.writePhonePagePushEnabled('preference-account-b', false);
      assert.equal(pagePushPreferences.readPhonePagePushEnabledFromLocalStorage('preference-account-b'), false);
      assert.equal(pagePushPreferences.readPhonePagePushEnabledFromLocalStorage('preference-account-a'), true);
    } finally {
      for (const key of Array.from(storage.keys())) {
        if (key.startsWith('aira_phone_page_push_')) {
          storage.delete(key);
        }
      }
    }
  });

  test('Aira Cloud sync intent is isolated by Aira account on the same Desktop Device', () => {
    try {
      airaCloudPreferences.writeAiraCloudSyncEnabled('cloud-account-a', true);
      assert.equal(airaCloudPreferences.readAiraCloudSyncEnabledFromLocalStorage('cloud-account-a'), true);
      assert.equal(airaCloudPreferences.readAiraCloudSyncEnabledFromLocalStorage('cloud-account-b'), false);
      airaCloudPreferences.writeAiraCloudSyncEnabled('cloud-account-b', false);
      assert.equal(airaCloudPreferences.readAiraCloudSyncEnabledFromLocalStorage('cloud-account-a'), true);
      assert.equal(airaCloudPreferences.readAiraCloudSyncEnabledFromLocalStorage('cloud-account-b'), false);
      assert.equal(airaCloudPreferences.resolveAiraCloudSelectedSourceForAccount({
        selectedSource: 'aira-cloud',
        uid: 'cloud-account-a',
        selectedAccountUid: 'cloud-account-b',
        enabledForAccount: true,
      }), 'aira-cloud');
      assert.equal(airaCloudPreferences.resolveAiraCloudSelectedSourceForAccount({
        selectedSource: 'aira-cloud',
        uid: 'cloud-account-c',
        selectedAccountUid: 'cloud-account-b',
        enabledForAccount: false,
      }), null);
    } finally {
      for (const key of Array.from(storage.keys())) {
        if (key.startsWith('aira_cloud_bookmark_sync_')) {
          storage.delete(key);
        }
      }
    }
  });

  await asyncTest('selected sync source is restored independently for each Aira account', async () => {
    const legacySelectedSourceKey = 'leaftab_primary_sync_remote_kind';
    try {
      storage.set(legacySelectedSourceKey, 'aira-cloud');
      await airaCloudPreferences.persistAiraAccountSelectedSyncSource('aira-cloud', 'source-account-b');
      storage.set(legacySelectedSourceKey, 'webdav');
      await airaCloudPreferences.persistAiraAccountSelectedSyncSource('webdav', 'source-account-a');

      assert.equal(airaCloudPreferences.readAiraCloudSelectedSourceFromLocalStorage(
        'webdav',
        'source-account-a',
        false,
      ), 'webdav');
      assert.equal(airaCloudPreferences.readAiraCloudSelectedSourceFromLocalStorage(
        'webdav',
        'source-account-b',
        true,
      ), 'aira-cloud');
    } finally {
      storage.delete(legacySelectedSourceKey);
      storage.delete(airaCloudPreferences.AIRA_CLOUD_SELECTED_ACCOUNT_KEY);
      for (const key of Array.from(storage.keys())) {
        if (key.startsWith('leaftab_primary_sync_remote_kind_v2:')) {
          storage.delete(key);
        }
      }
    }
  });

  test('temporary entitlement failure is not reported as Pro-required', () => {
    assert.equal(connectionProfile.resolveAiraDesktopProCapability({
      uid: 'degraded-user',
      uidSuffix: 'd-user',
      displayName: 'Degraded User',
      avatarUri: '',
      membershipPlan: 'club',
      membershipStatus: 'missing_plan_default_club',
      membershipExpiresAt: 0,
      membershipCheckedAt: '2026-07-14T00:00:00.000Z',
      deviceCredential: 'degraded-token',
      deviceId: 'degraded-device',
      connectionStatus: 'degraded',
      lastErrorCode: 'network_unavailable',
    }), 'temporarily-unavailable');
  });

  await asyncTest('legacy Desktop Device Session is imported once and the legacy profile is removed', async () => {
    const legacyProfileKey = 'aira_desktop_login_profile_v1';
    const canonicalConnectionKey = 'aira_desktop_connection_v1';
    const legacyDeviceIdKey = 'leaftab_sync_v1_device_id';
    const legacyProfile = JSON.stringify({
      uid: 'legacy-user',
      uidSuffix: 'y-user',
      displayName: 'Legacy User',
      membershipPlan: 'pro',
      membershipStatus: 'active_pro',
      membershipExpiresAt: 0,
      membershipCheckedAt: '2026-07-14T00:00:00.000Z',
      desktopPushToken: 'legacy-device-credential',
    });
    extensionStorage.set(legacyProfileKey, legacyProfile);
    extensionStorage.set(legacyDeviceIdKey, 'stable-legacy-device');
    storage.set(legacyProfileKey, legacyProfile);
    try {
      const snapshot = await desktopConnectionRuntime.readAiraDesktopConnectionSnapshot();
      assert.equal(snapshot.account?.uid, 'legacy-user');
      assert.equal(snapshot.deviceId, 'stable-legacy-device');
      assert.ok(extensionStorage.has(canonicalConnectionKey));
      assert.equal(extensionStorage.has(legacyProfileKey), false);
      assert.equal(storage.has(legacyProfileKey), false);
    } finally {
      extensionStorage.delete(canonicalConnectionKey);
      extensionStorage.delete(legacyProfileKey);
      extensionStorage.delete(legacyDeviceIdKey);
      extensionStorage.delete('aira_desktop_device_id_v1');
      storage.delete(legacyProfileKey);
    }
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

  await asyncTest('revoked Device Credential becomes reauth-required without a zombie authorized session', async () => {
    let stored = {
      version: 1,
      status: 'connected',
      deviceId: 'desktop-device',
      deviceName: 'Desktop',
      account: {
        uid: 'desktop-user',
        uidSuffix: 'p-user',
        displayName: 'Desktop User',
        avatarUri: '',
      },
      membership: {
        plan: 'pro',
        status: 'active_pro',
        expiresAt: 0,
        checkedAt: '2026-07-14T00:00:00.000Z',
      },
      credential: 'revoked-token',
      lastError: null,
    };
    const module = new desktopConnection.AiraDesktopConnectionModule({
      storage: {
        read: async () => stored,
        write: async (next) => { stored = next; },
        clear: async () => { stored = null; },
      },
      remote: {
        createPairing: async () => { throw new Error('unused'); },
        pollPairing: async () => { throw new Error('unused'); },
        refreshMembership: async () => {
          throw new desktopConnection.AiraDesktopConnectionRemoteError(
            'invalid_desktop_push_token',
            '桌面设备凭证无效。',
          );
        },
        revoke: async () => undefined,
      },
      now: () => Date.parse('2026-07-14T01:00:00.000Z'),
    });

    const snapshot = await module.refreshMembership({ force: true });
    assert.equal(snapshot.status, 'reauth-required');
    assert.equal(snapshot.account?.uid, 'desktop-user');
    assert.equal(await module.getAuthorizedSession(), null);
    assert.equal(stored.credential, '');
  });

  await asyncTest('Aira Cloud credential failure is absorbed by the Desktop Connection module', async () => {
    let stored = {
      version: 1,
      status: 'connected',
      deviceId: 'cloud-device',
      deviceName: 'Cloud Device',
      account: { uid: 'cloud-user', uidSuffix: 'd-user', displayName: 'Cloud User', avatarUri: '' },
      membership: { plan: 'pro', status: 'active_pro', expiresAt: 0, checkedAt: '2026-07-14T00:00:00.000Z' },
      credential: 'cloud-token',
      lastError: null,
    };
    const module = new desktopConnection.AiraDesktopConnectionModule({
      storage: {
        read: async () => stored,
        write: async (next) => { stored = next; },
        clear: async () => { stored = null; },
      },
      remote: {
        createPairing: async () => { throw new Error('unused'); },
        pollPairing: async () => { throw new Error('unused'); },
        refreshMembership: async () => { throw new Error('unused'); },
        revoke: async () => undefined,
      },
    });

    const snapshot = await module.recordRemoteFailure(
      new LeafTabSyncAiraCloudError(
        'Aira desktop credential was revoked.',
        'invalid_desktop_push_token',
        401,
      ),
    );

    assert.equal(snapshot.status, 'reauth-required');
    assert.equal(snapshot.lastError?.code, 'invalid_desktop_push_token');
    assert.equal(await module.getAuthorizedSession(), null);
  });

  await asyncTest('temporary membership failure keeps the Device Credential for automatic recovery', async () => {
    let stored = {
      version: 1,
      status: 'connected',
      deviceId: 'recover-device',
      deviceName: 'Recover Device',
      account: { uid: 'recover-user', uidSuffix: 'r-user', displayName: 'Recover User', avatarUri: '' },
      membership: { plan: 'pro', status: 'active_pro', expiresAt: 0, checkedAt: '2026-07-14T00:00:00.000Z' },
      credential: 'recover-token',
      lastError: null,
    };
    const module = new desktopConnection.AiraDesktopConnectionModule({
      storage: {
        read: async () => stored,
        write: async (next) => { stored = next; },
        clear: async () => { stored = null; },
      },
      remote: {
        createPairing: async () => { throw new Error('unused'); },
        pollPairing: async () => { throw new Error('unused'); },
        refreshMembership: async () => {
          throw new desktopConnection.AiraDesktopConnectionRemoteError('network_unavailable', 'offline');
        },
        revoke: async () => undefined,
      },
    });

    const snapshot = await module.refreshMembership({ force: true });
    assert.equal(snapshot.status, 'degraded');
    assert.equal((await module.getAuthorizedSession())?.deviceCredential, 'recover-token');
  });

  await asyncTest('confirmed pairing persists one connected Desktop Device Session', async () => {
    let stored = null;
    const module = new desktopConnection.AiraDesktopConnectionModule({
      storage: {
        read: async () => stored,
        write: async (next) => { stored = next; },
        clear: async () => { stored = null; },
      },
      remote: {
        createPairing: async (device) => ({
          sessionId: 'pairing-session',
          pollToken: 'poll-token',
          deviceCredential: 'device-credential',
          deviceId: device.deviceId,
          deviceName: device.deviceName,
          qrPayload: 'aira://desktop-login',
          expiresAt: Date.parse('2026-07-14T02:00:00.000Z'),
          pollIntervalMs: 1000,
        }),
        pollPairing: async () => ({
          status: 'confirmed',
          account: {
            uid: 'paired-user',
            uidSuffix: 'd-user',
            displayName: 'Paired User',
            avatarUri: '',
          },
          membership: {
            plan: 'pro',
            status: 'active_pro',
            expiresAt: 0,
            checkedAt: '2026-07-14T01:00:00.000Z',
          },
          confirmedAt: Date.parse('2026-07-14T01:00:00.000Z'),
        }),
        refreshMembership: async () => { throw new Error('unused'); },
        revoke: async () => undefined,
      },
      device: { deviceId: 'stable-device', deviceName: 'Stable Device' },
    });

    const pairing = await module.createPairing();
    const result = await module.pollPairing(pairing);
    const authorized = await module.getAuthorizedSession();

    assert.equal(result.status, 'confirmed');
    assert.equal((await module.getSnapshot()).status, 'connected');
    assert.equal(stored.deviceId, 'stable-device');
    assert.equal(authorized?.deviceCredential, 'device-credential');
  });

  await asyncTest('disconnect revokes only the current Desktop Device Session before clearing storage', async () => {
    let stored = {
      version: 1,
      status: 'connected',
      deviceId: 'logout-device',
      deviceName: 'Logout Device',
      account: {
        uid: 'logout-user',
        uidSuffix: 't-user',
        displayName: 'Logout User',
        avatarUri: '',
      },
      membership: {
        plan: 'pro',
        status: 'active_pro',
        expiresAt: 0,
        checkedAt: '2026-07-14T01:00:00.000Z',
      },
      credential: 'logout-token',
      lastError: null,
    };
    const revoked = [];
    const module = new desktopConnection.AiraDesktopConnectionModule({
      storage: {
        read: async () => stored,
        write: async (next) => { stored = next; },
        clear: async () => { stored = null; },
      },
      remote: {
        createPairing: async () => { throw new Error('unused'); },
        pollPairing: async () => { throw new Error('unused'); },
        refreshMembership: async () => { throw new Error('unused'); },
        revoke: async (session) => { revoked.push(session); },
      },
    });

    const snapshot = await module.disconnectCurrentDevice();
    assert.equal(revoked.length, 1);
    assert.equal(revoked[0].deviceId, 'logout-device');
    assert.equal(snapshot.status, 'disconnected');
    assert.equal(stored, null);
  });

  await asyncTest('failed current-device revoke keeps the Desktop Device Session for retry', async () => {
    let stored = {
      version: 1,
      status: 'connected',
      deviceId: 'retry-logout-device',
      deviceName: 'Retry Logout Device',
      account: { uid: 'retry-logout-user', uidSuffix: 't-user', displayName: 'Retry User', avatarUri: '' },
      membership: { plan: 'pro', status: 'active_pro', expiresAt: 0, checkedAt: '2026-07-14T01:00:00.000Z' },
      credential: 'retry-logout-token',
      lastError: null,
    };
    const module = new desktopConnection.AiraDesktopConnectionModule({
      storage: {
        read: async () => stored,
        write: async (next) => { stored = next; },
        clear: async () => { stored = null; },
      },
      remote: {
        createPairing: async () => { throw new Error('unused'); },
        pollPairing: async () => { throw new Error('unused'); },
        refreshMembership: async () => { throw new Error('unused'); },
        revoke: async () => { throw new Error('offline'); },
      },
    });

    await assert.rejects(module.disconnectCurrentDevice(), /offline/);
    assert.equal(stored.credential, 'retry-logout-token');
    assert.equal((await module.getAuthorizedSession())?.deviceId, 'retry-logout-device');
  });

  await asyncTest('fresh membership snapshot avoids an unnecessary remote refresh', async () => {
    const checkedAt = '2026-07-14T01:00:00.000Z';
    let refreshCalls = 0;
    const stored = {
      version: 1,
      status: 'connected',
      deviceId: 'cached-membership-device',
      deviceName: 'Cached Membership Device',
      account: { uid: 'cached-user', uidSuffix: 'd-user', displayName: 'Cached User', avatarUri: '' },
      membership: { plan: 'pro', status: 'active_pro', expiresAt: 0, checkedAt },
      credential: 'cached-token',
      lastError: null,
    };
    const module = new desktopConnection.AiraDesktopConnectionModule({
      storage: {
        read: async () => stored,
        write: async () => undefined,
        clear: async () => undefined,
      },
      remote: {
        createPairing: async () => { throw new Error('unused'); },
        pollPairing: async () => { throw new Error('unused'); },
        refreshMembership: async () => {
          refreshCalls += 1;
          throw new Error('should not refresh');
        },
        revoke: async () => undefined,
      },
      now: () => Date.parse(checkedAt) + 60_000,
    });

    const snapshot = await module.refreshMembership();
    assert.equal(snapshot.status, 'connected');
    assert.equal(refreshCalls, 0);
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
