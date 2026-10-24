// Replay the production synchronous ArkWeb bridge and callback guards without a browser or device.
// The native caller-frame URL is the authority even while tab navigation state is still stale.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function evaluate(source, filename, dependencies = {}) {
  const module = { exports: {} };
  const code = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports,
    require(name) {
      if (name in dependencies) return dependencies[name];
      throw new Error('Unexpected dependency: ' + name);
    }
  }, { filename });
  return module.exports;
}

function load(relative, dependencies = {}) {
  const filename = path.join(root, relative + '.ets');
  return evaluate(fs.readFileSync(filename, 'utf8'), filename, dependencies);
}

const hostPath = path.join(root, 'core/web/HostedWebNode.ets');
const hostSource = fs.readFileSync(hostPath, 'utf8');
function productionSection(start, end) {
  const startOffset = hostSource.indexOf(start);
  const endOffset = hostSource.indexOf(end, startOffset);
  assert.ok(startOffset >= 0 && endOffset > startOffset, 'production bridge section not found');
  return hostSource.slice(startOffset, endOffset);
}
const { HostedWebNodeNativeBridge, buildTrackedHostedWebNodeConfig, registeredMethods } = evaluate(
  'const HOSTED_WEB_NODE_NOOP_USER_SCRIPT_BRIDGE = {};\n' +
  productionSection('const HOSTED_WEB_NATIVE_BRIDGE_METHODS:', 'const HOSTED_WEB_NATIVE_BRIDGE_ALIAS_SCRIPT:') +
  productionSection('class HostedWebNodeNativeBridge {', 'const HOSTED_WEB_NODE_NOOP_NATIVE_BRIDGE:') +
  productionSection('function buildTrackedHostedWebNodeConfig(', 'function hostedWebTouchPhase(') +
  '\nmodule.exports = { HostedWebNodeNativeBridge, buildTrackedHostedWebNodeConfig, ' +
  'registeredMethods: HOSTED_WEB_NATIVE_BRIDGE_METHODS };', hostPath
);
const { buildGenerationBoundHostedWebNodeCallbacks } = load('core/browser/BrowserHostedWebNodeGenerationCallbacks');
const loggedFailures = [];
const { BrowserWebEventHostCoordinator } = load('core/browser/BrowserWebEventHostCoordinator', {
  '@kit.PerformanceAnalysisKit': { hilog: { warn: (...args) => loggedFailures.push(args) } },
  '../../services/web/BrowserWebNavigationGuardService': { sharedBrowserWebNavigationGuardService: {} }
});

function fixture(options = {}) {
  const queries = [];
  const controller = { getLastJavascriptProxyCallingFrameUrl() {
    if (options.frameFailure) throw new Error('ArkWeb caller unavailable');
    return options.frameUrl ?? 'https://destination.example/article';
  } };
  const bridge = new HostedWebNodeNativeBridge();
  const callback = (tabId, frameUrl, payloadJson) => {
    queries.push({ tabId, frameUrl, payloadJson });
    if (options.handlerFailure) throw new Error('Cosmetic engine unavailable');
    return options.response ?? '{"cssSelectors":[".ad"]}';
  };
  const config = { tabId: 'tab', controller, callbacks: { onAdBlockCosmeticQuery: callback } };
  bridge.bind(config);
  return { bridge, controller, queries, callback, config };
}

test('the registered synchronous method passes the actual caller frame instead of a claimed URL', () => {
  assert.ok(registeredMethods.includes('adBlockCosmeticQuery'));
  const f = fixture();
  const payload = JSON.stringify({ pageUrl: 'https://stale.example/start', classes: ['ad'] });
  assert.equal(f.bridge.adBlockCosmeticQuery(payload), '{"cssSelectors":[".ad"]}');
  assert.deepEqual(f.queries, [{ tabId: 'tab', frameUrl: 'https://destination.example/article', payloadJson: payload }]);
});

test('unbound and released bridges cannot call the engine or read a retired controller', () => {
  const unbound = new HostedWebNodeNativeBridge();
  assert.equal(unbound.adBlockCosmeticQuery('{}'), '');
  const f = fixture();
  f.bridge.unbind();
  f.controller.getLastJavascriptProxyCallingFrameUrl = () => assert.fail('released controller read');
  assert.equal(f.bridge.adBlockCosmeticQuery('{}'), '');
  assert.equal(f.queries.length, 0);
});

test('missing caller identity and native or handler failures return an empty response', () => {
  for (const options of [{ frameUrl: '' }, { frameUrl: '  ' }, { frameFailure: true }, { handlerFailure: true }]) {
    const f = fixture(options);
    assert.equal(f.bridge.adBlockCosmeticQuery('{}'), '');
    assert.equal(f.queries.length, options.handlerFailure ? 1 : 0);
  }
});

test('rebinding resolves the new controller and optional callback', () => {
  const f = fixture();
  f.bridge.bind({ tabId: 'next-tab', controller: {
    getLastJavascriptProxyCallingFrameUrl: () => 'https://new.example/path'
  }, callbacks: { onAdBlockCosmeticQuery: f.callback } });
  f.controller.getLastJavascriptProxyCallingFrameUrl = () => assert.fail('old controller read');
  assert.equal(f.bridge.adBlockCosmeticQuery('{}'), '{"cssSelectors":[".ad"]}');
  assert.deepEqual(f.queries, [{ tabId: 'next-tab', frameUrl: 'https://new.example/path', payloadJson: '{}' }]);
  f.bridge.bind({ ...f.config, callbacks: {} });
  assert.equal(f.bridge.adBlockCosmeticQuery('{}'), '');
});

test('generation guards reject retired nodes and a different tab without querying the engine', () => {
  const f = fixture();
  let activeGeneration = 1;
  const guarded = buildGenerationBoundHostedWebNodeCallbacks('tab', 1, f.config.callbacks,
    (tabId, generation) => tabId === 'tab' && generation === activeGeneration);
  f.bridge.bind({ ...f.config, callbacks: guarded });
  assert.equal(f.bridge.adBlockCosmeticQuery('{}'), '{"cssSelectors":[".ad"]}');
  assert.equal(guarded.onAdBlockCosmeticQuery('another-tab', 'https://example.com', '{}'), '');
  activeGeneration = 2;
  assert.equal(f.bridge.adBlockCosmeticQuery('{}'), '');
  assert.equal(f.queries.length, 1);
});

test('event host preserves strings and contains engine errors or missing handlers', () => {
  const host = new BrowserWebEventHostCoordinator({});
  const args = ['tab', 'https://destination.example', '{"classes":["ad"]}'];
  const observed = [];
  const callbacks = host.buildCallbacks({ onAdBlockCosmeticQuery: (...values) => {
    observed.push(values);
    return '{"cssSelectors":[".ad"]}';
  } });
  assert.equal(callbacks.onAdBlockCosmeticQuery(...args), '{"cssSelectors":[".ad"]}');
  assert.deepEqual(observed, [args]);
  const failuresBefore = loggedFailures.length;
  const failing = host.buildCallbacks({ onAdBlockCosmeticQuery: () => { throw new Error('engine failed'); } });
  assert.equal(failing.onAdBlockCosmeticQuery(...args), '');
  assert.equal(loggedFailures.length, failuresBefore + 1);
  assert.equal(host.buildCallbacks({}).onAdBlockCosmeticQuery(...args), '');
  assert.equal(host.buildCallbacks({ onAdBlockCosmeticQuery: () => undefined }).onAdBlockCosmeticQuery(...args), '');
});

test('tracked Web configs retain the query callback and controller disposal releases the bridge', () => {
  const f = fixture();
  const tracked = buildTrackedHostedWebNodeConfig(f.config, {
    rememberWebController() {}, rememberDocumentScripts() {}, rememberAppearancePolicy() {},
    rememberRuntimeSecurityPolicy() {}, bindHostedNativeBridge: () => f.bridge
  });
  assert.equal(tracked.callbacks.onAdBlockCosmeticQuery, f.callback);
  const dispose = productionSection('  dispose(): void {', '\nfunction buildHostedWebAppearancePolicySignature(');
  assert.match(dispose, /this\.hostedNativeBridge\.unbind\(\)/);
});
