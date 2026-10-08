#!/usr/bin/env node
'use strict';

// Synthetic, deterministic races; run production coordinator/ViewModel and UI
// completion methods without an ArkUI runtime or access to user history.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const coordinatorPath = 'core/history/HistoryWorkspaceSessionCoordinator.ets';
const workspacePath = 'app/components/history/HistoryLargeScreenWorkspace.ets';
const baseRoute = 'aira://system/history';

function compile(source, filename, requireModule) {
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename, reportDiagnostics: true
  });
  assert.equal((result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
  const module = { exports: {} };
  vm.runInNewContext(result.outputText, {
    module,
    exports: module.exports,
    require: requireModule,
    // ArkTS resources resolve in the ArkUI runtime. The harness keeps the
    // resource key plus its format arguments so diagnostics stay assertable.
    $r: (value, ...args) => args.length > 0 ? `${value} ${args.join(' ')}` : value
  }, { filename });
  return module.exports;
}
const modules = new Map();
function load(relative) {
  if (modules.has(relative)) return modules.get(relative);
  const filename = path.join(root, relative);
  const exports = compile(fs.readFileSync(filename, 'utf8'), filename, name => {
    if (name === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
    if (!name.startsWith('.')) throw new Error(`Unexpected dependency: ${name}`);
    return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
  });
  modules.set(relative, exports);
  return exports;
}
const { HistoryWorkspaceSessionCoordinator } = load(coordinatorPath);

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function visits(count = 100, prefix = 'old') {
  return Array.from({ length: count }, (_, i) => ({
    id: `${prefix}-${i}`, title: `${prefix} ${i}`, url: `https://example.invalid/${prefix}/${i}`,
    host: 'example.invalid', origin: 'https://example.invalid', visitedAt: 1800000000000 - i,
    dayBucketLabel: 'synthetic-day', visitCount: 1, source: 'local'
  }));
}
function sites(count = 100, prefix = 'old') {
  return Array.from({ length: count }, (_, i) => ({
    host: `${prefix}-${i}.invalid`, origin: `https://${prefix}-${i}.invalid`, title: prefix,
    latestTitle: prefix, latestUrl: `https://${prefix}-${i}.invalid/`,
    latestVisitedAt: 1800000000000 - i, visitCount: 1, uniqueUrlCount: 1
  }));
}
function fixture() {
  const reads = [];
  const writes = [];
  function read(kind, query, offset) {
    const request = { kind, query, offset, ...deferred() };
    reads.push(request);
    return request.promise;
  }
  function write(kind, target) {
    const request = { kind, target, ...deferred() };
    writes.push(request);
    return request.promise;
  }
  const feature = {
    canReadForManagement: () => true,
    canMutateForManagement: () => true,
    refreshPageForManagement: offset => read('timeline', '', offset),
    refreshSearchPageForManagement: (query, offset) => read('search', query, offset),
    refreshSitePageForManagement: (query, offset) => read('sites', query, offset),
    deleteVisitsByIdsForManagement: ids => write('ids', ids),
    deleteVisitsByHostForManagement: host => write('host', host),
    clearVisitsForManagement: () => write('clear')
  };
  return { coordinator: new HistoryWorkspaceSessionCoordinator(feature, {}), reads, writes };
}
async function seed(f, mode = 'timeline') {
  const task = f.coordinator.activate(mode === 'sites' ? `${baseRoute}?view=sites` : baseRoute);
  f.reads.at(-1).resolve(mode === 'sites' ? sites() : visits());
  await task;
}
async function flush() {
  // Only drain microtasks; no timing-dependent sleeps.
  for (let i = 0; i < 8; i++) await Promise.resolve();
}
function mutate(f, operation) {
  if (operation === 'deleteVisit') return f.coordinator.deleteVisit('old-0');
  if (operation === 'deleteSelection') {
    f.coordinator.selectVisit('old-0');
    return f.coordinator.deleteSelection();
  }
  if (operation === 'deleteSite') return f.coordinator.deleteSite('old-0.invalid');
  return f.coordinator.clearAll();
}

for (const operation of ['deleteVisit', 'deleteSelection', 'deleteSite', 'clearAll']) {
  for (const delivery of ['during-write', 'after-write']) {
    test(`${operation}: stale pagination ${delivery} cannot resurrect deleted rows`, async () => {
      const f = fixture();
      const mode = operation === 'deleteSite' ? 'sites' : 'timeline';
      await seed(f, mode);
      const oldTask = f.coordinator.loadNextPage();
      const oldRead = f.reads.at(-1);
      assert.equal(oldRead.offset, 100);
      const task = mutate(f, operation);
      assert.equal(f.coordinator.getSnapshot().busy, true);
      assert.equal(f.coordinator.getSnapshot().loading, false);
      await f.coordinator.loadNextPage();
      assert.equal(f.reads.length, 2, 'busy gates new pagination');
      if (delivery === 'during-write') {
        oldRead.resolve(mode === 'sites' ? sites(1, 'stale') : visits(1, 'stale'));
        await oldTask;
      }
      f.writes[0].resolve(1);
      await flush();
      if (operation !== 'clearAll') {
        assert.equal(f.reads.at(-1).offset, 0, 'write rebases the database offset');
        f.reads.at(-1).resolve(mode === 'sites' ? sites(100, 'fresh') : visits(100, 'fresh'));
      }
      await task;
      if (delivery === 'after-write') {
        oldRead.resolve(mode === 'sites' ? sites(1, 'stale') : visits(1, 'stale'));
        await oldTask;
      }
      const state = f.coordinator.getSnapshot();
      assert.equal(state.busy, false);
      assert.equal(state.loading, false);
      assert.ok(!JSON.stringify(state).includes('stale'));
      assert.ok(!JSON.stringify(state).includes('old-0'));
      if (operation === 'clearAll') {
        assert.equal(state.visits.length, 0);
        assert.equal(state.sites.length, 0);
        assert.equal(state.hasMore, false);
        assert.equal(f.reads.length, 2, 'successful clear needs no read');
      } else {
        const next = f.coordinator.loadNextPage();
        assert.equal(f.reads.at(-1).offset, 100);
        f.reads.at(-1).resolve([]);
        await next;
      }
    });
  }
}

for (const mode of ['timeline', 'sites']) {
  for (const failOld of [false, true]) {
    test(`clear during ${mode} first page ignores late ${failOld ? 'failure' : 'success'}`, async () => {
      const f = fixture();
      const oldTask = f.coordinator.activate(mode === 'sites' ? `${baseRoute}?view=sites` : baseRoute);
      const oldRead = f.reads[0];
      const clear = f.coordinator.clearAll();
      await f.coordinator.setQuery('latest');
      await f.coordinator.setViewMode('sites');
      assert.equal(f.reads.length, 1, 'navigation during write queues no pre-write read');
      f.writes[0].resolve();
      await clear;
      const before = JSON.stringify(f.coordinator.getSnapshot());
      if (failOld) oldRead.reject(new Error('late error'));
      else oldRead.resolve(mode === 'sites' ? sites() : visits());
      await oldTask;
      assert.equal(JSON.stringify(f.coordinator.getSnapshot()), before);
      assert.equal(f.coordinator.getSnapshot().query, 'latest');
      assert.equal(f.coordinator.getSnapshot().loading, false);
    });
  }
}

for (const operation of ['deleteVisit', 'deleteSelection', 'deleteSite', 'clearAll']) {
  test(`${operation}: failure recovers latest route; recovery failure permits same-route retry`, async () => {
    const f = fixture();
    await seed(f);
    const task = mutate(f, operation);
    await f.coordinator.setQuery('intermediate');
    await f.coordinator.setViewMode('sites');
    await f.coordinator.setQuery('latest');
    assert.equal(f.reads.length, 1);
    f.writes[0].reject(new Error('write failed after partial commit'));
    await flush();
    const recovery = f.reads.at(-1);
    assert.equal(recovery.offset, 0);
    assert.equal(recovery.kind, 'sites');
    assert.equal(recovery.query, 'latest');
    recovery.reject(new Error('recovery failed'));
    await task;
    const failed = f.coordinator.getSnapshot();
    assert.equal(failed.busy, false);
    assert.equal(failed.loading, false);
    assert.equal(failed.hasMore, false);
    assert.match(failed.message, /write failed.*recovery failed/);
    await f.coordinator.loadNextPage();
    assert.equal(f.reads.length, 2, 'failed first page cannot advance an old cursor');
    const retry = f.coordinator.setViewMode('sites');
    assert.equal(f.reads.length, 3, 'same mode can retry failed recovery');
    f.reads.at(-1).resolve(sites(1, 'recovered'));
    await retry;
    assert.equal(f.coordinator.getSnapshot().sites.length, 1);
    assert.equal(f.coordinator.getSnapshot().message, '');
  });
}

for (const mode of ['timeline', 'sites']) {
  test(`site deletion supersedes ${mode} first page and recovers only latest navigation`, async () => {
    const f = fixture();
    const oldTask = f.coordinator.activate(mode === 'sites' ? `${baseRoute}?view=sites` : baseRoute);
    const oldRead = f.reads[0];
    const task = f.coordinator.deleteSite('old-0.invalid');
    await f.coordinator.setQuery('latest');
    await f.coordinator.setViewMode('sites');
    await f.coordinator.clearAll();
    assert.equal(f.writes.length, 1, 'writes are serialized');
    assert.equal(f.reads.length, 1);
    f.writes[0].resolve(1);
    await flush();
    assert.equal(f.reads.at(-1).kind, 'sites');
    assert.equal(f.reads.at(-1).query, 'latest');
    assert.equal(f.reads.at(-1).offset, 0);
    oldRead.reject(new Error('superseded first page'));
    await oldTask;
    assert.equal(f.coordinator.getSnapshot().loading, true, 'old read cannot finish recovery loading');
    assert.equal(f.coordinator.getSnapshot().message, '');
    f.reads.at(-1).resolve(sites(1, 'survivor'));
    await task;
    assert.equal(f.coordinator.getSnapshot().sites[0].host, 'survivor-0.invalid');
    assert.equal(f.coordinator.getSnapshot().loading, false);
  });
}

test('write failure supersedes a pending page and retries from persisted first page', async () => {
  const f = fixture();
  await seed(f);
  const oldTask = f.coordinator.loadNextPage();
  const oldRead = f.reads.at(-1);
  const task = f.coordinator.deleteVisit('old-0');
  f.writes[0].reject(new Error('write failed'));
  await flush();
  const recovery = f.reads.at(-1);
  assert.equal(recovery.offset, 0);
  recovery.resolve(visits(100, 'persisted'));
  await task;
  const state = JSON.stringify(f.coordinator.getSnapshot());
  oldRead.resolve(visits(1, 'stale'));
  await oldTask;
  assert.equal(JSON.stringify(f.coordinator.getSnapshot()), state);
  assert.match(f.coordinator.getSnapshot().message, /write failed/);
  const next = f.coordinator.loadNextPage();
  assert.equal(f.reads.at(-1).offset, 100);
  f.reads.at(-1).resolve([]);
  await next;
});

test('zero-removal and rejected writes refresh persisted data and retain write diagnostics', async () => {
  for (const fail of [false, true]) {
    const f = fixture();
    await seed(f);
    const task = f.coordinator.deleteVisit('old-0');
    if (fail) f.writes[0].reject(new Error('write failed'));
    else f.writes[0].resolve(0);
    await flush();
    f.reads.at(-1).resolve(visits(1, 'remaining'));
    await task;
    const state = f.coordinator.getSnapshot();
    assert.equal(state.visits[0].id, 'remaining-0');
    assert.match(state.message, fail ? /write failed/ : /history_none_deleted/);
    assert.equal(state.loading, false);
  }
});

test('latest route wins while recovery read is in flight', async () => {
  const f = fixture();
  await seed(f);
  const deletion = f.coordinator.deleteVisit('old-0');
  f.writes[0].resolve(1);
  await flush();
  const obsolete = f.reads.at(-1);
  const navigation = f.coordinator.setQuery('latest');
  f.reads.at(-1).resolve(visits(1, 'latest'));
  await navigation;
  obsolete.reject(new Error('obsolete recovery'));
  await deletion;
  assert.equal(f.coordinator.getSnapshot().visits[0].id, 'latest-0');
  assert.equal(f.coordinator.getSnapshot().message, '');
});

// Extract unchanged production method bodies; omit only ArkUI rendering/decorators.
const workspaceSource = fs.readFileSync(path.join(root, workspacePath), 'utf8');
function method(name) {
  const match = new RegExp(`\\n  private (?:async )?${name}\\(`).exec(workspaceSource);
  assert.ok(match, `production method ${name} must exist`);
  const end = workspaceSource.indexOf('\n  private ', match.index + match[0].length);
  return workspaceSource.slice(match.index, end < 0 ? workspaceSource.lastIndexOf('\n}') : end);
}
const methods = ['deleteVisit', 'deleteSelection', 'clearAll', 'deleteSite', 'isBindingCurrent'];
const { WorkspaceHarness } = compile(`export class WorkspaceHarness {\n${methods.map(method).join('\n')}\n}`,
  workspacePath, name => { throw new Error(`Unexpected UI dependency: ${name}`); });
for (const operation of methods.slice(0, 4)) {
  for (const change of ['none', 'tab', 'revision', 'coordinator', 'unmount']) {
    test(`${operation}: UI completion checks ${change} binding`, async () => {
      const result = deferred();
      const pending = { revision: 1 };
      const finished = { revision: 2 };
      const coordinator = { [operation]: () => result.promise, getSnapshot: () => pending };
      const applied = [];
      const ui = Object.assign(new WorkspaceHarness(), {
        coordinator, mounted: true, tabId: 'A', sessionBindingRevision: 1,
        applySnapshot: snapshot => applied.push(snapshot)
      });
      const task = ui[operation]('old-0');
      assert.equal(applied[0], pending);
      if (change === 'tab') ui.tabId = 'B';
      if (change === 'revision') ui.sessionBindingRevision++;
      if (change === 'coordinator') ui.coordinator = {};
      if (change === 'unmount') ui.mounted = false;
      result.resolve(finished);
      await task;
      assert.equal(applied.length, change === 'none' ? 2 : 1);
      if (change === 'none') assert.equal(applied[1], finished);
    });
  }
}
