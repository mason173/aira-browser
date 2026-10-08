const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');

const filename = path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/ets/core/browser/BrowserTabSwipePreviewCoordinator.ets');
const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  fileName: filename, reportDiagnostics: true
});
assert.equal((result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
const drain = () => new Promise(resolve => setImmediate(resolve));
const tab = (id, extra = {}) => ({ id, profileId: 'default', privacyMode: 'regular',
  dataScope: 'profile_persistent', url: `https://${id}.example/`, isHome: false, ...extra });
const image = (id, width = 400, height = 800) => ({ pixelMap: { id }, width, height });

function harness() {
  let now = 1000;
  let timerId = 0;
  const timers = new Map();
  const module = { exports: {} };
  class FakeDate extends Date { static now() { return now; } }
  vm.runInNewContext(result.outputText, {
    module, exports: module.exports, Date: FakeDate,
    require(specifier) { assert.fail(`Swipe owner must not access overview or platform services: ${specifier}`); },
    setTimeout(callback, delay) {
      const id = ++timerId;
      timers.set(id, { callback, due: now + delay });
      return id;
    },
    clearTimeout(id) { timers.delete(id); }
  }, { filename });
  const h = {
    facts: { windowId: 'w1', tabs: [tab('a'), tab('b')], activeTabId: 'a',
      canCapture: true, motionActive: false, viewportWidth: 400, viewportHeight: 800 },
    generations: new Map(), requests: [], released: [], changes: 0, timers, frameQueue: [],
    throwNotify: false, throwRelease: false, throwCapture: false, reads: 0, ready: false,
    flushFrame() {
      const callbacks = this.frameQueue.splice(0);
      callbacks.forEach(callback => callback());
    },
    flushFrames(count) {
      for (let i = 0; i < count; i++) this.flushFrame();
    },
    advance(ms) {
      const end = now + ms;
      let count = 0;
      while (true) {
        const next = [...timers].filter(([, value]) => value.due <= end)
          .sort((a, b) => a[1].due - b[1].due || a[0] - b[0])[0];
        if (!next) break;
        assert.ok(++count < 10000);
        now = next[1].due;
        timers.delete(next[0]);
        next[1].callback();
      }
      now = end;
    },
    async capture(id = `image-${this.requests.length}`, width = 400, height = 800) {
      const task = this.owner.captureActive();
      const value = image(id, width, height);
      this.requests.at(-1).resolve(value);
      assert.equal(await task, true);
      return value.pixelMap;
    },
    state(id = 'a') { return this.owner.getPreviewState(id); },
    finish() {
      this.owner.clear();
      for (const id of this.facts.tabs.map(tab => tab.id)) this.owner.unpin(id);
      this.flushFrames(2);
      assert.equal(new Set(this.released).size, this.released.length, 'release each PixelMap only once');
    }
  };
  h.owner = new module.exports.BrowserTabSwipePreviewCoordinator({
    readFacts: () => {
      h.reads++;
      assert.ok(h.ready, 'constructor must not read unfinished Shell fields');
      return h.facts;
    },
    getHostedGeneration: id => h.generations.get(id) || 0,
    capture: id => {
      if (h.throwCapture) throw new Error('capture failed synchronously');
      return new Promise((resolve, reject) => h.requests.push({ id, resolve, reject }));
    },
    release: pixelMap => {
      h.released.push(pixelMap);
      if (h.throwRelease) throw new Error('release failed');
    },
    afterFrame: callback => { h.frameQueue.push(callback); },
    notifyChanged: () => {
      h.changes++;
      if (h.throwNotify) throw new Error('notification failed');
    }
  });
  h.ready = true;
  return h;
}

test('constructor defers facts and window initialization until first reconcile', () => {
  const h = harness();
  assert.equal(h.reads, 0);
  assert.equal(h.owner.windowId, undefined);
  h.facts.windowId = 'initialized-shell';
  h.owner.reconcile();
  assert.equal(h.owner.windowId, 'initialized-shell');
  assert.equal(h.changes, 0);
  h.finish();
});

test('valid getter is pure and does not consult hosted generation', async () => {
  const h = harness();
  const cached = await h.capture();
  const changes = h.changes;
  const clock = h.owner.clock;
  h.owner.host.getHostedGeneration = () => assert.fail('getter read runtime generation');
  for (const method of ['reconcile', 'notify', 'release', 'clear']) {
    const original = h.owner[method];
    h.owner[method] = () => assert.fail(`getter called ${method}`);
    assert.equal(h.state().sharedSnapshotPixelMap, cached);
    h.owner[method] = original;
  }
  assert.equal(h.changes, changes);
  assert.equal(h.owner.clock, clock);
  assert.deepEqual(h.released, []);
  h.finish();
});

for (const reconcile of [false, true]) {
  test(`background generation preserves history and rejects in-flight capture (reconcile=${reconcile})`, async () => {
    const h = harness();
    const cached = await h.capture('history');
    const task = h.owner.captureActive();
    h.facts.activeTabId = 'b';
    h.generations.set('a', 1);
    if (reconcile) h.owner.reconcile();
    assert.equal(h.state('a').sharedSnapshotPixelMap, cached);
    h.facts.activeTabId = 'a';
    const late = image('old-generation');
    h.requests.at(-1).resolve(late);
    assert.equal(await task, false);
    assert.equal(h.state().sharedSnapshotPixelMap, cached);
    assert.deepEqual(h.released, [late.pixelMap]);
    h.owner.reconcile();
    assert.equal(h.state().sharedSnapshotPixelMap, cached);
    h.owner.noteDocumentBegin('a');
    assert.equal(h.state(), undefined);
    assert.deepEqual(h.released, [late.pixelMap, cached]);
    h.finish();
  });
}

test('generation prevents deduplication of a new capture with an old run', async () => {
  const h = harness();
  const old = h.owner.captureActive();
  h.generations.set('a', 1);
  const current = h.owner.captureActive();
  assert.notEqual(current, old);
  h.requests[1].resolve(image('new-generation'));
  assert.equal(await current, true);
  h.requests[0].resolve(image('old-generation'));
  assert.equal(await old, false);
  h.finish();
});

for (const cleanup of ['closed tab', 'ephemeral']) {
  test(`${cleanup} clears revisions, keeps pins, and rejects asynchronous results after ID reuse`, async () => {
    const h = harness();
    h.facts.tabs[0].dataScope = 'session_ephemeral';
    h.owner.noteDocumentBegin('a');
    h.facts.motionActive = true;
    h.owner.handleScroll('a');
    const cached = await h.capture('owned');
    h.owner.pin('a');
    const old = h.owner.captureActive();
    if (cleanup === 'closed tab') {
      h.facts.tabs = [tab('b')];
      h.owner.reconcile();
    } else {
      // Include tabs with revisions but no cache or outstanding capture.
      h.facts.tabs.push(tab('revision-only', { privacyMode: 'private' }));
      h.owner.noteDocumentBegin('revision-only');
      h.owner.handleScroll('revision-only');
      h.facts.tabs = [tab('b')];
      h.owner.clearEphemeral();
      assert.equal(h.owner.documents.has('revision-only'), false);
      assert.equal(h.owner.scrolls.has('revision-only'), false);
    }
    assert.equal(h.owner.documents.has('a'), false);
    assert.equal(h.owner.scrolls.has('a'), false);
    assert.equal(h.owner.pins.get('a'), 1);
    h.facts.tabs.push(tab('a', { dataScope: 'session_ephemeral' }));
    const late = image('reused-id-late');
    h.requests.at(-1).resolve(late);
    assert.equal(await old, false);
    assert.equal(h.state(), undefined);
    assert.deepEqual(h.released, [late.pixelMap]);
    h.owner.unpin('a');
    h.flushFrames(2);
    assert.deepEqual(h.released, [late.pixelMap, cached]);
    await h.capture('reused-id-new');
    h.finish();
  });
}

test('root viewport remains valid across active-page bottom reservations', async () => {
  const h = harness();
  const cached = await h.capture('root-sized');
  h.facts.tabs[0].bottomReservation = 120;
  h.facts.tabs[1].bottomReservation = 48;
  h.facts.activeTabId = 'b';
  h.owner.reconcile();
  assert.equal(h.state('a').sharedSnapshotPixelMap, cached);
  h.facts.viewportHeight = 900;
  assert.equal(h.state('a'), undefined);
  h.owner.reconcile();
  assert.deepEqual(h.released, [cached]);
  h.finish();
});

test('bare-page state has only independent in-memory image and exact transition metadata', async () => {
  const h = harness();
  const overviewPixelMap = { id: 'overview' };
  h.facts.tabs[0].sharedSnapshotPixelMap = overviewPixelMap;
  const captured = await h.capture('bare-page');
  assert.equal(h.state().sharedSnapshotPixelMap, captured);
  assert.notEqual(captured, overviewPixelMap);
  assert.deepEqual(Object.keys(h.state()).sort(), ['tabId', 'sharedSnapshotPixelMap',
    'sharedSnapshotImageWidth', 'sharedSnapshotImageHeight', 'capturedAt', 'transitionSource'].sort());
  assert.equal(h.state().sharedSnapshotImageWidth, 400);
  assert.equal(h.state().sharedSnapshotImageHeight, 800);
  assert.equal(h.state().capturedAt, 1000);
  assert.deepEqual(JSON.parse(JSON.stringify(h.state().transitionSource)), {
    captureSource: 'component', captureScope: 'web-content', transitionFrame: 'current-web'
  });
  h.finish();
  assert.deepEqual(h.released, [captured]);
});

test('explicit capture refreshes fresh images; per-tab in-flight requests deduplicate', async () => {
  const h = harness();
  const first = h.owner.captureActive();
  assert.equal(h.owner.captureActive(), first);
  assert.equal(h.requests.length, 1);
  const old = image('old');
  h.requests[0].resolve(old);
  assert.equal(await first, true);
  const fresh = await h.capture('fresh');
  assert.equal(h.state().sharedSnapshotPixelMap, fresh);
  assert.deepEqual(h.released, [old.pixelMap]);
  h.finish();
});

test('automatic scheduling debounces and checks motion again at dispatch', async () => {
  const h = harness();
  h.owner.schedule();
  h.advance(200);
  h.owner.schedule();
  h.advance(249);
  assert.equal(h.requests.length, 0);
  h.advance(1);
  assert.equal(h.requests.length, 1);
  h.requests[0].resolve(image('auto'));
  await drain();
  h.owner.schedule();
  h.facts.motionActive = true;
  h.advance(250);
  assert.equal(h.requests.length, 1);
  h.owner.schedule();
  assert.equal(h.timers.size, 0);
  h.finish();
});

test('motion does not reject explicit capture or a previously issued bare-page capture', async () => {
  const h = harness();
  const task = h.owner.captureActive();
  h.facts.motionActive = true;
  h.owner.reconcile();
  h.requests[0].resolve(image('before-motion'));
  assert.equal(await task, true);
  await h.capture('during-motion');
  h.finish();
});

test('scroll invalidates in-flight capture and debounces a replacement by 200ms', async () => {
  const h = harness();
  const old = await h.capture('cached');
  const task = h.owner.captureActive();
  const late = image('scrolled');
  h.owner.handleScroll('a');
  h.advance(150);
  h.owner.handleScroll('a');
  h.requests[1].resolve(late);
  assert.equal(await task, false);
  assert.equal(h.state().sharedSnapshotPixelMap, old);
  h.advance(199);
  assert.equal(h.requests.length, 2);
  h.advance(1);
  assert.equal(h.requests.length, 3);
  h.requests[2].resolve(image('after-scroll'));
  await drain();
  assert.deepEqual(h.released, [late.pixelMap, old]);
  h.facts.motionActive = true;
  h.owner.handleScroll('a');
  assert.equal(h.timers.size, 0);
  h.finish();
});

test('pin freezes image, rejects replacement, and reference-counts deferred retirement', async () => {
  const h = harness();
  const old = await h.capture('pinned');
  h.owner.pin('a');
  h.owner.pin('a');
  const task = h.owner.captureActive();
  const rejected = image('replacement');
  h.requests.at(-1).resolve(rejected);
  assert.equal(await task, false);
  assert.equal(h.state().sharedSnapshotPixelMap, old);
  assert.deepEqual(h.released, [rejected.pixelMap]);
  h.owner.noteDocumentBegin('a');
  assert.equal(h.state(), undefined);
  h.owner.clear();
  h.owner.unpin('a');
  h.flushFrames(2);
  assert.ok(!h.released.includes(old));
  h.owner.unpin('a');
  h.flushFrame();
  assert.ok(!h.released.includes(old));
  h.flushFrame();
  assert.deepEqual(h.released, [rejected.pixelMap, old]);
  h.finish();
});

for (const [name, mutate] of [
  ['window', h => { h.facts.windowId = 'w2'; h.owner.reconcile(); }],
  ['deleted tab', h => { h.facts.tabs = [tab('b')]; h.owner.reconcile(); }],
  ['active tab', h => { h.facts.activeTabId = 'b'; }],
  ['document', h => h.owner.noteDocumentBegin('a')],
  ['hosted generation', h => h.generations.set('a', 1)],
  ['URL', h => { h.facts.tabs[0].url = 'https://new.example/'; }],
  ['profile', h => { h.facts.tabs[0].profileId = 'other'; }],
  ['privacy', h => { h.facts.tabs[0].privacyMode = 'private'; }],
  ['data scope', h => { h.facts.tabs[0].dataScope = 'session_ephemeral'; }],
  ['viewport width', h => { h.facts.viewportWidth = 500; }],
  ['viewport height', h => { h.facts.viewportHeight = 900; }],
  ['capture permission', h => { h.facts.canCapture = false; }]
]) {
  test(`${name} change rejects late image with exactly one release`, async () => {
    const h = harness();
    const task = h.owner.captureActive();
    mutate(h);
    const late = image(name);
    h.requests[0].resolve(late);
    assert.equal(await task, false);
    assert.equal(h.state(), undefined);
    assert.deepEqual(h.released, [late.pixelMap]);
    h.finish();
  });
}

for (const [name, mutate] of [
  ['window', h => { h.facts.windowId = 'w2'; }],
  ['profile', h => { h.facts.tabs[0].profileId = 'other'; }],
  ['privacy', h => { h.facts.tabs[0].privacyMode = 'private'; }],
  ['scope', h => { h.facts.tabs[0].dataScope = 'session_ephemeral'; }],
  ['URL', h => { h.facts.tabs[0].url += 'new'; }],
  ['document', h => h.owner.noteDocumentBegin('a')],
  ['tab removal', h => { h.facts.tabs = [tab('b')]; }]
]) {
  test(`get hides pinned cache on ${name} mismatch, retaining resource until unpin`, async () => {
    const h = harness();
    const cached = await h.capture('cached');
    h.owner.pin('a');
    mutate(h);
    const changes = h.changes;
    const entries = h.owner.entries.size;
    const clock = h.owner.clock;
    for (const method of ['reconcile', 'notify', 'release', 'clear']) {
      const original = h.owner[method];
      h.owner[method] = () => assert.fail(`getter called ${method}`);
      assert.equal(h.state(), undefined);
      h.owner[method] = original;
    }
    assert.equal(h.changes, changes);
    assert.equal(h.owner.entries.size, entries);
    assert.equal(h.owner.clock, clock);
    assert.deepEqual(h.released, []);
    h.owner.reconcile();
    h.owner.unpin('a');
    h.flushFrames(2);
    assert.deepEqual(h.released, [cached]);
    h.finish();
  });
}




test('private cleanup cancels only ephemeral work and preserves regular cache and capture', async () => {
  const h = harness();
  const regular = await h.capture('regular');
  h.facts.tabs.push(tab('private', { privacyMode: 'private', dataScope: 'session_ephemeral' }));
  h.facts.activeTabId = 'private';
  const privateImage = await h.capture('private');
  h.owner.pin('private');
  const privateTask = h.owner.captureActive();
  h.owner.schedule();
  h.owner.clearEphemeral();
  assert.equal(h.timers.size, 0);
  assert.equal(h.state('private'), undefined);
  assert.equal(h.state('a').sharedSnapshotPixelMap, regular);
  assert.deepEqual(h.released, []);
  const late = image('private-late');
  h.requests.at(-1).resolve(late);
  assert.equal(await privateTask, false);
  h.owner.unpin('private');
  h.flushFrames(2);
  assert.deepEqual(h.released, [late.pixelMap, privateImage]);
  h.facts.activeTabId = 'a';
  const regularTask = h.owner.captureActive();
  h.owner.schedule();
  h.owner.clearEphemeral();
  assert.equal(h.timers.size, 1);
  h.requests.at(-1).resolve(image('regular-new'));
  assert.equal(await regularTask, true);
  h.finish();
});

test('session_ephemeral scope is cleaned even with regular privacy mode', async () => {
  const h = harness();
  h.facts.tabs[0].dataScope = 'session_ephemeral';
  const cached = await h.capture('ephemeral');
  h.owner.clearEphemeral();
  assert.equal(h.state(), undefined);
  assert.deepEqual(h.released, [cached]);
  h.finish();
});

test('suspend retains cache and cancels pending and late captures; clear releases remaining cache', async () => {
  const h = harness();
  const cached = await h.capture('cached');
  const task = h.owner.captureActive();
  h.owner.schedule();
  h.owner.suspend();
  assert.equal(h.timers.size, 0);
  assert.equal(h.state().sharedSnapshotPixelMap, cached);
  const late = image('suspended');
  h.requests.at(-1).resolve(late);
  assert.equal(await task, false);
  h.owner.clear();
  assert.equal(h.state(), undefined);
  assert.deepEqual(h.released, [late.pixelMap, cached]);
  h.finish();
});

test('cache bounds entries at eight, skips pins, and getters do not change eviction order', async () => {
  const h = harness();
  h.facts.tabs = Array.from({ length: 10 }, (_, i) => tab(`t${i}`));
  const images = [];
  for (let i = 0; i < 8; i++) {
    h.facts.activeTabId = `t${i}`;
    images.push(await h.capture(`i${i}`, 100, 100));
  }
  h.owner.pin('t0');
  h.state('t1');
  h.facts.activeTabId = 't8';
  await h.capture('i8', 100, 100);
  assert.equal(h.state('t1'), undefined);
  assert.deepEqual(h.released, [images[1]]);
  assert.ok(h.state('t0'));
  assert.ok(h.state('t2'));
  h.finish();
});

test('32MiB bound evicts unpinned images and rejects incoming images when all residents pinned', async () => {
  const h = harness();
  const first = await h.capture('16MiB-a', 2048, 2048);
  h.owner.pin('a');
  h.facts.activeTabId = 'b';
  const second = await h.capture('16MiB-b', 2048, 2048);
  h.owner.pin('b');
  h.facts.tabs.push(tab('c'));
  h.facts.activeTabId = 'c';
  const task = h.owner.captureActive();
  const rejected = image('over-budget', 1, 1);
  h.requests.at(-1).resolve(rejected);
  assert.equal(await task, false);
  assert.deepEqual(h.released, [rejected.pixelMap]);
  h.owner.unpin('b');
  h.flushFrames(2);
  await h.capture('16MiB-c', 2048, 2048);
  assert.ok(h.state('a'));
  assert.equal(h.state('b'), undefined);
  assert.deepEqual(h.released, [rejected.pixelMap, second]);
  assert.ok(!h.released.includes(first));
  h.finish();
});

test('retired pinned images still count toward memory budget', async () => {
  const h = harness();
  await h.capture('32MiB-pinned', 4096, 2048);
  h.owner.pin('a');
  h.owner.noteDocumentBegin('a');
  h.facts.activeTabId = 'b';
  const task = h.owner.captureActive();
  const incoming = image('too-much', 1, 1);
  h.requests.at(-1).resolve(incoming);
  assert.equal(await task, false);
  assert.deepEqual(h.released, [incoming.pixelMap]);
  h.owner.unpin('a');
  h.owner.unpin('a');
  h.owner.pin('a');
  h.owner.unpin('a');
  const beforeFrame = h.owner.captureActive();
  const stillTooMuch = image('release-not-yet-complete', 1, 1);
  h.requests.at(-1).resolve(stillTooMuch);
  assert.equal(await beforeFrame, false);
  assert.equal(h.released.at(-1), stillTooMuch.pixelMap);
  h.flushFrames(2);
  await h.capture('after-unpin');
  h.finish();
});

for (const cleanup of ['clear', 'clearEphemeral', 'noteDocumentBegin']) {
  test(`final unpin protects active image through same-frame ${cleanup}, even without a live host`, async () => {
    const h = harness();
    h.facts.tabs[0].dataScope = 'session_ephemeral';
    const cached = await h.capture('frozen-shell-preview');
    const frozen = h.state();
    h.owner.pin('a');
    h.owner.unpin('a');
    h.owner[cleanup]('a');
    h.owner.clearEphemeral();
    h.owner.clear();
    assert.equal(h.state(), undefined);
    assert.equal(frozen.sharedSnapshotPixelMap, cached);
    assert.equal(h.owner.pins.get('a'), 1);
    assert.deepEqual(h.released, []);
    const changes = h.changes;
    h.owner.host.readFacts = () => assert.fail('deferred unpin must not read a destroyed host');
    h.owner.host.notifyChanged = () => assert.fail('deferred release needs no UI notification');
    h.throwRelease = true;
    h.owner.unpin('a'); // Duplicate unpin must not advance or extend the deadline.
    h.flushFrame();
    assert.deepEqual(h.released, []);
    h.flushFrame();
    assert.deepEqual(h.released, [cached]);
    assert.equal(h.owner.pins.has('a'), false);
    assert.equal(h.owner.retired.length, 0);
    assert.equal(h.owner.releasing.length, 0);
    h.advance(100);
    assert.deepEqual(h.released, [cached]);
    assert.equal(h.changes, changes);
  });
}

test('same-frame capture after final unpin cannot replace the frozen active image', async () => {
  const h = harness();
  const cached = await h.capture('frozen');
  h.owner.pin('a');
  h.owner.unpin('a');
  const task = h.owner.captureActive();
  const incoming = image('same-frame');
  h.requests.at(-1).resolve(incoming);
  assert.equal(await task, false);
  assert.equal(h.state().sharedSnapshotPixelMap, cached);
  assert.deepEqual(h.released, [incoming.pixelMap]);
  h.flushFrame();
  assert.deepEqual(h.released, [incoming.pixelMap]);
  h.flushFrame();
  assert.equal(h.owner.pins.has('a'), false);
  assert.equal(h.state().sharedSnapshotPixelMap, cached);
  await h.capture('after-frame');
  assert.deepEqual(h.released, [incoming.pixelMap, cached]);
  h.finish();
});

for (const retire of [false, true]) {
  test(`new gesture inherits deferred pin and gets its own full frame delay (retired=${retire})`, async () => {
    const h = harness();
    const cached = await h.capture('shared-between-gestures');
    h.owner.pin('a');
    if (retire) h.owner.clear();
    h.owner.unpin('a');
    h.advance(8);
    h.owner.pin('a');
    h.owner.pin('a');
    assert.equal(h.owner.pins.get('a'), 2);
    h.advance(8); // The previous gesture's deadline must not remove the new pins.
    assert.equal(h.owner.pins.get('a'), 2);
    h.owner.unpin('a');
    h.flushFrames(2);
    assert.deepEqual(h.released, []);
    h.owner.unpin('a');
    h.owner.clear();
    h.flushFrame();
    assert.deepEqual(h.released, []);
    h.flushFrame();
    assert.deepEqual(h.released, [cached]);
    assert.equal(h.owner.pins.has('a'), false);
    h.finish();
  });
}

for (const bound of ['bytes', 'entries']) {
  for (const retire of [false, true]) {
    test(`${bound} budget includes final-unpin images until frame deadline (retired=${retire})`, async () => {
      const h = harness();
      const count = bound === 'bytes' ? 1 : 8;
      h.facts.tabs = Array.from({ length: count + 1 }, (_, i) => tab(`t${i}`));
      const cached = [];
      for (let i = 0; i < count; i++) {
        h.facts.activeTabId = `t${i}`;
        cached.push(await h.capture(`resident-${i}`, bound === 'bytes' ? 4096 : 1,
          bound === 'bytes' ? 2048 : 1));
        h.owner.pin(`t${i}`);
        h.owner.unpin(`t${i}`);
      }
      if (retire) h.owner.clear();
      h.facts.activeTabId = `t${count}`;
      const task = h.owner.captureActive();
      const incoming = image('over-budget', 1, 1);
      h.requests.at(-1).resolve(incoming);
      assert.equal(await task, false);
      assert.deepEqual(h.released, [incoming.pixelMap]);
      h.flushFrame();
      assert.deepEqual(h.released, [incoming.pixelMap]);
      h.flushFrame();
      await h.capture('after-frame', 1, 1);
      h.finish();
      for (const pixelMap of cached) {
        assert.equal(h.released.filter(value => value === pixelMap).length, 1);
      }
    });
  }
}

test('old canceled run settling cannot remove a newer in-flight run for the same tab', async () => {
  const h = harness();
  const oldTask = h.owner.captureActive();
  h.owner.handleScroll('a');
  const nextTask = h.owner.captureActive();
  const late = image('old-scroll');
  h.requests[0].resolve(late);
  assert.equal(await oldTask, false);
  assert.equal(h.owner.captureActive(), nextTask);
  assert.equal(h.requests.length, 2);
  h.requests[1].resolve(image('new-scroll'));
  assert.equal(await nextTask, true);
  assert.deepEqual(h.released, [late.pixelMap]);
  h.finish();
});

test('window reconcile clears all caches, cancels schedule, and rejects previous-window work', async () => {
  const h = harness();
  const cached = await h.capture('old-window-cache');
  const task = h.owner.captureActive();
  h.owner.schedule();
  h.facts.windowId = 'new-window';
  h.owner.reconcile();
  assert.equal(h.state(), undefined);
  assert.equal(h.timers.size, 0);
  assert.deepEqual(h.released, [cached]);
  const late = image('old-window-late');
  h.requests.at(-1).resolve(late);
  assert.equal(await task, false);
  await h.capture('new-window');
  assert.deepEqual(h.released, [cached, late.pixelMap]);
  h.finish();
});

test('capture rejection, invalid size, oversized image and throwing callbacks do not leak or double release', async () => {
  const h = harness();
  h.throwCapture = true;
  assert.equal(await h.owner.captureActive(), false);
  h.throwCapture = false;
  const rejectedTask = h.owner.captureActive();
  h.requests.at(-1).reject(new Error('snapshot failed'));
  assert.equal(await rejectedTask, false);
  const emptyTask = h.owner.captureActive();
  h.requests.at(-1).resolve(undefined);
  assert.equal(await emptyTask, false);
  for (const [width, height] of [[0, 1], [-1, 1], [NaN, 1], [Infinity, 1], [8192, 8192]]) {
    const task = h.owner.captureActive();
    const invalid = image('invalid', width, height);
    h.requests.at(-1).resolve(invalid);
    assert.equal(await task, false);
    assert.equal(h.released.at(-1), invalid.pixelMap);
  }
  h.throwNotify = true;
  const owned = await h.capture('notification-throws');
  assert.equal(h.state().sharedSnapshotPixelMap, owned);
  assert.ok(!h.released.includes(owned));
  h.throwRelease = true;
  h.finish();
  assert.equal(h.released.at(-1), owned);
});

test('dispose releases all ownership and invalidates queued frame callbacks', async () => {
  const h = harness();
  const cached = await h.capture('dispose-cached');
  h.owner.pin('a');
  h.owner.clear();
  h.owner.unpin('a');
  h.owner.dispose();
  assert.deepEqual(h.released, [cached]);
  h.flushFrames(3);
  assert.deepEqual(h.released, [cached]);
  h.owner.dispose();
});

test('home, missing tab, no viewport and disabled capture never invoke snapshot host', async () => {
  for (const mutate of [
    h => { h.facts.tabs[0].isHome = true; },
    h => { h.facts.tabs = []; },
    h => { h.facts.viewportWidth = 0; },
    h => { h.facts.viewportWidth = NaN; },
    h => { h.facts.viewportHeight = Infinity; },
    h => { h.facts.canCapture = false; }
  ]) {
    const h = harness();
    mutate(h);
    assert.equal(await h.owner.captureActive(), false);
    h.owner.schedule();
    h.advance(1000);
    assert.equal(h.requests.length, 0);
    h.finish();
  }
});
