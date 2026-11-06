'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function runtime() {
  const cache = new Map();
  const timers = new Map();
  let nextTimer = 0;
  const routes = [];
  const router = {
    pushUrl: request => { routes.push(request); return Promise.resolve(); },
    back: request => routes.push(request)
  };
  function load(relative) {
    if (cache.has(relative)) return cache.get(relative);
    if (relative.endsWith('/BookmarkSortPreferencesRepository')) {
      return { sharedBookmarkSortPreferencesRepository: { getMode: () => 'manual' } };
    }
    if (relative.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
    const filename = path.join(root, relative + '.ets');
    const module = { exports: {} };
    cache.set(relative, module.exports);
    vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
    }).outputText, {
      module, exports: module.exports, $r: value => value, Edge: { Top: 'top' },
      setTimeout: callback => { timers.set(++nextTimer, callback); return nextTimer; },
      clearTimeout: timer => timers.delete(timer),
      require(id) {
        if (id === '@ohos.router') return { default: router };
        if (id === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
        assert.ok(id.startsWith('.'), `Unexpected platform import: ${id}`);
        return load(path.relative(root, path.resolve(path.dirname(filename), id)));
      }
    }, { filename });
    return module.exports;
  }
  const constants = load('data/repositories/BookmarkRepositoryCore');
  const store = load('core/bookmarks/BookmarkBrowseSessionStore').sharedBookmarkBrowseSessionStore;
  const Coordinator = load('core/bookmarks/BookmarkWorkspaceSessionCoordinator').BookmarkWorkspaceSessionCoordinator;
  const nodes = new Map();
  for (const scope of ['regular', 'private']) {
    const toolbar = scope === 'private' ? constants.PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : constants.BOOKMARK_TOOLBAR_ROOT_ID;
    const other = scope === 'private' ? constants.PRIVATE_BOOKMARK_OTHER_ROOT_ID : constants.BOOKMARK_OTHER_ROOT_ID;
    for (const [id, parentId] of [[toolbar], [other], [scope + '-parent', other], [scope + '-deep', scope + '-parent']]) {
      nodes.set(id, { id, parentId, scope, type: 'folder', title: id });
    }
    nodes.set(scope + '-link', {
      id: scope + '-link', parentId: scope + '-deep', scope, type: 'bookmark', title: 'Link', url: 'https://example.com'
    });
  }
  const find = id => nodes.get(id);
  const feature = {
    scope: 'regular',
    configure(_boundary, scope) { this.scope = scope; },
    refresh: async () => {},
    findNodeById(id) { const node = find(id); return node?.scope === this.scope ? node : undefined; },
    getPrimaryFolderId() { return this.scope === 'private' ? constants.PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : constants.BOOKMARK_TOOLBAR_ROOT_ID; },
    listDisplayChildren(parentId) { return [...nodes.values()].filter(node => node.scope === this.scope && node.parentId === parentId); },
    searchBookmarks() { return [...nodes.values()].filter(node => node.scope === this.scope && node.type === 'bookmark'); },
    buildFolderBookmarkCounts: () => ({ counts: new Map() })
  };
  return {
    store, constants, nodes, find, feature, Coordinator, routes,
    PhoneCoordinator: load('core/bookmarks/BookmarkManagerBrowseSessionCoordinator').BookmarkManagerBrowseSessionCoordinator,
    flushTimers() { const callbacks = [...timers.values()]; timers.clear(); callbacks.forEach(callback => callback()); }
  };
}

for (const scope of ['regular', 'private']) {
  test(`${scope}: deep folder, root, query and exact scroll offset survive reentry`, async () => {
    const r = runtime();
    r.store.remember(scope, scope + '-deep', 'Link', 583.5, r.find);
    const coordinator = new r.Coordinator(r.feature, {});
    const snapshot = await coordinator.activate(scope, 'aira://system/bookmarks');
    assert.equal(snapshot.currentFolderId, scope + '-deep');
    assert.equal(snapshot.query, 'Link');
    assert.equal(coordinator.takeBrowseScrollOffset(), 583.5);
    assert.equal(coordinator.takeBrowseScrollOffset(), undefined, 'restore is applied only once');
    assert.equal(r.store.peek(scope).rootId, scope === 'private'
      ? r.constants.PRIVATE_BOOKMARK_OTHER_ROOT_ID : r.constants.BOOKMARK_OTHER_ROOT_ID);
  });
}

test('normal and private sessions are isolated and reads cannot mutate saved state', () => {
  const r = runtime();
  assert.equal(r.store.peek('regular'), undefined);
  r.store.remember('regular', 'regular-deep', '', 123, r.find);
  assert.equal(r.store.peek('private'), undefined);
  r.store.remember('private', 'private-deep', 'private query', 456, r.find);
  const read = r.store.peek('regular');
  read.folderId = 'corrupted';
  read.offset = 0;
  assert.equal(r.store.peek('regular').folderId, 'regular-deep');
  assert.equal(r.store.peek('regular').offset, 123);
  assert.equal(r.store.peek('private').offset, 456);
});

test('deleted folders fall back through surviving ancestors to their original collection root', () => {
  const r = runtime();
  r.store.remember('regular', 'regular-deep', '', 300, r.find);
  r.nodes.delete('regular-deep');
  assert.equal(r.store.resolve('regular', r.find).folderId, 'regular-parent');
  assert.equal(r.store.resolve('regular', r.find).offset, 0);
  r.nodes.delete('regular-parent');
  assert.equal(r.store.resolve('regular', r.find).folderId, r.constants.BOOKMARK_OTHER_ROOT_ID);
});

test('moved folders restore in their new collection and restored back navigation follows current parents', () => {
  const r = runtime();
  r.store.remember('regular', 'regular-deep', '', 300, r.find);
  r.nodes.get('regular-deep').parentId = r.constants.BOOKMARK_TOOLBAR_ROOT_ID;
  const location = r.store.resolve('regular', r.find);
  assert.equal(location.rootId, r.constants.BOOKMARK_TOOLBAR_ROOT_ID);
  assert.equal(r.store.parentLocation('regular', location.folderId, location.rootId, r.find).folderId,
    r.constants.BOOKMARK_TOOLBAR_ROOT_ID);
});

test('explicit folder and search routes take precedence over the remembered location', async () => {
  const r = runtime();
  r.store.remember('regular', 'regular-deep', 'previous', 300, r.find);
  const coordinator = new r.Coordinator(r.feature, {});
  const snapshot = await coordinator.activate('regular', 'aira://system/bookmarks?id=regular-parent&q=new');
  assert.equal(snapshot.currentFolderId, 'regular-parent');
  assert.equal(snapshot.query, 'new');
  assert.equal(coordinator.takeBrowseScrollOffset(), undefined);
});

test('a retained desktop session and a new session both resume after opening a bookmark', async () => {
  const r = runtime();
  const coordinator = new r.Coordinator(r.feature, {});
  await coordinator.activate('regular', 'aira://system/bookmarks');
  coordinator.selectFolder('regular-deep');
  coordinator.rememberBrowseLocation(720);
  coordinator.selectFolder('regular-parent');
  assert.equal((await coordinator.activate('regular', 'aira://system/bookmarks')).currentFolderId, 'regular-deep');
  assert.equal(coordinator.takeBrowseScrollOffset(), 720);
  const fresh = new r.Coordinator(r.feature, {});
  assert.equal((await fresh.activate('regular', 'aira://system/bookmarks')).currentFolderId, 'regular-deep');
});

test('invalid scroll offsets are sanitized and cyclic folder data cannot hang restoration', () => {
  const r = runtime();
  r.nodes.get('regular-parent').parentId = 'regular-deep';
  for (const offset of [-3, NaN, Infinity]) {
    r.store.remember('regular', 'regular-deep', '', offset, r.find);
    assert.equal(r.store.resolve('regular', r.find).offset, 0);
  }
});

function phone(r, scope = 'regular', contentStartOffset = 0) {
  r.feature.configure({}, scope);
  const state = { scope, folderId: '', rootId: '', query: '', offset: undefined, contentStartOffset, scrolls: [], reloads: 0 };
  const scroller = {
    offset: () => state.offset === undefined ? undefined : ({ yOffset: state.offset }),
    // ArkUI scrollTo with animation:false clamps negative targets to zero.
    // https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-scroll#scrolloptions18对象说明
    scrollTo: ({ yOffset }) => { state.offset = Math.max(0, yOffset); state.scrolls.push(state.offset); },
    scrollBy: (_dx, dy) => {
      state.offset = Math.max(-state.contentStartOffset, state.offset + dy);
      state.scrolls.push(state.offset);
    },
    scrollEdge: edge => {
      assert.equal(edge, 'top');
      state.offset = -state.contentStartOffset;
      state.scrolls.push(state.offset);
    }
  };
  const coordinator = new r.PhoneCoordinator({
    feature: r.feature,
    scope: () => scope,
    folderId: () => state.folderId,
    rootId: () => state.rootId,
    query: () => state.query,
    scroller: () => scroller,
    contentStartOffset: () => state.contentStartOffset,
    applyLocation: location => Object.assign(state, { folderId: location.folderId, rootId: location.rootId }),
    exitSearch: () => { state.query = ''; },
    reload: () => { state.reloads++; },
    setElevated: elevated => { state.elevated = elevated; }
  });
  function enter(params) {
    const location = coordinator.initialize(params);
    Object.assign(state, { folderId: location.folderId, rootId: location.rootId, query: location.query });
    return location;
  }
  return { coordinator, state, enter };
}

test('opening a root bookmark and reentering preserves the space below the floating tabs', () => {
  const r = runtime();
  // ArkUI List starts at -contentStartOffset, not zero (ContentOffset001 in
  // OpenHarmony's test/unittest/core/pattern/list/list_layout_test_ng.cpp).
  const inset = 152;
  const original = phone(r, 'regular', inset);
  original.enter();
  r.nodes.get('regular-link').parentId = original.state.folderId;
  original.state.offset = -inset;
  r.feature.authorizeNavigation = () => {};
  original.coordinator.openBookmark(r.find('regular-link'), 'current_tab', 'regular', 'profile_persistent');
  original.coordinator.dispose();

  const reopened = phone(r, 'regular', inset);
  reopened.enter();
  reopened.state.offset = -inset;
  reopened.coordinator.validateLocation();
  reopened.coordinator.scheduleScrollRestore();
  r.flushTimers();
  assert.equal(-reopened.state.offset, inset, 'first row must retain its original top inset below the tabs');
});

test('phone restores the inset range from any bound position despite native scrollTo clamping', () => {
  const r = runtime();
  const inset = 152;
  for (const savedDistance of [0, 24.5, inset - 1]) {
    r.store.remember('regular', r.constants.BOOKMARK_TOOLBAR_ROOT_ID, '', savedDistance, r.find);
    for (const mountedOffset of [-inset, -40, 0, 300]) {
      const p = phone(r, 'regular', inset);
      p.enter();
      p.state.offset = mountedOffset;
      p.coordinator.validateLocation();
      p.coordinator.scheduleScrollRestore();
      r.flushTimers();
      assert.equal(p.state.offset, savedDistance - inset);
      assert.equal(p.state.elevated, false);
      p.coordinator.scheduleScrollRestore();
      r.flushTimers();
      assert.equal(p.state.scrolls.length, 1, 'restoration must not apply a relative movement twice');
    }
  }
});

for (const scope of ['regular', 'private']) {
  for (const view of ['toolbar', 'other', 'folder', 'search']) {
    test(`${scope} ${view}: negative and positive native positions survive repeated bookmark reentry`, () => {
      const r = runtime();
      const rootId = view === 'toolbar'
        ? (scope === 'private' ? r.constants.PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : r.constants.BOOKMARK_TOOLBAR_ROOT_ID)
        : (scope === 'private' ? r.constants.PRIVATE_BOOKMARK_OTHER_ROOT_ID : r.constants.BOOKMARK_OTHER_ROOT_ID);
      const folderId = view === 'folder' || view === 'search' ? scope + '-deep' : rootId;
      const query = view === 'search' ? 'Link' : '';
      const inset = view === 'search' ? 116 : view === 'folder' ? 112 : 152;
      r.nodes.get(scope + '-link').parentId = folderId;
      r.feature.authorizeNavigation = () => {};
      for (const offset of [-inset, -inset + 24.5, 0, 583.5]) {
        let p = phone(r, scope, inset);
        p.enter({ folderId, query });
        p.state.offset = offset;
        for (let reentry = 0; reentry < 3; reentry++) {
          p.coordinator.openBookmark(r.find(scope + '-link'), 'current_tab', scope, 'profile_persistent');
          p.coordinator.dispose();
          assert.equal(r.store.peek(scope).offset, offset + inset);
          p = phone(r, scope, inset);
          p.enter();
          p.state.offset = -inset;
          p.coordinator.validateLocation();
          p.coordinator.scheduleScrollRestore();
          r.flushTimers();
          assert.equal(p.state.folderId, folderId);
          assert.equal(p.state.query, query);
          assert.equal(p.state.offset, offset, 'reentry must not move content relative to the header');
          assert.equal(p.state.elevated, offset > 8);
        }
      }
    });
  }
}

test('phone clamps only actual rebound and restores against the current header inset', () => {
  const r = runtime();
  const p = phone(r, 'regular', 152);
  p.enter();
  for (const offset of [-180, NaN, Infinity]) {
    p.state.offset = offset;
    p.coordinator.remember();
    assert.equal(r.store.peek('regular').offset, 0);
    const reopened = phone(r, 'regular', 164);
    reopened.enter();
    reopened.state.offset = -164;
    reopened.coordinator.validateLocation();
    reopened.coordinator.scheduleScrollRestore();
    r.flushTimers();
    assert.equal(reopened.state.offset, -164);
  }
  p.state.offset = -127.5;
  p.coordinator.remember();
  const reopened = phone(r, 'regular', 164);
  reopened.enter();
  reopened.coordinator.remember();
  assert.equal(r.store.peek('regular').offset, 24.5, 'unbound lists keep the pending logical distance');
  reopened.state.offset = -164;
  reopened.coordinator.validateLocation();
  reopened.coordinator.scheduleScrollRestore();
  r.flushTimers();
  assert.equal(reopened.state.offset, -139.5);
});

test('phone deleted-folder fallback and parent navigation retain the header inset at the top', () => {
  const r = runtime();
  r.store.remember('regular', 'regular-deep', '', 300, r.find);
  r.nodes.delete('regular-deep');
  const p = phone(r, 'regular', 112);
  p.enter();
  p.state.offset = -112;
  p.coordinator.validateLocation();
  p.coordinator.scheduleScrollRestore();
  r.flushTimers();
  assert.equal(p.state.folderId, 'regular-parent');
  assert.equal(p.state.offset, -112, 'deleted folder falls back to the parent resting top');
  p.state.offset = 300;
  assert.equal(p.coordinator.navigateParent(), true);
  assert.equal(p.state.offset, -112, 'reset the bound list to its real edge before changing parents');
});

test('phone reentry waits for refreshed data and a bound list, then restores the offset once', () => {
  const r = runtime();
  r.store.remember('regular', 'regular-deep', 'Link', 902.5, r.find);
  const p = phone(r);
  p.enter();
  p.coordinator.scheduleScrollRestore();
  r.flushTimers();
  assert.deepEqual(p.state.scrolls, []);
  p.coordinator.validateLocation();
  p.coordinator.scheduleScrollRestore();
  r.flushTimers();
  assert.deepEqual(p.state.scrolls, [], 'unmounted lists retain the pending restore');
  p.state.offset = 0;
  p.coordinator.scheduleScrollRestore();
  r.flushTimers();
  assert.deepEqual(p.state.scrolls, [902.5]);
  assert.equal(p.state.query, 'Link');
  p.coordinator.scheduleScrollRestore();
  r.flushTimers();
  assert.deepEqual(p.state.scrolls, [902.5]);
});

test('phone resumed back navigation visits each parent and finally returns control to the router', () => {
  const r = runtime();
  r.store.remember('regular', 'regular-deep', '', 200, r.find);
  const p = phone(r);
  p.enter();
  p.coordinator.validateLocation();
  assert.equal(p.coordinator.navigateParent(), true);
  assert.equal(p.state.folderId, 'regular-parent');
  assert.equal(p.coordinator.navigateParent(), true);
  assert.equal(p.state.folderId, r.constants.BOOKMARK_OTHER_ROOT_ID);
  assert.equal(p.coordinator.navigateParent(), false);
  assert.equal(p.state.reloads, 2);
});

test('phone explicit routes override saved state and disposing cancels queued scroll restoration', () => {
  const r = runtime();
  r.store.remember('regular', 'regular-deep', 'previous', 200, r.find);
  const p = phone(r);
  assert.equal(p.enter({ folderId: 'regular-parent', query: 'new' }).folderId, 'regular-parent');
  assert.equal(p.state.query, 'new');
  assert.equal(p.coordinator.navigateParent(), false, 'ordinary pushed pages use their existing router stack');
  const resumed = phone(r);
  resumed.enter();
  resumed.state.offset = 0;
  resumed.coordinator.validateLocation();
  resumed.coordinator.scheduleScrollRestore();
  resumed.coordinator.dispose();
  r.flushTimers();
  assert.deepEqual(resumed.state.scrolls, []);
});

test('phone bookmark opening remembers the active folder before exiting; denied navigation changes nothing', () => {
  const r = runtime();
  const p = phone(r);
  p.enter({ folderId: 'regular-deep' });
  p.state.offset = 456;
  r.feature.authorizeNavigation = () => { throw new Error('locked'); };
  assert.throws(() => p.coordinator.openBookmark(r.find('regular-link'), 'current_tab', 'regular', 'profile_persistent'), /locked/);
  assert.equal(r.store.peek('regular'), undefined);
  assert.equal(r.routes.length, 0);
  r.feature.authorizeNavigation = () => {};
  p.coordinator.openBookmark(r.find('regular-link'), 'current_tab', 'regular', 'profile_persistent');
  assert.equal(r.store.peek('regular').folderId, 'regular-deep');
  assert.equal(r.store.peek('regular').offset, 456);
  assert.equal(r.routes[0].params.openUrl, 'https://example.com');
  assert.equal(r.routes[0].params.openIntent, 'current_tab');
});

test('phone startup restoration never overrides a newer folder choice or schedules work after disposal', () => {
  const r = runtime();
  r.store.remember('regular', 'regular-deep', '', 900, r.find);
  const p = phone(r);
  p.enter();
  p.state.folderId = r.constants.BOOKMARK_TOOLBAR_ROOT_ID;
  p.state.rootId = r.constants.BOOKMARK_TOOLBAR_ROOT_ID;
  p.state.offset = 0;
  p.coordinator.validateLocation();
  p.coordinator.scheduleScrollRestore();
  r.flushTimers();
  assert.equal(p.state.folderId, r.constants.BOOKMARK_TOOLBAR_ROOT_ID);
  assert.deepEqual(p.state.scrolls, []);
  const disposed = phone(r);
  disposed.enter();
  disposed.state.offset = 0;
  disposed.coordinator.dispose();
  disposed.coordinator.validateLocation();
  disposed.coordinator.scheduleScrollRestore();
  r.flushTimers();
  assert.deepEqual(disposed.state.scrolls, []);
});
