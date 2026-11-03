'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function createStore() {
  const cache = new Map();
  class Scroller {
    value = undefined;
    currentOffset() { return this.value; }
    offset() { return this.value; }
  }
  function load(relative) {
    if (cache.has(relative)) return cache.get(relative);
    const filename = path.join(root, relative + '.ets');
    const module = { exports: {} };
    cache.set(relative, module.exports);
    vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
    }).outputText, {
      module, exports: module.exports, Scroller,
      require(id) {
        if (id === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
        if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
        assert.ok(id.startsWith('.'), `Unexpected platform import: ${id}`);
        return load(path.relative(root, path.resolve(path.dirname(filename), id)));
      }
    }, { filename });
    return module.exports;
  }
  return new (load('features/bookmarks/BookmarkRootPageStore').BookmarkRootPageStore)();
}

for (const scope of ['regular', 'private']) {
  for (const page of ['toolbar', 'other']) {
    test(`${scope} ${page}: populated root remains safe before mount and after detach`, () => {
      const store = createStore();
      const rootId = page === 'toolbar' ? store.toolbarRootId(scope) : store.otherRootId(scope);
      store.replace(rootId, scope, [{ id: 'bookmark', title: 'Bookmark', position: 0, updatedAt: 1 }]);
      const scroller = store.scrollerFor(rootId, scope);
      // The native Scroller returns undefined while its list is not bound.
      assert.equal(store.titleElevated(rootId, scope), false);
      scroller.value = { xOffset: 0, yOffset: 24 };
      assert.equal(store.titleElevated(rootId, scope), true);
      scroller.value = undefined;
      assert.equal(store.titleElevated(rootId, scope), false);
      scroller.value = { xOffset: 0, yOffset: 0 };
      assert.equal(store.titleElevated(rootId, scope), false);
    });
  }
}

test('title elevation preserves the scroll threshold and rejects invalid offsets', () => {
  const store = createStore();
  const rootId = store.toolbarRootId('regular');
  store.replace(rootId, 'regular', [{ id: 'bookmark' }]);
  for (const [offset, elevated] of [[-1, false], [8, false], [8.1, true], [NaN, false], [Infinity, false]]) {
    store.toolbarScroller.value = { xOffset: 0, yOffset: offset };
    assert.equal(store.titleElevated(rootId, 'regular'), elevated);
  }
});

test('empty roots do not consult their scroll controller', () => {
  const store = createStore();
  const unexpectedRead = () => { throw new Error('Empty root must not query a scroller'); };
  store.toolbarScroller.currentOffset = store.toolbarScroller.offset = unexpectedRead;
  store.otherScroller.currentOffset = store.otherScroller.offset = unexpectedRead;
  for (const scope of ['regular', 'private']) {
    assert.equal(store.titleElevated(store.toolbarRootId(scope), scope), false);
    assert.equal(store.titleElevated(store.otherRootId(scope), scope), false);
  }
});

function loadListScrollHandlers() {
  const filename = path.join(root, 'app/components/bookmarks/BookmarkRecordList.ets');
  const source = fs.readFileSync(filename, 'utf8');
  // Execute the callback wired to the real List, including its native-controller read.
  const callback = source.match(/\.onDidScroll\(([\s\S]*?)\n    \}\)/);
  const dragOffset = source.match(/  private resolveScrollOffsetY\(\): number \{[\s\S]*?\n  \}/);
  assert.ok(callback, 'Bookmark List must report scroll changes');
  assert.ok(dragOffset, 'Bookmark drag must resolve its scroll position');
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(`
    export function bindScrollCallback() { return ${callback[1]}\n}; }
    export class DragScrollProbe { ${dragOffset[0]} }
  `, { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS } }).outputText, {
    module, exports: module.exports,
    resolveBrowserSheetHeaderBlurRadius: offset => offset * 2
  }, { filename });
  return module.exports;
}

test('real List callback ignores unbound scroll events and resumes after reattachment', () => {
  const { bindScrollCallback } = loadListScrollHandlers();
  const published = [];
  let position;
  const host = {
    scroller: { currentOffset: () => position, offset: () => position },
    headerBlurRadius: 0,
    onScrollOffsetChange: offset => published.push(offset)
  };
  const onDidScroll = bindScrollCallback.call(host);
  onDidScroll(0, 0);
  assert.deepEqual(published, []);
  position = { xOffset: 0, yOffset: 24 };
  onDidScroll(24, 1);
  assert.deepEqual(published, [24]);
  assert.equal(host.headerBlurRadius, 48);
  position = undefined;
  onDidScroll(0, 0);
  assert.deepEqual(published, [24], 'detached list must not overwrite the active root header');
  assert.equal(host.headerBlurRadius, 48);
  position = { xOffset: 0, yOffset: 0 };
  onDidScroll(0, 0);
  assert.deepEqual(published, [24, 0]);
  assert.equal(host.headerBlurRadius, 0);
});

test('real drag offset reader handles unbound lists and clamps rebound offsets', () => {
  const { DragScrollProbe } = loadListScrollHandlers();
  const probe = new DragScrollProbe();
  let position;
  probe.scroller = { currentOffset: () => position, offset: () => position };
  assert.equal(probe.resolveScrollOffsetY(), 0);
  for (const [offset, expected] of [[24, 24], [-8, 0], [NaN, 0], [Infinity, 0]]) {
    position = { xOffset: 0, yOffset: offset };
    assert.equal(probe.resolveScrollOffsetY(), expected);
  }
});
