'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function createRuntime() {
  const cache = new Map();
  const values = new Map();
  const storage = new Map();
  let durable = new Map();
  let failFlush = false;
  const store = {
    getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
    putSync: (key, value) => values.set(key, value),
    flushSync() {
      if (failFlush) throw new Error('disk failure');
      durable = new Map(values);
    }
  };
  const overrides = {
    'app/runtime/AppRuntimeContext': { AppRuntimeContext: { getApplicationContext: () => ({}) } },
    'core/resources/AppResourceText': { resolveAppResourceText: text => text },
    'services/bookmarks/BookmarkHtmlTransferService': { BookmarkHtmlTransferService: class {} },
    'services/privacy/BrowserPrivacyEffectPolicyService': {
      BrowserPrivacyEffectPolicyService: class {
        decide() { return { outcome: 'allow' }; }
        resolveDataPolicyForBoundary() { return { persistentReadAllowed: true, persistentWriteAllowed: true }; }
      }
    },
    'core/browser/BrowserProfileBoundaryService': {
      BrowserProfileBoundaryService: class { buildBoundary(boundary) { return boundary; } }
    },
    'core/browser/BrowserNativeTabSceneService': {
      browserNativeTabSceneService: { buildBookmarkRoute: () => 'aira://bookmarks' }
    }
  };
  function load(relative) {
    if (overrides[relative]) return overrides[relative];
    if (cache.has(relative)) return cache.get(relative);
    const filename = path.resolve(root, relative + '.ets');
    const module = { exports: {} };
    vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
    }).outputText, {
      module, exports: module.exports, $r: id => id,
      AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
      require: id => {
        if (id === '@kit.LocalizationKit') return { intl: { Collator: Intl.Collator } };
        if (id === '@kit.ArkData') return { preferences: { getPreferencesSync: () => store } };
        assert.ok(id.startsWith('.'), `Unexpected platform import: ${id}`);
        return load(path.relative(root, path.resolve(path.dirname(filename), id)));
      }
    }, { filename });
    cache.set(relative, module.exports);
    return module.exports;
  }
  return { load, values, storage, get durable() { return durable; }, set failFlush(value) { failFlush = value; } };
}

function node(id, title, position, createdAt, type = 'bookmark') {
  return { id, title, position, createdAt, type, parentId: 'folder', updatedAt: 999,
    sync: { state: 'synced', updatedAt: 999 } };
}
const ids = rows => Array.from(rows, row => row.id);

test('all five views keep folders first and never alter the stored order or sync metadata', () => {
  const runtime = createRuntime();
  const sorter = new (runtime.load('services/bookmarks/BookmarkDisplaySortService').BookmarkDisplaySortService)();
  const rows = [node('z', 'Zulu', 0, 10), node('a', 'Alpha', 1, 30),
    node('f2', 'Folder 2', 2, 20, 'folder'), node('f1', 'Folder 1', 3, 40, 'folder')];
  const before = JSON.stringify(rows);
  const expected = {
    manual: ['f2', 'f1', 'z', 'a'], newest: ['f1', 'f2', 'a', 'z'], oldest: ['f2', 'f1', 'z', 'a'],
    name_asc: ['f1', 'f2', 'a', 'z'], name_desc: ['f2', 'f1', 'z', 'a']
  };
  for (const [mode, order] of Object.entries(expected)) {
    assert.deepEqual(ids(sorter.sort(rows, mode)), order);
    assert.equal(JSON.stringify(rows), before);
  }
  assert.deepEqual(ids(sorter.sort(sorter.sort(rows, 'newest'), 'manual')), expected.manual);
});

test('names use pinyin, ignore case, compare numbers naturally, and keep equal keys deterministic', () => {
  const sorter = new (createRuntime().load('services/bookmarks/BookmarkDisplaySortService').BookmarkDisplaySortService)();
  assert.deepEqual(ids(sorter.sort([node('zhong', '中', 0, 1), node('a', '阿', 1, 1),
    node('bei', '北', 2, 1)], 'name_asc')), ['a', 'bei', 'zhong']);
  assert.deepEqual(ids(sorter.sort([node('ten', 'Item 10', 0, 1), node('two', 'item 2', 1, 1),
    node('first', 'ITEM 2', 2, 1)], 'name_asc')), ['two', 'first', 'ten']);
  assert.deepEqual(ids(sorter.sort([node('b', 'Same', 1, 1), node('a', 'same', 1, 1)], 'name_asc')), ['a', 'b']);
});

test('regular and private preferences survive a new repository instance and reject corrupt values', () => {
  const runtime = createRuntime();
  const { BookmarkSortPreferencesRepository } = runtime.load('data/bookmarks/BookmarkSortPreferencesRepository');
  const first = new BookmarkSortPreferencesRepository();
  assert.equal(first.getMode('regular'), 'manual');
  first.setMode('regular', 'newest');
  first.setMode('private', 'name_desc');
  const reopened = new BookmarkSortPreferencesRepository();
  assert.equal(reopened.getMode('regular'), 'newest');
  assert.equal(reopened.getMode('private'), 'name_desc');
  assert.equal(runtime.durable.get('regular'), 'newest');
  assert.equal(runtime.durable.get('private'), 'name_desc');
  assert.equal(runtime.storage.get('bookmarkSortPreferencesRevision'), 2);
  runtime.values.set('regular', 'invalid');
  assert.equal(reopened.getMode('regular'), 'manual');
});

test('failed persistence restores the previous preference and publishes no success revision', () => {
  const runtime = createRuntime();
  const repository = runtime.load('data/bookmarks/BookmarkSortPreferencesRepository').sharedBookmarkSortPreferencesRepository;
  repository.setMode('regular', 'oldest');
  runtime.failFlush = true;
  assert.throws(() => repository.setMode('regular', 'name_asc'), /disk failure/);
  assert.equal(repository.getMode('regular'), 'oldest');
  assert.equal(runtime.durable.get('regular'), 'oldest');
  assert.equal(runtime.storage.get('bookmarkSortPreferencesRevision'), 1);
});

function managementFixture(runtime) {
  const { BookmarkManagementFeature, BookmarkManagementBoundary } = runtime.load('features/bookmarks/BookmarkManagementFeature');
  const rows = [node('z', 'Zulu', 0, 10), node('a', 'Alpha', 1, 30)];
  const source = { setScope() {}, listDisplayChildren: () => rows, searchBookmarks: () => rows };
  let mutations = 0;
  const feature = new BookmarkManagementFeature(source, { reorderChildren: async () => { mutations++; return rows; } });
  feature.configure(new BookmarkManagementBoundary('profile_persistent', 'regular'), 'regular');
  return { feature, rows, get mutations() { return mutations; } };
}

test('management sorts folder contents, preserves collection roots and searches, and guards late reorder commits', async () => {
  const runtime = createRuntime();
  const prefs = runtime.load('data/bookmarks/BookmarkSortPreferencesRepository').sharedBookmarkSortPreferencesRepository;
  const fixture = managementFixture(runtime);
  prefs.setMode('regular', 'newest');
  assert.deepEqual(ids(fixture.feature.listDisplayChildren('folder')), ['a', 'z']);
  assert.deepEqual(ids(fixture.feature.listDisplayChildren(undefined)), ['z', 'a']);
  assert.deepEqual(ids(fixture.feature.searchBookmarks('anything', 500)), ['z', 'a']);
  await fixture.feature.reorderChildren({ parentId: 'folder', childIds: ['a', 'z'] });
  assert.equal(fixture.mutations, 0);
  prefs.setMode('regular', 'manual');
  await fixture.feature.reorderChildren({ parentId: 'folder', childIds: ['a', 'z'] });
  assert.equal(fixture.mutations, 1);
});

test('mobile search keeps match order, while previews, renames, and exiting search use the selected view', () => {
  const runtime = createRuntime();
  const prefs = runtime.load('data/bookmarks/BookmarkSortPreferencesRepository').sharedBookmarkSortPreferencesRepository;
  const { feature, rows } = managementFixture(runtime);
  const model = new (runtime.load('core/bookmarks/BookmarkManagerSearchViewModel').BookmarkManagerSearchViewModel)(feature);
  prefs.setMode('regular', 'name_asc');
  assert.deepEqual(ids(model.setCurrentFolderNodes(rows).nodes), ['a', 'z']);
  assert.deepEqual(ids(model.replaceNode({ ...rows[0], title: 'Aardvark' }).nodes), ['z', 'a']);
  model.enterSearchMode();
  assert.deepEqual(ids(model.setQuery('query').nodes), ['z', 'a']);
  assert.deepEqual(ids(model.exitSearchMode().nodes), ['z', 'a']);
  prefs.setMode('regular', 'manual');
  assert.deepEqual(ids(model.setCurrentFolderNodes(rows).nodes), ['z', 'a']);
});

test('the header places five exclusive sort choices between creating a folder and selecting items', () => {
  const runtime = createRuntime();
  const model = new (runtime.load('core/bookmarks/BookmarkManagerHeaderActionViewModel').BookmarkManagerHeaderActionViewModel)();
  let selected;
  const context = { isSelectionMode: false, isSearchMode: false, hasCurrentFolder: true,
    canEnterSelectionMode: true, isTransferBusy: false, sortMode: 'newest' };
  const handlers = { openSearch() {}, createFolder() {}, enterSelectionMode() {}, importBookmarks() {},
    exportBookmarks() {}, selectSortMode: mode => { selected = mode; } };
  const actions = model.buildActions(context, handlers);
  assert.equal(actions[1].label, 'app.string.bookmark_new_folder');
  assert.equal(actions[2].label, 'app.string.bookmark_sort_order');
  assert.equal(actions[3].label, 'app.string.ui_multi_select');
  assert.equal(actions[2].labelInfo, 'app.string.bookmark_sort_newest');
  assert.equal(actions[2].options.length, 5);
  assert.equal(actions[2].options.filter(option => option.selected).length, 1);
  actions[2].options[4].action();
  assert.equal(selected, 'name_desc');
  assert.equal(model.buildActions({ ...context, isSearchMode: true }, handlers).length, 0);
});

test('desktop positional drops are ignored in sorted views and searches before any mutation', async () => {
  const runtime = createRuntime();
  const prefs = runtime.load('data/bookmarks/BookmarkSortPreferencesRepository').sharedBookmarkSortPreferencesRepository;
  const { BookmarkWorkspaceSessionCoordinator } = runtime.load('core/bookmarks/BookmarkWorkspaceSessionCoordinator');
  const coordinator = new BookmarkWorkspaceSessionCoordinator({}, {});
  prefs.setMode('regular', 'newest');
  await coordinator.moveSelectionToFolder('folder', 1);
  prefs.setMode('regular', 'manual');
  coordinator.snapshotState.query = 'query';
  await coordinator.moveSelectionToFolder('folder', 1);
});

test('sorted desktop folder drops preserve existing siblings while still moving from another folder', async () => {
  const runtime = createRuntime();
  const prefs = runtime.load('data/bookmarks/BookmarkSortPreferencesRepository').sharedBookmarkSortPreferencesRepository;
  const { BookmarkWorkspaceSessionCoordinator } = runtime.load('core/bookmarks/BookmarkWorkspaceSessionCoordinator');
  const a = node('a', 'A', 0, 1);
  const b = { ...node('b', 'B', 0, 2), parentId: 'other' };
  const folders = [node('folder', 'Folder', 0, 1, 'folder'), node('other', 'Other', 1, 1, 'folder')]
    .map(folder => ({ ...folder, parentId: undefined }));
  const nodes = [...folders, a, b];
  const moved = [];
  const feature = {
    findNodeById: id => nodes.find(row => row.id === id),
    listDisplayChildren: parent => nodes.filter(row => row.parentId === parent),
    buildFolderBookmarkCounts: () => ({ counts: new Map() }),
    getPrimaryFolderId: () => 'folder',
    async moveSubtrees(command) { moved.push(...command.nodeIds); b.parentId = command.parentId; }
  };
  const coordinator = new BookmarkWorkspaceSessionCoordinator(feature, {});
  Object.assign(coordinator.snapshotState, { loading: false, currentFolderId: 'folder', selectedNodeIds: ['a'] });
  prefs.setMode('regular', 'newest');
  await coordinator.moveSelectionToFolder('folder');
  assert.deepEqual(moved, []);
  coordinator.snapshotState.selectedNodeIds = ['a', 'b'];
  const result = await coordinator.moveSelectionToFolder('folder');
  assert.deepEqual(moved, ['b']);
  assert.equal(result.message, '');
  assert.equal(a.position, 0);
});

test('all localized sort labels are present and unique', () => {
  const resourceRoot = path.resolve(root, '../resources');
  const names = ['order', 'manual', 'newest', 'oldest', 'name_asc', 'name_desc', 'manual_drag_hint'];
  for (const locale of ['base', 'zh_CN', 'en_US', 'zh_Hant']) {
    const entries = JSON.parse(fs.readFileSync(path.join(resourceRoot, locale, 'element/string.json'), 'utf8')).string;
    for (const name of names) {
      const matches = entries.filter(entry => entry.name === `bookmark_sort_${name}`);
      assert.equal(matches.length, 1, `${locale}: ${name}`);
      assert.ok(matches[0].value.length > 0);
    }
  }
});
