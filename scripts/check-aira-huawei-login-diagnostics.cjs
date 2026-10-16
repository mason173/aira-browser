#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');

// Run the real activation -> auth adapter -> error presentation chain. Only the
// device SDK and unrelated persistence/identity-change boundaries are replaced.
function fixture(failure = '', originalError = Object.assign(new Error('Parameter check failed.'), { code: 401 })) {
  const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
  const modules = new Map();
  const logs = [];
  const calls = { reset: 0, signIn: 0, save: 0 };
  const failAt = (stage) => { if (failure === stage) throw originalError; };
  const user = { getUid: () => 'fixture-user', getDisplayName: () => 'Fixture', getPhotoUrl: () => '' };
  const sdk = { auth: {
    async signOut() { calls.reset++; failAt('session-reset'); },
    async getCurrentUser() { failAt('cached-user-read'); return null; },
    async signIn() { calls.signIn++; failAt('agc-sign-in'); return { getUser: () => user }; }
  } };
  const mocks = {
    '@kit.AccountKit': {},
    '@kit.PerformanceAnalysisKit': { hilog: { warn(...args) { logs.push(args.join(' ')); } } },
    '@kit.ArkTS': { util: { generateRandomUUID: () => 'fixture-state' } },
    'app/runtime/AppRuntimeContext': { AppRuntimeContext: { getUIAbilityContext: () => ({}) } },
    'common/config/AiraDistributionCapabilityOwner': {
      AIRA_DISTRIBUTION_CAPABILITY_OWNER: { isAvailable: () => true }
    },
    'common/config/AiraLocalTestAuth': { resolveAiraLocalTestIdentity: () => undefined },
    'platform/huawei/HuaweiAgcSdkLoader': { sharedHuaweiAgcSdkLoader: { load: async () => sdk } },
    'services/sync/HuaweiCloudSyncInitService': { HuaweiCloudSyncInitService: class {
      async initializeAuth() { failAt('auth-initialize'); }
    } },
    'services/sync/AiraSyncConfigStore': { AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME: 'fixture' },
    'services/account/AiraAccountUnionLinkFunctionService': { AiraAccountUnionLinkFunctionService: class {
      async linkUnionId() { return true; }
    } }
  };
  function load(relative) {
    if (mocks[relative]) return mocks[relative];
    if (modules.has(relative)) return modules.get(relative).exports;
    const filename = path.join(sourceRoot, relative + '.ets');
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const module = { exports: {} };
    modules.set(relative, module);
    vm.runInNewContext(code, { module, exports: module.exports, require(name) {
      if (mocks[name]) return mocks[name];
      if (!name.startsWith('.')) throw new Error('Unexpected native import: ' + name);
      const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(relative), name));
      return load(resolved);
    } }, { filename });
    return module.exports;
  }
  const { SyncExperienceProviderActivation } = load('core/sync/SyncExperienceProviderActivation');
  const activation = new SyncExperienceProviderActivation({
    async initializeAiraSyncSettings() { failAt('settings-initialize'); },
    async saveHuaweiCloudConfig() { calls.save++; failAt('settings-save'); return {}; },
    async checkHuaweiSpaceCapability() { failAt('huawei-space-capability'); },
    async saveHuaweiSpaceConfig() { calls.save++; failAt('settings-save'); return {}; }
  }, async () => { failAt('identity-change'); });
  return { activation, load, calls, logs, sdk };
}

for (const stage of ['settings-initialize', 'auth-initialize', 'session-reset',
  'cached-user-read', 'agc-sign-in', 'settings-save', 'identity-change', 'huawei-space-capability']) {
  test('the failed login screenshot identifies ' + stage + ' and keeps the native error message', async () => {
    const f = fixture(stage);
    const result = stage === 'huawei-space-capability' ?
      await f.activation.signInHuaweiSpaceAccountOnly() : await f.activation.signInHuaweiAccountOnly();
    assert.equal(result.type, 'failed');
    assert.ok(result.message.includes('stage=' + stage), result.message);
    assert.ok(result.message.includes('401'), result.message);
    assert.ok(result.message.includes('Parameter check failed.'), result.message);
    assert.doesNotMatch(result.message, /请确认已登录系统华为账号/);
    assert.ok(f.logs.some(line => line.includes('stage=' + stage) && line.includes('Parameter check failed.')));
    if (stage === 'session-reset' || stage === 'cached-user-read') {
      assert.equal(f.calls.signIn, 0, 'do not claim native login ran when it was never reached');
    }
  });
}

test('successful sign-in keeps the existing reset, authentication and save behavior', async () => {
  const f = fixture();
  const result = await f.activation.signInHuaweiAccountOnly();
  assert.equal(result.type, 'saved');
  assert.deepEqual(f.calls, { reset: 1, signIn: 1, save: 1 });
});

test('a bare 401 does not diagnose an unsigned-in Huawei account or misclassify 4010', () => {
  const f = fixture();
  const { HuaweiCloudSyncErrorMessageService } = f.load('services/sync/HuaweiCloudSyncErrorMessageService');
  const formatter = new HuaweiCloudSyncErrorMessageService();
  assert.doesNotMatch(formatter.formatForDialog({ code: 401 }), /华为账号登录参数|系统华为账号/);
  assert.doesNotMatch(formatter.formatForDialog({ code: 4010 }), /参数检查失败/);
});

test('login diagnostics redact credentials while preserving the native parameter explanation', async () => {
  const error = Object.assign(new Error('Invalid nonce. access_token=private-at refreshToken=private-rt authorizationCode=private-code'), { code: 401 });
  const f = fixture('session-reset', error);
  const result = await f.activation.signInHuaweiAccountOnly();
  const output = result.message + f.logs.join('\n');
  assert.match(output, /Invalid nonce/);
  assert.doesNotMatch(output, /private-at|private-rt|private-code/);
});

test('unknown error objects do not dump arbitrary SDK payloads into login diagnostics', async () => {
  const f = fixture('session-reset', { code: 401, token: 'private-token', user: 'private-user' });
  const result = await f.activation.signInHuaweiAccountOnly();
  assert.match(result.message, /stage=session-reset/);
  assert.doesNotMatch(result.message + f.logs.join('\n'), /private-token|private-user/);
});

test('the screenshot with only code 401 now identifies the failed session reset', async () => {
  const f = fixture('session-reset', { code: 401 });
  const result = await f.activation.signInHuaweiAccountOnly();
  assert.match(result.message, /stage=session-reset, code=401, message=\(no native message\)/);
  assert.equal(f.calls.signIn, 0);
});

test('a secondary reset failure preserves the original sign-in failure and logs both stages', async () => {
  const f = fixture('agc-sign-in');
  f.sdk.auth.signOut = async () => { throw Object.assign(new Error('Reset failed.'), { code: 402 }); };
  const { HuaweiAccountSyncAuthService } = f.load('services/sync/HuaweiAccountSyncAuthService');
  const service = new HuaweiAccountSyncAuthService();
  await assert.rejects(service.signInForBookmarkSync(false), error => {
    assert.equal(error.stage, 'agc-sign-in');
    assert.equal(error.code, 401);
    assert.equal(error.message, 'Parameter check failed.');
    return true;
  });
  assert.ok(f.logs.some(line => line.includes('stage=session-reset, code=402, message=Reset failed.')));
});
