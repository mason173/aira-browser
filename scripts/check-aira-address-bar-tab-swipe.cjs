const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');

const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
function createLoader(globals = {}) {
  const cache = new Map();
  function load(relativePath) {
    const filename = path.resolve(sourceRoot, relativePath);
    if (cache.has(filename)) return cache.get(filename);
    const module = { exports: {} };
    const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
      fileName: filename,
      reportDiagnostics: true
    });
    assert.equal((result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0,
      `Transpile errors in ${filename}`);
    cache.set(filename, module.exports);
    vm.runInNewContext(result.outputText, {
      ...globals,
      module, exports: module.exports,
      require(specifier) {
        assert.ok(specifier.startsWith('.'), `Unexpected platform dependency: ${specifier}`);
        return load(path.relative(sourceRoot, path.resolve(path.dirname(filename), `${specifier}.ets`)));
      }
    }, { filename });
    return module.exports;
  }
  return load;
}
const load = createLoader();

function createSwipeHarness({ reduceMotion = false } = {}) {
  let now = 0;
  let timerId = 0;
  const timers = new Map();
  const clearedTimers = [];
  const frames = [];
  class FakeDate extends Date {
    static now() { return now; }
  }
  const isolatedLoad = createLoader({
    Date: FakeDate,
    setTimeout(callback, delay) {
      const id = ++timerId;
      timers.set(id, { callback, due: now + delay });
      return id;
    },
    clearTimeout(id) {
      clearedTimers.push(id);
      timers.delete(id);
    }
  });
  const { BrowserAddressBarTabSwipeCoordinator } = isolatedLoad(
    'core/browser/BrowserAddressBarTabSwipeCoordinator.ets');
  const h = {
    facts: { tabs: [
      tab('left', { title: 'Left', url: 'https://left.example/path' }),
      tab('middle'),
      tab('right', { title: 'Right', url: 'http://right.example/path' })
    ], activeTabId: 'middle', windowId: 'window-1', enabled: true, width: 400, height: 800 },
    reduceMotion, ready: false, states: [], animations: [], switches: [],
    locks: [], unlocks: [], readyChecks: [], timers, clearedTimers, frames,
    get state() { return this.states.at(-1); },
    flushFrame() {
      // Callbacks registered during this frame belong to the next real frame.
      const callbacks = frames.splice(0);
      for (const callback of callbacks) callback();
    },
    advance(milliseconds) {
      const end = now + milliseconds;
      let count = 0;
      while (true) {
        const next = [...timers].filter(([, timer]) => timer.due <= end)
          .sort((a, b) => a[1].due - b[1].due || a[0] - b[0])[0];
        if (!next) break;
        assert.ok(++count < 10000, 'timer queue must make progress');
        now = next[1].due;
        timers.delete(next[0]);
        next[1].callback();
      }
      now = end;
    },
    event(phase, offsetX = 0, velocityX = 0) {
      this.coordinator.handle({ phase, offsetX, velocityX });
    },
    release(offsetX = -140) {
      this.event('start');
      this.event('end', offsetX);
      return this.animations.at(-1);
    },
    async completeSwitch(request = this.switches.at(-1)) {
      if (request.canApply()) {
        this.facts = { ...this.facts, activeTabId: request.tabId };
        request.applied += 1;
      }
      request.resolve();
      // Drain cross-context Promise assimilation before inspecting coordinator state.
      await new Promise(resolve => setImmediate(resolve));
    }
  };
  h.coordinator = new BrowserAddressBarTabSwipeCoordinator({
    readFacts: () => h.facts,
    readReduceMotion: () => h.reduceMotion,
    publish: state => h.states.push({ ...state }),
    animate: (duration, update, finish) => h.animations.push({ duration, update, finish }),
    switchToTab: (tabId, canApply) => new Promise((resolve, reject) => {
      h.switches.push({ tabId, canApply, resolve, reject, applied: 0 });
    }),
    afterFrame: callback => frames.push(callback),
    isTargetReady: tabId => { h.readyChecks.push(tabId); return h.ready; },
    lockPreview: tabId => h.locks.push(tabId),
    unlockPreview: tabId => h.unlocks.push(tabId)
  });
  return h;
}

function assertSwipeReleased(h) {
  assert.equal(h.state.stage, 'idle');
  assert.equal(h.timers.size, 0, 'monitor must be cleared');
  assert.deepEqual([...h.unlocks].sort(), [...h.locks].sort(), 'release every preview lock exactly once');
}

const { BrowserWebTabsController } = load('core/browser/BrowserWebTabsController.ets');
const { buildGenerationBoundHostedWebNodeCallbacks } = load(
  'core/browser/BrowserHostedWebNodeGenerationCallbacks.ets');

function connectStopLoading(h, { notify = true } = {}) {
  const notifications = [];
  const calls = [];
  const results = new Map();
  const recordRuntimeEvent = () => {};
  const controller = new BrowserWebTabsController({}, {
    recordRuntimeEvent,
    resolveActiveWebTabId: () => h.facts.activeTabId,
    resolveWebTabSnapshot: id => h.facts.tabs.find(tab => tab.id === id),
    ...(notify ? { onLoadingStopped: tabId => {
      assert.equal(calls.at(-1).tabId, tabId, 'notify only after the page command');
      assert.equal(calls.at(-1).result.status, 'native_issued');
      notifications.push(tabId);
      h.coordinator.handleLoadingStopped(tabId);
    } } : {})
  }, {});
  for (const tab of h.facts.tabs) {
    const result = { status: 'native_issued', reason: 'native_history', targetUrl: '', errorMessage: '' };
    results.set(tab.id, result);
    // Only the page boundary is doubled; resolvePage, host construction and stopLoading stay real.
    controller.pagesByTabId[tab.id] = {
      setTabId: id => assert.equal(id, tab.id),
      hydrateFromTab: (url, pendingUrl) => {
        assert.equal(url, tab.url);
        assert.equal(pendingUrl, tab.pendingUrl);
      },
      stopLoading: host => {
        assert.equal(host.recordRuntimeEvent, recordRuntimeEvent);
        calls.push({ tabId: tab.id, result });
        return result;
      }
    };
  }
  return { controller, notifications, calls, results };
}

async function enterHandoff(h) {
  const settle = h.release();
  settle.update();
  settle.finish();
  assert.equal(h.state.stage, 'committing');
  await h.completeSwitch();
  assert.equal(h.state.stage, 'handoff');
}

test('coordinator drag reverses candidates and publishes previews without switching', () => {
  const h = createSwipeHarness();
  h.event('start');
  assert.deepEqual(h.locks, ['left', 'right']);
  assert.equal(h.timers.size, 1);
  for (const [offset, id, title, address] of [
    [-180, 'right', 'Right', 'right.example'],
    [180, 'left', 'Left', 'left.example'],
    [0, '', '', ''],
    [-40, 'right', 'Right', 'right.example']
  ]) {
    h.event('update', offset);
    assert.equal(h.state.stage, 'dragging');
    assert.equal(h.state.targetTabId, id);
    assert.equal(h.state.targetTitle, title);
    assert.equal(h.state.targetAddress, address);
    assert.equal(h.state.direction, Math.sign(offset));
    assert.equal(h.state.offsetX, offset);
  }
  h.advance(96);
  assert.equal(h.switches.length, 0);
  assert.equal(h.animations.length, 0);
  assert.equal(h.facts.activeTabId, 'middle');
  h.coordinator.cancel();
  assertSwipeReleased(h);
});

test('coordinator insufficient distance settles back and releases resources without commit', () => {
  const h = createSwipeHarness();
  const settle = h.release(-40);
  assert.equal(h.state.stage, 'settling');
  settle.update();
  assert.equal(h.state.offsetX, 0);
  assert.equal(h.state.stage, 'settling');
  assert.equal(h.unlocks.length, 0);
  settle.finish();
  assert.equal(h.switches.length, 0);
  assertSwipeReleased(h);
  assert.equal(h.clearedTimers.length, 1);
});

test('coordinator commits either direction only after settle finishes and ignores repeated end events', async () => {
  for (const [offset, target] of [[-140, 'right'], [140, 'left']]) {
    const h = createSwipeHarness();
    const settle = h.release(offset);
    h.event('end', offset);
    assert.equal(h.animations.length, 1);
    assert.equal(h.switches.length, 0);
    settle.update();
    assert.equal(h.state.offsetX, Math.sign(offset) * 412);
    assert.equal(h.switches.length, 0);
    assert.equal(h.facts.activeTabId, 'middle');
    settle.finish();
    assert.equal(h.switches.length, 1);
    assert.equal(h.switches[0].tabId, target);
    assert.equal(h.switches[0].canApply(), true);
    h.event('end', offset);
    assert.equal(h.switches.length, 1);
    await h.completeSwitch();
    assert.equal(h.facts.activeTabId, target);
    assert.equal(h.switches[0].applied, 1);
    h.coordinator.cancel();
    assertSwipeReleased(h);
  }
});

test('coordinator recovers a dropped settle onFinish instead of freezing the gesture', async () => {
  const h = createSwipeHarness();
  const settle = h.release(-140);
  assert.equal(h.state.stage, 'settling');
  assert.equal(h.switches.length, 0);
  h.advance(1200);
  assert.equal(h.switches.length, 1, 'monitor must commit when onFinish never arrives');
  assert.equal(h.switches[0].tabId, 'right');
  settle.finish();
  assert.equal(h.switches.length, 1, 'a late onFinish must not submit a second switch');
  await h.completeSwitch();
  assert.equal(h.state.stage, 'handoff');
  h.coordinator.cancel();
  assertSwipeReleased(h);
});

test('coordinator recovers a dropped non-commit settle by releasing the gesture', () => {
  const h = createSwipeHarness();
  h.release(-40);
  h.advance(1200);
  assert.equal(h.switches.length, 0);
  assertSwipeReleased(h);
});

test('coordinator recovers a dropped fade onFinish without leaving the cover pinned forever', async () => {
  const h = createSwipeHarness();
  await enterHandoff(h);
  h.ready = true;
  h.advance(32);
  h.flushFrame();
  h.flushFrame();
  const fade = h.animations.at(-1);
  fade.update();
  assert.equal(h.state.previewOpacity, 0);
  h.advance(1200);
  assertSwipeReleased(h);
  fade.update();
  fade.finish();
  assertSwipeReleased(h);
});

test('coordinator settle finish is idempotent while asynchronous switch is pending', () => {
  const h = createSwipeHarness();
  try {
    const settle = h.release();
    settle.update();
    settle.finish();
    settle.finish();
    assert.equal(h.switches.length, 1, 'duplicate finish must not submit a second switch');
  } finally {
    h.coordinator.cancel();
  }
});

for (const [name, invalidate] of [
  ['explicit cancel', h => h.coordinator.cancel()],
  ['window change', h => { h.facts = { ...h.facts, windowId: 'window-2' }; }],
  ['target deletion', h => { h.facts = { ...h.facts, tabs: h.facts.tabs.filter(t => t.id !== 'right') }; }],
  ['source deletion', h => { h.facts = { ...h.facts, tabs: h.facts.tabs.filter(t => t.id !== 'middle') }; }],
  ['external active tab change', h => { h.facts = { ...h.facts, activeTabId: 'left' }; }]
]) {
  test(`coordinator async canApply rejects stale result after ${name}`, async () => {
    const h = createSwipeHarness();
    const settle = h.release();
    settle.update();
    settle.finish();
    const request = h.switches[0];
    assert.equal(request.canApply(), true);
    invalidate(h);
    assert.equal(request.canApply(), false, 'guard must read current facts before reconciliation');
    const activeBeforeResolution = h.facts.activeTabId;
    await h.completeSwitch(request);
    h.coordinator.reconcile();
    assert.equal(request.applied, 0);
    assert.equal(h.facts.activeTabId, activeBeforeResolution);
    assertSwipeReleased(h);
  });
}

test('coordinator canceled generation cannot affect a replacement gesture', async () => {
  const h = createSwipeHarness();
  const oldSettle = h.release();
  oldSettle.update();
  oldSettle.finish();
  const oldRequest = h.switches[0];
  h.coordinator.cancel();
  h.event('start');
  h.event('update', 120);
  const snapshot = { ...h.state };
  const published = h.states.length;
  oldSettle.update();
  oldSettle.finish();
  await h.completeSwitch(oldRequest);
  assert.equal(oldRequest.canApply(), false);
  assert.equal(h.switches.length, 1);
  assert.equal(h.states.length, published);
  assert.deepEqual(h.state, snapshot);
  assert.equal(h.timers.size, 1);
  h.coordinator.cancel();
  assertSwipeReleased(h);
});

test('coordinator monitor cancels an invalid session before settle callback can commit', () => {
  const h = createSwipeHarness();
  const settle = h.release();
  h.facts = { ...h.facts, width: 500 };
  h.advance(32);
  assertSwipeReleased(h);
  const published = h.states.length;
  settle.update();
  settle.finish();
  assert.equal(h.states.length, published);
  assert.equal(h.switches.length, 0);
});

test('coordinator handoff requires two actual frames and retains locks until fade finish', async () => {
  const h = createSwipeHarness();
  await enterHandoff(h);
  h.ready = true;
  h.advance(128);
  assert.equal(h.animations.length, 1, 'timer ticks cannot substitute for frames');
  assert.equal(h.frames.length, 1, 'monitor must not enqueue duplicate frame waits');
  h.flushFrame();
  assert.equal(h.animations.length, 1, 'one frame cannot start fade');
  assert.equal(h.frames.length, 1, 'nested callback waits for the next frame');
  h.advance(128);
  assert.equal(h.animations.length, 1, 'time between frames cannot start fade');
  h.flushFrame();
  assert.equal(h.animations.length, 2);
  assert.equal(h.frames.length, 0);
  assert.ok(h.readyChecks.length > 0);
  assert.ok(h.readyChecks.every(tabId => tabId === 'right'));
  const fade = h.animations[1];
  assert.equal(fade.duration, 120);
  assert.equal(h.state.previewOpacity, 1);
  fade.update();
  assert.equal(h.state.previewOpacity, 0);
  assert.equal(h.state.stage, 'handoff');
  assert.equal(h.unlocks.length, 0);
  h.advance(96);
  assert.equal(h.animations.length, 2, 'fade starts only once');
  fade.finish();
  assertSwipeReleased(h);
  assert.equal(h.clearedTimers.length, 1);
  const published = h.states.length;
  fade.update();
  fade.finish();
  h.advance(1000);
  assert.equal(h.states.length, published);
  assertSwipeReleased(h);
});

for (const interruption of ['document', 'monitor', 'finish']) {
  test(`fade interruption (${interruption}) restores the same opaque cover and ignores stale completion`, async () => {
    const h = createSwipeHarness();
    await enterHandoff(h);
    h.ready = true;
    h.advance(32); h.flushFrame(); h.flushFrame();
    const fade = h.animations.at(-1);
    fade.update();
    assert.equal(h.state.previewOpacity, 0);
    h.ready = false;
    if (interruption === 'document') h.coordinator.noteDocumentBegin('right');
    else if (interruption === 'monitor') h.advance(32);
    else fade.finish();
    const restore = h.animations.at(-1);
    assert.notEqual(restore, fade);
    assert.equal(restore.duration, 0);
    restore.update();
    assert.equal(h.state.previewOpacity, 1);
    assert.equal(h.state.stage, 'handoff');
    assert.equal(h.unlocks.length, 0, 'keep the image lease throughout a failed handoff');
    fade.update(); fade.finish();
    assert.equal(h.state.previewOpacity, 1);
    assert.equal(h.state.stage, 'handoff');
    const count = h.animations.length;
    h.ready = true;
    h.advance(32); h.flushFrame();
    assert.equal(h.animations.length, count);
    h.flushFrame();
    const retry = h.animations.at(-1);
    assert.notEqual(retry, fade);
    retry.update(); retry.finish();
    assertSwipeReleased(h);
  });
}

test('coordinator handoff timeout keeps the preview pinned until ready plus two frames', async () => {
  const h = createSwipeHarness();
  const settle = h.release();
  settle.update();
  settle.finish();
  h.advance(640);
  await h.completeSwitch();
  assert.equal(h.state.stage, 'handoff');
  h.advance(899);
  assert.equal(h.animations.length, 1);
  h.advance(1);
  assert.equal(h.animations.length, 1, 'timeout is checked by the 32ms monitor');
  assert.equal(h.state.loadingPlaceholder, false);
  h.advance(28);
  assert.equal(h.animations.length, 1, 'timeout must not start fade');
  assert.equal(h.ready, false);
  assert.equal(h.state.stage, 'handoff');
  assert.equal(h.state.loadingPlaceholder, true);
  assert.equal(h.state.previewOpacity, 1, 'loading UI must fully cover the unready target');
  assert.equal(h.state.targetTabId, 'right');
  assert.equal(h.unlocks.length, 0, 'visible cached image must remain pinned during slow restoration');
  const loadingStart = h.states.length - 1;
  h.advance(5000);
  h.flushFrame();
  assert.equal(h.animations.length, 1, 'arbitrarily slow content must keep the cover');
  assert.equal(h.timers.size, 1, 'continue watching readiness while keeping the displayed image pinned');
  assert.ok(h.states.slice(loadingStart).every(state =>
    state.stage === 'handoff' && state.loadingPlaceholder && state.previewOpacity === 1));
  h.ready = true;
  h.advance(100);
  h.flushFrame();
  assert.equal(h.animations.length, 1);
  assert.equal(h.state.previewOpacity, 1);
  h.flushFrame();
  assert.equal(h.animations.length, 2);
  const fade = h.animations[1];
  fade.update();
  assert.equal(h.state.previewOpacity, 0);
  assert.equal(h.state.loadingPlaceholder, true);
  fade.finish();
  assertSwipeReleased(h);
  assert.equal(h.state.loadingPlaceholder, false);
});

for (const lostAtFrame of [1, 2]) {
  test(`coordinator readiness lost at frame ${lostAtFrame} keeps cover and retries two frames`, async () => {
    const h = createSwipeHarness();
    await enterHandoff(h);
    h.ready = true;
    h.advance(32);
    if (lostAtFrame === 2) h.flushFrame();
    h.ready = false;
    h.flushFrame();
    if (lostAtFrame === 1) h.flushFrame();
    assert.equal(h.animations.length, 1);
    assert.equal(h.state.stage, 'handoff');
    assert.equal(h.state.previewOpacity, 1);
    assert.equal(h.unlocks.length, 0);
    h.ready = true;
    h.advance(32);
    h.flushFrame();
    assert.equal(h.animations.length, 1, 'retry requires a fresh pair of frames');
    h.flushFrame();
    assert.equal(h.animations.length, 2);
    h.animations[1].update();
    h.animations[1].finish();
    assertSwipeReleased(h);
  });
}

test('coordinator readiness lost on first frame cannot fade when it returns only on second frame', async () => {
  const h = createSwipeHarness();
  try {
    await enterHandoff(h);
    h.ready = true;
    h.advance(32);
    h.ready = false;
    h.flushFrame();
    h.advance(32); // Also let the readiness monitor observe the interrupted streak.
    h.ready = true;
    h.flushFrame();
    assert.equal(h.animations.length, 1, 'interrupted readiness requires two new ready frames');
    assert.equal(h.state.previewOpacity, 1);
    h.advance(32);
    h.flushFrame();
    assert.equal(h.animations.length, 1);
    h.flushFrame();
    assert.equal(h.animations.length, 2);
  } finally {
    h.coordinator.cancel();
    assertSwipeReleased(h);
  }
});

for (const flushedBeforeCancel of [0, 1]) {
  test(`coordinator canceled frame callbacks cannot affect replacement handoff after ${flushedBeforeCancel} frames`, async () => {
    const h = createSwipeHarness();
    await enterHandoff(h);
    h.ready = true;
    h.advance(32);
    if (flushedBeforeCancel) h.flushFrame();
    assert.equal(h.frames.length, 1);
    h.coordinator.cancel();
    assertSwipeReleased(h);
    // Start another handoff while the old generation still has a queued callback.
    h.ready = false;
    const settle = h.release(140);
    settle.update();
    settle.finish();
    await h.completeSwitch();
    assert.equal(h.state.stage, 'handoff');
    const snapshot = { ...h.state };
    const published = h.states.length;
    const animations = h.animations.length;
    const unlocks = [...h.unlocks];
    h.ready = true;
    h.advance(32);
    h.flushFrame();
    assert.equal(h.animations.length, animations, 'old callback cannot start a fade');
    assert.equal(h.states.length, published);
    assert.deepEqual(h.state, snapshot);
    assert.deepEqual(h.unlocks, unlocks);
    assert.equal(h.timers.size, 1);
    h.flushFrame();
    assert.equal(h.animations.length, animations + 1, 'only replacement handoff may fade');
    const fade = h.animations.at(-1);
    fade.update();
    fade.finish();
    assertSwipeReleased(h);
    const released = h.states.length;
    h.flushFrame();
    assert.equal(h.states.length, released);
    assertSwipeReleased(h);
  });
}

test('coordinator visible surfaces isolate tab IDs, hosted generations and document begins', () => {
  const h = createSwipeHarness();
  const coordinator = h.coordinator;
  assert.equal(coordinator.hasVisibleSurface('left', 1), false);
  coordinator.noteSurfaceVisible('left', 1);
  assert.equal(coordinator.hasVisibleSurface('left', 1), true);
  assert.equal(coordinator.hasVisibleSurface('left', 2), false);
  assert.equal(coordinator.hasVisibleSurface('right', 1), false);
  coordinator.noteSurfaceVisible('right', 1);
  coordinator.noteSurfaceVisible('left', 2);
  assert.equal(coordinator.hasVisibleSurface('left', 1), false);
  assert.equal(coordinator.hasVisibleSurface('left', 2), true);
  assert.equal(coordinator.hasVisibleSurface('right', 1), true);
  coordinator.noteDocumentBegin('left');
  assert.equal(coordinator.hasVisibleSurface('left', 1), false);
  assert.equal(coordinator.hasVisibleSurface('left', 2), false);
  assert.equal(coordinator.hasVisibleSurface('right', 1), true);
  coordinator.noteSurfaceVisible('left', 2);
  assert.equal(coordinator.hasVisibleSurface('left', 2), true, 'new document must report visible again');
  coordinator.noteDocumentBegin('missing');
  assert.equal(coordinator.hasVisibleSurface('left', 2), true);
  assert.equal(coordinator.hasVisibleSurface('right', 1), true);
  h.facts = { ...h.facts, tabs: h.facts.tabs.filter(tab => tab.id !== 'left') };
  coordinator.reconcile();
  assert.equal(coordinator.hasVisibleSurface('left', 2), false, 'deleted tab must lose surface readiness');
  assert.equal(coordinator.hasVisibleSurface('right', 1), true);
  h.facts = { ...h.facts, tabs: [tab('left'), ...h.facts.tabs] };
  assert.equal(coordinator.hasVisibleSurface('left', 2), false, 'reused tab ID cannot inherit readiness');
});

test('real generation wrapper ignores old or wrong-tab begins while current begin clears readiness', () => {
  const h = createSwipeHarness();
  let currentGeneration = 1;
  const begins = [];
  const visibles = [];
  const wrapper = generation => buildGenerationBoundHostedWebNodeCallbacks('right', generation, {
    onPageBegin: (tabId, event) => {
      begins.push(event);
      h.coordinator.noteDocumentBegin(tabId);
    },
    onPageVisible: (tabId, event) => {
      visibles.push(event);
      h.coordinator.noteSurfaceVisible(tabId, generation);
    }
  }, (tabId, generation) => tabId === 'right' && generation === currentGeneration);
  const old = wrapper(1);
  const current = wrapper(2);
  currentGeneration = 2;
  const visible = { url: 'https://right.example/new' };
  const begin = { url: 'https://right.example/next' };
  current.onPageVisible('right', visible);
  assert.equal(h.coordinator.hasVisibleSurface('right', 2), true);
  old.onPageBegin('right', begin);
  current.onPageBegin('left', begin);
  old.onPageVisible('right', visible);
  current.onPageVisible('left', visible);
  assert.equal(h.coordinator.hasVisibleSurface('right', 2), true);
  assert.equal(h.coordinator.hasVisibleSurface('left', 2), false);
  assert.deepEqual(begins, []);
  assert.deepEqual(visibles, [visible]);
  current.onPageBegin('right', begin);
  assert.deepEqual(begins, [begin]);
  assert.equal(h.coordinator.hasVisibleSurface('right', 2), false);
  current.onPageVisible('right', visible);
  assert.equal(h.coordinator.hasVisibleSurface('right', 2), true);
});

test('real stopLoading dismisses the loading placeholder even when target never becomes ready', async () => {
  const h = createSwipeHarness();
  const stop = connectStopLoading(h);
  await enterHandoff(h);
  h.advance(928);
  assert.equal(h.ready, false);
  assert.equal(h.state.loadingPlaceholder, true);
  assert.equal(h.state.stage, 'handoff');
  assert.equal(h.timers.size, 1);
  stop.controller.stopLoading('right');
  assert.deepEqual(stop.notifications, ['right']);
  assertSwipeReleased(h);
  assert.equal(h.state.loadingPlaceholder, false);
  assert.equal(h.state.targetTabId, '');
  const published = h.states.length;
  h.advance(5000);
  h.flushFrame();
  assert.equal(h.states.length, published);
  assert.equal(h.animations.length, 1, 'stopping must not wait for a fade');
  assertSwipeReleased(h);
});

for (const framesBeforeStop of [0, 1]) {
  test(`real stopLoading clears timed-out cover and isolates old callback after ${framesBeforeStop} frames`, async () => {
    const h = createSwipeHarness();
    const stop = connectStopLoading(h);
    await enterHandoff(h);
    h.advance(900);
    h.advance(28); // First 32ms monitor tick after the 900ms handoff threshold.
    assert.equal(h.state.loadingPlaceholder, true);
    assert.equal(h.state.previewOpacity, 1);
    assert.equal(h.timers.size, 1);
    assert.equal(h.unlocks.length, 0, 'loading cover still owns its image before explicit stop');
    h.ready = true;
    h.advance(100); // Loading placeholders poll readiness every 100ms.
    if (framesBeforeStop) h.flushFrame();
    assert.equal(h.frames.length, 1);
    assert.equal(stop.controller.stopLoading('right'), stop.results.get('right'));
    assert.deepEqual(stop.notifications, ['right']);
    assertSwipeReleased(h);
    assert.equal(h.state.loadingPlaceholder, false);
    assert.equal(h.state.targetTabId, '');
    assert.equal(h.clearedTimers.length, 1);
    h.ready = false;
    const settle = h.release(140);
    settle.update();
    settle.finish();
    await h.completeSwitch();
    const snapshot = { ...h.state };
    const published = h.states.length;
    const animations = h.animations.length;
    const unlocks = [...h.unlocks];
    h.ready = true;
    h.advance(32);
    h.flushFrame();
    assert.deepEqual(h.state, snapshot);
    assert.equal(h.states.length, published);
    assert.equal(h.animations.length, animations);
    assert.deepEqual(h.unlocks, unlocks);
    assert.equal(h.timers.size, 1);
    h.flushFrame();
    assert.equal(h.animations.length, animations + 1);
    h.animations.at(-1).update();
    h.animations.at(-1).finish();
    assertSwipeReleased(h);
  });
}

test('real stopLoading cancels committing only once target is active and ignores late switch completion', async () => {
  const h = createSwipeHarness();
  const stop = connectStopLoading(h);
  const settle = h.release();
  settle.update();
  settle.finish();
  stop.controller.stopLoading('right');
  assert.equal(h.state.stage, 'committing', 'inactive target must not cancel');
  assert.equal(h.timers.size, 1);
  assert.equal(h.unlocks.length, 0);
  h.facts = { ...h.facts, activeTabId: 'right' };
  stop.controller.stopLoading('right');
  assert.deepEqual(stop.notifications, ['right', 'right']);
  assertSwipeReleased(h);
  const published = h.states.length;
  await h.completeSwitch();
  assert.equal(h.switches[0].canApply(), false);
  assert.equal(h.states.length, published);
  assertSwipeReleased(h);
});

test('real stopLoading of another tab keeps target handoff and preview locks', async () => {
  const h = createSwipeHarness();
  const stop = connectStopLoading(h);
  await enterHandoff(h);
  const snapshot = { ...h.state };
  stop.controller.stopLoading('left');
  assert.deepEqual(stop.notifications, ['left']);
  assert.deepEqual(h.state, snapshot);
  assert.equal(h.timers.size, 1);
  assert.equal(h.unlocks.length, 0);
  stop.controller.stopLoading('right');
  assertSwipeReleased(h);
});

test('real stopLoading forwards only native_issued results and supports an absent optional callback', async () => {
  const h = createSwipeHarness();
  const stop = connectStopLoading(h);
  await enterHandoff(h);
  const snapshot = { ...h.state };
  for (const status of ['failed', 'unavailable', 'loading_cancelled', 'transient_consumed']) {
    stop.results.get('right').status = status;
    assert.equal(stop.controller.stopLoading('right'), stop.results.get('right'));
    assert.deepEqual(stop.notifications, []);
    assert.deepEqual(h.state, snapshot);
    assert.equal(h.timers.size, 1);
    assert.equal(h.unlocks.length, 0);
  }
  const calls = stop.calls.length;
  assert.equal(stop.controller.stopLoading('missing').status, 'unavailable');
  assert.equal(stop.calls.length, calls);
  assert.deepEqual(stop.notifications, []);
  const optional = connectStopLoading(h, { notify: false });
  assert.equal(optional.controller.stopLoading('right').status, 'native_issued');
  assert.deepEqual(h.state, snapshot);
  h.coordinator.cancel();
  assertSwipeReleased(h);
});

test('coordinator reduced motion is captured for settle, cancel and handoff durations', async () => {
  for (const reduceMotion of [false, true]) {
    const h = createSwipeHarness({ reduceMotion });
    const settle = h.release();
    assert.equal(h.state.reduceMotion, reduceMotion);
    h.reduceMotion = !reduceMotion;
    if (reduceMotion) assert.equal(settle.duration, 80);
    else assert.ok(settle.duration >= 220 && settle.duration <= 300);
    settle.update();
    settle.finish();
    await h.completeSwitch();
    h.ready = true;
    h.advance(32);
    h.flushFrame();
    h.flushFrame();
    assert.equal(h.animations[1].duration, reduceMotion ? 80 : 120);
    h.animations[1].update();
    h.animations[1].finish();
    assertSwipeReleased(h);
  }
  const canceled = createSwipeHarness({ reduceMotion: true });
  const settleBack = canceled.release(-40);
  assert.equal(settleBack.duration, 80);
  settleBack.update();
  settleBack.finish();
  assertSwipeReleased(canceled);
});

test('coordinator rejected switch returns to idle and releases its monitor and previews', async () => {
  const h = createSwipeHarness();
  const settle = h.release();
  settle.update();
  settle.finish();
  h.switches[0].reject(new Error('switch failed'));
  await new Promise(resolve => setImmediate(resolve));
  assertSwipeReleased(h);
  h.advance(1000);
  assert.equal(h.animations.length, 1);
});

const { BrowserAddressBarTabSwipePolicy } = load('core/browser/BrowserAddressBarTabSwipePolicy.ets');
const policy = new BrowserAddressBarTabSwipePolicy();
function tab(id, overrides = {}) {
  return Object.freeze({ id, isHome: false, profileId: 'default', privacyMode: 'normal',
    dataScope: 'profile_persistent', lastActiveAt: 0, ...overrides });
}
const a = tab('a', { lastActiveAt: 10 });
const b = tab('b', { lastActiveAt: 500, pinned: true });
const c = tab('c', { lastActiveAt: 1 });
const p = tab('private', { privacyMode: 'private' });
const e = tab('ephemeral', { dataScope: 'session_ephemeral' });
const home = tab('home', { isHome: true });
const privateHome = tab('private-home', { isHome: true, privacyMode: 'private' });
const tabs = Object.freeze([home, a, p, b, privateHome, e, c]);

test('neighbors preserve array order, isolate privacy and exclude home without mutating inputs', () => {
  assert.equal(policy.resolveNeighbor(tabs, 'a', -10), b);
  assert.equal(policy.resolveNeighbor(tabs, 'b', -10), c);
  assert.equal(policy.resolveNeighbor(tabs, 'c', 10), b);
  assert.equal(policy.resolveNeighbor(tabs, 'b', 10), a);
  assert.equal(policy.resolveNeighbor(tabs, 'private', -10), e);
  assert.equal(policy.resolveNeighbor(tabs, 'ephemeral', 10), p);
  assert.equal(policy.canStart(tabs, 'private'), true);
  assert.equal(policy.canStart(tabs, 'a'), true);
});

test('edges never wrap; home, missing active IDs and single-tab sections cannot switch', () => {
  for (const [id, offset] of [['a', 10], ['c', -10], ['private', 10], ['ephemeral', -10]]) {
    assert.equal(policy.resolveNeighbor(tabs, id, offset), undefined);
  }
  for (const id of ['home', 'private-home', 'missing', '']) {
    assert.equal(policy.canStart(tabs, id), false);
    for (const offset of [-10, 10]) assert.equal(policy.resolveNeighbor(tabs, id, offset), undefined);
  }
  for (const items of [[], [a], [home, a, p]]) {
    assert.equal(policy.canStart(items, 'a'), false);
    assert.equal(policy.resolveNeighbor(items, 'a', -10), undefined);
    assert.equal(policy.resolveNeighbor(items, 'a', 10), undefined);
  }
  assert.equal(policy.canStart([a, p], 'private'), false);
  assert.equal(policy.resolveNeighbor(tabs, 'b', 0), undefined);
});

test('distance commits at one quarter of width in either direction', () => {
  for (const width of [240, 400, 800]) {
    for (const sign of [-1, 1]) {
      assert.equal(policy.shouldCommit(sign * (width / 4 - 0.1), 0, width, true), false);
      assert.equal(policy.shouldCommit(sign * width / 4, 0, width, true), true);
      assert.equal(policy.shouldCommit(sign * width, sign * 900, width, false), false);
    }
  }
});

test('flings require 650 vp/s, 24 vp travel and matching direction', () => {
  for (const sign of [-1, 1]) {
    assert.equal(policy.shouldCommit(sign * 24, sign * 650, 400, true), true);
    assert.equal(policy.shouldCommit(sign * 23.99, sign * 2000, 400, true), false);
    assert.equal(policy.shouldCommit(sign * 24, sign * 649.99, 400, true), false);
    assert.equal(policy.shouldCommit(sign * 24, -sign * 1000, 400, true), false);
    assert.equal(policy.shouldCommit(0, sign * 2000, 400, true), false);
  }
});

test('deliberate reverse release cancels even after crossing distance threshold', () => {
  for (const sign of [-1, 1]) {
    assert.equal(policy.shouldCommit(sign * 140, -sign * 300, 400, true), false);
    assert.equal(policy.shouldCommit(sign * 140, -sign * 900, 400, true), false);
    assert.equal(policy.shouldCommit(sign * 140, -sign * 50, 400, true), true);
    assert.equal(policy.shouldCommit(sign * 140, sign * 300, 400, true), true);
  }
});

test('normal drag clamps at width + 12; boundary resistance is symmetric, monotonic and bounded', () => {
  for (const sign of [-1, 1]) {
    assert.equal(policy.resolveOffset(sign * 40, 400, true), sign * 40);
    assert.equal(policy.resolveOffset(sign * 1000, 400, true), sign * 412);
    let previous = 0;
    for (const distance of [1, 24, 100, 400, 10000, Number.MAX_VALUE]) {
      const offset = policy.resolveOffset(sign * distance, 400, false);
      assert.equal(Math.sign(offset), sign);
      assert.ok(Math.abs(offset) >= previous && Math.abs(offset) <= 48);
      assert.ok(Math.abs(offset) < distance);
      previous = Math.abs(offset);
    }
  }
  assert.equal(policy.resolveOffset(0, 400, false), 0);
});

test('settle duration follows remaining travel, stays at 220–300 ms and honors reduced motion', () => {
  assert.ok(policy.resolveSettleDuration(40, 400, true, false) >
    policy.resolveSettleDuration(300, 400, true, false));
  assert.ok(policy.resolveSettleDuration(40, 400, false, false) <
    policy.resolveSettleDuration(300, 400, false, false));
  for (const offset of [-10000, -100, 0, 100, 10000]) {
    for (const committed of [false, true]) {
      const duration = policy.resolveSettleDuration(offset, 400, committed, false);
      assert.ok(duration >= 220 && duration <= 300);
      assert.equal(policy.resolveSettleDuration(offset, 400, committed, true), 80);
    }
  }
});

test('non-finite input never leaks invalid geometry or accidentally flings', () => {
  for (const invalid of [NaN, Infinity, -Infinity]) {
    assert.equal(policy.resolveNeighbor(tabs, 'b', invalid), undefined);
    assert.equal(policy.shouldCommit(invalid, 900, 400, true), false);
    assert.equal(policy.shouldCommit(24, invalid, 400, true), false);
    assert.equal(policy.shouldCommit(100, invalid, 400, true), true, 'invalid velocity is treated as rest');
    for (const neighbor of [false, true]) {
      assert.equal(policy.resolveOffset(invalid, 400, neighbor), 0);
    }
  }
  for (const width of [0, -1, NaN, Infinity, -Infinity]) {
    assert.equal(policy.resolveOffset(100, width, true), 0);
    assert.equal(policy.resolveOffset(100, width, false), 0);
    assert.equal(policy.shouldCommit(100, 900, width, true), false);
    for (const offset of [100, NaN, Infinity, -Infinity]) {
      for (const committed of [false, true]) {
        const duration = policy.resolveSettleDuration(offset, width, committed, false);
        assert.ok(Number.isFinite(duration) && duration >= 220 && duration <= 300);
        assert.equal(policy.resolveSettleDuration(offset, width, committed, true), 80);
      }
    }
  }
});
