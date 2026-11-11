#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const noop = () => {};
const probe = new Proxy({}, { get: () => noop });

function harness() {
  const timers = [];
  const cache = new Map();
  const stubs = {
    'common/debug/AiraNavForensicsProbe': { AiraNavForensicsProbe: probe },
    'services/web/BrowserSslDecisionCacheRuntime': {},
    'core/browser/BrowserWebActiveSurfaceCoordinator': {},
    'core/resources/AppResourceText': { resolveAppResourceText: value => value },
    'services/web/BrowserWebNavigationGuardService': { sharedBrowserWebNavigationGuardService: {} },
    'data/browser/BrowserNonRestorableNavigationGuardStore': {
      ArkBrowserNonRestorableNavigationGuardStore: class {
        async loadRecords() { return []; }
        async saveRecords() {}
      }
    }
  };
  let now = 100000;
  function load(relative) {
    if (stubs[relative]) return stubs[relative];
    if (cache.has(relative)) return cache.get(relative);
    const exports = {};
    const source = fs.readFileSync(path.join(root, relative + '.ets'), 'utf8');
    const output = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    vm.runInNewContext(output, { exports, $r: id => id, Date: { now: () => now },
      setTimeout: callback => timers.push(callback), clearTimeout: noop,
      require(id) {
        if (id === '@kit.ArkWeb') return { webview: {} };
        if (id === '@kit.PerformanceAnalysisKit') return { hilog: probe };
        assert.ok(id.startsWith('.'), `Unexpected native dependency ${id}`);
        return load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), id)));
      }
    });
    cache.set(relative, exports);
    return exports;
  }
  const { TabRuntimeRegistry } = load('core/tabs/TabRuntimeRegistry');
  let nextController = 0;
  const createController = () => ({ id: ++nextController });
  const registry = new TabRuntimeRegistry(createController);
  const tab = { id: 'search-tab', isHome: false, runtimeState: 'active',
    url: 'https://example.test/search?q=aaaa', pendingUrl: 'https://example.test/search?q=bbbb',
    lastRestorableUrl: 'https://example.test/search?q=aaaa', lastGoodUrl: '',
    title: 'Search', lastRestorableTitle: 'Search', lastGoodTitle: '',
    navigationHistory: ['https://example.test/search?q=aaaa'], navigationIndex: 0,
    webStatePath: 'previous-document.snapshot', webStateUpdatedAt: 1, lastCrashReason: '' };
  registry.ensureRuntime({ tabId: tab.id, windowId: 'main', initialUrl: tab.url,
    pendingUrl: tab.pendingUrl, initialTitle: tab.title, state: tab.runtimeState });
  registry.markControllerAttached(tab.id);
  const originalController = registry.getRuntime(tab.id).controller;
  let visible = false, activeTabId = tab.id, recoveries = 0, failures = 0, releases = 0;
  const port = {
    resolveRuntime: id => registry.getRuntime(id),
    replaceControllerForRuntimeRefresh: id => registry.replaceControllerForProxyRefresh(id, createController()),
    markTabCrashed: (...args) => registry.markRuntimeCrashed(...args)
  };
  const host = {
    getActiveTabId: () => activeTabId,
    canRecoverActiveRenderProcess: () => visible,
    recoverActiveRenderProcess: () => recoveries++,
    applyTabRuntimePatch: (_id, patch) => Object.assign(tab, patch),
    recordRuntimeEvent: noop, appendRestoreTraceBreadcrumb: noop,
    releaseEventContext: noop
  };
  const { BrowserControllerAttachmentRuntimeCoordinator: Coordinator } =
    load('services/web/BrowserControllerAttachmentRuntimeCoordinator');
  const coordinator = new Coordinator({}, port, {
    release(id) { releases++; registry.detachController(id); }
  }, {}, { applyLoadFailurePresentationWithHost() { failures++; } }, {}, {}, {}, host);
  const { BrowserDownloadNavigationStateCoordinator } = load('core/browser/BrowserDownloadNavigationStateCoordinator');
  const { WebRecoveryManager } = load('core/web/WebRecoveryManager');
  const downloadState = new BrowserDownloadNavigationStateCoordinator();
  const recovery = new WebRecoveryManager(downloadState);
  return { coordinator, tab, registry, recovery, downloadState, originalController, load,
    drain: () => { while (timers.length) timers.shift()(); },
    show: () => { visible = true; }, hide: () => { visible = false; },
    select: id => { activeTabId = id; }, advance: ms => { now += ms; },
    counts: () => ({ recoveries, failures, releases }) };
}

test('background renderer exit invalidates and replaces the old runtime without loading hidden pages', () => {
  const h = harness();
  h.coordinator.handleRenderExitedSignal(h.tab.id, h.originalController, 1);
  h.drain();
  assert.equal(h.registry.getRuntime(h.tab.id).hasLiveController, false);
  assert.notEqual(h.registry.getRuntime(h.tab.id).controller, h.originalController);
  assert.equal(h.tab.lastCrashReason, 'render_process_terminated');
  assert.equal(h.tab.pendingUrl, 'https://example.test/search?q=bbbb');
  assert.equal(h.counts().recoveries, 0);
  assert.equal(h.counts().releases, 1);
});

test('visible renderer exit requests recovery once and stale duplicate callbacks cannot destroy its replacement', () => {
  const h = harness();
  h.show();
  h.coordinator.handleRenderExitedSignal(h.tab.id, h.originalController, 2);
  const replacement = h.registry.getRuntime(h.tab.id).controller;
  h.coordinator.handleRenderExitedSignal(h.tab.id, h.originalController, 2);
  h.drain();
  assert.equal(h.counts().recoveries, 1);
  assert.equal(h.counts().releases, 1);
  assert.equal(h.registry.getRuntime(h.tab.id).controller, replacement);
});

test('returning after a background renderer loss selects a fresh attachment instead of live-page reuse', () => {
  const h = harness();
  h.advance(30 * 60 * 1000);
  h.coordinator.handleRenderExitedSignal(h.tab.id, h.originalController, 3);
  h.show();
  const { BrowserRuntimeLifecycleCoordinator } = h.load('core/browser/BrowserRuntimeLifecycleCoordinator');
  const resolution = new BrowserRuntimeLifecycleCoordinator().resolveActiveRuntime({
    ensureTabRuntime: tab => h.registry.ensureRuntime({ tabId: tab.id, windowId: 'main',
      initialUrl: tab.url, initialTitle: tab.title, pendingUrl: tab.pendingUrl,
      state: tab.runtimeState, lastCrashReason: tab.lastCrashReason })
  }, { getActiveTab: tabs => tabs[0] }, [h.tab], h.tab.id, 'main', false);
  assert.equal(resolution.shouldReuseLiveRuntime, false);
  assert.equal(resolution.shouldWaitForControllerAttachRestore, true);
  assert.notEqual(resolution.runtime.controller, h.originalController);
});

test('an exit notification from an intentionally detached page cannot create a new runtime', () => {
  const h = harness();
  h.registry.detachController(h.tab.id);
  h.coordinator.handleRenderExitedSignal(h.tab.id, h.originalController, 1);
  h.drain();
  assert.equal(h.counts().releases, 0);
  assert.equal(h.counts().recoveries, 0);
  assert.equal(h.registry.getRuntime(h.tab.id).controller, h.originalController);
});

test('closing, replacing, hiding or switching away cancels queued recovery', () => {
  for (const change of ['close', 'replace', 'hide', 'switch']) {
    const h = harness();
    h.show();
    h.coordinator.handleRenderExitedSignal(h.tab.id, h.originalController, 1);
    if (change === 'close') h.registry.removeRuntime(h.tab.id);
    if (change === 'replace') h.registry.replaceControllerForProxyRefresh(h.tab.id, {});
    if (change === 'hide') h.hide();
    if (change === 'switch') h.select('another-tab');
    h.drain();
    assert.equal(h.counts().recoveries, 0, change);
  }
});

test('repeated renderer crashes stop automatic reloads and leave a retry surface', () => {
  const h = harness();
  h.show();
  h.coordinator.handleRenderExitedSignal(h.tab.id, h.originalController, 2);
  h.drain();
  h.registry.markControllerAttached(h.tab.id);
  h.coordinator.handleRenderExitedSignal(h.tab.id, h.registry.getRuntime(h.tab.id).controller, 2);
  h.drain();
  assert.equal(h.counts().recoveries, 1);
  assert.equal(h.counts().failures, 1);
});

test('renderer recovery loads the latest requested search instead of restoring the old document snapshot', () => {
  const h = harness();
  h.tab.lastCrashReason = 'render_process_terminated';
  h.tab.runtimeState = 'crashed';
  const plan = h.recovery.buildRestorePlan(h.tab, 'crash_restore');
  assert.equal(plan.targetUrl, h.tab.pendingUrl);
  assert.equal(plan.attemptSnapshotRestore, false);
  assert.equal(plan.snapshotPath, '');
  h.tab.lastCrashReason = '';
  assert.equal(h.recovery.buildRestorePlan(h.tab, 'tab_switch').attemptSnapshotRestore, true);
});

test('renderer recovery keeps the download guard and does not replay a rejected download URL', () => {
  const h = harness();
  h.tab.lastCrashReason = 'render_process_terminated';
  h.tab.pendingUrl = 'https://example.test/download.zip';
  h.downloadState.markDownloadUrlHandled(h.tab.pendingUrl);
  assert.equal(h.recovery.buildRestorePlan(h.tab, 'crash_restore').targetUrl, h.tab.url);
});

test('ordinary background/foreground transitions resume paused timers, including failed resume retries', () => {
  const { planArkWebBackgroundTimerCommand: plan } = harness().load('core/browser/BrowserArkWebBackgroundTimerPolicy');
  const background = plan(false, [], false, 'process_background');
  assert.equal(background.command, 'pause');
  assert.equal(plan(true, [], true, 'process_foreground').command, 'resume');
  assert.equal(plan(false, [], true, 'process_foreground').command, 'resume');
  assert.equal(plan(false, [], false, 'process_foreground').command, 'none');
});

// After Hvigor, exercise the real native binding and both callback adapters too.
// This catches a missing onRenderExited at any hop, even when the recovery unit tests pass.
if (process.argv[2]) {
  test('compiled Web renderer-exit event reaches recovery through the tracked config and event host', () => {
    const mode = process.argv[2];
    assert.ok(['debug', 'release'].includes(mode));
    const file = path.resolve(root, '../../../build/default/cache/default',
      `default@CompileArkTS/esmodule/${mode}/entry/src/main/ets/core/web/HostedWebNode.ts`);
    const source = fs.readFileSync(file, 'utf8');
    const functions = ['HostedWebNodeBuilder', 'buildTrackedHostedWebNodeConfig'].map(name => {
      const declaration = source.match(new RegExp(`function ${name}\\([^]*?\\n}`))?.[0];
      assert.ok(declaration, name);
      return `export ${declaration}`;
    }).join('\n');
    const attrs = {};
    const enums = new Proxy({}, { get: (_target, key) => key });
    const globals = {
      exports: {}, Stack: probe,
      Web: new Proxy({}, { get: (_target, key) => value => { attrs[key] = value; } }),
      SafeAreaType: enums, SafeAreaEdge: enums, OverScrollMode: enums,
      BrowserWebAttributeModifier: class {},
      resolveHostedWebAppearancePolicy: () => ({}), resolveHostedWebNestedScrollOptions: () => ({}),
      HOSTED_WEB_NODE_NOOP_NATIVE_BRIDGE: {}, HOSTED_WEB_NATIVE_BRIDGE_NAME: 'test',
      HOSTED_WEB_NATIVE_BRIDGE_METHODS: [],
      buildHostedWebDocumentStartScripts: () => [], buildHostedWebDocumentEndScripts: () => [],
      applyHostedWebSafeBrowsing: noop, configureHostedWebBackForwardCache: noop,
      AiraLoadScrollJankProbe: { beginUiTask: noop, endUiTask: noop }
    };
    vm.runInNewContext(ts.transpileModule(functions, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText, globals);
    const h = harness();
    const { BrowserWebEventHostCoordinator } = h.load('core/browser/BrowserWebEventHostCoordinator');
    const callbacks = new BrowserWebEventHostCoordinator().buildCallbacks({
      onControllerAttached: noop,
      onRenderExited: (id, event, controller) =>
        h.coordinator.handleRenderExitedSignal(id, controller, event.renderExitReason)
    });
    const config = globals.exports.buildTrackedHostedWebNodeConfig({
      tabId: h.tab.id, controller: h.originalController, callbacks
    }, probe);
    globals.exports.HostedWebNodeBuilder.call({
      observeComponentCreation2: callback => callback(1, true)
    }, config);
    attrs.onControllerAttached();
    attrs.onRenderExited?.({ renderExitReason: 1 });
    assert.equal(h.registry.getRuntime(h.tab.id).hasLiveController, false,
      'A renderer killed in the background must not remain falsely live');
    assert.equal(h.tab.lastCrashReason, 'render_process_terminated');
    h.drain();
    assert.equal(h.counts().recoveries, 0, 'A hidden Web must not be eagerly reloaded');
  });
}
