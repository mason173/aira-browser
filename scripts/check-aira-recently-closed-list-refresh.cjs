#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
// Run after building the client; an explicit first argument can select a release cache.
const compiledPath = process.argv[2] || path.resolve(__dirname,
  '../AiraBrowser/entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/' +
  'entry/src/main/ets/app/components/browser/RecentlyClosedRecordList.ts');
assert.ok(fs.existsSync(compiledPath), 'Build the client first to generate the CompileArkTS cache.');

function evaluate(source, globals = {}, imports = {}) {
  const compiled = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
    reportDiagnostics: true
  });
  assert.equal(compiled.diagnostics.length, 0);
  const module = { exports: {} };
  vm.runInNewContext(compiled.outputText, {
    module, exports: module.exports, ...globals,
    require: id => {
      const provided = imports[path.basename(id)];
      if (provided) return provided;
      const modules = [
        'common/models/BrowserModels',
        'core/browser/BrowserProfileBoundaryService',
        'services/privacy/BrowserPrivacyEffectPolicyService'
      ];
      const relative = modules.find(file => id.endsWith('/' + path.basename(file)));
      if (relative) return evaluate(read(relative + '.ets'));
      if (id.endsWith('/SiteIconService')) return { SiteIconService: class { peekUri() { return ''; } } };
      throw new Error(`Unexpected dependency: ${id}`);
    }
  });
  return module.exports;
}

function read(relative) { return fs.readFileSync(path.join(root, relative), 'utf8'); }

function selectMethods(source, className, names) {
  const ast = ts.createSourceFile('component.ts', source.replace(/\bstruct\b/g, 'class'), ts.ScriptTarget.Latest, true);
  const declaration = ast.statements.find(node => node.name?.text === className);
  return names.map(name => {
    const member = declaration.members.find(node => node.name?.text === name);
    assert.ok(member, `${className}.${name}`);
    return member.getText(ast);
  }).join('\n');
}

function service() {
  const { BrowserRecentlyClosedTabsService } = evaluate(read('core/browser/BrowserRecentlyClosedTabsService.ets'));
  return new BrowserRecentlyClosedTabsService({
    shouldTreatAsNonRestorableNavigation: () => false,
    allowExplicitPageRestore() {},
    resolveRestorableNavigation: tab => ({ url: tab.url, title: tab.title })
  });
}

function tab(id) {
  const url = `https://${id}.example.test/article`;
  return {
    id, title: id, url, isHome: false, profileId: 'profile-main',
    privacyMode: 'regular', dataScope: 'profile_persistent',
    pendingUrl: url, navigationHistory: [url], navigationIndex: 0,
    runtimeState: 'loading', lastGoodUrl: url, lastGoodTitle: id,
    lastRestorableUrl: url, lastRestorableTitle: id, webStatePath: '',
    launchContext: { sourceType: '', sourceId: '', sourceUrl: '', key: '' }
  };
}

function application() {
  const facts = {
    currentWindowId: 'window-main', currentProfileId: 'profile-main',
    dataScope: 'profile_persistent', privacyMode: 'regular', showHomePage: true
  };
  const confirmations = [];
  const blocks = [];
  const snapshots = [];
  const writes = [];
  const stored = new Map();
  const cached = new Map();
  let resolveRefresh;
  const { BrowserRecentlyClosedApplicationCoordinator } = evaluate(
    read('core/browser/BrowserRecentlyClosedApplicationCoordinator.ets'),
    { $r: name => name, setTimeout, clearTimeout },
    {
      AppResourceText: { resolveAppResourceText: text => text },
      BrowserAppRuntime: { getBrowserAppRuntimeInitializationPromise: () => undefined },
      HomeRecentlyClosedIconHydrationCoordinator: {
        HomeRecentlyClosedIconHydrationCoordinator: class {
          resolveFor(records, callbacks) { callbacks.applySnapshot({ icons: [] }); }
          clear(callbacks) { callbacks.applySnapshot({ icons: [] }); }
        }
      }
    }
  );
  const owner = new BrowserRecentlyClosedApplicationCoordinator({
    repository: {
      replaceCachedRecords(records, window, profile) { cached.set(`${window}/${profile}`, [...records]); },
      replaceRecords(records, window, profile) {
        writes.push({ window, profile, count: records.length });
        stored.set(`${window}/${profile}`, [...records]);
        return Promise.resolve();
      },
      refresh: () => new Promise(resolve => { resolveRefresh = resolve; }),
      clearAllRecords: () => assert.fail('Menu deletion must not clear other windows or profiles')
    },
    preferencesRepository: {
      getPreferences: () => ({ appearance: { showHomeRecentlyClosed: true, homeRecentlyClosedLimit: 8 } })
    },
    homeShortcutToggleService: { isUrlAddedToScenario: () => false },
    tabsService: service(),
    homePresentationViewModel: { shouldRemountRecentlyClosedSection: () => false }
  }, {
    resolveFacts: () => facts,
    publishSnapshot: snapshot => snapshots.push(snapshot),
    confirmDelete: request => confirmations.push(request),
    presentBoundaryBlock: event => blocks.push(event),
    showToast() {}
  });
  return {
    owner, facts, confirmations, blocks, snapshots, writes, stored, cached,
    resolveRefresh: records => resolveRefresh(records)
  };
}

// Integration with the actual DevEco-generated update callbacks. Only
// native layout and row widgets are stubbed; the captured builder arguments and
// list data expressions are executed unchanged. No device or screen is accessed.
function compiledList(records, columns) {
  const widget = () => new Proxy({}, { get: () => () => {} });
  const If = widget();
  const methods = selectMethods(fs.readFileSync(compiledPath, 'utf8'), 'RecentlyClosedRecordList', [
    'initialRender', 'buildRecordContent', 'resolveDisplayRecords', 'resolveRecordRowsFor',
    'buildRecordRowKey', 'buildDisplayRecordKey', 'buildDisplayLimitKey'
  ]);
  const { List } = evaluate(`export class List { ${methods} }`, {
    Column: widget(), Row: widget(), If, ForEach: widget(), HorizontalAlign: { Center: 0 }
  });
  let updateContent;
  let rows = [];
  const list = Object.assign(new List(), {
    records, columns, recordLimit: 8, showEmptyState: false,
    resolveColumnCount: () => columns,
    resolveRecordCellWidth: () => 200, resolveRecordRowWidth: () => 600, resolveRecordGridWidth: () => 600,
    observeComponentCreation2(callback, component) {
      if (component === If && !updateContent) updateContent = callback;
      callback(1, true);
    },
    ifElseBranchUpdateFunction: (_branch, callback) => callback(),
    forEachUpdateFunction: (_id, items, generate) => items.forEach(generate),
    buildRecordRow: record => rows.push({ id: record.id, click: restore => restore(record.id) })
  });
  list.initialRender();
  return {
    get rows() { return rows; },
    update(nextRecords) {
      list.records = nextRecords;
      rows = [];
      // Even an explicit update must read current props, not the first array.
      updateContent(1, false);
    }
  };
}

test('restore and immediate close produces a new restorable record and consumes the old ID', () => {
  const recent = service();
  const initial = recent.recordClosedTab([], tab('current')).records;
  const restored = recent.restoreByRecordId([], '', initial, initial[0].id);
  assert.equal(restored.restored, true);
  const next = recent.recordClosedTab(restored.remainingRecords, restored.tabs[0]).records;
  assert.notEqual(next[0].id, initial[0].id);
  assert.equal(recent.restoreByRecordId([], '', next, initial[0].id).restored, false);
  assert.equal(recent.restoreByRecordId([], '', next, next[0].id).restored, true);
});

for (const columns of [1, 3]) {
  test(`compiled ${columns}-column list: restore -> immediate Back -> click restores the new record`, () => {
    const recent = service();
    let records = recent.recordClosedTab([], tab('current')).records;
    const list = compiledList(records, columns);
    for (let cycle = 0; cycle < 3; cycle++) {
      const restored = list.rows[0].click(id => recent.restoreByRecordId([], '', records, id));
      assert.equal(restored.restored, true,
        `cycle ${cycle}: visible row must restore, not report "这个标签页已经无法恢复。" (${restored.summaryLine})`);
      // Opening and returning within one UI update coalesces the intermediate
      // empty array; the homepage/list instance can remain mounted throughout.
      records = recent.recordClosedTab(restored.remainingRecords, restored.tabs[0]).records;
      list.update(records);
    }
  });

  test(`compiled ${columns}-column list drops consumed rows and accepts later closures`, () => {
    const recent = service();
    const initial = recent.recordClosedTab([], tab('current')).records;
    const list = compiledList(initial, columns);
    list.update([]);
    assert.equal(list.rows.length, 0);
    const next = recent.recordClosedTab([], tab('later')).records;
    list.update(next);
    assert.equal(list.rows[0].id, next[0].id);
  });

  test(`delete all clears every record and refreshes the compiled ${columns}-column list`, () => {
    const app = application();
    for (let i = 0; i < 10; i++) app.owner.recordClosedTab(tab(`closed-${i}`));
    const initial = app.owner.getSnapshot();
    assert.equal(initial.recordCount, 10);
    assert.equal(initial.displayRecords.length, 8);
    const list = compiledList(initial.displayRecords, columns);
    const otherScopes = ['window-other/profile-main', 'window-main/profile-other'];
    for (const scope of otherScopes) app.stored.set(scope, ['preserved']);

    app.owner.handleUserAction({ type: 'request_delete_all_records' });
    assert.equal(app.confirmations.length, 1);
    // Opening or dismissing the dialog must not change persisted or visible records.
    assert.equal(app.owner.getSnapshot().recordCount, 10);
    assert.equal(app.stored.get('window-main/profile-main').length, 10);
    app.confirmations[0].onCancel?.();
    assert.equal(app.owner.getSnapshot().recordCount, 10);

    app.owner.handleUserAction({ type: 'request_delete_all_records' });
    app.confirmations[1].onConfirm();
    const cleared = app.snapshots.at(-1);
    assert.equal(cleared.recordCount, 0);
    assert.ok(cleared.renderVersion > initial.renderVersion);
    list.update(cleared.displayRecords);
    assert.equal(list.rows.length, 0);
    assert.equal(app.stored.get('window-main/profile-main').length, 0);
    assert.equal(app.cached.get('window-main/profile-main').length, 0);
    for (const scope of otherScopes) assert.deepEqual(app.stored.get(scope), ['preserved']);

    app.owner.recordClosedTab(tab('later'));
    list.update(app.snapshots.at(-1).displayRecords);
    assert.equal(list.rows.length, 1);
    assert.equal(app.stored.get('window-main/profile-main').length, 1);
  });
}

test('empty recently closed list does not request deletion or write data', () => {
  const app = application();
  app.owner.handleUserAction({ type: 'request_delete_all_records' });
  assert.equal(app.confirmations.length, 0);
  assert.equal(app.writes.length, 0);
});

for (const changed of ['currentWindowId', 'currentProfileId', 'window-reset', 'privacyMode']) {
  test(`pending delete-all confirmation cannot delete after ${changed} changes`, () => {
    const app = application();
    app.owner.recordClosedTab(tab('existing'));
    app.owner.handleUserAction({ type: 'request_delete_all_records' });
    if (changed === 'window-reset') {
      // Even switching away and back to the same IDs invalidates an old dialog.
      app.owner.resetForWindowSwitch();
      app.owner.recordClosedTab(tab('new-session'));
    } else {
      app.facts[changed] = changed === 'privacyMode' ? 'private' : 'different';
    }
    const writesBefore = app.writes.length;
    app.confirmations[0].onConfirm();
    assert.equal(app.writes.length, writesBefore);
    app.facts.privacyMode = 'regular';
    assert.equal(app.owner.getSnapshot().recordCount, 1);
  });
}

test('private session cannot request deletion of regular recently closed records', () => {
  const app = application();
  app.owner.recordClosedTab(tab('existing'));
  app.facts.privacyMode = 'private';
  app.owner.handleUserAction({ type: 'request_delete_all_records' });
  assert.equal(app.confirmations.length, 0);
  assert.equal(app.blocks.length, 1);
});

test('a pending repository refresh cannot resurrect deleted records', async () => {
  const app = application();
  app.owner.recordClosedTab(tab('existing'));
  const oldRecords = app.owner.getSnapshot().records;
  const loading = app.owner.loadForStartup('profile-main');
  app.owner.handleUserAction({ type: 'request_delete_all_records' });
  app.confirmations[0].onConfirm();
  app.resolveRefresh(oldRecords);
  await loading;
  assert.equal(app.owner.getSnapshot().recordCount, 0);
  assert.equal(app.stored.get('window-main/profile-main').length, 0);
});
