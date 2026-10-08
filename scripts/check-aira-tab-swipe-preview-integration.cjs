const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');

const drain = () => new Promise(resolve => setImmediate(resolve));
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function clock() {
  let now = 0, sequence = 0;
  const pending = new Map();
  const delays = [];
  return {
    pending, delays,
    setTimeout(callback, delay) {
      delays.push(delay);
      pending.set(++sequence, { callback, due: now + delay });
      return sequence;
    },
    clearTimeout(id) { pending.delete(id); },
    advance(ms) {
      const end = now + ms;
      for (;;) {
        const next = [...pending].filter(([, timer]) => timer.due <= end)
          .sort((a, b) => a[1].due - b[1].due)[0];
        if (!next) break;
        now = next[1].due;
        pending.delete(next[0]);
        next[1].callback();
      }
      now = end;
    }
  };
}
function load(relative, stubs, timers) {
  const filename = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets', relative);
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename, reportDiagnostics: true
  });
  assert.equal((result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
  const module = { exports: {} };
  vm.runInNewContext(result.outputText, {
    module, exports: module.exports,
    require(specifier) {
      assert.ok(Object.hasOwn(stubs, specifier), `Unexpected runtime dependency (including disk/platform IO): ${specifier}`);
      return stubs[specifier];
    },
    setTimeout: timers.setTimeout, clearTimeout: timers.clearTimeout
  }, { filename });
  return module.exports;
}
function captureHarness(outcome = 'success') {
  const timers = clock();
  const calls = [];
  const { BrowserTabSwipePreviewCaptureService } = load('services/web/BrowserTabSwipePreviewCaptureService.ets', {
    './BrowserTabPreviewCaptureService': {
      BrowserTabPreviewCaptureService: class {
        async captureWebPage(controller, tabId, options) {
          calls.push({ controller, tabId, options: { ...options } });
          return outcome === 'throw' ? Promise.reject(new Error('snapshot failed')) : outcome();
        }
      },
      buildBrowserTabWebComponentSnapshotId(id) { return `web-component:${id}`; }
    },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } }
  }, timers);
  const controller = { name: 'controller' };
  return { calls, controller, tabId: 'tab/a',
    viewport: { width: 412, height: 892 }, uiContext: { name: 'ui' },
    service: new BrowserTabSwipePreviewCaptureService() };
}
function pixel(info) {
  return {
    releases: 0, infoCalls: 0,
    getImageInfo() { this.infoCalls++; return info(); },
    release() { this.releases++; return Promise.resolve(); }
  };
}
function goodSize() { return Promise.resolve({ size: { width: 412, height: 892 } }); }

test('the swipe cover uses ArkWeb page pixels only, in memory, and never the blank component path', async () => {
  const image = pixel(goodSize);
  const h = captureHarness(() => Promise.resolve({ snapshot: image, failureReason: '' }));
  const result = await h.service.capture({
    tabId: h.tabId, controller: h.controller, viewport: h.viewport, uiContext: h.uiContext
  });
  assert.equal(h.calls.length, 1);
  const call = h.calls[0];
  assert.equal(call.tabId, 'tab/a');
  assert.equal(call.controller, h.controller);
  assert.equal(call.options.webComponentSnapshotId, 'web-component:tab/a');
  assert.equal(call.options.componentSnapshotOnly, false);
  assert.equal(call.options.preferVisibleSnapshot, false);
  assert.equal(call.options.allowWebPageSnapshot, true, 'only the swipe cover may re-lay the page');
  assert.equal(call.options.allowWindowSnapshot, false);
  assert.equal(call.options.allowSurfaceSnapshot, false);
  assert.equal(call.options.persistSharedSnapshot, false, 'the swipe cover must never reach the disk cache');
  assert.equal(call.options.requireSharedSnapshot, false);
  assert.equal(call.options.preferredWebViewportSnapshotSize.width, 412);
  assert.equal(call.options.preferredWebViewportSnapshotSize.height, 892);
  assert.equal(result.pixelMap, image, 'the usable image is handed over, not copied');
  assert.equal(result.width, 412);
  assert.equal(result.height, 892);
  assert.equal(image.infoCalls, 1);
  assert.equal(image.releases, 0, 'a usable image is transferred, not released');
});

test('a capture without page pixels yields no cover and releases nothing foreign', async () => {
  const h = captureHarness(() => Promise.resolve({ snapshot: undefined, failureReason: 'web-unavailable' }));
  assert.equal(await h.service.capture({
    tabId: h.tabId, controller: h.controller, viewport: h.viewport, uiContext: h.uiContext
  }), undefined);
  assert.equal(h.calls.length, 1);
});

test('an unreadable image is released exactly once', async () => {
  for (const info of [
    () => Promise.resolve({ size: { width: 0, height: 0 } }),
    () => Promise.reject(new Error('image info failed')),
    () => { throw new Error('image info threw'); }
  ]) {
    const image = pixel(info);
    const h = captureHarness(() => Promise.resolve({ snapshot: image, failureReason: '' }));
    assert.equal(await h.service.capture({
      tabId: h.tabId, controller: h.controller, viewport: h.viewport, uiContext: h.uiContext
    }), undefined);
    assert.equal(image.releases, 1);
    assert.equal(image.infoCalls, 1);
  }
});

test('a throwing snapshot path never produces a cover', async () => {
  const h = captureHarness('throw');
  assert.equal(await h.service.capture({
    tabId: h.tabId, controller: h.controller, viewport: h.viewport, uiContext: h.uiContext
  }), undefined);
  assert.equal(h.calls.length, 1);
});

test('release swallows platform failures and reports one release', async () => {
  const h = captureHarness(() => Promise.resolve({ snapshot: undefined, failureReason: '' }));
  let released = 0;
  h.service.release({ release() { released++; return Promise.resolve(); } });
  h.service.release({ release() { throw new Error('already released'); } });
  assert.equal(released, 1);
});
