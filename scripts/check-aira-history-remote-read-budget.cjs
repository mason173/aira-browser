#!/usr/bin/env node
'use strict';

// Drive the production remote write API. Only platform RDB/cloud and worker boundaries are
// substituted; count materialized payload bytes so small writes cannot silently reread everything.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const filename = path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceHistoryRemoteStore.ets');

function scenario({ mismatch = false, rejectConfirmation = false, failCloud = false } = {}) {
  const tableFor = kind => kind === 'snapshot_head' ? 'heads' : kind === 'snapshot_block' ? 'blocks' : 'legacy';
  const row = (id, kind, data) => ({ rowId: id, accountUid: 'owner', recordKind: kind,
    logicalId: id, data, updatedAt: 100 });
  const tables = { heads: [], blocks: Array.from({ length: 3000 }, (_, i) =>
    row(`block-${i}`, 'snapshot_block', 'x'.repeat(10000))), legacy: [] };
  const desired = { visits: [], tombstones: [], deleteRanges: [], clearBefore: 0 };
  const head = row('head', 'snapshot_head', JSON.stringify({ deviceId: 'phone', generation: 2, stateChecksum: 'ok' }));
  tables.heads.push({ ...head, data: JSON.stringify({ deviceId: 'phone', generation: 1, stateChecksum: 'old' }) });
  const projection = { rowsToUpsert: [row('block-1', 'snapshot_block', 'new'), head],
    rowIdsToDeleteBeforePublish: [], legacyRowIdsToDeleteAfterConfirmation: [],
    targetHeadRowId: 'head', targetDeviceId: 'phone', targetGeneration: 2, targetStateChecksum: 'ok' };
  const stats = { bytes: 0, rows: 0, queries: [], cloud: [], confirmations: 0, deletes: 0, open: 0, deferredDecodes: 0 };
  class Predicates {
    constructor(table) { this.table = table; this.filters = []; }
    equalTo(key, value) { this.filters.push(r => r[key] === value); return this; }
    in(key, values) {
      assert.ok(values.length > 0, 'empty IN would become a full query on the platform');
      assert.ok(values.length <= 200, 'lookup must bound SQL parameters');
      this.ids = values;
      this.filters.push(r => values.includes(r[key])); return this;
    }
    beginsWith(key, value) { this.filters.push(r => r[key].startsWith(value)); return this; }
    matches(r) { return this.filters.every(f => f(r)); }
  }
  const store = {
    async queryWithoutRowCount(p, columns) {
      const rows = tables[p.table].filter(r => p.matches(r));
      stats.queries.push({ table: p.table, ids: p.ids, rows: rows.length });
      stats.open++;
      let index = -1;
      return {
        getColumnIndex: name => columns.indexOf(name),
        goToNextRow() { return ++index < rows.length; },
        getString(i) { const v = rows[index][columns[i]]; if (columns[i] === 'data') stats.bytes += v.length; return v; },
        getLong: i => rows[index][columns[i]],
        close() { stats.open--; stats.rows += rows.length; }
      };
    },
    beginTransaction() {}, commit() {}, rollBack() {},
    async insert(table, value) {
      const at = tables[table].findIndex(r => r.rowId === value.rowId && r.accountUid === value.accountUid);
      if (at < 0) tables[table].push({ ...value }); else tables[table][at] = { ...value };
      return 1;
    },
    async delete(p) {
      const before = tables[p.table].length;
      tables[p.table] = tables[p.table].filter(r => !p.matches(r));
      const count = before - tables[p.table].length; stats.deletes += count; return count;
    }
  };
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require(name) {
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: Predicates,
      SyncMode: { SYNC_MODE_TIME_FIRST: 4, SYNC_MODE_CLOUD_FIRST: 6 },
      ConflictResolution: { ON_CONFLICT_REPLACE: 1 } } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, error() {} } };
    if (name.endsWith('/AiraSyncConfigStore')) return { AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME: 'test' };
    if (name.endsWith('/AiraSyncWorkThrottleService')) return { AiraSyncWorkThrottleService: class {
      async afterBatchItem() {} async afterStage() {}
    } };
    if (name.endsWith('/AiraSyncJankProbe')) return { AiraSyncJankProbe: { endExtra() {}, markExtra() {} } };
    if (name.endsWith('/AiraSyncComputeExecutor')) return { AiraSyncComputeExecutor: class {
      async decodeHuaweiHistoryTransferredState() { stats.deferredDecodes++; return desired; }
      async confirmHuaweiHistoryRemoteWrite(_uid, _device, rows) {
        stats.confirmations++;
        assert.ok(rows.some(r => r.rowId === 'block-2999'), 'fallback needs all blocks');
        return { confirmed: desired, projectionConfirmed: !rejectConfirmation,
          desiredStateConfirmed: !rejectConfirmation, localApplyRequired: false };
      }
    } };
    if (name.endsWith('/HuaweiSpaceRdbStoreOwner')) return {
      HUAWEI_SPACE_HISTORY_HEAD_TABLE: 'heads', HUAWEI_SPACE_HISTORY_BLOCK_TABLE: 'blocks',
      HUAWEI_SPACE_HISTORY_TABLE: 'legacy', HuaweiSpaceRdbStoreOwner: { getStore: async () => store }
    };
    if (name.endsWith('/HuaweiSpaceHistorySnapshotCodec')) return { HuaweiSpaceHistorySnapshotCodec: class { needsBlockCloudSync() { return false; } }, huaweiHistoryPhysicalTable: kind =>
      kind === 'snapshot_head' ? 'head' : kind === 'snapshot_block' ? 'block' : 'legacy' };
    if (name.endsWith('/HuaweiSpaceCloudSyncCoordinator')) return { HuaweiSpaceCloudSyncCoordinator: {
      async run(request) {
        stats.cloud.push(request.syncMode);
        if (failCloud) throw new Error('synthetic cloud failure');
        if (mismatch && request.syncMode === 6) tables.heads[0].data = '{}';
      }
    } };
    if (name.endsWith('/AiraHistoryTaskpoolTransferCodec')) return { AiraHistoryTaskpoolTransferCodec: {
      async encodeRowsCooperatively(rows) { return new TextEncoder().encode(JSON.stringify(rows)).buffer; }
    } };
    if (name.endsWith('/AppRuntimeContext')) return {};
    throw new Error(`Unexpected dependency: ${name}`);
  } });
  return { api: new module.exports.HuaweiSpaceHistoryRemoteStore('owner', 'phone', 'test', {}),
    stats, tables, desired, projection, row, tableFor };
}

test('a small prepared write materializes changed rows and Head, not the 30 MB replica twice', async () => {
  const s = scenario();
  const result = await s.api.writePreparedProjection(s.projection, s.desired);
  assert.equal(result.changedRowCount, 2);
  assert.deepEqual(s.stats.cloud, [4, 6]);
  assert.equal(s.stats.confirmations, 0);
  assert.ok(s.stats.bytes < 20000, `small write read ${s.stats.bytes} payload bytes`);
  assert.equal(s.stats.open, 0);
});

test('unchanged/empty projections do not trigger cloud transport or full block queries', async () => {
  for (const empty of [false, true]) {
    const s = scenario();
    s.tables.heads[0] = { ...s.projection.rowsToUpsert[1] };
    s.tables.blocks[1] = { ...s.projection.rowsToUpsert[0] };
    if (empty) s.projection.rowsToUpsert = [];
    const result = await s.api.writePreparedProjection(s.projection, s.desired);
    assert.equal(result.changedRowCount, 0);
    assert.deepEqual(s.stats.cloud, []);
    assert.ok(s.stats.bytes < 1000);
    assert.ok(s.stats.queries.every(q => q.table !== 'blocks' || q.ids !== undefined));
  }
});

test('Head mismatch still loads the full replica for worker confirmation and rejects failure', async () => {
  for (const rejectConfirmation of [false, true]) {
    const s = scenario({ mismatch: true, rejectConfirmation });
    s.tables.blocks.push(s.row('legacy-row', 'snapshot_block', 'legacy'));
    s.projection.legacyRowIdsToDeleteAfterConfirmation = ['legacy-row'];
    if (rejectConfirmation) {
      await assert.rejects(s.api.writePreparedProjection(s.projection, s.desired), /尚未完整确认/);
      assert.equal(s.stats.deletes, 0, 'must not clean up before confirmation');
    } else {
      const result = await s.api.writePreparedProjection(s.projection, s.desired);
      assert.equal(result.changedRowCount, 3);
      assert.equal(s.stats.deletes, 1);
    }
    assert.ok(s.stats.confirmations > 0);
    assert.ok(s.stats.bytes >= 29000000);
    assert.equal(s.stats.open, 0);
  }
});

test('cloud failure does not confirm or delete legacy rows', async () => {
  const s = scenario({ failCloud: true });
  s.projection.legacyRowIdsToDeleteAfterConfirmation = ['legacy-row'];
  await assert.rejects(s.api.writePreparedProjection(s.projection, s.desired), /synthetic cloud failure/);
  assert.equal(s.stats.confirmations, 0);
  assert.equal(s.stats.deletes, 0);
  assert.equal(s.api.consumeLastHeadChecksum(), '');
});

test('large projections use bounded account-scoped queries and preserve deletion counts', async () => {
  const s = scenario();
  const head = s.projection.rowsToUpsert[1];
  s.projection.rowsToUpsert = Array.from({ length: 501 }, (_, i) => s.row(`block-${i}`, 'snapshot_block', 'new'));
  s.projection.rowsToUpsert.push(head);
  s.tables.blocks.push({ ...s.row('block-1', 'snapshot_block', 'other-owner'), accountUid: 'other' });
  s.projection.rowIdsToDeleteBeforePublish = ['block-2998'];
  const result = await s.api.writePreparedProjection(s.projection, s.desired);
  assert.equal(result.changedRowCount, 503);
  assert.equal(s.stats.deletes, 1);
  assert.ok(s.stats.queries.filter(q => q.table === 'blocks').every(q => q.ids?.length <= 200));
  assert.equal(s.tables.blocks.find(r => r.accountUid === 'other').data, 'other-owner');
});


test('lite planning reads only this device blocks and expands to all devices on full fallback', async () => {
  const s = scenario();
  for (const row of s.tables.blocks) row.logicalId = `other:chunk:${row.rowId}`;
  s.tables.blocks.push({ ...s.row('own', 'snapshot_block', 'ours'), logicalId: 'phone:chunk:0:0:0' });
  s.tables.blocks.push({ ...s.row('wrong-account', 'snapshot_block', 'private'),
    accountUid: 'another', logicalId: 'phone:chunk:0:0:0' });
  assert.equal(await s.api.preparePackedReplicaRows(true), true);
  assert.ok(s.stats.bytes < 2000, `lite read ${s.stats.bytes} bytes from unrelated devices`);
  assert.deepEqual(Array.from(s.api.peekFreshReplicaRows(), row => row.rowId), ['head', 'own']);
  const packed = s.api.takePackedReplicaRows();
  structuredClone(packed, { transfer: [packed] });
  const full = await s.api.repackFreshReplicaRows(true);
  assert.ok(full.byteLength > 30000000, 'full fallback must reacquire other-device data');
  assert.ok(s.api.peekFreshReplicaRows().some(row => row.rowId === 'block-2999'));
  assert.ok(!s.api.peekFreshReplicaRows().some(row => row.rowId === 'wrong-account'));
  assert.equal(s.stats.open, 0);
});


test('deferred confirmation never decodes planned history for matching Head, but still validates mismatches', async () => {
  for (const options of [{}, { mismatch: true }, { mismatch: true, rejectConfirmation: true }, { failCloud: true }]) {
    const s = scenario(options);
    const write = s.api.writePreparedProjectionDeferred(s.projection, new ArrayBuffer(8));
    if (options.rejectConfirmation || options.failCloud) await assert.rejects(write);
    else assert.equal((await write).changedRowCount, 2);
    assert.equal(s.stats.deferredDecodes, options.mismatch ? 1 : 0);
    assert.equal(s.stats.confirmations, options.mismatch ? 1 : 0);
    assert.equal(s.stats.open, 0);
  }
});
