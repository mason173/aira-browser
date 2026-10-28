#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const probe = new Proxy({}, { get: () => () => {} });

function harness() {
  const cache = new Map();
  const mocks = new Map([
    ['common/debug/AiraTabSessionProbe.ets', { AiraTabSessionProbe: probe }],
    ['core/browser/BrowserNativeTabSceneService.ets', {
      browserNativeTabSceneService: { isNativeTabUrl: () => false }
    }],
    ['app/runtime/BrowserWindowRuntime.ets', {
      resolveBrowserTabSessionProfileId: id => id || 'profile-main'
    }],
    ['core/deviceTabs/CrossDeviceTabPresenceCoordinator.ets', {
      sharedCrossDeviceTabPresenceCoordinator: { reconcileWindowRecords() {} }
    }]
  ].map(([file, value]) => [path.join(root, file), value]));

  function evaluate(source, filename, globals = {}) {
    const result = ts.transpileModule(source, {
      compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
      reportDiagnostics: true, fileName: filename
    });
    assert.equal((result.diagnostics || []).length, 0, filename);
    const module = { exports: {} };
    vm.runInNewContext(result.outputText, {
      module, exports: module.exports, ...globals,
      require: id => load(path.resolve(path.dirname(filename), `${id}.ets`))
    }, { filename });
    return module.exports;
  }

  function load(filename) {
    if (mocks.has(filename)) return mocks.get(filename);
    if (!cache.has(filename)) {
      cache.set(filename, evaluate(fs.readFileSync(filename, 'utf8'), filename));
    }
    return cache.get(filename);
  }

  function declarations(relative, names) {
    const filename = path.join(root, relative);
    const ast = ts.createSourceFile(filename, fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true);
    return names.map(name => {
      const declaration = ast.statements.find(node => node.name?.text === name);
      assert.ok(declaration, name);
      return declaration.getText(ast);
    }).join('\n');
  }

  const models = load(path.join(root, 'common/models/BrowserModels.ets'));
  const { RdbTabSessionRepository: Repository } = evaluate(declarations(
    'data/repositories/BrowserRepositories.ets',
    ['RdbTabSessionRepository', 'filterPersistentTabSessionRecords', 'normalizeTabSessionOrder', 'compareTabSessionOrder']
  ), 'TabSessionRepository.ts', { ...models, AiraTabSessionProbe: probe });
  let disk = [];
  const database = {
    initialize: async () => {},
    listTabRecords: async (windowId, profileId) => structuredClone(disk.filter(tab =>
      tab.windowId === windowId && (!profileId || tab.profileId === profileId))),
    replaceTabRecords: async (windowId, records, profileId) => {
      disk = disk.filter(tab => tab.windowId !== windowId || (profileId && tab.profileId !== profileId))
        .concat(structuredClone(records));
    }
  };
  const repository = new Repository(database);
  const general = { tabAutoClosePolicy: 'manual', privateTabRestorePolicy: 'never_restore' };
  mocks.set(path.join(root, 'app/bootstrap/BrowserAppRuntime.ets'), {
    sharedPreferencesRepository: { getPreferences: () => ({ general }) },
    sharedTabSessionRepository: repository
  });

  const { TabManager } = load(path.join(root, 'core/tabs/TabManager.ets'));
  const { BrowserTabSessionPersistenceCoordinator: Persistence } = load(
    path.join(root, 'core/browser/BrowserTabSessionPersistenceCoordinator.ets'));
  const { BrowserTabSessionRestoreService: Restore } = load(
    path.join(root, 'core/browser/BrowserTabSessionRestoreService.ets'));
  const { BrowserTabSessionRuntime: runtime } = load(path.join(root, 'app/runtime/BrowserTabSessionRuntime.ets'));
  const manager = new TabManager();
  let state = { tabs: [], activeTabId: '', tabSequence: 0 };
  let restoring = false;
  let disconnected = false;
  const persistence = new Persistence({
    tabManager: {
      serializeTabs: (...args) => disconnected ? [] : manager.serializeTabs(...args),
      createBootstrapTab: (...args) => manager.createBootstrapTab(...args)
    },
    documentViewerService: { isDocumentViewerTabRecord: () => false },
    downloadNavigationStateCoordinator: { sanitizePersistedRecord: record => ({ record }) },
    siteClearOnCloseCoordinator: {
      filterPersistableTabRecords: records => ({ records, removedRecords: [] }),
      persistPendingRecords() {}
    },
    siteClearOnCloseHost: {}
  }, {
    isRestoringTabs: () => restoring,
    getTabs: () => state.tabs,
    getActiveTabId: () => state.activeTabId,
    getCurrentWindowId: () => 'window-main',
    getCurrentTabSessionProfileId: () => 'profile-main'
  });

  return {
    general, persistence, runtime,
    addTab(options = {}) {
      state = manager.createTab(state.tabs, state.tabSequence, 'https://example.test', 'Example', options);
    },
    closeAll() {
      state = manager.closeTabsToHome(state.tabs, state.activeTabId, state.tabs.map(tab => tab.id));
    },
    closeOne() { state = manager.closeTab(state.tabs, state.activeTabId, state.tabs[0].id); },
    disconnect() { disconnected = true; },
    setRestoring(value) { restoring = value; },
    failStartupRestore() {
      state = { tabs: [], activeTabId: '', tabSequence: 0 };
      restoring = true;
      const filename = path.join(root, 'core/browser/BrowserStartupTabRestoreCoordinator.ets');
      const ast = ts.createSourceFile(filename, fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true);
      const coordinator = ast.statements.find(node => node.name?.text === 'BrowserStartupTabRestoreCoordinator');
      const failure = coordinator?.members.find(node => node.name?.text === 'applyRestoreFailure');
      assert.ok(failure, 'production startup failure path');
      const { StartupFailure } = evaluate(`export class StartupFailure { ${failure.getText(ast)} }`,
        'StartupFailure.ts');
      const startup = Object.assign(new StartupFailure(), {
        isStartupRestoreCurrent: () => true,
        host: {
          setStartupHomeSurfacePending() {},
          applyState: application => { if (application.restoreCompleted) restoring = false; }
        },
        dependencies: {
          tabSessionPersistenceCoordinator: persistence,
          resolveWindowContextCoordinator: () => ({ consumePendingWebSceneLaunch: () => false }),
          tabSwitchCoordinator: { synchronizeActiveTab() {} }
        },
        completePendingLaunch() {}
      });
      startup.applyRestoreFailure('', 1);
    },
    async flushLifecycle(source) {
      const filename = path.join(root, 'app/abilities/EntryAbility.ets');
      const ast = ts.createSourceFile(filename, fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true);
      const ability = ast.statements.find(node => node.name?.text === 'EntryAbility');
      const flush = ability?.members.find(node => node.name?.text === 'flushLastKnownTabSession');
      assert.ok(flush, 'production lifecycle flush');
      const pending = [];
      const { AbilityFlush } = evaluate(
        `export class AbilityFlush { currentWindowId = 'window-main'; ${flush.getText(ast)} }`,
        'AbilityFlush.ts', {
          BrowserTabSessionRuntime: runtime,
          BrowserTabSessionRestoreService: Restore,
          sharedPreferencesRepository: { getPreferences: () => ({ general }) },
          sharedTabSessionRepository: {
            replaceTabs: (...args) => {
              const operation = repository.replaceTabs(...args);
              pending.push(operation);
              return operation;
            }
          },
          AiraTabSessionProbe: probe, hilog: probe, DOMAIN: 0, TAG: 'test'
        });
      new AbilityFlush().flushLastKnownTabSession(source);
      await Promise.all(pending);
    },
    async restart() {
      // A new repository reads only persisted state; no runtime cache can mask stale records.
      const records = await new Repository(database).refresh('window-main', 'profile-main');
      return new Restore().prepareRecordsForColdRestore(records,
        new Restore().buildOptions(general.tabAutoClosePolicy, general.privateTabRestorePolicy)).records;
    }
  };
}

for (const mode of ['close all', 'close individually']) {
  test(`${mode}: restarting after closure must not resurrect tabs`, async () => {
    const h = harness();
    h.addTab();
    h.addTab();
    await h.persistence.persistAndWait();
    assert.equal((await h.restart()).length, 2, 'seed a persisted session');
    if (mode === 'close all') {
      h.closeAll();
    } else {
      h.closeOne();
      await h.persistence.persistAndWait();
      assert.equal((await h.restart()).length, 1);
      h.closeOne();
    }
    await h.persistence.persistAndWait();
    assert.equal((await h.restart()).length, 0, 'closed tabs must stay closed on cold restart');
    assert.equal(h.runtime.getSnapshot('window-main').records.length, 0,
      'lifecycle fallback must also remember the empty session');
    for (const source of ['ability-background', 'window-stage-destroy']) {
      await h.flushLifecycle(source);
      assert.equal((await h.restart()).length, 0, `${source} must not write closed tabs back`);
    }
  });
}

test('disconnected tab manager must not erase a nonempty session', async () => {
  const h = harness();
  h.addTab();
  await h.persistence.persistAndWait();
  h.disconnect();
  await h.persistence.persistAndWait();
  assert.equal((await h.restart()).length, 1);
  assert.equal(h.runtime.getSnapshot('window-main').records.length, 1);
});

test('temporary empty state while restoring must not erase the saved session', async () => {
  const h = harness();
  h.addTab();
  await h.persistence.persistAndWait();
  h.closeAll();
  h.setRestoring(true);
  await h.persistence.persistAndWait();
  assert.equal((await h.restart()).length, 1);
});

test('policy-driven empty persistence still removes the previous session', async () => {
  const h = harness();
  h.addTab();
  await h.persistence.persistAndWait();
  h.general.tabAutoClosePolicy = 'on_app_exit';
  await h.persistence.persistAndWait();
  h.general.tabAutoClosePolicy = 'manual';
  assert.equal((await h.restart()).length, 0);
});

test('explicit closure also clears private tabs opted into restoration', async () => {
  const h = harness();
  h.general.privateTabRestorePolicy = 'restore_private_tabs';
  h.addTab({ privacyMode: 'private', dataScope: 'session_ephemeral' });
  await h.persistence.persistAndWait();
  assert.equal((await h.restart()).length, 1);
  h.closeAll();
  await h.persistence.persistAndWait();
  await h.flushLifecycle('ability-background');
  assert.equal((await h.restart()).length, 0);
});

test('failed startup must preserve saved tabs until a live session is established', async () => {
  const h = harness();
  h.addTab();
  await h.persistence.persistAndWait();
  h.failStartupRestore();
  await h.persistence.persistAndWait();
  assert.equal((await h.restart()).length, 1, 'startup failure must not erase the unread saved session');
  h.addTab();
  await h.persistence.persistAndWait();
  h.closeAll();
  await h.persistence.persistAndWait();
  assert.equal((await h.restart()).length, 0, 'a new live session must still allow explicit closure');
});
