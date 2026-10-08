#!/usr/bin/env node
'use strict';

// Exercise the production runner -> executor -> transfer/normalization path.
// Database/cloud and TaskPool are controlled boundaries; data is synthetic.
// Per-URL work is simulated, so these are uninterrupted-work checks, not device FPS.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function scenario({ bytes = 1024, rejectLite = false, invalidLite = false, dirty = true, databaseWorker = false } = {}) {
  let now = 1000;
  let uninterrupted = 0;
  let longest = 0;
  let yields = 0;
  let urlParses = 0;
  let localReads = 0;
  let repacks = 0;
  let cloudReads = 0;
  let headProbes = 0;
  let hasLocalWork = true;
  let pruned = 0;
  let head = 'same-head';
  let pendingWriteFailure = false;
  const writeFailure = new Error('synthetic cloud commit failure');
  let packedRows;
  const tasks = [];
  const order = [];
  const modules = new Map();
  const state = {
    visits: Array.from({ length: 1000 }, (_, i) => ({ visitId: `h1:phone:${i}`, clientId: 'phone',
      nativeVisitId: String(i), url: `https://example.invalid/${i}`, title: `记录 ${i}`,
      visitedAt: 10000 + i, transition: 'link', referrer: '', deviceName: 'phone', source: 'local' })),
    tombstones: [{ visitId: 'h1:phone:deleted', deletedAt: 9000 }],
    deleteRanges: [{ rangeId: 'range', url: 'https://example.invalid/removed', startedAt: 1, endedAt: 50, seq: 600 }],
    clearBefore: 10,
    retentionFrontier: { cutoffAt: 10, boundaryVisitedAt: 20, boundaryVisitId: 'boundary', updatedAt: 100 }
  };
  const projection = { rowsToUpsert: [{ rowId: 'synthetic-head' }], rowIdsToDeleteBeforePublish: [],
    legacyRowIdsToDeleteAfterConfirmation: [], targetHeadRowId: 'synthetic-head', targetDeviceId: 'phone',
    targetGeneration: 2, targetStateChecksum: 'confirmed' };
  class ControlledDate extends Date { static now() { return now; } }
  class CostedURL extends URL {
    static parseURL(value) { return new CostedURL(value); }
    constructor(value) {
      super(value);
      urlParses++;
      now += 0.5;
      uninterrupted += 0.5;
      longest = Math.max(longest, uninterrupted);
    }
  }
  function load(relative) {
    if (modules.has(relative)) return modules.get(relative);
    const filename = path.join(root, relative);
    const module = { exports: {} };
    modules.set(relative, module.exports);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
    }).outputText;
    vm.runInNewContext(code, {
      module, exports: module.exports, Date: ControlledDate, ArrayBuffer, Uint8Array,
      setTimeout(callback, delay) { now += delay; uninterrupted = 0; yields++; queueMicrotask(callback); },
      require(name) {
        if (name === '@kit.ArkData') return { relationalStore: {} };
        if (name === '@kit.AbilityKit') return { application: { getApplicationContext: () => ({}) } };
        if (name === '@ohos.url') return { default: { URL: CostedURL } };
        if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, error() {} } };
        if (name.endsWith('/AiraSyncJankProbe')) return { AiraSyncJankProbe: {
          markExtra() {}, endExtra() {}, async measure(_name, operation) { return operation(); }
        } };
        if (name.endsWith('/HuaweiSpaceHistorySnapshotCodec')) return { HuaweiSpaceHistorySnapshotCodec: class {
          collectDirtyBucketIndexes() { return dirty ? [1] : undefined; }
        } };
        if (name.endsWith('/HuaweiSpaceHistoryRemoteStore') || name.endsWith('/BrowserDatabase')) return {};
        if (name === '@kit.ArkTS') return {
          util: {
            TextEncoder: { create: () => ({ encodeInto: text => new TextEncoder().encode(text) }) },
            TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) }
          },
          taskpool: {
            Task: class {
              constructor(name, fn, ...args) { this.name = name; this.args = args; }
              setTransferList(buffers) { this.buffers = buffers; }
            },
            Priority: { LOW: 2 },
            async execute(task, priority) {
              assert.equal(priority, 2);
              tasks.push(task.name);
              assert.ok((task.buffers ?? []).every(buffer => buffer.byteLength > 0),
                'fallback must not reuse a detached buffer');
              structuredClone(task.args, { transfer: task.buffers });
              if (task.name.endsWith('lite-database')) {
                assert.equal(task.args.some(v => v?.visits || v?.rowsToUpsert), false,
                  'no local/state objects cross into the worker');
                assert.ok(task.args.filter(v => v instanceof ArrayBuffer).length === 1,
                  'only the packed replica rows cross as an ArrayBuffer');
                assert.ok(task.args.every(v => typeof v === 'string' || typeof v === 'number' || v instanceof ArrayBuffer),
                  'a Context cannot cross into TaskPool, so the worker receives scalars and the row buffer only');
                if (rejectLite) throw new Error('synthetic worker failure');
                return invalidLite ? { errorMessage: 'invalid replica' } : { errorMessage: '', projection,
                  desiredBuffer: new ArrayBuffer(8), mutationIds: ['captured-mutation'] };
              }
              if (task.name.endsWith('initial-merge-packed')) {
                return { errorMessage: '', localApplyRequired: false, remoteWriteRequired: false,
                  mergedBuffer: new ArrayBuffer(0) };
              }
              if (task.name.endsWith('lite-packed')) {
                if (rejectLite) throw new Error('synthetic transfer failure');
                return invalidLite ? { errorMessage: 'synthetic incomplete own head' } : { errorMessage: '', projection };
              }
              return { errorMessage: '', localApplyRequired: false, remoteWriteRequired: true,
                mergedBuffer: new ArrayBuffer(0), projection };
            }
          }
        };
        if (!name.startsWith('.')) throw new Error(`Unexpected dependency: ${name}`);
        return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
      }
    }, { filename });
    return module.exports;
  }
  const database = {
    async prepareHuaweiHistoryWorkerRead() { return 'local.db'; },
    async initialize() {}, async pruneHistorySyncProjection() { return pruned; },
    async prepareHistorySyncEnrollment() { return hasLocalWork ? 1 : 0; },
    async readHuaweiHistoryRemoteHead() { return { checksum: 'same-head', updatedAt: 1000 }; },
    async hasHistorySyncOutbox() { return hasLocalWork; }, async hasHistorySyncTombstonesSince() { return false; },
    async readHuaweiSpaceHistorySyncState() { localReads++; return state; },
    async listHistorySyncOutbox() { return [{ kind: 'upsert', visit: state.visits[0] }]; },
    async clearHistorySyncOutbox() { order.push('clear-outbox'); },
    async deleteHistorySyncOutboxMutations(_uid, ids) {
      assert.deepEqual(Array.from(ids), ['captured-mutation']); order.push('clear-outbox');
    },
    async writeHuaweiHistoryRemoteHeadChecksum() { order.push('save-head'); }
  };
  const remote = {
    async peekHeadChecksum() { headProbes++; return head; },
    async tryReadLocalReplicaMatchingHead() { return undefined; },
    async readCloudBlocksAndDecode() { cloudReads++; return state; },
    requiresMaintenance() { return false; },
    async preparePackedReplicaRows(ownDeviceOnly) { assert.equal(ownDeviceOnly, true); packedRows = new ArrayBuffer(bytes); return true; },
    supportsWorkerReplicaPlan() { return databaseWorker; },
    peekFreshReplicaRows() { return [{ rowId: 'synthetic-row' }]; },
    takePackedReplicaRows() { const rows = packedRows; packedRows = undefined; return rows; },
    async repackFreshReplicaRows(includeOtherDevices) { assert.equal(includeOtherDevices, true); repacks++; packedRows = new ArrayBuffer(bytes); return packedRows; },
    async writePreparedProjection(value, desired) {
      assert.equal(value, projection);
      assert.equal(desired, state);
      if (pendingWriteFailure) {
        pendingWriteFailure = false;
        throw writeFailure;
      }
      order.push('confirm-cloud');
      return { state: desired, changedRowCount: 1, localApplyRequired: false };
    },
    consumeLastHeadChecksum() { return 'confirmed-head'; }
  };
  if (databaseWorker) {
    remote.writePreparedProjectionDeferred = async (value, buffer) => {
      assert.equal(buffer.byteLength, 8); return remote.writePreparedProjection(value, state);
    };
  }
  const { HuaweiSpaceHistorySyncRunner } = load('services/sync/HuaweiSpaceHistorySyncRunner.ets');
  const { HistorySyncMergeService } = load('services/sync/HistorySyncMergeService.ets');
  const runner = new HuaweiSpaceHistorySyncRunner(database, () => remote);
  return { runner, state, tasks, order,
    writeFailure, failNextWrite() { pendingWriteFailure = true; },
    metrics: () => ({ longest, yields, urlParses, localReads, repacks, cloudReads, headProbes }),
    setLocalWork(value) { hasLocalWork = value; }, setHead(value) { head = value; },
    setPruned(value) { pruned = value; },
    normalize: value => new HistorySyncMergeService().normalize(value),
    run: clear => runner.run({ accountUid: 'synthetic-account', clientId: 'phone', deviceName: 'phone' }, clear) };
}

test('one pending visit with a 27.7 MB unchanged replica stays on the lite worker path', async () => {
  const s = scenario({ bytes: 27721091 });
  const result = await s.run(true);
  assert.equal(result.ok, true);
  assert.deepEqual(s.tasks, ['aira-sync-history-replica-lite-packed']);
  assert.equal(s.metrics().localReads, 1, 'size alone must not trigger another full local read');
  assert.equal(s.metrics().repacks, 0, 'size alone must not trigger another replica pack');
});

test('confirmed history finalization does not parse every URL again on the caller thread', async () => {
  for (const plan of ['lite', 'full', 'cloud']) {
    const s = scenario({ dirty: plan !== 'full' });
    if (plan === 'cloud') s.setHead('changed-head');
    await s.run(true);
    assert.equal(s.metrics().urlParses, 0, 'confirmation must not repeat full-history normalization');
    assert.deepEqual(s.order, plan === 'cloud' ? ['clear-outbox', 'save-head'] :
      ['confirm-cloud', 'clear-outbox', 'save-head']);
  }
});

test('actual lite task failure or invalid head still falls back with fresh buffers', async () => {
  for (const options of [{ rejectLite: true }, { invalidLite: true }]) {
    const s = scenario(options);
    assert.equal((await s.run(true)).ok, true);
    assert.deepEqual(s.tasks, ['aira-sync-history-replica-lite-packed', 'aira-sync-history-replica-packed']);
    assert.equal(s.metrics().repacks, 1);
    assert.equal(s.metrics().localReads, 2);
    assert.deepEqual(s.order, ['confirm-cloud', 'clear-outbox', 'save-head']);
  }
});

test('a failed lite cloud commit preserves pending data and never starts a full CPU recomputation', async () => {
  for (const cached of [false, true]) {
    const s = scenario();
    if (cached) await s.run(true);
    const beforeTasks = s.tasks.length;
    const beforeOrder = s.order.slice();
    const before = s.metrics();
    s.failNextWrite();
    await assert.rejects(s.run(true), error => error === s.writeFailure,
      'transport failure must reach the existing sync retry policy');
    assert.deepEqual(s.tasks.slice(beforeTasks), ['aira-sync-history-replica-lite-packed']);
    assert.deepEqual(s.order, beforeOrder, 'do not clear outbox or save a confirmed head after a failed upload');
    assert.equal(s.metrics().repacks, before.repacks, 'network failure does not invalidate the compute plan');
    assert.equal((await s.run(true)).ok, true, 'a later retry can confirm pending data normally');
    assert.deepEqual(s.order.slice(beforeOrder.length), ['confirm-cloud', 'clear-outbox', 'save-head']);
  }
});

test('provider-transition runs retain the outbox after cloud confirmation', async () => {
  const s = scenario();
  assert.equal((await s.run(false)).ok, true);
  assert.deepEqual(s.order, ['confirm-cloud', 'save-head']);
});

test('a later run with no local changes checks the durable head and skips the full merge', async () => {
  const s = scenario();
  await s.run(true);
  s.setLocalWork(false);
  const before = s.metrics();
  const taskCount = s.tasks.length;
  const result = await s.run(true);
  assert.equal(result.ok, true);
  assert.equal(result.uploadedMutationCount, 0);
  assert.equal(s.metrics().headProbes, before.headProbes + 1, 'cached state still needs a fresh remote head');
  assert.equal(s.metrics().localReads, before.localReads, 'unchanged cached run must not rescan history');
  assert.equal(s.tasks.length, taskCount, 'unchanged cached run must not re-merge the entire history');
});

test('a changed remote head reaches merge with or without local edits', async () => {
  for (const hasLocalWork of [false, true]) {
    const s = scenario();
    await s.run(true);
    s.setLocalWork(hasLocalWork);
    s.setHead('another-device-changed');
    await s.run(true);
    assert.equal(s.metrics().cloudReads, 1, 'cache must not hide other-device updates');
    assert.equal(s.tasks.at(-1), 'aira-sync-history-initial-merge-packed');
  }
});

test('retention pruning is local work even when it removes the last pending upsert', async () => {
  const s = scenario({ dirty: false });
  await s.run(true);
  s.setLocalWork(false);
  s.setPruned(1);
  const before = s.metrics();
  const taskCount = s.tasks.length;
  await s.run(true);
  assert.ok(s.metrics().localReads > before.localReads,
    'pruned history must reach planning instead of the cached no-change shortcut');
  assert.equal(s.tasks.length, taskCount + 1);
});


test('unchanged Head local edits read and plan in the worker without materializing/packing the snapshot on the caller', async () => {
  const s = scenario({ databaseWorker: true, bytes: 27721091 });
  await s.run(true);
  assert.equal(s.metrics().localReads, 0, 'UI thread must not read the full local snapshot');
  assert.deepEqual(s.tasks, ['aira-sync-history-replica-lite-database']);
  assert.equal(s.metrics().repacks, 0);
  assert.deepEqual(s.order, ['confirm-cloud', 'clear-outbox', 'save-head']);
});


test('database worker upload failure never falls back or acknowledges, and provider transition retains captured IDs', async () => {
  const s = scenario({ databaseWorker: true });
  s.failNextWrite();
  await assert.rejects(s.run(true), error => error === s.writeFailure);
  assert.deepEqual(s.order, []);
  assert.deepEqual(s.tasks, ['aira-sync-history-replica-lite-database']);
  assert.equal(s.metrics().localReads, 0);
  await s.run(false);
  assert.deepEqual(s.order, ['confirm-cloud', 'save-head']);
});
