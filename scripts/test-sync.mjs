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

try {
  const { resolveAiraDesktopSyncStatus } = await vite.ssrLoadModule(
    '/src/features/sync/bookmarks/desktopSyncEligibility.ts',
  );
  const login = await vite.ssrLoadModule('/src/popup/desktopLogin.ts');

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

  console.log(`${passed} sync tests passed`);
} finally {
  await vite.close();
}
