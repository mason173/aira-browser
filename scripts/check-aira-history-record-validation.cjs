#!/usr/bin/env node
'use strict';

// Run the production snapshot codec and merge service on synthetic records.
// Count platform URL parsing and whole-state normalization, not host timing.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function fixture(count = 1000, rdb = {}) {
  const modules = new Map();
  let urlParses = 0;
  let stateNormalizations = 0;
  function load(relative) {
    if (modules.has(relative)) return modules.get(relative);
    const filename = path.join(root, relative);
    const module = { exports: {} };
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
    }).outputText;
    vm.runInNewContext(code, { module, exports: module.exports, require(name) {
      if (name === '@kit.ArkData') return { relationalStore: rdb };
      if (name === '@ohos.url') return { default: { URL: {
        parseURL(value) { urlParses++; return new URL(value); }
      } } };
      if (name === '@kit.ArkTS') return { util: { TextEncoder: class {
        static create() { return new this(); }
        encodeInto(value) { return new TextEncoder().encode(value); }
      }, TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) } } };
      if (name === '@kit.CryptoArchitectureKit') return { cryptoFramework: {
        createMd() {
          const hash = crypto.createHash('sha256');
          return { updateSync({ data }) { hash.update(data); }, digestSync() { return { data: hash.digest() }; } };
        }
      } };
      if (name.endsWith('/AiraSyncJankProbe')) return { AiraSyncJankProbe: { markExtra() {}, endExtra() {} } };
      if (!name.startsWith('.')) throw new Error(`Unexpected dependency: ${name}`);
      return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
    } }, { filename });
    modules.set(relative, module.exports);
    return module.exports;
  }
  const { HistorySyncMergeService } = load('services/sync/HistorySyncMergeService.ets');
  const normalize = HistorySyncMergeService.prototype.normalize;
  HistorySyncMergeService.prototype.normalize = function (...args) {
    stateNormalizations++;
    return normalize.apply(this, args);
  };
  const { HuaweiSpaceHistorySnapshotCodec } = load('data/sync/HuaweiSpaceHistorySnapshotCodec.ets');
  const codec = new HuaweiSpaceHistorySnapshotCodec('synthetic-owner', 'phone');
  const merge = new HistorySyncMergeService();
  const now = 1800000000000;
  const state = merge.emptyState();
  state.visits = Array.from({ length: count }, (_, i) => ({
    visitId: `h1:phone:${i}`, clientId: 'phone', nativeVisitId: String(i),
    url: `https://example.invalid/page/${i}?q=%E4%B8%AD`, title: `记录 ${i}`,
    visitedAt: now - i - 100, transition: 'link', referrer: '', deviceName: 'phone', source: 'local'
  }));
  const base = codec.buildProjection(state, codec.decodeRows([], now), now);
  const changed = structuredClone(state);
  changed.visits.push({ ...state.visits[0], visitId: 'h1:phone:new', nativeVisitId: 'new', visitedAt: now + 1 });
  return { codec, merge, now, state, base, changed, load,
    reset() { urlParses = 0; stateNormalizations = 0; },
    counts() { return { urlParses, stateNormalizations }; } };
}

function apply(rows, projection) {
  const result = new Map(rows.map(row => [row.rowId, row]));
  projection.rowIdsToDeleteBeforePublish.forEach(id => result.delete(id));
  projection.rowsToUpsert.forEach(row => result.set(row.rowId, row));
  return [...result.values()];
}

test('lite reuse compares canonical desired bytes without parsing stored visit URLs again', () => {
  const f = fixture();
  f.reset();
  // Deliberately empty hints: every bucket must still be checked against desired records.
  const projection = f.codec.buildProjectionReusingHead(f.changed, f.base.rowsToUpsert, [], f.now + 2);
  const counts = f.counts();
  assert.ok(counts.urlParses <= f.changed.visits.length,
    `duplicate record validation performed ${counts.urlParses} URL parses`);
  assert.equal(counts.stateNormalizations, 1, 'single-record validation must not construct a whole merge state');
  const decoded = f.codec.decodeRows(apply(f.base.rowsToUpsert, projection), f.now + 2);
  assert.equal(JSON.stringify(decoded.state), JSON.stringify(f.merge.merge(f.merge.emptyState(), f.changed, f.now + 2)));
});

test('snapshot bytes retain the pre-optimization format', () => {
  const f = fixture(16);
  const projection = f.codec.buildProjectionReusingHead(f.changed, f.base.rowsToUpsert, [], f.now + 2);
  const hash = crypto.createHash('sha256').update(JSON.stringify(projection)).digest('hex');
  // Captured from the production codec before removing redundant validation.
  assert.equal(hash, '91fff86424f920bd934d7eb145e2ecdb06ee12642f11a9b5d929e1e5e5caed09');
});

test('malformed or noncanonical record contents still fail validation', () => {
  const f = fixture(16);
  const changes = [
    value => { value.data.url = 'HTTPS://EXAMPLE.INVALID/noncanonical'; },
    value => { value.data.url = 'file:///private/data'; },
    value => { value.data.title = 123; },
    value => { value.data.transition = 'unsupported'; },
    value => { value.logicalId = 'h1:phone:wrong'; },
    value => { value.updatedAt++; },
    value => { value.data.extra = 'unexpected'; }
  ];
  for (const change of changes) {
    const rows = structuredClone(f.base.rowsToUpsert);
    const row = rows.find(row => row.recordKind === 'snapshot_chunk');
    const chunk = JSON.parse(row.data);
    change(chunk.records[0]);
    row.data = JSON.stringify(chunk);
    assert.throws(() => f.codec.decodeRows(rows, f.now), /invalid|canonical/);
  }
});

test('normalized local records retain strict transport validation and cooperative output', async () => {
  const f = fixture(16);
  for (const change of [
    value => { value.title = 123; },
    value => { value.transition = 'unsupported'; },
    value => { value.visitedAt = Number.MAX_SAFE_INTEGER + 1; }
  ]) {
    const state = structuredClone(f.changed);
    change(state.visits[0]);
    assert.throws(() => f.codec.buildProjectionReusingHead(state, f.base.rowsToUpsert, [], f.now + 2), /invalid/);
  }
  const mirror = f.codec.decodeRows(f.base.rowsToUpsert, f.now);
  const sync = f.codec.buildProjection(f.changed, mirror, f.now + 2);
  const cooperative = await f.codec.buildProjectionCooperatively(f.changed, mirror,
    { async afterBatchItem() {}, async afterStage() {} }, f.now + 2);
  assert.equal(JSON.stringify(cooperative), JSON.stringify(sync));
});

test('worker merges index deletion records instead of rescanning every deletion for each visit', async () => {
  const f = fixture(1000);
  const state = structuredClone(f.state);
  state.tombstones = Array.from({ length: 800 }, (_, i) => ({ visitId: `deleted:${i}`, deletedAt: f.now }));
  state.tombstones.push({ visitId: state.visits[0].visitId, deletedAt: f.now });
  state.deleteRanges = Array.from({ length: 200 }, (_, i) => ({ rangeId: `range:${i}`,
    url: `https://example.invalid/removed/${i}`, startedAt: 0, endedAt: f.now, seq: i + 1 }));
  state.deleteRanges.push({ rangeId: 'matched', url: state.visits[1].url,
    startedAt: state.visits[1].visitedAt, endedAt: state.visits[1].visitedAt, seq: 999 });
  state.clearBefore = state.visits[990].visitedAt;
  state.retentionFrontier = { cutoffAt: 0, boundaryVisitedAt: state.visits[980].visitedAt,
    boundaryVisitId: state.visits[980].visitId, updatedAt: f.now };
  let deletionReads = 0;
  for (const [method, field] of [['mergeTombstones', 'visitId'], ['mergeDeleteRanges', 'url']]) {
    const original = f.merge[method];
    f.merge[method] = function (...args) {
      const values = original.apply(this, args);
      for (const value of values) {
        const key = value[field];
        Object.defineProperty(value, field, { enumerable: true, get() { deletionReads++; return key; } });
      }
      return values;
    };
  }
  const result = f.merge.merge(state, f.merge.emptyState(), f.now);
  assert.ok(deletionReads < 20 * (state.visits.length + state.tombstones.length + state.deleteRanges.length),
    `merge performed ${deletionReads} deletion-key reads for ${state.visits.length} visits`);
  const expected = await f.merge.mergeCooperatively(state, f.merge.emptyState(),
    { async afterBatchItem() {}, async afterStage() {} }, f.now);
  assert.equal(JSON.stringify(result), JSON.stringify(expected), 'worker and cooperative deletion/retention rules must match');
  assert.ok(!result.visits.some(visit => visit.visitId === state.visits[0].visitId || visit.visitId === state.visits[1].visitId));
});

test('all publication paths reject an unretained 10001-visit snapshot instead of publishing an unreadable Head', async () => {
  const f = fixture(10000);
  const mirror = f.codec.decodeRows(f.base.rowsToUpsert, f.now);
  assert.equal(mirror.state.visits.length, 10000);
  assert.throws(() => f.codec.buildProjectionReusingHead(f.changed, f.base.rowsToUpsert, [], f.now + 2),
    /retention limit/);
  assert.throws(() => f.codec.buildProjection(f.changed, mirror, f.now + 2), /retention limit/);
  await assert.rejects(f.codec.buildProjectionCooperatively(f.changed, mirror,
    { async afterBatchItem() {}, async afterStage() {} }, f.now + 2), /retention limit/);
});

test('recover a previously published oversized Head only after full checksum validation, then republish at the retention limit', async () => {
  const f = fixture(10000);
  const state = f.merge.normalize(f.changed);
  // Reproduce the old writer's physical format independently of the guarded publication entry
  // points. This is synthetic legacy data, not a relaxation of the new writer's retention policy.
  const buckets = f.codec.buildBucketRecords(state);
  const refs = [];
  const rows = [];
  for (let index = 0; index < 64; index++) {
    const built = f.codec.buildBucket(index, 0, 1, f.now + 2, buckets.get(index) || []);
    rows.push(...built.rows); refs.push(built.reference);
  }
  const checksum = crypto.createHash('sha256').update(JSON.stringify(state)).digest('hex');
  rows.push(f.codec.buildHead(0, 1, f.now + 2, refs, state, checksum));
  const mirror = f.codec.decodeRows(rows, f.now + 2);
  assert.equal(mirror.selectedHeads[0].state.visits.length, 10001, 'validate the original complete snapshot before retention');
  assert.equal(mirror.state.visits.length, 10000);
  assert.ok(mirror.state.retentionFrontier.boundaryVisitedAt > 0);
  const merged = f.merge.mergeKeepingPreferredVisits(mirror.state, f.changed, f.now + 2);
  const repaired = f.codec.buildProjection(merged, mirror, f.now + 3);
  const head = repaired.rowsToUpsert.find(row => row.recordKind === 'snapshot_head');
  assert.equal(JSON.parse(head.data).counts.visits, 10000);
  assert.equal(f.codec.decodeRows(apply(rows, repaired), f.now + 3).state.visits.length, 10000);
  const cooperative = await f.codec.decodeRowsCooperatively(rows,
    { async afterBatchItem() {}, async afterStage() {} }, f.now + 2);
  assert.equal(JSON.stringify(cooperative.state), JSON.stringify(mirror.state));
  for (const count of [-1, 100001, 1.5, '10001']) {
    const invalid = structuredClone(rows);
    const h = invalid.find(row => row.recordKind === 'snapshot_head');
    const value = JSON.parse(h.data); value.counts.visits = count; h.data = JSON.stringify(value);
    assert.throws(() => f.codec.decodeRows(invalid, f.now + 2), /visits is invalid/);
  }
  const corrupt = structuredClone(rows);
  const chunk = corrupt.find(row => row.recordKind === 'snapshot_chunk');
  const value = JSON.parse(chunk.data); value.records[0].data.title = 'tampered'; chunk.data = JSON.stringify(value);
  assert.throws(() => f.codec.decodeRows(corrupt, f.now + 2), /incomplete|canonical/);
});

test('canonical-byte reuse rejects damaged payloads, metadata and reference hashes', () => {
  const f = fixture(128);
  const originalChunk = f.base.rowsToUpsert.find(row => row.recordKind === 'snapshot_chunk');
  const bucketIndex = JSON.parse(originalChunk.data).bucketIndex;
  const edits = [
    rows => { rows.find(r => r.rowId === originalChunk.rowId).data += ' '; },
    rows => { rows.find(r => r.rowId === originalChunk.rowId).updatedAt++; },
    rows => {
      const row = rows.find(r => r.rowId === originalChunk.rowId);
      const value = JSON.parse(row.data); value.records[0].data.title = 'tampered'; row.data = JSON.stringify(value);
    },
    rows => {
      const row = rows.find(r => r.recordKind === 'snapshot_head');
      const value = JSON.parse(row.data); value.buckets[bucketIndex].hash = 'a'.repeat(64); row.data = JSON.stringify(value);
    }
  ];
  for (const edit of edits) {
    const rows = structuredClone(f.base.rowsToUpsert);
    edit(rows);
    const projected = f.codec.buildProjectionReusingHead(f.state, rows, [], f.now + 2);
    assert.ok(projected.rowsToUpsert.some(r => r.recordKind === 'snapshot_bucket' &&
      JSON.parse(r.data).bucketIndex === bucketIndex), 'damaged bucket must not be reused');
  }
  const deleted = structuredClone(f.state);
  const removed = deleted.visits.splice(0, 3);
  deleted.tombstones = removed.map(v => ({ visitId: v.visitId, deletedAt: f.now + 1 }));
  const projected = f.codec.buildProjectionReusingHead(deleted, f.base.rowsToUpsert, [], f.now + 2);
  const decoded = f.codec.decodeRows(apply(f.base.rowsToUpsert, projected), f.now + 2);
  assert.equal(decoded.state.visits.length, f.state.visits.length - 3);
  assert.equal(decoded.state.tombstones.length, 3);
});

test('small repeated deletions reuse inactive-slot chunks instead of repacking every affected bucket', () => {
  const f = fixture(10000);
  const first = structuredClone(f.state);
  first.tombstones = first.visits.splice(0, 40).map(v => ({ visitId: v.visitId, deletedAt: f.now + 1 }));
  const firstProjection = f.codec.buildProjectionReusingHead(first, f.base.rowsToUpsert, [], f.now + 2);
  const rows = apply(f.base.rowsToUpsert, firstProjection);
  const second = structuredClone(first);
  second.tombstones.push(...second.visits.splice(0, 40).map(v => ({ visitId: v.visitId, deletedAt: f.now + 3 })));
  const baseline = f.codec.buildProjection(second, f.codec.decodeRows(rows, f.now + 4), f.now + 4);
  const optimized = f.codec.buildProjectionReusingHead(second, rows, [], f.now + 4);
  const before = baseline.rowsToUpsert.length;
  const after = optimized.rowsToUpsert.length;
  console.log(`Deletion amplification: ${before} -> ${after} upsert rows for 40 deletions`);
  assert.ok(after <= before * 0.75, `40 deletions still upload ${after} rows vs ${before} whole-bucket rows`);
  const stagedOnly = { ...optimized, rowsToUpsert: optimized.rowsToUpsert.filter(r => r.recordKind !== 'snapshot_head') };
  const stillPublished = f.codec.decodeRows(apply(rows, stagedOnly), f.now + 4);
  assert.equal(JSON.stringify(stillPublished.state), JSON.stringify(f.merge.merge(f.merge.emptyState(), first, f.now + 4)),
    'staging inactive chunks must not change the published snapshot before Head commit');
  const decoded = f.codec.decodeRows(apply(rows, optimized), f.now + 4);
  assert.equal(JSON.stringify(decoded.state), JSON.stringify(f.merge.merge(f.merge.emptyState(), second, f.now + 4)));
  // An unchanged follow-up reuses the new chunk layout instead of repacking it again.
  const unchanged = f.codec.buildProjectionReusingHead(second, apply(rows, optimized), [], f.now + 5);
  assert.equal(unchanged.rowsToUpsert.length, 1);
});


function databaseFixture(count = 1000, options = {}) {
  const tables = {};
  const stats = { stores: 0, results: 0, opens: [], queries: [] };
  class Predicates {
    constructor(table) { this.table = table; this.filters = []; }
    equalTo(key, value) { this.filters.push(r => r[key] === value); return this; }
    beginsWith(key, value) { this.filters.push(r => r[key].startsWith(value)); return this; }
    orderByAsc() { return this; } orderByDesc() { return this; } limitAs() { return this; }
  }
  const rdb = { RdbPredicates: Predicates, SecurityLevel: { S1: 1 }, getRdbStoreSync(_context, config) {
    assert.equal(stats.stores, 0, 'worker opens databases sequentially');
    stats.stores++; stats.opens.push(config.name);
    const store = {
      close() { assert.equal(stats.results, 0); stats.stores--; },
      querySync(p, columns) { return store.queryWithoutRowCountSync(p, columns); },
      queryWithoutRowCountSync(p, columns) {
        stats.queries.push(p.table);
        const rows = (tables[p.table] || []).filter(r => p.filters.every(f => f(r)));
        stats.results++; let at = -1;
        return { getColumnIndex: name => columns.indexOf(name), goToNextRow: () => ++at < rows.length,
          getString: i => rows[at][columns[i]], getLong: i => rows[at][columns[i]],
          close() {
            stats.results--;
            if (options.lateEdit && p.table === 'history_sync_outbox_v1') {
              tables[p.table].push({ account_uid: 'synthetic-owner', mutation_id: 'late', payload_json: '{}' });
            }
          }
        };
      },
      querySqlWithoutRowCountSync(sql, args) {
        const table = /FROM\s+(\w+)/.exec(sql)[1];
        stats.queries.push(table);
        const [accountUid, likePrefix] = args || [];
        let rows = (tables[table] || []).filter(r => r.accountUid === accountUid);
        if (likePrefix !== undefined) {
          const prefixValue = String(likePrefix).replace(/%$/, '');
          rows = rows.filter(r => r.logicalId.startsWith(prefixValue));
        }
        const columns = ['rowId', 'recordKind', 'logicalId', 'data', 'updatedAt'];
        stats.results++; let at = -1;
        return { getColumnIndex: name => columns.indexOf(name), goToNextRow: () => ++at < rows.length,
          getString: i => rows[at][columns[i]], getLong: i => rows[at][columns[i]],
          close() { stats.results--; }
        };
      }
    };
    return store;
  } };
  const f = fixture(count, rdb);
  const local = structuredClone(f.changed);
  local.visits = local.visits.filter(v => v.visitId !== 'h1:phone:0');
  local.tombstones = [{ visitId: 'h1:phone:0', deletedAt: f.now + 1 }];
  tables.history_sync_canonical_visits_v1 = local.visits.map(v => ({ account_uid: 'synthetic-owner',
    visit_id: v.visitId, payload_json: JSON.stringify(v) }));
  tables.history_sync_canonical_visits_v1.push({ account_uid: 'other', visit_id: 'private', payload_json: 'broken' });
  tables.history_sync_tombstones_v1 = [{ account_uid: 'synthetic-owner', visit_id: 'h1:phone:0', deleted_at: f.now + 1 }];
  tables.history_sync_outbox_v1 = [{ account_uid: 'synthetic-owner', mutation_id: 'captured',
    payload_json: JSON.stringify({ kind: 'delete_visit', visitId: 'h1:phone:0' }) },
    { account_uid: 'other', mutation_id: 'private', payload_json: 'broken' }];
  tables.heads = f.base.rowsToUpsert.filter(r => r.recordKind === 'snapshot_head')
    .map(r => ({ ...r, accountUid: 'synthetic-owner' }));
  tables.blocks = f.base.rowsToUpsert.filter(r => r.recordKind !== 'snapshot_head')
    .map(r => ({ ...r, accountUid: 'synthetic-owner' }));
  tables.blocks.push({ accountUid: 'other', logicalId: 'phone:private', data: 'invalid' },
    { accountUid: 'synthetic-owner', logicalId: 'another-device:private', data: 'invalid' });
  const { HuaweiHistoryReplicaReader } = f.load('data/sync/HuaweiHistoryReplicaReader.ets');
  const { AiraHistoryTaskpoolTransferCodec } = f.load('services/sync/AiraHistoryTaskpoolTransferCodec.ets');
  return { ...f, local, tables, stats, transfer: AiraHistoryTaskpoolTransferCodec,
    // The worker now reads only the local database; the caller packs the replica rows it
    // would send (own account + own device only), exactly like preparePackedReplicaRows(true).
    run: () => {
      const ownRows = tables.heads.concat(tables.blocks.filter(r =>
        r.accountUid === 'synthetic-owner' && r.logicalId.startsWith('phone:')));
      return HuaweiHistoryReplicaReader.plan({}, 'local.db',
        AiraHistoryTaskpoolTransferCodec.encodeRows(ownRows), 'synthetic-owner', 'phone', f.now);
    } };
}

test('database worker produces a valid deletion snapshot, scopes accounts/devices, and captures only pre-read outbox IDs', async () => {
  const f = databaseFixture(1000, { lateEdit: true });
  const result = await f.run();
  assert.equal(result.errorMessage, '');
  assert.deepEqual(Array.from(result.mutationIds), ['captured']);
  assert.equal(f.tables.history_sync_outbox_v1.at(-1).mutation_id, 'late');
  const confirmed = f.codec.decodeRows(apply(f.base.rowsToUpsert, result.projection), f.now + 10).state;
  assert.equal(JSON.stringify(confirmed), JSON.stringify(f.merge.merge(f.merge.emptyState(), f.local, f.now + 10)));
  const reserved = f.transfer.decodeState(result.desiredBuffer);
  assert.equal(JSON.stringify(reserved), JSON.stringify(f.local));
  assert.deepEqual(f.stats.opens, ['local.db']);
  assert.equal(f.stats.stores, 0); assert.equal(f.stats.results, 0);
});

test('database worker fails closed on corrupt canonical data, missing chunks, retention, and range deletion', async () => {
  for (const reason of ['canonical', 'missing-chunk', 'retention', 'range']) {
    const f = databaseFixture(reason === 'retention' ? 10000 : 16);
    if (reason === 'retention') {
      const visit = { ...f.local.visits[0], visitId: 'h1:phone:overflow', nativeVisitId: 'overflow' };
      f.tables.history_sync_canonical_visits_v1.push({ account_uid: 'synthetic-owner',
        visit_id: visit.visitId, payload_json: JSON.stringify(visit) });
    }
    if (reason === 'canonical') f.tables.history_sync_canonical_visits_v1[0].payload_json = '{}';
    if (reason === 'missing-chunk') f.tables.blocks = f.tables.blocks.filter(r => r.recordKind !== 'snapshot_chunk');
    if (reason === 'range') f.tables.history_sync_outbox_v1[0].payload_json = JSON.stringify({ kind: 'delete_range' });
    const result = await f.run();
    assert.ok(result.errorMessage.length > 0, reason);
    assert.equal(result.projection, undefined, reason);
    assert.equal(result.mutationIds.length, 0, 'failed plans never acknowledge pending edits');
    assert.equal(f.stats.stores, 0); assert.equal(f.stats.results, 0);
  }
});
