const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');

const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const surfaceSource = fs.readFileSync(path.join(sourceRoot,
  'app/components/browser/BrowserAddressBarTabSwipeSurface.ets'), 'utf8');
const shellSource = fs.readFileSync(path.join(sourceRoot, 'app/pages/BrowserShellPage.ets'), 'utf8');

function leaveCaptureHarness(stage) {
  const policyModule = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(sourceRoot,
    'core/browser/BrowserTabPreviewActionCoordinator.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { module: policyModule, exports: policyModule.exports });
  const members = ['prepareAddressBarTabSwipeSnapshot', 'captureCurrentTabPreviewBeforeLeavingOpenerTab',
    'replaceVisibleTabCardImage'].map(name => {
    const member = shellSource.match(new RegExp(`  private (?:async )?${name}\\([^]*?\\n  }`))?.[0];
    assert.ok(member, name);
    return member;
  }).join('\n');
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(`export class Shell { ${members} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { module, exports: module.exports,
    visibleTabPreviewMustBeReplaced: policyModule.exports.visibleTabPreviewMustBeReplaced,
    buildBrowserTabPreviewVisibleSurfaceSnapshotId: id => `visible:${id}`,
    TABS_OVERVIEW_ENTRY_PIXELMAP_SCALE: 0.5
  });
  const stored = new Map([['a', 'page-a'], ['b', 'page-b']]), drawable = new Map();
  const reads = [], releases = [], captures = [], copies = [];
  let copyGate;
  const previewCoordinator = {
    persistImmediateSharedSnapshot: async (tab, image) => { stored.set(tab.id, image.pixels); return true; },
    adoptExternalTransitionSnapshot: (tab, image) => { stored.set(tab.id, image.pixels); },
    getTransitionSnapshotState: id => stored.has(id) ? { tabId: id } : undefined
  };
  const { BrowserTabsOverviewSnapshotPipelineCoordinator: Pipeline } = load(
    'core/browser/tabsOverview/BrowserTabsOverviewSnapshotPipelineCoordinator.ets', {
      '@kit.ImageKit': { image: { PixelMapFormat: { RGBA_8888: 'rgba' },
        async createPixelMap(buffer) {
          const pixels = new Uint8Array(buffer)[0] === 1 ? 'page-a' : 'page-b';
          const copy = { pixels, release: async () => { releases.push(`copy:${pixels}`); } };
          copies.push(copy);
          return copy;
        }
      } },
      '../BrowserTabsOverviewEntrySnapshotSessionCoordinator': {
        BrowserTabsOverviewEntrySnapshotSessionCoordinator: class {}
      },
      './BrowserTabsOverviewThumbnailCoordinator': { BrowserTabsOverviewThumbnailCoordinator: class {} },
      './BrowserTabSnapshotPixelMapCache': {
        BrowserTabSnapshotPixelMapCache: { put: (id, image) => drawable.set(id, image) }
      }
    }, clock());
  const pipeline = new Pipeline({ previewCoordinator, notifyChanged() {},
    releasePixelMap: image => image.release(), recordFailure() {} });
  const shell = Object.assign(new module.exports.Shell(), {
    activeTabId: 'a', currentWindowId: 'w', showHomePage: false, showTabsSheet: false,
    addressBarTabSwipeState: { stage }, tabs: [{ id: 'a', url: 'https://a.example/', isHome: false }],
    tabManager: { getTab: (tabs, id) => tabs.find(tab => tab.id === id) },
    getUIContext: () => ({ getComponentSnapshot: () => ({ get: (id, options) => {
      reads.push({ id, options });
      const capture = deferred();
      captures.push(capture);
      return capture.promise;
    } }) }),
    browserTabPreviewCoordinator: previewCoordinator,
    tabsOverviewSnapshotPipelineCoordinator: pipeline,
    notifyTabPreviewChanged() {}, recordRuntimeEvent() {}
  });
  return { shell, pipeline, reads, stored, drawable, releases, copies, captures,
    blockCopy() { copyGate = deferred(); return copyGate; },
    complete(pixels, index = captures.length - 1) {
      captures[index]?.resolve({ pixels,
        getImageInfoSync: () => ({ size: { width: 1, height: 1 }, pixelFormat: 'rgba' }),
        getPixelBytesNumber: () => 4,
        readPixelsToBuffer: async buffer => {
          if (copyGate) await copyGate.promise;
          new Uint8Array(buffer).set([pixels === 'page-a' ? 1 : 2, 0, 0, 255]);
        },
        release: async () => { releases.push(`raw:${pixels}`); }
      });
    }
  };
}

test('gesture entry captures once; commit never waits for capture, copy or persistence', async () => {
  const h = leaveCaptureHarness('idle');
  h.stored.delete('a');
  h.shell.prepareAddressBarTabSwipeSnapshot();
  assert.equal(h.reads.length, 1, 'request the current drawn frame synchronously at gesture entry');
  assert.equal(h.reads[0].id, 'visible:a');
  assert.equal(h.reads[0].options.waitUntilRenderFinished, false);
  assert.equal(h.reads[0].options.scale, 0.5);
  h.shell.addressBarTabSwipeState = { stage: 'committing' };
  let switched = false;
  h.shell.captureCurrentTabPreviewBeforeLeavingOpenerTab('a', 'b', 'tab_switch')
    .then(() => { h.shell.activeTabId = 'b'; switched = true; });
  await drain();
  assert.equal(switched, true, 'a pending snapshot must never hold the Web switch');
  assert.equal(h.reads.length, 1, 'release never requests another capture');
  h.complete('page-a');
  await drain();
  assert.equal(h.stored.get('a'), 'page-a', 'late delivery still belongs to the outgoing page');
  assert.equal(h.stored.get('b'), 'page-b');
  assert.equal(h.drawable.get('a'), h.copies[0], 'gallery and swipe consume the same retained image');
  assert.deepEqual(h.releases, ['raw:page-a'], 'only the temporary raw capture is released');
});

test('a slow drawable copy cannot hold switching or trigger a second capture', async () => {
  const h = leaveCaptureHarness('idle');
  const copy = h.blockCopy();
  h.shell.prepareAddressBarTabSwipeSnapshot();
  h.complete('page-a');
  await drain();
  assert.equal(h.drawable.size, 0);
  h.shell.addressBarTabSwipeState = { stage: 'committing' };
  let switched = false;
  h.shell.captureCurrentTabPreviewBeforeLeavingOpenerTab('a', 'b', 'tab_switch')
    .then(() => { switched = true; h.shell.activeTabId = 'b'; });
  await drain();
  assert.equal(switched, true);
  assert.equal(h.reads.length, 1);
  copy.resolve();
  await drain();
  assert.equal(h.drawable.get('a').pixels, 'page-a');
});

for (const interruption of ['document', 'window', 'closed']) {
  test(`entry capture finishing after ${interruption} cannot overwrite the saved image`, async () => {
    const h = leaveCaptureHarness('idle');
    h.shell.prepareAddressBarTabSwipeSnapshot();
    if (interruption === 'document') h.shell.tabs = [{ ...h.shell.tabs[0], url: 'https://new.example/' }];
    if (interruption === 'window') h.shell.currentWindowId = 'other-window';
    if (interruption === 'closed') h.shell.tabs = [];
    h.complete('page-b');
    await drain();
    assert.equal(h.stored.get('a'), 'page-a');
    assert.equal(h.drawable.size, 0);
    assert.deepEqual(h.releases, ['raw:page-b']);
  });
}

test('an older entry capture cannot overwrite a newer frame of the same tab', async () => {
  const h = leaveCaptureHarness('idle');
  h.shell.prepareAddressBarTabSwipeSnapshot();
  h.shell.prepareAddressBarTabSwipeSnapshot();
  h.complete('page-a', 1);
  await drain();
  h.complete('page-b', 0);
  await drain();
  assert.equal(h.stored.get('a'), 'page-a');
  assert.equal(h.drawable.get('a').pixels, 'page-a');
  assert.ok(h.releases.includes('raw:page-b'));
});

test('the browser shell never calls the relayout-producing swipe snapshot scheduler', () => {
  assert.doesNotMatch(shellSource, /BrowserTabSwipePreviewCoordinator|BrowserTabSwipePreviewCaptureService/);
  const entry = shellSource.match(/prepareOutgoingPreview:\s*\(\): void => \{([^]*?)\n      }/)[1];
  assert.match(entry, /this.prepareAddressBarTabSwipeSnapshot\(\)/);
  assert.doesNotMatch(entry, /await/);
});

for (const stage of ['dragging', 'settling', 'committing', 'handoff']) {
  test(`leaving during ${stage} never saves the incoming page as the outgoing tab's screenshot`, async () => {
    const h = leaveCaptureHarness(stage);
    const task = h.shell.captureCurrentTabPreviewBeforeLeavingOpenerTab('a', 'b', 'tab_switch');
    h.complete('page-b'); // The shell is displaying the neighbor cover, not page A alone.
    await task;
    assert.equal(h.stored.get('a'), 'page-a', 'page B must not contaminate page A preview');
    assert.equal(h.reads.length, 0, 'a composed swipe frame is not a tab screenshot');
  });
}

test('an idle leave capture is rejected if a swipe starts before its pixels arrive', async () => {
  const h = leaveCaptureHarness('idle');
  const task = h.shell.replaceVisibleTabCardImage('a', 'tab_switch');
  h.shell.addressBarTabSwipeState.stage = 'dragging';
  h.complete('mixed-pages');
  assert.equal(await task, false);
  assert.equal(h.stored.get('a'), 'page-a');
  assert.deepEqual(h.releases, ['raw:mixed-pages']);
});

test('ordinary idle tab switching still saves the outgoing page', async () => {
  const h = leaveCaptureHarness('idle');
  const task = h.shell.replaceVisibleTabCardImage('a', 'tab_switch');
  h.complete('fresh-page-a');
  assert.equal(await task, true);
  assert.equal(h.stored.get('a'), 'fresh-page-a');
  assert.equal(h.stored.get('b'), 'page-b');
});

test('a late composite is rejected even when a canceled swipe has already returned to idle', async () => {
  const h = leaveCaptureHarness('idle');
  const task = h.shell.replaceVisibleTabCardImage('a', 'tab_switch');
  h.shell.addressBarTabSwipeState = { stage: 'dragging' };
  h.shell.addressBarTabSwipeState = { stage: 'idle' };
  h.complete('mixed-pages');
  assert.equal(await task, false);
  assert.equal(h.stored.get('a'), 'page-a');
  assert.deepEqual(h.releases, ['raw:mixed-pages']);
});

// Exercise the real image-builder and geometry methods across the shell/component boundary.
// This models Huawei's documented state semantics, not a device renderer: @Prop deep-copies
// enumerable JS data and loses native PixelMap backing; @Link shares the parent's state.
// https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-prop
function swipeSurfaceHarness() {
  const decorator = surfaceSource.match(/@(Prop|Link)\s+preview[?:]/)?.[1];
  assert.ok(decorator, 'the preview must have an explicit state binding');
  const binding = shellSource.match(/BrowserAddressBarTabSwipeSurface\(\{[^]*?preview:\s*this\.(\$?\w+)/)?.[1];
  assert.equal(binding, decorator === 'Link' ? '$addressBarTabSwipePreview' : 'addressBarTabSwipePreview');
  const members = ['buildPreviewImage', 'usesPageFrame', 'resolvePagePreviewHeight',
    'previewUri', 'resolveLiveOffset', 'resolvePreviewOffset', 'resolvePreviewOpacity'].map(name => {
    const member = surfaceSource.match(new RegExp(`  private ${name}\\([^]*?\\n  }`))?.[0];
    assert.ok(member, `missing surface member: ${name}`);
    // Keep a leaf update callback, as the ArkUI compiler does. Re-entering the entire Builder
    // on every assertion hid stale by-value arguments in the original regression check.
    return member.replace(/\bImage\(([^\n]*)\)/g, 'Image(() => $1)');
  }).join('\n');
  const sourceResolver = surfaceSource.match(/  private resolvePreviewImageSource\([^]*?\n  }/)?.[0] ?? '';
  const module = { exports: {} };
  const draws = [];
  const code = ts.transpileModule(`export class Surface { ${members} ${sourceResolver} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports,
    ImageFit: { Fill: 'fill' }, ImageInterpolation: { Medium: 'medium' },
    Image(readSource) {
      const draw = { source: readSource(), readSource };
      draws.push(draw);
      const node = {};
      for (const property of ['width', 'height', 'objectFit', 'interpolation', 'syncLoad', 'blur', 'position']) {
        node[property] = value => { draw[property] = value; return node; };
      }
      return node;
    }
  });
  const surface = new module.exports.Surface();
  // Evaluate the actual PixelMap/URI selection in build(), including its priority order.
  const selection = surfaceSource.match(
    /if \(this\.preview\.sharedSnapshotPixelMap !== undefined\) \{[^]*?\n            }(?! else)/)?.[0];
  assert.ok(selection, 'missing preview image selection');
  const paint = vm.runInNewContext(ts.transpileModule(`(function () { ${selection} })`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText);
  return { surface, draws,
    update(preview) {
      surface.preview = decorator === 'Prop' && preview !== undefined ?
        JSON.parse(JSON.stringify(preview)) : preview;
    },
    paint() { paint.call(surface); return draws.at(-1); }
  };
}

for (const direction of [-1, 1]) {
  test(`half swipe (${direction}) paints the leased neighbor's native pixels in the exposed region`, () => {
    const h = swipeSurfaceHarness();
    // Native backing cannot be recovered by copying the object's enumerable properties.
    const nativePixels = new WeakMap();
    const pixelMap = {};
    nativePixels.set(pixelMap, 'neighbor page pixels');
    h.surface.state = { stage: 'dragging', direction, offsetX: direction * 200,
      width: 400, reduceMotion: false, previewOpacity: 1 };
    h.surface.topInset = 24;
    h.surface.previewBlurRadius = 0;
    h.update({ sharedSnapshotPixelMap: pixelMap, sharedSnapshotImageWidth: 400,
      sharedSnapshotImageHeight: 760, transitionSource: { captureScope: 'web-content' } });
    const draw = h.paint();
    assert.equal(nativePixels.get(draw.source), 'neighbor page pixels',
      'the incoming image must retain its native backing rather than paint a blank copy');
    assert.equal(h.surface.resolveLiveOffset(), direction * 200);
    assert.equal(h.surface.resolvePreviewOffset(), -direction * 212);
    assert.equal(h.surface.resolvePreviewOpacity(), 1);
    assert.equal(draw.height, 760);
    assert.equal(draw.position.y, 24);
  });
}

test('the mounted swipe surface follows neighbor changes and keeps file previews and privacy blur', () => {
  const h = swipeSurfaceHarness();
  h.surface.state = { width: 400 };
  h.surface.topInset = 24;
  h.surface.previewBlurRadius = 16;
  const left = {}, right = {};
  for (const pixelMap of [left, right, left]) {
    h.update({ sharedSnapshotPixelMap: pixelMap, sharedSnapshotImageUri: 'file://stored-preview' });
    const draw = h.paint();
    assert.equal(draw.source, pixelMap, 'direction reversal keeps the selected leased source');
    assert.equal(draw.blur, 16);
    assert.equal(draw.position.y, 0, 'full-surface screenshots include their own top chrome');
  }
  h.update(undefined);
  assert.equal(h.surface.preview, undefined, 'ending the gesture clears the child reference');
  h.update({ sharedSnapshotImageUri: 'file://next-preview' });
  assert.equal(h.paint().source, 'file://next-preview');
});

test('an existing image leaf reads the new neighbor after reversal without rebuilding the Builder', () => {
  const h = swipeSurfaceHarness();
  h.surface.state = { width: 400 };
  const a = {}, b = {};
  h.update({ sharedSnapshotPixelMap: a });
  const leaf = h.paint();
  assert.equal(leaf.readSource(), a);
  h.update({ sharedSnapshotPixelMap: b });
  assert.equal(leaf.readSource(), b, 'the leaf must not retain the first Builder argument');
});

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
