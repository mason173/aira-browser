// Replay the production subscription pipeline without contacting a server or capturing a screen.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const HOUR = 60 * 60 * 1000;
const BASE = 'https://lists.example/filters/main.txt';

function load(relative, dependencies = {}, unused = false) {
  const filename = path.join(root, relative + '.ets');
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, Date, $r: name => name,
    require(name) {
      if (name in dependencies) return dependencies[name];
      if (/AdBlockSubscription(?:Preprocessor|Policy)Service$/.test(name)) {
        return load('services/adblock/' + path.basename(name), dependencies);
      }
      if (unused) return {};
      throw new Error('Unexpected dependency: ' + name);
    }
  }, { filename });
  return module.exports;
}

function fetchFixture(documents) {
  const requests = [];
  let destroyed = 0;
  const { AdBlockRuleListFetchService } = load('services/adblock/AdBlockRuleListFetchService', {
    '@kit.NetworkKit': { http: {
      RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' },
      createHttp() { return {
        async request(url, options) {
          requests.push({ url, options });
          if (!(url in documents)) throw new Error('Fixture download failed: ' + url);
          const body = documents[url];
          if (body instanceof Error) throw body;
          return { responseCode: 200, result: body };
        },
        destroy() { destroyed++; }
      }; }
    } }
  });
  return { service: new AdBlockRuleListFetchService(), requests, destroyed: () => destroyed };
}

function source(id, patch = {}) {
  return { id, url: BASE.replace('main', id), sourceType: 'remote', enabled: true,
    ruleCount: 3, lastUpdatedAt: Date.now() - 2 * 24 * HOUR, updatedAt: Date.now() - 2 * 24 * HOUR,
    lastError: '', updateIntervalMs: 24 * HOUR, ...patch };
}

function coordinatorFixture(sources) {
  const { AdBlockRuleSourceCoordinator } = load('core/adblock/AdBlockRuleSourceCoordinator', {}, true);
  const coordinator = Object.create(AdBlockRuleSourceCoordinator.prototype);
  const calls = [];
  const settings = { preferences: { enabled: true, updateOnForeground: true }, customRuleSources: sources };
  coordinator.repository = { getSettings: () => settings };
  coordinator.fetchAndStore = async (url, item) => {
    calls.push(item.id);
    return { settings, success: true, message: item.id };
  };
  return { coordinator, calls, settings };
}

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

function transactionFixture() {
  const { AdBlockRuleSourceMetadataService } = load('services/adblock/AdBlockRuleSourceMetadataService');
  const { AdBlockRuleSourceCoordinator } = load('core/adblock/AdBlockRuleSourceCoordinator', {
    '../../core/resources/AppResourceText': { resolveAppResourceText: value => value },
    '../../features/adblock/AdBlockThirdPartyRuleSourceCatalog': { isAdBlockThirdPartyRuleSourceId: () => false }
  }, true);
  const metadata = new AdBlockRuleSourceMetadataService();
  const original = source(metadata.buildSource(BASE, 'Current').id, { url: BASE, title: 'Current',
    payloadIdentity: 'old', createdAt: 100 });
  const settings = { preferences: { enabled: true, updateOnForeground: true }, customRuleSources: [original] };
  const coordinator = Object.create(AdBlockRuleSourceCoordinator.prototype);
  coordinator.repository = { getSettings: () => settings, initializeMetadata: async () => {},
    ensureRustV1NativeRuleArtifactCleanup: async () => {} };
  coordinator.metadataService = metadata;
  coordinator.canWriteDevicePreference = () => true;
  const requests = [];
  coordinator.fetchService = { fetchSubscription() { const task = deferred(); requests.push(task); return task.promise; } };
  let payload = 'old', staged = '', prior = '';
  coordinator.nativeRuleProvider = {
    async stageSourcePayload(id, text) { staged = text; },
    async validateStagedSourcePayload() { return { identity: staged, networkRuleCount: 1, cosmeticRuleCount: 0, ruleCount: 1 }; },
    async commitStagedSourcePayload() { prior = payload; payload = staged; },
    async rollbackStagedSourcePayload() { payload = prior; },
    async discardStagedSourcePayload() { staged = ''; },
    async completeStagedSourcePayload() {},
    async reconcile() { return {}; },
    async removeSourcePayload() { payload = ''; }
  };
  coordinator.runtimeGeneration = {
    async upsertCustomRuleSource(item) { settings.customRuleSources = [item]; return settings; },
    async removeCustomRuleSource(id) { settings.customRuleSources = settings.customRuleSources.filter(item => item.id !== id); return settings; }
  };
  coordinator.acceptNativeAuthority = async () => true;
  coordinator.activateNativeAuthority = async () => true;
  return { coordinator, settings, requests, original, payload: () => payload };
}

async function waitRequests(fixture, count) {
  for (let index = 0; index < 20 && fixture.requests.length < count; index++) await Promise.resolve();
  assert.equal(fixture.requests.length, count, 'the requested download must have started');
}

test('deleting a source while its refresh downloads cannot resurrect it', async () => {
  const f = transactionFixture();
  const refresh = f.coordinator.refreshSource(f.original.id, {});
  await waitRequests(f, 1);
  await f.coordinator.removeSource(f.original.id, {});
  f.requests[0].resolve({ text: 'stale', updateIntervalMs: HOUR });
  await refresh;
  assert.deepEqual(f.settings.customRuleSources, []);
  assert.equal(f.payload(), '');
});

test('a slower foreground response cannot overwrite a newer manual refresh', async () => {
  const f = transactionFixture();
  const automatic = f.coordinator.autoUpdateDueRemoteSources();
  await waitRequests(f, 1);
  const manual = f.coordinator.refreshSource(f.original.id, {});
  await waitRequests(f, 2);
  f.requests[1].resolve({ text: 'newer', updateIntervalMs: 2 * HOUR });
  await manual;
  f.requests[0].resolve({ text: 'older', updateIntervalMs: HOUR });
  await automatic;
  assert.equal(f.payload(), 'newer');
  assert.equal(f.settings.customRuleSources[0].payloadIdentity, 'newer');
  assert.equal(f.settings.customRuleSources[0].updateIntervalMs, 2 * HOUR);
});

test('a stale failed request cannot replace a later successful refresh status', async () => {
  const f = transactionFixture();
  const older = f.coordinator.refreshSource(f.original.id, {});
  await waitRequests(f, 1);
  const newer = f.coordinator.refreshSource(f.original.id, {});
  await waitRequests(f, 2);
  f.requests[1].resolve({ text: 'newer', updateIntervalMs: HOUR });
  await newer;
  const current = { ...f.settings.customRuleSources[0] };
  f.requests[0].reject(new Error('stale network failure'));
  await older;
  assert.equal(f.payload(), 'newer');
  assert.equal(f.settings.customRuleSources[0].lastError, '');
  assert.equal(f.settings.customRuleSources[0].lastAttemptAt, current.lastAttemptAt);
});

test('removing and re-adding the same URL invalidates the old in-flight generation', async () => {
  const f = transactionFixture();
  const older = f.coordinator.refreshSource(f.original.id, {});
  await waitRequests(f, 1);
  await f.coordinator.removeSource(f.original.id, {});
  const added = f.coordinator.addSource(BASE, {});
  await waitRequests(f, 2);
  f.requests[1].resolve({ text: 're-added', updateIntervalMs: HOUR });
  await added;
  f.requests[0].resolve({ text: 'removed-generation', updateIntervalMs: HOUR });
  await older;
  assert.equal(f.payload(), 're-added');
  assert.equal(f.settings.customRuleSources[0].payloadIdentity, 're-added');
});

test('a generation superseded during native commit rolls back before the newer payload is staged', async () => {
  const f = transactionFixture();
  const enteredCommit = deferred();
  const resumeCommit = deferred();
  const native = f.coordinator.nativeRuleProvider;
  const originalCommit = native.commitStagedSourcePayload;
  const originalRollback = native.rollbackStagedSourcePayload;
  let rollbacks = 0;
  native.commitStagedSourcePayload = async () => {
    await originalCommit();
    enteredCommit.resolve();
    await resumeCommit.promise;
  };
  native.rollbackStagedSourcePayload = async () => { rollbacks++; await originalRollback(); };
  const older = f.coordinator.refreshSource(f.original.id, {});
  await waitRequests(f, 1);
  f.requests[0].resolve({ text: 'older', updateIntervalMs: HOUR });
  await enteredCommit.promise;
  const newer = f.coordinator.refreshSource(f.original.id, {});
  await waitRequests(f, 2);
  f.requests[1].resolve({ text: 'newer', updateIntervalMs: HOUR });
  resumeCommit.resolve();
  const oldResult = await older;
  await newer;
  assert.equal(oldResult.success, false);
  assert.equal(oldResult.message, '');
  assert.equal(rollbacks, 1);
  assert.equal(f.payload(), 'newer');
  assert.equal(f.settings.customRuleSources[0].payloadIdentity, 'newer');
  assert.equal(f.settings.customRuleSources[0].lastError, '');
});

test('conditional syntax does not activate unsupported or unknown capabilities', async () => {
  const f = fetchFixture({ [BASE]: [
    '!#if ext_ublock && (adguard_ext_chromium || env_firefox)', '||ubo-compatible.example^', '!#endif',
    '!#if cap_user_stylesheet', '||user-origin-only.example^', '!#else', '||author-style-fallback.example^', '!#endif',
    '!#if !future_unknown_capability', '||unknown-if.example^', '!#else', '||unknown-else.example^', '!#endif',
    '!#if ext_abp', '||abp-only.example^', '!#endif', // Present in the current EasyPrivacy preset.
    '!#if false', '!#if env_mobile', '||inactive-nested.example^', '!#else', '||inactive-else.example^',
    '!#endif', '!#endif'
  ].join('\n') });
  const text = await f.service.fetchText(BASE);
  assert.match(text, /ubo-compatible/);
  assert.match(text, /author-style-fallback/);
  assert.doesNotMatch(text, /user-origin-only|unknown-|abp-only|inactive-/);
});

test('malformed conditional stacks reject the refresh instead of importing both arms', async () => {
  for (const text of ['!#if env_mobile\n||ad.example^', '!#else\n||ad.example^',
    '!#if env_mobile\n!#else\n!#else\n!#endif', '!#if env_mobile &&\n||ad.example^\n!#endif',
    '!#if (env_mobile\n||ad.example^\n!#endif', '!#if !'.repeat(50) + 'env_mobile']) {
    await assert.rejects(fetchFixture({ [BASE]: text }).service.fetchText(BASE));
  }
});

test('included files are deduplicated and cannot follow HTTP redirects to another origin', async () => {
  const f = fetchFixture({ [BASE]: '!#include ./child.txt\n!#include child.txt',
    'https://lists.example/filters/child.txt': '||child.example^' });
  const text = await f.service.fetchText(BASE);
  assert.equal(text.match(/child\.example/g).length, 1);
  assert.equal(f.requests.length, 2);
  assert.equal(f.requests[1].options.maxRedirects, 0);
  assert.equal(f.requests[1].options.maxLimit, 5 * 1024 * 1024);
});

test('include depth, count and total downloaded characters have finite budgets', async () => {
  const depthDocs = { [BASE]: '!#include depth0.txt' };
  for (let i = 0; i < 15; i++) depthDocs[`https://lists.example/filters/depth${i}.txt`] = `!#include depth${i + 1}.txt`;
  const deep = fetchFixture(depthDocs);
  await assert.rejects(deep.service.fetchText(BASE), /限制/);
  assert.ok(deep.requests.length <= 9);

  const countDocs = { [BASE]: Array.from({ length: 40 }, (_, i) => `!#include list${i}.txt`).join('\n') };
  for (let i = 0; i < 40; i++) countDocs[`https://lists.example/filters/list${i}.txt`] = '||ads.example^';
  const wide = fetchFixture(countDocs);
  await assert.rejects(wide.service.fetchText(BASE), /限制/);
  assert.equal(wide.requests.length, 32);

  const totalDocs = { [BASE]: Array.from({ length: 6 }, (_, i) => `!#include large${i}.txt`).join('\n') };
  for (let i = 0; i < 6; i++) totalDocs[`https://lists.example/filters/large${i}.txt`] = '!'.repeat(5 * 1024 * 1024);
  await assert.rejects(fetchFixture(totalDocs).service.fetchText(BASE), /总量/);
  await assert.rejects(fetchFixture({ [BASE]: '!'.repeat(5 * 1024 * 1024 + 1) }).service.fetchText(BASE), /5MB/);
});

test('Expires honors list metadata, the earliest child expiry and sane bounds/default', async () => {
  for (const [expires, expected] of [
    ['1 days (update frequency)', 24 * HOUR], ['4 days', 96 * HOUR], ['2 hours', 2 * HOUR],
    ['999 days', 14 * 24 * HOUR], ['0 hours', 24 * HOUR], ['invalid', 24 * HOUR]
  ]) {
    const result = await fetchFixture({ [BASE]: '! Expires: ' + expires + '\n||ad.example^' }).service.fetchSubscription(BASE);
    assert.equal(result.updateIntervalMs, expected, expires);
  }
  const f = fetchFixture({ [BASE]: '! Expires: 4 days\n!#include child.txt',
    'https://lists.example/filters/child.txt': '! Expires: 2 hours\n||ad.example^' });
  assert.equal((await f.service.fetchSubscription(BASE)).updateIntervalMs, 2 * HOUR);
});

test('fresh sources, local sources, disabled sources and recent failures are not downloaded', async () => {
  const f = coordinatorFixture([
    source('fresh', { lastUpdatedAt: Date.now() }), source('local', { sourceType: 'local' }),
    source('disabled', { enabled: false }), source('recent-failure', {
      lastError: 'offline', lastAttemptAt: Date.now() - HOUR / 2, updatedAt: 1 })
  ]);
  await f.coordinator.autoUpdateDueRemoteSources();
  assert.deepEqual(f.calls, []);
  f.settings.preferences.updateOnForeground = false;
  f.settings.customRuleSources = [source('due')];
  await f.coordinator.autoUpdateDueRemoteSources();
  assert.deepEqual(f.calls, []);
});

test('a pre-upgrade payload gets one preprocessing refresh without waiting for ten days', async () => {
  const f = coordinatorFixture([source('old-format', { updateIntervalMs: undefined, lastUpdatedAt: Date.now() })]);
  await f.coordinator.autoUpdateDueRemoteSources();
  assert.deepEqual(f.calls, ['old-format']);
});

test('concurrent foreground callbacks share one download pass and recheck changed sources', async () => {
  const f = coordinatorFixture([source('first'), source('disabled-later'), source('refreshed-later')]);
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  f.coordinator.fetchAndStore = async (url, item) => {
    f.calls.push(item.id);
    await pending;
    return { settings: f.settings, success: true, message: item.id };
  };
  const first = f.coordinator.autoUpdateDueRemoteSources();
  const second = f.coordinator.autoUpdateDueRemoteSources();
  f.settings.customRuleSources[1].enabled = false;
  f.settings.customRuleSources[2].lastUpdatedAt = Date.now();
  release();
  await Promise.all([first, second]);
  assert.deepEqual(f.calls, ['first']);
});

test('failed child download preserves active payload metadata and records an independent retry timestamp', async () => {
  const { AdBlockRuleSourceMetadataService } = load('services/adblock/AdBlockRuleSourceMetadataService');
  const { AdBlockRuleSourceCoordinator } = load('core/adblock/AdBlockRuleSourceCoordinator', {}, true);
  const current = source('current', { url: BASE, title: 'Current', payloadIdentity: 'old-payload',
    nativeNetworkRuleCount: 2, nativeCosmeticRuleCount: 1, createdAt: 100 });
  const settings = { preferences: {}, customRuleSources: [current] };
  const coordinator = Object.create(AdBlockRuleSourceCoordinator.prototype);
  coordinator.repository = { getSettings: () => settings, initializeMetadata: async () => {},
    ensureRustV1NativeRuleArtifactCleanup: async () => {} };
  coordinator.metadataService = new AdBlockRuleSourceMetadataService();
  coordinator.fetchService = fetchFixture({ [BASE]: '||new.example^\n!#include unavailable.txt' }).service;
  let staged = false;
  coordinator.storeRemoteSource = async () => { staged = true; throw new Error('must not publish partial data'); };
  coordinator.runtimeGeneration = { upsertCustomRuleSource: async item => {
    settings.customRuleSources = [item]; return settings;
  } };
  const result = await coordinator.fetchAndStore(BASE, current);
  assert.equal(result.success, false);
  assert.equal(staged, false);
  const failed = settings.customRuleSources[0];
  for (const key of ['payloadIdentity', 'enabled', 'ruleCount', 'nativeNetworkRuleCount',
    'nativeCosmeticRuleCount', 'lastUpdatedAt', 'updateIntervalMs', 'createdAt']) assert.equal(failed[key], current[key], key);
  assert.ok(failed.lastAttemptAt > current.lastUpdatedAt);
  assert.match(failed.lastError, /Fixture download failed/);
  assert.equal(coordinator.shouldAutoUpdateRemoteSource(failed, failed.lastAttemptAt + HOUR - 1), false);
  assert.equal(coordinator.shouldAutoUpdateRemoteSource(failed, failed.lastAttemptAt + HOUR), true);
});

test('only the completely expanded payload and its expiry are committed to the native source', async () => {
  const { AdBlockRuleSourceMetadataService } = load('services/adblock/AdBlockRuleSourceMetadataService');
  const { AdBlockRuleSourceCoordinator } = load('core/adblock/AdBlockRuleSourceCoordinator', {
    '../../core/resources/AppResourceText': { resolveAppResourceText: value => value }
  }, true);
  const oldSource = source('current', { url: BASE, title: 'Current', payloadIdentity: 'old-payload', createdAt: 100 });
  const settings = { preferences: {}, customRuleSources: [oldSource] };
  const coordinator = Object.create(AdBlockRuleSourceCoordinator.prototype);
  coordinator.repository = { getSettings: () => settings, initializeMetadata: async () => {},
    ensureRustV1NativeRuleArtifactCleanup: async () => {} };
  coordinator.metadataService = new AdBlockRuleSourceMetadataService();
  coordinator.fetchService = fetchFixture({ [BASE]: '! Expires: 4 days\n!#include child.txt',
    'https://lists.example/filters/child.txt': '! Expires: 2 hours\n!#if ext_ublock\n||child.example^\n!#endif' }).service;
  const operations = [];
  coordinator.nativeRuleProvider = {
    async stageSourcePayload(id, text) { operations.push('stage'); assert.match(text, /child\.example/); assert.doesNotMatch(text, /!#/); },
    async validateStagedSourcePayload() { operations.push('validate'); return { identity: 'expanded-payload', networkRuleCount: 1, cosmeticRuleCount: 0, ruleCount: 1 }; },
    async commitStagedSourcePayload() { operations.push('commit'); },
    async reconcile() { operations.push('activate'); return {}; },
    async completeStagedSourcePayload() { operations.push('complete'); }
  };
  coordinator.runtimeGeneration = { upsertCustomRuleSource: async item => {
    operations.push('metadata'); settings.customRuleSources = [item]; return settings;
  } };
  coordinator.acceptNativeAuthority = async () => true;
  const result = await coordinator.fetchAndStore(BASE, oldSource);
  assert.equal(result.success, true);
  assert.deepEqual(operations, ['stage', 'validate', 'commit', 'metadata', 'activate', 'complete']);
  const current = settings.customRuleSources[0];
  assert.equal(current.updateIntervalMs, 2 * HOUR);
  assert.equal(current.payloadIdentity, 'expanded-payload');
  assert.equal(current.ruleCount, 1);
  assert.equal(current.lastAttemptAt, current.lastUpdatedAt);
  assert.equal(current.lastError, '');
});

test('repository and runtime copies retain update metadata without manufacturing it for old records', () => {
  const { AdBlockRepository } = load('data/adblock/AdBlockRepository', {}, true);
  const repo = Object.create(AdBlockRepository.prototype);
  const record = source('preserved', { payloadIdentity: 'identity', title: 'Title', createdAt: 1,
    updateIntervalMs: 3 * HOUR, lastAttemptAt: Date.now() - HOUR });
  const normalized = repo.normalizeCustomRuleSource(record);
  const copied = repo.cloneCustomRuleSource(normalized);
  assert.equal(copied.updateIntervalMs, record.updateIntervalMs);
  assert.equal(copied.lastAttemptAt, record.lastAttemptAt);
  assert.equal(repo.normalizeCustomRuleSource({ ...record, updateIntervalMs: undefined }).updateIntervalMs, undefined);
  const { AdBlockRuntimeGenerationCoordinator } = load('core/adblock/AdBlockRuntimeGenerationCoordinator', {}, true);
  const runtime = Object.create(AdBlockRuntimeGenerationCoordinator.prototype);
  const settings = { preferences: {}, customRuleSources: [copied], siteExceptions: [],
    userRules: [], allowlist: [], stats: { dailyProtectionActivity: [] },
    customRules: [], allowlistDomains: [] };
  const copy = runtime.cloneRuntimeSettings(settings).customRuleSources[0];
  assert.equal(copy.updateIntervalMs, record.updateIntervalMs);
  assert.equal(copy.lastAttemptAt, record.lastAttemptAt);
});

test('download expands a nested include before supplying rules to Rust', async () => {
  const f = fetchFixture({ [BASE]: '||root.example^\n!#include child.txt',
    'https://lists.example/filters/child.txt': '!#include nested/leaf.txt\n||child.example^',
    'https://lists.example/filters/nested/leaf.txt': '||leaf.example^' });
  const text = await f.service.fetchText(BASE);
  assert.match(text, /\|\|leaf\.example\^/);
  assert.match(text, /\|\|child\.example\^/);
  assert.equal(f.requests.length, 3);
  assert.equal(f.destroyed(), 3);
});

test('known conditions select only the matching mobile Chromium branch', async () => {
  const f = fetchFixture({ [BASE]: [
    '!#if (env_chromium && env_mobile)', '||mobile.example^',
    '!#if cap_html_filtering', '||html-only.example^', '!#else', '||scriptlet-fallback.example^', '!#endif',
    '!#else', '||desktop.example^', '!#endif',
    '!#if false', '!#include never.txt', '||disabled.example^', '!#endif',
    '!#if env_firefox || ext_ubol', '||unsupported.example^', '!#endif'
  ].join('\n') });
  const text = await f.service.fetchText(BASE);
  assert.match(text, /\|\|mobile\.example\^/);
  assert.match(text, /\|\|scriptlet-fallback\.example\^/);
  assert.doesNotMatch(text, /html-only|desktop|disabled|unsupported|never\.txt/);
  assert.equal(f.requests.length, 1);
});

test('an unavailable included file rejects the entire refresh', async () => {
  const f = fetchFixture({ [BASE]: '||root.example^\n!#include missing.txt' });
  await assert.rejects(f.service.fetchText(BASE));
  assert.equal(f.destroyed(), 2);
});

test('circular, external, absolute and directory-escaping includes are rejected', async () => {
  for (const include of ['main.txt', '../outside.txt', '%2e%2e/outside.txt',
    '/outside.txt', '//elsewhere.example/rules.txt', 'https://elsewhere.example/rules.txt',
    'http://lists.example/rules.txt', 'nested\\outside.txt']) {
    const f = fetchFixture({ [BASE]: '||root.example^\n!#include ' + include });
    await assert.rejects(f.service.fetchText(BASE), undefined, include);
    assert.equal(f.requests.length, 1);
  }
});

test('auto update honors a one-day subscription interval', async () => {
  const f = coordinatorFixture([source('daily')]);
  await f.coordinator.autoUpdateDueRemoteSources();
  assert.deepEqual(f.calls, ['daily']);
});

test('a recent failure retries after one hour instead of waiting ten days', async () => {
  const f = coordinatorFixture([source('failed', { lastUpdatedAt: Date.now() - 20 * 24 * HOUR,
    lastError: 'offline', updatedAt: Date.now() - 2 * HOUR, lastAttemptAt: Date.now() - 2 * HOUR })]);
  await f.coordinator.autoUpdateDueRemoteSources();
  assert.deepEqual(f.calls, ['failed']);
});

test('foreground refresh services all due sources even if the first fails', async () => {
  const f = coordinatorFixture([source('first'), source('second'), source('third')]);
  f.coordinator.fetchAndStore = async (url, item) => {
    f.calls.push(item.id);
    return { settings: f.settings, success: item.id !== 'first', message: item.id };
  };
  await f.coordinator.autoUpdateDueRemoteSources();
  assert.deepEqual(f.calls, ['first', 'second', 'third']);
});
