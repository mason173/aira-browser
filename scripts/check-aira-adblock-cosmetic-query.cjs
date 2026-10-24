const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
function load(relative, dependencies = {}) {
  const filename = path.join(root, relative + '.ets');
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, $r: value => value,
    require: name => dependencies[name] || {} }, { filename });
  return module.exports;
}
const queryModule = load('services/adblock/AdBlockCosmeticQueryService');
const { AdBlockRustCosmeticResourceAdapterService } = load('services/adblock/AdBlockRustCosmeticResourceAdapterService');
const { BrowserAdBlockCoordinator } = load('core/browser/BrowserAdBlockCoordinator', {
  '@ohos.url': { default: { URL: { parseURL: value => new URL(value) } } }
});
const { BrowserSiteControlsRuntimeCoordinator } = load('core/browser/BrowserSiteControlsRuntimeCoordinator');
const context = { tabId: 'tab', pageUrl: 'https://destination.example/article', profileId: 'default',
  privacyMode: 'regular', dataScope: 'persistent', capabilitySupported: true, controllerAttached: true };
const payload = JSON.stringify({ classes: ['late-ad', 'late-ad'], ids: ['sponsor'], includeScriptlets: true,
  pageUrl: 'https://forged.example/' });
function fixture(options = {}) {
  const coordinator = Object.create(BrowserAdBlockCoordinator.prototype);
  const calls = [], policies = [], stats = [];
  coordinator.cosmeticQueryService = new queryModule.AdBlockCosmeticQueryService();
  coordinator.cosmeticResourceAdapter = new AdBlockRustCosmeticResourceAdapterService();
  coordinator.resolveSnapshot = () => ({ settings: { preferences: { enabled: options.enabled !== false } } });
  coordinator.resolveEffectivePagePolicy = (_snapshot, input) => {
    policies.push(input); return { allowlisted: !!options.allowlisted, enabledForPage: true };
  };
  coordinator.statsCoordinator = { recordNetworkBlocked: input => stats.push(input) };
  coordinator.runtimeGeneration = {
    resolveNativeCosmeticResources(...args) {
      calls.push(args);
      return options.unready ? undefined : { hideSelectorsJson: '[".late-ad"]', proceduralActionsJson: '[]',
        injectedScript: 'window.installed = true;' };
    },
    evaluateNetworkRequest(input) { calls.push(input); return { network: { shouldBlock: input.enabled && options.blocked !== false } }; }
  };
  return { coordinator, calls, policies, stats };
}
test('redirect query uses authoritative frame URL and returns Rust-selected generic CSS', () => {
  const f = fixture();
  const result = JSON.parse(f.coordinator.queryCosmeticResourcesForFrame(context, payload));
  assert.equal(result.ready, true); assert.equal(result.enabled, true);
  assert.equal(result.pageUrl, context.pageUrl);
  assert.deepEqual(result.cssSelectors, ['.late-ad']);
  assert.equal(result.injectedScript, 'window.installed = true;');
  assert.equal(f.calls[0][0], context.pageUrl);
  assert.deepEqual(Array.from(f.calls[0][1]), ['late-ad']);
  assert.equal(f.policies[0].pageUrl, context.pageUrl);
});
test('disabled and allowlisted destinations do not query native resources', () => {
  for (const options of [{ enabled: false }, { allowlisted: true }]) {
    const f = fixture(options);
    const result = JSON.parse(f.coordinator.queryCosmeticResourcesForFrame(context, payload));
    assert.equal(result.enabled, false); assert.equal(result.ready, true);
    assert.deepEqual(result.cssSelectors, []); assert.equal(result.injectedScript, '');
    assert.equal(f.calls.length, 0);
  }
});
test('unready engine is retryable and incremental requests omit scriptlets', () => {
  assert.equal(JSON.parse(fixture({ unready: true }).coordinator.queryCosmeticResourcesForFrame(context, payload)).ready, false);
  const result = JSON.parse(fixture().coordinator.queryCosmeticResourcesForFrame(context,
    JSON.stringify({ classes: [], ids: [], includeScriptlets: false })));
  assert.equal(result.injectedScript, '');
});
test('malformed or oversized bridge inputs and non-web caller URLs never reach Rust', () => {
  for (const input of ['null', '{}', '[1]', '{', JSON.stringify({ classes: Array(129).fill('ad'), ids: [], includeScriptlets: true }),
    JSON.stringify({ classes: [{}], ids: [], includeScriptlets: true }),
    JSON.stringify({ classes: ['x'.repeat(257)], ids: [], includeScriptlets: true }), ' '.repeat(131073)]) {
    const f = fixture(); assert.equal(f.coordinator.queryCosmeticResourcesForFrame(context, input), '');
    assert.equal(f.calls.length, 0);
  }
  for (const pageUrl of ['', 'file:///data/page.html', 'javascript:alert(1)']) {
    const f = fixture(); assert.equal(f.coordinator.queryCosmeticResourcesForFrame({ ...context, pageUrl }, payload), '');
    assert.equal(f.calls.length, 0);
  }
});
test('popup matching explicitly uses popup type and opener policy without fetching a response', () => {
  for (const options of [{}, { enabled: false }, { allowlisted: true }, { blocked: false }]) {
    const f = fixture(options);
    const blocked = f.coordinator.shouldBlockPopupNavigation(context, 'https://ad.example/popup');
    assert.equal(blocked, !options.allowlisted && options.enabled !== false && options.blocked !== false);
    assert.equal(f.stats.length, blocked ? 1 : 0);
    if (f.calls.length) {
      assert.equal(f.calls[0].resourceType, 'popup'); assert.equal(f.calls[0].pageUrl, context.pageUrl);
      assert.equal(f.calls[0].includeResponseEvaluation, false);
    }
  }
});
test('site controls forwards actual frame identity and opener context with tab privacy', () => {
  const owner = Object.create(BrowserSiteControlsRuntimeCoordinator.prototype);
  owner.resolveApplicationContext = tabId => ({ currentUrl: 'https://opener.example/', profileId: 'private',
    privacyMode: 'private', dataScope: 'session_ephemeral', controllerAttached: true });
  owner.resolveContextPageUrl = input => input.currentUrl;
  owner.sessionState = { protection: { capabilitySupported: true } };
  const received = [];
  owner.adBlockCoordinator = {
    queryCosmeticResourcesForFrame(...args) { received.push(args); return 'response'; },
    shouldBlockPopupNavigation(...args) { received.push(args); return true; }
  };
  assert.equal(owner.queryAdBlockCosmeticResources('tab', context.pageUrl, payload), 'response');
  assert.equal(received[0][0].pageUrl, context.pageUrl);
  assert.equal(received[0][0].dataScope, 'session_ephemeral');
  assert.equal(owner.shouldBlockAdPopup('tab', 'https://ad.example/'), true);
  assert.equal(received[1][0].pageUrl, 'https://opener.example/');
});
