#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const window = {
  WindowStatusType: { UNDEFINED: 0, FULL_SCREEN: 1, MAXIMIZE: 2, MINIMIZE: 3, FLOATING: 4, SPLIT_SCREEN: 5 },
  MaximizePresentation: { EXIT_IMMERSIVE: 1, ENTER_IMMERSIVE: 2 }
};
const cache = new Map();

function evaluate(source, globals = {}, requireModule = () => ({})) {
  const module = { exports: {} };
  const code = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require: requireModule, ...globals });
  return module.exports;
}

function load(relative) {
  const filename = path.resolve(root, relative + '.ets');
  if (cache.has(filename)) return cache.get(filename);
  const exports = evaluate(fs.readFileSync(filename, 'utf8'), {}, (id) => {
    if (id === '@kit.ArkUI') return { window };
    if (id === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
    return load(path.relative(root, path.resolve(path.dirname(filename), id)));
  });
  cache.set(filename, exports);
  return exports;
}

const { BrowserStartupWindowService } = load('services/browser/BrowserStartupWindowService');
const { BrowserWindowPresentationProfileCoordinator } = load('core/browser/BrowserWindowPresentationProfile');
const ability = fs.readFileSync(path.join(root, 'app/abilities/EntryAbility.ets'), 'utf8');
const readinessMethod = ability.slice(ability.indexOf('  private waitForInitialRouteReadiness('),
  ability.indexOf('  private resolveInitialRoute(')).replace('private ', '');

function fixture(input = { platformDeviceType: '2in1' }) {
  const profile = new BrowserWindowPresentationProfileCoordinator();
  let shellFamily;
  let revision = 0;
  const native = {
    status: window.WindowStatusType.FLOATING, width: 900, calls: [],
    isInFreeWindowMode: () => true,
    getWindowStatus() { return this.status; },
    async maximize(presentation) {
      this.calls.push(presentation);
      this.status = window.WindowStatusType.MAXIMIZE;
      this.width = 1600;
    }
  };
  const prepared = [];
  const facts = [];
  const { StartupHarness } = evaluate(`export class StartupHarness { ${readinessMethod} }`, {
    BrowserWindowRuntime: {
      connectShellPresentation: () => ({ snapshot: () => ({ shellFamily }) }),
      prepareInitialShellPresentation: (_storage, viewport) => prepared.push(viewport)
    },
    resolveBrowserWindowSessionShellPresentationBinding: (binding) => binding
  });
  const host = Object.assign(new StartupHarness(), {
    launchReadinessPromise: Promise.resolve(), initialExternalShareIngressReadiness: Promise.resolve(),
    windowStageLifecycleGeneration: 1, pageStorage: {},
    browserStartupWindowService: new BrowserStartupWindowService(),
    browserWindowPresentationProfileInputService: { resolve: (win) => ({ windowWidthVp: win.width }) },
    waitForInitialBrowserPresentationFacts: async () => {},
    reconcileBrowserWindowPresentationProfile() {
      shellFamily = profile.reconcile({ ...input, windowWidthVp: native.width }, {
        phoneShellAvailable: true, largeScreenShellAvailable: true
      }, ++revision).shellFamily;
    },
    reconcileBrowserLargeScreenWindowFacts: async (win) => { facts.push(win.width); },
    resolveInitialRoute: () => 'app/pages/BrowserShellPage'
  });
  return { host, native, prepared, facts, input,
    run: (source = 'create') => host.waitForInitialRouteReadiness(native, 1, source) };
}

for (const [name, input, maximize] of [
  ['PC', { platformDeviceType: 'pc' }, true],
  ['2in1', { platformDeviceType: '2in1' }, true],
  ['tablet desktop override', { platformDeviceType: 'tablet', tabletInterfaceMode: 'desktop' }, true],
  ['tablet with pointer', { platformDeviceType: 'tablet', pointerAvailable: true }, true],
  ['tablet touch override', { platformDeviceType: 'tablet', tabletInterfaceMode: 'touch', pointerAvailable: true }, false],
  ['tablet without pointer', { platformDeviceType: 'tablet' }, false],
  ['phone', { platformDeviceType: 'phone' }, false],
  ['car with desktop preference', { platformDeviceType: 'car', tabletInterfaceMode: 'desktop' }, false]
]) {
  test(`${name}: startup follows the actual Shell Family and prepares its final viewport`, async () => {
    const f = fixture(input);
    assert.equal(await f.run(), 'app/pages/BrowserShellPage');
    assert.deepEqual(f.native.calls, maximize ? [window.MaximizePresentation.EXIT_IMMERSIVE] : []);
    assert.equal(f.prepared[0].windowWidthVp, maximize ? 1600 : 900);
    assert.deepEqual(f.facts, maximize ? [1600] : []);
  });
}

test('startup waits for the persisted tablet interface preference before choosing the window size', async () => {
  const f = fixture({ platformDeviceType: 'tablet', tabletInterfaceMode: 'auto' });
  let ready;
  f.host.launchReadinessPromise = new Promise((resolve) => { ready = resolve; });
  const launch = f.run();
  await Promise.resolve();
  assert.equal(f.native.calls.length, 0);
  assert.equal(f.prepared.length, 0);
  f.input.tabletInterfaceMode = 'desktop';
  ready();
  await launch;
  assert.equal(f.native.calls.length, 1);
  assert.equal(f.prepared[0].windowWidthVp, 1600);
});

test('restoring a WindowStage preserves its window size', async () => {
  const f = fixture();
  await f.run('restore');
  assert.equal(f.native.calls.length, 0);
  assert.equal(f.prepared[0].windowWidthVp, 900);
});

test('startup preserves split-screen, fullscreen, maximized, minimized and non-free windows', async () => {
  for (const status of [0, 1, 2, 3, 5]) {
    const f = fixture();
    f.native.status = status;
    await f.run();
    assert.equal(f.native.calls.length, 0);
  }
  const f = fixture();
  f.native.isInFreeWindowMode = () => false;
  await f.run();
  assert.equal(f.native.calls.length, 0);
});

test('unsupported APIs and failed maximization do not prevent the first page from loading', async () => {
  for (const method of ['isInFreeWindowMode', 'getWindowStatus', 'maximize', 'async maximize']) {
    const f = fixture();
    if (method === 'async maximize') {
      f.native.maximize = () => Promise.reject(new Error('unavailable'));
    } else {
      f.native[method] = () => { throw new Error('unavailable'); };
    }
    assert.equal(await f.run(), 'app/pages/BrowserShellPage');
    assert.equal(f.prepared[0].windowWidthVp, 900);
  }
});

test('a destroyed WindowStage cannot maximize or publish a viewport after readiness completes', async () => {
  const f = fixture();
  f.host.windowStageLifecycleGeneration += 1;
  await f.run();
  assert.equal(f.native.calls.length, 0);
  assert.equal(f.prepared.length, 0);
});

test('the initial viewport waits for maximization, and a destroyed stage cannot publish its result', async () => {
  for (const destroyed of [false, true]) {
    const f = fixture();
    let finish;
    let entered;
    const started = new Promise((resolve) => { entered = resolve; });
    f.native.maximize = () => new Promise((resolve) => {
      finish = () => { f.native.width = 1600; resolve(); };
      entered();
    });
    const launch = f.run();
    await started;
    assert.equal(f.prepared.length, 0);
    if (destroyed) f.host.windowStageLifecycleGeneration += 1;
    finish();
    await launch;
    assert.equal(f.prepared.length, destroyed ? 0 : 1);
    assert.equal(f.facts.length, destroyed ? 0 : 1);
  }
});
