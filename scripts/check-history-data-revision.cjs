#!/usr/bin/env node
'use strict';

// Production methods, synthetic stores only: never opens a browser database.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
function source(relative) {
  const text = fs.readFileSync(path.join(root, relative), 'utf8');
  return ts.createSourceFile(relative + '.ts', text, ts.ScriptTarget.Latest, true);
}
const database = source('data/database/BrowserDatabase.ets');
const repositories = source('data/repositories/BrowserRepositories.ets');
const feature = source('features/history/HistoryFeature.ets');
function declaration(file, name) {
  return file.statements.find(node => node.name?.text === name);
}
function member(file, owner, name) {
  const node = declaration(file, owner).members.find(node => node.name?.text === name);
  assert.ok(node, `${owner}.${name} exists`);
  return node;
}
function extract(file, owner, names, globals = {}) {
  const text = `export class Subject {\n${names.map(name => member(file, owner, name).getText(file)).join('\n')}\n}`;
  const result = ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    reportDiagnostics: true
  });
  assert.equal((result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
  const module = { exports: {} };
  vm.runInNewContext(result.outputText, { module, exports: module.exports, ...globals });
  return module.exports.Subject;
}
const boundaries = {
  upsertHistoryVisit: [{ id: 'synthetic' }, undefined],
  deleteHistoryVisit: ['synthetic', undefined],
  deleteHistoryVisitsByIds: [['synthetic'], undefined],
  deleteHistoryVisitsInRange: [1, 2, undefined],
  deleteHistoryVisitsByHost: ['example.invalid', undefined],
  clearHistoryVisits: [undefined],
  seedHistoryStressFixture: [10],
  applyHuaweiSpaceHistorySyncState: ['synthetic-account', {}],
  prepareHistorySyncEnrollment: ['synthetic-account', 'synthetic-client', 'test', 10],
  applyHistorySyncExchange: ['synthetic-account', 'synthetic-client', {}, true],
  applyHistorySyncBootstrap: ['synthetic-account', 'synthetic-client', {}, true],
  detachHistorySyncRemoteProjection: ['synthetic-account'],
  pruneHistorySyncProjection: ['synthetic-account', 1800000000000],
  detachHistorySyncRemoteProjectionsExcept: ['synthetic-account']
};
const signals = ['historyDataRevision', 'historyMutationPendingCount', 'getHistoryDataRevision',
  'isHistoryMutationPending', 'runHistoryMutation'];
const Database = extract(database, 'BrowserDatabase', [...signals,
  ...Object.keys(boundaries).flatMap(name => [name, name + 'Mutation'])], {
  AiraSyncJankProbe: { mark() {}, endExtra() {} },
  hilog: { error() {} }, DOMAIN: 0, TAG: 'synthetic',
  HISTORY_VISITS_TABLE: 'history_visits', HISTORY_URLS_TABLE: 'history_urls',
  HISTORY_STRESS_VISIT_ID_PREFIX: 'fixture-visit-', HISTORY_STRESS_URL_ID_PREFIX: 'fixture-url-',
  HISTORY_STRESS_INSERT_BATCH_SIZE: 100, HISTORY_SYNC_APPLY_YIELD_BUDGET_MS: Infinity,
  HISTORY_SYNC_RETENTION_MS: 1000, HISTORY_SYNC_RETENTION_FRONTIER_GRANULARITY_MS: 100
});
const Repository = extract(repositories, 'RdbHistoryRepository',
  ['getDataRevision', 'isMutationPending', 'importVisits', 'importVisitsMutation']);
const Feature = extract(feature, 'HistoryFeature', ['getDataRevision', 'isMutationPending']);
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function assertState(db, revision, pending) {
  assert.equal(db.getHistoryDataRevision(), revision);
  assert.equal(db.isHistoryMutationPending(), pending);
}
function syntheticDatabase() {
  const db = new Database();
  db.describeError = error => error.message;
  db.rollbackHistoryTransaction = () => {};
  return db;
}

for (const [name, args] of Object.entries(boundaries)) {
  test(`${name}: entry invalidates before work; zero result and errors invalidate in finally`, async () => {
    const db = syntheticDatabase();
    const gate = deferred();
    db[name + 'Mutation'] = (...actual) => {
      assert.deepEqual(actual, args, 'arguments are forwarded unchanged');
      assertState(db, 1, true);
      return gate.promise;
    };
    const pending = db[name](...args);
    assertState(db, 1, true);
    gate.resolve(0);
    assert.equal(await pending, 0);
    assertState(db, 2, false);
    const error = new Error('synthetic failure');
    db[name + 'Mutation'] = () => { throw error; };
    await assert.rejects(db[name](...args), e => e === error);
    assertState(db, 4, false);
  });
  test(`${name}: actual preparation failure releases pending`, async () => {
    const db = syntheticDatabase();
    db.getStore = async () => { throw new Error('synthetic store failure'); };
    db.findHistoryUrlsByHost = db.getStore;
    await assert.rejects(db[name](...args));
    assertState(db, 2, false);
  });
}

test('overlapping writes stay pending regardless of completion order or rejection', async () => {
  for (const first of [0, 1]) {
    const db = syntheticDatabase();
    const gates = [deferred(), deferred()];
    db.upsertHistoryVisitMutation = () => gates[0].promise;
    db.clearHistoryVisitsMutation = () => gates[1].promise;
    const tasks = [db.upsertHistoryVisit({}), db.clearHistoryVisits()];
    assertState(db, 2, true);
    gates[first].resolve(0);
    await tasks[first];
    assertState(db, 3, true);
    const rejection = assert.rejects(tasks[1 - first], /overlap failure/);
    gates[1 - first].reject(new Error('overlap failure'));
    await rejection;
    assertState(db, 4, false);
  }
});

test('actual upsert transaction rollback and failed rollback both execute revision finally', async () => {
  for (const rollbackThrows of [false, true]) {
    const db = syntheticDatabase();
    const gate = deferred();
    let rollbackCount = 0;
    db.getStore = async () => ({ beginTransaction() {} });
    db.upsertHistoryVisitInStore = () => gate.promise;
    db.rollbackHistoryTransaction = (store, started) => {
      assert.equal(started, true);
      rollbackCount++;
      if (rollbackThrows) throw new Error('rollback failed');
    };
    const task = db.upsertHistoryVisit({}, {});
    assertState(db, 1, true);
    const rejection = assert.rejects(task);
    gate.reject(new Error('write failed'));
    await rejection;
    assert.equal(rollbackCount, 1);
    assertState(db, 2, false);
  }
});

test('bootstrap deletes projection but returns zero; completion still invalidates', async () => {
  const db = syntheticDatabase();
  let removed = 0;
  let committed = false;
  db.getStore = async () => ({ beginTransaction() {}, commit() { committed = true; } });
  db.settleHistorySyncBeforeApply = async () => {};
  db.deleteRemoteHistoryProjectionInStore = async () => { removed = 9; return removed; };
  db.persistHistorySyncClearBefore = async () => {};
  db.applyHistorySyncChangesInStore = async () => 0;
  db.upsertHistorySyncState = async () => { assertState(db, 1, true); };
  assert.equal(await db.applyHistorySyncBootstrap('account', 'client', {
    clearBefore: 0, deleteRanges: [], deletedVisitIds: [], visits: [], hasMore: false, bootstrapHead: 1
  }, true), 0);
  assert.equal(removed, 9);
  assert.equal(committed, true);
  assertState(db, 2, false);
});

test('seed deletes old fixture even at zero insert count; partial SQL failure invalidates', async () => {
  for (const fail of [false, true]) {
    const db = syntheticDatabase();
    let statements = 0;
    db.getStore = async () => ({ executeSql: async () => {
      assertState(db, 1, true);
      statements++;
      if (fail && statements === 2) throw new Error('partial seed');
    } });
    db.countHistoryVisits = async () => 10;
    if (fail) await assert.rejects(db.seedHistoryStressFixture(0), /partial seed/);
    else assert.equal(await db.seedHistoryStressFixture(0), 0);
    assert.equal(statements, 2);
    assertState(db, 2, false);
  }
});

test('Huawei apply includes retention prune within one revision boundary', async () => {
  const db = syntheticDatabase();
  let pruned = false;
  db.getStore = async () => ({ beginTransaction() {}, commit() {} });
  db.readHistoryTombstoneVisitIds = async () => new Set();
  db.readHistoryEventSyncIds = async () => new Set();
  db.persistHistorySyncClearBefore = async () => {};
  db.deleteHistorySyncBeforeInStore = async () => 0;
  db.persistHistorySyncRetentionFrontier = async () => {};
  db.deleteHistoryVisitsBehindRetentionFrontierInStore = async () => {
    assertState(db, 1, true);
    pruned = true;
    return 3;
  };
  assert.equal(await db.applyHuaweiSpaceHistorySyncState('account', {
    visits: [], tombstones: [], deleteRanges: [], clearBefore: 0, retentionFrontier: {}
  }), 3);
  assert.equal(pruned, true);
  assertState(db, 2, false);
});

test('repository/feature delegation and unsupported repository defaults', () => {
  const f = new Feature();
  f.repository = {};
  assert.equal(f.getDataRevision(), -1);
  assert.equal(f.isMutationPending(), false);
  const db = syntheticDatabase();
  const repo = new Repository();
  repo.database = db;
  f.repository = repo;
  assert.equal(f.getDataRevision(), 0);
  const task = db.runHistoryMutation(async () => {
    assert.equal(f.getDataRevision(), 1);
    assert.equal(f.isMutationPending(), true);
  });
  return task.then(() => {
    assert.equal(f.getDataRevision(), 2);
    assert.equal(f.isMutationPending(), false);
  });
});

test('import remains pending between rows and refresh; nested writes and failure settle correctly', async () => {
  for (const fail of [false, true]) {
    const db = syntheticDatabase();
    const repo = new Repository();
    repo.database = db;
    repo.initialize = async () => { assertState(db, 1, true); };
    let added = 0;
    repo.addVisit = async () => {
      assert.equal(repo.isMutationPending(), true);
      await db.runHistoryMutation(async () => { added++; });
      assert.equal(repo.isMutationPending(), true);
      if (fail && added === 2) throw new Error('import failure');
    };
    repo.refresh = async () => { assertState(db, 5, true); };
    const task = repo.importVisits([{}, {}]);
    if (fail) await assert.rejects(task, /import failure/);
    else assert.equal(await task, 2);
    assert.equal(added, 2);
    assertState(db, 6, false);
  }
});

test('actual projection prune early return still finalizes the write boundary', async () => {
  const db = syntheticDatabase();
  let committed = false;
  db.getStore = async () => ({ beginTransaction() {}, commit() { committed = true; } });
  db.pruneExpiredHistorySyncDeletions = async () => {};
  db.hasHistorySyncProjectionVictims = async () => {
    assertState(db, 1, true);
    return false;
  };
  assert.equal(await db.pruneHistorySyncProjection('account', 1800000000000), 0);
  assert.equal(committed, true);
  assertState(db, 2, false);
});

test('revision and pending jointly reject cached snapshots throughout overlapping writes', async () => {
  const db = syntheticDatabase();
  const before = db.getHistoryDataRevision();
  const gate = deferred();
  const task = db.runHistoryMutation(() => gate.promise);
  const during = db.getHistoryDataRevision();
  const reusable = revision => revision >= 0 && !db.isHistoryMutationPending() &&
    db.getHistoryDataRevision() === revision;
  assert.equal(reusable(before), false);
  assert.equal(reusable(during), false, 'same revision during a write is insufficient');
  gate.resolve();
  await task;
  assert.equal(reusable(before), false);
  assert.equal(reusable(during), false, 'a read from inside the write cannot be cached afterward');
  assert.equal(reusable(db.getHistoryDataRevision()), true);
  assertState(new Database(), 0, false);
});

test('source contracts: all write boundaries guarded, no per-row internal increments, optional methods', () => {
  const owner = declaration(database, 'BrowserDatabase');
  const guarded = owner.members.filter(node => node.body?.getText(database).includes('this.runHistoryMutation('));
  assert.deepEqual(guarded.map(node => node.name.text).sort(), Object.keys(boundaries).sort());
  for (const name of Object.keys(boundaries)) {
    const wrapper = member(database, 'BrowserDatabase', name).getText(database);
    assert.match(wrapper, new RegExp(`return this\\.runHistoryMutation\\([\\s\\S]*this\\.${name}Mutation\\(`));
    const inner = member(database, 'BrowserDatabase', name + 'Mutation');
    assert.ok(inner.modifiers.some(modifier => modifier.kind === ts.SyntaxKind.PrivateKeyword));
  }
  const increments = owner.members.filter(node => node.body && /historyDataRevision\s*\+=/.test(node.body.getText(database)));
  assert.deepEqual(increments.map(node => node.name.text), ['runHistoryMutation']);
  for (const name of ['getDataRevision', 'isMutationPending']) {
    assert.ok(member(repositories, 'HistoryRepository', name).questionToken);
  }
  // Existing ArkTS optional-method precedent in the same source file.
  assert.ok(member(repositories, 'BookmarkRepository', 'getDatabase').questionToken);
  assert.match(member(repositories, 'RdbHistoryRepository', 'addVisit').getText(repositories), /this\.database\.upsertHistoryVisit\(/);
  assert.match(member(repositories, 'RdbHistoryRepository', 'importVisits').getText(repositories), /this\.database\.runHistoryMutation\(/);
  console.log(`Covered database boundaries (${Object.keys(boundaries).length}): ${Object.keys(boundaries).join(', ')}`);
});
