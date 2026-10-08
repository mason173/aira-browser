const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
function load(name) {
  const filename = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/core/browser', name + '.ets');
  const module = { exports: {} };
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
    fileName: filename
  });
  vm.runInNewContext(output.outputText, { module, exports: module.exports,
    require(id) { throw Error('Unexpected dependency: ' + id); } }, { filename });
  return module.exports;
}
const { BrowserTabSwipeCoverCoordinator: Cover } = load('BrowserTabSwipeCoverCoordinator');
const { BrowserTabPreviewImageLeaseStore: Leases } = load('BrowserTabPreviewImageLeaseStore');
function harness() {
  const frames = [], leases = new Leases(), stored = new Map(), fallback = new Map();
  const pins = [], unpins = [], acquisitions = [];
  const owner = new Cover({
    acquire(tabId) {
      const state = stored.get(tabId);
      if (!state) return undefined;
      const pixel = state.sharedSnapshotPixelMap;
      assert.equal(leases.retain(pixel), true);
      let released = false;
      const lease = { state: { ...state }, release() {
        if (!released) { released = true; void leases.releaseLease(pixel); }
      } };
      acquisitions.push(lease);
      return lease;
    },
    readFallback: id => fallback.get(id), pinFallback: id => pins.push(id),
    unpinFallback: id => unpins.push(id), afterFrame: callback => frames.push(callback)
  });
  return { owner, stored, fallback, frames, pins, unpins, acquisitions,
    flushFrame() { frames.splice(0).forEach(callback => callback()); },
    drop(pixel) { return leases.requestRelease(pixel, () => pixel.release()); },
    set(id, name) {
      const pixel = { name, released: 0, async release() { this.released++; } };
      const state = { tabId: id, sharedSnapshotPixelMap: pixel, capturedAt: Date.now() };
      stored.set(id, state); return pixel;
    }
  };
}

test('a displayed card screenshot survives cache refresh, clear and delayed disposal', async () => {
  const h = harness(), first = h.set('a', 'first');
  h.owner.pin('a');
  const selected = h.owner.resolve('a');
  const replacement = h.set('a', 'replacement');
  await h.drop(first);
  assert.equal(first.released, 0);
  assert.equal(h.owner.resolve('a'), selected);
  h.stored.clear();
  assert.equal(h.owner.resolve('a'), selected, 'cache clearing cannot blank an ongoing gesture');
  h.owner.unpin('a');
  assert.equal(h.owner.resolve('a'), undefined);
  assert.equal(first.released, 0);
  h.flushFrame(); assert.equal(first.released, 0);
  h.flushFrame(); assert.equal(first.released, 1);
  assert.equal(replacement.released, 0);
  h.owner.dispose(); h.flushFrame();
  assert.equal(first.released, 1);
});

test('direction reversal reuses the pinned neighbor image instead of reloading newer thumbnails', async () => {
  const h = harness(), a = h.set('a', 'left'), b = h.set('b', 'right');
  h.owner.pin('a'); h.owner.pin('b');
  const left = h.owner.resolve('a'), right = h.owner.resolve('b');
  h.set('a', 'later-left'); h.set('b', 'later-right');
  await h.drop(a); await h.drop(b);
  assert.equal(h.owner.resolve('b'), right);
  assert.equal(h.owner.resolve('a'), left);
  h.owner.unpin('a'); h.owner.unpin('b');
  h.flushFrame(); h.flushFrame();
  assert.equal(a.released, 1); assert.equal(b.released, 1);
});

test('a missing preview can be filled once; later cache notifications never change its source', () => {
  const h = harness();
  h.owner.pin('a');
  assert.equal(h.owner.resolve('a'), undefined);
  const image = h.set('a', 'arrived');
  const cover = h.owner.resolve('a');
  assert.equal(cover.sharedSnapshotPixelMap, image);
  h.set('a', 'later');
  assert.equal(h.owner.resolve('a'), cover);
  h.owner.dispose();
});

test('stored screenshot takes priority, fallback selection is also stable', () => {
  const h = harness();
  h.fallback.set('a', { tabId: 'a', sharedSnapshotPixelMap: {} });
  const stored = h.set('a', 'stored');
  h.owner.pin('a');
  assert.equal(h.owner.resolve('a').sharedSnapshotPixelMap, stored);
  h.fallback.set('b', { tabId: 'b', sharedSnapshotPixelMap: {} });
  h.owner.pin('b');
  const fallback = h.owner.resolve('b');
  h.set('b', 'later'); h.fallback.delete('b');
  assert.equal(h.owner.resolve('b'), fallback);
  h.owner.dispose();
  assert.deepEqual(h.unpins.sort(), ['a', 'b']);
});

test('a new gesture has an independent lease while the old image awaits render removal', async () => {
  const h = harness(), old = h.set('a', 'old');
  h.owner.pin('a'); h.owner.resolve('a'); h.owner.unpin('a');
  await h.drop(old);
  const next = h.set('a', 'new');
  h.owner.pin('a');
  assert.equal(h.owner.resolve('a').sharedSnapshotPixelMap, next);
  h.flushFrame(); h.flushFrame();
  assert.equal(old.released, 1); assert.equal(next.released, 0);
  await h.drop(next);
  h.owner.dispose(); h.owner.dispose(); h.flushFrame(); h.flushFrame();
  assert.equal(next.released, 1);
});

test('dispose drains current and pending leases; queued frames cannot double-release', async () => {
  const h = harness(), a = h.set('a', 'a'), b = h.set('b', 'b');
  h.owner.pin('a'); h.owner.pin('b');
  await h.drop(a); await h.drop(b);
  h.owner.unpin('a');
  h.owner.dispose();
  h.flushFrame(); h.flushFrame();
  h.owner.pin('a');
  assert.equal(h.owner.resolve('a'), undefined);
  assert.equal(a.released, 1); assert.equal(b.released, 1);
  assert.deepEqual(h.unpins.sort(), ['a', 'b']);
});
